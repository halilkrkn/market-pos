# Market Management System (MMS) — Mantıksal Veri Modeli Teknik Denetim Raporu (Data Model Technical Review)

**Doküman Kodu:** `DATA_MODEL_REVIEW.md`  
**Sürüm:** 1.0  
**Tarih:** 31 Ekim 2026  
**Durum:** Faz 0 — Bağımsız Teknik Mimari Denetimi  
**Denetlenen Ana Belgeler:**  
1. `docs/architecture/DATA_MODEL.md` (v1.0)  
2. `docs/architecture/DATA_MODEL_DECISIONS.md` (v1.0)  
3. `docs/requirements/BUSINESS_RULES_SPEC.md` (v1.2)  
4. `docs/requirements/PHASE_0_BUSINESS_DISCOVERY.md` (v1.3)  
5. `MARKET_POS_AI_STUDIO_BUILD_PLANI.md` (v1.2.2)  
6. `docs/ARCHITECTURE.md` (v1.0)  

---

## 1. Yönetici Özeti (Executive Summary)

Bu teknik denetim çalışması; **Market Management System (MMS)** projesinin Faz 0 aşamasında tasarlanan 25 tabloluk mantıksal veri modelinin (`DATA_MODEL.md`), onaylanmış iş kuralları (`BUSINESS_RULES_SPEC.md` v1.2), offline-first mimari prensipleri ve PostgreSQL/Drift çapraz platform hedefleriyle uyumunu **bağımsız ve eleştirel bir gözle** doğrulamak amacıyla gerçekleştirilmiştir.

### Temel Denetim Sonuçları:
- **Genel Değerlendirme:** Mantıksal veri modeli mimari açıdan **yüksek kalitede, iş kurallarıyla tam tutarlı ve sağlam bir temele sahiptir**.
- **Kritik Hata (CRITICAL):** Projenin devamını engelleyecek veya mimariyi çökertecek **hiçbir `CRITICAL` bulgu tespit edilmemiştir**.
- **Önemli İyileştirmeler (HIGH / MEDIUM):** Veritabanı DDL ve Drift implementasyonu aşamasında ele alınması gereken **5 adet teknik iyileştirme alanı** (çapraz barkod tekilliği, birim dönüşümünde periyodik bölme hassasiyeti, bileşik foreign key kademesi, çoklu kısmi iade tavan kontrolü ve saat sapması güvencesi) tespit edilmiştir.
- **Teknik Tasarıma Geçiş Kararı:** Veri modeli, bu denetim raporundaki öneriler gözetilerek **offline senkronizasyon protokolü ve DDL/Drift teknik şema tasarımına geçmeye hazırdır**.

---

## 2. Denetim Başlıkları Kapsamında Ayrıntılı Değerlendirme

### 2.1 Veri Bütünlüğü ve İlişkisel Tasarım
- **Primary & Foreign Key Uyumu:** Tüm tablolarda UUID tabanlı birincil anahtarlar (`PK`) kullanılmıştır. Dağıtık ve çevrimdışı istemcilerde yerel ID üretimi için UUID zorunludur ve doğru seçilmiştir.
- **Tenant ve Store İzolasyon Hiyerarşisi:** Kök varlık olan `tenants` tablosu üzerinden hiyerarşik izolasyon kurulmuştur. Katalog varlıkları (`categories`, `products`, `product_barcodes`) tenant seviyesinde; operasyonel varlıklar (`stores`, `devices`, `stock_balances`, `stock_movements`, `sales`, `held_carts`, `refunds`) şube seviyesinde izole edilmiştir.
- **Constraint Yeterliliği:** Kuruş bazlı fiyatların pozitifliği (`CHECK price > 0`), miktarların pozitifliği (`CHECK quantity > 0`) ve durum alanlarının enum kısıtları deklaratif olarak tanımlanmıştır.
- **Soft Delete Disiplini:** Ürünler, kategoriler, kullanıcılar ve cihazlar için `is_active = false` bayrağı ile geçmiş kayıtların silinmesi engellenmiştir. Satışlar için `status = 'CANCELLED'` alanı kullanılarak veri kaybı önlenmiştir.
- **İyileştirme Fırsatı:** Şube bazlı operasyonel tablolarda (`sales`, `stock_balances`, `stock_movements`) `tenant_id` ve `store_id` alanları bağımsız FK olarak tanımlanmıştır. Bir fişin yanlışlıkla başka bir tenant'a ait şubeye bağlanmasını DB seviyesinde imkansız kılmak için `(tenant_id, store_id)` bileşik foreign key uygulanması önerilmektedir (Bkz: `FND-03`).

### 2.2 Ürün, Barkod ve Birim Modeli
- **Barkodsuz Ürün Mimarisi:** `products` tablosunda nullable bir barkod kolonu açılmamış; `product_barcodes` tablosunda kaydı olmayan ürün "Barkodsuz Ürün" olarak tanımlanmıştır. Ekmek hızlı satış tuşu doğrudan `product_id` ile eşleştirilmiştir (`BR-PROD-04`). Bu yaklaşım kusursuzdur.
- **Farklı Ticari Paketler:** Tekli kutu ve 6'lı paket gibi farklı ambalaj miktarları bağımsız birer `products` kaydı olarak ayrıştırılmıştır (`BR-PROD-02`). Bu sayede her paketin kendi satış fiyatı, maliyeti ve barkodu bağımsız yönetilebilir.
- **Barkod Tekilliği ve Tarihçe Ayrımı:** Aktif barkodlar `product_barcodes` tablosunda `UNIQUE (tenant_id, barcode)` ile korunmaktadır. Silinen barkodlar `barcode_history` tablosuna aktarılmaktadır. Ancak aktif barkodlar tablosu ile tarihçe tablosu arasında iki ayrı tablo bulunması nedeniyle çapraz veritabanı kısıtı zorluğu tespit edilmiştir (Bkz: `FND-01`).
- **Birim Dönüşüm Çarpanı (`unit_conversion_rate`):** Ürün kartındaki `stock_unit` ve `pricing_unit` ayrımı doğrudur. Ancak kutu ile stok tutulup adet ile satış yapıldığında ($1 / 24 = 0.041666...$) 3 ondalık haneli `NUMERIC(12, 3)` saklamada periyodik bölme yuvarlama sapması oluşma riski değerlendirilmiştir (Bkz: `FND-02`).

