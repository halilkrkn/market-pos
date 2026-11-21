import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

import '../../../core/security/android_keystore_token_store.dart';
import '../../../core/security/secure_token_store.dart';
import '../../../core/storage/local_database_service.dart';
import '../../setup/data/local_setup_config_store.dart';
import 'backup_schedule_controller.dart';
import 'client_backup_service.dart';

/// ADR-020: Android arka plan (uygulama kapalıyken) yedekleme kısıtları.
class BackgroundBackupConstraints {
  final bool requiresNetwork;
  final bool requiresBatteryNotLow;
  final bool requiresStorageNotLow;

  const BackgroundBackupConstraints({
    this.requiresNetwork = false,
    this.requiresBatteryNotLow = true,
    this.requiresStorageNotLow = true,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'requires_network': requiresNetwork,
        'requires_battery_not_low': requiresBatteryNotLow,
        'requires_storage_not_low': requiresStorageNotLow,
      };

  factory BackgroundBackupConstraints.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const BackgroundBackupConstraints();
    return BackgroundBackupConstraints(
      requiresNetwork: j['requires_network'] == true,
      requiresBatteryNotLow: j['requires_battery_not_low'] != false,
      requiresStorageNotLow: j['requires_storage_not_low'] != false,
    );
  }
}

/// Sistem seviyesi arka plan zamanlama durumu.
class BackgroundBackupScheduleStatus {
  final bool isScheduled;
  final bool supportedOnPlatform;
  final int intervalMinutes;
  final BackgroundBackupConstraints constraints;
  final DateTime? lastRunAtUtc;
  final String? lastStatus;
  final String? lastErrorCode;
  final DateTime? nextRunAtUtc;

  const BackgroundBackupScheduleStatus({
    required this.isScheduled,
    required this.supportedOnPlatform,
    this.intervalMinutes = 360,
    this.constraints = const BackgroundBackupConstraints(),
    this.lastRunAtUtc,
    this.lastStatus,
    this.lastErrorCode,
    this.nextRunAtUtc,
  });

  static const BackgroundBackupScheduleStatus unsupported =
      BackgroundBackupScheduleStatus(
    isScheduled: false,
    supportedOnPlatform: false,
  );

  static const BackgroundBackupScheduleStatus idle =
      BackgroundBackupScheduleStatus(
    isScheduled: false,
    supportedOnPlatform: true,
  );

  factory BackgroundBackupScheduleStatus.fromNativeMap(
    Map<dynamic, dynamic>? raw, {
    bool supportedOnPlatform = true,
  }) {
    if (raw == null) {
      return BackgroundBackupScheduleStatus(
        isScheduled: false,
        supportedOnPlatform: supportedOnPlatform,
      );
    }
    DateTime? parseEpoch(Object? val) {
      if (val is int && val > 0) {
        return DateTime.fromMillisecondsSinceEpoch(val, isUtc: true);
      }
      return null;
    }

    return BackgroundBackupScheduleStatus(
      isScheduled: raw['isScheduled'] == true,
      supportedOnPlatform: supportedOnPlatform,
      intervalMinutes: (raw['intervalMinutes'] as num?)?.toInt() ?? 360,
      constraints: BackgroundBackupConstraints(
        requiresNetwork: raw['requiresNetwork'] == true,
        requiresBatteryNotLow: raw['requiresBatteryNotLow'] != false,
        requiresStorageNotLow: raw['requiresStorageNotLow'] != false,
      ),
      lastRunAtUtc: parseEpoch(raw['lastRunEpochMs']),
      lastStatus: raw['lastStatus'] as String?,
      lastErrorCode: raw['lastErrorCode'] as String?,
      nextRunAtUtc: parseEpoch(raw['nextRunEpochMs']),
    );
  }
}

/// İşletim sistemi arka plan periyodik yedekleme zamanlayıcı sözleşmesi.
abstract class BackgroundBackupScheduler {
  bool get isPlatformSupported;

  Future<BackgroundBackupScheduleStatus> schedulePeriodic({
    required Duration interval,
    BackgroundBackupConstraints constraints = const BackgroundBackupConstraints(),
  });

