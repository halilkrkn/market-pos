import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'backup_operation_lock.dart';
import 'backup_retention_policy.dart';
import 'database_backup_engine.dart';

/// Faz 3 / 7D — Zamanlanmış yerel yedekleme.
///
/// Windows Hub (merkezi `market_master.db`) ve istemciler (yerel DB) aynı iş
/// kurallarını kullanır. Altyapıdan (Timer, dosya sistemi, şifreleme) bağımsız
/// saf karar mantığı [BackupSchedulePolicy] içindedir.

/// Yedeğin neden alındığı.
enum BackupTrigger {
  scheduled('SCHEDULED'),
  manual('MANUAL');

  final String value;
  const BackupTrigger(this.value);

  static BackupTrigger fromString(String? raw) =>
      BackupTrigger.values.firstWhere((t) => t.value == raw, orElse: () => BackupTrigger.manual);
}

/// Yedekleme sıklığı ve saklama politikası.
class BackupSchedulePolicy {
  /// İki başarılı yedek arasındaki süre. `Duration.zero` → zamanlama kapalı.
  final Duration interval;

  /// Başarısız denemeden sonra tekrar denemeden önce beklenecek süre
  /// (disk dolu / USB çıkarılmış gibi durumlarda sürekli denemeyi engeller).
  final Duration failureRetryDelay;

  final RetentionPolicy retention;

  const BackupSchedulePolicy({
    required this.interval,
    this.failureRetryDelay = const Duration(minutes: 30),
    this.retention = const RetentionPolicy(),
  });

  static const disabled = BackupSchedulePolicy(interval: Duration.zero);

  bool get enabled => interval > Duration.zero;

  bool isDue({required BackupScheduleState state, required DateTime now}) {
    if (!enabled) return false;
    final lastFailure = state.lastFailureAt;
    if (lastFailure != null &&
        (state.lastSuccessAt == null || lastFailure.isAfter(state.lastSuccessAt!)) &&
        now.difference(lastFailure) < failureRetryDelay) {
      return false;
    }
    final lastSuccess = state.lastSuccessAt;
    if (lastSuccess == null) return true;
    return now.difference(lastSuccess) >= interval;
  }

  /// Son başarılı yedek, beklenen aralığın %25 fazlasına ulaştıysa gecikmiş sayılır.
  bool isOverdue({required BackupScheduleState state, required DateTime now}) {
    if (!enabled) return false;
    final lastSuccess = state.lastSuccessAt;
    if (lastSuccess == null) return state.lastFailureAt != null;
    return now.difference(lastSuccess) >= interval * 1.25;
  }

  DateTime? nextDueAt(BackupScheduleState state) {
    if (!enabled) return null;
    final last = state.lastSuccessAt;
    return last?.add(interval);
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'interval_minutes': interval.inMinutes,
        'daily_retention_days': retention.dailyRetentionDays,
        'monthly_retention_months': retention.monthlyRetentionMonths,
      };
}

/// Tek bir yedekleme denemesinin kaydı (geçmiş listesi).
class BackupRunRecord {
  final DateTime startedAt;
  final DateTime finishedAt;
  final BackupTrigger trigger;
  final bool success;
  final String? backupId;
  final int? sizeBytes;
  final int prunedCount;
  final String? errorCode;
  final String? errorMessage;

  /// Yerel yedek başarılı ancak sonraki adım (ör. Google Drive yüklemesi) başarısız.
  final String? postProcessError;

  const BackupRunRecord({
    required this.startedAt,
    required this.finishedAt,
    required this.trigger,
    required this.success,
    this.backupId,
    this.sizeBytes,
    this.prunedCount = 0,
    this.errorCode,
    this.errorMessage,
    this.postProcessError,
  });

  Map<String, dynamic> toJson() => {
        'started_at': startedAt.toUtc().toIso8601String(),
        'finished_at': finishedAt.toUtc().toIso8601String(),
        'trigger': trigger.value,
        'success': success,
        'backup_id': backupId,
        'size_bytes': sizeBytes,
        'pruned_count': prunedCount,
        'error_code': errorCode,
        'error_message': errorMessage,
        'post_process_error': postProcessError,
      };

