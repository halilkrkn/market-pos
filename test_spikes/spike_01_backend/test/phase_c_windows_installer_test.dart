@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/pepper_manager.dart';

/// Bölüm 5.10 — PHASE C Windows Installer Kapsamlı Otomatik Test Paketi.
///
/// KURAL: Gerçek `%ProgramData%\MarketMMS`, gerçek `%ProgramFiles%`, gerçek SCM
/// veya `MarketMmsSpike01` servisine KESİNLİKLE dokunulmaz. Tüm dosya/ACL/upgrade/
/// rollback/uninstall/health/MSI doğrulamaları izole `Directory.systemTemp`
/// dizinlerinde, sentetik ikililer + gerçek `icacls` + gerçek `WindowsInstaller.Installer`
/// + izole loopback `SpikeServer` ile çalıştırılır.
void main() {
  final repoRoot = Directory(p.normalize(p.join(Directory.current.path, '..', '..'))).absolute.path;
  final engineScript = p.join(repoRoot, 'installer', 'windows', 'scripts', 'mms_installer_engine.ps1');
  final buildScript = p.join(repoRoot, 'scripts', 'build_windows_installer.ps1');

  late Directory tempRoot;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    configureSqliteNative();
  });

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('mms_phasec_inst_test_');
  });

  tearDown(() async {
    if (tempRoot.existsSync()) {
      try {
        tempRoot.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Directory createSyntheticStaging(String tag, {bool omitFlutterDll = false}) {
    final stage = Directory(p.join(tempRoot.path, 'staging_$tag'));
    final client = Directory(p.join(stage.path, 'client'))..createSync(recursive: true);
    final hubBin = Directory(p.join(stage.path, 'hub_bin'))..createSync(recursive: true);
    final hubScripts = Directory(p.join(stage.path, 'hub_scripts'))..createSync(recursive: true);

    File(p.join(client.path, 'market_pos.exe')).writeAsStringSync('CLIENT_$tag');
    if (!omitFlutterDll) {
      File(p.join(client.path, 'flutter_windows.dll')).writeAsStringSync('FLUTTER_$tag');
    }
    File(p.join(hubBin.path, 'mms_backend.exe')).writeAsStringSync('HUB_$tag');
    File(p.join(hubBin.path, 'sqlite3.dll')).writeAsStringSync('SQLITE_$tag');
    File(p.join(hubBin.path, 'MarketMMSService.exe')).writeAsStringSync('WINSW_$tag');
    File(p.join(hubBin.path, 'MarketMMSService.xml')).writeAsStringSync(
      File(p.join(repoRoot, 'test_spikes', 'spike_01_backend', 'service_wrapper', 'MarketMMSService.xml'))
          .readAsStringSync(),
    );
    File(p.join(hubBin.path, 'hub_config.example.json')).writeAsStringSync(
      File(p.join(repoRoot, 'test_spikes', 'spike_01_backend', 'config', 'hub_config.example.json'))
          .readAsStringSync(),
    );
    File(engineScript).copySync(p.join(hubScripts.path, 'mms_installer_engine.ps1'));
    return stage;
  }

  void seedSyntheticCerts(Directory programDataRoot) {
    final certs = Directory(p.join(programDataRoot.path, 'certs'))..createSync(recursive: true);
    File(p.join(certs.path, 'ca.crt')).writeAsStringSync('SYNTHETIC_CA_CERT');
    File(p.join(certs.path, 'server.crt')).writeAsStringSync('SYNTHETIC_SERVER_CERT');
    File(p.join(certs.path, 'server.key')).writeAsStringSync('SYNTHETIC_SERVER_KEY');
  }

  Future<ProcessResult> runPsFile(String scriptPath, List<String> args) {
    return Process.run(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, ...args],
      workingDirectory: repoRoot,
    );
  }

  Future<ProcessResult> runEngine({
    required String action,
    required Directory installDir,
    required Directory programDataRoot,
    Directory? stagingDir,
    String appVersion = '1.0.0',
    String serviceName = 'MarketMMSService',
    String faultInjection = 'None',
    String? healthCheckUrl,
    bool purgeUserData = false,
    String confirmPurgeToken = '',
    bool allowDeferredTlsStart = true,
    List<String> simulatedExistingServices = const [],
  }) {
    final args = <String>[
      '-Action', action,
      '-InstallDir', installDir.path,
      '-ProgramDataRoot', programDataRoot.path,
      if (stagingDir != null) ...['-StagingDir', stagingDir.path],
      '-AppVersion', appVersion,
      '-ServiceName', serviceName,
      '-TestSandboxMode',
      '-FaultInjectionStage', faultInjection,
      '-AllowDeferredTlsStart', allowDeferredTlsStart ? '1' : '0',
      if (healthCheckUrl != null) ...['-HealthCheckUrl', healthCheckUrl],
      if (purgeUserData) '-PurgeUserData',
      if (confirmPurgeToken.isNotEmpty) ...['-ConfirmPurgeToken', confirmPurgeToken],
      if (simulatedExistingServices.isNotEmpty) ...[
        '-SimulatedExistingServices',
        simulatedExistingServices.join(','),
      ],
    ];
    return runPsFile(engineScript, args);
  }

  group('PHASE C — Windows Installer (WiX MSI + Sandbox Lifecycle)', () {
    test('1 & 2. WiX MSI paket üretimi, SHA-256 doğrulaması ve MSI tablo/içerik denetimi', () async {
      final msiStage = Directory(p.join(tempRoot.path, 'msi_stage'));
      final msiOut = Directory(p.join(tempRoot.path, 'msi_out'));
      final res = await runPsFile(buildScript, [
        '-SyntheticStagingForTest',
        '-StagingDir', msiStage.path,
        '-OutputDir', msiOut.path,
        '-OverrideVersion', '1.0.0',
      ]);
      expect(res.exitCode, equals(0), reason: '${res.stdout}\n${res.stderr}');

      final msiFile = File(p.join(msiOut.path, 'MarketMMS-Setup-1.0.0-x64.msi'));
      expect(msiFile.existsSync(), isTrue);
      expect(msiFile.lengthSync(), greaterThan(30000));

      final sumsFile = File(p.join(msiOut.path, 'SHA256SUMS.txt'));
      expect(sumsFile.existsSync(), isTrue);
      expect(sumsFile.readAsStringSync().toUpperCase(), contains('MARKETMMS-SETUP-1.0.0-X64.MSI'));

      // Windows Installer COM üzerinden gerçek MSI veritabanı tablolarını denetle
      final inspectScript = '''
\$installer = New-Object -ComObject WindowsInstaller.Installer
\$db = \$installer.GetType().InvokeMember("OpenDatabase", "InvokeMethod", \$null, \$installer, @("${msiFile.path.replaceAll('\\', '\\\\')}", 0))
function Read-Table(\$sql, [int]\$colCount) {
  \$view = \$db.GetType().InvokeMember("OpenView", "InvokeMethod", \$null, \$db, @(\$sql))
  [void]\$view.GetType().InvokeMember("Execute", "InvokeMethod", \$null, \$view, \$null)
  \$rows = New-Object System.Collections.Generic.List[string]
  while (\$true) {
    \$rec = \$view.GetType().InvokeMember("Fetch", "InvokeMethod", \$null, \$view, \$null)
    if (\$null -eq \$rec) { break }
    \$cols = @()
    for (\$i = 1; \$i -le \$colCount; \$i++) {
      \$val = \$rec.GetType().InvokeMember("StringData", "GetProperty", \$null, \$rec, @([int]\$i))
      \$cols += [string]\$val
    }
    \$rows.Add((\$cols -join '|'))
  }
  [void]\$view.GetType().InvokeMember("Close", "InvokeMethod", \$null, \$view, \$null)
  return \$rows.ToArray()
}
\$out = [ordered]@{
  properties = @(Read-Table "SELECT Property, Value FROM Property" 2)
  upgrades = @(Read-Table "SELECT UpgradeCode, VersionMin, VersionMax FROM Upgrade" 3)
  custom_actions = @(Read-Table "SELECT Action, Type, Target FROM CustomAction" 3)
  shortcuts = @(Read-Table "SELECT Shortcut, Name, Target FROM Shortcut" 3)
  files = @(Read-Table "SELECT File, FileName FROM File" 2)
}
\$out | ConvertTo-Json -Depth 4
''';
      final inspectRes = await Process.run('powershell.exe', ['-NoProfile', '-Command', inspectScript]);
      expect(inspectRes.exitCode, equals(0), reason: '${inspectRes.stdout}\n${inspectRes.stderr}');

      final msiData = jsonDecode(inspectRes.stdout as String) as Map<String, dynamic>;
      final props = List<String>.from(msiData['properties'] as List);
      expect(props, contains('ProductVersion|1.0.0'));
      expect(props, contains('UpgradeCode|{8F4E2D1A-6C7B-4E93-A521-9D3C0478B6E2}'));
      expect(props, contains('PURGE_USER_DATA|0'));
      expect(props, contains('ALLOW_DEFERRED_TLS_START|1'));

      final customActions = List<String>.from(msiData['custom_actions'] as List).join('\n');
      expect(customActions, contains('CA_InstallOrUpgrade'));
      expect(customActions, contains('CA_RollbackInstall'));
      expect(customActions, contains('CA_Uninstall'));

      final shortcuts = List<String>.from(msiData['shortcuts'] as List).join('\n');
      expect(shortcuts, matches(RegExp(r'StartMenuShortcut\|([^|\r\n]*\|)?Market MMS\|\[ClientFolder\]market_pos\.exe')));
      expect(shortcuts, matches(RegExp(r'DesktopShortcut\|([^|\r\n]*\|)?Market MMS\|\[ClientFolder\]market_pos\.exe')));

      final files = List<String>.from(msiData['files'] as List).join('\n').toLowerCase();
      for (final required in [
        'market_pos.exe',
        'flutter_windows.dll',
        'mms_backend.exe',
        'marketmmsservice.exe',
        'marketmmsservice.xml',
        'sqlite3.dll',
        'mms_installer_engine.ps1',
      ]) {
        expect(files, contains(required), reason: 'MSI File tablosunda $required bulunmalı');
      }
    });

    test('3, 4 & 5. İlk kurulum, ProgramData dizinleri, servis config, NTFS ACL ve güvenlik doğrulaması', () async {
      final installDir = Directory(p.join(tempRoot.path, 'ProgramFiles', 'MarketMMS'));
      final dataRoot = Directory(p.join(tempRoot.path, 'ProgramData', 'MarketMMS'));
      final stage = createSyntheticStaging('v100');
      seedSyntheticCerts(dataRoot);

      final res = await runEngine(
        action: 'Install',
        installDir: installDir,
        programDataRoot: dataRoot,
        stagingDir: stage,
        appVersion: '1.0.0',
      );
      expect(res.exitCode, equals(0), reason: '${res.stdout}\n${res.stderr}');

      final manifest = jsonDecode(res.stdout as String) as Map<String, dynamic>;
      expect(manifest['app_version'], equals('1.0.0'));
      expect(manifest['mode'], equals('FreshInstall'));
      expect(manifest['service_state'], equals('RUNNING'));

      for (final sub in ['bin', 'bin\\lib', 'lib', 'config', 'certs', 'data', 'security', 'logs', 'backups', 'run']) {
        expect(Directory(p.join(dataRoot.path, sub)).existsSync(), isTrue);
      }
      expect(File(p.join(installDir.path, 'client', 'market_pos.exe')).existsSync(), isTrue);
      expect(File(p.join(dataRoot.path, 'bin', 'mms_backend.exe')).existsSync(), isTrue);
      expect(File(p.join(dataRoot.path, 'bin', 'sqlite3.dll')).existsSync(), isTrue);
      expect(File(p.join(dataRoot.path, 'lib', 'sqlite3.dll')).existsSync(), isTrue);
      expect(File(p.join(dataRoot.path, 'config', 'hub_config.json')).existsSync(), isTrue);

      final xmlContent = File(p.join(dataRoot.path, 'bin', 'MarketMMSService.xml')).readAsStringSync();
      expect(xmlContent, contains('<user>LocalService</user>'));
      expect(xmlContent, contains('<stoptimeout>15 sec</stoptimeout>'));

      final adminSecretFile = File(p.join(dataRoot.path, 'security', 'admin_secret.txt'));
      expect(adminSecretFile.existsSync(), isTrue);
      final secretVal = adminSecretFile.readAsStringSync();
      expect(secretVal.length, greaterThanOrEqualTo(32));
      expect('${res.stdout}\n${res.stderr}', isNot(contains(secretVal)),
          reason: 'Admin secret kurulum loglarına yazılmamalıdır.');

      // Gerçek NTFS ACL doğrulaması (Users / Everyone erişimi kaldırılmış olmalı)
      final icaclsOut = await Process.run('icacls', [p.join(dataRoot.path, 'security')]);
      expect(icaclsOut.exitCode, equals(0));
      final aclText = icaclsOut.stdout as String;
      expect(aclText, isNot(contains('BUILTIN\\Users')));
      expect(aclText, isNot(contains('Everyone')));
      expect(aclText, isNot(contains('Authenticated Users')));

      // ca.key varsa kurulum ERR_SECURITY_VIOLATION (72) ile fail-closed durmalıdır
      File(p.join(dataRoot.path, 'certs', 'ca.key')).writeAsStringSync('FORBIDDEN_CA_KEY');
      final caKeyRes = await runEngine(
        action: 'VerifyPrerequisites',
        installDir: installDir,
        programDataRoot: dataRoot,
        stagingDir: stage,
      );
      expect(caKeyRes.exitCode, equals(72));
      expect('${caKeyRes.stderr}', contains('ERR_SECURITY_VIOLATION'));
    });

    test('6, 7 & 8. Aynı sürüm tekrar kurulumu, v1.0.0 -> v1.1.0 Upgrade, downgrade reddi ve başarısız upgrade rollback', () async {
      final installDir = Directory(p.join(tempRoot.path, 'ProgramFiles', 'MarketMMS'));
      final dataRoot = Directory(p.join(tempRoot.path, 'ProgramData', 'MarketMMS'));
      final stage10 = createSyntheticStaging('v100');
      final stage11 = createSyntheticStaging('v110');
      seedSyntheticCerts(dataRoot);

      // v1.0.0 kur
      final install10 = await runEngine(
        action: 'Install',
        installDir: installDir,
        programDataRoot: dataRoot,
        stagingDir: stage10,
        appVersion: '1.0.0',
      );
      expect(install10.exitCode, equals(0), reason: '${install10.stderr}');

      // Sentetik DB + özelleştirilmiş config + DPAPI sırları oluştur
      final dbFile = File(p.join(dataRoot.path, 'data', 'market_master.db'));
      final db = SpikeDatabase(dbFile);
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'prod_upgrade_keep',
              barcode: '8690123456789',
              name: 'Korunan Ürün',
              price: 4990,
              stock: 5000,
            ),
          );
      await db.close();

      final cfgFile = File(p.join(dataRoot.path, 'config', 'hub_config.json'));
      final customCfg = cfgFile.readAsStringSync();
      final originalSecret = File(p.join(dataRoot.path, 'security', 'admin_secret.txt')).readAsStringSync();
      File(p.join(dataRoot.path, 'security', 'pepper.dpapi')).writeAsBytesSync([1, 2, 3, 4]);
      File(p.join(dataRoot.path, 'security', 'backup_recovery_key.dpapi')).writeAsBytesSync([5, 6, 7, 8]);
      File(p.join(dataRoot.path, 'security', 'backup_drive_oauth.dpapi')).writeAsBytesSync([9, 10, 11, 12]);

      // 6. Aynı sürüm tekrar kurulum (Repair): mevcut config, secret, DB ve DPAPI dosyaları ezilmez
      final repair = await runEngine(
        action: 'Install',
        installDir: installDir,
        programDataRoot: dataRoot,
        stagingDir: stage10,
        appVersion: '1.0.0',
      );
      expect(repair.exitCode, equals(0), reason: '${repair.stderr}');
      expect((jsonDecode(repair.stdout as String) as Map)['mode'], equals('Repair'));
      expect(cfgFile.readAsStringSync(), equals(customCfg));
      expect(File(p.join(dataRoot.path, 'security', 'admin_secret.txt')).readAsStringSync(), equals(originalSecret));

      // 8a. Başarısız Upgrade Rollback (v1.0.0 -> v1.1.0 Migration/HealthCheck/UpgradeInterrupt hatası)
      for (final stageFault in ['UpgradeInterrupt', 'Migration', 'HealthCheck']) {
        final failedUpgrade = await runEngine(
          action: 'Install',
          installDir: installDir,
          programDataRoot: dataRoot,
          stagingDir: stage11,
          appVersion: '1.1.0',
          faultInjection: stageFault,
        );
        expect(failedUpgrade.exitCode, equals(74));
        expect(File(p.join(dataRoot.path, 'bin', 'mms_backend.exe')).readAsStringSync(), equals('HUB_v100'),
            reason: '$stageFault hatası sonrası 1.0.0 ikililerine geri dönülmelidir.');
        expect(File(p.join(installDir.path, 'client', 'market_pos.exe')).readAsStringSync(), equals('CLIENT_v100'));
        final manifestAfterRb = jsonDecode(File(p.join(dataRoot.path, 'config', 'install_manifest.json')).readAsStringSync()) as Map;
        expect(manifestAfterRb['app_version'], equals('1.0.0'));
        final scmAfterRb = jsonDecode(File(p.join(dataRoot.path, 'run', 'sandbox_scm.json')).readAsStringSync()) as Map;
        expect(scmAfterRb['status'], equals('Running'));
      }

      // 7. Başarılı Upgrade v1.0.0 -> v1.1.0
      final upgrade = await runEngine(
        action: 'Install',
        installDir: installDir,
        programDataRoot: dataRoot,
        stagingDir: stage11,
        appVersion: '1.1.0',
      );
      expect(upgrade.exitCode, equals(0), reason: '${upgrade.stderr}');
      final upgManifest = jsonDecode(upgrade.stdout as String) as Map<String, dynamic>;
      expect(upgManifest['mode'], equals('Upgrade'));
      expect(upgManifest['app_version'], equals('1.1.0'));
      expect(upgManifest['pre_upgrade_backup_path'], isNotNull);
      expect(File(upgManifest['pre_upgrade_backup_path'] as String).existsSync(), isTrue);
      expect(File(p.join(dataRoot.path, 'bin', 'mms_backend.exe')).readAsStringSync(), equals('HUB_v110'));
      expect(File(p.join(installDir.path, 'client', 'market_pos.exe')).readAsStringSync(), equals('CLIENT_v110'));
      expect(File(p.join(dataRoot.path, 'security', 'pepper.dpapi')).readAsBytesSync(), equals([1, 2, 3, 4]));
      expect(File(p.join(dataRoot.path, 'security', 'backup_recovery_key.dpapi')).readAsBytesSync(), equals([5, 6, 7, 8]));

      // Veritabanı verileri upgrade sonrası eksiksiz korunur
      final dbAfter = SpikeDatabase(dbFile);
      final prods = await dbAfter.select(dbAfter.products).get();
      expect(prods.map((e) => e.id).toList(), equals(['prod_upgrade_keep']));
      await dbAfter.close();

      // Downgrade 1.1.0 -> 1.0.0 reddedilir
      final downgrade = await runEngine(
        action: 'Install',
        installDir: installDir,
        programDataRoot: dataRoot,
        stagingDir: stage10,
        appVersion: '1.0.0',
      );
      expect(downgrade.exitCode, equals(73));
      expect('${downgrade.stderr}', contains('ERR_DOWNGRADE_NOT_ALLOWED'));
    });

    test('9, 10 & 11. Güvenli Uninstall, kullanıcı verisinin korunması, tekrar kurulum ve MarketMmsSpike01 koruması', () async {
      final installDir = Directory(p.join(tempRoot.path, 'ProgramFiles', 'MarketMMS'));
      final dataRoot = Directory(p.join(tempRoot.path, 'ProgramData', 'MarketMMS'));
      final stage = createSyntheticStaging('v100');
      seedSyntheticCerts(dataRoot);

      // MarketMmsSpike01 hedefi veya mevcut çalışması fail-closed 70 ile engellenir
      final spikeProtected = await runEngine(
        action: 'Install',
        installDir: installDir,
        programDataRoot: dataRoot,
        stagingDir: stage,
        serviceName: 'MarketMmsSpike01',
      );
      expect(spikeProtected.exitCode, equals(70));
      expect('${spikeProtected.stderr}', contains('ERR_PROTECTED_SERVICE_CONFLICT'));

      final spikeConflict = await runEngine(
        action: 'Install',
        installDir: installDir,
        programDataRoot: dataRoot,
        stagingDir: stage,
        simulatedExistingServices: const ['MarketMmsSpike01'],
      );
      expect(spikeConflict.exitCode, equals(70));

      // Kurulum + veri oluşturma
      final inst = await runEngine(
        action: 'Install',
        installDir: installDir,
        programDataRoot: dataRoot,
        stagingDir: stage,
      );
      expect(inst.exitCode, equals(0));
      File(p.join(dataRoot.path, 'data', 'market_master.db')).writeAsStringSync('USER_DB_BYTES');
      File(p.join(dataRoot.path, 'backups', 'bak_1.mmsbak')).writeAsStringSync('USER_BACKUP');
      File(p.join(dataRoot.path, 'security', 'pepper.dpapi')).writeAsStringSync('USER_PEPPER');

      // Yanlış/boş token ile PurgeUserData reddedilir ve veri korunur
      final badPurge = await runEngine(
        action: 'Uninstall',
        installDir: installDir,
        programDataRoot: dataRoot,
        purgeUserData: true,
        confirmPurgeToken: 'WRONG_TOKEN',
      );
      expect(badPurge.exitCode, equals(76));
      expect(File(p.join(dataRoot.path, 'data', 'market_master.db')).existsSync(), isTrue);

      // Varsayılan Uninstall: ikililer ve servis kalkar, ProgramData verisi %100 korunur
      final uninst = await runEngine(
        action: 'Uninstall',
        installDir: installDir,
        programDataRoot: dataRoot,
      );
      expect(uninst.exitCode, equals(0), reason: '${uninst.stderr}');
      final uninstJson = jsonDecode(uninst.stdout as String) as Map<String, dynamic>;
      expect(uninstJson['user_data_preserved'], isTrue);
      expect(installDir.existsSync(), isFalse);
      expect(Directory(p.join(dataRoot.path, 'bin')).existsSync(), isFalse);
      expect(File(p.join(dataRoot.path, 'run', 'sandbox_scm.json')).existsSync(), isFalse);
      expect(File(p.join(dataRoot.path, 'data', 'market_master.db')).readAsStringSync(), equals('USER_DB_BYTES'));
      expect(File(p.join(dataRoot.path, 'backups', 'bak_1.mmsbak')).existsSync(), isTrue);
      expect(File(p.join(dataRoot.path, 'security', 'pepper.dpapi')).existsSync(), isTrue);

      // Kaldırma sonrası tekrar kurulum veriyi bozmadan başarılı olur
      final reinst = await runEngine(
        action: 'Install',
        installDir: installDir,
        programDataRoot: dataRoot,
        stagingDir: stage,
      );
      expect(reinst.exitCode, equals(0));
      expect(File(p.join(dataRoot.path, 'data', 'market_master.db')).readAsStringSync(), equals('USER_DB_BYTES'));
    });

    test('12, 13 & 14. Canlı Hub Health Check, Recovery Password durumu ve tek seferlik OWNER bootstrap', () async {
      final serverDir = Directory(p.join(tempRoot.path, 'live_hub'));
      final dbFile = File(p.join(serverDir.path, 'data', 'market_master.db'));
      await dbFile.parent.create(recursive: true);
      final liveDb = SpikeDatabase(dbFile);
      final pepper = PepperManager(File(p.join(serverDir.path, 'security', 'pepper.dpapi')))
        ..initialize(overrideForTesting: 'phase_c_live_hub_pepper_32bytes!');
      final server = SpikeServer(
        db: liveDb,
        dbFile: dbFile,
        writeQueue: WriteQueue(),
        backupDirectory: p.join(serverDir.path, 'backups'),
        adminSecret: 'phasec_admin_secret_2026',
        pepperManager: pepper,
      );
      final probeSock = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probeSock.port;
      await probeSock.close();
      await server.start(address: InternetAddress.loopbackIPv4, port: port, enableDiscovery: false);
      final baseUrl = 'http://127.0.0.1:$port';

      try {
        // 12. Recovery Password yokken /health recovery_key_configured == false ve admin/backup fail-closed 412
        final hBefore = jsonDecode((await http.get(Uri.parse('$baseUrl/health'))).body) as Map<String, dynamic>;
        expect(hBefore['status'], equals('UP'));
        expect((hBefore['backup'] as Map)['recovery_key_configured'], isFalse);

        final failBackup = await http.post(
          Uri.parse('$baseUrl/api/v1/admin/backup'),
          headers: {'x-mms-admin-secret': 'phasec_admin_secret_2026', 'content-type': 'application/json'},
          body: '{}',
        );
        expect(failBackup.statusCode, equals(412));

        await server.hubRecoveryKeyStore.saveRecoveryPassword('OwnerKurulumParolasi-2026!');
        final hAfter = jsonDecode((await http.get(Uri.parse('$baseUrl/health'))).body) as Map<String, dynamic>;
        expect((hAfter['backup'] as Map)['recovery_key_configured'], isTrue);

        // 13. Tek seferlik OWNER bootstrap (OV-04): ilk çağrı OWNER döner, ikinci 409 reddedilir
        final boot1 = await http.post(
          Uri.parse('$baseUrl/api/v1/admin/owner/bootstrap'),
          headers: {'x-mms-admin-secret': 'phasec_admin_secret_2026', 'content-type': 'application/json'},
          body: jsonEncode({
            'device_id': 'POS-WIN-OWNER-01',
            'name': 'Ana Kasa Windows',
            'register_if_missing': true,
          }),
        );
        expect(boot1.statusCode, equals(200), reason: boot1.body);
        expect((jsonDecode(boot1.body) as Map)['role'], equals('OWNER'));

        final boot2 = await http.post(
          Uri.parse('$baseUrl/api/v1/admin/owner/bootstrap'),
          headers: {'x-mms-admin-secret': 'phasec_admin_secret_2026', 'content-type': 'application/json'},
          body: jsonEncode({'device_id': 'POS-WIN-OWNER-02', 'register_if_missing': true}),
        );
        expect(boot2.statusCode, equals(409));
        expect((jsonDecode(boot2.body) as Map)['code'], equals('ERR_OWNER_ALREADY_BOOTSTRAPPED'));

        // 14. Canlı Hub /health ile Installer doğrulaması
        final installDir = Directory(p.join(tempRoot.path, 'ProgramFilesLive', 'MarketMMS'));
        final dataRoot = Directory(p.join(tempRoot.path, 'ProgramDataLive', 'MarketMMS'));
        final stage = createSyntheticStaging('live');
        seedSyntheticCerts(dataRoot);
        final instLive = await runEngine(
          action: 'Install',
          installDir: installDir,
          programDataRoot: dataRoot,
          stagingDir: stage,
          healthCheckUrl: '$baseUrl/health',
        );
        expect(instLive.exitCode, equals(0), reason: '${instLive.stderr}');
        final liveManifest = jsonDecode(instLive.stdout as String) as Map<String, dynamic>;
        expect(liveManifest['health_verified'], isTrue);
        expect(liveManifest['recovery_key_configured'], isTrue);
      } finally {
        await server.stop();
      }

      // Kapalı /health ucunda installer rollback yapmalıdır
      final deadInstallDir = Directory(p.join(tempRoot.path, 'ProgramFilesDead', 'MarketMMS'));
      final deadDataRoot = Directory(p.join(tempRoot.path, 'ProgramDataDead', 'MarketMMS'));
      seedSyntheticCerts(deadDataRoot);
      final instDead = await runEngine(
        action: 'Install',
        installDir: deadInstallDir,
        programDataRoot: deadDataRoot,
        stagingDir: createSyntheticStaging('dead'),
        healthCheckUrl: 'http://127.0.0.1:$port/health',
      );
      expect(instDead.exitCode, equals(74));
      expect(File(p.join(deadDataRoot.path, 'bin', 'mms_backend.exe')).existsSync(), isFalse);
    });

    test('15 & 16. Eksik runtime kontrolü ve tüm kritik aşamalarda kullanıcı verisini koruyan rollback', () async {
      final installDir = Directory(p.join(tempRoot.path, 'ProgramFilesErr', 'MarketMMS'));
      final dataRoot = Directory(p.join(tempRoot.path, 'ProgramDataErr', 'MarketMMS'));
      final brokenStage = createSyntheticStaging('broken', omitFlutterDll: true);

      // 15. Eksik flutter_windows.dll -> ERR_MISSING_RUNTIME_ARTIFACT (71)
      final missingRes = await runEngine(
        action: 'VerifyPrerequisites',
        installDir: installDir,
        programDataRoot: dataRoot,
        stagingDir: brokenStage,
      );
      expect(missingRes.exitCode, equals(71));
      expect('${missingRes.stderr}', contains('ERR_MISSING_RUNTIME_ARTIFACT'));

      // 16. ProgramData, Acl, ServiceInstall, ServiceStart, UninstallService hata enjeksiyonları
      final validStage = createSyntheticStaging('err');
      seedSyntheticCerts(dataRoot);
      Directory(p.join(dataRoot.path, 'data')).createSync(recursive: true);
      final existingDb = File(p.join(dataRoot.path, 'data', 'market_master.db'))
        ..writeAsStringSync('CRITICAL_DATA');

      for (final fault in ['ProgramData', 'Acl', 'ServiceInstall', 'ServiceStart']) {
        final r = await runEngine(
          action: 'Install',
          installDir: installDir,
          programDataRoot: dataRoot,
          stagingDir: validStage,
          faultInjection: fault,
        );
        expect(r.exitCode, equals(74), reason: '$fault rollback ile 74 dönmeli');
        expect(existingDb.readAsStringSync(), equals('CRITICAL_DATA'),
            reason: '$fault rollback kullanıcı verisini silmemeli');
      }

      // Uninstall sırasında servis hatası olursa veri yine korunur
      final uninstErr = await runEngine(
        action: 'Uninstall',
        installDir: installDir,
        programDataRoot: dataRoot,
        faultInjection: 'UninstallService',
      );
      expect(uninstErr.exitCode, equals(75));
      expect(existingDb.readAsStringSync(), equals('CRITICAL_DATA'));
    });
  });
}
