# MARKET MMS — UX Final Verification & Project Status Reconciliation Report

**Rapor Kodu:** `UX_FINAL_VERIFICATION_AND_RECONCILIATION_REPORT.md`  
**Tarih:** 11 Kasım 2026  
**Proje / Depo:** `market-pos` (**MARKET MANAGEMENT SYSTEM — MARKET MMS**)  
**Hazırlayan:** Antigravity (Gemini)  
**Bağlayıcı Anayasa:** [`AGENTS.md`](../../AGENTS.md), [`GEMINI.md`](../../GEMINI.md), [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](../../MARKET_POS_AI_STUDIO_BUILD_PLANI.md) (v1.4)  
**Görev Niteliği:** Doğrulama, Teknik Düzeltme, Karar Kapanışı & Hazırlık Uzlaştırması (v1.2 — UX Kabulü & `OD-01..OD-04` Kapanışı Eklendi)

> [!NOTE]
> **Yönetişim ve Yetki Sınırı (`AGENTS.md` Madde 13–15):**  
> Bu rapor ilk doğrulama (`v1.0`) ve düzeltme (`v1.1`) kayıtlarını **tarihsel kanıt olarak korur**. **11 Kasım 2026** tarihinde Proje Sahibi mevcut UI/UX teslimatını **kabul etmiş** ve `OD-01`..`OD-04` açık kararlarını kapatmıştır (bkz. Bölüm 13 Karar Kapanışı Eki).  
> Hâlen **hiçbir Git stage (`git add`), commit veya push işlemi yapılmamış**, **hiçbir uygulama kaynak koduna (`lib/`, `test/`, `pubspec.yaml`, backend, veritabanı) dokunulmamıştır**. Faz 1.2 kodlaması ve Git işlemleri Proje Sahibi onayı beklemektedir.

---

## 1. Depo ve Git Durumu

Tüm Git kontrolleri 11 Kasım 2026 tarihinde çalışma dizini `c:\Users\halil\Github\market-pos` üzerinde fiilen çalıştırılmıştır:

| Kontrol | Komut | Gerçek Çıktı | Değerlendirme |
|---|---|---|---|
| **Aktif Branch** | `git branch --show-current` | `main` | ✅ Doğru dal |
| **HEAD vs `origin/main`** | `git rev-parse HEAD`, `git rev-parse origin/main`, `git rev-list --left-right --count origin/main...HEAD` | `32111b8aeed6fd396c2ed06e543824e9e22529b2` (her ikisi), fark: `0 0` | ✅ Uzak depo ile tam senkron |
| **Son Commit** | `git log -n 1 --stat` | `32111b8` (`Fri Nov 6 18:12:12 2026 +0300`) — `docs(audit): document DT-01 developer tooling audits and Phase 1.1 git execution` (7 dosya, +1418 satır) | ✅ DT-01 denetimleri commitli |
| **`git status --short`** | `git status --short` | `?? docs/development/PHASE_1_1_GIT_EXECUTION_REPORT.md`<br/>`?? docs/ui-ux/` | ⚠️ Untracked teslimatlar mevcut |
| **Staged Değişiklikler** | `git diff --cached --stat` | *(Boş — 0 bayt)* | ✅ Staging alanı temiz |
| **Unstaged (Tracked) Değişiklikler** | `git diff --stat` | *(Boş — 0 bayt)* | ✅ Tracked dosyalar değiştirilmemiş |

### 1.1 Untracked Dosyalar Tam Listesi (`git ls-files --others --exclude-standard`)

Toplam **32 adet** untracked dosya mevcuttur:
- `docs/development/PHASE_1_1_GIT_EXECUTION_REPORT.md` (1 dosya — içeriği DT-01 Git yürütme raporudur; bkz. Bölüm 7 & 10)
- `docs/ui-ux/` altında **31 dosya**:
  - Dokümantasyon ve raporlar (14): `DESIGN_DECISIONS.md`, `DESIGN_REFERENCES_AND_LICENSES.md`, `UX_01_FINAL_REVIEW_REPORT.md`, `UX_01_USER_RESEARCH.md`, `UX_01_USER_SCENARIOS_AND_PRODUCT_ANALYSIS.md`, `UX_02_INFORMATION_ARCHITECTURE.md`, `UX_03_DESIGN_SYSTEM.md`, `UX_04_SCREEN_DESIGNS.md`, `UX_05_INTERACTIVE_PROTOTYPE.md`, `UX_06_USABILITY_VALIDATION.md`, `UX_07_FLUTTER_HANDOFF.md`, `UX_FINAL_DELIVERY_REPORT.md`, `UX_INDEPENDENT_REVIEW_PACKAGE.md`, `UX_TARGETED_AUDIT_REPORT.md`
  - Etkileşimli prototip (1): `market_mms_prototype.html`
  - Görsel ekran koleksiyonu ve doğrulama araçları (16): `visual-designs/VISUAL_DESIGN_DELIVERY_REPORT.md`, `visual-designs/index.html`, `visual-designs/shared.css`, `visual-designs/shared.js`, `visual-designs/test_currency_engine.js`, `visual-designs/verify_wcag.js`, 6 Windows HTML ekranı (`win-01-dashboard.html` .. `win-06-stock-management.html`), 4 Mobil HTML ekranı (`mob-01-dashboard.html` .. `mob-04-stock-view.html`)

*(Ek: Çalışma alanı bütünlüğü için `flutter analyze --no-pub` → `No issues found! (ran in 4.3s)` ve `flutter test` → `00:06 +31: All tests passed!` doğrulandı.)*

---

## 2. UX Dosyalarının Gerçek Durumu

1. **Fiziksel Varlık:** `docs/ui-ux/` altındaki 31 dosyanın tamamı diskte mevcuttur ve boş değildir (`5,795` – `49,462` bayt aralığında).
2. **Git ve Kabul Durumu:** Dosyaların tamamı **untracked** durumdadır; hiçbir UX dosyası commit edilmemiştir ve **Proje Sahibi tarafından henüz resmi olarak kabul edilmemiştir**.
3. **İç Tutarlılık & Uzlaştırma Durumu:**
   - **İlk doğrulama (`v1.0`):** `UX_FINAL_DELIVERY_REPORT.md` v1.5 ve `UX_TARGETED_AUDIT_REPORT.md` v1.1 içindeki bazı test/ID uyumsuzlukları, eski UX dokümanlarındaki `₺`/sayım/kasiyer kalıntıları ve Dark mod inline kontrast açıkları tespit edildi (aşağıdaki Bölüm 3–7 bulguları).
   - **Final Remediation (`v1.1` — 11 Kasım 2026):** Tespit edilen tüm teknik, WCAG/kontrast, `-0`/`-0.00` para motoru, `market_mms_prototype.html` legacy/syntax, touch/responsive, `AppTheme`/`main_shell_screen.dart` handoff, `BUSINESS_RULES_SPEC.md`/`PROJECT_STATUS.md` uzlaştırma ve denetim raporu açıkları giderildi ve yeniden çalıştırılarak doğrulandı (bkz. Bölüm 12).

---

## 3. Para Motoru Test Sonuçları

