# Market Management System (MMS) — Veri Modeli Mimari Kararları (Data Model Architecture Decisions)

**Doküman Kodu:** `DATA_MODEL_DECISIONS.md`  
**Sürüm:** 1.1 (Revize ve Sertleştirilmiş Sürüm)  
**Tarih:** 31 Ekim 2026  
**Durum:** Faz 0 — Veri Modeli Karar Kayıtları (Son Teknik Bulgular Kapatıldı)  
**Ana Referans Doküman:** `MARKET_POS_AI_STUDIO_BUILD_PLANI.md` (v1.2.2)  
**İlgili Tasarım Dokümanı:** `docs/architecture/DATA_MODEL.md` (v1.1)  
**İlgili Denetim Belgeleri:** `docs/architecture/DATA_MODEL_REVIEW.md` (v1.0), `docs/architecture/DATA_MODEL_V1_1_TECHNICAL_VALIDATION.md` (v1.0)  
**Teknik Proje / Klasör Adı:** `market-pos`  
**Ürün Tanımı:** Market Management System (MMS) — Profesyonel Market Yönetim SaaS Uygulaması  

---

## 1. Amaç ve Kapsam

Bu doküman, **Market Management System (MMS)** veri modeli v1.1 tasarlanırken ve bağımsız teknik doğrulama raporundaki bulgular (`NEW-01` .. `NEW-04`, `FND-04`, `FND-05`) ele alınırken verilen mimari kararları, eşzamanlılık (concurrency) mekanizmalarını, idempotency kurallarını ve teknik sınırları kayıt altına alır.

> [!NOTE]
> **Pilot ve Gelecek SaaS Mimari Bağlamı:** Bu belgedeki kararlar, pilot için Windows Local Master Hub (merkezi SQLite) ve uç cihazlar (Drift + SQLite) üzerinde uygulanacak ilkeleri belirler. SQLite ortamında motor seviyesinde RLS (Row Level Security) bulunmadığından, pilot aşamasında tenant/store veri erişim izolasyonu merkezi API iş mantığı seviyesinde uygulanacaktır. PostgreSQL ve RLS politikaları, çok şubeli bulut SaaS genişlemesi için tarihsel ve hedef karar olarak korunmaktadır. Spesifik tablo sayıları, alan adları ve veri tipleri taslak niteliğinde olup Aşama 6B-2 ve Faz 1'de doğrulanacaktır.

---

## 2. Mimari Karar Kayıtları (Decisions)

---

### Karar 1: Para Alanlarında Kuruş Bazlı Tamsayı (`BIGINT`) Temsili
- **Bağlam:** Finansal alanlarda kayan noktalı sayı aritmetiği hatalarını önleme zorunluluğu (`BR-POS-04`).
- **Karar:** Tüm para değerleri kuruş tamsayı (`BIGINT` / `INTEGER`) olarak tutulur. Kayan noktalı sayı aritmetiği kesinlikle kullanılmaz.
- **Durum:** `[CONFIRMED]`

---

### Karar 2: Birleşik Barkod Yaşam Döngüsü ve Mutlak Kiracı Tekilliği (`FND-01`)
- **Bağlam:** Aktif ve pasif barkodların mükerrer kullanımını engelleme (`BR-PROD-02`, `BR-PROD-15`).
- **Karar:** `barcode_history` tablosu `product_barcodes` içine çekilmiştir. Küresel `UNIQUE (tenant_id, barcode)` deklaratif kısıtı ile pasif bir barkodun sistemdeki başka bir ürüne mükerrer atanması veritabanı motoru seviyesinde engellenmiştir. Arama için kısmi benzersiz indeks (`idx_active_product_barcodes`) kullanılır.
- **Durum:** `[CONFIRMED]`

---

### Karar 3: Atomik Stok Birimi Prensibi ve Kesirli Birim Dönüşümü (`FND-02`)
- **Bağlam:** Koli/kutu gibi paketli ürünlerde periyodik bölme ($1/24$) kaynaklı yuvarlama sapmalarını sıfırlama (`BR-PROD-07`, `BR-PROD-08`).
- **Karar:** Depolanan `stock_unit` daima bölünemez en küçük atomik birim (adet, gram, ml) olarak belirlenir. Ürün kartında `conversion_factor_numerator` ve `conversion_factor_denominator` tamsayı pay/payda oranları kullanılır. Dönüşümler tamsayı çarpımıyla yapılır; periyodik bölme sapması sıfırdır.
- **Durum:** `[CONFIRMED]`

