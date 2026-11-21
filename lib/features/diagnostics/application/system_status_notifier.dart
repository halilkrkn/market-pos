import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_contracts/mms_contracts.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';
import '../../../core/security/security_providers.dart';
import '../../../core/security/tls_pinned_client_factory.dart';
import '../../../core/storage/local_database_service.dart';
import '../../setup/setup_providers.dart';
import '../../sync/application/hub_connection_notifier.dart';
import '../../sync/domain/hub_connection_state.dart';
import '../domain/system_status.dart';

/// Bağımlılık Sağlayıcıları (Riverpod Providers)
final Provider<MmsApiClient> apiClientProvider = Provider<MmsApiClient>((ref) {
  final setup = ref.watch(setupConfigProvider);
  final pinnedTls = ref.watch(pinnedTlsConfigProvider);
  final pinnedClient = pinnedTls != null
      ? MmsPinnedTlsClientFactory.createClient(pinnedTls)
      : null;
  if (pinnedClient != null) {
    ref.onDispose(pinnedClient.close);
  }

  return MmsApiClient(
    client: pinnedClient,
    readBaseUrl: () => ref.read(hubConnectionProvider).activeHubUrl,
    allowLoopback: ref.watch(hubAllowLoopbackPolicyProvider),
    deviceId: setup.deviceId,
    deviceToken: AppConstants.defaultDeviceToken.isNotEmpty
        ? AppConstants.defaultDeviceToken
        : null,
    readDeviceToken: () => ref.read(effectiveDeviceTokenProvider),
  );
});

final localDatabaseServiceProvider = Provider<LocalDatabaseService>((ref) {
  throw UnimplementedError('LocalDatabaseService must be initialized before use');
});

final systemStatusProvider =
    StateNotifierProvider<SystemStatusNotifier, SystemStatus>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final localDb = ref.watch(localDatabaseServiceProvider);
  final initialHubOverride = ref.watch(initialHubConnectionStateProvider);
  final initialBackendUrl = initialHubOverride != null
      ? (initialHubOverride.activeHubUrl ?? '')
      : apiClient.baseUrl;

  final notifier = SystemStatusNotifier(
    apiClient: apiClient,
    localDbService: localDb,
    initialStatus: SystemStatus.initial(
      backendUrl: initialBackendUrl,
      deviceId: apiClient.deviceId,
      localDbPath: localDb.databasePath,
    ),
    onHealthObserved: (checkedUrl, health) {
      return ref
          .read(hubConnectionProvider.notifier)
          .syncHealthObservation(url: checkedUrl, health: health);
    },
  );

  ref.listen<HubConnectionState>(hubConnectionProvider, (previous, next) {
    final effectiveUrl = next.isInitialized ? (next.activeHubUrl ?? '') : '';
    notifier.updateDisplayedBackendUrl(effectiveUrl);

    final urlChangedAfterInit = previous != null &&
        previous.isInitialized &&
        next.isInitialized &&
        previous.activeHubUrl != next.activeHubUrl &&
        next.hasActiveHubUrl;
    if (urlChangedAfterInit) {
      unawaited(notifier.refreshStatus());
    }
  });

  // Başlangıçta arka planda kontrol tetikle
  notifier.refreshStatus();

  return notifier;
});

/// Outbox Durum Özeti Sağlayıcısı (Reaktif, bağımsız tüketim için)
final outboxSummaryProvider = Provider<OutboxSummary>((ref) {
  return ref.watch(systemStatusProvider.select((s) => s.outboxSummary));
});

/// Sistem Durumu ve Canlılık Yöneticisi (StateNotifier)
class SystemStatusNotifier extends StateNotifier<SystemStatus> {
  final MmsApiClient apiClient;
  final LocalDatabaseService localDbService;
  final FutureOr<void> Function(
    String checkedUrl,
    CentralHealthResponse health,
  )? onHealthObserved;
  Future<void>? _activeRefreshFuture;
  bool _isIoInProgress = false;
  bool _hasSubsequentRequest = false;

  SystemStatusNotifier({
    required this.apiClient,
    required this.localDbService,
    required SystemStatus initialStatus,
    this.onHealthObserved,
  }) : super(initialStatus);

  /// Hub adresi çalışma anında güncellendiğinde gösterilen URL'yi anında senkronize eder.
  void updateDisplayedBackendUrl(String backendUrl) {
    if (!mounted || state.backendUrl == backendUrl) return;
    state = state.copyWith(backendUrl: backendUrl);
  }

  /// Sunucu ve Yerel Veritabanı Durumunu Yenile
  ///
  /// Eşzamanlı re-entrancy koruması ile çalışır; aynı anda birden fazla
  /// HTTP/DB sağlık kontrolünün paralel çalışmasını önler.
  /// Eşzamanlı çağrılar tekilleştirilir; asenkron I/O devam ederken gelen
  /// çağrılar için işlem tamamlandıktan sonra güncel durumu garanti eden
  /// tekil bir ardışık tur yürütülür.
  Future<void> refreshStatus() async {
    if (!mounted) return;

    if (_activeRefreshFuture != null) {
      if (_isIoInProgress) {
        _hasSubsequentRequest = true;
      }
      await _activeRefreshFuture;
      return;
    }

    _activeRefreshFuture = _runRefreshLoop();
    try {
      await _activeRefreshFuture;
    } finally {
      _activeRefreshFuture = null;
      _isIoInProgress = false;
      _hasSubsequentRequest = false;
    }
  }

