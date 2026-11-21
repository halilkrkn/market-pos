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

/// Faz 2 §4.3 / Faz 7A §8.2 / Faz 7B — Hub STOCK_RECEIPT, stok ezilme düzeltmesi,
/// tenant/store başlık zorunluluğu ve admin secret fail-closed testleri.
void main() {
  late Directory tempDir;
  late SpikeDatabase db;
  late WriteQueue writeQueue;
  late SpikeServer server;
  late PepperManager pepperManager;
  const port = 8984;
  const baseUrl = 'http://127.0.0.1:$port';
  const tokenA = 'mms_pat_stock_receipt_device_a_token';
  const tokenB = 'mms_pat_stock_receipt_device_b_token';
  const deviceA = 'DEV_STOCK_A';
  const deviceB = 'DEV_STOCK_B';
  const productId = 'prod_stock_01';

  Future<void> registerDevice(String id, String token) async {
    final salt = TokenManager.generateSalt();
    await db.into(db.devices).insert(DevicesCompanion(
          deviceId: Value(id),
          name: Value(id),
          tokenHash: Value(TokenManager.hashToken(
            rawToken: token,
            salt: salt,
            pepper: pepperManager.pepper,
          )),
          salt: Value(salt),
          isActive: const Value(true),
          isConfirmed: const Value(true),
        ));
  }

  Map<String, String> headers(String token) => {
        'authorization': 'Bearer $token',
        'content-type': 'application/json',
        'x-mms-tenant-id': SpikeServer.defaultTenantId,
        'x-mms-store-id': SpikeServer.defaultStoreId,
      };

  Map<String, dynamic> receipt({
    required int seq,
    required String receiptId,
    int quantity = 2000,
    String unit = 'adet',
    String product = productId,
    int? purchase = 750,
  }) =>
      {
        'operation_id': 'op_stock_$receiptId',
        'operation_type': 'STOCK_RECEIPT',
        'client_seq': seq,
        'receipt_id': receiptId,
        'product_id': product,
        'quantity': quantity,
        'unit': unit,
        'unit_purchase_price': purchase,
        'note': 'İrsaliye 42',
        'occurred_at': '2026-11-21T10:30:00.000Z',
      };

  Future<http.Response> postReceipt(String token, Map<String, dynamic> body) => http.post(
        Uri.parse('$baseUrl/api/v1/stock/receipts'),
        headers: headers(token),
        body: jsonEncode(body),
      );

  Future<int> hubStock() async =>
      (await (db.select(db.products)..where((p) => p.id.equals(productId))).getSingle()).stock;

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    tempDir = await Directory.systemTemp.createTemp('mms_hub_stock_receipt_');
    final dbFile = File(p.join(tempDir.path, 'market_master.db'));
    pepperManager = PepperManager(File(p.join(tempDir.path, 'pepper.dpapi')))..initialize();
    db = SpikeDatabase(dbFile);
    writeQueue = WriteQueue();
    await registerDevice(deviceA, tokenA);
    await registerDevice(deviceB, tokenB);

    server = SpikeServer(
      db: db,
      writeQueue: writeQueue,
      dbFile: dbFile,
      pepperManager: pepperManager,
      requireTls: false,
      requireTenantStoreHeaders: true,
    );
    await server.start(port: port);

    // seq 1: ürün 5 adet başlangıç stoğuyla Hub'a gelir
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/products/upsert'),
      headers: headers(tokenA),
      body: jsonEncode({
        'client_seq': 1,
        'operation_id': 'op_prod_create',
        'operation_type': 'PRODUCT_UPSERT',
        'product': {
          'id': productId,
          'name': 'Su 0.5L',
          'barcode': '8690000000011',
          'price': 1000,
          'stock': 5000,
          'stock_unit': 'adet',
          'pricing_unit': 'adet',
          'is_active': true,
        },
      }),
    );
    expect(res.statusCode, 200, reason: res.body);
  });

  tearDownAll(() async {
    await server.stop();
    await db.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('POST /api/v1/stock/receipts', () {
    test('Delta uygulanır: 5 + 2 = 7; GIRIS hareketi alış fiyatı ve açıklamayla yazılır', () async {
      final res = await postReceipt(tokenA, receipt(seq: 2, receiptId: 'rcpt_hub_1'));
      expect(res.statusCode, 200, reason: res.body);
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      expect(json['status'], 'COMMITTED');
      expect(json['new_stock'], 7000);
      expect(await hubStock(), 7000);

      final movement = await (db.select(db.stockMovements)
            ..where((m) => m.id.equals('rcpt_hub_1')))
          .getSingle();
      expect(movement.movementType, 'GIRIS');
      expect(movement.quantity, 2000);
      expect(movement.purchasePrice, 750);
      expect(movement.note, 'İrsaliye 42');
    });

    test('Aynı istek tekrarı (ağ retry) replay döner, stok ikinci kez artmaz', () async {
      final res = await postReceipt(tokenA, receipt(seq: 2, receiptId: 'rcpt_hub_1'));
      expect(res.statusCode, 200);
      expect(res.headers['x-mms-idempotent-replay'], 'true');
      expect(await hubStock(), 7000);
    });

    test('Aynı client_seq farklı içerikle 409 idempotency conflict döner', () async {
      final res = await postReceipt(tokenA, receipt(seq: 2, receiptId: 'rcpt_hub_1', quantity: 9000));
      expect(res.statusCode, 409);
      expect(await hubStock(), 7000);
    });

    test('Aynı receipt_id yeni client_seq ile gelirse stok uygulanmaz ama kuyruk ilerler', () async {
      final res = await postReceipt(tokenA, receipt(seq: 3, receiptId: 'rcpt_hub_1'));
      expect(res.statusCode, 200, reason: res.body);
      expect((jsonDecode(res.body) as Map)['status'], 'DUPLICATE_RECEIPT_IGNORED');
      expect(await hubStock(), 7000);
      final count = await (db.select(db.stockMovements)
            ..where((m) => m.id.equals('rcpt_hub_1')))
          .get();
      expect(count, hasLength(1));
    });

    test('Aynı receipt_id farklı miktarla yeni client_seq ile gelirse 409 döner', () async {
      final res = await postReceipt(tokenA, receipt(seq: 4, receiptId: 'rcpt_hub_1', quantity: 3000));
      expect(res.statusCode, 409);
      expect((jsonDecode(res.body) as Map)['code'], 'ERR_STOCK_RECEIPT_CONFLICT');
    });

    test('Doğrulama: bilinmeyen ürün 404, birim uyuşmazlığı 422, sıfır miktar 400, sıra boşluğu 409', () async {
      final unknown = await postReceipt(tokenA, receipt(seq: 4, receiptId: 'r_x', product: 'prod_yok'));
      expect(unknown.statusCode, 404);
      final unit = await postReceipt(tokenA, receipt(seq: 4, receiptId: 'r_y', unit: 'kg'));
      expect(unit.statusCode, 422);
      expect((jsonDecode(unit.body) as Map)['code'], 'ERR_UNIT_MISMATCH');
      final zero = await postReceipt(tokenA, receipt(seq: 4, receiptId: 'r_z', quantity: 0));
      expect(zero.statusCode, 400);
      final gap = await postReceipt(tokenA, receipt(seq: 10, receiptId: 'r_gap'));
      expect(gap.statusCode, 409);
      expect((jsonDecode(gap.body) as Map)['code'], 'ERR_CLIENT_SEQ_GAP');
      expect(await hubStock(), 7000);
    });

    test('İki cihazdan eşzamanlı stok girişleri kayıpsız toplanır', () async {
      final results = await Future.wait([
        postReceipt(tokenA, receipt(seq: 4, receiptId: 'rcpt_a_conc', quantity: 1000)),
        postReceipt(tokenB, receipt(seq: 1, receiptId: 'rcpt_b_conc', quantity: 3000)),
      ]);
      for (final r in results) {
        expect(r.statusCode, 200, reason: r.body);
      }
      expect(await hubStock(), 11000);
    });
  });

  group('PRODUCT_UPSERT mevcut ürünün stoğunu ezmez (lost-update düzeltmesi)', () {
    test('Bayat mutlak stok değeriyle gelen ürün güncellemesi Hub stoğunu değiştirmez', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/products/upsert'),
        headers: headers(tokenB),
        body: jsonEncode({
          'client_seq': 2,
          'operation_id': 'op_prod_rename',
          'operation_type': 'PRODUCT_UPSERT',
          'product': {
            'id': productId,
            'name': 'Su 0.5L (Yeni Ad)',
            'barcode': '8690000000011',
            'price': 1000,
            'stock': 1000, // bayat değer
            'stock_unit': 'adet',
            'pricing_unit': 'adet',
            'is_active': true,
          },
        }),
      );
      expect(res.statusCode, 200, reason: res.body);
      final product = await (db.select(db.products)..where((p) => p.id.equals(productId))).getSingle();
      expect(product.name, 'Su 0.5L (Yeni Ad)');
      expect(product.stock, 11000);
    });
  });

  group('Tenant/store izolasyonu', () {
    test('Başlıksız istek 403 ERR_TENANT_STORE_REQUIRED, yanlış mağaza 403 ERR_TENANT_STORE_MISMATCH', () async {
      final noHeaders = await http.post(
        Uri.parse('$baseUrl/api/v1/stock/receipts'),
        headers: {'authorization': 'Bearer $tokenA', 'content-type': 'application/json'},
        body: jsonEncode(receipt(seq: 5, receiptId: 'r_iso')),
      );
      expect(noHeaders.statusCode, 403);
      expect((jsonDecode(noHeaders.body) as Map)['code'], 'ERR_TENANT_STORE_REQUIRED');

      final wrongStore = await http.get(
        Uri.parse('$baseUrl/api/v1/products'),
        headers: {
          'authorization': 'Bearer $tokenA',
          'x-mms-tenant-id': SpikeServer.defaultTenantId,
          'x-mms-store-id': 'baska-sube',
        },
      );
      expect(wrongStore.statusCode, 403);
      expect((jsonDecode(wrongStore.body) as Map)['code'], 'ERR_TENANT_STORE_MISMATCH');
      expect(wrongStore.body, isNot(contains('Su 0.5L')));
    });
  });

  group('Admin secret fail-closed (adm_sec fallback kaldırıldı)', () {
    test('ADMIN_SECRET yapılandırılmamışsa "adm_sec" ile yedekleme/geri yükleme/listeleme reddedilir', () async {
      expect(Platform.environment['ADMIN_SECRET'], isNull,
          reason: 'Test ortamında ADMIN_SECRET tanımlı olmamalı');
      for (final route in [
        '/api/v1/admin/backup',
        '/api/v1/admin/restore',
        '/api/v1/admin/backup/prune',
      ]) {
        final res = await http.post(
          Uri.parse('$baseUrl$route'),
          headers: {'x-mms-admin-secret': 'adm_sec', 'content-type': 'application/json'},
          body: '{}',
        );
        expect(res.statusCode, 503, reason: '$route: ${res.body}');
      }
      final list = await http.get(
        Uri.parse('$baseUrl/api/v1/admin/backups'),
        headers: {'x-mms-admin-secret': 'adm_sec'},
      );
      expect(list.statusCode, 503);
    });
  });
}
