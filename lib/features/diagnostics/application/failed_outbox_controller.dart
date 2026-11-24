import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/redacting_logger.dart';
import '../../../core/security/security_providers.dart';
import '../../../core/storage/local_database_service.dart';
import '../../sync/domain/sync_coordinator_state.dart';
import '../../sync/sync_providers.dart';
import '../domain/failed_outbox_item.dart';
import 'system_status_notifier.dart';

/// Kalıcı Outbox kuyruk hatalarını yükleyen ve güvenli yeniden deneme uygulayan
/// application servisi (`AUD-MED-06`: presentation katmanını DB'den ayırır).
class FailedOutboxService {
  final LocalDatabaseService? dbService;
  final RedactingLogger logger;
  final Future<void> Function() refreshMetrics;
  final Future<void> Function() triggerManualSync;

  const FailedOutboxService({
    required this.dbService,
    required this.logger,
    required this.refreshMetrics,
    required this.triggerManualSync,
  });

  Future<List<FailedOutboxItem>?> loadFailedOperations(String deviceId) async {
    final cleanDeviceId = deviceId.trim();
    if (dbService == null || cleanDeviceId.isEmpty) {
      return null;
    }
    try {
      final ops =
          await dbService!.repository.getFailedPermanentOperations(cleanDeviceId);
      return ops
          .map(
            (op) => FailedOutboxItem(
              operationId: op.operationId,
              operationType: op.operationType,
              clientSeq: op.clientSeq,
              lastError: op.lastError,
            ),
          )
          .toList(growable: false);
    } catch (e) {
      logger.warning(
        'diagnostics',
        'Kalıcı hata listesi yüklenemedi: ${e.runtimeType}',
      );
      rethrow;
    }
  }

  Future<void> retryOperation(String operationId) async {
    final service = dbService;
    if (service == null) {
      throw StateError('Yerel veritabanı servisi kullanılamıyor.');
    }
    await service.repository.retryFailedPermanentOperation(operationId);
    await refreshMetrics();
    await triggerManualSync();
  }
}

final failedOutboxServiceProvider = Provider<FailedOutboxService>((ref) {
  final logger = ref.watch(redactingLoggerProvider);
  LocalDatabaseService? dbService;
  try {
    dbService = ref.watch(localDatabaseServiceProvider);
  } catch (e) {
    logger.warning(
      'diagnostics',
      'LocalDatabaseService sağlayıcısı henüz hazır değil: ${e.runtimeType}',
    );
    dbService = null;
  }

  return FailedOutboxService(
    dbService: dbService,
    logger: logger,
    refreshMetrics: () =>
        ref.read(systemStatusProvider.notifier).refreshLocalMetrics(),
    triggerManualSync: () => ref
        .read(backgroundSyncCoordinatorProvider.notifier)
        .triggerSync(reason: SyncTriggerReason.manual),
  );
});
