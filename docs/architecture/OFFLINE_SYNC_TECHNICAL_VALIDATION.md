# Market Management System (MMS) — Offline Senkronizasyon Protokolü Bağımsız Teknik Denetim ve Doğrulama Raporu (Technical Validation & Hardening)

**Doküman Kodu:** `OFFLINE_SYNC_TECHNICAL_VALIDATION.md`  
**Sürüm:** 1.0  
**Tarih:** 31 Ekim 2026  
**Durum:** Faz 0 — Senkronizasyon ve Outbox Protokolü Bağımsız Teknik Denetimi  
**Denetlenen Belgeler:**  
1. `docs/architecture/OFFLINE_SYNC_PROTOCOL.md` (v1.0)  
2. `docs/architecture/OFFLINE_SYNC_DECISIONS.md` (v1.0)  
3. `docs/architecture/DATA_MODEL.md` (v1.1)  
4. `docs/architecture/DATA_MODEL_DECISIONS.md` (v1.1)  
5. `docs/requirements/BUSINESS_RULES_SPEC.md` (v1.2)  
6. `docs/requirements/PHASE_0_BUSINESS_DISCOVERY.md` (v1.3)  
7. `docs/ai/rules/offline-first.md`  
8. `docs/PROJECT_STATUS.md`  
**Teknik Proje / Klasör Adı:** `market-pos`  
**Ürün Tanımı:** Market Management System (MMS) — Profesyonel Market Yönetim SaaS Uygulaması  

---

## 1. Genel Değerlendirme

Bu bağımsız teknik denetim çalışması; **Market Management System (MMS)** projesinde Faz 0 kapsamında hazırlanan `OFFLINE_SYNC_PROTOCOL.md` (v1.0) ve `OFFLINE_SYNC_DECISIONS.md` (v1.0) belgelerini derinlemesine incelemek, dağıtık sistem hatalarını, uç senaryoları (edge cases) ve potansiyel veri tutarsızlıklarını açığa çıkarmak ve protokolü sertleştirmek amacıyla gerçekleştirilmiştir.

### Temel Denetim Sonuçları:
- **Genel Değerlendirme:** Senkronizasyon protokolü mimari açıdan yüksek olgunluktadır; çift yönlü idempotency, Outbox state machine ve veri kaybı önleme prensipleri sağlam bir temele oturmaktadır.
- **Düzeltilmesi Gereken Kritik / Önemli Bulgular:**
  1. **`FND-SYNC-01` [HIGH] Restore Sırasında Sıra Numaralarının Yeniden Numaralandırılması Riski:** `max(S_backup, S_pending) + 1` formülü bekleyen işlemlerin kendi sıra numaralarını değiştirmek için kullanılamaz; işlem kimlikleri (`id`, `idempotency_key`, `client_sequence_number`) mutlak değişmez (immutable) kalmalı, formül yalnızca gelecekteki yeni işlemleri üretecek yerel sayaç üretecini (generator) güncellemelidir.
  2. **`FND-SYNC-02` [HIGH] İki Şeritli Kuyrukta Çapraz Şerit Varlık Bağımlılığı (Cross-Lane Entity Dependency):** Ürün oluşturma veya fiyat değişikliği ilişkisel bir işlem iken, görsel yükleme ikili (binary/blob) bir işlemdir. İlişkisel tüm işlemler (ürün, fiyat, satış) tek bir sıralı Meta-veri şeridinde kalmalı; yalnızca ikili görseller bağımsız Medya şeridine ayrılmalıdır.
  3. **`FND-SYNC-03` [MEDIUM] `SYNCING` Durumunda Atomik Worker Kilitleme (`worker_id`) Eksikliği:** Birden fazla eşzamanlı senkronizasyon tetikleyicisinin (timer, ağ olayı, UI) aynı işlemi kapmasını önlemek için worker seviyesinde atomik kiralama (`locked_by_worker_id`) ve stale worker yanıt iptali tanımlanmalıdır.
  4. **`FND-SYNC-04` [MEDIUM] Çevrimdışı Cihaz İptali Gerçekliği ve Tehdit Modeli Sınırları:** Çevrimdışı bir cihazın iptal kararını anında öğrenmesi fiziksel olarak imkansızdır. Çevrimdışı oturum süresi sınırı (TTL), yerel veri kilitlenmesi ve çevrimdışı satışların akıbeti net bir tehdit modeliyle sınırlandırılmalıdır.
  5. **`FND-SYNC-05` [MEDIUM] Sunucu Inbox Defteri ile İşlem Transaction'ının Atomik Bütünlüğü:** Sunucu tarafında `sales` kaydının oluşması ile `processed_operations` kaydının yazılması aynı PostgreSQL transaction'ı içinde atomik olmak zorundadır.
  6. **`FND-SYNC-06` [LOW] Hata Durumlarında `FAILED` ile `RETRY_EXHAUSTED` (DLQ) Ayrımı:** Kalıcı doğrulama hataları ile 10 kez denenip geçici olarak tıkanan işlemler durum bazında ayrıştırılmalıdır.

