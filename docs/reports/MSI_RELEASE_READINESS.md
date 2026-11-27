# MARKET MMS — Windows MSI Yayın ve İmza Hazırlık Raporu (`MSI_RELEASE_READINESS`)

**Tarih:** 2026-11-27

**Kapsam:** Stage G — B-1 Düzeltmeli Release MSI Yeniden Derlemesi, MSI Veritabanı Tablo Denetimi ve İzole `TEST_ONLY` İmza Doğrulaması

**Durum:** Release MSI başarıyla üretildi ve tablo/hash bütünlüğü **PASS**; ticari OV/EV kod imzalama sertifikası bulunmadığından üretim MSI **imzasız (`NotSigned`)** durumdadır (**EXTERNAL BLOCKER** — izole kopyada yalnızca `TEST-SIGNED ONLY` imza yapısı doğrulandı).

---

## 1. Üretilen Release MSI Paketi ve Bütünlük

Derleme komutu:
`scripts\build_windows_installer.ps1 -Configuration Release -OutputDir dist\installer_v1_0_0_tray -SkipFlutterBuild`

| Alan | Değer / Kanıt |
|---|---|
| **Dosya Yolu** | `dist\installer_v1_0_0_tray\MarketMMS-Setup-1.0.0-x64.msi` |
| **Boyut** | `23064576` bayt (~22.00 MB) |
| **SHA-256** | `183B014FD6ED80785E4302388A2362D020DAD300D3BDEE21317450EE73CA820C` |
| **`SHA256SUMS.txt` Uyumu** | **Eşleşiyor (`true`)** — `183B014FD6ED80785E4302388A2362D020DAD300D3BDEE21317450EE73CA820C  MarketMMS-Setup-1.0.0-x64.msi` |
| **Paketlenen Hub İkilisi** | `mms_backend.exe` (`9972736` bayt, SHA-256 `D72B05E5FDD51A982702E727377BB54D4121AE10D28EBE3C9FE1BDD98947A53F`, taze Dart AOT `3.13.7` derlemesi) |
| **Paketlenen İstemci İkilisi** | `build\windows\x64\runner\Release\market_pos.exe` (`175104` bayt, SHA-256 `7F449053E569740E8436B6ED9D28926811498E04E405215C5C01C254ADDB1217`) |
| **Paketlenen Yaşam Döngüsü Betiği** | `installer\windows\scripts\mms_installer_engine.ps1` (B-1 deterministik SCM damgası dahil `4541` satır) |
| **WiX Derleme Sonucu** | `0 Hata`, `3 Uyarı` (ICE60 non-font language uyarısı) |
| **NTFS HardLink Durumu** | **`LinkType: ''` (Bağımsız dosya — hardlink yok)** |
| **İmza Durumu (Release MSI)** | **`NotSigned`** (`Get-AuthenticodeSignature`) |

---

## 2. MSI Veritabanı Tablo Denetimi (`WindowsInstaller.Installer` COM)

### 2.1. SummaryInformation ve Kapsam Hijyeni
- **Title / Author / Template:** `Installation Database` / `Market MMS` / `x64;1055`
- **`File` Tablosu Satır Sayısı:** `27` (not: iç COM sayımı `File` satırları; `GeneratedPayload.wxs` bileşenleri eksiksiz)
- **`MarketMmsSpike01` / `Spike01` Referansı:** **`0`** (`File`, `Property` ve `CustomAction` tablolarında hiç referans yok)

### 2.2. `Property` ve `LaunchCondition` Tabloları
- `ALLUSERS=1`, `PURGE_USER_DATA=0`, `ALLOW_DEFERRED_TLS_START=1`, `HUB_PORT=8945`, `DISCOVERY_PORT=8946`
- `ProductCode={A2251640-D9C3-476B-B695-81B87A92B0FA}`, `UpgradeCode={8F4E2D1A-6C7B-4E93-A521-9D3C0478B6E2}`, `ProductVersion=1.0.0`, `ProductLanguage=1055`
- `SecureCustomProperties`: `ALLOW_DEFERRED_TLS_START;CONFIRM_PURGE_TOKEN;DISCOVERY_PORT;HUB_PORT;PURGE_USER_DATA;WIX_DOWNGRADE_DETECTED;WIX_UPGRADE_DETECTED`
- `LaunchCondition`: `NOT WIX_DOWNGRADE_DETECTED`, `Installed OR VersionNT64`, `Installed OR ALLUSERS=1`

### 2.3. `CustomAction` ve `InstallExecuteSequence` Sıralaması
| Sıra | Action | Tip | Bağlam / Koşul |
|---:|---|---|---|
| `25` | `FindRelatedProducts` | — | MajorUpgrade tespiti |
| `1501` | `RemoveExistingProducts` | — | MajorUpgrade kaldırma |
| `3498` | `CA_SetUninstallCtx` (`51`) | Immediate | `REMOVE="ALL" AND NOT UPGRADINGPRODUCTCODE` |
| `3499` | `CA_Uninstall` (`3106`) | Deferred (no impersonate) | `REMOVE="ALL" AND NOT UPGRADINGPRODUCTCODE` |
| `4001` | `CA_SetInstallCtx` (`51`) | Immediate | `NOT REMOVE="ALL"` (`[INSTALLFOLDER].\|1.0.0\|...`) |
| `4002` | `CA_RollbackInstall` (`3426`) | Rollback (no impersonate) | `NOT REMOVE="ALL"` |
| `4003` | `CA_InstallOrUpgrade` (`3106`) | Deferred (no impersonate) | `NOT REMOVE="ALL"` |
| `4004` | `CA_CommitInstall` (`3682`) | Commit (no impersonate) | `NOT REMOVE="ALL"` |

