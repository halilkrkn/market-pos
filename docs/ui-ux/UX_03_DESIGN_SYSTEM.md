# UX_03_DESIGN_SYSTEM.md — MARKET MMS TASARIM SİSTEMİ VE BİLEŞEN KÜTÜPHANESİ
# Market Management System (Market MMS) — Design System, Design Tokens & Core Components

- **Doküman Versiyonu:** v1.2 (11 Kasım 2026 Uzlaştırması)
- **Revizyon Notu:** v1.1 kontrast analizini temel alır. v1.2 uzlaştırmasıyla Light ikincil metin token'ı `#64748B` -> **`#475569`** olarak yükseltildi (`#F1F5F9` üzerinde `4.34:1 FAIL` yerine **`6.92:1 AA`** ve mevcut `AppTheme.textMutedLight` ile eşitlik), Dark inline durum metinleri (`--success-text`, `--warning-text`, `--danger-text`) ve `lib/core/theme/app_theme.dart` (`AppTheme`) ile hizalama eklendi.
- **Araç Yokluğu Notu:** Figma veya Google Stitch bu ortamda bağlı değildir. Tasarım sistemi ASCII wireframe'ler, Mermaid diyagramları ve `AppTheme` uyumlu token şartnameleri olarak üretilmiştir.
- **Bağlayıcı Temel:** [`AGENTS.md`](../../AGENTS.md), [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](../../MARKET_POS_AI_STUDIO_BUILD_PLANI.md) (v1.4), [`DESIGN_DECISIONS.md`](./DESIGN_DECISIONS.md)

---

## 1. Tasarım Sistemi Statüsü

Aşağıdaki tasarım sistemi bileşenlerinin tamamı **tasarım önerisi** (`[UX PROPOSAL]`) statüsündedir. Hiçbiri proje sahibi tarafından henüz nihai onay almamıştır.

---

## 2. Renk Sistemi ve Doğrulanmış WCAG Kontrast Oranları

### 2.1. Kontrast Hesaplama Metodolojisi

Tüm kontrast oranları **W3C WCAG 2.1 Relative Luminance** formülüyle hesaplanmıştır:

$$L = 0.2126 \cdot R_{lin} + 0.7152 \cdot G_{lin} + 0.0722 \cdot B_{lin}$$

sRGB doğrusallaştırması:

$$c_{lin} = \begin{cases} c/12.92 & c \le 0.04045 \\ \left(\frac{c + 0.055}{1.055}\right)^{2.4} & c > 0.04045 \end{cases}$$

Kontrast oranı:

$$\text{Oran} = \frac{L_{aydınlık} + 0.05}{L_{karanlık} + 0.05}$$

**WCAG 2.1 Kriterleri:**
- Normal metin (< 18pt / < 14pt kalın): **4.5:1 (AA)**, 7.0:1 (AAA)
- Büyük metin (≥ 18pt / ≥ 14pt kalın): **3.0:1 (AA)**, 4.5:1 (AAA)
- UI bileşen sınırı / grafik: **3.0:1 (AA)**

> [!IMPORTANT]
> **48 dp dokunmatik hedef boyutu bir WCAG erişilebilirlik zorunluluğu değildir.** Bu değer MARKET MMS için önerilen kasa ergonomi standardıdır (`[UX PROPOSAL]`).

---

### 2.2. Hesaplanmış Kontrast Oranları — Tam Tablo

#### Light Tema Token'ları

