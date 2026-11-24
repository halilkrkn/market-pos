# PHASE_A1_DELIVERY_REPORT.md — Faz 2 (`Hat A / Faz A-1`) Teslim Raporu

- **Faz:** Faz 2 — Core Market Pilot Hazırlık (`A-1.1`, `A-1.2` / `GAP-A01`, `A-1.3`, `A-1.4` / `GAP-A03`)
- **Durum Özeti:**
  - `A-1.1` Birleşik Hub Kapanışı (`LifecycleManager` + `SpikeServer`): **`IMPLEMENTED`**, **`AUTOMATED_TESTED`**
  - `A-1.2` İkincil Barkod Tam-Yığın Senkronizasyonu (`GAP-A01`, Hub v3→v4 migration + Client Outbox + Sync): **`IMPLEMENTED`**, **`AUTOMATED_TESTED`** — *veri/senkron katmanı.*
    - **Düzeltme (23 Kasım 2026 (2. tur)):** Bu raporun önceki sürümü ikincil barkodun kullanıcı arayüzüne bağlandığını ima ediyordu. Bağımsız incelemede yalnızca `CatalogNotifier.addProductBarcode/removeProductBarcode` fonksiyonlarının bulunduğu, **hiçbir ekrandan çağrılmadığı** doğrulandı (23 Kasım 1. tur itibarıyla ikincil barkod UI **YOKTU**). Gerçek UI 23 Kasım 2. turda eklendi (`IMP-15`, §5).
  - `A-1.3` Sınırsız Dashboard SQL Aggregate Sorguları: **`IMPLEMENTED`**, **`AUTOMATED_TESTED`**
  - `A-1.4` E2E Doğrulama Testi Güncellemesi (`GAP-A03`): **`IMPLEMENTED`** (canlı fiziksel cihaz çalıştırması **`BLOCKED`**)
  - Gerçek Windows Servis / ACL / Fiziksel Android / LAN Kabul Testleri: **`BLOCKED`** (Owner cihaz/servis adımları gereklidir)

---

## 1. Kapsam ve Tamamlanan İşler

### 1.1 `A-1.1` — Birleşik Hub Kapanış Akışı
- [lifecycle_manager.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/service/lifecycle_manager.dart):
  - `LifecycleManager` içine isteğe bağlı `Future<void> Function()? onBeforeDrain` kancası eklendi.
  - `shutdown()` içinde `admissionGate.close()`, `writeQueue.markDraining()` ve sinyal dinleyici iptallerinin hemen ardından, `12` saniyelik küresel `drainTimeout` bütçesi içinde `onBeforeDrain` çalıştırılır; 101 çıkış kodu ve WAL koruma davranışı bozulmadı.
- [server.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart):
  - `_stopServerResources()` idempotent yardımcısı `lifecycle.onBeforeDrain` kancasına bağlandı (`_pairingCleanupTimer`, `_backupScheduler`, `_discoveryResponder` durdurma).
  - `SpikeServer.stop()` artık doğrudan yalnızca timer/responder kapatıp `lifecycle.shutdown(reason: 'SpikeServer.stop', exitProcess: false)` üzerinden birleşik tahliye + WAL `TRUNCATE` + `db.close()` yürütür; `main()` kapanışta `await server.stop()` bekler.

### 1.2 `A-1.2` — İkincil Barkod Tam-Yığın Senkronizasyonu (`GAP-A01`)
- [database.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/db/database.dart) & üretilen `database.g.dart`:
  - Hub `SpikeDatabase` üzerinde `ProductBarcodes` Drift tablosu (`id`, `productId`, `barcode` UNIQUE, `isPrimary`, `isActive`, `createdAt`) tanımlandı ve `schemaVersion` `3 → 4` yükseltildi.
  - `onCreate`, `onUpgrade` ve `beforeOpen` yollarında `_ensureV4ProductBarcodesTable()` ile `products.barcode` satırları güvenli biçimde backfill edilir.
- [server.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart):
  - `POST /api/v1/products/upsert`: `product.barcodes` dizisini doğrular, mükerrerliği kontrol eder (`products` ve `product_barcodes` üzerinde farklı ürüne kayıtlıysa `409 ERR_DUPLICATE_BARCODE`), `product_barcodes` tablosunu atomik olarak uzlaştırır; `idempotent replay` korunur.
  - `GET /api/v1/products`: her ürün için aktif tüm barkodları (`isPrimary` önde olacak şekilde) `barcodes` dizisinde döner.
