@Timeout(Duration(minutes: 6))
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sq;
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/certificate_manager.dart';
import '../lib/security/pepper_manager.dart';

/// Aşama 3 — Windows Installer (WiX v5) Denetim Regresyon Test Paketi.
///
/// KURAL: Gerçek `%ProgramData%\MarketMMS`, gerçek `%ProgramFiles%`, gerçek SCM,
/// gerçek Windows Firewall, gerçek Windows Sertifika Deposu (`Cert:\*`) ve
/// `MarketMmsSpike01` servisine KESİNLİKLE dokunulmaz. Tüm doğrulamalar izole
/// `Directory.systemTemp` dizinlerinde çalışır.
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
  final setupAclSrc = p.join(
    repoRoot,
    'test_spikes',
    'spike_01_backend',
    'scripts',
    'setup_service_acls.ps1',
  );
  final firewallSrc = p.join(repoRoot, 'scripts', 'configure_hub_firewall.ps1');

  late Directory tempRoot;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    configureSqliteNative();
  });

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('mms_stage3_inst_audit_');
  });

  tearDown(() async {
    if (tempRoot.existsSync()) {
      try {
        tempRoot.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Directory createSyntheticStaging(
    String tag, {
    bool useRealSqliteDll = false,
  }) {
    final stage = Directory(p.join(tempRoot.path, 'staging_$tag'));
    final client = Directory(p.join(stage.path, 'client'))
      ..createSync(recursive: true);
    final hubBin = Directory(p.join(stage.path, 'hub_bin'))
      ..createSync(recursive: true);
    final hubScripts = Directory(p.join(stage.path, 'hub_scripts'))
      ..createSync(recursive: true);

    File(p.join(client.path, 'market_pos.exe'))
        .writeAsStringSync('CLIENT_$tag');
    File(p.join(client.path, 'flutter_windows.dll'))
        .writeAsStringSync('FLUTTER_$tag');
    File(p.join(hubBin.path, 'mms_backend.exe')).writeAsStringSync('HUB_$tag');

    if (useRealSqliteDll) {
      final realDll =
          [
                p.join(repoRoot, '.dart_tool', 'lib', 'sqlite3.dll'),
                p.join(
                  repoRoot,
                  'build',
                  'native_assets',
                  'windows',
                  'sqlite3.dll',
                ),
              ]
              .map(File.new)
              .firstWhere(
                (f) => f.existsSync(),
                orElse: () => throw StateError('Gercek sqlite3.dll bulunamadi'),
              );
      realDll.copySync(p.join(hubBin.path, 'sqlite3.dll'));
    } else {
      File(p.join(hubBin.path, 'sqlite3.dll')).writeAsStringSync('SQLITE_$tag');
    }

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
    File(setupAclSrc)
        .copySync(p.join(hubScripts.path, 'setup_service_acls.ps1'));
    File(firewallSrc)
        .copySync(p.join(hubScripts.path, 'configure_hub_firewall.ps1'));
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
    bool allowDeferredTlsStart = true,
    bool msiManaged = false,
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
      '-FaultInjectionStage',
      faultInjection,
      '-AllowDeferredTlsStart',
      allowDeferredTlsStart ? '1' : '0',
      if (healthCheckUrl != null) ...['-HealthCheckUrl', healthCheckUrl],
      if (msiManaged) '-MsiManaged',
    ];
    return runPsFile(engineScript, args);
  }

  Future<Map<String, dynamic>> buildAndInspectSyntheticMsi(
    String tag, {
    String version = '1.0.0',
  }) async {
    final msiStage = Directory(p.join(tempRoot.path, 'msi_stage_$tag'));
    final msiOut = Directory(p.join(tempRoot.path, 'msi_out_$tag'));
    final res = await runPsFile(buildScript, [
      '-SyntheticStagingForTest',
      '-StagingDir',
      msiStage.path,
      '-OutputDir',
      msiOut.path,
      '-OverrideVersion',
      version,
    ]);
    expect(res.exitCode, equals(0), reason: '${res.stdout}\n${res.stderr}');

    final msiFile = File(
      p.join(msiOut.path, 'MarketMMS-Setup-$version-x64.msi'),
    );
    expect(msiFile.existsSync(), isTrue);

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
  msi_path = "${msiFile.path.replaceAll('\\', '\\\\')}"
  properties = @(Read-Table "SELECT ``Property``, ``Value`` FROM ``Property``" 2)
  launch_conditions = @(Read-Table "SELECT ``Condition``, ``Description`` FROM ``LaunchCondition``" 2)
  sequence = @(Read-Table "SELECT ``Action``, ``Condition``, ``Sequence`` FROM ``InstallExecuteSequence`` ORDER BY ``Sequence``" 3)
  custom_actions = @(Read-Table "SELECT ``Action``, ``Type``, ``Source``, ``Target`` FROM ``CustomAction``" 4)
  registry = @(Read-Table "SELECT ``Registry``, ``Root``, ``Key``, ``Name``, ``Component_`` FROM ``Registry``" 5)
  files = @(Read-Table "SELECT ``File``, ``FileName`` FROM ``File``" 2)
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
    return jsonDecode(inspectRes.stdout as String) as Map<String, dynamic>;
  }

  Map<String, String> parseCustomActionTargets(Map<String, dynamic> msiData) {
    final map = <String, String>{};
    for (final row in List<String>.from(msiData['custom_actions'] as List)) {
      final parts = row.split('|');
      if (parts.length >= 4) {
        map[parts[0]] = parts.sublist(3).join('|');
      }
    }
    return map;
  }

  void generateServerCertWithParams({
    required String caKeyPath,
    required String caCertPath,
    required String serverKeyPath,
    required String serverCertPath,
    required List<String> sanList,
    required String notBefore,
    required String notAfter,
  }) {
    final openssl = CertificateManager.getOpenSslPath();
    final csrDir = Directory(
      p.join(tempRoot.path, 'csr_${DateTime.now().microsecondsSinceEpoch}'),
    )..createSync(recursive: true);
    final csrPath = p.join(csrDir.path, 'server.csr');
    final extPath = p.join(csrDir.path, 'server.ext');
    final sanFormatted = sanList
        .map((entry) {
          if (entry.contains('.') && RegExp(r'^[0-9.]+$').hasMatch(entry)) {
            return 'IP:$entry';
          }
          return 'DNS:$entry';
        })
        .join(',');

    final csrRes = Process.runSync(openssl, [
      'req',
      '-new',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-keyout',
      serverKeyPath,
      '-out',
      csrPath,
      '-subj',
      '/CN=localhost',
    ]);
    if (csrRes.exitCode != 0) {
      throw StateError('CSR olusturulamadi: ${csrRes.stderr}');
    }
    File(extPath).writeAsStringSync('subjectAltName=$sanFormatted\n');

    final signRes = Process.runSync(openssl, [
      'x509',
      '-req',
      '-in',
      csrPath,
      '-CA',
      caCertPath,
      '-CAkey',
      caKeyPath,
      '-CAcreateserial',
      '-out',
      serverCertPath,
      '-not_before',
      notBefore,
      '-not_after',
      notAfter,
      '-extfile',
      extPath,
    ]);
    if (signRes.exitCode != 0) {
      throw StateError('Sertifika imzalanamadi: ${signRes.stderr}');
    }
  }

  Future<Map<String, String>> formatWithNativeMsiDllFor({
    required String msiPath,
    required Directory installDir,
    required Map<String, String> targets,
    required String hubPort,
    required String discoveryPort,
    required String allowDeferredTls,
    required String purgeUserData,
    required String confirmPurgeToken,
  }) async {
    final installFolderProp = '${installDir.path}\\';
    final hubScriptsProp = '${p.join(installDir.path, 'hub_scripts')}\\';
    final payloadJson = jsonEncode({
      'msiPath': msiPath,
      'installFolder': installFolderProp,
      'hubScripts': hubScriptsProp,
      'hubPort': hubPort,
      'discoveryPort': discoveryPort,
      'allowDeferredTls': allowDeferredTls,
      'purgeUserData': purgeUserData,
      'confirmPurgeToken': confirmPurgeToken,
      'targets': {
        'CA_InstallOrUpgrade': targets['CA_InstallOrUpgrade'],
        'CA_CommitInstall': targets['CA_CommitInstall'],
        'CA_Uninstall': targets['CA_Uninstall'],
      },
    });
    final b64Input = base64Encode(utf8.encode(payloadJson));
    final nativeScript =
        '''
\$cfg = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64Input')) | ConvertFrom-Json
if (-not ("MsiRuntimeFormatter" -as [type])) {
  Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class MsiRuntimeFormatter {
    [DllImport("msi.dll", CharSet = CharSet.Unicode)]
    public static extern uint MsiOpenPackageExW(string szPackagePath, uint dwOptions, out IntPtr hProduct);
    [DllImport("msi.dll", CharSet = CharSet.Unicode)]
    public static extern uint MsiDoActionW(IntPtr hInstall, string szAction);
    [DllImport("msi.dll", CharSet = CharSet.Unicode)]
    public static extern uint MsiSetPropertyW(IntPtr hInstall, string szName, string szValue);
    [DllImport("msi.dll", CharSet = CharSet.Unicode)]
    public static extern uint MsiGetPropertyW(IntPtr hInstall, string szName, StringBuilder szValueBuf, ref int pcchValueBuf);
    [DllImport("msi.dll")]
    public static extern IntPtr MsiCreateRecord(uint cParams);
    [DllImport("msi.dll", CharSet = CharSet.Unicode)]
    public static extern uint MsiRecordSetStringW(IntPtr hRecord, uint iField, string szValue);
    [DllImport("msi.dll", CharSet = CharSet.Unicode)]
    public static extern uint MsiFormatRecordW(IntPtr hInstall, IntPtr hRecord, StringBuilder szResultBuf, ref int pcchResultBuf);
    [DllImport("msi.dll")]
    public static extern uint MsiCloseHandle(IntPtr hAny);

    public static string GetProp(IntPtr hInstall, string name) {
        int cch = 0;
        uint rc = MsiGetPropertyW(hInstall, name, new StringBuilder(0), ref cch);
        if (rc != 234 && rc != 0) throw new InvalidOperationException("MsiGetPropertyW " + name + " rc=" + rc);
        cch++;
        StringBuilder sb = new StringBuilder(cch);
        rc = MsiGetPropertyW(hInstall, name, sb, ref cch);
        if (rc != 0) throw new InvalidOperationException("MsiGetPropertyW(2) " + name + " rc=" + rc);
        return sb.ToString();
    }

    public static string FormatTemplate(IntPtr hInstall, string template) {
        IntPtr hRec = MsiCreateRecord(0);
        try {
            uint rcSet = MsiRecordSetStringW(hRec, 0, template);
            if (rcSet != 0) throw new InvalidOperationException("MsiRecordSetStringW rc=" + rcSet);
            int cch = 0;
            uint rc = MsiFormatRecordW(hInstall, hRec, new StringBuilder(0), ref cch);
            if (rc != 234 && rc != 0) throw new InvalidOperationException("MsiFormatRecordW rc=" + rc);
            cch++;
            StringBuilder sb = new StringBuilder(cch);
            rc = MsiFormatRecordW(hInstall, hRec, sb, ref cch);
            if (rc != 0) throw new InvalidOperationException("MsiFormatRecordW(2) rc=" + rc);
            return sb.ToString();
        } finally {
            if (hRec != IntPtr.Zero) MsiCloseHandle(hRec);
        }
    }
}
"@
}
\$hPkg = [IntPtr]::Zero
try {
  \$rcOpen = [MsiRuntimeFormatter]::MsiOpenPackageExW([string]\$cfg.msiPath, 1, [ref]\$hPkg)
  if (\$rcOpen -ne 0) { throw "MsiOpenPackageExW failed: \$rcOpen" }
  foreach (\$step in @("CostInitialize", "FileCost", "CostFinalize")) {
    \$rcStep = [MsiRuntimeFormatter]::MsiDoActionW(\$hPkg, \$step)
    if (\$rcStep -ne 0) { throw "\$step failed: \$rcStep" }
  }
  [void][MsiRuntimeFormatter]::MsiSetPropertyW(\$hPkg, "INSTALLFOLDER", [string]\$cfg.installFolder)
  [void][MsiRuntimeFormatter]::MsiSetPropertyW(\$hPkg, "HubScriptsFolder", [string]\$cfg.hubScripts)
  [void][MsiRuntimeFormatter]::MsiSetPropertyW(\$hPkg, "HUB_PORT", [string]\$cfg.hubPort)
  [void][MsiRuntimeFormatter]::MsiSetPropertyW(\$hPkg, "DISCOVERY_PORT", [string]\$cfg.discoveryPort)
  [void][MsiRuntimeFormatter]::MsiSetPropertyW(\$hPkg, "ALLOW_DEFERRED_TLS_START", [string]\$cfg.allowDeferredTls)
  [void][MsiRuntimeFormatter]::MsiSetPropertyW(\$hPkg, "PURGE_USER_DATA", [string]\$cfg.purgeUserData)
  [void][MsiRuntimeFormatter]::MsiSetPropertyW(\$hPkg, "CONFIRM_PURGE_TOKEN", [string]\$cfg.confirmPurgeToken)

  if ([MsiRuntimeFormatter]::MsiDoActionW(\$hPkg, "CA_SetInstallCtx") -ne 0) { throw "CA_SetInstallCtx failed" }
  if ([MsiRuntimeFormatter]::MsiDoActionW(\$hPkg, "CA_SetUninstallCtx") -ne 0) { throw "CA_SetUninstallCtx failed" }

  [ordered]@{
    MMS_CA_INSTALL_CTX = [MsiRuntimeFormatter]::GetProp(\$hPkg, "MMS_CA_INSTALL_CTX")
    MMS_CA_UNINSTALL_CTX = [MsiRuntimeFormatter]::GetProp(\$hPkg, "MMS_CA_UNINSTALL_CTX")
    CA_InstallOrUpgrade = [MsiRuntimeFormatter]::FormatTemplate(\$hPkg, [string]\$cfg.targets.CA_InstallOrUpgrade)
    CA_CommitInstall = [MsiRuntimeFormatter]::FormatTemplate(\$hPkg, [string]\$cfg.targets.CA_CommitInstall)
    CA_Uninstall = [MsiRuntimeFormatter]::FormatTemplate(\$hPkg, [string]\$cfg.targets.CA_Uninstall)
  } | ConvertTo-Json -Compress
} finally {
  if (\$hPkg -ne [IntPtr]::Zero) { [void][MsiRuntimeFormatter]::MsiCloseHandle(\$hPkg) }
}
''';
    final r = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      nativeScript,
    ]);
    expect(r.exitCode, equals(0), reason: '${r.stdout}\n${r.stderr}');
    return Map<String, String>.from(jsonDecode(r.stdout as String) as Map);
  }

  Future<({int exitCode, String stdout, String stderr})> runExactExeCommand(
    String fullExeCommand, {
    String? workingDir,
  }) async {
    final b64Cmd = base64Encode(utf8.encode(fullExeCommand));
    final work = workingDir ?? repoRoot;
    final runner =
        '''
\$full = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64Cmd'))
\$idx = \$full.IndexOf(' ')
\$exe = \$full.Substring(0, \$idx)
\$argsLine = \$full.Substring(\$idx + 1)
\$psi = New-Object System.Diagnostics.ProcessStartInfo
\$psi.FileName = \$exe
\$psi.Arguments = \$argsLine
\$psi.WorkingDirectory = '${work.replaceAll("'", "''")}'
\$psi.UseShellExecute = \$false
\$psi.RedirectStandardOutput = \$true
\$psi.RedirectStandardError = \$true
\$proc = [System.Diagnostics.Process]::Start(\$psi)
\$so = \$proc.StandardOutput.ReadToEnd()
\$se = \$proc.StandardError.ReadToEnd()
\$proc.WaitForExit()
[ordered]@{ exitCode = \$proc.ExitCode; stdout = \$so; stderr = \$se } | ConvertTo-Json -Compress
''';
    final r = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      runner,
    ]);
    expect(r.exitCode, equals(0), reason: '${r.stdout}\n${r.stderr}');
    final parsed = jsonDecode(r.stdout as String) as Map<String, dynamic>;
    return (
      exitCode: (parsed['exitCode'] as num).toInt(),
      stdout: parsed['stdout'] as String? ?? '',
      stderr: parsed['stderr'] as String? ?? '',
    );
  }

  group('AUD-CRIT-01: MSI PowerShell arguman aktarimi, trailing backslash, ACL & Firewall baglantilari', () {
    test('1. WiX MSI Property, File ve CustomAction tablolari guvenli parametre ve script baglantilarini icerir', () async {
      final msiData = await buildAndInspectSyntheticMsi('crit01');
      final props = <String, String>{};
      for (final row in List<String>.from(msiData['properties'] as List)) {
        final idx = row.indexOf('|');
        if (idx > 0) {
          props[row.substring(0, idx)] = row.substring(idx + 1);
        }
      }

      final secureProps = (props['SecureCustomProperties'] ?? '')
          .split(';')
          .toSet();
      expect(
        secureProps,
        containsAll([
          'PURGE_USER_DATA',
          'CONFIRM_PURGE_TOKEN',
          'ALLOW_DEFERRED_TLS_START',
          'HUB_PORT',
          'DISCOVERY_PORT',
        ]),
      );

      final launchConds = List<String>.from(
        msiData['launch_conditions'] as List,
      ).join('\n');
      expect(launchConds, contains('Installed OR VersionNT64'));
      expect(launchConds, contains('Installed OR ALLUSERS=1'));

      final files = List<String>.from(msiData['files'] as List)
          .join('\n')
          .toLowerCase();
      expect(files, contains('setup_service_acls.ps1'));
      expect(files, contains('configure_hub_firewall.ps1'));

      final targets = parseCustomActionTargets(msiData);
      expect(
        targets.keys,
        containsAll([
          'CA_SetInstallCtx',
          'CA_SetUninstallCtx',
          'CA_RollbackInstall',
          'CA_InstallOrUpgrade',
          'CA_CommitInstall',
          'CA_Uninstall',
        ]),
      );
      for (final entry in targets.entries) {
        expect(
          entry.value.length,
          lessThanOrEqualTo(255),
          reason:
              '${entry.key} CustomAction.Target 255 karakter sinirini (${entry.value.length}) asmamali (ICE03)',
        );
      }

      final caSetInstall = targets['CA_SetInstallCtx'] ?? '';
      expect(
        caSetInstall,
        equals(
          'Install|[INSTALLFOLDER].|1.0.0|[HUB_PORT]|[DISCOVERY_PORT]|[ALLOW_DEFERRED_TLS_START]',
        ),
      );

      final caSetUninstall = targets['CA_SetUninstallCtx'] ?? '';
      expect(
        caSetUninstall,
        equals(
          'Uninstall|[INSTALLFOLDER].|[HUB_PORT]|[DISCOVERY_PORT]|[PURGE_USER_DATA]|[CONFIRM_PURGE_TOKEN]|END',
        ),
      );

      final caInstall = targets['CA_InstallOrUpgrade'] ?? '';
      expect(
        caInstall,
        contains('-File "[HubScriptsFolder]mms_installer_engine.ps1"'),
      );
      expect(
        caInstall,
        contains('-MsiManaged -MsiContext "[MMS_CA_INSTALL_CTX]"'),
      );

      final caRollback = targets['CA_RollbackInstall'] ?? '';
      expect(caRollback, contains('"[INSTALLFOLDER]."'));
      expect(caRollback, isNot(contains('"[INSTALLFOLDER]"')));
      expect(caRollback, contains('-MsiManaged'));

      final caUninstall = targets['CA_Uninstall'] ?? '';
      expect(
        caUninstall,
        contains('-File "[HubScriptsFolder]mms_installer_engine.ps1"'),
      );
      expect(
        caUninstall,
        contains('-MsiManaged -MsiContext "[MMS_CA_UNINSTALL_CTX]"'),
      );
    });

    test('2. Gercek msi.dll MsiDoActionW+MsiFormatRecordW ile uretilen bosluklu ve trailing backslash komutlari kurulur ve kaldirilir', () async {
      final msiData = await buildAndInspectSyntheticMsi('crit01_exec');
      final msiPath = msiData['msi_path'] as String;
      final targets = parseCustomActionTargets(msiData);

      // Bosluk iceren hedef kurulum dizini (MSI gibi C:\...\Program Files\Market MMS\ biciminde sondaki \ ile yerine konacak)
      final installDir = Directory(
        p.join(tempRoot.path, 'Program Files', 'Market MMS'),
      );
      final dataRoot = Directory(
        p.join(tempRoot.path, 'Program Data', 'Market MMS'),
      );
      final srcStage = createSyntheticStaging('crit01_stage');

      // MSI InstallFiles aşamasının kopyaladığı dosya düzenini oluştur
      for (final sub in ['client', 'hub_bin', 'hub_scripts']) {
        final dstSub = Directory(p.join(installDir.path, sub))
          ..createSync(recursive: true);
        for (final f in Directory(
          p.join(srcStage.path, sub),
        ).listSync().whereType<File>()) {
          f.copySync(p.join(dstSub.path, p.basename(f.path)));
        }
      }

      Future<Map<String, String>> formatWithNativeMsiDll({
        required String hubPort,
        required String discoveryPort,
        required String allowDeferredTls,
        required String purgeUserData,
        required String confirmPurgeToken,
      }) {
        return formatWithNativeMsiDllFor(
          msiPath: msiPath,
          installDir: installDir,
          targets: targets,
          hubPort: hubPort,
          discoveryPort: discoveryPort,
          allowDeferredTls: allowDeferredTls,
          purgeUserData: purgeUserData,
          confirmPurgeToken: confirmPurgeToken,
        );
      }

      // 2a. ALLOW_DEFERRED_TLS_START=0 + sertifika yokken msi.dll formatlı komut fail-closed (exit 74, ERR_TLS_CERTS_MISSING)
      final fmtFailDeferred = await formatWithNativeMsiDll(
        hubPort: '9443',
        discoveryPort: '9444',
        allowDeferredTls: '0',
        purgeUserData: '0',
        confirmPurgeToken: '',
      );
      expect(fmtFailDeferred['MMS_CA_INSTALL_CTX'], contains('|9443|9444|0'));
      final failDeferredRes = await runExactExeCommand(
        '${fmtFailDeferred['CA_InstallOrUpgrade']!} -ProgramDataRoot "${dataRoot.path}\\." -TestSandboxMode',
      );
      expect(
        failDeferredRes.exitCode,
        equals(74),
        reason: '${failDeferredRes.stdout}\n${failDeferredRes.stderr}',
      );
      expect(failDeferredRes.stderr, contains('ERR_TLS_CERTS_MISSING'));

      // 2b. MsiManaged altinda setup_service_acls.ps1 eksikse fail-closed (exit 71 ERR_MISSING_RUNTIME_ARTIFACT)
      final aclScriptInstalled = File(
        p.join(installDir.path, 'hub_scripts', 'setup_service_acls.ps1'),
      );
      final aclBytes = aclScriptInstalled.readAsBytesSync();
      aclScriptInstalled.deleteSync();
      final fmtOk = await formatWithNativeMsiDll(
        hubPort: '9443',
        discoveryPort: '9444',
        allowDeferredTls: '1',
        purgeUserData: '0',
        confirmPurgeToken: '',
      );
      final missingAclRes = await runExactExeCommand(
        '${fmtOk['CA_InstallOrUpgrade']!} -ProgramDataRoot "${dataRoot.path}\\." -TestSandboxMode',
      );
      expect(
        missingAclRes.exitCode,
        equals(71),
        reason: '${missingAclRes.stdout}\n${missingAclRes.stderr}',
      );
      expect(missingAclRes.stderr, contains('ERR_MISSING_RUNTIME_ARTIFACT'));
      aclScriptInstalled.writeAsBytesSync(aclBytes);

      // 2c. ALLOW_DEFERRED_TLS_START=1 ile kurulum başarılı olmalı ve port/script cozumleme eksiksiz calismali
      final installRes = await runExactExeCommand(
        '${fmtOk['CA_InstallOrUpgrade']!} -ProgramDataRoot "${dataRoot.path}\\." -TestSandboxMode',
      );
      expect(
        installRes.exitCode,
        equals(0),
        reason: '${installRes.stdout}\n${installRes.stderr}',
      );
      final instManifest =
          jsonDecode(installRes.stdout) as Map<String, dynamic>;
      expect(instManifest['acl_script_path'], equals(aclScriptInstalled.path));
      expect(
        instManifest['firewall_script_path'],
        equals(
          p.join(installDir.path, 'hub_scripts', 'configure_hub_firewall.ps1'),
        ),
      );

      final cfgJson = jsonDecode(
        File(p.join(dataRoot.path, 'config', 'hub_config.json'))
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(cfgJson['port'], equals(9443));
      expect(cfgJson['discovery_port'], equals(9444));

      // CA_CommitInstall çalışınca geçici artifaktlar temizlenmeli
      final commitRes = await runExactExeCommand(
        '${fmtOk['CA_CommitInstall']!} -ProgramDataRoot "${dataRoot.path}\\." -TestSandboxMode',
      );
      expect(
        commitRes.exitCode,
        equals(0),
        reason: '${commitRes.stdout}\n${commitRes.stderr}',
      );

      // Veri dosyası oluştur
      final dbMarker = File(p.join(dataRoot.path, 'data', 'market_master.db'))
        ..writeAsStringSync('KEEP_DB');

      // 2d. CA_Uninstall CWD'si Directory="HubScriptsFolder" iken (InstallDir altında!) PURGE_USER_DATA=0 ile çalışmalı
      final hubScriptsCwd = p.join(installDir.path, 'hub_scripts');
      final uninstallKeepRes = await runExactExeCommand(
        '${fmtOk['CA_Uninstall']!} -ProgramDataRoot "${dataRoot.path}\\." -TestSandboxMode',
        workingDir: hubScriptsCwd,
      );
      expect(
        uninstallKeepRes.exitCode,
        equals(0),
        reason: '${uninstallKeepRes.stdout}\n${uninstallKeepRes.stderr}',
      );
      expect(
        (jsonDecode(uninstallKeepRes.stdout) as Map)['user_data_preserved'],
        isTrue,
      );
      expect(dbMarker.existsSync(), isTrue);

      // 2e. PURGE_USER_DATA=1 + doğru token ile kullanıcı verileri silinmeli
      final fmtPurge = await formatWithNativeMsiDll(
        hubPort: '9443',
        discoveryPort: '9444',
        allowDeferredTls: '1',
        purgeUserData: '1',
        confirmPurgeToken: 'CONFIRM_DELETE_ALL_MARKET_MMS_DATA',
      );
      final uninstallPurgeRes = await runExactExeCommand(
        '${fmtPurge['CA_Uninstall']!} -ProgramDataRoot "${dataRoot.path}\\." -TestSandboxMode',
        workingDir: hubScriptsCwd,
      );
      expect(
        uninstallPurgeRes.exitCode,
        equals(0),
        reason: '${uninstallPurgeRes.stdout}\n${uninstallPurgeRes.stderr}',
      );
      expect(
        (jsonDecode(uninstallPurgeRes.stdout) as Map)['user_data_purged'],
        isTrue,
      );
      expect(dataRoot.existsSync(), isFalse);
    });

    test('3. -AclScriptPath ve -FirewallScriptPath acikca verilmediginde hub_scripts altindan otomatik cozumlenir', () async {
      final installDir = Directory(
        p.join(tempRoot.path, 'ProgramFiles', 'MarketMMS'),
      );
      final dataRoot = Directory(
        p.join(tempRoot.path, 'ProgramData', 'MarketMMS'),
      );
      final stage = createSyntheticStaging('crit01_fallback');

      final res = await runEngine(
        action: 'Install',
        installDir: installDir,
        programDataRoot: dataRoot,
        stagingDir: stage,
      );
      expect(res.exitCode, equals(0), reason: '${res.stdout}\n${res.stderr}');
      final manifest = jsonDecode(res.stdout as String) as Map<String, dynamic>;
      expect(
        manifest['acl_script_path'],
        equals(p.join(stage.path, 'hub_scripts', 'setup_service_acls.ps1')),
      );
      expect(
        manifest['firewall_script_path'],
        equals(p.join(stage.path, 'hub_scripts', 'configure_hub_firewall.ps1')),
      );
    });
  });

  group('AUD-CRIT-02: Tek sorumluluklu idempotent Rollback ve MajorUpgrade siralamasi', () {
    test('1. WiX InstallExecuteSequence tablosunda MajorUpgrade afterInstallInitialize ve CA_CommitInstall yer alir', () async {
      final msiData = await buildAndInspectSyntheticMsi('crit02_seq');
      final seqMap = <String, int>{};
      for (final row in List<String>.from(msiData['sequence'] as List)) {
        final parts = row.split('|');
        if (parts.length >= 3) {
          seqMap[parts[0]] = int.parse(parts[2]);
        }
      }

      expect(seqMap['InstallInitialize'], isNotNull);
      expect(seqMap['RemoveExistingProducts'], isNotNull);
      expect(seqMap['InstallFiles'], isNotNull);
      expect(seqMap['CA_InstallOrUpgrade'], isNotNull);
      expect(seqMap['CA_RollbackInstall'], isNotNull);
      expect(seqMap['CA_CommitInstall'], isNotNull);

      expect(
        seqMap['RemoveExistingProducts']!,
        greaterThan(seqMap['InstallInitialize']!),
      );
      expect(
        seqMap['RemoveExistingProducts']!,
        lessThan(seqMap['InstallFiles']!),
      );
      expect(
        seqMap['CA_RollbackInstall']!,
        lessThan(seqMap['CA_InstallOrUpgrade']!),
      );
      expect(
        seqMap['CA_CommitInstall']!,
        greaterThan(seqMap['CA_InstallOrUpgrade']!),
      );
    });

    test('2. MsiManaged modda basarisiz upgrade -> CA_RollbackInstall -> tekrar CA_RollbackInstall v1.0.0 servisi ve manifesti korur', () async {
      final installDir = Directory(
        p.join(tempRoot.path, 'ProgramFiles', 'MarketMMS'),
      );
      final dataRoot = Directory(
        p.join(tempRoot.path, 'ProgramData', 'MarketMMS'),
      );
      final stage10 = createSyntheticStaging('v100');
      final stage11 = createSyntheticStaging('v110');
      seedSyntheticCerts(dataRoot);

      // v1.0.0 kurulum
      final inst10 = await runEngine(
        action: 'Install',
        installDir: installDir,
        programDataRoot: dataRoot,
        stagingDir: stage10,
        appVersion: '1.0.0',
      );
      expect(inst10.exitCode, equals(0), reason: '${inst10.stderr}');
      File(p.join(dataRoot.path, 'data', 'market_master.db'))
          .writeAsStringSync('IMPORTANT_V100_DATA');

      // v1.1.0 upgrade denemesi MsiManaged modunda HealthCheck ve Migration hatasi ile duser
      for (final fault in ['HealthCheck', 'Migration']) {
        final failRes = await runEngine(
          action: 'Install',
          installDir: installDir,
          programDataRoot: dataRoot,
          stagingDir: stage11,
          appVersion: '1.1.0',
          faultInjection: fault,
          msiManaged: true,
        );
        expect(failRes.exitCode, equals(74), reason: '$fault 74 donmeli');

        // Tekil MSI rollback eylemi (CA_RollbackInstall) v1.0.0'i geri yukler
        final rb1 = await runEngine(
          action: 'Rollback',
          installDir: installDir,
          programDataRoot: dataRoot,
          appVersion: '1.1.0',
          msiManaged: true,
        );
        expect(rb1.exitCode, equals(0), reason: '${rb1.stderr}');
        expect(
          File(p.join(dataRoot.path, 'bin', 'mms_backend.exe'))
              .readAsStringSync(),
          equals('HUB_v100'),
        );
        expect(
          File(p.join(dataRoot.path, 'lib', 'sqlite3.dll')).readAsStringSync(),
          equals('SQLITE_v100'),
        );
        expect(
          File(p.join(dataRoot.path, 'bin', 'lib', 'sqlite3.dll'))
              .readAsStringSync(),
          equals('SQLITE_v100'),
        );

        final manifestRb1 = jsonDecode(
          File(p.join(dataRoot.path, 'config', 'install_manifest.json'))
              .readAsStringSync(),
        ) as Map;
        expect(manifestRb1['app_version'], equals('1.0.0'));
        final scmRb1 = jsonDecode(
          File(p.join(dataRoot.path, 'run', 'sandbox_scm.json'))
              .readAsStringSync(),
        ) as Map;
        expect(scmRb1['status'], equals('Running'));
        expect(scmRb1['version'], equals('1.0.0'));
        expect(
          File(p.join(dataRoot.path, 'data', 'market_master.db'))
              .readAsStringSync(),
          equals('IMPORTANT_V100_DATA'),
        );

        // Idempotency: CA_RollbackInstall ikinci kez cagirilsa dahi v1.0.0 servisi veya manifesti SILMEZ
        final rb2 = await runEngine(
          action: 'Rollback',
          installDir: installDir,
          programDataRoot: dataRoot,
          appVersion: '1.1.0',
          msiManaged: true,
        );
        expect(rb2.exitCode, equals(0), reason: '${rb2.stderr}');
        expect(
          File(p.join(dataRoot.path, 'bin', 'mms_backend.exe'))
              .readAsStringSync(),
          equals('HUB_v100'),
        );
        expect(
          File(p.join(dataRoot.path, 'config', 'install_manifest.json'))
              .existsSync(),
          isTrue,
        );
        final scmRb2 = jsonDecode(
          File(p.join(dataRoot.path, 'run', 'sandbox_scm.json'))
              .readAsStringSync(),
        ) as Map;
        expect(scmRb2['status'], equals('Running'));
      }

      // Basarili MsiManaged upgrade + Commit
      final okUpg = await runEngine(
        action: 'Install',
        installDir: installDir,
        programDataRoot: dataRoot,
        stagingDir: stage11,
        appVersion: '1.1.0',
        msiManaged: true,
      );
      expect(okUpg.exitCode, equals(0), reason: '${okUpg.stderr}');
      // Commit oncesi .previous yedekleri henuz korunuyor olmali (gec MSI rollback guvenligi)
      expect(
        Directory(p.join(dataRoot.path, 'bin.previous')).existsSync(),
        isTrue,
      );

      final commitRes = await runEngine(
        action: 'Commit',
        installDir: installDir,
        programDataRoot: dataRoot,
        appVersion: '1.1.0',
        msiManaged: true,
      );
      expect(commitRes.exitCode, equals(0), reason: '${commitRes.stderr}');
      expect(
        Directory(p.join(dataRoot.path, 'bin.previous')).existsSync(),
        isFalse,
      );
      expect(
        File(p.join(dataRoot.path, 'config', 'install_manifest.previous.json'))
            .existsSync(),
        isFalse,
      );
      expect(
        File(p.join(dataRoot.path, 'run', 'installer_tx_state.json'))
            .existsSync(),
        isFalse,
      );
      expect(
        File(p.join(dataRoot.path, 'bin', 'mms_backend.exe'))
            .readAsStringSync(),
        equals('HUB_v110'),
      );
    });

    test('3. Standalone (non-MsiManaged) basarisiz upgrade sonrasi ek -Action Rollback cagrisi da cift rollback yikimi yapmaz', () async {
      final installDir = Directory(
        p.join(tempRoot.path, 'ProgramFiles', 'MarketMMS'),
      );
      final dataRoot = Directory(
        p.join(tempRoot.path, 'ProgramData', 'MarketMMS'),
      );
      final stage10 = createSyntheticStaging('v100');
      final stage11 = createSyntheticStaging('v110');
      seedSyntheticCerts(dataRoot);

      expect(
        (await runEngine(
          action: 'Install',
          installDir: installDir,
          programDataRoot: dataRoot,
          stagingDir: stage10,
          appVersion: '1.0.0',
        )).exitCode,
        equals(0),
      );

      final failStandalone = await runEngine(
        action: 'Install',
        installDir: installDir,
        programDataRoot: dataRoot,
        stagingDir: stage11,
        appVersion: '1.1.0',
        faultInjection: 'HealthCheck',
      );
      expect(failStandalone.exitCode, equals(74));

      // Ardından dışarıdan -Action Rollback çağrılsa bile çalışan v1.0.0 servisi silinmez
      final extraRb = await runEngine(
        action: 'Rollback',
        installDir: installDir,
        programDataRoot: dataRoot,
        appVersion: '1.1.0',
      );
      expect(extraRb.exitCode, equals(0));
      final scm = jsonDecode(
        File(p.join(dataRoot.path, 'run', 'sandbox_scm.json'))
            .readAsStringSync(),
      ) as Map;
      expect(scm['status'], equals('Running'));
      expect(
        File(p.join(dataRoot.path, 'config', 'install_manifest.json'))
            .existsSync(),
        isTrue,
      );
    });
  });

  group(
    'AUD-HIGH-03: Ozel Root CA (ca.crt) kullanan Hub TLS /health dogrulamasi',
    () {
      test('1. Ozel MMS Root CA ile HTTPS /health dogrulanir; sahte CA, suresi dolmus sertifika ve eksik 127.0.0.1 SAN fail-closed reddedilir', () async {
        final caOfflineDir = Directory(p.join(tempRoot.path, 'offline_ca'))
          ..createSync(recursive: true);
        final legitimateCaKey = p.join(caOfflineDir.path, 'ca.key');
        final legitimateCaCert = p.join(caOfflineDir.path, 'ca.crt');
        CertificateManager.generateRootCa(
          caKeyPath: legitimateCaKey,
          caCertPath: legitimateCaCert,
        );

        final rogueCaKey = p.join(caOfflineDir.path, 'rogue_ca.key');
        final rogueCaCert = p.join(caOfflineDir.path, 'rogue_ca.crt');
        CertificateManager.generateRootCa(
          caKeyPath: rogueCaKey,
          caCertPath: rogueCaCert,
          commonName: 'Rogue CA',
        );

        final installDir = Directory(
          p.join(tempRoot.path, 'ProgramFiles', 'MarketMMS'),
        );
        final dataRoot = Directory(
          p.join(tempRoot.path, 'ProgramData', 'MarketMMS'),
        );
        final stage = createSyntheticStaging('tls');

        final certsDir = Directory(p.join(dataRoot.path, 'certs'))
          ..createSync(recursive: true);
        final serverCertPath = p.join(certsDir.path, 'server.crt');
        final serverKeyPath = p.join(certsDir.path, 'server.key');
        File(legitimateCaCert).copySync(p.join(certsDir.path, 'ca.crt'));

        CertificateManager.generateServerCertificate(
          caKeyPath: legitimateCaKey,
          caCertPath: legitimateCaCert,
          serverKeyPath: serverKeyPath,
          serverCertPath: serverCertPath,
          sanList: const ['localhost', '127.0.0.1'],
        );

        // 1a. Geçerli özel Root CA + IP:127.0.0.1 SAN -> HTTPS /health başarılı (exit 0)
        final serverDir = Directory(p.join(tempRoot.path, 'live_tls_hub'))
          ..createSync(recursive: true);
        final dbFile = File(p.join(serverDir.path, 'data', 'market_master.db'))
          ..parent.createSync(recursive: true);
        final liveDb = SpikeDatabase(dbFile);
        final pepper = PepperManager(
          File(p.join(serverDir.path, 'security', 'pepper.dpapi')),
        )..initialize(overrideForTesting: 'stage3_tls_pepper_32bytes_long!');
        final secCtx = CertificateManager.createServerSecurityContext(
          certChainPath: serverCertPath,
          privateKeyPath: serverKeyPath,
        );
        final server = SpikeServer(
          db: liveDb,
          dbFile: dbFile,
          writeQueue: WriteQueue(),
          backupDirectory: p.join(serverDir.path, 'backups'),
          adminSecret: 'stage3_tls_admin_secret_2026',
          pepperManager: pepper,
          securityContext: secCtx,
          requireTls: true,
          caCertPath: p.join(certsDir.path, 'ca.crt'),
          serverCertPath: serverCertPath,
        );
        final sock = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final tlsPort = sock.port;
        await sock.close();
        await server.start(
          address: InternetAddress.loopbackIPv4,
          port: tlsPort,
          enableDiscovery: false,
        );
        await server.hubRecoveryKeyStore.saveRecoveryPassword(
          'OwnerTlsRecovery-2026!',
        );

        try {
          final okRes = await runEngine(
            action: 'Install',
            installDir: installDir,
            programDataRoot: dataRoot,
            stagingDir: stage,
            healthCheckUrl: 'https://127.0.0.1:$tlsPort/health',
          );
          expect(
            okRes.exitCode,
            equals(0),
            reason: '${okRes.stdout}\n${okRes.stderr}',
          );
          final manifest =
              jsonDecode(okRes.stdout as String) as Map<String, dynamic>;
          expect(manifest['health_verified'], isTrue);
          expect(manifest['recovery_key_configured'], isTrue);
        } finally {
          await server.stop();
        }

        // 1b. Sahte (Rogue) Root CA ile imzalı sunucu -> fail-closed rollback (exit 74)
        final rogueSrvCert = p.join(caOfflineDir.path, 'rogue_server.crt');
        final rogueSrvKey = p.join(caOfflineDir.path, 'rogue_server.key');
        CertificateManager.generateServerCertificate(
          caKeyPath: rogueCaKey,
          caCertPath: rogueCaCert,
          serverKeyPath: rogueSrvKey,
          serverCertPath: rogueSrvCert,
          sanList: const ['localhost', '127.0.0.1'],
        );
        final rogueHttps = await HttpServer.bindSecure(
          InternetAddress.loopbackIPv4,
          0,
          CertificateManager.createServerSecurityContext(
            certChainPath: rogueSrvCert,
            privateKeyPath: rogueSrvKey,
          ),
        );
        rogueHttps.listen((req) {
          req.response
            ..statusCode = 200
            ..write('{"status":"UP","backup":{"recovery_key_configured":true}}')
            ..close();
        });
        try {
          final rogueRes = await runEngine(
            action: 'Install',
            installDir: installDir,
            programDataRoot: dataRoot,
            stagingDir: stage,
            appVersion: '1.1.0',
            healthCheckUrl: 'https://127.0.0.1:${rogueHttps.port}/health',
          );
          expect(rogueRes.exitCode, equals(74));
        } finally {
          await rogueHttps.close(force: true);
        }

        // 1c. Süresi dolmuş (expired) sunucu sertifikası -> fail-closed rollback (exit 74)
        final expSrvCert = p.join(caOfflineDir.path, 'exp_server.crt');
        final expSrvKey = p.join(caOfflineDir.path, 'exp_server.key');
        generateServerCertWithParams(
          caKeyPath: legitimateCaKey,
          caCertPath: legitimateCaCert,
          serverKeyPath: expSrvKey,
          serverCertPath: expSrvCert,
          sanList: const ['localhost', '127.0.0.1'],
          notBefore: '20200101000000Z',
          notAfter: '20200102000000Z',
        );
        final expHttps = await HttpServer.bindSecure(
          InternetAddress.loopbackIPv4,
          0,
          CertificateManager.createServerSecurityContext(
            certChainPath: expSrvCert,
            privateKeyPath: expSrvKey,
          ),
        );
        expHttps.listen((req) {
          req.response
            ..statusCode = 200
            ..write('{"status":"UP","backup":{"recovery_key_configured":true}}')
            ..close();
        });
        try {
          final expRes = await runEngine(
            action: 'Install',
            installDir: installDir,
            programDataRoot: dataRoot,
            stagingDir: stage,
            appVersion: '1.1.0',
            healthCheckUrl: 'https://127.0.0.1:${expHttps.port}/health',
          );
          expect(expRes.exitCode, equals(74));
        } finally {
          await expHttps.close(force: true);
        }

        // 1d. 127.0.0.1 IP SAN içermeyen sunucu sertifikası -> fail-closed rollback (exit 74)
        final badSanCert = p.join(caOfflineDir.path, 'badsan_server.crt');
        final badSanKey = p.join(caOfflineDir.path, 'badsan_server.key');
        CertificateManager.generateServerCertificate(
          caKeyPath: legitimateCaKey,
          caCertPath: legitimateCaCert,
          serverKeyPath: badSanKey,
          serverCertPath: badSanCert,
          sanList: const ['localhost', '192.0.2.55'],
        );
        final badSanHttps = await HttpServer.bindSecure(
          InternetAddress.loopbackIPv4,
          0,
          CertificateManager.createServerSecurityContext(
            certChainPath: badSanCert,
            privateKeyPath: badSanKey,
          ),
        );
        badSanHttps.listen((req) {
          req.response
            ..statusCode = 200
            ..write('{"status":"UP","backup":{"recovery_key_configured":true}}')
            ..close();
        });
        try {
          final badSanRes = await runEngine(
            action: 'Install',
            installDir: installDir,
            programDataRoot: dataRoot,
            stagingDir: stage,
            appVersion: '1.1.0',
            healthCheckUrl: 'https://127.0.0.1:${badSanHttps.port}/health',
          );
          expect(badSanRes.exitCode, equals(74));
        } finally {
          await badSanHttps.close(force: true);
        }
      });
    },
  );

  group('AUD-MED-05: Per-machine HKLM kisayol KeyPath ve upgrade oncesi SQLite WAL guvenli yedekleme', () {
    test('1. WiX Registry tablosu perMachine kisayol bilesenleri icin yalniz HKLM (Root=2) KeyPath kullanir', () async {
      final msiData = await buildAndInspectSyntheticMsi('med05_reg');
      final regRows = List<String>.from(msiData['registry'] as List);
      expect(regRows, isNotEmpty);

      final componentRoots = <String, String>{};
      for (final row in regRows) {
        final parts = row.split('|');
        // Registry | Root | Key | Name | Component_
        expect(parts.length, greaterThanOrEqualTo(5));
        expect(
          parts[1],
          isNot(equals('1')),
          reason: 'Per-machine MSI icinde HKCU (Root=1) KeyPath olmamali: $row',
        );
        componentRoots[parts[4]] = parts[1];
      }

      expect(componentRoots['CmpStartMenuShortcut'], equals('2'));
      expect(componentRoots['CmpDesktopShortcut'], equals('2'));
    });

    test('2. Upgrade oncesi .pre_upgrade yedegi birlesmemis -wal cercevelerini VACUUM INTO ile yakalar ve canli DB/WAL dosyalarina dokunmaz', () async {
      final installDir = Directory(
        p.join(tempRoot.path, 'ProgramFiles', 'MarketMMS'),
      );
      final dataRoot = Directory(
        p.join(tempRoot.path, 'ProgramData', 'MarketMMS'),
      );
      final stage10 = createSyntheticStaging(
        'v100_wal',
        useRealSqliteDll: true,
      );
      final stage11 = createSyntheticStaging(
        'v110_wal',
        useRealSqliteDll: true,
      );
      seedSyntheticCerts(dataRoot);

      expect(
        (await runEngine(
          action: 'Install',
          installDir: installDir,
          programDataRoot: dataRoot,
          stagingDir: stage10,
          appVersion: '1.0.0',
        )).exitCode,
        equals(0),
      );

      final liveDbFile = File(
        p.join(dataRoot.path, 'data', 'market_master.db'),
      );
      final initDb = SpikeDatabase(liveDbFile);
      await initDb
          .into(initDb.products)
          .insert(
            ProductsCompanion.insert(
              id: 'prod_base_01',
              barcode: '8690000000011',
              name: 'Temel Urun',
              price: 1000,
              stock: 2000,
            ),
          );
      await initDb.close();

      // Alt süreç açarak PRAGMA wal_autocheckpoint = 0 altında commit edilmiş satırı SADECE -wal içinde bırakıp kapatmadan çık
      final workerScript = File(
        p.join(tempRoot.path, 'write_unmerged_wal.dart'),
      );
      final packageConfigPath = p.join(
        repoRoot,
        'test_spikes',
        'spike_01_backend',
        '.dart_tool',
        'package_config.json',
      );
      workerScript.writeAsStringSync('''
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';

void main(List<String> args) {
  final dbPath = args[0];
  final db = sqlite3.open(dbPath);
  db.execute('PRAGMA journal_mode = WAL;');
  db.execute('PRAGMA wal_autocheckpoint = 0;');
  db.execute(
    "INSERT INTO products (id, barcode, name, price, stock) "
    "VALUES ('prod_wal_unmerged', '8690000000999', 'WAL Urunu', 15500, 4000);",
  );
  if (!File('\$dbPath-wal').existsSync() || File('\$dbPath-wal').lengthSync() <= 0) {
    exit(2);
  }
  exit(101);
}
''');

      final workerRes = await Process.run(Platform.resolvedExecutable, [
        'run',
        '--packages=$packageConfigPath',
        workerScript.path,
        liveDbFile.path,
      ], workingDirectory: p.join(repoRoot, 'test_spikes', 'spike_01_backend'));
      expect(
        workerRes.exitCode,
        equals(101),
        reason: '${workerRes.stdout}\n${workerRes.stderr}',
      );

      final liveWalFile = File('${liveDbFile.path}-wal');
      expect(liveWalFile.existsSync(), isTrue);
      expect(liveWalFile.lengthSync(), greaterThan(0));

      // Ön kontrol: yalnızca ana .db dosyasını (WAL olmadan) kopyaladığımızda prod_wal_unmerged HALA yok olmalı
      final rawOnlyCheckDir = Directory(p.join(tempRoot.path, 'raw_only_check'))
        ..createSync(recursive: true);
      final rawOnlyDb = File(p.join(rawOnlyCheckDir.path, 'raw.db'));
      liveDbFile.copySync(rawOnlyDb.path);
      final rawSq = sq.sqlite3.open(rawOnlyDb.path);
      final rawRows = rawSq.select(
        "SELECT id FROM products WHERE id = 'prod_wal_unmerged'",
      );
      rawSq.close();
      expect(
        rawRows,
        isEmpty,
        reason: 'On kosul: satir sadece -wal dosyasinda olmali',
      );

      final dbBytesBefore = liveDbFile.readAsBytesSync();
      final walBytesBefore = liveWalFile.readAsBytesSync();

      // Upgrade çalıştır
      final upgRes = await runEngine(
        action: 'Install',
        installDir: installDir,
        programDataRoot: dataRoot,
        stagingDir: stage11,
        appVersion: '1.1.0',
      );
      expect(
        upgRes.exitCode,
        equals(0),
        reason: '${upgRes.stdout}\n${upgRes.stderr}',
      );

      // Canlı DB ve WAL dosyalarına dokunulmamış olmalı
      expect(liveDbFile.readAsBytesSync(), equals(dbBytesBefore));
      expect(liveWalFile.readAsBytesSync(), equals(walBytesBefore));

      final manifest =
          jsonDecode(upgRes.stdout as String) as Map<String, dynamic>;
      final backupPath = manifest['pre_upgrade_backup_path'] as String;
      expect(File(backupPath).existsSync(), isTrue);

      // Backup dosyasını TEK BAŞINA boş bir klasöre kopyalayıp aç (yanında -wal/-shm olmadan)
      final isolatedRestoreDir = Directory(
        p.join(tempRoot.path, 'verify_pre_upgrade_only'),
      )..createSync(recursive: true);
      final soloBackupCopy = File(
        p.join(isolatedRestoreDir.path, 'restored_check.db'),
      );
      File(backupPath).copySync(soloBackupCopy.path);

      final checkDb = sq.sqlite3.open(soloBackupCopy.path);
      try {
        final integrity =
            checkDb.select('PRAGMA integrity_check;').first.values.first
                as String;
        expect(integrity, equals('ok'));
        final rows = checkDb.select(
          "SELECT id, price, stock FROM products ORDER BY id ASC",
        );
        final byId = {for (final r in rows) r['id'] as String: r};
        expect(byId.keys, containsAll(['prod_base_01', 'prod_wal_unmerged']));
        expect(byId['prod_wal_unmerged']!['price'], equals(15500));
        expect(byId['prod_wal_unmerged']!['stock'], equals(4000));
      } finally {
        checkDb.close();
      }
    });
  });

  group('AUD-DIAG-01: MSI MsiContext tanilama gunlugu, reparse-point korumasi ve erken hata kapsamasi', () {
    test('1. Gercek msi.dll ile formatlanan CA_InstallOrUpgrade ExitCode 74 verdiginde MsiManaged: True ve Stage loglar', () async {
      final msiData = await buildAndInspectSyntheticMsi('diag01_msi');
      final msiPath = msiData['msi_path'] as String;
      final targets = parseCustomActionTargets(msiData);
      final installDir = Directory(
        p.join(tempRoot.path, 'Program Files', 'Market MMS Diag'),
      );
      final dataRoot = Directory(
        p.join(tempRoot.path, 'Program Data', 'Market MMS Diag'),
      );
      final srcStage = createSyntheticStaging('diag01_stage');

      for (final sub in ['client', 'hub_bin', 'hub_scripts']) {
        final dstSub = Directory(p.join(installDir.path, sub))
          ..createSync(recursive: true);
        for (final f in Directory(
          p.join(srcStage.path, sub),
        ).listSync().whereType<File>()) {
          f.copySync(p.join(dstSub.path, p.basename(f.path)));
        }
      }

      final fmt = await formatWithNativeMsiDllFor(
        msiPath: msiPath,
        installDir: installDir,
        targets: targets,
        hubPort: '9455',
        discoveryPort: '9456',
        allowDeferredTls: '0',
        purgeUserData: '0',
        confirmPurgeToken: '',
      );
      final failRes = await runExactExeCommand(
        '${fmt['CA_InstallOrUpgrade']!} -ProgramDataRoot "${dataRoot.path}\\." -TestSandboxMode',
      );
      expect(failRes.exitCode, equals(74));

      final diagLog = File(
        p.join(dataRoot.path, 'logs', 'installer-diagnostics.log'),
      );
      expect(diagLog.existsSync(), isTrue);
      final content = diagLog.readAsStringSync();
      expect(content, contains('MsiManaged: True'));
      expect(content, contains('TestSandboxMode: True'));
      expect(content, contains('Stage: ServiceStart'));
      expect(content, contains('ErrorCode: ERR_INSTALLER_STEP_FAILED'));
      expect(content, contains('ERR_TLS_CERTS_MISSING'));
    });

    test('2. Bozuk install_manifest.json erken hatasi Stage: VersionCheck altinda ExitCode 74 ve log ile yakalanir', () async {
      final installDir = Directory(p.join(tempRoot.path, 'diag02_inst'));
      final dataRoot = Directory(p.join(tempRoot.path, 'diag02_data'));
      final configDir = Directory(p.join(dataRoot.path, 'config'))
        ..createSync(recursive: true);
      File(p.join(configDir.path, 'install_manifest.json'))
          .writeAsStringSync('{ invalid json');
      final curSidRes = Process.runSync('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        '([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value',
      ]);
      expect(curSidRes.exitCode, equals(0));
      final curSid = (curSidRes.stdout as String).trim();
      final lockDataRootRes = Process.runSync('icacls.exe', [
        dataRoot.path,
        '/inheritance:r',
        '/grant:r',
        '*S-1-5-18:(OI)(CI)F',
        '/grant:r',
        '*S-1-5-32-544:(OI)(CI)F',
        '/grant:r',
        '*$curSid:(OI)(CI)F',
      ]);
      expect(lockDataRootRes.exitCode, equals(0));
      final stage = createSyntheticStaging('diag02_stage');

      final res = await runEngine(
        action: 'Install',
        installDir: installDir,
        programDataRoot: dataRoot,
        stagingDir: stage,
        msiManaged: true,
      );
      expect(res.exitCode, equals(74));

      final diagLog = File(
        p.join(dataRoot.path, 'logs', 'installer-diagnostics.log'),
      );
      expect(diagLog.existsSync(), isTrue);
      final content = diagLog.readAsStringSync();
      expect(content, contains('Stage: VersionCheck'));
      expect(content, contains('ExitCode: 74'));
      expect(content, contains('ErrorCode: ERR_INSTALLER_PRECHECK_FAILED'));
      expect(content, contains('MsiManaged: True'));
    });

    test('3. Gercek CA_InstallOrUpgrade sirasinda logs uzerindeki reparse-point junction reddedilir ve ExitCode 74 korunur', () async {
      final msiData = await buildAndInspectSyntheticMsi('diag03_junc');
      final msiPath = msiData['msi_path'] as String;
      final targets = parseCustomActionTargets(msiData);
      final installDir = Directory(
        p.join(tempRoot.path, 'Program Files', 'Market MMS Junc'),
      );
      final dataRoot = Directory(
        p.join(tempRoot.path, 'Program Data', 'Market MMS Junc'),
      )..createSync(recursive: true);
      final outsideDir = Directory(
        p.join(tempRoot.path, 'outside_junction_target'),
      )..createSync(recursive: true);
      final srcStage = createSyntheticStaging('diag03_stage');

      for (final sub in ['client', 'hub_bin', 'hub_scripts']) {
        final dstSub = Directory(p.join(installDir.path, sub))
          ..createSync(recursive: true);
        for (final f in Directory(
          p.join(srcStage.path, sub),
        ).listSync().whereType<File>()) {
          f.copySync(p.join(dstSub.path, p.basename(f.path)));
        }
      }

      final tempFallbackPath = p.join(
        Platform.environment['TEMP'] ?? Directory.systemTemp.path,
        'market-mms-installer-diagnostics.log',
      );
      final tempFallbackExistedBefore = File(tempFallbackPath).existsSync();
      final logsJunction = p.join(dataRoot.path, 'logs');
      final mkJunc = Process.runSync('cmd', [
        '/c',
        'mklink',
        '/J',
        logsJunction,
        outsideDir.path,
      ]);
      expect(
        mkJunc.exitCode,
        equals(0),
        reason: '${mkJunc.stdout}\n${mkJunc.stderr}',
      );

      try {
        final fmt = await formatWithNativeMsiDllFor(
          msiPath: msiPath,
          installDir: installDir,
          targets: targets,
          hubPort: '9465',
          discoveryPort: '9466',
          allowDeferredTls: '0',
          purgeUserData: '0',
          confirmPurgeToken: '',
        );
        final failRes = await runExactExeCommand(
          '${fmt['CA_InstallOrUpgrade']!} -ProgramDataRoot "${dataRoot.path}\\." -TestSandboxMode',
        );
        // On-kurulum Assert-ProgramDataSafety junction'i yakalayip ExitCode 72 doner ve Write-InstallerDiagnosticLog da junction hedefe yazmaz
        expect(failRes.exitCode, equals(72));
        expect(failRes.stderr, contains('ERR_SECURITY_VIOLATION'));
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
        Process.runSync('cmd', ['/c', 'rmdir', logsJunction]);
      }
    });

    test('4. Gercek CA_InstallOrUpgrade sirasinda Users yazma izinli guvensiz logs dizini reddedilir ve ExitCode 74 korunur', () async {
      final msiData = await buildAndInspectSyntheticMsi('diag04_unsafe_acl');
      final msiPath = msiData['msi_path'] as String;
      final targets = parseCustomActionTargets(msiData);
      final installDir = Directory(p.join(tempRoot.path, 'Program Files', 'Market MMS UnsafeAcl'));
      final dataRoot = Directory(p.join(tempRoot.path, 'Program Data', 'Market MMS UnsafeAcl'))..createSync(recursive: true);
      final unsafeLogs = Directory(p.join(dataRoot.path, 'logs'))..createSync(recursive: true);
      final grantUsers = Process.runSync('icacls.exe', [unsafeLogs.path, '/grant', '*S-1-5-32-545:(OI)(CI)M']);
      expect(grantUsers.exitCode, equals(0), reason: '${grantUsers.stdout}\n${grantUsers.stderr}');

      final srcStage = createSyntheticStaging('diag04_stage');
      for (final sub in ['client', 'hub_bin', 'hub_scripts']) {
        final dstSub = Directory(p.join(installDir.path, sub))..createSync(recursive: true);
        for (final f in Directory(p.join(srcStage.path, sub)).listSync().whereType<File>()) {
          f.copySync(p.join(dstSub.path, p.basename(f.path)));
        }
      }

      final fmt = await formatWithNativeMsiDllFor(
        msiPath: msiPath,
        installDir: installDir,
        targets: targets,
        hubPort: '9475',
        discoveryPort: '9476',
        allowDeferredTls: '0',
        purgeUserData: '0',
        confirmPurgeToken: '',
      );
      final failRes = await runExactExeCommand(
        '${fmt['CA_InstallOrUpgrade']!} -ProgramDataRoot "${dataRoot.path}\\." -TestSandboxMode',
      );
      expect(failRes.exitCode, equals(74));
      expect(failRes.stderr, contains('ERR_SECURITY_VIOLATION'));
      expect(failRes.stderr, contains('S-1-5-32-545'));
      expect(File(p.join(unsafeLogs.path, 'installer-diagnostics.log')).existsSync(), isFalse);
    });

    test('5. Gercek CA_InstallOrUpgrade sirasinda Users yazma izinli guvensiz DataRoot reddedilir, log acilmaz ve ExitCode 74 korunur', () async {
      final msiData = await buildAndInspectSyntheticMsi('diag05_unsafe_dataroot');
      final msiPath = msiData['msi_path'] as String;
      final targets = parseCustomActionTargets(msiData);
      final installDir = Directory(p.join(tempRoot.path, 'Program Files', 'Market MMS UnsafeRoot'));
      final dataRoot = Directory(p.join(tempRoot.path, 'Program Data', 'Market MMS UnsafeRoot'))..createSync(recursive: true);
      final grantUsersRoot = Process.runSync('icacls.exe', [dataRoot.path, '/grant', '*S-1-5-32-545:(OI)(CI)M']);
      expect(grantUsersRoot.exitCode, equals(0), reason: '${grantUsersRoot.stdout}\n${grantUsersRoot.stderr}');

      final srcStage = createSyntheticStaging('diag05_stage');
      for (final sub in ['client', 'hub_bin', 'hub_scripts']) {
        final dstSub = Directory(p.join(installDir.path, sub))..createSync(recursive: true);
        for (final f in Directory(p.join(srcStage.path, sub)).listSync().whereType<File>()) {
          f.copySync(p.join(dstSub.path, p.basename(f.path)));
        }
      }

      final fmt = await formatWithNativeMsiDllFor(
        msiPath: msiPath,
        installDir: installDir,
        targets: targets,
        hubPort: '9485',
        discoveryPort: '9486',
        allowDeferredTls: '0',
        purgeUserData: '0',
        confirmPurgeToken: '',
      );
      final failRes = await runExactExeCommand(
        '${fmt['CA_InstallOrUpgrade']!} -ProgramDataRoot "${dataRoot.path}\\." -TestSandboxMode',
      );
      expect(failRes.exitCode, equals(74));
      expect(failRes.stderr, contains('ERR_INSTALLER_STEP_FAILED'));
      expect(File(p.join(dataRoot.path, 'logs', 'installer-diagnostics.log')).existsSync(), isFalse);
    });
  });
}
