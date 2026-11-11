# MARKET MMS — DOCUMENTATION RECONCILIATION RAPORU

**Belge Kodu:** `docs/development/DOCUMENTATION_RECONCILIATION_REPORT.md`  
**Tarih:** 12 Kasım 2026  
**Durum:** Tamamlandı — Proje Sahibi İncelemesi Bekliyor  
**Dayanak Commit:** `b069d5b` (`origin/main` ile eşit — `fix(sync): enforce canonical payment methods and recover legacy outbox`)

---

## 1. Görev Kapsamı ve Değiştirilen Dosyalar

Bu çalışmada yalnız Proje Sahibi tarafından belirtilen aşağıdaki **3 kanonik doküman** incelenip güncel proje kararlarıyla uzlaştırılmış ve sonuç raporu oluşturulmuştur:

| # | Dosya Yolu | İşlem | Özet |
| :---: |---|---|---|
| 1 | [`docs/PROJECT_STATUS.md`](../PROJECT_STATUS.md) | Güncellendi | Son tarih (`12 Kasım 2026`), `HEAD` (`b069d5b`), `PaymentMethod` & Legacy Outbox Recovery tamamlanma/push durumu (`235` yeşil test), UI/UX kabulü + `OD-01..OD-04`, Faz 1.2 POS geliştirmesinin henüz başlamadığı ve sonraki adımlar uzlaştırıldı. |
| 2 | [`docs/REQUIREMENTS.md`](../REQUIREMENTS.md) | Güncellendi | `12 Kasım 2026` & `BUSINESS_RULES_SPEC.md v1.6` referansları, `BR-PROD` (`12.50 TL` + `Half-Up`), `BR-SYNC` (`OD-03`/`BR-SYNC-04`, katı FIFO + Legacy Outbox `'CREDIT_CARD'` onarımı `b069d5b`) ve `NFR-DATA-01`/`NFR-OFFLINE-01` uzlaştırıldı; `BR-PAY`, `OD-02`, `OD-03`, `OD-04` korundu. |
| 3 | [`docs/requirements/BUSINESS_RULES_SPEC.md`](../requirements/BUSINESS_RULES_SPEC.md) | Güncellendi (**v1.6**) | Değişiklik geçmişine `v1.6` eklendi; `BR-PAY-01` ve `BR-SYNC-02` altına Legacy Outbox Recovery (`b069d5b`) & FIFO uyumu işlendi; Bölüm 12 izlenebilirlik matrisindeki sürüm (`v1.6`) ve çelişkili `BR-POS-05` satırı (`BR-POS-07`) düzeltildi; Bölüm 13 kabul durumu ve `v1.4` plan referansı güncellendi. |
| 4 | [`docs/development/DOCUMENTATION_RECONCILIATION_REPORT.md`](./DOCUMENTATION_RECONCILIATION_REPORT.md) | Oluşturuldu | Bu uzlaştırma raporu. |

**Kapsam Korunumu:** Kaynak kod (`lib/`, `packages/`, `test_spikes/`), testler, diğer dokümanlar (`DATA_MODEL.md`, `DATA_MODEL_DECISIONS.md`, `docs/ui-ux/**`) değiştirilmemiştir; `git add`, `git commit` veya `git push` çalıştırılmamıştır.

---

## 2. Çekirdek Proje Kararları Uyum Matrisi

| Karar / Konu | `PROJECT_STATUS.md` | `REQUIREMENTS.md` | `BUSINESS_RULES_SPEC.md` (`v1.6`) |
|---|---|---|---|
| **PaymentMethod yalnız `CASH` ve `CARD`** | Uyumlu (`b069d5b` tamamlandı/push edildi) | Uyumlu (`BR-PAY`: `'CASH'`/`'CARD'`, eski dizgeler *obsolete*) | Uyumlu (`BR-PAY-01`, `BR-PAY-04`, Bölüm 12) |
| **Legacy Outbox Recovery tamamlandı** | Uyumlu (`updateAndRetryFailedOperation`, rollback, FIFO, `b069d5b`) | Uyumlu (`BR-SYNC`: atomik `CREDIT_CARD -> CARD` onarımı) | Uyumlu (`v1.6`, `BR-PAY-01`, `BR-SYNC-02`) |
| **Half-Up yuvarlama & `12.50 TL`** | Uyumlu (`OD-01` Half-Up + `12.50 TL`) | Uyumlu (`BR-PROD`, `NFR-DATA-01`) | Uyumlu (`BR-PROD-07`, Bölüm 11, Bölüm 12) |
| **`OD-02`, `OD-03`, `OD-04` kararları** | Korundu (Bölüm 1, 2, 3) | Korundu (`BR-PROD`, `BR-POS`, `BR-SYNC`, `NFR-OFFLINE-01`) | Korundu (`BR-POS-05` `OUT_OF_SCOPE`, `BR-PROD-05`/`BR-SYNC-04`, Bölüm 11) |
| **UI/UX teslimatı kabul edildi** | Korundu (11 Kasım 2026 — `docs/ui-ux/` untracked) | Etkilenmeyen modül indeksi korundu | Korundu (`v1.4` + Bölüm 13) |
| **Phase 1.2 POS geliştirmesi başlamadı** | Açıkça belirtildi (Bölüm 1, 2, 3, 4) | Etkilenmedi (Faz 0 kural indeksi) | Bölüm 13 güncellendi (**henüz başlamadı**, onay bekliyor) |

