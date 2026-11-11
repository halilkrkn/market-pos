# VISUAL_DESIGN_DELIVERY_REPORT.md
# MARKET MMS UI/UX GÖRSEL TASARIM TESLİMAT RAPORU (v1.4)

**Rapor Tarihi:** 11 Kasım 2026  
**Rapor Versiyonu:** v1.4 (Proje Sahibi Kabulü & `OD-01..OD-04` Kapanış Sürümü)  
**Hazırlayan:** Antigravity / Gemini  
**Konum:** `docs/ui-ux/visual-designs/`  
**Danışman Rolü:** ChatGPT  
**Karar ve Onay Mercii:** Proje Sahibi  
**Durum:** PROJE SAHİBİ TARAFINDAN KABUL EDİLDİ (11 Kasım 2026 — `docs/ui-ux/` Git'te Commit Bekliyor)  
**Bağlayıcı Temel:** [`AGENTS.md`](../../../AGENTS.md), [`GEMINI.md`](../../../GEMINI.md), [`UX_03_DESIGN_SYSTEM.md`](../UX_03_DESIGN_SYSTEM.md), [`UX_FINAL_DELIVERY_REPORT.md`](../UX_FINAL_DELIVERY_REPORT.md)

---

## 1. Yönetici Özeti (Executive Summary)

Bu rapor, **MARKET MANAGEMENT SYSTEM (MARKET MMS)** platformunun görsel tasarım teslimatında `UX_TARGETED_AUDIT_REPORT.md` ve `UX_FINAL_VERIFICATION_AND_RECONCILIATION_REPORT.md` denetimleri sonucunda tespit edilen tüm gerçek teknik, kontrast, ergonomi ve kapsam açıklarının giderildiği **v1.3 revizyonunu** belgeler.

1. **Kuruş Aritmetiği ve Negatif Sıfır Düzeltmesi (`shared.js` & `test_currency_engine.js`):**
   - Binlik ayırıcı doğrulaması: Yalnızca geçerli 3'lü basamak blokları (`1,250.00` ve `1.250,00`) kabul edilmekte; `1,25.00`, `1,,250.00`, `12,34,567.89` reddedilmektedir.
   - Büyük/küçük harf duyarsız TL eki (`12 TL`, `12TL`, `12 Tl`, `12 tL`) temizlenmektedir.
   - `BigInt` sınır kontrolü (`Number.MAX_SAFE_INTEGER`) korunmaktadır.
   - `parseToCents("-0", true)` ve `parseToCents("-0.00", true)` çağrılarının JavaScript `-0` döndürme hatası `totalCents === 0 ? 0 : ...` ile düzeltildi; `Object.is(..., 0)` doğrulaması eklendi.
   - Test süiti 43 teste genişletildi ve **43/43 PASS** olarak fiilen çalıştırılarak doğrulandı.
2. **Renk Kontrastı ve CSS Düzeltmeleri (`shared.css`, `verify_wcag.js` & 10 HTML Ekranı):**
   - Light `--text-muted` token'ı `#64748B`'den **`#475569`** değerine çekilerek hem [`AppTheme.textMutedLight`](../../../lib/core/theme/app_theme.dart#L14) ile eşitlendi hem de `#F1F5F9` (`--bg-surface-subtle`) üzerindeki `4.34:1` kontrast hatası **6.92:1 AA** seviyesine yükseltildi.
   - `win-01`, `win-02`, `win-03`, `win-04`, `win-05`, `win-06`, `mob-01` ve `mob-04` dosyalarında Dark temada `1.91:1–3.56:1` FAIL veren inline `var(--success)` / `var(--warning)` / `var(--danger)` metinleri `var(--success-text)` / `var(--warning-text)` / `var(--danger-text)` token'larına taşındı.
   - `shared.css` üzerine Dark `.btn-card:hover` (`#1E40AF`), `.btn-primary:hover`, `win-04` hata durumu kutusu (`.change-display-box.is-error` / `--danger-bg` + `--danger-text`) ve bilgi kutusu eklendi.
   - `verify_wcag.js` gerçek RGBA alpha blend yüzeylerini (`darkWarningBgApp`, `darkDangerBg`, `mob-02` `#020617` üzeri `%70` beyaz) ölçmek üzere **83 renk kontrastı kontrolüne** genişletildi (**83/83 PASS**). **Kapsam Notu:** Bu doğrulama yalnızca SC 1.4.3 / 1.4.11 renk kontrastını kapsar (tam WCAG uygunluğu değildir); `.btn:disabled` öğeleri WCAG SC 1.4.3 muafiyeti nedeniyle kapsam dışıdır ve PASS sayılmamıştır.
3. **Fiziksel Stok Sayımı Kalıntılarının Kaldırılması (`win-01`..`win-06`):**
   - MVP dışı fiziksel sayım (`BR-STK-04..10`) nedeniyle tüm masaüstü sol menülerindeki `"Stok & Sayım"` başlığı `"Stok & Hareketler"`, `win-01:223` notu toptancı/manuel hareket notuna, `win-06` içindeki `Sayım Düzeltmesi (AUDIT)` ve `SAYIM DÜZELTME / Raf Sayım Farkı` satırları ise MVP geçerli `MANUEL_DUZELTME` / `FİRE / KAYIP` hareketlerine dönüştürüldü.
4. **Dokunmatik ($\ge 48\times 48\text{ CSS px}$), Responsive ($\le 1024\text{ px}$) & Kısayol Uzlaştırması:**
   - `.btn`, `.nav-link`, `.mob-nav-item`, `.input-text`, `.numpad-btn`, `win-03` `Sepete Ekle`/checkbox etiketi, `win-04` kapatma `×` ve `mob-01` `.mob-action-btn` kontrolleri en az $48\times 48\text{ CSS px}$ standardına getirildi (`CSS px != Flutter dp`).
   - `win-01` (`.kpi-grid`, `.dashboard-grid`), `win-02` (`.pos-canvas`, `.quick-keys-grid`, `.checkout-buttons-row`, semantik `<button>` hızlı tuşlar), `win-04` (`max-height: calc(100vh - 32px)`, `@media 540px`, çalışan Nakit/Kart seçimi), `win-05` (`.sales-split` & filtre wrap) ve `win-06` (filtre wrap) için `<= 1024px` ve dar ekran kırılımları eklendi.
   - `win-02` ve `win-04` F-tuşları mevcut [`main_shell_screen.dart`](../../../lib/features/shell/presentation/screens/main_shell_screen.dart#L205-L209) (`F1 Yardım`, `F2 Miktar`, `F9 Kredi Kartı`, `F10 Nakit`, `Esc İptal`) ile hizalandı; `B-2`/`B-3` onaylı backlog maddeleri olarak korundu.

---

## 2. Üretilen Görsel Ekranlar Envanteri (10 Öncelikli Ekran)

Tüm dosyalar [`docs/ui-ux/visual-designs/`](file:///c:/Users/halil/Github/market-pos/docs/ui-ux/visual-designs/) klasöründe konumlandırılmıştır:

| No | Dosya Adı | Platform | İlgili Blueprint | Açıklama ve Kapsam |
|:---:|---|:---:|:---:|---|
| **0** | [`index.html`](file:///c:/Users/halil/Github/market-pos/docs/ui-ux/visual-designs/index.html) | Hub / Vitrin | — | Tüm ekranlara doğrudan erişim sağlayan ana vitrin, tema değiştirme konsolu ve mimari değişmezler paneli. |
| **1** | [`win-01-dashboard.html`](file:///c:/Users/halil/Github/market-pos/docs/ui-ux/visual-designs/win-01-dashboard.html) | Windows | `W-05` | 4'lü KPI kartı (Toplam: `8,450.00 TL`, Nakit: `5,120.00 TL`, Kart: `3,330.00 TL`), son satışlar tablosu, eksiye düşen ürünler paneli (`INV-04`). |
| **2** | [`win-02-pos.html`](file:///c:/Users/halil/Github/market-pos/docs/ui-ux/visual-designs/win-02-pos.html) | Windows | `W-01` | %60 Sepet tablosu, %40 hızlı tuşlar (`<button>`), opsiyonel sanal numpad önizlemesi (`OD-04`: varsayılan kapalı, 48px), dev genel toplam (`306.80 TL`), `main_shell_screen.dart` uyumlu F10 Nakit ve F9 Kart butonları (`INV-08`). |
| **3** | [`win-03-product-search.html`](file:///c:/Users/halil/Github/market-pos/docs/ui-ux/visual-designs/win-03-product-search.html) | Windows | `W-06` | Anlık ürün/barkod arama, kategori filtresi, son bilinen fiyat (`INV-10`), eksi stok uyarıları, $\ge 48\text{ px}$ sepete ekleme/checkbox kontrolleri. |
| **4** | [`win-04-payment-modal.html`](file:///c:/Users/halil/Github/market-pos/docs/ui-ux/visual-designs/win-04-payment-modal.html) | Windows | `W-02` | Hızlı Ödeme modalı (`max-height: calc(100vh - 32px)`, Flutter hedefi 600×480 dp), etkileşimli Nakit (F10) / Kart (F9) geçişi, banknotlar (48px), hata state'i (`.is-error`), `93.20 TL` para üstü kutusu. |
| **5** | [`win-05-sales-history.html`](file:///c:/Users/halil/Github/market-pos/docs/ui-ux/visual-designs/win-05-sales-history.html) | Windows | `W-10` | Tarih filtreli fiş tablosu, `<= 1024px` responsive ayrım, snapshot satış fiyatları (`INV-01`, `INV-03`) ve Hub LAN (`BR-POS-09`) uyarılı REFUND iade simülasyonu. |
| **6** | [`win-06-stock-management.html`](file:///c:/Users/halil/Github/market-pos/docs/ui-ux/visual-designs/win-06-stock-management.html) | Windows | `W-09` | Stok seviyeleri, eksi stok politikası (`allow` `INV-04`), toptancı mal kabul ve manuel/fire hareket günlüğü *(fiziksel sayım / AUDIT kalıntısı tamamen kaldırıldı)*. |
| **7** | [`mob-01-dashboard.html`](file:///c:/Users/halil/Github/market-pos/docs/ui-ux/visual-designs/mob-01-dashboard.html) | Mobil | `M-01` | Mağaza sahibi günlük özet, ciro kartı (`8,450.00 TL`), yerel Wi-Fi Hub online rozeti, bekleyen outbox kuyruk göstergesi, hızlı reyon butonları. |
| **8** | [`mob-02-barcode-scan.html`](file:///c:/Users/halil/Github/market-pos/docs/ui-ux/visual-designs/mob-02-barcode-scan.html) | Mobil | `M-02` | Kamera vizör simülasyonu, lazer tarama çizgisi, fener kontrolü, taranan ürün için anında açılan alt çekmece kartı (`185.00 TL`), stok geçmişi butonu. |
| **9** | [`mob-03-cart-checkout.html`](file:///c:/Users/halil/Github/market-pos/docs/ui-ux/visual-designs/mob-03-cart-checkout.html) | Mobil | `M-03` | Dikey dokunmatik sepet listesi, adet +/- butonları, alt yapışkan ödeme çubuğu (`244.90 TL`), tek dokunuşla Nakit/Kart satış tamamlama (`INV-08`). |
| **10** | [`mob-04-stock-view.html`](file:///c:/Users/halil/Github/market-pos/docs/ui-ux/visual-designs/mob-04-stock-view.html) | Mobil | `M-04` | MVP Uyumlu Reyon Stok Görüntüleyici: Barkod arama, anlık stok düzeyi (`-14 Adet`), son bilinen fiyat (`12.50 TL` `INV-10`), `allow` eksi stok rozeti (`INV-04`) ve detaylı hareket geçmişi (audit trail). Fiziksel sayım kaldırılmıştır. |

---

## 3. Tema ve Tasarım Sistemi Uyumu (Theme & Design System)

Tüm ekranlar [`shared.css`](file:///c:/Users/halil/Github/market-pos/docs/ui-ux/visual-designs/shared.css) ve [`shared.js`](file:///c:/Users/halil/Github/market-pos/docs/ui-ux/visual-designs/shared.js) üzerinden ortak tasarım token'larını kullanır:

1. **Çift Tema Desteği (Light & Dark):**
   - Her ekranda tek tıkla çalışan tema geçiş butonu mevcuttur.
   - Seçilen tema `localStorage` (`mms_theme`) üzerinden kalıcı olarak hatırlanır.
2. **Modern SaaS Tasarım Dili:**
   - Slate/Zinc paleti, $1\text{px}$ net kenarlıklar (`var(--border-subtle)`), gereksiz gradyan, gölge veya dekoratif süslemelerden arındırılmış temiz kartlar.
   - $4\text{dp}$ temel birim / $8\text{dp}$ artış ölçeği (`4, 8, 12, 16, 20, 24, 32\text{ dp}`) — CSS ve tasarım dokümanları uyumlaştırılmıştır.
3. **Monospace Tabular Tipografi:**
   - Fiş tutarları, birim fiyatlar, barkodlar ve adet sayıları `.mono` sınıfı ile tabular monospace (`tabular-nums`) olarak sağa dayalı hizalanmıştır (`INV-01`).
4. **Navigasyon, Metin ve Odak Kontrastı İyileştirmeleri (`v1.3`):**
   - Light temada `--text-muted` token'ı `#475569` olarak güncellenerek hem `#FFFFFF` (`7.58:1 AAA`) hem `#F1F5F9` (`6.92:1 AA`) yüzeylerinde geçiş sağlandı (`AppTheme.textMutedLight` ile eşit).
   - Dark temada aktif navigasyon metni (`#60A5FA`) ve inline durum metinleri (`--success-text: #34D399`, `--warning-text: #FBBF24`, `--danger-text: #F87171`) tam uyumlu hale getirildi; Dark `.btn-card:hover` `#1E40AF` (`8.72:1 AAA`) olarak ayrıştırıldı.
   - Form girdi sınırları (`--border-strong: #64748B`) WCAG Non-text ($\ge 3:1$) kriterini Light (**4.76:1**) ve Dark (**3.07:1**) temada karşılamaktadır.

---

## 4. Kapsamlı Renk Kontrastı Doğrulama Matrisi (83 Kontrol — `verify_wcag.js`)

> [!IMPORTANT]
> Bu bölüm yalnızca `verify_wcag.js` betiği üzerinden IEC 61966-2-1 (`0.04045` sRGB eşiği) formülü ve gerçek RGBA alpha blending ile ölçülen **renk kontrastlarını** raporlar; genel WCAG 2.1 uygunluğu beyanı değildir. `.btn:disabled` (`opacity: 0.45`) öğeleri WCAG 2.1 SC 1.4.3 Inactive istisnası kapsamında dışarıda tutulmuştur.

Çalıştırma komutu: `node docs/ui-ux/visual-designs/verify_wcag.js` -> **83/83 PASS (0 FAIL)** (tam çıktı listesi `UX_TARGETED_AUDIT_REPORT.md` §8.2 içindedir). Özet kritik çiftler:

| Tema | Bileşen / Kullanım Alanı | Ön Plan | Arka Plan | Kontrast | Kriter | Değerlendirme |
|---|---|---|---|:---:|:---:|:---:|
| **Light** | Gövde Metni (`.text-main`) | `#0F172A` | `#FFFFFF` | **17.85:1** | ≥ 4.5:1 | ✅ **PASS AAA** |
| **Light** | İkincil Metin (`--text-muted` / Surface & Subtle) | `#475569` | `#FFFFFF` / `#F1F5F9` | **7.58:1** / **6.92:1** | ≥ 4.5:1 | ✅ **PASS AAA / AA** |
| **Light** | Aktif Menü / Sekme | `#1E40AF` | `#F1F5F9` / `#FFFFFF` | **7.96:1** / **8.72:1** | ≥ 4.5:1 | ✅ **PASS AAA** |
| **Light** | Nakit / Kart / İptal Butonları | `#FFFFFF` | `#047857` / `#2563EB` / `#B91C1C` | **5.48** / **5.17** / **6.47:1** | ≥ 4.5:1 | ✅ **PASS AA** |
| **Light** | Para Üstü Normal / Hata Kutusu | `#166534` / `#991B1B` | `#DCFCE7` / `#FEE2E2` | **6.49:1** / **6.80:1** | ≥ 4.5:1 | ✅ **PASS AA** |
| **Light** | Input Border / Error / Focus Ring | `#64748B` / `#B91C1C` / `#2563EB` | `#FFFFFF` | **4.76** / **6.47** / **5.17:1** | ≥ 3.0:1 | ✅ **PASS AA** |
| **Dark** | Gövde / İkincil Metin (Surface & Subtle) | `#F8FAFC` / `#94A3B8` | `#1E293B` / `#0F172A` | **13.98** / **5.71–6.96:1** | ≥ 4.5:1 | ✅ **PASS AAA / AA** |
| **Dark** | Kart Butonu / Kart Hover | `#FFFFFF` | `#1D4ED8` / `#1E40AF` | **6.70:1** / **8.72:1** | ≥ 4.5:1 | ✅ **PASS AA / AAA** |
| **Dark** | Inline `--success/warning/danger-text` | `#34D399` / `#FBBF24` / `#F87171` | `#1E293B` | **7.61** / **8.76** / **5.29:1** | ≥ 4.5:1 | ✅ **PASS AAA / AA** |
| **Dark** | Para Üstü Normal / Hata (RGBA Blend) | `#34D399` / `#F87171` | `rgb(25,57,65)` / `rgb(61,38,53)` | **6.41:1** / **4.97:1** | ≥ 4.5:1 | ✅ **PASS AA** |
| **Dark** | `win-06` Uyarı Kartı (App Blend) | `#FBBF24` | `rgb(43,27,19)` | **9.91:1** | ≥ 4.5:1 | ✅ **PASS AAA** |
| **Mob-02**| Kamera Vizör İpucu (70% White) | `rgb(179,180,185)` | `#020617` | **9.75:1** | ≥ 4.5:1 | ✅ **PASS AAA** |

---

## 5. JavaScript Kuruş Para Motoru ve Test Sonuçları (`shared.js`)

`test_currency_engine.js` süiti `node docs/ui-ux/visual-designs/test_currency_engine.js` komutu ile fiilen çalıştırılmıştır (**43/43 PASS**). Tam çıktı:

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
  [PASS] Test #38: parseToCents("-0") varsayılanda ret (allowNegative=false)
  [PASS] Test #39: parseToCents("-0.00") varsayılanda ret (allowNegative=false)
  [PASS] Test #40: parseToCents("-0", true) +0 döndürmeli (-0 değil, Object.is kontrolü)
  [PASS] Test #41: parseToCents("-0.00", true) +0 döndürmeli (-0 değil, Object.is kontrolü)
  [PASS] Test #42: parseToCents("-0,00 TL", true) +0 döndürmeli (-0 değil, Object.is kontrolü)
  [PASS] Test #43: formatKurus(-0) ve formatCentsToInput(-0) pozitif sıfır metni döndürmeli

================================================================
 TEST RAPORU: Toplam: 43 | Başarılı: 43 | Başarısız: 0
================================================================
```

---

## 6. Ürün Kararları ve Mimari Değişmezler Doğrulaması

Tüm görsel ekranlarda projenin bağlayıcı anayasası (`AGENTS.md`) ve mimari kuralları tavizsiz uygulanmıştır:

1. **Kuruş Tamsayı Standardı (`INV-01`) ve Onaylı Para Formatı:**
   - Arayüzde hiçbir zaman kayan noktalı sayı (`float/double`) kullanılmamıştır.
   - Tüm tutarlar görsel olarak onaylanan `12.50 TL` formatında (nokta ondalık ayırıcı, iki hane, virgülsüz kuruş, `TL` soneki) gösterilmektedir. Simge (`₺`) kesinlikle yer almaz.
   - `shared.js` içindeki `parseToCents(textInput, allowNegative)` fonksiyonu, `parseFloat` veya `Math.round(val * 100)` yerine **katı string/integer ayrıştırma** uygular. Çoklu ayırıcıları, 2 haneden fazla kuruşları, boş veya harf içeren girdileri reddeder; `{ valid: true, cents: integer }` veya `{ valid: false, error: string }` döner.
   - `formatKurus(cents)` fonksiyonu tamsayı bölme (`Math.floor(absCents / 100)`) ve kalan (`absCents % 100`) ile çalışarak `1,250.00 TL` formatı üretir.
   - `formatCentsToInput(cents)` fonksiyonu ise `toFixed()` kullanmaksızın doğrudan tamsayılardan input formatı (`12.50`) türetir.
   - Node.js test ortamında çalıştırılan **43/43** birim test senaryosu (`-0`/`-0.00` `Object.is` dahil) tam başarıyla geçmiştir.
2. **Ayrık Veritabanı Modeli (`INV-02`):** Windows masaüstü arayüzünde sunucu veritabanına (`market_master.db`) doğrudan bağlantı gösterilmemiş; loopback API ve Hub durumu (`● HUB ONLINE`) rozetle izlenmiştir.
3. **Satış Dokunulmazlığı (`INV-03`):** Satış geçmişi ekranında (`win-05`) satış satırını silme aksiyonu kaldırılmış; yalnızca ters yönde `REFUND` ve stok iade hareketi oluşturan mekanizma modellenmiştir.
4. **Eksi Stok Serbestliği (`INV-04`):** Dashboard (`win-01`), ürün listesi (`win-03`), stok ekranı (`win-06`) ve mobil stok sorgulamada (`mob-04`) eksiye düşen ürünler engellenmemiş; `allow` politikası uyarınca sarı/kehribar uyarı rozetleriyle gösterilmiştir.
5. **Donanımsal Banka POS Sınırı (`INV-05`):** Kredi kartı ödemesinde banka terminaline otomatik tutar gönderme yer almamış; tutarın terminale elle girildiği uyarısı eklenmiştir.
6. **Nakit ve Kart Yalnızca (`INV-08`):** Parçalı ödeme (split payment) tüm ekranlardan ve prototipten tamamen çıkarılmıştır.
7. **Tek Sahip Hesabı (`INV-09`):** Başlık çubuğunda ve kullanıcı profilinde kasiyer rolü kaldırılmış; "Kullanıcı: Mağaza Sahibi (Pilot)" tek hesap modeli uygulanmıştır.
8. **Son Bilinen Fiyat (`INV-10`):** Offline ürün listelemesinde yerel veritabanındaki son bilinen fiyatların geçerli olduğu not edilmiştir.
9. **Stok Sayımı / Audit Sınırı (Post-MVP):** Fiziksel stok sayımı, sayım farkı kaydı ve outbox ile sayım eşitleme özellikleri MVP kapsamı dışına (`[OUT_OF_SCOPE]` / `[FUTURE SCOPE]`) alınmış; `mob-04` ekranı salt stok düzeyi, son fiyat ve hareket geçmişi sorgulama ekranına indirgenmiştir.
10. **Kesinleşen Ürün Kararları (`OD-01`..`OD-04`, 11 Kasım 2026):** Alt kuruş yuvarlama Half-Up (`OD-01`), Parked Carts MVP dışı (`OD-02` — `OUT_OF_SCOPE`), offline bilinmeyen barkod eklenemez/oluşturulamaz (`OD-03`), sanal numpad opsiyonel ve varsayılan kapalı (`OD-04`) olarak Proje Sahibi tarafından onaylanmıştır (`win-02` vitrinde yalnızca opsiyonel yerleşim örneği gösterir; KDV alanları MVP dışıdır).

---

## 6. Gerçek ve Simüle Edilen Fonksiyonların Ayrımı

- **Gerçek Çalışan Özellikler:**
  - Light / Dark tema geçişi ve tarayıcı belleğinde kalıcı saklanması (`localStorage`).
  - Ödeme yönteminin Nakit/Kredi Kartı geçişi (`win-04`) ve dinamik para üstü / hata durumu (`.is-error`, katı tamsayı kuruş ayrıştırma ve formatlama motoru ile).
  - Ekranlar arası tam navigasyon (Sidebar menüsü, mobil alt sekmeler ve vitrin sayfası).
  - Hızlı banknot butonlarıyla (`310 TL`, `400 TL`, `1,000 TL` vb.) anlık kuruş girdisi doldurma.
  - Reyon barkodlu stok seviyesi, son fiyat ve hareket geçmişi (audit trail) inceleme.
- **Simüle Edilen (Tasarım Demosu) Özellikler:**
  - Gerçek SQLite/Drift veritabanı okuma/yazma işlemleri (veriler bellekte mock olarak tutulmaktadır).
  - Windows Arka Plan Servisi ve Shelf HTTPS API bağlantısı.
  - Mobil kamera donanım erişimi (vizör CSS/JS animasyonu ile simüle edilmektedir).
  - Outbox kuyruk senkronizasyon worker'ı.

---

## 7. Açık Kalan Konular ve Gelecek Adımlar

1. **Flutter Kod Devri:** Bu görsel HTML tasarımları, `lib/` altındaki Flutter widget implementasyonu için piksel referansı teşkil etmektedir. Flutter kodlamasına başlama kararı proje sahibine aittir.
2. **Kullanıcı Testleri:** Ekranların fiziki dokunmatik monitör ve barkod tabancasıyla pilot mağazada test edilmesi tavsiye edilir.

---

## 8. Sonuç

Üretilen **10 öncelikli görsel ekran tasarımı**, `shared.css`, `shared.js` ve `index.html` vitrini, MARKET MMS UI/UX gereksinimlerini eksiksiz karşılayacak şekilde hazırlanmış olup, **Proje Sahibi'nin nihai değerlendirme ve kabul incelemesine saygıyla sunulur.**
