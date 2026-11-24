import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:mms_client_storage/mms_client_storage.dart';

class _MockProductSyncTransport implements SyncTransport {
  final List<Map<String, dynamic>> recordedSaleCalls = [];
  final List<Map<String, dynamic>> recordedProductUpsertCalls = [];
  final List<String> acknowledgedSyncSessions = [];

  SyncResponse? nextProductUpsertResponse;
  int productUpsertCallCount = 0;

  @override
  Future<SyncResponse> postSale({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    recordedSaleCalls.add({
      'hubUrl': hubUrl,
      'token': token,
      'payload': jsonDecode(payload),
    });
    return SyncResponse(
      statusCode: 201,
      body: jsonEncode({'status': 'COMMITTED'}),
    );
  }

  @override
  Future<SyncResponse> postProductUpsert({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    productUpsertCallCount++;
    final decoded = jsonDecode(payload) as Map<String, dynamic>;
    recordedProductUpsertCalls.add({
      'hubUrl': hubUrl,
      'token': token,
      'payload': decoded,
    });

    if (nextProductUpsertResponse != null) {
      return nextProductUpsertResponse!;
    }

    return SyncResponse(
      statusCode: 200,
      body: jsonEncode({
        'status': 'OK',
        'product_id': decoded['product']?['id'],
      }),
    );
  }

  @override
  Future<SyncResponse> getProducts({
    required String hubUrl,
    required String token,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return SyncResponse(
      statusCode: 200,
      body: jsonEncode({
        'status': 'OK',
        'sync_session_id': 'sync_sess_123',
        'products': [
          {
            'id': 'prod_hub_1',
            'barcode': '8690001',
            'name': 'Hub Ürünü',
            'price': 1500,
            'stock': 50000,
            'stock_unit': 'adet',
            'pricing_unit': 'adet',
            'conversion_factor_numerator': 1,
            'conversion_factor_denominator': 1,
            'vat_rate': 20,
            'is_active': true,
            'barcodes': ['8690001'],
          }
        ],
      }),
    );
  }

  @override
  Future<SyncResponse> postSyncAck({
    required String hubUrl,
    required String token,
    required String syncSessionId,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    acknowledgedSyncSessions.add(syncSessionId);
    return SyncResponse(
      statusCode: 200,
      body: jsonEncode({'status': 'ACKNOWLEDGED'}),
    );
  }

  @override
  Future<SyncResponse> getSales({
    required String hubUrl,
    required String token,
    int cursor = 0,
    int limit = 50,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return SyncResponse(
      statusCode: 200,
      body: jsonEncode({'sales': [], 'next_cursor': cursor, 'has_more': false}),
    );
  }

  @override
  Future<SyncResponse> postStockReceipt({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(statusCode: 200, body: '{"status":"COMMITTED"}');

  @override
  void close() {}
}

void main() {
  late Directory tempDir;
  late File dbFile;
  late ClientDatabase db;
  late ClientStorageRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mms_prod_outbox_test_');
    dbFile = File(p.join(tempDir.path, 'client_test.db'));
    db = ClientDatabase(dbFile);
    repo = ClientStorageRepository(db);
    await repo.initializeDevice('POS-WIN-01');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Ürün Kataloğu Outbox ve Senkronizasyon Testleri', () {
    test('1. createProduct deviceId ile çağrıldığında atomik olarak PRODUCT_UPSERT outbox kaydı üretir', () async {
      final product = await repo.createProduct(
        name: 'Test Bisküvi',
        price: 2500, // 25.00 TL
        barcode: '869000000101',
        initialStock: 10000, // 10 adet
        deviceId: 'POS-WIN-01',
      );

      expect(product.name, equals('Test Bisküvi'));
      expect(product.price, equals(2500));

      // Outbox tablosunu kontrol et
      final outboxOps = await (db.select(db.outboxOperations)
            ..where((o) => o.deviceId.equals('POS-WIN-01')))
          .get();

      expect(outboxOps.length, equals(1));
      final op = outboxOps.first;
      expect(op.operationType, equals('PRODUCT_UPSERT'));
      expect(op.clientSeq, equals(1));
      expect(op.status, equals('PENDING'));

      final payload = jsonDecode(op.payload) as Map<String, dynamic>;
      expect(payload['operation_type'], equals('PRODUCT_UPSERT'));
      expect(payload['client_seq'], equals(1));
      expect(payload['product']['id'], equals(product.id));
      expect(payload['product']['name'], equals('Test Bisküvi'));
      expect(payload['product']['price'], equals(2500));
      expect(payload['product']['barcode'], equals('869000000101'));
      expect(payload['product']['stock'], equals(10000));
    });

    test('2. updateProduct deviceId ile çağrıldığında güncel durum için yeni bir PRODUCT_UPSERT outbox kaydı üretir', () async {
      final product = await repo.createProduct(
        name: 'Fiyat Değişecek Ürün',
        price: 3000,
        barcode: '869000000102',
        deviceId: 'POS-WIN-01',
      );

      final updated = await repo.updateProduct(
        id: product.id,
        name: 'Fiyatı Güncellenmiş Ürün',
        price: 3500,
        deviceId: 'POS-WIN-01',
      );

      expect(updated.price, equals(3500));

      final outboxOps = await (db.select(db.outboxOperations)
            ..where((o) => o.deviceId.equals('POS-WIN-01'))
            ..orderBy([(o) => OrderingTerm.asc(o.clientSeq)]))
          .get();

      expect(outboxOps.length, equals(2));
      expect(outboxOps[0].clientSeq, equals(1));
      expect(outboxOps[1].clientSeq, equals(2));
      expect(outboxOps[1].operationType, equals('PRODUCT_UPSERT'));

      final payload2 = jsonDecode(outboxOps[1].payload) as Map<String, dynamic>;
      expect(payload2['product']['name'], equals('Fiyatı Güncellenmiş Ürün'));
      expect(payload2['product']['price'], equals(3500));
    });

    test('3. reconcileUnsyncedProducts daha önce outbox olmadan oluşturulmuş ürünleri (Test Ürün A) kuyruğa ekler ve idempotenttir', () async {
      // Outbox yazmadan doğrudan ürün ekle (Eski Test Ürün A durumu simülasyonu)
      await db.into(db.localProducts).insert(
            LocalProductsCompanion.insert(
              id: 'prod_legacy_a',
              name: 'Test Ürün A (Eski)',
              price: 5000,
              priceVersionId: const Value('pv_legacy_a'),
              stock: 20000,
              updatedAt: Value(DateTime.now()),
            ),
          );
      await db.into(db.localProductBarcodes).insert(
            LocalProductBarcodesCompanion.insert(
              id: 'bc_legacy_a',
              productId: 'prod_legacy_a',
              barcode: '99910001',
              createdAt: Value(DateTime.now()),
            ),
          );

      // İlk reconciliation: 1 ürün bulunmalı ve kuyruğa eklenmeli
      final count = await repo.reconcileUnsyncedProducts('POS-WIN-01');
      expect(count, equals(1));

      final outboxOps = await (db.select(db.outboxOperations)
            ..where((o) => o.deviceId.equals('POS-WIN-01')))
          .get();
      expect(outboxOps.length, equals(1));
      expect(outboxOps.first.operationType, equals('PRODUCT_UPSERT'));
      final payload = jsonDecode(outboxOps.first.payload) as Map<String, dynamic>;
      expect(payload['product']['id'], equals('prod_legacy_a'));
      expect(payload['product']['barcode'], equals('99910001'));

      // İkinci kez reconciliation çalıştırıldığında mükerrer kayıt üretilmemelidir (Idempotency)
      final countAgain = await repo.reconcileUnsyncedProducts('POS-WIN-01');
      expect(countAgain, equals(0));

      final outboxOpsAfter = await (db.select(db.outboxOperations)
            ..where((o) => o.deviceId.equals('POS-WIN-01')))
          .get();
      expect(outboxOpsAfter.length, equals(1));
    });

    test('4. ClientSyncService syncPendingOutbox PRODUCT_UPSERT operasyonunu postProductUpsert rotasına gönderir ve ACK alır', () async {
      await repo.createProduct(
        name: 'Hub Gönderilecek Ürün',
        price: 1800,
        barcode: '869000000103',
        deviceId: 'POS-WIN-01',
      );

      final transport = _MockProductSyncTransport();
      final syncService = ClientSyncService(
        repository: repo,
        transport: transport,
        deviceId: 'POS-WIN-01',
        deviceToken: 'test_token_123',
        hubUrl: 'http://127.0.0.1:8945',
      );

      final result = await syncService.syncPendingOutbox();
      expect(result.syncedCount, equals(1));
      expect(result.retriedCount, equals(0));
      expect(result.permanentFailedCount, equals(0));

      expect(transport.productUpsertCallCount, equals(1));
      expect(transport.recordedSaleCalls.length, equals(0), reason: 'Ürün işlemi postSale rotasına gitmemelidir');

      final sentPayload = transport.recordedProductUpsertCalls.first['payload'] as Map<String, dynamic>;
      expect(sentPayload['product']['name'], equals('Hub Gönderilecek Ürün'));
      expect(sentPayload['product']['price'], equals(1800));

      // Outbox durumunun SYNCED olduğunu doğrula
      final outboxOps = await (db.select(db.outboxOperations)
            ..where((o) => o.deviceId.equals('POS-WIN-01')))
          .get();
      expect(outboxOps.first.status, equals('SYNCED'));
    });

    test('5. ClientSyncService syncProducts Hub snapshot ürünlerini çeker ve iki aşamalı ACK gönderir', () async {
      final transport = _MockProductSyncTransport();
      final syncService = ClientSyncService(
        repository: repo,
        transport: transport,
        deviceId: 'POS-WIN-01',
        deviceToken: 'test_token_123',
        hubUrl: 'http://127.0.0.1:8945',
      );

      final count = await syncService.syncProducts();
      expect(count, equals(1));
      expect(transport.acknowledgedSyncSessions, contains('sync_sess_123'));

      // Yerel SQLite'ta ürünün mevcut olduğunu doğrula
      final localProd = await repo.getProductById('prod_hub_1');
      expect(localProd, isNotNull);
      expect(localProd!.name, equals('Hub Ürünü'));
      expect(localProd.price, equals(1500));
    });

    test('6. upsertProducts aynı ürün için aynı barkod geldiğinde başarıyla günceller ve hata fırlatmaz', () async {
      await repo.createProduct(
        name: 'İlk Ürün',
        price: 2000,
        barcode: '869000000001',
        deviceId: 'POS-WIN-01',
      );

      final prods = await db.select(db.localProducts).get();
      final prodId = prods.first.id;

      // Ürün Hub'a gönderilmiş (SYNCED) kabul edilir; aksi halde bekleyen PRODUCT_UPSERT
      // yerel ad/fiyat alanlarını Hub güncellemesine karşı korur (Bölüm 3.5).
      await db.update(db.outboxOperations).write(
            const OutboxOperationsCompanion(status: Value('SYNCED')),
          );

      // Aynı ürün için upsertProducts çağrısı (Örn: Hub senkronizasyonu fiyat güncellemesi)
      await repo.upsertProducts(
        [
          LocalProductsCompanion(
            id: Value(prodId),
            name: const Value('İlk Ürün Güncellendi'),
            price: const Value(2500),
            stock: const Value(10000),
          ),
        ],
        barcodes: [
          LocalProductBarcodesCompanion(
            id: Value('bc_$prodId'),
            productId: Value(prodId),
            barcode: const Value('869000000001'),
            isPrimary: const Value(true),
            isActive: const Value(true),
          ),
        ],
      );

      final updated = await repo.getProductById(prodId);
      expect(updated, isNotNull);
      expect(updated!.name, equals('İlk Ürün Güncellendi'));
      expect(updated.price, equals(2500));

      final bc = await repo.getProductByBarcode('869000000001');
      expect(bc, isNotNull);
      expect(bc!.id, equals(prodId));
    });

    test('7. upsertProducts farklı bir ürün var olan bir barkodu almaya çalıştığında StateError fırlatır ve atomik rollback yapar', () async {
      // 1. Orijinal ürünü oluştur (Örn: prod_sut_1l -> 869000000001)
      final sut = await repo.createProduct(
        name: 'Tam Yağlı Süt 1L',
        price: 3500,
        barcode: '869000000001',
        deviceId: 'POS-WIN-01',
      );

      // 2. Kötü niyetli veya hatalı bir sync payload (prod_cola, 869000000001 barkodunu sahiplenmeye çalışıyor)
      expect(
        () => repo.upsertProducts(
          [
            const LocalProductsCompanion(
              id: Value('prod_cola_intruder'),
              name: Value('Kutu Kola İstilacı'),
              price: Value(4000),
              stock: Value(10000),
            ),
          ],
          barcodes: [
            const LocalProductBarcodesCompanion(
              id: Value('bc_cola_intruder'),
              productId: Value('prod_cola_intruder'),
              barcode: Value('869000000001'), // ÇAKIŞAN BARKOD
              isPrimary: Value(true),
              isActive: Value(true),
            ),
          ],
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Barkod çakışması: "869000000001" barkodu zaten mevcut başka bir ürüne'),
        )),
      );

      // 3. Atomik rollback doğrulaması: prod_cola_intruder yerel veritabanına HİÇ YAZILMAMIŞ olmalı
      final intruder = await repo.getProductById('prod_cola_intruder');
      expect(intruder, isNull, reason: 'Transaction rollback ile istilacı ürün kaydedilmemelidir');

      // 4. Orijinal barkod sahipliği korunmalı (prod_sut_1l hala 869000000001 barkoduna sahip)
      final sutByBarcode = await repo.getProductByBarcode('869000000001');
      expect(sutByBarcode, isNotNull);
      expect(sutByBarcode!.id, equals(sut.id));
      expect(sutByBarcode.name, equals('Tam Yağlı Süt 1L'));
    });

    test('8. upsertProducts gelen liste içinde (intra-batch) iki farklı ürün aynı barkodu paylaştığında StateError fırlatır ve rollback yapar', () async {
      expect(
        () => repo.upsertProducts(
          [
            const LocalProductsCompanion(
              id: Value('prod_batch_1'),
              name: Value('Batch Ürünü 1'),
              price: Value(1000),
              stock: Value(10000),
            ),
            const LocalProductsCompanion(
              id: Value('prod_batch_2'),
              name: Value('Batch Ürünü 2'),
              price: Value(2000),
              stock: Value(10000),
            ),
          ],
          barcodes: [
            const LocalProductBarcodesCompanion(
              id: Value('bc_b1'),
              productId: Value('prod_batch_1'),
              barcode: Value('869999999999'),
              isPrimary: Value(true),
              isActive: Value(true),
            ),
            const LocalProductBarcodesCompanion(
              id: Value('bc_b2'),
              productId: Value('prod_batch_2'),
              barcode: Value('869999999999'), // Aynı barkod!
              isPrimary: Value(true),
              isActive: Value(true),
            ),
          ],
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Gelen listede "869999999999" barkodu birden fazla ürüne'),
        )),
      );

      // Rollback sonucu hiçbir ürün kaydedilmemiş olmalı
      expect(await repo.getProductById('prod_batch_1'), isNull);
      expect(await repo.getProductById('prod_batch_2'), isNull);
      expect(await repo.getProductByBarcode('869999999999'), isNull);
    });
  });
}
