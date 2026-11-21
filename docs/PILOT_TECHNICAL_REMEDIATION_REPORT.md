# MARKET MMS — Bütünleşik Teknik Düzeltme, ADR Uygulaması ve Pilot Hazırlık Raporu

- **Tarih:** 21 Kasım 2026
- **Proje / Dizin:** MARKET MANAGEMENT SYSTEM (MARKET MMS) · `market-pos`
- **Koordinasyon ve Denetim:** Orchestrator (Neon) · Uygulama: Gemini 4 Hydrogen · Bağımsız Güvenlik/Mimari Reviewer alt ajanı (`6c673107-dd66-418a-a8dc-60b904a44ad7`)
- **Durum Uyarısı:** **Proje tamamlanmış veya üretime hazır değildir. Fiziksel kabul testleri (`PAT-01…15`) henüz yapılmamıştır (`BLOCKED`). Bu belge bir üretim yayını veya faz kabulü yerine geçmez.**

---

## A. Yönetici Özeti

1. **Çalışmanın amacı:** Önceki 7 faz ve 7A–7D teknik tamamlama çalışmalarını, Offline-First SQLite/Drift + FIFO Outbox + `client_seq` + idempotency protokolünü, integer kuruş + Half-Up yuvarlama standardını ve tek-yazarlı Hub mimarisini bozmadan; Owner tarafından karara bağlanan **ADR-015…020** kararlarını kod tabanına ve proje dokümantasyonuna uygulamak, bağımsız güvenlik/mimari incelemede yakalanan kritik/yüksek bulguları gidermek ve fiziksel kabul testleri öncesindeki yazılım hazırlığını tamamlamaktır.
2. **Yapılan ana değişiklikler:**
   - **ADR-015 (`CONFIRMED`):** `--config=` tek yapılandırma kaynağında `ROOT_CA_CERT_FILE` ve `ADMIN_SECRET` ortam değişkeni sızıntıları engellendi; `tls` nesnesi katı anahtar denetimine bağlandı; eksik/okunamayan `ca.crt` durumunda `/api/v1/pairing/session` fail-closed `503 ERR_CA_CERT_UNAVAILABLE` döndü; `POST /api/v1/devices/revoke` loopback + yapılandırılmış `ADMIN_SECRET` denetimine (`_verifyLoopbackAndAdmin`) bağlandı; `backup_dir` atlanırsa `System32` yerine `<configDir>/backups` varsayılanı ve `admin/restore` bozuk JSON'da `400 ERR_INVALID_JSON` yanıtı sağlandı.
   - **ADR-016 (`CONFIRMED`):** `BackupOperationLock`, yalnızca timeout kısaltmasıyla değil **10 sn heartbeat + 60 sn stale eşiği + atomik `.tmp`→rename + sahip (`owner_id`/`token`) doğrulamalı devralma + 5 sn 0-bayt çökme artığı kurtarması + sahip doğrulamalı `.recovering` mutex + `lostOwnership` tespiti** ile sertleştirildi. İstemci (`prune`, `export`, `import`, `delete`) ve Hub (`admin/backup`, `admin/restore`, `admin/backup/prune`, zamanlanmış temizlik) işlemleri ortak kilide bağlandı. Restore akışında bekleyen Outbox kayıtları ve monotonik `client_seq` korundu. `BACKUP_AND_RESTORE_GUIDE.md` §7 kurtarma prosedürü ve özel parola uyarısı düzeltildi.
   - **ADR-017 (`PARTIALLY_CONFIRMED / IN_REVIEW`):** `MmsPinnedTlsClientFactory` içindeki CA-pin/leaf-pin karışıklığı ve CA-bundle sızması giderildi (`_encodeMatchedCertificatesAsPem` + `SecurityContext(withTrustedRoots: false)`). Aynı CA ile yenilenmiş sunucu sertifikası kabul edilirken; yabancı CA / MITM / CA öz-sunumu (`TlsPinMismatchException` / `TLS_PIN_MISMATCH`) ile güvenilen CA altında IP SAN, hostname SAN, süre sonu veya henüz geçerli değil hataları (`TlsCertificateValidationException` / `TLS_CERT_ERROR`) ayrıştırıldı. Paralel istek yarışı (`_PinRejectionLog` FIFO kuyruk + `_inFlight` sayacı), ham `HandshakeException` sızıntısı ve Outbox boşken downlink TLS hata yutulması kapatıldı; `TLS_PIN_MISMATCH` ve `TLS_CERT_ERROR` durumları sağlık, sync koordinatörü, rozetler (`StatusBadge`, `DiagnosticsView`, `_CompactStatusPill`) ve Türkçe hata eşleyici (`UserFriendlyErrorMapper`) genelinde ayrı görünür hale getirildi.
   - **ADR-018 (`CONFIRMED` §2.1 & Seçenek C):** UDP keşif yükü (`protocol_version: "1.0"`) korundu; eşleştirilmiş cihazlarda keşif yalnızca `https://` kullanacak şekilde testle güvence altına alındı (HTTP fallback yok). `PairingQrPayload` `ca_fingerprint` ve `UNKNOWN` -> `null` ayrıştırması düzeltildi; yerleşik QR görseli olmadığı için `PAT-03`'te manuel kopyala-yapıştır akışı tanımlandı. **Mevcut eşleştirme protokolüne dokunulmazlık kuralı gereği çözülmeyen 3 protokol bloklayıcısı (`P-BLOCK-1..3`) tespit edilip belgelendi.**
   - **ADR-019 (`DEFERRED_POST_PILOT`):** Hub/istemci DB şeması (`v3`/`v4`), `PRODUCT_UPSERT` ve `CATEGORY_UPSERT` üzerinde değişiklik yapılmadı; pilot için onaylanan **7 geçici %20 KDV operasyonel kısıtı**, **8 teknik risk** ve pilot sonrası **9 kalıcı tasarım gereksinimi** ADR-019, `OWNER_ACTION_CHECKLIST.md` ve `PHYSICAL_ACCEPTANCE_TEST_PLAN.md` içine işlendi.
   - **ADR-020 (`DEFERRED_POST_PILOT`):** `workmanager`, `MainActivity.kt` ve `pubspec.yaml` değiştirilmedi; `AndroidKeystoreTokenStore` içindeki `MissingPluginException` / `PlatformException` durumları ham detay/sır sızdırmadan fail-closed `SecureStorageException` olarak eşlendi ve `OWNER_ACTION_CHECKLIST.md` içinde gerçek `minSdk 24 (Android 7.0)` değeri düzeltildi.
