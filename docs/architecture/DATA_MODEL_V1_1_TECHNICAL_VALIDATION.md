# Market Management System (MMS) — Mantıksal Veri Modeli v1.1 Bağımsız Teknik Doğrulama Raporu (Technical Validation Report)

**Doküman Kodu:** `DATA_MODEL_V1_1_TECHNICAL_VALIDATION.md`  
**Sürüm:** 1.1 (Nihai Kapanış ve Doğrulama)  
**Tarih:** 31 Ekim 2026  
**Durum:** Faz 0 — Mantıksal Veri Modeli v1.1 Teknik Doğrulaması (Tüm Bulgular Kapatıldı)  
**Denetlenen Belgeler:**  
1. `docs/architecture/DATA_MODEL.md` (v1.1)  
2. `docs/architecture/DATA_MODEL_DECISIONS.md` (v1.1)  
3. `docs/architecture/DATA_MODEL_REVISION_REPORT.md` (v1.1)  
4. `docs/architecture/DATA_MODEL_REVIEW.md` (v1.0)  
5. `docs/requirements/BUSINESS_RULES_SPEC.md` (v1.2)  
6. `docs/requirements/PHASE_0_BUSINESS_DISCOVERY.md` (v1.3)  
7. `MARKET_POS_AI_STUDIO_BUILD_PLANI.md` (v1.2.2)  
8. `docs/PROJECT_STATUS.md`  
**Teknik Proje / Klasör Adı:** `market-pos`  
**Ürün Tanımı:** Market Management System (MMS) — Profesyonel Market Yönetim SaaS Uygulaması  

---

## 1. Genel Değerlendirme

Bu bağımsız teknik doğrulama çalışması, **Market Management System (MMS)** projesinde Faz 0 kapsamında hazırlanan mantıksal veri modelinin revize edilmiş ve sertleştirilmiş **v1.1** sürümünü (`DATA_MODEL.md` ve `DATA_MODEL_DECISIONS.md`), ilk teknik denetim raporundaki (`DATA_MODEL_REVIEW.md`) bulguların (`FND-01` .. `FND-05`, `EK-01` .. `EK-04`) ve yeni doğrulama bulgularının (`NEW-01` .. `NEW-04`) çözülme durumunu eleştirel bir gözle incelemiştir.

### Temel Doğrulama Özeti:
- **Kritik Hata (CRITICAL):** Tasarımda sistemi durduracak, veri kaybına yol açacak veya mimariyi çökertecek **hiçbir `CRITICAL` bulgu tespit edilmemiştir**.
- **Tüm Bulguların Kapanışı:** İlk denetimde raporlanan `FND-01`, `FND-02`, `FND-03`, `FND-04` ve `FND-05` teknik bulguları ile doğrulama sırasında tespit edilen `NEW-01` .. `NEW-04` maddeleri veri modeli ve karar kayıtları seviyesinde **eksiksiz olarak uygulanmış ve kapatılmıştır**.
- **İş Kurallarıyla Tutarlılık:** Veri modeli, bağlayıcı iş belgeleriyle (`BUSINESS_RULES_SPEC.md` v1.2 ve `PHASE_0_BUSINESS_DISCOVERY.md` v1.3) %100 uyumludur; hiçbir çelişki bulunmamaktadır.
- **Sonraki Aşamaya Geçiş:** Veri modeli ve karar kayıtları, projenin sonraki adımı olan **Offline Senkronizasyon ve Outbox Kuyruğu Protokolü Tasarımı**na geçişe tam olarak hazırdır.

---

## 2. Bulguların Nihai Kapanış Durumu (Findings Resolution Matrix)

