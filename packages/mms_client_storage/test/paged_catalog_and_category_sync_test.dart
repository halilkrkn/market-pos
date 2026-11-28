import 'dart:convert';

import 'package:drift/native.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:test/test.dart';

class _PagedCatalogFakeTransport
    implements SyncTransport, CatalogExtendedSyncTransport {
  final int totalProducts;
  final List<({int limit, int offset, Duration timeout})> pageRequests = [];
  final List<({String payload, Duration timeout})> categoryPosts = [];
  bool omitHasMoreForLegacyTest = false;
  int getProductsLegacyCalls = 0;

  _PagedCatalogFakeTransport({required this.totalProducts});

  @override
  Future<SyncResponse> getProductsPage({
    required String hubUrl,
    required String token,
    required int limit,
    required int offset,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    pageRequests.add((limit: limit, offset: offset, timeout: timeout));

    final end = (offset + limit) < totalProducts ? (offset + limit) : totalProducts;
    final pageItems = <Map<String, dynamic>>[];
    for (var i = offset; i < end; i++) {
      final isChildCat = i % 2 == 1;
      pageItems.add({
        'id': 'prod_${i.toString().padLeft(4, '0')}',
        'barcode': '869000${i.toString().padLeft(7, '0')}',
        'name': 'Ürün $i',
        'category_id': isChildCat ? 'cat_child' : 'cat_parent',
        'price': 1000 + i,
        'price_version_id': 'pv_$i',
        'stock': 5000,
        'stock_unit': 'adet',
        'pricing_unit': 'adet',
        'conversion_factor_numerator': 1,
        'conversion_factor_denominator': 1,
        'vat_rate': isChildCat ? 1 : 10,
        'is_active': true,
      });
    }

    // Alt kategori üst kategoriden önce sıralanarak FK sıralama güvencesi test edilir.
    final categories = [
      {
        'id': 'cat_child',
        'name': 'Süt Ürünleri',
        'parent_id': 'cat_parent',
        'is_active': true,
      },
      {
        'id': 'cat_parent',
        'name': 'Temel Gıda',
        'parent_id': null,
        'is_active': true,
      },
    ];

    final hasMore = !omitHasMoreForLegacyTest && end < totalProducts;
    return SyncResponse(
      statusCode: 200,
      body: jsonEncode({
        'status': 'OK',
        'products': pageItems,
        'categories': categories,
        'count': pageItems.length,
        if (!omitHasMoreForLegacyTest) 'has_more': hasMore,
        if (!omitHasMoreForLegacyTest) 'next_offset': end,
        if (!omitHasMoreForLegacyTest) 'total_count': totalProducts,
        if (!hasMore) 'sync_session_id': 'sync_paged_1',
      }),
    );
  }

  @override
  Future<SyncResponse> postCategoryUpsert({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    categoryPosts.add((payload: payload, timeout: timeout));
    return const SyncResponse(
      statusCode: 200,
      body: '{"status":"COMMITTED","operation_type":"CATEGORY_UPSERT"}',
    );
  }

  @override
  Future<SyncResponse> getProducts({
    required String hubUrl,
    required String token,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    getProductsLegacyCalls++;
    return const SyncResponse(statusCode: 200, body: '{"products":[]}');
  }

  @override
  Future<SyncResponse> postSyncAck({
    required String hubUrl,
    required String token,
    required String syncSessionId,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(statusCode: 200, body: '{"status":"ACKNOWLEDGED"}');

  @override
  Future<SyncResponse> getSales({
    required String hubUrl,
    required String token,
    int cursor = 0,
    int limit = 50,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(
        statusCode: 200,
        body: '{"sales":[],"next_cursor":0,"has_more":false}',
      );

  @override
  Future<SyncResponse> postProductUpsert({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(statusCode: 200, body: '{"status":"COMMITTED"}');

  @override
  Future<SyncResponse> postSale({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(statusCode: 201, body: '{"status":"COMMITTED"}');

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
  group('Sprint 2 (MMS-001 & MMS-005): Sayfalı Katalog ve Kategori Outbox Testleri', () {
    late ClientDatabase db;
    late ClientStorageRepository repo;

    setUp(() async {
      db = ClientDatabase.forTesting(NativeDatabase.memory());
      repo = ClientStorageRepository(db);
      await repo.initializeDevice('DEV-PAGED-01');
    });

    tearDown(() async {
      await db.close();
    });

    test('MMS-005: 2.500 ürün 3 sayfada (limit=1000) eksiksiz çekilir, >=30sn timeout kullanılır ve hiyerarşik kategoriler/KDV korunur', () async {
      final transport = _PagedCatalogFakeTransport(totalProducts: 2500);
      final sync = ClientSyncService(
        repository: repo,
        transport: transport,
        deviceId: 'DEV-PAGED-01',
        deviceToken: 'tok_paged_1',
        hubUrl: 'https://192.168.1.50:8945',
      );

      final syncedCount = await sync.syncProducts();
      expect(syncedCount, equals(2500));
      expect(transport.pageRequests, hasLength(3));
      expect(
        transport.pageRequests.map((r) => (limit: r.limit, offset: r.offset)),
        equals([
          (limit: 1000, offset: 0),
          (limit: 1000, offset: 1000),
          (limit: 1000, offset: 2000),
        ]),
      );
      for (final req in transport.pageRequests) {
        expect(req.timeout, greaterThanOrEqualTo(const Duration(seconds: 30)));
      }

      final allProducts = await db.select(db.localProducts).get();
      expect(allProducts, hasLength(2500));

      final p0 = await repo.getProductById('prod_0000');
      final p2499 = await repo.getProductById('prod_2499');
      expect(p0?.categoryId, equals('cat_parent'));
      expect(p0?.vatRate, equals(10));
      expect(p2499?.categoryId, equals('cat_child'));
      expect(p2499?.vatRate, equals(1));

      final cats = await repo.getCategories(includeInactive: true);
      expect(cats.map((c) => c.id), containsAll(['cat_parent', 'cat_child']));
      final child = await repo.getCategoryById('cat_child');
      expect(child?.parentId, equals('cat_parent'));
    });

    test('MMS-005 geriye uyumluluk: has_more dönmeyen sunucu yanıtında tek istekte tamamlanır', () async {
      final transport = _PagedCatalogFakeTransport(totalProducts: 12)
        ..omitHasMoreForLegacyTest = true;
      final sync = ClientSyncService(
        repository: repo,
        transport: transport,
        deviceId: 'DEV-PAGED-01',
        deviceToken: 'tok_paged_1',
        hubUrl: 'https://192.168.1.50:8945',
      );

      final syncedCount = await sync.syncProducts();
      expect(syncedCount, equals(12));
      expect(transport.pageRequests, hasLength(1));
    });

    test('MMS-001: createCategory ve updateCategory deviceId ile CATEGORY_UPSERT Outbox kaydı oluşturur ve syncPendingOutbox gönderir', () async {
      final transport = _PagedCatalogFakeTransport(totalProducts: 0);
      final sync = ClientSyncService(
        repository: repo,
        transport: transport,
        deviceId: 'DEV-PAGED-01',
        deviceToken: 'tok_paged_1',
        hubUrl: 'https://192.168.1.50:8945',
      );

      final cat = await repo.createCategory(
        name: 'Temel Gıda',
        deviceId: 'DEV-PAGED-01',
      );
      await repo.updateCategory(
        id: cat.id,
        name: 'Temel Gıda ve Bakliyat',
        deviceId: 'DEV-PAGED-01',
      );

      final ops = await db.select(db.outboxOperations).get();
      expect(ops, hasLength(2));
      expect(ops.every((o) => o.operationType == 'CATEGORY_UPSERT'), isTrue);
      expect(ops.every((o) => o.status == 'PENDING'), isTrue);

      final batch = await sync.syncPendingOutbox();
      expect(batch.syncedCount, equals(2));
      expect(batch.isCleanSuccess, isTrue);
      expect(transport.categoryPosts, hasLength(2));

      final firstBody =
          jsonDecode(transport.categoryPosts.first.payload) as Map<String, dynamic>;
      expect(firstBody['operation_type'], equals('CATEGORY_UPSERT'));
      expect((firstBody['category'] as Map)['name'], equals('Temel Gıda'));

      final secondBody =
          jsonDecode(transport.categoryPosts.last.payload) as Map<String, dynamic>;
      expect(
        (secondBody['category'] as Map)['name'],
        equals('Temel Gıda ve Bakliyat'),
      );
    });
  });
}