---

## 2. Bulguların Ayrıntılı Analizi ve Sertleştirme Kararları

---

### `FND-SYNC-01` [HIGH] Restore Sırasında Bekleyen İşlemlerin Sıra Numaralarının Değiştirilmesi Tehlikesi
- **İlgili Bölüm:** `OFFLINE_SYNC_PROTOCOL.md` Bölüm 8.1; `OFFLINE_SYNC_DECISIONS.md` Karar 8.
- **Sorunun Açıklaması:**  
  v1.0 dokümanında eski yedek yüklendiğinde sıra numarası çakışmasını önlemek için:  
  `S_new = max(S_backup, S_local_pending) + 1` formülü verilmiş ve bekleyen işlemlerin bu formülle "yeniden indekslenebileceği" ima edilmiştir.  
- **Gerçekleşebilecek Hata Senaryosu:**  
  Eğer bekleyen bir işlem (`seq = 101`, `idempotency_key = 'sale-abc'`) cihaz çökmeden önce sunucuya gönderilmiş ancak yanıt alınamamışsa; sunucu `processed_operations` tablosunda `(device_id, seq = 101, idempotency_key = 'sale-abc')` kaydı zaten oluşmuştur.  
  Cihaz eski bir yedeği yükleyip bu işlemi `seq = 201` olarak yeniden numaralandırırsa:
  1. Sunucu aynı `idempotency_key` ile farklı bir sequence number görecek ve sıra ihlali/tampering şüphesiyle işlemi reddedecektir.
  2. Başka bir işlem ileride `seq = 101` numarasını alırsa sunucu "Bu sequence daha önce işlendi" diyerek yeni satışı çöpe atacaktır!
  3. Restore işlemi arka arkaya iki kez çalıştırılırsa sıralar tamamen bozulacaktır.
- **Sertleştirilmiş Çözüm Kuralı (Mutlak Değişmezlik Prensibi):**
  - **Kural 1 (İşlem Değişmezliği):** Bekleyen bir işlemin `id`, `idempotency_key`, `client_sequence_number` ve `payload` değerleri **RESTORE DAHİL HİÇBİR KOŞULDA DEĞİŞTİRİLEMEZ**.
  - **Kural 2 (Yalnızca Sayaç İlerletilir):** Geri yükleme tamamlandığında yeni yüklenen veritabanındaki sayaç tablosu (`device_sync_sequence`), bekleyen işlemlerin sıra numaralarını değiştirmek için değil; **bundan sonra üretilecek YENİ işlemlerin** çakışmasını engellemek için ileriye sarılır:
    $$S_{\text{next\_generator}} = \max(S_{\text{backup\_max}}, \; \max(S_{\text{pending\_ops\_seq}})) + 1$$
  - **Kural 3 (Sunucu Tarafı Deduplication):** Bekleyen işlemler sunucuya gönderilmeden önce `POST /sync/verify-keys` ile sunucu Inbox'ına sorulur; sunucuda zaten var olanlar yerelde doğrudan `COMPLETED` yapılır.

