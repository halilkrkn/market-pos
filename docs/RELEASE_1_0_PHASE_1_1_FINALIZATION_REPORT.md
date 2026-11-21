# MARKET MMS — RELEASE 1.0 / PHASE 1.1 NİHAİ TESLİMAT RAPORU (FINALIZATION)

- **Tarih:** 22 Kasım 2026
- **Oturum:** **PHASE 1.1 FINALIZATION — `ADR-022` + Android NDK `28.2.13676358` + Build & Test Doğrulama + Git Teslimatı**
- **Genel Teslimat Durumu:** **`PHASE 1.1 COMPLETE — SOFTWARE VALIDATION PASSED`**

> [!IMPORTANT]
> **Dürüst Kapsam ve Doğrulama Beyanı:** Bu aşamada tüm yazılımsal ve dokümantasyon doğrulamaları (`774/774` test, `4` paket `analyze = 0`, NDK `28.2.13676358` kurulumu, Kotlin compile, Debug APK ve Release fail-closed kontrolü) fiilen çalıştırılıp geçmiştir. Ancak **Phase 2** işleri (`ADR-022` `google_sign_in` implementasyonu, Google Cloud OAuth yapılandırması, Release keystore üretimi, Hub TLS sertifikaları ve **`PAT-01…PAT-18`** fiziksel kabul testleri) yürütülmemiştir (`BLOCKED / NOT RUN`). Pilot kabulü veya production readiness iddiasında bulunulmaz.

---

## 1. Owner Kararları

Phase 1.1 Finalization kapsamında Owner tarafından kesinleştirilen ve birebir uygulanan kararlar:

| Konu | Kesinleşen Karar | Uygulama Durumu |
|---|---|---|
| Android Google Drive OAuth | **Seçenek A — `google_sign_in`** | `ADR-022` güncellendi (`DESIGN APPROVED — PENDING PHASE 2 IMPLEMENTATION`) |
| Android Drive Entegrasyonu | **Pilot kapsamına dahil** | `ADR-022`, `OWNER_ACTION_CHECKLIST.md` ve `PRODUCTION_DEPLOYMENT_RUNBOOK.md` içine işlendi |
| OAuth Implementasyonu | **Yalnızca mimari karar ve teknik tasarım; kodlama yok** | Kod yazılmadı, `google_sign_in` eklenmedi, Google Cloud / credential işlemi yapılmadı |
| Android NDK | **`28.2.13676358` kurulacak** | Kuruldu (`android-ndk-r28c`), `build.gradle.kts` `flutter.ndkVersion` oldu, derleme doğrulandı |
| Android Uygulama Sürümü | **`1.0.0+1`** | `pubspec.yaml:5`, `local.properties` ve `aapt2 dump badging` ile doğrulandı |
| `PAT-16` Kanonik Job ID | **`70201`** | Kotlin kodu + dokümanlar + otomatik testle kilitlendi |
| `ADR-021` Drive Klasör Adı | **`MARKET MMS LiveSync`** | Kod sabiti (`hybrid_drive_live_sync.dart:878`) ve `ADR-021` §S5 uyumlu |
| Git Teslimatı | **ADR-022 ve NDK sonrası doğrulamalar geçerse commit/push** | `feat(market-mms): finalize phase 1.1 remediation` (4 korunan dosya dışarıda) |

---

## 2. `ADR-022` Teknik Değerlendirmesi

