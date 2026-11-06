# Faz 0.1 — İş Gereksinimleri Keşif ve Analiz Dokümanı
## MARKET MANAGEMENT SYSTEM (MMS)

**Doküman Kodu:** `PHASE_0_BUSINESS_DISCOVERY.md`  
**Sürüm:** 1.3 (İş Kararları Tam Konsolidasyonu)  
**Tarih:** 31 Ekim 2026  
**Durum:** Faz 0 — İş Gereksinimleri Analizi (Kodlama Yok)  
**Ana Referans:** `MARKET_POS_AI_STUDIO_BUILD_PLANI.md` (v1.2.2)  
**Teknik Proje / Klasör Adı:** `market-pos`  
**Ürün Tanımı:** Market Management System (MMS) — Profesyonel Market Yönetim SaaS Uygulaması  

---

## 1. Amaç ve Kapsam

Bu dokümanın amacı; **Market Management System (MMS)** projesinde Faz 0 kapsamında ele alınan tüm iş gereksinimlerini, operasyonel akışları ve sınırları tek bir tutarlı dokümanda konsolide etmek; açıkta kalan 7 kritik konuyu kullanıcı direktifleri ve teknik öneriler doğrultusunda sınıflandırarak kesinleştirmek ve Faz 0.2 / Faz 0.3 adımı olan `BUSINESS_RULES_SPEC.md` belgesine eksiksiz girdi sağlamaktır.

Bu dokümanda:
- Onaylanmış iş kuralları ve mimari kararlar (`CONFIRMED`) sabit tutulur.
- Teknik doğrulamaya muhtaç parametrik ve mimari teklifler (`PROPOSED`) açıkça işaretlenir (kesinleşmiş işletme kuralı gibi gösterilmez).
- MVP aşamasında yapılmayacak özellikler (`OUT_OF_SCOPE`) kesin sınır çizgileriyle belirlenir.
- İş kuralları düzeyinde hiçbir `OPEN` (belirsiz) soru bırakılmamış; kalan teknik ayrıntılar teknik tasarım aşamasına devredilmiştir.

---

## 2. Önceden Onaylanmış Temel Kararlar (Değiştirilemez Temel)

Aşağıdaki maddeler v1.2 ana dokümanında ve talimat mimarisinde kesinleşmiştir; bu analizde yeniden tartışmaya açılmaz:

1. **Ürün Tanımı:** Market Management System (MMS) — Profesyonel Market Yönetim SaaS (`CONFIRMED`).
2. **Teknoloji Yığını:** Flutter (Dart), Drift + SQLite (yerel operasyonel), Windows Local Master Hub ve merkezi SQLite (pilot), Riverpod, go_router; Gelecek SaaS için Supabase PostgreSQL ve Supabase Auth (`CONFIRMED`).
3. **Mimari:** Feature-first + Clean Architecture; katman yönü $\text{presentation} \to \text{domain} \leftarrow \text{data}$; domain katmanı saf Dart ile izole (`CONFIRMED`).
4. **Çoklu Cihaz Eşitliği:** Windows masaüstü bilgisayar ve mobil telefonlar aynı temel işlevleri (ürün, satış, stok, dashboard, raporlama) tam yetkiyle çalıştırır (`CONFIRMED`).
5. **Barkod Donanımı:** Windows PC'de USB HID barkod okuyucu, mobil cihazlarda kamera ile tarama (`CONFIRMED`).
6. **Open Food Facts:** Kesin işletme verisi değil, kullanıcı onayına sunulan öneri mekanizmasıdır; satış fiyatı ve stok asla API'den otomatik gelmez (`CONFIRMED`).
7. **Offline-First Bütünlüğü:** Tüm temel işlemler internet olmadan yerel veritabanında çalışır; atomik transaction içinde satış, sepet, stok ve senkronizasyon kuyruğu (`sync_operations`) kaydedilir (`CONFIRMED`).
8. **Idempotency & Geçmişin Korunması:** Her satış benzersiz `idempotency_key` taşır; senkronizasyon çakışmalarında fiziksel satışlar ve stok hareketleri geçmişi asla silinmez (`CONFIRMED`).
9. **Yedekleme:** Merkezi Windows SQLite ve mobil SQLite ayrık yedeklerine ek olarak bağımsız otomatik Google Drive yedekleme mekanizması (`CONFIRMED`).
10. **Finansal Hassasiyet:** Para değerleri kesinlik kaybını önleyen veri tipleriyle tutulur (kuruş bazlı integer veya sabit kesinlikli tür); para hesaplamalarında asla floating-point (`double`) aritmetiği kullanılmaz (`CONFIRMED`).
11. **Geliştirme Kuralı:** Faz 0 kabul kriterleri eksiksiz tamamlanmadan ve kullanıcı onayı alınmadan Flutter/Dart kodlamasına başlanamaz (`CONFIRMED`).

---

## 3. MVP Kapsam Dışı (OUT_OF_SCOPE) Sınırları

Projenin ilk pilot sürümünde (MVP) kapsam kaymasını önlemek ve operasyonel kararlılığı sağlamak amacıyla aşağıdaki maddeler **kesin olarak ilk sürümün dışındadır**:

