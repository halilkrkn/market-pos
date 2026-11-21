# ADR 013: Stok Girişinde Delta Senkronizasyonu (`STOCK_RECEIPT`) ve Mutlak Stok Ezilmesinin Kaldırılması

- **Durum:** CONFIRMED (Proje sahibi onayı: 21 Kasım 2026)
- **Tarih:** 2026-11-21
- **Karar Vericiler:** Proje Sahibi (Owner); uygulama: Claude Code

---

## 1. Bağlam

- Mevcut ürüne stok girişi (Faz 2 §4.3) Hub'a senkronize edilmeli ve çok cihazlı eşzamanlı çalışmada miktar kaybı olmamalıdır.
- Doğrulanan hata: Hub `PRODUCT_UPSERT` mevcut ürünün `stock` değerini istemcinin gönderdiği **mutlak** değerle eziyordu. B cihazında ürün adı değiştirmek, A cihazının senkronize ettiği satış düşümlerini sessizce geri alabiliyordu (lost update).
- Doğrulanan ikinci hata: İstemci Hub ürün snapshot'ını uygularken, Outbox'ta henüz bekleyen yerel satış/giriş düşümlerini geçici olarak geri alıyordu.

## 2. Değerlendirilen Seçenekler

1. **Yeni `STOCK_RECEIPT` işlem türü (delta):** Mevcut FIFO / `client_seq` / makbuz (`processed_operations`) / HWM altyapısı aynen kullanılır; yalnızca yeni bir işlem türü ve uç nokta eklenir. Additive şema değişikliği gerekir.
2. **Yalnızca yerel stok girişi:** Protokol değişmez ama Hub'a aktarılmaz.
3. **`PRODUCT_UPSERT` ile mutlak stok:** Protokol değişmez ama eşzamanlı cihazlarda miktar kaybı oluşur.

## 3. Karar

Seçenek 1 uygulanmıştır:

- İstemci şeması v3 → v4 ve Hub şeması v2 → v3: `stock_movements` tablolarına nullable `purchase_price` (kuruş / stok birimi) ve `note` sütunları eklendi (DROP/RECREATE yok, idempotent).
- Yeni Outbox işlemi `STOCK_RECEIPT` → `POST /api/v1/stock/receipts`. Yük: `receipt_id`, `product_id`, `quantity` (**delta**, milli-birim), `unit`, `unit_purchase_price`, `note`, `occurred_at`. Mutlak stok gönderilmez.
- Idempotency iki katmanlıdır: (a) mevcut `device_id:client_seq` makbuzu ve kanonik v2 hash; (b) `receipt_id` = stok hareketi PK. Aynı `receipt_id` yeni bir `client_seq` ile gelirse stok **uygulanmaz**, makbuz yazılır ve FIFO kuyruğu kilitlenmez (`DUPLICATE_RECEIPT_IGNORED`); içerik farklıysa `409 ERR_STOCK_RECEIPT_CONFLICT`.
- Hub `PRODUCT_UPSERT`: mevcut ürünün stoğu artık değiştirilmez; başlangıç stoğu yalnızca ürün ilk oluşturulurken uygulanır. Stok yalnızca hareketlerle değişir (satış, iptal, iade, giriş).
- İstemci snapshot'ı: SYNCED olmayan stok etkili işlemleri (SALE_CREATE / SALE_CANCEL / SALE_REFUND / STOCK_RECEIPT) bulunan ürünlerde yerel stok korunur; kuyruk boşalınca Hub değeri otoritedir.

FIFO sırası, `client_seq` üretimi, server cursor ve mevcut işlem türlerinin hash sözleşmeleri **değiştirilmemiştir**.

## 4. Gerekçeler

Delta semantiği eşzamanlı girişleri değişmeli (commutative) kılar; mevcut idempotency altyapısı yeniden kullanıldığı için yeni bir senkronizasyon mekanizması icat edilmemiştir.

## 5. Sonuçlar ve Ödünleşimler

- **Olumlu:** Çok cihazlı stok tutarlılığı; aynı giriş iki kez uygulanamaz; alış fiyatı ve açıklama izlenebilir.
- **Ödünleşim:** Eski (bu sürümden önceki) istemciler `STOCK_RECEIPT` üretmez; Hub/istemci birlikte güncellenmelidir. Kategori ve KDV oranı hâlâ Hub'a taşınmamaktadır (ayrı karar, bkz. nihai rapor).
- **Risk:** Ürün Hub'da yoksa (`404 ERR_PRODUCT_NOT_FOUND`) kayıt kalıcı hataya düşer ve FIFO durur; aynı cihazda ürün oluşturma işlemi önce sıraya girdiği için normal akışta oluşmaz.

## 6. İlgili Dokümanlar / Kod

- `packages/mms_client_storage/lib/src/database/client_storage_repository.dart` (`receiveStock`, `productIdsWithUnsyncedStockChanges`)
- `test_spikes/spike_01_backend/bin/server.dart` (`/api/v1/stock/receipts`, `PRODUCT_UPSERT`)
- Testler: `packages/mms_client_storage/test/stock_receipt_test.dart`, `test_spikes/spike_01_backend/test/stock_receipt_api_test.dart`
