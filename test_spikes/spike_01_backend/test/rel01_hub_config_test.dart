import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/config/hub_config.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/certificate_manager.dart';
import '../lib/security/pepper_manager.dart';

/// REL-01: Windows Hub yapılandırması tek doğrulanmış kaynaktan (hub_config.json) okunur.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mms_rel01_');
    await File(p.join(dir.path, 'server.crt')).writeAsString('crt');
    await File(p.join(dir.path, 'server.key')).writeAsString('key');
    await File(p.join(dir.path, 'ca.crt')).writeAsString('ca');
  });

  tearDown(() => dir.delete(recursive: true));

  Map<String, dynamic> productionConfig() => {
        'environment': 'production',
        'port': 8945,
        'discovery_port': 8946,
        'enable_discovery': true,
        'db_path': 'data/market_master.db',
        'backup_dir': 'backups',
        'pepper_file': 'security/pepper.dpapi',
        'admin_secret_file': 'security/admin_secret.txt',
        'tls': {'enabled': true, 'cert': 'server.crt', 'key': 'server.key', 'ca_cert': 'ca.crt'},
        'tenant_id': 'tenant-1',
        'store_id': 'store-1',
        'hub_id': 'MMS-HUB-01',
        'require_tenant_store_headers': true,
      };

  Future<File> write(Map<String, dynamic> json) async {
    final f = File(p.join(dir.path, 'hub_config.json'));
    await f.writeAsString(jsonEncode(json));
    return f;
  }

  test('Geçerli üretim yapılandırması okunur; göreli yollar config dizinine göre çözülür', () async {
    final cfg = HubConfig.load(await write(productionConfig()));
    expect(cfg.port, 8945);
    expect(cfg.discoveryPort, 8946);
    expect(cfg.enableTls, isTrue);
    expect(cfg.dbPath, p.normalize(p.join(dir.path, 'data/market_master.db')));
    expect(cfg.certPath, p.normalize(p.join(dir.path, 'server.crt')));
    expect(cfg.requireTenantStoreHeaders, isTrue);
    expect(cfg.tenantId, 'tenant-1');
  });

  test('PAIR-CA: Üretimde eşleştirme kök CA sertifikası (tls.ca_cert) zorunlu ve çözülür', () async {
    final cfg = HubConfig.load(await write(productionConfig()));
    expect(cfg.caCertPath, p.normalize(p.join(dir.path, 'ca.crt')));

    final missingKey = productionConfig()
      ..['tls'] = {'enabled': true, 'cert': 'server.crt', 'key': 'server.key'};
    expect(
      () async => HubConfig.load(await write(missingKey)),
      throwsA(isA<HubConfigException>().having((e) => e.message, 'message', contains('ca_cert'))),
    );

    final missingFile = productionConfig()
      ..['tls'] = {'enabled': true, 'cert': 'server.crt', 'key': 'server.key', 'ca_cert': 'yok_ca.crt'};
    expect(() async => HubConfig.load(await write(missingFile)), throwsA(isA<HubConfigException>()));
  });

  test('PAIR-CA: Geliştirme ortamında tls.ca_cert isteğe bağlıdır (geriye uyumlu)', () async {
    final dev = productionConfig()
      ..['environment'] = 'development'
      ..['tls'] = {'enabled': false};
    final cfg = HubConfig.load(await write(dev));
    expect(cfg.caCertPath, isNull);
  });

  test('PAIR-CA: Hub main() kök CA yolunu sunucuya geçirir (QR parmak izi ve /pairing/ca-cert)', () {
    final src = File(p.join(Directory.current.path, 'bin', 'server.dart')).readAsStringSync();
    expect(src, contains('caCertPath: startup.caCertPath'));
    expect(src, isNot(contains("Platform.environment['ROOT_CA_CERT_FILE']")));
  });

  test('ADR-015: tls nesnesindeki bilinmeyen anahtarlar (yazım hatası) reddedilir', () async {
    final json = productionConfig()
      ..['tls'] = {'enabled': true, 'cert': 'server.crt', 'key': 'server.key', 'ca_crt': 'ca.crt'};
    expect(
      () async => HubConfig.load(await write(json)),
      throwsA(isA<HubConfigException>().having((e) => e.message, 'message', contains('ca_crt'))),
    );
  });

  test('ADR-015: --config modunda ROOT_CA_CERT_FILE ortam değişkenine fallback yapılmaz', () async {
    final devWithoutCa = {
      'environment': 'development',
      'port': 8945,
      'discovery_port': 8946,
      'db_path': 'data/market_master.db',
      'tls': {'enabled': false},
      'require_tenant_store_headers': false,
    };
    final cfgFile = await write(devWithoutCa);
    final envCaPath = p.join(dir.path, 'ca.crt');

    final resolved = resolveHubStartupConfig(
      ['--config=${cfgFile.path}'],
      environment: {'ROOT_CA_CERT_FILE': envCaPath, 'PORT': '9999'},
    );
    expect(resolved.caCertPath, isNull,
        reason: '--config tek yapılandırma kaynağıdır; ROOT_CA_CERT_FILE sızmamalı');
    expect(resolved.port, 8945);

    // Geliştirme (bayraklı/env) modunda geriye dönük uyumluluk korunur.
    final devFromEnv = resolveHubStartupConfig(
      const <String>[],
      environment: {'ROOT_CA_CERT_FILE': envCaPath, 'PORT': '8955'},
    );
    expect(devFromEnv.caCertPath, envCaPath);
    expect(devFromEnv.port, 8955);

    final devFromFlag = resolveHubStartupConfig(
      ['--ca-cert=$envCaPath'],
      environment: const <String, String>{},
    );
    expect(devFromFlag.caCertPath, envCaPath);
  });

  test('ADR-015: Pairing uçları ortam değişkeni fallbacki kullanmaz ve TLS aktifken eksik CA dosyasında fail-closed (503) döner', () async {
    final caKey = p.join(dir.path, 'real_ca.key');
    final caCrt = p.join(dir.path, 'real_ca.crt');
    final srvKey = p.join(dir.path, 'real_srv.key');
    final srvCrt = p.join(dir.path, 'real_srv.crt');
    CertificateManager.generateRootCa(caKeyPath: caKey, caCertPath: caCrt);
    CertificateManager.generateServerCertificate(
      caKeyPath: caKey,
      caCertPath: caCrt,
      serverKeyPath: srvKey,
      serverCertPath: srvCrt,
    );

    final dbFile = File(p.join(dir.path, 'master.db'));
    final db = SpikeDatabase(dbFile);
    final pepper = PepperManager(File(p.join(dir.path, 'pepper.dpapi')))..initialize();
    const adminSecret = 'rel01_admin_secret_test';
    final missingCaPath = p.join(dir.path, 'missing_ca.crt');

    final secCtx = CertificateManager.createServerSecurityContext(
      certChainPath: srvCrt,
      privateKeyPath: srvKey,
    );
    final server = SpikeServer(
      db: db,
      dbFile: dbFile,
      writeQueue: WriteQueue(),
      backupDirectory: p.join(dir.path, 'backups'),
      adminSecret: adminSecret,
      pepperManager: pepper,
      securityContext: secCtx,
      requireTls: true,
      caCertPath: missingCaPath,
    );
    final sock = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = sock.port;
    await sock.close();
    await server.start(address: InternetAddress.loopbackIPv4, port: port, enableDiscovery: false);
    addTearDown(() async {
      await server.stop();
    });

    final client = HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..badCertificateCallback = (_, __, ___) => true;
    addTearDown(() => client.close(force: true));

    // 1. requireTls=true + CA dosyası yok => /pairing/session 503 fail-closed (UNKNOWN dönmemeli)
    final reqSession = await client.postUrl(Uri.parse('https://127.0.0.1:$port/api/v1/pairing/session'));
    reqSession.headers.set('x-mms-admin-secret', adminSecret);
    final respSession = await reqSession.close();
    final sessionBody = jsonDecode(await utf8.decoder.bind(respSession).join()) as Map<String, dynamic>;
    expect(respSession.statusCode, 503);
    expect(sessionBody['code'], 'ERR_CA_CERT_UNAVAILABLE');
    expect(sessionBody.containsKey('ca_fingerprint'), isFalse);

    // 2. /pairing/ca-cert => 404 ERR_CA_CERT_NOT_FOUND
    final reqCa = await client.getUrl(Uri.parse('https://127.0.0.1:$port/api/v1/pairing/ca-cert'));
    final respCa = await reqCa.close();
    final caBody = jsonDecode(await utf8.decoder.bind(respCa).join()) as Map<String, dynamic>;
    expect(respCa.statusCode, 404);
    expect(caBody['code'], 'ERR_CA_CERT_NOT_FOUND');

    // 3. requireTls=false (geliştirme) ve caCertPath=null => eski 'UNKNOWN' davranışı korunur
    final devDb = SpikeDatabase(File(p.join(dir.path, 'dev.db')));
    final devServer = SpikeServer(
      db: devDb,
      writeQueue: WriteQueue(),
      backupDirectory: p.join(dir.path, 'backups_dev'),
      adminSecret: adminSecret,
      pepperManager: pepper,
      requireTls: false,
      caCertPath: null,
    );
    final devSock = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final devPort = devSock.port;
    await devSock.close();
    await devServer.start(address: InternetAddress.loopbackIPv4, port: devPort, enableDiscovery: false);
    addTearDown(() async => devServer.stop());

    final devSessionResp = await http.post(
      Uri.parse('http://127.0.0.1:$devPort/api/v1/pairing/session'),
      headers: {'x-mms-admin-secret': adminSecret},
    );
    expect(devSessionResp.statusCode, 201);
    expect((jsonDecode(devSessionResp.body) as Map)['ca_fingerprint'], 'UNKNOWN');
  });

  test('Üretimde TLS kapalıysa açılış reddedilir', () async {
    final json = productionConfig()..['tls'] = {'enabled': false};
    expect(() async => HubConfig.load(await write(json)), throwsA(isA<HubConfigException>()));
  });

  test('TLS açık ama sertifika dosyası yoksa reddedilir', () async {
    final json = productionConfig()
      ..['tls'] = {'enabled': true, 'cert': 'yok.crt', 'key': 'server.key'};
    expect(() async => HubConfig.load(await write(json)), throwsA(isA<HubConfigException>()));
  });

  test('Üretimde tenant/store başlık zorunluluğu kapatılamaz', () async {
    final json = productionConfig()..['require_tenant_store_headers'] = false;
    expect(() async => HubConfig.load(await write(json)), throwsA(isA<HubConfigException>()));
  });

  test('Geçersiz/çakışan port ve bilinmeyen anahtar (yazım hatası) reddedilir', () async {
    expect(() async => HubConfig.load(await write(productionConfig()..['port'] = 70000)),
        throwsA(isA<HubConfigException>()));
    expect(() async => HubConfig.load(await write(productionConfig()..['discovery_port'] = 8945)),
        throwsA(isA<HubConfigException>()));
    expect(() async => HubConfig.load(await write(productionConfig()..['prot'] = 1)),
        throwsA(isA<HubConfigException>()));
  });

  test('Config içinde düz metin admin secret kabul edilmez', () async {
    expect(() async => HubConfig.load(await write(productionConfig()..['admin_secret'] = 'x')),
        throwsA(isA<HubConfigException>()));
  });

  group('Depodaki dağıtım dosyaları tutarlı (REL-01)', () {
    final root = Directory.current.path; // test_spikes/spike_01_backend

    test('Tek üretim WinSW tanımı vardır ve yalnızca --config ile tek kaynağa işaret eder', () {
      final wrapperDir = Directory(p.join(root, 'service_wrapper'));
      // Spike/test servis tanımları (MMS_ENV=test_spike) üretim kurulumunda kullanılmaz.
      final xmls = wrapperDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.xml'))
          .where((f) => !f.readAsStringSync().contains('value="test_spike"'))
          .toList();
      expect(xmls.map((f) => p.basename(f.path)), ['MarketMMSService.xml']);

      final xml = xmls.single.readAsStringSync();
      final args = RegExp(r'<arguments>(.*?)</arguments>', dotAll: true).firstMatch(xml)!.group(1)!;
      expect(args.trim(), contains('--config='));
      for (final forbidden in ['--port', '--cert', '--key', '--db-path', '--admin-secret', '--tls']) {
        expect(args, isNot(contains(forbidden)), reason: '$forbidden yalnızca hub_config.json içinde olmalı');
      }
      expect(xml, contains('<user>LocalService</user>'));
    });

    test('Örnek üretim yapılandırması geçerli ve firewall varsayılan portlarıyla aynı', () async {
      final example = File(p.join(root, 'config', 'hub_config.example.json'));
      final json = jsonDecode(example.readAsStringSync()) as Map<String, dynamic>;
      // Sertifikalar kurulumda üretilir; yapısal doğrulama için geçici dosyalarla yükle.
      final tlsJson = Map<String, dynamic>.from(json['tls'] as Map)
        ..['cert'] = 'server.crt'
        ..['key'] = 'server.key'
        ..['ca_cert'] = 'ca.crt';
      expect((json['tls'] as Map)['ca_cert'], '../certs/ca.crt', reason: 'şablon kök CA yolunu içermeli');
      final cfg = HubConfig.load(await write({...json, 'tls': tlsJson}));
      expect(cfg.environment, 'production');
      expect(cfg.enableTls, isTrue);

      final firewall = File(p.join(root, '..', '..', 'scripts', 'configure_hub_firewall.ps1')).readAsStringSync();
      expect(firewall, contains('[int]\$TcpPort = ${cfg.port}'));
      expect(firewall, contains('[int]\$UdpPort = ${cfg.discoveryPort}'));
      // Varsayılan profil Private ve yalnızca yerel alt ağ (Public/Internet erişimi yok).
      expect(firewall, contains('[string]\$Profile = "Private"'));
      expect(firewall, contains('[string]\$RemoteAddress = "LocalSubnet"'));
      expect(RegExp(r'-RemoteAddress \$remoteList').allMatches(firewall).length, 2,
          reason: 'hem yeni kural hem güncellenen kural uzak adresi sınırlamalı');
    });

    test('PowerShell betikleri Windows PowerShell 5.1 ile doğru okunur (yalnızca ASCII veya UTF-8 BOM)', () {
      // Windows PowerShell 5.1 BOM'suz dosyayı ANSI (cp1252/1254) okur. UTF-8 "—" (E2 80 94)
      // baytlarındaki 0x94 bu kod sayfasında "”" (akıllı tırnak) olur ve PowerShell onu string
      // sonlandırıcı sayar → betik AYRIŞTIRILAMAZ (ACL/kaldırma betikleri çalışmaz).
      final dirs = [Directory(p.join(root, 'scripts')), Directory(p.join(root, '..', '..', 'scripts'))];
      final offenders = <String>[];
      var checked = 0;
      for (final dir in dirs) {
        for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.ps1'))) {
          checked++;
          final bytes = f.readAsBytesSync();
          final hasBom = bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF;
          if (!hasBom && bytes.any((b) => b > 0x7F)) offenders.add(p.basename(f.path));
        }
      }
      expect(checked, greaterThanOrEqualTo(7));
      expect(offenders, isEmpty, reason: 'BOM eklenmeli veya ASCII olmalı: $offenders');
    });

    test('Kurulum betiği güncellemede servisi ikilileri kopyalamadan ÖNCE durdurur ve geri dönüş sağlar', () {
      final s = File(p.join(root, 'scripts', 'install_mms_service.ps1')).readAsStringSync();
      final stopIdx = s.indexOf('Stop-AndRemoveMmsService -WrapperExe \$deployedWrapperExe');
      final copyIdx = s.indexOf('Copy-Item -Path \$backendExeSrc -Destination \$deployedBackendExe');
      final tlsIdx = s.indexOf('TLS sertifikasi bulunamadi');
      expect(stopIdx, greaterThan(0));
      expect(copyIdx, greaterThan(stopIdx), reason: 'çalışan exe kilitlidir; önce durdurulmalı');
      expect(tlsIdx, lessThan(stopIdx), reason: 'eksik sertifika çalışan servisi durdurmadan yakalanmalı');
      expect(s, contains('bin.previous'));
      expect(s, contains(r'certs\ca.crt'), reason: 'kurulum, eşleştirme kök CA sertifikası yoksa durmalı');
      expect(s, contains('[ROLLBACK]'));
      expect(s, contains(r'if ($LASTEXITCODE -ne 0) { throw "HATA: WinSW install basarisiz'));
      expect(s, isNot(contains('Remove-Item -Recurse -Force \$configDir')));

      // Dart 3.13 native asset sqlite3.dll kurulumu, rollback ve admin_secret.txt :R ACL kilidi
      expect(s, contains('sqlite3.dll'));
      expect(s, contains(r'$deployedBinLibSqliteDll'));
      expect(s, contains(r'$deployedRootLibSqliteDll'));
      expect(s, contains(r'$prevSqlite'));
      expect(s, contains(r'${sidSvc}:R'));

      final aclScript = File(p.join(root, 'scripts', 'setup_service_acls.ps1')).readAsStringSync();
      expect(aclScript, contains('"lib"'));
      expect(aclScript, contains(r'$BaseDir\lib'));
      expect(aclScript, contains(r'$BaseDir\security'));
      expect(aclScript, contains('"M" { "(OI)(CI)M" }'));
      expect(aclScript, contains(r'${sidTarget}:${svcSpec}'));
      expect(aclScript, contains('[System.Security.AccessControl.FileSystemRights]::Modify'));
    });

    test('ADR-015 H-3 & M-1: --config ile başlatılan başlangıç akışı ADMIN_SECRET ve ROOT_CA_CERT_FILE env sızıntısını reddeder; eksik backup_dir System32 yerine config/backups olur', () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final sock = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = sock.port;
      await sock.close();
      final discSock = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final discPort = discSock.port;
      discSock.close();

      final cfgJson = {
        'environment': 'development',
        'port': port,
        'discovery_port': discPort,
        'enable_discovery': false,
        'db_path': 'data/master.db',
        'pepper_file': 'security/pepper.dpapi',
        'admin_secret_file': 'security/missing_admin.txt',
        'tls': {'enabled': false},
        'require_tenant_store_headers': false,
        'backup_schedule': {'interval_hours': 0},
      };
      final configFile = await write(cfgJson);
      final cfg = HubConfig.load(configFile);
      expect(cfg.backupDir, p.normalize(p.join(dir.path, 'backups')));

      final server = await startHubFromArgs(
        ['--config=${configFile.path}'],
        environment: {
          'ADMIN_SECRET': 'leaked_env_admin_secret',
          'ROOT_CA_CERT_FILE': p.join(dir.path, 'ca.crt'),
        },
      );
      try {
        expect(server.allowAdminEnvFallback, isFalse);
        expect(server.caCertPath, isNull);
        expect(server.backupDirectory, p.normalize(p.join(dir.path, 'backups')));

        final revokeResp = await http.post(
          Uri.parse('http://127.0.0.1:$port/api/v1/devices/revoke'),
          headers: {'x-mms-admin-secret': 'leaked_env_admin_secret', 'content-type': 'application/json'},
          body: jsonEncode({'device_id': 'D1'}),
        );
        expect(revokeResp.statusCode, 503,
            reason: '--config modunda env ADMIN_SECRET kabul edilmemeli (fail-closed 503)');

        final sessionResp = await http.post(
          Uri.parse('http://127.0.0.1:$port/api/v1/pairing/session'),
          headers: {'x-mms-admin-secret': 'leaked_env_admin_secret'},
        );
        expect(sessionResp.statusCode, 503);
      } finally {
        await server.stop();
        await server.db.close();
      }
    });
  });
}