1. **Banka POS Terminali Entegrasyonu:** POS cihazlarına tutar aktarımı veya ödeme terminalleriyle donanımsal iletişim MVP dışındadır. Tutar POS cihazına gerekirse elle girilir (`OUT_OF_SCOPE`).
2. **Mali Cihaz / Yazar Kasa Entegrasyonu:** Mali onaylı yazar kasalar, mali mühür, e-Fatura/e-Arşiv doğrudan entegrasyonu MVP dışındadır (`OUT_OF_SCOPE`).
3. **KDV Hesaplama ve Mali Raporlama:** KDV oranları ayrıştırması, vergi dilimleri ve mali beyanname raporlaması MVP dışındadır (`OUT_OF_SCOPE`).
4. **Personel Hesapları ve Kasiyer Yetki Matrisi:** Pilot aşamasında yalnızca tek kullanıcı rolü (İşletme Sahibi) desteklenecektir. Kasiyer yetkilendirmesi, vardiya, PIN ile hızlı kasiyer değişimi MVP dışındadır (`OUT_OF_SCOPE`).
5. **Kasa Açılış/Kapanış ve Kasa Farkı Takibi:** Kasa oturumu açma/kapatma, gün sonu fiziki nakit sayımı ve kasa nakit mutabakatı (kasa farkı takibi) MVP dışındadır (`OUT_OF_SCOPE`).
6. **Karma / Parçalı Ödeme ve Veresiye:** Satış başına tek ödeme yöntemi esastır; bir kısmı nakit bir kısmı kart veya müşteri veresiye borç defteri takibi MVP dışındadır (`OUT_OF_SCOPE`).
7. **Tedarikçi ve Satın Alma Modülü:** Satın alma siparişleri, tedarikçi cari hesapları, irsaliye/fatura eşleştirme MVP dışındadır (`OUT_OF_SCOPE`).
8. **İndirim, Kampanya ve Promosyon Motoru:** "3 al 2 öde", sepet altı yüzde indirim, müşteri sadakat/puan sistemi MVP dışındadır (`OUT_OF_SCOPE`).
9. **Terazi Entegrasyonu ve Terazi Barkodu:** RS232/USB terazi donanım bağlantısı ile EAN-13 ağırlık gömülü (27xxxxx) barkodların otomatik ayrıştırılması MVP dışındadır (`OUT_OF_SCOPE`). Tartılı ürünlerin miktarı kasada elle girilir.
10. **Şubeye Özel Fiyatlandırma:** MVP tek şube çalışır; şubeler arası farklı satış fiyatı ve fiyat geçersiz kılma mantığı MVP dışındadır (`OUT_OF_SCOPE`).
11. **Push Bildirimleri:** Mobil/Masaüstü push bildirim altyapısı (FCM, OneSignal vb.) MVP dışındadır (`OUT_OF_SCOPE`).
12. **Gider Yönetimi ve Net Kâr Hesabı:** Dükkân kirası, elektrik, su, personel maaşı gibi işletme giderlerinin kaydı ve bunlara dayalı Net Kâr hesabı MVP dışındadır. MVP'de sadece maliyeti girilmiş ürünler üzerinden Brüt Kâr izlenir (`OUT_OF_SCOPE`).

---

## 4. Detaylı İş Gereksinimleri ve Analizi

### 4.1 Excel / CSV İçe Aktarma (Toplu Ürün Girişi)

- **[CONFIRMED] XLSX ve CSV Desteği:** Sistem hem `.xlsx` hem de standart `.csv` dosyalarını destekler.
- **[CONFIRMED] Standart Şablon:** Kullanıcının dışa aktarıp doldurabileceği standart bir Excel/CSV şablonu sağlanır.
- **[CONFIRMED] Tam Ön Doğrulama (Pre-validation):** Dosyanın tamamı satır satır ve alan alan doğrulanmadan veritabanına tek bir kayıt dahi yazılmaz.
- **[CONFIRMED] Hata Durumunda Bütünsel Durdurma:** Tek bir geçersiz satır tespit edildiğinde tüm içe aktarma işlemi durdurulur; kısmi/yarım veri aktarılmaz. Kullanıcı hataları düzelttikten sonra dosyayı yeniden doğrulamaya gönderir.
- **[CONFIRMED] Dosya İçi Mükerrer Barkod Engeli:** Dosyanın kendi içinde aynı barkodun birden fazla satırda bulunması kesin bir doğrulama hatasıdır ve içe aktarma başlatılamaz.
- **[CONFIRMED] Tenant Düzeyinde Barkod Çakışma Yönetimi:** Dosyadaki bir barkod tenant veritabanında zaten mevcutsa otomatik üzerine yazılmaz; kullanıcıya önizlemede gösterilerek güncelleme veya atlama onayı sorulur.
- **[CONFIRMED] Kategori Eşleştirmesi ve Onayı:** Dosyadaki kategoriler mevcut kategorilerle eşleştirilir; sistemde bulunmayan yeni kategoriler yalnızca kullanıcı onayıyla açılır.
- **[CONFIRMED] Fiyat ve Maliyet Geçmişi:** İçe aktarma ile güncellenen fiyat/maliyetler `price_history` / `cost_history` tablolarına "EXCEL_IMPORT" kaynağıyla işlenir.
- **[CONFIRMED] Atomik Transaction:** Kullanıcı onayladığında tüm işlem tek bir veritabanı transaction'ı içinde icra edilir; hata anında rollback yapılır.
- **[PROPOSED] Önerilen Teknik Satır Üst Sınırı (5.000 Satır):** İlk sürüm için bellek ve işlem süresini korumak amacıyla tek seferde önerilen teknik üst sınır 5.000 satırdır. *(Performans testleriyle doğrulanacaktır)*.

