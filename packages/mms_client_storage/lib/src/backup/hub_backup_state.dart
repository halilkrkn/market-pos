/// Faz B-3 (`ADR-023`): Merkezi Hub Google Drive Yedekleme 12-Durum Makinesi.
enum HubBackupJobState {
  pending('PENDING'),
  runningSnapshot('RUNNING_SNAPSHOT'),
  snapshotReady('SNAPSHOT_READY'),
  runningEncrypt('RUNNING_ENCRYPT'),
  encryptedLocalReady('ENCRYPTED_LOCAL_READY'),
  uploading('UPLOADING'),
  verifying('VERIFYING'),
  completedUploaded('COMPLETED_UPLOADED'),
  retryPending('RETRY_PENDING'),
  failedAuth('FAILED_AUTH'),
  failedQuota('FAILED_QUOTA'),
  superseded('SUPERSEDED');

  final String wireName;
  const HubBackupJobState(this.wireName);

  bool get isTerminal =>
      this == HubBackupJobState.completedUploaded ||
      this == HubBackupJobState.superseded;

  bool get isIncompleteForRollover =>
      this == HubBackupJobState.retryPending ||
      this == HubBackupJobState.failedAuth ||
      this == HubBackupJobState.failedQuota ||
      this == HubBackupJobState.pending ||
      this == HubBackupJobState.runningSnapshot ||
      this == HubBackupJobState.snapshotReady ||
      this == HubBackupJobState.runningEncrypt ||
      this == HubBackupJobState.encryptedLocalReady ||
      this == HubBackupJobState.uploading ||
      this == HubBackupJobState.verifying;

  static HubBackupJobState fromWireName(String raw) {
    for (final v in values) {
      if (v.wireName == raw) return v;
    }
    throw ArgumentError('Bilinmeyen HubBackupJobState: $raw');
  }
}

enum HubBackupTrigger {
  initialEnable('INITIAL_ENABLE'),
  scheduledDaily('SCHEDULED_DAILY'),
  catchUp('CATCH_UP'),
  manual('MANUAL');

  final String wireName;
  const HubBackupTrigger(this.wireName);

  static HubBackupTrigger fromWireName(String raw) {
    for (final v in values) {
      if (v.wireName == raw) return v;
    }
    return HubBackupTrigger.manual;
  }
}

class HubBackupStateTransitionException implements Exception {
  final HubBackupJobState from;
  final HubBackupJobState to;

  const HubBackupStateTransitionException(this.from, this.to);

  @override
  String toString() =>
      'HubBackupStateTransitionException: Geçersiz durum geçişi ${from.wireName} -> ${to.wireName}';
}

class HubBackupStateMachine {
  const HubBackupStateMachine._();

  static final Map<HubBackupJobState, Set<HubBackupJobState>> allowedTransitions = {
    HubBackupJobState.pending: {
      HubBackupJobState.runningSnapshot,
      HubBackupJobState.retryPending,
      HubBackupJobState.superseded,
    },
    HubBackupJobState.runningSnapshot: {
      HubBackupJobState.snapshotReady,
      HubBackupJobState.retryPending,
      HubBackupJobState.superseded,
    },
    HubBackupJobState.snapshotReady: {
      HubBackupJobState.runningEncrypt,
      HubBackupJobState.retryPending,
      HubBackupJobState.superseded,
    },
    HubBackupJobState.runningEncrypt: {
      HubBackupJobState.encryptedLocalReady,
      HubBackupJobState.retryPending,
      HubBackupJobState.superseded,
    },
    HubBackupJobState.encryptedLocalReady: {
      HubBackupJobState.uploading,
      HubBackupJobState.retryPending,
      HubBackupJobState.failedAuth,
      HubBackupJobState.failedQuota,
      HubBackupJobState.superseded,
    },
    HubBackupJobState.uploading: {
      HubBackupJobState.verifying,
      HubBackupJobState.retryPending,
      HubBackupJobState.failedAuth,
      HubBackupJobState.failedQuota,
      HubBackupJobState.superseded,
    },
    HubBackupJobState.verifying: {
      HubBackupJobState.completedUploaded,
      HubBackupJobState.retryPending,
      HubBackupJobState.failedAuth,
      HubBackupJobState.failedQuota,
      HubBackupJobState.superseded,
    },
    HubBackupJobState.retryPending: {
      HubBackupJobState.pending,
      HubBackupJobState.runningSnapshot,
      HubBackupJobState.runningEncrypt,
      HubBackupJobState.uploading,
      HubBackupJobState.verifying,
      HubBackupJobState.completedUploaded,
      HubBackupJobState.failedAuth,
      HubBackupJobState.failedQuota,
      HubBackupJobState.superseded,
    },
    HubBackupJobState.failedAuth: {
      HubBackupJobState.uploading,
      HubBackupJobState.verifying,
      HubBackupJobState.retryPending,
      HubBackupJobState.superseded,
    },
    HubBackupJobState.failedQuota: {
      HubBackupJobState.uploading,
      HubBackupJobState.verifying,
      HubBackupJobState.retryPending,
      HubBackupJobState.superseded,
    },
    HubBackupJobState.completedUploaded: const {},
    HubBackupJobState.superseded: const {},
  };

