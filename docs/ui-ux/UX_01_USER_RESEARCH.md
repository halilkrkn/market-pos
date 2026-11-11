# UX_01_USER_RESEARCH.md — MARKET MMS KULLANICI ARAŞTIRMASI VE PERSONA ANALİZİ
# Market Management System (Market MMS) — User Research, Personas & Ergonomic Field Analysis

- **Doküman Versiyonu:** v1.1 (11 Kasım 2026 Uzlaştırması)
- **Tarih:** 11 Kasım 2026
- **Durum:** DRAFT / IN REVIEW BY PROJECT OWNER (MVP Kapsam Uzlaştırmalı)
- **Bağlayıcı Temel:** [`AGENTS.md`](../../AGENTS.md), [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](../../MARKET_POS_AI_STUDIO_BUILD_PLANI.md) (v1.4), [`UX_01_USER_SCENARIOS_AND_PRODUCT_ANALYSIS.md`](./UX_01_USER_SCENARIOS_AND_PRODUCT_ANALYSIS.md)
- **Metodolojik ve Kapsam Uzlaştırma Notu:** Bu belgedeki bulgular; perakende market gözlemleri, POS literatürü ve uzman analiziyle derlenmiştir (gerçek saha testi henüz yapılmamıştır). **Önemli Kapsam Notu:** Aşağıda yer alan Persona 1 (Ayrı Kasiyer Rolü) ve Persona 3 (Depo Sayımcısı) ileri faz kullanıcı keşfini temsil eder; **MVP/Pilot aşamada yalnızca Tek Sahip Hesabı (`INV-09`) aktif olup ayrı kasiyer rolü, Kasa Sayımı/Z-Raporu ve Fiziksel Stok Sayımı (`BR-STK-04`..`BR-STK-10`) MVP kapsamı dışındadır (`[OUT_OF_SCOPE]`).** Para gösterimi standart `12.50 TL` biçimindedir (`₺` simgesi ve virgüllü format kullanılmaz).

---

## 1. Giriş ve Araştırmanın Kapsamı

Küçük ve orta ölçekli perakende marketlerde (bakkal, mini-market, süpermarket, şarküteri) yazılım başarısı, karmaşık özelliklerden ziyade **kasa başındaki saniyelik hız, göz yorgunluğunu önleme, sıfır tıklama ile işlem tamamlama ve hatasız para üstü hesaplama** kabiliyetine bağlıdır.

Bu araştırma, MARKET MMS sistemini kullanacak 3 temel kullanıcı profilini, fiziksel çalışma ortamlarının ergonomik kısıtlarını ve uçtan uca kullanıcı yolculuklarını detaylandırır.

---

## 2. Kullanıcı Personaları (User Personas)

### Persona 1: Ayşe Hanım (Kasiyer / Tezgahtar)
- **Demografi:** 24 yaşında, lise mezunu, 2 yıldır mahalle marketinde tam zamanlı kasiyer.
- **Teknoloji Yetkinliği:** Orta (Akıllı telefon ve standart POS/barkod cihazı kullanıcısı; karmaşık bilgisayar menülerinden hoşlanmaz).
- **Kullandığı Cihaz:** Windows Masaüstü Kasa PC (`market_pos.exe`), USB Lazer/Kamera Barkod Okuyucu, Dokunmatik Ekran + Fiziksel Klavye (Fiş yazıcı donanım entegrasyonu `[FUTURE SCOPE]`).
- **Temel Hedefleri:**
  - Akşam yoğunluğunda (17:00 - 20:00) müşterileri bekletmeden, kuyruk oluşturmadan hızlı satış yapmak.
  - Para üstünü kuruşu kuruşuna hatasız ve ekranda kocaman puntolarla görmek.
  - Barkodu yıpranmış veya olmayan ürünlerde (ekmek, maydanoz, yumurta) tek tıkla veya tek tuşla ürünü sepete atabilmek.
- **Korkuları ve Hayal Kırıklıkları:**
  - Kasanın kilitlenmesi veya programın yanıt vermemesi.
  - Yanlışlıkla fazla ürün eklemek ve iptal ederken müşteriyi bekletmek.
  - Barkod okuturken farenin yerinden oynaması sonucu barkodun başka bir alana yazılması.
