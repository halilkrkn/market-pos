# REQUIREMENTS.md — MARKET MMS İş ve Sistem Gereksinimleri İndeksi

**Belge Sürümü:** v1.0  
**Tarih:** 4 Kasım 2026  
**Aşama:** Faz 0 — İş Gereksinimleri ve Kabul Kriterleri  
**Ana Şartname:** [`docs/requirements/BUSINESS_RULES_SPEC.md`](./requirements/BUSINESS_RULES_SPEC.md) (v1.2 — 159 BR + 21 NFR)  
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
| **BR-PROD** | Ürün ve Kategori Yönetimi | 16 Kural | Çoklu aktif barkod (`BR-PROD-02`), barkodsuz ekmek hızlı tuşu (`BR-PROD-04`), pasifleştirme (`BR-PROD-03`), Open Food Facts önerisi (`BR-PROD-06`), pay/payda rasyonel birim dönüşümü (`BR-PROD-08`), snapshot maliyet kopyalama (`BR-PROD-13`). |
| **BR-STK** | Stok ve Envanter Yönetimi | 10 Kural | 9 stok hareket türü (`BR-STK-01`), eksi stok serbestliği (`BR-STK-02`), raftan satışın faturadan önce yapılabilmesi (`BR-STK-03`), mağaza sayımı ve uzlaştırması (`BR-STK-08`). |
| **BR-POS** | Sepet ve Satış İşlemleri | 14 Kural | Kuruş bazlı tam sayı hesabı (`BR-POS-04`), atomik sepet satışı ve stok düşüşü (`BR-POS-05`), tam fiş iptali (`BR-POS-08`), kısmi iade tavan sınırı (`BR-POS-09`), hasarlı iadenin fireye ayrılması (`BR-POS-10`), sepet satırı gerekçeli fiyat müdahalesi (`BR-POS-11`). |
| **BR-PAY** | Ödeme Yönetimi | 5 Kural | Satış başına tek ödeme (Nakit veya Kart) (`BR-PAY-01`), nakit para üstü zorunlu doğrulaması (`BR-PAY-02`), kart ödemesinde tutarın banka POS terminaline manuel girilmesi (`BR-PAY-04`), hatalı ödeme düzeltme audit kaydı (`BR-PAY-05`). |
| **BR-TNT** | Tenant ve Şube İzolasyonu | 5 Kural | Her kayıtta `tenant_id` zorunluluğu, bileşik foreign key `(tenant_id, store_id)` (`BR-TNT-02`), pilotta tek market tek mağaza standardı (`BR-TNT-03`). |
| **BR-SYNC** | Senkronizasyon & Outbox | 7 Kural | Kalıcı `sync_operations` kuyruğu (`BR-SYNC-01`), deterministik artan `client_sequence_number` (`BR-SYNC-03`), `idempotency_key` ile mükerrerlik koruması, gerçekleşmiş satışların çakışmada asla silinmemesi (`BR-SYNC-06`). |
| **BR-DSH** | Dashboard ve Finans | 4 Kural | Takvim günü bazlı ciro (`BR-DSH-01`), maliyeti girilmiş ürünler üzerinden brüt kâr hesabı (`BR-DSH-02`), genel giderler olmadan net kâr iddiasında bulunmama ilkesi (`BR-DSH-03`). |
| **BR-BAK** | Yedekleme ve Kurtarma | 6 Kural | Bağımsız Google Drive yedeklemesi (`BR-BAK-01`), canlı SQLite `VACUUM INTO` snapshot'ı (`BR-BAK-03`), 30 günlük döngüsel saklama (`BR-BAK-04`), geri yükleme öncesi koruyucu güvenlik yedeği (`BR-BAK-05`), S5A-4 standardında AES-256-CBC + HMAC-SHA256 şifreleme (`BR-BAK-06`). |
| **BR-DEV** | Cihaz ve Donanım | 4 Kural | PC'de USB HID klavye taklitli barkod okuyucu (`BR-DEV-01`), mobilde kamera barkod tarama (`BR-DEV-02`), Windows ekranından QR kod ile cihaz eşleştirme (`BR-DEV-03`). |
| **BR-USR** | Kullanıcı ve Güvenlik | 4 Kural | Pilot aşamasında tek işletme sahibi hesabı (`BR-USR-01`), hassas işlemler için açık onay ve şifre gereksinimi (`BR-USR-03`). |

---

## 3. Fonksiyonel Olmayan Gereksinimler (NFR Özeti)

- **NFR-PERF-01 (Kasa Hızı):** Barkod okutulduğunda sepet satırı güncelleme süresi $\le 100\text{ ms}$ olmalıdır.
- **NFR-PERF-02 (Açılış Süresi):** Windows ve mobil uygulamanın yerel veritabanıyla açılış süresi $\le 2\text{ saniye}$ olmalıdır.
- **NFR-DATA-01 (Finansal Kesinlik):** Para hesaplamalarında yuvarlama hatası payı 0'dır; kayan noktalı sayı (`double`) aritmetiği kullanılamaz.
- **NFR-OFFLINE-01 (Çevrimdışı Çalışma):** Ağ bağlantısı olmasa dahi satış işlemleri süresiz olarak yerel veritabanında yürütülebilmelidir.

*Ayrıntılı kural metinleri, hata senaryoları ve istisnalar için [`docs/requirements/BUSINESS_RULES_SPEC.md`](./requirements/BUSINESS_RULES_SPEC.md) belgesi referans alınmalıdır.*

