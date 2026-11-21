# ADR 019: Kategori ve KDV Oranı Senkronizasyonu (SYNC-CAT) — Pilot %20 KDV Kısıtı ve Gelecek Tasarım

- **Durum:** **DEFERRED_POST_PILOT** (Owner kararıyla pilot sonrasına ertelendi; şema v3→v4, `CATEGORY_UPSERT`, `PRODUCT_UPSERT` değişiklikleri ve kısmi KDV senkronizasyonu pilot kapsamında **UYGULANMADI**)
- **Tarih:** 2026-11-21
- **Karar Vericiler:** Owner (Pilot erteleme kararı), Öneren: Claude Code / Dokümantasyon: Antigravity
- **İlgili:** ADR-007 (FIFO `client_seq`), ADR-012 (Hub tek yazıcı), ADR-013 (delta senkron), ADR-014 (tenant/store)

---

## 1. Mevcut Durum (kodla doğrulandı, 21.11.2026)

| Konu | İstemci (`mms_client_storage`) | Hub (`spike_01_backend`) |
|---|---|---|
| Kategori tablosu | `local_categories` (`id`, `name`, `parent_id`, `is_active`, zaman damgaları) | **Yok** |
| Ürün → kategori | `local_products.category_id` (nullable FK) | `products` tablosunda **sütun yok** |
| KDV oranı | `local_products.vat_rate` (int, varsayılan 20) | `products` tablosunda **sütun yok** |
| `PRODUCT_UPSERT` yükü | `category_id` ve `vat_rate` **gönderiliyor** | Hub bu alanları **saklamıyor** (şemada yok) |
| Ürün snapshot indirme | `vat_rate` gelmezse yerel değer korunur; `category_id` hiç yazılmaz (yerel korunur) | Alanlar gönderilmez |
| `CATEGORY_UPSERT` | Outbox tür listesinde yorum olarak var; **üretilmiyor** | Rota yok |

**Pilot İçin Onaylanan 7 Geçici Operasyonel Kısıt (%20 KDV Modeli):**
1. **Tek Varsayılan KDV (%20):** Pilot süresince tüm ürünler Hub ve yeni kurulan/eşleştirilen cihazlar arasında varsayılan **%20 KDV** ile işletilir; çoklu KDV (%0, %1, %10) senkronize edilmez.
2. **Hub Şema Sınırı:** Windows Master Hub (`products` tablosu) üzerinde `vat_rate`, `category_id` sütunları ve `categories` tablosu yoktur; şema v3 → v4 geçişi pilotta yapılmaz.
3. **Yeni / Yeniden Eşleştirilen Cihazlar:** Sıfırdan kurulan veya yeniden eşleştirilen her istemci, Hub'dan ürün indirdiğinde tüm ürünleri `vat_rate = 20` ve `category_id = null` olarak alır.
4. **Yerel Değişiklik İzolasyonu:** Bir cihazda elle girilen `%1` veya `%10` KDV oranı ya da kategori ataması diğer cihazlara ve Hub'a aktarılmaz; yalnızca o cihazın yerel SQLite veritabanında kalır.
5. **Mali Beyan Sınırı:** Satış toplamları (kuruş tamsayı) tüm cihazlarda doğrudur; ancak KDV kırılımı ve vergi tutarı dökümleri cihazlar arasında tutarsız kalabileceği için pilot boyunca resmî mali beyan doğrudan çoklu cihaz KDV dökümüne dayandırılmamalıdır.
6. **Geri Yükleme Sonrası Durum:** Mevcut cihazda yapılan restore sonrasında yerel KDV bilgisi korunur; ancak cihaz arızasında yeni telefona geçildiğinde eski yerel KDV/kategori eşlemeleri Hub'dan geri getirilemez.
7. **Kategori Operasyonu ve Migrasyon Öncesi Yedek:** Pilotta ortak kategori paylaşımı yoktur; pilot sonrası ADR-019 geçişi başlatılmadan önce mutlaka doğrulanmış şifreli `.mmsbak` Hub yedeği alınmalıdır.

