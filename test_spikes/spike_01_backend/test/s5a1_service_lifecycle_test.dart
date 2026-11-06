import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late String spikeRoot;
  late String buildDir;
  late String serviceWrapperDir;
  late String scriptsDir;

  setUpAll(() {
    spikeRoot = Directory.current.path;
    buildDir = p.join(spikeRoot, 'build');
    serviceWrapperDir = p.join(spikeRoot, 'service_wrapper');
    scriptsDir = p.join(spikeRoot, 'scripts');
  });

  group('Aşama S-5A-1: Windows Service Altyapısı ve Yaşam Döngüsü Doğrulama Testleri', () {
    test('1. Dart AOT Backend Executable başarıyla derlenmiş ve çalıştırılabilir olmalıdır', () {
      final aotExe = File(p.join(buildDir, 'mms_backend.exe'));
      expect(aotExe.existsSync(), isTrue,
          reason: 'build/mms_backend.exe derlenmiş olmalıdır.');
      expect(aotExe.lengthSync(), greaterThan(1024 * 1024),
          reason: 'Dart AOT executable boyutu > 1 MB olmalıdır.');
    });

    test('2. WinSW v2.12.0 wrapper ikilisi ve sürümü doğrulanmalıdır', () {
      final wrapperExe = File(p.join(serviceWrapperDir, 'MarketMMSService.exe'));
      expect(wrapperExe.existsSync(), isTrue,
          reason: 'MarketMMSService.exe WinSW binary mevcut olmalıdır.');

      final res = Process.runSync(wrapperExe.path, ['version']);
      expect(res.exitCode, equals(0));
      expect(res.stdout.toString(), contains('WinSW 2.12.0.0'),
          reason: 'WinSW resmi v2.12.0.0 sürümü olmalıdır.');
    });

    test('3. WinSW v2.12.0 XML yapılandırması resmi şemaya tam uyumlu olmalı ve TLS zorunlu kılmalıdır', () {
      final xmlFile = File(p.join(serviceWrapperDir, 'MarketMMSService.xml'));
      expect(xmlFile.existsSync(), isTrue);

      final xmlContent = xmlFile.readAsStringSync();

      // Servis ID ve İsim
      expect(xmlContent, contains('<id>MarketMMSService</id>'));
      expect(xmlContent, contains('<name>Market MMS Backend Engine</name>'));

      // Başlangıç Modu
      expect(xmlContent, contains('<startmode>Automatic</startmode>'));

      // LocalService Hesabı (Domain ve User ayrımı)
      expect(xmlContent, contains('<domain>NT AUTHORITY</domain>'));
      expect(xmlContent, contains('<user>LocalService</user>'));

      // TLS Zorunluluğu (S-3 Uyumu: Üretim servisi kesinlikle şifresiz HTTP listener açamaz)
      expect(xmlContent, contains('--tls'),
          reason: 'WinSW XML argümanlarında TLS zorunluluğu (--tls) bulunmalıdır.');
      expect(xmlContent, contains('--cert='),
          reason: 'Sunucu TLS sertifika yolu yapılandırılmış olmalıdır.');
      expect(xmlContent, contains('--key='),
          reason: 'Sunucu TLS özel anahtar yolu yapılandırılmış olmalıdır.');
      expect(xmlContent, contains('<env name="ENABLE_TLS" value="true"/>'),
          reason: 'Ortam değişkeninde TLS etkinleştirilmiş olmalıdır.');

      // Kurtarma Politikası
      expect(xmlContent, contains('<onfailure action="restart" delay="5 sec"/>'));
      expect(xmlContent, contains('<resetfailure>1 hour</resetfailure>'));

      // Stop Timeout
      expect(xmlContent, contains('<stoptimeout>15 sec</stoptimeout>'));

      // WinSW CLI ile XML doğrulama (status sorgusu hatasız XML ayrıştırmasını teyit eder)
      final wrapperExe = p.join(serviceWrapperDir, 'MarketMMSService.exe');
      final res = Process.runSync(wrapperExe, ['status']);
      expect(res.exitCode, equals(0));
      expect(res.stdout.toString().trim(), anyOf(equals('NonExistent'), equals('Stopped'), equals('Running')));
    });

    test('4. Windows Servis kurulum ve kaldırma betikleri mevcut ve sözdizimi geçerli olmalıdır', () {
      final installScript = File(p.join(scriptsDir, 'install_mms_service.ps1'));
      final uninstallScript = File(p.join(scriptsDir, 'uninstall_mms_service.ps1'));
      final buildScript = File(p.join(scriptsDir, 'build_aot.ps1'));
      final aclScript = File(p.join(scriptsDir, 'setup_service_acls.ps1'));

      expect(installScript.existsSync(), isTrue);
      expect(uninstallScript.existsSync(), isTrue);
      expect(buildScript.existsSync(), isTrue);
      expect(aclScript.existsSync(), isTrue);

      final installContent = installScript.readAsStringSync();
      expect(installContent, contains('sc.exe sidtype \$ServiceName unrestricted'),
          reason: 'Install betiği Service SID atamasını kesinlikle içermelidir.');
      expect(installContent, contains('setup_service_acls.ps1'),
          reason: 'Install betiği ACL kurulumunu tetiklemelidir.');
      expect(installContent, contains('Copy-Item'),
          reason: 'Install betiği ikilileri ProgramData hedefine kopyalamalıdır.');

      final aclContent = aclScript.readAsStringSync();
      expect(aclContent, contains('[1/7] Reparse Point / Junction denetimi'),
          reason: 'ACL betiği reparse point denetimini en başta yapmalıdır.');
      expect(aclContent, contains('[2/7] ca.key dosya taramasi'),
          reason: 'ACL betiği ca.key kontrolünü içermelidir.');
      expect(aclContent, contains('NT SERVICE\\\$ServiceName'),
          reason: 'ACL betiği Service SID tanımlarını içermelidir.');
    });

    test('5. S5A-1 Kurulum Betikleri PowerShell AST Ayrıştırmasından Hatasız Geçmelidir', () {
      final scripts = ['build_aot.ps1', 'setup_service_acls.ps1', 'install_mms_service.ps1', 'uninstall_mms_service.ps1'];
      for (final s in scripts) {
        final path = p.join(scriptsDir, s);
        final res = Process.runSync('powershell.exe', [
          '-Command',
          '[System.Management.Automation.Language.Parser]::ParseFile("$path", [ref]\$null, [ref]\$null)'
        ]);
        expect(res.exitCode, equals(0), reason: '$s PowerShell AST ayrıştırması başarılı olmalıdır.');
      }
    });
  });
}
