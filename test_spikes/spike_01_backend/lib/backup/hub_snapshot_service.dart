import 'dart:convert';
import 'dart:io';

import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../db/database.dart';
import '../db/write_queue.dart';

class HubSnapshotStageResult {
  final String backupId;
  final File snapshotFile;
  final File ownerSidecarFile;
  final int unencryptedSizeBytes;
  final String snapshotSha256;

  const HubSnapshotStageResult({
    required this.backupId,
    required this.snapshotFile,
    required this.ownerSidecarFile,
    required this.unencryptedSizeBytes,
    required this.snapshotSha256,
  });
}

class HubEncryptedBackupResult {
  final String backupId;
  final File backupFile;
  final BackupManifest manifest;
  final int encryptedSizeBytes;
  final int unencryptedSizeBytes;

  const HubEncryptedBackupResult({
    required this.backupId,
    required this.backupFile,
    required this.manifest,
    required this.encryptedSizeBytes,
    required this.unencryptedSizeBytes,
  });
}

typedef HubEncryptHook = Future<BackupManifest> Function({
  required File inputFile,
  required File outputFile,
  required String password,
  required BackupManifest manifest,
  int kdfIterations,
});

/// Faz B-1 (`ADR-023`): Hub merkezi SQLite yedeği için 2 aşamalı snapshot & şifreleme motoru.
///
/// - **Aşama 1 (`captureConsistentSnapshot`):** `WriteQueue` üzerinden yalnızca hızlı `VACUUM INTO`
///   çalıştırır; ardından kuyruk dışında FFI `PRAGMA integrity_check` doğrular.
/// - **Aşama 2 (`encryptSnapshotToPackage`):** `WriteQueue` tamamen serbestken
///   `<backupDir>/.tmp_snapshots` altındaki doğrulanmış snapshot'ı akışlı `MMSBAK02`
///   ile şifreler; yalnız `.owner.json` sahipliği eşleşen geçici dosyayı siler.
class HubSnapshotService {
  final SpikeDatabase Function() readDb;
  final WriteQueue writeQueue;
  final File liveDbFile;
  final Directory backupDir;
  final String hubId;
  final String tenantId;
  final String storeId;
  final String appVersion;
  final DiskSpaceChecker diskSpaceChecker;
  final int kdfIterations;
  final HubEncryptHook? encryptHook;

  HubSnapshotService({
    required this.readDb,
    required this.writeQueue,
    required this.liveDbFile,
    required this.backupDir,
    required this.hubId,
    required this.tenantId,
    required this.storeId,
    required this.appVersion,
    this.diskSpaceChecker = const DiskSpaceChecker(),
    this.kdfIterations = MmsbakV2Crypto.defaultPbkdf2Iterations,
    this.encryptHook,
  });

  Directory get tmpSnapshotsDir =>
      Directory(p.join(backupDir.path, '.tmp_snapshots'));

  File snapshotFileForBackup(String backupId) =>
      File(p.join(tmpSnapshotsDir.path, 'snap_$backupId.db'));

  File ownerSidecarForSnapshot(File snapFile) =>
      File('${snapFile.path}.owner.json');

  File encryptedFileForBackup(String backupId) =>
      File(p.join(backupDir.path, 'hub_backup_$backupId.mmsbak'));

  Future<void> _ensureProtectedDirs() async {
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    if (await FileSystemEntity.isLink(backupDir.path)) {
      throw BackupException(
        'ERR_UNSAFE_BACKUP_DIR',
        'Yedekleme klasörü sembolik bağ / reparse point olamaz: ${backupDir.path}',
      );
    }
    final tmpDir = tmpSnapshotsDir;
    if (!await tmpDir.exists()) {
      await tmpDir.create(recursive: true);
    }
    if (await FileSystemEntity.isLink(tmpDir.path)) {
      throw BackupException(
        'ERR_UNSAFE_SNAPSHOT_DIR',
        'Geçici snapshot klasörü sembolik bağ olamaz: ${tmpDir.path}',
      );
    }
  }

