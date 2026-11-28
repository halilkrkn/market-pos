# HUB TLS PROVISIONING REPORT (TEST_ONLY)

- **Durum:** `PASS (İzole TEST_ONLY TLS üretimi doğrulandı)` / `BLOCKED (C:\ProgramData\MarketMMS canlı yazımı yönetici yetkisi gerektiriyor — IS_ADMIN=False)`
- **Tarih:** 2026-11-28
- **Bağlam:** [MASTER_HUB_CONNECTIVITY_ROOT_CAUSE_REPORT.md](file:///c:/Users/halil/Github/market-pos/docs/reports/MASTER_HUB_CONNECTIVITY_ROOT_CAUSE_REPORT.md) ve kontrollü test DB sıfırlaması

## Yapılan değişiklikler

1. **Güvenli Yerel Geliştirme Veritabanı Yedekleme ve Kontrollü Sıfırlama:**
   - Uygulama süreçlerinin çalışmadığı (`MARKET_POS_RUNNING=0`) ve `MarketMMSService` servisinin `Stopped` olduğu teyit edildi.
   - `scripts\dev_test\backup_client_db_safe.ps1` çalıştırılarak mevcut `%LOCALAPPDATA%\MarketMMS\client_local.db` için yedek alındı: `C:\Users\halil\MarketMMS_PreInstall_Backups\client_local_pre_reset_20261128.db` (`163840` bayt, `status=BACKUP_VERIFIED_OK`, `integrity_check=ok`, `backup_sha256=437F1017B8F6736F30F15D4E9C17D0D332B8D863BB28C520547A324BFF39AF50`).
   - Yalnızca geliştirme/test amaçlı `client_local.db` (+ `-wal`/`-shm`) sıfırlandı; `backups/`, `backup_schedule_settings.json`, `backup_schedule_state.json`, `client_config.json`, `client_theme.json` ve `secure_tokens.dpapi.json` korundu.
   - Boş şema başlatımı doğrulandı (`EMPTY_DB_SCHEMA=4`, `EMPTY_DB_JOURNAL=wal`, `EMPTY_DB_INTEGRITY=ok`, `settings:0, products:0, sales:0, outbox:0`).
2. **OpenSSL 3.5.9 ile İzole TEST_ONLY Kök CA ve Hub Sunucu Sertifikası Üretimi:**
   - Eski `OpenSSL 0.9.8k` kullanılmadan, yalnızca `C:\Program Files\Git\usr\bin\openssl.exe` (`OpenSSL 3.5.9 29 Sep 2026`) ile sertifika üretildi.
   - Üretim çıktısı: `C:\Users\halil\AppData\Local\MarketMMS_Isolated_Test\test_only_tls\`
     - `ca_private\ca.key`: Hub dağıtım dizininden tamamen izole tutuldu (`CA_KEY_ISOLATED_IN_CA_PRIVATE=True`, `CA_KEY_ABSENT_FROM_HUB_DEPLOY=True`).
     - `hub_deploy\ca.crt`: `CN=Market MMS TEST_ONLY Local Root CA, O=Market MMS TEST_ONLY`, `CA:TRUE`, `Certificate Sign, CRL Sign`, `SHA256=5C78095BCA8B2D8C419158C4E7433F99FAB9EBD32A7B5AE3815A2413E057FA2A`.
     - `hub_deploy\server.crt`: `CN=Market MMS TEST_ONLY Hub, O=Market MMS TEST_ONLY`, `CA:FALSE`, `EKU=TLS Web Server Authentication`, `SAN=IP Address:127.0.0.1, IP Address:192.168.1.158, DNS:localhost`, `SHA256=0C:F2:BF:CB:BC:3E:77:FF:58:72:A0:DA:32:A2:7A:4D:2A:EB:65:AB:17:65:19:B3:30:2F:63:DB:23:B4:15:38`.
     - `openssl verify`: `: OK`.
3. **Geri Alınabilir Yönetici Provisioning Betiği:**
   - [apply_test_only_hub_tls_admin.ps1](file:///c:/Users/halil/Github/market-pos/scripts/dev_test/apply_test_only_hub_tls_admin.ps1) oluşturuldu (`-Rollback` destekli, `ca.key` kopyalamaz, servis ACL'sini ve `MarketMMSService` TLS başlatımını uygular).

## Değiştirilen dosyalar

- [apply_test_only_hub_tls_admin.ps1](file:///c:/Users/halil/Github/market-pos/scripts/dev_test/apply_test_only_hub_tls_admin.ps1) *(yeni yardımcı betik)*
- Depo dışı izole TEST_ONLY sertifikalar: `C:\Users\halil\AppData\Local\MarketMMS_Isolated_Test\test_only_tls\`
- Geliştirme yerel veritabanı: `%LOCALAPPDATA%\MarketMMS\client_local.db` *(kontrollü boş şema reseti; yedek `C:\Users\halil\MarketMMS_PreInstall_Backups\client_local_pre_reset_20261128.db`)*

## Çalıştırılan testler

- PowerShell betik sözdizimi doğrulaması: `apply_test_only_hub_tls_admin.ps1` (`ADMIN_PS1_PARSE_ERRORS=0`)
- OpenSSL 3.5.9 zincir ve X.509 doğrulaması (`openssl verify`)
- `test_spikes\spike_01_backend\test\s3_tls_security_test.dart`
- `test_spikes\spike_01_backend\test\rel01_hub_config_test.dart`
- `test_spikes\spike_01_backend\test\stage6_live_tls_e2e_bidirectional_sync_test.dart` (`Üretilen izole TEST_ONLY TLS sertifikaları OpenSSL 3.5.9 ve MmsX509PreValidator ile uyumludur`)
- `dart analyze` (`test_spikes/spike_01_backend`), `flutter analyze` (kök)

## Test sonuçları

- `test_spikes\spike_01_backend` (8 süit toplamı, `task-2353`): `+108: All tests passed!`, `No issues found!`.
- `stage6_live_tls_e2e_bidirectional_sync_test.dart` Test 1: `CertificateManager.validateRootCaBytes` ve `extractServerCertSanIpv4s` ile gerçek TEST_ONLY `ca.crt` + `server.crt` doğrulandı (`127.0.0.1` ve aktif Wi-Fi SAN IP dahil).
- `apply_test_only_hub_tls_admin.ps1`: `ADMIN_PS1_PARSE_ERRORS=0`.

## Başarısız testler

- Otomatik testlerde başarısız test yok (`0` fail).

## Bilinen riskler

- Bu oturum standart kullanıcı haklarıyla (`IS_ADMIN=False`) çalıştığı için `C:\ProgramData\MarketMMS\certs\` dizinine dosya kopyalama, Windows Firewall kuralları (`scripts\configure_hub_firewall.ps1`) ve `MarketMMSService` servis başlatma adımları henüz çalıştırılamadı.
- TEST_ONLY CA anahtarı (`ca_private\ca.key`) geliştirme makinesindedir; üretim mağaza kurulumunda ayrı ve çevrimdışı korunan üretim CA üretilmelidir.

## Fiziksel olarak doğrulanan işlemler

- OpenSSL 3.5.9 ile üretilen gerçek X.509 `ca.crt` ve `server.crt` dosyalarının SAN, EKU (`serverAuth`) ve `CertificateManager` / `MmsX509PreValidator` uyumluluğu.
- `%LOCALAPPDATA%\MarketMMS\client_local.db` güvenli yedeği ve boş `schemaVersion=4` WAL veritabanı olarak sıfırdan açılması.

## Henüz doğrulanmayan işlemler

- Yönetici PowerShell oturumunda aşağıdaki komutun çalıştırılması:
  ```powershell
  powershell -ExecutionPolicy Bypass -File "C:\Users\halil\Github\market-pos\scripts\dev_test\apply_test_only_hub_tls_admin.ps1"
  ```
- Provisioning sonrasında `C:\ProgramData\MarketMMS\certs\` ACL denetimi ve `https://127.0.0.1:8945/health` canlı servis yanıtı.
