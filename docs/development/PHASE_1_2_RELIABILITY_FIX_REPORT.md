# MARKET MMS — Faz 1.2 POS Güvenilirlik İncelemesi ve Düzeltme Raporu

- **Tarih:** 2026-11-12
- **Kapsam:** Faz 1.2 POS implementasyonu kabul öncesi güvenilirlik, veri bütünlüğü, fiyat tutarlılığı, eşzamanlılık, UI ergonomi ve barkod/ürün arama denetimi
- **Bağlayıcı Kurallar:** `AGENTS.md`, `GEMINI.md`, `docs/architecture/DATA_MODEL_DECISIONS.md`, `docs/requirements/BUSINESS_RULES_SPEC.md`
- **Durum:** İnceleme için hazır (Faz kabulü proje sahibine aittir; `git add`, `commit` veya `push` yapılmamıştır).

---

## 1. Bulunan Sorunlar (Kod Denetimi Bulguları)

1. **Sessiz Fiyat / Fiyat Sürümü Kayması (Alan 1):**
   - `CartItemInput`, sepete eklendiği andaki beklenen birim fiyatı ve `priceVersionId` değerini taşımıyordu.
   - `ClientStorageRepository.createOfflineSale()` ve `LocalPosRepository.completeOfflineSale()`, ödeme anında DB'deki güncel `product.price` değerini okuyup sepet tutarından farklı bir tutarla satışı sessizce kaydedebiliyordu.
2. **Storage Eksik Sınır ve Underflow Kontrolleri (Alan 2):**
   - `createOfflineSale()`, DB `product.price` için negatif veya üst sınır (`_maxAmountCents`) doğrulaması yapmıyordu.
   - Aynı satışta yinelenen `productId` ve geçersiz `quantity` kontrolleri transaction açılmadan önce uygulanmıyordu.
   - Stok azaltma (`currentProd.stock - item.stockDelta`) öncesinde 64-bit işaretli tamsayı alt sınırı (`_minSafeInt = -9223372036854775808`) taşması (integer underflow) denetlenmiyordu.
3. **Satış / Kalem / Hareket ID Çakışma Riski (Alan 3):**
   - `saleId` (`csale_<micro>_<nextSeq>`) ve `operationId` (`op_<micro>_<nextSeq>`) farklı cihazlarda aynı mikrosaniye + aynı `client_seq` değerinde çakışabiliyordu.
   - `itemId` (`citem_<micro>_<productId>`) ve `movementId` (`csm_<micro>_<productId>`) yalnızca zaman damgası ve `productId` kullandığından, aynı mikrosaniye içinde aynı ürünü içeren iki farklı satışta benzersizlik bozulabiliyordu.
4. **`CartNotifier` Eşzamanlılık ve Post-Commit Callback İzolasyonu (Alan 4):**
   - `completeSale()` metodu, senkron bir kilit olmadan çağrıldığında asenkron pencere boyunca mükerrer gönderime açıktı.
   - DB commit işlemi (`repository.completeOfflineSale`) ile satış sonrası yenileme callback'i (`onSaleCommitted`) aynı `try/catch` bloğundaydı; callback hata fırlattığında başarıyla commit edilmiş satış kullanıcıya başarısız (`null` + hata mesajı) gibi dönebiliyordu.
5. **`PaymentDialog` Yöntem Değişimi, Hata Kurtarma ve Kısayol Odağı (Alan 5):**
   - Kart (`CARD`) seçiliyken manuel harici POS teyidi işaretlenip `F10` / dokunma ile Nakit'e geçildiğinde `_externalPosConfirmed` sıfırlanmıyordu.
   - `_submit()` içinde `widget.onConfirmSale(...)` beklenmeyen bir exception fırlattığında `_isSubmitting` kalıcı olarak `true` kalabiliyordu.
   - `PaymentDialog`, `barrierDismissible: false` ve `PopScope(canPop: !_isSubmitting)` koruması taşımıyordu; ayrıca `DialogRoute` odak kapsamı nedeniyle `TextField` unfocus veya `CheckboxListTile` etkileşimi sonrası `Esc`/`F9`/`F10` kısayolları modal içindeki `CallbackShortcuts`'a ulaşamayabiliyordu.