  factory BackupRunRecord.fromJson(Map<String, dynamic> json) => BackupRunRecord(
        startedAt: DateTime.parse(json['started_at'] as String),
        finishedAt: DateTime.parse(json['finished_at'] as String),
        trigger: BackupTrigger.fromString(json['trigger'] as String?),
        success: json['success'] as bool,
        backupId: json['backup_id'] as String?,
        sizeBytes: json['size_bytes'] as int?,
        prunedCount: (json['pruned_count'] as int?) ?? 0,
        errorCode: json['error_code'] as String?,
        errorMessage: json['error_message'] as String?,
        postProcessError: json['post_process_error'] as String?,
      );
}

const Object _keep = Object();

/// Zamanlayıcının kalıcı durumu (son başarı/hata ve geçmiş).
class BackupScheduleState {
  static const int maxHistory = 30;

  final DateTime? lastSuccessAt;
  final DateTime? lastFailureAt;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final int consecutiveFailures;

  /// En yeni kayıt başta.
  final List<BackupRunRecord> history;

  const BackupScheduleState({
    this.lastSuccessAt,
    this.lastFailureAt,
    this.lastErrorCode,
    this.lastErrorMessage,
    this.consecutiveFailures = 0,
    this.history = const [],
  });

  static const empty = BackupScheduleState();

  BackupScheduleState copyWith({
    Object? lastSuccessAt = _keep,
    Object? lastFailureAt = _keep,
    Object? lastErrorCode = _keep,
    Object? lastErrorMessage = _keep,
    int? consecutiveFailures,
    List<BackupRunRecord>? history,
  }) =>
      BackupScheduleState(
        lastSuccessAt: identical(lastSuccessAt, _keep) ? this.lastSuccessAt : lastSuccessAt as DateTime?,
        lastFailureAt: identical(lastFailureAt, _keep) ? this.lastFailureAt : lastFailureAt as DateTime?,
        lastErrorCode: identical(lastErrorCode, _keep) ? this.lastErrorCode : lastErrorCode as String?,
        lastErrorMessage:
            identical(lastErrorMessage, _keep) ? this.lastErrorMessage : lastErrorMessage as String?,
        consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
        history: history ?? this.history,
      );

  BackupScheduleState withRecord(BackupRunRecord record) {
    final nextHistory = [record, ...history];
    final capped = nextHistory.length > maxHistory ? nextHistory.sublist(0, maxHistory) : nextHistory;
    if (record.success) {
      return copyWith(
        lastSuccessAt: record.finishedAt,
        lastErrorCode: null,
        lastErrorMessage: null,
        consecutiveFailures: 0,
        history: capped,
      );
    }
    return copyWith(
      lastFailureAt: record.finishedAt,
      lastErrorCode: record.errorCode,
      lastErrorMessage: record.errorMessage,
      consecutiveFailures: consecutiveFailures + 1,
      history: capped,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'last_success_at': lastSuccessAt?.toUtc().toIso8601String(),
        'last_failure_at': lastFailureAt?.toUtc().toIso8601String(),
        'last_error_code': lastErrorCode,
        'last_error_message': lastErrorMessage,
        'consecutive_failures': consecutiveFailures,
        'history': history.map((r) => r.toJson()).toList(),
      };

  factory BackupScheduleState.fromJson(Map<String, dynamic> json) {
    DateTime? ts(Object? raw) => raw is String ? DateTime.parse(raw) : null;
    return BackupScheduleState(
      lastSuccessAt: ts(json['last_success_at']),
      lastFailureAt: ts(json['last_failure_at']),
      lastErrorCode: json['last_error_code'] as String?,
      lastErrorMessage: json['last_error_message'] as String?,
      consecutiveFailures: (json['consecutive_failures'] as int?) ?? 0,
      history: ((json['history'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => BackupRunRecord.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
    );
  }
}

/// Zamanlayıcı durumunu JSON dosyasında atomik (tmp + flush + rename) saklar.
/// Veritabanı şemasına dokunmaz (migration gerektirmez).
class BackupScheduleStateStore {
  final File file;

  BackupScheduleStateStore(this.file);

  Future<BackupScheduleState> load() async {
    if (!await file.exists()) return BackupScheduleState.empty;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) throw const FormatException('Kök nesne değil');
      return BackupScheduleState.fromJson(Map<String, dynamic>.from(decoded));
    } on FormatException catch (e) {
      // Bozuk durum dosyası sessizce silinmez: inceleme için karantinaya alınır.
      final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
      final quarantine = '${file.path}.corrupt_$stamp';
      try {
        await file.rename(quarantine);
      } on FileSystemException catch (renameErr) {
        stderr.writeln('[BackupSchedule] Bozuk durum dosyası karantinaya alınamadı: ${renameErr.message}');
      }
      stderr.writeln('[BackupSchedule] Durum dosyası bozuk (${e.message}); $quarantine olarak saklandı.');
      return BackupScheduleState.empty;
    } on TypeError catch (e) {
      stderr.writeln('[BackupSchedule] Durum dosyası beklenmeyen biçimde: $e');
      return BackupScheduleState.empty;
    }
  }

  Future<void> save(BackupScheduleState state) async {
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(state.toJson()), flush: true);
    await tmp.rename(file.path);
  }
}

/// Yedekleme hatalarını kullanıcıya gösterilebilir sabit kodlara çevirir.
class BackupFailureClassifier {
  const BackupFailureClassifier._();

