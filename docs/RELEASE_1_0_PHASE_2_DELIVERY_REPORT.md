# MARKET MMS — RELEASE 1.0 PILOT YAZILIM KAPANIŞI & PHASE 2 (`ADR-022`) TESLİMAT RAPORU

- **Tarih:** 22 Kasım 2026
- **Kapsam:** **Commit 1 (`ebf726a`: `WP-1`, `A7`, `K-05`, Docs)** + **WP-3 (`ADR-022` Android Google Drive OAuth `google_sign_in: ^7.2.0`)** + **WP-4 (Tam Regresyon, Çoklu Platform Build, `.ps1` Sözdizimi & Dokümantasyon Kapanışı)**
- **Genel Durum:** **`ALL SOFTWARE WORK PACKAGES DELIVERED (799/799) — PAT-01…PAT-18 & EXTERNAL OWNER OPS BLOCKED`**

> [!IMPORTANT]
> **Dürüst Doğrulama ve Sınır Beyanı:** Bu oturumda Pilot 1.0 yazılım geliştirme kapsamındaki **tüm teknik geliştirme, birim/widget/entegasyon testleri, çok platformlu derlemeler ve dokümantasyon uzlaştırması** tamamlanmış ve sıfır hata ile geçmiştir (`799/799` test). Bununla birlikte bağlı fiziksel Android cihaz (`adb devices` boş), üretim Android upload keystore (`android/key.properties` yok), üretim Hub TLS sertifikaları (`C:\ProgramData\MarketMMS` yok) ve gerçek Google Cloud OAuth hesabı (`C1/C2`) ortamda mevcut olmadığı için **`D1–D4` temizlik, `B1`, `B2`, `C1/C2`, fiziksel kabul testleri (`PAT-01…PAT-18`) ve resmî faz kabulleri (`E2`)** çalıştırılamamıştır (`BLOCKED`).

---

## 1. Faz Hedefleri ve Tamamlanma Durumu

| İş Kalemi / Çalışma Paketi | Hedef | Durum |
|---|---|---|
| **Commit 1 (`WP-1` + `A7` + `K-05` + Docs)** | DHCP/Wi-Fi `connected` reconnect, mobil ergonomi `48dp`, kalıcı tema, Test 15 timeout, E2E sabit IP temizliği, `OD-03`/`go_router` dokümanları, Windows QR görseli (`qr_flutter`), Hub TLS-pinned live-drive config (`K-05`) | **Tamamlandı & Push Edildi** (`ebf726a240f016df19a613b5d730d60256c39ac2`) |
| **WP-3 (`ADR-022` Phase 2 — `google_sign_in: ^7.2.0`)** | Android `Credential Manager` + `AuthorizationClient` tabanlı OAuth, ortak Windows/Android `driveAccessTokenProvider`, Android UI bağla/kaldır & `ADR-021` entegrasyonu | **Tamamlandı & Test Edildi (9/9 + Debug APK)** |
| **WP-4 Yazılım, Build & Betik Kapanışı** | 4 paket tam re-test, 7 `.ps1` parse, Hub Dart AOT, Windows Debug+Release, Android Debug APK + Release fail-closed guard, tüm kanonik dokümanların güncellenmesi | **Tamamlandı & Doğrulandı** |
| **WP-2 / Saha Kabulü (`D1–D4`, `B1`, `B2`, `C1/C2`, `PAT-01…18`, `E2`)** | Fiziksel cihaz, donanım, temiz ortam ve dış hesaplarla canlı Pilot 1.0 doğrulaması | **`BLOCKED — OWNER HARDWARE & CREDENTIALS REQUIRED`** |

---

## 2. Gerçekleştirilen Geliştirmeler (`WP-3` `ADR-022` + `WP-4`)