---

## 3. Yapılan Düzeltmelerin Ayrıntılı Listesi

### 3.1. `docs/PROJECT_STATUS.md`
- **Tarih ve Commit Etkisi (`L4, L10, L17, L18`):** Son güncelleme `12 Kasım 2026` olarak güncellendi; gerçek `HEAD` (`32111b8` yerine `b069d5b`, `HEAD == origin/main`) ve `PaymentMethod` + Legacy Outbox Recovery'nin "onay bekliyor / henüz commitlenmedi" durumundan **"TAMAMLANDI, KABUL EDİLDİ VE PUSH EDİLDİ (Commit `b069d5b`)"** durumuna geçtiği işlendi.
- **Doğrulama Rakamı (`L27`):** Mevcut Faz 1.1 tarihsel kaydı (`221` test) korunarak altına **Faz 1.2 Öncesi `b069d5b` doğrulaması (`34 + 57 + 144 = 235` yeşil test, `0` analyzer hatası)** eklendi.
- **Faz 1 Takibi & Sonraki Görevler (`L50, L89-99`):** `BUSINESS_RULES_SPEC.md` sürüm atfı `v1.6` yapıldı; Faz 1 listesinde PaymentMethod + Legacy Outbox Recovery `[x]` olarak kapatıldı; Faz 1.2 POS geliştirmesinin **HENÜZ BAŞLAMADIĞI** vurgulandı; Bölüm 4'teki eski PaymentMethod onay talebi kaldırılarak güncel `DOCUMENTATION_RECONCILIATION_REPORT.md` incelemesi, kalan UI/UX + doküman Git işlemi ve Faz 1.2 POS başlatma onayı listelendi.

### 3.2. `docs/REQUIREMENTS.md`
- **Üst Veri (`L3-6`):** Belge tarihi `12 Kasım 2026` ve ana şartname atfı `BUSINESS_RULES_SPEC.md (v1.6)` olarak güncellendi.
- **`BR-PROD` ve `NFR-DATA-01` (`L26, L43`):** `OD-01` Half-Up yuvarlama yanında **`12.50 TL` gösterim standardı** her iki satırda da açıkça güvenceye alındı.
- **`BR-SYNC` ve `NFR-OFFLINE-01` (`L31, L44`):** `BR-SYNC-04 / OD-03` (ürün oluşturma için Hub zorunluluğu), katı FIFO (`client_sequence_number`) ve Legacy `'CREDIT_CARD'` Outbox kayıtlarının `updateAndRetryFailedOperation` ile atomik transaction/rollback altında `'CARD'`'a onarılması (`b069d5b`) eklendi.

### 3.3. `docs/requirements/BUSINESS_RULES_SPEC.md` (`v1.6`)
- **Üst Bilgi & Revizyon Geçmişi (`L4-6, L24`):** `v1.6 (12 Kasım 2026)` satırı ve başlık bilgisi eklendi (tüm `v1.0..v1.5` geçmişi korundu).
- **`BR-PAY-01` & `BR-SYNC-02` (`L222-223, L312-313`):** Hub'da commitli `'CREDIT_CARD'` kayıtlarının `200` idempotent replay korunumu ile istemcide `FAILED_PERMANENT` durumuna düşen `'CREDIT_CARD'` kayıtlarının yerel satış silinmeden tek atomik SQLite transaction'da `'CARD'`'a onarılıp FIFO'nun devam etmesi (`b069d5b`) ve `sync_operations` / `outbox_operations` eşlemesi netleştirildi.
- **Bölüm 12 İzlenebilirlik Matrisi (`L455, L485`):** Satır `455`'teki stale `(v1.2)` ifadesi `(v1.6)` yapıldı; satır `485`'teki `BR-POS-05, BR-POS-07` (`CONFIRMED`) çelişkisi (`BR-POS-05` Parked Carts `OD-02` kararıyla `OUT_OF_SCOPE` olduğu için) yalnız **`BR-POS-07`** olarak düzeltildi.
- **Bölüm 13 Kabul Durumu (`L526-530`):** Stale `MARKET_POS_AI_STUDIO_BUILD_PLANI.md (v1.2.2)` -> `v1.4`, stale `v1.2 düzeyinde` -> `v1.6 düzeyinde` ve stale `"aktif DT-01 alt aşamalarının tamamlanması"` ifadesi güncel durumla (`DT-01.1..DT-01.4`, `UI/UX` kabulü, `b069d5b` tamamlandı; Faz 1.2 POS geliştirmesi henüz başlamadı) düzeltildi.

