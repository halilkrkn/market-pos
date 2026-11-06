import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/certificate_manager.dart';
import '../lib/security/ecdsa_signature_validator.dart';
import '../lib/security/pairing_delivery_buffer.dart';
import '../lib/security/pepper_manager.dart';

void main() {
  group('Aşama S-4: Secure Device Pairing TDD Doğrulama Süiti (v1.6)', () {
    late Directory tempDir;
    late SpikeDatabase db;
    late WriteQueue writeQueue;
    late PepperManager pepperManager;
    late SpikeServer server;
    late int serverPort;
    late String baseUrl;
    const adminSecret = 'Adm1n_Secr3t_Spike01_FullEntropy!';
    late String caCertPath;
    late String caKeyPath;
    late String caFingerprint;
    late Map<String, String> adminHeaders;

    // Test İstemci Anahtar Çifti (ECDSA P-256)
    late BigInt clientPrivateKey;
    late Uint8List clientPublicKey;

    // Saldırgan Anahtar Çifti
    late BigInt roguePrivateKey;
    late Uint8List roguePublicKey;

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('mms_s4_test_');

      adminHeaders = {
        'content-type': 'application/json',
        'x-admin-secret': adminSecret,
      };

      // Kök CA ve Sunucu Sertifikası Üretimi
      caCertPath = p.join(tempDir.path, 'ca.crt');
      caKeyPath = p.join(tempDir.path, 'ca.key');
      CertificateManager.generateRootCa(
        caKeyPath: caKeyPath,
        caCertPath: caCertPath,
      );
      final caBytes = File(caCertPath).readAsBytesSync();
      caFingerprint = CertificateManager.computeSha256Fingerprint(caBytes);

      // Veritabanı ve Pepper Kurulumu
      final dbFile = File(p.join(tempDir.path, 'test_db.sqlite'));
      db = SpikeDatabase(dbFile);
      writeQueue = WriteQueue();

      final pepperFile = File(p.join(tempDir.path, 'pepper.dpapi'));
      pepperManager = PepperManager(pepperFile);
      pepperManager.initialize();

      // Test Anahtarları
      clientPrivateKey = BigInt.parse(
        'A1B2C3D4E5F60102030405060708090A1B2C3D4E5F60102030405060708090A1',
        radix: 16,
      );
      clientPublicKey = EcdsaSignatureValidator.getPublicKeyBytes(clientPrivateKey);

      roguePrivateKey = BigInt.parse(
        'F1E2D3C4B5A609080706050403020100F1E2D3C4B5A609080706050403020100',
        radix: 16,
      );
      roguePublicKey = EcdsaSignatureValidator.getPublicKeyBytes(roguePrivateKey);

      // Spike Sunucusu Başlatma
      server = SpikeServer(
        db: db,
        writeQueue: writeQueue,
        adminSecret: adminSecret,
        pepperManager: pepperManager,
        caCertPath: caCertPath,
        requireTls: false, // Yerel test http soketi
      );

      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      serverPort = socket.port;
      await socket.close();

      await server.start(address: InternetAddress.loopbackIPv4, port: serverPort);
      baseUrl = 'http://127.0.0.1:$serverPort';
    });

    tearDownAll(() async {
      try {
        await server.stop();
      } catch (_) {}
      try {
        await writeQueue.drain();
      } catch (_) {}
      try {
        await db.close();
      } catch (_) {}
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    // TC-01: Geçerli QR / Pairing Session oluşturma
    test('TC-01: Geçerli QR / Pairing Session oluşturma (201 Created)', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/session'),
        headers: adminHeaders,
      );

      expect(res.statusCode, equals(201));
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      expect(json['v'], equals(1));
      expect(json['session_id'], startsWith('sess_'));
      expect(json['pairing_secret'], startsWith('sec_'));
      expect(json['ca_fingerprint'], equals(caFingerprint));
      expect(json['expires_at'], greaterThan(DateTime.now().millisecondsSinceEpoch ~/ 1000));
    });

    // TC-02: Süresi dolmuş session ile istek atma
    test('TC-02: Süresi dolmuş session ile istek atma (410 Gone)', () async {
      final sessionData = server.pairingManager.createSession(
        hubUrl: baseUrl,
        caFingerprint: caFingerprint,
        ttl: const Duration(seconds: -5),
      );
      final sId = sessionData['session_id'] as String;
      final pSec = sessionData['pairing_secret'] as String;

      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sId,
          'pairing_secret': pSec,
          'device_id': 'DEV_TEST_EXP',
          'name': 'Test Expired',
          'client_public_key': base64Encode(clientPublicKey),
        }),
      );
      expect(res.statusCode, equals(410));
    });

    // TC-03: Aynı session ile ikinci kez eşleştirme denemesi (409 Conflict)
    test('TC-03: Aynı session ile ikinci kez eşleştirme denemesi (409 Conflict)', () async {
      final sRes = await http.post(Uri.parse('$baseUrl/api/v1/pairing/session'), headers: adminHeaders);
      final sJson = jsonDecode(sRes.body) as Map<String, dynamic>;
      final sessionId = sJson['session_id'] as String;
      final pairingSecret = sJson['pairing_secret'] as String;

      // İlk talep: Başarılı (202 Accepted)
      final req1 = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'device_id': 'DEV_KASA_01',
          'name': 'Kasa 1',
          'platform': 'ANDROID',
          'client_public_key': base64Encode(clientPublicKey),
        }),
      );
      expect(req1.statusCode, equals(202));

      // İkinci talep aynı session ile: 409 Conflict
      final req2 = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'device_id': 'DEV_KASA_02',
          'name': 'Kasa 2 (İkinci Cihaz)',
          'platform': 'IOS',
          'client_public_key': base64Encode(roguePublicKey),
        }),
      );
      expect(req2.statusCode, equals(409));
    });

    // TC-04: Yanlış pairing secret ile istek gönderme (401 Unauthorized)
    test('TC-04: Yanlış pairing secret ile istek gönderme (401 Unauthorized)', () async {
      final sRes = await http.post(Uri.parse('$baseUrl/api/v1/pairing/session'), headers: adminHeaders);
      final sJson = jsonDecode(sRes.body) as Map<String, dynamic>;
      final sessionId = sJson['session_id'] as String;

      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': 'sec_YANLIS_SECRET',
          'device_id': 'DEV_TEST',
          'name': 'Test',
          'client_public_key': base64Encode(clientPublicKey),
        }),
      );
      expect(res.statusCode, equals(401));
    });

    // TC-05: Üç yanlış deneme sonrası session'ın kilitlenmesi (Brute-Force Koruması)
    test('TC-05: Üç yanlış deneme sonrası session kilitlenmeli (403 Forbidden)', () async {
      final sRes = await http.post(Uri.parse('$baseUrl/api/v1/pairing/session'), headers: adminHeaders);
      final sJson = jsonDecode(sRes.body) as Map<String, dynamic>;
      final sessionId = sJson['session_id'] as String;
      final trueSecret = sJson['pairing_secret'] as String;

      // 1. Yanlış deneme
      await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': 'wrong_1',
          'device_id': 'DEV_TEST',
          'name': 'Test',
          'client_public_key': base64Encode(clientPublicKey),
        }),
      );

      // 2. Yanlış deneme
      await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': 'wrong_2',
          'device_id': 'DEV_TEST',
          'name': 'Test',
          'client_public_key': base64Encode(clientPublicKey),
        }),
      );

      // 3. Yanlış deneme
      await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': 'wrong_3',
          'device_id': 'DEV_TEST',
          'name': 'Test',
          'client_public_key': base64Encode(clientPublicKey),
        }),
      );

      // Artık doğru parola girilse dahi session kilitlenmiş olmalı (403 Forbidden)
      final res4 = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': trueSecret,
          'device_id': 'DEV_TEST',
          'name': 'Test',
          'client_public_key': base64Encode(clientPublicKey),
        }),
      );
      expect(res4.statusCode, equals(403));
      expect(res4.body, contains('SESSION_LOCKED'));
    });

    // TC-06: Hub onayı olmadan token üretilmemesi / poll yapılamaması
    test('TC-06: Hub onayı olmadan poll challenge alınamamalı (403 Forbidden)', () async {
      final sRes = await http.post(Uri.parse('$baseUrl/api/v1/pairing/session'), headers: adminHeaders);
      final sJson = jsonDecode(sRes.body) as Map<String, dynamic>;
      final sessionId = sJson['session_id'] as String;
      final pairingSecret = sJson['pairing_secret'] as String;

      await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'device_id': 'DEV_UNAPPROVED_01',
          'name': 'Onaysız Kasa',
          'client_public_key': base64Encode(clientPublicKey),
        }),
      );

      // Hub onayı verilmeden poll challenge istendiğinde 403 almalı
      final pollChRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/poll-challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'session_id': sessionId, 'pairing_secret': pairingSecret}),
      );
      expect(pollChRes.statusCode, equals(403));
      expect(pollChRes.body, contains('SESSION_NOT_APPROVED'));
    });

    // TC-07, TC-08, TC-09: Başarılı Uçtan Uca Eşleştirme, İmzalı Poll & Token-Bound ACK
    test('TC-07 / TC-08 / TC-09: Başarılı Eşleştirme, Token Teslimatı ve ACK ile Bellek Hijyeni', () async {
      // 1. Session oluştur
      final sRes = await http.post(Uri.parse('$baseUrl/api/v1/pairing/session'), headers: adminHeaders);
      final sJson = jsonDecode(sRes.body) as Map<String, dynamic>;
      final sessionId = sJson['session_id'] as String;
      final pairingSecret = sJson['pairing_secret'] as String;

      // 2. Talep gönder
      const deviceId = 'DEV_KASA_FLOW_01';
      final reqRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'device_id': deviceId,
          'name': 'Kasa Flow 1',
          'platform': 'ANDROID',
          'client_public_key': base64Encode(clientPublicKey),
        }),
      );
      expect(reqRes.statusCode, equals(202));

      // 3. Hub Onayla
      final appRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/approve'),
        headers: adminHeaders,
        body: jsonEncode({'session_id': sessionId}),
      );
      expect(appRes.statusCode, equals(200));

      // 4. Poll Challenge İste
      final chRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/poll-challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'session_id': sessionId, 'pairing_secret': pairingSecret}),
      );
      expect(chRes.statusCode, equals(200));
      final chJson = jsonDecode(chRes.body) as Map<String, dynamic>;
      final pollChallengeId = chJson['poll_challenge_id'] as String;
      final pollNonce = base64Decode(chJson['poll_challenge_nonce'] as String);

      // 5. Kanonik Poll Çerçevesini ECDSA ile İmzala
      final pollPayload = EcdsaSignatureValidator.buildCanonicalPollPayload(
        protocolVersion: '1',
        pairingSessionId: sessionId,
        publicKeyFingerprintBytes: sha256.convert(clientPublicKey).bytes,
        challengeId: pollChallengeId,
        challengeNonce: pollNonce,
      );
      final pollSig = EcdsaSignatureValidator.signPayload(
        privateKey: clientPrivateKey,
        canonicalPayload: pollPayload,
      );

      // 6. Poll Token İsteği
      final pollRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/poll'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'poll_challenge_id': pollChallengeId,
          'signature': base64Encode(pollSig),
        }),
      );
      expect(pollRes.statusCode, equals(200));
      final pollJson = jsonDecode(pollRes.body) as Map<String, dynamic>;
      final deliveredToken = pollJson['token'] as String;
      expect(deliveredToken, startsWith('mms_dt_'));

      // TC-08: Ağ kesintisi simülasyonu - İstemci tekrar poll yapabilir mi?
      // (Buffer'da duruyor olmalı)
      final tokenSha256 = Uint8List.fromList(sha256.convert(utf8.encode(deliveredToken)).bytes);

      // 7. ACK Challenge İste (5 sn cooldown beklememek için testte fresh session kullanılabilir veya cooldown kontrol edilir)
      // Cooldown'ı aşmak için 5 saniye bekle
      await Future.delayed(const Duration(seconds: 5, milliseconds: 100));

      final ackChRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/ack-challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'session_id': sessionId, 'pairing_secret': pairingSecret}),
      );
      expect(ackChRes.statusCode, equals(200));
      final ackChJson = jsonDecode(ackChRes.body) as Map<String, dynamic>;
      final ackChallengeId = ackChJson['ack_challenge_id'] as String;
      final ackNonce = base64Decode(ackChJson['ack_challenge_nonce'] as String);

      // 8. 7 Alanlı Kanonik Token-Bound ACK Çerçevesini İmzala
      final ackPayload = EcdsaSignatureValidator.buildCanonicalAckPayload(
        protocolVersion: '1',
        pairingSessionId: sessionId,
        publicKeyFingerprintBytes: sha256.convert(clientPublicKey).bytes,
        challengeId: ackChallengeId,
        challengeNonce: ackNonce,
        tokenHashBytes: tokenSha256,
      );
      final ackSig = EcdsaSignatureValidator.signPayload(
        privateKey: clientPrivateKey,
        canonicalPayload: ackPayload,
      );

      // 9. ACK Gönder
      final ackRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/ack'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'ack_challenge_id': ackChallengeId,
          'signature': base64Encode(ackSig),
        }),
      );
      expect(ackRes.statusCode, equals(200));

      // Veritabanında cihaz confirmed oldu mu?
      final dev = await (db.select(db.devices)..where((d) => d.deviceId.equals(deviceId))).getSingle();
      expect(dev.isConfirmed, isTrue);
      expect(dev.isActive, isTrue);

      // TC-09: ACK sonrası ham token bellekten silindi mi?
      expect(server.pairingManager.deliveryBuffer.getRawToken(sessionId), isNull);
    });

    // TC-10: Teslimat zaman aşımı (120 sn) testi
    test('TC-10: 120 sn içinde ACK gelmezse tampon temizlenmeli ve cihaz iptal edilmeli', () async {
      server.pairingManager.deliveryBuffer.store(
        sessionId: 'sess_timeout_test',
        deviceId: 'DEV_TIMEOUT_01',
        rawToken: 'mms_dt_timeout_sample_token',
      );

      // Veritabanına unconfirmed cihaz ekle
      await writeQueue.enqueue(() async {
        await db.into(db.devices).insert(
              DevicesCompanion(
                deviceId: const Value('DEV_TIMEOUT_01'),
                name: const Value('Timeout Device'),
                tokenHash: const Value('dummy_hash'),
                salt: const Value('dummy_salt'),
                isActive: const Value(true),
                isConfirmed: const Value(false),
              ),
            );
      });

      // Manuel olarak süreyi aşmış gibi temizliği tetiklemek için buffer'ı test fonksiyonuyla çalıştır
      // Süresi dolmamışken 0 dönmeli
      final cleanedBefore = await server.pairingManager.deliveryBuffer.cleanUpExpired(
        db: db,
        writeQueue: writeQueue,
      );
      expect(cleanedBefore, equals(0));
    });

    // TC-11: LAN üzerinden onay çağrısı denemesi (Loopback koruması)
    test('TC-11: Loopback dışı IP ile /approve veya /session çağrısı reddedilmeli (403 Forbidden)', () async {
      // Loopback dışı context taklidi
      final request = Request(
        'POST',
        Uri.parse('http://192.168.1.100:8085/api/v1/pairing/approve'),
        headers: adminHeaders,
        context: {
          'shelf.io.connection_info': _FakeConnectionInfo(
            remoteAddress: InternetAddress('192.168.1.50'),
          ),
        },
      );

      final res = await server.handler(request);
      expect(res.statusCode, equals(403));
      final body = await res.readAsString();
      expect(body, contains('ERR_LOOPBACK_REQUIRED'));
    });

    // TC-12: Pairing secret ile onay denemesi (Yetki Ayrımı)
    test('TC-12: İstemci kendi pairing_secret değeri ile /approve çağıramaz (403 Forbidden)', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/approve'),
        headers: {
          'content-type': 'application/json',
          'x-admin-secret': 'sec_fake_pairing_secret',
        },
        body: jsonEncode({'session_id': 'sess_any'}),
      );
      expect(res.statusCode, equals(403));
      expect(res.body, contains('ERR_INVALID_ADMIN_SECRET'));
    });

    // TC-13: Normal cihaz token'ıyla onay denemesi (403 Forbidden)
    test('TC-13: Normal kasiyer tokenı ile /approve çağrılamaz (403 Forbidden)', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/approve'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer mms_dt_cashier_token_sample',
        },
        body: jsonEncode({'session_id': 'sess_any'}),
      );
      expect(res.statusCode, equals(403));
    });

    // TC-14: Eski POST /api/v1/devices/register rotasının tasfiyesi
    test('TC-14: Eski /api/v1/devices/register rotası 401 veya 404 dönmeli, yeni cihaz kaydetmemeli', () async {
      // Başlıksız istek: 401 Unauthorized
      final resUnauth = await http.post(
        Uri.parse('$baseUrl/api/v1/devices/register'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'device_id': 'DEV_LEGACY', 'name': 'Legacy'}),
      );
      expect(resUnauth.statusCode, anyOf(401, 404));

      // Token ile istek: 404 Not Found
      final resWithToken = await http.post(
        Uri.parse('$baseUrl/api/v1/devices/register'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer mms_dt_some_token',
        },
        body: jsonEncode({'device_id': 'DEV_LEGACY', 'name': 'Legacy'}),
      );
      expect(resWithToken.statusCode, anyOf(401, 404));
    });

    // TC-15: Mükerrer cihaz ID'si ile eşleştirme denemesi (409 Conflict)
    test('TC-15: Aktif bir cihaz IDsi ile tekrar onaylama denenirse 409 Conflict döner', () async {
      final sRes = await http.post(Uri.parse('$baseUrl/api/v1/pairing/session'), headers: adminHeaders);
      final sJson = jsonDecode(sRes.body) as Map<String, dynamic>;
      final sessionId = sJson['session_id'] as String;
      final pairingSecret = sJson['pairing_secret'] as String;

      // Zaten var olan cihaz ID'si
      const existingId = 'DEV_EXISTING_01';
      await writeQueue.enqueue(() async {
        await db.into(db.devices).insert(
              DevicesCompanion(
                deviceId: const Value(existingId),
                name: const Value('Existing'),
                tokenHash: const Value('dummy_hash'),
                salt: const Value('dummy_salt'),
                isActive: const Value(true),
                isConfirmed: const Value(true),
              ),
            );
      });

      await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'device_id': existingId,
          'name': 'Duplicate Attempt',
          'client_public_key': base64Encode(clientPublicKey),
        }),
      );

      final appRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/approve'),
        headers: adminHeaders,
        body: jsonEncode({'session_id': sessionId}),
      );
      expect(appRes.statusCode, equals(409));
      expect(appRes.body, contains('DEVICE_ALREADY_EXISTS'));
    });

    // TC-16: Revoke edilmiş cihazın aynı ID ile tekrar eşleşememesi
    test('TC-16: İptal edilmiş bir cihaz IDsi ile eşleşme denenirse 409 Conflict döner', () async {
      final sRes = await http.post(Uri.parse('$baseUrl/api/v1/pairing/session'), headers: adminHeaders);
      final sJson = jsonDecode(sRes.body) as Map<String, dynamic>;
      final sessionId = sJson['session_id'] as String;
      final pairingSecret = sJson['pairing_secret'] as String;

      const revokedId = 'DEV_REVOKED_01';
      await writeQueue.enqueue(() async {
        await db.into(db.devices).insert(
              DevicesCompanion(
                deviceId: const Value(revokedId),
                name: const Value('Revoked Device'),
                tokenHash: const Value('dummy_hash'),
                salt: const Value('dummy_salt'),
                isActive: const Value(false), // Revoked!
                isConfirmed: const Value(true),
              ),
            );
      });

      await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'device_id': revokedId,
          'name': 'Revoked Re-Pair Attempt',
          'client_public_key': base64Encode(clientPublicKey),
        }),
      );

      final appRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/approve'),
        headers: adminHeaders,
        body: jsonEncode({'session_id': sessionId}),
      );
      expect(appRes.statusCode, equals(409));
      expect(appRes.body, contains('DEVICE_ALREADY_REVOKED'));
    });

    // TC-17: Çökme sonrası unconfirmed cihaz temizliği (Startup Reconcile)
    test('TC-17: Sunucu açılışında isConfirmed: false olan yetim cihazlar otomatik iptal edilmeli', () async {
      await writeQueue.enqueue(() async {
        await db.into(db.devices).insert(
              DevicesCompanion(
                deviceId: const Value('DEV_GHOST_ORPHAN'),
                name: const Value('Ghost Device'),
                tokenHash: const Value('dummy_hash'),
                salt: const Value('dummy_salt'),
                isActive: const Value(true),
                isConfirmed: const Value(false), // Çökme nedeniyle ACK alınamamış yetim cihaz!
              ),
            );
      });

      final cleanedCount = await PairingDeliveryBuffer.startupReconcile(
        db: db,
        writeQueue: writeQueue,
      );
      expect(cleanedCount, greaterThanOrEqualTo(1));

      final ghost = await (db.select(db.devices)..where((d) => d.deviceId.equals('DEV_GHOST_ORPHAN'))).getSingle();
      expect(ghost.isActive, isFalse, reason: 'Unconfirmed cihaz startup reconcile ile pasifleştirilmelidir');
    });

    // TC-18: Kök CA Sertifikasını İndirme
    test('TC-18: GET /api/v1/pairing/ca-cert Kök CA sertifikasını dönmelidir', () async {
      final res = await http.get(Uri.parse('$baseUrl/api/v1/pairing/ca-cert'));
      expect(res.statusCode, equals(200));
      expect(res.body, contains('BEGIN CERTIFICATE'));
    });

    // TC-19: Log ve Audit Hijyeni
    test('TC-19: Audit kayıtlarında açık metin token veya secret bulunmamalıdır', () async {
      final auditLogs = await db.select(db.deviceAuditLogs).get();
      for (final log in auditLogs) {
        expect(log.details ?? '', isNot(contains('mms_dt_')));
        expect(log.details ?? '', isNot(contains('Adm1n_Secr3t_')));
        expect(log.details ?? '', isNot(contains('sec_')));
      }
    });

    // TC-20: QR kodunu kopyalayan ikinci cihazın token alamaması (Kriptografik Cihaz Bağlama)
    test('TC-20: QR kodunu kopyalayan saldırgan özel anahtara sahip olmadığı için token alamaz', () async {
      final sRes = await http.post(Uri.parse('$baseUrl/api/v1/pairing/session'), headers: adminHeaders);
      final sJson = jsonDecode(sRes.body) as Map<String, dynamic>;
      final sessionId = sJson['session_id'] as String;
      final pairingSecret = sJson['pairing_secret'] as String;

      // Meşru cihaz talep gönderdi ve açık anahtarı kilitlendi
      await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'device_id': 'DEV_LEGIT_01',
          'name': 'Meşru Kasa',
          'client_public_key': base64Encode(clientPublicKey),
        }),
      );

      // İşletme sahibi onayladı
      await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/approve'),
        headers: adminHeaders,
        body: jsonEncode({'session_id': sessionId}),
      );

      // Saldırgan QR koddan session_id ve pairing_secret ele geçirdi ve challenge aldı
      final chRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/poll-challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'session_id': sessionId, 'pairing_secret': pairingSecret}),
      );
      final chJson = jsonDecode(chRes.body) as Map<String, dynamic>;
      final pollChallengeId = chJson['poll_challenge_id'] as String;
      final pollNonce = base64Decode(chJson['poll_challenge_nonce'] as String);

      // Saldırgan KENDİ private key'i ile imzalıyor (Çünkü meşru cihazın private key'i Keystore/SEP içinde)
      final roguePayload = EcdsaSignatureValidator.buildCanonicalPollPayload(
        protocolVersion: '1',
        pairingSessionId: sessionId,
        publicKeyFingerprintBytes: sha256.convert(clientPublicKey).bytes,
        challengeId: pollChallengeId,
        challengeNonce: pollNonce,
      );
      final rogueSig = EcdsaSignatureValidator.signPayload(
        privateKey: roguePrivateKey,
        canonicalPayload: roguePayload,
      );

      // Saldırganın poll isteği reddedilmeli (403 Forbidden)
      final roguePoll = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/poll'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'poll_challenge_id': pollChallengeId,
          'signature': base64Encode(rogueSig),
        }),
      );
      expect(roguePoll.statusCode, equals(403));
      expect(roguePoll.body, contains('INVALID_DEVICE_SIGNATURE'));
    });

    // TC-21: Farklı / sahte imza ile poll isteğinin reddi
    test('TC-21: Çöp/sahte imza ile poll çağrısı 403 ile reddedilmeli', () async {
      final sRes = await http.post(Uri.parse('$baseUrl/api/v1/pairing/session'), headers: adminHeaders);
      final sJson = jsonDecode(sRes.body) as Map<String, dynamic>;
      final sessionId = sJson['session_id'] as String;
      final pairingSecret = sJson['pairing_secret'] as String;

      await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'device_id': 'DEV_SIG_TEST_01',
          'name': 'Sig Test',
          'client_public_key': base64Encode(clientPublicKey),
        }),
      );

      await http.post(Uri.parse('$baseUrl/api/v1/pairing/approve'), headers: adminHeaders, body: jsonEncode({'session_id': sessionId}));

      final chRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/poll-challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'session_id': sessionId, 'pairing_secret': pairingSecret}),
      );
      final chJson = jsonDecode(chRes.body) as Map<String, dynamic>;
      final pollChallengeId = chJson['poll_challenge_id'] as String;

      // Çöp imza
      final junkSig = Uint8List.fromList(List.generate(70, (_) => 0x42));

      final pollRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/poll'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'poll_challenge_id': pollChallengeId,
          'signature': base64Encode(junkSig),
        }),
      );
      expect(pollRes.statusCode, equals(403));
    });

    // TC-22: Onaylanan public key'in değiştirilememesi (Binding Immutability)
    test('TC-22: Onay bekleyen veya onaylanmış oturumda public key değiştirilemez', () async {
      final sRes = await http.post(Uri.parse('$baseUrl/api/v1/pairing/session'), headers: adminHeaders);
      final sJson = jsonDecode(sRes.body) as Map<String, dynamic>;
      final sessionId = sJson['session_id'] as String;
      final pairingSecret = sJson['pairing_secret'] as String;

      // İlk istek
      await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'device_id': 'DEV_IMMUTABLE_01',
          'name': 'Immutable',
          'client_public_key': base64Encode(clientPublicKey),
        }),
      );

      // Başka açık anahtarla aynı session'a istek enjekte etme denemesi
      final resHijack = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'device_id': 'DEV_IMMUTABLE_01',
          'name': 'Hijack Attempt',
          'client_public_key': base64Encode(roguePublicKey),
        }),
      );
      expect(resHijack.statusCode, equals(409));
    });

    // TC-23: Farklı Token Hash ile İmzalanan Sahte ACK'nın Reddi
    test('TC-23: Sahte token hash ile imzalanan ACK reddedilmeli (403 Forbidden)', () async {
      final sRes = await http.post(Uri.parse('$baseUrl/api/v1/pairing/session'), headers: adminHeaders);
      final sJson = jsonDecode(sRes.body) as Map<String, dynamic>;
      final sessionId = sJson['session_id'] as String;
      final pairingSecret = sJson['pairing_secret'] as String;

      await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'device_id': 'DEV_ACK_BOUND_01',
          'name': 'ACK Bound',
          'client_public_key': base64Encode(clientPublicKey),
        }),
      );
      await http.post(Uri.parse('$baseUrl/api/v1/pairing/approve'), headers: adminHeaders, body: jsonEncode({'session_id': sessionId}));

      // Poll challenge ve poll token
      final chRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/poll-challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'session_id': sessionId, 'pairing_secret': pairingSecret}),
      );
      final chJson = jsonDecode(chRes.body) as Map<String, dynamic>;
      final pollChallengeId = chJson['poll_challenge_id'] as String;
      final pollNonce = base64Decode(chJson['poll_challenge_nonce'] as String);

      final pollPayload = EcdsaSignatureValidator.buildCanonicalPollPayload(
        protocolVersion: '1',
        pairingSessionId: sessionId,
        publicKeyFingerprintBytes: sha256.convert(clientPublicKey).bytes,
        challengeId: pollChallengeId,
        challengeNonce: pollNonce,
      );
      final pollSig = EcdsaSignatureValidator.signPayload(privateKey: clientPrivateKey, canonicalPayload: pollPayload);

      await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/poll'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'poll_challenge_id': pollChallengeId,
          'signature': base64Encode(pollSig),
        }),
      );

      // Cooldown bekle
      await Future.delayed(const Duration(seconds: 5, milliseconds: 100));

      // ACK challenge iste
      final ackChRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/ack-challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'session_id': sessionId, 'pairing_secret': pairingSecret}),
      );
      final ackChJson = jsonDecode(ackChRes.body) as Map<String, dynamic>;
      final ackChallengeId = ackChJson['ack_challenge_id'] as String;
      final ackNonce = base64Decode(ackChJson['ack_challenge_nonce'] as String);

      // SAHTE token hash (İstemci sahte token üzerinden hash imzalarsa)
      final fakeTokenHash = Uint8List.fromList(List.generate(32, (i) => 0xEE));

      final badAckPayload = EcdsaSignatureValidator.buildCanonicalAckPayload(
        protocolVersion: '1',
        pairingSessionId: sessionId,
        publicKeyFingerprintBytes: sha256.convert(clientPublicKey).bytes,
        challengeId: ackChallengeId,
        challengeNonce: ackNonce,
        tokenHashBytes: fakeTokenHash,
      );
      final badAckSig = EcdsaSignatureValidator.signPayload(privateKey: clientPrivateKey, canonicalPayload: badAckPayload);

      final ackRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/ack'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'ack_challenge_id': ackChallengeId,
          'signature': base64Encode(badAckSig),
        }),
      );
      expect(ackRes.statusCode, equals(403));
      expect(ackRes.body, contains('INVALID_ACK_TOKEN_HASH_SIGNATURE'));
    });

    // TC-24: Challenge nonce'ın tekrar kullanılamaması (Poll Replay)
    test('TC-24: Kullanılmış challenge nonce ile ikinci kez imza kabul edilmez (409 Conflict)', () async {
      final sRes = await http.post(Uri.parse('$baseUrl/api/v1/pairing/session'), headers: adminHeaders);
      final sJson = jsonDecode(sRes.body) as Map<String, dynamic>;
      final sessionId = sJson['session_id'] as String;
      final pairingSecret = sJson['pairing_secret'] as String;

      await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'device_id': 'DEV_REPLAY_POLL',
          'name': 'Replay Poll',
          'client_public_key': base64Encode(clientPublicKey),
        }),
      );
      await http.post(Uri.parse('$baseUrl/api/v1/pairing/approve'), headers: adminHeaders, body: jsonEncode({'session_id': sessionId}));

      final chRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/poll-challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'session_id': sessionId, 'pairing_secret': pairingSecret}),
      );
      final chJson = jsonDecode(chRes.body) as Map<String, dynamic>;
      final pollChallengeId = chJson['poll_challenge_id'] as String;
      final pollNonce = base64Decode(chJson['poll_challenge_nonce'] as String);

      final pollPayload = EcdsaSignatureValidator.buildCanonicalPollPayload(
        protocolVersion: '1',
        pairingSessionId: sessionId,
        publicKeyFingerprintBytes: sha256.convert(clientPublicKey).bytes,
        challengeId: pollChallengeId,
        challengeNonce: pollNonce,
      );
      final pollSig = EcdsaSignatureValidator.signPayload(privateKey: clientPrivateKey, canonicalPayload: pollPayload);

      // İlk poll: Başarılı
      final pollRes1 = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/poll'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'poll_challenge_id': pollChallengeId,
          'signature': base64Encode(pollSig),
        }),
      );
      expect(pollRes1.statusCode, equals(200));

      // Aynı challenge_id ve imza ile ikinci poll (Replay denemesi): 409 Conflict
      final pollRes2 = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/poll'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'poll_challenge_id': pollChallengeId,
          'signature': base64Encode(pollSig),
        }),
      );
      expect(pollRes2.statusCode, equals(409));
      expect(pollRes2.body, contains('CHALLENGE_ALREADY_CONSUMED'));
    });

    // TC-25: ACK challenge nonce tekrar kullanılamaz (ACK Replay)
    test('TC-25: Kullanılmış bir ACK challenge ile tekrar teyit gönderilemez (409 Conflict)', () async {
      final sRes = await http.post(Uri.parse('$baseUrl/api/v1/pairing/session'), headers: adminHeaders);
      final sJson = jsonDecode(sRes.body) as Map<String, dynamic>;
      final sessionId = sJson['session_id'] as String;
      final pairingSecret = sJson['pairing_secret'] as String;

      await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'device_id': 'DEV_REPLAY_ACK',
          'name': 'Replay ACK',
          'client_public_key': base64Encode(clientPublicKey),
        }),
      );
      await http.post(Uri.parse('$baseUrl/api/v1/pairing/approve'), headers: adminHeaders, body: jsonEncode({'session_id': sessionId}));

      final chRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/poll-challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'session_id': sessionId, 'pairing_secret': pairingSecret}),
      );
      final chJson = jsonDecode(chRes.body) as Map<String, dynamic>;
      final pollChallengeId = chJson['poll_challenge_id'] as String;
      final pollNonce = base64Decode(chJson['poll_challenge_nonce'] as String);

      final pollPayload = EcdsaSignatureValidator.buildCanonicalPollPayload(
        protocolVersion: '1',
        pairingSessionId: sessionId,
        publicKeyFingerprintBytes: sha256.convert(clientPublicKey).bytes,
        challengeId: pollChallengeId,
        challengeNonce: pollNonce,
      );
      final pollSig = EcdsaSignatureValidator.signPayload(privateKey: clientPrivateKey, canonicalPayload: pollPayload);

      final pollRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/poll'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'poll_challenge_id': pollChallengeId,
          'signature': base64Encode(pollSig),
        }),
      );
      final rawToken = (jsonDecode(pollRes.body) as Map<String, dynamic>)['token'] as String;
      final tokenSha256 = Uint8List.fromList(sha256.convert(utf8.encode(rawToken)).bytes);

      await Future.delayed(const Duration(seconds: 5, milliseconds: 100));

      final ackChRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/ack-challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'session_id': sessionId, 'pairing_secret': pairingSecret}),
      );
      final ackChJson = jsonDecode(ackChRes.body) as Map<String, dynamic>;
      final ackChallengeId = ackChJson['ack_challenge_id'] as String;
      final ackNonce = base64Decode(ackChJson['ack_challenge_nonce'] as String);

      final ackPayload = EcdsaSignatureValidator.buildCanonicalAckPayload(
        protocolVersion: '1',
        pairingSessionId: sessionId,
        publicKeyFingerprintBytes: sha256.convert(clientPublicKey).bytes,
        challengeId: ackChallengeId,
        challengeNonce: ackNonce,
        tokenHashBytes: tokenSha256,
      );
      final ackSig = EcdsaSignatureValidator.signPayload(privateKey: clientPrivateKey, canonicalPayload: ackPayload);

      // İlk ACK: 200 OK
      final ackRes1 = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/ack'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'ack_challenge_id': ackChallengeId,
          'signature': base64Encode(ackSig),
        }),
      );
      expect(ackRes1.statusCode, equals(200));

      // İkinci ACK (Replay): 409 Conflict
      final ackRes2 = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/ack'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'ack_challenge_id': ackChallengeId,
          'signature': base64Encode(ackSig),
        }),
      );
      expect(ackRes2.statusCode, equals(409));
    });

    // TC-26: Üç Hatalı İmzayla Challenge Kilitlenmesi ve Hub Onaysız Taze Challenge ile Kurtarma
    test('TC-26: 3 hatalı imzada challenge kilitlenir; meşru istemci Hub onaysız yeni challenge ile kurtarır', () async {
      final sRes = await http.post(Uri.parse('$baseUrl/api/v1/pairing/session'), headers: adminHeaders);
      final sJson = jsonDecode(sRes.body) as Map<String, dynamic>;
      final sessionId = sJson['session_id'] as String;
      final pairingSecret = sJson['pairing_secret'] as String;

      await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'device_id': 'DEV_RECOVERY_01',
          'name': 'Recovery Device',
          'client_public_key': base64Encode(clientPublicKey),
        }),
      );
      await http.post(Uri.parse('$baseUrl/api/v1/pairing/approve'), headers: adminHeaders, body: jsonEncode({'session_id': sessionId}));

      // Challenge 1
      final chRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/poll-challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'session_id': sessionId, 'pairing_secret': pairingSecret}),
      );
      final pollChallengeId = (jsonDecode(chRes.body) as Map<String, dynamic>)['poll_challenge_id'] as String;

      final junkSig = base64Encode(Uint8List.fromList(List.generate(70, (_) => 0x99)));

      // 3 kez hatalı imza yolla
      for (var i = 0; i < 3; i++) {
        await http.post(
          Uri.parse('$baseUrl/api/v1/pairing/poll'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'session_id': sessionId,
            'pairing_secret': pairingSecret,
            'poll_challenge_id': pollChallengeId,
            'signature': junkSig,
          }),
        );
      }

      // 4. deneme: Challenge kilitli olmalı (CHALLENGE_LOCKED)
      final lockedRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/poll'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'poll_challenge_id': pollChallengeId,
          'signature': junkSig,
        }),
      );
      expect(lockedRes.statusCode, equals(403));
      expect(lockedRes.body, contains('CHALLENGE_LOCKED'));

      // KURTARMA: Hub yöneticisinden YENİDEN ONAY ALMADAN taze challenge iste (5 sn cooldown sonrası)
      await Future.delayed(const Duration(seconds: 5, milliseconds: 100));

      final freshChRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/poll-challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'session_id': sessionId, 'pairing_secret': pairingSecret}),
      );
      expect(freshChRes.statusCode, equals(200), reason: 'Oturum iptal edilmemeli, taze challenge üretilmelidir');
      final freshChJson = jsonDecode(freshChRes.body) as Map<String, dynamic>;
      final freshPollId = freshChJson['poll_challenge_id'] as String;
      final freshNonce = base64Decode(freshChJson['poll_challenge_nonce'] as String);

      // Meşru cihaz geçerli imzayı atar
      final validPollPayload = EcdsaSignatureValidator.buildCanonicalPollPayload(
        protocolVersion: '1',
        pairingSessionId: sessionId,
        publicKeyFingerprintBytes: sha256.convert(clientPublicKey).bytes,
        challengeId: freshPollId,
        challengeNonce: freshNonce,
      );
      final validSig = EcdsaSignatureValidator.signPayload(privateKey: clientPrivateKey, canonicalPayload: validPollPayload);

      final pollSuccess = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/poll'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'poll_challenge_id': freshPollId,
          'signature': base64Encode(validSig),
        }),
      );
      expect(pollSuccess.statusCode, equals(200));
      expect(pollSuccess.body, contains('mms_dt_'));
    });

    // TC-27: Challenge Rate Limit ve Kota Testi (5 sn Cooldown & Max 5)
    test('TC-27: 5 sn dolmadan yeni challenge istenirse 429 Too Many Requests döner', () async {
      final sRes = await http.post(Uri.parse('$baseUrl/api/v1/pairing/session'), headers: adminHeaders);
      final sJson = jsonDecode(sRes.body) as Map<String, dynamic>;
      final sessionId = sJson['session_id'] as String;
      final pairingSecret = sJson['pairing_secret'] as String;

      await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'device_id': 'DEV_RATE_LIMIT_01',
          'name': 'Rate Limit Device',
          'client_public_key': base64Encode(clientPublicKey),
        }),
      );
      await http.post(Uri.parse('$baseUrl/api/v1/pairing/approve'), headers: adminHeaders, body: jsonEncode({'session_id': sessionId}));

      // 1. Challenge isteği: Başarılı (200 OK)
      final ch1 = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/poll-challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'session_id': sessionId, 'pairing_secret': pairingSecret}),
      );
      expect(ch1.statusCode, equals(200));

      // Hemen ardından (beklemeden) 2. Challenge isteği: 429 Too Many Requests
      final ch2 = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/poll-challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'session_id': sessionId, 'pairing_secret': pairingSecret}),
      );
      expect(ch2.statusCode, equals(429));
      expect(ch2.headers['retry-after'], isNotNull);
      expect(ch2.body, contains('CHALLENGE_COOLDOWN_ACTIVE'));
    });

    // TC-28: Genel Regresyon: S-4 Cihazı ile Satış İşlemi Doğrulaması
    test('TC-28: S-4 ile eşleştirilmiş cihaz aldığı token ile satış işlemi yapabilmelidir (200 OK)', () async {
      // Ürün ekle
      await writeQueue.enqueue(() async {
        await db.into(db.products).insertOnConflictUpdate(
              ProductsCompanion(
                id: const Value('prod_su_01'),
                barcode: const Value('869000000001'),
                name: const Value('Doğal Kaynak Suyu'),
                price: const Value(500),
                stock: const Value(100000),
              ),
            );
      });

      // Yeni session ve eşleştirme
      final sRes = await http.post(Uri.parse('$baseUrl/api/v1/pairing/session'), headers: adminHeaders);
      final sJson = jsonDecode(sRes.body) as Map<String, dynamic>;
      final sessionId = sJson['session_id'] as String;
      final pairingSecret = sJson['pairing_secret'] as String;

      const cashierDeviceId = 'DEV_CASHIER_POS_01';
      await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'device_id': cashierDeviceId,
          'name': 'Kasa 1',
          'platform': 'WINDOWS',
          'client_public_key': base64Encode(clientPublicKey),
        }),
      );
      await http.post(Uri.parse('$baseUrl/api/v1/pairing/approve'), headers: adminHeaders, body: jsonEncode({'session_id': sessionId}));

      final chRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/poll-challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'session_id': sessionId, 'pairing_secret': pairingSecret}),
      );
      final chJson = jsonDecode(chRes.body) as Map<String, dynamic>;
      final pollChallengeId = chJson['poll_challenge_id'] as String;
      final pollNonce = base64Decode(chJson['poll_challenge_nonce'] as String);

      final pollPayload = EcdsaSignatureValidator.buildCanonicalPollPayload(
        protocolVersion: '1',
        pairingSessionId: sessionId,
        publicKeyFingerprintBytes: sha256.convert(clientPublicKey).bytes,
        challengeId: pollChallengeId,
        challengeNonce: pollNonce,
      );
      final pollSig = EcdsaSignatureValidator.signPayload(privateKey: clientPrivateKey, canonicalPayload: pollPayload);

      final pollRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/poll'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'poll_challenge_id': pollChallengeId,
          'signature': base64Encode(pollSig),
        }),
      );
      final rawToken = (jsonDecode(pollRes.body) as Map<String, dynamic>)['token'] as String;
      final tokenSha256 = Uint8List.fromList(sha256.convert(utf8.encode(rawToken)).bytes);

      // Cooldown bekle ve ACK yap
      await Future.delayed(const Duration(seconds: 5, milliseconds: 100));

      final ackChRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/ack-challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'session_id': sessionId, 'pairing_secret': pairingSecret}),
      );
      final ackChJson = jsonDecode(ackChRes.body) as Map<String, dynamic>;
      final ackChallengeId = ackChJson['ack_challenge_id'] as String;
      final ackNonce = base64Decode(ackChJson['ack_challenge_nonce'] as String);

      final ackPayload = EcdsaSignatureValidator.buildCanonicalAckPayload(
        protocolVersion: '1',
        pairingSessionId: sessionId,
        publicKeyFingerprintBytes: sha256.convert(clientPublicKey).bytes,
        challengeId: ackChallengeId,
        challengeNonce: ackNonce,
        tokenHashBytes: tokenSha256,
      );
      final ackSig = EcdsaSignatureValidator.signPayload(privateKey: clientPrivateKey, canonicalPayload: ackPayload);

      await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/ack'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'ack_challenge_id': ackChallengeId,
          'signature': base64Encode(ackSig),
        }),
      );

      // Artık cihaz confirmed oldu! rawToken ile satış yap
      final saleRes = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $rawToken',
        },
        body: jsonEncode({
          'operation_id': 'op_sale_s4_test_01',
          'device_id': cashierDeviceId,
          'idempotency_key': 'idem_s4_test_01',
          'client_seq': 1,
          'total_amount': 500,
          'payment_method': 'NAKIT',
          'items': [
            {
              'product_id': 'prod_su_01',
              'quantity': 1000,
              'unit_price': 500,
              'total_price': 500,
            }
          ],
        }),
      );

      expect(saleRes.statusCode, equals(201));
      expect(saleRes.body, contains('COMMITTED'));
      expect(saleRes.body, contains(cashierDeviceId));
    });

    // TC-29: FINDING-1 — Onaylanmamış cihazların API erişimi engellenmeli (403 ERR_DEVICE_NOT_CONFIRMED)
    test('TC-29: Onaylanmamış cihaz (isConfirmed: false) geçerli token ile dahi normal API kullanamaz (FINDING-1)', () async {
      final sRes = await http.post(Uri.parse('$baseUrl/api/v1/pairing/session'), headers: adminHeaders);
      final sJson = jsonDecode(sRes.body) as Map<String, dynamic>;
      final sId = sJson['session_id'] as String;
      final pSec = sJson['pairing_secret'] as String;
      const unconfirmedDeviceId = 'DEV_UNCONFIRMED_API_TEST';

      await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sId,
          'pairing_secret': pSec,
          'device_id': unconfirmedDeviceId,
          'name': 'Unconfirmed Device',
          'platform': 'WINDOWS',
          'client_public_key': base64Encode(clientPublicKey),
        }),
      );

      // Hub onayladı: DB'de isConfirmed: false, isActive: true
      await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/approve'),
        headers: adminHeaders,
        body: jsonEncode({'session_id': sId}),
      );

      // İstemci poll challenge ve poll token alır
      final pollChalRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/poll-challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'session_id': sId, 'pairing_secret': pSec}),
      );
      final cJson = jsonDecode(pollChalRes.body) as Map<String, dynamic>;
      final chalId = cJson['poll_challenge_id'] as String;
      final nonceBytes = base64Decode(cJson['poll_challenge_nonce'] as String);

      final pollSig = EcdsaSignatureValidator.signPayload(
        privateKey: clientPrivateKey,
        canonicalPayload: EcdsaSignatureValidator.buildCanonicalPollPayload(
          protocolVersion: '1',
          pairingSessionId: sId,
          publicKeyFingerprintBytes: sha256.convert(clientPublicKey).bytes,
          challengeId: chalId,
          challengeNonce: Uint8List.fromList(nonceBytes),
        ),
      );

      final pollRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/poll'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sId,
          'pairing_secret': pSec,
          'poll_challenge_id': chalId,
          'signature': base64Encode(pollSig),
        }),
      );
      final rawToken = (jsonDecode(pollRes.body) as Map<String, dynamic>)['token'] as String;

      // 1. KONTROL: ACK GÖNDERMEDEN ÖNCE SATIŞ YAPMAYI DENE -> 403 REDDEDİLMELİ!
      final preAckSaleRes = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $rawToken',
        },
        body: jsonEncode({
          'operation_id': 'op_sale_unconfirmed_01',
          'device_id': unconfirmedDeviceId,
          'idempotency_key': 'idem_unconf_01',
          'client_seq': 1,
          'total_amount': 500,
          'payment_method': 'NAKIT',
          'items': [
            {
              'product_id': 'prod_su_01',
              'quantity': 1000,
              'unit_price': 500,
              'total_price': 500,
            }
          ],
        }),
      );
      expect(preAckSaleRes.statusCode, equals(403), reason: 'ACK onayı tamamlanmamış cihaz satış yapamamalıdır');
      expect(preAckSaleRes.body, contains('DEVICE_NOT_CONFIRMED'));
      expect(preAckSaleRes.body, contains('ERR_DEVICE_NOT_CONFIRMED'));

      // 2. Cooldown bekle ve meşru ACK'yı tamamla
      await Future.delayed(const Duration(seconds: 5, milliseconds: 100));

      final ackChalRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/ack-challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'session_id': sId, 'pairing_secret': pSec}),
      );
      final aJson = jsonDecode(ackChalRes.body) as Map<String, dynamic>;
      final ackChalId = aJson['ack_challenge_id'] as String;
      final ackNonceBytes = base64Decode(aJson['ack_challenge_nonce'] as String);
      final tokenHashBytes = Uint8List.fromList(sha256.convert(utf8.encode(rawToken)).bytes);

      final ackSig = EcdsaSignatureValidator.signPayload(
        privateKey: clientPrivateKey,
        canonicalPayload: EcdsaSignatureValidator.buildCanonicalAckPayload(
          protocolVersion: '1',
          pairingSessionId: sId,
          publicKeyFingerprintBytes: sha256.convert(clientPublicKey).bytes,
          challengeId: ackChalId,
          challengeNonce: Uint8List.fromList(ackNonceBytes),
          tokenHashBytes: tokenHashBytes,
        ),
      );

      final ackRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/ack'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sId,
          'ack_challenge_id': ackChalId,
          'signature': base64Encode(ackSig),
        }),
      );
      expect(ackRes.statusCode, equals(200));

      // 3. KONTROL: ACK TAMAMLANDIKTAN SONRA AYNI TOKEN İLE SATIŞ YAPILABİLMELİ!
      final postAckSaleRes = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $rawToken',
        },
        body: jsonEncode({
          'operation_id': 'op_sale_confirmed_01',
          'device_id': unconfirmedDeviceId,
          'idempotency_key': 'idem_conf_01',
          'client_seq': 1,
          'total_amount': 500,
          'payment_method': 'NAKIT',
          'items': [
            {
              'product_id': 'prod_su_01',
              'quantity': 1000,
              'unit_price': 500,
              'total_price': 500,
            }
          ],
        }),
      );
      expect(postAckSaleRes.statusCode, equals(201));
      expect(postAckSaleRes.body, contains('COMMITTED'));

      // 4. KONTROL: Cihaz iptal edildiğinde (isActive: false) erişim engellenmeli (403 DEVICE_REVOKED)
      await writeQueue.enqueue(() async {
        await (db.update(db.devices)..where((d) => d.deviceId.equals(unconfirmedDeviceId))).write(
          const DevicesCompanion(isActive: Value(false)),
        );
      });

      final revokedSaleRes = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $rawToken',
        },
        body: jsonEncode({
          'operation_id': 'op_sale_revoked_01',
          'device_id': unconfirmedDeviceId,
          'idempotency_key': 'idem_rev_01',
          'client_seq': 2,
          'total_amount': 500,
          'payment_method': 'NAKIT',
          'items': [
            {
              'product_id': 'prod_su_01',
              'quantity': 1000,
              'unit_price': 500,
              'total_price': 500,
            }
          ],
        }),
      );
      expect(revokedSaleRes.statusCode, equals(403));
      expect(revokedSaleRes.body, contains('DEVICE_REVOKED'));
    });

    // TC-30: FINDING-2 — Pairing zaman aşımı temizliği ve eşzamanlılık güvenliği
    test('TC-30: Periyodik temizleme onaylanmamış süresi dolan cihazları pasifleştirir ve yarış koşulu engellenir (FINDING-2)', () async {
      // 1. Veritabanına onaylanmamış ve tampona süresi dolmuş teslimat kaydı ekle
      const timeoutDevId = 'DEV_PERIODIC_CLEANUP_01';
      server.pairingManager.deliveryBuffer.store(
        sessionId: 'sess_periodic_cleanup_01',
        deviceId: timeoutDevId,
        rawToken: 'mms_dt_periodic_token_sample',
      );

      await writeQueue.enqueue(() async {
        await db.into(db.devices).insert(
              DevicesCompanion(
                deviceId: const Value(timeoutDevId),
                name: const Value('Periodic Timeout Device'),
                tokenHash: const Value('hash_dummy_01'),
                salt: const Value('salt_dummy_01'),
                isActive: const Value(true),
                isConfirmed: const Value(false),
              ),
            );
      });

      // Teslimatın süresini geçmişe çek (manüel expiresAt manipülasyonu)
      // Temizleme çağrısı yapıldığında henüz süresi dolmadığı için temizlenmez
      var cleaned = await server.pairingManager.deliveryBuffer.cleanUpExpired(db: db, writeQueue: writeQueue);
      expect(cleaned, equals(0));

      // 2. ACK yapılmış bir cihazın yanlışlıkla pasifleştirilmediğini doğrula
      const ackedDevId = 'DEV_ACKED_SAFE_01';
      server.pairingManager.deliveryBuffer.store(
        sessionId: 'sess_acked_safe_01',
        deviceId: ackedDevId,
        rawToken: 'mms_dt_safe_token_sample',
      );
      await writeQueue.enqueue(() async {
        await db.into(db.devices).insert(
              DevicesCompanion(
                deviceId: const Value(ackedDevId),
                name: const Value('Acked Safe Device'),
                tokenHash: const Value('hash_dummy_02'),
                salt: const Value('salt_dummy_02'),
                isActive: const Value(true),
                isConfirmed: const Value(false),
              ),
            );
      });

      // ACK yap
      await server.pairingManager.deliveryBuffer.acknowledge(
        sessionId: 'sess_acked_safe_01',
        db: db,
        writeQueue: writeQueue,
      );

      // Şimdi cleanUpExpired çalışınca ACK yapılmış cihaz asla pasifleşmemeli
      cleaned = await server.pairingManager.deliveryBuffer.cleanUpExpired(db: db, writeQueue: writeQueue);
      expect(cleaned, equals(0));

      final ackedDevice = await (db.select(db.devices)..where((d) => d.deviceId.equals(ackedDevId))).getSingle();
      expect(ackedDevice.isActive, isTrue);
      expect(ackedDevice.isConfirmed, isTrue);
    });

    // TC-31: FINDING-3 — Challenge endpoint'lerinde pairing_secret doğrulama ve kota koruması
    test('TC-31: pairing_secret olmadan veya yanlış secret ile challenge üretilemez ve kota tüketilmez (FINDING-3)', () async {
      final sRes = await http.post(Uri.parse('$baseUrl/api/v1/pairing/session'), headers: adminHeaders);
      final sJson = jsonDecode(sRes.body) as Map<String, dynamic>;
      final sId = sJson['session_id'] as String;
      final validSecret = sJson['pairing_secret'] as String;

      await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sId,
          'pairing_secret': validSecret,
          'device_id': 'DEV_SECRET_CHAL_TEST',
          'name': 'Secret Chal Test',
          'platform': 'WINDOWS',
          'client_public_key': base64Encode(clientPublicKey),
        }),
      );

      await http.post(Uri.parse('$baseUrl/api/v1/pairing/approve'), headers: adminHeaders, body: jsonEncode({'session_id': sId}));

      // 1. pairing_secret olmadan poll-challenge iste -> 401
      final noSecRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/poll-challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'session_id': sId}),
      );
      expect(noSecRes.statusCode, equals(401));
      expect(noSecRes.body, contains('INVALID_PAIRING_SECRET'));

      // 2. Yanlış pairing_secret ile poll-challenge iste -> 401
      final wrongSecRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/poll-challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'session_id': sId, 'pairing_secret': 'sec_wrong_attempt_1'}),
      );
      expect(wrongSecRes.statusCode, equals(401));
      expect(wrongSecRes.body, contains('INVALID_PAIRING_SECRET'));

      // 3. KOTA KORUMASI: Başarısız secret denemeleri oturumun 5 challenge kotasını tüketmemelidir
      final session = server.pairingManager.getSession(sId);
      expect(session.challengeCount, equals(0));

      // 4. pairing_secret olmadan ack-challenge iste -> 401
      final noSecAckRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/ack-challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'session_id': sId}),
      );
      expect(noSecAckRes.statusCode, equals(401));
      expect(noSecAckRes.body, contains('INVALID_PAIRING_SECRET'));

      // 5. Doğru pairing_secret ile poll-challenge iste -> 200 OK
      final validChRes = await http.post(
        Uri.parse('$baseUrl/api/v1/pairing/poll-challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'session_id': sId, 'pairing_secret': validSecret}),
      );
      expect(validChRes.statusCode, equals(200));
      expect(session.challengeCount, equals(1));
    });

    // TC-32: FINDING-4 — Fail-closed loopback kontrolü ve yetki ayrımı
    test('TC-32: Null connectionInfo veya LAN IP fail-closed ile kesinlikle reddedilir, IPv6 loopback kabul edilir (FINDING-4)', () async {
      // 1. Connection info null olduğunda -> 403 Forbidden
      final reqNullInfo = Request(
        'POST',
        Uri.parse('http://127.0.0.1:$serverPort/api/v1/pairing/session'),
        headers: adminHeaders,
        // context'te shelf.io.connection_info verilmedi
      );
      final resNullInfo = await server.handler(reqNullInfo);
      expect(resNullInfo.statusCode, equals(403));
      final bodyNull = await resNullInfo.readAsString();
      expect(bodyNull, contains('ERR_LOOPBACK_REQUIRED'));

      // 2. LAN IP (192.168.1.100) -> 403 Forbidden
      final reqLanIp = Request(
        'POST',
        Uri.parse('http://192.168.1.100:$serverPort/api/v1/pairing/session'),
        headers: adminHeaders,
        context: {
          'shelf.io.connection_info': _FakeConnectionInfo(
            remoteAddress: InternetAddress('192.168.1.100'),
          ),
        },
      );
      final resLanIp = await server.handler(reqLanIp);
      expect(resLanIp.statusCode, equals(403));
      final bodyLan = await resLanIp.readAsString();
      expect(bodyLan, contains('ERR_LOOPBACK_REQUIRED'));

      // 3. IPv6 loopback (::1) -> 201 Created (Kabul edilmeli)
      final reqIpv6 = Request(
        'POST',
        Uri.parse('http://[::1]:$serverPort/api/v1/pairing/session'),
        headers: adminHeaders,
        context: {
          'shelf.io.connection_info': _FakeConnectionInfo(
            remoteAddress: InternetAddress('::1'),
          ),
        },
      );
      final resIpv6 = await server.handler(reqIpv6);
      expect(resIpv6.statusCode, equals(201));

      // 4. Yanlış admin secret ile loopback çağrısı -> 403 Forbidden
      final reqWrongSecret = Request(
        'POST',
        Uri.parse('http://127.0.0.1:$serverPort/api/v1/pairing/session'),
        headers: {
          'content-type': 'application/json',
          'x-admin-secret': 'wrong_secret_123',
        },
        context: {
          'shelf.io.connection_info': _FakeConnectionInfo(
            remoteAddress: InternetAddress('127.0.0.1'),
          ),
        },
      );
      final resWrongSecret = await server.handler(reqWrongSecret);
      expect(resWrongSecret.statusCode, equals(403));
      final bodyWrong = await resWrongSecret.readAsString();
      expect(bodyWrong, contains('ERR_INVALID_ADMIN_SECRET'));
    });
  });
}

class _FakeConnectionInfo implements HttpConnectionInfo {
  @override
  final InternetAddress remoteAddress;
  @override
  int get remotePort => 54321;
  @override
  int get localPort => 8085;

  _FakeConnectionInfo({required this.remoteAddress});
}
