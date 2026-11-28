import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw_sqlite;

import '../db/database.dart';
import '../security/token_manager.dart';

class HubRestoreResult {
  final String backupId;
  final BackupManifest manifest;
  final String? safetyBackupPath;
  final bool safetyBackupEncrypted;
  final String restoreEpoch;
  final int invalidatedActiveDeviceCount;
  final int preservedRevokedDeviceCount;
  final DateTime restoredAtUtc;

  const HubRestoreResult({
    required this.backupId,
    required this.manifest,
    this.safetyBackupPath,
    required this.safetyBackupEncrypted,
    required this.restoreEpoch,
    required this.invalidatedActiveDeviceCount,
    required this.preservedRevokedDeviceCount,
    required this.restoredAtUtc,
  });

  Map<String, dynamic> toJson({bool maskPaths = false}) => {
        'status': 'RESTORED',
        'backup_id': backupId,
        'manifest': manifest.toJson(),
        'safety_backup_path': maskPaths && safetyBackupPath != null
            ? p.basename(safetyBackupPath!)
            : safetyBackupPath,
        'safety_backup_encrypted': safetyBackupEncrypted,
        'restore_epoch': restoreEpoch,
        'invalidated_active_device_count': invalidatedActiveDeviceCount,
        'preserved_revoked_device_count': preservedRevokedDeviceCount,
        'restored_at_utc': restoredAtUtc.toUtc().toIso8601String(),
      };
}

/// Faz B-4 (`OV-03`, `OV-05`, `ADR-023`): Taşınabilir `.mmsbak` (`MMSBAK02` + `MMSBAK01`)
/// paketinden yeni PC / Master Hub felaket kurtarma ve kontrollü token geçersizleştirme motoru.
class HubRestoreService {
  static final Random _secureRandom = Random.secure();

  const HubRestoreService._();

