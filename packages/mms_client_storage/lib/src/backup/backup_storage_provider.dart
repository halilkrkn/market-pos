import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;

import 'backup_crypto.dart';
import 'backup_manifest.dart';

class BackupPackageInfo {
  final BackupManifest manifest;
  final File file;
  final int fileSizeBytes;
  final DateTime createdAt;

  const BackupPackageInfo({
    required this.manifest,
    required this.file,
    required this.fileSizeBytes,
    required this.createdAt,
  });

  String get backupId => manifest.backupId;
  DatabaseType get databaseType => manifest.databaseType;
  String get deviceId => manifest.deviceId;
  String get tenantId => manifest.tenantId;
  DateTime get timestamp => manifest.timestamp;
}

/// S5A-4: Harici yedekleme sağlayıcıları (Local Disk, Google Drive vb.) için soyut arayüz.
/// Google Drive entegrasyonu bu arayüz üzerinden sonradan eklenebilir.
abstract class BackupStorageProvider {
  /// Şifrelenmiş yedek paketini ve manifestini hedefe yazar.
  /// Hedefte aynı dosya adı varsa ASLA üzerine yazmaz.
  Future<void> saveBackup({
    required Uint8List packageBytes,
    required BackupManifest manifest,
  });

  /// Saklanan yedek paketlerini listeler ve filtrelere göre döner.
  Future<List<BackupPackageInfo>> listBackups({
    String? tenantId,
    String? deviceId,
    DatabaseType? databaseType,
  });

  /// Belirtilen backupId'ye ait dosya referansını döner.
  Future<File> getBackupFile(String backupId);

  /// Belirtilen backupId'ye ait paketi siler (Saklama politikası temizliği vb.)
  Future<void> deleteBackup(String backupId);

  /// Belirtilen backupId'nin var olup olmadığını kontrol eder.
  Future<bool> backupExists(String backupId);
}

/// Yerel disk, harici USB veya ağ paylaşımı için dosya sistemi tabanlı sağlayıcı
class LocalStorageProvider implements BackupStorageProvider {
  final Directory rootDir;

  LocalStorageProvider(this.rootDir) {
    if (!rootDir.existsSync()) {
      rootDir.createSync(recursive: true);
    }
  }

  /// Güvenli, deterministik ve çakışmasız dosya adı üretir
  /// Format: backup_{databaseType}_{deviceId}_{YYYYMMDD_HHMMSS}_{backupId}.mmsbak
  String generateFileName(BackupManifest manifest) {
    final dateStr = manifest.timestamp.toUtc().toIso8601String().replaceAll(':', '').replaceAll('-', '').replaceAll('.', '_');
    return 'backup_${manifest.databaseType.value}_${manifest.deviceId}_${dateStr}_${manifest.backupId}.mmsbak';
  }

  @override
  Future<void> saveBackup({
    required Uint8List packageBytes,
    required BackupManifest manifest,
  }) async {
    final fileName = generateFileName(manifest);
    final finalFile = File(p.join(rootDir.path, fileName));

    if (await finalFile.exists()) {
      throw StateError('Yedek dosyası zaten mevcut; mevcut yedeğin üzerine yazılamaz: ${finalFile.path}');
    }

    // Yarım kalan yedeklerin geçerli yedek gibi görünmesini engellemek için .tmp uzantısıyla başla
    final tmpFile = File(p.join(rootDir.path, '$fileName.tmp'));
    try {
      await tmpFile.writeAsBytes(packageBytes, flush: true);

      // Yazılan geçici dosyanın geçerliliğini doğrula
      final writtenBytes = await tmpFile.readAsBytes();
      final extractedManifest = BackupCryptoService.extractManifestWithoutDecryption(writtenBytes);
      if (extractedManifest.backupId != manifest.backupId) {
        throw StateError('Geçici yedek dosyası doğrulanamadı.');
      }

      // Atomik isim değiştirme ile geçerli yedek konumuna al
      await tmpFile.rename(finalFile.path);
    } catch (e) {
      if (await tmpFile.exists()) {
        try {
          await tmpFile.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  @override
  Future<List<BackupPackageInfo>> listBackups({
    String? tenantId,
    String? deviceId,
    DatabaseType? databaseType,
  }) async {
    if (!await rootDir.exists()) return [];

    final result = <BackupPackageInfo>[];
    final files = rootDir.listSync().whereType<File>();

    for (final file in files) {
      if (!file.path.endsWith('.mmsbak')) {
        continue; // .tmp veya diğer dosyaları asla listeleme
      }

      try {
        final bytes = await file.readAsBytes();
        final manifest = BackupCryptoService.extractManifestWithoutDecryption(bytes);

        if (tenantId != null && manifest.tenantId != tenantId) continue;
        if (deviceId != null && manifest.deviceId != deviceId) continue;
        if (databaseType != null && manifest.databaseType != databaseType) continue;

        final stat = file.statSync();
        result.add(BackupPackageInfo(
          manifest: manifest,
          file: file,
          fileSizeBytes: stat.size,
          createdAt: stat.changed,
        ));
      } catch (e) {
        // Bozuk veya uyumsuz dosyalar listeye dahil edilmez
        continue;
      }
    }

    // Kronolojik sıralama: En yeniden en eskiye
    result.sort((a, b) => b.manifest.timestamp.compareTo(a.manifest.timestamp));
    return result;
  }

  @override
  Future<File> getBackupFile(String backupId) async {
    // 1. Önce dosya adı kuralı üzerinden ara (Manifest bozuk olsa bile dosyayı bütünlük kontrolüne teslim eder)
    if (rootDir.existsSync()) {
      final files = rootDir.listSync().whereType<File>();
      for (final file in files) {
        if (file.path.endsWith('.mmsbak') && file.path.contains(backupId)) {
          return file;
        }
      }
    }

    // 2. Fallback: Parsed manifest listesini tarayarak ara
    final all = await listBackups();
    for (final b in all) {
      if (b.backupId == backupId) {
        return b.file;
      }
    }
    throw StateError('Yedek paketi bulunamadı: $backupId');
  }

  @override
  Future<bool> backupExists(String backupId) async {
    final all = await listBackups();
    return all.any((b) => b.backupId == backupId);
  }

  @override
  Future<void> deleteBackup(String backupId) async {
    final file = await getBackupFile(backupId);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