---

### 4.2 Ürün Birimleri ve Ölçü Dönüşümleri

- **[CONFIRMED] Desteklenen Birimler:** Sistem adet, kg, g, L, ml, paket ve kutu birimlerini destekler.
- **[CONFIRMED] Stok Birimi ve Fiyatlandırma Birimi Ayrımı:** Bir ürünün depodaki stok birimi (ör. kg) ile reyondaki fiyatlandırma birimi (ör. 100 g veya adet) farklı tanımlanabilir.
- **[CONFIRMED] İhtiyaca Dayalı Kutu/Paket Dönüşüm Çarpanı:** Paket veya kutu dönüşüm çarpanı yalnızca gerçekten birim dönüşümü gerektiğinde ürün kartında tanımlanır; her ürün için zorunlu değildir. Örneğin: 1 Kutu = 24 Adet gibi ürün bazlı dönüşümler desteklenir.
- **[CONFIRMED] Kontrollü Birim Dönüşümü:** Birimler arası dönüşüm yalnızca aynı fiziksel boyutta (Ağırlık: kg $\leftrightarrow$ g, Hacim: L $\leftrightarrow$ ml, Adet: Kutu $\leftrightarrow$ Adet) tanımlı oranla yapılabilir. Farklı boyutlar arası (ör. L'den kg'a) geçersiz dönüşüm yapılamaz.
- **[CONFIRMED] Kesirli Miktar Desteği:** Tartılı ve hacimli ürünler için ondalıklı/kesirli miktarlar (ör. 0.450 kg) desteklenir.
- **[CONFIRMED] Finansal Hesaplama Kuralı:** Kesirli miktar ile birim fiyat çarpımlarında floating-point (`double`) aritmetiği kullanılmaz. Kuruş bazlı integer veya sabit kesinlikli tür kullanılır.
- **[CONFIRMED] Dönüştürülemeyen Birimlerle Satış Engeli:** Sistemde geçerli dönüşüm katsayısı bulunmayan birimlerle satış yapılması engellenir.
- **[PROPOSED] Hassasiyet ve Yuvarlama Kural Seti:** Miktar hassasiyeti (ör. tartıda 3 ondalık hane: 0.001 kg; fiyatta 2 ondalık hane: 0.01 TL) ve kesin yuvarlama algoritması teknik tasarımda kural seti olarak belirlenecektir.

---

### 4.3 Barkodsuz Ürünler ve Satış Süreci

- **[CONFIRMED] Ekmek Hızlı Satış Tuşu:** Ekmek için satış ekranında özel hızlı satış tuşu bulunur. Tuşa her basış miktarı 1 artırır.
- **[CONFIRMED] Kayıtlı Güncel Fiyat Kullanımı:** Ekmek tuşu ürünün sistemde kayıtlı güncel satış fiyatını kullanır.
- **[CONFIRMED] Fiyat Değişikliği ve Geçmişin Korunması:** Ekmek fiyatı ürün kartından değiştirilir; geçmiş satışlar kendi snapshot fiyatlarını aynen korur.
- **[CONFIRMED] Genişletilebilir Mimari:** Barkodsuz ürün altyapısı, ileride ekmek dışındaki diğer barkodsuz ürünleri de (poşet vb.) destekleyecek esneklikte tasarlanır.
- **[CONFIRMED] Bulunamayan Barkod Akışı:** Yerel katalogda bulunmayan bir barkod okutulduğunda ürün kayıt akışı açılır. İnternet varsa Open Food Facts bilgileri öneri olarak sunulur; yoksa manuel kayıt yapılır. Ürün yerel veritabanına başarıyla kaydedilmeden sepet satırına eklenmez.

---

### 4.4 Stok Yönetimi, Eksi Stok ve Stok Sayımı

