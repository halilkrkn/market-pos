# PHASE_A2_A3_DELIVERY_REPORT.md — Faz 6 (`Hat A / A-2 & A-3`) Güvenli Derleme/AST & Fiziksel Blokaj Raporu

- **Faz:** Faz 6 — Güvenli Derleme / PowerShell AST Doğrulama ve Fiziksel Kabul Kapısı (`A-2 & A-3`)
- **Durum Özeti:**
  - PowerShell Betik Sözdizimi (`AST`) Doğrulaması: **`BUILD_VERIFIED`** (`0` parse hatası)
  - Windows Master Hub AOT İkili Derleme Kontrolü (`dart build cli`): **`BUILD_VERIFIED`**
  - Windows Masaüstü İstemci Debug Derlemesi (`flutter build windows --debug`): **`BUILD_VERIFIED`**
  - Android Mobil APK Debug Derlemesi (`flutter build apk --debug`): **`BUILD_VERIFIED`**
  - Fiziksel Ortam & Canlı Servis/Cihaz Kabul Maddeleri (`D1–D4`, `B1`, `B2`, `PAT-01…12, 14, 15`): **`BLOCKED`** (`OWNER ACTION REQUIRED`)

---

## 1. Gerçekleşen Güvenli AST ve Derleme Doğrulamaları

### 1.1 PowerShell AST Doğrulaması (`test_spikes/spike_01_backend/scripts/*.ps1`)
- `build_aot.ps1` → `AST OK (0 errors)`
- `install_mms_service.ps1` → `AST OK (0 errors)`
- `setup_service_acls.ps1` → `AST OK (0 errors)`
- `uninstall_mms_service.ps1` → `AST OK (0 errors)`

### 1.2 Güvenli Derleme Çıktıları
1. **Windows Master Hub (`test_spikes/spike_01_backend`):**
   - Komut: `dart build cli -t bin/server.dart -o <isolated_temp_dir>`
   - Sonuç: `DART_BUILD_CLI_EXIT=0` (`sqlite3` build/link hook'u ile `bundle\bin\server.exe` üretildi; doğrulama sonrası geçici klasör silindi).
   - Not: Paket SQLite native assets (`build hooks`) kullandığından güncel Dart SDK'da `dart compile exe` yerine `build_aot.ps1` içindeki `dart build cli` kullanılmaktadır.
2. **Windows İstemci (`market_pos`):**
   - Komut: `flutter build windows --debug`
   - Sonuç: `WIN_BUILD_EXIT=0` (`Built build\windows\x64\runner\Debug\market_pos.exe` in `20,9s`).
3. **Android İstemci (`market_pos`):**
   - Komut: `flutter build apk --debug`
   - Sonuç: `APK_BUILD_EXIT=0` (`Built build\app\outputs\flutter-apk\app-debug.apk` in `49,9s`).

---

## 2. Fiziksel Blokajlar (`BLOCKED — OWNER ACTION REQUIRED`)

Aşağıdaki maddeler gerçek Windows Server/Service ortamı, standart Windows kullanıcısı NTFS ACL testi, canlı TLS/CA sertifika doğrulaması, fiziksel Android cihaz, gerçek kamera ve yerel Wi-Fi/LAN gerektirdiği için otomatik ortamda **`BLOCKED`** olarak işaretlenmiştir ve proje sahibi tarafından [PHYSICAL_ACCEPTANCE_TEST_PLAN.md](file:///c:/Users/halil/Github/market-pos/PHYSICAL_ACCEPTANCE_TEST_PLAN.md) ve [OWNER_ACTION_CHECKLIST.md](file:///c:/Users/halil/Github/market-pos/OWNER_ACTION_CHECKLIST.md) adımlarıyla yürütülmelidir:

- **`D1–D4`:** `MarketMMSService` WinSW kurulumu, yeniden başlatma, kurtarma ve standart kullanıcı ACL denetimleri — **`BLOCKED`**
- **`B1`, `B2` (`B-2` / `B-3` canlı doğrulama):** Fiziksel Android/iOS istemcilerde Root CA + Certificate Pinning, Android Keystore / Windows DPAPI canlı yeniden başlatma — **`BLOCKED`**
- **`PAT-01…12, PAT-14, PAT-15`:** Fiziksel LAN keşfi, QR/mDNS eşleştirme, canlı çoklu cihaz satış/barkod/OFF/restore uçtan uca fiziksel saha kabul testleri — **`BLOCKED`**

> **Güvenlik Kısıtı Teyidi:** Mevcut `MarketMmsSpike01` servisine ve `%PROGRAMDATA%\MarketMMS` canlı verilerine kesinlikle dokunulmamıştır.