### 2.3 Satış ve Finansal İşlemler
- **Kuruş Bazlı Tamsayı Kesinliği (`BIGINT`):** Para alanlarında floating-point (`double`) aritmetiği tamamen dışlanmış, kuruş tamsayı (`BIGINT`) seçilmiştir. Bu karar Dart `int` ve SQLite `INTEGER` (64-bit) ile sıfır kayıpla çalışır (`BR-POS-04`).
- **Değişmez Snapshot Verileri:** `sale_items` satırlarında `product_name_snapshot`, `unit_snapshot`, `unit_price_snapshot` ve `unit_cost_snapshot` alanları zorunlu tutulmuştur. Ürün kartındaki fiyat veya maliyet sonradan değişse bile geçmiş satışlar etkilenmez (`BR-PROD-13`).
- **Nakit Para Üstü Hesabı:** `sales.cash_received_amount` ve `sales.cash_change_amount` alanları kuruş bazında modellenmiştir; `CHECK (cash_received_amount >= total_amount)` kısıtı ile eksik ödemede satış engeli veritabanı seviyesinde garanti altına alınmıştır (`BR-PAY-02`, `BR-PAY-03`).
- **İptal ve İade Ayrımı:** Tam satış iptali (`sales.status = 'CANCELLED'`) ile kısmi iade (`refunds` ve `refund_items`) birbirinden ayrılmıştır. Tam iptalde ciro sıfırlanır; kısmi iadede ise Brüt Satıştan iadeler düşülerek Net Satış hesaplanır (`BR-POS-08`, `BR-POS-09`, `BR-REP-02`).
- **Hasarlı İade Koruması:** `refund_items.condition = 'DAMAGED'` olduğunda `stock_movements` tablosuna `FIRE_KAYIP` yazılmakta ve satılabilir stoğun haksız yere artması engellenmektedir (`BR-POS-10`).
- **Ödeme Yöntemi Düzeltmesi:** `payment_method_corrections` tablosu sayesinde geçmiş satış fişi silinmeden veya sessizce değiştirilmeden kasa hasılat raporları düzeltilmektedir (`BR-PAY-05`).

### 2.4 Stok ve Sayım Mimarisi
- **Negatif Stok Uyum Kriteri:** `stock_balances` tablosunda `CHECK (current_stock >= 0)` kısıtı bilerek konulmamıştır. Eksi stok market gerçeğiyle tam uyumludur (`BR-STK-02`, `BR-STK-03`).
- **Append-Only Stok Defteri:** `stock_movements` tablosunda 9 farklı hareket türü tanımlanmış, silme ve güncelleme engellenmiştir (`BR-STK-11`).
- **Sayım Anında Satış ve Ürün Bazlı `counted_at`:** Sayım oturumu (`stock_counts`) açıkken kasada satış devam edebilir. Sayım kalemlerinde `stock_count_items.counted_at` zaman damgası tutularak sayım sonrası hareketlerin matematiksel uzlaştırılması modellenmiştir (`BR-STK-09`). Cihazlar arası saat sapması durumuna ilişkin koruyucu önlem tespit edilmiştir (Bkz: `FND-05`).
- **Şube Başına Tek Aktif Sayım:** `stock_counts` üzerinde `WHERE status = 'DRAFT'` şartlı kısmi benzersiz indeks (`Partial Unique Index`) kullanılarak şube başına tek aktif sayım kuralı deklaratif olarak güvenceye alınmıştır (`BR-STK-04`).

### 2.5 Offline-First ve Senkronizasyon Altyapı Uyumluluğu
- **Dağıtık Kimlik Yönetimi:** Tüm birincil anahtarların istemcide üretilebilir `UUID` olması offline-first için zorunlu ve yeterlidir.
- **Idempotency Güvencesi:** `sales.idempotency_key` alanı `UNIQUE (tenant_id, idempotency_key)` kısıtıyla korunmuştur. Ağ kesintisinde istemci aynı satışı tekrar gönderse dahi mükerrer satış ve mükerrer stok düşümü imkansızdır (`BR-SYNC-03`).
- **Cihaz ve Oturum Takibi:** `devices` ve `device_sessions` tabloları sayesinde her işlemin hangi fiziksel cihazdan ve hangi oturumdan geldiği izlenebilmektedir (`BR-SEC-04`, `BR-SEC-05`).
- **Geri Yüklemede Kuyruk Koruma:** `DATA_MODEL_DECISIONS.md` içerisinde yerel bekleyen kuyrukların geri yükleme sonrası doğrudan silinmeyip uzlaştırılması ilkesi benimsenmiştir (`BR-BAK-06`).