- **Belge:** [`docs/decisions/022-android-google-drive-oauth-design.md`](./decisions/022-android-google-drive-oauth-design.md)
- **Kayıt Durumu:** **`DESIGN APPROVED — PENDING PHASE 2 IMPLEMENTATION`** (`docs/decisions/README.md`: `DESIGN_APPROVED`). Uygulama henüz kodlanmadığı için `IMPLEMENTED` veya `CONFIRMED` yazılmamıştır.
- **Teknik Özeti:**
  - `google_sign_in` **v7+** mimarisi kullanıcı kimlik doğrulamasını (Android **Credential Manager**: `GoogleSignIn.instance.initialize(serverClientId: ...)` + `authenticate()`) API kapsam yetkilendirmesinden (Play Services **`AuthorizationClient`**: `authorizeScopes` / `authorizationForScopes`) ayırır.
  - **Least Privilege (`ADR-011`):** Yalnızca `https://www.googleapis.com/auth/drive.file` kapsamı talep edilir; Windows Desktop, Android ve Web (`serverClientId`) OAuth istemcileri **aynı Google Cloud projesinde** tanımlanmalıdır.
  - **Mevcut Sözleşme Uyumu:** Mevcut `GoogleDriveBackupUploader` (`"MARKET MMS Yedekleri"`) ve `GoogleDriveLiveEnvelopeTransport` (`"MARKET MMS LiveSync"`) yalnızca `DriveAccessTokenProvider.accessToken({bool forceRefresh = false})` soyutlamasına bağlıdır; Phase 2'de eklenecek `AndroidGoogleSignInTokenProvider` protokol/şema/Hub-first (`ADR-021`) mimarisini bozmadan entegre olur.
  - **`authorizeScopes` vs `authorizeServer`:** MARKET MMS pilotunda bulut sunucu olmadığından ve APK içinde `client_secret` bulunamayacağından, sunucu değişim kodu (`serverAuthCode`) yerine istemci tarafı kısa ömürlü `access_token` (`authorizeScopes` / `authorizationForScopes`) kullanılır.
  - **Açık Teknik Sınır (Şeffaf Beyan):** `google_sign_in` Android istemciye kalıcı ham `refresh_token` **vermez**. Ayrıca uygulama tamamen kapalıyken headless `MmsBackgroundBackupJobService` (`JOB_ID = 70201`, sıfır `Activity`) içinden katılımsız Google Drive upload yapılabilmesi Seçenek A ile **garanti değildir / çözülmemiş konu** olarak işaretlenmiştir; `JOB_ID = 70201` yerel şifreli `.mmsbak` üretimini Keystore ile her durumda sürdürür, bekleyen yedekler ön plan oturumunda `DriveUploadLedger` ile idempotent yüklenir.

---

## 3. Google OAuth Token Lifecycle

1. **Hesap Seçimi & İlk Yetkilendirme:** Ön planda `initialize(serverClientId: MMS_GDRIVE_WEB_CLIENT_ID)` → `authenticate()` → `account.authorizationClient.authorizeScopes([drive.file])` ile kısa ömürlü `accessToken` (~1 saat) alınır ve **yalnızca RAM'de** tutulur (asla diske/Keystore'a/SQLite'a yazılmaz).
2. **Soğuk Başlatma (`Cold Start`):** Ön planda `initialize(...)` + `attemptLightweightAuthentication()` (event stream: `authenticationEvents`) + sessiz `authorizationForScopes([drive.file])` denenir. Credential Manager sessiz oturumu geri yükleyemezse yerel sır-olmayan `gdrive_connected_v1` bayrağı sayesinde POS/Hub senkronizasyonu etkilenmeden `ERR_DRIVE_REAUTH_REQUIRED` gösterilir.
3. **Süre Dolumu & `401` Yenileme:** Süre dolumunda veya `401`/`forceRefresh: true` anında `GoogleSignIn.instance.clearAuthorizationToken(accessToken: staleToken)` sonrası `authorizationForScopes` ile sessiz yenileme denenir; etkileşim/rıza (`hasResolution`) gerekiyorsa `ERR_DRIVE_REAUTH_REQUIRED` döner.
4. **Refresh Token & 7 Gün Kısıtı:** Android'de ham `refresh_token` saklanmaz. OAuth izin ekranı `"Testing"` statüsünde kalırsa Google yetki/tokenları **7 gün sonra otomatik iptal eder** (`"In production"` yayınlama zorunludur).
5. **Android Keystore (`MmsSecureStorageChannelHandler`):** `backup_schedule_password`, `drive_live_sync_secret_v1`, Hub pairing token ve sır-olmayan bağlantı bayrağını `AES/GCM/NoPadding` (`allowBackup="false"`, tüm bulut/aktarım alanları hariç) ile fail-closed korur.
6. **Sign-Out & İptal:** `signOut()` yalnızca yerel oturumu temizler; MMS "Bağlantıyı Kaldır" eylemi `clearAuthorizationToken` + `disconnect()` (`revokeAccess`) çağırarak Google sunucusundaki izni de iptal eder (çevrimdışıysa yerel temizlik + kullanıcı bildirimi). Yerel `.mmsbak` ve `outbox_operations` korunur.
7. **Eksik Yapılandırma Fail-Safe:** `MMS_GDRIVE_WEB_CLIENT_ID` eksikse, cihazda GMS yoksa veya SHA-1/`serverClientId` hatalıysa (`clientConfigurationError`) Drive sağlayıcıları devre dışı/`ERR_DRIVE_NOT_CONFIGURED` kalır; yerel POS, Hub senkronu ve `JOB_ID = 70201` yerel yedekleri çökmeden çalışır.

