# MARKET POS — Market Management System (MMS)
## Proje Ana Planı ve Mimari Dokümanı

**Versiyon:** 1.4 (Mimari ve Faz 1.1 Mutabakatı)  
**Tarih:** 6 Kasım 2026  
**Durum:** Faz 1 — MVP Uygulama ve Doğrulama  
**Geliştirme durumu:** Faz 1.1 Windows Client Foundation tamamlandı ve kabul edildi; DT-01.3 teknik çalışması tamamlandı (proje sahibi kabulü bekleniyor).  
**Teknik Proje / Klasör Adı:** `market-pos`  
**Ürün Tanımı:** Market Management System (MMS) — Profesyonel Market Yönetim SaaS Uygulaması  
**Pilot:** Arkadaşın marketi  
**Uzun vadeli hedef:** Birden fazla markete satılabilecek ticari SaaS ürünü

---

## 1. Proje vizyonu

Küçük ve orta ölçekli marketlerin ürün, kategori, fiyat, stok, satış, dashboard, raporlama, kullanıcı yönetimi ve yedekleme süreçlerini tek bir entegre sistemden yönetebildiği; internet kesintilerinde yerel olarak çalışmaya devam eden; birden fazla cihazla (Windows bilgisayar ve telefon/tablet) tam işlevli çevrimdışı işlem yapabilen; modern ve ticari olarak ölçeklenebilir bir **Market Management System (MMS)** geliştirilecektir.

Proje, yalnızca kasada barkod okutup fiş kesen dar kapsamlı bir CRUD/POS uygulaması olarak ele alınmayacaktır. `market-pos` teknik adı korunmakla birlikte, ürünün kendisi uçtan uca bir market yönetim SaaS platformudur. İlk pilotta gereksiz karmaşıklıktan kaçınılacak, ancak sonraki aşamalarda yeni modüllerin eklenmesini, birden fazla marketin sisteme katılmasını ve uygulamanın uzaktan güncellenmesini destekleyecek sağlam bir mimari kurulacaktır.

### 1.1 Hedefler

