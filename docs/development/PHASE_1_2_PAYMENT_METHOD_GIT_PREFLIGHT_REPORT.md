# PHASE 1.2 PRE-WORK — `PaymentMethod` & LEGACY OUTBOX RECOVERY GIT PRE-FLIGHT RAPORU

**Belge Kodu:** `docs/development/PHASE_1_2_PAYMENT_METHOD_GIT_PREFLIGHT_REPORT.md`  
**Tarih:** 12 Kasım 2026  
**Görev Türü:** Salt İnceleme / Git Preflight Denetimi *(Staging, Commit, Push, Kod Değişikliği YOK)*  
**Ana Anayasa:** [`AGENTS.md`](../../AGENTS.md) (§13 Git Automation Rules, §14 Forbidden Actions)

---

## 1. Branch ve HEAD Bilgisi

- **Aktif Branch:** `main` (`git branch --show-current`)
- **HEAD Commit:** `32111b8` — `docs(audit): document DT-01 developer tooling audits and Phase 1.1 git execution`
- **Önceki Son 2 Commit:** `2db892d` (AGENTS/GEMINI), `6b7898c` (Documentation Reconciliation)
- **Uzak Depo (`origin`):** `https://github.com/halilkrkn/market-pos.git` (`fetch` ve `push`)

---

## 2. `origin/main` Karşılaştırması

- **Komut:** `git rev-list --left-right --count HEAD...origin/main`
- **Gözlemlenen Çıktı:** `0	0`
- **Sonuç:** Yerel `main` dalı (`HEAD`) ile `origin/main` **birebir eşittir** (`0` commit ileride, `0` commit geride).

---

## 3. Tracked Değişikliklerin Listesi (`M` — 14 Dosya)

`git status -uall --short` çıktısında yer alan tüm `M` dosyalar:

| # | Dosya Yolu | `git diff --stat` | Kapsam Sınıflandırması |
| :---: |---|---|---|
| 1 | `docs/PROJECT_STATUS.md` | `38 ++--` | **KARIŞIK (Mixed):** Önceki `DT-01.2/3/4` + `UI/UX` kabulü + `OD-01..OD-04` + `PaymentMethod` birlikte |
| 2 | `docs/REQUIREMENTS.md` | `14 +-` | **KARIŞIK (Mixed):** Önceki `OD-01..OD-04` + `BR-STK`/`BR-POS` + `PaymentMethod` birlikte |
| 3 | `docs/architecture/DATA_MODEL.md` | `+1` | **SAF:** Yalnız `PaymentMethod` standardizasyon notu |
| 4 | `docs/architecture/DATA_MODEL_DECISIONS.md` | `+1` | **SAF:** Yalnız `PaymentMethod` kanonik sözleşme güncellemesi |
| 5 | `docs/requirements/BUSINESS_RULES_SPEC.md` | `96 ++--` | **KARIŞIK (Mixed):** Önceki `v1.3`/`v1.4` (`OD-01..04`, `BR-STK-04..10`) + `v1.5` (`PaymentMethod`) birlikte |
| 6 | `packages/mms_client_storage/lib/mms_client_storage.dart` | `+1` | **SAF:** `PaymentMethod` ihracı |
| 7 | `packages/mms_client_storage/lib/src/database/client_database.dart` | `2 +-` | **SAF:** Yalnız satır içi yorum güncellemesi (`L56`); DDL/şema değişikliği yok |
| 8 | `packages/mms_client_storage/lib/src/database/client_storage_repository.dart` | `120 ++-` | **SAF:** `PaymentMethod.parse`, `updateAndRetryFailedOperation` transaction/koruma sıkılaştırması, `_syncRepairedLocalSale` |
| 9 | `packages/mms_client_storage/test/s5a3_live_hub_integration_test.dart` | `4 +-` | **SAF:** `'CREDIT_CARD'` -> `'CARD'` fixture hizalama + `masterSales` doğrulamaları |
| 10 | `packages/mms_client_storage/test/s5a3_outbox_sync_test.dart` | `2 +-` | **SAF:** `'CREDIT_CARD'` -> `'CARD'` fixture hizalama |
| 11 | `test_spikes/spike_01_backend/bin/server.dart` | `18 +-` | **SAF:** `POST /api/v1/sales` katı `PaymentMethod` doğrulaması (`ERR_INVALID_PAYMENT_METHOD`) |
| 12 | `test_spikes/spike_01_backend/test/s4_device_pairing_test.dart` | `8 +-` | **SAF:** `'NAKIT'` -> `'CASH'` fixture hizalama (4 konum) |
| 13 | `test_spikes/spike_01_backend/test/s5a2_durability_lifecycle_test.dart` | `4 +-` | **SAF:** `'CREDIT_CARD'` -> `'CARD'` fixture hizalama (2 konum) |
| 14 | `test_spikes/spike_01_backend/test/s5a3_sales_validation_test.dart` | `+231` | **SAF:** Backend `PaymentMethod` doğrulama, red (`400`), `409` hash conflict ve legacy replay (`200`) testleri (#12–15) |

---

## 4. Untracked Dosyaların Listesi (`??` — 43 Dosya)

### 4.1. `PaymentMethod` ve Legacy Outbox Recovery Kapsamındaki Untracked Dosyalar (7 + bu rapor = 8 dosya)

1. [`packages/mms_client_storage/lib/payment_method.dart`](../../packages/mms_client_storage/lib/payment_method.dart)
2. [`packages/mms_client_storage/lib/src/models/payment_method.dart`](../../packages/mms_client_storage/lib/src/models/payment_method.dart)
3. [`packages/mms_client_storage/test/payment_method_contract_test.dart`](../../packages/mms_client_storage/test/payment_method_contract_test.dart)
4. [`test/core/storage/payment_method_contract_test.dart`](../../test/core/storage/payment_method_contract_test.dart)
5. [`test_spikes/spike_01_backend/test/legacy_outbox_recovery_e2e_test.dart`](../../test_spikes/spike_01_backend/test/legacy_outbox_recovery_e2e_test.dart)
6. [`docs/development/PHASE_1_2_PAYMENT_CONTRACT_FIX_REPORT.md`](./PHASE_1_2_PAYMENT_CONTRACT_FIX_REPORT.md)
7. [`docs/development/PHASE_1_2_LEGACY_OUTBOX_RECOVERY_REPORT.md`](./PHASE_1_2_LEGACY_OUTBOX_RECOVERY_REPORT.md)
8. [`docs/development/PHASE_1_2_PAYMENT_METHOD_GIT_PREFLIGHT_REPORT.md`](./PHASE_1_2_PAYMENT_METHOD_GIT_PREFLIGHT_REPORT.md) *(bu preflight raporu)*

### 4.2. Kapsam Dışındaki Untracked Dosyalar (35 dosya)

- **Önceki gelişim/hazırlık raporları (3 dosya):**
  - `docs/development/PHASE_1_1_GIT_EXECUTION_REPORT.md`
  - `docs/development/PHASE_1_2_PREPARATION_REPORT.md`
  - `docs/development/PHASE_1_2_FINAL_PREFLIGHT_REPORT.md`
- **Önceki kabul edilmiş UI/UX teslimatı (`docs/ui-ux/` — 32 dosya):**
  - `docs/ui-ux/DESIGN_DECISIONS.md` *(not: bu çalışmada içine `v1.4 INV-08` notu eklendi, ancak dosya önceki UI/UX klasör teslimatının parçasıdır)*
  - `docs/ui-ux/UX_07_FLUTTER_HANDOFF.md` *(not: bu çalışmada içine `v1.4` maddesi eklendi, ancak dosya önceki UI/UX klasör teslimatının parçasıdır)*
  - `docs/ui-ux/DESIGN_REFERENCES_AND_LICENSES.md`, `UX_01_FINAL_REVIEW_REPORT.md`, `UX_01_USER_RESEARCH.md`, `UX_01_USER_SCENARIOS_AND_PRODUCT_ANALYSIS.md`, `UX_02_INFORMATION_ARCHITECTURE.md`, `UX_03_DESIGN_SYSTEM.md`, `UX_04_SCREEN_DESIGNS.md`, `UX_05_INTERACTIVE_PROTOTYPE.md`, `UX_06_USABILITY_VALIDATION.md`, `UX_FINAL_DELIVERY_REPORT.md`, `UX_FINAL_VERIFICATION_AND_RECONCILIATION_REPORT.md`, `UX_INDEPENDENT_REVIEW_PACKAGE.md`, `UX_TARGETED_AUDIT_REPORT.md`, `market_mms_prototype.html`
  - `docs/ui-ux/visual-designs/` altındaki 16 dosya (`VISUAL_DESIGN_DELIVERY_REPORT.md`, `index.html`, `mob-01..04.html`, `win-01..06.html`, `shared.css`, `shared.js`, `test_currency_engine.js`, `verify_wcag.js`)
- **Kaldırılmış Dosya Gözlemi:** Önceki oturum çıktılarında görülen `docs/ui-ux.zip` artık çalışma ağacında mevcut değildir.

---

## 5. `PaymentMethod` ve Legacy Outbox Recovery İçin Saf Commit Adayı Dosyalar (18 veya 19 Dosya)

İlgisiz önceki işleri (`UI/UX`, `OD-01..OD-04`, Faz 1.2 hazırlık raporları) **kesinlikle içermeyen** saf aday dosyalar:

- **11 Tracked (`M`) Saf Dosya:**
  - `packages/mms_client_storage/lib/mms_client_storage.dart`
  - `packages/mms_client_storage/lib/src/database/client_database.dart`
  - `packages/mms_client_storage/lib/src/database/client_storage_repository.dart`
  - `packages/mms_client_storage/test/s5a3_live_hub_integration_test.dart`
  - `packages/mms_client_storage/test/s5a3_outbox_sync_test.dart`
  - `test_spikes/spike_01_backend/bin/server.dart`
  - `test_spikes/spike_01_backend/test/s4_device_pairing_test.dart`
  - `test_spikes/spike_01_backend/test/s5a2_durability_lifecycle_test.dart`
  - `test_spikes/spike_01_backend/test/s5a3_sales_validation_test.dart`
  - `docs/architecture/DATA_MODEL.md`
  - `docs/architecture/DATA_MODEL_DECISIONS.md`
- **7 Untracked (`??`) Saf Kod/Test/Rapor Dosyası (+ opsiyonel 8. olarak bu preflight raporu):**
  - `packages/mms_client_storage/lib/payment_method.dart`
  - `packages/mms_client_storage/lib/src/models/payment_method.dart`
  - `packages/mms_client_storage/test/payment_method_contract_test.dart`
  - `test/core/storage/payment_method_contract_test.dart`
  - `test_spikes/spike_01_backend/test/legacy_outbox_recovery_e2e_test.dart`
  - `docs/development/PHASE_1_2_PAYMENT_CONTRACT_FIX_REPORT.md`
  - `docs/development/PHASE_1_2_LEGACY_OUTBOX_RECOVERY_REPORT.md`
  - *(Proje sahibi preflight belgesini de commit kapsamına almak isterse: `docs/development/PHASE_1_2_PAYMENT_METHOD_GIT_PREFLIGHT_REPORT.md`)*

---

## 6. Kapsam Dışı Bırakılan Dosyalar ve Gerekçeleri

| Kapsam Dışı Grup | Dosyalar | Gerekçe |
|---|---|---|
| **Karışık Geçmiş Değişiklik İçeren Tracked Belgeler (3)** | `docs/PROJECT_STATUS.md`, `docs/REQUIREMENTS.md`, `docs/requirements/BUSINESS_RULES_SPEC.md` | Her üç dosya da önceki commitlenmemiş `OD-01..OD-04` ve `UI/UX` teslimat kabulü değişikliklerini (`v1.3`/`v1.4`) `PaymentMethod` değişiklikleriyle (`v1.5`) aynı dosya diff'i içinde barındırmaktadır (`git add <dosya>` bütün olarak eklerse önceki çalışmalar commit kapsamına karışır; ayrıntı Bölüm 10'dadır). |
| **Önceki UI/UX Teslimat Paketi (32)** | `docs/ui-ux/**` (`DESIGN_DECISIONS.md` ve `UX_07_FLUTTER_HANDOFF.md` dahil) | Önceki kabul edilmiş UI/UX teslimat klasörüdür ve Git'te henüz untracked'dır; UI/UX teslimatı bu commit kapsamı dışındadır. |
| **Önceki Aşama / Hazırlık Raporları (3)** | `PHASE_1_1_GIT_EXECUTION_REPORT.md`, `PHASE_1_2_PREPARATION_REPORT.md`, `PHASE_1_2_FINAL_PREFLIGHT_REPORT.md` | Sırasıyla Faz 1.1 ve UX/Faz 1.2 hazırlık çalışmalarına aittir. |
| **Generated `.g.dart` Dosyaları (2)** | `client_database.g.dart`, `database.g.dart` | `git ls-files "*.g.dart"` ile doğrulanmış tracked dosyalardır. Şema değişmediği için diff üretmemişlerdir (otomatik kapsam dışı sayılmadı; değiştirilmedikleri için diff'te yokturlar). |
| **`.gitignore`d Çalışma / Build / Secret Artifaktları** | `.dart_tool/`, `build/`, `test_spikes/spike_01_backend/build/`, `backups/`, `logs/`, `pepper.dpapi`, `service_wrapper/*.exe` | Derleme ikilileri (`mms_backend.exe`), test SQLite DB/WAL dosyaları ve yerel DPAPI sırrı `.gitignore` tarafından doğru biçimde dışlanmıştır. |

---

## 7. Her Aday Dosyanın Kısa Diff Özeti

1. `packages/mms_client_storage/lib/src/models/payment_method.dart` *(yeni, 58 satır)*: Pure Dart `PaymentMethod` enumu (`'CASH'`, `'CARD'`), fail-closed `parse`, `tryParse`, `isCanonical`, tarihsel salt-okunur `tryParseLegacyReadOnly`.
2. `packages/mms_client_storage/lib/payment_method.dart` *(yeni, 5 satır)*: Drift/Flutter bağımlılıksız `mms_payment_method` kütüphane export girişi.
3. `packages/mms_client_storage/lib/mms_client_storage.dart` *(+1)*: `src/models/payment_method.dart` ihracı eklendi (`L6`).
4. `packages/mms_client_storage/lib/src/database/client_database.dart` *(+1/-1)*: `LocalSales.paymentMethod` yorum satırı `// Kanonik sözleşme: 'CASH', 'CARD'` olarak hizalandı (`L56`); tablo/DDL/sürüm değişmedi.
5. `packages/mms_client_storage/lib/src/database/client_storage_repository.dart` *(+110/-10)*: `createOfflineSale()`'a `PaymentMethod.parse` zorunlu kılındı (`L76, 178, 233, 269`); `computeSaleRequestHash()` değişmedi; `updateAndRetryFailedOperation()` atomik `db.transaction`, `FAILED_PERMANENT` durum koruması, `operation_id`/`client_seq`/`total_amount`/`items` ve `PaymentMethod.parse` doğrulaması ile `_syncRepairedLocalSale()` (`local_sales` eşitlemesi ve yöntem ailesi koruması) eklendi (`L438-544`).
6. `test_spikes/spike_01_backend/bin/server.dart` *(+17/-1)*: `POST /api/v1/sales` içinde `processedOperations` idempotency kontrolünden sonra eksik/hatalı/legacy değerleri sessizce `'CASH'` yapan `?? 'CASH'` kaldırılıp `400 ERR_INVALID_PAYMENT_METHOD` döndüren `PaymentMethod.isCanonical` kontrolü eklendi (`L995, 1031-1045`).
7. `packages/mms_client_storage/test/s5a3_outbox_sync_test.dart` *(+1/-1)*: `'CREDIT_CARD'` -> `'CARD'` (`L172`).
8. `packages/mms_client_storage/test/s5a3_live_hub_integration_test.dart` *(+3/-1)*: `'CREDIT_CARD'` -> `'CARD'` (`L270`) ve `masterSales` içinde `'CASH'`/`'CARD'` assertion'ları eklendi (`L326, 329`).
9. `test_spikes/spike_01_backend/test/s5a2_durability_lifecycle_test.dart` *(+2/-2)*: 2 eski `'CREDIT_CARD'` fixture'ı `'CARD'` yapıldı (`L499, 548`).
10. `test_spikes/spike_01_backend/test/s4_device_pairing_test.dart` *(+4/-4)*: 4 eski `'NAKIT'` fixture'ı `'CASH'` yapıldı (`L1300, 1391, 1455, 1488`).
11. `packages/mms_client_storage/test/payment_method_contract_test.dart` *(yeni, 654 satır)*: Pure Dart `PaymentMethod`, `CASH`/`CARD` kalıcılık + hash, red testleri, legacy `CREDIT_CARD` Outbox koruma, `updateAndRetryFailedOperation` guard/rollback (`TEMP TRIGGER` + doğrulama) ve FIFO devam testleri (#1–6).
12. `test/core/storage/payment_method_contract_test.dart` *(yeni, 153 satır)*: `LocalDatabaseService` ile `CASH`/`CARD` hash, geçersiz metot reddi ve legacy `CREDIT_CARD -> CARD` onarım testleri (#1–3).
13. `test_spikes/spike_01_backend/test/s5a3_sales_validation_test.dart` *(+231)*: `CARD` kabul + replay (`#12`), 7 geçersiz/eski/eksik/null tip `400 ERR_INVALID_PAYMENT_METHOD` (`#13`), `CARD->CASH` `409` (`#14`), legacy commitli `'CREDIT_CARD'` `200 replay / 409 alter` (`#15`).
14. `test_spikes/spike_01_backend/test/legacy_outbox_recovery_e2e_test.dart` *(yeni, 356 satır)*: Canlı `SpikeServer` (`127.0.0.1:8967`) + `ClientDatabase` + `ClientSyncService` ile uçtan uca 11 adımlı legacy `CREDIT_CARD -> FAILED_PERMANENT -> Rollback -> CARD` onarım, FIFO bloklama/devam ve duplicate replay testi.
15. `docs/architecture/DATA_MODEL.md` *(+1)*: Bölüm 1.1 Madde 4 altına 11 Kasım 2026 `PaymentMethod` `'CASH'`/`'CARD'` standardizasyon alt notu (`L29`).
16. `docs/architecture/DATA_MODEL_DECISIONS.md` *(+1)*: `Karar 6` altına kanonik `'CASH'`/`'CARD'` tel/depolama notu (`L74`).
17. `docs/development/PHASE_1_2_PAYMENT_CONTRACT_FIX_REPORT.md` *(yeni, 163 satır)*: Sözleşme standardizasyonu kapanış raporu.
18. `docs/development/PHASE_1_2_LEGACY_OUTBOX_RECOVERY_REPORT.md` *(yeni, 148 satır)*: `updateAndRetryFailedOperation`, transaction rollback, FIFO ve E2E doğrulama raporu.

---

## 8. Secret, Hassas Dosya ve `.gitignore` Denetimi

- **Tracked binary/DB/secret kontrolü:** `git ls-files "*.db" "*.sqlite*" "*.dpapi" "*.key" "*.pem" "*.p12" "*.keystore" "*.jks" "*.env*" "*.exe" "*.dll"` -> **0 eşleşme**.
- **`.gitignore` ve İgnore Edilenler (`git status --ignored --short`):**
  - DB/WAL/SHM (`*.db`, `*.db-wal`, `*.db-shm`, `*.sqlite*`), DPAPI/anahtar (`*.dpapi`, `pepper.dpapi`, `*.key`), build/temp (`build/`, `.dart_tool/`, `test_spikes/spike_01_backend/build/mms_backend.exe`) ve log dosyalarının tamamı `.gitignore` altındadır.
  - **Markdown kontrolü (`§2.9`):** `.gitignore` içinde `*.md` dışlama kuralı yoktur; `git check-ignore -v docs/...` boş çıktı (exit 1) vererek hiçbir `.md` raporunun `.gitignore` ile engellenmediğini doğrulamıştır.
- **Diff & Aday İçerik Secret Taraması:** Candidate `git diff` ve yeni dosyalar üzerinde yapılan `Select-String` (`BEGIN ... KEY`, `AIza`, `sk-`, `ghp_`, `xoxb-`, `pepper`, `secret`, `password`, `token`) taramasında **gerçek hiçbir kimlik bilgisi, canlı token veya `.dpapi` sırrı bulunmamıştır** (`server.dart` ve testlerde görülenler yalnız pre-existing veya test-local localhost sabit dizgeleridir).

---

## 9. Önerilen Explicit-Path Staging Listesi (Yalnız İncelenmiş Saf Liste — Henüz Çalıştırılmadı)

> [!NOTE]
> Aşağıdaki liste **`git add .` veya `git add -A` içermez** ve bu görevde çalıştırılmamıştır; yalnızca Proje Sahibi açık commit talimatı verdiğinde referans alınmak üzere hazırlanmıştır.

```text
git add packages/mms_client_storage/lib/src/models/payment_method.dart
git add packages/mms_client_storage/lib/payment_method.dart
git add packages/mms_client_storage/lib/mms_client_storage.dart
git add packages/mms_client_storage/lib/src/database/client_database.dart
git add packages/mms_client_storage/lib/src/database/client_storage_repository.dart
git add packages/mms_client_storage/test/payment_method_contract_test.dart
git add packages/mms_client_storage/test/s5a3_outbox_sync_test.dart
git add packages/mms_client_storage/test/s5a3_live_hub_integration_test.dart
git add test/core/storage/payment_method_contract_test.dart
git add test_spikes/spike_01_backend/bin/server.dart
git add test_spikes/spike_01_backend/test/s4_device_pairing_test.dart
git add test_spikes/spike_01_backend/test/s5a2_durability_lifecycle_test.dart
git add test_spikes/spike_01_backend/test/s5a3_sales_validation_test.dart
git add test_spikes/spike_01_backend/test/legacy_outbox_recovery_e2e_test.dart
git add docs/architecture/DATA_MODEL.md
git add docs/architecture/DATA_MODEL_DECISIONS.md
git add docs/development/PHASE_1_2_PAYMENT_CONTRACT_FIX_REPORT.md
git add docs/development/PHASE_1_2_LEGACY_OUTBOX_RECOVERY_REPORT.md
```
*(İsteğe bağlı olarak proje sahibi tercih ederse: `git add docs/development/PHASE_1_2_PAYMENT_METHOD_GIT_PREFLIGHT_REPORT.md` eklenebilir.)*

---

## 10. Commit İçin Risk ve Engeller

1. **BLOKE EDİCİ DİKKAT NOKTASI — 3 Tracked Dokümanda Karışık Değişiklik (`PROJECT_STATUS.md`, `REQUIREMENTS.md`, `BUSINESS_RULES_SPEC.md`):**
   - Bu 3 dosya `HEAD (32111b8)` üzerine **önceki commitlenmemiş `UI/UX` & `OD-01..OD-04` değişikliklerini** VE **bu çalışmanın `PaymentMethod` değişikliklerini** birlikte içermektedir.
   - Hatta `BUSINESS_RULES_SPEC.md` değişim günlüğünde `v1.3`, `v1.4` (`OD-01..OD-04`) ve `v1.5` (`PaymentMethod`) satırları **aynı bitişik hunk içindedir**.
   - **Risk:** Bu 3 dosya bütün hâlde stage edilirse kapsam dışı tutulan önceki `UI/UX` & `OD-01..OD-04` karar değişiklikleri bu commit'e sızar (ve henüz commitlenmemiş `docs/ui-ux/` ile `PHASE_1_2_PREPARATION_REPORT.md`'ye atıf yapılmış olur). Tersi durumda bu 3 dosya commit dışında bırakılırsa `PaymentMethod` kodu + testleri + `DATA_MODEL*.md` + geliştirme raporları commitlenmiş olurken `BUSINESS_RULES_SPEC.md` (`v1.5`), `REQUIREMENTS.md` (`v1.3`) ve `PROJECT_STATUS.md` güncellemeleri sonraki doküman/UI-UX commit'inde veya ayrı hunk ayrıştırmasıyla commitlenmek üzere çalışma ağacında bekler.
   - **Önerilen Karar Yolu:**
     - **Seçenek 1 (Önerilen Temiz Commit):** Önce Bölüm 9'daki **18 (veya 19) saf `PaymentMethod` & Legacy Recovery dosyası** tek atomik commit ile işlenir; karışık 3 doküman ve `docs/ui-ux/` bir sonraki `UI/UX & Docs` commit'ine bırakılır (veya tam tersi sırada önce `UI/UX & OD-01..OD-04` commitlenip üzerine `PaymentMethod` commit'i atılır).
     - **Seçenek 2 (Hunk Ayrımı):** Proje sahibi `BUSINESS_RULES_SPEC.md` / `REQUIREMENTS.md` / `PROJECT_STATUS.md` dosyasındaki yalnız `PaymentMethod` satırlarının girmesini isterse önce çalışma ağacındaki iki iş parçasının ayrıştırılması gerekir (bu preflight görevinde dosya değiştirilmemiştir).
2. **`docs/ui-ux/` Altındaki `v1.4` Satırları:** `DESIGN_DECISIONS.md` (`v1.4`) ve `UX_07_FLUTTER_HANDOFF.md` (`v1.4`) dosyaları untracked `docs/ui-ux/` klasörü içinde olduğundan `UI/UX` commit'iyle birlikte gitmelidir.
3. **CRLF Uyarıları:** Windows ortamında `git diff` çıktılarına `LF will be replaced by CRLF` uyarısı yansımaktadır; bilinen Git satır sonu davranışıdır (engel değildir).

---

## 11. Gerçek Git Durumu (`00:40` İtibarıyla Doğrulandı)

- **Aktif Dal / Eşitlik:** `main`, `32111b8` (`HEAD == origin/main`)
- **Staged dosya sayısı:** **0**
- **Yeni commit:** **0**
- **Push:** **0**
- **Unstaged tracked (`M`):** **14 dosya**
- **Untracked (`??`):** **43 dosya** (`32` `docs/ui-ux/**`, `3` önceki rapor, `8` `PaymentMethod` / Legacy Recovery / Preflight dosyası)

---

**Sonuç:** `PaymentMethod` ve Legacy Outbox Recovery için Bölüm 9'daki **18 saf dosya** (+ isteğe bağlı bu preflight raporu) gizli veri/binary riski olmaksızın staging ve commit'e teknik olarak hazırdır; `PROJECT_STATUS.md`, `REQUIREMENTS.md` ve `BUSINESS_RULES_SPEC.md` içindeki karışık `UI/UX` & `OD-01..OD-04` değişiklikleri konusunda Proje Sahibinin commit sırası onayı beklenmektedir.