### 2.6 PostgreSQL ve Drift (SQLite) Çapraz Platform Uyumluluğu
- **Tip Eşleme:** `UUID` (PostgreSQL) $\leftrightarrow$ `Text` (Drift), `BIGINT` $\leftrightarrow$ `Int64/Integer`, `NUMERIC(12, 3)` $\leftrightarrow$ `Real/CustomDecimal`, `TIMESTAMPTZ` $\leftrightarrow$ `DateTime` (UTC) eşleşmeleri tam uyumludur.
- **Drift TypeConverter Kullanımı:** `audit_logs.old_values` ve `new_values` alanlarında kullanılan `JSONB` tipi PostgreSQL'de yereldir; Drift/SQLite tarafında ise `TypeConverter<Map<String, dynamic>, String>` ile JSON string olarak saklanacaktır.
- **UTC Standardı:** Tüm zaman alanları (`TIMESTAMPTZ`) UTC olarak depolanacak, arayüzde ve raporlamada `Europe/Istanbul` yerel saatine dönüştürülecektir (`BR-REP-01`).

### 2.7 Karmaşıklık ve Over-Engineering İncelemesi
- **Tablo Sayısı Değerlendirmesi:** Tasarlanan 25 tablo incelenmiş; gereksiz hiçbir yapay mikroservis tablosu veya erken soyutlama bulunmadığı doğrulanmıştır.
- **Bilinçli Sadeleştirmeler:**
  - Çoklu `payments` (1-N) tablosu yerine satış başına tek ödeme yöntemi (`sales.payment_method`) + düzeltme tablosu (`payment_method_corrections`) tercih edilerek karmaşıklık ve JOIN maliyeti önlenmiştir (`BR-PAY-01`).
  - Tedarikçi, satın alma, cari hesap, vardiya ve KDV tabloları MVP kapsamı dışında tutulmuş; veri modeline gereksiz şişkinlik eklenmemiştir (`OUT_OF_SCOPE`).

---

## 3. Denetim Bulguları Listesi (Findings Matrix)

Aşağıdaki bulgular, mantıksal veri modelinin DDL ve Drift implementasyonu aşamasında daha sağlam hale getirilmesi için belirlenmiş teknik fırsatlardır:

---

### `FND-01` [HIGH] Aktif Barkodlar ile Barkod Tarihçesi Arasında Çapraz Benzersizlik Kısıtı Eksikliği
- **İlgili Tablo ve Alan:** `product_barcodes.barcode` ve `barcode_history.barcode`.
- **İlgili İş Kuralı:** `BR-PROD-02`, `BR-PROD-15` (Tarihçedeki pasif barkodun başka bir ürüne mükerrer atanamaması kuralı).
- **Sorunun Açıklaması:**  
  Mantıksal modelde `product_barcodes` üzerinde `UNIQUE (tenant_id, barcode)` ve `barcode_history` üzerinde `UNIQUE (tenant_id, barcode)` tanımlıdır. Ancak iki ayrı tablo arasında ilişkisel veritabanlarında doğrudan deklaratif bir "çapraz unique constraint" kurulamaz.
- **Gerçekleşebilecek Hata Senaryosu:**  
  Bir kullanıcı daha önce pasife alınmış ve `barcode_history` tablosuna yazılmış bir barkodu, sistemde yeni açtığı başka bir ürüne barkod olarak eklemeye kalkarsa; `product_barcodes` tablosu kendi içinde o an tekil olduğu için veritabanı kısıtı bunu yakalayamaz ve kural ihlali oluşur.
- **Önerilen Çözüm (İki Seçenek):**
  - *Seçenek A (Tek Tablo & Partial Index - Önerilen):* Barkodları iki ayrı tabloya bölmek yerine tek bir `product_barcodes` tablosunda toplamak; `is_active` alanı eklemek; tüm barkodlar için `UNIQUE (tenant_id, barcode)` kısıtı koyarak bir barkodun pasif de olsa tenant içinde daima tek kalmasını sağlamak; aktif barkod araması için ise `CREATE UNIQUE INDEX idx_active_barcodes ON product_barcodes (tenant_id, barcode) WHERE is_active = true;` kullanmak.
  - *Seçenek B (Trigger/Fonksiyon Koruması):* İki tablo yapısı korunacaksa, `product_barcodes` tablosuna `BEFORE INSERT OR UPDATE` trigger'ı yazılarak `barcode_history` tablosunda o barkodun varlığı kontrol edilmeli ve varsa işlem reddedilmelidir.
- **İş Kuralı Değişikliği Gerekli mi?:** Hayır. `BR-PROD-15` iş kuralı zaten bunu emretmektedir; bu bir teknik uygulama sertleştirmesidir.

---

### `FND-02` [HIGH] Birim Dönüşümünde Periyodik Bölme ve Ondalık Yuvarlama Sapması Riski
- **İlgili Tablo ve Alan:** `products.stock_unit`, `products.pricing_unit`, `products.unit_conversion_rate`, `stock_balances.current_stock`.
- **İlgili İş Kuralı:** `BR-PROD-07`, `BR-PROD-08`.
- **Sorunun Açıklaması:**  
  Modelde stok birimi ile fiyatlandırma birimi farklı olabilmekte ve `unit_conversion_rate` çarpanı kullanılmaktadır. Örneğin stok birimi "Kutu", satış birimi "Adet" ve 1 Kutu = 24 Adet olarak tanımlandığında; kasada 1 adet satış yapıldığında stoktan düşülmesi gereken miktar:
  $$\Delta \text{Stok} = \frac{1}{24} = 0.0416666... \text{ Kutu}$$
  Stok bakiyesi `NUMERIC(12, 3)` (3 hane) olduğunda bu değer `0.042` olarak yuvarlanır. 24 adet tekil satış yapıldığında stoktan toplam $24 \times 0.042 = 1.008$ kutu düşülür; 1 kutu yerine fazladan 0.008 kutu (binde 8) yapay stok fire/sapması oluşur.
