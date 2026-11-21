import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/core/network/api_response.dart';
import 'package:market_pos/core/security/tls_pinned_client_factory.dart';
import 'package:market_pos/features/setup/setup_providers.dart';
import 'package:market_pos/features/sync/application/hub_connection_notifier.dart';
import 'package:market_pos/features/sync/domain/hub_connection_state.dart';
import 'package:market_pos/features/sync/domain/hub_discovery_client.dart';
import 'package:market_pos/features/sync/infrastructure/udp_hub_discovery_client.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

class _HttpsFakeDiscoveryClient implements HubDiscoveryClient {
  final Map<String, dynamic> payload;
  final String Function() schemeResolver;

  _HttpsFakeDiscoveryClient(this.payload, this.schemeResolver);

  @override
  Future<List<DiscoveredHubCandidate>> discover({
    required String deviceId,
    Duration timeout = const Duration(milliseconds: 2500),
    int probeCount = 3,
    Duration probeInterval = const Duration(milliseconds: 600),
  }) async {
    final candidate = DiscoveredHubCandidate.tryFromUdpPayload(
      payload,
      responderIp: '192.168.1.20',
      scheme: schemeResolver(),
    );
    return candidate == null ? const [] : [candidate];
  }
}

/// TLS-DISC (istemci tarafı, protokol DEĞİŞMEDEN) — UDP keşif yanıtı şema bilgisi
/// taşımaz (`service`, `protocol_version`, `hub_id`, `http_port`, `server_ips`).
/// Üretim Hub'ı yalnızca TLS kabul eder ve release APK'da cleartext kapalıdır;
/// keşfedilen adaylar `http://` olarak denenirse üretimde keşif hiçbir zaman
/// bağlanamaz. Cihaz eşleştirilmiş (CA pin'i var) ise adaylar `https://` olarak
/// denenir ve sabitlenmiş sertifikayla doğrulanır; pin yoksa (geliştirme Hub'ı)
/// davranış eskisi gibi `http://` kalır. HTTPS başarısızsa HTTP'ye DÜŞÜLMEZ.
void main() {
  const pin = PinnedTlsConfig(expectedSha256Hex: 'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789');
  final payload = <String, dynamic>{
    'service': 'market_mms_hub',
    'protocol_version': '1.0',
    'hub_id': 'MMS-HUB-MASTER',
    'http_port': 8945,
    'server_time': '2026-11-21T10:00:00Z',
    'server_ips': ['192.168.1.20'],
  };

  test('1. Eşleştirilmiş cihaz (CA pin var): keşif adayları yalnızca https:// üretir', () {
    final container = ProviderContainer(overrides: [pinnedTlsConfigProvider.overrideWithValue(pin)]);
    addTearDown(container.dispose);

    final client = container.read(hubDiscoveryClientProvider) as UdpHubDiscoveryClient;
    expect(client.effectiveScheme, 'https');

    final candidate = DiscoveredHubCandidate.tryFromUdpPayload(
      payload,
      responderIp: '192.168.1.20',
      scheme: client.effectiveScheme,
    )!;
    final urls = candidate.candidateBaseUrls(allowLoopback: false);
    expect(urls, isNotEmpty);
    expect(urls.every((u) => u.startsWith('https://')), isTrue, reason: 'HTTP aday (downgrade) üretilmemeli: $urls');
  });

  test('2. Pin yoksa (geliştirme / TLS\'siz yerel Hub) davranış değişmez: http://', () {
    final container = ProviderContainer(overrides: [pinnedTlsConfigProvider.overrideWithValue(null)]);
    addTearDown(container.dispose);

    final client = container.read(hubDiscoveryClientProvider) as UdpHubDiscoveryClient;
    expect(client.effectiveScheme, 'http');
  });

  test('2b. Pin sonradan (eşleştirme) değişince keşif sağlayıcısı yeniden kurulmaz; şema güncel pini izler', () {
    final pinState = StateProvider<PinnedTlsConfig?>((ref) => null);
    final container = ProviderContainer(overrides: [
      pinnedTlsConfigProvider.overrideWith((ref) => ref.watch(pinState)),
    ]);
    addTearDown(container.dispose);

    final before = container.read(hubDiscoveryClientProvider) as UdpHubDiscoveryClient;
    expect(before.effectiveScheme, 'http');
    container.read(pinState.notifier).state = pin; // cihaz eşleştirildi
    final after = container.read(hubDiscoveryClientProvider) as UdpHubDiscoveryClient;
    expect(identical(before, after), isTrue, reason: 'hubConnectionProvider durumunu sıfırlamamalı');
    expect(after.effectiveScheme, 'https');
  });

  test('3. Keşif yanıtı biçimi değişmedi (eski Hub ile uyumlu): şema alanı beklenmez', () {
    final candidate = DiscoveredHubCandidate.tryFromUdpPayload(payload, responderIp: '192.168.1.20', scheme: 'https');
    expect(candidate, isNotNull);
    expect(payload.containsKey('tls'), isFalse);
  });

  test('4. ADR-018: HubConnectionNotifier.discoverAndConnect yalnızca https:// yoklar, hatada http:// fallback yapmaz', () async {
    final db = ClientDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = ClientStorageRepository(db);
    final probedUrls = <String>[];

    final notifier = HubConnectionNotifier(
      repository: repo,
      discoveryClient: _HttpsFakeDiscoveryClient(payload, () => 'https'),
      allowLoopback: false,
      initialState: const HubConnectionState(
        phase: HubConnectionPhase.needsDiscovery,
        isInitialized: true,
      ),
      checkUrlHealth: (url) async {
        probedUrls.add(url);
        return CentralHealthResponse.tlsPinMismatch(
          errorMessage: 'GÜVENLİK UYARISI: pin uyuşmuyor',
        );
      },
    );
    addTearDown(notifier.dispose);

    final connected = await notifier.discoverAndConnect();
    expect(connected, isFalse);
    expect(probedUrls, ['https://192.168.1.20:8945']);
    expect(probedUrls.any((u) => u.startsWith('http://')), isFalse);
  });
}
