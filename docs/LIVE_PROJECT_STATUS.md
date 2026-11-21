# LIVE_PROJECT_STATUS.md — MARKET MMS Canlı Proje Durumu (Güncel: 22 Kasım 2026)

> [!IMPORTANT]
> **22 Kasım 2026 — Faz 1.1 Sonrası Tamamlama Paketi (Aşama 1 → 3 → 4 → 2):** Commit `a118434` üzerine Owner onayıyla **1 → 3 → 4 → 2** sırasıyla 4 aşamalı tamamlama çalışması çalışma ağacına (unstaged) uygulanmıştır (`schemaVersion = 3` korunmuştur; `ADR-022` Android `google_sign_in` Phase 2 kapsamındadır):
> 1. **Aşama 1 (`WP-1` Saha Sertleştirmesi):** `BackgroundSyncCoordinator` (`onHubNetworkUnreachable`) ↔ `HubConnectionNotifier` (`reportTransportUnreachable` + `onResume` bağlı durumda keşif/sağlık kontrolü) DHCP/Wi-Fi kopma kurtarma köprüsü (TLS/Auth güvenlik durdurmalarında tetiklenmez); `PaymentDialog` (`showKeyboardHints` ile masaüstü klavye kısayol/odak ayrımı ve `48dp` hazır tutar butonları); `DiagnosticsView` `48dp` `_themeChip`; kalıcı `FileThemePreferenceStore` (`client_theme.json`); `s5a4_backup_restore_test.dart` Test 15 için `90 sn` timeout; `integration_test/android_full_e2e_verification_test.dart` içinde sabit `127.0.0.1` yerine `MMS_E2E_HUB_URL` + `UdpHubDiscoveryClient` dinamik keşfi.
> 2. **Aşama 3 (Dokümantasyon Uzlaştırması):** `OD-03` uzlaştırması ([`BUSINESS_RULES_SPEC.md`](./requirements/BUSINESS_RULES_SPEC.md) **v1.7** — offline yeni ürün oluşturma + `PRODUCT_UPSERT` `CONFIRMED`; satış ekranında ad-hoc kayıtsız ürün satışı yasak), `AGENTS.md` & `README.md` içinde `go_router` (*Planlı / Pilot Sonrası*; Pilot 1.0'da `MainShellScreen` aktif) güncellemesi ve [`PROJECT_STATUS.md`](./PROJECT_STATUS.md) yönlendirme notu.
> 3. **Aşama 4 (`A7` QR Görseli):** `pubspec.yaml` (`qr_flutter: ^4.1.0`) + Windows [`PairingApprovalPanel`](../lib/features/security/presentation/widgets/pairing_approval_panel.dart) içinde canlı kare QR görseli (`Key('pairing_qr_image')`).
> 4. **Aşama 2 (`K-05` Seçenek 1 — Hub TLS-Pinned Dağıtım & Kalıcı Cihaz Kayıt Defteri):** Hub tarafında DPAPI korumalı `LiveDriveSecretManager` (`live_drive_sync_secret.dpapi`), `strictTenantStorePaths` korumalı `GET /api/v1/sync/live-drive-config` (`Cache-Control: no-store`, `ACTIVE`/`REVOKED` cihaz listesi + `live_sync_secret`) ve loopback + admin korumalı `POST /api/v1/admin/live-drive-secret/rotate`; istemci tarafında atomik `FileDriveAuthorizedRegistryStore` (`drive_authorized_devices.json`), `HubLiveDriveConfigClient`, `DriveAuthorizedRegistryNotifier` ve `BackgroundSyncCoordinator.onSyncCompleted` 5 dk throttle'lı provizyon.
> - **Son Tam Doğrulama (4 Paket + Debug Build'ler):** **790/790 otomatik test geçti / 0 başarısız / 0 atlanan** (`mms_contracts` **7/7** · `mms_client_storage` **225/225** · `spike_01_backend` **249/249** · kök `market_pos` **309/309**), 4 pakette `analyze` çıkış kodu `0` (`market_pos` `0` sorun, `mms_contracts` `0` sorun, `mms_client_storage` `16` ve `spike_01_backend` `18` önceden var olan `sqlite3 dispose` info), `flutter build windows --debug` (`build\windows\x64\runner\Debug\market_pos.exe`) ve `flutter build apk --debug` (`build\app\outputs\flutter-apk\app-debug.apk`) çıkış kodu `0`. **Fiziksel kabul testleri (`PAT-01…18`), `B1` Android release imza anahtarı, `B2` Hub TLS üretim sertifikaları, `C1/C2` Google Cloud OAuth kurulumu, `D1–D4` temizlik, `ADR-022` Phase 2 (`google_sign_in`) ve v1.1 RBAC/Raporlama henüz tamamlanmamıştır (`BLOCKED / PENDING`). Stage/commit/push yapılmamıştır.**
>
> **21 Kasım 2026 — Release 1.0 End-to-End Tamamlama Çalışması (Faz A–F):** Owner kararları (`DEC-REV-1..5`, Android kapalıyken arka plan yedekleme, Google Drive şifreli yedekleme/geri yükleme, Hub öncelikli Google Drive canlı senkronizasyon) çalışma ağacına eksiksiz uygulandı ve doğrulandı: (1) **Faz A (`P-BLOCK-1..3`):** UTF-8 bağımsız DER/PEM kanonikalizasyonu + `MmsX509PreValidator`, sıfır-sırlı `ALT-BOOT-2` `GET /api/v1/pairing/ca-cert` bootstrap akışı, crash-safe `POLL_RECEIVED -> ACK_PENDING -> ACK_CONFIRMED -> P1..P4` re-pairing durum makinesi, Windows `GetAdaptersAddresses` + `GetIfEntry2` x64 FFI adaptör ayrımı ve `advertise_host`/SAN çift doğrulaması (`pblock_1_2_client_test`, `pblock_1_3_hub_test`); (2) **Faz B (`ADR-020`):** Saf Android SDK `JobScheduler` (`MmsBackgroundBackupJobService`) + headless `FlutterEngine` (`mmsBackgroundBackupEntrypoint`), ortak Android Keystore kanalı (`MmsSecureStorageChannelHandler`), `BackgroundBackupWorkerExecutor` ve `BackupScheduleSection` zamanlama/hata/sonraki çalışma UI entegrasyonu; (3) **Faz C (Google Drive Yedek & Geri Yükleme):** Sayfalı `listRemoteBackups`, `.part` Range sürdürmeli `downloadEncryptedBackup` + SHA-256 + `verifyPackageStructure` (bozuk `.part` otomatik silme), `revokeToken` iptali, canlı DB'ye dokunmadan önce parola/HMAC/`integrity_check` doğrulayan `downloadAndRestoreFromGoogleDrive` ve `ExternalBackupSection` geri yükleme UI'ı; (4) **Faz D (`ADR-021` Hibrit Canlı Senkronizasyon):** `MMSENV01` zarf kriptografisi (`MMS-LIVESYNC-ENV-V1` ayrı anahtar + Encrypt-then-MAC), `DriveAuthorizedDeviceRegistry` (`ACTIVE`/`REVOKED`), `DriveLiveSyncLedger`, bitişik `(origin_device_id, client_seq)` sıralama, non-LWW `PRODUCT_UPSERT` çakışma bayrağı, echo-loop + `outbox_operations` koruması, Hub dönüşü `reconcileWithMasterHub`, TLS/Auth hatalarında fail-closed non-fallback ve `DiagnosticsView` 10 UI durumu (`26` senaryo). **Son Doğrulama (son kod düzenlemeleri sonrası):** **772/772 otomatik test geçti / 0 başarısız / 0 atlanan** (`mms_contracts` 7/7 · `mms_client_storage` 225/225 · `spike_01_backend` 245/245 · kök `market_pos` 295/295), 4 pakette `analyze` çıkış kodu `0` (`market_pos` `0` sorun, `mms_contracts` `0` sorun, `mms_client_storage` `16` ve `spike_01_backend` `18` önceden var olan `sqlite3 dispose` info) ve Android `:app:compileDebugKotlin` `BUILD SUCCESSFUL` (çıkış `0`). **Fiziksel kabul testleri (`PAT-01…18`), `integration_test/` cihaz testleri, üretim Android APK imzası (`B1`), Hub TLS üretim sertifikaları (`B2`), Google Cloud OAuth kurulumu (`C1–C2`) ve Windows SCM/ACL kurulumu henüz yürütülmemiştir (`BLOCKED — NOT RUN`). Commit/push yapılmamıştır.** Ayrıntılı teslim raporu: [`RELEASE_1_0_FINAL_DELIVERY_REPORT.md`](./RELEASE_1_0_FINAL_DELIVERY_REPORT.md).
>
> **21 Kasım 2026 — Bütünleşik Teknik Düzeltme, ADR Uyum ve Pilot Hazırlık Oturumu:** ADR-015…020 kapsamındaki Owner kararları kod ve dokümantasyonla uyumlu hale getirildi: (1) ADR-015 (`CONFIRMED`): `--config=` modunda ve eşleştirme/revocation uçlarında env fallback kaldırıldı, `/devices/revoke` loopback korumasına alındı, sıkı `tls` anahtar denetimi ve fail-closed `503 ERR_CA_CERT_UNAVAILABLE` eklendi; (2) ADR-016 (`CONFIRMED`): `BackupOperationLock` heartbeat (10 sn) + 60 sn kurtarma + sahip doğrulamalı `.recovering` mutex + 5 sn 0-bayt kurtarma ile sertleştirildi, Hub/istemci bakım ve saklama temizliği ortak kilide bağlandı, kılavuz §7 referansı düzeltildi; (3) ADR-017 (`PARTIALLY_CONFIRMED / IN_REVIEW`): `MmsPinnedTlsClientFactory` içindeki CA-pin/leaf-pin karışıklığı, CA-bundle sızması ve `_PinRejectionLog` paralellik yarışı giderildi; IP SAN, hostname SAN, süre dolumu/henüz geçersiz, aynı-CA yenileme, yabancı CA, CA öz-sunumu, leaf pin uyuşmazlığı ve MITM durumları `TlsCertificateValidationException` (`TLS_CERT_ERROR`) ve `TlsPinMismatchException` (`TLS_PIN_MISMATCH`) olarak ayrıştırılıp UI/sağlık/sync katmanlarına taşındı; (4) ADR-018 (`CONFIRMED` Seçenek C): UDP discovery korundu, `PairingQrPayload` `ca_fingerprint` ve `UNKNOWN` çözümlemesi düzeltildi, **`P-BLOCK-1..3`** Owner karar bloklayıcıları olarak belgelendi; (5) ADR-019 (`DEFERRED_POST_PILOT`): 7 geçici %20 KDV kısıtı, 8 risk ve 9 kalıcı tasarım gereksinimi belgelendi (kod/şema değişmedi); (6) ADR-020 (`DEFERRED_POST_PILOT`): `AndroidKeystoreTokenStore` fail-closed `SecureStorageException` hata eşlemesi eklendi, `minSdk 24 (Android 7.0)` belgelendi. Sıralı doğrulama: **730 test geçti / 0 başarısız / 0 atlanan** (Uygulama 276 · Client Storage 215 · Contracts 7 · Hub 232); statik analizlerde 0 hata/uyarı (Uygulama 0, Contracts 0, Client Storage 16 önceden var olan `sqlite3 dispose` info, Hub 18 önceden var olan `sqlite3 dispose` info). Ayrıntılar: [`PILOT_TECHNICAL_REMEDIATION_REPORT.md`](./PILOT_TECHNICAL_REMEDIATION_REPORT.md). **Fiziksel kabul testleri (PAT-01…15) henüz yapılmadı (`BLOCKED`); proje üretime hazır değildir ve stage/commit yapılmamıştır.**
>
> **21 Kasım 2026 (3. oturum) — Son Tamamlama, Üretim Hazırlığı ve Saha Kabulü:** Önceki raporun test sayıları bu çalışma ağacında yeniden doğrulandı (243 / 191 / 7 / 219 = 660, 0 başarısız). Raporda olmayan **10 bulgu** düzeltildi: (0) **üretim Hub'ı eşleştirme kök CA yolunu hiç almıyordu → QR `ca_fingerprint: UNKNOWN`, TLS pin kurulamazdı (PAIR-CA; `tls.ca_cert` eklendi, üretimde zorunlu)**; (1) Android otomatik Google yedeği açıktı → şifresiz DB + `device_id` cihaz dışına çıkabiliyordu; (2) restore koruyucu kopyası şifresiz kalıyordu → şifreli `.mmsbak`; (3) restore sırasında zamanlanmış yedek yanıltıcı hata veriyordu → dosya kilidi (BK-LOCK); (4) Drive yükleyicisi dosyanın şifreli olduğunu doğrulamıyordu; (5) keşif adayları her zaman `http://` → üretimde (TLS) otomatik keşif bağlanamıyordu; (6) `setup_service_acls.ps1` ve `uninstall_mms_service.ps1` Windows PowerShell 5.1'de **ayrıştırılamıyordu**; (7) kurulum betiği güncellemede ikilileri servis durmadan kopyalıyordu, geri dönüş yoktu; (8) firewall kuralları tüm uzak adreslere açıktı; (9) güncelleme manifesti HTTP indirme adresi/SHA-256'sız kabul ediliyordu. Ek: Hub `/pairing/reject` bozuk gövdede 500 dönüyordu. Yeni testlerle **700 geçti / 0 başarısız**. ADR-018/019/020 eklendi (PROPOSED). Fiziksel kabul **BLOCKED**; stage/commit yapılmadı. Rapor: [`FINAL_COMPLETION_REPORT.md`](./FINAL_COMPLETION_REPORT.md).
>
> **21 Kasım 2026 (2. oturum) — Nihai Teknik Denetim:** Önceki raporun test sayıları bağımsız olarak yeniden doğrulandı (224 / 146 / 210 / 7). Ek olarak **2 kritik hata** (istemci restore'unda bekleyen Outbox/`client_seq` kaybı — ADR-BAK-03 uygulanmamıştı; kasiyer token'ıyla şifresiz merkezi DB snapshot'ı) ve 4 yüksek/orta bulgu düzeltildi. **Zamanlanmış yedek** (Hub + istemci), **USB aktarımı**, **Google Drive altyapısı** (gerçek OAuth hesabı BLOCKED), **TLS pin uyuşmazlığı durumu** ve **Windows Owner eşleştirme onay/red ekranı** eklendi. Mimari değerlendirme: [`ARCHITECTURE_REVIEW.md`](./ARCHITECTURE_REVIEW.md). Kararlar: ADR-016, ADR-017 (PROPOSED). Güncel tek rapor: [`FINAL_COMPLETION_REPORT.md`](./FINAL_COMPLETION_REPORT.md). Fiziksel cihaz/servis/USB/Drive hesabı testleri **BLOCKED**; hiçbir faz Owner tarafından kabul edilmiş sayılmaz; stage/commit yapılmadı.
>
> **21 Kasım 2026 Güncellemesi — Birleştirilmiş Tamamlama Çalışması:** Faz 2 (stok girişi, sürekli kamera taraması, yeni ürün alış fiyatı), Faz 7A (STOCK_RECEIPT delta senkronizasyonu, stok ezilme düzeltmeleri, 401/403/426 bekletme, downlink hata görünürlüğü, kimlik değişikliği koruması, yedekleme isolate'i), Faz 7B (`adm_sec` fallback ve gömülü cihaz token'ı kaldırıldı, güvenli depo fail-closed, tenant/store başlık zorunluluğu) ve Faz 7C (REL-01 tek yapılandırma kaynağı, Android release imza/cleartext sertleştirmesi) uygulandı ve otomatik testlerle doğrulandı. Google Drive, USB ve tüm fiziksel cihaz/servis testleri **BLOCKED / NOT_STARTED**. Ayrıntılar, test sayıları ve Owner kararları: [`docs/FINAL_COMPLETION_REPORT.md`](./FINAL_COMPLETION_REPORT.md). Aşağıdaki 20 Kasım bölümleri tarihsel kayıttır; Faz 1–7 alt aşamalarının çoğu kodda mevcut olup fiziksel kabul testleri beklemektedir. Hiçbir değişiklik stage/commit edilmemiştir.

*Bu belge 20 Kasım 2026 itibarıyla güncel proje ilerlemesini, doğrulama düzeylerini ve **Faz 1–7 Ana Yol Haritası** durumunu izler.*  
*Tarihsel 15 Kasım 2026 MVP durum kaydı için bkz.: [`docs/PROJECT_STATUS.md`](./PROJECT_STATUS.md)*  
*Bağlayıcı 7 Fazlı Yol Haritası için bkz.: [`docs/MASTER_ROADMAP.md`](./MASTER_ROADMAP.md)*

---

## Özet Durum Panosu *(Tarihsel 20 Kasım 2026 Özeti — Güncel Teknik Durum için En Üstteki 22 Kasım Notu, [`RELEASE_1_0_FINAL_DELIVERY_REPORT.md`](./RELEASE_1_0_FINAL_DELIVERY_REPORT.md) ve [`OWNER_ACTION_CHECKLIST.md`](../OWNER_ACTION_CHECKLIST.md) Esastır)*

- **Tarihsel Ana Faz Kaydı (20 Kasım):** **Faz 1 — Otomatik Hub Keşfi ve Bağlantı Yönetimi** (kodda Release 1.0, Phase 1.1 ve Faz 1–7 çalışmaları eklenmiş olsa da Owner tarafından resmî faz kabulü **verilmemiştir**, `PAT-01…18` **BLOCKED**).
- **Son Tamamlanan Teknik Çalışma:** **22 Kasım 2026 — Faz 1.1 Sonrası Tamamlama Paketi (Aşama 1 `WP-1` → Aşama 3 Doküman Uzlaştırma → Aşama 4 `A7` QR → Aşama 2 `K-05` Hub Live-Drive Config)** *(commit `a118434` üzerinde **790/790 otomatik test**, 4 pakette temiz `analyze`, `flutter build windows --debug` ve `flutter build apk --debug` ile doğrulandı; fiziksel donanım/kabul testi bekleniyor — `TECHNICALLY COMPLETE — PHYSICAL VALIDATION REQUIRED`)*.
- **Git Çalışma Alanı:** `main` dalı (`HEAD = a118434`) üzerinde çalışma ağacı unstaged durumdadır; **stage/commit/push yapılmamıştır**.

---

## 1. Tamamlanan ve Git Geçmişine (`origin/main`) Kabul / Push Edilmiş Çalışmalar

Son ortak `origin/main` commit'i: `8454933df95c6de04813d3eb9499331ec86471dc` (15 Kasım 2026). Aşağıdaki çekirdek MVP temeli kullanıcı kabulüyle depoya kaydedilmiştir:

- **Planlama, Mimari & SPIKE-01 (Tarihsel Faz 0):** İş kuralları (`BUSINESS_RULES_SPEC.md`), mantıksal veri modeli (`DATA_MODEL.md`), offline senkronizasyon ve şifreli yedekleme protokolleri, Dart Shelf + SQLite WAL single-writer backend altyapısı.
- **Windows Client Foundation (Commit `8676586`, Tag `v1.1.0-windows-client-foundation`):** `packages/mms_client_storage`, Drift yerel SQLite ve Windows masaüstü istemci temeli.
- **Yönetişim & UI/UX Programı (Commitler `50343d9`, `6b7898c`, `2db892d`, `32111b8`, `9ad09fc`, `1a3f8e5`):** 5 çekirdek Agent Skill, dokümantasyon uzlaştırması ve 32 HTML/CSS/JS UI/UX prototipi (`OD-01` Half-Up yuvarlama + `12.50 TL`, `OD-02` Parked Carts kapsam dışı, `OD-03` offline bilinmeyen barkod engeli, `OD-04` sanal numpad opsiyonel/kapalı kararları).
- **PaymentMethod Standardizasyonu & Legacy Outbox Recovery (Commit `b069d5b`):** Kanonik `'CASH'`/`'CARD'` ödeme sözleşmesi ve atomik outbox kurtarma akışı.
- **Kasa Satış Ekranı & Sepet Yönetimi (Commit `e9e1df5`):** `PosScreen`, `CartNotifier`, `PaymentDialog`, snapshot fiyat güvencesi (`PriceChangedException`), klavye kısayolları (`F1`, `F2`, `F9`, `F10`, `Esc`).
- **Outbox Status Summary & Diagnostics (Commit `8454933`):** `packages/mms_contracts` ve `OutboxStatusBadge`.

---

## 2. Kullanıcı Tarafından Fiziksel / Manuel Olarak Doğrulanmış İşler

Commit `8454933` sonrasında geliştirilen ve çalışma alanında yer alan işlevlerden aşağıdakiler doğrudan kullanıcı tarafından manuel/fiziksel testlerle doğrulanmıştır:

- [x] **Ürün Senkronizasyonu:** Ürün oluşturma, FIFO Outbox `PRODUCT_UPSERT` ve Hub ürün snapshot indirme akışı manuel kabul testinden geçmiştir.
- [x] **Android Satışının Windows Tarafında Görünmesi:** Android cihazda yapılan satışın Master Hub üzerinden satış uplink → downlink akışıyla Windows istemcisine ulaştığı kullanıcı tarafından doğrulanmıştır.
- [x] **Windows Satış Geçmişinde İade Durumu Görünürlüğü:** Windows Satış Geçmişi ekranında iade edilen satışların `İADE EDİLDİ` rozetiyle gösterilmesi kullanıcı tarafından manuel olarak doğrulanmıştır.

---

## 3. Antigravity Raporuna Göre Tamamlanan — Henüz Bağımsız / Kullanıcı Tarafından Doğrulanmamış İşler

> [!WARNING]
> Bu bölümdeki çalışmalar önceki Antigravity oturumlarının geliştirme, otomatik test ve build raporlarına dayanmaktadır. **Bağımsız doğrulanmış veya kullanıcı tarafından nihai kabulü verilmiş sayılmazlar**; ayrıca çalışma ağacında unstaged durumda beklemektedirler.

- **Arka Plan Senkronizasyonu, Satış Geçmişi, İptal/İade ve Katalog Altyapısı:**
  - `BackgroundSyncCoordinator` (periyodik 30 sn zamanlayıcı, lifecycle, connectivity restore, single-flight, trailing sync).
  - Satış Geçmişi (`SalesHistoryScreen`), Dashboard → Son Satışlar (`SaleDisplayStatus` / `SaleStatusBadge`), tam satış iptali (`SALE_CANCEL`), kısmi ürün iadesi (`SALE_REFUND` + `SELLABLE`/`DAMAGED` ayrımı), Ürün/Kategori Katalog CRUD (`CatalogScreen`), çoklu barkod ve fiyat geçmişi (`LocalPriceHistory`).
- **Satış Downlink ve `SALE_REFUND` FK / Android İade Düzeltmesi:**
  - `GET /api/v1/sales` (cursor tabanlı satış indirme) ve echo-prevention koruması.
  - `SALE_REFUND` Foreign Key çözümlemesi (`device_id` + `target_client_seq`).
  - `reconcileSaleStatuses()`, `upsertSales()` yeni/mevcut satış durum türetmesi, Hub `SALE_REFUND` sonrası `sales.status` güncellemesi ve `GET /api/v1/sales` içinde `effectiveStatus` türetmesi.
  - Android Release APK ([`build/app/outputs/flutter-apk/app-release.apk`](../build/app/outputs/flutter-apk/app-release.apk)): 20 Kasım 2026 tarihli derlemenin başarılı olduğu Antigravity tarafından raporlanmıştır *(fiziksel Android cihaz üzerinde kabul testi henüz beklenmektedir)*.
- **Faz 1.1 — Hub-side UDP Discovery Responder (Yalnızca Windows Tarafı):**
  - [`test_spikes/spike_01_backend/lib/discovery/discovery_responder.dart`](../test_spikes/spike_01_backend/lib/discovery/discovery_responder.dart): Saf Dart `RawDatagramSocket` ile UDP `8946` dinleyicisi, `DISCOVER_MMS_HUB` komutuna unicast JSON yanıt (`service`, `protocol_version`, `hub_id`, `http_port: 8945`, `server_time`, `server_ips` sanal adaptör filtreli).
  - [`test_spikes/spike_01_backend/bin/server.dart`](../test_spikes/spike_01_backend/bin/server.dart): `SpikeServer.start()` / `stop()` yaşam döngüsü entegrasyonu, `--discovery-port` ve `--no-discovery` bayrakları.
  - [`test_spikes/spike_01_backend/test/hub_discovery_responder_test.dart`](../test_spikes/spike_01_backend/test/hub_discovery_responder_test.dart): 7 senaryo ve ilgili backend regresyon testlerinin geçtiği raporlanmıştır.
  - **Windows Gerçek Ortam Doğrulaması (Antigravity Tarafından Yürütüldü):** Güncel `mms_backend.exe` derlendi; kontrollü shutdown/restart yapıldı; TCP `8945` (`0.0.0.0`) ve UDP `8946` (`0.0.0.0`) dinlemesi, `/health` (`200 UP`), `192.168.1.255` ve `255.255.255.255` UDP broadcast yanıtları ve dönen IP'lerle (`192.168.1.158`, `192.168.84.2`, `172.19.64.1`) HTTP `/health` erişimi Windows makinesi üzerinde doğrulanmıştır. *(Not: `build_aot.ps1` çalıştırıldığında arka plandaki eski `MarketMmsSpike01` süreci `sqlite3.dll` dosyasını kilitlediği için betik 59. satırda kopyalama hatası verdi; ancak diskteki `sqlite3.dll` SHA-256 hash'inin özdeş olduğu doğrulandı.)*

---

## 4. Henüz Test Edilmemiş ve Başlanmamış İşler

### A. Fiziksel Cihazda Henüz Test Edilmemiş Açık Doğrulamalar
- [ ] **Faz 1.1 Gerçek Android Ağ Testi:** Fiziksel Android cihazdan yerel Wi-Fi ağı üzerinden UDP `8946` broadcast keşfinin ve Windows Firewall geçişinin çalışıp çalışmadığı **henüz test edilmemiştir** (şu ana kadar yalnızca Windows makinesi üzerinden doğrulandı).
- [ ] **Android İade Durumu Fiziksel Doğrulama:** 20 Kasım 2026 tarihli `app-release.apk` üzerinde iade edilen satışların `İADE EDİLDİ` / `KISMİ İADE` göründüğü fiziksel cihazda **henüz kullanıcı tarafından doğrulanmamıştır**.

### B. Faz 1 Alt Aşamaları *(20 Kasım Tarihsel Listesi — Güncel Durum Notlu)*
- [x] **Faz 1.2 — Client Storage ve Hub Adresi Saklama *(Kodda Tamamlandı — Fiziksel Kabul Bekler)*:**
  - Son başarılı Hub adresinin yerel kalıcı depolamada saklanması (`SharedPreferencesHubConnectionStore` / kalıcı bağlantı durumu).
  - Kayıtlı adresin yeniden doğrulanması ve TLS/Loopback güvenlik politikaları.
  - Adres değişikliğinin güvenli yönetimi (`schemaVersion = 3` korunarak, migration gerektirmeden).
  - Offline çalışma davranışının ve satış/outbox mekanizmalarının eksiksiz korunması.
- [x] **Faz 1.3 — Android Discovery ve Bağlantı Yönetimi *(Kodda Tamamlandı + `WP-1` ile Sertleştirildi — Fiziksel Kabul Bekler)*:**
  - Android'de hardcoded `http://127.0.0.1:8945` varsayılanının kaldırılması (E2E testi dahil `MMS_E2E_HUB_URL` + `UdpHubDiscoveryClient` olarak düzeltildi).
  - UDP Discovery isteği ve Hub yanıtının doğrulanması + TLS fail-closed eşleştirme.
  - Birden fazla IP adayı arasından HTTP `/health` geçen erişilebilir IP'nin seçilmesi.
  - Otomatik reconnect (`WP-1` `onHubNetworkUnreachable` ↔ `reportTransportUnreachable` + `onResume` kontrolü) ve manuel IP fallback mekanizması ile UI durum göstergesi.
- [ ] **Faz 1.4 — Gerçek Android–Windows Kabul Testi (`PAT-01…PAT-18` — `BLOCKED`):** Fiziksel cihaz/ağ testleri Owner onayıyla yürütülecek.
- [ ] **Phase 2 & v1.1 Açık Kalan İşler:** `ADR-022` Android Google Drive OAuth (`google_sign_in`, Phase 2), Kullanıcı/RBAC & bağımsız Raporlama/Export (v1.1), `B1` Android imza anahtarı, `B2` Hub TLS üretim sertifikaları, `C1/C2` Google Cloud OAuth kurulumu ve `D1–D4` temizlik adımları.

### C. Sonraki Ana Fazlar (Faz 2 – Faz 7)
- Faz 2 (UI Ayrıştırması), Faz 3 (Platform Klavye/Barkod), Faz 4 (Kamera ile Ürün Tanımlama), Faz 5 (Open Food Facts), Faz 6 (Mobil Kullanılabilirlik/Offline Deneyimi) ve Faz 7 (Üretim/Kurulum/Dağıtım) fazları Faz 1 kabul edilmeden **kesinlikle başlatılmayacaktır**.

---

## 5. Bilinen Teknik Riskler ve Açık Konular

1. **Çoklu Ağ Arayüzleri ve Sanal Adaptör Seçim Riski:** Windows test makinesinde aktif Wi-Fi (`192.168.1.158`) dışında ikinci arayüz (`Ethernet 3: 192.168.84.2`) ve Hyper-V (`172.19.64.1`) bulunmaktadır. Global broadcast (`255.255.255.255`) atıldığında kaynak IP bazen `172.19.64.1` olarak dönebilmektedir. Faz 1.3'te Android istemcisi hem UDP yanıtındaki `server_ips` listesini hem kaynak IP'yi değerlendirip yalnızca **HTTP `/health` doğrulaması başarılı olan adresi** seçmelidir.
2. **Windows Firewall Profili ve İkili Dosya Yolu:** Mevcut Wi-Fi profili `Public` olarak görünmektedir ve kural mevcut `build/mms_backend.exe` yolu üzerindeydi. Ağ `Private`/`Domain` olduğunda veya üretim kurulumunda `%PROGRAMDATA%\MarketMMS\bin\` kullanıldığında TCP `8945` + UDP `8946` kurallarının tanımlanması gerekecektir.
3. **`sqlite3.dll` Dosya Kilidi Riski:** `build_aot.ps1` çalıştırılırken eski `MarketMmsSpike01` süreci `sqlite3.dll`'i kilitleyebilmektedir; derleme öncesi aktif süreçlerin kontrollü durdurulması gerekir.
4. **Router AP Isolation / Android UDP Kısıtları:** Mağaza Wi-Fi modemlerinde istemci izolasyonu veya multicast/broadcast filtrelemesi varsa otomatik keşif başarısız olabilir; bu nedenle manuel IP fallback ve tam offline satış devamlılığı zorunludur.
5. **Çalışma Alanında Unstaged Değişiklikler:** `HEAD = a118434` üzerinde 22 Kasım Aşama 1/3/4/2 değişiklikleri (`24` değiştirilmiş, `13` takip edilmeyen dosya; `4` korunan `.vscode`/`*.bat` yerel dosyası dahil) unstaged beklemektedir; Owner onayı olmadan commit/push yapılmaz.
6. **Pilot Öncesi Açık Güvenlik/Donanım Koşulları:** Fiziksel cihaz/ağ testleri (`PAT-01…PAT-18`), `B1` Android release imza anahtarı, `B2` Hub TLS üretim sertifikaları, `C1/C2` Google Cloud OAuth kurulumu ve `D1–D4` test ortamı temizliği (`OWNER_ACTION_CHECKLIST.md`) henüz tamamlanmamıştır.
7. **Dokümantasyon & Mimari Notlar:**
   - `OD-01` (Half-Up kuruş yuvarlama) ve `OD-03` (offline yeni ürün + `PRODUCT_UPSERT` serbest / satışta ad-hoc kayıtsız ürün yasak; `BUSINESS_RULES_SPEC.md` v1.7) kesinleşmiştir.
   - `go_router` paketi *Planlı / Pilot Sonrası* kapsamındadır (`AGENTS.md` & `README.md`); Pilot 1.0'da `MainShellScreen` aktiftir.
   - `ADR-022` (Android `google_sign_in`) Phase 2 kapsamındadır; Kullanıcı/RBAC ve bağımsız Raporlama/Export v1.1 kapsamındadır.

---

## 6. Bir Sonraki İş

1. Owner'ın `22 Kasım` Aşama 1/3/4/2 değişikliklerini gözden geçirip commit/kabul kararını vermesi (`OWNER_ACTION_CHECKLIST.md` `A2`).
2. `OWNER_ACTION_CHECKLIST.md` içindeki temizlik ve kimlik/sertifika adımlarının (`D1–D4`, `B2`, `B1`, `C1/C2`) tamamlanması.
3. Fiziksel Windows + Android donanımı üzerinde **`PAT-01…PAT-18`** kabul testlerinin tek adım protokolüyle yürütülmesi ve ardından Phase 2 (`ADR-022` `google_sign_in`) için onay verilmesi.
