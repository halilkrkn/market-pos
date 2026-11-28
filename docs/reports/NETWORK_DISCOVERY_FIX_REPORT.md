# NETWORK DISCOVERY FIX REPORT

- **Durum:** `PASS (Otomatik birim/widget ve canlı UDP+TLS doğrulamaları tamamlandı)`
- **Tarih:** 2026-11-28
- **Kök Neden:** VirtualBox Host-Only (`192.168.84.2`) arayüzünün LAN IP adayı olarak duyurulması, şemasız IP girdilerinde HTTP varsayılanı ve süresi dolmuş (stale) `discovered` kayıtların başlangıçta korunması.

## Yapılan değişiklikler

1. **Hub LAN Arayüz Seçimi ve Filtreleme (Sunucu Tarafı):**
   - [hub_lan_address_resolver.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/network/hub_lan_address_resolver.dart): `'host-only'` anahtar sözcüğü `_excludedKeywords` listesine eklendi; `resolveDiscoveryLanIps` ve `selectDiscoveryLanIpsFromCandidates` eklendi (`advertiseHost` öncelikli, Tier 1 ağ geçitli donanım NIC'i -> ağ geçitsiz donanım -> Tier 2 köprülü vSwitch, SAN sıralaması ve tekilleştirme).
   - [discovery_responder.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/discovery/discovery_responder.dart): `tlsEnabled`, `advertiseHost`, `serverCertSanIpv4s`, `lanIpsProvider` eklendi; yanıtta `'scheme': tlsEnabled ? 'https' : 'http'` yayımı eklendi (`tls`/`ca_*` eklenmeden); Windows `getLocalLanIps()` sanal NIC ve `'host-only'` filtrelemesine bağlandı.
2. **İstemci UDP Keşfi, HTTPS Normalizasyonu ve Stale Discovery TTL:**
   - [discovered_hub_candidate.dart](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/models/discovered_hub_candidate.dart): Varsayılan şema `'https'` yapıldı ve sunucudan gelen `'scheme': 'https'` değeri HTTP'ye düşürülmeden korundu.
   - [hub_url_validator.dart](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/models/hub_url_validator.dart): `normalizeUserInput(..., defaultScheme = 'https')` parametresi eklendi.
   - [app_constants.dart](file:///c:/Users/halil/Github/market-pos/lib/core/constants/app_constants.dart): `defaultBackendBaseUrl` ve `windowsLocalhostFallbackUrl` HTTPS standardına çekildi.
   - [udp_hub_discovery_client.dart](file:///c:/Users/halil/Github/market-pos/lib/features/sync/infrastructure/udp_hub_discovery_client.dart): `defaultScheme = 'https'`, yerel ağ filtrelemesine `'host-only'` eklendi.
   - [hub_connection_notifier.dart](file:///c:/Users/halil/Github/market-pos/lib/features/sync/application/hub_connection_notifier.dart) ve [main.dart](file:///c:/Users/halil/Github/market-pos/lib/main.dart): `HubConnectionBootstrapper.loadInitialState` için `maxDiscoveredAge` (`24 saat`) eklendi; süresi dolmuş `HubUrlSource.discovered` kayıtları otomatik temizlenir. `hubDiscoveryClientProvider` daima `'https'` şeması kullanır.
   - [hub_connection_controls.dart](file:///c:/Users/halil/Github/market-pos/lib/features/diagnostics/presentation/widgets/hub_connection_controls.dart): Kullanıcı ipucu metni `Örn: 192.168.1.158 veya https://192.168.1.158:8945` olarak güncellendi.

## Değiştirilen dosyalar

- [hub_lan_address_resolver.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/network/hub_lan_address_resolver.dart)
- [discovery_responder.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/discovery/discovery_responder.dart)
- [server.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart)
- [discovered_hub_candidate.dart](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/models/discovered_hub_candidate.dart)
- [hub_url_validator.dart](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/models/hub_url_validator.dart)
- [app_constants.dart](file:///c:/Users/halil/Github/market-pos/lib/core/constants/app_constants.dart)
- [udp_hub_discovery_client.dart](file:///c:/Users/halil/Github/market-pos/lib/features/sync/infrastructure/udp_hub_discovery_client.dart)
- [hub_connection_notifier.dart](file:///c:/Users/halil/Github/market-pos/lib/features/sync/application/hub_connection_notifier.dart)
- [main.dart](file:///c:/Users/halil/Github/market-pos/lib/main.dart)
- [hub_connection_controls.dart](file:///c:/Users/halil/Github/market-pos/lib/features/diagnostics/presentation/widgets/hub_connection_controls.dart)
- Test dosyaları: `hub_discovery_lan_filtering_test.dart`, `hub_connection_storage_test.dart`, `discovery_tls_scheme_test.dart`, `udp_hub_discovery_client_test.dart`, `hub_connection_management_test.dart`, `connectivity_recovery_tls_pairing_test.dart`, `stage6_live_tls_e2e_bidirectional_sync_test.dart`

## Çalıştırılan testler

- `packages\mms_client_storage`: `dart analyze` + `dart test`
- `test_spikes\spike_01_backend`: `dart analyze` + `dart test -j 1` (8 süit)
- Kök proje: `flutter analyze` + 14 güvenlik/senkronizasyon/üretim test süiti

## Test sonuçları

- `packages\mms_client_storage`: `No issues found!`, `+265: All tests passed!` (`task-2353`).
- `test_spikes\spike_01_backend`: `No issues found!`, `+108: All tests passed!` (`task-2353`, `hub_discovery_lan_filtering_test.dart`, `hub_discovery_responder_test.dart`, `stage6_live_tls_e2e_bidirectional_sync_test.dart` dahil).
- Kök Flutter (`1.0.1+2` sürüm artışı sonrası `task-2378`): `No issues found! (ran in 8.4s)`, `+102: All tests passed!`.

## Başarısız testler

- Otomatik testlerde başarısız test yok (`0` fail).

## Bilinen riskler

- Gerçek LAN üzerinde Windows ↔ fiziksel Android UDP yayın geçişi (`UDP 8946`) yerel Wi-Fi yönlendirici AP isolation / firewall ayarlarına bağlıdır; henüz fiziksel Android cihazla test edilmedi.

## Fiziksel olarak doğrulanan işlemler

- Geliştirici makinesindeki yerel döngü UDP 8946 + aktif Wi-Fi IP (`192.168.1.158`) keşfi (`stage6_live_tls_e2e_bidirectional_sync_test.dart`).
- VirtualBox Host-Only (`192.168.84.x`) adaylarının seçilmemesi.

## Henüz doğrulanmayan işlemler

- Fiziksel Android telefon ile aynı Wi-Fi ağında çalışan canlı `MarketMMSService` UDP keşfi ve manuel `https://192.168.1.158:8945` bağlantısı (`adb devices` şu an boş).