- **Tasarım İhtiyacı:** Bağlam duyarlı odak yönetimi (Context-Aware Focus `[UX PROPOSAL]`), devasa yeşil/mavi ödeme butonları, tek tuşla (`F12`) nakit ödeme, net para üstü kartı.

---

### Persona 2: Mahmut Bey (Market Sahibi / Mağaza Yöneticisi)
- **Demografi:** 52 yaşında, 15 yıldır market işletmecisi.
- **Teknoloji Yetkinliği:** Temel - Orta (Excel ve banka mobil uygulamalarını kullanır; pratik ve anlaşılır tablolar ister).
- **Kullandığı Cihaz:** Hem arka ofisteki Windows PC hem de reyonları gezerken Android akıllı telefonu.
- **Temel Hedefleri:**
  - Gün sonunda "Bugün kasaya ne kadar nakit, ne kadar kart girdi?" sorusuna tek tıkla net cevap almak.
  - Hangi ürünlerin tükendiğini veya eksiye düştüğünü görerek toptancıya sipariş vermek.
  - İnternet kopsa dahi marketin durmayacağını, akşam eve gittiğinde telefonundan mağaza durumunu görebileceğini bilmek.
- **Korkuları ve Hayal Kırıklıkları:**
  - Kasiyerlerin kasada kaçak yapması veya kontrolsüz fiş iptali (Pilot aşamasında tek sahip hesabı geçerlidir `[INV-09]`; kasiyer yetkilendirme `[FUTURE SCOPE]` olarak planlanmaktadır).
  - Karışık muhasebe jargonu ve karmaşık raporlama ekranları.
  - Veritabanının bozulması ve geçmiş satışların kaybolması.
- **Tasarım İhtiyacı:** Sade ve anlaşılır Dashboard kartları, tek tıkla şifreli Google Drive yedekleme, net stok uyarıları, mobil izleme paneli.

---

### Persona 3: Ali (Reyon Görevlisi / Sevkiyat ve Depo Sayımcısı)
- **Demografi:** 28 yaşında, hareketli, günün %80'ini reyonlarda ve depoda geçirir.
- **Teknoloji Yetkinliği:** Yüksek (Mobil uygulamalara ve mobil kamera tarayıcılara çok alışkın).
- **Kullandığı Cihaz:** Android Akıllı Telefon (Mobil MMS Uygulaması), Dahili Kamera Barkod Okuyucu.
- **Temel Hedefleri:**
  - Raftaki ürünün barkodunu kamerayla okutup anında fiyatını ve etiket doğruluğunu teyit etmek ("Fiyat Gör" modu).
  - Toptancıdan gelen 20 koli malı reyon önünde telefonla sayıp sisteme "Stok Girişi" yapabilmek.
  - Depoda Wi-Fi çekmediğinde bile sayıma devam edebilmek.
- **Korkuları ve Hayal Kırıklıkları:**
  - Kameranın barkodu yavaş tanıması.
  - Küçük dokunmatik butonlara rafta ayaktayken basamamak.
  - Sayım yaparken bağlantı koptu diye tüm girilen verinin silinmesi.
- **Tasarım İhtiyacı:** Thumb Zone (ekranın alt üçte birinde büyük butonlar), hızlı sürekli kamera tarama modu, çevrimdışı outbox garantisi.

---

## 3. Fiziksel Kasa Çevresi ve Ergonomik Kısıtlar

Market kasaları ergonomik açıdan zorlu ortamlardır. Tasarımın bu fiziksel gerçekleri karşılaması zorunludur:

```
+-----------------------------------------------------------------------+
| FİZİKSEL MARKET KASASI ÇALIŞMA ORTAMI                                 |
+-----------------------------------------------------------------------+
|  [Tavan Floresan Işıkları] -> Ekran parlaması (Gereksinim: Yüksek Kontrast)
|                                                                       |
|        [Müşteri] (Göz hizasında toplam tutarı görmek ister)          |
|           |                                                           |
|    +------v-----------------------------------------------------+     |
|    | Kasa Tezgâhı (Bantlı veya Masalı)                          |     |
|    |                                                            |     |
|    |   +-----------------------+     [Fiziksel Klavye / Numpad] |     |
|    |   | Dokunmatik Monitör    |     [USB Lazer Barkod Okuyucu] |     |
|    |   | (1366x768 / 1920x1080)|     [Termal Fiş Yazıcı]        |     |
|    |   +-----------------------+     [Para Çekmecesi]           |     |
|    +------------------------------------------------------------+     |
|           ^                                                           |
|           |                                                           |
|       [Kasiyer] (Ayakta / Bar taburesinde, göz mesafesi 60-80 cm)     |
+-----------------------------------------------------------------------+
```

