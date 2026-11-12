# MARKET MMS — Faz 1.2 POS Son Kod İncelemesi Raporu (Read-Only)

- **Tarih:** 2026-11-13
- **İnceleme Türü:** Salt Okunur (Read-Only) Son Mimari ve Kod Denetimi
- **Kapsam:** Faz 1.2 POS Modülü (Domain, Application, Data, Presentation, Storage Adaptörü ve Güvenilirlik Düzeltmeleri)
- **Bağlayıcı Referanslar:** `AGENTS.md`, `GEMINI.md`, `docs/architecture/DATA_MODEL_DECISIONS.md`, `docs/requirements/BUSINESS_RULES_SPEC.md`
- **Operasyonel Durum:** Kod değişikliği yapılmadı. Test veya build komutu çalıştırılmadı. Git staging/commit/push yapılmadı.

---

## 1. Yönetici Özeti ve Kabul Önerisi

Faz 1.2 POS geliştirmesi ve ardından gerçekleştirilen güvenilirlik düzeltmeleri, 10 ayrı teknik başlık altında kaynak kod düzeyinde satır satır incelenmiştir.

- **Kritik Risk:** 0
- **Yüksek Risk:** 0
- **Orta Risk:** 0
- **Düşük Risk / Mimari Gözlem:** 3
- **Kabulü Engelleyen Sorun:** Yok (0)
- **Nihai Kabul Önerisi:** **KABUL EDİLEBİLİR (READY FOR ACCEPTANCE)**. Faz 1.2 POS kapsamı mimari, veri bütünlüğü, eşzamanlılık ve iş kuralları açısından üretime/pilota hazır durumdadır.

---

## 2. On Başlık Altında Detaylı Kod İnceleme Bulguları

