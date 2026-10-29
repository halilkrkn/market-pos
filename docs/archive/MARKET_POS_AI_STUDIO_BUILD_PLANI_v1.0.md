# MARKET POS — AI Studio Build Plan
**Belge sürümü:** 1.0  
**Dil:** Türkçe  
**Amaç:** Bu belgeyi Google AI Studio'nun Build alanına proje talimatı olarak ver. Yalnızca fikir değerlendirmesi yapma: önce uygulanabilirliği ve planı çıkar, ardından uygun kapsamda geliştirmeye başla.

---

## 1. AI Studio için ana talimat

Bu belge, Market POS adlı satış ve stok takip uygulamasının ürün gereksinimlerini ve bugüne kadar alınan mimari kararları içerir.

Görevlerin:

1. Belgeyi baştan sona incele.
2. Gereksinimleri ve çelişkileri değerlendir.
3. **İlk olarak hedef platformları ve teknoloji uygunluğunu açıkça değerlendir.** Bu ortamın gerçekten Flutter/Dart projesi üretip üretemediğini ve Windows, Android, iOS ve Web için üretim kalitesinde çıktı sağlayıp sağlayamayacağını belirt.
4. Eğer Flutter tabanlı, dört platformu hedefleyen gerçek uygulamayı burada üretemiyorsan bunu gizleme veya web uygulamasını Flutter uygulamasıymış gibi sunma. Bu durumda yalnızca kullanıcı deneyimini doğrulamak için web tabanlı bir prototip oluştur.
5. Kısa ve somut bir faz planı, risk listesi, varsayımlar ve her faz için kabul kriterleri hazırla.
6. Planı sunduktan sonra, mevcut ortamın desteklediği en küçük anlamlı MVP parçasını uygulamaya başla. Sadece plan üretip durma.
7. Ücretli API, ücretli sunucu veya ücretli üçüncü taraf servis gerektiren bir çözüm seçme. Böyle bir gereksinim kaçınılmaz görünüyorsa önce açıkla ve ücretsiz/yerel alternatifi öner.
8. Çalışan kodu, çalıştırma talimatlarını, bilinen eksikleri ve sonraki adımı açıkça belirt.

**Önemli:** Bu dosya ürünün hedeflerini tanımlar; ortamın teknik yetenekleri hakkında gerçek dışı varsayımlarda bulunma. Kod üretimi ile üretim mimarisini birbirinden ayır. Prototipte kullanılan geçici çözümleri üretim çözümü olarak nitelendirme.

---

## 2. Ürün vizyonu

Market POS; küçük ve orta ölçekli işletmelerin ürün, barkod, satış, stok, kasa ve raporlama süreçlerini yönetebileceği, öncelikle çevrimdışı çalışabilen, anlaşılır ve güvenilir bir satış noktası uygulamasıdır.

### Hedef platformlar
- Windows masaüstü
- Android
- iOS
- Web

### Temel ilkeler
- Önce yerel ve çevrimdışı çalışma.
- İnternet kesilse de satış gibi temel işlemler devam edebilmeli.
- Ürün verileri ve finansal kayıtlar tutarlı olmalı.
- Basit, hızlı ve Türkçe kullanıcı deneyimi sunulmalı.
- SOLID, Clean Code, modülerlik ve Clean Architecture ilkeleri uygulanmalı.
- Özellikler aşamalar hâlinde geliştirilip doğrulanmalı.
- İlk MVP'de ücretli sunucu/API zorunlu olmamalı.
- Güvenlik, veri bütünlüğü ve geri yükleme, görsel özelliklerden daha öncelikli olmalı.

---

## 3. Teknoloji ve mimari kararları

### Tercih edilen üretim teknolojisi
- Flutter ve Dart.
- Flutter'ın hedef platformlar için gerçek desteği ve gerekli paketlerin platform uyumluluğu doğrulanmalı.
- Durum yönetimi için Riverpod değerlendirilebilir.
- Navigasyon için go_router değerlendirilebilir.
- Yerel ilişkisel veri için Drift/SQLite tercih edilir; ancak paketlerin her hedef platformda çalıştığı doğrulanmalıdır.
- Web için SQLite/Drift yaklaşımı doğrudan varsayılmamalı. Tarayıcı uyumluluğu ve kalıcı depolama davranışı incelenmeli; gerekirse aynı domain katmanını kullanan uygun bir web depolama adaptörü tasarlanmalı.

