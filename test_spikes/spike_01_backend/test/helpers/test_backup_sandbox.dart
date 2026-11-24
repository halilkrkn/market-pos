import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Stage 4 (`AUD-LOW-02`): Yalnızca `Directory.systemTemp` altında işaretli ve
/// test ömrüne bağlı izole geçici yedekleme dizini sağlar.
///
/// Gerçek proje dizinlerine (`test_spikes/spike_01_backend/backups`),
/// `%ProgramData%\MarketMMS` veya `%LOCALAPPDATA%\MarketMMS` yollarına erişimi
/// ve işaretlenmemiş herhangi bir dizinin özyinelemeli silinmesini engeller.
class TestBackupSandbox {
  static const String markerFileName = '.mms_test_only_marker';

  final Directory directory;

  String get path => directory.path;

  const TestBackupSandbox._(this.directory);

  /// `package:test` `addTearDown` ile test başarılı olsa da hata fırlatsa da
  /// yalnızca bu testin kendi işaretli dizinini temizleyen sandbox oluşturur.
  factory TestBackupSandbox.create({String prefix = 'mms_test_bak_'}) {
    final sandbox = TestBackupSandbox.createManual(prefix: prefix);
    addTearDown(sandbox.dispose);
    return sandbox;
  }

  /// Manuel temizlik (`try / finally` ile) gerektiren izolasyon testleri içindir.
  factory TestBackupSandbox.createManual({String prefix = 'mms_test_bak_'}) {
    final dir = Directory.systemTemp.createTempSync(prefix);
    File(p.join(dir.path, markerFileName)).writeAsStringSync(
      'TEST_ONLY_BACKUP_SANDBOX\ncreated_at_utc=${DateTime.now().toUtc().toIso8601String()}\n',
      flush: true,
    );
    return TestBackupSandbox._(dir);
  }

  static String _normalizeForComparison(String rawPath) {
    final normalized = p.normalize(rawPath);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  /// [dir] özyinelemeli silinmeden veya test yedek hedefi olarak kullanılmadan önce
  /// yalnızca `Directory.systemTemp` altındaki işaretli bir test sandbox'ı olduğunu doğrular.
  static void assertSafeTestBackupDirectory(Directory dir) {
    final rawNorm = _normalizeForComparison(dir.absolute.path);
    final sysTempNorm = _normalizeForComparison(
      Directory.systemTemp.resolveSymbolicLinksSync(),
    );

    if (rawNorm.contains(r'spike_01_backend\backups') ||
        rawNorm.contains('spike_01_backend/backups') ||
        rawNorm.contains(r'\marketmms\') ||
        rawNorm.contains('/marketmms/')) {
      throw StateError(
        'Test yedekleme dizini gerçek veya paylaşılan sistem/proje klasörünü hedefleyemez: ${dir.path}',
      );
    }

    if (!dir.existsSync()) {
      throw StateError(
        'Test backup sandbox dizini mevcut değil (silme/doğrulama reddedildi): ${dir.path}',
      );
    }

    final resolvedNorm = _normalizeForComparison(dir.resolveSymbolicLinksSync());
    if (resolvedNorm == sysTempNorm || !p.isWithin(sysTempNorm, resolvedNorm)) {
      throw StateError(
        'Test backup sandbox dizini sistem Temp dışında olamaz: $resolvedNorm',
      );
    }

    final marker = File(p.join(dir.path, markerFileName));
    if (!marker.existsSync()) {
      throw StateError(
        'İşaretlenmemiş geçici dizin ($markerFileName eksik) silinemez: ${dir.path}',
      );
    }
  }

  /// Yalnızca [assertSafeTestBackupDirectory] kontrolünden geçen bu sandbox'ı temizler.
  void dispose() {
    if (!directory.existsSync()) {
      return;
    }
    assertSafeTestBackupDirectory(directory);
    directory.deleteSync(recursive: true);
  }
}
