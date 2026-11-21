# ADR-021 — Hub Öncelikli, Google Drive Destekli Hibrit Canlı Senkronizasyon Mimarisi

- **Karar Kodu:** ADR-021
- **Durum:** `[CONFIRMED — TEKNİK TASARIM VE UYGULAMA]` (Owner Release 1.0 Kapsam Kararı; fiziksel saha doğrulaması `PAT-18` gerektirir)
- **Tarih:** 2026-11-21
- **Sorumlu Bileşenler:**
  - `packages/mms_client_storage/lib/src/sync/hybrid_drive_live_sync.dart`
  - `lib/features/sync/domain/sync_coordinator_state.dart`
  - `lib/features/sync/application/background_sync_coordinator.dart`
  - `lib/features/sync/sync_providers.dart`
  - `lib/features/diagnostics/presentation/screens/diagnostics_view.dart`

---

## 1. Bağlam ve Problem

MARKET MMS birincil olarak **Windows Local Master Hub** üzerinden yerel ağda (LAN) senkronize olur (`ADR-012`). Ancak mağaza içinde Windows Hub makinesi uzun süreli kapandığında, donanım/ağ arızası yaşadığında veya internet üzerinden çoklu mobil cihaz geçici süre birbirinin satış/stok/ürün hareketlerinden haberdar olmak istediğinde salt Hub bağlantısı tek hata noktası oluşturabilir.

Google Drive zaten şifreli yedekleme için (`ADR-011`, `drive.file`) entegre edilmiştir. Owner, Release 1.0 kapsamında **Hub öncelikli** kalmak şartıyla kontrollü **Google Drive canlı senkronizasyon fallback** mimarisini pilot kapsamına almıştır.

---

## 2. 20 Mimari Tasarım Sorusunun Kanonik Cevapları

### S1. Birincil otorite ve Hub önceliği nasıl korunur?
Windows Local Master Hub **her koşulda tekil katalog ve satış otoritesidir**. Hub sağlıklı erişilebildiği sürece (`HubStatus == Online`) hiçbir canlı işlem Google Drive relay'ine yazılmaz veya okunmaz; Drive senkronizasyonu tamamen beklemede kalır.

### S2. Google Drive fallback tam olarak ne zaman devreye girer?
Yalnızca **doğrulanmış Hub ulaşılamazlığı** oluştuğunda: ardışık ağ/timeout/5xx bağlantı hatası eşiği (`fallbackFailureThreshold`, varsayılan `2`) aşıldığında `SyncDriveMode.driveFallbackActive` devreye girer. Tek anlık paket kaybında hemen Drive'a geçilmez.

### S3. Hangi durumlarda Drive fallback KESİNLİKLE devreye GİRMEZ?
1. **`tlsPinMismatch` (TLS Sertifika Parmak İzi Uyuşmazlığı)** — MITM/güvenlik şüphesi; sistem fail-closed durur.
2. **`tlsCertError` (TLS SAN/CA/Tarih Sertifika Hatası)** — güvenlik doğrulaması başarısız; bypass yasaktır.
3. **`authRequired` (401/403 token iptali)** — yetki sorununu gizlemek için Drive'a geçilmez.
4. **Kullanıcı tarafından duraklatılmış (`paused`) veya Drive bağlantısı/sırrı yapılandırılmamış** durumlarda.

### S4. Neden Google Drive üzerinde paylaşılan canlı `.db` (SQLite) dosyası tutulmaz?
Birden fazla cihazın Google Drive'daki aynı SQLite dosyasına yazması **dosya bozulmasına, WAL kaybına ve sessiz veri ezilmesine (split-brain)** yol açar. Bunun yerine Drive yalnızca **değiştirilemez (immutable, append-only), işlem başına tekil şifreli zarf (`.mmsenv`)** mesaj kuyruğu / relay alanı olarak kullanılır.

### S5. Drive klasör yapısı ve dosya adlandırma şeması nasıldır?
`MMS LiveSync/` klasörü (en dar `drive.file` yetkisi altında) içinde işlem başına tekil dosya açılır:
`env_<tenantId>_<storeId>_<deviceId>_<clientSeq_12hane>_<operationId>.mmsenv`
`appProperties`: `mms_env_v`, `mms_tenant_id`, `mms_store_id`, `mms_device_id`, `mms_client_seq`, `mms_op_id`, `mms_op_type`, `mms_sha256`. Mevcut aynı `(device_id, client_seq, operation_id)` zarfı bir daha yüklenmez (idempotent).

