# MARKET MMS — Owner (Proje Sahibi) İşlem Listesi

*Tarih: 22 Kasım 2026 (Commit 1 `ebf726a` + Commit 2 `3ebeda9` + Commit 3 Pilot 1.0 Sıfır-Hata Dağıtım & Canlı AOT Kapanışı) · Kaynaklar: [`docs/PILOT_1_0_FINAL_VERIFICATION_REPORT.md`](docs/PILOT_1_0_FINAL_VERIFICATION_REPORT.md), [`docs/RELEASE_1_0_PHASE_2_DELIVERY_REPORT.md`](docs/RELEASE_1_0_PHASE_2_DELIVERY_REPORT.md), [`docs/RELEASE_1_0_FINAL_DELIVERY_REPORT.md`](docs/RELEASE_1_0_FINAL_DELIVERY_REPORT.md), [`docs/LIVE_PROJECT_STATUS.md`](docs/LIVE_PROJECT_STATUS.md)*

Bu listede **sizin** donanım, gizli anahtar, dış Google Cloud kurulumu, ortam temizliği ve fiziksel kabul testi gerektiren maddeleriniz yer alır. Pilot 1.0 yazılım geliştirme kapsamı (`P-BLOCK-1..3`, `WP-1`, `A7` QR, `K-05` Hub provizyonu, `ADR-020` [`JOB_ID = 70201`], `Faz C` Drive Restore, `ADR-021` hibrit canlı senkronizasyon, **`ADR-022` Android OAuth `google_sign_in: ^7.2.0`** ve Pilot kurulum/paketleme sertleştirmeleri) tümüyle tamamlanmış; **4/4 pakette `0` analyzer sorunu**, **800/800 otomatik test**, **Windows Pilot Release paketi (`dist\windows_release\`, `26/26` SHA-256 doğrulamalı)**, **Canlı Derlenmiş AOT `mms_backend.exe` duman testi (`7/7`)**, **Android Debug APK (`189.28 MB`)**, **Android Release fail-closed kontrolü** ve **7/7 PowerShell betiği sözdizimi/BOM doğrulaması** geçmiştir. Ancak fiziksel kabul testleri (**`PAT-01…PAT-18`**), üretim Android imza anahtarı (**`B1`**), üretim Hub TLS sertifikaları (**`B2`**), Google Cloud OAuth kurulumu (**`C1/C2`**), ortam temizliği (**`D1–D4`**) ve resmî faz kabulleri (**`E2`**) dış donanım/hesap gerektirdiği için sahada henüz yürütülmemiştir (**`ALL SOFTWARE DELIVERED & VALIDATED (800/800, 0 ANALYZER ISSUES) — PAT-01…18 BLOCKED`**).

> **Bu belgede hiçbir gerçek parola, token, sertifika veya özel anahtar yoktur; eklemeyin.**

**Sizin İçin Sıradaki Uygulama Sırası:**
1. Temizlik (**`D1–D4`**) — `MarketMmsSpike01` kaldırılması (`D1`), eski test token/DB temizliği (`D2–D4`).
2. Üretim anahtarları ve sertifikalar (**`B2`** + **`B1`**) — OpenSSL ile Hub `ca.crt`/`server.crt` (`IP:127.0.0.1` + sabit LAN IP SAN) ve `keytool` ile Android upload keystore + `android/key.properties` (`SHA-1`/`SHA-256` kaydedin).
3. Google Cloud OAuth (**`C1/C2`**) — Drive API açma, OAuth izin ekranını `"In production"` yapma; aynı projede Desktop + Android (`SHA-1`) + Web (`serverClientId`) Client ID üretip `package_windows_release.ps1` (`-GoogleDriveClientId`) / `package_android_release.ps1` (`-GoogleDriveWebClientId`) parametreleriyle derleme (`K-05` canlı senkron sırrı zaten Hub üzerinden otomatizedir).
4. Pilot donanımı, fiziksel kabul testleri (**`PAT-01…PAT-18`**) ve resmî faz kabulleri (**`E2`**).

---

## Özet Tablo

| # | Madde | Tür | Durum / Engellediği iş | Öncelik |
|---|---|---|---|---|
| A1 | ADR-015…022 kararları | **Teknik Tamam (Yazılım)** | `ADR-015, 016, 018, 020, 021, 022` tamamı kodlandı ve otomatik testlerden geçti (`PAT-01…18` saha doğrulaması **BLOCKED**); `ADR-017` `PAT-12` sonrası kesin onay, `ADR-019` pilot sonrası (`v1.1`) | **Saha Testi (`PAT-01…18`)** |
| A2 | Git commit ve sürüm takibi | **Commit 1 (`ebf726a`) + Commit 2 (`3ebeda9`) + Commit 3 Tamamlandı** | WP-1/`A7`/`K-05`/Docs Commit 1 (`ebf726a`), WP-3/WP-4 Commit 2 (`3ebeda9`) ve Pilot dağıtım/analiz/canlı-AOT kapanışı Commit 3 `origin/main`'e kaydedilmiştir; 4 yerel dosya (`.vscode/settings.json`, `*.bat`) commit dışı korundu | Tamamlandı |
| A3 | Kategori/KDV senkronu (ADR-019) | **DEFERRED_POST_PILOT (`v1.1`)** | Pilotta 7 geçici %20 KDV kısıtıyla kabul; pilot sonrası (`v1.1`) migrasyon | Orta (pilot sonrası) |
| A4 | Discovery TLS (ADR-018 §2.2) & `P-BLOCK-1..3` | **IMPLEMENTED (Otomatik Testli)** | `DEC-REV-1..5` + `WP-1` (`networkError` DHCP/Wi-Fi reconnect) kodlandı; fiziksel doğrulama **`PAT-03` & `PAT-12`** bekleniyor (**BLOCKED**) | **Saha Testi (`PAT-03`, `PAT-12`)** |
| A5 | Android kapalıyken arka plan yedek (`ADR-020`) | **IMPLEMENTED (`JobScheduler`, `JOB_ID = 70201`)** | `MmsBackgroundBackupJobService` + headless `FlutterEngine` + Keystore ile harici bağımlılıksız uygulandı; fiziksel doğrulama **`PAT-16`** bekleniyor (**BLOCKED**) | **Saha Testi (`PAT-16`)** |
| A6 | Google Drive Yedek + Hibrit Canlı Senkron (`ADR-021`, `K-05`) + Android OAuth (`ADR-022`) | **IMPLEMENTED (`google_sign_in: ^7.2.0` + `K-05`)** | `ADR-022` `AndroidGoogleSignInTokenProvider`, `drive_auth_providers.dart`, `GoogleDriveConnectService`, `ExternalBackupSection` + `K-05` Hub provizyonu kodlandı (`android_google_sign_in_oauth_test.dart` 9/9 + Android Debug APK geçti). Yalnız **`C1/C2`** Google Cloud kurulumu ve **`PAT-13/17/18`** saha doğrulaması bekliyor | **Yüksek (`C1/C2`, `PAT-13/17/18`)** |
| A7 | QR görseli paketi (`qr_flutter`) | **IMPLEMENTED (`qr_flutter: ^4.1.0`)** | Windows `PairingApprovalPanel` içinde canlı kare QR (`Key('pairing_qr_image')`) eklendi; fiziksel doğrulama **`PAT-03`** bekleniyor (**BLOCKED**) | **Saha Testi (`PAT-03`)** |
| A8 | Güncelleme paketi imzalama ve merkezi hata izleme | İsteğe bağlı (`v1.1` / Operasyon) | Şu an SHA-256 manifest doğrulaması ve maskeli tanı dışa aktarımı aktif; kod imzalama sertifikası / merkezi tanı ucu için karar | Düşük / İsteğe bağlı |
| B1 | Android üretim imza anahtarı | Gizli anahtar | Release APK (`pubspec.yaml` `1.0.0+1`, `PAT-11`) | **Engelleyici** |
| B2 | Hub TLS sertifikaları (CA + `IP:127.0.0.1` & LAN IP SAN'lı sunucu) | Sertifika | Üretim Hub'ı startup (`exit 78` koruması), eşleştirme (`PAT-03`, `PAT-12`) | **Engelleyici** |
| C1 | Google Cloud projesi | Hesap | Drive uzak yedeği (`PAT-13`, `PAT-17`) ve hibrit Drive canlı senkron (`PAT-18`) | Pilot kapsamına bağlı |
| C2 | Google OAuth yapılandırması (Desktop + karar verilirse Android) | Hesap | Drive yetkilendirmesi (`PAT-13`, `PAT-17`, `PAT-18`) | Pilot kapsamına bağlı |
| D1 | `MarketMmsSpike01` servisinin kaldırılması | Temizlik | Port/çakışma riski (`PAT-08` ön koşulu) | Orta |
| D2 | Manuel test token'larının iptali/rotasyonu | Güvenlik | Bilinen token ile erişim | **Yüksek** |
| D3 | Şifresiz test DB kopyalarının kaldırılması | Güvenlik | Veri sızıntısı | Yüksek |
| D4 | Eski şifresiz restore koruyucu kopyaları | Güvenlik | Veri sızıntısı | Orta |
| E1 | Pilot ortamı ve donanım | Donanım | Tüm fiziksel kabul testleri (`PAT-01…PAT-18` **BLOCKED**) | **Engelleyici** |
| E2 | Faz kabulleri | Karar | "Kullanıma hazır" kararı (`docs/MASTER_ROADMAP.md`) | Son adım |

---

## A. Kararlar

### A1. ADR-015…ADR-022 Kararları
- **Neden gerekli?**
  - `ADR-015`, `016`, `018`, `020` ve `021` teknik olarak kodlandı ve otomatik testlerden geçti; ancak fiziksel saha doğrulamaları (`PAT-01…PAT-18`) henüz yürütülmediği için üretime kabul edilmedi.
  - `ADR-017` TLS sınıflandırması `PAT-12` sonrası kesin onay bekliyor; `ADR-019` pilot sonrasına ertelenmiş durumda; **`ADR-022` (Android Google Drive OAuth Tasarımı)** için Owner **Seçenek A (`google_sign_in`)** ve pilot kapsamına dahil edilmesi kararını vermiştir (**`DESIGN APPROVED — PENDING PHASE 2 IMPLEMENTATION`**, henüz kodlanmamıştır).
- **Mevcut ADR Durum Tablosu:**

  | ADR | Konu | Kodda / Belgede Durum | Sizden İstenen |
  |---|---|---|---|
  | 015 (+Ek A/B) | Tek `hub_config.json`, `ROOT_CA_CERT_FILE` env fallback temizliği, `tls` katı anahtar denetimi, fail-closed `503` | **CONFIRMED** (kodda uygulandı; fiziksel SCM/ACL **BLOCKED**) | Fiziksel kurulum testi `E1` / `PAT-08`…`PAT-10` ile doğrulanacak |
  | 016 (+Ek A/B) | Restore'da Outbox/seq koruması, zamanlanmış/USB/Drive yedek, **`BackupOperationLock` heartbeat + 60 sn kurtarma + Hub kilidi** | **CONFIRMED** (kodda uygulandı; Guide §7 düzeltildi) | Fiziksel USB ve restore süre ölçümü (`PAT-07`, `PAT-14`) |
  | 017 | Snapshot endpoint (`CONFIRMED`), **TLS CA/SAN/IP/Hostname/Tarih/MITM sınıflandırması** | **PARTIALLY_CONFIRMED / IN_REVIEW** (uygulandı; `PAT-12` **BLOCKED**) | TLS sınıflandırmasını `PAT-12` sonrası kesin onaylayın |
  | 018 (+`DEC-REV-1..5`) | Eşleştirilmiş keşifte `https://` zorunluluğu (§2.1), UDP Seçenek C (§2.2) ve **`P-BLOCK-1..3`** (`X.509/DER`, `ALT-BOOT-2`, `ACK_PENDING`, Win FFI, `advertise_host`) | **CONFIRMED — IMPLEMENTED (Otomatik Testli)** (`PAT-03`, `PAT-12` **BLOCKED**) | Gerçek donanım/LAN doğrulaması (`PAT-03`, `PAT-12`) |
  | 019 | Kategori/KDV senkronu (`SYNC-CAT`) | **DEFERRED_POST_PILOT** (kod/şema değişmedi) | Pilot boyunca 7 geçici %20 KDV kısıtını operasyonel olarak uygulayın |
  | 020 | Android kapalıyken arka plan yedekleme (saf SDK `JobScheduler`, **`JOB_ID = 70201`** + headless `FlutterEngine` + Keystore) | **CONFIRMED — TECHNICALLY IMPLEMENTED** (`PAT-16` **BLOCKED**) | Fiziksel Android cihazda uygulama kapalıyken yedek + reboot doğrulaması (`PAT-15`, `PAT-16`) |
  | 021 | Hub öncelikli, Google Drive destekli hibrit canlı senkronizasyon (`MMSENV01`, klasör: `MARKET MMS LiveSync`, non-LWW, **`K-05` Hub provizyonu**) | **CONFIRMED — TECHNICALLY IMPLEMENTED** (26 motor senaryosu + `K-05` Hub/istemci provizyon testleri geçti; `PAT-18` **BLOCKED**) | `C1/C2` kurulumu sonrası 2 cihaz saha doğrulaması (`PAT-18`) |
  | 022 | Android Google Drive OAuth Tasarımı (**Seçenek A — `google_sign_in: ^7.2.0`**) | **`CONFIRMED — TECHNICALLY IMPLEMENTED`** (`AndroidGoogleSignInTokenProvider` + `drive_auth_providers` + 9 otomatik test & Android Debug APK geçti; `C1/C2` & `PAT-13/17/18` **BLOCKED**) | `B1` Release keystore sonrasında `C1/C2` (Web `serverClientId` + Android SHA-1 + "In production") yapılandırıp `--dart-define=MMS_GDRIVE_WEB_CLIENT_ID=...` ile APK derleyin |

- **Etkilenen dosyalar:** `docs/decisions/015…022-*.md`, `docs/decisions/README.md`, `docs/RELEASE_1_0_FINAL_DELIVERY_REPORT.md`, `docs/RELEASE_1_0_PHASE_1_VERIFICATION_REPORT.md`, `docs/RELEASE_1_0_PHASE_1_1_FINALIZATION_REPORT.md`, `docs/RELEASE_1_0_PHASE_2_DELIVERY_REPORT.md`, `docs/LIVE_PROJECT_STATUS.md`.
- **Tamamlandığında yapılacak test:** Fiziksel kabul testleri **`PAT-01…PAT-18`** (şu an tamamı **BLOCKED**).

### A2. Değişikliklerin commit edilmesi ve sürüm takibi
- **Mevcut Durum:**
  - Release 1.0 (`a02a3c6`), Phase 1.1 (`a118434`), Commit 1 (`ebf726a`), Commit 2 (`3ebeda9`) ve **Commit 3 (Pilot 1.0 sıfır-hata dağıtım/analiz/canlı-AOT kapanışı)** `origin/main`'e commit edilerek çalışma ağacı yalnızca 4 korunan yerel dosyayla temizlenmiştir.
  - Bilinçli olarak commit dışı bırakılan 4 korunan yerel dosya (`.vscode/settings.json`, `run_windows_client.bat`, `start_master_hub.bat`, `stop_master_hub.bat`) ve çalışma zamanı verileri/servisleri dokunulmadan korunur.
- **Güvenlik kontrolü:**
  - `git status --ignored` / `git diff --cached` içinde şu dosyalar **asla bulunmaz**: `manual_test_env/`, `*.db`, `*.key`, `pepper.dpapi`, `live_drive_sync_secret.dpapi`, `android/key.properties`, `*.jks`, `dist/`.
- **Tamamlandığında yapılacak test:** Dört test süitinin (**`800/800`**), statik analizlerin (`4/4` pakette `0` sorun), `dist\windows_release\` paketinin (`26/26` SHA-256), canlı derlenmiş AOT `mms_backend.exe` duman testinin (`7/7`), Windows Release + Android Debug (`189.28 MB`) + Android Release fail-closed kontrolünün ve `7/7` `.ps1` sözdizimi/BOM kontrolünün tam yeşil olduğu doğrulanmıştır.

### A3. Kategori / KDV senkronizasyonu kararı (SYNC-CAT, ADR-019 — **DEFERRED_POST_PILOT**)
- **Karar Durumu:** Owner kararıyla pilot sonrasına **ertelendi**. Şema v3 → v4, `CATEGORY_UPSERT`, `PRODUCT_UPSERT` değişiklikleri ve kısmi KDV senkronizasyonu pilotta uygulanmayacaktır.
- **Pilot İçin Bağlayıcı 7 Geçici %20 KDV Operasyonel Kısıtı:**
  1. Tüm ürünler cihazlar arasında varsayılan **%20 KDV** varsayımıyla yönetilir; çoklu KDV (%0, %1, %10) senkronize edilmez.
  2. Hub `products` tablosunda `vat_rate` ve `category_id` sütunu ile `categories` tablosu yoktur.
  3. Yeni kurulan veya yeniden eşleştirilen her cihaz tüm ürünleri `%20` KDV ve `category_id = null` olarak alır.
  4. Bir cihazda yerel değiştirilen KDV oranı veya kategori diğer cihazlara ve Hub'a taşınmaz.
  5. Satış toplamları (kuruş) doğrudur ancak çoklu KDV mağazada KDV dökümü tutarsız olabilir → resmî mali beyan doğrudan çoklu cihaz KDV raporuna dayandırılmamalıdır.
  6. Restore mevcut cihazda yerel KDV'yi korur; cihaz değişiminde eski yerel KDV geri gelmez.
  7. Pilot sonrası ADR-019 migrasyonu başlatılmadan önce doğrulanmış şifreli `.mmsbak` Hub yedeği alınmalıdır.
- **Pilot Sonrası Uygulama Kapsamı (9 Kalıcı Gereksinim):** Ayrıntılı liste [`docs/decisions/019-category-vat-sync.md`](docs/decisions/019-category-vat-sync.md) §2 içindedir.

### A4. Discovery TLS (ADR-018 **CONFIRMED — Seçenek C**) ve `P-BLOCK-1..3` (`DEC-REV-1..5` Uygulandı)
- **Durum (Release 1.0):** `DEC-REV-1..5` kapsamındaki tüm `P-BLOCK-1..3` düzeltmeleri (`extractCanonicalSingleCertDer`, dar `MmsX509PreValidator`, `ALT-BOOT-2`, crash-safe `ACK_PENDING` + idempotent `/ack`, Windows `GetAdaptersAddresses`+`GetIfEntry2` x64 FFI + `advertise_host`) kodlandı ve otomatik testlerden geçti (`HUB-T01..T09b`, `APP-T01..T18`).
- **Sizden İstenen:** Gerçek donanımda **`PAT-03`** ve **`PAT-12`** fiziksel kabul testlerinin yürütülmesi (`DEC-REV-6`). Ayrıca Windows FFI canlı adaptör çözümlemesi (`HUB-T04c`) ve crash-safe re-pairing kesinti kurtarmasının (`APP-T16`) `PAT-03` alt adımı olarak mı yoksa ayrı kontrol adımlarıyla mı doğrulanacağına karar verin.

### A5. Android Uygulama Kapalıyken Zamanlanmış Yedek (`ADR-020` — **IMPLEMENTED (`JobScheduler`)**)
- **Karar & Uygulama Durumu:** Harici pub paketi (`workmanager`) olmadan saf Android SDK `JobScheduler` (`MmsBackgroundBackupJobService`, kanonik **`JOB_ID = 70201`**) + headless `FlutterEngine` + paylaşılan `MmsSecureStorageChannelHandler` (`AndroidKeyStore`) + `BackgroundBackupWorkerExecutor` uygulandı; `BackupOperationLock` ve üstel geri çekilme (exponential backoff) entegre edildi ve otomatik testlerle doğrulandı.
- **Sizden İstenen:** Fiziksel Android cihazda **`PAT-16`** ile uygulama kapalıyken yedekleme (`adb shell cmd jobscheduler run -f com.marketmms.market_pos 70201`) + yeniden başlatma (`setPersisted(true)`) kalıcılığının doğrulanması.

### A6. Google Drive Yedekleme, Hibrit Canlı Senkronizasyon (`ADR-021`, `K-05`) ve Android OAuth (`ADR-022`)
- **Mevcut Durum:**
  - **Uygulananlar (Otomatik Testli — Masaüstü + Android Tamam):**
    - Uzak şifreli yedek listeleme/indirme/ön doğrulamalı geri yükleme (`Faz C`), Hub-öncelikli `MMSENV01` hibrit canlı senkronizasyon motoru (`ADR-021`, `MARKET MMS LiveSync` klasörü, 26 otomatik senaryo),
    - **Seçenek 1 (`K-05`) Hub TLS-pinned provizyonu:** Hub tarafında Windows DPAPI `LiveDriveSecretManager` (`live_drive_sync_secret.dpapi`), `GET /api/v1/sync/live-drive-config` + `POST /api/v1/admin/live-drive-secret/rotate`; istemci tarafında `FileDriveAuthorizedRegistryStore`, `HubLiveDriveConfigClient`, `DriveAuthorizedRegistryNotifier` ve 5 dk throttle'lı Hub sync provizyonu,
    - **Phase 2 Android OAuth (`ADR-022` Seçenek A — `google_sign_in: ^7.2.0`):** `AndroidGoogleSignInTokenProvider` (RAM-only `accessToken` + `50 dk` TTL, yalnızca `drive.file` kapsamı, `401`/`forceRefresh` `clearAuthorizationToken`, soğuk başlatma `attemptLightweightAuthentication`, `disconnect()` + çevrimdışı `signOut()` fallback, fail-safe `ERR_DRIVE_NOT_CONFIGURED`/`ERR_DRIVE_GMS_UNAVAILABLE`), `drive_auth_providers.dart`, `GoogleDriveConnectService`, `backup_providers.dart`, `sync_providers.dart`, `ExternalBackupSection` ve 9 otomatik senaryo (`android_google_sign_in_oauth_test.dart` 9/9 + Android Debug APK derlemesi geçti).
- **Ne yapmalısınız? (Yalnızca Dış Google Cloud Hesap Kurulumu & Saha Testi Kaldı)**
  1. `B1` Release keystore oluşturduktan sonra **SHA-1** ve **SHA-256** parmak izlerini `C1/C2` Google Cloud OAuth kurulumunda kaydedin.
  2. `C1/C2` altında aynı Google Cloud projesinde **Desktop app Client ID** (`MMS_GDRIVE_CLIENT_ID`), **Android OAuth Client ID** (`com.marketmms.market_pos` + SHA-1) ve `google_sign_in` için zorunlu **Web application Client ID (`serverClientId`)** oluşturun; OAuth izin ekranını **`"In production"`** durumuna alın.
  3. Android Release APK derlerken `--dart-define=MMS_GDRIVE_WEB_CLIENT_ID=<web-client-id>` değerini geçin (Web `client_secret` ASLA APK'ya konulmaz).
- **Etkilenen dosyalar:**
  - `K-05`: `test_spikes/spike_01_backend/lib/security/live_drive_secret_manager.dart`, `auth_middleware.dart`, `bin/server.dart`, `lib/features/sync/data/drive_authorized_registry_store.dart`, `hub_live_drive_config_client.dart`, `application/drive_authorized_registry_notifier.dart`, `sync_providers.dart`, `lib/main.dart`.
  - `ADR-022`: `pubspec.yaml` (`google_sign_in: ^7.2.0`), `lib/features/backup/application/android_google_sign_in_token_provider.dart`, `lib/features/backup/drive_auth_providers.dart`, `google_drive_connect_service.dart`, `backup_providers.dart`, `sync_providers.dart`, `external_backup_section.dart`, `test/features/backup/android_google_sign_in_oauth_test.dart`.
- **Güvenlik uyarısı:** Kapsam her koşulda yalnızca `drive.file` kalmalıdır (`ADR-011`). Web `client_secret` ve `drive_live_sync_secret_v1` değerleri APK'ya, depoya, loglara veya SQLite'a **asla** yazılmamalıdır.
- **Kalan doğrulama:** Gerçek Google Cloud (`C1/C2`) + Release keystore (`B1`) sonrası fiziksel **`PAT-13`**, **`PAT-17`** ve **`PAT-18`** (**BLOCKED**).

### A7. QR görseli bağımlılığı (**IMPLEMENTED (`qr_flutter: ^4.1.0`)**)
- **Neden gerekliydi & Ne yapıldı?**
  - Windows `PairingApprovalPanel` eşleştirme ekranı QR görselini doğrudan ekranda göstermiyordu.
  - `pubspec.yaml` dosyasına `qr_flutter: ^4.1.0` eklendi ve `PairingApprovalPanel` içinde beyaz zeminli kart üzerinde kare modüllü `QrImageView` (`Key('pairing_qr_image')`, `220×220`) + güvenlik uyarısı ile kopyalanabilir payload akışı birlikte sunuldu; açık/koyu tema widget testleri (`pairing_approval_panel_test.dart`) geçti.
- **Etkilenen dosyalar:** `pubspec.yaml`, `lib/features/security/presentation/widgets/pairing_approval_panel.dart`, `test/features/security/pairing_approval_panel_test.dart`.
- **Güvenlik uyarısı:** QR içeriği tek kullanımlık ve süreli bir eşleştirme sırrı içerir. Ekran görüntüsünü paylaşmayın.
- **Kalan doğrulama:** Fiziksel Android kamera taraması ile **`PAT-03`** adım 1–4 (**BLOCKED**).

### A8. Güncelleme paketi imzalama ve merkezi hata izleme
- **Neden gerekli?**
  - Hub güncellemeleri `SHA256SUMS.txt` ile doğrulanıyor. Başarısız güncellemede önceki sürüme otomatik dönülüyor.
  - Ancak kod imzalama yok.
  - Uygulama içi güncelleme denetimi yalnızca bildirim yapıyor. HTTP adres ve eksik SHA-256 reddediliyor.
  - Merkezi hata izleme yok. Şu an cihaz başına maskeli tanı raporu dışa aktarılabiliyor.
- **Ne yapmalısınız?** İki konuda karar verin:
  - **Kod imzalama sertifikası:** Ücretli. Windows'ta "bilinmeyen yayıncı" uyarısını kaldırır.
  - **Merkezi hata izleme:** Önerilen seçenek ücretsizdir ve dış servis gerektirmez: cihazların maskeli tanı raporlarını Hub'a göndermesi. Bu yeni bir Hub ucu demektir.
- **Güvenlik uyarısı:**
  - İmzalama anahtarı depoya konmamalı.
  - Dış hata izleme servisleri (Sentry vb.) cihaz verisini dışarı gönderir; KVKK değerlendirmesi gerektirir.
- **Tamamlandığında yapılacak test:** `PAT-09` (güncelleme ve geri dönüş).

---

## B. Üretim Anahtarları ve Sertifikalar

### B1. Android üretim imza anahtarı
- **Neden gerekli?**
  - `android/key.properties` olmadan release derlemesi **durur** (fail-closed: `BUILD FAILED — Release imzalama yapılandırılmadı`).
  - Debug anahtarıyla üretim paketi üretilmez.
  - Phase 1.1 ile `pubspec.yaml` sürümü `1.0.0+1` olarak sabitlendi ve `scripts/package_android_release.ps1` artık APK dosya adını (`market_mms_v1.0.0-b1.apk`) ve `--build-name`/`--build-number` bayraklarını doğrudan `pubspec.yaml`'dan üretir.
  - **Not (NDK `28.2.13676358` & Android OAuth):** Yerel Android SDK'ya NDK **`28.2.13676358`** kurulmuş ve `android/app/build.gradle.kts` `ndkVersion = flutter.ndkVersion` (`28.2.13676358`) olarak hizalanmıştır. `ADR-022` Seçenek A (`google_sign_in`) pilot kapsamında onaylandığından, `market_mms_upload.jks` üretildikten sonra `keytool -list -v` çıktısındaki **SHA-1** ve **SHA-256** parmak izlerini `C2` Google Cloud kurulumu için mutlaka kaydedin.
- **Ne yapmalısınız?** [`docs/release/ANDROID_RELEASE.md`](docs/release/ANDROID_RELEASE.md) §2'yi izleyin:
  1. `keytool` ile `.jks` dosyasını üretin.
  2. Dosyayı **depo dışında** saklayın. Örnek konum: `C:\MarketMMS-Secrets\`.
  3. `android/key.properties` dosyasını oluşturun.
- **Etkilenen dosyalar:** `android/key.properties` (Git'e girmez), `.jks` dosyası.
- **Güvenlik uyarısı:**
  - Anahtar ve parolalar kaybolursa kurulu uygulamalar **güncellenemez**. Şifreli iki ayrı yedek tutun.
  - Bu dosyaları kimseyle, yapay zekâ araçları dahil, paylaşmayın.
- **Tamamlandığında yapılacak test:**
  - `pwsh scripts/package_android_release.ps1` (`flutter build apk --release --build-name=1.0.0 --build-number=1`) başarılı olmalı.
  - Birleşik manifestte `usesCleartextTraffic="false"` ve `allowBackup="false"` olmalı.
  - Ardından `PAT-11` ve `PAT-16`.

### B2. Windows Hub TLS sertifikaları (kök CA + sunucu)
- **Neden gerekli?**
  - Üretim Hub'ı TLS olmadan açılmaz.
  - `tls.ca_cert` (kök CA'nın **genel** sertifikası) üretimde zorunludur; yoksa eşleştirme QR'ı CA parmak izi taşıyamaz (`POST /api/v1/pairing/session` → `503 ERR_CA_CERT_UNAVAILABLE`).
  - **`IP:127.0.0.1` Loopback SAN Zorunluluğu (`HUB-T07`):** `server.crt` SAN listesinde **`IP:127.0.0.1`** yoksa Hub başlangıçta fail-fast **çıkış kodu `78`** (`ERR_SERVER_CERT_MISSING_LOOPBACK_SAN`) ile durur (yalnızca `DNS:localhost` yeterli değildir).
  - **LAN IP SAN & `advertise_host`:** `server.crt` ayrıca Hub'ın aktif LAN IPv4 adres(ler)ini (ör. `IP:192.168.1.50`) içermelidir; çoklu NIC ortamında `hub_config.json` içinde `advertise_host` tanımlanabilir. LAN IP SAN uyuşmazlığında Hub yerel POS için açık kalır ancak `/api/v1/pairing/session` **`503`** döner (ayrıntı: [`docs/release/WINDOWS_HUB_RELEASE.md`](docs/release/WINDOWS_HUB_RELEASE.md) §1.1).
- **Ne yapmalısınız?**
  1. **Hub dışında** güvenli bir bilgisayarda OpenSSL ile şunları üretin:
     - Kök CA: `ca.key` ve `ca.crt`. Öneri: RSA 2048+, uzun ömürlü ve açık X.509 uzantılarıyla (`-addext "basicConstraints=critical,CA:TRUE"` `-addext "keyUsage=critical,keyCertSign,cRLSign"` — eski OpenSSL ikilileri `-addext` desteklemiyorsa `-config ca.cnf -extensions v3_ca` kullanın); **`ca.crt` üzerinde sunucu SAN'ı bulunmamalıdır**.
     - Sunucu sertifikası: `server.key` ve `server.crt`. CA ile imzalanmalı (`keyUsage=digitalSignature,keyEncipherment`, `extendedKeyUsage=serverAuth`; eski OpenSSL'de `-extfile srv.cnf -extensions v3_req`). `subjectAltName` alanında **zorunlu `IP:127.0.0.1`** + Hub'ın sabit **LAN IPv4 adres(ler)i** + isteğe bağlı makine adı (`DNS:localhost,DNS:<hub-hostname>`) bulunmalıdır.
  2. `server.crt`, `server.key` ve `ca.crt` dosyalarını `%ProgramData%\MarketMMS\certs\` altına koyun.
  3. `ca.key` dosyasını **Hub'a koymayın**. Çevrimdışı ve şifreli saklayın. ACL betiği Hub'da `ca.key` bulursa kurulumu durdurur.
  4. `hub_config.json` → `tls` alanının `cert`, `key` ve `ca_cert` dosyalarını gösterdiğini ve çoklu NIC varsa `advertise_host` değerinin `server.crt` SAN ile eşleştiğini kontrol edin.
- **Etkilenen dosyalar:** `%ProgramData%\MarketMMS\certs\*`, `config\hub_config.json`.
- **Güvenlik uyarısı:**
  - Sunucu sertifikasını aynı CA ile yenilerseniz cihazlar yeniden eşleştirme gerektirmez (otomatik testle doğrulandı).
  - CA'yı değiştirirseniz tüm cihazlar "Sertifika Uyuşmuyor" gösterir ve yeniden eşleştirilmelidir.
  - Hub'ın LAN IP'si değişirse sunucu sertifikasındaki SAN alanını (ve tanımlıysa `advertise_host` değerini) güncelleyin.
- **Tamamlandığında yapılacak test:** `PAT-12`, `PAT-03`.

---

## C. Google Drive OAuth ve Hibrit Canlı Senkronizasyon Hazırlığı

> [!NOTE]
> **Kapsam Ayrımı (`ADR-022` — Pilot Kapsamına Dahil & Kodlandı):** Android Google Drive entegrasyonu Owner kararıyla pilot kapsamına alınmış ve `WP-3` (`ADR-022`, `google_sign_in: ^7.2.0`) olarak kodlanıp otomatik test + Debug APK ile doğrulanmıştır (`PAT-13/17/18` saha testleri **`C1/C2`** bekler). Yerel ağ testi için Windows Hub yerel yedek + USB tek başına çalışsa da, **Google Drive uzak yedek (`PAT-13`, `PAT-17`)** ve **`ADR-021` hibrit canlı senkronizasyon (`PAT-18`)** için `C1` ve `C2` (Desktop + Android + Web `serverClientId`) zorunlu Owner ön koşullarıdır; `drive_live_sync_secret_v1` dağıtımı `K-05` ile Hub DPAPI üzerinden otomatiktir.

### C1. Google Cloud projesi
- **Neden gerekli?** Drive yedekleme (`Faz C`) ve hibrit canlı senkronizasyon (`ADR-021`) yazılımı hazır olup sahte/mock transport ve `android_google_sign_in_oauth_test.dart` (`9/9`) ile test edilmiştir; gerçek Google hesabıyla hiç denenmemiştir (`PAT-13`, `PAT-17`, `PAT-18` **BLOCKED**).
- **Ne yapmalısınız?**
  1. Google Cloud Console'da mağazaya özel 2FA korumalı bir proje oluşturun.
  2. **Google Drive API**'yi etkinleştirin.
- **Etkilenen:** Yok (dış hesap).
- **Güvenlik uyarısı:** Projeyi market adına açılmış, iki adımlı doğrulamalı bir hesapta oluşturun.
- **Tamamlandığında yapılacak test:** `C2` ve üretim derlemeleri sonrasında `PAT-13`, `PAT-17` ve `PAT-18`.

### C2. Google OAuth yapılandırması (`K-05` Hub canlı senkron sırrı dahil)
- **Ne yapmalısınız?** [`docs/operations/BACKUP_AND_RESTORE_GUIDE.md`](docs/operations/BACKUP_AND_RESTORE_GUIDE.md) §4 ve [`docs/decisions/022-android-google-drive-oauth-design.md`](docs/decisions/022-android-google-drive-oauth-design.md) belgelerini izleyin:
  1. **OAuth Consent Screen:** Kapsam **yalnızca** `https://www.googleapis.com/auth/drive.file` olmalı ve 7 günlük token iptalinden kaçınmak için durum **`"In production"`** statüsüne geçirilmelidir.
  2. **Desktop app OAuth Client ID (Windows):** Oluşturup `scripts\package_windows_release.ps1 -GoogleDriveClientId "<ID>" -GoogleDriveClientSecret "<SECRET>"` ile paketleyin.
  3. **Android OAuth Client ID (`com.marketmms.market_pos`):** **Aynı Google Cloud projesinde** geliştirme (debug SHA-1) ve üretim (`B1` Release `market_mms_upload.jks` SHA-1; ileride Play kullanılırsa Play App Signing SHA-1) için tanımlayın (`SHA-256` değerini de denetim kaydına ekleyin).
  4. **Web Application OAuth Client ID (`serverClientId` — `google_sign_in` v7+ için ZORUNLU):** Aynı Google Cloud projesinde bir **Web application** OAuth Client ID oluşturun ve `scripts\package_android_release.ps1 -GoogleDriveWebClientId "<WEB_CLIENT_ID>"` ile derleyin (Web `client_secret` **asla** APK'ya konulmaz).
  5. **`drive_live_sync_secret_v1` (`K-05` Otomatik):** `ADR-021` hibrit canlı senkronizasyonu (`MARKET MMS LiveSync`) sırrı Hub'da DPAPI (`live_drive_sync_secret.dpapi`) ile otomatik üretilir ve eşleştirilmiş cihazlara TLS `GET /api/v1/sync/live-drive-config` üzerinden dağıtılır (manuel dağıtım gerekmez; rotasyon için `POST /api/v1/admin/live-drive-secret/rotate` kullanılır).
- **Etkilenen:** Derleme parametreleri (`MMS_GDRIVE_CLIENT_ID`, `MMS_GDRIVE_CLIENT_SECRET`, `MMS_GDRIVE_WEB_CLIENT_ID`) ve Hub DPAPI deposu (kimlik/gizli değerler asla Git deposuna yazılmaz).
- **Güvenlik uyarısı:**
  - Geniş kapsam (`drive`) eklemeyin.
  - OAuth client secret veya `drive_live_sync_secret_v1` değerini APK'ya, depoya, loglara veya SQLite tablolarına yazmayın.
- **Tamamlandığında yapılacak test:** `PAT-13` (yükleme/iptal), `PAT-17` (listeleme/`.part` indirme/ön doğrulamalı geri yükleme) ve `PAT-18` (Hub-kapalı 2 cihaz canlı senkronizasyon + Hub dönüş uzlaştırması).

---

## D. Temizlik ve Güvenlik

### D1. `MarketMmsSpike01` spike servisinin kaldırılması
- **Neden gerekli?**
  - Bu makinede **kurulu ve çalışıyor**: Status `Running`, StartType `Automatic` (21.11.2026'da okunarak görüldü).
  - Bu bir test servisi (`MMS_ENV=test_spike`). Üretim servisiyle port veya DB çakışması yaratabilir.
- **Ne yapmalısınız?**
  1. Yönetici PowerShell açın.
  2. `Stop-Service MarketMmsSpike01` komutunu çalıştırın.
  3. `test_spikes\spike_01_backend\service_wrapper\MarketMmsSpike01.exe uninstall` komutunu çalıştırın.
  4. İsterseniz XML ve EXE dosyalarını depodan kaldırın.
- **Etkilenen:** Windows servis kaydı, `service_wrapper/MarketMmsSpike01.*`.
- **Güvenlik uyarısı:** Önce servisin kullandığı DB'de saklanması gereken veri olmadığını kontrol edin.
- **Tamamlandığında yapılacak test:** `Get-Service MarketMmsSpike01` "bulunamadı" demeli. Üretim servisi kurulduktan sonra PAT-08.

### D2. Manuel test token'larının iptali / rotasyonu
- **Neden gerekli?**
  - `manual_test_env/init_test_env.dart` dosyasında bilinen, düz metin test cihaz token'ları var.
  - `manual_test_env/write_scripts.py` dosyasında bir admin secret var.
  - Bu değerler manuel test DB'sinde geçerli.
- **Ne yapmalısınız?**
  - Bu DB ve token'ları **pilotta asla kullanmayın**.
  - Üretim Hub'ını temiz bir DB ile kurun. Kurulum betiği admin secret'ı rastgele üretir. Cihazları yeniden eşleştirin.
  - Manuel test Hub'ı açık kalacaksa, bu token'lara sahip cihazları iptal edin.
- **Etkilenen:** `manual_test_env/` (bu oturumda `.gitignore` kapsamına alındı; hiçbir dosya silinmedi).
- **Güvenlik uyarısı:** Bu dosyaları paylaşmayın ve commit etmeyin.
- **Tamamlandığında yapılacak test:** Bilinen test token'ıyla üretim Hub'ına istek atın. `401` dönmeli.

### D3. Şifresiz test DB kopyalarının güvenli biçimde kaldırılması
- **Neden gerekli?** Aşağıdaki dosyalar şifresiz SQLite ve cihaz token özetleri içerir. Hepsi Git dışında, ama diskte duruyor:
  - `manual_test_env/market_master.db*`
  - `manual_test_env/market_master.db.bak_before_cola_cleanup`
  - Kök dizindeki `spike_master.db`
  - `manual_test_env/pepper.key`. Bu dosya bir **pepper**; DB'deki token özetlerini anlamlı kılan sırdır.
- **Ne yapmalısınız?**
  1. Bu dosyalara ihtiyacınız olup olmadığına karar verin.
  2. Gerekliyse şifreli bir arşive taşıyın.
  3. Gereksizse silin. Örnek: `Remove-Item manual_test_env\market_master.db.bak_before_cola_cleanup -Confirm`.
  
  Silme kararı sizindir; dosyalara dokunulmadı.
- **Etkilenen:** Yalnızca yukarıdaki yerel dosyalar.
- **Güvenlik uyarısı:**
  - Bu dosyalar gerçek satış verisi içeriyorsa, silmeden önce şifreli yedek alın.
  - Silme işlemi **geri alınamaz**.
- **Tamamlandığında yapılacak test:** `git status --ignored` ile dosyaların gittiğini doğrulayın.

### D4. Eski şifresiz restore koruyucu kopyaları
- **Neden gerekli?**
  - 21.11.2026 öncesi yapılan restore'lar koruyucu kopyayı `safety_snapshot_*.db` olarak şifresiz bıraktı.
  - Yeni sürüm bu kopyaları artık şifreli tutuyor, ancak eski dosyalara dokunmadı.
- **Ne yapmalısınız?** [`BACKUP_AND_RESTORE_GUIDE.md`](docs/operations/BACKUP_AND_RESTORE_GUIDE.md) §7'deki prosedürü uygulayın.
- **Etkilenen:** Kasada `backups\safety\*.db`, Hub'da `backups\safety_snapshots\*.db`.
- **Güvenlik uyarısı:** Silmeden önce ihtiyaç olmadığından emin olun.
- **Tamamlandığında yapılacak test:** Bu klasörlerde `.db` kalmamalı.

---

## E. Pilot Ortamı, Fiziksel Testler ve Kabul

### E1. Pilot ortamı ve gerekli donanım
- **Neden gerekli?** Fiziksel kabul testlerinin **hiçbiri** yapılmadı. Liste: [`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`](PHYSICAL_ACCEPTANCE_TEST_PLAN.md), **`PAT-01…PAT-18`**.
- **Gerekli donanım:**
  - **Hub:** Windows 10/11 bilgisayar. Yönetici hesabı ve sabit LAN IP gerekli.
  - **Kasa:** En az bir Windows kasa bilgisayarı ve USB HID barkod okuyucu.
  - **Mobil:** Kameralı en az **iki** Android cihaz. Birleşik Android manifesti ve uygulama yapılandırması en az **minSdk 24 (Android 7.0)** gerektirir; Android 8 veya üzeri önerilir. Biri düşük donanımlı olmalı.
  - **Ağ:** Mağaza Wi-Fi router'ı. "AP/istemci izolasyonu" kapalı olmalı.
  - **Depolama:** En az bir USB bellek (FAT32/NTFS). Disk dolu testi için ayrıca küçük kapasiteli bir USB.
  - **Barkodlu ürünler:** Gerçek EAN-13 ürünler ve bilinmeyen bir barkod.
  - İsteğe bağlı: Google hesabı (C1/C2 tamamlandıysa).
- **Ne yapmalısınız?**
  1. B1 ve B2'yi tamamlayın.
  2. Hub'ı temiz DB ile kurun.
  3. `PAT-01…PAT-18`'i sırayla uygulayın ve her test için kanıtı kaydedin.
- **Güvenlik uyarısı:** Pilotu gerçek satış verisiyle değil, test ürünleriyle başlatın. Restore ve çökme testlerinden önce şifreli yedek alın.

### E2. Faz kabulleri
- **Neden gerekli?** Yol haritasındaki 7 fazın hiçbiri sizin tarafınızdan kabul edilmiş sayılmaz.
- **Ne yapmalısınız?** Fiziksel testler geçtikten sonra her faz için kabul kararı verin. Ardından `docs/MASTER_ROADMAP.md` dosyasındaki durum sütunu güncellenir.
