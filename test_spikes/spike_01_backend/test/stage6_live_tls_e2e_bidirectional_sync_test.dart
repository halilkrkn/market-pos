import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/discovery/discovery_responder.dart';
import '../lib/security/certificate_manager.dart';
import '../lib/security/ecdsa_signature_validator.dart';
import '../lib/security/pepper_manager.dart';

http.Client _createStrictPinnedClient(Uint8List caPemBytes) {
  final ctx = SecurityContext(withTrustedRoots: false);
  ctx.setTrustedCertificatesBytes(caPemBytes);
  final io = HttpClient(context: ctx);
  io.badCertificateCallback = (cert, host, port) => false;
  return IOClient(io);
}

Future<String?> _detectActiveWifiIpv4() async {
  final ifaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLinkLocal: false,
    includeLoopback: false,
  );
  for (final i in ifaces) {
    if (i.name.toLowerCase() == 'wi-fi' && i.addresses.isNotEmpty) {
      return i.addresses.first.address;
    }
  }
  return null;
}

void main() {
  group('AŞAMA 6 — Canlı TLS HTTPS Hub, UDP Discovery, Eşleştirme ve Çift Yönlü E2E Testi', () {
    test('Üretilen izole TEST_ONLY TLS sertifikaları OpenSSL 3.5.9 ve MmsX509PreValidator ile uyumludur', () async {
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
      final deployDir = Directory(
        p.join(localAppData, 'MarketMMS_Isolated_Test', 'test_only_tls', 'hub_deploy'),
      );
      if (!deployDir.existsSync()) {
        markTestSkipped('İzole test_only_tls/hub_deploy dizini bu ortamda henüz oluşturulmadı.');
        return;
      }

      final caFile = File(p.join(deployDir.path, 'ca.crt'));
      final srvFile = File(p.join(deployDir.path, 'server.crt'));
      final keyFile = File(p.join(deployDir.path, 'server.key'));
      final forbiddenCaKey = File(p.join(deployDir.path, 'ca.key'));

      expect(caFile.existsSync(), isTrue);
      expect(srvFile.existsSync(), isTrue);
      expect(keyFile.existsSync(), isTrue);
      expect(forbiddenCaKey.existsSync(), isFalse, reason: 'ca.key asla deploy dizininde olmamalı');

      final validatedCa = CertificateManager.validateRootCaBytes(caFile.readAsBytesSync());
      expect(validatedCa.canonical.sha256Hex, hasLength(64));

      final sanIps = CertificateManager.extractServerCertSanIpv4s(srvFile.readAsBytesSync());
      expect(sanIps, contains('127.0.0.1'));
      final wifiIp = await _detectActiveWifiIpv4();
      if (wifiIp != null) {
        expect(sanIps, contains(wifiIp));
      }
    });

    test('Uçtan uca TLS Hub + Discovery + Owner Bootstrap + Android QR Pairing + Çift Yönlü & Offline-Reconnect Sync', () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      configureSqliteNative();

      final wifiIp = await _detectActiveWifiIpv4();
      final sanHosts = <String>['localhost', '127.0.0.1', if (wifiIp != null) wifiIp];

      final tempDir = Directory.systemTemp.createTempSync('mms_stage6_live_tls_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final certsDir = Directory(p.join(tempDir.path, 'certs'))..createSync();
      final caKeyPath = p.join(tempDir.path, 'ca_private.key'); // Hub dizininden ayrı
      final caCertPath = p.join(certsDir.path, 'ca.crt');
      final srvKeyPath = p.join(certsDir.path, 'server.key');
      final srvCertPath = p.join(certsDir.path, 'server.crt');

      CertificateManager.generateRootCa(
        caKeyPath: caKeyPath,
        caCertPath: caCertPath,
        commonName: 'Market MMS TEST_ONLY E2E Root CA',
      );
      CertificateManager.generateServerCertificate(
        caKeyPath: caKeyPath,
        caCertPath: caCertPath,
        serverKeyPath: srvKeyPath,
        serverCertPath: srvCertPath,
        commonName: 'Market MMS TEST_ONLY E2E Hub',
        sanList: sanHosts,
      );

      // Negatif doğrulama için sahte ikinci CA
      final rogueCaKey = p.join(tempDir.path, 'rogue_ca.key');
      final rogueCaCert = p.join(tempDir.path, 'rogue_ca.crt');
      CertificateManager.generateRootCa(
        caKeyPath: rogueCaKey,
        caCertPath: rogueCaCert,
        commonName: 'Rogue Untrusted CA',
      );

      final caPemBytes = Uint8List.fromList(File(caCertPath).readAsBytesSync());
      final validatedCa = CertificateManager.validateRootCaBytes(caPemBytes);
      final caFingerprintColon = validatedCa.colonFingerprint;
      final rogueCaBytes = Uint8List.fromList(File(rogueCaCert).readAsBytesSync());

      const adminSecret = 'Stage6_E2E_Admin_Secret_2026!';
      final hubDbFile = File(p.join(tempDir.path, 'hub_master.db'));
      final pepperFile = File(p.join(tempDir.path, 'pepper.dpapi'));
      final backupsDir = p.join(tempDir.path, 'backups');

      Future<({SpikeServer server, SpikeDatabase db, WriteQueue queue, int httpPort, int udpPort})> startTlsHub() async {
        final s1 = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
        final hPort = s1.port;
        await s1.close();

        final u1 = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        final uPort = u1.port;
        u1.close();

        final db = SpikeDatabase(hubDbFile);
        final queue = WriteQueue();
        final pepper = PepperManager(pepperFile)..initialize();
        final secCtx = CertificateManager.createServerSecurityContext(
          certChainPath: srvCertPath,
          privateKeyPath: srvKeyPath,
        );
        final server = SpikeServer(
          db: db,
          dbFile: hubDbFile,
          writeQueue: queue,
          backupDirectory: backupsDir,
          adminSecret: adminSecret,
          pepperManager: pepper,
          securityContext: secCtx,
          requireTls: true,
          caCertPath: caCertPath,
          serverCertPath: srvCertPath,
          advertiseHost: wifiIp,
          tenantId: 'default-tenant',
          storeId: 'default-store',
          hubId: 'MMS-HUB-E2E-TLS',
          requireTenantStoreHeaders: true,
        );
        await server.start(
          port: hPort,
          discoveryPort: uPort,
          enableDiscovery: true,
        );
        return (server: server, db: db, queue: queue, httpPort: hPort, udpPort: uPort);
      }

      var hub = await startTlsHub();
      var hubStopped = false;
      addTearDown(() async {
        if (!hubStopped) {
          await hub.server.stop();
          await hub.queue.drain();
          await hub.db.close();
        }
      });

      final loopbackHttpsUrl = 'https://127.0.0.1:${hub.httpPort}';
      final lanHost = wifiIp ?? '127.0.0.1';
      final lanHttpsUrl = 'https://$lanHost:${hub.httpPort}';

      final pinnedClient = _createStrictPinnedClient(caPemBytes);
      addTearDown(pinnedClient.close);

      // 1 & 2. Localhost HTTPS /health (strict CA pin) + yanlış CA reddi (fail-closed)
      final hLocal = await pinnedClient.get(Uri.parse('$loopbackHttpsUrl/health'));
      expect(hLocal.statusCode, equals(200));
      expect((jsonDecode(hLocal.body) as Map)['status'], equals('UP'));

      final rogueClient = _createStrictPinnedClient(rogueCaBytes);
      addTearDown(rogueClient.close);
      await expectLater(
        () => rogueClient.get(Uri.parse('$loopbackHttpsUrl/health')),
        throwsA(isA<HandshakeException>()),
      );

      // 3. Wi-Fi LAN IP üzerinden HTTPS /health
      final hLan = await pinnedClient.get(Uri.parse('$lanHttpsUrl/health'));
      expect(hLan.statusCode, equals(200));

      // 4. UDP Discovery yanıtı HTTPS + sanal IP (192.168.84.2) dışlama
      final udpSock = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final discCompleter = Completer<Map<String, dynamic>>();
      udpSock.listen((ev) {
        if (ev == RawSocketEvent.read) {
          final dg = udpSock.receive();
          if (dg != null && !discCompleter.isCompleted) {
            discCompleter.complete(jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>);
          }
        }
      });
      udpSock.send(
        utf8.encode(jsonEncode(<String, dynamic>{
          'cmd': HubDiscoveryResponder.discoveryCommand,
          'version': '1.0',
          'client_device_id': 'POS-AND-E2E',
        })),
        InternetAddress.loopbackIPv4,
        hub.udpPort,
      );
      final discJson = await discCompleter.future.timeout(const Duration(seconds: 3));
      udpSock.close();

      expect(discJson['scheme'], equals('https'));
      expect(discJson['http_port'], equals(hub.httpPort));
      final discoveredIps = List<String>.from(discJson['server_ips'] as List);
      expect(discoveredIps, isNot(contains('192.168.84.2')));
      expect(discoveredIps, isNot(contains('192.168.56.1')));
      if (wifiIp != null) {
        expect(discoveredIps, contains(wifiIp));
      }

      // Eski endpoint kimliksiz istekte 401, yetkili istekte ise 404 ERR_ENDPOINT_RETIRED dönmeli
      final unauthRetiredRes = await pinnedClient.post(
        Uri.parse('$loopbackHttpsUrl/api/v1/devices/register'),
        headers: {'content-type': 'application/json'},
        body: '{}',
      );
      expect(unauthRetiredRes.statusCode, equals(401));

      // 5. Windows Owner Bootstrap (loopback HTTPS + admin secret)
      const winDeviceId = 'POS-WIN-E2E';
      final winBootRes = await pinnedClient.post(
        Uri.parse('$loopbackHttpsUrl/api/v1/admin/owner/bootstrap'),
        headers: {
          'content-type': 'application/json',
          'x-mms-admin-secret': adminSecret,
        },
        body: jsonEncode({
          'device_id': winDeviceId,
          'name': 'Windows E2E Owner',
          'register_if_missing': true,
        }),
      );
      expect(winBootRes.statusCode, equals(200));
      final winToken = (jsonDecode(winBootRes.body) as Map)['token'] as String;
      expect(winToken, startsWith('mms_dt_'));

      // Yetkili istekte bile eski register endpointi kapalı kalmalı
      final retiredRes = await pinnedClient.post(
        Uri.parse('$loopbackHttpsUrl/api/v1/devices/register'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $winToken',
        },
        body: '{}',
      );
      expect(retiredRes.statusCode, equals(404));
      expect(retiredRes.body, contains('ERR_ENDPOINT_RETIRED'));

      // 6. Android S-4 ECDSA P-256 QR Pairing (LAN HTTPS üzerinden)
      const andDeviceId = 'POS-AND-E2E';
      final sessRes = await pinnedClient.post(
        Uri.parse('$loopbackHttpsUrl/api/v1/pairing/session'),
        headers: {
          'content-type': 'application/json',
          'x-mms-admin-secret': adminSecret,
        },
        body: '{}',
      );
      expect(sessRes.statusCode, equals(201));
      final sessJson = jsonDecode(sessRes.body) as Map<String, dynamic>;
      final sessionId = sessJson['session_id'] as String;
      final pairingSecret = sessJson['pairing_secret'] as String;
      expect(sessJson['ca_fingerprint'], equals(caFingerprintColon));
      if (wifiIp != null) {
        expect(sessJson['hub_url'], equals('https://$wifiIp:${hub.httpPort}'));
      }

      final caEndpointRes = await pinnedClient.get(
        Uri.parse('$lanHttpsUrl/api/v1/pairing/ca-cert'),
      );
      expect(caEndpointRes.statusCode, equals(200));
      expect(
        CertificateManager.validateRootCaBytes(caEndpointRes.bodyBytes).colonFingerprint,
        equals(caFingerprintColon),
      );

      final andPrivKey = BigInt.parse(
        'A1B2C3D4E5F60102030405060708090A1B2C3D4E5F60102030405060708090A1',
        radix: 16,
      );
      final andPubKey = EcdsaSignatureValidator.getPublicKeyBytes(andPrivKey);
      final andFp = sha256.convert(andPubKey).bytes;

      final reqRes = await pinnedClient.post(
        Uri.parse('$lanHttpsUrl/api/v1/pairing/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'device_id': andDeviceId,
          'name': 'Android E2E',
          'platform': 'android',
          'client_public_key': base64Encode(andPubKey),
        }),
      );
      expect(reqRes.statusCode, equals(202));

      final appRes = await pinnedClient.post(
        Uri.parse('$loopbackHttpsUrl/api/v1/pairing/approve'),
        headers: {
          'content-type': 'application/json',
          'x-mms-admin-secret': adminSecret,
        },
        body: jsonEncode({'session_id': sessionId}),
      );
      expect(appRes.statusCode, equals(200));

      final pollChRes = await pinnedClient.post(
        Uri.parse('$lanHttpsUrl/api/v1/pairing/poll-challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'session_id': sessionId, 'pairing_secret': pairingSecret}),
      );
      expect(pollChRes.statusCode, equals(200));
      final pollCh = jsonDecode(pollChRes.body) as Map<String, dynamic>;
      final pollPayload = EcdsaSignatureValidator.buildCanonicalPollPayload(
        protocolVersion: '1',
        pairingSessionId: sessionId,
        publicKeyFingerprintBytes: andFp,
        challengeId: pollCh['poll_challenge_id'] as String,
        challengeNonce: base64Decode(pollCh['poll_challenge_nonce'] as String),
      );
      final pollSig = EcdsaSignatureValidator.signPayload(
        privateKey: andPrivKey,
        canonicalPayload: pollPayload,
      );

      final pollRes = await pinnedClient.post(
        Uri.parse('$lanHttpsUrl/api/v1/pairing/poll'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'poll_challenge_id': pollCh['poll_challenge_id'],
          'signature': base64Encode(pollSig),
        }),
      );
      expect(pollRes.statusCode, equals(200));
      final andToken = (jsonDecode(pollRes.body) as Map)['token'] as String;
      expect(andToken, startsWith('mms_dt_'));

      // Challenge cooldown (5 sn) sonrasında ACK challenge al
      await Future.delayed(const Duration(seconds: 5, milliseconds: 150));
      final ackChRes = await pinnedClient.post(
        Uri.parse('$lanHttpsUrl/api/v1/pairing/ack-challenge'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'session_id': sessionId, 'pairing_secret': pairingSecret}),
      );
      expect(ackChRes.statusCode, equals(200));
      final ackCh = jsonDecode(ackChRes.body) as Map<String, dynamic>;
      final ackPayload = EcdsaSignatureValidator.buildCanonicalAckPayload(
        protocolVersion: '1',
        pairingSessionId: sessionId,
        publicKeyFingerprintBytes: andFp,
        challengeId: ackCh['ack_challenge_id'] as String,
        challengeNonce: base64Decode(ackCh['ack_challenge_nonce'] as String),
        tokenHashBytes: Uint8List.fromList(sha256.convert(utf8.encode(andToken)).bytes),
      );
      final ackSig = EcdsaSignatureValidator.signPayload(
        privateKey: andPrivKey,
        canonicalPayload: ackPayload,
      );
      final ackRes = await pinnedClient.post(
        Uri.parse('$lanHttpsUrl/api/v1/pairing/ack'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'ack_challenge_id': ackCh['ack_challenge_id'],
          'signature': base64Encode(ackSig),
        }),
      );
      expect(ackRes.statusCode, equals(200));

      // İki ayrı yerel ClientDatabase (Windows ve Android)
      final winDb = ClientDatabase(File(p.join(tempDir.path, 'win_client.db')));
      final andDb = ClientDatabase(File(p.join(tempDir.path, 'and_client.db')));
      addTearDown(() async {
        await winDb.close();
        await andDb.close();
      });
      final winRepo = ClientStorageRepository(winDb);
      final andRepo = ClientStorageRepository(andDb);
      await winRepo.initializeDevice(winDeviceId);
      await andRepo.initializeDevice(andDeviceId);

      final winTransport = HttpSyncTransport.forStore(
        client: _createStrictPinnedClient(caPemBytes),
        tenantId: 'default-tenant',
        storeId: 'default-store',
      );
      final andTransport = HttpSyncTransport.forStore(
        client: _createStrictPinnedClient(caPemBytes),
        tenantId: 'default-tenant',
        storeId: 'default-store',
      );
      addTearDown(() {
        winTransport.close();
        andTransport.close();
      });

      final winSync = ClientSyncService(
        repository: winRepo,
        transport: winTransport,
        deviceId: winDeviceId,
        deviceToken: winToken,
        hubUrl: loopbackHttpsUrl,
      );
      final andSync = ClientSyncService(
        repository: andRepo,
        transport: andTransport,
        deviceId: andDeviceId,
        deviceToken: andToken,
        hubUrl: lanHttpsUrl,
      );

      // 7 & 8. Android ürün oluştur -> Hub -> Windows çeker
      final andProd = await andRepo.createProduct(
        name: 'Android Canlı E2E Süt 1L',
        price: 3450,
        barcode: '8691112223334',
        initialStock: 25000,
        deviceId: andDeviceId,
      );
      final andPush = await andSync.syncPendingOutbox();
      expect(andPush.isCleanSuccess, isTrue);
      expect(andPush.syncedCount, equals(1));

      await winSync.syncProducts();
      final winGotAndProd = await winRepo.getProductByBarcode('8691112223334');
      expect(winGotAndProd, isNotNull);
      expect(winGotAndProd!.id, equals(andProd.id));
      expect(winGotAndProd.price, equals(3450));

      // 9. Windows ürün oluştur -> Hub -> Android çeker
      final winProd = await winRepo.createProduct(
        name: 'Windows Canlı E2E Çikolata',
        price: 1990,
        barcode: '8695556667778',
        initialStock: 40000,
        deviceId: winDeviceId,
      );
      final winPush = await winSync.syncPendingOutbox();
      expect(winPush.isCleanSuccess, isTrue);
      expect(winPush.syncedCount, equals(1));
      await winSync.syncProducts();

      await andSync.syncProducts();
      final andGotWinProd = await andRepo.getProductByBarcode('8695556667778');
      expect(andGotWinProd, isNotNull);
      expect(andGotWinProd!.id, equals(winProd.id));
      expect(andGotWinProd.price, equals(1990));

      // 10. Hub kesintisi -> Android offline satış & outbox korunumu -> Hub yeniden başlatma -> FIFO sync
      await hub.server.stop();
      await hub.queue.drain();
      await hub.db.close();
      hubStopped = true;

      final offlineSale = await andRepo.createOfflineSale(
        deviceId: andDeviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units(winProd.id, 2)],
      );
      expect(offlineSale.totalAmount, equals(3980));
      expect((await andRepo.getOutboxSummary(deviceId: andDeviceId)).pending, equals(1));

      // Bağlantı yokken sync denemesi outbox'ı silmez (RETRY durumuna alır)
      final failedPush = await andSync.syncPendingOutbox();
      expect(failedPush.isCleanSuccess, isFalse);
      final afterFailSummary = await andRepo.getOutboxSummary(deviceId: andDeviceId);
      expect(afterFailSummary.retry, equals(1));
      expect(afterFailSummary.failedPermanent, equals(0));

      // Hub tekrar açılır
      hub = await startTlsHub();
      hubStopped = false;
      final reconnectedLanUrl = 'https://$lanHost:${hub.httpPort}';
      final reconnectedLoopUrl = 'https://127.0.0.1:${hub.httpPort}';

      final andSyncReconnected = ClientSyncService(
        repository: andRepo,
        transport: andTransport,
        deviceId: andDeviceId,
        deviceToken: andToken,
        hubUrl: reconnectedLanUrl,
      );
      final winSyncReconnected = ClientSyncService(
        repository: winRepo,
        transport: winTransport,
        deviceId: winDeviceId,
        deviceToken: winToken,
        hubUrl: reconnectedLoopUrl,
      );

      final drainAfterReconnect = await andSyncReconnected.syncPendingOutbox(
        now: DateTime.now().add(const Duration(minutes: 2)),
      );
      expect(drainAfterReconnect.isCleanSuccess, isTrue);
      expect(drainAfterReconnect.syncedCount, equals(1));
      final afterReconnectSummary = await andRepo.getOutboxSummary(deviceId: andDeviceId);
      expect(afterReconnectSummary.pending, equals(0));
      expect(afterReconnectSummary.retry, equals(0));

      await winSyncReconnected.syncSales();
      await winSyncReconnected.syncProducts();
      final winSales = await winRepo.getSalesHistory(limit: 20);
      expect(
        winSales.any((s) => s.clientSeq == offlineSale.clientSeq && s.totalAmount == 3980),
        isTrue,
      );
      final winStockAfterAndSale = await winRepo.getProductByBarcode('8695556667778');
      expect(winStockAfterAndSale!.stock, equals(38000));
    });
  });
}
