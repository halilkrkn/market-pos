# MARKET MANAGEMENT SYSTEM (MMS) — Veri Modeli ve Senkronizasyon Mimari Denetimi (Data Model & Sync Review)

**Rapor Kodu:** `MARKET_MMS_DATA_MODEL_SYNC_REVIEW.md`  
**Tarih:** 4 Kasım 2026  
**Aşama:** Faz 0 — Veri Modeli, Senkronizasyon ve Dağıtık Bütünlük İncelemesi  
**Hazırlayan:** Google Antigravity / Gemini 3.8 Flash (High)  
**Kapsam:** `DATA_MODEL.md` v1.1 İçindeki 25 Tablonun Merkezi SQLite ve Mobil SQLite Sorumluluk Dağılımı, Senkronizasyon Akış Yönleri, 12 Kritik Veri Bütünlüğü İlkesi ve Model Düzeltme Önerileri  
**İlgili Belgeler:** `docs/architecture/DATA_MODEL.md` (v1.1), `docs/architecture/OFFLINE_SYNC_PROTOCOL.md` (v1.1), `docs/requirements/BUSINESS_RULES_SPEC.md` (v1.2)

---

## 1. Giriş ve Temel İlke

MARKET MANAGEMENT SYSTEM (MMS), fiziksel market ortamında Windows ana bilgisayar (Windows Service + Merkezi SQLite) ve mobil cihazların (Android/iOS Drift + SQLite) bir arada çalıştığı hibrit, asenkron ve dağıtık bir sistemdir.

Bu mimaride **en yaygın tasarım yanılgısı; merkezi veritabanı ile mobil uç cihazların veritabanı şemalarının ve veri yüklerinin birebir aynı olması gerektiğini varsaymaktır**.

- **Merkezi SQLite (Windows Service):** İşletmenin tüm tarihsel satış arşivini, tüm cihazların audit loglarını, ürün maliyet geçmişini ve yetkili tekil stok defterini barındıran **nihai doğruluk kaynağıdır (Single Source of Truth)**.
- **Mobil SQLite (Drift / Telefon):** Kasada hızlı ürün bulma, kamera ile barkod okuma, sepet oluşturma ve çevrimdışı satış yapma operasyonunu destekleyen, disk ve bellek dostu bir **uç operasyonel önbellek ve Outbox kuyruğu deposudur (Operational Edge Cache & Outbox Store)**.

Bu raporda mevcut 25 tablo bu prensip ışığında incelenmiş; veri sorumlulukları ve senkronizasyon yönleri netleştirilmiştir.

---

## 2. 25 Tablonun Konum ve Senkronizasyon Dağılım Matrisi

Aşağıdaki tabloda her bir varlığın Merkezi Windows SQLite ve Mobil Drift SQLite tarafındaki rolü ile senkronizasyon yönü tanımlanmıştır:

| No | Tablo Adı | Merkezi SQLite | Mobil SQLite | Senkronizasyon Yönü | Açıklama ve Neden Farklı? |
| :---: | :--- | :---: | :---: | :---: | :--- |
| **1** | `tenants` | **TAM** | **ÖZET** | **Aşağı (Downlink)** | Mobil cihaz yalnızca bağlı olduğu aktif tenant bilgilerini tutar; diğer kiracıları bilmez. |
| **2** | `stores` | **TAM** | **ÖZET** | **Aşağı (Downlink)** | Mobil cihaz yalnızca kayıtlı olduğu fiziksel şubenin kimlik ve adını tutar. |
| **3** | `users` | **TAM** | **ÖZET / YOK** | **Aşağı (Downlink)** | Mobil cihaz yalnızca oturum açmış aktif kullanıcının (işletme sahibi) profil ve tokenını saklar. |
| **4** | `memberships` | **TAM** | **YOK** | **Yerel (Yalnızca Merkez)** | Rol ve üyelik yönetimi merkezi bir idari işlevdir; mobil uç birimde tabloya gerek yoktur. |
| **5** | `devices` | **TAM** | **KENDİSİ** | **Çift Yönlü** | Cihaz ilk eşleştirmede merkeze kaydedilir; mobil cihaz yalnızca kendi `device_id` ve durumunu bilir. |
| **6** | `categories` | **TAM** | **TAM** | **Aşağı (Downlink)** | Hızlı ürün filtreleme için tüm kategori hiyerarşisi mobilde eksiksiz önbelleklenir. |
| **7** | `products` | **TAM** | **TAM (Aktifler)**| **Aşağı (Downlink)** | Kasada anında ürün bulabilmek için aktif ürün kataloğu mobilde tam yerel tutulur. |
| **8** | `product_barcodes` | **TAM** | **TAM** | **Aşağı (Downlink)** | Barkod okutulduğunda sıfır gecikmeyle ürün eşleşmesi için tüm aktif barkodlar mobildedir. |
| **9** | `product_images` | **TAM** | **ÖNBELLEK** | **Aşağı (Medya)** | Görseller mobilde yalnızca ihtiyaç duyuldukça yerel disk önbelleğine indirilir (`Lane 2`). |
| **10** | `price_history` | **TAM** | **YOK / KISITLI** | **Yerel (Yalnızca Merkez)** | Tarihsel fiyat değişim logları mobilde gerekmez; mobilde yalnızca `products.current_sale_price` kullanılır. |
| **11** | `cost_history` | **TAM** | **YOK** | **Yerel (Yalnızca Merkez)** | Gizli toptancı alış maliyetleri güvenlik gereği kasiyer/mobil cihazlara aktarılmaz (`BR-PROD-13`). |
| **12** | `stock_balances` | **TAM (Yetkili)**| **ÖNBELLEK** | **Aşağı (Delta Yayını)**| Mobil cihaz son bilinen stok bakiyesini görür; eksi stok serbest olduğundan çevrimdışı satışı engellemez. |
| **13** | `stock_movements` | **TAM (Defter)** | **OUTBOX GEÇİCİ**| **Yukarı (Uplink)** | Mobil cihaz yaptığı satışın stok düşüm hareketini üretir, merkeze aktarır; merkez deftere yazar. |
| **14** | `stock_counts` | **TAM** | **OTURUM BAZLI** | **Çift Yönlü** | Mağaza sayımı sırasında mobilde aktif sayım oturumu açılır, bitince merkeze teslim edilir. |
| **15** | `stock_count_items`| **TAM** | **OTURUM BAZLI** | **Yukarı (Uplink)** | Mobilde taranan sayım kalemleri merkeze gönderilir; merkez uzlaştırmayı icra eder. |
| **16** | `held_carts` | **TAM (Paylaşımlı)**| **TAM (Yerel)** | **Çift Yönlü / Ops**| Beklemeye alınan sepet mobilde yerel kalabilir veya diğer kasaların devralması için merkeze senkronize edilir. |
| **17** | `held_cart_items` | **TAM (Paylaşımlı)**| **TAM (Yerel)** | **Çift Yönlü / Ops**| Bekleyen sepet kalemleri. |
| **18** | `sales` | **TAM (Tarihsel)** | **SON SATIŞLAR** | **Yukarı (Uplink)** | Mobil cihaz çevrimdışı satışını kaydeder ve merkeze basar; mobilde yalnızca son N günün fişleri tutulur. |
| **19** | `sale_items` | **TAM (Tarihsel)** | **SON SATIŞLAR** | **Yukarı (Uplink)** | Satış detay satırları, snapshot fiyat ve miktar bilgileri. |
| **20** | `refunds` | **TAM** | **YEREL / İLGİLİ**| **Yukarı (Uplink)** | Mobilde yapılan iade kaydı merkeze aktarılır; merkez satılan miktarın aşılmadığını atomik teyit eder. |
| **21** | `refund_items` | **TAM** | **YEREL / İLGİLİ**| **Yukarı (Uplink)** | İade satır detayları. |
| **22** | `payment_method_corrections`| **TAM** | **YEREL / İLGİLİ**| **Yukarı (Uplink)** | Hatalı ödeme yöntemi düzeltmesi yetkili denetim kaydı olarak merkeze aktarılır. |
| **23** | `audit_logs` | **TAM (Append-only)**| **OUTBOX GEÇİCİ**| **Yukarı (Uplink)** | Mobilde oluşan kritik güvenlik ve işlem logları merkeze iletilir; mobilde biriktirilmez. |
| **24** | `device_sessions` | **TAM** | **KENDİSİ** | **Yukarı (Uplink)** | Cihazın açılış, kapanış ve ağ bağlantı oturum metrikleri. |
| **25** | `sync_operations` | **GELEN (INBOX)** | **GİDEN (OUTBOX)**| **Yukarı $\to$ ACK** | Mobilde deterministik artan FIFO kuyruğu; merkezde idempotent işleme ve onay defteri. |

---

## 3. 12 Kritik Veri Bütünlüğü ve Senkronizasyon Konusunun Değerlendirilmesi

