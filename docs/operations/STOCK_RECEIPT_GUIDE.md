# Stok Girişi ve Stok Hareketleri Kullanım Kılavuzu — MARKET MMS

*Son güncelleme: 21 Kasım 2026*

## 1. Stok Girişi Ne İşe Yarar?

Tedarikçiden gelen, **sistemde zaten kayıtlı** ürünlerin miktarını mevcut stoğa ekler. Yeni ürün oluşturmaz. Yeni bir ürün için **Katalog → Yeni Ürün** (veya Stok Girişi ekranındaki "Yeni Ürün Ekle") kullanılır.

Örnek: Mevcut stok 5 adet, gelen 2 adet → güncel stok **7 adet**.

## 2. Adımlar

1. **Stok Yönetimi → Stok Girişi** (dar ekranda kutu simgesi).
2. Barkodu okutun:
   - **Android:** "Kamera" düğmesi.
   - **Windows:** USB barkod okuyucu (barkod alanına yazar ve Enter gönderir) veya elle yazıp Enter.
3. Ekranda ürün adı, barkodu ve **mevcut stok** görünür.
4. **Gelen Miktar**: `adet/paket/kutu/koli` biriminde tam sayı (ör. `2`); `kg/l` gibi birimlerde en fazla 3 ondalık (ör. `1,250`).
5. İsteğe bağlı **Birim Alış Fiyatı** (TL, ör. `7,50`) ve **Açıklama** (ör. irsaliye no).
6. **Stoğa Ekle**. Ekranın altında ürünün **Stok Hareket Geçmişi** (tarih/saat, miktar, alış fiyatı) güncellenir.

Ürün bulunamazsa uyarı çıkar ve **Yeni Ürün Ekle** düğmesi barkodu forma aktararak ürün tanımlamayı açar; ürün kaydedilince aynı ekranda stok girişine devam edilir.

## 3. Güvenceler

| Durum | Davranış |
|---|---|
| "Stoğa Ekle"ye çift dokunma | Tek hareket kaydedilir |
| Hata sonrası aynı girişin tekrar denenmesi | Aynı giriş kimliği kullanılır; stok iki kez artmaz |
| İnternet / Hub yok | Giriş yerelde kaydedilir; bağlantı gelince Hub'a aktarılır |
| İki cihazdan aynı anda giriş | Her giriş Hub'a fark (delta) olarak iletilir; miktar kaybolmaz |
| Pasif ürün | Stok girişi yapılamaz |

Her giriş tek bir veritabanı işleminde (transaction) hem stoğu artırır hem `STOK GİRİŞİ` hareketi yazar hem de senkronizasyon kuyruğuna ekler; biri başarısız olursa hiçbiri uygulanmaz.

## 4. Hareket Türleri

| Etiket | Anlamı |
|---|---|
| STOK GİRİŞİ | Mevcut ürüne gelen mal (bu ekran) |
| BAŞLANGIÇ STOĞU | Ürün ilk tanımlanırken girilen stok (alış fiyatı ile) |
| SATIŞ | Satış düşümü |
| İPTAL İADESİ / MÜŞTERİ İADESİ | İptal veya iade ile geri giriş |
| FİRE / HASAR | Hasarlı iade |

## 5. POS'ta Sürekli Kamera Taraması (Android)

POS ekranındaki kamera düğmesi tarayıcıyı **açık tutar**: her ürün okutulduğunda sepete eklenir ve ekranda "Sepete eklendi: … · 2 adet" geri bildirimi görünür. Aynı ürün tekrar okutulursa yeni satır açılmaz, miktar artar (aynı barkodun ardışık kareleri 1,5 sn içinde tekrar sayılmaz). Bitince **Taramayı Bitir**.