---

### Karar 4: Eksi Stoğun Veritabanı Seviyesinde Serbest Bırakılması
- **Bağlam:** Rafta bulunan faturası henüz girilmemiş ürünlerin kasadan satılabilmesi zorunluluğu (`BR-STK-02`, `BR-STK-03`).
- **Karar:** `stock_balances.current_stock` alanında `CHECK (current_stock >= 0)` kısıtı yer almaz; negatif sayılar serbesttir. Eksi stoklar `idx_stock_balances_negative` kısmi indeksiyle dashboard'da izlenir.
- **Durum:** `[CONFIRMED]`

---

### Karar 5: Çevrimdışı Stok Sayımında Nedensel Sıralama, Cihaz Sıra Numarası ve Belirsizlik Aralığı (`FND-05`)
- **Bağlam:** Sayım sürerken veya çevrimdışıyken yapılan satışların matematiksel olarak çift düşülmeden uzlaştırılması (`BR-STK-08`, `BR-STK-09`).
- **Değerlendirilen Senaryolar ve Kararlar:**
  1. **Cihaz Zamanı ve Sunucu Zamanının Ayrılması:** Sayım kaleminde yerel cihaz zamanı (`client_counted_at`) ile sunucu uzlaştırma zamanı (`server_reconciled_at`) ayrılmıştır.
  2. **Tek Cihazda Nedensel Sıralama (Causal Ordering):** Eğer sayım işlemi ve satış işlemi aynı cihazda çevrimdışıyken gerçekleşmişse, `sync_operations.client_sequence_number` alanı sayesinde işlemlerin mutlak oluşum sırası kesin olarak bilinir (`sequence_number` küçük olan önce gerçekleşmiştir).
  3. **Çoklu Cihazda Çevrimdışı Durum ve Belirsizlik Sınırı:**  
     - Cihaz A çevrimdışı sayım yaparken, Cihaz B çevrimdışı satış yapıyorsa; cihaz saatleri arasındaki olası sapma (clock drift) nedeniyle iki bağımsız cihazdaki olayların mutlak kronolojik sırası **matematiksel olarak kesin bilinemez**.
     - Bu durumda sunucu uzlaştırma motoru oturum açılışındaki zaman ofsetini kullanarak $\pm 5$ dakikalık bir **belirsizlik aralığı (ambiguity window)** uygular.
     - Sayım anının $\pm 5$ dakikalık penceresine denk gelen satış hareketleri `stock_count_items.is_ambiguous_interval = true` olarak işaretlenir.
     - Varsayılan iş kuralı olarak fiziksel sayım fiili durum kabul edilir, ancak şüpheli hareketler yönetici dashboard'unda incelemeye sunulur.
- **Durum:** `[CONFIRMED]` (Veri alanları ve tek cihaz determinizmi kesin; çoklu cihaz uzlaştırma penceresi `[PROPOSED]`).

---

### Karar 6: Satış Başına Tek Ödeme ve Düzeltme Modeli
- **Bağlam:** MVP aşamasında satış başına tek ödeme (Nakit veya Kart) esastır (`BR-PAY-01`).
- **Karar:** Karmaşık 1-N `payments` tablosu yerine `sales.payment_method` doğrudan kullanılır. Hatalı seçimler `payment_method_corrections` tablosuyla denetlenir (`BR-PAY-05`).
- **Durum:** `[CONFIRMED]`

---

### Karar 7: Tam Satış İptali ile Kısmi İadenin Ayrıştırılması ve Idempotency (`EK-04`)
- **Bağlam:** Fiş iptali ile ürün iadesi muhasebesi ayrımı (`BR-POS-08`, `BR-POS-09`).
- **Karar:** Tam iptalde `sales.status = 'CANCELLED'` güncellenir ve fiş cirodan tamamen çıkar. Satış iptali idempotenttir; mükerrer çağrılsa bile stok iadesini tekrarlamaz.
- **Durum:** `[CONFIRMED]`

