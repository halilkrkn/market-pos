@Timeout(Duration(minutes: 15))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:sqlite3/sqlite3.dart' as sq;
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/pepper_manager.dart';
import '../lib/security/token_manager.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  configureSqliteNative();

  late Directory tempRoot;

  setUpAll(() {
    stdout.writeln(
      '[STAGE5-ENV] os=${Platform.operatingSystem} ${Platform.operatingSystemVersion} '
      'dart=${Platform.version.split(' ').first} cpus=${Platform.numberOfProcessors}',
    );
  });

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('mms_test_only_stage5_perf_');
  });

  tearDown(() async {
    for (var attempt = 0; attempt < 6; attempt++) {
      if (!tempRoot.existsSync()) break;
      try {
        tempRoot.deleteSync(recursive: true);
        break;
      } on FileSystemException {
        if (attempt == 5) break;
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    }
  });

  double rssMb() => ProcessInfo.currentRss / (1024 * 1024);
  double maxRssMb() => ProcessInfo.maxRss / (1024 * 1024);

  double percentileMsExact(List<int> sortedMicros, double q) {
    if (sortedMicros.isEmpty) return 0.0;
    final idx = ((sortedMicros.length - 1) * q).round().clamp(0, sortedMicros.length - 1);
    return sortedMicros[idx] / 1000.0;
  }

  Future<Map<String, dynamic>> runScaleBenchmark(int productCount) async {
    final scaleDir = Directory(p.join(tempRoot.path, 'scale_$productCount'))
      ..createSync(recursive: true);
    final hubDbFile = File(p.join(scaleDir.path, 'hub_master.db'));
    final clientDbFile = File(p.join(scaleDir.path, 'client_local.db'));
    final backupDir = Directory(p.join(scaleDir.path, 'backups'))..createSync();
    final safetyDir = Directory(p.join(scaleDir.path, 'safety'))..createSync();
    final pepperFile = File(p.join(scaleDir.path, 'pepper.dpapi'));

    final pepper = PepperManager(pepperFile)..initialize();
    final hubDb = SpikeDatabase(hubDbFile);
    await hubDb.customStatement('SELECT 1;');

    const deviceId = 'PERF-POS-01';
    const rawToken = 'mms_dt_perf_stage5_token';
    final salt = TokenManager.generateSalt();
    await hubDb.into(hubDb.devices).insert(
          DevicesCompanion.insert(
            deviceId: deviceId,
            name: 'Perf Terminal',
            tokenHash: TokenManager.hashToken(
              rawToken: rawToken,
              salt: salt,
              pepper: pepper.pepper,
            ),
            salt: salt,
            isActive: const Value(true),
            isConfirmed: const Value(true),
            role: const Value('OWNER'),
          ),
        );

    final baseTime = DateTime.utc(2026, 11, 24, 10, 0);
    final seedSw = Stopwatch()..start();
    const chunkSize = 1000;
    for (var offset = 0; offset < productCount; offset += chunkSize) {
      final limit = min(offset + chunkSize, productCount);
      await hubDb.batch((b) {
        b.insertAll(
          hubDb.products,
          [
            for (var i = offset; i < limit; i++)
              ProductsCompanion.insert(
                id: 'prod_${i.toString().padLeft(6, '0')}',
                barcode: '869${i.toString().padLeft(10, '0')}',
                name: 'Market Ürün ${i.toString().padLeft(6, '0')}',
                price: 1000 + (i % 500),
                priceVersionId: const Value('pv_perf_1'),
                stock: 500000,
                updatedAt: Value(baseTime),
              ),
          ],
        );
        b.insertAll(
          hubDb.productBarcodes,
          [
            for (var i = offset; i < limit; i++)
              ProductBarcodesCompanion.insert(
                id: 'bc_prim_${i.toString().padLeft(6, '0')}',
                productId: 'prod_${i.toString().padLeft(6, '0')}',
                barcode: '869${i.toString().padLeft(10, '0')}',
                isPrimary: const Value(true),
              ),
          ],
        );
      });
    }
    seedSw.stop();

    final server = SpikeServer(
      db: hubDb,
      dbFile: hubDbFile,
      writeQueue: WriteQueue(),
      backupDirectory: backupDir.path,
      pepperManager: pepper,
      adminSecret: 'perf_adm_sec',
      hubRestoreSafetyKdfIterations: 1000,
    );
    final ioServer = await shelf_io.serve(
      server.handler,
      InternetAddress.loopbackIPv4,
      0,
    );
    final hubUrl = 'http://127.0.0.1:${ioServer.port}';

    var clientDb = ClientDatabase(clientDbFile);
    var clientRepo = ClientStorageRepository(clientDb);
    await clientRepo.initializeDevice(deviceId);
    final transport = HttpSyncTransport();
    final syncService = ClientSyncService(
      repository: clientRepo,
      transport: transport,
      deviceId: deviceId,
      deviceToken: rawToken,
      hubUrl: hubUrl,
      requestTimeout: const Duration(seconds: 60),
    );

    var errorCount = 0;
    var totalOps = 0;

    try {
      // 1. Tam Sync (GET /api/v1/products -> upsertProducts -> sync-ack)
      totalOps++;
      final syncSw = Stopwatch()..start();
      final syncedProducts = await syncService.syncProducts();
      syncSw.stop();
      expect(syncedProducts, equals(productCount));

      // 2. Ürün ekleme (20 yeni ürün UI akışı hız ölçümü)
      final createMicros = <int>[];
      for (var k = 0; k < 20; k++) {
        totalOps++;
        final sw = Stopwatch()..start();
        await clientRepo.createProduct(
          name: 'Yeni Eklenen $k',
          price: 2500,
          barcode: '86999${productCount.toString().padLeft(5, '0')}${k.toString().padLeft(3, '0')}',
          initialStock: 10000,
          deviceId: deviceId,
        );
        sw.stop();
        createMicros.add(sw.elapsedMicroseconds);
      }

      // 3. Listeleme + arama süresi
      totalOps++;
      final listSw = Stopwatch()..start();
      final page = await clientRepo.getProducts(limit: 100, offset: 0);
      listSw.stop();
      expect(page.length, equals(100));

      totalOps++;
      final searchSw = Stopwatch()..start();
      final searched = await clientRepo.getProducts(
        searchQuery: 'Market Ürün ${(productCount ~/ 2).toString().padLeft(6, '0')}',
        limit: 50,
      );
      searchSw.stop();
      expect(searched, isNotEmpty);

      // 4. Barkod arama süresi (200 rastgele + son barkod)
      final barcodeMicros = <int>[];
      final step = max(1, productCount ~/ 200);
      for (var i = 0; i < 200; i++) {
        totalOps++;
        final idx = (i * step) % productCount;
        final bc = '869${idx.toString().padLeft(10, '0')}';
        final sw = Stopwatch()..start();
        final found = await clientRepo.getProductByBarcode(bc);
        sw.stop();
        expect(found, isNotNull);
        barcodeMicros.add(sw.elapsedMicroseconds);
      }
      barcodeMicros.sort();

      // 5. Satış kaydetme süresi (50 ardışık atomik satış)
      final saleMicros = <int>[];
      for (var i = 0; i < 50; i++) {
        totalOps++;
        final targetId = 'prod_${((i * step) % productCount).toString().padLeft(6, '0')}';
        final sw = Stopwatch()..start();
        await clientRepo.createOfflineSale(
          deviceId: deviceId,
          paymentMethod: i.isEven ? 'CASH' : 'CARD',
          items: [CartItemInput.units(targetId, 1)],
        );
        sw.stop();
        saleMicros.add(sw.elapsedMicroseconds);
      }
      saleMicros.sort();

      // 6. Stok güncelleme (receiveStock) süresi (50 işlem)
      final stockMicros = <int>[];
      for (var i = 0; i < 50; i++) {
        totalOps++;
        final targetId = 'prod_${((i * step) % productCount).toString().padLeft(6, '0')}';
        final sw = Stopwatch()..start();
        await clientRepo.receiveStock(
          receiptId: 'rcpt_perf_${productCount}_$i',
          productId: targetId,
          quantityMilli: 5000,
          unitPurchasePrice: 700,
          deviceId: deviceId,
        );
        sw.stop();
        stockMicros.add(sw.elapsedMicroseconds);
      }
      stockMicros.sort();

      // 7. Outbox okuma + işleme ve Hub sync süresi (20 PRODUCT_UPSERT + 50 SALE + 50 STOCK = 120 ops)
      totalOps++;
      final outboxReadSw = Stopwatch()..start();
      final pendingList = await clientRepo.getUnsyncedOutboxOperations(deviceId);
      outboxReadSw.stop();
      expect(pendingList.length, equals(120));

      totalOps++;
      final outboxSyncSw = Stopwatch()..start();
      final push1 = await syncService.syncPendingOutbox(maxBatch: 200);
      outboxSyncSw.stop();
      expect(push1.syncedCount, equals(120));
      expect(push1.permanentFailedCount, equals(0));

      // 8. Backup oluşturma süresi (kdf=1000 çalışma süresi ölçümü + büyük DB I/O)
      final storageProvider = LocalStorageProvider(backupDir);
      totalOps++;
      final backupSw = Stopwatch()..start();
      final backupResult = await DatabaseBackupEngine.createBackup(
        liveDbFile: clientDbFile,
        executeVacuumInto: (snapPath) async {
          await clientDb.customStatement("VACUUM INTO '${snapPath.replaceAll("'", "''")}';");
        },
        deviceId: deviceId,
        tenantId: SpikeServer.defaultTenantId,
        storeId: SpikeServer.defaultStoreId,
        databaseType: DatabaseType.clientLocal,
        schemaVersion: clientDb.schemaVersion,
        appVersion: '1.0.0',
        backupPassword: 'Perf_Test_Password_2026!',
        storageProvider: storageProvider,
        kdfIterations: 1000,
      );
      backupSw.stop();

      // 9. Restore süresi
      totalOps++;
      final restoreSw = Stopwatch()..start();
      await DatabaseBackupEngine.restoreBackup(
        backupId: backupResult.backupId,
        liveDbFile: clientDbFile,
        backupPassword: 'Perf_Test_Password_2026!',
        storageProvider: storageProvider,
        expectedDeviceId: deviceId,
        expectedTenantId: SpikeServer.defaultTenantId,
        expectedStoreId: SpikeServer.defaultStoreId,
        expectedDatabaseType: DatabaseType.clientLocal,
        currentSchemaVersion: clientDb.schemaVersion,
        pauseLiveDb: () async => clientDb.close(),
        resumeLiveDb: () async {
          clientDb = ClientDatabase(clientDbFile);
          clientRepo = ClientStorageRepository(clientDb);
        },
        safetyBackupDir: safetyDir,
        encryptSafetyBackup: false,
      );
      restoreSw.stop();

      createMicros.sort();
      final metrics = <String, dynamic>{
        'product_count': productCount,
        'hub_seed_ms': seedSw.elapsedMilliseconds,
        'full_product_sync_ms': syncSw.elapsedMilliseconds,
        'create_product_p50_ms': percentileMsExact(createMicros, 0.50),
        'create_product_p95_ms': percentileMsExact(createMicros, 0.95),
        'list_100_ms': listSw.elapsedMilliseconds,
        'search_query_ms': searchSw.elapsedMilliseconds,
        'barcode_lookup_avg_ms':
            barcodeMicros.reduce((a, b) => a + b) / barcodeMicros.length / 1000.0,
        'barcode_lookup_p95_ms': percentileMsExact(barcodeMicros, 0.95),
        'sale_create_avg_ms':
            saleMicros.reduce((a, b) => a + b) / saleMicros.length / 1000.0,
        'sale_create_p95_ms': percentileMsExact(saleMicros, 0.95),
        'stock_receipt_avg_ms':
            stockMicros.reduce((a, b) => a + b) / stockMicros.length / 1000.0,
        'stock_receipt_p95_ms': percentileMsExact(stockMicros, 0.95),
        'outbox_read_120_ms': outboxReadSw.elapsedMilliseconds,
        'outbox_sync_120_ms': outboxSyncSw.elapsedMilliseconds,
        'backup_kdf1k_ms': backupSw.elapsedMilliseconds,
        'backup_plain_bytes': backupResult.unencryptedSizeBytes,
        'backup_enc_bytes': backupResult.encryptedSizeBytes,
        'restore_kdf1k_ms': restoreSw.elapsedMilliseconds,
        'rss_mb': double.parse(rssMb().toStringAsFixed(2)),
        'max_rss_mb': double.parse(maxRssMb().toStringAsFixed(2)),
        'total_ops': totalOps,
        'error_count': errorCount,
        'error_rate': errorCount / totalOps,
      };

      // Eğer 50k ürün senkronizasyonunda üretim timeout'ı (10s) veya uzun blokaj varsa yakala
      stdout.writeln('[STAGE5-PERF] ${jsonEncode(metrics)}');
      return metrics;
    } finally {
      transport.close();
      await clientDb.close();
      await ioServer.close(force: true);
      await hubDb.close();
    }
  }

  group('Aşama 5.5 — Performans ve Ölçek Doğrulaması (1k / 10k / 50k)', () {
    test('1. 1.000, 10.000 ve 50.000 ürün ölçeklerinde tüm metrikler ölçülür ve DB kilitlenmez', () async {
      final results = <Map<String, dynamic>>[];
      for (final scale in [1000, 10000, 50000]) {
        final m = await runScaleBenchmark(scale);
        results.add(m);
        // Varsayılan ClientSyncService requestTimeout (10s) içinde bile sağlıklı tamamlanabilme hedefi (< 10000 ms)
        expect(
          m['full_product_sync_ms'] as int,
          lessThan(10000),
          reason: '${m['product_count']} ürün senkronizasyonu 10 sn ClientSyncService timeout sınırını aşmamalıdır (ölçülen: ${m['full_product_sync_ms']} ms)',
        );
        expect(m['error_count'], equals(0));
      }
      expect(results.length, equals(3));
    });

    test('2. Üretim 600.000 PBKDF2-HMAC-SHA256 MMSBAK02 gerçek şifreleme ve çözme süresi ölçülür', () async {
      final f = File(p.join(tempRoot.path, 'prod_kdf_sample.db'));
      final db = sq.sqlite3.open(f.path);
      db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, txt TEXT);');
      db.execute('BEGIN TRANSACTION;');
      final stmt = db.prepare('INSERT INTO t (txt) VALUES (?);');
      for (var i = 0; i < 5000; i++) {
        stmt.execute(['Market MMS Sentetik Satır #$i — 869000100$i']);
      }
      stmt.close();
      db.execute('COMMIT;');
      db.close();

      final outBak = File(p.join(tempRoot.path, 'prod_600k.mmsbak'));
      final outRestored = File(p.join(tempRoot.path, 'prod_restored.db'));
      final manifest = BackupManifest(
        backupId: 'perf_600k',
        deviceId: 'PERF-HUB',
        tenantId: 'tenant-1',
        storeId: 'store-1',
        databaseType: DatabaseType.centralMaster,
        schemaVersion: 4,
        appVersion: '1.0.0',
        timestamp: DateTime.now().toUtc(),
        checksum: await MmsbakV2Crypto.computeFileSha256(f),
        unencryptedSizeBytes: f.lengthSync(),
        encryptedSizeBytes: 0,
        encryptionAlgorithm: MmsbakV2Crypto.algorithmId,
        kdfIterations: MmsbakV2Crypto.defaultPbkdf2Iterations,
      );

      final swEnc = Stopwatch()..start();
      await MmsbakV2Crypto.encryptFile(
        inputFile: f,
        outputFile: outBak,
        password: 'Stage5-Prod-Password-2026!',
        manifest: manifest,
        kdfIterations: MmsbakV2Crypto.defaultPbkdf2Iterations,
      );
      swEnc.stop();

      final swDec = Stopwatch()..start();
      await MmsbakV2Crypto.decryptFile(
        inputFile: outBak,
        outputFile: outRestored,
        password: 'Stage5-Prod-Password-2026!',
      );
      swDec.stop();

      stdout.writeln(
        '[STAGE5-PERF-600K] ${jsonEncode({
          'plain_bytes': f.lengthSync(),
          'enc_bytes': outBak.lengthSync(),
          'encrypt_600k_ms': swEnc.elapsedMilliseconds,
          'decrypt_600k_ms': swDec.elapsedMilliseconds,
          'rss_mb': double.parse(rssMb().toStringAsFixed(2)),
        })}',
      );
      expect(outRestored.lengthSync(), equals(f.lengthSync()));
    });
  });

  group('Aşama 5.5 — Dayanıklılık (Durability) Testleri', () {
    test('3. Büyük Outbox (500 işlem), ağ kesintisi/reconnect, SQLite busy lock, yarım transaction ve kapanma/açılma toparlanır', () async {
      final durDir = Directory(p.join(tempRoot.path, 'durability'))..createSync();
      final hubDbFile = File(p.join(durDir.path, 'hub_master.db'));
      final clientDbFile = File(p.join(durDir.path, 'client_local.db'));
      final pepper = PepperManager(File(p.join(durDir.path, 'pepper.dpapi')))
        ..initialize();

      final hubDb = SpikeDatabase(hubDbFile);
      await hubDb.customStatement('SELECT 1;');
      const devId = 'DUR-POS-01';
      const rawTok = 'mms_dt_dur_tok';
      final salt = TokenManager.generateSalt();
      await hubDb.into(hubDb.devices).insert(
            DevicesCompanion.insert(
              deviceId: devId,
              name: 'Durability Device',
              tokenHash: TokenManager.hashToken(
                rawToken: rawTok,
                salt: salt,
                pepper: pepper.pepper,
              ),
              salt: salt,
              isActive: const Value(true),
              isConfirmed: const Value(true),
              role: const Value('OWNER'),
            ),
          );
      await hubDb.into(hubDb.products).insert(
            ProductsCompanion.insert(
              id: 'prod_dur',
              barcode: '8690005555551',
              name: 'Dayanıklılık Süt',
              price: 1000,
              stock: 1000000, // 1000 adet
            ),
          );

      final server = SpikeServer(
        db: hubDb,
        dbFile: hubDbFile,
        writeQueue: WriteQueue(),
        backupDirectory: p.join(durDir.path, 'backups'),
        pepperManager: pepper,
        adminSecret: 'dur_adm_sec',
      );
      final ioServer = await shelf_io.serve(
        server.handler,
        InternetAddress.loopbackIPv4,
        0,
      );
      final hubUrl = 'http://127.0.0.1:${ioServer.port}';

      var clientDb = ClientDatabase(clientDbFile);
      var clientRepo = ClientStorageRepository(clientDb);
      await clientRepo.initializeDevice(devId);
      final baseTransport = HttpSyncTransport();
      final failingTransport = _InterruptAfterTransport(baseTransport, failAfterPosts: 5);

      try {
        final syncWithCut = ClientSyncService(
          repository: clientRepo,
          transport: failingTransport,
          deviceId: devId,
          deviceToken: rawTok,
          hubUrl: hubUrl,
        );
        expect(await syncWithCut.syncProducts(), equals(1));

        // 3a. 500 işlemlik büyük Outbox kuyruğu üret
        final bulkCreateSw = Stopwatch()..start();
        for (var i = 0; i < 500; i++) {
          await clientRepo.createOfflineSale(
            deviceId: devId,
            paymentMethod: 'CASH',
            items: [CartItemInput.units('prod_dur', 1)],
          );
        }
        bulkCreateSw.stop();
        expect(
          (await clientRepo.getUnsyncedOutboxOperations(devId)).length,
          equals(500),
        );

        // 3b. Senkronizasyon ortasında ağ kesintisi (5. posttan sonra kesilir)
        final cutRes = await syncWithCut.syncPendingOutbox(maxBatch: 200);
        expect(cutRes.syncedCount, equals(5));
        expect(cutRes.retriedCount, equals(1));
        expect(cutRes.permanentFailedCount, equals(0));
        expect((await clientRepo.getUnsyncedOutboxOperations(devId)).length, equals(495));

        // 3c. Bağlantı geri dönünce tüm kalan 495 işlem FIFO ile eksiksiz gider (idempotent)
        final healthySync = ClientSyncService(
          repository: clientRepo,
          transport: baseTransport,
          deviceId: devId,
          deviceToken: rawTok,
          hubUrl: hubUrl,
        );
        final drainSw = Stopwatch()..start();
        var drained = 0;
        final futureAt = DateTime.now().add(const Duration(seconds: 10));
        while (true) {
          final batch = await healthySync.syncPendingOutbox(now: futureAt, maxBatch: 200);
          drained += batch.syncedCount;
          expect(batch.permanentFailedCount, equals(0));
          if (!batch.hasMore) break;
        }
        drainSw.stop();
        expect(drained, equals(495));
        expect((await clientRepo.getUnsyncedOutboxOperations(devId)), isEmpty);

        // Hub satış sayısı tam 500, stok 1000 - 500 = 500 adet (500,000 milli-unit) olmalı
        final hubSalesCount = (await hubDb.select(hubDb.sales).get()).length;
        expect(hubSalesCount, equals(500));
        final hubProd = await (hubDb.select(hubDb.products)
              ..where((t) => t.id.equals('prod_dur')))
            .getSingle();
        expect(hubProd.stock, equals(500000));

        // 3d. Geçici SQLite kilidi (BEGIN IMMEDIATE 350 ms tutulurken eşzamanlı satış busy_timeout=5000 ile tamamlanır)
        final lockerDb = sq.sqlite3.open(clientDbFile.path);
        lockerDb.execute('PRAGMA busy_timeout = 5000;');
        lockerDb.execute('BEGIN IMMEDIATE;');
        final lockTimer = Future<void>.delayed(const Duration(milliseconds: 350), () {
          lockerDb.execute('COMMIT;');
          lockerDb.close();
        });
        final lockedSale = await clientRepo.createOfflineSale(
          deviceId: devId,
          paymentMethod: 'CARD',
          items: [CartItemInput.units('prod_dur', 2)],
        );
        await lockTimer;
        expect(lockedSale.clientSeq, equals(501));

        // 3e. Yarıda kesilen transaction rollback (atomiklik)
        await expectLater(
          clientDb.transaction(() async {
            await clientDb.into(clientDb.localCategories).insert(
                  LocalCategoriesCompanion.insert(
                    id: 'cat_aborted_dur',
                    name: 'Yarım Kategori',
                  ),
                );
            throw StateError('Simüle güç kesintisi');
          }),
          throwsA(isA<StateError>()),
        );
        final abortedCat = await (clientDb.select(clientDb.localCategories)
              ..where((c) => c.id.equals('cat_aborted_dur')))
            .getSingleOrNull();
        expect(abortedCat, isNull);

        // 3f. Uygulama DB kapanışı & yeniden açılışı kalıcılığı
        await clientDb.close();
        clientDb = ClientDatabase(clientDbFile);
        clientRepo = ClientStorageRepository(clientDb);
        final stateAfterReopen = await clientRepo.getSyncState(devId);
        expect(stateAfterReopen?.currentClientSeq, equals(501));
        expect(
          (await clientRepo.getUnsyncedOutboxOperations(devId)).single.clientSeq,
          equals(501),
        );

        stdout.writeln(
          '[STAGE5-DURABILITY] ${jsonEncode({
            'create_500_sales_ms': bulkCreateSw.elapsedMilliseconds,
            'drain_495_outbox_ms': drainSw.elapsedMilliseconds,
            'hub_sales_verified': hubSalesCount,
            'hub_remaining_stock_milli': hubProd.stock,
          })}',
        );
      } finally {
        baseTransport.close();
        await clientDb.close();
        await ioServer.close(force: true);
        await hubDb.close();
      }
    });
  });
}

