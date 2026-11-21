# ADR 015: REL-01 — Windows Hub için Tek Doğrulanmış Yapılandırma Kaynağı

- **Durum:** **CONFIRMED** (Mevcut tek `hub_config.json` yaklaşımı ve kod düzeltmeleri Owner tarafından onaylandı; fiziksel SCM/ACL/firewall doğrulaması hâlâ **BLOCKED**)
- **Tarih:** 2026-11-21
- **Karar Vericiler:** Owner (Onay), Öneren: Claude Code / Uygulayan: Antigravity (Ek B)

---

## 1. Bağlam

Depoda birbiriyle çelişen üç servis/başlatma tanımı vardı: `service_wrapper/winsw.xml` (port 8080, TLS yok, `spike_service.exe`), `service_wrapper/MarketMMSService.xml` (port 8085, TLS), `start_master_hub.bat` ve firewall betiği (port 8945, HTTP). Hub'ın kod içi varsayılan portu 8080'di. Admin secret bazı uçlarda koda gömülü `adm_sec` fallback'ine düşüyordu.

## 2. Karar

- Hub, `--config=<yol>` ile verilen `hub_config.json` dosyasını **tek** kaynak olarak okur (`lib/config/hub_config.dart`). `--config` başka bayraklarla veya ortam değişkenleriyle karıştırılamaz (çelişki riski; çıkış kodu 64).
- Doğrulama (fail-fast, çıkış kodu 78): port aralığı, port ≠ discovery port, bilinmeyen anahtar (yazım hatası) reddi, TLS açıkken sertifika/anahtar dosyalarının varlığı, üretimde TLS ve tenant/store başlık zorunluluğu, yapılandırmada düz metin `admin_secret` yasağı (yalnızca ACL korumalı `admin_secret_file`).
- Tek üretim WinSW tanımı: `MarketMMSService.xml` yalnızca `--config="%BASE%\..\config\hub_config.json"` geçirir; LocalService hesabı korunur. Çelişen `winsw.xml` kaldırıldı.
- `install_mms_service.ps1`: şablondan config oluşturur ama **mevcut config'i asla ezmez**, admin secret'ı kriptografik rastgele üretir (ekrana yazmaz), sertifika yoksa kurulumu durdurur, kurulum sonunda servis durumu + TCP health check yapar.
- `configure_hub_firewall.ps1`: kurulu `hub_config.json` varsa portları oradan okur.
- Şablon: `test_spikes/spike_01_backend/config/hub_config.example.json` (8945/8946, TLS açık, üretim).

## 3. Sonuçlar

- **Olumlu:** Port/TLS/dizin/tenant değerleri tek yerde; çelişki depo testleriyle (`test/rel01_hub_config_test.dart`) yakalanır.
- **Açık:** `MarketMmsSpike01.xml` (yalnızca spike test servisi, `MMS_ENV=test_spike`) yerinde bırakıldı; makinede kurulu olabileceği için silinmedi. Owner onayıyla kaldırılması önerilir. Gerçek SCM kurulum/güncelleme/kaldırma ve ACL testleri **fiziksel olarak çalıştırılmadı** (BLOCKED, bkz. nihai rapor).

---

## Ek A — 21.11.2026 (3. oturum): Kurulum betiği güncelleme sırası, kodlama ve firewall kapsamı

Durum: **CONFIRMED** (Ek A + Ek B kod/betik olarak uygulandı ve Windows PowerShell 5.1 ayrıştırma testinden geçti; gerçek SCM/ACL/firewall çalıştırması hâlâ **BLOCKED** — yönetici yetkili kurulum ortamı gerekir).