### S6. Zarf kriptografisi (`MMSENV01`) ve yedek parolasından ayrım nasıl sağlanır?
Her zarf `MMSENV01` başlığıyla şifrelenir:
`[MMSENV01 (8B)] + [MetaLen (4B BE)] + [MetaJSON] + [Salt (16B)] + [IV (16B)] + [Ciphertext (AES-256-CBC + PKCS7)] + [HMAC-SHA256 Tag (32B)]`.
- Anahtarlar, **yedek parolasından tamamen bağımsız** `drive_live_sync_secret_v1` gizlisinden `MMS-LIVESYNC-ENV-V1|<tenantId>|<storeId>` domain ayırıcısı ve PBKDF2-HMAC-SHA256 ile türetilir (`encKey` 32B, `hmacKey` 32B).
- Encrypt-then-MAC doğrulaması çözmeden önce `BackupCryptoService.constantTimeEquals` ile yürütülür; HMAC geçmezse şifre çözmeye asla geçilmez.
- İsteğe bağlı/kayıtlı cihaz ECDSA P-256 / HMAC imza alanı (`deviceSignatureBase64`) desteklenir.

### S7. Yetkisiz veya iptal edilmiş (`REVOKED`) cihazlar nasıl engellenir?
`DriveAuthorizedDeviceRegistry` her mağaza için yetkili cihaz durumlarını (`ACTIVE` / `REVOKED`) tutar. `REVOKED`, bilinmeyen, imzası bozuk veya farklı `tenant_id`/`store_id` taşıyan tüm zarflar reddedilir (`DriveSyncSecurityException` / güvenlik sayacı) ve yerel veritabanına işlenmez.

### S8. Cihaz saatleri kaymışsa sıralama neden bozulmaz?
Sıralama ve tutarlılık **asla cihaz duvar saatine (`occurredAt`) dayanmaz**. Her kaynak cihaz bağımsız tekil monotonik `(origin_device_id, client_seq)` sırası üretir (`ADR-007`). Saat 1970'e veya geleceğe ayarlı cihazlar dahil işlem sırası bozulmaz.

### S9. Sıra dışı (Out-of-Order) ve boşluklu (`gap`) zarflar nasıl ele alınır?
Alıcı cihaz `DriveLiveSyncLedger` içinde her `origin_device_id` için `lastAppliedSeq` değerini tutar. Yalnızca `seq == lastAppliedSeq + 1` olan **bitişik** zarf işlenir; `seq > lastAppliedSeq + 1` zarflar uygulanmaz (aradaki eksik işlemin gelmesi beklenir) ve `seq <= lastAppliedSeq` zarflar idempotent olarak atlanır.

### S10. Yerel `outbox_operations` ve `client_seq` Drive yüklemesinden nasıl korunur?
Cihaz kendi bekleyen Outbox satırlarını Drive'a yüklediğinde Drive'dan başarı dönse bile yerel `outbox_operations.status` **ASLA `SYNCED` yapılmaz**. Kayıt `PENDING`/`RETRY` olarak korunur ve yalnızca `DriveLiveSyncLedger.lastUploadedSeqByDevice` güncellenir; Hub'a gerçek ACK iletildiğinde `SYNCED` olur.

### S11. Yankı döngüsü (Echo Loop) nasıl önlenir?
1) Cihaz kendi `origin_device_id == localDeviceId` zarflarını Drive'dan geri indirip uygulamaz.
2) Diğer cihazlardan Drive üzerinden gelen zarflar doğrudan yerel tablolara (`local_sales`, `local_sale_items`, `local_stock_movements`, `local_products`) işlenir; **kesinlikle yerel `outbox_operations` kuyruğuna eklenmez**.

### S12. Satış, iptal, iade ve stok girişinde veri kaybı/çift sayım nasıl önlenir?
- `SALE_CREATE`: `(origin_device_id, client_seq)` tekilliği + `local_sales` benzersiz kısıtı ile çift yazım engellenir; stok `-stockDelta` uygulanır (eksi stok `allow`).
- `SALE_CANCEL` / `SALE_REFUND`: İlgili satışın durumu (`CANCELLED`, `REFUNDED`, `PARTIALLY_REFUNDED`) ve stok/fire hareketleri idempotent ID ile işlenir; hedef satış yoksa bekletilir.
- `STOCK_RECEIPT`: `receipt_id` bazlı idempotent `GIRIS` hareketi + `stock + quantityMilli` atomik delta uygulanır.

### S13. Eşzamanlı `PRODUCT_UPSERT` değişikliklerinde LWW (Last-Write-Wins) neden yasaktır ve ne yapılır?
Farklı iki cihazın aynı ürün üzerinde internet/Hub yokken fiyat veya isim değiştirmesinde saate göre sessiz LWW veri kaybı/fiyat uyuşmazlığı riski doğurur. Bunun yerine **çakışma tespiti (Conflict Detection & Flagging)** uygulanır: hedef ürün için yerelde gönderilmemiş bir `PRODUCT_UPSERT` veya mevcut farklı bir `price_version_id` varsa çakışma `DriveSyncConflictRecord` olarak `DriveLiveSyncLedger`'a kaydedilir, UI'da Owner/kasiyer bilgilendirilir ve son çözüm Master Hub dönüşüne bırakılır.

