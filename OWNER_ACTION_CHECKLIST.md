# MARKET MMS — Owner (Proje Sahibi) İşlem Listesi

*Tarih: 22 Kasım 2026 (Release 1.0 + Phase 1.1 + Aşama 1/3/4/2 Tamamlama) · Kaynaklar: [`docs/RELEASE_1_0_FINAL_DELIVERY_REPORT.md`](docs/RELEASE_1_0_FINAL_DELIVERY_REPORT.md), [`docs/RELEASE_1_0_PHASE_1_VERIFICATION_REPORT.md`](docs/RELEASE_1_0_PHASE_1_VERIFICATION_REPORT.md), [`docs/RELEASE_1_0_PHASE_1_1_FINALIZATION_REPORT.md`](docs/RELEASE_1_0_PHASE_1_1_FINALIZATION_REPORT.md), [`docs/LIVE_PROJECT_STATUS.md`](docs/LIVE_PROJECT_STATUS.md)*

Bu listede **sizin** karar, gizli anahtar, ortam temizliği veya fiziksel test gerektiren maddeleriniz yer alır. Release 1.0 + Phase 1.1 + 22 Kasım Aşama 1/3/4/2 yazılım geliştirme kapsamı (`P-BLOCK-1..3` / `DEC-REV-1..5`, `WP-1` DHCP reconnect & mobil ergonomi & tema kalıcılığı, `A7` Windows `qr_flutter` QR görseli, `K-05` Hub TLS-pinned canlı Drive sır/kayıt defteri provizyonu, Android kapalıyken arka plan yedeği `ADR-020` [`JOB_ID = 70201`], Google Drive listeleme/indirme/kontrollü geri yükleme `Faz C` ve Hub öncelikli Google Drive hibrit canlı senkronizasyon `ADR-021`) teknik olarak uygulanmış ve **790/790 otomatik test** + **Windows/Android debug build** ile doğrulanmıştır. Phase 1.1 kapsamında Android sürümü `1.0.0+1` olarak sabitlenmiş, Android NDK `28.2.13676358` doğrulanmış ve Android Google Drive OAuth için **Seçenek A (`google_sign_in`)** + **pilot kapsamına dahil edilmesi** Owner kararıyla **`ADR-022`** içinde tasarımsal olarak kesinleştirilmiştir (OAuth implementasyonu Phase 2 kapsamındadır). Ancak fiziksel kabul testleri (`PAT-01…PAT-18`), üretim Android imza anahtarı (`B1`), üretim Hub TLS sertifikaları (`B2`), Google Cloud OAuth kurulumu (`C1/C2`), ortam temizliği (`D1–D4`) ve `ADR-022` Phase 2 implementasyonu henüz tamamlanmadığı için sistem sahaya / üretime tam hazır ilan edilmemiştir (**`SOFTWARE VALIDATED (790/790) — PAT-01…18 BLOCKED`**).

> **Bu belgede hiçbir gerçek parola, token, sertifika veya özel anahtar yoktur; eklemeyin.**