### 3.1. Merkezi SQLite ve Mobil SQLite Veri Sorumlulukları
- **Merkezi SQLite:** Tek yetkili otoritedir. Bütün cihazların işlemlerini toplar, sıralar, `stock_balances` bakiyesini tekil olarak günceller ve tarihsel muhasebe defterini tutar.
- **Mobil SQLite:** İstemci odaklıdır. Cihaz belleğini şişirmemek için yıllar öncesinin satışlarını veya alış maliyetlerini tutmaz. Yalnızca satış yapmaya ve bekleyen işlemleri Outbox'ta korumaya odaklanır.

### 3.2. Tenant / Store İlişkileri
- Fiziksel market pilotunda tek bir `tenant` ve tek bir `store` kullanılacaktır.
- Ancak veri modelindeki tüm tablolarda `tenant_id` ve operasyonel tablolarda `store_id` **kesinlikle korunacaktır**.
- Bu yaklaşım, yarın ikinci bir şube açıldığında veya yazılım çoklu market SaaS modeline geçtiğinde veritabanı şemasını baştan yazma zorunluluğunu (büyük kırıcı refactor) tamamen ortadan kaldırır.

### 3.3. Device ve `device_sequence` (Deterministik FIFO Sıralaması)
- Her mobil cihaz donanım tabanlı kalıcı bir `device_id` (UUID) alır (`BR-SYNC-01`).
- Cihazda üretilen her `sync_operations` kaydı için `client_sequence_number` (1, 2, 3...) atanır (`NEW-02`).
- Windows Service, aynı cihazdan gelen paketleri bu numaranın artan sırasına göre işler. Cihaz saati yanlış olsa veya geri alınsa bile, işlemlerin cihazdaki fiziksel oluşum sırası **bozulamaz**.

### 3.4. Operation ID ve İdempotency (`idempotency_key`)
- Ağ kopmalarında mobil cihaz aynı satışı defalarca merkeze gönderebilir.
- Her satış ve iade işleminde cihazda UUID tabanlı benzersiz bir `idempotency_key` üretilir.
- Windows Service Merkezi API'si, gelen anahtarı kontrol eder; işlem daha önce işlenmişse ikinci kez stok düşmez veya mükerrer fiş açmaz; ilk işlemin sonucunu (HTTP 200 / ACK) döner (`BR-SYNC-01`).

### 3.5. Outbox ve ACK Mekanizması
- Mobil cihazda bir satış tamamlandığında, işlem yerel `sync_operations` tablosuna `status = 'PENDING'` olarak yazılır.
- Mobil arka plan senkronizasyon servisi işlemi Windows API'ye gönderir (`status = 'SYNCING'`).
- **Kesin Kural:** Windows Service'ten açık ve doğrulanmış **ACK (Acknowledge)** yanıtı gelmeden mobil cihaz işlemi asla `status = 'COMPLETED'` olarak işaretleyemez (`BR-SYNC-02`). ACK alınamazsa kiralama süresi (lease) biter ve işlem tekrar denenir.

### 3.6. Sale, Sale Item ve Stock Movement Transaction Bütünlüğü
- **Mobil Tarafta:** Satışın kaydedilmesi (`sales`), sepet kalemlerinin yazılması (`sale_items`), yerel stok düşümü (`stock_movements`) ve kuyruk kaydı (`sync_operations`) **tek bir yerel SQLite transaction'ı içinde atomik** gerçekleşir (`BR-POS-05`). Yarım kalan satış fiziksel olarak imkânsızdır.
- **Merkezi Tarafta:** Windows Service paketi aldığında, satış kaydı, kalemler ve merkezi stok bakiyesi güncellemesini **tek bir merkezi SQLite transaction'ı içinde** atomik icra eder.

### 3.7. `occurred_at` (Cihaz Zamanı) ve `accepted_at` (Merkez Kabul Zamanı) Ayrımı
- `occurred_at`: Satışın cihazda fiilen yapıldığı yerel anı gösterir (fiş üzerine bu tarih basılır).
- `accepted_at`: Satış paketinin Windows Service tarafından teslim alınıp merkezi veritabanına işlendiği sunucu anıdır.
- Bu iki alanın ayrılması, cihaz saatlerinin farklılığından doğan kronolojik karmaşayı ve raporlama uyuşmazlıklarını çözer.

