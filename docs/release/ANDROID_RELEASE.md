# Android Üretim Sürümü (Release) Kılavuzu — MARKET MMS

*Son güncelleme: 22 Kasım 2026 (Phase 1.1 Finalization — NDK `28.2.13676358` & Sürümleme Doğrulaması)*

## 1. Güvenlik Varsayılanları

| Ayar | Debug / Profile | Release |
|---|---|---|
| `usesCleartextTraffic` (şifresiz HTTP) | `true` (yerel geliştirme Hub'ı) | **`false`** — Hub ile yalnızca HTTPS/TLS |
| İmzalama | Debug anahtarı | **`android/key.properties`** zorunlu; yoksa derleme durur |
| Derlemeye gömülü cihaz token'ı | Yok | Yok (token yalnızca eşleştirme sonrası Android Keystore'dan okunur) |
| Android otomatik yedekleme (Google bulut / cihaz aktarımı) | **Kapalı** | **Kapalı** — `allowBackup=false`, `fullBackupContent=false`, `res/xml/data_extraction_rules.xml` (API 31+, tüm alanlar hariç). Şifresiz yerel DB ve `device_id` cihaz dışına çıkmaz (ADR-016 Ek A.4) |

Doğrulama (22.11.2026, Phase 1.1 Finalization, bu depoda çalıştırıldı):
- `:app:printNdkVersion :app:compileDebugKotlin --no-daemon` → `NdkVersion: 28.2.13676358`, `BUILD SUCCESSFUL in 55s` (`exit 0`).
- `flutter build apk --debug` → `app-debug.apk` (`179.860.276` bayt, `exit 0`); `android/local.properties` içinde `flutter.versionName=1.0.0`, `flutter.versionCode=1`; `aapt2 dump badging` üzerinde `package: name='com.marketmms.market_pos' versionCode='1' versionName='1.0.0'`.
- `:app:assembleRelease --no-daemon` (`android/key.properties` yok) → `BUILD FAILED in 46s`: *"Release imzalama yapılandırılmadı…"* (beklenen, fail-closed; debug anahtarıyla release **üretilmedi**).
- `scripts/package_android_release.ps1` → UTF-8 BOM (`EF BB BF`), PowerShell 5.1 AST `0` hata, `-Version 9.9.9 -SkipFlutterBuild` fail-closed reddi (`exit 1`).
- Depo testi: `test/features/production/android_release_hardening_test.dart` (`6` test).

Önceki doğrulamalar (21.11.2026, 3. oturum & 1. oturum):
- `flutter build apk --release` (key.properties yok) → `BUILD FAILED in 40s`: *"Release imzalama yapılandırılmadı…"* (beklenen, fail-closed). Debug anahtarıyla release **üretilmedi**.
- `flutter build apk --debug` → başarılı (85 sn); birleşik manifestte `allowBackup="false"`, `fullBackupContent="false"`, `dataExtractionRules="@xml/data_extraction_rules"`.
- `MMS_ALLOW_DEBUG_SIGNING=true flutter build apk --release` (1. oturum) → `app-release.apk` (77.4 MB) üretildi; birleşik manifestte `usesCleartextTraffic="false"`.

## 2. Üretim İmza Anahtarı Oluşturma (bir kez, Owner)

```powershell
keytool -genkeypair -v -keystore C:\MarketMMS-Secrets\market_mms_upload.jks `
  -keyalg RSA -keysize 4096 -validity 10000 -alias market_mms