| Token / Kullanım Alanı | Ön Plan (Metin/İkon) | Arka Plan | Hesaplanan Oran | Normal Metin | Büyük Metin | UI Sınırı |
|---|---|---|---|---|---|---|
| **Birincil Metin** `color-text-main` | `#0F172A` Slate 900 | `#FFFFFF` Beyaz | **17.85:1** | ✅ AAA | ✅ AAA | ✅ |
| **Birincil Metin on Bg** | `#0F172A` Slate 900 | `#F8FAFC` Slate 50 | **17.06:1** | ✅ AAA | ✅ AAA | ✅ |
| **İkincil Metin** `color-text-muted` | `#64748B` Slate 500 | `#FFFFFF` Beyaz | **4.76:1** | ✅ AA | ✅ AAA | ✅ |
| **Surface Dark Metin** | `#FFFFFF` | `#1E293B` Slate 800 | **14.63:1** | ✅ AAA | ✅ AAA | ✅ |
| **Muted Dark** `color-text-muted` dark | `#94A3B8` Slate 400 | `#090D16` Charcoal | **7.58:1** | ✅ AAA | ✅ AAA | ✅ |
| **Muted Dark on Surface** | `#94A3B8` Slate 400 | `#1E293B` Slate 800 | **5.71:1** | ✅ AA | ✅ AAA | ✅ |
| **Nakit Butonu Light** ⚠️ | `#FFFFFF` | `#059669` Emerald 600 | **3.77:1** | ❌ FAIL | ✅ AA large | ✅ UI |
| **Nakit Butonu Light (Hover)** | `#FFFFFF` | `#047857` Emerald 700 | **5.48:1** | ✅ AA | ✅ AAA | ✅ |
| **Nakit Butonu Dark** ⚠️ | `#FFFFFF` | `#10B981` Emerald 500 | **2.54:1** | ❌ FAIL | ❌ FAIL | ❌ |
| **Kart Butonu Light** ✅ | `#FFFFFF` | `#2563EB` Blue 600 | **5.17:1** | ✅ AA | ✅ AAA | ✅ |
| **Kart Butonu Light (Hover)** | `#FFFFFF` | `#1D4ED8` Blue 700 | **6.70:1** | ✅ AA | ✅ AAA | ✅ |
| **Kart Butonu Dark** ⚠️ | `#FFFFFF` | `#3B82F6` Blue 500 | **3.68:1** | ❌ FAIL | ✅ AA large | ✅ UI |
| **Uyarı Metni (Warning)** ⚠️ | `#FFFFFF` | `#D97706` Amber 600 | **3.19:1** | ❌ FAIL | ✅ AA large | ✅ UI |
| **Uyarı Hover** | `#FFFFFF` | `#B45309` Amber 700 | **5.02:1** | ✅ AA | ✅ AAA | ✅ |
| **Tehlike / İptal Light** ✅ | `#FFFFFF` | `#DC2626` Red 600 | **4.83:1** | ✅ AA | ✅ AAA | ✅ |
| **Tehlike / İptal Hover** | `#FFFFFF` | `#B91C1C` Red 700 | **6.47:1** | ✅ AA | ✅ AAA | ✅ |
| **Tehlike Dark** ⚠️ | `#FFFFFF` | `#EF4444` Red 500 | **3.76:1** | ❌ FAIL | ✅ AA large | ✅ UI |
| **Para Üstü Kutusu** ✅ | `#166534` Dark Green | `#DCFCE7` Light Green | **6.49:1** | ✅ AA | ✅ AAA | ✅ |
| **Offline Rozet** ✅ | `#92400E` Dark Amber | `#FEF3C7` Light Amber | **6.37:1** | ✅ AA | ✅ AAA | ✅ |
| **Outbox Rozet** ✅ | `#1E3A8A` Blue 900 | `#DBEAFE` Blue 100 | **8.49:1** | ✅ AAA | ✅ AAA | ✅ |

#### ⚠️ Kritik Kontrast Sorunları ve Düzeltme Önerileri

| Sorunlu Kombinasyon | Mevcut Oran | Sorun | Önerilen Çözüm |
|---|---|---|---|
| Beyaz üzerine Emerald 600 `#059669` (Nakit buton) | 3.77:1 | Normal metin AA FAIL | **Büyük/Kalın metin kullan (≥18pt / ≥14pt Bold) VEYA hover rengi `#047857` (5.48:1) kullan** |
| Beyaz üzerine Emerald 500 `#10B981` (Dark nakit) | 2.54:1 | Her kategoride FAIL | **Dark temada `#065F46` (8.6:1) veya `#047857` (5.48:1) kullan** |
| Beyaz üzerine Blue 500 `#3B82F6` (Dark kart) | 3.68:1 | Normal metin AA FAIL | **Dark temada `#1D4ED8` Blue 700 (6.70:1) kullan** |
| Beyaz üzerine Amber 600 `#D97706` (Uyarı) | 3.19:1 | Normal metin AA FAIL | **`#B45309` Amber 700 (5.02:1) kullan VEYA koyu zemin üzerine amber metin** |
| Beyaz üzerine Red 500 `#EF4444` (Dark tehlike) | 3.76:1 | Normal metin AA FAIL | **Dark temada `#B91C1C` Red 700 (6.47:1) kullan** |

---

### 2.3. Revize Edilmiş Renk Token Önerileri (`[UX PROPOSAL]` — `shared.css` & `AppTheme` Hizalı)

