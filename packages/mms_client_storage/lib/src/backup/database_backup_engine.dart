import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'backup_crypto.dart';
import 'backup_manifest.dart';
import 'backup_storage_provider.dart';
import 'client_restore_reconciler.dart';

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

  /// Restore ÖNCESİ canlı veritabanının güvenlik kopyası. [safetyBackupEncrypted]
  /// `true` ise şifreli `.mmsbak` paketidir (geri yüklenen yedeğin parolasıyla açılır);
  /// `false` ise şifresiz `.db` dosyasıdır (şifreleme kapalı veya başarısız).
  final String safetyBackupPath;
  final bool safetyBackupEncrypted;
  final DateTime restoredAt;

  const RestoreResult({
    required this.backupId,
    required this.manifest,
    required this.safetyBackupPath,
    required this.restoredAt,
    this.safetyBackupEncrypted = false,
  });
}

/// S5A-4: Veri kaybını önleyen, şifreli, doğrulanabilir ve geri alınabilir (rollback-safe)
/// SQLite veritabanı yedekleme ve geri yükleme motoru.
class DatabaseBackupEngine {
  static final Random _secureRandom = Random.secure();

  static String _redactFilesystemPath(String rawPath) {
    final normalized = rawPath.trim();
    if (normalized.isEmpty) return '[REDACTED_PATH]';
    final sepIndex = normalized.lastIndexOf(RegExp(r'[/\\]'));
    if (sepIndex < 0 || sepIndex == normalized.length - 1) {
      return '[REDACTED_PATH]';
    }
    final basename = normalized.substring(sepIndex + 1);
    return basename.isEmpty ? '[REDACTED_PATH]' : '[REDACTED_PATH]/$basename';
  }

  /// Hata ve kurtarma loglarındaki token, parola, PEM anahtarı, URL gizlileri
  /// ve tam yerel dosya yollarını maskeler.
  static String redactLogText(String raw) {
    var text = raw;
    text = text.replaceAll(
      RegExp(
        r'-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----',
      ),
      '[REDACTED_PRIVATE_KEY]',
    );
    text = text.replaceAllMapped(
      RegExp(
        r'("(?:auth_code|code|pairing_secret|device_token|access_token|accessToken|refresh_token|refreshToken|token|password|backupPassword|backup_password|recovery_password|recoveryPassword|privateKey|private_key|client_secret|clientSecret|admin_secret|adminSecret|live_sync_secret|dpapi_secret|signing_key|code_verifier|x-mms-admin-secret|x-admin-secret|api_key|upload_id|session|signature|sig|secret|pepper)"\s*:\s*)"[^"]*"',
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}"[REDACTED]"',
    );
    text = text.replaceAll(
      RegExp(r'Bearer\s+[A-Za-z0-9_\-\.]+', caseSensitive: false),
      'Bearer [REDACTED]',
    );
    text = text.replaceAll(
      RegExp(r'mms_dt_[A-Za-z0-9_\-]+'),
      'mms_dt_[REDACTED]',
    );
    text = text.replaceAll(
      RegExp(r'\bya29\.[A-Za-z0-9_\-\.]+'),
      'ya29.[REDACTED]',
    );
    text = text.replaceAll(
      RegExp(r'\b1//[A-Za-z0-9_\-\.]+'),
      '1//[REDACTED]',
    );
    text = text.replaceAll(
      RegExp(r'\bGOCSPX-[A-Za-z0-9_\-]+'),
      'GOCSPX-[REDACTED]',
    );
    text = text.replaceAllMapped(
      RegExp(
        r"""([?&])(code|auth_code|access_token|refresh_token|device_token|token|client_secret|admin_secret|live_sync_secret|dpapi_secret|signing_key|recovery_password|pairing_secret|private_key|code_verifier|api_key|key|upload_id|session|signature|sig|pepper|password|secret)=([^&#\s"'`\)\]]*)""",
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}${m.group(2)}=[REDACTED]',
    );
    text = text.replaceAllMapped(
      RegExp(
        r"""\b(access_token|refresh_token|device_token|token|client_secret|admin_secret|live_sync_secret|dpapi_secret|signing_key|recovery_password|pairing_secret|private_key|code_verifier|x-mms-admin-secret|x-admin-secret|api_key|auth_code|upload_id|pepper|secret|password)\s*([:=])\s*(?!\[REDACTED\])([^\s,&;"'`\)\]]+)""",
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}${m.group(2)} [REDACTED]',
    );
    text = text.replaceAllMapped(
      RegExp(
        r"""file:///(?:[A-Za-z]:[\\/][^\s"'`\)\]\r\n]+|(?:data|Users|home|var|private|tmp|opt|etc|root|storage|mnt|sdcard|Library|Volumes|proc)/[^\s"'`\)\]\r\n]+)""",
      ),
      (m) => 'file:///${_redactFilesystemPath(m.group(0)!.substring(8))}',
    );
    text = text.replaceAllMapped(
      RegExp(
        r'"((?:(?<![A-Za-z0-9_])[A-Za-z]:[\\/]|\\\\|/(?:data|Users|home|var|private|tmp|opt|etc|root|storage|mnt|sdcard|Library|Volumes|proc)/)[^"\r\n]+)"',
      ),
      (m) => '"${_redactFilesystemPath(m.group(1)!)}"',
    );
    text = text.replaceAllMapped(
      RegExp(
        r"'((?:(?<![A-Za-z0-9_])[A-Za-z]:[\\/]|\\\\|/(?:data|Users|home|var|private|tmp|opt|etc|root|storage|mnt|sdcard|Library|Volumes|proc)/)[^'\r\n]+)'",
      ),
      (m) => "'${_redactFilesystemPath(m.group(1)!)}'",
    );
    text = text.replaceAllMapped(
      RegExp(r"""(?<![A-Za-z0-9_])(?:[A-Za-z]:[\\/]|\\\\)[^\s"'`\)\]\r\n,;]+"""),
      (m) => _redactFilesystemPath(m.group(0)!),
    );
    text = text.replaceAllMapped(
      RegExp(
        r"""(?<![A-Za-z0-9:/\.\[])/(?:data|Users|home|var|private|tmp|opt|etc|root|storage|mnt|sdcard|Library|Volumes|proc)/[^\s"'`\)\]\r\n,;]+""",
      ),
      (m) => _redactFilesystemPath(m.group(0)!),
    );
    return text;
  }

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
    final tempSnapshotFile =
        File(p.join(tempDir.path, 'snapshot_$backupId.db'));