1. **`pubspec.yaml` & `pubspec.lock`:** `google_sign_in: ^7.2.0` bağımlılığı `3.13.7` / Flutter `3.47.9` üzerinde çakışmasız çözümlendi.
2. **[`android_google_sign_in_token_provider.dart`](../lib/features/backup/application/android_google_sign_in_token_provider.dart):**
   - `GoogleSignInClientAdapter` ve gerçek `GoogleSignIn.instance` v7+ sarıcısı `PluginGoogleSignInClientAdapter` yazıldı (`initialize(serverClientId)`, `attemptLightweightAuthentication()`, `authenticate()`, `authorizationForScopes`, `authorizeScopes`, `authorizationClient.clearAuthorizationToken(accessToken: ...)`, `signOut()`, `disconnect()`).
   - `AndroidGoogleSignInTokenProvider implements DriveAccessTokenProvider`: yalnızca `https://www.googleapis.com/auth/drive.file` kapsamını ister (`ADR-011`); kısa ömürlü `access_token`'ı **yalnızca RAM'de** (`50 dk` TTL) önbellekler ve `RedactingLogger` ile maskeler; `SecureTokenStore`'a kesinlikle ham token yazmaz (yalnızca sır-olmayan `gdrive_connected_v1` + `gdrive_account_email_v1`).
   - `forceRefresh: true` anında eski token'ı `clearAuthorizationToken` ile temizleyip sessiz yenileme dener; başarısız olursa `ERR_DRIVE_REAUTH_REQUIRED` döndürür.
   - `disconnect()` uzak iptali (`disconnect()`) dener, ağ/servis hatasında `signOut()` + yerel bayrak temizliğine düşer; `.mmsbak` dosyalarına, `outbox_operations` veya `client_seq` kayıtlarına dokunmaz.
   - `GoogleSignInException`, `MissingPluginException` ve `PlatformException` hatalarını Türkçe kullanıcı dostu güvenli kodlara (`ERR_DRIVE_NOT_CONFIGURED`, `ERR_DRIVE_GMS_UNAVAILABLE`, `ERR_DRIVE_REAUTH_REQUIRED`, `ERR_OAUTH_DENIED`, `ERR_DRIVE_UNAVAILABLE`) eşler ve token sızdırmaz.
3. **[`drive_auth_providers.dart`](../lib/features/backup/drive_auth_providers.dart), [`google_drive_connect_service.dart`](../lib/features/backup/application/google_drive_connect_service.dart), [`backup_providers.dart`](../lib/features/backup/backup_providers.dart), [`sync_providers.dart`](../lib/features/sync/sync_providers.dart):**
   - `backup_providers.dart` ↔ `sync_providers.dart` arasında döngüsel bağımlılık yaratmadan platform-bağımsız `driveAccessTokenProvider` ayrıştırıldı (`kGoogleDriveClientId`, `kGoogleDriveClientSecret`, `kGoogleDriveWebClientId` / `MMS_GDRIVE_WEB_CLIENT_ID`).
   - `GoogleDriveConnectService` Windows PKCE akışını koruyarak Android modunda `AndroidGoogleSignInTokenProvider`'a yönlendirildi.
   - `driveLiveSyncEngineProvider` ve `googleDriveUploaderProvider` artık hem Windows hem Android üzerinde `driveAccessTokenProvider` tüketir (OAuth kimliği yoksa fail-safe `null` döner).
   - `backupScheduleControllerProvider` `afterSuccess` Drive yüklemesi fail-safe `try/catch` + `RedactingLogger` ile sarıldı (yerel `.mmsbak` başarısı Drive hatasından etkilenmez).
4. **[`external_backup_section.dart`](../lib/features/backup/presentation/widgets/external_backup_section.dart):** Android mobil profilde de `MMS_GDRIVE_WEB_CLIENT_ID` tanımlıysa `gdrive_connect_button` (Bağla / Kaldır) ve `gdrive_list_backups_button` görünür hale getirildi; kimlik yoksa fail-safe `gdrive_not_configured_banner` korunur.
5. **Kapsamlı Test Süiti ([`android_google_sign_in_oauth_test.dart`](../test/features/backup/android_google_sign_in_oauth_test.dart)):** Boş `serverClientId`, scope & RAM-only token, TTL + `forceRefresh`, sessiz yenileme `null`, soğuk başlatma `attemptLightweightAuthentication`, offline fallback `disconnect` + Outbox korunması, gerçek `PluginGoogleSignInClientAdapter.mapError`, Android `ExternalBackupSection` widget akışı ve `ADR-021` + `ADR-022` uçtan uca Hub-first / TLS-auth non-fallback / `401` yenileme senaryoları dahil **9/9 test** yazıldı ve geçirildi.

---