### 3.1. Işıklandırma ve Parlama
- Marketlerde tavandaki güçlü beyaz floresan/LED aydınlatma monitör yüzeyinde yansıma yapar.
- Düşük kontrastlı pastel renkler, açık gri yazılar okunamaz hale gelir.
- **Çözüm:** Saf beyaz zemin yerine gözü yormayan nötr açık gri (`#F8FAFC`), koyu tema seçeneği (`#0F172A`), saf siyah veya derin lacivert yüksek kontrastlı metinler.

### 3.2. Mesafe ve Okuma Açısı
- Kasiyer monitöre ortalama **60-80 cm** mesafeden ve genellikle hafif yukarıdan aşağıya bakar.
- Standart web fontları (12-14px) bu mesafeden hızla okunamaz.
- **Çözüm:** Sepet satırlarında minimum 15-16sp metin puntoları, Toplam Tutar alanında 48sp - 72sp devasa rakamlar.

### 3.3. Ayakta Çalışma ve Parmak Yorgunluğu
- Kasiyer saatlerce ayakta durur. Küçük butonlara parmakla isabet ettirmek zihinsel ve fiziksel yorgunluk yaratır.
- **Çözüm:** Dokunmatik hedefler masaüstünde minimum 80x60 dp, mobilde minimum 48x48 dp; fare kullanımını tamamen ortadan kaldıran tam klavye navigasyonu.

---

## 4. Kullanıcı Yolculuk Haritaları (User Journey Maps)

### 4.1. Pilot Kasa (Mağaza Sahibi): Akşam Yoğunluğunda Hızlı Satış Yolculuğu

| Adım | İşletme Sahibi Eylemi | Sistem Tepkisi | Duygu / Stres Durumu | Kritik UI Gereksinimi |
|---|---|---|---|---|
| **1. Ürün Okutma** | Barkod okuyucuyla sütü okutur. | Bip sesiyle anında sepetin en üstüne ekler; toplamı günceller. | Sakin / Hızlı | Sesli/görsel geri bildirim, 100ms altı yanıt. |
| **2. Çoklu Adet** | 5 adet ekmek okutmak yerine `F2` (Miktar) veya hızlı ürün/numpad kullanır. | Miktar 5 × `12.50 TL` olarak sepete işlenir (`62.50 TL`). | Odaklanmış | Tek dokunuşla miktar çarpımı. |
| **3. Toplamı Görme** | Müşteri "Ne kadar tuttu?" der. | Sağ altta devasa kutuda `142.50 TL` görünür. | Rahat | Büyük Monospace Tabular gösterim. |
| **4. Ödeme Alma** | Müşteri 200 TL nakit uzatır; işletmeci `200` yazar ve `F10` (Nakit) basar (`main_shell_screen.dart`). | Para Üstü kutusu yeşil renkte dev puntolarla `57.50 TL` gösterir. | Güvenli | Yeşil renkli Para Üstü kartı; integer kuruş hesabı. |
| **5. Tamamlama** | Para çekmecesi açılır, para üstü verilir; sistem 2 sn sonra veya bir sonraki barkodda yeni sepete geçer. | Yerel SQLite/Outbox'a kaydedilir, sepet sıfırlanır, odak barkod kutusuna döner *(fiş yazıcı entegrasyonu `[FUTURE SCOPE]`)*. | Başarılı | Yeni satışa otomatik sıfırlanma. |

---

### 4.2. Market Sahibi: Gün Sonu Ciro İnceleme ve Yedekleme Yolculuğu *(Kasa Sayımı / Z-Raporu MVP Dışıdır)*

| Adım | Yönetici Eylemi | Sistem Tepkisi | Duygu / Stres Durumu | Kritik UI Gereksinimi |
|---|---|---|---|---|
| **1. Özet Ekranı** | Sol menüden "Dashboard" veya "Satış Geçmişi" sekmesine tıklar. | Günün toplam cirosu, nakit ve kart dağılımı özet kartlarla açılır (`Z-Raporu` ve kasa farkı sayımı MVP dışıdır). | Beklenti | Net KPI kartları (Nakit vs Kart Toplamı). |
| **2. Yedekleme** | "Drive'a Yedekle" / Şifreli Yedekleme aksiyonuna tıklar. | AES-256-CBC + HMAC-SHA256 şifreli snapshot alınır ve bağımsız yedek oluşturulur; yeşil onay simgesi çıkar. | Güvende hissetme | "Son Yedekleme: Bugün 22:30 (Başarılı)" rozeti. |

