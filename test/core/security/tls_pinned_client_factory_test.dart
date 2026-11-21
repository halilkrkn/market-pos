import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/core/network/api_client.dart';
import 'package:market_pos/core/security/tls_pinned_client_factory.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

String? _findOpenSslBinary() {
  const candidates = <String>[
    r'C:\Program Files\Git\usr\bin\openssl.exe',
    r'C:\Program Files\Git\mingw64\bin\openssl.exe',
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return candidate;
  }
  final res = Platform.isWindows
      ? Process.runSync('where.exe', <String>['openssl'])
      : Process.runSync('which', <String>['openssl']);
  if (res.exitCode == 0) {
    final first = res.stdout.toString().split(RegExp(r'\r?\n')).first.trim();
    if (first.isNotEmpty) return first;
  }
  return null;
}

({String certPem, String keyPem, String sha256Hex})? _generateSelfSignedCert(
  Directory workDir,
  String prefix,
) {
  final openssl = _findOpenSslBinary();
  if (openssl == null) return null;

  final certFile = File(p.join(workDir.path, '${prefix}_cert.pem'));
  final keyFile = File(p.join(workDir.path, '${prefix}_key.pem'));
  final res = Process.runSync(openssl, <String>[
    'req',
    '-x509',
    '-newkey',
    'rsa:2048',
    '-keyout',
    keyFile.path,
    '-out',
    certFile.path,
    '-days',
    '2',
    '-nodes',
    '-subj',
    '/CN=127.0.0.1',
    '-addext',
    'subjectAltName=IP:127.0.0.1,DNS:localhost',
  ]);
  if (res.exitCode != 0 || !certFile.existsSync() || !keyFile.existsSync()) {
    return null;
  }

  final certPem = certFile.readAsStringSync();
  final keyPem = keyFile.readAsStringSync();
  final ders = MmsPinnedTlsClientFactory.extractPemCertificatesDer(certPem);
  final shaHex = MmsPinnedTlsClientFactory.computeSha256Hex(ders.first);
  return (certPem: certPem, keyPem: keyPem, sha256Hex: shaHex);
}

/// Faz 7B (TLS-ROT): Test kök CA'sı ve bu CA ile imzalı yaprak sertifika üretir.
({String caPem, String caSha256, String leafPem, String leafKeyPem})? _generateCaSignedLeaf(
  Directory workDir,
  String prefix, {
  ({String caPem, String caKeyPath})? existingCa,
}) {
  final openssl = _findOpenSslBinary();
  if (openssl == null) return null;
  String caPem;
  String caKeyPath;
  if (existingCa == null) {
    final caCert = File(p.join(workDir.path, '${prefix}_ca.pem'));
    final caKey = File(p.join(workDir.path, '${prefix}_ca_key.pem'));
    final r = Process.runSync(openssl, <String>[
      'req', '-x509', '-newkey', 'rsa:2048', '-keyout', caKey.path, '-out', caCert.path,
      '-days', '2', '-nodes', '-subj', '/CN=MMS Test Root CA',
      '-addext', 'basicConstraints=critical,CA:TRUE',
      '-addext', 'keyUsage=critical,keyCertSign,cRLSign',
    ]);
    if (r.exitCode != 0) return null;
    caPem = caCert.readAsStringSync();
    caKeyPath = caKey.path;
  } else {
    caPem = existingCa.caPem;
    caKeyPath = existingCa.caKeyPath;
  }
  final caCertPath = p.join(workDir.path, '${prefix}_ca_in.pem');
  File(caCertPath).writeAsStringSync(caPem);
  final leafKey = File(p.join(workDir.path, '${prefix}_leaf_key.pem'));
  final csr = File(p.join(workDir.path, '${prefix}_leaf.csr'));
  final leafCert = File(p.join(workDir.path, '${prefix}_leaf.pem'));
  final ext = File(p.join(workDir.path, '${prefix}_ext.cnf'))
    ..writeAsStringSync('subjectAltName=IP:127.0.0.1,DNS:localhost\n');
  final r1 = Process.runSync(openssl, <String>[
    'req', '-newkey', 'rsa:2048', '-keyout', leafKey.path, '-out', csr.path, '-nodes', '-subj', '/CN=127.0.0.1',
  ]);
  if (r1.exitCode != 0) return null;
  final r2 = Process.runSync(openssl, <String>[
    'x509', '-req', '-in', csr.path, '-CA', caCertPath, '-CAkey', caKeyPath, '-CAcreateserial',
    '-out', leafCert.path, '-days', '2', '-extfile', ext.path,
  ]);
  if (r2.exitCode != 0) return null;
  final caDer = MmsPinnedTlsClientFactory.extractPemCertificatesDer(caPem).first;
  return (
    caPem: caPem,
    caSha256: MmsPinnedTlsClientFactory.computeSha256Hex(caDer),
    leafPem: leafCert.readAsStringSync(),
    leafKeyPem: leafKey.readAsStringSync(),
  );
}

