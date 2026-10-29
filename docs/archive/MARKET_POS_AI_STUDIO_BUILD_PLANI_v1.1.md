# MARKET POS — Proje Ana Planı ve Mimari Dokümanı

**Versiyon:** 1.1  
**Tarih:** 29 Ekim 2026  
**Durum:** Faz 0 — Planlama ve mimari kararlar  
**Geliştirme durumu:** Henüz uygulama kodu yazılmayacak  
**Pilot:** Arkadaşın marketi  
**Uzun vadeli hedef:** Birden fazla markete satılabilecek ticari SaaS ürünü

---

## 1. Proje vizyonu

Küçük ve orta ölçekli marketlerin ürün, kategori, fiyat, stok ve satış işlemlerini tek bir sistemden yönetebildiği; internet kesintilerinde yerel olarak çalışmaya devam eden; birden fazla cihazla çevrimdışı işlem yapabilen; modern ve ticari olarak ölçeklenebilir bir market yönetim sistemi geliştirilecektir.

Proje basit bir CRUD uygulaması olarak ele alınmayacaktır. İlk pilotta gereksiz karmaşıklıktan kaçınılacak, ancak sonraki aşamalarda yeni modüllerin eklenmesini, birden fazla marketin sisteme katılmasını ve uygulamanın uzaktan güncellenmesini destekleyecek bir mimari kurulacaktır.

### 1.1 Hedefler

- Kategori ve ürün yönetimi.
- Barkod okuyucuyla ürün kaydı ve satış.
- Open Food Facts üzerinden ürün bilgilerinin öneri olarak alınması.
- Satış fiyatı, maliyet, birim, gramaj ve stok takibi.
- Satış, sepet ve stok hareketleri.
- Windows, Android, iOS ve uygun web istemcileri.
- İnternet bağlantısı olmadığında yerel çalışma.
- Birden fazla cihazdan çevrimdışı işlem yapabilme.
- Bağlantı geldiğinde güvenli ve otomatik senkronizasyon.
- Market sahibine yönelik kapsamlı dashboard.
- Supabase ve Google Drive üzerinden otomatik yedekleme.
- Çoklu market SaaS altyapısı.
- Uzaktan güncelleme ve sürdürülebilir ürün geliştirme.
- Pilot kullanım sonrası ticari satış.

### 1.2 Temel mimari kararlar

| Konu | Karar |
|---|---|
| Uygulama | Flutter |
| Yerel veritabanı | Drift + SQLite; platforma özel depolama doğrulaması |
| Merkezi veritabanı | Supabase PostgreSQL |
| Kimlik doğrulama | Supabase Auth |
| Yerel veri erişimi | Repository arayüzleri |
| Durum yönetimi | Riverpod |
| Navigasyon | go_router |
| Barkod | USB HID okuyucu ve mobil kamera |
| Ürün bilgisi | Open Food Facts API |
| Mimari | Feature-first + Clean Architecture |
| Kod kalitesi | SOLID, Clean Code, otomatik testler |
| Senkronizasyon | Ayrı modül, kalıcı işlem kuyruğu ve çakışma yönetimi |
| Yedekleme | Supabase tarafı + Google Drive'a bağımsız yedek |
| Dağıtım | Platforma özel güncelleme stratejisi |
| Pilot yaklaşımı | Tek markette gerçek kullanım, çoklu market mimarisi |

---

## 2. Ürün kapsamı ve öncelikler

### 2.1 İlk sürümdeki temel özellikler

**Ürün ve kategori yönetimi**

- Kategori oluşturma, listeleme, güncelleme ve pasifleştirme.
- Barkodla ürün arama ve kayıt.
- Ürün adı, marka, kategori ve açıklama.
- Satış fiyatı ve isteğe bağlı maliyet fiyatı.
- Gramaj, ağırlık, hacim ve ölçü birimi.
- Stok miktarı ve kritik stok eşiği.
- Birden fazla barkodun aynı ürüne bağlanabilmesi.
- Ürünleri düzenleme ve geçmiş kayıtları bozmadan pasifleştirme.
- Open Food Facts ile ürün bilgisi önerme.
- API'de bulunmayan ürünleri manuel kaydetme.