---

## 3. İzole `TEST_ONLY` Authenticode İmza Doğrulaması (Konak `Cert:\*` Dokunulmadı)

Gerçek `MarketMMS-Setup-1.0.0-x64.msi` paketi **değiştirilmeden** `%LOCALAPPDATA%\MarketMMS_Isolated_Test\msi_test_signing\MarketMMS-Setup-1.0.0-x64-testsigned.msi` konumuna kopyalanarak OpenSSL `3.5.9` ile disk üzerinde geçici `MarketMMS-TEST-ONLY-CodeSign` (`CN=MarketMMS-TEST-ONLY-CodeSign`, EKU `codeSigning`) PFX üretildi ve `signtool.exe` (`10.0.26100.0\x64`) ile `/fd SHA256` imzalandı:

- **İmza (`signtool sign /fd SHA256`):** **`ExitCode 0`** (TEST-SIGNED copy SHA-256: `015C18C7B7860B9AEFC7388CB57F805E6D31F49DC493607932C6DBDDB5CDC004`, imza parmak izi `DCBC29E5C9BE11D07CE4D3348928779B332006E9`).
- **Doğrulama (`signtool verify /v /pa`):** İmzalı gömülü Authenticode SHA-256 (`961856044CFFD087067CBF255128C306AFE9CD3531387B38B505D05671FE1C49`) doğrulandı; ancak konak `Cert:\*` kök deposuna self-signed test sertifikası eklenmediği için beklenen şekilde **`ExitCode 1` — `SignTool Error: A certificate chain processed, but terminated in a root certificate which is not trusted by the trust provider`** (`Get-AuthenticodeSignature`: `UnknownError`) döndü.

---

## 4. Tespit Edilen ve Kökten Düzeltilen WiX v5 NTFS HardLink Hatası

Nihai doğrulama sırasında [`MarketMMSInstaller.wixproj`](file:///c:/Users/halil/Github/market-pos/installer/windows/MarketMMSInstaller.wixproj) içinde paylaşılan `build\wix_obj\` dizini ve MSBuild'in NTFS hardlink (`LinkType: HardLink`) kopyalaması nedeniyle `phase_c_windows_installer_test.dart` ve `stage3_windows_installer_audit_test.dart` koşuları sırasında sentetik MSI derlemelerinin `build\wix_obj\Release\` üzerinden hem `dist\installer_v1_0_0_tray\MarketMMS-Setup-1.0.0-x64.msi` hem de eski `dist\installer\MarketMMS-Setup-1.0.0-x64.msi` dosyalarını `81920` B sentetik MSI ile ezdiği tespit edildi.

- **Uygulanan Kalıcı Çözüm:**
  1. [`MarketMMSInstaller.wixproj`](file:///c:/Users/halil/Github/market-pos/installer/windows/MarketMMSInstaller.wixproj): Koşullu `BaseIntermediateOutputPath` / `BaseOutputPath` ve `CreateHardLinksForCopyFilesToOutputDirectoryIfPossible=false` eklendi.
  2. [`build_windows_installer.ps1`](file:///c:/Users/halil/Github/market-pos/scripts/build_windows_installer.ps1): Her derleme tekil `$env:TEMP\mms_wix_build_<guid>\` (`obj/`, `bin/`, `out/`) içinde çalıştırılır; hedef `.msi`/`.wixpdb` önce `Remove-Item -Force` ile olası eski hardlinkten koparılır ve `[System.IO.File]::Copy` ile bağımsız dosya olarak kopyalanır.
  3. [`phase_c_windows_installer_test.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/test/phase_c_windows_installer_test.dart) (`Test 1 & 2`): Hardlink yokluğu ve ardışık sentetik derlemenin önceki çıktıyı ezmemesi regresyon testine bağlandı.
- **Doğrulama:** Güncel Release MSI (`183B014FD6ED80785E4302388A2362D020DAD300D3BDEE21317450EE73CA820C`) üretildikten **sonra** `+31` kurulum/denetim testinin tamamı (`phase_c` + `stage3`, `task-1844`, `POST_FIX_INSTALLER_SUITE_EXIT=0`) çalıştırılmış ve MSI bayt/SHA-256/`LinkType=''` değerlerinin değişmeden korunduğu teyit edilmiştir.
- **Tarihsel Paket Notu:** Eski `dist\installer\MarketMMS-Setup-1.0.0-x64.msi` (24 Kasım tarihli `SHA256SUMS.txt` kaydı `9484F2E0...`) düzeltme öncesi `HardLink` paylaşımı nedeniyle `81920` B durumundadır ve güncel `dist\installer_v1_0_0_tray\MarketMMS-Setup-1.0.0-x64.msi` ile ikame edilmiştir.

---

## 5. Üretim / Dağıtım Engeli (Commercial Signing)

- **EXTERNAL BLOCKER:** Üretim ortamında Windows SmartScreen / Windows Defender Application Control uyarılarını önlemek ve güvenilen zincir elde etmek için geçerli bir ticari **OV veya EV Authenticode kod imzalama sertifikası** ile timestamp (`/tr <RFC3161-TSA> /td SHA256`) imzalaması gerekir. Test-imzalı kopya yalnızca yapısal doğrulama (`TEST-SIGNED ONLY`) amaçlıdır ve dağıtımda kullanılamaz.
