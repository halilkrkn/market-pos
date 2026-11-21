# MARKET MMS — RELEASE 1.0 / PHASE 1.1 TEKNİK VE DOKÜMANTASYON DÜZELTME RAPORU

- **Tarih:** 22 Kasım 2026
- **Oturum:** **PHASE 1.1 — RELEASE 1.0 REMEDIATION & FINALIZATION**
- **Git Bazı:** Branch `main` · Taban commit `a02a3c66edb3d580c047a02557057acf7d6fa573` · Hedef commit mesajı: `feat(market-mms): finalize phase 1.1 remediation` (commit ve `origin/main` push işlemleri Owner yetkisiyle son doğrulama sonrası yürütülür)
- **Korunan Yerel Öğeler:** `.vscode/settings.json`, `run_windows_client.bat`, `start_master_hub.bat`, `stop_master_hub.bat`, `docs/RELEASE_1_0_PHASE_1_VERIFICATION_REPORT.md`, `MarketMmsSpike01` (`Running / Automatic`), tüm DB/token/pepper/sertifika dosyaları (`VERIFIED`)
- **Genel Durum:** **`PHASE 1.1 COMPLETE — SOFTWARE VALIDATION PASSED`** *(Fiziksel kabul testleri `PAT-01…PAT-18` henüz çalıştırılmamıştır: `BLOCKED / NOT RUN`; ayrıntılı nihai özet: [`RELEASE_1_0_PHASE_1_1_FINALIZATION_REPORT.md`](./RELEASE_1_0_PHASE_1_1_FINALIZATION_REPORT.md))*

---

## 1. Yapılan Değişiklikler

1. **Düzeltme A — Android Sürüm Yönetimi (`COMPLETED` · `VERIFIED`):**
   - `pubspec.yaml` sürümü `0.1.0+1` → `1.0.0+1` olarak güncellendi.
   - `scripts/package_android_release.ps1` içindeki sabit `[string]$Version = "1.0.0"` kaldırıldı; betik artık sürümü doğrudan `pubspec.yaml` (`version: X.Y.Z+N`) üzerinden okuyor, `flutter build apk/appbundle --release` çağrısına `--build-name` ve `--build-number` bayraklarını açıkça geçiriyor, derleme sonrası `android/local.properties` (`flutter.versionName` / `flutter.versionCode`) eşleşmesini doğruluyor, paket adını dinamik olarak `market_mms_v<X.Y.Z>-b<N>.apk` (veya `.aab`) biçiminde üretiyor ve isteğe bağlı `-Version` parametresini uyuşmazlık durumunda fail-closed duran bir koruma (guard) olarak işletiyor.
   - `docs/release/ANDROID_RELEASE.md` ve `docs/PRODUCTION_DEPLOYMENT_RUNBOOK.md` sürümleme ve paketleme akışı yeni davranışla güncellendi; `test/features/production/android_release_hardening_test.dart` içine otomatik regresyon testi eklendi.
2. **Düzeltme B — Android NDK `28.2.13676358` Kurulumu ve Uyumu (`COMPLETED` · `VERIFIED`):**
   - Owner kararıyla yerel Android SDK (`C:\Users\halil\AppData\Local\Android\sdk`) içine `android.exe sdk install ndk/28.2.13676358` ile `android-ndk-r28c` (`28.2.13676358`) kuruldu ve `source.properties` (`Pkg.Revision = 28.2.13676358`) doğrulandı.
   - Ardından `android/app/build.gradle.kts:29` `ndkVersion = flutter.ndkVersion` (`28.2.13676358`) olarak güncellendi ve `test/features/production/android_release_hardening_test.dart` içine regresyon kontrolü eklendi.
   - `:app:printNdkVersion` (`NdkVersion: 28.2.13676358`), `:app:compileDebugKotlin --no-daemon` (`BUILD SUCCESSFUL in 55s`), `flutter build apk --debug` (`app-debug.apk`, `179.860.276` bayt, `aapt2 dump badging`: `versionCode='1' versionName='1.0.0'`) ve `key.properties` yokken `:app:assembleRelease` fail-closed reddi (`exit 1`) doğrulandı.
3. **Düzeltme C — `PAT-16` Kanonik Job ID (`COMPLETED` · `VERIFIED`):**
   - `MmsBackgroundBackupJobService.kt` içindeki `JOB_ID = 70201` değiştirilmedi.
   - `PHYSICAL_ACCEPTANCE_TEST_PLAN.md:293` komutu `202611` → `70201` olarak düzeltildi; `docs/decisions/020-android-background-backup-workmanager.md` ve `docs/decisions/README.md` içine `JOB_ID = 70201` eklendi; kod–doküman eşleşmesi otomatik testle kilitlendi.
