import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
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
  late String baseUrl;
  const testPort = 8899;
  late String validToken;
  late PepperManager pepperManager;
  const testAdminSecret = 'sec_admin_test_super_secret_9988';

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    configureSqliteNative();
    tempDir = await Directory.systemTemp.createTemp('mms_s1_hardening_');
    dbFile = File(p.join(tempDir.path, 's1_test.db'));

    pepperManager = PepperManager(File(p.join(tempDir.path, 'pepper.dpapi')));
    pepperManager.initialize();

    db = SpikeDatabase(dbFile);
    writeQueue = WriteQueue();

    // 1. Ürün ekle
    await db.into(db.products).insert(
          ProductsCompanion(
            id: const Value('prod_cola'),
            barcode: const Value('869000000001'),
            name: const Value('Kutu Kola 330ml'),
            price: const Value(2500),
            stock: const Value(100),
          ),
        );

    // 2. Yetkili Normal Cihaz ekle (Kasa Terminali)
    validToken = TokenManager.generateToken();
    final salt = TokenManager.generateSalt();
    final tokenHash = TokenManager.hashToken(
      rawToken: validToken,
      salt: salt,
      pepper: pepperManager.pepper,
    );

    await db.into(db.devices).insert(
          DevicesCompanion(
            deviceId: const Value('DEV_S1_01'),
            name: const Value('S1 Test Kasası'),
            tokenHash: Value(tokenHash),
            salt: Value(salt),
            isActive: const Value(true),
          ),
        );

    server = SpikeServer(
      db: db,
      writeQueue: writeQueue,
      backupDirectory: p.join(tempDir.path, 'backups'),
      adminSecret: testAdminSecret,
      pepperManager: pepperManager,
    );
    await server.start(address: InternetAddress.loopbackIPv4, port: testPort);
    baseUrl = 'http://127.0.0.1:$testPort';
  });

  tearDownAll(() async {
    try {
      await server.stop();
    } catch (_) {}
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('S-1 API Security Hardening Testleri', () {
    test('1. Cihaz kayıt endpoint’i yetkisiz erişime KAPALI olmalıdır (401 Unauthorized)', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/devices/register'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'device_id': 'DEV_ROGUE_01',
          'name': 'Saldırgan Cihaz',
          'token': 'rogue_token_123',
        }),
      );

      expect(res.statusCode, equals(401),
          reason: 'Açık cihaz kaydı kapatılmalı ve yetkilendirme aranmalıdır.');
    });

    test('2. Backup endpoint’inde SQL Injection denemesi engellenmelidir', () async {
      const maliciousSql = "'; DROP TABLE sales; --";
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/backup/snapshot'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $validToken',
        },
        body: jsonEncode({'target_path': maliciousSql}),
      );

      expect(res.statusCode, equals(400));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      expect(data['code'], equals('ERR_MALICIOUS_INPUT'));

      // Ürün tablosunun sağlam olduğunu doğrula
      final productsCount = (await db.select(db.products).get()).length;
      expect(productsCount, greaterThan(0));
    });

    test('3. Backup endpoint’i keyfi dosya yolu kabul etmemeli, sunucu güvenli dizinde üretmelidir', () async {
      final dangerousPath = p.join(tempDir.path, 'arbitrary_overwrite.db');
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/backup/snapshot'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $validToken',
        },
        body: jsonEncode({'target_path': dangerousPath}),
      );

      expect(res.statusCode, equals(200));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final returnedPath = data['backup_path'] as String;

      expect(returnedPath, isNot(equals(dangerousPath)));
      expect(File(returnedPath).existsSync(), isTrue);
      expect(File(dangerousPath).existsSync(), isFalse);
    });

    test('4. Eşzamanlı (Concurrent) Backup İstekleri Çakışmamalı ve Her Biri Benzersiz Dosya Üretmelidir', () async {
      // 3 eşzamanlı yedekleme isteği gönder
      final futures = List.generate(3, (_) {
        return http.post(
          Uri.parse('$baseUrl/api/v1/backup/snapshot'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $validToken',
          },
          body: jsonEncode({}),
        );
      });

      final responses = await Future.wait(futures);
      final generatedPaths = <String>{};

      for (final res in responses) {
        expect(res.statusCode, equals(200));
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final path = data['backup_path'] as String;

        expect(File(path).existsSync(), isTrue);
        generatedPaths.add(path);

        // Her snapshot dosyasının SQLite bütünlüğünü doğrula
        final snapDb = sqlite3.open(path);
        final check = snapDb.select('PRAGMA integrity_check;');
        expect(check.first['integrity_check'], equals('ok'));
        snapDb.dispose();
      }

      // 3 isteğin de kesinlikle benzersiz dosya adı ürettiğini doğrula (çakışma ve üzerine yazma yok!)
      expect(generatedPaths.length, equals(3),
          reason: 'Eşzamanlı istekler aynı dosyayı ezmemeli, benzersiz yollar üretmelidir.');
    });

    test('5. HTTP 500 hata yanıtlarında stack trace, dosya yolu veya dahili hata detayı sızmamalıdır', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $validToken',
        },
        body: jsonEncode({
          'operation_id': 'op_error_leak_test',
          'client_seq': 999,
          'total_amount': 2500,
          'payment_method': 'CASH',
          'items': [
            {'product_id': 'prod_non_existent', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500}
          ],
        }),
      );

      expect(res.statusCode, equals(500));
      final bodyStr = res.body;

      expect(bodyStr, isNot(contains('StateError')));
      expect(bodyStr, isNot(contains('stackTrace')));
      expect(bodyStr, isNot(contains('.dart')));
      expect(bodyStr, isNot(contains('C:\\')));

      final data = jsonDecode(bodyStr) as Map<String, dynamic>;
      expect(data['error'], equals('TRANSACTION_FAILED'));
      expect(data['code'], isNotNull);
    });

    test('6. Request body boyutu Content-Length > 2 MB olduğunda 413 Payload Too Large dönmelidir', () async {
      final largeData = 'A' * (2500 * 1024);
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'text/plain',
          'authorization': 'Bearer $validToken',
        },
        body: largeData,
      );

      expect(res.statusCode, equals(413));
    });

    test('7. Request body boyutu stream okuma sırasında 2 MB aşıldığında stream kesilmeli (413 veya soket sonlandırma)', () async {
      final req = http.StreamedRequest('POST', Uri.parse('$baseUrl/api/v1/sales'));
      req.headers['authorization'] = 'Bearer $validToken';
      req.headers['content-type'] = 'application/json';

      final chunk = utf8.encode('{"op":"stream","pad":"' + ('X' * (64 * 1024)) + '"}');
      Future<void> sendChunks() async {
        try {
          for (var i = 0; i < 35; i++) {
            req.sink.add(chunk);
          }
          await req.sink.close();
        } catch (_) {}
      }

      sendChunks();
      try {
        final streamedResponse = await req.send();
        expect(streamedResponse.statusCode, equals(413));
      } on http.ClientException catch (e) {
        expect(e.message, anyOf(contains('Connection closed'), contains('Write failed')));
      } on SocketException catch (_) {}
    });

    test('8. CORS başlıklarında wildcard (*) bulunmamalıdır', () async {
      final res = await http.get(
        Uri.parse('$baseUrl/health'),
        headers: {'origin': 'http://evil-website.com'},
      );

      final corsAllowOrigin = res.headers['access-control-allow-origin'];
      expect(corsAllowOrigin, isNot(equals('*')));
    });

    test('9. Health endpoint’inde SQLite sürüm bilgisi maskelenmiş olmalıdır', () async {
      final res = await http.get(Uri.parse('$baseUrl/health'));
      expect(res.statusCode, equals(200));

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final version = data['sqlite_version'] as String;

      expect(version.toLowerCase(), contains('masked'));
    });

    test('10. Admin shutdown endpoint’ine normal cihaz tokenı ile istek yapıldığında 403 Forbidden ile REDDEDİLMELİDİR', () async {
      // Normal cihaz token'ı (kasiyer kasası) shutdown yetkisi vermemelidir!
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/admin/shutdown'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $validToken',
        },
      );

      expect(res.statusCode, equals(403),
          reason: 'Normal cihaz tokenı ile shutdown yetkisi verilmemelidir!');
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      expect(data['code'], equals('ERR_INVALID_ADMIN_SECRET'));
    });

    test('11. Admin shutdown endpoint’ine yetkisiz (başlıksız) loopback isteği 401 Unauthorized dönmelidir', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/admin/shutdown'),
        headers: {'content-type': 'application/json'},
      );

      expect(res.statusCode, equals(401),
          reason: 'Hiçbir başlık/secret olmadan gelen shutdown isteği 401 almalıdır.');
    });

    test('12. Admin shutdown endpoint’i secret yapılandırılmadığında varsayılan olarak KAPALI (503) olmalıdır', () async {
      // Secret verilmeden ve ayrı kuyrukla başlatılan geçici sunucu
      final unconfigQueue = WriteQueue();
      final unconfigServer = SpikeServer(
        db: db,
        writeQueue: unconfigQueue,
        adminSecret: null, // Yapılandırılmamış
        pepperManager: pepperManager,
      );
      const unconfigPort = 8892;
      await unconfigServer.start(address: InternetAddress.loopbackIPv4, port: unconfigPort);

      try {
        final res = await http.post(
          Uri.parse('http://127.0.0.1:$unconfigPort/api/v1/admin/shutdown'),
          headers: {'content-type': 'application/json', 'x-admin-secret': 'any_secret'},
        );

        expect(res.statusCode, equals(503));
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        expect(data['code'], equals('ERR_SHUTDOWN_NOT_CONFIGURED'));
      } finally {
        await unconfigServer.stop();
      }
    });

    test('13. Admin shutdown endpoint’i doğru Admin Secret ile loopback üzerinden başarıyla tetiklenebilmelidir', () async {
      // En son test: Sunucuyu kapatma testi (X-Admin-Secret veya Bearer Admin Secret)
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/admin/shutdown'),
        headers: {
          'content-type': 'application/json',
          'x-admin-secret': testAdminSecret,
        },
      );

      expect(res.statusCode, equals(200));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      expect(data['status'], equals('SHUTTING_DOWN'));
      // Secret sızmadığını doğrula
      expect(res.body, isNot(contains(testAdminSecret)));
    });
  });
}
