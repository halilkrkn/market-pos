import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../diagnostics/application/system_status_notifier.dart';
import '../sync/domain/sync_coordinator_state.dart';
import '../sync/sync_providers.dart';
import 'application/catalog_notifier.dart';
import 'application/catalog_state.dart';
import 'data/catalog_repository.dart';
import 'data/open_food_facts_client.dart';
import 'domain/external_product_lookup_service.dart';

final externalProductLookupServiceProvider =
    Provider<ExternalProductLookupService>((ref) {
  final client = OpenFoodFactsClient();
  ref.onDispose(client.dispose);
  return client;
});

/// Widget testlerinde ağ görseli indirmeden güvenli önizleme sağlamak için opsiyonel sağlayıcı.
final externalProductImageBuilderProvider =
    Provider<Widget Function(BuildContext, String)?>(
  (ref) => null,
);

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  final localDbService = ref.watch(localDatabaseServiceProvider);
  return LocalCatalogRepository(localDbService);
});

final catalogProvider =
    StateNotifierProvider<CatalogNotifier, CatalogState>((ref) {
  final repository = ref.watch(catalogRepositoryProvider);
  final apiClient = ref.watch(apiClientProvider);
  final syncCoordinator = ref.watch(backgroundSyncCoordinatorProvider.notifier);
  return CatalogNotifier(
    repository,
    apiClient.deviceId,
    onProductChanged: () {
      syncCoordinator.triggerSync(reason: SyncTriggerReason.productCommitted);
    },
  );
});