### 3.1 Kaynak Kod Doğrulaması ([`shared.js`](./visual-designs/shared.js) & [`test_currency_engine.js`](./visual-designs/test_currency_engine.js))

| Kontrol Kriteri | Gerçek Durum ve Kanıt | Sonuç |
|---|---|---:|
| **Integer kuruş hesaplaması** | `parseToCents()` (`shared.js:69-191`) tam sayı parçalama + `BigInt(intPartStr) * 100n + BigInt(decKurus)` kullanır. `formatKurus()` (`L33-45`) ve `formatCentsToInput()` (`L49-60`) `Math.floor(absCents / 100)` ve `absCents % 100` ile çalışır. | ✅ PASS |
| **`parseFloat` yasağı** | `shared.js` içinde `parseFloat` yalnızca yorumda (`L63`) geçer; kodda **hiç çağrılmaz** (`parseInt(..., 10)` ve `BigInt` kullanılır). | ✅ PASS |
| **`toFixed` yasağı** | `shared.js` içinde `toFixed` yalnızca yorumda (`L47`) geçer; kodda **hiç çağrılmaz**. | ✅ PASS |
| **Binlik ayırıcı doğrulaması** | `L130-159`: Nokta/virgül son konumuna göre `^\d{1,3}(,\d{3})+(\.\d{1,2})?$` ve `^\d{1,3}(\.\d{3})+(,\d{1,2})?$` regex'leri 3'lü gruplamayı doğrular. `1,25.00`, `1,,250.00`, `12,34,567.89` reddedilir. | ✅ PASS |
| **Türkçe ve standart sayı girişleri** | `12.50`, `12,50`, `1,250.00`, `1.250,00`, `12 Tl`, `12 tL` doğru ayrıştırılır. Tek ayırıcılı 3 basamak (`1,250`, `1.250`) belirsizliğe karşı reddedilir. | ✅ PASS |
| **Negatif değer politikası** | `allowNegative = false` iken `-5`, `-0.50` reddedilir (`L89-92`). **Not (Kenar Durum):** `allowNegative = true` iken `"-0"` veya `"-0.00"` verildiğinde `L187` (`isNegative ? -totalCents : totalCents`) JS'de `-0` (`Object.is(res.cents, -0) === true`) döndürür. | ⚠️ UYARI |
| **Güvenli tamsayı sınırı** | `L183`: `totalCentsBig > BigInt(Number.MAX_SAFE_INTEGER)` kontrolü ile `90071992547409.91` (`9007199254740991`) kabul, `90071992547409.92` reddedilir. | ✅ PASS |
| **Hatalı girişlerde sessiz sıfırlama yok** | `parseToCents()` hatalı girdide `{ valid: false, error: ... }` döner. `formatKurus()` ve `formatCentsToInput()` (`L34-36, 50-52`) `NaN`, `null`, `undefined` ve `12.5` (float) için `TypeError` fırlatır. | ✅ PASS |
| **`12.50 TL` formatı tüm ekranlarda** | `visual-designs/` içindeki **10 HTML ekranı + `index.html` + `market_mms_prototype.html`** taramasında `₺` sayısı **0**'dır. *Ancak* eski Markdown belgelerinde (`UX_04`, `UX_05`, `UX_06`) `₺` ve virgüllü format kalıntıları mevcuttur. | ⚠️ KISMİ |

> [!WARNING]
> **Ek Kritik Bulgu — [`market_mms_prototype.html`](./market_mms_prototype.html) Ayrışması:**  
> `market_mms_prototype.html` dosyası `shared.js`'yi import etmez; satır `317-353` arasında kendi eski `formatKurus` / `parseToCents` fonksiyonlarını barındırır. Bu satır içi kopyada `formatKurus(NaN)` sessizce `'0.00 TL'` döner (`L318`), `Math.round(cents)` kullanılır (`L319, L330`), `1,250.00` binlik ayırıcısı reddedilir ve `MAX_SAFE_INTEGER` kontrolü yoktur. Ayrıca `L240`'taki `X` butonu tanımlı olmayan `multiplyQty()` fonksiyonunu çağırmaktadır.

### 3.2 Gerçek Terminal Test Çıktısı (`node docs/ui-ux/visual-designs/test_currency_engine.js`)

```text
================================================================
 MARKET MMS — JAVASCRIPT KURUŞ PARA MOTORU DOĞRULAMA TESTLERİ
 Standart: 12.50 TL | Kuruş Tamsayı Standardı [INV-01]
================================================================

--- 1. BÖLÜM: parseToCents() Ayrıştırma Testleri (13 Test) ---
  [PASS] Test #1: parseToCents("12.50") standart iki basamaklı kuruş
  [PASS] Test #2: parseToCents("12.5") tek basamaklı kuruş (12.50 TL karşılığı)
  [PASS] Test #3: parseToCents("12") tamsayı lira
  [PASS] Test #4: parseToCents("0.50") alt lira standart
  [PASS] Test #5: parseToCents("0.5") alt lira tek basamak
  [PASS] Test #6: parseToCents("0") sıfır tutar
  [PASS] Test #7: parseToCents("12.50 TL") TL para birimi eki içeren metin
  [PASS] Test #8: parseToCents("") boş metin girişi
  [PASS] Test #9: parseToCents("abc") geçersiz harfli metin
  [PASS] Test #10: parseToCents("-5") negatif tutar (allowNegative=false)
  [PASS] Test #11: parseToCents("-5", true) negatif tutar (allowNegative=true)
  [PASS] Test #12: parseToCents("12.345") 3 ondalık basamaklı girdi
  [PASS] Test #13: parseToCents("12..50") çoklu ondalık nokta

--- 2. BÖLÜM: formatKurus() Formatlama & Hata Yönetimi Testleri ---
  [PASS] Test #14: formatKurus(1250) -> "12.50 TL"
  [PASS] Test #15: formatKurus(99) -> "0.99 TL"
  [PASS] Test #16: formatKurus(125000) -> "1,250.00 TL"
  [PASS] Test #17: formatKurus(0) -> "0.00 TL"
  [PASS] Test #18: formatKurus(-500) -> "-5.00 TL"
  [PASS] Test #19: formatKurus(NaN) TypeError fırlatmalı (sessizce yutulamaz) -> TypeError: Geçersiz kuruş değeri: "NaN". Değer güvenli bir tamsayı (int) olmalıdır.
  [PASS] Test #20: formatKurus(null) TypeError fırlatmalı (sessizce yutulamaz) -> TypeError: Geçersiz kuruş değeri: "null". Değer güvenli bir tamsayı (int) olmalıdır.
  [PASS] Test #21: formatKurus(12.5) float kuruş girişi reddedilmeli -> TypeError: Geçersiz kuruş değeri: "12.5". Değer güvenli bir tamsayı (int) olmalıdır.

--- 3. BÖLÜM: formatCentsToInput() İnput Formatlayıcı Testleri ---
  [PASS] Test #22: formatCentsToInput(1250) -> "12.50"
  [PASS] Test #23: formatCentsToInput(50) -> "0.50"
  [PASS] Test #24: formatCentsToInput(0) -> "0.00"
  [PASS] Test #25: formatCentsToInput(undefined) TypeError fırlatmalı -> TypeError: Geçersiz kuruş değeri: "undefined". Değer güvenli bir tamsayı (int) olmalıdır.

--- 4. BÖLÜM: Yeni Zorunlu Sınır & Ayırıcı Doğrulama Testleri ---
  [PASS] Test #26: parseToCents("12,50") Türkçe tek virgül ondalık
  [PASS] Test #27: parseToCents("1,250.00") standart 3 basamaklı binlik virgüllü
  [PASS] Test #28: parseToCents("1.250,00") Türkçe noktalı binlik virgüllü ondalık
  [PASS] Test #29: parseToCents("1,25.00") hatalı 2 basamaklı binlik ayırıcı
  [PASS] Test #30: parseToCents("1,,250.00") ardışık çift virgüllü girdi
  [PASS] Test #31: parseToCents("12,34,567.89") hatalı basamak gruplama
  [PASS] Test #32: parseToCents("12 Tl") mixed-case TL soneki
  [PASS] Test #33: parseToCents("12 tL") mixed-case tL soneki
  [PASS] Test #34: parseToCents("-0.50") varsayılanda ret (allowNegative=false)
  [PASS] Test #35: parseToCents("-0.50", true) izinli negatif alt lira
  [PASS] Test #36: parseToCents("90071992547409.91") MAX_SAFE_INTEGER sınırında tam kuruş
  [PASS] Test #37: parseToCents("90071992547409.92") MAX_SAFE_INTEGER sınır aşımı

================================================================
 TEST RAPORU: Toplam: 37 | Başarılı: 37 | Başarısız: 0
================================================================
```

