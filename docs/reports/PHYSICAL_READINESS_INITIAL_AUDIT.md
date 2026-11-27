# PHYSICAL READINESS INITIAL AUDIT (Aşama A)

**Tarih:** 2026-11-27

**Çalışma Dizini:** `c:\Users\halil\Github\market-pos`

**Denetim Türü:** Salt okunur başlangıç durum tespiti

---

## 1. Git ve Çalışma Ağacı Durumu

| Özellik | Değer |
|---|---|
| **Dal (`Branch`)** | `main` |
| **`HEAD` Commit** | `a5596769ebc85ca66afde540c19dac9e8d6ae81d` (`feat: complete MARKET MMS core implementation and pilot readiness`) |
| **Staged Dosya Sayısı** | `0` |
| **Staged Olmayan (Unstaged) Değişiklikler** | `installer/windows/scripts/mms_installer_engine.ps1`, `lib/features/diagnostics/presentation/screens/diagnostics_view.dart`, `lib/features/shell/presentation/screens/main_shell_screen.dart`, `lib/main.dart`, `test_spikes/spike_01_backend/scripts/setup_service_acls.ps1`, `test_spikes/spike_01_backend/test/phase_c_windows_installer_test.dart`, `test_spikes/spike_01_backend/test/stage3_windows_installer_audit_test.dart`, `windows/runner/CMakeLists.txt`, `windows/runner/flutter_window.cpp`, `windows/runner/flutter_window.h` |
| **Önemli Untracked Artefaktlar** | `docs/reports/*.md`, `lib/features/shell/presentation/windows/`, `scripts/dev_test/`, `test/features/production/isolated_live_hub_e2e_test.dart`, `test/features/shell/windows_*_test.dart`, `windows/runner/windows_shell_tray.{cpp,h}`, korunan 4 dosya |

---

## 2. Korunan 4 Untracked Dosya Başlangıç SHA-256 Kaydı

| Dosya | Boyut (Bayt) | SHA-256 |
|---|---|---|
| `.vscode/settings.json` | `145` | `70CE85ED5039EE83FA3C9260E56DF3BBCD60C3549AD0148A114F5BBC09A5F8EA` |
| `run_windows_client.bat` | `384` | `10BBC6D6FCA0D8ECAAC141509B7BA842B8B340D5C7191F4D6BECE7EBD5F2567D` |
| `start_master_hub.bat` | `1341` | `03D0A2A493F8A49ECF3E72C59C510233401EC5C9A563B4BE58B22CBA34D9E2DD` |
| `stop_master_hub.bat` | `160` | `C18C9081A5A49941FE734C65A815366E2F90A913A7E5E10E24B883E41EB33677` |

---

## 3. Ana Bileşen ve Doküman Eşleme Envanteri