({String caPem, String caSha256, String leafPem, String leafKeyPem, String leafSha256})? _generateCaSignedLeafWithOptions(
  Directory workDir,
  String prefix, {
  ({String caPem, String caKeyPath})? existingCa,
  String san = 'IP:127.0.0.1,DNS:localhost',
  bool expired = false,
  bool futureNotYetValid = false,
}) {
  final openssl = _findOpenSslBinary();
  if (openssl == null) return null;
  String caPem;
  String caKeyPath;
  if (existingCa == null) {
    final caCert = File(p.join(workDir.path, '${prefix}_ca.pem'));
    final caKey = File(p.join(workDir.path, '${prefix}_ca_key.pem'));
    final r = Process.runSync(openssl, <String>[
      'req', '-x509', '-newkey', 'rsa:2048', '-keyout', caKey.path, '-out', caCert.path,
      '-days', '2', '-nodes', '-subj', '/CN=MMS Test Root CA ($prefix)',
      '-addext', 'basicConstraints=critical,CA:TRUE',
      '-addext', 'keyUsage=critical,keyCertSign,cRLSign',
    ]);
    if (r.exitCode != 0) return null;
    caPem = caCert.readAsStringSync();
    caKeyPath = caKey.path;
  } else {
    caPem = existingCa.caPem;
    caKeyPath = existingCa.caKeyPath;
  }
  final caCertPath = p.join(workDir.path, '${prefix}_ca_in.pem');
  File(caCertPath).writeAsStringSync(caPem);
  final leafKey = File(p.join(workDir.path, '${prefix}_leaf_key.pem'));
  final csr = File(p.join(workDir.path, '${prefix}_leaf.csr'));
  final leafCert = File(p.join(workDir.path, '${prefix}_leaf.pem'));
  final ext = File(p.join(workDir.path, '${prefix}_ext.cnf'))
    ..writeAsStringSync('subjectAltName=$san\n');
  final r1 = Process.runSync(openssl, <String>[
    'req', '-newkey', 'rsa:2048', '-keyout', leafKey.path, '-out', csr.path, '-nodes', '-subj', '/CN=127.0.0.1',
  ]);
  if (r1.exitCode != 0) return null;

  if (expired || futureNotYetValid) {
    final startDate = futureNotYetValid ? '20990101000000Z' : '20240101000000Z';
    final endDate = futureNotYetValid ? '20990102000000Z' : '20240102000000Z';
    final caDbDir = Directory(p.join(workDir.path, '${prefix}_ca_db'))..createSync(recursive: true);
    final indexFile = File(p.join(caDbDir.path, 'index.txt'))..writeAsStringSync('');
    final serialFile = File(p.join(caDbDir.path, 'serial'))..writeAsStringSync('01\n');
    final caDbPosix = caDbDir.path.replaceAll('\\', '/');
    final indexPosix = indexFile.path.replaceAll('\\', '/');
    final serialPosix = serialFile.path.replaceAll('\\', '/');
    final caCnf = File(p.join(caDbDir.path, 'ca.cnf'))
      ..writeAsStringSync('''
[ca]
default_ca = CA_default
[CA_default]
new_certs_dir = $caDbPosix
database = $indexPosix
serial = $serialPosix
default_md = sha256
policy = policy_any
copy_extensions = copy
[policy_any]
commonName = optional
''');
    final rCa = Process.runSync(openssl, <String>[
      'ca',
      '-batch',
      '-config', caCnf.path,
      '-cert', caCertPath,
      '-keyfile', caKeyPath,
      '-startdate', startDate,
      '-enddate', endDate,
      '-in', csr.path,
      '-out', leafCert.path,
      '-extfile', ext.path,
    ]);
    if (rCa.exitCode != 0 || !leafCert.existsSync()) return null;
  } else {
    final r2 = Process.runSync(openssl, <String>[
      'x509', '-req', '-in', csr.path, '-CA', caCertPath, '-CAkey', caKeyPath, '-CAcreateserial',
      '-out', leafCert.path, '-days', '2', '-extfile', ext.path,
    ]);
    if (r2.exitCode != 0 || !leafCert.existsSync()) return null;
  }

  final caDer = MmsPinnedTlsClientFactory.extractPemCertificatesDer(caPem).first;
  final leafPem = leafCert.readAsStringSync();
  final leafDer = MmsPinnedTlsClientFactory.extractPemCertificatesDer(leafPem).first;
  return (
    caPem: caPem,
    caSha256: MmsPinnedTlsClientFactory.computeSha256Hex(caDer),
    leafPem: leafPem,
    leafKeyPem: leafKey.readAsStringSync(),
    leafSha256: MmsPinnedTlsClientFactory.computeSha256Hex(leafDer),
  );
}

