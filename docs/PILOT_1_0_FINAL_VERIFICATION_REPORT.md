# MARKET MMS — PILOT 1.0 NİHAİ DOĞRULAMA & TESLİMAT RAPORU

- **Tarih:** 22 Kasım 2026
- **Kapsam:** Release 1.0 + Phase 1.1 (`ebf726a`, `3ebeda9`, `6c88c60`) + **Commit 4 (Gerçek Market Uçtan Uca Kalite, Finansal Doğruluk, Çapraz Ekran Reaktivitesi & UX Kapanışı)**
- **Genel Durum:** **`ALL SOFTWARE WORK PACKAGES DELIVERED (806/806 TESTS, 0/0 ANALYZER ISSUES, LIVE AOT 7/7 SMOKE PASSED) — HARDWARE/CREDENTIALS (PAT-01…18, B1, B2, C1/C2, D1–D4, E2) BLOCKED`**

> [!IMPORTANT]
> **Dürüst Doğrulama ve Sınır Beyanı:** Bu kapanış denetiminde tespit edilen dağıtım/ACL hataları, 34 eski `sqlite3.dispose()` analiz bilgisi, otomatik zamanlanmış yedek başlangıç eksikleri, Dashboard tam/kısmi iade (`REFUNDED`/`PARTIALLY_REFUNDED`) net ciro hesabı, modüller arası anlık Outbox/UI reaktivitesi, `OD-03` bilinmeyen barkod mesajı, Türkçe hata/tarih aralığı UX'i ve varsayılan `8945` port tutarlılığının tamamı düzeltilmiştir. Son değişikliklerden **sonra** 4 paketin tamamında **`No issues found!` (0/0)**, **806/806 otomatik test**, **`7/7` PowerShell 5.1 AST sözdizimi kontrolü**, **`dist\windows_release\` gerçek üretim paketi (`26/26` SHA-256)**, **izole üretim modunda canlı derlenmiş `mms_backend.exe` (`7/7` duman testi)**, **Android Debug APK (`189.29 MB`)** ve **Android Release fail-closed güvenlik kapısı** doğrulanmıştır.
> Buna karşılık bağlı fiziksel Android cihaz (`adb devices` boş), üretim Android imza keystore (`android/key.properties` yok), üretim Hub TLS sertifikaları (`C:\ProgramData\MarketMMS` yok) ve gerçek Google Cloud OAuth kimlik bilgileri (`C1/C2`) ortamda mevcut olmadığı için **`D1–D4` temizlik, `B1`, `B2`, `C1/C2`, `PAT-01…PAT-18` ve resmî faz kabulleri (`E2`)** çalıştırılamamıştır (**`BLOCKED`**).

---

## 1. Faz Hedefleri ve Tamamlanma Durumu

| İş Kalemi / Paket | Kapsam ve Doğrulama | Durum |
|---|---|---|
| **Commit 1 (`ebf726a`)** | `WP-1` DHCP/Wi-Fi reconnect, mobil 48dp ergonomi, tema kalıcılığı, Test 15 timeout, E2E sabit IP temizliği, `OD-03`/`go_router` uzlaştırması, `A7` QR görseli (`qr_flutter`), `K-05` Hub TLS-pinned `live-drive-config` + DPAPI | **Tamamlandı & Push Edildi** (`origin/main`) |
| **Commit 2 (`3ebeda9`)** | `WP-3` (`ADR-022` Android Google Drive OAuth `google_sign_in: ^7.2.0`) + `WP-4` İlk Yazılım & Doküman Kapanışı | **Tamamlandı & Push Edildi** (`origin/main`) |
| **Commit 3 (`6c88c60`)** | 5 dağıtım/paketleme/hata-mesajı düzeltmesi (`sqlite3.dll`, ACL, izole AOT staging, OAuth build parametreleri), 6 `.ps1` UTF-8 BOM + 7/7 PS 5.1 AST doğrulaması, 34 `sqlite3.dispose()` -> `.close()` temizliği | **Tamamlandı & Push Edildi** (`origin/main`) |
| **Commit 4 (Gerçek Market Denetimi)** | Zamanlanmış yedek/JobScheduler oto-başlatma, Dashboard `REFUNDED`/`PARTIALLY_REFUNDED` net ciro & `2000` satış limiti, tam çapraz ekran Outbox/UI reaktivitesi, `OD-03` barkod mesajı, `UserFriendlyErrorMapper` teknik önek temizliği, Türkçe `showDateRangePicker`, varsayılan port `8945`, 6 yeni E2E/birim testi, canlı AOT 7/7 & 806/806 tam doğrulama | **Tamamlandı & Doğrulandı** |
| **Saha / Donanım / Kimlik (`D1–D4`, `B1`, `B2`, `C1/C2`, `PAT-01…18`, `E2`)** | Fiziksel Windows + Android cihaz kurulumu, gerçek TLS sertifikaları, Android release keystore, Google Cloud OAuth ve mağaza saha kabul testleri | **`BLOCKED — OWNER HARDWARE & CREDENTIALS REQUIRED`** |

