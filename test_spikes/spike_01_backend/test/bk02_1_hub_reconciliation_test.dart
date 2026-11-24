import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:http/http.dart' as http;
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/pepper_manager.dart';
import '../lib/security/token_manager.dart';
import '../lib/sync/canonical_payload_hasher.dart';
import '../lib/sync/device_sequence_inspector.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    configureSqliteNative();
  });

  Future<void> seedDeviceAndProducts({
    required SpikeDatabase db,
    required PepperManager pepperManager,
    required String deviceId,
    required String token,
    bool seedProducts = true,
  }) async {
    if (seedProducts) {
      await db.into(db.products).insertOnConflictUpdate(
            ProductsCompanion(
              id: const Value('prod_kola'),
              barcode: const Value('8690001001'),
              name: const Value('Kutu Kola 330ml'),
              price: const Value(2500),
              stock: const Value(100000),
              stockUnit: const Value('adet'),
              pricingUnit: const Value('adet'),
              conversionFactorNumerator: const Value(1),
              conversionFactorDenominator: const Value(1),
            ),
          );
    }

    final salt = TokenManager.generateSalt();
    final hash = TokenManager.hashToken(
      rawToken: token,
      salt: salt,
      pepper: pepperManager.pepper,
    );
    await db.into(db.devices).insertOnConflictUpdate(
          DevicesCompanion(
            deviceId: Value(deviceId),
            name: Value('Test Device $deviceId'),
            tokenHash: Value(hash),
            salt: Value(salt),
            isActive: const Value(true),
            isConfirmed: const Value(true),
          ),
        );
  }

  Map<String, String> authTenantHeaders(
    String token, {
    String tenantId = SpikeServer.defaultTenantId,
    String storeId = SpikeServer.defaultStoreId,
  }) =>
      {
        'content-type': 'application/json',
        'authorization': 'Bearer $token',
        'x-mms-tenant-id': tenantId,
        'x-mms-store-id': storeId,
      };

  group('BK-02.1 Grup 1 — Hub v1 -> v2 Migration ve Veri Koruma', () {
    test(
      '1.1. Ham v1 DB verileri korunur, {1,2,3,5} boşluğunda HWM=3/max=5 olur ve eksik __request_hash NULL kalır',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('bk02_mig_v1_');
        addTearDown(() => tempDir.delete(recursive: true));
        final dbFile = File(p.join(tempDir.path, 'legacy_v1.db'));
        final pepper = PepperManager(File(p.join(tempDir.path, 'pepper.dpapi')))
          ..initialize();

        const devId = 'POS-LEGACY-01';
        const token = 'tok_legacy_01';
        final salt = TokenManager.generateSalt();
        final tokenHash = TokenManager.hashToken(
          rawToken: token,
          salt: salt,
          pepper: pepper.pepper,
        );

        final v1HashSeq1 = SpikeServer.computeSaleRequestHash({
          'client_seq': 1,
          'total_amount': 2500,
          'payment_method': 'CASH',
          'items': [
            {
              'product_id': 'prod_kola',
              'quantity': 1000,
              'unit_price': 2500,
              'total_price': 2500,
            }
          ],
        });
        const v1HashSeq2 =
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

        // Gerçek v1 SQLite şeması (user_version = 1) oluştur
        final raw = sqlite.sqlite3.open(dbFile.path);
        raw.execute('''
          PRAGMA journal_mode = WAL;
          PRAGMA user_version = 1;
          CREATE TABLE products (
            id TEXT NOT NULL PRIMARY KEY,
            barcode TEXT NOT NULL,
            name TEXT NOT NULL,
            price INTEGER NOT NULL,
            price_version_id TEXT NOT NULL DEFAULT 'pv_init',
            stock INTEGER NOT NULL,
            stock_unit TEXT NOT NULL DEFAULT 'adet',
            pricing_unit TEXT NOT NULL DEFAULT 'adet',
            conversion_factor_numerator INTEGER NOT NULL DEFAULT 1,
            conversion_factor_denominator INTEGER NOT NULL DEFAULT 1,
            is_active INTEGER NOT NULL DEFAULT 1,
            updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
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
            created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
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
            created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
          );
          CREATE TABLE product_price_histories (
            id TEXT NOT NULL PRIMARY KEY,
            product_id TEXT NOT NULL REFERENCES products(id),
            price INTEGER NOT NULL,
            valid_from INTEGER NOT NULL,
            valid_until INTEGER,
            created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
          );
          CREATE TABLE product_sync_sessions (
            id TEXT NOT NULL PRIMARY KEY,
            device_id TEXT NOT NULL,
            product_count INTEGER NOT NULL,
            synced_at INTEGER NOT NULL,
            is_acknowledged INTEGER NOT NULL DEFAULT 0,
            acknowledged_at INTEGER,
            created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
          );
          CREATE TABLE processed_operations (
            operation_id TEXT NOT NULL PRIMARY KEY,
            device_id TEXT NOT NULL,
            idempotency_key TEXT NOT NULL UNIQUE,
            result_payload TEXT NOT NULL,
            processed_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
          );
          CREATE TABLE devices (
            device_id TEXT NOT NULL PRIMARY KEY,
            name TEXT NOT NULL,
            token_hash TEXT NOT NULL,
            salt TEXT NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1,
            is_confirmed INTEGER NOT NULL DEFAULT 1,
            created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
            last_used_at INTEGER,
            expires_at INTEGER,
            last_product_sync_at INTEGER,
            role TEXT NOT NULL DEFAULT 'CASHIER'
          );
          CREATE TABLE device_audit_logs (
            id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
            device_id TEXT NOT NULL,
            action TEXT NOT NULL,
            details TEXT,
            created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
          );
        ''');

        raw.execute('''
          INSERT INTO products (id, barcode, name, price, stock) VALUES
            ('prod_kola', '8690001001', 'Kutu Kola', 2500, 99000);
          INSERT INTO devices (device_id, name, token_hash, salt, is_active, is_confirmed) VALUES
            ('$devId', 'Legacy Kasa', '$tokenHash', '$salt', 1, 1);
          INSERT INTO sales (id, device_id, client_seq, total_amount, payment_method, server_seq) VALUES
            ('sale_leg_1', '$devId', 1, 2500, 'CASH', 1),
            ('sale_leg_5', '$devId', 5, 2500, 'CASH', 2);
          INSERT INTO processed_operations (operation_id, device_id, idempotency_key, result_payload, processed_at) VALUES
            ('op_1', '$devId', '$devId:1', '${jsonEncode({
              'status': 'COMMITTED',
              'sale_id': 'sale_leg_1',
              'client_seq': 1,
              'total_amount': 2500,
              '__request_hash': v1HashSeq1,
            })}', 1700000001),
            ('op_2', '$devId', '$devId:2', '${jsonEncode({
              'status': 'COMMITTED',
              'operation_type': 'PRODUCT_UPSERT',
              'product_id': 'prod_kola',
              '__request_hash': v1HashSeq2,
            })}', 1700000002),
            ('op_3', '$devId', '$devId:3', '${jsonEncode({
              'status': 'COMMITTED',
              'operation_type': 'SALE_CANCEL',
              'sale_id': 'sale_leg_1',
              'client_seq': 3,
            })}', 1700000003),
            ('op_5', '$devId', '$devId:5', '${jsonEncode({
              'status': 'COMMITTED',
              'sale_id': 'sale_leg_5',
              'client_seq': 5,
              'total_amount': 2500,
            })}', 1700000005);
        ''');
        raw.close();

        // Drift v2 veritabanı açılışı v1 -> v2 migration'ı tetikler
        final db = SpikeDatabase(dbFile);
        try {
          final products = await db.select(db.products).get();
          expect(products.length, equals(1));
          expect(products.single.stock, equals(99000));

          final sales = await db.select(db.sales).get();
          expect(sales.length, equals(2));

          final ops = await (db.select(db.processedOperations)
                ..orderBy([(o) => OrderingTerm.asc(o.clientSeq)]))
              .get();
          expect(ops.length, equals(4));

          expect(ops[0].clientSeq, equals(1));
          expect(ops[0].operationType, equals('SALE_CREATE'));
          expect(ops[0].requestHash, equals(v1HashSeq1));
          expect(ops[0].hashVersion, equals('v1_legacy'));

          expect(ops[1].clientSeq, equals(2));
          expect(ops[1].operationType, equals('PRODUCT_UPSERT'));
          expect(ops[1].requestHash, equals(v1HashSeq2));
          expect(ops[1].hashVersion, equals('v1_legacy'));

          // seq=3 (__request_hash yok): kesinlikle NULL kalmalı, tahmin edilmemeli
          expect(ops[2].clientSeq, equals(3));
          expect(ops[2].operationType, equals('SALE_CANCEL'));
          expect(ops[2].requestHash, isNull);
          expect(ops[2].hashVersion, isNull);

          // seq=5 (__request_hash yok): NULL kalmalı
          expect(ops[3].clientSeq, equals(5));
          expect(ops[3].operationType, equals('SALE_CREATE'));
          expect(ops[3].requestHash, isNull);
          expect(ops[3].hashVersion, isNull);

          // Cihaz HWM {1, 2, 3, 5} -> HWM = 3, max_seen = 5
          final dev = await (db.select(db.devices)
                ..where((d) => d.deviceId.equals(devId)))
              .getSingle();
          expect(dev.lastCommittedClientSeq, equals(3));
          expect(dev.maxSeenClientSeq, equals(5));
          expect(dev.lastCommittedAt, isNotNull);
        } finally {
          await db.close();
        }

        // v1 -> v2 -> v3 -> v4 zinciri: user_version = 4, v3 sütunları ve v4 product_barcodes eklenmiş olmalı
        final rawCheck = sqlite.sqlite3.open(dbFile.path);
        try {
          expect(rawCheck.select('PRAGMA user_version;').first.values.first, equals(4));
          final movementCols = rawCheck
              .select("PRAGMA table_info('stock_movements');")
              .map((r) => r['name'])
              .toSet();
          expect(movementCols, containsAll(['purchase_price', 'note']));
          final pbTables = rawCheck.select(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='product_barcodes';",
          );
          expect(pbTables.length, equals(1));
        } finally {
          rawCheck.close();
        }
      },
    );

    test(
      '1.2. Geçersiz idempotency_key içeren bozuk v1 DB migration sırasında hatayı gizlemez (fail-closed)',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('bk02_mig_bad_');
        addTearDown(() => tempDir.delete(recursive: true));
        final dbFile = File(p.join(tempDir.path, 'corrupt_v1.db'));

        final raw = sqlite.sqlite3.open(dbFile.path);
        raw.execute('''
          PRAGMA user_version = 1;
          CREATE TABLE products (
            id TEXT NOT NULL PRIMARY KEY,
            barcode TEXT NOT NULL,
            name TEXT NOT NULL,
            price INTEGER NOT NULL,
            price_version_id TEXT NOT NULL DEFAULT 'pv_init',
            stock INTEGER NOT NULL,
            stock_unit TEXT NOT NULL DEFAULT 'adet',
            pricing_unit TEXT NOT NULL DEFAULT 'adet',
            conversion_factor_numerator INTEGER NOT NULL DEFAULT 1,
            conversion_factor_denominator INTEGER NOT NULL DEFAULT 1,
            is_active INTEGER NOT NULL DEFAULT 1,
            updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
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
            created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
          );
          CREATE TABLE sale_items (id TEXT NOT NULL PRIMARY KEY, sale_id TEXT NOT NULL, product_id TEXT NOT NULL, quantity INTEGER NOT NULL, unit_price INTEGER NOT NULL, total_price INTEGER NOT NULL);
          CREATE TABLE stock_movements (id TEXT NOT NULL PRIMARY KEY, product_id TEXT NOT NULL, quantity INTEGER NOT NULL, unit TEXT NOT NULL, movement_type TEXT NOT NULL, reference_id TEXT NOT NULL, created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')));
          CREATE TABLE product_price_histories (id TEXT NOT NULL PRIMARY KEY, product_id TEXT NOT NULL, price INTEGER NOT NULL, valid_from INTEGER NOT NULL, valid_until INTEGER, created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')));
          CREATE TABLE product_sync_sessions (id TEXT NOT NULL PRIMARY KEY, device_id TEXT NOT NULL, product_count INTEGER NOT NULL, synced_at INTEGER NOT NULL, is_acknowledged INTEGER NOT NULL DEFAULT 0, acknowledged_at INTEGER, created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')));
          CREATE TABLE processed_operations (
            operation_id TEXT NOT NULL PRIMARY KEY,
            device_id TEXT NOT NULL,
            idempotency_key TEXT NOT NULL UNIQUE,
            result_payload TEXT NOT NULL,
            processed_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
          );
          CREATE TABLE devices (
            device_id TEXT NOT NULL PRIMARY KEY,
            name TEXT NOT NULL,
            token_hash TEXT NOT NULL,
            salt TEXT NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1,
            is_confirmed INTEGER NOT NULL DEFAULT 1,
            created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
            last_used_at INTEGER,
            expires_at INTEGER,
            last_product_sync_at INTEGER,
            role TEXT NOT NULL DEFAULT 'CASHIER'
          );
          CREATE TABLE device_audit_logs (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, device_id TEXT NOT NULL, action TEXT NOT NULL, details TEXT, created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')));
          INSERT INTO processed_operations (operation_id, device_id, idempotency_key, result_payload)
          VALUES ('op_bad', 'DEV_1', 'BOZUK_ANAHTAR_NO_COLON', '{}');
        ''');
        raw.close();

        final db = SpikeDatabase(dbFile);
        try {
          await expectLater(
            db.select(db.devices).get(),
            throwsA(
              predicate<Object>(
                (e) =>
                    e.toString().contains('Hub v1 -> v2 Migration Hatası') &&
                    e.toString().contains('BOZUK_ANAHTAR_NO_COLON'),
              ),
            ),
          );
        } finally {
          await db.close();
        }
      },
    );

    test(
      '1.3. Eski v1 şifreli Hub yedeği /api/v1/admin/restore ile staging DB üzerinden v2\'ye yükseltilir',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('bk02_v1_restore_');
        addTearDown(() => tempDir.delete(recursive: true));
        final backupDir = Directory(p.join(tempDir.path, 'backups'));
        final v1SourceDbPath = p.join(tempDir.path, 'v1_src.db');
        final liveDbFile = File(p.join(tempDir.path, 'live_v2.db'));
        final pepper = PepperManager(File(p.join(tempDir.path, 'pepper.dpapi')))
          ..initialize();

        // 1. Ham v1 DB oluştur ve şifreli backup (schemaVersion=1) üret
        final rawV1 = sqlite.sqlite3.open(v1SourceDbPath);
        rawV1.execute('''
          PRAGMA user_version = 1;
          CREATE TABLE products (id TEXT NOT NULL PRIMARY KEY, barcode TEXT NOT NULL, name TEXT NOT NULL, price INTEGER NOT NULL, price_version_id TEXT NOT NULL DEFAULT 'pv_init', stock INTEGER NOT NULL, stock_unit TEXT NOT NULL DEFAULT 'adet', pricing_unit TEXT NOT NULL DEFAULT 'adet', conversion_factor_numerator INTEGER NOT NULL DEFAULT 1, conversion_factor_denominator INTEGER NOT NULL DEFAULT 1, is_active INTEGER NOT NULL DEFAULT 1, updated_at INTEGER NOT NULL DEFAULT 1700000000);
          CREATE TABLE sales (id TEXT NOT NULL PRIMARY KEY, device_id TEXT NOT NULL, client_seq INTEGER NOT NULL, total_amount INTEGER NOT NULL, payment_method TEXT NOT NULL, server_seq INTEGER, status TEXT NOT NULL DEFAULT 'COMPLETED', cancel_reason TEXT, cancelled_at INTEGER, created_at INTEGER NOT NULL DEFAULT 1700000000);
          CREATE TABLE sale_items (id TEXT NOT NULL PRIMARY KEY, sale_id TEXT NOT NULL, product_id TEXT NOT NULL, quantity INTEGER NOT NULL, unit_price INTEGER NOT NULL, total_price INTEGER NOT NULL);
          CREATE TABLE stock_movements (id TEXT NOT NULL PRIMARY KEY, product_id TEXT NOT NULL, quantity INTEGER NOT NULL, unit TEXT NOT NULL DEFAULT 'adet', movement_type TEXT NOT NULL, reference_id TEXT NOT NULL, created_at INTEGER NOT NULL DEFAULT 1700000000);
          CREATE TABLE product_price_histories (id TEXT NOT NULL PRIMARY KEY, product_id TEXT NOT NULL, price INTEGER NOT NULL, valid_from INTEGER NOT NULL DEFAULT 1700000000, valid_until INTEGER, created_at INTEGER NOT NULL DEFAULT 1700000000);
          CREATE TABLE product_sync_sessions (id TEXT NOT NULL PRIMARY KEY, device_id TEXT NOT NULL, product_count INTEGER NOT NULL, synced_at INTEGER NOT NULL, is_acknowledged INTEGER NOT NULL DEFAULT 0, acknowledged_at INTEGER, created_at INTEGER NOT NULL DEFAULT 1700000000);
          CREATE TABLE processed_operations (operation_id TEXT NOT NULL PRIMARY KEY, device_id TEXT NOT NULL, idempotency_key TEXT NOT NULL UNIQUE, result_payload TEXT NOT NULL, processed_at INTEGER NOT NULL DEFAULT 1700000000);
          CREATE TABLE devices (device_id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, token_hash TEXT NOT NULL, salt TEXT NOT NULL, is_active INTEGER NOT NULL DEFAULT 1, is_confirmed INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL DEFAULT 1700000000, last_used_at INTEGER, expires_at INTEGER, last_product_sync_at INTEGER, role TEXT NOT NULL DEFAULT 'CASHIER');
          CREATE TABLE device_audit_logs (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, device_id TEXT NOT NULL, action TEXT NOT NULL, details TEXT, created_at INTEGER NOT NULL DEFAULT 1700000000);
        ''');

        const devId = 'POS-V1-RESTORE';
        const rawTok = 'tok_v1_restore_123';
        final salt = TokenManager.generateSalt();
        final tokHash = TokenManager.hashToken(
          rawToken: rawTok,
          salt: salt,
          pepper: pepper.pepper,
        );
        final v1SaleHash = SpikeServer.computeSaleRequestHash({
          'client_seq': 1,
          'total_amount': 2500,
          'payment_method': 'CASH',
          'items': [
            {'product_id': 'prod_kola', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500}
          ],
        });
        rawV1.execute('''
          INSERT INTO products (id, barcode, name, price, stock) VALUES ('prod_kola', '8690001001', 'Kola', 2500, 99000);
          INSERT INTO devices (device_id, name, token_hash, salt, is_active, is_confirmed) VALUES ('$devId', 'Kasa', '$tokHash', '$salt', 1, 1);
          INSERT INTO sales (id, device_id, client_seq, total_amount, payment_method, server_seq) VALUES ('sale_v1_1', '$devId', 1, 2500, 'CASH', 1);
          INSERT INTO processed_operations (operation_id, device_id, idempotency_key, result_payload) VALUES
            ('op_v1_1', '$devId', '$devId:1', '${jsonEncode({'status': 'COMMITTED', 'sale_id': 'sale_v1_1', 'client_seq': 1, 'total_amount': 2500, '__request_hash': v1SaleHash})}');
        ''');
        rawV1.close();

        final backupStorage = LocalStorageProvider(backupDir);
        final backupResult = await DatabaseBackupEngine.createBackup(
          liveDbFile: File(v1SourceDbPath),
          executeVacuumInto: (snapPath) async {
            final src = sqlite.sqlite3.open(v1SourceDbPath);
            try {
              final escaped = snapPath.replaceAll("'", "''");
              src.execute("VACUUM INTO '$escaped';");
            } finally {
              src.close();
            }
          },
          deviceId: 'SERVER_HUB',
          tenantId: SpikeServer.defaultTenantId,
          storeId: SpikeServer.defaultStoreId,
          databaseType: DatabaseType.centralMaster,
          schemaVersion: 1,
          appVersion: '1.0.0',
          backupPassword: 'StrongPassword2026!',
          storageProvider: backupStorage,
          kdfIterations: 1000,
        );

        // 2. Canlı v2 sunucusunu başlat ve v1 yedeğini /api/v1/admin/restore ile geri yükle
        final liveDb = SpikeDatabase(liveDbFile);
        final queue = WriteQueue();
        final server = SpikeServer(
          db: liveDb,
          dbFile: liveDbFile,
          writeQueue: queue,
          backupDirectory: backupDir.path,
          adminSecret: 'adm_v1_restore_secret',
          pepperManager: pepper,
        );
        await server.start(address: InternetAddress.loopbackIPv4, port: 8961);
        addTearDown(() async {
          await server.stop();
        });

        final restoreRes = await http.post(
          Uri.parse('http://127.0.0.1:8961/api/v1/admin/restore'),
          headers: {
            'x-mms-admin-secret': 'adm_v1_restore_secret',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'backup_id': backupResult.backupId,
            'backup_password': 'StrongPassword2026!',
          }),
        );
        expect(restoreRes.statusCode, equals(200), reason: restoreRes.body);
        final restoreBody = jsonDecode(restoreRes.body) as Map<String, dynamic>;
        expect(restoreBody['restore_epoch'], isNotNull);
        expect(restoreBody['restore_epoch'], isNot(equals('epoch_0')));

        // AUD-MED-01: Restore sonrası eski cihaz tokenı geçersizleştirilir (401)
        final oldTokenStateRes = await http.get(
          Uri.parse('http://127.0.0.1:8961/api/v1/sync/device-state'),
          headers: authTenantHeaders(rawTok),
        );
        expect(oldTokenStateRes.statusCode, equals(401));

        // Cihaz kontrollü re-pair / yeni token ile yeniden onaylandığında v2 şemasında HWM=1 döner
        const renewedTok = 'tok_v1_restore_renewed_456';
        final newSalt = TokenManager.generateSalt();
        final newHash = TokenManager.hashToken(
          rawToken: renewedTok,
          salt: newSalt,
          pepper: pepper.pepper,
        );
        await server.writeQueue.enqueue(() async {
          await (server.db.update(server.db.devices)
                ..where((d) => d.deviceId.equals(devId)))
              .write(
            DevicesCompanion(
              tokenHash: Value(newHash),
              salt: Value(newSalt),
              isConfirmed: const Value(true),
              isActive: const Value(true),
            ),
          );
        });

        final stateRes = await http.get(
          Uri.parse('http://127.0.0.1:8961/api/v1/sync/device-state'),
          headers: authTenantHeaders(renewedTok),
        );
        expect(stateRes.statusCode, equals(200), reason: stateRes.body);
        final stateJson = jsonDecode(stateRes.body) as Map<String, dynamic>;
        expect(stateJson['restore_epoch'], equals(restoreBody['restore_epoch']));
        expect(stateJson['high_water_mark_seq'], equals(1));
        expect(stateJson['max_seen_client_seq'], equals(1));
        expect(stateJson['expected_next_client_seq'], equals(2));
      },
    );
  });

  group('BK-02.1 Grup 2 — 4 İşlem Türü, Atomik Receipt ve Canonical Hash', () {
    late Directory tempDir;
    late SpikeDatabase db;
    late WriteQueue writeQueue;
    late PepperManager pepperManager;
    late SpikeServer server;
    const port = 8962;
    const baseUrl = 'http://127.0.0.1:$port';
    const deviceId = 'POS-OPS-01';
    const token = 'tok_ops_01';

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('bk02_ops_');
      final dbFile = File(p.join(tempDir.path, 'master.db'));
      pepperManager = PepperManager(File(p.join(tempDir.path, 'pepper.dpapi')))
        ..initialize();
      db = SpikeDatabase(dbFile);
      writeQueue = WriteQueue();
      await seedDeviceAndProducts(
        db: db,
        pepperManager: pepperManager,
        deviceId: deviceId,
        token: token,
      );
      server = SpikeServer(
        db: db,
        dbFile: dbFile,
        writeQueue: writeQueue,
        backupDirectory: p.join(tempDir.path, 'backups'),
        pepperManager: pepperManager,
      );
      await server.start(address: InternetAddress.loopbackIPv4, port: port);
    });

    tearDown(() async {
      await server.stop();
      await db.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      '2.1. PRODUCT_UPSERT, SALE_CREATE, SALE_REFUND ve SALE_CANCEL aynı tx\'te receipt yazar ve HWM 1->2->3->4 ilerler',
      () async {
        // seq=1: PRODUCT_UPSERT
        final upsertRes = await http.post(
          Uri.parse('$baseUrl/api/v1/products/upsert'),
          headers: authTenantHeaders(token),
          body: jsonEncode({
            'client_seq': 1,
            'operation_id': 'op_prod_1',
            'operation_type': 'PRODUCT_UPSERT',
            'product': {
              'id': 'prod_ekmek',
              'name': 'Ekmek',
              'barcode': '869000999',
              'price': 1000,
              'stock': 50000,
              'stock_unit': 'adet',
              'pricing_unit': 'adet',
            },
          }),
        );
        expect(upsertRes.statusCode, equals(200), reason: upsertRes.body);
        expect((jsonDecode(upsertRes.body) as Map)['client_seq'], equals(1));

        // seq=2: SALE_CREATE
        final saleRes = await http.post(
          Uri.parse('$baseUrl/api/v1/sales'),
          headers: authTenantHeaders(token),
          body: jsonEncode({
            'operation_id': 'op_sale_2',
            'client_seq': 2,
            'total_amount': 2000,
            'payment_method': 'CASH',
            'items': [
              {
                'product_id': 'prod_ekmek',
                'quantity': 2000,
                'unit_price': 1000,
                'total_price': 2000,
              }
            ],
          }),
        );
        expect(saleRes.statusCode, equals(201), reason: saleRes.body);
        final saleId = (jsonDecode(saleRes.body) as Map)['sale_id'] as String;

        // seq=3: SALE_REFUND
        final refundRes = await http.post(
          Uri.parse('$baseUrl/api/v1/sales'),
          headers: authTenantHeaders(token),
          body: jsonEncode({
            'operation_id': 'op_refund_3',
            'operation_type': 'SALE_REFUND',
            'client_seq': 3,
            'refund_id': 'ref_3',
            'sale_id': saleId,
            'target_client_seq': 2,
            'total_refund_amount': 1000,
            'reason': '1 adet iade',
            'items': [
              {
                'product_id': 'prod_ekmek',
                'quantity': 1000,
                'unit_price': 1000,
                'refund_amount': 1000,
                'product_condition': 'SELLABLE',
              }
            ],
          }),
        );
        expect(refundRes.statusCode, equals(201), reason: refundRes.body);

        // seq=4: SALE_CANCEL
        final cancelRes = await http.post(
          Uri.parse('$baseUrl/api/v1/sales'),
          headers: authTenantHeaders(token),
          body: jsonEncode({
            'operation_id': 'op_cancel_4',
            'operation_type': 'SALE_CANCEL',
            'client_seq': 4,
            'sale_id': saleId,
            'target_client_seq': 2,
            'reason': 'Satış iptal',
          }),
        );
        expect(cancelRes.statusCode, equals(201), reason: cancelRes.body);

        final ops = await (db.select(db.processedOperations)
              ..where((o) => o.deviceId.equals(deviceId))
              ..orderBy([(o) => OrderingTerm.asc(o.clientSeq)]))
            .get();
        expect(ops.map((o) => o.clientSeq).toList(), equals([1, 2, 3, 4]));
        expect(
          ops.map((o) => o.operationType).toList(),
          equals(['PRODUCT_UPSERT', 'SALE_CREATE', 'SALE_REFUND', 'SALE_CANCEL']),
        );
        for (final op in ops) {
          expect(CanonicalPayloadHasher.isValidSha256Hex(op.requestHash), isTrue);
          expect(op.hashVersion, equals(CanonicalPayloadHasher.hashVersionV2Canonical));
        }

        final dev = await (db.select(db.devices)
              ..where((d) => d.deviceId.equals(deviceId)))
            .getSingle();
        expect(dev.lastCommittedClientSeq, equals(4));
        expect(dev.maxSeenClientSeq, equals(4));

        // Kısmi iade (1000) + kalan iptal (1000) sonrası stok ilk seviye (50000) olmalı
        final prodAfterAll = await (db.select(db.products)
              ..where((p) => p.id.equals('prod_ekmek')))
            .getSingle();
        expect(prodAfterAll.stock, equals(50000));
      },
    );

    test(
      '2.2. PRODUCT_UPSERT farklı JSON anahtar sırası/boşluk ile idempotent replay yapar; mutasyonda 409 döner',
      () async {
        final res1 = await http.post(
          Uri.parse('$baseUrl/api/v1/products/upsert'),
          headers: authTenantHeaders(token),
          body: jsonEncode({
            'client_seq': 1,
            'operation_id': 'op_canon_prod_1',
            'operation_type': 'PRODUCT_UPSERT',
            'product': {
              'id': 'prod_sut',
              'name': 'Süt 1L',
              'barcode': '8690002002',
              'price': 3500,
              'stock': 10000,
            },
          }),
        );
        expect(res1.statusCode, equals(200));

        // Farklı anahtar sırası + girintili JSON formatı (aynı veri)
        const reorderedPrettyJson = '''
        {
          "operation_type": "PRODUCT_UPSERT",
          "product": {
            "stock": 10000,
            "price": 3500,
            "barcode": "8690002002",
            "name": "Süt 1L",
            "id": "prod_sut"
          },
          "operation_id": "op_canon_prod_1",
          "client_seq": 1
        }
        ''';
        final replayRes = await http.post(
          Uri.parse('$baseUrl/api/v1/products/upsert'),
          headers: authTenantHeaders(token),
          body: reorderedPrettyJson,
        );
        expect(replayRes.statusCode, equals(200));
        expect(replayRes.headers['x-mms-idempotent-replay'], equals('true'));

        // Aynı seq=1 ile farklı fiyat gönderilirse -> 409 ERR_IDEMPOTENCY_PAYLOAD_MISMATCH
        final conflictRes = await http.post(
          Uri.parse('$baseUrl/api/v1/products/upsert'),
          headers: authTenantHeaders(token),
          body: jsonEncode({
            'client_seq': 1,
            'operation_id': 'op_canon_prod_1',
            'operation_type': 'PRODUCT_UPSERT',
            'product': {
              'id': 'prod_sut',
              'name': 'Süt 1L',
              'barcode': '8690002002',
              'price': 9999,
              'stock': 10000,
            },
          }),
        );
        expect(conflictRes.statusCode, equals(409));
        expect(
          (jsonDecode(conflictRes.body) as Map)['code'],
          equals('ERR_IDEMPOTENCY_PAYLOAD_MISMATCH'),
        );
      },
    );

    test(
      '2.3. Rollback olan transaction receipt yazmaz ve HWM ilerlemez; unverifiable legacy replay 409 döner',
      () async {
        // 1. Rollback olan işlem (var olmayan ürün -> 500)
        final failRes = await http.post(
          Uri.parse('$baseUrl/api/v1/sales'),
          headers: authTenantHeaders(token),
          body: jsonEncode({
            'operation_id': 'op_fail_rollback_1',
            'client_seq': 1,
            'total_amount': 2500,
            'payment_method': 'CASH',
            'items': [
              {
                'product_id': 'prod_yok',
                'quantity': 1000,
                'unit_price': 2500,
                'total_price': 2500,
              }
            ],
          }),
        );
        expect(failRes.statusCode, equals(500));

        final devAfterFail = await (db.select(db.devices)
              ..where((d) => d.deviceId.equals(deviceId)))
            .getSingle();
        expect(devAfterFail.lastCommittedClientSeq, equals(0));
        expect(await db.select(db.processedOperations).get(), isEmpty);

        // 2. Hash bilgisi NULL olan eski receipt eklendiğinde tekrar gönderim fail-closed 409 döner
        await db.into(db.processedOperations).insert(
              ProcessedOperationsCompanion(
                operationId: const Value('op_unverifiable_1'),
                deviceId: const Value(deviceId),
                idempotencyKey: const Value('$deviceId:1'),
                clientSeq: const Value(1),
                operationType: const Value('SALE_CREATE'),
                requestHash: const Value(null),
                hashVersion: const Value(null),
                resultPayload: Value(jsonEncode({
                  'status': 'COMMITTED',
                  'sale_id': 'sale_old_no_hash',
                  'client_seq': 1,
                  'total_amount': 2500,
                })),
              ),
            );

        final replayUnverifiable = await http.post(
          Uri.parse('$baseUrl/api/v1/sales'),
          headers: authTenantHeaders(token),
          body: jsonEncode({
            'operation_id': 'op_unverifiable_1',
            'client_seq': 1,
            'total_amount': 2500,
            'payment_method': 'CASH',
            'items': [
              {
                'product_id': 'prod_kola',
                'quantity': 1000,
                'unit_price': 2500,
                'total_price': 2500,
              }
            ],
          }),
        );
        expect(replayUnverifiable.statusCode, equals(409));
        expect(
          (jsonDecode(replayUnverifiable.body) as Map)['code'],
          equals('ERR_IDEMPOTENCY_HASH_UNVERIFIABLE'),
        );
      },
    );
  });

  group('BK-02.1 Grup 3 — Kesintisiz HWM ve Katı Sequence Gap Politikası', () {
    test('3.1. Unit: {1, 2, 3, 5} dizisinde kesintisiz HWM=3, max_seen=5 olur; 4 eklenince 5 olur', () {
      final summaryWithGap = DeviceSequenceInspector.computeFromSeqs([1, 2, 3, 5]);
      expect(summaryWithGap.contiguousHwm, equals(3));
      expect(summaryWithGap.maxSeenClientSeq, equals(5));
      expect(summaryWithGap.hasSequenceGaps, isTrue);
      expect(summaryWithGap.missingSeqSample, equals([4]));
      expect(summaryWithGap.expectedNextClientSeq, equals(4));

      final closedGap = DeviceSequenceInspector.computeFromSeqs([1, 2, 3, 4, 5]);
      expect(closedGap.contiguousHwm, equals(5));
      expect(closedGap.maxSeenClientSeq, equals(5));
      expect(closedGap.hasSequenceGaps, isFalse);
      expect(closedGap.missingSeqSample, isEmpty);
      expect(closedGap.expectedNextClientSeq, equals(6));
    });

    test(
      '3.2. HTTP: Sequence gap (HWM=0 iken seq=2 veya 1,2 sonrası seq=4) 409 ERR_CLIENT_SEQ_GAP ile reddedilir',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('bk02_gap_');
        addTearDown(() => tempDir.delete(recursive: true));
        final dbFile = File(p.join(tempDir.path, 'master.db'));
        final pepper = PepperManager(File(p.join(tempDir.path, 'pepper.dpapi')))
          ..initialize();
        final db = SpikeDatabase(dbFile);
        const deviceId = 'POS-GAP-01';
        const token = 'tok_gap_01';
        await seedDeviceAndProducts(
          db: db,
          pepperManager: pepper,
          deviceId: deviceId,
          token: token,
        );
        final server = SpikeServer(
          db: db,
          dbFile: dbFile,
          writeQueue: WriteQueue(),
          backupDirectory: p.join(tempDir.path, 'backups'),
          pepperManager: pepper,
        );
        await server.start(address: InternetAddress.loopbackIPv4, port: 8963);
        addTearDown(() async {
          await server.stop();
          await db.close();
        });

        Map<String, dynamic> salePayload(int seq) => {
              'operation_id': 'op_gap_$seq',
              'client_seq': seq,
              'total_amount': 2500,
              'payment_method': 'CASH',
              'items': [
                {
                  'product_id': 'prod_kola',
                  'quantity': 1000,
                  'unit_price': 2500,
                  'total_price': 2500,
                }
              ],
            };

        // HWM=0 iken seq=2 reddedilmeli
        final gap1 = await http.post(
          Uri.parse('http://127.0.0.1:8963/api/v1/sales'),
          headers: authTenantHeaders(token),
          body: jsonEncode(salePayload(2)),
        );
        expect(gap1.statusCode, equals(409));
        final gap1Body = jsonDecode(gap1.body) as Map<String, dynamic>;
        expect(gap1Body['code'], equals('ERR_CLIENT_SEQ_GAP'));
        expect(gap1Body['expected_client_seq'], equals(1));
        expect(gap1Body['received_client_seq'], equals(2));

        // seq=1 ve seq=2 kabul edilir
        expect(
          (await http.post(
            Uri.parse('http://127.0.0.1:8963/api/v1/sales'),
            headers: authTenantHeaders(token),
            body: jsonEncode(salePayload(1)),
          ))
              .statusCode,
          equals(201),
        );
        expect(
          (await http.post(
            Uri.parse('http://127.0.0.1:8963/api/v1/sales'),
            headers: authTenantHeaders(token),
            body: jsonEncode(salePayload(2)),
          ))
              .statusCode,
          equals(201),
        );

        // seq=4 reddedilir (expected=3)
        final gap2 = await http.post(
          Uri.parse('http://127.0.0.1:8963/api/v1/sales'),
          headers: authTenantHeaders(token),
          body: jsonEncode(salePayload(4)),
        );
        expect(gap2.statusCode, equals(409));
        expect((jsonDecode(gap2.body) as Map)['expected_client_seq'], equals(3));

        // Önce idempotency replay (seq=2) çalışmalı (200 OK)
        final replay2 = await http.post(
          Uri.parse('http://127.0.0.1:8963/api/v1/sales'),
          headers: authTenantHeaders(token),
          body: jsonEncode(salePayload(2)),
        );
        expect(replay2.statusCode, equals(200));
        expect(replay2.headers['x-mms-idempotent-replay'], equals('true'));

        // seq=3 geldiğinde kabul edilir ve HWM=3 olur
        expect(
          (await http.post(
            Uri.parse('http://127.0.0.1:8963/api/v1/sales'),
            headers: authTenantHeaders(token),
            body: jsonEncode(salePayload(3)),
          ))
              .statusCode,
          equals(201),
        );
      },
    );
  });

  group('BK-02.1 Grup 4 & 5 — Sync API\'leri, İzolasyon ve Tenant/Store Doğrulaması', () {
    late Directory tempDir;
    late SpikeDatabase db;
    late PepperManager pepper;
    late SpikeServer server;
    const port = 8964;
    const baseUrl = 'http://127.0.0.1:$port';
    const devA = 'POS-DEV-A';
    const tokA = 'tok_dev_a_111';
    const devB = 'POS-DEV-B';
    const tokB = 'tok_dev_b_222';

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('bk02_api_');
      final dbFile = File(p.join(tempDir.path, 'master.db'));
      pepper = PepperManager(File(p.join(tempDir.path, 'pepper.dpapi')))
        ..initialize();
      db = SpikeDatabase(dbFile);
      await seedDeviceAndProducts(
        db: db,
        pepperManager: pepper,
        deviceId: devA,
        token: tokA,
      );
      await seedDeviceAndProducts(
        db: db,
        pepperManager: pepper,
        deviceId: devB,
        token: tokB,
        seedProducts: false,
      );
      server = SpikeServer(
        db: db,
        dbFile: dbFile,
        writeQueue: WriteQueue(),
        backupDirectory: p.join(tempDir.path, 'backups'),
        adminSecret: 'adm_api_secret',
        pepperManager: pepper,
      );
      await server.start(address: InternetAddress.loopbackIPv4, port: port);
    });

    tearDown(() async {
      await server.stop();
      await db.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      '4.1. device-state ve receipts API cihaz bazlı izolasyon sağlar, unverifiable makbuzu doğrulamaz',
      () async {
        // DEV_A seq=1 ve seq=2 işlesin; DEV_B seq=1 işlesin
        for (final seq in [1, 2]) {
          final r = await http.post(
            Uri.parse('$baseUrl/api/v1/sales'),
            headers: authTenantHeaders(tokA),
            body: jsonEncode({
              'operation_id': 'op_a_$seq',
              'client_seq': seq,
              'total_amount': 2500,
              'payment_method': 'CASH',
              'items': [
                {'product_id': 'prod_kola', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500}
              ],
            }),
          );
          expect(r.statusCode, equals(201));
        }

        // DEV_A için seq=3'ü hash'i NULL eski tip makbuz gibi DB'ye yerleştir (UNVERIFIABLE_LEGACY testi)
        await db.into(db.processedOperations).insert(
              ProcessedOperationsCompanion(
                operationId: const Value('op_a_3_nohash'),
                deviceId: const Value(devA),
                idempotencyKey: const Value('$devA:3'),
                clientSeq: const Value(3),
                operationType: const Value('SALE_CREATE'),
                requestHash: const Value(null),
                hashVersion: const Value(null),
                resultPayload: Value(jsonEncode({'status': 'COMMITTED'})),
              ),
            );

        // DEV_B yalnızca seq=1 yapsın
        final rB = await http.post(
          Uri.parse('$baseUrl/api/v1/sales'),
          headers: authTenantHeaders(tokB),
          body: jsonEncode({
            'operation_id': 'op_b_1',
            'client_seq': 1,
            'total_amount': 2500,
            'payment_method': 'CASH',
            'items': [
              {'product_id': 'prod_kola', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500}
            ],
          }),
        );
        expect(rB.statusCode, equals(201));

        // 1. DEV_A device-state
        final stateARes = await http.get(
          Uri.parse('$baseUrl/api/v1/sync/device-state'),
          headers: authTenantHeaders(tokA),
        );
        expect(stateARes.statusCode, equals(200));
        final stateA = jsonDecode(stateARes.body) as Map<String, dynamic>;
        expect(stateA['device_id'], equals(devA));
        expect(stateA['high_water_mark_seq'], equals(3));
        expect(stateA['unverifiable_receipt_count'], equals(1));

        // 2. DEV_B device-state yalnızca kendi HWM=1 verisini görür
        final stateBRes = await http.get(
          Uri.parse('$baseUrl/api/v1/sync/device-state'),
          headers: authTenantHeaders(tokB),
        );
        expect(stateBRes.statusCode, equals(200));
        final stateB = jsonDecode(stateBRes.body) as Map<String, dynamic>;
        expect(stateB['device_id'], equals(devB));
        expect(stateB['high_water_mark_seq'], equals(1));
        expect(stateB['unverifiable_receipt_count'], equals(0));

        // 3. DEV_A receipts sorgusu: 1 FOUND, 3 UNVERIFIABLE_LEGACY (is_hash_verifiable: false), 99 NOT_FOUND
        final recARes = await http.post(
          Uri.parse('$baseUrl/api/v1/sync/receipts'),
          headers: authTenantHeaders(tokA),
          body: jsonEncode({
            'client_seqs': [1, 3, 99],
          }),
        );
        expect(recARes.statusCode, equals(200));
        final recA = jsonDecode(recARes.body) as Map<String, dynamic>;
        final receiptsA = (recA['receipts'] as List).cast<Map<String, dynamic>>();
        expect(receiptsA[0]['status'], equals('FOUND'));
        expect(receiptsA[0]['is_hash_verifiable'], isTrue);
        expect(receiptsA[1]['status'], equals('UNVERIFIABLE_LEGACY'));
        expect(receiptsA[1]['is_hash_verifiable'], isFalse);
        expect(receiptsA[1]['request_hash'], isNull);
        expect(receiptsA[2]['status'], equals('NOT_FOUND'));

        // 4. DEV_B, DEV_A'nın seq=2 makbuzuna erişemez ve başka device_id isteyemez
        final recBCrossRes = await http.post(
          Uri.parse('$baseUrl/api/v1/sync/receipts'),
          headers: authTenantHeaders(tokB),
          body: jsonEncode({
            'client_seqs': [2],
          }),
        );
        expect(recBCrossRes.statusCode, equals(200));
        expect(
          ((jsonDecode(recBCrossRes.body) as Map)['receipts'] as List).first['status'],
          equals('NOT_FOUND'),
        );

        final recBSpoofDeviceRes = await http.post(
          Uri.parse('$baseUrl/api/v1/sync/receipts'),
          headers: authTenantHeaders(tokB),
          body: jsonEncode({
            'device_id': devA,
            'client_seqs': [1],
          }),
        );
        expect(recBSpoofDeviceRes.statusCode, equals(403));
        expect(
          (jsonDecode(recBSpoofDeviceRes.body) as Map)['code'],
          equals('ERR_DEVICE_ID_MISMATCH'),
        );
      },
    );

    test(
      '4.2. Tenant/Store uyuşmazlığı veya sync API\'de eksik başlık 403 fail-closed reddedilir',
      () async {
        // Eksik başlık -> 403 ERR_TENANT_STORE_REQUIRED
        final missingHeaderRes = await http.get(
          Uri.parse('$baseUrl/api/v1/sync/device-state'),
          headers: {'authorization': 'Bearer $tokA'},
        );
        expect(missingHeaderRes.statusCode, equals(403));
        expect(
          (jsonDecode(missingHeaderRes.body) as Map)['code'],
          equals('ERR_TENANT_STORE_REQUIRED'),
        );

        // Yanlış store_id -> 403 ERR_TENANT_STORE_MISMATCH
        final wrongStoreRes = await http.post(
          Uri.parse('$baseUrl/api/v1/sync/receipts'),
          headers: authTenantHeaders(tokA, storeId: 'wrong-store'),
          body: jsonEncode({
            'client_seqs': [1],
          }),
        );
        expect(wrongStoreRes.statusCode, equals(403));
        expect(
          (jsonDecode(wrongStoreRes.body) as Map)['code'],
          equals('ERR_TENANT_STORE_MISMATCH'),
        );

        // Yanlış tenant_id /api/v1/sales üzerinde de reddedilir
        final wrongTenantSaleRes = await http.post(
          Uri.parse('$baseUrl/api/v1/sales'),
          headers: authTenantHeaders(tokA, tenantId: 'other-tenant'),
          body: jsonEncode({
            'operation_id': 'op_wrong_tenant',
            'client_seq': 1,
            'total_amount': 2500,
            'payment_method': 'CASH',
            'items': [
              {'product_id': 'prod_kola', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500}
            ],
          }),
        );
        expect(wrongTenantSaleRes.statusCode, equals(403));
        expect(
          (jsonDecode(wrongTenantSaleRes.body) as Map)['code'],
          equals('ERR_TENANT_STORE_MISMATCH'),
        );
      },
    );

    test(
      '4.3. hub_metadata tenant/store uyuşmazlığı fail-closed durdurur ve requireTenantStoreHeaders sıkı mod çalışır',
      () async {
        // Mevcut DB tenant_id='default-tenant' ile mühürlü; farklı tenantId ile yeni server başlatma reddedilmeli
        final wrongIdentityServer = SpikeServer(
          db: db,
          writeQueue: WriteQueue(),
          backupDirectory: p.join(tempDir.path, 'backups_wrong_id'),
          pepperManager: pepper,
          tenantId: 'tenant-baska',
          storeId: SpikeServer.defaultStoreId,
        );
        await expectLater(
          wrongIdentityServer.start(
            address: InternetAddress.loopbackIPv4,
            port: 8965,
            enableDiscovery: false,
          ),
          throwsA(isA<StateError>()),
        );

        // requireTenantStoreHeaders: true sunucuda /api/v1/products başlık yoksa 403 döner
        final strictDir = await Directory.systemTemp.createTemp('bk02_strict_');
        addTearDown(() => strictDir.delete(recursive: true));
        final strictDb = SpikeDatabase(File(p.join(strictDir.path, 'strict.db')));
        final strictPep = PepperManager(File(p.join(strictDir.path, 'pep.dpapi')))
          ..initialize();
        await seedDeviceAndProducts(
          db: strictDb,
          pepperManager: strictPep,
          deviceId: 'POS-STR',
          token: 'tok_str',
        );
        final strictServer = SpikeServer(
          db: strictDb,
          writeQueue: WriteQueue(),
          backupDirectory: p.join(strictDir.path, 'backups'),
          pepperManager: strictPep,
          requireTenantStoreHeaders: true,
        );
        await strictServer.start(
          address: InternetAddress.loopbackIPv4,
          port: 8966,
          enableDiscovery: false,
        );
        addTearDown(() async {
          await strictServer.stop();
          await strictDb.close();
        });

        final strictMissing = await http.get(
          Uri.parse('http://127.0.0.1:8966/api/v1/products'),
          headers: {'authorization': 'Bearer tok_str'},
        );
        expect(strictMissing.statusCode, equals(403));
        expect(
          (jsonDecode(strictMissing.body) as Map)['code'],
          equals('ERR_TENANT_STORE_REQUIRED'),
        );
      },
    );
  });
}
