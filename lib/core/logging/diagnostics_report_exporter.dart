import 'dart:convert';
import 'dart:io';

import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

import '../../features/diagnostics/domain/system_status.dart';
import '../../features/setup/domain/app_setup_config.dart';
import '../../features/sync/domain/hub_connection_state.dart';
import '../../features/sync/domain/sync_coordinator_state.dart';
import '../constants/app_constants.dart';
import 'redacting_logger.dart';

/// İstemci tanı ve operasyon verilerini sır içermeyen JSON raporu olarak dışa aktarır.
class DiagnosticsReportExporter {
  static Future<File> exportToDirectory({
    required Directory outputDir,
    required RedactingLogger logger,
    required AppSetupConfig setupConfig,
    required SystemStatus systemStatus,
    required HubConnectionState hubState,
    required SyncCoordinatorState syncState,
    OutboxSummary? outboxSummary,
    String? tokenBackendLabel,
    bool hasStoredToken = false,
  }) async {
    if (!outputDir.existsSync()) {
      outputDir.createSync(recursive: true);
    }

    final jsonString = buildRedactedReportJson(
      logger: logger,
      setupConfig: setupConfig,
      systemStatus: systemStatus,
      hubState: hubState,
      syncState: syncState,
      outboxSummary: outboxSummary,
      tokenBackendLabel: tokenBackendLabel,
      hasStoredToken: hasStoredToken,
    );

    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('-', '')
        .replaceAll('.', '_');
    final file = File(p.join(outputDir.path, 'mms_diagnostics_$stamp.json'));
    await file.writeAsString(jsonString, flush: true);
    return file;
  }

  static String buildRedactedReportJson({
    required RedactingLogger logger,
    required AppSetupConfig setupConfig,
    required SystemStatus systemStatus,
    required HubConnectionState hubState,
    required SyncCoordinatorState syncState,
    OutboxSummary? outboxSummary,
    String? tokenBackendLabel,
    bool hasStoredToken = false,
  }) {
    final safeHubUrl = hubState.activeHubUrl == null
        ? null
        : logger.redact(hubState.activeHubUrl!);
    final safeSystemError = systemStatus.errorMessage == null
        ? null
        : logger.redact(systemStatus.errorMessage!);
    final safeSyncError = syncState.errorMessage == null
        ? null
        : logger.redact(syncState.errorMessage!);

    final payload = <String, dynamic>{
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'app_version': AppConstants.appVersion,
      'platform': Platform.operatingSystem,
      'setup': <String, dynamic>{
        'is_setup_completed': setupConfig.isSetupCompleted,
        'tenant_id': setupConfig.tenantId,
        'store_id': setupConfig.storeId,
        'store_name': setupConfig.storeName,
        'device_id': setupConfig.deviceId,
        'device_name': setupConfig.deviceName,
        'tls_pinning_enabled': setupConfig.tlsPinningEnabled,
        'pinned_ca_sha256': setupConfig.normalizedPinSha256,
      },
      'security': <String, dynamic>{
        'token_backend': tokenBackendLabel ?? 'unknown',
        'has_stored_token': hasStoredToken,
      },
      'hub': <String, dynamic>{
        'phase': hubState.phase.name,
        'is_initialized': hubState.isInitialized,
        'active_url': safeHubUrl,
        'url_source': hubState.source?.name,
        'hub_id': hubState.hubId,
        'last_verified_at': hubState.lastVerifiedAt?.toUtc().toIso8601String(),
        'last_error': hubState.errorMessage == null
            ? null
            : logger.redact(hubState.errorMessage!),
      },
      'system_status': <String, dynamic>{
        'backend_state': systemStatus.backendState.name,
        'backend_sqlite_version': systemStatus.backendSqliteVersion,
        'backend_latency_ms': systemStatus.backendLatencyMs,
        'local_sales_count': systemStatus.localSalesCount,
        'local_products_count': systemStatus.localProductsCount,
        'pending_outbox_count': systemStatus.pendingOutboxCount,
        'last_checked': systemStatus.lastChecked.toUtc().toIso8601String(),
        'error_message': safeSystemError,
      },
      'sync': <String, dynamic>{
        'status': syncState.status.name,
        'is_syncing': syncState.isSyncing,
        'has_pending_trailing_sync': syncState.hasPendingTrailingSync,
        'last_sync_time': syncState.lastSyncTime?.toUtc().toIso8601String(),
        'last_error': safeSyncError,
        if (outboxSummary != null)
          'outbox': <String, dynamic>{
            'pending': outboxSummary.pending,
            'retry': outboxSummary.retry,
            'in_progress': outboxSummary.inProgress,
            'failed_permanent': outboxSummary.failedPermanent,
            'total_unsynced': outboxSummary.totalUnsynced,
          },
      },
      'logs': logger.entries.map((e) => e.toJson()).toList(growable: false),
    };

    return logger.redact(const JsonEncoder.withIndent('  ').convert(payload));
  }
}