  static bool canTransition(HubBackupJobState from, HubBackupJobState to) {
    if (from == to) return true;
    return allowedTransitions[from]?.contains(to) ?? false;
  }

  static void assertTransition(HubBackupJobState from, HubBackupJobState to) {
    if (!canTransition(from, to)) {
      throw HubBackupStateTransitionException(from, to);
    }
  }
}

const Object _keepField = Object();

class HubBackupJobRecord {
  final String backupId;
  final HubBackupTrigger trigger;
  final HubBackupJobState state;
  final String scheduledDateLocal; // YYYY-MM-DD
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final String? snapshotPath;
  final String? encryptedPath;
  final String? encryptedSha256;
  final int? encryptedSizeBytes;
  final String? driveSessionUri;
  final int uploadedBytes;
  final String? driveFileId;
  final int attemptCount;
  final DateTime? nextRetryAtUtc;
  final String? lastErrorCode;
  final String? lastErrorMessage;

  const HubBackupJobRecord({
    required this.backupId,
    required this.trigger,
    required this.state,
    required this.scheduledDateLocal,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.snapshotPath,
    this.encryptedPath,
    this.encryptedSha256,
    this.encryptedSizeBytes,
    this.driveSessionUri,
    this.uploadedBytes = 0,
    this.driveFileId,
    this.attemptCount = 0,
    this.nextRetryAtUtc,
    this.lastErrorCode,
    this.lastErrorMessage,
  });

