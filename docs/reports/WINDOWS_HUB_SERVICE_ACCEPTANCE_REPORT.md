# WINDOWS HUB SERVICE ACCEPTANCE REPORT (TEST_ONLY)

- **Durum:** `PASS (İzole canlı TLS Hub + AOT ikili derlemesi doğrulandı)` / `BLOCKED (Canlı MarketMMSService SCM başlatma yönetici yetkisi gerektiriyor — IS_ADMIN=False)`
- **Tarih:** 2026-11-28
- **Bağlam:** `MarketMMSService` canlı TLS çalıştırma hazırlığı ve `MarketMmsSpike01` izolasyon doğrulaması

## Yapılan değişiklikler

1. **Sunucu TLS Başlangıç ve Discovery Yapılandırması:**
   - [server.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart) içinde `HubDiscoveryResponder` kurulumuna `tlsEnabled`, `advertiseHost`, `certSanIps` ve `lanIpsProvider` parametreleri geçirildi.
   - `main()` giriş noktasında `TlsConfigurationException` (`exit 78`) ve başlangıç hataları yakalanıp gizli bilgi içermeyen (redacted) hata günlüğüyle raporlanır hale getirildi.
2. **Yönetici Servis Provisioning Betiği:**
   - [apply_test_only_hub_tls_admin.ps1](file:///c:/Users/halil/Github/market-pos/scripts/dev_test/apply_test_only_hub_tls_admin.ps1) oluşturuldu (`server.crt`, `server.key`, `ca.crt` kopyalama, ACL ayarı, `scripts\configure_hub_firewall.ps1` ve `MarketMMSService` yeniden başlatma + `-Rollback`).
3. **Güncel Dart AOT & MSI Paketlemesi:**
   - `mms_backend.exe` (`9994240` bayt, `SHA-256: C3841BB7A26DB578787D1F4F0090EA67C40EE89EEBC2D1A1B3A585176692A2C4`) derlendi ve `MarketMMS-Setup-1.0.1-x64.msi` içine paketlendi.

## Değiştirilen dosyalar

- [server.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart)
- [apply_test_only_hub_tls_admin.ps1](file:///c:/Users/halil/Github/market-pos/scripts/dev_test/apply_test_only_hub_tls_admin.ps1)

## Çalıştırılan testler

- `test_spikes\spike_01_backend\test\rel01_hub_config_test.dart`
- `test_spikes\spike_01_backend\test\pblock_1_3_hub_test.dart`
- `test_spikes\spike_01_backend\test\stage6_live_tls_e2e_bidirectional_sync_test.dart`
- Windows ortam salt-okunur SCM kontrolü (`MarketMMSService` ve `MarketMmsSpike01` yokluğu)
- `powershell -ExecutionPolicy Bypass -File scripts\build_windows_installer.ps1 -Configuration Release -OutputDir dist\test_only_1.0.1-b2 -OverrideVersion 1.0.1`

## Test sonuçları

- `test_spikes\spike_01_backend` (8 süit, `task-2353`): `+108: All tests passed!`, `No issues found!`.
- Salt-okunur ortam denetimi: `MarketMMSService` mevcut (`Stopped` — önceki v1.0.0 kurulumundan kalan durum), `MarketMmsSpike01` mevcut değil (`0` adet).
- `MarketMMS-Setup-1.0.1-x64.msi` (`23076864` bayt, `SHA256: ECA70C9F66E60AFD0405BB6AF958B0BA51D44EF2E5241A42C59C9836F6422FD2`): `ProductVersion=1.0.1`, `PURGE_USER_DATA=0`, `ALLOW_DEFERRED_TLS_START=1`.

## Başarısız testler

- Otomatik testlerde başarısız test yok (`0` fail).

## Bilinen riskler

- `IS_ADMIN=False` nedeniyle canlı Windows Service Control Manager (`MarketMMSService`) üzerinde `Start-Service` / crash recovery / ACL doğrulaması bu oturumda yürütülemedi.
- Otomatik `msiexec` çalıştırılmadığı için `1.0.1` MSI upgrade akışı sahibi tarafından manuel yürütülmelidir.

## Fiziksel olarak doğrulanan işlemler

- Yerel döngü ve LAN soketi üzerinde gerçek `SpikeServer` TLS süreç başlatması (`stage6_live_tls_e2e_bidirectional_sync_test.dart`).
- `MarketMmsSpike01` servisinin makinede ve yeni MSI bileşenlerinde bulunmadığı.
- `mms_backend.exe` AOT ikilisinin ve `MarketMMS-Setup-1.0.1-x64.msi` kurulum paketinin hatasız üretimi.

## Henüz doğrulanmayan işlemler

- Yönetici PowerShell ile TEST_ONLY MSI kurulumu (gerekirse) ve ardından:
  ```powershell
  powershell -ExecutionPolicy Bypass -File "C:\Users\halil\Github\market-pos\scripts\dev_test\apply_test_only_hub_tls_admin.ps1"
  ```
- Canlı `MarketMMSService` durumu (`Running`), UDP 8946 yanıtı ve `https://127.0.0.1:8945/health` / `https://192.168.1.158:8945/health` doğrulaması.
- Windows SCM kurtarma (servis durdurma/yeniden başlatma) ve standart kullanıcı ACL erişim reddi testi.
