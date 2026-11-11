# Faz 1.2 Hazırlık Raporu — Kasa Satış Ekranı & Sepet Yönetimi
# MARKET MANAGEMENT SYSTEM (MARKET MMS)

**Belge Kodu:** `PHASE_1_2_PREPARATION_REPORT.md`  
**Tarih:** 11 Kasım 2026  
**Aşama:** Faz 1.2 Ön Hazırlık ve Kapsam Doğrulama (Kodlama Henüz Başlatılmadı)  
**Hazırlayan:** Antigravity (Gemini)  
**Karar ve Başlatma Mercii:** Proje Sahibi  
**Bağlayıcı Anayasa & Kaynaklar:** [`AGENTS.md`](../../AGENTS.md), [`GEMINI.md`](../../GEMINI.md), [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](../../MARKET_POS_AI_STUDIO_BUILD_PLANI.md) (v1.4), [`BUSINESS_RULES_SPEC.md`](../requirements/BUSINESS_RULES_SPEC.md) (v1.4), [`DESIGN_DECISIONS.md`](../ui-ux/DESIGN_DECISIONS.md) (v1.3), [`UX_07_FLUTTER_HANDOFF.md`](../ui-ux/UX_07_FLUTTER_HANDOFF.md) (v1.3)

> [!IMPORTANT]
> **Yönetişim Sınırı (`AGENTS.md` §12–15):**  
> Bu belge Faz 1.2 (Kasa Satış Ekranı & Sepet Yönetimi) öncesinde kesinleşen Proje Sahibi kararlarına göre kapsamı, bağımlılıkları, teknik riskleri ve TDD test stratejisini raporlar. `lib/`, `test/`, `pubspec.yaml`, backend ve veritabanı dosyalarında **hiçbir değişiklik yapılmamış**, Git staging/commit/push çalıştırılmamıştır. Faz 1.2 kodlamasına **yalnızca Proje Sahibi'nin açık başlatma onayından sonra** geçilecektir.

---

## 1. Kesinleşen Kararlar (11 Kasım 2026 — UX Kabulü & Karar Kapanışı)

Proje Sahibi **11 Kasım 2026** tarihinde `docs/ui-ux/` UI/UX teslimatını **kabul etmiş** (`KABUL EDİLDİ`) ve önceki aşamalarda açık kalan `OD-01`..`OD-04` maddelerini mevcut karar kimlikleri ve tarihçesi korunarak aşağıdaki şekilde kesinleştirmiştir:

