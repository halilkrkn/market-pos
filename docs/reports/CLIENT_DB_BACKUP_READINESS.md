# CLIENT DB BACKUP READINESS (Aşama E)

**Tarih:** 2026-11-27

**Hedef Veritabanı:** `%LOCALAPPDATA%\MarketMMS\client_local.db` (`C:\Users\halil\AppData\Local\MarketMMS\client_local.db`)

**Koruma Durumu:** Gerçek veritabanına **hiçbir yazma/açma işlemi yapılmamıştır**.

---

## 1. Gerçek İstemci DB Salt Okunur Durum Tespiti

| Ölçüm | Gerçek Değer | Not |
|---|---|---|
| **Tam Yol** | `C:\Users\halil\AppData\Local\MarketMMS\client_local.db` | Mevcut (`Exists = True`) |
| **Boyut** | `159.744` bayt (`156 KiB`) | Başlangıç/bitiş birebir aynı |
| **Son Yazım (UTC)** | `2026-11-20T12:00:01.3928872Z` | Kurulum öncesi son yazım |
| **SHA-256** | `587120C66FA6D0AECB0AC2CAEB1D2A47EC1E2BD2E5D38149DE7F45FE828F3AED` | Değişmedi (`REAL_CLIENT_DB_UNCHANGED=True`) |
| **`-wal` / `-shm` Dosyaları** | `WAL = False`, `SHM = False` | Temiz kapatılmış durumda |
| **Aktif Process Kilidi** | Çalışan `market_pos` süreci yok | Kilit yok |
| **Salt Okunur Kopya Üzerinden Bütünlük (`SQLite Backup API`)** | `integrity_check = ok` (`159.744` B çıktı) | İzole geçici kopya üzerinden doğrulandı |

---

## 2. Güvenli Yedekleme Mekanizması ve WAL/SHM İlkesi

Drift/SQLite istemci veritabanı çalışma zamanında `WAL` (`Write-Ahead Logging`) modunda çalışır. Yalnızca `.db` dosyasını kopyalamak:
1. Birleştirilmemiş (uncheckpointed) `-wal` çerçevelerini kaçırarak veri kaybına yol açar,
2. Çalışan süreç varken yarı tutarlı (bozuk sayfa çerçeveli) bir kopya üretebilir.

Bu nedenle [**`scripts/dev_test/backup_client_db_safe.ps1`**](file:///c:/Users/halil/Github/market-pos/scripts/dev_test/backup_client_db_safe.ps1) aracı geliştirilmiş ve Pure ASCII + PowerShell AST (`NON_ASCII=0`, `PARSE_ERRORS=0`) olarak doğrulanmıştır:
- Kaynak veritabanını native `sqlite3.dll` üzerinden **`SQLITE_OPEN_READONLY` (`0x00000001`)** bayrağıyla açar (kaynak dosyaya, başlığa veya `-wal` dosyasına hiçbir byte yazılmaz),
- **`sqlite3_backup_init` -> `sqlite3_backup_step(-1)` -> `sqlite3_backup_finish`** SQLite Online Backup API ile aktif WAL çerçeveleri dahil tutarlı tek parça anlık görüntüyü `.tmp` dosyasına yazar,
- Hedef anlık görüntü üzerinde **`PRAGMA integrity_check;` = `ok`** doğrulaması yaptıktan sonra hedef dosyaya atomik taşır ve `.sha256` dosyası üretir,
- İşlem öncesi ve sonrası kaynak DB'nin `SHA-256` özetini karşılaştırıp `source_untouched = true` olduğunu doğrular.

---

## 3. TEST_ONLY Ortamda Yürütülen Yedekleme Test Kanıtları

| Test | Girdi / Ortam | Çıktı |
|---|---|---|
| **Test 1 — `client_local.db` Salt Okunur Kopyası** | `%LOCALAPPDATA%\MarketMMS_Isolated_Test\db_backup_test\ro_client_copy.db` | `status: BACKUP_VERIFIED_OK`, `integrity_check: ok`, `backup_size_bytes: 159744`, `backup_sha256: 4988B11F01A85CB6A54A25C58323355D9E813CFE76CA0795D585A65BAB4ABAFB`, gerçek `client_local.db` `SHA-256` değişmedi (`True`). |
| **Test 2 — Aktif Açık Bağlantılı `WAL` Modu DB** | `[MmsClientDbSafeBackup]::CreateTestWalSeedAndVerify` (`PRAGMA journal_mode=WAL;`, açık yazıcı bağlantısı varken canlı online backup) | `WAL_TEST_PASS`: `wal_active_backup.db` (`8.192` B, `SHA256: 0BD810C1B674278199EACEEACDC163807DFA44A4B3E4344E2A5C3506266D3FA0`) oluştu; yalnızca WAL'da bulunan `row_in_db_and_wal` satırı bağımsız yedekte `SQLITE_OPEN_READONLY` ile okundu ve `integrity_check = ok` geçti. |

---

## 4. Fiziksel Kurulum Öncesi Gerçek İstemci DB Yedekleme Prosedürü (Owner / Pilot)

Gerçek MSI veya fiziksel test başlatılmadan hemen önce mevcut makinede güvenli yedek almak için:

```powershell
$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$bakDir = "$env:USERPROFILE\MarketMMS_PreInstall_Backups"
$bakPath = "$bakDir\client_local_$stamp.db"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\dev_test\backup_client_db_safe.ps1 `
  -SourceDbPath "$env:LOCALAPPDATA\MarketMMS\client_local.db" `
  -OutputBackupPath $bakPath
Get-Content "$bakPath.sha256"
```

*Not:* Yukarıdaki komut gerçek `%LOCALAPPDATA%\MarketMMS\client_local.db` dosyasına `SQLITE_OPEN_READONLY` ile bağlanır ve özgün dosyayı değiştirmez.
