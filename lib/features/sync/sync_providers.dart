import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

import '../../core/security/security_providers.dart';
import '../../core/security/tls_pinned_client_factory.dart';
import '../backup/drive_auth_providers.dart';
import '../diagnostics/application/system_status_notifier.dart';
import '../diagnostics/domain/system_status.dart';
import '../setup/setup_providers.dart';
import 'application/background_sync_coordinator.dart';
import 'application/drive_authorized_registry_notifier.dart';
import 'application/hub_connection_notifier.dart';
import 'data/drive_authorized_registry_store.dart';
import 'data/hub_live_drive_config_client.dart';
import 'domain/hub_connection_state.dart';
import 'domain/sync_coordinator_state.dart';

/// ADR-021: Google Drive canlı senkronizasyon gizlisi anahtarı (yedek parolasından ayrı).
const String kDriveLiveSyncSecretKey = 'drive_live_sync_secret_v1';

class _LiveDriveProvisionState {
  DateTime? lastAttemptAt;
  bool inFlight = false;
}

final _liveDriveProvisionStateProvider =
    Provider<_LiveDriveProvisionState>((ref) {
  return _LiveDriveProvisionState();
});

/// K-05 / ADR-021: Kalıcı yetkili cihaz kayıt defteri deposu sağlayıcısı.
final driveAuthorizedRegistryStoreProvider =
    Provider<DriveAuthorizedRegistryStore>((ref) {
  return InMemoryDriveAuthorizedRegistryStore();
});

/// Başlangıçta diskten yüklenen yetkili cihaz kayıt defteri (varsa).
final initialDriveAuthorizedRegistryProvider =
    Provider<DriveAuthorizedDeviceRegistry?>((ref) => null);

/// K-05 / ADR-021: Reaktif ve kalıcı yetkili cihaz kayıt defteri yöneticisi.
final driveAuthorizedRegistryNotifierProvider = StateNotifierProvider<
    DriveAuthorizedRegistryNotifier, DriveAuthorizedDeviceRegistry>((ref) {
  final store = ref.watch(driveAuthorizedRegistryStoreProvider);
  final initialRegistry = ref.watch(initialDriveAuthorizedRegistryProvider);
  final setupIdentity = ref.watch(
    setupConfigProvider.select((s) => (s.deviceId, s.tenantId, s.storeId)),
  );
  return DriveAuthorizedRegistryNotifier(
    store: store,
    initialRegistry: initialRegistry,
    localDeviceId: setupIdentity.$1,
    tenantId: setupIdentity.$2,
    storeId: setupIdentity.$3,
  );
});

/// ADR-021: Yetkili ve iptal edilmiş cihaz kayıt defteri.
final driveAuthorizedRegistryProvider =
    Provider<DriveAuthorizedDeviceRegistry>((ref) {
  return ref.watch(driveAuthorizedRegistryNotifierProvider);
});

/// K-05: Hub TLS-pinned Live Drive yapılandırma istemcisi sağlayıcısı.
final hubLiveDriveConfigClientProvider =
    Provider<HubLiveDriveConfigClient>((ref) {
  final pinnedTls = ref.watch(pinnedTlsConfigProvider);
  final httpClient = pinnedTls != null
      ? MmsPinnedTlsClientFactory.createClient(pinnedTls)
      : null;
  final client = HubLiveDriveConfigClient(httpClient: httpClient);
  ref.onDispose(client.close);
  return client;
});

