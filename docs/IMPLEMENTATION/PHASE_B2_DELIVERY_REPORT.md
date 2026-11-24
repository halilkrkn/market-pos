# PHASE_B2_DELIVERY_REPORT.md — Faz 4 (`Hat B / Faz B-2`) Teslim Raporu

- **Faz:** Faz 4 — Windows PKCE → Hub DPAPI Handoff, ACL Sertleştirmesi & 4 MiB Akışlı Resumable Drive Yükleyici (`B-2`)
- **Durum Özeti:**
  - `WindowsDpapi` `pOptionalEntropy` Uzantısı (`OV-01`): **`IMPLEMENTED`**, **`AUTOMATED_TESTED`**
  - `HubBackupOAuthStore` & `HubBackupOAuthService` (`backup_drive_oauth.dpapi` — `live_drive_sync_secret.dpapi` izolasyonu, `OV-02`): **`IMPLEMENTED`**, **`AUTOMATED_TESTED`**
  - `setup_service_acls.ps1` `%PROGRAMDATA%\MarketMMS\backups` Sıkı ACL Denetimi: **`IMPLEMENTED`**, **`BUILD_VERIFIED`** (PS AST 0 hata; canlı NTFS uygulama sahada **`BLOCKED`**)
  - Hub OAuth Uçları (`/api/v1/backup/oauth/connect`, `/status`, `/disconnect`) & Windows PKCE Handoff İstemcisi: **`IMPLEMENTED`**, **`AUTOMATED_TESTED`**
  - `ResumableDriveUploader` (4 MiB `RandomAccessFile` akışı, `HTTP 308`, `404/410` kurtarma, `403 storageQuotaExceeded` vs `authFailure`, `<1.5s` iptal, `VERIFYING`): **`IMPLEMENTED`**, **`AUTOMATED_TESTED`**
  - Canlı Google Drive Gerçek Hesap & `LocalService` OAuth Testleri: **`BLOCKED`** (`OWNER ACTION REQUIRED`)

---

## 1. Oluşturulan ve Değiştirilen Dosyalar

| Dosya | Açıklama | Durum |
|---|---|---|
| [dpapi.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/dpapi.dart) | `protect`/`unprotect` metodlarına geriye dönük uyumlu isteğe bağlı `List<int>? entropy` (`pOptionalEntropy`) bağlaması eklendi | `IMPLEMENTED`, `AUTOMATED_TESTED` |
| [hub_backup_oauth_store.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/backup/hub_backup_oauth_store.dart) | `LocalMachine` DPAPI + `MarketMMS:HubBackupDriveOAuth:v1` entropy ile `backup_drive_oauth.dpapi` atomik kasa yönetimi | `IMPLEMENTED`, `AUTOMATED_TESTED` |
| [hub_backup_oauth_service.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/backup/hub_backup_oauth_service.dart) | PKCE `connectWithPkce`, `drive.file` scope kontrolü, otomatik token refresh, `invalid_grant` → `FAILED_AUTH`, sterilize `HubBackupOAuthStatus` | `IMPLEMENTED`, `AUTOMATED_TESTED` |
| [setup_service_acls.ps1](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/scripts/setup_service_acls.ps1) | `$BaseDir\backups` dizini `$criticalPaths` bildirimsel SID doğrulamasına eklendi | `IMPLEMENTED` |
| [auth_middleware.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/auth_middleware.dart) & [server.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart) | `bearerOrAdminPaths` desteği ve `/api/v1/backup/oauth/connect`, `/status`, `/disconnect` Hub uçları (sıfır ham token sızıntısı) | `IMPLEMENTED`, `AUTOMATED_TESTED` |
| [hub_backup_oauth_handoff_service.dart](file:///c:/Users/halil/Github/market-pos/lib/features/backup/application/hub_backup_oauth_handoff_service.dart) | Windows tarayıcı PKCE kodunun `POST /api/v1/backup/oauth/connect` üzerinden Hub'a devri (UI tarafında token saklanmaz) | `IMPLEMENTED` |
| [resumable_drive_uploader.dart](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/backup/resumable_drive_uploader.dart) | 4 MiB `RandomAccessFile` parçalı Drive yükleyici, `HTTP 308`, `404/410` oturum kurtarma, `403` kota/yetki ayrımı, `BackupCancellationToken`, `VERIFYING` doğrulaması | `IMPLEMENTED`, `AUTOMATED_TESTED` |
| [resumable_drive_uploader_test.dart](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/test/resumable_drive_uploader_test.dart) | `BK-011..013` otomatik yükleyici testleri | `AUTOMATED_TESTED` |
| [hub_backup_b2_oauth_test.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/test/hub_backup_b2_oauth_test.dart) | `BK-020`, `BK-021` DPAPI entropy, gizli izolasyonu ve PKCE Hub devri testleri | `AUTOMATED_TESTED` |

---

## 2. Doğrulama Sonuçları (Gerçek Komut Çıktıları)

1. **PowerShell AST:** `setup_service_acls.ps1` → `PS AST OK: setup_service_acls.ps1 (0 errors)`
2. **`packages/mms_client_storage`:**
   - `dart analyze` → `No issues found!`
   - `dart test test/resumable_drive_uploader_test.dart test/google_drive_backup_test.dart` → **`00:00 +20: All tests passed!`**
3. **`test_spikes/spike_01_backend`:**
   - `dart analyze` → `No issues found!`
   - `dart test test/hub_backup_b2_oauth_test.dart` → **`00:00 +2: All tests passed!`**
4. **Kök `market_pos` (`lib/features/backup/`):**
   - `flutter analyze lib/features/backup/` → **`No issues found! (ran in 1.9s)`**

---

## 3. 23 Kasım 2026 Devralma Doğrulaması ve Ek Düzeltmeler

- **Dağıtım hatası düzeltildi:** Önceki tur `setup_service_acls.ps1` dosyasına `backups\` dizinini eklerken dosyanın **UTF-8 BOM'unu kaldırmıştı**. Türkçe karakter içeren betik Windows PowerShell 5.1'de yanlış kod sayfasıyla okunur; tam Hub takımında `rel01_hub_config_test` bunu yakaladı (`BOM eklenmeli veya ASCII olmalı: [setup_service_acls.ps1]`). BOM geri eklendi (içerik değişmedi); PowerShell AST: `0` hata.
- `ResumableDriveUploader`: 4 MiB varsayılan chunk (256 KiB katı doğrulaması), `HTTP 308` offset sorgusu, `404/410` oturum kurtarma, `403` kota/yetki ayrımı korunmuştur (`resumable_drive_uploader_test`).
