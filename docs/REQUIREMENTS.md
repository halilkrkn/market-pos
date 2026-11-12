# REQUIREMENTS.md — MARKET MMS İş ve Sistem Gereksinimleri İndeksi

**Belge Sürümü:** v1.4 (13 Kasım 2026 — Faz 1.2 POS Kabulü & Faz 1.3 Kapsam Güncellemesi)\
**Tarih:** 13 Kasım 2026\
**Aşama:** Faz 1 — MVP Uygulama ve Doğrulama\
**Ana Şartname:** [`docs/requirements/BUSINESS_RULES_SPEC.md`](./requirements/BUSINESS_RULES_SPEC.md) (v1.6 — 12 Kasım 2026 uzlaştırmalı; `OD-01..OD-04`, `'CASH'`/`'CARD'` ve Legacy Outbox Recovery)  
**Keşif ve Karar Konsolidasyonu:** [`docs/requirements/PHASE_0_BUSINESS_DISCOVERY.md`](./requirements/PHASE_0_BUSINESS_DISCOVERY.md) (v1.3)

---

## 1. Giriş ve Şartname Hiyerarşisi

MARKET MANAGEMENT SYSTEM (MMS) projesinde yazılacak her satır kod, oluşturulacak her veritabanı tablosu ve her arayüz bileşeni, onaylanmış iş kurallarına dayanmak zorundadır.

Gereksinim belgeleri 3 katmanda yönetilmektedir:
1. **İş Gereksinimleri Keşif Dokümanı (`PHASE_0_BUSINESS_DISCOVERY.md`):** İş kararlarının, MVP kapsam dışı (`OUT_OF_SCOPE`) sınırlarının ve paydaş mutabakatlarının tutulduğu zemin belgesidir.
2. **İş Kuralları Şartnamesi (`BUSINESS_RULES_SPEC.md`):** 10 modül altında tekil kimliklerle (`BR-...`) tanımlanmış, kabul kriterleri ve veri etkileri belirlenmiş **kesin ve bağlayıcı ana şartnamedir**.
3. **Bu Belge (`REQUIREMENTS.md`):** Geliştiriciler ve modeller için yüksek seviyeli modül fihristi ve izlenebilirlik haritasıdır.

---

## 2. On Modüllük İş Kuralları Özeti

