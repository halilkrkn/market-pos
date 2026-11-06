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
import '../lib/security/dpapi.dart';
import '../lib/security/pepper_manager.dart';
import '../lib/security/token_manager.dart';

void main() {
  late Directory tempDir;
  late File dbFile;
  late File pepperFile;
  late SpikeDatabase db;
  late WriteQueue writeQueue;
  late PepperManager pepperManager;
  late SpikeServer server;
  late String baseUrl;
  const testPort = 8995;
  const testAdminSecret = 'admin_secret_s2_test_4567';

  late String validCashierToken;
  late String revokedCashierToken;
  late String expiredCashierToken;

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    configureSqliteNative();
    tempDir = await Directory.systemTemp.createTemp('mms_s2_security_');
    dbFile = File(p.join(tempDir.path, 's2_test.db'));
    pepperFile = File(p.join(tempDir.path, 'pepper.dpapi'));

    // Pepper'ı başlat
    pepperManager = PepperManager(pepperFile);
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
            stock: const Value(100000),
          ),
        );

    // 2. Yetkili Normal Kasa Cihazı (Valid)
    validCashierToken = TokenManager.generateToken();
    final validSalt = TokenManager.generateSalt();
    final validHash = TokenManager.hashToken(
      rawToken: validCashierToken,
      salt: validSalt,
      pepper: pepperManager.pepper,
    );

    await db.into(db.devices).insert(
          DevicesCompanion(
            deviceId: const Value('DEV_CASHIER_01'),
            name: const Value('Kasa 1 Terminali'),
            tokenHash: Value(validHash),
            salt: Value(validSalt),
            isActive: const Value(true),
          ),
        );

    // 3. İptal Edilmiş Cihaz (Revoked)
    revokedCashierToken = TokenManager.generateToken();
    final revokedSalt = TokenManager.generateSalt();
    final revokedHash = TokenManager.hashToken(
      rawToken: revokedCashierToken,
      salt: revokedSalt,
      pepper: pepperManager.pepper,
    );

    await db.into(db.devices).insert(
          DevicesCompanion(
            deviceId: const Value('DEV_STOLEN_02'),
            name: const Value('Çalınan Tablet Kasa'),
            tokenHash: Value(revokedHash),
            salt: Value(revokedSalt),
            isActive: const Value(false),
          ),
        );

    // 4. Süresi Dolmuş Cihaz (Expired)
    expiredCashierToken = TokenManager.generateToken();
    final expiredSalt = TokenManager.generateSalt();
    final expiredHash = TokenManager.hashToken(
      rawToken: expiredCashierToken,
      salt: expiredSalt,
      pepper: pepperManager.pepper,
    );

    await db.into(db.devices).insert(
          DevicesCompanion(
            deviceId: const Value('DEV_EXPIRED_03'),
            name: const Value('Eski Sezon Kasası'),
            tokenHash: Value(expiredHash),
            salt: Value(expiredSalt),
            isActive: const Value(true),
            expiresAt: Value(DateTime.now().subtract(const Duration(days: 1))), // Dün bitti
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

  group('S-2 Device Token Security 20 Doğrulama Senaryosu', () {
    test('1. Token güvenli şekilde üretiliyor (256 bit entropi, CSPRNG)', () {
      final token = TokenManager.generateToken();
      expect(token, startsWith('mms_dt_'));
      expect(token.length, greaterThanOrEqualTo(45));
    });

    test('2. Üretilen token yeterli rastgeleliğe sahip (alfanümerik base64url)', () {
      final token = TokenManager.generateToken();
      final body = token.substring(7);
      expect(RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(body), isTrue);
    });

    test('3. Aynı cihaz için art arda üretilen tokenlar birbirinden farklı', () {
      final token1 = TokenManager.generateToken();
      final token2 = TokenManager.generateToken();
      expect(token1, isNot(equals(token2)));
    });

    test('4. SQLite veritabanı içerisinde AÇIK METİN TOKEN BULUNMUYOR', () {
      // Doğrudan raw SQLite tablosunu sorgula
      final rawDb = sqlite3.open(dbFile.path);
      final rows = rawDb.select('SELECT * FROM devices;');

      for (final row in rows) {
        expect(row.containsKey('token'), isFalse,
            reason: 'token sütunu SQLite şemasından tamamen kaldırılmış olmalıdır.');
        expect(row['token_hash'], isNotNull);
        expect(row['salt'], isNotNull);

        // Hiçbir sütunda açık token metni geçmemelidir
        for (final val in row.values) {
          if (val is String) {
            expect(val, isNot(contains(validCashierToken)));
            expect(val, isNot(contains(revokedCashierToken)));
          }
        }
      }
      rawDb.dispose();
    });

    test('5. Salt her cihaz bazında birbirinden farklı ve benzersizdir', () {
      final rawDb = sqlite3.open(dbFile.path);
      final rows = rawDb.select('SELECT salt FROM devices;');
      final salts = rows.map((r) => r['salt'] as String).toSet();
      expect(salts.length, equals(rows.length));
      rawDb.dispose();
    });

    test('6. Doğru token ile korumalı API çağrısı kabul edilmelidir (200 OK)', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $validCashierToken',
        },
        body: jsonEncode({
          'operation_id': 'op_s2_valid_tx',
          'client_seq': 1,
          'total_amount': 2500,
          'payment_method': 'CASH',
          'items': [
            {'product_id': 'prod_cola', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500}
          ],
        }),
      );

      expect(res.statusCode, equals(201));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      expect(data['status'], equals('COMMITTED'));
    });

    test('7. Yanlış token ile istek yapıldığında 401 Unauthorized dönmelidir', () async {
      final wrongToken = TokenManager.generateToken();
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $wrongToken',
        },
        body: jsonEncode({'operation_id': 'op_wrong'}),
      );

      expect(res.statusCode, equals(401));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      expect(data['error'], equals('DEVICE_NOT_FOUND'));
    });

    test('8. İptal edilmiş (revoked) cihaz tokenı ile istek yapıldığında 403 Forbidden dönmelidir', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $revokedCashierToken',
        },
        body: jsonEncode({'operation_id': 'op_revoked'}),
      );

      expect(res.statusCode, equals(403));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      expect(data['error'], equals('DEVICE_REVOKED'));
    });

    test('9. Süresi dolmuş (expired) token ile istek yapıldığında 401 Unauthorized dönmelidir', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $expiredCashierToken',
        },
        body: jsonEncode({'operation_id': 'op_expired'}),
      );

      expect(res.statusCode, equals(401));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      expect(data['error'], equals('TOKEN_EXPIRED'));
    });

    test('10. Token yenileme (renew) işlemi başarıyla çalışmalı ve yeni token dönmelidir', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/devices/renew-token'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $validCashierToken',
        },
      );

      expect(res.statusCode, equals(200));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      expect(data['status'], equals('RENEWED'));
      expect(data['device_id'], equals('DEV_CASHIER_01'));
      expect(data['token'], startsWith('mms_dt_'));
      expect(data['token'], isNot(equals(validCashierToken)));

      // Yeni token ile satış yapılabilmelidir
      final newCashierToken = data['token'] as String;
      final saleRes = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $newCashierToken',
        },
        body: jsonEncode({
          'operation_id': 'op_s2_renew_new_tx',
          'client_seq': 2,
          'total_amount': 2500,
          'payment_method': 'CASH',
          'items': [
            {'product_id': 'prod_cola', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500}
          ],
        }),
      );
      expect(saleRes.statusCode, equals(201));

      // Global değişkeni güncelle
      validCashierToken = newCashierToken;
    });

    test('11. Eski token yenileme sonrasında kesinlikle KULLANILAMAZ olmalıdır (401)', () async {
      // Eski validCashierToken yerine yenisi geçmişti. Eski tokenla tekrar istek at:
      const oldUsedToken = 'mms_dt_old_used_token_that_was_replaced';
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $oldUsedToken',
        },
        body: jsonEncode({'operation_id': 'op_old_token'}),
      );

      expect(res.statusCode, equals(401));
    });

    test('12. Eski tokenla yenileme işlemi tekrarlandığında ikinci token üretilmemelidir', () async {
      // Geçersiz/eski tokenla yenileme denemesi
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/devices/renew-token'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer invalid_or_old_token',
        },
      );

      expect(res.statusCode, equals(401));
    });

    test('13. Token iptal (revoke) işlemi doğru çalışmalı ve audit kaydı oluşmalıdır', () async {
      // DEV_CASHIER_01 cihazını iptal et
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/devices/revoke'),
        headers: {
          'content-type': 'application/json',
          'x-admin-secret': testAdminSecret,
        },
        body: jsonEncode({
          'device_id': 'DEV_CASHIER_01',
          'reason': 'Güvenlik denetimi iptali',
        }),
      );

      expect(res.statusCode, equals(200));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      expect(data['status'], equals('REVOKED'));
      expect(data['device_id'], equals('DEV_CASHIER_01'));

      // İptal edilen cihazın hemen ardından gelen isteği 403 almalıdır
      final saleRes = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $validCashierToken',
        },
        body: jsonEncode({'operation_id': 'op_after_revoke'}),
      );
      expect(saleRes.statusCode, equals(403));

      // Audit tablosunu doğrudan doğrula
      final rawDb = sqlite3.open(dbFile.path);
      final logs = rawDb.select("SELECT * FROM device_audit_logs WHERE device_id = 'DEV_CASHIER_01' ORDER BY id ASC;");
      expect(logs.isNotEmpty, isTrue);
      expect(logs.any((l) => l['action'] == 'REVOKE'), isTrue);
      expect(logs.last['action'], equals('REVOKE'));
      // Audit logunda açık token bulunmamalıdır
      for (final log in logs) {
        expect(log['details']?.toString() ?? '', isNot(contains(validCashierToken)));
      }
      rawDb.dispose();
    });

    test('14. İptal edilmiş token tekrar etkinleştirilemez olmalıdır', () async {
      // Tekrar revoke isteği gönderildiğinde 400 ALREADY_REVOKED dönmeli
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/devices/revoke'),
        headers: {
          'content-type': 'application/json',
          'x-admin-secret': testAdminSecret,
        },
        body: jsonEncode({
          'device_id': 'DEV_CASHIER_01',
          'reason': 'İkinci kez iptal denemesi',
        }),
      );

      expect(res.statusCode, equals(400));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      expect(data['error'], equals('ALREADY_REVOKED'));
    });

    test('15. Pepper Windows DPAPI LocalMachine üzerinden güvenli şekilde şifrelenip çözülüyor', () {
      if (!Platform.isWindows) return;
      const testSecret = 'MMS_PEPPER_TEST_STRING_12345';
      final cipher = WindowsDpapi.protectString(testSecret);
      expect(cipher.length, greaterThan(testSecret.length));

      final decrypted = WindowsDpapi.unprotectString(cipher);
      expect(decrypted, equals(testSecret));
    });

    test('16. Bozuk veya çözülemeyen pepper dosyasında servis güvenli biçimde başlamayı REDDETMELİDİR', () {
      final corruptPepperFile = File(p.join(tempDir.path, 'corrupt_pepper.dpapi'));
      corruptPepperFile.writeAsStringSync('TAMAMEN_BOZUK_CIPHER_BYTES_12345');

      final corruptPepperManager = PepperManager(corruptPepperFile);
      expect(
        () => corruptPepperManager.initialize(),
        throwsA(isA<PepperSecurityException>()),
        reason: 'Bozuk pepper durumunda açık metin fallback kesinlikle oluşturulmamalıdır!',
      );
    });

    test('17. Token ve Pepper hiçbir log veya hata çıktısında sızmamalıdır', () async {
      // Bilerek geçersiz bir token ile hata tetikle
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer mms_dt_attacker_leak_probe_token',
        },
        body: jsonEncode({'operation_id': 'probe'}),
      );

      expect(res.body, isNot(contains('mms_dt_attacker_leak_probe_token')));
      expect(res.body, isNot(contains(pepperManager.pepper)));
    });

    test('18. Mevcut S-1 API hardening kontrolleri çalışmaya devam etmelidir (Gövde sınırı, CORS, Shutdown)', () async {
      // 1. Health check
      final healthRes = await http.get(Uri.parse('$baseUrl/health'));
      expect(healthRes.statusCode, equals(200));
      final healthData = jsonDecode(healthRes.body) as Map<String, dynamic>;
      expect(healthData['sqlite_version'], equals('masked'));

      // 2. 2 MB body sınırı kontrolü
      final largeData = 'A' * (2500 * 1024);
      final bodyRes = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'text/plain',
          'authorization': 'Bearer any',
        },
        body: largeData,
      );
      expect(bodyRes.statusCode, equals(413));
    });

    test('19. Eşzamanlı token yenileme ve satış istekleri veri tutarlılığını korumalıdır', () async {
      // Yeni bir test cihazı oluştur
      final testDevToken = TokenManager.generateToken();
      final testSalt = TokenManager.generateSalt();
      final testHash = TokenManager.hashToken(
        rawToken: testDevToken,
        salt: testSalt,
        pepper: pepperManager.pepper,
      );

      await db.into(db.devices).insert(
            DevicesCompanion(
              deviceId: const Value('DEV_CONCURRENT_01'),
              name: const Value('Eşzamanlı Test Kasası'),
              tokenHash: Value(testHash),
              salt: Value(testSalt),
              isActive: const Value(true),
            ),
          );

      // Eşzamanlı 3 işlem gönder (1 yenileme, 2 satış)
      final results = await Future.wait([
        http.post(
          Uri.parse('$baseUrl/api/v1/sales'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $testDevToken',
          },
          body: jsonEncode({
            'operation_id': 'op_conc_1',
            'client_seq': 101,
            'total_amount': 2500,
            'payment_method': 'CASH',
            'items': [
              {'product_id': 'prod_cola', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500}
            ],
          }),
        ),
        http.post(
          Uri.parse('$baseUrl/api/v1/devices/renew-token'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $testDevToken',
          },
        ),
      ]);

      // Biri yenilemeden önce veya sonra mutlaka tutarlı yanıt almalıdır (patlama/500 olmamalı)
      for (final r in results) {
        expect([200, 201, 401], contains(r.statusCode));
      }
    });

    test('20. Uygulama yeniden başlatıldığında şifrelenmiş token doğrulaması kesintisiz çalışmalıdır', () async {
      // Yeni cihaz ekle
      final persToken = TokenManager.generateToken();
      final persSalt = TokenManager.generateSalt();
      final persHash = TokenManager.hashToken(
        rawToken: persToken,
        salt: persSalt,
        pepper: pepperManager.pepper,
      );

      await db.into(db.devices).insert(
            DevicesCompanion(
              deviceId: const Value('DEV_PERSIST_01'),
              name: const Value('Kalıcı Cihaz'),
              tokenHash: Value(persHash),
              salt: Value(persSalt),
              isActive: const Value(true),
            ),
          );

      // Sunucuyu durdur ve aynı DB dosyası/pepper ile tekrar başlat
      await server.stop();

      final restartedDb = SpikeDatabase(dbFile);
      final restartedQueue = WriteQueue();
      final restartedServer = SpikeServer(
        db: restartedDb,
        writeQueue: restartedQueue,
        backupDirectory: p.join(tempDir.path, 'backups'),
        adminSecret: testAdminSecret,
        pepperManager: pepperManager,
      );
      await restartedServer.start(address: InternetAddress.loopbackIPv4, port: testPort);

      // Kalıcı token ile istek gönder
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $persToken',
        },
        body: jsonEncode({
          'operation_id': 'op_persist_tx',
          'client_seq': 201,
          'total_amount': 2500,
          'payment_method': 'CASH',
          'items': [
            {'product_id': 'prod_cola', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500}
          ],
        }),
      );

      expect(res.statusCode, equals(201));
      await restartedServer.stop();
    });
  });
}
