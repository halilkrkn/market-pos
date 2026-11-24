# PHASE_B1_DELIVERY_REPORT.md — Faz 3 (`Hat B / Faz B-1`) Teslim Raporu

- **Faz:** Faz 3 — Taşınabilir `MMSBAK02` Akışlı Şifreleme, İki Aşamalı Hub Snapshot, Disk Alanı & Saklama Ayrımı (`B-1`)
- **Durum Özeti:**
  - `MMSBAK02` Akışlı AEAD + DEK/KEK Zarflama ve `MMSBAK01` Geriye Dönük Uyumluluk: **`IMPLEMENTED`**, **`AUTOMATED_TESTED`**
  - `DiskSpaceChecker` (`2.5 * (db + wal) + 64 MiB` + `GetDiskFreeSpaceExW` FFI): **`IMPLEMENTED`**, **`AUTOMATED_TESTED`**
  - `HubBackupRetentionPolicy` (Drive `30g + 12 ay + >= 1` sert değişmez vs 7 günlük yerel önbellek): **`IMPLEMENTED`**, **`AUTOMATED_TESTED`**
  - `HubSnapshotService` (`WriteQueue` içi `VACUUM INTO` → dışında `PRAGMA integrity_check` + akışlı `MMSBAK02` + `.tmp_snapshots/.owner.json`): **`IMPLEMENTED`**, **`AUTOMATED_TESTED`**
  - Gerçek Windows Servis / Büyük Üretim DB / Fiziksel Drive Kabul Testleri: **`BLOCKED`** (`OWNER ACTION REQUIRED`)

---

## 1. Oluşturulan ve Değiştirilen Dosyalar

| Dosya | Açıklama | Durum |
|---|---|---|
| [pubspec.yaml](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/pubspec.yaml) | `cryptography: ^2.7.0` (`2.9.0` çözüldü) bağımlılığı eklendi (`package:cryptography` AES-256-GCM + PBKDF2-HMAC-SHA256; özel AES-GCM yazılmadı) | `IMPLEMENTED` |
| [mmsbak_v2_crypto.dart](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/backup/mmsbak_v2_crypto.dart) | `MMSBAK02` ikili formatı (`8B MMSBAK02 + 4B headerLen + headerJson + wrap(nonce/DEK/MAC) + 1 MiB chunk AEAD`), min 12 karakter parola doğrulaması (`OV-05`), `MMSBAK01` geriye dönük `inspectFile`/`decryptFile` | `IMPLEMENTED`, `AUTOMATED_TESTED` |
| [disk_space_checker.dart](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/backup/disk_space_checker.dart) | `ceil(2.5 * (db + wal)) + 64 MiB` ön kontrolü ve Windows `kernel32.dll` `GetDiskFreeSpaceExW` FFI | `IMPLEMENTED`, `AUTOMATED_TESTED` |
| [hub_backup_retention_policy.dart](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/backup/hub_backup_retention_policy.dart) | Drive arşivi (30g günlük + 12 farklı takvim ayı + en az 1 geçerli `COMPLETED_UPLOADED` sert değişmezi) ve 7 günlük bağımsız yerel önbellek ayrımı | `IMPLEMENTED`, `AUTOMATED_TESTED` |
| [backup_file_transfer.dart](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/backup/backup_file_transfer.dart) | `verifyPackageStructure` her iki formatı (`MMSBAK01` ve `MMSBAK02`) kabul edecek şekilde güncellendi | `IMPLEMENTED`, `AUTOMATED_TESTED` |
| [mms_client_storage.dart](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/mms_client_storage.dart) | Yeni `MMSBAK02`, `DiskSpaceChecker` ve `HubBackupRetentionPolicy` export'ları eklendi | `IMPLEMENTED` |
| [hub_snapshot_service.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/backup/hub_snapshot_service.dart) | Aşama 1 (`WriteQueue` içi `VACUUM INTO`, `.tmp_snapshots` + `.owner.json` sahipliği, dışında FFI `PRAGMA integrity_check`) ve Aşama 2 (`WriteQueue` dışında `MMSBAK02` şifreleme) | `IMPLEMENTED`, `AUTOMATED_TESTED` |
| [mmsbak_v2_and_retention_test.dart](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/test/mmsbak_v2_and_retention_test.dart) | `BK-001..003`, `BK-017..019` testleri | `AUTOMATED_TESTED` |
| [hub_backup_b1_test.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/test/hub_backup_b1_test.dart) | `BK-004`, `BK-005` gerçek FFI WAL + eşzamanlı `WriteQueue` testleri | `AUTOMATED_TESTED` |