/// ADR-021 & ADR-022: Hub-öncelikli Google Drive canlı senkronizasyon motoru sağlayıcısı.
///
/// Bellek içi test veritabanlarında veya platform Drive OAuth kimliği tanımlanmamışsa
/// otomatik olarak `null` döner (Hub-yalnız mod korunur).
final driveLiveSyncEngineProvider = Provider<MmsDriveLiveSyncEngine?>((ref) {
  final tokenProvider = ref.watch(driveAccessTokenProvider);
  if (tokenProvider == null) return null;

  final localDb = ref.watch(localDatabaseServiceProvider);
  if (localDb.databasePath == ':memory:') return null;

  final setup = ref.watch(setupConfigProvider);
  final secureStore = ref.watch(secureTokenStoreProvider);
  final registry = ref.watch(driveAuthorizedRegistryProvider);

  final httpClient = http.Client();
  ref.onDispose(httpClient.close);

  return MmsDriveLiveSyncEngine(
    repository: localDb.repository,
    transport: GoogleDriveLiveEnvelopeTransport(
      tokenProvider: tokenProvider,
      httpClient: httpClient,
    ),
    ledger: DriveLiveSyncLedger(
      File(p.join(localDb.dataDirectoryPath, 'drive_live_sync_ledger.json')),
    ),
    deviceRegistry: registry,
    tenantId: setup.tenantId,
    storeId: setup.storeId,
    localDeviceId: setup.deviceId,
    readLiveSyncSecret: () => secureStore.readSecret(kDriveLiveSyncSecretKey),
    operationLockFile: File(
      p.join(localDb.dataDirectoryPath, 'backups', BackupOperationLock.defaultFileName),
    ),
  );
});

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
      final driveEngine = ref.watch(driveLiveSyncEngineProvider);
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

      var providerDisposed = false;
      ref.onDispose(() {
        providerDisposed = true;
      });

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
        driveLiveSyncEngine: driveEngine,
        isDriveFallbackStandby: driveEngine != null,
        onSyncCompleted: (result) async {
          // Senkronizasyon tamamlandığında yalnızca yerel sayaçları/outbox durumunu reaktif yenile
          // Kesinlikle yeni bir HTTP /health isteği oluşturmaz (sonsuz döngüyü önler).
          await ref.read(systemStatusProvider.notifier).refreshLocalMetrics();

          if (providerDisposed ||
              localDb.databasePath == ':memory:' ||
              result == null ||
              !result.isCleanSuccess ||
              result.retriedCount > 0) {
            return;
          }

          final provisionState = ref.read(_liveDriveProvisionStateProvider);
          final now = DateTime.now();
          if (provisionState.inFlight) return;
          if (provisionState.lastAttemptAt != null &&
              now.difference(provisionState.lastAttemptAt!) <
                  const Duration(minutes: 5)) {
            return;
          }

          final hubUrl = ref.read(hubConnectionProvider).activeHubUrl;
          final token = apiClient.effectiveDeviceToken;
          if (hubUrl == null ||
              hubUrl.trim().isEmpty ||
              token == null ||
              token.trim().isEmpty) {
            return;
          }

          final setup = ref.read(setupConfigProvider);
          final configClient = ref.read(hubLiveDriveConfigClientProvider);
          final secureStore = ref.read(secureTokenStoreProvider);
          final logger = ref.read(redactingLoggerProvider);
          final registryNotifier =
              ref.read(driveAuthorizedRegistryNotifierProvider.notifier);

          provisionState.inFlight = true;
          provisionState.lastAttemptAt = now;
          try {
            final config = await configClient.fetchConfig(
              hubUrl: hubUrl,
              deviceToken: token,
              tenantId: setup.tenantId,
              storeId: setup.storeId,
            );
            if (providerDisposed || config == null) return;
            logger.registerSensitiveValue(config.liveSyncSecret);
            final existingSecret =
                await secureStore.readSecret(kDriveLiveSyncSecretKey);
            if (providerDisposed) return;
            if (existingSecret != config.liveSyncSecret) {
              await secureStore.saveSecret(
                kDriveLiveSyncSecretKey,
                config.liveSyncSecret,
              );
            }
            if (providerDisposed) return;
            await registryNotifier.applyHubSnapshot(
              devices: config.authorizedDevices,
              localDeviceId: setup.deviceId,
              tenantId: setup.tenantId,
              storeId: setup.storeId,
            );
          } catch (e) {
            debugPrint(
              '[BackgroundSyncCoordinator] Live Drive yapılandırması alınamadı: $e',
            );
          } finally {
            provisionState.inFlight = false;
          }
        },
        onHubNetworkUnreachable: (failedUrl, errorMessage) {
          ref.read(hubConnectionProvider.notifier).reportTransportUnreachable(
                failedUrl: failedUrl,
                errorMessage: errorMessage,
              );
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
