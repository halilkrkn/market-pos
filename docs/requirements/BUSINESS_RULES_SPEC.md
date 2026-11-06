# Market Management System (MMS) — İş Kuralları Şartnamesi (Business Rules Specification)

**Doküman Kodu:** `BUSINESS_RULES_SPEC.md`  
**Sürüm:** 1.2 (İş Kuralları Tutarlılık ve Hassasiyet Revizyonu)  
**Tarih:** 31 Ekim 2026  
**Durum:** Faz 0 — İş Kuralları Şartnamesi (Kodlama Yok)  
**Ana Referans Doküman:** `MARKET_POS_AI_STUDIO_BUILD_PLANI.md` (v1.2.2)  
**Girdi Dokümanı:** `docs/requirements/PHASE_0_BUSINESS_DISCOVERY.md` (v1.3)  
**Teknik Proje / Klasör Adı:** `market-pos`  
**Ürün Tanımı:** Market Management System (MMS) — Profesyonel Market Yönetim SaaS Uygulaması  

---

## Değişiklik Geçmişi (Document Revision History)

| Sürüm | Tarih | Değişiklik Türü | Açıklama |
|---|---|---|---|
| **v1.0** | 31 Ekim 2026 | İlk Yayın | Faz 0 keşif çıktılarının 10 modül altında ilk şartname haline getirilmesi. |
| **v1.1** | 31 Ekim 2026 | Kapsamlı Revizyon | İptal ve kısmi iade ayrıştırıldı; 9 stok hareket türü netleştirildi; fiyat/maliyet geçmişi eklendi; sepet fiyat snapshot'ı ve manuel müdahale tanımlandı; hiyerarşik kategori ve barkod yaşam döngüsü eklendi; rapor takvim günü ve birim gruplama eklendi; XLSX katalog dışa aktarımı tanımlandı; izlenebilirlik matrisi oluşturuldu. |
| **v1.2** | 31 Ekim 2026 | Tutarlılık ve Hassasiyet Revizyonu | Satış iptalindeki yapay zaman kısıtı kaldırıldı (herhangi bir zamanda gerekçe ve onayla iptal); ekmek hızlı tuşunun `product_barcodes` ilişkisizliğiyle modellendiği ve sepet içi manuel fiyat müdahalesiyle (`BR-POS-11`) tam uyumu netleştirildi; `BR-PROD-02` farklı paket miktarlarının ayrı ürün kaydı olması kuralına bağlandı; bilinmeyen barkod kayıt akışına birim ve kategori zorunluluğu eklendi (`BR-PROD-01` ile tam uyum); sayım uzlaştırmasında zaman damgasının ürün/kalem bazında ele alınması ve kesin algoritmanın PROPOSED olarak işaretlenmesi; MVP kullanıcısı için "kasiyer" yerine "işletme sahibi" terminolojisi uygulandı; hasarlı iade ürünlerinin satılabilir stoktan ayrı tutulması ve `FIRE_KAYIP` etkisi netleştirildi; `stock_movements` gerekçe zorunluluk matrisi tanımlandı; `barcode_history` tekillik ve yeniden kullanılamama kuralı açıklandı; ödeme yöntemi düzeltmesinin nakit/kart raporlarına etkisi belirlendi; haftalık raporların Pazartesi başlangıcı tanımlandı; iadelerin orijinal ödeme yöntemi cirosundan düşülmesi kurala bağlandı; geri yükleme sırasında bekleyen yerel kuyrukların silinmemesi ilkesi pekiştirildi; izlenebilirlik matrisi güncellendi. |

---

## 1. Belgenin Amacı ve Kapsamı

Bu şartname; **Market Management System (MMS)** projesinde uygulama kodlaması (Faz 1+) öncesinde geliştiricilerin, yazılım mimarlarının ve yapay zekâ asistanlarının başvuracağı **kesin ve bağlayıcı iş kuralları dizinidir**.

Bu şartnamede yer alan her kural tekil bir kimlik koduyla (`BR-...`) tanımlanmış; kapsamı, sınır koşulları, veri etkileri, istisnaları ve kabul kriterleri ayrıntılı olarak kayıt altına alınmıştır. Şartnamede yer almayan veya şartnameyle çelişen hiçbir iş mantığı uygulama koduna yansıtılamaz.

### 1.1 Kural Kodlama ve Durum Standardı

- **Kural Kodu Biçimi:** `BR-[MODÜL]-[SIRA_NO]`
- **Kural Durumları:**
  - **`[CONFIRMED]`**: Kesinleşmiş ve onaylanmış iş kuralı. Uygulama kodunda birebir hayata geçirilecektir.
  - **`[PROPOSED]`**: Teknik tasarımla, algoritmik modellemeyle veya performans testleriyle doğrulanacak teknik öneri veya parametre.
  - **`[OUT_OF_SCOPE]`**: İlk pilot sürümün (MVP) kesinlikle dışında tutulan özellik/iş kuralı.

### 1.2 Terminoloji ve Kullanıcı Rolü Standardı
Pilot aşamasında sistem tek bir işletme (Tenant) ve tek bir mağaza (Store) üzerinde çalışacak olup, sistemin aktif kullanıcısı **"İşletme Sahibi"**dir. Dokümanda kasa ve yönetim ekranlarını kullanan aktör olarak "işletme sahibi" ifadesi esas alınmıştır. Harici banka POS cihazına kart takan veya temas ettiren kişi için bağlama göre "müşteri / işletme sahibi" ayrımı gözetilmiştir.

---

## 2. Modül 1: Ürün ve Kategori Yönetimi (BR-PROD)

### `BR-PROD-01` [CONFIRMED] Ürün Tanımlama ve Zorunlu Alanlar
- **Açıklama:** Yeni bir ürün oluşturulurken Ürün Adı, Satış Fiyatı, Birim ve Kategori alanlarının doldurulması zorunludur. Marka, Açıklama, Alış Maliyeti ve Kritik Stok eşiği alanları isteğe bağlıdır.
- **Sınır ve Kısıt:** Satış fiyatı sıfırdan büyük olmalıdır ($> 0$). Alış maliyeti girilmişse sıfır veya sıfırdan büyük ($\ge 0$) olmalıdır; satış fiyatından yüksek olduğunda sistem uyarı verir ("Maliyet satış fiyatından yüksektir - Zararına satış"), ancak işletme sahibinin onay vermesi halinde işlem engellenmez.
- **Hata Durumu:** Zorunlu alanlardan biri eksikse ürün kaydedilemez ve işletme sahibine ilgili alan özelinde hata mesajı gösterilir.

### `BR-PROD-02` [CONFIRMED] Çoklu Barkod ve Farklı Paket Miktarları Kuralı
- **Açıklama:** Bir ürüne birden fazla aktif barkod bağlanabilir (ör. üreticinin ambalaj/grafik değişikliği, geçici promosyonlu ambalaj barkodu veya ithalatçı etiket barkodu).
- **Farklı Ticari Miktarlar Ayrı Üründür:** Tekli kutu kola ile 6'lı paket veya 24'lü koli gibi farklı ticari satış miktarları ve birimleri kesinlikle aynı ürünün alternatif barkodu olarak tanımlanamaz. Farklı paket miktarları sistemde bağımsız birer ürün kaydı (`products`) olarak açılmalıdır. Bu ürünler arasındaki stok/fiyat ilişkisi gerekirse kutu/paket dönüşüm çarpanı (`BR-PROD-08`) ile kurulur.
- **Sınır ve Kısıt:** Bir barkod aynı tenant altında yalnızca tek bir ürüne atanabilir. Aynı barkodun ikinci bir ürüne mükerrer verilmesi engellenir.
- **Hata Durumu:** Girilen barkod sistemde başka bir aktif veya pasif ürüne aitse "Bu barkod zaten [Ürün Adı] ürününe kayıtlıdır" hatası verilir.

### `BR-PROD-03` [CONFIRMED] Ürün Pasifleştirme (Soft Delete)
- **Açıklama:** Sistemde ürünler fiziksel olarak veritabanından silinmez; pasife alınır (`is_active = false`).
- **Gerekçe:** Geçmiş satış fişlerinin, kâr-zarar raporlarının ve stok hareketleri denetim izlerinin veri bütünlüğünü korumak.
- **Kabul Kriteri:** Pasife alınan ürün satış ekranında barkodla veya isimle aranamaz, sepete eklenemez ve satılamaz. Ancak geçmiş satış raporlarında, fiş detaylarında ve stok hareket geçmişinde adı, birimi ve geçmiş verileri aynen görüntülenmeye devam eder.

