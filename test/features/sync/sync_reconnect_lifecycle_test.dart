import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/core/network/api_client.dart';
import 'package:market_pos/core/network/api_response.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:market_pos/features/diagnostics/domain/system_status.dart';
import 'package:market_pos/features/sync/domain/sync_coordinator_state.dart';
import 'package:market_pos/features/sync/sync_providers.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

class _MockMmsApiClient extends Fake implements MmsApiClient {
  int healthCallCount = 0;
  CentralHealthResponse nextHealthResponse;

  _MockMmsApiClient({required this.nextHealthResponse});

  @override
  String get baseUrl => 'http://127.0.0.1:8945';
  @override
  String get deviceId => 'POS-WIN-01';
  @override
  String? get deviceToken => 'token_test_123';

  @override
  Future<CentralHealthResponse> checkHealth() async {
    healthCallCount++;
    return nextHealthResponse;
  }
}

class _MockSyncTransport extends Fake implements SyncTransport {
  int sendBatchCount = 0;

  @override
  Future<SyncResponse> postSale({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    sendBatchCount++;
    return const SyncResponse(
      statusCode: 200,
      body: '{"status":"COMMITTED"}',
    );
  }

  @override
  void close() {}
}

void main() {
  late LocalDatabaseService localDb;

  setUpAll(() async {
    localDb = LocalDatabaseService.forTesting(
      NativeDatabase.memory(),
      path: ':memory:',
    );
  });

  tearDownAll(() async {
    await localDb.close();
    await LocalDatabaseService.closeActive();
    LocalDatabaseService.resetForTesting();
  });

  group('Sync & Health Reconnection Lifecycle Testleri', () {
    test('1. checking -> online geçişi sync TETİKLEMEMELİDİR (Flickering engeli)', () async {
      final mockClient = _MockMmsApiClient(
        nextHealthResponse: CentralHealthResponse(
          isHealthy: true,
          status: 'UP',
          service: 'MARKET_MMS_HUB',
          sqliteVersion: 'masked',
          latencyMs: 15,
          checkedAt: DateTime.now(),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          localDatabaseServiceProvider.overrideWithValue(localDb),
          apiClientProvider.overrideWithValue(mockClient),
          syncTransportProvider.overrideWithValue(_MockSyncTransport()),
        ],
      );

      // backgroundSyncCoordinatorProvider dinleyicisini başlat
      final coordinator = container.read(backgroundSyncCoordinatorProvider);

      // İlk kontrol
      await container.read(systemStatusProvider.notifier).refreshStatus();

      // checking -> online geçişinde connectivityRestored tetiklenmemelidir
      // Yalnızca startup tetiklenmiş olabilir
      expect(coordinator.lastTriggerReason, isNot(equals(SyncTriggerReason.connectivityRestored)));

      container.dispose();
    });

    test('2 & 3. offline -> online ve draining -> online geçişi connectivityRestored tetikler', () async {
      int syncTriggeredCount = 0;
      SyncTriggerReason? lastReason;

      final mockClient = _MockMmsApiClient(
        nextHealthResponse: CentralHealthResponse.unreachable(
          errorMessage: 'Bağlantı kesildi',
        ),
      );

      final container = ProviderContainer(
        overrides: [
          localDatabaseServiceProvider.overrideWithValue(localDb),
          apiClientProvider.overrideWithValue(mockClient),
          syncTransportProvider.overrideWithValue(_MockSyncTransport()),
        ],
      );

      final notifier = container.read(systemStatusProvider.notifier);

      // 1. Önce offline yap
      await notifier.refreshStatus();
      expect(notifier.state.backendState, equals(BackendConnectionState.offline));

      // Dinleyici simülasyonu (sync_providers kuralı)
      container.listen<SystemStatus>(systemStatusProvider, (previous, next) {
        final wasOffline = previous != null &&
            (previous.backendState == BackendConnectionState.offline ||
                previous.backendState == BackendConnectionState.draining);
        final isNowOnline = next.backendState == BackendConnectionState.online;

        if (wasOffline && isNowOnline) {
          syncTriggeredCount++;
          lastReason = SyncTriggerReason.connectivityRestored;
        }
      });

      // 2. Şimdi online yap (offline -> online)
      mockClient.nextHealthResponse = CentralHealthResponse(
        isHealthy: true,
        status: 'UP',
        service: 'MARKET_MMS_HUB',
        sqliteVersion: 'masked',
        latencyMs: 10,
        checkedAt: DateTime.now(),
      );

      await notifier.refreshStatus();
      expect(notifier.state.backendState, equals(BackendConnectionState.online));
      expect(syncTriggeredCount, equals(1));
      expect(lastReason, equals(SyncTriggerReason.connectivityRestored));

      // 3. draining -> online testi
      mockClient.nextHealthResponse = CentralHealthResponse.draining(
        errorMessage: '503 Bakım',
      );
      await notifier.refreshStatus();
      expect(notifier.state.backendState, equals(BackendConnectionState.draining));

      mockClient.nextHealthResponse = CentralHealthResponse(
        isHealthy: true,
        status: 'UP',
        service: 'MARKET_MMS_HUB',
        sqliteVersion: 'masked',
        latencyMs: 12,
        checkedAt: DateTime.now(),
      );
      await notifier.refreshStatus();
      expect(notifier.state.backendState, equals(BackendConnectionState.online));
      expect(syncTriggeredCount, equals(2));

      container.dispose();
    });

    test('4. online -> online geçişi sync TETİKLEMEMELİDİR', () async {
      int syncTriggeredCount = 0;

      final mockClient = _MockMmsApiClient(
        nextHealthResponse: CentralHealthResponse(
          isHealthy: true,
          status: 'UP',
          service: 'MARKET_MMS_HUB',
          sqliteVersion: 'masked',
          latencyMs: 10,
          checkedAt: DateTime.now(),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          localDatabaseServiceProvider.overrideWithValue(localDb),
          apiClientProvider.overrideWithValue(mockClient),
          syncTransportProvider.overrideWithValue(_MockSyncTransport()),
        ],
      );

      final notifier = container.read(systemStatusProvider.notifier);
      await notifier.refreshStatus();
      expect(notifier.state.backendState, equals(BackendConnectionState.online));

      container.listen<SystemStatus>(systemStatusProvider, (previous, next) {
        final wasOffline = previous != null &&
            (previous.backendState == BackendConnectionState.offline ||
                previous.backendState == BackendConnectionState.draining);
        final isNowOnline = next.backendState == BackendConnectionState.online;

        if (wasOffline && isNowOnline) {
          syncTriggeredCount++;
        }
      });

      // İkinci kez online kontrolü
      await notifier.refreshStatus();
      expect(notifier.state.backendState, equals(BackendConnectionState.online));
      expect(syncTriggeredCount, equals(0), reason: 'online -> online sync tetiklememelidir');

      container.dispose();
    });

    test('5. refreshLocalMetrics yeni HTTP /health isteği OLUŞTURMAZ', () async {
      final mockClient = _MockMmsApiClient(
        nextHealthResponse: CentralHealthResponse(
          isHealthy: true,
          status: 'UP',
          service: 'MARKET_MMS_HUB',
          sqliteVersion: 'masked',
          latencyMs: 10,
          checkedAt: DateTime.now(),
        ),
      );

      final notifier = SystemStatusNotifier(
        apiClient: mockClient,
        localDbService: localDb,
        initialStatus: SystemStatus.initial(backendUrl: mockClient.baseUrl),
      );

      await notifier.refreshStatus();
      expect(mockClient.healthCallCount, equals(1));

      // refreshLocalMetrics çağrısı
      await notifier.refreshLocalMetrics();
      expect(mockClient.healthCallCount, equals(1), reason: 'Yerel metrik yenilemesi HTTP ping atmamalıdır');

      notifier.dispose();
    });

    test('6. Re-entrancy guard: Aynı anda gelen refreshStatus çağrıları birbirinin üzerine yazmaz', () async {
      final mockClient = _MockMmsApiClient(
        nextHealthResponse: CentralHealthResponse(
          isHealthy: true,
          status: 'UP',
          service: 'MARKET_MMS_HUB',
          sqliteVersion: 'masked',
          latencyMs: 10,
          checkedAt: DateTime.now(),
        ),
      );

      final notifier = SystemStatusNotifier(
        apiClient: mockClient,
        localDbService: localDb,
        initialStatus: SystemStatus.initial(backendUrl: mockClient.baseUrl),
      );

      // Aynı anda 5 adet refreshStatus çağrısı başlat
      await Future.wait([
        notifier.refreshStatus(),
        notifier.refreshStatus(),
        notifier.refreshStatus(),
        notifier.refreshStatus(),
        notifier.refreshStatus(),
      ]);

      // Re-entrancy guard sayesinde yalnızca 1 tanesi çalışmalıdır
      expect(mockClient.healthCallCount, equals(1));
      expect(notifier.state.backendState, equals(BackendConnectionState.online));

      notifier.dispose();
    });

    test('7. Online sistem arka planda kontrol edilirken UI durumu online kalır (Sıfır Titreme)', () async {
      final mockClient = _MockMmsApiClient(
        nextHealthResponse: CentralHealthResponse(
          isHealthy: true,
          status: 'UP',
          service: 'MARKET_MMS_HUB',
          sqliteVersion: 'masked',
          latencyMs: 10,
          checkedAt: DateTime.now(),
        ),
      );

      final notifier = SystemStatusNotifier(
        apiClient: mockClient,
        localDbService: localDb,
        initialStatus: SystemStatus.initial(backendUrl: mockClient.baseUrl),
      );

      await notifier.refreshStatus();
      expect(notifier.state.backendState, equals(BackendConnectionState.online));

      final stateTransitions = <BackendConnectionState>[];
      notifier.addListener((s) {
        stateTransitions.add(s.backendState);
      });

      // İkinci kontrol
      await notifier.refreshStatus();

      // checking durumuna asla düşmemeli, online olarak stabil kalmalıdır
      expect(stateTransitions.contains(BackendConnectionState.checking), isFalse);
      expect(notifier.state.backendState, equals(BackendConnectionState.online));

      notifier.dispose();
    });

    test('8 & 9. Gerçek bağlantı kaybında offline, kurtarmada online geçişi tam doğrulanır', () async {
      final mockClient = _MockMmsApiClient(
        nextHealthResponse: CentralHealthResponse(
          isHealthy: true,
          status: 'UP',
          service: 'MARKET_MMS_HUB',
          sqliteVersion: 'masked',
          latencyMs: 10,
          checkedAt: DateTime.now(),
        ),
      );

      final notifier = SystemStatusNotifier(
        apiClient: mockClient,
        localDbService: localDb,
        initialStatus: SystemStatus.initial(backendUrl: mockClient.baseUrl),
      );

      // 1. Online
      await notifier.refreshStatus();
      expect(notifier.state.backendState, equals(BackendConnectionState.online));

      // 2. Bağlantı koptu (Offline)
      mockClient.nextHealthResponse = CentralHealthResponse.unreachable(
        errorMessage: 'SocketException: Connection refused',
      );
      await notifier.refreshStatus();
      expect(notifier.state.backendState, equals(BackendConnectionState.offline));
      expect(notifier.state.errorMessage, contains('Connection refused'));

      // 3. Bağlantı geri geldi (Online)
      mockClient.nextHealthResponse = CentralHealthResponse(
        isHealthy: true,
        status: 'UP',
        service: 'MARKET_MMS_HUB',
        sqliteVersion: 'masked',
        latencyMs: 8,
        checkedAt: DateTime.now(),
      );
      await notifier.refreshStatus();
      expect(notifier.state.backendState, equals(BackendConnectionState.online));
      expect(notifier.state.errorMessage, isNull);

      notifier.dispose();
    });
  });
}