  Future<BackgroundBackupScheduleStatus> cancelPeriodic();

  Future<BackgroundBackupScheduleStatus> getStatus();
}

/// Android `JobScheduler` (`MmsBackgroundBackupJobService`) MethodChannel köprüsü.
class MethodChannelBackgroundBackupScheduler implements BackgroundBackupScheduler {
  static const MethodChannel defaultChannel =
      MethodChannel('com.marketmms.market_pos/background_backup');

  final MethodChannel _channel;
  final bool? platformOverride;

  const MethodChannelBackgroundBackupScheduler({
    MethodChannel? channel,
    this.platformOverride,
  }) : _channel = channel ?? defaultChannel;

  @override
  bool get isPlatformSupported => platformOverride ?? Platform.isAndroid;

  @override
  Future<BackgroundBackupScheduleStatus> schedulePeriodic({
    required Duration interval,
    BackgroundBackupConstraints constraints = const BackgroundBackupConstraints(),
  }) async {
    if (!isPlatformSupported) {
      return BackgroundBackupScheduleStatus.unsupported;
    }
    final intervalMinutes = interval.inMinutes < 15 ? 15 : interval.inMinutes;
    try {
      final res = await _channel.invokeMapMethod<dynamic, dynamic>(
        'schedulePeriodicBackup',
        <String, dynamic>{
          'intervalMinutes': intervalMinutes,
          'requiresNetwork': constraints.requiresNetwork,
          'requiresBatteryNotLow': constraints.requiresBatteryNotLow,
          'requiresStorageNotLow': constraints.requiresStorageNotLow,
        },
      );
      return BackgroundBackupScheduleStatus.fromNativeMap(
        res,
        supportedOnPlatform: true,
      );
    } on MissingPluginException {
      return BackgroundBackupScheduleStatus(
        isScheduled: false,
        supportedOnPlatform: false,
        lastStatus: 'PLUGIN_MISSING',
        lastErrorCode: 'ERR_BG_PLUGIN_UNAVAILABLE',
      );
    } on PlatformException catch (e) {
      throw BackupException(
        e.code.isEmpty ? 'ERR_BG_SCHEDULE_FAILED' : e.code,
        'Arka plan yedek zamanlaması başarısız (${e.code}).',
      );
    }
  }

  @override
  Future<BackgroundBackupScheduleStatus> cancelPeriodic() async {
    if (!isPlatformSupported) {
      return BackgroundBackupScheduleStatus.unsupported;
    }
    try {
      final res = await _channel.invokeMapMethod<dynamic, dynamic>(
        'cancelPeriodicBackup',
      );
      return BackgroundBackupScheduleStatus.fromNativeMap(
        res,
        supportedOnPlatform: true,
      );
    } on MissingPluginException {
      return BackgroundBackupScheduleStatus.unsupported;
    } on PlatformException catch (e) {
      throw BackupException(
        e.code.isEmpty ? 'ERR_BG_CANCEL_FAILED' : e.code,
        'Arka plan yedek iptali başarısız (${e.code}).',
      );
    }
  }

  @override
  Future<BackgroundBackupScheduleStatus> getStatus() async {
    if (!isPlatformSupported) {
      return BackgroundBackupScheduleStatus.unsupported;
    }
    try {
      final res = await _channel.invokeMapMethod<dynamic, dynamic>(
        'getScheduleStatus',
      );
      return BackgroundBackupScheduleStatus.fromNativeMap(
        res,
        supportedOnPlatform: true,
      );
    } on MissingPluginException {
      return BackgroundBackupScheduleStatus.unsupported;
    } on PlatformException catch (e) {
      return BackgroundBackupScheduleStatus(
        isScheduled: false,
        supportedOnPlatform: true,
        lastStatus: 'ERROR',
        lastErrorCode: e.code.isEmpty ? 'ERR_BG_STATUS_FAILED' : e.code,
      );
    }
  }
}