- **[CONFIRMED] Eksi Stok Satış İzni:** Kasada stok yetersiz olduğunda kullanıcı uyarılır; ancak işletme sahibi isterse satışı tamamlayabilir. Stok miktarı negatif olabilir.
- **[CONFIRMED] Negatif Stok İzleme ve Veritabanı Kısıtı:** Negatif stoklar dashboard ve stok listesinde ayrıca gösterilir. Veritabanında `CHECK (quantity >= 0)` kısıtı bulunmaz.
- **[CONFIRMED] Şube Başına Tek Aktif Sayım:** Veri tutarsızlığını önlemek için bir şubede aynı anda yalnızca bir aktif sayım oturumu bulunabilir.
- **[CONFIRMED] Kalıcı Taslak Sayım:** Sayım kayıtları yerel veritabanında "DRAFT" durumunda kalıcı saklanır; uygulama yeniden açıldığında kaldığı yerden devam ettirilebilir.
- **[CONFIRMED] Tam ve Kısmi Sayım:** Tüm marketin veya belirli reyon/kategorilerin sayımı desteklenir.
- **[CONFIRMED] Sayım Sırasında Satışa Devam Edilmesi:** Sayım yapılırken kasada satış durdurulmaz; satış hareketleri arka planda işlenmeye devam eder.
- **[CONFIRMED] Çoklu Cihaz Sayım Kilidi (Tek Cihaz Düzenler):** Aynı sayım oturumunu aynı anda yalnızca bir cihaz düzenleyebilir; diğer cihazlar taslağı salt okunur görüntüler.
- **[CONFIRMED] Sayım Onayı ve Değiştirilemezlik:** Onaylanan sayım belgesi geriye dönük düzenlenemez; fiziksel sayım ile sistem arasındaki farklar `stock_movements` tablosuna düzeltme hareketi olarak kaydedilir.
- **[CONFIRMED] Bekleyen Senkronizasyon Kontrolü:** Sayım onaylanmadan önce diğer cihazların bekleyen stok senkronizasyonlarının bulunup bulunmadığı kontrol edilir.
- **[CONFIRMED] Ara Stok Hareketlerinin Uzlaştırılması:** Sayım başlangıç anı ile onay anı arasında gerçekleşen satış ve stok girişleri formüle doğru şekilde katılarak uzlaştırılır.
- **[PROPOSED] Sayım Kilidi Lease/Heartbeat Modeli:** Sayım düzenleme yetkisinin sepet kilidine benzer bir lease/heartbeat mekanizmasıyla yönetilmesi teknik öneridir.
- **[PROPOSED] Kesin Uzlaştırma Algoritması:** Başlangıç-onay arasındaki stok hareketlerinin matematiksel kesin uzlaştırma algoritması teknik tasarımda hazırlanacaktır.

---

### 4.5 Sepet Yönetimi, Sepet Kilidi ve Askıya Alma (Holding)

- **[CONFIRMED] Tek Cihazda Düzenleme:** Bir sepet aynı anda yalnızca bir cihaz tarafından aktif düzenlenebilir.
- **[CONFIRMED] Diğer Cihazlarda Salt Okunur Görüntüleme:** Başka cihazda kilitli sepet, diğer cihazlarda yalnızca salt okunur ve "Düzenleniyor" rozetiyle görüntülenebilir.
- **[CONFIRMED] Süresi Dolan Kilidin Güvenli Devri:** Kilit süresi dolmuş sepet diğer cihaz tarafından devralınabilir.
- **[CONFIRMED] Kalıcı Saklama ve Geri Yükleme:** Askıya alınan sepetler yerel veritabanında kalıcı tutulur; uygulama yeniden başlatıldığında aynen geri yüklenir.
- **[CONFIRMED] Keyfî Sepet Limiti Olmaması:** MVP için keyfî bir maksimum bekleyen sepet sayısı belirlenmez; sistem donanım sınırları elverdiğince sepetleri kalıcı saklar.
- **[PROPOSED] Sayfalama (Pagination):** Sepet listeleme ekranında performans için sayfalama mekanizması teknik tasarımda değerlendirilecektir.
- **[PROPOSED] Kalp Atışı (30 sn) ve Zaman Aşımı (2 dk):** 30 saniye heartbeat ve 2 dakika timeout parametreleri teknik testlerle doğrulanacaktır.
- **[PROPOSED] Çevrimdışı Kilit Sınırı Dokümantasyonu:** İnternet yokken dağıtık ortamda mutlak anlık kilit garantisi verilemeyeceği mimari sınır olarak belgelenmiştir.

---

### 4.6 Çevrimdışı Fiyat ve Ürün Çakışması Yönetimi

- **[CONFIRMED] Anında Yerel Kayıt:** Fiyat değişikliği veya yeni ürün açılışı yerel cihazda anında kaydedilir ve senkronizasyon kuyruğuna (`sync_operations`) eklenir.
- **[CONFIRMED] Senkronizasyona Kadar Eski Fiyat Gösterimi:** Diğer cihazlar senkronizasyon gerçekleşene kadar ellerindeki son fiyatı göstermeye devam eder.
- **[CONFIRMED] Fiyat Çakışması Tespiti ve Koruma:** Aynı ürünün fiyatı iki çevrimdışı cihazda farklı biçimde değiştirilmişse çakışma tespit edilir; her iki değer de korunur. Sistem sessizce bir fiyatı diğerinin üzerine yazmaz.
- **[CONFIRMED] İşletme Sahibi Kararı:** Çakışma işletme sahibinin inceleme ekranına sunulur; hangi fiyatın geçerli olacağına işletme sahibi karar verir.
- **[CONFIRMED] Audit Kaydı:** Verilen karar zaman damgası ve kullanıcı bilgisiyle `audit_logs` tablosuna yazılır.
- **[CONFIRMED] Çakışma Çözülene Kadar Son Yerel Fiyat Kuralı:** Çakışma çözülene kadar ilgili cihazın elindeki son yerel fiyat bilgisi korunur; belirsiz bir merkezi fiyat otomatik kabul edilmez.
- **[CONFIRMED] Tenant Düzeyinde Barkod Benzersizliği:** Çevrimdışı açılan ürünler sunucuya ulaştığında tenant düzeyinde tekillik kontrol edilir; çakışan ürünler otomatik birleştirilmez.

