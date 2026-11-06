import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/local_database_service.dart';
import '../domain/system_status.dart';

/// Bağımlılık Sağlayıcıları (Riverpod Providers)
final apiClientProvider = Provider<MmsApiClient>((ref) {
  return MmsApiClient(
    baseUrl: AppConstants.defaultBackendBaseUrl,
    deviceId: AppConstants.defaultDeviceId,
  );
});

final localDatabaseServiceProvider = Provider<LocalDatabaseService>((ref) {
  throw UnimplementedError('LocalDatabaseService must be initialized before use');
});

final systemStatusProvider =
    StateNotifierProvider<SystemStatusNotifier, SystemStatus>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final localDb = ref.watch(localDatabaseServiceProvider);

  final notifier = SystemStatusNotifier(
    apiClient: apiClient,
    localDbService: localDb,
    initialStatus: SystemStatus.initial(
      backendUrl: apiClient.baseUrl,
      deviceId: apiClient.deviceId,
      localDbPath: localDb.databasePath,
    ),
  );

  // Başlangıçta arka planda kontrol tetikle
  notifier.refreshStatus();

  return notifier;
});

/// Sistem Durumu ve Canlılık Yöneticisi (StateNotifier)
class SystemStatusNotifier extends StateNotifier<SystemStatus> {
  final MmsApiClient apiClient;
  final LocalDatabaseService localDbService;

  SystemStatusNotifier({
    required this.apiClient,
    required this.localDbService,
    required SystemStatus initialStatus,
  }) : super(initialStatus);

  /// Sunucu ve Yerel Veritabanı Durumunu Yenile
  Future<void> refreshStatus() async {
    state = state.copyWith(
      backendState: BackendConnectionState.checking,
    );

    // 1. Merkezi Sunucu Sağlık Kontrolü
    final health = await apiClient.checkHealth();

    final BackendConnectionState newBackendState;
    if (health.isHealthy) {
      newBackendState = BackendConnectionState.online;
    } else if (health.status == 'DRAINING') {
      newBackendState = BackendConnectionState.draining;
    } else {
      newBackendState = BackendConnectionState.offline;
    }

    // 2. Yerel Veritabanı Metrikleri
    int pendingOutbox = 0;
    int localSales = 0;
    int localProducts = 0;
    LocalDatabaseState dbState = LocalDatabaseState.ready;
    String? dbError;

    try {
      pendingOutbox = await localDbService.getPendingOutboxCount();
      localSales = await localDbService.getLocalSalesCount();
      localProducts = await localDbService.getLocalProductsCount();
    } catch (e) {
      dbState = LocalDatabaseState.error;
      dbError = 'Yerel veritabanı okuma hatası: $e';
    }

    state = state.copyWith(
      backendState: newBackendState,
      localDbState: dbState,
      backendLatencyMs: health.latencyMs,
      backendSqliteVersion: health.sqliteVersion,
      pendingOutboxCount: pendingOutbox,
      localSalesCount: localSales,
      localProductsCount: localProducts,
      lastChecked: DateTime.now(),
      errorMessage: health.errorMessage ?? dbError,
    );
  }
}