**Stok yönetimi**

- Başlangıç stoğu tanımlama.
- Stok girişi ve çıkışı.
- Satışla otomatik stok düşme.
- İade ve stok düzeltme hareketleri.
- Kritik stok takibi.
- Stok hareketi geçmişi.

**Satış ve POS**

- Barkod okutunca ürünün bulunması.
- Ürün adı, fiyatı ve ölçü biriminin gösterilmesi.
- Sepete ürün ekleme ve çıkarma.
- Miktar ve toplam fiyat hesaplama.
- Satış tamamlama ve stok hareketi oluşturma.
- Satış geçmişini görüntüleme.
- POS cihazına tutarın ilk sürümde elle girilmesi.
- Satış işlemlerinin çevrimdışı kaydedilebilmesi.

**Dashboard**

- Günlük, haftalık ve aylık satış özeti.
- Satış adedi ve satış tutarı.
- Kritik stoklar.
- En çok satılan ürünler.
- Son satışlar ve stok hareketleri.
- Fiyat değişiklikleri.
- Cihazların bağlantı ve senkronizasyon durumu.
- Son başarılı yedekleme bilgisi.

### 2.2 Pilot öncesi zorunlu altyapı

- Çoklu market veri izolasyonu.
- Yerel veritabanı ve migration sistemi.
- Kalıcı çevrimdışı işlem kuyruğu.
- Tekrarlanan satış işlemlerine karşı idempotency.
- Çakışma tespiti ve çözüm kuralları.
- Temel kullanıcı kimlik doğrulama ve yetkilendirme.
- Otomatik yedekleme ve geri yükleme testi.
- Kritik işlemlere ilişkin audit kayıtları.
- Birim ve entegrasyon testleri.

### 2.3 Sonraki sürümlere bırakılabilecek özellikler

- Ingenico veya benzeri POS cihazlarına tutar gönderme.
- Termal fiş yazıcısı.
- Tartı entegrasyonu.
- Gelişmiş satış ve kârlılık raporları.
- E-fatura/e-arşiv entegrasyonu.
- Gelişmiş kullanıcı ve şube yetkilendirme ekranları.
- Abonelik ve lisans yönetimi.
- Çoklu dil desteği.
- Gelişmiş analitik.

Ödeme cihazları ve mali belgelerle ilgili özellikler, Türkiye'deki güncel mevzuat ve ilgili sağlayıcıların teknik şartları ayrıca doğrulandıktan sonra ele alınacaktır.

---

## 3. Çoklu market SaaS mimarisi

İlk pilot yalnızca bir markette yapılacak olsa da sistemin veri modeli en baştan birden fazla marketi destekleyecektir.

### 3.1 Temel kavramlar

- **Tenant:** Sisteme müşteri olarak katılan işletme veya market grubu.
- **Store:** Tenant'a bağlı fiziksel market veya şube.
- **User:** Sisteme giriş yapan kullanıcı.
- **Membership:** Kullanıcının hangi tenant veya şubede hangi yetkilere sahip olduğunu belirleyen ilişki.
- **Device:** Windows bilgisayar, telefon veya tablet gibi uygulamayı çalıştıran cihaz.

Her iş kaydı doğru tenant ve gerektiğinde şube ile ilişkilendirilecektir.

### 3.2 Veri izolasyonu

- Tenant'a ait veriler tenant kimliğiyle ilişkilendirilecek.
- Ürün, kategori, stok, satış ve kullanıcı ilişkileri yetki sınırları içinde doğrulanacak.
- Supabase RLS politikaları uygulanacak ve test edilecek.
- İstemci tarafından gönderilen tenant kimliği tek başına yetki kanıtı sayılmayacak.
- Farklı marketlerin verilerini okuyup değiştirmeye yönelik güvenlik testleri yapılacak.