4. **Düzeltme D — `PAT-16` / `PAT-17` Tanım Tutarlılığı (`COMPLETED` · `VERIFIED`):**
   - `PHYSICAL_ACCEPTANCE_TEST_PLAN.md` kanonik esas alındı (`PAT-01…PAT-18` korunup yeni numara açılmadı); önerilen yürütme sırasına `PAT-16`, `PAT-17`, `PAT-18` eklendi ve `PAT-03` içindeki eski `P-BLOCK-1..3` notu güncel uygulama durumuna göre düzeltildi.
   - `docs/RELEASE_1_0_FINAL_DELIVERY_REPORT.md` içindeki yanlış `PAT-15`/`PAT-16`/`PAT-17` eşleştirmeleri düzeltildi. Windows FFI canlı doğrulaması (`HUB-T04c`) ve crash-safe re-pairing kesinti kurtarmasının (`APP-T16`) saha izleme biçimi Owner kararına açık bırakıldı.
5. **Düzeltme E — `OWNER_ACTION_CHECKLIST.md` Uzlaştırması (`COMPLETED` · `VERIFIED`):**
   - *(Gerçek dosya yolu: repo kökü `OWNER_ACTION_CHECKLIST.md`; `docs/OWNER_ACTION_CHECKLIST.md` dosyası depoda yoktur.)*
   - Özet tablo ile `A1`, `A2`, `A4`, `A5`, `A6`, `B1`, `B2`, `C1`, `C2`, `D1–D4`, `E1–E2` bölümleri arasındaki tüm çelişkiler giderildi; `ADR-020` (`JOB_ID = 70201`), `ADR-021`, yeni `[PROPOSED]` `ADR-022`, commit `a02a3c6` ve `PAT-01…PAT-18` (`BLOCKED`) durumu tutarlı hâle getirildi.
6. **Düzeltme F — `ADR-021` Google Drive Klasör Adı (`COMPLETED` · `VERIFIED`):**
   - Kod sabiti `GoogleDriveLiveEnvelopeTransport.folderName = 'MARKET MMS LiveSync'` (`packages/mms_client_storage/lib/src/sync/hybrid_drive_live_sync.dart:878`) doğrulandı.
   - `docs/decisions/021-hybrid-hub-google-drive-live-sync.md` §S5 içindeki `MMS LiveSync/` ifadesi `MARKET MMS LiveSync` olarak düzeltildi; kod ve protokol değiştirilmedi.
7. **Düzeltme G — Windows Hub TLS Release Dokümantasyonu (`COMPLETED` · `VERIFIED`):**
   - `docs/release/WINDOWS_HUB_RELEASE.md` içine §1.1 eklendi: `advertise_host` çift doğrulaması (SAN + aktif yerel arayüz), zorunlu `IP:127.0.0.1` loopback SAN şartı (`exit 78` / `ERR_SERVER_CERT_MISSING_LOOPBACK_SAN`), LAN IPv4/hostname SAN gereksinimleri ve Hub startup fail (`exit 78`) vs pairing `HTTP 503` hata kodları tablosu (`bin/server.dart`, `hub_config.dart`, `hub_lan_address_resolver.dart` ile birebir doğrulandı).
   - `test_spikes/spike_01_backend/config/hub_config.example.json` şemayla uyumlu biçimde `"advertise_host": null` alanıyla güncellendi (`rel01_hub_config_test.dart` ve `s5a1_service_lifecycle_test.dart` ile doğrulandı).
8. **ADR-022 — Android Google Drive OAuth Tasarım Belgesi (`DESIGN APPROVED — PENDING PHASE 2 IMPLEMENTATION`):**
   - Owner kararıyla **Seçenek A (`google_sign_in`)** ve **Android Drive entegrasyonunun pilot kapsamına dahil edilmesi** kesinleştirilerek `docs/decisions/022-android-google-drive-oauth-design.md` 14 teknik boyutla güncellendi (`docs/decisions/README.md`: `DESIGN_APPROVED`). Phase 1.1 kapsamında OAuth kodu yazılmadı, `google_sign_in` eklenmedi ve Google Cloud / credential işlemi yapılmadı.

---

## 2. Değiştirilen ve Oluşturulan Dosyalar (Phase 1.1 Finalization Kapsamı)