---

## 4. Tespit Edilen Çelişkiler, Belirsizlikler ve Açık Kalan Konular

Yeni karar üretme veya mevcut kural ID'lerini sessizce değiştirme yasağı gereği aşağıdaki yapısal tutarsızlıklar **değiştirilmeden** raporlanmaktadır:

1. **`REQUIREMENTS.md` Özet Tablosu vs `BUSINESS_RULES_SPEC.md` Modül Kodu ve Kural Sayısı Farkları:**
   - `REQUIREMENTS.md` Bölüm 2 tablosu Modül 9'u `BR-DSH (4 Kural)`, Modül 6'yı `BR-USR (4 Kural)` ve ek satır olarak `BR-DEV (4 Kural)` başlıklarıyla özetlerken; `BUSINESS_RULES_SPEC.md` içinde bu modüller sırasıyla `BR-REP` (`BR-REP-01..08`, **8 kural**) ve `BR-SEC` (`BR-SEC-01..06`, **6 kural**) olarak kodlanmıştır (`BR-DEV` kodu `BUSINESS_RULES_SPEC.md` içinde yer almamaktadır).
   - Ayrıca `REQUIREMENTS.md`'deki kural sayısı sütunu (`BR-STK: 10 Kural`, `BR-POS: 14 Kural`, `BR-PAY: 5 Kural`, `BR-SYNC: 7 Kural`, `BR-TNT: 5 Kural`) ile `BUSINESS_RULES_SPEC.md`'deki fiili alt başlık sayısı (`BR-STK-01..11 = 11`, `BR-POS-01..11 = 11`, `BR-PAY-01..06 = 6`, `BR-SYNC-01..06 = 6`, `BR-TNT-01..04 = 4`) farklıdır; geçmiş keşif (`PHASE_0_BUSINESS_DISCOVERY.md`) sayımından miras kalan bu tabloya sessizce dokunulmamıştır. Proje Sahibi isterse ayrı kararla senkronize edilebilir.
2. **`BUSINESS_RULES_SPEC.md` Faz 0 Gelecek-Zaman İfadeleri:**
   - `BR-STK-03` (`L256`: *"Aşama 6B-2 kapsamında değerlendirilecektir"*) ve `BR-SEC-01` (`L337`: *"açık konu olup Faz 1'de ele alınacaktır"*) ifadeleri Faz 0 taslağından kalan gelecek-zaman notlarıdır (Aşama 6B-2 tamamlandığı halde kural içi tarihsel notlar korunmuştur).
3. **`BR-PAY-05` Operatör Audit / UI Eksikliği (Faz 1.2+ Takibi):**
   - `b069d5b` ile tamamlanan `updateAndRetryFailedOperation()` yalnızca teknik eski sözleşme (`'CREDIT_CARD' -> 'CARD'`) onarımı yapar ve ödeme ailesi değişimini (`CASH <-> CARD`) engeller; kullanıcı kaynaklı yanlış ödeme seçimi düzeltmesi (`BR-PAY-05`: `audit_logs` / `payment_method_corrections` + UI) ile `FAILED_PERMANENT` operatör kurtarma ekranı henüz pilot `ClientDatabase` (`schemaVersion: 1`) ve `lib/` içinde uygulanmamıştır.
4. **Çalışma Ağacı Git Durumu (Dışarıda Bırakılan Dosyalar):**
   - Uzlaştırılan bu 3 doküman + `docs/ui-ux/` (`32` dosya) + geçmiş geliştirme raporları (`PHASE_1_1_GIT_EXECUTION_REPORT.md`, `PHASE_1_2_PREPARATION_REPORT.md`, `PHASE_1_2_FINAL_PREFLIGHT_REPORT.md`, `PHASE_1_2_PAYMENT_METHOD_GIT_EXECUTION_REPORT.md`, `DOCUMENTATION_RECONCILIATION_REPORT.md`) çalışma ağacında ayrı commit onayı beklemektedir.

---

**Durum:** Yalnızca istenen 3 doküman ve bu uzlaştırma raporu güncellenmiştir; kaynak koda, diğer belgelere ve Git geçmişine müdahale edilmemiştir. İncelemeniz beklenmektedir.

