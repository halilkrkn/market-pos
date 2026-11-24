# ADR-023: Hub-Centric Google Drive Backup & Restore

- **Karar Kodu:** `ADR-023`
- **Başlık:** Hub-Centric Google Drive Backup & Restore (Merkezi Hub Yedekleme, Portable Recovery, 12-Durum Makinesi, 00.00 Zamanlama ve RBAC)
- **Durum:** **`[CONFIRMED]`** *(Owner **B1.1–B1.12** ve **`OV-01…OV-05`**, **`GAP-A01`**, **`GAP-A03`** kararları kesinleştirilmiştir; gerçek Windows/Android/Drive fiziksel doğrulamaları `BK-PAT-01…18` kapsamında saha kabulüne tabidir.)*
- **Tarih:** 22 Kasım 2026
- **İlgili Belgeler:**
  - [`GOOGLE_DRIVE_BACKUP_ARCHITECTURE_V1_1.md`](../architecture/GOOGLE_DRIVE_BACKUP_ARCHITECTURE_V1_1.md)
  - [`AUTOMATED_BACKUP_SCHEDULING_SPEC_V1_1.md`](../architecture/AUTOMATED_BACKUP_SCHEDULING_SPEC_V1_1.md)
  - [`BACKUP_RESTORE_ACCEPTANCE_TESTS_V1_1.md`](../testing/BACKUP_RESTORE_ACCEPTANCE_TESTS_V1_1.md)
  - [`MASTER_IMPLEMENTATION_DECISIONS.md`](../IMPLEMENTATION/MASTER_IMPLEMENTATION_DECISIONS.md)
  - Önceki İlgili Kararlar: [`016`](./016-backup-reliability-restore-outbox-scheduled-usb-drive.md), [`020`](./020-android-background-backup-workmanager.md), [`021`](./021-hybrid-hub-google-drive-live-sync.md), [`022`](./022-android-google-drive-oauth-design.md)

---

## 1. Context (Bağlam)

MARKET MMS kod tabanında 22 Kasım 2026 tarihinde yürütülen pilot hazırlık denetiminde, Google Drive yedekleme ve geri yükleme uygulamasının Owner tarafından belirlenen merkezi mağaza koruma modeliyle yapısal olarak uyumsuz ve kritik riskler taşır durumda olduğu tespit edilmiştir:

1. **Ters Yedekleme Topolojisi:** Mevcut `GoogleDriveBackupUploader` (`packages/mms_client_storage/lib/src/backup/google_drive_backup.dart`), `GoogleDriveConnectService` ve `AndroidGoogleSignInTokenProvider` yalnızca Flutter **istemcileri** (yerel `client_local.db` / `mms_client.db`) üzerinde çalışmakta, Windows Master Hub (`test_spikes/spike_01_backend/bin/server.dart`) ise Google Drive'a bağlanmamaktadır.
2. **Makineye Bağlı (`pepper.dpapi`) Şifreleme Hatası:** Hub yedeği parola verilmediğinde makineye bağlı `pepperManager.pepper` kullandığından yeni bir Windows PC'de kurtarma imkânsızdır.
3. **`afterSuccess` Yanıltıcı Başarı Hatası:** `ScheduledBackupRunner._run` upload hatasını `postProcessError` içine koyup kaydı `success: true` işaretlemekte, `backup_providers.dart` ise Drive hatasını yakalayıp yutmaktadır.
4. **Windows UI vs `LocalService` DPAPI Sınırı:** UI `CurrentUser` DPAPI blob'ları `NT AUTHORITY\LocalService` tarafından okunamaz; UI hiçbir zaman Hub servis sırlarına doğrudan erişmemelidir.
5. **Parçasız Upload, Hatalı Kota Sınıflandırması ve Korumasız Retention:** Eski uploader tüm dosyayı RAM'e okuyup tek PUT atar (`308` resume yok) ve `403 storageQuotaExceeded` hatasını `ERR_DRIVE_REAUTH_REQUIRED` olarak sınıflar; eski retention ise son geçerli yedeği korumadan tüm yedekleri silebilir.
6. **15 sn Servis Kapanışı vs 2 dk HTTP Timeout & Kapanış Sırası Hatası:** `MarketMMSService.xml` (`15 sec`), `lifecycle_manager.dart` (`12s`), `google_drive_backup.dart` (`2 min`) ve `bin/server.dart` `SIGINT` baypası çelişir.
7. **Yetki, Replay & Restore Mutabakat Eksikliği:** Backup uçlarında `OWNER`/`CASHIER` RBAC, tek seferlik Hub `OWNER` bootstrap, nonce/timestamp replay koruması ve restore sonrası kayıp `SYNCED` operasyonların uzlaştırması eksiktir.

