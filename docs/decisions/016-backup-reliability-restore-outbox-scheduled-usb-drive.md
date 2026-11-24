# ADR 016: Yedekleme Güvenilirliği — Restore'da Outbox Korunması, Zamanlanmış Yedek, USB ve Google Drive

- **Durum:** **CONFIRMED** (Mevcut backup/restore tasarımı, lock güvenilirliği ve dokümantasyon düzeltmeleri onaylandı; fiziksel donanım testleri **BLOCKED**)
- **Tarih:** 2026-11-21
- **Karar Vericiler:** Owner (Onay), Öneren: Claude Code / Uygulayan: Antigravity (Ek B)
- **İlgili:** ADR-008 (ADR-BAK-03 / DEC-BAK-02), ADR-009, ADR-010, ADR-011 (`drive.file`), ADR-015 (REL-01)

---

## 1. Bağlam

1. **ADR-008 / ADR-BAK-03** (CONFIRMED), restore sırasında Hub'a ulaşmamış Outbox işlemlerinin silinmemesini ve `client_seq` sayacının `max(yedek, canlı)` ile ilerletilmesini zorunlu tutuyordu. Kod bunu **uygulamıyordu**: istemci restore'u canlı dosyayı yedekle değiştiriyor, yedekten sonraki bekleyen satışları siliyor ve sayacı geriye alıyordu. Sonuç: satış kaybı ve aynı sıra numarasının farklı içerikle yeniden üretilmesi (Hub `409 ERR_IDEMPOTENCY_CONFLICT`, kuyruk kilidi).
2. Restore hazırlığında (güvenlik yedeği yazımı) hata olursa canlı DB / Hub servisi duraklatılmış kalıyordu.
3. Zamanlanmış yedek yoktu (Hub ve istemci). USB aktarımı ve Google Drive entegrasyonu yoktu.

## 2. Karar

### 2.1 Restore (veri protokolü DEĞİŞMEDİ)
- `ClientRestoreReconciler.mergeLiveOutboxIntoStaging`: canlı DB duraklatılıp WAL checkpoint yapıldıktan sonra, swap'tan **önce** staging DB'ye canlı `outbox_operations` satırları `INSERT OR REPLACE` ile yazılır (canlı satır her zaman kazanır; `operation_id`, `payload`, `payload_hash`, `client_seq` değişmez). `current_client_seq` ve `last_synced_seq` = max; `last_server_sale_seq` yedekteki değerinde kalır → yedekten sonraki satışlar Hub'dan yeniden indirilir.
- İstemci DB türlerinde (`clientLocal`, `mobileLocal`) varsayılan açık; merkezi Hub DB'sinde kapalı (Hub için istemcilerin yeniden gönderimi geçerli kural olmaya devam eder).
- Restore iki aşamalı: **hazırlık** (canlı dosyaya dokunulmaz; her hata → canlı DB yeniden açılır, staging/journal silinir, `ERR_RESTORE_PREPARATION_FAILED`) ve **swap** (mevcut rollback/journal).
- Şube (store) doğrulaması motora taşındı (`expectedStoreId`); Hub ve istemci aynı kontrolü kullanır.
- İstemci restore'u öncesi arka plan senkronizasyonu `pauseForMaintenance()` ile durdurulur, sonrasında `resumeAfterMaintenance()`.
- **Bilinen sınır:** Yedekten sonra oluşan bekleyen işlemlerin *yerel satır kayıtları* (ör. `local_sales`) geri yüklenen DB'de yoktur; işlemler Hub'a gönderildikten sonra satış downlink'i ve ürün snapshot'ı ile geri gelir.