---

### Karar 8: Şube Tablolarında Çift Seviyeli Bileşik Foreign Key `(tenant_id, store_id)` (`FND-03`)
- **Bağlam:** Multi-tenant veri izolasyonunda bir şubenin başka bir tenant altında işlem görmesini engelleme (`BR-TNT-02`).
- **Karar:** `stores` tablosuna `UNIQUE (tenant_id, id)` eklenmiş; tüm şube tabanlı operasyonel tablolarda `FOREIGN KEY (tenant_id, store_id) REFERENCES stores(tenant_id, id) ON DELETE RESTRICT` uygulanmıştır.
- **Durum:** `[CONFIRMED]`

---

### Karar 9: Eşzamanlı Kısmi İadelerde Satır Kilitleme, Atomik Güncelleme ve Çevrimdışı Çakışma Yönetimi (`FND-04`)
- **Bağlam:** Aynı fişteki bir ürün için birden fazla kez kısmi iade yapılması durumunda satılan miktarın aşılmasının önlenmesi (`BR-POS-09`).
- **Karar ve Uygulama Detayları:**
  1. **Yalnızca CHECK Kısıtı Yetersizdir:** `sale_items` üzerindeki `CHECK (refunded_quantity <= quantity)` kısıtı veritabanı motorunun son savunma hattıdır; ancak tek başına eşzamanlı transaction yarışını (race condition) veya çevrimdışı çoklu cihaz çakışmasını yönetemez.
  2. **Sunucu Eşzamanlılık Kontrolü (Atomic Conditional Update):** İade transaction'ı sırasında `sale_items` satırı doğrudan koşullu atomik update ile kilitlenir ve güncellenir:
     ```sql
     UPDATE sale_items 
     SET refunded_quantity = refunded_quantity + :refund_qty 
     WHERE id = :sale_item_id 
       AND (refunded_quantity + :refund_qty) <= quantity 
     RETURNING refunded_quantity;
     ```
     Eğer dönen satır sayısı 0 ise işlem veritabanı seviyesinde reddedilir ve `OVER_REFUND_ERROR` üretilir.
  3. **İdempotency Güvencesi:** `refunds` tablosuna `idempotency_key TEXT NOT NULL` ve `UNIQUE (tenant_id, idempotency_key)` kısıtı eklenmiştir. Ağ kesintisinde istemci aynı iadeyi tekrar gönderdiğinde mükerrer iade ve mükerrer stok girişi engellenir.
  4. **Çevrimdışı Çoklu Cihaz Çakışma Protokolü (Cross-Device Conflict):**  
     - İki bağımsız çevrimdışı cihaz (PC ve mobil) aynı fişteki ürün için ayrı ayrı kısmi iade açarsa ($3 + 3 = 6 > 5$):
     - Her iki cihaz da internet yokken yerelde işlemi kaydeder.
     - Sunucuya ilk ulaşan cihazın iadesi başarıyla işlenir (`refunded_quantity = 3`).
     - İkinci cihaz sunucuya ulaştığında atomik koşullu güncelleme reddedilir ($3 + 3 > 5$).
     - Sunucu ikinci cihazın `sync_operations` kaydını `status = 'CONFLICT'` durumuna alır.
     - Kasiyer/işletme sahibine dashboard'da iade tutarsızlığı uyarısı verilir ve `audit_logs` tablosuna `'REFUND_CONFLICT_REJECTED'` kaydı düşülür. Fiş sessizce bozulmaz veya satılandan fazla stok iade edilmez.
- **Durum:** `[CONFIRMED]`

---