---

## 2. Decision (Kesinleşmiş Mimari Kararlar)

### 2.1. Owner Temel Kararları (`B1.1–B1.12` — `CONFIRMED`)
1. **Merkezi Kaynak:** Backup kaynağı Windows Master Hub merkezi SQLite veritabanıdır (`market_master.db`); Android yerel SQLite DB merkezi backup kaynağı değildir (`B1.1`, `B1.2`).
2. **Doğrudan Hub Upload & Bağlantı:** Windows Master Hub Google Drive'a doğrudan yükler; Google Drive ortak DB değildir, yalnız şifreli yedek saklar; Google hesabı Windows Hub üzerinden bağlanır (`B1.3`, `B1.4`, `B1.5`).
3. **Android Yönetim UI & Eski Akış Ayrımı:** Android uygulaması Hub backup durumunu, geçmişini ve izin verilen ayarları yönetir; Android'in eski yerel yedekleme akışı (`Legacy Yerel Cihaz Yedeği`) ayrı tutulur ve eski yerel yedekler silinmez (`B1.6`, `B1.12`).
4. **Portable Recovery Password:** Hub yedekleri makineye bağlı `pepper.dpapi` yerine taşınabilir kurtarma parolasıyla kurtarılabilir olacaktır (`B1.7`).
5. **Saklama (Retention):** Drive üzerinde son **30 günlük** günlük + son **12 takvim ayı** aylık yedekler + **en az 1 geçerli doğrulanmış `COMPLETED_UPLOADED` yedek** korunur (`B1.8`).
6. **Zamanlama:** İlk etkinleştirmede hemen başlangıç yedeği (`INITIAL_ENABLE`); sonrasında yerel saat `00.00` hedefi, `CATCH_UP` davranışı ve `5/10/20/40/80/160` dk backoff (gün sonuna dek `160` dk sabit) uygulanır (`B1.9`, `B1.10`, `B1.11`).

