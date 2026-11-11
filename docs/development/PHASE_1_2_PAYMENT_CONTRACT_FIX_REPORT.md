# PHASE 1.2 PRE-WORK — `PaymentMethod` SÖZLEŞME STANDARDİZASYON RAPORU

**Belge Kodu:** `docs/development/PHASE_1_2_PAYMENT_CONTRACT_FIX_REPORT.md`  
**Tarih:** 11 Kasım 2026  
**Durum:** Tamamlandı — Proje Sahibi İnceleme ve Kabulü Bekliyor  
**Ön Koşul Dayanak:** [`docs/development/PHASE_1_2_FINAL_PREFLIGHT_REPORT.md`](./PHASE_1_2_FINAL_PREFLIGHT_REPORT.md) (Bölüm 1 — Blocking Finding)  
**Ana Anayasa ve Plan:** [`AGENTS.md`](../../AGENTS.md), [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](../../MARKET_POS_AI_STUDIO_BUILD_PLANI.md) (v1.4), [`BUSINESS_RULES_SPEC.md`](../requirements/BUSINESS_RULES_SPEC.md) (v1.5)

---

## 1. Değiştirilen ve Oluşturulan Dosyalar ile Gerekçeleri

### 1.1. Yeni Oluşturulan Dosyalar

| Dosya | Rol ve Gerekçe |
|---|---|
| [`packages/mms_client_storage/lib/src/models/payment_method.dart`](../../packages/mms_client_storage/lib/src/models/payment_method.dart) | Yalnızca `'CASH'` ve `'CARD'` değerlerini kanonik kabul eden saf Dart (`dart:core`) `PaymentMethod` enumu (`code`, `canonicalCodes`, fail-closed `parse`, `tryParse`, `isCanonical` ve salt-okunur tarihsel çözümleme için `tryParseLegacyReadOnly`). Flutter veya Drift bağımlılığı taşımadığı için Domain ve Backend tarafından ortak kullanılabilir. |
| [`packages/mms_client_storage/lib/payment_method.dart`](../../packages/mms_client_storage/lib/payment_method.dart) | Saf Dart domain katmanının Drift/SQLite kütüphanelerini içeri çekmeden yalnızca [`payment_method.dart`](../../packages/mms_client_storage/lib/src/models/payment_method.dart) sözleşmesini içe aktarabilmesi için saf Dart barrel girişi. |
| [`packages/mms_client_storage/test/payment_method_contract_test.dart`](../../packages/mms_client_storage/test/payment_method_contract_test.dart) | Saf Dart `PaymentMethod`, `CASH`/`CARD` kalıcılık + Outbox JSON + SHA-256 hash doğrulaması, eski/geçersiz değerlerin (`CREDIT_CARD`, `NAKIT`, küçük harf, boş) reddi ve eski kalıcı `'CREDIT_CARD'` Outbox kaydı için veri kaybı olmadan `ClientSyncService` davranışını doğrulayan 4 birim/entegrasyon testi. |
| [`test/core/storage/payment_method_contract_test.dart`](../../test/core/storage/payment_method_contract_test.dart) | Kök Flutter istemcisi [`LocalDatabaseService`](../../lib/core/storage/local_database_service.dart) üzerinden `CASH`/`CARD` Outbox payload + hash üretimini ve geçersiz değerlerin (`CREDIT_CARD`, `NAKIT`, `cash`, `''`) reddedilmesini doğrulayan 2 test. |

### 1.2. Güncellenen Kaynak ve Test Dosyaları