    try {
      // 2. WAL modunda çalışan veritabanından VACUUM INTO ile tutarlı snapshot al
      await executeVacuumInto(tempSnapshotFile.path);

      if (!await tempSnapshotFile.exists() ||
          (await tempSnapshotFile.length()) == 0) {
        throw const BackupException('ERR_EMPTY_SNAPSHOT',
            'Yedekleme snapshot dosyası üretilemedi veya boş.');
      }

      // 3. Snapshot üzerinde SQLite integrity check çalıştır
      final rawDb = sqlite3.open(tempSnapshotFile.path);
      try {
        final result = rawDb.select('PRAGMA integrity_check;');
        final status = result.first.columnAt(0)?.toString().toLowerCase();
        if (status != 'ok') {
          throw BackupException('ERR_INTEGRITY_CHECK_FAILED',
              'Snapshot SQLite integrity_check başarısız: $status');
        }
      } finally {
        rawDb.close();
      }

      // 4. SHA-256 Checksum ve dosya boyutunu hesapla
      final rawSnapshotBytes = await tempSnapshotFile.readAsBytes();
      final checksum =
          sha256.convert(rawSnapshotBytes).toString().toLowerCase();
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
        kdfIterations:
            kdfIterations ?? BackupCryptoService.defaultPbkdf2Iterations,
        isMonthlyArchive: isMonthlyArchive,
      );