---

### `FND-SYNC-02` [HIGH] İki Şeritli Kuyrukta Çapraz Şerit Bağımlılıkları ve Nedensel Sıra Bozulması
- **İlgili Bölüm:** `OFFLINE_SYNC_PROTOCOL.md` Bölüm 10.2; `OFFLINE_SYNC_DECISIONS.md` Karar 1.
- **Sorunun Açıklaması:**  
  v1.0 dokümanında Lane 1 (Kritik POS: Satış, İade, Stok) ve Lane 2 (Katalog ve Medya: Ürün, Fiyat, Görsel) olarak ikiye ayrılmıştır.  
  Eğer bir kasiyer çevrimdışıyken sisteme yeni bir barkodsuz ürün ekler (`seq = 50`) ve 10 saniye sonra bu ürünü kasadan satarsa (`seq = 51`):
  - Ürün kaydı Lane 2'ye (düşük öncelik), Satış kaydı Lane 1'e (yüksek öncelik) girerse;
  - Lane 1 önce sunucuya ulaşır; sunucuda `sale_items.product_id` foreign key kısıtı patlar (ürün henüz sunucuda yoktur!).
- **Sertleştirilmiş Çözüm Kuralı (Meta-Veri ve Medya Ayrımı):**
  - Şerit ayrımı "İlişkisel Veri" ile "İlişkisel Olmayan İkili Dosya (Blob)" arasında yapılmalıdır:
    1. **Lane 1 — Meta-Veri Şeridi (Tüm İlişkisel Tablolar):** `products`, `product_barcodes`, `price_history`, `sales`, `sale_items`, `refunds`, `stock_movements`. Tüm ilişkisel kayıtlar **tek bir ortak `client_sequence_number`** taşır ve kesin nedensel FIFO sırasıyla gönderilir. Ürün oluşturma küçük bir JSON olduğundan satışı geciktirmez.
    2. **Lane 2 — Medya Şeridi (Yalnızca Blob Dosyalar):** `product_images` (JPEG/WebP dosyaları). Yalnızca dosya ikilileri arka planda bağımsız asenkron yüklenir. Bir ürünün fotoğrafının yüklenememesi satışı asla engellemez.

---

### `FND-SYNC-03` [MEDIUM] `SYNCING` Durumunda Atomik Kiralama (`worker_id`) ve Stale Worker Koruması
- **İlgili Bölüm:** `OFFLINE_SYNC_PROTOCOL.md` Bölüm 2.2.
- **Sorunun Açıklaması:**  
  Yerel senkronizasyon servisi; ağ dinleyicisi, zamanlayıcı (timer) ve UI butonları tarafından tetiklenebilir. İki iş parçacığı (worker) aynı anda çalışırsa aynı `PENDING` işlemi sunucuya mükerrer gönderebilir. Ayrıca kaza kurtarma sonrası eski worker uyanırsa yerel durumu ezebilir.
- **Sertleştirilmiş Çözüm Kuralı:**
  - `sync_operations` tablosuna `locked_by_worker_id: UUID NULL` ve `lease_expires_at: TIMESTAMPTZ NULL` eklenir.
  - Kiralama atomik tek bir sorguyla yapılır:
    ```sql
    UPDATE sync_operations 
    SET status = 'SYNCING', 
        locked_by_worker_id = :worker_id, 
        lease_expires_at = now() + interval '60 seconds'
    WHERE id = (
      SELECT id FROM sync_operations 
      WHERE status = 'PENDING' OR (status = 'SYNCING' AND lease_expires_at < now())
      ORDER BY client_sequence_number ASC LIMIT 1
    );
    ```
  - Yanıt geldiğinde: `WHERE id = :id AND locked_by_worker_id = :worker_id`. Eğer lease başka bir worker tarafından devralınmışsa etkilenen satır 0 olur; eski worker'ın yanıtı güvenle çöpe atılır.

---

