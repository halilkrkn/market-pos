# MARKET MMS — Fiziksel Test & Pilot Hazırlık Nihai Karar Raporu (`PHYSICAL_TEST_GO_NO_GO_DECISION`)

**Tarih:** 2026-11-27

**Değerlendirme Kapsamı:** Stages A–O Sonrası Teknik Hazırlık, Güvenlik Sınırları ve Fiziksel Kabul Geçiş Kararı

**Genel Başlık:** **İlk Fiziksel Fresh Install & Kontrollü Saha Kabul Testine Geçiş → `CONDITIONAL GO` | Doğrudan Gerçek Mağaza Üretim Pilotu → `NO-GO`**

---

## 1. Altı Katmanlı Ayrı Nihai Karar (§18)

> [!IMPORTANT]
> Bu karar tablosu yalnızca bu oturumda **fiilen yürütülen** otomatik testler, canlı izole `https://127.0.0.1:8947` Hub doğrulamaları, WiX COM incelemeleri ve konak denetimine dayanır; konakta yükseltilmiş (`Administrator`) kurulum, fiziksel Android cihaz, ticari kod imzalama sertifikası veya canlı Google hesabı **simüle edilmeden** mevcut olmayan dış bağımlılıklar açıkça `BLOCKED` / koşul olarak ayrılmıştır.