### `BR-PROD-04` [CONFIRMED] Barkodsuz Ürün Satışı, Ekmek Hızlı Tuşu ve Fiyat Müdahalesi Uyumu
- **Açıklama:** Barkodu bulunmayan fırın ekmeği için satış ekranında özel bir "Ekmek Hızlı Satış Tuşu" yer alır.
- **İlişki Modellemesi:** Barkodsuz ürünler `products` tablosuna yapay bir nullable barkod kolonu eklenerek modellenmez. Ana mimarideki `product_barcodes` (1-N) ilişkisinde hiçbir aktif barkod kaydı bulunmayan ürünler "Barkodsuz Ürün" kabul edilir. Ekmek hızlı tuşu, tenant'ta ekmek için tanımlanmış `product_id` ile doğrudan ilişkilendirilir.
- **İş Akışı:**
  1. İşletme sahibi ekmek tuşuna her bastığında sepet satırındaki ekmek miktarı 1 artırılır.
  2. Birim fiyat, ekmek ürün kartında tanımlı güncel satış fiyatından otomatik alınır.
  3. Fiyat değişikliği kural olarak ürün yönetim ekranından yapılır; geçmiş satış kayıtları kendi snapshot fiyatlarını aynen korur.
- **Sepet İçi Fiyat Müdahalesi ile Uyum:** Ekmek satırı da genel sepet satırı fiyat müdahalesi kuralına (`BR-POS-11`) tabidir. İşletme sahibi dilerse sepet satırındaki ekmek birim fiyatını zorunlu gerekçe ve açık onayla değiştirebilir (ör. bayat ekmek indirimi veya ikram). Bu müdahale ana ürün kartındaki satış fiyatını kesinlikle değiştirmez; yalnızca o sepet ve fiş için geçerlidir.

### `BR-PROD-05` [CONFIRMED] Bulunamayan Barkod İş Akışı ve Zorunlu Alan Doğrulaması
- **Açıklama:** Kasada okutulan bir barkod yerel katalogda bulunamazsa sistem satışı durdurmaz; işletme sahibini kontrollü ürün kayıt akışına yönlendirir.
- **İş Akışı:**
  1. "Ürün Bulunamadı" modalı açılır ve okutulan barkod otomatik dolu gelir.
  2. Cihazda aktif internet bağlantısı varsa arka planda Open Food Facts sorgusu yapılır.
  3. İnternet yoksa veya API ürünü bulamazsa manuel ürün kayıt formu açılır.
  4. **`BR-PROD-01` ile Tam Uyum:** Ürünün **Ürün Adı**, **Satış Fiyatı**, **Birim** ve **Kategori** alanlarının tamamı eksiksiz ve geçerli biçimde doldurulup yerel veritabanına başarıyla kaydedilmeden ürün sepete kesinlikle eklenemez. Yalnızca ad ve fiyat girilerek yarım/eksik ürün oluşturulması engellenir.

### `BR-PROD-06` [CONFIRMED] Open Food Facts Öneri Mekanizması
- **Açıklama:** Open Food Facts verileri yalnızca kullanıcı onayına sunulan bir öneridir; kesin işletme verisi değildir.
- **Kural:** API'den gelen ürün adı, marka, kategori ve görsel öneri olarak arayüze doldurulur. Ancak Satış Fiyatı ve Başlangıç Stoğu asla API'den gelmez; işletme sahibi tarafından elle girilmek zorundadır. İşletme sahibi önerilen bilgileri onaylamadan önce dilediği gibi düzenleyebilir.

