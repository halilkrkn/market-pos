import 'dart:async';
import 'dart:io';

import 'package:mms_client_storage/mms_client_storage.dart';

import 'hub_backup_oauth_service.dart';
import 'hub_backup_oauth_store.dart';
import 'hub_backup_state_store.dart';
import 'hub_recovery_key_store.dart';
import 'hub_snapshot_service.dart';

/// Faz B-3 (`ADR-023`): Merkezi Hub Google Drive Yedekleme Orkestratörü.
///
/// - 12 durumlu yaşam döngüsünü (`backup_jobs_state.json`) atomik yönetir.
/// - Tetikleyiciler: `INITIAL_ENABLE`, yerel `00:00` (`SCHEDULED_DAILY`), `CATCH_UP`, `MANUAL`.
/// - Üstel geri çekilme: `5, 10, 20, 40, 80, 160 dk` (gün sonuna dek 160 dk tavan).
/// - Gece yarısı devri: Önceki günün tamamlanmamış işi `SUPERSEDED` olur; önceki
///   geçerli `COMPLETED_UPLOADED` yedeği yenisi doğrulanana dek korunur.
/// - Aşamalı çökme kurtarma: `ENCRYPTED_LOCAL_READY` / `UPLOADING` / `RETRY_PENDING`
///   durumunda geçerli `.mmsbak` varsa 600k PBKDF2 tekrar çalıştırılmaz.
/// - Kooperatif kapanış: Aktif HTTP yüklemesi `< 1.5s` içinde iptal edilir (`RETRY_PENDING`,
///   aynı `backup_id`); aktif SQLite snapshot transaction'ı kesilmez.
/// - S1: Dakikalık zamanlayıcı ve açılış kurtarması yalnızca [runGuardedTick] üzerinden
///   çalışır; hiçbir hata `Timer` geri çağrısından sızıp Hub sürecini sonlandıramaz.
///   Kilit çakışması (`ERR_BACKUP_OPERATION_BUSY`) hata sayılmaz, sonraki tura ertelenir.
/// - S2: Tüm yedekler YALNIZCA Hub'da kayıtlı (DPAPI) Portable Recovery Password ile
///   şifrelenir; istekle gelen parola yedek şifrelemede kullanılmaz.
class HubBackupOrchestrator {
  static const List<int> retryBackoffMinutes = [5, 10, 20, 40, 80, 160];

  final HubSnapshotService snapshotService;
  final HubBackupStateStore stateStore;
  final HubRecoveryKeyStore recoveryKeyStore;
  final HubBackupOAuthService oauthService;
  final ResumableDriveUploader uploader;
  final BackupOperationLock operationLock;
  final int Function() readSchemaVersion;
  final String oauthClientId;
  final String? oauthClientSecret;
  final HubBackupRetentionPolicy retentionPolicy;
  final DateTime Function() localClock;
  final Duration checkInterval;

  /// Zamanlayıcı günlük çıkışı (varsayılan: `stderr`). Testler yakalamak için verir.
  final void Function(String message) log;

  Timer? _timer;
  bool _shutdownRequested = false;
  BackupCancellationToken? _activeCancellationToken;
  Future<HubBackupJobRecord?>? _activeRunFuture;
  bool _tickInFlight = false;
  String? _lastLoggedTickErrorSignature;
  HubSchedulerTickError? _lastTickError;

  /// Son başarısız zamanlayıcı turunun hata özeti (başarılı turda temizlenir).
  /// Kilit çakışması hata sayılmaz. Gizli bilgi içermez.
  HubSchedulerTickError? get lastSchedulerError => _lastTickError;

  HubBackupOrchestrator({
    required this.snapshotService,
    required this.stateStore,
    required this.recoveryKeyStore,
    required this.oauthService,
    required this.uploader,
    required this.operationLock,
    required this.readSchemaVersion,
    required this.oauthClientId,
    this.oauthClientSecret,
    this.retentionPolicy = const HubBackupRetentionPolicy(),
    DateTime Function()? localClock,
    this.checkInterval = const Duration(minutes: 1),
    void Function(String message)? log,
  })  : localClock = localClock ?? DateTime.now,
        log = log ?? _defaultLog;

  static void _defaultLog(String message) => stderr.writeln(message);

  static Duration retryDelayForAttempt(int attemptCount) {
    if (attemptCount <= 1) {
      return Duration(minutes: retryBackoffMinutes.first);
    }
    final index = attemptCount - 1;
    final mins = index >= retryBackoffMinutes.length
        ? retryBackoffMinutes.last
        : retryBackoffMinutes[index];
    return Duration(minutes: mins);
  }

  static String formatLocalDate(DateTime localDt) {
    final l = localDt.isUtc ? localDt.toLocal() : localDt;
    return '${l.year.toString().padLeft(4, '0')}-'
        '${l.month.toString().padLeft(2, '0')}-'
        '${l.day.toString().padLeft(2, '0')}';
  }

  Future<HubBackupJobsSnapshot> getStatusSnapshot() => stateStore.load();

