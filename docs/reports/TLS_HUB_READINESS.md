# MARKET MMS — TLS Hub Hazırlık ve Doğrulama Raporu (`TLS_HUB_READINESS`)

**Tarih:** 2026-11-27

**Kapsam:** Stage F — İzole Hub TLS Sertifika Matrisi, SAN Kısıtlamaları, Rotasyon, Süre/CA Fail-Closed Kontrolleri ve `server.key` ACL Doğrulaması (`TCP 8947` / `UDP 8948`)

**Durum:** İzole canlı `mms_backend.exe` + `OpenSSL 3.5.9` + üretim `MmsTlsHealthProbe` doğrulaması **PASS (`6/6`)**; gerçek Windows Service / `NT SERVICE\MarketMMSService` altında üretim sertifikası provizyonu (`C:\ProgramData\MarketMMS\certs\`) elevated/fiziksel kurulumda **BLOCKED** (beklemede).

---

## 1. Test Ortamı ve İzolasyon Kanıtı

- **Test Kökü:** `%LOCALAPPDATA%\MarketMMS_Isolated_Test\tls_matrix\`
- **Kullanılan Hub İkilisi:** `dist\windows_release_v1_0_0_tray\hub_bin\mms_backend.exe` (`lib\sqlite3.dll` izole kopyası ile)
- **OpenSSL Sürümü:** `OpenSSL 3.5.9 29 Sep 2026 (Library: OpenSSL 3.5.9 29 Sep 2026)` (`C:\Program Files\Git\usr\bin\openssl.exe`; Not: `C:\OpenSSL\bin\openssl.exe` içindeki eski `0.9.8k` modern SAN/CA doğrulamaları için kullanılmadı)
- **Kullanılan Portlar:** `TCP 8947`, `UDP 8948` (konak `8085`, `8945`, `8946` kullanılmadı; `Cert:\*` ve sistem saatine dokunulmadı)
- **Öretilen Geçerli SAN Profili:** `IP:127.0.0.1,IP:10.0.2.2,DNS:localhost,IP:192.168.56.1`
- **İstemci Doğrulayıcısı:** [`mms_installer_engine.ps1`](file:///c:/Users/halil/Github/market-pos/installer/windows/scripts/mms_installer_engine.ps1#L1309-L1719) içindeki üretim `MmsTlsHealthProbe::VerifyHttpsHealth` sınıfı (`AllowUnknownCertificateAuthority` + tekil canonical Root CA byte eşleştirmesi + IP/DNS SAN denetimi + `TLS 1.2/1.3` zorunluluğu).

---

## 2. TLS Matrisi Doğrulama Sonuçları (`task-1297`)

| Senaryo | Beklenen Davranış | Gerçek Gözlem / Çıktı | Sonuç |
|---|---|---|---|
| **T1 — Geçerli Root CA + Leaf Sertifika & `server.key` ACL** | Hub HTTPS `8947` üzerinde ayağa kalkar; `ca.crt` pinli istemci `200 UP` alır; `server.key` üzerinde `Users` yetkisi bulunmaz. | `http_status: UP`, `thumbprint: DA14755DEAE75E07E8D00812D02CEC20F594F2BA`, `serial: 62FDF0E8EF95525569CC5A9CC3EE52D828CC4362`. `icacls` çıktısı: `HALILKRKN\halil:(R)`, `BUILTIN\Administrators:(F)`, `NT AUTHORITY\SYSTEM:(F)` (kalıtım kapalı, `Users`/`Everyone` yok). | **PASS** |
| **T2 — Aynı Root CA Altında Leaf Sertifika Rotasyonu** | `ca.crt` değişmeden yeni `server.crt`/`server.key` yüklendiğinde mevcut pinli istemci kesintisiz `200 UP` alır. | Thumbprint `DA14755D...` → `CC1DADC9FFE4391D28C9FC995D5888B982BEE920` olarak değişti; aynı `ca.crt` ile `VerifyHttpsHealth` `UP` döndü. | **PASS** |
| **T3 — Süresi Dolmuş Leaf Sertifika (`NotAfter: 2024-01-02`)** | Sistem saati değiştirilmeden üretilen süresi geçmiş sertifika TLS istemci doğrulaması tarafından reddedilir. | `[TLS_VALIDATION_FAILED] Sunucu sertifikasinin suresi gecmis veya henuz baslamamis.` hatasıyla fail-closed reddedildi. *(Ek bulgu: `CertificateManager` PEM bloğu dışındaki `-notext` olmayan metinleri de `ERR_SERVER_CERT_INVALID` ile reddeder.)* | **PASS (Fail-Closed)** |
| **T4 — Farklı / Sahte Root CA (`rogue_ca.crt`) İmzalı Leaf** | Geçerli SAN ve tarihlere rağmen farklı CA ile imzalı sertifika reddedilir. | `[TLS_VALIDATION_FAILED] Sertifika zincir hatasi: Sertifika zinciri güvenilen bir kök yetkili kullanılarak oluşturulamaz.` hatasıyla fail-closed reddedildi. | **PASS (Fail-Closed)** |
| **T5 — `127.0.0.1` Loopback SAN Eksikliği** | [`server.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart#L5841-L5845) gereği `IP:127.0.0.1` içermeyen sertifika ile Hub açılmamalıdır. | `mms_backend.exe` **`ExitCode 78`** ve `ERR_SERVER_CERT_MISSING_LOOPBACK_SAN` çıktısıyla açılışta fail-fast durdu (`started: false`). Ayrıca `stage3` Test 23 `MmsTlsHealthProbe` istemci tarafı SAN reddini doğrulamıştır. | **PASS (Fail-Closed)** |
| **T6 — Sertifikasız İlk Kurulum (`ALLOW_DEFERRED_TLS_START=1`)** | Sertifikasız MSI kurulumunda kurulum Exit `0` tamamlanır ancak servis `PENDING_TLS_PROVISIONING` (`Stopped`) durumunda bekler. | `install_manifest.json` `service_state: PENDING_TLS_PROVISIONING`, `sandbox_scm.json` `status: Stopped`. | **PASS** |

**Temizlik & Çıkış Teyidi:** `TLS_MATRIX_EXIT=0`, `TCP_8947_LISTEN=0`, `UDP_8948_EP=0`, `MMS_BACKEND_PROCS=0`.

---

## 3. Üretim Kurulumunda TLS Sağlama Gereksinimleri (Owner / Sahip Notları)

1. Üretim kurulumunda `OpenSSL 3.x` (ör. `C:\Program Files\Git\usr\bin\openssl.exe`) kullanılmalı; eski `OpenSSL 0.9.8k` ile SAN üretilmemelidir.
2. `ca.key` asla Hub veya mağaza cihazlarında tutulmaz; `C:\ProgramData\MarketMMS\certs\` içine yalnızca **`ca.crt`**, **`server.crt`** (mutlaka `IP:127.0.0.1` + aktif LAN IPv4 + `DNS:localhost` SAN'lı ve saf PEM `-notext`) ve **`server.key`** konur.
3. Üretim ortamında `server.key` üzerinde `setup_service_acls.ps1` ile yalnızca `SYSTEM:(F)`, `Administrators:(F)` ve `NT SERVICE\MarketMMSService:(R)` hakları bulunur.
4. Konak üzerinde henüz gerçek sertifika provizyonu yapılmamıştır (`BLOCKED` — elevated/fiziksel kurulum adımı beklenmektedir).
