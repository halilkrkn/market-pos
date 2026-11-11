# Faz 1.2 Nihai Ön Kontrol Raporu (Final Preflight Review)
# MARKET MANAGEMENT SYSTEM (MARKET MMS)

**Belge Kodu:** `PHASE_1_2_FINAL_PREFLIGHT_REPORT.md`  
**Tarih:** 11 Kasım 2026  
**Aşama:** Faz 1.2 Kodlama Öncesi Son Teknik Doğrulama (Kodlama Henüz Başlatılmadı)  
**Hazırlayan:** Antigravity (Gemini)  
**Karar ve Onay Mercii:** Proje Sahibi  
**Dayanak Belgeler:** [`AGENTS.md`](../../AGENTS.md), [`GEMINI.md`](../../GEMINI.md), [`PHASE_1_2_PREPARATION_REPORT.md`](./PHASE_1_2_PREPARATION_REPORT.md), [`DATA_MODEL.md`](../architecture/DATA_MODEL.md), [`DESIGN_DECISIONS.md`](../ui-ux/DESIGN_DECISIONS.md)

> [!IMPORTANT]
> **Salt İnceleme ve Kısıt Beyanı (`AGENTS.md` §12–15):**  
> Bu görev kapsamında `lib/`, `test/`, `pubspec.yaml`, `packages/`, `test_spikes/` backend dosyaları ve veritabanı şemalarında **hiçbir değişiklik yapılmamış**, yeni paket eklenmemiş, `git add` / `commit` / `push` çalıştırılmamış ve **Faz 1.2 kodlamasına başlanmamıştır**. Yalnızca mevcut kaynak kodlar, testler ve kanonik dokümantasyon doğrudan incelenerek kanıta dayalı bulgular raporlanmıştır.

---

## 1. Ödeme Sözleşmesi (`PaymentMethod`) — BLOCKING Analizi ve Kanıtlar

### 1.1. Depodaki Gerçek Kod ve Doküman Durumu (Katman Katman Envanter)

Depo genelindeki tüm Dart kaynak kodları, drift şemaları, backend uçları, testler ve mimari dokümanlar taranarak aşağıdaki gerçek tablo doğrulanmıştır:

| Katman / Dosya | Mevcut Durum / Kullanılan Değer | Sözleşme / Kısıt Durumu |
|---|---|---|
| **Kanonik Veri Modeli (`DATA_MODEL.md`)** | `sales.payment_method`: `'CASH'`, **`'CARD'`** (`L415`, `L430`, `L436`)<br/>`refunds.refund_payment_method`: `'CASH'`, **`'CARD'`** (`L483`)<br/>`payment_method_corrections`: `'CASH'`, **`'CARD'`** (`L520-521`)<br/>`DATA_MODEL_DECISIONS.md`: `'CASH'`, **`'CARD'`** (`L138`, `L144`) | **SQL CHECK Kısıtı Tanımlı:** `CHECK (payment_method IN ('CASH', 'CARD'))` ve `chk_sales_payment_consistency` (`NEW-01`) |
| **İstemci Yerel Şema (`client_database.dart:56`)** | `TextColumn get paymentMethod => text()(); // 'CASH', 'CREDIT_CARD', etc.` | SQL CHECK kısıtı **yok**; serbest `TEXT`. `'CREDIT_CARD'` yalnızca satır içi yorumda geçer |
| **İstemci Repository (`client_storage_repository.dart`)** | `createOfflineSale(..., required String paymentMethod)` (`L67, 176, 231, 267`) ve `computeSaleRequestHash` (`L22`) | Değer doğrulaması / enum kontrolü **yok**. Parametreyi doğrudan `local_sales`, `outbox_operations.payload` ve SHA-256 hash içine yazar |
| **Flutter Uygulaması (`lib/`)** | `lib/core/storage/local_database_service.dart:438` parametreyi geçirir; `lib/` içinde sıfır `'CARD'`, `'CREDIT_CARD'` veya `PaymentMethod` enumu | Henüz Faz 1.2 kodlaması başlamadığı için sabit yok |
| **Backend Veritabanı (`spike_01_backend/lib/db/database.dart:31`)** | `TextColumn get paymentMethod => text()();` | SQL CHECK kısıtı **yok**; serbest `TEXT` |
| **Backend Satış / Sync Ucu (`spike_01_backend/bin/server.dart`)** | `POST /api/v1/sales` (`L946, 995, 1198`) ve `computeSaleRequestHash` (`L123`):<br/>`final paymentMethod = body['payment_method'] as String? ?? 'CASH';` *(Ayrı bir `/sync` batch endpoint'i henüz yoktur; `ClientSyncService` + `HttpSyncTransport.postSale` outbox payload'ını doğrudan `/api/v1/sales` ucuna yollar.)* | Değer doğrulaması **yok**! Gelen herhangi bir String (`CARD`, `CREDIT_CARD`, `NAKIT`) kabul edilip `sales` tablosuna yazılır; `null` gelirse sessizce `'CASH'` atanır |
| **Mevcut Testler (Çelişen Örnekler)** | - **~45+ test:** `'CASH'`<br/>- `packages/mms_client_storage/test/s5a3_outbox_sync_test.dart:172`: **`'CREDIT_CARD'`**<br/>- `packages/mms_client_storage/test/s5a3_live_hub_integration_test.dart:270`: **`'CREDIT_CARD'`**<br/>- `test_spikes/spike_01_backend/test/s5a2_durability_lifecycle_test.dart:499, 548`: **`'CREDIT_CARD'`**<br/>- `test_spikes/spike_01_backend/test/s4_device_pairing_test.dart:1300, 1391, 1455, 1488`: **`'NAKIT'`** | Spike ve paket testlerinde geçmişte standart dışı test dizgileri (`CREDIT_CARD` ve `NAKIT`) kullanılmıştır |
| **UX / Hazırlık Belgeleri** | `UX_FINAL_VERIFICATION_AND_RECONCILIATION_REPORT.md:253` & `PHASE_1_2_PREPARATION_REPORT.md:32`: `'CASH'` / `'CARD'` (`PHASE_1_2_PREPARATION_REPORT` `R-04` çelişkiyi işaretlemiştir) | Doküman düzeyinde `'CARD'` lehine; kod uyumu bekleniyor |