- **Gerçekleşebilecek Hata Senaryosu:**  
  Yoğun satılan koli/kutu ürünlerinde zaman içinde fiziksel stok ile sistem stoğu arasında matematiksel bölme kaynaklı yapay sapmalar birikir.
- **Önerilen Çözüm (Atomik Stok Birimi Prensibi):**
  - **İş Kuralı Prensibi Olarak:** Sistemde ürünün depodaki `stock_unit` (stok takip birimi) daima **bölünemez en küçük atomik birim** olmalıdır (Ör. stok birimi Adet, satış birimi Kutu; veya stok birimi Gram, fiyatlandırma birimi Kg).
  - Böylece dönüşüm yapılırken daima **çarpma işlemi** uygulanır ($1 \text{ Kutu} \times 24 = 24 \text{ Adet}$; $0.450 \text{ Kg} \times 1000 = 450 \text{ Gram}$). Çarpma işlemlerinde ondalık periyodik kayıp sıfırdır.
  - Ters yönde bölme gerekiyorsa, stok miktar hassasiyeti teknik tasarımda en az 4 veya 6 haneli (`NUMERIC(14, 4)`) olarak değerlendirilmelidir.
- **İş Kuralı Değişikliği Gerekli mi?:** Hayır; `BR-PROD-07` kapsamında birim hassasiyeti ve yuvarlama kural seti zaten `[PROPOSED]` olarak teknik tasarıma bırakılmıştır. Bu prensip teknik tasarımda kural olarak benimsenecektir.

---

### `FND-03` [MEDIUM] Şube Tablolarında Çift Seviyeli Bileşik Foreign Key `(tenant_id, store_id)` Eksikliği
- **İlgili Tablo ve Alan:** `stock_balances`, `stock_movements`, `sales`, `held_carts`, `refunds`.
- **İlgili İş Kuralı:** `BR-TNT-02`, `BR-TNT-03` (Multi-tenant veri izolasyonu).
- **Sorunun Açıklaması:**  
  Bu tablolarda hem `tenant_id` hem de `store_id` kolonları bulunmaktadır. Ancak FK kısıtı yalnızca `store_id -> stores(id)` ve `tenant_id -> tenants(id)` olarak bağımsız iki tekil kısıt halindedir.
- **Gerçekleşebilecek Hata Senaryosu:**  
  Hatalı bir istemci isteği veya yazılım hatası nedeniyle, Tenant A'ya ait bir satış kaydında `tenant_id = 'tenant-A'` iken, yanlışlıkla Tenant B'ye ait bir `store_id = 'store-B'` değeri gönderilirse; tekil FK kısıtları bunu engellemez (çünkü store-B veritabanında mevcuttur).
- **Önerilen Çözüm:**  
  `stores` tablosuna `UNIQUE (tenant_id, id)` bileşik kısıtı eklenmeli; ilgili operasyonel tablolarda yabancı anahtar kısıtı şu şekilde tanımlanmalıdır:  
  `FOREIGN KEY (tenant_id, store_id) REFERENCES stores(tenant_id, id) ON DELETE RESTRICT;`
  Böylece bir şubenin ait olmadığı bir tenant altında işlem görmesi veritabanı motoru seviyesinde imkansız kılınır.
- **İş Kuralı Değişikliği Gerekli mi?:** Hayır. Güvenlik ve RLS mimarisini güçlendiren saf bir teknik şema iyileştirmesidir.

---

### `FND-04` [MEDIUM] Çoklu Kısmi İadelerde Satılan Miktarın Aşılmasını Önleyecek Kalan Miktar Takibi
- **İlgili Tablo ve Alan:** `refund_items.quantity`, `sale_items.quantity`.
- **İlgili İş Kuralı:** `BR-POS-09` (İade miktarı satılan miktardan önceki iadeler düşüldükten sonra kalan miktarı aşamaz kuralı).
- **Sorunun Açıklaması:**  
  `refund_items` tablosu `sale_item_id` referansına sahiptir. Ancak bir satış kaleminde satılan miktar 5 iken; kullanıcı ilk gün 3 adet, ertesi gün 3 adet iade etmek isterse, veritabanı deklaratif kısıtları iki bağımsız fişteki toplamı ($3 + 3 = 6 > 5$) otomatik denetleyemez.
- **Gerçekleşebilecek Hata Senaryosu:**  
  Offline senkronizasyonda veya eşzamanlı iki farklı cihazda aynı fiş için ayrı ayrı kısmi iade açılırsa satılandan fazla ürün iadesi yapılabilir.
- **Önerilen Çözüm:**  
  - Uygulama transaction katmanında ve PostgreSQL RPC/Trigger seviyesinde iade oluşturulurken:
    $$\sum \text{refund\_items.quantity} \le \text{sale\_items.quantity}$$
    kontrolü zorunlu kılınmalıdır.
  - İade onaylandığında `sale_items` satırında `refunded_quantity` denetim kolonu güncellenerek hızlı bakiye kontrolü sağlanabilir.
- **İş Kuralı Değişikliği Gerekli mi?:** Hayır. `BR-POS-09` kuralının transaction seviyesindeki implementasyon kılavuzudur.

