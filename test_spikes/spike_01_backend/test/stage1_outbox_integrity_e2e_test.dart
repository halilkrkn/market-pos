@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/pepper_manager.dart';
import '../lib/security/token_manager.dart';

/// Stage 1 (Aşama 1 — Outbox ve Veri Bütünlüğü) Tam Yığın E2E Regresyon Testleri:
/// - AUD-CRIT-04: `PRODUCT_UPSERT` ve `SALE_CREATE` arasında `price_version_id` ve
///   `product_price_histories` tutarlılığı (aynı cihaz çevrimdışı zam + satış,
///   çapraz cihaz eski fiyat sürümüyle çevrimdışı satış, eşzamanlı aynı fiyata güncelleme).
/// - AUD-HIGH-01: `FAILED_PERMANENT` ilk `PRODUCT_UPSERT` yerinde onarımında bekleyen
///   `SALE_CREATE` ve `STOCK_RECEIPT` varken Hub'da çift stok düşümü/artışı olmaması
///   ve onarım sırasında fiyat değişimiyle birlikte satışın korunması.
///
/// Gerçek FFI SQLite (`ClientDatabase` + `SpikeDatabase`) ve gerçek `SpikeServer` kullanır.
void main() {
  late Directory tempDir;
  late File hubDbFile;
  late SpikeDatabase hubDb;
  late PepperManager pepper;
  late SpikeServer server;
  const port = 18997;
  const hubUrl = 'http://127.0.0.1:$port';
  const devA = 'POS-S1-E2E-A';
  const devB = 'POS-S1-E2E-B';
  final tokens = <String, String>{};
  final clientDbs = <String, ClientDatabase>{};
  final repos = <String, ClientStorageRepository>{};
  final syncs = <String, ClientSyncService>{};
  final transports = <HttpSyncTransport>[];

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    configureSqliteNative();
  });

  Future<void> startHub() async {
    hubDb = SpikeDatabase(hubDbFile);
    server = SpikeServer(
      db: hubDb,
      dbFile: hubDbFile,
      writeQueue: WriteQueue(),
      backupDirectory: p.join(tempDir.path, 'backups'),
      pepperManager: pepper,
    );
    await server.start(port: port, enableDiscovery: false);
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mms_stage1_outbox_e2e_');
    hubDbFile = File(p.join(tempDir.path, 'hub_master.db'));
    pepper = PepperManager(File(p.join(tempDir.path, 'pepper.dpapi')))
      ..initialize();

    final seedDb = SpikeDatabase(hubDbFile);
    for (final devId in [devA, devB]) {
      final raw = 'test_only_stage1_token_$devId';
      tokens[devId] = raw;
      final salt = TokenManager.generateSalt();
      await seedDb.into(seedDb.devices).insert(
            DevicesCompanion(
              deviceId: Value(devId),
              name: Value('Stage1 E2E $devId'),
              tokenHash: Value(
                TokenManager.hashToken(
                  rawToken: raw,
                  salt: salt,
                  pepper: pepper.pepper,
                ),
              ),
              salt: Value(salt),
              isActive: const Value(true),
              isConfirmed: const Value(true),
            ),
          );

      final cdb = ClientDatabase(File(p.join(tempDir.path, '$devId.db')));
      final repo = ClientStorageRepository(cdb);
      await repo.initializeDevice(devId);
      final transport = HttpSyncTransport();
      transports.add(transport);
      clientDbs[devId] = cdb;
      repos[devId] = repo;
      syncs[devId] = ClientSyncService(
        repository: repo,
        transport: transport,
        deviceId: devId,
        deviceToken: raw,
        hubUrl: hubUrl,
      );
    }
    await seedDb.close();
    await startHub();
  });

  tearDown(() async {
    for (final t in transports) {
      t.close();
    }
    transports.clear();
    for (final db in clientDbs.values) {
      try {
        await db.close();
      } catch (_) {}
    }
    clientDbs.clear();
    repos.clear();
    syncs.clear();
    try {
      await server.stop();
    } catch (_) {}
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('AUD-CRIT-04: PRODUCT_UPSERT ve SALE_CREATE price_version_id bütünlüğü', () {
    test(
        '1. Aynı cihazda çevrimdışı fiyat güncellemesi + hemen ardından yapılan satış FIFO ile kilitlenmeden senkronize olur',
        () async {
      final prod = await repos[devA]!.createProduct(
        name: 'Tam Yağlı Yoğurt 1kg',
        price: 4500,
        barcode: '8690008810001',
        initialStock: 10000,
        deviceId: devA,
      );

      final initPush = await syncs[devA]!.syncPendingOutbox();
      expect(initPush.syncedCount, equals(1));
      expect(initPush.permanentFailedCount, equals(0));

      // Çevrimdışı zam (45.00 TL -> 55.00 TL) ve hemen ardından 1 adet satış
      final updated = await repos[devA]!.updateProduct(
        id: prod.id,
        price: 5500,
        deviceId: devA,
      );
      final sale = await repos[devA]!.createOfflineSale(
        deviceId: devA,
        paymentMethod: 'CASH',
        items: [CartItemInput.units(prod.id, 1)],
      );
      expect(sale.totalAmount, equals(5500));
      expect(sale.items.single.priceVersionId, equals(updated.priceVersionId));

      final pushRes = await syncs[devA]!.syncPendingOutbox();
      expect(
        pushRes.permanentFailedCount,
        equals(0),
        reason: 'SALE_CREATE 400 ERR_UNRECOGNIZED_PRICE_VERSION almamalı: ${pushRes.lastError}',
      );
      expect(pushRes.syncedCount, equals(2));

      final hubProd = await (hubDb.select(hubDb.products)
            ..where((p) => p.id.equals(prod.id)))
          .getSingle();
      expect(hubProd.price, equals(5500));
      expect(hubProd.priceVersionId, equals(updated.priceVersionId));
      expect(hubProd.stock, equals(9000));

      final hubSales = await hubDb.select(hubDb.sales).get();
      expect(hubSales, hasLength(1));
      expect(hubSales.single.totalAmount, equals(5500));
    });

    test(
        '2. Çapraz cihaz: Cihaz A zam yaptıktan sonra Cihaz B henüz katalog çekmeden eski fiyat sürümüyle yaptığı çevrimdışı satışı gönderebilir',
        () async {
      final prod = await repos[devA]!.createProduct(
        name: 'Tereyağı 500g',
        price: 4500,
        barcode: '8690008810002',
        initialStock: 10000,
        deviceId: devA,
      );
      await syncs[devA]!.syncPendingOutbox();

      // Cihaz B kataloğu çeker ve ACK gönderir (45.00 TL, ilk priceVersionId)
      final pulledCount = await syncs[devB]!.syncProducts();
      expect(pulledCount, equals(1));
      final prodOnB = (await repos[devB]!.getProductById(prod.id))!;
      expect(prodOnB.price, equals(4500));

      // Cihaz A fiyatı 60.00 TL yapar ve Hub'a gönderir
      await repos[devA]!.updateProduct(
        id: prod.id,
        price: 6000,
        deviceId: devA,
      );
      final pushA = await syncs[devA]!.syncPendingOutbox();
      expect(pushA.syncedCount, equals(1));

      // Cihaz B henüz syncProducts() yapmadan eski fiyatla (45.00 TL) çevrimdışı satar
      final saleOnB = await repos[devB]!.createOfflineSale(
        deviceId: devB,
        paymentMethod: 'CARD',
        items: [CartItemInput.units(prod.id, 1)],
      );
      expect(saleOnB.totalAmount, equals(4500));

      // BackgroundSyncCoordinator sırası: önce Outbox gönderimi
      final pushB = await syncs[devB]!.syncPendingOutbox();
      expect(
        pushB.permanentFailedCount,
        equals(0),
        reason: 'Önceki geçerli fiyat sürümüyle yapılan satış kabul edilmeli: ${pushB.lastError}',
      );
      expect(pushB.syncedCount, equals(1));

      final hubSales = await hubDb.select(hubDb.sales).get();
      expect(hubSales, hasLength(1));
      expect(hubSales.single.totalAmount, equals(4500));
      final hubProd = await (hubDb.select(hubDb.products)
            ..where((p) => p.id.equals(prod.id)))
          .getSingle();
      expect(hubProd.stock, equals(9000));
    });

    test(
        '3. İki cihaz çevrimdışı olarak aynı ürüne aynı yeni fiyatı (farklı pv_* kimlikleriyle) verip satış yaptığında ikisi de kabul edilir',
        () async {
      final prod = await repos[devA]!.createProduct(
        name: 'Zeytinyağı 1L',
        price: 4000,
        barcode: '8690008810022',
        initialStock: 10000,
        deviceId: devA,
      );
      await syncs[devA]!.syncPendingOutbox();
      await syncs[devB]!.syncProducts();

      // Her iki cihaz çevrimdışı aynı 5200 kuruş fiyatına günceller ve 1'er adet satar
      await repos[devA]!.updateProduct(id: prod.id, price: 5200, deviceId: devA);
      await repos[devA]!.createOfflineSale(
        deviceId: devA,
        paymentMethod: 'CASH',
        items: [CartItemInput.units(prod.id, 1)],
      );

      await repos[devB]!.updateProduct(id: prod.id, price: 5200, deviceId: devB);
      await repos[devB]!.createOfflineSale(
        deviceId: devB,
        paymentMethod: 'CASH',
        items: [CartItemInput.units(prod.id, 1)],
      );

      final resA = await syncs[devA]!.syncPendingOutbox();
      expect(resA.permanentFailedCount, equals(0));
      expect(resA.syncedCount, equals(2));

      final resB = await syncs[devB]!.syncPendingOutbox();
      expect(
        resB.permanentFailedCount,
        equals(0),
        reason: 'Aynı fiyata farklı pv_* ile geçen ikinci cihazın satışı reddedilmemeli: ${resB.lastError}',
      );
      expect(resB.syncedCount, equals(2));

      final hubProd = await (hubDb.select(hubDb.products)
            ..where((p) => p.id.equals(prod.id)))
          .getSingle();
      expect(hubProd.stock, equals(8000));
    });
  });

  group('AUD-HIGH-01: FAILED_PERMANENT PRODUCT_UPSERT onarımında stok ve fiyat bütünlüğü', () {
    test(
        '4. İlk PRODUCT_UPSERT FAILED_PERMANENT iken yapılan çevrimdışı satış ve mal kabul, barkod onarımı sonrası Hub\'da iki kez uygulanmaz',
        () async {
      // Cihaz B Hub'da '8690009990001' barkodlu ürünü oluşturur
      await repos[devB]!.createProduct(
        name: 'Hub Mevcut Ürün',
        price: 3000,
        barcode: '8690009990001',
        initialStock: 5000,
        deviceId: devB,
      );
      expect((await syncs[devB]!.syncPendingOutbox()).syncedCount, equals(1));

      // Cihaz A henüz katalog çekmeden aynı barkodla yeni ürün açar (başlangıç stoğu: 10 adet = 10000)
      final newProd = await repos[devA]!.createProduct(
        name: 'Çakışan Yeni Ürün',
        price: 4000,
        barcode: '8690009990001',
        initialStock: 10000,
        deviceId: devA,
      );

      // Çevrimdışı 2 adet satış (-2000 -> 8000) ve +5 adet mal kabul (+5000 -> 13000)
      await repos[devA]!.createOfflineSale(
        deviceId: devA,
        paymentMethod: 'CASH',
        items: [CartItemInput.units(newProd.id, 2)],
      );
      await repos[devA]!.receiveStock(
        receiptId: 'rcpt_stage1_high01',
        productId: newProd.id,
        quantityMilli: 5000,
        unitPurchasePrice: 2500,
        deviceId: devA,
      );
      expect((await repos[devA]!.getProductById(newProd.id))!.stock, equals(13000));

      // İlk senkronizasyon: seq=1 barkod çakışması ile FAILED_PERMANENT olur, kuyruk durur
      final firstPush = await syncs[devA]!.syncPendingOutbox();
      expect(firstPush.permanentFailedCount, equals(1));
      expect(firstPush.syncedCount, equals(0));

      final failedBefore = await repos[devA]!.getFailedPermanentOperations(devA);
      expect(failedBefore, hasLength(1));
      final seq1OpId = failedBefore.single.operationId;
      expect(failedBefore.single.clientSeq, equals(1));

      // Kasiyer barkodu düzeltir -> seq=1 yerinde onarılır (operationId ve clientSeq korunur)
      await repos[devA]!.updateProduct(
        id: newProd.id,
        barcode: '8690009990002',
        deviceId: devA,
      );

      final seq1AfterRepair = await (clientDbs[devA]!.select(clientDbs[devA]!.outboxOperations)
            ..where((o) => o.deviceId.equals(devA) & o.clientSeq.equals(1)))
          .getSingle();
      expect(seq1AfterRepair.operationId, equals(seq1OpId));
      expect(seq1AfterRepair.status, equals('PENDING'));

      // İkinci senkronizasyon: seq=1 (PRODUCT_UPSERT), seq=2 (SALE_CREATE), seq=3 (STOCK_RECEIPT)
      final secondPush = await syncs[devA]!.syncPendingOutbox();
      expect(secondPush.permanentFailedCount, equals(0), reason: '${secondPush.lastError}');
      expect(secondPush.syncedCount, equals(3));

      final hubNewProd = await (hubDb.select(hubDb.products)
            ..where((p) => p.id.equals(newProd.id)))
          .getSingle();
      expect(
        hubNewProd.stock,
        equals(13000),
        reason: '10000 - 2000 + 5000 = 13000 olmalı; çift stok düşümü/artışı olmamalı',
      );

      await syncs[devA]!.syncProducts();
      expect((await repos[devA]!.getProductById(newProd.id))!.stock, equals(13000));
    });

    test(
        '5. FAILED_PERMANENT yeni ürün onarılırken aynı anda fiyatı da değiştirilirse aradaki çevrimdışı satış kilitlenmez ve son fiyat korunur',
        () async {
      await repos[devB]!.createProduct(
        name: 'Hub Barkod Sahibi',
        price: 3000,
        barcode: '8690009990011',
        initialStock: 5000,
        deviceId: devB,
      );
      await syncs[devB]!.syncPendingOutbox();

      final newProd = await repos[devA]!.createProduct(
        name: 'Fiyat ve Barkod Onarılacak Ürün',
        price: 4500,
        barcode: '8690009990011',
        initialStock: 10000,
        deviceId: devA,
      );
      await repos[devA]!.createOfflineSale(
        deviceId: devA,
        paymentMethod: 'CASH',
        items: [CartItemInput.units(newProd.id, 1)],
      );

      final failPush = await syncs[devA]!.syncPendingOutbox();
      expect(failPush.permanentFailedCount, equals(1));

      // Barkod düzeltilirken fiyat da 45.00 TL -> 50.00 TL yapılır
      await repos[devA]!.updateProduct(
        id: newProd.id,
        barcode: '8690009990012',
        price: 5000,
        deviceId: devA,
      );

      final okPush = await syncs[devA]!.syncPendingOutbox();
      expect(okPush.permanentFailedCount, equals(0), reason: '${okPush.lastError}');
      expect(okPush.retriedCount, equals(0));
      expect(okPush.hasMore, isFalse);

      final hubNewProd = await (hubDb.select(hubDb.products)
            ..where((p) => p.id.equals(newProd.id)))
          .getSingle();
      expect(hubNewProd.price, equals(5000));
      expect(hubNewProd.stock, equals(9000));

      final hubSales = await hubDb.select(hubDb.sales).get();
      expect(hubSales, hasLength(1));
      expect(hubSales.single.totalAmount, equals(4500));
    });
  });
}