| # | Dosya Yolu | Düzeltme / Amaç | Statü |
|---|---|---|---|
| 1 | `pubspec.yaml` | Sürüm `0.1.0+1` → `1.0.0+1` | `COMPLETED` · `VERIFIED` |
| 2 | `android/app/build.gradle.kts` | `ndkVersion = flutter.ndkVersion` (`28.2.13676358`) geçişi | `COMPLETED` · `VERIFIED` |
| 3 | `scripts/package_android_release.ps1` | Dinamik `pubspec.yaml` sürüm okuma, `--build-name`/`--build-number`, `market_mms_v<ver>-b<num>.<ext>`, `-Version` mismatch guard, UTF-8 BOM | `COMPLETED` · `VERIFIED` |
| 4 | `docs/release/ANDROID_RELEASE.md` | §1 doğrulama kayıtları, §3 sürüm yönetimi, paketleme betiği ve NDK `28.2.13676358` güncellemesi | `COMPLETED` · `VERIFIED` |
| 5 | `docs/PRODUCTION_DEPLOYMENT_RUNBOOK.md` | Phase 1.1 özeti, `ADR-020` (`JOB_ID = 70201`), `ADR-022` Seçenek A, `P-BLOCK-1..3` ve `PAT-01…PAT-18` uyumu | `COMPLETED` · `VERIFIED` |
| 6 | `PHYSICAL_ACCEPTANCE_TEST_PLAN.md` | `PAT-16` Job ID `202611` → `70201`, yürütme sırasına `PAT-16..18`, `PAT-03` güncel `P-BLOCK-1..3` notu, `PAT-13` Android ön koşul notu | `COMPLETED` · `VERIFIED` |
| 7 | `docs/RELEASE_1_0_FINAL_DELIVERY_REPORT.md` | `PAT-15`/`PAT-16`/`PAT-17` eşleştirmeleri ve Phase 1.1 Finalization referans notu | `COMPLETED` · `VERIFIED` |
| 8 | `OWNER_ACTION_CHECKLIST.md` | Özet tablo, `A1`, `A2`, `A4–A6`, `B1–B2`, `C1–C2` (Web `serverClientId` + SHA-1/SHA-256), NDK `28.2.13676358` ve `PAT-01..18` tam uzlaştırması | `COMPLETED` · `VERIFIED` |
| 9 | `docs/decisions/020-android-background-backup-workmanager.md` | Kanonik `JOB_ID = 70201` referansı | `COMPLETED` · `VERIFIED` |
| 10 | `docs/decisions/021-hybrid-hub-google-drive-live-sync.md` | Klasör adı `MMS LiveSync/` → `MARKET MMS LiveSync` | `COMPLETED` · `VERIFIED` |
| 11 | `docs/decisions/README.md` | `ADR-020` (`JOB_ID = 70201`), `ADR-021` (`MARKET MMS LiveSync`) ve `ADR-022` (`DESIGN_APPROVED` — Seçenek A) kaydı | `COMPLETED` · `VERIFIED` |
| 12 | `docs/decisions/022-android-google-drive-oauth-design.md` | Android Google Drive OAuth tasarımı (`DESIGN APPROVED — PENDING PHASE 2 IMPLEMENTATION`, Seçenek A `google_sign_in`, 14 teknik konu) | `COMPLETED` · `DESIGN_APPROVED` |
| 13 | `docs/release/WINDOWS_HUB_RELEASE.md` | `advertise_host`, zorunlu `IP:127.0.0.1` loopback SAN (`exit 78`), LAN SAN ve pairing `503` tablosu | `COMPLETED` · `VERIFIED` |
| 14 | `test_spikes/spike_01_backend/config/hub_config.example.json` | Şema uyumlu `"advertise_host": null` alanı | `COMPLETED` · `VERIFIED` |
| 15 | `test/features/production/android_release_hardening_test.dart` | Phase 1.1 regresyon testleri (sürüm/NDK `flutter.ndkVersion`/script/BOM/AST/guard + `PAT-16` `JOB_ID = 70201`) | `COMPLETED` · `VERIFIED` |
| 16 | `docs/RELEASE_1_0_PHASE_1_VERIFICATION_REPORT.md` | Release 1.0 salt-okunur doğrulama denetim raporu | `COMPLETED` |
| 17 | `docs/RELEASE_1_0_PHASE_1_1_REMEDIATION_REPORT.md` | Phase 1.1 düzeltme ve doğrulama raporu | `COMPLETED` |
| 18 | `docs/RELEASE_1_0_PHASE_1_1_FINALIZATION_REPORT.md` | Phase 1.1 nihai teslimat raporu (15 zorunlu bölüm) | `COMPLETED` |

---

## 3. Önceki Raporlama Notu
*(Yukarıdaki tablo hem modified hem newly created tüm Phase 1.1 dosyalarını kapsar.)*

---

## 4. Her Owner Kararının Uygulanma Durumu

