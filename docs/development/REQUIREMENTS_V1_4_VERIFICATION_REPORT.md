# MARKET MMS — REQUIREMENTS.md (v1.4) Doğrulama Raporu

- **Tarih:** 2026-11-13
- **Görev:** `docs/REQUIREMENTS.md` v1.4 Güncellemesi ve Kapsam Doğrulaması
- **İncelenen ve Doğrulanan Dosya:** [`docs/REQUIREMENTS.md`](file:///c:/Users/halil/Github/market-pos/docs/REQUIREMENTS.md)
- **Referans Commit:** `e9e1df5574fff5433aa67987663ef3df37bd6592` (`feat(pos): implement cashier sales screen, cart engine, and storage reliability`)
- **Yürütme Sınırları ve Kısıtlamalar:**
  - `docs/requirements/BUSINESS_RULES_SPEC.md` dosyasına dokunulmamıştır.
  - 10 modül ve 75 temel iş kuralı firesiz korunmuştur.
  - İş kuralı kimlikleri ve anlamları değiştirilmemiştir.
  - Yeni bir iş kararı üretilmemiştir.
  - NFR gereksinimleri korunmuştur.
  - Kod dosyalarına dokunulmamıştır.
  - `git add`, `git commit` veya `git push` çalıştırılmamıştır.

---

## 1. On Maddelik Kapsam Doğrulama Matrisi

`docs/REQUIREMENTS.md` dosyasının disk üzerindeki gerçek içeriği okunmuş ve aşağıdaki 10 zorunlu değişiklik maddesi tek tek doğrulanmıştır:

| No | Zorunlu Değişiklik Maddesi | REQUIREMENTS.md İçerisindeki Gerçek Karşılığı | Doğrulama Durumu |
|:---:|---|---|:---:|
| **1** | Belge sürümü v1.4, tarih 13 Kasım 2026, aşama Faz 1 — MVP Uygulama ve Doğrulama | **L3-5:** `**Belge Sürümü:** v1.4 (13 Kasım 2026 ...)`<br>`**Tarih:** 13 Kasım 2026`<br>`**Aşama:** Faz 1 — MVP Uygulama ve Doğrulama` | ✅ **%100 DOĞRULANDI** |
| **2** | `BR-PROD-04`: Barkodsuz ürün modellemesi ile kısayol atamasını ayır, ekmek hızlı tuşunu onaylanmış sayma, F1 yalnızca Yardım panelidir | **L26 (`BR-PROD`):** `barkodsuz ürün modellemesi (BR-PROD-04 — modelleme: product_barcodes ilişkisinde aktif barkod kaydı bulunmayan ürün olarak tanımlanır; klavye kısayolu ve ekmek hızlı tuşu ataması onaylanmış bir özellik olmayıp kesinleşmemiş açık bir tasarım konusudur, F1 yalnızca Yardım paneline ayrılmıştır)` | ✅ **%100 DOĞRULANDI** |
| **3** | Faz 1.2 POS ekranı, sepet motoru ve atomik yerel satış/Outbox kaydını tamamlandı ve push edildi (`e9e1df5`) olarak belirt | **L28 (`BR-POS`):** `*(Not: Faz 1.2 kapsamında Kasa Satış Ekranı, sepet motoru ve atomik yerel satış/Outbox kaydı tamamlandı, kabul edildi ve push edildi [Commit e9e1df5]. ...)*` | ✅ **%100 DOĞRULANDI** |
| **4** | `BR-SYNC`: Yerel Outbox kaydının Faz 1.2'de tamamlandığını, canlı sync'in Faz 1.3.1 kapsamında olduğunu ayır | **L31 (`BR-SYNC`):** `*(Not: Yerel Outbox kaydı ve atomik transaction yazımı Faz 1.2'de tamamlanmıştır [Commit e9e1df5]; arka plan senkronizasyonu, HTTP aktarımı ve canlı kuyruk derinliği rozeti ise ayrı bir durum olarak doğrudan Faz 1.3.1 kapsamındadır)*` | ✅ **%100 DOĞRULANDI** |
| **5** | `BR-POS-08` tam satış iptalini Faz 1.3.3 ile ilişkilendir | **L28 (`BR-POS`):** `Tam fiş iptali BR-POS-08 [Faz 1.3.3]` | ✅ **%100 DOĞRULANDI** |
| **6** | `BR-POS-09` kısmi iadeyi Faz 1.3.4 ile ilişkilendir | **L28 (`BR-POS`):** `kısmi ürün iadesi BR-POS-09 [Faz 1.3.4]` | ✅ **%100 DOĞRULANDI** |
| **7** | `BR-POS-10` hasarlı/satılabilir iade ayrımını Faz 1.3.4 ile ilişkilendir | **L28 (`BR-POS`):** `hasarlı/satılabilir iade ayrımı BR-POS-10 [Faz 1.3.4] doğrudan Faz 1.3 kapsamındadır` | ✅ **%100 DOĞRULANDI** |
| **8** | Ürün ve kategori CRUD'u Faz 1.4 adayı olarak belirt | **L26 (`BR-PROD`):** `Ürün ve Kategori yönetimi arayüzü [CRUD] Faz 1.4 adayıdır` | ✅ **%100 DOĞRULANDI** |
| **9** | `BR-DSH-02` brüt kâr gereksinimini silme; MVP kapsamı dışında / Post-MVP olarak işaretle | **L32 (`BR-DSH`):** `maliyeti girilmiş ürünler üzerinden brüt kâr hesabı (BR-DSH-02 — gereksinim korunmaktadır; mevcut iş kararımız doğrultusunda MVP kapsamı dışında / Post-MVP olarak işaretlenmiştir)` | ✅ **%100 DOĞRULANDI** |
| **10** | `BR-PAY-05` gereksinimini koru; operatör arayüzü ve düzeltme audit mekanizmasının henüz tamamlanmadığını belirt | **L29 (`BR-PAY`):** `hatalı ödeme düzeltme audit kaydı (BR-PAY-05 — gereksinim korunmaktadır; operatör arayüzü ve düzeltme audit mekanizması henüz tamamlanmamıştır)` | ✅ **%100 DOĞRULANDI** |

---

## 2. 10 Modül ve 75 İş Kuralı Envanter Kontrolü

`docs/REQUIREMENTS.md` içerisindeki kural sayıları `docs/requirements/BUSINESS_RULES_SPEC.md` ana şartnamesi ile karşılaştırılmış ve tam uyum teyit edilmiştir:

| Modül Kodu | Modül Adı | Temel Kural Sayısı | Durum |
|:---:|---|:---:|:---:|
| **BR-PROD** | Ürün ve Kategori Yönetimi | 16 | ✅ Doğrulandı (16 Kural) |
| **BR-STK** | Stok ve Envanter Yönetimi | 10 | ✅ Doğrulandı (10 Kural) |
| **BR-POS** | Sepet ve Satış İşlemleri | 14 | ✅ Doğrulandı (14 Kural) |
| **BR-PAY** | Ödeme Yönetimi | 5 | ✅ Doğrulandı (5 Kural) |
| **BR-TNT** | Tenant ve Şube İzolasyonu | 5 | ✅ Doğrulandı (5 Kural) |
| **BR-SYNC** | Senkronizasyon & Outbox | 7 | ✅ Doğrulandı (7 Kural) |
| **BR-DSH** | Dashboard ve Finans | 4 | ✅ Doğrulandı (4 Kural) |
| **BR-BAK** | Yedekleme ve Kurtarma | 6 | ✅ Doğrulandı (6 Kural) |
| **BR-DEV** | Cihaz ve Donanım | 4 | ✅ Doğrulandı (4 Kural) |
| **BR-USR** | Kullanıcı ve Güvenlik | 4 | ✅ Doğrulandı (4 Kural) |
| **TOPLAM** | **10 Modül** | **75 Kural** | **%100 Eksiksiz ve Tutarlı** |

---

## 3. Git Diff ve Durum Raporu

### 3.1. `git diff --stat`

```text
 docs/PROJECT_STATUS.md | 35 ++++++++++++++++++++++-------------
 docs/REQUIREMENTS.md   | 17 ++++++++---------
 2 files changed, 30 insertions(+), 22 deletions(-)
```

### 3.2. `git diff docs/REQUIREMENTS.md`

```diff
diff --git a/docs/REQUIREMENTS.md b/docs/REQUIREMENTS.md
index df57ae1..2d11968 100644
--- a/docs/REQUIREMENTS.md
+++ b/docs/REQUIREMENTS.md
@@ -1,8 +1,8 @@
 # REQUIREMENTS.md — MARKET MMS İş ve Sistem Gereksinimleri İndeksi
 
-**Belge Sürümü:** v1.3 (12 Kasım 2026 — Karar, `PaymentMethod` & Legacy Outbox Recovery Uzlaştırması)  
-**Tarih:** 12 Kasım 2026  
-**Aşama:** Faz 0 — İş Gereksinimleri ve Kabul Kriterleri  
+**Belge Sürümü:** v1.4 (13 Kasım 2026 — Faz 1.2 POS Kabulü & Faz 1.3 Kapsam Güncellemesi)  
+**Tarih:** 13 Kasım 2026  
+**Aşama:** Faz 1 — MVP Uygulama ve Doğrulama  
 **Ana Şartname:** [`docs/requirements/BUSINESS_RULES_SPEC.md`](./requirements/BUSINESS_RULES_SPEC.md) (v1.6 — 12 Kasım 2026 uzlaştırmalı; `OD-01..OD-04`, `'CASH'`/`'CARD'` ve Legacy Outbox Recovery)  
 **Keşif ve Karar Konsolidasyonu:** [`docs/requirements/PHASE_0_BUSINESS_DISCOVERY.md`](./requirements/PHASE_0_BUSINESS_DISCOVERY.md) (v1.3)
 
@@ -23,13 +23,13 @@ Gereksinim belgeleri 3 katmanda yönetilmektedir:
 
 | Modül Kodu | Modül Adı | Temel Kural Sayısı | Çekirdek İş Kuralları ve Prensipler |
 | :---: | :--- | :---: | :--- |
-| **BR-PROD** | Ürün ve Kategori Yönetimi | 16 Kural | Çoklu aktif barkod (`BR-PROD-02`), barkodsuz ekmek hızlı tuşu (`BR-PROD-04`), pasifleştirme (`BR-PROD-03`), Open Food Facts önerisi (`BR-PROD-06`), pay/payda rasyonel birim dönüşümü (`BR-PROD-08`), snapshot maliyet kopyalama (`BR-PROD-13`), alt kuruş Half-Up yuvarlama ve `12.50 TL` gösterim standardı (`BR-PROD-07` / `OD-01`). *(Not: Bilinmeyen barkod `BR-PROD-05` / `OD-03`: offline ürün oluşturulamaz ve bilinmeyen barkod offline sepete eklenemez; ürün oluşturma Hub gerektirir)* |
+| **BR-PROD** | Ürün ve Kategori Yönetimi | 16 Kural | Çoklu aktif barkod (`BR-PROD-02`), barkodsuz ürün modellemesi (`BR-PROD-04` — modelleme: `product_barcodes` ilişkisinde aktif barkod kaydı bulunmayan ürün olarak tanımlanır; klavye kısayolu ve ekmek hızlı tuşu ataması onaylanmış bir özellik olmayıp kesinleşmemiş açık bir tasarım konusudur, `F1` yalnızca Yardım paneline ayrılmıştır), pasifleştirme (`BR-PROD-03`), Open Food Facts önerisi (`BR-PROD-06`), pay/payda rasyonel birim dönüşümü (`BR-PROD-08`), snapshot maliyet kopyalama (`BR-PROD-13`), alt kuruş Half-Up yuvarlama ve `12.50 TL` gösterim standardı (`BR-PROD-07` / `OD-01`). *(Not: Bilinmeyen barkod `BR-PROD-05` / `OD-03`: offline ürün oluşturulamaz ve bilinmeyen barkod offline sepete eklenemez; ürün oluşturma Hub gerektirir. Ürün ve Kategori yönetimi arayüzü [CRUD] Faz 1.4 adayıdır)* |
 | **BR-STK** | Stok ve Envanter Yönetimi | 10 Kural | Stok hareket türleri (`BR-STK-01`, `BR-STK-11`), eksi stok serbestliği (`BR-STK-02`), raftan satışın faturadan önce yapılabilmesi (`BR-STK-03`). *(Not: Fiziksel sayım kuralları `BR-STK-04..10` MVP dışıdır / Post-MVP `OUT_OF_SCOPE`)* |
-| **BR-POS** | Sepet ve Satış İşlemleri | 14 Kural | Kuruş bazlı tam sayı hesabı (`BR-POS-04`), atomik sepet satışı ve stok düşüşü (`BR-POS-07`), tam fiş iptali (`BR-POS-08`), kısmi iade tavan sınırı (`BR-POS-09`), hasarlı iadenin fireye ayrılması (`BR-POS-10`), sepet satırı gerekçeli fiyat müdahalesi (`BR-POS-11`). *(Not: Parked Carts `BR-POS-05` / `OD-02` 11 Kasım 2026 Proje Sahibi kararıyla MVP kapsamı dışındadır — `OUT_OF_SCOPE`; sanal numpad `OD-04` opsiyonel ve varsayılan kapalıdır)* |
-| **BR-PAY** | Ödeme Yönetimi | 5 Kural | Satış başına tek ödeme: yalnızca kanonik `'CASH'` (Nakit) veya `'CARD'` (Kart) sözleşmesi (`BR-PAY-01`; eski `'CREDIT_CARD'` ve `'NAKIT'` dizgeleri *obsolete*, eksik/geçersiz değerde sessiz `'CASH'` fallback yasaktır), nakit para üstü zorunlu doğrulaması (`BR-PAY-02`), kart ödemesinde tutarın banka POS terminaline manuel girilmesi (`BR-PAY-04`), hatalı ödeme düzeltme audit kaydı (`BR-PAY-05`). |
+| **BR-POS** | Sepet ve Satış İşlemleri | 14 Kural | Kuruş bazlı tam sayı hesabı (`BR-POS-04`), atomik sepet satışı ve stok düşüşü (`BR-POS-07`), tam fiş iptali (`BR-POS-08`), kısmi iade tavan sınırı (`BR-POS-09`), hasarlı iadenin fireye ayrılması (`BR-POS-10`), sepet satırı gerekçeli fiyat müdahalesi (`BR-POS-11`). *(Not: Faz 1.2 kapsamında Kasa Satış Ekranı, sepet motoru ve atomik yerel satış/Outbox kaydı tamamlandı, kabul edildi ve push edildi [Commit `e9e1df5`]. Parked Carts `BR-POS-05` / `OD-02` MVP kapsamı dışındadır — `OUT_OF_SCOPE`; sanal numpad `OD-04` opsiyonel ve varsayılan kapalıdır. Tam fiş iptali `BR-POS-08` [Faz 1.3.3], kısmi ürün iadesi `BR-POS-09` [Faz 1.3.4] ve hasarlı/satılabilir iade ayrımı `BR-POS-10` [Faz 1.3.4] doğrudan Faz 1.3 kapsamındadır)* |
+| **BR-PAY** | Ödeme Yönetimi | 5 Kural | Satış başına tek ödeme: yalnızca kanonik `'CASH'` (Nakit) veya `'CARD'` (Kart) sözleşmesi (`BR-PAY-01`; eski `'CREDIT_CARD'` ve `'NAKIT'` dizgeleri *obsolete*, eksik/geçersiz değerde sessiz `'CASH'` fallback yasaktır), nakit para üstü zorunlu doğrulaması (`BR-PAY-02`), kart ödemesinde tutarın banka POS terminaline manuel girilmesi (`BR-PAY-04`), hatalı ödeme düzeltme audit kaydı (`BR-PAY-05` — gereksinim korunmaktadır; operatör arayüzü ve düzeltme audit mekanizması henüz tamamlanmamıştır). |
 | **BR-TNT** | Tenant ve Şube İzolasyonu | 5 Kural | Her kayıtta `tenant_id` zorunluluğu, bileşik foreign key `(tenant_id, store_id)` (`BR-TNT-02`), pilotta tek market tek mağaza standardı (`BR-TNT-03`). |
-| **BR-SYNC** | Senkronizasyon & Outbox | 7 Kural | Kalıcı `sync_operations` / `outbox_operations` kuyruğu (`BR-SYNC-01`), deterministik artan `client_sequence_number` + katı FIFO (`BR-SYNC-03`), `idempotency_key` ile mükerrerlik koruması, ürün oluşturma için Hub zorunluluğu (`BR-SYNC-04` / `OD-03`), gerçekleşmiş satışların çakışmada asla silinmemesi (`BR-SYNC-06`) ve Legacy `'CREDIT_CARD'` Outbox kayıtlarının `updateAndRetryFailedOperation` ile atomik transaction/rollback altında `'CARD'`'a onarılıp FIFO'nun sürdürülmesi (`b069d5b`). |
-| **BR-DSH** | Dashboard ve Finans | 4 Kural | Takvim günü bazlı ciro (`BR-DSH-01`), maliyeti girilmiş ürünler üzerinden brüt kâr hesabı (`BR-DSH-02`), genel giderler olmadan net kâr iddiasında bulunmama ilkesi (`BR-DSH-03`). |
+| **BR-SYNC** | Senkronizasyon & Outbox | 7 Kural | Kalıcı `sync_operations` / `outbox_operations` kuyruğu (`BR-SYNC-01`), deterministik artan `client_sequence_number` + katı FIFO (`BR-SYNC-03`), `idempotency_key` ile mükerrerlik koruması, ürün oluşturma için Hub zorunluluğu (`BR-SYNC-04` / `OD-03`), gerçekleşmiş satışların çakışmada asla silinmemesi (`BR-SYNC-06`) ve Legacy `'CREDIT_CARD'` Outbox kayıtlarının `updateAndRetryFailedOperation` ile atomik transaction/rollback altında `'CARD'`'a onarılıp FIFO'nun sürdürülmesi (`b069d5b`). *(Not: Yerel Outbox kaydı ve atomik transaction yazımı Faz 1.2'de tamamlanmıştır [Commit `e9e1df5`]; arka plan senkronizasyonu, HTTP aktarımı ve canlı kuyruk derinliği rozeti ise ayrı bir durum olarak doğrudan Faz 1.3.1 kapsamındadır)* |
+| **BR-DSH** | Dashboard ve Finans | 4 Kural | Takvim günü bazlı ciro (`BR-DSH-01`), maliyeti girilmiş ürünler üzerinden brüt kâr hesabı (`BR-DSH-02` — gereksinim korunmaktadır; mevcut iş kararımız doğrultusunda MVP kapsamı dışında / Post-MVP olarak işaretlenmiştir), genel giderler olmadan net kâr iddiasında bulunmama ilkesi (`BR-DSH-03`). |
 | **BR-BAK** | Yedekleme ve Kurtarma | 6 Kural | Bağımsız Google Drive yedeklemesi (`BR-BAK-01`), canlı SQLite `VACUUM INTO` snapshot'ı (`BR-BAK-03`), 30 günlük döngüsel saklama (`BR-BAK-04`), geri yükleme öncesi koruyucu güvenlik yedeği (`BR-BAK-05`), S5A-4 standardında AES-256-CBC + HMAC-SHA256 şifreleme (`BR-BAK-06`). |
 | **BR-DEV** | Cihaz ve Donanım | 4 Kural | PC'de USB HID klavye taklitli barkod okuyucu (`BR-DEV-01`), mobilde kamera barkod tarama (`BR-DEV-02`), Windows ekranından QR kod ile cihaz eşleştirme (`BR-DEV-03`). |
 | **BR-USR** | Kullanıcı ve Güvenlik | 4 Kural | Pilot aşamasında tek işletme sahibi hesabı (`BR-USR-01`), hassas işlemler için açık onay ve şifre gereksinimi (`BR-USR-03`). |
```

### 3.3. `git status --short --branch`

```text
## main...origin/main
 M docs/PROJECT_STATUS.md
 M docs/REQUIREMENTS.md
?? docs/development/FINAL_DOCUMENTATION_ACCEPTANCE_REPORT.md
?? docs/development/PHASE_1_2_DOCUMENTATION_FINAL_VERIFICATION_REPORT.md
?? docs/development/PHASE_1_2_DOCUMENTATION_RECONCILIATION_REPORT.md
?? docs/development/PHASE_1_2_GIT_STAGING_REPORT.md
?? docs/development/PHASE_1_2_PAYMENT_METHOD_ARCHITECTURE_REVIEW.md
?? docs/development/PHASE_1_2_STAGED_DIFF_REVIEW_REPORT.md
?? docs/development/PHASE_1_3_ROADMAP_REVIEW.md
?? docs/development/REQUIREMENTS_V1_4_VERIFICATION_REPORT.md
?? docs/development/UI_UX_DOCUMENTATION_GIT_EXECUTION_REPORT.md
```

- Staging alanı tamamen boştur (`git diff --cached` 0 bayt).
- Yalnızca kanonik dokümanlar üzerinde çalışılmıştır.
- Hiçbir kod dosyasına dokunulmamış, hiçbir Git yazma komutu (`git add/commit/push`) çalıştırılmamıştır.

---

## 4. Sonuç

`docs/REQUIREMENTS.md` dosyasının v1.4 sürümüne yükseltilmesi, 10 zorunlu kapsam maddesinin eksiksiz işlenmesi ve 75 temel iş kuralının tam tutarlılığı doğrulanmıştır.

Dokümanlar Proje Sahibinin onayını beklemektedir.

