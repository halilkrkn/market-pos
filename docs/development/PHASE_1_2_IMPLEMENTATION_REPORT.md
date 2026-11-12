# MARKET MMS — Faz 1.2 POS Uygulama Geliştirme Raporu

**Belge Kodu:** `docs/development/PHASE_1_2_IMPLEMENTATION_REPORT.md`  
**Tarih:** 12 Kasım 2026  
**Aşama:** Faz 1.2 — Kasa Satış Ekranı (POS), Sepet Yönetimi & Ödeme Akışı  
**Yöntem:** Sıkı Test-First (TDD Red-Green-Refactor) & Clean Architecture  
**Durum:** **GELİŞTİRME VE OTOMATİK DOĞRULAMALAR TAMAMLANDI — PROJE SAHİBİ İNCELEMESİ VE KABULÜ BEKLENİYOR**  

> [!IMPORTANT]
> **Yönetişim Sınırı (`AGENTS.md` §12–15):**  
> Bu rapor Faz 1.2 uygulama geliştirmesinin teknik çıktısını ve fiilen çalıştırılan test/analiz sonuçlarını sunar. Faz kabulü yapay zekâ tarafından ilan edilmez; onay ve kabul yetkisi yalnızca Proje Sahibine aittir. Veritabanı şeması/migration'ı değiştirilmemiş, `pubspec.yaml`'e yeni bağımlılık eklenmemiş ve hiçbir `git add`, `git commit` veya `git push` çalıştırılmamıştır.

---

## 1. Tamamlanan İşler

Faz 1.2 geliştirmesi `test-first` yaklaşımıyla küçük ve doğrulanabilir adımlar hâlinde yürütülerek tamamlanmıştır:

1. **Domain Katmanı (`lib/features/pos/domain/` — Saf Dart, Sıfır Flutter/Drift/HTTP Bağımlılığı):**
   - **`Money` ([`money.dart`](../../lib/features/pos/domain/money.dart)):** Kuruş bazlı tamsayı (`int`) hesaplama, `OD-01` **Half-Up** yuvarlama (`((unitPriceCents * quantityMilli) + 500) ~/ 1000`), `int64` çarpım/toplama taşma korumaları, `12.50 TL` / `1,250.00 TL` biçimlendirme ve floating-point (`double`) kullanmadan sıkı TL/milli-birim (ölçek `1000`, en fazla 3 ondalık hane) metin ayrıştırıcıları.
   - **`PosProduct` & `CartItem` & Immutable `CartState` ([`pos_product.dart`](../../lib/features/pos/domain/pos_product.dart), [`cart_item.dart`](../../lib/features/pos/domain/cart_item.dart), [`cart_state.dart`](../../lib/features/pos/domain/cart_state.dart)):** Değişmez (`List.unmodifiable`) sepet durumu, aynı `productId` okutulduğunda tek satırda birleştirme (`BR-POS-02`), pasif ürün reddi (`BR-PROD-03`, `R-01`), rasyonel birim dönüşüm payda (`conversionFactorDenominator`) bölünebilirlik doğrulaması (`R-03`), miktar `0` girildiğinde satır silme, `0.00 TL` satış önleme (`hasPayableItems`) ve eksi stok (`allow` — `INV-04`) uyarı bayrakları.
   - **`PosRepository` & Kanonik `PaymentMethod` ([`pos_repository.dart`](../../lib/features/pos/domain/pos_repository.dart)):** Pure-Dart [`payment_method.dart`](../../packages/mms_client_storage/lib/payment_method.dart) üzerinden yalnızca kanonik `PaymentMethod.cash` (`'CASH'`) ve `PaymentMethod.card` (`'CARD'`) sözleşmesi; `OD-03` çevrimdışı bilinmeyen barkod ve pasif ürün ayrımlı `BarcodeLookupResult` sözleşmesi.