---

## 4. Google Cloud Owner Aksiyonları (`C1/C2` + `B1` — Phase 2 Ön Koşulu)

1. Mağazaya özel 2FA korumalı Google Cloud projesinde **Google Drive API** etkinleştirilecek.
2. OAuth Consent Screen üzerinde **yalnızca** `https://www.googleapis.com/auth/drive.file` kapsamı tanımlanacak ve 7 gün kuralı nedeniyle **`"In production"`** durumuna alınacak.
3. **Aynı proje içinde** 3 OAuth Client ID oluşturulacak:
   - **Desktop app** (Windows: `--dart-define=MMS_GDRIVE_CLIENT_ID=...`).
   - **Android** (`applicationId`: `com.marketmms.market_pos`; Debug ve `B1` Release `market_mms_upload.jks` **SHA-1** parmak izleri ayrı istemci olarak; **SHA-256** parmak izi denetim envanterine kaydedilecek; ileride Play Store kullanılırsa Play App Signing SHA-1 eklenecek).
   - **Web application (`serverClientId`)** (`--dart-define=MMS_GDRIVE_WEB_CLIENT_ID=...`, Phase 2; Web `client_secret` **asla** APK'ya konulmayacak).
4. `ADR-021` hibrit canlı senkronizasyon (`MARKET MMS LiveSync`) için `drive_live_sync_secret_v1` dağıtım yöntemi (`K-05`: Hub TLS-pinned vs Owner manuel/QR) netleştirilecek.

---

## 5. NDK Kurulum Sonucu (`28.2.13676358`)

- **Kurulum Komutu:** `C:\Users\halil\AppData\Local\Android\sdk\cmdline-tools\latest\bin\android.exe --sdk="C:\Users\halil\AppData\Local\Android\sdk" sdk install ndk/28.2.13676358`
- **Sonuç:** `EXIT=0` (`android-ndk-r28c-windows.zip`, `713.5 MB` indirildi ve `2.1 GB` çıkarıldı).
- **Disk Doğrulaması (`C:\Users\halil\AppData\Local\Android\sdk\ndk\28.2.13676358\source.properties`):**
  - `Pkg.Desc = Android NDK`
  - `Pkg.Revision = 28.2.13676358`
  - `Pkg.BaseRevision = 28.2.13676358`
  - `Pkg.ReleaseName = r28c`
- **Gradle Hizalaması:** `android/app/build.gradle.kts:29` `ndkVersion = flutter.ndkVersion` (`FlutterExtension.kt:42` varsayılanı: `"28.2.13676358"`) olarak güncellendi.
- **Gradle NDK Çıktısı:** `.\gradlew.bat :app:printNdkVersion` → **`NdkVersion: 28.2.13676358`** (sıfır NDK sürüm uyarısı).

---

## 6. Android Build ve Sürümleme Sonuçları

| Kontrol | Komut / Dosya | Gerçek Gözlenen Sonuç |
|---|---|---|
| **Flutter & Dart Sürümü** | `flutter --version` | `Flutter 3.47.9` (`stable`) · `Dart 3.13.7` · `DevTools 2.60.0` |
| **`pubspec.yaml` Sürümü** | `pubspec.yaml:5` | `version: 1.0.0+1` |
| **Kotlin Compile & NDK** | `.\gradlew.bat :app:printNdkVersion :app:compileDebugKotlin --no-daemon` | `NdkVersion: 28.2.13676358`, `BUILD SUCCESSFUL in 55s` (`exit 0`, `34` görev) |
| **Debug APK Build** | `flutter build apk --debug` | `Running Gradle task 'assembleDebug'... 164,6s` · `√ Built build\app\outputs\flutter-apk\app-debug.apk` (`exit 0`) |
| **APK Dosya & Boyut** | `build\app\outputs\flutter-apk\app-debug.apk` | `app-debug.apk` · `179.860.276` bayt |
| **`android/local.properties`** | Dosya içeriği | `flutter.buildMode=debug`, `flutter.versionName=1.0.0`, `flutter.versionCode=1` |
| **APK Metadata (`aapt2`)** | `aapt2.exe dump badging build\app\outputs\flutter-apk\app-debug.apk` | `package: name='com.marketmms.market_pos' versionCode='1' versionName='1.0.0' platformBuildVersionName='16' platformBuildVersionCode='36' compileSdkVersion='36'` · `minSdkVersion:'24'` · `targetSdkVersion:'36'` · `application-label:'Market MMS'` |
| **Release Fail-Closed Guard** | `.\gradlew.bat :app:assembleRelease --no-daemon` (`key.properties` yok) | `KEY_PROPS_EXISTS=False` → `BUILD FAILED in 46s` (`exit 1`: *"Release imzalama yapılandırılmadı: android/key.properties bulunamadı..."*) |
| **Paketleme Betiği (`PS 5.1`)** | `scripts/package_android_release.ps1` | `PS_BOM=True` (`EF BB BF`), `PS_AST_ERRORS=0`, `-Version 9.9.9 -SkipFlutterBuild` → `PS_GUARD_EXIT=1` (fail-closed) |

---

## 7. Test Sonuçları (`774 / 774` — Tüm Düzenlemeler Sonrası Tam Süit)

> [!NOTE]
> **İlk Tam Koşum ve Tekrar Koşum Gözlemi:** İlk tam çalıştırmada `packages/mms_client_storage` içindeki `s5a4_backup_restore_test.dart` **Test 15** (600.000 iterasyonlu PBKDF2 yedek + şifreli koruyucu kopyalı restore) `30 sn` varsayılan test zaman aşımına yakalanarak başarısız oldu (`7.48 sn + 25.14 sn`). Tekil koşumda (`9.21 sn + 18.16 sn = 27.37 sn`) ve ardından yeniden yürütülen tam 4 paketlik ardışık süitte (`7.835 ms + 17.515 ms = 25.35 sn`) sıfır hata/sıfır atlama ile geçti; hiçbir test silinmedi, atlanmadı veya gevşetilmedi.

| Modül / Paket | Komut | Geçen / Toplam | Başarısız / Atlanan | Çıkış Kodu | Süre | Statü |
|---|---|---:|---:|---:|---:|---|
| **`packages/mms_contracts`** | `dart test -r expanded` | **7 / 7** | 0 / 0 | `0` | `00:04.75` | `VERIFIED` |
| **`packages/mms_client_storage`** | `dart test -j 1` | **225 / 225** | 0 / 0 | `0` | `02:09.02` | `VERIFIED` |
| **`test_spikes/spike_01_backend`** | `dart test -j 1` | **245 / 245** | 0 / 0 | `0` | `03:11.18` | `VERIFIED` |
| **Kök `market_pos`** | `flutter test -j 1` | **297 / 297** | 0 / 0 | `0` | `03:05.23` | `VERIFIED` |
| **TOPLAM** | **4 Süit** | **774 / 774** | **0 / 0** | **`0`** | — | **`VERIFIED`** |
| `integration_test/` & `PAT-01…18` | Çalıştırılmadı | `BLOCKED` | — | — | — | `BLOCKED / NOT RUN` |

---

## 8. Analyze Sonuçları

| Paket | Komut | Çıkış Kodu | Süre | Gerçek Çıktı | Yeni Hata / Uyarı |
|---|---|---:|---:|---|---|
| `packages/mms_contracts` | `dart analyze` | `0` | `00:03.34` | `No issues found!` | 0 |
| `packages/mms_client_storage` | `dart analyze` | `0` | `00:04.95` | `16 issues found.` *(tamamı önceden var olan `test/s5a3_live_hub_integration_test.dart` ve `test/s5a4_backup_restore_test.dart` içindeki `sqlite3 dispose` `deprecated_member_use` `info` kayıtları)* | 0 |
| `test_spikes/spike_01_backend` | `dart analyze` | `0` | `00:08.40` | `18 issues found.` *(tamamı önceden var olan test dosyalarındaki `sqlite3 dispose` `deprecated_member_use` `info` kayıtları)* | 0 |
| Kök `market_pos` | `flutter analyze` | `0` | `00:46.66` | `No issues found! (ran in 41.2s)` | 0 |

---

## 9. Dokümantasyon ve PAT Kontrolü

Tüm ilgili belgeler incelendi ve Phase 1.1 kararlarıyla tutarlı hâle getirildi:

- `PAT-01…PAT-18` numaralandırması korundu ve tamamı **`BLOCKED / NOT RUN`** bırakıldı (`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`).
- `PAT-16` kanonik Job ID'si **`70201`** (`MmsBackgroundBackupJobService.kt`, `PHYSICAL_ACCEPTANCE_TEST_PLAN.md`, `ADR-020`, `OWNER_ACTION_CHECKLIST.md`, `PRODUCTION_DEPLOYMENT_RUNBOOK.md`, `android_release_hardening_test.dart`).
- `PAT-16` / `PAT-17` eşleştirmeleri ve `PAT-16..18` yürütme sırası tutarlı (`RELEASE_1_0_FINAL_DELIVERY_REPORT.md` + `PHYSICAL_ACCEPTANCE_TEST_PLAN.md` + `OWNER_ACTION_CHECKLIST.md`); `PAT-13` Android varyantına `ADR-022` Phase 2 ön koşul notu eklendi.
- `ADR-021` klasör adı kod sabitiyle (`MARKET MMS LiveSync`) birebir tutarlı (`021-hybrid-hub-google-drive-live-sync.md`).
- Windows Hub TLS kuralları (`advertise_host`, zorunlu `IP:127.0.0.1` loopback SAN `exit 78`, LAN SAN & pairing `HTTP 503` fail-closed) güncel (`docs/release/WINDOWS_HUB_RELEASE.md`, `hub_config.example.json`).
- `docs/PRODUCTION_DEPLOYMENT_RUNBOOK.md` içindeki eski `ADR-020 DEFERRED`, `PAT-01..15` ve `P-BLOCK` ifadeleri Phase 1.1 ile uzlaştırıldı.
- `docs/release/ANDROID_RELEASE.md` sürümleme (`1.0.0+1`), APK isimlendirme (`market_mms_v1.0.0-b1.apk`) ve NDK `28.2.13676358` doğrulaması ile güncellendi.

---

## 10. Korunan Kaynakların Durumu

| Korunan Kaynak | Kontrol / Sonuç |
|---|---|
| `MarketMmsSpike01` Windows Servisi | `Get-Service -Name "MarketMmsSpike01"` → **`Running` / `Automatic`** (dokunulmadı) |
| 4 Korunan Untracked Dosya | `.vscode/settings.json`, `run_windows_client.bat`, `start_master_hub.bat`, `stop_master_hub.bat` — **stage edilmedi, silinmedi, değiştirilmedi** |
| Veritabanları, Tokenlar, Pepper, Sertifikalar, Signing Key, Safety Snapshots, Backups | Hiçbirine dokunulmadı; `android/key.properties` yok (`KEY_PROPS_EXISTS=False`); hiçbir credential/keystore/sertifika üretilmedi |

---

## 11. Git Commit Bilgisi

- **Branch:** `main`
- **Başlangıç (Taban) Commit:** `a02a3c66edb3d580c047a02557057acf7d6fa573`
- **Planlanan Commit Mesajı:** `feat(market-mms): finalize phase 1.1 remediation`
- *(Not: Nihai commit hash'i, bu rapor ve hassas dosya taraması tamamlandıktan hemen sonra `git commit` komutuyla üretilmekte ve teslimat özetiyle `origin/main` eşleşmesi olarak sunulmaktadır.)*

---

## 12. Git Push Bilgisi

- **Hedef Remote:** `origin` (`https://github.com/halilkrkn/market-pos.git`) → `refs/heads/main`
- **Güvenlik Politikası:** Push öncesi `origin/main == a02a3c66edb3d580c047a02557057acf7d6fa573` doğrulanmış, yalnızca Phase 1.1 dosyaları tek tek stage edilmiş, hassas dosya taraması ve 4 korunan dosyanın dışlandığı teyit edilerek `git push origin main` (force/rebase/merge/reset/clean olmadan) çalıştırılmaktadır. Nihai push ve remote hash doğrulama sonucu teslimat özetinde raporlanmaktadır.

---

## 13. Açık Riskler

1. **`google_sign_in` Arka Plan Headless Kısıtı:** Uygulama tamamen kapalıyken (`JOB_ID = 70201`) Google Drive upload yapılabileceği garanti değildir (yerel `.mmsbak` üretilir; Drive upload ön plan oturumunda `DriveUploadLedger` ile tamamlanır).
2. **GMS (Google Play Services) Bağımlılığı:** GMS olmayan (HMS-only / AOSP) cihazlar Seçenek A ile Drive OAuth çalıştıramaz.
3. **OAuth "Testing" Modu 7 Gün Kısıtı:** Consent screen `"In production"` durumuna alınmazsa 7 günde bir yetki düşer.
4. **Saha / Fiziksel Kabul Testleri (`PAT-01…PAT-18`):** Tamamı **`BLOCKED / NOT RUN`** durumundadır.
5. **Test 15 Zaman Aşımı Payı:** `s5a4_backup_restore_test.dart` Test 15 (`25–32 sn`) Dart'ın 30 sn varsayılan zaman aşımına yakındır (yeniden koşumda `25.35 sn` ile geçti).
6. **Güncel `mms_backend.exe` AOT Derlemesi ve `L-3`:** `a02a3c6` sonrası üretim `build_aot.ps1` derlemesi ve düşük öncelikli `L-3` DPAPI teknik borcu açıktır.

---

## 14. Phase 2 Ön Koşulları

Phase 2'ye (Android `google_sign_in` implementasyonu + Release APK üretimi) geçmeden önce:
1. **`B1`:** Owner tarafından depo dışında `market_mms_upload.jks` ve `android/key.properties` oluşturulması (**SHA-1** ve **SHA-256** kaydedilmesi).
2. **`C1/C2`:** Google Cloud projesinde Drive API + Consent Screen (`drive.file`, `"In production"`) + Desktop, Android ve Web (`serverClientId`) OAuth Client ID'lerinin hazırlanması.
3. **`K-05`:** `drive_live_sync_secret_v1` dağıtım modelinin (Hub TLS-pinned vs Owner manuel/QR) karara bağlanması.
4. **`ADR-022` Phase 2 Implementasyonu:** `google_sign_in` bağımlılığının eklenmesi, `AndroidGoogleSignInTokenProvider` + UI + birim testlerinin yazılması.
5. **`B2` + `D1–D4` + `PAT-01…18`:** Üretim Hub TLS sertifikaları, `MarketMmsSpike01` temizliği ve gerçek donanımda adım adım fiziksel kabul testlerinin yürütülmesi.

---

## 15. Genel Teslimat Durumu

- **`PHASE 1.1 COMPLETE — SOFTWARE VALIDATION PASSED`**
- *Pilot kabulü veya production readiness iddiası taşımaz; tüm fiziksel testler (`PAT-01…PAT-18`) ve Phase 2 implementasyonu sonraki aşamalardır.*