3. **Genel sonuç:** 4 test süitinin tamamı son kod düzenlemelerinden sonra CPU çakışması olmadan sıralı çalıştırıldı ve **730 testten 730'u geçti (0 başarısız, 0 atlanan)**; 4 pakette statik analiz çıkış kodu `0` oldu (0 yeni uyarı/hata). Bağımsız Reviewer alt ajanının tespit ettiği 5 HIGH ve 3 MEDIUM bulgunun tamamı ile 2 LOW doküman/CA talimat bulgusu giderildi; düşük öncelikli 1 gözlem (`L-3`: `WindowsDpapiTokenStore.readSecret` içindeki tekil anahtar çözme hatasının `null` dönmesi) kapsam sınırı gereği açık düşük öncelikli teknik borç olarak bırakıldı.
4. **Pilot hazırlık durumu:** Yazılım düzeltmeleri onaylı kapsamda tamamlanmış olmakla birlikte, **`P-BLOCK-1..3` protokol uyuşmazlıkları çözülmeden ve Owner ön koşulları (`B1`, `B2`) + `PAT-01…15` fiziksel kabul testleri tamamlanmadan sistem fiziksel pilota ve üretime hazır değildir.**

---

## B. Değişen Dosyalar

> **Kapsam Ayrımı:** Çalışma ağacında `origin/main` (`8454933`) sonrasında önceki oturumlardan kalma unstaged dosya değişiklikleri mevcuttur. Aşağıdaki liste **yalnızca bu Bütünleşik Teknik Düzeltme, ADR Uygulaması ve Pilot Hazırlık oturumunda (`21.11.2026 15:24+`) oluşturulan veya güncellenen dosyaları** kapsar (23 kaynak kodu, 12 test, 15 doküman = **50 dosya**, tümü unstaged ve commit edilmemiştir). `android/app/src/main/kotlin/com/marketmms/market_pos/MainActivity.kt`, `pubspec.yaml`, `lib/features/security/data/device_pairing_client.dart`, `test_spikes/spike_01_backend/lib/discovery/discovery_responder.dart` ve veritabanı şema dosyalarına dokunulmamıştır.

### B.1 Kaynak Kod Dosyaları (23 Dosya)

