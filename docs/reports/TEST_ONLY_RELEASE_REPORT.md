# TEST_ONLY RELEASE REPORT (`1.0.1+2`)

- **Durum:** `PASS (TEST_ONLY Windows MSI ve Android Release APK izole dizinde üretildi ve doğrulandı)`
- **Tarih:** 2026-11-28
- **Kapsam:** GitHub `v1.0.0` sürümüne ve korumalı 4 yerel dosyaya dokunmadan izole `dist\test_only_1.0.1-b2\` TEST_ONLY test paketi üretimi

## Yapılan değişiklikler

1. **TEST_ONLY Sürüm Ayrımı (`1.0.0+1` -> `1.0.1+2`):**
   - [pubspec.yaml](file:///c:/Users/halil/Github/market-pos/pubspec.yaml): `version: 1.0.1+2`
   - [app_constants.dart](file:///c:/Users/halil/Github/market-pos/lib/core/constants/app_constants.dart): `appVersion = '1.0.1'`
   - [android_release_hardening_test.dart](file:///c:/Users/halil/Github/market-pos/test/features/production/android_release_hardening_test.dart): yeni sürüm `1.0.1+2` ile uyumlu hale getirildi.
2. **İzole TEST_ONLY Derlemeler (`dist\test_only_1.0.1-b2\`):**
   - Windows MSI: `scripts\build_windows_installer.ps1 -Configuration Release -OutputDir dist\test_only_1.0.1-b2 -OverrideVersion 1.0.1`
   - Android Release APK (`MMS_ALLOW_DEBUG_SIGNING=true`, `MMS_ALLOW_CLEARTEXT` ayarlı değil / cleartext `false`): `scripts\package_android_release.ps1 -OutputDir dist\test_only_1.0.1-b2 -Version '1.0.1+2'`
   - Üretilen `market_mms_v1.0.1-b2.apk` ayrıca `MarketMMS-1.0.1-b2-android-TEST_ONLY.apk` olarak kopyalandı.
   - Birleşik doğrulama dosyası: `dist\test_only_1.0.1-b2\SHA256SUMS.txt` yazıldı.

## Değiştirilen dosyalar

- [pubspec.yaml](file:///c:/Users/halil/Github/market-pos/pubspec.yaml)
- [app_constants.dart](file:///c:/Users/halil/Github/market-pos/lib/core/constants/app_constants.dart)
- [android_release_hardening_test.dart](file:///c:/Users/halil/Github/market-pos/test/features/production/android_release_hardening_test.dart)
- Derleme çıktıları (git dışı `dist\test_only_1.0.1-b2\`):
  - `MarketMMS-Setup-1.0.1-x64.msi` (`23076864` bayt)
  - `MarketMMS-1.0.1-b2-android-TEST_ONLY.apk` & `market_mms_v1.0.1-b2.apk` (`84286355` bayt)
  - `SHA256SUMS.txt` ve `manifest.json`

## Çalıştırılan testler

- Sürüm artışı sonrası `flutter analyze` + 14 güvenlik/senkronizasyon/üretim test süiti (`task-2378`)
- `build_windows_installer.ps1` (Dart AOT `mms_backend.exe` + Flutter Windows Release + WiX v4 MSI)
- `package_android_release.ps1` (`flutter build apk --release --build-name=1.0.1 --build-number=2`)
- `Get-AuthenticodeSignature` + Windows Installer COM özelliği denetimi (`WindowsInstaller.Installer`) + SHA-256 doğrulama

## Test sonuçları

- `flutter analyze`: `No issues found! (ran in 8.4s)`.
- Kök `flutter test` (14 süit): `+102: All tests passed!`.
- **Windows MSI (`MarketMMS-Setup-1.0.1-x64.msi`):**
  - Boyut: `23076864` bayt
  - SHA-256: `ECA70C9F66E60AFD0405BB6AF958B0BA51D44EF2E5241A42C59C9836F6422FD2`
  - Authenticode: `NotSigned` *(TEST_ONLY kod imzasız)*
  - MSI Properties: `ProductVersion=1.0.1`, `PURGE_USER_DATA=0`, `ALLOW_DEFERRED_TLS_START=1`
  - Paket içi `mms_backend.exe`: `9994240` bayt, `SHA-256: C3841BB7A26DB578787D1F4F0090EA67C40EE89EEBC2D1A1B3A585176692A2C4`
- **Android APK (`MarketMMS-1.0.1-b2-android-TEST_ONLY.apk`):**
  - Boyut: `84286355` bayt
  - SHA-256: `05214C3B09621D1FDD29E02EA873CB74CE144496CCC9EE4D3058DF0231DAD937`
  - `MMS_ALLOW_CLEARTEXT`: `false` (varsayılan, açık trafik kapalı)
  - İmzalama: `MMS_ALLOW_DEBUG_SIGNING=true` (`android/key.properties` mevcut olmadığı için TEST_ONLY debug keystore)

## Başarısız testler

- Otomatik test ve derleme adımlarında başarısız adım yok (`0` fail).
- Not: İlk MSI tablo taramasında `ServiceInstall`/`ServiceControl` gibi opsiyonel MSI tablolarının WiX paketinde farklı CustomAction yapısında olması nedeniyle `OpenView` sorgusu COM hatası verdi; ardından ek bir salt-okunur `_Tables` denetimiyle `MarketMmsSpike01` yokluğu teyit edilir.

## Bilinen riskler

- Android APK debug imzalı (`TEST_ONLY`) ve Windows MSI Authenticode imzasızdır (`NotSigned`); Windows SmartScreen ve Android Play Protect / bilinmeyen kaynak uyarısı verecektir. Mağaza/üretim yayını öncesinde gerçek keystore ve kod imzalama gerekir.
- Git üzerinde commit/push/tag/release değişikliği yapılmamıştır (`STAGED_COUNT=0`); karar proje sahibine aittir.

## Fiziksel olarak doğrulanan işlemler

- Windows Release ikilisi (`market_pos.exe`), Dart AOT (`mms_backend.exe`), WiX MSI paketi ve Android Release APK derlemelerinin tamamlanıp SHA-256 değerlerinin üretilmesi.

## Henüz doğrulanmayan işlemler

- `MarketMMS-Setup-1.0.1-x64.msi` paketinin makinede fiziksel upgrade/kurulumu (`msiexec` bu oturumda bilerek çalıştırılmadı).
- `MarketMMS-1.0.1-b2-android-TEST_ONLY.apk` dosyasının gerçek Android cihaza yüklenip başlatılması.