### 2.2. Owner Kesinleştirilmiş Teknik Kararları (`OV-01…OV-05`, `GAP-A01`, `GAP-A03` — `CONFIRMED`)
1. **`OV-01` (Windows `LocalService` DPAPI):** **LocalMachine DPAPI + `pOptionalEntropy` + sıkı NTFS ACL** (`%PROGRAMDATA%\MarketMMS\security` ve `backups`) kullanılır. Windows UI PKCE `authorization_code` + `code_verifier` alır ve yerel loopback HTTPS üzerinden Hub servisine (`POST /api/v1/backup/oauth/connect`) devreder; Hub `refresh_token`'ı yalnızca servis kasasında `LocalMachine` DPAPI + domain-separated `pOptionalEntropy` + ACL ile saklar. UI hiçbir servis sırrını doğrudan okumaz; gerçek `LocalService` fiziksel doğrulaması `BK-PAT-01/18` (`BLOCKED`) kapsamındadır.
2. **`OV-02` (`ADR-021` & `ADR-022` İzolasyonu):** Hibrit Canlı Senkronizasyon (`.mmsenv`, `ADR-021` + `ADR-022`) ile Merkezi Hub Drive Yedekleme (`.mmsbak`, `ADR-023`) **kesin olarak ayrı** tutulur: ayrı OAuth scope/token/yaşam döngüsü, ayrı Drive klasörü ve ayrı modüller. Android OAuth merkezi yedekleme için gerekmez; `ADR-022` olduğu gibi korunur.
3. **`OV-03` (Restore Sonrası Eksik İşlem & Sequence Uzlaştırması):** Restore sonrası uzlaştırma yalnızca `PENDING` Outbox satırlarına indirgenemez. Mevcut `GET /api/v1/sync/device-state` ve `POST /api/v1/sync/receipts` uçları `restore_epoch` alanıyla genişletilir. İstemci `outbox_operations` geçmişini (`SYNCED` dahil) tam `operation_id`, `device_id`, `client_seq`, `payload`, `payload_hash` ile saklar; `restore_epoch` değiştiğinde veya `hub.high_water_mark_seq < local.lastSyncedSeq` olduğunda Hub'da kayıp (`NOT_FOUND`) görünen önceden `SYNCED` işlemleri özgün kimlik ve sırayla atomik yeniden kuyruğa alır, idempotent tekrar gönderir; herhangi bir kayıp işlemin içeriği yerelde yoksa **fail-closed (`ERR_POST_RESTORE_HISTORY_MISSING`)** reddedip eksik uzlaştırmayı asla başarılı göstermez.
4. **`OV-04` (İlk `OWNER` Cihaz Bootstrap):** Windows Master Hub üzerinde tek seferlik, tekrar kullanılamaz `OWNER` bootstrap mekanizması (`POST /api/v1/admin/owner/bootstrap`) sağlanır. İlk eşleştirilen Android cihaz otomatik `OWNER` **yapılmaz**; eşleştirilen tüm cihazlar varsayılan **`CASHIER`** rolü alır. Yeni `OWNER` rolü atamak için mevcut `OWNER` (veya loopback + admin secret) yetkisi zorunludur.
5. **`OV-05` (Portable Recovery Password & Yerel Önbellek):** Minimum **12 karakter** zorunludur (daha uzun parola/cümle önerilir). Parola düz metin olarak ne Hub'da ne Google Drive'da saklanır; kaybolursa yedek çözülemez. Yerel disk `.mmsbak` önbellek hedefi **7 gündür** ve Drive'ın 30g/12a saklamasından tamamen bağımsızdır.
6. **`MMSBAK02` Taşınabilir AEAD + DEK/KEK Zarfı & `MMSBAK01` Uyumu:** Yeni yedekler `package:cryptography` üzerinden güvenilir `AES-256-GCM` + `PBKDF2-HMAC-SHA256` (`600.000` tur) ile üretilir: rastgele `DEK` şifreler, `KEK` ise `DEK`'i AAD korumalı AEAD ile sarar; büyük dosyalar `RandomAccessFile` ile akışlı (streaming chunk) işlenir. Eski `MMSBAK01` yedekleri tam geriye dönük okunabilir kalır.
7. **12 Durumlu State Machine & 12 sn Kooperatif Kapanış:** `PENDING`, `RUNNING_SNAPSHOT`, `SNAPSHOT_READY`, `RUNNING_ENCRYPT`, `ENCRYPTED_LOCAL_READY`, `UPLOADING`, `VERIFYING`, `COMPLETED_UPLOADED`, `RETRY_PENDING`, `FAILED_AUTH`, `FAILED_QUOTA`, `SUPERSEDED`. Kapanışta `afterSuccess` olmadan aktif upload `< 1.5 sn` kesilir (`RETRY_PENDING`, aynı `backup_id`), SQLite transaction/snapshot kesilmeden beklenir, ardından `wal_checkpoint(TRUNCATE)` ve `db.close()` işletilir.
8. **`GAP-A01` & `GAP-A03`:** İkincil barkod tam-yığın senkronizasyonu (istemci Outbox + Hub `product_barcodes` v3→v4 migration + çakışma reddi + `GET /api/v1/products`) ve `integration_test/android_full_e2e_verification_test.dart` temizliği bu plana dahildir.

---

## 3. Paket Sorumluluk Ayrımı (`Clean Architecture`)

- **`packages/mms_client_storage`:** Saf Dart taşınabilir `MMSBAK02` + `MMSBAK01` kripto formatı, manifest, disk alanı ölçer (`GetDiskFreeSpaceExW`), `RandomAccessFile` 4 MB chunked resumable Drive uploader (`HTTP 308` + `VERIFYING`), 12-durum enum/state modelleri, Drive (30g/12a + `>=1`) vs yerel (7g) retention planlayıcıları, istemci DB ve `OV-03` post-restore mutabakatı. Hub'a özgü servis/OAuth/orkestrasyon sınıfları buraya yığılmaz.
- **`test_spikes/spike_01_backend`:** Hub `WriteQueue` + `VACUUM INTO` snapshot/encrypt aşamaları, `LocalMachine` DPAPI + `pOptionalEntropy` OAuth/Recovery kasaları, PKCE token takası ve yenileme, atomik `backup_jobs_state.json`, 12-durum Hub orkestratörü, aşamalı crash recovery, `restore_epoch` + controlled token invalidation restore servisi, `OWNER`/`CASHIER` RBAC + bootstrap, replay protection ve Hub REST uçları.
- **`market_pos` (kök UI):** Windows PKCE → Hub loopback handoff, `HubBackupClient`, "Merkezi Hub Yedekleme (Google Drive)" vs "Legacy Yerel Cihaz Yedeği (S5A-4)" UI ayrımı.