| Modül Kodu | Modül Adı | Temel Kural Sayısı | Çekirdek İş Kuralları ve Prensipler |
| :---: | :--- | :---: | :--- |
| **BR-PROD** | Ürün ve Kategori Yönetimi | 16 Kural | Çoklu aktif barkod (`BR-PROD-02`), barkodsuz ürün modellemesi (`BR-PROD-04` — modelleme: `product_barcodes` ilişkisinde aktif barkod kaydı bulunmayan ürün olarak tanımlanır; klavye kısayolu ve ekmek hızlı tuşu ataması onaylanmış bir özellik olmayıp kesinleşmemiş açık bir tasarım konusudur, `F1` yalnızca Yardım paneline ayrılmıştır), pasifleştirme (`BR-PROD-03`), Open Food Facts önerisi (`BR-PROD-06`), pay/payda rasyonel birim dönüşümü (`BR-PROD-08`), snapshot maliyet kopyalama (`BR-PROD-13`), alt kuruş Half-Up yuvarlama ve `12.50 TL` gösterim standardı (`BR-PROD-07` / `OD-01`). *(Not: Bilinmeyen barkod `BR-PROD-05` / `OD-03`: offline ürün oluşturulamaz ve bilinmeyen barkod offline sepete eklenemez; ürün oluşturma Hub gerektirir. Ürün ve Kategori yönetimi arayüzü [CRUD] Faz 1.4 adayıdır)* |
| **BR-STK** | Stok ve Envanter Yönetimi | 10 Kural | Stok hareket türleri (`BR-STK-01`, `BR-STK-11`), eksi stok serbestliği (`BR-STK-02`), raftan satışın faturadan önce yapılabilmesi (`BR-STK-03`). *(Not: Fiziksel sayım kuralları `BR-STK-04..10` MVP dışıdır / Post-MVP `OUT_OF_SCOPE`)* |
| **BR-POS** | Sepet ve Satış İşlemleri | 14 Kural | Kuruş bazlı tam sayı hesabı (`BR-POS-04`), atomik sepet satışı ve stok düşüşü (`BR-POS-07`), tam fiş iptali (`BR-POS-08`), kısmi iade tavan sınırı (`BR-POS-09`), hasarlı iadenin fireye ayrılması (`BR-POS-10`), sepet satırı gerekçeli fiyat müdahalesi (`BR-POS-11`). *(Not: Faz 1.2 kapsamında Kasa Satış Ekranı, sepet motoru ve atomik yerel satış/Outbox kaydı tamamlandı, kabul edildi ve push edildi [Commit `e9e1df5`]. Parked Carts `BR-POS-05` / `OD-02` MVP kapsamı dışındadır — `OUT_OF_SCOPE`; sanal numpad `OD-04` opsiyonel ve varsayılan kapalıdır. Tam fiş iptali `BR-POS-08` [Faz 1.3.3], kısmi ürün iadesi `BR-POS-09` [Faz 1.3.4] ve hasarlı/satılabilir iade ayrımı `BR-POS-10` [Faz 1.3.4] doğrudan Faz 1.3 kapsamındadır)* |
| **BR-PAY** | Ödeme Yönetimi | 5 Kural | Satış başına tek ödeme: yalnızca kanonik `'CASH'` (Nakit) veya `'CARD'` (Kart) sözleşmesi (`BR-PAY-01`; eski `'CREDIT_CARD'` ve `'NAKIT'` dizgeleri *obsolete*, eksik/geçersiz değerde sessiz `'CASH'` fallback yasaktır), nakit para üstü zorunlu doğrulaması (`BR-PAY-02`), kart ödemesinde tutarın banka POS terminaline manuel girilmesi (`BR-PAY-04`), hatalı ödeme düzeltme audit kaydı (`BR-PAY-05` — gereksinim korunmaktadır; operatör arayüzü ve düzeltme audit mekanizması henüz tamamlanmamıştır). |
| **BR-TNT** | Tenant ve Şube İzolasyonu | 5 Kural | Her kayıtta `tenant_id` zorunluluğu, bileşik foreign key `(tenant_id, store_id)` (`BR-TNT-02`), pilotta tek market tek mağaza standardı (`BR-TNT-03`). |
| **BR-SYNC** | Senkronizasyon & Outbox | 7 Kural | Kalıcı `sync_operations` / `outbox_operations` kuyruğu (`BR-SYNC-01`), deterministik artan `client_sequence_number` + katı FIFO (`BR-SYNC-03`), `idempotency_key` ile mükerrerlik koruması, ürün oluşturma için Hub zorunluluğu (`BR-SYNC-04` / `OD-03`), gerçekleşmiş satışların çakışmada asla silinmemesi (`BR-SYNC-06`) ve Legacy `'CREDIT_CARD'` Outbox kayıtlarının `updateAndRetryFailedOperation` ile atomik transaction/rollback altında `'CARD'`'a onarılıp FIFO'nun sürdürülmesi (`b069d5b`). *(Not: Yerel Outbox kaydı ve atomik transaction yazımı Faz 1.2'de tamamlanmıştır [Commit `e9e1df5`]; arka plan senkronizasyonu, HTTP aktarımı ve canlı kuyruk derinliği rozeti ise ayrı bir durum olarak doğrudan Faz 1.3.1 kapsamındadır)* |
| **BR-DSH** | Dashboard ve Finans | 4 Kural | Takvim günü bazlı ciro (`BR-DSH-01`), maliyeti girilmiş ürünler üzerinden brüt kâr hesabı (`BR-DSH-02` — gereksinim korunmaktadır; mevcut iş kararımız doğrultusunda MVP kapsamı dışında / Post-MVP olarak işaretlenmiştir), genel giderler olmadan net kâr iddiasında bulunmama ilkesi (`BR-DSH-03`). |
| **BR-BAK** | Yedekleme ve Kurtarma | 6 Kural | Bağımsız Google Drive yedeklemesi (`BR-BAK-01`), canlı SQLite `VACUUM INTO` snapshot'ı (`BR-BAK-03`), 30 günlük döngüsel saklama (`BR-BAK-04`), geri yükleme öncesi koruyucu güvenlik yedeği (`BR-BAK-05`), S5A-4 standardında AES-256-CBC + HMAC-SHA256 şifreleme (`BR-BAK-06`). |
| **BR-DEV** | Cihaz ve Donanım | 4 Kural | PC'de USB HID klavye taklitli barkod okuyucu (`BR-DEV-01`), mobilde kamera barkod tarama (`BR-DEV-02`), Windows ekranından QR kod ile cihaz eşleştirme (`BR-DEV-03`). |
| **BR-USR** | Kullanıcı ve Güvenlik | 4 Kural | Pilot aşamasında tek işletme sahibi hesabı (`BR-USR-01`), hassas işlemler için açık onay ve şifre gereksinimi (`BR-USR-03`). |

---

## 3. Fonksiyonel Olmayan Gereksinimler (NFR Özeti)

- **NFR-PERF-01 (Kasa Hızı):** Barkod okutulduğunda sepet satırı güncelleme süresi $\le 100\text{ ms}$ olmalıdır.
- **NFR-PERF-02 (Açılış Süresi):** Windows ve mobil uygulamanın yerel veritabanıyla açılış süresi $\le 2\text{ saniye}$ olmalıdır.
- **NFR-DATA-01 (Finansal Kesinlik):** Para hesaplamalarında yuvarlama hatası payı 0'dır; kayan noktalı sayı (`double`) aritmetiği kullanılamaz. Dahili parasal değerler kuruş tamsayı (`int`) olarak tutulur, alt kuruş hesaplamalarında **Half-Up yuvarlama (`OD-01`)** uygulanır ve kullanıcı arayüzü gösterim standardı **`12.50 TL`**dir.
- **NFR-OFFLINE-01 (Çevrimdışı Çalışma):** Ağ bağlantısı olmasa dahi satış işlemleri süresiz olarak yerel veritabanında yürütülebilmelidir (`OD-03`: yerel DB'de bulunan ürünler offline satılabilir; yeni ürün oluşturma Hub gerektirir).

*Ayrıntılı kural metinleri, hata senaryoları ve istisnalar için [`docs/requirements/BUSINESS_RULES_SPEC.md`](./requirements/BUSINESS_RULES_SPEC.md) (`v1.6`) belgesi referans alınmalıdır.*