*(Önceki rapor çelişkisi: [`UX_TARGETED_AUDIT_REPORT.md`](./UX_TARGETED_AUDIT_REPORT.md) satır `458-501` arasındaki terminal çıktısı gerçek `test_currency_engine.js` çıktı biçimiyle ve test isimleriyle uyuşmamakta, ayrıca mevcut betikte bulunmayan `Test #36: Negative zero: -0.00 -> 0 kurus` satırını göstermektedir.)*

---

## 4. WCAG Test Sonuçları

### 4.1 `verify_wcag.js` Çalıştırma Sonucu

`node docs/ui-ux/visual-designs/verify_wcag.js` komutu çalıştırılmış ve tanımlı **55/55 kontrolün PASS** döndüğü doğrulanmıştır (`0` başarısız; Light tema 26 kontrol, Dark tema 29 kontrol; IEC 61966-2-1:1999 resmi `0.04045` eşiği kullanılmıştır).

### 4.2 `shared.css` ve HTML Ekranlarıyla Çapraz Doğrulama Bulguları

`verify_wcag.js` betiğinin kapsamadığı veya CSS/HTML gerçeğiyle farklılaştığı kritik noktalar tespit edilmiştir:

1. **KRİTİK FAIL — Dark Modda Inline `var(--success)`, `var(--warning)`, `var(--danger)` Metin Kullanımı (Test Dışı Kalmış ve Başarısız):**
   [`shared.css`](./visual-designs/shared.css) satır `76, 84, 88`'de Dark tema altında `--success: #047857`, `--warning: #B45309`, `--danger: #B91C1C` (buton arka planları) değişmeden bırakılmıştır; metinler için aydınlık `--success-text` (`#34D399`), `--warning-text` (`#FBBF24`), `--danger-text` (`#F87171`) tokenları tanımlanmıştır. Ancak 7 HTML ekranında metin rengi olarak `-text` sonekli token yerine doğrudan `var(--success)` / `var(--warning)` / `var(--danger)` kullanılmıştır:

   | Gerçek Ekran & Satır | CSS Çifti (FG on BG) | Hesaplanan Oran | WCAG Eşiği | Durum |
   |---|---|---:|:---:|:---:|
   | `win-01:125`, `win-03:135,146,157`, `mob-01:82`, `mob-04:139,148` | Dark `--success` (`#047857`) on `--bg-surface` (`#1E293B`) | **2.67:1** | ≥ 4.5:1 | ❌ **FAIL** |
   | `win-05:201` | Dark `--success` (`#047857`) on `--bg-surface-subtle` (`#0F172A`) | **3.26:1** | ≥ 4.5:1 | ❌ **FAIL** |
   | `win-01:135`, `win-06:116,126,156`, `mob-01:121,125` | Dark `--warning` (`#B45309`) on `--bg-surface` (`#1E293B`) | **2.91:1** | ≥ 4.5:1 | ❌ **FAIL** |
   | `win-01:205,213,221`, `mob-04:93` | Dark `--warning` (`#B45309`) on `--bg-surface-subtle` (`#0F172A`) | **3.56:1** | ≥ 4.5:1 | ❌ **FAIL** |
   | `win-06:115,125,145`, `mob-04:121,130` | Dark `--danger` (`#B91C1C`) on `--bg-surface` (`#1E293B`) | **2.26:1** | ≥ 4.5:1 | ❌ **FAIL** |
   | `win-04:205,217` (Hatalı/Eksik nakit durumunda JS `changeBox.style.color = 'var(--danger)'`) | Dark `--danger` (`#B91C1C`) on `--success-bg` (`rgba(4,120,87,0.2)` blended over `#1E293B`) | **1.91:1** | ≥ 4.5:1 | ❌ **FAIL** |

2. **Light Modda `--text-muted` on `--bg-surface-subtle` Sınır Altı Kontrast:**
   `win-02:55` (`.cart-summary-footer`), `win-05:197` (ödeme özet kutusu) ve `mob-04:92,97,99` (`.stock-metric-box`) bileşenlerinde `#64748B` metni `#F1F5F9` zemin üzerinde **4.34:1** vermektedir (4.5:1 normal metin kriterinin altında; ❌ **FAIL**). `verify_wcag.js:60` yalnızca `#64748B` on `#FFFFFF` (`4.76:1`) durumunu test etmiştir.
3. **`win-04` Dark Mod Para Üstü Kutusu Yüzey Uyuşmazlığı:**
   `win-04-payment-modal.html:69` üzerinde `.change-display-box` arka planı `var(--success-bg)` (`rgba(4,120,87,0.2)` over `#1E293B`) iken `verify_wcag.js:118` bunu düz `#1E293B` üzerinde test edip `7.61:1` (AAA) göstermiştir. Gerçek blended yüzeyde `#34D399` kontrastı **6.41:1** (AA geçer, AAA değil).
4. **RGBA Yüzey Birleştirme Kontrolü:**
   `verify_wcag.js:44-55` Dark rozetler ve tablo hover satırları için alpha blending hesabını doğru uygulamıştır (`#1E293B` ve `#0F172A` üzerinde `6.41:1` – `12.88:1`). Ancak `win-06:72` banner'ı `.desktop-content` (`--bg-app: #090D16`) üzerinde `var(--warning-bg)` kullanmaktadır; Node ile doğrulanan blended kontrastı **9.91:1** (AAA).
