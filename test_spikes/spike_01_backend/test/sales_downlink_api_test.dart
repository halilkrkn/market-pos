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
  final testPort = 8981;
  final baseUrl = 'http://127.0.0.1:$testPort';
  final validToken = 'mms_pat_sales_downlink_token_999';
  final deviceId = 'POS-ANDROID-01';

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    tempDir = await Directory.systemTemp.createTemp('mms_sales_downlink_backend_test_');
    dbFile = File(p.join(tempDir.path, 'market_master.db'));
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

    // Test cihazını kaydet
    await db.into(db.devices).insert(
      DevicesCompanion(
        deviceId: Value(deviceId),
        name: const Value('Android POS Test'),
        tokenHash: Value(hash),
        salt: Value(salt),
        isActive: const Value(true),
        isConfirmed: const Value(true),
      ),
    );

    // Test ürününü ekle
    await db.into(db.products).insert(
      ProductsCompanion(
        id: const Value('prod_dl_1001'),
        name: const Value('Downlink Test Ürünü'),
        barcode: const Value('99910002'),
        price: const Value(7500),
        stock: const Value(100000),
        pricingUnit: const Value('adet'),
        stockUnit: const Value('adet'),
        isActive: const Value(true),
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

  group('MARKET MMS — Backend Sales Downlink API Testleri', () {
    test('401 Unauthorized: Bearer token olmadan GET /api/v1/sales reddedilmeli', () async {
      final res = await http.get(Uri.parse('$baseUrl/api/v1/sales'));
      expect(res.statusCode, equals(401));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['error'], equals('UNAUTHORIZED'));
    });

    test('200 OK: Başlangıçta boş satış listesi döner', () async {
      final res = await http.get(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {'Authorization': 'Bearer $validToken'},
      );
      expect(res.statusCode, equals(200));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['status'], equals('OK'));
      expect(body['sales'], isEmpty);
      expect(body['count'], equals(0));
      expect(body['cursor'], equals(0));
      expect(body['next_cursor'], equals(0));
      expect(body['has_more'], isFalse);
    });

    test('POST /api/v1/sales ile satış oluşturulduğunda server_seq atanmalı ve GET /api/v1/sales ile çekilebilmeli', () async {
      final saleBody = {
        'operation_id': 'op_test_dl_001',
        'client_seq': 1,
        'idempotency_key': '$deviceId:1',
        'total_amount': 7500,
        'payment_method': 'CASH',
        'items': [
          {
            'product_id': 'prod_dl_1001',
            'quantity': 1000,
            'unit_price': 7500,
            'total_price': 7500,
          }
        ],
      };

      final postRes = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'Authorization': 'Bearer $validToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(saleBody),
      );
      expect(postRes.statusCode, equals(201));

      // Şimdi GET /api/v1/sales ile satışı sorgula
      final getRes = await http.get(
        Uri.parse('$baseUrl/api/v1/sales?cursor=0&limit=10'),
        headers: {'Authorization': 'Bearer $validToken'},
      );
      expect(getRes.statusCode, equals(200));
      final getBody = jsonDecode(getRes.body) as Map<String, dynamic>;
      final sales = getBody['sales'] as List<dynamic>;
      expect(sales.length, equals(1));

      final firstSale = sales.first as Map<String, dynamic>;
      expect(firstSale['device_id'], equals(deviceId));
      expect(firstSale['client_seq'], equals(1));
      expect(firstSale['total_amount'], equals(7500));
      expect(firstSale['payment_method'], equals('CASH'));
      expect(firstSale['status'], equals('COMPLETED'));
      expect(firstSale['server_seq'], isNotNull);
      expect(firstSale['server_seq'], isPositive);

      final items = firstSale['items'] as List<dynamic>;
      expect(items.length, equals(1));
      expect(items.first['product_name'], equals('Downlink Test Ürünü'));

      expect(getBody['next_cursor'], equals(firstSale['server_seq']));
      expect(getBody['has_more'], isFalse);
    });

    test('İptal (SALE_CANCEL) durumunda status güncellenmeli ve server_seq ilerlemeli', () async {
      // Önce mevcut satışı sorgula
      final currentRes = await http.get(
        Uri.parse('$baseUrl/api/v1/sales?cursor=0'),
        headers: {'Authorization': 'Bearer $validToken'},
      );
      final currentBody = jsonDecode(currentRes.body) as Map<String, dynamic>;
      final saleId = currentBody['sales'][0]['id'] as String;
      final prevServerSeq = currentBody['sales'][0]['server_seq'] as int;

      // SALE_CANCEL gönder
      final cancelBody = {
        'operation_id': 'op_test_cancel_001',
        'operation_type': 'SALE_CANCEL',
        'client_seq': 2,
        'idempotency_key': '$deviceId:2',
        'sale_id': saleId,
        'reason': 'Müşteri vazgeçti',
      };

      final cancelRes = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'Authorization': 'Bearer $validToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(cancelBody),
      );
      expect(cancelRes.statusCode, anyOf(200, 201));

      // cursor=prevServerSeq ile sorgulandığında güncellenmiş satış gelmeli!
      final updatedRes = await http.get(
        Uri.parse('$baseUrl/api/v1/sales?cursor=$prevServerSeq'),
        headers: {'Authorization': 'Bearer $validToken'},
      );
      expect(updatedRes.statusCode, equals(200));
      final updatedBody = jsonDecode(updatedRes.body) as Map<String, dynamic>;
      final updatedSales = updatedBody['sales'] as List<dynamic>;
      expect(updatedSales.length, equals(1));

      final cancelledSale = updatedSales.first as Map<String, dynamic>;
      expect(cancelledSale['id'], equals(saleId));
      expect(cancelledSale['status'], equals('CANCELLED'));
      expect(cancelledSale['cancel_reason'], equals('Müşteri vazgeçti'));
      expect(cancelledSale['server_seq'], greaterThan(prevServerSeq));
    });
  });
}