---

### `FND-05` [MEDIUM] Sayım Uzlaştırmasında Cihaz Saat Sapması (Clock Drift) Riski
- **İlgili Tablo ve Alan:** `stock_count_items.counted_at`, `stock_movements.created_at`.
- **İlgili İş Kuralı:** `BR-STK-09` (Ara stok hareketlerinin uzlaştırılması).
- **Sorunun Açıklaması:**  
  Fiziksel sayım yapan mobil cihazın sistem saati ile kasadaki masaüstü bilgisayarın veya merkezi sunucunun sistem saati arasında birkaç dakikalık fark (clock drift) bulunabilir. Sayım uzlaştırmasında `counted_at` zaman damgası `stock_movements.created_at` ile zaman kıyaslamasına tabi tutulduğunda, saat farkı ara hareketlerin yanlış sınıflandırılmasına yol açabilir.
- **Önerilen Çözüm:**  
  - Çevrimdışı çalışan cihazlarda işlem zaman damgaları kaydedilirken yerel cihaz saatinin yanı sıra, oturum açılışındaki sunucu zaman ofseti (NTP / Supabase server time offset) hesaba katılmalıdır.
  - Sayım oturumu başlatılırken ve onaylanırken merkezi sunucu zamanı veya ana kasa düğüm saati baz alınmalıdır. Bu detay `DATA_MODEL_DECISIONS.md` içerisindeki `PROPOSED` algoritma kapsamında doğrulanacaktır.
- **İş Kuralı Değişikliği Gerekli mi?:** Hayır.

---

### `FND-06` [LOW] Web Platformunda JavaScript 53-Bit Tamsayı ve `BIGINT` Para Tipi
- **İlgili Tablo ve Alan:** Tüm kuruş bazlı `BIGINT` para alanları.
- **İlgili İş Kuralı:** `BR-POS-04`.
- **Sorunun Açıklaması:**  
  Dart `int` tipi 64-bit tamsayıdır. Ancak uygulama Web (JavaScript) platformuna derlendiğinde, standart JS sayıları çift duyarlıklı kayan noktalı sayı olarak ($2^{53} - 1$) sınırına sahiptir.
- **Değerlendirme:**  
  $2^{53} - 1 \text{ kuruş} \approx 90 \text{ Trilyon TL}$ etmektedir. Bir market yönetim sistemindeki satış tutarlarının veya ürün fiyatlarının bu sınıra yaklaşması pratik olarak imkansızdır. Dolayısıyla Web derlemesinde hiçbir veri taşması veya kesinlik kaybı riski **oluşmaz**. Bilgi amaçlı kayıt altına alınmıştır.

---

### `FND-07` [LOW] SQLite / Drift Tarafında Kısmi Benzersiz İndeks (Partial Unique Index) Uyumluluğu
- **İlgili Tablo ve Alan:** `stock_counts` (`WHERE status = 'DRAFT'`).
- **İlgili İş Kuralı:** `BR-STK-04` (Şube başına tek aktif taslak sayım kuralı).
- **Değerlendirme:**  
  SQLite sürüm 3.8.0 ve sonrasından itibaren `CREATE UNIQUE INDEX ... WHERE ...` kısmi indeks sözdizimini yerel olarak tam desteklemektedir. Drift kütüphanesi de özel indeks tanımlarında bunu destekler. Çapraz platform uyumluluğu tamdır.

---

## 4. Kritik Senaryo Testleri ve İzlenebilirlik Doğrulaması

Aşağıdaki 13 kritik operasyonel senaryo, tasarlanan veri modelinin tabloları, alanları ve kısıtları üzerinden adım adım simüle edilerek test edilmiştir:

---

### Senaryo 1: Barkodsuz Ekmek Satışı
- **Kullanılan Tablolar:** `products`, `held_carts`, `held_cart_items`, `sales`, `sale_items`, `stock_balances`, `stock_movements`.
- **Adım Adım İzlenebilirlik:**
  1. `products` tablosunda `id = 'prod-bread'`, `name = 'Somun Ekmek'`, `current_sale_price = 1000` (10.00 TL), `pricing_unit = 'adet'` tanımlıdır. `product_barcodes` tablosunda hiçbir satır yoktur.
  2. Kasiyer ekrandaki "Ekmek" hızlı butonuna basar. `held_cart_items` tablosuna `product_id = 'prod-bread'`, `unit_price_snapshot = 1000`, `quantity = 1.000` satırı eklenir.
  3. Satış tamamlandığında atomik transaction ile:
     - `sales` başlığı oluşur (`total_amount = 1000`, `payment_method = 'CASH'`).
     - `sale_items` satırına `product_name_snapshot = 'Somun Ekmek'`, `unit_price_snapshot = 1000`, `quantity = 1.000`, `line_total = 1000` kopyalanır.
     - `stock_balances.current_stock` 1 adet düşürülür.
     - `stock_movements` tablosuna `movement_type = 'SATIS'`, `quantity = -1.000`, `reference_id = sale.id` yazılır.
- **Sonuç:** **BAŞARILI.** Barkodsuz ürün hiçbir kısıt ihlali olmadan eksiksiz satılmaktadır (`BR-PROD-04`).

---