### `FND-SYNC-04` [MEDIUM] Çevrimdışı Cihaz İptali Tehdit Modeli ve Fiziksel Sınırlar
- **İlgili Bölüm:** `OFFLINE_SYNC_PROTOCOL.md` Bölüm 7 (Senaryo 9), Bölüm 9; `OFFLINE_SYNC_DECISIONS.md` Karar 9.
- **Sorunun Açıklaması:**  
  "İptal edilen cihaz anında kilitlenir" ifadesi fiziksel dağıtık sistem gerçekleriyle çelişir. İnterneti kesilmiş bir telefon, sunucuda yetkisinin alındığını bilemez.
- **Sertleştirilmiş Tehdit Modeli ve Davranış Sınırları:**
  1. **Garanti Edilemeyen Durum:** Cihaz çevrimdışıyken donanım kilidi veya uzaktan imha anlık olarak garanti **edilemez**.
  2. **Zaman Aşımı Güvencesi (TTL):** Her cihazın yerel oturumunda `device_sessions.expires_at` (en fazla 7 gün, `BR-SEC-06`) damgalıdır. İnternete bağlanıp token yenileyemeyen cihaz 7 günün sonunda yerel olarak kendini kilitler.
  3. **Ağ Temasında Kesin Yaptırım:** Cihaz internete bağlandığı ilk milisaniyede gönderdiği istek `HTTP 403 Forbidden (CODE: DEVICE_REVOKED)` alır. Yerel oturum silinir ve cihaz bloke edilir.
  4. **Yetki İptali Öncesi Çevrimdışı Satışların Korunması:** Çalınan cihazda iptalden önce yapılmış meşru satışlar varsa, cihaz sahibi web konsolundan "Bekleyen satışları kabul et ve cihazı kapat" seçeneğini seçebilir.

---

### `FND-SYNC-05` [MEDIUM] Sunucu Inbox Defteri ile İşlem Transaction'ının Atomik Bütünlüğü
- **İlgili Bölüm:** `OFFLINE_SYNC_PROTOCOL.md` Bölüm 4.
- **Sorunun Açıklaması:**  
  Sunucu satışı `sales` tablosuna yazıp tam `processed_operations` tablosuna yazarken veritabanı kilitlenirse veya sunucu yeniden başlarsa, satış kaydedilmiş ama idempotency kaydı oluşmamış olur. İstemci tekrar denediğinde satış çift kaydedilir!
- **Sertleştirilmiş Çözüm Kuralı:**  
  Sunucu tarafındaki Supabase Edge Function / PostgreSQL saklı yordamında:  
  `sales`, `sale_items`, `stock_movements` yazımı ile `processed_operations` yazımı **TEK BİR POSTGRESQL TRANSACTION'I İÇİNDE** yürütülür. Biri başarısız olursa tüm işlem geri alınır (rollback).

---

### `FND-SYNC-06` [LOW] Hata Durumlarında `FAILED` ile `RETRY_EXHAUSTED` (DLQ) Ayrımı
- **İlgili Bölüm:** `OFFLINE_SYNC_PROTOCOL.md` Bölüm 2.1, Bölüm 5.
- **Sorunun Açıklaması:**  
  v1.0'da hem 400 Bad Request gibi kalıcı hatalar hem de 10 kez denenip geçici olarak başarısız olan kayıtlar `FAILED` altında toplanmıştır. Bu durum teşhisi zorlaştırır.
- **Sertleştirilmiş Çözüm Kuralı:**
  - `FAILED`: Kalıcı doğrulama veya şema hatası alan, otomatik tekrar denenmeyecek kayıtlar.
  - `RETRY_EXHAUSTED`: Geçici hata almasına rağmen maksimum deneme sınırını (10 deneme) aşan ve operatör incelemesi için Dead-Letter Queue (DLQ) durumuna geçen kayıtlar.

---

## 3. İş Kurallarıyla Tutarlılık Denetimi

