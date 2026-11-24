import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:mms_client_storage/mms_client_storage.dart';

class HubBackupClientException implements Exception {
  final int statusCode;
  final String code;
  final String message;

  const HubBackupClientException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  bool get isOwnerRoleRequired => code == 'ERR_OWNER_ROLE_REQUIRED';

  @override
  String toString() => 'HubBackupClientException($statusCode, $code): $message';
}

class HubSchedulerLastError {
  final String code;
  final String message;
  final DateTime? atUtc;

  const HubSchedulerLastError({
    required this.code,
    required this.message,
    this.atUtc,
  });

  factory HubSchedulerLastError.fromJson(Map<String, dynamic> json) =>
      HubSchedulerLastError(
        code: (json['code'] as String?)?.trim() ?? 'ERR_HUB_BACKUP_SCHEDULER',
        message: (json['message'] as String?)?.trim() ?? '',
        atUtc: json['at_utc'] is String
            ? DateTime.tryParse(json['at_utc'] as String)?.toUtc()
            : null,
      );
}

class HubCentralBackupOverview {
  final bool oauthConnected;
  final String? accountEmail;
  final bool needsReauth;
  final bool hasRecoveryKey;
  final HubBackupScheduleConfig schedule;
  final String? lastCompletedDateLocal;
  final DateTime? lastCompletedAtUtc;
  final HubBackupJobRecord? latestJob;
  final List<HubBackupJobRecord> jobs;
  final HubSchedulerLastError? schedulerLastError;

  const HubCentralBackupOverview({
    required this.oauthConnected,
    this.accountEmail,
    this.needsReauth = false,
    required this.hasRecoveryKey,
    required this.schedule,
    this.lastCompletedDateLocal,
    this.lastCompletedAtUtc,
    this.latestJob,
    this.jobs = const [],
    this.schedulerLastError,
  });

  factory HubCentralBackupOverview.fromJson(Map<String, dynamic> json) {
    final oauth = json['oauth'] is Map
        ? Map<String, dynamic>.from(json['oauth'] as Map)
        : const <String, dynamic>{};
    final schedMap = json['schedule'] is Map
        ? Map<String, dynamic>.from(json['schedule'] as Map)
        : const <String, dynamic>{};
    final jobsRaw = (json['jobs'] as List?) ?? const [];
    final jobs = jobsRaw
        .whereType<Map>()
        .map((m) => HubBackupJobRecord.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    final latestRaw = json['latest_job'];
    final latest = latestRaw is Map
        ? HubBackupJobRecord.fromJson(Map<String, dynamic>.from(latestRaw))
        : (jobs.isNotEmpty ? jobs.first : null);
    final schedErrRaw = json['scheduler_last_error'];
    final schedErr = schedErrRaw is Map
        ? HubSchedulerLastError.fromJson(Map<String, dynamic>.from(schedErrRaw))
        : null;

    return HubCentralBackupOverview(
      oauthConnected: (oauth['connected'] as bool?) ?? false,
      accountEmail: oauth['account_email'] as String?,
      needsReauth: (oauth['needs_reauth'] as bool?) ?? false,
      hasRecoveryKey: (json['has_recovery_key'] as bool?) ?? false,
      schedule: HubBackupScheduleConfig.fromJson(schedMap),
      lastCompletedDateLocal: json['last_completed_date_local'] as String?,
      lastCompletedAtUtc: json['last_completed_at_utc'] is String
          ? DateTime.tryParse(json['last_completed_at_utc'] as String)?.toUtc()
          : null,
      latestJob: latest,
      jobs: jobs,
      schedulerLastError: schedErr,
    );
  }
}

/// Faz B-4: Master Hub merkezi Google Drive yedekleme HTTP istemcisi.
/// Tüm hassas mutasyon isteklerine benzersiz `X-MMS-Timestamp` (UTC ISO-8601)
/// ve `X-MMS-Nonce` replay koruma başlıkları ekler (`BK-031`).
class HubBackupClient {
  static final Random _secureRandom = Random.secure();

  final http.Client httpClient;
  final String Function() readHubUrl;
  final String? Function() readDeviceToken;
  final String? Function()? readAdminSecret;
  final String? tenantId;
  final String? storeId;
  final DateTime Function() clock;

  HubBackupClient({
    required this.httpClient,
    required this.readHubUrl,
    required this.readDeviceToken,
    this.readAdminSecret,
    this.tenantId,
    this.storeId,
    DateTime Function()? clock,
  }) : clock = clock ?? (() => DateTime.now().toUtc());

  static String generateNonce() {
    final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Map<String, String> buildReplayHeaders() => {
        'x-mms-timestamp': clock().toUtc().toIso8601String(),
        'x-mms-nonce': generateNonce(),
      };

  Map<String, String> _buildHeaders({bool includeReplay = false}) {
    final token = readDeviceToken();
    final adminSecret = readAdminSecret?.call();
    return {
      'content-type': 'application/json',
      if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
      if ((token == null || token.isEmpty) &&
          adminSecret != null &&
          adminSecret.isNotEmpty)
        'x-mms-admin-secret': adminSecret,
      if (tenantId != null && tenantId!.isNotEmpty) 'x-mms-tenant-id': tenantId!,
      if (storeId != null && storeId!.isNotEmpty) 'x-mms-store-id': storeId!,
      if (includeReplay) ...buildReplayHeaders(),
    };
  }

  Uri _uri(String path) {
    final base = readHubUrl().trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) {
      throw const HubBackupClientException(
        statusCode: 0,
        code: 'ERR_HUB_URL_MISSING',
        message: 'Master Hub adresi yapılandırılmamış.',
      );
    }
    return Uri.parse('$base$path');
  }