5. **Test Edilmeyen CSS Durumları (PASS Sayılamaz):**
   - `.btn:disabled` (`shared.css:159-165`, `opacity: 0.45`) — WCAG 1.4.3'ten muaf olsa da betikte test edilmemiştir.
   - `.btn:active` (`shared.css:156-158`) ve `.banknote-btn:hover` (`win-04:64-67`).
   - `.btn-primary` (`shared.css:166-170` — Light `17.85:1`, Dark `17.06:1`).
   - Dark `.btn-card:hover` (`shared.css:80` `--accent: #1D4ED8` ve `L191` `.btn-card:hover: #1D4ED8` birebir aynı renk olduğu için hover'da görsel değişim oluşmaz; ayrıca `UX_TARGETED_AUDIT_REPORT.md:563`'teki `Test #47: Dark - Card Button Hover [8.76:1]` satırı gerçek `verify_wcag.js` betiğinde **bulunmamaktadır**).
   - `.input-error-msg` (`shared.css:261-269`: Light `#991B1B` on `#FFF` = `8.31:1`, Dark `#F87171` on `#1E293B` = `5.29:1`) ve pasif `.nav-link` / `.mob-nav-item`.
6. **WCAG Kapsam Sınırı:** Renk kontrastı hesaplaması **tam WCAG 2.1 AA uygunluğu değildir**. Ekranlarda `aria-label` eksikliği, modal focus trap yokluğu, `win-02:41` `.barcode-input-pos` üzerinde `outline: none` bulunup `:focus-visible` kuralı olmaması ve `win-02:288-293` hızlı tuşlarının `<button>` yerine `<div>` olması erişilebilirlik eksikleridir.

---

## 5. 10 Ekranın Kontrol Sonuçları

> [!IMPORTANT]
> **Prototip Sınırı:** İncelenen 10 HTML ekranı (ve `index.html` / `market_mms_prototype.html`) **Flutter uygulaması değildir**; yalnızca tarayıcıda görüntülenen HTML/CSS/JS görsel tasarım maketleridir. Hiçbir fiziksel Android/iOS cihaz, USB HID barkod okuyucu veya dokunmatik POS monitörü üzerinde saha testi **yapılmamıştır**.

| Ekran | Para Formatı | Dokunmatik Hedefler | Tema (Light/Dark) | Gerçek Etkileşim vs Simülasyon | İş Kuralı / Tasarım Bulguları |
|---|---|---|---|---|---|
| **[`win-01-dashboard.html`](./visual-designs/win-01-dashboard.html)** | `12.50 TL` ✅ | Tema/butonlar `.btn` (~34px), desktop standart | Dark `--success` (`2.67:1`), `--warning` (`2.91–3.56:1`) ❌ | **Gerçek:** `toggleTheme()`, linkler.<br/>**Statik:** KPI & tablolar. | `L80` menü `"Stok & Sayım"`, `L223` `"Stok sayım düzeltmesi"` (MVP dışı sayım kalıntısı). `.kpi-grid`/`.dashboard-grid` (`L9-47`) `<=1024px` kırılımı yok. |
| **[`win-02-pos.html`](./visual-designs/win-02-pos.html)** | `12.50 TL` ✅ | `+`/`-`/`×` **48×48px** (`L224-268`), barkod/Ara **48px** (`L33,198`); ancak `.numpad-btn` **46px** (`L102`), Tema **~34px** | Light/Dark temel uyumlu | **Gerçek:** `toggleTheme()`, ödeme linki.<br/>**Statik:** Barkod input, `+`/`-`/`×`, quick-keys, numpad, F11/F12. | `L159` `"Stok & Sayım"`. `L288-293` `<div class="quick-key-btn">` klavyeyle odaklanamaz. `L41` `outline: none`. `L212` `140px` sütununda `48px` butonlar dar genişlikte taşma/sıkışma riski taşır. `.pos-canvas` (`L9`) dar ekranda alt alta kırılmaz. |
| **[`win-03-product-search.html`](./visual-designs/win-03-product-search.html)** | `12.50 TL` ✅ | `Sepete Ekle` **~26px** (`L115-159`: `padding: 4px 10px`), Tema **~34px** | Dark `--success` (`2.67:1`) ❌ (`L135,146,157`) | **Gerçek:** `toggleTheme()`, link.<br/>**Statik:** Arama, select, checkbox, `+ Yeni Ürün Ekle`. | `L39` `"Stok & Sayım"`. Dokunmatik POS monitörü için tablo satırı aksiyon butonları `<48px`. |
| **[`win-04-payment-modal.html`](./visual-designs/win-04-payment-modal.html)** | `12.50 TL` ✅ | Banknot **48px** (`L52`), input **48px** (`L155`), İptal/Tamamla **50px** (`L170-173`); **Ancak `×` kapatma linki <48px (`L101`)** | Dark hata metni `--danger` on `--success-bg` **1.91:1** ❌ (`L205,217`) | **Gerçek:** `setAmount`, `parseToCents`, `formatKurus`, `Enter`/`ESC`.<br/>**Simülasyon:** `alert()` ve `Kredi Kartı` radio değişimi JS'de işlenmiyor (`L119-126`). | Kart seçilse de `confirmSale()` nakit kontrolü çalıştırır (`L221-235`). `.input-error` sınıfı uygulanmamış. |
| **[`win-05-sales-history.html`](./visual-designs/win-05-sales-history.html)** | `12.50 TL` ✅ | Alt butonlar `.btn` (~34px) | Dark `--success` (`3.26:1`) ❌ (`L201`) | **Gerçek:** `toggleTheme()`.<br/>**Simülasyon:** Fiş listesi statik; İade ve Yazdırma `alert()` (`L213,216`). | `L54` `"Stok & Sayım"`. `.sales-split` (`L9`) ve filtre satırı (`L89`) `<=1024px` kırılımı/wrap içermiyor. Offline iken iade engeli UI'da yok. |
| **[`win-06-stock-management.html`](./visual-designs/win-06-stock-management.html)** | Sayısal Adet | Üst/filtre butonları `.btn` (~34px) | Dark `--danger` (`2.26:1`), `--warning` (`2.91:1`), `--success` (`2.67:1`) ❌ | **Gerçek:** `toggleTheme()`.<br/>**Simülasyon:** Mal kabul `alert()` (`L62`); filtre/tablo statik. | `L39` `"Stok & Sayım"`, `L87` `Sayım Düzeltmesi (AUDIT)`, `L144-148` `SAYIM DÜZELTME / Raf Sayım Farkı` → **MVP dışı sayım kuralıyla çelişir!** |
| **[`mob-01-dashboard.html`](./visual-designs/mob-01-dashboard.html)** | `12.50 TL` ✅ | Tema **48×48px** (`L64`), kart aksiyonları >48px (`L93,97`), alt bar 64px (`L133`); *`Menü` linki (`L50`) <48px* | Dark `--success` (`2.67:1`), `--warning` (`2.91:1`) ❌ | **Gerçek:** `toggleTheme()`, linkler.<br/>**Statik:** Ciro/outbox/eksi stok kartları. | `@media (max-width:480px)` tam ekran çalışır; `@media (max-height:840px)` çerçeveyi uyarlar. |
| **[`mob-02-barcode-scan.html`](./visual-designs/mob-02-barcode-scan.html)** | `12.50 TL` ✅ | Fener & Tema **48×48px** (`L68,71`), çekmece butonları **48px** (`L102,105`) | Light/Dark uyumlu | **Gerçek:** `toggleTheme()`, CSS lazer animasyonu.<br/>**Simülasyon:** Kamera yok, Fener `alert()`. | Alt çekmece & vizör yerleşimi MVP kapsamıyla uyumlu. |
| **[`mob-03-cart-checkout.html`](./visual-designs/mob-03-cart-checkout.html)** | `12.50 TL` ✅ | Temizle/Tema **48×48px** (`L46,49`), `+`/`-` **48×48px** (`L67-105`), Nakit/Kart **50px** (`L127,130`) | Light/Dark uyumlu | **Gerçek:** `toggleTheme()`.<br/>**Simülasyon:** `+`/`-` işlevsiz; Nakit/Kart `alert()`. | `360px` dar genişlikte 3 sütunlu sepet kartı (`flex:1` + `132px` butonlar + `65px` tutar) metni sıkıştırabilir. |
| **[`mob-04-stock-view.html`](./visual-designs/mob-04-stock-view.html)** | `12.50 TL` ✅ | Tara/Tema/Ara **48×48px** (`L60,63,75`), input **48px** (`L74`) | Dark `--warning` (`3.56:1`), `--danger` (`2.26:1`), `--success` (`2.67:1`) ❌ | **Gerçek:** `toggleTheme()`, linkler.<br/>**Statik:** Arama & hareket listesi. | Fiziksel sayım girişi yok (salt okunur denetim izi ✅). Light `--text-muted` on `.stock-metric-box` `4.34:1` ❌. |