| İş Kuralı Kodu | Konu | Uyum Durumu | Denetim Açıklaması |
|---|---|---|---|
| `BR-SYNC-01` | Kalıcı Outbox kuyruğu | **TAM UYUMLU** | `sync_operations` tablosu yerel transaction ile atomik yazılır. |
| `BR-SYNC-03` | Idempotency ve mükerrerlik engeli | **TAM UYUMLU** | `idempotency_key` ve sunucu Inbox defteri ile çift satış imkansızdır. |
| `BR-SYNC-05` | Fiyat çakışması | **TAM UYUMLU** | Çift değer korunur, kasada yerel fiyat sürer, audit kaydı tutulur. |
| `BR-SYNC-06` | Çevrimdışı satışların silinemezliği | **TAM UYUMLU** | Satış fişleri ve hareketler hiçbir çakışmada silinmez. |
| `BR-STK-02` | Eksi stok serbestliği | **TAM UYUMLU** | Çoklu cihaz çevrimdışı satışlarında eksi stok oluşumu desteklenir. |
| `BR-POS-08` | Satış iptali idempotency | **TAM UYUMLU** | `status = 'CANCELLED'` güncellemesi tek yönlü ve idempotenttir. |
| `BR-POS-09` | Kısmi iadeler | **TAM UYUMLU** | Eşzamanlı tavan kontrolü ve `CONFLICT` durumu eksiksiz modellenmiştir. |
| `BR-BAK-05`, `06` | Geri yüklemede kuyruk koruma | **TAM UYUMLU** | Koruyucu snapshot ve immutable sıra numarası koruması sağlanmıştır. |
| `BR-SEC-04` | Cihaz yetki iptali | **TAM UYUMLU** | Ağ temasında anında HTTP 403 ve oturum feshi kuralları netleştirilmiştir. |

---

## 4. Sertleştirme Sonuç Tablosu

| Bulgu Kodu | Önem | Başlık | Durum | Hedef Doküman Revizyonu |
|---|---|---|---|---|
| **`FND-SYNC-01`** | **HIGH** | Restore Sıra Numarası Değişmezliği | **DÜZELTİLDİ** | `OFFLINE_SYNC_PROTOCOL.md` Bölüm 8 |
| **`FND-SYNC-02`** | **HIGH** | Meta-Veri ve Medya Şeridi Ayrımı | **DÜZELTİLDİ** | `OFFLINE_SYNC_PROTOCOL.md` Bölüm 10 |
| **`FND-SYNC-03`** | **MEDIUM** | Atomik Worker Kiralama (`worker_id`) | **DÜZELTİLDİ** | `OFFLINE_SYNC_PROTOCOL.md` Bölüm 2 |
| **`FND-SYNC-04`** | **MEDIUM** | Çevrimdışı Cihaz İptali Tehdit Modeli | **DÜZELTİLDİ** | `OFFLINE_SYNC_PROTOCOL.md` Bölüm 7, 9 |
| **`FND-SYNC-05`** | **MEDIUM** | Sunucu Inbox Atomik Transaction | **DÜZELTİLDİ** | `OFFLINE_SYNC_PROTOCOL.md` Bölüm 4 |
| **`FND-SYNC-06`** | **LOW** | `RETRY_EXHAUSTED` (DLQ) Durumu | **DÜZELTİLDİ** | `OFFLINE_SYNC_PROTOCOL.md` Bölüm 2, 5 |

---

## 5. Sonuç ve Öneri

> [!TIP]
> **DENETİM VE SERTLEŞTİRME ONAYI:**  
> Yapılan teknik denetim sonucunda tespit edilen 6 bulgu, `OFFLINE_SYNC_PROTOCOL.md` ve `OFFLINE_SYNC_DECISIONS.md` dokümanlarına yansıtılarak protokol **v1.1 Sertleştirilmiş Sürüm** seviyesine yükseltilmiştir.  
> Bu haliyle senkronizasyon protokolü, dağıtık sistem hatalarına, eşzamanlı yarışlara ve kaza/çökme senaryolarına karşı tam korumalıdır.  
> **Faz 0 henüz tamamlanmamıştır.** Bir sonraki görev olarak **Windows, Android, iOS ve Web İçin Yerel Depolama Doğrulaması**na geçilmesi önerilmektedir.

