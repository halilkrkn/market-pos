# PHASE 1.2 PRE-WORK — LEGACY OUTBOX RECOVERY DOĞRULAMA RAPORU

**Belge Kodu:** `docs/development/PHASE_1_2_LEGACY_OUTBOX_RECOVERY_REPORT.md`  
**Tarih:** 12 Kasım 2026  
**Durum:** Tamamlandı — Proje Sahibi İnceleme ve Onayı Bekliyor  
**Dayanak Belge:** [`docs/development/PHASE_1_2_PAYMENT_CONTRACT_FIX_REPORT.md`](./PHASE_1_2_PAYMENT_CONTRACT_FIX_REPORT.md) (Bölüm 5)  
**Ana Anayasa ve Şartname:** [`AGENTS.md`](../../AGENTS.md), [`BUSINESS_RULES_SPEC.md`](../requirements/BUSINESS_RULES_SPEC.md) (v1.5)

---

## 1. İncelenen Metotlar, Çağrı Zinciri ve 7 Doğrulama Sorusunun Cevapları

### 1.1. Kaynak Kod Referansları ve Çağrı Zinciri

| Bileşen / Metot | Dosya ve Satır Aralığı | Rolü |
|---|---|---|
| `ClientStorageRepository.updateAndRetryFailedOperation()` | [`packages/mms_client_storage/lib/src/database/client_storage_repository.dart`](../../packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L441-L512) | Kalıcı hatalı (`FAILED_PERMANENT`) Outbox operasyonu için kontrollü onarım ve yeniden deneme giriş noktası. |
| `ClientStorageRepository._syncRepairedLocalSale()` | [`packages/mms_client_storage/lib/src/database/client_storage_repository.dart`](../../packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L516-L544) | `SALE_CREATE` onarımında aynı transaction içinde `local_sales` satırının ödeme yöntemi ve tutar tutarlılığını doğrular/eşitler. |
| `ClientStorageRepository.computeSaleRequestHash()` | [`packages/mms_client_storage/lib/src/database/client_storage_repository.dart`](../../packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L19-L27) | `client_seq`, `total_amount`, `payment_method`, `items` alanlarından kanonik SHA-256 hash üretir (değiştirilmedi). |
| `ClientStorageRepository.retryFailedPermanentOperation()` | [`packages/mms_client_storage/lib/src/database/client_storage_repository.dart`](../../packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L427-L436) | Yükü ve hash'i değiştirmeden yalnız statüyü `PENDING`'e çeker (payload değişmeyecek dış kurtarma durumları içindir; eski `'CREDIT_CARD'` yükünü tek başına onarmaz). |
| `ClientStorageRepository.getFailedPermanentOperations()` | [`packages/mms_client_storage/lib/src/database/client_storage_repository.dart`](../../packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L419-L424) | Cihaza ait `FAILED_PERMANENT` kayıtları `clientSeq ASC` sırasıyla listeler. |
| `LocalDatabaseService.updateAndRetryFailedOperation()` | [`lib/core/storage/local_database_service.dart`](../../lib/core/storage/local_database_service.dart#L527-L534) | Flutter masaüstü uygulamasında aktif DB drain koruması (`_service.runOperation`) ile `ClientStorageRepository.updateAndRetryFailedOperation()`'a delege eder (imza korundu, değiştirilmedi). |
| `ClientSyncService.syncPendingOutbox()` | [`packages/mms_client_storage/lib/src/sync/client_sync_service.dart`](../../packages/mms_client_storage/lib/src/sync/client_sync_service.dart#L49-L166) | En küçük `client_seq` bekleyen/hatalı kaydı sorgular (`L68-74`), `FAILED_PERMANENT` gördüğünde kuyruğu durdurur (`L83-87`), onarım sonrası `PENDING` kaydını `HttpSyncTransport.postSale` üzerinden Hub'a gönderir ve 200/201 yanıtında `markOutboxSynced()` (`L113-118`, repo `L352-382`) ile ACK işler. |
| `SpikeServer.computeSaleRequestHash()` | [`test_spikes/spike_01_backend/bin/server.dart`](../../test_spikes/spike_01_backend/bin/server.dart#L119-L127) | İstemcideki `computeSaleRequestHash()` ile birebir aynı 4 alan ve JSON SHA-256 hesaplamasını çalıştırır. |
| `SpikeServer` (`POST /api/v1/sales`) | [`test_spikes/spike_01_backend/bin/server.dart`](../../test_spikes/spike_01_backend/bin/server.dart#L946-L1293) | Önce `processedOperations` idempotency defterini (`L999-1029`), yeni kayıtlarda `PaymentMethod.isCanonical(rawPaymentMethod)` doğrulamasını (`L1034-1045`) çalıştırıp atomik satış + stok + `processedOperations` commit'i (`L1049-1286`) yapar. |

**Çağrı Zinciri:**
`syncPendingOutbox()` (`L103` Hub'a `'CREDIT_CARD'` gönderimi -> `400 ERR_INVALID_PAYMENT_METHOD` -> `L144` `markOutboxPermanentFail()`) -> kuyruk `FAILED_PERMANENT` ile durur -> operatör/onarım katmanı `getFailedPermanentOperations()` ile kaydı inceler -> `(LocalDatabaseService.)updateAndRetryFailedOperation(operationId, correctedPayload: ...)` -> tek `db.transaction` içinde `outbox_operations` + `local_sales` güncellenir ve `PENDING` olur -> bir sonraki `syncPendingOutbox()` çağrısı `clientSeq ASC` sırayla kaydı Hub `/api/v1/sales` ucuna gönderir -> Hub `201 Created` (tekrarda `200 OK` + `x-mms-idempotent-replay: true`) döner -> `markOutboxSynced()` Outbox'ı `SYNCED` yapar ve `lastSyncedSeq`'i ilerletir.

### 1.2. Ön İncelemede Tespit Edilen Eksikler (Pre-Verification Baseline) ve TDD Sıkılaştırması

İlk kaynak kod incelemesinde (`client_storage_repository.dart:438-459` eski hâli) 5 gerçek boşluk tespit edilmiştir:
1. Metot `db.transaction(() async { ... })` içinde çalışmıyordu; yalnız tek çıplak `db.update(db.outboxOperations)...write(...)` çalıştırıyordu.
2. Hedef `operationId`'nin veritabanında mevcut olup olmadığı ve `status == 'FAILED_PERMANENT'` durumunda bulunup bulunmadığı kontrol edilmiyordu (olmayan ID sessizce geçiyor, `SYNCED`/`PENDING` kayıtların üzerine yazılabiliyordu).
3. `correctedPayload` içindeki `'operation_id'` ve `'client_seq'` değerlerinin mevcut Outbox satırıyla (`existing.operationId`, `existing.clientSeq`) eşleştiği doğrulanmıyordu; ayrıca `'payment_method'` anahtarı tamamen eksikse `containsKey('payment_method')` atlanıyordu.
4. `SALE_CREATE` için `local_sales.payment_method` güncellenmediğinden onarım ve Master Hub senkronizasyonu sonrasında Hub (`'CARD'`) ve Outbox (`'CARD'`) ile istemci `local_sales` (`'CREDIT_CARD'`) arasında veri tutarsızlığı kalıyordu.

Bu boşluklar **DB şeması, bağımlılıklar, `computeSaleRequestHash()`, metot imzası (`LocalDatabaseService` uyumu) ve mimari yapı değiştirilmeden** doğrudan `updateAndRetryFailedOperation()` içinde TDD (Red -> Green) döngüsüyle kapatılmıştır.

### 1.3. Bölüm 1'deki 7 Soruya Kesin Cevaplar

1. **Eski payload içindeki `CREDIT_CARD` değeri kontrollü biçimde `CARD` olarak değiştirilebiliyor mu?**  
   **Evet.** `updateAndRetryFailedOperation()` çağıranın sağladığı `correctedPayload` içindeki `payment_method` alanını `SALE_CREATE` operasyonlarında zorunlu olarak `PaymentMethod.parse(...)` ile doğrular (`L471-473`). Eski `'CREDIT_CARD'` değeri kontrollü biçimde `'CARD'` yapılabilir; buna karşılık `CREDIT_CARD`'ın `'CASH'`'e sessizce çevrilmesi (`_syncRepairedLocalSale`, `L533-538`) veya geçersiz/eksik değer geçirilmesi `ArgumentError` ile engellenir.
2. **Payload değiştirildiğinde `payload_hash` yeniden hesaplanıyor mu?**  
   **Evet.** Güncelleme yazılmadan hemen önce `final payloadHash = computeSaleRequestHash(correctedPayload);` (`L489`) çağrılır ve `OutboxOperationsCompanion.payloadHash` (`L495`) güncellenir.
3. **Yeniden hesaplanan hash, backend `computeSaleRequestHash()` algoritmasıyla birebir aynı mı?**  
   **Evet.** [`ClientStorageRepository.computeSaleRequestHash`](../../packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L19-L27) ile [`SpikeServer.computeSaleRequestHash`](../../test_spikes/spike_01_backend/bin/server.dart#L119-L127) birebir aynı 4 anahtarı (`'client_seq'`, `'total_amount'`, `'payment_method'`, `'items'`) aynı sırayla `jsonEncode` -> `sha256` olarak hesaplar (hem testlerde hem E2E canlı Hub testinde birebir eşitlik kanıtlandı).
4. **Operation ID, device ID, client sequence ve idempotency bilgileri korunuyor mu?**  
   **Evet.** Veritabanı sütunları (`operationId`, `deviceId`, `clientSeq`, `operationType`, `occurredAt`, `createdAt`) `OutboxOperationsCompanion` ile kesinlikle değiştirilmez (`L493-500`). Ek olarak JSON içindeki `correctedPayload['operation_id'] == existing.operationId` (`L458-462`) ve `correctedPayload['client_seq'] == existing.clientSeq` (`L463-467`) doğrulamalarıyla idempotency anahtarı (`$deviceId:$clientSeq`) tam korunur.
5. **İşlem atomik SQLite transaction içinde mi gerçekleştiriliyor?**  
   **Evet (sıkılaştırma sonrası).** Tüm okuma, statü/kimlik/tutar doğrulama, `outbox_operations` güncellemesi ve `local_sales` eşitlemesi tek bir `await db.transaction(() async { ... });` (`L445-511`) bloğu içinde yürütülür. *(Not: Ön incelemede bu sarmalayıcı eksikti; TDD kapsamında eklendi.)*
6. **Başarısız onarımda eski payload ve hash korunuyor mu?**  
   **Evet.** Doğrulama hataları (`StateError`, `ArgumentError`) veya transaction içindeki SQLite yazma hataları (ör. trigger/constraint `ABORT`) transaction rollback tetikler; `outbox_operations.payload`, `payloadHash`, `status` (`'FAILED_PERMANENT'`), `attemptCount`, `lastError` ve `local_sales.payment_method` değişmeden korunur.
7. **`FAILED_PERMANENT` kaydı tekrar gönderilebilir duruma doğru biçimde geçiriliyor mu?**  
   **Evet.** Metot öncelikle `existing.status == 'FAILED_PERMANENT'` (`L453-457`) şartını zorunlu kılar (`PENDING`, `RETRY`, `IN_PROGRESS`, `SYNCED` kayıtları reddeder), ardından `status: 'PENDING'`, `attemptCount: 0`, `nextRetryAt: null`, `lastError: null` (`L496-499`) atar. Bu alanlar `ClientSyncService.syncPendingOutbox()` (`client_sync_service.dart:68-74`) sorgusuyla doğrudan eşleşir.

---

## 2. Payload ve Hash Onarım Mekanizması

[`updateAndRetryFailedOperation()`](../../packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L441-L512) çağrıldığında işletilen mekanizma:

1. Mevcut `outbox_operations` satırı `operationId` ile okunur; kayıt yoksa veya `status != 'FAILED_PERMANENT'` ise `StateError` fırlatılır.
2. `correctedPayload['operation_id']` ve `correctedPayload['client_seq']` değerlerinin mevcut satırla birebir aynı olduğu doğrulanır.
3. `operationType == 'SALE_CREATE'` için:
   - `PaymentMethod.parse(correctedPayload['payment_method'])` çalıştırılır (`'CASH'` veya `'CARD'` dışındaki her değer — `'CREDIT_CARD'`, `'NAKIT'`, `null`, eksik alan vb. — `ArgumentError` fırlatır).
   - `total_amount` pozitif `int`, `items` boş olmayan `List` olarak doğrulanır.
4. `jsonEncode(correctedPayload)` ve değişmemiş `computeSaleRequestHash(correctedPayload)` üretilip `outbox_operations` kaydı `PENDING` olarak güncellenir.
5. Aynı transaction içinde [`_syncRepairedLocalSale`](../../packages/mms_client_storage/lib/src/database/client_storage_repository.dart#L516-L544) ilgili `local_sales` satırını `(deviceId, clientSeq)` ile bulur:
   - `repairedTotalAmount == localSale.totalAmount` şartını doğrular (satış tutarının gizlice değiştirilmesini önler).
   - `PaymentMethod.tryParseLegacyReadOnly(localSale.paymentMethod)` üzerinden ödeme ailesinin değişmediğini doğrular (`'CREDIT_CARD'` -> `'CASH'` sessiz değişimini engeller).
   - `local_sales.paymentMethod` değeri kanonik değere (`'CARD'`) güncellenir.

---

## 3. Transaction ve Rollback Davranışı

- **İlk denetimde tespit edilen risk:** Önceki `client_storage_repository.dart:438-459` sürümü açık `db.transaction` açmadığı ve `local_sales` satırını güncellemediği için çok adımlı rollback mekanizmasına sahip değildi; bunu TDD Red aşamasında gerçek test hata çıktısı (`Expected: throws anything -> returned a Future that emitted <null>`) ile doğruladık.
- **Sıkılaştırma sonrası davranış:** `db.transaction` içinde önce `outbox_operations` satırı güncellenir, ardından `_syncRepairedLocalSale()` ile `local_sales` güncellenir/doğrulanır.
- **Kanıtlanan Rollback Senaryoları:**
  1. *Uygulama doğrulama hatası:* `outbox_operations` güncellendikten hemen sonra `_syncRepairedLocalSale` içinde `'CREDIT_CARD' -> 'CASH'` veya `total_amount` uyuşmazlığı yakalanıp `ArgumentError` fırlatıldığında Drift/SQLite `ROLLBACK` işletir; ilk `UPDATE` geri alınır.
  2. *Veritabanı katmanı hatası:* FFI SQLite üzerinde `local_sales` tablosuna `BEFORE UPDATE ... SELECT RAISE(ABORT, ...)` `TEMP TRIGGER` eklendiğinde, ilk `UPDATE outbox_operations` sonrası tetiklenen SQLite `ABORT` hatası tüm transaction'ı geri alır; `outbox_operations` (`payload`, `payloadHash`, `status == 'FAILED_PERMANENT'`, `attemptCount`, `lastError`) ve `local_sales.payment_method == 'CREDIT_CARD'` bozulmadan kalır.

---

## 4. FIFO Davranışı (`FAILED_PERMANENT` Kuyruk Blokajı ve Devamı)

[`ClientSyncService.syncPendingOutbox()`](../../packages/mms_client_storage/lib/src/sync/client_sync_service.dart#L66-L150) katı deterministik FIFO (`clientSeq ASC`) uygular:

1. Her döngüde `status IN ('PENDING', 'RETRY', 'FAILED_PERMANENT')` kümesinden **yalnızca en küçük `client_seq`** kaydını (`limit(1)`) seçer (`L68-74`).
2. Eğer en küçük sıradaki kayıt `FAILED_PERMANENT` ise (`L83-87`), kuyruk döngüsü `break` ile sonlandırılır (`stopError` set edilir, `permanentFailedCount++`). **Sonraki satışlar (`seq 2, 3, ...`) ASLA atlanıp gönderilmez.** Bu sırada kasa satışları yerel DB'de offline olarak oluşturulmaya devam edebilir (`local_sales` + `PENDING` Outbox).
3. Eski kayıt `updateAndRetryFailedOperation()` ile onarılıp `status = 'PENDING'` ve `nextRetryAt = null` yapıldıktan sonra çağrılan `syncPendingOutbox()`:
   - Önce `seq 1`'i (onarılan `'CARD'` satışı) Hub'a gönderip ACK alır (`SYNCED`, `lastSyncedSeq = 1`),
   - Hemen ardından bekleyen `seq 2`, `seq 3` ... kayıtlarını `client_seq ASC` sırayla Hub'a iletip senkronize eder.

---

## 5. Eklenen Testler, TDD Kanıtı ve Gerçek Komut Sonuçları

### 5.1. Eklenen / Genişletilen Testler

| Test Dosyası | Kapsam |
|---|---|
| [`packages/mms_client_storage/test/payment_method_contract_test.dart`](../../packages/mms_client_storage/test/payment_method_contract_test.dart#L239-L654) | **Test #5:** Kayıt yokluğu (`StateError`), `PENDING` kaydın onarım reddi (`StateError`), `operation_id`/`client_seq`/eksik `payment_method`/`CREDIT_CARD->CASH`/`total_amount` tamper rollback (`ArgumentError`), gerçek FFI SQLite `TEMP TRIGGER` ile multi-table `ROLLBACK` kanıtı ve başarılı atomik onarım (`outbox_operations` + `local_sales`).<br/>**Test #6:** `seq 1` `CREDIT_CARD` (`400` -> `FAILED_PERMANENT`) iken `seq 2` `CASH` satışının bloke edilmesi (`attemptedSeqs == [1]`), `updateAndRetryFailedOperation()` sonrası `[1, 1, 2]` FIFO sırayla senkronizasyon devamı. |
| [`test_spikes/spike_01_backend/test/legacy_outbox_recovery_e2e_test.dart`](../../test_spikes/spike_01_backend/test/legacy_outbox_recovery_e2e_test.dart#L1-L356) | **Canlı Master Hub E2E (Bölüm 2 Adım 1–11 + FIFO + Rollback):** Gerçek `SpikeServer` (`127.0.0.1:8967`) + FFI `SpikeDatabase` ve gerçek FFI `ClientDatabase` + `HttpSyncTransport` + `ClientSyncService` ile:<br/>1) `CREDIT_CARD` eski Outbox + `local_sales`/`local_sale_items`/`local_stock_movements`/stok oluşturma;<br/>2) Hub gönderimi -> `400 ERR_INVALID_PAYMENT_METHOD` -> `FAILED_PERMANENT`;<br/>3) Yerel satış/stok hareketi korunumu, Hub'da `0` satış;<br/>4) `seq 2` `CASH` eklenip FIFO blokajının doğrulanması;<br/>5) SQLite `TEMP TRIGGER` ile başarısız onarımda rollback kanıtı;<br/>6) `updateAndRetryFailedOperation` ile `'CARD'` onarımı, hash'in `SpikeServer.computeSaleRequestHash` ile eşleşmesi, `operation_id`/`device_id`/`client_seq` korunumu, `PENDING` geçişi;<br/>7) Live Hub'a FIFO (`seq 1 CARD`, `seq 2 CASH`) aktarımı ve Hub `sales`/`stock_movements`/`products` doğrulaması;<br/>8) Aynı `'CARD'` payload tekrarında HTTP `200` (`x-mms-idempotent-replay: true`) ve duplicate satış/stok düşüşü olmaması;<br/>9) İstemci `local_sales` (`'CARD'`), `outbox_operations` (`SYNCED`, `acknowledgedAt != null`) ve `lastSyncedSeq == 2` tutarlılığı. |
| [`test/core/storage/payment_method_contract_test.dart`](../../test/core/storage/payment_method_contract_test.dart#L86-L151) | **Test #3:** Flutter istemcisi [`LocalDatabaseService.repository`](../../lib/core/storage/local_database_service.dart) (`updateAndRetryFailedOperation`) üzerinden eski `'CREDIT_CARD'` kaydının atomik `'CARD'` onarımını doğrular. |

### 5.2. TDD Red -> Green Kanıtı ve Güncellenen Test Binary Notu

- **Red Aşaması (düzeltme öncesi):**
  - `dart test test/payment_method_contract_test.dart` (`packages/mms_client_storage`): Test #5 satır 329'da `StateError` beklenirken `<null>` dönerek başarısız oldu (`+5 -1`).
  - `dart test test/legacy_outbox_recovery_e2e_test.dart` (`test_spikes/spike_01_backend`): `local_sales` trigger rollback testinde metot `local_sales`'a dokunmadığı ve hata fırlatmadığı için satır 282'de başarısız oldu (`+0 -1`).
- **Eski Binary Yenilemesi:** Ön incelemede `.gitignore` kapsamındaki `test_spikes/spike_01_backend/build/mms_backend.exe` dosyasının 6 Kasım 2026'dan kalma olduğu tespit edildi; `packages/mms_client_storage/test/s5a3_live_hub_integration_test.dart` bu çalıştırılabilir dosyayı başlattığı için [`scripts/build_aot.ps1`](../../test_spikes/spike_01_backend/scripts/build_aot.ps1) çalıştırılarak güncel `bin/server.dart` üzerinden `mms_backend.exe` (`8.22 MB`, SHA-256 `EB951395AAF506F2A67F9F9978AB8FC96E91D3D8444FB895656524C6449B71E8`) yeniden derlendi.

### 5.3. Son Düzenlemeler Sonrası Çalıştırılan Gerçek Doğrulama Sonuçları

| Kapsam | Komutlar | Gözlemlenen Sonuç |
|---|---|---|
| **Kök Flutter (`market-pos`)** | `flutter analyze --no-pub`<br/>`flutter test` | `No issues found! (ran in 2.8s)`<br/>`00:06 +34: All tests passed!` *(5 dosya, 34 test; 0 hata, 0 atlanan)* |
| **İstemci Depolama (`packages/mms_client_storage`)** | `dart analyze`<br/>`dart test` | `No issues found!`<br/>`00:33 +57: All tests passed!` *(5 dosya, 57 test; 0 hata, 0 atlanan)* |
| **Spike Backend (`test_spikes/spike_01_backend`)** | `dart analyze`<br/>`dart test` | `No issues found!`<br/>`00:47 +144: All tests passed!` *(15 dosya, 144 test; 0 hata, 0 atlanan)* |
| **Toplam** | Tüm paket analizleri + tüm test süitleri | **0 Analyzer Hatası / 235 Otomatik Test %100 Yeşil (0 Başarısız, 0 Atlanan)** |

---

## 6. Açık Riskler ve Kapsam Dışı Mimari Öneriler (Yalnızca Raporlandı)

1. **Head-of-Line FIFO Blokajı ve Operatör Onarım Arayüzü Eksikliği:** Katı FIFO gereği bir cihazda tek bir `FAILED_PERMANENT` kaydı arkasındaki tüm yeni satışların Hub'a aktarımını durdurur. Mevcut `lib/` UI katmanında `getFailedPermanentOperations()` / `updateAndRetryFailedOperation()` akışını tetikleyen bir operatör kurtarma ekranı henüz yoktur. *(Öneri — bu görevde uygulanmadı: İlgili Faz UI/Operasyon adımında `FAILED_PERMANENT` uyarı rozeti ve kontrollü onarım diyaloğu planlanmalıdır; stok ve nedensellik bütünlüğü nedeniyle FIFO atlama tavsiye edilmez.)*
2. **İstemci Tarafı Ödeme Düzeltme Audit Tablosu (`BR-PAY-05`):** Pilot `ClientDatabase` (`schemaVersion: 1`) içinde `audit_logs` veya `payment_method_corrections` tablosu henüz yoktur. Şu an `_syncRepairedLocalSale` yalnız eski string normalize (`CREDIT_CARD -> CARD`, `NAKIT -> CASH`) için güncelleme yapar ve yöntem ailesi değişimine (`CASH <-> CARD`) izin vermez.
3. **AOT Binary Güncel Tutma Disiplini:** `test_spikes/spike_01_backend/bin/server.dart` değiştiğinde harici EXE testi (`s5a3_live_hub_integration_test.dart`) için `build_aot.ps1` çalıştırılması gerekir (aksi halde eski binary test edilir).
4. **Yerel İstemci SQLite `CHECK` Kısıtı:** Şema değişikliği yapılmaması sınırı gereği `local_sales.payment_method` kolonunda SQL düzeyi `CHECK` yoktur; koruma uygulama/repository ve backend API sınırlarında sağlanmaktadır.

---

## 7. Git Durumu

- **Aktif Branch ve Eşitlik:** `main` (`32111b8 docs(audit): document DT-01 developer tooling audits and Phase 1.1 git execution`), `HEAD == origin/main` (`0` ileride / `0` geride).
- **Staged Değişiklikler (`git diff --cached --stat`):** Yok *(hiçbir dosya stage edilmedi)*.
- **Sınır Kontrolleri:**
  - `git diff -- lib/ pubspec.yaml packages/mms_client_storage/pubspec.yaml test_spikes/spike_01_backend/pubspec.yaml`: **Boş** (Flutter UI ve `pubspec.yaml` dosyalarına dokunulmadı).
  - `packages/mms_client_storage/lib/src/database/client_database.dart`: Yalnız önceki görevde güncellenen `L56` yorum satırı diff'i mevcut; sıfır şema/DDL/migration değişikliği.
  - `build/mms_backend.exe` güncellemesi `.gitignore` (`build/`) altında kaldığından `git status` içine yeni artifakt eklemedi.
- **Çalışma Ağacındaki Tracked (`M` — 14 dosya) ve Untracked (`??`) Dosyalar:** Bu doğrulama turunda ek olarak yalnız `packages/mms_client_storage/lib/src/database/client_storage_repository.dart`, `packages/mms_client_storage/test/payment_method_contract_test.dart`, `test/core/storage/payment_method_contract_test.dart`, `test_spikes/spike_01_backend/test/legacy_outbox_recovery_e2e_test.dart` ve `docs/development/PHASE_1_2_LEGACY_OUTBOX_RECOVERY_REPORT.md` eklendi/güncellendi.
- **Git İşlemi:** `git add`, `git commit` ve `git push` çalıştırılmamıştır; Faz 1.2 POS geliştirmesi başlatılmamıştır.

---

**Durum:** Proje Sahibi incelemesi ve bir sonraki adım (commit talimatı veya Faz 1.2 POS kodlama onayı) beklenmektedir.