### 2.2 Zamanlanmış yedek
- Ortak saf iş kuralı: `BackupSchedulePolicy` (aralık, başarısızlık sonrası 30 dk bekleme, gecikme tespiti), `ScheduledBackupRunner` (single-flight, hata sınıflandırma `ERR_DISK_FULL` / `ERR_TARGET_UNAVAILABLE`, saklama politikası, isteğe bağlı sonraki adım), `BackupScheduleStateStore` (atomik JSON; bozuk dosya karantinaya alınır). DB şeması değişmedi.
- **Hub:** `hub_config.json` → `backup_schedule {interval_hours (0–168, varsayılan 24; 0 kapalı), daily_retention_days, monthly_retention_months}`. Parola: DPAPI korumalı pepper (mevcut admin yedeğiyle aynı). *(23 Kasım 2026 — ADR-023 `B1.7` ile **geçersiz kılındı**: parola artık Owner'ın Portable Recovery Password'üdür (`backup_recovery_key.dpapi`); tanımlı değilse yedek alınmaz (`ERR_RECOVERY_KEY_NOT_CONFIGURED`). Bkz. [`MASTER_IMPLEMENTATION_DECISIONS.md`](../IMPLEMENTATION/MASTER_IMPLEMENTATION_DECISIONS.md) `IMP-01/02`.)* Durum dosyası DB dizininde (yedek hedefi erişilemese bile hata kaydedilir). `GET /api/v1/admin/backup/status` (loopback + admin) ve `/health.backup` (yol/hata ayrıntısı içermeyen özet). Servis kapanışında devam eden yedek beklenir.
- **İstemci:** 6/12/24 saat; parola yalnızca güvenli depoda (DPAPI / Android Keystore), ayar dosyasında değil. Android'de zamanlayıcı uygulama açıkken çalışır; açılışta gecikmiş yedek hemen alınır (arka plan iş zamanlayıcısı yeni bağımlılık gerektirir → Owner kararı).

### 2.3 USB / harici klasör (Windows)
- `BackupFileTransfer.exportToDirectory`: `.tmp` + flush + geri okuma SHA-256 + atomik rename; üzerine yazmaz; disk dolu / aygıt çıkarıldı / sessiz bozulma ayrı kodlarla raporlanır, yarım dosya bırakılmaz.
- `importFromFile`: parolasız yapısal doğrulama (başlık + manifest + beklenen uzunluk → `ERR_INCOMPLETE_BACKUP`), tür/cihaz/tenant/şube kontrolü. HMAC ve SQLite bütünlüğü restore sırasında doğrulanır.
- Dizin seçimi metin alanıyla yapılır (dosya seçici paketi yeni bağımlılık olurdu).

### 2.4 Google Drive (canlı senkron değil)
- `drive.file` kapsamı, PKCE (S256) + loopback yönlendirme (Windows), `state` CSRF kontrolü, refresh token yalnızca güvenli depoda.
- `GoogleDriveBackupUploader`: yalnızca şifreli `.mmsbak`; `MARKET MMS Yedekleri` klasörü; `appProperties.mms_backup_id` ile uzaktan tekrar yükleme engeli + yerel kayıt defteri; resumable upload; yükleme sonrası boyut + MD5 doğrulaması (uyuşmazsa uzak kopya silinir); 401'de bir kez token yenileme; 429/5xx/ağ hatasında üstel bekleme; hata yerel yedeği başarısız yapmaz, sonraki turda `uploadPending` ile tekrar denenir.
- OAuth istemci kimliği derlemede `--dart-define=MMS_GDRIVE_CLIENT_ID` ile verilir; tanımlı değilse Drive devre dışıdır.

## 3. Sonuçlar

- **Olumlu:** Restore artık satış kaybetmiyor ve `client_seq` tekrar etmiyor; disk dolu/USB çıkarılması güvenli; Hub ve istemci otomatik yedek alıyor; Drive altyapısı hazır.
- **Açık / BLOCKED:** Gerçek Google Cloud projesi ve OAuth istemci kimliği (Owner); Android Drive bağlantısı (Google Sign-In SDK — yeni bağımlılık, Owner kararı); fiziksel USB ve Hub servis testleri.
- **Testler:** `restore_outbox_preservation_test` (5), `scheduled_backup_runner_test` (14), `backup_file_transfer_test` (10), `google_drive_backup_test` (11), `hub_scheduled_backup_test` (10), `backup_schedule_controller_test` (7), koordinatör #29–30.

