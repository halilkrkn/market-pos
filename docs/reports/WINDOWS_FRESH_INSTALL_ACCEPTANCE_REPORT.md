# MARKET MMS — Windows Fresh Install, Rollback & Uninstall Kabul Raporu (`WINDOWS_FRESH_INSTALL_ACCEPTANCE_REPORT`)

**Tarih:** 2026-11-27

**Kapsam:** Stage H — İzole Yaşam Döngüsü Doğrulaması (`-IsolatedSandboxVerification`, `20/20`) ve Temiz Windows VM / Yükseltilmiş Kurulum Anahtar-Teslim Otomasyonu (`run_vm_fresh_install_acceptance.ps1`)

**Durum:** İzole sandbox uçtan uca yaşam döngüsü (Fresh Install → Deferred TLS → Sertifika Provizyonu → Canlı `--config` HTTPS Hub `8947` → Upgrade Fault/Rollback → Uninstall `PURGE_USER_DATA=0` → Reinstall) **PASS (`20/20`)**; canlı yükseltilmiş (`Administrator`) Windows VM / `msiexec /i` kurulumu bu konakta **BLOCKED** (yükseltilmiş temiz VM / fiziksel Windows testi bekliyor).

---

## 1. Gerçek Ortam ve Sanallaştırma Kısıtı

Konak ortam doğrulaması (`Stage A` / `Stage D`):
- **Kullanıcı Yetkisi:** `IS_ADMIN=False` (`HALILKRKN\halil`).
- **Sanallaştırma Durumu:** `WindowsSandbox=NOT_FOUND`, `vboxmanage=NOT_FOUND`, `qemu=NOT_FOUND`, `Get-VM` boş (`vmms` servisi mevcut ancak Windows ISO / temel VHDX imajı yok), `wsl=docker-desktop Stopped`.
- **Konak Dokunulmazlığı:** Konak üzerinde MSI çalıştırılmadı, `MarketMMSService` ve `MarketMmsSpike01` oluşturulmadı, `C:\ProgramData\MarketMMS` değiştirilmedi (`SIM_20_HOST_SERVICES_UNTOUCHED=PASS`).

Bu nedenle `scripts/dev_test/run_vm_fresh_install_acceptance.ps1` (`NON_ASCII=0`, `PARSE_ERRORS=0`) iki modlu olarak geliştirildi:
1. **`-IsolatedSandboxVerification`:** Non-admin konak üzerinde `%LOCALAPPDATA%\MarketMMS_Isolated_Test\vm_acceptance_sim\` içinde tamamen izole biçimde yürütüldü (`20/20 PASS`).
2. **`-LiveVmExecution -ConfirmCleanTestVm`:** Temiz Windows 10/11 VM veya test makinesinde yükseltilmiş PowerShell içinden `msiexec /i`, gerçek SCM `MarketMMSService` (`HKLM:\...\Parameters` kimlik damgası), `NT SERVICE\MarketMMSService` ACL, Firewall `8945`/`8946`, `https://127.0.0.1:8945/health`, uninstall (`PURGE_USER_DATA=0`) ve reinstall çalıştırmak üzere hazır beklemektedir.

---

## 2. İzole Yaşam Döngüsü Doğrulama Sonuçları (`20/20 PASS`, `VM_SIM_EXIT=0`)

Komut: `scripts\dev_test\run_vm_fresh_install_acceptance.ps1 -IsolatedSandboxVerification`