### 1.2. Kanıta Dayalı Kanonik Değer Kararı: `'CASH'` ve `'CARD'`

**Önerilen Kanonik Değerler:** Nakit için **`'CASH'`**, Kredi Kartı için **`'CARD'`**.

**Dayanak Kanıtlar:**
1. **Kanonik Mimari ve PostgreSQL/Supabase CHECK Uyumluluğu (`DATA_MODEL.md:415, 430-440`):** Proje anayasası (`AGENTS.md` §2) mevcut yerel yapının gelecek PostgreSQL/Supabase SaaS fazıyla uyumlu tutulmasını zorunlu kılar. `DATA_MODEL.md` altındaki 3 temel tabloda (`sales`, `refunds`, `payment_method_corrections`) `CHECK (... IN ('CASH', 'CARD'))` kısıtı bağlayıcıdır. `'CREDIT_CARD'` seçilirse gelecek SaaS / kanonik şema geçişinde veya iade/ödeme düzeltme tablolarında **veritabanı kısıtı (`check_violation`) her kart satışını reddedecektir**.
2. **Düşük Değişiklik Maliyeti ve Sıfır Üretim Etkisi:** `'CREDIT_CARD'` hiçbir gerçek üretim verisinde, Flutter UI'da (`lib/`), SQL `CHECK` kısıtında veya API validator'ında zorunlu tutulmamaktadır; yalnızca `client_database.dart:56` yorumunda ve 3 eski test dosyasındaki birkaç satırda yer almaktadır (`s4_device_pairing_test.dart` içindeki `'NAKIT'` gibi test verisi tutarsızlığıdır).
3. **Outbox SHA-256 Hash ve Append-Only Koruma Gereği:** `ClientStorageRepository.createOfflineSale` (`L22, L231, L236`) `payment_method` değerini değiştirilemez `outbox_operations.payload` ve SHA-256 `payload_hash` içine gömer; backend `server.dart:123` da aynı hash'i doğrular. Faz 1.2 başladıktan sonra üretilecek her yerel satış kaydı Outbox payload'ına kazınacağından, bu sözleşmenin **Faz 1.2 kodlaması başlamadan önce** `'CARD'` olarak kilitlenmesi zorunludur.