/// Testler için bellek içi arka plan zamanlayıcı sürücüsü (yeniden başlatma simülasyonlu).
class InMemoryBackgroundBackupScheduler implements BackgroundBackupScheduler {
  @override
  final bool isPlatformSupported;

  bool scheduled = false;
  int intervalMinutes = 360;
  BackgroundBackupConstraints constraints = const BackgroundBackupConstraints();
  DateTime? lastRunAtUtc;
  String? lastStatus;
  String? lastErrorCode;
  DateTime? nextRunAtUtc;
  final DateTime Function() clock;

  InMemoryBackgroundBackupScheduler({
    this.isPlatformSupported = true,
    DateTime Function()? clock,
  }) : clock = clock ?? (() => DateTime.now().toUtc());

  @override
  Future<BackgroundBackupScheduleStatus> schedulePeriodic({
    required Duration interval,
    BackgroundBackupConstraints constraints = const BackgroundBackupConstraints(),
  }) async {
    if (!isPlatformSupported) {
      return BackgroundBackupScheduleStatus.unsupported;
    }
    scheduled = true;
    intervalMinutes = interval.inMinutes < 15 ? 15 : interval.inMinutes;
    this.constraints = constraints;
    nextRunAtUtc = clock().add(Duration(minutes: intervalMinutes));
    return getStatus();
  }

  @override
  Future<BackgroundBackupScheduleStatus> cancelPeriodic() async {
    if (!isPlatformSupported) {
      return BackgroundBackupScheduleStatus.unsupported;
    }
    scheduled = false;
    nextRunAtUtc = null;
    return getStatus();
  }

  void recordWorkerOutcome({
    required String status,
    String? errorCode,
  }) {
    final now = clock();
    lastRunAtUtc = now;
    lastStatus = status;
    lastErrorCode = errorCode;
    if (scheduled) {
      nextRunAtUtc = now.add(Duration(minutes: intervalMinutes));
    }
  }

  @override
  Future<BackgroundBackupScheduleStatus> getStatus() async {
    if (!isPlatformSupported) {
      return BackgroundBackupScheduleStatus.unsupported;
    }
    return BackgroundBackupScheduleStatus(
      isScheduled: scheduled,
      supportedOnPlatform: true,
      intervalMinutes: intervalMinutes,
      constraints: constraints,
      lastRunAtUtc: lastRunAtUtc,
      lastStatus: lastStatus,
      lastErrorCode: lastErrorCode,
      nextRunAtUtc: nextRunAtUtc,
    );
  }
}

enum BackgroundWorkerOutcomeKind {
  success,
  skippedNotEnabled,
  skippedNotDue,
  skippedLockBusy,
  failedKeystoreUnavailable,
  failedRetryable,
}

class BackgroundWorkerExecutionResult {
  final BackgroundWorkerOutcomeKind kind;
  final bool shouldRetry;
  final String statusCode;
  final String? errorCode;
  final BackupRunRecord? runRecord;
  final Duration? nextBackoffDelay;

  const BackgroundWorkerExecutionResult({
    required this.kind,
    required this.shouldRetry,
    required this.statusCode,
    this.errorCode,
    this.runRecord,
    this.nextBackoffDelay,
  });

  bool get isSuccess => kind == BackgroundWorkerOutcomeKind.success;
}

/// Arka plan işçisi (`MmsBackgroundBackupJobService` / test sürücüsü).
///
/// Özellikler:
/// - Uygulama kapalıyken çalışır (`FlutterEngine` arka plan giriş noktası).
/// - Ortak [BackupOperationLock] ile ön plan/restore ile eşzamanlı çalışmaz.
/// - [ScheduledBackupRunner.runIfDue] ile idempotent zaman kontrolü yapar.
/// - Keystore okuma hatasında fail-closed (`FAILED_KEYSTORE_UNAVAILABLE`) durur,
///   asla şifresiz yedek üretmez.
/// - Başarısız veya geçici ağ/disk hatalarında üstel geri çekilme (exponential backoff) üretir.
class BackgroundBackupWorkerExecutor {
  final ClientBackupService backupService;
  final SecureTokenStore secureStore;
  final ClientBackupScheduleSettingsStore settingsStore;
  final BackupScheduleStateStore stateStore;
  final Future<void> Function(BackupResult result)? afterSuccess;
  final DateTime Function() clock;