## 3. Oluşturulan ve Değiştirilen Dosyalar

- **Commit 1 (`ebf726a` — `33` dosya):** `WP-1`, `A7`, `K-05` ve ilk dokümantasyon uzlaştırması ([`LIVE_PROJECT_STATUS.md`](./LIVE_PROJECT_STATUS.md) özetli).
- **Commit 2 (`WP-3` `ADR-022` + `WP-4` Dokümantasyon Kapanışı):**
  - Yeni kod & test:
    - `lib/features/backup/application/android_google_sign_in_token_provider.dart`
    - `lib/features/backup/drive_auth_providers.dart`
    - `test/features/backup/android_google_sign_in_oauth_test.dart`
    - `docs/RELEASE_1_0_PHASE_2_DELIVERY_REPORT.md`
  - Güncellenen kod & doküman:
    - `pubspec.yaml`, `pubspec.lock`
    - `lib/features/backup/application/google_drive_connect_service.dart`
    - `lib/features/backup/backup_providers.dart`
    - `lib/features/backup/presentation/widgets/external_backup_section.dart`
    - `lib/features/sync/sync_providers.dart`
    - `docs/decisions/022-android-google-drive-oauth-design.md`, `docs/decisions/README.md`
    - `PHYSICAL_ACCEPTANCE_TEST_PLAN.md`, `OWNER_ACTION_CHECKLIST.md`, `docs/LIVE_PROJECT_STATUS.md`, `docs/MASTER_ROADMAP.md`

---

## 4. Mimari Kararlar ve Gerekçeleri

- **`drive_auth_providers.dart` Ayrımı:** `googleDriveConnectServiceProvider`, `driveAccessTokenProvider` ve `androidGoogleSignInTokenProvider`'ı ayrı bir dosyaya alarak `backup_providers.dart` ile `sync_providers.dart` arasında döngüsel Riverpod/import bağımlılığı engellendi.
- **Kuru `drive.file` + RAM-Only Access Token (`ADR-022`):** Android `AuthorizationClient` ham `refresh_token` vermediğinden diske/Keystore'a token yazılmadı; yalnızca sır-olmayan `gdrive_connected_v1` ve `gdrive_account_email_v1` saklanarak soğuk başlatmada `ERR_DRIVE_REAUTH_REQUIRED` ayrımı sağlandı.

---

## 5. Çalıştırılan Testler ve Gerçek Sonuçları (Son Kod Düzenlemesi Sonrası)

| Paket / Komut | Statik Analiz | Test Sonucu |
|---|---|---|
| `packages/mms_contracts` (`dart analyze` + `dart test`) | `No issues found!` (exit `0`) | **7/7 All tests passed!** |
| `packages/mms_client_storage` (`dart analyze` + `dart test`) | Exit `0` (`16` önceden var olan `sqlite3 dispose` info, 0 hata/uyarı) | **225/225 All tests passed!** |
| `test_spikes/spike_01_backend` (`dart analyze` + `dart test`) | Exit `0` (`18` önceden var olan `sqlite3 dispose` info, 0 hata/uyarı) | **249/249 All tests passed!** |
| Kök `market_pos` (`flutter analyze` + `flutter test`) | `No issues found!` (exit `0`) | **318/318 All tests passed!** |
| **Toplam Otomatik Test (4 Paket)** | **4/4 Paket Exit `0`** | **799/799 geçti / 0 başarısız / 0 atlanan** |

- **PowerShell Betik Sözdizimi Kontrolü:** `[System.Management.Automation.Language.Parser]::ParseFile(...)` ile **`7/7` `.ps1` betiği** (`configure_hub_firewall.ps1`, `package_android_release.ps1`, `package_windows_release.ps1`, `build_aot.ps1`, `install_mms_service.ps1`, `setup_service_acls.ps1`, `uninstall_mms_service.ps1`) **0 sözdizimi hatası** ile doğrulandı.

---

## 6. Build Sonuçları

