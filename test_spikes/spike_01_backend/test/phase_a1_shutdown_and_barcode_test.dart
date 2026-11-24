import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw_sqlite;
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/pepper_manager.dart';
import '../lib/security/token_manager.dart';

void main() {
  group('Faz A-1.1: Unified Hub Shutdown (LifecycleManager + SpikeServer)', () {
    test('SpikeServer.stop() ve admin shutdown aynı birleşik kapanış yolunu çalıştırır (timers/discovery/drain/db.close)', () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      configureSqliteNative();
      final tempDir = await Directory.systemTemp.createTemp('mms_test_only_a1_shutdown_');
      try {
        final dbFile = File(p.join(tempDir.path, 'hub.db'));
        final pepperManager = PepperManager(File(p.join(tempDir.path, 'pepper.dpapi')))
          ..initialize();
        final db = SpikeDatabase(dbFile);
        final queue = WriteQueue();

        final server = SpikeServer(
          db: db,
          dbFile: dbFile,
          writeQueue: queue,
          backupDirectory: p.join(tempDir.path, 'backups'),
          pepperManager: pepperManager,
          adminSecret: 'test_only_admin_secret_a1',
        );

        await server.start(port: 0, enableDiscovery: false);
        expect(server.lifecycle.onBeforeDrain, isNotNull);

        await server.stop();
        // İkinci stop() çağrısı idempotent olmalıdır
        await server.stop();

        expect(server.lifecycle.isShuttingDown, isTrue);
        expect(server.lifecycle.exitCode, equals(0));
        expect(queue.isDraining, isTrue);
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });

    test('Admin HTTP /api/v1/admin/shutdown tetiklendiğinde birleşik kaynak durdurma ve DB drain eksiksiz çalışır', () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      configureSqliteNative();
      final tempDir = await Directory.systemTemp.createTemp('mms_test_only_a1_http_shut_');
      try {
        final dbFile = File(p.join(tempDir.path, 'hub_http_shut.db'));
        final pepperManager = PepperManager(File(p.join(tempDir.path, 'pepper.dpapi')))
          ..initialize();
        final db = SpikeDatabase(dbFile);
        final queue = WriteQueue();
        const adminSecret = 'test_only_http_shut_secret';

        final server = SpikeServer(
          db: db,
          dbFile: dbFile,
          writeQueue: queue,
          backupDirectory: p.join(tempDir.path, 'backups'),
          pepperManager: pepperManager,
          adminSecret: adminSecret,
        );

        const port = 18981;
        await server.start(port: port, enableDiscovery: false);

        final res = await http.post(
          Uri.parse('http://127.0.0.1:$port/api/v1/admin/shutdown'),
          headers: {
            'content-type': 'application/json',
            'x-admin-secret': adminSecret,
          },
        );
        expect(res.statusCode, equals(200));

        await server.lifecycle.onShutdown.timeout(const Duration(seconds: 5));
        expect(server.lifecycle.exitCode, equals(0));
        expect(queue.isDraining, isTrue);

        // Tekrarlı stop güvenli olmalı
        await server.stop();
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });
  });

  group('Faz A-1.2: GAP-A01 Secondary Barcode Hub Migration & Full-Stack Sync', () {
    test('Hub DB v3 -> v4 migration mevcut ürünleri korur ve birincil barkodları product_barcodes tablosuna backfill eder', () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      configureSqliteNative();
      final tempDir = await Directory.systemTemp.createTemp('mms_test_only_v3_v4_mig_');
      try {
        final dbFile = File(p.join(tempDir.path, 'legacy_v3.db'));
        final raw = raw_sqlite.sqlite3.open(dbFile.path);
        raw.execute('''
          CREATE TABLE products (
            id TEXT NOT NULL PRIMARY KEY,
            barcode TEXT NOT NULL UNIQUE,
            name TEXT NOT NULL,
            price INTEGER NOT NULL,
            price_version_id TEXT NOT NULL DEFAULT 'pv_init',
            stock INTEGER NOT NULL,
            stock_unit TEXT NOT NULL DEFAULT 'adet',
            pricing_unit TEXT NOT NULL DEFAULT 'adet',
            conversion_factor_numerator INTEGER NOT NULL DEFAULT 1,
            conversion_factor_denominator INTEGER NOT NULL DEFAULT 1,
            is_active INTEGER NOT NULL DEFAULT 1,
            updated_at INTEGER NOT NULL DEFAULT 1700000000
          );
          CREATE TABLE sales (
            id TEXT NOT NULL PRIMARY KEY,
            device_id TEXT NOT NULL,
            client_seq INTEGER NOT NULL,
            total_amount INTEGER NOT NULL,
            payment_method TEXT NOT NULL,
            server_seq INTEGER,
            status TEXT NOT NULL DEFAULT 'COMPLETED',
            cancel_reason TEXT,
            cancelled_at INTEGER,
            created_at INTEGER NOT NULL DEFAULT 1700000000
          );
          CREATE TABLE sale_items (
            id TEXT NOT NULL PRIMARY KEY,
            sale_id TEXT NOT NULL REFERENCES sales(id),
            product_id TEXT NOT NULL REFERENCES products(id),
            quantity INTEGER NOT NULL,
            unit_price INTEGER NOT NULL,
            total_price INTEGER NOT NULL
          );
          CREATE TABLE stock_movements (
            id TEXT NOT NULL PRIMARY KEY,
            product_id TEXT NOT NULL REFERENCES products(id),
            quantity INTEGER NOT NULL,
            unit TEXT NOT NULL DEFAULT 'adet',
            movement_type TEXT NOT NULL,
            reference_id TEXT NOT NULL,
            purchase_price INTEGER,
            note TEXT,
            created_at INTEGER NOT NULL DEFAULT 1700000000
          );
          CREATE TABLE product_price_histories (
            id TEXT NOT NULL PRIMARY KEY,
            product_id TEXT NOT NULL REFERENCES products(id),
            price INTEGER NOT NULL,
            valid_from INTEGER NOT NULL,
            valid_until INTEGER,
            created_at INTEGER NOT NULL DEFAULT 1700000000
          );
          CREATE TABLE product_sync_sessions (
            id TEXT NOT NULL PRIMARY KEY,
            device_id TEXT NOT NULL,
            product_count INTEGER NOT NULL,
            synced_at INTEGER NOT NULL,
            is_acknowledged INTEGER NOT NULL DEFAULT 0,
            acknowledged_at INTEGER,
            created_at INTEGER NOT NULL DEFAULT 1700000000
          );
          CREATE TABLE processed_operations (
            operation_id TEXT NOT NULL PRIMARY KEY,
            device_id TEXT NOT NULL,
            idempotency_key TEXT NOT NULL UNIQUE,
            client_seq INTEGER,
            operation_type TEXT,
            request_hash TEXT,
            hash_version TEXT,
            result_payload TEXT NOT NULL,
            processed_at INTEGER NOT NULL DEFAULT 1700000000
          );
          CREATE TABLE devices (
            device_id TEXT NOT NULL PRIMARY KEY,
            name TEXT NOT NULL,
            token_hash TEXT NOT NULL,
            salt TEXT NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1,
            is_confirmed INTEGER NOT NULL DEFAULT 1,
            created_at INTEGER NOT NULL DEFAULT 1700000000,
            last_used_at INTEGER,
            expires_at INTEGER,
            last_product_sync_at INTEGER,
            last_committed_client_seq INTEGER NOT NULL DEFAULT 0,
            max_seen_client_seq INTEGER NOT NULL DEFAULT 0,
            last_committed_at INTEGER,
            role TEXT NOT NULL DEFAULT 'CASHIER'
          );
          CREATE TABLE hub_metadata (
            key TEXT NOT NULL PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at INTEGER NOT NULL DEFAULT 1700000000
          );
          CREATE TABLE device_audit_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id TEXT NOT NULL,
            action TEXT NOT NULL,
            details TEXT,
            created_at INTEGER NOT NULL DEFAULT 1700000000
          );
          PRAGMA user_version = 3;
        ''');
        raw.execute(
          "INSERT INTO products (id, barcode, name, price, stock) VALUES ('prod_legacy_v3', '8690000333333', 'V3 Eski Ürün', 1500, 10000);",
        );
        raw.close();

        final db = SpikeDatabase(dbFile);
        final products = await db.select(db.products).get();
        expect(products.length, equals(1));
        expect(products.first.name, equals('V3 Eski Ürün'));

        final backfilled = await db.select(db.productBarcodes).get();
        expect(backfilled.length, equals(1));
        expect(backfilled.first.productId, equals('prod_legacy_v3'));
        expect(backfilled.first.barcode, equals('8690000333333'));
        expect(backfilled.first.isPrimary, isTrue);
        expect(backfilled.first.isActive, isTrue);
        await db.close();
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });

    test('Çoklu barkod upsert, GET /api/v1/products döndürme, duplicate barkod reddi (409) ve idempotent replay', () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      configureSqliteNative();
      final tempDir = await Directory.systemTemp.createTemp('mms_test_only_a1_barcodes_');
      late SpikeDatabase db;
      late SpikeServer server;
      try {
        final dbFile = File(p.join(tempDir.path, 'hub_barcodes.db'));
        final pepperManager = PepperManager(File(p.join(tempDir.path, 'pepper.dpapi')))
          ..initialize();
        db = SpikeDatabase(dbFile);
        final queue = WriteQueue();
        const validToken = 'test_only_barcode_sync_tok';
        final salt = TokenManager.generateSalt();
        final hash = TokenManager.hashToken(
          rawToken: validToken,
          salt: salt,
          pepper: pepperManager.pepper,
        );
        await db.into(db.devices).insert(
          DevicesCompanion(
            deviceId: const Value('DEV_BC_TEST'),
            name: const Value('Barcode Sync Test'),
            tokenHash: Value(hash),
            salt: Value(salt),
            isActive: const Value(true),
            isConfirmed: const Value(true),
          ),
        );

        server = SpikeServer(
          db: db,
          dbFile: dbFile,
          writeQueue: queue,
          backupDirectory: p.join(tempDir.path, 'backups'),
          pepperManager: pepperManager,
          requireTls: false,
        );
        const port = 18982;
        await server.start(port: port, enableDiscovery: false);
        final baseUrl = 'http://127.0.0.1:$port';

        final payload = {
          'client_seq': 1,
          'operation_id': 'op_multi_bc_1',
          'operation_type': 'PRODUCT_UPSERT',
          'product': {
            'id': 'prod_multi_01',
            'name': 'Çoklu Barkodlu Çay',
            'barcode': '8691111111111',
            'price': 9900,
            'stock': 20000,
            'stock_unit': 'adet',
            'pricing_unit': 'adet',
            'conversion_factor_numerator': 1,
            'conversion_factor_denominator': 1,
            'is_active': true,
            'barcodes': ['8691111111111', '8692222222222', '8693333333333'],
          },
        };

        final res1 = await http.post(
          Uri.parse('$baseUrl/api/v1/products/upsert'),
          headers: {
            'Authorization': 'Bearer $validToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(payload),
        );
        expect(res1.statusCode, equals(200));

        // Idempotent replay
        final replay = await http.post(
          Uri.parse('$baseUrl/api/v1/products/upsert'),
          headers: {
            'Authorization': 'Bearer $validToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(payload),
        );
        expect(replay.statusCode, equals(200));
        expect(replay.headers['x-mms-idempotent-replay'], equals('true'));

        // GET /api/v1/products tüm aktif ikincil barkodları dönmeli
        final getRes = await http.get(
          Uri.parse('$baseUrl/api/v1/products'),
          headers: {'Authorization': 'Bearer $validToken'},
        );
        expect(getRes.statusCode, equals(200));
        final body = jsonDecode(getRes.body) as Map<String, dynamic>;
        final prods = (body['products'] as List).cast<Map<String, dynamic>>();
        expect(prods.length, equals(1));
        expect(
          prods.first['barcodes'],
          containsAll(['8691111111111', '8692222222222', '8693333333333']),
        );

        // Başka ürün aynı ikincil barkodu almaya çalışırsa 409 ERR_DUPLICATE_BARCODE
        final dupRes = await http.post(
          Uri.parse('$baseUrl/api/v1/products/upsert'),
          headers: {
            'Authorization': 'Bearer $validToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'client_seq': 2,
            'operation_id': 'op_multi_bc_dup',
            'operation_type': 'PRODUCT_UPSERT',
            'product': {
              'id': 'prod_multi_02',
              'name': 'Çakışan Ürün',
              'barcode': '8699999999999',
              'price': 500,
              'barcodes': ['8699999999999', '8692222222222'],
            },
          }),
        );
        expect(dupRes.statusCode, equals(409));
        expect(jsonDecode(dupRes.body)['code'], equals('ERR_DUPLICATE_BARCODE'));

        // Barkod kaldırma senkronizasyonu: sadece primary + tek alternatif bırak (dupRes 409 aldığı için sıradaki client_seq=2)
        final removeRes = await http.post(
          Uri.parse('$baseUrl/api/v1/products/upsert'),
          headers: {
            'Authorization': 'Bearer $validToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'client_seq': 2,
            'operation_id': 'op_multi_bc_rm',
            'operation_type': 'PRODUCT_UPSERT',
            'product': {
              'id': 'prod_multi_01',
              'name': 'Çoklu Barkodlu Çay',
              'barcode': '8691111111111',
              'price': 9900,
              'barcodes': ['8691111111111', '8693333333333'],
            },
          }),
        );
        expect(removeRes.statusCode, equals(200));

        final afterRemove = await http.get(
          Uri.parse('$baseUrl/api/v1/products'),
          headers: {'Authorization': 'Bearer $validToken'},
        );
        final prodsAfter = ((jsonDecode(afterRemove.body) as Map<String, dynamic>)['products'] as List)
            .cast<Map<String, dynamic>>();
        expect(prodsAfter.first['barcodes'], equals(['8691111111111', '8693333333333']));

        // Son barkodların tamamı silindiğinde (istemci: barcode null + barcodes [])
        // Hub eski birincil barkoda geri DÜŞMEMELİ; silinen barkodlar istemciye
        // ürün indirmesinde geri dirilmemelidir.
        final removeAllRes = await http.post(
          Uri.parse('$baseUrl/api/v1/products/upsert'),
          headers: {
            'Authorization': 'Bearer $validToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'client_seq': 3,
            'operation_id': 'op_multi_bc_rm_all',
            'operation_type': 'PRODUCT_UPSERT',
            'product': {
              'id': 'prod_multi_01',
              'name': 'Çoklu Barkodlu Çay',
              'barcode': null,
              'price': 9900,
              'barcodes': <String>[],
            },
          }),
        );
        expect(removeAllRes.statusCode, equals(200), reason: removeAllRes.body);

        final afterRemoveAll = await http.get(
          Uri.parse('$baseUrl/api/v1/products'),
          headers: {'Authorization': 'Bearer $validToken'},
        );
        final prodAfterAll = ((jsonDecode(afterRemoveAll.body) as Map<String, dynamic>)['products']
                as List)
            .cast<Map<String, dynamic>>()
            .single;
        expect(prodAfterAll['barcode'], isNot(anyOf('8691111111111', '8693333333333')));
        expect(
          prodAfterAll['barcodes'],
          isNot(anyElement(anyOf('8691111111111', '8693333333333'))),
        );
        // Silinen barkod geçmişi korunur (BR-PROD-15): satırlar pasif, silinmez.
        final inactiveRows = await (db.select(db.productBarcodes)
              ..where((b) => b.productId.equals('prod_multi_01') & b.isActive.equals(false)))
            .get();
        expect(
          inactiveRows.map((r) => r.barcode),
          containsAll(['8691111111111', '8692222222222', '8693333333333']),
        );

        await server.stop();
        await db.close();
      } finally {
        if (tempDir.existsSync()) {
          try {
            tempDir.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
    });
  });
}