| Hedef Aşama | Karar | Kanıta Dayalı Gerekçe & Açık Koşul |
|---|---|---|
| **1. Fresh Install v1.0.0** | **`CONDITIONAL GO`** | `MarketMMS-Setup-1.0.0-x64.msi` (`23064576` B, SHA-256 `183B014FD6ED80785E4302388A2362D020DAD300D3BDEE21317450EE73CA820C`, `LinkType=''`) `0` WiX hatası, `0` `Spike01` referansı ve NTFS HardLink izolasyonu düzeltmesiyle üretildi; `+31` installer testinden ve `20/20` izole yaşam döngüsü doğrulamasından geçti. **Koşullar:** (a) Korunan geliştirme konağı yerine temiz Windows 10/11 test PC/VM'de **Yönetici (`Administrator`)** olarak çalıştırılmalı, (b) MSI **`NotSigned`** olduğu için SmartScreen onayı verilmeli, (c) İlk başlatmada `ALLOW_DEFERRED_TLS_START=1` ile `PENDING_TLS_PROVISIONING` sonrası `OpenSSL 3.5.9` ile TLS sertifikaları sağlanmalıdır (`PAT-21`, `PAT-22`). |
| **2. Upgrade (`v1.0.0 -> v1.1.0`)** | **`CONDITIONAL GO`** | Stage B'de `B-1` deterministik Windows SCM kimlik damgası (`HKLM:\SYSTEM\CurrentControlSet\Services\<Name>\Parameters` altında `MmsAppVersion`, `MmsXmlSha256`, `MmsTxId`, `MmsPreviousVersion`) ve `Invoke-VerifiedServiceStop` / `Invoke-VerifiedServiceUninstall` / `Resolve-DeterministicScmDisposition` uygulandı (`Test 25` + `Test 27` A–J & 14 fail-closed kenar durumu geçti). **Koşul:** Gerçek yükseltilmiş Windows SCM + `HKLM:\...` kayıt defteri yazma/okuma henüz non-admin konakta çalıştırılamadı (`BLOCKED` — önce temiz VM/PC'de Fresh Install `PAT-21` ardından Upgrade `PAT-23` ile doğrulanmalıdır). |
| **3. Rollback** | **`CONDITIONAL GO`** | `H-1`, `M-1..M-4` ve `B-1` düzeltmeleri `phase_c` (`17/17`) + `stage3` (`14/14`) ve `run_vm_fresh_install_acceptance.ps1` (`20/20`, `Migration` hatası → `ExitCode 74` → `1.0.0` geri dönüş) ile doğrulandı; yabancı servis koruması (`ERR_FOREIGN_SERVICE_PROTECTED`) ve `DELETE_PENDING` fail-closed mantığı eklendi. **Koşul:** Gerçek `msiexec` `CA_RollbackInstall` elevated SCM yürütmesi `PAT-24` (yalnızca test VM'de) doğrulaması beklemektedir. |
| **4. Multi-device Acceptance** | **`CONDITIONAL GO`** | Canlı izole Test Hub (`https://127.0.0.1:8947`, `UDP 8948`) karşısında Windows + Android FFI SQLite çift istemci E2E (`isolated_live_hub_e2e_test.dart` + `stage_j_multidevice_live_e2e_test.dart`, `+2`, `Exit 0`), Half-Up kuruş, `SELLABLE`/`DAMAGED` iade, eksi stok, replay/idempotency, Hub durdurma/açma uzlaştırması ve RBAC doğrulandı. **Koşullar:** (a) Gerçek fiziksel Android telefon, (b) üretim imzalı Release APK (şu an `android/key.properties` yok → `FAIL_CLOSED_RELEASE_EXIT=1`), (c) Private Wi-Fi LAN & Firewall altında QR eşleştirme/kamera testleri (`PAT-01..06`, `PAT-11`, `PAT-19`) fiziksel yürütülmelidir. |
| **5. Google Drive Acceptance** | **`CONDITIONAL GO`** | Live Sync (`.mmsenv`, `'MARKET MMS LiveSync'`) ve Merkezi Hub Backup/Restore (`.mmsbak`, `'MARKET MMS Yedekleri/Hub'`), DPAPI `pOptionalEntropy` izolasyonu (`BK-020`), PKCE Hub devri (`BK-021`) ve canlı izole Hub üzerinde şifreli yedek → 1-bayt kurcalama reddi (`HTTP 400 ERR_RESTORE_DECRYPT_FAILED`) → restore + epoch rotasyonu (`STAGE_K_LIVE_HUB_PASS`) doğrulandı. **Blokaj:** Canlı Google Cloud OAuth Client kimliği ve `TEST_ONLY` Google hesabı tarayıcı onayı **BLOCKED**; canlı bulut testleri Owner hesabı sağlanınca yapılacaktır. |
| **6. Physical Store Pilot (Mağaza Kesimi)** | **`NO-GO`** | Gerçek mağaza ortamına geçiş için fiziksel Windows + Android kabul planının (`PAT-01..26`, `BK-PAT-01..18`) sahada **PASS** edilmesi, ticari **OV/EV Authenticode** kod imzalama sertifikası ile MSI imzalanması, üretim Android **Release Keystore** ile `app-release.apk` üretilmesi ve mağaza Private LAN TLS/Drive OAuth provizyonunun tamamlanması zorunludur. |

---

## 2. Zorunlu 17 Satırlık Nihai Özet Tablosu (§20)

| Alan | Durum | Kanıt | Açık Engel |
|---|---|---|---|
| **B-1 SCM** | **CONDITIONAL PASS (Sandbox/Code)** | `mms_installer_engine.ps1` (`4541` satır) Registry kimlik damgası + `Resolve-DeterministicScmDisposition`; `phase_c` Test 25 & 27 A–J (`+31` Exit `0`) | Yükseltilmiş (`Administrator`) gerçek Windows SCM / `HKLM:\...\Parameters` saha testi (`PAT-23`, `PAT-24`) — non-admin konakta **BLOCKED** |
| **MSI ExitCode 74** | **ROOT CAUSE CONFIRMED & FIXED** | Kök neden `a559676` öncesi `Apply-DirectoryAcls` sırası + geçersiz `:(NP)X` (87) + eşlenmeyen SID (1332) → `74` → `1722` → `1603`; `MmsSafeDiagnosticLogWriter` 14 kontrol + `stage3` `AUD-DIAG-01` **PASS** | Yalnızca gerçek elevated kurulum teyidi (`PAT-21`) bekliyor |
| **Windows Environment** | **PASS (Read-Only / Host Protected)** | `IS_ADMIN=False`, Wi-Fi `Public`, `MarketMmsSpike01=NOT_PRESENT`, `MarketMMSService=NOT_PRESENT`, `Program Files\MarketMMS=False`, `FW_COUNT=0`, 4 korunan dosya & gerçek `client_local.db` değişmedi | Hedef test/pilot PC'de `Administrator` yetkisi ve **Private** ağ profili gerekir |
| **Client DB Backup** | **PASS** | `backup_client_db_safe.ps1` (`SQLITE_OPEN_READONLY` Online Backup API + `integrity_check=ok` + `.sha256`); gerçek DB kopyası (`159744` B) ve canlı WAL test DB (`WAL_TEST_PASS`) doğrulandı | Gerçek kurulum öncesi Owner makinede 1 kez çalıştırılmalı (`OWNER_PHYSICAL_TEST_CHECKLIST.md` Adım 1) |
| **TLS** | **PASS (Isolated 6/6) / BLOCKED (Prod)** | `run_tls_matrix.ps1` (`OpenSSL 3.5.9` + canlı `mms_backend.exe` `8947` + `MmsTlsHealthProbe`): T1 geçerli `DA14755D`, T2 rotasyon `CC1DADC9`, T3 expired fail, T4 rogue CA fail, T5 SANsız `Exit 78`, T6 Deferred TLS; `server.key` ACL'de `Users` yok | Gerçek hedef PC'nin Private LAN IP'si ile üretim CA/leaf sertifika provizyonu (`PAT-22`) |
| **MSI Signing** | **EXTERNAL BLOCKER (`NotSigned` / `TEST-SIGNED ONLY`)** | Release MSI `NotSigned`; izole kopya `...\MarketMMS-Setup-1.0.0-x64-testsigned.msi` (`015C18C7...`) `signtool sign` Exit `0` (`DCBC29E5...`), `verify` self-signed root `Exit 1` | Dağıtım/pilot için ticari OV/EV Authenticode sertifikası + TSA timestamp gerekir |
| **MSI Integrity** | **PASS** | `dist\installer_v1_0_0_tray\MarketMMS-Setup-1.0.0-x64.msi` (`23064576` B, SHA-256 `183B014FD6ED80785E4302388A2362D020DAD300D3BDEE21317450EE73CA820C`), `SHA256SUMS.txt` uyumlu, `COM_FILE_COUNT=27`, `COM_SPIKE01_ANY=0`, `LinkType=''` + HardLink fix sonrası `+31` testte sıfır bozulma | Yok (tarihsel eski `dist\installer\` kopyası pre-fix hardlink nedeniyle eskimiştir; güncel olan `dist\installer_v1_0_0_tray\`'dir) |
| **Windows Master Hub** | **PASS (Isolated) / BLOCKED (Service)** | Taze AOT `mms_backend.exe` (`9972736` B, `D72B05E5...`) canlı `8947/8948` HTTPS `/health UP`, E2E sync & restore doğrulandı | Gerçek `MarketMMSService` (`NT AUTHORITY\LocalService`, `UNRESTRICTED` SID) altında kurulum (`PAT-21..25`) |
| **Windows Client** | **PASS (Tray + Isolated Client)** | `market_pos.exe` (`175104` B, `7F449053...`) izole DB ile `SMOKE_PASS` (`pid=10084`, `WM_CLOSE` tepside yaşadı), `client_local.db` korundu | Fiziksel USB HID barkod okuyucu ve kullanıcı tepsi/autostart saha kontrolü (`PAT-02`, `PAT-08`) |
| **Android Client** | **CONDITIONAL (`TEST-SIGNED ONLY`)** | Fail-closed imza koruması (`Exit 1`), `app-debug.apk` (`A3D67707...`) + `app-release-testsigned.apk` (`E94A35C8...`), `allowBackup=false`, `usesCleartextTraffic=false`, `flutter_emulator` launch (`APP_PID=3757`, sıfır çökme) | Üretim Android Release Keystore (`android/key.properties`) + fiziksel Android cihaz (`PAT-01..06`, `PAT-11`) |
| **Multi-device Sync** | **PASS (Loopback Live E2E)** | `isolated_live_hub_e2e_test.dart` + `stage_j_multidevice_live_e2e_test.dart` (`00:44 +2 Exit 0`): çift yönlü ürün/barkod/satış/iade/stok/RBAC/idempotency/replay | Gerçek LAN Wi-Fi üzerinden fiziksel Windows + Android testi (`PAT-03..06`, `PAT-19`) |
| **Offline-first** | **PASS (Automated + Disk Reopen)** | Hub durduruldu → her iki SQLite dosyası diskten kapatılıp açıldı → Hub açıldığında FIFO Outbox `0` bekleyene indi ve stok/satışlar birebir uzlaştı | Fiziksel Wi-Fi kopması, mobil arka plan/Doze (`PAT-04`, `PAT-16`) |
| **Google Drive Live Sync** | **CONDITIONAL (Mock PASS / Cloud BLOCKED)** | `MMSENV01`, ayrı `'MARKET MMS LiveSync'` klasörü, `live_drive_sync_secret.dpapi`, `/api/v1/sync/live-drive-config`, `hybrid_drive_live_sync_test.dart` & `coordinator` **PASS** | Gerçek Google Cloud OAuth Client & `TEST_ONLY` Google hesabı tarayıcı girişi (`PAT-18`) |
| **Hub Backup/Restore** | **PASS (Live Hub) / BLOCKED (Cloud Upload)** | Canlı izole `8947` Hub'da `.mmsbak` yedek (`1505c06d...`), 1-bayt kurcalama `400 ERR_RESTORE_DECRYPT_FAILED`, restore `RESTORED` + epoch rotasyonu (`STAGE_K_LIVE_HUB_PASS`), `600k` PBKDF2 `~4.9s` | Canlı Google Drive bulut upload/download & `BK-PAT-01..18` (`PAT-13`, `PAT-17`) |
| **Automated Tests** | **PASS (`0` Hata, Konak İzole)** | Analiz `4/4` temiz; PS1 AST `14/14` (`0` hata); `mms_contracts` `+7`; `mms_client_storage` `+265`; root `market_pos` `+376 ~2` + canlı E2E `+2`; `spike_01_backend` tam koşu `+359` + HardLink düzeltmesi sonrası installer paketi `+31` (`stage5` yüksüz `5362 ms`) | Yok *(Not: paralel yüksek konak yükü altında `stage5` 50k senkronizasyonu `11899 ms` ölçümü gözlendi — performans marjı izlenmelidir)* |
| **Physical Acceptance** | **NOT RUN / PENDING PHYSICAL TEST** | [`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`](file:///c:/Users/halil/Github/market-pos/PHYSICAL_ACCEPTANCE_TEST_PLAN.md) (`PAT-01..26` & `BK-PAT-01..18`) ve [`OWNER_PHYSICAL_TEST_CHECKLIST.md`](file:///c:/Users/halil/Github/market-pos/docs/reports/OWNER_PHYSICAL_TEST_CHECKLIST.md) hazır | Fiziksel Windows yönetici kurulumu, fiziksel Android cihaz, ağ/LAN & canlı Google hesabı |
| **Pilot Readiness** | **NO-GO (Saha Kabul Öncesi)** | Tüm teknik hazırlık ve saha kılavuzları tamamlandı; henüz hiçbir fiziksel mağaza kabul testi yürütülmedi | Physical Acceptance `PASS`, OV/EV MSI imzası, Android Release Keystore, mağaza TLS & OAuth |

---

## 3. Owner'ın 10 Temel Sorusuna Açık ve Kanıta Dayalı Yanıtlar (§20)

1. **İlk Fresh Install fiziksel testine başlayabilir miyiz?**
   **Evet — `CONDITIONAL GO`.** Ancak mevcut korunan geliştirme konağı üzerinde değil; **yükseltilmiş (`Administrator`) yetkili temiz bir Windows 10/11 (x64) test VM veya ayrı test bilgisayarı** üzerinde başlayabilirsiniz. Güncel paket `dist\installer_v1_0_0_tray\MarketMMS-Setup-1.0.0-x64.msi` (`183B014FD6ED80785E4302388A2362D020DAD300D3BDEE21317450EE73CA820C`), izole `TEST_ONLY` ortamda tüm teknik yaşam döngüsü kontrollerini geçmiştir. (`NotSigned` olduğu için SmartScreen onayı gerekecektir; başlangıç öncesi gerçek veriniz varsa Adım 1 emniyet yedeğini alın.)

2. **Teknik olarak hangi işler tamamlandı?**
   - Stage B **B-1 Deterministik SCM Kimlik Damgası** (`MmsAppVersion`, `MmsXmlSha256`, `MmsTxId`, `MmsPreviousVersion`) ve Senaryo A–J + 14 fail-closed kenar durumu eklendi.
   - **ExitCode 74 / 1603** kök nedeni (`a559676` öncesi ACL sıralaması + `:(NP)X` + unmapped SID) doğrulandı; `setup_service_acls.ps1` v2.1 ile kalıcı çözüldü ve `MmsSafeDiagnosticLogWriter` doğrulandı.
   - **WiX v5 NTFS HardLink Build İzolasyon Hatası** bulundu ve `MarketMMSInstaller.wixproj` + `build_windows_installer.ps1` + `phase_c` regresyon testi ile kökten kapatıldı; taze Release MSI üretildi ve `+31` post-build testte bozulmadığı kanıtlandı.
   - **Güvenli Client DB Yedekleme Betiği** (`backup_client_db_safe.ps1`, salt-okunur Online Backup API + WAL testi), **TLS Sertifika Matrisi** (`6/6`), **İzole VM Fresh Install/Rollback/Uninstall Yaşam Döngüsü** (`20/20`), **Windows Tray İstemci & Emülatör APK Smoke**, **Canlı İzole Çoklu İstemci E2E** (`+2`, `00:44`), **Canlı Hub Backup/Tamper/Restore** (`STAGE_K_LIVE_HUB_PASS`) ve **4 pakette statik analiz + test doğrulamaları** tamamlandı.
   - Tüm 15 rapor/plan ve Owner saha rehberi (`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`, `OWNER_PHYSICAL_TEST_CHECKLIST.md`) güncellendi.

3. **Hangi teknik engeller kaldı?**
   - **Gerçek Windows Elevated SCM / HKLM / ACL / Firewall Doğrulaması:** Mevcut konak `IS_ADMIN=False` ve temiz VM ISO/imajı yok (`run_vm_fresh_install_acceptance.ps1 -LiveVmExecution` yalnızca temiz VM/test PC'de çalışabilir).
   - **Fiziksel LAN Keşfi & Android Kamera Donanımı:** Loopback dışı gerçek router/Wi-Fi `Private` profilinde `UDP 8946` + QR kamera eşleştirme saha testi yapılmadı.
   - **50.000 Ürün İlk Senkronizasyon Zaman Aşımı Marjı (Gözlenen Risk):** Yüksüz konakta `5362–6089 ms`, ancak yoğun CPU/disk yükü altında (`task-1607`) `11899 ms` gözlenmiştir; `ClientSyncService.requestTimeout` varsayılanı `10s` olduğundan çok büyük kataloglarda dikkatle izlenmelidir.

4. **Hangi dış bağımlılıklar mevcut?**
   1. **Ticari OV/EV Authenticode Kod İmzalama Sertifikası + RFC3161 TSA** (Release MSI şu an `NotSigned`).
   2. **Üretim Android Release Keystore (`android/key.properties`)** (mevcut `app-release-testsigned.apk` yalnızca `TEST-SIGNED ONLY`).
   3. **Google Cloud OAuth Client (`drive.file`) Kimlik Bilgileri + `TEST_ONLY` Google Hesabı Tarayıcı Onayı**.
   4. **Fiziksel Donanım & Ortam:** Yönetici yetkili ikinci Windows PC/VM, fiziksel Android telefon, Private Wi-Fi router, varsa USB HID barkod okuyucu.

5. **İlk fiziksel test için hangi cihazlar gerekiyor?**
   - **1 adet Yönetici (`Administrator`) yetkili temiz Windows 10/11 (x64) PC veya temiz Windows VM** (Hub + Windows masaüstü istemci kurulumu için).
   - **1 adet Android 8.0+ (tercihen Android 10–14) fiziksel telefon** (`adb` veya APK yükleme, kamera ve Wi-Fi için).
   - **Client isolation kapalı, aynı Private Wi-Fi / LAN ağı sağlayan yönlendirici/erişim noktası**.
   - *(Opsiyonel ama `PAT-02` için gerekli)* **1 adet USB HID barkod okuyucu**.

6. **İlk fiziksel testte hangi adımlar uygulanacak?**
   Tek seferde bir test adımı kuralıyla [`OWNER_PHYSICAL_TEST_CHECKLIST.md`](file:///c:/Users/halil/Github/market-pos/docs/reports/OWNER_PHYSICAL_TEST_CHECKLIST.md) ve [`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`](file:///c:/Users/halil/Github/market-pos/PHYSICAL_ACCEPTANCE_TEST_PLAN.md) sırası uygulanır:
   1. **Ön-Uçuş:** Mevcut `client_local.db` yedeği (`backup_client_db_safe.ps1`), `MarketMmsSpike01` yokluğu ve ağın `Private` olması.
   2. **`PAT-21` Fresh Install:** Release MSI SHA-256 doğrulama → `msiexec /i ... ALLOW_DEFERRED_TLS_START=1` → 11 dizin ve `PENDING_TLS_PROVISIONING` kontrolü.
   3. **`PAT-22` & `PAT-12` (Adım 1):** `OpenSSL 3.5.9` ile `-notext` + `IP:127.0.0.1` + LAN IP SAN'lı `ca.crt`/`server.crt`/`server.key` yerleştirme → `setup_service_acls.ps1 -BaseDir "C:\ProgramData\MarketMMS"` → `Start-Service MarketMMSService` → `/health UP`.
   4. **`PAT-08`, `PAT-25`, `PAT-10`:** Sistem tepsisi / autostart, standart kasiyer Windows hesabının `data`/`security` klasörlerine erişememesi ve `8945`/`8946` firewall doğrulaması.
   5. **`PAT-11`, `PAT-03`, `PAT-01..06`, `PAT-19`:** İmzalı Android APK kurulumu, QR ile LAN HTTPS eşleştirme ve canlı satış/stok/kesinti testleri.

7. **Upgrade ve rollback testlerine ne zaman geçilebilir?**
   **`PAT-21`, `PAT-22`, `PAT-25`, `PAT-10` ve `PAT-03` temiz bir test VM veya test PC'de başarılı (`PASS`) olduktan hemen sonra** `PAT-23` (v1.0.0 → v1.1.0 Upgrade), `PAT-24` (Test VM Rollback — yalnızca test VM'de, üretim verisi varken çalıştırılmamalı), `PAT-09` (WinSW crash recovery) ve `PAT-26` (Uninstall `PURGE_USER_DATA=0` & Reinstall) aşamalarına geçilebilir.

8. **Google Drive testleri hangi seviyede tamamlandı?**
   - **Tamamlanan Seviye:** Kod, kriptografi, ayrım ve **yerel/mock** entegrasyon seviyesi (`MMSENV01` LiveSync vs `MMSBAK01`/`MMSBAK02` Central Backup/Restore klasör ve DPAPI `pOptionalEntropy` ayrımı, PKCE Hub devrinde token sızdırmazlık `BK-021`, TLS pin hatasında Drive fallback engeli `S25b`, canlı izole Hub üzerinde `.mmsbak` üretimi + 1 bayt tamper reddi `HTTP 400` + restore + epoch rotasyonu `STAGE_K_LIVE_HUB_PASS`).
   - **Tamamlanmayan (`BLOCKED`) Seviye:** Gerçek Google Cloud Console OAuth Client ve `TEST_ONLY` Google hesabı üzerinden canlı tarayıcı girişi (`oauth2.googleapis.com`) ve gerçek Drive bulut klasörüne upload/download (`PAT-13`, `PAT-17`, `PAT-18`, `BK-PAT-01..18`).

9. **Gerçek mağaza pilotuna geçmek için hangi kriterler eksik?**
   1. `PAT-01..PAT-26` ve `BK-PAT-01..18` saha kabul testlerinin tümünün gerçek Windows + Android cihazlarda **PASS** edilmesi ve Owner tarafından onaylanması.
   2. Release MSI'ın ticari **OV/EV Authenticode** sertifikası ile zaman damgalı imzalanması.
   3. Android APK'nın gerçek mağaza/upload **Release Keystore** ile imzalanması (`CN=Android Debug` olmadan).
   4. Mağaza sunucusunda kalıcı Root CA / Leaf TLS (`OpenSSL 3.5.9`), Recovery Password ve merkezi Google Drive yedekleme OAuth kurulumunun tamamlanması.

10. **Kullanıcıdan (Owner) gerçekten beklenen tekil işlemler nelerdir?**
    - *(Varsa canlı veri için)* `backup_client_db_safe.ps1` ile `client_local.db` emniyet yedeğini almak.
    - Temiz Windows test PC/VM üzerinde Yönetici olarak ilk MSI kurulumu (`PAT-21`) ve TLS sertifika provizyonunu (`PAT-22`, `OpenSSL 3.5.9`) çalıştırmak.
    - Üretim Android keystore (`android/key.properties`) oluşturup gerçek `flutter build apk --release` almak ve fiziksel Android telefona kurmak (`PAT-11`, `PAT-03`).
    - Google Cloud OAuth Client kimliği ve `TEST_ONLY` Google hesabı girişiyle bulut Drive testlerini (`PAT-13`, `PAT-17`, `PAT-18`) yürütmek.
    - Ticari dağıtım öncesi OV/EV kod imzalama sertifikasını temin edip MSI'ı imzalamak ve saha kabul sonuçlarını onaylamak.

---

**Oturum Rapor Durumu (`GEMINI.md` §6.7):** **`FAZ KABULÜ BEKLİYOR`**
*(Tüm otonom mühendislik iyileştirmeleri, izole testler ve 15 kanıt/plan belgesi tamamlanmıştır; fiziksel cihaz ve dış erişim gerektiren saha kabul adımları ile faz/git kararları Proje Sahibinin onayını beklemektedir.)*