```

`android/key.properties` (Git'e **eklenmez**, `.gitignore` kapsamında):

```properties
storeFile=C:\\MarketMMS-Secrets\\market_mms_upload.jks
storePassword=<parola>
keyAlias=market_mms
keyPassword=<parola>
```

Anahtar dosyasını ve parolaları ayrı, şifreli bir yedekte saklayın. Anahtar kaybolursa mevcut kurulumlar aynı paket adıyla güncellenemez.

## 3. Sürüm Yönetimi, Derleme ve Paketleme

Tekil sürüm kaynağı kök dizindeki [`pubspec.yaml`](../../pubspec.yaml) dosyasındaki `version: <build-name>+<build-number>` alanıdır (Release 1.0 için `1.0.0+1`). `android/app/build.gradle.kts`, `versionName = flutter.versionName` ve `versionCode = flutter.versionCode` değerlerini doğrudan Flutter derlemesinden alır.

`scripts/package_android_release.ps1` betiği sabit bir sürüm metni kullanmaz:
1. `pubspec.yaml` içindeki `version: X.Y.Z+N` değerini otomatik okur.
2. `flutter build apk --release` / `flutter build appbundle --release` komutuna `--build-name=<X.Y.Z>` ve `--build-number=<N>` bayraklarını açıkça geçirir ve derleme sonrası `android/local.properties` içindeki `flutter.versionName` / `flutter.versionCode` eşleşmesini doğrular.
3. Paket dosyasını gerçek sürüm bilgisiyle `market_mms_v<X.Y.Z>-b<N>.apk` (veya `.aab`) biçiminde üretir; `pubspec.yaml` güncellendiğinde APK adı ve `manifest.json` otomatik güncellenir.
4. İsteğe bağlı `-Version` parametresi yalnızca **uyuşmazlık koruması (guard)** olarak çalışır; `pubspec.yaml` sürümüyle eşleşmezse betik fail-closed olarak durur.

```powershell
flutter test
flutter analyze
pwsh scripts/package_android_release.ps1                  # APK (sürüm pubspec.yaml'dan okunur -> market_mms_v1.0.0-b1.apk)
pwsh scripts/package_android_release.ps1 -BuildAppBundle  # AAB (market_mms_v1.0.0-b1.aab)
# İsteğe bağlı tutarlılık doğrulaması ile:
pwsh scripts/package_android_release.ps1 -Version 1.0.0+1
```

Betik `dist/android_release/` altına sürüm etiketli paket, `.sha256` ve yerel güncelleme `manifest.json` (`latest_version`, `build_number`, `download_url`, `sha256`) örneğini üretir.

> **Android NDK Durumu (Phase 1.1 Finalization):** Yerel Android SDK içine NDK **`28.2.13676358`** (`android-ndk-r28c`) kurulmuş ve `android/app/build.gradle.kts` içinde `ndkVersion = flutter.ndkVersion` (`28.2.13676358`) olarak hizalanmıştır (`:app:printNdkVersion` ile doğrulandı). Release keystore (`market_mms_upload.jks`) üretildikten sonra **SHA-1** (ve denetim için **SHA-256**) parmak izini `ADR-022` (`C2`) Google Cloud Android OAuth Client ID kurulumu için kaydedin.

## 4. Saha Denemesi İçin Bilinçli Gevşetmeler (üretimde KULLANMAYIN)

- `MMS_ALLOW_DEBUG_SIGNING=true` — key.properties yokken debug anahtarıyla imzalar (uyarı loglanır).
- `MMS_ALLOW_CLEARTEXT=true` — TLS'siz geliştirme Hub'ına (`start_master_hub.bat`) release APK ile bağlanmak için.

## 5. Kurulum Sonrası Kabul Kontrolleri (fiziksel cihaz — BLOCKED, Owner tarafından yürütülecek)

1. APK kurulumu ve ilk açılış (kurulum sihirbazı).
2. Hub ile QR eşleştirme ve TLS sertifika sabitleme.
3. Kamera izni → POS'ta sürekli tarama (aynı ürün iki kez → miktar 2).
4. Stok Girişi: barkod okut → 2 adet ekle → stok 5'ten 7'ye çıkar; Hub'da da 7 olur.
5. Wi-Fi kapalıyken satış ve stok girişi; Wi-Fi açılınca kayıpsız senkronizasyon.

> Hub ve tüm APK'lar **birlikte** güncellenmelidir (ADR-014: tenant/store başlık zorunluluğu; ADR-013: `STOCK_RECEIPT`).
