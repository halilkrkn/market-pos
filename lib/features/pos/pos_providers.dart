import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diagnostics/application/system_status_notifier.dart';
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
    onSaleCommitted: () =>
        ref.read(systemStatusProvider.notifier).refreshStatus(),
  );
});