### `BR-PROD-07` [CONFIRMED] Ürün Birimleri ve Stok-Fiyat Birim Ayrımı
- **Açıklama:** Desteklenen ölçü birimleri: Adet, kg, g, L, ml, paket, kutu.
- **Kural:** Bir ürünün depodaki stok birimi ile reyondaki satış/fiyatlandırma birimi farklı olabilir (ör. stok birimi kg, satış fiyatı 100 g veya stok birimi Kutu, satış birimi Adet).
- **Hassasiyet ve Para Kuralı:** Tartılı ve hacimli ürünlerde kesirli miktar (ondalıklı sayı) desteklenir. Fiyat hesaplamalarında floating-point (`double`) aritmetiği kesinlikle kullanılmaz; kuruş bazlı tamsayı veya sabit kesinlikli tür kullanılır. Tanımsız veya boyutlar arası keyfi birim dönüşümleri kesinlikle engellenir.
- **`[PROPOSED]` Hassasiyet Parametreleri:** Miktar hassasiyeti (ör. tartıda 3 ondalık hane: 0.001 kg; fiyatta 2 ondalık hane: 0.01 TL) ve kesin yuvarlama fonksiyonu (Banker's rounding / Round Half Up) teknik tasarım aşamasında kodlanacaktır.

### `BR-PROD-08` [CONFIRMED] Kutu / Paket Dönüşüm Çarpanı ve Boyut Uyumsuzluğu
- **Açıklama:** Paket veya kutu dönüşüm çarpanı yalnızca gerçekten birim dönüşümü gerektiğinde ürün kartında tanımlanır; her ürün için zorunlu değildir.
- **Kural:** Örneğin 1 Kutu = 24 Adet gibi ürün bazlı birim çarpanı tanımlandığında, kutu ile mal kabul edilip adet olarak satış yapılabilir veya tam tersi uygulanabilir. Tanımlı dönüşüm oranı bulunmayan veya farklı fiziksel boyutlar arası (ör. L'den kg'a veya adet'ten metreye) geçersiz birim dönüşümleri kesinlikle engellenir.

### `BR-PROD-09` [CONFIRMED] Excel / CSV İçe Aktarma — Bütünsel Ön Doğrulama
- **Açıklama:** XLSX ve CSV formatındaki toplu ürün listeleri içeri aktarılabilir. Standart bir şablon sağlanır.
- **Doğrulama ve Hata Kuralı:** Dosyanın tamamı doğrulanmadan veritabanına tek bir kayıt dahi yazılmaz. Tek bir geçersiz satır tespit edilirse tüm içe aktarma işlemi durdurulur; kısmi/yarım kayıt kesinlikle bırakılmaz. Hatalar satır ve alan bazında kullanıcıya sunulur. İşletme sahibi hataları düzelttikten sonra dosyayı yeniden doğrulamaya gönderir.
- **Atomik Kayıt:** Doğrulama başarılı olduğunda tüm ürünler tek bir atomik veritabanı transaction'ı içinde kaydedilir.
- **`[PROPOSED]` Teknik Sınır:** İlk sürümde bellek ve işlem süresini korumak için tek seferde önerilen teknik üst sınır 5.000 satırdır.

### `BR-PROD-10` [CONFIRMED] Excel / CSV — Dosya İçi Mükerrer Barkod Engeli
- **Açıklama:** İçe aktarılan dosyanın kendi içinde aynı barkodun birden fazla satırda bulunması kesin bir doğrulama hatasıdır. Sistem işlemi başlatmaz ve "Dosya içinde mükerrer barkod tespit edildi: [Barkod] (Satır X ve Satır Y)" uyarısı verir.

### `BR-PROD-11` [CONFIRMED] Excel / CSV — Tenant Çakışması ve Kategori Eşleştirme
- **Açıklama:** Dosyadaki bir barkod tenant sisteminde zaten mevcutsa otomatik üzerine yazılmaz. Önizleme ekranında çakışan ürünler listelenir; işletme sahibi "Mevcut ürünü güncelle" veya "Atla" seçimini onaylar. Dosyadaki kategoriler sistemdeki kategorilerle eşleştirilir; yeni kategoriler yalnızca işletme sahibi onayıyla oluşturulur. Fiyat/maliyet güncellemeleri geçmişe "EXCEL_IMPORT" kaynağıyla kaydedilir. İçe aktarma sonunda kullanıcıya detaylı başarı/hata raporu sunulur.

### `BR-PROD-12` [CONFIRMED] Ürün Görselleri
- **Açıklama:** Ürün görseli eklemek isteğe bağlıdır; görsel olmaması ürünün kaydına, satışına veya stok hareketine hiçbir şekilde engel teşkil etmez.
- **Kural:** Görseller hem PC'den hem mobilden yüklenebilir. Cihaz çevrimdışıyken eklenen görseller kalıcı yükleme kuyruğuna alınır ve internet sağlandığında merkezi depolamaya aktarılır.
- **`[PROPOSED]` Boyutlandırma:** İstemcide görsel boyutlandırma ve sıkıştırma yapılması önerilir (en fazla 1200×1200 px, ~1 MB, JPEG/WebP).

### `BR-PROD-13` [CONFIRMED] Fiyat ve Maliyet Değişiklik Geçmişi (`price_history`, `cost_history`)
- **Açıklama:** Ürünlerin satış fiyatı veya alış maliyeti zaman içinde değiştiğinde bu değişiklikler denetlenebilir biçimde saklanır.
- **İş Akışı ve Kapsam:**
  1. Satış fiyatı değiştiğinde: Önceki Fiyat, Yeni Fiyat, Değişiklik Zamanı (UTC + yerel), Kullanıcı (`user_id`), Cihaz (`device_id`) ve Değişiklik Kaynağı (`MANUAL_UI` veya `EXCEL_IMPORT`) `price_history` tablosuna yazılır.
  2. Alış maliyeti değiştiğinde: Önceki Maliyet, Yeni Maliyet, Değişiklik Zamanı, Kullanıcı, Cihaz ve Değişiklik Kaynağı `cost_history` tablosuna yazılır.
  3. Satış anında ürün adı, birim, satış fiyatı ve o anki maliyet `sale_items` satırına snapshot olarak kopyalanır.
  4. Sonradan yapılan ürün fiyatı veya maliyet güncellemeleri geçmiş satış fişlerini, iadeleri ve kâr raporlarını kesinlikle etkilemez/değiştirmez.

### `BR-PROD-14` [CONFIRMED] Hiyerarşik Kategori Yapısı ve Kategori Yaşam Döngüsü
- **Açıklama:** Sistemde hiyerarşik kategori yapısı (Ana Kategori $\to$ Alt Kategori) desteklenir (`parent_id` hiyerarşisi).
- **Kural:**
  1. Bir ürün doğrudan tek bir kategoriye (veya alt kategoriye) bağlanır.
  2. Kategoriler fiziksel olarak silinmez; pasife alınır (`is_active = false`).
  3. İçinde en az bir aktif veya pasif ürün bulunan bir kategori sistemden fiziksel olarak silinemez.
  4. Pasif kategoriye yeni ürün eklenemez; ancak altındaki mevcut ürünlerin durumu korunur.

### `BR-PROD-15` [CONFIRMED] Barkod Yaşam Döngüsü, Tarihçe ve Yeniden Kullanılamama Kuralı
- **Açıklama:** Ürünlerin barkodları zaman içinde güncellenebilir veya yeni barkodlar eklenebilir.
- **Kural:**
  1. Bir ürünün mevcut barkodu değiştirildiğinde veya silindiğinde, eski barkod pasifleştirilerek `barcode_history` tablosunda saklanır.
  2. **Yeniden Kullanılamazlık:** Tarihçedeki pasif barkodlar da dahil olmak üzere, geçmişte kullanılmış hiçbir barkod aynı tenant altında başka bir ürüne mükerrer olarak atanamaz; barkodun tekilliği ve denetim izi korunur.
  3. Ürün arama ekranında: Ürün Adı, Barkod ve Marka alanlarına göre tam ve kısmi arama desteklenir. Kategori, Alt Kategori ve Aktiflik filtreleri sağlanır.

### `BR-PROD-16` [CONFIRMED] Ürün Kataloğunu XLSX Olarak Dışa Aktarma
- **Açıklama:** İşletme sahibi mevcut ürün kataloğunu dilediği zaman standart bir XLSX dosyası olarak dışa aktarabilir.
- **Kapsam:** Dışa aktarma dosyası; Barkodlar, Ürün Adı, Marka, Kategori, Satış Fiyatı, Maliyet, Birim, Stok Miktarı, Kritik Stok Eşiği ve Aktiflik Durumu kolonlarını içerir. Pasif ürünler de "Durum: Pasif" işaretiyle dışa aktarma dosyasında yer alır.

---

## 3. Modül 2: Satış, Sepet ve POS İş Kuralları (BR-POS)

### `BR-POS-01` [CONFIRMED] Barkod Okutma ve Sepete Ekleme
- **Açıklama:** İşletme sahibi barkod okuttuğunda (PC'de USB HID, mobilde kamera) ürün yerel veritabanında taranır. Bulunan ürün anında sepet listesine eklenir; adı, birim fiyatı ve miktarı net olarak görüntülenir.

### `BR-POS-02` [CONFIRMED] Aynı Barkodda Miktar Artırma ve Satır Düzenleme
- **Açıklama:** Sepette zaten bulunan bir ürünün barkodu tekrar okutulduğunda sepet satırı çoğaltılmaz; mevcut satırdaki miktar 1 artırılır ve toplam tutar anında yeniden hesaplanır.
- **Manuel Düzenleme:** İşletme sahibi sepet satırındaki miktarı klavye/numpad ile doğrudan değiştirebilir. Miktar 0'a (sıfır) indirilirse ilgili ürün satırı sepetten otomatik olarak kaldırılır.

### `BR-POS-03` [CONFIRMED] Sepet Satırı Silme
- **Açıklama:** İşletme sahibi sepet satırındaki "Sil" butonuna basarak ürünü sepetten tamamen çıkarabilir. Sepet toplamı anında güncellenir.

### `BR-POS-04` [CONFIRMED] Sepet Tutarı ve Finansal Kesinlik
- **Açıklama:** Sepet ara toplamı ve genel toplamı her miktar değişiminde anında güncellenir.
- **Kesinlik Kuralı:** Hesaplamalarda floating-point (`double`) aritmetiği kesinlikle yasaktır. Kuruş bazlı tamsayı (örn. 150.50 TL = 15050 kuruş) veya fixed-point kesinlik kullanılır.

### `BR-POS-05` [CONFIRMED] Askıya Alınan Sepetler (Parked Carts)
- **Açıklama:** Müşteri cüzdanını unuttuğunda veya reyonu terk ettiğinde işletme sahibi sepeti "Askıya Al" (Park Et) işlemiyle beklemeye alabilir ve sıradaki müşterinin satışına geçebilir.
- **Kural:** Askıya alınan sepetler yerel veritabanında kalıcı olarak saklanır; uygulama kapansa veya cihaz yeniden başlatılsa dahi kaybolmaz. MVP için keyfî bir sepet sayısı üst sınırı uygulanmaz. Sepet tamamlanmadan stok miktarı kesinlikle düşürülmez.
- **`[PROPOSED]` Sayfalama:** Bekleyen sepet listesinde performans için sayfalama mekanizması teknik tasarımda değerlendirilecektir.

### `BR-POS-06` [CONFIRMED] Sepet Kilitleme (Cart Locking) ve Çoklu Cihaz
- **Açıklama:** Bir sepet aynı anda yalnızca tek bir cihaz tarafından düzenlenebilir.
- **Kural:** Bir cihazda düzenlenmekte olan sepet, ağdaki diğer cihazlarda salt okunur (read-only) olarak görüntülenir ve üzerinde "Düzenleniyor" rozeti yer alır. Süresi dolan kilit diğer cihaz tarafından devralınabilir.
- **`[PROPOSED]` Parametreler:** 30 saniyelik kalp atışı (heartbeat) ve 2 dakikalık kilit zaman aşımı (timeout) parametreleri teknik testlerle doğrulanacaktır. Çevrimdışı ortamda mutlak eşzamanlı kilit garantisi verilemeyeceği bir sistem sınırı olarak belgelenmiştir.

### `BR-POS-07` [CONFIRMED] Satış Tamamlama Atomik Transaction'ı
- **Açıklama:** İşletme sahibi satışı onayladığında aşağıdaki işlemler **tek bir yerel veritabanı transaction'ı** içinde atomik olarak yürütülür:
  1. `sales` tablosuna satış başlık kaydı yazılır.
  2. `sale_items` tablosuna her sepet kalemi için ürün adı, birim, satış anındaki birim fiyatı, miktarı ve o anki maliyetini içeren snapshot satırları yazılır.
  3. `stock_movements` tablosuna her ürün için "SATIS" tipiyle stok düşüm kaydı yazılır.
  4. İlgili ürünlerin stok miktarları yerel veritabanında düşürülür (eksi stoğa izin verilir).
  5. `sync_operations` tablosuna merkezi sunucuya aktarılmak üzere outbox senkronizasyon kuyruk kaydı yazılır.
- **Rollback:** Transaction içindeki adımlardan herhangi biri başarısız olursa tüm işlem geri alınır (rollback); tutarsız veya yarım kayıt bırakılamaz.

### `BR-POS-08` [CONFIRMED] Tam Satış İptali İş Akışı (Zaman Sınırsız İptal)
- **Açıklama:** Daha önce tamamlanmış bir satış fişinin tamamının iptal edilmesi işlemidir.
- **Zaman Sınırının Bulunmaması:** Satış iptali işlemi için "müşteri kasadan ayrılmadan veya gün içinde" gibi herhangi bir yapay zaman sınırlaması bulunmaz. Daha önce tamamlanmış geçmiş satışlar da zaman sınırı olmaksızın işletme sahibinin açık onayı ve zorunlu gerekçe girişiyle tamamen iptal edilebilir.
- **Kurallar:**
  1. Satış kaydı veritabanından fiziksel olarak silinmez; durumu "CANCELLED" olarak güncellenir.
  2. Fişteki tüm ürünler için `stock_movements` tablosuna "SATIS_IPTALI" türüyle stok iade kaydı yazılır ve ürün stokları otomatik artırılır.
  3. İptal edilen satış tutarı ciro ve hasılat toplamlarından tamamen çıkarılır; iptal edilmiş satışlar hasılatı artıramaz.
  4. Kasa nakit/kart dengesi orijinal satışın ödeme yöntemine göre ters işlemle dengelenir.
  5. İptal işlemi için işletme sahibinden **zorunlu bir gerekçe** ("Müşteri vazgeçti", "Yanlış fiş" vb.) ve işlem öncesi açık onay istenir.
  6. İptal edilen bir satış ikinci kez iptal edilemez veya üzerinden ürün iadesi yapılamaz (mükerrerlik engeli).
  7. İşlem tek bir atomik transaction içinde icra edilir ve `audit_logs` tablosuna işlenir.

### `BR-POS-09` [CONFIRMED] Kısmi Ürün İadesi İş Akışı
- **Açıklama:** Müşterinin fişteki ürünlerden yalnızca birini veya birkaçını ya da belirli bir miktarını geri getirmesi durumudur.
- **Kurallar:**
  1. İade işlemi orijinal fiş/satış referansıyla başlatılır (`sale_id`).
  2. **Miktar Tutarlılık Sınırı:** İade edilecek ürün miktarı, o satışta satılan miktardan daha önce yapılmış iadeler düşüldükten sonra kalan iade edilebilir miktarı kesinlikle aşamaz:
     $$\text{İade Edilebilir Miktar} = \text{Orijinal Satış Miktarı} - \sum \text{Önceki İadeler}$$
  3. **Fiyat Kuralı:** İade edilecek birim fiyat, ürün kartındaki güncel fiyat değil; fişteki snapshot satış fiyatıdır.
  4. **Ödeme İadesi:** İade tutarı, orijinal satışın ödeme yöntemine göre ödenir (nakit satış ise nakit iade, kart satış ise kart iade kaydı).
  5. İade işlemi için zorunlu gerekçe ve işlem öncesi açık onay şarttır.
  6. İade edilen tutar Net Satış raporuna anında yansır ($\text{Net Satış} = \text{Brüt Satış} - \text{İadeler}$).
  7. Bir kalemin tamamı iade edildiğinde o kalem için tekrar iade başlatılamaz.
  8. İşlem tek bir atomik transaction içinde `refunds` ve `refund_items` tablolarına kaydedilir.

### `BR-POS-10` [CONFIRMED] İade Edilen Ürünün Durumu (Satılabilir vs. Hasarlı/Fire)
- **Açıklama:** İade alınan ürünün fiziksel kondisyonu işlem sırasında seçilir: **Satılabilir** veya **Hasarlı / Bozuk**.
- **Satılabilir Ürün Kuralı:** Ürün tekrar rafa konulabilir durumdaysa, `stock_movements` tablosuna "MUSTERI_IADESI" türüyle stok artırıcı kayıt yazılır ve ürünün satılabilir stoğu artar.
- **Hasarlı / Bozuk Ürün Kuralı:** Ürün bozulmuş, kırılmış veya ambalajı zarar görmüşse, normal satılabilir stoğa kesinlikle eklenmez. `stock_movements` tablosuna doğrudan "FIRE_KAYIP" türüyle kayıt yazılır ve fire raporlarında izlenir; satılabilir stok artırılmaz.
- **`[PROPOSED]` Ayrı Hasarlı Stok Takibi:** Ayrı bir hasarlı/karantina ürün deposu takibinin gerekip gerekmediği teknik tasarım aşamasında netleştirilecektir.

### `BR-POS-11` [CONFIRMED] Sepet Fiyat Snapshot'ı ve Manuel Fiyat Müdahalesi
- **Açıklama:** Sepete ürün eklendiği anda ürünün o anki satış fiyatı sepet satırına snapshot olarak kopyalanır.
- **Kural:**
  1. Ürün kartındaki fiyat daha sonra (ürün yönetiminden veya diğer cihazdan) değişse dahi, açık sepetin satır fiyatı kendiliğinden değişmez.
  2. Ekmek dahil tüm ürünler için işletme sahibi sepet satırındaki birim fiyatı elle değiştirebilir (ör. defolu ürün veya bayat ekmek indirimi).
  3. Manuel fiyat müdahalesinde: Mevcut Fiyat, Yeni Fiyat, Zorunlu Gerekçe ve Açık Onay istenir.
  4. Sepet satırında yapılan manuel fiyat değişikliği, ürün kartındaki ana satış fiyatını kesinlikle değiştirmez; yalnızca o sepet ve fiş için geçerlidir.

---

## 4. Modül 3: Ödeme, Kasa ve Para Üstü İş Kuralları (BR-PAY)

### `BR-PAY-01` [CONFIRMED] Satış Başına Tek Ödeme Yöntemi
- **Açıklama:** MVP sürümünde satış başına tek bir ödeme yöntemi seçilir: **Nakit** veya **Kredi Kartı**.
- **`[OUT_OF_SCOPE]`:** Parçalı / karma ödeme (bir kısmı nakit, bir kısmı kart) ve veresiye (müşteri cari defteri) MVP kapsamı dışındadır.

### `BR-PAY-02` [CONFIRMED] Nakit Satış ve Otomatik Para Üstü Hesabı
- **Açıklama:** Nakit ödeme seçildiğinde işletme sahibi müşteriden alınan nakit tutarı girer. Sistem para üstünü anında hesaplar ($\text{Para Üstü} = \text{Alınan Tutar} - \text{Satış Toplamı}$) ve ekranda belirgin biçimde gösterir.

### `BR-PAY-03` [CONFIRMED] Eksik Tutar Durumunda Satış Engeli
- **Açıklama:** Alınan nakit tutar satış toplam tutarından az ise ($\text{Alınan Tutar} < \text{Toplam Tutar}$), "Tamamla" butonu kilitli kalır; satış kesinlikle tamamlanamaz.

### `BR-PAY-04` [CONFIRMED] Kredi Kartı Ödemesi ve Donanım Sınırı
- **Açıklama:** Kredi kartı seçildiğinde satış tutarı sisteme "Kart ile Ödendi" olarak kaydedilir. Banka POS terminaline otomatik tutar gönderme MVP dışındadır (`OUT_OF_SCOPE`). Tutar harici banka POS cihazına gerekirse elle girilir.

### `BR-PAY-05` [CONFIRMED] Ödeme Yöntemi Düzeltme İşlemi ve Raporlama Etkisi
- **Açıklama:** Yanlışlıkla "Nakit" yerine "Kart" (veya tam tersi) seçilerek satış kapatıldıysa, tamamlanmış geçmiş satış kaydı fiziksel olarak silinemez veya sessizce değiştirilemez.
- **İş Akışı ve Rapor Etkisi:** Bu durum ayrı ve denetlenebilir bir "Ödeme Yöntemi Düzeltme" işlemi olarak yürütülür. Düzeltme işlemi gerekçesiyle birlikte `audit_logs` tablosuna işlenir. Raporlarda ilgili satışın ödeme yöntemi güncel seçime göre yeniden sınıflandırılır (eski ödeme türünün cirosu düşülür, yeni ödeme türünün cirosu artırılır); böylece kasa raporlarının doğruluğu korunur.

### `BR-PAY-06` [OUT_OF_SCOPE] Kasa Açılış/Kapanış ve Kasa Farkı Takibi
- **Açıklama:** Sabah kasa açılış nakdi girme, akşam gün sonu fiziki kasa sayımı yapma ve sistem nakdi ile sayılan nakit arasındaki "Kasa Farkı" mutabakatı MVP kapsamı dışındadır.

---

## 5. Modül 4: Stok Yönetimi ve Stok Sayımı İş Kuralları (BR-STK)

### `BR-STK-01` [CONFIRMED] Otomatik Stok Düşümü ve Başlangıç Stoğu
- **Açıklama:** Yeni ürün tanımlanırken başlangıç stoğu girilebilir (`BASLANGIC_STOK`). Satış işlemi tamamlandığında satılan miktar kadar stok otomatik olarak düşer (`SATIS`).

### `BR-STK-02` [CONFIRMED] Eksi Stok Satış İzni ve Uyarı Kuralı
- **Açıklama:** Kasada satışı yapılmak istenen ürünün sistem stoğu yetersiz ise (stok sıfır veya satış miktarı mevcut stoktan fazla ise), sistem belirgin bir görsel uyarı verir ("Stok yetersiz / Eksiye düşecek").
- **İşletme İzni:** İşletme sahibi uyarıya rağmen satışı tamamlamayı seçebilir. Satış tamamlandığında ürünün stok miktarı eksiye (negatif sayıya) düşer.
- **İzleme:** Negatif stoklu ürünler dashboard'da ve stok listesinde "Eksi Stoklu Ürünler" filtresi altında ayrıca vurgulanır.

### `BR-STK-03` [CONFIRMED] Eksi Stokta Satışın Tamamlanabilmesi ve Stok Uyuşmazlığı Takibi
- **İş Kuralı:** Stok miktarı yetersiz veya sıfır olsa dahi işletme sahibi satışı tamamlayabilir; satış işlemi engellenmez. Ortaya çıkan stok uyuşmazlığı, negatif bakiye ve çakışmalar sisteme kaydedilir, denetim kayıtları (`audit_logs`) ve dashboard üzerinden izlenip raporlanır.
- **Teknik Tasarım Şerhi (Aşama 6B-2):** Veritabanı seviyesinde pozitif stok CHECK kısıtının (`quantity >= 0`) bulunup bulunmayacağı, negatif değerlerin veri tabanında nasıl temsil edileceği ve SQLite/Drift veri tipi ayrıntıları teknik tasarım konusu olup kullanıcı iş kuralı değildir; Aşama 6B-2 kapsamında değerlendirilecektir.

### `BR-STK-04` [CONFIRMED] Şube Başına Tek Aktif Stok Sayımı
- **Açıklama:** Veri tutarsızlığını önlemek için bir şubede aynı anda yalnızca bir adet aktif (açık) sayım oturumu bulunabilir. Yeni bir sayım başlatılabilmesi için mevcut sayımın ya onaylanması ya da iptal edilmesi gerekir.

### `BR-STK-05` [CONFIRMED] Kalıcı Taslak Sayım ve Tam/Kısmi Sayım
- **Açıklama:** Sayım kayıtları yerel veritabanında "DRAFT" durumunda kalıcı tutulur; uygulama kapatılıp açılsa da sayım kaldığı yerden devam eder. Hem tüm dükkânın sayıldığı "Tam Sayım", hem de reyon/kategori bazlı "Kısmi Sayım" desteklenir.

### `BR-STK-06` [CONFIRMED] Sayım Sırasında Satışa Devam Edilebilmesi
- **Açıklama:** Sayım oturumu açıkken kasada satış kesinlikle durdurulmaz. İşletme sahibi normal satış yapmaya devam eder; satış hareketleri arka planda veritabanına işlenir.

### `BR-STK-07` [CONFIRMED] Çoklu Cihaz Sayım Kilidi (Tek Cihaz Düzenler)
- **Açıklama:** Bir şubede açık olan taslak sayımı aynı anda yalnızca tek bir cihaz düzenleyebilir ve kalem girebilir. Diğer cihazlar taslak sayımı yalnızca salt okunur olarak inceler.
- **`[PROPOSED]` Lease Modeli:** Sayım düzenleme yetkisinin sepet kilidine benzer bir heartbeat/lease mekanizmasıyla yönetilmesi teknik öneridir.

### `BR-STK-08` [CONFIRMED] Sayım Onayında Bekleyen Senkronizasyon Kontrolü
- **Açıklama:** Sayım onaylanmadan hemen önce sistem, diğer çevrimdışı cihazların henüz sunucuya aktarılmamış bekleyen stok hareketleri olup olmadığını kontrol eder. Bekleyen kuyruk varsa kullanıcı uyarılır.

### `BR-STK-09` [CONFIRMED] Ara Stok Hareketlerinin Matematiksel Uzlaştırılması
- **Açıklama:** Fiziksel sayımın zamanı ürün ve sayım kalemi bazında ele alınır. Bir ürünün rafta fiilen sayıldığı an ile sayım oturumunun onaylandığı an arasında kasada gerçekleşen satışlar ve mal girişleri formüle doğru biçimde katılarak uzlaştırılır:
  $$\text{Nihai Stok} = \text{Fiziksel Sayılan} - \text{Sayım Sonrası Satışlar} + \text{Sayım Sonrası Mal Girişleri}$$
- **`[PROPOSED]` Kesin Uzlaştırma Algoritması:** Ürün bazlı sayım zaman damgasının (`counted_at`) kaydedilmesi, sayım sırasındaki ara hareketlerin mikro düzeyde ayrıştırılması ve eşzamanlı transaction algoritması teknik tasarım aşamasında hazırlanacaktır.

### `BR-STK-10` [CONFIRMED] Sayım Onayı, İptali ve Değiştirilemezlik
- **Açıklama:**
  1. Onaylanan ("COMPLETED") bir sayım belgesi geriye dönük olarak kesinlikle düzenlenemez veya silinemez. Sayım farkları `stock_movements` tablosuna "SAYIM_FARKI" tipiyle otomatik düzeltme hareketi olarak kaydedilir.
  2. İşletme sahibi taslak sayımı dilediği zaman iptal edebilir ("CANCELLED"). İptal edilen taslak sayım stok miktarlarında kesinlikle hiçbir değişiklik yapmaz.

### `BR-STK-11` [CONFIRMED] Stok Hareketi Türleri ve Gerekçe Zorunluluk Matrisi
- **Açıklama:** Sistemdeki tüm stok değişimleri kesin olarak şu 9 türe ayrılır ve aşağıdaki gerekçe kuralına göre denetlenir:

| Hareket Türü (`movement_type`) | Açıklama ve Tetikleyici | Gerekçe / Açıklama Zorunluluğu |
|---|---|---|
| `BASLANGIC_STOK` | Ürün ilk oluşturulurken girilen başlangıç stoğu | İsteğe Bağlı |
| `NORMAL_GIRIS` | Toptancıdan mal gelişi / manuel mal kabul | İsteğe Bağlı |
| `NORMAL_CIKIS` | Manuel stok çıkışı | İsteğe Bağlı |
| `SATIS` | Satış tamamlandığında otomatik stok düşümü | **Otomatik** (`sale_id` referansı yazılır) |
| `SATIS_IPTALI` | Satış fişinin tamamen iptal edilmesiyle stoğa iade | **Gerekçe ZORUNLU** |
| `MUSTERI_IADESI` | Müşteri ürün iadesinde satılabilir ürünün stoğa girişi | **Gerekçe ZORUNLU** |
| `FIRE_KAYIP` | Kırılan, bozulan, SKT'si geçen veya hasarlı iade edilen mallar | **Gerekçe ZORUNLU** |
| `MANUEL_DUZELTME` | Sayım dışı tekil stok miktar düzeltmesi | **Gerekçe ZORUNLU** |
| `SAYIM_FARKI` | Onaylanan sayım sonucu sistem stoğu fark düzeltmesi | **Otomatik** (`count_session_id` referansı yazılır) |

- **Zorunlu Alanlar:** Her stok hareketinde Tarih/Saat (UTC + yerel), Kullanıcı (`user_id`), Cihaz (`device_id`), Ürün (`product_id`), Miktar (+ / -), Hareket Türü (`movement_type`) ve Açıklama/Gerekçe kaydedilir.
- **Değiştirilemezlik:** Geçmiş stok hareketleri veritabanından sessizce silinemez veya geriye dönük değiştirilemez.

---

## 6. Modül 5: Çevrimdışı Çalışma ve Senkronizasyon İş Kuralları (BR-SYNC)

### `BR-SYNC-01` [CONFIRMED] Offline-First Yerel Bütünlük
- **Açıklama:** İnternet bağlantısı tamamen kesik olsa dahi ürün arama, sepete ekleme, satış tamamlama, eksi stok satışı, taslak sayım ve raporlama yerel SQLite veritabanında kesintisiz çalışır.

### `BR-SYNC-02` [CONFIRMED] Outbox Kuyruğu (`sync_operations`)
- **Açıklama:** Çevrimdışıyken yapılan her işlem atomik transaction içinde yerel `sync_operations` tablosuna yazılır. Yerel ağ (LAN) bağlantısı sağlandığında kuyruk arka planda otomatik olarak Windows Local Master Hub API'sine aktarılır; internet bağlantısı zorunlu değildir.

### `BR-SYNC-03` [CONFIRMED] Idempotency Garantisi (`idempotency_key`)
- **Açıklama:** Her satış ve stok işlemi istemci tarafından üretilen benzersiz bir idempotency anahtarı taşır. Ağ kesintisi veya mükerrer istek gönderiminde sunucu aynı işlemi ikinci kez işlemez; mükerrer stok düşümü engellenir.
- **`[PROPOSED]` Format:** Anahtar formatı olarak UUIDv4 kullanılması teknik tasarım tercihidir.

### `BR-SYNC-04` [CONFIRMED] Çevrimdışı Ürün Ekleme ve Barkod Tekilliği
- **Açıklama:** İnternet yokken yerel veritabanında yeni ürün açılabilir. Cihaz internete bağlandığında sunucuda tenant düzeyinde barkod tekilliği kontrol edilir. Çakışan ürünler sistem tarafından otomatik olarak birleştirilmez veya ezilmez.

### `BR-SYNC-05` [CONFIRMED] Çevrimdışı Fiyat Değişikliği ve Çakışma Koruma
- **Açıklama:** Fiyat değişikliği yerel cihazda anında kaydedilir ve kuyruğa eklenir. Senkronizasyon gerçekleşene kadar diğer cihazlar kendi yerel fiyatını gösterebilir.
- **Çakışma Kuralı:** İki farklı çevrimdışı cihazda aynı ürüne farklı fiyat verilmişse çakışma tespit edilir; sistem sessizce birini ezmez, her iki değeri de saklar.
- **İşletme Sahibi Kararı:** Çakışma işletme sahibinin inceleme ekranına sunulur ve onaylanan fiyat geçerli kılınır. Karar `audit_logs` tablosuna yazılır.
- **Geçerli Fiyat:** Çakışma çözülene kadar ilgili cihazın elindeki son yerel fiyat bilgisi kasada geçerli sayılır.

### `BR-SYNC-06` [CONFIRMED] Satışların Asla Silinmemesi ve Çevrimdışı Stok Farkı
- **Açıklama:** İki cihazın çevrimdışı satışları senkronize olurken stok eksiye düşse dahi yapılmış fiziksel satış kayıtları kesinlikle silinemez veya iptal edilemez. Çevrimdışı cihazlar arasında anlık stok tutarsızlığı oluşabilir; internet bağlantısı geldiğinde stok farkları görünür hale gelir ve audit loglarına alınır.

---

## 7. Modül 6: Kimlik, Cihaz ve Güvenlik İş Kuralları (BR-SEC)

### `BR-SEC-01` [CONFIRMED] Pilot Kullanıcı Kimlik Doğrulaması
- **Açıklama:** Pilot aşamasında sistem tek işletme sahibi (Owner) hesabı ile yerel olarak yönetilir. Yerel kimlik doğrulama yöntemi (PIN, parola, token vb.) açık konu olup Faz 1'de ele alınacaktır. Gelecek SaaS aşamasında e-posta/parola ve Supabase Auth altyapısı desteklenecektir.

### `BR-SEC-02` [CONFIRMED] Pilot Tek Kullanıcı (İşletme Sahibi) Kuralı
- **Açıklama:** Pilot markette yalnızca tek bir kullanıcı hesabı (İşletme Sahibi) çalışacaktır.
- **`[OUT_OF_SCOPE]`:** Kasiyer/personel rolleri, PIN ile hızlı kasiyer değişimi ve vardiya yönetimi MVP kapsamı dışındadır.

### `BR-SEC-03` [CONFIRMED] İlk Girişte İnternet Şartı ve Çevrimdışı Çalışma
- **Açıklama:** Bir cihazda ilk defa oturum açılırken internet bağlantısı zorunludur. Kimlik doğrulandıktan sonra oturum bilgileri yerel kasada şifreli saklanır; ardından cihaz internet olmasa da çalışmaya devam eder.

### `BR-SEC-04` [CONFIRMED] Cihaz İptali (Device Revocation)
- **Açıklama:** İşletme sahibi yönetim arayüzünden bir cihazın yetkisini iptal edebilir. İptal edilen cihazın Master Hub API erişim yetkisi derhal düşürülür; ancak cihazın yerel veritabanı silinmez, Outbox kayıtları ve bekleyen satışları korunur. İptal edilen cihazdaki satışların kurtarılması ve uzlaştırılması ayrıca tasarlanacaktır.

### `BR-SEC-05` [CONFIRMED] Pilot Cihaz Sınırı
- **Açıklama:** Pilot aşamasında bir işletme için en fazla 3 aktif cihaz (1 PC Kasa + 2 Mobil Telefon/Tablet) tanımlanabilir.

### `BR-SEC-06` [PROPOSED] Güvenli Depolama ve Çevrimdışı Oturum Süresi
- **Öneri:** Masaüstünde DPAPI / Windows Credential Manager, mobilde Keychain / KeyStore mekanizmalarının kullanılması ve çevrimdışı oturum süresinin en fazla 7 gün olarak sınırlandırılması teknik öneri olarak doğrulanacaktır.

---

## 8. Modül 7: Tenant ve Çoklu Şube Mimarisi (BR-TNT)

### `BR-TNT-01` [CONFIRMED] Pilot Tek Tenant ve Tek Şube
- **Açıklama:** Pilot aşamasında tek bir işletme (Tenant) ve bu işletmeye ait tek bir şube (Store) aktiftir.

### `BR-TNT-02` [CONFIRMED] Geleceğe Hazır Veri Modeli
- **Açıklama:** Kodlama yapılmasa dahi veritabanı şeması ve modeller `tenant_id` ve `store_id` hiyerarşisine uygun tasarlanır. Ürün kataloğu tenant düzeyinde; fiziksel stok, satış fişleri ve sepetler şube düzeyinde izole edilir.

### `BR-TNT-03` [CONFIRMED] Veri İzolasyonu
- **Açıklama:** Pilot aşamasında veri izolasyonu merkezi API tarafından iş kuralları seviyesinde uygulanır; merkezi API veri erişiminde tenant ve store sınırlarını uygular. Gelecek bulut SaaS aşamasında ise PostgreSQL Row Level Security (RLS) politikaları zorunludur.

### `BR-TNT-04` [OUT_OF_SCOPE] Şubeye Özel Fiyatlandırma
- **Açıklama:** İleride desteklenecek şubeler arası farklı fiyat tanımlama mantığı MVP kapsamı dışındadır. Veri modeli bu genişlemeye engel olmayacak biçimde tasarlanır (`[PROPOSED]`).

---

## 9. Modül 8: Yedekleme ve Kurtarma İş Kuralları (BR-BAK)

### `BR-BAK-01` [CONFIRMED] Günlük Otomatik Yedekleme ve 30 Gün Saklama
- **Açıklama:** Veritabanının günlük otomatik yedeği alınır ve son 30 günün yedekleri geriye dönük saklanır.

### `BR-BAK-02` [CONFIRMED] Önemli Olaylardan Sonra Ek Yedek
- **Açıklama:** Toplu Excel içe aktarımı veya yıl sonu devri gibi kritik operasyonel olayların ardından sistem otomatik ek yedek alır.

### `BR-BAK-03` [CONFIRMED] Satış Başına Tam Yedek Almama İlkesi
- **Açıklama:** Sistem performansını ve disk ömrünü korumak için her tekil satış işleminde tam veritabanı yedeği kesinlikle alınmaz. Satışlar yerel transaction ve outbox kuyruğu ile korunur.

### `BR-BAK-04` [CONFIRMED] Bağımsız Google Drive Yedeği
- **Açıklama:** Merkezi Windows SQLite veritabanı ve mobil cihaz veritabanlarının ayrık yedeklerine ek olarak, harici ve bağımsız bir Google Drive yedekleme mekanizması çalışır.
- **`[PROPOSED]` OAuth Modeli:** Her tenant kendi Google hesabını en dar yetki kapsamıyla bağlar. Merkezi tek bir hesap kullanılmaz.

### `BR-BAK-05` [CONFIRMED] Geri Yükleme Öncesi Koruyucu Yedek
- **Açıklama:** Bir yedek sisteme geri yüklenmeden (restore) hemen önce, o anki veritabanı durumunun koruyucu bir yedeği (safety snapshot) zorunlu olarak alınır.

### `BR-BAK-06` [PROPOSED] Geri Yükleme Sırasında Bekleyen Yerel İşlemlerin Korunması ve Uzlaştırma
- **Prensip ve Öneri:** Bir yedek geri yüklendiğinde, cihazlardaki yerel bekleyen senkronizasyon kuyrukları ve henüz sunucuya aktarılmamış çevrimdışı satışlar/stok hareketleri kesinlikle silinmez veya körü körüne sıfırlanmaz. Geri yüklenen ana veri ile cihazlardaki bekleyen işlemlerin veri kaybı yaşanmadan uzlaştırılması ve eski kuyrukların yedeği kirletmesini önleyecek kesin uzlaştırma protokolü teknik tasarım aşamasında modellenecektir.

---

## 10. Modül 9: Dashboard ve Raporlama İş Kuralları (BR-REP)

### `BR-REP-01` [CONFIRMED] Zaman Dilimi, Takvim Günü ve Haftalık Periyot Standardı
- **Açıklama:** Raporlama zaman filtreleri: **Bugün**, **Dün**, **Bu Hafta**, **Bu Ay** ve **Özel Tarih Aralığı** seçeneklerini içerir.
- **Haftalık Periyot Kuralı:** Haftalık raporlar `Europe/Istanbul` yerel saatine göre **Pazartesi günü 00:00:00'da başlar ve Pazar günü 23:59:59'da biter**.
- **Takvim Günü ve Saat Kuralı:** Raporlama takvim günü sınırları `Europe/Istanbul` yerel saat dilimine göre (00:00:00 - 23:59:59) belirlenir. Veritabanında zaman damgaları UTC saklanır; rapor ekranlarında ve dışa aktarımlarda yerel saat dilimine dönüştürülerek gösterilir.

### `BR-REP-02` [CONFIRMED] Net Satış ve Finansal Metrik Ayrımı
- **Açıklama:** Raporlarda Brüt Satış, İadeler ve Net Satış matematiksel olarak ayrı gösterilir:
  $$\text{Net Satış} = \text{Brüt Satış} - \text{İadeler}$$
- **İptaller:** İptal edilen satışlar ciro ve hasılat toplamlarına kesinlikle dahil edilmez; audit ve kontrol amacıyla ayrı bir "İptal Edilen Satışlar" raporunda izlenir.

### `BR-REP-03` [CONFIRMED] Ödeme Türü Hasılat Kırılımı ve İade/Düzeltme Yansıması
- **Açıklama:** Raporlarda toplam satış hasılatı Nakit ve Kredi Kartı kırılımında net olarak ayrıştırılır.
- **İade Yansıması:** Yapılan ürün iadeleri, orijinal satışın ödeme yöntemine göre ilgili cirodan düşülür (nakit satış iadesi nakit hasılatından, kart satış iadesi kart hasılatından düşülür).
- **Düzeltme Yansıması:** Ödeme yöntemi düzeltmeleri ilgili ödeme türü cirolarına anında yansıtılır.

### `BR-REP-04` [CONFIRMED] Ayrı En Çok Satan Ürün Sıralamaları ve Birim Ayrımı
- **Açıklama:** "Miktar Bazında En Çok Satanlar" ile "Ciro Bazında En Çok Satanlar" (TL) iki bağımsız liste olarak sunulur.
- **İade Düşümü:** Yapılan ürün iadeleri çok satanlar miktar ve ciro toplamlarından düşülür.
- **Birim Bütünlüğü:** Farklı ölçü birimlerine sahip ürünler (ör. 5 Adet çikolata ile 5 kg elma) aynı miktar toplamında toplanmaz; birim bazlı ayrı gruplanır.

### `BR-REP-05` [CONFIRMED] Brüt Kâr Hesabı ve Eksik Maliyet Uyarısı
- **Açıklama:** Brüt Kâr yalnızca alış maliyeti girilmiş ürünler için ($\text{Satış Tutarı} - \text{Maliyet Tutarı}$) hesaplanır.
- **Eksik Maliyet:** Maliyeti girilmemiş ürünlerin satışları kâr raporunda "Maliyeti Belirtilmemiş Satışlar" olarak açıkça uyarılır ve ayrı listelenir; kâr sıfır veya %100 kabul edilerek kullanıcı yanıltılmaz.

### `BR-REP-06` [CONFIRMED] Çevrimdışı Rapor Veri Eksikliği Uyarısı
- **Açıklama:** Cihaz çevrimdışıyken alınan raporların üzerinde belirgin bir uyarı yer alır: *"Bu rapor yalnızca bu cihazdaki yerel verileri içermektedir; diğer cihazların çevrimdışı satışları henüz yansımamış olabilir."*

### `BR-REP-07` [CONFIRMED] XLSX ve PDF Dışa Aktarma
- **Açıklama:** Tüm raporlar Excel (.xlsx) ve PDF formatında dışa aktarılabilir.

### `BR-REP-08` [OUT_OF_SCOPE] Gider Yönetimi ve Net Kâr
- **Açıklama:** İşletme giderleri (kira, elektrik, personel vb.) ilk sürümde girilemediğinden sistemde Net Kâr metriği gösterilmez.

---

## 11. MVP Kapsam Dışı Sınırlar Özeti

Aşağıdaki özellikler ilk sürümün (MVP) kapsamı dışındadır:
1. Banka POS terminali entegrasyonu (tutar POS cihazına gerekirse elle girilir).
2. Mali cihaz / yazar kasa entegrasyonu.
3. KDV hesaplama ve mali raporlama.
4. Personel hesapları ve kasiyer yetki matrisi (pilotta sadece işletme sahibi).
5. Kasa açılış/kapanış ve kasa farkı takibi.
6. Karma/split ödeme ve veresiye takibi.
7. Tedarikçi ve satın alma sipariş modülü.
8. İndirim, kampanya ve promosyon motoru.
9. Terazi entegrasyonu ve terazi barkodu (27xxxxx) ayrıştırma.
10. Şubeye özel farklı fiyatlandırma.
11. Push bildirimleri.
12. Gider yönetimi ve net kâr hesabı.

---

## 12. Keşif Dokümanı ile İzlenebilirlik Matrisi (Traceability Matrix)

Aşağıdaki tablo, [`PHASE_0_BUSINESS_DISCOVERY.md`](file:///c:/Users/halil/Github/market-pos/docs/requirements/PHASE_0_BUSINESS_DISCOVERY.md) (v1.3) belgesindeki her bir gereksinimin işbu şartnamedeki (v1.2) karşılığını doğrulamaktadır:

| Keşif Dokümanı Bölümü | Konu / İş Gereksinimi | İlgili BR Kodu | Kural Durumu | Şartname Bölümü | Not / Doğrulama Durumu |
|---|---|---|---|---|---|
| **Bölüm 2** | MMS SaaS, Clean Architecture, Offline-First, Drift, Windows Master Hub | Genel | `CONFIRMED` | Bölüm 1 & AGENTS.md | Mimari temel tam korundu |
| **Bölüm 2 & 4.2** | Floating-point (`double`) para aritmetiği yasağı | `BR-PROD-07`, `BR-POS-04` | `CONFIRMED` | Bölüm 2, Bölüm 3 | Kuruş bazlı integer kesinliği |
| **Bölüm 4.1** | XLSX/CSV desteği, tam ön doğrulama, hatada durma | `BR-PROD-09` | `CONFIRMED` | Bölüm 2 | Atomik transaction ile tam korundu |
| **Bölüm 4.1** | Dosya içi mükerrer barkod engeli | `BR-PROD-10` | `CONFIRMED` | Bölüm 2 | Ön doğrulama kuralı |
| **Bölüm 4.1** | Tenant barkod çakışma onayı, kategori eşleştirme | `BR-PROD-11` | `CONFIRMED` | Bölüm 2 | Fiyat geçmişine EXCEL_IMPORT yazılır |
| **Bölüm 4.1** | Önerilen 5.000 satır sınırı | `BR-PROD-09` | `PROPOSED` | Bölüm 2 | Performans testi bekliyor |
| **Bölüm 4.2** | Desteklenen birimler, stok-fiyat birim ayrımı | `BR-PROD-07` | `CONFIRMED` | Bölüm 2 | Depo vs reyon birimi ayrıldı |
| **Bölüm 4.2** | Paket/kutu dönüşüm çarpanı ve farklı paket miktarları | `BR-PROD-02`, `BR-PROD-08` | `CONFIRMED` | Bölüm 2 | Farklı paket miktarları ayrı ürün |
| **Bölüm 4.2** | Birim hassasiyeti ve yuvarlama kural seti | `BR-PROD-07` | `PROPOSED` | Bölüm 2 | Teknik tasarıma devredildi |
| **Bölüm 4.3** | Ekmek hızlı satış tuşu (barkodsuz) | `BR-PROD-04` | `CONFIRMED` | Bölüm 2 | `product_barcodes` ilişkisizliği ile |
| **Bölüm 4.3** | Bulunamayan barkod zorunlu kayıt akışı | `BR-PROD-05` | `CONFIRMED` | Bölüm 2 | Ad, birim, kategori, fiyat zorunlu |
| **Bölüm 4.3** | Open Food Facts öneri mekanizması | `BR-PROD-06` | `CONFIRMED` | Bölüm 2 | Fiyat/stok API'den gelmez |
| **Bölüm 4.4** | Eksi stok satış izni, uyarı ve negatif stok takibi | `BR-STK-02` | `CONFIRMED` | Bölüm 5 | İşletme onaylı eksi stok |
| **Bölüm 4.4** | Eksi stokta satışın engellenmemesi ve uyuşmazlık takibi | `BR-STK-03` | `CONFIRMED` | Bölüm 5 | Eksi stok iş kuralı; DDL kısıtı Aşama 6B-2 |
| **Bölüm 4.4** | Şube başına tek aktif sayım oturumu | `BR-STK-04` | `CONFIRMED` | Bölüm 5 | Çakışma önleyici kural |
| **Bölüm 4.4** | Kalıcı taslak sayım, tam/kısmi sayım | `BR-STK-05` | `CONFIRMED` | Bölüm 5 | DRAFT durumunda saklanır |
| **Bölüm 4.4** | Sayım anında kasada satışa devam edebilme | `BR-STK-06` | `CONFIRMED` | Bölüm 5 | Kasa durdurulamaz |
| **Bölüm 4.4** | Sayımda tek cihaz düzenleme kilidi | `BR-STK-07` | `CONFIRMED` | Bölüm 5 | Diğerleri salt okunur inceler |
| **Bölüm 4.4** | Sayım onayı öncesi bekleyen sync kontrolü | `BR-STK-08` | `CONFIRMED` | Bölüm 5 | Kullanıcı uyarılır |
| **Bölüm 4.4** | Ara stok hareketlerinin matematiksel uzlaştırılması | `BR-STK-09` | `CONFIRMED` | Bölüm 5 | Ürün bazlı zaman damgası; algoritma PROPOSED |
| **Bölüm 4.4** | Sayım onayı değiştirilemezliği ve taslak iptali | `BR-STK-10` | `CONFIRMED` | Bölüm 5 | COMPLETED değiştirilemez, taslak iptal edilir |
| **Bölüm 4.4** | 9 farklı stok hareket türü ve gerekçe matrisi | `BR-STK-11` | `CONFIRMED` | Bölüm 5 | Gerekçe zorunluluk matrisi netleşti |
| **Bölüm 4.5** | Sepet kilitleme (tek cihaz düzenler, diğerleri salt okunur) | `BR-POS-06` | `CONFIRMED` | Bölüm 3 | Kilit devri desteklenir |
| **Bölüm 4.5** | Sepet kilidi 30 sn heartbeat, 2 dk timeout | `BR-POS-06` | `PROPOSED` | Bölüm 3 | Ağ/batarya testi bekliyor |
| **Bölüm 4.5** | Askıya alınan sepet kalıcılığı ve limitsiz sepet mantığı | `BR-POS-05` | `CONFIRMED` | Bölüm 3 | Sayfalama PROPOSED |
| **Bölüm 4.5** | Sepet snapshot'ı ve ekmek dahil manuel fiyat müdahalesi | `BR-POS-11` | `CONFIRMED` | Bölüm 3 | Gerekçe ve onay zorunlu |
| **Bölüm 4.5** | Satış tamamlanmadan stok düşmeme kuralı | `BR-POS-05`, `BR-POS-07` | `CONFIRMED` | Bölüm 3 | Atomik transaction şartı |
| **Bölüm 4.6** | Çevrimdışı fiyat değişikliği ve anında yerel kayıt | `BR-SYNC-05` | `CONFIRMED` | Bölüm 6 | Kuyruğa yazılır |
| **Bölüm 4.6** | Fiyat çakışmasında iki değerin korunması | `BR-SYNC-05` | `CONFIRMED` | Bölüm 6 | Sessizce ezilmez |
| **Bölüm 4.6** | Fiyat çakışmasında işletme sahibi kararı ve audit | `BR-SYNC-05` | `CONFIRMED` | Bölüm 6 | Karar audit_logs'a yazılır |
| **Bölüm 4.6** | Çakışma çözülene kadar son yerel fiyatın geçerliliği | `BR-SYNC-05` | `CONFIRMED` | Bölüm 6 | Kasayı durdurmama kuralı |
| **Bölüm 4.6** | Çevrimdışı satışların hiçbir koşulda silinmemesi | `BR-SYNC-06` | `CONFIRMED` | Bölüm 6 | Geçmiş korunur |
| **Bölüm 4.7** | Pilot kullanıcı kimlik doğrulama modeli | `BR-SEC-01` | `CONFIRMED` | Bölüm 7 | Kimlik altyapısı (Gelecek SaaS için Supabase Auth) |
| **Bölüm 4.7** | Pilot tek kullanıcı (işletme sahibi) | `BR-SEC-02` | `CONFIRMED` | Bölüm 7 | Personel hesapları MVP dışı |
| **Bölüm 4.7** | İlk girişte internet şartı, sonrasında offline çalışma | `BR-SEC-03` | `CONFIRMED` | Bölüm 7 | Şifreli yerel token |
| **Bölüm 4.7** | Cihaz iptali ve gecikmeli çevrimdışı yaptırım | `BR-SEC-04` | `CONFIRMED` | Bölüm 7 | İlk bağlantıda oturum düşer |
| **Bölüm 4.7** | Pilot cihaz sınırı (en fazla 3 aktif cihaz) | `BR-SEC-05` | `CONFIRMED` | Bölüm 7 | 1 PC + 2 Mobil |
| **Bölüm 4.7** | DPAPI / Keychain güvenli saklama ve 7 gün offline süresi | `BR-SEC-06` | `PROPOSED` | Bölüm 7 | Teknik tasarıma devredildi |
| **Bölüm 4.8** | Günlük otomatik yedek (30 gün saklama), olay sonrası ek yedek | `BR-BAK-01`, `BR-BAK-02` | `CONFIRMED` | Bölüm 9 | Satış başı yedek alınmaz |
| **Bölüm 4.8** | Bağımsız Google Drive OAuth modeli | `BR-BAK-04` | `CONFIRMED` / `PROPOSED` | Bölüm 9 | En dar scope kuralı |
| **Bölüm 4.8** | Geri yükleme öncesi koruyucu yedek | `BR-BAK-05` | `CONFIRMED` | Bölüm 9 | Safety snapshot |
| **Bölüm 4.8** | Geri yükleme sonrası yerel bekleyen işlemlerin korunması | `BR-BAK-06` | `PROPOSED` | Bölüm 9 | Kuyruklar silinmez, uzlaştırılır |
| **Bölüm 4.9** | Ürün görseli isteğe bağlılığı, PC/mobil yükleme | `BR-PROD-12` | `CONFIRMED` | Bölüm 2 | Görsel satışı engellemez |
| **Bölüm 4.9** | Görsel boyutlandırma (1200x1200 px, ~1 MB, JPEG/WebP) | `BR-PROD-12` | `PROPOSED` | Bölüm 2 | İstemci sıkıştırma önerisi |
| **Bölüm 4.10** | Satış başına tek ödeme (Nakit veya Kart) | `BR-PAY-01` | `CONFIRMED` | Bölüm 4 | Karma ödeme ve veresiye yok |
| **Bölüm 4.10** | Nakit para üstü hesabı ve eksik ödemede satış engeli | `BR-PAY-02`, `BR-PAY-03` | `CONFIRMED` | Bölüm 4 | Otomatik para üstü |
| **Bölüm 4.10** | Banka POS cihaz entegrasyonu dışılığı | `BR-PAY-04` | `CONFIRMED` / `OUT_OF_SCOPE` | Bölüm 4 | Donanıma tutar gitmez |
| **Bölüm 4.10** | Ödeme yöntemi düzeltme işlemi ve audit kaydı | `BR-PAY-05` | `CONFIRMED` | Bölüm 4 | Ciroya doğrudan yansır |
| **Bölüm 4.11** | Pilot tek tenant + tek şube | `BR-TNT-01` | `CONFIRMED` | Bölüm 8 | Tek market pilotu |
| **Bölüm 4.11** | Geleceğe hazır veri modeli (`tenant_id`, `store_id`), API İzolasyonu | `BR-TNT-02`, `BR-TNT-03` | `CONFIRMED` | Bölüm 8 | Pilot API filtreleme, Gelecek SaaS RLS |
| **Bölüm 4.11** | Şubeye özel fiyat geçersiz kılma | `BR-TNT-04` | `OUT_OF_SCOPE` / `PROPOSED` | Bölüm 8 | Gelecekte desteklenecek |
| **Bölüm 4.12** | Zaman dilimi, takvim günü (`Europe/Istanbul`) ve Pazartesi başlangıçlı hafta | `BR-REP-01` | `CONFIRMED` | Bölüm 10 | UTC saklama, yerel gösterim |
| **Bölüm 4.12** | Net satış ayrımı ($\text{Brüt} - \text{İadeler}$), iptal satışı ciro dışılığı | `BR-REP-02` | `CONFIRMED` | Bölüm 10 | Finansal kavram ayrımı |
| **Bölüm 4.12** | Nakit ve Kredi Kartı hasılat ayrımı, iadelerin ödeme türünden düşümü | `BR-REP-03` | `CONFIRMED` | Bölüm 10 | İade orijinal ödeme türünden düşer |
| **Bölüm 4.12** | Miktar ve ciro bazlı ayrı en çok satanlar, birim ayrımı | `BR-REP-04` | `CONFIRMED` | Bölüm 10 | İade düşümü, birim gruplama |
| **Bölüm 4.12** | Yalnızca maliyetli ürünlerde brüt kâr, eksik maliyet uyarısı | `BR-REP-05` | `CONFIRMED` | Bölüm 10 | Net kâr MVP dışı |
| **Bölüm 4.12** | Çevrimdışı rapor veri eksikliği uyarısı, XLSX/PDF export | `BR-REP-06`, `BR-REP-07` | `CONFIRMED` | Bölüm 10 | Yerel veri uyarısı |
| **Bölüm 3 & 4** | Tam Satış İptali (zaman sınırsız, gerekçe ve açık onayla) | `BR-POS-08` | `CONFIRMED` | Bölüm 3 | Zaman sınırı kaldırıldı |
| **Bölüm 3 & 4** | Kısmi İade (miktar sınırı, snapshot fiyat, orijinal ödeme) | `BR-POS-09` | `CONFIRMED` | Bölüm 3 | Ayrı iş akışı olarak tanımlandı |
| **Bölüm 3 & 4** | İade edilen ürünün durumu (Satılabilir vs. Hasarlı/Fire) | `BR-POS-10` | `CONFIRMED` | Bölüm 3 | Hasarlı satılabilir stoğa girmez |
| **Bölüm 3 & 4** | Fiyat ve maliyet değişiklik geçmişi (`price_history`, `cost_history`) | `BR-PROD-13` | `CONFIRMED` | Bölüm 2 | Geçmiş satışları etkilemez |
| **Bölüm 3 & 4** | Hiyerarşik kategori yapısı ve kategori yaşam döngüsü | `BR-PROD-14` | `CONFIRMED` | Bölüm 2 | Ürünü olan kategori silinemez |
| **Bölüm 3 & 4** | Barkod yaşam döngüsü, `barcode_history` tekillik ve yeniden kullanılamama | `BR-PROD-15` | `CONFIRMED` | Bölüm 2 | Eski barkod başka ürüne devredilemez |
| **Bölüm 3 & 4** | Ürün kataloğunu XLSX olarak dışa aktarma (pasifler dahil) | `BR-PROD-16` | `CONFIRMED` | Bölüm 2 | Standart şablonla dışa aktarım |

---

## 13. Faz 0 Kabul Durumu ve Sonraki Adımlar

- Bu şartname `MARKET_POS_AI_STUDIO_BUILD_PLANI.md` (v1.2.2) ve `docs/requirements/PHASE_0_BUSINESS_DISCOVERY.md` (v1.3) ile tam tutarlıdır.
- İş kuralları şartnamesi v1.2 düzeyinde kesinleştirilmiştir.
- **Faz 0 ve Faz 1.1 tamamlanmıştır.** Faz 1.2 (Kasa Satış Ekranı & Sepet Yönetimi) uygulamasına geçmeden önce aktif DT-01 alt aşamalarının tamamlanması ve kullanıcıdan açık onay alınması esastır.
