import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/core/logging/redacting_logger.dart';
import 'package:market_pos/core/security/secure_token_store.dart';
import 'package:market_pos/features/security/data/device_pairing_client.dart';
import 'package:market_pos/features/security/data/windows_zero_touch_bootstrapper.dart';
import 'package:market_pos/features/setup/domain/app_setup_config.dart';
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

({String caPem, String caSha256Hex, String leafPem, String leafKeyPem})
    _generateCertPair(Directory dir, String prefix) {
  final ssl = _findOpenSsl();
  final caKey = p.join(dir.path, '${prefix}_ca.key');
  final caCrt = p.join(dir.path, '${prefix}_ca.crt');
  final r1 = Process.runSync(ssl, [
    'req',
    '-x509',
    '-newkey',
    'rsa:2048',
    '-nodes',
    '-keyout',
    caKey,
    '-out',
    caCrt,
    '-days',
    '10',
    '-subj',
    '/CN=MMS Zero-Touch Test Root CA ($prefix)',
    '-addext',
    'basicConstraints=critical,CA:TRUE',
    '-addext',
    'keyUsage=critical,keyCertSign,cRLSign',
  ]);
  if (r1.exitCode != 0) throw StateError('OpenSSL CA error: ${r1.stderr}');

  final srvKey = p.join(dir.path, '${prefix}_srv.key');
  final csr = p.join(dir.path, '${prefix}_srv.csr');
  final srvCrt = p.join(dir.path, '${prefix}_srv.crt');
  final extFile = File(p.join(dir.path, '${prefix}_ext.cnf'))
    ..writeAsStringSync(
      'basicConstraints=critical,CA:FALSE\n'
      'keyUsage=critical,digitalSignature,keyEncipherment\n'
      'extendedKeyUsage=serverAuth\n'
      'subjectAltName=IP:127.0.0.1,DNS:localhost\n',
    );

  final r2 = Process.runSync(ssl, [
    'req',
    '-newkey',
    'rsa:2048',
    '-nodes',
    '-keyout',
    srvKey,
    '-out',
    csr,
    '-subj',
    '/CN=localhost',
  ]);
  if (r2.exitCode != 0) throw StateError('OpenSSL CSR error: ${r2.stderr}');

  final r3 = Process.runSync(ssl, [
    'x509',
    '-req',
    '-in',
    csr,
    '-CA',
    caCrt,
    '-CAkey',
    caKey,
    '-CAcreateserial',
    '-out',
    srvCrt,
    '-days',
    '5',
    '-extfile',
    extFile.path,
  ]);
  if (r3.exitCode != 0) throw StateError('OpenSSL Sign error: ${r3.stderr}');

  final caPem = File(caCrt).readAsStringSync();
  final canonicalCa =
      extractCanonicalSingleCertDer(Uint8List.fromList(utf8.encode(caPem)));
  return (
    caPem: canonicalCa.toPem(),
    caSha256Hex: canonicalCa.sha256Hex,
    leafPem: File(srvCrt).readAsStringSync(),
    leafKeyPem: File(srvKey).readAsStringSync(),
  );
}