| # | Owner Kararı | Uygulama Özeti | Statü |
|---|---|---|---|
| 1 | Android uygulama sürümü `1.0.0+1` olacak | `pubspec.yaml:5` → `1.0.0+1`; `flutter build apk --debug --config-only` ile `android/local.properties` `flutter.versionName=1.0.0` ve `flutter.versionCode=1` doğrulandı | `COMPLETED` · `VERIFIED` |
| 2 | APK dosya adı gerçek sürüm bilgisinden üretilecek | `scripts/package_android_release.ps1` `pubspec.yaml`'dan okuyup `--build-name`/`--build-number` geçirerek `market_mms_v<buildName>-b<buildNumber>.apk` üretiyor; `-Version` mismatch fail-closed test edildi | `COMPLETED` · `VERIFIED` |
| 3 | NDK `28.2.13676358` kurulacak ve uyumlu hâle getirilecek | Android SDK içine `ndk/28.2.13676358` kuruldu (`source.properties` `28.2.13676358`); `android/app/build.gradle.kts` `ndkVersion = flutter.ndkVersion` güncellendi; `:app:printNdkVersion` + `:app:compileDebugKotlin` + `flutter build apk --debug` geçti | `COMPLETED` · `VERIFIED` |
| 4 | `PAT-16` Job ID için kodda tanımlı `70201` esas alınacak | `MmsBackgroundBackupJobService.kt` korundu; `PHYSICAL_ACCEPTANCE_TEST_PLAN.md:293` (`70201`) ve `ADR-020` güncellendi; `202611` tamamen kaldırıldı | `COMPLETED` · `VERIFIED` |
| 5 | `PAT-16` / `PAT-17` tanımları kanonik test planıyla tutarlı hâle getirilecek | `RELEASE_1_0_FINAL_DELIVERY_REPORT.md`, `OWNER_ACTION_CHECKLIST.md` ve `PHYSICAL_ACCEPTANCE_TEST_PLAN.md` uzlaştırıldı (`PAT-01..18` korundu) | `COMPLETED` · `VERIFIED` |
| 6 | Owner Action Checklist güncellenecek | Kök `OWNER_ACTION_CHECKLIST.md` baştan sona güncellendi (`A1–E2` tutarlı, fiziksel testler `BLOCKED` korundu) | `COMPLETED` · `VERIFIED` |
| 7 | `ADR-021` Google Drive klasör adı kodla tutarlı hâle getirilecek | `MARKET MMS LiveSync` olarak düzeltildi; kod/protokol değiştirilmedi | `COMPLETED` · `VERIFIED` |
| 8 | Windows Hub TLS dokümantasyonu tamamlanacak | `WINDOWS_HUB_RELEASE.md` §1.1 + `hub_config.example.json` (`"advertise_host": null`) gerçek kodla birebir güncellendi | `COMPLETED` · `VERIFIED` |
| 9 | Android Google Drive OAuth ayrı tasarım/ADR olacak (`Seçenek A: google_sign_in`, pilot kapsamına dahil), bu oturumda uygulanmayacak | `ADR-022` (`DESIGN APPROVED — PENDING PHASE 2 IMPLEMENTATION`) 14 teknik boyutla kesinleştirildi; kod, `google_sign_in` bağımlılığı veya OAuth Client ID üretilmedi | `COMPLETED` · `DESIGN_APPROVED` |

---

## 5. Android Version Kontrolü (`VERIFIED`)

- **`pubspec.yaml:5`:** `version: 1.0.0+1` (`AppConstants.appVersion == '1.0.0'` ile eşleşiyor).
- **`android/app/build.gradle.kts:37,40-41`:** `applicationId = "com.marketmms.market_pos"` (değiştirilmedi), `versionCode = flutter.versionCode`, `versionName = flutter.versionName` (signing yapılandırmasına dokunulmadı).
- **Flutter Propagasyon Doğrulaması:** `flutter build apk --debug --config-only` (`exit 0`) çalıştırıldığında `android/local.properties` dosyasının otomatik olarak `flutter.versionName=1.0.0` ve `flutter.versionCode=1` değerlerine güncellendiği doğrudan gözlendi.
- **Paketleme Betiği (`scripts/package_android_release.ps1`):**
  - UTF-8 BOM (`EF BB BF`) doğrulandı (`rel01_hub_config_test.dart` uyumlu).
  - Windows PowerShell 5.1 AST ayrıştırması: `0` sözdizimi hatası.
  - `-Version 9.9.9 -SkipFlutterBuild` çağrısı `exit != 0` ile fail-closed reddedildi (uyuşmazlık koruması çalışıyor).
  - Release APK üretimi Phase 2 kapsamında olup bu oturumda çalıştırılmadı (`NOT_VERIFIED` — `B1` imza anahtarı gerektirir).

---

## 6. NDK Uyumluluk Kontrolü ve Kurulumu (`COMPLETED` · `VERIFIED`)

### Gerçek Bağımlılık ve SDK Bulguları
- **Aktif Android eklentileri (`.flutter-plugins-dependencies`):**
  1. `integration_test` (`dev_dependency`, Flutter SDK): `android/build.gradle.kts` içinde `ndkVersion = flutter.ndkVersion` kullanır; kendi C/C++ kaynağı yoktur.
  2. `mobile_scanner` (`7.5.0`, ana bağımlılık): `android/build.gradle.kts` içinde `ndkVersion` belirtmez ve C/C++ kaynağı yoktur (saf Kotlin/Java + CameraX + MLKit AAR).
  3. `sqlite3` (`3.5.2`): Dart Native Assets (`hook/build.dart`) üzerinden önceden derlenmiş (precompiled) `libsqlite3.so` kullanır.
  4. Uygulamanın kendi Android kaynakları (`MainActivity.kt`, `MmsSecureStorageChannelHandler.kt`, `MmsBackgroundBackupJobService.kt`): saf Kotlin, sıfır JNI/CMake/NDK kodu.