İlk pilotta tek tenant kullanılması, sistemin tek tenant olarak tasarlanacağı anlamına gelmeyecektir.

---

## 4. Offline-first ve çoklu cihaz stratejisi

### 4.1 Temel karar

Windows bilgisayar, telefon ve tabletler kendi yerel veritabanlarında işlem yapabilecek. İnternet bağlantısı kesildiğinde ürün arama, uygun yerel ürün bilgileriyle satış ve işlem kaydı mümkün olacaktır.

Bağlantı geri geldiğinde cihazların bekleyen işlemleri merkezi veritabanına aktarılacaktır.

### 4.2 Yerel veri akışı

1. Kullanıcı işlemi başlatır.
2. İş kuralı doğrulamaları yerel olarak yapılır.
3. İşlem yerel veritabanına kalıcı biçimde kaydedilir.
4. Aynı işlem için senkronizasyon kaydı oluşturulur.
5. Senkronizasyon servisi işlemi buluta göndermeyi dener.
6. Başarılı işlem senkronize olarak işaretlenir.
7. Başarısız işlem tekrar denenir veya çakışma kuyruğuna alınır.

İşlem kaydı ile senkronizasyon kuyruğunun oluşturulması mümkün olduğunca aynı yerel veritabanı işlemi içinde gerçekleştirilmelidir.

### 4.3 Çoklu cihazın sınırları

Birden fazla cihaz internetten tamamen kopuksa her cihaz diğer cihazların yaptığı satışları bilemez. Bu nedenle bağımsız çevrimdışı cihazlarda stok miktarının tüm market genelinde her an doğru kalacağı garanti edilemez.

Örneğin, bir üründen bir adet kaldığında iki cihaz da çevrimdışıyken bu ürünü satabilir. Bağlantı geldiğinde iki satış da geçmişte gerçekleşmiş işlem olarak korunmalı; stok uyuşmazlığı belirlenmeli ve çözüm için kayıt oluşturulmalıdır.

**Kurallar:**

- Satış kayıtları yalnızca stok çakışması nedeniyle silinmeyecek.
- Her satışın benzersiz bir işlem kimliği olacak.
- Aynı satışın tekrar gönderilmesi ikinci satış oluşturmayacak.
- Stok hareketleri geçmişi korunacak.
- Çakışma tespitleri audit kayıtlarına alınacak.
- Gerekli durumlarda stok düzeltmesi veya yetkili kullanıcı müdahalesi istenecek.
- Ürün fiyatı ve ürün bilgisi değişikliklerinde güncellik bilgisi izlenecek.
- Senkronizasyon hataları kullanıcıdan gizlenmeyecek.

### 4.4 Senkronizasyon teknolojisi

İlk tercih Flutter ekosistemiyle uyumlu yerel veri erişimi olarak Drift ve SQLite'tır. Senkronizasyon katmanı ise uygulamanın kendi modülü olarak tasarlanacaktır.

PowerSync gibi bir çözüm, prototip ve teknik doğrulama sırasında değerlendirilebilir. Ancak ürün, stok ve satış işlemlerinin gerektirdiği tutarlılık kuralları doğrulanmadan ek bir senkronizasyon altyapısı seçilmeyecektir.

RxDB veya PouchDB, Flutter uygulamasına otomatik olarak eklenmeyecek; farklı bir teknoloji yığınının getireceği maliyet ve karmaşıklık ayrıca değerlendirilmeden kullanılmayacaktır.

### 4.5 Platform farklılıkları

Drift + SQLite mobil ve masaüstünde temel yerel depolama yaklaşımıdır. Web için tarayıcı tabanlı depolama ve gerekli SQLite/WebAssembly yapılandırması ayrıca doğrulanacaktır.

Windows, Android, iOS ve web'in aynı yerel depolama mekanizmasını hiçbir değişiklik yapmadan kullanacağı varsayılmayacaktır. Repository arayüzleri ortak tutulacak, platforma özel ayrıntılar data katmanında izole edilecektir.