### Mimari
Feature-first, modüler Clean Architecture yaklaşımı kullan:

- `presentation`: ekranlar, widget'lar, durum yönetimi ve kullanıcı etkileşimleri
- `domain`: entity, value object, use case ve repository sözleşmeleri
- `data`: yerel veri kaynakları, modeller, repository implementasyonları ve eşleme işlemleri
- `core`: ortak hata tipleri, yardımcılar, tema, yapılandırma ve ortak bileşenler

Örnek özellik modülleri:
- `products`
- `sales`
- `inventory`
- `cash`
- `reports`
- `backup`
- `settings`
- `users` (yetkilendirme kapsamı netleştikçe)

Kurallar:
- UI katmanı doğrudan SQL/veritabanı çağrısı yapmamalı.
- Domain katmanı Flutter widget'larına veya veritabanı ayrıntılarına bağımlı olmamalı.
- İş kuralları UI içinde dağınık biçimde tutulmamalı.
- Para hesaplarında kayan noktalı `double` ile finansal hesap yapılmamalı.
- Veri yazımları, özellikle satış ve stok hareketleri, transaction ile atomik yürütülmeli.
- Hatalar kullanıcıya anlaşılır şekilde gösterilmeli; sessizce yutulmamalı.
- Gereksiz soyutlama ve erken optimizasyondan kaçın; ancak modüller arası sınırları koru.

### Çevrimdışı çalışma ve senkronizasyon
- İlk MVP tek cihazda yerel veriyle çalışabilmeli.
- Yerel satış için internet zorunlu olmamalı.
- İleride çoklu cihaz/bulut senkronizasyonu eklenirse outbox, idempotent işlem, çakışma yönetimi ve tekrar deneme tasarlanmalı.
- Bulut senkronizasyonunu ilk sürümde varsayılan gereksinim olarak uygulama.
- Yerel veriyi bulut olmadan da kullanılabilir tut.

---

## 4. İşlevsel kapsam

### 4.1 Ürün ve barkod
- Ürün oluşturma, düzenleme, arama ve pasife alma
- Ürün adı, SKU/kod, kategori, satış fiyatı, maliyet alanı (kapsamı doğrulanarak), vergi oranı yapılandırması
- Bir ürüne birden fazla barkod bağlama
- Barkodla hızlı ürün bulma
- Ürün stok miktarını görüntüleme
- Kesirli miktarları ve kilogram gibi ölçüleri destekleme

### 4.2 Satış ve sepet
- Barkod veya arama ile ürünü sepete ekleme
- Miktar değiştirme ve satır silme
- Ara toplam, indirim/vergi/toplam hesaplamasını açık ve test edilebilir kurallarla yapma
- Nakit, kart ve karma ödeme kaydı
- Kart terminaline ödeme gönderme entegrasyonu **ilk sürümde yok**; kart ödemesi yalnızca kullanıcı tarafından kaydedilen ödeme türüdür.
- Satışı tamamlayınca satış, ödeme ve stok hareketlerini tutarlı biçimde kaydetme
- Aynı satışın yanlışlıkla iki kez kaydedilmesini önleme

### 4.3 Stok
- Satıştan kaynaklanan stok düşümü
- Manuel stok düzeltmesi
- Mal kabul / stok girişi
- Stok sayımı ve fark kaydı
- Her değişikliğin gerekçesi ve zaman bilgisiyle izlenebilir olması

### 4.4 İade ve düzeltme
- Satış iadesi veya ters kayıt akışı
- İade işleminin stok ve kasa etkileri açıkça tanımlanmalı
- Geçmiş satışın sessizce değiştirilmesi yerine izlenebilir ters kayıt tercih edilmeli

### 4.5 Kasa
- Kasa oturumu açma ve kapatma
- Nakit giriş/çıkış kaydı
- Beklenen ve sayılan nakit arasındaki farkı gösterme
- Kasa hareketlerini satış kayıtlarından ayırt edebilme

### 4.6 Raporlama
- Günlük satış özeti
- Ödeme türüne göre toplamlar
- Ürün bazında satışlar
- Stok durumu ve düşük stok listesi
- Tarih aralığına göre filtreleme
- PDF, yalnızca rapor çıktısı için düşünülebilir; tam veritabanı yedeğinin yerine geçmez.

