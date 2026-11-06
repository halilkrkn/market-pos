import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/certificate_manager.dart';
import '../lib/security/pepper_manager.dart';
import '../lib/security/tls_client_factory.dart';
import '../lib/security/token_manager.dart';

void main() {
  late Directory tempDir;
  late File dbFile;
  late File pepperFile;
  late SpikeDatabase db;
  late WriteQueue writeQueue;
  late PepperManager pepperManager;

  // Sertifika dosya yolları
  late String caKeyPath;
  late String caCertPath;
  late String serverKeyPath;
  late String serverCertPath;

  // Yanlış / Sahte CA
  late String rogueCaKeyPath;
  late String rogueCaCertPath;

  // Süresi dolmuş sunucu sertifikası
  late String expiredServerKeyPath;
  late String expiredServerCertPath;

  late SpikeServer server;
  late String baseHttpsUrl;
  const testPort = 8980;
  const testAdminSecret = 'admin_secret_s3_tls_secure_9988';
  late String validCashierToken;

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    configureSqliteNative();
    tempDir = await Directory.systemTemp.createTemp('mms_s3_tls_');
    dbFile = File(p.join(tempDir.path, 's3_test.db'));
    pepperFile = File(p.join(tempDir.path, 'pepper.dpapi'));

    pepperManager = PepperManager(pepperFile)..initialize();
    db = SpikeDatabase(dbFile);
    writeQueue = WriteQueue();

    // 1. Ürün tohumla
    await db.into(db.products).insert(
          ProductsCompanion(
            id: const Value('prod_cola'),
            barcode: const Value('869000000001'),
            name: const Value('Kutu Kola 330ml'),
            price: const Value(2500),
            stock: const Value(100000),
          ),
        );

    // 2. Cihaz tohumla
    validCashierToken = TokenManager.generateToken();
    final validSalt = TokenManager.generateSalt();
    final validHash = TokenManager.hashToken(
      rawToken: validCashierToken,
      salt: validSalt,
      pepper: pepperManager.pepper,
    );

    await db.into(db.devices).insert(
          DevicesCompanion(
            deviceId: const Value('DEV_TLS_CASHIER_01'),
            name: const Value('TLS Test Kasa'),
            tokenHash: Value(validHash),
            salt: Value(validSalt),
            isActive: const Value(true),
          ),
        );

    // 3. Sertifikaları oluştur
    caKeyPath = p.join(tempDir.path, 'root_ca.key');
    caCertPath = p.join(tempDir.path, 'root_ca.crt');
    serverKeyPath = p.join(tempDir.path, 'server.key');
    serverCertPath = p.join(tempDir.path, 'server.crt');

    CertificateManager.generateRootCa(
      caKeyPath: caKeyPath,
      caCertPath: caCertPath,
      commonName: 'Market MMS Local Root CA S3',
    );

    CertificateManager.generateServerCertificate(
      caKeyPath: caKeyPath,
      caCertPath: caCertPath,
      serverKeyPath: serverKeyPath,
      serverCertPath: serverCertPath,
      commonName: 'localhost',
      sanList: ['localhost', '127.0.0.1'],
    );

    // Sahte CA oluştur
    rogueCaKeyPath = p.join(tempDir.path, 'rogue_ca.key');
    rogueCaCertPath = p.join(tempDir.path, 'rogue_ca.crt');
    CertificateManager.generateRootCa(
      caKeyPath: rogueCaKeyPath,
      caCertPath: rogueCaCertPath,
      commonName: 'Attacker Rogue CA',
    );

    // Süresi dolmuş sunucu sertifikası oluştur
    expiredServerKeyPath = p.join(tempDir.path, 'expired_server.key');
    expiredServerCertPath = p.join(tempDir.path, 'expired_server.crt');
    CertificateManager.generateExpiredServerCertificate(
      caKeyPath: caKeyPath,
      caCertPath: caCertPath,
      serverKeyPath: expiredServerKeyPath,
      serverCertPath: expiredServerCertPath,
      commonName: 'localhost',
    );

    // 4. HTTPS Server başlat
    final serverContext = CertificateManager.createServerSecurityContext(
      certChainPath: serverCertPath,
      privateKeyPath: serverKeyPath,
    );

    server = SpikeServer(
      db: db,
      writeQueue: writeQueue,
      backupDirectory: p.join(tempDir.path, 'backups'),
      adminSecret: testAdminSecret,
      pepperManager: pepperManager,
      securityContext: serverContext,
      requireTls: true,
    );

    await server.start(address: InternetAddress.loopbackIPv4, port: testPort);
    baseHttpsUrl = 'https://127.0.0.1:$testPort';
  });

  tearDownAll(() async {
    try {
      await server.stop();
    } catch (_) {}
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Aşama S-3: LAN TLS Security Doğrulama Senaryoları', () {
    test('1. Geçerli Root CA sabitlenmiş istemci HTTPS üzerinden başarıyla bağlanmalıdır (200 OK)', () async {
      final caBytes = File(caCertPath).readAsBytesSync();
      final client = TlsClientFactory.createPinnedClient(
        trustedRootCaBytes: caBytes,
      );

      try {
        final req = await client.getUrl(Uri.parse('$baseHttpsUrl/health'));
        final res = await req.close();
        expect(res.statusCode, equals(200));

        final body = await utf8.decodeStream(res);
        final data = jsonDecode(body) as Map<String, dynamic>;
        expect(data['status'], equals('UP'));
      } finally {
        client.close(force: true);
      }
    });

    test('2. Yanlış / Yabancı Root CA kullanan istemci bağlantısı derhal reddedilmelidir (HandshakeException)', () async {
      final rogueCaBytes = File(rogueCaCertPath).readAsBytesSync();
      final rogueClient = TlsClientFactory.createPinnedClient(
        trustedRootCaBytes: rogueCaBytes,
      );

      try {
        final req = await rogueClient.getUrl(Uri.parse('$baseHttpsUrl/health'));
        await req.close();
        fail('Bağlantı yabancı CA ile reddedilmeliydi!');
      } on HandshakeException catch (e) {
        expect(e.message, contains('Handshake error'));
      } on SocketException catch (_) {
        // Socket seviyesinde TLS el sıkışma reddi kabul edilebilir
      } finally {
        rogueClient.close(force: true);
      }
    });

    test('3. Root CA SHA-256 parmak izi (fingerprint) uyuşmadığında istemci bağlantıyı kurmamalıdır', () {
      final caBytes = File(caCertPath).readAsBytesSync();
      const fakeFingerprint = 'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99';

      expect(
        () => TlsClientFactory.createPinnedClient(
          trustedRootCaBytes: caBytes,
          expectedFingerprint: fakeFingerprint,
        ),
        throwsA(isA<TlsSecurityException>()),
        reason: 'Parmak izi uyuşmazlığında TlsSecurityException fırlatılmalıdır.',
      );
    });

    test('4. Doğru Root CA parmak izi sağlandığında istemci güvenle başlatılmalıdır', () {
      final caBytes = File(caCertPath).readAsBytesSync();
      final correctFingerprint = CertificateManager.computeSha256Fingerprint(caBytes);

      final client = TlsClientFactory.createPinnedClient(
        trustedRootCaBytes: caBytes,
        expectedFingerprint: correctFingerprint,
      );
      expect(client, isNotNull);
      client.close(force: true);
    });

    test('5. Süresi dolmuş (expired) sunucu sertifikası ile bağlantı reddedilmelidir (HandshakeException)', () async {
      const expiredPort = 8981;
      final expContext = CertificateManager.createServerSecurityContext(
        certChainPath: expiredServerCertPath,
        privateKeyPath: expiredServerKeyPath,
      );
      final expDb = SpikeDatabase(dbFile);
      final expQueue = WriteQueue();
      final expServer = SpikeServer(
        db: expDb,
        writeQueue: expQueue,
        pepperManager: pepperManager,
        securityContext: expContext,
        requireTls: true,
      );
      await expServer.start(address: InternetAddress.loopbackIPv4, port: expiredPort);

      final caBytes = File(caCertPath).readAsBytesSync();
      final client = TlsClientFactory.createPinnedClient(trustedRootCaBytes: caBytes);

      try {
        final req = await client.getUrl(Uri.parse('https://127.0.0.1:$expiredPort/health'));
        await req.close();
        fail('Süresi dolmuş sertifika reddedilmeliydi!');
      } on HandshakeException catch (e) {
        expect(e.message, contains('Handshake error'));
      } on SocketException catch (_) {
      } finally {
        client.close(force: true);
        await expServer.stop();
      }
    });

    test('6. Bozuk sertifika zinciri (CA tarafından imzalanmamış sahte sunucu sertifikası) reddedilmelidir', () async {
      const rogueServerPort = 8982;
      // Rogue CA tarafından imzalanmış sunucu sertifikası üret
      final rogueServerKey = p.join(tempDir.path, 'rogue_srv.key');
      final rogueServerCert = p.join(tempDir.path, 'rogue_srv.crt');
      CertificateManager.generateServerCertificate(
        caKeyPath: rogueCaKeyPath,
        caCertPath: rogueCaCertPath,
        serverKeyPath: rogueServerKey,
        serverCertPath: rogueServerCert,
      );

      final rogueContext = CertificateManager.createServerSecurityContext(
        certChainPath: rogueServerCert,
        privateKeyPath: rogueServerKey,
      );
      final rDb = SpikeDatabase(dbFile);
      final rQueue = WriteQueue();
      final rServer = SpikeServer(
        db: rDb,
        writeQueue: rQueue,
        pepperManager: pepperManager,
        securityContext: rogueContext,
        requireTls: true,
      );
      await rServer.start(address: InternetAddress.loopbackIPv4, port: rogueServerPort);

      // Orijinal Root CA'yı sabitleyen meşru istemci sahte sunucuya bağlanmayı dener
      final caBytes = File(caCertPath).readAsBytesSync();
      final client = TlsClientFactory.createPinnedClient(trustedRootCaBytes: caBytes);

      try {
        final req = await client.getUrl(Uri.parse('https://127.0.0.1:$rogueServerPort/health'));
        await req.close();
        fail('Sahte zincir reddedilmeliydi!');
      } on HandshakeException catch (e) {
        expect(e.message, contains('Handshake error'));
      } on SocketException catch (_) {
      } finally {
        client.close(force: true);
        await rServer.stop();
      }
    });

    test('7. Şifresiz HTTP portuna veya HTTPS portuna düz metin HTTP isteği atıldığında el sıkışma çökmelidir', () async {
      final plainClient = HttpClient();
      try {
        // HTTPS portuna düz HTTP isteği gönder
        final req = await plainClient.getUrl(Uri.parse('http://127.0.0.1:$testPort/health'));
        await req.close();
        fail('Düz metin HTTP isteği HTTPS portunda kabul edilmemelidir!');
      } catch (e) {
        // SocketException, ClientException veya Connection reset beklenir
        expect(e, anyOf(isA<SocketException>(), isA<HttpException>(), isA<HandshakeException>()));
      } finally {
        plainClient.close(force: true);
      }
    });

    test('8. Bearer Device Token HTTPS üzerinden başarıyla çalışmalıdır (POST /api/v1/sales)', () async {
      final caBytes = File(caCertPath).readAsBytesSync();
      final client = TlsClientFactory.createPinnedClient(trustedRootCaBytes: caBytes);

      try {
        final req = await client.postUrl(Uri.parse('$baseHttpsUrl/api/v1/sales'));
        req.headers.contentType = ContentType.json;
        req.headers.set('authorization', 'Bearer $validCashierToken');
        req.write(jsonEncode({
          'operation_id': 'op_tls_sale_01',
          'client_seq': 1,
          'total_amount': 2500,
          'payment_method': 'CASH',
          'items': [
            {'product_id': 'prod_cola', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500}
          ],
        }));

        final res = await req.close();
        expect(res.statusCode, equals(201));

        final body = await utf8.decodeStream(res);
        final data = jsonDecode(body) as Map<String, dynamic>;
        expect(data['status'], equals('COMMITTED'));
      } finally {
        client.close(force: true);
      }
    });

    test('9. Admin Secret HTTPS üzerinden başarıyla doğrulanmalıdır (POST /api/v1/devices/revoke)', () async {
      final caBytes = File(caCertPath).readAsBytesSync();
      final client = TlsClientFactory.createPinnedClient(trustedRootCaBytes: caBytes);

      try {
        final req = await client.postUrl(Uri.parse('$baseHttpsUrl/api/v1/devices/revoke'));
        req.headers.contentType = ContentType.json;
        req.headers.set('x-admin-secret', testAdminSecret);
        req.write(jsonEncode({
          'device_id': 'DEV_TLS_CASHIER_01',
          'reason': 'TLS testi kapsamında iptal',
        }));

        final res = await req.close();
        expect(res.statusCode, equals(200));

        final body = await utf8.decodeStream(res);
        final data = jsonDecode(body) as Map<String, dynamic>;
        expect(data['status'], equals('REVOKED'));
      } finally {
        client.close(force: true);
      }
    });

    test('10. Kesintisiz Yaprak Sertifika Yenileme (Leaf Renewal): İstemci sertifikayı güncellemeden çalışmaya devam etmelidir', () async {
      // 1. Mevcut Root CA altında yeni bir yaprak sertifika (Server Cert v2) üret
      final serverKeyV2 = p.join(tempDir.path, 'server_v2.key');
      final serverCertV2 = p.join(tempDir.path, 'server_v2.crt');
      CertificateManager.generateServerCertificate(
        caKeyPath: caKeyPath,
        caCertPath: caCertPath,
        serverKeyPath: serverKeyV2,
        serverCertPath: serverCertV2,
        commonName: 'localhost',
        sanList: ['localhost', '127.0.0.1'],
      );

      // 2. Sunucuyu yeni sertifikayla başlat
      const rotPort = 8983;
      final rotContext = CertificateManager.createServerSecurityContext(
        certChainPath: serverCertV2,
        privateKeyPath: serverKeyV2,
      );
      final rotDb = SpikeDatabase(dbFile);
      final rotQueue = WriteQueue();
      final rotServer = SpikeServer(
        db: rotDb,
        writeQueue: rotQueue,
        pepperManager: pepperManager,
        securityContext: rotContext,
        requireTls: true,
      );
      await rotServer.start(address: InternetAddress.loopbackIPv4, port: rotPort);

      // 3. İstemci SADECE orijinal Root CA'yı sabitlemiştir; yeni yaprak sertifikadan haberdar değildir
      final caBytes = File(caCertPath).readAsBytesSync();
      final client = TlsClientFactory.createPinnedClient(trustedRootCaBytes: caBytes);

      try {
        final req = await client.getUrl(Uri.parse('https://127.0.0.1:$rotPort/health'));
        final res = await req.close();
        expect(res.statusCode, equals(200),
            reason: 'Kök CA sabitlendiği için yaprak sertifika yenilemelerinde istemci kesintiye uğramamalıdır!');
      } finally {
        client.close(force: true);
        await rotServer.stop();
      }
    });

    test('11. Bozuk sertifika dosyalarında sunucu güvenli olmayan HTTP fallback yapmadan çökmelidir (Fail-Safe)', () {
      final corruptCertPath = p.join(tempDir.path, 'corrupt.crt');
      File(corruptCertPath).writeAsStringSync('TAMAMEN_BOZUK_SERTIFIKA');

      expect(
        () => CertificateManager.createServerSecurityContext(
          certChainPath: corruptCertPath,
          privateKeyPath: serverKeyPath,
        ),
        throwsA(isA<TlsConfigurationException>()),
        reason: 'Bozuk sertifika durumunda sessizce güvensiz HTTP fallback yapılmamalıdır.',
      );
    });

    test('12. Sunucu yeniden başlatıldığında mevcut TLS sertifikalarını kesintisiz yüklemelidir', () async {
      await server.stop();

      final restartedDb = SpikeDatabase(dbFile);
      final restartedQueue = WriteQueue();
      final serverContext = CertificateManager.createServerSecurityContext(
        certChainPath: serverCertPath,
        privateKeyPath: serverKeyPath,
      );

      final restartedServer = SpikeServer(
        db: restartedDb,
        writeQueue: restartedQueue,
        backupDirectory: p.join(tempDir.path, 'backups'),
        adminSecret: testAdminSecret,
        pepperManager: pepperManager,
        securityContext: serverContext,
        requireTls: true,
      );

      await restartedServer.start(address: InternetAddress.loopbackIPv4, port: testPort);

      final caBytes = File(caCertPath).readAsBytesSync();
      final client = TlsClientFactory.createPinnedClient(trustedRootCaBytes: caBytes);

      try {
        final req = await client.getUrl(Uri.parse('$baseHttpsUrl/health'));
        final res = await req.close();
        expect(res.statusCode, equals(200));
      } finally {
        client.close(force: true);
        await restartedServer.stop();
      }
    });
  });
}

