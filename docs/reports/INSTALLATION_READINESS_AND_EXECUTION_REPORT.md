# MARKET MMS — Kurulum Hazırlık, Uygulama ve İzole Uçtan Uca Doğrulama Raporu

*Tarih: 25 Kasım 2026 · Çalışma Dizini: `c:\Users\halil\Github\market-pos` · Kapsam: Windows System Tray + Otomatik Başlatma + Kontrollü Çıkış, Windows Release & WiX v5 MSI, Android Release APK Denetimi, İzole Geliştirme Test Ortamı (Test Hub + Windows Client + 2-İstemcili Canlı E2E) ve İkinci PC Pilot Hazırlığı.*

> [!IMPORTANT]
> **Gerçeklik ve Şeffaflık İlkesi:** Bu raporda yalnızca bu oturumda fiilen çalıştırılan komutlar, okunan dosyalar ve alınan gerçek çıktılar raporlanmıştır. Fiziksel Windows masaüstü etkileşimleri (tepsi ikonuna çift tık/sağ tık), fiziksel Android telefon testleri, Android üretim imzalı Release APK üretimi (Owner keystore yok) ve ikinci bilgisayarda gerçek MSI/SCM kurulumu **gerçekleştirilmemiştir** ve açıkça `NOT RUN / BLOCKED` olarak işaretlenmiştir.

---

## 1. Yönetici Özeti