- **Flutter SDK (`3.47.9`) Varsayılanı:** `FlutterExtension.kt:42` → `val ndkVersion: String = "28.2.13676358"`.
- **Yerel Android SDK Kurulu NDK'lar (`C:\Users\halil\AppData\Local\Android\sdk\ndk`):**
  - `25.1.8937393`
  - `26.1.10909125`
  - `27.0.11718014`
  - **`28.2.13676358` (`android-ndk-r28c`): KURULDU VE DOĞRULANDI** (`android.exe sdk install ndk/28.2.13676358`, `exit 0`, `source.properties` `Pkg.Revision = 28.2.13676358`).
- **Sonuç:** `android/app/build.gradle.kts:29` `ndkVersion = flutter.ndkVersion` olarak güncellendi. `:app:printNdkVersion :app:compileDebugKotlin --no-daemon` çıktısında **`NdkVersion: 28.2.13676358`** ve **`BUILD SUCCESSFUL in 55s`** (`exit 0`) elde edildi; önceki NDK sürüm uyuşmazlık uyarısı kalıcı olarak giderildi. `flutter build apk --debug` **`164,6s`** içinde başarıyla `app-debug.apk` (`179.860.276` bayt) üretti.

---

## 7. `PAT-16` / `PAT-17` Tutarlılığı (`COMPLETED` · `VERIFIED`)

| Test ID | Kanonik Tanım (`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`) | Güncellenen Referanslar | Saha Statüsü |
|---|---|---|---|
| **`PAT-15`** | Gerçek cihazda zamanlanmış yedek (uygulama açık / kapalı) | `RELEASE_1_0_FINAL_DELIVERY_REPORT.md`, `OWNER_ACTION_CHECKLIST.md` | `BLOCKED` |
| **`PAT-16`** | Android Uygulama Kapalıyken Arka Plan Şifreli Yedekleme (`JobScheduler`, **`JOB_ID = 70201`**) ve Yeniden Başlatma Kalıcılığı | `PHYSICAL_ACCEPTANCE_TEST_PLAN.md` (`202611` → `70201`), `RELEASE_1_0_FINAL_DELIVERY_REPORT.md`, `OWNER_ACTION_CHECKLIST.md`, `ADR-020`, `android_release_hardening_test.dart` | `BLOCKED` |
| **`PAT-17`** | Google Drive Gerçek Hesap ile Yedek Listeleme, Kesintili İndirme ve Kontrollü Geri Yükleme | `RELEASE_1_0_FINAL_DELIVERY_REPORT.md`, `OWNER_ACTION_CHECKLIST.md`, `BACKUP_AND_RESTORE_GUIDE.md` | `BLOCKED` |
| **`PAT-18`** | Hub Öncelikli Hibrit + Google Drive Canlı Senkronizasyon ve Hub Geri Dönüş Uzlaştırması | Tüm belgeler tutarlı | `BLOCKED` |

- **Owner Kararı Gerektiren Açık Nokta (`REQUIRES_OWNER_APPROVAL`):** Eski raporda yanlışlıkla `PAT-16`/`PAT-17` içine yazılmış olan **Windows x64 FFI canlı adaptör doğrulaması (`HUB-T04c`)** ve **crash-safe re-pairing kesinti kurtarması (`APP-T16`)** için mevcut `PAT-03` altına alt adım mı ekleneceği yoksa ayrı kontrol maddesi mi açılacağı Owner kararına bırakıldı (yeni PAT numarası açılmadı).

---

## 8. Owner Checklist Durumu (`COMPLETED` · `VERIFIED`)

- Kök dizindeki `OWNER_ACTION_CHECKLIST.md` güncellendi:
  - `A1`: `ADR-015…ADR-021` gerçek uygulama durumları ve yeni `[PROPOSED]` `ADR-022` eklendi; eski `P-BLOCK-1..3` düzeltme onayı bekleme ve `ADR-020 DEFERRED_POST_PILOT` ifadeleri kaldırıldı.
  - `A2`: Eski "~200 dosya" ifadesi yerine `a02a3c6` (`origin/main`) commit durumu ve unstaged Phase 1.1 kapsamı yazıldı.
  - `A4`, `A5`, `A6`: `P-BLOCK-1..3`, `JOB_ID = 70201`, `MARKET MMS LiveSync`, `ERR_DRIVE_PLATFORM_UNSUPPORTED` (`ADR-022`) ve `drive_live_sync_secret_v1` dağıtımı netleştirildi.
  - `B1`, `B2`, `C1`, `C2`, `D1–D4`, `E1–E2`: Mevcut güvenlik/ön koşul durumları korunarak `1.0.0+1`, `IP:127.0.0.1` loopback SAN (`exit 78`), `advertise_host` ve `PAT-01…PAT-18` (`BLOCKED`) ile senkronize edildi.

