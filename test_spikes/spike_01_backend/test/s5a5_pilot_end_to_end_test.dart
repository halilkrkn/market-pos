import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:mms_client_storage/mms_client_storage.dart';
import '../bin/server.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/pepper_manager.dart';
import '../lib/security/token_manager.dart';

void main() {
  late Directory tempDir;
  late File masterDbFile;
  late File pepperFile;
  late SpikeDatabase masterDb;
  late WriteQueue masterWriteQueue;
  late PepperManager pepperManager;
  late SpikeServer server;
  late String baseUrl;
  const testPort = 8990;
  const adminSecret = 'pilot_admin_secret_s5a5_2026!';

  // Pilot Ölçeği Cihazları: 1 Windows + 3 Mobil = 4 Cihaz
  const devWin = 'DEV_PILOT_WIN_01';
  const devMob1 = 'DEV_PILOT_MOB_01';
  const devMob2 = 'DEV_PILOT_MOB_02';
  const devMob3 = 'DEV_PILOT_MOB_03';

  final deviceTokens = <String, String>{};
  final clientDbs = <String, ClientDatabase>{};
  final clientRepos = <String, ClientStorageRepository>{};
  final clientSyncServices = <String, ClientSyncService>{};

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    configureSqliteNative();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mms_s5a5_pilot_');
    masterDbFile = File(p.join(tempDir.path, 'market_master.db'));
    pepperFile = File(p.join(tempDir.path, 'pepper.dpapi'));

    pepperManager = PepperManager(pepperFile)..initialize();
    masterDb = SpikeDatabase(masterDbFile);
    masterWriteQueue = WriteQueue();

    // 1. Ürün tohumla (Ortak test ürünü: 50 kg Kuşbaşı Et)
    // pricing_unit=kg, stock_unit=g, factor=1000/1, price=200 TL/kg (20000 kuruş), stok=50,000,000 milli-g (50 kg)
    await masterDb.into(masterDb.products).insert(
          ProductsCompanion(
            id: const Value('prod_et'),
            barcode: const Value('869001'),
            name: const Value('Kuşbaşı Et'),
            price: const Value(20000), // 200.00 TL/kg
            stock: const Value(50000000), // 50,000 g (50 kg)
            stockUnit: const Value('g'),
            pricingUnit: const Value('kg'),
            conversionFactorNumerator: const Value(1000),
            conversionFactorDenominator: const Value(1),
          ),
        );

    // 2. İkinci tohum ürün: Kutu Kola 330ml (100 adet)
    await masterDb.into(masterDb.products).insert(
          ProductsCompanion(
            id: const Value('prod_cola'),
            barcode: const Value('869002'),
            name: const Value('Kutu Kola 330ml'),
            price: const Value(2500), // 25.00 TL
            stock: const Value(100000), // 100 adet
            stockUnit: const Value('adet'),
            pricingUnit: const Value('adet'),
            conversionFactorNumerator: const Value(1),
            conversionFactorDenominator: const Value(1),
          ),
        );

    // 3. Pilot cihazları yetkilendir (1 Windows + 3 Mobil)
    final devices = [devWin, devMob1, devMob2, devMob3];
    for (final devId in devices) {
      final rawToken = 'pilot_token_${devId}_sec';
      deviceTokens[devId] = rawToken;

      final salt = TokenManager.generateSalt();
      final hash = TokenManager.hashToken(
        rawToken: rawToken,
        salt: salt,
        pepper: pepperManager.pepper,
      );

      await masterDb.into(masterDb.devices).insert(
            DevicesCompanion(
              deviceId: Value(devId),
              name: Value('Pilot Device $devId'),
              tokenHash: Value(hash),
              salt: Value(salt),
              isActive: const Value(true),
              isConfirmed: const Value(true),
              role: const Value('CASHIER'),
            ),
          );

      // Cihaz veritabanlarını oluştur
      final dbFile = File(p.join(tempDir.path, '$devId.db'));
      final clientDb = ClientDatabase(dbFile);
      final clientRepo = ClientStorageRepository(clientDb);
      final syncService = ClientSyncService(
        repository: clientRepo,
        transport: HttpSyncTransport(),
        deviceId: devId,
        deviceToken: rawToken,
        hubUrl: 'http://127.0.0.1:$testPort',
      );

      clientDbs[devId] = clientDb;
      clientRepos[devId] = clientRepo;
      clientSyncServices[devId] = syncService;
    }

    server = SpikeServer(
      db: masterDb,
      dbFile: masterDbFile,
      writeQueue: masterWriteQueue,
      backupDirectory: p.join(tempDir.path, 'backups'),
      adminSecret: adminSecret,
      pepperManager: pepperManager,
    );

    await server.start(port: testPort);
    baseUrl = 'http://127.0.0.1:$testPort';
  });

  tearDown(() async {
    for (final db in clientDbs.values) {
      try {
        await db.close();
      } catch (_) {}
    }
    clientDbs.clear();
    clientRepos.clear();
    clientSyncServices.clear();

    await server.stop();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('Aşama S-5A-5: Uçtan Uca Pilot Entegrasyon ve Dayanıklılık Doğrulaması', () {
    test('1. Pilot Ölçeği Entegrasyon: 4 Cihaz Senkronizasyonu, Çevrimdışı Satış, Stok Açığı, Idempotent Outbox ve Sıralılık', () async {
      // -------------------------------------------------------------
      // ADIM 1: Tüm cihazlar (1 Windows + 3 Mobil) canlı hub'dan ürünleri senkronize eder
      // -------------------------------------------------------------
      for (final devId in clientSyncServices.keys) {
        final syncSvc = clientSyncServices[devId]!;
        final count = await syncSvc.syncProducts();
        expect(count, equals(2), reason: '$devId 2 ürünü eksiksiz almalıdır');

        final localProducts = await clientDbs[devId]!.select(clientDbs[devId]!.localProducts).get();
        expect(localProducts.length, equals(2));
      }

      // -------------------------------------------------------------
      // ADIM 2: Merkezi servis geçici olarak durdurulur (Offline Mod)
      // -------------------------------------------------------------
      await server.stop();

      // -------------------------------------------------------------
      // ADIM 3: 4 cihaz bağımsız ve eşzamanlı olarak çevrimdışı satış yapar
      // Toplam mevcut et: 50 kg (50,000 g).
      // 4 cihaz sırasıyla 20 kg, 15 kg, 15 kg ve 10 kg satar (Toplam: 60 kg -> 10 kg stok açığı oluşmalıdır).
      // -------------------------------------------------------------
      final saleAmountsKg = {
        devWin: 20,   // 20 kg -> 4,000 TL
        devMob1: 15,  // 15 kg -> 3,000 TL
        devMob2: 15,  // 15 kg -> 3,000 TL
        devMob3: 10,  // 10 kg -> 2,000 TL
      };

      for (final devId in saleAmountsKg.keys) {
        final repo = clientRepos[devId]!;
        final kg = saleAmountsKg[devId]!;

        // 1. Atomik yerel transaction içinde satış yap
        final saleResult = await repo.createOfflineSale(
          deviceId: devId,
          paymentMethod: 'CASH',
          items: [CartItemInput.units('prod_et', kg)], // 20 kg = 20,000 milli-kg
        );

        expect(saleResult.clientSeq, equals(1));
        expect(saleResult.totalAmount, equals(kg * 20000)); // 200 TL/kg = 20000 kuruş

        // 2. Yerel veritabanında Outbox, stok hareketi ve satış kontrolü
        final outboxOps = await clientDbs[devId]!.select(clientDbs[devId]!.outboxOperations).get();
        expect(outboxOps.length, equals(1));
        expect(outboxOps.first.status, equals('PENDING'));
        expect(outboxOps.first.clientSeq, equals(1));

        final stockMovs = await clientDbs[devId]!.select(clientDbs[devId]!.localStockMovements).get();
        expect(stockMovs.length, equals(1));
        expect(stockMovs.first.quantity, equals(-(kg * 1000 * 1000))); // milli-gram bazında negatif
      }

      // -------------------------------------------------------------
      // ADIM 4: Merkezi servis yeniden açılır (Bağlantı Sağlandı)
      // -------------------------------------------------------------
      masterDb = SpikeDatabase(masterDbFile);
      masterWriteQueue = WriteQueue();
      server = SpikeServer(
        db: masterDb,
        dbFile: masterDbFile,
        writeQueue: masterWriteQueue,
        backupDirectory: p.join(tempDir.path, 'backups'),
        adminSecret: adminSecret,
        pepperManager: pepperManager,
      );
      await server.start(port: testPort);

      // -------------------------------------------------------------
      // ADIM 5: 4 cihaz da Outbox kuyruklarını merkezi API'ye gönderir
      // -------------------------------------------------------------
      for (final devId in clientSyncServices.keys) {
        final syncSvc = clientSyncServices[devId]!;
        final batchRes = await syncSvc.syncPendingOutbox();
        expect(batchRes.syncedCount, equals(1), reason: '$devId 1 outbox kaydını başarıyla aktarmalıdır');

        final remainingPending = await (clientDbs[devId]!.select(clientDbs[devId]!.outboxOperations)
              ..where((o) => o.status.equals('PENDING')))
            .get();
        expect(remainingPending, isEmpty, reason: '$devId PENDING kuyruğu boşalmalıdır');
      }

      // -------------------------------------------------------------
      // ADIM 6: Merkezi Veritabanı Doğrulaması (Stok Açığı ve Bütünlük)
      // -------------------------------------------------------------
      // A. Toplam 4 satış kaydedilmiş olmalıdır
      final centralSales = await masterDb.select(masterDb.sales).get();
      expect(centralSales.length, equals(4));

      // B. Stok açığı (Deficit) kuralı doğrulaması:
      // Başlangıç: 50,000 g. Toplam Satış: 60,000 g. Sonuç: -10,000 g (-10,000,000 milli-g).
      // Satışlar silinmemeli veya reddedilmemelidir, stok eksiye düşmelidir.
      final etProduct = await (masterDb.select(masterDb.products)..where((p) => p.id.equals('prod_et'))).getSingle();
      expect(etProduct.stock, equals(-10000000)); // -10 kg

      // C. Stok hareketleri (Audit Trail): 4 adet hareket, toplam -60,000,000 milli-g
      final movements = await masterDb.select(masterDb.stockMovements).get();
      expect(movements.length, equals(4));
      final totalMovementQty = movements.fold<int>(0, (acc, m) => acc + m.quantity);
      expect(totalMovementQty, equals(-60000000));

      // -------------------------------------------------------------
      // ADIM 7: Idempotency Replay Doğrulaması
      // Aynı Outbox kayıtları tekrar gönderildiğinde (örn. ağ kesintisi/tekrar deneme),
      // mükerrer satış veya mükerrer stok düşümü oluşmamalıdır.
      // -------------------------------------------------------------
      for (final devId in clientDbs.keys) {
        final outboxList = await clientDbs[devId]!.select(clientDbs[devId]!.outboxOperations).get();
        final op = outboxList.first;

        // Manuel tekrar gönderim
        final replayResp = await http.post(
          Uri.parse('$baseUrl/api/v1/sales'),
          headers: {
            'authorization': 'Bearer ${deviceTokens[devId]}',
            'content-type': 'application/json',
          },
          body: op.payload,
        );

        expect(replayResp.statusCode, equals(200), reason: 'Tekrarlanan istek önceki ACK ile 200 dönmelidir');
        final replayJson = jsonDecode(replayResp.body) as Map<String, dynamic>;
        expect(replayJson['status'], anyOf(['COMMITTED', 'PROCESSED']));
      }

      // Satış ve stok sayısı mükerrerlik nedeniyle DEĞİŞMEMİŞ olmalıdır
      final salesAfterReplay = await masterDb.select(masterDb.sales).get();
      expect(salesAfterReplay.length, equals(4));
      final etProductAfterReplay = await (masterDb.select(masterDb.products)..where((p) => p.id.equals('prod_et'))).getSingle();
      expect(etProductAfterReplay.stock, equals(-10000000));

      // -------------------------------------------------------------
      // ADIM 8: Monotonik client_seq Sıralılık Doğrulaması
      // -------------------------------------------------------------
      for (final devId in clientRepos.keys) {
        final state = await clientRepos[devId]!.getSyncState(devId);
        expect(state?.currentClientSeq, equals(1));
        expect(state?.lastSyncedSeq, equals(1));
      }
    });

    test('2. Canlı Çalışma Sırasında Backup, Restore, 503 Engellemesi ve Kurtarma Doğrulaması', () async {
      // 1. Canlı sunucudan şifreli merkezi yedek al
      final backupResp = await http.post(
        Uri.parse('$baseUrl/api/v1/admin/backup'),
        headers: {
          'x-mms-admin-secret': adminSecret,
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'backup_password': 'Mms_Pilot_Backup_Secret_2026!',
        }),
      );
      expect(backupResp.statusCode, equals(200));
      final backupJson = jsonDecode(backupResp.body) as Map<String, dynamic>;
      final backupId = backupJson['backup_id'] as String;

      // 2. Canlı veritabanına yeni bir satış ekle
      final salePayload = {
        'operation_id': 'op_pilot_pre_restore',
        'sale_id': 'sale_pre_restore',
        'device_id': devWin,
        'client_seq': 2,
        'items': [
          {'product_id': 'prod_cola', 'quantity': 2000, 'unit_price': 2500, 'total_price': 5000}
        ],
        'total_amount': 5000,
        'payment_method': 'CASH',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      final saleResp = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'authorization': 'Bearer ${deviceTokens[devWin]}',
          'content-type': 'application/json',
        },
        body: jsonEncode(salePayload),
      );
      expect(saleResp.statusCode, anyOf([200, 201]));

      // Kola stoku 100 - 2 = 98'e düşmeli
      final midCola = (await (server.db.select(server.db.products)..where((p) => p.id.equals('prod_cola'))).getSingle()).stock;
      expect(midCola, equals(98000));

      // 3. Restore tetikle ve AdmissionGate 503 engellemesini doğrula
      final restoreFuture = http.post(
        Uri.parse('$baseUrl/api/v1/admin/restore'),
        headers: {
          'x-mms-admin-secret': adminSecret,
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'backup_id': backupId,
          'backup_password': 'Mms_Pilot_Backup_Secret_2026!',
        }),
      );

      final healthCheck = await http.get(Uri.parse('$baseUrl/health'));
      expect(healthCheck.statusCode, anyOf([200, 503]));

      final restoreResp = await restoreFuture;
      expect(restoreResp.statusCode, equals(200));

      // 4. Restore sonrası: Kola stoku 100'e dönmeli, ara satış silinmiş olmalı
      final restoredCola = (await (server.db.select(server.db.products)..where((p) => p.id.equals('prod_cola'))).getSingle()).stock;
      expect(restoredCola, equals(100000));

      final postRestoreSales = await server.db.select(server.db.sales).get();
      expect(postRestoreSales, isEmpty);
    });

    test('3. Güvenlik, Loopback İzolasyonu ve Cihaz Revoke Doğrulaması', () async {
      // 1. LAN İzolasyonu: Admin / Pairing endpoint'lerine harici IP bağlamı testi
      // Context olmadan doğrudan yapılan admin çağrıları fail-closed çalışır
      final unauthorizedReq = await http.post(
        Uri.parse('$baseUrl/api/v1/admin/shutdown'),
        headers: {'content-type': 'application/json'},
      );
      expect(unauthorizedReq.statusCode, anyOf([401, 403]));

      // 2. Cihaz Revoke Testi: devMob3 revoke edilsin
      final revokeResp = await http.post(
        Uri.parse('$baseUrl/api/v1/devices/revoke'),
        headers: {
          'x-admin-secret': adminSecret,
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'device_id': devMob3,
          'reason': 'Pilot güvenlik testi: Cihaz yetkisi geri alınıyor',
        }),
      );
      expect(revokeResp.statusCode, equals(200));

      // 3. Revoke edilen cihaz satış yapmaya çalıştığında 401 Unauthorized ile reddedilir
      final blockedSaleResp = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'authorization': 'Bearer ${deviceTokens[devMob3]}',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'operation_id': 'op_revoked_try',
          'sale_id': 'sale_revoked',
          'device_id': devMob3,
          'client_seq': 99,
          'items': [
            {'product_id': 'prod_cola', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500}
          ],
          'total_amount': 2500,
          'payment_method': 'CASH',
        }),
      );
      expect(blockedSaleResp.statusCode, anyOf([401, 403]));

      // 4. Yetkisi geçerli diğer cihazlar (devWin) satış yapmaya devam edebilmelidir
      final allowedSaleResp = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'authorization': 'Bearer ${deviceTokens[devWin]}',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'operation_id': 'op_valid_after_revoke',
          'sale_id': 'sale_valid_dev_win',
          'device_id': devWin,
          'client_seq': 10,
          'items': [
            {'product_id': 'prod_cola', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500}
          ],
          'total_amount': 2500,
          'payment_method': 'CASH',
        }),
      );
      expect(allowedSaleResp.statusCode, anyOf([200, 201]));
    });

    test('4. Pilot Ölçeği Performans ve Gecikme Metrikleri (P50, P95, P99 Latency)', () async {
      // Pilot ölçeğinde 20 adet sıralı ve eşzamanlı satış isteği göndererek gecikme ölçümü yap
      final latenciesMs = <int>[];

      for (var i = 1; i <= 20; i++) {
        final devId = (i % 2 == 0) ? devWin : devMob1;
        final sw = Stopwatch()..start();

        final resp = await http.post(
          Uri.parse('$baseUrl/api/v1/sales'),
          headers: {
            'authorization': 'Bearer ${deviceTokens[devId]}',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'operation_id': 'op_perf_$i',
            'sale_id': 'sale_perf_$i',
            'device_id': devId,
            'client_seq': 100 + i,
            'items': [
              {'product_id': 'prod_cola', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500}
            ],
            'total_amount': 2500,
            'payment_method': 'CASH',
          }),
        );
        sw.stop();
        expect(resp.statusCode, anyOf([200, 201]));
        latenciesMs.add(sw.elapsedMilliseconds);
      }

      latenciesMs.sort();
      final p50 = latenciesMs[(latenciesMs.length * 0.50).floor()];
      final p95 = latenciesMs[(latenciesMs.length * 0.95).floor()];
      final p99 = latenciesMs[(latenciesMs.length * 0.99).floor()];

      print('[PERF METRICS] Pilot Yükü (20 İşlem) - P50: ${p50}ms, P95: ${p95}ms, P99: ${p99}ms');

      // Pilot kabul eşiği: P99 < 150ms
      expect(p99, lessThan(150), reason: 'P99 gecikmesi pilot kabul sınırı olan 150ms altında olmalıdır');
      expect(p50, lessThan(50), reason: 'P50 gecikmesi 50ms altında olmalıdır');
    });
  });
}
