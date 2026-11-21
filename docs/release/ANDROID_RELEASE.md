# Android Üretim Sürümü (Release) Kılavuzu — MARKET MMS

*Son güncelleme: 21 Kasım 2026*

## 1. Güvenlik Varsayılanları

| Ayar | Debug / Profile | Release |
|---|---|---|
| `usesCleartextTraffic` (şifresiz HTTP) | `true` (yerel geliştirme Hub'ı) | **`false`** — Hub ile yalnızca HTTPS/TLS |
| İmzalama | Debug anahtarı | **`android/key.properties`** zorunlu; yoksa derleme durur |
| Derlemeye gömülü cihaz token'ı | Yok | Yok (token yalnızca eşleştirme sonrası Android Keystore'dan okunur) |
| Android otomatik yedekleme (Google bulut / cihaz aktarımı) | **Kapalı** | **Kapalı** — `allowBackup=false`, `fullBackupContent=false`, `res/xml/data_extraction_rules.xml` (API 31+, tüm alanlar hariç). Şifresiz yerel DB ve `device_id` cihaz dışına çıkmaz (ADR-016 Ek A.4) |

Doğrulama (21.11.2026, 3. oturum, bu depoda çalıştırıldı):
- `flutter build apk --release` (key.properties yok) → `BUILD FAILED in 40s`: *"Release imzalama yapılandırılmadı…"* (beklenen, fail-closed). Debug anahtarıyla release **üretilmedi**.
- `flutter build apk --debug` → başarılı (85 sn); birleşik manifestte `allowBackup="false"`, `fullBackupContent="false"`, `dataExtractionRules="@xml/data_extraction_rules"`.
- Depo testi: `test/features/production/android_release_hardening_test.dart` (4).

Önceki doğrulama (21.11.2026, 1. oturum):
- `flutter build apk --release` (key.properties yok) → `BUILD FAILED`: *"Release imzalama yapılandırılmadı…"* (beklenen, fail-closed).
- `MMS_ALLOW_DEBUG_SIGNING=true flutter build apk --release` → `app-release.apk` (77.4 MB) üretildi; birleşik manifestte `usesCleartextTraffic="false"`.

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

## 3. Derleme ve Paketleme

```powershell
flutter test
flutter analyze
pwsh scripts/package_android_release.ps1 -Version 1.0.0            # APK
pwsh scripts/package_android_release.ps1 -Version 1.0.0 -BuildAppBundle  # AAB
```

Betik `dist/android_release/` altına paket, `.sha256` ve güncelleme manifest örneği üretir.

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