| Bulgu Kodu | Başlık ve İlk Tespit | Uygulanan Nihai Çözüm ve Kapanış Kanıtı | Kapanış Sonucu |
|---|---|---|---|
| **`FND-01`** | Aktif ve pasif barkodlar arasında çapraz tekillik kısıtı eksikliği | `barcode_history` kaldırılarak `product_barcodes` içine çekildi. Küresel `UNIQUE (tenant_id, barcode)` deklaratif kısıtı ile pasif bir barkodun sistemdeki başka bir ürüne mükerrer atanması DB motoru seviyesinde kesin olarak engellendi. Arama için kısmi benzersiz indeks (`idx_active_product_barcodes`) konuldu. | **KAPATILDI (`RESOLVED`)** |
| **`FND-02`** | Birim dönüşümünde periyodik bölme ve yuvarlama sapması riski | "Atomik Stok Birimi Prensibi" benimsendi (`stock_unit` daima adet, gram vb.). `products` tablosuna `conversion_factor_numerator` ve `conversion_factor_denominator` rasyonel tamsayı oranları eklendi. Dönüşümler tamsayı çarpımıyla yapıldığından periyodik bölme sapması sıfırlandı. | **KAPATILDI (`RESOLVED`)** |
| **`FND-03`** | Şube tablolarında bileşik foreign key `(tenant_id, store_id)` eksikliği | `stores` tablosuna `UNIQUE (tenant_id, id)` eklendi. Şube tabanlı 9 operasyonel tabloda `FOREIGN KEY (tenant_id, store_id) REFERENCES stores(tenant_id, id) ON DELETE RESTRICT` bileşik yabancı anahtarı zorunlu kılındı. Tenantlar arası çapraz şube ataması donanımsal olarak engellendi. | **KAPATILDI (`RESOLVED`)** |
| **`FND-04`** | Çoklu kısmi iadelerde eşzamanlı yarış, satılan miktarın aşılması ve offline çakışma riski | `sale_items` tablosuna `refunded_quantity` ve `CHECK (refunded_quantity <= quantity)` eklendi. Yalnızca kısıtla yetinilmeyip: Satır kilitleme (`SELECT FOR UPDATE`), atomik koşullu güncelleme `(refunded_quantity + :qty) <= quantity`, `refunds.idempotency_key` ve çevrimdışı çoklu cihaz çakışmasında `sync_operations.status = 'CONFLICT'` çözüm protokolü tasarlandı. | **KAPATILDI (`RESOLVED`)** |
| **`FND-05`** | Sayım uzlaştırmasında cihaz saat sapması (clock drift) ve nedensel sıralama | `client_counted_at` ve `server_reconciled_at` ayrıldı. Tek cihazda nedensel sıra `sync_operations.client_sequence_number` ile deterministik çözüldü. Çoklu cihaz çevrimdışı senaryosunda ise kesin olarak bilinemeyen sıralama için $\pm 5$ dakikalık belirsizlik aralığı (`is_ambiguous_interval = true`) ve denetimli uzlaştırma kuralı tanımlandı. | **KAPATILDI (`RESOLVED`)** |
| **`EK-01`** | Hasarlı iade stok düşümü davranışı | Hasarlı iadelerde (`condition = 'DAMAGED'`) satılabilir stoğun (`current_stock`) kesinlikle artırılmayacağı veya mükerrer eksiltilmeyeceği (net 0), `stock_movements` tablosuna `FIRE_KAYIP` denetim izi yazılacağı netleştirildi. | **KAPATILDI (`RESOLVED`)** |
| **`EK-02`** | Yerel Outbox kuyruk tablosu | `sync_operations` tablosu şemaya 25. tablo olarak eklendi. | **KAPATILDI (`RESOLVED`)** |
| **`EK-03`** | Çoklu üyelikli kullanıcılarda RLS alt sorgusu | RLS filtrelerinde tekil alt sorgu yerine JWT claim (`app_metadata.tenant_id`) veya oturum değişkeni bağlamı kararlaştırıldı. | **KAPATILDI (`RESOLVED`)** |
| **`EK-04`** | Satış iptalinde idempotency güvencesi | `sales.status = 'CANCELLED'` güncellemesiyle iptalin idempotent çalıştığı ve ciro raporlarından `status = 'COMPLETED'` filtresiyle düştüğü teyit edildi. | **KAPATILDI (`RESOLVED`)** |
| **`NEW-01`** | `sales` tablosunda ödeme yöntemi ile nakit alanları tutarlılığı | `sales` tablosuna tablo düzeyinde birleşik `chk_sales_payment_consistency` CHECK kısıtı eklendi. Nakitte alınan tutarın zorunluluğu, toplamdan az olamayacağı ve para üstünün kuruşu kuruşuna eşitliği; kartta ise nakit alanlarının `NULL` olması garanti altına alındı. | **KAPATILDI (`RESOLVED`)** |
| **`NEW-02`** | `sync_operations` deterministik FIFO sıralaması | Cihaz bazında monotonik artan `client_sequence_number BIGINT NOT NULL` alanı ve `UNIQUE (device_id, client_sequence_number)` kısıtı eklendi. Zaman damgası çakışmalarından bağımsız kesin sıra sağlandı. | **KAPATILDI (`RESOLVED`)** |
| **`NEW-03`** | `audit_logs` nullable şube bileşik FK eksikliği | `audit_logs` tablosunda `FOREIGN KEY (tenant_id, store_id) REFERENCES stores(tenant_id, id) ON DELETE SET NULL` bileşik yabancı anahtarı tanımlandı (`MATCH SIMPLE` standardı). | **KAPATILDI (`RESOLVED`)** |
| **`NEW-04`** | Atomik stok birimi domain validasyonu | Ürün kartı açılırken `stock_unit` değerinin bölünemez atomik birim olması kuralı Domain Use Case / Validator katmanında zorunlu iş kuralı olarak belgelendi. | **KAPATILDI (`RESOLVED`)** |

---

