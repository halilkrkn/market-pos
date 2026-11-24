import 'dart:io';

import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

import '../../../core/constants/app_constants.dart';
import '../../../core/storage/local_database_service.dart';
import '../../setup/domain/app_setup_config.dart';

/// S5A-4: İstemci yerel veritabanı (`client_local.db`) için şifreli yedekleme ve
/// rollback korumalı geri yükleme servisi.
class ClientBackupService {
  final LocalDatabaseService dbService;
  final Directory backupRootDir;
  final AppSetupConfig Function() readSetupConfig;
  final int kdfIterations;
  final DatabaseType? databaseTypeOverride;

  /// Faz 7A: Restore öncesi arka plan senkronizasyonunu duraklatır (devam eden turu bekler).
  final Future<void> Function()? pauseSync;

  /// Faz 7A: Restore sonrası (başarılı veya başarısız) senkronizasyonu yeniden başlatır.
  final void Function()? resumeSync;

  ClientBackupService({
    required this.dbService,
    required this.backupRootDir,
    required this.readSetupConfig,
    this.kdfIterations = BackupCryptoService.defaultPbkdf2Iterations,
    this.databaseTypeOverride,
    this.pauseSync,
    this.resumeSync,
  });

  DatabaseType get effectiveDatabaseType =>
      databaseTypeOverride ??
      ((Platform.isAndroid || Platform.isIOS)
          ? DatabaseType.mobileLocal
          : DatabaseType.clientLocal);

  Directory get safetyBackupDir => Directory(p.join(backupRootDir.path, 'safety'));

  /// BK-LOCK: Yedek ve restore aynı anda çalışmaz (ön plan zamanlayıcısı, arka plan
  /// işçisi ve kullanıcı komutu aynı kilit dosyasını paylaşır).
  File get operationLockFile => File(p.join(backupRootDir.path, BackupOperationLock.defaultFileName));

  BackupOperationLock get _operationLock => BackupOperationLock(operationLockFile);

  void _ensureFileBackedDatabase() {
    if (dbService.databasePath == ':memory:') {
      throw const BackupException(
        'ERR_MEMORY_DB_UNSUPPORTED',
        'Bellek içi veritabanı yedeklenemez veya geri yüklenemez.',
      );
    }
  }

  void _validatePassword(String password) {
    if (password.trim().length < 8) {
      throw const BackupException(
        'ERR_WEAK_PASSWORD',
        'Yedekleme parolası en az 8 karakter olmalıdır.',
      );
    }
  }

  Future<BackupResult> createEncryptedBackup({
    required String password,
    bool isMonthlyArchive = false,
  }) async {
    _ensureFileBackedDatabase();
    _validatePassword(password);

    final setup = readSetupConfig();
    final storageProvider = LocalStorageProvider(backupRootDir);
    return _operationLock.synchronized(
      BackupOperationKind.backup,
      () => DatabaseBackupEngine.createBackup(
        liveDbFile: File(dbService.databasePath),
        executeVacuumInto: dbService.vacuumInto,
        deviceId: setup.deviceId,
        tenantId: setup.tenantId,
        storeId: setup.storeId,
        databaseType: effectiveDatabaseType,
        schemaVersion: dbService.database.schemaVersion,
        appVersion: AppConstants.appVersion,
        backupPassword: password,
        storageProvider: storageProvider,
        kdfIterations: kdfIterations,
        isMonthlyArchive: isMonthlyArchive,
      ),
    );
  }