---

## 5. Yedekleme ve veri kurtarma

Yedekleme, senkronizasyonun alternatifi değildir. Her ikisi de ayrı mekanizmalar olarak tasarlanacaktır.

### 5.1 Yedekleme hedefleri

1. Supabase/PostgreSQL tarafındaki yedekleme olanakları kullanılacak.
2. Google Drive'a bağımsız ve otomatik yedekler alınacak.
3. Yedekleme geçmişi tutulacak.
4. Son başarılı yedekleme zamanı gösterilecek.
5. Başarısız yedeklemeler izlenecek ve bildirilecek.
6. Yedekler belirlenen saklama politikasına göre yönetilecek.
7. Düzenli geri yükleme testleri yapılacak.

Supabase'in otomatik yedekleme imkânları plan ve hizmet koşullarına bağlıdır. Bu nedenle yalnızca sağlayıcının sunduğu otomatik yedeklemeye güvenilmeyecek; harici yedekleme politikası ayrıca uygulanacaktır.

### 5.2 Google Drive yaklaşımı

- Yedekler otomatik olarak üretilecek ve yükleme sonucu kaydedilecek.
- Yedekler mümkünse şifrelenecek.
- Google hesabı yetkilendirmesi güvenli şekilde yönetilecek.
- OAuth erişim bilgileri kaynak koduna yazılmayacak.
- Yedekleme sırasında kesinti olursa işlem güvenli şekilde tekrar denenebilecek.
- Dosya sürümü, oluşturulma zamanı ve bütünlük bilgisi izlenecek.
- Yedekten geri yükleme adımları belgelenecek.

Google Drive tek başına tüm verilerin her koşulda yedeklendiğini garanti etmez. Yedekleme işleminin başarılı olduğu doğrulanmalı ve geri yükleme ile kullanılabilir olduğu test edilmelidir.

### 5.3 Yerel veri kurtarma

Çevrimdışı satışlar henüz buluta ulaşmamış olabilir. Bu nedenle cihazda bekleyen işlemler de korunmalıdır. Yerel veritabanı bozulması, cihaz kaybı ve senkronizasyon hataları için kurtarma senaryoları hazırlanacaktır.

---

## 6. Open Food Facts ve barkod yönetimi

### 6.1 Ürün kaydı

1. Barkod okutulur.
2. Önce yerel ürün kataloğunda arama yapılır.
3. Ürün bulunursa mevcut ürün bilgileri gösterilir.
4. Ürün bulunamazsa internet varsa Open Food Facts sorgulanır.
5. API'den dönen alanlar kullanıcıya öneri olarak sunulur.
6. Market sahibi bilgileri doğrular ve düzenler.
7. Satış fiyatı ve stok gibi işletmeye özel bilgiler girilir.
8. Ürün yerel veritabanına kaydedilir ve senkronizasyon kuyruğuna eklenir.

### 6.2 Ürün verisinin sorumluluğu

Open Food Facts ürün adı, marka, kategori, görsel, miktar veya benzeri bilgileri sağlayabilir; ancak her ürünün tüm alanlarının mevcut veya doğru olacağı garanti edilmez.

- Satış fiyatı marketin kendi fiyatıdır.
- Stok miktarı marketin kendi stok verisidir.
- Kategori, marketin kategori yapısıyla eşleştirilmelidir.
- API verisi market sahibinin onayı olmadan kritik işletme verilerinin üzerine yazmamalıdır.
- Ürün bulunamazsa manuel kayıt yapılabilmelidir.
- API kullanım koşulları, atıf ve lisans gereksinimleri entegrasyon sırasında kontrol edilmelidir.

### 6.3 Barkod modeli

Barkodlar ayrı bir ilişki yapısıyla yönetilmeye uygun tasarlanacaktır. Böylece gerektiğinde bir ürüne birden fazla barkod bağlanabilecek ve mükerrer barkod kayıtları kontrol edilebilecektir.

