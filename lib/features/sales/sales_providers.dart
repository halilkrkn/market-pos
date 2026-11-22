import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../diagnostics/application/system_status_notifier.dart';
import '../sync/domain/sync_coordinator_state.dart';
import '../sync/sync_providers.dart';
import 'application/sales_history_notifier.dart';
import 'application/sales_history_state.dart';
import 'data/sales_repository.dart';

final salesRepositoryProvider = Provider<SalesRepository>((ref) {
  final localDbService = ref.watch(localDatabaseServiceProvider);
  return LocalSalesRepository(localDbService);
});

final salesHistoryProvider =
    StateNotifierProvider<SalesHistoryNotifier, SalesHistoryState>((ref) {
  final repository = ref.watch(salesRepositoryProvider);
  final apiClient = ref.watch(apiClientProvider);
  final notifier = SalesHistoryNotifier(
    repository,
    apiClient.deviceId,
    onSaleMutated: () async {
      try {
        await ref.read(systemStatusProvider.notifier).refreshLocalMetrics();
      } catch (e, stack) {
        debugPrint(
          '[sales_providers] onSaleMutated refreshLocalMetrics hatası: $e\n$stack',
        );
      }
      try {
        await ref
            .read(backgroundSyncCoordinatorProvider.notifier)
            .triggerSync(reason: SyncTriggerReason.saleCommitted);
      } catch (e, stack) {
        debugPrint(
          '[sales_providers] onSaleMutated triggerSync hatası: $e\n$stack',
        );
      }
    },
  );

  // Yalnızca veri değişimlerini reaktif dinle (ref.watch yerine ref.listen):
  // Notifier yeniden oluşturulmaz, bu nedenle aktif filtreler ve tarih aralığı korunur.
  ref.listen<(int, int)>(
    systemStatusProvider.select(
      (s) => (s.localSalesCount, s.localMetricsRevision),
    ),
    (previous, next) {
      if (previous != null && previous != next) {
        notifier.loadSales(silent: true);
      }
    },
  );

  return notifier;
});
