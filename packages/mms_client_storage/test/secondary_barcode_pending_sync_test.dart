// İkincil barkod iş kuralları (BR-PROD-02/15) ve 9.4 "Outbox bloke iken silinen barkodun
// Hub snapshot'ı ile geri gelmesi" regresyonu. Geçici dizinde sentetik SQLite kullanır.
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _device = 'POS-WIN-BC';

void main() {
  late Directory tempDir;
  late ClientDatabase db;
  late ClientStorageRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mms_test_only_bc_pending_');
    db = ClientDatabase(File(p.join(tempDir.path, 'client_bc.db')));
    repo = ClientStorageRepository(db);
    await repo.initializeDevice(_device);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<void> markAllOutbox(String status, {String? lastError}) async {
    await db.update(db.outboxOperations).write(OutboxOperationsCompanion(
          status: Value(status),
          lastError: Value(lastError),
        ));
  }

  Future<List<String>> lastUpsertBarcodes(String productId) async {
    final ops = await (db.select(db.outboxOperations)
          ..where((o) => o.operationType.equals('PRODUCT_UPSERT'))
          ..orderBy([(o) => OrderingTerm.desc(o.clientSeq)]))
        .get();
    for (final op in ops) {
      final prod = (jsonDecode(op.payload) as Map)['product'] as Map;
      if (prod['id'] == productId) return List<String>.from(prod['barcodes'] as List);
    }
    return const [];
  }

  /// Hub katalog snapshot'ını uygular (ClientSyncService ile aynı çağrı biçimi).
  Future<void> applyHubSnapshot(LocalProduct product, {required String primary, required List<String> barcodes}) async {
    await repo.upsertProducts(
      [product.toCompanion(true).copyWith(barcode: Value(primary))],
      barcodes: [
        for (final bc in barcodes)
          LocalProductBarcodesCompanion(
            id: Value('hub_bc_$bc'),
            productId: Value(product.id),
            barcode: Value(bc),
            isPrimary: Value(bc == primary),
            isActive: const Value(true),
            createdAt: Value(DateTime.utc(2026, 11, 20)),
          ),
      ],
      deactivateRemovedBarcodes: true,
    );
  }

  group('BR-PROD-02 ikincil barkod iş kuralları', () {
    test('Birincil barkod ikincil olarak, aynı barkod aynı ürüne iki kez, başka ürünün barkodu eklenemez', () async {
      final a = await repo.createProduct(name: 'Kahve', price: 9000, barcode: '8690000000011', deviceId: _device);
      final b = await repo.createProduct(name: 'Çay', price: 5000, barcode: '8690000000028', deviceId: _device);

      await expectLater(
        repo.addProductBarcode(productId: a.id, barcode: '8690000000011', deviceId: _device),
        throwsA(isA<ArgumentError>().having((e) => e.message.toString(), 'message', contains('birincil'))),
      );

      await repo.addProductBarcode(productId: a.id, barcode: '2000000000015', deviceId: _device);
      await expectLater(
        repo.addProductBarcode(productId: a.id, barcode: '2000000000015', deviceId: _device),
        throwsA(isA<ArgumentError>().having((e) => e.message.toString(), 'message', contains('zaten ekli'))),
      );
      await expectLater(
        repo.addProductBarcode(productId: b.id, barcode: '2000000000015', deviceId: _device),
        throwsA(isA<ArgumentError>().having((e) => e.message.toString(), 'message', contains('başka bir ürüne'))),
      );
      await expectLater(
        repo.addProductBarcode(productId: b.id, barcode: '8690000000011', deviceId: _device),
        throwsA(isA<ArgumentError>()),
      );

      // Silinen ikincil barkod aynı ürüne yeniden eklenebilir (geçmiş satır yeniden aktifleşir).
      final row = (await repo.getBarcodesForProduct(a.id)).firstWhere((r) => r.barcode == '2000000000015');
      await repo.removeProductBarcode(row.id, deviceId: _device);
      expect((await repo.getProductByBarcode('2000000000015')), isNull);
      await repo.addProductBarcode(productId: a.id, barcode: '2000000000015', deviceId: _device);
      expect((await repo.getProductByBarcode('2000000000015'))?.id, equals(a.id));
    });
  });

  group('9.4 Bekleyen PRODUCT_UPSERT varken Hub snapshot barkodları ezmez', () {
    test('Silinen barkod Outbox bloke iken Hub snapshot ile geri gelmez; sonraki yerel değişiklik onu Hub\'a geri yazmaz', () async {
      final prod = await repo.createProduct(name: 'Kola', price: 2500, barcode: '8690000000301', deviceId: _device);
      await repo.addProductBarcode(productId: prod.id, barcode: '8690000000399', deviceId: _device);
      await markAllOutbox('SYNCED'); // Hub ürünü + ikincil barkodu almış durumda
      expect((await repo.getProductCatalogSyncStatus(prod.id)).state, ProductCatalogSyncState.synced);

      final row = (await repo.getBarcodesForProduct(prod.id)).firstWhere((r) => r.barcode == '8690000000399');
      await repo.removeProductBarcode(row.id, deviceId: _device);
      final status = await repo.getProductCatalogSyncStatus(prod.id);
      expect(status.state, ProductCatalogSyncState.pending);
      expect(status.unsyncedOperationCount, 1);

      // Outbox Hub'a ulaşamıyor; bu sırada Hub snapshot'ı hâlâ eski barkodu içeriyor.
      final local = (await repo.getProductById(prod.id))!;
      await applyHubSnapshot(local, primary: '8690000000301', barcodes: ['8690000000301', '8690000000399']);
      expect(await repo.getProductByBarcode('8690000000399'), isNull,
          reason: 'Yerelde silinmiş barkod Hub snapshot ile geri gelmemeli.');

      // Kullanıcı başka bir barkod ekler; yeni PRODUCT_UPSERT silinen barkodu taşımamalı.
      await repo.addProductBarcode(productId: prod.id, barcode: '8690000000400', deviceId: _device);
      final payloadBarcodes = await lastUpsertBarcodes(prod.id);
      expect(payloadBarcodes, containsAll(['8690000000301', '8690000000400']));
      expect(payloadBarcodes, isNot(contains('8690000000399')),
          reason: 'Geri gelen barkod sonraki Outbox kaydıyla Hub\'a kalıcı olarak geri yazılmamalı.');

      // Outbox başarıyla gönderildi → Hub artık silinmiş barkodu döndürmüyor.
      await markAllOutbox('SYNCED');
      expect((await repo.getProductCatalogSyncStatus(prod.id)).state, ProductCatalogSyncState.synced);
      final synced = (await repo.getProductById(prod.id))!;
      await applyHubSnapshot(synced, primary: '8690000000301', barcodes: ['8690000000301', '8690000000400']);
      expect(await repo.getProductByBarcode('8690000000399'), isNull);
      expect((await repo.getProductByBarcode('8690000000400'))?.id, prod.id);
    });

    test('Bekleyen değişiklik yokken Hub snapshot (Hub doğrusu) yine uygulanır', () async {
      final prod = await repo.createProduct(name: 'Süt', price: 3000, barcode: '8690000000501', deviceId: _device);
      await markAllOutbox('SYNCED');
      final local = (await repo.getProductById(prod.id))!;
      // Başka bir cihaz Hub'a ikincil barkod eklemiş.
      await applyHubSnapshot(local, primary: '8690000000501', barcodes: ['8690000000501', '8690000000599']);
      expect((await repo.getProductByBarcode('8690000000599'))?.id, prod.id);
    });

    test('Bekleyen ürünün yerel birincil barkodu Hub snapshot ile değişmez', () async {
      final prod = await repo.createProduct(name: 'Ekmek', price: 1000, barcode: '8690000000601', deviceId: _device);
      await markAllOutbox('SYNCED');
      final primaryRow = (await repo.getBarcodesForProduct(prod.id)).firstWhere((r) => r.isPrimary);
      await repo.removeProductBarcode(primaryRow.id, deviceId: _device); // birincil kaldırıldı (bekliyor)
      final local = (await repo.getProductById(prod.id))!;
      expect(local.barcode, isNull);
      await applyHubSnapshot(local, primary: '8690000000601', barcodes: ['8690000000601']);
      expect((await repo.getProductById(prod.id))!.barcode, isNull);
      expect(await repo.getProductByBarcode('8690000000601'), isNull);
    });

    test('Ürün bazlı durum: RETRY → yeniden denenecek, FAILED_PERMANENT → kalıcı hata (son hata ile)', () async {
      final prod = await repo.createProduct(name: 'Peynir', price: 12000, barcode: '8690000000701', deviceId: _device);
      await repo.addProductBarcode(productId: prod.id, barcode: '8690000000799', deviceId: _device);
      await markAllOutbox('RETRY', lastError: 'HTTP 503');
      var s = await repo.getProductCatalogSyncStatus(prod.id);
      expect(s.state, ProductCatalogSyncState.retrying);
      expect(s.lastError, 'HTTP 503');

      await markAllOutbox('FAILED_PERMANENT', lastError: 'HTTP 409 BARCODE_CONFLICT');
      s = await repo.getProductCatalogSyncStatus(prod.id);
      expect(s.state, ProductCatalogSyncState.failed);
      expect(s.lastError, contains('BARCODE_CONFLICT'));
      expect((await repo.getCatalogSyncStatusByProduct()).keys, contains(prod.id));
    });
  });

  group('Bölüm 3.1, 3.5 & 4: FAILED_PERMANENT onarımı, tam ürün alan koruması ve barkodsuz senkron', () {
    test('3.1: Çapraz ürün barkod çakışmasında diğer ürünlerin senkronizasyonu kesilmez ve yerel FAILED_PERMANENT barkod korunur', () async {
      final prodA = await repo.createProduct(name: 'Ürün A', price: 1000, barcode: '8691111111111', deviceId: _device);
      final prodB = await repo.createProduct(name: 'Ürün B', price: 2000, barcode: '8692222222228', deviceId: _device);
      final prodC = await repo.createProduct(name: 'Ürün C', price: 3000, barcode: '8693333333335', deviceId: _device);
      await markAllOutbox('SYNCED');

      // Senaryo: Başka bir cihaz Hub'da Prod B'ye '8697777777777' barkodunu tanımlamışken
      // bu cihazda offline olarak aynı '8697777777777' barkodu Prod A'ya eklenir ve Hub 409 ile FAILED_PERMANENT döner.
      await repo.updateProduct(id: prodA.id, barcode: '8697777777777', deviceId: _device);
      await (db.update(db.outboxOperations)
            ..where((o) => o.status.isNotValue('SYNCED')))
          .write(const OutboxOperationsCompanion(
            status: Value('FAILED_PERMANENT'),
            lastError: Value('HTTP 409 ERR_DUPLICATE_BARCODE'),
          ));

      // Şimdi Hub snapshot'ı geliyor: Hub'da 8697777777777 Prod B'de görünüyor, Prod C'nin fiyatı 3500 olmuş.
      await repo.upsertProducts(
        [
          prodB.toCompanion(true).copyWith(name: const Value('Hub Ürün B'), price: const Value(2200), barcode: const Value('8697777777777')),
          prodC.toCompanion(true).copyWith(name: const Value('Hub Ürün C Güncel'), price: const Value(3500), barcode: const Value('8693333333335')),
        ],
        barcodes: [
          LocalProductBarcodesCompanion(
            id: const Value('hub_b'),
            productId: Value(prodB.id),
            barcode: const Value('8697777777777'),
            isPrimary: const Value(true),
            isActive: const Value(true),
            createdAt: Value(DateTime.utc(2026, 11, 20)),
          ),
          LocalProductBarcodesCompanion(
            id: const Value('hub_c'),
            productId: Value(prodC.id),
            barcode: const Value('8693333333335'),
            isPrimary: const Value(true),
            isActive: const Value(true),
            createdAt: Value(DateTime.utc(2026, 11, 20)),
          ),
        ],
        deactivateRemovedBarcodes: true,
      );

      // Diğer ürün C (ve B'nin fiyat/adı) sorunsuz güncellenmeli, Prod A'nın yerel barkodu korunmalıdır
      expect((await repo.getProductById(prodC.id))!.price, equals(3500));
      expect((await repo.getProductById(prodB.id))!.price, equals(2200));
      expect((await repo.getProductByBarcode('8697777777777'))?.id, equals(prodA.id));

      // Prod A'nın çakışan barkodunu yerelde düzeltince FAILED_PERMANENT op yerinde PENDING'e onarılır (FIFO tıkanmaz!)
      await repo.updateProduct(id: prodA.id, barcode: '8698888888881', deviceId: _device);
      final nextOp = await repo.getNextUnsyncedOutboxOperation(_device);
      expect(nextOp, isNotNull);
      expect(nextOp!.status, equals('PENDING'));
      expect((jsonDecode(nextOp.payload)['product'] as Map)['barcode'], equals('8698888888881'));
      final remainingFailed = await repo.getFailedPermanentOperations(_device);
      expect(remainingFailed, isEmpty);

      // Düzeltilen op Hub'a gönderilip SYNCED olduktan sonraki snapshot'ta Hub barkodu 8697777777777 Prod B'ye geçer
      await markAllOutbox('SYNCED');
      await repo.upsertProducts(
        [
          prodB.toCompanion(true).copyWith(name: const Value('Hub Ürün B'), price: const Value(2200), barcode: const Value('8697777777777')),
        ],
        barcodes: [
          LocalProductBarcodesCompanion(
            id: const Value('hub_b'),
            productId: Value(prodB.id),
            barcode: const Value('8697777777777'),
            isPrimary: const Value(true),
            isActive: const Value(true),
            createdAt: Value(DateTime.utc(2026, 11, 20)),
          ),
        ],
        deactivateRemovedBarcodes: true,
      );
      expect((await repo.getProductByBarcode('8697777777777'))?.id, equals(prodB.id));
    });

    test('3.5: Bekleyen PRODUCT_UPSERT sırasında ürün adı, fiyatı, birimi, KDV oranı, barkodları ve stoğu Hub verisiyle ezilmez', () async {
      final prod = await repo.createProduct(
        name: 'Eski Hub Adı',
        price: 1000,
        barcode: '8695000000011',
        initialStock: 5000,
        initialPurchasePrice: 700,
        vatRate: 10,
        deviceId: _device,
      );
      await markAllOutbox('SYNCED');
      // Hub ile senkronize ürün olarak işaretle
      await repo.upsertProducts([prod.toCompanion(true)], deactivateRemovedBarcodes: true);

      // Offline düzenleme: adı, fiyatı, KDV'si ve stoğu (alış fişiyle) yerel olarak güncellendi -> PENDING PRODUCT_UPSERT + STOCK_RECEIPT
      await repo.updateProduct(
        id: prod.id,
        name: 'Yerel Yeni Ad',
        price: 1850,
        vatRate: 20,
        stockUnit: 'paket',
        pricingUnit: 'paket',
        deviceId: _device,
      );
      await repo.receiveStock(
        receiptId: 'rcpt_35_protect',
        productId: prod.id,
        quantityMilli: 3000,
        unitPurchasePrice: 950,
        deviceId: _device,
      );

      // Hub'dan bayat veriler geliyor
      await repo.upsertProducts(
        [
          LocalProductsCompanion(
            id: Value(prod.id),
            name: const Value('Hub Bayat Ad'),
            price: const Value(900),
            priceVersionId: const Value('pv_hub_stale'),
            barcode: const Value('8695000000011'),
            stock: const Value(1000),
            stockUnit: const Value('adet'),
            pricingUnit: const Value('adet'),
            vatRate: const Value(1),
            isActive: const Value(false),
            updatedAt: Value(DateTime.utc(2026, 11, 21)),
          ),
        ],
        deactivateRemovedBarcodes: true,
      );

      final localAfter = (await repo.getProductById(prod.id))!;
      expect(localAfter.name, equals('Yerel Yeni Ad'));
      expect(localAfter.price, equals(1850));
      expect(localAfter.vatRate, equals(20));
      expect(localAfter.stockUnit, equals('paket'));
      expect(localAfter.isActive, isTrue);
      expect(localAfter.stock, equals(8000));
      final movements = await repo.getStockMovements(productId: prod.id);
      expect(movements.first.purchasePrice, equals(950));
    });

    test('4: clearBarcode birincili temizler; ClientSyncService Hub prodId placeholderını gizler', () async {
      final prod = await repo.createProduct(name: 'Kutu Süt', price: 3200, barcode: '8697000000011', deviceId: _device);
      await markAllOutbox('SYNCED');
      final cleared = await repo.updateProduct(id: prod.id, clearBarcode: true, deviceId: _device);
      expect(cleared.barcode, isNull);
      expect(await repo.getBarcodesForProduct(prod.id), isEmpty);

      // Hub ürün indirmede barkodsuz ürün için `barcode: prod.id` döndürdüğünde istemci null'a çevirir
      await markAllOutbox('SYNCED');
      final sync = ClientSyncService(
        repository: repo,
        transport: _FakeProductSyncTransport(productsJson: [
          {
            'id': prod.id,
            'name': 'Kutu Süt',
            'barcode': prod.id,
            'price': 3200,
            'price_version_id': 'pv_1',
            'stock': 0,
            'barcodes': [prod.id],
          },
        ]),
        deviceId: _device,
        deviceToken: 'tok',
        hubUrl: 'https://127.0.0.1:8945',
      );
      await sync.syncProducts();
      final afterSync = (await repo.getProductById(prod.id))!;
      expect(afterSync.barcode, isNull);
      expect(await repo.getBarcodesForProduct(prod.id), isEmpty);
    });
  });
}