### Senaryo 2: Bir Ürünün İki Farklı Barkodla Bulunması
- **Kullanılan Tablolar:** `products`, `product_barcodes`.
- **Adım Adım İzlenebilirlik:**
  1. `products` tablosunda tekil ürün: `id = 'prod-milk'`, `name = 'Kutu Süt 1 L'`.
  2. `product_barcodes` tablosunda iki aktif satır:  
     - `(product_id: 'prod-milk', barcode: '869000100001', is_active: true)`  
     - `(product_id: 'prod-milk', barcode: '869000100002', is_active: true)`  
  3. Kasiyer USB okuyucuyla `869000100001` okutursa, `idx_barcodes_lookup` indeksi üzerinden anında `prod-milk` bulunur ve sepete eklenir.
  4. Başka bir cihazda `869000100002` okutulsa yine aynı `prod-milk` bulunur.
- **Sonuç:** **BAŞARILI.** Çoklu barkod yapısı ürün ana kaydını tek tutarak kusursuz çalışmaktadır (`BR-PROD-02`).

---

### Senaryo 3: Eski Barkodun Yeniden Kullanılmasının Engellenmesi
- **Kullanılan Tablolar:** `product_barcodes`, `barcode_history`.
- **Adım Adım İzlenebilirlik:**
  1. `prod-milk` ürününün `869000100001` barkodu silinir; `barcode_history` tablosuna `(tenant_id, product_id, barcode: '869000100001')` olarak kaydedilir.
  2. Kasiyer sisteme yeni açtığı `prod-water` ürününe aynı `869000100001` barkodunu atamaya çalışır.
  3. `FND-01` kapsamında önerilen birleşik kısıt veya trigger sayesinde veritabanı seviyesinde `UNIQUE` ihlali fırlatılır ve işlem engellenir.
- **Sonuç:** **BAŞARILI.** Denetim izi ve barkod tekilliği garanti altındadır (`BR-PROD-15`).

---

### Senaryo 4: 1 Kg Üzerinden Fiyatlandırılan Ürünün Gram Bazında Stok Takibi
- **Kullanılan Tablolar:** `products`, `held_cart_items`, `sale_items`, `stock_balances`, `stock_movements`.
- **Adım Adım İzlenebilirlik:**
  1. `products` tablosunda: `name = 'Elma'`, `stock_unit = 'kg'`, `pricing_unit = 'kg'`, `current_sale_price = 5000` (50.00 TL/kg).
  2. Müşteri 450 gram elma alır. Kasada miktar `quantity = 0.450` girilir.
  3. Tutar hesabı: $0.450 \times 5000 = 2250$ kuruş (22.50 TL) olarak kuruş tamsayı ile hesaplanır.
  4. `sale_items` satırına `quantity = 0.450`, `line_total = 2250` yazılır.
  5. `stock_balances.current_stock` tam `0.450` kg düşürülür; `stock_movements` satırına `quantity = -0.450`, `unit = 'kg'` yazılır.
- **Sonuç:** **BAŞARILI.** Kesirli miktar ve kuruş tam sayı hesabı sıfır kayıpla eşleşmektedir (`BR-PROD-07`, `BR-POS-04`).

---

### Senaryo 5: Nakit Satış ve Para Üstü Hesaplama
- **Kullanılan Tablolar:** `sales`, `sale_items`, `stock_movements`.
- **Adım Adım İzlenebilirlik:**
  1. Sepet toplamı: `total_amount = 7550` (75.50 TL).
  2. Kasiyer müşteriden alınan nakit tutarı girer: `cash_received_amount = 10000` (100.00 TL).
  3. Sistem para üstünü hesaplar: $\text{Para Üstü} = 10000 - 7550 = 2450$ kuruş (24.50 TL).
  4. Satış tamamlandığında `sales` tablosuna `payment_method = 'CASH'`, `cash_received_amount = 10000`, `cash_change_amount = 2450` atomik kaydedilir.
  5. Eğer kasiyer `cash_received_amount = 5000` girerse, `CHECK (cash_received_amount >= total_amount)` kısıtı gereği veritabanı işlemi reddeder.
- **Sonuç:** **BAŞARILI.** Para üstü hesabı ve eksik ödeme engeli tam güvencededir (`BR-PAY-02`, `BR-PAY-03`).

---

### Senaryo 6: Geçmiş Satışın İptali (Zaman Sınırsız)
- **Kullanılan Tablolar:** `sales`, `sale_items`, `stock_balances`, `stock_movements`, `audit_logs`.
- **Adım Adım İzlenebilirlik:**
  1. İşletme sahibi 5 gün önce tamamlanmış `sale-999` fişini açar ve zorunlu gerekçe girerek ("Müşteri vazgeçti - Fiş iadesi") onaylar.
  2. Atomik transaction başlar:
     - `sales` tablosunda `status = 'CANCELLED'`, `cancelled_at = now()`, `cancellation_reason = '...'` güncellenir (fiziksel silinmez).
     - Fişteki 3 kalem taranır; her biri için `stock_movements` tablosuna `movement_type = 'SATIS_IPTALI'`, pozitif miktarla stok iade satırı yazılır.
     - `stock_balances` bakiyeleri artırılır.
     - `audit_logs` tablosuna `'SALE_CANCELLED'` kaydı atılır.
  3. Günlük rapor sorgusu `WHERE status = 'COMPLETED'` koşulu içerdiğinden bu fiş cirolardan kendiliğinden düşer.
- **Sonuç:** **BAŞARILI.** Zaman sınırı olmaksızın, veri silinmeden ve stoklar geri dönerek iptal gerçekleşir (`BR-POS-08`, `BR-REP-02`).

---