USB barkod okuyucu klavye benzeri giriş sağlayan cihaz olarak desteklenecek; mobil kamerayla barkod okuma da ayrıca uygulanacaktır.

---

## 7. Veri modeli

Aşağıdaki tablo listesi başlangıç modelidir. Kesin alanlar, ilişkiler ve kısıtlar Faz 0 sonunda belirlenecektir.

### 7.1 Temel tablolar

**tenant / store / user / membership / device**

- Tenant, şube, kullanıcı, yetki ve cihaz ilişkileri.
- Tenant ve şube izolasyonu.
- Cihaz kimliği ve son senkronizasyon bilgileri.

**categories**

- id
- tenant_id
- name
- parent_id
- is_active
- created_at
- updated_at

**products**

- id
- tenant_id
- name
- brand
- category_id
- sale_price
- cost_price
- unit
- net_quantity
- net_quantity_unit
- description
- image_url
- minimum_stock_level
- is_active
- created_at
- updated_at

**product_barcodes**

- id
- tenant_id
- product_id
- barcode
- barcode_type
- is_primary
- created_at

**stock_balances**

- product_id
- store_id
- quantity
- updated_at

**stock_movements**

- id
- tenant_id
- store_id
- product_id
- movement_type
- quantity_delta
- reference_type
- reference_id
- note
- created_at
- device_id

**sales**

- id
- tenant_id
- store_id
- device_id
- cashier_id
- idempotency_key
- total_amount
- status
- payment_method
- created_at

**sale_items**

- id
- sale_id
- product_id
- quantity
- unit_price
- total_price
- product_name_snapshot
- unit_snapshot

**price_history**

- id
- tenant_id
- product_id
- previous_price
- new_price
- changed_by
- changed_at

**sync_operations**

- id
- device_id
- operation_id
- entity_type
- entity_id
- operation_type
- payload
- status
- retry_count
- created_at
- last_attempt_at

**audit_logs**

- id
- tenant_id
- user_id
- device_id
- action
- entity_type
- entity_id
- created_at

**backup_runs**

- id
- backup_type
- destination
- status
- started_at
- completed_at
- error_summary

### 7.2 Veri modeli kuralları

- Para değerleri uygun kesinlikte sayısal tiplerle tutulacaktır; kayan noktalı sayılarla para hesabı yapılmayacaktır.
- Miktar ve birimler ürün tipine uygun doğrulanacaktır.
- Satış satırları, satış anındaki fiyat ve ürün bilgilerini koruyacaktır.
- Stok hareketleri geçmişi sonradan sessizce değiştirilmemelidir.
- Ürün silme işlemi, geçmiş satışların bağlantılarını bozmamalıdır.
- Kritik işlemler transaction içinde gerçekleştirilmelidir.
- Aynı satışın tekrar işlenmesi idempotency ile engellenmelidir.
- Tenant'a özgü benzersizlik kuralları ve yabancı anahtarlar tanımlanmalıdır.
- Güncel stok değeri, stok hareketleriyle tutarlı olacak şekilde yönetilmelidir.

---

## 8. Mimari ve kod organizasyonu

Proje feature-first ve Clean Architecture yaklaşımıyla geliştirilecektir.

Önerilen başlangıç yapısı:

```text
lib/
├── app/
│   ├── router/
│   ├── theme/
│   └── bootstrap/
├── core/
│   ├── errors/
│   ├── result/
│   ├── network/
│   ├── logging/
│   └── shared/
├── features/
│   ├── auth/
│   ├── tenants/
│   ├── stores/
│   ├── devices/
│   ├── categories/
│   ├── products/
│   ├── inventory/
│   ├── sales/
│   ├── dashboard/
│   ├── sync/
│   ├── backup/
│   └── settings/
├── infrastructure/
│   ├── database/
│   ├── supabase/
│   └── platform/
└── main.dart
```

Her feature kendi içinde gerektiğinde şu katmanlara ayrılacaktır:

- **domain:** Entity, value object, repository arayüzü ve iş kuralları.
- **data:** Repository implementasyonları, yerel/bulut veri kaynakları, DTO ve eşlemeler.
- **presentation:** Ekranlar, widget'lar ve kullanıcı etkileşimleri.

Her özellik için aynı sayıda sınıf veya use case üretmek zorunlu değildir. Katmanlar gerçek bir sorumluluk ayrımı sağlamak için kullanılacak, gereksiz soyutlamalardan kaçınılacaktır.

### 8.1 SOLID ve Clean Code

- Her sınıf tek ve açık bir sorumluluğa sahip olmalıdır.
- Domain katmanı Flutter widget'larına ve Supabase istemcisine doğrudan bağımlı olmamalıdır.
- Veri erişimi repository arayüzleri üzerinden yürütülmelidir.
- İş kuralları ekranların içine gömülmemelidir.
- Bağımlılıklar mümkün olduğunca dış katmanlardan iç katmanlara yönelmelidir.
- İsimlendirme açık ve tutarlı olmalıdır.
- Test edilebilirlik mimari kararların bir parçasıdır.
- CRUD işlemleri yalnızca veritabanı çağrısı olarak değil, gerekli doğrulama ve iş kurallarıyla birlikte tasarlanmalıdır.

---

## 9. Tasarım ve kullanıcı deneyimi

Uygulama, market ortamında hızlı ve hataya dayanıklı kullanım için tasarlanacaktır.

- Türkçe arayüz.
- Windows, tablet ve telefon ekranlarına uyumlu responsive tasarım.
- Dokunmaya uygun büyük işlem alanları.
- Barkod okuma için hızlı ve kesintisiz akış.
- Klavye ve USB barkod okuyucu kullanımına uygun masaüstü deneyimi.
- Açık ve koyu tema desteği.
- Hata, bağlantı kaybı ve bekleyen senkronizasyon durumlarının görünür olması.
- Ürün ekleme ve fiyat değiştirme işlemlerinde hızlı erişim.
- Satış sırasında gereksiz ekran geçişlerinin azaltılması.
- Erişilebilirlik ve okunabilirlik.

Hazır, birbirine benzeyen yapay zekâ üretimi yönetim paneli şablonları kullanılmayacaktır. Tasarım gerçek market iş akışlarına, kullanıcı geri bildirimlerine ve kullanım testlerine göre şekillendirilecektir.

---

## 10. Güvenlik

- Supabase Row Level Security politikaları uygulanacaktır.
- Yetki kontrolleri hem arayüzde hem sunucu/veritabanı sınırında ele alınacaktır.
- Gizli anahtarlar kaynak koduna gömülmeyecektir.
- Google Drive OAuth bilgileri güvenli saklanacaktır.
- Hassas işlemler audit kayıtlarıyla izlenecektir.
- Gerekli işlemlerde kullanıcı onayı alınacaktır.
- Yedekler için şifreleme ve erişim kontrolü uygulanacaktır.
- Tenant izolasyonu otomatik testlerle doğrulanacaktır.
- Bağımlılıklar ve güvenlik güncellemeleri düzenli kontrol edilecektir.
- Silme, iade, stok düzeltme ve satış tamamlama gibi kritik işlemlerde iş kuralları zorunlu olacaktır.

Flutter, Drift ve Supabase kullanımı tek başına uygulamanın güvenli olduğunu garanti etmez. Güvenlik ayrı bir gereksinim ve test alanıdır.

---

## 11. Uzaktan güncelleme ve dağıtım

Uygulamanın kod güncellemeleri ve işletme verilerinin senkronizasyonu ayrı konular olarak ele alınacaktır.

- **Web:** Sunucuya yeni sürüm dağıtımı ve istemci önbelleği yönetimi.
- **Windows:** Paketleme ve kontrollü uygulama güncelleme mekanizması.
- **Android/iOS:** İlgili platformların yayın ve güncelleme kurallarına uygun dağıtım.
- **Veritabanı:** Sürümlendirilmiş migration'lar.
- **Sunucu tarafı:** Geri alınabilir ve izlenebilir dağıtım süreci.