---

## 9. `ADR-021` Düzeltmesi (`COMPLETED` · `VERIFIED`)

- Kod doğrulaması: `packages/mms_client_storage/lib/src/sync/hybrid_drive_live_sync.dart:878` → `static const String folderName = 'MARKET MMS LiveSync';`.
- `docs/decisions/021-hybrid-hub-google-drive-live-sync.md:41` → `` `MARKET MMS LiveSync` `` olarak güncellendi.
- Kod ve senkronizasyon protokolüne dokunulmadı.

---

## 10. Windows Hub TLS Dokümantasyonu (`COMPLETED` · `VERIFIED`)

- `docs/release/WINDOWS_HUB_RELEASE.md` §1 ve §1.1 gerçek kod (`bin/server.dart:762-872, 4047-4075`, `lib/config/hub_config.dart:241-259`, `lib/network/hub_lan_address_resolver.dart:454-583`) ile birebir hizalandı:
  - Zorunlu `IP:127.0.0.1` SAN eksikliğinde Hub açılışında fail-fast **`exit 78`** (`ERR_SERVER_CERT_MISSING_LOOPBACK_SAN`).
  - `server.crt` için LAN IPv4 + isteğe bağlı hostname SAN gereksinimi (`subjectAltName=IP:127.0.0.1,IP:<HUB-LAN-IP>,DNS:localhost,DNS:<HOSTNAME>`).
  - `advertise_host` çift doğrulaması (`server.crt` SAN + aktif yerel NIC) ve otomatik Tier 1 / Tier 2 çözümleme kuralları.
  - LAN SAN / `advertise_host` / CA eksikliğinde Hub yerel POS'u korurken `/api/v1/pairing/session` ucunun **`HTTP 503`** (`ERR_CA_CERT_UNAVAILABLE`, `ERR_ADVERTISE_HOST_SAN_MISMATCH`, `ERR_ADVERTISE_HOST_NOT_LOCAL`, `ERR_HUB_LAN_IP_UNAVAILABLE`, `ERR_HUB_LAN_IP_AMBIGUOUS`) dönmesi.
- `test_spikes/spike_01_backend/config/hub_config.example.json`: `"advertise_host": null` eklendi; TLS güvenliği zayıflatılmadı ve mevcut config testleri (`rel01_hub_config_test.dart`, `s5a1_service_lifecycle_test.dart`) geçti.

---

## 11. `ADR-022` Android OAuth Tasarım Özeti (`DESIGN APPROVED — PENDING PHASE 2 IMPLEMENTATION`)