| Karar ID | Konu | Kesinleşen Karar (`11 Kasım 2026`) | Kanonik Yansıması |
|---|---|---|---|
| **`OD-01`** | **Alt Kuruş Yuvarlama** (`BR-PROD-07`) | **Half-Up** yuvarlama uygulanacaktır (`((unitPrice * quantity) + 500) ~/ 1000`). Para hesaplamalarında floating-point (`double`) aritmetik kesinlikle yasaktır; hesaplama integer/decimal tabanlı güvenli yöntemle yapılır. İç parasal veri `int` kuruş olarak tutulur ve gösterim standardı **`12.50 TL`** olarak korunur. | [`DESIGN_DECISIONS.md`](../ui-ux/DESIGN_DECISIONS.md) v1.3, [`BUSINESS_RULES_SPEC.md`](../requirements/BUSINESS_RULES_SPEC.md) v1.4, [`REQUIREMENTS.md`](../REQUIREMENTS.md) v1.2 |
| **`OD-02`** | **Parked Carts / Sepeti Askıya Alma** (`BR-POS-05`) | **`[OUT_OF_SCOPE]` — MVP kapsamı dışındadır.** Gelecek sürümlerde yeniden değerlendirilebilir. MVP ekranlarında, navigasyon haritasında (`F4`) veya Faz 1.2 kodlamasında onaylanmış özellik gibi sunulmayacaktır. | [`BUSINESS_RULES_SPEC.md`](../requirements/BUSINESS_RULES_SPEC.md) `BR-POS-05`, [`UX_02`](../ui-ux/UX_02_INFORMATION_ARCHITECTURE.md), [`UX_04`](../ui-ux/UX_04_SCREEN_DESIGNS.md), [`UX_05`](../ui-ux/UX_05_INTERACTIVE_PROTOTYPE.md) |
| **`OD-03`** | **Offline Bilinmeyen Barkod** (`BR-PROD-05`, `BR-SYNC-04`) | Yerel veritabanında (`client_local.db` / `mms_client.db`) bulunmayan ürün **offline olarak oluşturulamaz** ve bilinmeyen barkod **offline satış sepetine eklenemez** (geçici/tanımsız ürün satırı ekleme yasaktır). Yeni ürün oluşturma işlemi **Master Hub bağlantısı gerektirir**. Yerel veritabanında zaten bulunan ürünler offline ortamda satılabilir (`INV-10`). | [`BUSINESS_RULES_SPEC.md`](../requirements/BUSINESS_RULES_SPEC.md) `BR-PROD-05` & `BR-SYNC-04`, [`UX_05`](../ui-ux/UX_05_INTERACTIVE_PROTOTYPE.md), [`UX_07`](../ui-ux/UX_07_FLUTTER_HANDOFF.md) |
| **`OD-04`** | **Masaüstü Sanal Numpad** | **Opsiyonel bir özelliktir ve varsayılan olarak kapalıdır.** Fiziksel klavye ve USB HID barkod okuyucu temel kullanım yöntemidir; kullanıcı isterse ayar/görünüm anahtarı üzerinden açabilir. | [`DESIGN_DECISIONS.md`](../ui-ux/DESIGN_DECISIONS.md), [`win-02-pos.html`](../ui-ux/visual-designs/win-02-pos.html), [`UX_04`](../ui-ux/UX_04_SCREEN_DESIGNS.md), [`UX_06`](../ui-ux/UX_06_USABILITY_VALIDATION.md) |

### Korunan Değişmez Mimari Kararlar (`AGENTS.md` & `DESIGN_DECISIONS.md`)
- **Clean Architecture & Saf Dart Domain:** `presentation -> application -> domain <- data <- infrastructure`; `domain` katmanında Flutter, Drift veya HTTP importu yasaktır.
- **Dual SQLite İzolasyonu (`INV-02`):** Windows Flutter UI `market_master.db` dosyasına hiçbir koşulda doğrudan erişemez; yalnızca `LocalDatabaseService` üzerinden `client_local.db` ve loopback API ile çalışır.
- **Tek Tema Kaynağı & Ergonomi:** [`AppTheme`](../../lib/core/theme/app_theme.dart) tek yetkili tema kaynağıdır (`tabularFiguresFeature`, `Size(64, 52)` taban, kritik dokunmatik hedefler $\ge 48\times 48\text{ logical pixel (dp)}$).
- **Tek Ödeme Yöntemi & Donanım Sınırı (`INV-05`, `INV-08`):** Yalnızca Nakit (`CASH`) veya Kredi Kartı; parçalı ödeme ve banka POS cihazına otomatik tutar gönderme yoktur.
- **Eksi Stok (`allow` — `INV-04`) & Append-Only Satış (`INV-03`):** Eksi stok satışa engel değildir (uyarı rozeti verilir); tamamlanmış satışlar silinemez.
- **Fiziksel Stok Sayımı (`BR-STK-04..10`), KDV Hesaplama & Z-Raporu:** MVP kapsamı dışındadır (`OUT_OF_SCOPE`).

---

## 2. Faz 1.2 Kapsamı (`OD-01`..`OD-04` Sonrası Yeniden Kontrol Edilmiş Kapsam)

Kesinleşen kararlar ışığında Faz 1.2'nin kapsamı aşağıdaki şekilde netleştirilmiştir:

### 2.1. Kapsama Dahil Olan İş Paketleri (In Scope)