## 3. İş Kurallarıyla Tutarlılık İncelemesi (Business Rules Traceability)

Veri modeli v1.1, bağlayıcı iş belgeleriyle karşılaştırılmış ve 11 ana denetim konusu doğrulanmıştır:

### 3.1 Aktif ve Pasif Barkod Tekilliği (`BR-PROD-02`, `BR-PROD-15`)
- `product_barcodes` tablosundaki `UNIQUE (tenant_id, barcode)` deklaratif kısıtı, aktif veya pasif fark etmeksizin aynı barkodun ikinci bir ürüne kaydedilmesini kesin olarak önler.
- `idx_active_product_barcodes` kısmi benzersiz indeksi ise kasadaki barkod okuma performansını milisaniye seviyesinde tutar.
- **Sonuç:** **%100 TUTARLI.**

### 3.2 Rasyonel Birim Dönüşüm Doğrulaması (`BR-PROD-07`, `BR-PROD-08`)
- **Adet & Paket/Koli:** 1 Koli = 24 Adet. Stok birimi: `adet`. Satış/mal kabul: 1 Koli $\to 1 \times (24 / 1) = 24$ adet düşer/eklenir. (Tam sayı, sıfır yuvarlama hatası).
- **Gram & Kilogram:** Stok birimi: `g`. 450 gram tartılı satış $\to 0.450 \text{ kg} \times (1000 / 1) = 450\text{ g}$. Tutar: $0.450 \times \text{Kg Fiyatı}$. (Kuruş bazında tam sayı hesaplanır).
- **Litre & Mililitre:** Stok birimi: `ml`. Pay=1000, Payda=1. Sıfır kayıp.
- **Sonuç:** **%100 TUTARLI.**

### 3.3 Tenant ve Store İzolasyonu (`BR-TNT-02`, `BR-TNT-03`)
- `stores(tenant_id, id)` bileşik kısıtı, 9 operasyonel tablodaki `(tenant_id, store_id)` bileşik FK yapısı ve `audit_logs` üzerindeki `MATCH SIMPLE` bileşik kısıtı sayesinde hiçbir şube verisi yanlış tenant altına sızamaz.
- **Sonuç:** **%100 TUTARLI.**

### 3.4 Çoklu Kısmi İadeler (`BR-POS-09`)
- `sale_items.refunded_quantity` alanı, `CHECK (refunded_quantity >= 0 AND refunded_quantity <= quantity)` kısıtı, satır kilitleme, atomik koşullu güncelleme ve `refunds.idempotency_key` ile satılan miktarın aşılması her düzeyde engellenmiştir.
- **Sonuç:** **%100 TUTARLI.**

### 3.5 Çevrimdışı Sayım ve Saat Sapması (`BR-STK-08`, `BR-STK-09`)
- `stock_count_items.client_counted_at`, `server_reconciled_at` ve `is_ambiguous_interval` alanları mevcuttur. Tek cihazda sıra numarası ile nedensellik garantilenmiş, çoklu cihazda ise belirsizlik aralığı protokolü tanımlanmıştır.
- **Sonuç:** **%100 TUTARLI.**

### 3.6 Hasarlı İadede Stok Bütünlüğü (`BR-POS-10`)
- Hasarlı iadede (`condition = 'DAMAGED'`), `stock_balances.current_stock` artırılmaz veya eksiltilmez; net stok değişimi 0'dır. `stock_movements` tablosuna `FIRE_KAYIP` denetim izi yazılır. Satılabilir stoğa bozuk ürün girmez.
- **Sonuç:** **%100 TUTARLI.**

### 3.7 `sync_operations` ve Offline Yaşam Döngüsü (`BR-SYNC-01`, `BR-SYNC-03`)
- `client_sequence_number` (monotonik artan sıra) ve durum yaşam döngüsü (`PENDING`, `SYNCING`, `COMPLETED`, `FAILED`, `CONFLICT`) ile yerel Outbox kuyruğu tam ve deterministiktir.
- **Sonuç:** **%100 TUTARLI.**

### 3.8 Çoklu Tenant Üyeliği ve RLS (`BR-SEC-02`, `BR-TNT-03`)
- RLS tasarımında scalar subquery yerine JWT claim veya oturum değişkeni bağlamı benimsenerek çoklu tenant üyeliği desteklenmiştir.
- **Sonuç:** **%100 TUTARLI.**

### 3.9 Ödeme Alanları ve Kısıtları (`BR-PAY-01`, `BR-PAY-02`)
- Tablo düzeyinde deklaratif `chk_sales_payment_consistency` kısıtı ile nakit ve kartlı satış tutarlılığı tam güvenceye alınmıştır.
- **Sonuç:** **%100 TUTARLI.**

