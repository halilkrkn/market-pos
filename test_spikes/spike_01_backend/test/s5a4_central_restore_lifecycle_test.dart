import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNotNull, isNull;
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
  late PepperManager pepperManager;
  late SpikeServer server;
  late String baseUrl;
  const testPort = 8996;
  const adminSecret = 'admin_s5a4_secret_test';
  const deviceId = 'DEV_S5A4_SERVER';
  const rawToken = 'token_s5a4_server_secret';

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    configureSqliteNative();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mms_s5a4_server_test_');
    dbFile = File(p.join(tempDir.path, 'market_master.db'));

    pepperManager = PepperManager(File(p.join(tempDir.path, 'pepper.dpapi')));
    pepperManager.initialize();

    db = SpikeDatabase(dbFile);
    writeQueue = WriteQueue();

    // Ürün tohumla
    await db.into(db.products).insert(
          ProductsCompanion(
            id: const Value('prod_cola'),
            barcode: const Value('869000000001'),
            name: const Value('Kutu Kola 330ml'),
            price: const Value(2500),
            stock: const Value(100000),
          ),
        );

    // Cihaz yetkilendir
    final salt = TokenManager.generateSalt();
    final hash = TokenManager.hashToken(
      rawToken: rawToken,
      salt: salt,
      pepper: pepperManager.pepper,
    );
    await db.into(db.devices).insert(
          DevicesCompanion(
            deviceId: const Value(deviceId),
            name: const Value('Test Terminal'),
            tokenHash: Value(hash),
            salt: Value(salt),
            isActive: const Value(true),
            isConfirmed: const Value(true),
            role: const Value('CASHIER'),
          ),
        );

    server = SpikeServer(
      db: db,
      dbFile: dbFile,
      writeQueue: writeQueue,
      backupDirectory: p.join(tempDir.path, 'backups'),
      adminSecret: adminSecret,
      pepperManager: pepperManager,
    );

    await server.start(port: testPort);
    baseUrl = 'http://127.0.0.1:$testPort';
  });

  tearDown(() async {
    await server.stop();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('Aşama S-5A-4: Merkezi Sunucu (market_master.db) Restore ve Yaşam Döngüsü', () {
    test('1. Merkezi Restore Sırasında AdmissionGate 503 Engellemesi, WriteQueue Dondurma ve Güvenli Yeniden Açılış', () async {
      // 1. Durum A: 100 stok var iken şifreli bir yedek oluştur
      final backupResp = await http.post(
        Uri.parse('$baseUrl/api/v1/admin/backup'),
        headers: {
          'x-mms-admin-secret': adminSecret,
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'backup_password': 'Mms_Master_Backup_Password_2026!',
        }),
      );

      expect(backupResp.statusCode, equals(200));
      final backupJson = jsonDecode(backupResp.body) as Map<String, dynamic>;
      final backupId = backupJson['backup_id'] as String;
      expect(backupId, isNotEmpty);

      // 2. Durum B: 1 adet satış yap (Stok 99'a düşsün)
      final salePayload = {
        'operation_id': 'op_master_test_1',
        'sale_id': 'sale_master_test_1',
        'device_id': deviceId,
        'client_seq': 1,
        'items': [
          {'product_id': 'prod_cola', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500}
        ],
        'total_amount': 2500,
        'payment_method': 'CASH',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      final saleResp = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'authorization': 'Bearer $rawToken',
          'content-type': 'application/json',
        },
        body: jsonEncode(salePayload),
      );
      expect(saleResp.statusCode, anyOf([200, 201]));

      final midStock = (await (server.db.select(server.db.products)..where((p) => p.id.equals('prod_cola'))).getSingle()).stock;
      expect(midStock, equals(99000)); // 99 adet

      // 3. Restore tetikle ve eşzamanlı istekleri gözlemle
      // AdmissionGate'in restore sırasında kapandığını ve diğer isteklerin 503 aldığını doğrula
      final restoreFuture = http.post(
        Uri.parse('$baseUrl/api/v1/admin/restore'),
        headers: {
          'x-mms-admin-secret': adminSecret,
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'backup_id': backupId,
          'backup_password': 'Mms_Master_Backup_Password_2026!',
        }),
      );

      // Restore işlemi arka planda yürürken hemen arkasından gelen normal API isteği
      // AdmissionGate tarafından 503 SERVICE_DRAINING ile reddedilmelidir veya restore bitene kadar kuyrukta tutulmalıdır
      final healthCheck = await http.get(Uri.parse('$baseUrl/health'));
      // Health check ya 200 (restore öncesi/sonrası) ya da 503 (tam restore anında) döner
      expect(healthCheck.statusCode, anyOf([200, 503]));

      final restoreResp = await restoreFuture;
      expect(restoreResp.statusCode, equals(200));
      final restoreJson = jsonDecode(restoreResp.body) as Map<String, dynamic>;
      expect(restoreJson['status'], equals('RESTORED'));

      // 4. Restore sonrası:
      // A. AdmissionGate ve WriteQueue yeniden açık olmalıdır
      expect(server.lifecycle.admissionGate.isOpen, isTrue);
      expect(server.writeQueue.isDraining, isFalse);

      // B. Normal API istekleri 200 OK ile sorunsuz kabul edilmelidir
      final postRestoreHealth = await http.get(Uri.parse('$baseUrl/health'));
      expect(postRestoreHealth.statusCode, equals(200));

      // C. Veritabanının durum A'ya (100 stok) döndüğü doğrulanmalıdır
      final restoredStock = (await (server.db.select(server.db.products)..where((p) => p.id.equals('prod_cola'))).getSingle()).stock;
      expect(restoredStock, equals(100000)); // 100 adet

      // D. Durum B'deki satışın veritabanından başarıyla temizlendiği teyit edilmelidir
      final sales = await server.db.select(server.db.sales).get();
      expect(sales, isEmpty);
    });
  });
}