- Dosya: `docs/decisions/022-android-google-drive-oauth-design.md` (**Durum: `DESIGN APPROVED — PENDING PHASE 2 IMPLEMENTATION`**, Phase 1.1'de kodlanmadı).
- Owner kararı: **Seçenek A — `google_sign_in`** ve **Android Drive entegrasyonunun pilot kapsamına dahil edilmesi** kesinleştirilmiştir (implementasyon Phase 2 kapsamındadır).
- Özet teknik bulgular:
  - `google_sign_in` v7+, kimlik doğrulama (`authenticate()`, Android Credential Manager) ile scope yetkilendirmesini (`account.authorizationClient.authorizeScopes([drive.file])` / `authorizationForScopes(...)`, Play Services `AuthorizationClient`) ayırır.
  - Android istemcisine ham `refresh_token` **teslim edilmez** (`access_token` ~1 saatliktir ve yalnızca RAM'de tutulur; `401` / `forceRefresh` durumunda `clearAuthorizationToken` + `authorizationForScopes` denenir, çözünürlük gerekirse `ERR_DRIVE_REAUTH_REQUIRED` fırlatılır).
  - `authorizeServer` (`serverAuthCode`) bulut backend gerektirdiğinden ve APK'da `client_secret` bulunamayacağından pilotta kullanılmaz.
  - `MmsBackgroundBackupJobService` (`JOB_ID = 70201`) yerel `.mmsbak` yedeklemesini Android Keystore üzerinden her koşulda sürdürür; uygulama tamamen kapalıyken headless `google_sign_in` Drive yüklemesi çözülmemiş sınır olarak belgelenmiştir (yerel yedek + ön planda `DriveUploadLedger` yüklemesi güvence altındadır).
  - Google Cloud'da aynı projede Desktop, Android (`com.marketmms.market_pos` + SHA-1) ve Web (`serverClientId`) OAuth Client ID'leri tanımlanmalı ve 7 gün token iptalinden kaçınmak için izin ekranı `"In production"` statüsüne alınmalıdır.
  - `drive_live_sync_secret_v1` dağıtım modeli (`K-05`) Phase 2 öncesi Owner seçimine açıktır.

---

## 12. Çalıştırılan Testler ve Gerçek Sonuçları (`VERIFIED`)

*(Tüm 4 paket, statik analizler ve Android NDK 28.2.13676358 / Debug APK / Release fail-closed derlemeleri Phase 1.1 Finalization düzenlemeleri sonrasında fiilen çalıştırıldı. Not: İlk tam koşumda `packages/mms_client_storage` içindeki `s5a4_backup_restore_test.dart` Test 15 [600.000 iterasyonlu PBKDF2] 30 sn varsayılan zaman aşımına takıldı [`7.48 sn + 25.14 sn`]; tekil test koşumunda [`27.37 sn`] ve ardından yeniden çalıştırılan tam 4 paketlik ardışık süitte [`7.835 ms + 17.515 ms = 25.35 sn`] sıfır hata ve sıfır atlamayla geçti.)*

| Paket / Kontrol | Komut | Önceki (Phase 1) | Phase 1.1 Final Sonucu | Başarısız / Atlanan | Süre | Statü |
|---|---|---:|---:|---:|---:|---|
| **`packages/mms_contracts`** | `dart test -r expanded` | 7 | **7 / 7** (`exit 0`) | 0 / 0 | `00:04.75` | `VERIFIED` |
| **`packages/mms_client_storage`** | `dart test -j 1` | 225 | **225 / 225** (`exit 0`) | 0 / 0 | `02:09.02` | `VERIFIED` |
| **`test_spikes/spike_01_backend`** | `dart test -j 1` | 245 | **245 / 245** (`exit 0`) | 0 / 0 | `03:11.18` | `VERIFIED` |
| **Kök `market_pos`** | `flutter test -j 1` | 295 | **297 / 297** (`exit 0`, `+2` Phase 1.1 testi + NDK kontrolü) | 0 / 0 | `03:05.23` | `VERIFIED` |
| **TOPLAM Dart/Flutter** | **4 Süit** | **772** | **774 / 774** | **0 / 0** | — | `VERIFIED` |
| **Android NDK & Kotlin Derleme** | `android\gradlew.bat :app:printNdkVersion :app:compileDebugKotlin --no-daemon` | `27.0.11718014` | **`NdkVersion: 28.2.13676358` · `BUILD SUCCESSFUL`** (`exit 0`) | — | `55s` | `VERIFIED` |
| **Android Debug APK & Metadata** | `flutter build apk --debug` + `aapt2 dump badging` | — | **`app-debug.apk` (`179.860.276` bayt)** · `versionName=1.0.0`, `versionCode=1`, `minSdkVersion=24`, `targetSdkVersion=36` | — | `164,6s` | `VERIFIED` |
| **Android Release Fail-Closed** | `android\gradlew.bat :app:assembleRelease --no-daemon` (`key.properties` yok) | — | **`BUILD FAILED`** (`exit 1` — *"Release imzalama yapılandırılmadı"*, beklenen) | — | `46s` | `VERIFIED` |
| **PowerShell 5.1 AST & Guard** | `Parser::ParseFile` + `-Version 9.9.9` + BOM | — | `PS_BOM=True`, `PS_AST_ERRORS=0`, guard `exit 1` | — | — | `VERIFIED` |
| **`integration_test/` & `PAT-01…18`** | Çalıştırılmadı (fiziksel cihaz/imza/sertifika/OAuth gerekir) | `BLOCKED` | `BLOCKED / NOT RUN` | — | — | `BLOCKED` |

---

## 13. Analyze Sonuçları (`VERIFIED`)

| Paket | Komut | Çıkış Kodu | Bulgu Özeti | Süre | Statü |
|---|---|---:|---|---|---|
| `packages/mms_contracts` | `dart analyze` | `0` | `No issues found!` | `00:03.34` | `VERIFIED` |
| `packages/mms_client_storage` | `dart analyze` | `0` | `16 issues found.` *(tamamı önceden var olan `sqlite3 dispose` `deprecated_member_use` `info` kayıtları; 0 hata, 0 uyarı)* | `00:04.95` | `VERIFIED` |
| `test_spikes/spike_01_backend` | `dart analyze` | `0` | `18 issues found.` *(tamamı önceden var olan `sqlite3 dispose` `deprecated_member_use` `info` kayıtları; 0 hata, 0 uyarı)* | `00:08.40` | `VERIFIED` |
| Kök `market_pos` | `flutter analyze` | `0` | `No issues found! (ran in 41.2s)` | `00:46.66` | `VERIFIED` |

---

## 14. Bilinen Teknik Borçlar

1. **Test 15 (`s5a4_backup_restore_test.dart`) 30 sn Zaman Aşımı Payının Dar Olması:** 600.000 iterasyonlu PBKDF2 yedek + şifreli koruyucu kopyalı restore tek testte `~25–32 sn` sürebildiği için sistem yüküne bağlı dar zaman payı taşır (bu oturumda tekrar koşumda `25.35 sn` ile geçti).
2. **AGP 9.x Built-In Kotlin Deprecation Uyarısı:** `android/gradle.properties` içindeki Flutter şablon bayrakları (`android.builtInKotlin=false`, `android.newDsl=false`) Gradle 10 öncesi deprecation uyarısı üretir; mevcut derlemeyi etkilemez (`NOT_VERIFIED` — gelecek bakım).
3. **`L-3` (`WindowsDpapiTokenStore.readSecret`):** Tekil anahtar DPAPI çözümleme hatasında `null` dönme davranışı (düşük öncelikli pilot sonrası borç).
4. **Önceden Bilinen `sqlite3 dispose` Info Kayıtları:** `mms_client_storage` (16) ve `spike_01_backend` (18) test dosyalarındaki `deprecated_member_use` `info` bildirimleri (`exit 0`, fonksiyonel etkisi yok).
5. **`ADR-019` (`SYNC-CAT` — %20 KDV Kısıtı):** Bilinçli olarak pilot sonrasına ertelenmiş durumda.
6. **Güncel Windows Hub AOT İkilisi (`mms_backend.exe`):** `a02a3c6` sonrası üretim `build_aot.ps1` yeniden derlemesi henüz yapılmadı (`NOT_VERIFIED`).
7. **Tarihsel Belgelerdeki Eski Commit/Durum Notları:** `docs/LIVE_PROJECT_STATUS.md`, `docs/PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md` ve `docs/PILOT_PROTOCOL_BLOCKERS_FINAL_REVIEW_REPORT.md` içindeki bazı tarihsel notlar Phase 1.1 kapsamı dışında bırakıldı.

---

## 15. Owner Kararları ve Phase 2 Ön Koşulları

1. **Kesinleştirilmiş Owner Kararları (Phase 1.1):** Android OAuth = **Seçenek A (`google_sign_in`)**, Android Drive = **Pilot kapsamına dahil**, NDK = **`28.2.13676358`**, Sürüm = **`1.0.0+1`**, PAT-16 Job ID = **`70201`**, ADR-021 Drive klasörü = **`MARKET MMS LiveSync`**, Phase 1.1 Git commit/push yetkisi verildi.
2. **Kalan Açık Kararlar (Phase 2 / Pilot Öncesi):**
   - `drive_live_sync_secret_v1` dağıtım modeli (`ADR-022` `K-05`: Hub üzerinden TLS-pinned teslim vs Owner manuel/QR kurulumu).
   - `HUB-T04c` (Win x64 FFI) ve `APP-T16` (re-pairing kesinti kurtarma) saha izleme biçimi (`PAT-03` alt adımı vs ayrı adım).
   - Diğer pilot kararları (`OWNER_ACTION_CHECKLIST.md`: `A7` QR görsel paketi, `A8` kod imzalama / merkezi tanı, `D1–D4` `MarketMmsSpike01` ve test DB/token temizliği).

---

## 16. Phase 2'ye Geçiş Engelleri ve Ön Koşulları

Phase 1.1 yazılım doğrulaması başarıyla tamamlanmıştır. **Phase 2** (Android Google Drive OAuth implementasyonu + imzalı Release APK üretimi) için aşağıdaki ön koşullar beklenmektedir:

| # | Ön Koşul / Engel | Tür | Mevcut Durum | Sorumlu |
|---|---|---|---|---|
| 1 | **`B1` — Android Üretim İmza Anahtarı (`android/key.properties` & `.jks`)** | **Sert Teknik Engel (`BLOCKED`)** | `key.properties` olmadan `:app:assembleRelease` fail-closed durur | Owner depo dışında `market_mms_upload.jks` + `android/key.properties` oluşturmalı; SHA-1/SHA-256 kaydedilmeli |
| 2 | **`ADR-022` Phase 2 Implementasyonu (`google_sign_in`)** | **Phase 2 Geliştirme İşi** | Tasarım onaylı (`DESIGN APPROVED`); `google_sign_in` eklenmedi ve Android OAuth kodlanmadı | Phase 2 geliştirme oturumu |
| 3 | **`C1/C2` — Google Cloud Projesi ve OAuth Client ID'leri** | **Dış Ortam Ön Koşulu (`BLOCKED`)** | Desktop, Android (`com.marketmms.market_pos` + SHA-1) ve Web (`serverClientId`) Client ID'leri + `"In production"` yayınlama yapılmadı | Owner |
| 4 | **`B2` Hub TLS Sertifikaları + `D1–D4` Temizlik + `PAT-01…18`** | **Saha Ön Koşulu (`BLOCKED`)** | `MarketMmsSpike01` korunuyor; hiçbir fiziksel test çalıştırılmadı | Owner |

---

**Nihai Durum:** **`PHASE 1.1 COMPLETE — SOFTWARE VALIDATION PASSED`** *(Ayrıntılı 15 bölümlük nihai teslimat raporu: [`RELEASE_1_0_PHASE_1_1_FINALIZATION_REPORT.md`](./RELEASE_1_0_PHASE_1_1_FINALIZATION_REPORT.md).)*
