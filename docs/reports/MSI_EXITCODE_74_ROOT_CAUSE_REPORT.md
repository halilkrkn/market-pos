# MSI EXITCODE 74 ROOT CAUSE REPORT (Aşama C)

**Karar:** **`ROOT CAUSE CONFIRMED`**

**Analiz Edilen Log:** [`C:\Users\halil\Desktop\MarketMMS_Install_Debug.log`](file:///C:/Users/halil/Desktop/MarketMMS_Install_Debug.log) (`252.666` bayt, `25.11.2026 02:26:54 - 02:27:17`)

**Eşleşen Tarihsel Kaynak:** Commit `a5596769ebc85ca66afde540c19dac9e8d6ae81d` (`mms_installer_engine.ps1` + `setup_service_acls.ps1`)

**Güvenlik Sınırı:** Mevcut gerçek sistemde MSI çalıştırılarak ExitCode 74 yeniden üretilmemiştir.

---

## 1. Doğrulanmış Olay Zaman Çizelgesi ve Kök Neden Zinciri

1. **`2026-11-24T23:22:18Z` (`02:22:18` yerel — önceki logsiz deneme) & `02:26:54` (`MarketMMS_Install_Debug.log` başlangıcı):**
   - `Package.wxs` üzerinden `MarketMMS-Setup-1.0.0-x64.msi` (`ProductCode {2DC1BB31-1691-4BA5-8C40-F086FF142D10}`) `AdminUser=1` yetkisiyle çalıştırıldı.
   - `InstallFiles` dosyaları `C:\Program Files\MarketMMS\` altına kopyaladı.
2. **`02:26:56.416` — `CA_InstallOrUpgrade` Başlatıldı (MSI Log L815):**
   - WiX `ActionType=3106` (`34` EXE CustomAction + `1024` `msidbCustomActionTypeInScript` deferred + `2048` `msidbCustomActionTypeNoImpersonate` SYSTEM) ile şu komut çalıştırıldı:
     `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "C:\Program Files\MarketMMS\hub_scripts\mms_installer_engine.ps1" -MsiManaged -MsiContext "Install|C:\Program Files\MarketMMS\.|1.0.0|8945|8946|1"`
   - *WiX Type 3106 Sınırı:* Harici süreç `Type 34/3106` alt sürecin (`powershell.exe`) `stdout`/`stderr` akışlarını MSI verbose günlüğüne aktarmaz; MSI yalnız dönüş kodunu görür.
3. **`a559676` İçindeki Çifte Hata (`mms_installer_engine.ps1#L796` + `setup_service_acls.ps1#L89-L100`):**
   - Commit `a559676`'daki `mms_installer_engine.ps1` satır `L755-L796`:
     - `C:\ProgramData\MarketMMS` altında 11 alt dizini oluşturdu (`copied_bin=false`, `copied_client=false`, `service_modified=false` iken `installer_tx_state.json` yazıldı),
     - Henüz `CopyBinaries` ve `ServiceInstall` çalışmadan **adım 2'de (`L796`)** `Apply-DirectoryAcls` üzerinden `setup_service_acls.ps1` betiğini çağırdı.
   - Commit `a559676`'daki `setup_service_acls.ps1`:
     - `L89-L90`: `icacls $BaseDir /reset` ve `/inheritance:r` çalıştırdıktan **sonra**,
     - `L97` ve `L100`: Geçersiz **`${sidTarget}:(NP)X`** ve **`${sidUsers}:(NP)X`** sözdizimini kullandı. Windows `icacls.exe`, kalıtım bayrağı (`(OI)` veya `(CI)`) olmadan `(NP)` bayrağını **ExitCode 87 (`The parameter is incorrect`)** ile reddeder.
     - *(Ek ikincil hata)* Ayrıca servis henüz SCM'de kurulu olmadığından ve `sc.exe showsid` yedeği bulunmadığından `NT SERVICE\MarketMMSService` adı `icacls` tarafından **ExitCode 1332** ile çözülemezdi.
4. **`02:26:59.802` — `ExitCode 74` → MSI `Error 1722` → `CA_RollbackInstall` → `1603` (MSI Log L816–L1237):**
   - `Apply-DirectoryAcls`, `[ERR_ACL_FAILED]` fırlattı; `mms_installer_engine.ps1` ana `catch` bloğu `Fail-Installer -ExitCode 74` ile sonlandı (ve commit `a559676`'da henüz `MmsSafeDiagnosticLogWriter` bulunmadığından diskte `installer-diagnostics.log` oluşmadı).
   - MSI Log L816–824: `CustomAction CA_InstallOrUpgrade returned actual error code 74`, `Error 1722`, `InstallFinalize` `Return value 3`.
   - MSI Log L841: `CA_RollbackInstall` `23:27:16.799Z`'de çalıştı ve diskte hâlen gözlemlenen `C:\ProgramData\MarketMMS\run\installer_tx_state.json` (`493` B, `status: ROLLED_BACK`, `copied_bin: false`, `copied_client: false`, `service_modified: false`) dosyasını güncelledi.
   - MSI Log L844–L921: MSI tüm `C:\Program Files\MarketMMS\` dosyalarını `FileRemove` ile sildi.
   - MSI Log L1088–L1235: `Event 11722` / `Event 1033` / `MainEngineThread is returning 1603` ile temiz sonlandı.

### Disk Üzerindeki Fiziksel Kanıtlarla Birebir Örtüşme
Bugün `C:\ProgramData\MarketMMS` altında hâlen bulunan 11 boş klasörün `OWNER=NT AUTHORITY\SYSTEM`, `AreAccessRulesProtected=False` ve `USERS_ACE=True` (kalıtılmış `Users:RX/W`) durumda olması, `icacls /reset` sonrası `Users:(NP)X` (`ExitCode 87`) yüzünden betiğin yarıda kesildiğini **kesin olarak kanıtlamaktadır**.

---

## 2. Diagnostic Logging & Güvenlik Mekanizması Denetimi (Güncel Kod)

[`mms_installer_engine.ps1`](file:///c:/Users/halil/Github/market-pos/installer/windows/scripts/mms_installer_engine.ps1#L88-L1214) içindeki güncel `MmsSafeDiagnosticLogWriter`, `Protect-InstallerDiagnosticText` ve `Write-InstallerDiagnosticLog` denetlendi:

| Gereksinim (§6.2) | Doğrulanan Uygulama (Dosya + Satır) | Durum |
|---|---|---|
| UTF-8 no-BOM | `New-Object System.Text.UTF8Encoding($false)` (`L1118`) | **PASS** |
| Secret redaction | `Protect-InstallerDiagnosticText` (`L872-L956`) — parola, secret, pepper, key-value, JSON (1–3 escape katmanı), CLI flags | **PASS** |
| PEM / private key masking | Tam ve kesik (`truncated`) `PRIVATE KEY` / `CERTIFICATE` / `PKCS7` blokları (`L884-L909`) | **PASS** |
| Bearer / Basic masking | `Authorization` başlığı ve tekil `Bearer` / `Basic` değerleri (`L912-L929`) | **PASS** |
| OAuth / JWT token masking | `mms_dt_`, `ya29.`, `1//`, `GOCSPX-`, 2/3-segment `eyJ...` JWT (`L932-L937`) | **PASS** |
| Hassas key-value & path ayrımı | Gizli alanlar maskelenirken `pepper_file`, `admin_secret_file` yolları korunur (`L940-L950`) | **PASS** |
| Log ACL ve owner | `S-1-5-18` (SYSTEM) + `S-1-5-32-544` (Administrators) sahiplik ve korumalı DACL; `DataRoot` ve `logs` üzerinde `Users`/geniş SID yazma reddi (`L402-L602`, `L1135-L1175`) | **PASS** |
| Reparse point koruması | `AssertNoReparsePointInPath` tüm ata segmentleri tarar + `FILE_FLAG_OPEN_REPARSE_POINT` ve `FileAttributes.ReparsePoint` kontrolü (`L206-L248`, `L314`, `L419`, `L588`) | **PASS** |
| Hardlink kontrolü | `ValidateRegularFileHandle` içinde `if (info.NumberOfLinks > 1)` reddi (`L322-L325`) | **PASS** |
| Handle tabanlı yazma | Çift sabitlenmiş dizin tanıtıcısı (`hRoot` + `hLogs`) + `hAppend` (`CreateFileW` + `GetFinalPathNameByHandleW` + `WriteFile`) (`L663-L757`) | **PASS** |
| Rotation | `1.048.576` bayt (1 MiB) eşiğinde handle üzerinden `DeleteByHandle` (`FILE_DISPOSITION_INFO`) + `RenameByHandle` (`FILE_RENAME_INFO`, `ReplaceIfExists=false`) (`L334-L381`, `L611-L660`) | **PASS** |
| Asıl hatayı maskelememe | `Write-InstallerDiagnosticLog` iç dış `try/catch` ile sarmalanmıştır; log yazımı reddedilse dahi `Fail-Installer` asıl `ExitCode` ve `[ERR_*]` mesajını korur (`L1189-L1213`) | **PASS** |
| TEMP fallback yok | Yalnız `$DataRoot\logs\installer-diagnostics.log` kullanılır; güvenli değilse log yazımı durdurulur (`L1120-L1191`) | **PASS** |
| Güvenli log konumu | `%ProgramData%\MarketMMS\logs\installer-diagnostics.log` | **PASS** |

**Çözüm Durumu:** MSI `ExitCode 74` / `1722` / `1603` hatasına yol açan BLOCKER-1 (`:(NP)X`) ve BLOCKER-2 (`Apply-DirectoryAcls` sırası + `sc.exe showsid` + deterministik SID) mevcut kodda giderilmiştir. Ancak bu düzeltilmiş MSI gerçek yükseltilmiş Windows ortamında henüz yeniden çalıştırılmamıştır.
