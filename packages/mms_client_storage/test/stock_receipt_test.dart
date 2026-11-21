import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Stok Girişi (STOCK_RECEIPT) — Faz 2 §4.3 ve Faz 7A §8.2 TDD testleri.
///
/// Gerçek FFI SQLite (WAL) dosyası üzerinde çalışır.
class _ScriptedTransport implements SyncTransport {
  final List<String> calls = [];
  final List<Map<String, dynamic>> stockReceiptPayloads = [];
  SyncResponse Function(String opKind)? responder;
  Map<String, dynamic> productsSnapshot = {'status': 'OK', 'products': []};

  SyncResponse _respond(String kind) =>
      responder?.call(kind) ??
      SyncResponse(statusCode: 200, body: jsonEncode({'status': 'COMMITTED'}));

  @override
  Future<SyncResponse> postSale({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    calls.add('sale');
    return _respond('sale');
  }

  @override
  Future<SyncResponse> postProductUpsert({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    calls.add('product');
    return _respond('product');
  }

  @override
  Future<SyncResponse> postStockReceipt({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    calls.add('stock');
    stockReceiptPayloads.add(jsonDecode(payload) as Map<String, dynamic>);
    return _respond('stock');
  }

  @override
  Future<SyncResponse> getProducts({
    required String hubUrl,
    required String token,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return SyncResponse(statusCode: 200, body: jsonEncode(productsSnapshot));
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
  Future<SyncResponse> postSyncAck({
    required String hubUrl,
    required String token,
    required String syncSessionId,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return SyncResponse(statusCode: 200, body: '{"status":"ACKNOWLEDGED"}');
  }

  @override
  void close() {}
}

const _device = 'POS-STOCK-01';

void main() {
  late Directory tempDir;
  late File dbFile;
  late ClientDatabase db;
  late ClientStorageRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mms_stock_receipt_test_');
    dbFile = File(p.join(tempDir.path, 'client_test.db'));
    db = ClientDatabase(dbFile);
    repo = ClientStorageRepository(db);
    await repo.initializeDevice(_device);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<LocalProduct> seedProduct({
    String barcode = '8690000000011',
    int stockMilli = 5000,
    String stockUnit = 'adet',
    bool viaOutbox = false,
  }) {
    return repo.createProduct(
      name: 'Su 0.5L',
      price: 1000,
      barcode: barcode,
      initialStock: stockMilli,
      stockUnit: stockUnit,
      pricingUnit: stockUnit,
      deviceId: viaOutbox ? _device : null,
    );
  }

  Future<List<OutboxOperation>> outboxOf(String type) =>
      (db.select(db.outboxOperations)
            ..where((o) => o.operationType.equals(type))
            ..orderBy([(o) => OrderingTerm.asc(o.clientSeq)]))
          .get();

  Future<List<LocalStockMovement>> receiptMovements(String productId) =>
      (db.select(db.localStockMovements)
            ..where((m) =>
                m.productId.equals(productId) & m.movementType.equals('GIRIS')))
          .get();

  group('receiveStock — mevcut ürüne stok girişi', () {
    test('5 adet + 2 adet = 7 adet; yeni ürün oluşmaz, tek GIRIS hareketi ve tek STOCK_RECEIPT outbox kaydı yazılır', () async {
      final product = await seedProduct(stockMilli: 5000);
      final productCountBefore = (await db.select(db.localProducts).get()).length;
      final at = DateTime(2026, 11, 21, 10, 30);

      final result = await repo.receiveStock(
        receiptId: 'rcpt_test_0001',
        productId: product.id,
        quantityMilli: 2000,
        unitPurchasePrice: 750,
        note: 'Tedarikçi irsaliyesi #42',
        deviceId: _device,
        occurredAt: at,
      );

      expect(result.isDuplicate, isFalse);
      expect(result.newStockMilli, 7000);
      expect((await repo.getProductById(product.id))!.stock, 7000);
      expect((await db.select(db.localProducts).get()).length, productCountBefore);

      final movements = await receiptMovements(product.id);
      expect(movements, hasLength(1));
      final m = movements.single;
      expect(m.id, 'rcpt_test_0001');
      expect(m.quantity, 2000);
      expect(m.unit, 'adet');
      expect(m.purchasePrice, 750);
      expect(m.note, 'Tedarikçi irsaliyesi #42');
      expect(m.createdAt, at);

      final ops = await outboxOf('STOCK_RECEIPT');
      expect(ops, hasLength(1));
      final payload = jsonDecode(ops.single.payload) as Map<String, dynamic>;
      expect(payload['operation_type'], 'STOCK_RECEIPT');
      expect(payload['client_seq'], ops.single.clientSeq);
      expect(payload['receipt_id'], 'rcpt_test_0001');
      expect(payload['product_id'], product.id);
      expect(payload['quantity'], 2000, reason: 'Hub mutlak stok değil, delta almalı');
      expect(payload.containsKey('stock'), isFalse);
      expect(payload['unit'], 'adet');
      expect(payload['unit_purchase_price'], 750);
      expect(ops.single.status, 'PENDING');
      expect(ops.single.payloadHash, hasLength(64));
    });

    test('Aynı receiptId ile ikinci kayıt stoğu ikinci kez artırmaz (duplicate engeli)', () async {
      final product = await seedProduct(stockMilli: 5000);
      await repo.receiveStock(
        receiptId: 'rcpt_dup_1',
        productId: product.id,
        quantityMilli: 2000,
        deviceId: _device,
      );
      final second = await repo.receiveStock(
        receiptId: 'rcpt_dup_1',
        productId: product.id,
        quantityMilli: 2000,
        deviceId: _device,
      );

      expect(second.isDuplicate, isTrue);
      expect(second.newStockMilli, 7000);
      expect((await repo.getProductById(product.id))!.stock, 7000);
      expect(await receiptMovements(product.id), hasLength(1));
      expect(await outboxOf('STOCK_RECEIPT'), hasLength(1));
    });

    test('Aynı receiptId farklı miktarla gelirse çakışma hatası verir ve hiçbir şey yazmaz', () async {
      final product = await seedProduct(stockMilli: 5000);
      await repo.receiveStock(
        receiptId: 'rcpt_conflict',
        productId: product.id,
        quantityMilli: 2000,
        deviceId: _device,
      );

      await expectLater(
        repo.receiveStock(
          receiptId: 'rcpt_conflict',
          productId: product.id,
          quantityMilli: 3000,
          deviceId: _device,
        ),
        throwsA(isA<StateError>()),
      );
      expect((await repo.getProductById(product.id))!.stock, 7000);
      expect(await outboxOf('STOCK_RECEIPT'), hasLength(1));
    });

    test('Geçersiz girdiler reddedilir: sıfır/negatif miktar, adet biriminde kesirli miktar, negatif alış fiyatı, boş receiptId', () async {
      final product = await seedProduct(stockMilli: 5000);

      Future<void> expectRejected(Future<Object?> Function() call) async {
        await expectLater(call(), throwsA(isA<ArgumentError>()));
      }

      await expectRejected(() => repo.receiveStock(
          receiptId: 'r1', productId: product.id, quantityMilli: 0, deviceId: _device));
      await expectRejected(() => repo.receiveStock(
          receiptId: 'r2', productId: product.id, quantityMilli: -1000, deviceId: _device));
      await expectRejected(() => repo.receiveStock(
          receiptId: 'r3', productId: product.id, quantityMilli: 1500, deviceId: _device));
      await expectRejected(() => repo.receiveStock(
          receiptId: 'r4',
          productId: product.id,
          quantityMilli: 1000,
          unitPurchasePrice: -1,
          deviceId: _device));
      await expectRejected(() => repo.receiveStock(
          receiptId: '  ', productId: product.id, quantityMilli: 1000, deviceId: _device));
      await expectRejected(() => repo.receiveStock(
          receiptId: 'r6', productId: product.id, quantityMilli: 1000, deviceId: ''));

      expect((await repo.getProductById(product.id))!.stock, 5000);
      expect(await receiptMovements(product.id), isEmpty);
      expect(await outboxOf('STOCK_RECEIPT'), isEmpty);
    });

    test('kg biriminde kesirli giriş (1.250 kg) kabul edilir', () async {
      final product = await seedProduct(barcode: '2000000000017', stockMilli: 500, stockUnit: 'kg');
      final result = await repo.receiveStock(
        receiptId: 'rcpt_kg',
        productId: product.id,
        quantityMilli: 1250,
        deviceId: _device,
      );
      expect(result.newStockMilli, 1750);
    });

    test('Bilinmeyen ve pasif ürüne stok girişi reddedilir', () async {
      final product = await seedProduct(stockMilli: 5000);
      await expectLater(
        repo.receiveStock(
            receiptId: 'r_unknown', productId: 'prod_yok', quantityMilli: 1000, deviceId: _device),
        throwsA(isA<StateError>()),
      );

      await repo.deactivateProduct(product.id);
      await expectLater(
        repo.receiveStock(
            receiptId: 'r_inactive', productId: product.id, quantityMilli: 1000, deviceId: _device),
        throwsA(isA<StateError>()),
      );
      expect((await repo.getProductById(product.id))!.stock, 5000);
    });

    test('Atomiklik: outbox yazımı başarısız olursa stok ve hareket kaydı geri alınır', () async {
      final product = await seedProduct(stockMilli: 5000);
      // Outbox operationId çakışması üreterek transaction'ın son adımını bilinçli olarak düşür.
      await db.into(db.outboxOperations).insert(OutboxOperationsCompanion.insert(
            operationId: 'op_stock_rcpt_atomic',
            deviceId: 'OTHER-DEVICE',
            clientSeq: 1,
            operationType: 'STOCK_RECEIPT',
            payload: '{}',
            payloadHash: 'x',
            occurredAt: DateTime(2026),
          ));

      await expectLater(
        repo.receiveStock(
          receiptId: 'rcpt_atomic',
          productId: product.id,
          quantityMilli: 2000,
          deviceId: _device,
        ),
        throwsA(anything),
      );

      expect((await repo.getProductById(product.id))!.stock, 5000);
      expect(await receiptMovements(product.id), isEmpty);
    });

    test('Eşzamanlı stok girişleri ve satış miktar kaybetmez (5 + 10×1 − 2 = 13)', () async {
      final product = await seedProduct(stockMilli: 5000);
      await Future.wait([
        for (var i = 0; i < 10; i++)
          repo.receiveStock(
            receiptId: 'rcpt_conc_$i',
            productId: product.id,
            quantityMilli: 1000,
            deviceId: _device,
          ),
        repo.createOfflineSale(
          deviceId: _device,
          paymentMethod: 'CASH',
          items: [CartItemInput(productId: product.id, quantity: 2000)],
        ),
      ]);

      expect((await repo.getProductById(product.id))!.stock, 13000);
      expect(await receiptMovements(product.id), hasLength(10));
      final seqs = (await db.select(db.outboxOperations).get()).map((o) => o.clientSeq).toList()
        ..sort();
      expect(seqs, List<int>.generate(seqs.length, (i) => i + 1),
          reason: 'client_seq kesintisiz ve tekil kalmalı');
    });

    test('Faz 4: Aynı receiptId ile EŞZAMANLI çift kayıt (çift dokunma yarışı) stoğu yalnızca bir kez artırır', () async {
      final product = await seedProduct(stockMilli: 5000);
      final results = await Future.wait([
        for (var i = 0; i < 5; i++)
          repo.receiveStock(
            receiptId: 'rcpt_double_tap',
            productId: product.id,
            quantityMilli: 2000,
            deviceId: _device,
          ),
      ]);

      expect(results.where((r) => !r.isDuplicate), hasLength(1));
      expect((await repo.getProductById(product.id))!.stock, 7000);
      expect(await receiptMovements(product.id), hasLength(1));
      expect(await outboxOf('STOCK_RECEIPT'), hasLength(1));
    });

    test('Faz 4: Aynı DB dosyasına iki ayrı bağlantıdan eşzamanlı giriş — hiçbir giriş sessizce kaybolmaz', () async {
      final product = await seedProduct(stockMilli: 5000);
      final db2 = ClientDatabase(dbFile);
      final repo2 = ClientStorageRepository(db2);
      addTearDown(db2.close);

      final outcomes = await Future.wait([
        for (var i = 0; i < 6; i++)
          (i.isEven ? repo : repo2)
              .receiveStock(receiptId: 'rcpt_two_conn_$i', productId: product.id, quantityMilli: 1000, deviceId: _device)
              .then<Object>((r) => r, onError: (Object e) => e),
      ]);

      final applied = outcomes.whereType<StockReceiptResult>().where((r) => !r.isDuplicate).length;
      final stock = (await repo.getProductById(product.id))!.stock;
      // Kilit çakışmasında işlem hata ile geri alınabilir (kullanıcı tekrar dener) ama
      // uygulanan her giriş stoğa, hareket defterine ve Outbox'a TAM olarak yansımalıdır.
      expect(stock, 5000 + applied * 1000);
      expect(await receiptMovements(product.id), hasLength(applied));
      final seqs = (await outboxOf('STOCK_RECEIPT')).map((o) => o.clientSeq).toList();
      expect(seqs.toSet(), hasLength(seqs.length), reason: 'client_seq tekrar etmemeli');
      expect(seqs, hasLength(applied));
    });

    test('createProduct başlangıç alış fiyatını BASLANGIC_STOK hareketine yazar', () async {
      final product = await repo.createProduct(
        name: 'Makarna',
        price: 2500,
        barcode: '8690000000028',
        initialStock: 4000,
        initialPurchasePrice: 1800,
      );
      final movements = await (db.select(db.localStockMovements)
            ..where((m) => m.productId.equals(product.id)))
          .get();
      expect(movements.single.movementType, 'BASLANGIC_STOK');
      expect(movements.single.purchasePrice, 1800);
    });
  });

  group('STOCK_RECEIPT senkronizasyonu', () {
    ClientSyncService serviceFor(_ScriptedTransport t) => ClientSyncService(
          repository: repo,
          transport: t,
          deviceId: _device,
          deviceToken: 'tok',
          hubUrl: 'https://hub.local:8945',
        );

    test('FIFO sırasıyla PRODUCT_UPSERT → STOCK_RECEIPT gönderilir ve SYNCED işaretlenir', () async {
      final product = await seedProduct(stockMilli: 5000, viaOutbox: true);
      await repo.receiveStock(
          receiptId: 'rcpt_sync', productId: product.id, quantityMilli: 2000, deviceId: _device);

      final t = _ScriptedTransport();
      final result = await serviceFor(t).syncPendingOutbox();

      expect(t.calls, ['product', 'stock']);
      expect(result.syncedCount, 2);
      expect(t.stockReceiptPayloads.single['receipt_id'], 'rcpt_sync');
      final op = (await outboxOf('STOCK_RECEIPT')).single;
      expect(op.status, 'SYNCED');
    });

    for (final code in [401, 403, 426]) {
      test('HTTP $code kayıt FAILED_PERMANENT yapılmaz; RETRY ile bekletilir ve kuyruk durur', () async {
        final product = await seedProduct(stockMilli: 5000);
        await repo.receiveStock(
            receiptId: 'rcpt_auth_$code', productId: product.id, quantityMilli: 1000, deviceId: _device);
        await repo.receiveStock(
            receiptId: 'rcpt_auth2_$code', productId: product.id, quantityMilli: 1000, deviceId: _device);

        final t = _ScriptedTransport()
          ..responder = (_) => SyncResponse(statusCode: code, body: '{"code":"ERR"}');
        final result = await serviceFor(t).syncPendingOutbox();

        expect(result.permanentFailedCount, 0);
        expect(t.calls, ['stock'], reason: 'FIFO: ilk kayıt bekletilince ikinci gönderilmez');
        final ops = await outboxOf('STOCK_RECEIPT');
        expect(ops.first.status, 'RETRY');
        expect(ops.first.lastError, contains('$code'));
        expect(ops.last.status, 'PENDING');
      });
    }
  });

  group('Hub ürün snapshot’ı bekleyen yerel değişiklikleri ezmez', () {
    Map<String, dynamic> hubProduct(LocalProduct p, {required int stock, Object? vatRate}) => {
          'id': p.id,
          'barcode': p.barcode,
          'name': p.name,
          'price': p.price,
          'price_version_id': p.priceVersionId,
          'stock': stock,
          'stock_unit': p.stockUnit,
          'pricing_unit': p.pricingUnit,
          'conversion_factor_numerator': 1,
          'conversion_factor_denominator': 1,
          'is_active': true,
          'barcodes': [p.barcode],
          if (vatRate != null) 'vat_rate': vatRate,
        };

    test('Bekleyen STOCK_RECEIPT varken Hub stoğu yerel stoğu ezmez; senkron sonrası Hub otoritedir', () async {
      final product = await seedProduct(stockMilli: 5000);
      await repo.receiveStock(
          receiptId: 'rcpt_snap', productId: product.id, quantityMilli: 2000, deviceId: _device);

      final t = _ScriptedTransport()
        ..productsSnapshot = {
          'status': 'OK',
          'products': [hubProduct(product, stock: 5000)],
        };
      final service = ClientSyncService(
          repository: repo, transport: t, deviceId: _device, deviceToken: 'tok', hubUrl: 'https://h');

      await service.syncProducts();
      expect((await repo.getProductById(product.id))!.stock, 7000,
          reason: 'Bekleyen giriş geri alınmamalı');

      await service.syncPendingOutbox();
      t.productsSnapshot = {
        'status': 'OK',
        'products': [hubProduct(product, stock: 9000)],
      };
      await service.syncProducts();
      expect((await repo.getProductById(product.id))!.stock, 9000);
    });

    test('Bekleyen SALE_CREATE varken Hub stoğu satılan ürünün yerel stoğunu ezmez', () async {
      final product = await seedProduct(stockMilli: 5000);
      await repo.createOfflineSale(
        deviceId: _device,
        paymentMethod: 'CASH',
        items: [CartItemInput(productId: product.id, quantity: 1000)],
      );
      final t = _ScriptedTransport()
        ..productsSnapshot = {
          'status': 'OK',
          'products': [hubProduct(product, stock: 5000)],
        };
      await ClientSyncService(
              repository: repo, transport: t, deviceId: _device, deviceToken: 'tok', hubUrl: 'https://h')
          .syncProducts();
      expect((await repo.getProductById(product.id))!.stock, 4000);
    });

    test('Hub snapshot vat_rate göndermezse yerel KDV oranı 20’ye sıfırlanmaz', () async {
      final product = await repo.createProduct(
        name: 'Ekmek',
        price: 1000,
        barcode: '8690000000035',
        vatRate: 1,
      );
      final t = _ScriptedTransport()
        ..productsSnapshot = {
          'status': 'OK',
          'products': [hubProduct(product, stock: 0)],
        };
      await ClientSyncService(
              repository: repo, transport: t, deviceId: _device, deviceToken: 'tok', hubUrl: 'https://h')
          .syncProducts();
      expect((await repo.getProductById(product.id))!.vatRate, 1);
    });
  });

  group('Şema v3 → v4 migration', () {
    test('Eski local_stock_movements satırları korunur, purchase_price/note sütunları eklenir', () async {
      final product = await seedProduct(stockMilli: 5000);
      await db.close();

      // v3 şemasını simüle et: v4 sütunlarını kaldır ve user_version'ı 3'e çek.
      final raw = ClientDatabase.forTesting(NativeDatabase(dbFile));
      await raw.customStatement('ALTER TABLE local_stock_movements DROP COLUMN purchase_price;');
      await raw.customStatement('ALTER TABLE local_stock_movements DROP COLUMN note;');
      await raw.customStatement('PRAGMA user_version = 3;');
      await raw.close();

      db = ClientDatabase(dbFile);
      repo = ClientStorageRepository(db);
      final movements = await (db.select(db.localStockMovements)
            ..where((m) => m.productId.equals(product.id)))
          .get();
      expect(movements, hasLength(1));
      expect(movements.single.purchasePrice, isNull);

      final r = await repo.receiveStock(
          receiptId: 'rcpt_after_migration',
          productId: product.id,
          quantityMilli: 1000,
          unitPurchasePrice: 500,
          deviceId: _device);
      expect(r.newStockMilli, 6000);
    });
  });

  group('HttpSyncTransport tenant/store başlıkları', () {
    test('Tüm mağaza verisi isteklerinde X-MMS-Tenant-Id ve X-MMS-Store-Id gönderilir', () async {
      final seen = <String, Map<String, String>>{};
      final client = MockClient((http.Request req) async {
        seen[req.url.path] = req.headers;
        return http.Response('{"status":"OK","products":[],"sales":[]}', 200);
      });
      final transport = HttpSyncTransport.forStore(
          client: client, tenantId: 'tenant-a', storeId: 'store-1');

      await transport.postSale(hubUrl: 'https://h', token: 't', payload: '{}');
      await transport.postProductUpsert(hubUrl: 'https://h', token: 't', payload: '{}');
      await transport.postStockReceipt(hubUrl: 'https://h', token: 't', payload: '{}');
      await transport.getProducts(hubUrl: 'https://h', token: 't');
      await transport.getSales(hubUrl: 'https://h', token: 't');
      await transport.postSyncAck(hubUrl: 'https://h', token: 't', syncSessionId: 's');

      expect(seen.keys, containsAll(<String>[
        '/api/v1/sales',
        '/api/v1/products/upsert',
        '/api/v1/stock/receipts',
        '/api/v1/products',
        '/api/v1/products/sync-ack',
      ]));
      for (final headers in seen.values) {
        expect(headers['x-mms-tenant-id'], 'tenant-a');
        expect(headers['x-mms-store-id'], 'store-1');
        expect(headers['authorization'], 'Bearer t');
      }
    });
  });
}