### S14. Windows Master Hub geri geldiğinde (Reconciliation) adım adım ne olur?
Hub erişilebilir olduğunda (`reconcileWithMasterHub`):
1. Cihaz önce kendi bekleyen tüm yerel `outbox_operations` kayıtlarını FIFO (`client_seq ASC`) sırasıyla Hub'a gönderir (`syncPendingOutbox`).
2. Ardından authoritative ürün kataloğunu (`syncProducts`) ve satış cursor'ını (`syncSales`) Hub'dan çeker.
3. Yalnızca her iki adım da hatasız tamamlandığında `pendingHubReconciliation = false` ve `active = false` işaretlenir; Drive kaynaklı çakışma bayrakları Hub otoritesiyle temizlenir.
4. Başka cihazların offline yaptığı satışların Drive üzerinden geçici yansıtılmış olması, Hub `syncSales` cursor'ını bozmaz (`upsertSales` aynı `(device_id, client_seq)` satırını idempotent günceller).

### S15. Hub'dan gelen otorite ile çakışan Drive verisi nasıl çözümlenir?
Hub döndüğünde ürün fiyat/katalog otoritesi her zaman Hub'daki sürümdür (`syncProducts`); satış ve stok hareketleri ise tüm cihazların monotonic `Outbox` kayıtları Hub'a ulaştıkça merkezi defterde deterministik sırada birleşir.

### S16. Kısmi arıza, oran sınırı (HTTP 429) ve büyük dosya koruması nasıldır?
- İstek boyut üst sınırı (`maxEnvelopeBytes = 512 KB`).
- Google Drive 429 / 5xx yanıtlarında üstel bekleme (exponential backoff) uygulanır.
- Drive upload/download sırasında yerel veritabanı yarım transaction görmez; her zarf tek SQLite transaction'ı ile atomik uygulanır veya rollback edilir.

### S17. Restore ve BackupOperationLock ile koordinasyon nasıldır?
Canlı yedekleme veya geri yükleme kilidi (`BackupOperationLock`) tutuluyorken Drive canlı senkronizasyon turu atlanır (`driveFallbackSkippedLock`); böylece restore journal ve WAL checkpoint işlemleri Drive sync ile çakışmaz.

### S18. Kullanıcı arayüzünde hangi 10 durum açıkça gösterilir?
`SyncCoordinatorState` + `DiagnosticsView` tüm 10 durumu deterministik sunar:
1. Hub Primary (`hubPrimary`)
2. Hub Offline Confirmed (`hubOfflineConfirmed`)
3. Drive Sync Enabled / Standby (`driveStandby`)
4. Drive Fallback Active (`driveFallbackActive`)
5. Drive Syncing (`driveSyncing`)
6. Drive Synced / Up-to-date (`driveSynced`)
7. Drive Offline Error (`driveOfflineError`)
8. Drive Conflict Detected (`driveConflictDetected`)
9. Hub Recovered — Reconciling (`hubReconciling`)
10. Hub Synchronized — Reconciled (`hubReconciled`)

### S19. Güvenli kimlik ve anahtar yönetimi (Security & Log Hygiene) nasıldır?
`drive_live_sync_secret_v1` ve OAuth tokenları asla SQLite tablolarına, Drive zarf meta verilerine veya loglara düz metin yazılmaz; işletim sistemi güvenli anahtarlığında (`SecureTokenStore`: Windows DPAPI / Android Keystore) tutulur. Zarf meta verisi yalnızca kimlik/sıra/SHA-256 bilgisini taşır; satış kalemi veya tutar şifresiz metadata'da yer almaz.

### S20. Pilot kapsamı vs Post-Pilot sınırları nelerdir?
- **Pilot Kapsamı (Release 1.0):** Tek mağaza içinde çok cihazlı (Windows + Android) Hub-öncelikli + Drive fallback canlı senkronizasyon (yukarıdaki tam protokol + 26 otomatik senaryo + `PAT-18` fiziksel test planı).
- **Post-Pilot Kapsam Dışı:** Çok şubeli bulut PostgreSQL/Supabase zincir senkronizasyonu (`AGENTS.md` §2) ve Google Drive üzerinde gerçek zamanlı Push Webhook (FCM) bildirim tetikleme (pilot periyodik poll/tetikleme kullanır).

---

## 3. Sonuçlar ve Riskler

- Hub çevrimiçiyken Drive trafiği sıfır kalır; bant genişliği ve Drive kota kullanımı optimize edilir.
- Gerçek Google OAuth ve fiziksel 2 cihaz arası Hub-kapalı Drive relay akışı saha ortamında **`PAT-18`** ile Owner tarafından fiziksel olarak doğrulanacaktır.