  /// Aşama 1: Disk alanı kontrolü + `WriteQueue` içinde `VACUUM INTO` + dışında `PRAGMA integrity_check`.
  Future<HubSnapshotStageResult> captureConsistentSnapshot({
    required String backupId,
    DateTime? nowUtc,
  }) async {
    await _ensureProtectedDirs();

    final space = await diskSpaceChecker.checkForDatabase(
      databaseFile: liveDbFile,
      targetDir: tmpSnapshotsDir,
    );
    if (!space.ok) {
      throw BackupException(
        'ERR_INSUFFICIENT_DISK_SPACE',
        space.reason ?? 'Yedekleme için yeterli disk alanı yok.',
      );
    }

    final snapFile = snapshotFileForBackup(backupId);
    final ownerFile = ownerSidecarForSnapshot(snapFile);

    // Aynı backupId için önceki yarım owned snapshot varsa güvenle temizle
    if (await snapFile.exists() || await ownerFile.exists()) {
      await deleteOwnedSnapshot(backupId: backupId, snapshotFile: snapFile);
    }
    if (await snapFile.exists()) {
      throw BackupException(
        'ERR_UNOWNED_SNAPSHOT_EXISTS',
        'Sahipliği doğrulanamayan snapshot dosyası üzerine yazılmadı: ${snapFile.path}',
      );
    }

    final createdAt = (nowUtc ?? DateTime.now()).toUtc();
    await ownerFile.writeAsString(
      jsonEncode({
        'backup_id': backupId,
        'pid': pid,
        'created_at_utc': createdAt.toIso8601String(),
        'stage': 'SNAPSHOT_IN_PROGRESS',
      }),
      flush: true,
    );

    final escapedPath = snapFile.path.replaceAll("'", "''");
    try {
      await writeQueue.enqueue(() async {
        await readDb().customStatement("VACUUM INTO '$escapedPath';");
      });
    } catch (e) {
      await deleteOwnedSnapshot(backupId: backupId, snapshotFile: snapFile);
      rethrow;
    }

    if (!await snapFile.exists() || (await snapFile.length()) == 0) {
      await deleteOwnedSnapshot(backupId: backupId, snapshotFile: snapFile);
      throw const BackupException(
        'ERR_EMPTY_SNAPSHOT',
        'VACUUM INTO sonrası snapshot dosyası boş veya eksik.',
      );
    }

    verifySnapshotIntegrityOrThrow(snapFile);

    final unencSize = await snapFile.length();
    final shaHex = await MmsbakV2Crypto.computeFileSha256(snapFile);
    await ownerFile.writeAsString(
      jsonEncode({
        'backup_id': backupId,
        'pid': pid,
        'created_at_utc': createdAt.toIso8601String(),
        'stage': 'SNAPSHOT_READY',
        'sha256': shaHex,
      }),
      flush: true,
    );

    return HubSnapshotStageResult(
      backupId: backupId,
      snapshotFile: snapFile,
      ownerSidecarFile: ownerFile,
      unencryptedSizeBytes: unencSize,
      snapshotSha256: shaHex,
    );
  }

  /// Snapshot dosyasının gerçek FFI SQLite `PRAGMA integrity_check` doğrulamasını yapar.
  static void verifySnapshotIntegrityOrThrow(File snapFile) {
    final checkDb = sqlite3.open(snapFile.path, mode: OpenMode.readOnly);
    try {
      final res = checkDb.select('PRAGMA integrity_check;');
      final status = res.isEmpty ? '' : res.first.columnAt(0)?.toString().toLowerCase();
      if (status != 'ok') {
        throw BackupException(
          'ERR_INTEGRITY_CHECK_FAILED',
          'Hub snapshot SQLite integrity_check başarısız: $status',
        );
      }
    } finally {
      checkDb.close();
    }
  }

