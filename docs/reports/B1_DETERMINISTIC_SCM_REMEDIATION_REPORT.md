# MARKET MMS — B-1 Deterministik SCM Kimlik Damgası İyileştirme Raporu

**Tarih:** 2026-11-27

**Kapsam:** Stage B — Windows MSI Kurulum / Yükseltme / Geri Alma (Rollback) Sırasında Deterministik Windows SCM Sahiplik ve Kimlik Doğrulaması (`B-1`)

**Durum:** Otomatik sandbox ve `msi.dll` testleri %100 geçti; canlı yükseltilmiş (`Administrator`) Windows SCM / Registry `HKLM:\SYSTEM\CurrentControlSet\Services` doğrulaması bu non-admin konakta **BLOCKED** (elevated VM/fiziksel test bekliyor).

---

## 1. Önceki Durum ve Kök Sorun Analizi

`Resolve-ManifestFallbackServiceModified` fonksiyonunun önceki sürümü, Upgrade sırasında transaction state dosyasının bozulması (`installer_tx_state.json`) veya Step 5 çevresindeki kesintilerde SCM servisinin eski kurulum (`1.0.0`) tarafından mı yoksa yeni yükseltme adımı (`1.1.0`) tarafından mı oluşturulduğunu yalnızca dosya/klasör kalıntılarına bakarak **sezgisel (heuristic)** olarak kestirmeye çalışıyordu:

1. `bin.previous` oluşturulduysa ancak `ServiceInstall` henüz çalışmadan (`PrePreviousBackup`, `UpgradeInterrupt`, `Migration`, `ServiceInstall`) kurulum başarısız olduysa, eski servis kaydı hâlâ `MarketMMSService` olarak SCM'de duruyor olabilirken yanlış karar dalında servisin kaldırılıp yeniden kurulması veya tersi riski vardı.
2. Yabancı bir yazılıma ait aynı isimli veya farklı `ImagePath`'li bir servis, yanlış `ObjectName` (`NT AUTHORITY\LocalService` yerine `LocalSystem`), yanlış `ServiceSidType` (`UNRESTRICTED` dışı), `DELETE_PENDING` (Windows Win32 Exit `1072`) durumu ya da damgasız/değiştirilmiş `MarketMMSService.xml` durumunda fail-closed durdurma mekanizması eksikti.
3. `sc.exe qc`, `Stop`, `Delete` ve WinSW `install` çağrılarının doğrulanmış son durum kontrolleri ve zaman aşımlı servis kaldırma/yeniden yükleme döngüsü deterministik bir kimlik damgasına bağlı değildi.

---

## 2. Uygulanan Deterministik SCM Kimlik Damgası Mimarisi