### 1.3. Uygulanacak Çözüm Planı (Faz 1.2 Onayıyla Birlikte İlk Adımda Yapılacaklar)
1. **Flutter Domain Sabiti (`lib/features/pos/domain/`):** Saf Dart `enum PaymentMethod { cash('CASH'), card('CARD') }` tanımlanır; UI/Application/Data katmanları serbest String yerine yalnızca bu tipi kullanır.
2. **Yerel Repository & Veri Modeli Uyumu (Faz 1.2 Başlangıcı veya Hazırlık Adımı):**
   - `client_database.dart:56` yorumu `// 'CASH', 'CARD'` olarak düzeltilir *(mevcut schemaVersion=1 yapısı korunarak gereksiz migration açılmaz; istenirse uygulama/repository katmanında sabit doğrulaması uygulanır)*.
   - Backend `server.dart:995` (`POST /api/v1/sales`): Sessiz `?? 'CASH'` fallback'ı kaldırılıp `payment_method` alanının `'CASH'` veya `'CARD'` olmasını zorunlu kılan açık `400 ERR_INVALID_PAYMENT_METHOD` doğrulaması eklenmelidir *(Faz 1.2 kapsamında backend dosyasına dokunulmayacaksa, ayrı bir sözleşme/sync sertleştirme adımında ele alınmak üzere takip kaydına alınır; ancak istemci Faz 1.2'de her zaman yalnızca `'CASH'` / `'CARD'` üretir)*.
   - Eski test dosyalarındaki 3 `'CREDIT_CARD'` ve 4 `'NAKIT'` örnek dizgisi tekil bakım adımında `'CARD'` ve `'CASH'` olarak standardize edilir.

---

## 2. Device ID Değerlendirmesi (Faz 1.2 Kapsam İncelemesi)