  // Windows: ERROR_HANDLE_DISK_FULL=39, ERROR_DISK_FULL=112. POSIX: ENOSPC=28.
  static const _diskFullCodes = {39, 112};
  // Windows: ERROR_PATH_NOT_FOUND=3, ERROR_NOT_READY=21, ERROR_DEV_NOT_EXIST=55,
  // ERROR_DEVICE_NOT_CONNECTED=1167. POSIX: ENOENT=2, ENXIO=6, ENODEV=19, EIO=5.
  static const _unavailableCodes = {3, 21, 55, 1167};

  static String codeFor(Object error) {
    if (error is BackupException) return error.code;
    if (error is FileSystemException) {
      final os = error.osError?.errorCode;
      if (os != null) {
        if (_diskFullCodes.contains(os) || (!Platform.isWindows && os == 28)) return 'ERR_DISK_FULL';
        if (_unavailableCodes.contains(os) || (!Platform.isWindows && {2, 5, 6, 19}.contains(os))) {
          return 'ERR_TARGET_UNAVAILABLE';
        }
        if (os == 5 && Platform.isWindows) return 'ERR_ACCESS_DENIED';
      }
      return 'ERR_FILESYSTEM';
    }
    return 'ERR_BACKUP_FAILED';
  }

  static String messageFor(String code, Object error) {
    switch (code) {
      case 'ERR_DISK_FULL':
        return 'Yedek hedefinde yeterli boş alan yok. Disk/USB alanını boşaltın; yarım yedek geçerli sayılmadı.';
      case 'ERR_TARGET_UNAVAILABLE':
        return 'Yedek hedefi erişilemiyor (USB çıkarılmış veya klasör yok). Hedefi kontrol edin.';
      case 'ERR_ACCESS_DENIED':
        return 'Yedek hedefine yazma izni yok.';
      default:
        return error is BackupException ? error.message : 'Yedekleme başarısız: $error';
    }
  }
}

/// Zamanı gelen yedeği alır, saklama politikasını uygular ve sonucu kalıcı kaydeder.
/// Tek seferde yalnızca bir yedek çalışır (single-flight).
class ScheduledBackupRunner {
  final BackupSchedulePolicy Function() readPolicy;
  final BackupScheduleStateStore stateStore;
  final Future<BackupResult> Function() createBackup;

  /// Saklama politikası temizliği; silinen yedek kimliklerini döner.
  final Future<List<String>> Function()? pruneExpired;

  /// Başarılı yerel yedek sonrası isteğe bağlı adım (ör. şifreli dosyanın Drive'a
  /// yüklenmesi). Hatası yerel yedeği başarısız yapmaz.
  final Future<void> Function(BackupResult result)? afterSuccess;
  final DateTime Function() clock;

  Future<BackupRunRecord?>? _inFlight;

  ScheduledBackupRunner({
    required this.readPolicy,
    required this.stateStore,
    required this.createBackup,
    this.pruneExpired,
    this.afterSuccess,
    DateTime Function()? clock,
  }) : clock = clock ?? (() => DateTime.now().toUtc());

  bool get isRunning => _inFlight != null;

