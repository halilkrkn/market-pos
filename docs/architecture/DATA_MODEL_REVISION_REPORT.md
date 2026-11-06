# Market Management System (MMS) — Mantıksal Veri Modeli Revizyon Raporu (Data Model Revision Report v1.1)

**Doküman Kodu:** `DATA_MODEL_REVISION_REPORT.md`  
**Sürüm:** 1.1 (Nihai Revizyon ve Sertleştirme)  
**Tarih:** 31 Ekim 2026  
**Durum:** Faz 0 — Mantıksal Veri Modeli Revizyonu ve Teknik Kapatma Tamamlandı  
**Kaynak Denetim Belgeleri:** `docs/architecture/DATA_MODEL_REVIEW.md` (v1.0), `docs/architecture/DATA_MODEL_V1_1_TECHNICAL_VALIDATION.md` (v1.0)  
**Güncellenen Belgeler:**  
1. `docs/architecture/DATA_MODEL.md` (v1.1)  
2. `docs/architecture/DATA_MODEL_DECISIONS.md` (v1.1)  
3. `docs/architecture/DATA_MODEL_V1_1_TECHNICAL_VALIDATION.md` (v1.1)  
4. `docs/PROJECT_STATUS.md`  
**Teknik Proje / Klasör Adı:** `market-pos`  
**Ürün Tanımı:** Market Management System (MMS) — Profesyonel Market Yönetim SaaS Uygulaması  

---

## 1. Giriş ve Amaç

Bu rapor; Faz 0 kapsamında hazırlanan mantıksal veri modelinin bağımsız teknik denetimi (`DATA_MODEL_REVIEW.md` v1.0) ve bağımsız teknik doğrulaması (`DATA_MODEL_V1_1_TECHNICAL_VALIDATION.md` v1.0) sonucunda tespit edilen tüm bulguların (`FND-01` .. `FND-05`, `EK-01` .. `EK-04`, `NEW-01` .. `NEW-04`) kapatılması amacıyla gerçekleştirilen şema sertleştirmelerini, ek kısıtları ve mimari kararları belgeler.

---

## 2. Bulgular ve Yapılan Düzeltmeler Kapanış Matrisi

| Bulgu Kodu | Kategori | İlgili Tablo(lar) | Yapılan Revizyon ve Çözüm Özeti | Durum |
|---|---|---|---|---|
| **`FND-01`** | **HIGH** | `product_barcodes` | `barcode_history` tablosu `product_barcodes` içine çekildi. Küresel `UNIQUE (tenant_id, barcode)` deklaratif kısıtı ile pasif barkodların mükerrer kullanımı DB motoru seviyesinde engellendi; hızlı arama için kısmi indeks (`idx_active_product_barcodes`) konuldu. | **KAPATILDI** |
| **`FND-02`** | **HIGH** | `products` | "Atomik Stok Birimi Prensibi" benimsendi (`stock_unit` daima adet, gram vb.). Periyodik bölme ($1/24$) kayıplarını sıfırlamak için `conversion_factor_numerator` ve `conversion_factor_denominator` rasyonel tamsayı alanları eklendi. | **KAPATILDI** |
| **`FND-03`** | **MEDIUM** | Şube Tabloları | `stores` tablosuna `UNIQUE (tenant_id, id)` eklendi. Şube tabanlı 9 operasyonel tabloda `FOREIGN KEY (tenant_id, store_id) REFERENCES stores(tenant_id, id) ON DELETE RESTRICT` bileşik yabancı anahtarı zorunlu kılındı. | **KAPATILDI** |
| **`FND-04`** | **MEDIUM** | `sale_items`, `refunds` | `sale_items` tablosuna `refunded_quantity` ve `CHECK (refunded_quantity <= quantity)` kısıtı eklendi. Eşzamanlı iadeler için satır kilitleme (`SELECT FOR UPDATE`), atomik koşullu güncelleme `(refunded_quantity + :qty) <= quantity`, `refunds.idempotency_key` ve çevrimdışı çoklu cihaz çakışmasında `sync_operations.status = 'CONFLICT'` protokolü tanımlandı. | **KAPATILDI** |
| **`FND-05`** | **MEDIUM** | `stock_count_items` | `client_counted_at` ve `server_reconciled_at` zaman damgaları ayrıldı. Tek cihazda nedensel sıra `client_sequence_number` ile çözüldü; çoklu cihaz çevrimdışı çakışmaları için `is_ambiguous_interval` belirsizlik bayrağı ve $\pm 5$ dk pencere uzlaştırma kuralı tanımlandı. | **KAPATILDI** |
| **`EK-01`** | **MEDIUM** | `refund_items`, `stock_movements` | Hasarlı iadelerde (`condition = 'DAMAGED'`) satılabilir stoğun (`current_stock`) kesinlikle artırılmayacağı veya mükerrer eksiltilmeyeceği (net 0), `stock_movements` tablosuna `FIRE_KAYIP` denetim izi yazılacağı netleştirildi. | **KAPATILDI** |
| **`EK-02`** | **MEDIUM** | `sync_operations` | Offline senkronizasyon yerel Outbox tablosu 25. tablo olarak veri modeline dahil edildi. | **KAPATILDI** |
| **`EK-03`** | **LOW** | RLS İzolasyonu | Çoklu üyelikli kullanıcılarda RLS filtresi için JWT claim veya oturum değişkeni bağlamı kararlaştırıldı. | **KAPATILDI** |
| **`EK-04`** | **LOW** | `sales` | Satış iptalinin idempotent olduğu (`status = 'CANCELLED'`) teyit edildi. | **KAPATILDI** |
| **`NEW-01`** | **MEDIUM** | `sales` | Tablo düzeyinde birleşik `chk_sales_payment_consistency` CHECK kısıtı eklendi. Nakit satışta alınan tutarın zorunluluğu, toplamdan az olamayacağı ve para üstünün kuruşu kuruşuna eşitliği; kartta ise nakit alanlarının `NULL` olması garanti altına alındı. | **KAPATILDI** |
| **`NEW-02`** | **MEDIUM** | `sync_operations` | Cihaz bazında monotonik artan `client_sequence_number BIGINT NOT NULL` alanı ve `UNIQUE (device_id, client_sequence_number)` kısıtı eklendi. İşlemlerin deterministik FIFO sırası garantiye alındı. | **KAPATILDI** |
| **`NEW-03`** | **LOW** | `audit_logs` | Nullable `store_id` için `FOREIGN KEY (tenant_id, store_id) REFERENCES stores(tenant_id, id) ON DELETE SET NULL` bileşik yabancı anahtarı tanımlandı (`MATCH SIMPLE` standardı). | **KAPATILDI** |
| **`NEW-04`** | **LOW** | Domain Validasyonu | Ürün kartı açılırken `stock_unit` değerinin bölünemez atomik birim olması kuralı Domain Use Case / Validator katmanında zorunlu iş kuralı olarak belgelendi. | **KAPATILDI** |