---

## 2. Gerçekleştirilen Düzeltmeler ve İyileştirmeler (Commit 3 + Commit 4)

### 2.1. Dağıtım, Paketleme ve Statik Analiz Temizliği (`6c88c60`)
1. **`setup_service_acls.ps1` & `install_mms_service.ps1`:** `sqlite3.dll` üç konuma (`bin\`, `bin\lib\`, `$TargetBaseDir\lib\`) rollback korumalı kopyalanır; `lib\` Service SID `RX`, `security\` `(OI)(CI)M` (`pepper.dpapi` + `live_drive_sync_secret.dpapi`), `security\admin_secret.txt` ise açık `:R` kilitlenir. 6 Unicode `.ps1` dosyası UTF-8 BOM'lu, `install_mms_service.ps1` saf ASCII'dir (**7/7 PS 5.1 AST `0` hata**).
2. **`scripts\package_windows_release.ps1` & `scripts\package_android_release.ps1`:** Hub AOT izole `$env:TEMP\mms_hub_aot_stage_*` altında derlenir; `-GoogleDriveClientId`, `-GoogleDriveClientSecret` ve `-GoogleDriveWebClientId` (`--dart-define`) parametreleri eklenmiştir.
3. **`google_drive_connect_service.dart` & 34 Analyzer Info:** Platform hata mesajı Windows ve Android'i yansıtacak biçimde güncellendi ve 34 deprecated `sqlite3.dispose()` çağrısı `.close()` ile değiştirildi.

### 2.2. Gerçek Market Çalışma Zamanı, Finans ve UX Düzeltmeleri (Commit 4)
1. **Açılışta Otomatik Zamanlanmış Yedek & Android `JobScheduler` Başlatma:**
   - [`backup_providers.dart`](../lib/features/backup/backup_providers.dart) içinde `backupAutoScheduleLifecycleEnabledProvider` eklendi; [`main.dart`](../lib/main.dart) içinde `true` override edilip [`main_shell_screen.dart`](../lib/features/shell/presentation/screens/main_shell_screen.dart) ilk karede `backupScheduleControllerProvider`'ı izleyerek kasiyer Sistem & Tanı sekmesine hiç geçmese bile zamanlanmış yerel/arka plan yedek denetimini başlatır.
2. **Dashboard Net Ciro Finansal Doğruluğu (`REFUNDED` / `PARTIALLY_REFUNDED` + 2000 Limit):**
   - [`client_storage_repository.dart`](../packages/mms_client_storage/lib/src/database/client_storage_repository.dart) içine parça-bazlı toplu iade okuyucu `getRefundTotalsBySaleIds(...)` eklendi.
   - [`dashboard_providers.dart`](../lib/features/dashboard/dashboard_providers.dart) artık 7 günlük dönemi `limit: 2000` ile okur, `CANCELLED` yanında **`REFUNDED`** satışları dışlar ve **`PARTIALLY_REFUNDED`** satışlarda `totalAmount - refundedCents` (tamsayı kuruş) net tutarını bugün/nakit/kart/7 günlük grafik kovalarına ekler.
3. **Çapraz Ekran Reaktivitesi & Outbox Senkronizasyonu:**
   - [`sales_history_notifier.dart`](../lib/features/sales/application/sales_history_notifier.dart) ve [`sales_providers.dart`](../lib/features/sales/sales_providers.dart): Tam iptal (`cancelSale`) ve kısmi iade (`refundSale`) sonrası `systemStatusProvider.notifier.refreshLocalMetrics()` + `backgroundSyncCoordinatorProvider.notifier.triggerSync(SaleCommitted)` bağımsız `try/catch` ile tetiklenir.
   - [`catalog_notifier.dart`](../lib/features/catalog/application/catalog_notifier.dart) ve [`catalog_providers.dart`](../lib/features/catalog/catalog_providers.dart): Ürün oluşturma/güncelleme/pasifleştirme hem Outbox sayaçlarını hem senkronizasyonu tetikler; `systemStatusProvider` değişikliklerinde (`localProductsCount`, `localMetricsRevision`) kataloğu aktif filtre/aramayı bozmadan `loadProducts(silent: true)` ile yeniler.
   - [`stock_providers.dart`](../lib/features/stock/stock_providers.dart): `stockOverviewProvider` artık `localMetricsRevision` izler ve `stockReceiptProvider` kayıt sonrası `refreshLocalMetrics()` çalıştırır.
4. **`OD-03` Uyumlu Bilinmeyen Barkod Rehberliği ([`cart_notifier.dart`](../lib/features/pos/application/cart_notifier.dart)):**
   - Tanımsız barkod uyarısı doğrulanmış `OD-03` kuralıyla hizalandı (`Tanımsız ürün doğrudan sepete eklenemez; ürünü Ürünler ekranından ekleyebilir veya Master Hub ile senkronize edebilirsiniz.`).
5. **Türkçe Hata Eşleme & Tarih Aralığı Seçicisi (`showDateRangePicker`):**
   - [`user_friendly_error_mapper.dart`](../lib/core/utils/user_friendly_error_mapper.dart) `Bad state:`, `Invalid argument(s):`, `RangeError:`, `Exception:` öneklerini temizler; [`sales_history_notifier.dart`](../lib/features/sales/application/sales_history_notifier.dart), [`catalog_notifier.dart`](../lib/features/catalog/application/catalog_notifier.dart), [`dashboard_screen.dart`](../lib/features/dashboard/presentation/screens/dashboard_screen.dart) ve [`first_setup_wizard_dialog.dart`](../lib/features/setup/presentation/widgets/first_setup_wizard_dialog.dart) hataları bu eşleyiciden geçirir.
   - [`sales_history_screen.dart`](../lib/features/sales/presentation/screens/sales_history_screen.dart) `_pickDateRange()` içinde Türkçe başlık, düğme ve giriş etiketleri (`Tarih Aralığı Seçin`, `İptal`, `Uygula`, `Başlangıç Tarihi`, `Bitiş Tarihi`) tanımlandı.
6. **Varsayılan Port Tutarlılığı ([`system_status.dart`](../lib/features/diagnostics/domain/system_status.dart)):**
   - `SystemStatus.initial()` içindeki eski `'https://127.0.0.1:8443'` varsayılanı standart Hub portu `'https://127.0.0.1:8945'` olarak düzeltildi.

---

## 3. Oluşturulan ve Değiştirilen Dosyalar (Commit 4)

- **Uygulama & Altyapı Kodları:**
  - `packages/mms_client_storage/lib/src/database/client_storage_repository.dart`
  - `lib/main.dart`
  - `lib/core/utils/user_friendly_error_mapper.dart`
  - `lib/features/backup/backup_providers.dart`
  - `lib/features/catalog/application/catalog_notifier.dart`
  - `lib/features/catalog/catalog_providers.dart`
  - `lib/features/dashboard/dashboard_providers.dart`
  - `lib/features/dashboard/presentation/screens/dashboard_screen.dart`
  - `lib/features/diagnostics/domain/system_status.dart`
  - `lib/features/pos/application/cart_notifier.dart`
  - `lib/features/sales/application/sales_history_notifier.dart`
  - `lib/features/sales/presentation/screens/sales_history_screen.dart`
  - `lib/features/sales/sales_providers.dart`
  - `lib/features/setup/presentation/widgets/first_setup_wizard_dialog.dart`
  - `lib/features/shell/presentation/screens/main_shell_screen.dart`
  - `lib/features/stock/stock_providers.dart`
- **Testler:**
  - `packages/mms_client_storage/test/sales_management_and_catalog_test.dart` (`getRefundTotalsBySaleIds` testi dahil `7/7`)
  - `test/features/production/pilot_real_market_e2e_test.dart` (`5/5` yeni gerçek market U2U süiti)
- **Dokümantasyon & Raporlar:**
  - `docs/PILOT_1_0_FINAL_VERIFICATION_REPORT.md` *(bu rapor)*
  - `docs/LIVE_PROJECT_STATUS.md`
  - `OWNER_ACTION_CHECKLIST.md`

---

## 4. Mimari Kararlar ve Gerekçeleri

- **En Az Ayrıcalık + İşlevsellik Ayrımı (`security\` vs `admin_secret.txt`):** `MarketMMSService` DPAPI anahtar dosyalarını (`pepper.dpapi`, `live_drive_sync_secret.dpapi`) kendisi üretip döndürebilmek için `security\` klasöründe `(OI)(CI)M` gerektirirken, yönetici parolası (`admin_secret.txt`) servis tarafından değiştirilmemelidir (`:R`).
- **Bağımsız Reaktif İzolasyon (`backupAutoScheduleLifecycleEnabledProvider`):** Test ortamlarında gerçek disk/WorkManager/JobScheduler yan etkilerini izole tutarken, canlı uygulamada (`main.dart`) ilk karede zamanlanmış yedek yaşam döngüsünü etkinleştirir.
- **Şema & Protokol Dondurma:** `ClientDatabase.schemaVersion = 3`, `SpikeDatabase.schemaVersion = 3`, kuruş tamsayı + Half-Up yuvarlama (`OD-01`), FIFO Outbox (`client_seq`, ACK-önce-`SYNCED` yasağı) ve `ADR-015…022` güvenlik sınırları hiç bozulmadı.

---

## 5. Çalıştırılan Testler ve Gerçek Sonuçları (Son Kod Değişikliği Sonrası)

### 5.1. Tam 4 Paket Statik Analiz ve Otomatik Test Süitleri (**`806/806`** — `0` Sorun)

| Paket / Komut | Statik Analiz (`analyze`) | Test Sonucu (`test`) | Çıkış Kodu |
|---|---|---|---|
| `packages/mms_contracts` (`dart analyze` + `dart test`) | **`No issues found!`** (`0` hata/uyarı/info) | **`7/7` All tests passed!** (`0` fail, `0` skip) | `0` |
| `packages/mms_client_storage` (`dart analyze` + `dart test`) | **`No issues found!`** (`0` hata/uyarı/info) | **`226/226` All tests passed!** (`0` fail, `0` skip) | `0` |
| `test_spikes/spike_01_backend` (`dart analyze` + `dart test`) | **`No issues found!`** (`0` hata/uyarı/info) | **`249/249` All tests passed!** (`0` fail, `0` skip) | `0` |
| Kök `market_pos` (`flutter analyze` + `flutter test`) | **`No issues found!`** (`0` hata/uyarı/info, `3.4s`) | **`324/324` All tests passed!** (`0` fail, `0` skip) | `0` |
| **TOPLAM** | **`4/4` Paket `0` Sorun** | **`806/806` Geçti / `0` Başarısız / `0` Atlanan** | **`0`** |

### 5.2. PowerShell 5.1 AST Sözdizimi ve Encoding Doğrulaması (**`7/7`**)

`[System.Management.Automation.Language.Parser]::ParseFile(...)` ile tüm **7/7** `.ps1` betiği **`parseErrors=0`** ile geçmiştir:
- `scripts\configure_hub_firewall.ps1` (`bom=True`, `nonAsciiBytes=45`)
- `scripts\package_android_release.ps1` (`bom=True`, `nonAsciiBytes=105`)
- `scripts\package_windows_release.ps1` (`bom=True`, `nonAsciiBytes=47`)
- `test_spikes\spike_01_backend\scripts\build_aot.ps1` (`bom=True`, `nonAsciiBytes=6`)
- `test_spikes\spike_01_backend\scripts\install_mms_service.ps1` (`bom=False`, `nonAsciiBytes=0` — saf ASCII)
- `test_spikes\spike_01_backend\scripts\setup_service_acls.ps1` (`bom=True`, `nonAsciiBytes=11`)
- `test_spikes\spike_01_backend\scripts\uninstall_mms_service.ps1` (`bom=True`, `nonAsciiBytes=13`)

### 5.3. Canlı Derlenmiş AOT `mms_backend.exe` Uçtan Uca Duman Testi (**`7/7`**)

Son kod değişikliklerinden sonra yeniden derlenen üretim paketindeki `dist\windows_release\hub_bin\mms_backend.exe` (SHA-256: `54FE640284C6D32352CA7C5A7896182A290F371E97F02772B5371E9D1D1F5DF4`) + `sqlite3.dll`, izole `--config=` üretim klasöründe OpenSSL kök CA + çoklu-SAN sunucu sertifikasıyla başlatılarak tüm 7 uçtan uca adım doğrulandı (çıkış `0`; geçici sandbox temizlendi):
1. `[SMOKE 1/7]` Sabitlenmiş TLS `GET /health -> 200 (UP)`.
2. `[SMOKE 2/7]` Canlı UDP `DISCOVER_MMS_HUB` (`1.0`) -> `MMS-HUB-SMOKE port=57862`.
3. `[SMOKE 3/7]` TLS Admin `POST /api/v1/pairing/session` + `GET /api/v1/pairing/ca-cert` (`hub_url=https://192.168.1.158:57862`).
4. `[SMOKE 4/7]` Tam ECDSA P-256 eşleştirme (`request` -> `approve` -> `poll` -> `429` cooldown + `ack CONFIRMED`).
5. `[SMOKE 5/7]` Kimlik doğrulamalı senkronizasyon (`PRODUCT_UPSERT` `10000` + `STOCK_RECEIPT` `5000` + `SALE_CREATE` `2000` + idempotent tekrar `200` -> `stock=13000`, `sales=1`).
6. `[SMOKE 6/7]` `K-05` `live-drive-config` + DPAPI rotasyon + diskte `pepper.dpapi` ve `live_drive_sync_secret.dpapi` ikisinin de üretimi (`True`).
7. `[SMOKE 7/7]` `POST /api/v1/admin/backup` ile şifreli `.mmsbak` dosyası ve `MMSBAK01` sihirli başlığı.

---

## 6. Build ve Dağıtım Paketi Sonuçları

| Hedef | Komut / Yol | Çıktı / Durum |
|---|---|---|
| **Windows Pilot Release Paketi** | `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\package_windows_release.ps1` (`dist\windows_release\`) | **Başarılı** (`mms_backend.exe` **`8.76 MB`** [SHA-256: `54FE640284C6D32352CA7C5A7896182A290F371E97F02772B5371E9D1D1F5DF4`], `market_pos.exe` **`120.0 KB`** [SHA-256: `EFC54FFC8CED3DFA4B749AAF397C5DCC42126A582DE3D3C92BE3F146F39C15BB`], **`26/26` dosya `SHA256SUMS.txt` doğrulamalı**) |
| **Android APK Debug (`google_sign_in` dahil)** | `flutter build apk --debug` (`build\app\outputs\flutter-apk\app-debug.apk`) | **Başarılı** (**`189.29 MB`** / `198.481.800` bayt, Exit `0`) |
| **Android Release Fail-Closed İmza Kapısı** | `flutter build apk --release` | **Başarılı — Beklenen Engelleme (Exit `1`)**: `"Release imzalama yapılandırılmadı: android/key.properties bulunamadı..."` |

---

## 7. Veritabanı ve Migration Etkileri

- Sıfır şema değişikliği (`ClientDatabase.schemaVersion = 3`, `SpikeDatabase.schemaVersion = 3`).
- Offline-first kuruş tamsayı + Half-Up yuvarlama (`OD-01`), FIFO Outbox (`client_seq`, ACK-önce-`SYNCED` yasağı), `MMSBAK01` / `MMSENV01` şifreleme sözleşmeleri korunmuştur.

---

## 8. Güvenlik Değerlendirmesi

- `setup_service_acls.ps1` hem native SQLite (`lib\`) hem DPAPI sır üretimi (`security\:M`) hem de `admin_secret.txt:R` salt okuma sınırını tek matriste tutar; `Users` (`S-1-5-32-545`) kritik dizinlerden tamamen izoledir.
- Hata maskeleme (`UserFriendlyErrorMapper.redactSecrets`) token/sır/şifre desenlerini arayüzde maskeler, yığın izlerini gizler.
- Üretim `android/key.properties`, `server.key` ve OAuth sırları depoya sokulmamıştır.

---

## 9. Performans Değerlendirmesi

- Tam 4-paket test süresi son çalıştırmada: `mms_contracts` `<1s` (7), `mms_client_storage` `49s` (226), `spike_01_backend` `57s` (249), kök `market_pos` `72s` (324); `flutter analyze` `3.4s`.
- Dashboard sorgusu 7 günlük pencereyle sınırlandırılıp (`limit: 2000`) iadeleri toplu `WHERE sale_id IN (...)` parçalı sorguyla okuyarak yoğun mağaza cirolarında N+1 sorgu veya 200-kayıt kırpılması yaratmaz.

---

## 10. Tespit Edilen Sorunlar ve Çözümleri

1. **Zamanlanmış Yedek Başlatılmıyordu:** `backupScheduleControllerProvider` yalnızca Sistem & Tanı sekmesine girildiğinde tetikleniyordu -> `main_shell_screen.dart` ilk karede başlatır.
2. **Dashboard Net Ciro & Satış Limiti Hatası:** `REFUNDED` ve `PARTIALLY_REFUNDED` iade düşüşleri ciroya yansıtılmıyordu ve `limit: 200` sınırı vardı -> `getRefundTotalsBySaleIds` ile kuruş hassasiyetinde net ciro + `limit: 2000` sağlandı.
3. **Çapraz Ekran & Outbox Güncelleme Gecikmesi:** İptal/iade/ürün/stok girişi sonrası üst çubuk Outbox rozeti ve diğer açık sekmeler yenilenmiyordu -> `refreshLocalMetrics()` + `triggerSync()` + `CatalogNotifier` sessiz dinleyici eklendi.
4. **Hata/Barkod Metinleri ve Tarih Seçici UX:** Teknik önekler (`Bad state:`), eski bilinmeyen barkod mesajı, İngilizce `showDateRangePicker` düğmeleri ve `8443` varsayılan portu düzeltildi.

---

## 11. Kalan Riskler ve Eksikler (`BLOCKED`)

- **`D1–D4` Ortam Temizliği:** Bu makinede `MarketMmsSpike01` spike servisi hâlâ `Running`/`Automatic` durumundadır (`PAT-08` öncesi Yönetici PowerShell ile durdurulup kaldırılmalıdır).
- **`B1` Android Release Keystore & `B2` Hub TLS Üretim Sertifikaları:** `android/key.properties` ve `C:\ProgramData\MarketMMS\certs\` henüz Owner tarafından oluşturulmamıştır.
- **`C1/C2` Google Cloud OAuth & `PAT-01…PAT-18` Fiziksel Saha Testleri:** Bağlı fiziksel Android cihaz (`adb devices` boş) ve Google Cloud `"In production"` OAuth kimlikleri olmadığından gerçek cihaz, kamera, USB HID, Wi-Fi kesintisi ve gerçek Drive OAuth senaryoları **`BLOCKED`** durumdadır.
- **`v1.1` Kapsamı:** Kullanıcı/RBAC, Raporlama/Export, `go_router` ve `ADR-019` çoklu KDV migrasyonu pilot sonrası kapsamdadır.

---

## 12. Owner Tarafından Yürütülmesi Gereken Fiziksel Saha / Operasyon Adımları

Tek seferde bir adım kuralıyla (`GEMINI.md` §6.8) sırasıyla şu adımları uygulayın ([`OWNER_ACTION_CHECKLIST.md`](../OWNER_ACTION_CHECKLIST.md)):

1. **Temizlik (`D1–D4`):** Yönetici PowerShell'de `Stop-Service MarketMmsSpike01` + `test_spikes\spike_01_backend\service_wrapper\MarketMmsSpike01.exe uninstall`; ardından test DB/token dosyalarını (`D2–D4`) temizleyin.
2. **Üretim TLS (`B2`) & Servis Kurulumu:** OpenSSL (`-config`/`-extensions` veya modern OpenSSL `-addext`) ile `ca.crt`, `server.crt` (zorunlu `IP:127.0.0.1` + sabit LAN IP SAN) ve `server.key` üretip `%ProgramData%\MarketMMS\certs\` altına koyun (`ca.key`'i Hub'a koymayın); `dist\windows_release\hub_bin\` + `hub_scripts\` üzerinden `install_mms_service.ps1`, `setup_service_acls.ps1`, `configure_hub_firewall.ps1` çalıştırın.
3. **Android Keystore (`B1`):** `keytool` ile depo dışında `market_mms_upload.jks` + `android/key.properties` oluşturup `SHA-1`/`SHA-256` değerlerini kaydedin.
4. **Google Cloud OAuth (`C1/C2`):** Drive API + `"In production"` (`drive.file`); Desktop Client ID (`-GoogleDriveClientId`), Android Client ID (`B1` SHA-1) ve Web `serverClientId` (`-GoogleDriveWebClientId`) ile `scripts\package_windows_release.ps1` ve `scripts\package_android_release.ps1` yeniden çalıştırın.
5. **Saha Kabul Testleri (`PAT-01…PAT-18`):** [`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`](../PHYSICAL_ACCEPTANCE_TEST_PLAN.md) sırasıyla çalıştırıp `E2` faz kabul kararını verin.

---

## 13. Git Durumu

- **Commit 1:** `ebf726a240f016df19a613b5d730d60256c39ac2` (`WP-1`, `A7` QR, `K-05`, Docs — pushed `origin/main`).
- **Commit 2:** `3ebeda9ae889cb036e4c79582e4df1f0de4630b0` (`WP-3` `ADR-022` Phase 2 + `WP-4` İlk Yazılım Kapanışı — pushed `origin/main`).
- **Commit 3:** `6c88c60576b2a48dda602304b8c58fcb94f05569` (`fix(market-mms): resolve Pilot deployment sqlite3/ACL/packaging bugs and clear all analyzer infos` — pushed `origin/main`).
- **Commit 4 (Bu Kapanış):** Bölüm 3'te listelenen dosyalar açık dosya listesiyle (`git add -- <files>`) stage → commit → `origin/main` push edilmiştir. 4 korunan yerel dosya (`.vscode/settings.json`, `run_windows_client.bat`, `start_master_hub.bat`, `stop_master_hub.bat`), `dist/` (`.gitignore`) ve çalışma zamanı verileri commit dışı korunmuştur.

---

## 14. Bir Sonraki Faza (`v1.1`) Geçiş İçin Gerekli Koşullar

1. Owner tarafından `D1–D4`, `B2`, `B1` ve (Drive kullanılacaksa) `C1/C2` kurulumlarının tamamlanması,
2. Gerçek Windows + Android donanımı üzerinde **`PAT-01…PAT-18`** kabul testlerinin geçilmesi,
3. Owner'ın resmî **Pilot 1.0 (`v1.0.0`) / `E2`** faz kabulünü vermesi.

**DURUM: `FAZ KABULÜ BEKLİYOR`**