---

### 4.7 Kimlik Doğrulama ve Cihaz Güvenliği

- **[CONFIRMED] Pilot Kullanıcı Kimliği:** Pilot aşamasında sistem tek işletme sahibi (Owner) hesabı ile yerel olarak yönetilir. Yerel kimlik yöntemi (PIN, parola, token vb.) açık konu olup Faz 1'de ele alınacaktır. Gelecek SaaS aşamasında Supabase Auth desteklenecektir.
- **[CONFIRMED] Parola Sıfırlama:** Güvenli e-posta tabanlı şifre sıfırlama akışı desteklenir.
- **[CONFIRMED] İlk Girişte İnternet Şartı:** Cihazda ilk oturum açılırken aktif internet bağlantısı zorunludur.
- **[CONFIRMED] Doğrulanmış Cihazda Çevrimdışı Çalışma:** Daha önce oturum açılmış cihaz internet kesildiğinde çalışmaya devam eder.
- **[CONFIRMED] Cihaz İptali (Revocation):** İşletme sahibi yönetim arayüzünden bir cihazın yetkisini iptal edebilir; iptal edilen cihazın API erişim yetkisi kaldırılır ancak yerel veritabanı ve satışları korunur.
- **[CONFIRMED] Pilot Cihaz Limiti:** Pilot aşamasında bir işletme için en fazla 3 aktif cihaz (1 PC + 2 Mobil) tanımlanabilir.
- **[PROPOSED] Güvenli Yerel Depolama (DPAPI / Keychain):** Masaüstünde DPAPI, mobilde Keychain/KeyStore ile token saklanması teknik tasarımda doğrulanacaktır.
- **[PROPOSED] Çevrimdışı Oturum Süresi (7 Gün):** İnternete bağlanmayan cihazın 7 gün sonra oturum yenilemesinin zorunlu tutulması teknik öneri olarak değerlendirilmektedir.

---

### 4.8 Yedekleme, Arşivleme ve Geri Yükleme

- **[CONFIRMED] Günlük Otomatik Yedekleme:** Yerel ve merkezi veritabanının günlük yedeği otomatik olarak alınır.
- **[CONFIRMED] 30 Günlük Günlük Yedek Saklama:** Günlük alınan yedekler 30 gün boyunca geriye dönük saklanır.
- **[CONFIRMED] Önemli Olaylardan Sonra Ek Yedek:** Yıl sonu devri veya toplu Excel içe aktarımı gibi önemli olayların ardından otomatik ek yedek alınır.
- **[CONFIRMED] Satış Başı Tam Yedek Almama:** Performansı korumak için her tekil satış işleminde tam veritabanı yedeği kesinlikle alınmaz.
- **[CONFIRMED] Geri Yükleme Sonrası Cihaz Uzlaştırması:** Bir yedek geri yüklendiğinde, diğer cihazların yerel veritabanları ve senkronizasyon kuyrukları sıfırlanarak geri yüklenen ana veriyle senkronize edilir.
- **[CONFIRMED] Bağımsız Google Drive Yedeği:** Merkezi Windows SQLite ve mobil cihazların ayrık yedeklerine ek olarak bağımsız otomatik Google Drive yedeklemesi sağlanır.
- **[PROPOSED] Tenant Başına Bağımsız Google Drive OAuth Modeli:**
  - Her tenant/işletme sahibi kendi Google hesabını OAuth ile bağlar.
  - Yedekler ilgili işletmenin kendi Drive alanında tutulur.
  - Gerekli en düşük erişim kapsamı (en dar scope) kullanılır.
  - Yedekler şifrelenir ve bütünlük kontrolünden geçirilir.
  - OAuth erişim bilgileri güvenli saklanır.
  - Merkezi, bütün müşterilerin verilerini toplayan tek bir kişisel Google hesabı kesinlikle kullanılmaz.
  *(OAuth kapsamı, token yenileme ve bağlantı kaldırma davranışları teknik tasarımda doğrulanacaktır)*.
- **[PROPOSED] Şifreleme ve Bütünlük Doğrulama (AES / SHA-256):** Dosya şifrelemesinde AES ve doğrulamasında SHA-256 kullanılması teknik tasarımda doğrulanacaktır.
- **[PROPOSED] Aylık Arşiv Saklama Süresi:** Aylık arşivlerin 12 ay saklanması depolama maliyetine göre netleşecektir.
- **[PROPOSED] Olay Öncesi Koruyucu Yedek:** Geri yükleme öncesinde koruyucu anlık snapshot alınması teknik öneridir.

---

### 4.9 Ürün Görselleri ve Önbellek Yönetimi

