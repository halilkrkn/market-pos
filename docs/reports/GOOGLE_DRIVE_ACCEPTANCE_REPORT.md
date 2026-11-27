# MARKET MMS — Google Drive Live Sync & Hub Backup/Restore Kabul Raporu (`GOOGLE_DRIVE_ACCEPTANCE_REPORT`)

**Tarih:** 2026-11-27

**Kapsam:** Stage K — Google Drive Canlı Operasyon Senkronizasyonu (`.mmsenv`, ADR-021), Merkezi Hub Yedekleme/Geri Yükleme (`.mmsbak`, ADR-011 / ADR-022 / ADR-023) ve OAuth PKCE / DPAPI Mimarisi Doğrulaması

**Durum:**
- **Yerel & İzole Canlı Hub Backup/Restore + Kripto/Kurcalama Reddi:** **PASS** (`STAGE_K_LIVE_HUB_PASS`, `STAGE_K_LIVE_EXIT=0`)
- **Offline/Mock OAuth, PKCE Hub Devri, Klasör/Sır İzolasyonu ve Drive Fallback Otomatik Testleri:** **PASS** (`mms_client_storage` `+265`, root `market_pos` `+376 ~2`, Hub doğrulamaları)
- **Gerçek Google Cloud OAuth Girişi & Canlı Google Drive Bulut Upload/Download:** **BLOCKED** *(Harici Google Cloud / `TEST_ONLY` Google hesabı tarayıcı onayı gerektirir; konakta sahte/uydurma bulut testi yapılmadı ve gerçek Drive içeriğine dokunulmadı).*

---

## 1. İki Alt Sistemin Kesin Mimari Ayrımı

MARKET MMS içinde Google Drive kullanan iki özellik token, sır (secret), klasör ve veri modeli düzeyinde birbirinden bağımsızdır:

| Özellik | Live Drive Sync (ADR-021) | Merkezi Hub Backup/Restore (ADR-011 / ADR-022 / ADR-023) |
|---|---|---|
| **Amaç** | Hub kapalıyken cihazlar arası operasyon aktarımı ve Hub dönüşü uzlaştırma | Merkezi `market_master.db` felaket kurtarma anlık görüntüsü |
| **Taşınan Veri** | Yalnızca şifreli **`.mmsenv`** (`MMSENV01`) operasyon zarfları (Ham SQLite DB **asla** paylaşılmaz) | Tam SQLite `VACUUM INTO` şifreli **`.mmsbak`** (`MMSBAK01` / `MMSBAK02`) paketi |
| **Drive Klasörü** | `'MARKET MMS LiveSync'` ([`hybrid_drive_live_sync.dart`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/sync/hybrid_drive_live_sync.dart#L878)) | `'MARKET MMS Yedekleri/Hub'` (`MmsDriveBackupFolders`, [`resumable_drive_uploader.dart`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/backup/resumable_drive_uploader.dart#L202-L208)) |
| **Şifreleme / Bütünlük** | `DriveLiveSyncEnvelopeCodec` (Encrypt-then-MAC, tenant/store alan ayrıcılı) | `MMSBAK01` (`AES-256-CBC` + `HMAC-SHA256`, `600000` PBKDF2) / `MMSBAK02` (`AES-256-GCM` DEK + `600000` PBKDF2, min 12 karakter parola, `1 MiB` chunk) |
| **Yerel Gizli Anahtar / Kasa** | `live_drive_sync_secret.dpapi` ([`live_drive_secret_manager.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/live_drive_secret_manager.dart)) | DPAPI + `pOptionalEntropy = MarketMMS:HubBackupDriveOAuth:v1` ([`hub_backup_oauth_store.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/backup/hub_backup_oauth_store.dart)) |

---

## 2. §14.1 Live Drive Sync (`.mmsenv`) Doğrulaması

### 2.1. Tasarım ve Güvenlik Kontrolleri
- **Klasör ve Şema İzolasyonu:** `GoogleDriveLiveEnvelopeTransport.folderName` (`'MARKET MMS LiveSync'`) değeri yedekleme kökü `'MARKET MMS Yedekleri'` değerinden farklıdır; `s5_drive_folder_separation_test.dart` istemci listelerinin Hub veya LiveSync dosyalarını karıştırmadığını doğrular.
- **Hub Üzerinden Sırrın Dağıtımı (`GET /api/v1/sync/live-drive-config`):**
  - [`hub_live_drive_config_client.dart`](file:///c:/Users/halil/Github/market-pos/lib/features/sync/data/hub_live_drive_config_client.dart) ve [`live_drive_config_endpoint_test.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/test/live_drive_config_endpoint_test.dart) doğrulamalarına göre:
    - Sır `pepper.dpapi` ve `admin_secret.txt` değerlerinden bağımsızdır; en az 32 karakter (256-bit entropi) taşır ve yanıt `Cache-Control: no-store` döner.
    - Tokensız istekler `401 Unauthorized`, iptal edilen cihazlar `403 DEVICE_REVOKED`, onaysız cihazlar `403 DEVICE_NOT_CONFIRMED`, hatalı `X-MMS-Tenant-Id` / `X-MMS-Store-Id` başlıkları `403`, TLS açıkken düz HTTP istekleri `426 UPGRADE_REQUIRED` ile reddedilir.
- **İstemci Reconciler ve Güvenlik Durdurmaları:**
  - `hybrid_drive_live_sync_test.dart`: Yetkili `ACTIVE` ve iptal edilen `REVOKED` cihaz ayrımı, duplicate/corrupt zarf reddi ve Hub geri geldiğinde Outbox uzlaştırması doğrulanmıştır.
  - `hybrid_drive_sync_coordinator_test.dart` (`S24–S25b`): Hub erişilemezken `DriveFallbackActive` geçişi, Hub döndüğünde `HubReconciling -> HubReconciled` tamamlanması ve **TLS pin uyuşmazlığı / Auth reddinde (`TLS_PIN_MISMATCH`) Drive fallback'in ASLA açılmaması** doğrulanmıştır.

---

## 3. §14.2 Hub Central Backup / Restore (`.mmsbak`) Doğrulaması

### 3.1. Canlı İzole Test Hub Uçtan Uca Doğrulaması (`task-1599`)
İzole Test Hub (`https://127.0.0.1:8947`, `PID 9680`, test DB `...\MarketMMS_Isolated_Test\hub\data\market_master_test.db`) üzerinde `stage_k_backup_verify.ps1` çalıştırılarak gerçek sunucu endpoint'leri doğrulandı:

| Test Adımı | Gerçek Gözlem / Çıktı | Sonuç |
|---|---|---:|
| **Başlangıç Sağlık & Anahtar Durumu** | `/health`: `status=UP`, `recovery_key_configured=true`, `epoch_before=epoch_1795801295587537_282fcf8e3f98` | **PASS** |
| **Merkezi Şifreli Yedek Alma** | `backup_id=1505c06d4e8b85c98576c14e6531f69f`, boyut `344656` bayt, `/api/v1/admin/backups` listesinde `listed_in_admin_backups=true` | **PASS** |
| **1 Bayt Kurcalama (Tamper) Reddi** | Paket üzerinde 1 bayt değiştirilerek `POST /api/v1/admin/restore` denendi → **`HTTP 400 ERR_RESTORE_DECRYPT_FAILED`** ile reddedildi; canlı DB korunarak değiştirilmedi | **PASS** |
| **Geçerli Geri Yükleme & Safety Backup** | Geçerli yedek ile geri yükleme: `restore_status=RESTORED`, **`safety_backup_encrypted=true`** | **PASS** |
| **Restore Epoch Rotasyonu** | Geri yükleme sonrası `/health` doğrulaması: `epoch_after=epoch_1795801358838097_6386cd148d0a` (`epoch_before`'dan farklı taze epoch üretildi) | **PASS** |
| **Çıkış & Temizlik** | `STAGE_K_LIVE_HUB_PASS`, `STAGE_K_LIVE_EXIT=0`, `TCP_8947_LISTEN=0`, `UDP_8948_EP=0`, `MMS_BACKEND_PROCS=0` | **PASS** |

### 3.2. Yük, Kripto ve Çökme Dayanıklılığı Kanıtı (`stage5_performance_and_durability_test.dart`, `task-1664`)
- Üretim `600.000` iterasyon PBKDF2-HMAC-SHA256 `MMSBAK02` gerçek şifreleme süresi: `5459 ms`; çözme süresi: `5297 ms` (`299008` B düz → `299880` B şifreli, hata `0`).

### 3.3. Hub Backup / OAuth Modüler Test Dosyaları
- `packages/mms_client_storage`: `backup_file_transfer_test.dart`, `backup_isolate_responsiveness_test.dart`, `backup_operation_lock_test.dart`, `google_drive_backup_test.dart`, `hybrid_drive_live_sync_test.dart`, `resumable_drive_uploader_test.dart`, `s5_drive_folder_separation_test.dart`, `s5a4_backup_restore_test.dart`, `scheduled_backup_runner_test.dart` (`+265` tam paketin içinde exit `0`).
- Root `market_pos`: `test/features/backup/` (`android_google_sign_in_oauth_test.dart`, `backup_schedule_controller_test.dart`, `client_backup_operation_lock_test.dart`, `drive_backup_restore_integration_test.dart`, `hub_backup_b3_provider_test.dart`, `hub_central_backup_ui_test.dart`, `stage2_hub_drive_restore_ui_test.dart`, `workmanager_background_backup_test.dart` — `+376 ~2` tam paketin içinde exit `0`).
- Backend `test_spikes/spike_01_backend`: `hub_backup_b1_test.dart`, `hub_backup_b2_oauth_test.dart`, `hub_backup_b3_orchestrator_test.dart`, `hub_backup_b4_rbac_restore_test.dart`, `hub_backup_s1_s6_hardening_test.dart`, `hub_scheduled_backup_test.dart`, `legacy_backup_portable_key_test.dart`, `stage2_hub_backup_restore_audit_test.dart`, `live_drive_config_endpoint_test.dart`.

---

## 4. §14.3 OAuth Mimarisi, Kapsam/Redirect Matrisi ve `BLOCKED` Sınırları

| Bileşen | Onaylı Scope & Redirect URI | Güvenlik Davranışı | Durum |
|---|---|---|---|
| **Windows Masaüstü PKCE → Hub Devri** ([`google_drive_connect_service.dart`](file:///c:/Users/halil/Github/market-pos/lib/features/backup/application/google_drive_connect_service.dart#L70-L93), [`hub_backup_oauth_service.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/backup/hub_backup_oauth_service.dart)) | Scope: `https://www.googleapis.com/auth/drive.file`<br>Redirect: `http://127.0.0.1:<ephemeral_port>/` | Tarayıcı PKCE kodunu Hub `/api/v1/backup/oauth/connect` ucuna devreder; Hub token takası, `/status`, otomatik `/refresh` ve `/disconnect` yönetir. Yanıtlar ham `access_token` / `refresh_token` içermez (`BK-021` doğrulandı). | **PASS (Mock OAuth)** |
| **Windows Tekil Client DPAPI Saklama** | Key: `gdrive_refresh_token_v1` | `SecureTokenStore` üzerinden işletim sistemi güvenli deposunda tutulur. | **PASS (Mock OAuth)** |
| **Android `google_sign_in` v7+ Akışı** ([`google_drive_connect_service.dart`](file:///c:/Users/halil/Github/market-pos/lib/features/backup/application/google_drive_connect_service.dart#L14-L15,L53-L62)) | Scope: `drive.file`<br>Yapılandırma: `MMS_GDRIVE_WEB_CLIENT_ID` | Credential Manager + `AuthorizationClient`; kısa ömürlü `access_token` yalnızca RAM'de tutulur; kimlik bilgisi yoksa fail-closed `ERR_DRIVE_NOT_CONFIGURED` döner. | **PASS (Unit / Widget Mock)** |
| **Canlı Google Cloud OAuth Girişi & Bulut Aktarımı** | `oauth2.googleapis.com/token`, `googleapis.com/drive/v3/files` | Owner tarafından sağlanan Google Cloud OAuth Client ID (`MMS_GDRIVE_CLIENT_ID` / `MMS_GDRIVE_WEB_CLIENT_ID`) ve `TEST_ONLY` Google hesabı tarayıcı consent onayı gerekir. Konakta mevcut olmadığından uydurulmadı. | **`BLOCKED`** |

---

## 5. Özet ve Geçiş Notu

- **Tamamlanan teknik seviye:** Live Sync (`.mmsenv`) + Hub Backup/Restore (`.mmsbak`) kripto motorları, DPAPI entropy izolasyonu (`BK-020`), PKCE Hub handoff + sıfır token sızıntısı (`BK-021`), canlı izole Hub şifreli yedek + 1 bayt tamper reddi (`HTTP 400`) + epoch döndüren geri yükleme (`STAGE_K_LIVE_HUB_PASS`) ve 4 MiB resumable yükleyici mantığı eksiksiz doğrulanmıştır.
- **Kalan dış engel (`BLOCKED`):** Gerçek `TEST_ONLY` Google hesabı + Google Cloud OAuth Client kimlik bilgileri sağlandığında `PAT-13`, `PAT-17`, `PAT-18` ve `BK-PAT-01..18` canlı bulut kabul testleri yürütülebilir (`OWNER_PHYSICAL_TEST_CHECKLIST.md` Adım 6).