*(Özel kontrol: `shared.css:498-536` içindeki 3 `@media` kuralı yalnızca `.mobile-wrapper`/`.mobile-frame` ve `.desktop-layout`/`.desktop-sidebar` üzerine etki eder; `win-01`, `win-02`, `win-05`, `win-06` içi grid/flex panellerinde responsive medya kırılımı yoktur.)*

---

## 6. Flutter Handoff Kontrolü

[`docs/ui-ux/UX_07_FLUTTER_HANDOFF.md`](./UX_07_FLUTTER_HANDOFF.md) dosyası `AGENTS.md`, `pubspec.yaml` ve `lib/` altındaki mevcut Faz 1.1 koduyla karşılaştırılmıştır:

### 6.1 Uyumlu Noktalar
- **Clean Architecture & Saf Dart Domain (`UX_07:45-51`):** `AGENTS.md:41-50` ile birebir uyumlu.
- **Drift & Dual SQLite İzolasyonu (`UX_07:49-51`):** `lib/core/storage/local_database_service.dart:33-34` ile birebir uyumlu.
- **`pubspec.yaml` Doğruluğu (`UX_07:14-34`):** Mevcut `drift: ^2.20.0`, `flutter_riverpod: ^2.5.1`, `http: ^1.2.2`, `path: ^1.9.0`, `mms_client_storage` kayıtları doğru; `go_router`, özel font ve `google_sign_in` paketlerinin henüz bulunmadığı şeffafça belirtilmiş.
- **Tek Ödeme (`INV-08`), İade Hub LAN ACK Şartı (`L230`), Integer Kuruş & `12.50 TL` (`L196-208`), `48x48 dp` (`L155-157`), B-2 & B-3 Backlog Sınıflandırması (`L228-229`):** Mimari kararlarla uyumlu.

### 6.2 Tespit Edilen Çelişkiler ve Eksikler
1. **Mevcut [`lib/core/theme/app_theme.dart`](../../lib/core/theme/app_theme.dart) ile Renk Çelişkisi:** Kod tabanında halihazırda `AppTheme` (`primaryBlue = #1E40AF`, `statusOnline = #15803D`, `statusOffline = #B91C1C`, `statusWarning = #B45309`, `textMutedLight = #475569`) tanımlıdır. `UX_07:67-106` yeni bir `AppColors` sınıfı (`cardAction = #2563EB`, `cashAction = #047857`, `textMuted = #64748B`, `danger = #DC2626`) önermekte fakat mevcut `AppTheme` ile nasıl uzlaştırılacağını belirtmemektedir. Ayrıca `UX_07`'de Dark mod metin tokenları (`successTextDk`, `warningTextDk`, `dangerTextDk`) yer almamaktadır.
2. **Mevcut [`lib/features/shell/presentation/screens/main_shell_screen.dart`](../../lib/features/shell/presentation/screens/main_shell_screen.dart) Kısayol ve Metin Çelişkisi:**
   - Mevcut Flutter alt çubuğu (`L205-209`): `F1: Yardım`, `F2: Miktar`, `F9: Kart`, `F10: Nakit`, `Esc: İptal`.
   - UX Handoff / `DESIGN_DECISIONS.md`: `F2: Ürün Arama`, `F3: Miktar`, `F9: Seçili Sil`, `F10: Sepeti Temizle`, `F11: Kredi Kartı`, `F12: Nakit`.
   - Ayrıca `main_shell_screen.dart:112, 119` placeholder metinlerinde hâlâ `"stok sayımı"` ve `"KDV dökümü"` ifadeleri bulunmaktadır.
3. **`UX_07:96` Küçük Renk Farkı:** `UX_07:96` `danger = Color(0xFFDC2626)` (Light) ve `dangerDk = Color(0xFFB91C1C)` verirken, `shared.css:33` Light temada da `#B91C1C` kullanmaktadır (ikisi de AA geçer ancak tokenlar birebir aynı değildir).

---

## 7. İş Kararları ve Çelişkiler

Mevcut karar ID'leri değiştirilmeden yapılan karşılaştırmada kritik ID çakışmaları ve durum uyuşmazlıkları saptanmıştır:

