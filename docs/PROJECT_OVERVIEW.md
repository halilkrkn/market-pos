# PROJECT_OVERVIEW.md — MARKET MMS Proje Genel Bakışı

**Belge Sürümü:** v1.0  
**Tarih:** 4 Kasım 2026  
**Aşama:** Faz 1 — MVP Uygulama ve Doğrulama (Faz 1.1 Kabul Edildi)  
**Kanonik Referans:** [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](../MARKET_POS_AI_STUDIO_BUILD_PLANI.md)  
**Kök Kurallar:** [`AGENTS.md`](../AGENTS.md)

---

## 1. Ürün Tanımı ve Hedef Kitle

**MARKET MANAGEMENT SYSTEM (MMS)**; küçük ve orta ölçekli perakende marketlerin (bakkal, süpermarket, şarküteri) günlük operasyonlarını modern, güvenli ve kesintisiz bir biçimde yönetmek üzere tasarlanmış masaüstü ve mobil destekli bir market otomasyon yazılımıdır.

### Pilot Hedefi ve Vizyon:
- **İlk Aşama (Pilot):** Gerçek bir mahalle marketinde Windows ana kasa ve işletme sahibinin Android/iOS telefonlarıyla aktif saha kullanımı.
- **Uzun Vadeli Hedef:** Çok şubeli zincir marketleri ve bağımsız marketleri destekleyen kurumsal bir SaaS platformuna dönüşüm.

---

## 2. Temel Ürün Modülleri (Kapsam)

MMS, perakende operasyonunu 10 entegre modül üzerinden yürütür:

1. **Hızlı Sepet ve Satış Yönetimi (POS):** USB HID barkod okuyucu ve telefon kamerası ile saniyeler içinde ürün ekleme, adet artırma, kuruş hassasiyetinde toplam tutar hesabı ve fiş oluşturma.
2. **Ürün ve Kategori Kataloğu:** Çoklu aktif barkod desteği (`product_barcodes`), hiyerarşik kategoriler, barkodsuz ekmek hızlı tuşu, Open Food Facts öneri mekanizması.
3. **Stok ve Envanter Yönetimi:** Atomik birimler (adet, gram, ml), pay/payda rasyonel dönüşümü, 9 stok hareket türü, eksi stok serbestliği (`allow`), mağaza içi sayım oturumları.
4. **Fiyat ve Maliyet Yönetimi:** Fiyat değişiklik geçmişi (`price_history`), gizli alış maliyeti geçmişi (`cost_history`), satış anında satıra kopyalanan snapshot fiyatlar.
5. **Ödeme Yönetimi:** Satış başına tek ödeme (Nakit veya Kart), nakit para üstü otomatik hesabı, hatalı ödeme düzeltme denetim izi. (Banka POS cihaz entegrasyonu MVP dışıdır).
6. **İptal ve Kısmi İade Yönetimi:** Tam satış iptali ile kısmi ürün iadesinin muhasebesel ayrımı; satılan miktarın üzerinde iade yapılmasını engelleyen koşullu veritabanı kilitleri.
7. **Çoklu Cihaz ve Senkronizasyon:** Windows bilgisayar kapalıyken bile mobil cihazlarda yerel satış; Windows açıldığında LAN üzerinden deterministik FIFO Outbox senkronizasyonu.
8. **Dashboard ve Finansal Doğruluk:** Günlük ciro, brüt kâr (maliyeti girilmiş ürünler üzerinden), kritik stoklar ve son hareketler.
9. **Kullanıcı ve Cihaz Yönetimi:** Tek işletme sahibi hesabı, Windows ekranından QR kod ile dinamik mobil cihaz eşleştirme, kalıcı cihaz kimliği (`device_id`).
10. **Yedekleme ve Kurtarma:** SQLite WAL canlı anlık görüntüsü (`VACUUM INTO`), istemci taraflı S5A-4 standardında `AES-256-CBC` + `HMAC-SHA256` (Encrypt-then-MAC) şifreleme ve bağımsız Google Drive yedeklemesi.

---

## 3. Sistem Mimarisi İlkeleri

1. **Windows Local Master Hub:** Windows bilgisayar ana sunucudur. Arka plandaki **Windows Service** merkezi SQLite veritabanına tekil yazıcı (Single-Writer) olarak hükmeder.
2. **Çevrimdışı Çalışabilirlik (Offline-First):** Mağazada internet tamamen kopsa dahi yerel Wi-Fi / LAN üzerinden tüm cihazlar Windows ile senkronize çalışır; Windows kapalıysa mobil cihazlar yerelde fiş keser.
3. **Kuruş Bazlı Tamsayı:** Asla `double` veya kayan noktalı sayı aritmetiği kullanılmaz. 150.50 TL = `15050` kuruş tamsayıdır.
4. **Fiziksel Silmeme (Soft-Delete & Immutability):** Ürünler, satışlar ve stok hareketleri sessizce silinemez; append-only defter tutulur.
5. **SaaS Hazırlığı:** `tenant_id` ve `store_id` alanları tüm şemada korunarak gelecekte buluta taşınabilirlik garanti edilir.