  static String generateRestoreEpoch({DateTime? nowUtc}) {
    final ts = (nowUtc ?? DateTime.now()).toUtc().microsecondsSinceEpoch;
    final nonce = List<int>.generate(6, (_) => _secureRandom.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'epoch_${ts}_$nonce';
  }

  static Future<HubRestoreResult> restoreFromEncryptedPackage({
    required File packageFile,
    required String recoveryPassword,
    required File liveDbFile,
    required Directory backupDir,
    required BackupOperationLock lock,
    required Future<void> Function() pauseAndCloseLiveDb,
    required Future<SpikeDatabase> Function(File liveDbFile) reopenLiveDb,
    required String expectedTenantId,
    required String expectedStoreId,
    String? expectedHubId,
    String? safetyBackupPassword,
    int minSupportedSchemaVersion = 1,
    int maxSupportedSchemaVersion = 5,
    int kdfIterations = MmsbakV2Crypto.defaultPbkdf2Iterations,
    bool acquireLock = true,
    Future<void> Function(SpikeDatabase newDb, String restoreEpoch)? onDbReopened,
    void Function(String message)? log,
  }) async {
    final void Function(String message) writeLog =
        log ?? (msg) => stderr.writeln(msg);
    Future<HubRestoreResult> run() async {
      final inspected = await MmsbakV2Crypto.inspectFile(packageFile);
      final manifest = inspected.manifest;
      if (manifest.databaseType != DatabaseType.centralMaster) {
        throw BackupException(
          'ERR_DATABASE_TYPE_MISMATCH',
          'Bu yedek Master Hub merkezi veritabanına ait değil: ${manifest.databaseType.value}',
        );
      }
      if (manifest.tenantId != expectedTenantId) {
        throw const BackupException(
          'ERR_TENANT_ID_MISMATCH',
          'Yedek farklı bir işletmeye (tenant_id) ait.',
        );
      }
      if (manifest.storeId != expectedStoreId) {
        throw const BackupException(
          'ERR_STORE_ID_MISMATCH',
          'Yedek farklı bir şubeye (store_id) ait.',
        );
      }
      if (manifest.schemaVersion < minSupportedSchemaVersion ||
          manifest.schemaVersion > maxSupportedSchemaVersion) {
        throw BackupException(
          'ERR_UNSUPPORTED_SCHEMA',
          'Yedek şema sürümü (${manifest.schemaVersion}) bu Hub sürümü tarafından desteklenmiyor.',
        );
      }

      final stagingDir = await Directory.systemTemp.createTemp('mms_hub_restore_');
      final stagingDbFile = File(p.join(stagingDir.path, 'staging_restore.db'));
      final safetyPreSnapFile = File(p.join(stagingDir.path, 'safety_plain.db'));

      var dbPausedAndClosed = false;
      SpikeDatabase? openedDb;
      String? safetyPackagePath;
      var safetyEncrypted = false;
      final backupSwapTemp = File('${liveDbFile.path}.pre_swap');

      try {
        // 1. Paketi doğrula ve çöz (`MMSBAK02` / `MMSBAK01` tam uyumlu)
        await MmsbakV2Crypto.decryptFile(
          inputFile: packageFile,
          outputFile: stagingDbFile,
          password: recoveryPassword,
        );

        // 2. Ham FFI SQLite integrity_check
        _verifyIntegrityOrThrow(stagingDbFile);

        // 3. Staging üzerinde Drift açılış/migration ve WAL temizliği
        final migrationDb = SpikeDatabase(stagingDbFile);
        try {
          await migrationDb.customSelect('SELECT COUNT(*) FROM products;').getSingle();
          await migrationDb.customSelect('SELECT COUNT(*) FROM devices;').getSingle();
          final cp = await migrationDb.checkpointWal(mode: 'TRUNCATE');
          if (!cp.isSuccess) {
            throw const BackupException(
              'ERR_RESTORE_WAL_CHECKPOINT',
              'Staging veritabanı WAL checkpoint tamamlanamadı.',
            );
          }
          await migrationDb.customStatement('PRAGMA journal_mode = DELETE;');
        } finally {
          await migrationDb.close();
        }
        _deleteWalShm(stagingDbFile);

        // 4. Canlı yazmaları durdur, checkpoint yap ve canlı DB bağlantısını kapat
        await pauseAndCloseLiveDb();
        dbPausedAndClosed = true;

        // 5. Restore öncesi canlı DB varsa şifreli safety snapshot al
        if (await liveDbFile.exists() && (await liveDbFile.length()) > 0) {
          final safetyPass = safetyBackupPassword ?? recoveryPassword;
          final safetyDir = Directory(p.join(backupDir.path, 'safety_snapshots'));
          await safetyDir.create(recursive: true);

          await liveDbFile.copy(safetyPreSnapFile.path);
          final preChecksum = await MmsbakV2Crypto.computeFileSha256(safetyPreSnapFile);
          final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
          final safetyId = 'pre_restore_$stamp';
          final safetyTarget = File(p.join(safetyDir.path, '$safetyId.mmsbak'));
          final safetyManifest = BackupManifest(
            backupId: safetyId,
            deviceId: expectedHubId ?? 'SERVER_HUB',
            tenantId: expectedTenantId,
            storeId: expectedStoreId,
            databaseType: DatabaseType.centralMaster,
            schemaVersion: maxSupportedSchemaVersion,
            appVersion: manifest.appVersion,
            timestamp: DateTime.now().toUtc(),
            checksum: preChecksum,
            unencryptedSizeBytes: await safetyPreSnapFile.length(),
            encryptedSizeBytes: 0,
            encryptionAlgorithm: MmsbakV2Crypto.algorithmId,
            kdfIterations: kdfIterations,
          );
          if (safetyPass.length >= MmsbakV2Crypto.minPasswordLength) {
            await MmsbakV2Crypto.encryptFile(
              inputFile: safetyPreSnapFile,
              outputFile: safetyTarget,
              password: safetyPass,
              manifest: safetyManifest,
              kdfIterations: kdfIterations,
            );
          } else {
            // Eski S5A-4 kısa parolalı yerel/pepper uyumu (geriye dönük koruma)
            final plainBytes = await safetyPreSnapFile.readAsBytes();
            final legacyMan = safetyManifest.copyWith(
              encryptionAlgorithm: 'AES-256-CBC-HMAC-SHA256',
            );
            final pkgBytes = await Isolate.run(
              () => BackupCryptoService.encryptPackage(
                databaseBytes: plainBytes,
                password: safetyPass,
                manifest: legacyMan,
              ),
              debugName: 'mms_hub_safety_legacy_encrypt',
            );
            await LocalStorageProvider(safetyDir).saveBackup(
              packageBytes: pkgBytes,
              manifest: legacyMan.copyWith(encryptedSizeBytes: pkgBytes.length),
            );
            final written = await LocalStorageProvider(safetyDir).getBackupFile(safetyId);
            if (written.path != safetyTarget.path) {
              await written.rename(safetyTarget.path);
            }
          }
          safetyPackagePath = safetyTarget.path;
          safetyEncrypted = true;
        }

        // 6. Canlı DB dosyasını atomik değiştir (`.pre_swap` Step 7 tamamlanana dek tutulur)
        if (!await liveDbFile.parent.exists()) {
          await liveDbFile.parent.create(recursive: true);
        }
        _deleteWalShm(liveDbFile);
        if (await backupSwapTemp.exists()) {
          await backupSwapTemp.delete();
        }
        if (await liveDbFile.exists()) {
          await liveDbFile.rename(backupSwapTemp.path);
        }
        try {
          await stagingDbFile.copy(liveDbFile.path);
        } catch (e) {
          if (await backupSwapTemp.exists() && !(await liveDbFile.exists())) {
            await backupSwapTemp.rename(liveDbFile.path);
          }
          rethrow;
        }

        // 7. Yeni DB'yi aç, `restore_epoch` artır ve kontrollü token geçersizleştirme uygula
        final reopened = await reopenLiveDb(liveDbFile);
        openedDb = reopened;
        final restoreEpoch = generateRestoreEpoch();
        var invalidatedActive = 0;
        var preservedRevoked = 0;

        await reopened.transaction(() async {
          await reopened.into(reopened.hubMetadata).insertOnConflictUpdate(
                HubMetadataCompanion(
                  key: const Value('restore_epoch'),
                  value: Value(restoreEpoch),
                  updatedAt: Value(DateTime.now().toUtc()),
                ),
              );

          final allDevices = await reopened.select(reopened.devices).get();
          for (final device in allDevices) {
            if (!device.isActive) {
              // Kalıcı olarak iptal edilmiş cihaz ASLA tekrar aktif edilmez!
              preservedRevoked++;
              continue;
            }
            // Aktif cihaz token'ı geçersizleştirilir (401/yeniden eşleştirme gerekir),
            // ancak `isActive = true` korunarak allowRePair akışı açık bırakılır.
            final invalidatedSalt = TokenManager.generateSalt();
            final sentinelToken = TokenManager.generateToken();
            final nonMatchingHash = TokenManager.hashToken(
              rawToken: sentinelToken,
              salt: invalidatedSalt,
              pepper: 'RESTORE_EPOCH_INVALIDATED_${DateTime.now().microsecondsSinceEpoch}',
            );
            await (reopened.update(reopened.devices)
                  ..where((d) => d.deviceId.equals(device.deviceId)))
                .write(
              DevicesCompanion(
                tokenHash: Value(nonMatchingHash),
                salt: Value(invalidatedSalt),
                isConfirmed: const Value(false),
                isActive: const Value(true),
              ),
            );
            invalidatedActive++;
          }

          await reopened.into(reopened.deviceAuditLogs).insert(
                DeviceAuditLogsCompanion(
                  deviceId: const Value('HUB_RESTORE'),
                  action: const Value('RESTORE_CONTROLLED_INVALIDATION'),
                  details: Value(
                    'backup_id=${manifest.backupId}, restore_epoch=$restoreEpoch, '
                    'invalidated_active=$invalidatedActive, preserved_revoked=$preservedRevoked',
                  ),
                ),
              );
        });

        await reopened.checkpointWal(mode: 'TRUNCATE');
        if (onDbReopened != null) {
          await onDbReopened(reopened, restoreEpoch);
        }

        // Tüm restore adımları (yeniden açılış + epoch/token güncellemesi dahil) başarılı:
        // Artık geçici `.pre_swap` kopyası temizlenebilir; şifreli safety paketi saklanır.
        if (await backupSwapTemp.exists()) {
          try {
            await backupSwapTemp.delete();
          } catch (delErr) {
            writeLog(
              '[HubRestoreService] Geçici pre_swap dosyası silinemedi (${p.basename(backupSwapTemp.path)}): ${delErr.runtimeType}',
            );
          }
        }

        return HubRestoreResult(
          backupId: manifest.backupId,
          manifest: manifest,
          safetyBackupPath: safetyPackagePath,
          safetyBackupEncrypted: safetyEncrypted,
          restoreEpoch: restoreEpoch,
          invalidatedActiveDeviceCount: invalidatedActive,
          preservedRevokedDeviceCount: preservedRevoked,
          restoredAtUtc: DateTime.now().toUtc(),
        );
      } catch (e) {
        if (dbPausedAndClosed) {
          if (openedDb != null) {
            try {
              await openedDb.close();
            } catch (closeErr) {
              writeLog(
                '[HubRestoreService] Hata sonrası DB kapatma uyarısı: ${closeErr.runtimeType}',
              );
            }
            openedDb = null;
          }
          if (await backupSwapTemp.exists()) {
            try {
              _deleteWalShm(liveDbFile, log: writeLog);
              if (await liveDbFile.exists()) {
                await liveDbFile.delete();
              }
              await backupSwapTemp.rename(liveDbFile.path);
            } catch (rollbackErr) {
              writeLog(
                '[HubRestoreService] CRITICAL: pre_swap geri alma uyarısı (${p.basename(liveDbFile.path)}): ${rollbackErr.runtimeType}',
              );
            }
          } else if (safetyPackagePath != null &&
              await File(safetyPackagePath).exists() &&
              !await liveDbFile.exists()) {
            try {
              final safetyPass = safetyBackupPassword ?? recoveryPassword;
              await MmsbakV2Crypto.decryptFile(
                inputFile: File(safetyPackagePath),
                outputFile: liveDbFile,
                password: safetyPass,
              );
            } catch (safetyRollbackErr) {
              writeLog(
                '[HubRestoreService] CRITICAL: Koruyucu güvenlik paketinden geri alma uyarısı (${p.basename(safetyPackagePath)}): ${safetyRollbackErr.runtimeType}',
              );
            }
          }
          if (await liveDbFile.exists()) {
            try {
              openedDb = await reopenLiveDb(liveDbFile);
              if (onDbReopened != null) {
                await onDbReopened(openedDb, '');
              }
            } catch (reopenErr) {
              writeLog(
                '[HubRestoreService] Hata sonrası canlı DB yeniden açılamadı (${p.basename(liveDbFile.path)}): ${reopenErr.runtimeType}',
              );
            }
          }
        }
        rethrow;
      } finally {
        if (await stagingDir.exists()) {
          try {
            await stagingDir.delete(recursive: true);
          } catch (stageErr) {
            writeLog(
              '[HubRestoreService] Geçici staging dizini silinemedi (${p.basename(stagingDir.path)}): ${stageErr.runtimeType}',
            );
          }
        }
      }
    }

    if (acquireLock) {
      return lock.synchronized(BackupOperationKind.restore, run);
    }
    return run();
  }

  static void _verifyIntegrityOrThrow(File dbFile) {
    final check = raw_sqlite.sqlite3.open(
      dbFile.path,
      mode: raw_sqlite.OpenMode.readOnly,
    );
    try {
      final rows = check.select('PRAGMA integrity_check;');
      final status = rows.isEmpty ? '' : rows.first.columnAt(0)?.toString().toLowerCase();
      if (status != 'ok') {
        throw BackupException(
          'ERR_INTEGRITY_CHECK_FAILED',
          'Geri yüklenecek yedek SQLite bütünlük kontrolünden geçemedi: $status',
        );
      }
    } finally {
      check.close();
    }
  }

  static void _deleteWalShm(File dbFile, {void Function(String message)? log}) {
    for (final suffix in const ['-wal', '-shm']) {
      final f = File('${dbFile.path}$suffix');
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (delErr) {
          (log ?? stderr.writeln)(
            '[HubRestoreService] WAL/SHM dosyası silinemedi (${p.basename(f.path)}): ${delErr.runtimeType}',
          );
        }
      }
    }
  }
}