2. **Application Katmanı (`lib/features/pos/application/`):**
   - **`PosPreferencesNotifier` ([`pos_preferences_notifier.dart`](../../lib/features/pos/application/pos_preferences_notifier.dart)):** `OD-04` uyumlu opsiyonel sanal numpad görünürlük yönetimi (**varsayılan `showVirtualNumpad = false`**).
   - **`CartNotifier` ([`cart_notifier.dart`](../../lib/features/pos/application/cart_notifier.dart)):** Barkod okutma, yerel ürün ekleme, `+` / `-` / satır silme / `F2` miktar güncelleme, `CASH` (`cashReceivedCents >= totalCents`) ve `CARD` (`externalPosConfirmed == true` ve nakitsiz) doğrulamaları, hata durumunda sepeti koruyup anlaşılır Türkçe mesaj üretme ve satış sonrası [`SystemStatusNotifier`](../../lib/features/diagnostics/application/system_status_notifier.dart) yenileme tetiklemesi.

3. **Data Katmanı (`lib/features/pos/data/` & DI Kompozisyonu):**
   - **`LocalPosRepository` ([`local_pos_repository.dart`](../../lib/features/pos/data/local_pos_repository.dart)):** [`LocalDatabaseService.runOperation`](../../lib/core/storage/local_database_service.dart#L226) drain takip sarmalayıcısı altında çalışan barkod sorgusu (`local_product_barcodes` üzerinde pasifleştirilmiş barkodların `local_products.barcode` fallback'ından sızmasını önleyen kontrol + `R-01` pasif ürün tespiti) ve yerel aktif ürün isim/barkod araması (`searchActiveProducts`).
   - **Atomik Satış Entegrasyonu:** Satış onayında [`LocalDatabaseService.repository.createOfflineSale`](../../lib/core/storage/local_database_service.dart#L436-L450) çağrısıyla tek SQLite transaction içinde `local_sales`, `local_sale_items` (satış anı fiyat/ad/birim snapshot'ı), `local_stock_movements` (`SATIS`), `local_products` stok düşümü (`allow` eksi stok destekli), `client_sync_states.currentClientSeq` artışı ve `outbox_operations` (`PENDING` + SHA-256 `payloadHash`) yazımı.
   - **[`pos_providers.dart`](../../lib/features/pos/pos_providers.dart):** `deviceId` bilgisini doğrudan `apiClientProvider` (`R-07` tek kaynak) üzerinden okuyan ve satış sonrasında `systemStatusProvider` yenileyen Riverpod kompozisyon katmanı.

4. **Presentation & Shell Entegrasyonu (`lib/features/pos/presentation/` & `MainShellScreen`):**
   - **[`PosScreen`](../../lib/features/pos/presentation/screens/pos_screen.dart), [`CartItemRow`](../../lib/features/pos/presentation/widgets/cart_item_row.dart), [`VirtualNumpadPanel`](../../lib/features/pos/presentation/widgets/virtual_numpad_panel.dart):** USB HID keyboard-wedge barkod odak yönetimi (modal açıkken arka plan odağını `canRequestFocus = false` ile kilitleyip kapanışta barkoda döndürme), $\ge 48\times 48\text{ dp}$ tüm etkileşimli hedefler, `AppTheme.tabularFiguresFeature` ile `12.50 TL` dikey hizalama, eksi stok (`allow`) uyarı rozeti, `OD-04` varsayılan kapalı sanal numpad ve onaylı sepet temizleme diyaloğu.
   - **[`ProductSearchDialog`](../../lib/features/pos/presentation/widgets/product_search_dialog.dart), [`QuantityEditDialog`](../../lib/features/pos/presentation/widgets/quantity_edit_dialog.dart), [`HelpShortcutsDialog`](../../lib/features/pos/presentation/widgets/help_shortcuts_dialog.dart), [`PaymentDialog`](../../lib/features/pos/presentation/widgets/payment_dialog.dart):**
     - Yerel katalog isim/barkod arama ve `OD-03` offline bilgilendirmesi.
     - `F2` ile kesirli (3 ondalık hane, milli ölçek `1000`) ve `0` ile satır silen miktar düzenleme modalı.
     - `F10` Nakit (hızlı banknotlar, anlık kuruş para üstü, eksik tutarda kilitli onay butonu) ve `F9` Kredi Kartı (harici POS terminaline tutarın elle girildiğine dair zorunlu onay kutusu), `Esc` ile iptal ve `R-06` Enter koruması.
     - `F1` onaylı kısayollar yardım penceresi (`F1/F2/F9/F10/Esc`).
   - **[`MainShellScreen`](../../lib/features/shell/presentation/screens/main_shell_screen.dart) & [`AppTheme`](../../lib/core/theme/app_theme.dart):** Varsayılan açılış sekmesi `0` (`Kasa (Satış)`) yapıldı; `case 1` / `case 2` placeholder açıklamalarındaki MVP dışı (*stok sayımı*, *Z-Raporu, KDV dökümü*) kalıntıları kanonik MVP kapsamına göre temizlendi; `AppTheme` içine paralel tema sınıfı açılmadan POS yüksek kontrast sabitleri eklendi.

---

## 2. Değiştirilen ve Oluşturulan Dosyalar

### 2.1 Değiştirilen Mevcut Dosyalar (`3` dosya)
- [`lib/core/theme/app_theme.dart`](../../lib/core/theme/app_theme.dart) — Mevcut `AppTheme` korunarak semantik POS aksiyon/uyarı renk sabitleri eklendi.
- [`lib/features/shell/presentation/screens/main_shell_screen.dart`](../../lib/features/shell/presentation/screens/main_shell_screen.dart) — Başlangıç sekmesi `0` (`PosScreen`) yapıldı ve placeholder metinleri MVP kapsamıyla uyumlu hâle getirildi.
- [`test/features/shell/main_shell_screen_test.dart`](../../test/features/shell/main_shell_screen_test.dart) — `R-05` gereği açılış POS kontrolü, `Sistem & Tanı` geçişi ve temizlenen placeholder doğrulamaları güncellendi.

### 2.2 Yeni Oluşturulan Uygulama ve Test Dosyaları (`21` kod/test dosyası + bu rapor)

**Uygulama Kaynak Dosyaları (`17` dosya):**
- `lib/features/pos/domain/pos_exceptions.dart`
- `lib/features/pos/domain/money.dart`
- `lib/features/pos/domain/pos_product.dart`
- `lib/features/pos/domain/cart_item.dart`
- `lib/features/pos/domain/cart_state.dart`
- `lib/features/pos/domain/pos_repository.dart`
- `lib/features/pos/application/pos_preferences_notifier.dart`
- `lib/features/pos/application/cart_notifier.dart`
- `lib/features/pos/data/local_pos_repository.dart`
- `lib/features/pos/pos_providers.dart`
- `lib/features/pos/presentation/screens/pos_screen.dart`
- `lib/features/pos/presentation/widgets/cart_item_row.dart`
- `lib/features/pos/presentation/widgets/virtual_numpad_panel.dart`
- `lib/features/pos/presentation/widgets/product_search_dialog.dart`
- `lib/features/pos/presentation/widgets/quantity_edit_dialog.dart`
- `lib/features/pos/presentation/widgets/help_shortcuts_dialog.dart`
- `lib/features/pos/presentation/widgets/payment_dialog.dart`

**Otomatik Test Dosyaları (`4` dosya):**
- `test/features/pos/domain/money_and_cart_test.dart`
- `test/features/pos/application/pos_notifiers_test.dart`
- `test/features/pos/data/local_pos_repository_test.dart`
- `test/features/pos/presentation/pos_screen_test.dart`

**Dokümantasyon:**
- `docs/development/PHASE_1_2_IMPLEMENTATION_REPORT.md` *(bu rapor)*

---

## 3. Mimari Kararlar ve Gerçek Kod Doğrulamaları

1. **Tek Kanonik `PaymentMethod` & Saf Dart Domain İzolasyonu:** `lib/features/pos/domain/` yalnızca pure-Dart [`package:mms_client_storage/payment_method.dart`](../../packages/mms_client_storage/lib/payment_method.dart) modülünü kullanır; `flutter`, `drift`, `http` veya tam `mms_client_storage.dart` importu bulunmamaktadır.
2. **`hasPayableItems` vs `canCheckout` Ayrımı (Entegrasyon Bulgusu):** `CartNotifier.completeSale` işlem sürerken `isProcessing: true` durumuna geçtiğinden, `LocalPosRepository.completeOfflineSale` içinde `canCheckout` (`!isProcessing && hasPayableItems`) yerine `hasPayableItems` (`items.isNotEmpty && totalCents > 0 && totalCents <= Money.maxTotalCents`) doğrulanmıştır. Bu ayrıca backend `server.dart` (`total_amount > 0`) sözleşmesiyle tam uyum sağlar.
3. **Deaktive Barkod Sızma Koruması (`R-01`):** `ClientStorageRepository.getProductByBarcode` üzerindeki `LocalProducts.barcode` fallback'ı pasifleştirilmiş barkodları ve pasif ürünleri döndürebildiği için `LocalPosRepository.findByBarcode` önce `localProductBarcodes` üzerinde pasiflik kontrolü yapar ve `product.isActive` durumunu zorunlu kılar; tüm sorgular `LocalDatabaseService.runOperation(...)` drain sayacı içinden geçirilir.
4. **Tek Kaynaklı `deviceId` (`R-07`) & Modal Odak Kilidi (`R-06`):** `cartProvider` cihaz kimliğini doğrudan `apiClientProvider.deviceId` üzerinden alır (ikinci bir hardcoded sabit yoktur). Herhangi bir modal açıkken `_barcodeFocusNode.canRequestFocus = false` yapılarak arka plan barkod okuyucu sızması engellenir ve ödeme diyalogu içinde `TextField.onSubmitted` tek başına satış tamamlamayı tetiklemez.
5. **Sıfır Şema / Bağımlılık Değişikliği:** Mevcut Drift `schemaVersion = 1` ve `pubspec.yaml` korunmuştur.

---

## 4. Test Senaryoları ve Sonuçları (TDD & Gerçek Çıktılar)

Tüm yeni iş kuralları önce başarısız test (RED) yazılarak geliştirilmiş, ardından tüm monorepo testleri yeniden çalıştırılmıştır:

| Kapsam / Süit | Çalıştırılan Komut | Sonuç |
|---|---|---|
| **Kök Flutter Uygulaması (`market-pos`)** | `flutter test` | **59 / 59 PASS** (`0` hata, `0` atlanan) — Mevcut 34 test + `money_and_cart_test.dart` (12), `pos_notifiers_test.dart` (4), `local_pos_repository_test.dart` (4 — gerçek dosya tabanlı FFI SQLite WAL), `pos_screen_test.dart` (5 — gerçek dosya tabanlı FFI SQLite WAL + klavye/odak) |
| **`packages/mms_client_storage`** | `dart test` | **57 / 57 PASS** |
| **`test_spikes/spike_01_backend`** | `dart test` | **144 / 144 PASS** |
| **Toplam Doğrulama** | Tüm 3 hedef | **260 / 260 Test %100 Yeşil** |

**Öne Çıkan Doğrulanmış Senaryolar:**
- `OD-01`: `150 * 50 -> 8 kr`, `250 * 10 -> 3 kr`, `12550 * 345 -> 4330 kr (43.30 TL)`, `double` aritmetik yokluğu (statik tarama ile `0` float para kullanımı doğrulandı), sıkı lira ayrıştırıcı (`"12.345"`, negatif, hatalı binlik reddi).
- `OD-02` & Kısayol Sınırı: Ekranda Parked Carts, `F3`, `F4`, `F8`, `Delete` ve hızlı ürün tuşları gridi bulunmadığı widget testiyle doğrulandı.
- `OD-03`: Bilinmeyen barkodun offline eklenmediği ve yeni ürün oluşturmadığı; yalnızca yerel aktif katalogdan seçim yapılabildiği doğrulandı.
- `OD-04`: Sanal numpad'in başlangıçta kapalı (`false`) olduğu ve toggle ile $\ge 48\times 48\text{ dp}$ olarak açıldığı doğrulandı.
- `R-01..R-07`: Pasif ürün reddi, aynı `productId` birleştirme, `den` bölünememe ve rollback, `CASH` / `CARD` Outbox `PENDING` JSON + SHA-256 `payloadHash` eşleşmesi, `MainShellScreen` sekmeleri/temiz placeholder'ları, `R-06` modal Enter koruması, `close()` + reopen sonrasında `client_seq` (`1 -> 2`) sürekliliği ve `Bekleyen Outbox` sayaç güncellemesi gerçek FFI SQLite WAL üzerinde doğrulandı.

---

## 5. Statik Analiz (Analyze) Sonuçları

| Hedef | Komut | Çıktı |
|---|---|---|
| **Kök Flutter Uygulaması** | `flutter analyze --no-pub` | `No issues found! (ran in 3.0s)` |
| **`packages/mms_client_storage`** | `dart analyze` | `No issues found!` |
| **`test_spikes/spike_01_backend`** | `dart analyze` | `No issues found!` |

---

## 6. Açık Kalan İşler ve Riskler

1. **Gerçek Donanım ve Platform Derlemesi (Faz 1.2 Sonrası Fiziksel Doğrulama):** Otomatik widget/FFI testleri klavye/barkod akışını simüle ederek doğrulamıştır; gerçek Windows USB HID barkod okuyucu donanım saha testi ve `flutter build windows --release` paket derlemesi fiziksel ortamda ayrıca doğrulanmalıdır.
2. **Faz 2+ Güvenlik ve Eşleştirme Bağımlılıkları:** `deviceId` şimdilik `apiClientProvider` (`AppConstants.defaultDeviceId` = `'POS-WIN-01'`) üzerinden tek noktadan okunmaktadır; gerçek cihaz kaydı, `B-2` (Root CA pinning), `B-3` (DPAPI / Keystore / Keychain) ve `SCM`/`ACL` doğrulamaları sonraki fazlarda/pilot öncesinde tamamlanacaktır.
3. **Faz 5 Sync Worker ile Uçtan Uca Canlı Aktarım:** Faz 1.2 yerel satışları `outbox_operations` tablosuna `PENDING` ve SHA-256 hash'li olarak yazar; arka plan Outbox sync worker'ı Faz 5 kapsamında devreye alınacaktır.
4. **Proje Durum Dokümanı Güncellemesi:** Faz kabulü Proje Sahibi tarafından onaylandıktan sonra `docs/PROJECT_STATUS.md` ve gerekiyorsa `git add <explicit-paths>` işlemleri ayrı onaylı adımda yürütülmelidir.

---

## 7. Faz 1.2 Kapsam Dışı Bırakılan Konular

- `OD-02` Parked Carts (Sepeti Askıya Alma / `F4`).
- Onaylanmamış `[UX PROPOSAL]` öğeleri (`F3`, `F8`, `Delete`, hızlı ürün tuşları paneli).
- Banka POS cihazı doğrudan tutar gönderme / mali yazarkasa entegrasyonu (`INV-05`).
- Ürün ve kategori CRUD, fiyat düzenleme, Excel/CSV aktarım (Faz 3).
- Satış geçmişi, tam fiş iptali, kısmi iade (`W-10`/`W-11` — Faz 4).
- Arka plan Outbox Sync Worker ve çakışma çözümü (Faz 5).
- Fiziksel stok sayımı (`BR-STK-04..10`), KDV dökümü, Z-Raporu (`OUT_OF_SCOPE`).
- QR cihaz eşleştirme, veritabanı şeması/migration değişikliği ve yeni `pubspec.yaml` bağımlılığı ekleme.
- Git `add`, `commit` ve `push` işlemleri.