  const BackgroundBackupWorkerExecutor({
    required this.backupService,
    required this.secureStore,
    required this.settingsStore,
    required this.stateStore,
    this.afterSuccess,
    DateTime Function()? clock,
  }) : clock = clock ?? _utcNow;

  static DateTime _utcNow() => DateTime.now().toUtc();

  static Duration computeBackoffDelay(int failureCount) {
    final safeFailures = failureCount < 1 ? 1 : (failureCount > 6 ? 6 : failureCount);
    final minutes = 5 * (1 << (safeFailures - 1)); // 5dk, 10dk, 20dk, 40dk, 80dk, 160dk
    return Duration(minutes: minutes > 180 ? 180 : minutes);
  }

  Future<BackgroundWorkerExecutionResult> executeTick() async {
    final settings = await settingsStore.load();
    if (!settings.enabled) {
      return const BackgroundWorkerExecutionResult(
        kind: BackgroundWorkerOutcomeKind.skippedNotEnabled,
        shouldRetry: false,
        statusCode: 'SKIPPED_DISABLED',
      );
    }

    // ADR-020: Keystore'dan parolayı ön-kontrol ile oku (fail-closed; şifresiz yedek yasak).
    final String? password;
    try {
      password = await secureStore.readSecret(BackupScheduleController.passwordSecretKey);
    } on SecureStorageException catch (e) {
      return BackgroundWorkerExecutionResult(
        kind: BackgroundWorkerOutcomeKind.failedKeystoreUnavailable,
        shouldRetry: true,
        statusCode: 'FAILED_KEYSTORE_UNAVAILABLE',
        errorCode: e.code ?? 'ERR_KEYSTORE_UNAVAILABLE',
        nextBackoffDelay: computeBackoffDelay(1),
      );
    } on PlatformException catch (e) {
      return BackgroundWorkerExecutionResult(
        kind: BackgroundWorkerOutcomeKind.failedKeystoreUnavailable,
        shouldRetry: true,
        statusCode: 'FAILED_KEYSTORE_UNAVAILABLE',
        errorCode: e.code.isEmpty ? 'ERR_KEYSTORE_PLATFORM' : e.code,
        nextBackoffDelay: computeBackoffDelay(1),
      );
    } on MissingPluginException {
      return const BackgroundWorkerExecutionResult(
        kind: BackgroundWorkerOutcomeKind.failedKeystoreUnavailable,
        shouldRetry: false,
        statusCode: 'FAILED_KEYSTORE_MISSING_PLUGIN',
        errorCode: 'MISSING_PLUGIN',
      );
    }

    final String resolvedPassword;
    if (password == null || password.isEmpty) {
      return const BackgroundWorkerExecutionResult(
        kind: BackgroundWorkerOutcomeKind.failedKeystoreUnavailable,
        shouldRetry: false,
        statusCode: 'FAILED_PASSWORD_MISSING',
        errorCode: 'ERR_SCHEDULE_PASSWORD_MISSING',
      );
    } else {
      resolvedPassword = password;
    }

    final policy = settings.toPolicy();
    final preState = await stateStore.load();
    if (!policy.isDue(state: preState, now: clock())) {
      return const BackgroundWorkerExecutionResult(
        kind: BackgroundWorkerOutcomeKind.skippedNotDue,
        shouldRetry: false,
        statusCode: 'SKIPPED_NOT_DUE',
      );
    }

    final runner = ScheduledBackupRunner(
      readPolicy: () => policy,
      stateStore: stateStore,
      clock: clock,
      createBackup: () =>
          backupService.createEncryptedBackup(password: resolvedPassword),
      pruneExpired: () => backupService.pruneExpiredBackups(policy.retention),
      afterSuccess: afterSuccess,
    );

    final record = await runner.runIfDue();
    if (record == null) {
      // ScheduledBackupRunner.runIfDue yalnızca kilit başka işlemde tutulduğunda null döner.
      return const BackgroundWorkerExecutionResult(
        kind: BackgroundWorkerOutcomeKind.skippedLockBusy,
        shouldRetry: true,
        statusCode: 'SKIPPED_LOCK_BUSY',
        errorCode: BackupOperationLock.busyErrorCode,
        nextBackoffDelay: Duration(minutes: 5),
      );
    }

    if (!record.success) {
      if (record.errorCode == BackupOperationLock.busyErrorCode) {
        return BackgroundWorkerExecutionResult(
          kind: BackgroundWorkerOutcomeKind.skippedLockBusy,
          shouldRetry: true,
          statusCode: 'SKIPPED_LOCK_BUSY',
          errorCode: BackupOperationLock.busyErrorCode,
          runRecord: record,
          nextBackoffDelay: const Duration(minutes: 5),
        );
      }
      final state = await stateStore.load();
      return BackgroundWorkerExecutionResult(
        kind: BackgroundWorkerOutcomeKind.failedRetryable,
        shouldRetry: true,
        statusCode: 'FAILED',
        errorCode: record.errorCode ?? 'ERR_BACKUP_FAILED',
        runRecord: record,
        nextBackoffDelay: computeBackoffDelay(state.consecutiveFailures),
      );
    }

    return BackgroundWorkerExecutionResult(
      kind: BackgroundWorkerOutcomeKind.success,
      shouldRetry: false,
      statusCode: 'SUCCESS',
      runRecord: record,
    );
  }
}

