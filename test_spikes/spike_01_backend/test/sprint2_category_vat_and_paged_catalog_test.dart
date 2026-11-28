import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw_sqlite;
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/pepper_manager.dart';
import '../lib/security/token_manager.dart';

void main() {
  group('Sprint 2: Hub DB v5 Migration, KDV/Kategori Senkronizasyonu ve Sayfalı Katalog', () {
    test('MMS-001 Migration: Hub DB v4 -> v5 geçişi mevcut ürünleri vat_rate=20 ve category_id=null ile korur', () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      configureSqliteNative();
      final tempDir = await Directory.systemTemp.createTemp('mms_test_v4_v5_mig_');
      try {
        final dbFile = File(p.join(tempDir.path, 'legacy_v4.db'));
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
          CREATE TABLE product_barcodes (
            id TEXT NOT NULL PRIMARY KEY,
            product_id TEXT NOT NULL REFERENCES products(id),
            barcode TEXT NOT NULL UNIQUE,
            is_primary INTEGER NOT NULL DEFAULT 0,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at INTEGER NOT NULL DEFAULT 1700000000
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
          CREATE TABLE refunds (
            id TEXT NOT NULL PRIMARY KEY,
            sale_id TEXT NOT NULL REFERENCES sales(id),
            device_id TEXT NOT NULL,
            client_seq INTEGER NOT NULL,
            total_refund_amount INTEGER NOT NULL,
            payment_method TEXT NOT NULL,
            reason TEXT NOT NULL,
            created_at INTEGER NOT NULL DEFAULT 1700000000
          );
          CREATE TABLE refund_items (
            id TEXT NOT NULL PRIMARY KEY,
            refund_id TEXT NOT NULL REFERENCES refunds(id),
            sale_item_id TEXT,
            product_id TEXT NOT NULL REFERENCES products(id),
            quantity INTEGER NOT NULL,
            unit_price INTEGER NOT NULL,
            refund_amount INTEGER NOT NULL,
            product_condition TEXT NOT NULL DEFAULT 'SELLABLE',
            created_at INTEGER NOT NULL DEFAULT 1700000000
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
          PRAGMA user_version = 4;
        ''');
        raw.execute(
          "INSERT INTO products (id, barcode, name, price, stock) VALUES ('prod_v4_1', '8690000444444', 'V4 Mevcut Ürün', 2500, 12000);",
        );
        raw.close();

        final db = SpikeDatabase(dbFile);
        expect(db.schemaVersion, equals(5));

        final products = await db.select(db.products).get();
        expect(products, hasLength(1));
        expect(products.first.name, equals('V4 Mevcut Ürün'));
        expect(products.first.price, equals(2500));
        expect(products.first.vatRate, equals(20));
        expect(products.first.categoryId, isNull);

        // Categories tablosunun oluşturulmuş ve kullanılabilir olduğunu doğrula
        final cats = await db.select(db.categories).get();
        expect(cats, isEmpty);
        await db.close();
      } finally {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });

    test('MMS-001 E2E (2 Cihaz): Cihaz 1 kategori ("Temel Gıda") + %1 KDV ürün oluşturur -> Hub -> Cihaz 2 eksiksiz çeker', () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      configureSqliteNative();
      final tempDir = await Directory.systemTemp.createTemp('mms_test_cat_vat_e2e_');
      late SpikeDatabase hubDb;
      late SpikeServer server;
      late ClientDatabase dev1Db;
      late ClientDatabase dev2Db;
      try {
        final dbFile = File(p.join(tempDir.path, 'hub_cat_vat.db'));
        final pepperManager =
            PepperManager(File(p.join(tempDir.path, 'pepper.dpapi')))..initialize();
        hubDb = SpikeDatabase(dbFile);
        final queue = WriteQueue();

        const tok1 = 'tok_dev_cat_1';
        const tok2 = 'tok_dev_cat_2';
        for (final entry in [('DEV-CAT-1', tok1), ('DEV-CAT-2', tok2)]) {
          final salt = TokenManager.generateSalt();
          final hash = TokenManager.hashToken(
            rawToken: entry.$2,
            salt: salt,
            pepper: pepperManager.pepper,
          );
          await hubDb.into(hubDb.devices).insert(
                DevicesCompanion.insert(
                  deviceId: entry.$1,
                  name: entry.$1,
                  tokenHash: hash,
                  salt: salt,
                ),
              );
        }

        final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final serverPort = socket.port;
        await socket.close();

        server = SpikeServer(
          db: hubDb,
          dbFile: dbFile,
          writeQueue: queue,
          backupDirectory: p.join(tempDir.path, 'backups'),
          pepperManager: pepperManager,
          adminSecret: 'admin_cat_vat_e2e',
          requireTenantStoreHeaders: true,
        );
        await server.start(
          address: InternetAddress.loopbackIPv4,
          port: serverPort,
          enableDiscovery: false,
        );
        final hubUrl = 'http://127.0.0.1:$serverPort';

        dev1Db = ClientDatabase.forTesting(NativeDatabase.memory());
        dev2Db = ClientDatabase.forTesting(NativeDatabase.memory());
        final repo1 = ClientStorageRepository(dev1Db);
        final repo2 = ClientStorageRepository(dev2Db);
        await repo1.initializeDevice('DEV-CAT-1');
        await repo2.initializeDevice('DEV-CAT-2');

        final sync1 = ClientSyncService(
          repository: repo1,
          transport: HttpSyncTransport.forStore(
            tenantId: 'default-tenant',
            storeId: 'default-store',
          ),
          deviceId: 'DEV-CAT-1',
          deviceToken: tok1,
          hubUrl: hubUrl,
        );
        final sync2 = ClientSyncService(
          repository: repo2,
          transport: HttpSyncTransport.forStore(
            tenantId: 'default-tenant',
            storeId: 'default-store',
          ),
          deviceId: 'DEV-CAT-2',
          deviceToken: tok2,
          hubUrl: hubUrl,
        );

        // 1. Cihaz 1: "Temel Gıda" kategorisi + %1 KDV'li ürün
        final cat = await repo1.createCategory(
          name: 'Temel Gıda',
          deviceId: 'DEV-CAT-1',
        );
        final prod = await repo1.createProduct(
          name: 'Osmancık Pirinç 1kg',
          price: 6500,
          barcode: '8690000111222',
          categoryId: cat.id,
          initialStock: 10000,
          vatRate: 1,
          deviceId: 'DEV-CAT-1',
        );

        final batch1 = await sync1.syncPendingOutbox();
        expect(batch1.isCleanSuccess, isTrue);
        expect(batch1.syncedCount, equals(2));

        // 2. Cihaz 2: syncProducts() ile kategori + ürün + KDV %1 çeker
        final downloadedCount = await sync2.syncProducts();
        expect(downloadedCount, equals(1));

        final dev2Cat = await repo2.getCategoryById(cat.id);
        expect(dev2Cat, isNotNull);
        expect(dev2Cat!.name, equals('Temel Gıda'));
        expect(dev2Cat.isActive, isTrue);

        final dev2Prod = await repo2.getProductById(prod.id);
        expect(dev2Prod, isNotNull);
        expect(dev2Prod!.categoryId, equals(cat.id));
        expect(dev2Prod.vatRate, equals(1));

        // 3. Cihaz 1 kategoriyi günceller -> Cihaz 2 güncel adını alır (idempotent sync)
        await repo1.updateCategory(
          id: cat.id,
          name: 'Temel Gıda & Bakliyat',
          deviceId: 'DEV-CAT-1',
        );
        final batch1b = await sync1.syncPendingOutbox();
        expect(batch1b.syncedCount, equals(1));

        await sync2.syncProducts();
        final dev2CatUpdated = await repo2.getCategoryById(cat.id);
        expect(dev2CatUpdated?.name, equals('Temel Gıda & Bakliyat'));
      } finally {
        await dev1Db.close();
        await dev2Db.close();
        await server.stop();
        await hubDb.close();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });

    test('MMS-001 & MMS-005 API: Sayfalı GET /api/v1/products, geçersiz vat_rate 400 ve eksik category_id FK koruması', () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      configureSqliteNative();
      final tempDir = await Directory.systemTemp.createTemp('mms_test_paged_api_');
      late SpikeDatabase hubDb;
      late SpikeServer server;
      try {
        final dbFile = File(p.join(tempDir.path, 'hub_paged_api.db'));
        final pepperManager =
            PepperManager(File(p.join(tempDir.path, 'pepper.dpapi')))..initialize();
        hubDb = SpikeDatabase(dbFile);
        final queue = WriteQueue();

        const tok = 'tok_paged_api_1';
        final salt = TokenManager.generateSalt();
        final hash = TokenManager.hashToken(
          rawToken: tok,
          salt: salt,
          pepper: pepperManager.pepper,
        );
        await hubDb.into(hubDb.devices).insert(
              DevicesCompanion.insert(
                deviceId: 'DEV-API-1',
                name: 'DEV-API-1',
                tokenHash: hash,
                salt: salt,
              ),
            );

        final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final serverPort = socket.port;
        await socket.close();

        server = SpikeServer(
          db: hubDb,
          dbFile: dbFile,
          writeQueue: queue,
          backupDirectory: p.join(tempDir.path, 'backups'),
          pepperManager: pepperManager,
          adminSecret: 'admin_paged_api',
        );
        await server.start(
          address: InternetAddress.loopbackIPv4,
          port: serverPort,
          enableDiscovery: false,
        );
        final baseUrl = 'http://127.0.0.1:$serverPort';
        final headers = {
          'content-type': 'application/json',
          'authorization': 'Bearer $tok',
        };

        // 1. Geçersiz vat_rate=101 -> 400 ERR_INVALID_VAT_RATE
        final badVatRes = await http.post(
          Uri.parse('$baseUrl/api/v1/products/upsert'),
          headers: headers,
          body: jsonEncode({
            'client_seq': 1,
            'operation_id': 'op_bad_vat',
            'product': {
              'id': 'prod_bad_vat',
              'name': 'Hatalı KDV',
              'price': 1000,
              'vat_rate': 101,
            },
          }),
        );
        expect(badVatRes.statusCode, equals(400));
        expect(badVatRes.body, contains('ERR_INVALID_VAT_RATE'));

        // 2. Hub'da henüz olmayan category_id ile 5 ürün ekle -> FK hatası olmadan başarılı
        for (var i = 1; i <= 5; i++) {
          final res = await http.post(
            Uri.parse('$baseUrl/api/v1/products/upsert'),
            headers: headers,
            body: jsonEncode({
              'client_seq': i,
              'operation_id': 'op_p_$i',
              'product': {
                'id': 'prod_page_$i',
                'name': 'Ürün $i',
                'barcode': '869000090000$i',
                'category_id': 'cat_auto_fk',
                'price': 1000 * i,
                'vat_rate': 10,
              },
            }),
          );
          expect(res.statusCode, equals(200));
        }

        // 3. Parametresiz GET /api/v1/products -> geriye uyumlu tam liste
        final fullRes = await http.get(
          Uri.parse('$baseUrl/api/v1/products'),
          headers: headers,
        );
        expect(fullRes.statusCode, equals(200));
        final fullJson = jsonDecode(fullRes.body) as Map<String, dynamic>;
        expect((fullJson['products'] as List), hasLength(5));
        expect(fullJson.containsKey('has_more'), isFalse);
        expect((fullJson['categories'] as List), hasLength(1));
        expect((fullJson['categories'] as List).first['id'], equals('cat_auto_fk'));

        // 4. Sayfalı GET /api/v1/products?limit=2&offset=0 -> 3 sayfada 5 ürün
        final collectedIds = <String>[];
        var offset = 0;
        var pageCount = 0;
        while (true) {
          final pageRes = await http.get(
            Uri.parse('$baseUrl/api/v1/products?limit=2&offset=$offset'),
            headers: headers,
          );
          expect(pageRes.statusCode, equals(200));
          final pageJson = jsonDecode(pageRes.body) as Map<String, dynamic>;
          expect(pageJson['total_count'], equals(5));
          final list = (pageJson['products'] as List).cast<Map<String, dynamic>>();
          for (final item in list) {
            expect(item['category_id'], equals('cat_auto_fk'));
            expect(item['vat_rate'], equals(10));
            collectedIds.add(item['id'] as String);
          }
          pageCount++;
          if (pageJson['has_more'] != true) {
            expect(pageJson['sync_session_id'], isNotNull);
            break;
          }
          offset = pageJson['next_offset'] as int;
        }
        expect(pageCount, equals(3));
        expect(collectedIds, hasLength(5));
      } finally {
        await server.stop();
        await hubDb.close();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });
  });
}