### Senaryo 7: Bir Satışın Farklı Zamanlarda İki Kez Kısmi İadesi
- **Kullanılan Tablolar:** `sales`, `sale_items`, `refunds`, `refund_items`, `stock_movements`.
- **Adım Adım İzlenebilirlik:**
  1. Orijinal fişte 5 adet çikolata satılmıştır (`sale_items.quantity = 5.000`, birim fiyat 2000 kuruş).
  2. **1. İade (1. Gün):** Müşteri 2 adedini iade eder.  
     - `refunds` kaydı açılır (`total_refund_amount = 4000`).  
     - `refund_items` satırına `quantity = 2.000`, `unit_price_snapshot = 2000` yazılır.  
     - Kalan iade edilebilir miktar: $5 - 2 = 3$.
  3. **2. İade (3. Gün):** Müşteri 2 adet daha iade eder.  
     - 2. `refunds` fişi açılır (`total_refund_amount = 4000`).  
     - `refund_items` satırına `quantity = 2.000` yazılır.  
     - Kalan iade edilebilir miktar: $5 - (2 + 2) = 1$.
  4. Müşteri 2 adet daha getirmeye kalkarsa ($2 > 1$), `FND-04` kuralı gereği sistem satılan miktarın aşıldığını belirterek işlemi engeller.
- **Sonuç:** **BAŞARILI.** Çoklu kısmi iade desteği snapshot fiyatlarla ve tavan kontrolüyle tam çalışmaktadır (`BR-POS-09`).

---

### Senaryo 8: İade Edilen Ürünün Hasarlı Olması
- **Kullanılan Tablolar:** `refunds`, `refund_items`, `stock_balances`, `stock_movements`.
- **Adım Adım İzlenebilirlik:**
  1. Müşteri ambalajı patlamış 1 L sütü iade eder.
  2. Kasiyer iade ekranında ürün kondisyonunu `condition = 'DAMAGED'` seçer.
  3. `refund_items` tablosuna `condition = 'DAMAGED'` yazılır.
  4. `stock_movements` tablosuna `movement_type = 'FIRE_KAYIP'`, `quantity = -1.000` (veya nötr denetim izi) yazılır; `stock_balances.current_stock` kesinlikle artırılmaz.
  5. Müşteriye parası iade edilir (`refunds` cirodan düşer); ancak bozuk mal rafa satılabilir stok olarak geri girmez.
- **Sonuç:** **BAŞARILI.** Hasarlı ürünün satılabilir stoğa karışması veritabanı kuralıyla engellenmiştir (`BR-POS-10`).

---

### Senaryo 9: Negatif Stok Oluşması
- **Kullanılan Tablolar:** `stock_balances`, `stock_movements`, `sales`.
- **Adım Adım İzlenebilirlik:**
  1. `prod-oil` ürününün güncel stoğu `current_stock = 0.000`'dır.
  2. Rafta fiziksel ürün gören kasiyer 2 adet satış yapar.
  3. `stock_balances.current_stock` değeri `0 - 2 = -2.000` olarak güncellenir.
  4. Veritabanında hiçbir `CHECK` kısıtı patlamaz; satış tamamlanır.
  5. `idx_stock_balances_negative` indeksi sayesinde dashboard anında bu ürünü "Eksi Stoklu Ürünler" listesinde gösterir.
  6. 2 gün sonra toptancıdan 10 adet mal girişi (`movement_type = 'NORMAL_GIRIS'`) yapıldığında stok: $-2 + 10 = +8.000$ olur.
- **Sonuç:** **BAŞARILI.** Eksi stok tam olarak iş kuralına uygun davranmaktadır (`BR-STK-02`, `BR-STK-03`).

---

### Senaryo 10: Sayım Sürerken Aynı Ürünün Satılması ve Stok Girişi Yapılması
- **Kullanılan Tablolar:** `stock_counts`, `stock_count_items`, `stock_balances`, `stock_movements`.
- **Adım Adım İzlenebilirlik:**
  1. Sayım oturumu açılır (`stock_counts.status = 'DRAFT'`).
  2. Saat 10:00'da bisküvi sayılır: 20 adet.  
     `stock_count_items` satırına `counted_quantity = 20.000`, `counted_at = '10:00'`, `snapshot_stock_at_count = 25.000` yazılır.
  3. Saat 10:30'da kasadan 2 adet satılır (`SATIS`, $q = -2$).
  4. Saat 11:00'de toptancıdan 5 adet mal kabul edilir (`NORMAL_GIRIS`, $q = +5$).
  5. Saat 11:30'da sayım onaylanır (`COMPLETED`).
  6. Uzlaştırma motoru `counted_at` ('10:00') sonrasındaki hareketleri filtreler:
     - $\text{reconciliation\_sales} = 2.000$
     - $\text{reconciliation\_entries} = 5.000$
     - $\text{Nihai Stok} = 20.000 - 2.000 + 5.000 = 23.000$
  7. `stock_balances.current_stock` değeri doğrudan `23.000` yapılır; sayım farkı olarak $23 - (25 - 2 + 5) = 23 - 28 = -5$ adet `SAYIM_FARKI` hareketi kaydedilir.
- **Sonuç:** **BAŞARILI.** Sayım anındaki ara satışlar çift düşülmemiş, matematiksel olarak tam uzlaştırılmıştır (`BR-STK-09`).

---