| Konu | Kanonik Durum | Tespit Edilen Çelişki (Dosya & Satır) | Önerilen Uzlaştırma (Eski ID Korunarak) |
|---|---|---|---|
| **Alt kuruş yuvarlama (`OD-01` / `OPEN DECISION`)** | `OPEN DECISION` (`AGENTS.md:64`, `BUILD_PLANI:258`, `DESIGN_DECISIONS:128`) | 1) `UX_INDEPENDENT_REVIEW_PACKAGE.md:439` `OD-01`'i "Kasiyer Yetki Rolleri" için kullandı.<br/>2) `packages/mms_client_storage/lib/src/database/client_storage_repository.dart:119` kodunda `((unitPrice * quantity) + 500) ~/ 1000` (Half-Up) hali hazırda yazılmış durumda. | `OD-01` yalnızca **Alt Kuruş Yuvarlama Politikası** olarak korunur; `UX_INDEPENDENT_REVIEW_PACKAGE` tablosuna düzeltme şerhi düşülür. |
| **Parked Carts / Sepeti askıya alma (`OD-02` vs `BR-POS-05`)** | UX & Ürün yönü: Onaylanmamış / `OD-02` (`DESIGN_DECISIONS:133`, `UX_01_FINAL_REVIEW:24-26`) | 1) Kanonik `BUSINESS_RULES_SPEC.md:154` `BR-POS-05`'i `[CONFIRMED]` göstermektedir.<br/>2) `UX_INDEPENDENT_REVIEW_PACKAGE.md:440` `OD-02`'yi "Parçalı Ödeme Modülü" için kullandı. | `OD-02` **Sepeti Askıya Alma** olarak korunur; `BR-POS-05` ID'si silinmeden Proje Sahibi kararıyla `[PROPOSED]` / ertelenmiş statüye çekilmesi önerilir. |
| **Offline bilinmeyen barkod (`OD-03` vs `BR-PROD-05`)** | `OPEN DECISION` (`DESIGN_DECISIONS:138`, `UX_05:79-89`) | 1) `BUSINESS_RULES_SPEC.md:70-76` (`BR-PROD-05 [CONFIRMED]`) zorunlu tam ürün kaydı isterken `UX_05:88` geçici muhtelif kalem önerir.<br/>2) `UX_INDEPENDENT_REVIEW_PACKAGE.md:441` ve `UX_TARGETED_AUDIT_REPORT.md:323` `OD-03`'ü "Mobil Fiziksel Sayım" için kullandı. | `OD-03` **Hub Çevrimdışıyken Bilinmeyen Barkod** olarak korunur; `UX_TARGETED_AUDIT` / `UX_INDEPENDENT_REVIEW` şerhlenir. |
| **Sanal numpad (`OD-04`)** | Onaylanmamış UX önerisi / `OPEN DECISION` (`DESIGN_DECISIONS:143`) | `UX_INDEPENDENT_REVIEW_PACKAGE.md:442` `[UX PROPOSAL]` olarak doğru ama kapsamı "Hızlı Tuşlar" ile birleştirilmiş. | `OD-04` **Windows Masaüstünde Sanal Numpad** olarak korunur. |
| **Fiziksel stok sayımı** | Güncel kapsam: **MVP dışında** (`UX_FINAL_DELIVERY_REPORT:49`) | `BUSINESS_RULES_SPEC.md:252-276` (`BR-STK-04..10 [CONFIRMED]`), `DATA_MODEL.md:329-366`, `win-01..06` sidebar (`Stok & Sayım`), `win-06:87,144`, `UX_02:57,188,213`, `UX_04:143,251`, `UX_05:115`, `UX_06:58,114` ve `main_shell_screen.dart:112` sayım içeriyor. | `BR-STK-04..10` ID'leri korunup MVP dışı (`[OUT_OF_SCOPE]` / `[FUTURE SCOPE]`) şerhi önerilir; UI prototip ve menülerden `"& Sayım"` / `AUDIT` kaldırılır. |
| **`B-2` & `B-3` Güvenlik Backlog'u** | Kesinleşmiş mimari karar, uygulama backlog'u (`AGENTS.md:91-92`, `PROJECT_STATUS:26-27`, `UX_07:228-229`) | 1) `UX_INDEPENDENT_REVIEW_PACKAGE.md:571-572` bunları `OPEN DECISION` yazdı.<br/>2) `UX_TARGETED_AUDIT_REPORT.md:428-439` ve `UX_FINAL_DELIVERY_REPORT.md:137-148` UX audit bulgularına **`B-1.1..B-4.2`** kodlarını vererek `B-1..B-6` / `B-2` / `B-3` ile ID çakışması yarattı.<br/>3) `DT_01_1_AGENT_GOVERNANCE_AUDIT.md:56` B-2 ve B-3 açıklamalarını ters yazmıştı. | `B-2` = Mobil Root CA Pinning, `B-3` = DPAPI/Keystore/Keychain olarak kesinlikle korunur; UX denetim bulguları için `B-*` yerine `UX-AUD-*` öneki kullanılmalıdır. |
| **Ek İkincil ID Sapmaları** | `DESIGN_DECISIONS.md:26-37` (`INV-01..10`) | `UX_04:155` REFUND için `(INV-04)` yazmış (doğrusu `INV-03`). `UX_INDEPENDENT_REVIEW_PACKAGE.md:434-435` `INV-06` ve `INV-07`'yi `DESIGN_DECISIONS.md` ile farklı tanımlamış. | `DESIGN_DECISIONS.md` `INV-01..10` listesi tek referans alınmalıdır. |

---

## 8. `PROJECT_STATUS.md` İçin Uygulanan Güncelleme Özeti

[`docs/PROJECT_STATUS.md`](../PROJECT_STATUS.md) dosyası `v1.1` uzlaştırması kapsamında aşağıdaki gerçek depo kanıtlarına göre güncellenmiştir (yalnızca çalışma dizininde düzenlenmiştir; commit/push yapılmamıştır):
- Tarih `11 Kasım 2026`, son commit `32111b8`, aktif dal `main` (`HEAD == origin/main`).
- `Faz 1.1` (`8676586`), `DT-01.2` (`50343d9`), `DT-01.3` (`6b7898c`) ve `DT-01.4` (`2db892d`, `32111b8`) tamamlanma/push durumları işlendi.
- **UI/UX Tasarım Programı (`docs/ui-ux/`):** "Teknik düzeltmeler ve uzlaştırma tamamlandı — **Proje Sahibi Kabulü Bekleniyor (HENÜZ KABUL EDİLMEDİ; untracked)**".
- **Faz 1.2 (Kasa Satış Ekranı & Sepet Yönetimi):** "Henüz başlamadı (Planlandı; kullanıcı onayı ve `OD-01`/`OD-03`/`OD-04` kararları bekleniyor)".
- `BUSINESS_RULES_SPEC.md` `v1.3` (`BR-POS-05` -> `OD-02`, `BR-STK-04..10` -> `OUT_OF_SCOPE`) ve `REQUIREMENTS.md` `v1.1` referansları eşitlendi.

---

## 9. Faz 1.2 Kapsam Önerisi (Kodlama Yok)

Mevcut [`LocalDatabaseService`](../../lib/core/storage/local_database_service.dart), [`ClientStorageRepository`](../../packages/mms_client_storage/lib/src/database/client_storage_repository.dart) (`createOfflineSale`, `getProductByBarcode`, `CartItemInput`, `SaleTransactionResult`) ve [`MainShellScreen`](../../lib/features/shell/presentation/screens/main_shell_screen.dart) altyapısı üzerine kurulacak **Faz 1.2** kapsam önerisi:

1. **Kasa Satış Ekranı:** `MainShellScreen` içindeki Kasa placeholder'ı yerine Clean Architecture uyumlu POS ekranı (`presentation` → `application` → saf Dart `domain` → `data`).
2. **Barkodla Ürün Ekleme:** USB HID klavye/barkod dinleyicisi (`FocusNode`) + manuel barkod girişi üzerinden `getProductByBarcode()`; pasif ürün (`!isActive`) engeli; aynı barkodda satır miktarını artırma (`BR-POS-02`).
3. **Ürün Arama:** Yerel `LocalProducts` ve `LocalProductBarcodes` üzerinde ad/barkod aramasıyla sepete tek tık ekleme.
4. **Sepet Yönetimi:** Riverpod tabanlı `CartNotifier` / `CartState`; `CartItem` domain entity'sinde ürün adı, birim ve satış fiyatı snapshot'ı (`BR-POS-11`).
5. **Miktar Artırma/Azaltma:** Satır içi `≥ 48×48 dp` `-` / `+` butonları ve klavye ile miktar güncelleme; miktar `0` olduğunda satırın kaldırılması (`BR-POS-02`).
6. **Satır Silme & Temizleme:** Tekil satır silme ve onay diyaloğuyla sepet temizleme.
7. **Satış Toplamı:** Yalnızca `int` kuruş aritmetiği (`double` yasak) ve UI'da `12.50 TL` tabular monospace biçimlendirme.
8. **Tek Ödeme Yöntemi (`INV-08`, `BR-PAY-01`):** Yalnızca **Nakit (`CASH`)** veya **Kredi Kartı (`CARD`)**; karma ödeme yok; kart ödemesinde banka POS terminaline otomatik tutar gönderilmez (`INV-05`).
9. **Nakit Para Üstü Hesaplama (`BR-PAY-02`, `BR-PAY-03`):** Hızlı banknot butonları + manuel kuruş girişi; `changeCents = receivedCents - totalCents`; alınan tutar toplamdan azsa "Satışı Tamamla" butonu kesinlikle kilitli kalır.
10. **Satış Kaydı (`BR-POS-07`):** `LocalDatabaseService.repository.createOfflineSale()` ile tek atomik SQLite transaction içinde `local_sales`, `local_sale_items` (snapshot), `local_stock_movements` (`SATIS`), `local_products` stok düşümü (`allow` eksi stok serbest) ve `client_sync_states.currentClientSeq` artışı.
11. **Offline Outbox Davranışı:** Aynı transaction içinde `outbox_operations` tablosuna `PENDING` kaydı ve `SystemStatusNotifier` / üst barda bekleyen outbox sayacının anlık güncellenmesi; Hub kapalıyken kesintisiz yerel satış. *(Arka plan otomatik sync worker döngüsü ve çakışma çözümü Faz 5 kapsamındadır.)*
12. **İlgili Test Senaryoları (TDD):**
    - *Unit:* Saf Dart sepet toplamı, kuruş ayrıştırma/formatlama, para üstü ve eksik ödeme engeli testleri.
    - *Entegrasyon (Gerçek FFI SQLite):* Atomik `createOfflineSale`, eksi stok (`allow`) satışı, `clientSeq` monotonik artışı, `outbox_operations` `PENDING` yazımı.
    - *Widget:* Kasa ekranı `48×48 dp` kontroller, barkod ekleme, ödeme diyaloğu ve klavye odak/kısayol akışı.

### Faz 1.2'yi Doğrudan Etkileyen vs Sonraki Faza Bırakılacak Kararlar

- **Faz 1.2'yi Doğrudan Etkileyenler (Önceden Netleşmeli):**
  - **`OD-01` (Alt Kuruş Yuvarlama):** Faz 1.2 yalnızca tam adetli (`quantity = 1000` milli-birim katları) ürünlerle sınırlandırılmaz ve gramajlı satış açılırsa, `ClientStorageRepository:119`'daki mevcut Half-Up formülü nedeniyle Proje Sahibi kararı gerekir.
  - **`OD-03` (Offline Bilinmeyen Barkod):** Barkod `client_local.db`'de bulunamadığında Hub offline iken satışın durdurulması mı yoksa geçici kalem/kayıt akışı mı uygulanacağı belirlenmelidir.
  - **`OD-04` (Sanal Numpad):** Masaüstü POS ekranında sanal numpad'in yer alıp almayacağı ve varsayılan görünürlüğü ekran yerleşimini doğrudan etkiler.
  - **Kısayol & Tema Uzlaştırması:** `main_shell_screen.dart:205-209` (`F9/F10`) vs UX (`F11/F12`) kısayol haritası ve `AppTheme` vs `UX_07 AppColors` birleştirilmesi.