6. **Barkod/Ürün Arama Performansı ve `640x720` Dar Ekran Overflow (Alan 6):**
   - `LocalPosRepository.searchActiveProducts()`, her aramada tüm aktif `local_products` ve tüm `local_product_barcodes` tablolarını belleğe çekiyor, `limit <= 0` değerini reddetmiyor ve SQL `LIKE` wildcard karakterlerini (`%`, `_`, `\`) kaçırmıyordu.
   - `640x720` dar pencerede POS üst araç çubuğu (`_buildBarcodeToolbar`), sepet tablo başlığı/satırları (`CartItemRow`), dar yığılı aksiyon paneli (`SingleChildScrollView -> Column -> Expanded`), üst başlık (`CashierHeaderBar`, `StatusBadge`) ve alt kısayol çubuğu (`MainShellScreen._buildShortcutFooter`) yatay/kısıt taşması (`RenderFlex overflow`) üretiyordu.

---

## 2. Yapılan Değişiklikler

- **Alan 1 — Fiyat Tutarlılığı (Kuruş + `priceVersionId`):**
  - `CartItemInput` ve fabrika kurucularına (`.units`, `.fractional`, `.fromDecimalString`) opsiyonel `expectedUnitPrice` ve `expectedPriceVersionId` eklendi (`toJson()` sözleşmesi değiştirilmedi).
  - Yeni `PriceChangedException` tanımlandı ve `mms_client_storage.dart` üzerinden dışa aktarıldı.
  - `ClientStorageRepository.createOfflineSale()`, DB transaction içinde `product.price != expectedUnitPrice` veya `product.priceVersionId != expectedPriceVersionId` tespit ettiğinde satışı durdurup `PriceChangedException` fırlatıyor.
  - `LocalPosRepository.completeOfflineSale()`, sepetteki `unitPriceCents` ve `priceVersionId` değerlerini gönderiyor ve `PriceChangedException` yakalandığında anlaşılır Türkçe `PosDomainException` üretiyor. Offline son bilinen fiyatla satış (`INV-10`) ve Half-Up yuvarlama korundu.
- **Alan 2 — Storage Savunmacı Doğrulamalar ve Rollback:**
  - `createOfflineSale()` transaction öncesinde boş `deviceId`, boş sepet, yinelenen `productId`, `quantity <= 0 || quantity > CartItemInput.maxQuantity` ve negatif `expectedUnitPrice` girdilerini reddeder.
  - Transaction içinde `unitPrice < 0 || unitPrice > _maxAmountCents`, satır/sepet toplamı taşma ve `_maxAmountCents` sınırları ile `_minSafeInt` stok azaltma underflow koruması (`stockDelta > 0 && stock < _minSafeInt + stockDelta`) uygulanır; hata durumunda SQLite transaction tamamen geri alınır.
- **Alan 3 — Çakışmasız Satış ID Üretimi:**
  - `ClientStorageRepository` içinde monotonik sayaç + `Random.secure()` birleşimli `_nextUniqueToken()` eklendi.
  - `saleId` (`csale_<micro>_<nextSeq>_<token>`) ve varsayılan `operationId` (`op_<micro>_<nextSeq>_<token>`) değerleri cihazlar veya aynı mikrosaniyedeki ardışık işlemler arasında benzersiz kılındı.
  - `itemId` (`citem_<saleId>_<productId>`) ve `movementId` (`csm_<saleId>_<productId>`) değerleri benzersiz `saleId` ile ilişkilendirildi. Şema değişikliği yapılmadı.
- **Alan 4 — `CartNotifier` Güvenliği:**
  - `completeSale()` metoduna tüm `await` çağrılarından önce denetlenen `_isCompletingSale` kilidi (`try/finally`) eklendi.
  - `repository.completeOfflineSale(...)` başarısı sonrası sepet hemen temizlenir ve `lastCompletedSale` güncellenir; `onSaleCommitted()` kendi izole `try/catch` bloğunda çalıştırılarak callback hatasının gerçekleşmiş satışı başarısız göstermesi engellendi.
- **Alan 5 — `PaymentDialog` Güvenliği ve Klavye Odağı:**
  - `_selectPaymentMethod(PaymentMethod)` yardımcı metoduyla ödeme yöntemi değişiminde `_externalPosConfirmed = false` ve `_submitError = null` sıfırlaması zorunlu kılındı.
  - `_submit()`, `try/catch` içine alınarak callback exception durumunda `_isSubmitting = false` geri yüklenir ve Türkçe hata mesajı gösterilir.
  - `PopScope(canPop: !_isSubmitting)`, `barrierDismissible: false` ve `CallbackShortcuts` altında `FocusScope(autofocus: true)` eklendi.
- **Alan 6 — Barkod/Ürün Arama Optimizasyonu ve Responsive UI:**
  - `LocalPosRepository.searchActiveProducts()`, `limit <= 0` için `ArgumentError` fırlatır, üst sınırı `maxSearchLimit = 200` olarak uygular.
  - Boş sorguda doğrudan `LIMIT`, saf ASCII sorguda `\`, `%`, `_` kaçışlı parametreli SQLite `LIKE` + `EXISTS` + `LIMIT` pushdown, Türkçe/Unicode büyük-küçük harf katlaması gereken sorgularda 200'lük sayfalı (`offset/limit`) tarama ve yalnızca eşleşen ürünlerin barkodlarını çeken `_loadBarcodeContext` uygulanır.
  - `PosScreen` (`_buildBarcodeToolbar`, `_buildCartPanel`, `_buildActionPanel` `embedScrollable`), `CartItemRow`, `CashierHeaderBar`, `StatusBadge` ve `MainShellScreen._buildShortcutFooter` dar pencerede (`640x720`) sıfır taşma ve `>= 48x48 dp` dokunmatik hedef standardıyla yeniden düzenlendi.

---

## 3. Değiştirilen ve Eklenen Dosyalar

### Eklenen Dosyalar
- `packages/mms_client_storage/lib/src/models/price_changed_exception.dart`
- `packages/mms_client_storage/test/phase_1_2_reliability_test.dart`

### Güncellenen Uygulama Dosyaları
- `packages/mms_client_storage/lib/mms_client_storage.dart`
- `packages/mms_client_storage/lib/src/models/cart_item_input.dart`
- `packages/mms_client_storage/lib/src/database/client_storage_repository.dart`
- `lib/features/pos/data/local_pos_repository.dart`
- `lib/features/pos/application/cart_notifier.dart`
- `lib/features/pos/presentation/widgets/payment_dialog.dart`
- `lib/features/pos/presentation/screens/pos_screen.dart`
- `lib/features/pos/presentation/widgets/cart_item_row.dart`
- `lib/features/diagnostics/presentation/widgets/status_badge.dart`
- `lib/features/shell/presentation/widgets/cashier_header_bar.dart`
- `lib/features/shell/presentation/screens/main_shell_screen.dart`

### Güncellenen Test Dosyaları
- `test/features/pos/data/local_pos_repository_test.dart`
- `test/features/pos/application/pos_notifiers_test.dart`
- `test/features/pos/presentation/pos_screen_test.dart`

---

## 4. Eklenen Testler

Toplam **14 yeni güvenilirlik testi** (6 storage + 8 Flutter unit/integration/widget) TDD Red-Green döngüsüyle eklendi:

1. `packages/mms_client_storage/test/phase_1_2_reliability_test.dart` (6 test):
   - Senaryo 1: Sepet fiyatı veya `priceVersionId` DB'de değişirse `PriceChangedException` fırlatılır ve kayıt oluşmaz.
   - Senaryo 4 & 5: Sıfır/negatif/limit üstü miktar ve DB'de negatif `unitPrice` reddedilir.
   - Senaryo 6: `price * quantity` integer overflow ve stok azaltma 64-bit integer underflow güvenli reddedilir.
   - Senaryo 7: Aynı ürünün aynı zaman damgalı ardışık satışlarında ve farklı cihazlarda (`client_seq = 1`) ID çakışması oluşmaz.
   - Senaryo 8: Yinelenen `productId` transaction açılmadan reddedilir (`client_sync_states` ve `outbox_operations` bozulmaz).
   - Senaryo 12: Çok kalemli transaction ortasında 2. kalem hata verdiğinde 1. kalemin stok düşüşü tamamen rollback edilir.
2. `test/features/pos/data/local_pos_repository_test.dart` (+2 yeni test):
   - Sepet sonrası fiyat/sürüm değişiminde `LocalPosRepository.completeOfflineSale()` `PosDomainException` fırlatır ve rollback doğrulanır.
   - `searchActiveProducts` `limit` doğrulaması (`limit <= 0 -> ArgumentError`) ve `%` LIKE wildcard kaçış kontrolü.
3. `test/features/pos/application/pos_notifiers_test.dart` (+2 yeni test):
   - Senaryo 2: Eşzamanlı iki `completeSale()` çağrısında ikinci satış engellenir (`saleCallCount == 1`).
   - Senaryo 3: DB kaydı başarılıyken `onSaleCommitted` exception fırlattığında satış başarılı kalır, sepet temizlenir ve `errorMessage` temiz kalır.
4. `test/features/pos/presentation/pos_screen_test.dart` (+4 yeni widget/FFI testi):
   - Senaryo 9 (Test 6): Kart teyidi sonrası `F10 -> F9` geçişinde `card_manual_confirm_checkbox` sıfırlanır.
   - Senaryo 10 (Test 7): `PaymentDialog` callback exception fırlattığında kilitlenmez, hata gösterir ve İptal/Onay butonları yeniden etkinleşir.
   - Senaryo 11 (Test 8): `640x720` dar pencerede tam POS kabuğu, araç çubuğu ve sepet satırı sıfır overflow ile render edilir.
   - Test 9: Ürün Arama modalı açıkken `F1`/`F9` arka plan kısayolları tetiklemez ve sepette ürün varken DB fiyat değişiminde `PaymentDialog` içinde hata gösterilip satış engellenir.

---

## 5. Test Sonuçları

Son kod düzenlemelerinden sonra tüm paketler tek tek (CPU çakışması olmadan) çalıştırılmıştır:

| Paket / Kapsam | Komut | Sonuç | Detay |
|---|---|---|---|
| **Ana Flutter Uygulaması** | `flutter test --no-pub` | **GEÇTİ (67/67)** | `00:17 +67: All tests passed!` (Exit 0, atlanan/devre dışı test yok) |
| **`packages/mms_client_storage`** | `dart test` (`packages/mms_client_storage`) | **GEÇTİ (63/63)** | `00:33 +63: All tests passed!` (Exit 0, gerçek FFI SQLite WAL + PBKDF2 600k dahil) |
| **`test_spikes/spike_01_backend`** | `dart test -j 1` (`test_spikes/spike_01_backend`) | **GEÇTİ (144/144)** | `01:50 +144: All tests passed!` (Exit 0, PBKDF2 600k zaman aşımını önlemek için sıralı dosya moduyla çalıştırıldı; önceki paralel çalıştırmada eşzamanlı CPU yükü nedeniyle 2 PBKDF2 testi 30s timeout almıştı) |
| **Toplam Doğrulanan Test** | — | **274/274** | %100 başarılı |

---

## 6. Statik Analiz (`Analyze`) ve Mimari Hijyen Sonuçları

- **Ana uygulama:** `flutter analyze --no-pub` → `No issues found! (ran in 2.8s)` (Exit 0)
- **`packages/mms_client_storage`:** `dart analyze` → `No issues found!` (Exit 0)
- **`test_spikes/spike_01_backend`:** `dart analyze` → `No issues found!` (Exit 0)
- **Saf Dart Domain Koruması (`lib/features/pos/domain/*.dart`):** `DOMAIN_VIOLATIONS=0` (`flutter`, `drift`, `http`, `mms_client_storage.dart` bağımlılığı yok)
- **Tamsayı Kuruş Aritmetiği (`lib/features/pos/**/*.dart`):** Çalıştırılabilir kodda `double` kullanımı `0` (`cart_state.dart:42` ve `money.dart:1` yalnız yorum satırları)

---

## 7. Build Sonucu

- **Komut:** `flutter build windows --debug`
- **Sonuç:** **BAŞARILI** (`62,0s`, Exit 0)
- **Üretilen Çıktı:** `build\windows\x64\runner\Debug\market_pos.exe`
- *Not:* Release paket (`flutter build windows --release`) bu doğrulama turunda çalıştırılmamıştır; yalnızca `--debug` Windows derlemesi doğrulanmıştır.

---

## 8. Çözülemeyen veya İleri Faza Kalan Riskler

- **Gerçek Windows Fiziksel Ekran / USB HID Donanım Testi:** Widget testleri `tester.view.physicalSize` (`640x720`, `1280x760`) ve sentetik klavye olaylarıyla doğrulanmıştır; fiziksel USB HID okuyucu donanımı ve canlı Windows penceresi üzerinde el ile doğrulama henüz yapılmamıştır.
- **Unicode Türkçe Küçük/Büyük Harf Arama (`İ`/`ı`/`Ş`):** SQLite `LOWER()` yalnızca ASCII katlaması yaptığından, ASCII olmayan aramalar 200'lük sayfalı (bounded) taramaya yönlendirilmiştir; çok yüksek ürün sayısında (ör. >10.000 SKU) Türkçe karakter yoğun sorgularda sayfa tarama maliyeti artabilir (ileride FTS5/normalize arama kolonu ayrı migration fazında değerlendirilebilir).
- **Release Windows Derlemesi ve Faz 1.1 Açık Teknik Koşullar:** `flutter build windows --release` henüz çalıştırılmamıştır; ayrıca `GEMINI.md` içindeki pilot öncesi güvenlik koşulları (`B-2`, `B-3`, SCM, ACL, fiziksel mobil testler) kapsam dışı bırakılmıştır.

---

## 9. Schema Migration veya Yeni Bağımlılık İhtiyacı

- **Schema Migration:** **Gerekmiyor / Yapılmadı.** `packages/mms_client_storage/lib/src/database/client_database.dart` dosyasında `git diff` boştur (`schemaVersion` değiştirilmedi).
- **Yeni Paket / Bağımlılık:** **Gerekmiyor / Eklenmedi.** Kök `pubspec.yaml`, `packages/mms_client_storage/pubspec.yaml` ve `test_spikes/spike_01_backend/pubspec.yaml` dosyalarında `git diff` boştur.