1. **Kodlama (kritik):** `setup_service_acls.ps1` ve `uninstall_mms_service.ps1` BOM'suz UTF-8 idi. Windows PowerShell 5.1 (Windows'un varsayılanı; bu makinede `pwsh` yok) bu dosyaları ANSI okur; `—` karakterinin 0x94 baytı `”` akıllı tırnağına dönüşüp string'i sonlandırır → betikler **ayrıştırılamıyordu** (7 + 1 ayrıştırma hatası). Kurulum betiği adım 3'te ACL betiğini çağırdığı için kurulum varsayılan kabukta çalışamazdı. Düzeltme: Türkçe/Unicode içeren tüm `.ps1` dosyalarına UTF-8 BOM eklendi (içerik değişmedi). Regresyon testi: `rel01_hub_config_test` "PowerShell betikleri Windows PowerShell 5.1 ile doğru okunur".
2. **Güncelleme sırası:** `install_mms_service.ps1` (v2.1) ikilileri, çalışan servis **durdurulduktan sonra** kopyalar (önceden çalışan `mms_backend.exe` kilitliyken kopyalamaya çalışıp güncellemeyi başarısız yapıyordu). Yapılandırma/secret/TLS kontrolleri çalışan servise dokunmadan önce yapılır. WinSW `install`/`start` çıkış kodları kontrol edilir.
3. **Otomatik geri dönüş:** Önceki ikililer `bin.previous` altında saklanır; yeni sürüm başlamaz veya sağlık kontrolü (servis `Running` + TCP portu) geçmezse önceki ikililere dönülüp servis yeniden başlatılır ve hata bildirilir. **Sınır:** DB geri alınmaz; şema yükselten bir sürümde geri dönüş öncesi şifreli yedek alınmalıdır (runbook).
4. **Firewall kapsamı:** Kurallar varsayılan olarak `-RemoteAddress LocalSubnet` ile sınırlandı (önceden tüm uzak adresler). Farklı VLAN topolojisi için `-RemoteAddress "a.b.c.0/24,..."`.
5. **PAIR-CA (üretimi engelleyen boşluk):** Üretim `main()` eşleştirme kök CA sertifikasının yolunu sunucuya hiç geçirmiyordu ve `hub_config.json`'da bunun için anahtar yoktu. `tls.ca_cert` (yalnızca genel CA sertifikası) eklendi; üretimde zorunlu, verilirse dosya var olmalı (fail-fast, çıkış kodu 78). Kurulum betiği `certs\ca.crt` yoksa çalışan servise dokunmadan durur.

---

## Ek B — 21.11.2026 (Teknik Düzeltme Oturumu): Tek Konfigürasyon Tutarsızlığının Giderilmesi (`CONFIRMED`)

- **Ortam Değişkeni Sızıntısı Giderildi:** `--config=<yol>` ile yapılandırma verildiğinde `resolveHubStartupConfig` artık `ROOT_CA_CERT_FILE` ortam değişkenine fallback yapmaz (yalnızca `hub_config.json` `tls.ca_cert` ve açık `--ca-cert=` CLI bayrağı geçerlidir; `--config` olmayan geliştirme başlatmalarında geriye dönük env fallback korunur).
- **Eşleştirme Uçları Tutarlılığı:** `/api/v1/pairing/session` ve `/api/v1/pairing/ca-cert` rotalarındaki `Platform.environment['ROOT_CA_CERT_FILE']` fallback'i kaldırıldı; yalnızca sunucuya yapılandırmadan geçirilen `caCertPath` kullanılır.
- **Sıkı `tls` Şeması ve Fail-Closed Davranış:** `hub_config.json` içindeki `tls` bloğunda yalnızca `enabled`, `cert`, `key`, `ca_cert` anahtarları kabul edilir (bilinmeyen anahtar reddedilir). `requireTls == true` iken CA sertifikası yoksa veya okunamıyorsa (`FileSystemException` dahil) `/api/v1/pairing/session` `UNKNOWN` üretmek yerine `503 ERR_CA_CERT_UNAVAILABLE` ile fail-closed reddeder.
- **Ek Güvenlik ve Yapılandırma Sertleştirmeleri (`H-3`, `M-1`, `M-2`):**
  - `--config=` ile başlatılan sunucuda `allowAdminEnvFallback: false` uygulanır; `/api/v1/admin/*`, `/api/v1/backup/snapshot`, `/api/v1/admin/shutdown` ve `/api/v1/devices/revoke` hiçbir şekilde `Platform.environment['ADMIN_SECRET']` sızıntısını kabul etmez (`startHubFromArgs(..., environment: ...)` gerçek başlangıç akışı ve HTTP istekleriyle doğrulandı).
  - `POST /api/v1/devices/revoke` artık `_denyIfNotLoopback` (fail-closed loopback) ve `x-mms-admin-secret` desteğine tabidir.
  - `hub_config.json` içinde `backup_dir` atlanırsa `System32`/çalışma dizini yerine yapılandırma dizini altında `backups` varsayılan alınır ve tüm Hub rotaları `_backupTargetDir` kullanır.
  - `POST /api/v1/admin/restore` bozuk/nesne olmayan JSON gövdesinde `500` yerine `400 ERR_INVALID_JSON` döner.
- **Doğrulama Sınırı:** `rel01_hub_config_test`, `s4_device_pairing_test`, `s1_api_hardening_test`, `s2_token_security_test` ve `s3_tls_security_test`. Gerçek Windows SCM servis kurulumu/güncellemesi/geri dönüşü (`install_mms_service.ps1`), standart kullanıcı ACL ve firewall çalıştırmaları gerçek makinede yapılmadığı için **BLOCKED** kalmaya devam eder.