- **Sonraki Faza Bırakılabilecekler:**
  - **`OD-02` (Parked Carts):** Temel tek sepet satış döngüsü tamamlandıktan sonraki adıma bırakılabilir (`F4` butonu onay yoksa Faz 1.2'ye konmaz).
  - Satış iptal/kısmi iade (`W-10`/`W-11`), fiziki stok sayımı (`FUTURE SCOPE`), KDV hesaplama (`OUT_OF_SCOPE`), `B-2`/`B-3` cihaz eşleştirme/mobil güvenlik sertleştirmesi.

---

## 10. Kalan Açık Riskler, Teknik Borçlar & Kapatılan Bulgular (v1.1)

*Not: İlk doğrulamadaki (`v1.0`) Dark tema kontrast açıkları, `market_mms_prototype.html` hataları, `test_currency_engine.js` `-0` normalizasyonu, `UX_TARGETED_AUDIT_REPORT.md` sahte/eski çıktıları ve ID çakışmaları, `win-01..06` / UX belgelerindeki sayım/₺/kasiyer kalıntıları ve masaüstü `<= 1024px` / dokunmatik hedef eksikleri **11 Kasım 2026 Final Remediation ile kapatılmıştır** (bkz. Bölüm 12).* Hâlen açık kalan saha, donanım ve karar borçları şunlardır:

1. **Doğrulanmamış Saha/Donanım Alanları:** Fiziksel Android/iOS cihaz, USB HID barkod okuyucu odak davranışı, dokunmatik POS monitörü, gerçek Mağaza Sahibi/kullanıcı TCT süreleri ve otomatik SBOM lisans taraması henüz yapılmamıştır (`PARTIAL`).
2. **Untracked Rapor İsimlendirmesi:** `docs/development/PHASE_1_1_GIT_EXECUTION_REPORT.md` dosyası untracked durumdadır ve dosya adı `docs/phase-1/PHASE_1_1_GIT_EXECUTION_REPORT.md` ile karışırken içeriği DT-01 Git yürütmesini belgelemektedir.
3. **Mevcut Flutter Placeholder Metinleri:** `lib/` dosyalarına dokunma yasağı nedeniyle [`main_shell_screen.dart:112, 119`](../../lib/features/shell/presentation/screens/main_shell_screen.dart#L112-L119) içindeki eski `"stok sayımı"` ve `"Z-Raporu, KDV dökümü"` placeholder metinleri korunmuştur (Faz 1.2+ kapsamında temizlenmek üzere [`UX_07_FLUTTER_HANDOFF.md`](./UX_07_FLUTTER_HANDOFF.md) §4.1'de işaretlenmiştir).

---

## 11. Proje Sahibinden Beklenen Nihai Onaylar

1. **UX Teslimat Kabulü:** Tüm teknik ve karar düzeltmeleri yapılmış `docs/ui-ux/` paketinin kabulüne veya ek revizyona karar verilmesi *(henüz kabul edilmemiştir)*.
2. **Kanonik Şartname & Durum Güncellemesi:** `docs/PROJECT_STATUS.md`, `docs/REQUIREMENTS.md` (`v1.1`) ve `docs/requirements/BUSINESS_RULES_SPEC.md` (`v1.3` — `BR-POS-05` `OD-02`, `BR-STK-04..10` `OUT_OF_SCOPE`) güncellemelerinin ve `docs/development/PHASE_1_1_GIT_EXECUTION_REPORT.md` dosya adının onaylanması.
3. **Faz 1.2 Ön Kararları:** `OD-01` (Faz 1.2'de tam adet sınırı mı Half-Up mı), `OD-03` (offline bilinmeyen barkod), `OD-04` (sanal numpad açık/kapalı varsayılanı) kararlarının verilmesi.
4. **Git İşlem Talimatı:** Kabul sonrasında stage edilecek dosya listesi için açık Git commit/push talimatı verilmesi.
5. **Faz 1.2 Başlatma Onayı:** Faz 1.2 (Kasa Satış Ekranı & Sepet Yönetimi) uygulama ve TDD geliştirme sürecine geçiş izni verilmesi.

---

## 12. Final Remediation & Yeniden Doğrulama Özeti (11 Kasım 2026)

11 Kasım 2026 tarihinde **Final UX Remediation & Decision Reconciliation** kapsamında uygulanan düzeltmeler ve sonrasında fiilen çalıştırılan doğrulamalar:

1. **Dark Tema, Light `--text-muted` & Kontrast (`shared.css`, `verify_wcag.js`, 10 HTML Ekranı):** Light `--text-muted` `#475569`'a çıkarıldı (`AppTheme.textMutedLight` ile eşit; `#F1F5F9` üzerinde `6.92:1 AA`), HTML'deki tüm Dark inline `var(--success/warning/danger)` metinleri `var(--*-text)` token'larına taşındı, Dark `.btn-card:hover` `#1E40AF` ve `win-04` hata kutusu `.change-display-box.is-error` eklendi, `verify_wcag.js` 83 sRGB/RGBA kontrolü ile **83/83 PASS** alındı (yalnızca renk kontrastı kapsamındadır; `.btn:disabled` SC 1.4.3 muaf).
2. **Fiziksel Stok Sayımı Kalıntılarının Kaldırılması:** `win-01..06` menülerindeki `"Stok & Sayım"`, `win-01:223` notu, `win-06:87,144-148` (`AUDIT` / `SAYIM DÜZELTME` / `Raf Sayım Farkı`) ve `UX_01`..`UX_06`, `VISUAL_DESIGN_DELIVERY_REPORT.md` sayım kalıntıları temizlendi; `BUSINESS_RULES_SPEC.md` (`v1.3`) üzerinde `BR-STK-04..10` ID'leri korunarak `[OUT_OF_SCOPE]` statüsüne çekildi.
3. **Eski Prototip (`market_mms_prototype.html`):** Açıkça **`LEGACY / EXPERIMENTAL`** olarak işaretlendi, ana menü (`index.html`) dışında bırakıldı, tanımsız `multiplyQty()` ve satır içi `formatKurus`/`parseToCents` (`Math.round` / sessiz sıfır / binlik doğrulama / `-0`) hataları giderildi.
4. **Dokunmatik ($\ge 48\times 48\text{ CSS px}$) & Responsive ($\le 1024\text{ px}$):** `.btn`, `.nav-link`, `.mob-nav-item`, `.input-text`, `.numpad-btn`, `win-03` `Sepete Ekle`/checkbox etiketi, `win-04` kapatma `×` ve mobil kontroller $\ge 48\times 48\text{ px}$ boyutlandırıldı; `win-01`, `win-02`, `win-04`, `win-05`, `mob-03` ve `index.html` dar ekran kırılımları eklendi (`CSS px != Flutter dp`).
5. **Para Motoru (`shared.js` & `test_currency_engine.js`):** `-0` / `-0.00` normalizasyonu (`totalCents === 0 ? 0 : ...`) ve strict `Object.is` testleri (#38-43) eklenerek **43/43 PASS** alındı.
6. **Kanonik Kararlar, `AppTheme`, `main_shell_screen.dart` & Raporlar:** `BR-POS-05` (`OD-02`), `BR-STK-04..10` (`OUT_OF_SCOPE`), `B-2`/`B-3` (onaylı backlog) ve `UX-AUD-*` ID'leri uzlaştırıldı; `UX_07` mevcut `AppTheme` ve `main_shell_screen.dart` (`F1/F2/F9/F10/Esc`) ile eşitlendi; `docs/PROJECT_STATUS.md` gerçek kanıtlarla güncellendi; `flutter analyze --no-pub` (**No issues found!**) ve `flutter test` (**+31: All tests passed!**) ile uygulama kodunun temizliği teyit edildi.

---

## 13. UX Kabulü & Karar Kapanışı Eki (v1.2 — 11 Kasım 2026)

Bu bölüm, `v1.1` raporu sonrasında **Proje Sahibi tarafından verilen UI/UX kabulü ve `OD-01..OD-04` karar kapanışını** (`docs/development/PHASE_1_2_PREPARATION_REPORT.md` hazırlığıyla birlikte) kaydeder; yukarıdaki Bölüm 1–12 tarihsel doğrulama kaydı korunmuştur:

1. **UI/UX Kabulü:** Proje Sahibi `docs/ui-ux/` UI/UX teslimatını **11 Kasım 2026** tarihinde kabul etmiştir (`KABUL EDİLDİ`). Teslimat dosyaları Git'te açık commit onayı verilene kadar untracked olarak korunmaktadır; gerçek cihaz ve saha testleri (`T-09`, `T-11` partial) Faz 7 Pilot kapsamındadır.
2. **Kesinleşen Proje Kararları (ID'ler Korundu):**
   - **`OD-01` (Alt Kuruş Yuvarlama — ONAYLANDI):** **Half-Up yuvarlama** kullanılır; floating-point aritmetik yasaktır, hesaplama integer/decimal güvenli yöntemle yürütülür, `12.50 TL` gösterimi ve dahili integer kuruş standardı korunur.
   - **`OD-02` (Parked Carts / `BR-POS-05` — MVP DIŞI / `OUT_OF_SCOPE`):** MVP kapsamı dışındadır; gelecek sürümlerde değerlendirilebilir; MVP ekranlarında sunulmaz.
   - **`OD-03` (Offline Bilinmeyen Barkod / `BR-PROD-05`, `BR-SYNC-04` — ONAYLANDI):** Yerel DB'de bulunmayan ürün offline oluşturulamaz ve bilinmeyen barkod offline satış sepetine eklenemez; ürün oluşturma Master Hub bağlantısı gerektirir; yerel DB'de bulunan ürünler offline satılabilir.
   - **`OD-04` (Sanal Numpad — ONAYLANDI):** Opsiyoneldir ve **varsayılan olarak kapalıdır**; fiziksel klavye ve USB HID barkod okuyucu temel kullanım yöntemidir.
3. **Faz 1.2 Hazırlık Teslimatı:** Faz 1.2 kapsamı bu kararlara göre yeniden kontrol edilerek [`docs/development/PHASE_1_2_PREPARATION_REPORT.md`](../development/PHASE_1_2_PREPARATION_REPORT.md) hazırlanmıştır; kodlama (`lib/`, `test/`, `pubspec.yaml`, backend, DB) ve Git işlemleri hâlâ Proje Sahibi onayı beklemektedir.