1. **POS Özellik Modülü İskeleti (`lib/features/pos/`):**
   - `domain/`: Saf Dart `CartItem`, `CartState` (değişmez/immutable), `Money` / kuruş hesaplama-formatlama yardımcıları (Half-Up `((unitPrice * quantity) + 500) ~/ 1000`, `12.50 TL` biçimlendirme), ürün arama / satış tamamlama repository portları.
   - `application/`: Riverpod tabanlı `CartNotifier` / `PosPreferencesNotifier` (sanal numpad opsiyonel görünürlük durumu — varsayılan `false`).
   - `data/`: [`LocalDatabaseService`](../../lib/core/storage/local_database_service.dart) ve [`ClientStorageRepository`](../../packages/mms_client_storage/lib/src/database/client_storage_repository.dart) üzerine kurulu somut adaptörler.
   - `presentation/`: `MainShellScreen` içindeki Kasa sekmesi (`case 0`) için Windows masaüstü POS ekranı, ödeme modalı, yerel ürün arama diyalogu ve kısayol yardım penceresi (`F1`).
2. **Barkod Okuma ve Yerel Ürün Arama (`OD-03` Uyumlu):**
   - Fiziksel klavye ve USB HID barkod okuyucu için context-aware `FocusNode` odak yönetimi (modal kapalıyken barkod alanında hazır kalır, kullanıcı aktif başka input'ta iken zorla çalmaz).
   - [`ClientStorageRepository.getProductByBarcode`](../../packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L294-L307) ile birincil ve alternatif barkodlar (`LocalProductBarcodes` + `LocalProducts`) üzerinden ürün sorgulama; `!product.isActive` (pasif ürün) engeli.
   - **Bilinmeyen Barkod Davranışı (`OD-03`):** Yerel katalogda bulunamayan barkod offline olarak sepete **eklenmez** ve yeni ürün **oluşturulmaz**; kullanıcıya Türkçe net bilgilendirme ("*Ürün yerel katalogda bulunamadı. Yeni ürün oluşturmak için Master Hub bağlantısı gereklidir.*") gösterilir. (Online Hub üzerinden tam yeni ürün/kategori CRUD yönetimi Faz 3 kapsamındadır.)
   - **Yerel Ürün Arama:** Mevcut yerel katalogdan (`LocalProducts` / `LocalProductBarcodes`) ad veya barkod ile hızlı arama ve tek tıkla sepete ekleme.
3. **Dinamik Sepet Yönetimi & Half-Up Para Hesabı (`OD-01` Uyumlu):**
   - Aynı `productId` tekrar okutulduğunda yeni satır açmak yerine mevcut satır miktarını artırma (`BR-POS-02`).
   - Satır içi `>= 48×48 dp` `-` / `+` / `Sil` butonları, `F2` miktar düzenleme ve miktar `0` olduğunda satırı kaldırma; sepet temizlemede onay diyaloğu.
   - Tam adet (`CartItemInput.units`) ve kesirli/gramajlı (`CartItemInput.fractional` / `fromDecimalString`, `scale = 1000`) miktarların Half-Up kuruş yuvarlaması ile floating-point olmadan hesaplanması.
   - Stok `<= 0` veya sepet miktarı sonrası eksiye düşen satırlarda `allow` politikası uyarınca engellememe ve görsel uyarı rozeti (`INV-04`).
4. **Opsiyonel Sanal Numpad (`OD-04` Uyumlu):**
   - `OD-04` gereği **varsayılan olarak kapalı (`false`)** gelir; POS ekranı üst/yan ayar veya görünüm anahtarıyla açılıp kapatılabilir. Açıldığında dokunmatik $\ge 48\times 48\text{ dp}$ tuş düzenini sunar.
5. **Tek Ödeme Diyaloğu (`INV-08`, `INV-05`) & Atomik Satış Kaydı (`BR-POS-07`):**
   - `F10` (Nakit), `F9` (Kart), `Esc` (İptal) ve dokunmatik ödeme butonları (`main_shell_screen.dart` uyumlu).
   - **Nakit Akışı:** Hızlı banknot butonları + katı kuruş metin ayrıştırıcısı + anlık para üstü (`receivedCents - totalCents`); alınan tutar toplamdan küçükse onay butonu kesinlikle pasif kalır (`BR-PAY-03`).
   - **Kart Akışı:** Banka POS cihazına tutar gönderilmez (`INV-05`); tutarın harici POS terminalinden tahsil edildiğine dair kasiyer/sahip onayı istenir.
   - **Atomik Kayıt:** Onaylandığında [`LocalDatabaseService.repository.createOfflineSale`](../../lib/core/storage/local_database_service.dart#L436-L450) çağrısı ile tek SQLite transaction içinde `local_sales`, `local_sale_items` (snapshot ad, birim, fiyat, sürüm), `local_stock_movements` (`SATIS`), `local_products` stok düşümü, `client_sync_states.currentClientSeq` artışı ve `outbox_operations` (`PENDING`) kaydı işlenir; ardından `systemStatusProvider` yenilenerek [`CashierHeaderBar`](../../lib/features/shell/presentation/widgets/cashier_header_bar.dart) bekleyen outbox sayacını anında günceller.
6. **Shell Entegrasyonu & Placeholder Hizalama (`UX_07` §4.1):**
   - `MainShellScreen` `case 0` gerçek POS ekranına geçirilir (`_selectedIndex = 0` başlangıç tercihi ve `case 1`/`case 2` placeholder metinlerindeki *"stok sayımı"* / *"Z-Raporu, KDV dökümü"* ifadelerinin kanonik MVP kapsamına göre temizlenmesi).

### 2.2. Faz 1.2 Kapsam Dışı Bırakılanlar (Explicitly Out of Scope for Faz 1.2)
- **`OD-02` / `BR-POS-05` Parked Carts (Sepeti Askıya Alma & `F4`):** MVP kapsamı dışındadır (`OUT_OF_SCOPE`).
- **Fiziksel Stok Sayımı (`BR-STK-04..10`), KDV Hesaplama & Z-Raporu:** MVP dışıdır.
- **Hub Üzerinden Online Ürün Ekleme / Kategori CRUD / Open Food Facts:** Faz 3 kapsamındadır (`OD-03` offline eklemeyi tamamen yasaklar).
- **Arka Plan Outbox Senkronizasyon Worker'ı & Çakışma Çözümü:** Faz 5 kapsamındadır (Faz 1.2 yalnız `outbox_operations` tablosuna `PENDING` kaydını atomik yazar).
- **Satış Geçmişi, Fiş İptali / Kısmi İade (`W-10`/`W-11`):** Faz 4 kapsamındadır (iade Hub LAN bağlantısı gerektirir).
- **QR Cihaz Eşleştirme & `B-2` / `B-3` Güvenlik Sertleştirmesi:** Faz 2 / pilot öncesi güvenlik fazı kapsamındadır.
- **Donanımsal Fiş Yazıcı & Kasa Çekmecesi:** `FUTURE SCOPE`.

---

## 3. Bağımlılıklar

### 3.1. Mevcut Hazır Altyapı ve Paketler (`pubspec.yaml` Değişikliği Gerektirmez)
| Bileşen / Paket | Mevcut Durum ve Konum | Faz 1.2'deki Rolü |
|---|---|---|
| **`mms_client_storage`** | Hazır (`packages/mms_client_storage`, commit `8676586`): `ClientDatabase`, `ClientStorageRepository`, `CartItemInput`, `SaleTransactionResult`. | Barkod sorgusu (`getProductByBarcode`), kesirli/adet girdi dönüşümü (`CartItemInput`), Half-Up hesap ve atomik `createOfflineSale`. |
| **`LocalDatabaseService`** | Hazır ([`local_database_service.dart`](../../lib/core/storage/local_database_service.dart)): drain takip sarmalayıcısı `_TrackedClientStorageRepository` ve metrik sorguları. | UI/Repository işlemlerinin güvenli DB yaşam döngüsü ve in-flight drain garantisi altında yürütülmesi. |
| **`SystemStatusNotifier`** | Hazır ([`system_status_notifier.dart`](../../lib/features/diagnostics/application/system_status_notifier.dart)): `localDatabaseServiceProvider`, `apiClientProvider`, `systemStatusProvider`. | Üst barda Hub durumu (`online/offline/draining`) ve satış sonrası `pendingOutboxCount` / `localSalesCount` yenilemesi. |
| **`AppTheme` & `MainShellScreen`** | Hazır ([`app_theme.dart`](../../lib/core/theme/app_theme.dart), [`main_shell_screen.dart`](../../lib/features/shell/presentation/screens/main_shell_screen.dart)): `F1/F2/F9/F10/Esc` alt çubuğu, `primaryBlue (#1E40AF)`, `textMutedLight (#475569)`, `Size(64, 52)`. | Ek paket gerektirmeden doğrudan Faz 1.2 UI kabuğu ve tema tabanı olarak kullanılır. |
| **Dart / Flutter Bağımlılıkları** | [`pubspec.yaml`](../../pubspec.yaml): `flutter_riverpod: ^2.5.1`, `drift: ^2.20.0`, `http: ^1.2.2`, `path: ^1.9.0`. | Durum yönetimi ve yerel SQLite sorguları için yeterlidir. |

### 3.2. Faz 1.2 Uygulaması Sırasında Tamamlanacak Dahili Eksikler
1. **Yerel Katalog Arama Sorgusu:** [`ClientStorageRepository`](../../packages/mms_client_storage/lib/src/database/client_storage_repository.dart) yalnızca tam barkod eşleştirmesi (`getProductByBarcode`) sunar; ürün adına/kısmi barkoda göre arama yapan `searchActiveProducts(String query)` veya muadili Drift sorgusu Faz 1.2 veri katmanına eklenecektir.
2. **Veri/Test Seed Yardımcıları:** Henüz Faz 3 Ürün CRUD ve Faz 5 Sync Pull bulunmadığından, Faz 1.2 UI geliştirme/doğrulamasında yerel DB entegrasyonu test fixture'ları veya kontrollü geliştirme seed verisi (üretim dışı) tanımlanmalıdır.
3. **`go_router` & Ek Fontlar:** [`pubspec.yaml`](../../pubspec.yaml) içinde `go_router` veya `RobotoMono` fontu **bulunmamaktadır** (`UX_07` §1). Faz 1.2 tek pencere `MainShellScreen` tabları ve `showDialog` modalları ile **yeni harici bağımlılık eklemeden** geliştirilebilir (`AppTheme.tabularFiguresFeature` halihazırda mevcuttur).

---

## 4. Teknik Riskler ve Azaltma Önlemleri

Kod tabanı incelemesi (`client_storage_repository.dart`, `client_database.dart`, `main_shell_screen_test.dart`, `server.dart`) sonucunda aşağıdaki somut teknik riskler tespit edilmiştir:

| Risk ID | Tespit Edilen Gerçek Risk ve Kaynak Referansı | Etkisi | Azaltma Önlemi |
|---|---|---|---|
| **R-01** | **`getProductByBarcode` Pasif Ürün Filtresi Eksikliği:** [`client_storage_repository.dart:294-307`](../../packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L294-L307) `isActive == true` filtresini yalnızca `LocalProductBarcodes` üzerinde uygular, `LocalProducts.isActive` kontrolü yapmaz; kontrol yalnız `createOfflineSale` satır `106`'da gerçekleşir. Ayrıca `localProducts.barcode` fallback araması `getSingleOrNull()` kullanır. | Pasif ürün sepete eklenebilir, kasiyer tüm ürünleri okutup ödeme onayında `StateError` alabilir; mükerrer fallback barkod varsa sorgu hata fırlatabilir. | `domain`/`application` barkod ekleme use-case'inde `!product.isActive` kontrolü ekleme anında yapılmalı ve pasif ürün kesin reddedilmelidir; gerekiyorsa repository arama sorgusu sertleştirilmelidir. |
| **R-02** | **Aynı `productId` İçin Satır PK Çakışma Riski:** [`client_storage_repository.dart:184, 199`](../../packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L184-L199) kalem ID'sini `'citem_${saleTimestamp.microsecondsSinceEpoch}_${item.productId}'` şeklinde üretir. | Aynı `productId` bir satış çağrısında iki ayrı `CartItemInput` olarak gönderilirse `UNIQUE constraint failed` hatasıyla transaction düşer. | `CartNotifier` aynı ürünü her zaman tek satırda birleştirerek (`BR-POS-02`) `createOfflineSale`'e tekil `productId` listesi göndermelidir; fiyat müdahalesi gibi farklı kurallar ileride gerekirse ID şeması gözden geçirilmelidir. |
| **R-03** | **Birim Dönüşüm `den` Bölünebilirlik Kısıtı:** [`client_storage_repository.dart:139-145`](../../packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L139-L145) `prodMilli % den != 0` ise `ArgumentError` fırlatır. | Kesirli gramajlı/oranlı ürünlerde (`conversionFactorDenominator > 1`) miktar adımı `den` ile tam bölünmüyorsa satış ödeme anında başarısız olabilir. | Sepet ekleme/miktar güncelleme aşamasında `den` bölünebilirlik doğrulaması yapılmalı ve kullanıcıya anlaşılır Türkçe uyarı verilmelidir. |
| **R-04** | **`paymentMethod` Sözleşme Tutarsızlığı:** [`client_database.dart:56`](../../packages/mms_client_storage/lib/src/database/client_database.dart#L56) yorumu `'CASH', 'CREDIT_CARD'`, [`server.dart:995`](../../test_spikes/spike_01_backend/bin/server.dart#L995) varsayılan `'CASH'`, UX dokümanları `'CASH'`/`'CARD'` ifadelerini kullanmaktadır. | Frontend `'CARD'`, backend veya rapor sorguları `'CREDIT_CARD'` beklerse senkronizasyonda/raporlamada uyumsuzluk doğabilir. | Faz 1.2 kodlaması başlamadan `PaymentMethod` sabitleri backend `/sync` sözleşmesiyle kesin olarak standardize edilmelidir. |
| **R-05** | **Mevcut Widget Test Kırılma Riski:** [`main_shell_screen_test.dart:79-82`](../../test/features/shell/main_shell_screen_test.dart#L79-L82) varsayılan açılış sekmesinin index `3` (`Sistem Durumu ve Altyapı Tanılama`) olmasını test eder. | Başlangıç sekmesi `0: Kasa (Satış)` yapıldığında mevcut Faz 1.1 testleri kırılır. | Sekme değişimi bilinçli yapılarak ilgili Faz 1.1 navigasyon testleri güncellenmeli ve diagnostics erişim testi korunmalıdır. |
| **R-06** | **USB HID Odak Yarışı ve Yanlış Enter Tetiklemesi:** Fiziksel barkod okuyucu klavye taklidiyle hızlı karakter + `Enter` gönderir; ödeme diyaloğu veya miktar kutusu açıkken yanlışlıkla barkod okunursa beklenmeyen input/onay tetiklenebilir. | Ödeme tutar alanına barkod numarası yazılması veya hatalı satış onayı. | Modal/diyalog açıkken barkod okuyucu pasif tutulmalı (`FocusNode` state makinesi), ödeme diyalogunda yalnız açık kullanıcı girdisi + onay mekanizması çalışmalıdır. |
| **R-07** | **Cihaz ID Sabiti (`AppConstants.defaultDeviceId`):** Faz 2 cihaz kaydı ve `B-3` güvenli saklama henüz olmadığından [`app_constants.dart:12`](../../lib/core/constants/app_constants.dart#L12) `'POS-WIN-01'` kullanır. | Çoklu terminal ortamında farklı kurulumlar aynı `deviceId` ile çıkabilir. | Faz 1.2 için yapılandırılabilir/yerel `initializeDevice` akışı izole bir provider üzerinden sağlanmalı, Faz 2'de kalıcı kayıtlı ID'ye sorunsuz devredilmelidir. |

---

## 5. Test Stratejisi (`test-first` Becerisi & `AGENTS.md` §8)

Faz 1.2 geliştirmesi tavizsiz **TDD (Red-Green-Refactor)** döngüsüyle yürütülecektir; yeni iş kuralı/use-case/UI davranışı yazılmadan önce başarısız testi yazılacaktır:

1. **Birim Testleri (Saf Dart — `test/features/pos/domain/` & `application/`):**
   - **Para & Yuvarlama (`OD-01`):** Half-Up yuvarlama sınır değerleri (`0.004 kg`, `0.005 kg`, `0.335 kg × 12550 kr`, `Number/int64` taşma koruması), `double` kullanılmadan `MoneyFormatter` (`12.50 TL`, `1,250.00 TL`), katı kuruş string ayrıştırıcı (`"0"`, `"-0"` normalizasyonu/negatif giriş reddi, geçersiz metin reddi).
   - **Bilinmeyen & Pasif Barkod (`OD-03`):** Yerel DB'de bulunmayan barkodun offline eklenememesi ve yeni ürün oluşturma yolunun kapalı olması; pasif ürünün (`isActive: false`) sepete alınmaması; yerel DB'deki aktif ürünün offline eklenebilmesi.
   - **Sepet İş Kuralları & `OD-04`:** Aynı `productId` okutmada miktar artırma/birleştirme, `0` miktarda satır silme, `showVirtualNumpad` başlangıç değerinin `false` (kapalı) olması, nakit para üstü (`received >= total`), eksik nakit ödemede tamamlama kilidi (`INV-08`).
2. **Entegrasyon Testleri (Gerçek FFI SQLite WAL — `test/features/pos/data/`):**
   - Sahte in-memory mock'lar yerine **gerçek dosya tabanlı FFI SQLite (`WAL`, `PRAGMA busy_timeout = 5000`)** üzerinde:
     - Barkod (birincil + ikincil aktif barkod) sorgulama -> sepet oluşturma -> `createOfflineSale` -> `local_sales`, `local_sale_items` snapshot (fiyat/ad/birim değişse bile eski satışın etkilenmemesi), `local_stock_movements` (`SATIS`), `local_products.stock` eksiye düşebilme (`allow` `INV-04`), `client_sync_states.currentClientSeq` artışı ve `outbox_operations` `PENDING` kaydının atomik yazımı.
     - Kısmi hata durumunda (ör. `den` bölünememesi veya DB kısıtı) transaction rollback doğrulaması (`0` kısmi kayıt).
3. **Widget & Klavye Etkileşim Testleri (`test/features/pos/presentation/`):**
   - `MainShellScreen` Kasa sekmesi entegrasyonu, tüm kritik aksiyon butonlarının (`+`, `-`, sil, hızlı tuşlar, Nakit/Kart ödeme, opsiyonel numpad tuşları) $\ge 48\times 48\text{ dp}$ boyutu, `OD-04` sanal numpad'in varsayılan gizli olup toggle ile açılması.
   - `F1` (Yardım), `F2` (Miktar), `F9` (Kart), `F10` (Nakit), `Esc` (İptal/Kapat) klavye kısayolları ve **`F4` / Parked Carts UI öğelerinin bulunmadığının** doğrulanması (`OD-02`).
   - Ödeme diyalogunda eksik tutarda onay butonunun `onPressed == null` (kilitli) kalması; başarılı satış sonrası sepetin sıfırlanıp [`SystemStatusNotifier`](../../lib/features/diagnostics/application/system_status_notifier.dart) bekleyen outbox sayacının güncellenmesi.
4. **Kalite Kapısı:** Her PR/adım sonunda `flutter analyze --no-pub` (0 hata/uyarı) ve `flutter test` (%100 yeşil, skip/mocked-away pass olmaksızın) çalıştırılarak gerçek terminal çıktıları raporlanacaktır.

---

## 6. Açık Kalan Konular

`OD-01`..`OD-04` UI/UX açık kararlarının tamamı kapanmış olmakla birlikte, Faz 1.2 öncesi ve sonrasında takip edilen konular şeffafça ayrılmıştır:

1. **Faz 1.2 Kodlaması Öncesi 3 Hızlı Teyit Maddesi (Engelleyici Değildir — Uygulama Netleştirme):**
   - *Ek Klavye Kısayolları (`[UX PROPOSAL]`):* `MainShellScreen`'deki mevcut `F1/F2/F9/F10/Esc` çubuğuna ek olarak `F3` (Ürün Arama) ve `F8` / `Del` (Seçili Satır Sil) kısayollarının Faz 1.2'de eklenmesi ve uygulama açılış sekmesinin `3` yerine `0` (`Kasa (Satış)`) yapılması.
   - *Hızlı Ürün Tuşları (`[UX PROPOSAL]`):* Sağ panelde sabit/yapılandırılabilir hızlı ürün butonlarının Faz 1.2 içinde başlangıçta nasıl besleneceği (ör. yerel `LocalProducts` üzerinden tanımlı hızlı tuş listesi veya temel ilk set).
   - *`paymentMethod` Sabit Adı:* `CASH` yanında kart ödemesi için `'CARD'` mı `'CREDIT_CARD'` mı kullanılacağının backend `/sync` ile eşitlenmesi.
2. **Kesinleşmiş Mimari / Güvenlik Backlog Kalemleri (Açık Karar Değildir — Pilot Öncesi Zorunlu Uygulama):**
   - **`B-2`:** Mobil istemcilerde Root CA doğrulaması ve Certificate Pinning (Faz 2 / mobil).
   - **`B-3`:** Güvenli token depolama — Windows DPAPI (`pepper.dpapi`), Android Keystore, iOS Keychain.
   - **Sistem & Saha Doğrulamaları:** Windows `SCM` gerçek servis kurulum/recovery testleri, standart Windows kullanıcısı `ACL` doğrulaması, fiziksel Android/iOS mDNS/QR eşleştirme testleri ile gerçek kullanıcı/donanım testleri (`T-09` & `T-11` — Faz 7 Pilot).
3. **Senkronizasyon Protokolü Parametreleri (`OFFLINE_SYNC_PROTOCOL.md` / Faz 5):**
   - Worker kiralama (lease), kilit kurtarma süresi ve üstel backoff retry parametreleri (`Faz 1.2` yalnız local outbox `PENDING` yazar, Faz 5'te netleşir).
4. **Hukuki Lisans Taraması (`T-12` — `DESIGN_REFERENCES_AND_LICENSES.md`):**
   - Üretim dağıtımı öncesinde üçüncü parti paket/font lisanslarının otomatik denetimi.
5. **Diğer Belgelerdeki Tarihsel `OPEN DECISION` Metinleri & `main_shell_screen.dart` Placeholder Borcu:**
   - Bu görev kapsamında kapsam dışı bırakılan [`AGENTS.md`](../../AGENTS.md) §4.7, [`ARCHITECTURE.md`](../ARCHITECTURE.md) (`L106`), [`ROADMAP.md`](../ROADMAP.md) (`L54`) ve [`testing.md`](../ai/rules/testing.md) (`L13`) dosyalarındaki tarihsel *"alt kuruş yuvarlama OPEN DECISION"* ibareleri ile [`main_shell_screen.dart:112,119`](../../lib/features/shell/presentation/screens/main_shell_screen.dart#L112-L119) placeholder metinlerindeki (*"stok sayımı"*, *"Z-Raporu, KDV dökümü"*) ifadeler Faz 1.2 uygulaması / doküman bakımında hizalanmalıdır.

---

## 7. Faz 1.2'ye Başlamak İçin Gereken Koşullar

Faz 1.2 uygulama kodlamasına geçilebilmesi için aşağıdaki koşulların sağlanması gerekmektedir:

1. **Proje Sahibi Açık Kodlama Onayı (`AGENTS.md` §12, §14.1):** Proje sahibinin bu hazırlık raporundaki Faz 1.2 kapsamını, risk önlemlerini, Clean Architecture sınırlarını ve Bölüm 6.1'deki 3 netleştirme noktasını inceleyerek **"Faz 1.2'ye başla"** onayı vermesi.
2. **Git Hijyeni / Kayıt Güvencesi (Opsiyonel Önerilen):** Mevcut kabul edilmiş UI/UX paketi (`docs/ui-ux/`), `PHASE_1_1_GIT_EXECUTION_REPORT.md`, `PHASE_1_2_PREPARATION_REPORT.md` ve uzlaştırılmış kanonik dokümanların (`PROJECT_STATUS.md`, `REQUIREMENTS.md`, `BUSINESS_RULES_SPEC.md`) Proje Sahibi tarafından verilecek dosya bazlı `git add <dosya>` / `git commit` talimatıyla temiz bir başlangıç noktasına alınması.
3. **Temiz Başlangıç Doğrulaması:** Mevcut `flutter analyze --no-pub` ve `flutter test` paketlerinin sıfır hatayla yeşil kalması (`lib/`, `test/`, `pubspec.yaml` temiz).