  /// Google Drive `MARKET MMS Yedekleri/Hub` klasöründeki merkezi Hub yedeklerini
  /// listeler; varsa yerel disk önbelleği durumunu (`cachedLocally`) işaretler.
  Future<List<HubDriveRemoteBackup>> listDriveBackups() async {
    final cachedHubFolderId = await oauthService.getCachedHubFolderId();
    final remote = await uploader.listHubBackups(knownFolderId: cachedHubFolderId);
    final localSnap = await stateStore.load();
    final localByBackupId = {
      for (final j in localSnap.jobs) j.backupId: j.encryptedPath,
    };

    return remote.map((item) {
      var cached = false;
      final bId = item.backupId;
      if (bId != null && bId.isNotEmpty) {
        final trackedPath = localByBackupId[bId];
        if (trackedPath != null &&
            trackedPath.isNotEmpty &&
            File(trackedPath).existsSync()) {
          cached = true;
        } else if (snapshotService.encryptedFileForBackup(bId).existsSync()) {
          cached = true;
        }
      }
      return item.copyWith(cachedLocally: cached);
    }).toList();
  }

  /// Seçilen merkezi Hub yedeğini Google Drive'dan indirip boyut + SHA-256 +
  /// şifreli `.mmsbak` paket yapısı doğrulamasından geçirir (`AUD-CRIT-03`).
  Future<ResumableDriveDownloadResult> downloadBackupFromDrive({
    String? backupId,
    String? driveFileId,
    required Directory targetDir,
  }) async {
    final cleanBackupId = backupId?.trim();
    final cleanDriveFileId = driveFileId?.trim();
    if ((cleanBackupId == null || cleanBackupId.isEmpty) &&
        (cleanDriveFileId == null || cleanDriveFileId.isEmpty)) {
      throw const BackupException(
        'ERR_BACKUP_NOT_FOUND',
        'Google Drive indirmesi için backup_id veya drive_file_id gereklidir.',
      );
    }

    final snap = await stateStore.load();
    HubBackupJobRecord? matchingJob;
    if (cleanBackupId != null && cleanBackupId.isNotEmpty) {
      for (final j in snap.jobs) {
        if (j.backupId == cleanBackupId) {
          matchingJob = j;
          break;
        }
      }
    }

    String? resolvedDriveFileId = (cleanDriveFileId != null && cleanDriveFileId.isNotEmpty)
        ? cleanDriveFileId
        : matchingJob?.driveFileId;
    int? expectedSize = matchingJob?.encryptedSizeBytes;
    String? expectedSha = matchingJob?.encryptedSha256;
    String? expectedId = (cleanBackupId != null && cleanBackupId.isNotEmpty)
        ? cleanBackupId
        : matchingJob?.backupId;

    if (resolvedDriveFileId == null || resolvedDriveFileId.isEmpty) {
      final remoteList = await listDriveBackups();
      for (final r in remoteList) {
        if (r.backupId == cleanBackupId) {
          resolvedDriveFileId = r.driveFileId;
          expectedSize ??= r.sizeBytes > 0 ? r.sizeBytes : null;
          expectedSha ??= r.sha256Hex;
          expectedId ??= r.backupId;
          break;
        }
      }
    }

    if (resolvedDriveFileId == null || resolvedDriveFileId.isEmpty) {
      throw BackupException(
        'ERR_BACKUP_NOT_FOUND',
        'Yedek Google Drive üzerinde bulunamadı (${cleanBackupId ?? cleanDriveFileId}).',
      );
    }

    return uploader.downloadAndVerifyBackup(
      driveFileId: resolvedDriveFileId,
      targetDir: targetDir,
      expectedBackupId: expectedId,
      expectedSizeBytes: expectedSize,
      expectedSha256Hex: expectedSha,
    );
  }

  void start() {
    _shutdownRequested = false;
    _timer?.cancel();
    _timer = Timer.periodic(checkInterval, (_) {
      // S1: Geri çağrı asla hata fırlatmaz; runGuardedTick tüm hataları yakalar.
      unawaited(runGuardedTick());
    });
  }

  /// S1: Zamanlayıcı ve servis açılışı için TEK güvenli giriş noktası.
  ///
  /// - Önceki tur hâlâ sürüyorsa yeni tur başlatılmaz (çakışma yok).
  /// - `ERR_BACKUP_OPERATION_BUSY` (manuel yedek, restore, retention veya eski 24 saatlik
  ///   yerel yedek kilidi tutuyor) beklenen durumdur: hata kaydı oluşturulmaz, iş durumu
  ///   değiştirilmez ve bir sonraki tura ertelenir.
  /// - Diğer tüm hatalar (bozuk kurtarma parolası dosyası, disk/durum dosyası hatası vb.)
  ///   yakalanır, [lastSchedulerError] olarak saklanır ve günlüğe yazılır; aynı hata her
  ///   dakika tekrar loglanmaz. Hata hiçbir koşulda çağırana / Timer'a sızmaz.
  Future<HubBackupJobRecord?> runGuardedTick({bool startup = false}) async {
    if (_shutdownRequested || _tickInFlight) return null;
    _tickInFlight = true;
    try {
      final result = startup ? await recoverOnStartup() : await evaluateTick();
      _clearTickError();
      return result;
    } on BackupException catch (e) {
      if (e.code == BackupOperationLock.busyErrorCode) {
        log('[HubBackupScheduler] Yedekleme kilidi başka bir işlemde (yedek/restore/'
            'temizlik); bu tur atlandı, sonraki turda tekrar denenecek.');
        return null;
      }
      _recordTickError(e.code, e.message);
      return null;
    } on HubRecoveryKeyException catch (e) {
      _recordTickError(e.code, e.message);
      return null;
    } catch (e) {
      _recordTickError('ERR_HUB_BACKUP_SCHEDULER', e.toString());
      return null;
    } finally {
      _tickInFlight = false;
    }
  }

