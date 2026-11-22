import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/core/constants/app_constants.dart';

/// Faz 7C / SEC-ABK — Android üretim yapılandırmasının depo düzeyinde doğrulanması.
///
/// Android'in otomatik yedekleme (Google bulut yedeği ve cihazdan cihaza aktarım)
/// özelliği varsayılan olarak AÇIKTIR. Açık kalırsa:
///  * şifresiz yerel SQLite (satışlar, Outbox) ve kurulum dosyaları ADR-010/011
///    dışında Google hesabına kopyalanır (Drive yalnızca şifreli `.mmsbak` içindir);
///  * yeni bir cihaza geri yüklendiğinde aynı `device_id` ve `client_seq` sayacı iki
///    cihazda birden yaşar → Hub'da `ERR_IDEMPOTENCY_CONFLICT` / sıra çakışması.
/// Bu nedenle manifest yedeklemeyi kapatmalı ve API 31+ kurallarıyla tüm alanları
/// hariç tutmalıdır.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  final rules = File('android/app/src/main/res/xml/data_extraction_rules.xml');
  final gradle = File('android/app/build.gradle.kts');

  String applicationTag(String xml) =>
      RegExp(r'<application\b[^>]*>', dotAll: true).firstMatch(xml)!.group(0)!;

  test('Android otomatik yedekleme kapalı (allowBackup=false, fullBackupContent=false)', () {
    final app = applicationTag(manifest.readAsStringSync());
    expect(app, contains('android:allowBackup="false"'));
    expect(app, contains('android:fullBackupContent="false"'));
    expect(app, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
  });

  test('API 31+ veri çıkarma kuralları bulut yedeği ve cihaz aktarımında tüm alanları hariç tutar', () {
    expect(rules.existsSync(), isTrue, reason: 'res/xml/data_extraction_rules.xml eksik');
    final xml = rules.readAsStringSync();
    for (final section in ['cloud-backup', 'device-transfer']) {
      final body = RegExp('<$section>(.*?)</$section>', dotAll: true).firstMatch(xml)?.group(1);
      expect(body, isNotNull, reason: '<$section> bölümü yok');
      for (final domain in ['root', 'file', 'database', 'sharedpref', 'external']) {
        expect(body, contains('<exclude domain="$domain" path="."'),
            reason: '$section içinde $domain alanı hariç tutulmalı');
      }
      expect(body, isNot(contains('<include')), reason: '$section hiçbir alanı dahil etmemeli');
    }
  });

  test('Release: cleartext kapalı ve key.properties yoksa derleme durur (debug imzaya sessiz düşüş yok)', () {
    final g = gradle.readAsStringSync();
    expect(g, contains('manifestPlaceholders["usesCleartextTraffic"] = if (allowReleaseCleartext) "true" else "false"'));
    expect(g, contains('throw GradleException('));
    expect(g, contains('!hasReleaseKeystore && !allowDebugSigning'));
    expect(manifest.readAsStringSync(), contains(r'android:usesCleartextTraffic="${usesCleartextTraffic}"'));
  });

  test('key.properties ve keystore dosyaları Git dışında tutulur', () {
    final gitignore = File('.gitignore').readAsStringSync();
    expect(gitignore, contains('key.properties'));
    expect(gitignore, anyOf(contains('*.jks'), contains('*.keystore')));
  });

  test('Phase 1.1: pubspec.yaml sürümü 1.0.0+1, Gradle Flutter sürüm alanlarını kullanır ve paketleme betiği dinamik sürüm üretir', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final versionMatch = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(versionMatch, isNotNull, reason: 'pubspec.yaml geçerli X.Y.Z+N sürümü taşımalı');
    expect(versionMatch!.group(1), '1.0.0');
    expect(versionMatch.group(2), '1');
    expect(AppConstants.appVersion, versionMatch.group(1));

    final g = gradle.readAsStringSync();
    expect(g, contains('ndkVersion = flutter.ndkVersion'));
    expect(g, contains('versionCode = flutter.versionCode'));
    expect(g, contains('versionName = flutter.versionName'));

    final scriptFile = File('scripts/package_android_release.ps1');
    expect(scriptFile.existsSync(), isTrue);
    final scriptBytes = scriptFile.readAsBytesSync();
    final hasBom = scriptBytes.length >= 3 &&
        scriptBytes[0] == 0xEF &&
        scriptBytes[1] == 0xBB &&
        scriptBytes[2] == 0xBF;
    expect(
      hasBom || !scriptBytes.any((b) => b > 0x7F),
      isTrue,
      reason: 'package_android_release.ps1 Windows PowerShell 5.1 için UTF-8 BOM veya ASCII olmalı',
    );

    final script = scriptFile.readAsStringSync();
    expect(script, isNot(contains(r'[string]$Version = "1.0.0"')));
    expect(script, contains('pubspec.yaml'));
    expect(script, contains('--build-name=\$buildName'));
    expect(script, contains('--build-number=\$buildNumber'));
    expect(script, contains(r'market_mms_v$buildName-b$buildNumber$ext'));

    if (Platform.isWindows) {
      final parseRes = Process.runSync('powershell.exe', [
        '-NoProfile',
        '-Command',
        '[System.Management.Automation.Language.Parser]::ParseFile("${scriptFile.absolute.path}", [ref]\$null, [ref]\$null)',
      ]);
      expect(parseRes.exitCode, 0, reason: 'PowerShell AST ayrıştırması geçmeli: ${parseRes.stderr}');

      final mismatchRes = Process.runSync('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        scriptFile.absolute.path,
        '-Version',
        '9.9.9',
        '-SkipFlutterBuild',
      ]);
      expect(
        mismatchRes.exitCode,
        isNot(0),
        reason: 'pubspec.yaml ile uyuşmayan -Version fail-closed reddedilmeli',
      );
    }
  });

  test('Phase 1.1: PAT-16 Android JobScheduler JOB_ID (70201) Kotlin kodu ve fiziksel test planında tutarlıdır', () {
    final jobService = File(
      'android/app/src/main/kotlin/com/marketmms/market_pos/MmsBackgroundBackupJobService.kt',
    ).readAsStringSync();
    expect(jobService, contains('const val JOB_ID = 70201'));

    final patPlan = File('PHYSICAL_ACCEPTANCE_TEST_PLAN.md').readAsStringSync();
    expect(
      patPlan,
      contains('adb shell cmd jobscheduler run -f com.marketmms.market_pos 70201'),
    );
    expect(patPlan, isNot(contains('202611')));
  });

  test('Pilot dağıtım betikleri Android/Windows Drive OAuth define ve sqlite3.dll paketlemesini destekler', () {
    final androidPkgFile = File('scripts/package_android_release.ps1');
    final winPkgFile = File('scripts/package_windows_release.ps1');
    expect(androidPkgFile.existsSync(), isTrue);
    expect(winPkgFile.existsSync(), isTrue);

    final androidScript = androidPkgFile.readAsStringSync();
    expect(androidScript, contains('GoogleDriveWebClientId'));
    expect(androidScript, contains('MMS_GDRIVE_WEB_CLIENT_ID='));

    final winScript = winPkgFile.readAsStringSync();
    expect(winScript, contains('GoogleDriveClientId'));
    expect(winScript, contains('MMS_GDRIVE_CLIENT_ID='));
    expect(winScript, contains('sqlite3.dll'));
    expect(winScript, contains('uninstall_mms_service.ps1'));
    expect(winScript, contains('MarketMMSService.exe'));
    expect(winScript, contains('hub_config.example.json'));

    for (final scriptFile in [androidPkgFile, winPkgFile]) {
      final bytes = scriptFile.readAsBytesSync();
      final hasBom = bytes.length >= 3 &&
          bytes[0] == 0xEF &&
          bytes[1] == 0xBB &&
          bytes[2] == 0xBF;
      expect(
        hasBom || !bytes.any((b) => b > 0x7F),
        isTrue,
        reason: '${scriptFile.path} PowerShell 5.1 için UTF-8 BOM veya ASCII olmalı',
      );
      if (Platform.isWindows) {
        final parseRes = Process.runSync('powershell.exe', [
          '-NoProfile',
          '-Command',
          '[System.Management.Automation.Language.Parser]::ParseFile("${scriptFile.absolute.path}", [ref]\$null, [ref]\$null)',
        ]);
        expect(parseRes.exitCode, 0, reason: '${scriptFile.path} AST hatası: ${parseRes.stderr}');
      }
    }
  });
}