> [!NOTE]
> Aşağıdaki token'lar `shared.css` v1.2 ve mevcut [`lib/core/theme/app_theme.dart`](../../lib/core/theme/app_theme.dart) (`AppTheme`) ile uyumlu olacak biçimde güncellenmiştir (`verify_wcag.js` kapsamında **83/83** renk kontrastı geçmektedir; genel WCAG uygunluğu beyanı değildir). Proje sahibi onayını beklemektedir.

| Token | Light HEX | Dark HEX | Light Oran (White / Subtle) | Dark Oran (Slate 800 bg) | Kontrast Durumu |
|---|---|---|---|---|---|
| `color-text-main` | `#0F172A` (`AppTheme.textMainLight`) | `#F8FAFC` | 17.85:1 / 16.30:1 | 13.98:1 | ✅ AAA her ikisi |
| `color-text-muted` | **`#475569`** (`AppTheme.textMutedLight`) | `#94A3B8` | **7.58:1 / 6.92:1** | 5.71:1 | ✅ AAA / ✅ AA |
| **`color-cash-action`** | **`#047857`** (Emerald 700) | `#047857` (Hover `#065F46`) | **5.48:1** | **5.48:1 (Hover 7.68:1)** | ✅ AA / ✅ AAA |
| **`color-card-action`** | `#2563EB` (Blue 600) | **`#1D4ED8`** (Hover `#1E40AF`) | 5.17:1 | **6.70:1 (Hover 8.72:1)** | ✅ AA / ✅ AAA |
| **`color-warning`** | **`#B45309`** (`AppTheme.statusWarning`) | `#B45309` (Metin `#FBBF24`) | **5.02:1** | Metin: **8.76:1** | ✅ AA / ✅ AAA |
| **`color-danger`** | **`#B91C1C`** (`AppTheme.statusOffline`) | **`#B91C1C`** (Metin `#F87171`) | **6.47:1** | **6.47:1** (Metin: 5.29:1) | ✅ AA |
| `color-cash-bg` | `#DCFCE7` (Metin `#166534`) | RGBA Blend (`#34D399`) | Rozet: 6.49:1 | Rozet: 6.41:1 | ✅ AA |
| `color-warning-bg` | `#FEF3C7` (Metin `#92400E`) | RGBA Blend (`#FBBF24`) | Rozet: 6.37:1 | Rozet: 7.51:1 | ✅ AA / ✅ AAA |
| `color-outbox-bg` | `#DBEAFE` (Metin `#1E40AF`) | RGBA Blend (`#60A5FA`) | Rozet: 7.15:1 | Rozet: 4.89:1 | ✅ AAA / ✅ AA |

**Önemli Uygulama Notu:** `#059669` (Emerald 600) büyük/kalın metin butonlarında (≥14pt Bold) büyük metin AA kriteri olan 3.0:1'i 3.77:1 ile karşılar; ancak referans olarak Emerald 700 `#047857` tercih edilir.

---

## 3. Tipografi Sistemi `[UX PROPOSAL]`

### 3.1. Yazı Tipi Önerileri

1. **Arayüz Fontu:** `Inter` veya platform varsayılanı (`Roboto` / `-apple-system`). Etiketler, butonlar, menüler için.
2. **Sayısal / Finansal Font:** `Roboto Mono` veya OpenType `tabular-nums` özelliği aktif font. Tüm parasal tutarlar, barkodlar, miktarlar için.

**Not:** Bu fontların gerçekte projeye eklenmesi proje sahibi onayını ve `pubspec.yaml` değişikliğini gerektirir. Mevcut `pubspec.yaml`'de özel font tanımı bulunmamaktadır.

### 3.2. Tipografi Skalası Önerisi

| Stil Adı | Boyut | Ağırlık | Font | Kullanım |
|---|---|---|---|---|
| `display-total` | 48–64 sp | Bold 700 | Monospace | Kasa "Genel Toplam" tutar kutusu |
| `display-change` | 36–44 sp | Bold 700 | Monospace | "Para Üstü" alanı |
| `headline-lg` | 24–28 sp | SemiBold 600 | Sans-serif | Modül ana başlıkları |
| `headline-md` | 20–22 sp | SemiBold 600 | Sans-serif | Modal / Kart başlıkları |
| `body-currency` | 15–16 sp | SemiBold 600 | Monospace | Sepet birim fiyat ve satır toplamı |
| `body-md` | 14–15 sp | Regular 400 | Sans-serif | Genel metinler, ürün adları |
| `body-sm` | 12–13 sp | Regular 400 | Sans-serif | İkincil bilgiler |
| `caption-mono` | 11–12 sp | Regular 400 | Monospace | Barkod numaraları |