  Future<HubCentralBackupOverview> fetchStatus() async {
    final resp = await httpClient.get(
      _uri('/api/v1/backup/status'),
      headers: _buildHeaders(),
    );
    final body = _decodeOrThrow(resp);
    return HubCentralBackupOverview.fromJson(body);
  }

  /// Google Drive `MARKET MMS Yedekleri/Hub` klasöründeki yedekleri listeler (`AUD-CRIT-03`).
  Future<List<HubDriveRemoteBackup>> fetchDriveBackups() async {
    final resp = await httpClient.get(
      _uri('/api/v1/backup/drive/list'),
      headers: _buildHeaders(),
    );
    final body = _decodeOrThrow(resp);
    final rawList = (body['backups'] as List?) ?? const [];
    return rawList
        .whereType<Map>()
        .map((m) => HubDriveRemoteBackup.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<void> disconnectOAuth() async {
    final resp = await httpClient.post(
      _uri('/api/v1/backup/oauth/disconnect'),
      headers: _buildHeaders(includeReplay: true),
      body: jsonEncode(const <String, dynamic>{}),
    );
    _decodeOrThrow(resp);
  }

  Future<void> setRecoveryKey(String recoveryPassword) async {
    final resp = await httpClient.post(
      _uri('/api/v1/backup/recovery-key'),
      headers: _buildHeaders(includeReplay: true),
      body: jsonEncode({'recovery_password': recoveryPassword}),
    );
    _decodeOrThrow(resp);
  }

  Future<HubBackupScheduleConfig> configureSchedule({
    required bool enabled,
    int dailyHourLocal = 0,
    int dailyMinuteLocal = 0,
    bool uploadToDrive = true,
    String? recoveryPassword,
    bool triggerInitialIfDue = true,
  }) async {
    final resp = await httpClient.post(
      _uri('/api/v1/backup/schedule'),
      headers: _buildHeaders(includeReplay: true),
      body: jsonEncode({
        'enabled': enabled,
        'daily_hour_local': dailyHourLocal,
        'daily_minute_local': dailyMinuteLocal,
        'upload_to_drive': uploadToDrive,
        'recovery_password': ?recoveryPassword,
        'trigger_initial_if_due': triggerInitialIfDue,
      }),
    );
    final body = _decodeOrThrow(resp);
    final sched = body['schedule'];
    if (sched is Map) {
      return HubBackupScheduleConfig.fromJson(Map<String, dynamic>.from(sched));
    }
    return HubBackupScheduleConfig(enabled: enabled);
  }

  /// S2: Manuel Hub yedeği her zaman Hub'da KAYITLI kurtarma parolasıyla şifrelenir;
  /// istemci bu istekte parola göndermez (Hub parola içeren isteği reddeder).
  Future<HubBackupJobRecord> triggerManualBackup() async {
    final resp = await httpClient.post(
      _uri('/api/v1/backup/run'),
      headers: _buildHeaders(includeReplay: true),
      body: jsonEncode(const <String, dynamic>{}),
    );
    final body = _decodeOrThrow(resp);
    return HubBackupJobRecord.fromJson(body);
  }

  Future<Map<String, dynamic>> restoreFromBackup({
    String? backupId,
    String? driveFileId,
    String? packagePath,
    required String recoveryPassword,
  }) async {
    final resp = await httpClient.post(
      _uri('/api/v1/backup/restore'),
      headers: _buildHeaders(includeReplay: true),
      body: jsonEncode({
        if (backupId != null && backupId.isNotEmpty) 'backup_id': backupId,
        if (driveFileId != null && driveFileId.isNotEmpty)
          'drive_file_id': driveFileId,
        if (packagePath != null && packagePath.isNotEmpty)
          'package_path': packagePath,
        'recovery_password': recoveryPassword,
      }),
    );
    return _decodeOrThrow(resp);
  }

  static Map<String, dynamic> _decodeOrThrow(http.Response resp) {
    Map<String, dynamic> map = const {};
    if (resp.body.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map) {
          map = Map<String, dynamic>.from(decoded);
        } else {
          stderr.writeln(
            '[HubBackupClient] Beklenmeyen JSON türü (${decoded.runtimeType}, HTTP ${resp.statusCode}).',
          );
        }
      } catch (e) {
        stderr.writeln(
          '[HubBackupClient] Yanıt JSON ayrıştırılamadı (HTTP ${resp.statusCode}): ${e.runtimeType}',
        );
      }
    }
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return map;
    }
    throw HubBackupClientException(
      statusCode: resp.statusCode,
      code: (map['code'] as String?) ?? 'ERR_HTTP_${resp.statusCode}',
      message: (map['message'] as String?) ??
          'Hub yedekleme isteği başarısız oldu (HTTP ${resp.statusCode}).',
    );
  }
}