---

## 2. Test Kapsamı (`BK-001…BK-005`, `BK-017…BK-019`)

- **`BK-001`:** 12 karakterden kısa parolaların reddi, `MMSBAK02` akışlı şifreleme/çözme ve eski `MMSBAK01` paketlerinin `MmsbakV2Crypto` üzerinden çözülmesi/incelenmesi.
- **`BK-002`:** Yanlış parola reddi; parça ciphertext/MAC 1-bit bozulması ve eksik/kesilmiş (`truncation`) dosya durumlarında fail-closed reddi ve hedef dosyanın kirletilmemesi.
- **`BK-003`:** `> 3 MiB` (`3 MiB + 200 KiB`) veri üzerinde `1 MiB` akışlı çok parçalı `MMSBAK02` şifreleme/çözme ve tam SHA-256 doğrulaması.
- **`BK-004`:** Gerçek FFI SQLite WAL üzerinde Aşama 2 şifreleme sürerken eşzamanlı `WriteQueue` ürün yazmasının bloklanmadan çalışması ve `PRAGMA integrity_check == ok`.
- **`BK-005`:** Yetersiz disk alanında `ERR_INSUFFICIENT_DISK_SPACE` fail-fast; `.tmp_snapshots` altında `.owner.json` sahipliği eşleşmeyen yabancı/farklı iş dosyalarının korunması.
- **`BK-017`:** `2.5 * (db + wal) + 64 MiB` formülünün sınır altı/üstünde doğru geçiş kararları.
- **`BK-018` / `BK-019`:** Drive'da 24 aydan eski yedeklerde bile son geçerli `COMPLETED_UPLOADED` kaydının korunması, 30g + 12 farklı takvim ayı budaması ve 7 günlük yerel önbelleğin yüklenmemiş paketleri koruması.

---

## 3. Gerçek Komut Çıktıları

1. **`packages/mms_client_storage`:**
   - `dart analyze` → `No issues found!`
   - `dart test test/mmsbak_v2_and_retention_test.dart test/backup_file_transfer_test.dart test/backup_operation_lock_test.dart test/s5a4_backup_restore_test.dart test/scheduled_backup_runner_test.dart` → **`00:34 +65: All tests passed!`**
2. **`test_spikes/spike_01_backend`:**
   - `dart analyze` → `No issues found!`
   - `dart test test/hub_backup_b1_test.dart` → **`00:00 +2: All tests passed!`**

---

## 4. 23 Kasım 2026 Devralma Doğrulaması ve Ek Düzeltmeler

- **`IMP-01` / `IMP-02` — Makineye bağlı pepper fallback'inin kaldırılması:** `createEncryptedHubBackup` (eski `/api/v1/admin/backup` ve eski aralıklı zamanlayıcı) parola verilmediğinde artık `pepper.dpapi` yerine Portable Recovery Password (`backup_recovery_key.dpapi`) kullanır; tanımlı değilse `412 ERR_RECOVERY_KEY_NOT_CONFIGURED` (fail-closed, dosya üretilmez); açık parola < 12 karakter → `400 ERR_WEAK_RECOVERY_PASSWORD`. `/api/v1/admin/restore` varsayılan olarak kurtarma parolasını kullanır; eski pepper-şifreli yedekler yalnızca aynı makinede açık `legacy_machine_key: true` ile açılır. Yeni test dosyası `test/legacy_backup_portable_key_test.dart` (`LP-01…LP-07`); `hub_scheduled_backup_test.dart` yeni sözleşmeye hizalandı (paket pepper ile **açılamaz** doğrulaması eklendi).
- **`MMSBAK01` geriye dönük okuma** korunmuştur (`mmsbak_v2_and_retention_test`, `bk02_1_hub_reconciliation_test` v1 yedeğinin v2'ye restore'u, `LP-05`).
- Gerçek test sayıları: [`FINAL_PILOT_READINESS_REPORT.md`](../FINAL_PILOT_READINESS_REPORT.md) §3.