- **[CONFIRMED] Görselin İsteğe Bağlı Olması:** Görsel yüklemek zorunlu değildir; ürün kaydı ve satış görsel olmadan da tam yetkiyle çalışır.
- **[CONFIRMED] Open Food Facts Görsel Önerisi:** Barkod okutulduğunda Open Food Facts'ten gelen görsel kullanıcı onayına sunulur.
- **[CONFIRMED] Çift Platformdan Yükleme:** Hem PC'den hem mobilden görsel yüklenebilir.
- **[CONFIRMED] Yerel Görsel Önbelleği ve Çevrimdışı Kuyruk:** Görseller yerel diskte önbelleğe alınır; çevrimdışıyken eklenen görseller kalıcı yükleme kuyruğuna alınarak internet geldiğinde sunucuya aktarılır.
- **[PROPOSED] İstemci Sıkıştırma ve Boyutlandırma:** İstemcide görsel boyutlandırma ve sıkıştırma yapılması önerilir. Başlangıç teknik önerisi: en fazla 1200×1200 piksel ve yaklaşık 1 MB; JPEG/WebP formatları.
- **[PROPOSED] Görsel Depolama Modeli:** Pilot için ürün görsellerinin yerel depolama ve servis modeli açık konu olarak değerlendirilecek; gelecek SaaS aşamasında Supabase Storage ve CDN kotaları doğrulanacaktır.

---

### 4.10 Kasa, Ödeme ve Para Üstü İşlemleri

- **[CONFIRMED] Satış Başına Tek Ödeme Yöntemi:** Satış işleminde tek bir ödeme yöntemi seçilir: **Nakit** veya **Kredi Kartı**.
- **[CONFIRMED] Nakit Para Üstü Hesabı:** Nakit satışta müşteriden alınan tutar girilir ve sistem para üstünü otomatik hesaplar. Alınan tutar satış toplamından azsa işlem tamamlanamaz.
- **[CONFIRMED] Kart Ödemesi Kaydı:** Kart ödemesi yalnızca uygulamaya ödeme kaydı olarak işlenir; banka POS terminaline otomatik tutar gönderilmez (`OUT_OF_SCOPE`).
- **[CONFIRMED] Ödeme Yöntemi Düzeltme İşlemi:** Yanlış ödeme yöntemi seçildiğinde düzeltme ayrı ve denetlenebilir (`audit_logs`) bir işlem olarak yürütülür.
- **[OUT_OF_SCOPE] Kasa Açılış/Kapanış ve Kasa Farkı:** Kasa açılış/kapanış oturumları, gün sonu nakit sayımı ve kasa farkı mutabakatı MVP dışındadır.

---

### 4.11 Tenant ve Çoklu Şube Mimarisi

- **[CONFIRMED] Pilot Tek Tenant ve Tek Şube:** Pilot markette tek bir işletme ve tek mağaza çalışacaktır.
- **[CONFIRMED] Geleceğe Hazır Veri Modeli:** Şema ve modeller `tenant_id` ve `store_id` hiyerarşisine uygun tasarlanır.
- **[CONFIRMED] Katalog ve Stok Ayrımı:** Ürün kataloğu tenant düzeyinde; stok ve satış kayıtları şube düzeyinde izole edilir.
- **[CONFIRMED] Veri İzolasyonu Güvenliği:** Pilot aşamasında veri izolasyonu merkezi API seviyesinde sağlanır; gelecek bulut SaaS aşamasında Supabase PostgreSQL katmanında Row Level Security (RLS) zorunludur.
- **[PROPOSED] Şubeye Özel Fiyatlandırma Vizyonu:** Uzun vadeli mimaride tenant genelinde varsayılan satış fiyatı bulunurken, ileride şubeye özel fiyat tanımlama ve varsayılan fiyatı geçersiz kılma desteklenebilir. *(Bu özellik MVP kapsamı dışındadır (`OUT_OF_SCOPE`); veri modeli bu genişlemeye engel oluşturmayacak biçimde tasarlanacaktır)*.

---

### 4.12 Raporlama, Dashboard ve Kâr Ayrımı

- **[CONFIRMED] Net Satış Ayrımı:** Raporlarda Brüt Satış, İadeler ve Net Satış ($\text{Net Satış} = \text{Brüt Satış} - \text{İadeler}$) ayrı gösterilir.
- **[CONFIRMED] İptal Satışların Cirodan Ayrılması:** İptal edilen satışlar ciroya kesinlikle dahil edilmez; ayrı bir iptal raporunda izlenir.
- **[CONFIRMED] Ödeme Türü Hasılatı:** Nakit ve Kredi Kartı ciroları ayrı ayrı raporlanır.
- **[CONFIRMED] Ayrı En Çok Satan Ürün Sıralamaları:** Miktar bazında ve Ciro bazında en çok satanlar iki ayrı liste olarak sunulur.
- **[CONFIRMED] Brüt Kâr Hesabı:** Yalnızca alış maliyeti tanımlı ürünler için ($\text{Satış Tutarı} - \text{Maliyet Tutarı}$) brüt kâr hesaplanır.
- **[CONFIRMED] Eksik Maliyet Uyarısı:** Maliyeti girilmemiş ürünlerin satışları dashboard ve kâr raporunda "Maliyeti Belirtilmemiş Satışlar" olarak ayrı listelenir.
- **[CONFIRMED] Çevrimdışı Veri Uyarısı:** Çevrimdışıyken alınan raporlarda yerel veri eksikliği uyarısı gösterilir.
- **[CONFIRMED] XLSX ve PDF Dışa Aktarma:** Raporlar Excel ve PDF formatında dışa aktarılabilir.
- **[OUT_OF_SCOPE] Gider Yönetimi ve Net Kâr:** Gider modülü bulunmadığından net kâr raporu MVP dışındadır.

---

## 5. Gereksinimlerin Konsolide Sınıflandırma Tablosu