- Kategori ve ürün yönetimi (Windows ve mobilde tam yetki).
- Barkod okuyucuyla hızlı ürün kaydı ve satış (PC'de USB HID, telefonda kamera).
- Open Food Facts üzerinden ürün bilgilerinin öneri olarak alınması ve doğrulanması.
- Satış fiyatı, maliyet, birim, gramaj ve hassas stok takibi.
- Hızlı satış, dinamik sepet ve izlenebilir stok hareketleri.
- Windows, Android, iOS ve uygun web istemcileri.
- İnternet bağlantısı olmadığında yerel çalışma (Offline-first).
- Birden fazla cihazdan (PC ve telefon) bağımsız çevrimdışı işlem yapabilme.
- Bağlantı geldiğinde güvenli, idempotent ve otomatik senkronizasyon.
- Market sahibine yönelik kapsamlı, ciro/kâr ayrımı net dashboard ve raporlama.
- Windows Master Hub SQLite ve Google Drive üzerinden otomatik bağımsız yedekleme.
- Çoklu market (Multi-Tenant) SaaS altyapısı.
- Uzaktan güncelleme ve sürdürülebilir ürün geliştirme.
- Pilot kullanım sonrası ticari satış ve lisanslama.

### 1.2 Temel mimari kararlar

| Konu | Karar |
|---|---|
| Ürün Konsepti | Market Management System (MMS) — Tam işlevli market yönetim SaaS |
| Uygulama Çerçevesi | Flutter (Dart) |
| Yerel veritabanı | Drift + SQLite (Mobil ve Masaüstü yerel operasyonel depolama, `mms_client.db`) |
| Merkezi veritabanı | Pilot için Windows Service Dart Shelf + Merkezi SQLite (Single-Writer, `%PROGRAMDATA%\MarketMMS\data\market_master.db`); Gelecek SaaS için PostgreSQL / Supabase |
| Kimlik doğrulama | Pilot için Dinamik QR Kod & Token Eşleştirme (Tek Owner); Gelecek SaaS için Supabase Auth |
| Yerel veri erişimi | Repository arayüzleri (Clean Architecture) |
| Durum yönetimi | Riverpod |
| Navigasyon | go_router |
| Barkod Girişi | Masaüstünde USB HID okuyucu, mobil cihazlarda kamera ile tarama |
| Ürün bilgisi | Open Food Facts API (doğrulama gerektiren öneri mekanizması) |
| Mimari | Paket tabanlı Feature-first + Clean Architecture (`mms_client_storage`, `spike_01_backend`, `lib`) |
| Kod kalitesi | SOLID, Clean Code, 5 aktif beceri, risk temelli otomatik testler (221 yeşil test) |
| Senkronizasyon | Yerel Wi-Fi / LAN HTTPS API, kalıcı Outbox işlem kuyruğu ve çakışma yönetimi |
| Yedekleme | Windows Service `VACUUM INTO` + Google Drive'a bağımsız S5A-4 standardında AES-256-CBC, PKCS#7 padding, PBKDF2-HMAC-SHA256 (600.000 iterasyon) ve HMAC-SHA256 Encrypt-then-MAC şifreli otomatik yedek |
| Dağıtım | Platforma özel dağıtım ve güncelleme stratejisi |
| Pilot yaklaşımı | Tek markette Windows Master Hub gerçek kullanım; çoklu market SaaS'a hazır mimari |

---

## 2. Ürün kapsamı ve öncelikler

### 2.1 İlk sürümdeki temel özellikler

**Ürün ve kategori yönetimi (PC ve Telefonda Eşit İşlev)**
- Kategori oluşturma, listeleme, güncelleme ve pasifleştirme.
- Barkodla ürün arama ve hızlı kayıt.
- Ürün adı, marka, kategori ve açıklama.
- Satış fiyatı ve isteğe bağlı maliyet fiyatı (kâr analizleri için temel).
- Gramaj, ağırlık, hacim ve ölçü birimi (kesirli miktar desteği).
- Stok miktarı ve kritik stok eşiği.
- Birden fazla barkodun aynı ürüne bağlanabilmesi.
- Ürünleri düzenleme ve geçmiş kayıtları bozmadan pasifleştirme.
- Open Food Facts ile ürün bilgisi önerme; eksik alanları manuel tamamlama.
- API'de bulunmayan ürünleri manuel kaydetme.

**Stok yönetimi**
- Başlangıç stoğu tanımlama.
- Stok girişi ve çıkışı.
- Satışla otomatik stok düşme.
- İade ve stok düzeltme hareketleri.
- Kritik stok takibi ve uyarıları.
- Tüm stok hareketlerinin zaman ve kullanıcı bazlı geçmişi.

**Satış ve POS Modülü (PC ve Telefonda Eşit İşlev)**
- Barkod okutulduğunda ürünün otomatik bulunması.
- Ürünün satış listesine anında eklenmesi; ürün adı, miktarı ve birim fiyatının net gösterimi.
- Aynı barkod tekrar okutulduğunda sepet kalem miktarının otomatik artırılması.
- Sepet toplam tutarının kesinlik kaybı oluşturmayan uygun sayısal tiplerle otomatik hesaplanması.
- Ürün çıkarma, miktar değiştirme ve satır silme.
- Satış tamamlandığında atomik transaction ile satış kaydı, sepet detayları ve stok hareketinin oluşturulması.
- Satış geçmişini anlık ve geriye dönük görüntüleme.
- Çevrimdışı satışların yerel olarak kaydedilmesi ve bağlantı kurulduğunda senkronizasyonu.
- **Ödeme İşlemleri ve Kuralları:**
  - Satış başına tek bir ödeme yöntemi seçilir: **Nakit** veya **Kredi Kartı** (`CONFIRMED`).
  - Karma (split) ödeme ve veresiye (müşteri borç defteri) MVP kapsamı dışındadır (`OUT_OF_SCOPE`).
  - Nakit satışta müşteriden alınan tutar girilir ve para üstü sistem tarafından otomatik hesaplanır; alınan tutar satış toplamından düşükse satış işlemi kesinlikle tamamlanamaz (`CONFIRMED`).
  - Kart ödemesi yalnızca uygulamaya ödeme kaydı olarak işlenir; banka POS terminaline otomatik tutar gönderilmez (`CONFIRMED`).
  - Yanlış ödeme yöntemi seçimi durumunda ödeme yöntemi düzeltmesi ayrı, denetlenebilir ve yetki kontrollü bir işlem olarak (`audit_logs`) yürütülür (`CONFIRMED`).
  - Kasa açılış/kapanış oturumları, gün sonu fiziki nakit sayımı ve kasa farkı takibi MVP kapsamı dışındadır (`OUT_OF_SCOPE`).

> [!IMPORTANT]
> **Banka POS Terminali Entegrasyonu Kapsam Dışıdır:**  
> Banka POS cihazlarına tutar gönderme, Ingenico/Beko vb. ödeme terminalleriyle donanımsal iletişim ve mali entegrasyonlar **ilk sürümün kapsamı dışındadır**. Tutar POS cihazına gerekirse elle girilir. Bu tür donanımsal ve mali entegrasyonlar, Türkiye'deki mali mevzuat ve donanım sağlayıcılarının teknik şartları doğrulandıktan sonra sonraki fazlarda ele alınacaktır.

**Dashboard ve Kazanç Kavramları (PC ve Telefonda)**
- Günlük, haftalık ve aylık satış özeti.
- Satış adedi ve toplam satış cirosu.
- **Finansal Ayrım:** Ciro (toplam hasılat), Brüt Kâr (satış fiyatı - maliyet) ve Net Kâr kavramları net şekilde ayrılır. Maliyet verisi girilmemiş ürünlerde gerçek kâr hesabı yapılmaz; işletme giderleri (kira, fatura, personel vb.) sisteme girilmeden "net kâr" iddiasında bulunulamaz.
- Kritik stok seviyesine inen ürünlerin listesi.
- En çok satan ürünler ve hareket grafiği.
- Son satışlar ve son stok hareketleri.
- Fiyat değişiklik geçmişi.
- Cihazların bağlantı, yerel kuyruk ve senkronizasyon durumu.
- Son başarılı yedekleme zamanı ve durumu.

### 2.2 Pilot öncesi zorunlu altyapı

- Çoklu market (Tenant) veri izolasyonu (Pilot için merkezi API katmanında, Gelecek SaaS için RLS).
- Windows Local Master Hub mimarisi (Dart Shelf HTTPS API + Merkezi SQLite tekil yazıcı; ilk planlamadaki Supabase pilot seçeneğinin yerini almıştır).
- Yerel veritabanı (Drift + SQLite) ve migration sistemi (`packages/mms_client_storage`).
- Kalıcı çevrimdışı işlem kuyruğu (`sync_operations` outbox durum makinesi).
- Tekrarlanan satış işlemlerine karşı idempotency (`idempotency_key`).
- Çakışma tespiti ve çözüm kuralları (satışlar asla silinmez, eksi stok `allow`).
- Temel kullanıcı kimlik doğrulama ve yetkilendirme (Pilot için Dinamik QR ve tek yerel Owner hesabı; Gelecek SaaS için Supabase Auth).
- Otomatik yedekleme ve geri yükleme testi (`VACUUM INTO` + Google Drive).
- Kritik işlemlere ilişkin audit kayıtları (`audit_logs`).
- Risk temelli birim ve entegrasyon testleri (221 test).

### 2.3 Sonraki sürümlere bırakılabilecek özellikler

- Banka POS cihazlarına ve Ingenico terminallerine otomatik tutar gönderme.
- Termal fiş yazıcısı ve ESC/POS protokolü.
- Terazi / tartı entegrasyonu (özellikle manav/şarküteri reyonları için).
- Gelişmiş kârlılık, gider yönetimi ve net kâr analizleri.
- E-fatura / e-arşiv mali onaylı entegrasyonlar.
- Gelişmiş kullanıcı, kasiyer ve şube bazlı detaylı yetkilendirme matrisi.
- Abonelik, lisanslama ve faturalandırma modülleri.
- Çoklu dil ve döviz desteği.

---

## 3. Çoklu market SaaS mimarisi

İlk pilot yalnızca bir markette yapılacak olsa da sistemin veri modeli en baştan birden fazla marketi destekleyecek çoklu kiracı (multi-tenant) yapısında tasarlanacaktır.

### 3.1 Temel kavramlar

- **Tenant:** Sisteme müşteri olarak kaydolan işletme veya market grubu.
- **Store:** Tenant'a bağlı fiziksel market, mağaza veya şube.
- **User:** Sisteme giriş yapan kullanıcı (örnek roller: işletme sahibi, yönetici, çalışan veya kasiyer).
- **Membership:** Kullanıcının hangi tenant veya şubede hangi yetkilere sahip olduğunu belirleyen ilişki. (Yetkilendirme kapsamı, çalışan sayısı ve rol sınırları `OPEN` durumundadır).
- **Device:** Kasadaki Windows masaüstü bilgisayar veya personelin elindeki telefon/tablet.

Her iş kaydı mutlaka doğru `tenant_id` ve gerektiğinde `store_id` ile ilişkilendirilir.

### 3.2 Veri izolasyonu

- Tenant'a ait veriler `tenant_id` üzerinden ayrıştırılır.
- Ürün, kategori, stok, satış ve kullanıcı ilişkileri yetki sınırları içinde doğrulanır.
- Pilot aşamasında veri izolasyonu merkezi API tarafından uygulanır; Gelecek SaaS aşamasında Supabase Row Level Security (RLS) politikaları tüm tablolarda uygulanır ve doğrulanır.
- İstemci tarafından gönderilen `tenant_id` parametresi tek başına yetki kanıtı sayılmaz; kullanıcının JWT kimliğiyle doğrulanır.

---

## 4. Çoklu cihaz yaklaşımı ve Offline-first stratejisi

### 4.1 Çoklu cihazın eşit rolü

Sistemde telefon yalnızca bir "yardımcı etiket okuyucu" değildir. Windows bilgisayar ve mobil telefonlar **aynı temel işlev setini** sunan bağımsız market yönetim istemcileridir.

Her iki cihaz tipinde de:
- Ürün ve kategori yönetimi,
- Ürün ekleme ve düzenleme,
- Satış ve sepet tamamlama,
- Stok takibi ve düzeltmesi,
- Dashboard ve ciro/kâr raporları,
- Kullanıcı yönetimi ve oturum kontrolü,
- Offline çalışma ve senkronizasyon takibi,
tam işlevli olarak yer alır.

**Cihazların Temel Farkı:** Donanım ve giriş yöntemidir:
- **Windows Masaüstü:** Hızlı kasa operasyonları için USB HID barkod okuyucu ve klavye odaklı UX.
- **Android / iOS:** Reyonda ürün gezerken veya rafta sayım yaparken mobil kamera ile barkod okuma ve dokunmatik UX.

### 4.2 Offline-first temel kararı

Windows bilgisayar ve telefonlar kendi yerel Drift + SQLite veritabanlarında (`mms_client.db`) çalışır. İnternet kesildiğinde ürün arama, satış tamamlama ve stok hareketleri kesintisiz devam eder.

Mağaza içi ağda (Wi-Fi / LAN), cihazlar Windows Local Master Hub API'sine bağlanır; mağazanın genel internet erişimi kopsa dahi yerel senkronizasyon çalışmaya devam eder. Windows kapalıyken veya servis durduğunda tüm cihazlar (Windows masaüstü UI dahil) yerel outbox kuyruğuna yazar.

### 4.3 Yerel veri akışı

1. Kullanıcı işlemi başlatır (ör. barkod okutur veya satışı onaylar).
2. İş kuralı doğrulamaları yerel olarak tamamlanır.
3. Satış, sepet satırları, stok hareketi ve senkronizasyon operasyonu **tek bir yerel transaction** içinde atomik olarak kaydedilir.
4. Senkronizasyon servisi yerel ağ üzerinden Windows Master Hub API'sine (veya loopback üzerinden) göndermeyi dener.
5. Sunucudan başarılı onay (ACK) alındığında işlem `SYNCED` olarak mühürlenir.
6. Ağ kesintisinde işlem kuyrukta tutulur ve bağlantı geldiğinde deterministik FIFO sırasıyla tekrar denenir. (Kuyruk kiralama ve hata tekrar parametreleri `OPEN DECISION` statüsündedir).

### 4.4 Çoklu cihazın çevrimdışı sınırları ve çakışma yönetimi

İki bağımsız cihaz çevrimdışıyken aynı üründen kalan son stoğu satabilir. Cihazlar birbirinden habersiz olduğundan çevrimdışıyken bunun yazılımla önlenmesi imkansızdır.

**Çakışma Kuralları:**
- **Satışlar Asla Silinmez:** Gerçekleşmiş fiziksel satış kayıtları stok çakışması gerekçesiyle silinemez.
- **Idempotency:** Her satış benzersiz bir `idempotency_key` taşır; mükerrer ağ istekleri ikinci bir satış veya mükerrer stok düşüşü yaratmaz.
- **Geçmişin Korunması:** Stok hareketleri geçmişi sessizce değiştirilemez.
- **Uyuşmazlık Yönetimi:** Oluşan negatif stok veya uyuşmazlıklar `audit_logs` tablosuna çakışma olarak kaydedilir ve dashboard'da market sahibine stok sayımı/düzeltme uyarısı olarak sunulur.

---

## 5. Open Food Facts ve barkodlu ürün kayıt sistemi

### 5.1 Ürün kayıt iş akışı (Kamera veya USB Okuyucu)

1. Barkod okutulur (telefonda kamera, PC'de okuyucu ile).
2. Önce yerel veritabanında barkod aranır.
3. Ürün bulunursa mevcut ürün bilgileri ve stok durumu getirilir.
4. Ürün bulunamazsa ve internet erişimi varsa Open Food Facts API sorgulanır.
5. API'den dönen ürün adı, marka, kategori, görsel ve miktar bilgileri kullanıcıya **öneri** olarak sunulur.
6. Market sahibi bilgileri kontrol eder; eksik veya hatalı alanları manuel olarak tamamlar/düzenler.
7. Satış fiyatı ve başlangıç stoğu market sahibi tarafından girilir.
8. Ürün yerel veritabanına kaydedilir ve senkronizasyon kuyruğuna eklenir.

### 5.2 Ürün verisinin sorumluluğu

Open Food Facts açık bir veritabanıdır; verilerin doğruluğu garanti edilemez.
- Satış fiyatı ve stok marketin kendi işletme verisidir; API'den gelemez.
- API verisi kullanıcının onayı olmadan yerel verilerin üzerine yazamaz.
- API'de bulunmayan ürünler için eksiksiz manuel kayıt desteği zorunludur.

---

## 6. Veri modeli

Temel veri modeli v1.1 ile tam uyumlu olarak korunmuştur.

### 6.1 Temel tablolar

- `tenant` / `store` / `user` / `membership` / `device`: Çoklu market, kullanıcı ve cihaz ilişkileri.
- `categories`: Ürün kategori hiyerarşisi (`tenant_id` ile izole).
- `products`: Ürün kartı (ad, marka, kategori, `sale_price`, `cost_price`, `unit`, `minimum_stock_level`).
- `product_barcodes`: Bir ürüne birden fazla barkod bağlama yapısı.
- `stock_balances`: Mağaza bazlı güncel stok miktarı.
- `stock_movements`: Stok hareketleri geçmişi (giriş, çıkış, satış, düzeltme, iade).
- `sales`: Satış başlığı (`tenant_id`, `store_id`, `device_id`, `idempotency_key`, `total_amount`, `payment_method`).
- `sale_items`: Satış detay satırları (satış anındaki fiyat ve ad snapshots'ı ile).
- `price_history`: Fiyat değişim logları.
- `sync_operations`: Yerel kalıcı senkronizasyon kuyruğu.
- `audit_logs`: Güvenlik ve çakışma denetim kayıtları.
- `backup_runs`: Yedekleme geçmişi ve durumları.

### 6.2 Finansal veri kuralları

- Para değerleri kesinlikle floating-point ile tutulamaz ve hesaplanamaz; kuruş bazlı tamsayılar (`int` / `BIGINT`) veya özel Value Object (`Money`) ile saklanır. Diğer sayısal işlemlerde (gramaj, ağırlık, oran, ölçüm ve istatistik gibi) problem alanına uygun sayısal temsil ayrıca belirlenir.
- Satış satırları, satış anındaki birim fiyat ve ürün adını snapshot olarak saklar; ürünün sonradan fiyatının değişmesi geçmiş satışları etkileyemez.
- **Alt Kuruş Yuvarlama Politikası (`OPEN DECISION`):** Kesirli miktar veya birim maliyet hesaplarında ortaya çıkabilecek alt kuruşların yuvarlama yöntemi proje sahibi tarafından henüz onaylanmamış olup `OPEN DECISION` statüsündedir.

---

## 7. Mimari ve kod organizasyonu

Paket tabanlı, modüler ve Feature-first Clean Architecture yaklaşımı:

```text
market-pos/
├── packages/
│   └── mms_client_storage/    # Uç / Yerel Drift SQLite veritabanı, outbox işlem kuyruğu, şifreli yedekleme motoru (51 test)
├── test_spikes/
│   └── spike_01_backend/      # Dart Shelf HTTPS merkezi API, merkezi SQLite tekil yazıcı, dinamik QR ve yetkilendirme (139 test)
├── lib/
│   ├── app/                   # Router (go_router), tema, bootstrap
│   ├── core/                  # Para (kuruş), rasyonel oran, hata tipleri, network
│   ├── features/              # auth, tenants, stores, devices, categories, products, inventory, sales, dashboard, sync, backup, settings
│   │   └── <feature>/
│   │       ├── domain/        # Entity, value object, repository sözleşmeleri (saf Dart)
│   │       ├── data/          # Repository implementasyonları, Drift DAO adaptörleri, Master Hub REST DTO'ları
│   │       └── presentation/  # Ekranlar, responsive widget'lar, Riverpod provider'ları
│   └── infrastructure/        # Master Hub API istemcisi (REST), platform donanım köprüleri (USB HID, kamera)
├── test/                      # İstemci unit ve widget testleri (31 test)
└── main.dart
```

---

## 8. Güvenlik, yedekleme ve test stratejisi

- **Veri İzolasyonu:** Pilot aşamasında merkezi API iş kuralları seviyesinde, Gelecek SaaS aşamasında ise Supabase RLS ile veri izolasyonu sağlanır.
- **Sırların Korunması:** API anahtarları, DPAPI pepper (`pepper.dpapi`) ve OAuth token'ları asla kaynak koda veya Git'e dahil edilmez; `.env` ve secret dosyaları `.gitignore` kapsamındadır.
- **Yedekleme:** Windows Master Hub SQLite veritabanı ve mobil SQLite veritabanlarının ayrık yedekleri alınır; harici ve bağımsız bir Google Drive yedekleme mekanizması S5A-4 standardında AES-256-CBC, PKCS#7 padding, PBKDF2-HMAC-SHA256 (600.000 iterasyon) ve HMAC-SHA256 Encrypt-then-MAC ile işletilir.
- **Risk Temelli Test:** Finansal hesaplamalar (kuruş bazlı), atomik transaction'lar, idempotency, çevrimdışı senkronizasyon ve veri bütünlüğü birim ve entegrasyon testleriyle (221 test) doğrulanır.

---

## 9. Güncellenmiş geliştirme yol haritası (Faz 0–8)

Fazların sırası ve kabul kriterleri korunmuştur:

- **Faz 0 — Planlama ve Mimari Kararlar** (✅ TAMAMLANDI — Spike 01, protokoller, veri modeli ve iş kuralları onaylandı)
- **Faz 1 — Temel Altyapı ve MVP** (🔄 DEVAM EDİYOR)
  - **Faz 1.1 — Windows Client Foundation** (✅ TAMAMLANDI ve KABUL EDİLDİ — Tag `v1.1.0-windows-client-foundation`, 221 yeşil test)
  - **DT-01.1 — Agent Governance Audit** (✅ TAMAMLANDI)
  - **DT-01.2 — Skills Security & License Review / Activation** (✅ TAMAMLANDI)
  - **DT-01.3 — Documentation Reconciliation** (Teknik çalışma tamamlandı — Proje sahibi kabulü bekleniyor)
  - **DT-01.4 — Instruction Infrastructure Integration** (Henüz başlamadı — Planlandı)
  - **Faz 1.2 — Kasa Satış Ekranı & Sepet Yönetimi** (⏳ Planlandı — Kullanıcı Onayı Bekleniyor)
- **Faz 2 — Kimlik, Tenant ve Cihazlar** (Yerel Owner modeli, QR eşleştirme, Tenant/Store modeli; Gelecek SaaS için Supabase Auth ve RLS)
- **Faz 3 — Ürün ve Kategori Yönetimi** (CRUD, Kamera/USB Barkod, Open Food Facts)
- **Faz 4 — Stok ve Satış** (Sepet, satış tamamlama, stok hareketi, idempotency)
- **Faz 5 — Offline ve Senkronizasyon** (Kalıcı kuyruk, çakışma çözümü, çoklu cihaz)
- **Faz 6 — Dashboard ve Yedekleme** (Ciro/kâr analizi, kritik stok, Google Drive yedekleme)
- **Faz 7 — Pilot** (Arkadaşın marketinde gerçek operasyonel test — Açık teknik koşulların tamamlanması şartıyla)
- **Faz 8 — Ticari Hazırlık** (Paketleme, lisanslama, dağıtım ve satış planı)

---

## 10. Değişmez kurallar ve sonraki adım

- Bu doküman projenin tek ve bağlayıcı ana referansıdır.
- **Faz 0 ve Faz 1.1 başarıyla tamamlanmıştır.**
- Faz 1.2 geliştirmesine geçilmeden önce DT-01 alt aşamaları tamamlanmalı ve kullanıcı onayı alınmalıdır.
- Bir sonraki çalışma: **DT-01.3 Proje Sahibi Kabulü ve DT-01.4 Talimat Entegrasyonu.**