**Para Sütunu Hizalama İlkesi:** Parasal sütunlar her zaman sağa dayalı (right-aligned) gösterilir. Bu INV-01 kapsamında bir iş kuralıdır.

---

## 4. Spacing, Grid ve Layout Sistemi `[UX PROPOSAL]`

**Öneri:** 8 dp temel ızgara sistemi (8-Point Grid).

| Değer | dp | Kullanım |
|---|---|---|
| `space-1` | 4 | Mikro boşluklar, ikonlar arası |
| `space-2` | 8 | Form dolguları, sıkı butonlar |
| `space-3` | 12 | Standart buton dolgusu, tablo satır iç boşluğu |
| `space-4` | 16 | Kart iç boşluğu, sütunlar arası |
| `space-6` | 24 | Sayfa kenar boşlukları, modal içi |
| `space-8` | 32 | Büyük bölüm ayrımları |
| `space-12` | 48 | Panel ayrımları |

**Köşe Yuvarlama:**
- `radius-sm`: 4 dp — Rozetler, etiketler
- `radius-md`: 8 dp — Butonlar, giriş alanları
- `radius-lg`: 12 dp — Kartlar, modaller
- `radius-pill`: 9999 dp — Yuvarlak butonlar, durum noktaları

---

## 5. Temel Bileşen Şartnameleri `[UX PROPOSAL]`

### 5.1. Barkod Giriş Alanı (BarcodeInputField)
- **Yükseklik:** 44–48 dp
- **Davranış:** POS ekranı boştayken varsayılan odaklıdır. Odak yönetimi context-aware modele göre çalışır. Bkz. [DESIGN_DECISIONS.md §3.4](./DESIGN_DECISIONS.md).
- **Görsel:** Belirgin sınır, barkod okuyucu ikonu, açık placeholder metni.

### 5.2. Sepet Veri Tablosu (CartTable)
Önerilen sütun yapısı:
1. `Sıra` (40 dp, ortalanmış)
2. `Barkod` (110 dp, monospace, sol)
3. `Ürün Adı` (Esnek, sol, kalın)
4. `Birim Fiyat` (100 dp, monospace, **sağa dayalı**)
5. `Miktar` (110 dp, [-] [n] [+] kontrolleri)
6. `Satır Tutarı` (110 dp, monospace, **sağa dayalı**, kalın)
7. `Sil` (48 dp, kırmızı ikon)

Satır yüksekliği: 44–48 dp önerilir.

### 5.3. Hub / Outbox Durum Rozetleri (StatusBadge)
| Durum | Zemin | Metin | Oran | WCAG |
|---|---|---|---|---|
| Hub Online | `#DCFCE7` | `#166534` | 6.49:1 | ✅ AA |
| Local Offline | `#FEF3C7` | `#92400E` | 6.37:1 | ✅ AA |
| Outbox Pending | `#DBEAFE` | `#1E3A8A` | 8.49:1 | ✅ AAA |

### 5.4. Ödeme Butonları (PaymentButtons)
- **Nakit Butonu:** Yüksek kontrast için `#047857` (Emerald 700) üzerine beyaz metin önerilir (5.48:1, AA ✅). Büyük kalın metin kullanılırsa `#059669` de büyük metin 3.77:1 ≥ 3.0:1 kriterini karşılar.
- **Kart Butonu:** `#2563EB` (Blue 600) üzerine beyaz, 5.17:1 (AA ✅).

---

## 6. Görsel Tasarım Yaklaşımı ve Sınırlar

> [!NOTE]
> Bu ortamda Figma veya gerçek görsel tasarım aracı bağlı değildir. Üretilen tasarım çıktıları:
> - ASCII / Unicode tel kafes (wireframe) şartnameleri
> - Mermaid diyagramları (site map, state diagram, sequence)
> - Mevcut [`AppTheme`](../../lib/core/theme/app_theme.dart) ile hizalanmış Dark/Semantic token devir eşlemesi (bkz. [`UX_07_FLUTTER_HANDOFF.md`](./UX_07_FLUTTER_HANDOFF.md))
> - HTML/CSS/JS interaktif prototip (tasarım demosu; gerçek uygulama değil)
>
> Bu çıktılar **nihai görsel tasarım değildir; tasarım şartnamesi ve referans dokümanıdır.** Pilot öncesi gerçek Figma / görsel tasarım üretimi ayrıca planlanabilir.