- **Geliştirme Bilgisayarı İzolasyon Kararı:** Mevcut geliştirme bilgisayarında korunan `MarketMmsSpike01` servisine (`TCP 8085`, `PID 15232`), gerçek `%LOCALAPPDATA%\MarketMMS\client_local.db` dosyasına, firewall kurallarına, `Public` Wi-Fi profiline ve dört korunan untracked dosyaya dokunmadan **tam izole bir Test Hub (`TCP 8947`, `UDP 8948`) + izole Windows Client (`%LOCALAPPDATA%\MarketMMS_Isolated_Test`)** ortamı kurulmuş ve canlı uçtan uca senkronizasyon çalıştırılmıştır.
- **Windows System Tray & Otomatik Başlatma:** Harici pub paketi eklenmeden native Win32 C++ (`windows/runner/windows_shell_tray.h`, `windows_shell_tray.cpp`) ve Flutter Presentation katmanı (`lib/features/shell/presentation/windows/*`) ile System Tray, pencere küçültme/X ile tepsiye gizleme, sağ tık durum menüsü, kullanıcı kontrollü `HKCU\...\Run` otomatik başlatma ve kontrollü çıkış (sync duraklat -> yedek bekle -> Drift SQLite kapat -> native çıkış) geliştirilmiş ve otomatik testlerle doğrulanmıştır.
- **Windows Release & WiX v5 MSI:** Güncel koddan `dist\windows_release_v1_0_0_tray\` paketi ve `dist\installer_v1_0_0_tray\MarketMMS-Setup-1.0.0-x64.msi` (`23.044.096` bayt, SHA-256: `A54DF1AC74CD48AA6974874004C962F249000BACB83CD9AE8C12B0F6BF65FD9C`, Authenticode: `NotSigned`) başarıyla üretilmiştir. MSI mevcut geliştirme bilgisayarında **çalıştırılmamıştır**. *(Şeffaflık notu: WiX/MSBuild derleme çıktısı aynı anda `dist\installer\MarketMMS-Setup-1.0.0-x64.msi` dosyasını da `23.044.096` bayt / `A54DF1AC...` sürümüne güncellemiştir; ayrıntı §10'dadır.)*
- **Android Release APK:** `android/key.properties` ve üretim `.jks` keystore dosyası bulunmadığından `flutter build apk --release` **fail-closed (`exit code 1`)** olarak durmuştur. Sahte veya debug imzalı Release APK üretilmemiştir.
- **Nihai Karar:** **`CONDITIONAL GO`** — Yazılım ve izole yerel uçtan uca senkronizasyon/Windows paketleme teknik olarak hazırdır; ancak ikinci PC Pilot kurulumu ve fiziksel Android kabulü için Owner tarafından üretim Android keystore (`B1`), üretim Hub TLS sertifikaları (`B2`), Portable Recovery Password (`B3`) ve isteğe bağlı Google Cloud OAuth (`C1/C2`) adımlarının tamamlanması gerekmektedir.

---

## 2. Mevcut Bilgisayarda Test Edilebilirlik Kararı

**Karar: EVET — Güvenli İzolasyonla Test Edilebilir (`VERIFIED`).**

Mevcut geliştirme bilgisayarında `MarketMmsSpike01` servisinin `Running` olması MSI kurulumunu engeller (`ERR_PROTECTED_SERVICE_CONFLICT`), ancak `mms_backend.exe` ikilisinin `--config=<yol>` ile Windows Service olmadan bağımsız bir süreç olarak ayrı port (`TCP 8947 / UDP 8948`), ayrı çalışma dizini (`%LOCALAPPDATA%\MarketMMS_Isolated_Test`), ayrı TLS sertifikaları ve ayrı SQLite veritabanı (`market_master_test.db`) üzerinden çalıştırılmasına teknik bir engel yoktur. Windows Client da `LOCALAPPDATA` ortam değişkeni yalnızca alt sürece özel yönlendirilerek gerçek `%LOCALAPPDATA%\MarketMMS\client_local.db` dosyasına dokunmadan çalıştırılmıştır.

Ayrı bir bilgisayara geçmek **yalnızca şu iki amaç için** zorunludur:
1. Gerçek Windows Service (`MarketMMSService`), MSI kurulumu, `%ProgramData%\MarketMMS` ACL'leri ve `TCP 8945 / UDP 8946` firewall kurallarının pilot kabulü (çünkü geliştirme makinesinde `MarketMmsSpike01` korunmaktadır ve MSI çalıştırılamaz).
2. `Public` Wi-Fi profili ve firewall kuralları değiştirilmeden fiziksel Android cihazların LAN üzerinden doğrudan Hub'a bağlanması gereken saha testi (mevcut PC'de Wi-Fi profili `Public` olduğu için firewall değişikliği yapılmadan dış telefon erişimi engellenebilir).

---

## 3. `MarketMmsSpike01` ve Çevre Koruma Doğrulaması

Tüm çalışma boyunca aşağıdaki değişmez güvenlik sınırları **başlangıçta ve bitişte** read-only olarak doğrulanmıştır:

| Korunan Varlık | Başlangıç Ölçümü (01:14) | Bitiş Ölçümü (01:56) | Durum |
|---|---|---|---|
| `MarketMmsSpike01` Servisi | `Running`, `Auto`, `PID 15232`, `PathName: ...\MarketMmsSpike01.exe` | `Running`, `PID 15232` | **DEĞİŞMEDİ / KORUNDU** |
| Port `TCP 8085` | `0.0.0.0:8085 Listen OwningProcess=23800` | `0.0.0.0:8085 Listen OwningProcess=23800` | **DEĞİŞMEDİ / KORUNDU** |
| `%LOCALAPPDATA%\MarketMMS\client_local.db` | `159744 B`, `2026-11-20T12:00:01.3928872Z`, SHA-256 `587120C66FA6D0AECB0AC2CAEB1D2A47EC1E2BD2E5D38149DE7F45FE828F3AED` | `159744 B`, `2026-11-20T12:00:01.3928872Z`, SHA-256 `587120C66FA6D0AECB0AC2CAEB1D2A47EC1E2BD2E5D38149DE7F45FE828F3AED` | **DEĞİŞMEDİ / KORUNDU** |
| `.vscode/settings.json` | `145 B`, SHA-256 `70CE85ED5039EE83FA3C9260E56DF3BBCD60C3549AD0148A114F5BBC09A5F8EA` | `145 B`, SHA-256 `70CE85ED5039EE83FA3C9260E56DF3BBCD60C3549AD0148A114F5BBC09A5F8EA` | **DEĞİŞMEDİ / KORUNDU** |
| `run_windows_client.bat` | `384 B`, SHA-256 `10BBC6D6FCA0D8ECAAC141509B7BA842B8B340D5C7191F4D6BECE7EBD5F2567D` | `384 B`, SHA-256 `10BBC6D6FCA0D8ECAAC141509B7BA842B8B340D5C7191F4D6BECE7EBD5F2567D` | **DEĞİŞMEDİ / KORUNDU** |
| `start_master_hub.bat` | `1341 B`, SHA-256 `03D0A2A493F8A49ECF3E72C59C510233401EC5C9A563B4BE58B22CBA34D9E2DD` | `1341 B`, SHA-256 `03D0A2A493F8A49ECF3E72C59C510233401EC5C9A563B4BE58B22CBA34D9E2DD` | **DEĞİŞMEDİ / KORUNDU** |
| `stop_master_hub.bat` | `160 B`, SHA-256 `C18C9081A5A49941FE734C65A815366E2F90A913A7E5E10E24B883E41EB33677` | `160 B`, SHA-256 `C18C9081A5A49941FE734C65A815366E2F90A913A7E5E10E24B883E41EB33677` | **DEĞİŞMEDİ / KORUNDU** |
| Git Durumu | `main` dalı, commit/stage yapılmadı | Yalnızca yerel çalışma dosyaları, **0 commit/stage** | **KORUNDU** |

---

## 4. Test Hub Mimarisi

İzole Test Hub altyapısı [`scripts/dev_test/start_isolated_test_hub.ps1`](file:///c:/Users/halil/Github/market-pos/scripts/dev_test/start_isolated_test_hub.ps1) ve [`scripts/dev_test/stop_isolated_test_hub.ps1`](file:///c:/Users/halil/Github/market-pos/scripts/dev_test/stop_isolated_test_hub.ps1) ile kurulmuştur:

- **Çalışma Modeli:** Windows Service kurulmadan `mms_backend.exe --config="<test_config>\hub_config.json"` komutuyla bağımsız Dart AOT süreci olarak başlatılır (`test_spikes/spike_01_backend/bin/server.dart#L6065-L6292`, `test_spikes/spike_01_backend/lib/config/hub_config.dart#L18-L292`).
- **`sqlite3.dll` Kopyalama Gereksinimi:** Derlenmiş `mms_backend.exe`, `sqlite3` native asset çözümlemesi gereği `..\lib\sqlite3.dll` (`hub\lib\sqlite3.dll`) yolunu aradığı için betik `sqlite3.dll` dosyasını üç konuma (`hub\bin\sqlite3.dll`, `hub\bin\lib\sqlite3.dll`, `hub\lib\sqlite3.dll`) kopyalar.
- **Güvenlik ve OAuth İzolasyonu:**
  - Test Hub çalıştırılırken `MMS_GDRIVE_CLIENT_ID`, `MMS_GDRIVE_CLIENT_SECRET`, `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET`, `ROOT_CA_CERT_FILE`, `ADMIN_SECRET`, `PEPPER_FILE`, `DB_PATH`, `PORT`, `DISCOVERY_PORT` ortam değişkenleri alt süreç ortamından temizlenir (`scripts/dev_test/start_isolated_test_hub.ps1#L198-L228`).
  - Test-only Root CA (`ca_offline\ca.key` + `hub\certs\ca.crt`, X.509v3 `CA:TRUE`, `keyCertSign,cRLSign`) ve leaf sertifika (`server.crt`, SAN: `IP:127.0.0.1,DNS:localhost,IP:192.168.1.158`) OpenSSL 3.5.9 ile izole dizinde üretilir; `ca.key` sunucunun `certs\` klasörüne konmaz.
  - `environment: "production"`, `require_tenant_store_headers: true`, `tenant_id: "tenant-isolated-test"`, `store_id: "store-isolated-test-01"`, `hub_id: "MMS-HUB-ISOLATED-TEST"`, `backup_schedule.interval_hours: 0` ile gerçek TLS + tenant/store doğrulama akışı çalıştırılır.
  - Test `pepper.dpapi` ve `live_drive_sync_secret.dpapi` dosyaları yalnızca `%LOCALAPPDATA%\MarketMMS_Isolated_Test\hub\security\` içinde oluşturulur.
- **Log Hijyeni Doğrulaması:** Çalıştırma sonrası `hub_stdout.log` ve `hub_stderr.log` üzerinde gizli veri taraması (`mms_dt_`, `ya29.`, `BEGIN ... PRIVATE KEY`, `GOCSPX-`, `admin_secret`) yapılmış ve **`LOG_SECRET_LEAK_HITS=0`** sonucu alınmıştır.

---

## 5. Test Portları

| Bileşen | Üretim / Korunan Port | Test Hub Portu | Durum |
|---|---|---|---|
| `MarketMmsSpike01` (Korunan) | `TCP 8085` | Dokunulmadı | `Running` (`PID 23800`) |
| Üretim Hub HTTPS API | `TCP 8945` | **Kullanılmadı** | Boş / ayrılmış |
| Üretim UDP Discovery | `UDP 8946` | **Kullanılmadı** | Boş / ayrılmış |
| **İzole Test Hub HTTPS API** | — | **`TCP 8947`** | Boş doğrulandı, canlı test edildi |
| **İzole Test Hub UDP Discovery** | — | **`UDP 8948`** | Boş doğrulandı, canlı test edildi |

---

## 6. Test SQLite DB Yolu

- **Test Hub Merkezi DB:** `C:\Users\halil\AppData\Local\MarketMMS_Isolated_Test\hub\data\market_master_test.db`
- **İzole E2E İstemci DB'leri:** `C:\Users\halil\AppData\Local\MarketMMS_Isolated_Test\e2e_clients\win_test_<ts>.db` ve `and_sim_<ts>.db`
- **İzole Windows Client UI DB:** `C:\Users\halil\AppData\Local\MarketMMS_Isolated_Test\client_win\MarketMMS\client_local.db`
- **Otomatik Silmeme Kuralı:** [`scripts/dev_test/stop_isolated_test_hub.ps1`](file:///c:/Users/halil/Github/market-pos/scripts/dev_test/stop_isolated_test_hub.ps1) süreci durdurduğunda `market_master_test.db` dosyasını silmez; çıktı olarak `Test DB korundu: True` raporlar.

---

## 7. Windows Client Sonucu

- **Başlatma İzolasyonu:** [`scripts/dev_test/start_isolated_windows_client.ps1`](file:///c:/Users/halil/Github/market-pos/scripts/dev_test/start_isolated_windows_client.ps1) yalnızca alt süreç ortamında `LOCALAPPDATA` değişkenini `%LOCALAPPDATA%\MarketMMS_Isolated_Test\client_win` olarak ayarlar; `lib/core/storage/local_database_service.dart#L199-L217` bu dizin altında `MarketMMS\client_local.db` açar.
- **Gerçekleştirilen Duman Testi:** `dist\windows_release_v1_0_0_tray\client\market_pos.exe` (`PID 29200`) izole modda çalıştırılmıştır:
  - 5 saniye sonra `alive_before_close: true`, `isolated_db_exists: true` (`client_local.db` `4096 B` + `-wal`/`-shm` oluşturuldu), `status: "SMOKE_PASS"`.
  - `WM_CLOSE` (`CloseMainWindow()`) gönderildiğinde sürecin kapanmayıp ayakta kaldığı (`alive_after_wm_close: true`) gözlenmiştir.
  - *Sınır Notu:* Otomasyon oturumu etkileşimli olmayan masaüstü oturumunda çalıştığı için `MainWindowHandle` değeri `0` raporlanmıştır; görsel pencere, tepsi simgesi ve fare tıklaması etkileşimleri fiziksel Windows masaüstü doğrulaması gerektirir (§17).

