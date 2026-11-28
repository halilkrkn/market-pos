import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/core/network/api_client.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:market_pos/features/sync/application/hub_connection_notifier.dart';
import 'package:market_pos/features/sync/domain/hub_connection_state.dart';
import 'package:market_pos/features/sync/domain/hub_discovery_client.dart';
import 'package:market_pos/features/sync/domain/sync_coordinator_state.dart';
import 'package:market_pos/features/sync/infrastructure/udp_hub_discovery_client.dart';
import 'package:market_pos/features/sync/sync_providers.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

class _TestUdpResponder {
  final RawDatagramSocket socket;
  final int httpPort;
  final String hubId;
  final List<String> serverIps;
  final bool sendNoiseFirst;
  final List<String> receivedCommands = [];
  StreamSubscription<RawSocketEvent>? _sub;

  _TestUdpResponder._(
    this.socket, {
    required this.httpPort,
    required this.hubId,
    required this.serverIps,
    this.sendNoiseFirst = false,
  }) {
    _sub = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;

      final decoded = jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      receivedCommands.add(decoded['cmd'] as String);
      if (decoded['cmd'] != UdpHubDiscoveryClient.discoveryCommand) return;

      if (sendNoiseFirst) {
        // Geçersiz UTF-8, bozuk JSON, büyük paket ve farklı servis adı gürültüsü
        socket.send(<int>[0xff, 0xfe, 0x80], datagram.address, datagram.port);
        socket.send(utf8.encode('{invalid'), datagram.address, datagram.port);
        socket.send(
          List<int>.filled(2500, 65),
          datagram.address,
          datagram.port,
        );
        socket.send(
          utf8.encode(
            jsonEncode(<String, dynamic>{
              'service': 'other_service',
              'protocol_version': '1.0',
              'hub_id': 'wrong',
              'http_port': 9999,
              'server_ips': <String>['10.10.10.10'],
            }),
          ),
          datagram.address,
          datagram.port,
        );
      }

      final payload = jsonEncode(<String, dynamic>{
        'service': 'market_mms_hub',
        'protocol_version': '1.0',
        'hub_id': hubId,
        'http_port': httpPort,
        'server_time': DateTime.now().toUtc().toIso8601String(),
        'server_ips': serverIps,
      });
      socket.send(utf8.encode(payload), datagram.address, datagram.port);
    });
  }

  int get port => socket.port;

  static Future<_TestUdpResponder> start({
    required int httpPort,
    String hubId = 'MMS-HUB-TEST',
    List<String> serverIps = const <String>['192.168.1.50'],
    bool sendNoiseFirst = false,
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    return _TestUdpResponder._(
      socket,
      httpPort: httpPort,
      hubId: hubId,
      serverIps: serverIps,
      sendNoiseFirst: sendNoiseFirst,
    );
  }

  Future<void> close() async {
    await _sub?.cancel();
    socket.close();
  }
}

class _StubDiscoveryClient implements HubDiscoveryClient {
  final List<DiscoveredHubCandidate> Function() onDiscover;
  int calls = 0;

  _StubDiscoveryClient(this.onDiscover);

  @override
  Future<List<DiscoveredHubCandidate>> discover({
    required String deviceId,
    Duration timeout = const Duration(milliseconds: 2500),
    int probeCount = 3,
    Duration probeInterval = const Duration(milliseconds: 600),
  }) async {
    calls++;
    return onDiscover();
  }
}

class _FifoRecordingSyncTransport implements SyncTransport {
  final String? expectedHubUrl;
  final List<({String hubUrl, int clientSeq})> salePosts = [];

  _FifoRecordingSyncTransport({this.expectedHubUrl});

  void _ensureReachable(String hubUrl) {
    if (expectedHubUrl != null && hubUrl != expectedHubUrl) {
      throw SocketException('Dead test Hub URL: $hubUrl');
    }
  }