class _FakeProductSyncTransport implements SyncTransport {
  final List<Map<String, dynamic>> productsJson;

  _FakeProductSyncTransport({required this.productsJson});

  @override
  Future<SyncResponse> getProducts({
    required String hubUrl,
    required String token,
    Duration timeout = const Duration(seconds: 5),
  }) async =>
      SyncResponse(
        statusCode: 200,
        body: jsonEncode({'products': productsJson, 'sync_session_id': 'sess_1'}),
      );

  @override
  Future<SyncResponse> postSyncAck({
    required String hubUrl,
    required String token,
    required String syncSessionId,
    Duration timeout = const Duration(seconds: 5),
  }) async =>
      const SyncResponse(statusCode: 200, body: '{}');

  @override
  Future<SyncResponse> postSale({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(statusCode: 200, body: '{}');

  @override
  Future<SyncResponse> postProductUpsert({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(statusCode: 200, body: '{}');

  @override
  Future<SyncResponse> postStockReceipt({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(statusCode: 200, body: '{}');

  @override
  Future<SyncResponse> getSales({
    required String hubUrl,
    required String token,
    int cursor = 0,
    int limit = 50,
    Duration timeout = const Duration(seconds: 5),
  }) async =>
      SyncResponse(
        statusCode: 200,
        body: jsonEncode({'sales': const [], 'next_cursor': cursor, 'has_more': false}),
      );

  @override
  void close() {}
}