---

## 3. Tablo Sayısı ve Varlık Organizasyonu Değişimi

- **Nihai Tablo Sayısı:** **25 Tablo** (24 Operasyon/Katalog Tablosu + 1 Offline Senkronizasyon Tablosu).
- **Tablo Grupları:**
  1. Tenant, Organizasyon ve Kullanıcı: `tenants`, `stores`, `users`, `memberships`, `devices` (5 tablo)
  2. Ürün ve Kategori Kataloğu: `categories`, `products`, `product_barcodes`, `product_images` (4 tablo)
  3. Fiyat ve Maliyet Geçmişi: `price_history`, `cost_history` (2 tablo)
  4. Stok Yönetimi ve Sayım: `stock_balances`, `stock_movements`, `stock_counts`, `stock_count_items` (4 tablo)
  5. Satış, Sepet ve POS: `held_carts`, `held_cart_items`, `sales`, `sale_items` (4 tablo)
  6. İade ve Ödeme Düzeltme: `refunds`, `refund_items`, `payment_method_corrections` (3 tablo)
  7. Güvenlik ve Denetim: `audit_logs`, `device_sessions` (2 tablo)
  8. Offline-First Senkronizasyon: `sync_operations` (1 tablo)

---

## 4. Yapılan Son Alan ve Kısıt Güncellemeleri

1. **`sales` Tablosu (`NEW-01`):**
   - Kolon bazlı kısıtlar kaldırıldı; tablo düzeyinde `chk_sales_payment_consistency` koşullu kısıtı tanımlandı.
2. **`sync_operations` Tablosu (`NEW-02`):**
   - `client_sequence_number: BIGINT NOT NULL` alanı eklendi.
   - `UNIQUE (device_id, client_sequence_number)` kısıtı ve `idx_sync_queue_order` indeksi eklendi.
3. **`audit_logs` Tablosu (`NEW-03`):**
   - `FOREIGN KEY (tenant_id, store_id) REFERENCES stores(tenant_id, id) ON DELETE SET NULL` bileşik FK tanımlandı.
4. **`refunds` Tablosu (`FND-04`):**
   - `idempotency_key: TEXT NOT NULL` ve `UNIQUE (tenant_id, idempotency_key)` kısıtı eklendi.
5. **`stock_count_items` Tablosu (`FND-05`):**
   - `is_ambiguous_interval: BOOLEAN NOT NULL DEFAULT false` alanı eklendi.

---

## 5. Sonuç

Tüm teknik bulgular (`FND-01` .. `FND-05`) ve bağımsız doğrulama maddeleri (`NEW-01` .. `NEW-04`) veri modeli ve karar kayıtları seviyesinde eksiksiz olarak kapatılmıştır.  
Veri modeli dokümantasyonu Faz 0 mimari hedefleriyle tam uyumlu olup, bir sonraki aşama olan **Offline Senkronizasyon ve Outbox Kuyruğu Protokolü Tasarımı**na geçişe hazırdır.