---

## Ek A — 21.11.2026 (3. oturum): Güvenlik kopyası şifreleme, yedek kilidi, Drive koruması, Android otomatik yedek

Durum: **CONFIRMED** (Ek A ve Ek B kodda uygulandı, otomatik testlerle doğrulandı; fiziksel USB/donanım testleri **BLOCKED**). Veri protokolü (Outbox, `client_seq`, hash, cursor) **değişmedi**; DB şeması **değişmedi**.

### A.1 SEC-SAFETY — Restore güvenlik kopyası şifreli saklanır
- **Bağlam:** Restore öncesi alınan güvenlik kopyası (`backups/safety`, Hub'da `backups/safety_snapshots`) şifresiz `.db` olarak kalıcı tutuluyordu. Hub kopyası cihaz token hash/salt değerlerini içerir; yedek dizini USB/NAS olabilir.
- **Karar:** Şifresiz kopya yalnızca restore SÜRESİNCE (rollback / journal kurtarma penceresi) tutulur. Swap başarılı olup journal silindikten ve canlı DB yeniden açıldıktan sonra kopya, **geri yüklenen yedeğin parolası ve KDF iterasyon sayısıyla** standart `.mmsbak` paketine dönüştürülür (`LocalStorageProvider.saveBackup`: `.tmp` + doğrulama + atomik rename), yazılan dosya bayt düzeyinde (uzunluk + SHA-256) doğrulanır, ancak ondan sonra şifresiz kopya silinir. Manifest `app_version = "pre-restore-safety"`.
- **Hata davranışı:** Şifreleme başarısız olursa restore başarısız SAYILMAZ; şifresiz kopya korunur, `RestoreResult.safetyBackupEncrypted = false` ve uyarı loglanır (kurtarma noktası kaybı yerine görünür risk).
- **Geriye dönük uyumluluk:** Eski şifresiz kopyalara **dokunulmaz** (silinmez, dönüştürülmez). `encryptSafetyBackup: false` ile eski davranış açıkça seçilebilir. Hub restore yanıtına `safety_backup_encrypted` alanı eklendi (ek alan; mevcut alanlar aynı).
- **Ödünleşim:** Restore bir PBKDF2 türetmesi daha yapar (ayrı isolate'te; UI donmaz). Masaüstünde birkaç saniye, düşük donanımlı Android'de onlarca saniye ek süre beklenir (gerçek cihazda ölçülmedi — PAT-14). Restore nadir yapılan bir işlemdir.
- **Kurtarma:** Şifreli güvenlik kopyası normal restore akışıyla (aynı parola, aynı cihaz/şube) geri yüklenir — bkz. `docs/operations/BACKUP_AND_RESTORE_GUIDE.md` §7.
- **Testler:** `restore_safety_snapshot_encryption_test` (6), `s5a4_backup_restore_test` #5 (beklenti güncellendi), Hub `s5a4_central_restore_lifecycle_test`.

## Ek B — 21.11.2026 (Teknik Düzeltme Oturumu): `BackupOperationLock` Sertleştirme ve Tam Kapsam (`CONFIRMED`)

- **Bağlam:** Restore sırasında zamanlayıcı tetiklenirse yedek kapalı DB'ye çarpıp "başarısız" kaydediliyor, 30 dk yeniden deneme gecikmesi başlıyordu. Ayrıca ilk sürümdeki sabit 1 saat stale timeout'u süreç çökmesi (`SIGKILL`/elektrik kesintisi) sonrasında yeni yedek/restore işlemlerini 1 saat bloklayabiliyordu ve Hub tarafında prune/snapshot ile istemcide `prune/export/import/delete` ortak kilit dışındaydı.
- **Karar (Ek B Sertleştirmesi):** `BackupOperationLock` — yedek dizininde `.mms_backup_operation.lock` dosyasının özel (`exclusive: true`) oluşturulması üzerine kurulu isolate ve süreçler arası kilit:
  - **Lease + Heartbeat + Sahip Doğrulaması:** Varsayılan `staleAfter = 60 sn` ve `heartbeatInterval = 10 sn`. Aktif kilit sahibi (`owner_id`/`token`) işlem sürdükçe atomik tmp+rename ile `heartbeat_at` damgasını yeniler ve süre sınırı aşımı / art arda erişim hatasında sahipliği güvenli düşürür (`_markOwnershipLost`).
  - **Güvenli Çökme Kurtarma ve TOCTOU Koruması:** Süreç çökerse heartbeat durur ve kilit 60 sn (yarım kalmış `0` bayt oluşturma artıkları `emptyLockStaleAfter = 5 sn`) sonrasında devralınır. Eski kilidi devralma işlemi sahip belirteçli `.recovering` mutex dosyası altında çift doğrulama ile yürütülür; iki kurtarıcı birbirinin taze `.recovering` kilidini silemez ve aktif sahip ezilmez. Eski v1 kilit biçimiyle geriye dönük uyumludur.
  - **Tam Kapsam (İstemci + Hub):** `ClientBackupService` içinde yedek, restore, `pruneExpiredBackups`, `exportLatestBackupTo`, `importBackupFile` ve `deleteBackup`; Hub'da ise `createEncryptedHubBackup`, `/api/v1/admin/restore`, `/api/v1/admin/backup/prune` ve zamanlayıcı saklama temizliği ortak kilit altındadır (meşgulde istemci `ERR_BACKUP_OPERATION_BUSY`, Hub HTTP `409 ERR_BACKUP_OPERATION_BUSY`). Salt-okunur `/api/v1/backup/snapshot` uç noktası `writeQueue` ile sıralanıp benzersiz nonce dosya adı üretir ve restore sırasında `admissionGate` + `pauseForMaintenance` ile engellenir.
  - **Outbox & `client_seq`:** Kilitli restore akışında da canlı bekleyen Outbox satırları ve monotonik `client_seq` korunur.
- **Testler:** `backup_operation_lock_test` (14 test: SIGKILL süreç çökmesi, heartbeat ömür uzatma, 6-isolate TOCTOU yarışı, sahip doğrulamalı `.recovering`, 0-bayt hızlı kurtarma, eski sahip güvenliği, v1 uyumluluğu), `client_backup_operation_lock_test` (5), `restore_outbox_preservation_test` (5), `hub_scheduled_backup_test` (10).
- **Fiziksel Sınır:** Gerçek USB, gerçek Android düşük donanım PBKDF2 süresi ve uzun süreli güç kesintisi testleri (`PAT-07`, `PAT-14`, `PAT-15`) **BLOCKED**.

### A.3 Drive'a yalnızca şifreli paket
- `GoogleDriveBackupUploader.upload` ağ isteğinden önce paket başlığını/manifestini okur; şifresiz dosya veya manifesti beklenen yedekle (kimlik, cihaz, tür) eşleşmeyen dosya `ERR_DRIVE_NOT_ENCRYPTED_PACKAGE` ile reddedilir. Testler: `google_drive_backup_test` #8b, #8c (fikstürler gerçek şifreli pakete çevrildi).

### A.4 SEC-ABK — Android otomatik yedekleme kapalı
- Android varsayılanı (`allowBackup=true`) yerel SQLite'ı ve kurulum kimliğini Google bulut yedeğine / yeni cihaza kopyalar: şifresiz veri ADR-010/011 dışında çıkar ve aynı `device_id` iki cihazda yaşarsa Hub'da sıra/idempotency çakışması oluşur. Manifest: `allowBackup="false"`, `fullBackupContent="false"`, `dataExtractionRules` (API 31+, bulut ve cihaz aktarımında tüm alanlar hariç). Test: `android_release_hardening_test` (4); debug derlemede birleşik manifest doğrulandı.