### 2.1. Mevcut Kod Kullanımı ve İlişki Haritası
- [`AppConstants.defaultDeviceId`](../../lib/core/constants/app_constants.dart#L12) = `'POS-WIN-01'`.
- **İstemci API İstemcisi (`lib/core/network/api_client.dart:17, 24, 33`):** `MmsApiClient` varsayılan olarak `AppConstants.defaultDeviceId` alır ve her HTTP isteğinin `'X-Device-Id'` başlığına ekler.
- **Durum Sağlayıcılar (`system_status_notifier.dart:12, 30`, `system_status.dart:12, 37`):** `apiClientProvider` üzerinden `systemStatusProvider` içine aktarılır; `CashierHeaderBar:55` ve `diagnostics_view.dart:135` ekranlarında gösterilir.
- **Yerel Satış & Outbox & Seq İlişkisi (`client_storage_repository.dart:29-89, 173, 242, 255`):**
  - `createOfflineSale(deviceId: ...)` çağrıldığında `client_sync_states` tablosunda ilgili `deviceId` yoksa `initializeDevice(deviceId)` ile `currentClientSeq = 0` satırı oluşturulur; her satışta `nextSeq = currentClientSeq + 1` hesaplanır.
  - `(deviceId, clientSeq)` ikilisi hem `local_sales` (`L65`) hem `outbox_operations` (`L120`) tablolarında **`UNIQUE` anahtardır**. Bu sayede aynı cihaz için FIFO sırası (`1, 2, 3...`) bozulmaz.
- **Sunucu Idempotency İlişkisi (`server.dart:947-948, 994`, `s5a2_durability_lifecycle_test.dart:624`):**
  - `POST /api/v1/sales` güvenlik gereği gövdedeki sahte `device_id` veya `X-Device-Id` başlığına güvenmez; doğrudan kimliği doğrulanmış `Bearer` token'a bağlı **`req.context['authenticated_device_id']`** değerini kullanır ve merkezi idempotency anahtarını **`$deviceId:$clientSeq`** biçiminde üretir.

### 2.2. Faz 1.2 Engel Değerlendirmesi
- **Sabit `defaultDeviceId` Faz 1.2 için GERÇEK BİR ENGEL MİDİR?** **HAYIR.**
- **Neden Engel Değildir?**
  1. Faz 1.2 yalnızca tekil Windows masaüstü istemcisinde yerel POS UI, sepet ve `client_local.db` offline satış/outbox üretimi aşamasıdır (`Device Token` ve otomatik `ClientSyncService` çalışması Faz 2 / Faz 5 kapsamındadır).
  2. Sabit `'POS-WIN-01'` ile yerel `client_sync_states`, `local_sales` ve `outbox_operations` tablolarındaki `(device_id, client_seq)` tekilliği ve artışı %100 tutarlı çalışır; `client_storage_repository.dart` ve `ClientSyncService` zaten cihaz başına sıra sayacını bu mimariye göre kurmuştur.
  3. **Mimari Uyum Şartı (Yeni Mekanizma Açmadan):** Faz 1.2 kodu `deviceId` değerini POS katmanında ikinci kez sabit kodlamak (`'POS-WIN-01'`) yerine mevcut `systemStatusProvider` / `apiClientProvider` (`AppConstants.defaultDeviceId`) üzerinden tek noktadan okuyarak `createOfflineSale` metoduna geçirmelidir.
  4. **Faz 2 Devir Notu:** Faz 2'de dinamik cihaz kaydı / QR eşleştirme (`device_id` + `Bearer` token) devreye alındığında yerel `client_local.db` geliştirme verileri sıfırlanarak eşleştirilmiş gerçek cihaz kimliğiyle senkronize başlatılır (veya Faz 2 eşleştirme akışıyla devralınır).
- **Sonuç:** Faz 1.2'de yeni cihaz kayıt mekanizması oluşturulmayacak ve mevcut mimari değiştirilmeyecektir; dinamik cihaz kimliği çözümü **Faz 2'ye bırakılmıştır**.

---

## 3. Para Hesaplama ve Miktar Sözleşmesi Doğrulaması (`OD-01` & Half-Up)

Tüm doğrulama doğrudan [`cart_item_input.dart`](../../packages/mms_client_storage/lib/src/models/cart_item_input.dart), [`client_storage_repository.dart`](../../packages/mms_client_storage/lib/src/database/client_storage_repository.dart), [`client_database.dart`](../../packages/mms_client_storage/lib/src/database/client_database.dart) ve [`server.dart`](../../test_spikes/spike_01_backend/bin/server.dart) kaynak kodları üzerinden yapılmıştır:

### 3.1. Soru Bazlı Teknik Doğrulama Tablosu

| Doğrulama Sorusu | Gerçek Kod Kanıtı | Doğrulama Sonucu |
|---|---|---|
| **1. `unitPrice` birimi kuruş mu?** | [`client_database.dart:14`](../../packages/mms_client_storage/lib/src/database/client_database.dart#L14) (`// Kuruş bazlı birim satış fiyatı Ör: 200 TL/kg = 20000 kuruş`), [`client_storage_repository.dart:110`](../../packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L110), [`server.dart:1089`](../../test_spikes/spike_01_backend/bin/server.dart#L1089). | ✅ **EVET — Kuruş (`int`).** |
| **2. Miktar ölçeği `1000` mi?** | [`CartItemInput.scale = 1000`](../../packages/mms_client_storage/lib/src/models/cart_item_input.dart#L11) (`units` -> `count * 1000`; `fractional` -> `milliUnits`; `fromDecimalString` -> `(whole * 1000) + frac` 3 ondalık hane), [`ClientStorageRepository.quantityScale = 1000`](../../packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L10), [`server.dart:1132-1134`](../../test_spikes/spike_01_backend/bin/server.dart#L1132-L1134) (`scale=1000`). | ✅ **EVET — Ölçek `1000` (milli-birim).** |
| **3. Çarpımda integer taşma kontrolü var mı?** | [`client_storage_repository.dart:11, 114, 122, 135`](../../packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L11-L137): `_maxSafeInt = 9223372036854775807` ($2^{63}-1$); çarpım öncesi `unitPrice > 0 && item.quantity > (_maxSafeInt - 500) ~/ unitPrice`, birikim öncesi `calculatedTotalAmount > _maxSafeInt - itemTotal`, birim dönüşümü öncesi `num > 0 && item.quantity > _maxSafeInt ~/ num` kontrolleri `ArgumentError` fırlatır. [`CartItemInput:37`](../../packages/mms_client_storage/lib/src/models/cart_item_input.dart#L37) `units` için `count > maxQuantity ~/ scale` denetler (`maxQuantity = 10^9`). Sunucu [`server.dart:1065-1079, 1144, 1157`](../../test_spikes/spike_01_backend/bin/server.dart#L1065-L1079) aynı taşma + `100000000000` üst sınır kontrollerini uygular. | ✅ **EVET — Çarpım, toplama ve dönüşüm öncesinde korumalı.** *(Not: `fromDecimalString` içinde çok uzun string verilmesi ihtimaline karşı UI/domain tarafında basamak/üst sınır ön kontrolü ayrıca korunur.)* |
| **4. Half-Up sınır değerleri doğru mu?** | Hem istemci ([`client_storage_repository.dart:119`](../../packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L119)) hem backend ([`server.dart:1134`](../../test_spikes/spike_01_backend/bin/server.dart#L1134)):<br/>`((unitPrice * quantity) + 500) ~/ 1000` *(yalnız pozitif/sıfır tutarlarda)* | ✅ **EVET (`unitPrice >= 0`, `quantity > 0` için).** Kalan $r = (\text{unitPrice} \times \text{quantity}) \bmod 1000$ iken:<br/>• $r = 499$ (`0.499` kr) $\Rightarrow (499 + 500) \div 1000 = 0$ (aşağı)<br/>• $r = 500$ (`0.500` kr — **tam sınır**) $\Rightarrow (500 + 500) \div 1000 = +1$ (yukarı; örn. `unitPrice=150, qty=50 -> 8 kr`; `unitPrice=250, qty=10 -> 3 kr`, Banker's değil Half-Up!)<br/>• $r = 501$ (`0.501` kr) $\Rightarrow +1$ (yukarı)<br/>• Örnek: `12550 kr × 345 milli-birim` $\Rightarrow 4329750 + 500 \div 1000 = 4330\text{ kr} = 43.30\text{ TL}$. |
| **5. Floating-point (`double`) kullanılıyor mu?** | `CartItemInput`, `ClientStorageRepository.createOfflineSale`, `SaleTransactionItemResult` ve `server.dart` içinde **sıfır `double` / floating-point operasyonu** vardır. `fromDecimalString` saf string (`RegExp`, `padRight(3, '0')`, `int.parse`) ayrıştırır; tüm bölmeler `~/` tamsayı bölmesidir. | ✅ **HAYIR — %100 saf tamsayı (`int`) aritmetiği.** |
| **6. Negatif miktar ve negatif para değerleri nasıl ele alınıyor?** | • **Negatif/Sıfır Miktar:** [`CartItemInput`](../../packages/mms_client_storage/lib/src/models/cart_item_input.dart#L26, L36, L45, L61, L85) (`<= 0` veya `-` işareti) anında `ArgumentError` fırlatır; backend `400 ERR_INVALID_QUANTITY` döner (`server.dart:1065`).<br/>• **Negatif Para / `<= 0` Fiyat Boşluğu (Önemli Bulgu):** Backend `server.dart:966, 1068, 1071` `uPrice < 0`, `tPrice < 0` ve `totalAmount <= 0` durumlarını reddeder; ancak `client_storage_repository.dart:110` `product.price <= 0` denetimi **yapmamaktadır**! | ⚠️ **Miktar tam korumalı; `unitPrice <= 0` / `totalAmount == 0` koruması Faz 1.2 Domain katmanında zorunlu tutulmalıdır.** `unitPrice < 0` olursa negatif sayılarda `~/` sıfıra kesme nedeniyle Half-Up bozulur ve backend senkronizasyonu reddeder; `totalAmount == 0` da backend `ERR_INVALID_TOTAL_AMOUNT` ile Outbox'ta `FAILED_PERMANENT` doğurabilir. |

### 3.2. Sözleşme Uyumu Kanıtı
İstemci (`client_storage_repository.dart:119, 125`), yerel veritabanı (`LocalSaleItems` şeması), Outbox JSON yükü (`payloadItems['total_price']` + `outboxPayloadMap['total_amount']`) ve Windows Master Hub doğrulaması (`server.dart:1134-1147, 1182`) **birebir aynı formülü** (`((uPrice * qty) + 500) ~/ 1000` ve satırların toplamı `calculatedTotalAmount`) işletir. Dolayısıyla Faz 1.2 `domain` / `application` katmanının aynı formülü ve `unitPrice > 0 && totalAmount > 0` korumasını uygulaması hâlinde istemci–outbox–sunucu arasında **kuruş farkı (`ERR_ITEM_TOTAL_MISMATCH` / `ERR_TOTAL_AMOUNT_MISMATCH`) oluşması matematiksel olarak imkânsızdır**.

*(Ek Not: Mevcut `packages/mms_client_storage/test/s5a3_client_storage_test.dart` dosyasında `fromDecimalString` negatif/0 reddi ve `den` bölünememe testleri mevcutken; `0.500` alt kuruş tam sınır değeri ve `int64` overflow sınır değerleri için özel testler eksik olduğundan Faz 1.2 test süitine eklenmelidir.)*

---

## 4. UX Proposal Kapsam Sınırı (Faz 1.2 Disiplini)

Proje Sahibi talimatı doğrultusunda aşağıdaki maddeler **onaylanmamış `[UX PROPOSAL]`** statüsünde korunmakta olup **Faz 1.2 kapsamına kendiliğinden eklenmeyecektir**:
1. **`F3` — Ürün Arama kısayolu / ekranı** (`[UX PROPOSAL]`)
2. **`F8` / `Delete` — Seçili satır silme kısayolu** (`[UX PROPOSAL]`)
3. **Hızlı ürün tuşları paneli** (`[UX PROPOSAL]`)

**Faz 1.2'de Korunacak Onaylı Kısayol ve Girdi Çekirdeği (`main_shell_screen.dart:205-209`):**
- `F1`: Yardım
- `F2`: Miktar
- `F9`: Kart (`PaymentMethod.card` -> `'CARD'`)
- `F10`: Nakit (`PaymentMethod.cash` -> `'CASH'`)
- `Esc`: İptal / Modal Kapat
- Temel giriş: Fiziksel klavye + USB HID barkod okuyucu (ekran içi satır butonları $\ge 48\times 48\text{ dp}$); `OD-04` sanal numpad opsiyonel ve **varsayılan kapalı**; `OD-02` Parked Carts / `F4` **kapsam dışı**.

*(Yukarıdaki `[UX PROPOSAL]` kalemlerinden herhangi biri istenirse yalnızca Proje Sahibi'nin ayrı ve açık onayıyla sonradan dahil edilir.)*

---

## 5. R-01 – R-07 Risk Test Senaryoları

Faz 1.2 kodlaması sırasında `test-first` (TDD) disipliniyle yazılacak somut risk doğrulama senaryoları:

### `R-01`: Pasif Ürünün Sepete Eklenememesi (ve Çoklu Fallback Güvenliği)
- **Risk Kaynağı:** `ClientStorageRepository.getProductByBarcode` (`L294-307`) `LocalProducts.isActive` kontrolü yapmaz; `isActive` denetimi yalnız `createOfflineSale` (`L106`) içindedir.
- **Test Senaryosu (Unit + FFI SQLite Entegrasyon + Widget):**
  1. Yerel SQLite'ta `id: 'prod_pasif'`, `isActive: false`, aktif barkod `'8690009990001'` ve denormalize `barcode: '8690009990001'` kaydı oluştur.
  2. POS barkod ekleme use-case'ine `'8690009990001'` gönder.
  3. **Beklenen Sonuç:** Ürün sepete **kesinlikle eklenmez** (`CartState.items.isEmpty`), `createOfflineSale` hiç çağrılmaz, kullanıcıya *"Pasif ürün satışa eklenemez"* Türkçe uyarısı döner ve odak barkod alanında kalır. Pasif barkodu `local_product_barcodes` üzerinde `isActive = false` olan bir ürün de aynı şekilde bulunamaz/eklenemez (`OD-03`).

### `R-02`: Aynı Ürünün Tek Satırda Birleştirilmesi (`local_sale_items` PK Koruması)
- **Risk Kaynağı:** `createOfflineSale` (`L184, 199`) `itemId = 'citem_${saleTimestamp.microsecondsSinceEpoch}_${item.productId}'` üretir; aynı `productId` tek sepette 2 ayrı öğe olarak gönderilirse `UNIQUE constraint` hatası verir.
- **Test Senaryosu (Unit + FFI SQLite Entegrasyon):**
  1. Aktif `prod_ekmek` (`price: 1250`, `scale: 1000`) barkodunu 2 kez art arda ekle, ardından satır içi `+` ile miktarı `3` adede çıkar.
  2. **Beklenen Sonuç:** `CartState.items.length == 1`, tek satırda `quantity == 3000`, satır toplamı `3750` kr (`37.50 TL`).
  3. Satışı `createOfflineSale` ile tamamla -> transaction hatasız başarılı döner, `local_sale_items` tablosunda `1` satır ve `quantity == 3000` saklanır.

### `R-03`: Kesirli Miktar, Half-Up Sınır ve `den` Bölünebilirlik Doğrulaması
- **Risk Kaynağı:** `prodMilli % den != 0` (`L140`) satış onayında `ArgumentError` üretir; kesirli sınır değerleri (`0.500` alt kuruş) doğrudan test edilmelidir.
- **Test Senaryosu (Unit + FFI SQLite Entegrasyon):**
  1. **Sınır Testi (`OD-01`):** `unitPrice: 150`, `decimalText: '0.05'` (`qty: 50`) $\rightarrow$ `(150 * 50 + 500) ~/ 1000 == 8` kr; `unitPrice: 250`, `decimalText: '0.01'` (`qty: 10`) $\rightarrow$ `3` kr; `unitPrice: 12550`, `'0,345'` $\rightarrow$ `4330` kr (`43.30 TL`). Negatif (`'-1'`), sıfır (`'0'`, `'0.000'`) ve 4 basamaklı (`'1.2345'`) girişler `ArgumentError`/validasyon hatasıyla reddedilir.
  2. **Bölünebilirlik Kısıtı (`den > 1`):** `num: 1, den: 3` olan üründe miktar `'1'` (`1000` milli-birim; `1000 % 3 != 0`) girildiğinde daha sepet/miktar düzenleme anında reddedilir veya ödeme öncesi uyarılır; `createOfflineSale` entegrasyonunda `ArgumentError` atıldığında `local_sales` ve `outbox_operations` tablosunda **0 kayıt** kaldığı (tam rollback) doğrulanır.

### `R-04`: Ödeme Yönteminin Doğru Persistence ve Outbox Payload Değeri
- **Risk Kaynağı:** `CARD` vs `CREDIT_CARD` vs `NAKIT` çelişkisi.
- **Test Senaryosu (Unit + FFI SQLite Entegrasyon + Widget):**
  1. Sepette `prod_su` (`500` kr) varken `F10` (Nakit) ile `receivedCents = 1000` girerek satışı tamamla (`BR-PAY-03`: önce `receivedCents = 400` iken onay butonunun kilitli olduğunu doğrula!).
  2. Sepette aynı ürünle `F9` (Kart) seçerek kart satışını tamamla.
  3. **Beklenen Sonuç:**
     - `local_sales`: 1. kayıtta `payment_method == 'CASH'`, 2. kayıtta `payment_method == 'CARD'`.
     - `outbox_operations`: 1. kaydın `jsonDecode(op.payload)['payment_method'] == 'CASH'`, 2. kaydın `'CARD'` olduğu; `computeSaleRequestHash(jsonDecode(op.payload)) == op.payloadHash` eşitliğinin sağlandığı doğrulanır. `'CREDIT_CARD'` veya `'NAKIT'` kesinlikle yazılmaz.

### `R-05`: Kasa Sekmesi ve Diagnostics Erişimi (`MainShellScreen` Bütünlüğü)
- **Risk Kaynağı:** `main_shell_screen_test.dart:79-82` mevcut testte açılışta index `3` (`Sistem Durumu ve Altyapı Tanılama`) bekler.
- **Test Senaryosu (Widget — `MainShellScreen` + `ProviderScope`):**
  1. `1280×720` masaüstü boyutunda `MarketPosApp` / `MainShellScreen` başlatılır.
  2. Varsayılan sekme (`Kasa (Satış)` — index `0`) aktifken POS arayüzü (`Barkod` alanı, sepet, Nakit/Kart ödeme butonları $\ge 48\times 48\text{ dp}$, `OD-04` numpad varsayılan gizli, `F4` Parked Carts yok) render edilir; alt kısayol çubuğunda yalnızca `F1`, `F2`, `F9`, `F10`, `Esc` yer alır (`F3`/`F8`/`F4` yoktur).
  3. `Sistem & Tanı` (index `3`) sekmesine tıklandığında `Sistem Durumu ve Altyapı Tanılama`, Hub ve `client_local.db` kartlarının eksiksiz açıldığı ve `Ürünler` / `Raporlar` placeholder sekmelerinin MVP dışı metinlerden temizlenmiş olduğu doğrulanır.

### `R-06`: Barkod Okuyucu `Enter` Karakterinin Ödeme Onayını Tetiklememesi
- **Risk Kaynağı:** USB HID okuyucu rakam + `Enter` dizisi gönderir; modal veya ödeme penceresi açıkken `Enter` sızması erken/hatalı satış tamamlamaya yol açabilir.
- **Test Senaryosu (Widget — Klavye & Focus Etkileşim Testi):**
  1. Sepete ürün ekle ve `F10` ile **Nakit Ödeme Modalını** aç.
  2. Modal açıkken barkod/USB HID hızlı tuş dizisi (`'8','6','9','0','0','0','1'` + `LogicalKeyboardKey.enter`) simüle et; alınan tutar alanı boş/eksikken ve yeterliyken test et.
  3. **Beklenen Sonuç:**
     - Barkod alanı modal açıkken arka planda yeni ürün EKLEMEZ (`CartState.items` değişmez).
     - Ödeme modalında yalnızca kullanıcı odağı açık onay butonunda olmadıkça veya tutar eksikse (`received < total`) `Enter` satışı tamamlamaz (`local_sales` sayısı `0` kalır).
     - `Esc` tuşuna basıldığında modal kapanır, satış oluşmaz ve odak tekrar POS barkod alanına döner.

### `R-07`: Cihaz Kimliğinin Satış ve Outbox İşlemlerinde Tutarlı Kalması
- **Risk Kaynağı:** Faz 1.2 sabit `AppConstants.defaultDeviceId` (`'POS-WIN-01'`) ile çalışan çoklu satış ve yeniden başlatma senaryolarında `client_seq` ve `device_id` kayması.
- **Test Senaryosu (FFI SQLite Entegrasyon + Restart Yaşam Döngüsü):**
  1. `apiClientProvider` (`deviceId: AppConstants.defaultDeviceId`) ve dosya tabanlı gerçek `LocalDatabaseService` ile art arda 2 satış (`CASH`, `CARD`) yap.
  2. `LocalDatabaseService`'i kapat (`close()`), aynı `.db` dosyasıyla yeniden başlat ve 3. satışı yap.
  3. **Beklenen Sonuç:**
     - `CashierHeaderBar` / `SystemStatus.deviceId` == `'POS-WIN-01'`.
     - `client_sync_states`: tek satır (`device_id == 'POS-WIN-01'`, `current_client_seq == 3`).
     - `local_sales` ve `outbox_operations`: 3 kaydın tamamında `device_id == 'POS-WIN-01'`, `client_seq` kesin olarak `1, 2, 3`, durum `'PENDING'` ve FIFO `getUnsyncedOutboxOperations('POS-WIN-01')` sırası `1 -> 2 -> 3`.

---

## 6. Engelleyici Konular (Blockers & Kısıt Özeti)

1. **`BLOCKING` — `PaymentMethod` Sözleşme Kararı Onayı (`CARD` vs `CREDIT_CARD`):**
   - Bölüm 1'de kanıtlandığı üzere kanonik `DATA_MODEL.md` (`'CARD'`) ile `client_database.dart:56` yorumu + 3 eski test dosyası (`'CREDIT_CARD'`) arasında aktif çelişki vardır.
   - Faz 1.2'de yazılacak her satış `outbox_operations` payload'ı ve SHA-256 hash'ine değişmez biçimde işleneceğinden, Proje Sahibi'nin **kanonik `'CASH'` / `'CARD'` standardını onaylaması** Faz 1.2 kodlaması öncesi **tek teknik BLOCKING maddedir**.
2. **Blocker Olmayan Ancak Açık Korunan Konular:**
   - **Device ID Dinamik Eşleştirme:** Blocker DEĞİLDİR; Faz 2 kapsamına bırakılmıştır.
   - **UX Proposals (`F3`, `F8`/`Del`, Hızlı Ürün Tuşları):** Blocker DEĞİLDİR; onaylanmamış öneri olarak Faz 1.2 dışı korunur (yalnız ek onay verilirse kapsam alınır).
   - **Diğer Faz/Pilot Borçları (`B-2`, `B-3`, `SCM`, `ACL`, `T-09`/`T-11`/`T-12`):** Faz 1.2 yerel kasa akışını bloklamaz; Faz 2–7 aşamalarında uygulanır.

---

## 7. Faz 1.2'ye Başlamak İçin Nihai Öneri

1. **Proje Sahibi'nin Ön Kontrol Onayı:**
   - `PaymentMethod` için kanonik **`'CASH'`** ve **`'CARD'`** sözleşmesini onaylamak *(ve mevcut 3 `CREDIT_CARD` / 4 `NAKIT` test örneği ile `client_database.dart:56` yorumu / `server.dart:995` validator hizalamasına yetki vermek)*.
   - `AppConstants.defaultDeviceId` (`'POS-WIN-01'`) kullanımının Faz 2'ye devredilmesini onaylamak.
   - `F3`, `F8/Del` ve Hızlı Ürün Tuşları olmadan, yalnız onaylı **`F1 / F2 / F9 / F10 / Esc`**, barkod okuma, yerel ürün seçimi, `OD-01` Half-Up, `OD-03` offline bilinmeyen barkod engeli ve `OD-04` varsayılan kapalı opsiyonel sanal numpad kapsamıyla ilerlemeyi teyit etmek.
2. **Faz 1.2 Başlatma Talimatı:** Yukarıdaki onaylarla birlikte Proje Sahibi'nin açık **"Faz 1.2 kodlamasına başla"** talimatını vermesi hâlinde `test-first` (TDD) disipliniyle Bölüm 5'teki `R-01`–`R-07` testlerinden başlanarak uygulama geliştirme sürecine geçilebilir.
3. **Git Hijyeni (Tercihe Bağlı):** Kodlama öncesi mevcut dokümantasyon/UI-UX değişiklikleri için dosya bazlı `git add` / `commit` talimatı verilebilir.

