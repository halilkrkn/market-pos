import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import '../bin/server.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/pepper_manager.dart';
import '../lib/security/token_manager.dart';

void main() {
  late Directory tempDir;
  late File dbFile;
  late SpikeDatabase db;
  late WriteQueue writeQueue;
  late SpikeServer server;
  late PepperManager pepperManager;
  final testPort = 8979;
  final baseUrl = 'http://127.0.0.1:$testPort';
  final validToken = 'mms_pat_prod_upsert_test_token_123';
  final deviceId = 'DEV_PROD_TEST';

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    tempDir = await Directory.systemTemp.createTemp('mms_prod_upsert_test_');
    dbFile = File(p.join(tempDir.path, 'market_prod.db'));
    final pepperFile = File(p.join(tempDir.path, 'pepper.dpapi'));
    pepperManager = PepperManager(pepperFile);
    pepperManager.initialize();

    db = SpikeDatabase(dbFile);
    writeQueue = WriteQueue();

    final salt = TokenManager.generateSalt();
    final hash = TokenManager.hashToken(
      rawToken: validToken,
      salt: salt,
      pepper: pepperManager.pepper,
    );

    await db.into(db.devices).insert(
      DevicesCompanion(
        deviceId: Value(deviceId),
        name: const Value('Product Test Device'),
        tokenHash: Value(hash),
        salt: Value(salt),
        isActive: const Value(true),
        isConfirmed: const Value(true),
      ),
    );

    server = SpikeServer(
      db: db,
      writeQueue: writeQueue,
      dbFile: dbFile,
      pepperManager: pepperManager,
      requireTls: false,
    );

    await server.start(port: testPort);
  });

  tearDownAll(() async {
    await server.stop();
    await db.close();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('Master Hub POST /api/v1/products/upsert Testleri', () {
    test('1. Yeni ürün ekleme: 200 OK, db.products ve db.productPriceHistories kayıtları oluşturulur', () async {
      final payload = {
        'client_seq': 1,
        'operation_id': 'op_prod_001',
        'operation_type': 'PRODUCT_UPSERT',
        'product': {
          'id': 'prod_test_01',
          'name': 'Test Ürün 1',
          'barcode': '99910001',
          'category_id': 'cat_temel',
          'price': 4500,
          'stock': 20000,
          'stock_unit': 'adet',
          'pricing_unit': 'adet',
          'conversion_factor_numerator': 1,
          'conversion_factor_denominator': 1,
          'vat_rate': 20,
          'is_active': true,
        },
      };

      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/products/upsert'),
        headers: {
          'Authorization': 'Bearer $validToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      expect(res.statusCode, equals(200));
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      expect(json['status'], equals('COMMITTED'));
      expect(json['product_id'], equals('prod_test_01'));

      final pInDb = await (db.select(db.products)..where((p) => p.id.equals('prod_test_01'))).getSingleOrNull();
      expect(pInDb, isNotNull);
      expect(pInDb!.name, equals('Test Ürün 1'));
      expect(pInDb.barcode, equals('99910001'));
      expect(pInDb.price, equals(4500));
      expect(pInDb.stock, equals(20000));

      final ph = await (db.select(db.productPriceHistories)..where((h) => h.productId.equals('prod_test_01'))).get();
      expect(ph.length, equals(1));
      expect(ph.first.price, equals(4500));
    });

    test('2. Mevcut ürünü güncelleme: fiyat değiştiğinde price_version_id ve yeni price history eklenir', () async {
      final payload = {
        'client_seq': 2,
        'operation_id': 'op_prod_002',
        'operation_type': 'PRODUCT_UPSERT',
        'product': {
          'id': 'prod_test_01',
          'name': 'Test Ürün 1 Güncel',
          'barcode': '99910001',
          'category_id': 'cat_temel',
          'price': 5500, // Zam: 45 TL -> 55 TL
          'stock': 25000,
          'stock_unit': 'adet',
          'pricing_unit': 'adet',
          'conversion_factor_numerator': 1,
          'conversion_factor_denominator': 1,
          'vat_rate': 20,
          'is_active': true,
        },
      };

      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/products/upsert'),
        headers: {
          'Authorization': 'Bearer $validToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      expect(res.statusCode, equals(200));
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      expect(json['status'], equals('COMMITTED'));

      final pInDb = await (db.select(db.products)..where((p) => p.id.equals('prod_test_01'))).getSingleOrNull();
      expect(pInDb, isNotNull);
      expect(pInDb!.name, equals('Test Ürün 1 Güncel'));
      expect(pInDb.price, equals(5500));

      final ph = await (db.select(db.productPriceHistories)..where((h) => h.productId.equals('prod_test_01'))).get();
      expect(ph.length, equals(2));
      expect(ph.last.price, equals(5500));
    });

    test('3. Idempotent tekrar: Aynı payload ile ikinci istek 200 OK döner, x-mms-idempotent-replay başlığı taşır', () async {
      final payload = {
        'client_seq': 2,
        'operation_id': 'op_prod_002',
        'operation_type': 'PRODUCT_UPSERT',
        'product': {
          'id': 'prod_test_01',
          'name': 'Test Ürün 1 Güncel',
          'barcode': '99910001',
          'category_id': 'cat_temel',
          'price': 5500,
          'stock': 25000,
          'stock_unit': 'adet',
          'pricing_unit': 'adet',
          'conversion_factor_numerator': 1,
          'conversion_factor_denominator': 1,
          'vat_rate': 20,
          'is_active': true,
        },
      };

      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/products/upsert'),
        headers: {
          'Authorization': 'Bearer $validToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      expect(res.statusCode, equals(200));
      expect(res.headers['x-mms-idempotent-replay'], equals('true'));
    });

    test('4. Idempotency çakışması: Aynı client_seq farklı payload ile 409 CONFLICT döner', () async {
      final payloadMismatch = {
        'client_seq': 2,
        'operation_id': 'op_prod_002_diff',
        'operation_type': 'PRODUCT_UPSERT',
        'product': {
          'id': 'prod_test_01',
          'name': 'Tamamen Farklı Payload',
          'barcode': '99910001',
          'price': 9999,
        },
      };

      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/products/upsert'),
        headers: {
          'Authorization': 'Bearer $validToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payloadMismatch),
      );

      expect(res.statusCode, equals(409));
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      expect(json['code'], equals('ERR_IDEMPOTENCY_PAYLOAD_MISMATCH'));
    });

    test('5. Barkod çakışması: Başka bir ürünün barkodu kullanıldığında 409 ERR_DUPLICATE_BARCODE döner', () async {
      final payloadDuplicateBarcode = {
        'client_seq': 3,
        'operation_id': 'op_prod_003',
        'operation_type': 'PRODUCT_UPSERT',
        'product': {
          'id': 'prod_test_02', // Farklı ürün ID
          'name': 'İkinci Ürün',
          'barcode': '99910001', // Ama prod_test_01 ile aynı barkod!
          'price': 2000,
        },
      };

      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/products/upsert'),
        headers: {
          'Authorization': 'Bearer $validToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payloadDuplicateBarcode),
      );

      expect(res.statusCode, equals(409));
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      expect(json['code'], equals('ERR_DUPLICATE_BARCODE'));
    });

    test('6. Veritabanı seviyesinde Products tablosu UNIQUE(barcode) kısıtı ile mükerrer barkodu reddeder', () async {
      // prod_test_01 zaten 99910001 barkoduna sahip
      expect(
        () => db.into(db.products).insert(
          const ProductsCompanion(
            id: Value('prod_direct_dup'),
            name: Value('Doğrudan Eklenen Mükerrer'),
            barcode: Value('99910001'), // ÇAKIŞAN BARKOD
            price: Value(1000),
            stock: Value(5000),
          ),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('7. Eski Spike kodunun kaldırıldığı doğrulanır: prod_cola veritabanında otomatik oluşturulmaz', () async {
      final orphanCola = await (db.select(db.products)..where((p) => p.id.equals('prod_cola'))).getSingleOrNull();
      expect(orphanCola, isNull, reason: 'prod_cola asla sunucu başlangıcında otomatik oluşturulmamalıdır');
    });
  });
}