### 4.7 Kullanıcılar ve roller
- İlk aşamada işletme sahibi/yönetici kullanımına odaklan.
- Owner/admin/manager rolleri için temel yetkilendirme gereksinimlerini tanımla.
- Ayrı kasiyer girişi ilk MVP'de ertelenebilir.
- Yetkilendirme yalnızca buton gizlemekten ibaret olmamalı; iş kuralları ve veri işlemleri de korunmalı.

---

## 5. Veri ve finansal doğruluk

- Para birimi: Türk lirası (TRY/₺).
- Para hesaplamalarında decimal/fixed-point yaklaşımı veya kuruş bazlı tamsayı kullan; `double` ile finansal toplam hesaplama.
- Yuvarlama kurallarını açıkça tanımla ve test et.
- KDV/vergi oranları yapılandırılabilir olmalı; ancak vergi ve mali mevzuat uyumluluğunu kendiliğinden garanti ettiğini iddia etme. Türkiye'deki mali/fiskal gereksinimler uzman ve güncel mevzuat doğrulaması gerektirir.
- Satış, ödeme, stok hareketi ve kasa kayıtlarının ilişkileri tutarlı olmalı.
- Kritik yazma işlemlerinde transaction kullan.
- Zaman damgaları ve yerel saat gösterimi tutarlı olmalı.
- Silme yerine mümkün olduğunda pasife alma veya ters kayıt kullan.
- Veritabanı şeması sürümlendirilmeli; migration stratejisi oluşturulmalı.

---

## 6. Yedekleme ve geri yükleme

### 6.1 Google Drive otomatik yedekleme için hedef kararlar
Bu özellik ilk MVP'ye zorunlu olarak eklenmek zorunda değildir; faz planında ele alınmalı.

- Hedef saat: işletmenin yerel saatine göre her gün 22:00.
- Bir adet güncel "latest" yedek ve son 30 güne ait tarihli arşivler hedeflenir.
- Yeni yedek başarıyla oluşturulup doğrulanmadan eski arşiv silinmemeli.
- SQLite veritabanı çalışırken dosyayı gelişigüzel kopyalamak yerine güvenli snapshot/yedekleme yöntemi kullanılmalı.
- Ağ, kota, yetki veya OAuth hatalarında tekrar deneme ve anlaşılır hata bildirimi olmalı.
- Son başarılı yedekleme zamanı arayüzde görünmeli.
- OAuth güvenli uygulanmalı; gizli anahtarlar kaynak koduna gömülmemeli.
- Windows'ta uygulama kapalıyken zamanlanmış görev değerlendirilebilir.
- Android, iOS ve Web'de uygulama kapalıyken tam olarak 22:00'de çalışmayı işletim sistemi/tarayıcı kısıtları nedeniyle garanti etme. Bu sınırlamayı kullanıcıya açıkça bildir.

### 6.2 Manuel yedek ve geri yükleme
- Kullanıcı tam veritabanı yedeğini bilgisayara veya USB belleğe kaydedebilmeli.
- Desteklenen veri kümeleri CSV olarak dışa/içe aktarılabilmeli.
- CSV içe aktarmada önizleme, doğrulama, hata raporu ve yinelenen kayıt politikası olmalı.
- PDF raporlar, tam yedek/geri yükleme formatı değildir.
- Geri yüklemeden önce dosya sürümü ve bütünlüğü doğrulanmalı.
- Üzerine yazma öncesinde açık onay alınmalı.
- Mümkünse geri yükleme öncesi koruyucu yedek alınmalı.
- Hata durumunda veri kaybını önleyen güvenli kurtarma akışı tasarlanmalı.
- Yedek dosyalarının şifrelenmesi ve erişim izinleri risk değerlendirmesiyle ele alınmalı.

---

## 7. Güvenlik, gizlilik ve dayanıklılık

- Kaynak koda parola, OAuth token'ı veya API anahtarı gömme.
- Hata mesajlarında gizli veri sızdırma.
- Yıkıcı işlemlerde onay iste.
- Satış ve stok kayıtlarında denetlenebilirlik sağla.
- Yedekleme/geri yükleme başarısızlığında mevcut yerel veriyi koru.
- Testlerde boş veri, hatalı girdi, yinelenen barkod, yetersiz stok, yarım kalan satış ve transaction hatalarını ele al.
- Gerçek ödeme kartı verisi toplama veya saklama; ilk sürümde kart terminali entegrasyonu yok.