/// Android `MmsBackgroundBackupJobService` arka plan FlutterEngine giriş noktası.
@pragma('vm:entry-point')
Future<void> mmsBackgroundBackupEntrypoint() async {
  const workerChannel = MethodChannel('com.marketmms.market_pos/background_backup_worker');
  var success = false;
  var shouldRetry = true;
  var status = 'FAILED';
  String? errorCode;

  LocalDatabaseService? localDb;
  try {
    final defaultDbPath = LocalDatabaseService.resolveDefaultDatabasePath();
    DatabaseBackupEngine.recoverPendingRestoreSync(File(defaultDbPath));
    localDb = await LocalDatabaseService.initialize(customPath: defaultDbPath);
    final dataDir = Directory(localDb.dataDirectoryPath);
    final setup = await FileSetupConfigStore.inDirectory(dataDir).load();
    final secureStore = const AndroidKeystoreTokenStore();

    final backupService = ClientBackupService(
      dbService: localDb,
      backupRootDir: Directory(p.join(dataDir.path, 'backups')),
      readSetupConfig: () => setup,
      databaseTypeOverride: DatabaseType.mobileLocal,
    );

    final executor = BackgroundBackupWorkerExecutor(
      backupService: backupService,
      secureStore: secureStore,
      settingsStore: ClientBackupScheduleSettingsStore(
        File(p.join(dataDir.path, 'backup_schedule_settings.json')),
      ),
      stateStore: BackupScheduleStateStore(
        File(p.join(dataDir.path, 'backup_schedule_state.json')),
      ),
    );

    final outcome = await executor.executeTick();
    success = outcome.isSuccess ||
        outcome.kind == BackgroundWorkerOutcomeKind.skippedNotDue ||
        outcome.kind == BackgroundWorkerOutcomeKind.skippedNotEnabled;
    shouldRetry = outcome.shouldRetry;
    status = outcome.statusCode;
    errorCode = outcome.errorCode;
  } catch (e) {
    success = false;
    shouldRetry = true;
    status = 'FAILED';
    errorCode = e.runtimeType.toString();
  } finally {
    await localDb?.close();
    LocalDatabaseService.resetForTesting();
    try {
      await workerChannel.invokeMethod<void>('completeBackgroundWork', <String, dynamic>{
        'success': success,
        'shouldRetry': shouldRetry,
        'status': status,
        'errorCode': errorCode,
      });
    } catch (_) {
      // Test/headless ortamında kanal yoksa sessiz çık.
    }
  }
}