### 3.8. Stok Çakışması ve Oversell (Eksi Stok Serbestliği)
- Projede çevrimdışı stok politikası `allow` olarak kabul edilmiştir (`BR-STK-02`, `BR-STK-03`).
- İki mobil cihaz çevrimdışıyken son kalan 1 adet ürünü aynı anda satabilir ($1 - 2 = -1$).
- **Kural:** Gerçekleşmiş satışlar stok yetersizliği nedeniyle **asla silinmez veya iptal edilmez** (`BR-SYNC-06`).
- Windows Service stoğu eksiye düşürür (`current_stock = -1`), `stock_movements` tablosuna append-only yazar ve işletme sahibine dashboard'da "Stok Uyuşmazlığı / Negatif Stok" uyarısı üretir.

### 3.9. Fiyat ve Maliyet Snapshot'ı
- Satış anında ürünün o anki satış fiyatı, para birimi ve alış maliyeti `sale_items` satırına doğrudan kopyalanır (`unit_price_snapshot`, `unit_cost_snapshot`) (`BR-PROD-13`).
- Sonradan ürün yönetiminden yapılan fiyat artışları veya indirimler, geçmiş satış fişlerinin ve kâr raporlarının tutarlarını kesinlikle değiştiremez.

### 3.10. Tam Satış İptali ve Kısmi İade Ayrımı
- **İptal (`CANCELLED`):** Fişin tamamı iptal edilir. Satış kaydı silinmez; durumu güncellenir, ters stok hareketi açılır ve cirodan tamamen çıkarılır (`BR-POS-08`).
- **Kısmi İade (`refunds`):** Belirli ürünler iade alınır. İade satırındaki miktar, orijinal satıştaki miktarı aşamaz (`refunded_quantity <= quantity`). Eşzamanlı iadeler koşullu atomik SQL ile korunur (`FND-04`).

### 3.11. Audit Kayıtları (Append-Only Denetim İzi)
- Fiyat değişiklikleri, manuel sepet indirimleri, stok sayım farkları, hatalı ödeme yöntemi düzeltmeleri ve iadeler `audit_logs` tablosuna silinemez ve değiştirilemez biçimde yazılır.
- Mobil cihaz kendi ürettiği audit loglarını senkronizasyon ile merkeze iletir; merkez tüm mağazanın denetim izini konsolide saklar.

### 3.12. Veri Tabanı Sürümleme (Migration) ve Kaza Kurtarma
- Hem Drift (mobil) hem de Windows Service SQLite tarafında deklaratif `schema_version` tablosu tutulur.
- SQLite WAL modunun sağladığı otomatik crash recovery mekanizması sayesinde elektrik kesintisinde bozulma önlenir.
- Herhangi bir geri yükleme (restore) öncesinde canlı veritabanının `VACUUM INTO` ile güvenlik kopyası (`safety_snapshot`) alınması zorunludur.

---

## 4. Tespit Edilen Model Uyumsuzlukları ve Önerilen Düzeltmeler

Mevcut `DATA_MODEL.md` v1.1 dosyası mantıksal olarak mükemmel tasarlanmış olmakla birlikte, yeni Windows Local Hub mimarisi açısından şu 3 düzeltmeye ihtiyaç duymaktadır:

1. **`processed_operations` (Merkezi Inbox) Tablosunun Eklenmesi:**
   - Mevcut modelde mobil tarafın Outbox tablosu (`sync_operations`) tanımlıdır; ancak Windows Service'in gelen işlemleri kaydedip mükerrerliği önleyeceği merkezi Inbox tablosu şemaya deklaratif olarak eklenmelidir.
2. **PostgreSQL RLS ve pg_cron Bölümlerinin Arşivlenmesi:**
   - `DATA_MODEL.md` içindeki RLS kod blokları "Geleceğe Dönük SaaS Şartnamesi" olarak etiketlenmeli, pilot aşamasında SQLite DDL kısıtları (`CHECK`, `UNIQUE`, `FOREIGN KEY`) birincil kabul edilmelidir.
3. **Mobil Veri Modeli İçin "Hafifletilmiş Drift Şeması (Lightweight Mobile Profile)" Tanımı:**
   - Hangi tabloların mobil Drift'te açılacağı, hangilerinin yalnızca Windows Service SQLite'ta kalacağı dokümanda açıkça tablolaştırılmalıdır.

---

## 5. Sonuç ve Karar

Mevcut 25 tabloluk veri modeli, yeni Windows Local Master Hub mimarisiyle **%100 mantıksal uyumludur**. Tablo şemalarını silmeye veya sıfırdan yapmaya gerek yoktur. Yalnızca tabloların sorumluluk alanları (Merkez vs Uç) ve senkronizasyon yönleri yukarıdaki matrise göre netleştirilmiştir.