---

## 8. UI/UX gereksinimleri

- Arayüz dili Türkçe.
- Para biçimi `₺`; sayı ve tarih biçimleri Türkçe yerel ayarlarına uygun.
- Profesyonel, sade, hızlı ve okunabilir tasarım.
- Windows'ta klavye kullanımını ve barkod okuyucunun çoğunlukla klavye gibi veri göndermesini dikkate al.
- Satış ekranında ürün arama, barkod girişi, sepet, miktar ve toplam kolayca görülebilmeli.
- Ekranlar boş, yükleniyor, başarı ve hata durumlarını tasarlamalı.
- Kritik işlemler için erişilebilir etiketler ve uygun kontrast kullan.
- Masaüstü, tablet ve telefon boyutlarında düzeni kontrol et.
- Web prototipi üretilirse bunu **UX prototipi** olarak etiketle; Flutter üretim uygulaması olduğunu iddia etme.

---

## 9. Ücretsiz kullanım kısıtları

- İlk MVP için ücretli sunucu/API zorunlu olmasın.
- Öncelik yerel veri ve ücretsiz geliştirme araçlarıdır.
- Google Drive, ücretsiz kota ve hesap koşullarına tabidir; sınırsız veya kesintisiz ücretsiz olacağını varsayma.
- Uygulama mağazası yayımlama, Apple geliştirici hesabı, cihazlar ve bazı üçüncü taraf hizmetler ek maliyet gerektirebilir.
- Ücretsiz servis sınırları veya lisanslar değişebileceğinden, bunları güncel olarak doğrula ve varsayımlarını belirt.
- Ücretli bir bağımlılık gerekiyorsa onay almadan mimarinin zorunlu parçası yapma.

---

## 10. Fazlara ayrılmış uygulama planı

AI Studio bu planı inceleyebilir ve iyileştirebilir; ancak fazları, kapsamı ve kabul kriterlerini açıkça korumalıdır.

### Faz 0 — Ortam ve uygulanabilirlik
- Bu ortamın hangi proje türlerini gerçekten üretebildiğini belirle.
- Flutter/Dart ve dört platform hedefinin desteklenip desteklenmediğini açıkla.
- Gerekli SDK ve araçları listele.
- Paketlerin hedef platform uyumluluğuna ilişkin riskleri işaretle.

**Kabul kriterleri:** Teknik sınırlamalar ve prototip/üretim ayrımı açıkça yazılmıştır.

### Faz 1 — Temel iskelet ve tasarım sistemi
- Proje yapısı, tema, navigasyon, ortak bileşenler.
- Türkçe yerelleştirme, hata/boş/yükleniyor durumları.
- Test ve lint altyapısı.

**Kabul kriterleri:** Proje çalışır, modüler yapı anlaşılır ve temel testler çalıştırılabilir.

### Faz 2 — Ürün ve barkod yönetimi
- Ürün listeleme, ekleme, düzenleme, arama.
- Birden fazla barkod desteği.
- Ölçü birimi ve kesirli miktar modeli.

**Kabul kriterleri:** Ürünler yerel olarak saklanır; yinelenen barkod politikası test edilir.

### Faz 3 — Satış ve sepet
- Sepet, miktar, toplamlar, nakit/kart/karma ödeme kaydı.
- Satış ve stok hareketlerinin atomik kaydı.

**Kabul kriterleri:** Satış yarıda başarısız olursa tutarsız satış/stok kaydı oluşmaz; para hesapları test edilmiştir.

### Faz 4 — Stok, kasa ve iade
- Stok girişi/düzeltme/sayım.
- Kasa oturumları ve hareketleri.
- İade/ters kayıt.

**Kabul kriterleri:** Her stok ve kasa hareketi izlenebilir; iade kayıtları tutarlı çalışır.

### Faz 5 — Raporlar ve dışa aktarma
- Günlük satış, ödeme türü ve stok raporları.
- CSV dışa aktarma; PDF raporu uygun görülürse ekleme.