  void _recordTickError(String code, String message) {
    final safeMessage = _sanitizeSchedulerErrorMessage(code, message);
    _lastTickError = HubSchedulerTickError(
      code: code,
      message: safeMessage,
      atUtc: localClock().toUtc(),
    );
    final signature = '$code|$safeMessage';
    if (signature != _lastLoggedTickErrorSignature) {
      _lastLoggedTickErrorSignature = signature;
      log('[HubBackupScheduler] HATA [$code]: $safeMessage '
          '(Hub çalışmaya devam ediyor; sonraki turda tekrar denenecek.)');
    }
  }

  static String _sanitizeSchedulerErrorMessage(String code, String rawMessage) {
    var cleaned = rawMessage
        .replaceAll(RegExp(r'[A-Za-z]:\\[^\s,;]+'), '[yol]')
        .replaceAll(RegExp(r'/(?:[^\s/;,]+/)+[^\s,;]*'), '[yol]')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.length > 220) {
      cleaned = '${cleaned.substring(0, 217)}...';
    }
    if (cleaned.isEmpty) {
      return 'Otomatik yedekleme kontrolü başarısız oldu ($code).';
    }
    return cleaned;
  }

  void _clearTickError() {
    if (_lastTickError != null) {
      log('[HubBackupScheduler] Zamanlayıcı turu yeniden başarılı; önceki hata temizlendi.');
    }
    _lastTickError = null;
    _lastLoggedTickErrorSignature = null;
  }

  /// İlişkili kurtarma/yapılandırma sorunu çözüldüğünde ilgili zamanlayıcı hatasını temizler.
  void clearTickErrorIfCodes(Set<String> codes) {
    final active = _lastTickError;
    if (active != null && codes.contains(active.code)) {
      _lastTickError = null;
      _lastLoggedTickErrorSignature = null;
    }
  }

  /// Açılışta aşamalı çökme kurtarma ve zamanlama kontrolü.
  ///
  /// Servis açılışı bunu [runGuardedTick] (`startup: true`) üzerinden çağırır.
  Future<HubBackupJobRecord?> recoverOnStartup() async {
    if (_shutdownRequested) return null;
    await _supersedePastIncompleteJobs(formatLocalDate(localClock()));

    final reloaded = await stateStore.load();
    final today = formatLocalDate(localClock());
    final activeToday = _findRecoverableJobForDate(
      reloaded.jobs,
      today,
      uploadToDrive: reloaded.schedule.uploadToDrive,
    );
    if (activeToday != null) {
      final pass = await recoveryKeyStore.loadRecoveryPassword();
      if (pass != null) {
        return _runJobExclusive(activeToday, pass);
      }
    }
    return evaluateTick();
  }

  Future<HubBackupJobsSnapshot> configureSchedule({
    required bool enabled,
    int dailyHourLocal = 0,
    int dailyMinuteLocal = 0,
    bool uploadToDrive = true,
    String? unattendedRecoveryPassword,
    bool triggerInitialIfDue = true,
  }) async {
    if (dailyHourLocal < 0 ||
        dailyHourLocal > 23 ||
        dailyMinuteLocal < 0 ||
        dailyMinuteLocal > 59) {
      throw ArgumentError('Geçersiz günlük yedekleme saati: $dailyHourLocal:$dailyMinuteLocal');
    }

    if (unattendedRecoveryPassword != null) {
      await recoveryKeyStore.saveRecoveryPassword(unattendedRecoveryPassword);
    }
    if (enabled && !(await recoveryKeyStore.hasRecoveryPassword())) {
      throw const HubRecoveryKeyException(
        'ERR_RECOVERY_KEY_REQUIRED',
        'Zamanlanmış yedekleme için önce en az 12 karakterli kurtarma anahtarı kaydedilmelidir.',
      );
    }

    final nextConfig = HubBackupScheduleConfig(
      enabled: enabled,
      dailyHourLocal: dailyHourLocal,
      dailyMinuteLocal: dailyMinuteLocal,
      uploadToDrive: uploadToDrive,
    );
    // S3: Yalnızca zamanlama alanı güncellenir; aynı anda yazılan iş kayıtları korunur.
    late HubBackupJobsSnapshot before;
    await stateStore.update((current) {
      before = current;
      return current.copyWith(schedule: nextConfig);
    });

    if (enabled && triggerInitialIfDue) {
      final today = formatLocalDate(localClock());
      final hasCompletedToday = before.jobs.any(
        (j) =>
            j.scheduledDateLocal == today &&
            (j.state == HubBackupJobState.completedUploaded ||
                (!uploadToDrive &&
                    j.state == HubBackupJobState.encryptedLocalReady &&
                    j.lastErrorCode == null)),
      );
      if (!hasCompletedToday && !before.schedule.enabled) {
        try {
          await triggerBackup(trigger: HubBackupTrigger.initialEnable);
        } on BackupException catch (e) {
          if (e.code != BackupOperationLock.busyErrorCode) rethrow;
          // Zamanlama kaydedildi; kilit boşaldığında dakikalık tur CATCH_UP ile çalıştırır.
          log('[HubBackupScheduler] İlk etkinleştirme yedeği kilit meşgul olduğu için '
              'ertelendi; zamanlayıcı sonraki turda yakalayacak.');
        }
      }
    }
    return stateStore.load();
  }

  Future<HubBackupJobRecord?> evaluateTick() async {
    if (_shutdownRequested || _activeRunFuture != null) return null;

    final nowLocal = localClock();
    final nowUtc = nowLocal.toUtc();
    final todayStr = formatLocalDate(nowLocal);

    await _supersedePastIncompleteJobs(todayStr);

    final current = await stateStore.load();
    if (!current.schedule.enabled) return null;

    final recoveryPass = await recoveryKeyStore.loadRecoveryPassword();
    if (recoveryPass == null) return null;

    final todayJobs = current.jobs
        .where((j) => j.scheduledDateLocal == todayStr)
        .toList();

    for (final job in todayJobs) {
      if (job.state == HubBackupJobState.completedUploaded) {
        return null;
      }
      if (!current.schedule.uploadToDrive &&
          job.state == HubBackupJobState.encryptedLocalReady &&
          job.lastErrorCode == null) {
        return null;
      }
      if (job.state == HubBackupJobState.failedAuth ||
          job.state == HubBackupJobState.failedQuota) {
        // BK-028: Yetki veya kota hatasında hızlı kör tekrar döngüsüne girilmez.
        return null;
      }
      if (job.state == HubBackupJobState.retryPending) {
        if (job.nextRetryAtUtc == null || !nowUtc.isBefore(job.nextRetryAtUtc!)) {
          return _runJobExclusive(job, recoveryPass);
        }
        return null;
      }
      if (!job.state.isTerminal) {
        return _runJobExclusive(job, recoveryPass);
      }
    }

    final scheduledToday = DateTime(
      nowLocal.year,
      nowLocal.month,
      nowLocal.day,
      current.schedule.dailyHourLocal,
      current.schedule.dailyMinuteLocal,
    );
    if (nowLocal.isBefore(scheduledToday)) {
      return null;
    }

    final trigger = nowLocal.difference(scheduledToday) > const Duration(minutes: 15)
        ? HubBackupTrigger.catchUp
        : HubBackupTrigger.scheduledDaily;

    return triggerBackup(trigger: trigger);
  }

  /// Manuel veya zamanlanmış yeni iş başlatır (`BackupOperationLock` altında).
  ///
  /// S2: Paket HER ZAMAN Hub'da kayıtlı Portable Recovery Password ile şifrelenir.
  /// Kayıtlı parola yoksa `ERR_RECOVERY_KEY_REQUIRED` ile reddedilir (fail-closed);
  /// çağıranın verdiği geçici/kaydedilmemiş bir parola kabul edilmez.
  Future<HubBackupJobRecord> triggerBackup({
    HubBackupTrigger trigger = HubBackupTrigger.manual,
  }) async {
    final effectivePassword = await recoveryKeyStore.loadRecoveryPassword();
    if (effectivePassword == null) {
      throw const HubRecoveryKeyException(
        'ERR_RECOVERY_KEY_REQUIRED',
        'Yedekleme için önce Hub\'a en az 12 karakterli taşınabilir kurtarma parolası '
            'kaydedilmelidir.',
      );
    }
    MmsbakV2Crypto.validateRecoveryPassword(effectivePassword);

    final nowLocal = localClock();
    final nowUtc = nowLocal.toUtc();
    final todayStr = formatLocalDate(nowLocal);
    final backupId = DatabaseBackupEngine.generateBackupId();

    final newJob = HubBackupJobRecord(
      backupId: backupId,
      trigger: trigger,
      state: HubBackupJobState.pending,
      scheduledDateLocal: todayStr,
      createdAtUtc: nowUtc,
      updatedAtUtc: nowUtc,
    );
    return _runJobExclusive(newJob, effectivePassword, upsertInitial: true);
  }

  /// Bekleyen / FAILED_AUTH / FAILED_QUOTA / RETRY_PENDING bir işi manuel olarak tekrar dener.
  Future<HubBackupJobRecord> retryExistingJob(String backupId) async {
    final snap = await stateStore.load();
    final job = snap.jobs.firstWhere(
      (j) => j.backupId == backupId,
      orElse: () => throw BackupException(
        'ERR_JOB_NOT_FOUND',
        'Yedekleme işi bulunamadı: $backupId',
      ),
    );
    if (job.state.isTerminal) {
      return job;
    }
    final pass = await recoveryKeyStore.loadRecoveryPassword();
    if (pass == null) {
      throw const HubRecoveryKeyException(
        'ERR_RECOVERY_KEY_REQUIRED',
        'Tekrar deneme için kurtarma parolası gereklidir.',
      );
    }
    return _runJobExclusive(job, pass);
  }

  /// Kooperatif kapanış: Aktif Drive yüklemesini `< 1.5s` içinde durdurup
  /// aynı `backup_id` ile `RETRY_PENDING` durumuna alır; aktif SQLite snapshot'ı kesmez.
  Future<void> shutdown() async {
    _shutdownRequested = true;
    _timer?.cancel();
    _timer = null;
    _activeCancellationToken?.cancel();
    final inFlight = _activeRunFuture;
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (e) {
        log(
          '[HubBackupOrchestrator] Kapanış sırasında aktif yedekleme hatayla sonlandı: ${e.runtimeType}',
        );
      }
    }
  }

  Future<HubBackupJobRecord> _runJobExclusive(
    HubBackupJobRecord initialJob,
    String recoveryPassword, {
    bool upsertInitial = false,
  }) {
    final running = _activeRunFuture;
    if (running != null) {
      throw const BackupException(
        BackupOperationLock.busyErrorCode,
        'Şu anda başka bir Hub yedekleme işi yürütülüyor.',
      );
    }
    final future = operationLock.synchronized(
      BackupOperationKind.backup,
      () async {
        if (upsertInitial) {
          await stateStore.upsertJob(initialJob);
        }
        return _executeStagedPipeline(initialJob, recoveryPassword);
      },
    );
    _activeRunFuture = future;
    return future.whenComplete(() {
      if (identical(_activeRunFuture, future)) {
        _activeRunFuture = null;
      }
    });
  }

  Future<HubBackupJobRecord> _executeStagedPipeline(
    HubBackupJobRecord job,
    String recoveryPassword,
  ) async {
    var current = job;
    final token = BackupCancellationToken();
    _activeCancellationToken = token;
    if (_shutdownRequested) token.cancel();

    try {
      // Aşamalı çökme kurtarma kontrolü: Geçerli .mmsbak zaten varsa 600k PBKDF2'yi ATLA!
      final hasReusableEncrypted = await _hasValidLocalEncryptedPackage(current);

      if (!hasReusableEncrypted) {
        final hasReusableSnapshot = await _hasValidLocalSnapshot(current);

        // Aşama 1: Snapshot (`WriteQueue` yalnızca burada kullanılır)
        if (!hasReusableSnapshot) {
          current = current.transitionTo(
            HubBackupJobState.runningSnapshot,
            nowUtc: localClock(),
          );
          await stateStore.upsertJob(current);

          final stage1 = await snapshotService.captureConsistentSnapshot(
            backupId: current.backupId,
            nowUtc: localClock(),
          );
          current = current.transitionTo(
            HubBackupJobState.snapshotReady,
            nowUtc: localClock(),
            snapshotPath: stage1.snapshotFile.path,
          );
          await stateStore.upsertJob(current);
        }

        if (_shutdownRequested) {
          return await _pauseForShutdown(current);
        }

        // Aşama 2: Akışlı MMSBAK02 Şifreleme (`WriteQueue` dışında)
        current = current.transitionTo(
          HubBackupJobState.runningEncrypt,
          nowUtc: localClock(),
        );
        await stateStore.upsertJob(current);

        final snapFile = File(current.snapshotPath!);
        final schemaVer = readSchemaVersion();
        final baseManifest = BackupManifest(
          backupId: current.backupId,
          deviceId: snapshotService.hubId,
          tenantId: snapshotService.tenantId,
          storeId: snapshotService.storeId,
          databaseType: DatabaseType.centralMaster,
          schemaVersion: schemaVer,
          appVersion: snapshotService.appVersion,
          timestamp: current.createdAtUtc,
          checksum: await MmsbakV2Crypto.computeFileSha256(snapFile),
          unencryptedSizeBytes: await snapFile.length(),
          encryptedSizeBytes: 0,
          encryptionAlgorithm: MmsbakV2Crypto.algorithmId,
          kdfIterations: snapshotService.kdfIterations,
        );

        final encRes = await snapshotService.encryptSnapshotToPackage(
          backupId: current.backupId,
          snapshotFile: snapFile,
          recoveryPassword: recoveryPassword,
          baseManifest: baseManifest,
          cleanupSnapshot: true,
        );
        final encSha = await MmsbakV2Crypto.computeFileSha256(encRes.backupFile);

        current = current.transitionTo(
          HubBackupJobState.encryptedLocalReady,
          nowUtc: localClock(),
          snapshotPath: null,
          encryptedPath: encRes.backupFile.path,
          encryptedSha256: encSha,
          encryptedSizeBytes: encRes.encryptedSizeBytes,
        );
        await stateStore.upsertJob(current);
      }

      if (_shutdownRequested) {
        return await _pauseForShutdown(current);
      }

      // Aşama 3 + 4: 4 MiB Resumable Drive Upload + VERIFYING
      final encFile = File(current.encryptedPath!);
      final inspected = await MmsbakV2Crypto.inspectFile(encFile);

      // AUD-MED-03: upload_to_drive = false yapılandırıldıysa yerel şifreli paket
      // doğrulandıktan sonra ENCRYPTED_LOCAL_READY aşamasında temiz tamamlanır
      // (12-durum makinesine yeni durum eklenmez, Drive OAuth/yükleme çalıştırılmaz).
      final latestConfig = await stateStore.load();
      if (!latestConfig.schedule.uploadToDrive) {
        final localCompletedAt = localClock();
        if (current.state == HubBackupJobState.encryptedLocalReady) {
          current = current.transitionTo(
            HubBackupJobState.encryptedLocalReady,
            nowUtc: localCompletedAt,
            lastErrorCode: null,
            lastErrorMessage: null,
          );
          await stateStore.upsertJob(
            current,
            lastCompletedDateLocal: current.scheduledDateLocal,
            lastCompletedAtUtc: localCompletedAt.toUtc(),
          );
          await _applyPostCompletionRetention(localCompletedAt, allowDriveDeletion: false);
          _clearTickError();
          return current;
        }
      }

      final resumeDriveFileId =
          current.state == HubBackupJobState.verifying ? current.driveFileId : null;

      if (current.state != HubBackupJobState.verifying ||
          resumeDriveFileId == null ||
          resumeDriveFileId.isEmpty) {
        if (current.state == HubBackupJobState.verifying) {
          // 12-durum makinesini koru: VERIFYING -> RETRY_PENDING -> UPLOADING
          current = current.transitionTo(
            HubBackupJobState.retryPending,
            nowUtc: localClock(),
          );
          await stateStore.upsertJob(current);
        }
        current = current.transitionTo(
          HubBackupJobState.uploading,
          nowUtc: localClock(),
          lastErrorCode: null,
          lastErrorMessage: null,
        );
        await stateStore.upsertJob(current);
      }

      // S5: Yalnızca Hub alt klasör düzeninde önbelleğe alınmış kimlik kullanılır;
      // eski kök klasör kimliği yok sayılır ve `MARKET MMS Yedekleri/Hub` çözülür.
      final cachedHubFolderId = await oauthService.getCachedHubFolderId();
      final uploadRes = await uploader.uploadFile(
        encryptedFile: encFile,
        manifest: inspected.manifest,
        knownFolderId: cachedHubFolderId,
        existingSessionUri: current.driveSessionUri,
        existingUploadedBytes: current.uploadedBytes,
        existingDriveFileId: resumeDriveFileId,
        cancellationToken: token,
        onSessionProgress: (sessionUri, uploadedBytes) async {
          if (current.state == HubBackupJobState.verifying) {
            current = current.transitionTo(
              HubBackupJobState.retryPending,
              nowUtc: localClock(),
            );
            current = current.transitionTo(
              HubBackupJobState.uploading,
              nowUtc: localClock(),
            );
          }
          current = HubBackupJobRecord(
            backupId: current.backupId,
            trigger: current.trigger,
            state: current.state,
            scheduledDateLocal: current.scheduledDateLocal,
            createdAtUtc: current.createdAtUtc,
            updatedAtUtc: localClock().toUtc(),
            snapshotPath: current.snapshotPath,
            encryptedPath: current.encryptedPath,
            encryptedSha256: current.encryptedSha256,
            encryptedSizeBytes: current.encryptedSizeBytes,
            driveSessionUri: sessionUri,
            uploadedBytes: uploadedBytes,
            driveFileId: current.driveFileId,
            attemptCount: current.attemptCount,
            nextRetryAtUtc: current.nextRetryAtUtc,
            lastErrorCode: current.lastErrorCode,
            lastErrorMessage: current.lastErrorMessage,
          );
          await stateStore.upsertJob(current);
        },
        onBeforeVerify: (driveFileId) async {
          current = current.transitionTo(
            HubBackupJobState.verifying,
            nowUtc: localClock(),
            driveFileId: driveFileId,
          );
          await stateStore.upsertJob(current);
        },
      );

      if (uploadRes.folderId.isNotEmpty &&
          cachedHubFolderId != uploadRes.folderId) {
        await oauthService.updateFolderId(uploadRes.folderId);
      }

      final completedAt = localClock();
      current = current.transitionTo(
        HubBackupJobState.completedUploaded,
        nowUtc: completedAt,
        driveFileId: uploadRes.driveFileId,
        uploadedBytes: uploadRes.uploadedBytes,
        nextRetryAtUtc: null,
        lastErrorCode: null,
        lastErrorMessage: null,
      );
      await stateStore.upsertJob(
        current,
        lastCompletedDateLocal: current.scheduledDateLocal,
        lastCompletedAtUtc: completedAt.toUtc(),
      );

      // BK-030: Saklama budaması YALNIZCA COMPLETED_UPLOADED doğrulamasından sonra çalışır.
      await _applyPostCompletionRetention(completedAt);
      _clearTickError();
      return current;
    } on DriveResumableUploadException catch (e) {
      if (e.kind == DriveUploadFailureKind.cancelled) {
        current = current.transitionTo(
          HubBackupJobState.retryPending,
          nowUtc: localClock(),
          driveSessionUri: e.sessionUri ?? current.driveSessionUri,
          uploadedBytes: e.uploadedBytes > 0 ? e.uploadedBytes : current.uploadedBytes,
          lastErrorCode: e.code,
          lastErrorMessage: e.message,
        );
        await stateStore.upsertJob(current);
        return current;
      }

      if (e.kind == DriveUploadFailureKind.authFailure) {
        current = current.transitionTo(
          HubBackupJobState.failedAuth,
          nowUtc: localClock(),
          lastErrorCode: 'FAILED_AUTH',
          lastErrorMessage: e.message,
        );
        await stateStore.upsertJob(current);
        return current;
      }

      if (e.kind == DriveUploadFailureKind.quotaExceeded) {
        current = current.transitionTo(
          HubBackupJobState.failedQuota,
          nowUtc: localClock(),
          lastErrorCode: 'FAILED_QUOTA',
          lastErrorMessage: e.message,
        );
        await stateStore.upsertJob(current);
        return current;
      }

      final isVerifyMismatch =
          e.kind == DriveUploadFailureKind.integrityVerificationFailed;
      return _scheduleRetry(
        current,
        code: e.code,
        message: e.message,
        sessionUri: isVerifyMismatch ? null : e.sessionUri,
        uploadedBytes: isVerifyMismatch ? 0 : e.uploadedBytes,
        clearUploadSession: isVerifyMismatch,
      );
    } on HubBackupOAuthException catch (e) {
      if (e.code == 'FAILED_AUTH') {
        current = current.transitionTo(
          HubBackupJobState.failedAuth,
          nowUtc: localClock(),
          lastErrorCode: 'FAILED_AUTH',
          lastErrorMessage: e.message,
        );
        await stateStore.upsertJob(current);
        return current;
      }
      return _scheduleRetry(
        current,
        code: e.code,
        message: _sanitizeSchedulerErrorMessage(e.code, e.message),
      );
    } catch (e) {
      if (_shutdownRequested) {
        return await _pauseForShutdown(current);
      }
      final code = e is BackupException ? e.code : 'ERR_HUB_BACKUP_FAILED';
      return _scheduleRetry(
        current,
        code: code,
        message: _sanitizeSchedulerErrorMessage(code, e.toString()),
      );
    } finally {
      if (identical(_activeCancellationToken, token)) {
        _activeCancellationToken = null;
      }
    }
  }

  Future<HubBackupJobRecord> _pauseForShutdown(HubBackupJobRecord job) async {
    final paused = job.transitionTo(
      HubBackupJobState.retryPending,
      nowUtc: localClock(),
      lastErrorCode: 'SHUTDOWN_PAUSED',
      lastErrorMessage: 'Servis kapanışı nedeniyle yükleme güvenli noktada duraklatıldı.',
    );
    await stateStore.upsertJob(paused);
    return paused;
  }

  Future<HubBackupJobRecord> _scheduleRetry(
    HubBackupJobRecord job, {
    required String code,
    required String message,
    String? sessionUri,
    int? uploadedBytes,
    bool clearUploadSession = false,
  }) async {
    final nextAttempt = job.attemptCount + 1;
    final nowLocal = localClock();
    final delay = retryDelayForAttempt(nextAttempt);
    final nextRetryUtc = nowLocal.toUtc().add(delay);

    final retried = job.transitionTo(
      HubBackupJobState.retryPending,
      nowUtc: nowLocal,
      attemptCount: nextAttempt,
      nextRetryAtUtc: nextRetryUtc,
      driveSessionUri: clearUploadSession ? null : (sessionUri ?? job.driveSessionUri),
      driveFileId: clearUploadSession ? null : job.driveFileId,
      uploadedBytes: clearUploadSession
          ? 0
          : ((uploadedBytes != null && uploadedBytes > 0)
              ? uploadedBytes
              : job.uploadedBytes),
      lastErrorCode: code,
      lastErrorMessage: message,
    );
    await stateStore.upsertJob(retried);
    return retried;
  }

  Future<bool> _hasValidLocalEncryptedPackage(HubBackupJobRecord job) async {
    if (job.state != HubBackupJobState.encryptedLocalReady &&
        job.state != HubBackupJobState.uploading &&
        job.state != HubBackupJobState.verifying &&
        job.state != HubBackupJobState.retryPending &&
        job.state != HubBackupJobState.failedAuth &&
        job.state != HubBackupJobState.failedQuota) {
      return false;
    }
    final encPath = job.encryptedPath;
    final expectedSha = job.encryptedSha256;
    if (encPath == null || encPath.isEmpty || expectedSha == null) {
      return false;
    }
    final file = File(encPath);
    if (!await file.exists()) return false;
    try {
      await MmsbakV2Crypto.inspectFile(file);
      final actualSha = await MmsbakV2Crypto.computeFileSha256(file);
      return actualSha == expectedSha.toLowerCase();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _hasValidLocalSnapshot(HubBackupJobRecord job) async {
    if (job.state != HubBackupJobState.snapshotReady &&
        job.state != HubBackupJobState.runningEncrypt) {
      return false;
    }
    final snapPath = job.snapshotPath;
    if (snapPath == null || snapPath.isEmpty) return false;
    final file = File(snapPath);
    if (!await file.exists()) return false;
    try {
      HubSnapshotService.verifySnapshotIntegrityOrThrow(file);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _supersedePastIncompleteJobs(String todayStr) async {
    // S3: Güncel durum üzerinde alan bazlı dönüşüm (eski nesne geri yazılmaz).
    final nowUtc = localClock();
    await stateStore.update((snapshot) {
      var changed = false;
      final nextJobs = <HubBackupJobRecord>[];
      for (final j in snapshot.jobs) {
        final completedLocalOnly = !snapshot.schedule.uploadToDrive &&
            j.state == HubBackupJobState.encryptedLocalReady &&
            j.lastErrorCode == null &&
            j.encryptedPath != null;
        if (j.scheduledDateLocal.compareTo(todayStr) < 0 &&
            j.state.isIncompleteForRollover &&
            !completedLocalOnly) {
          changed = true;
          nextJobs.add(
            j.transitionTo(
              HubBackupJobState.superseded,
              nowUtc: nowUtc,
              lastErrorCode: 'ROLLOVER_SUPERSEDED',
              lastErrorMessage:
                  'Yeni gün başladı; tamamlanmamış önceki gün işi SUPERSEDED işaretlendi.',
            ),
          );
        } else {
          nextJobs.add(j);
        }
      }
      return changed ? snapshot.copyWith(jobs: nextJobs) : snapshot;
    });
  }

  HubBackupJobRecord? _findRecoverableJobForDate(
    List<HubBackupJobRecord> jobs,
    String dateStr, {
    required bool uploadToDrive,
  }) {
    for (final j in jobs) {
      if (j.scheduledDateLocal == dateStr &&
          !j.state.isTerminal &&
          j.state != HubBackupJobState.failedAuth &&
          j.state != HubBackupJobState.failedQuota) {
        if (!uploadToDrive &&
            j.state == HubBackupJobState.encryptedLocalReady &&
            j.lastErrorCode == null) {
          continue;
        }
        return j;
      }
    }
    return null;
  }

  Future<void> _applyPostCompletionRetention(
    DateTime nowLocal, {
    bool allowDriveDeletion = true,
  }) async {
    final snapshot = await stateStore.load();
    final candidates = snapshot.jobs
        .map(
          (j) => HubBackupRetentionCandidate(
            backupId: j.backupId,
            createdAtUtc: j.createdAtUtc,
            isCompletedUploaded: j.state == HubBackupJobState.completedUploaded,
            driveFileId: j.driveFileId,
            localFilePath: j.encryptedPath,
          ),
        )
        .toList();

    final drivePlan = retentionPolicy.evaluateDriveRetention(
      candidates,
      nowUtc: nowLocal.toUtc(),
    );
    final byId = {for (final j in snapshot.jobs) j.backupId: j};

    // Yalnızca Drive'dan başarıyla silinen (veya zaten bulunmayan, 404) yedeklerin
    // `driveFileId` alanı temizlenir. Böylece silinmiş bir Drive kopyası sonraki
    // retention turlarında "geçerli Drive yedeği" sayılmaz ve geri yükleme listesinde
    // indirilebilir gibi görünmez; başarısız silmeler bir sonraki turda yeniden denenir.
    // backupId → silinen Drive dosya kimliği / yerel yol. Durum güncellemesi yalnızca
    // kayıt hâlâ AYNI dosyayı gösteriyorsa ilgili alanı temizler (S3).
    final prunedDriveFileIds = <String, String>{};
    if (allowDriveDeletion) {
      for (final pruneId in drivePlan.pruneIds) {
        final fid = byId[pruneId]?.driveFileId;
        if (fid != null && fid.isNotEmpty) {
          try {
            await uploader.deleteRemoteFile(fid);
            prunedDriveFileIds[pruneId] = fid;
          } catch (e) {
            log('[HubBackupOrchestrator] Drive budama hatası ($pruneId): $e');
          }
        }
      }
    }

    final localPlan = retentionPolicy.evaluateLocalCacheRetention(
      candidates,
      nowUtc: nowLocal.toUtc(),
    );
    final prunedLocalPaths = <String, String>{};
    for (final pruneId in localPlan.pruneIds) {
      final path = byId[pruneId]?.encryptedPath;
      if (path != null && path.isNotEmpty) {
        try {
          final f = File(path);
          if (await f.exists()) {
            await f.delete();
          }
          prunedLocalPaths[pruneId] = path;
        } catch (e) {
          log('[HubBackupOrchestrator] Yerel önbellek temizleme hatası ($pruneId): $e');
        }
      }
    }

    if (prunedLocalPaths.isNotEmpty || prunedDriveFileIds.isNotEmpty) {
      // S3: Drive silmeleri beklenirken başka bir işlem (ör. zamanlama ayarı veya yeni iş)
      // durumu değiştirmiş olabilir. Okunan ESKİ nesne geri yazılmaz; yalnızca budanan
      // işlerin ilgili alanları GÜNCEL durum üzerinde temizlenir.
      await stateStore.patchJobs(
        {...prunedLocalPaths.keys, ...prunedDriveFileIds.keys},
        (j) {
          final clearLocal = prunedLocalPaths[j.backupId] != null &&
              j.encryptedPath == prunedLocalPaths[j.backupId];
          final clearDrive = prunedDriveFileIds[j.backupId] != null &&
              j.driveFileId == prunedDriveFileIds[j.backupId];
          if (!clearLocal && !clearDrive) return j;
          return _withRetentionApplied(j, clearLocal: clearLocal, clearDrive: clearDrive);
        },
      );
    }
  }

  /// Durum geçişi olmadan (12 durumlu makine korunur) retention sonucu alanları temizler.
  static HubBackupJobRecord _withRetentionApplied(
    HubBackupJobRecord j, {
    required bool clearLocal,
    required bool clearDrive,
  }) {
    return HubBackupJobRecord(
      backupId: j.backupId,
      trigger: j.trigger,
      state: j.state,
      scheduledDateLocal: j.scheduledDateLocal,
      createdAtUtc: j.createdAtUtc,
      updatedAtUtc: j.updatedAtUtc,
      snapshotPath: j.snapshotPath,
      encryptedPath: clearLocal ? null : j.encryptedPath,
      encryptedSha256: j.encryptedSha256,
      encryptedSizeBytes: j.encryptedSizeBytes,
      driveSessionUri: clearDrive ? null : j.driveSessionUri,
      uploadedBytes: j.uploadedBytes,
      driveFileId: clearDrive ? null : j.driveFileId,
      attemptCount: j.attemptCount,
      nextRetryAtUtc: j.nextRetryAtUtc,
      lastErrorCode: j.lastErrorCode,
      lastErrorMessage: j.lastErrorMessage,
    );
  }
}

/// S1: Son başarısız zamanlayıcı turunun gizli bilgi içermeyen özeti.
class HubSchedulerTickError {
  final String code;
  final String message;
  final DateTime atUtc;

  const HubSchedulerTickError({
    required this.code,
    required this.message,
    required this.atUtc,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        'at_utc': atUtc.toUtc().toIso8601String(),
      };
}
