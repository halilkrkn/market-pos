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
  final repoRoot = Directory(
    p.normalize(p.join(Directory.current.path, '..', '..')),
  ).absolute.path;
  final engineScript = p.join(
    repoRoot,
    'installer',
    'windows',
    'scripts',
    'mms_installer_engine.ps1',
  );
  final buildScript = p.join(
    repoRoot,
    'scripts',
    'build_windows_installer.ps1',
  );

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
    final client = Directory(p.join(stage.path, 'client'))
      ..createSync(recursive: true);
    final hubBin = Directory(p.join(stage.path, 'hub_bin'))
      ..createSync(recursive: true);
    final hubScripts = Directory(p.join(stage.path, 'hub_scripts'))
      ..createSync(recursive: true);

    File(p.join(client.path, 'market_pos.exe'))
        .writeAsStringSync('CLIENT_$tag');
    if (!omitFlutterDll) {
      File(p.join(client.path, 'flutter_windows.dll'))
          .writeAsStringSync('FLUTTER_$tag');
    }
    File(p.join(hubBin.path, 'mms_backend.exe')).writeAsStringSync('HUB_$tag');
    File(p.join(hubBin.path, 'sqlite3.dll')).writeAsStringSync('SQLITE_$tag');
    File(p.join(hubBin.path, 'MarketMMSService.exe'))
        .writeAsStringSync('WINSW_$tag');
    File(p.join(hubBin.path, 'MarketMMSService.xml')).writeAsStringSync(
      File(
        p.join(
          repoRoot,
          'test_spikes',
          'spike_01_backend',
          'service_wrapper',
          'MarketMMSService.xml',
        ),
      ).readAsStringSync(),
    );
    File(p.join(hubBin.path, 'hub_config.example.json')).writeAsStringSync(
      File(
        p.join(
          repoRoot,
          'test_spikes',
          'spike_01_backend',
          'config',
          'hub_config.example.json',
        ),
      ).readAsStringSync(),
    );
    File(engineScript)
        .copySync(p.join(hubScripts.path, 'mms_installer_engine.ps1'));
    return stage;
  }

  void seedSyntheticCerts(Directory programDataRoot) {
    final certs = Directory(p.join(programDataRoot.path, 'certs'))
      ..createSync(recursive: true);
    File(p.join(certs.path, 'ca.crt')).writeAsStringSync('SYNTHETIC_CA_CERT');
    File(p.join(certs.path, 'server.crt'))
        .writeAsStringSync('SYNTHETIC_SERVER_CERT');
    File(p.join(certs.path, 'server.key'))
        .writeAsStringSync('SYNTHETIC_SERVER_KEY');
  }

  Future<ProcessResult> runPsFile(String scriptPath, List<String> args) {
    return Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      scriptPath,
      ...args,
    ], workingDirectory: repoRoot);
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
    bool msiManaged = false,
    List<String> simulatedExistingServices = const [],
  }) {
    final args = <String>[
      '-Action',
      action,
      '-InstallDir',
      installDir.path,
      '-ProgramDataRoot',
      programDataRoot.path,
      if (stagingDir != null) ...['-StagingDir', stagingDir.path],
      '-AppVersion',
      appVersion,
      '-ServiceName',
      serviceName,
      '-TestSandboxMode',
      if (msiManaged) '-MsiManaged',
      '-FaultInjectionStage',
      faultInjection,
      '-AllowDeferredTlsStart',
      allowDeferredTlsStart ? '1' : '0',
      if (healthCheckUrl != null) ...['-HealthCheckUrl', healthCheckUrl],
      if (purgeUserData) '-PurgeUserData',
      if (confirmPurgeToken.isNotEmpty) ...[
        '-ConfirmPurgeToken',
        confirmPurgeToken,
      ],
      if (simulatedExistingServices.isNotEmpty) ...[
        '-SimulatedExistingServices',
        simulatedExistingServices.join(','),
      ],
    ];
    return runPsFile(engineScript, args);
  }

  String buildEngineAstBootstrap() {
    final escapedEngine = engineScript.replaceAll("'", "''");
    return '''
\$tokens = \$null
\$errors = \$null
\$ast = [System.Management.Automation.Language.Parser]::ParseFile(
  '$escapedEngine',
  [ref]\$tokens,
  [ref]\$errors
)
if (\$errors -and \$errors.Count -gt 0) { throw "Parse errors in engine script" }
\$typeAst = \$ast.FindAll({ param(\$n) \$n -is [System.Management.Automation.Language.IfStatementAst] -and \$n.Extent.Text -match 'MmsSafeDiagnosticLogWriter' }, \$true) | Select-Object -First 1
if (\$null -eq \$typeAst) { throw "Missing MmsSafeDiagnosticLogWriter AST" }
Invoke-Expression \$typeAst.Extent.Text
foreach (\$fnName in @('Test-IsPathReparsePoint', 'Resolve-WindowsServiceSid', 'Test-IsSafeDiagnosticDirectorySecurity', 'Test-AdminSecretReadOnlyAcl', 'Get-InstallerTxStateFile', 'Get-InstallerTxPrevStateFile', 'Test-ValidTxStateObject', 'Read-InstallerTxStateSafe', 'Resolve-ValidatedManifestFallback', 'Protect-InstallerDiagnosticText', 'Write-InstallerDiagnosticLog', 'Fail-Installer', 'Apply-DirectoryAcls')) {
  \$fnAst = \$ast.FindAll({ param(\$n) \$n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and \$n.Name -eq \$fnName }, \$true) | Select-Object -First 1
  if (\$null -eq \$fnAst) { throw "Missing function: \$fnName" }
  Invoke-Expression \$fnAst.Extent.Text
}
\$script:DiagnosticIcaclsPath = 'icacls.exe'
\$ServiceName = 'MarketMMSService'
\$FaultInjectionStage = 'None'
\$StandardProgramDataSubdirs = @("bin", "bin\\broker", "bin\\lib", "lib", "config", "certs", "data", "security", "logs", "backups", "run")
''';
  }

  group('PHASE C — Windows Installer (WiX MSI + Sandbox Lifecycle)', () {
    test('1 & 2. WiX MSI paket üretimi, SHA-256 doğrulaması ve MSI tablo/içerik denetimi', () async {
      final msiStage = Directory(p.join(tempRoot.path, 'msi_stage'));
      final msiOut = Directory(p.join(tempRoot.path, 'msi_out'));
      final res = await runPsFile(buildScript, [
        '-SyntheticStagingForTest',
        '-StagingDir',
        msiStage.path,
        '-OutputDir',
        msiOut.path,
        '-OverrideVersion',
        '1.0.0',
      ]);
      expect(res.exitCode, equals(0), reason: '${res.stdout}\n${res.stderr}');

      final msiFile = File(
        p.join(msiOut.path, 'MarketMMS-Setup-1.0.0-x64.msi'),
      );
      expect(msiFile.existsSync(), isTrue);
      expect(msiFile.lengthSync(), greaterThan(30000));

      final sumsFile = File(p.join(msiOut.path, 'SHA256SUMS.txt'));
      expect(sumsFile.existsSync(), isTrue);
      expect(
        sumsFile.readAsStringSync().toUpperCase(),
        contains('MARKETMMS-SETUP-1.0.0-X64.MSI'),
      );

      // NTFS HardLink regresyon korumasi: ikinci sentetik derleme ilk MSI baytlarini bozmamali
      final firstMsiBytesBefore = msiFile.readAsBytesSync();
      final linkCheck1 = Process.runSync('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        '\$lt = (Get-Item -LiteralPath "${msiFile.path.replaceAll("'", "''")}").LinkType; if (-not [string]::IsNullOrEmpty(\$lt)) { Write-Error "UNEXPECTED_LINKTYPE=\$lt"; exit 2 }',
      ]);
      expect(linkCheck1.exitCode, equals(0), reason: '${linkCheck1.stderr}');

      final msiStage2 = Directory(p.join(tempRoot.path, 'msi_stage_2'));
      final msiOut2 = Directory(p.join(tempRoot.path, 'msi_out_2'));
      final res2 = await runPsFile(buildScript, [
        '-SyntheticStagingForTest',
        '-StagingDir',
        msiStage2.path,
        '-OutputDir',
        msiOut2.path,
        '-OverrideVersion',
        '1.0.0',
      ]);
      expect(res2.exitCode, equals(0), reason: '${res2.stdout}\n${res2.stderr}');
      final msiFile2 = File(
        p.join(msiOut2.path, 'MarketMMS-Setup-1.0.0-x64.msi'),
      );
      expect(msiFile2.existsSync(), isTrue);
      expect(
        msiFile.readAsBytesSync(),
        equals(firstMsiBytesBefore),
        reason: 'Ikincil MSI derlemesi onceki OutputDir icindeki MSI dosyasinin uzerine yazmamalidir',
      );
      expect(
        msiFile2.readAsBytesSync(),
        isNot(equals(firstMsiBytesBefore)),
        reason: 'Her MSI derlemesi benzersiz ProductCode ve bagimsiz dosya uretmelidir',
      );

      // Windows Installer COM üzerinden gerçek MSI veritabanı tablolarını denetle
      final inspectScript =
          '''
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
      final inspectRes = await Process.run('powershell.exe', [
        '-NoProfile',
        '-Command',
        inspectScript,
      ]);
      expect(
        inspectRes.exitCode,
        equals(0),
        reason: '${inspectRes.stdout}\n${inspectRes.stderr}',
      );

      final msiData =
          jsonDecode(inspectRes.stdout as String) as Map<String, dynamic>;
      final props = List<String>.from(msiData['properties'] as List);
      expect(props, contains('ProductVersion|1.0.0'));
      expect(
        props,
        contains('UpgradeCode|{8F4E2D1A-6C7B-4E93-A521-9D3C0478B6E2}'),
      );
      expect(props, contains('PURGE_USER_DATA|0'));
      expect(props, contains('ALLOW_DEFERRED_TLS_START|1'));

      final customActions = List<String>.from(msiData['custom_actions'] as List)
          .join('\n');
      expect(customActions, contains('CA_InstallOrUpgrade'));
      expect(customActions, contains('CA_RollbackInstall'));
      expect(customActions, contains('CA_Uninstall'));

      final shortcuts = List<String>.from(msiData['shortcuts'] as List)
          .join('\n');
      expect(
        shortcuts,
        matches(
          RegExp(
            r'StartMenuShortcut\|([^|\r\n]*\|)?Market MMS\|\[ClientFolder\]market_pos\.exe',
          ),
        ),
      );
      expect(
        shortcuts,
        matches(
          RegExp(
            r'DesktopShortcut\|([^|\r\n]*\|)?Market MMS\|\[ClientFolder\]market_pos\.exe',
          ),
        ),
      );

      final files = List<String>.from(msiData['files'] as List)
          .join('\n')
          .toLowerCase();
      for (final required in [
        'market_pos.exe',
        'flutter_windows.dll',
        'mms_backend.exe',
        'marketmmsservice.exe',
        'marketmmsservice.xml',
        'sqlite3.dll',
        'mms_installer_engine.ps1',
      ]) {
        expect(
          files,
          contains(required),
          reason: 'MSI File tablosunda $required bulunmalı',
        );
      }
    });

    test('3, 4 & 5. İlk kurulum, ProgramData dizinleri, servis config, NTFS ACL ve güvenlik doğrulaması', () async {
      final installDir = Directory(
        p.join(tempRoot.path, 'ProgramFiles', 'MarketMMS'),
      );
      final dataRoot = Directory(
        p.join(tempRoot.path, 'ProgramData', 'MarketMMS'),
      );
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

      for (final sub in [
        'bin',
        'bin\\lib',
        'lib',
        'config',
        'certs',
        'data',
        'security',
        'logs',
        'backups',
        'run',
      ]) {
        expect(Directory(p.join(dataRoot.path, sub)).existsSync(), isTrue);
      }
      expect(
        File(p.join(installDir.path, 'client', 'market_pos.exe')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(dataRoot.path, 'bin', 'mms_backend.exe')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(dataRoot.path, 'bin', 'sqlite3.dll')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(dataRoot.path, 'lib', 'sqlite3.dll')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(dataRoot.path, 'config', 'hub_config.json')).existsSync(),
        isTrue,
      );

      final xmlContent = File(
        p.join(dataRoot.path, 'bin', 'MarketMMSService.xml'),
      ).readAsStringSync();
      expect(xmlContent, contains('<user>LocalService</user>'));
      expect(xmlContent, contains('<stoptimeout>15 sec</stoptimeout>'));

      final adminSecretFile = File(
        p.join(dataRoot.path, 'security', 'admin_secret.txt'),
      );
      expect(adminSecretFile.existsSync(), isTrue);
      final secretVal = adminSecretFile.readAsStringSync();
      expect(secretVal.length, greaterThanOrEqualTo(32));
      expect(
        '${res.stdout}\n${res.stderr}',
        isNot(contains(secretVal)),
        reason: 'Admin secret kurulum loglarına yazılmamalıdır.',
      );

      // Gerçek NTFS ACL doğrulaması (Users / Everyone erişimi kaldırılmış olmalı)
      final icaclsOut = await Process.run('icacls', [
        p.join(dataRoot.path, 'security'),
      ]);
      expect(icaclsOut.exitCode, equals(0));
      final aclText = icaclsOut.stdout as String;
      expect(aclText, isNot(contains('BUILTIN\\Users')));
      expect(aclText, isNot(contains('Everyone')));
      expect(aclText, isNot(contains('Authenticated Users')));

      // ca.key varsa kurulum ERR_SECURITY_VIOLATION (72) ile fail-closed durmalıdır
      File(p.join(dataRoot.path, 'certs', 'ca.key'))
          .writeAsStringSync('FORBIDDEN_CA_KEY');
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
      final installDir = Directory(
        p.join(tempRoot.path, 'ProgramFiles', 'MarketMMS'),
      );
      final dataRoot = Directory(
        p.join(tempRoot.path, 'ProgramData', 'MarketMMS'),
      );
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
      await db
          .into(db.products)
          .insert(
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
      final originalSecret = File(
        p.join(dataRoot.path, 'security', 'admin_secret.txt'),
      ).readAsStringSync();
      File(p.join(dataRoot.path, 'security', 'pepper.dpapi'))
          .writeAsBytesSync([1, 2, 3, 4]);
      File(p.join(dataRoot.path, 'security', 'backup_recovery_key.dpapi'))
          .writeAsBytesSync([5, 6, 7, 8]);
      File(p.join(dataRoot.path, 'security', 'backup_drive_oauth.dpapi'))
          .writeAsBytesSync([9, 10, 11, 12]);

      // 6. Aynı sürüm tekrar kurulum (Repair): mevcut config, secret, DB ve DPAPI dosyaları ezilmez
      final repair = await runEngine(
        action: 'Install',
        installDir: installDir,
        programDataRoot: dataRoot,
        stagingDir: stage10,
        appVersion: '1.0.0',
      );
      expect(repair.exitCode, equals(0), reason: '${repair.stderr}');
      expect(
        (jsonDecode(repair.stdout as String) as Map)['mode'],
        equals('Repair'),
      );
      expect(cfgFile.readAsStringSync(), equals(customCfg));
      expect(
        File(p.join(dataRoot.path, 'security', 'admin_secret.txt'))
            .readAsStringSync(),
        equals(originalSecret),
      );

      // 8a. Başarısız Upgrade Rollback (v1.0.0 -> v1.1.0 Migration/HealthCheck/UpgradeInterrupt hatası)
      for (final stageFault in [
        'UpgradeInterrupt',
        'Migration',
        'HealthCheck',
      ]) {
        final failedUpgrade = await runEngine(
          action: 'Install',
          installDir: installDir,
          programDataRoot: dataRoot,
          stagingDir: stage11,
          appVersion: '1.1.0',
          faultInjection: stageFault,
        );
        expect(failedUpgrade.exitCode, equals(74));
        expect(
          File(p.join(dataRoot.path, 'bin', 'mms_backend.exe'))
              .readAsStringSync(),
          equals('HUB_v100'),
          reason:
              '$stageFault hatası sonrası 1.0.0 ikililerine geri dönülmelidir.',
        );
        expect(
          File(p.join(installDir.path, 'client', 'market_pos.exe'))
              .readAsStringSync(),
          equals('CLIENT_v100'),
        );
        final manifestAfterRb = jsonDecode(
          File(p.join(dataRoot.path, 'config', 'install_manifest.json'))
              .readAsStringSync(),
        ) as Map;
        expect(manifestAfterRb['app_version'], equals('1.0.0'));
        final scmAfterRb = jsonDecode(
          File(p.join(dataRoot.path, 'run', 'sandbox_scm.json'))
              .readAsStringSync(),
        ) as Map;
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
      final upgManifest =
          jsonDecode(upgrade.stdout as String) as Map<String, dynamic>;
      expect(upgManifest['mode'], equals('Upgrade'));
      expect(upgManifest['app_version'], equals('1.1.0'));
      expect(upgManifest['pre_upgrade_backup_path'], isNotNull);
      expect(
        File(upgManifest['pre_upgrade_backup_path'] as String).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(dataRoot.path, 'bin', 'mms_backend.exe'))
            .readAsStringSync(),
        equals('HUB_v110'),
      );
      expect(
        File(p.join(installDir.path, 'client', 'market_pos.exe'))
            .readAsStringSync(),
        equals('CLIENT_v110'),
      );
      expect(
        File(p.join(dataRoot.path, 'security', 'pepper.dpapi'))
            .readAsBytesSync(),
        equals([1, 2, 3, 4]),
      );
      expect(
        File(p.join(dataRoot.path, 'security', 'backup_recovery_key.dpapi'))
            .readAsBytesSync(),
        equals([5, 6, 7, 8]),
      );

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
      final installDir = Directory(
        p.join(tempRoot.path, 'ProgramFiles', 'MarketMMS'),
      );
      final dataRoot = Directory(
        p.join(tempRoot.path, 'ProgramData', 'MarketMMS'),
      );
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
      expect(
        '${spikeProtected.stderr}',
        contains('ERR_PROTECTED_SERVICE_CONFLICT'),
      );

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
      File(p.join(dataRoot.path, 'data', 'market_master.db'))
          .writeAsStringSync('USER_DB_BYTES');
      File(p.join(dataRoot.path, 'backups', 'bak_1.mmsbak'))
          .writeAsStringSync('USER_BACKUP');
      File(p.join(dataRoot.path, 'security', 'pepper.dpapi'))
          .writeAsStringSync('USER_PEPPER');

      // Yanlış/boş token ile PurgeUserData reddedilir ve veri korunur
      final badPurge = await runEngine(
        action: 'Uninstall',
        installDir: installDir,
        programDataRoot: dataRoot,
        purgeUserData: true,
        confirmPurgeToken: 'WRONG_TOKEN',
      );
      expect(badPurge.exitCode, equals(76));
      expect(
        File(p.join(dataRoot.path, 'data', 'market_master.db')).existsSync(),
        isTrue,
      );

      // Varsayılan Uninstall: ikililer ve servis kalkar, ProgramData verisi %100 korunur
      final uninst = await runEngine(
        action: 'Uninstall',
        installDir: installDir,
        programDataRoot: dataRoot,
      );
      expect(uninst.exitCode, equals(0), reason: '${uninst.stderr}');
      final uninstJson =
          jsonDecode(uninst.stdout as String) as Map<String, dynamic>;
      expect(uninstJson['user_data_preserved'], isTrue);
      expect(installDir.existsSync(), isFalse);
      expect(Directory(p.join(dataRoot.path, 'bin')).existsSync(), isFalse);
      expect(
        File(p.join(dataRoot.path, 'run', 'sandbox_scm.json')).existsSync(),
        isFalse,
      );
      expect(
        File(p.join(dataRoot.path, 'data', 'market_master.db'))
            .readAsStringSync(),
        equals('USER_DB_BYTES'),
      );
      expect(
        File(p.join(dataRoot.path, 'backups', 'bak_1.mmsbak')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(dataRoot.path, 'security', 'pepper.dpapi')).existsSync(),
        isTrue,
      );

      // Kaldırma sonrası tekrar kurulum veriyi bozmadan başarılı olur
      final reinst = await runEngine(
        action: 'Install',
        installDir: installDir,
        programDataRoot: dataRoot,
        stagingDir: stage,
      );
      expect(reinst.exitCode, equals(0));
      expect(
        File(p.join(dataRoot.path, 'data', 'market_master.db'))
            .readAsStringSync(),
        equals('USER_DB_BYTES'),
      );
    });

    test('12, 13 & 14. Canlı Hub Health Check, Recovery Password durumu ve tek seferlik OWNER bootstrap', () async {
      final serverDir = Directory(p.join(tempRoot.path, 'live_hub'));
      final dbFile = File(p.join(serverDir.path, 'data', 'market_master.db'));
      await dbFile.parent.create(recursive: true);
      final liveDb = SpikeDatabase(dbFile);
      final pepper = PepperManager(
        File(p.join(serverDir.path, 'security', 'pepper.dpapi')),
      )..initialize(overrideForTesting: 'phase_c_live_hub_pepper_32bytes!');
      final server = SpikeServer(
        db: liveDb,
        dbFile: dbFile,
        writeQueue: WriteQueue(),
        backupDirectory: p.join(serverDir.path, 'backups'),
        adminSecret: 'phasec_admin_secret_2026',
        pepperManager: pepper,
      );
      final probeSock = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = probeSock.port;
      await probeSock.close();
      await server.start(
        address: InternetAddress.loopbackIPv4,
        port: port,
        enableDiscovery: false,
      );
      final baseUrl = 'http://127.0.0.1:$port';

      try {
        // 12. Recovery Password yokken /health recovery_key_configured == false ve admin/backup fail-closed 412
        final hBefore = jsonDecode(
          (await http.get(Uri.parse('$baseUrl/health'))).body,
        ) as Map<String, dynamic>;
        expect(hBefore['status'], equals('UP'));
        expect((hBefore['backup'] as Map)['recovery_key_configured'], isFalse);

        final failBackup = await http.post(
          Uri.parse('$baseUrl/api/v1/admin/backup'),
          headers: {
            'x-mms-admin-secret': 'phasec_admin_secret_2026',
            'content-type': 'application/json',
          },
          body: '{}',
        );
        expect(failBackup.statusCode, equals(412));

        await server.hubRecoveryKeyStore.saveRecoveryPassword(
          'OwnerKurulumParolasi-2026!',
        );
        final hAfter = jsonDecode(
          (await http.get(Uri.parse('$baseUrl/health'))).body,
        ) as Map<String, dynamic>;
        expect((hAfter['backup'] as Map)['recovery_key_configured'], isTrue);

        // 13. Tek seferlik OWNER bootstrap (OV-04): ilk çağrı OWNER döner, ikinci 409 reddedilir
        final boot1 = await http.post(
          Uri.parse('$baseUrl/api/v1/admin/owner/bootstrap'),
          headers: {
            'x-mms-admin-secret': 'phasec_admin_secret_2026',
            'content-type': 'application/json',
          },
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
          headers: {
            'x-mms-admin-secret': 'phasec_admin_secret_2026',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'device_id': 'POS-WIN-OWNER-02',
            'register_if_missing': true,
          }),
        );
        expect(boot2.statusCode, equals(409));
        expect(
          (jsonDecode(boot2.body) as Map)['code'],
          equals('ERR_OWNER_ALREADY_BOOTSTRAPPED'),
        );

        // 14. Canlı Hub /health ile Installer doğrulaması
        final installDir = Directory(
          p.join(tempRoot.path, 'ProgramFilesLive', 'MarketMMS'),
        );
        final dataRoot = Directory(
          p.join(tempRoot.path, 'ProgramDataLive', 'MarketMMS'),
        );
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
        final liveManifest =
            jsonDecode(instLive.stdout as String) as Map<String, dynamic>;
        expect(liveManifest['health_verified'], isTrue);
        expect(liveManifest['recovery_key_configured'], isTrue);
      } finally {
        await server.stop();
      }

      // Kapalı /health ucunda installer rollback yapmalıdır
      final deadInstallDir = Directory(
        p.join(tempRoot.path, 'ProgramFilesDead', 'MarketMMS'),
      );
      final deadDataRoot = Directory(
        p.join(tempRoot.path, 'ProgramDataDead', 'MarketMMS'),
      );
      seedSyntheticCerts(deadDataRoot);
      final instDead = await runEngine(
        action: 'Install',
        installDir: deadInstallDir,
        programDataRoot: deadDataRoot,
        stagingDir: createSyntheticStaging('dead'),
        healthCheckUrl: 'http://127.0.0.1:$port/health',
      );
      expect(instDead.exitCode, equals(74));
      expect(
        File(p.join(deadDataRoot.path, 'bin', 'mms_backend.exe')).existsSync(),
        isFalse,
      );
    });

    test('15 & 16. Eksik runtime kontrolü ve tüm kritik aşamalarda kullanıcı verisini koruyan rollback', () async {
      final installDir = Directory(
        p.join(tempRoot.path, 'ProgramFilesErr', 'MarketMMS'),
      );
      final dataRoot = Directory(
        p.join(tempRoot.path, 'ProgramDataErr', 'MarketMMS'),
      );
      final brokenStage = createSyntheticStaging(
        'broken',
        omitFlutterDll: true,
      );

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

      for (final fault in [
        'ProgramData',
        'Acl',
        'ServiceInstall',
        'ServiceStart',
      ]) {
        final r = await runEngine(
          action: 'Install',
          installDir: installDir,
          programDataRoot: dataRoot,
          stagingDir: validStage,
          faultInjection: fault,
        );
        expect(
          r.exitCode,
          equals(74),
          reason: '$fault rollback ile 74 dönmeli',
        );
        expect(
          existingDb.readAsStringSync(),
          equals('CRITICAL_DATA'),
          reason: '$fault rollback kullanıcı verisini silmemeli',
        );
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

    test('17. MSI hata tanılama günlüğü (installer-diagnostics.log), sır maskeleme ve log hatasına dayanıklılık', () async {
      final staging = createSyntheticStaging('t17');
      File(p.join(staging.path, 'hub_scripts', 'setup_service_acls.ps1'))
          .writeAsStringSync('# synthetic acl script\n');
      File(p.join(staging.path, 'hub_scripts', 'configure_hub_firewall.ps1'))
          .writeAsStringSync('# synthetic firewall script\n');

      // A) MsiManaged kurulumda ExitCode 74 olustugunda kalici log yazilmalidir
      final installDirA = Directory(p.join(tempRoot.path, 't17_inst_a'));
      final dataRootA = Directory(p.join(tempRoot.path, 't17_data_a'));
      final failRes = await runEngine(
        action: 'Install',
        installDir: installDirA,
        programDataRoot: dataRootA,
        stagingDir: staging,
        msiManaged: true,
        faultInjection: 'ServiceInstall',
      );
      expect(failRes.exitCode, equals(74));

      final diagLogA = File(
        p.join(dataRootA.path, 'logs', 'installer-diagnostics.log'),
      );
      expect(diagLogA.existsSync(), isTrue);
      final logContentA = diagLogA.readAsStringSync();
      expect(logContentA, contains('ErrorCode: ERR_INSTALLER_STEP_FAILED'));
      expect(logContentA, contains('ExitCode: 74'));
      expect(logContentA, contains('Stage: ServiceInstallAndFirewall'));
      expect(logContentA, contains('MsiManaged: True'));
      expect(logContentA, contains('ExceptionType:'));
      expect(logContentA, contains('Simule edilmis servis kayit hatasi'));
      expect(logContentA, contains('ScriptStackTrace:'));

      // B) Sertlestirilmis hassas veri maskelemesi, 2-segment JWT, cift-kacisli JSON, idempotency ve normal metadata korunumu
      final dataRootB = Directory(p.join(tempRoot.path, 't17_data_b'));
      final psScriptB = File(p.join(tempRoot.path, 't17_redact_test.ps1'));
      final syntheticRawJwt =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJzeW50aC11c2VyIiwicm9sZSI6ImNhc2hpZXIifQ.U3ludGhldGljU2lnbmF0dXJlOTk';
      final syntheticTwoSegJwt =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJzeW50aC0yc2VnIiwicm9sZSI6ImFkbWluIn0';
      psScriptB.writeAsStringSync('''
${buildEngineAstBootstrap()}
\$Action = 'Install'
\$AppVersion = '1.0.0'
\$MsiManaged = \$true
\$TestSandboxMode = [switch]::Present
\$script:CurrentInstallerStage = 'ServiceStart'

\$normalMeta = "Stage=ServiceStart ExitCode=74 pepper_file=../security/pepper.dpapi admin_secret_file=../security/admin_secret.txt recovery_key_configured=true Basic configuration mode token_count=3 secret_mode=strict"
\$normalOut = Protect-InstallerDiagnosticText -Text \$normalMeta
if (\$normalOut -ne \$normalMeta) { throw "Normal metadata corrupted: \$normalOut" }

\$secretPayload = @(
  "Authorization: Basic U3ludGhldGljQmFzaWNDcmVkMTIz",
  "Basic U3ludGhldGljU3RhbmRhbG9uZTk5",
  "Authorization=Bearer SynthAuthBearer001",
  "Bearer secret_bearer_123",
  "mms_dt_test_device_token_999",
  "$syntheticRawJwt",
  "$syntheticTwoSegJwt",
  "pepper_hex=SynthPepperHex99 pepper_b64=U3ludGhQZXBwZXJCZDQ= client_secret=SynthClientSec77 master_key=SynthMasterKey66 encryption_key=SynthEncKey55 db_password=SynthDbPass44 jwt=SynthJwtField33 ID_TOKEN=SynthUpperI99 confirm_purge_token=SYNTH_PURGE_TOK11 admin_secret=SuperSecretAdmin42 password=TopSecretPass1",
  '{\\"password\\":\\"SynthEscapedPass1\\",\\"client_secret\\":\\"SynthEscapedSecret2\\",\\"user\\":\\"cashier1\\"}',
  '{\\\\"password\\\\":\\\\"SynthDblEscPass1\\\\",\\\\"client_secret\\\\":\\\\"SynthDblEscSec2\\\\",\\\\"user\\\\":\\\\"cashier2\\\\"}',
  '{\\\\\\"password\\\\\\":\\\\\\"SynthTriEscPass1\\\\\\",\\\\\\"client_secret\\\\\\":\\\\\\"SynthTriEscSec2\\\\\\",\\\\\\"user\\\\\\":\\\\\\"cashier3\\\\\\"}',
  '{"encryption_key":"SynthJsonEncKey","db_password":"SynthJsonDbPass","label":"market_pos"}',
  "-Password SynthCliPass777 -ConfirmPurgeToken SYNTH_CLI_PURGE -Action Install -ServiceName MarketMMSService",
  "-----BEGIN RSA PRIVATE KEY-----SYNTH_FULL_RSA_KEY_DATA-----END RSA PRIVATE KEY-----",
  "-----BEGIN TRUSTED CERTIFICATE-----SYNTH_TRUSTED_CERT_DATA-----END TRUSTED CERTIFICATE-----",
  "-----BEGIN X509 CERTIFICATE-----SYNTH_X509_CERT_DATA-----END X509 CERTIFICATE-----",
  "-----BEGIN CERTIFICATE REQUEST-----SYNTH_CSR_DATA-----END CERTIFICATE REQUEST-----",
  "-----BEGIN PKCS7-----SYNTH_PKCS7_DATA-----END PKCS7-----",
  "-----BEGIN PRIVATE KEY-----SYNTH_TRUNC_PRIV_NO_END_999"
) -join " | "

\$once = Protect-InstallerDiagnosticText -Text \$secretPayload
\$twice = Protect-InstallerDiagnosticText -Text \$once
if (\$once -ne \$twice) { throw "Redaction not idempotent!" }

try {
  throw [System.InvalidOperationException]::new(\$secretPayload)
} catch {
  Write-InstallerDiagnosticLog -DataRoot '${dataRootB.path.replaceAll("'", "''")}' -ExitCode 74 -Code 'ERR_INSTALLER_STEP_FAILED' -Message \$_.Exception.Message -ErrorRecord \$_ -Stage 'ServiceStart'
}

\$truncCertOnly = "prefix before -----BEGIN CERTIFICATE-----SYNTH_TRUNC_CERT_NO_END_888"
Write-InstallerDiagnosticLog -DataRoot '${dataRootB.path.replaceAll("'", "''")}' -ExitCode 74 -Code 'ERR_CERT_TRUNC' -Message \$truncCertOnly -Stage 'HealthCheck'
''');
      final redactRes = await runPsFile(psScriptB.path, const []);
      expect(
        redactRes.exitCode,
        equals(0),
        reason: '${redactRes.stdout}\n${redactRes.stderr}',
      );

      final diagLogB = File(
        p.join(dataRootB.path, 'logs', 'installer-diagnostics.log'),
      );
      expect(diagLogB.existsSync(), isTrue);
      final logContentB = diagLogB.readAsStringSync();
      for (final leaked in [
        'U3ludGhldGljQmFzaWNDcmVkMTIz',
        'U3ludGhldGljU3RhbmRhbG9uZTk5',
        'SynthAuthBearer001',
        'secret_bearer_123',
        'test_device_token_999',
        'U3ludGhldGljU2lnbmF0dXJlOTk',
        'eyJzdWIiOiJzeW50aC0yc2VnIiwicm9sZSI6ImFkbWluIn0',
        'SynthPepperHex99',
        'U3ludGhQZXBwZXJCZDQ=',
        'SynthClientSec77',
        'SynthMasterKey66',
        'SynthEncKey55',
        'SynthDbPass44',
        'SynthJwtField33',
        'SynthUpperI99',
        'SYNTH_PURGE_TOK11',
        'SuperSecretAdmin42',
        'TopSecretPass1',
        'SynthEscapedPass1',
        'SynthEscapedSecret2',
        'SynthDblEscPass1',
        'SynthDblEscSec2',
        'SynthTriEscPass1',
        'SynthTriEscSec2',
        'SynthJsonEncKey',
        'SynthJsonDbPass',
        'SynthCliPass777',
        'SYNTH_CLI_PURGE',
        'SYNTH_FULL_RSA_KEY_DATA',
        'SYNTH_TRUSTED_CERT_DATA',
        'SYNTH_X509_CERT_DATA',
        'SYNTH_CSR_DATA',
        'SYNTH_PKCS7_DATA',
        'SYNTH_TRUNC_PRIV_NO_END_999',
        'SYNTH_TRUNC_CERT_NO_END_888',
      ]) {
        expect(
          logContentB,
          isNot(contains(leaked)),
          reason: 'Secret leaked: $leaked',
        );
      }
      expect(logContentB, contains('Authorization: Basic [REDACTED]'));
      expect(logContentB, contains('Basic [REDACTED]'));
      expect(logContentB, contains('Bearer [REDACTED]'));
      expect(logContentB, contains('[REDACTED_JWT]'));
      expect(logContentB, contains('mms_dt_[REDACTED]'));
      expect(
        logContentB,
        contains('-----BEGIN PRIVATE KEY----- [REDACTED_TRUNCATED]'),
      );
      expect(
        logContentB,
        contains('-----BEGIN CERTIFICATE----- [REDACTED_TRUNCATED]'),
      );
      expect(logContentB, contains(r'\"user\":\"cashier1\"'));
      expect(logContentB, contains(r'\\"user\\":\\"cashier2\\"'));
      expect(logContentB, contains(r'\\\"user\\\":\\\"cashier3\\\"'));
      expect(logContentB, contains('"label":"market_pos"'));
      expect(
        logContentB,
        contains('-Action Install -ServiceName MarketMMSService'),
      );
      expect(logContentB, contains('MsiManaged: True'));
      expect(logContentB, contains('TestSandboxMode: True'));
      expect(
        logContentB,
        contains('ExceptionType: System.InvalidOperationException'),
      );

      // C) Log dizini olusturulamadiginda orijinal kurulum hatasi ve ExitCode 74 korunmalidir, %TEMP% yedek dosya acilmaz
      final tempFallbackPath = p.join(
        Platform.environment['TEMP'] ?? Directory.systemTemp.path,
        'market-mms-installer-diagnostics.log',
      );
      final tempFallbackExistedBefore = File(tempFallbackPath).existsSync();
      final installDirC = Directory(p.join(tempRoot.path, 't17_inst_c'));
      final dataRootC = Directory(p.join(tempRoot.path, 't17_data_c'))
        ..createSync(recursive: true);
      final dataDirC = Directory(p.join(dataRootC.path, 'data'))
        ..createSync(recursive: true);
      final dbFileC = File(p.join(dataDirC.path, 'market_master.db'))
        ..writeAsStringSync('EXISTING_MASTER_DB');
      File(p.join(dataRootC.path, 'logs')).writeAsStringSync('BLOCK_LOGS_DIR');

      final blockedLogFail = await runEngine(
        action: 'Install',
        installDir: installDirC,
        programDataRoot: dataRootC,
        stagingDir: staging,
        faultInjection: 'Acl',
      );
      expect(blockedLogFail.exitCode, equals(74));
      expect(
        blockedLogFail.stderr.toString(),
        contains('ERR_INSTALLER_ROLLED_BACK'),
      );
      expect(
        blockedLogFail.stderr.toString(),
        contains('Simule edilmis NTFS ACL atama hatasi'),
      );
      expect(dbFileC.readAsStringSync(), equals('EXISTING_MASTER_DB'));
      if (!tempFallbackExistedBefore) {
        expect(File(tempFallbackPath).existsSync(), isFalse);
      }
    });

    test('18. MsiContext boolean, reparse-point engeli, InnerException zinciri, STDERR maskeleme ve log rotasyonu', () async {
      final staging = createSyntheticStaging('t18');
      File(p.join(staging.path, 'hub_scripts', 'setup_service_acls.ps1'))
          .writeAsStringSync('# synthetic acl script\n');
      File(p.join(staging.path, 'hub_scripts', 'configure_hub_firewall.ps1'))
          .writeAsStringSync('# synthetic firewall script\n');

      // 1) Gercek -MsiContext boolean davranisi (valid MsiContext + AllowDeferredTlsStart=0 -> ExitCode 74)
      final installDirCtx = Directory(p.join(tempRoot.path, 't18_inst_ctx'));
      for (final sub in ['client', 'hub_bin', 'hub_scripts']) {
        final dstSub = Directory(p.join(installDirCtx.path, sub))
          ..createSync(recursive: true);
        for (final f in Directory(
          p.join(staging.path, sub),
        ).listSync().whereType<File>()) {
          f.copySync(p.join(dstSub.path, p.basename(f.path)));
        }
      }
      final dataRootCtx = Directory(p.join(tempRoot.path, 't18_data_ctx'));
      final msiCtxRes = await runPsFile(engineScript, [
        '-MsiContext',
        'Install|${installDirCtx.path}|1.0.0|8945|8946|0',
        '-ProgramDataRoot',
        dataRootCtx.path,
        '-TestSandboxMode',
      ]);
      expect(msiCtxRes.exitCode, equals(74));
      final ctxLog = File(
        p.join(dataRootCtx.path, 'logs', 'installer-diagnostics.log'),
      ).readAsStringSync();
      expect(ctxLog, contains('MsiManaged: True'));
      expect(ctxLog, contains('TestSandboxMode: True'));
      expect(ctxLog, contains('Stage: ServiceStart'));
      expect(ctxLog, contains('ERR_TLS_CERTS_MISSING'));

      // 2) Gecersiz MsiContext erken hatasi (Stage: ParseMsiContext, ExitCode 71)
      final dataRootBadCtx = Directory(
        p.join(tempRoot.path, 't18_data_bad_ctx'),
      );
      final badCtxRes = await runPsFile(engineScript, [
        '-MsiContext',
        'Install|too|few',
        '-ProgramDataRoot',
        dataRootBadCtx.path,
        '-TestSandboxMode',
      ]);
      expect(badCtxRes.exitCode, equals(71));
      final badCtxLog = File(
        p.join(dataRootBadCtx.path, 'logs', 'installer-diagnostics.log'),
      ).readAsStringSync();
      expect(badCtxLog, contains('Stage: ParseMsiContext'));
      expect(badCtxLog, contains('ExitCode: 71'));
      expect(badCtxLog, contains('ErrorCode: ERR_INVALID_MSI_CONTEXT'));
      expect(badCtxLog, contains('MsiManaged: True'));

      // 3) Reparse-point (directory junction) hedefinin reddedilmesi ve %TEMP% yazilmamasinin dogrulanmasi
      final tempFallbackPath = p.join(
        Platform.environment['TEMP'] ?? Directory.systemTemp.path,
        'market-mms-installer-diagnostics.log',
      );
      final tempFallbackExistedBefore = File(tempFallbackPath).existsSync();
      final installDirJ = Directory(p.join(tempRoot.path, 't18_inst_j'));
      final dataRootJ = Directory(p.join(tempRoot.path, 't18_data_j'))
        ..createSync(recursive: true);
      final outsideDir = Directory(p.join(tempRoot.path, 't18_outside_target'))
        ..createSync(recursive: true);
      final logsJunctionPath = p.join(dataRootJ.path, 'logs');
      final mkJunction = Process.runSync('cmd', [
        '/c',
        'mklink',
        '/J',
        logsJunctionPath,
        outsideDir.path,
      ]);
      expect(
        mkJunction.exitCode,
        equals(0),
        reason: '${mkJunction.stdout}\n${mkJunction.stderr}',
      );
      try {
        // 3a) Kurulum oncesi logs junction varsa Assert-ProgramDataSafety ExitCode 72 ile reddeder ve log hedefi kullanilmaz
        final junctionFail = await runEngine(
          action: 'Install',
          installDir: installDirJ,
          programDataRoot: dataRootJ,
          stagingDir: staging,
          msiManaged: true,
          faultInjection: 'Acl',
        );
        expect(junctionFail.exitCode, equals(72));
        expect(
          junctionFail.stderr.toString(),
          contains('ERR_SECURITY_VIOLATION'),
        );
        expect(
          File(p.join(outsideDir.path, 'installer-diagnostics.log'))
              .existsSync(),
          isFalse,
        );
        expect(outsideDir.listSync(), isEmpty);

        // 3b) Fail-Installer ExitCode 74 sirasinda logs junction ise Write-InstallerDiagnosticLog hedefi reddeder ve ExitCode 74 korunur
        final junc74Script = File(p.join(tempRoot.path, 't18_junc74.ps1'));
        junc74Script.writeAsStringSync('''
${buildEngineAstBootstrap()}
\$Action = 'Install'
\$AppVersion = '1.0.0'
\$MsiManaged = \$true
\$TestSandboxMode = [switch]::Present
\$ProgramDataRoot = '${dataRootJ.path.replaceAll("'", "''")}'
\$script:CurrentInstallerStage = 'ServiceInstallAndFirewall'
Fail-Installer -ExitCode 74 -Code 'ERR_JUNC_74_TEST' -Message 'Junction protection preserves ExitCode 74' -Stage 'ServiceInstallAndFirewall'
''');
        final junc74Res = await runPsFile(junc74Script.path, const []);
        expect(junc74Res.exitCode, equals(74));
        expect(junc74Res.stderr.toString(), contains('[ERR_JUNC_74_TEST]'));
        expect(
          File(p.join(outsideDir.path, 'installer-diagnostics.log'))
              .existsSync(),
          isFalse,
        );
        expect(outsideDir.listSync(), isEmpty);
        if (!tempFallbackExistedBefore) {
          expect(File(tempFallbackPath).existsSync(), isFalse);
        }
      } finally {
        Process.runSync('cmd', ['/c', 'rmdir', logsJunctionPath]);
      }

      // 4) InnerException zinciri (max 5 seviye + FullyQualifiedErrorId + her seviyede maskeleme), STDERR maskeleme ve rotasyon
      final dataRootInner = Directory(p.join(tempRoot.path, 't18_data_inner'));
      final realProgDataLog = File(
        p.join(
          Platform.environment['ProgramData'] ?? r'C:\ProgramData',
          'MarketMMS',
          'logs',
          'installer-diagnostics.log',
        ),
      );
      final realProgDataExistedBefore = realProgDataLog.existsSync();
      final realProgDataSizeBefore = realProgDataExistedBefore
          ? realProgDataLog.lengthSync()
          : -1;
      final innerScript = File(
        p.join(tempRoot.path, 't18_inner_stderr_rot.ps1'),
      );
      innerScript.writeAsStringSync('''
${buildEngineAstBootstrap()}
\$Action = 'Install'
\$AppVersion = '1.0.0'
\$MsiManaged = \$true
\$TestSandboxMode = [switch]::Present
\$ProgramDataRoot = '${dataRootInner.path.replaceAll("'", "''")}'
\$script:CurrentInstallerStage = 'ServiceInstallAndFirewall'

# Strict ACL ile DataRoot ve logs dizini olusturup 1MB+ baslangic dosyasi hazirla
[MmsSafeDiagnosticLogWriter]::CreateDirectoryWithStrictSecurity(\$ProgramDataRoot, \$true)
\$logsDir = Join-Path \$ProgramDataRoot 'logs'
[MmsSafeDiagnosticLogWriter]::CreateDirectoryWithStrictSecurity(\$logsDir, \$true)
\$logFile = Join-Path \$logsDir 'installer-diagnostics.log'
[System.IO.File]::WriteAllText(\$logFile, ('R' * 1049000))

# 6 seviyeli InnerException zinciri -> 1..5 loglanir, 6. seviye max depth 5 nedeniyle kirpilir
\$e7 = [System.Exception]::new('Level7 jwt=SynthInnerSecret7')
\$e6 = [System.Exception]::new('Level6 db_password=SynthInnerSecret6', \$e7)
\$e5 = [System.InvalidOperationException]::new('Level5 master_key=SynthInnerSecret5', \$e6)
\$e4 = [System.IO.IOException]::new('Level4 client_secret=SynthInnerSecret4', \$e5)
\$e3 = [System.UnauthorizedAccessException]::new('Level3 pepper_hex=SynthInnerSecret3', \$e4)
\$e2 = [System.TimeoutException]::new('Level2 Bearer SynthInnerSecret2', \$e3)
\$e1 = [System.ApplicationException]::new('Level1 eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJpbm5lciJ9.U3ludGhJbm5lclNpZzk5', \$e2)
\$errRec = New-Object System.Management.Automation.ErrorRecord (\$e1, 'MMS_SYNTH_CHAIN_ID', [System.Management.Automation.ErrorCategory]::InvalidOperation, \$null)

Fail-Installer -ExitCode 74 -Code 'ERR_CHAIN_STDERR_TEST' -Message 'Top Bearer SynthTopSecret88 -Password SynthTopCli88' -ErrorRecord \$errRec -Stage 'ServiceInstallAndFirewall'
''');
      final innerRes = await runPsFile(innerScript.path, const []);
      expect(innerRes.exitCode, equals(74));
      final stderrOut = innerRes.stderr.toString();
      expect(stderrOut, contains('[ERR_CHAIN_STDERR_TEST]'));
      expect(stderrOut, contains('Bearer [REDACTED]'));
      expect(stderrOut, contains('-Password [REDACTED]'));
      expect(stderrOut, isNot(contains('SynthTopSecret88')));
      expect(stderrOut, isNot(contains('SynthTopCli88')));

      final rotatedFile = File(
        p.join(dataRootInner.path, 'logs', 'installer-diagnostics.log.1'),
      );
      final currentFile = File(
        p.join(dataRootInner.path, 'logs', 'installer-diagnostics.log'),
      );
      expect(rotatedFile.existsSync(), isTrue);
      expect(rotatedFile.lengthSync(), greaterThanOrEqualTo(1048576));
      expect(currentFile.existsSync(), isTrue);
      expect(currentFile.lengthSync(), lessThan(50000));

      final innerLog = currentFile.readAsStringSync();
      expect(innerLog, contains('FullyQualifiedErrorId: MMS_SYNTH_CHAIN_ID'));
      expect(innerLog, contains('InnerException[1]: System.TimeoutException'));
      expect(
        innerLog,
        contains('InnerException[2]: System.UnauthorizedAccessException'),
      );
      expect(innerLog, contains('InnerException[3]: System.IO.IOException'));
      expect(
        innerLog,
        contains('InnerException[4]: System.InvalidOperationException'),
      );
      expect(innerLog, contains('InnerException[5]: System.Exception'));
      expect(innerLog, contains('InnerException[truncated]:'));
      expect(innerLog, isNot(contains('SynthInnerSecret2')));
      expect(innerLog, isNot(contains('SynthInnerSecret3')));
      expect(innerLog, isNot(contains('SynthInnerSecret4')));
      expect(innerLog, isNot(contains('SynthInnerSecret5')));
      expect(innerLog, isNot(contains('SynthInnerSecret6')));
      expect(innerLog, isNot(contains('SynthInnerSecret7')));
      expect(innerLog, isNot(contains('U3ludGhJbm5lclNpZzk5')));
      expect(innerLog, isNot(contains('SynthTopSecret88')));
      expect(innerLog, isNot(contains('SynthTopCli88')));
      expect(innerLog, contains('Level5 master_key=[REDACTED]'));
      if (!realProgDataExistedBefore) {
        expect(realProgDataLog.existsSync(), isFalse);
      } else {
        expect(realProgDataLog.lengthSync(), equals(realProgDataSizeBefore));
      }
    });

    test('19. Mevcut/yeni logs ACL, sahiplik, icacls hatasi, ata junction ve NTFS hardlink TOCTOU savunmasi', () async {
      final staging = createSyntheticStaging('t19');
      File(p.join(staging.path, 'hub_scripts', 'setup_service_acls.ps1'))
          .writeAsStringSync('# synthetic acl script\n');
      File(p.join(staging.path, 'hub_scripts', 'configure_hub_firewall.ps1'))
          .writeAsStringSync('# synthetic firewall script\n');

      // 19A) Onceden olusturulmus guvensiz ACL'li logs dizini (Users=Modify) reddedilir, ExitCode 74 korunur
      final dataRootUnsafe = Directory(p.join(tempRoot.path, 't19_unsafe_logs'))
        ..createSync(recursive: true);
      final unsafeLogs = Directory(p.join(dataRootUnsafe.path, 'logs'))
        ..createSync(recursive: true);
      final icaclsGrantUsers = Process.runSync('icacls.exe', [
        unsafeLogs.path,
        '/grant',
        '*S-1-5-32-545:(OI)(CI)M',
      ]);
      expect(
        icaclsGrantUsers.exitCode,
        equals(0),
        reason: '${icaclsGrantUsers.stdout}\n${icaclsGrantUsers.stderr}',
      );

      final unsafeInstallDir = Directory(
        p.join(tempRoot.path, 't19_inst_unsafe'),
      );
      final unsafeEngineRes = await runEngine(
        action: 'Install',
        installDir: unsafeInstallDir,
        programDataRoot: dataRootUnsafe,
        stagingDir: staging,
        msiManaged: true,
        faultInjection: 'ServiceStart',
      );
      expect(unsafeEngineRes.exitCode, equals(74));
      expect(
        unsafeEngineRes.stderr.toString(),
        contains('ERR_SECURITY_VIOLATION'),
      );
      expect(unsafeEngineRes.stderr.toString(), contains('S-1-5-32-545'));
      expect(
        File(p.join(unsafeLogs.path, 'installer-diagnostics.log')).existsSync(),
        isFalse,
      );

      // 19A-2) Dogrudan Write-InstallerDiagnosticLog / Fail-Installer hem explicit Users ACL hem kalitsal ACL'li mevcut dizini reddeder
      final dataRootInherited = Directory(
        p.join(tempRoot.path, 't19_inherited_logs'),
      )..createSync(recursive: true);
      final inheritedLogs = Directory(p.join(dataRootInherited.path, 'logs'))
        ..createSync(recursive: true);
      final unsafeDirectScript = File(
        p.join(tempRoot.path, 't19_unsafe_direct.ps1'),
      );
      unsafeDirectScript.writeAsStringSync('''
${buildEngineAstBootstrap()}
\$Action = 'Install'
\$AppVersion = '1.0.0'
\$MsiManaged = \$true
\$TestSandboxMode = [switch]::Present
\$script:CurrentInstallerStage = 'ServiceInstallAndFirewall'
Write-InstallerDiagnosticLog -DataRoot '${dataRootUnsafe.path.replaceAll("'", "''")}' -ExitCode 74 -Code 'ERR_UNSAFE_EXPLICIT' -Message 'Must reject explicit Users ACE'
\$ProgramDataRoot = '${dataRootInherited.path.replaceAll("'", "''")}'
Fail-Installer -ExitCode 74 -Code 'ERR_UNSAFE_INHERITED' -Message 'Must reject unprotected inherited ACL'
''');
      final unsafeDirectRes = await runPsFile(
        unsafeDirectScript.path,
        const [],
      );
      expect(unsafeDirectRes.exitCode, equals(74));
      expect(
        unsafeDirectRes.stderr.toString(),
        contains('[ERR_UNSAFE_INHERITED]'),
      );
      expect(
        File(p.join(unsafeLogs.path, 'installer-diagnostics.log')).existsSync(),
        isFalse,
      );
      expect(
        File(p.join(inheritedLogs.path, 'installer-diagnostics.log'))
            .existsSync(),
        isFalse,
      );

      // 19B) Guvenli ACL'li mevcut logs kabul edilir + yeni logs dizini baslangictan strict ACL ile olusturulur + 19C) guvensiz sahiplik reddi + 19D) icacls hatasi
      final dataRootSafeAndNew = Directory(
        p.join(tempRoot.path, 't19_safe_and_new'),
      )..createSync(recursive: true);
      final dataRootFreshNew = Directory(
        p.join(tempRoot.path, 't19_fresh_new'),
      );
      final fakeFailIcacls = File(p.join(tempRoot.path, 't19_fake_icacls.cmd'))
        ..writeAsStringSync('@echo off\r\nexit /b 5\r\n');
      final dataRootIcaclsFail = Directory(
        p.join(tempRoot.path, 't19_icacls_fail'),
      );

      final secScript = File(p.join(tempRoot.path, 't19_sec_checks.ps1'));
      secScript.writeAsStringSync('''
${buildEngineAstBootstrap()}
\$Action = 'Install'
\$AppVersion = '1.0.0'
\$MsiManaged = \$true
\$TestSandboxMode = [switch]::Present
\$script:CurrentInstallerStage = 'ServiceInstallAndFirewall'

# 19B-1: Apply-DirectoryAcls ile olusan guvenli mevcut logs kabul edilir
Apply-DirectoryAcls -DataRoot '${dataRootSafeAndNew.path.replaceAll("'", "''")}'
\$safeLogs = Join-Path '${dataRootSafeAndNew.path.replaceAll("'", "''")}' 'logs'
if (-not (Test-IsSafeDiagnosticDirectorySecurity -DirectoryPath \$safeLogs -SandboxMode -ExpectedServiceName \$ServiceName)) {
  throw 'Expected Apply-DirectoryAcls logs dir to pass security check'
}
Write-InstallerDiagnosticLog -DataRoot '${dataRootSafeAndNew.path.replaceAll("'", "''")}' -ExitCode 74 -Code 'ERR_SAFE_EXISTING' -Message 'Allowed in safe ACL logs'
if (-not (Test-Path (Join-Path \$safeLogs 'installer-diagnostics.log'))) { throw 'Safe existing logs write failed' }

# 19C: SYSTEM/Administrators disi guvensiz sahiplik gercek modda reddedilir
if (Test-IsSafeDiagnosticDirectorySecurity -DirectoryPath \$safeLogs -ExpectedServiceName \$ServiceName -OverrideOwnerSid 'S-1-5-21-111111-222222-333333-1099') {
  throw 'Untrusted owner SID should have been rejected'
}

# 19B-2: Yeni olusturulan logs dizininde kalitim kirik, SYSTEM ve Admins FullControl, Users/Everyone erisimi yok
Write-InstallerDiagnosticLog -DataRoot '${dataRootFreshNew.path.replaceAll("'", "''")}' -ExitCode 74 -Code 'ERR_FRESH_STRICT' -Message 'Strict ACL creation check'
\$freshLogs = Join-Path '${dataRootFreshNew.path.replaceAll("'", "''")}' 'logs'
if (-not (Test-Path (Join-Path \$freshLogs 'installer-diagnostics.log'))) { throw 'Fresh strict logs write failed' }
\$aclFresh = Get-Acl -LiteralPath \$freshLogs
if (-not \$aclFresh.AreAccessRulesProtected) { throw 'Fresh logs inheritance must be protected' }
\$sids = @(\$aclFresh.Access | ForEach-Object { \$_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value })
if (-not (\$sids -contains 'S-1-5-18') -or -not (\$sids -contains 'S-1-5-32-544')) { throw 'SYSTEM or Admins missing' }
foreach (\$bad in @('S-1-5-32-545','S-1-1-0','S-1-5-11')) {
  if (\$sids -contains \$bad) { throw "Forbidden SID present: \$bad" }
}

# 19D: icacls hata dondugunde log yazimi durur ve ExitCode 74 korunur
\$script:DiagnosticIcaclsPath = '${fakeFailIcacls.path.replaceAll("'", "''")}'
\$ProgramDataRoot = '${dataRootIcaclsFail.path.replaceAll("'", "''")}'
Fail-Installer -ExitCode 74 -Code 'ERR_ICACLS_ABORT_TEST' -Message 'Must keep ExitCode 74 on icacls failure'
''');
      final secRes = await runPsFile(secScript.path, const []);
      expect(
        secRes.exitCode,
        equals(74),
        reason: '${secRes.stdout}\n${secRes.stderr}',
      );
      expect(secRes.stderr.toString(), contains('[ERR_ICACLS_ABORT_TEST]'));
      expect(
        File(
          p.join(dataRootIcaclsFail.path, 'logs', 'installer-diagnostics.log'),
        ).existsSync(),
        isFalse,
      );

      // 19E: Ust ata dizin junction (ancestor reparse point) reddedilir
      final outsideAnc = Directory(p.join(tempRoot.path, 't19_outside_anc'))
        ..createSync(recursive: true);
      final ancJunc = p.join(tempRoot.path, 't19_anc_junc');
      final mkAnc = Process.runSync('cmd', [
        '/c',
        'mklink',
        '/J',
        ancJunc,
        outsideAnc.path,
      ]);
      expect(
        mkAnc.exitCode,
        equals(0),
        reason: '${mkAnc.stdout}\n${mkAnc.stderr}',
      );
      try {
        final ancScript = File(p.join(tempRoot.path, 't19_anc_test.ps1'));
        ancScript.writeAsStringSync('''
${buildEngineAstBootstrap()}
\$Action = 'Install'
\$AppVersion = '1.0.0'
\$MsiManaged = \$true
\$TestSandboxMode = [switch]::Present
\$ProgramDataRoot = '${p.join(ancJunc, 'nested_data').replaceAll("'", "''")}'
Fail-Installer -ExitCode 74 -Code 'ERR_ANCESTOR_JUNC' -Message 'Ancestor reparse point must abort log write'
''');
        final ancRes = await runPsFile(ancScript.path, const []);
        expect(ancRes.exitCode, equals(74));
        expect(ancRes.stderr.toString(), contains('[ERR_ANCESTOR_JUNC]'));
        expect(outsideAnc.listSync(), isEmpty);
      } finally {
        Process.runSync('cmd', ['/c', 'rmdir', ancJunc]);
      }

      // 19F: NTFS hardlink TOCTOU savunmasi (hem aktif log hem .1 rotasyon hedefi) ve basarili handle rotasyonu
      final dataRootHL = Directory(p.join(tempRoot.path, 't19_hardlink'));
      final canary = File(p.join(tempRoot.path, 't19_canary.txt'))
        ..writeAsStringSync('CANARY_UNTOUCHED');
      final hlLogsDir = Directory(p.join(dataRootHL.path, 'logs'));
      final hlSetupScript = File(p.join(tempRoot.path, 't19_hl_setup.ps1'));
      hlSetupScript.writeAsStringSync('''
${buildEngineAstBootstrap()}
[MmsSafeDiagnosticLogWriter]::CreateDirectoryWithStrictSecurity('${dataRootHL.path.replaceAll("'", "''")}', \$true)
[MmsSafeDiagnosticLogWriter]::CreateDirectoryWithStrictSecurity('${hlLogsDir.path.replaceAll("'", "''")}', \$true)
''');
      final setupRes = await runPsFile(hlSetupScript.path, const []);
      expect(setupRes.exitCode, equals(0), reason: '${setupRes.stderr}');

      final activeLogLink = p.join(hlLogsDir.path, 'installer-diagnostics.log');
      final rotatedLogLink = p.join(
        hlLogsDir.path,
        'installer-diagnostics.log.1',
      );
      final mkHl1 = Process.runSync('cmd', [
        '/c',
        'mklink',
        '/H',
        activeLogLink,
        canary.path,
      ]);
      expect(
        mkHl1.exitCode,
        equals(0),
        reason: '${mkHl1.stdout}\n${mkHl1.stderr}',
      );
      try {
        final hlScript = File(p.join(tempRoot.path, 't19_hl_exec.ps1'));
        hlScript.writeAsStringSync('''
${buildEngineAstBootstrap()}
\$Action = 'Install'
\$AppVersion = '1.0.0'
\$MsiManaged = \$true
\$TestSandboxMode = [switch]::Present
\$ProgramDataRoot = '${dataRootHL.path.replaceAll("'", "''")}'
Fail-Installer -ExitCode 74 -Code 'ERR_HL_ACTIVE_TEST' -Message 'Hardlink target must never be modified'
''');
        final hlRes1 = await runPsFile(hlScript.path, const []);
        expect(hlRes1.exitCode, equals(74));
        expect(hlRes1.stderr.toString(), contains('[ERR_HL_ACTIVE_TEST]'));
        expect(canary.readAsStringSync(), equals('CANARY_UNTOUCHED'));
      } finally {
        if (File(activeLogLink).existsSync()) File(activeLogLink).deleteSync();
      }

      // Aktif log >= 1MB iken .1 hedefi hardlink yapilirsa rotasyon ve yazma iptal edilir, canary korunur
      File(activeLogLink).writeAsStringSync('Z' * 1049000);
      final mkHl2 = Process.runSync('cmd', [
        '/c',
        'mklink',
        '/H',
        rotatedLogLink,
        canary.path,
      ]);
      expect(
        mkHl2.exitCode,
        equals(0),
        reason: '${mkHl2.stdout}\n${mkHl2.stderr}',
      );
      try {
        final hlScript2 = File(p.join(tempRoot.path, 't19_hl_exec2.ps1'));
        hlScript2.writeAsStringSync('''
${buildEngineAstBootstrap()}
\$Action = 'Install'
\$AppVersion = '1.0.0'
\$MsiManaged = \$true
\$TestSandboxMode = [switch]::Present
\$ProgramDataRoot = '${dataRootHL.path.replaceAll("'", "''")}'
Fail-Installer -ExitCode 74 -Code 'ERR_HL_ROT_TEST' -Message 'Hardlink .1 target must abort rotation'
''');
        final hlRes2 = await runPsFile(hlScript2.path, const []);
        expect(hlRes2.exitCode, equals(74));
        expect(hlRes2.stderr.toString(), contains('[ERR_HL_ROT_TEST]'));
        expect(canary.readAsStringSync(), equals('CANARY_UNTOUCHED'));
        expect(File(activeLogLink).lengthSync(), greaterThanOrEqualTo(1049000));
      } finally {
        if (File(rotatedLogLink).existsSync())
          File(rotatedLogLink).deleteSync();
      }

      // .1 hardlink kalktiktan sonra gercek handle tabanli rotasyon basariyla gerceklesir
      final hlScript3 = File(p.join(tempRoot.path, 't19_hl_exec3.ps1'));
      hlScript3.writeAsStringSync('''
${buildEngineAstBootstrap()}
\$Action = 'Install'
\$AppVersion = '1.0.0'
\$MsiManaged = \$true
\$TestSandboxMode = [switch]::Present
\$ProgramDataRoot = '${dataRootHL.path.replaceAll("'", "''")}'
Fail-Installer -ExitCode 74 -Code 'ERR_HANDLE_ROT_OK' -Message 'Handle rotation succeeds cleanly'
''');
      final hlRes3 = await runPsFile(hlScript3.path, const []);
      expect(hlRes3.exitCode, equals(74));
      expect(File(rotatedLogLink).lengthSync(), greaterThanOrEqualTo(1049000));
      expect(
        File(activeLogLink).readAsStringSync(),
        contains('ERR_HANDLE_ROT_OK'),
      );
      expect(canary.readAsStringSync(), equals('CANARY_UNTOUCHED'));
    });

    test('20. M-1 DataRoot ACL, sahiplik, SYSTEM/Administrators zorunlulugu, icacls hatasi ve DataRoot junction reddi', () async {
      final staging = createSyntheticStaging('t20');
      File(p.join(staging.path, 'hub_scripts', 'setup_service_acls.ps1'))
          .writeAsStringSync('# synthetic acl script\n');
      File(p.join(staging.path, 'hub_scripts', 'configure_hub_firewall.ps1'))
          .writeAsStringSync('# synthetic firewall script\n');

      // 1, 2b, 3, 4, 5: Guvenli DataRoot (ve Users traverse-only), kalitsal DataRoot reddi, guvensiz owner reddi, eksik Admins/SYSTEM reddi, logs icacls hatasi
      final dataRootSafe = Directory(p.join(tempRoot.path, 't20_safe_root'));
      final dataRootTraverse = Directory(
        p.join(tempRoot.path, 't20_traverse_root'),
      );
      final dataRootInherited = Directory(
        p.join(tempRoot.path, 't20_inherited_root'),
      )..createSync(recursive: true);
      final dataRootNoAdmin = Directory(
        p.join(tempRoot.path, 't20_no_admin_root'),
      );
      final dataRootLogsIcaclsFail = Directory(
        p.join(tempRoot.path, 't20_logs_icacls_fail'),
      );
      final fakeFailIcacls = File(p.join(tempRoot.path, 't20_fake_icacls.cmd'))
        ..writeAsStringSync('@echo off\r\nexit /b 5\r\n');

      final t20Script = File(p.join(tempRoot.path, 't20_dataroot_sec.ps1'));
      t20Script.writeAsStringSync('''
${buildEngineAstBootstrap()}
\$Action = 'Install'
\$AppVersion = '1.0.0'
\$MsiManaged = \$true
\$TestSandboxMode = [switch]::Present
\$script:CurrentInstallerStage = 'ServiceInstallAndFirewall'

# 1a. Guvenli DataRoot ACL kabul edilir
Apply-DirectoryAcls -DataRoot '${dataRootSafe.path.replaceAll("'", "''")}'
if (-not (Test-IsSafeDiagnosticDirectorySecurity -DirectoryPath '${dataRootSafe.path.replaceAll("'", "''")}' -IsDataRoot -SandboxMode -ExpectedServiceName \$ServiceName)) {
  throw 'Safe DataRoot must pass security validation'
}
Write-InstallerDiagnosticLog -DataRoot '${dataRootSafe.path.replaceAll("'", "''")}' -ExitCode 74 -Code 'ERR_T20_SAFE_ROOT' -Message 'Safe DataRoot allowed'
if (-not (Test-Path '${p.join(dataRootSafe.path, 'logs', 'installer-diagnostics.log').replaceAll("'", "''")}')) {
  throw 'Expected log in safe DataRoot'
}

# 1b. Users:(NP) Execute/Traverse-only ACE iceren DataRoot kabul edilir, Users Write ACE'i reddedilir
Apply-DirectoryAcls -DataRoot '${dataRootTraverse.path.replaceAll("'", "''")}'
\$diTrav = New-Object System.IO.DirectoryInfo('${dataRootTraverse.path.replaceAll("'", "''")}')
\$aclTrav = \$diTrav.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
\$travRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
  (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-545')),
  ([System.Security.AccessControl.FileSystemRights]::ExecuteFile -bor [System.Security.AccessControl.FileSystemRights]::Synchronize),
  [System.Security.AccessControl.InheritanceFlags]::None,
  [System.Security.AccessControl.PropagationFlags]::None,
  [System.Security.AccessControl.AccessControlType]::Allow
)
\$aclTrav.AddAccessRule(\$travRule)
\$diTrav.SetAccessControl(\$aclTrav)
if (-not (Test-IsSafeDiagnosticDirectorySecurity -DirectoryPath '${dataRootTraverse.path.replaceAll("'", "''")}' -IsDataRoot -SandboxMode -ExpectedServiceName \$ServiceName)) {
  throw 'DataRoot with non-inheriting Users Traverse-only ACE must be accepted'
}
Write-InstallerDiagnosticLog -DataRoot '${dataRootTraverse.path.replaceAll("'", "''")}' -ExitCode 74 -Code 'ERR_T20_TRAVERSE_ROOT' -Message 'Users NP-X allowed'
if (-not (Test-Path '${p.join(dataRootTraverse.path, 'logs', 'installer-diagnostics.log').replaceAll("'", "''")}')) {
  throw 'Expected log in Users traverse DataRoot'
}

# 2b. Korumasiz kalitsal ACL'li mevcut DataRoot reddedilir ve logs/log dosyasi olusturulmaz
Write-InstallerDiagnosticLog -DataRoot '${dataRootInherited.path.replaceAll("'", "''")}' -ExitCode 74 -Code 'ERR_T20_INHERITED' -Message 'Must reject inherited DataRoot'
if (Test-Path '${p.join(dataRootInherited.path, 'logs').replaceAll("'", "''")}') {
  throw 'logs must NOT be created inside unsafe inherited DataRoot'
}

# 3. Guvensiz DataRoot sahip SID'i reddedilir
if (Test-IsSafeDiagnosticDirectorySecurity -DirectoryPath '${dataRootSafe.path.replaceAll("'", "''")}' -IsDataRoot -ExpectedServiceName \$ServiceName -OverrideOwnerSid 'S-1-5-21-111111-222222-333333-1099') {
  throw 'Untrusted DataRoot owner SID must be rejected'
}

# 4a. Administrators izni eksik DataRoot reddedilir
[MmsSafeDiagnosticLogWriter]::CreateDirectoryWithStrictSecurity('${dataRootNoAdmin.path.replaceAll("'", "''")}', \$true)
\$curSid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
& icacls.exe '${dataRootNoAdmin.path.replaceAll("'", "''")}' /inheritance:r /grant:r "*\${curSid}:(OI)(CI)F" /grant:r '*S-1-5-18:(OI)(CI)F' /remove '*S-1-5-32-544' | Out-Null
if (Test-IsSafeDiagnosticDirectorySecurity -DirectoryPath '${dataRootNoAdmin.path.replaceAll("'", "''")}' -IsDataRoot -SandboxMode -ExpectedServiceName \$ServiceName) {
  throw 'DataRoot missing Administrators FullControl must be rejected'
}
Write-InstallerDiagnosticLog -DataRoot '${dataRootNoAdmin.path.replaceAll("'", "''")}' -ExitCode 74 -Code 'ERR_T20_NO_ADMIN' -Message 'Must reject DataRoot without Administrators'
if (Test-Path '${p.join(dataRootNoAdmin.path, 'logs').replaceAll("'", "''")}') {
  throw 'logs must NOT be created when Administrators ACE is missing on DataRoot'
}

# 4b. SYSTEM izni eksik DataRoot reddedilir
\$dataRootNoSys = '${dataRootNoAdmin.path.replaceAll("'", "''")}_nosys'
[MmsSafeDiagnosticLogWriter]::CreateDirectoryWithStrictSecurity(\$dataRootNoSys, \$true)
& icacls.exe \$dataRootNoSys /inheritance:r /grant:r "*\${curSid}:(OI)(CI)F" /grant:r '*S-1-5-32-544:(OI)(CI)F' /remove '*S-1-5-18' | Out-Null
if (Test-IsSafeDiagnosticDirectorySecurity -DirectoryPath \$dataRootNoSys -IsDataRoot -SandboxMode -ExpectedServiceName \$ServiceName) {
  throw 'DataRoot missing SYSTEM FullControl must be rejected'
}
Write-InstallerDiagnosticLog -DataRoot \$dataRootNoSys -ExitCode 74 -Code 'ERR_T20_NO_SYS' -Message 'Must reject DataRoot without SYSTEM'
if (Test-Path (Join-Path \$dataRootNoSys 'logs')) {
  throw 'logs must NOT be created when SYSTEM ACE is missing on DataRoot'
}

# 5. Mevcut guvenli DataRoot altinda yeni logs olusturulurken icacls hata verirse log yazimi durur ve ExitCode 74 korunur
[MmsSafeDiagnosticLogWriter]::CreateDirectoryWithStrictSecurity('${dataRootLogsIcaclsFail.path.replaceAll("'", "''")}', \$true)
\$script:DiagnosticIcaclsPath = '${fakeFailIcacls.path.replaceAll("'", "''")}'
\$ProgramDataRoot = '${dataRootLogsIcaclsFail.path.replaceAll("'", "''")}'
Fail-Installer -ExitCode 74 -Code 'ERR_T20_LOGS_ICACLS_FAIL' -Message 'Original error preserved when logs icacls fails'
''');
      final t20Res = await runPsFile(t20Script.path, const []);
      expect(
        t20Res.exitCode,
        equals(74),
        reason: '${t20Res.stdout}\n${t20Res.stderr}',
      );
      expect(t20Res.stderr.toString(), contains('[ERR_T20_LOGS_ICACLS_FAIL]'));
      expect(
        File(
          p.join(
            dataRootLogsIcaclsFail.path,
            'logs',
            'installer-diagnostics.log',
          ),
        ).existsSync(),
        isFalse,
      );

      // 2a & 7: Gercek motor Install akisinda Users yazma izinli guvensiz DataRoot reddedilir, log yazilmaz ve ExitCode 74 + orijinal hata korunur
      final unsafeRoot = Directory(
        p.join(tempRoot.path, 't20_unsafe_users_root'),
      )..createSync(recursive: true);
      final grantUsersRoot = Process.runSync('icacls.exe', [
        unsafeRoot.path,
        '/grant',
        '*S-1-5-32-545:(OI)(CI)M',
      ]);
      expect(grantUsersRoot.exitCode, equals(0));
      final unsafeRootInst = Directory(
        p.join(tempRoot.path, 't20_inst_unsafe_root'),
      );
      final unsafeRootEngineRes = await runEngine(
        action: 'Install',
        installDir: unsafeRootInst,
        programDataRoot: unsafeRoot,
        stagingDir: staging,
        msiManaged: true,
        faultInjection: 'ServiceInstall',
      );
      expect(unsafeRootEngineRes.exitCode, equals(74));
      expect(
        unsafeRootEngineRes.stderr.toString(),
        contains('ERR_INSTALLER_STEP_FAILED'),
      );
      expect(
        File(p.join(unsafeRoot.path, 'logs', 'installer-diagnostics.log'))
            .existsSync(),
        isFalse,
      );

      // 6 & 7: DataRoot kendisi bir junction/reparse point oldugunda reddedilir ve ExitCode 74 + orijinal hata korunur
      final outsideRootTarget = Directory(
        p.join(tempRoot.path, 't20_outside_root_junc'),
      )..createSync(recursive: true);
      final rootJuncPath = p.join(tempRoot.path, 't20_dataroot_junc');
      final mkRootJunc = Process.runSync('cmd', [
        '/c',
        'mklink',
        '/J',
        rootJuncPath,
        outsideRootTarget.path,
      ]);
      expect(
        mkRootJunc.exitCode,
        equals(0),
        reason: '${mkRootJunc.stdout}\n${mkRootJunc.stderr}',
      );
      try {
        final rootJuncScript = File(p.join(tempRoot.path, 't20_root_junc.ps1'));
        rootJuncScript.writeAsStringSync('''
${buildEngineAstBootstrap()}
\$Action = 'Install'
\$AppVersion = '1.0.0'
\$MsiManaged = \$true
\$TestSandboxMode = [switch]::Present
\$ProgramDataRoot = '${rootJuncPath.replaceAll("'", "''")}'
Fail-Installer -ExitCode 74 -Code 'ERR_T20_DATAROOT_JUNC' -Message 'DataRoot junction must abort log write and keep ExitCode 74'
''');
        final rootJuncRes = await runPsFile(rootJuncScript.path, const []);
        expect(rootJuncRes.exitCode, equals(74));
        expect(
          rootJuncRes.stderr.toString(),
          contains('[ERR_T20_DATAROOT_JUNC]'),
        );
        expect(outsideRootTarget.listSync(), isEmpty);
      } finally {
        Process.runSync('cmd', ['/c', 'rmdir', rootJuncPath]);
      }
    });

    test('21. BLOCKER-1 & BLOCKER-2: Gercek setup_service_acls.ps1 icacls/takeown, inheritance, Service SID ve ACL failure rollback dogrulamasi', () async {
      final setupAclScript = p.join(
        repoRoot,
        'test_spikes',
        'spike_01_backend',
        'scripts',
        'setup_service_acls.ps1',
      );
      expect(File(setupAclScript).existsSync(), isTrue);

      // 1 & 2 & 3 & 4 & 5: Gercek icacls + takeown + stale explicit Users ACE temizligi (salt-okunur Dnscache SID ile)
      final tmpMappedBase = Directory(
        p.join(tempRoot.path, 't21_mapped_dnscache'),
      )..createSync(recursive: true);
      final mappedVerifyScript = File(
        p.join(tempRoot.path, 't21_verify_mapped.ps1'),
      );
      mappedVerifyScript.writeAsStringSync('''
\$ErrorActionPreference = 'Stop'
${buildEngineAstBootstrap()}
\$baseDir = '${tmpMappedBase.path.replaceAll("'", "''")}'
foreach (\$d in @('bin', 'bin\\broker', 'bin\\lib', 'lib', 'config', 'certs', 'data', 'security', 'logs', 'backups', 'run')) {
  New-Item -ItemType Directory -Path (Join-Path \$baseDir \$d) -Force | Out-Null
}
\$staleFile = Join-Path \$baseDir 'data\\stale.txt'
[System.IO.File]::WriteAllText(\$staleFile, 'SENSITIVE_DB_DATA')
foreach (\$p in @(\$baseDir, (Join-Path \$baseDir 'data'), (Join-Path \$baseDir 'security'), (Join-Path \$baseDir 'config'), (Join-Path \$baseDir 'certs'), (Join-Path \$baseDir 'logs'), (Join-Path \$baseDir 'bin'), (Join-Path \$baseDir 'bin\\lib'), (Join-Path \$baseDir 'lib'))) {
  & icacls.exe \$p /grant '*S-1-5-32-545:(OI)(CI)M' /Q | Out-Null
  if (\$LASTEXITCODE -ne 0) { throw "Pre-seed failed for \$p" }
}
& icacls.exe \$staleFile /grant '*S-1-5-32-545:M' /Q | Out-Null
if (\$LASTEXITCODE -ne 0) { throw 'Pre-seed failed for stale.txt' }

& '${setupAclScript.replaceAll("'", "''")}' -BaseDir \$baseDir -ServiceName 'Dnscache' -TestSandboxMode
if (\$LASTEXITCODE -ne 0) { throw "setup_service_acls.ps1 exited with \$LASTEXITCODE" }

\$svcSid = Resolve-WindowsServiceSid -TargetServiceName 'Dnscache'
if (\$svcSid -notmatch '^S-1-5-80(?:-\\d+){5}\$') { throw "Invalid Dnscache SID: \$svcSid" }

function Get-AclEntryMap {
  param([string]\$PathToCheck, [switch]\$AllowInherited)
  \$di = New-Object System.IO.DirectoryInfo(\$PathToCheck)
  \$ds = \$di.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
  if (-not \$AllowInherited -and -not \$ds.AreAccessRulesProtected) { throw "DACL not protected on \$PathToCheck" }
  \$map = @{}
  foreach (\$r in \$ds.Access) {
    \$s = if (\$r.IdentityReference -is [System.Security.Principal.SecurityIdentifier]) { \$r.IdentityReference.Value } else { \$r.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value }
    if (-not \$map.ContainsKey(\$s)) { \$map[\$s] = @() }
    \$map[\$s] += \$r
  }
  return \$map
}

\$rootMap = Get-AclEntryMap \$baseDir
if (-not \$rootMap.ContainsKey('S-1-5-18') -or (([int]\$rootMap['S-1-5-18'][0].FileSystemRights -band 0x001F01FF) -ne 0x001F01FF)) { throw 'Root missing SYSTEM FullControl' }
if (-not \$rootMap.ContainsKey('S-1-5-32-544') -or (([int]\$rootMap['S-1-5-32-544'][0].FileSystemRights -band 0x001F01FF) -ne 0x001F01FF)) { throw 'Root missing Admins FullControl' }
foreach (\$travSid in @('S-1-5-32-545', \$svcSid)) {
  if (-not \$rootMap.ContainsKey(\$travSid)) { throw "Root missing \$travSid" }
  \$ace = \$rootMap[\$travSid][0]
  if (\$ace.InheritanceFlags -ne [System.Security.AccessControl.InheritanceFlags]::None -or \$ace.PropagationFlags -ne [System.Security.AccessControl.PropagationFlags]::None) {
    throw "Root \$travSid must not inherit: Inh=\$(\$ace.InheritanceFlags)"
  }
  if (([int]\$ace.FileSystemRights -band (-bnot 0x00100020)) -ne 0) {
    throw "Root \$travSid must be traverse-only, got \$([int]\$ace.FileSystemRights)"
  }
}

# Root altinda yeni alt dizin olusturuldugunda Users:(X) kalitsal olmamali
\$freshRootChild = Join-Path \$baseDir 'fresh_probe_child'
New-Item -ItemType Directory -Path \$freshRootChild -Force | Out-Null
\$freshRootChildMap = Get-AclEntryMap -PathToCheck \$freshRootChild -AllowInherited
if (\$freshRootChildMap.ContainsKey('S-1-5-32-545') -or \$freshRootChildMap.ContainsKey(\$svcSid)) {
  throw 'Non-inheriting (X) leaked to fresh child under root!'
}
if (-not \$freshRootChildMap.ContainsKey('S-1-5-18') -or -not \$freshRootChildMap.ContainsKey('S-1-5-32-544')) {
  throw 'fresh_probe_child missing inherited SYSTEM/Admins from root'
}

# bin/ ve bin/lib/ ve bin/broker/
\$binMap = Get-AclEntryMap (Join-Path \$baseDir 'bin')
if (([int]\$binMap['S-1-5-32-545'][0].FileSystemRights -band (-bnot 0x00100020)) -ne 0 -or \$binMap['S-1-5-32-545'][0].InheritanceFlags -ne [System.Security.AccessControl.InheritanceFlags]::None) {
  throw 'bin Users must be non-inheriting traverse-only'
}
if (([int]\$binMap[\$svcSid][0].FileSystemRights -band 0x001200A9) -ne 0x001200A9) { throw 'bin svcSid missing RX' }

\$binLibMap = Get-AclEntryMap -PathToCheck (Join-Path \$baseDir 'bin\\lib') -AllowInherited
if (\$binLibMap.ContainsKey('S-1-5-32-545')) { throw 'bin\\lib leaked Users SID!' }
if (([int]\$binLibMap['S-1-5-18'][0].FileSystemRights -band 0x001F01FF) -ne 0x001F01FF) { throw 'bin\\lib missing SYSTEM FullControl' }
if (([int]\$binLibMap['S-1-5-32-544'][0].FileSystemRights -band 0x001F01FF) -ne 0x001F01FF) { throw 'bin\\lib missing Admins FullControl' }
if (([int]\$binLibMap[\$svcSid][0].FileSystemRights -band 0x001200A9) -ne 0x001200A9) { throw 'bin\\lib missing svcSid RX' }

\$freshBinLibFile = Join-Path \$baseDir 'bin\\lib\\probe.dll'
[System.IO.File]::WriteAllText(\$freshBinLibFile, 'dll')
\$binLibFileAcl = (Get-Acl -LiteralPath \$freshBinLibFile).Access | ForEach-Object { \$_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value }
if (\$binLibFileAcl -contains 'S-1-5-32-545') { throw 'Users leaked into bin\\lib child file!' }

\$brokerMap = Get-AclEntryMap (Join-Path \$baseDir 'bin\\broker')
if (([int]\$brokerMap['S-1-5-32-545'][0].FileSystemRights -band 0x001200A9) -ne 0x001200A9) { throw 'bin\\broker missing Users RX' }
if (([int]\$brokerMap[\$svcSid][0].FileSystemRights -band 0x001200A9) -ne 0x001200A9) { throw 'bin\\broker missing svcSid RX' }

# Kritik alt dizinler + stale.txt temizligi
foreach (\$rwDir in @('data', 'logs', 'backups', 'run', 'security')) {
  \$m = Get-AclEntryMap (Join-Path \$baseDir \$rwDir)
  foreach (\$bad in @('S-1-5-32-545', 'S-1-1-0', 'S-1-5-11')) {
    if (\$m.ContainsKey(\$bad)) { throw "\$rwDir still contains \$bad" }
  }
  if (([int]\$m[\$svcSid][0].FileSystemRights -band 0x001301BF) -ne 0x001301BF) { throw "\$rwDir missing svcSid Modify" }
}
foreach (\$roDir in @('config', 'certs', 'lib')) {
  \$m = Get-AclEntryMap (Join-Path \$baseDir \$roDir)
  foreach (\$bad in @('S-1-5-32-545', 'S-1-1-0', 'S-1-5-11')) {
    if (\$m.ContainsKey(\$bad)) { throw "\$roDir still contains \$bad" }
  }
  \$reqMask = if (\$roDir -eq 'lib') { 0x001200A9 } else { 0x00120089 }
  if (([int]\$m[\$svcSid][0].FileSystemRights -band \$reqMask) -ne \$reqMask) { throw "\$roDir missing expected svcSid mask" }
}
\$staleAclSids = (Get-Acl -LiteralPath \$staleFile).Access | ForEach-Object { \$_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value }
if (\$staleAclSids -contains 'S-1-5-32-545') { throw 'Pre-existing explicit Users ACE survived on data\\stale.txt!' }
if (-not (\$staleAclSids -contains \$svcSid)) { throw 'Service SID did not propagate onto existing data\\stale.txt!' }

# MmsSafeDiagnosticLogWriter root & logs guvenlik dogrulamasi
if (-not (Test-IsSafeDiagnosticDirectorySecurity -DirectoryPath \$baseDir -IsDataRoot -SandboxMode -ExpectedServiceName 'Dnscache')) {
  throw 'ValidateDirectoryPathSecurity failed on setup_service_acls root'
}
if (-not (Test-IsSafeDiagnosticDirectorySecurity -DirectoryPath (Join-Path \$baseDir 'logs') -SandboxMode -ExpectedServiceName 'Dnscache')) {
  throw 'ValidateDirectoryPathSecurity failed on setup_service_acls logs'
}
Write-Output 'MAPPED_ACL_MATRIX_OK'
''');
      final mappedRes = await runPsFile(mappedVerifyScript.path, const []);
      expect(
        mappedRes.exitCode,
        equals(0),
        reason: '${mappedRes.stdout}\n${mappedRes.stderr}',
      );
      expect(mappedRes.stdout.toString(), contains('MAPPED_ACL_MATRIX_OK'));

      // 6: SCM'de kayitli olmayan MarketMMSService icin sc.exe showsid cozumlemesi + taze kurulum ACL
      final tmpUnregBase = Directory(
        p.join(tempRoot.path, 't21_unreg_marketmms'),
      )..createSync(recursive: true);
      final unregVerifyScript = File(
        p.join(tempRoot.path, 't21_verify_unreg.ps1'),
      );
      unregVerifyScript.writeAsStringSync('''
\$ErrorActionPreference = 'Stop'
${buildEngineAstBootstrap()}
\$baseDir = '${tmpUnregBase.path.replaceAll("'", "''")}'
\$dataDir = Join-Path \$baseDir 'data'
New-Item -ItemType Directory -Path \$dataDir -Force | Out-Null
\$staleUnreg = Join-Path \$dataDir 'existing.db'
[System.IO.File]::WriteAllText(\$staleUnreg, 'DB')
& icacls.exe \$dataDir /grant '*S-1-5-32-545:(OI)(CI)M' /Q | Out-Null
& icacls.exe \$staleUnreg /grant '*S-1-5-32-545:M' /Q | Out-Null

& '${setupAclScript.replaceAll("'", "''")}' -BaseDir \$baseDir -ServiceName 'MarketMMSService' -TestSandboxMode
if (\$LASTEXITCODE -ne 0) { throw "Unregistered setup_service_acls.ps1 exited with \$LASTEXITCODE" }

\$resolvedMmsSid = Resolve-WindowsServiceSid -TargetServiceName 'MarketMMSService'
if (\$resolvedMmsSid -ne 'S-1-5-80-797541623-321148302-3770705866-2770528629-4185066158') {
  throw "Unexpected MarketMMSService SID: \$resolvedMmsSid"
}

foreach (\$checkSub in @('data', 'security', 'config', 'certs', 'logs', 'backups', 'run', 'lib')) {
  \$p = Join-Path \$baseDir \$checkSub
  \$sids = (Get-Acl -LiteralPath \$p).Access | ForEach-Object {
    if (\$_.IdentityReference -is [System.Security.Principal.SecurityIdentifier]) { \$_.IdentityReference.Value } else { \$_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value }
  }
  if (\$sids -contains 'S-1-5-32-545') { throw "\$checkSub leaked Users SID in fresh MarketMMSService run" }
  if (-not (\$sids -contains \$resolvedMmsSid)) { throw "\$checkSub missing MarketMMSService SID" }
}
\$staleUnregSids = (Get-Acl -LiteralPath \$staleUnreg).Access | ForEach-Object {
  if (\$_.IdentityReference -is [System.Security.Principal.SecurityIdentifier]) { \$_.IdentityReference.Value } else { \$_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value }
}
if (\$staleUnregSids -contains 'S-1-5-32-545') { throw 'Pre-existing Users ACE survived on stale file in unregistered SID path!' }

if (-not (Test-IsSafeDiagnosticDirectorySecurity -DirectoryPath \$baseDir -IsDataRoot -SandboxMode -ExpectedServiceName 'MarketMMSService')) {
  throw 'ValidateDirectoryPathSecurity failed on fresh MarketMMSService root'
}
if (-not (Test-IsSafeDiagnosticDirectorySecurity -DirectoryPath (Join-Path \$baseDir 'logs') -SandboxMode -ExpectedServiceName 'MarketMMSService')) {
  throw 'ValidateDirectoryPathSecurity failed on fresh MarketMMSService logs'
}
Write-Output 'UNREGISTERED_MMS_SID_OK'
''');
      final unregRes = await runPsFile(unregVerifyScript.path, const []);
      expect(
        unregRes.exitCode,
        equals(0),
        reason: '${unregRes.stdout}\n${unregRes.stderr}',
      );
      expect(unregRes.stdout.toString(), contains('UNREGISTERED_MMS_SID_OK'));

      // 7: ACL hatasi sirasinda hem FreshInstall hem Upgrade akislarinda ExitCode 74 ve servis/dosya rollback korunur
      final staging21 = createSyntheticStaging('t21_rb');
      final freshInst = Directory(p.join(tempRoot.path, 't21_rb_fresh_inst'));
      final freshData = Directory(p.join(tempRoot.path, 't21_rb_fresh_data'));
      Directory(p.join(freshData.path, 'data')).createSync(recursive: true);
      final freshDb = File(p.join(freshData.path, 'data', 'market_master.db'))
        ..writeAsStringSync('FRESH_DB_UNTOUCHED');
      seedSyntheticCerts(freshData);

      final freshAclFail = await runEngine(
        action: 'Install',
        installDir: freshInst,
        programDataRoot: freshData,
        stagingDir: staging21,
        faultInjection: 'Acl',
      );
      expect(freshAclFail.exitCode, equals(74));
      expect(
        File(p.join(freshData.path, 'run', 'sandbox_scm.json')).existsSync(),
        isFalse,
        reason: 'Servis kaydi sonrasindaki Acl hatasi yeni servisi geri almali',
      );
      expect(freshDb.readAsStringSync(), equals('FRESH_DB_UNTOUCHED'));
      final txFresh = jsonDecode(
        File(p.join(freshData.path, 'run', 'installer_tx_state.json'))
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(txFresh['status'], equals('ROLLED_BACK'));

      // Upgrade Acl failure rollback
      final upgInst = Directory(p.join(tempRoot.path, 't21_rb_upg_inst'));
      final upgData = Directory(p.join(tempRoot.path, 't21_rb_upg_data'));
      final stage10 = createSyntheticStaging('t21_v10');
      final stage11 = createSyntheticStaging('t21_v11');
      seedSyntheticCerts(upgData);
      final baseOk = await runEngine(
        action: 'Install',
        installDir: upgInst,
        programDataRoot: upgData,
        stagingDir: stage10,
        appVersion: '1.0.0',
      );
      expect(
        baseOk.exitCode,
        equals(0),
        reason: '${baseOk.stdout}\n${baseOk.stderr}',
      );
      final upgDb = File(p.join(upgData.path, 'data', 'market_master.db'))
        ..writeAsStringSync('UPGRADE_DB_CRITICAL');

      final upgAclFail = await runEngine(
        action: 'Install',
        installDir: upgInst,
        programDataRoot: upgData,
        stagingDir: stage11,
        appVersion: '1.1.0',
        faultInjection: 'Acl',
      );
      expect(upgAclFail.exitCode, equals(74));
      expect(upgDb.readAsStringSync(), equals('UPGRADE_DB_CRITICAL'));
      final scmRestored = jsonDecode(
        File(p.join(upgData.path, 'run', 'sandbox_scm.json'))
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(scmRestored['version'], equals('1.0.0'));
      expect(scmRestored['status'], equals('Running'));
    });

    test('22. H-1 & M-4: Standalone/MSI admin_secret ACL, Upgrade Rollback bin/lib ACL yenileme ve ACL hatasinda servis engeli', () async {
      final setupAclScript = p.join(
        repoRoot,
        'test_spikes',
        'spike_01_backend',
        'scripts',
        'setup_service_acls.ps1',
      );

      // M-4A) Standalone setup_service_acls.ps1 hem mapped (Dnscache) hem unmapped (MarketMMSService) icin admin_secret.txt'yi Read-only kilitlemeli
      for (final svc in ['Dnscache', 'MarketMMSService']) {
        final standaloneDir = Directory(p.join(tempRoot.path, 't22_m4_$svc'))
          ..createSync(recursive: true);
        final secDir = Directory(p.join(standaloneDir.path, 'security'))
          ..createSync(recursive: true);
        final secFile = File(p.join(secDir.path, 'admin_secret.txt'))
          ..writeAsStringSync('STANDALONE_SECRET_DO_NOT_WIDEN');

        final psCheck = File(p.join(tempRoot.path, 't22_check_m4_$svc.ps1'));
        psCheck.writeAsStringSync('''
\$ErrorActionPreference = 'Stop'
${buildEngineAstBootstrap()}
\$baseDir = '${standaloneDir.path.replaceAll("'", "''")}'
\$secFile = '${secFile.path.replaceAll("'", "''")}'
& icacls.exe \$secFile /grant '*S-1-5-32-545:M' /Q | Out-Null
\$svcSid = Resolve-WindowsServiceSid -TargetServiceName '$svc'
if (-not \$svcSid) { throw 'Failed to resolve SID for $svc' }

# Pre-seed Modify ACE for ServiceSID to simulate upgrade/re-run before setup_service_acls.ps1
\$fiPre = New-Object System.IO.FileInfo(\$secFile)
\$fsPre = \$fiPre.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
\$fsPre.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
  (New-Object System.Security.Principal.SecurityIdentifier(\$svcSid)),
  [System.Security.AccessControl.FileSystemRights]::Modify,
  [System.Security.AccessControl.InheritanceFlags]::None,
  [System.Security.AccessControl.PropagationFlags]::None,
  [System.Security.AccessControl.AccessControlType]::Allow
)))
\$fiPre.SetAccessControl(\$fsPre)

& '${setupAclScript.replaceAll("'", "''")}' -BaseDir \$baseDir -ServiceName '$svc' -TestSandboxMode
if (\$LASTEXITCODE -ne 0) { throw "setup_service_acls failed for $svc (\$LASTEXITCODE)" }

if (-not (Test-AdminSecretReadOnlyAcl -FilePath \$secFile -ExpectedServiceSid \$svcSid -SandboxMode)) {
  throw "admin_secret.txt failed Read-only ACL verification after standalone setup_service_acls.ps1 ($svc)"
}
Write-Output "M4_STANDALONE_${svc}_OK"
''');
        final m4Res = await runPsFile(psCheck.path, const []);
        expect(
          m4Res.exitCode,
          equals(0),
          reason: '${m4Res.stdout}\n${m4Res.stderr}',
        );
        expect(m4Res.stdout.toString(), contains('M4_STANDALONE_${svc}_OK'));
        expect(
          secFile.readAsStringSync(),
          equals('STANDALONE_SECRET_DO_NOT_WIDEN'),
        );
      }

      // H-1 & M-4B) Motor FreshInstall -> Upgrade v1.1.0 HealthCheck hatasi -> Rollback sonrasi bin/lib/admin_secret ACL + dogru SID/LocalService + Running
      final instH1 = Directory(p.join(tempRoot.path, 't22_h1_inst'));
      final dataH1 = Directory(p.join(tempRoot.path, 't22_h1_data'));
      final stage10 = createSyntheticStaging('t22_v10');
      final stage11 = createSyntheticStaging('t22_v11');
      for (final st in [stage10, stage11]) {
        File(p.join(st.path, 'hub_scripts', 'setup_service_acls.ps1'))
            .writeAsStringSync('# synthetic acl script\n');
        File(p.join(st.path, 'hub_scripts', 'configure_hub_firewall.ps1'))
            .writeAsStringSync('# synthetic firewall script\n');
      }
      seedSyntheticCerts(dataH1);

      final freshOk = await runEngine(
        action: 'Install',
        installDir: instH1,
        programDataRoot: dataH1,
        stagingDir: stage10,
        appVersion: '1.0.0',
      );
      expect(
        freshOk.exitCode,
        equals(0),
        reason: '${freshOk.stdout}\n${freshOk.stderr}',
      );
      File(p.join(dataH1.path, 'data', 'market_master.db'))
          .writeAsStringSync('H1_CRITICAL_USER_DB');

      final upgFail = await runEngine(
        action: 'Install',
        installDir: instH1,
        programDataRoot: dataH1,
        stagingDir: stage11,
        appVersion: '1.1.0',
        faultInjection: 'HealthCheck',
        msiManaged: true,
      );
      expect(upgFail.exitCode, equals(74));

      final rbOk = await runEngine(
        action: 'Rollback',
        installDir: instH1,
        programDataRoot: dataH1,
        appVersion: '1.1.0',
        msiManaged: true,
      );
      expect(
        rbOk.exitCode,
        equals(0),
        reason: '${rbOk.stdout}\n${rbOk.stderr}',
      );

      // Rollback sonrasi bin, bin\lib, lib ve admin_secret ACL dogrulamasi
      final h1AclCheck = File(p.join(tempRoot.path, 't22_h1_acl_check.ps1'));
      h1AclCheck.writeAsStringSync('''
\$ErrorActionPreference = 'Stop'
${buildEngineAstBootstrap()}
\$baseDir = '${dataH1.path.replaceAll("'", "''")}'
\$svcSid = Resolve-WindowsServiceSid -TargetServiceName 'MarketMMSService'
if (\$svcSid -ne 'S-1-5-80-797541623-321148302-3770705866-2770528629-4185066158') { throw "Wrong SID: \$svcSid" }

foreach (\$d in @('bin', 'lib', 'bin\\lib')) {
  \$p = Join-Path \$baseDir \$d
  \$di = New-Object System.IO.DirectoryInfo(\$p)
  \$ds = \$di.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
  if (\$d -ne 'bin\\lib' -and -not \$ds.AreAccessRulesProtected) { throw "\$d not protected" }
  \$hasSvcRx = \$false; \$hasSys = \$false; \$hasAdm = \$false
  foreach (\$r in \$ds.Access) {
    \$s = if (\$r.IdentityReference -is [System.Security.Principal.SecurityIdentifier]) { \$r.IdentityReference.Value } else { \$r.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value }
    if (\$s -eq 'S-1-5-32-545' -or \$s -eq 'S-1-1-0' -or \$s -eq 'S-1-5-11') { throw "\$d leaked \$s" }
    \$m = [int]\$r.FileSystemRights
    if (\$s -eq \$svcSid -and ((\$m -band 0x001200A9) -eq 0x001200A9)) { \$hasSvcRx = \$true }
    if (\$s -eq 'S-1-5-18' -and ((\$m -band 0x001F01FF) -eq 0x001F01FF)) { \$hasSys = \$true }
    if (\$s -eq 'S-1-5-32-544' -and ((\$m -band 0x001F01FF) -eq 0x001F01FF)) { \$hasAdm = \$true }
  }
  if (-not (\$hasSvcRx -and \$hasSys -and \$hasAdm)) { throw "\$d missing required ACL (Svc=\$hasSvcRx Sys=\$hasSys Adm=\$hasAdm)" }
}
\$secPath = Join-Path \$baseDir 'security\\admin_secret.txt'
if (-not (Test-AdminSecretReadOnlyAcl -FilePath \$secPath -ExpectedServiceSid \$svcSid -SandboxMode)) {
  throw 'Post-rollback admin_secret.txt failed Read-only check'
}
Write-Output 'H1_POST_ROLLBACK_ACL_OK'
''');
      final h1AclRes = await runPsFile(h1AclCheck.path, const []);
      expect(
        h1AclRes.exitCode,
        equals(0),
        reason: '${h1AclRes.stdout}\n${h1AclRes.stderr}',
      );
      expect(h1AclRes.stdout.toString(), contains('H1_POST_ROLLBACK_ACL_OK'));

      final scmH1 = jsonDecode(
        File(p.join(dataH1.path, 'run', 'sandbox_scm.json')).readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(scmH1['service_name'], equals('MarketMMSService'));
      expect(scmH1['account'], equals(r'NT AUTHORITY\LocalService'));
      expect(scmH1['sid_type'], equals('UNRESTRICTED'));
      expect(scmH1['version'], equals('1.0.0'));
      expect(scmH1['status'], equals('Running'));
      expect(
        File(p.join(dataH1.path, 'data', 'market_master.db'))
            .readAsStringSync(),
        equals('H1_CRITICAL_USER_DB'),
      );

      // H-1 ACL Fail Gate: Rollback sirasinda ACL basarisizsa eski servis Stopped kalir ve ROLLED_BACK isaretlenmez
      final instGate = Directory(p.join(tempRoot.path, 't22_gate_inst'));
      final dataGate = Directory(p.join(tempRoot.path, 't22_gate_data'));
      seedSyntheticCerts(dataGate);
      expect(
        (await runEngine(
          action: 'Install',
          installDir: instGate,
          programDataRoot: dataGate,
          stagingDir: stage10,
          appVersion: '1.0.0',
        )).exitCode,
        equals(0),
      );
      File(p.join(dataGate.path, 'data', 'market_master.db'))
          .writeAsStringSync('GATE_DB_INTACT');
      expect(
        (await runEngine(
          action: 'Install',
          installDir: instGate,
          programDataRoot: dataGate,
          stagingDir: stage11,
          appVersion: '1.1.0',
          faultInjection: 'Migration',
          msiManaged: true,
        )).exitCode,
        equals(74),
      );

      final rbAclFail = await runEngine(
        action: 'Rollback',
        installDir: instGate,
        programDataRoot: dataGate,
        appVersion: '1.1.0',
        faultInjection: 'RollbackAcl',
        msiManaged: true,
      );
      expect(rbAclFail.exitCode, equals(74));
      final scmGate = jsonDecode(
        File(p.join(dataGate.path, 'run', 'sandbox_scm.json'))
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(
        scmGate['status'],
        equals('Stopped'),
        reason: 'ACL hatasinda eski servis baslatilmamali',
      );
      final txGate = jsonDecode(
        File(p.join(dataGate.path, 'run', 'installer_tx_state.json'))
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(txGate['status'], equals('PARTIAL_ROLLBACK_FAILED'));
      expect(
        txGate['failed_steps'],
        containsAll(['reapply_acls', 'start_service']),
      );
      expect(
        File(p.join(dataGate.path, 'logs', 'installer-diagnostics.log'))
            .readAsStringSync(),
        contains('ERR_PARTIAL_ROLLBACK_FAILED'),
      );
      expect(
        File(p.join(dataGate.path, 'data', 'market_master.db'))
            .readAsStringSync(),
        equals('GATE_DB_INTACT'),
      );
    });

    test('23. M-2, M-3 & M-1: Rollback izolasyonu (Binary/Manifest/Firewall), Firewall geri alma ve bozuk TxState kurtarma', () async {
      final stage10 = createSyntheticStaging('t23_v10');
      final stage11 = createSyntheticStaging('t23_v11');
      for (final st in [stage10, stage11]) {
        File(p.join(st.path, 'hub_scripts', 'setup_service_acls.ps1'))
            .writeAsStringSync('# synthetic acl script\n');
        File(p.join(st.path, 'hub_scripts', 'configure_hub_firewall.ps1'))
            .writeAsStringSync('# synthetic firewall script\n');
      }

      // M-2A) Binary restore hatasi manifest restore'u engellemez, bin.previous silinmez, servis baslatilmaz, status PARTIAL_ROLLBACK_FAILED
      final instBinFail = Directory(p.join(tempRoot.path, 't23_binfail_inst'));
      final dataBinFail = Directory(p.join(tempRoot.path, 't23_binfail_data'));
      seedSyntheticCerts(dataBinFail);
      expect(
        (await runEngine(
          action: 'Install',
          installDir: instBinFail,
          programDataRoot: dataBinFail,
          stagingDir: stage10,
          appVersion: '1.0.0',
        )).exitCode,
        equals(0),
      );
      File(p.join(dataBinFail.path, 'data', 'market_master.db'))
          .writeAsStringSync('M2_BIN_FAIL_DB');
      expect(
        (await runEngine(
          action: 'Install',
          installDir: instBinFail,
          programDataRoot: dataBinFail,
          stagingDir: stage11,
          appVersion: '1.1.0',
          faultInjection: 'HealthCheck',
          msiManaged: true,
        )).exitCode,
        equals(74),
      );
      final rbBinFail = await runEngine(
        action: 'Rollback',
        installDir: instBinFail,
        programDataRoot: dataBinFail,
        appVersion: '1.1.0',
        faultInjection: 'RollbackBinary',
        msiManaged: true,
      );
      expect(rbBinFail.exitCode, equals(74));
      expect(
        Directory(p.join(dataBinFail.path, 'bin.previous')).existsSync(),
        isTrue,
      );
      final manifestAfterBinFail = jsonDecode(
        File(p.join(dataBinFail.path, 'config', 'install_manifest.json'))
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(manifestAfterBinFail['app_version'], equals('1.0.0'));
      final txBinFail = jsonDecode(
        File(p.join(dataBinFail.path, 'run', 'installer_tx_state.json'))
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(txBinFail['status'], equals('PARTIAL_ROLLBACK_FAILED'));
      expect(txBinFail['failed_steps'], contains('restore_binaries'));
      expect(
        File(p.join(dataBinFail.path, 'data', 'market_master.db'))
            .readAsStringSync(),
        equals('M2_BIN_FAIL_DB'),
      );

      // M-2B) Manifest restore hatasi binary restore'u engellemez, install_manifest.previous.json korunur
      final instManFail = Directory(p.join(tempRoot.path, 't23_manfail_inst'));
      final dataManFail = Directory(p.join(tempRoot.path, 't23_manfail_data'));
      seedSyntheticCerts(dataManFail);
      expect(
        (await runEngine(
          action: 'Install',
          installDir: instManFail,
          programDataRoot: dataManFail,
          stagingDir: stage10,
          appVersion: '1.0.0',
        )).exitCode,
        equals(0),
      );
      expect(
        (await runEngine(
          action: 'Install',
          installDir: instManFail,
          programDataRoot: dataManFail,
          stagingDir: stage11,
          appVersion: '1.1.0',
          faultInjection: 'HealthCheck',
          msiManaged: true,
        )).exitCode,
        equals(74),
      );
      final rbManFail = await runEngine(
        action: 'Rollback',
        installDir: instManFail,
        programDataRoot: dataManFail,
        appVersion: '1.1.0',
        faultInjection: 'RollbackManifest',
        msiManaged: true,
      );
      expect(rbManFail.exitCode, equals(74));
      expect(
        File(
          p.join(dataManFail.path, 'config', 'install_manifest.previous.json'),
        ).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(dataManFail.path, 'bin', 'mms_backend.exe'))
            .readAsStringSync(),
        contains('t23_v10'),
      );
      final txManFail = jsonDecode(
        File(p.join(dataManFail.path, 'run', 'installer_tx_state.json'))
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(txManFail['status'], equals('PARTIAL_ROLLBACK_FAILED'));
      expect(txManFail['failed_steps'], contains('restore_manifest'));

      // M-1A) Fresh Install sirasinda yalnizca bu transaction'in olusturdugu firewall kurali kaldirilir, digerleri korunur
      final instFw = Directory(p.join(tempRoot.path, 't23_fw_inst'));
      final dataFw = Directory(p.join(tempRoot.path, 't23_fw_data'));
      Directory(p.join(dataFw.path, 'run')).createSync(recursive: true);
      final sandboxFwFile =
          File(
            p.join(dataFw.path, 'run', 'sandbox_firewall.json'),
          )..writeAsStringSync(
            jsonEncode(['OtherApp-Custom-9999', 'MarketMMS-Hub-API-TCP-8945']),
          );
      final fwFailInstall = await runEngine(
        action: 'Install',
        installDir: instFw,
        programDataRoot: dataFw,
        stagingDir: stage10,
        faultInjection: 'ServiceStart',
        msiManaged: true,
      );
      expect(fwFailInstall.exitCode, equals(74));
      final duringTxFw = (jsonDecode(sandboxFwFile.readAsStringSync()) as List)
          .cast<String>();
      expect(
        duringTxFw,
        containsAll([
          'OtherApp-Custom-9999',
          'MarketMMS-Hub-API-TCP-8945',
          'MarketMMS-Hub-Discovery-UDP-8946',
        ]),
      );

      final fwRbOk = await runEngine(
        action: 'Rollback',
        installDir: instFw,
        programDataRoot: dataFw,
        msiManaged: true,
      );
      expect(
        fwRbOk.exitCode,
        equals(0),
        reason: '${fwRbOk.stdout}\n${fwRbOk.stderr}',
      );
      final afterRbFw = (jsonDecode(sandboxFwFile.readAsStringSync()) as List)
          .cast<String>();
      expect(
        afterRbFw,
        equals(['OtherApp-Custom-9999', 'MarketMMS-Hub-API-TCP-8945']),
      );
      expect(
        File(p.join(dataFw.path, 'run', 'sandbox_scm.json')).existsSync(),
        isFalse,
      );

      // M-1B) Firewall temizleme hatasi diger rollback adimlarini engellemez ve ayri raporlanir
      final instFwErr = Directory(p.join(tempRoot.path, 't23_fwerr_inst'));
      final dataFwErr = Directory(p.join(tempRoot.path, 't23_fwerr_data'));
      expect(
        (await runEngine(
          action: 'Install',
          installDir: instFwErr,
          programDataRoot: dataFwErr,
          stagingDir: stage10,
          faultInjection: 'ServiceStart',
          msiManaged: true,
        )).exitCode,
        equals(74),
      );
      final fwRbErr = await runEngine(
        action: 'Rollback',
        installDir: instFwErr,
        programDataRoot: dataFwErr,
        faultInjection: 'RollbackFirewall',
        msiManaged: true,
      );
      expect(fwRbErr.exitCode, equals(74));
      expect(
        File(p.join(dataFwErr.path, 'run', 'sandbox_scm.json')).existsSync(),
        isFalse,
      );
      final txFwErr = jsonDecode(
        File(p.join(dataFwErr.path, 'run', 'installer_tx_state.json'))
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(txFwErr['status'], equals('PARTIAL_ROLLBACK_FAILED'));
      expect(txFwErr['failed_steps'], contains('cleanup_firewall'));
      expect(
        File(p.join(dataFwErr.path, 'logs', 'installer-diagnostics.log'))
            .readAsStringSync(),
        contains('ERR_PARTIAL_ROLLBACK_FAILED'),
      );

      // M-3A) Bozuk birincil tx state -> gecerli installer_tx_state.previous.json uzerinden kurtarma ve tanilama logu
      final instPrevRec = Directory(p.join(tempRoot.path, 't23_m3a_inst'));
      final dataPrevRec = Directory(p.join(tempRoot.path, 't23_m3a_data'));
      seedSyntheticCerts(dataPrevRec);
      expect(
        (await runEngine(
          action: 'Install',
          installDir: instPrevRec,
          programDataRoot: dataPrevRec,
          stagingDir: stage10,
          appVersion: '1.0.0',
        )).exitCode,
        equals(0),
      );
      File(p.join(dataPrevRec.path, 'data', 'market_master.db'))
          .writeAsStringSync('M3_PREV_REC_DB');
      expect(
        (await runEngine(
          action: 'Install',
          installDir: instPrevRec,
          programDataRoot: dataPrevRec,
          stagingDir: stage11,
          appVersion: '1.1.0',
          faultInjection: 'HealthCheck',
          msiManaged: true,
        )).exitCode,
        equals(74),
      );
      final primaryTxA = File(
        p.join(dataPrevRec.path, 'run', 'installer_tx_state.json'),
      );
      final prevTxA = File(
        p.join(dataPrevRec.path, 'run', 'installer_tx_state.previous.json'),
      );
      expect(prevTxA.existsSync(), isTrue);
      primaryTxA.writeAsStringSync('{ BROKEN_PRIMARY_JSON');

      final rbPrevRec = await runEngine(
        action: 'Rollback',
        installDir: instPrevRec,
        programDataRoot: dataPrevRec,
        appVersion: '1.1.0',
        msiManaged: true,
      );
      expect(
        rbPrevRec.exitCode,
        equals(0),
        reason: '${rbPrevRec.stdout}\n${rbPrevRec.stderr}',
      );
      expect(
        File(p.join(dataPrevRec.path, 'bin', 'mms_backend.exe'))
            .readAsStringSync(),
        contains('t23_v10'),
      );
      expect(
        File(p.join(dataPrevRec.path, 'data', 'market_master.db'))
            .readAsStringSync(),
        equals('M3_PREV_REC_DB'),
      );
      expect(
        File(p.join(dataPrevRec.path, 'logs', 'installer-diagnostics.log'))
            .readAsStringSync(),
        contains('INFO_TX_STATE_RECOVERED_FROM_PREVIOUS'),
      );

      // M-3B) Birincil tx state bozuk + tx_state.previous yok -> gecerli install_manifest.previous.json kurtarmasi
      final instManRec = Directory(p.join(tempRoot.path, 't23_m3b_inst'));
      final dataManRec = Directory(p.join(tempRoot.path, 't23_m3b_data'));
      seedSyntheticCerts(dataManRec);
      expect(
        (await runEngine(
          action: 'Install',
          installDir: instManRec,
          programDataRoot: dataManRec,
          stagingDir: stage10,
          appVersion: '1.0.0',
        )).exitCode,
        equals(0),
      );
      expect(
        (await runEngine(
          action: 'Install',
          installDir: instManRec,
          programDataRoot: dataManRec,
          stagingDir: stage11,
          appVersion: '1.1.0',
          faultInjection: 'HealthCheck',
          msiManaged: true,
        )).exitCode,
        equals(74),
      );
      File(p.join(dataManRec.path, 'run', 'installer_tx_state.json'))
          .writeAsStringSync('{ BROKEN_PRIMARY_JSON');
      final prevTxB = File(
        p.join(dataManRec.path, 'run', 'installer_tx_state.previous.json'),
      );
      if (prevTxB.existsSync()) prevTxB.deleteSync();

      final rbManRec = await runEngine(
        action: 'Rollback',
        installDir: instManRec,
        programDataRoot: dataManRec,
        appVersion: '1.1.0',
        msiManaged: true,
      );
      expect(
        rbManRec.exitCode,
        equals(0),
        reason: '${rbManRec.stdout}\n${rbManRec.stderr}',
      );
      expect(
        File(p.join(dataManRec.path, 'bin', 'mms_backend.exe'))
            .readAsStringSync(),
        contains('t23_v10'),
      );
      expect(
        File(p.join(dataManRec.path, 'logs', 'installer-diagnostics.log'))
            .readAsStringSync(),
        contains('INFO_TX_STATE_RECOVERED_FROM_MANIFEST_PREVIOUS'),
      );

      // M-3C) Her iki tx state dosyasi da bozuksa tahminle silme/rollback yapilmaz, fail-closed ExitCode 74 ve kullanici verileri korunur
      final instBothCorrupt = Directory(p.join(tempRoot.path, 't23_m3c_inst'));
      final dataBothCorrupt = Directory(p.join(tempRoot.path, 't23_m3c_data'));
      seedSyntheticCerts(dataBothCorrupt);
      expect(
        (await runEngine(
          action: 'Install',
          installDir: instBothCorrupt,
          programDataRoot: dataBothCorrupt,
          stagingDir: stage10,
          appVersion: '1.0.0',
        )).exitCode,
        equals(0),
      );
      File(p.join(dataBothCorrupt.path, 'data', 'market_master.db'))
          .writeAsStringSync('M3_BOTH_CORRUPT_DB');
      expect(
        (await runEngine(
          action: 'Install',
          installDir: instBothCorrupt,
          programDataRoot: dataBothCorrupt,
          stagingDir: stage11,
          appVersion: '1.1.0',
          faultInjection: 'HealthCheck',
          msiManaged: true,
        )).exitCode,
        equals(74),
      );
      File(p.join(dataBothCorrupt.path, 'run', 'installer_tx_state.json'))
          .writeAsStringSync('{ BROKEN_PRIMARY');
      File(
        p.join(dataBothCorrupt.path, 'run', 'installer_tx_state.previous.json'),
      ).writeAsStringSync('{ BROKEN_PREVIOUS');

      final rbBothCorrupt = await runEngine(
        action: 'Rollback',
        installDir: instBothCorrupt,
        programDataRoot: dataBothCorrupt,
        appVersion: '1.1.0',
        msiManaged: true,
      );
      expect(rbBothCorrupt.exitCode, equals(74));
      expect(rbBothCorrupt.stderr.toString(), contains('ERR_TX_STATE_CORRUPT'));
      // Tahminle hicbir .previous veya bin veya DB silinmemis/degistirilmemis olmali
      expect(
        Directory(p.join(dataBothCorrupt.path, 'bin.previous')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(dataBothCorrupt.path, 'bin', 'mms_backend.exe'))
            .readAsStringSync(),
        contains('t23_v11'),
      );
      expect(
        File(p.join(dataBothCorrupt.path, 'data', 'market_master.db'))
            .readAsStringSync(),
        equals('M3_BOTH_CORRUPT_DB'),
      );
      expect(
        File(p.join(dataBothCorrupt.path, 'logs', 'installer-diagnostics.log'))
            .readAsStringSync(),
        contains('ERR_TX_STATE_CORRUPT'),
      );
    });

    test('24. M-3 Manifest Fallback Hardening: service_state, service_name, bin.previous ve fail-closed dogrulamalari', () async {
      final stage10 = createSyntheticStaging('t24_v10');
      final stage11 = createSyntheticStaging('t24_v11');
      for (final st in [stage10, stage11]) {
        File(p.join(st.path, 'hub_scripts', 'setup_service_acls.ps1'))
            .writeAsStringSync('# synthetic acl script\n');
        File(p.join(st.path, 'hub_scripts', 'configure_hub_firewall.ps1'))
            .writeAsStringSync('# synthetic firewall script\n');
      }

      Future<Directory> prepareFailedUpgrade({
        required String tag,
        required bool withCerts,
        required String dbContent,
        bool deleteTxFiles = false,
        bool corruptPrimaryTx = true,
      }) async {
        final inst = Directory(p.join(tempRoot.path, 't24_${tag}_inst'));
        final data = Directory(p.join(tempRoot.path, 't24_${tag}_data'));
        if (withCerts) seedSyntheticCerts(data);
        expect(
          (await runEngine(
            action: 'Install',
            installDir: inst,
            programDataRoot: data,
            stagingDir: stage10,
            appVersion: '1.0.0',
          )).exitCode,
          equals(0),
        );
        File(p.join(data.path, 'data', 'market_master.db'))
            .writeAsStringSync(dbContent);
        expect(
          (await runEngine(
            action: 'Install',
            installDir: inst,
            programDataRoot: data,
            stagingDir: stage11,
            appVersion: '1.1.0',
            faultInjection: 'ServiceStart',
            msiManaged: true,
          )).exitCode,
          equals(74),
        );
        final txFile = File(
          p.join(data.path, 'run', 'installer_tx_state.json'),
        );
        final prevTxFile = File(
          p.join(data.path, 'run', 'installer_tx_state.previous.json'),
        );
        if (prevTxFile.existsSync()) prevTxFile.deleteSync();
        if (deleteTxFiles) {
          if (txFile.existsSync()) txFile.deleteSync();
        } else if (corruptPrimaryTx) {
          txFile.writeAsStringSync('{ CORRUPT_TX');
        }
        return data;
      }

      // 1) Gecerli RUNNING manifest + gecerli bin.previous -> servis yeniden kurulur ve Running olur
      final dataRun = await prepareFailedUpgrade(
        tag: 'running',
        withCerts: true,
        dbContent: 'T24_RUNNING_DB',
      );
      final resRun = await runEngine(
        action: 'Rollback',
        installDir: Directory(p.join(tempRoot.path, 't24_running_inst')),
        programDataRoot: dataRun,
        appVersion: '1.1.0',
        msiManaged: true,
      );
      expect(
        resRun.exitCode,
        equals(0),
        reason: '${resRun.stdout}\n${resRun.stderr}',
      );
      final scmRun = jsonDecode(
        File(p.join(dataRun.path, 'run', 'sandbox_scm.json'))
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(scmRun['status'], equals('Running'));
      expect(scmRun['version'], equals('1.0.0'));
      expect(
        File(p.join(dataRun.path, 'bin', 'mms_backend.exe')).readAsStringSync(),
        contains('t24_v10'),
      );
      expect(
        File(p.join(dataRun.path, 'data', 'market_master.db'))
            .readAsStringSync(),
        equals('T24_RUNNING_DB'),
      );
      expect(
        File(p.join(dataRun.path, 'logs', 'installer-diagnostics.log'))
            .readAsStringSync(),
        contains('INFO_TX_STATE_RECOVERED_FROM_MANIFEST_PREVIOUS'),
      );

      // 2) Gecerli PENDING_TLS_PROVISIONING manifest + gecerli bin.previous -> servis geri yuklenir ama BASLATILMAZ (Stopped)
      final dataPending = await prepareFailedUpgrade(
        tag: 'pending_tls',
        withCerts: false,
        dbContent: 'T24_PENDING_DB',
      );
      final prevManifestPending = jsonDecode(
        File(
          p.join(dataPending.path, 'config', 'install_manifest.previous.json'),
        ).readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(
        prevManifestPending['service_state'],
        equals('PENDING_TLS_PROVISIONING'),
      );
      final resPending = await runEngine(
        action: 'Rollback',
        installDir: Directory(p.join(tempRoot.path, 't24_pending_tls_inst')),
        programDataRoot: dataPending,
        appVersion: '1.1.0',
        msiManaged: true,
      );
      expect(
        resPending.exitCode,
        equals(0),
        reason: '${resPending.stdout}\n${resPending.stderr}',
      );
      final scmPending = jsonDecode(
        File(p.join(dataPending.path, 'run', 'sandbox_scm.json'))
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(
        scmPending['status'],
        equals('Stopped'),
        reason:
            'PENDING_TLS_PROVISIONING onceki kurulumda servis baslatilmamali',
      );
      expect(scmPending['version'], equals('1.0.0'));
      expect(
        File(p.join(dataPending.path, 'bin', 'mms_backend.exe'))
            .readAsStringSync(),
        contains('t24_v10'),
      );
      expect(
        File(p.join(dataPending.path, 'data', 'market_master.db'))
            .readAsStringSync(),
        equals('T24_PENDING_DB'),
      );

      // 3) Yanlis service_name -> fail-closed (ExitCode 74, ERR_TX_STATE_CORRUPT, hicbir sey degistirilmez)
      final dataBadSvc = await prepareFailedUpgrade(
        tag: 'bad_svc',
        withCerts: true,
        dbContent: 'T24_BADSVC_DB',
      );
      final badSvcManifestFile = File(
        p.join(dataBadSvc.path, 'config', 'install_manifest.previous.json'),
      );
      final badSvcMap = jsonDecode(
        badSvcManifestFile.readAsStringSync(),
      ) as Map<String, dynamic>;
      badSvcMap['service_name'] = 'WrongOtherService';
      badSvcManifestFile.writeAsStringSync(jsonEncode(badSvcMap));
      final secBeforeBadSvc = File(
        p.join(dataBadSvc.path, 'security', 'admin_secret.txt'),
      ).readAsStringSync();

      final resBadSvc = await runEngine(
        action: 'Rollback',
        installDir: Directory(p.join(tempRoot.path, 't24_bad_svc_inst')),
        programDataRoot: dataBadSvc,
        appVersion: '1.1.0',
        msiManaged: true,
      );
      expect(resBadSvc.exitCode, equals(74));
      expect(resBadSvc.stderr.toString(), contains('ERR_TX_STATE_CORRUPT'));
      expect(
        jsonDecode(
          File(p.join(dataBadSvc.path, 'run', 'sandbox_scm.json'))
              .readAsStringSync(),
        )['status'],
        equals('Stopped'),
      );
      expect(
        File(p.join(dataBadSvc.path, 'bin', 'mms_backend.exe'))
            .readAsStringSync(),
        contains('t24_v11'),
      );
      expect(
        File(p.join(dataBadSvc.path, 'data', 'market_master.db'))
            .readAsStringSync(),
        equals('T24_BADSVC_DB'),
      );
      expect(
        File(p.join(dataBadSvc.path, 'security', 'admin_secret.txt'))
            .readAsStringSync(),
        equals(secBeforeBadSvc),
      );

      // 4) Eksik bin.previous -> mevcut bin eski surum sayilmaz, fail-closed
      final dataNoBinPrev = await prepareFailedUpgrade(
        tag: 'nobinprev',
        withCerts: true,
        dbContent: 'T24_NOBINPREV_DB',
      );
      Directory(p.join(dataNoBinPrev.path, 'bin.previous'))
          .deleteSync(recursive: true);
      final resNoBinPrev = await runEngine(
        action: 'Rollback',
        installDir: Directory(p.join(tempRoot.path, 't24_nobinprev_inst')),
        programDataRoot: dataNoBinPrev,
        appVersion: '1.1.0',
        msiManaged: true,
      );
      expect(resNoBinPrev.exitCode, equals(74));
      expect(resNoBinPrev.stderr.toString(), contains('ERR_TX_STATE_CORRUPT'));
      expect(
        File(p.join(dataNoBinPrev.path, 'bin', 'mms_backend.exe'))
            .readAsStringSync(),
        contains('t24_v11'),
      );
      expect(
        jsonDecode(
          File(p.join(dataNoBinPrev.path, 'run', 'sandbox_scm.json'))
              .readAsStringSync(),
        )['status'],
        equals('Stopped'),
      );
      expect(
        File(p.join(dataNoBinPrev.path, 'data', 'market_master.db'))
            .readAsStringSync(),
        equals('T24_NOBINPREV_DB'),
      );

      // 5) Eksik install_manifest.previous.json (hem tx state yok hem tx state bozuk durumlarinda fail-closed)
      for (final delTx in [true, false]) {
        final dataNoMf = await prepareFailedUpgrade(
          tag: 'nomf_$delTx',
          withCerts: true,
          dbContent: 'T24_NOMF_DB',
          deleteTxFiles: delTx,
        );
        File(p.join(dataNoMf.path, 'config', 'install_manifest.previous.json'))
            .deleteSync();
        final resNoMf = await runEngine(
          action: 'Rollback',
          installDir: Directory(
            p.join(tempRoot.path, 't24_nomf_${delTx}_inst'),
          ),
          programDataRoot: dataNoMf,
          appVersion: '1.1.0',
          msiManaged: true,
        );
        expect(resNoMf.exitCode, equals(74));
        expect(resNoMf.stderr.toString(), contains('ERR_TX_STATE_CORRUPT'));
        expect(
          Directory(p.join(dataNoMf.path, 'bin.previous')).existsSync(),
          isTrue,
        );
        expect(
          File(p.join(dataNoMf.path, 'data', 'market_master.db'))
              .readAsStringSync(),
          equals('T24_NOMF_DB'),
        );
      }

      // 6) Bozuk install_manifest.previous.json JSON -> fail-closed
      final dataBadJson = await prepareFailedUpgrade(
        tag: 'badmfjson',
        withCerts: true,
        dbContent: 'T24_BADMFJSON_DB',
      );
      File(p.join(dataBadJson.path, 'config', 'install_manifest.previous.json'))
          .writeAsStringSync('{ BROKEN_MANIFEST');
      final resBadJson = await runEngine(
        action: 'Rollback',
        installDir: Directory(p.join(tempRoot.path, 't24_badmfjson_inst')),
        programDataRoot: dataBadJson,
        appVersion: '1.1.0',
        msiManaged: true,
      );
      expect(resBadJson.exitCode, equals(74));
      expect(resBadJson.stderr.toString(), contains('ERR_TX_STATE_CORRUPT'));
      expect(
        Directory(p.join(dataBadJson.path, 'bin.previous')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(dataBadJson.path, 'data', 'market_master.db'))
            .readAsStringSync(),
        equals('T24_BADMFJSON_DB'),
      );

      // 7) Bilinmeyen service_state -> fail-closed
      final dataUnknownState = await prepareFailedUpgrade(
        tag: 'unkstate',
        withCerts: true,
        dbContent: 'T24_UNKSTATE_DB',
      );
      final unkFile = File(
        p.join(
          dataUnknownState.path,
          'config',
          'install_manifest.previous.json',
        ),
      );
      final unkMap =
          jsonDecode(unkFile.readAsStringSync()) as Map<String, dynamic>;
      unkMap['service_state'] = 'MAYBE_RUNNING_OR_UNKNOWN';
      unkFile.writeAsStringSync(jsonEncode(unkMap));
      final resUnk = await runEngine(
        action: 'Rollback',
        installDir: Directory(p.join(tempRoot.path, 't24_unkstate_inst')),
        programDataRoot: dataUnknownState,
        appVersion: '1.1.0',
        msiManaged: true,
      );
      expect(resUnk.exitCode, equals(74));
      expect(resUnk.stderr.toString(), contains('ERR_TX_STATE_CORRUPT'));
      expect(
        jsonDecode(
          File(p.join(dataUnknownState.path, 'run', 'sandbox_scm.json'))
              .readAsStringSync(),
        )['status'],
        equals('Stopped'),
      );
      expect(
        File(p.join(dataUnknownState.path, 'data', 'market_master.db'))
            .readAsStringSync(),
        equals('T24_UNKSTATE_DB'),
      );

      // 8) Eksik binary (bin.previous icinde MarketMMSService.exe yok) + RollbackAcl recovery hatasi -> servis baslatilmaz, veriler korunur
      final dataPartialBin = await prepareFailedUpgrade(
        tag: 'partbin',
        withCerts: true,
        dbContent: 'T24_PARTBIN_DB',
      );
      File(p.join(dataPartialBin.path, 'bin.previous', 'MarketMMSService.exe'))
          .deleteSync();
      final resPartBin = await runEngine(
        action: 'Rollback',
        installDir: Directory(p.join(tempRoot.path, 't24_partbin_inst')),
        programDataRoot: dataPartialBin,
        appVersion: '1.1.0',
        msiManaged: true,
      );
      expect(resPartBin.exitCode, equals(74));
      expect(resPartBin.stderr.toString(), contains('ERR_TX_STATE_CORRUPT'));
      expect(
        File(p.join(dataPartialBin.path, 'data', 'market_master.db'))
            .readAsStringSync(),
        equals('T24_PARTBIN_DB'),
      );

      final dataAclGate = await prepareFailedUpgrade(
        tag: 'aclgate',
        withCerts: true,
        dbContent: 'T24_ACLGATE_DB',
      );
      final secAclGateBefore = File(
        p.join(dataAclGate.path, 'security', 'admin_secret.txt'),
      ).readAsStringSync();
      final cfgAclGateBefore = File(
        p.join(dataAclGate.path, 'config', 'hub_config.json'),
      ).readAsStringSync();
      final resAclGate = await runEngine(
        action: 'Rollback',
        installDir: Directory(p.join(tempRoot.path, 't24_aclgate_inst')),
        programDataRoot: dataAclGate,
        appVersion: '1.1.0',
        faultInjection: 'RollbackAcl',
        msiManaged: true,
      );
      expect(resAclGate.exitCode, equals(74));
      expect(
        jsonDecode(
          File(p.join(dataAclGate.path, 'run', 'sandbox_scm.json'))
              .readAsStringSync(),
        )['status'],
        equals('Stopped'),
      );
      expect(
        File(p.join(dataAclGate.path, 'data', 'market_master.db'))
            .readAsStringSync(),
        equals('T24_ACLGATE_DB'),
      );
      expect(
        File(p.join(dataAclGate.path, 'security', 'admin_secret.txt'))
            .readAsStringSync(),
        equals(secAclGateBefore),
      );
      expect(
        File(p.join(dataAclGate.path, 'config', 'hub_config.json'))
            .readAsStringSync(),
        equals(cfgAclGateBefore),
      );
    });

    test('25. B-1 Manifest Fallback ServiceModified, WinSW Sirasi ve Fresh/Upgrade Rollback Tutarliligi', () async {
      final stage10 = createSyntheticStaging('t25_v10');
      final stage11 = createSyntheticStaging('t25_v11');
      for (final st in [stage10, stage11]) {
        File(p.join(st.path, 'hub_scripts', 'setup_service_acls.ps1'))
            .writeAsStringSync('# synthetic acl script\n');
        File(p.join(st.path, 'hub_scripts', 'configure_hub_firewall.ps1'))
            .writeAsStringSync('# synthetic firewall script\n');
      }

      List<String> readScmOps(Directory dataDir) {
        final f = File(p.join(dataDir.path, 'run', 'sandbox_scm_ops.log'));
        if (!f.existsSync()) return const [];
        return f
            .readAsLinesSync()
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
      }

      Future<Directory> prepareInterruptedUpgrade({
        required String tag,
        required String faultStage,
        required String dbContent,
        bool deleteTxFiles = false,
        bool corruptPrimaryTx = true,
      }) async {
        final inst = Directory(p.join(tempRoot.path, 't25_${tag}_inst'));
        final data = Directory(p.join(tempRoot.path, 't25_${tag}_data'));
        seedSyntheticCerts(data);
        expect(
          (await runEngine(
            action: 'Install',
            installDir: inst,
            programDataRoot: data,
            stagingDir: stage10,
            appVersion: '1.0.0',
          )).exitCode,
          equals(0),
        );
        File(p.join(data.path, 'data', 'market_master.db'))
            .writeAsStringSync(dbContent);
        expect(
          (await runEngine(
            action: 'Install',
            installDir: inst,
            programDataRoot: data,
            stagingDir: stage11,
            appVersion: '1.1.0',
            faultInjection: faultStage,
            msiManaged: true,
          )).exitCode,
          equals(74),
        );
        final txFile = File(
          p.join(data.path, 'run', 'installer_tx_state.json'),
        );
        final prevTxFile = File(
          p.join(data.path, 'run', 'installer_tx_state.previous.json'),
        );
        if (prevTxFile.existsSync()) prevTxFile.deleteSync();
        if (deleteTxFiles) {
          if (txFile.existsSync()) txFile.deleteSync();
        } else if (corruptPrimaryTx) {
          txFile.writeAsStringSync('{ CORRUPT_PRIMARY_TX');
        }
        return data;
      }

      // 1) Manifest fallback + degismemis mevcut servis (Step 5 oncesi Migration hatasi)
      final dataUnmod = await prepareInterruptedUpgrade(
        tag: 'unmod',
        faultStage: 'Migration',
        dbContent: 'T25_UNMOD_DB',
      );
      final rbUnmod = await runEngine(
        action: 'Rollback',
        installDir: Directory(p.join(tempRoot.path, 't25_unmod_inst')),
        programDataRoot: dataUnmod,
        appVersion: '1.1.0',
        msiManaged: true,
      );
      expect(
        rbUnmod.exitCode,
        equals(0),
        reason: '${rbUnmod.stdout}\n${rbUnmod.stderr}',
      );
      final scmUnmod = jsonDecode(
        File(p.join(dataUnmod.path, 'run', 'sandbox_scm.json'))
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(scmUnmod['status'], equals('Running'));
      expect(scmUnmod['version'], equals('1.0.0'));
      expect(
        File(p.join(dataUnmod.path, 'bin', 'mms_backend.exe'))
            .readAsStringSync(),
        contains('t25_v10'),
      );
      expect(
        File(p.join(dataUnmod.path, 'data', 'market_master.db'))
            .readAsStringSync(),
        equals('T25_UNMOD_DB'),
      );
      expect(
        readScmOps(dataUnmod),
        equals(['verify_existing:1.0.0', 'start:1.0.0']),
      );
      expect(
        File(p.join(dataUnmod.path, 'logs', 'installer-diagnostics.log'))
            .readAsStringSync(),
        contains('service_modified=False'),
      );

      // 2A) Upgrade Step 5 sonrasi (HealthCheck, primary tx bozuk) -> stop -> uninstall -> install -> sidtype -> start
      final dataModCorrupt = await prepareInterruptedUpgrade(
        tag: 'mod_corrupt',
        faultStage: 'HealthCheck',
        dbContent: 'T25_MOD_CORRUPT_DB',
      );
      final rbModCorrupt = await runEngine(
        action: 'Rollback',
        installDir: Directory(p.join(tempRoot.path, 't25_mod_corrupt_inst')),
        programDataRoot: dataModCorrupt,
        appVersion: '1.1.0',
        msiManaged: true,
      );
      expect(
        rbModCorrupt.exitCode,
        equals(0),
        reason: '${rbModCorrupt.stdout}\n${rbModCorrupt.stderr}',
      );
      final scmModCorrupt = jsonDecode(
        File(p.join(dataModCorrupt.path, 'run', 'sandbox_scm.json'))
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(scmModCorrupt['status'], equals('Running'));
      expect(scmModCorrupt['version'], equals('1.0.0'));
      expect(
        File(p.join(dataModCorrupt.path, 'data', 'market_master.db'))
            .readAsStringSync(),
        equals('T25_MOD_CORRUPT_DB'),
      );
      expect(
        readScmOps(dataModCorrupt),
        equals([
          'stop:1.1.0',
          'uninstall:1.1.0',
          'install:1.0.0',
          'sidtype:unrestricted',
          'stamp:1.0.0',
          'start:1.0.0',
        ]),
      );
      expect(
        File(p.join(dataModCorrupt.path, 'logs', 'installer-diagnostics.log'))
            .readAsStringSync(),
        contains('service_modified=True'),
      );

      // 2B) Upgrade Step 5 sonrasi (ServiceStart, tum tx dosyalari silinmis) -> uninstall -> install -> sidtype -> start
      final dataModNoTx = await prepareInterruptedUpgrade(
        tag: 'mod_notx',
        faultStage: 'ServiceStart',
        dbContent: 'T25_MOD_NOTX_DB',
        deleteTxFiles: true,
      );
      final rbModNoTx = await runEngine(
        action: 'Rollback',
        installDir: Directory(p.join(tempRoot.path, 't25_mod_notx_inst')),
        programDataRoot: dataModNoTx,
        appVersion: '1.1.0',
        msiManaged: true,
      );
      expect(
        rbModNoTx.exitCode,
        equals(0),
        reason: '${rbModNoTx.stdout}\n${rbModNoTx.stderr}',
      );
      final scmModNoTx = jsonDecode(
        File(p.join(dataModNoTx.path, 'run', 'sandbox_scm.json'))
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(scmModNoTx['status'], equals('Running'));
      expect(scmModNoTx['version'], equals('1.0.0'));
      expect(
        File(p.join(dataModNoTx.path, 'data', 'market_master.db'))
            .readAsStringSync(),
        equals('T25_MOD_NOTX_DB'),
      );
      expect(
        readScmOps(dataModNoTx),
        equals([
          'uninstall:1.1.0',
          'install:1.0.0',
          'sidtype:unrestricted',
          'stamp:1.0.0',
          'start:1.0.0',
        ]),
      );
      expect(
        File(p.join(dataModNoTx.path, 'logs', 'installer-diagnostics.log'))
            .readAsStringSync(),
        contains('service_modified=True'),
      );

      // 3) Fresh Install fallback davranislari (asla manifest fallback veya servis baslatma yok)
      // 3a) Fresh Install bozuk primary tx + previous yok -> fail-closed 74 ERR_TX_STATE_CORRUPT
      final freshCorruptInst = Directory(p.join(tempRoot.path, 't25_fc_inst'));
      final freshCorruptData = Directory(p.join(tempRoot.path, 't25_fc_data'));
      Directory(p.join(freshCorruptData.path, 'data'))
          .createSync(recursive: true);
      File(p.join(freshCorruptData.path, 'data', 'market_master.db'))
          .writeAsStringSync('T25_FRESH_CORRUPT_DB');
      expect(
        (await runEngine(
          action: 'Install',
          installDir: freshCorruptInst,
          programDataRoot: freshCorruptData,
          stagingDir: stage10,
          faultInjection: 'ServiceStart',
          msiManaged: true,
        )).exitCode,
        equals(74),
      );
      final fcPrev = File(
        p.join(freshCorruptData.path, 'run', 'installer_tx_state.previous.json'),
      );
      if (fcPrev.existsSync()) fcPrev.deleteSync();
      File(p.join(freshCorruptData.path, 'run', 'installer_tx_state.json'))
          .writeAsStringSync('{ BROKEN_FRESH_TX');
      final rbFreshCorrupt = await runEngine(
        action: 'Rollback',
        installDir: freshCorruptInst,
        programDataRoot: freshCorruptData,
        msiManaged: true,
      );
      expect(rbFreshCorrupt.exitCode, equals(74));
      expect(
        rbFreshCorrupt.stderr.toString(),
        contains('ERR_TX_STATE_CORRUPT'),
      );
      expect(
        jsonDecode(
          File(p.join(freshCorruptData.path, 'run', 'sandbox_scm.json'))
              .readAsStringSync(),
        )['status'],
        equals('Stopped'),
      );
      expect(readScmOps(freshCorruptData), isEmpty);
      expect(
        File(p.join(freshCorruptData.path, 'data', 'market_master.db'))
            .readAsStringSync(),
        equals('T25_FRESH_CORRUPT_DB'),
      );

      // 3b) Fresh Install tum tx dosyalari silinmis + .previous yok -> idempotent no-op (ExitCode 0), servis baslatilmaz
      final freshNoTxInst = Directory(p.join(tempRoot.path, 't25_fn_inst'));
      final freshNoTxData = Directory(p.join(tempRoot.path, 't25_fn_data'));
      Directory(p.join(freshNoTxData.path, 'data'))
          .createSync(recursive: true);
      File(p.join(freshNoTxData.path, 'data', 'market_master.db'))
          .writeAsStringSync('T25_FRESH_NOTX_DB');
      expect(
        (await runEngine(
          action: 'Install',
          installDir: freshNoTxInst,
          programDataRoot: freshNoTxData,
          stagingDir: stage10,
          faultInjection: 'ServiceStart',
          msiManaged: true,
        )).exitCode,
        equals(74),
      );
      for (final fName in [
        'installer_tx_state.json',
        'installer_tx_state.previous.json',
      ]) {
        final f = File(p.join(freshNoTxData.path, 'run', fName));
        if (f.existsSync()) f.deleteSync();
      }
      final rbFreshNoTx = await runEngine(
        action: 'Rollback',
        installDir: freshNoTxInst,
        programDataRoot: freshNoTxData,
        msiManaged: true,
      );
      expect(rbFreshNoTx.exitCode, equals(0));
      expect(
        jsonDecode(
          File(p.join(freshNoTxData.path, 'run', 'sandbox_scm.json'))
              .readAsStringSync(),
        )['status'],
        equals('Stopped'),
      );
      expect(readScmOps(freshNoTxData), isEmpty);
      expect(
        File(p.join(freshNoTxData.path, 'data', 'market_master.db'))
            .readAsStringSync(),
        equals('T25_FRESH_NOTX_DB'),
      );

      // 3c) Normal Fresh Install rollback -> yalnizca uninstall:1.0.0 calisir, install/start cagrilmaz
      final freshNormInst = Directory(p.join(tempRoot.path, 't25_fnorm_inst'));
      final freshNormData = Directory(p.join(tempRoot.path, 't25_fnorm_data'));
      expect(
        (await runEngine(
          action: 'Install',
          installDir: freshNormInst,
          programDataRoot: freshNormData,
          stagingDir: stage10,
          faultInjection: 'ServiceStart',
          msiManaged: true,
        )).exitCode,
        equals(74),
      );
      final rbFreshNorm = await runEngine(
        action: 'Rollback',
        installDir: freshNormInst,
        programDataRoot: freshNormData,
        msiManaged: true,
      );
      expect(rbFreshNorm.exitCode, equals(0));
      expect(readScmOps(freshNormData), equals(['uninstall:1.0.0']));
      expect(
        File(p.join(freshNormData.path, 'run', 'sandbox_scm.json'))
            .existsSync(),
        isFalse,
      );

      // 4) Rollback basarisizliklari -> servis BASLATILMAZ, kullanici verileri korunur
      // 4a) Manifest fallback (ServiceModified=true) + RollbackService hatasi
      final dataRbSvcFail = await prepareInterruptedUpgrade(
        tag: 'rbsvcfail',
        faultStage: 'ServiceStart',
        dbContent: 'T25_RBSVCFAIL_DB',
      );
      final secBeforeSvcFail = File(
        p.join(dataRbSvcFail.path, 'security', 'admin_secret.txt'),
      ).readAsStringSync();
      final resRbSvcFail = await runEngine(
        action: 'Rollback',
        installDir: Directory(p.join(tempRoot.path, 't25_rbsvcfail_inst')),
        programDataRoot: dataRbSvcFail,
        appVersion: '1.1.0',
        faultInjection: 'RollbackService',
        msiManaged: true,
      );
      expect(resRbSvcFail.exitCode, equals(74));
      expect(
        File(p.join(dataRbSvcFail.path, 'run', 'sandbox_scm.json'))
            .existsSync(),
        isFalse,
      );
      expect(readScmOps(dataRbSvcFail), equals(['uninstall:1.1.0']));
      final txSvcFail = jsonDecode(
        File(p.join(dataRbSvcFail.path, 'run', 'installer_tx_state.json'))
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(txSvcFail['status'], equals('PARTIAL_ROLLBACK_FAILED'));
      expect(
        txSvcFail['failed_steps'],
        containsAll(['reinstall_service', 'reapply_acls', 'start_service']),
      );
      expect(
        File(p.join(dataRbSvcFail.path, 'data', 'market_master.db'))
            .readAsStringSync(),
        equals('T25_RBSVCFAIL_DB'),
      );
      expect(
        File(p.join(dataRbSvcFail.path, 'security', 'admin_secret.txt'))
            .readAsStringSync(),
        equals(secBeforeSvcFail),
      );

      // 4b) ServiceModified=false + tutarsiz bin_path -> Step 6 ERR_ROLLBACK_SERVICE_CONFLICT, servis Stopped
      final dataConflict = await prepareInterruptedUpgrade(
        tag: 'conflict',
        faultStage: 'Migration',
        dbContent: 'T25_CONFLICT_DB',
      );
      final scmConflictFile = File(
        p.join(dataConflict.path, 'run', 'sandbox_scm.json'),
      );
      final scmConflictMap =
          jsonDecode(scmConflictFile.readAsStringSync()) as Map<String, dynamic>;
      scmConflictMap['bin_path'] = r'C:\Tampered\OtherWrapper.exe';
      scmConflictFile.writeAsStringSync(jsonEncode(scmConflictMap));
      final resConflict = await runEngine(
        action: 'Rollback',
        installDir: Directory(p.join(tempRoot.path, 't25_conflict_inst')),
        programDataRoot: dataConflict,
        appVersion: '1.1.0',
        msiManaged: true,
      );
      expect(resConflict.exitCode, equals(74));
      expect(
        jsonDecode(scmConflictFile.readAsStringSync())['status'],
        equals('Stopped'),
      );
      expect(readScmOps(dataConflict), isEmpty);
      final txConflict = jsonDecode(
        File(p.join(dataConflict.path, 'run', 'installer_tx_state.json'))
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(txConflict['status'], equals('PARTIAL_ROLLBACK_FAILED'));
      expect(
        txConflict['failed_steps'],
        containsAll(['reinstall_service', 'reapply_acls', 'start_service']),
      );
      expect(
        txConflict['rollback_errors'].toString(),
        contains('ERR_ROLLBACK_SERVICE_CONFLICT'),
      );
      expect(
        File(p.join(dataConflict.path, 'data', 'market_master.db'))
            .readAsStringSync(),
        equals('T25_CONFLICT_DB'),
      );

      // 4c) ServiceModified=true + RollbackAcl hatasi -> install edilir ama start:1.0.0 CAGRILMAZ (Stopped)
      final dataAclGate = await prepareInterruptedUpgrade(
        tag: 'acl_gate',
        faultStage: 'ServiceStart',
        dbContent: 'T25_ACLGATE_DB',
      );
      final resAclGate = await runEngine(
        action: 'Rollback',
        installDir: Directory(p.join(tempRoot.path, 't25_acl_gate_inst')),
        programDataRoot: dataAclGate,
        appVersion: '1.1.0',
        faultInjection: 'RollbackAcl',
        msiManaged: true,
      );
      expect(resAclGate.exitCode, equals(74));
      expect(
        jsonDecode(
          File(p.join(dataAclGate.path, 'run', 'sandbox_scm.json'))
              .readAsStringSync(),
        )['status'],
        equals('Stopped'),
      );
      expect(
        readScmOps(dataAclGate),
        equals([
          'uninstall:1.1.0',
          'install:1.0.0',
          'sidtype:unrestricted',
          'stamp:1.0.0',
        ]),
      );
      expect(
        File(p.join(dataAclGate.path, 'data', 'market_master.db'))
            .readAsStringSync(),
        equals('T25_ACLGATE_DB'),
      );
    });

    test('26. A-6 Manifest Fallback program_data_root Fail-Closed Dogrulamalari', () async {
      final stage10 = createSyntheticStaging('t26_v10');
      final stage11 = createSyntheticStaging('t26_v11');
      for (final st in [stage10, stage11]) {
        File(p.join(st.path, 'hub_scripts', 'setup_service_acls.ps1'))
            .writeAsStringSync('# synthetic acl script\n');
        File(p.join(st.path, 'hub_scripts', 'configure_hub_firewall.ps1'))
            .writeAsStringSync('# synthetic firewall script\n');
      }

      Future<Directory> prepareA6Case({
        required String tag,
        required String dbContent,
        required void Function(Map<String, dynamic> manifest, Directory data)
            mutateManifest,
      }) async {
        final inst = Directory(p.join(tempRoot.path, 't26_${tag}_inst'));
        final data = Directory(p.join(tempRoot.path, 't26_${tag}_data'));
        seedSyntheticCerts(data);
        expect(
          (await runEngine(
            action: 'Install',
            installDir: inst,
            programDataRoot: data,
            stagingDir: stage10,
            appVersion: '1.0.0',
          )).exitCode,
          equals(0),
        );
        File(p.join(data.path, 'data', 'market_master.db'))
            .writeAsStringSync(dbContent);
        expect(
          (await runEngine(
            action: 'Install',
            installDir: inst,
            programDataRoot: data,
            stagingDir: stage11,
            appVersion: '1.1.0',
            faultInjection: 'ServiceStart',
            msiManaged: true,
          )).exitCode,
          equals(74),
        );
        final prevTx = File(
          p.join(data.path, 'run', 'installer_tx_state.previous.json'),
        );
        if (prevTx.existsSync()) prevTx.deleteSync();
        File(p.join(data.path, 'run', 'installer_tx_state.json'))
            .writeAsStringSync('{ CORRUPT_PRIMARY_FOR_A6');

        final prevMf = File(
          p.join(data.path, 'config', 'install_manifest.previous.json'),
        );
        final mfMap =
            jsonDecode(prevMf.readAsStringSync()) as Map<String, dynamic>;
        mutateManifest(mfMap, data);
        prevMf.writeAsStringSync(jsonEncode(mfMap));
        return data;
      }

      // 1) Gecerli program_data_root (sonunda slash ve buyuk/kucuk harf farki dahil) -> kabul ve rollback basarili
      final dataValid = await prepareA6Case(
        tag: 'valid',
        dbContent: 'T26_VALID_DB',
        mutateManifest: (mf, data) {
          mf['program_data_root'] = '${data.path.toUpperCase()}\\';
        },
      );
      final resValid = await runEngine(
        action: 'Rollback',
        installDir: Directory(p.join(tempRoot.path, 't26_valid_inst')),
        programDataRoot: dataValid,
        appVersion: '1.1.0',
        msiManaged: true,
      );
      expect(
        resValid.exitCode,
        equals(0),
        reason: '${resValid.stdout}\n${resValid.stderr}',
      );
      expect(
        File(p.join(dataValid.path, 'bin', 'mms_backend.exe'))
            .readAsStringSync(),
        contains('t26_v10'),
      );
      expect(
        jsonDecode(
          File(p.join(dataValid.path, 'run', 'sandbox_scm.json'))
              .readAsStringSync(),
        )['status'],
        equals('Running'),
      );
      expect(
        File(p.join(dataValid.path, 'data', 'market_master.db'))
            .readAsStringSync(),
        equals('T26_VALID_DB'),
      );

      // 2-6) Fail-closed red senaryolari: eksik, null, bos, farkli path, gecersiz path
      final invalidCases =
          <({String tag, void Function(Map<String, dynamic>, Directory) mut})>[
        (
          tag: 'missing',
          mut: (mf, _) => mf.remove('program_data_root'),
        ),
        (
          tag: 'null',
          mut: (mf, _) => mf['program_data_root'] = null,
        ),
        (
          tag: 'empty',
          mut: (mf, _) => mf['program_data_root'] = '',
        ),
        (
          tag: 'whitespace',
          mut: (mf, _) => mf['program_data_root'] = '   ',
        ),
        (
          tag: 'mismatch',
          mut: (mf, _) =>
              mf['program_data_root'] = r'C:\OtherMarketMMS\Data',
        ),
        (
          tag: 'relative_path',
          mut: (mf, _) => mf['program_data_root'] = r'relative\MarketMMS',
        ),
        (
          tag: 'invalid_chars',
          mut: (mf, _) =>
              mf['program_data_root'] = r'C:\Invalid<Path>\MarketMMS',
        ),
      ];

      for (final c in invalidCases) {
        final dbMarker = 'T26_${c.tag.toUpperCase()}_DB';
        final dataBad = await prepareA6Case(
          tag: c.tag,
          dbContent: dbMarker,
          mutateManifest: c.mut,
        );
        final resBad = await runEngine(
          action: 'Rollback',
          installDir: Directory(p.join(tempRoot.path, 't26_${c.tag}_inst')),
          programDataRoot: dataBad,
          appVersion: '1.1.0',
          msiManaged: true,
        );
        expect(
          resBad.exitCode,
          equals(74),
          reason: '${c.tag} fail-closed ExitCode 74 vermeli',
        );
        expect(
          resBad.stderr.toString(),
          contains('ERR_TX_STATE_CORRUPT'),
          reason: '${c.tag} ERR_TX_STATE_CORRUPT bildirmeli',
        );
        // Fallback rollback hic baslamamis olmali: bin.previous korunur, bin v11 kalir, servis Stopped, DB korunur
        expect(
          Directory(p.join(dataBad.path, 'bin.previous')).existsSync(),
          isTrue,
        );
        expect(
          File(p.join(dataBad.path, 'bin', 'mms_backend.exe'))
              .readAsStringSync(),
          contains('t26_v11'),
        );
        expect(
          jsonDecode(
            File(p.join(dataBad.path, 'run', 'sandbox_scm.json'))
                .readAsStringSync(),
          )['status'],
          equals('Stopped'),
        );
        expect(
          File(p.join(dataBad.path, 'data', 'market_master.db'))
              .readAsStringSync(),
          equals(dbMarker),
        );
      }
    });

    test('27. B-1 Deterministik SCM Kimlik Damgasi, Senaryo A-J ve 14 Fail-Closed Edge-Case Dogrulamasi', () async {
      final stage10 = createSyntheticStaging('t27_v10');
      final stage11 = createSyntheticStaging('t27_v11');
      // Farkli MarketMMSService.xml icerigi ile XML SHA-256 degisimini de sinyalle
      File(p.join(stage11.path, 'hub_bin', 'MarketMMSService.xml')).writeAsStringSync(
        '${File(p.join(stage10.path, 'hub_bin', 'MarketMMSService.xml')).readAsStringSync()}\n<!-- v1.1.0-xml -->\n',
      );
      for (final st in [stage10, stage11]) {
        File(p.join(st.path, 'hub_scripts', 'setup_service_acls.ps1'))
            .writeAsStringSync('# synthetic acl script\n');
        File(p.join(st.path, 'hub_scripts', 'configure_hub_firewall.ps1'))
            .writeAsStringSync('# synthetic firewall script\n');
      }

      List<String> readLines(Directory dataDir, String fileName) {
        final f = File(p.join(dataDir.path, 'run', fileName));
        if (!f.existsSync()) return const [];
        return f
            .readAsLinesSync()
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList();
      }

      Map<String, dynamic> readScm(Directory dataDir) =>
          jsonDecode(File(p.join(dataDir.path, 'run', 'sandbox_scm.json')).readAsStringSync())
              as Map<String, dynamic>;

      Future<({Directory inst, Directory data})> setupBaseV10({
        required String tag,
        required bool withCerts,
        required String dbContent,
      }) async {
        final inst = Directory(p.join(tempRoot.path, 't27_${tag}_inst'));
        final data = Directory(p.join(tempRoot.path, 't27_${tag}_data'));
        if (withCerts) seedSyntheticCerts(data);
        final res = await runEngine(
          action: 'Install',
          installDir: inst,
          programDataRoot: data,
          stagingDir: stage10,
          appVersion: '1.0.0',
        );
        expect(res.exitCode, equals(0), reason: '${res.stdout}\n${res.stderr}');
        File(p.join(data.path, 'data', 'market_master.db')).writeAsStringSync(dbContent);
        return (inst: inst, data: data);
      }

      // Senaryo A: Eski servis durduruldu, .previous olusturulmadan hata -> servis kaldirilmaz, verify_existing -> start
      final scA = await setupBaseV10(tag: 'scA', withCerts: true, dbContent: 'SC_A_DB');
      final resA = await runEngine(
        action: 'Install',
        installDir: scA.inst,
        programDataRoot: scA.data,
        stagingDir: stage11,
        appVersion: '1.1.0',
        faultInjection: 'PrePreviousBackup',
        msiManaged: true,
      );
      expect(resA.exitCode, equals(74));
      expect(Directory(p.join(scA.data.path, 'bin.previous')).existsSync(), isFalse);
      expect(readLines(scA.data, 'sandbox_install_scm_ops.log'), equals(['install:1.0.0', 'sidtype:unrestricted', 'stamp:1.0.0', 'stop:1.0.0']));
      expect(readScm(scA.data)['mms_app_version'], equals('1.0.0'));
      final rbA = await runEngine(
        action: 'Rollback',
        installDir: scA.inst,
        programDataRoot: scA.data,
        appVersion: '1.1.0',
        msiManaged: true,
      );
      expect(rbA.exitCode, equals(0), reason: '${rbA.stdout}\n${rbA.stderr}');
      expect(readLines(scA.data, 'sandbox_scm_ops.log'), equals(['verify_existing:1.0.0', 'start:1.0.0']));
      expect(readScm(scA.data)['status'], equals('Running'));
      expect(readScm(scA.data)['mms_app_version'], equals('1.0.0'));
      expect(File(p.join(scA.data.path, 'data', 'market_master.db')).readAsStringSync(), equals('SC_A_DB'));

      // Senaryo B, C, D + Stopped servis: .previous sonrasi, Migration ve ServiceInstall (Step 5 oncesi) -> uninstall yok!
      for (final item in [
        (tag: 'scB', fault: 'UpgradeInterrupt', certs: true, expectedEndStatus: 'Running'),
        (tag: 'scC', fault: 'Migration', certs: true, expectedEndStatus: 'Running'),
        (tag: 'scD', fault: 'ServiceInstall', certs: true, expectedEndStatus: 'Running'),
        (tag: 'scStopped', fault: 'Migration', certs: false, expectedEndStatus: 'Stopped'),
      ]) {
        final base = await setupBaseV10(tag: item.tag, withCerts: item.certs, dbContent: 'DB_${item.tag}');
        final failUpg = await runEngine(
          action: 'Install',
          installDir: base.inst,
          programDataRoot: base.data,
          stagingDir: stage11,
          appVersion: '1.1.0',
          faultInjection: item.fault,
          msiManaged: true,
        );
        expect(failUpg.exitCode, equals(74));
        final rb = await runEngine(
          action: 'Rollback',
          installDir: base.inst,
          programDataRoot: base.data,
          appVersion: '1.1.0',
          msiManaged: true,
        );
        expect(rb.exitCode, equals(0), reason: '${item.tag}: ${rb.stdout}\n${rb.stderr}');
        final ops = readLines(base.data, 'sandbox_scm_ops.log');
        expect(ops, contains('verify_existing:1.0.0'));
        expect(ops.where((e) => e.startsWith('uninstall:') || e.startsWith('install:')), isEmpty);
        if (item.expectedEndStatus == 'Running') {
          expect(ops, equals(['verify_existing:1.0.0', 'start:1.0.0']));
        } else {
          expect(ops, equals(['verify_existing:1.0.0']));
        }
        expect(readScm(base.data)['status'], equals(item.expectedEndStatus));
        expect(readScm(base.data)['mms_app_version'], equals('1.0.0'));
        expect(File(p.join(base.data.path, 'bin', 'mms_backend.exe')).readAsStringSync(), contains('t27_v10'));
        expect(File(p.join(base.data.path, 'data', 'market_master.db')).readAsStringSync(), equals('DB_${item.tag}'));
      }

      // Senaryo E: Step 5 WinSW install yapti ama Registry damgasi yazilamadi (ScmStamp) -> gecerli tx state kurtarmasi
      final scE = await setupBaseV10(tag: 'scE', withCerts: true, dbContent: 'SC_E_DB');
      final failE = await runEngine(
        action: 'Install',
        installDir: scE.inst,
        programDataRoot: scE.data,
        stagingDir: stage11,
        appVersion: '1.1.0',
        faultInjection: 'ScmStamp',
        msiManaged: true,
      );
      expect(failE.exitCode, equals(74));
      final midE = readScm(scE.data);
      expect(midE['mms_app_version'], isNull); // Damga henuz yazilmadi!
      final rbE = await runEngine(
        action: 'Rollback',
        installDir: scE.inst,
        programDataRoot: scE.data,
        appVersion: '1.1.0',
        msiManaged: true,
      );
      expect(rbE.exitCode, equals(0), reason: '${rbE.stdout}\n${rbE.stderr}');
      expect(
        readLines(scE.data, 'sandbox_scm_ops.log'),
        equals(['uninstall:unstamped', 'install:1.0.0', 'sidtype:unrestricted', 'stamp:1.0.0', 'start:1.0.0']),
      );
      expect(readScm(scE.data)['status'], equals('Running'));
      expect(readScm(scE.data)['mms_app_version'], equals('1.0.0'));
      expect(File(p.join(scE.data.path, 'data', 'market_master.db')).readAsStringSync(), equals('SC_E_DB'));

      // Senaryo F (Acl) & H (HealthCheck): Step 5 1.1.0 damgasi yazildi -> kaldirilip 1.0.0 damgali kurulur
      for (final fh in [(tag: 'scF', fault: 'Acl'), (tag: 'scH', fault: 'HealthCheck')]) {
        final b = await setupBaseV10(tag: fh.tag, withCerts: true, dbContent: 'DB_${fh.tag}');
        expect(
          (await runEngine(
            action: 'Install',
            installDir: b.inst,
            programDataRoot: b.data,
            stagingDir: stage11,
            appVersion: '1.1.0',
            faultInjection: fh.fault,
            msiManaged: true,
          )).exitCode,
          equals(74),
        );
        expect(readScm(b.data)['mms_app_version'], equals('1.1.0'));
        final rbFh = await runEngine(
          action: 'Rollback',
          installDir: b.inst,
          programDataRoot: b.data,
          appVersion: '1.1.0',
          msiManaged: true,
        );
        expect(rbFh.exitCode, equals(0), reason: '${fh.tag}: ${rbFh.stdout}\n${rbFh.stderr}');
        final opsFh = readLines(b.data, 'sandbox_scm_ops.log');
        expect(opsFh, containsAllInOrder(['uninstall:1.1.0', 'install:1.0.0', 'sidtype:unrestricted', 'stamp:1.0.0', 'start:1.0.0']));
        expect(readScm(b.data)['mms_app_version'], equals('1.0.0'));
        expect(readScm(b.data)['status'], equals('Running'));
      }

      // Eksik registry damgasi (Manifest fallback durumunda belirsiz koken) -> FAIL-CLOSED (ERR_SCM_STAMP_MISSING)
      final scMissingStamp = await setupBaseV10(tag: 'missStamp', withCerts: true, dbContent: 'DB_MISS_STAMP');
      expect(
        (await runEngine(
          action: 'Install',
          installDir: scMissingStamp.inst,
          programDataRoot: scMissingStamp.data,
          stagingDir: stage11,
          appVersion: '1.1.0',
          faultInjection: 'Migration',
          msiManaged: true,
        )).exitCode,
        equals(74),
      );
      File(p.join(scMissingStamp.data.path, 'run', 'installer_tx_state.previous.json')).deleteSync();
      File(p.join(scMissingStamp.data.path, 'run', 'installer_tx_state.json')).writeAsStringSync('{ CORRUPT');
      final scmMissMap = readScm(scMissingStamp.data)
        ..remove('mms_app_version')
        ..remove('mms_xml_sha256');
      File(p.join(scMissingStamp.data.path, 'run', 'sandbox_scm.json')).writeAsStringSync(jsonEncode(scmMissMap));
      final resMiss = await runEngine(
        action: 'Rollback',
        installDir: scMissingStamp.inst,
        programDataRoot: scMissingStamp.data,
        appVersion: '1.1.0',
        msiManaged: true,
      );
      expect(resMiss.exitCode, equals(74));
      expect(readLines(scMissingStamp.data, 'sandbox_scm_ops.log'), isEmpty);
      expect(readScm(scMissingStamp.data)['status'], equals('Stopped'));
      final txMiss = jsonDecode(File(p.join(scMissingStamp.data.path, 'run', 'installer_tx_state.json')).readAsStringSync()) as Map<String, dynamic>;
      expect(txMiss['status'], equals('PARTIAL_ROLLBACK_FAILED'));
      expect(txMiss['rollback_errors'].toString(), contains('ERR_SCM_STAMP_MISSING'));
      expect(Directory(p.join(scMissingStamp.data.path, 'bin.previous')).existsSync(), isTrue);
      expect(File(p.join(scMissingStamp.data.path, 'data', 'market_master.db')).readAsStringSync(), equals('DB_MISS_STAMP'));

      // Yanlis surum damgasi & XML SHA-256 uyusmazligi -> Eski sanmaz, yeniden kurup dogru damgayi basar
      for (final mismatchCase in [
        (tag: 'wrongVer', mutate: (Map<String, dynamic> m) => m['mms_app_version'] = '9.9.9', expectedUninst: 'uninstall:9.9.9'),
        (tag: 'wrongXml', mutate: (Map<String, dynamic> m) => m['mms_xml_sha256'] = '0' * 64, expectedUninst: 'uninstall:1.0.0'),
      ]) {
        final b = await setupBaseV10(tag: mismatchCase.tag, withCerts: true, dbContent: 'DB_${mismatchCase.tag}');
        expect(
          (await runEngine(
            action: 'Install',
            installDir: b.inst,
            programDataRoot: b.data,
            stagingDir: stage11,
            appVersion: '1.1.0',
            faultInjection: 'Migration',
            msiManaged: true,
          )).exitCode,
          equals(74),
        );
        final mutated = readScm(b.data);
        mismatchCase.mutate(mutated);
        File(p.join(b.data.path, 'run', 'sandbox_scm.json')).writeAsStringSync(jsonEncode(mutated));
        final rb = await runEngine(
          action: 'Rollback',
          installDir: b.inst,
          programDataRoot: b.data,
          appVersion: '1.1.0',
          msiManaged: true,
        );
        expect(rb.exitCode, equals(0), reason: '${mismatchCase.tag}: ${rb.stdout}\n${rb.stderr}');
        expect(
          readLines(b.data, 'sandbox_scm_ops.log'),
          equals([mismatchCase.expectedUninst, 'install:1.0.0', 'sidtype:unrestricted', 'stamp:1.0.0', 'start:1.0.0']),
        );
        expect(readScm(b.data)['mms_app_version'], equals('1.0.0'));
        expect(File(p.join(b.data.path, 'data', 'market_master.db')).readAsStringSync(), equals('DB_${mismatchCase.tag}'));
      }

      // Yabanci ImagePath + Yanlis Hesap + Yanlis SID Tipi + DELETE_PENDING (Senaryo I) -> hepsi FAIL-CLOSED
      for (final guardCase in [
        (tag: 'foreignImg', fault: 'None', errCode: 'ERR_FOREIGN_SERVICE_PROTECTED', mut: (Map<String, dynamic> m) => m['bin_path'] = r'C:\Vendor\ForeignSvc.exe'),
        (tag: 'badAcc', fault: 'None', errCode: 'ERR_SCM_INVALID_ACCOUNT', mut: (Map<String, dynamic> m) => m['account'] = 'LocalSystem'),
        (tag: 'badSid', fault: 'None', errCode: 'ERR_SCM_INVALID_SIDTYPE', mut: (Map<String, dynamic> m) => m['sid_type'] = 'NONE'),
        (tag: 'delPendFlag', fault: 'None', errCode: 'ERR_SCM_DELETE_PENDING', mut: (Map<String, dynamic> m) => m['delete_pending'] = true),
        (tag: 'delPendFault', fault: 'ScmDeletePending', errCode: 'ERR_SCM_DELETE_PENDING', mut: (Map<String, dynamic> m) {}),
      ]) {
        final b = await setupBaseV10(tag: guardCase.tag, withCerts: true, dbContent: 'DB_${guardCase.tag}');
        expect(
          (await runEngine(
            action: 'Install',
            installDir: b.inst,
            programDataRoot: b.data,
            stagingDir: stage11,
            appVersion: '1.1.0',
            faultInjection: 'Migration',
            msiManaged: true,
          )).exitCode,
          equals(74),
        );
        final mScm = readScm(b.data);
        guardCase.mut(mScm);
        File(p.join(b.data.path, 'run', 'sandbox_scm.json')).writeAsStringSync(jsonEncode(mScm));
        final rb = await runEngine(
          action: 'Rollback',
          installDir: b.inst,
          programDataRoot: b.data,
          appVersion: '1.1.0',
          faultInjection: guardCase.fault,
          msiManaged: true,
        );
        expect(rb.exitCode, equals(74), reason: guardCase.tag);
        expect(readLines(b.data, 'sandbox_scm_ops.log'), isEmpty, reason: '${guardCase.tag} asla uninstall/start yapmamali');
        final tx = jsonDecode(File(p.join(b.data.path, 'run', 'installer_tx_state.json')).readAsStringSync()) as Map<String, dynamic>;
        expect(tx['status'], equals('PARTIAL_ROLLBACK_FAILED'));
        expect(tx['rollback_errors'].toString(), contains(guardCase.errCode));
        expect(Directory(p.join(b.data.path, 'bin.previous')).existsSync(), isTrue);
        expect(File(p.join(b.data.path, 'data', 'market_master.db')).readAsStringSync(), equals('DB_${guardCase.tag}'));
      }

      // Install Step 5 sirasinda ServiceUninstall hatasi -> rollback Step 1/6 guvenli kalir, veri korunur
      final scUninstErr = await setupBaseV10(tag: 'uninstErr', withCerts: true, dbContent: 'DB_UNINST_ERR');
      final failUninst = await runEngine(
        action: 'Install',
        installDir: scUninstErr.inst,
        programDataRoot: scUninstErr.data,
        stagingDir: stage11,
        appVersion: '1.1.0',
        faultInjection: 'ServiceUninstall',
        msiManaged: true,
      );
      expect(failUninst.exitCode, equals(74));
      expect(failUninst.stderr.toString(), contains('ERR_SERVICE_UNINSTALL_FAILED'));
      expect(readScm(scUninstErr.data)['status'], equals('Stopped'));
      expect(File(p.join(scUninstErr.data.path, 'data', 'market_master.db')).readAsStringSync(), equals('DB_UNINST_ERR'));
    });
  });
}