- [client_storage_repository.dart](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/database/client_storage_repository.dart) & [client_sync_service.dart](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/sync/client_sync_service.dart):
  - `addProductBarcode` ve `removeProductBarcode` isteğe bağlı `String? deviceId` parametresi aldı; her iki tablo (`local_products` ve `local_product_barcodes`) üzerinde mükerrer barkod reddi uygulandı ve `deviceId` verildiğinde aynı SQLite transaction içinde FIFO `PRODUCT_UPSERT` Outbox kaydı üretildi.
  - `upsertProducts(..., deactivateRemovedBarcodes: bool = false)` eklendi ve `ClientSyncService` ürün indirmede `deactivateRemovedBarcodes: true` ile Hub barkod silmelerini yerel veritabanına yansıtır.
- [catalog_repository.dart](file:///c:/Users/halil/Github/market-pos/lib/features/catalog/data/catalog_repository.dart), [catalog_notifier.dart](file:///c:/Users/halil/Github/market-pos/lib/features/catalog/application/catalog_notifier.dart) ve [local_database_service.dart](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart):
  - `deviceId` ve `onProductChanged?.call()` ikincil barkod ekleme/silme akışlarına bağlandı. *(Not: Bu yalnızca notifier/repository düzeyindeydi; 23 Kasım 1. tur itibarıyla bu fonksiyonları çağıran bir ekran yoktu — bkz. §5.)*
  - `_TrackedClientStorageRepository` yeni parametre ve özet metodlarını `_service.runOperation(...)` üzerinden iletecek şekilde güncellendi.

### 1.3 `A-1.3` — Sınırsız Dashboard SQL Aggregate Sorguları
- [dashboard_summary.dart](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/models/dashboard_summary.dart) (ve [mms_client_storage.dart](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/mms_client_storage.dart) export):
  - `DashboardProductSummary`, `DashboardDailySalesTotal`, `DashboardSalesSummary` modelleri eklendi.
- [client_storage_repository.dart](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/database/client_storage_repository.dart):
  - `getDashboardProductSummary` ve `getDashboardSalesSummary`: 500 ürün / 2000 satış bellek içi sınırları kaldırıldı; aktif/kritik/eksi stok sayıları, son kritik ürünler önizlemesi ve net ciro/iade kesintisi doğrudan SQL aggregate sorgularıyla hesaplanır.
- [dashboard_providers.dart](file:///c:/Users/halil/Github/market-pos/lib/features/dashboard/dashboard_providers.dart):
  - `dashboardSnapshotProvider` yeni SQL aggregate metotlarını ve `getSalesHistory(limit: 8)` çağrısını tüketir.

### 1.4 `A-1.4` — E2E Doğrulama Testi Güncellemesi (`GAP-A03`)
- [android_full_e2e_verification_test.dart](file:///c:/Users/halil/Github/market-pos/integration_test/android_full_e2e_verification_test.dart):
  - Gömülü token kaldırıldı (`MMS_E2E_DEVICE_TOKEN` ortam/define anahtarı).
  - Kısmi iade durum beklentisi `PARTIALLY_REFUNDED` olarak hizalandı.
  - Canlı DB yedeğinde `dbFile.copy` yerine `VACUUM INTO` kullanıldı.

---

## 2. Doğrulama Sonuçları (Gerçek Komut Çıktıları)

1. **`packages/mms_client_storage`:**
   - `dart analyze` → `No issues found!`
   - `dart test test/phase_a1_barcode_and_dashboard_test.dart test/database_test.dart test/stock_receipt_test.dart test/client_sync_service_test.dart test/bk02_reconciliation_test.dart` → **`00:05 +51: All tests passed!`**
2. **`test_spikes/spike_01_backend`:**
   - `dart analyze` → `No issues found!`
   - `dart test test/phase_a1_shutdown_and_barcode_test.dart test/s5a2_durability_lifecycle_test.dart test/bk02_1_hub_reconciliation_test.dart test/product_upsert_test.dart test/lifecycle_drain_test.dart test/hub_discovery_responder_test.dart test/s5a3_sales_validation_test.dart` → **`00:14 +63: All tests passed!`**
3. **Kök Uygulama (`market_pos`):**
   - `flutter analyze` → **`No issues found! (ran in 2.8s)`**
   - `flutter test test/features/dashboard/ test/features/catalog/` → **`00:04 +12: All tests passed!`**

---

## 3. Açık Blokajlar (Fiziksel Kabul Gereksinimleri)
- Canlı Windows Service kurulum/yeniden başlatma, `setup_service_acls.ps1`, fiziksel Android cihazda ikincil barkod E2E senkronizasyonu ve `integration_test/android_full_e2e_verification_test.dart` cihaz koşumu bu aşamada **`BLOCKED`** durumundadır (`OWNER ACTION REQUIRED`).

---

## 4. 23 Kasım 2026 Devralma Doğrulaması ve Ek Düzeltmeler

Önceki aracın `A-1.1…A-1.4` çalışmaları korunmuş, yeniden yazılmamıştır. Gerçek test çıktıları için [`FINAL_PILOT_READINESS_REPORT.md`](../FINAL_PILOT_READINESS_REPORT.md) §3 esastır.

- **`A-1.1` kapanış zinciri (kod incelemesi):** SIGINT → `LifecycleManager.shutdown(exitProcess: true)` → `AdmissionGate.close` + `WriteQueue.markDraining` → `onBeforeDrain` (= `SpikeServer._stopServerResources`: orkestratör kooperatif iptali, eşleştirme temizlik zamanlayıcısı, eski yedek zamanlayıcısı, UDP discovery) **aynı 12 s global bütçe içinde** → HTTP close → in-flight drain → WriteQueue drain → `wal_checkpoint(TRUNCATE)` → `db.close()`; drain zaman aşımında DB kapatılmaz, çıkış `101`. `SpikeServer.stop()` aynı yolu `exitProcess: false` ile kullanır; `main()` admin kapanışında `onShutdown` → `stop()` → `exit(code)`. `phase_a1_shutdown_and_barcode_test`, `lifecycle_drain_test`, `shutdown_regression_test`, `s5a2_durability_lifecycle_test` tam Hub takımında geçti.
- **`A-1.2` ek düzeltme (`IMP-05`):** Son barkod silindiğinde (istemci `barcode: null`, `barcodes: []`) Hub eski birincil barkoda geri düşüyordu → silinen barkod Hub'da aktif kalıp ürün indirmesinde istemciye geri diriliyordu. Düzeltildi (`bin/server.dart`); `phase_a1_shutdown_and_barcode_test` genişletildi.
- **`A-1.2` yeni tam yığın testi:** `test/a1_secondary_barcode_full_stack_e2e_test.dart` — gerçek istemci DB + `ClientSyncService`/`HttpSyncTransport` + gerçek Hub: ikincil barkod oluşturma → Hub → ikinci cihaz → Hub kapalıyken ikincil barkodla çevrimdışı 2 adet satış → Hub stoğu tek sefer düşer, tekrar gönderim mükerrer üretmez → barkod silme yayılımı.
- **`A-1.4` ek düzeltme (`IMP-06`):** E2E testi uygulamanın gerçek `client_local.db` dosyasını kullanıyordu ve URL verilmezse LAN'da keşfettiği (üretim olabilecek) Hub'a test satışı gönderebiliyordu. Artık geçici izole SQLite kullanır; Hub adresi `MMS_E2E_HUB_URL` ile zorunlu, keşif yalnız `MMS_E2E_ALLOW_DISCOVERY=true` ile. Yedek manifestindeki sabit `schemaVersion: 2` gerçek şema sürümüyle değiştirildi. Cihaz koşumu: **`BLOCKED`** (`PAT-20`).

---

## 5. 23 Kasım 2026 (2. tur) — İkincil Barkod Kullanıcı Arayüzü (`IMP-15`)

- **Eklenen ekran/girişler:** Katalog ürün satırı (masaüstü) ve ürün kartı (dar/Android) üzerinde **Barkodları Yönet** düğmesi; ürün düzenleme (detay) diyaloğunda **İkincil Barkodları Yönet** düğmesi → `ProductBarcodesDialog` (`lib/features/catalog/presentation/widgets/product_barcodes_dialog.dart`).
- **Kullanıcı işlemleri:** Birincil barkodu görme, ikincil barkodları listeleme, elle/USB okuyucuyla veya (destekleyen cihazda) kamerayla ekleme, onay diyaloğuyla silme; başarı/hata geri bildirimi diyalog içinde.
- **İş kuralları:** Birincil barkod ikincil olarak eklenemez; aynı ürüne tekrar eklenemez; başka ürüne kayıtlı barkod eklenemez (ürün adı gösterilir); geçersiz biçim reddedilir. Kurallar depo katmanında da zorlanır.
- **Senkron geri bildirimi:** Ürün bazlı Hub gönderim durumu (eşit / bekliyor / yeniden denenecek / kalıcı hata) diyalogda ve liste rozetinde; genel Outbox rozetine bağımlı değildir.
- **9.4 düzeltmesi:** Gönderilmemiş `PRODUCT_UPSERT` olan ürünlerin barkodları Hub snapshot'ı ile ezilmez (silinen barkodun geçici geri dönmesi ve sonraki değişiklikle Hub'a geri yazılması önlendi).
- **Durum:** **`IMPLEMENTED`**, **`AUTOMATED_TESTED`** (widget + paket testleri, sayılar `FINAL_PILOT_READINESS_REPORT.md` §E). Kamera taraması ve iki cihaz arası gerçek senkron **fiziksel olarak test edilmedi** → `PAT-19` **`BLOCKED`**.