| İstenen Artefakt | Depodaki Gerçek Konum / Durum | İlk Bulgu |
|---|---|---|
| Installer Motoru | [`installer/windows/scripts/mms_installer_engine.ps1`](file:///c:/Users/halil/Github/market-pos/installer/windows/scripts/mms_installer_engine.ps1) | `B-1` ve `A-6` güncellemeleri mevcut; **ancak** canlı Windows SCM dalında `Resolve-ManifestFallbackServiceModified` yalnız `Get-Service` varlığına bakıyor (`FAIL` — Aşama B'de düzeltilecek). |
| ACL Betiği *(not)* | [`test_spikes/spike_01_backend/scripts/setup_service_acls.ps1`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/scripts/setup_service_acls.ps1) | *(Yol notu: `installer/windows/scripts/` yerine `test_spikes/spike_01_backend/scripts/` altında bulunur ve WiX staging tarafından `hub_scripts\` içine paketlenir.)* BLOCKER-1/2, M-4, L-1 düzeltilmiş, AST/ASCII temiz. |
| WiX Paketi | [`installer/windows/Package.wxs`](file:///c:/Users/halil/Github/market-pos/installer/windows/Package.wxs) | `CA_RollbackInstall` -> `CA_InstallOrUpgrade` -> `CA_CommitInstall` sırası doğru; `UpgradeCode` sabit, `PURGE_USER_DATA=0`, `ALLOW_DEFERRED_TLS_START=1`. |
| Installer Testleri | [`phase_c_windows_installer_test.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/test/phase_c_windows_installer_test.dart), [`stage3_windows_installer_audit_test.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/test/stage3_windows_installer_audit_test.dart) | Son koşum: **`30/30 PASS`** (`16 + 14`). Canlı Windows SCM yerine JSON sandbox sürüm alanını sınamaktadır. |
| Mevcut MSI | `dist/installer_v1_0_0_tray/MarketMMS-Setup-1.0.0-x64.msi` | `22.814.720` B · SHA-256 `7B1E3644A5DDA7C8E2C8FBE9E1EF380762FCB92F96C8EA4E7CE6F6E22449E27E` · `NotSigned` (B-1 remediation sonrası yeniden derlenecek). |
| Stage 1–5 Raporları | [`docs/FINAL_PILOT_READINESS_REPORT.md`](file:///c:/Users/halil/Github/market-pos/docs/FINAL_PILOT_READINESS_REPORT.md), [`docs/IMPLEMENTATION/PHASE_B5_PILOT_ACCEPTANCE_REPORT.md`](file:///c:/Users/halil/Github/market-pos/docs/IMPLEMENTATION/PHASE_B5_PILOT_ACCEPTANCE_REPORT.md), [`docs/reports/INSTALLATION_READINESS_AND_EXECUTION_REPORT.md`](file:///c:/Users/halil/Github/market-pos/docs/reports/INSTALLATION_READINESS_AND_EXECUTION_REPORT.md) | 23–25 Kasım tarihli raporlar otomatik testlerin geçtiğini (`898/898` + `36` + `15` + izole 2-istemci E2E `1/1`), ancak Android Release keystore (`B1`), ticari/pilot TLS (`B2`), Drive OAuth (`C1/C2`) ve gerçek fiziksel donanım testlerinin **`BLOCKED`** olduğunu göstermektedir. |
| Kabul Planı ve Owner Listesi | [`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`](file:///c:/Users/halil/Github/market-pos/PHYSICAL_ACCEPTANCE_TEST_PLAN.md), [`OWNER_ACTION_CHECKLIST.md`](file:///c:/Users/halil/Github/market-pos/OWNER_ACTION_CHECKLIST.md), [`docs/reports/OWNER_PROVISIONING_CHECKLIST.md`](file:///c:/Users/halil/Github/market-pos/docs/reports/OWNER_PROVISIONING_CHECKLIST.md), [`docs/reports/PILOT_ACCEPTANCE_TEST_PLAN.md`](file:///c:/Users/halil/Github/market-pos/docs/reports/PILOT_ACCEPTANCE_TEST_PLAN.md) | Tüm fiziksel kabul testleri `NOT RUN / PENDING PHYSICAL TEST` durumundadır. Installer (`PAT-21..26` / upgrade / rollback / standard user) kapsamı Aşama L'de `PHYSICAL_ACCEPTANCE_TEST_PLAN.md` yapısına eklenecektir. |

---

## 4. Araç ve Sanallaştırma Kapasitesi (Ana Makine)

| Yetenek | Durum | Not |
|---|---|---|
| **Yönetici Yetkisi (`IS_ADMIN`)** | `False` (`HALILKRKN\halil`) | Host Windows 11 Pro Build `22631`; yükseltilmemiş oturum — host SCM/Program Files/Firewall/ProgramData değiştirilmez. |
| **Hyper-V / VM / Sandbox** | `vmms = Running`, `Get-VM = Boş`, `WindowsSandbox = NOT_FOUND`, `VirtualBox = NOT_FOUND`, `QEMU = NOT_FOUND` | Hazır temiz Windows VM imajı/ISO'su bulunmadığından bu makinede sıfırdan temiz Windows VM oluşturulamaz; fiziksel ikinci PC / temiz VM kurulumu `BLOCKED` kalacaktır, ancak script otomasyonu ve izole Windows doğrulaması tamamlanacaktır. |
| **Android SDK & Emülatör** | `adb.exe` mevcut, AVD: `flutter_emulator`, `flutter_emulator_2` (`adb devices` boş) | Aşama I'da emülatör başlatma ve APK doğrulama denenecektir. |
| **SignTool & OpenSSL** | `signtool.exe` (`10.0.26100.0\x64`) ve `C:\OpenSSL\bin\openssl.exe` mevcut | `TEST_ONLY` TLS CA ve `TEST_ONLY` self-signed MSI imzalama yapılabilir. |
