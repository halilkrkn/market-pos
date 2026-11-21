import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diagnostics/application/system_status_notifier.dart';
import '../diagnostics/domain/system_status.dart';
import '../sync/domain/sync_coordinator_state.dart';
import '../sync/sync_providers.dart';
import 'application/cart_notifier.dart';
import 'application/pos_preferences_notifier.dart';
import 'data/local_pos_repository.dart';
import 'domain/cart_state.dart';
import 'domain/pos_repository.dart';

/// POS özellik modülü Riverpod bağımlılık kompozisyonu.
final posRepositoryProvider = Provider<PosRepository>((ref) {
  final localDbService = ref.watch(localDatabaseServiceProvider);
  return LocalPosRepository(localDbService);
});

final posPreferencesProvider =
    StateNotifierProvider<PosPreferencesNotifier, PosPreferencesState>((ref) {
      return PosPreferencesNotifier();
    });

final cartProvider = StateNotifierProvider<CartNotifier, CartState>((ref) {
  final repository = ref.watch(posRepositoryProvider);
  final apiClient = ref.watch(apiClientProvider);

  return CartNotifier(
    repository: repository,
    readDeviceId: () => apiClient.deviceId,
    isHubOffline: () =>
        ref.read(systemStatusProvider).backendState !=
        BackendConnectionState.online,
    onSaleCommitted: () async {
      // 1. Sistem durumu yenileme hatası senkronizasyonu KESİNLİKLE engellememelidir
      try {
        await ref.read(systemStatusProvider.notifier).refreshStatus();
      } catch (e, stack) {
        debugPrint(
          '[pos_providers] onSaleCommitted refreshStatus hatası (satış kaydedildi): $e\n$stack',
        );
      }

      // 2. Senkronizasyon tetiklemesi bağımsız try-catch ile yürütülür
      try {
        await ref
            .read(backgroundSyncCoordinatorProvider.notifier)
            .triggerSync(reason: SyncTriggerReason.saleCommitted);
      } catch (e, stack) {
        debugPrint(
          '[pos_providers] onSaleCommitted triggerSync hatası (satış kaydedildi): $e\n$stack',
        );
      }
    },
  );
});