İyileştirme [`mms_installer_engine.ps1`](file:///c:/Users/halil/Github/market-pos/installer/windows/scripts/mms_installer_engine.ps1) (`4541` satır, SHA-256 `A8FBE08DE24A6C6734CB78B62388F73A355A60EFA5C46F981A9DB090FB26944A`, Pure ASCII `NON_ASCII=0`, PowerShell AST `PARSE_ERRORS=0`) üzerinde uygulandı:

### 2.1. Kimlik Damgası Alanları
Servis kurulumu ve geri yüklemesi başarıyla tamamlandığında hem canlı Windows SCM altında `HKLM:\SYSTEM\CurrentControlSet\Services\<ServiceName>\Parameters` anahtarına hem de `-TestSandboxMode` altında `run\sandbox_scm.json` içine atomik (`.tmp` → `Move-Item -Force`) olarak şu alanlar yazılır ve geri okunarak doğrulanır:
- `MmsAppVersion` (`mms_app_version`): Servisi kuran veya yükselten uygulama sürümü (`1.0.0`, `1.1.0` vb.).
- `MmsXmlSha256` (`mms_xml_sha256`): Kurulan `bin\MarketMMSService.xml` dosyasının büyük harfli SHA-256 özeti (`Get-FileSha256Upper`).
- `MmsTxId` (`mms_tx_id`): İlgili kurulum/yükseltme işleminin GUID `tx_id` değeri (`$script:Tx.TxId` ve `installer_tx_state.json` `tx_id` alanı).
- `MmsPreviousVersion` (`mms_previous_version`): Upgrade sırasında bir önceki sürümün kimliği.

### 2.2. Eklenen ve Güncellenen Çekirdek Fonksiyonlar
| Fonksiyon / Değişiklik | Satır | Görev ve Güvenlik Kontrolü |
|---|---:|---|
| `$FaultInjectionStage` genişletmesi | `L23-24` | `"PrePreviousBackup"`, `"ScmStamp"`, `"ServiceStop"`, `"ServiceUninstall"`, `"ScmDeletePending"` hata enjeksiyon noktaları eklendi. |
| `Write-SandboxService` & `Add-SandboxInstallScmOp` | `L2016`, `L2083` | Sandbox SCM durumunu atomik `.tmp` üzerinden yazar; `-ClearStamp` verilmedikçe damga alanlarını korur ve işlem günlüğüne (`sandbox_scm_ops.log` / `sandbox_install_scm_ops.log`) yazar. |
| `Get-FileSha256Upper` | `L2357` | `MarketMMSService.xml` için kanonik büyük harfli SHA-256 üretir. |
| `Test-IsExpectedLocalServiceAccount` | `L2369` | Yalnızca `NT AUTHORITY\LocalService` (ve eşdeğeri `S-1-5-19` / lokalize biçimler) hesabını kabul eder; `LocalSystem` vb. yüksek yetkili hesapları reddeder. |
| `Read-ScmServiceIdentitySnapshot` | `L2414` | `Get-Service`, `HKLM:\...\Services\<Name>` (`ImagePath`, `ObjectName`, `ServiceSidType`, `DeleteFlag`, `Parameters\{MmsAppVersion, MmsXmlSha256, MmsTxId, MmsPreviousVersion}`) ve `sc.exe qc` (`1072` `DELETE_PENDING`) verilerini tek snapshot nesnesinde toplar. |
| `Write-ScmServiceIdentityStamp` | `L2537` | Servis kurulumundan hemen sonra kimlik damgasını yazar ve geri okuyarak doğrular (`ScmStamp` hata noktası dahil). |
| `Invoke-VerifiedServiceStop` | `L2624` | Yabancı `ImagePath` koruması, `DELETE_PENDING` reddi, `$LASTEXITCODE` kontrolü, `WaitForStatus('Stopped')` ve tekrar durum sorgusu yapar. |
| `Invoke-VerifiedServiceUninstall` | `L2680` | Yabancı servisleri ASLA kaldırmaz; `$LASTEXITCODE` kontrolü ve 15 saniye / 250 ms aralıklarla SCM + Registry anahtarı silinme doğrulaması yapar. |
| `Resolve-DeterministicScmDisposition` | `L2752` | Tüm geri alma kararlarını 6 deterministik çıktıya indirger: `ABSENT_CLEAN`, `ABSENT_NEEDS_INSTALL`, `FAIL_CLOSED`, `PRESERVE_UNMODIFIED_PREVIOUS`, `REMOVE_NEW_ONLY`, `REMOVE_NEW_AND_REINSTALL_PREVIOUS`. |
| `Resolve-ManifestFallbackServiceModified` | `L2850` | Bozuk `tx_state` + manifest fallback durumunda `Resolve-DeterministicScmDisposition` sonucuna dayanarak fail-closed çalışır (`ERR_SCM_STAMP_MISSING` vb.). |
| `Invoke-MarketMmsRollback` | `L3364` | `.previous` temizlenmeden önce `Resolve-DeterministicScmDisposition` kararını alır; `PRESERVE_UNMODIFIED_PREVIOUS` durumda eski servisi kaldırmadan doğrular (`verify_existing`) ve yalnızca önceden çalışıyorsa başlatır; `FAIL_CLOSED` durumda yıkıcı Step 2–4 temizliğini atlar; yeniden kurulumda damgayı tazeler; `start_service` yalnızca tüm kapılar geçerse çalışır. |
| Upgrade Step 1 & Step 5 | `L4187`, `L4338` | Upgrade Step 1'de yalnızca `Invoke-VerifiedServiceStop` yapılır (erken uninstall kaldırıldı). Step 5'te eski servis kaldırılıp yeni servis kurulur ve `Write-ScmServiceIdentityStamp` ile damgalanır. |

---

## 3. Senaryo Matrisi (`Test 25` ve `Test 27`)

[`phase_c_windows_installer_test.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/test/phase_c_windows_installer_test.dart) içinde `Test 25` (`L3106`) damga uyumu için güncellendi ve `Test 27` (`L3745-4050`) eklendi:

- **Senaryo A (`PrePreviousBackup`):** Eski servis durdurulup `.previous` oluşturulmadan hata oluştuğunda rollback `uninstall` yapmaz, `verify_existing:1.0.0` → `start:1.0.0` uygular; `1.0.0` kimliği ve `market_master.db` korunur.
- **Senaryo B, C, D (`UpgradeInterrupt`, `Migration`, `ServiceInstall`) + `Stopped` servis:** Step 5 öncesi hatalarda `uninstall`/`install` olmadan `verify_existing:1.0.0` uygulanır; önceden `Running` olanlar başlatılır, `PENDING_TLS_PROVISIONING` (`Stopped`) olanlar kapalı tutulur.
- **Senaryo E (`ScmStamp`):** Step 5 yeni servisi kurup damgayı basamadan çöktüğünde rollback `uninstall:unstamped` → `install:1.0.0` → `sidtype:unrestricted` → `stamp:1.0.0` → `start:1.0.0` uygular.
- **Senaryo F (`Acl`) & H (`HealthCheck`):** Step 5 sonrası `1.1.0` damgalı yeni servis kurulduktan sonra hata alınırsa rollback `uninstall:1.1.0` → `1.0.0` temiz kurulumu ve damgalamasını yapar.
- **Senaryo I & 14 Fail-Closed Edge-Case Doğrulaması:**
  - Eksik damgalı manifest fallback → `ExitCode 74`, `PARTIAL_ROLLBACK_FAILED`, `ERR_SCM_STAMP_MISSING`, sıfır yıkıcı SCM komutu.
  - Yanlış sürüm damgası (`9.9.9`) ve `XML SHA-256` uyuşmazlığı → eski varsayılmaz, kaldırılıp temiz `1.0.0` kurulur.
  - Yabancı `ImagePath` (`ERR_FOREIGN_SERVICE_PROTECTED`), yanlış hesap (`LocalSystem` → `ERR_SCM_INVALID_ACCOUNT`), yanlış SID tipi (`NONE` → `ERR_SCM_INVALID_SIDTYPE`), `DELETE_PENDING` bayrağı ve `ScmDeletePending` hata enjeksiyonu (`ERR_SCM_DELETE_PENDING`) → tümünde `ExitCode 74`, `PARTIAL_ROLLBACK_FAILED`, sıfır SCM operasyonu ve `bin.previous` / DB korunumu.
  - Step 5 sırasında `ServiceUninstall` hatası → `ExitCode 74`, `ERR_SERVICE_UNINSTALL_FAILED`, veri dokunulmazlığı.

---

## 4. Gerçek Doğrulama Komutları ve Çıktıları

| Doğrulama | Komut / Kapsam | Gerçek Sonuç |
|---|---|---|
| **Pure ASCII & PowerShell AST** | `mms_installer_engine.ps1` | `ENGINE_NON_ASCII=0`, `ENGINE_PARSE_ERRORS=0` (`ExitCode 0`) |
| **Statik Analiz** | `dart analyze test/phase_c_windows_installer_test.dart test/stage3_windows_installer_audit_test.dart` | `No issues found!` (`ExitCode 0`) |
| **Hedefli B-1 Testleri (`task-1160`)** | `Test 25` ve `Test 27` (`-j 1 -r expanded`) | `Test 25`: `01:05 +1 All tests passed!`; `Test 27`: `02:09 +1 All tests passed!` (`EC25=0 EC27=0`) |
| **Tam Installer Regresyon Paketi (`task-1172`)** | `phase_c_windows_installer_test.dart` + `stage3_windows_installer_audit_test.dart` (`-j 1`) | **`12:06 +31: All tests passed!`** (`17` Phase C + `14` Stage 3 audit testi, `INSTALLER_SUITE_EXIT=0`, atlanan/başarısız test yok) |

---

## 5. Kalan Açık Sınırlar

- **Canlı Windows SCM / HKLM Registry Doğrulaması (`BLOCKED` — Host Yetki & İzolasyon Sınırı):** Konakta kullanıcı `IS_ADMIN=False` ve proje anayasası uyarınca konak SCM'ye dokunulmadı. `HKLM:\SYSTEM\CurrentControlSet\Services\MarketMMSService\Parameters` yazma/okuma ve `sc.exe qc` `DELETE_PENDING` dalları yükseltilmiş (`Administrator`) temiz test VM veya fiziksel makine üzerinde `run_vm_fresh_install_acceptance.ps1 -LiveVmExecution` ile doğrulanacaktır.