**Kabul kriterleri:** Raporlar kayıtlı verilerle tutarlıdır; dışa aktarma hataları kullanıcıya bildirilir.

### Faz 6 — Yedekleme ve geri yükleme
- Manuel tam yedek/geri yükleme.
- CSV içe aktarma doğrulaması.
- Google Drive otomatik yedekleme, OAuth ve platform kısıtları ayrı alt faz olarak ele alınır.

**Kabul kriterleri:** Geçersiz yedek reddedilir; başarısız geri yükleme mevcut veriyi bozmaz; yedek doğrulanır.

### Faz 7 — Sertleştirme ve dağıtım hazırlığı
- Test kapsamı, hata yönetimi, performans, erişilebilirlik.
- Windows/Android/Web paketleme ve kurulum talimatları.
- iOS için macOS/Xcode gereksinimlerini açıkça belirt.

**Kabul kriterleri:** Desteklenen her platform için doğrulama adımları ve bilinen sınırlamalar belgelenmiştir.

---

## 11. MVP dışında tutulacaklar

İlk aşamada aşağıdakileri varsayılan olarak uygulama:
- Ücretli bulut sunucusu veya zorunlu abonelik
- Gerçek kart terminali/ödeme sağlayıcısı entegrasyonu
- Çok şubeli, çok cihazlı gerçek zamanlı senkronizasyon
- Gelişmiş muhasebe veya e-fatura/e-arşiv entegrasyonu
- Kasiyer için kapsamlı kullanıcı yönetimi
- Gereksiz mikroservisler veya aşırı karmaşık altyapı

Bunlar daha sonra ihtiyaç, mevzuat ve maliyet analiziyle değerlendirilebilir.

---

## 12. AI Studio'dan beklenen çıktı biçimi

Önce aşağıdaki başlıklarla kısa bir değerlendirme yap:

1. **Ortamın gerçek yetenekleri:** Flutter mı, web mi, başka bir çıktı mı?
2. **Karar özeti:** Hangi gereksinimler doğrudan karşılanabilir?
3. **Riskler ve varsayımlar:** Özellikle veri kalıcılığı, platform uyumluluğu ve yedekleme.
4. **Faz planı:** Sıralı, küçük ve doğrulanabilir işler.
5. **İlk uygulama adımı:** Şimdi hangi dosyaları/ekranları oluşturacaksın?

Ardından mevcut ortamın desteklediği ilk küçük ama çalışan parçayı uygula. Örneğin:
- Türkçe Market POS ana ekranı
- Özet kartları
- Ürün listesi ve arama
- Sepet/satış ekranı için ilk etkileşimli akış
- Prototipte açıkça belirtilmiş yerel veya örnek veri

### Kodlama kuralları
- Önce çalışan en küçük parçayı oluştur; her şeyi tek seferde yazmaya çalışma.
- Dosya ve klasör isimlerini tutarlı kullan.
- Gerçekleştirilmemiş özellikleri tamamlanmış gibi gösterme.
- Test edemediğin davranışları "doğrulanmadı" olarak belirt.
- Çalıştırma adımlarını ve gerekli komutları ver.
- Mevcut dosyaları değiştirmeden önce mevcut yapıyı incele.
- Büyük değişikliklerden önce planı güncelle.
- Bir özelliği bitirirken kabul kriterlerini tek tek kontrol et.
- Belirsizlik varsa güvenli bir varsayım yapıp bunu açıkla; kritik mimari kararları sessizce değiştirme.

---

## 13. İlk görev

Şimdi bu belgeyi esas alarak:

1. Ortamının Flutter ve dört platformu doğrudan destekleyip desteklemediğini değerlendir.
2. Desteklemiyorsa, gerçek üretim uygulamasından ayrı bir web UX prototipi oluşturacağını açıkça belirt.
3. Faz planını ve en önemli teknik riskleri kısa biçimde sun.
4. Ardından **Market POS'un ilk çalışan MVP/prototip parçasını oluşturmaya başla**.
5. İlk teslimde neyin çalıştığını, neyin örnek veri kullandığını, neyin henüz yapılmadığını ve nasıl test edileceğini belirt.

**Öncelik sırası:** veri bütünlüğü → doğru satış/stok davranışı → çevrimdışı kullanılabilirlik → anlaşılır UI → ek özellikler.