      // 6. AES-256-CBC ve HMAC-SHA256 ile şifrele.
      // Faz 7A: PBKDF2 (600.000 iterasyon) + AES CPU yoğun; çağıran (UI) isolate'i
      // bloklamamak için ayrı isolate'te çalıştırılır.
      final packageBytes = await Isolate.run(
        () => BackupCryptoService.encryptPackage(
          databaseBytes: rawSnapshotBytes,
          password: backupPassword,
          manifest: manifest,
        ),
        debugName: 'mms_backup_encrypt',
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
        } on FileSystemException catch (e) {
          stderr.writeln(
            '[BackupEngine] Geçici snapshot dizini silinemedi (${p.basename(tempDir.path)}): ${redactLogText(e.message)}',
          );
        }
      }
    }
  }

  static Future<void> _safeRename(File source, String newPath,
      {int maxRetries = 30,
      Duration delay = const Duration(milliseconds: 50)}) async {
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

  static void _safeRenameSync(File source, String newPath,
      {int maxRetries = 30,
      Duration delay = const Duration(milliseconds: 50)}) {
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

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException catch (e) {
      stderr.writeln(
        '[BackupEngine] Geçici dosya silinemedi (${p.basename(file.path)}): ${redactLogText(e.message)}',
      );
    }
  }

  static void _deleteQuietlySync(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException catch (e) {
      stderr.writeln(
        '[BackupEngine] Geçici dosya silinemedi (${p.basename(file.path)}): ${redactLogText(e.message)}',
      );
    }
  }

  static void _verifyIntegrityOrThrow(File dbFile, String errorCode) {
    final checkDb = sqlite3.open(dbFile.path);
    try {
      final status = checkDb
          .select('PRAGMA integrity_check;')
          .first
          .columnAt(0)
          ?.toString()
          .toLowerCase();
      if (status != 'ok') {
        throw BackupException(
            errorCode, 'SQLite integrity_check başarısız: $status');
      }
    } finally {
      checkDb.close();
    }
  }

  /// Çözülmüş SQLite veritabanı baytlarının `PRAGMA integrity_check` doğrulamasını
  /// canlı veritabanına dokunmadan geçici bir hazırlık dosyasında çalıştırır.
  static void verifyDecryptedBytesIntegrity(
    List<int> decryptedDbBytes,
    Directory stagingDir,
  ) {
    final checkFile =
        File(p.join(stagingDir.path, 'precheck_${generateBackupId()}.db'));
    checkFile.writeAsBytesSync(decryptedDbBytes, flush: true);
    try {
      _verifyIntegrityOrThrow(checkFile, 'ERR_INTEGRITY_CHECK_FAILED');
    } finally {
      _deleteQuietlySync(checkFile);
    }
  }

  /// Bekleyen veya yarıda kalmış restore işlemini (.restore_journal) senkron olarak kurtarır.
  /// Süreç çökmesi veya elektrik kesintisi sonrasında veritabanı açılırken çağrılır.
  static bool recoverPendingRestoreSync(File liveDbFile) {
    final liveDir = liveDbFile.parent;
    final journalFile = File(
        p.join(liveDir.path, '${p.basename(liveDbFile.path)}.restore_journal'));
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
          checkDb?.close();
        }

        if (liveOk) {
          if (stagingFile != null && stagingFile.existsSync()) {
            _deleteQuietlySync(stagingFile);
          }
          if (swapFile != null && swapFile.existsSync()) {
            _deleteQuietlySync(swapFile);
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
          checkDb?.close();
        }

        if (stagingOk) {
          if (liveDbFile.existsSync()) {
            _deleteQuietlySync(liveDbFile);
          }
          _safeRenameSync(stagingFile, liveDbFile.path);
          if (swapFile != null && swapFile.existsSync()) {
            _deleteQuietlySync(swapFile);
          }
          journalFile.deleteSync();
          return true;
        }
      }

      // 3. Durum C: Swap yedeği mevcut -> Önceki kararlı duruma geri dönülür
      if (swapFile != null && swapFile.existsSync()) {
        if (liveDbFile.existsSync()) {
          _deleteQuietlySync(liveDbFile);
        }
        _safeRenameSync(swapFile, liveDbFile.path);
        if (stagingFile != null && stagingFile.existsSync()) {
          _deleteQuietlySync(stagingFile);
        }
        journalFile.deleteSync();
        return true;
      }

      // 4. Durum D: Koruyucu yedek mevcut -> Koruyucu yedekten canlı dosya kopyalanır
      if (safetyFile != null && safetyFile.existsSync()) {
        if (liveDbFile.existsSync()) {
          _deleteQuietlySync(liveDbFile);
        }
        safetyFile.copySync(liveDbFile.path);
        if (stagingFile != null && stagingFile.existsSync()) {
          _deleteQuietlySync(stagingFile);
        }
        journalFile.deleteSync();
        return true;
      }
    } catch (e) {
      stderr.writeln(
        '[CRITICAL] recoverPendingRestoreSync kurtarma hatası: ${redactLogText(e.toString())}',
      );
    }

    return false;
  }

  /// Asenkron kurtarma metodu
  static Future<bool> recoverPendingRestore(File liveDbFile) async {
    return recoverPendingRestoreSync(liveDbFile);
  }

  /// Canlı DB veya kilit dokunulmadan şifreli `.mmsbak` paketini ayrı isolate'te
  /// HMAC-SHA256 + parola + SHA-256 doğrulamasından geçirir.
  /// Static metod olduğu için çağıran servis (`this`) isolate kapanına yakalanmaz.
  static Future<DecryptedBackupResult> preVerifyEncryptedPackage({
    required Uint8List packageBytes,
    required String password,
  }) {
    return Isolate.run(
      () => BackupCryptoService.verifyAndDecryptPackage(
        packageBytes: packageBytes,
        password: password,
      ),
      debugName: 'mms_backup_preverify',
    );
  }

  /// Şifrelenmiş yedek paketini doğrular, koruyucu yedek alır ve canlı veritabanına kontrollü geri yükler
  static Future<RestoreResult> restoreBackup({
    required String backupId,
    required File liveDbFile,
    required String backupPassword,
    required BackupStorageProvider storageProvider,
    required String expectedDeviceId,
    required String expectedTenantId,
    String? expectedStoreId,
    required DatabaseType expectedDatabaseType,
    required int currentSchemaVersion,
    int minSupportedSchemaVersion = 1,
    required Future<void> Function() pauseLiveDb,
    required Future<void> Function() resumeLiveDb,
    required Directory safetyBackupDir,
    Future<void> Function(String safetyPath)? customSafetySnapshotExecutor,
    dynamic applySchemaMigration,

    /// ADR-BAK-03: `null` ise istemci DB türlerinde (clientLocal/mobileLocal) açıktır.
    bool? preservePendingOutbox,

    /// SEC-SAFETY: Başarılı restore sonrası şifresiz güvenlik kopyası, geri yüklenen
    /// yedeğin parolası ve KDF gücüyle şifreli `.mmsbak` paketine dönüştürülür.
    bool encryptSafetyBackup = true,

    /// Varsayılan mühürleme yerine kullanılacak adım (şifreli paketin yolunu döner).
    Future<String> Function(File plainSafetyBackup)? customSafetyBackupSealer,
  }) async {
    // 0. Önceki bir çökmeden kalan yarım kurtarma journal'ı varsa güvenle tamamla
    await recoverPendingRestore(liveDbFile);

    // 1. Yedek dosyasını getir
    final packageFile = await storageProvider.getBackupFile(backupId);
    if (!await packageFile.exists()) {
      throw BackupException(
          'ERR_BACKUP_NOT_FOUND', 'Yedek dosyası bulunamadı: $backupId');
    }

    final packageBytes = await packageFile.readAsBytes();

    // 2. Manifest'i oku ve uyumluluk kontrollerini yap
    final BackupManifest preliminaryManifest;
    try {
      preliminaryManifest =
          BackupCryptoService.extractManifestWithoutDecryption(packageBytes);
    } catch (e) {
      throw BackupException('ERR_CORRUPT_MANIFEST',
          'Yedek manifesti bozuk veya manipüle edilmiş: $e');
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

    if (expectedStoreId != null &&
        preliminaryManifest.storeId != expectedStoreId) {
      throw BackupException(
        'ERR_STORE_ID_MISMATCH',
        'Şube (Store) uyuşmazlığı: Hedef [$expectedStoreId], Yedek [${preliminaryManifest.storeId}]. Başka bir şubenin yedeği geri yüklenemez.',
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
      // Faz 7A: Şifre çözme/HMAC doğrulama ayrı isolate'te (UI donmaz).
      decryptedResult = await Isolate.run(
        () => BackupCryptoService.verifyAndDecryptPackage(
          packageBytes: packageBytes,
          password: backupPassword,
        ),
        debugName: 'mms_backup_decrypt',
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
    final stagingFile = File(p.join(
        liveDir.path, '${p.basename(liveDbFile.path)}.restore_staging.tmp'));
    if (await stagingFile.exists()) {
      await _deleteQuietly(stagingFile);
    }
    await stagingFile.writeAsBytes(decryptedResult.databaseBytes, flush: true);

    // 5. Staging DB üzerinde SQLite bütünlük kontrolü (PRAGMA integrity_check)
    final stagingDb = sqlite3.open(stagingFile.path);
    try {
      final res = stagingDb.select('PRAGMA integrity_check;');
      final status = res.first.columnAt(0)?.toString().toLowerCase();
      if (status != 'ok') {
        throw BackupException('ERR_INTEGRITY_CHECK_FAILED',
            'Çözülen veritabanı SQLite integrity_check başarısız: $status');
      }
    } finally {
      stagingDb.close();
    }

    // 6. Eski şema sürümünden restore edildiyse MİGRASYONU ÖNCE STAGING DB ÜZERİNDE UYGULA!
    // Böylece canlı veritabanına ve bağlantılara HİÇ DOKUNULMADAN migrasyon doğrulanmış olur.
    if (preliminaryManifest.schemaVersion < currentSchemaVersion) {
      if (applySchemaMigration != null) {
        if (applySchemaMigration is Future<void> Function(File, int, int)) {
          await applySchemaMigration(stagingFile,
              preliminaryManifest.schemaVersion, currentSchemaVersion);
        } else if (applySchemaMigration is Future<void> Function(int, int)) {
          await applySchemaMigration(
              preliminaryManifest.schemaVersion, currentSchemaVersion);
        } else {
          await (applySchemaMigration as dynamic)(stagingFile,
              preliminaryManifest.schemaVersion, currentSchemaVersion);
        }
      }

      final postMigrateDb = sqlite3.open(stagingFile.path);
      try {
        final postMigrateCheck =
            postMigrateDb.select('PRAGMA integrity_check;');
        final postMigrateStatus =
            postMigrateCheck.first.columnAt(0)?.toString().toLowerCase();
        if (postMigrateStatus != 'ok') {
          throw BackupException('ERR_MIGRATION_INTEGRITY_FAILED',
              'Şema migrasyonu sonrası veritabanı hasarlı: $postMigrateStatus');
        }
      } finally {
        postMigrateDb.close();
      }
    }

    // 7. CANLI VERİTABANINI GÜVENLE DURDUR (PAUSE LIVE DB & CONNECTION SAFETY)
    // Yeni istekler 503 ile durdurulur, devam edenler bitirilir, WAL checkpoint yapılır ve bağlantı kapatılır
    await pauseLiveDb();

    if (!safetyBackupDir.existsSync()) {
      safetyBackupDir.createSync(recursive: true);
    }
    final dateStr = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('-', '')
        .replaceAll('.', '_');
    final safetyBackupFile = File(p.join(safetyBackupDir.path,
        'safety_snapshot_${expectedDatabaseType.value}_$dateStr.db'));
    final swapBakFile =
        File(p.join(liveDir.path, '${p.basename(liveDbFile.path)}.swap_bak'));
    final journalFile = File(
        p.join(liveDir.path, '${p.basename(liveDbFile.path)}.restore_journal'));
    final shouldPreserveOutbox = preservePendingOutbox ??
        (expectedDatabaseType == DatabaseType.clientLocal ||
            expectedDatabaseType == DatabaseType.mobileLocal);

    // HAZIRLIK AŞAMASI (canlı dosyaya HENÜZ dokunulmaz). Faz 7A: Bu aşamadaki her hata
    // (disk dolu, USB çıkarıldı, kilit) canlı DB'yi yeniden açar ve staging'i temizler;
    // aksi halde duraklatılmış veritabanı/servis kalıcı olarak kapalı kalırdı.
    try {
      // 8. RESTORE ÖNCESİ KORUYUCU GÜVENLİK YEDEĞİ (Pre-Restore Safety Snapshot)
      if (await liveDbFile.exists()) {
        if (customSafetySnapshotExecutor != null) {
          await customSafetySnapshotExecutor(safetyBackupFile.path);
        } else {
          await safetyBackupFile.writeAsBytes(await liveDbFile.readAsBytes(),
              flush: true);
        }
      }

      // 8.1 ADR-BAK-03: Hub'a ulaşmamış Outbox işlemleri ve client_seq korunur.
      if (shouldPreserveOutbox) {
        ClientRestoreReconciler.mergeLiveOutboxIntoStaging(
          liveDbFile: liveDbFile,
          stagingDbFile: stagingFile,
        );
        _verifyIntegrityOrThrow(
            stagingFile, 'ERR_OUTBOX_MERGE_INTEGRITY_FAILED');
      }

      // 9. CRASH / POWER-LOSS JOURNAL YAZILMASI (Same Volume)
      final journalData = {
        'version': 1,
        'staging_file': stagingFile.path,
        'safety_file': safetyBackupFile.path,
        'live_file': liveDbFile.path,
        'swap_file': swapBakFile.path,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };
      await journalFile.writeAsString(jsonEncode(journalData), flush: true);
    } catch (e) {
      await _deleteQuietly(journalFile);
      await _deleteQuietly(stagingFile);
      await _deleteQuietly(File('${stagingFile.path}-wal'));
      await _deleteQuietly(File('${stagingFile.path}-shm'));
      if (customSafetySnapshotExecutor == null) {
        // Yarım yazılmış koruyucu yedek geçerli kurtarma noktası gibi görünmemeli.
        await _deleteQuietly(safetyBackupFile);
      }
      await resumeLiveDb();
      if (e is BackupException) rethrow;
      throw BackupException(
        'ERR_RESTORE_PREPARATION_FAILED',
        'Geri yükleme hazırlığı tamamlanamadı (disk dolu, hedef aygıt çıkarılmış veya dosya kilitli olabilir); '
            'canlı veritabanı değiştirilmedi: $e',
      );
    }

    // 10. ATOMİK DOSYA DEĞİŞTİRME (ATOMIC SWAP ON SAME VOLUME)
    try {
      // A. Canlı DB'nin eski WAL ve SHM dosyalarını temizle
      final walFile = File('${liveDbFile.path}-wal');
      final shmFile = File('${liveDbFile.path}-shm');
      if (await walFile.exists()) {
        await _deleteQuietly(walFile);
      }
      if (await shmFile.exists()) {
        await _deleteQuietly(shmFile);
      }

      // B. Windows dosya kilidi ve aynı disk bölümünde rename:
      // Canlı dosya swap_bak'a taşınır, staging dosya canlı dosya adına taşınır
      if (await swapBakFile.exists()) {
        await _deleteQuietly(swapBakFile);
      }

      if (await liveDbFile.exists()) {
        await _safeRename(liveDbFile, swapBakFile.path);
      }

      await _safeRename(stagingFile, liveDbFile.path);

      // C. Post-swap SQLite bütünlük doğrulaması
      final checkLiveDb = sqlite3.open(liveDbFile.path);
      try {
        final liveCheck = checkLiveDb.select('PRAGMA integrity_check;');
        final liveStatus =
            liveCheck.first.columnAt(0)?.toString().toLowerCase();
        if (liveStatus != 'ok') {
          throw BackupException('ERR_POST_RESTORE_INTEGRITY',
              'Geri yükleme sonrası canlı veritabanı hasarlı: $liveStatus');
        }
      } finally {
        checkLiveDb.close();
      }

      // D. Başarılı swap sonrası swap yedeğini ve journal dosyasını temizle
      if (await swapBakFile.exists()) {
        await _deleteQuietly(swapBakFile);
      }
      if (await journalFile.exists()) {
        await _deleteQuietly(journalFile);
      }

      // E. Veritabanını ve API kabulünü yeniden aç
      await resumeLiveDb();
    } catch (e) {
      // 11. BAŞARISIZLIK DURUMUNDA KORUYUCU YEDEKTEN OTOMATİK GERİ ALMA (ROLLBACK)
      try {
        if (await swapBakFile.exists()) {
          if (await liveDbFile.exists()) {
            await _deleteQuietly(liveDbFile);
          }
          await _safeRename(swapBakFile, liveDbFile.path);
        } else if (await safetyBackupFile.exists()) {
          if (await liveDbFile.exists()) {
            await _deleteQuietly(liveDbFile);
          }
          await safetyBackupFile.copy(liveDbFile.path);
        }

        final walFile = File('${liveDbFile.path}-wal');
        final shmFile = File('${liveDbFile.path}-shm');
        if (await walFile.exists()) {
          await _deleteQuietly(walFile);
        }
        if (await shmFile.exists()) {
          await _deleteQuietly(shmFile);
        }

        if (await stagingFile.exists()) {
          await _deleteQuietly(stagingFile);
        }
        if (await journalFile.exists()) {
          await _deleteQuietly(journalFile);
        }

        await resumeLiveDb();
      } catch (rollbackErr) {
        stderr.writeln(
          '[CRITICAL] Koruyucu yedekten geri alma sırasında ikincil hata: ${redactLogText(rollbackErr.toString())}',
        );
      }
      rethrow;
    } finally {
      if (await stagingFile.exists()) {
        await _deleteQuietly(stagingFile);
      }
    }

    // 12. SEC-SAFETY: Rollback penceresi kapandı (journal silindi, canlı DB açık);
    // şifresiz güvenlik kopyasına artık gerek yok → şifreli pakete dönüştürülür.
    var safetyPath = safetyBackupFile.path;
    var safetyEncrypted = false;
    if (encryptSafetyBackup && await safetyBackupFile.exists()) {
      try {
        safetyPath = customSafetyBackupSealer != null
            ? await customSafetyBackupSealer(safetyBackupFile)
            : await _sealSafetyBackup(
                plainSafety: safetyBackupFile,
                safetyDir: safetyBackupDir,
                password: backupPassword,
                kdfIterations: preliminaryManifest.kdfIterations,
                deviceId: expectedDeviceId,
                tenantId: expectedTenantId,
                storeId: expectedStoreId ?? preliminaryManifest.storeId,
                databaseType: expectedDatabaseType,
                schemaVersion: currentSchemaVersion,
              );
        safetyEncrypted = true;
      } catch (e) {
        // Restore tamamlandı; şifreleme hatası onu geri almaz. Şifresiz kopya korunur
        // (silinirse kurtarma noktası kaybolur) ve sonuçta işaretlenir.
        safetyPath = safetyBackupFile.path;
        stderr.writeln(
            '[BackupEngine] UYARI: Güvenlik kopyası şifrelenemedi, şifresiz kaldı (${p.basename(safetyPath)}): ${e.runtimeType}');
      }
    }

    return RestoreResult(
      backupId: backupId,
      manifest: manifest,
      safetyBackupPath: safetyPath,
      safetyBackupEncrypted: safetyEncrypted,
      restoredAt: DateTime.now().toUtc(),
    );
  }

  /// Şifresiz güvenlik kopyasını standart `.mmsbak` biçiminde şifreler, yazılan
  /// dosyayı bayt düzeyinde doğrular ve ancak ondan sonra şifresiz kopyayı siler.
  /// Paket mevcut restore/USB içe aktarma akışlarıyla açılabilir (aynı cihaz/şube).
  static Future<String> _sealSafetyBackup({
    required File plainSafety,
    required Directory safetyDir,
    required String password,
    required int kdfIterations,
    required String deviceId,
    required String tenantId,
    required String storeId,
    required DatabaseType databaseType,
    required int schemaVersion,
  }) async {
    final plainBytes = await plainSafety.readAsBytes();
    final manifest = BackupManifest(
      backupId: generateBackupId(),
      deviceId: deviceId,
      tenantId: tenantId,
      storeId: storeId,
      databaseType: databaseType,
      schemaVersion: schemaVersion,
      appVersion: safetySnapshotAppVersion,
      timestamp: DateTime.now().toUtc(),
      checksum: sha256.convert(plainBytes).toString().toLowerCase(),
      unencryptedSizeBytes: plainBytes.length,
      encryptedSizeBytes: 0,
      kdfIterations: kdfIterations,
    );
    final packageBytes = await Isolate.run(
      () => BackupCryptoService.encryptPackage(
          databaseBytes: plainBytes, password: password, manifest: manifest),
      debugName: 'mms_safety_encrypt',
    );
    final provider = LocalStorageProvider(safetyDir);
    await provider.saveBackup(packageBytes: packageBytes, manifest: manifest);
    final sealed = await provider.getBackupFile(manifest.backupId);

    final written = await sealed.readAsBytes();
    if (written.length != packageBytes.length ||
        sha256.convert(written) != sha256.convert(packageBytes)) {
      throw const BackupException('ERR_SAFETY_SEAL_VERIFY',
          'Şifreli güvenlik kopyası geri okunarak doğrulanamadı.');
    }
    await plainSafety.delete();
    return sealed.path;
  }

  /// Şifreli güvenlik kopyalarının manifestindeki `app_version` işareti.
  static const String safetySnapshotAppVersion = 'pre-restore-safety';
}