  HubBackupJobRecord transitionTo(
    HubBackupJobState nextState, {
    DateTime? nowUtc,
    Object? snapshotPath = _keepField,
    Object? encryptedPath = _keepField,
    Object? encryptedSha256 = _keepField,
    Object? encryptedSizeBytes = _keepField,
    Object? driveSessionUri = _keepField,
    int? uploadedBytes,
    Object? driveFileId = _keepField,
    int? attemptCount,
    Object? nextRetryAtUtc = _keepField,
    Object? lastErrorCode = _keepField,
    Object? lastErrorMessage = _keepField,
  }) {
    HubBackupStateMachine.assertTransition(state, nextState);
    return HubBackupJobRecord(
      backupId: backupId,
      trigger: trigger,
      state: nextState,
      scheduledDateLocal: scheduledDateLocal,
      createdAtUtc: createdAtUtc,
      updatedAtUtc: (nowUtc ?? DateTime.now()).toUtc(),
      snapshotPath: identical(snapshotPath, _keepField)
          ? this.snapshotPath
          : snapshotPath as String?,
      encryptedPath: identical(encryptedPath, _keepField)
          ? this.encryptedPath
          : encryptedPath as String?,
      encryptedSha256: identical(encryptedSha256, _keepField)
          ? this.encryptedSha256
          : encryptedSha256 as String?,
      encryptedSizeBytes: identical(encryptedSizeBytes, _keepField)
          ? this.encryptedSizeBytes
          : encryptedSizeBytes as int?,
      driveSessionUri: identical(driveSessionUri, _keepField)
          ? this.driveSessionUri
          : driveSessionUri as String?,
      uploadedBytes: uploadedBytes ?? this.uploadedBytes,
      driveFileId: identical(driveFileId, _keepField)
          ? this.driveFileId
          : driveFileId as String?,
      attemptCount: attemptCount ?? this.attemptCount,
      nextRetryAtUtc: identical(nextRetryAtUtc, _keepField)
          ? this.nextRetryAtUtc
          : nextRetryAtUtc as DateTime?,
      lastErrorCode: identical(lastErrorCode, _keepField)
          ? this.lastErrorCode
          : lastErrorCode as String?,
      lastErrorMessage: identical(lastErrorMessage, _keepField)
          ? this.lastErrorMessage
          : lastErrorMessage as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'backup_id': backupId,
        'trigger': trigger.wireName,
        'state': state.wireName,
        'scheduled_date_local': scheduledDateLocal,
        'created_at_utc': createdAtUtc.toUtc().toIso8601String(),
        'updated_at_utc': updatedAtUtc.toUtc().toIso8601String(),
        'snapshot_path': snapshotPath,
        'encrypted_path': encryptedPath,
        'encrypted_sha256': encryptedSha256,
        'encrypted_size_bytes': encryptedSizeBytes,
        'drive_session_uri': driveSessionUri,
        'uploaded_bytes': uploadedBytes,
        'drive_file_id': driveFileId,
        'attempt_count': attemptCount,
        'next_retry_at_utc': nextRetryAtUtc?.toUtc().toIso8601String(),
        'last_error_code': lastErrorCode,
        'last_error_message': lastErrorMessage,
      };

  factory HubBackupJobRecord.fromJson(Map<String, dynamic> json) =>
      HubBackupJobRecord(
        backupId: json['backup_id'] as String,
        trigger: HubBackupTrigger.fromWireName(
          (json['trigger'] as String?) ?? 'MANUAL',
        ),
        state: HubBackupJobState.fromWireName(json['state'] as String),
        scheduledDateLocal: json['scheduled_date_local'] as String,
        createdAtUtc: DateTime.parse(json['created_at_utc'] as String).toUtc(),
        updatedAtUtc: DateTime.parse(json['updated_at_utc'] as String).toUtc(),
        snapshotPath: json['snapshot_path'] as String?,
        encryptedPath: json['encrypted_path'] as String?,
        encryptedSha256: json['encrypted_sha256'] as String?,
        encryptedSizeBytes: (json['encrypted_size_bytes'] as num?)?.toInt(),
        driveSessionUri: json['drive_session_uri'] as String?,
        uploadedBytes: (json['uploaded_bytes'] as num?)?.toInt() ?? 0,
        driveFileId: json['drive_file_id'] as String?,
        attemptCount: (json['attempt_count'] as num?)?.toInt() ?? 0,
        nextRetryAtUtc: json['next_retry_at_utc'] is String
            ? DateTime.parse(json['next_retry_at_utc'] as String).toUtc()
            : null,
        lastErrorCode: json['last_error_code'] as String?,
        lastErrorMessage: json['last_error_message'] as String?,
      );
}

class HubBackupScheduleConfig {
  final bool enabled;
  final int dailyHourLocal;
  final int dailyMinuteLocal;
  final bool uploadToDrive;

  const HubBackupScheduleConfig({
    this.enabled = false,
    this.dailyHourLocal = 0,
    this.dailyMinuteLocal = 0,
    this.uploadToDrive = true,
  });

  HubBackupScheduleConfig copyWith({
    bool? enabled,
    int? dailyHourLocal,
    int? dailyMinuteLocal,
    bool? uploadToDrive,
  }) =>
      HubBackupScheduleConfig(
        enabled: enabled ?? this.enabled,
        dailyHourLocal: dailyHourLocal ?? this.dailyHourLocal,
        dailyMinuteLocal: dailyMinuteLocal ?? this.dailyMinuteLocal,
        uploadToDrive: uploadToDrive ?? this.uploadToDrive,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'daily_hour_local': dailyHourLocal,
        'daily_minute_local': dailyMinuteLocal,
        'upload_to_drive': uploadToDrive,
      };

  factory HubBackupScheduleConfig.fromJson(Map<String, dynamic> json) =>
      HubBackupScheduleConfig(
        enabled: (json['enabled'] as bool?) ?? false,
        dailyHourLocal: (json['daily_hour_local'] as num?)?.toInt() ?? 0,
        dailyMinuteLocal: (json['daily_minute_local'] as num?)?.toInt() ?? 0,
        uploadToDrive: (json['upload_to_drive'] as bool?) ?? true,
      );
}