**Tespit Edilen 8 Teknik Risk:**
1. Farklı cihazlarda aynı ürünün farklı KDV oranıyla (%1/%10 vs %20) görünmesi.
2. Çoklu KDV oranlı marketlerde KDV dağılımı ve vergi raporu sapması (mali raporlama riski).
3. İstemcinin `PRODUCT_UPSERT` gövdesinde gönderdiği `vat_rate`/`category_id` verilerinin Hub tarafından saklanmadan sessizce atılması.
4. Yeni veya fabrika sıfırlamasına uğrayan cihazda tüm ürünlerin KDV oranının %20'ye dönmesi.
5. Windows masaüstünde tanımlanan kategorilerin Android ekranlarında hiç görünmemesi.
6. Ertelenen süre boyunca cihazlarda farklı yerel `category_id` kimlikleri birikmesi sonucu ileriki ADR-019 veri birleştirme karmaşıklığı.
7. Operatörlerin tek cihazda değiştirdiği KDV ayarının mağaza geneline yayıldığını varsayma riski.
8. Owner onayı olmadan şema/sözleşme üzerinde kısmi KDV değişikliği yapılmasının geriye uyumsuz kuyruk/snapshot hatasına yol açma riski (bu nedenle tamamı ertelenmiştir).

**Sonuçlar (mevcut kod durumu):**
1. Kategoriler cihaza özeldir; Windows'ta oluşturulan kategori Android'de görünmez.
2. **KDV:** Yeni eşleştirilen veya sıfırdan kurulan cihaz tüm ürünleri **%20** varsayılanıyla alır. Owner'ın başka cihazda %1 / %10 olarak ayarladığı ürünler bu cihazda %20 görünür. Satış toplamı (kuruş) etkilenmez, ancak KDV dökümü/raporu cihazlar arasında tutarsız olur → **mali raporlama riski**.
3. Restore sonrası ürünler Hub'dan yeniden indiğinde KDV yerel değerde kalır (doğru), ama yeni cihazda kaynak yoktur.

## 2. Kalıcı Gelecek Tasarım Gereksinimleri (Post-Pilot 9 Madde) ve Teknik Sorular

Pilot sonrası SYNC-CAT uygulanırken aşağıdaki **9 kalıcı tasarım gereksinimi** birlikte karşılanacaktır:
1. **Hub Şema Migrasyonu (v3 → v4):** `categories(id, tenant_id, store_id, name, parent_id, is_active, updated_at, version)` tablosu ile `products.category_id` ve `products.vat_rate` sütunlarının veri kaybı olmadan eklenmesi.
2. **Tek Otorite ve Rol Sınırı:** KDV ve kategori otoritesinin Hub olması; kategori oluşturma/düzenleme yetkisinin pilotta yalnızca Owner rolündeki Windows kasasına verilmesi.
3. **`PRODUCT_UPSERT` ve Ürün Snapshot Entegrasyonu:** Hub'ın `PRODUCT_UPSERT` içindeki `category_id`/`vat_rate` alanlarını saklaması ve `GET /api/v1/products` ile istemcilere dağıtması.
4. **`CATEGORY_UPSERT` ve Kategori Snapshot Yolu:** Mevcut FIFO `client_seq` Outbox protokolü üzerinden `CATEGORY_UPSERT` işleminin ve ürün snapshot'ından **önce** indirilecek `GET /api/v1/categories` cursor ucunun eklenmesi.
5. **FK ve Eski İstemci Güvenliği:** İstemcide henüz bulunmayan `category_id` değerlerinin FK çökmesine yol açmaması için uygulama düzeyinde doğrulama (`null` fallback veya kategori-önce indirme).
6. **Geriye Uyumlu `NULL` KDV Başlatma:** Migrasyonda mevcut Hub ürünlerinin `vat_rate` değerinin ilk güncellemeye kadar `NULL` ("bilinmiyor") kalması ve istemcilerin `NULL` geldiğinde yerel KDV değerini ezmemesi.
7. **Veri Bütünlüğü Kısıtları:** `vat_rate` için `CHECK (0..100)` / izinli oran listesi ve kategorilerde fiziksel silme yerine `is_active = false` (soft delete).
8. **Çakışma Yönetimi ve Değişmezler:** Kategorilerde `version`/`base_version` tabanlı kayıt bazlı çözüm, tüm yazmaların tekil `WriteQueue` üzerinden geçmesi, ADR-014 tenant/store izolasyonu ve idempotency/echo-prevention korunumu.
9. **Güvenli Geçiş ve Kabul Testleri:** Migrasyon öncesi şifreli `.mmsbak` Hub yedeği, TDD birim/entegrasyon testleri ve fiziksel `PAT-05` çoklu cihaz KDV tutarlılığı doğrulaması.