  /// Zamanı geldiyse yedek alır. Başka bir yedek/restore işlemi kilidi tutuyorsa
  /// ([BackupOperationLock.busyErrorCode]) tur hata KAYDEDİLMEDEN atlanır ve `null`
  /// döner; böylece restore sırasında yanıltıcı hata ve yeniden deneme gecikmesi oluşmaz.
  Future<BackupRunRecord?> runIfDue() async {
    final active = _inFlight;
    if (active != null) return active;
    final state = await stateStore.load();
    if (!readPolicy().isDue(state: state, now: clock())) return null;
    return _start(BackupTrigger.scheduled, skipWhenBusy: true);
  }

  Future<BackupRunRecord> runNow({required BackupTrigger trigger}) async {
    final active = _inFlight;
    if (active != null) {
      final joined = await active;
      if (joined != null) return joined;
    }
    return (await _start(trigger, skipWhenBusy: false))!;
  }

  Future<BackupRunRecord?> _start(BackupTrigger trigger, {required bool skipWhenBusy}) {
    final future = _run(trigger, skipWhenBusy: skipWhenBusy);
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  Future<BackupRunRecord?> _run(BackupTrigger trigger, {required bool skipWhenBusy}) async {
    final startedAt = clock();
    BackupRunRecord record;
    try {
      final result = await createBackup();
      var pruned = 0;
      String? postError;
      try {
        if (pruneExpired != null) pruned = (await pruneExpired!()).length;
      } catch (e) {
        postError = 'Saklama politikası temizliği başarısız: $e';
      }
      try {
        if (afterSuccess != null) await afterSuccess!(result);
      } catch (e) {
        postError = [if (postError != null) postError, 'Uzak yedek adımı başarısız: $e'].join(' | ');
      }
      record = BackupRunRecord(
        startedAt: startedAt,
        finishedAt: clock(),
        trigger: trigger,
        success: true,
        backupId: result.backupId,
        sizeBytes: result.encryptedSizeBytes,
        prunedCount: pruned,
        postProcessError: postError,
      );
    } catch (e) {
      final code = BackupFailureClassifier.codeFor(e);
      if (skipWhenBusy && code == BackupOperationLock.busyErrorCode) {
        stderr.writeln('[BackupSchedule] Başka bir yedek/restore işlemi sürüyor; zamanlanmış tur atlandı.');
        return null;
      }
      record = BackupRunRecord(
        startedAt: startedAt,
        finishedAt: clock(),
        trigger: trigger,
        success: false,
        errorCode: code,
        errorMessage: BackupFailureClassifier.messageFor(code, e),
      );
    }

    final state = await stateStore.load();
    await stateStore.save(state.withRecord(record));
    return record;
  }
}

/// Belirli aralıklarla [ScheduledBackupRunner.runIfDue] çağıran zamanlayıcı.
class BackupScheduler {
  final ScheduledBackupRunner runner;
  final Duration checkInterval;
  final void Function(BackupRunRecord record)? onRun;
  Timer? _timer;

  BackupScheduler({
    required this.runner,
    this.checkInterval = const Duration(minutes: 5),
    this.onRun,
  });

  bool get isActive => _timer != null;

  void start({bool runImmediately = true}) {
    if (_timer != null) return;
    _timer = Timer.periodic(checkInterval, (_) => _tick());
    if (runImmediately) _tick();
  }

  Future<void> _tick() async {
    try {
      final record = await runner.runIfDue();
      if (record != null) onRun?.call(record);
    } catch (e) {
      // runIfDue hatalarını kendi içinde kaydeder; buraya yalnızca durum dosyası
      // yazılamadığında düşülür. Zamanlayıcı durmaz, bir sonraki turda tekrar dener.
      stderr.writeln('[BackupScheduler] Zamanlanmış yedek kontrolü başarısız: $e');
    }
  }

  /// Zamanlayıcıyı durdurur ve devam eden yedeğin bitmesini bekler
  /// (servis kapanırken DB yedek ortasında kapatılmaz).
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final active = runner._inFlight;
    if (active != null) {
      try {
        await active;
      } catch (e) {
        stderr.writeln('[BackupScheduler] Kapanış sırasında bekleyen yedek hatayla bitti: $e');
      }
    }
  }
}
