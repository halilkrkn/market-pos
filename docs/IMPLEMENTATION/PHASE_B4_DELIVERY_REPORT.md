# PHASE_B4_DELIVERY_REPORT.md — Faz 7 (`Hat B / Faz B-4`) Teslim Raporu

- **Faz:** Faz 7 — Merkezi Restore + `OV-03` Tam Uzlaştırma + `OV-04` İlk `OWNER` Bootstrap / `CASHIER` Varsayılanı + Replay Koruması + UI Ayrıştırma (`B-4`)
- **Durum Özeti:**
  - `ReplayProtectionService` (`X-MMS-Timestamp` ±300s + `X-MMS-Nonce` 600s TTL → `403 ERR_REPLAY_DETECTED` + `device_audit_logs`): **`IMPLEMENTED`**, **`AUTOMATED_TESTED`**
  - `HubRestoreService` (`BackupOperationLock` + duraklatma + `MMSBAK02`/`MMSBAK01` çözümleme + FFI `PRAGMA integrity_check` + şifreli pre-restore safety snapshot + atomik swap + `restore_epoch` artışı + kontrollü token geçersizleştirme [`allowRePair` açık / kalıcı revoke `isActive = false` korunur]): **`IMPLEMENTED`**, **`AUTOMATED_TESTED`**
  - `OV-04` İlk `OWNER` Bootstrap & `CASHIER` Varsayılanı (`POST /api/v1/admin/owner/bootstrap`, `POST /api/v1/devices/role`, son aktif `OWNER` koruması `409 ERR_LAST_OWNER_PROTECTED`): **`IMPLEMENTED`**, **`AUTOMATED_TESTED`**
  - `OV-03` İstemci Restore Sonrası Eksik `SYNCED` İşlem Uzlaştırması (`PostRestoreSyncTransport`, `reconcilePostRestoreIfNeeded`, fail-closed `PostRestoreHistoryMissingException`): **`IMPLEMENTED`**, **`AUTOMATED_TESTED`**
  - `HubCentralBackupCard` (`Merkezi Hub Yedekleme (Google Drive)`) vs `BackupManagementCard` (`Legacy Yerel Cihaz Yedeği (S5A-4)`) UI ayrımı ve `HubBackupClient` replay başlıkları: **`IMPLEMENTED`**, **`AUTOMATED_TESTED`**
  - Gerçek Çoklu Cihaz Yeni-PC Restore, Canlı Re-Pairing & Fiziksel Android/Windows Saha Testleri: **`BLOCKED`** (`OWNER ACTION REQUIRED`)

---

## 1. Oluşturulan ve Değiştirilen Dosyalar

