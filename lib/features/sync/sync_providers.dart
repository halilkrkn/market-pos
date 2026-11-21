import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../../core/security/tls_pinned_client_factory.dart';
import '../diagnostics/application/system_status_notifier.dart';
import '../diagnostics/domain/system_status.dart';
import '../setup/setup_providers.dart';
import 'application/background_sync_coordinator.dart';
import 'application/hub_connection_notifier.dart';
import 'domain/hub_connection_state.dart';
import 'domain/sync_coordinator_state.dart';

/// HTTP Senkronizasyon Taşıma Katmanı Sağlayıcısı (SyncTransport)
final syncTransportProvider = Provider<SyncTransport>((ref) {
  final pinnedTls = ref.watch(pinnedTlsConfigProvider);
  // ISO: Hub mağaza verisi rotalarında tenant/store başlıklarını zorunlu tutar.
  final storeIdentity = ref.watch(
    setupConfigProvider.select((s) => (s.tenantId, s.storeId)),
  );
  final transport = HttpSyncTransport.forStore(
    client: pinnedTls != null
        ? MmsPinnedTlsClientFactory.createClient(pinnedTls)
        : null,
    tenantId: storeIdentity.$1,
    storeId: storeIdentity.$2,
  );
  ref.onDispose(() => transport.close());
  return transport;
});

/// MARKET MMS - Arka Plan Senkronizasyon Koordinatörü Sağlayıcısı
final backgroundSyncCoordinatorProvider =
    StateNotifierProvider<BackgroundSyncCoordinator, SyncCoordinatorState>((
      ref,
    ) {
      final localDb = ref.watch(localDatabaseServiceProvider);
      final apiClient = ref.watch(apiClientProvider);
      final transport = ref.watch(syncTransportProvider);
      final allowLoopback = ref.watch(hubAllowLoopbackPolicyProvider);
      final autoDiscoveryEnabled = ref.watch(
        hubAutoDiscoveryLifecycleEnabledProvider,
      );

      bool isStateReadyForSync(HubConnectionState hubState) {
        if (!hubState.isInitialized || !hubState.hasActiveHubUrl) return false;
        if (hubState.phase == HubConnectionPhase.discovering) return false;
        if (autoDiscoveryEnabled &&
            hubState.phase == HubConnectionPhase.verifying) {
          return false;
        }
        return true;
      }

      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: apiClient.deviceId,
        readDeviceToken: () => apiClient.effectiveDeviceToken,
        hubUrl: apiClient.baseUrl,
        readHubUrl: () {
          final hubState = ref.read(hubConnectionProvider);
          if (!isStateReadyForSync(hubState)) return null;
          return hubState.activeHubUrl;
        },
        isHubUrlReady: () =>
            isStateReadyForSync(ref.read(hubConnectionProvider)),
        allowLoopbackHubUrl: allowLoopback,
        onSyncCompleted: (result) async {
          // Senkronizasyon tamamlandığında yalnızca yerel sayaçları/outbox durumunu reaktif yenile
          // Kesinlikle yeni bir HTTP /health isteği oluşturmaz (sonsuz döngüyü önler).
          await ref.read(systemStatusProvider.notifier).refreshLocalMetrics();
        },
        // Canlı ortamda 30 saniyelik periyodik sayaç ve lifecycle dinleyicisi etkindir
        periodicInterval: const Duration(seconds: 30),
        autoStartTimer: true,
        enableLifecycleListener: true,
      );

      // Yerel ağ veya internet bağlantısı gerçekten yeniden kurulduğunda senkronizasyonu otomatik tetikle
      ref.listen<SystemStatus>(systemStatusProvider, (previous, next) {
        // Yalnızca önceki durum gerçekten çevrimdışı veya bakımdayken (offline/draining) yeni durum online olduğunda tetikle;
        // Geçici 'checking' ara durumu bağlantı kurtarma olarak kabul edilmez.
        final wasOffline =
            previous != null &&
            (previous.backendState == BackendConnectionState.offline ||
                previous.backendState == BackendConnectionState.draining ||
                previous.backendState == BackendConnectionState.tlsPinMismatch ||
                previous.backendState == BackendConnectionState.tlsCertError);
        final isNowOnline = next.backendState == BackendConnectionState.online;

        if (wasOffline && isNowOnline) {
          coordinator.triggerSync(
            reason: SyncTriggerReason.connectivityRestored,
          );
        }
      });

      // Hub URL başlatma tamamlandığında veya çalışma anında yeni/kurtarılmış Hub URL devreye alındığında tetikle
      ref.listen<HubConnectionState>(hubConnectionProvider, (previous, next) {
        if (!isStateReadyForSync(next)) return;

        final becameInitializedWithUrl =
            (previous == null || !previous.isInitialized) && next.isInitialized;
        if (becameInitializedWithUrl) {
          coordinator.triggerSync(reason: SyncTriggerReason.startup);
          return;
        }

        final becameConnectedFirstTimeInAutoMode =
            autoDiscoveryEnabled &&
            previous != null &&
            previous.phase == HubConnectionPhase.verifying &&
            next.phase == HubConnectionPhase.connected;
        if (becameConnectedFirstTimeInAutoMode) {
          coordinator.triggerSync(reason: SyncTriggerReason.startup);
          return;
        }

        final urlChangedOrRecoveredWhileInitialized =
            previous != null &&
            previous.isInitialized &&
            next.isInitialized &&
            (previous.activeHubUrl != next.activeHubUrl ||
                ((previous.phase == HubConnectionPhase.offline ||
                        previous.phase == HubConnectionPhase.needsDiscovery ||
                        previous.phase == HubConnectionPhase.discovering) &&
                    next.phase == HubConnectionPhase.connected));
        if (urlChangedOrRecoveredWhileInitialized) {
          coordinator.triggerSync(
            reason: SyncTriggerReason.connectivityRestored,
          );
        }
      });

      // Başlangıç tetiklemesi (yalnızca Hub URL başlatıldıysa ve senkronizasyona hazırsa)
      final currentHubState = ref.read(hubConnectionProvider);
      if (isStateReadyForSync(currentHubState)) {
        coordinator.triggerSync(reason: SyncTriggerReason.startup);
      }

      return coordinator;
    });