| Hedef | Komut | Çıktı / Durum |
|---|---|---|
| **Windows Hub Dart AOT (`build_aot.ps1`)** | `powershell -NoProfile -ExecutionPolicy Bypass -File test_spikes\spike_01_backend\scripts\build_aot.ps1 -OutputDir "$env:TEMP\mms_aot_verify"` | **Başarılı** (`mms_backend.exe`, `8.76 MB`, SHA-256: `54FE640284C6D32352CA7C5A7896182A290F371E97F02772B5371E9D1D1F5DF4`, `10697 ms`; geçici klasör temizlendi) |
| **Windows Desktop Debug** | `flutter build windows --debug` | **Başarılı** (`build\windows\x64\runner\Debug\market_pos.exe`) |
| **Windows Desktop Release** | `flutter build windows --release` | **Başarılı** (`build\windows\x64\runner\Release\market_pos.exe`) |
| **Android APK Debug (`google_sign_in` dahil)** | `flutter build apk --debug` | **Başarılı** (`build\app\outputs\flutter-apk\app-debug.apk`) |
| **Android Release Fail-Closed İmza Kapısı** | `flutter build apk --release` | **Başarılı — Beklenen Engelleme (Exit `1`)**: `"Release imzalama yapılandırılmadı: android/key.properties bulunamadı"` |

---

## 7. Veritabanı ve Migration Etkileri

- **Sıfır şema değişikliği:** `ClientDatabase.schemaVersion = 3` ve `SpikeDatabase.schemaVersion = 3` korundu; migration gereksinimi doğmadı.
- FIFO Outbox sırası, `client_seq` monotonik artışı, ACK-önce-`SYNCED` yasağı, kuruş tamsayı + Half-Up yuvarlama (`OD-01`) ve `MMSENV01` / `MMSBAK01` kripto ayrımı birebir korundu.

---

## 8. Güvenlik Değerlendirmesi

- Android APK içine hiçbir `client_secret`, API anahtarı veya `drive_live_sync_secret_v1` gömülmez; `android/key.properties` olmadan Release paketleme Gradle tarafından fail-closed engellenir.
- `AndroidGoogleSignInTokenProvider` yalnızca `https://www.googleapis.com/auth/drive.file` kapsamını kullanır, `accessToken` değerini RAM'de tutup `RedactingLogger` ile maskeler ve loglara/SQLite'a/diske yazmaz.
- Hub `K-05` `live_drive_sync_secret.dpapi` Windows DPAPI ile korunur ve `GET /api/v1/sync/live-drive-config` `strictTenantStorePaths` + `Cache-Control: no-store` arkasındadır.

---

## 9. Performans Değerlendirmesi

- Android OAuth token'ı bellek içi TTL (`50 dk`) önbelleğiyle gereksiz Play Services IPC çağrılarını önler.
- Hub `live-drive-config` eşitlemesi `BackgroundSyncCoordinator.onSyncCompleted` içinde `5 dk` throttle ile çalışır ve eşdeğer cihaz listesinde disk yazımını atlar.
- Dart AOT backend `spike_test` 4 istemci normal yük (`P50 62 ms`) ve 10 istemci stres (`P50 123 ms`–`144 ms`), pilot E2E (`P50 11 ms`) metriklerini korumuştur.

---

## 10. Tespit Edilen Sorunlar ve Çözümleri

- **`google_sign_in` v7.2 API Yüzeyi:** `attemptLightweightAuthentication()` nullable `Future<GoogleSignInAccount?>?` döner; `clearAuthorizationToken({required String accessToken})` ise `GoogleSignIn.instance.authorizationClient` üzerindedir — kaynak paket okunarak birebir doğru çağrılar yazıldı.
- **Test 9 `runDriveFallbackCycle` Kapısı:** `recordHubFailure` `driveFallbackActive` bayrağını Ledger'da tutar ve koordinatör bu bayrağı kontrol eder; test güncellenerek `recordHubFailure(isSecurityHold: true)` / `isAuthFailure` kapısı doğrulandı.

---

## 11. Kalan Riskler ve Eksikler