Her güncelleme mevcut yerel verileri bozmamalıdır. Veritabanı şema değişiklikleri ve uygulama sürümleri arasındaki uyumluluk test edilmelidir.

---

## 12. Test stratejisi

**Unit testleri**

- Ürün doğrulamaları.
- Fiyat ve toplam hesaplama.
- Stok hareketleri.
- Satış iş kuralları.
- Yetki ve tenant kuralları.
- Çakışma çözümü.

**Entegrasyon testleri**

- Drift işlemleri ve migration'lar.
- Supabase veri erişimi.
- Senkronizasyon kuyruğu.
- Idempotency.
- Yedekleme ve geri yükleme.

**Uçtan uca testler**

- Barkodla ürün kaydı.
- Ürün ve kategori CRUD.
- Satış ve stok düşme.
- İnternet kesilmesi ve bağlantının geri gelmesi.
- Birden fazla cihazdan aynı ürüne ilişkin satışlar.
- Tenant izolasyonu.
- Bozuk veya yarım kalmış senkronizasyon.
- Yedekten geri yükleme.

Başarılı bir pilot için yalnızca normal koşullar değil, hata ve kesinti senaryoları da test edilmelidir.

---

## 13. Güncellenmiş geliştirme yol haritası

### Faz 0 — Planlama ve mimari kararlar

- [x] Temel ürün vizyonunun belirlenmesi.
- [x] İlk sürüm özelliklerinin belirlenmesi.
- [x] Çoklu cihazın yerel çalışma modeli.
- [x] Çoklu market SaaS kararı.
- [x] Supabase + Google Drive yedekleme hedefi.
- [ ] Kesin veri modeli ve ilişkiler.
- [ ] Tenant ve şube izolasyonu kuralları.
- [ ] Ürün birimleri ve barkod kuralları.
- [ ] Satış ve stok iş kuralları.
- [ ] Offline çakışma çözümü.
- [ ] Yedekleme sıklığı, saklama politikası ve geri yükleme prosedürü.
- [ ] Windows, mobil ve web için depolama doğrulaması.
- [ ] Dağıtım ve güncelleme yaklaşımı.
- [ ] Faz 0 kabul kriterlerinin tamamlanması.

**Faz 0 tamamlanmadan ürün kodlamasına başlanmayacaktır.**

### Faz 1 — Temel altyapı

- Flutter proje iskeleti.
- Katman ve modül sınırları.
- Drift ve migration sistemi.
- Riverpod ve go_router.
- Hata yönetimi ve logging.
- Tema ve ortak UI bileşenleri.
- Otomatik test altyapısı.

### Faz 2 — Kimlik, tenant ve cihazlar

- Supabase Auth.
- Tenant ve store modeli.
- Kullanıcı üyelikleri ve temel yetkiler.
- Cihaz kaydı.
- Tenant izolasyonu ve güvenlik testleri.

### Faz 3 — Ürün ve kategori yönetimi

- Kategori CRUD.
- Ürün CRUD.
- Barkod okuma.
- Open Food Facts entegrasyonu.
- Birim ve gramaj yönetimi.
- Fiyat düzenleme ve fiyat geçmişi.
- Stok görüntüleme.
- Pasifleştirme ve veri doğrulamaları.

### Faz 4 — Stok ve satış

- Sepet.
- Barkodla satış.
- Toplam hesaplama.
- Satış tamamlama.
- Stok hareketleri.
- Satış geçmişi.
- Tekrarlanan işlemlere karşı idempotency.

### Faz 5 — Offline ve senkronizasyon

- Yerel işlem kuyruğu.
- Otomatik senkronizasyon.
- Tekrar deneme politikası.
- Çakışma tespiti.
- Çoklu cihaz senaryoları.
- Senkronizasyon durumu arayüzü.
- Veri kurtarma testleri.