  Future<List<BackupPackageInfo>> listBackups() async {
    if (!backupRootDir.existsSync()) {
      return const <BackupPackageInfo>[];
    }
    final storageProvider = LocalStorageProvider(backupRootDir);
    final list = await storageProvider.listBackups(
      databaseType: effectiveDatabaseType,
    );
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  Future<RestoreResult> restoreEncryptedBackup({
    required String backupId,
    required String password,
  }) async {
    _ensureFileBackedDatabase();
    if (password.isEmpty) {
      throw const BackupException(
        'ERR_EMPTY_PASSWORD',
        'Geri yükleme için yedek parolası girilmelidir.',
      );
    }

    final setup = readSetupConfig();
    final storageProvider = LocalStorageProvider(backupRootDir);
    // BK-LOCK: Kilit senkron duraklatmadan ÖNCE alınır; meşgulse hiçbir şey değişmez.
    return _operationLock.synchronized(BackupOperationKind.restore, () async {
      // Faz 7A: Restore boyunca Hub'a gönderim/ACK yazımı yapılmaz (tek yazıcı ilkesi).
      if (pauseSync != null) await pauseSync!();
      try {
        return await _restoreWithEngine(backupId, password, setup, storageProvider);
      } finally {
        resumeSync?.call();
      }
    });
  }

  Future<RestoreResult> _restoreWithEngine(
    String backupId,
    String password,
    AppSetupConfig setup,
    BackupStorageProvider storageProvider,
  ) {
    return DatabaseBackupEngine.restoreBackup(
      backupId: backupId,
      liveDbFile: File(dbService.databasePath),
      backupPassword: password,
      storageProvider: storageProvider,
      expectedDeviceId: setup.deviceId,
      expectedTenantId: setup.tenantId,
      expectedStoreId: setup.storeId,
      expectedDatabaseType: effectiveDatabaseType,
      currentSchemaVersion: dbService.database.schemaVersion,
      pauseLiveDb: dbService.suspendForRestore,
      resumeLiveDb: dbService.resumeAfterRestore,
      safetyBackupDir: safetyBackupDir,
    );
  }

  /// Faz 3: Saklama politikası (30 gün günlük / 12 ay aylık arşiv) dışında kalan
  /// yerel yedekleri siler; silinen kimlikleri döner (ortak kilit altında).
  Future<List<String>> pruneExpiredBackups(RetentionPolicy retention) {
    return _operationLock.synchronized(BackupOperationKind.backup, () async {
      if (!backupRootDir.existsSync()) return const <String>[];
      return RetentionPolicyManager(policy: retention).executePruning(
        LocalStorageProvider(backupRootDir),
        databaseType: effectiveDatabaseType,
      );
    });
  }

  /// Faz 7D: En yeni yerel yedeği USB / ağ klasörüne doğrulamalı olarak kopyalar.
  Future<File> exportLatestBackupTo(Directory targetDir) {
    return _operationLock.synchronized(BackupOperationKind.backup, () async {
      final storageProvider = LocalStorageProvider(backupRootDir);
      final backups = !backupRootDir.existsSync()
          ? const <BackupPackageInfo>[]
          : await storageProvider.listBackups(databaseType: effectiveDatabaseType);
      if (backups.isEmpty) {
        throw const BackupException('ERR_NO_LOCAL_BACKUP', 'Aktarılacak yerel yedek yok; önce yedek alın.');
      }
      return BackupFileTransfer.exportToDirectory(source: backups.first.file, targetDir: targetDir);
    });
  }

  /// Faz 7D: USB'deki yedeği yapı/cihaz/şube doğrulamasıyla yerel yedek listesine alır.
  /// Parola ve HMAC doğrulaması geri yükleme sırasında (canlı DB'ye dokunmadan) yapılır.
  Future<BackupPackageInfo> importBackupFile(File external) {
    final setup = readSetupConfig();
    return _operationLock.synchronized(
      BackupOperationKind.backup,
      () => BackupFileTransfer.importFromFile(
        external: external,
        backupRoot: backupRootDir,
        expectedType: effectiveDatabaseType,
        expectedDeviceId: setup.deviceId,
        expectedTenantId: setup.tenantId,
        expectedStoreId: setup.storeId,
      ),
    );
  }

  Future<void> deleteBackup(String backupId) {
    return _operationLock.synchronized(BackupOperationKind.backup, () async {
      final storageProvider = LocalStorageProvider(backupRootDir);
      await storageProvider.deleteBackup(backupId);
    });
  }

  /// Faz C: Google Drive üzerindeki şifreli `.mmsbak` yedeklerini listeler.
  Future<List<DriveRemoteBackupInfo>> listGoogleDriveBackups({
    required GoogleDriveBackupUploader uploader,
    bool currentDeviceOnly = true,
  }) {
    final setup = readSetupConfig();
    return uploader.listRemoteBackups(
      tenantId: setup.tenantId,
      storeId: setup.storeId,
      deviceId: currentDeviceOnly ? setup.deviceId : null,
      databaseType: effectiveDatabaseType,
    );
  }

  /// Faz C: Owner kontrollü Google Drive geri yükleme.
  ///
  /// Yedeği önce geçici hazırlık dizinine indirir; kilit almadan veya canlı
  /// veritabanını duraklatmadan ÖNCE SHA-256 + `verifyPackageStructure` + parola +
  /// HMAC-SHA256 + tenant/store/device/şema + SQLite `integrity_check` doğrular.
  /// Bozuk/yanlış parolalı dosya silinir ve canlı DB'ye hiç dokunulmaz.
  /// Doğrulama geçerse [BackupOperationLock], `pauseSync`/`resumeSync`, koruyucu
  /// kopya ve Outbox korumasıyla güvenli geri yükler.
  Future<RestoreResult> downloadAndRestoreFromGoogleDrive({
    required GoogleDriveBackupUploader uploader,
    required DriveRemoteBackupInfo remote,
    required String password,
  }) async {
    _ensureFileBackedDatabase();
    if (password.trim().isEmpty) {
      throw const BackupException(
        'ERR_EMPTY_PASSWORD',
        'Geri yükleme için yedek parolası girilmelidir.',
      );
    }

    final setup = readSetupConfig();
    final stagingDir = Directory.systemTemp.createTempSync('mms_drive_restore_');
    try {
      final downloaded = await uploader.downloadEncryptedBackup(
        remote: remote,
        targetDir: stagingDir,
      );
      final packageBytes = await downloaded.readAsBytes();

      final DecryptedBackupResult decrypted;
      try {
        decrypted = await DatabaseBackupEngine.preVerifyEncryptedPackage(
          packageBytes: packageBytes,
          password: password,
        );
      } on BackupCryptoException catch (e) {
        throw BackupException('ERR_DECRYPTION_FAILED', e.message);
      }

      final manifest = decrypted.manifest;
      if (manifest.databaseType != effectiveDatabaseType) {
        throw BackupException(
          'ERR_DATABASE_TYPE_MISMATCH',
          'Veritabanı türü uyuşmazlığı: Hedef [${effectiveDatabaseType.value}], '
              'Yedek [${manifest.databaseType.value}].',
        );
      }
      if (manifest.deviceId != setup.deviceId) {
        throw BackupException(
          'ERR_DEVICE_ID_MISMATCH',
          'Cihaz kimliği uyuşmazlığı: Hedef [${setup.deviceId}], Yedek [${manifest.deviceId}].',
        );
      }
      if (manifest.tenantId != setup.tenantId) {
        throw BackupException(
          'ERR_TENANT_ID_MISMATCH',
          'Kiracı (Tenant) uyuşmazlığı: Hedef [${setup.tenantId}], Yedek [${manifest.tenantId}].',
        );
      }
      if (manifest.storeId != setup.storeId) {
        throw BackupException(
          'ERR_STORE_ID_MISMATCH',
          'Şube (Store) uyuşmazlığı: Hedef [${setup.storeId}], Yedek [${manifest.storeId}].',
        );
      }
      if (manifest.schemaVersion > dbService.database.schemaVersion) {
        throw BackupException(
          'ERR_INCOMPATIBLE_SCHEMA_VERSION',
          'Yedek şema sürümü (${manifest.schemaVersion}) desteklenenden yeni.',
        );
      }

      DatabaseBackupEngine.verifyDecryptedBytesIntegrity(
        decrypted.databaseBytes,
        stagingDir,
      );

      return await _operationLock.synchronized(BackupOperationKind.restore, () async {
        final storageProvider = LocalStorageProvider(backupRootDir);
        if (!await storageProvider.backupExists(manifest.backupId)) {
          final targetName = storageProvider.generateFileName(manifest);
          final targetFile = File(p.join(backupRootDir.path, targetName));
          final tmpFile = File('${targetFile.path}.tmp');
          await tmpFile.writeAsBytes(packageBytes, flush: true);
          await tmpFile.rename(targetFile.path);
        }

        if (pauseSync != null) {
          await pauseSync!();
        }
        try {
          return await _restoreWithEngine(
            manifest.backupId,
            password,
            setup,
            storageProvider,
          );
        } finally {
          resumeSync?.call();
        }
      });
    } finally {
      if (stagingDir.existsSync()) {
        try {
          stagingDir.deleteSync(recursive: true);
        } catch (e) {
          stderr.writeln(
            '[ClientBackupService] Geçici staging dizini silinemedi (${p.basename(stagingDir.path)}): ${e.runtimeType}',
          );
        }
      }
    }
  }
}