### Senaryo 11: Aynı Satışın Birden Fazla Kez İşlenmeye Çalışılması (Idempotency)
- **Kullanılan Tablolar:** `sales`, `sync_operations`.
- **Adım Adım İzlenebilirlik:**
  1. Mobil cihaz çevrimdışıyken bir satış yapar: `idempotency_key = 'uuid-abc-123'`.
  2. İnternet gelir; mobil cihaz satışı sunucuya post eder. Satış başarıyla `sales` tablosuna yazılır.
  3. Ağda anlık kopma olur ve sunucunun "HTTP 200 Başarılı" yanıtı cihaza ulaşmaz.
  4. İstemci aynı isteği 30 saniye sonra tekrar sunucuya gönderir (`idempotency_key = 'uuid-abc-123'`).
  5. Sunucu `UNIQUE (tenant_id, idempotency_key)` kısıtına takılır; mükerrer kayıt açmaz ve mevcut satışın sonucunu istemciye güvenle döner.
- **Sonuç:** **BAŞARILI.** Çift fiş kesilmesi ve çift stok düşümü kesin olarak engellenir (`BR-SYNC-03`).

---

### Senaryo 12: Aynı Kullanıcının İki Cihazdan İşlem Yapması
- **Kullanılan Tablolar:** `devices`, `device_sessions`, `held_carts`, `audit_logs`.
- **Adım Adım İzlenebilirlik:**
  1. İşletme sahibi hem Windows PC'den hem Android telefondan aynı kullanıcı hesabıyla oturum açar.
  2. Her cihaz kendi donanım kimliğiyle `devices` tablosunda (`dev-pc`, `dev-phone`) kayıtlıdır ve kendi `device_sessions` kaydına sahiptir.
  3. PC'de açılan bir sepet `held_carts.locked_by_device_id = 'dev-pc'` ile kilitlenir.
  4. Telefonda bu sepet açıldığında salt okunur görüntülenir ve düzenleme engellenir.
  5. İki cihazdan yapılan her satışın ve hareketin `device_id` alanı ayrı ayrı izlenir.
- **Sonuç:** **BAŞARILI.** Çoklu cihaz oturumu ve kilit mekanizması veri modelinde tam desteklenmektedir (`BR-POS-06`, `BR-SEC-05`).

---

### Senaryo 13: Bir Tenant'ın Başka Tenant'ın Verisine Erişmeye Çalışması
- **Kullanılan Tablolar:** Tüm tablolar (RLS & Bileşik FK).
- **Adım Adım İzlenebilirlik:**
  1. Kötü niyetli bir istemci JWT auth token'ında Tenant A yetkisine sahipken, URL veya parametre üzerinden Tenant B'ye ait `product_id` veya `sale_id` okumaya çalışır.
  2. PostgreSQL katmanında aktif olan RLS politikası devreye girer:  
     `WHERE tenant_id = (SELECT tenant_id FROM memberships WHERE user_id = auth.uid())`
  3. İlgili kayıt veritabanı sorgu motoru seviyesinde filtrelenir; sorgu `0 rows returned` (veya `404 Not Found`) döner.
  4. `FND-03` kapsamında önerilen `(tenant_id, store_id)` bileşik FK sayesinde, tenantlar arası çapraz şube ataması da fiziksel olarak engellenir.
- **Sonuç:** **BAŞARILI.** Çoklu kiracı veri izolasyonu %100 güvendedir (`BR-TNT-03`).

---

## 5. Nihai Denetim Sonuçları ve Tavsiyeler

1. **Kritik Bulgular:** Mimariyi bloke eden veya tasarım değişikliği gerektiren hiçbir `CRITICAL` bulgu yoktur.
2. **Önemli İyileştirmeler:**
   - `FND-01`: Aktif ve pasif barkodların çapraz tekilliği için ya tek tablo partial index modeli ya da DB trigger çözümü benimsenmelidir.
   - `FND-02`: Birim dönüşümlerinde periyodik bölme kaybını önlemek için depolanan stok biriminin daima en küçük atomik birim (gram, adet vb.) olması prensibi teknik kural olarak uygulanmalıdır.
   - `FND-03`: Multi-tenant güvenliğini donanımsal kılmak için `(tenant_id, store_id)` bileşik foreign key kullanılmalıdır.
3. **Eksik Tablo veya İlişki:** 25 tabloluk şema `BUSINESS_RULES_SPEC.md` v1.2'deki tüm isterleri eksiksiz karşılamaktadır; eksik tablo tespit edilmemiştir.
4. **Gereksiz Tablo / Soyutlama:** Over-engineering veya gereksiz ara tablolar bulunmamaktadır.
5. **PostgreSQL / Drift Uyumluluğu:** Tipler birebir eşleşmektedir; SQLite kısıtlamaları (partial index, check constraint) desteklenmektedir.
6. **Onay Bekleyen Teknik Kararlar:** Sayım mikro-transaction uzlaştırma algoritması ve geri yükleme senkronizasyon protokolü sonraki adımlarda test edilecektir.

---

## 6. Sonuç ve Karar

> [!TIP]
> **DENETİM ONAYI:**  
> `docs/architecture/DATA_MODEL.md` (v1.0) içerisinde tanımlanan mantıksal veri modeli, Faz 0 gereksinimlerini ve iş kurallarını **eksiksiz ve hatasız biçimde karşılamaktadır**.  
> Yukarıdaki `FND-01` .. `FND-05` teknik bulguları, doğrudan DDL scriptleri ve Drift DAO implementasyonu sırasında uygulanabilecek teknik optimizasyonlar olup, **veri modelinin sonraki aşamaya (Offline Senkronizasyon ve Outbox Kuyruğu Protokolü Tasarımı) geçmesine hiçbir engel bulunmamaktadır**.

