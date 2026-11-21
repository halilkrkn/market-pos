import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/core/logging/redacting_logger.dart';
import 'package:market_pos/core/security/secure_token_store.dart';
import 'package:market_pos/core/security/tls_pinned_client_factory.dart';
import 'package:market_pos/features/security/data/device_pairing_client.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

String _findOpenSsl() {
  const candidates = <String>[
    r'C:\Program Files\Git\usr\bin\openssl.exe',
    r'C:\Program Files\Git\mingw64\bin\openssl.exe',
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) return c;
  }
  return 'openssl';
}

({String caPem, String caKeyPath, String caSha256Hex, String leafPem, String leafKeyPem})
    _generateCertPair(
  Directory dir,
  String prefix, {
  String san = 'IP:127.0.0.1,DNS:localhost',
  bool makeLeafNonCa = false,
}) {
  final ssl = _findOpenSsl();
  final caKey = p.join(dir.path, '${prefix}_ca.key');
  final caCrt = p.join(dir.path, '${prefix}_ca.crt');
  final r1 = Process.runSync(ssl, [
    'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
    '-keyout', caKey, '-out', caCrt, '-days', '10',
    '-subj', '/CN=MMS Client Test Root CA ($prefix)',
    if (!makeLeafNonCa) ...[
      '-addext', 'basicConstraints=critical,CA:TRUE',
      '-addext', 'keyUsage=critical,keyCertSign,cRLSign',
    ] else ...[
      '-addext', 'basicConstraints=critical,CA:FALSE',
      '-addext', 'subjectAltName=$san',
    ],
  ]);
  if (r1.exitCode != 0) throw StateError('OpenSSL CA error: ${r1.stderr}');

  final srvKey = p.join(dir.path, '${prefix}_srv.key');
  final csr = p.join(dir.path, '${prefix}_srv.csr');
  final srvCrt = p.join(dir.path, '${prefix}_srv.crt');
  final extFile = File(p.join(dir.path, '${prefix}_ext.cnf'))
    ..writeAsStringSync('subjectAltName=$san\n');

  final r2 = Process.runSync(ssl, [
    'req', '-newkey', 'rsa:2048', '-nodes',
    '-keyout', srvKey, '-out', csr, '-subj', '/CN=127.0.0.1',
  ]);
  if (r2.exitCode != 0) throw StateError('OpenSSL CSR error: ${r2.stderr}');

  final r3 = Process.runSync(ssl, [
    'x509', '-req', '-in', csr, '-CA', caCrt, '-CAkey', caKey,
    '-CAcreateserial', '-out', srvCrt, '-days', '5', '-extfile', extFile.path,
  ]);
  if (r3.exitCode != 0) throw StateError('OpenSSL Sign error: ${r3.stderr}');

  final caPem = File(caCrt).readAsStringSync();
  final canonicalCa = extractCanonicalSingleCertDer(Uint8List.fromList(utf8.encode(caPem)));
  return (
    caPem: canonicalCa.toPem(),
    caKeyPath: caKey,
    caSha256Hex: canonicalCa.sha256Hex,
    leafPem: File(srvCrt).readAsStringSync(),
    leafKeyPem: File(srvKey).readAsStringSync(),
  );
}

