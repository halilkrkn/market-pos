import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/certificate_manager.dart';
import '../lib/security/pepper_manager.dart';
import '../lib/security/token_manager.dart';

class _FakeConnectionInfo implements HttpConnectionInfo {
  @override
  final InternetAddress remoteAddress;
  @override
  int get remotePort => 54321;
  @override
  int get localPort => 8945;

  _FakeConnectionInfo({required this.remoteAddress});
}

void main() {
  group('Zero-Touch Loopback Auto-Bootstrap (/api/v1/local/auto-bootstrap)', () {
    late Directory tempDir;

    setUp(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      tempDir = Directory.systemTemp.createTempSync('mms_zt_bootstrap_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    Future<
        ({
          SpikeDatabase db,
          WriteQueue wq,
          PepperManager pepper,
          SpikeServer server,
          HttpServer ioServer,
          String baseUrl,
        })> bootServer({
      bool requireTls = false,
      String? caCertPath,
      String? serverCertPath,
    }) async {
      configureSqliteNative();
      final dbFile = File(p.join(tempDir.path, 'data', 'market_master.db'));
      await dbFile.parent.create(recursive: true);
      final secDir = Directory(p.join(tempDir.path, 'security'));
      await secDir.create(recursive: true);
      final db = SpikeDatabase(dbFile);
      await db.customStatement('SELECT 1;');
      final wq = WriteQueue();
      final pepper = PepperManager(File(p.join(secDir.path, 'pepper.dpapi')))
        ..initialize(overrideForTesting: 'pepper_zero_touch_test_32bytes_min');

      final server = SpikeServer(
        db: db,
        writeQueue: wq,
        dbFile: dbFile,
        backupDirectory: p.join(tempDir.path, 'backups'),
        pepperManager: pepper,
        adminSecret: 'admin_secret_zt_test',
        requireTls: requireTls,
        caCertPath: caCertPath,
        serverCertPath: serverCertPath,
      );
      final ioServer = await shelf_io.serve(
        server.handler,
        InternetAddress.loopbackIPv4,
        0,
      );
      return (
        db: db,
        wq: wq,
        pepper: pepper,
        server: server,
        ioServer: ioServer,
        baseUrl: 'http://127.0.0.1:${ioServer.port}',
      );
    }

    test('1. Boş Hub loopback ilk çağrısı 200 + OWNER token döner, mühürler ve OWNER pairing erişimi açar', () async {
      final ctx = await bootServer();
      try {
        final res = await http.post(
          Uri.parse('${ctx.baseUrl}/api/v1/local/auto-bootstrap'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'device_id': 'POS-WIN-ZT-01'}),
        );
        expect(res.statusCode, equals(200));
        expect(res.headers['cache-control'], equals('no-store'));

        final json = jsonDecode(res.body) as Map<String, dynamic>;
        expect(json['device_id'], equals('POS-WIN-ZT-01'));
        expect(json['role'], equals('OWNER'));
        expect(json['owner_bootstrap_completed'], isTrue);
        final token = json['device_token'] as String?;
        expect(token, isNotNull);
        expect(token!.length, greaterThan(16));

        // DB mühür ve audit doğrulaması
        final metaCompleted = await (ctx.db.select(ctx.db.hubMetadata)
              ..where((m) => m.key.equals('owner_bootstrap_completed')))
            .getSingleOrNull();
        expect(metaCompleted?.value, equals('true'));

        final metaDevice = await (ctx.db.select(ctx.db.hubMetadata)
              ..where((m) => m.key.equals('owner_bootstrap_device_id')))
            .getSingleOrNull();
        expect(metaDevice?.value, equals('POS-WIN-ZT-01'));

        final device = await (ctx.db.select(ctx.db.devices)
              ..where((d) => d.deviceId.equals('POS-WIN-ZT-01')))
            .getSingleOrNull();
        expect(device, isNotNull);
        expect(device!.name, equals('Windows Ana Bilgisayar'));
        expect(device.role, equals('OWNER'));
        expect(device.isActive, isTrue);
        expect(device.isConfirmed, isTrue);

        final auditLogs = await (ctx.db.select(ctx.db.deviceAuditLogs)
              ..where((l) =>
                  l.deviceId.equals('POS-WIN-ZT-01') &
                  l.action.equals('LOCAL_AUTO_BOOTSTRAP')))
            .get();
        expect(auditLogs, hasLength(1));

        // Alınan OWNER token ile /api/v1/devices/me ve loopback pairing uçları admin secret olmadan çalışır
        final meRes = await http.get(
          Uri.parse('${ctx.baseUrl}/api/v1/devices/me'),
          headers: {
            'authorization': 'Bearer $token',
            'x-mms-tenant-id': SpikeServer.defaultTenantId,
            'x-mms-store-id': SpikeServer.defaultStoreId,
          },
        );
        expect(meRes.statusCode, equals(200));
        final meJson = jsonDecode(meRes.body) as Map<String, dynamic>;
        expect(meJson['role'], equals('OWNER'));
        expect(meJson['owner_bootstrap_completed'], isTrue);

        final reqListRes = await http.get(
          Uri.parse('${ctx.baseUrl}/api/v1/pairing/requests'),
          headers: {'authorization': 'Bearer $token'},
        );
        expect(reqListRes.statusCode, equals(200));

        final sessRes = await http.post(
          Uri.parse('${ctx.baseUrl}/api/v1/pairing/session'),
          headers: {'authorization': 'Bearer $token'},
          body: '{}',
        );
        expect(sessRes.statusCode, equals(201));
      } finally {
        await ctx.ioServer.close(force: true);
        await ctx.server.stop();
        await ctx.wq.drain();
        await ctx.db.close();
      }
    });

    test('2. İkinci auto-bootstrap çağrısı 409 ERR_OWNER_ALREADY_BOOTSTRAPPED ile reddedilir', () async {
      final ctx = await bootServer();
      try {
        final first = await http.post(
          Uri.parse('${ctx.baseUrl}/api/v1/local/auto-bootstrap'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'device_id': 'POS-WIN-ZT-01',
            'name': 'Ana Kasa PC',
          }),
        );
        expect(first.statusCode, equals(200));

        final second = await http.post(
          Uri.parse('${ctx.baseUrl}/api/v1/local/auto-bootstrap'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'device_id': 'POS-WIN-ZT-02'}),
        );
        expect(second.statusCode, equals(409));
        expect(second.headers['cache-control'], equals('no-store'));
        final err = jsonDecode(second.body) as Map<String, dynamic>;
        expect(err['code'], equals('ERR_OWNER_ALREADY_BOOTSTRAPPED'));
      } finally {
        await ctx.ioServer.close(force: true);
        await ctx.server.stop();
        await ctx.wq.drain();
        await ctx.db.close();
      }
    });

    test('3. Aktif OWNER cihazı zaten mevcutsa metadata olmasa bile 409 ERR_OWNER_ALREADY_BOOTSTRAPPED döner', () async {
      final ctx = await bootServer();
      try {
        final rawTok = TokenManager.generateToken();
        final salt = TokenManager.generateSalt();
        final tokHash = TokenManager.hashToken(
          rawToken: rawTok,
          salt: salt,
          pepper: ctx.pepper.pepper,
        );
        await ctx.db.into(ctx.db.devices).insert(
              DevicesCompanion(
                deviceId: const Value('EXISTING-OWNER'),
                name: const Value('Mevcut Owner'),
                tokenHash: Value(tokHash),
                salt: Value(salt),
                isActive: const Value(true),
                isConfirmed: const Value(true),
                role: const Value('OWNER'),
              ),
            );

        final res = await http.post(
          Uri.parse('${ctx.baseUrl}/api/v1/local/auto-bootstrap'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'device_id': 'POS-WIN-NEW'}),
        );
        expect(res.statusCode, equals(409));
        expect(jsonDecode(res.body)['code'], equals('ERR_OWNER_ALREADY_BOOTSTRAPPED'));
      } finally {
        await ctx.ioServer.close(force: true);
        await ctx.server.stop();
        await ctx.wq.drain();
        await ctx.db.close();
      }
    });

    test('4. Loopback dışı IP ve connectionInfo yokluğu 403 ERR_LOOPBACK_ONLY döner; ::1 kabul edilir', () async {
      final ctx = await bootServer();
      try {
        // LAN IP -> 403 ERR_LOOPBACK_ONLY
        final lanReq = Request(
          'POST',
          Uri.parse('http://192.168.1.20:8945/api/v1/local/auto-bootstrap'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'device_id': 'ROGUE-LAN'}),
          context: {
            'shelf.io.connection_info': _FakeConnectionInfo(
              remoteAddress: InternetAddress('192.168.1.50'),
            ),
          },
        );
        final lanRes = await ctx.server.handler(lanReq);
        expect(lanRes.statusCode, equals(403));
        expect(jsonDecode(await lanRes.readAsString())['code'], equals('ERR_LOOPBACK_ONLY'));

        // Null connectionInfo -> 403 ERR_LOOPBACK_ONLY
        final nullConnReq = Request(
          'POST',
          Uri.parse('http://127.0.0.1:8945/api/v1/local/auto-bootstrap'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'device_id': 'ROGUE-NULL'}),
        );
        final nullConnRes = await ctx.server.handler(nullConnReq);
        expect(nullConnRes.statusCode, equals(403));
        expect(jsonDecode(await nullConnRes.readAsString())['code'], equals('ERR_LOOPBACK_ONLY'));

        // IPv6 loopback (::1) -> 200 OK
        final ipv6Req = Request(
          'POST',
          Uri.parse('http://[::1]:8945/api/v1/local/auto-bootstrap'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'device_id': 'POS-WIN-IPV6'}),
          context: {
            'shelf.io.connection_info': _FakeConnectionInfo(
              remoteAddress: InternetAddress('::1'),
            ),
          },
        );
        final ipv6Res = await ctx.server.handler(ipv6Req);
        expect(ipv6Res.statusCode, equals(200));
        final ipv6Json = jsonDecode(await ipv6Res.readAsString()) as Map<String, dynamic>;
        final ownerToken = ipv6Json['device_token'] as String;

        // LAN üzerinden OWNER token ile /api/v1/pairing/session denemesi yine reddedilir
        final lanPairingReq = Request(
          'POST',
          Uri.parse('http://192.168.1.20:8945/api/v1/pairing/session'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $ownerToken',
          },
          body: '{}',
          context: {
            'shelf.io.connection_info': _FakeConnectionInfo(
              remoteAddress: InternetAddress('192.168.1.50'),
            ),
          },
        );
        final lanPairingRes = await ctx.server.handler(lanPairingReq);
        expect(lanPairingRes.statusCode, equals(403));
        expect(
          jsonDecode(await lanPairingRes.readAsString())['code'],
          equals('ERR_LOOPBACK_REQUIRED'),
        );
      } finally {
        await ctx.ioServer.close(force: true);
        await ctx.server.stop();
        await ctx.wq.drain();
        await ctx.db.close();
      }
    });

    test('5. requireTls=true iken HTTP reddedilir (426), draining=503 ve boş device_id=400 döner', () async {
      final ctx = await bootServer(requireTls: true);
      try {
        final httpReq = Request(
          'POST',
          Uri.parse('http://127.0.0.1:8945/api/v1/local/auto-bootstrap'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'device_id': 'POS-WIN-HTTP'}),
          context: {
            'shelf.io.connection_info': _FakeConnectionInfo(
              remoteAddress: InternetAddress('127.0.0.1'),
            ),
          },
        );
        final httpRes = await ctx.server.handler(httpReq);
        expect(httpRes.statusCode, equals(426));
        expect(jsonDecode(await httpRes.readAsString())['code'], equals('ERR_TLS_REQUIRED'));

        final missingIdReq = Request(
          'POST',
          Uri.parse('https://127.0.0.1:8945/api/v1/local/auto-bootstrap'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({}),
          context: {
            'shelf.io.connection_info': _FakeConnectionInfo(
              remoteAddress: InternetAddress('127.0.0.1'),
            ),
          },
        );
        final missingIdRes = await ctx.server.handler(missingIdReq);
        expect(missingIdRes.statusCode, equals(400));
        expect(jsonDecode(await missingIdRes.readAsString())['code'], equals('ERR_DEVICE_ID_REQUIRED'));

        ctx.wq.markDraining();
        final drainingReq = Request(
          'POST',
          Uri.parse('https://127.0.0.1:8945/api/v1/local/auto-bootstrap'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'device_id': 'POS-WIN-DRAIN'}),
          context: {
            'shelf.io.connection_info': _FakeConnectionInfo(
              remoteAddress: InternetAddress('127.0.0.1'),
            ),
          },
        );
        final drainingRes = await ctx.server.handler(drainingReq);
        expect(drainingRes.statusCode, equals(503));
      } finally {
        await ctx.ioServer.close(force: true);
        await ctx.server.stop();
        await ctx.wq.drain();
        await ctx.db.close();
      }
    });

    test('6. Mevcut /api/v1/admin/owner/bootstrap ucu bozulmamıştır ve mühür sonrası auto-bootstrap 409 döner', () async {
      final ctx = await bootServer();
      try {
        final adminBootstrap = await http.post(
          Uri.parse('${ctx.baseUrl}/api/v1/admin/owner/bootstrap'),
          headers: {
            'content-type': 'application/json',
            'x-admin-secret': 'admin_secret_zt_test',
          },
          body: jsonEncode({
            'device_id': 'ADMIN-OWNER-01',
            'name': 'Manual Owner',
            'register_if_missing': true,
          }),
        );
        expect(adminBootstrap.statusCode, equals(200));

        final autoRes = await http.post(
          Uri.parse('${ctx.baseUrl}/api/v1/local/auto-bootstrap'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'device_id': 'POS-WIN-02'}),
        );
        expect(autoRes.statusCode, equals(409));
        expect(jsonDecode(autoRes.body)['code'], equals('ERR_OWNER_ALREADY_BOOTSTRAPPED'));
      } finally {
        await ctx.ioServer.close(force: true);
        await ctx.server.stop();
        await ctx.wq.drain();
        await ctx.db.close();
      }
    });
  });

  group('Installer Auto-TLS Provisioning (mms_installer_engine.ps1)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('mms_zt_installer_tls_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    Directory createSandboxStaging(String name) {
      final staging = Directory(p.join(tempDir.path, '${name}_staging'));
      Directory(p.join(staging.path, 'client')).createSync(recursive: true);
      Directory(p.join(staging.path, 'hub_bin')).createSync(recursive: true);
      Directory(p.join(staging.path, 'hub_scripts')).createSync(recursive: true);

      // Minimal valid PE header ('MZ') for Test-IsPeBinary
      final peStub = <int>[0x4D, 0x5A, 0x90, 0x00, 0x03, 0x00, 0x00, 0x00];
      File(p.join(staging.path, 'client', 'market_pos.exe'))
          .writeAsBytesSync(peStub);
      File(p.join(staging.path, 'client', 'flutter_windows.dll'))
          .writeAsBytesSync(peStub);
      File(p.join(staging.path, 'hub_bin', 'mms_backend.exe'))
          .writeAsBytesSync(peStub);
      File(p.join(staging.path, 'hub_bin', 'sqlite3.dll'))
          .writeAsBytesSync(peStub);
      File(p.join(staging.path, 'hub_bin', 'MarketMMSService.exe'))
          .writeAsBytesSync(peStub);
      File(p.join(staging.path, 'hub_bin', 'MarketMMSService.xml'))
          .writeAsStringSync(
        File(
          p.join(
            Directory.current.path,
            'service_wrapper',
            'MarketMMSService.xml',
          ),
        ).readAsStringSync(),
      );
      File(p.join(staging.path, 'hub_bin', 'hub_config.example.json'))
          .writeAsStringSync(
        File(
          p.join(
            Directory.current.path,
            'config',
            'hub_config.example.json',
          ),
        ).readAsStringSync(),
      );
      File(p.join(staging.path, 'hub_scripts', 'setup_service_acls.ps1'))
          .writeAsStringSync('# synthetic acl script\n');
      File(p.join(staging.path, 'hub_scripts', 'configure_hub_firewall.ps1'))
          .writeAsStringSync('# synthetic fw script\n');
      return staging;
    }

    String sha256File(File f) =>
        sha256.convert(f.readAsBytesSync()).toString().toUpperCase();

    for (final useDotNetOnly in [false, true]) {
      final label = useDotNetOnly ? '.NET X.509 fallback' : 'OpenSSL 3.x / auto';
      test('Auto-TLS üretimi ($label): geçerli X.509v3 Root CA + server.crt + server.key üretir, ca.key bırakmaz ve upgrade korur', () async {
        final staging = createSandboxStaging(useDotNetOnly ? 'dotnet' : 'auto');
        final installDir = Directory(p.join(tempDir.path, 'install_${useDotNetOnly ? 'dn' : 'os'}'));
        final dataRoot = Directory(p.join(tempDir.path, 'data_${useDotNetOnly ? 'dn' : 'os'}'));
        final engineScript = p.normalize(
          p.join(
            Directory.current.path,
            '..',
            '..',
            'installer',
            'windows',
            'scripts',
            'mms_installer_engine.ps1',
          ),
        );

        final res = await Process.run('powershell.exe', [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          engineScript,
          '-Action',
          'Install',
          '-InstallDir',
          installDir.path,
          '-ProgramDataRoot',
          dataRoot.path,
          '-StagingDir',
          staging.path,
          '-AppVersion',
          '1.0.2',
          '-TestSandboxMode',
          '-AutoGenerateTlsCerts',
          if (useDotNetOnly) '-ForceDotNetTlsGenerator',
        ]);
        expect(res.exitCode, equals(0), reason: 'STDERR: ${res.stderr}\nSTDOUT: ${res.stdout}');

        final certsDir = Directory(p.join(dataRoot.path, 'certs'));
        final caFile = File(p.join(certsDir.path, 'ca.crt'));
        final srvCrtFile = File(p.join(certsDir.path, 'server.crt'));
        final srvKeyFile = File(p.join(certsDir.path, 'server.key'));
        expect(caFile.existsSync(), isTrue);
        expect(srvCrtFile.existsSync(), isTrue);
        expect(srvKeyFile.existsSync(), isTrue);

        // ca.key kesinlikle ProgramDataRoot altında bulunmamalı
        final caKeyFiles = dataRoot
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => p.basename(f.path).toLowerCase() == 'ca.key')
            .toList();
        expect(caKeyFiles, isEmpty);

        // Katı X.509v3 doğrulaması + 127.0.0.1 SAN + SecurityContext yükleme
        final caValidated = CertificateManager.validateRootCaBytes(
          caFile.readAsBytesSync(),
        );
        expect(caValidated.canonical.sha256Hex.length, equals(64));

        final sanIps = CertificateManager.extractServerCertSanIpv4s(
          srvCrtFile.readAsBytesSync(),
        );
        expect(sanIps, contains('127.0.0.1'));

        final secCtx = CertificateManager.createServerSecurityContext(
          certChainPath: srvCrtFile.path,
          privateKeyPath: srvKeyFile.path,
        );
        expect(secCtx, isNotNull);

        // hub_config.json tls.enabled = true olmalı
        final hubCfg = jsonDecode(
          File(p.join(dataRoot.path, 'config', 'hub_config.json'))
              .readAsStringSync(),
        ) as Map<String, dynamic>;
        expect((hubCfg['tls'] as Map)['enabled'], isTrue);

        // Mevcut sertifikalar upgrade sırasında kesinlikle korunmalı
        final caHashBefore = sha256File(caFile);
        final srvCrtHashBefore = sha256File(srvCrtFile);
        final srvKeyHashBefore = sha256File(srvKeyFile);

        final upgradeRes = await Process.run('powershell.exe', [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          engineScript,
          '-Action',
          'Upgrade',
          '-InstallDir',
          installDir.path,
          '-ProgramDataRoot',
          dataRoot.path,
          '-StagingDir',
          staging.path,
          '-AppVersion',
          '1.0.3',
          '-TestSandboxMode',
          '-AutoGenerateTlsCerts',
          if (useDotNetOnly) '-ForceDotNetTlsGenerator',
        ]);
        expect(upgradeRes.exitCode, equals(0), reason: 'STDERR: ${upgradeRes.stderr}');
        expect(sha256File(caFile), equals(caHashBefore));
        expect(sha256File(srvCrtFile), equals(srvCrtHashBefore));
        expect(sha256File(srvKeyFile), equals(srvKeyHashBefore));
      });
    }
  });
}