Future<HttpServer> _serve(String certPem, String keyPem) async {
  final ctx = SecurityContext()
    ..useCertificateChainBytes(utf8.encode(certPem))
    ..usePrivateKeyBytes(utf8.encode(keyPem));
  final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, ctx);
  server.listen((req) {
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write('{"status":"HEALTHY"}')
      ..close();
  });
  return server;
}

void main() {
  group('Faz 7.3: B-2 TLS Certificate Pinning Gerçek Socket Testleri', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('mms_b2_tls_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'CA PEM + eşleşen pin ve leaf pin bağlantıyı kabul eder; uyumsuz pin ve güvenilmeyen sunucuyu reddeder',
      () async {
        final certA = _generateSelfSignedCert(tempDir, 'srv_a');
        final certB = _generateSelfSignedCert(tempDir, 'srv_b');
        if (certA == null || certB == null) {
          fail('Test ortamında OpenSSL ikilisi bulunamadı; B-2 TLS testi çalıştırılamadı.');
        }

        final ctxA = SecurityContext()
          ..useCertificateChainBytes(utf8.encode(certA.certPem))
          ..usePrivateKeyBytes(utf8.encode(certA.keyPem));
        final ctxB = SecurityContext()
          ..useCertificateChainBytes(utf8.encode(certB.certPem))
          ..usePrivateKeyBytes(utf8.encode(certB.keyPem));

        final serverA = await HttpServer.bindSecure(
          InternetAddress.loopbackIPv4,
          0,
          ctxA,
        );
        final serverB = await HttpServer.bindSecure(
          InternetAddress.loopbackIPv4,
          0,
          ctxB,
        );
        addTearDown(() async {
          await serverA.close(force: true);
          await serverB.close(force: true);
        });

        serverA.listen((req) {
          req.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write('{"status":"HEALTHY"}')
            ..close();
        });
        serverB.listen((req) {
          req.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write('{"status":"HEALTHY"}')
            ..close();
        });

        // 1. CA PEM + eşleşen SHA-256 parmak izi -> KABUL
        final clientCaPinned = MmsPinnedTlsClientFactory.createClient(
          PinnedTlsConfig(
            caCertPem: certA.certPem,
            expectedSha256Hex: certA.sha256Hex,
          ),
        );
        try {
          final resp = await clientCaPinned.get(
            Uri.parse('https://127.0.0.1:${serverA.port}/health'),
          );
          expect(resp.statusCode, 200);
        } finally {
          clientCaPinned.close();
        }

        // 2. Yalnızca leaf SHA-256 parmak izi -> KABUL
        final clientLeafPinned = MmsPinnedTlsClientFactory.createClient(
          PinnedTlsConfig(expectedSha256Hex: certA.sha256Hex),
        );
        try {
          final resp = await clientLeafPinned.get(
            Uri.parse('https://127.0.0.1:${serverA.port}/health'),
          );
          expect(resp.statusCode, 200);
        } finally {
          clientLeafPinned.close();
        }

        // 3. Yanlış parmak izi (CA PEM verilmiş olsa dahi!) -> RED
        final clientWrongPin = MmsPinnedTlsClientFactory.createClient(
          PinnedTlsConfig(
            caCertPem: certA.certPem,
            expectedSha256Hex: '0' * 64,
          ),
        );
        try {
          await expectLater(
            () => clientWrongPin.get(
              Uri.parse('https://127.0.0.1:${serverA.port}/health'),
            ),
            throwsA(isA<TlsPinMismatchException>()),
          );
        } finally {
          clientWrongPin.close();
        }

        // 4. Farklı sunucu sertifikası (Server B) -> RED
        final clientMismatchServer = MmsPinnedTlsClientFactory.createClient(
          PinnedTlsConfig(
            caCertPem: certA.certPem,
            expectedSha256Hex: certA.sha256Hex,
          ),
        );
        try {
          await expectLater(
            () => clientMismatchServer.get(
              Uri.parse('https://127.0.0.1:${serverB.port}/health'),
            ),
            throwsA(isA<TlsPinMismatchException>()),
          );
        } finally {
          clientMismatchServer.close();
        }
      },
    );
    test(
      'Faz 7B: Pin uyuşmazlığı TlsPinMismatchException olarak sınıflanır (sıradan ağ hatası değil) ve sunulan parmak izi raporlanır',
      () async {
        final certA = _generateSelfSignedCert(tempDir, 'pm_a');
        final certB = _generateSelfSignedCert(tempDir, 'pm_b');
        if (certA == null || certB == null) {
          fail('Test ortamında OpenSSL ikilisi bulunamadı.');
        }
        final serverB = await _serve(certB.certPem, certB.keyPem);
        addTearDown(() => serverB.close(force: true));

        final client = MmsPinnedTlsClientFactory.createClient(
          PinnedTlsConfig(expectedSha256Hex: certA.sha256Hex),
        );
        addTearDown(client.close);

        await expectLater(
          () => client.get(Uri.parse('https://127.0.0.1:${serverB.port}/health')),
          throwsA(
            isA<TlsPinMismatchException>()
                .having((e) => e.presentedSha256, 'presentedSha256', certB.sha256Hex)
                .having((e) => e.port, 'port', serverB.port),
          ),
        );

        // Aynı istemci üzerinden HttpSyncTransport ayrı hata türü üretir.
        final transport = HttpSyncTransport(
          MmsPinnedTlsClientFactory.createClient(PinnedTlsConfig(expectedSha256Hex: certA.sha256Hex)),
        );
        addTearDown(transport.close);
        final resp = await transport.postSale(
          hubUrl: 'https://127.0.0.1:${serverB.port}',
          token: 'gizli_token',
          payload: '{}',
        );
        expect(resp.isTlsPinMismatch, isTrue);
      },
    );

    test(
      'Faz 7B (TLS-ROT): CA sabitlemesinde aynı CA ile yenilenen sertifika kabul edilir; başka CA/kendinden imzalı sertifika reddedilir',
      () async {
        final gen1 = _generateCaSignedLeaf(tempDir, 'rot1');
        if (gen1 == null) fail('Test ortamında OpenSSL ikilisi bulunamadı.');
        final gen2 = _generateCaSignedLeaf(
          tempDir,
          'rot2',
          existingCa: (caPem: gen1.caPem, caKeyPath: p.join(tempDir.path, 'rot1_ca_key.pem')),
        );
        final foreign = _generateSelfSignedCert(tempDir, 'rot_foreign');
        if (gen2 == null || foreign == null) fail('Sertifika üretilemedi.');

        final pin = PinnedTlsConfig(caCertPem: gen1.caPem, expectedSha256Hex: gen1.caSha256);
        final s1 = await _serve(gen1.leafPem, gen1.leafKeyPem);
        final s2 = await _serve(gen2.leafPem, gen2.leafKeyPem); // rotasyon sonrası yeni yaprak
        final s3 = await _serve(foreign.certPem, foreign.keyPem);
        addTearDown(() async {
          await s1.close(force: true);
          await s2.close(force: true);
          await s3.close(force: true);
        });

        final client = MmsPinnedTlsClientFactory.createClient(pin);
        addTearDown(client.close);
        expect((await client.get(Uri.parse('https://127.0.0.1:${s1.port}/health'))).statusCode, 200);
        expect((await client.get(Uri.parse('https://127.0.0.1:${s2.port}/health'))).statusCode, 200,
            reason: 'Aynı kök CA ile imzalanmış yenilenmiş Hub sertifikası yeniden eşleştirme gerektirmemeli');
        await expectLater(
          () => client.get(Uri.parse('https://127.0.0.1:${s3.port}/health')),
          throwsA(isA<TlsPinMismatchException>()),
        );
      },
    );

    test(
      'ADR-017: IP SAN, Hostname SAN, süre sonu, aynı CA yenileme, farklı CA, leaf pin ve MITM ayrımını doğru sınıflandırır',
      () async {
        final ca1Root = _generateCaSignedLeafWithOptions(tempDir, 'adr17_ca1_valid');
        if (ca1Root == null) fail('Test ortamında OpenSSL ikilisi bulunamadı.');
        final ca1Ref = (caPem: ca1Root.caPem, caKeyPath: p.join(tempDir.path, 'adr17_ca1_valid_ca_key.pem'));

        final ca1Renewed = _generateCaSignedLeafWithOptions(
          tempDir,
          'adr17_ca1_renewed',
          existingCa: ca1Ref,
        );
        final ca1IpMissing = _generateCaSignedLeafWithOptions(
          tempDir,
          'adr17_ca1_no_ip',
          existingCa: ca1Ref,
          san: 'IP:10.0.0.99,DNS:localhost',
        );
        final ca1HostMismatch = _generateCaSignedLeafWithOptions(
          tempDir,
          'adr17_ca1_wrong_host',
          existingCa: ca1Ref,
          san: 'IP:127.0.0.1,DNS:wrong.hub.local',
        );
        final ca1Expired = _generateCaSignedLeafWithOptions(
          tempDir,
          'adr17_ca1_expired',
          existingCa: ca1Ref,
          expired: true,
        );
        final ca2Valid = _generateCaSignedLeafWithOptions(
          tempDir,
          'adr17_ca2_valid',
          san: 'IP:127.0.0.1,DNS:localhost',
        );
        final ca2BadSanMitm = _generateCaSignedLeafWithOptions(
          tempDir,
          'adr17_ca2_badsan',
          existingCa: ca2Valid == null
              ? null
              : (caPem: ca2Valid.caPem, caKeyPath: p.join(tempDir.path, 'adr17_ca2_valid_ca_key.pem')),
          san: 'IP:10.0.0.99,DNS:localhost',
        );

        if (ca1Renewed == null ||
            ca1IpMissing == null ||
            ca1HostMismatch == null ||
            ca1Expired == null ||
            ca2Valid == null ||
            ca2BadSanMitm == null) {
          fail('ADR-017 test sertifikaları üretilemedi.');
        }

        final sRenewed = await _serve(ca1Renewed.leafPem, ca1Renewed.leafKeyPem);
        final sNoIp = await _serve(ca1IpMissing.leafPem, ca1IpMissing.leafKeyPem);
        final sWrongHost = await _serve(ca1HostMismatch.leafPem, ca1HostMismatch.leafKeyPem);
        final sExpired = await _serve(ca1Expired.leafPem, ca1Expired.leafKeyPem);
        final sCa2 = await _serve(ca2Valid.leafPem, ca2Valid.leafKeyPem);
        final sCa2BadSan = await _serve(ca2BadSanMitm.leafPem, ca2BadSanMitm.leafKeyPem);
        addTearDown(() async {
          await sRenewed.close(force: true);
          await sNoIp.close(force: true);
          await sWrongHost.close(force: true);
          await sExpired.close(force: true);
          await sCa2.close(force: true);
          await sCa2BadSan.close(force: true);
        });

        final caPinned = MmsPinnedTlsClientFactory.createClient(
          PinnedTlsConfig(caCertPem: ca1Root.caPem, expectedSha256Hex: ca1Root.caSha256),
        );
        addTearDown(caPinned.close);

        // 1. Aynı CA ile yenilenen geçerli sunucu sertifikası kabul edilir.
        expect(
          (await caPinned.get(Uri.parse('https://127.0.0.1:${sRenewed.port}/health'))).statusCode,
          200,
        );

        // 2. Hub IP adresinin SAN içinde bulunmaması -> TlsCertificateValidationException(ipAddressMismatch)
        await expectLater(
          () => caPinned.get(Uri.parse('https://127.0.0.1:${sNoIp.port}/health')),
          throwsA(
            isA<TlsCertificateValidationException>().having(
              (e) => e.kind,
              'kind',
              TlsCertificateFailureKind.ipAddressMismatch,
            ),
          ),
        );

        // 3. Hostname/SAN uyuşmazlığı -> TlsCertificateValidationException(hostnameMismatch)
        await expectLater(
          () => caPinned.get(Uri.parse('https://localhost:${sWrongHost.port}/health')),
          throwsA(
            isA<TlsCertificateValidationException>().having(
              (e) => e.kind,
              'kind',
              TlsCertificateFailureKind.hostnameMismatch,
            ),
          ),
        );

        // 4. Süresi dolmuş aynı CA yaprak sertifikası -> TlsCertificateValidationException(certificateExpired)
        await expectLater(
          () => caPinned.get(Uri.parse('https://127.0.0.1:${sExpired.port}/health')),
          throwsA(
            isA<TlsCertificateValidationException>().having(
              (e) => e.kind,
              'kind',
              TlsCertificateFailureKind.certificateExpired,
            ),
          ),
        );

        // 5. Farklı CA imzalı sertifika -> TlsPinMismatchException(untrustedCaChain)
        await expectLater(
          () => caPinned.get(Uri.parse('https://127.0.0.1:${sCa2.port}/health')),
          throwsA(
            isA<TlsPinMismatchException>().having(
              (e) => e.reason,
              'reason',
              TlsPinMismatchReason.untrustedCaChain,
            ),
          ),
        );

        // 6. Olası MITM (sahte CA2 + bozuk IP SAN): zincir hatası SAN uyarısına indirgenemez, fail-closed reddedilir.
        await expectLater(
          () => caPinned.get(Uri.parse('https://127.0.0.1:${sCa2BadSan.port}/health')),
          throwsA(
            isA<TlsPinMismatchException>().having(
              (e) => e.reason,
              'reason',
              TlsPinMismatchReason.untrustedCaChain,
            ),
          ),
        );

        // CA-bundle sızma koruması: CA PEM içine yabancı CA2 eklense dahi yalnızca pinlenen CA1'e güvenilir.
        final smuggledClient = MmsPinnedTlsClientFactory.createClient(
          PinnedTlsConfig(
            caCertPem: '${ca2Valid.caPem}\n${ca1Root.caPem}',
            expectedSha256Hex: ca1Root.caSha256,
          ),
        );
        addTearDown(smuggledClient.close);
        await expectLater(
          () => smuggledClient.get(Uri.parse('https://127.0.0.1:${sCa2.port}/health')),
          throwsA(
            isA<TlsPinMismatchException>().having(
              (e) => e.reason,
              'reason',
              TlsPinMismatchReason.untrustedCaChain,
            ),
          ),
        );

        // 7. Doğrudan yaprak pin modunda gerçek leaf pin mismatch sınıflandırması
        final leafPinned = MmsPinnedTlsClientFactory.createClient(
          PinnedTlsConfig(expectedSha256Hex: ca1Root.leafSha256),
        );
        addTearDown(leafPinned.close);
        await expectLater(
          () => leafPinned.get(Uri.parse('https://127.0.0.1:${sRenewed.port}/health')),
          throwsA(
            isA<TlsPinMismatchException>()
                .having((e) => e.reason, 'reason', TlsPinMismatchReason.leafPinMismatch)
                .having((e) => e.presentedSha256, 'presentedSha256', ca1Renewed.leafSha256),
          ),
        );
      },
    );

    test(
      'ADR-017 M-3 & H-1: certificateNotYetValid, yabancı CA+expired, CA öz-sunumu, paralel istek yarışı ve gerçek soket MmsApiClient',
      () async {
        final ca1 = _generateCaSignedLeafWithOptions(tempDir, 'm3_ca1');
        if (ca1 == null) fail('OpenSSL ikilisi bulunamadı.');
        final ca1Ref = (caPem: ca1.caPem, caKeyPath: p.join(tempDir.path, 'm3_ca1_ca_key.pem'));

        final ca1NotYet = _generateCaSignedLeafWithOptions(
          tempDir,
          'm3_ca1_future',
          existingCa: ca1Ref,
          futureNotYetValid: true,
        );
        final ca1NoIp = _generateCaSignedLeafWithOptions(
          tempDir,
          'm3_ca1_noip',
          existingCa: ca1Ref,
          san: 'IP:10.0.0.99,DNS:localhost',
        );
        final ca2Expired = _generateCaSignedLeafWithOptions(
          tempDir,
          'm3_ca2_exp',
          expired: true,
        );
        if (ca1NotYet == null || ca1NoIp == null || ca2Expired == null) {
          fail('Test sertifikaları üretilemedi.');
        }

        final ca1KeyPem = File(ca1Ref.caKeyPath).readAsStringSync();
        final sValid = await _serve(ca1.leafPem, ca1.leafKeyPem);
        final sNotYet = await _serve(ca1NotYet.leafPem, ca1NotYet.leafKeyPem);
        final sNoIp = await _serve(ca1NoIp.leafPem, ca1NoIp.leafKeyPem);
        final sCa2Expired = await _serve(ca2Expired.leafPem, ca2Expired.leafKeyPem);
        // Hub kök CA sertifikasını doğrudan yaprak olarak sunarsa (CA öz-sunumu) SAN eşleşmediği için
        // badCertificateCallback true dönmemeli (eski kod leaf==CA eşitliğinden kabul ediyordu!).
        final sCaSelf = await _serve(ca1.caPem, ca1KeyPem);
        addTearDown(() async {
          await sValid.close(force: true);
          await sNotYet.close(force: true);
          await sNoIp.close(force: true);
          await sCa2Expired.close(force: true);
          await sCaSelf.close(force: true);
        });

        final client = MmsPinnedTlsClientFactory.createClient(
          PinnedTlsConfig(caCertPem: ca1.caPem, expectedSha256Hex: ca1.caSha256),
        );
        addTearDown(client.close);

        // 1. Geçersiz başlangıç tarihi (notYetValid)
        await expectLater(
          () => client.get(Uri.parse('https://127.0.0.1:${sNotYet.port}/health')),
          throwsA(
            isA<TlsCertificateValidationException>().having(
              (e) => e.kind,
              'kind',
              TlsCertificateFailureKind.certificateNotYetValid,
            ),
          ),
        );

        // 2. Yabancı CA + süresi dolmuş yaprak -> güven zinciri önceliklidir (untrustedCaChain)
        await expectLater(
          () => client.get(Uri.parse('https://127.0.0.1:${sCa2Expired.port}/health')),
          throwsA(
            isA<TlsPinMismatchException>().having(
              (e) => e.reason,
              'reason',
              TlsPinMismatchReason.untrustedCaChain,
            ),
          ),
        );

        // 3. CA öz-sunumu fail-closed reddedilir (eski callback leaf==CA nedeniyle kabul ediyordu; KEY_USAGE_BIT_INCORRECT / CA chain -> untrustedCaChain)
        await expectLater(
          () => client.get(Uri.parse('https://127.0.0.1:${sCaSelf.port}/health')),
          throwsA(
            isA<TlsPinMismatchException>().having(
              (e) => e.reason,
              'reason',
              TlsPinMismatchReason.untrustedCaChain,
            ),
          ),
        );

        // 4. H-1 Concurrency: Tek paylaşımlı client üzerinden aynı host:port'a 6 paralel hatalı istek
        final parallelResults = await Future.wait(
          List.generate(6, (_) async {
            try {
              await client.get(Uri.parse('https://127.0.0.1:${sNoIp.port}/health'));
              return 'UNEXPECTED_OK';
            } catch (e) {
              return e.runtimeType.toString();
            }
          }),
        );
        expect(
          parallelResults.every((t) => t == 'TlsCertificateValidationException'),
          isTrue,
          reason: 'Paralel isteklerde hiçbir raw HandshakeException sızmamalı: $parallelResults',
        );

        final parallelCaErrors = await Future.wait(
          List.generate(6, (_) async {
            try {
              await client.get(Uri.parse('https://127.0.0.1:${sCa2Expired.port}/health'));
              return 'UNEXPECTED_OK';
            } catch (e) {
              return e.runtimeType.toString();
            }
          }),
        );
        expect(
          parallelCaErrors.every((t) => t == 'TlsPinMismatchException'),
          isTrue,
          reason: 'Paralel yabancı CA isteklerinde TlsPinMismatchException korunmalı: $parallelCaErrors',
        );

        // 5. Gerçek soket + MmsPinnedTlsClientFactory -> MmsApiClient.checkHealth entegrasyonu
        final apiHealthy = MmsApiClient(baseUrl: 'https://127.0.0.1:${sValid.port}', client: client);
        expect((await apiHealthy.checkHealth()).isHealthy, isTrue);

        final apiNoIp = MmsApiClient(baseUrl: 'https://127.0.0.1:${sNoIp.port}', client: client);
        final certHealth = await apiNoIp.checkHealth();
        expect(certHealth.status, 'TLS_CERT_ERROR');

        final apiForeignCa = MmsApiClient(baseUrl: 'https://127.0.0.1:${sCa2Expired.port}', client: client);
        final pinHealth = await apiForeignCa.checkHealth();
        expect(pinHealth.status, 'TLS_PIN_MISMATCH');
      },
    );
  });
}