**Önerilen sıra:**
1. Kararlar (A) — `A1`, `A6` (`C1/C2` hazırlığı ve `ADR-022` Phase 2 takvimi), `A8`. (`A7` QR görseli `qr_flutter` ile ve `A6` `K-05` Seçenek 1 Hub TLS-pinned dağıtım modeliyle kodlanmıştır.)
2. Üretim anahtarları ve sertifikalar (B) — `B1` (Android Keystore) ve `B2` (Hub TLS `ca.crt` + `IP:127.0.0.1` ve LAN IP SAN'lı `server.crt`).
3. Temizlik (D) — `D1` (`MarketMmsSpike01`) ve `D2–D4` test kalıntıları.
4. Pilot donanımı ve fiziksel kabul testleri (E) — `PAT-01…PAT-18`.
5. Google Drive OAuth (`C1/C2`) ve `ADR-022` (`google_sign_in`, Phase 2) — salt yerel Hub+USB başlangıç pilotu için en sona kalabilir; ancak `PAT-13`, `PAT-17` ve `PAT-18` (hibrit Drive canlı senkronizasyon) için ön koşuldur. (`drive_live_sync_secret_v1` dağıtımı `K-05` ile Hub üzerinden otomatize edilmiştir.)

---

## Özet Tablo

| # | Madde | Tür | Durum / Engellediği iş | Öncelik |
|---|---|---|---|---|
| A1 | ADR-015…022 kararları | **Teknik Tamam / Tasarım Onaylı** | `ADR-015, 016, 018, 020, 021` teknik olarak uygulandı (`PAT-01…18` saha doğrulaması **BLOCKED**); `ADR-017` `PAT-12` sonrası kesin onay, `ADR-019` pilot sonrası, `ADR-022` **DESIGN APPROVED — PENDING PHASE 2 IMPLEMENTATION** (Seçenek A `google_sign_in`, pilot kapsamına dahil) | **Orta** |
| A2 | Git commit ve sürüm takibi | **Phase 1.1 Commit Onaylandı (`a118434`); Yeni Paket Unstaged** | Release 1.0 (`a02a3c6`) ve Phase 1.1 (`a118434`) push edildi; 22 Kasım Aşama 1/3/4/2 değişiklikleri çalışma ağacında unstaged durumda (Owner commit onayı bekler); 4 yerel dosya (`.vscode/settings.json`, `*.bat`) commit dışı korunur | İzleme / Commit Onayı |
| A3 | Kategori/KDV senkronu (ADR-019) | **DEFERRED_POST_PILOT** | Pilotta 7 geçici %20 KDV kısıtıyla kabul; pilot sonrası migrasyon | Orta (pilot sonrası) |
| A4 | Discovery TLS (ADR-018 §2.2) & `P-BLOCK-1..3` | **IMPLEMENTED (Otomatik Testli)** | `DEC-REV-1..5` + `WP-1` (`networkError` DHCP/Wi-Fi reconnect) kodlandı; fiziksel doğrulama **`PAT-03` & `PAT-12`** bekleniyor (**BLOCKED**) | **Saha Testi (`PAT-03`, `PAT-12`)** |
| A5 | Android kapalıyken arka plan yedek (`ADR-020`) | **IMPLEMENTED (`JobScheduler`, `JOB_ID = 70201`)** | `MmsBackgroundBackupJobService` + headless `FlutterEngine` + Keystore ile harici bağımlılıksız uygulandı; fiziksel doğrulama **`PAT-16`** bekleniyor (**BLOCKED**) | **Saha Testi (`PAT-16`)** |
| A6 | Google Drive Yedek + Hibrit Canlı Senkron (`ADR-021`, `K-05`) + Android OAuth (`ADR-022`) | **Hibrit + `K-05` IMPLEMENTED / `ADR-022` Phase 2 Bekler** | `MMSENV01` hibrit canlı senkron + `K-05` Hub TLS-pinned `GET /api/v1/sync/live-drive-config`, admin secret rotation ve kalıcı `FileDriveAuthorizedRegistryStore` uygulandı; **yalnızca `ADR-022` (`google_sign_in`) Phase 2**, **`C1/C2`** Google Cloud kurulumu ve **`PAT-13/17/18`** saha doğrulaması bekleniyor | **Yüksek (`ADR-022` Phase 2, `C1/C2`, `PAT-13/17/18`)** |
| A7 | QR görseli paketi (`qr_flutter`) | **IMPLEMENTED (`qr_flutter: ^4.1.0`)** | Windows `PairingApprovalPanel` içinde canlı kare QR (`Key('pairing_qr_image')`) eklendi; fiziksel doğrulama **`PAT-03`** bekleniyor (**BLOCKED**) | **Saha Testi (`PAT-03`)** |
| A8 | Güncelleme paketi imzalama ve merkezi hata izleme | Karar + sertifika | İmzalı güncelleme / merkezi tanı | Orta |
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
  | 022 | Android Google Drive OAuth Tasarımı (**Seçenek A — `google_sign_in`**) | **`DESIGN APPROVED — PENDING PHASE 2 IMPLEMENTATION`** (Phase 1.1 ve Aşama 1/3/4/2'de kodlanmadı) | Phase 2 implementasyonu öncesi `C1/C2` (Web `serverClientId` + Android SHA-1 + "In production") yapılandırın |

- **Etkilenen dosyalar:** `docs/decisions/015…022-*.md`, `docs/decisions/README.md`, `docs/RELEASE_1_0_FINAL_DELIVERY_REPORT.md`, `docs/RELEASE_1_0_PHASE_1_VERIFICATION_REPORT.md`, `docs/RELEASE_1_0_PHASE_1_1_FINALIZATION_REPORT.md`, `docs/LIVE_PROJECT_STATUS.md`.
- **Tamamlandığında yapılacak test:** Fiziksel kabul testleri **`PAT-01…PAT-18`** (şu an tamamı **BLOCKED**).

### A2. Değişikliklerin commit edilmesi ve sürüm takibi
- **Mevcut Durum:**
  - Release 1.0 (`a02a3c6`) ve Phase 1.1 (`a118434`) commit'leri `origin/main` üzerinde kayıtlıdır; **22 Kasım 2026 Aşama 1/3/4/2 değişiklikleri `HEAD = a118434` üzerinde çalışma ağacında unstaged beklemektedir** (Owner onayı olmadan stage/commit/push yapılmaz).
  - Bilinçli olarak commit dışı bırakılan 4 korunan yerel dosya (`.vscode/settings.json`, `run_windows_client.bat`, `start_master_hub.bat`, `stop_master_hub.bat`) ve çalışma zamanı verileri/servisleri dokunulmadan korunur.
- **Güvenlik kontrolü:**
  - `git status --ignored` / `git diff --cached` içinde şu dosyalar **asla bulunmaz**: `manual_test_env/`, `*.db`, `*.key`, `pepper.dpapi`, `live_drive_sync_secret.dpapi`, `android/key.properties`, `*.jks`.
- **Tamamlandığında yapılacak test:** Dört test süitinin (**`790/790`**) ve statik analizlerin + Windows/Android debug derlemelerinin tam yeşil olduğu doğrulanmıştır.

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

### A6. Google Drive Yedekleme, Hibrit Canlı Senkronizasyon (`ADR-021`, `K-05`) ve Android OAuth Kararı (`ADR-022`)
- **Mevcut Durum:**
  - **Uygulananlar (Otomatik Testli):** Uzak şifreli yedek listeleme/indirme/ön doğrulamalı geri yükleme (`Faz C`, `PAT-17`), Hub-öncelikli `MMSENV01` hibrit canlı senkronizasyon motoru (`ADR-021`, `MARKET MMS LiveSync` klasörü, 26 otomatik senaryo, `PAT-18`) ve **Seçenek 1 (`K-05`) Hub TLS-pinned provizyonu**:
    - Hub tarafında Windows DPAPI korumalı `LiveDriveSecretManager` (`live_drive_sync_secret.dpapi`), `strictTenantStorePaths` korumalı `GET /api/v1/sync/live-drive-config` (`Cache-Control: no-store`, `ACTIVE`/`REVOKED` cihaz listesi + `live_sync_secret`) ve loopback + admin korumalı `POST /api/v1/admin/live-drive-secret/rotate`.
    - İstemci tarafında atomik `FileDriveAuthorizedRegistryStore` (`drive_authorized_devices.json`), `HubLiveDriveConfigClient`, `DriveAuthorizedRegistryNotifier` ve başarılı Hub sync sonrası 5 dk throttle'lı provizyon (`live_sync_secret` güvenli depoya, `ACTIVE`/`REVOKED` cihaz kayıt defteri diske yazılır).
  - **Owner Kararı & Phase 2 Kapsamı (`ADR-022`):** Owner, Android Drive entegrasyonunu **pilot kapsamına dahil etmiş** ve yöntem olarak **Seçenek A (`google_sign_in`)** tasarımını onaylamıştır (`DESIGN APPROVED — PENDING PHASE 2 IMPLEMENTATION`). Mevcut aşamada Android OAuth kodu yazılmamış ve `google_sign_in` eklenmemiştir; şu an Android'de `connect()` çağrısı hâlâ **`ERR_DRIVE_PLATFORM_UNSUPPORTED`** döndürmektedir.
- **Ne yapmalısınız?**
  1. `B1` Release keystore oluşturduktan sonra **SHA-1** ve **SHA-256** parmak izlerini `C1/C2` Google Cloud OAuth kurulumunda kaydedin.
  2. `C1/C2` altında aynı Google Cloud projesinde **Desktop app Client ID**, **Android OAuth Client ID** (`com.marketmms.market_pos` + SHA-1) ve `google_sign_in` için zorunlu **Web application Client ID (`serverClientId`)** oluşturun; OAuth izin ekranını **`"In production"`** durumuna alın.
  3. Phase 2 (`ADR-022`) onayı verdiğinizde `google_sign_in` entegrasyonu başlatılacaktır.
- **Etkilenen dosyalar (`K-05` Tamamlandı / `ADR-022` Phase 2):**
  - Tamamlanan (`K-05`): `test_spikes/spike_01_backend/lib/security/live_drive_secret_manager.dart`, `auth_middleware.dart`, `bin/server.dart`, `lib/features/sync/data/drive_authorized_registry_store.dart`, `hub_live_drive_config_client.dart`, `application/drive_authorized_registry_notifier.dart`, `sync_providers.dart`, `lib/main.dart`.
  - Phase 2 (`ADR-022`): `pubspec.yaml`, Android yapılandırması, `lib/features/backup/application/google_drive_connect_service.dart`, `lib/features/backup/backup_providers.dart`.
- **Güvenlik uyarısı:** Kapsam her koşulda yalnızca `drive.file` kalmalıdır (`ADR-011`). Web `client_secret` ve `drive_live_sync_secret_v1` değerleri APK'ya, depoya, loglara veya SQLite'a **asla** yazılmamalıdır.
- **Tamamlandığında yapılacak test:** `K-05` backend + istemci provizyon otomatik testleri geçti; Phase 2 (`ADR-022`) + `C1/C2` sonrası `PAT-13` (Windows & Android), `PAT-17` (Drive geri yükleme) ve `PAT-18` (2 cihaz hibrit canlı senkronizasyon).

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
     - Kök CA: `ca.key` ve `ca.crt`. Öneri: RSA 2048+, uzun ömürlü ve açık X.509 uzantılarıyla (`-addext "basicConstraints=critical,CA:TRUE"` `-addext "keyUsage=critical,keyCertSign,cRLSign"`); **`ca.crt` üzerinde sunucu SAN'ı bulunmamalıdır**.
     - Sunucu sertifikası: `server.key` ve `server.crt`. CA ile imzalanmalı (`keyUsage=digitalSignature,keyEncipherment`, `extendedKeyUsage=serverAuth`). `subjectAltName` alanında **zorunlu `IP:127.0.0.1`** + Hub'ın sabit **LAN IPv4 adres(ler)i** + isteğe bağlı makine adı (`DNS:localhost,DNS:<hub-hostname>`) bulunmalıdır.
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
> **Kapsam Ayrımı (`ADR-022` — Pilot Kapsamına Dahil):** Android Google Drive entegrasyonu Owner kararıyla pilot kapsamına dahil edilmiştir (`ADR-022`, Seçenek A — `google_sign_in`, implementasyon Phase 2). Başlangıç yerel ağ testi için Windows Hub yerel yedek + USB çalışsa da, **Google Drive uzak yedek (`PAT-13`, `PAT-17`)** ve **`ADR-021` hibrit canlı senkronizasyon (`PAT-18`)** için `C1`, `C2` (Desktop + Android + Web `serverClientId`), `drive_live_sync_secret_v1` ve Phase 2 `ADR-022` kodlaması zorunlu ön koşullardır.

### C1. Google Cloud projesi
- **Neden gerekli?** Drive yedekleme (`Faz C`) ve hibrit canlı senkronizasyon (`ADR-021`) yazılımı hazır olup sahte/mock transport ile test edilmiştir; gerçek Google hesabıyla hiç denenmemiştir (`PAT-13`, `PAT-17`, `PAT-18` **BLOCKED**).
- **Ne yapmalısınız?**
  1. Google Cloud Console'da mağazaya özel 2FA korumalı bir proje oluşturun.
  2. **Google Drive API**'yi etkinleştirin.
- **Etkilenen:** Yok (dış hesap).
- **Güvenlik uyarısı:** Projeyi market adına açılmış, iki adımlı doğrulamalı bir hesapta oluşturun.
- **Tamamlandığında yapılacak test:** `C2` ve Phase 2 `ADR-022` sonrasında `PAT-13`, `PAT-17` ve (2 cihaz + `drive_live_sync_secret_v1` ile) `PAT-18`.

### C2. Google OAuth yapılandırması ve `drive_live_sync_secret_v1`
- **Ne yapmalısınız?** [`docs/operations/BACKUP_AND_RESTORE_GUIDE.md`](docs/operations/BACKUP_AND_RESTORE_GUIDE.md) §4 ve [`docs/decisions/022-android-google-drive-oauth-design.md`](docs/decisions/022-android-google-drive-oauth-design.md) belgelerini izleyin:
  1. **OAuth Consent Screen:** Kapsam **yalnızca** `https://www.googleapis.com/auth/drive.file` olmalı ve 7 günlük token iptalinden kaçınmak için durum **`"In production"`** statüsüne geçirilmelidir.
  2. **Desktop app OAuth Client ID (Windows):** Oluşturup Windows derlemesine `--dart-define=MMS_GDRIVE_CLIENT_ID=…` ile verin.
  3. **Android OAuth Client ID (`com.marketmms.market_pos`):** **Aynı Google Cloud projesinde** geliştirme (debug SHA-1) ve üretim (`B1` Release `market_mms_upload.jks` SHA-1; ileride Play kullanılırsa Play App Signing SHA-1) için tanımlayın (`SHA-256` değerini de denetim kaydına ekleyin).
  4. **Web Application OAuth Client ID (`serverClientId` — `google_sign_in` v7+ için ZORUNLU):** Aynı Google Cloud projesinde bir **Web application** OAuth Client ID oluşturun; yalnızca Client ID string'i Android derlemesine (`--dart-define=MMS_GDRIVE_WEB_CLIENT_ID=…`, Phase 2) verilir, Web `client_secret` **asla** APK'ya konulmaz.
  5. **`drive_live_sync_secret_v1`:** `ADR-021` hibrit canlı senkronizasyonu (`MARKET MMS LiveSync`) için yedek parolasından bağımsız yüksek entropili gizliyi mağaza cihazlarına güvenli kanaldan dağıtın.
- **Etkilenen:** Derleme komutu ve güvenli depo (kimlik/gizli değerler asla Git deposuna yazılmaz).
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