| Dosya | Açıklama | Durum |
|---|---|---|
| [replay_protection_service.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/replay_protection_service.dart) | `X-MMS-Timestamp` (±300s) ve `X-MMS-Nonce` (600s TTL tek kullanımlık) replay koruma motoru (`403 ERR_REPLAY_DETECTED`) | `IMPLEMENTED`, `AUTOMATED_TESTED` |
| [hub_restore_service.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/backup/hub_restore_service.dart) | Tek-uçlu kilitli Hub restore akışı, `MMSBAK02`/`MMSBAK01` çözümleme, FFI `PRAGMA integrity_check`, şifreli safety snapshot, `restore_epoch` artışı ve kontrollü token geçersizleştirme | `IMPLEMENTED`, `AUTOMATED_TESTED` |
| [pairing_manager.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/pairing_manager.dart) | Eşleştirilen yeni cihazlara açık `role: const Value('CASHIER')` ataması (`OV-04`) | `IMPLEMENTED`, `AUTOMATED_TESTED` |
| [server.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart) | `POST /api/v1/admin/owner/bootstrap`, `POST /api/v1/devices/role`, `POST /api/v1/backup/restore`, son `OWNER` koruması (`revoke`/`role`), `/health` + `/api/v1/sync/device-state` + `/api/v1/sync/receipts` üzerinde `restore_epoch`, ve 7 hassas mutasyon rotasında replay koruması | `IMPLEMENTED`, `AUTOMATED_TESTED` |
| [hub_backup_b2_oauth_test.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/test/hub_backup_b2_oauth_test.dart) | Replay koruma başlıkları eklenen OAuth PKCE handoff uçlarıyla hizalandı | `AUTOMATED_TESTED` |
| [hub_backup_b4_rbac_restore_test.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/test/hub_backup_b4_rbac_restore_test.dart) | `BK-022…BK-025` (Hub RBAC, `OV-04` bootstrap, replay protection ve yeni-PC Hub restore) test takımı | `AUTOMATED_TESTED` |
| [client_storage_repository.dart](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/database/client_storage_repository.dart) | `PostRestoreHistoryMissingException`, `getStoredRestoreEpoch`, `saveStoredRestoreEpoch` (`local_client_settings` — şema değişikliği yok), `getSyncedOutboxOperations`, `requeueOperationsForPostRestore` | `IMPLEMENTED`, `AUTOMATED_TESTED` |
| [sync_transport.dart](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/sync/sync_transport.dart) | Mevcut 17 `SyncTransport` test sahtesini bozmamak için ayrık `abstract interface class PostRestoreSyncTransport` + `HttpSyncTransport` uygulaması | `IMPLEMENTED`, `AUTOMATED_TESTED` |
| [client_sync_service.dart](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/sync/client_sync_service.dart) | `reconcilePostRestoreIfNeeded()` ve `SyncBatchResult.postRestoreHistoryMissing` / `postRestoreRequeuedCount` entegrasyonu | `IMPLEMENTED`, `AUTOMATED_TESTED` |
| [post_restore_reconciliation_test.dart](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/test/post_restore_reconciliation_test.dart) | `BK-026`, `BK-027` (`OV-03` eksik `SYNCED` işlem uzlaştırması & fail-closed geçmiş eksikliği testi) | `AUTOMATED_TESTED` |
| [local_database_service.dart](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart) | `_TrackedClientStorageRepository` üzerinde `OV-03` repository metot yönlendirmeleri | `IMPLEMENTED` |
| [hub_backup_client.dart](file:///c:/Users/halil/Github/market-pos/lib/features/backup/data/hub_backup_client.dart) | Replay başlıklı (`X-MMS-Timestamp`, `X-MMS-Nonce`) Merkezi Hub REST istemcisi | `IMPLEMENTED`, `AUTOMATED_TESTED` |
| [hub_central_backup_card.dart](file:///c:/Users/halil/Github/market-pos/lib/features/backup/presentation/widgets/hub_central_backup_card.dart) | `Merkezi Hub Yedekleme (Google Drive)` kartı (Windows masaüstünde tam PKCE/anahtar/zamanlama/restore; Android `OWNER`'da OAuth'suz uzaktan durum/tetik; Android `CASHIER`'da kısıt banner'ı) | `IMPLEMENTED`, `AUTOMATED_TESTED` |
| [backup_providers.dart](file:///c:/Users/halil/Github/market-pos/lib/features/backup/backup_providers.dart) | `hubBackupDeviceRoleProvider`, `hubBackupHttpClientProvider`, `hubBackupClientProvider`, `hubBackupOAuthHandoffServiceProvider` | `IMPLEMENTED`, `AUTOMATED_TESTED` |
| [backup_management_card.dart](file:///c:/Users/halil/Github/market-pos/lib/features/backup/presentation/widgets/backup_management_card.dart) | Kart başlığı `Legacy Yerel Cihaz Yedeği (S5A-4)` olarak etiketlendi (`Key('diagnostics_backup_card')` korundu) | `IMPLEMENTED`, `AUTOMATED_TESTED` |
| [diagnostics_view.dart](file:///c:/Users/halil/Github/market-pos/lib/features/diagnostics/presentation/screens/diagnostics_view.dart) | `HubCentralBackupCard` (ana) üstte, `BackupManagementCard` (legacy) altta konumlandırıldı | `IMPLEMENTED` |
| [hub_central_backup_ui_test.dart](file:///c:/Users/halil/Github/market-pos/test/features/backup/hub_central_backup_ui_test.dart) | UI rol/platform ayrımı (`BK-029a`, `BK-029b`) ve `HubBackupClient` replay başlık (`BK-031`) widget/birim testleri | `AUTOMATED_TESTED` |

---

## 2. Doğrulama Sonuçları (Gerçek Komut Çıktıları)

1. **`packages/mms_client_storage`:**
   - `dart analyze` → `No issues found!`
   - `dart test test/post_restore_reconciliation_test.dart test/s5a3_outbox_sync_test.dart` → **`00:01 +10: All tests passed!`**
2. **`test_spikes/spike_01_backend`:**
   - `dart analyze` → `No issues found!`
   - `dart test test/hub_backup_b4_rbac_restore_test.dart test/hub_backup_b3_orchestrator_test.dart test/hub_backup_b2_oauth_test.dart` → **`00:02 +11: All tests passed!`**
3. **Kök `market_pos`:**
   - `flutter analyze lib/features/backup/ lib/features/diagnostics/ test/features/backup/` → **`No issues found! (ran in 3.2s)`**
   - `flutter test test/features/backup/hub_central_backup_ui_test.dart test/features/backup/hub_backup_b3_provider_test.dart test/features/production/production_readiness_test.dart` → **`00:06 +12: All tests passed!`**

---

## 3. Kapsam & Açık Fiziksel Koşullar

- **Otomatik Kabul Kapsamı:** `OV-03`, `OV-04`, replay koruması (`X-MMS-Timestamp`/`X-MMS-Nonce`), şifreli safety snapshot + atomik restore, kontrollü token geçersizleştirme ve Windows/Android rol bazlı UI ayrımı birim ve entegrasyon/widget testleriyle doğrulandı.
- **Fiziksel Doğrulama (`BLOCKED — OWNER ACTION REQUIRED`):** Gerçek ikinci temiz Windows PC'de `MMSBAK02` kurtarma, fiziksel Android cihazda re-pairing sonrası Outbox/`client_seq` uzlaştırması ve canlı `CASHIER`/`OWNER` LAN saha testleri (`BK-PAT-12…15`, `BK-PAT-17`) fiziksel donanım ve ortam kurulumu gerektirdiğinden **`BLOCKED`** durumundadır.

---

## 4. 23 Kasım 2026 Devralma Doğrulaması ve Ek Düzeltmeler

- **`IMP-03` — Merkezi restore ucu sertleştirmesi (`POST /api/v1/backup/restore`):**
  - Uzak `OWNER` cihazı keyfi `package_path` gönderebiliyordu. Windows'ta `\\sunucu\paylaşım\x.mmsbak` UNC yolu, servis hesabının SMB/NTLM kimlik bilgisini dış sunucuya gönderebilir. Artık `package_path` yalnızca loopback + admin secret çağrısında kabul edilir (`403 ERR_PACKAGE_PATH_LOOPBACK_ONLY`), UNC/göreli yollar her durumda reddedilir (`400 ERR_INVALID_PACKAGE_PATH`), `backup_id` dizin geçişine karşı `^[A-Za-z0-9_-]{1,128}$` ile doğrulanır (`400 ERR_INVALID_BACKUP_ID`).
  - `kdf_iterations` istek gövdesinden okunuyordu; uzak çağıran safety snapshot PBKDF2 turunu (600k) düşürebiliyordu. Artık yalnızca sunucu yapılandırması (`hubRestoreSafetyKdfIterations`) kullanılır.
  - `hub_backup_b4_rbac_restore_test.dart` (`BK-025`) yeni-PC senaryosu `backup_id` ile yeniden yazıldı ve 3 red senaryosu eklendi. Windows UI kartı `package_path` kullanmadığından UI etkilenmedi.
- RBAC (`OV-04` bootstrap, `CASHIER` varsayılanı, son `OWNER` koruması), replay koruması (`±300 s`, `600 s` nonce TTL), şifreli safety snapshot, `restore_epoch` ve kontrollü token geçersizleştirme testleri tam Hub takımında yeniden çalıştırıldı.