| Dosya | Değişiklik Özeti ve Gerekçesi |
|---|---|
| [`packages/mms_client_storage/lib/mms_client_storage.dart`](../../packages/mms_client_storage/lib/mms_client_storage.dart) | Paket genel ihracına `src/models/payment_method.dart` eklendi. |
| [`packages/mms_client_storage/lib/src/database/client_database.dart`](../../packages/mms_client_storage/lib/src/database/client_database.dart) | `LocalSales.paymentMethod` kolonu satır içi yorumu (`L56`) eski `// 'CASH', 'CREDIT_CARD', etc.` ifadesinden `// Kanonik sözleşme: 'CASH', 'CARD'` şekline güncellendi. Şema sürümü (`schemaVersion`) ve DDL değiştirilmedi. |
| [`packages/mms_client_storage/lib/src/database/client_storage_repository.dart`](../../packages/mms_client_storage/lib/src/database/client_storage_repository.dart) | `createOfflineSale()` transaction öncesinde `PaymentMethod.parse(paymentMethod).code` doğrulaması uygular ve kanonik değeri `local_sales`, Outbox payload ve `SaleTransactionResult` çıktısında kullanır. `updateAndRetryFailedOperation()` da yükte `'payment_method'` anahtarı varsa `PaymentMethod.parse` ile doğrular. `computeSaleRequestHash()` metoduna dokunulmadı. |
| [`test_spikes/spike_01_backend/bin/server.dart`](../../test_spikes/spike_01_backend/bin/server.dart) | `POST /api/v1/sales` işleyicisi önce `processedOperations` idempotency kontrolünü çalıştırır (eski commit edilmiş kayıtların replay'ini korur), yeni işlemlerde ise `PaymentMethod.isCanonical(rawPaymentMethod)` denetimi yapar; eksik, `null`, tip dışı veya geçersiz/eski değerleri sessizce `'CASH'` yapmak yerine `400 Bad Request` (`code: 'ERR_INVALID_PAYMENT_METHOD'`) döndürür. |
| [`packages/mms_client_storage/test/s5a3_outbox_sync_test.dart`](../../packages/mms_client_storage/test/s5a3_outbox_sync_test.dart) | Eski test fixture değeri `'CREDIT_CARD'` -> `'CARD'` olarak hizalandı (`L172`). |
| [`packages/mms_client_storage/test/s5a3_live_hub_integration_test.dart`](../../packages/mms_client_storage/test/s5a3_live_hub_integration_test.dart) | Eski test fixture değeri `'CREDIT_CARD'` -> `'CARD'` olarak hizalandı ve Master Hub DB'deki `sales` tablosunda `masterSales[0]['payment_method'] == 'CASH'` ile `masterSales[1]['payment_method'] == 'CARD'` doğrulamaları eklendi (`L270, L323-328`). |
| [`test_spikes/spike_01_backend/test/s5a2_durability_lifecycle_test.dart`](../../test_spikes/spike_01_backend/test/s5a2_durability_lifecycle_test.dart) | Eski test fixture değerleri `'CREDIT_CARD'` -> `'CARD'` olarak hizalandı (`L499, L548`). |
| [`test_spikes/spike_01_backend/test/s4_device_pairing_test.dart`](../../test_spikes/spike_01_backend/test/s4_device_pairing_test.dart) | Eski test fixture değerleri `'NAKIT'` -> `'CASH'` olarak hizalandı (`L1300, L1391, L1455, L1488`). |
| [`test_spikes/spike_01_backend/test/s5a3_sales_validation_test.dart`](../../test_spikes/spike_01_backend/test/s5a3_sales_validation_test.dart) | Backend kanonik `'CARD'` kabul + idempotent replay, eksik/`null`/yanlış tip/eski/geçersiz 7 senaryoda `400 ERR_INVALID_PAYMENT_METHOD`, replay ödeme yöntemi değişiminde `409` hash uyuşmazlığı ve önceden işlenmiş legacy `'CREDIT_CARD'` replay uyumluluğunu test eden 4 yeni test (#12–15) eklendi. |

### 1.3. Uzlaştırılan Dokümantasyon Dosyaları

| Belge | Güncelleme Özeti |
|---|---|
| [`docs/requirements/BUSINESS_RULES_SPEC.md`](../requirements/BUSINESS_RULES_SPEC.md) | **v1.5:** Değişiklik günlüğü, `BR-PAY-01`, `BR-PAY-04` ve izlenebilirlik matrisi `'CASH'`/`'CARD'` kanonik tel/depolama sözleşmesiyle ve `'CREDIT_CARD'`/`'NAKIT'` kullanımının yürürlükten kaldırıldığı (*obsolete*) notuyla güncellendi (tarihçe korundu). |
| [`docs/REQUIREMENTS.md`](../REQUIREMENTS.md) | **v1.3:** `BR-PAY` özeti kanonik `'CASH'`/`'CARD'` sözleşmesi, *obsolete* dizgeler ve sessiz `'CASH'` yasağıyla güncellendi; `BUSINESS_RULES_SPEC.md` `v1.5` referansı işlendi. |
| [`docs/architecture/DATA_MODEL.md`](../architecture/DATA_MODEL.md) | Bölüm 1.1 Madde 4 altına `11 Kasım 2026 Sözleşme Standardizasyonu` alt notu eklendi (`'CASH'`/`'CARD'`, `'CREDIT_CARD'`/`'NAKIT'` *obsolete*). |
| [`docs/architecture/DATA_MODEL_DECISIONS.md`](../architecture/DATA_MODEL_DECISIONS.md) | `Karar 6` altına kanonik `'CASH'`/`'CARD'` sözleşmesi, backend sessiz fallback yasağı ve legacy idempotency koruma notu eklendi. |
| [`docs/ui-ux/DESIGN_DECISIONS.md`](../ui-ux/DESIGN_DECISIONS.md) | **v1.4:** `INV-08` satırı ve sürüm notu kanonik `'CASH'`/`'CARD'` kodlarıyla güncellendi (untracked `docs/ui-ux/` içinde). |
| [`docs/ui-ux/UX_07_FLUTTER_HANDOFF.md`](../ui-ux/UX_07_FLUTTER_HANDOFF.md) | **v1.4:** Bölüm 7 altına saf Dart `PaymentMethod` devir kılavuzu maddesi eklendi (untracked `docs/ui-ux/` içinde). |
| [`docs/PROJECT_STATUS.md`](../PROJECT_STATUS.md) | `PaymentMethod` standardizasyonu tamamlanma/inceleme bekleme statüsü, `v1.5`/`v1.4` belge sürümleri ve sonraki adım olarak Faz 1.2 kodlama onayı işlendi. |

### 1.4. Korunan Kapsam Dışı Sınırlar (`git diff` ile doğrulandı)

- `lib/` altında hiçbir Flutter POS ekranı, sepet veya ödeme modalı kodlamasına başlanmadı (`git diff -- lib/` boş).
- Kök `pubspec.yaml`, `packages/mms_client_storage/pubspec.yaml` ve `test_spikes/spike_01_backend/pubspec.yaml` değiştirilmedi; yeni bağımlılık eklenmedi.
- Veritabanı şema sürümü, tablo/kolon yapısı veya migration dosyaları değiştirilmedi.
- `AppConstants.defaultDeviceId` veya Faz 2 eşleştirme akışlarına dokunulmadı; `F3`, `F8/Delete` veya hızlı ürün tuşları uygulanmadı.
- `git add`, `git commit` veya `git push` çalıştırılmadı.
- Tarihsel ön inceleme snapshot'ları ([`PHASE_1_2_PREPARATION_REPORT.md`](./PHASE_1_2_PREPARATION_REPORT.md), [`PHASE_1_2_FINAL_PREFLIGHT_REPORT.md`](./PHASE_1_2_FINAL_PREFLIGHT_REPORT.md)) pre-fix kanıt geçmişini korumak için değiştirilmedi.

---

## 2. Önceki ve Yeni Sözleşme Karşılaştırması

| Boyut | Önceki Durum (`PHASE_1_2_FINAL_PREFLIGHT_REPORT.md`) | Yeni Standardize Edilmiş Durum |
|---|---|---|
| **Ortak Dart Modeli** | Mevcut değildi (`String` parametreleri serbest geçiyordu). | Saf Dart [`PaymentMethod`](../../packages/mms_client_storage/lib/src/models/payment_method.dart) (`PaymentMethod.cash` = `'CASH'`, `PaymentMethod.card` = `'CARD'`). |
| **İstemci Yerel DB Şeması & Repo** | `client_database.dart:56` yorumunda `'CREDIT_CARD'`; `createOfflineSale` doğrulamasız her metni kaydediyordu. | `client_database.dart:56` yorumu `'CASH'`, `'CARD'`; `createOfflineSale()` ve `updateAndRetryFailedOperation()` `PaymentMethod.parse` ile yalnızca `'CASH'` / `'CARD'` kabul eder, geçersiz değerde transaction açılmadan `ArgumentError` fırlatır. |
| **Outbox Payload & Hash** | Ham `paymentMethod` string'i doğrudan JSON yüküne ve SHA-256 hash'e yazılıyordu. | Yalnızca kanonik `'CASH'` veya `'CARD'` değerleri Outbox'a yazılır ve birebir aynı `computeSaleRequestHash` algoritmasıyla hash'lenir. |
| **Backend `POST /api/v1/sales`** | `body['payment_method'] as String? ?? 'CASH'` nedeniyle `null`/eksik sessizce `'CASH'` oluyor; `'CREDIT_CARD'`, `'NAKIT'`, `'cash'`, `''` serbestçe yazılabiliyordu. | Önce idempotency (`processedOperations`) denetimi, ardından yeni kayıtlarda katı `PaymentMethod.isCanonical` kontrolü: yalnızca `'CASH'` ve `'CARD'` kabul edilir; aksi halde `400 ERR_INVALID_PAYMENT_METHOD` döner. |
| **Test Fixture'ları** | 3 yerde `'CREDIT_CARD'`, 4 yerde `'NAKIT'`. | Tüm eski fixture'lar `'CARD'` ve `'CASH'` değerlerine çevrildi; negatif testler `'CREDIT_CARD'` ve `'NAKIT'` reddini doğrular. |
| **Kanonik Dokümantasyon** | `DATA_MODEL.md` `'CASH'`/`'CARD'` derken eski taslak/test notlarında belirsizlik vardı. | `BUSINESS_RULES_SPEC.md` v1.5, `REQUIREMENTS.md` v1.3, `DATA_MODEL.md`, `DATA_MODEL_DECISIONS.md`, `UX_07_FLUTTER_HANDOFF.md` v1.4, `DESIGN_DECISIONS.md` v1.4 ve `PROJECT_STATUS.md` üzerinde `'CASH'`/`'CARD'` tek sözleşme oldu. |

---

## 3. Backend Doğrulama Davranışı (`POST /api/v1/sales`)

[`test_spikes/spike_01_backend/bin/server.dart`](../../test_spikes/spike_01_backend/bin/server.dart) içindeki `/api/v1/sales` uç noktası şu sırayla çalışır:

1. **Idempotency Ön Kontrolü:** Gelen gövdeden `computeSaleRequestHash(body)` (alanlar: `client_seq`, `total_amount`, `payment_method`, `items`) hesaplanır ve `processedOperations` tablosunda `(device_id, client_seq, operation_id)` aranır.
   - Kayıt varsa ve hash eşleşirse mevcut yanıt (`200 OK`) tekrarlanır.
   - Kayıt varsa ve hash uyuşmazsa `409 ERR_IDEMPOTENCY_PAYLOAD_MISMATCH` döndürülür.
2. **Kanonik Ödeme Yöntemi Doğrulaması (Yeni İşlemler İçin):**
   - `final rawPaymentMethod = body['payment_method'];` okunur ve `PaymentMethod.isCanonical(rawPaymentMethod)` ile denetlenir.
   - Yalnızca birebir `String` `'CASH'` veya `'CARD'` değerleri kabul edilir.
   - Aşağıdaki durumların **tamamı** HTTP `400 Bad Request`, `code: 'ERR_INVALID_PAYMENT_METHOD'` ve Türkçe kullanıcı mesajıyla reddedilir — asla sessizce `'CASH'` varsayılanına çevrilmez:
     - `'payment_method'` alanının gövdede hiç bulunmaması (eksik alan)
     - `'payment_method': null`
     - `String` dışı tip (ör. `1`, `true`)
     - Küçük/karışık harf (`'cash'`, `'card'`, `'Cash'`) veya boş metin (`''`)
     - Eski/obsolete dizgeler (`'CREDIT_CARD'`, `'NAKIT'`)
     - Bilinmeyen değerler (`'EFT'`, `'BANK_TRANSFER'` vb.)
3. **Eski Testlerle Uyum Taraması:** Mevcut tüm backend ve entegrasyon testlerindeki `/api/v1/sales` çağrıları taranmış, `'payment_method'` alanını atlayan tek bir geçerli test olmadığı doğrulanmıştır.

---

## 4. Outbox, SHA-256 Hash ve Idempotency Değerlendirmesi

- `ClientStorageRepository.computeSaleRequestHash` ve backend `computeSaleRequestHash` fonksiyonlarının alan sırası, JSON biçimi ve SHA-256 özeti **hiç değiştirilmemiştir**.
- İstemcide `createOfflineSale()` çağrısı transaction açmadan önce `PaymentMethod.parse(paymentMethod).code` sonucunu aldığından:
  - `local_sales.payment_method` sütununa,
  - `outbox_operations.payload` JSON nesnesindeki `'payment_method'` alanına,
  - `SaleTransactionResult.paymentMethod` alanına
  her zaman aynı kanonik `'CASH'` veya `'CARD'` dizgesi yazılır.
- `outbox_operations.payload_hash` değeri `ClientStorageRepository.computeSaleRequestHash` tarafından hesaplandığı için istemci ve backend birebir aynı SHA-256 değerini üretir:
  - Aynı `idempotency_key` / `(device_id, client_seq, operation_id)` ile ağ tekrarı (replay) yapıldığında ikinci bir `sales` veya `stock_movements` satırı oluşturulmaz (`200 OK`).
  - Aynı anahtarla gönderilen replay paketinde `payment_method` `'CARD'` iken `'CASH'` yapılırsa (veya `'CREDIT_CARD'` iken `'CARD'` yapılırsa) SHA-256 hash farkı backend tarafından yakalanır ve `409` ile reddedilir.

---

## 5. Eski Kayıtlar İçin Geriye Dönük Uyumluluk Kararı ve Stratejisi

- **Depo DB Taraması:** Depoda `*.db`, `*.sqlite`, `*.sqlite3` araması yapılmış; canlı istemci veya üretim veritabanı bulunmadığı, yalnızca `test_spikes/spike_01_backend/backups/*.db` ve `build/{service_test,test_aot}.db` spike test artifaktlarının bulunduğu doğrulanmıştır.
- **Kontrolsüz Dönüşüm Yasağı İlkesi:** Daha önce oluşturulmuş kalıcı Outbox kayıtları veya `processed_operations` kayıtları üzerinde arka planda otomatik/sessiz string güncellemesi veya silme işlemi yapılmaz (hash bozulmasını ve fiziksel satış verisi kaybını önlemek için).
- **İki Senaryolu Güvenli Uyumluluk Stratejisi:**
  1. **Hub'da Önceden Commit Edilmiş Legacy `'CREDIT_CARD'` İşlemleri (ACK Kaybı Senaryosu):** Backend `/api/v1/sales` idempotency kontrolünü `PaymentMethod` doğrulamasından **önce** yaptığı için, daha önce commit edilmiş bir `'CREDIT_CARD'` işleminin birebir aynı payload ve hash ile tekrarı `200 OK` idempotent replay olarak güvenle kurtarılır; payload mutasyona uğratılırsa `409` hash conflict fırlatılır (Test #15 ile doğrulandı).
  2. **İstemci Outbox'ında Henüz Senkronize Olmamış Legacy `'CREDIT_CARD'` Kaydı:** Mevcut Outbox payload'ına ve hash'ine dokunulmaz. `ClientSyncService` kaydı Hub'a gönderdiğinde backend kalıcı doğrulama reddi (`400 ERR_INVALID_PAYMENT_METHOD`) döner; `ClientSyncService` yerel satışı (`local_sales`) kesinlikle silmeden Outbox kaydını `FAILED_PERMANENT` (`lastErrorCode = 'ERR_INVALID_PAYMENT_METHOD'`) statüsüne alır ve FIFO sırasını güvenli şekilde durdurur (Paket Test #4 ile doğrulandı). Salt-okunur tanı/raporlama katmanı `PaymentMethod.tryParseLegacyReadOnly` ile tarihsel değeri `PaymentMethod.card`/`cash` olarak okuyabilir; kontrollü onarım gerektiğinde operatör/bakım aracı üzerinden `ClientStorageRepository.updateAndRetryFailedOperation` ile `'CARD'`'a yükseltilip SHA-256 hash yeniden hesaplanabilir (bu metod da `PaymentMethod.parse` ile korunur).

---

## 6. Gerçek Komut Çıktılarıyla Test ve Analiz Sonuçları

Tüm kaynak, test ve kanonik doküman değişiklikleri tamamlandıktan sonra üç paketin tamamında çalıştırılan gerçek terminal doğrulamaları aşağıdadır:

| Paket / Kapsam | Çalıştırılan Komutlar | Gözlemlenen Sonuç |
|---|---|---|
| **Kök Flutter Uygulaması (`market-pos`)** | `flutter analyze --no-pub`<br/>`flutter test` | `No issues found! (ran in 2.0s)`<br/>`00:04 +33: All tests passed!` *(5 test dosyası, 33 test; 0 hata, 0 atlama)* |
| **İstemci Depolama Paketi (`packages/mms_client_storage`)** | `dart analyze`<br/>`dart test` | `No issues found!`<br/>`00:28 +55: All tests passed!` *(5 test dosyası, 55 test; 0 hata, 0 atlama)* |
| **Master Hub Spike Backend (`test_spikes/spike_01_backend`)** | `dart analyze`<br/>`dart test` | `No issues found!`<br/>`00:35 +143: All tests passed!` *(14 test dosyası, 143 test; 0 hata, 0 atlama)* |
| **Toplam** | Tüm analizler ve tüm test süitleri | **0 Analyzer Hatası / 231 Test %100 Yeşil (0 Başarısız, 0 Atlanan)** *(Faz 1.1 sonundaki 221 test üzerine +10 yeni `PaymentMethod` sözleşme testi)* |

### İstenen 8 Doğrulama Senaryosunun Eşleştirmesi

| # | Doğrulama Senaryosu | Doğrulayan Test(ler) |
|---|---|---|
| 1 | `CASH` satış oluşturma ve saklama | [`packages/mms_client_storage/test/payment_method_contract_test.dart`](../../packages/mms_client_storage/test/payment_method_contract_test.dart) (#2), [`test/core/storage/payment_method_contract_test.dart`](../../test/core/storage/payment_method_contract_test.dart) (#1) |
| 2 | `CARD` satış oluşturma ve saklama | Yukarıdaki (#2, #1), [`s5a3_live_hub_integration_test.dart`](../../packages/mms_client_storage/test/s5a3_live_hub_integration_test.dart), [`s5a3_sales_validation_test.dart`](../../test_spikes/spike_01_backend/test/s5a3_sales_validation_test.dart) (#12) |
| 3 | Geçersiz ödeme yönteminin backend tarafından reddedilmesi | [`s5a3_sales_validation_test.dart`](../../test_spikes/spike_01_backend/test/s5a3_sales_validation_test.dart) (#13 — `CREDIT_CARD`, `NAKIT`, `cash`, `''`, `BANK_TRANSFER`, eksik alan, `null`, `int` tip) |
| 4 | Outbox payload içinde kanonik değerlerin doğrulanması | [`packages/mms_client_storage/test/payment_method_contract_test.dart`](../../packages/mms_client_storage/test/payment_method_contract_test.dart) (#2), [`test/core/storage/payment_method_contract_test.dart`](../../test/core/storage/payment_method_contract_test.dart) (#1), [`s5a3_outbox_sync_test.dart`](../../packages/mms_client_storage/test/s5a3_outbox_sync_test.dart) |
| 5 | Idempotent gönderimde duplicate oluşmaması | [`s5a3_sales_validation_test.dart`](../../test_spikes/spike_01_backend/test/s5a3_sales_validation_test.dart) (#12 `CARD` replay `200`, #14 `CARD`->`CASH` değişiminde `409`), [`s5a3_live_hub_integration_test.dart`](../../packages/mms_client_storage/test/s5a3_live_hub_integration_test.dart) |
| 6 | SHA-256 hash bütünlüğünün korunması | [`packages/mms_client_storage/test/payment_method_contract_test.dart`](../../packages/mms_client_storage/test/payment_method_contract_test.dart) (#2, #4), [`test/core/storage/payment_method_contract_test.dart`](../../test/core/storage/payment_method_contract_test.dart) (#1), [`s5a3_sales_validation_test.dart`](../../test_spikes/spike_01_backend/test/s5a3_sales_validation_test.dart) (#14, #15) |
| 7 | Eski `'CREDIT_CARD'` ve `'NAKIT'` test fixture'larının temizlenmesi | [`s5a3_outbox_sync_test.dart`](../../packages/mms_client_storage/test/s5a3_outbox_sync_test.dart), [`s5a3_live_hub_integration_test.dart`](../../packages/mms_client_storage/test/s5a3_live_hub_integration_test.dart), [`s5a2_durability_lifecycle_test.dart`](../../test_spikes/spike_01_backend/test/s5a2_durability_lifecycle_test.dart), [`s4_device_pairing_test.dart`](../../test_spikes/spike_01_backend/test/s4_device_pairing_test.dart) + repo taraması |
| 8 | Geriye dönük eski kayıt uyumluluğu | [`packages/mms_client_storage/test/payment_method_contract_test.dart`](../../packages/mms_client_storage/test/payment_method_contract_test.dart) (#4 — Outbox bozulmaz, `FAILED_PERMANENT` + satış korunur), [`s5a3_sales_validation_test.dart`](../../test_spikes/spike_01_backend/test/s5a3_sales_validation_test.dart) (#15 — legacy `CREDIT_CARD` replay `200` / mutation `409`) |

---

## 7. Açık Riskler ve Kapsam Dışı Kalan Konular

1. **Yerel İstemci SQLite `CHECK` Kısıtı:** Bu görevde gereksiz DB şeması ve migration değişikliği yapılmaması kuralı gereğince `local_sales.payment_method` kolonuna SQL düzeyinde `CHECK (payment_method IN ('CASH', 'CARD'))` eklenmemiştir. Doğrulama uygulama katmanında [`PaymentMethod`](../../packages/mms_client_storage/lib/src/models/payment_method.dart), [`ClientStorageRepository`](../../packages/mms_client_storage/lib/src/database/client_storage_repository.dart) ve Backend [`POST /api/v1/sales`](../../test_spikes/spike_01_backend/bin/server.dart) sınırlarında uygulanmaktadır. İstemci tarafında gelecekte şema sürümü artırımı gerektiren bir fazda (gerek görülürse) `CHECK` kısıtı değerlendirilebilir; merkezi PostgreSQL/SaaS şemasında ([`DATA_MODEL.md`](../architecture/DATA_MODEL.md)) `CHECK` kısıtı tasarım gereği mevcuttur.
2. **Backend Ayrı Bir Batch `/sync` Endpoint'i:** Şu anda senkronizasyon akışı [`HttpSyncTransport`](../../packages/mms_client_storage/lib/src/sync/client_sync_service.dart) üzerinden doğrudan `POST /api/v1/sales` ucunu kullanmaktadır. İleride toplu `/sync` batch endpoint'i eklendiğinde aynı `PaymentMethod.isCanonical` doğrulaması o uçta da kullanılmalıdır.
3. **Tarihsel Ön-İnceleme Snapshot Belgeleri:** [`PHASE_1_2_PREPARATION_REPORT.md`](./PHASE_1_2_PREPARATION_REPORT.md) ve [`PHASE_1_2_FINAL_PREFLIGHT_REPORT.md`](./PHASE_1_2_FINAL_PREFLIGHT_REPORT.md) belgeleri düzeltme öncesi tespiti belgelemesi nedeniyle geçmiş kaydı olarak korunmuştur.
4. **Faz 1.2 POS Kodlaması ve Pilot Koşulları:** Faz 1.2 POS/Sepet/Ödeme UI kodlaması henüz başlatılmamıştır; Faz 2 Device ID/pairing ve `B-2`/`B-3`/SCM/ACL/fiziksel mobil saha koşulları kendi fazlarında ele alınacaktır.

---

## 8. Git Branch ve Çalışma Ağacı Durumu

- **Aktif Branch:** `main`
- **Son Commit & Uzak Eşitlik:** `32111b8 docs(audit): document DT-01 developer tooling audits and Phase 1.1 git execution` (`HEAD == origin/main`, `0` ileride / `0` geride)
- **Staged Değişiklikler (`git diff --cached --stat`):** Yok *(hiçbir dosya stage edilmedi)*.
- **Unstaged Değişiklikler (`git status --short` — `M`):** 14 dosya (`docs/PROJECT_STATUS.md`, `docs/REQUIREMENTS.md`, `docs/architecture/DATA_MODEL.md`, `docs/architecture/DATA_MODEL_DECISIONS.md`, `docs/requirements/BUSINESS_RULES_SPEC.md`, `packages/mms_client_storage/lib/mms_client_storage.dart`, `packages/mms_client_storage/lib/src/database/client_database.dart`, `packages/mms_client_storage/lib/src/database/client_storage_repository.dart`, `packages/mms_client_storage/test/s5a3_live_hub_integration_test.dart`, `packages/mms_client_storage/test/s5a3_outbox_sync_test.dart`, `test_spikes/spike_01_backend/bin/server.dart`, `test_spikes/spike_01_backend/test/s4_device_pairing_test.dart`, `test_spikes/spike_01_backend/test/s5a2_durability_lifecycle_test.dart`, `test_spikes/spike_01_backend/test/s5a3_sales_validation_test.dart`; *not: `PROJECT_STATUS.md`, `REQUIREMENTS.md` ve `BUSINESS_RULES_SPEC.md` üzerinde önceki `OD-01..OD-04` UX kabul değişiklikleri de commitlenmemiş durumdadır*).
- **Untracked Dosyalar/Klasörler (`git status --short` — `??`):** Bu görevle eklenen [`packages/mms_client_storage/lib/payment_method.dart`](../../packages/mms_client_storage/lib/payment_method.dart), [`packages/mms_client_storage/lib/src/models/payment_method.dart`](../../packages/mms_client_storage/lib/src/models/payment_method.dart), [`packages/mms_client_storage/test/payment_method_contract_test.dart`](../../packages/mms_client_storage/test/payment_method_contract_test.dart), [`test/core/storage/payment_method_contract_test.dart`](../../test/core/storage/payment_method_contract_test.dart) ve [`docs/development/PHASE_1_2_PAYMENT_CONTRACT_FIX_REPORT.md`](./PHASE_1_2_PAYMENT_CONTRACT_FIX_REPORT.md) *(artı önceki teslimatlardan kalan `docs/development/PHASE_1_1_GIT_EXECUTION_REPORT.md`, `docs/development/PHASE_1_2_PREPARATION_REPORT.md`, `docs/development/PHASE_1_2_FINAL_PREFLIGHT_REPORT.md`, `docs/ui-ux/`, `docs/ui-ux.zip`)*.
- **Git Eylemi:** Proje Sahibinin açık onayı olmadan `git add`, `git commit` veya `git push` çalıştırılmamıştır.

---

**Sonraki Adım:** Proje Sahibinin bu raporu inceleyerek `PaymentMethod` (`'CASH'` / `'CARD'`) standardizasyonunu onaylaması ve ardından Faz 1.2 POS/Sepet TDD kodlaması için başlatma onayı vermesi beklenmektedir.

