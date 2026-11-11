# MARKET MMS — UI/UX & Documentation Git Preflight Report

**Belge Kodu:** `docs/development/UI_UX_GIT_PREFLIGHT_REPORT.md`  
**Tarih:** 12 Kasım 2026  
**Aşama:** UI/UX Teslimatı (`docs/ui-ux/`), Kanonik Dokümantasyon Uzlaştırması ve Bekleyen Raporlar İçin Salt Git Preflight Denetimi  
**Hazırlayan:** Antigravity (Gemini)  
**Karar ve Onay Mercii:** Proje Sahibi  
**Preflight Kararı:** **PASS (GÜVENLİ — AÇIK DOSYA BAZLI STAGING İLE COMMIT'E HAZIR)**  

> [!IMPORTANT]
> **Salt Preflight Denetim Kısıtı (`AGENTS.md` §13–15):**  
> Bu görev kapsamında yalnızca okuma, tarama ve raporlama yapılmıştır. Hiçbir mevcut kaynak kod dosyası veya doküman değiştirilmemiş; **`git add`, `git commit` veya `git push` kesinlikle çalıştırılmamıştır.** Proje Sahibi açık talimat vermeden hiçbir staging veya commit işlemi başlatılamaz.

---

## 1. Branch, `HEAD` ve `origin/main` Durumu

Çalışma dizini `c:\Users\halil\Github\market-pos` üzerinde yapılan Git incelemesi sonuçları:

| Kontrol Parametresi | Gözlenen Değer | Değerlendirme |
|---|---|---|
| **Aktif Branch** | `main` | Doğru ana dal |
| **Yerel `HEAD`** | `b069d5b7ea521939459b55b705cb9ef50e51c8a9` (`b069d5b`) | `fix(sync): enforce canonical payment methods and recover legacy outbox` |
| **Önceki 2 Commit** | `32111b8` (`docs(audit)...`), `2db892d` (`docs(governance)...`) | Doğrusal temiz geçmiş |
| **Remote (`origin`)** | `https://github.com/halilkrkn/market-pos.git` (fetch & push) | Doğru uzak depo |
| **`HEAD...origin/main` Farkı** | `0` ahead / `0` behind (`0\t0`) | Uzak depo ile birebir eşit |
| **Staged Alan (`git diff --cached`)** | **0 dosya** (tamamen boş) | Önceki veya yarım staging kalıntısı yok |
| **`core.autocrlf`** | `true` | Windows Git standart satır sonu dönüşümü aktif |

---

## 2. Tracked ve Untracked Dosya Envanteri

Rapor oluşturulmadan önceki çalışma ağacı durumunda **3 takip edilen değiştirilmiş (`M`)** dosya ve **37 takip edilmeyen (`??`)** dosya bulunmaktadır (`UI_UX_GIT_PREFLIGHT_REPORT.md` eklendiğinde `docs/development/` altında untracked dosya sayısı 5'ten 6'ya, toplam untracked dosya sayısı 38'e çıkar).

### 2.1 Özet Dağılım Tablosu

| Grup | Git Statüsü | Dosya Sayısı | Toplam Boyut | Kapsam Açıklaması |
|---|---|---:|---:|---|
| **A. Kanonik Doküman Güncellemeleri** | `M` (Tracked Modified) | 3 | 88.033 B (~86,0 KB) | `PROJECT_STATUS.md`, `REQUIREMENTS.md`, `BUSINESS_RULES_SPEC.md` (`97 insertions, 78 deletions`) |
| **B. Kabul Edilmiş UI/UX Paketi** | `??` (Untracked) | 32 | 577.745 B (~564,2 KB) | `docs/ui-ux/` kökünde 16 + `docs/ui-ux/visual-designs/` altında 16 dosya |
| **C. Bekleyen Geliştirme & Git Raporları** | `??` (Untracked) | 5 *(+1 bu rapor)* | 80.405 B *(+bu rapor)* | Önceki execution/preparation/preflight raporları + `DOCUMENTATION_RECONCILIATION_REPORT.md` |
| **D. `.gitignore`d Çalışma / Build / Secret** | `!!` (Ignored) | Dışlanmış | — | `.dart_tool/`, `build/`, `backups/`, `logs/`, `pepper.dpapi`, `MarketMMSService.exe`, `MarketMmsSpike01.exe` vb. |
| **E. Dart / Flutter / Backend Kaynak Kodu** | Temiz | 0 değişiklik | — | `lib/`, `packages/`, `test/`, `test_spikes/` altında hiçbir değiştirilmiş veya untracked dosya yok |

*(Bilgi notu: `docs/development/` altında ayrıca önceden commitlenmiş 9 tracked rapor bulunmaktadır: `DT_01_1_AGENT_GOVERNANCE_AUDIT.md`, `DT_01_3_DOCUMENTATION_RECONCILIATION_REPORT.md`, `DT_01_3_FINAL_REVIEW_REPORT.md`, `DT_01_4_FINAL_GOVERNANCE_AUDIT.md`, `DT_01_4_INSTRUCTION_INTEGRATION_REPORT.md`, `PHASE_1_2_LEGACY_OUTBOX_RECOVERY_REPORT.md`, `PHASE_1_2_PAYMENT_CONTRACT_FIX_REPORT.md`, `PHASE_1_2_PAYMENT_METHOD_GIT_PREFLIGHT_REPORT.md`, `PRE_COMMIT_FINAL_AUDIT_REPORT.md`.)*

### 2.2 Grup A — Tracked Değiştirilmiş Kanonik Dokümanlar (`3 dosya`)

| # | Dosya Yolu | Boyut (Bayt) | Diff Özeti | Rolü |
|---|---|---:|---|---|
| 1 | `docs/PROJECT_STATUS.md` | 17.003 | `39` değişen satır | Canlı proje faz durumu ve Git senkronizasyon özeti |
| 2 | `docs/REQUIREMENTS.md` | 6.432 | `22` değişen satır | Özet iş kuralları ve NFR gereksinim kataloğu (`v1.3`) |
| 3 | `docs/requirements/BUSINESS_RULES_SPEC.md` | 64.598 | `114` değişen satır | Kanonik bağlayıcı iş kuralları şartnamesi (`v1.6`) |

### 2.3 Grup B — Untracked Kabul Edilmiş UI/UX Dosyaları (`docs/ui-ux/` — `32 dosya`)

**Kök Dizin (`docs/ui-ux/` — 16 dosya):**

| # | Dosya Yolu | Boyut (Bayt) | Tür / Rol |
|---|---|---:|---|
| 1 | `docs/ui-ux/DESIGN_DECISIONS.md` | 17.199 | Tasarım kararları ve değişmezler sicili (`v1.4`) |
| 2 | `docs/ui-ux/DESIGN_REFERENCES_AND_LICENSES.md` | 9.598 | Açık kaynak ilham referansları ve lisans notları (`v1.1`) |
| 3 | `docs/ui-ux/market_mms_prototype.html` | 31.634 | `[LEGACY / EXPERIMENTAL]` eski tek-dosya prototip referansı (ana vitrin dışı) |
| 4 | `docs/ui-ux/UX_01_FINAL_REVIEW_REPORT.md` | 15.400 | UX 01 aşaması final inceleme raporu |
| 5 | `docs/ui-ux/UX_01_USER_RESEARCH.md` | 13.312 | Kullanıcı araştırması ve kasiyer/yönetici profili |
| 6 | `docs/ui-ux/UX_01_USER_SCENARIOS_AND_PRODUCT_ANALYSIS.md` | 46.305 | Kullanım senaryoları ve ürün analizi |
| 7 | `docs/ui-ux/UX_02_INFORMATION_ARCHITECTURE.md` | 13.704 | Bilgi mimarisi ve ekran navigasyon yapısı |
| 8 | `docs/ui-ux/UX_03_DESIGN_SYSTEM.md` | 12.051 | Tasarım sistemi token'ları, tipografi ve bileşen standartları |
| 9 | `docs/ui-ux/UX_04_SCREEN_DESIGNS.md` | 18.485 | Ekran blueprint'leri ve akış tasarımları |
| 10 | `docs/ui-ux/UX_05_INTERACTIVE_PROTOTYPE.md` | 8.880 | Etkileşimli prototip davranış dokümanı |
| 11 | `docs/ui-ux/UX_06_USABILITY_VALIDATION.md` | 11.754 | Kullanılabilirlik doğrulama senaryoları ve pilot hedefleri |
| 12 | `docs/ui-ux/UX_07_FLUTTER_HANDOFF.md` | 18.254 | Flutter geliştirici devir kılavuzu (`v1.4`) |
| 13 | `docs/ui-ux/UX_FINAL_DELIVERY_REPORT.md` | 22.383 | UX program nihai teslimat ve kabul raporu (`v1.7`) |
| 14 | `docs/ui-ux/UX_FINAL_VERIFICATION_AND_RECONCILIATION_REPORT.md` | 41.546 | UX son teknik doğrulama ve dokümantasyon uzlaştırma raporu |
| 15 | `docs/ui-ux/UX_INDEPENDENT_REVIEW_PACKAGE.md` | 47.747 | Bağımsız tasarım danışmanı inceleme paketi |
| 16 | `docs/ui-ux/UX_TARGETED_AUDIT_REPORT.md` | 59.142 | Hedefli teknik, güvenlik ve ergonomi denetim raporu (`v1.3`) |

**Görsel Tasarımlar ve Doğrulama Betikleri (`docs/ui-ux/visual-designs/` — 16 dosya):**

| # | Dosya Yolu | Boyut (Bayt) | Tür / Rol |
|---|---|---:|---|
| 17 | `docs/ui-ux/visual-designs/index.html` | 11.945 | Ana görsel vitrin, tema konsolu ve değişmezler paneli |
| 18 | `docs/ui-ux/visual-designs/win-01-dashboard.html` | 12.222 | Windows `W-05` Yönetici Dashboard ekranı |
| 19 | `docs/ui-ux/visual-designs/win-02-pos.html` | 18.170 | Windows `W-01` Kasa Satış & Sepet ekranı |
| 20 | `docs/ui-ux/visual-designs/win-03-product-search.html` | 9.527 | Windows `W-06` Ürün/Barkod Arama ekranı |
| 21 | `docs/ui-ux/visual-designs/win-04-payment-modal.html` | 13.674 | Windows `W-02` Hızlı Ödeme modalı |
| 22 | `docs/ui-ux/visual-designs/win-05-sales-history.html` | 11.491 | Windows `W-10` Satış Geçmişi & İade ekranı |
| 23 | `docs/ui-ux/visual-designs/win-06-stock-management.html` | 9.283 | Windows `W-09` Stok & Hareketler ekranı |
| 24 | `docs/ui-ux/visual-designs/mob-01-dashboard.html` | 7.386 | Mobil `M-01` Mağaza Sahibi Dashboard ekranı |
| 25 | `docs/ui-ux/visual-designs/mob-02-barcode-scan.html` | 5.898 | Mobil `M-02` Kamera Barkod Tarama ekranı |
| 26 | `docs/ui-ux/visual-designs/mob-03-cart-checkout.html` | 8.268 | Mobil `M-03` Dokunmatik Sepet & Ödeme ekranı |
| 27 | `docs/ui-ux/visual-designs/mob-04-stock-view.html` | 8.919 | Mobil `M-04` Reyon Stok Görüntüleme ekranı |
| 28 | `docs/ui-ux/visual-designs/shared.css` | 14.173 | Ortak tasarım sistemi CSS token'ları ve layout stilleri |
| 29 | `docs/ui-ux/visual-designs/shared.js` | 10.228 | Ortak kuruş tamsayı para motoru (`parseToCents`, `formatKurus`), tema ve sepet yardımcıları |
| 30 | `docs/ui-ux/visual-designs/test_currency_engine.js` | 10.920 | Bağımsız Node.js para motoru birim test koşucusu (43 test) |
| 31 | `docs/ui-ux/visual-designs/verify_wcag.js` | 15.620 | Bağımsız Node.js WCAG 2.1 AA/AAA renk kontrastı doğrulama betiği |
| 32 | `docs/ui-ux/visual-designs/VISUAL_DESIGN_DELIVERY_REPORT.md` | 22.627 | Görsel tasarım teslimat raporu (`v1.4`) |

### 2.4 Grup C — Untracked Geliştirme ve Git İşlem Raporları (`docs/development/` — `5 + 1 dosya`)

| # | Dosya Yolu | Boyut (Bayt) | Tarih / Kapsam Notu |
|---|---|---:|---|
| 1 | `docs/development/PHASE_1_1_GIT_EXECUTION_REPORT.md` | 8.546 | 6 Kasım 2026 — DT-01.1..DT-01.4 commit yürütmesi (`50343d9`..`32111b8`) raporu |
| 2 | `docs/development/PHASE_1_2_PREPARATION_REPORT.md` | 25.272 | 11 Kasım 2026 — Faz 1.2 hazırlık & kapsam raporu *(tarihsel: `b069d5b` öncesi açık risk listesini içerir)* |
| 3 | `docs/development/PHASE_1_2_FINAL_PREFLIGHT_REPORT.md` | 27.125 | 11 Kasım 2026 — Faz 1.2 öncesi `PaymentMethod` & `defaultDeviceId` preflight analizi *(tarihsel: `b069d5b` öncesi BLOCKING bulguyu belgeler)* |
| 4 | `docs/development/PHASE_1_2_PAYMENT_METHOD_GIT_EXECUTION_REPORT.md` | 10.092 | 12 Kasım 2026 — `b069d5b` (`PaymentMethod` & Legacy Outbox Recovery) Git execution raporu |
| 5 | `docs/development/DOCUMENTATION_RECONCILIATION_REPORT.md` | 9.370 | 12 Kasım 2026 — 3 kanonik dokümanın uzlaştırma raporu |
| 6 | `docs/development/UI_UX_GIT_PREFLIGHT_REPORT.md` | Bu dosya | 12 Kasım 2026 — İşbu UI/UX ve dokümantasyon Git preflight raporu *(commit kapsamına dahil edilmesi opsiyoneldir)* |

---

## 3. İçerik ve Diff Kapsam İncelemesi

### 3.1 Tracked Kanonik Doküman Diff Kapsamı (`3 files changed, 97 insertions(+), 78 deletions(-)`)

1. **[`docs/PROJECT_STATUS.md`](../PROJECT_STATUS.md):**
   - Son güncelleme tarihi `6 Kasım 2026` -> `12 Kasım 2026` olarak güncellendi.
   - Aktif Git durumu (`main`, `b069d5b`, `HEAD == origin/main`) ve commit bekleyen `docs/ui-ux/` + önceki raporlar eklendi.
   - `DT-01.2` (`50343d9`), `DT-01.3` (`6b7898c`), `DT-01.4` (`2db892d`, `32111b8`), UI/UX kabulü (`11 Kasım 2026`, `OD-01..OD-04`), `PaymentMethod` & Legacy Outbox Recovery (`b069d5b`, `235` test) ve Faz 1.2'nin henüz başlamadığı (kodlama onayı beklediği) açıkça işlendi.
   - Sonraki Adımlar listesi güncel dokümantasyon uzlaştırma incelemesi, Git commit onayı ve Faz 1.2 POS başlatma onayı ile hizalandı.

2. **[`docs/REQUIREMENTS.md`](../REQUIREMENTS.md):**
   - Belge sürümü `v1.0` -> `v1.3 (12 Kasım 2026)` ve şartname referansı `BUSINESS_RULES_SPEC.md (v1.6)` olarak güncellendi.
   - `BR-PROD` (`OD-01` Half-Up + `12.50 TL`, `OD-03` offline bilinmeyen barkod eklenemez/oluşturulamaz), `BR-STK` (`BR-STK-04..10` `OUT_OF_SCOPE`), `BR-POS` (`BR-POS-07` atomik satış düzeltmesi, `BR-POS-05`/`OD-02` `OUT_OF_SCOPE`, `OD-04` sanal numpad opsiyonel/varsayılan kapalı), `BR-PAY` (`'CASH'`/`'CARD'` sözleşmesi, `'CREDIT_CARD'`/`'NAKIT'` *obsolete*, sessiz `'CASH'` fallback yasağı) ve `BR-SYNC` (`OD-03` Hub zorunluluğu, FIFO ve `updateAndRetryFailedOperation` Legacy Outbox atomik recovery `b069d5b`) uzlaştırıldı.
   - `NFR-DATA-01` ve `NFR-OFFLINE-01` maddeleri onaylı kurallarla eşitlendi.

3. **[`docs/requirements/BUSINESS_RULES_SPEC.md`](../requirements/BUSINESS_RULES_SPEC.md):**
   - Belge sürümü `v1.2` -> `v1.6 (12 Kasım 2026)` olarak güncellendi; `v1.0..v1.5` revizyon tarihçesi ve özgün kural ID'leri korundu.
   - `BR-PROD-05`/`07` (`OD-03`, `OD-01`), `BR-POS-05` (`OD-02` -> `[OUT_OF_SCOPE]`), `BR-STK-04..10` (`[OUT_OF_SCOPE]`), `BR-PAY-01`/`04` (`'CASH'`/`'CARD'` + sessiz fallback yasağı), `BR-SYNC-02`/`04` (`updateAndRetryFailedOperation`, FIFO bloklama/devamı, Hub ürün oluşturma), Bölüm 11–13 (`BR-POS-07` matris düzeltmesi, `v1.4` plan referansı ve güncel kabul durumu) tutarlı hâle getirildi.

> [!NOTE]
> `git diff` sırasında üç takip edilen dosyada Windows `core.autocrlf = true` nedeniyle `warning: in the working copy of '...', LF will be replaced by CRLF the next time Git touches it` mesajı gözlenmiştir. Bu durum Windows Git normalizasyonunun beklenen bir çıktısıdır; satır içeriğinde bozulma yoktur.

### 3.2 UI/UX Paketi ve Bekleyen Geliştirme Raporları Kapsamı

- **Kabul Edilmiş UI/UX Paketi (`docs/ui-ux/`):**
  - `DESIGN_DECISIONS.md` (`v1.4`), `UX_07_FLUTTER_HANDOFF.md` (`v1.4`), `UX_FINAL_DELIVERY_REPORT.md` (`v1.7`), `VISUAL_DESIGN_DELIVERY_REPORT.md` (`v1.4`) ve `UX_TARGETED_AUDIT_REPORT.md` (`v1.3`) `OD-01..OD-04` kararları ve `'CASH'`/`'CARD'` kanonik sözleşmesiyle uyumludur.
  - `docs/ui-ux/market_mms_prototype.html` başında açıkça `[LEGACY / EXPERIMENTAL] Eski Tek-Dosya POS Prototipi — ANA VİTRİN DIŞIDIR` uyarısı yer almakta olup güncel `visual-designs/index.html` vitrini ile karıştırılmaması belgelenmiştir.
  - **Tarihsel Referans Notu:** `UX_01_USER_SCENARIOS_AND_PRODUCT_ANALYSIS.md:541` (`v1.2`) ve `UX_07_FLUTTER_HANDOFF.md:167` (`v1.4`) içinde eski `BUSINESS_RULES_SPEC.md` sürüm numaralarına atıflar bulunmaktadır; kabul edilmiş UI/UX teslimatına dokunmama kuralı gereği preflight aşamasında değiştirilmemiştir.
- **Bekleyen Geliştirme Raporları (`docs/development/`):**
  - `PHASE_1_1_GIT_EXECUTION_REPORT.md` dosya adına rağmen (`PHASE_1_1_...`) DT-01.1..DT-01.4 yürütmesini belgeler ve `PROJECT_STATUS.md` tarafından bu adla referans alınır.
  - `PHASE_1_2_PREPARATION_REPORT.md` ve `PHASE_1_2_FINAL_PREFLIGHT_REPORT.md` (`11 Kasım 2026`), `b069d5b` commit'i öncesinde hazırlandığı için o dönemki açık `CREDIT_CARD`/`NAKIT` bulgularını "çözülmesi gereken ön koşul" olarak kayda geçirir. Bu kayıtlar tarihsel denetim izi olup `PHASE_1_2_PAYMENT_CONTRACT_FIX_REPORT.md` ve `b069d5b` tarafından kapatılmıştır.

---

## 4. Secret, Geçici Dosya, Build Çıktısı ve Hijyen Kontrolleri

| Denetim Başlığı | Uygulanan Komut / Kontrol | Sonuç |
|---|---|---|
| **Secret / Anahtar / Token Taraması** | 40 aday dosya (`32` UI/UX + `3` kanonik + `5` rapor) üzerinde `BEGIN ... KEY`, `AIza...`, `sk-...`, `ghp_...`, `xoxb-`, `password[:=]`, `api_key[:=]`, `pepper.dpapi`, `.env` taraması | **TEMİZ** — Yalnızca kuralları açıklayan metin atıfları (`pepper.dpapi`, `.env`) görüldü; **0 gerçek secret/anahtar** |
| **Geçici / Arşiv / OS Dosyası** | `docs/` altında `*.tmp`, `*.bak`, `*~`, `*.zip`, `*.7z`, `*.rar`, `Thumbs.db`, `.DS_Store` taraması | **0 eşleşme (TEMİZ)** |
| **Build / Binary / DB Artifaktı** | `docs/` altında `*.exe`, `*.apk`, `*.db`, `*.sqlite*` taraması + `git status --ignored` | **0 eşleşme (TEMİZ)** — `build/`, `.dart_tool/`, `pepper.dpapi`, `MarketMMSService.exe`, `MarketMmsSpike01.exe`, `backups/`, `logs/` `.gitignore` altındadır |
| **`.gitignore` Çakışma Kontrolü** | `git check-ignore -v` kontrolü (`market_mms_prototype.html`, `visual-designs/index.html`, `shared.js`, `DOCUMENTATION_RECONCILIATION_REPORT.md`) | **Engel yok** (`exit code 1` — hiçbiri ignore edilmiyor) |
| **Harici URL / CDN Bağımlılığı** | Tüm `.html`, `.css`, `.js` dosyalarında `https?://`, `<script`, `<link`, `@import`, `@font-face`, `url(...)`, `fetch(`, `XMLHttpRequest` taraması | **0 harici URL / CDN** — Yalnızca yerel `shared.css` ve `shared.js` bağlantıları var |

---

## 5. UI/UX HTML Prototipleri ve Dokümantasyonun Git'e Uygunluk Değerlendirmesi

1. **Hacim ve Dosya Yapısı Uygunluğu:**
   - `docs/ui-ux/` altındaki 32 dosya tamamen düz metin kaynaklardan (`Markdown`, `HTML`, `CSS`, `JS`) oluşur ve toplam boyutu **577.745 bayt (~564,2 KB)** seviyesindedir (en büyük dosya `UX_TARGETED_AUDIT_REPORT.md` 59.142 B; en büyük HTML prototip `market_mms_prototype.html` 31.634 B; en büyük güncel ekran `win-02-pos.html` 18.170 B). Binary medya, gömülü resim, derlenmiş paket veya `node_modules` bulunmadığından depo boyutuna olumsuz etkisi yoktur.
2. **%100 Çevrimdışı Çalışma (Offline Self-Containment):**
   - 10 güncel tasarım ekranı, `index.html` ve `market_mms_prototype.html` harici Google Fonts, CDN CSS/JS veya uzak API çağrısı yapmaz. Depoyu klonlayan her geliştirici tarayıcıda doğrudan çevrimdışı inceleme yapabilir.
3. **Node.js Doğrulama Betiklerinin Saklanması (`verify_wcag.js`, `test_currency_engine.js`):**
   - Sıfır harici npm paketine ihtiyaç duyar (`yalnızca Node.js fs` ve `./shared.js` kullanır) ve tasarım teslimatının yeniden doğrulanabilir kanıtını oluşturur. `docs/ui-ux/visual-designs/` içinde korunmaları uygundur.
4. **Engelleyici Olmayan Makine-Özel Yerel Link Gözlemi (`file:///c:/Users/...`):**
   - 5 Markdown raporunda toplam 29 adet (ayrıca `BUSINESS_RULES_SPEC.md:455` içinde pre-existing 1 adet -> toplam 30 eşleşme) `file:///c:/Users/halil/Github/market-pos/...` bağlantısı veya `PS C:\Users\halil\Github\market-pos>` terminal çıktısı alıntısı mevcuttur (`.html`/`.css`/`.js` dosyalarında **0** adet).
   - Terminal çıktıları tarihsel kanıt niteliğindedir. Ancak [`VISUAL_DESIGN_DELIVERY_REPORT.md`](../ui-ux/visual-designs/VISUAL_DESIGN_DELIVERY_REPORT.md) (13 bağlantı) ve [`UX_FINAL_DELIVERY_REPORT.md`](../ui-ux/UX_FINAL_DELIVERY_REPORT.md) (1 bağlantı) içindeki mutlak `file:///c:/Users/halil/...` linkleri başka makinelerde tıklanabilir olmayacağı için Git taşınabilirliği açısından idealde göreli linklere (`./index.html`, `./visual-designs/`) dönüştürülebilir; yine de Git güvenliği veya çalışma açısından **bloklayıcı değildir** ve kabul edilmiş UI/UX içeriğini izinsiz değiştirmemek adına olduğu gibi bırakılmıştır.
5. **Commit Yapısı Değerlendirmesi:**
   - Bu çalışma birbirinden net ayrılabilen iki mantıksal teslimattan oluşmaktadır: **(1)** Kabul edilmiş 32 dosyalık UI/UX Tasarım Paketi ve **(2)** 3 uzlaştırılmış kanonik doküman + bekleyen 5 (+ opsiyonel 1) geliştirme/Git raporu. Bu iki grubu **iki ayrı atomik commit** hâlinde almak Git geçmişini en okunabilir ve geri izlenebilir kılar; Proje Sahibi isterse tek atomik commit de tercih edebilir.

---

## 6. Açıkça Belirtilmiş Dosya Yollarıyla Staging Önerisi

> [!CAUTION]
> **Kesin Yasak (`AGENTS.md` §13–14):** `git add .` veya `git add -A` **KESİNLİKLE KULLANILMAMALIDIR**. Aşağıdaki açık dosya yolları (`explicit paths`) yalnızca Proje Sahibi onayından sonra kullanılmalıdır.

### 6.1 Seçenek A — İki Temiz Atomik Commit (ÖNERİLEN)

#### Commit 1 — Kabul Edilmiş UI/UX Tasarım Sistemi, Prototipler ve Denetim Paketleri (32 Dosya)
- **Önerilen Commit Mesajı:** `docs(ui-ux): add accepted design system, offline html prototypes and verification reports`
- **Explicit Staging Dosya Listesi (`32` dosya):**
  - `docs/ui-ux/DESIGN_DECISIONS.md`
  - `docs/ui-ux/DESIGN_REFERENCES_AND_LICENSES.md`
  - `docs/ui-ux/market_mms_prototype.html`
  - `docs/ui-ux/UX_01_FINAL_REVIEW_REPORT.md`
  - `docs/ui-ux/UX_01_USER_RESEARCH.md`
  - `docs/ui-ux/UX_01_USER_SCENARIOS_AND_PRODUCT_ANALYSIS.md`
  - `docs/ui-ux/UX_02_INFORMATION_ARCHITECTURE.md`
  - `docs/ui-ux/UX_03_DESIGN_SYSTEM.md`
  - `docs/ui-ux/UX_04_SCREEN_DESIGNS.md`
  - `docs/ui-ux/UX_05_INTERACTIVE_PROTOTYPE.md`
  - `docs/ui-ux/UX_06_USABILITY_VALIDATION.md`
  - `docs/ui-ux/UX_07_FLUTTER_HANDOFF.md`
  - `docs/ui-ux/UX_FINAL_DELIVERY_REPORT.md`
  - `docs/ui-ux/UX_FINAL_VERIFICATION_AND_RECONCILIATION_REPORT.md`
  - `docs/ui-ux/UX_INDEPENDENT_REVIEW_PACKAGE.md`
  - `docs/ui-ux/UX_TARGETED_AUDIT_REPORT.md`
  - `docs/ui-ux/visual-designs/index.html`
  - `docs/ui-ux/visual-designs/mob-01-dashboard.html`
  - `docs/ui-ux/visual-designs/mob-02-barcode-scan.html`
  - `docs/ui-ux/visual-designs/mob-03-cart-checkout.html`
  - `docs/ui-ux/visual-designs/mob-04-stock-view.html`
  - `docs/ui-ux/visual-designs/shared.css`
  - `docs/ui-ux/visual-designs/shared.js`
  - `docs/ui-ux/visual-designs/test_currency_engine.js`
  - `docs/ui-ux/visual-designs/verify_wcag.js`
  - `docs/ui-ux/visual-designs/VISUAL_DESIGN_DELIVERY_REPORT.md`
  - `docs/ui-ux/visual-designs/win-01-dashboard.html`
  - `docs/ui-ux/visual-designs/win-02-pos.html`
  - `docs/ui-ux/visual-designs/win-03-product-search.html`
  - `docs/ui-ux/visual-designs/win-04-payment-modal.html`
  - `docs/ui-ux/visual-designs/win-05-sales-history.html`
  - `docs/ui-ux/visual-designs/win-06-stock-management.html`

#### Commit 2 — Kanonik Dokümantasyon Uzlaştırması & Bekleyen Faz Raporları (8 veya 9 Dosya)
- **Önerilen Commit Mesajı:** `docs(reconciliation): reconcile canonical specs with ui-ux decisions and record phase reports`
- **Explicit Staging Dosya Listesi (`8` zorunlu + `1` opsiyonel bu rapor):**
  - `docs/PROJECT_STATUS.md`
  - `docs/REQUIREMENTS.md`
  - `docs/requirements/BUSINESS_RULES_SPEC.md`
  - `docs/development/DOCUMENTATION_RECONCILIATION_REPORT.md`
  - `docs/development/PHASE_1_1_GIT_EXECUTION_REPORT.md`
  - `docs/development/PHASE_1_2_PREPARATION_REPORT.md`
  - `docs/development/PHASE_1_2_FINAL_PREFLIGHT_REPORT.md`
  - `docs/development/PHASE_1_2_PAYMENT_METHOD_GIT_EXECUTION_REPORT.md`
  - *(Opsiyonel — Proje Sahibi dahil etmek isterse)* `docs/development/UI_UX_GIT_PREFLIGHT_REPORT.md`

### 6.2 Seçenek B — Tek Birleşik Atomik Commit (Alternatif — 40 veya 41 Dosya)
- Proje Sahibi UI/UX paketi, uzlaştırılmış 3 kanonik doküman ve `docs/development/` raporlarını tek commit'te toplamak isterse, Seçenek A'daki 32 + 8 (+ opsiyonel bu rapor) açık dosya yolu tek bir `git add <explicit-paths>` çağrısında birleştirilebilir (`docs(release): add accepted ui-ux package and reconciled canonical docs`).

### 6.3 Kesinlikle Stage Edilmeyecek Kapsam Dışı Öğeler
- `.gitignore` kapsamındaki tüm çalışma dizinleri, derleme ikilileri ve sır dosyaları (`.dart_tool/`, `build/`, `test_spikes/spike_01_backend/pepper.dpapi`, `test_spikes/spike_01_backend/backups/`, `test_spikes/spike_01_backend/logs/`, `test_spikes/spike_01_backend/service_wrapper/*.exe`).
- Uygulama kaynak kodları (zaten 0 değişiklik).

---

## 7. Son Durum Teyidi ve Sonraki Adım

- **Staging (`git add`):** Yapılmadı (`0` staged dosya).
- **Commit (`git commit`):** Yapılmadı (`HEAD` hâlâ `b069d5b`).
- **Push (`git push`):** Yapılmadı (`HEAD == origin/main`).
- **Tek Eklenen Dosya:** `docs/development/UI_UX_GIT_PREFLIGHT_REPORT.md`.

Proje Sahibi bu preflight raporunu inceledikten sonra:
1. Seçenek A (2 atomik commit) veya Seçenek B (tek commit) tercihini,
2. İşbu preflight raporunun (`UI_UX_GIT_PREFLIGHT_REPORT.md`) commit'e dahil edilip edilmeyeceğini,
3. İsterse `VISUAL_DESIGN_DELIVERY_REPORT.md` / `UX_FINAL_DELIVERY_REPORT.md` içindeki makine-özel `file:///c:/...` linklerinin olduğu gibi bırakılıp bırakılmayacağını,
4. Açık **`git add` / `git commit` / `git push` onayını** verdiğinde yürütme başlatılacaktır.