class _InterruptAfterTransport implements SyncTransport, PostRestoreSyncTransport {
  final HttpSyncTransport _inner;
  final int failAfterPosts;
  int _postCount = 0;

  _InterruptAfterTransport(this._inner, {required this.failAfterPosts});

  @override
  Future<SyncResponse> postSale({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    _postCount++;
    if (_postCount > failAfterPosts) {
      return const SyncResponse(
        statusCode: 0,
        body: '',
        isNetworkError: true,
        errorMessage: 'Simüle ağ kesintisi (SocketException)',
      );
    }
    return _inner.postSale(
      hubUrl: hubUrl,
      token: token,
      payload: payload,
      timeout: timeout,
    );
  }

  @override
  Future<SyncResponse> postProductUpsert({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) =>
      _inner.postProductUpsert(
        hubUrl: hubUrl,
        token: token,
        payload: payload,
        timeout: timeout,
      );

  @override
  Future<SyncResponse> postStockReceipt({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) =>
      _inner.postStockReceipt(
        hubUrl: hubUrl,
        token: token,
        payload: payload,
        timeout: timeout,
      );

  @override
  Future<SyncResponse> getProducts({
    required String hubUrl,
    required String token,
    Duration timeout = const Duration(seconds: 10),
  }) =>
      _inner.getProducts(hubUrl: hubUrl, token: token, timeout: timeout);

  @override
  Future<SyncResponse> getSales({
    required String hubUrl,
    required String token,
    int cursor = 0,
    int limit = 50,
    Duration timeout = const Duration(seconds: 10),
  }) =>
      _inner.getSales(
        hubUrl: hubUrl,
        token: token,
        cursor: cursor,
        limit: limit,
        timeout: timeout,
      );

  @override
  Future<SyncResponse> postSyncAck({
    required String hubUrl,
    required String token,
    required String syncSessionId,
    Duration timeout = const Duration(seconds: 10),
  }) =>
      _inner.postSyncAck(
        hubUrl: hubUrl,
        token: token,
        syncSessionId: syncSessionId,
        timeout: timeout,
      );

  @override
  Future<SyncResponse> getDeviceState({
    required String hubUrl,
    required String token,
    Duration timeout = const Duration(seconds: 10),
  }) =>
      _inner.getDeviceState(hubUrl: hubUrl, token: token, timeout: timeout);

  @override
  Future<SyncResponse> postSyncReceipts({
    required String hubUrl,
    required String token,
    required String deviceId,
    required List<int> clientSeqs,
    Duration timeout = const Duration(seconds: 10),
  }) =>
      _inner.postSyncReceipts(
        hubUrl: hubUrl,
        token: token,
        deviceId: deviceId,
        clientSeqs: clientSeqs,
        timeout: timeout,
      );

  @override
  void close() => _inner.close();
}
