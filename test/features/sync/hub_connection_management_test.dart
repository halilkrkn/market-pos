import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/core/network/api_client.dart';
import 'package:market_pos/core/network/api_exception.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/core/theme/app_theme.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:market_pos/features/diagnostics/presentation/screens/diagnostics_view.dart';
import 'package:market_pos/features/pos/pos_providers.dart';
import 'package:market_pos/features/sync/application/background_sync_coordinator.dart';
import 'package:market_pos/features/sync/application/hub_connection_notifier.dart';
import 'package:market_pos/features/sync/domain/hub_connection_state.dart';
import 'package:market_pos/features/sync/domain/hub_discovery_client.dart';
import 'package:market_pos/features/sync/domain/sync_coordinator_state.dart';
import 'package:market_pos/features/sync/sync_providers.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

class _RecordingSyncTransport implements SyncTransport {
  final List<({String hubUrl, int clientSeq, String operation})> salePosts = [];
  int totalCalls = 0;

  @override
  Future<SyncResponse> postSale({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    totalCalls++;
    final body = jsonDecode(payload) as Map<String, dynamic>;
    final seq = body['client_seq'] as int;
    salePosts.add((hubUrl: hubUrl, clientSeq: seq, operation: 'SALE'));
    return SyncResponse(
      statusCode: 201,
      body: jsonEncode({
        'status': 'COMMITTED',
        'client_seq': seq,
        'committed_at': DateTime.now().toIso8601String(),
      }),
    );
  }

  @override
  Future<SyncResponse> postProductUpsert({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    totalCalls++;
    return SyncResponse(
      statusCode: 201,
      body: jsonEncode({'status': 'COMMITTED'}),
    );
  }

  @override
  Future<SyncResponse> getProducts({
    required String hubUrl,
    required String token,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    totalCalls++;
    return SyncResponse(
      statusCode: 200,
      body: jsonEncode({'products': <dynamic>[]}),
    );
  }

  @override
  Future<SyncResponse> getSales({
    required String hubUrl,
    required String token,
    int cursor = 0,
    int limit = 50,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    totalCalls++;
    return SyncResponse(
      statusCode: 200,
      body: jsonEncode({
        'sales': <dynamic>[],
        'last_server_sale_seq': cursor,
        'has_more': false,
      }),
    );
  }

  @override
  Future<SyncResponse> postSyncAck({
    required String hubUrl,
    required String token,
    required String syncSessionId,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    totalCalls++;
    return SyncResponse(
      statusCode: 200,
      body: jsonEncode({'status': 'OK'}),
    );
  }

  @override
  Future<SyncResponse> postStockReceipt({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(statusCode: 200, body: '{"status":"COMMITTED"}');

  @override
  void close() {}
}

void main() {
  late LocalDatabaseService localDb;

  Future<void> seedProduct() async {
    await localDb.repository.upsertProducts([
      LocalProductsCompanion(
        id: const Value('prod_ekmek'),
        barcode: const Value('8690504018241'),
        name: const Value('Somun Ekmek'),
        price: const Value(1250),
        priceVersionId: const Value('pv_1'),
        stock: const Value(100000),
        stockUnit: const Value('adet'),
        pricingUnit: const Value('adet'),
        conversionFactorNumerator: const Value(1),
        conversionFactorDenominator: const Value(1),
        vatRate: const Value(1),
        isActive: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    ]);
  }

  setUp(() async {
    localDb = LocalDatabaseService.forTesting(
      NativeDatabase.memory(),
      path: 'memory_client.db',
    );
    await seedProduct();
  });

  tearDown(() async {
    await localDb.close();
  });

  group('Faz 1.2 - Platform Hub URL Politikası ve MmsApiClient Güvenliği', () {
    test('Android (allowLoopback=false) kayıtlı adres yokken unconfigured başlar ve 0 HTTP isteği atar', () async {
      final initialState = await HubConnectionBootstrapper.loadInitialState(
        repository: localDb.repository,
        allowLoopback: false,
        configuredHubUrl: '',
        desktopFallbackUrl: 'http://127.0.0.1:8945',
      );

      expect(initialState.isInitialized, isTrue);
      expect(initialState.phase, HubConnectionPhase.unconfigured);
      expect(initialState.activeHubUrl, isNull);
      expect(initialState.source, isNull);

      int httpRequestCount = 0;
      final mockHttp = MockClient((request) async {
        httpRequestCount++;
        return http.Response('{}', 200);
      });

      final apiClient = MmsApiClient(
        client: mockHttp,
        readBaseUrl: () => initialState.activeHubUrl,
        allowLoopback: false,
      );

      expect(apiClient.baseUrl, isEmpty);
      expect(apiClient.resolvedBaseUrl, isNull);

      final health = await apiClient.checkHealth();
      expect(health.isHealthy, isFalse);
      expect(httpRequestCount, 0);

      await expectLater(
        () => apiClient.get('/health'),
        throwsA(isA<NetworkException>()),
      );
      await expectLater(
        () => apiClient.post('/api/v1/sales', body: <String, dynamic>{}),
        throwsA(isA<NetworkException>()),
      );
      expect(
        httpRequestCount,
        0,
        reason: 'Android üzerinde URL yokken 127.0.0.1 fallback ile ağ isteği atılmamalıdır.',
      );
    });

    test('Windows (allowLoopback=true) kayıtlı adres yokken 127.0.0.1 fallback çözümlemesini korur', () async {
      final initialState = await HubConnectionBootstrapper.loadInitialState(
        repository: localDb.repository,
        allowLoopback: true,
        configuredHubUrl: '',
        desktopFallbackUrl: 'http://127.0.0.1:8945',
      );

      expect(initialState.isInitialized, isTrue);
      expect(initialState.phase, HubConnectionPhase.verifying);
      expect(initialState.activeHubUrl, 'http://127.0.0.1:8945');
      expect(initialState.source, HubUrlSource.localhostFallback);
    });

    test('Android politikasında HubConnectionNotifier.setHubUrl loopback adresleri reddeder', () async {
      int httpCalls = 0;
      final apiClient = MmsApiClient(
        client: MockClient((_) async {
          httpCalls++;
          return http.Response('{}', 200);
        }),
        allowLoopback: false,
      );

      final notifier = HubConnectionNotifier(
        repository: localDb.repository,
        checkUrlHealth: apiClient.checkHealthForUrl,
        allowLoopback: false,
        initialState: const HubConnectionState(
          phase: HubConnectionPhase.unconfigured,
          activeHubUrl: null,
          isInitialized: true,
        ),
      );
      addTearDown(notifier.dispose);

      for (final blocked in const <String>[
        'http://127.0.0.1:8945',
        'http://localhost:8945',
        'http://[::1]:8945',
        'http://0.0.0.0:8945',
      ]) {
        await expectLater(
          () => notifier.setHubUrl(blocked, source: HubUrlSource.manual),
          throwsA(isA<HubUrlValidationException>()),
        );
      }

      expect(httpCalls, 0);
      expect(notifier.state.activeHubUrl, isNull);
      expect(
        await localDb.repository.getStoredHubConnection(allowLoopback: false),
        isNull,
      );
    });
  });

  group('Faz 1.2 - Dinamik URL Geçişi, Sepet Korunumu ve Offline-First FIFO', () {
    test('Hub URL değişiminde apiClientProvider aynı instance kalır ve aktif POS sepeti sıfırlanmaz', () async {
      final requestedUrls = <String>[];
      final mockHttp = MockClient((request) async {
        requestedUrls.add('${request.url.scheme}://${request.url.host}:${request.url.port}${request.url.path}');
        return http.Response(
          jsonEncode({
            'status': 'HEALTHY',
            'service': 'MARKET_MMS_HUB',
            'sqlite_version': '3.45.1',
          }),
          200,
        );
      });

      final initialState = await HubConnectionBootstrapper.loadInitialState(
        repository: localDb.repository,
        allowLoopback: false,
        configuredHubUrl: 'http://192.168.1.10:8945',
      );

      late final ProviderContainer container;
      container = ProviderContainer(
        overrides: [
          localDatabaseServiceProvider.overrideWithValue(localDb),
          hubAllowLoopbackPolicyProvider.overrideWithValue(false),
          initialHubConnectionStateProvider.overrideWithValue(initialState),
          apiClientProvider.overrideWith(
            (ref) => MmsApiClient(
              client: mockHttp,
              readBaseUrl: () => ref.read(hubConnectionProvider).activeHubUrl,
              allowLoopback: false,
              deviceId: 'POS-AND-01',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final clientBefore = container.read(apiClientProvider);

      // Sepete ürün ekle
      final added = await container.read(cartProvider.notifier).scanBarcode('8690504018241');
      expect(added, isTrue);
      expect(container.read(cartProvider).items, hasLength(1));
      expect(container.read(cartProvider).totalCents, 1250);

      // Hub URL çalışma anında değiştirilir
      final ok = await container.read(hubConnectionProvider.notifier).setHubUrl(
            'http://192.168.1.20:8945/',
            hubId: 'hub-lan-02',
            source: HubUrlSource.discovered,
          );
      expect(ok, isTrue);

      final clientAfter = container.read(apiClientProvider);
      expect(identical(clientBefore, clientAfter), isTrue);
      expect(clientAfter.baseUrl, 'http://192.168.1.20:8945');

      // Sepet içeriği kesinlikle korunmuş olmalı
      final cartAfter = container.read(cartProvider);
      expect(cartAfter.items, hasLength(1));
      expect(cartAfter.items.single.productId, 'prod_ekmek');
      expect(cartAfter.totalCents, 1250);

      // Sonraki HTTP isteği yeni URL'ye gider
      await clientAfter.get('/api/v1/products');
      expect(
        requestedUrls,
        contains('http://192.168.1.20:8945/api/v1/products'),
      );
    });

    test('Android unconfigured iken offline satışlar birikir, URL gelince Outbox FIFO sırasıyla aktarılır', () async {
      final transport = _RecordingSyncTransport();
      final mockHttp = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'UP',
            'service': 'MARKET_MMS_HUB',
            'sqlite_version': '3.45.1',
          }),
          200,
        );
      });

      final initialState = await HubConnectionBootstrapper.loadInitialState(
        repository: localDb.repository,
        allowLoopback: false,
        configuredHubUrl: '',
      );
      expect(initialState.phase, HubConnectionPhase.unconfigured);
      expect(initialState.activeHubUrl, isNull);

      final container = ProviderContainer(
        overrides: [
          localDatabaseServiceProvider.overrideWithValue(localDb),
          hubAllowLoopbackPolicyProvider.overrideWithValue(false),
          initialHubConnectionStateProvider.overrideWithValue(initialState),
          syncTransportProvider.overrideWithValue(transport),
          apiClientProvider.overrideWith(
            (ref) => MmsApiClient(
              client: mockHttp,
              readBaseUrl: () => ref.read(hubConnectionProvider).activeHubUrl,
              allowLoopback: false,
              deviceId: 'POS-AND-01',
              deviceToken: 'test_token_123',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      // 1. Offline ortamda 2 ardışık satış yap (client_seq: 1, 2)
      await localDb.repository.createOfflineSale(
        deviceId: 'POS-AND-01',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_ekmek', 1)],
      );
      await localDb.repository.createOfflineSale(
        deviceId: 'POS-AND-01',
        paymentMethod: 'CARD',
        items: [CartItemInput.units('prod_ekmek', 2)],
      );

      final coordinator =
          container.read(backgroundSyncCoordinatorProvider.notifier);
      await coordinator.triggerSync(reason: SyncTriggerReason.startup);
      await coordinator.triggerSync(reason: SyncTriggerReason.saleCommitted);
      await coordinator.triggerSync(reason: SyncTriggerReason.periodic);

      expect(transport.totalCalls, 0);
      expect((await localDb.getOutboxSummary()).pending, 2);

      // 2. Çalışma anında LAN Hub adresi tanımlanır -> connectivityRestored tetiklenir
      final completer = Completer<void>();
      final sub = container.listen<SyncCoordinatorState>(
        backgroundSyncCoordinatorProvider,
        (prev, next) {
          if (prev?.isSyncing == true && !next.isSyncing && !completer.isCompleted) {
            completer.complete();
          }
        },
      );
      addTearDown(sub.close);

      await container.read(hubConnectionProvider.notifier).setHubUrl(
            'http://192.168.1.60:8945',
            hubId: 'hub-store-60',
            source: HubUrlSource.discovered,
          );

      await completer.future.timeout(const Duration(seconds: 5));

      expect(
        transport.salePosts.map((e) => (hubUrl: e.hubUrl, seq: e.clientSeq)).toList(),
        const <({String hubUrl, int seq})>[
          (hubUrl: 'http://192.168.1.60:8945', seq: 1),
          (hubUrl: 'http://192.168.1.60:8945', seq: 2),
        ],
      );
      expect((await localDb.getOutboxSummary()).pending, 0);
    });

    test('BackgroundSyncCoordinator: başlatma öncesi, null URL ve Android loopback durumlarında senkronizasyonu durdurur', () async {
      final transport = _RecordingSyncTransport();
      await localDb.repository.createOfflineSale(
        deviceId: 'POS-AND-01',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_ekmek', 1)],
      );

      bool isReady = false;
      String? dynamicUrl = 'http://192.168.1.70:8945';

      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: 'POS-AND-01',
        readDeviceToken: () => 'tok_1',
        hubUrl: 'http://127.0.0.1:8945',
        readHubUrl: () => dynamicUrl,
        isHubUrlReady: () => isReady,
        allowLoopbackHubUrl: false,
        autoStartTimer: false,
        enableLifecycleListener: false,
      );
      addTearDown(coordinator.dispose);

      // 1. isHubUrlReady == false -> sync çalışmamalı
      await coordinator.triggerSync(reason: SyncTriggerReason.startup);
      expect(transport.totalCalls, 0);

      // 2. Hazır ama null URL -> statik hubUrl (127.0.0.1) asla kullanılmamalı
      isReady = true;
      dynamicUrl = null;
      await coordinator.triggerSync(reason: SyncTriggerReason.manual);
      expect(coordinator.state.status, SyncCoordinatorStatus.networkError);
      expect(transport.totalCalls, 0);

      // 3. Android policy'de loopback URL -> reddedilmeli
      dynamicUrl = 'http://127.0.0.1:8945';
      await coordinator.triggerSync(reason: SyncTriggerReason.manual);
      expect(coordinator.state.status, SyncCoordinatorStatus.networkError);
      expect(transport.totalCalls, 0);

      // 4. Geçerli LAN URL -> güncel URL üzerinden aktarılır
      dynamicUrl = 'http://192.168.1.75:8945';
      await coordinator.triggerSync(reason: SyncTriggerReason.connectivityRestored);
      expect(transport.salePosts, hasLength(1));
      expect(transport.salePosts.single.hubUrl, 'http://192.168.1.75:8945');
    });

    test('Daha önce doğrulanmış Hub açılışta çevrimdışıysa offline fazına geçer fakat URL ve lastVerifiedAt silinmez', () async {
      final verifiedAt = DateTime.utc(2026, 11, 20, 9, 0, 0);
      await localDb.repository.saveStoredHubConnection(
        hubUrl: 'http://192.168.1.45:8945',
        hubId: 'hub-main',
        source: HubUrlSource.discovered,
        allowLoopback: false,
        verifiedAt: verifiedAt,
      );

      final initialState = await HubConnectionBootstrapper.loadInitialState(
        repository: localDb.repository,
        allowLoopback: false,
      );
      expect(initialState.activeHubUrl, 'http://192.168.1.45:8945');

      final unreachableClient = MmsApiClient(
        client: MockClient((_) async => throw const HttpException('Connection refused')),
        allowLoopback: false,
      );

      final notifier = HubConnectionNotifier(
        repository: localDb.repository,
        checkUrlHealth: unreachableClient.checkHealthForUrl,
        allowLoopback: false,
        initialState: initialState,
      );
      addTearDown(notifier.dispose);

      await notifier.verifyActiveHub();

      expect(notifier.state.phase, HubConnectionPhase.offline);
      expect(notifier.state.activeHubUrl, 'http://192.168.1.45:8945');
      expect(
        notifier.state.lastVerifiedAt?.millisecondsSinceEpoch,
        verifiedAt.millisecondsSinceEpoch,
      );

      final persisted =
          await localDb.repository.getStoredHubConnection(allowLoopback: false);
      expect(persisted?.hubUrl, 'http://192.168.1.45:8945');
      expect(
        persisted?.lastVerifiedAt?.millisecondsSinceEpoch,
        verifiedAt.millisecondsSinceEpoch,
      );
    });
  });

  group('Faz 1.2 - DiagnosticsView Görünüm Testleri', () {
    testWidgets('unconfigured durumda 127.0.0.1 göstermeden Henüz yapılandırılmadı gösterir, güncel URL geldiğinde canlı güncellenir',
        (WidgetTester tester) async {
      final mockHttp = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'UP',
            'service': 'MARKET_MMS_HUB',
            'sqlite_version': '3.45.1',
          }),
          200,
        );
      });

      const unconfigured = HubConnectionState(
        phase: HubConnectionPhase.unconfigured,
        activeHubUrl: null,
        isInitialized: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localDatabaseServiceProvider.overrideWithValue(localDb),
            hubAllowLoopbackPolicyProvider.overrideWithValue(false),
            initialHubConnectionStateProvider.overrideWithValue(unconfigured),
            syncTransportProvider.overrideWithValue(_RecordingSyncTransport()),
            apiClientProvider.overrideWith(
              (ref) => MmsApiClient(
                client: mockHttp,
                readBaseUrl: () => ref.read(hubConnectionProvider).activeHubUrl,
                allowLoopback: false,
                deviceId: 'POS-AND-01',
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(body: DiagnosticsView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Henüz yapılandırılmadı'), findsOneWidget);
      expect(find.text('Yapılandırılmadı'), findsOneWidget);
      expect(find.textContaining('127.0.0.1'), findsNothing);

      // Çalışma anında yeni LAN Hub URL tanımlanır
      final element = tester.element(find.byType(DiagnosticsView));
      final container = ProviderScope.containerOf(element);
      await container.read(hubConnectionProvider.notifier).setHubUrl(
            'http://192.168.1.88:8945',
            hubId: 'hub-market-01',
            source: HubUrlSource.discovered,
          );
      await tester.pumpAndSettle();

      expect(find.text('http://192.168.1.88:8945'), findsOneWidget);
      expect(find.text('Kaynak: Otomatik Keşif'), findsOneWidget);
      expect(find.text('hub-market-01'), findsOneWidget);
    });

    testWidgets('Faz 1.3: Yeniden Ara, Android loopback reddi, Manuel IP kaydı ve erişilemeyen IP koruması',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final requestedOrigins = <String>[];
      final mockHttp = MockClient((request) async {
        final origin = '${request.url.scheme}://${request.url.host}:${request.url.port}';
        requestedOrigins.add(origin);
        if (origin == 'https://192.168.1.250:8945' ||
            origin == 'http://192.168.1.250:8945') {
          throw const HttpException('Unreachable test host');
        }
        return http.Response(
          jsonEncode({
            'status': 'UP',
            'service': 'MARKET_MMS_HUB',
            'sqlite_version': '3.45.1',
          }),
          200,
        );
      });

      final stubDiscovery = _StubWidgetDiscoveryClient(
        const <DiscoveredHubCandidate>[
          DiscoveredHubCandidate(
            service: 'market_mms_hub',
            protocolVersion: '1.0',
            hubId: 'hub-udp-90',
            httpPort: 8945,
            responderIp: '192.168.1.90',
            serverIps: <String>['192.168.1.90'],
          ),
        ],
      );

      const unconfigured = HubConnectionState(
        phase: HubConnectionPhase.unconfigured,
        activeHubUrl: null,
        isInitialized: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localDatabaseServiceProvider.overrideWithValue(localDb),
            hubAllowLoopbackPolicyProvider.overrideWithValue(false),
            initialHubConnectionStateProvider.overrideWithValue(unconfigured),
            hubDiscoveryClientProvider.overrideWithValue(stubDiscovery),
            syncTransportProvider.overrideWithValue(_RecordingSyncTransport()),
            apiClientProvider.overrideWith(
              (ref) => MmsApiClient(
                client: mockHttp,
                readBaseUrl: () => ref.read(hubConnectionProvider).activeHubUrl,
                allowLoopback: false,
                deviceId: 'POS-AND-01',
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(body: DiagnosticsView()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Hub'ı Yeniden Ara butonuna bas -> keşif ve bağlantı kurulur
      final discoverBtn = find.byKey(const Key('diagnostics_discover_hub_button'));
      await tester.ensureVisible(discoverBtn);
      await tester.tap(discoverBtn);
      await tester.pumpAndSettle();

      expect(stubDiscovery.calls, 1);
      expect(find.text('https://192.168.1.90:8945'), findsOneWidget);
      expect(find.text('Kaynak: Otomatik Keşif'), findsOneWidget);
      expect(find.text('hub-udp-90'), findsOneWidget);

      // 2. Android politikasında yalın loopback ('127.0.0.1') manuel girişte reddedilir
      final inputFinder = find.byKey(const Key('diagnostics_manual_hub_input'));
      final saveBtn = find.byKey(const Key('diagnostics_save_manual_hub_button'));
      final callsBeforeLoopback = requestedOrigins.length;

      await tester.ensureVisible(inputFinder);
      await tester.enterText(inputFinder, '127.0.0.1');
      await tester.ensureVisible(saveBtn);
      await tester.pumpAndSettle();
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(requestedOrigins.length, callsBeforeLoopback);
      expect(find.byKey(const Key('diagnostics_hub_action_feedback')), findsOneWidget);
      expect(find.text('https://192.168.1.90:8945'), findsOneWidget);

      // 3. Geçerli yalın IP ('192.168.1.95') HTTPS olarak normalize edilir, doğrulanır ve Manuel kaydedilir
      await tester.enterText(inputFinder, '192.168.1.95');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(find.text('https://192.168.1.95:8945'), findsOneWidget);
      expect(find.text('Kaynak: Manuel'), findsOneWidget);

      final persistedValid =
          await localDb.repository.getStoredHubConnection(allowLoopback: false);
      expect(persistedValid?.hubUrl, 'https://192.168.1.95:8945');
      expect(persistedValid?.source, HubUrlSource.manual);

      // 4. Erişilemeyen IP ('192.168.1.250') girilirse hata gösterir fakat mevcut çalışan URL korunur
      await tester.enterText(inputFinder, '192.168.1.250');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('diagnostics_hub_action_feedback')), findsOneWidget);
      expect(find.text('https://192.168.1.95:8945'), findsOneWidget);
      final persistedAfterFail =
          await localDb.repository.getStoredHubConnection(allowLoopback: false);
      expect(persistedAfterFail?.hubUrl, 'https://192.168.1.95:8945');
    });
  });
}

class _StubWidgetDiscoveryClient implements HubDiscoveryClient {
  final List<DiscoveredHubCandidate> candidates;
  int calls = 0;

  _StubWidgetDiscoveryClient(this.candidates);

  @override
  Future<List<DiscoveredHubCandidate>> discover({
    required String deviceId,
    Duration timeout = const Duration(milliseconds: 2500),
    int probeCount = 3,
    Duration probeInterval = const Duration(milliseconds: 600),
  }) async {
    calls++;
    return candidates;
  }
}

class HttpException implements Exception {
  final String message;
  const HttpException(this.message);
  @override
  String toString() => message;
}