- **Donanım & Dış Hesap Eksikleri (`BLOCKED`):** Fiziksel Android cihaz (`adb devices` boş), `D1` (`MarketMmsSpike01` arka plan spike servisi hâlâ çalışıyor), `B2` (Hub TLS üretim sertifikaları), `B1` (`android/key.properties` & upload keystore), `C1/C2` (Google Cloud OAuth Desktop + Android SHA-1 + Web `serverClientId`, `"In production"`) ve `PAT-01…PAT-18` henüz sahada denenmedi.
- **`ADR-020` + `google_sign_in` Arka Plan Sınırı:** `JOB_ID = 70201` uygulaması tamamen kapalıyken yerel şifreli `.mmsbak` üretmeye devam eder; Google Drive'a yükleme ön plan açılışında `DriveUploadLedger` ile garanti edilir.
- **v1.1 Ertelenen Modüller:** Kullanıcı/RBAC, bağımsız Raporlama/CSV-PDF, `go_router` ve `ADR-019` çoklu KDV şema v3→v4 migrasyonu Pilot 1.0 kapsamı dışındadır (`v1.1`).

---

## 12. Owner Tarafından Yürütülmesi Gereken Fiziksel Saha / Operasyon Adımları

Fiziksel ortam hazır olduğunda tek seferde bir test adımı kuralıyla (`GEMINI.md` §6.8) sırasıyla şu adımları yürütün:

1. **Temizlik (`D1–D4`):** Yönetici PowerShell'de `Stop-Service MarketMmsSpike01` ve `test_spikes\spike_01_backend\service_wrapper\MarketMmsSpike01.exe uninstall`; ardından test DB/token dosyalarını (`D2–D4`) temizleyin.
2. **Hub TLS & Servis Kurulumu (`B2`):** OpenSSL (`C:\OpenSSL\bin\openssl.exe`) ile `ca.crt`, `server.crt` (zorunlu `IP:127.0.0.1` + sabit LAN IP SAN) ve `server.key` üretip `C:\ProgramData\MarketMMS\certs\` altına koyun; güncel `mms_backend.exe`'yi (`build_aot.ps1`) kurup `install_mms_service.ps1`, `setup_service_acls.ps1`, `configure_hub_firewall.ps1` çalıştırın.
3. **Android Keystore (`B1`):** `keytool` ile depo dışında `market_mms_upload.jks` ve `android/key.properties` oluşturup `SHA-1` ve `SHA-256` parmak izlerini alın.
4. **Google Cloud OAuth (`C1/C2`):** Aynı Google Cloud projesinde Drive API'yi açıp yalnızca `drive.file` kapsamıyla ekranı `"In production"` yapın; Desktop Client ID, Android Client ID (`com.marketmms.market_pos` + `B1` SHA-1) ve Web `serverClientId` üretin.
5. **Üretim Paketleme & Saha Testleri (`PAT-01…PAT-18`):**
   - Android Release APK'yı `MMS_GDRIVE_WEB_CLIENT_ID` tanımlı derleyin (`package_android_release.ps1`), Windows paketini `MMS_GDRIVE_CLIENT_ID` ile paketleyin (`package_windows_release.ps1`).
   - [`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`](../PHYSICAL_ACCEPTANCE_TEST_PLAN.md) sırasıyla (`PAT-12 adım 1` → `PAT-08` → `PAT-10` → `PAT-11` → `PAT-03` → `PAT-12 adım 2–5` → `PAT-01, 02, 04..07, 09, 14..16` → `PAT-13` → `PAT-17` → `PAT-18`) çalıştırıp `E2` kabulünü verin.

---

## 13. Git Durumu

- Commit 1 (`ebf726a`): `feat(market-mms): complete WP-1 hardening, A7 QR, K-05 Hub live-drive provisioning and docs reconciliation` (`origin/main`'e push edildi).
- Commit 2 (`WP-3` `ADR-022` + `WP-4` kapanışı): Explicit dosya listesiyle stage → commit → `origin/main` push yapılacak (4 yerel korunan dosya `.vscode/settings.json`, `run_windows_client.bat`, `start_master_hub.bat`, `stop_master_hub.bat` commit dışı korunacaktır).

---

## 14. Bir Sonraki Faza (`v1.1`) Geçiş İçin Gerekli Koşullar

1. Owner tarafından `D1–D4`, `B2`, `B1`, `C1/C2` kurulumlarının tamamlanması,
2. Fiziksel Windows + Android donanımında `PAT-01…PAT-18` testlerinin geçilmesi,
3. Owner'ın resmî **Pilot 1.0 (`v1.0.0`)** faz kabulünü vermesi.

**DURUM: `FAZ KABULÜ BEKLİYOR`**