  @override
  Future<SyncResponse> postSale({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    _ensureReachable(hubUrl);
    final body = jsonDecode(payload) as Map<String, dynamic>;
    final seq = body['client_seq'] as int;
    salePosts.add((hubUrl: hubUrl, clientSeq: seq));
    return SyncResponse(
      statusCode: 201,
      body: jsonEncode(<String, dynamic>{
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
    _ensureReachable(hubUrl);
    return SyncResponse(
      statusCode: 201,
      body: jsonEncode(<String, dynamic>{'status': 'COMMITTED'}),
    );
  }

  @override
  Future<SyncResponse> getProducts({
    required String hubUrl,
    required String token,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    _ensureReachable(hubUrl);
    return SyncResponse(
      statusCode: 200,
      body: jsonEncode(<String, dynamic>{'products': <dynamic>[]}),
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
    _ensureReachable(hubUrl);
    return SyncResponse(
      statusCode: 200,
      body: jsonEncode(<String, dynamic>{
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
    _ensureReachable(hubUrl);
    return SyncResponse(
      statusCode: 200,
      body: jsonEncode(<String, dynamic>{'status': 'OK'}),
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

Future<int> _reserveDeadLocalPort() async {
  final srv = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = srv.port;
  await srv.close();
  return port;
}

void main() {
  late LocalDatabaseService localDb;

  setUp(() async {
    localDb = LocalDatabaseService.forTesting(
      NativeDatabase.memory(),
      path: 'memory_udp_discovery_test.db',
    );
    await localDb.repository.upsertProducts([
      LocalProductsCompanion(
        id: const Value('prod_su'),
        barcode: const Value('8690001'),
        name: const Value('Su 0.5L'),
        price: const Value(500),
        priceVersionId: const Value('pv_1'),
        stock: const Value(50000),
        stockUnit: const Value('adet'),
        pricingUnit: const Value('adet'),
        conversionFactorNumerator: const Value(1),
        conversionFactorDenominator: const Value(1),
        vatRate: const Value(1),
        isActive: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    ]);
  });

  tearDown(() async {
    await localDb.close();
  });

  group('Faz 1.3 - UdpHubDiscoveryClient Gerçek Soket Testleri', () {
    test('gerçek UDP yanıtını çözer ve gürültülü/bozuk datagramları güvenle eler', () async {
      final responder = await _TestUdpResponder.start(
        httpPort: 8945,
        hubId: 'MMS-HUB-01',
        serverIps: const <String>['192.168.1.50', '10.0.0.8'],
        sendNoiseFirst: true,
      );
      addTearDown(responder.close);

      final client = UdpHubDiscoveryClient(
        discoveryPort: responder.port,
        bindAddress: InternetAddress.loopbackIPv4,
        overrideTargets: <InternetAddress>[InternetAddress.loopbackIPv4],
        settleAfterFirstMatch: const Duration(milliseconds: 120),
      );

      final candidates = await client.discover(
        deviceId: 'POS-AND-01',
        timeout: const Duration(seconds: 2),
        probeCount: 2,
        probeInterval: const Duration(milliseconds: 150),
      );

      expect(candidates, hasLength(1));
      expect(candidates.single.service, 'market_mms_hub');
      expect(candidates.single.protocolVersion, '1.0');
      expect(candidates.single.hubId, 'MMS-HUB-01');
      expect(candidates.single.httpPort, 8945);
      expect(candidates.single.responderIp, '127.0.0.1');
      expect(candidates.single.serverIps, const <String>['192.168.1.50', '10.0.0.8']);
      expect(responder.receivedCommands, contains('DISCOVER_MMS_HUB'));
    });

    test('cevap gelmediğinde zaman aşımı sonunda boş liste döner ve soketi kapatır', () async {
      final deadUdpPort = await _reserveDeadLocalPort();
      final client = UdpHubDiscoveryClient(
        discoveryPort: deadUdpPort,
        bindAddress: InternetAddress.loopbackIPv4,
        overrideTargets: <InternetAddress>[InternetAddress.loopbackIPv4],
      );

      final candidates = await client.discover(
        deviceId: 'POS-AND-01',
        timeout: const Duration(milliseconds: 220),
        probeCount: 2,
        probeInterval: const Duration(milliseconds: 80),
      );

      expect(candidates, isEmpty);
    });
  });

  group('Faz 1.3 - HubConnectionNotifier Keşif, Failover ve Reconnect Akışları', () {
    test('çoklu NIC aday failover: ölü responderIp başarısız olunca sağlıklı yedek aday URL doğrulanıp kaydedilir', () async {
      final deadPort = await _reserveDeadLocalPort();
      final deadUrl = 'http://192.168.1.250:$deadPort';
      final liveUrl = 'http://192.168.1.50:8945';
      final probedUrls = <String>[];

      final discovery = _StubDiscoveryClient(() => const <DiscoveredHubCandidate>[
            DiscoveredHubCandidate(
              service: 'market_mms_hub',
              protocolVersion: '1.0',
              hubId: 'MMS-HUB-LAN',
              httpPort: 8945,
              responderIp: '192.168.1.50',
              serverIps: <String>['192.168.1.50', '10.0.0.22'],
              scheme: 'http',
            ),
          ]);

      final multiNicDiscovery = _StubDiscoveryClient(() => <DiscoveredHubCandidate>[
            DiscoveredHubCandidate(
              service: 'market_mms_hub',
              protocolVersion: '1.0',
              hubId: 'MMS-HUB-DEAD',
              httpPort: deadPort,
              responderIp: '192.168.1.250',
              serverIps: const <String>['192.168.1.250'],
              scheme: 'http',
            ),
            ...discovery.onDiscover(),
          ]);

      final mockHttp = MockClient((request) async {
        final origin = '${request.url.scheme}://${request.url.host}:${request.url.port}';
        probedUrls.add(origin);
        if (origin == deadUrl) {
          throw const SocketException('Connection refused');
        }
        return http.Response(
          jsonEncode(<String, dynamic>{
            'status': 'UP',
            'service': 'MARKET_MMS_HUB',
            'sqlite_version': '3.45.1',
          }),
          200,
        );
      });

      final apiClient = MmsApiClient(client: mockHttp, allowLoopback: false);
      final notifier = HubConnectionNotifier(
        repository: localDb.repository,
        checkUrlHealth: apiClient.checkHealthForUrl,
        discoveryClient: multiNicDiscovery,
        allowLoopback: false,
        initialState: const HubConnectionState(
          phase: HubConnectionPhase.unconfigured,
          activeHubUrl: null,
          isInitialized: true,
        ),
      );
      addTearDown(notifier.dispose);

      final connected = await notifier.discoverAndConnect();

      expect(connected, isTrue);
      expect(probedUrls, <String>[deadUrl, liveUrl]);
      expect(notifier.state.phase, HubConnectionPhase.connected);
      expect(notifier.state.activeHubUrl, liveUrl);
      expect(notifier.state.source, HubUrlSource.discovered);
      expect(notifier.state.hubId, 'MMS-HUB-LAN');

      final persisted =
          await localDb.repository.getStoredHubConnection(allowLoopback: false);
      expect(persisted?.hubUrl, liveUrl);
      expect(persisted?.source, HubUrlSource.discovered);
    });

    test('kayıtlı son Hub erişilemez olunca UDP keşfine geçer, yeni IPyi doğrular ve biriken Outbox satışlarını FIFO ile aktarır', () async {
      // Gerçek HTTP /health sunucusu + gerçek UDP responder başlat
      final liveServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => liveServer.close(force: true));
      liveServer.listen((HttpRequest req) async {
        if (req.uri.path == '/health') {
          req.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(<String, dynamic>{
                'status': 'UP',
                'service': 'MARKET_MMS_HUB',
                'sqlite_version': '3.45.1',
              }),
            );
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      });

      final responder = await _TestUdpResponder.start(
        httpPort: liveServer.port,
        hubId: 'MMS-HUB-NEW',
        serverIps: const <String>['127.0.0.1'],
      );
      addTearDown(responder.close);

      final deadHttpPort = await _reserveDeadLocalPort();
      final oldUrl = 'http://127.0.0.1:$deadHttpPort';
      final newUrl = 'http://127.0.0.1:${liveServer.port}';

      await localDb.repository.saveStoredHubConnection(
        hubUrl: oldUrl,
        hubId: 'MMS-HUB-OLD',
        source: HubUrlSource.discovered,
        allowLoopback: true,
        verifiedAt: DateTime.utc(2026, 11, 20, 8, 0),
      );

      final initialState = await HubConnectionBootstrapper.loadInitialState(
        repository: localDb.repository,
        allowLoopback: true,
      );
      expect(initialState.activeHubUrl, oldUrl);

      final transport = _FifoRecordingSyncTransport(expectedHubUrl: newUrl);
      final udpClient = UdpHubDiscoveryClient(
        discoveryPort: responder.port,
        bindAddress: InternetAddress.loopbackIPv4,
        overrideTargets: <InternetAddress>[InternetAddress.loopbackIPv4],
        settleAfterFirstMatch: const Duration(milliseconds: 100),
        defaultScheme: 'http',
      );

      final container = ProviderContainer(
        overrides: [
          localDatabaseServiceProvider.overrideWithValue(localDb),
          hubAllowLoopbackPolicyProvider.overrideWithValue(true),
          hubAutoDiscoveryLifecycleEnabledProvider.overrideWithValue(true),
          initialHubConnectionStateProvider.overrideWithValue(initialState),
          hubDiscoveryClientProvider.overrideWithValue(udpClient),
          syncTransportProvider.overrideWithValue(transport),
          apiClientProvider.overrideWith(
            (ref) => MmsApiClient(
              readBaseUrl: () => ref.read(hubConnectionProvider).activeHubUrl,
              allowLoopback: true,
              deviceId: 'POS-AND-01',
              deviceToken: 'tok_sync_test',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Çevrimdışıyken 2 ardışık satış biriktir (client_seq 1, 2)
      await localDb.repository.createOfflineSale(
        deviceId: 'POS-AND-01',
        paymentMethod: 'CASH',
        items: <CartItemInput>[CartItemInput.units('prod_su', 1)],
      );
      await localDb.repository.createOfflineSale(
        deviceId: 'POS-AND-01',
        paymentMethod: 'CARD',
        items: <CartItemInput>[CartItemInput.units('prod_su', 2)],
      );

      final syncDone = Completer<void>();
      final sub = container.listen<SyncCoordinatorState>(
        backgroundSyncCoordinatorProvider,
        (prev, next) {
          if (prev?.isSyncing == true && !next.isSyncing && !syncDone.isCompleted) {
            syncDone.complete();
          }
        },
      );
      addTearDown(sub.close);

      // Başlangıç auto-lifecycle keşfinin tamamlanmasını ve ardından FIFO sync bitişini bekle
      await syncDone.future.timeout(const Duration(seconds: 6));

      expect(container.read(hubConnectionProvider).activeHubUrl, newUrl);
      expect(container.read(hubConnectionProvider).phase, HubConnectionPhase.connected);

      expect(
        transport.salePosts,
        <({String hubUrl, int clientSeq})>[
          (hubUrl: newUrl, clientSeq: 1),
          (hubUrl: newUrl, clientSeq: 2),
        ],
      );
      expect((await localDb.getOutboxSummary()).pending, 0);

      final persisted =
          await localDb.repository.getStoredHubConnection(allowLoopback: true);
      expect(persisted?.hubUrl, newUrl);
      expect(persisted?.hubId, 'MMS-HUB-NEW');
    });

    test('kayıtlı Hub kapalıyken ve keşif boş dönünce kayıtlı URL ve lastVerifiedAt korunur', () async {
      final verifiedAt = DateTime.utc(2026, 11, 20, 7, 30);
      await localDb.repository.saveStoredHubConnection(
        hubUrl: 'http://192.168.1.45:8945',
        hubId: 'MMS-HUB-01',
        source: HubUrlSource.discovered,
        allowLoopback: false,
        verifiedAt: verifiedAt,
      );

      final initialState = await HubConnectionBootstrapper.loadInitialState(
        repository: localDb.repository,
        allowLoopback: false,
      );

      final deadClient = MmsApiClient(
        client: MockClient((_) async => throw const SocketException('Timeout')),
        allowLoopback: false,
      );
      final emptyDiscovery = _StubDiscoveryClient(() => const <DiscoveredHubCandidate>[]);

      final notifier = HubConnectionNotifier(
        repository: localDb.repository,
        checkUrlHealth: deadClient.checkHealthForUrl,
        discoveryClient: emptyDiscovery,
        allowLoopback: false,
        initialState: initialState,
      );
      addTearDown(notifier.dispose);

      final ok = await notifier.ensureConnectedOrDiscover(force: true);
      expect(ok, isFalse);
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

    test('enableAutoLifecycle=true başlangıçta otomatik UDP keşfi çalıştırıp bağlanır', () async {
      final liveServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => liveServer.close(force: true));
      liveServer.listen((HttpRequest req) async {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, dynamic>{
              'status': 'UP',
              'service': 'MARKET_MMS_HUB',
              'sqlite_version': '3.45.1',
            }),
          );
        await req.response.close();
      });

      final responder = await _TestUdpResponder.start(
        httpPort: liveServer.port,
        hubId: 'MMS-HUB-AUTO',
        serverIps: const <String>['127.0.0.1'],
      );
      addTearDown(responder.close);

      final udpClient = UdpHubDiscoveryClient(
        discoveryPort: responder.port,
        bindAddress: InternetAddress.loopbackIPv4,
        overrideTargets: <InternetAddress>[InternetAddress.loopbackIPv4],
        settleAfterFirstMatch: const Duration(milliseconds: 100),
        defaultScheme: 'http',
      );

      final apiClient = MmsApiClient(allowLoopback: true);
      final notifier = HubConnectionNotifier(
        repository: localDb.repository,
        checkUrlHealth: apiClient.checkHealthForUrl,
        discoveryClient: udpClient,
        allowLoopback: true,
        enableAutoLifecycle: true,
        reconnectInterval: const Duration(hours: 1),
        initialState: const HubConnectionState(
          phase: HubConnectionPhase.unconfigured,
          activeHubUrl: null,
          isInitialized: true,
        ),
      );
      addTearDown(notifier.dispose);

      // Başlangıç otomatik keşfinin connected faza geçmesini bekle
      final deadline = DateTime.now().add(const Duration(seconds: 4));
      while (DateTime.now().isBefore(deadline) &&
          notifier.state.phase != HubConnectionPhase.connected) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }

      expect(notifier.state.phase, HubConnectionPhase.connected);
      expect(notifier.state.activeHubUrl, 'http://127.0.0.1:${liveServer.port}');
      expect(notifier.state.source, HubUrlSource.discovered);
    });

    test('WP-1: connected fazındayken reportTransportUnreachable yeni IP keşfini tetikler ve bayat URL hatalarını yok sayar', () async {
      final newServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => newServer.close(force: true));
      newServer.listen((HttpRequest req) async {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, dynamic>{
              'status': 'UP',
              'service': 'MARKET_MMS_HUB',
              'sqlite_version': '3.45.1',
            }),
          );
        await req.response.close();
      });

      final responder = await _TestUdpResponder.start(
        httpPort: newServer.port,
        hubId: 'MMS-HUB-DHCP-NEW',
        serverIps: const <String>['127.0.0.1'],
      );
      addTearDown(responder.close);

      final deadPort = await _reserveDeadLocalPort();
      final oldUrl = 'http://127.0.0.1:$deadPort';
      final newUrl = 'http://127.0.0.1:${newServer.port}';

      final udpClient = UdpHubDiscoveryClient(
        discoveryPort: responder.port,
        bindAddress: InternetAddress.loopbackIPv4,
        overrideTargets: <InternetAddress>[InternetAddress.loopbackIPv4],
        settleAfterFirstMatch: const Duration(milliseconds: 100),
        defaultScheme: 'http',
      );

      final apiClient = MmsApiClient(allowLoopback: true);
      final notifier = HubConnectionNotifier(
        repository: localDb.repository,
        checkUrlHealth: apiClient.checkHealthForUrl,
        discoveryClient: udpClient,
        allowLoopback: true,
        enableAutoLifecycle: true,
        reconnectCooldown: Duration.zero,
        reconnectInterval: const Duration(hours: 1),
        initialState: HubConnectionState(
          phase: HubConnectionPhase.connected,
          activeHubUrl: oldUrl,
          hubId: 'MMS-HUB-OLD',
          source: HubUrlSource.discovered,
          isInitialized: true,
        ),
      );
      addTearDown(notifier.dispose);

      // Başlangıç lifecycle auto-keşfinin yeni sunucuyu bulmasını beklemeden önce
      // yeni test için ayrı bir instance ile temiz senaryo da doğrulayalım:
      final deadline1 = DateTime.now().add(const Duration(seconds: 4));
      while (DateTime.now().isBefore(deadline1) &&
          notifier.state.activeHubUrl != newUrl) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      expect(notifier.state.activeHubUrl, newUrl);
      expect(notifier.state.phase, HubConnectionPhase.connected);

      // 1. Bayat URL'den (oldUrl) gelen hata yeni bağlı URL'yi (newUrl) BOZMAMALI
      notifier.reportTransportUnreachable(
        failedUrl: oldUrl,
        errorMessage: 'Bayat hata',
      );
      expect(notifier.state.phase, HubConnectionPhase.connected);
      expect(notifier.state.activeHubUrl, newUrl);

      // 2. Şimdi yeni sunucu da kapanıp 3. sunucu açılsın -> aktif URL hatasıyla offline + yeniden keşif
      await newServer.close(force: true);
      final thirdServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => thirdServer.close(force: true));
      thirdServer.listen((HttpRequest req) async {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, dynamic>{
              'status': 'UP',
              'service': 'MARKET_MMS_HUB',
              'sqlite_version': '3.45.1',
            }),
          );
        await req.response.close();
      });

      final responder2 = await _TestUdpResponder.start(
        httpPort: thirdServer.port,
        hubId: 'MMS-HUB-DHCP-3',
        serverIps: const <String>['127.0.0.1'],
      );
      addTearDown(responder2.close);

      // responder2'yi kullanacak ikinci notifier:
      final notifier2 = HubConnectionNotifier(
        repository: localDb.repository,
        checkUrlHealth: apiClient.checkHealthForUrl,
        discoveryClient: UdpHubDiscoveryClient(
          discoveryPort: responder2.port,
          bindAddress: InternetAddress.loopbackIPv4,
          overrideTargets: <InternetAddress>[InternetAddress.loopbackIPv4],
          settleAfterFirstMatch: const Duration(milliseconds: 100),
          defaultScheme: 'http',
        ),
        allowLoopback: true,
        enableAutoLifecycle: false,
        reconnectCooldown: Duration.zero,
        initialState: HubConnectionState(
          phase: HubConnectionPhase.connected,
          activeHubUrl: newUrl,
          hubId: 'MMS-HUB-DHCP-NEW',
          source: HubUrlSource.discovered,
          isInitialized: true,
        ),
      );
      addTearDown(notifier2.dispose);

      notifier2.reportTransportUnreachable(
        failedUrl: newUrl,
        errorMessage: 'SocketException',
      );
      expect(notifier2.state.phase, HubConnectionPhase.offline);

      final reconnected = await notifier2.ensureConnectedOrDiscover(force: true);
      expect(reconnected, isTrue);
      expect(notifier2.state.phase, HubConnectionPhase.connected);
      expect(notifier2.state.activeHubUrl, 'http://127.0.0.1:${thirdServer.port}');
    });

    test('WP-1 ProviderContainer: BackgroundSyncCoordinator networkError sonrası HubConnectionNotifier offline olur', () async {
      final deadPort = await _reserveDeadLocalPort();
      final oldUrl = 'http://127.0.0.1:$deadPort';

      await localDb.repository.saveStoredHubConnection(
        hubUrl: oldUrl,
        hubId: 'MMS-HUB-OLD',
        source: HubUrlSource.discovered,
        allowLoopback: true,
      );
      await localDb.repository.createOfflineSale(
        deviceId: 'POS-AND-01',
        paymentMethod: 'CASH',
        items: <CartItemInput>[CartItemInput.units('prod_su', 1)],
      );

      final container = ProviderContainer(
        overrides: [
          localDatabaseServiceProvider.overrideWithValue(localDb),
          hubAllowLoopbackPolicyProvider.overrideWithValue(true),
          hubAutoDiscoveryLifecycleEnabledProvider.overrideWithValue(false),
          initialHubConnectionStateProvider.overrideWithValue(
            HubConnectionState(
              phase: HubConnectionPhase.connected,
              activeHubUrl: oldUrl,
              hubId: 'MMS-HUB-OLD',
              source: HubUrlSource.discovered,
              isInitialized: true,
            ),
          ),
          syncTransportProvider.overrideWithValue(
            _NetworkErrorSyncTransport(),
          ),
          apiClientProvider.overrideWith(
            (ref) => MmsApiClient(
              readBaseUrl: () => ref.read(hubConnectionProvider).activeHubUrl,
              allowLoopback: true,
              deviceId: 'POS-AND-01',
              deviceToken: 'tok_sync_test',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(backgroundSyncCoordinatorProvider.notifier)
          .triggerSync(reason: SyncTriggerReason.manual);

      expect(
        container.read(backgroundSyncCoordinatorProvider).status,
        SyncCoordinatorStatus.networkError,
      );
      expect(
        container.read(hubConnectionProvider).phase,
        HubConnectionPhase.offline,
      );
    });
  });
}

class _NetworkErrorSyncTransport implements SyncTransport {
  static final SyncResponse _netErr = SyncResponse.networkError(
    'Ağ bağlantı hatası (SocketException): Connection refused',
  );

  @override
  Future<SyncResponse> postSale({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      _netErr;

  @override
  Future<SyncResponse> postProductUpsert({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      _netErr;

  @override
  Future<SyncResponse> postStockReceipt({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      _netErr;

  @override
  Future<SyncResponse> getProducts({
    required String hubUrl,
    required String token,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      _netErr;

  @override
  Future<SyncResponse> getSales({
    required String hubUrl,
    required String token,
    int cursor = 0,
    int limit = 50,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      _netErr;

  @override
  Future<SyncResponse> postSyncAck({
    required String hubUrl,
    required String token,
    required String syncSessionId,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      _netErr;

  @override
  void close() {}
}