  Future<void> _runRefreshLoop() async {
    while (mounted) {
      _hasSubsequentRequest = false;
      // İlk microtask turundan sonra asenkron I/O bayrağını aktif et
      scheduleMicrotask(() {
        _isIoInProgress = true;
      });

      await _doRefreshStatus();

      if (!_hasSubsequentRequest || !mounted) {
        break;
      }
    }
  }

  Future<void> _doRefreshStatus() async {
    // Yalnızca ilk açılışta veya bağlantı durumu henüz bilinmiyorken 'checking' rozeti gösterilir;
    // Sistem zaten online veya offline ise arkaplan kontrolü sırasında UI durumunu gereksiz titreşime sokmaz.
    if (state.backendState == BackendConnectionState.checking) {
      state = state.copyWith(
        backendState: BackendConnectionState.checking,
      );
    }

    // 1. Merkezi Sunucu Sağlık Kontrolü
    final checkedUrl = apiClient.baseUrl;
    final health = await apiClient.checkHealth();
    if (!mounted) return;
    if (onHealthObserved != null && checkedUrl.isNotEmpty) {
      try {
        await onHealthObserved!(checkedUrl, health);
      } catch (_) {}
      if (!mounted) return;
    }

    final BackendConnectionState newBackendState;
    if (health.isHealthy) {
      newBackendState = BackendConnectionState.online;
    } else if (health.status == 'DRAINING') {
      newBackendState = BackendConnectionState.draining;
    } else if (health.status == 'TLS_PIN_MISMATCH') {
      newBackendState = BackendConnectionState.tlsPinMismatch;
    } else if (health.status == 'TLS_CERT_ERROR') {
      newBackendState = BackendConnectionState.tlsCertError;
    } else {
      newBackendState = BackendConnectionState.offline;
    }

    // 2. Yerel Veritabanı Metrikleri
    OutboxSummary outboxSummary = OutboxSummary.empty();
    int pendingOutbox = 0;
    int localSales = 0;
    int localProducts = 0;
    LocalDatabaseState dbState = LocalDatabaseState.ready;
    String? dbError;

    try {
      outboxSummary = await localDbService.getOutboxSummary();
      pendingOutbox = await localDbService.getPendingOutboxCount();
      localSales = await localDbService.getLocalSalesCount();
      localProducts = await localDbService.getLocalProductsCount();
    } catch (e) {
      dbState = LocalDatabaseState.error;
      dbError = 'Yerel veritabanı okuma hatası: $e';
    }

    if (!mounted) return;

    state = state.copyWith(
      backendState: newBackendState,
      localDbState: dbState,
      backendUrl: checkedUrl,
      backendLatencyMs: health.latencyMs,
      backendSqliteVersion: health.sqliteVersion,
      outboxSummary: outboxSummary,
      pendingOutboxCount: pendingOutbox,
      localSalesCount: localSales,
      localProductsCount: localProducts,
      localMetricsRevision: state.localMetricsRevision + 1,
      lastChecked: DateTime.now(),
      errorMessage: health.errorMessage ?? dbError,
    );
  }

  /// Yalnızca Yerel Drift SQLite Metriklerini Yenile (Outbox, Satışlar, Ürünler)
  ///
  /// Senkronizasyon tamamlandığında çağrılır.
  /// Kesinlikle yeni bir HTTP /health isteği OLUŞTURMAZ; backendState durumuna dokunmaz.
  Future<void> refreshLocalMetrics() async {
    if (!mounted) return;

    OutboxSummary outboxSummary = OutboxSummary.empty();
    int pendingOutbox = 0;
    int localSales = 0;
    int localProducts = 0;
    LocalDatabaseState dbState = LocalDatabaseState.ready;
    String? dbError;

    try {
      outboxSummary = await localDbService.getOutboxSummary();
      pendingOutbox = await localDbService.getPendingOutboxCount();
      localSales = await localDbService.getLocalSalesCount();
      localProducts = await localDbService.getLocalProductsCount();
    } catch (e) {
      dbState = LocalDatabaseState.error;
      dbError = 'Yerel veritabanı okuma hatası: $e';
    }

    if (!mounted) return;

    state = state.copyWith(
      localDbState: dbState,
      outboxSummary: outboxSummary,
      pendingOutboxCount: pendingOutbox,
      localSalesCount: localSales,
      localProductsCount: localProducts,
      localMetricsRevision: state.localMetricsRevision + 1,
      errorMessage: dbError ?? state.errorMessage,
    );
  }
}
