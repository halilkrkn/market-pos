# PHASE_B3_DELIVERY_REPORT.md — Faz 5 (`Hat B / Faz B-3`) Teslim Raporu

- **Faz:** Faz 5 — 12-Durum Makinesi, Hub Zamanlayıcı, Aşamalı Çökme Kurtarma & Kooperatif Kapanış (`B-3`)
- **Durum Özeti:**
  - Kök İstemci Yutulan `afterSuccess` Drive Callback'inin Kaldırılması (`BK-032`): **`IMPLEMENTED`**, **`AUTOMATED_TESTED`**
  - 12-Durum Makinesi (`HubBackupJobState` & `HubBackupStateMachine`) ve Atomik `backup_jobs_state.json` (`HubBackupStateStore`): **`IMPLEMENTED`**, **`AUTOMATED_TESTED`**
  - `HubRecoveryKeyStore` (LocalMachine DPAPI + `MarketMMS:HubBackupRecoveryKey:v1` `pOptionalEntropy`): **`IMPLEMENTED`**, **`AUTOMATED_TESTED`**
  - `HubBackupOrchestrator` (`INITIAL_ENABLE`, `00:00` yerel, `CATCH_UP`, `MANUAL`, `5/10/20/40/80/160m` backoff, gece yarısı `SUPERSEDED`, 600k PBKDF2 tekrarsız aşamalı crash recovery, `<1.5s` kooperatif kapanış, `COMPLETED_UPLOADED` sonrası retention): **`IMPLEMENTED`**, **`AUTOMATED_TESTED`**
  - Gerçek `LocalService` & Çok Günlük Saha Çalışma Doğrulamaları: **`BLOCKED`** (`OWNER ACTION REQUIRED`)

---

## 1. Oluşturulan ve Değiştirilen Dosyalar

| Dosya | Açıklama | Durum |
|---|---|---|
| [backup_providers.dart](file:///c:/Users/halil/Github/market-pos/lib/features/backup/backup_providers.dart) | `backupScheduleControllerProvider` içindeki yutulan `afterSuccess` Google Drive upload callback'i kaldırıldı | `IMPLEMENTED`, `AUTOMATED_TESTED` |
| [hub_backup_state.dart](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/backup/hub_backup_state.dart) & [mms_client_storage.dart](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/mms_client_storage.dart) | Kesin 12 durum (`PENDING`..`SUPERSEDED`), 4 tetikleyici (`INITIAL_ENABLE`, `SCHEDULED_DAILY`, `CATCH_UP`, `MANUAL`), geçiş doğrulayıcı ve zamanlama config modelleri | `IMPLEMENTED`, `AUTOMATED_TESTED` |
| [hub_backup_state_store.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/backup/hub_backup_state_store.dart) | `backup_jobs_state.json` atomik `.tmp` + rename + bozuk dosya karantina deposu | `IMPLEMENTED`, `AUTOMATED_TESTED` |
| [hub_recovery_key_store.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/backup/hub_recovery_key_store.dart) | `backup_recovery_key.dpapi` DPAPI+entropy kasası (min. 12 karakter, asla düz metin / log / Drive çıktısı üretmez) | `IMPLEMENTED`, `AUTOMATED_TESTED` |
| [hub_backup_orchestrator.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/backup/hub_backup_orchestrator.dart) | 12-durumlu Hub zamanlayıcı/kurtarma/kapanış/retention orkestratörü (`BackupOperationLock` içinde başlangıç kaydı) | `IMPLEMENTED`, `AUTOMATED_TESTED` |
| [server.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart) | `SpikeServer` içine orkestratör, kooperatif `_stopServerResources()` kapanışı, açılış `recoverOnStartup()` ve `/api/v1/backup/{status,list,recovery-key,schedule,run}` uçları eklendi | `IMPLEMENTED` |
| [hub_backup_b3_orchestrator_test.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/test/hub_backup_b3_orchestrator_test.dart) | `BK-006..010`, `BK-014..016`, `BK-028`, `BK-030` otomatik testleri | `AUTOMATED_TESTED` |
| [hub_backup_b3_provider_test.dart](file:///c:/Users/halil/Github/market-pos/test/features/backup/hub_backup_b3_provider_test.dart) | `BK-032` yutulan callback kaldırma testi | `AUTOMATED_TESTED` |

---

## 2. Doğrulama Sonuçları (Gerçek Komut Çıktıları)

1. **`test_spikes/spike_01_backend`:**
   - `dart analyze` → `No issues found!`
   - `dart test test/hub_backup_b3_orchestrator_test.dart test/hub_backup_b2_oauth_test.dart test/hub_backup_b1_test.dart` → **`00:02 +9: All tests passed!`**
2. **Kök `market_pos`:**
   - `flutter analyze lib/features/backup/ test/features/backup/` → **`No issues found! (ran in 2.5s)`**
   - `flutter test test/features/backup/hub_backup_b3_provider_test.dart test/features/backup/backup_schedule_controller_test.dart test/features/backup/workmanager_background_backup_test.dart` → **`00:03 +15: All tests passed!`**

---

## 3. 23 Kasım 2026 Devralma Doğrulaması ve Ek Düzeltmeler

- **`IMP-04` — Drive retention durum kaydı:** Orkestratör eski Drive yedeklerini siliyor fakat iş kaydındaki `driveFileId`'yi temizlemiyordu; silinmiş kopya `/api/v1/backup/list`'te `COMPLETED_UPLOADED` + geçerli Drive kimliğiyle görünüyor, her turda yeniden `DELETE` gönderiliyor ve "en az 1 geçerli yedek" hesabı gerçek durumdan sapıyordu. Artık yalnızca başarıyla silinen (veya `404`) kopyaların `driveFileId`/`driveSessionUri` alanı temizlenir; 12 durumlu makineye yeni durum eklenmedi. Yeni test `BK-033` (`hub_backup_b3_orchestrator_test.dart`).
- 12 durum (`PENDING…SUPERSEDED`), `INITIAL_ENABLE`/`00:00`/`CATCH_UP`/`MANUAL`, `5/10/20/40/80/160 dk` backoff, aşamalı crash recovery ve `<1.5 s` kooperatif kapanış testleri tam Hub takımında yeniden çalıştırıldı.