  /// Aşama 2: `WriteQueue` dışında doğrulanmış snapshot'ı akışlı `MMSBAK02` paketine şifreler.
  Future<HubEncryptedBackupResult> encryptSnapshotToPackage({
    required String backupId,
    required File snapshotFile,
    required String recoveryPassword,
    required BackupManifest baseManifest,
    bool cleanupSnapshot = true,
  }) async {
    await _ensureProtectedDirs();
    final targetFile = encryptedFileForBackup(backupId);

    final hook = encryptHook ??
        ({
          required File inputFile,
          required File outputFile,
          required String password,
          required BackupManifest manifest,
          int kdfIterations = MmsbakV2Crypto.defaultPbkdf2Iterations,
        }) =>
            MmsbakV2Crypto.encryptFile(
              inputFile: inputFile,
              outputFile: outputFile,
              password: password,
              manifest: manifest,
              kdfIterations: kdfIterations,
            );

    final finalizedManifest = await hook(
      inputFile: snapshotFile,
      outputFile: targetFile,
      password: recoveryPassword,
      manifest: baseManifest,
      kdfIterations: kdfIterations,
    );

    final encSize = await targetFile.length();
    if (cleanupSnapshot) {
      await deleteOwnedSnapshot(backupId: backupId, snapshotFile: snapshotFile);
    }

    return HubEncryptedBackupResult(
      backupId: backupId,
      backupFile: targetFile,
      manifest: finalizedManifest,
      encryptedSizeBytes: encSize,
      unencryptedSizeBytes: finalizedManifest.unencryptedSizeBytes,
    );
  }

  /// Tam 2 aşamalı yedek üretimi (Aşama 1 `WriteQueue`, Aşama 2 `WriteQueue` dışında).
  Future<HubEncryptedBackupResult> createEncryptedBackup({
    required String backupId,
    required String recoveryPassword,
    required int schemaVersion,
    bool isMonthlyArchive = false,
    DateTime? timestampUtc,
  }) async {
    MmsbakV2Crypto.validateRecoveryPassword(recoveryPassword);
    final ts = (timestampUtc ?? DateTime.now()).toUtc();
    final stage1 = await captureConsistentSnapshot(
      backupId: backupId,
      nowUtc: ts,
    );
    final baseManifest = BackupManifest(
      backupId: backupId,
      deviceId: hubId,
      tenantId: tenantId,
      storeId: storeId,
      databaseType: DatabaseType.centralMaster,
      schemaVersion: schemaVersion,
      appVersion: appVersion,
      timestamp: ts,
      checksum: stage1.snapshotSha256,
      unencryptedSizeBytes: stage1.unencryptedSizeBytes,
      encryptedSizeBytes: 0,
      encryptionAlgorithm: MmsbakV2Crypto.algorithmId,
      kdfIterations: kdfIterations,
      isMonthlyArchive: isMonthlyArchive,
    );
    return encryptSnapshotToPackage(
      backupId: backupId,
      snapshotFile: stage1.snapshotFile,
      recoveryPassword: recoveryPassword,
      baseManifest: baseManifest,
      cleanupSnapshot: true,
    );
  }

  /// Yalnızca `.owner.json` sahipliği [backupId] ile doğrulanan snapshot dosyasını siler.
  Future<bool> deleteOwnedSnapshot({
    required String backupId,
    required File snapshotFile,
  }) async {
    final ownerFile = ownerSidecarForSnapshot(snapshotFile);
    if (!await ownerFile.exists()) {
      return false;
    }
    try {
      final decoded = jsonDecode(await ownerFile.readAsString());
      if (decoded is! Map || decoded['backup_id'] != backupId) {
        return false;
      }
    } catch (_) {
      return false;
    }

    if (await snapshotFile.exists()) {
      await snapshotFile.delete();
    }
    if (await ownerFile.exists()) {
      await ownerFile.delete();
    }
    return true;
  }
}