### Karar 10: Hasarlı İadelerin Satılabilir Stoğu Etkilememesi Davranışı (`EK-01`)
- **Bağlam:** İade edilen ürün hasarlı/bozuk ise (`condition = 'DAMAGED'`) stok yönetimi (`BR-POS-10`).
- **Karar:** Hasarlı iadelerde `stock_balances.current_stock` kesinlikle artırılmaz ve mükerrer azaltılmaz (net değişim 0'dır). Müşteriye para iadesi yapılır; `stock_movements` tablosuna `FIRE_KAYIP` denetim kaydı atılır.
- **Durum:** `[CONFIRMED]`

---

### Karar 11: Offline Senkronizasyon Outbox Tablosu (`sync_operations`) (`EK-02`)
- **Bağlam:** Uç cihazların çevrimdışı işlemlerini yerel veritabanında kalıcı kuyruğa alma gereksinimi (`BR-SYNC-01`).
- **Karar:** `sync_operations` tablosu veri modeline 25. tablo olarak eklenmiştir.
- **Durum:** `[CONFIRMED]`

---

### Karar 12: Satış Ödeme Bütünlüğü ve Koşullu Tablo CHECK Kısıtı (`NEW-01`)
- **Bağlam:** Nakit ve kart satışlarında tutar, nakit alınan ve para üstü alanlarının mantıksal tutarlılığı (`BR-PAY-01`, `BR-PAY-02`, `BR-PAY-03`).
- **Değerlendirilen Alternatifler:**
  1. *Bağımsız Kolon CHECK Kısıtları:* Kolonlar nullable olduğu için `payment_method = 'CASH'` iken `cash_received_amount` NULL geçilirse kısıt tetiklenmez. Kart satışında yanlışlıkla 0 girilirse patlar.
  2. *Tablo Düzeyinde Koşullu CHECK Kısıtı (Seçilen Yaklaşım):*  
     `sales` tablosuna tablo düzeyinde birleşik kısıt eklenmiştir:
     ```sql
     CONSTRAINT chk_sales_payment_consistency CHECK (
       (payment_method = 'CASH' 
         AND cash_received_amount IS NOT NULL 
         AND cash_received_amount >= total_amount 
         AND cash_change_amount = (cash_received_amount - total_amount)
       )
       OR
       (payment_method = 'CARD' 
         AND cash_received_amount IS NULL 
         AND cash_change_amount IS NULL
       )
     )
     ```
- **Tercih Gerekçesi:**
  - Nakit satışta eksik para alınması veya yanlış para üstü hesaplanması veritabanı motoru seviyesinde fiziksel olarak imkansız kılınır.
  - Kartlı satışta nakit alanlarının kirlenmesi engellenir.
- **Durum:** `[CONFIRMED]`

---

### Karar 13: Uç Cihaz Senkronizasyonunda Monotonik Sıra Numarası (`NEW-02`)
- **Bağlam:** Yerel SQLite işlemlerinde aynı milisaniyede gerçekleşen veya saat geri alındığında bozulan FIFO sırasını güvenceye alma (`BR-SYNC-01`).
- **Karar:**
  - `sync_operations` tablosuna `client_sequence_number BIGINT NOT NULL` alanı eklenmiştir.
  - Sıra numarası yerel transaction içerisinde (Drift SQLite `AUTOINCREMENT` veya atomik sayaç tablosuyla) üretilir.
  - Aynı cihazın işlemleri sunucuya deterministik FIFO sırasıyla aktarılır.
  - Uygulama yeniden başlatıldığında sayaç kaldığı yerden devam eder.
  - İşlem tekrar gönderildiğinde (retry) sıra numarası kesinlikle değişmez.
  - Farklı cihazlar arasında küresel sıralama aranmaz; her cihaz kendi bağımsız serisine sahiptir.
- **Durum:** `[CONFIRMED]`

---

### Karar 14: Nullable Şube Alanlarında Bileşik FK ve `MATCH SIMPLE` Standardı (`NEW-03`)
- **Bağlam:** `audit_logs` gibi tablolarda `store_id` kolonu nullable olduğunda tenant-şube izolasyonunu sağlama.
- **Karar:**
  - `audit_logs` tablosunda `FOREIGN KEY (tenant_id, store_id) REFERENCES stores(tenant_id, id) ON DELETE SET NULL;` bileşik kısıtı uygulanmıştır.
  - PostgreSQL'in `MATCH SIMPLE` kuralına göre: `store_id` kolonu `NULL` ise (ör. tenant genelindeki kategori değişikliği) kısıt geçer; ancak `store_id` dolu ise `(tenant_id, store_id)` çifti `stores` tablosunda mutlaka doğrulanır. Yanlış şube ataması engellenir.
- **Durum:** `[CONFIRMED]`

---

### Karar 15: Domain Katmanında Atomik Stok Birimi Validasyonu (`NEW-04`)
- **Bağlam:** Veritabanı CHECK kısıtının hangi ürün için hangi birimin atomik olduğunu tek başına bilememesi (`FND-02`).
- **Karar:**
  - Clean Architecture prensiplerine uygun olarak **Domain Katmanı** içerisindeki `CreateProductUseCase` ve `ProductValidator` servislerinde aşağıdaki doğrulama kuralları zorunlu tutulmuştur:
    1. Ürün stok birimi (`stock_unit`) bölünemez atomik birim olmalıdır (Adet, Gram, Mililitre).
    2. Koli/kutu gibi ticari paketler için `pricing_unit` belirlenmeli, `conversion_factor_numerator` tamsayı ambalaj adedi girilmeli, `conversion_factor_denominator = 1` olmalıdır.
    3. Fiyatlandırma birimi ile stok birimi aynı ise pay ve payda zorunlu olarak 1 olmalıdır.
    4. Bakiye dönüşümlerinde rasyonel aritmetik formülü ($Q_{\text{stock}} = Q_{\text{pricing}} \times \frac{\text{numerator}}{\text{denominator}}$) işletilmeli, floating-point bölme yapılmamalıdır.
- **Durum:** `[CONFIRMED]`

---

## 3. Henüz Kesinleşmemiş / Teknik Tasarımda Doğrulanacak Konular (`[PROPOSED]`)

Aşağıdaki konular veri bütünlüğü açısından risk teşkil etmemekte olup, ilgili tasarım adımlarında ele alınmak üzere `[PROPOSED]` durumunu korumaktadır:

1. **Çevrimdışı Çoklu Cihaz Sayım Belirsizlik Aralığı Algoritması (`FND-05`):**
   - Sayım anının $\pm 5$ dakikalık penceresine denk gelen satış hareketlerinin otomatik uzlaştırma kuralları ve kullanıcı arayüzü uyarı modeli senkronizasyon tasarımında saha testleriyle doğrulanacaktır.
2. **Sepet ve Sayım Kilidi Lease Parametreleri (`BR-POS-06`, `BR-STK-07`):**
   - 30 saniye kalp atışı ve 2 dakika kilit zaman aşımı süreleri ağ dayanıklılık testleriyle optimize edilecektir.
3. **Hasarlı İade Karantina Deposu (`BR-POS-10`):**
   - Hasarlı ürünler MVP'de `FIRE_KAYIP` ile doğrudan fireye atılmaktadır. İleride tedarikçiye iade edilmek üzere fiziksel bir karantina deposu gerekirse `damaged_stock_balances` tablosu değerlendirilecektir.
4. **Geri Yükleme Sırasında Bekleyen Senkronizasyon Kuyruklarının Uzlaştırılması (`BR-BAK-06`):**
   - Yedek geri yüklendiğinde çevrimdışı cihazlardaki bekleyen yerel Outbox kuyruğunun sunucuyla çift yönlü uzlaştırma protokolü senkronizasyon tasarımında ele alınacaktır.
5. **Şubeye Özel Fiyatlandırma Şeması (`BR-TNT-04`):**
   - Faz 8 çoklu şube aşamasında `store_product_prices` tablosu veri modeline eklenecektir.

---

## 4. Çelişki ve Tutarlılık İncelemesi

- **`DATA_MODEL_V1_1_TECHNICAL_VALIDATION.md` ile Uyumluluk:**
  - `NEW-01`: `chk_sales_payment_consistency` koşullu kısıtı kararlaştırıldı.
  - `NEW-02`: `sync_operations.client_sequence_number` (monotonik artan sayaç) kararlaştırıldı.
  - `NEW-03`: `audit_logs` nullable şube bileşik FK kararlaştırıldı.
  - `NEW-04`: Domain katmanında atomik stok birimi validasyonu kararlaştırıldı.
  - `FND-04`: Eşzamanlı iadeler için satır kilitleme, atomik güncelleme, idempotency ve offline çakışma protokolü kararlaştırıldı.
  - `FND-05`: Çevrimdışı sayımda nedensel sıralama ve belirsizlik aralığı protokolü netleştirildi.
- **Sonuç:** Hiçbir çelişki tespit edilmemiştir; veri modeli ve kararlar %100 uyumludur.