| Kategori / İş Alanı | CONFIRMED (Kesinleşen) | PROPOSED (Öneri / Teknik Doğrulama) | OUT_OF_SCOPE (MVP Dışı) |
|---|---|---|---|
| **Toplu İçe Aktarma** | XLSX/CSV desteği, tam ön doğrulama, hatada durma, dosya içi mükerrer barkod engeli, tenant barkod kontrolü, kategori onayı, atomik transaction | Önerilen teknik üst sınır: 5.000 satır | Tedarikçi XML entegrasyonu, otomatik senkronizasyon |
| **Ölçü ve Birimler** | Adet, kg, g, L, ml, paket, kutu desteği, stok-fiyat birim ayrımı, ihtiyaca bağlı kutu çarpanı, kesirli miktar, tamsayı para hesabı, geçersiz dönüşüm engeli | Birim hassasiyeti ve yuvarlama kural seti | Terazi donanım entegrasyonu (RS232), EAN-13 gramaj barkodu |
| **Barkodsuz Ürün** | Ekmek hızlı satış tuşu, kayıtlı güncel fiyat, geçmiş satış snapshot fiyatı koruması, genişletilebilir altyapı | - | PLU kodlu manav terazi otomasyonu |
| **Barkod Arama** | Bulunamayan barkodda ürün kayıt akışı açılması, OFF önerisi, manuel kayıt, kaydedilmeden sepete eklenmeme | - | Otomatik web fiyat karşılaştırması |
| **Stok & Eksi Stok** | Eksi stok satış izni (uyarı + onay), negatif stok dashboard gösterimi, `quantity >= 0` kısıtı yokluğu, tek aktif sayım, kalıcı taslak, sayım anında satışa devam, sayımda tek cihaz düzenler kuralı, onay değiştirilemezliği, ara hareketleri uzlaştırma | Sayım kilidi lease/heartbeat modeli, ara hareket kesin uzlaştırma algoritması | RFID el terminali sayımı, depo transferi |
| **Sepet & Kilit** | Tek cihazda düzenleme, diğerlerinde salt okunur, süresi dolan kilidi devretme, kalıcı saklama ve geri yükleme, limitsiz sepet mantığı | Sayfalama (pagination), 30 sn heartbeat, 2 dk lock timeout, çevrimdışı kilit sınırı belgesi | Müşteri ekranı (customer display) |
| **Çevrimdışı Çakışma** | Yerel ürün ve fiyat işlemi, tenant düzeyinde barkod tekilliği, otomatik birleştirmeme, fiyat çakışmasında iki değeri koruma, işletme sahibi kararı, audit log, çakışma çözülene kadar son yerel fiyatın geçerliliği | - | Otomatik yapay zekâ çakışma uzlaştırması |
| **Kimlik & Cihaz** | Pilot tek Owner hesabı, yerel oturum, cihaz iptali (yerel veri silinmez), pilotta maks 3 cihaz (Gelecek SaaS için Supabase Auth) | DPAPI/Keychain güvenli saklayıcılar, 7 günlük çevrimdışı oturum süresi | Personel/kasiyer yetki matrisi, PIN değişimi, vardiya takibi |
| **Yedekleme & Kurtarma** | Günlük yedek, 30 gün saklama, önemli olay sonrası ek yedek, satış başı yedek almama, geri yükleme uzlaştırması, bağımsız Google Drive yedeği | Tenant başına bağımsız OAuth Drive modeli, AES şifreleme/SHA-256 doğrulama, aylık arşiv saklama süresi, olay öncesi koruyucu yedek | Bant sürücü yedeği, üçüncü parti soğuk depolama |
| **Ürün Görselleri** | Görsel isteğe bağlı, Open Food Facts önerisi, PC/telefondan yükleme, yerel önbellek, çevrimdışı yükleme kuyruğu | İstemci sıkıştırma (maks 1200x1200 px, ~1 MB, JPEG/WebP), Görsel depolama modeli açık konu (Gelecek SaaS için Supabase Storage kotaları) | Otomatik arka plan temizleme (AI image processing) |
| **Kasa & Para Üstü** | Satış başı tek ödeme (Nakit/Kart), nakit para üstü hesabı, eksik ödemede engelleme, ödeme düzeltme denetim izi | - | Kasa açılış/kapanış, kasa farkı mutabakatı, banka POS cihaz entegrasyonu, parçalı ödeme, veresiye |
| **Tenant & Şube** | Pilot tek tenant + tek şube, tenant/store modelleri, katalog tenant düzeyinde, stok/satış şube düzeyinde, merkezi API izolasyonu (Gelecek SaaS için RLS) | Gelecekte şubeye özel fiyat geçersiz kılma mimarisi | Şubeye özel fiyatlandırma (MVP dışı), çoklu para birimi, franchise konsolidasyonu |
| **Rapor & Kâr** | Net satış ayrımı, iptal satışları cirodan düşme, nakit/kart hasılatı, miktar ve ciro bazlı en çok satanlar, brüt kâr, eksik maliyet uyarısı, XLSX/PDF dışa aktarma | - | Gider yönetimi, personel gideri, Net Kâr, KDV/mali raporlama |

---

## 6. Teknik Doğrulama Bekleyen Öneriler (PROPOSED Teknik Konular)