---

## 4. Açık Fiziksel Doğrulamalar (`BLOCKED — OWNER ACTION REQUIRED`)

Kod ve otomatik FFI/HTTP/widget testleri tüm gereksinimleri doğrular; ancak gerçek `NT AUTHORITY\LocalService` reboot kalıcılığı, gerçek Google Cloud `"In production"` OAuth & kota yanıtları, üretim TLS sertifikaları (`B2`), Android keystore (`B1`), ikinci temiz Windows PC ve fiziksel Android cihaz testleri (**`BK-PAT-01…BK-PAT-18`**, **`PAT-01…15`**, **`D1–D4`**) sahada Owner tarafından doğrulanana kadar **`BLOCKED`** kalır.

---

## 5. Uygulama Notları (23 Kasım 2026)

Karar anlamı değiştirilmeden uygulanan teknik ayrıntılar [`MASTER_IMPLEMENTATION_DECISIONS.md`](../IMPLEMENTATION/MASTER_IMPLEMENTATION_DECISIONS.md) §3'te `IMP-01…IMP-07` olarak kayıtlıdır. Özet:
- `B1.7`, eski S5A-4 Hub uçlarına ve eski aralıklı zamanlayıcıya da uygulandı: parolasız yedek artık pepper ile değil Portable Recovery Password ile şifrelenir; tanımlı değilse fail-closed (`IMP-01`). Eski pepper-şifreli yedekler yalnızca aynı makinede açık `legacy_machine_key` onayıyla açılır (`IMP-02`).
- Merkezi restore ucunda uzak `OWNER` için dosya yolu kapatıldı (yalnız `backup_id`), UNC yolları ve istemci kontrollü PBKDF2 turu reddedildi (`IMP-03`).
- Drive retention, silinen kopyaların durum kaydını temizler; "en az 1 geçerli yedek" değişmezi gerçek duruma göre hesaplanır (`IMP-04`).
- Gerçek test sonuçları: [`FINAL_PILOT_READINESS_REPORT.md`](../FINAL_PILOT_READINESS_REPORT.md).

---

## 6. Uygulama Notları (23 Kasım 2026 (2. tur) — Commit Öncesi Bağımsız İnceleme S1–S6)

Karar anlamı değiştirilmedi; ayrıntılar [`MASTER_IMPLEMENTATION_DECISIONS.md`](../IMPLEMENTATION/MASTER_IMPLEMENTATION_DECISIONS.md) §4'te `IMP-08…IMP-15` olarak kayıtlıdır.
- **Zamanlayıcı dayanıklılığı (`IMP-08`):** Dakikalık zamanlayıcı ve açılış kurtarması tek güvenli giriş noktası (`runGuardedTick`) kullanır; kilit çakışması sonraki tura ertelenir, diğer hatalar loglanır ve `scheduler_last_error` olarak raporlanır; hiçbir hata Hub sürecini sonlandırmaz.
- **`B1.7` netleştirmesi (`IMP-09`):** Manuel merkezi yedek de yalnızca Hub'da kayıtlı Portable Recovery Password ile şifrelenir; istekle gelen parola kabul edilmez (`ERR_RECOVERY_PASSWORD_NOT_ACCEPTED`). Kaydetme (`/backup/recovery-key`) ve yedekleme (`/backup/run`) ayrı işlemlerdir.
- **Durum deposu eşzamanlılığı (`IMP-10`):** `backup_jobs_state.json` yazmaları seri, alan bazlı ve atomiktir; 12 durumlu makine değişmedi.
- **Drive klasör ayrımı (`IMP-13`):** Hub yedekleri `MARKET MMS Yedekleri/Hub` alt klasöründe; eski istemci yedekleri kök klasörde; `ADR-021` LiveSync klasörü ve ayrı OAuth kapsamları/kasaları değişmedi.
- **Entropy dokümantasyonu (`IMP-12`):** Kasalar sabit, amaç-ayrımlı entropy kullanır (`MarketMMS:HubBackupDriveOAuth:v1`, `MarketMMS:HubBackupRecoveryKey:v1`); doküman koda hizalandı, mevcut DPAPI sırları korunarak kod değiştirilmedi.
- Fiziksel doğrulamalar (§4) değişmeden **`BLOCKED`** kalır.
