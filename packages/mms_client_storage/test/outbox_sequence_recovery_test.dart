import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

void main() {
  late Directory tempDir;
  late File dbFile;
  late ClientDatabase db;
  late ClientStorageRepository repo;
  const testDeviceId = 'POS-TEST-SEQ-01';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mms_seq_test_');
    dbFile = File(p.join(tempDir.path, 'client_seq_test.db'));
    db = ClientDatabase(dbFile);
    repo = ClientStorageRepository(db);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('MARKET MMS — Outbox Sequence & Self-Healing Testleri', () {
    test('Senaryo 1: Eksik sync state varken mevcut Outbox kaydından sonraki sequence üretilmesi', () async {
      // client_sync_states tablosunda henüz hiçbir kayıt yok.
      // Ancak outbox_operations tablosunda daha önceden kalma client_seq=5 kaydı var.
      final now = DateTime.now();
      await db.into(db.outboxOperations).insert(
        OutboxOperationsCompanion(
          operationId: const Value('op_legacy_5'),
          deviceId: const Value(testDeviceId),
          clientSeq: const Value(5),
          operationType: const Value('SALE_CREATE'),
          payload: const Value('{}'),
          payloadHash: const Value('dummy_hash_5'),
          occurredAt: Value(now),
          status: const Value('SYNCED'),
          attemptCount: const Value(0),
          createdAt: Value(now),
        ),
      );

      // Yeni sequence tahsis edildiğinde formül: max(0, 5) + 1 = 6 olmalı
      final nextSeq = await repo.allocateNextClientSeq(testDeviceId);
      expect(nextSeq, equals(6));

      // client_sync_states tablosunda da 6 olarak güncellenmiş olmalı
      final state = await repo.getSyncState(testDeviceId);
      expect(state, isNotNull);
      expect(state!.currentClientSeq, equals(6));
    });

    test('Senaryo 2: Geride kalmış sync state\'in onarılması (Self-Healing)', () async {
      final now = DateTime.now();

      // client_sync_states tablosunda currentClientSeq=3 ve lastSyncedSeq=2 var
      await db.into(db.clientSyncStates).insert(
        ClientSyncStatesCompanion(
          deviceId: const Value(testDeviceId),
          currentClientSeq: const Value(3),
          lastSyncedSeq: const Value(2),
          updatedAt: Value(now),
        ),
      );

      // Ancak outbox_operations tablosunda fiilen client_seq=10'a kadar işlem yazılmış
      await db.into(db.outboxOperations).insert(
        OutboxOperationsCompanion(
          operationId: const Value('op_legacy_10'),
          deviceId: const Value(testDeviceId),
          clientSeq: const Value(10),
          operationType: const Value('PRODUCT_UPSERT'),
          payload: const Value('{}'),
          payloadHash: const Value('dummy_hash_10'),
          occurredAt: Value(now),
          status: const Value('SYNCED'),
          attemptCount: const Value(0),
          createdAt: Value(now),
        ),
      );

      // initializeDevice çağrıldığında self-healing tetiklenmeli
      final healedState = await repo.initializeDevice(testDeviceId);
      expect(healedState.currentClientSeq, equals(10));
      expect(healedState.lastSyncedSeq, equals(2)); // lastSyncedSeq korunmalı

      // Ardından gelen sequence tahsisi 11 olmalı
      final nextSeq = await repo.allocateNextClientSeq(testDeviceId);
      expect(nextSeq, equals(11));
    });

    test('Senaryo 3: Ardışık PRODUCT_UPSERT işlemleri', () async {
      await repo.initializeDevice(testDeviceId);

      final p1 = await repo.createProduct(
        name: 'Ürün 1',
        price: 1000,
        barcode: '8690001001',
        deviceId: testDeviceId,
      );
      final p2 = await repo.createProduct(
        name: 'Ürün 2',
        price: 2000,
        barcode: '8690001002',
        deviceId: testDeviceId,
      );
      final p3 = await repo.createProduct(
        name: 'Ürün 3',
        price: 3000,
        barcode: '8690001003',
        deviceId: testDeviceId,
      );

      expect(p1.id, isNotEmpty);
      expect(p2.id, isNotEmpty);
      expect(p3.id, isNotEmpty);

      final outboxOps = await (db.select(db.outboxOperations)
            ..where((o) => o.deviceId.equals(testDeviceId))
            ..orderBy([(o) => OrderingTerm.asc(o.clientSeq)]))
          .get();

      expect(outboxOps.length, equals(3));
      expect(outboxOps[0].clientSeq, equals(1));
      expect(outboxOps[0].operationType, equals('PRODUCT_UPSERT'));
      expect(outboxOps[1].clientSeq, equals(2));
      expect(outboxOps[1].operationType, equals('PRODUCT_UPSERT'));
      expect(outboxOps[2].clientSeq, equals(3));
      expect(outboxOps[2].operationType, equals('PRODUCT_UPSERT'));

      final syncState = await repo.getSyncState(testDeviceId);
      expect(syncState!.currentClientSeq, equals(3));
    });

    test('Senaryo 4: PRODUCT_UPSERT ile SALE_CREATE işlemlerinin aynı sequence sayacını kullanması', () async {
      await repo.initializeDevice(testDeviceId);

      // 1. Ürün oluştur (Seq 1)
      final prod = await repo.createProduct(
        name: 'Bisküvi',
        price: 1500,
        barcode: '8690002001',
        initialStock: 50000,
        deviceId: testDeviceId,
      );

      // 2. Satış yap (Seq 2)
      final saleResult = await repo.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [
          CartItemInput(
            productId: prod.id,
            quantity: 2000,
            expectedUnitPrice: 1500,
            expectedPriceVersionId: prod.priceVersionId,
          ),
        ],
      );
      expect(saleResult.clientSeq, equals(2));

      // 3. İkinci bir ürün oluştur (Seq 3)
      await repo.createProduct(
        name: 'Çikolata',
        price: 2500,
        barcode: '8690002002',
        deviceId: testDeviceId,
      );

      final outboxOps = await (db.select(db.outboxOperations)
            ..where((o) => o.deviceId.equals(testDeviceId))
            ..orderBy([(o) => OrderingTerm.asc(o.clientSeq)]))
          .get();

      expect(outboxOps.length, equals(3));
      expect(outboxOps[0].clientSeq, equals(1));
      expect(outboxOps[0].operationType, equals('PRODUCT_UPSERT'));

      expect(outboxOps[1].clientSeq, equals(2));
      expect(outboxOps[1].operationType, equals('SALE_CREATE'));

      expect(outboxOps[2].clientSeq, equals(3));
      expect(outboxOps[2].operationType, equals('PRODUCT_UPSERT'));

      final syncState = await repo.getSyncState(testDeviceId);
      expect(syncState!.currentClientSeq, equals(3));
    });

    test('Senaryo 5: SALE_CANCEL ve SALE_REFUND işlemlerinin aynı sayacı kullanması', () async {
      await repo.initializeDevice(testDeviceId);

      // Ürün oluştur (Seq 1)
      final prod = await repo.createProduct(
        name: 'Deterjan',
        price: 5000,
        barcode: '8690003001',
        initialStock: 100000,
        deviceId: testDeviceId,
      );

      // Satış 1 (Seq 2)
      final sale1 = await repo.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [
          CartItemInput(
            productId: prod.id,
            quantity: 1000,
            expectedUnitPrice: 5000,
            expectedPriceVersionId: prod.priceVersionId,
          ),
        ],
      );

      // Satış 1 İptal Et (Seq 3)
      await repo.cancelSale(
        saleId: sale1.saleId,
        reason: 'Müşteri vazgeçti',
        deviceId: testDeviceId,
      );

      // Satış 2 (Seq 4)
      final sale2 = await repo.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CARD',
        items: [
          CartItemInput(
            productId: prod.id,
            quantity: 2000,
            expectedUnitPrice: 5000,
            expectedPriceVersionId: prod.priceVersionId,
          ),
        ],
      );

      // Satış 2 İade Et (Seq 5)
      final saleItems = await (db.select(db.localSaleItems)..where((i) => i.saleId.equals(sale2.saleId))).get();
      await repo.refundSale(
        saleId: sale2.saleId,
        items: [
          RefundItemInput(saleItemId: saleItems.first.id, quantity: 1000),
        ],
        reason: 'Hatalı alım',
        deviceId: testDeviceId,
      );

      final outboxOps = await (db.select(db.outboxOperations)
            ..where((o) => o.deviceId.equals(testDeviceId))
            ..orderBy([(o) => OrderingTerm.asc(o.clientSeq)]))
          .get();

      expect(outboxOps.length, equals(5));
      expect(outboxOps.map((o) => o.clientSeq).toList(), equals([1, 2, 3, 4, 5]));
      expect(outboxOps[0].operationType, equals('PRODUCT_UPSERT'));
      expect(outboxOps[1].operationType, equals('SALE_CREATE'));
      expect(outboxOps[2].operationType, equals('SALE_CANCEL'));
      expect(outboxOps[3].operationType, equals('SALE_CREATE'));
      expect(outboxOps[4].operationType, equals('SALE_REFUND'));
    });

    test('Senaryo 6: Eşzamanlı iki işlemde sequence çakışmaması', () async {
      await repo.initializeDevice(testDeviceId);

      // İki ayrı ürün oluşturmayı aynı anda tetikle
      final results = await Future.wait([
        repo.createProduct(
          name: 'Eşzamanlı Ürün 1',
          price: 1000,
          barcode: '8690006001',
          deviceId: testDeviceId,
        ),
        repo.createProduct(
          name: 'Eşzamanlı Ürün 2',
          price: 2000,
          barcode: '8690006002',
          deviceId: testDeviceId,
        ),
      ]);

      expect(results.length, equals(2));
      final outboxOps = await (db.select(db.outboxOperations)
            ..where((o) => o.deviceId.equals(testDeviceId))
            ..orderBy([(o) => OrderingTerm.asc(o.clientSeq)]))
          .get();

      expect(outboxOps.length, equals(2));
      final seqs = outboxOps.map((o) => o.clientSeq).toList();
      expect(seqs, equals([1, 2]));
    });

    test('Senaryo 7: Outbox INSERT başarısız olduğunda sequence güncellemesinin rollback olması', () async {
      await repo.initializeDevice(testDeviceId);

      // İlk işlemi tamamla (Seq 1)
      await repo.createProduct(
        name: 'Başarılı Ürün',
        price: 1000,
        barcode: '8690007001',
        deviceId: testDeviceId,
      );

      final stateBefore = await repo.getSyncState(testDeviceId);
      expect(stateBefore!.currentClientSeq, equals(1));

      // Hatalı bir işlem: transaction içinde sequence tahsis edip ardından hata fırlatalım
      try {
        await db.transaction(() async {
          await repo.allocateNextClientSeq(testDeviceId);
          throw Exception('Simüle edilmiş Outbox çökmesi');
        });
      } catch (_) {}

      // Transaction rollback olduğu için currentClientSeq 1 olarak kalmalı
      final stateAfter = await repo.getSyncState(testDeviceId);
      expect(stateAfter!.currentClientSeq, equals(1));
    });

    test('Senaryo 8: Ürün kaydı başarısız olduğunda Outbox ve ürün kayıtlarının tutarlı kalması', () async {
      await repo.initializeDevice(testDeviceId);

      // İlk geçerli ürün (Seq 1)
      await repo.createProduct(
        name: 'Benzersiz Barkodlu Ürün',
        price: 2000,
        barcode: '8690008001',
        deviceId: testDeviceId,
      );

      // Aynı barkodla ikinci ürünü eklemeye çalış (BR-PROD-02 ihlali)
      expect(
        () => repo.createProduct(
          name: 'Mükerrer Barkodlu Ürün',
          price: 3000,
          barcode: '8690008001', // Aynı barkod!
          deviceId: testDeviceId,
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Veritabanı tutarlı kalmalı: Sadece 1 ürün ve 1 outbox kaydı olmalı, sequence 1 olmalı
      final products = await db.select(db.localProducts).get();
      expect(products.length, equals(1));

      final outboxOps = await db.select(db.outboxOperations).get();
      expect(outboxOps.length, equals(1));
      expect(outboxOps.first.clientSeq, equals(1));

      final syncState = await repo.getSyncState(testDeviceId);
      expect(syncState!.currentClientSeq, equals(1));
    });

    test('Senaryo 9: Hub\'dan gelen ürünlerin gereksiz yere Outbox\'a eklenmemesi', () async {
      await repo.initializeDevice(testDeviceId);

      // Hub'dan senkronize edilen ürünler
      await repo.upsertProducts([
        LocalProductsCompanion(
          id: const Value('prod_hub_downloaded_1'),
          barcode: const Value('8690009001'),
          name: const Value('Hub İndirilen Ürün 1'),
          price: const Value(2500),
          priceVersionId: const Value('pv_hub_1'),
          stock: const Value(10000),
          stockUnit: const Value('adet'),
          pricingUnit: const Value('adet'),
          conversionFactorNumerator: const Value(1),
          conversionFactorDenominator: const Value(1),
          vatRate: const Value(20),
          isActive: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
        LocalProductsCompanion(
          id: const Value('prod_hub_downloaded_2'),
          barcode: const Value('8690009002'),
          name: const Value('Hub İndirilen Ürün 2'),
          price: const Value(3500),
          priceVersionId: const Value('pv_hub_2'),
          stock: const Value(20000),
          stockUnit: const Value('adet'),
          pricingUnit: const Value('adet'),
          conversionFactorNumerator: const Value(1),
          conversionFactorDenominator: const Value(1),
          vatRate: const Value(20),
          isActive: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      ]);

      // reconcileUnsyncedProducts çağrıldığında bu ürünler outbox'a atılmamalıdır
      final reconciledCount = await repo.reconcileUnsyncedProducts(testDeviceId);
      expect(reconciledCount, equals(0));

      final outboxOps = await (db.select(db.outboxOperations)
            ..where((o) => o.deviceId.equals(testDeviceId)))
          .get();
      expect(outboxOps, isEmpty);
    });
  });
}