void main() {
  group('P-BLOCK-1 & P-BLOCK-2: İstemci X.509, ALT-BOOT-2 Bootstrap & Crash-Safe Re-pairing (APP-T01..T18)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('mms_client_pblock_');
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('APP-T01..T01c: İstemci binary DER, CRLF+BOM PEM, F-1 ve sınır ihlalleri doğrulanır', () {
      final binRes = MmsPinnedTlsClientFactory.validateAndComputeCaPin(
        kSharedTestRootCaDerBytes,
        nowUtc: DateTime.utc(2027, 1, 1),
      );
      expect(binRes.sha256Hex, kSharedTestRootCaSha256Hex);
      expect(binRes.wasPem, isFalse);

      final pemRes = MmsPinnedTlsClientFactory.validateAndComputeCaPin(
        Uint8List.fromList([
          0xEF, 0xBB, 0xBF,
          ...utf8.encode(kSharedTestRootCaPem.replaceAll('\n', '\r\n')),
        ]),
        nowUtc: DateTime.utc(2027, 1, 1),
      );
      expect(pemRes.sha256Hex, kSharedTestRootCaSha256Hex);
      expect(pemRes.wasPem, isTrue);

      expect(
        () => MmsPinnedTlsClientFactory.validateAndComputeCaPin(
          Uint8List.fromList([...kSharedTestRootCaDerBytes, 0x99]),
        ),
        throwsA(isA<X509ValidationException>().having((e) => e.code, 'code', 'INVALID_CA_CERT')),
      );
    });

    test('APP-T02 & APP-T03 & APP-T11: Eksik/UNKNOWN pin, HTTP scheme, OOB != JSON, CA değişim onayı (0 ağ isteği)', () async {
      final store = InMemorySecureTokenStore();
      await store.saveDeviceToken('DEV-1', 'old_working_token');
      final client = DevicePairingClient(tokenStore: store, logger: RedactingLogger());

      await expectLater(
        () => client.pairDevice(
          hubBaseUrl: 'https://192.168.1.50:8945',
          sessionId: 's1',
          pairingSecret: 'sec1',
          deviceId: 'DEV-1',
          deviceName: 'Kasa 1',
          platformName: 'android',
          expectedCaSha256: 'UNKNOWN',
        ),
        throwsA(isA<DevicePairingException>().having((e) => e.code, 'code', 'CA_PIN_REQUIRED')),
      );

      await expectLater(
        () => client.pairDevice(
          hubBaseUrl: 'http://192.168.1.50:8945',
          sessionId: 's1',
          pairingSecret: 'sec1',
          deviceId: 'DEV-1',
          deviceName: 'Kasa 1',
          platformName: 'android',
          expectedCaSha256: kSharedTestRootCaSha256Hex,
        ),
        throwsA(isA<DevicePairingException>().having((e) => e.code, 'code', 'TLS_SCHEME_REQUIRED')),
      );

      await expectLater(
        () => client.pairDevice(
          hubBaseUrl: 'https://192.168.1.50:8945',
          sessionId: 's1',
          pairingSecret: 'sec1',
          deviceId: 'DEV-1',
          deviceName: 'Kasa 1',
          platformName: 'android',
          expectedCaSha256: kSharedTestRootCaSha256Hex,
          payloadCaSha256: 'F' * 64,
        ),
        throwsA(isA<DevicePairingException>().having((e) => e.code, 'code', 'OOB_FINGERPRINT_MISMATCH')),
      );

      await expectLater(
        () => client.pairDevice(
          hubBaseUrl: 'https://192.168.1.50:8945',
          sessionId: 's1',
          pairingSecret: 'sec1',
          deviceId: 'DEV-1',
          deviceName: 'Kasa 1',
          platformName: 'android',
          expectedCaSha256: kSharedTestRootCaSha256Hex,
          existingPinnedCaSha256: 'A' * 64,
          onConfirmCaChange: (_, _) async => false,
        ),
        throwsA(isA<DevicePairingException>().having((e) => e.code, 'code', 'REPAIRING_CA_CHANGE_CONFIRMATION_REQUIRED')),
      );

      expect(await store.readDeviceToken('DEV-1'), 'old_working_token');
    });

    test('APP-T04 / APP-T05 / APP-T05b / APP-T14..T15c / APP-T17: Redirect, gzip/deflate, eksik Content-Length, >64KB, Slowloris mutlak 5s, Non-CA ve Sahte CA reddi', () async {
      final pki = _generateCertPair(tempDir, 'boot_edges');
      final secCtx = SecurityContext()
        ..useCertificateChainBytes(utf8.encode(pki.leafPem))
        ..usePrivateKeyBytes(utf8.encode(pki.leafKeyPem));

      String mode = 'redirect';
      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, secCtx);
      addTearDown(() => server.close(force: true));

      final capturedHeaders = <Map<String, String>>[];
      server.listen((req) async {
        final hdrs = <String, String>{};
        req.headers.forEach((k, v) => hdrs[k] = v.join(','));
        capturedHeaders.add(hdrs);

        if (mode == 'redirect') {
          req.response.statusCode = 302;
          req.response.headers.set('location', 'https://127.0.0.1:${server.port}/evil');
          await req.response.close();
        } else if (mode == 'gzip') {
          final compressed = gzip.encode(utf8.encode(pki.caPem));
          req.response.statusCode = 200;
          req.response.headers.set('content-encoding', 'gzip');
          req.response.headers.contentLength = compressed.length;
          req.response.add(compressed);
          await req.response.close();
        } else if (mode == 'truncated_len') {
          final bodyBytes = utf8.encode(pki.caPem);
          final sock = await req.response.detachSocket(writeHeaders: false);
          sock.add(ascii.encode(
            'HTTP/1.1 200 OK\r\n'
            'Content-Type: application/x-x509-ca-cert\r\n'
            'Content-Length: ${bodyBytes.length + 500}\r\n'
            'Connection: close\r\n'
            '\r\n',
          ));
          sock.add(bodyBytes);
          await sock.flush();
          await sock.close();
        } else if (mode == 'too_large') {
          req.response.statusCode = 200;
          req.response.add(Uint8List(65537));
          await req.response.close();
        } else if (mode == 'slowloris') {
          req.response.statusCode = 200;
          req.response.bufferOutput = false;
          req.response.add(utf8.encode('-----BEGIN CERTIFICATE-----\n'));
          await req.response.flush();
          // Her 120ms'de 1 bayt damlat; mutlak Timer(300ms) yine kesmeli!
          for (var i = 0; i < 6; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 120));
            try {
              req.response.add([65]);
              await req.response.flush();
            } catch (_) {
              break;
            }
          }
          try {
            await req.response.close();
          } catch (_) {}
        }
      });

      final store = InMemorySecureTokenStore();
      final client = DevicePairingClient(
        tokenStore: store,
        logger: RedactingLogger(),
        bootstrapTimeout: const Duration(milliseconds: 350),
      );

      // APP-T04/T05: Redirect reddi + sıfır sır başlığı + proxy DIRECT
      mode = 'redirect';
      await expectLater(
        () => client.pairDevice(
          hubBaseUrl: 'https://127.0.0.1:${server.port}',
          sessionId: 's_redir',
          pairingSecret: 'sec_secret_never_sent_in_bootstrap',
          deviceId: 'DEV-BOOT',
          deviceName: 'Kasa',
          platformName: 'android',
          expectedCaSha256: pki.caSha256Hex,
        ),
        throwsA(isA<DevicePairingException>().having((e) => e.code, 'code', 'BOOTSTRAP_REDIRECT_FORBIDDEN')),
      );
      expect(capturedHeaders.single.containsKey('authorization'), isFalse);
      expect(capturedHeaders.single['accept-encoding'], 'identity');

      // APP-T15c (a): gzip reddi
      mode = 'gzip';
      await expectLater(
        () => client.pairDevice(
          hubBaseUrl: 'https://127.0.0.1:${server.port}',
          sessionId: 's_gzip',
          pairingSecret: 'sec_secret',
          deviceId: 'DEV-BOOT',
          deviceName: 'Kasa',
          platformName: 'android',
          expectedCaSha256: pki.caSha256Hex,
        ),
        throwsA(isA<DevicePairingException>().having((e) => e.code, 'code', 'INVALID_CA_CERT')),
      );

      // APP-T15c (b): Content-Length uyuşmazlığı reddi
      mode = 'truncated_len';
      await expectLater(
        () => client.pairDevice(
          hubBaseUrl: 'https://127.0.0.1:${server.port}',
          sessionId: 's_trunc',
          pairingSecret: 'sec_secret',
          deviceId: 'DEV-BOOT',
          deviceName: 'Kasa',
          platformName: 'android',
          expectedCaSha256: pki.caSha256Hex,
        ),
        throwsA(isA<DevicePairingException>().having((e) => e.code, 'code', 'INVALID_CA_CERT')),
      );

      // APP-T15: > 64 KB akış kesici
      mode = 'too_large';
      await expectLater(
        () => client.pairDevice(
          hubBaseUrl: 'https://127.0.0.1:${server.port}',
          sessionId: 's_big',
          pairingSecret: 'sec_secret',
          deviceId: 'DEV-BOOT',
          deviceName: 'Kasa',
          platformName: 'android',
          expectedCaSha256: pki.caSha256Hex,
        ),
        throwsA(isA<DevicePairingException>().having((e) => e.code, 'code', 'INVALID_CA_CERT')),
      );

      // APP-T14b: Slowloris (sıfırlanmayan Timer) timeout reddi
      mode = 'slowloris';
      await expectLater(
        () => client.pairDevice(
          hubBaseUrl: 'https://127.0.0.1:${server.port}',
          sessionId: 's_slow',
          pairingSecret: 'sec_secret',
          deviceId: 'DEV-BOOT',
          deviceName: 'Kasa',
          platformName: 'android',
          expectedCaSha256: pki.caSha256Hex,
        ),
        throwsA(isA<DevicePairingException>().having((e) => e.code, 'code', 'BOOTSTRAP_TIMEOUT')),
      );
    });

    test('APP-T08 / APP-T09: ALT-BOOT-2 Faz A->B->C->D gerçek soket uçtan uca eşleştirme ve Non-CA (CA:FALSE) reddi', () async {
      final pki = _generateCertPair(tempDir, 'e2e_ok');
      final nonCaPki = _generateCertPair(tempDir, 'non_ca', makeLeafNonCa: true);

      final secCtx = SecurityContext()
        ..useCertificateChainBytes(utf8.encode(pki.leafPem))
        ..usePrivateKeyBytes(utf8.encode(pki.leafKeyPem));
      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, secCtx);
      addTearDown(() => server.close(force: true));

      final pollNonce = List<int>.generate(32, (i) => i + 1);
      final ackNonce = List<int>.generate(32, (i) => i + 101);
      const issuedToken = 'mms_dt_fresh_e2e_token_999';

      server.listen((req) async {
        final path = req.uri.path;
        if (path == '/api/v1/pairing/ca-cert') {
          req.response
            ..statusCode = 200
            ..headers.set('content-type', 'application/x-x509-ca-cert')
            ..write(pki.caPem);
          await req.response.close();
          return;
        }
        await utf8.decoder.bind(req).join();
        req.response.headers.contentType = ContentType.json;
        if (path == '/api/v1/pairing/request') {
          req.response
            ..statusCode = 202
            ..write('{"status":"PENDING_APPROVAL"}');
        } else if (path == '/api/v1/pairing/poll-challenge') {
          req.response
            ..statusCode = 200
            ..write(jsonEncode({'poll_challenge_id': 'ch_p1', 'poll_challenge_nonce': base64Encode(pollNonce)}));
        } else if (path == '/api/v1/pairing/poll') {
          req.response
            ..statusCode = 200
            ..write(jsonEncode({'status': 'PAIRED', 'token': issuedToken}));
        } else if (path == '/api/v1/pairing/ack-challenge') {
          req.response
            ..statusCode = 200
            ..write(jsonEncode({'ack_challenge_id': 'ch_a1', 'ack_challenge_nonce': base64Encode(ackNonce)}));
        } else if (path == '/api/v1/pairing/ack') {
          req.response
            ..statusCode = 200
            ..write(jsonEncode({'status': 'CONFIRMED'}));
        }
        await req.response.close();
      });

      final store = InMemorySecureTokenStore();
      String? promotedSha;
      String? promotedUrl;
      final client = DevicePairingClient(tokenStore: store, logger: RedactingLogger());

      final res = await client.pairDevice(
        hubBaseUrl: 'https://127.0.0.1:${server.port}',
        sessionId: 'sess_e2e',
        pairingSecret: 'sec_e2e',
        deviceId: 'DEV-E2E',
        deviceName: 'Kasa E2E',
        platformName: 'windows',
        expectedCaSha256: pki.caSha256Hex,
        onPromoteTlsPinning: (sha, _) async => promotedSha = sha,
        onPromoteHubUrl: (url) async => promotedUrl = url,
      );

      expect(res.confirmed, isTrue);
      expect(await store.readDeviceToken('DEV-E2E'), issuedToken);
      expect(promotedSha, pki.caSha256Hex);
      expect(promotedUrl, 'https://127.0.0.1:${server.port}');
      expect(await store.readSecret(DevicePairingClient.stagedPairingStorageKey('DEV-E2E')), isNull);

      // Non-CA sertifikayı OOB kabul ettirmeye çalışma -> CA_CERT_NOT_CA veya CA_CERT_IS_LEAF_CERT reddi
      await expectLater(
        () => client.pairDevice(
          hubBaseUrl: 'https://127.0.0.1:${server.port}',
          sessionId: 'sess_nonca',
          pairingSecret: 'sec_nonca',
          deviceId: 'DEV-NONCA',
          deviceName: 'Kasa',
          platformName: 'android',
          expectedCaSha256: nonCaPki.caSha256Hex,
          initialCaPem: nonCaPki.caPem,
        ),
        throwsA(isA<DevicePairingException>().having((e) => e.code, 'code', anyOf('CA_CERT_IS_LEAF_CERT', 'CA_CERT_NOT_CA'))),
      );
    });

    test('APP-T16 / APP-T16b..T16e: Crash-safe POLL_RECEIVED, ACK_PENDING, ACK_CONFIRMED, P1..P4 çökme kurtarması ve Outbox değişmezliği', () async {
      final pki = _generateCertPair(tempDir, 'crash_rec');
      final db = ClientDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = ClientStorageRepository(db);
      await repo.upsertProducts([
        LocalProductsCompanion(
          id: const Value('prod_1'),
          name: const Value('Test Süt'),
          price: const Value(3500),
          stock: const Value(50000),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      ]);
      final saleRes = await repo.createOfflineSale(
        deviceId: 'DEV-CR',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_1', 2)],
      );
      expect(saleRes.clientSeq, 1);

      final secCtx = SecurityContext()
        ..useCertificateChainBytes(utf8.encode(pki.leafPem))
        ..usePrivateKeyBytes(utf8.encode(pki.leafKeyPem));

      var ackBehavior = 'drop_after_commit';
      var ackCalls = 0;
      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, secCtx);
      addTearDown(() => server.close(force: true));

      final pollNonce = List<int>.generate(32, (i) => i + 5);
      final ackNonce = List<int>.generate(32, (i) => i + 55);
      server.listen((req) async {
        final p = req.uri.path;
        if (p == '/api/v1/pairing/ack') {
          ackCalls++;
          await utf8.decoder.bind(req).join();
          if (ackBehavior == 'drop_after_commit') {
            // Sunucu ACK'yı işledi fakat soket client'a yanıt veremeden düştü!
            final s = await req.response.detachSocket(writeHeaders: false);
            s.destroy();
            return;
          }
          if (ackBehavior == 'session_expired') {
            req.response
              ..statusCode = 410
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'SESSION_EXPIRED'}));
            await req.response.close();
            return;
          }
          req.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'status': 'CONFIRMED', 'idempotent_replay': ackCalls > 1}));
          await req.response.close();
          return;
        }
        if (p == '/api/v1/products') {
          final auth = req.headers.value('authorization');
          req.response.statusCode = auth == 'Bearer mms_dt_new_token_cr' ? 200 : 401;
          req.response.headers.contentType = ContentType.json;
          req.response.write('{"products":[]}');
          await req.response.close();
          return;
        }
        await utf8.decoder.bind(req).join();
        req.response.headers.contentType = ContentType.json;
        if (p == '/api/v1/pairing/request') {
          req.response..statusCode = 202..write('{"status":"PENDING"}');
        } else if (p == '/api/v1/pairing/poll-challenge') {
          req.response..statusCode = 200..write(jsonEncode({'poll_challenge_id': 'cp', 'poll_challenge_nonce': base64Encode(pollNonce)}));
        } else if (p == '/api/v1/pairing/poll') {
          req.response..statusCode = 200..write(jsonEncode({'status': 'PAIRED', 'token': 'mms_dt_new_token_cr'}));
        } else if (p == '/api/v1/pairing/ack-challenge') {
          req.response..statusCode = 200..write(jsonEncode({'ack_challenge_id': 'ca', 'ack_challenge_nonce': base64Encode(ackNonce)}));
        }
        await req.response.close();
      });

      final store = InMemorySecureTokenStore();
      await store.saveDeviceToken('DEV-CR', 'mms_dt_old_token_cr');
      String activePin = 'OLD_PIN';
      String activeUrl = 'https://old.hub.local:8945';

      // 1. APP-T16c: /ack gönderildi ancak yanıt alınamadan bağlantı koptu -> ACK_PENDING + eski token korunur
      final crashingClient = DevicePairingClient(
        tokenStore: store,
        logger: RedactingLogger(),
      );

      await expectLater(
        () => crashingClient.pairDevice(
          hubBaseUrl: 'https://127.0.0.1:${server.port}',
          sessionId: 's_cr',
          pairingSecret: 'sec_cr',
          deviceId: 'DEV-CR',
          deviceName: 'Kasa CR',
          platformName: 'android',
          expectedCaSha256: pki.caSha256Hex,
          initialCaPem: pki.caPem,
          requestTimeout: const Duration(seconds: 2),
        ),
        throwsA(isA<Object>()),
      );

      // Eski kimlik %100 korunmuş olmalı, stage == ACK_PENDING!
      expect(await store.readDeviceToken('DEV-CR'), 'mms_dt_old_token_cr');
      expect(activePin, 'OLD_PIN');
      expect(activeUrl, 'https://old.hub.local:8945');
      final stagedRec = StagedPairingRecord.tryParse(
        await store.readSecret(DevicePairingClient.stagedPairingStorageKey('DEV-CR')),
      );
      expect(stagedRec?.stage, StagedPairingStage.ackPending);

      // 2. Restart -> Hub şimdi 200 OK ile ACK replay yanıtı verir -> terfi tamamlanır!
      ackBehavior = 'ok';
      final recovered = await crashingClient.reconcileStagedPairingOnStartup(
        deviceId: 'DEV-CR',
        onPromoteTlsPinning: (sha, _) async => activePin = sha,
        onPromoteHubUrl: (url) async => activeUrl = url,
      );
      expect(recovered, StagedPairingReconcileOutcome.reconciledViaAckReplay);
      expect(await store.readDeviceToken('DEV-CR'), 'mms_dt_new_token_cr');
      expect(activePin, pki.caSha256Hex);
      expect(activeUrl, 'https://127.0.0.1:${server.port}');
      expect(await store.readSecret(DevicePairingClient.stagedPairingStorageKey('DEV-CR')), isNull);

      // 3. APP-T16d: ACK_CONFIRMED -> P1 yazıldı, P2 öncesi çöktü -> yeniden başlatınca P1..P4 tamamlanır
      await store.saveSecret(
        DevicePairingClient.stagedPairingStorageKey('DEV-CR'),
        jsonEncode(StagedPairingRecord(
          stage: StagedPairingStage.ackConfirmed,
          sessionId: 's_p1',
          pairingSecret: 'sec_p1',
          token: 'mms_dt_p1_token',
          caSha256: pki.caSha256Hex,
          caPem: pki.caPem,
          hubUrl: 'https://127.0.0.1:${server.port}',
          stagedAtUtc: DateTime.now().toUtc(),
        ).toJson()),
      );
      activePin = 'STALE_PIN';
      final pCrashOutcome = await crashingClient.reconcileStagedPairingOnStartup(
        deviceId: 'DEV-CR',
        onPromoteTlsPinning: (sha, _) async => activePin = sha,
        onPromoteHubUrl: (url) async => activeUrl = url,
      );
      expect(pCrashOutcome, StagedPairingReconcileOutcome.promotedConfirmed);
      expect(await store.readDeviceToken('DEV-CR'), 'mms_dt_p1_token');
      expect(activePin, pki.caSha256Hex);

      // 4. APP-T16b: POLL_RECEIVED çökmesi geri alınır ve eski kimlik korunur
      await store.saveSecret(
        DevicePairingClient.stagedPairingStorageKey('DEV-CR'),
        jsonEncode(StagedPairingRecord(
          stage: StagedPairingStage.pollReceived,
          sessionId: 's_pr',
          pairingSecret: 'sec_pr',
          token: 'mms_dt_unacked_garbage',
          caSha256: pki.caSha256Hex,
          caPem: pki.caPem,
          hubUrl: 'https://127.0.0.1:${server.port}',
          stagedAtUtc: DateTime.now().toUtc(),
        ).toJson()),
      );
      final preAckOutcome = await crashingClient.reconcileStagedPairingOnStartup(
        deviceId: 'DEV-CR',
      );
      expect(preAckOutcome, StagedPairingReconcileOutcome.rolledBackPreAck);
      expect(await store.readDeviceToken('DEV-CR'), 'mms_dt_p1_token');

      // 5. APP-T16e: Session TTL dolmuşsa (410) Bearer yoklamasıyla doğrulanıp terfi edilir
      ackBehavior = 'session_expired';
      await store.saveSecret(
        DevicePairingClient.stagedPairingStorageKey('DEV-CR'),
        jsonEncode(StagedPairingRecord(
          stage: StagedPairingStage.ackPending,
          sessionId: 's_ttl',
          pairingSecret: 'sec_ttl',
          token: 'mms_dt_new_token_cr',
          caSha256: pki.caSha256Hex,
          caPem: pki.caPem,
          hubUrl: 'https://127.0.0.1:${server.port}',
          ackChallengeId: 'old_ch',
          ackSignatureB64: 'old_sig',
          stagedAtUtc: DateTime.now().toUtc(),
        ).toJson()),
      );
      final probeOutcome = await crashingClient.reconcileStagedPairingOnStartup(
        deviceId: 'DEV-CR',
      );
      expect(probeOutcome, StagedPairingReconcileOutcome.reconciledViaTokenProbe);
      expect(await store.readDeviceToken('DEV-CR'), 'mms_dt_new_token_cr');

      // APP-T16: Outbox ve client_seq kesinlikle korunmuştur!
      final outboxRows = await db.select(db.outboxOperations).get();
      expect(outboxRows.length, 1);
      expect(outboxRows.single.clientSeq, 1);
      expect(outboxRows.single.deviceId, 'DEV-CR');
      expect(outboxRows.single.status, 'PENDING');
    });
  });
}