---

## 8. System Tray Mimarisi ve Uygulaması

Clean Architecture korunarak yalnızca Windows runner ve Presentation katmanında uygulanmıştır (Domain ve Data katmanlarına hiçbir UI/tray bağımlılığı eklenmemiştir; harici pub paketi eklenmemiştir):

1. **Native Win32 Katmanı (`windows/runner/`):**
   - [`windows_shell_tray.h`](file:///c:/Users/halil/Github/market-pos/windows/runner/windows_shell_tray.h) ve [`windows_shell_tray.cpp`](file:///c:/Users/halil/Github/market-pos/windows/runner/windows_shell_tray.cpp): `com.marketmms.market_pos/windows_shell` MethodChannel üzerinden Flutter ile haberleşir.
   - `NOTIFYICONDATAW` (`IDI_APP_ICON`) ile tepsi simgesi ekler ve `TaskbarCreated` mesajında simgeyi yeniler.
   - `WM_CLOSE` ve `WM_SYSCOMMAND (SC_MINIMIZE)` mesajlarını (`tray_enabled_ && !allow_close_`) yakalayıp `ShowWindow(hwnd_, SW_HIDE)` ile tepsiye gizler; `WM_QUERYENDSESSION` durumunda OS oturum kapatmasını engellemez.
   - Çift tık (`WM_LBUTTONDBLCLK`) pencereyi geri getirir (`openApp`); sağ tık (`WM_RBUTTONUP` / `WM_CONTEXTMENU`) Türkçe bağlam menüsünü açar: `MARKET MMS'i Aç` (varsayılan kalın öğe), `Hub Durumu: ...`, `Senkronizasyon Durumu: ...`, `Yedekleme Durumu: ...`, `Ayarlar`, `Uygulamadan Çık`.
   - Runner entegrasyonu: [`flutter_window.h`](file:///c:/Users/halil/Github/market-pos/windows/runner/flutter_window.h), [`flutter_window.cpp`](file:///c:/Users/halil/Github/market-pos/windows/runner/flutter_window.cpp), [`CMakeLists.txt`](file:///c:/Users/halil/Github/market-pos/windows/runner/CMakeLists.txt) (`shell32.lib`, `advapi32.lib`).
2. **Presentation Katmanı (`lib/features/shell/presentation/windows/`):**
   - [`windows_tray_models.dart`](file:///c:/Users/halil/Github/market-pos/lib/features/shell/presentation/windows/windows_tray_models.dart): `WindowsTrayMenuAction`, `WindowsTrayStatusSnapshot`, `WindowsTrayStatusFormatter` (sahte başarı üretmeden gerçek `SystemStatus`, `HubConnectionState`, `SyncCoordinatorState`, `BackupScheduleViewState` değerlerini yansıtır) ve `WindowsTrayState`.
   - [`windows_desktop_shell_gateway.dart`](file:///c:/Users/halil/Github/market-pos/lib/features/shell/presentation/windows/windows_desktop_shell_gateway.dart): `WindowsDesktopShellGateway` arayüzü, `MethodChannelWindowsDesktopShellGateway` ve test/mobil için `NoopWindowsDesktopShellGateway`.
   - [`windows_tray_controller.dart`](file:///c:/Users/halil/Github/market-pos/lib/features/shell/presentation/windows/windows_tray_controller.dart): Yaşam döngüsü, durum tekilleştirme (`pushStatus`), otomatik başlatma yönetimi ve **kontrollü çıkış (`performControlledExit`)**:
     1. Re-entrancy koruması (`isExiting`),
     2. `BackgroundSyncCoordinator.pauseForMaintenance(timeout: 5s)`,
     3. `BackupScheduleController.waitForIdle()` (5s sınırlı bekleme),
     4. `LocalDatabaseService.close()` (aktif sorguları boşaltır, WAL ve Outbox verilerini korur),
     5. `gateway.confirmExit()` (`allow_close_ = true`, tepsi simgesini kaldırır ve `WM_CLOSE` ile temiz kapanış yapar).
   - [`windows_tray_providers.dart`](file:///c:/Users/halil/Github/market-pos/lib/features/shell/presentation/windows/windows_tray_providers.dart), [`windows_desktop_settings_card.dart`](file:///c:/Users/halil/Github/market-pos/lib/features/shell/presentation/windows/windows_desktop_settings_card.dart), [`main_shell_screen.dart`](file:///c:/Users/halil/Github/market-pos/lib/features/shell/presentation/screens/main_shell_screen.dart#L36-L52), [`diagnostics_view.dart`](file:///c:/Users/halil/Github/market-pos/lib/features/diagnostics/presentation/screens/diagnostics_view.dart#L70-L76), [`main.dart`](file:///c:/Users/halil/Github/market-pos/lib/main.dart#L140-L143).

---

## 9. Otomatik Başlatma

- **Kayıt Defteri Anahtarı:** `HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run` altında `MarketMMSClient` (`REG_SZ`, çalışan `market_pos.exe` tam yolu tırnak içinde) — [`windows_shell_tray.cpp#L23-L25`](file:///c:/Users/halil/Github/market-pos/windows/runner/windows_shell_tray.cpp#L23-L25) ve `#L283-L333`.
- **Güvenlik ve Kurallar:**
  - İlk kurulumda veya açılışta otomatik etkinleştirilmez; varsayılan `false` kalır ve yalnızca kullanıcı **Sistem Durumu → Windows Masaüstü ve Sistem Tepsisi** kartındaki anahtardan açıp kapatabilir (`Key('windows_autostart_switch')`).
  - Standart Windows kullanıcı hesabıyla yönetilir; yönetici yetkisi (`UAC`) gerektirmez.
  - `MarketMMSService` Windows Hub servisinden tamamen bağımsızdır.
- **Uninstall Temizliği:** [`installer/windows/scripts/mms_installer_engine.ps1#L1413-L1425`](file:///c:/Users/halil/Github/market-pos/installer/windows/scripts/mms_installer_engine.ps1#L1413-L1425) içine MSI kaldırma sırasında `HKCU` ve `Registry::HKEY_USERS\*\Software\Microsoft\Windows\CurrentVersion\Run` altındaki `MarketMMSClient` değerini temizleyen (veritabanı ve kullanıcı verilerine kesinlikle dokunmayan) temizlik adımı eklenmiştir.

---

## 10. Windows Release ve WiX v5 MSI Sonucu

- **Güncel Release Klasörü:** `dist\windows_release_v1_0_0_tray\` (`package_windows_release.ps1` ile üretildi):
  - `client\market_pos.exe`: `175.104` bayt, SHA-256: `7F449053E569740E8436B6ED9D28926811498E04E405215C5C01C254ADDB1217`
  - `hub_bin\mms_backend.exe`: `9.972.736` bayt (`9.51 MB`), SHA-256: `D72B05E5FDD51A982702E727377BB54D4121AE10D28EBE3C9FE1BDD98947A53F`
- **Güncel WiX v5 MSI Paketi:** `dist\installer_v1_0_0_tray\MarketMMS-Setup-1.0.0-x64.msi` (`build_windows_installer.ps1` ile üretildi, **0 hata**, 3 önemsiz ICE60 uyarısı):
  - **Boyut:** `23.044.096` bayt
  - **SHA-256:** `A54DF1AC74CD48AA6974874004C962F249000BACB83CD9AE8C12B0F6BF65FD9C`
  - **Authenticode Dijital İmza:** `NotSigned` *(dijital imzalı DEĞİLDİR; Owner kod imzalama sertifikası olmadan Windows SmartScreen "bilinmeyen yayıncı" uyarısı gösterecektir)*.
- **Koruma ve Önceki Paket Notu:** MSI mevcut geliştirme bilgisayarında **çalıştırılmamıştır**. `dist\windows_release\` klasörüne dokunulmamıştır. Ancak WiX/MSBuild derlemesi sırasında `dist\installer\MarketMMS-Setup-1.0.0-x64.msi` dosyasının da `22.994.944` bayt (`D53C74F9...`) iken `23.044.096` bayt (`A54DF1AC...`) olarak güncellendiği gözlemlenmiştir (`dist\installer\SHA256SUMS.txt` ise `9484F2E0...` değerini içermektedir); bunun nedeni `MarketMMSInstaller.wixproj` / `stage3_windows_installer_audit_test.dart` tarafından paylaşılan `build\wix_bin` çıktı yoludur.

---

## 11. Android Release APK Sonucu

- **Durum:** **`BLOCKED (Owner Keystore Eksik — Fail-Closed Doğrulandı)`**.
- **İnceleme Bulguları:**
  - `android/app/build.gradle.kts#L26-L87`: `applicationId = "com.marketmms.market_pos"`, Release'te `usesCleartextTraffic = "false"` (varsayılan), `android/key.properties` yoksa `GradleException` ile derlemeyi durdurur.
  - `.gitignore#L92-L96`: `*.key`, `*.keystore`, `*.jks`, `*.p12`, `**/android/key.properties` kapsamındadır.
  - `scripts/package_android_release.ps1`: sürümü `pubspec.yaml` (`1.0.0+1`) içinden okur ve `dist/android_release/market_mms_v1.0.0-b1.apk` + `.sha256` + `manifest.json` üretir.
- **Gerçek Komut Doğrulaması:** `flutter build apk --release` çalıştırılmış ve `Release imzalama yapılandırılmadı: android/key.properties bulunamadı.` hatasıyla çıkış kodu `1` dönerek fail-closed doğrulaması geçmiştir. Debug anahtarıyla imzalı sahte Release APK **üretilmemiştir**.
- **Google Drive OAuth:** LAN üzerinden Hub bağlantısı ve eşleştirme Google Drive OAuth gerektirmez; ancak uzak Drive yedekleme (`PAT-13/17`) ve Hibrit Drive LiveSync (`PAT-18`) için `-GoogleDriveWebClientId` parametresi gerekir (`OWNER_ACTION_CHECKLIST.md` `C1/C2`).

---

## 12. APK Tam Dosya Yolu

**`N/A (ÜRETİLMEDİ — Owner Keystore Bekleniyor)`**
Keystore oluşturulduktan sonra üretilecek dosya: `c:\Users\halil\Github\market-pos\dist\android_release\market_mms_v1.0.0-b1.apk`

---

## 13. APK SHA-256

**`N/A (ÜRETİLMEDİ — Owner Keystore Bekleniyor)`**
Üretildiğinde `dist\android_release\market_mms_v1.0.0-b1.apk.sha256` içine otomatik yazılacaktır.

---

## 14. APK İmza Sertifikası

**`N/A (ÜRETİLMEDİ — Owner Keystore Bekleniyor)`**
Üretim keystore (`market_mms_upload.jks`) Owner tarafından oluşturulduğunda `apksigner verify --print-certs` ile doğrulanacaktır.

---

## 15. Hub / TLS / Ağ Bağımlılıkları

1. **Mevcut Geliştirme Bilgisayarı Ağ Profili:** `FiberHGW_ZYEDED` (`Wi-Fi`, IP `192.168.1.158/24`) şu anda **`Public`** profilindedir; sanal adaptörler: `Ethernet 3 (192.168.84.2)`, `Ethernet 2 (192.168.56.1)`, `vEthernet (Default Switch) (172.27.80.1)`.
2. **Firewall Kısıtı:** `scripts/configure_hub_firewall.ps1` kuralları yalnızca `Private` profili ve `-RemoteAddress LocalSubnet` için tanımlar. Geliştirme bilgisayarında firewall ve Wi-Fi profili değiştirilmemiştir. Bu nedenle Android telefondan `192.168.1.158:8947` adresine bağlanmak için Owner'ın Wi-Fi profilini `Private` yapması veya test portları (`TCP 8947`, `UDP 8948`) için kontrollü LAN kuralı açması gerekir.
3. **Android TLS & Cleartext Politikası:** Release APK `usesCleartextTraffic="false"` zorunlu tutar ve `HubConnectionBootstrapper` (`lib/features/sync/application/hub_connection_notifier.dart#L24-L27`) Android'de loopback (`127.0.0.1`) adresini yasaklar. Android'de düz HTTP kullanılamaz; Hub mutlaka `IP:127.0.0.1` + aktif LAN IPv4 SAN içeren geçerli bir `server.crt` + `ca.crt` ile çalıştırılmalıdır.
4. **Hub Olmadan Çalışabilen Özellikler:** Hem Windows hem Android istemcileri yerel Drift SQLite (`WAL`) üzerinde **tam offline** ürün arama, sepet, nakit/kart satış, stok düşüşü, satış geçmişi ve şifreli yerel `.mmsbak` yedekleme işlemlerini Hub olmadan sürdürür ve Outbox'ta (`PENDING`) biriktirir.
5. **Test ve Üretim Ayrımı:** Test Hub sertifikaları (`ca_offline/ca.key`, `hub/certs/*`), `market_master_test.db` ve test secret'ları **hiçbir koşulda** ikinci PC pilot ortamına taşınmamalıdır.

---

## 16. Uçtan Uca Test ve Otomatik Doğrulama Sonuçları

| Test / Kontrol Paketi | Kapsam | Sonuç |
|---|---|---|
| `flutter analyze` (25.11.2026 final) | Tüm Dart/Flutter kaynakları ve yeni testler | **PASS (`No issues found!`)** |
| `flutter test test/features/shell/ test/features/production/` (default) | `main_shell_screen_test`, `platform_ui_separation_test`, `windows_tray_controller_test`, `windows_desktop_settings_card_test`, `pilot_real_market_e2e_test`, `android_release_hardening_test`, `production_readiness_test` (real FFI Outbox controlled-exit testi dahil) | **36 / 36 PASS (0 fail, 0 skip)** *(not: `isolated_live_hub_e2e_test.dart` sonra eklendi ve `MMS_ISOLATED_LIVE_E2E=true` ile ayrıca koşuldu)* |
| `dart test -j 1 test/phase_c_windows_installer_test.dart test/stage3_windows_installer_audit_test.dart` | WiX MSI tabloları, sandbox install/upgrade/rollback/uninstall, `MarketMmsSpike01` koruması, HKLM shortcut, WAL pre-upgrade yedek | **15 / 15 PASS** *(not: paralel çalıştırmada ortak `build\wix_obj` kilidi nedeniyle WiX 1631 alınmıştı; `-j 1` sıralı çalıştırmada %100 geçti)* |
| PowerShell 5.1 AST Denetimi | `mms_installer_engine.ps1` + `scripts/dev_test/*.ps1` (3 yeni betik) | **4 / 4 PASS (0 AST error)** |
| **Canlı İzole E2E (`isolated_live_hub_e2e_test.dart`, `MMS_ISOLATED_LIVE_E2E=true`)** | Canlı `mms_backend.exe` (`TCP 8947`, `UDP 8948`, `production` config, TLS, `market_master_test.db`) karşısında 2 ayrı gerçek FFI SQLite istemci DB'si (`WIN-TEST-*` & `AND-SIM-*`): Pinned TLS `/health`, UDP `8948` discovery, gerçek ECDSA P-256 pairing, Windows→Hub→Android kategori+ürün sync, Android→Hub→Windows ürün sync, barkodla satış & stok düşüşü (`10->8`), offline satış (`8->5`) & Outbox birikimi, yeniden bağlanma & Hub reconciliation, idempotency replay (`200 x-mms-idempotent-replay: true`) ve payload uyuşmazlık reddi (`409`) | **1 / 1 PASS (00:16 +1)** |
| İzole Windows Client Başlatma (`start_isolated_windows_client.ps1 -SmokeCheckSeconds 5`) | `dist\windows_release_v1_0_0_tray\client\market_pos.exe` (`PID 29200`), izole `client_local.db` (`4096 B`), `WM_CLOSE` sonrası sürecin yaşamaya devam etmesi | **SMOKE_PASS** *(GUI görsel kontrolü hariç)* |

---

## 17. Gerçekleştirilmeyen Testler (`NOT RUN / BLOCKED`)

1. **Fiziksel Windows Masaüstü GUI & Tepsi Etkileşimi:** Gerçek oturumda tepsi simgesinin bildirim alanında görünmesi, çift tıkla pencerenin öne gelmesi, sağ tık menü öğelerinin görsel tıklanması, **Otomatik Başlat** sonrası Windows oturum açılışında otomatik açılma ve gerçek "Uygulamadan Çık" tıklaması (otomatik birim/widget ve `WM_CLOSE` süreç testleri yapıldı, görsel masaüstü etkileşimi **yapılmadı**).
2. **Gerçek İkinci PC Windows MSI Kurulumu & SCM/ACL Testleri:** `MarketMmsSpike01` koruması nedeniyle mevcut bilgisayarda MSI çalıştırılmadı; `MarketMMSService` WinSW servis başlatma, Private firewall ve Uninstall sırasında registry temizliği **gerçek PC'de test edilmedi**.
3. **Android Üretim Release APK Derlemesi ve İmza Doğrulaması:** Owner keystore (`android/key.properties`) eksik olduğu için fail-closed durdu (**üretilmedi**).
4. **Fiziksel Android Telefon ↔ İzole Test Hub / Pilot Hub Bağlantısı:** Fiziksel telefon üzerinde APK kurulumu, kamera ile QR tarama, kamera ile barkod satış, telefon Wi-Fi kesme/açma ve çoklu cihaz saha senaryoları **yapılmadı**.
5. **Google Drive Canlı OAuth & Backup/Restore Saha Testi (`BK-PAT-*`):** Gerçek Google hesabı bağlanmadı (`BLOCKED`).

---

## 18. Owner İşlemleri

Ayrıntılı yönergeler için [`OWNER_PROVISIONING_CHECKLIST.md`](./OWNER_PROVISIONING_CHECKLIST.md) dosyasına bakın. Özet:
1. Üretim Android upload keystore (`market_mms_upload.jks`) oluşturma ve `android/key.properties` yapılandırma (parolaları terminal geçmişine düşürmeden).
2. Üretim Hub TLS sertifikaları (`ca.crt`, `server.crt`, `server.key` — `IP:127.0.0.1` + sabit LAN IPv4 SAN; `ca.key` offline kasada).
3. İkinci pilot bilgisayarda ağ profilini `Private` yapma, sabit LAN IP atama ve MSI kurulumunu Yönetici PowerShell/çift tık ile tamamlama.
4. İlk Owner Bootstrap (`POST /api/v1/admin/owner/bootstrap`) ve Hub **Portable Recovery Password** (min. 12 karakter) tanımlama.
5. (Drive kullanılacaksa) Google Cloud OAuth Client ID (Desktop + Android SHA-1 + Web `serverClientId`) tanımlayıp `package_windows_release.ps1` / `package_android_release.ps1` ile paketleme.

---

## 19. Bilinen Riskler

1. **Authenticode İmzasız MSI (`NotSigned`):** Ücretli Windows kod imzalama sertifikası olmadığından pilot PC'de SmartScreen uyarısı çıkar; kurulum öncesi mutlaka `SHA-256` doğrulanmalıdır.
2. **Wi-Fi `Public` Profili & DHCP IP Değişimi:** Hub PC'nin ağ profili `Public` kalırsa `configure_hub_firewall.ps1` kuralları gelen LAN trafiğini geçirmez; Hub IP'si değişirse `server.crt` SAN ve `advertise_host` güncellenmelidir.
3. **`dist\installer\` Paylaşımlı Çıktı Davranışı:** `MarketMMSInstaller.wixproj` / testler aynı `build\wix_bin` klasörünü paylaştığından paralel WiX testleri `-j 1` ile koşulmalıdır.
4. **Android Release Keystore Eksikliği:** `android/key.properties` tanımlanana dek üretim Release APK üretilemez.

---

## 20. Windows Kurulum Talimatları

- **Geliştirme Bilgisayarında İzole Test Ortamı:** Adım adım talimatlar [`DEVELOPMENT_ENVIRONMENT_SETUP.md`](./DEVELOPMENT_ENVIRONMENT_SETUP.md) içindedir (`start_isolated_test_hub.ps1`, `start_isolated_windows_client.ps1`, `stop_isolated_test_hub.ps1`). System Tray üzerinden X/küçültme tepsiye gizler; Ayarlar kartından otomatik başlatma yönetilebilir; güvenli çıkış için tepside **Uygulamadan Çık** veya kartta **Uygulamadan Güvenli Çık** kullanılır.
- **İkinci Pilot Bilgisayara MSI Kurulumu:** Adım adım talimatlar [`PILOT_INSTALLATION_GUIDE.md`](./PILOT_INSTALLATION_GUIDE.md) içindedir. Kaldırma sırasında `%ProgramData%\MarketMMS` (DB/yedek/sertifikalar) **korunur**, `MarketMMSClient` otomatik başlatma kaydı temizlenir.

---

## 21. Android Kurulum Talimatları

1. Owner tarafından [`OWNER_PROVISIONING_CHECKLIST.md`](./OWNER_PROVISIONING_CHECKLIST.md) §1 adımlarıyla `market_mms_upload.jks` ve `android/key.properties` hazırlanır.
2. `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\package_android_release.ps1` (Drive varsa `-GoogleDriveWebClientId "<WEB_CLIENT_ID>"`) komutuyla `dist\android_release\market_mms_v1.0.0-b1.apk` üretilir.
3. APK `adb install` veya USB üzerinden Android (7.0+ / `minSdk 24+`) cihaza aktarılıp kurulur.
4. İlk açılışta mağaza kurulumu tamamlanır; Windows uygulamasındaki **Eşleştirme QR** kodu Android cihazdan taranarak TLS CA pin ve ECDSA P-256 cihaz token'ı alınır.
5. **Önemli Ayrım:** Geliştirme bilgisayarındaki izole Test Hub (`TCP 8947`) ile denemek için geliştirme bilgisayarının Wi-Fi profili/güvenlik duvarının `8947/8948` LAN trafiğine izin vermesi ve Android cihazın aynı Wi-Fi'de olması gerekir (`usesCleartextTraffic=false` korunduğundan mutlaka Test CA üzerinden `https://<LAN-IP>:8947` ile bağlanılır). Google Drive OAuth yalnızca uzak Drive yedekleme ve Drive LiveSync için gereklidir; yerel LAN Hub senkronizasyonu OAuth olmadan çalışır.

---

## 22. Nihai Karar

### **`CONDITIONAL GO`**

- **Geliştirme Ortamında İzole Testler:** **GO** — İzole Test Hub (`8947/8948`), izole Windows Client, System Tray mimarisi, kontrollü çıkış, otomatik başlatma ve 2-istemcili canlı E2E senkronizasyon döngüsü başarıyla çalıştırılmış ve doğrulanmıştır.
- **İkinci PC Pilot & Fiziksel Saha Kullanımı:** **CONDITIONAL GO (Owner Ön Koşullarına Bağlı)** — Aşağıdaki koşullar tamamlanmadan pilot mağaza kullanımına geçilemez:
  1. Owner'ın üretim Android keystore'u oluşturup imzalı `market_mms_v1.0.0-b1.apk` paketini üretmesi,
  2. Pilot Windows PC'de temiz MSI kurulumu + üretim TLS sertifikalarının (`ca.crt`, `server.crt`, `server.key`) yerleştirilmesi + `Private` ağ profili ve sabit LAN IP ayarlanması,
  3. İlk Owner Bootstrap + Portable Recovery Password tanımlanması,
  4. [`PILOT_ACCEPTANCE_TEST_PLAN.md`](./PILOT_ACCEPTANCE_TEST_PLAN.md) üzerindeki 15 fiziksel kabul kriterinin ve Windows masaüstü System Tray görsel doğrulamasının tamamlanması.