Aşağıdaki teknik maddeler ve parametreler, teknik tasarım ve saha testleriyle doğrulanacaktır:

1. **Excel/CSV Teknik Satır Sınırı (5.000 Satır):** Bellek ve işlem süresi performansı test edilecektir.
2. **Kutu/Paket Dönüşüm ve Yuvarlama Algoritması:** Kesirli dönüşümlerde hassasiyet ve yuvarlama formülleri teknik tasarımda kodlanacaktır.
3. **Stok Sayımı Düzenleme Kilidi ve Ara Hareket Uzlaştırma:** Sayım kilidinin lease/heartbeat mekanizması ve başlangıç-onay arası stok hareketlerini uzlaştıran matematiksel formül teknik tasarımda hazırlanacaktır.
4. **Sepet Listelemede Sayfalama:** Bekleyen sepet sayısı arttığında UI performansı için sayfalama mekanizması değerlendirilecektir.
5. **Görsel Boyutlandırma ve Sıkıştırma (1200x1200 px, ~1 MB):** İstemci tarafındaki imaj işleme performansı test edilecektir.
6. **Tenant Başına Bağımsız Google Drive OAuth Modeli:** Her işletme sahibinin kendi Google hesabını en dar yetki kapsamıyla bağlaması; token yenileme ve bağlantı kesme akışları teknik tasarımda doğrulanacaktır.
7. **AES Şifreleme ve SHA-256 Bütünlük Doğrulaması:** Platform uyumluluğu ve şifreleme süreleri doğrulanacaktır.
8. **Güvenli Saklama (DPAPI / Keychain):** İşletim sistemi yerel kasalarının kararlılığı test edilecektir.
9. **Çevrimdışı Oturum Süresi (7 Gün):** Güvenlik ve token yaşam döngüsü doğrulanacaktır.
10. **Sepet Kilidi (30 sn Heartbeat / 2 dk Timeout):** Ağ ve batarya tüketim testleri yapılacaktır.
11. **Şubeye Özel Fiyatlandırma Şema Tasarımı:** İleride desteklenecek bu modelin veri şeması genişleyebilir biçimde modellenecektir.

---

## 7. İş Gereksinimlerinin Tamamlanma Durumu (Açık Kalan İş Sorusu Yoktur)

Tüm iş kuralları ve operasyonel belirsizlikler (eksi stok, ekmek tuşu, bulunamayan barkod, nakit para üstü, içe aktarma mükerrerliği, kutu dönüşümü, sayımda çoklu cihaz, sepet saklama, çevrimdışı fiyat çakışması, çoklu şube fiyatı ve görseller) netleştirilmiştir.

**İş kuralları düzeyinde hiçbir `OPEN` soru kalmamıştır.** Kalan tüm maddeler teknik tasarım parametreleridir (`PROPOSED`) ve bir sonraki adım olan `BUSINESS_RULES_SPEC.md` ile veri modelleme çalışmasında şartnameye bağlanacaktır.

---

## 8. Faz 0 Kabul Kriterleri Durumu ve Sonraki Adımlar

`MARKET_POS_AI_STUDIO_BUILD_PLANI.md` (v1.2.2) uyarınca Faz 0 kapsamında tamamlanması gereken kabul kriterleri:

- [x] Temel ürün vizyonunun belirlenmesi (MMS SaaS modeli, tek bağlayıcı doküman v1.2.2)
- [x] Çoklu cihaz yaklaşımı ve yerel çalışma modeli (PC + Mobil eşit işlev, Drift + SQLite)
- [x] Ortak yapay zekâ talimat mimarisinin kurulması (`AGENTS.md`, `GEMINI.md`, `rules/`)
- [x] İş gereksinimlerinin eksiksiz konsolide edilmesi ([`PHASE_0_BUSINESS_DISCOVERY.md`](file:///c:/Users/halil/Github/market-pos/docs/requirements/PHASE_0_BUSINESS_DISCOVERY.md) v1.3)
- [x] `CONFIRMED`, `PROPOSED` ve `OUT_OF_SCOPE` ayrımının net olarak korunması
- [x] Tüm iş sorularının karara bağlanması (İş gereksinimi düzeyinde açık konu kalmaması)
- [ ] **İş Kuralları Şartnamesi'nin (Business Rules Spec) hazırlanması (`docs/requirements/BUSINESS_RULES_SPEC.md`)**
- [ ] Kesin veri modeli, alan tipleri, foreign key ve indekslerin tasarlanması
- [ ] Offline senkronizasyon, outbox kuyruğu ve çakışma çözüm protokolünün detaylandırılması
- [ ] Bağımsız Google Drive yedekleme, OAuth akışı ve geri yükleme prosedürünün netleştirilmesi
- [ ] Windows, Android, iOS ve Web platform depolama doğrulaması
- [ ] Faz 0 Kapanış ve Kabul Doğrulama Raporu'nun kullanıcı onayına sunulması

> [!CAUTION]
> **Faz 0 henüz tamamlanmamıştır.** `BUSINESS_RULES_SPEC.md`, kesin veri modeli ve senkronizasyon protokolü hazırlanmadan ve kullanıcıdan açık onay alınmadan **Flutter/Dart kodlamasına geçilemez**.