## 2b. Teknik Sorular ve Önerilen Cevaplar

| Soru | Öneri |
|---|---|
| Kategori değişiklikleri hangi cihazlarda oluşturuluyor? | Pilotta yalnızca **Owner rolündeki Windows kasası** (yönetim ekranı). Android cihazlar kategori okur, oluşturmaz (UI kısıtı + Hub rol kontrolü). |
| KDV oranında otorite kim? | **Hub.** Ürünün KDV'si `products.vat_rate` (Hub) değeridir; istemci değeri yalnızca Hub'a ulaşmamış yerel değişikliktir. |
| Ürün–kategori ilişkisi nasıl korunur? | Hub'da `categories(id PK, tenant_id, store_id, name, parent_id, is_active, updated_at, version)` ve `products.category_id` (nullable, FK yerine uygulama düzeyinde doğrulama — silinen kategori ürünü bozmasın). Kategori silinmez, `is_active=false` yapılır (soft delete). |
| Offline değişiklik kuyruğu? | Mevcut Outbox + FIFO `client_seq` aynen kullanılır: yeni tür `CATEGORY_UPSERT`; ürünün KDV/kategori değişikliği mevcut `PRODUCT_UPSERT` yükünde zaten var. Yeni sıra sayacı veya yeni kuyruk **yok**. |
| Çakışma çözümü? | Kategori: alan bazlı değil kayıt bazlı **last-writer-wins**, karşılaştırma Hub'ın `version` sayacıyla (istemci `base_version` gönderir; eskiyse Hub `409 ERR_STALE_CATEGORY` yerine güncel kaydı döner ve istemci yerelini Hub'a göre günceller). Ürün KDV'si: Hub'a ulaşan son `PRODUCT_UPSERT` kazanır (mevcut ürün semantiği). |
| Eski istemciler? | Eski istemci `CATEGORY_UPSERT` üretmez; `PRODUCT_UPSERT`'teki `category_id`/`vat_rate` zaten gönderiliyor → Hub bunları **saklamaya başlar** (geriye uyumlu). Snapshot'a eklenen `vat_rate`/`category_id` alanlarını eski istemci yok sayar (`vat_rate` zaten okunuyor). Bilinmeyen `category_id` için istemci FK ihlali yaşamamalı → istemci, yerelde olmayan kategoriyi `null` olarak yazmalı veya önce kategori snapshot'ı indirmeli. |
| Hub'da veri bütünlüğü? | Şema migrasyonu v3 → v4 (yalnızca sütun/tablo ekleme; mevcut veri dokunulmaz). `vat_rate` için CHECK (0–100) ve izinli oran listesi (ör. 0, 1, 10, 20) yapılandırmadan. Tüm yazmalar `WriteQueue` üzerinden; tenant/store başlık zorunluluğu (ADR-014) aynen geçerli. |

## 3. Uygulama Adımları (Owner onayı sonrası)
1. Hub migrasyonu v4: `categories` tablosu, `products.category_id`, `products.vat_rate` (mevcut ürünler için başlangıç değeri: ilk `PRODUCT_UPSERT` gelene kadar `NULL` = "bilinmiyor"; istemci `NULL` gelirse yerel değeri korur).
2. Hub `PRODUCT_UPSERT` işleyicisi `category_id`/`vat_rate` saklar; ürün snapshot'ı bunları döner.
3. Hub `CATEGORY_UPSERT` işleyicisi + `GET /api/v1/categories` (cursor'lı snapshot).
4. İstemci: kategori snapshot indirme (ürün snapshot'ından önce), `CATEGORY_UPSERT` üretimi (yalnızca Owner rolü).
5. Testler (TDD): eski istemci yükünün saklanması, yeni cihazda KDV'nin Hub'dan gelmesi, `NULL` KDV'de yerel değerin korunması, bilinmeyen kategori FK güvenliği, çakışma, tenant/store izolasyonu, restore sonrası tutarlılık.

## 4. Bu Oturumda Yapılan
Owner kararıyla `DEFERRED_POST_PILOT` olarak sabitlendi; 7 geçici %20 KDV operasyonel kısıtı, 8 teknik risk ve pilot sonrası 9 kalıcı tasarım gereksinimi belgelendi. Kod, şema (`v3`), `PRODUCT_UPSERT`, `CATEGORY_UPSERT` ve sync sözleşmesi **değiştirilmedi**.