---

### 4.3. `[OUT_OF_SCOPE / FUTURE SCOPE]` Depo Fiziksel Stok Sayım Yolculuğu *(MVP Dışı)*

> [!NOTE]
> Aşağıdaki mobil fiziksel stok sayım akışı ilk keşif aşamasında tasarlanmış olup MVP kapsamı dışındadır (`BR-STK-04`..`BR-STK-10` — `[OUT_OF_SCOPE]`). Pilotta mobil arayüz yalnızca stok seviyesi, son bilinen fiyat ve stok hareket geçmişi izleme sunar.

---

## 5. Kullanıcı Gereksinimleri Matrisi (User Requirements Matrix)

| İhtiyaç Kodu | Kullanıcı | Fonksiyonel İhtiyaç | Ergonomik / UI Çözümü | Statü |
|---|---|---|---|---|
| **REQ-UX-01** | İşletme Sahibi (`INV-09`) | Barkod tabancasıyla kesintisiz ardışık okuma | Bağlam duyarlı odak (Context-Aware Focus; modal kapalıyken barkod alanında hazır kalır) | `[UX PROPOSAL]` |
| **REQ-UX-02** | İşletme Sahibi (`INV-09`) | Hızlı ekmek, su, poşet satışı | Sağ panelde hızlı ürün tuşları (tek dokunuşla ekleme) | `[UX PROPOSAL]` |
| **REQ-UX-03** | İşletme Sahibi (`INV-09`) | Yanlış ürünün hızlı iptali | Satır silme butonu ve kısayol desteği | `[UX PROPOSAL]` |
| **REQ-UX-04** | İşletme Sahibi (`INV-09`) | Para üstü hatası yapmama güvencesi | Kalın yeşil Para Üstü kutusu; alınan para girildiğinde canlı kuruş hesaplama | `[UX PROPOSAL]` |
| **REQ-UX-05** | İşletme Sahibi (`INV-09`) | Müşteri cüzdan ararken diğer müşteriye geçebilme | Sepeti Askıya Alma (Parked Carts, `BR-POS-05` / `OD-02`) | `[OUT_OF_SCOPE — MVP Dışı]` *(11 Kasım 2026 Proje Sahibi Kararı)* |
| **REQ-UX-06** | Yönetici / Sahip | İnternet ve servis durumunu anında bilme | Sağ üst barda Hub Durumu (Yeşil: Hub Online, Sarı: Yerel Offline, Kırmızı: Hata) | `[APPROVED PROJECT DECISION]` |
| **REQ-UX-07** | Yönetici / Sahip | Eksiye düşen kritik ürünleri takip etme | Dashboard'da "Eksi Stoktaki Ürünler" sarı/turuncu uyarı listesi (`INV-04`) | `[APPROVED PROJECT DECISION]` |
| **REQ-UX-08** | İşletme Sahibi (Mobil) | Reyonda tek elle kolay stok/fiyat ve satış kullanımı | Ekranın alt üçte birine yerleştirilmiş Thumb Zone kontrolleri ($\ge 48\times 48\text{ dp}$) | `[UX PROPOSAL]` |
| **REQ-UX-09** | İşletme Sahibi (Mobil) | Rafta fiyat etiketi doğruluğunu teyit etme | Kamerayla taranan ürünün son bilinen satış fiyatını ve stok hareketlerini gösteren mobil ekran | `[UX PROPOSAL]` |

---

## 6. Özet

Bu araştırma, MARKET MMS'in masaüstünde **"Klavyeden elini çekmeden hızlı nakit/kart satışı"**, mobilde ise **"Tek elle reyonu gezerken barkodla fiyat/stok görüntüleme ve hızlı satış"** ergonomisine odaklanacağını netleştirmiştir *(fiziksel stok sayımı MVP kapsamı dışındadır)*.
Tüm kullanıcı deneyimi akışları bir sonraki aşama olan `UX_02_INFORMATION_ARCHITECTURE.md` bilgi mimarisini doğrudan beslemektedir.