| # | Dosya Yolu | Yapılan Değişiklik | Gerekçe | İlgili ADR | Test Kanıtı |
|---|---|---|---|---|---|
| 1 | `test_spikes/spike_01_backend/lib/config/hub_config.dart` | Katı `_allowedTlsKeys` denetimi; eksik `backup_dir` için `<configDir>/backups` varsayılanı | Yazım hatalı `tls` anahtarlarını reddetmek ve Windows `LocalService` altında `System32` fallback'ini önlemek (`M-1`) | ADR-015 | `rel01_hub_config_test` (17/17) |
| 2 | `test_spikes/spike_01_backend/bin/server.dart` | `ROOT_CA_CERT_FILE` / `ADMIN_SECRET` `--config=` env sızıntısı kapatıldı; `/pairing/session` fail-closed `503`; `/devices/revoke` loopback+admin; `_backupOperationLock` Hub kapsamı (`admin/backup`, `admin/restore`, `admin/backup/prune`, scheduler prune); `/backup/snapshot` `_backupTargetDir` + `writeQueue` koruması; `/admin/restore` `400 ERR_INVALID_JSON`; `startHubFromArgs` + `dbFile.parent` oluşturma | Tek konfigürasyon tutarlılığı (`H-3`, `M-1`, `M-2`), Hub yedek/restore kilit bütünlüğü (`H-4`) | ADR-015, ADR-016 | `rel01_hub_config_test` (17), `hub_scheduled_backup_test` (10), `s1_api_hardening_test` (14), `s4_device_pairing_test` (32) |
| 3 | `packages/mms_client_storage/lib/src/backup/backup_operation_lock.dart` | v2 kilit biçimi (`owner_id`/`token`, `heartbeat_at`), `10 sn` heartbeat, `60 sn` stale, `5 sn` `emptyLockStaleAfter`, sahip doğrulamalı `.recovering` mutex, `_beat` yakın-süre aşımı ve `_markOwnershipLost`, v1 geriye dönük uyumu | Çökme sonrası 1 saatlik kilit blokajını gidermek, TOCTOU ve yarış koşullarını önlemek (`H-4`) | ADR-016 | `backup_operation_lock_test` (14/14) |
| 4 | `packages/mms_client_storage/lib/src/sync/tls_errors.dart` | `TlsPinMismatchReason`, `TlsCertificateFailureKind`, `TlsCertificateValidationException` sınıfları eklendi *(yeni)* | CA zinciri/leaf pin uyuşmazlıkları ile SAN/IP/tarih hatalarını ayrıştırmak | ADR-017 | `tls_pinned_client_factory_test` (5), `tls_pin_mismatch_sync_test` (5) |
| 5 | `packages/mms_client_storage/lib/src/models/sync_response.dart` | `SyncFailureKind.tlsCertError` ve `SyncResponse.tlsCertError` kurucusu eklendi | Senkron katmanının SAN/tarih TLS hatalarını pin ve ağ hatalarından ayırması (`H-2`) | ADR-017 | `tls_pin_mismatch_sync_test` (5), `tls_error_surface_test` (4) |
| 6 | `packages/mms_client_storage/lib/src/sync/sync_transport.dart` | `TlsCertificateValidationException` -> `SyncResponse.tlsCertError` dönüşümü (HTTP downgrade yok) | Sertifika doğrulama hatalarının sıradan ağ hatasına düşmesini engellemek (`H-2`) | ADR-017 | `tls_pin_mismatch_sync_test` (5) |
| 7 | `packages/mms_client_storage/lib/src/sync/client_sync_service.dart` | `SyncBatchResult.tlsCertError`, `maxBackoff` + `RETRY`/`client_seq` korunumu (`TLS_CERT_ERROR`), boş Outbox'ta `syncProducts`/`syncSales` TLS hatalarının `StateError` ile yukarı iletilmesi | Outbox bütünlüğü korunurken `TLS_CERT_ERROR` teşhisinin kaybolmamasını sağlamak (`H-2`) | ADR-017 | `tls_pin_mismatch_sync_test` (5), `tls_error_surface_test` (4) |
| 8 | `lib/core/security/tls_pinned_client_factory.dart` | `_encodeMatchedCertificatesAsPem` CA-bundle sızma yalıtımı, CA-pin modunda koşulsuz `false`, 7 durum ayrıştırma (`classifyCaTrustedCertError`), bounded FIFO + `_inFlight` sayacı içeren `_PinRejectionLog`, `KEY_USAGE_BIT_INCORRECT`/CA öz-sunumu fallback'i, initializing formal `this._isCaPinnedMode` | CA-pin / leaf-pin karışıklığını, paralel istek yarışını ve ham `HandshakeException` sızıntısını önlemek (`H-1`) | ADR-017 | `tls_pinned_client_factory_test` (5/5 gerçek soket), `flutter analyze` (0 issue) |
| 9 | `lib/core/security/secure_token_store.dart` | `SecureStorageException` sınıfına isteğe bağlı `code` alanı eklendi | Keystore hata kodlarını sır sızdırmadan üst katmana taşımak | ADR-020 | `secure_storage_fail_closed_test` (5/5) |
| 10 | `lib/core/security/android_keystore_token_store.dart` | Tüm kanal çağrılarında `MissingPluginException` / `PlatformException` -> fail-closed `SecureStorageException` dönüşümü | Android'de güvenli depo hatalarının ham platform istisnası sızdırmasını önlemek | ADR-020 | `secure_storage_fail_closed_test` (5/5) |
| 11 | `lib/core/network/api_response.dart` | `CentralHealthResponse.tlsPinMismatch` ve `tlsCertError` durumları/yardımcıları | Sağlık kontrolünün pin vs SAN/tarih hatalarını ayrı raporlaması (`H-1`, `H-2`) | ADR-017 | `api_client_test` (15), `tls_error_surface_test` (4) |
| 12 | `lib/core/network/api_client.dart` | `checkHealth` içine `TlsCertificateValidationException` + `HandshakeException` fail-closed işleyicileri; `get`/`post` içine `ApiException` sarımı | Ham TLS/Handshake istisnalarının `OFFLINE` maskesine düşmesini ve çağırana sızmasını önlemek (`H-1`) | ADR-017 | `api_client_test` (#10, #11), `tls_pinned_client_factory_test` |
| 13 | `lib/core/utils/user_friendly_error_mapper.dart` | Türkçe `TLS_PIN_MISMATCH`/`TLS_CERT_ERROR`/`sertifika` eşlemeleri 220-karakter kesmesinden önce alındı; `'formatexception'` küçük harf düzeltmesi | Uzun Türkçe TLS mesajlarının genel fallback ile yutulmasını önlemek (`H-2`) | ADR-017 | `tls_error_surface_test` #1 |
| 14 | `lib/features/diagnostics/domain/system_status.dart` | `BackendConnectionState` içine `tlsPinMismatch` ve `tlsCertError` eklendi | UI durum modelinde sertifika ve ağ kopukluğu ayrımı (`H-2`) | ADR-017 | `tls_error_surface_test` #2, #3 |
| 15 | `lib/features/diagnostics/application/system_status_notifier.dart` | `TLS_PIN_MISMATCH` -> `tlsPinMismatch`, `TLS_CERT_ERROR` -> `tlsCertError` durum eşlemesi | Sertifika hatalarının `offline` durumuna düşmesini önlemek (`H-2`) | ADR-017 | `tls_error_surface_test` #3, `system_status_notifier_test` (5) |
| 16 | `lib/features/diagnostics/presentation/widgets/status_badge.dart` | `tlsPinMismatch` (`SERTİFİKA UYUŞMUYOR`) ve `tlsCertError` (`SERTİFİKA HATASI (SAN/TARİH)`) rozetleri | Kullanıcıya `ÇEVRİMDIŞI` yerine doğru uyarı rozeti göstermek (`H-2`) | ADR-017 | `tls_error_surface_test` #2 |
| 17 | `lib/features/diagnostics/presentation/screens/diagnostics_view.dart` | `SyncCoordinatorStatus.tlsCertError` ve `BackendConnectionState.tlsPinMismatch`/`tlsCertError` kart görünümleri | Tanılama ekranında SAN/tarih sertifika hatalarını göstermek (`H-2`) | ADR-017 | `tls_error_surface_test` |
| 18 | `lib/features/sync/domain/sync_coordinator_state.dart` | `SyncCoordinatorStatus.tlsCertError` eklendi | Koordinatör düzeyinde sertifika vs ağ hatası ayrımı (`H-2`) | ADR-017 | `tls_error_surface_test` #4 |
| 19 | `lib/features/sync/application/background_sync_coordinator.dart` | `tlsCertError` propagasyonu, Outbox boşken downlink `TLS_PIN_MISMATCH`/`TLS_CERT_ERROR` tespiti | Boş ve dolu Outbox durumunda sertifika hatalarını ayrı raporlamak (`H-2`) | ADR-017 | `tls_error_surface_test` #4, `background_sync_coordinator_test` (32) |
| 20 | `lib/features/sync/sync_providers.dart` | `offline`/`tlsPinMismatch`/`tlsCertError` sonrası `online` geçişte otomatik keşif/yeniden bağlantı desteği | Hata çözüldükten sonra manuel müdahale gerekmeden kurtarma (`H-2`) | ADR-017 | `background_sync_coordinator_test`, `sync_reconnect_lifecycle_test` (7) |
| 21 | `lib/features/shell/presentation/widgets/cashier_header_bar.dart` | `_CompactStatusPill` üzerinde `tlsPinMismatch` ve `tlsCertError` kompakt uyarıları | Kasa üst çubuğunda operatöre net bağlantı/sertifika durumu göstermek (`H-2`) | ADR-017 | `tls_error_surface_test`, `main_shell_screen_test` (4) |
| 22 | `lib/features/security/domain/pairing_qr_payload.dart` | `ca_fingerprint`/`caFingerprint` desteği ve `'UNKNOWN'`/boş değerin `null` olarak temizlenmesi | Hub QR JSON çıktısı ile istemci ayrıştırıcısı arasındaki anahtar uyumunu sağlamak | ADR-018 | `pairing_qr_payload_test` (2/2) |
| 23 | `lib/features/backup/application/client_backup_service.dart` | `pruneExpiredBackups`, `exportLatestBackupTo`, `importBackupFile`, `deleteBackup` metotları `_operationLock` altına alındı | Yedek/restore ile dosya yönetimi arasındaki yarış koşullarını önlemek (`H-4`) | ADR-016 | `client_backup_operation_lock_test` (5/5) |

### B.2 Test Dosyaları (12 Dosya)

| # | Dosya Yolu | Kapsam / Eklenen Doğrulama | İlgili ADR | Güncel Sonuç |
|---|---|---|---|---|
| 1 | `packages/mms_client_storage/test/backup_operation_lock_test.dart` | Heartbeat ömür uzatma, gerçek `SIGKILL` çökme süreci, 6-isolate TOCTOU yarışı, sahip doğrulamalı `.recovering` mutex, 0-bayt hızlı kurtarma, eski sahip/v1 uyumu | ADR-016 | **14 / 14 geçti** |
| 2 | `packages/mms_client_storage/test/tls_pin_mismatch_sync_test.dart` | `TLS_PIN_MISMATCH` vs `TLS_CERT_ERROR`, HTTP fallback olmaması, `maxBackoff` `RETRY` ve `client_seq` korunumu, boş Outbox downlink hatası | ADR-017 | **5 / 5 geçti** |
| 3 | `test_spikes/spike_01_backend/test/hub_discovery_responder_test.dart` | UDP `8946` discovery yanıtında `protocol_version: "1.0"` ve `tls`/`ca_sha256` yokluğu regresyon kilidi | ADR-018 | **7 / 7 geçti** |
| 4 | `test_spikes/spike_01_backend/test/hub_scheduled_backup_test.dart` | Hub `admin/backup`, `admin/restore`, `admin/backup/prune` için `409 ERR_BACKUP_OPERATION_BUSY`; bozuk JSON'da `400 ERR_INVALID_JSON` (#10) | ADR-015, ADR-016 | **10 / 10 geçti** |
| 5 | `test_spikes/spike_01_backend/test/rel01_hub_config_test.dart` | Bilinmeyen `tls` anahtarları reddi, `--config` ile `ROOT_CA_CERT_FILE` fallback yasağı, fail-closed `503` pairing, `startHubFromArgs` ile `ADMIN_SECRET` env sızıntı reddi ve `backup_dir` varsayılanı | ADR-015 | **17 / 17 geçti** |
| 6 | `test/core/network/api_client_test.dart` | `checkHealth` `TLS_CERT_ERROR` ayrımı (#10) ve ham `HandshakeException` fail-closed koruması (#11) | ADR-017 | **15 / 15 geçti** |
| 7 | `test/core/security/secure_storage_fail_closed_test.dart` | `AndroidKeystoreTokenStore` `PlatformException`/`MissingPluginException` fail-closed `SecureStorageException` ve `BackupScheduleController`/`DeviceAuthNotifier` koruması | ADR-020 | **5 / 5 geçti** |
| 8 | `test/core/security/tls_error_surface_test.dart` *(yeni)* | `UserFriendlyErrorMapper`, `StatusBadge`, `SystemStatusNotifier` ve `BackgroundSyncCoordinator` için `TLS_PIN_MISMATCH`/`TLS_CERT_ERROR` uçtan uca yüzey doğrulaması | ADR-017 | **4 / 4 geçti** |
| 9 | `test/core/security/tls_pinned_client_factory_test.dart` | Gerçek soket: CA-bundle sızma engeli, aynı CA yenileme, yabancı CA, yabancı CA+expired önceliği, CA öz-sunumu, IP SAN, Hostname SAN, expired, notYetValid, MITM, 6 paralel istek yarışı + gerçek `MmsApiClient` | ADR-017 | **5 / 5 geçti** |
| 10 | `test/features/backup/client_backup_operation_lock_test.dart` | Eşzamanlı backup/restore/prune/export/import/delete `ERR_BACKUP_OPERATION_BUSY` ve Outbox/`client_seq` korunması | ADR-016 | **5 / 5 geçti** |
| 11 | `test/features/security/pairing_qr_payload_test.dart` | `ca_fingerprint` normalizasyonu ve `UNKNOWN` -> `null` testi | ADR-018 | **2 / 2 geçti** |
| 12 | `test/features/sync/discovery_tls_scheme_test.dart` | Eşleştirilmiş cihaz keşfinde yalnızca `https://` üretimi, HTTPS hatasında `http://` fallback olmaması | ADR-018 | **5 / 5 geçti** |

### B.3 Dokümantasyon Dosyaları (15 Dosya)

- `docs/decisions/README.md`, `015-rel01-single-hub-config.md`, `016-backup-reliability-restore-outbox-scheduled-usb-drive.md`, `017-snapshot-endpoint-and-tls-pin-classification.md`, `018-discovery-tls-scheme.md`, `019-category-vat-sync.md`, `020-android-background-backup-workmanager.md`: Owner onay/erteleme durumları, teknik ayrıntılar, `P-BLOCK-1..3`, %20 KDV kısıt/risk/gereksinim listeleri ve güncel test sayıları işlendi.
- `docs/operations/BACKUP_AND_RESTORE_GUIDE.md`: §2.5 (Android ön-plan sınırı), §2.6 (60 sn/10 sn heartbeat kilit ve tam kapsam), §6 (kilit hata kodları) ve §7 (özel parola ile alınmış koruyucu kopya uyarısı) düzeltildi.
- `OWNER_ACTION_CHECKLIST.md`: `minSdk 24 (Android 7.0)` düzeltmesi, 7 geçici %20 KDV kısıtı, `P-BLOCK-1..3`, Drive opsiyonelliği, B2 OpenSSL `CA:TRUE` + `keyCertSign,cRLSign` yönergesi güncellendi.
- `PHYSICAL_ACCEPTANCE_TEST_PLAN.md`: Tüm `PAT-01…15` maddeleri `BLOCKED` olarak korundu, test sırası (`PAT-12` adım 1 vs adım 2–5 bağımlılığı), `PAT-03` manuel kopyala-yapıştır + `P-BLOCK-1..3` notu, `PAT-05` %20 KDV sınırı, `PAT-13` başlangıçta opsiyonel, `PAT-15` ön-plan sınırı işlendi.
- `docs/PRODUCTION_DEPLOYMENT_RUNBOOK.md`, `docs/LIVE_PROJECT_STATUS.md`, `docs/MASTER_ROADMAP.md`, `docs/FINAL_COMPLETION_REPORT.md`: ADR-015…020 özetleri, `730` güncel test sonucu ve bu rapora referanslar uzlaştırıldı (mevcut faz isimleri korunarak).
- `docs/PILOT_TECHNICAL_REMEDIATION_REPORT.md` *(yeni)*: Bu kanonik bütünleşik rapor oluşturuldu.

---

## C. ADR Durum Tablosu

| ADR | Konu | Owner Kararı | Kod Uygulama Durumu | Otomatik Test Durumu | Kalan Teknik / Operasyonel Risk | Fiziksel Doğrulama Gereksinimi |
|---|---|---|---|---|---|---|
| **ADR-015** | Windows Hub tek yapılandırma (`hub_config.json`), env fallback temizliği, `/devices/revoke` | **CONFIRMED** | Tamamlandı (Ek A + Ek B; `hub_config.dart`, `server.dart`) | **Geçti:** `rel01_hub_config_test` (17), `s1_api_hardening_test` (14), `s2_token_security_test` (20) (`startHubFromArgs` ile test edildi; `dart test` içinde child `dart run` Windows `.dart_tool/lib/sqlite3.dll` dosya kilidi nedeniyle kullanılmadı) | Gerçek Windows `LocalService` ACL ve `Public`/`Private` firewall profilinde çalışma henüz çalıştırılmadı | `PAT-08` (PS 5.1 SCM kurulum/rollback), `PAT-09`, `PAT-10` (ACL + firewall) — **BLOCKED** |
| **ADR-016** | Backup/restore, Outbox/`client_seq` korunması, `BackupOperationLock` sertleştirmesi, Guide §7 | **CONFIRMED** | Tamamlandı (Ek A + Ek B; lock + Hub + istemci + Guide §7) | **Geçti:** `backup_operation_lock_test` (14), `client_backup_operation_lock_test` (5), `restore_outbox_preservation_test` (5), `hub_scheduled_backup_test` (10), `scheduled_backup_runner_test` (14) | Düşük donanımlı Android cihazda 3x PBKDF2 süresi ve gerçek USB aygıt çıkarma davranışı ölçülmedi | `PAT-07` (USB), `PAT-14` (restore çökmesi), `PAT-15` — **BLOCKED** |
| **ADR-017** | Snapshot loopback+admin ve TLS CA/SAN/pin/MITM sınıflandırması | **PARTIALLY_CONFIRMED / IN_REVIEW** (Snapshot **CONFIRMED**) | Tamamlandı (`tls_pinned_client_factory.dart`, `api_client.dart`, sync + UI yüzeyleri; `H-1` & `H-2` giderildi) | **Geçti:** `tls_pinned_client_factory_test` (5), `api_client_test` (15), `tls_error_surface_test` (4), `tls_pin_mismatch_sync_test` (5), `background_sync_coordinator_test` (32) | Üretim OpenSSL CA/server sertifikaları ve gerçek Android BoringSSL ağ rotasyonu henüz test edilmedi | `PAT-12` (CA zinciri, rotasyon, yabancı CA reddi) — **BLOCKED** |
| **ADR-018** | Discovery TLS (`https://`, UDP Seçenek C), QR/JSON ayrıştırma ve `P-BLOCK-1..3` | **CONFIRMED** (§2.1 & §2.2 Seçenek C) | §2.1 & Seçenek C + `PairingQrPayload` uygulandı; **eşleştirme protokolü (`P-BLOCK-1..3`) kural gereği değiştirilmedi** | **Geçti:** `discovery_tls_scheme_test` (5), `pairing_qr_payload_test` (2), `hub_discovery_responder_test` (7) | **`P-BLOCK-1..3` çözülmeden gerçek LAN'da ilk QR+TLS eşleştirmesi tamamlanamaz**; QR görsel paketi yok | `PAT-03` (Wi-Fi keşfi + eşleştirme + `P-BLOCK-1..3` Owner kararı sonrası) — **BLOCKED** |
| **ADR-019** | Kategori/KDV senkronizasyonu (`SYNC-CAT`) | **DEFERRED_POST_PILOT** | **Kod/şema/protokol değiştirilmedi** (`v3` korundu; 7 kısıt / 8 risk / 9 gereksinim belgelendi) | Mevcut regresyon süitleri (0 değişiklik) | Çoklu KDV oranlı mağazada yeni cihaz %20 varsayılanıyla başlar; mali KDV dökümü tutarsız olabilir | Operasyonel %20 KDV kuralıyla sınırlı (`PAT-05`); kalıcı çözüm pilot sonrası Owner kararı bekler |
| **ADR-020** | Android kapalıyken WorkManager yedekleme + Keystore hata eşleme | **DEFERRED_POST_PILOT** | WorkManager/`MainActivity.kt`/`pubspec.yaml` **değiştirilmedi**; Keystore hata eşleme + `minSdk 24` uygulandı | **Geçti:** `secure_storage_fail_closed_test` (5) (platform kanalı sahte testle doğrulandı) | Android uygulama günlerce kapalı kalırsa yedek alınmaz (açılışta gecikmiş yedek başlar) | `PAT-11` (Android Keystore kalıcılığı), `PAT-15` (ön-plan zamanlı yedek) — **BLOCKED** |

---

## D. Test Sonuçları

### D.1 Paket Bazlı Sıralı Test Sonuçları (Son Kod Düzenlemeleri Sonrası)

Tüm otomatik test ve analiz komutları CPU çekişmesini önlemek amacıyla **tamamen sıralı (`-j 1`)** çalıştırıldı:

| Test Süiti | Komut | Önceki Bildirilen (`FINAL_COMPLETION_REPORT`) | Güncel Geçen | Başarısız | Atlanan | Net Artış | Kaynak |
|---|---|---:|---:|---:|---:|---:|---|
| **Contracts** (`packages/mms_contracts`) | `dart test` | 7 | **7** | 0 | 0 | +0 | `task-758` |
| **Client Storage** (`packages/mms_client_storage`) | `flutter test -j 1` | 206 | **215** | 0 | 0 | +9 | `task-758` |
| **Hub Backend** (`test_spikes/spike_01_backend`) | `dart test -j 1` | 226 | **232** | 0 | 0 | +6 | `task-758` |
| **Ana Uygulama** (`market_pos`) | `flutter test -j 1` | 261 | **276** | 0 | 0 | +15 | `task-800` |
| **Toplam** | **Sıralı 4 Süit** | **700** | **730** | **0** | **0** | **+30** | — |

### D.2 Statik Analiz Sonuçları

| Paket | Komut | Çıkış Kodu | Raporlanan Çıktı | Açıklama |
|---|---|---:|---|---|
| **Ana Uygulama** | `flutter analyze` | `0` | `No issues found!` (`task-800`) | Yeni/mevcut 0 uyarı, 0 hata |
| **Contracts** | `dart analyze` | `0` | `No issues found!` (`task-758`) | 0 uyarı, 0 hata |
| **Client Storage** | `dart analyze` | `0` | `16 issues found.` (`task-758`) | Tamamı önceden var olan `sqlite3` `dispose` `deprecated_member_use` `info` kayıtları (test dosyaları); 0 yeni uyarı/hata |
| **Hub Backend** | `dart analyze` | `0` | `18 issues found.` (`task-758`) | Tamamı önceden var olan `sqlite3` `dispose` `deprecated_member_use` `info` kayıtları (test dosyaları); 0 yeni uyarı/hata |

### D.3 TDD RED → GREEN Uygulama Özeti (Dürüst Beyan)

- **RED → GREEN uygulanan ve gözlenenler:**
  - `tls_error_surface_test.dart`, `api_client_test.dart` (#10–11), `tls_pin_mismatch_sync_test.dart`, `backup_operation_lock_test.dart` (#13–14 ve 0-bayt/`.recovering` testleri), `tls_pinned_client_factory_test.dart`, `rel01_hub_config_test.dart` (`ADMIN_SECRET` / `ROOT_CA_CERT_FILE` / `tls` anahtar testleri), `secure_storage_fail_closed_test.dart`, `pairing_qr_payload_test.dart`, `discovery_tls_scheme_test.dart` testleri önce beklenen davranışı doğrulayacak şekilde yazılıp/güncellenip düzeltmeler sonrası geçer hale getirildi.
  - İlk çalıştırmada yakalanan gerçek hatalar (`server.dart` `/backup/snapshot` kilidi nedeniyle `s1_api_hardening_test` #4 `409` hatası; `rel01_hub_config_test.dart` Windows `.dart_tool/lib/sqlite3.dll` dosya kilidi; `tls_error_surface_test.dart` Drift `Column` isim çakışması; `tls_pinned_client_factory.dart:299` `prefer_initializing_formals` lint bilgisi) kök nedenleriyle düzeltilip yeniden doğrulandı.
- **Doğrudan RED adımı uygulanamayan / salt doküman veya mevcut davranış doğrulamaları:**
  - `ADR-018` §2.1 & Seçenek C ve `ADR-019` kod değişikliği içermediği için mevcut davranış üzerine regresyon testi (`hub_discovery_responder_test`, `discovery_tls_scheme_test`) ve dokümantasyon güncellemeleri olarak doğrulandı.
  - Android `MethodChannel` ve gerçek `Windows` DPAPI hatalarının bir kısmı sahte kanal/`Future.error` simülasyonuyla test edildi (gerçek cihaz Keystore donanım modülü test edilmedi).

### D.4 Fiziksel Olarak Çalıştırılamayan Testler (`BLOCKED`)

- **`integration_test/` (2 dosya):** `android_full_e2e_verification_test.dart` ve `android_sqlite_verification_test.dart` gerçek Android/Windows cihaz ortamı gerektirdiği için çalıştırılmadı (**BLOCKED**).
- **Fiziksel Kabul Test Planı (`PAT-01…PAT-15`):** Tamamı **BLOCKED** durumdadır (`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`); hiçbiri yürütülmemiştir.

---

## E. Güvenlik Değerlendirmesi

1. **TLS ve Sertifika Pin Sınıflandırması (`H-1`, `H-2` Giderildi):**
   - **CA-bundle sızması engellendi:** `tls_pinned_client_factory.dart` içinde yalnızca `expectedSha256Hex` özetine eşit olan CA sertifikası `SecurityContext(withTrustedRoots: false)` içine yazılır; aynı PEM içindeki ilgisiz CA'lar güven köküne eklenmez.
   - **CA vs Leaf Pin Ayrımı:** CA PEM pin eşleşmesinde `badCertificateCallback` daima `false` döner; aynı CA ile yenilenmiş geçerli sertifikalar BoringSSL tarafından doğrudan onaylanır.
   - **7 Durum Ayrımı:** Farklı CA / güven zinciri hatası / olası MITM / CA öz-sunumu (`KEY_USAGE_BIT_INCORRECT`) ve yabancı CA+expired durumları `TlsPinMismatchException` (`TLS_PIN_MISMATCH`) olurken; güvenilen CA altındaki IP SAN, Hostname SAN, süre dolumu ve henüz geçerli olmama durumları `TlsCertificateValidationException` (`TLS_CERT_ERROR`) olarak ayrışır. Her iki durumda da `http://` fallback yapılmaz, `RETRY` ve `client_seq` korunur.
   - **Paralel İstek ve Ham İstisna Koruması:** `_PinRejectionLog` bounded FIFO kuyruk ve `_inFlight` sayacı kullanır; `MmsApiClient.checkHealth`/`get`/`post` ham `HandshakeException` sızdırmaz ve sensitive verileri loglamaz.
2. **Pairing ve Protokol Bloklayıcıları (`P-BLOCK-1..3`):**
   - `hub_pairing_admin_client` ve `PairingQrPayload` `ca_fingerprint` çözümlemesi uyumludur; ancak mevcut eşleştirme tel protokolü kural gereği korunmuş olduğu için **`P-BLOCK-1`** (PEM vs DER SHA-256 uyuşmazlığı), **`P-BLOCK-2`** (`/pairing/ca-cert` ilk indirmede leaf-pin reddi + istemci yenilenmemesi) ve **`P-BLOCK-3`** (`hub_url` loopback üretimi) açık Owner bloklayıcılarıdır.
3. **Backup / Restore ve `BackupOperationLock` (`H-4` Giderildi):**
   - Yedek/restore/prune/export/import/delete işlemleri ortak kilit altında çalışır (`409` / `ERR_BACKUP_OPERATION_BUSY`); `VACUUM INTO` salt-okunur `/api/v1/backup/snapshot` ise `writeQueue` ile sıralanıp benzersiz nonce adı üretir ve restore `admissionGate` kapanınca engellenir.
   - Lock `10 sn` heartbeat + `60 sn` stale + `5 sn` 0-bayt hızlı kurtarma + sahip token doğrulamalı `.recovering` mutex + `lostOwnership` kontrolü ile sertleştirilmiştir. Restore'da bekleyen Outbox işlemleri ve `client_seq` korunur; koruyucu kopya restore parolasıyla `.mmsbak` olarak şifrelenir (kılavuz §7 özel parola istisnasıyla güncellendi).
4. **Secret Yönetimi ve Yapılandırma (`H-3`, `M-1`, `M-2`, ADR-020):**
   - Hub `--config=` modunda ortam değişkeni `ADMIN_SECRET` ve `ROOT_CA_CERT_FILE` tamamen devre dışıdır; `POST /api/v1/devices/revoke` artık loopback + admin secret zorunluluğundadır; `/api/v1/admin/restore` bozuk JSON'da `400` döner.
   - `AndroidKeystoreTokenStore` artık `MissingPluginException` / `PlatformException` durumlarında fail-closed `SecureStorageException` üretir ve sır sızdırmaz.
   - **Açık Düşük Öncelikli Teknik Borç (`L-3`):** `WindowsDpapiTokenStore.readSecret` (`lib/core/security/windows_dpapi_token_store.dart:251-261`) tekil anahtar DPAPI çözümleme hatasında `SecureStorageException` fırlatmak yerine `null` döndürmektedir (`_readAllEncrypted` toplu dosya hatasında fail-closed çalışmaya devam etmektedir). Pilot kapsamını değiştirmemek için bu aşamada dokunulmamış, teknik borç olarak kayıt altına alınmıştır.
5. **Bağımsız Reviewer Bulgu Özeti (`H-1..H-5`, `M-1..M-3`, `L-1..L-3`):**
   - `H-1` (TLS paralellik/`HandshakeException`), `H-2` (`TLS_CERT_ERROR` UI/sync propagation + `UserFriendlyErrorMapper`), `H-3` (`/devices/revoke` loopback + `--config` `ADMIN_SECRET` env), `H-4` (`BackupOperationLock` TOCTOU/heartbeat/0-bayt/`.recovering` + Hub/istemci kilit kapsamı), `H-5` (eksik rapor + doc çelişkileri), `M-1` (`backup_dir` default), `M-2` (`/admin/restore` JSON `400` + `caCertPath` TOCTOU), `M-3` (eksik test kapsamları) ve `L-1` (ADR durum/test sayıları), `L-2` (B2 OpenSSL CA uzantı talimatı) **tamamen giderildi ve yeniden test edildi**. Yalnızca `L-3` açık teknik borç olarak bırakıldı.
6. **Git Güvenliği:** Staging alanı boş, commit/push/reset/checkout yapılmadı, takip edilen gerçek DB / secret / private key / keystore dosyası bulunmadı.

---

## F. Pilot İçin Hazır Olanlar vs Fiziksel Test Bekleyenler

| Bileşen / Özellik | Yazılım Durumu | Fiziksel Doğrulama Durumu |
|---|---|---|
| Windows Hub tek `hub_config.json` + fail-closed TLS/CA/admin/revoke sertleştirmesi | **Tamamlandı & Otomatik Testli** (`rel01_hub_config_test`, `s1..s4`) | **BLOCKED** — Gerçek SCM (`PAT-08`), crash (`PAT-09`), ACL/Firewall (`PAT-10`) bekleniyor |
| Şifreli `.mmsbak` yedek, iki aşamalı restore, Outbox/`client_seq` korunması, `BackupOperationLock` | **Tamamlandı & Otomatik Testli** (`backup_operation_lock_test`, `restore_outbox_preservation_test`) | **BLOCKED** — Gerçek USB (`PAT-07`), restore crash (`PAT-14`), düşük donanımlı Android PBKDF2 süresi bekleniyor |
| TLS CA-pin / leaf-pin / IP-SAN / Hostname-SAN / tarih / MITM sınıflandırması ve UI yüzeyleri | **Tamamlandı & Otomatik Testli** (`tls_pinned_client_factory_test`, `tls_error_surface_test`) | **BLOCKED** — Gerçek OpenSSL sertifika + Android BoringSSL rotasyonu (`PAT-12`) bekleniyor |
| Eşleştirilmiş cihazda `https://` discovery (HTTP downgrade yok), UDP `"1.0"` | **Tamamlandı & Otomatik Testli** (`discovery_tls_scheme_test`, `hub_discovery_responder_test`) | **BLOCKED** — **`P-BLOCK-1..3` Owner kararı** + gerçek LAN QR/manuel eşleştirme (`PAT-03`) bekleniyor |
| Android release sertleştirme (`allowBackup=false`, cleartext=false, Keystore fail-closed, `minSdk 24`) | **Tamamlandı & Otomatik Testli** (`android_release_hardening_test`, `secure_storage_fail_closed_test`) | **BLOCKED** — B1 imza anahtarı + Release APK kurulumu (`PAT-11`) bekleniyor |
| POS satış/iade, barkod, stok girişi, FIFO Outbox, %20 KDV operasyonel model | **Mevcut Kod & Regresyon Testli** | **BLOCKED** — Gerçek kamera/HID/LAN/eşzamanlı satış testleri (`PAT-01`, `PAT-02`, `PAT-04..06`) bekleniyor |
| Google Drive şifreli yükleme / Android açıkken zamanlanmış yedek | **Yazılım Hazır (Mock/Otomatik Testli)** | **BLOCKED** — Başlangıç pilotu için opsiyonel (`PAT-13` Drive, `PAT-15` ön-plan yedek) |

---

## G. Pilot Bloklayıcıları

| Kod / Alan | Bloklayıcı Tanımı | Etki / Engel | Sorumlu |
|---|---|---|---|
| **P-BLOCK-1..3** | (1) `server.dart` ham CA PEM SHA-256 vs istemci DER SHA-256; (2) `DevicePairingClient` ilk `/pairing/ca-cert` isteğinde leaf-pin reddi + istemci yenilenmemesi; (3) Windows yerel oturumda `hub_url` loopback üretimi | Gerçek Android–Hub ilk QR+TLS eşleştirmesi (`PAT-03`) uçtan uca tamamlanamaz | **Owner Kararı + Ayrı Teknik Uygulama** |
| **B1 — Android Signing Key** | `android/key.properties` ve üretim `.jks` imza anahtarı depoda yoktur (bilinçli fail-closed) | Release APK üretilemez (`PAT-11` bloklu) | **Owner** (`OWNER_ACTION_CHECKLIST.md` §B1) |
| **B2 — Hub TLS Sertifikaları** | Üretim `ca.crt`, `server.crt` (SAN = Hub LAN IP + hostname) ve `server.key` (`CA:TRUE`, `keyCertSign,cRLSign`, `ca.crt` üzerinde SAN yok) henüz sağlanmadı | Üretim Hub TLS açık başlamaz (`PAT-03`, `PAT-08`, `PAT-12` bloklu) | **Owner** (`OWNER_ACTION_CHECKLIST.md` §B2) |
| **TLS Pin / SAN Gerçek Doğrulama** | Gerçek OpenSSL sertifikaları ve Android release APK üzerinde IP SAN / sertifika yenileme (`PAT-12`) hiç çalıştırılmadı | SAHA / LAN TLS güvenliği kanıtlanmadı | **Fiziksel Test (`PAT-12`)** |
| **Windows SCM, ACL ve Firewall** | `install_mms_service.ps1` (`LocalService`), `setup_service_acls.ps1`, `configure_hub_firewall.ps1` yönetici Windows ortamında çalıştırılmadı | Servis otomatik başlama, rollback ve standart kullanıcı ACL izolasyonu doğrulanmadı (`PAT-08..10`) | **Fiziksel Test (`PAT-08..10`)** |
| **Android Release APK & Keystore** | Gerçek telefonda APK kurulumu, yeniden başlatma sonrası token kalıcılığı, kamera izni (`PAT-01`, `PAT-11`) test edilmedi | Mobil cihaz saha davranışı kanıtlanmadı | **Fiziksel Test (`PAT-01`, `PAT-11`)** |
| **Pairing / Discovery Saha Testi** | Gerçek LAN/Wi-Fi altında UDP `8946` broadcast, sanal adaptör eleme ve DHCP IP değişimi test edilmedi | Router AP izolasyonu / firewall / yeniden keşif doğrulanmadı (`PAT-03`) | **Fiziksel Test (`PAT-03`)** |
| **Pilot Donanımı & Temizlik (`D1..D4`, `E1`)** | Pilot Windows PC, USB HID okuyucu, Android cihazlar ve `MarketMmsSpike01` + test token/DB temizliği tamamlanmadı | Tüm fiziksel kabul testleri (`PAT-01…15`) yürütülemiyor | **Owner** (`OWNER_ACTION_CHECKLIST.md` §D, §E) |

---

## H. Sonraki İşler

1. **Pilot öncesi zorunlu işler:**
   - Owner tarafından `P-BLOCK-1..3` protokol düzeltmesi için açık uygulama onayı verilmesi (PEM vs DER SHA-256 uyumu, `/pairing/ca-cert` TOFU yenilemesi, LAN `hub_url` stratejisi) ve bu düzeltmenin uygulanıp test edilmesi.
   - `OWNER_ACTION_CHECKLIST.md` §B1 (Android signing key), §B2 (OpenSSL CA + SAN'lı sunucu sertifikası), §D1–D4 (`MarketMmsSpike01` kaldırma, test token rotasyonu, şifresiz test DB/eski koruyucu kopya temizliği) adımlarının tamamlanması.
   - `PHYSICAL_ACCEPTANCE_TEST_PLAN.md` sırasıyla fiziksel kabul testlerinin yürütülmesi: `PAT-12 (adım 1)` → `PAT-08` → `PAT-10` → `PAT-11` → `PAT-03` → `PAT-12 (adım 2–5)` → kalan `PAT` testleri (`PAT-01`, `02`, `04..07`, `09`, `14`, `15`).
2. **Pilot sırasında yapılacaklar (Operasyonel Sınırlar):**
   - `ADR-019` kapsamındaki **7 geçici %20 KDV operasyonel kısıtının** uygulanması (tüm ürünler %20 KDV, ürün/kategori yönetimi tek Windows Owner cihazından, Android'de KDV alanı finansal doğruluk kaynağı sayılmaz, çoklu KDV ürünü eklenmez, KDV dökümleri resmî mali beyana esas alınmaz).
   - `ADR-020` sınırı gereği Android tablet/telefonların günlük kapanışta veya günde en az bir kez ön-planda açık tutulması (otomatik zamanlanmış yedek yalnızca uygulama açıkken çalışır); Windows Hub günlük şifreli yedeğinin + haftalık USB dışa aktarımının izlenmesi.
3. **Pilot sonrası `ADR-019` kalıcı çözümü:**
   - Belgelenen **8 teknik riskin** giderilmesi ve **9 kalıcı tasarım gereksiniminin** (Hub v3→v4 migrasyonu ve rollback uyumu, Hub/Owner rol yetkisi, `PRODUCT_UPSERT`/`CATEGORY_UPSERT` ve sıralı snapshot, FK/bilinmeyen kategori koruması, geriye uyumlu `NULL` KDV başlatma, `CHECK (0..100)` + soft delete, `version`/stale çakışma yönetimi, migrasyon öncesi şifreli `.mmsbak` yedek + `PAT-05` doğrulaması) ayrı bir tasarım ve TDD oturumunda uygulanması.
4. **Pilot sonrası `ADR-020` WorkManager:**
   - Owner onayı ile `workmanager` bağımlılığının değerlendirilmesi, Keystore `MethodChannel` kodunun `MainActivity.kt`'den bağımsız `FlutterPlugin` sınıfına taşınması ve uygulama kapalıyken arka plan yedekleme + `PAT-15` adım 4 doğrulaması.
5. **Google Drive OAuth (`C1`, `C2`, `PAT-13`):**
   - İlk pilot Windows Hub yerel şifreli yedek + USB aktarımıyla başlatılabilir; Google Cloud projesi (`drive.file` kapsamı, OAuth Desktop Client ID, Android istenirse Google Sign-In kararı) uygun aşamada eklenip `PAT-13` ile doğrulanır.
6. **Güvenlik cleanup:**
   - Açık düşük öncelikli teknik borç **`L-3`** (`WindowsDpapiTokenStore.readSecret` tekil anahtar DPAPI hatasında `null` yerine `SecureStorageException` ayrımı) için uygun bakım turunda düzenleme; `D1..D4` test kalıntılarının üretim ortamına sızmadığının teyidi.
7. **Faz kabulü:**
   - `AGENTS.md` §15 uyarınca hiçbir yapay zekâ asistanı faz kabulü ilan edemez; tüm otomatik doğrulamalar, kod düzeltmeleri ve fiziksel `PAT` kanıtları Owner tarafından incelendikten sonra faz kabulleri ve Git commit/push kararı yalnızca Owner tarafından verilir.

---

## I. Git ve Veri Güvenliği

Son salt-okunur git ve güvenlik hijyeni denetimiyle aşağıdakiler doğrulanmıştır:
- **Commit / Push yapılmadı:** `origin/main` üzerindeki son ortak commit `8454933` değişmemiştir.
- **Stage yapılmadı:** `git diff --cached --name-only` tamamen boştur.
- **Satır sonu / çakışma kontrolü:** `git diff --check` çıktısında bu oturumda değiştirilen tüm dosyalar temizdir (merge çakışma işareti yok); yalnızca önceden çalışma ağacında bulunan ve bu oturumda dokunulmayan `docs/ROADMAP.md` (satır 47, 60, 74, 99) üzerinde satır sonu boşluğu (`trailing whitespace`) uyarısı raporlanmıştır.
- **Gerçek veriler ve test ortamı korundu:** Hiçbir SQLite veritabanı silinmedi veya sıfırlanmadı, destructive migration çalıştırılmadı, Outbox kayıtları silinmedi, cihaz kimlikleri/test token'ları/secret/`pepper.dpapi` dosyaları değiştirilmedi, `MarketMmsSpike01` servisine dokunulmadı, plaintext test DB'ler ve eski safety snapshot dosyaları silinmedi.
- **Hassas dosya takip taraması (`git ls-files`):** Depo tarafından takip edilen `manual_test_env/`, `.db`, `.db-wal`, `.db-shm`, `.key`, `.pem`, `.p12`, `.jks`, `.keystore`, `pepper.dpapi`, `key.properties` veya `.env` dosyası **yoktur** (`manual_test_env/` `.gitignore` kapsamındadır).

---

## J. Nihai Karar

- **Yazılım düzeltmeleri (onaylı ADR-015…020 kapsamı):** **Tamamlandı** (`730/730` otomatik test geçti, 0 başarısız, 0 atlanan; statik analiz 0 hata/uyarı; bağımsız Reviewer `H-1..H-5`, `M-1..M-3`, `L-1..L-2` bulguları kapatıldı, `L-3` düşük öncelikli açık teknik borç olarak belgelendi).
- **Teknik bloklayıcı durumu:** **Mevcut — `P-BLOCK-1..3`** (ADR-018 eşleştirme QR/DER/`hub_url` protokol uyuşmazlıkları mevcut protokole dokunulmazlık gereği çözülmedi, Owner uygulama kararı bekliyor) ve **`L-3`** (düşük öncelikli DPAPI hata yayılımı).
- **Fiziksel pilot / üretim durumu:** **Fiziksel pilot testlerine (`PAT-01…15`) ve üretime HAZIR DEĞİLDİR (`BLOCKED`); fiziksel pilot testleri için Owner kararları (`P-BLOCK-1..3`) ve Owner hazırlıkları (`B1`, `B2`, `D1..D4`, `E1`) bekleniyor.**

**Durum Etiketi:** `KULLANICI KARARI BEKLİYOR`
