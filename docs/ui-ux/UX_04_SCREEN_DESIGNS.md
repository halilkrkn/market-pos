# UX_04_SCREEN_DESIGNS.md — MARKET MMS EKRAN TASARIMLARI VE BLUEPRINT ŞARTNAMESİ
# Market Management System (Market MMS) — Complete Screen Specifications & Wireframe Blueprints

- **Doküman Versiyonu:** v1.1 (11 Kasım 2026 Uzlaştırması)
- **Tarih:** 11 Kasım 2026
- **Durum:** DRAFT / IN REVIEW BY PROJECT OWNER (Para Formatı, F-Tuşu ve MVP Kapsam Uzlaştırmalı)
- **Bağlayıcı Temel:** [`AGENTS.md`](../../AGENTS.md), [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](../../MARKET_POS_AI_STUDIO_BUILD_PLANI.md) (v1.4), [`UX_02_INFORMATION_ARCHITECTURE.md`](./UX_02_INFORMATION_ARCHITECTURE.md), [`UX_03_DESIGN_SYSTEM.md`](./UX_03_DESIGN_SYSTEM.md)
- **Uzlaştırma Notu:** Tüm para birimleri `12.50 TL` formatına çekilmiş (`₺` ve virgül kaldırılmıştır), F-tuşları [`main_shell_screen.dart`](../../lib/features/shell/presentation/screens/main_shell_screen.dart#L205-L209) (`F1 Yardım`, `F2 Miktar`, `F9 Kart`, `F10 Nakit`, `Esc İptal`) ile hizalanmış, `INV-09` tek sahip hesabı korunmuş ve Fiziksel Stok Sayımı MVP dışı (`OUT_OF_SCOPE`) bırakılmıştır. KDV sütunu varsa yalnızca `[UX PROPOSAL / KAPSAM DIŞI NOT]` statüsündedir.

---

## 1. Giriş ve Tasarım Yaklaşımı

Bu belge, MARKET MMS platformunun **Windows Masaüstü için 15 Temel Ekranını** ve **Android/iOS Mobil Cihazlar için 12 Temel Ekranını** piksel düzeyinde yapısal blueprint'ler (ASCII/Unicode tel kafes çizimleri), bileşen yerleşimleri, klavye etkileşimleri ve kullanıcı akışlarıyla eksiksiz tanımlar.

---

## 2. Windows Masaüstü 15 Temel Ekran Tasarımı (Desktop Screens)

---

### EKRAN W-01: Kasa Satış Ekranı (Ana POS Ekranı - Split Panel)
- **Rota:** `/pos`
- **Hedef Cihaz:** 16:9 Yatay Ekran (1366x768 / 1920x1080), Dokunmatik Monitör veya Klavye/Fare.
- **Yerleşim Oranı:** %60 Sol Sepet Tablosu + %40 Sağ Hızlı Tuşlar, Numpad ve Dev Toplam.

```
+-------------------------------------------------------------------------------------------------------------------------+
| [MMS LOGO]  Kasa: KASA-01 | Kullanıcı: Mağaza Sahibi (Pilot) | [● HUB ONLINE] | [Outbox: 0] | Fiş No: #1042 | 06.11.2026 19:42:15  |
+-------------------------------------------------------------------------------------------------------------------------+
| [|||||] BARKOD OKUTUN VEYA YAZIN: [ 8690504018241                 ] [EKLE (Enter)] | [F3: Ürün Ara]                   |
+--------------------------------------------------------------------+----------------------------------------------------+
|  SIRA | BARKOD        | ÜRÜN ADI         | BİRİM    | BİRİM F. | ADET   | TOPLAM   | SİL | [ HIZLI ÜRÜNLER (TEK DOKUNUŞ) ]      |
+-------+---------------+------------------+----------+----------+--------+----------+-----+ [EKMEK 200g]   [SU 0.5L]    [POŞET]    |
|   1   | 8690504018241 | Somun Ekmek 200g | Adet     |    12.50 | [-] 3[+]|    37.50 | [X] | (12.50 TL)     (5.00 TL)    (0.50 TL)  |
|   2   | 8690555012345 | Yarım Yağlı Süt  | 1L       |    34.90 | [-] 2[+]|    69.80 | [X] |----------------------------------------|
|   3   | 8691234567890 | Çay Rize 1000g   | Paket    |   185.00 | [-] 1[+]|   185.00 | [X] | [YUMURTA 15Lİ] [SODA 200ML] [SİMİT]    |
|   4   | 8699999000112 | Bisküvi Kakaolu  | Paket    |    14.50 | [-] 1[+]|    14.50 | [X] | (65.00 TL)     (8.00 TL)    (15.00 TL) |
|       |               |                  |          |          |        |          |     |----------------------------------------|
|       |               |                  |          |          |        |          |     | [ OPSİYONEL NUMPAD (OD-04: Vars.Kapalı)]|
|       |               |                  |          |          |        |          |     |   [ 7 ]    [ 8 ]    [ 9 ]   [   C    ] |
|       |               |                  |          |          |        |          |     |   [ 4 ]    [ 5 ]    [ 6 ]   [  Sil   ] |
|       |               |                  |          |          |        |          |     |   [ 1 ]    [ 2 ]    [ 3 ]   [  OK    ] |
|       |               |                  |          |          |        |          |     |   [ 0 ]    [ 00]    [ . ]   [   X    ] |
+--------------------------------------------------------------------+----------------------------------------------------+
| Toplam Kalem: 4 Çeşit | Toplam Adet: 7 Adet (KDV hesaplama MVP dışı) | GENEL TOPLAM (ÖDENECEK):                           |
| [F1: Yardım] [F2: Miktar Değiştir] [ESC: İptal]                      |   306.80 TL                                        |
|                                                                    +----------------------------------------------------+
|                                                                    | [ F10: NAKİT ÖDEME ]    | [ F9: KREDİ KARTI ]      |
|                                                                    |   (Genişlik %50, 72dp)  |   (Genişlik %50, 72dp)   |
+--------------------------------------------------------------------+----------------------------------------------------+
```
- **Klavye Odağı (`[UX PROPOSAL]`):** Sayfa açıldığında varsayılan odak `BARKOD OKUTUN` alanındadır. Barkod okutulduğunda sesli geri bildirim (`Bip`) verilir, ürün sepetin en üstüne eklenir, genel toplam otomatik güncellenir. Modal açık değilken ve kullanıcı başka bir girdi alanında aktif değilken odak barkod kutusuna döner (Context-Aware Focus modeli; zorla döngü uygulanmaz). *Karar Kapanışı (`11 Kasım 2026`): Parked Carts (`OD-02`) MVP kapsamı dışına alınmıştır (`F4` kaldırılmıştır). Sanal Numpad (`OD-04`) opsiyonel olup varsayılan olarak kapalıdır; temel giriş fiziksel klavye + USB HID barkod okuyucudur. Çevrimdışıyken yerel DB'de bulunmayan barkod oluşturulamaz ve sepete eklenemez (`OD-03`).*

---

### EKRAN W-02: Hızlı Ödeme ve Para Üstü Modalı (Payment Modal)
- **Tetikleyici:** `F10` (Nakit) veya `F9` (Kredi Kartı — `main_shell_screen.dart` uyumlu) veya alt butonlara tıklanması.
- **Tasarım:** Ekran ortasında $600 \times 480\text{ dp}$ boyutunda modal. Arka plan %60 karartılmış.

```
+-----------------------------------------------------------------+
|                        HIZLI ÖDEME PANELİ                       |
+-----------------------------------------------------------------+
| ÖDENECEK TUTAR:                                  306.80 TL      |
+-----------------------------------------------------------------+
| ÖDEME TÜRÜ:  (*) NAKİT (F10)     ( ) KREDİ KARTI (F9)   [INV-08] |
+-----------------------------------------------------------------+
| HIZLI NAKİT SEÇENEKLERİ:                                        |
|   [ TAM TUTAR ]    [ 310.00 TL ]    [ 350.00 TL ]  [ 400.00 TL ] |
|   [ 500.00 TL ]    [ 600.00 TL ]    [ 1,000.00 TL] [  Manuel  ] |
+-----------------------------------------------------------------+
| MÜŞTERİDEN ALINAN NAKİT TUTAR:                                  |
| [ 400.00 TL                                                   ] |
+-----------------------------------------------------------------+
| VERİLECEK PARA ÜSTÜ:                                            |
| +-------------------------------------------------------------+ |
| |                         93.20 TL                            | |
| +-------------------------------------------------------------+ |
|                                                                 |
| [ ESC: İptal / Kapat ]                 [ ENTER: SATIŞI ONAYLA ] |
|                                             (Yeşil Dev Buton)   |
+-----------------------------------------------------------------+
```
- **Kural:** `Enter` tuşuna basıldığında satış atomik olarak kaydedilir (`sales`, `sale_items`, `stock_movements`, `sync_operations` / `outbox`). *(Fiş yazıcı entegrasyonu MVP dışıdır — `FUTURE SCOPE`.)*

---

### EKRAN W-03: Satış Başarılı ve Para Üstü Bilgi Ekranı (Post-Sale Card)
- **Tasarım:** Satış tamamlandıktan sonra kasa ekranında 2 saniye boyunca beliren (veya yeni barkod okutulana kadar sağ alt köşede kalan) teyit kartı.

```
+-----------------------------------------------------------------+
|   (✓) SATIŞ TAMAMLANDI — FİŞ #1042                              |
|   Ödeme: NAKİT  |  Tahsil Edilen: 400.00 TL                     |
|                                                                 |
|   >>> PARA ÜSTÜ: 93.20 TL <<<                                   |
|                                                                 |
|   [Yeni Satış İçin Barkod Okutun]  (Yazıcı entegrasyonu MVP dışı)|
+-----------------------------------------------------------------+
```

---

### EKRAN W-04: `[KALDIRILDI — OUT_OF_SCOPE]` Askıya Alınmış Sepetler (Parked Carts Panel) `[OD-02]`
- **Durum (11 Kasım 2026 Kararı):** Proje Sahibi tarafından **MVP kapsamı dışına çıkarılmıştır** (`OUT_OF_SCOPE`). MVP ekranlarında `F4` kısayolu veya Parked Carts paneli uygulanmayacaktır; gelecek sürümlerde yeniden değerlendirilebilir *(kimlik sürekliliği için `W-04` numarası tarihsel referans olarak korunmuştur)*.

---

### EKRAN W-05: Dashboard (Yönetici Günlük Ciro Özeti)
- **Rota:** `/dashboard`
- **Bileşenler:**
  - 4 Adet KPI Kartı: **Bugünkü Toplam Ciro** (`TL`), **Nakit Tahsilat** (`TL`), **Kredi Kartı Tahsilat** (`TL`), **Kritik Stok Uyarısı**.
  - Son 10 Satış Tablosu (Saat, Fiş No, Tutar, Ödeme Tipi).
  - Kritik Stok / Eksiye Düşen Ürünler Uyarı Paneli (`allow` politikasınca eksiye düşenler).

---

### EKRAN W-06: Ürün Listesi ve Katalog Yönetimi
- **Rota:** `/products`
- **İçerik:**
  - Üstte Filtreleme Çubuğu: Barkod/İsim Arama, Kategori Filtresi, "Sadece Eksi Stoktaki Ürünler" Onay Kutusu.
  - Veri Tablosu: Barkod, Ürün Adı, Kategori, Satış Fiyatı (`12.50 TL`), Mevcut Stok, Durum, İşlem Butonları (`Sepete Ekle` / Düzenle / Pasifleştir). *(KDV alanı ve mali raporlama MVP kapsamı dışındadır.)*
  - Sağ üstte "+ Yeni Ürün Ekle (Merkezi API)" butonu.

---

### EKRAN W-07: Yeni Ürün Ekleme / Düzenleme Formu
- **Rota:** `/products/new` veya `/products/:id`
- **Alanlar:** Barkod (Barkod tabancasıyla okutulabilir), Ürün Adı, Kategori (Dropdown), Birim (Adet, Kg, g, L, ml, Paket, Kutu), Satış Fiyatı (Kuruş cinsinden `12.50 TL` formatında), Opsiyonel Alış/Maliyet Fiyatı, Başlangıç Stoğu, Hızlı Tuşlara Ekle *(KDV oranı MVP dışı `[OUT_OF_SCOPE]`)*.
- **Kurallar:** Kuruş bazlı tamsayı formatlama (`Money`), zorunlu alan kontrolleri (`BR-PROD-01`).

---

### EKRAN W-08: Kategori Yönetimi
- **Rota:** `/categories`
- **İçerik:** Kategori ağacı ve sıralama listesi (Temel Gıda, İçecek, Şarküteri, Temizlik vb.). Kategori ekleme, isim değiştirme, renk/ikon atama.

---

### EKRAN W-09: Stok Hareketleri ve Mal Kabul (`INV-04`)
- **Rota:** `/stock`
- **İçerik:** Stok hareket tablosu (Tarih/Saat, Ürün, Hareket Türü: `SATIŞ` / `TOPTANCI GİRİŞİ` / `MANUEL DÜZELTME` / `FİRE KAYIP` / `İADE`, Değişim Miktarı, Kalan Stok, İşlemi Yapan). "Toptancı Mal Kabul Girişi" aksiyonu. *(Fiziksel stok sayımı ve `Sayım Düzelt` aksiyonu MVP kapsamı dışındadır — `BR-STK-04`..`BR-STK-10`.)*

---

### EKRAN W-10: Satış Geçmişi ve Fiş Detayı
- **Rota:** `/sales`
- **İçerik:** Tarih aralığına göre tüm satış fişlerinin listesi. Tıklanan fişin snapshot sepet satırlarını ve ödeme detayını gösteren yan panel *(KDV dökümü MVP kapsamı dışındadır)*.

---

### EKRAN W-11: Satış İptal ve İade İşlemi Modalı
- **Tetikleyici:** `F8` veya Satış Detay panelindeki "Satışı İptal / İade Et" butonu.
- **Güvenlik & Kural:** Master Hub LAN bağlantısı gerektirir (`BR-POS-09`). Seçili ürünler için ters yönde `stock_movement` ve `REFUND` kaydı oluşturulması (`INV-03`).

---

### EKRAN W-12: Cihaz Yönetimi ve QR Eşleştirme
- **Rota:** `/devices`
- **İçerik:** Sisteme kayıtlı mobil cihazların listesi (Cihaz Adı, IP Adresi, Son Senkronizasyon, İzin Durumu). "Yeni Mobil Cihaz Eşleştir" butonu tıklandığında ekranda dinamik QR Kod üretilir (`B-2` / `B-3` güvenlik sertleştirmesi gereksinimine tabidir).

---

### EKRAN W-13: Senkronizasyon ve Outbox Kuyruk İzleme
- **Rota:** `/sync`
- **İçerik:** Yerel `outbox_operations` tablosunun canlı durumu (Kuyruktaki Adet, Gönderilenler, Başarısızlar). "Şimdi Eşitle" butonu ve detaylı hata kayıtları (Audit Log).

---

### EKRAN W-14: Şifreli Yedekleme ve Kurtarma (Backup & Restore)
- **Rota:** `/backup`
- **İçerik:** Son alınan yerel ve Google Drive yedeklerinin listesi. "Yeni Güvenli Yedek Al (AES-256-CBC + HMAC-SHA256)" butonu. "Yedekten Geri Yükle" akışı (`VACUUM INTO` / `PRAGMA integrity_check` / güvenlik kopyası + bekleyen Outbox koruması).

---

### EKRAN W-15: Sistem ve Kasa Ayarları
- **Rota:** `/settings`
- **İçerik:** Sanal Dokunmatik Numpad Göster (`OD-04` — *Onaylı Karar: Opsiyonel, **varsayılan olarak kapalı**; temel giriş fiziksel klavye + USB HID barkod okuyucudur*), Tema Seçimi (Açık/Koyu), Yerel Hub URL ayarları *(Fiş yazıcı ve para çekmecesi donanım entegrasyonu `[FUTURE SCOPE]`)*.

---

## 3. Mobil Cihazlar 12 Temel Ekran Tasarımı (Mobile Screens - Android & iOS)

Mobil ekranlar, tek elle dikey kullanım (Portrait 9:16) ve **Thumb Zone (Ekranın alt üçte birlik başparmak erişim bölgesi)** prensibine göre tasarlanmıştır.

---

### EKRAN M-01: Mobil Hızlı Satış Ekranı
- **Rota:** `/mobile/pos`
- **Yerleşim:**
  - Üst Bar: Hub Durumu (`●`), Outbox Rozeti, Mağaza Sahibi (`INV-09`).
  - Üst Bölüm: Hızlı Barkod Giriş Çubuğu ve Kamera İkonu.
  - Orta Bölüm: Sepetteki Ürünlerin Listesi (Kompakt dikey kartlar: Ürün Adı, Adet +/- butonları $\ge 48\times 48\text{ dp}$, Tutar).
  - Alt Bölüm (Thumb Zone): Büyük "Sepet Toplamı: `185.00 TL`" Çubuğu ve "Satışı Tamamla" Butonu.

```
+------------------------------------------+
| MARKET MMS             ● ON  [0] (Sahip) |
+------------------------------------------+
| [||||| Barkod / Ürün Ara...     ] [📷KAM]|
+------------------------------------------+
| SEPET (3 Kalem)                          |
| ---------------------------------------- |
| Somun Ekmek 200g                         |
| 2 Adet x 12.50 TL               25.00 TL |
| [-]  [ 2 ]  [+]                      [X] |
| ---------------------------------------- |
| Yarım Yağlı Süt 1L                       |
| 1 Adet x 34.90 TL               34.90 TL |
| [-]  [ 1 ]  [+]                      [X] |
| ---------------------------------------- |
| Çay Rize 1000g                           |
| 1 Adet x 125.10 TL             125.10 TL |
| [-]  [ 1 ]  [+]                      [X] |
+------------------------------------------+
| GENEL TOPLAM:                  185.00 TL |
| +--------------------------------------+ |
| | [      SATIŞI TAMAMLA (ÖDE)        ] | |
| +--------------------------------------+ |
+------------------------------------------+
| [🏠 Özet] [📷 Tara] [🛒 Sepet] [📦 Stok] |
+------------------------------------------+
```

---

### EKRAN M-02: Kamera Barkod Tarayıcı Arayüzü (Camera Scanner View)
- **Tetikleyici:** `[📷 KAM]` butonuna basıldığında tam ekran vizör açılır.
- **Özellikler:** Ekran ortasında hedefleme karesi, Fener aç/kapat butonu, altta taranan ürün kartı (Bottom Sheet).

---

### EKRAN M-03: Mobil Sepet Bottom Sheet ve Ödeme Seçimi
- **Tasarım:** "Satışı Tamamla" butonuna basıldığında ekranın altından yukarı doğru kayan modal çekmece.
- **İçerik:** Ödenecek Tutar (Büyük puntolarla `244.90 TL`), "NAKİT" (Yeşil buton), "KREDİ KARTI" (Mavi buton — donanımsal POS olmadan elle giriş).

---

### EKRAN M-04: Mobil Satış Başarılı ve Para Üstü Ekranı
- **İçerik:** Yeşil onay tiki, Para Üstü kutusu (`12.50 TL` formatında), "Yeni Satışa Başla" butonu.

---

### EKRAN M-05: Mobil Ürün Listesi ve Barkodla Ürün Arama
- **Rota:** `/mobile/products`
- **İçerik:** Mobil arama kutusu, kategori çipleri, ürün kartları (Ürün Adı, Barkod, Fiyat, Kalan Stok).

---

### EKRAN M-06: Mobil Stok Görüntüleme ve Hareket Geçmişi (`mob-04-stock-view`)
- **Rota:** `/mobile/stock`
- **Ergonomi:** İşletme sahibinin reyonda rafta ürünün mevcut stoğunu, `allow` eksi stok uyarısını (`INV-04`), son bilinen fiyatını (`INV-10`) ve hareket denetim izini (audit trail) görüntülemesi için tasarlanmıştır. *(Fiziksel stok sayımı / sayım farkı girişi MVP kapsamı dışındadır — `BR-STK-04`..`BR-STK-10`.)*

---

### EKRAN M-07: Mobil Fiyat Gör / Etiket Doğrulama Ekranı
- **İşlev:** Mağaza sahibi reyonu gezerken kamerayla barkodu okutur; ekranda büyük harflerle ürün adı ve son bilinen satış fiyatı belirir (`INV-10`). *(KDV gösterimi MVP dışıdır.)*

---

### EKRAN M-08: Mobil Satış Geçmişi Ekranı
- **Rota:** `/mobile/more/sales`
- **İçerik:** Mobil cihazdan yapılan son satışlar ve durumları (Yerel Outbox Bekliyor / Hub İle Eşitlendi).

---

### EKRAN M-09: Mobil Dashboard ve Günlük Ciro Özeti
- **Rota:** `/mobile/more/dashboard`
- **İçerik:** Mağaza sahibinin cebinden anlık ciroyu, nakit/kart oranını ve eksi stoktaki ürünleri izleyebileceği özet kartları (`mob-01`).

---

### EKRAN M-10: Hub Eşleştirme Ekranı (QR Kod Okuyucu)
- **İşlev:** Mobil cihaz ilk açıldığında Windows Master Hub ekranındaki QR kodu kamerayla tarar; IP adresi, port ve TLS sertifika parmak izini (`B-2` / `B-3`) otomatik alarak güvenli eşleşmeyi tamamlar.

---

### EKRAN M-11: Mobil Ağ ve Senkronizasyon Durumu
- **İçerik:** Wi-Fi sinyal kalitesi, Hub bağlantı gecikmesi (ping), bekleyen Outbox paketleri ve manuel "Eşitle" butonu.

---

### EKRAN M-12: Mobil Ayarlar ve Mağaza Sahibi Profili (`INV-09`)
- **İçerik:** Mağaza Sahibi oturumu bilgileri, sesli bildirimler (bip sesi) açma/kapama, titreşim ayarı, tema seçimi (`Light` / `Dark`).

---

## 4. Özet

Bu şartname, MARKET MMS'in 27 ekranının (15 Windows + 12 Mobil) tüm işlevsel gereksinimlerini, klavye kısayollarını, bileşen yerleşimlerini ve operasyonel akışlarını belirlemiştir.
Bir sonraki aşama olan [`UX_05_INTERACTIVE_PROTOTYPE.md`](./UX_05_INTERACTIVE_PROTOTYPE.md) belgesinde bu ekranların kritik kullanıcı senaryoları ve interaktif prototip akışları modellenecektir.