### 3.10 Sayım Onayında Atomik Stok Güncellemesi (`BR-STK-04`, `BR-STK-10`)
- `stock_counts.status` geçişi tek yönlüdür (`DRAFT` $\to$ `COMPLETED`). Onay anında `stock_balances` ve `stock_movements` atomik transaction içinde bir kez işletilir.
- **Sonuç:** **%100 TUTARLI.**

### 3.11 Keşif ve Şartname Belgeleriyle Çelişki Durumu
- `MARKET_POS_AI_STUDIO_BUILD_PLANI.md` (v1.2.2), `BUSINESS_RULES_SPEC.md` (v1.2) ve `PHASE_0_BUSINESS_DISCOVERY.md` (v1.3) ile veri modeli v1.1 arasında **hiçbir çelişki bulunmamaktadır**.

---

## 4. Veri Bütünlüğü ve Transaction Değerlendirmesi

1. **Transaction Sınırları:**
   - Satış işlemi: `sales`, `sale_items`, `stock_balances`, `stock_movements`, `sync_operations` ve `held_carts` tek atomik transaction içinde yürütülür.
   - İade işlemi: `refunds`, `refund_items`, `sale_items` (`refunded_quantity` artışı), `stock_balances`, `stock_movements` ve `sync_operations` tek atomik transaction içinde yürütülür.
   - Sayım onayı: `stock_counts` (`status = 'COMPLETED'`), `stock_count_items`, `stock_balances` ve `stock_movements` tek atomik transaction içinde yürütülür.
2. **Kayıp Güncelleme (Lost Update) ve Concurrency:**
   - `sale_items.refunded_quantity` üzerinde satır bazlı kilit ve koşullu update (`(refunded_quantity + :qty) <= quantity`) çalıştığı için eşzamanlı iadeler birbirini ezemez.
3. **Idempotency Koruması:**
   - `sales.idempotency_key` ve `refunds.idempotency_key` üzerindeki tekil kısıtlar ağ kesintilerinde mükerrer işlem oluşmasını kesin olarak önler.

---

## 5. Offline-First Uyumluluk

- **Dağıtık Anahtar Üretimi:** Tüm birincil anahtarların (`id`) UUID olması istemcide çevrimdışıyken bağımsız kimlik üretimine olanak tanır.
- **Yerel Outbox Mimarisi:** `sync_operations` tablosunda `client_sequence_number` ile yerel SQLite tablosuna yazılır ve sunucuya FIFO sıralı boşaltılır.
- **Snapshot Değişmezliği:** Ürün kartındaki fiyatlar değişse bile `sale_items` ve `held_cart_items` tablolarındaki snapshot alanları offline çalışan cihazların geçmiş veriyi bozmasını engeller.
- **Kısmi İndeks Desteği:** SQLite 3.8.0+ sürümünden bu yana kısmi indeksleri yerel olarak tam desteklemektedir. Drift ile uyum tamdır.

---

## 6. Açık ve Öneri Kapsamındaki Teknik Kararlar Özeti

| Madde No | Konu | Durum | Planlanan Aşama / Açıklama |
|---|---|---|---|
| 1 | Çevrimdışı çoklu cihaz sayım belirsizlik penceresi ($\pm 5$ dk) uzlaştırma arayüzü | `[PROPOSED]` | Faz 0 Senkronizasyon Protokolü Tasarımı |
| 2 | Sepet ve sayım kilidi lease süreleri (30 sn kalp atışı / 2 dk timeout) | `[PROPOSED]` | Saha ağ testleri ve Senkronizasyon Tasarımı |
| 3 | Hasarlı iade karantina deposu tablosu (`damaged_stock_balances`) | `[PROPOSED]` | İlerideki depo genişlemesi (Faz 8) |
| 4 | Geri yükleme sonrası yerel kuyruk uzlaştırma protokolü | `[PROPOSED]` | Faz 0 Senkronizasyon ve Yedekleme Protokolü |
| 5 | Şubeye özel fiyat geçersiz kılma tablosu (`store_product_prices`) | `[PROPOSED]` | Çoklu şube aşaması (Faz 8) |

---

## 7. Sonuç ve Önerilen Sonraki Adım

> [!TIP]
> **NİHAİ TEKNİK DOĞRULAMA ONAYI:**  
> `DATA_MODEL.md` (v1.1) ve `DATA_MODEL_DECISIONS.md` (v1.1) içerisinde tanımlanan mantıksal veri modeli; `NEW-01` .. `NEW-04`, `FND-04` ve `FND-05` kararlarıyla sertleştirilmiş olup, Faz 0 iş kuralları ve mimari gereksinimleriyle **tamamen tutarlı, sağlam ve güvenilirdir**.  
> **Faz 0 henüz tamamlanmamıştır.** Bir sonraki görev olarak **Offline Senkronizasyon ve Outbox Kuyruğu Protokolü Tasarımı**na geçilmesi önerilmektedir.
