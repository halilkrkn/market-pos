# PHASE 1.3.1 — OUTBOX VE ARKA PLAN SENKRONİZASYONU ÖN TEKNİK İNCELEME RAPORU

**Belge Kimliği:** `PHASE_1_3_1_SYNC_TECHNICAL_ASSESSMENT.md`  
**Tarih:** 13 Kasım 2026  
**Aşama:** Faz 1.3 — Kasa Senkronizasyonu & Satış Geçmişi / İptal-İade (Alt Aşama 1.3.1 Hazırlığı)  
**Kapsam:** `ClientSyncService`, `outbox_operations`, `LocalDatabaseService`, Riverpod Entegrasyonu, Hub API İletişimi  
**Durum:** **TAMAMLANDI — PROJE SAHİBİ İNCELEMESİNE HAZIR (READ-ONLY ANALİZ)**  

---

## 1. Yönetici Özeti ve 8 Kritik Sorunun Cevapları

Faz 1.2 POS Kasa Satış Ekranı geliştirmesi başarıyla tamamlanmış ve `e9e1df5` commit'i ile depoya gönderilmiştir. Faz 1.3'ün ilk adımı olan **Faz 1.3.1 (Outbox ve Arka Plan Senkronizasyonu)** kapsamında, mevcut senkronizasyon altyapısının Flutter Windows istemcisine nasıl entegre edileceğini belirlemek amacıyla derinlemesine bir salt okunur (read-only) mimari inceleme gerçekleştirilmiştir.

İnceleme sonucunda belirlenen 8 kritik sorunun net cevapları aşağıdadır:

### Soru 1: `ClientSyncService` bugün gerçekten çalıştırılıyor mu, yoksa yalnızca altyapısı mı mevcut?
> **Cevap: Yalnızca altyapısı mevcuttur; Flutter uygulamasında fiilen çalıştırılmamaktadır.**  
> `ClientSyncService`, [`packages/mms_client_storage/lib/src/sync/client_sync_service.dart`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/sync/client_sync_service.dart#L27-L46) altında eksiksiz, test edilmiş ve sağlam bir altyapı olarak bulunmaktadır. Ancak Windows Flutter istemcisi (`lib/`) içinde hiçbir yerde bu sınıfın örneği (`instance`) üretilmemekte, hiçbir Riverpod provider'ına bağlanmamakta ve ne `main.dart`'ta ne de herhangi bir ekranda çağrılmamaktadır. Yalnızca paket birim ve entegrasyon testlerinde ([`s5a3_outbox_sync_test.dart`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/test/s5a3_outbox_sync_test.dart) ve [`s5a3_live_hub_integration_test.dart`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/test/s5a3_live_hub_integration_test.dart)) bağımsız olarak çalıştırılmaktadır.

### Soru 2: Windows istemcisinde otomatik senkronizasyon var mı?
> **Cevap: Hayır, kesinlikle yoktur.**  
> İstemci tarafında çalışan herhangi bir arka plan worker'ı, periyodik timer veya olay güdümlü senkronizasyon tetikleyicisi bulunmamaktadır. Kasa satış akışında ([`lib/features/pos/application/cart_notifier.dart`](file:///c:/Users/halil/Github/market-pos/lib/features/pos/application/cart_notifier.dart#L259-L267)) yer alan `onSaleCommitted` callback'i, yalnızca [`SystemStatusNotifier.refreshStatus()`](file:///c:/Users/halil/Github/market-pos/lib/features/diagnostics/application/system_status_notifier.dart#L53-L97) metodunu çağırarak yerel veritabanındaki kayıt sayısını ve Hub sağlık durumunu (`/health`) güncellemektedir; hiçbir ağ aktarımı başlatmamaktadır.

### Soru 3: Outbox kayıtları hangi koşullarda gönderiliyor?
> **Cevap: Yalnızca `ClientSyncService.syncPendingOutbox()` metodu çağrıldığında ve aşağıdaki sıra gözetilerek gönderilir:**  
> 1. Varsa önceki yarım kalmış ürün senkronizasyon oturumu Hub'a onaylanır (`_tryAcknowledgePendingSyncSession`, satır 56).  
> 2. Uygulama çökmesi sonrası `IN_PROGRESS` durumunda kilitli kalmış operasyonlar otomatik kurtarılır (`recoverStuckInProgressOperations`, satır 59).  
> 3. Cihaza ait `PENDING`, `RETRY` veya `FAILED_PERMANENT` durumundaki **en küçük `client_seq`** işlem bulunur (satır 68-75).  
> 4. Sıradaki işlem `FAILED_PERMANENT` ise kuyruk derhal durdurulur (satır 83).  
> 5. Sıradaki işlem `RETRY` ise ve `nextRetryAt` süresi henüz gelmediyse sıra atlanmaz, beklenir (satır 90).  
> 6. İşlem `IN_PROGRESS` yapılır ve `POST /api/v1/sales` ile Hub'a iletilir. Başarılı yanıt (200/201) alındığında `SYNCED` yapılır.

### Soru 4: Hub erişilemezse sistem nasıl davranıyor?
> **Cevap: İşlem `RETRY` durumuna alınır, üstel geri çekilme (exponential backoff) uygulanır ve kuyruk durdurulur.**  
> [`HttpSyncTransport`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/sync/sync_transport.dart#L80-L88), `SocketException`, `TimeoutException` veya `ClientException` aldığında durumu `SyncResponse.networkError(...)` olarak etiketler (`isTransientError = true`). [`ClientSyncService`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/sync/client_sync_service.dart#L120-L140) bu geçici hatayı aldığında:  
> - `attemptCount` sayısını 1 artırır,  
> - $T_{\text{backoff}} = \min(60\text{ sn}, 1\text{ sn} \times 2^{\text{attempt}-1})$ üstel gecikmesiyle `nextRetryAt` zamanını belirler,  
> - İşlemi `RETRY` olarak günceller ve döngüyü kırarak (`break`) **senkronizasyonu güvenle durdurur**.  
> - **Yerel satış kesintiye uğramaz:** Kasiyer offline modda sınırsız satış yapmaya devam eder; işlemler yerel Outbox tablosunda birikir.

### Soru 5: Aynı satışın tekrar gönderilmesi nasıl engelleniyor?
> **Cevap: Çift taraflı (İstemci + Sunucu) katı Idempotency mimarisi ile engellenir:**  
> - **İstemcide:** Her satış yerel transaction içinde benzersiz bir `operation_id` ve cihaz bazında monotonik artan `client_seq` ile kaydedilir ([`client_storage_repository.dart`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L128-L132)). Gönderim sırasında `IN_PROGRESS` yapılır; başarılı ACK gelince `SYNCED` yapılır.  
> - **Sunucuda:** [`test_spikes/spike_01_backend/bin/server.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart#L994-L1029) üzerinde `$deviceId:$clientSeq` bileşiği `idempotency_key` olarak `processed_operations` tablosunda denetlenir. Ağ tekrarında istek daha önce işlenmişse ve gelen SHA-256 payload özeti eşleşiyorsa, veritabanına mükerrer kayıt yazılmaz; önbellekteki yanıt `x-mms-idempotent-replay: true` başlığıyla `200 OK` olarak dönülür. İstemci bu yanıtı başarılı kabul edip işlemini `SYNCED` yapar.

### Soru 6: Bir işlem başarısız olduğunda sonraki Outbox kayıtları gönderilebiliyor mu?
> **Cevap: HAYIR, KESİNLİKLE GÖNDERİLEMEZ (Head-of-Line Blocking / Deterministik FIFO).**  
> `AGENTS.md` Anayasası (Bölüm 5) ve `ClientSyncService` (satır 83-95, 139-140):  
> - Eğer sıradaki işlem geçici hata aldıysa (`RETRY`), sonraki işlemler asla öne geçemez; `nextRetryAt` süresi dolana kadar kuyruk bekler.  
> - Eğer sıradaki işlem kalıcı hata aldıysa (`FAILED_PERMANENT` — örn. 400 Bad Request veya 409 Mismatch), kuyruk tamamen kilitlenir (`failed++`, `break`). Bu işlem bir yönetici veya otomatik mekanizma tarafından `updateAndRetryFailedOperation()` ile onarılana kadar arkadaki hiçbir satış Hub'a aktarılamaz. Bu kural stok ve hesap sırasının bozulmasını önlemek için mimarinin temel taşıdır.

### Soru 7: Uygulama kapanırken senkronizasyon güvenli biçimde durduruluyor mu?
> **Cevap: Hayır, henüz Flutter seviyesinde senkronizasyon yaşam döngüsü yönetimi kurulmamıştır.**  
> [`LocalDatabaseService`](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L42-L46) kendi veritabanı seviyesinde aktif sorguları kontrollü tahliye eden (`activeQueryCount`, `drainTimeout`) gelişmiş bir mekanizmaya sahiptir. Ancak Flutter tarafında bir senkronizasyon worker'ı henüz bulunmadığı için, uygulamanın kapatılması veya pencerenin kapatılması (`window_close` / `AppLifecycleState.detached`) anında devam eden bir HTTP isteğini zarifçe iptal etme veya timer'ı durdurma entegrasyonu mevcut değildir. (Yine de uygulama aniden kapansa dahi, açılışta çalışan `recoverStuckInProgressOperations` sayesinde veritabanı `IN_PROGRESS` kilitlenmesinden kurtulmaktadır).

### Soru 8: Mevcut altyapıyı kullanarak en az değişiklikle nasıl entegrasyon yapabiliriz?
> **Cevap: Sıfırdan kod yazmak yerine, mevcut `packages/mms_client_storage` sınıflarını Riverpod ile bağlayarak minimal ve temiz bir entegrasyon sağlanabilir:**  
> 1. `lib/features/sync/` altında bir `syncCoordinatorProvider` (StateNotifier) tanımlanır.  
> 2. Bu provider `LocalDatabaseService.repository`'yi alarak `ClientSyncService`'i oluşturur.  
> 3. Satış tamamlandığında (`CartNotifier.onSaleCommitted`) ve arka planda çalışan hafif bir periyodik timer (ör. 30 sn) ile `syncPendingOutbox()` tetiklenir.  
> 4. Eşzamanlı iki döngünün çakışmasını engellemek için tekil bir `_isSyncing` bayrağı konulur.  
> 5. Kasa başlığındaki `StatusBadge` widget'ına kuyruk derinliği (`pendingOutboxCount`) rozeti eklenir.

---

## 2. Mevcut Mimari ve Dosya Haritası

Sistem, Clean Architecture katman sınırlarına ve paket tabanlı modülerliğe tam uyumlu üç ana bileşenden oluşmaktadır:

```
┌────────────────────────────────────────────────────────────────────────┐
│                      FLUTTER CLIENT (market-pos)                       │
│                                                                        │
│  [Presentation]                                                        │
│   ├── CashierHeaderBar (StatusBadge, refresh button)                   │
│   └── PosScreen (Cart & Checkout UI)                                   │
│  [Application]                                                         │
│   ├── CartNotifier (completeSale -> calls repository)                  │
│   └── SystemStatusNotifier (checks /health & local DB counts)         │
│  [Data / Infrastructure]                                               │
│   ├── LocalPosRepository (adapters to local storage)                   │
│   ├── LocalDatabaseService (_TrackedClientStorageRepository)           │
│   └── MmsApiClient (HTTP client, redacts secrets)                      │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ consumes via package
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│              CORE STORAGE PACKAGE (packages/mms_client_storage)         │
│                                                                        │
│  [Database & Schema]                                                   │
│   ├── ClientDatabase (Drift SQLite: outbox_operations, client_sync_states)│
│   └── ClientStorageRepository (createOfflineSale, markOutboxSynced...) │
│  [Sync Engine]                                                         │
│   ├── ClientSyncService (FIFO worker, syncPendingOutbox, syncProducts) │
│   ├── SyncTransport / HttpSyncTransport (HTTPS client, Root CA pin)   │
│   └── SyncResponse (HTTP status mapping, isTransientError...)          │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ HTTPS (LAN / Loopback)
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│             CENTRAL MASTER HUB (test_spikes/spike_01_backend)          │
│                                                                        │
│  [Shelf API Server (bin/server.dart)]                                  │
│   ├── POST /api/v1/sales (Idempotency check, Single-Writer WriteQueue) │
│   ├── GET /api/v1/products (Product catalog snapshot + sync_session_id)│
│   ├── POST /api/v1/products/sync-ack (Two-phase product sync commit)   │
│   └── GET /health (Unauthenticated heartbeat & diagnostics)            │
│  [Security & Token Engine]                                             │
│   └── TokenManager, PairingManager, CertificateManager                 │
└────────────────────────────────────────────────────────────────────────┘
```

### Detaylı Dosya Referans Tablosu

| Bileşen | Dosya Yolu | Sorumluluk / İşlev |
|---|---|---|
| **Sync Motoru** | [`packages/mms_client_storage/lib/src/sync/client_sync_service.dart`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/sync/client_sync_service.dart) | Outbox kuyruğunu FIFO sırasıyla okur, Hub'a gönderir, hata sınıflandırması ve ürün senkronizasyonunu yönetir. |
| **Ağ Taşıyıcısı** | [`packages/mms_client_storage/lib/src/sync/sync_transport.dart`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/sync/sync_transport.dart) | `http.Client` tabanlı taşıyıcı. Root CA sertifika yükleme (`withCustomRootCa`) ve test modunu (`insecureForTesting`) destekler. |
| **Yanıt Modeli** | [`packages/mms_client_storage/lib/src/models/sync_response.dart`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/models/sync_response.dart) | HTTP durum kodlarını `isSuccess`, `isTransientError`, `isConflict`, `isBadRequest` olarak ayrıştırır. |
| **Outbox Tablosu** | [`packages/mms_client_storage/lib/src/database/client_database.dart`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/database/client_database.dart#L100-L135) | `outbox_operations` ve `client_sync_states` tabloları. `{deviceId, clientSeq}` tekillik garantisi ve indeksler. |
| **Depolama Repo** | [`packages/mms_client_storage/lib/src/database/client_storage_repository.dart`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L79-L340) | Satışı, stok hareketini ve outbox kaydını tek bir SQLite transaction'ında atomik olarak yazar (`createOfflineSale`). |
| **İstemci DB Servisi**| [`lib/core/storage/local_database_service.dart`](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L48-L274) | Windows'ta `%LOCALAPPDATA%\MarketMMS\client_local.db` yaşam döngüsünü, in-flight sorgu drain mekanizmasını ve repository takibini yönetir. |
| **Kasa Durumu** | [`lib/features/diagnostics/application/system_status_notifier.dart`](file:///c:/Users/halil/Github/market-pos/lib/features/diagnostics/application/system_status_notifier.dart) | Riverpod üzerinden sunucu sağlık kontrolü (`/health`) ve yerel veritabanı kayıt sayaçlarını (`getPendingOutboxCount`) izler. |
| **Kasa Başlığı** | [`lib/features/shell/presentation/widgets/cashier_header_bar.dart`](file:///c:/Users/halil/Github/market-pos/lib/features/shell/presentation/widgets/cashier_header_bar.dart) | Kasa ekranı üst çubuğunda bağlantı durumunu (`StatusBadge`) ve yenileme butonunu gösterir. |
| **Merkezi Sunucu** | [`test_spikes/spike_01_backend/bin/server.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart#L946-L1310) | Dart Shelf API. `/api/v1/sales` rotasında idempotency kontrolü (`processed_operations`) ve atomik Master Hub yazımını yönetir. |

---

## 3. Mevcut Senkronizasyon Akışı (Uçtan Uca İnceleme)

### 3.1. Satışın Doğuşu ve Atomik Yerel Yazım
1. Kasiyer sepete ürünleri ekler ve **F2 (Ödeme Al)** kısayolu ile `PaymentDialog` açılır.
2. Ödeme tamamlandığında [`CartNotifier.completeSale()`](file:///c:/Users/halil/Github/market-pos/lib/features/pos/application/cart_notifier.dart#L155) çağrılır.
3. [`LocalPosRepository.completeOfflineSale()`](file:///c:/Users/halil/Github/market-pos/lib/features/pos/data/local_pos_repository.dart#L278) üzerinden [`ClientStorageRepository.createOfflineSale()`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L79-L340) tetiklenir.
4. **Tek Atomik SQLite Transaction (`db.transaction`) İçinde:**
   - Cihaza ait monotonik sayaç artırılır: `nextSeq = currentClientSeq + 1`.
   - Sepet kalemlerinin o anki birim fiyatı ve fiyat sürümü (`priceVersionId`) snapshot alınır. Fiyat değişmişse `PriceChangedException` fırlatılır.
   - `local_sales` tablosuna `COMPLETED` durumunda satış eklenir.
   - `local_sale_items` tablosuna snapshot verileriyle kalemler eklenir.
   - `local_stock_movements` tablosuna negatif satış hareketi (`SATIS`) eklenir.
   - `local_products` tablosunda stok düşürülür (`ALLOW` politikası: eksi stok serbesttir).
   - Değiştirilemez JSON payload'ı ve SHA-256 özeti (`payloadHash`) hesaplanır.
   - `outbox_operations` tablosuna `status = 'PENDING'`, `attempt_count = 0` ve `client_seq = nextSeq` ile kayıt eklenir.
   - `client_sync_states.currentClientSeq` güncellenir.
5. Transaction başarıyla tamamlanır. Kasiyer fişi görür, sepet temizlenir.

### 3.2. Outbox Kuyruğunun Okunması ve Deterministik FIFO Sıralaması
`ClientSyncService.syncPendingOutbox()` çalıştığında:
- Cihaz için `status IN ('PENDING', 'RETRY', 'FAILED_PERMANENT')` olan kayıtlar arasından `client_seq ASC` sırasına göre **en küçük 1 kayıt** seçilir ([`client_sync_service.dart` L68-L75](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/sync/client_sync_service.dart#L68-L75)).
- **Katı Kural:** Eğer bu kayıt `FAILED_PERMANENT` ise kuyruk derhal durdurulur (`break`).
- Eğer bu kayıt `RETRY` ise ve `nextRetryAt` zamanı dolmadıysa sıra atlanamaz, kuyruk durdurulur (`break`).
- Sıradaki işlem `markOutboxInProgress` ile `IN_PROGRESS` yapılır.

### 3.3. Ağ İletimi ve Sunucu Tarafı İşleme
- [`HttpSyncTransport.postSale`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/sync/sync_transport.dart#L56-L89), `POST /api/v1/sales` uç noktasına `Authorization: Bearer <deviceToken>` başlığıyla payload'ı gönderir.
- Sunucu tarafında ([`server.dart` L946-L1030](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart#L946-L1030)):
  - `authenticated_device_id` doğrulanır.
  - `idempotency_key = '$deviceId:$clientSeq'` tablosu kontrol edilir.
  - Eğer istek daha önce işlenmişse ve gelen SHA-256 hash eşleşiyorsa `200 OK` (`x-mms-idempotent-replay: true`) döner.
  - Yeni istek ise tekil yazıcı kuyruğunda (`writeQueue`) merkezi transaction işletilir, satış kaydedilir, stok düşürülür, `processed_operations` tablosuna yazılır ve `201 Created` dönülür.

### 3.4. İstemci ACK ve Hata Yönetimi
- **200 / 201 (Başarı):** `markOutboxSynced` ile işlem `SYNCED` yapılır, `lastSyncedSeq` güncellenir ([`client_storage_repository.dart` L430-L460](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L430-L460)). Kuyruk bir sonraki `client_seq` için devam eder.
- **Geçici Hata (Ağ kopması, 503, 500, 408, 429):** `markOutboxRetry` ile işlem `RETRY` yapılır, `attemptCount` artırılır, üstel gecikme süresi (`nextRetryAt`) atanır ve döngü durur ([`client_sync_service.dart` L120-L140](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/sync/client_sync_service.dart#L120-L140)).
- **Kalıcı Hata (400 Bad Request, 409 Mismatch):** `markOutboxPermanentFail` ile işlem `FAILED_PERMANENT` yapılır, hata metni kaydedilir ve kuyruk kilitlenir ([`client_sync_service.dart` L142-L149](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/sync/client_sync_service.dart#L142-L149)).

---

## 4. Tamamlanmış ve Eksik Özellikler (Gap Analizi)

| Özellik / Gereksinim | Çekirdek Depolama Paketi (`mms_client_storage`) | Flutter İstemcisi (`market-pos/lib`) | Durum & Değerlendirme |
|---|---|---|---|
| **Atomik Satış & Outbox Kaydı** | TAMAMLANDI (`createOfflineSale`, 8 adım atomik) | TAMAMLANDI (`CartNotifier` -> `LocalPosRepository`) | **%100 Hazır.** Satış anında outbox tablosuna yazılmaktadır. |
| **Deterministik FIFO Sıralaması** | TAMAMLANDI (`client_seq ASC`, Head-of-Line koruması) | TAMAMLANDI (Altyapı paketine delege edilmiş) | **%100 Hazır.** |
| **Idempotency Koruması** | TAMAMLANDI (`operation_id`, SHA-256 payloadHash) | TAMAMLANDI (Altyapı paketine delege edilmiş) | **%100 Hazır.** Sunucu `processed_operations` ile çift korumalı. |
| **Geçici Hata & Backoff** | TAMAMLANDI (Üstel gecikme, max 60 sn, RETRY) | TAMAMLANDI (Altyapı paketinde mevcut) | **%100 Hazır.** |
| **Crash Recovery** | TAMAMLANDI (`recoverStuckInProgressOperations`) | **EKSİK** (Uygulama açılışında çağrılmıyor) | **Entegrasyon Gerekiyor.** `main.dart` veya sync provider başlatmasında çağrılmalıdır. |
| **Legacy Outbox Recovery** | TAMAMLANDI (`updateAndRetryFailedOperation`) | **EKSİK** (UI'da kalıcı hata onarım ekranı yok) | **Post-1.3.1 / Admin Adayı.** |
| **Sync Servis Provider'ı** | TAMAMLANDI (`ClientSyncService`) | **EKSİK** (Riverpod provider tanımlanmamış) | **Faz 1.3.1 Temel İşi.** |
| **Arka Plan Timer / Worker** | Destekleniyor (Harici çağrı bekliyor) | **EKSİK** (Periyodik timer veya döngü yok) | **Faz 1.3.1 Temel İşi.** |
| **Olay Güdümlü Tetikleme** | Destekleniyor | **EKSİK** (`onSaleCommitted` sync tetiklemiyor) | **Faz 1.3.1 Temel İşi.** |
| **Kasa Kuyruk Derinliği Rozeti**| Destekleniyor (`getPendingOutboxCount`) | **EKSİK** (`StatusBadge` yalnızca bağlantı durumunu gösteriyor) | **Faz 1.3.1 Temel İşi.** |
| **Cihaz Token Saklama (B-3)** | Destekleniyor (Constructor parametresi) | **EKSİK** (Hardcoded null / DPAPI henüz yok) | **Açık Koşul.** Pilot için Windows loopback token yapılandırması gerekli. |
| **Root CA / TLS Pinning (B-2)**| TAMAMLANDI (`withCustomRootCa`) | **EKSİK** (Mobil için geçerli; Windows'ta HTTP loopback) | **Faz 7 Pilot Koşulu.** |

---

## 5. Riskler ve Olası Veri Bütünlüğü Sorunları

### 5.1. Head-of-Line Blocking ve Kuyruk Kilitlenmesi Riski
- **Risk:** Bir outbox kaydı kalıcı hata (`FAILED_PERMANENT` — örn. geçersiz fiyat sürümü veya şema uyuşmazlığı) aldığında, katı FIFO kuralı gereği arkasındaki tüm satışların iletimi durur.
- **Olası Sonuç:** Kasiyer fiziksel satış yapmaya devam eder, yerel Outbox kuyruğu birikir (100, 200, 500 satış), ancak hiçbiri Hub'a aktarılamaz.
- **Çözüm / Önlem:**
  1. Kasa başlık çubuğunda `FAILED_PERMANENT` durumu oluştuğunda kasiyere veya yöneticiye belirgin bir uyarı rozeti (Kırmızı/Ünlem: "Senkronizasyon Kilitlendi") gösterilmelidir.
  2. Kilitlenmeye yol açan satışların incelenip düzeltilebilmesi için Faz 1.3.1 sonrasında teşhis ekranı (`DiagnosticsView`) üzerinden `updateAndRetryFailedOperation()` tetiklenebilir olmalıdır.

### 5.2. `LocalDatabaseService.getPendingOutboxCount()` Eksikliği
- **Mevcut Durum:** [`lib/core/storage/local_database_service.dart`](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L303-L312) satır 308'de:
  ```dart
  ..where(_db.outboxOperations.status.equals('PENDING'));
  ```
- **Kritik Hata:** Bir işlem geçici ağ kesintisi nedeniyle `RETRY` durumuna veya kalıcı hata nedeniyle `FAILED_PERMANENT` durumuna geçtiğinde, bu metot ilgili kayıtları saymaz ve bekleyen işlem sayısını `0` döner!
- **Sonuç:** Kasa başlığında bekleyen işlem yokmuş gibi görünür; sistem kasiyere yanlış bilgi verir.
- **Çözüm:** Metot `status.isNotValue('SYNCED')` veya `status.isIn(['PENDING', 'RETRY', 'IN_PROGRESS', 'FAILED_PERMANENT'])` olarak güncellenmelidir.

### 5.3. Eşzamanlı Senkronizasyon (Race Condition) Riski
- **Risk:** Satış anında tetiklenen senkronizasyon ile periyodik arka plan timer'ının aynı anda `syncPendingOutbox()` çağırması durumunda, iki eşzamanlı worker aynı `client_seq` kaydını `IN_PROGRESS` yapmaya çalışabilir.
- **Önlem:** Senkronizasyon servisini sarmalayan Riverpod notifier'ı (`SyncCoordinatorNotifier`), bir senkronizasyon yürütülürken ikinci bir çağrıyı güvenle engelleyen tekil bir kilit (`bool _isSyncing`) ve ardışık talep bayrağı (`bool _hasPendingRequest`) ile korunmalıdır.

### 5.4. Uygulama Kapanışı ve `IN_PROGRESS` Durumunda Kalma
- **Risk:** İstemci tam Hub'a POST atarken veya yanıt beklerken kasiyer uygulamayı kapatırsa, ilgili outbox kaydı veritabanında `IN_PROGRESS` olarak kalabilir.
- **Mevcut Güvence:** `ClientSyncService.syncPendingOutbox()` metodunun başında yer alan `recoverStuckInProgressOperations(deviceId)` çağrısı, uygulama bir sonraki açılışında bu kayıtları otomatik olarak `RETRY` veya `PENDING`'e çevirerek kurtarmaktadır.
- **Ek Önlem:** Windows masaüstünde pencere kapatma sinyali yakalanmalı ve devam eden bir senkronizasyon varsa `drainTimeout` süresince tamamlanması beklenmelidir.

### 5.5. Cihaz Token ve Kimlik Doğrulama Eksikliği (B-3 Koşulu)
- **Mevcut Durum:** `MmsApiClient` içinde `deviceToken` null'dır; backend'deki `/health` rotası şifresiz çalışırken `/api/v1/sales` rotası Bearer token zorunlu kılmaktadır.
- **Pilot Çözümü:** Windows Desktop Master Hub aynı bilgisayarda (`127.0.0.1:8080`) loopback çalıştığı için, Faz 1.3.1 entegrasyonunda Windows istemcisi için bir pilot cihaz token'ı (`AppConstants.defaultDeviceToken` veya yerel güvenli konfigürasyon) atanmalıdır.

---

## 6. Mevcut Testler ve Kapsamadıkları Senaryolar

### 6.1. Mevcut ve Yeşil Olan Testler
1. **`packages/mms_client_storage` (63 Test):**
   - [`s5a3_outbox_sync_test.dart`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/test/s5a3_outbox_sync_test.dart):
     - Servis yeniden erişilebilir olduğunda Outbox kayıtlarının iletimi ve `SYNCED` olması.
     - ACK kaybı sonrası aynı payload ile tekrar gönderimde Idempotent Replay'in başarılı sayılması.
     - Birden fazla Outbox kaydının `client_seq ASC` sırası korunarak gönderilmesi ve hata anında sıranın durdurulması.
     - Kalıcı hata (`FAILED_PERMANENT`), kuyruk kilitlenmesi ve `updateAndRetryFailedOperation` ile onarım.
     - HTTP 408 ve 429 yanıtlarının `RETRY`, HTTP 400 yanıtının `FAILED_PERMANENT` yapılması.
     - Sunucudan ürün çekme (`syncProducts`) ve iki aşamalı ACK onayı.
   - [`s5a3_live_hub_integration_test.dart`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/test/s5a3_live_hub_integration_test.dart):
     - Canlı backend process'i ile E2E SQLite WAL tekil yazıcı entegrasyonu.
2. **`test_spikes/spike_01_backend` (144 Test):**
   - E2E Idempotency, Token doğrulaması, Aubrey/WriteQueue tekil yazıcı eşzamanlılığı.
3. **`market-pos` Kök Testleri (67 Test):**
   - `LocalDatabaseService` drain ve yaşam döngüsü testleri, `PosScreen`, `CartNotifier` ve `Money` testleri.

### 6.2. Kapsanmayan / Eksik Kalan Senaryolar (Faz 1.3.1 Test İhtiyacı)
- [ ] `SyncCoordinatorNotifier` Riverpod birim testleri (Başlatma, timer tetikleme, manuel tetikleme).
- [ ] Eşzamanlı tetikleme engelleme testi (Aynı anda gelen satış ve timer çağrısının tekilleştirilmesi).
- [ ] Kasa üst çubuğu widget testi: Outbox rozetinin kuyruktaki sayıya göre dinamik güncellenmesi (`0` iken gizli/gri, `> 0` iken mavi/sarı, hata anında kırmızı).
- [ ] Satış yapıldığında senkronizasyonun otomatik tetiklendiğini doğrulayan entegrasyon testi.
- [ ] Uygulama açılışında `recoverStuckInProgressOperations` çağrısının çalıştığını doğrulayan yaşam döngüsü testi.

---

## 7. Önerilen Entegrasyon Mimarisi (Faz 1.3.1)

Clean Architecture ve SOLID ilkelerine tam uyumlu, mevcut kod tabanına en az müdahale eden önerilen mimari:

```
lib/features/sync/
├── domain/
│   └── sync_status.dart                # Senkronizasyon durum modeli (saf Dart: idle, syncing, error, pendingCount...)
├── application/
│   ├── sync_coordinator_notifier.dart  # Riverpod StateNotifier (Timer yönetimi, kilit mekanizması, tetikleme)
│   └── sync_providers.dart             # Riverpod bağımlılık kompozisyonu (transport, service, coordinator)
└── presentation/
    └── widgets/
        └── sync_queue_badge.dart       # Kasa başlığı için kuyruk rozeti (Ör: "3 Bekliyor", "Senkronize Ediliyor...")
```

### 7.1. Bağımlılık Kompozisyonu (`sync_providers.dart`)
```dart
/// SyncTransport sağlayıcısı (HTTP istemcisi)
final syncTransportProvider = Provider<SyncTransport>((ref) {
  final transport = HttpSyncTransport();
  ref.onDispose(() => transport.close());
  return transport;
});

/// ClientSyncService sağlayıcısı
final clientSyncServiceProvider = Provider<ClientSyncService>((ref) {
  final localDb = ref.watch(localDatabaseServiceProvider);
  final transport = ref.watch(syncTransportProvider);
  final apiClient = ref.watch(apiClientProvider);

  return ClientSyncService(
    repository: localDb.repository,
    transport: transport,
    deviceId: apiClient.deviceId,
    deviceToken: apiClient.deviceToken ?? 'pilot_win_token',
    hubUrl: apiClient.baseUrl,
  );
});

/// UI ve Yaşam Döngüsü Koordinatörü
final syncCoordinatorProvider =
    StateNotifierProvider<SyncCoordinatorNotifier, SyncStatus>((ref) {
  final syncService = ref.watch(clientSyncServiceProvider);
  final localDb = ref.watch(localDatabaseServiceProvider);

  return SyncCoordinatorNotifier(
    syncService: syncService,
    localDb: localDb,
  );
});
```

### 7.2. Tetikleme Politikaları (Trigger Policies)
1. **Olay Güdümlü (Event-Driven):** Satış kaydedildiğinde (`CartNotifier.onSaleCommitted`) doğrudan `ref.read(syncCoordinatorProvider.notifier).triggerSync()` çağrılır. İnternet/ağ varsa satış 1 saniye içinde Hub'a ulaşır.
2. **Periyodik (Periodic Timer):** Arka planda 30 saniyelik bir timer çalışır. Ağ koptuktan sonra tekrar geldiğinde birikmiş outbox kayıtları otomatik olarak Hub'a aktarılır.
3. **Manuel (User-Initiated):** Kasiyer üst çubuktaki yenile butonuna bastığında hem sistem durumu yenilenir hem de bekleyen kuyruk tetiklenir.
4. **Açılışta Kurtarma (Startup Recovery):** `SyncCoordinatorNotifier` başlatıldığında arka planda `recoverStuckInProgressOperations` çalıştırılır ve ardından `triggerSync()` işletilir.

---

## 8. Küçük ve Test Edilebilir Uygulama Adımları

Faz 1.3.1 geliştirmesi riskleri minimize etmek amacıyla aşağıdaki 6 küçük adımda yürütülmelidir:

- [ ] **Adım 1: `LocalDatabaseService` Outbox Sayaçlarının Düzeltilmesi**
  - `getPendingOutboxCount()` metodunun `RETRY` ve `FAILED_PERMANENT` kayıtlarını da kapsayacak veya detaylandıracak şekilde güncellenmesi.
  - `test/core/storage/local_database_service_test.dart` süitine birim testlerinin eklenmesi.
- [ ] **Adım 2: Domain Modeli ve Provider Kompozisyonu**
  - `lib/features/sync/domain/sync_status.dart` modelinin yazılması (saf Dart).
  - `lib/features/sync/application/sync_providers.dart` dosyasının oluşturulması.
- [ ] **Adım 3: `SyncCoordinatorNotifier` (TDD ile)**
  - Önce test süitinin yazılması (`test/features/sync/application/sync_coordinator_notifier_test.dart`).
  - Timer yönetimi, tekil senkronizasyon kilidi (`_isSyncing`), hata yönetimi ve crash recovery çağrısının kodlanması.
- [ ] **Adım 4: Kasa Satış Akışına Entegrasyon**
  - `lib/features/pos/pos_providers.dart` içindeki `onSaleCommitted` callback'ine `syncCoordinator.triggerSync()` çağrısının eklenmesi.
  - Bir satış tamamlandığında senkronizasyonun tetiklendiğinin test ile doğrulanması.
- [ ] **Adım 5: Kasa Üst Çubuğu UI Entegrasyonu (`CashierHeaderBar`)**
  - Kasa başlığına kuyruk derinliğini (`SyncQueueBadge`) gösteren rozetin eklenmesi.
  - Durumlar: Senkronize (Gizli/Yeşil Tik), Kuyrukta Bekleyen Var (Mavi/Sarı rozet: "N Satış Bekliyor"), Hata/Kilitlenme (Kırmızı rozet).
  - `test/features/shell/main_shell_screen_test.dart` widget testlerinin güncellenmesi.
- [ ] **Adım 6: Tam Doğrulama ve Windows Debug Derlemesi**
  - `flutter test` (tüm kök, storage ve backend testlerinin çalıştırılması).
  - `flutter analyze` (0 hata/uyarı).
  - `flutter build windows --debug` (masaüstü derleme başarısı).

---

## 9. Faz 1.3.1 Kapsam ve Kapsam Dışı Maddeler

| Alan | Faz 1.3.1 KAPSAMI İÇİNDE (In-Scope) | KAPSAM DIŞINDA (Out-of-Scope) |
|---|---|---|
| **Senkronizasyon Yönü** | **Yalnızca İstemciden Hub'a Satış İletimi (Outbox Push)** | Hub'dan ürün çekme (Ürün CRUD Faz 1.4 kapsamındadır). |
| **İşlem Türü** | **`SALE_CREATE`** (Yeni yapılan offline satışların aktarımı) | Satış iptali (`SALE_CANCEL` — Faz 1.3.3) ve iade (`SALE_REFUND` — Faz 1.3.4). |
| **Ağ Protokolü** | HTTP / HTTPS (Yerel Windows Loopback `127.0.0.1:8080`) | Mobil Wi-Fi mDNS keşfi ve dinamik IP eşleştirme (Faz 7 Pilot). |
| **Hata Onarım UI** | Başarısızlık rozeti ve audit log kaydı | UI üzerinden satışı manuel düzenleyip tekrar deneme ekranı (Post-1.3 / Admin). |
| **Güvenlik / Token** | Windows pilot için konfigüre edilmiş cihaz token'ı | DPAPI donanımsal anahtarlık (`pepper.dpapi`) entegrasyonu (Açık Koşul B-3). |
| **UI Bileşenleri** | Kasa başlık çubuğunda canlı kuyruk derinliği rozeti | Satış geçmişi ve fiş detayları ekranı (Faz 1.3.2 kapsamındadır). |

---

## 10. Açık Kararlar ve Proje Sahibinin Onayını Gerektiren Konular

Faz 1.3.1 uygulama kodlamasına başlamadan önce aşağıdaki tasarım kararlarının netleştirilmesi önerilmektedir:

1. **`OD-SYNC-01` (Arka Plan Senkronizasyon Periyodu):**
   - *Seçenek A (Önerilen):* 30 saniye. (Kasa kaynaklarını yormaz, ağ geri geldiğinde makul sürede kuyruğu eritir).
   - *Seçenek B:* 15 saniye. (Daha agresif, neredeyse anlık).
   - *Seçenek C:* 60 saniye.
2. **`OD-SYNC-02` (Kasa Başlığı Rozet Tasarımı):**
   - *Seçenek A (Önerilen):* Mevcut `StatusBadge` (Çevrimiçi/Çevrimdışı) yanına ikinci bir rozet olarak `OutboxBadge` eklenmesi (Örn: `[☁️ 3 Bekliyor]`). Kuyruk boşken rozet gizlenir veya nötr gri görünür.
   - *Seçenek B:* `StatusBadge` ile birleştirilmesi (Örn: `[🟢 ÇEVRİMİÇİ • 3 EŞİTLENİYOR]`).
3. **`OD-SYNC-03` (Windows Pilot Cihaz Token Yapılandırması):**
   - *Seçenek A (Önerilen):* Pilot aşamasında `AppConstants` veya yerel SQLite `client_sync_states` tablosuna başlangıçta sabit/konfigüre bir pilot cihaz token'ı tanımlanması.
   - *Seçenek B:* Uygulama açılışında Hub'a pairing simülasyonu yapılması.

---

## 11. Sonuç ve Özet Değerlendirme

Mevcut kod tabanı incelendiğinde; `packages/mms_client_storage` paketinin Outbox senkronizasyon motorunun (`ClientSyncService`, `SyncTransport`, `OutboxOperations`) mimari açıdan **mükemmel seviyede olgun, sağlam ve test edilmiş** olduğu tespit edilmiştir. İstemci tarafında sıfırdan bir senkronizasyon mantığı yazılmasına kesinlikle gerek yoktur.

Faz 1.3.1'de yapılması gereken iş; bu hazır motoru Flutter istemcisinin Riverpod durum yönetimine bağlamak, satış yapıldığında ve periyodik olarak tetiklemek ve kasiyere kasa üst çubuğunda kuyruk durumunu şeffaf bir rozetle sunmaktan ibarettir.

Bu rapor tamamen salt okunur inceleme prensibiyle hazırlanmış olup, hiçbir kaynak kod dosyası değiştirilmemiş ve Git staging/commit işlemi yapılmamıştır. Proje sahibinin onayı ve yönlendirmesi beklenmektedir.

