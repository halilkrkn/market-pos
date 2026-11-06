import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'backup_crypto.dart';
import 'backup_manifest.dart';
import 'backup_storage_provider.dart';

class BackupException implements Exception {
  final String code;
  final String message;
  const BackupException(this.code, this.message);

  @override
  String toString() => 'BackupException [$code]: $message';
}

class BackupResult {
  final String backupId;
  final BackupManifest manifest;
  final int encryptedSizeBytes;
  final int unencryptedSizeBytes;
  final DateTime createdAt;

  const BackupResult({
    required this.backupId,
    required this.manifest,
    required this.encryptedSizeBytes,
    required this.unencryptedSizeBytes,
    required this.createdAt,
  });
}

class RestoreResult {
  final String backupId;
  final BackupManifest manifest;
  final String safetyBackupPath;
  final DateTime restoredAt;

  const RestoreResult({
    required this.backupId,
    required this.manifest,
    required this.safetyBackupPath,
    required this.restoredAt,
  });
}

/// S5A-4: Veri kaybını önleyen, şifreli, doğrulanabilir ve geri alınabilir (rollback-safe)
/// SQLite veritabanı yedekleme ve geri yükleme motoru.
class DatabaseBackupEngine {
  static final Random _secureRandom = Random.secure();

  /// Benzersiz 128-bit yedekleme kimliği üretir
  static String generateBackupId() {
    final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Aktif SQLite veritabanından tutarlı bir snapshot alır, şifreler ve depolama sağlayıcısına yazar
  static Future<BackupResult> createBackup({
    required File liveDbFile,
    required Future<void> Function(String snapshotPath) executeVacuumInto,
    required String deviceId,
    required String tenantId,
    required String storeId,
    required DatabaseType databaseType,
    required int schemaVersion,
    required String appVersion,
    required String backupPassword,
    required BackupStorageProvider storageProvider,
    int? kdfIterations,
    bool isMonthlyArchive = false,
    DateTime? timestamp,
  }) async {
    final effectiveTimestamp = (timestamp ?? DateTime.now()).toUtc();
    final backupId = generateBackupId();

    // 1. Geçici snapshot dosyası oluştur
    final tempDir = Directory.systemTemp.createTempSync('mms_backup_snap_');
    final tempSnapshotFile = File(p.join(tempDir.path, 'snapshot_$backupId.db'));

    try {
      // 2. WAL modunda çalışan veritabanından VACUUM INTO ile tutarlı snapshot al
      await executeVacuumInto(tempSnapshotFile.path);

      if (!await tempSnapshotFile.exists() || (await tempSnapshotFile.length()) == 0) {
        throw const BackupException('ERR_EMPTY_SNAPSHOT', 'Yedekleme snapshot dosyası üretilemedi veya boş.');
      }

      // 3. Snapshot üzerinde SQLite integrity check çalıştır
      final rawDb = sqlite3.open(tempSnapshotFile.path);
      try {
        final result = rawDb.select('PRAGMA integrity_check;');
        final status = result.first.columnAt(0)?.toString().toLowerCase();
        if (status != 'ok') {
          throw BackupException('ERR_INTEGRITY_CHECK_FAILED', 'Snapshot SQLite integrity_check başarısız: $status');
        }
      } finally {
        rawDb.dispose();
      }

      // 4. SHA-256 Checksum ve dosya boyutunu hesapla
      final rawSnapshotBytes = await tempSnapshotFile.readAsBytes();
      final checksum = sha256.convert(rawSnapshotBytes).toString().toLowerCase();
      final unencryptedSize = rawSnapshotBytes.length;

      // 5. Manifest oluştur
      final manifest = BackupManifest(
        backupId: backupId,
        deviceId: deviceId,
        tenantId: tenantId,
        storeId: storeId,
        databaseType: databaseType,
        schemaVersion: schemaVersion,
        appVersion: appVersion,
        timestamp: effectiveTimestamp,
        checksum: checksum,
        unencryptedSizeBytes: unencryptedSize,
        encryptedSizeBytes: 0, // encryptPackage içinde güncellenir
        kdfIterations: kdfIterations ?? BackupCryptoService.defaultPbkdf2Iterations,
        isMonthlyArchive: isMonthlyArchive,
      );

      // 6. AES-256-CBC ve HMAC-SHA256 ile şifrele
      final packageBytes = BackupCryptoService.encryptPackage(
        databaseBytes: rawSnapshotBytes,
        password: backupPassword,
        manifest: manifest,
      );

      // 7. Depolama sağlayıcısına güvenle yaz (.tmp -> .mmsbak atomik geçişi)
      await storageProvider.saveBackup(
        packageBytes: packageBytes,
        manifest: manifest.copyWith(encryptedSizeBytes: packageBytes.length),
      );

      return BackupResult(
        backupId: backupId,
        manifest: manifest.copyWith(encryptedSizeBytes: packageBytes.length),
        encryptedSizeBytes: packageBytes.length,
        unencryptedSizeBytes: unencryptedSize,
        createdAt: effectiveTimestamp,
      );
    } finally {
      // Geçici snapshot dizinini temizle
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  }

  static Future<void> _safeRename(File source, String newPath, {int maxRetries = 30, Duration delay = const Duration(milliseconds: 50)}) async {
    for (var i = 0; i < maxRetries; i++) {
      try {
        if (await source.exists()) {
          await source.rename(newPath);
        }
        return;
      } catch (e) {
        if (i == maxRetries - 1) rethrow;
        await Future.delayed(delay);
      }
    }
  }

  static void _safeRenameSync(File source, String newPath, {int maxRetries = 30, Duration delay = const Duration(milliseconds: 50)}) {
    for (var i = 0; i < maxRetries; i++) {
      try {
        if (source.existsSync()) {
          source.renameSync(newPath);
        }
        return;
      } catch (e) {
        if (i == maxRetries - 1) rethrow;
        sleep(delay);
      }
    }
  }

  /// Bekleyen veya yarıda kalmış restore işlemini (.restore_journal) senkron olarak kurtarır.
  /// Süreç çökmesi veya elektrik kesintisi sonrasında veritabanı açılırken çağrılır.
  static bool recoverPendingRestoreSync(File liveDbFile) {
    final liveDir = liveDbFile.parent;
    final journalFile = File(p.join(liveDir.path, '${p.basename(liveDbFile.path)}.restore_journal'));
    if (!journalFile.existsSync()) return false;

    try {
      final content = journalFile.readAsStringSync();
      final journalJson = jsonDecode(content) as Map<String, dynamic>;
      final stagingPath = journalJson['staging_file'] as String?;
      final safetyPath = journalJson['safety_file'] as String?;
      final swapPath = journalJson['swap_file'] as String?;

      final stagingFile = stagingPath != null ? File(stagingPath) : null;
      final safetyFile = safetyPath != null ? File(safetyPath) : null;
      final swapFile = swapPath != null ? File(swapPath) : null;

      // 1. Durum A: Canlı DB dosyası mevcut ve PRAGMA integrity_check başarılı -> Swap tamamlanmış, journal silinmemiş
      if (liveDbFile.existsSync()) {
        bool liveOk = false;
        Database? checkDb;
        try {
          checkDb = sqlite3.open(liveDbFile.path);
          final res = checkDb.select('PRAGMA integrity_check;');
          liveOk = (res.first.columnAt(0)?.toString().toLowerCase() == 'ok');
        } catch (_) {
          liveOk = false;
        } finally {
          checkDb?.dispose();
        }

        if (liveOk) {
          if (stagingFile != null && stagingFile.existsSync()) {
            try { stagingFile.deleteSync(); } catch (_) {}
          }
          if (swapFile != null && swapFile.existsSync()) {
            try { swapFile.deleteSync(); } catch (_) {}
          }
          journalFile.deleteSync();
          return true;
        }
      }

      // 2. Durum B: Staging dosyası mevcut ve bütünlük kontrolü geçerli -> Restore ileriye doğru tamamlanır
      if (stagingFile != null && stagingFile.existsSync()) {
        bool stagingOk = false;
        Database? checkDb;
        try {
          checkDb = sqlite3.open(stagingFile.path);
          final res = checkDb.select('PRAGMA integrity_check;');
          stagingOk = (res.first.columnAt(0)?.toString().toLowerCase() == 'ok');
        } catch (_) {
          stagingOk = false;
        } finally {
          checkDb?.dispose();
        }

        if (stagingOk) {
          if (liveDbFile.existsSync()) {
            try { liveDbFile.deleteSync(); } catch (_) {}
          }
          _safeRenameSync(stagingFile, liveDbFile.path);
          if (swapFile != null && swapFile.existsSync()) {
            try { swapFile.deleteSync(); } catch (_) {}
          }
          journalFile.deleteSync();
          return true;
        }
      }

      // 3. Durum C: Swap yedeği mevcut -> Önceki kararlı duruma geri dönülür
      if (swapFile != null && swapFile.existsSync()) {
        if (liveDbFile.existsSync()) {
          try { liveDbFile.deleteSync(); } catch (_) {}
        }
        _safeRenameSync(swapFile, liveDbFile.path);
        if (stagingFile != null && stagingFile.existsSync()) {
          try { stagingFile.deleteSync(); } catch (_) {}
        }
        journalFile.deleteSync();
        return true;
      }

      // 4. Durum D: Koruyucu yedek mevcut -> Koruyucu yedekten canlı dosya kopyalanır
      if (safetyFile != null && safetyFile.existsSync()) {
        if (liveDbFile.existsSync()) {
          try { liveDbFile.deleteSync(); } catch (_) {}
        }
        safetyFile.copySync(liveDbFile.path);
        if (stagingFile != null && stagingFile.existsSync()) {
          try { stagingFile.deleteSync(); } catch (_) {}
        }
        journalFile.deleteSync();
        return true;
      }
    } catch (e) {
      stderr.writeln('[CRITICAL] recoverPendingRestoreSync kurtarma hatası: $e');
    }

    return false;
  }

  /// Asenkron kurtarma metodu
  static Future<bool> recoverPendingRestore(File liveDbFile) async {
    return recoverPendingRestoreSync(liveDbFile);
  }

  /// Şifrelenmiş yedek paketini doğrular, koruyucu yedek alır ve canlı veritabanına kontrollü geri yükler
  static Future<RestoreResult> restoreBackup({
    required String backupId,
    required File liveDbFile,
    required String backupPassword,
    required BackupStorageProvider storageProvider,
    required String expectedDeviceId,
    required String expectedTenantId,
    required DatabaseType expectedDatabaseType,
    required int currentSchemaVersion,
    int minSupportedSchemaVersion = 1,
    required Future<void> Function() pauseLiveDb,
    required Future<void> Function() resumeLiveDb,
    required Directory safetyBackupDir,
    Future<void> Function(String safetyPath)? customSafetySnapshotExecutor,
    dynamic applySchemaMigration,
  }) async {
    // 0. Önceki bir çökmeden kalan yarım kurtarma journal'ı varsa güvenle tamamla
    await recoverPendingRestore(liveDbFile);

    // 1. Yedek dosyasını getir
    final packageFile = await storageProvider.getBackupFile(backupId);
    if (!await packageFile.exists()) {
      throw BackupException('ERR_BACKUP_NOT_FOUND', 'Yedek dosyası bulunamadı: $backupId');
    }

    final packageBytes = await packageFile.readAsBytes();

    // 2. Manifest'i oku ve uyumluluk kontrollerini yap
    final BackupManifest preliminaryManifest;
    try {
      preliminaryManifest = BackupCryptoService.extractManifestWithoutDecryption(packageBytes);
    } catch (e) {
      throw BackupException('ERR_CORRUPT_MANIFEST', 'Yedek manifesti bozuk veya manipüle edilmiş: $e');
    }

    if (preliminaryManifest.databaseType != expectedDatabaseType) {
      throw BackupException(
        'ERR_DATABASE_TYPE_MISMATCH',
        'Veritabanı türü uyuşmazlığı: Hedef [${expectedDatabaseType.value}], Yedek [${preliminaryManifest.databaseType.value}]. Farklı tür veritabanları birbirinin üzerine yüklenemez.',
      );
    }

    if (preliminaryManifest.deviceId != expectedDeviceId) {
      throw BackupException(
        'ERR_DEVICE_ID_MISMATCH',
        'Cihaz kimliği uyuşmazlığı: Hedef [$expectedDeviceId], Yedek [${preliminaryManifest.deviceId}]. Başka bir cihazın yedeği bu cihaza yüklenemez.',
      );
    }

    if (preliminaryManifest.tenantId != expectedTenantId) {
      throw BackupException(
        'ERR_TENANT_ID_MISMATCH',
        'Kiracı (Tenant) uyuşmazlığı: Hedef [$expectedTenantId], Yedek [${preliminaryManifest.tenantId}].',
      );
    }

    if (preliminaryManifest.schemaVersion > currentSchemaVersion) {
      throw BackupException(
        'ERR_INCOMPATIBLE_SCHEMA_VERSION',
        'Şema sürümü uyuşmazlığı: Yedeğin şema sürümü (${preliminaryManifest.schemaVersion}), mevcut uygulama şema sürümünden ($currentSchemaVersion) daha yeni. Geri yükleme yapılamaz.',
      );
    }

    if (preliminaryManifest.schemaVersion < minSupportedSchemaVersion) {
      throw BackupException(
        'ERR_UNSUPPORTED_OLD_SCHEMA',
        'Desteklenmeyen eski şema sürümü: Yedeğin şema sürümü (${preliminaryManifest.schemaVersion}), desteklenen minimum şema sürümünden ($minSupportedSchemaVersion) eski. Geri yükleme yapılamaz.',
      );
    }

    // 3. Şifre çözme ve bütünlük doğrulama (HMAC + Checksum)
    DecryptedBackupResult decryptedResult;
    try {
      decryptedResult = BackupCryptoService.verifyAndDecryptPackage(
        packageBytes: packageBytes,
        password: backupPassword,
      );
    } catch (e) {
      if (e is BackupCryptoException) {
        throw BackupException('ERR_DECRYPTION_FAILED', e.message);
      }
      throw BackupException('ERR_DECRYPTION_FAILED', e.toString());
    }

    final manifest = decryptedResult.manifest;

    // 4. STAGING DOSYASI: Canlı DB ile KESİNLİKLE AYNI DİSK BÖLÜMÜNDE (Same Volume) oluşturulur
    final liveDir = liveDbFile.parent;
    if (!liveDir.existsSync()) {
      liveDir.createSync(recursive: true);
    }
    final stagingFile = File(p.join(liveDir.path, '${p.basename(liveDbFile.path)}.restore_staging.tmp'));
    if (await stagingFile.exists()) {
      try { await stagingFile.delete(); } catch (_) {}
    }
    await stagingFile.writeAsBytes(decryptedResult.databaseBytes, flush: true);

    // 5. Staging DB üzerinde SQLite bütünlük kontrolü (PRAGMA integrity_check)
    final stagingDb = sqlite3.open(stagingFile.path);
    try {
      final res = stagingDb.select('PRAGMA integrity_check;');
      final status = res.first.columnAt(0)?.toString().toLowerCase();
      if (status != 'ok') {
        throw BackupException('ERR_INTEGRITY_CHECK_FAILED', 'Çözülen veritabanı SQLite integrity_check başarısız: $status');
      }
    } finally {
      stagingDb.dispose();
    }

    // 6. Eski şema sürümünden restore edildiyse MİGRASYONU ÖNCE STAGING DB ÜZERİNDE UYGULA!
    // Böylece canlı veritabanına ve bağlantılara HİÇ DOKUNULMADAN migrasyon doğrulanmış olur.
    if (preliminaryManifest.schemaVersion < currentSchemaVersion) {
      if (applySchemaMigration != null) {
        if (applySchemaMigration is Future<void> Function(File, int, int)) {
          await applySchemaMigration(stagingFile, preliminaryManifest.schemaVersion, currentSchemaVersion);
        } else if (applySchemaMigration is Future<void> Function(int, int)) {
          await applySchemaMigration(preliminaryManifest.schemaVersion, currentSchemaVersion);
        } else {
          await (applySchemaMigration as dynamic)(stagingFile, preliminaryManifest.schemaVersion, currentSchemaVersion);
        }
      }

      final postMigrateDb = sqlite3.open(stagingFile.path);
      try {
        final postMigrateCheck = postMigrateDb.select('PRAGMA integrity_check;');
        final postMigrateStatus = postMigrateCheck.first.columnAt(0)?.toString().toLowerCase();
        if (postMigrateStatus != 'ok') {
          throw BackupException('ERR_MIGRATION_INTEGRITY_FAILED', 'Şema migrasyonu sonrası veritabanı hasarlı: $postMigrateStatus');
        }
      } finally {
        postMigrateDb.dispose();
      }
    }

    // 7. CANLI VERİTABANINI GÜVENLE DURDUR (PAUSE LIVE DB & CONNECTION SAFETY)
    // Yeni istekler 503 ile durdurulur, devam edenler bitirilir, WAL checkpoint yapılır ve bağlantı kapatılır
    await pauseLiveDb();

    // 8. RESTORE ÖNCESİ KORUYUCU GÜVENLİK YEDEĞİ (Pre-Restore Safety Snapshot)
    if (!safetyBackupDir.existsSync()) {
      safetyBackupDir.createSync(recursive: true);
    }
    final dateStr = DateTime.now().toUtc().toIso8601String().replaceAll(':', '').replaceAll('-', '').replaceAll('.', '_');
    final safetyBackupFile = File(p.join(safetyBackupDir.path, 'safety_snapshot_${expectedDatabaseType.value}_$dateStr.db'));

    if (await liveDbFile.exists()) {
      if (customSafetySnapshotExecutor != null) {
        await customSafetySnapshotExecutor(safetyBackupFile.path);
      } else {
        await safetyBackupFile.writeAsBytes(await liveDbFile.readAsBytes(), flush: true);
      }
    }

    // 9. CRASH / POWER-LOSS JOURNAL YAZILMASI (Same Volume)
    final swapBakFile = File(p.join(liveDir.path, '${p.basename(liveDbFile.path)}.swap_bak'));
    final journalFile = File(p.join(liveDir.path, '${p.basename(liveDbFile.path)}.restore_journal'));

    final journalData = {
      'version': 1,
      'staging_file': stagingFile.path,
      'safety_file': safetyBackupFile.path,
      'live_file': liveDbFile.path,
      'swap_file': swapBakFile.path,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
    await journalFile.writeAsString(jsonEncode(journalData), flush: true);

    // 10. ATOMİK DOSYA DEĞİŞTİRME (ATOMIC SWAP ON SAME VOLUME)
    try {
      // A. Canlı DB'nin eski WAL ve SHM dosyalarını temizle
      final walFile = File('${liveDbFile.path}-wal');
      final shmFile = File('${liveDbFile.path}-shm');
      if (await walFile.exists()) {
        try { await walFile.delete(); } catch (_) {}
      }
      if (await shmFile.exists()) {
        try { await shmFile.delete(); } catch (_) {}
      }

      // B. Windows dosya kilidi ve aynı disk bölümünde rename:
      // Canlı dosya swap_bak'a taşınır, staging dosya canlı dosya adına taşınır
      if (await swapBakFile.exists()) {
        try { await swapBakFile.delete(); } catch (_) {}
      }

      if (await liveDbFile.exists()) {
        await _safeRename(liveDbFile, swapBakFile.path);
      }

      await _safeRename(stagingFile, liveDbFile.path);

      // C. Post-swap SQLite bütünlük doğrulaması
      final checkLiveDb = sqlite3.open(liveDbFile.path);
      try {
        final liveCheck = checkLiveDb.select('PRAGMA integrity_check;');
        final liveStatus = liveCheck.first.columnAt(0)?.toString().toLowerCase();
        if (liveStatus != 'ok') {
          throw BackupException('ERR_POST_RESTORE_INTEGRITY', 'Geri yükleme sonrası canlı veritabanı hasarlı: $liveStatus');
        }
      } finally {
        checkLiveDb.dispose();
      }

      // D. Başarılı swap sonrası swap yedeğini ve journal dosyasını temizle
      if (await swapBakFile.exists()) {
        try { await swapBakFile.delete(); } catch (_) {}
      }
      if (await journalFile.exists()) {
        try { await journalFile.delete(); } catch (_) {}
      }

      // E. Veritabanını ve API kabulünü yeniden aç
      await resumeLiveDb();
    } catch (e) {
      // 11. BAŞARISIZLIK DURUMUNDA KORUYUCU YEDEKTEN OTOMATİK GERİ ALMA (ROLLBACK)
      try {
        if (await swapBakFile.exists()) {
          if (await liveDbFile.exists()) {
            try { await liveDbFile.delete(); } catch (_) {}
          }
          await _safeRename(swapBakFile, liveDbFile.path);
        } else if (await safetyBackupFile.exists()) {
          if (await liveDbFile.exists()) {
            try { await liveDbFile.delete(); } catch (_) {}
          }
          await safetyBackupFile.copy(liveDbFile.path);
        }

        final walFile = File('${liveDbFile.path}-wal');
        final shmFile = File('${liveDbFile.path}-shm');
        if (await walFile.exists()) {
          try { await walFile.delete(); } catch (_) {}
        }
        if (await shmFile.exists()) {
          try { await shmFile.delete(); } catch (_) {}
        }

        if (await stagingFile.exists()) {
          try { await stagingFile.delete(); } catch (_) {}
        }
        if (await journalFile.exists()) {
          try { await journalFile.delete(); } catch (_) {}
        }

        await resumeLiveDb();
      } catch (rollbackErr) {
        stderr.writeln('[CRITICAL] Koruyucu yedekten geri alma sırasında ikincil hata: $rollbackErr');
      }
      rethrow;
    } finally {
      if (await stagingFile.exists()) {
        try { await stagingFile.delete(); } catch (_) {}
      }
    }

    return RestoreResult(
      backupId: backupId,
      manifest: manifest,
      safetyBackupPath: safetyBackupFile.path,
      restoredAt: DateTime.now().toUtc(),
    );
  }
}