### Faz 6 — Dashboard ve yedekleme

- Satış ve stok dashboard'u.
- Kritik stoklar.
- İşlem geçmişi.
- Cihaz durumu.
- Supabase yedekleme yapılandırması.
- Google Drive otomatik yedekleme.
- Yedekleme geçmişi.
- Geri yükleme ve bütünlük testleri.

### Faz 7 — Pilot

- Arkadaşın marketinde kontrollü kurulum.
- Gerçek ürün ve barkod verileriyle kullanım.
- Elektrik ve internet kesintisi senaryoları.
- Çoklu cihaz satış testleri.
- Kullanıcı geri bildirimleri.
- Performans, güvenlik ve kullanılabilirlik iyileştirmeleri.

### Faz 8 — Ticari hazırlık

- Paketleme ve kurulum.
- Platforma uygun güncelleme sistemi.
- Müşteri ve abonelik yönetimi.
- İzleme ve hata raporlama.
- Teknik ve kullanıcı dokümantasyonu.
- Destek ve yedekleme prosedürleri.
- Pilot sonrası ticari fiyatlandırma ve satış planı.

---

## 14. Faz 0 kabul kriterleri

Faz 0 tamamlandığında aşağıdaki soruların dokümante edilmiş cevapları bulunmalıdır:

1. Bir tenant, store, user ve device arasındaki ilişkiler nelerdir?
2. Ürün, barkod, kategori ve ölçü birimi nasıl modellenir?
3. Satış tamamlandığında stok nasıl güncellenir?
4. Aynı satışın iki kez senkronize edilmesi nasıl engellenir?
5. Birden fazla çevrimdışı cihazın stok çakışmaları nasıl tespit edilir ve çözülür?
6. Yerel veri ve senkronizasyon kuyruğu nasıl korunur?
7. Web ve diğer platformlarda hangi yerel depolama yaklaşımı kullanılacaktır?
8. Supabase ve Google Drive yedekleri hangi sıklıkla alınacaktır?
9. Yedeklerin başarıyla alındığı ve geri yüklenebildiği nasıl doğrulanacaktır?
10. Tenant izolasyonu ve yetkilendirme nasıl test edilecektir?
11. Uygulama ve veritabanı güncellemeleri nasıl dağıtılacaktır?
12. Pilotun başarılı sayılması için ölçülebilir kriterler nelerdir?

---

## 15. Değişmez proje kuralları

- Bu doküman projenin ana referansıdır.
- Kod yazmadan önce ilgili modülün iş kuralları ve katman sınırları belirlenir.
- Clean Architecture ve SOLID ilkeleri uygulanır; gereksiz soyutlama yapılmaz.
- Offline-first davranışı korunur.
- Kritik işlemler idempotent ve test edilebilir olur.
- Tenant izolasyonu bütün iş modüllerinde uygulanır.
- Yedekleme ve geri yükleme ayrı ayrı test edilir.
- Gizli bilgiler kaynak koduna yazılmaz.
- Ürün ve satış geçmişi korunur.
- Kod, şema veya mimari kararları değiştiğinde doküman güncellenir.
- Yapay zekâ araçları değişse bile aynı proje kuralları geçerlidir.
- Her fazın kabul kriterleri karşılanmadan sonraki faza geçilmez.

---

## 16. Sonraki adım

**Bir sonraki çalışma: Faz 0 — İş kuralları ve veri modeli.**

Bu aşamada henüz kod yazılmayacak. Öncelikle ürün, barkod, kategori, stok, satış, tenant, cihaz, senkronizasyon ve yedekleme modellerinin kesinleştirilmesi; ardından kararların ve kabul kriterlerinin dokümante edilmesi hedeflenmektedir.

Bu çalışma tamamlandığında mimari kararlar uygulanabilir bir teknik tasarıma dönüştürülecek ve Faz 1'e geçiş için gerekli şartlar netleşecektir.