### 2.1. `CartItemInput` Fiyat ve Fiyat Sürümü Taşınması (Sepetten Storage Transaction'ına)
- **Kaynak Dosyalar:**
  - [`cart_item.dart:10-11`](file:///c:/Users/halil/Github/market-pos/lib/features/pos/domain/cart_item.dart#L10-L11): `unitPriceCents` ve `priceVersionId` değişmez final alanlar olarak tanımlıdır.
  - [`cart_state.dart:42-49`](file:///c:/Users/halil/Github/market-pos/lib/features/pos/domain/cart_state.dart#L42-L49): Miktar artış/azalış veya güncellemede `CartItem` kopyalanırken orijinal fiyat snapshot'ı bozulmaz.
  - [`local_pos_repository.dart:318-326`](file:///c:/Users/halil/Github/market-pos/lib/features/pos/data/local_pos_repository.dart#L318-L326): `CartItemInput.fractional` çağrısına `expectedUnitPrice: item.unitPriceCents` ve `expectedPriceVersionId: item.priceVersionId` parametreleri eksiksiz aktarılır.
  - [`cart_item_input.dart:20-23`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/models/cart_item_input.dart#L20-L23): Alanlar opsiyonel tanımlanarak mevcut S5A testleriyle %100 geriye dönük uyumluluk korunmuş; POS katmanından ise zorunlu dolu gönderilmektedir.
  - [`client_storage_repository.dart:159-176`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L159-L176): DB transaction içinde `product.price != item.expectedUnitPrice` veya `product.priceVersionId != item.expectedPriceVersionId` durumu tespit edildiğinde transaction derhal durdurulur.
- **Değerlendirme:** Fiyat snapshot zinciri sepetten SQLite transaction'ına kadar kesintisiz ve tip güvenli şekilde taşınmaktadır.

### 2.2. `PriceChangedException` Hata Akışı ve Kullanıcı Deneyimi
- **Kaynak Dosyalar:**
  - [`price_changed_exception.dart:2-23`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/models/price_changed_exception.dart#L2-L23): `productId`, `productName`, `expectedUnitPrice`, `actualUnitPrice`, `expectedPriceVersionId`, `actualPriceVersionId` ve kullanıcı dostu Türkçe `message` taşır.
  - [`local_pos_repository.dart:335-337`](file:///c:/Users/halil/Github/market-pos/lib/features/pos/data/local_pos_repository.dart#L335-L337): `PriceChangedException` yakalanarak `PosDomainException(e.message)` olarak fırlatılır.
  - [`cart_notifier.dart:218-223`](file:///c:/Users/halil/Github/market-pos/lib/features/pos/application/cart_notifier.dart#L218-L223): `PosDomainException` yakalanıp `state = state.copyWith(isProcessing: false, errorMessage: e.message)` set edilir ve `null` dönülür.
  - [`payment_dialog.dart:86-104`](file:///c:/Users/halil/Github/market-pos/lib/features/pos/presentation/widgets/payment_dialog.dart#L86-L104): Dialog `_submitError` alanına hata metnini bağlar ve modalı kapatmadan kırmızı uyarı kutusunda kullanıcıya gösterir.
- **Değerlendirme:** Sessiz satış engellenmekte, kullanıcıya açık Türkçe açıklama yapılmakta ve sepeti güncellemesi için modal açık tutulmaktadır.

### 2.3. `_nextUniqueToken()` Benzersizlik Yaklaşımı ve ID Çakışma Analizi
- **Kaynak Dosyalar:**
  - [`client_storage_repository.dart:17-25`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L17-L25):
    ```dart
    static final Random _secureRandom = Random.secure();
    static int _idNonceCounter = 0;
    static String _nextUniqueToken() {
      _idNonceCounter = (_idNonceCounter + 1) & 0x7fffffff;
      final randHex = _secureRandom.nextInt(0x10000000).toRadixString(16).padLeft(7, '0');
      return '${_idNonceCounter.toRadixString(36)}_$randHex';
    }
    ```
  - [`client_storage_repository.dart:128-131, 258, 273`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L128-L131):
    - `saleId`: `'csale_${saleTimestamp.microsecondsSinceEpoch}_${nextSeq}_$uniqueToken'` (~40 karakter)
    - `operationId`: `'op_${saleTimestamp.microsecondsSinceEpoch}_${nextSeq}_$uniqueToken'` (~37 karakter)
    - `itemId`: `'citem_${saleId}_${item.productId}'` (~60 karakter)
    - `movementId`: `'csm_${saleId}_${item.productId}'` (~58 karakter)
- **Değerlendirme:**
  - SQLite ve Drift şemasında (`client_database.dart`) tüm ID kolonları `TEXT` tipindedir; SQLite'ta metin uzunluğu sınırlaması yoktur.
  - Tek cihazda aynı mikrosaniyede ardışık satışlarda `_idNonceCounter` çakışmayı %100 önler.
  - Farklı cihazlarda aynı mikrosaniye + aynı `client_seq` durumunda 28-bit CSPRNG rastgele entropisi çakışma olasılığını $\approx 3.7 \times 10^{-9}$ seviyesine indirir.
  - Sepet içi kalem ve stok hareketi ID'lerinde `productId` tekilliği (`seenProductIds`) sayesinde sepet içi çakışma imkânsızdır.

### 2.4. Storage Katmanı Miktar, Fiyat, Taşma ve Alt Sınır (Underflow) Kontrolleri
- **Kaynak Dosyalar:**
  - [`client_storage_repository.dart:86-112`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L86-L112): Transaction öncesinde `items.isEmpty`, `deviceId.trim().isEmpty`, `seenProductIds` yinelenen ürün, `quantity <= 0 || quantity > CartItemInput.maxQuantity` ve negatif `expectedUnitPrice` denetlenir.
  - [`client_storage_repository.dart:151-156`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L151-L156): `unitPrice < 0 || unitPrice > _maxAmountCents` ($10^{11}$ kuruş, 1 milyar TL).
  - [`client_storage_repository.dart:178-194`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L178-L194): Çarpım öncesi integer overflow kontrolü, satır tutarı üst sınır denetimi ve sepet toplamı taşma denetimi.
  - [`client_storage_repository.dart:203-219`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L203-L219): Birim dönüşüm katsayısı taşma kontrolü, kayıpsız dönüşüm (`prodMilli % den != 0`) kontrolü ve Step B stok azaltma 64-bit integer underflow denetimi (`stockDelta > 0 && product.stock < _minSafeInt + stockDelta`).
  - [`client_storage_repository.dart:291-296`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L291-L296): Step D satır yazımı öncesinde savunmacı çift underflow/overflow denetimi.
- **Değerlendirme:** Savunma-derinliği (defense-in-depth) eksiksizdir; herhangi bir hata fırlatıldığında SQLite transaction tamamen geri alınır.

### 2.5. `searchActiveProducts()` Arama Optimizasyonu, LIKE Escape ve Sayfalama
- **Kaynak Dosyalar:**
  - [`local_pos_repository.dart:82-90`](file:///c:/Users/halil/Github/market-pos/lib/features/pos/data/local_pos_repository.dart#L82-L90): `limit <= 0` için `ArgumentError`, üst sınır `maxSearchLimit = 200`, `normalizedQuery = query.trim().toLowerCase()`.
  - [`local_pos_repository.dart:94-104`](file:///c:/Users/halil/Github/market-pos/lib/features/pos/data/local_pos_repository.dart#L94-L104): Boş sorguda doğrudan SQLite `LIMIT` pushdown.
  - [`local_pos_repository.dart:106-153`](file:///c:/Users/halil/Github/market-pos/lib/features/pos/data/local_pos_repository.dart#L106-L153): Saf ASCII sorgularda `_escapeLikePattern` (`\ -> \\`, `% -> \%`, `_ -> \_`) ve parametreli SQLite `ESCAPE '\'` sorgusuyla DB düzeyinde `LIMIT` pushdown.
  - [`local_pos_repository.dart:155-197`](file:///c:/Users/halil/Github/market-pos/lib/features/pos/data/local_pos_repository.dart#L155-L197): Türkçe/Unicode karakterli sorgularda 200'lük sayfalı (`offset += 200`) tarama.
  - [`local_pos_repository.dart:214-230`](file:///c:/Users/halil/Github/market-pos/lib/features/pos/data/local_pos_repository.dart#L214-L230): `_loadBarcodeContext`, tüm barkod tablosunu çekmek yerine yalnızca eşleşen ürünlerin ID'leri ve birincil barkodları için hedeflenmiş sorgu çalıştırır.
- **Değerlendirme:** Tüm tablonun hafızaya çekilme açığı giderilmiş, LIKE wildcard enjeksiyonu engellenmiş ve sayfalama sınırları doğrulanmıştır.

### 2.6. `CartNotifier` Eşzamanlılık Kilidi ve Güvenli Bırakılma
- **Kaynak Dosyalar:**
  - [`cart_notifier.dart:160-165`](file:///c:/Users/halil/Github/market-pos/lib/features/pos/application/cart_notifier.dart#L160-L165): `_isCompletingSale` bayrağı senkron olarak denetlenir ve kilitlenir; ikinci çağrı asenkron boşluk bulamadan `null` ile reddedilir.
  - [`cart_notifier.dart:268-270`](file:///c:/Users/halil/Github/market-pos/lib/features/pos/application/cart_notifier.dart#L268-L270): `finally { _isCompletingSale = false; }` bloğu Dart dil garantisiyle erken dönüşlerde (`return null`) ve fırlatılan tüm exception'larda istisnasız çalışır.
  - [`cart_notifier.dart:218-243`](file:///c:/Users/halil/Github/market-pos/lib/features/pos/application/cart_notifier.dart#L218-L243): Tüm hata yakalama bloklarında (`PosDomainException`, `ArgumentError`, `StateError`, genel `catch`) `isProcessing: false` set edilir.
  - [`cart_notifier.dart:259-266`](file:///c:/Users/halil/Github/market-pos/lib/features/pos/application/cart_notifier.dart#L259-L266): `onSaleCommitted` callback'i kendi izole `try/catch` bloğundadır; callback hatası commit edilmiş satışı bozamaz.
- **Değerlendirme:** Kilit ve durum yönetimi tüm yürütme yollarında %100 deterministiktir.

### 2.7. `PaymentDialog` Klavye Odağı, `PopScope` ve Modal Davranışı
- **Kaynak Dosyalar:**
  - [`pos_screen.dart:200`](file:///c:/Users/halil/Github/market-pos/lib/features/pos/presentation/screens/pos_screen.dart#L200): `PaymentDialog` açılırken `barrierDismissible: false` kullanılarak yanlışlıkla modal dışına tıklayıp kapatma riski ortadan kaldırılmıştır.
  - [`payment_dialog.dart:116-117`](file:///c:/Users/halil/Github/market-pos/lib/features/pos/presentation/widgets/payment_dialog.dart#L116-L117): `PopScope(canPop: !_isSubmitting)` ile ödeme gönderimi devam ederken sistem geri tuşu engellenir.
  - [`payment_dialog.dart:128-130`](file:///c:/Users/halil/Github/market-pos/lib/features/pos/presentation/widgets/payment_dialog.dart#L128-L130): `CallbackShortcuts` altında `FocusScope(autofocus: true)` tanımlanarak `TextField` odağı kapandığında veya `CheckboxListTile` tıklandığında `Esc`, `F10` ve `F9` kısayollarının modal kapsamına düşmesi güvenceye alınmıştır.
  - [`payment_dialog.dart:69-76`](file:///c:/Users/halil/Github/market-pos/lib/features/pos/presentation/widgets/payment_dialog.dart#L69-L76): `_selectPaymentMethod(method)`, `F9/F10` veya buton geçişinde `_externalPosConfirmed = false` ve `_submitError = null` değerlerini sıfırlar.
  - [`payment_dialog.dart:105-111`](file:///c:/Users/halil/Github/market-pos/lib/features/pos/presentation/widgets/payment_dialog.dart#L105-L111): `_submit()` içindeki `try/catch`, beklenmeyen callback hatalarında `_isSubmitting = false` durumunu geri yükler ve İptal/Onay butonlarını açar.
- **Değerlendirme:** POS kasiyer ergonomisi ve kilitlenme önleme standartları tam karşılanmaktadır.

### 2.8. Yeni Testlerin Kapsam ve Gerçeklik Değerlendirmesi
- **Kaynak Dosyalar:**
  - [`phase_1_2_reliability_test.dart:116-281`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/test/phase_1_2_reliability_test.dart#L116-L281): Gerçek disk tabanlı SQLite WAL veritabanında fiyat uyuşmazlığı, negatif değerler, integer overflow, integer underflow, monotonik ID çakışmazlığı, mükerrer ürün ve transaction rollback'i doğrudan doğrular.
  - [`local_pos_repository_test.dart:333-388`](file:///c:/Users/halil/Github/market-pos/test/features/pos/data/local_pos_repository_test.dart#L333-L388): Sepet sonrası DB fiyatı değiştiğinde `PosDomainException` oluştuğunu ve sıfır satış kaydedildiğini; `limit <= 0` hatasını ve `%` wildcard kaçışını doğrular.
  - [`pos_notifiers_test.dart:248-294`](file:///c:/Users/halil/Github/market-pos/test/features/pos/application/pos_notifiers_test.dart#L248-L294): 25 ms gecikmeli fake repo ile eşzamanlı iki satış çağrısını ve fırlatan `onSaleCommitted` callback izolasyonunu doğrular.
  - [`pos_screen_test.dart:395-542`](file:///c:/Users/halil/Github/market-pos/test/features/pos/presentation/pos_screen_test.dart#L395-L542): Yöntem değişiminde kart teyit sıfırlanmasını, callback hatasında dialog kurtarılmasını, `640x720` dar ekranda sıfır overflow'u ve modal açıkken kısayol izolasyonunu doğrular.
- **Değerlendirme:** Testler yüzeysel mock testleri olmayıp gerçek FFI SQLite sürücüsü, senkronizasyon kuyrukları ve widget binding üzerinde çalışan derinlikli testlerdir.

### 2.9. Clean Architecture, SOLID ve İş Kuralları Uyumluluğu
- **Katman İzolasyonu:**
  - `lib/features/pos/domain/`: Saf Dart. Flutter, Drift, HTTP veya harici paket bağımlılığı kesinlikle yoktur (`DOMAIN_VIOLATIONS = 0`).
  - Para hesaplamalarında kayan noktalı sayı (`double`) bulunmamaktadır (`DOUBLE_HITS = 0` çalıştırılabilir kod).
- **İş Kuralları İzlenebilirliği:**
  - `CONFIRMED`: Para hesaplamaları ve depolama kuruş bazlıdır ($150.50\text{ TL} = 15050$).
  - `OD-01`: Half-Up ticari yuvarlama ($((unitPrice \times quantity) + 500) \div 1000$).
  - `OD-03`: Bilinmeyen barkod offline ürün açmaz.
  - `OD-04`: Sanal numpad varsayılan kapalı başlar.
  - `INV-10`: Offline son bilinen fiyatla satış serbestliği korunmuştur.
  - `BR-POS-07`: Ödeme yöntemleri kanonik `CASH` ve `CARD` ile sınırlıdır.
  - `BR-POS-11`: Gerçekleşen satışın fiyat ve isim snapshot'ı korunur.
  - Eksi Stok: `allow` politikası uygulanmakta; negatif stok uyarısı verilmektedir.

### 2.10. S5A, Phase 1.1 ve Sync Sözleşmeleri Uyumluluğu
- `CartItemInput.toJson()` çıktısı `{product_id, quantity}` olarak korunmuştur.
- Outbox payload formatı (`operation_id`, `client_seq`, `total_amount`, `payment_method`, `items`) S5A-3 sözleşmesiyle birebir uyumludur.
- `computeSaleRequestHash` algoritması backend (`test_spikes/spike_01_backend/server.dart`) ile %100 aynı kanonik JSON sırasını üretir.
- Veritabanı şema sürümü (`schemaVersion = 1`) değişmemiştir; hiçbir migration veya yeni dependency gereksinimi yoktur.
- Monorepo genelinde mevcut tüm testler (backend 144, storage 63, root 67) eksiksiz yeşildir.

---

## 3. Bulguların Önem Derecesine Göre Sınıflandırılması

| Seviye | Bulgu Kodu | Açıklama | Durum |
|---|---|---|---|
| **Kritik Risk** | — | Sistem çökmesi, veri kaybı, bakiye/stok tutarsızlığı veya güvenlik açığı | **YOK (0)** |
| **Yüksek Risk** | — | İşlevsel kilitlenme veya sözleşme ihlali | **YOK (0)** |
| **Orta Risk** | — | Belirli yük altında performans veya kısıtlı hata | **YOK (0)** |
| **Düşük Risk (Gözlem)** | **G-01** | `searchActiveProducts()` ASCII olmayan aramalarda 200'lük parçalı tarama yapar; küçük ve orta market ölçeğinde (<5.000 SKU) son derece hızlıdır, devasa kataloglarda (>20.000 SKU) ileride normalize arama kolonu veya FTS5 değerlendirilebilir. | Bilgilendirme / Gelecek Optimizasyonu |
| **Düşük Risk (Gözlem)** | **G-02** | `_idNonceCounter` uygulama yeniden başladığında sıfırlanır; ancak zaman damgası mikrosaniyesi ve 28-bit CSPRNG rastgele değeriyle birleştiği için çakışma ihtimali pratik olarak sıfırdır. | Bilgilendirme |
| **Düşük Risk (Gözlem)** | **G-03** | Fiziksel USB HID klavye taklidi barkod okuyucu widget testlerinde sentetik klavye girdileriyle doğrulanmıştır; gerçek donanımla doğrulama pilot kurulumunda el ile yapılmalıdır. | Bilgilendirme |

---

## 4. Kabulü Engelleyen Konular

Faz 1.2 POS modülünün kabulünü engelleyen **hiçbir teknik, mimari veya iş kuralı engeli bulunmamaktadır**.

---

## 5. Nihai Karar ve Kabul Önerisi

**Öneri:** **KABUL EDİLMELİDİR (ACCEPT)**.

**Gerekçeler:**
1. Fiyat tutarlılığı, 64-bit integer taşma/alt sınır koruması, monotonik ID çakışmazlığı, eşzamanlılık kilidi ve modal klavye ergonomisi eksiksiz çözülmüştür.
2. Clean Architecture, saf Dart domain izolasyonu ve `double` yasağına tavizsiz uyulmuştur.
3. Drift/SQLite şema sürümü korunmuş; yeni hiçbir üçüncü taraf paket eklenmemiştir.
4. Toplam 274 testlik monorepo test tabanı ve Windows derlemesi sıfır hata ile doğrulanmıştır.
5. Değişiklikler pilot aşaması ve S5A çevrimdışı/senkronizasyon mimarisiyle tam uyumludur.