void main() {
  group('WindowsZeroTouchBootstrapper (Zero-Touch CA Pinning + Auto-Bootstrap)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('mms_zt_client_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('1. Boş Windows istemcisinde otomatik CA sabitleyip auto-bootstrap ile token alır, ikinci açılışta tekrar çağırmaz', () async {
      final certs = _generateCertPair(tempDir, 'zt1');
      final secCtx = SecurityContext()
        ..useCertificateChainBytes(utf8.encode(certs.leafPem))
        ..usePrivateKeyBytes(utf8.encode(certs.leafKeyPem));

      var caCertRequests = 0;
      var autoBootstrapCalls = 0;
      String? lastAutoBootstrapDeviceId;
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        secCtx,
      );
      server.listen((req) async {
        if (req.uri.path == '/api/v1/pairing/ca-cert') {
          caCertRequests++;
          req.response
            ..statusCode = 200
            ..headers.set('content-type', 'application/x-x509-ca-cert')
            ..write(certs.caPem);
          await req.response.close();
          return;
        }
        if (req.uri.path == '/health') {
          req.response
            ..statusCode = 200
            ..headers.set('content-type', 'application/json')
            ..write(jsonEncode({'status': 'UP'}));
          await req.response.close();
          return;
        }
        if (req.uri.path == '/api/v1/local/auto-bootstrap') {
          autoBootstrapCalls++;
          final rawBody = await utf8.decoder.bind(req).join();
          final body = jsonDecode(rawBody) as Map<String, dynamic>;
          lastAutoBootstrapDeviceId = body['device_id'] as String?;
          req.response
            ..statusCode = 200
            ..headers.set('content-type', 'application/json')
            ..write(jsonEncode({
              'device_id': lastAutoBootstrapDeviceId,
              'device_token': 'mms_zt_owner_token_001',
              'role': 'OWNER',
              'owner_bootstrap_completed': true,
            }));
          await req.response.close();
          return;
        }
        req.response.statusCode = 404;
        await req.response.close();
      });

      try {
        final tokenStore = InMemorySecureTokenStore();
        final logger = RedactingLogger();
        final pairingClient = DevicePairingClient(
          tokenStore: tokenStore,
          logger: logger,
        );
        final bootstrapper = WindowsZeroTouchBootstrapper(
          pairingClient: pairingClient,
          tokenStore: tokenStore,
          logger: logger,
          isWindowsPlatform: () => true,
        );

        var config = AppSetupConfig.initial(deviceId: 'POS-WIN-ZT-100');
        var refreshCalled = 0;

        // İlk açılış: CA sabitlenir ve auto-bootstrap token alınır
        final first = await bootstrapper.run(
          hubBaseUrl: 'https://127.0.0.1:${server.port}',
          setupConfig: config,
          onSavePinnedCa: (sha, pem) async {
            config = config.copyWith(
              tlsPinningEnabled: true,
              pinnedCaSha256: sha,
              pinnedCaPem: pem,
            );
            return config;
          },
          onSaveDeviceToken: (devId, tok) =>
              tokenStore.saveDeviceToken(devId, tok),
          onRefreshAfterBootstrap: () async {
            refreshCalled++;
          },
        );

        expect(first.status, equals(WindowsZeroTouchStatus.bootstrapped));
        expect(first.caPinnedNow, isTrue);
        expect(config.hasPinnedCertificate, isTrue);
        expect(config.normalizedPinSha256, equals(certs.caSha256Hex));
        expect(
          await tokenStore.readDeviceToken('POS-WIN-ZT-100'),
          equals('mms_zt_owner_token_001'),
        );
        expect(lastAutoBootstrapDeviceId, equals('POS-WIN-ZT-100'));
        expect(caCertRequests, equals(1));
        expect(autoBootstrapCalls, equals(1));
        expect(refreshCalled, equals(1));

        // İkinci açılış: CA ve token zaten var -> ne ca-cert ne auto-bootstrap çağrılır
        final second = await bootstrapper.run(
          hubBaseUrl: 'https://127.0.0.1:${server.port}',
          setupConfig: config,
          onSavePinnedCa: (sha, pem) async {
            fail('İkinci açılışta onSavePinnedCa çağrılmamalı');
          },
          onSaveDeviceToken: (devId, tok) async {
            fail('İkinci açılışta onSaveDeviceToken çağrılmamalı');
          },
          onRefreshAfterBootstrap: () async {
            refreshCalled++;
          },
        );

        expect(second.status, equals(WindowsZeroTouchStatus.alreadyConfigured));
        expect(second.caPinnedNow, isFalse);
        expect(caCertRequests, equals(1));
        expect(autoBootstrapCalls, equals(1));
        expect(refreshCalled, equals(1));
      } finally {
        await server.close(force: true);
      }
    });

    test('2. Hub 409 ERR_OWNER_ALREADY_BOOTSTRAPPED dönerse sessizce geçer, hata patlatmaz', () async {
      final certs = _generateCertPair(tempDir, 'zt2');
      final secCtx = SecurityContext()
        ..useCertificateChainBytes(utf8.encode(certs.leafPem))
        ..usePrivateKeyBytes(utf8.encode(certs.leafKeyPem));

      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        secCtx,
      );
      server.listen((req) async {
        if (req.uri.path == '/api/v1/pairing/ca-cert') {
          req.response
            ..statusCode = 200
            ..headers.set('content-type', 'application/x-x509-ca-cert')
            ..write(certs.caPem);
          await req.response.close();
          return;
        }
        if (req.uri.path == '/health') {
          req.response
            ..statusCode = 200
            ..headers.set('content-type', 'application/json')
            ..write(jsonEncode({'status': 'UP'}));
          await req.response.close();
          return;
        }
        if (req.uri.path == '/api/v1/local/auto-bootstrap') {
          req.response
            ..statusCode = 409
            ..headers.set('content-type', 'application/json; charset=utf-8')
            ..add(utf8.encode(jsonEncode({
              'error': 'ERR_OWNER_ALREADY_BOOTSTRAPPED',
              'code': 'ERR_OWNER_ALREADY_BOOTSTRAPPED',
              'message': 'Zaten mühürlenmiş.',
            })));
          await req.response.close();
          return;
        }
        req.response.statusCode = 404;
        await req.response.close();
      });

      try {
        final tokenStore = InMemorySecureTokenStore();
        final logger = RedactingLogger();
        final bootstrapper = WindowsZeroTouchBootstrapper(
          pairingClient: DevicePairingClient(
            tokenStore: tokenStore,
            logger: logger,
          ),
          tokenStore: tokenStore,
          logger: logger,
          isWindowsPlatform: () => true,
        );

        var config = AppSetupConfig.initial(deviceId: 'POS-WIN-409');
        final res = await bootstrapper.run(
          hubBaseUrl: 'https://127.0.0.1:${server.port}',
          setupConfig: config,
          onSavePinnedCa: (sha, pem) async {
            config = config.copyWith(
              tlsPinningEnabled: true,
              pinnedCaSha256: sha,
              pinnedCaPem: pem,
            );
            return config;
          },
          onSaveDeviceToken: (devId, tok) async {
            fail('409 durumunda token kaydedilmemeli');
          },
        );

        expect(
          res.status,
          equals(WindowsZeroTouchStatus.caPinnedOwnerAlreadyExists),
        );
        expect(res.caPinnedNow, isTrue);
        expect(config.hasPinnedCertificate, isTrue);
        expect(await tokenStore.readDeviceToken('POS-WIN-409'), isNull);
      } finally {
        await server.close(force: true);
      }
    });

    test('3. Hub kapalıyken uygulamayı bloklamadan sessizce hubUnreachable döner', () async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final unusedPort = probe.port;
      await probe.close();

      final tokenStore = InMemorySecureTokenStore();
      final logger = RedactingLogger();
      final bootstrapper = WindowsZeroTouchBootstrapper(
        pairingClient: DevicePairingClient(
          tokenStore: tokenStore,
          logger: logger,
          bootstrapTimeout: const Duration(seconds: 2),
        ),
        tokenStore: tokenStore,
        logger: logger,
        isWindowsPlatform: () => true,
        requestTimeout: const Duration(seconds: 2),
      );

      final res = await bootstrapper.run(
        hubBaseUrl: 'https://127.0.0.1:$unusedPort',
        setupConfig: AppSetupConfig.initial(deviceId: 'POS-WIN-OFFLINE'),
        onSavePinnedCa: (sha, pem) async => AppSetupConfig.initial(),
        onSaveDeviceToken: (devId, tok) async {},
      );

      expect(res.status, equals(WindowsZeroTouchStatus.hubUnreachable));
    });

    test('4. Fail-Closed: Uzak LAN IP, HTTP veya Android profilinde otomatik bootstrap ASLA çalışmaz', () async {
      var httpCalled = false;
      final tokenStore = InMemorySecureTokenStore();
      final logger = RedactingLogger();
      final pairingClient = DevicePairingClient(
        tokenStore: tokenStore,
        logger: logger,
      );

      // A) Uzak LAN IP (Windows'ta bile reddedilir)
      final winBootstrapper = WindowsZeroTouchBootstrapper(
        pairingClient: pairingClient,
        tokenStore: tokenStore,
        logger: logger,
        isWindowsPlatform: () => true,
        pinnedClientFactory: (_) => MockClient((_) async {
          httpCalled = true;
          return http.Response('{}', 200);
        }),
      );

      final lanRes = await winBootstrapper.run(
        hubBaseUrl: 'https://192.168.1.50:8945',
        setupConfig: AppSetupConfig.initial(),
        onSavePinnedCa: (_, _) async => fail('LAN IP için CA kaydedilmemeli'),
        onSaveDeviceToken: (_, _) async => fail('LAN IP için token kaydedilmemeli'),
      );
      expect(lanRes.status, equals(WindowsZeroTouchStatus.skippedNotEligible));

      // B) Şifresiz HTTP (127.0.0.1 olsa bile reddedilir)
      final httpRes = await winBootstrapper.run(
        hubBaseUrl: 'http://127.0.0.1:8945',
        setupConfig: AppSetupConfig.initial(),
        onSavePinnedCa: (_, _) async => fail('HTTP için CA kaydedilmemeli'),
        onSaveDeviceToken: (_, _) async => fail('HTTP için token kaydedilmemeli'),
      );
      expect(httpRes.status, equals(WindowsZeroTouchStatus.skippedNotEligible));

      // C) Android / Windows dışı profil (127.0.0.1 HTTPS olsa bile reddedilir)
      final androidBootstrapper = WindowsZeroTouchBootstrapper(
        pairingClient: pairingClient,
        tokenStore: tokenStore,
        logger: logger,
        isWindowsPlatform: () => false,
        pinnedClientFactory: (_) => MockClient((_) async {
          httpCalled = true;
          return http.Response('{}', 200);
        }),
      );
      final androidRes = await androidBootstrapper.run(
        hubBaseUrl: 'https://127.0.0.1:8945',
        setupConfig: AppSetupConfig.initial(),
        onSavePinnedCa: (_, _) async => fail('Android için CA kaydedilmemeli'),
        onSaveDeviceToken: (_, _) async => fail('Android için token kaydedilmemeli'),
      );
      expect(
        androidRes.status,
        equals(WindowsZeroTouchStatus.skippedNotEligible),
      );
      expect(httpCalled, isFalse);

      // D) fetchLoopbackRootCaTofu da Android ve LAN IP'yi fail-closed reddeder
      await expectLater(
        pairingClient.fetchLoopbackRootCaTofu(
          hubBaseUrl: 'https://127.0.0.1:8945',
          isWindowsOverride: false,
        ),
        throwsA(
          isA<DevicePairingException>().having(
            (e) => e.code,
            'code',
            'LOOPBACK_TOFU_FORBIDDEN',
          ),
        ),
      );
      await expectLater(
        pairingClient.fetchLoopbackRootCaTofu(
          hubBaseUrl: 'https://192.168.1.50:8945',
          isWindowsOverride: true,
        ),
        throwsA(
          isA<DevicePairingException>().having(
            (e) => e.code,
            'code',
            'LOOPBACK_TOFU_FORBIDDEN',
          ),
        ),
      );
    });
  });
}
