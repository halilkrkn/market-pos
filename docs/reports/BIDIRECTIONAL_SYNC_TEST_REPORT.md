# BIDIRECTIONAL SYNC TEST REPORT

- **Durum:** `PASS (Canlı TLS HTTPS üzerinde Windows ↔ Hub ↔ Android çift yönlü senkronizasyon E2E testle doğrulandı)` / `PENDING (Fiziksel Android cihazla LAN üzeri saha testi)`
- **Tarih:** 2026-11-28
- **Kapsam:** Çift yönlü katalog/stok senkronizasyonu, Outbox FIFO kuyruğu, kesinti-sonrası kurtarma ve idempotency

## Yapılan değişiklikler

- [stage6_live_tls_e2e_bidirectional_sync_test.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/test/stage6_live_tls_e2e_bidirectional_sync_test.dart) oluşturularak gerçek `SpikeDatabase`, iki ayrı yerel `ClientDatabase` (Windows ve Android), gerçek UDP 8946 keşfi ve sıkı TLS CA pinning (`MmsPinnedTlsClientFactory`) üzerinden uçtan uca çift yönlü senkronizasyon senaryosu kodlandı.
- Senkronizasyon çekirdeği (`ClientSyncService`, `ClientStorageRepository`, FIFO Outbox, `client_seq`, idempotency, Half-Up kuruş matematiği) mimari kurallara uygun biçimde değiştirilmeden korundu.

## Değiştirilen dosyalar

- [stage6_live_tls_e2e_bidirectional_sync_test.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/test/stage6_live_tls_e2e_bidirectional_sync_test.dart) *(yeni E2E test dosyası)*

## Çalıştırılan testler

- `packages\mms_client_storage`: `dart analyze` + `dart test` (yedekleme, göç, outbox FIFO, post-restore mutabakat dahil)
- `test_spikes\spike_01_backend`: `dart analyze` + `dart test -j 1` (8 süit, `stage6_live_tls_e2e_bidirectional_sync_test.dart` dahil)
- Kök `flutter test`: `background_sync_coordinator_test.dart`, `sync_reconnect_lifecycle_test.dart`, `hybrid_drive_sync_coordinator_test.dart`, `drive_live_config_provisioning_test.dart`, `hub_connection_management_test.dart`, `udp_hub_discovery_client_test.dart` dahil 14 süit

## Test sonuçları

- `packages\mms_client_storage` (`task-2353`): `No issues found!`, `+265: All tests passed!`.
- `test_spikes\spike_01_backend` (`task-2353`): `No issues found!`, `+108: All tests passed!`.
  - Doğrulanan E2E akışı:
    1. Android ürün ekler (`3450` krş, `25000` mili-birim stok) -> Hub -> Windows `syncProducts()` ile eksiksiz çeker.
    2. Windows ürün ekler (`1990` krş, `40000` mili-birim stok) -> Hub -> `winSync.syncProducts()` -> Android `andSync.syncProducts()` ile eksiksiz çeker.
    3. Hub durdurulur (`hub.server.stop()`); Android çevrimdışı `2` adet satış yapar (`3980` krş); çevrimdışı sync denemesi Outbox'ı silmez (`retry=1`, `failedPermanent=0`).
    4. Hub yeniden açılır; Android backoff sonrası (`syncPendingOutbox`) bekleyen satışı FIFO ile aktarır (`syncedCount=1`, `pending=0`, `retry=0`); Windows `syncSales()` + `syncProducts()` ile satışı ve güncellenmiş `38000` stoğu görür.
- Kök Flutter (`task-2378`): `No issues found!`, `+102: All tests passed!`.

## Başarısız testler

- Otomatik testlerde başarısız test yok (`0` fail).

## Bilinen riskler

- Yerel stok koruması kuralı (`isNeverSyncedLocal`) gereği yerel olarak yeni oluşturulan ve `syncProducts()` ile en az bir kez Hub tarafından teyit edilmemiş ürünlerde ilk `syncProducts()` yerel stoğu korur (`winSync.syncProducts()` normal periyodik döngüde bunu tamamlar).
- Fiziksel Android ↔ Windows Wi-Fi geçişinde gerçek işletim sistemi arka plan/doze davranışı saha testinde izlenmelidir.

## Fiziksel olarak doğrulanan işlemler

- Gerçek SQLite FFI (WAL) veritabanları, gerçek UDP soketi ve gerçek TLS HTTPS soketi üzerinden Windows ve Android istemci simülasyonlarının çift yönlü tam senkronizasyonu ve hub kesintisi sonrası kurtarma.

## Henüz doğrulanmayan işlemler

- Fiziksel Android cihaz ile Windows `MarketMMSService` arasında gerçek Wi-Fi LAN üzerinden ürün ekleme, satış yapma, Wi-Fi kesip/açma ve çift yönlü senkronizasyon kabul testi.