| Check ID | Doğrulanan Kriter | Gerçek Gözlem / Çıktı | Sonuç |
|---|---|---|---:|
| `SIM_01_FRESH_INSTALL_EXIT0` | Deferred TLS Fresh Install (`1.0.0`) | `exit=0` | **PASS** |
| `SIM_02_PROGRAMDATA_DIRS` | 11 standart dizin (`bin`, `bin\broker`, `bin\lib`, `lib`, `config`, `certs`, `data`, `security`, `logs`, `backups`, `run`) | `checked=11, missing=0` | **PASS** |
| `SIM_03_REQUIRED_FILES` | `install_manifest.json`, `hub_config.json`, `admin_secret.txt`, `MarketMMSService.xml`, `sandbox_scm.json` | Tümü mevcut | **PASS** |
| `SIM_04_DEFERRED_TLS_STATE` | `ALLOW_DEFERRED_TLS_START=1` ile başlangıç erteleme | `state=PENDING_TLS_PROVISIONING, scm=Stopped` | **PASS** |
| `SIM_05_HUB_CONFIG_PORTS` | Üretilen `hub_config.json` port ve TLS alanları | `port=8947, disc=8948, tls.enabled=true` | **PASS** |
| `SIM_06_SCM_IDENTITY_STAMP` | B-1 deterministik SCM damgası | `ver=1.0.0`, `mms_xml_sha256` dolu | **PASS** |
| `SIM_07_NO_SPIKE_SERVICE` | Yalnızca `MarketMMSService`, `MarketMmsSpike01` yok | `service=MarketMMSService` | **PASS** |
| `SIM_08_SECRET_FILE_NONEMPTY` | Rastgele `admin_secret.txt` üretimi | `bytes=44` | **PASS** |
| `SIM_09_TLS_CERT_PROVISION` | `OpenSSL 3.5.9` ile `ca.crt` + `server.crt`/`server.key` (`127.0.0.1`, `10.0.2.2`, `localhost`) | `ExitCode 0` | **PASS** |
| `SIM_10_LIVE_HUB_CONFIG_START` | Üretilen `--config=hub_config.json` ile canlı `bin\mms_backend.exe` açılışı | `pid=9252` (port `8947` bağlandı) | **PASS** |
| `SIM_11_LIVE_TLS_HEALTH_UP` | Pinli `MmsTlsHealthProbe::VerifyHttpsHealth` | `status=UP` | **PASS** |
| `SIM_12_HUB_DB_INITIALIZED` | Canlı Hub açılışıyla `data\market_master.db` şema başlatımı | `bytes=4096` | **PASS** |
| `SIM_13_UPGRADE_FAULT_FAIL_CLOSED` | `1.1.0` Upgrade sırasında `Migration` hata enjeksiyonu | `exit=74` | **PASS** |
| `SIM_14_ROLLBACK_RESTORED_V10` | MSI `Rollback` ile `1.0.0` ve DB korunumu | `rb_exit=0, scm_ver=1.0.0`, DB `4096` B | **PASS** |
| `SIM_15_UNINSTALL_EXIT0` | `Uninstall` (`PURGE_USER_DATA=0`) | `exit=0` | **PASS** |
| `SIM_16_UNINSTALL_PRESERVES_DATA` | Kaldırma sonrası `data`, `backups` sentinel, `security`, `certs` korunumu | Tümü korundu | **PASS** |
| `SIM_17_UNINSTALL_REMOVES_BIN` | Runtime çalıştırılabilir dosya temizliği | `bin\mms_backend.exe removed` | **PASS** |
| `SIM_18_REINSTALL_EXIT0` | Uninstall sonrası temiz `1.0.0` Reinstall | `exit=0`, `mms_app_version=1.0.0` | **PASS** |
| `SIM_19_REINSTALL_DATA_INTACT` | Reinstall sonrası mevcut DB ve sentinel yedek korunumu | `db=4096` B + sentinel sağlam | **PASS** |
| `SIM_20_HOST_SERVICES_UNTOUCHED` | Konak SCM koruması | `MarketMMSService` ve `MarketMmsSpike01` konakta yok | **PASS** |

**Çıkış & Port Temizliği:** `VM_SIM_EXIT=0`, `TCP_8947_LISTEN=0`, `UDP_8948_EP=0`, `MMS_BACKEND_PROCS=0`.

---

## 3. Açık Engel (Live Elevated VM Execution)

- **`BLOCKED`:** Gerçek `msiexec /i dist\installer_v1_0_0_tray\MarketMMS-Setup-1.0.0-x64.msi` çalıştırması, UAC / `Administrator` yetkili gerçek Windows SCM servisi (`NT SERVICE\MarketMMSService`), `HKLM:\...\Parameters` kayıt defteri damgası, `%PROGRAMDATA%\MarketMMS` gerçek Service SID ACL kuralları ve Windows Defender Firewall `8945 TCP`/`8946 UDP` kuralları için temiz bir Windows VM veya hedef test PC'de yükseltilmiş PowerShell ile:
  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\dev_test\run_vm_fresh_install_acceptance.ps1 -LiveVmExecution -ConfirmCleanTestVm
  ```
  çalıştırılmalıdır.
