# MARKET MMS — İstemci Uygulama Hazırlık Raporu (`CLIENT_APPLICATION_READINESS`)

**Tarih:** 2026-11-27

**Kapsam:** Stage I — İzole Windows İstemcisi Smoke Testi, Android Fail-Closed Release İmza Koruması, Debug & Test-Signed Release APK Derlemeleri ve WHPX Android Emülatör APK Smoke Doğrulaması

**Durum:** İzole Windows masaüstü istemcisi, Android APK derlemeleri (`apksigner` + `aapt2` doğrulamalı) ve WHPX Android emülatör (`flutter_emulator`) kurulum/başlatma smoke testi **PASS**; fiziksel Android telefon/LAN kamera testi (`adb devices` fiziksel cihaz yok) ve ticari Android keystore imzalaması **BLOCKED** (beklemede).

---

## 1. Windows Masaüstü İstemcisi (İzole Smoke Doğrulaması)

[`start_isolated_windows_client.ps1`](file:///c:/Users/halil/Github/market-pos/scripts/dev_test/start_isolated_windows_client.ps1) çalıştırıldı (`LOCALAPPDATA` geçici olarak `%LOCALAPPDATA%\MarketMMS_Isolated_Test\client_win` adresine yönlendirildi; gerçek `%LOCALAPPDATA%\MarketMMS\client_local.db` dokunulmadan kaldı):

- **Çalıştırılan İkili:** `dist\windows_release_v1_0_0_tray\client\market_pos.exe` (`175104` B, SHA-256 `7F449053E569740E8436B6ED9D28926811498E04E405215C5C01C254ADDB1217`)
- **Smoke Sonucu:** **`SMOKE_PASS`** (`WIN_SMOKE_EXIT=0`, `pid=10084`)
- **İzole İstemci DB:** `C:\Users\halil\AppData\Local\MarketMMS_Isolated_Test\client_win\MarketMMS\client_local.db` oluşturuldu (`isolated_db_exists=true`, `isolated_db_bytes=4096`)
- **Tray / Pencere Davranışı:** 5 saniye bekleme sonunda `alive_before_close=true`, `hwnd_before_close=68224`; `WM_CLOSE` (`CloseMainWindow()`) sonrasında sistem tepsisi tasarımı gereği süreç yaşamaya devam etti (`alive_after_wm_close=true`) ve test sonlandırması ile temiz kapatıldı (`MARKET_POS_PROCS=0`).

---

## 2. Android İstemci Derleme ve İmza Güvenliği Doğrulaması

| Kontrol / Artefakt | Komut / Yol | Boyut & SHA-256 | Sonuç |
|---|---|---|---|
| **Fail-Closed Release Guard** | `flutter build apk --release` (`MMS_ALLOW_DEBUG_SIGNING` yok, `android/key.properties` yok) | — | **`FAIL_CLOSED_RELEASE_EXIT=1`** (beklendiği gibi imzasız release engellendi) |
| **Debug APK** | `flutter build apk --debug` → `%LOCALAPPDATA%\MarketMMS_Isolated_Test\android_apk\app-debug.apk` | `199156436` B, `SHA-256: A3D6770709EDFF120AB9306C8580BFEAB586D1069488554AE53C49A2A44E59EB` | **`DEBUG_APK_EXIT=0`**, `APKSIGNER_EXIT=0` (`CN=Android Debug`, cert SHA-256 `beb68eff762d37885ec746b08459e7442d8a069c4190010a32ef9b2a2dd5ecbc`) |
| **Test-Signed Release APK** | `$env:MMS_ALLOW_DEBUG_SIGNING='true'; flutter build apk --release` → `%LOCALAPPDATA%\MarketMMS_Isolated_Test\android_apk\app-release-testsigned.apk` | `84155279` B (`80.3 MB`), `SHA-256: E94A35C8B002B2909AA6249FCB7E33A79D3C55EF64738727B0DF6D4190F0235E` | **`TEST_SIGNED_RELEASE_APK_EXIT=0`**, `APKSIGNER_EXIT=0` (**`TEST-SIGNED ONLY`**, `CN=Android Debug`!) |

### AndroidManifest Güvenlik Bayrakları (`aapt2 dump xmltree`)
Üretilen `app-release-testsigned.apk` içinde doğrulanan bayraklar:
- `package="com.marketmms.market_pos"`
- `android:allowBackup=false`
- `android:usesCleartextTraffic=false`
- `MainActivity`: `com.marketmms.market_pos.MainActivity`

---

## 3. Android Emülatör (`flutter_emulator`) Canlı Kurulum ve Başlatma Testi

- **Hızlandırma Kontrolü (`emulator -accel-check`):** `ACCEL_CHECK_EXIT=0` (`WHPX(10.0.22631) is installed and usable.`)
- **Önyükleme (`flutter_emulator` / Android 33 x86_64):** **`EMULATOR_BOOTED=True`** (`sys.boot_completed=1`)
- **APK Kurulumu (`adb install -r app-debug.apk`):** **`ADB_INSTALL_EXIT=0`** (`Performing Streamed Install`, `Success`)
- **Başlatma (`adb shell am start -W -n com.marketmms.market_pos/.MainActivity`):**
  - Uygulama süreci ayağa kalktı: **`APP_PID=3757`**
  - `adb logcat -d -t 40 AndroidRuntime:E flutter:V *:S` çıktısında çalışma zamanı çökmesi / istisnası gözlenmedi (`LOGCAT_TAIL` boş).
  - *Not:* İlk soğuk önyükleme altında `am start -W` `Status: timeout` (`WaitTime: 11687`) döndürdüyse de süreç (`APP_PID=3757`) çalıştı; görsel UI etkileşimi ve gerçek kamera/LAN testi bu testte yapılmadı.
- **Kapanış ve Temizlik:** `adb emu kill` sonrasında kalan emülatör/qemu/netsimd süreçleri temizlendi (`REMAINING_ANDROID_PROCS=0`).

---

## 4. Açık Sınırlar ve Fiziksel Önkoşullar (`BLOCKED`)

1. **Mağaza Yayın İmzası (Release Keystore):** Üretim dağıtımı için `android/key.properties` ve gerçek upload/release keystore sağlanmalıdır; mevcut `app-release-testsigned.apk` yalnızca **`TEST-SIGNED ONLY`** doğrulama içindir.
2. **Fiziksel Android Telefon & Donanım Doğrulaması (`BLOCKED`):** Gerçek telefon üzerinde QR okuma/kamera (`PAT-03`, `PAT-04`), gerçek mağaza Wi-Fi mDNS/UDP (`PAT-01`, `PAT-02`), pil/Doze arka plan eşitleme (`PAT-16`) fiziksel cihaz bağlı olmadığı için **yapılmamıştır**.
