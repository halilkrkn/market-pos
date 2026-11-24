import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'backup_manifest.dart';
import 'backup_storage_provider.dart';
import 'database_backup_engine.dart';
import 'mmsbak_v2_crypto.dart';
import 'scheduled_backup.dart';

/// Hedef dosyaya bayt yazan fonksiyon (testlerde disk dolu / aygıt çıkarıldı enjeksiyonu).
typedef BackupBytesWriter = Future<void> Function(File target, Uint8List bytes);

/// Faz 7D — Şifreli `.mmsbak` paketlerinin USB / ağ klasörüne güvenli aktarımı.
///
/// - Dışa aktarım: `.tmp` + flush + geri okuma SHA-256 doğrulaması + atomik rename.
///   Disk dolu veya aygıt çıkarılırsa yarım dosya bırakılmaz; var olan dosyanın
///   üzerine yazılmaz.
/// - İçe aktarım: parola gerektirmeyen yapısal bütünlük (başlık + manifest +
///   beklenen uzunluk) ile tür/cihaz/tenant/şube kontrolü. HMAC ve SQLite
///   bütünlüğü restore sırasında, canlı DB'ye dokunulmadan doğrulanır.
class BackupFileTransfer {
  const BackupFileTransfer._();

  static Future<void> _defaultWriter(File target, Uint8List bytes) =>
      target.writeAsBytes(bytes, flush: true);

  static Future<File> exportToDirectory({
    required File source,
    required Directory targetDir,
    BackupBytesWriter? writer,
  }) async {
    if (!await targetDir.exists()) {
      throw BackupException(
        'ERR_TARGET_UNAVAILABLE',
        'Hedef klasör bulunamadı (USB takılı değil veya yol yanlış): ${targetDir.path}',
      );
    }
    final bytes = await source.readAsBytes();
    final finalFile = File(p.join(targetDir.path, p.basename(source.path)));
    if (await finalFile.exists()) {
      throw BackupException('ERR_TARGET_EXISTS', 'Hedefte aynı yedek zaten var; üzerine yazılmadı: ${finalFile.path}');
    }

    final tmp = File('${finalFile.path}.tmp');
    try {
      await (writer ?? _defaultWriter)(tmp, bytes);
      final written = await tmp.readAsBytes();
      if (written.length != bytes.length || sha256.convert(written) != sha256.convert(bytes)) {
        throw const BackupException(
          'ERR_EXPORT_VERIFY_FAILED',
          'Hedefe yazılan yedek doğrulanamadı (içerik kaynakla uyuşmuyor). Aygıtı kontrol edip tekrar deneyin.',
        );
      }
      await tmp.rename(finalFile.path);
      return finalFile;
    } on FileSystemException catch (e) {
      await _deleteQuietly(tmp);
      final code = BackupFailureClassifier.codeFor(e);
      throw BackupException(code, BackupFailureClassifier.messageFor(code, e));
    } catch (_) {
      await _deleteQuietly(tmp);
      rethrow;
    }
  }

  /// Paketin parola olmadan doğrulanabilen yapısını kontrol eder (`MMSBAK01` / `MMSBAK02`) ve manifesti döner.
  static BackupManifest verifyPackageStructure(Uint8List bytes) {
    return MmsbakV2Crypto.verifyBytesStructure(bytes).manifest;
  }

  static Future<BackupPackageInfo> importFromFile({
    required File external,
    required Directory backupRoot,
    required DatabaseType expectedType,
    required String expectedDeviceId,
    required String expectedTenantId,
    String? expectedStoreId,
  }) async {
    final Uint8List bytes;
    try {
      bytes = await external.readAsBytes();
    } on FileSystemException catch (e) {
      final code = BackupFailureClassifier.codeFor(e);
      throw BackupException(code, BackupFailureClassifier.messageFor(code, e));
    }
    final manifest = verifyPackageStructure(bytes);

    if (manifest.databaseType != expectedType) {
      throw BackupException('ERR_DATABASE_TYPE_MISMATCH', 'Yedek türü bu cihaza uygun değil: ${manifest.databaseType.value}');
    }
    if (manifest.deviceId != expectedDeviceId) {
      throw BackupException('ERR_DEVICE_ID_MISMATCH', 'Bu yedek başka bir cihaza ait: ${manifest.deviceId}');
    }
    if (manifest.tenantId != expectedTenantId) {
      throw BackupException('ERR_TENANT_ID_MISMATCH', 'Bu yedek başka bir işletmeye ait.');
    }
    if (expectedStoreId != null && manifest.storeId != expectedStoreId) {
      throw BackupException('ERR_STORE_ID_MISMATCH', 'Bu yedek başka bir şubeye ait: ${manifest.storeId}');
    }

    final storage = LocalStorageProvider(backupRoot);
    if (await storage.backupExists(manifest.backupId)) {
      return (await storage.listBackups()).firstWhere((b) => b.backupId == manifest.backupId);
    }
    try {
      await storage.saveBackup(packageBytes: bytes, manifest: manifest);
    } on FileSystemException catch (e) {
      final code = BackupFailureClassifier.codeFor(e);
      throw BackupException(code, BackupFailureClassifier.messageFor(code, e));
    }
    final file = await storage.getBackupFile(manifest.backupId);
    return BackupPackageInfo(
      manifest: manifest,
      file: file,
      fileSizeBytes: bytes.length,
      createdAt: DateTime.now().toUtc(),
    );
  }

  static Future<void> _deleteQuietly(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } on FileSystemException catch (e) {
      stderr.writeln('[BackupFileTransfer] Geçici dosya silinemedi (${p.basename(f.path)}): ${e.message}');
    }
  }
}
