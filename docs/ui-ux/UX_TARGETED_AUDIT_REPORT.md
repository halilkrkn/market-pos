# MARKET MMS — UX Final Targeted Technical Audit Report

**Tarih:** 11 Kasım 2026 *(İlk Denetim: 7 Kasım 2026)*  
**Auditor / Hazırlayan:** Google Antigravity (Gemini Modeli)  
**Denetim Muhatabı:** Bağımsız Tasarım & Mimari Danışmanı (ChatGPT) ve Proje Sahibi  
**Proje / Depo:** `market-pos` (Market Management System - MMS)  
**Doküman Türü:** Hedefli Teknik Denetim, Güvenlik, Ergonomi ve Kaynak Kod Doğrulama Raporu  
**Kanonik Dosya:** [`docs/ui-ux/UX_TARGETED_AUDIT_REPORT.md`](./UX_TARGETED_AUDIT_REPORT.md)  
**Statü:** NİHAİ DÜZELTME TAMAMLANDI & PROJE SAHİBİ TARAFINDAN KABUL EDİLDİ (v1.3 — 11 Kasım 2026)  

---

> [!IMPORTANT]
> **DÜZELTME VE KARAR KAPANIŞI BEYANI (v1.3 — 11 Kasım 2026):**  
> Bu sürüm, `v1.2` raporu üzerine **11 Kasım 2026** tarihinde verilen **Proje Sahibi UI/UX Kabulü** ve **`OD-01..OD-04` Karar Kapanışı** ile güncellenmiştir:  
> 1. Önceki `v1.1` sürümünde UX bulguları için kullanılan `B-1.1..B-4.2` kodları, Faz 1.1 ve mimari güvenlik backlog'undaki `B-2` / `B-3` kodlarıyla ID çakışmasını önlemek amacıyla **`UX-AUD-1.1..4.3`** biçiminde yeniden adlandırılmıştır (tarihsel eşleme korunmuştur).  
> 2. `OD-01` (Half-Up yuvarlama + integer kuruş), `OD-02` (`BR-POS-05` Parked Carts: MVP dışı / `OUT_OF_SCOPE`), `OD-03` (`BR-PROD-05` offline bilinmeyen barkod eklenemez/oluşturulamaz; Hub gerekir) ve `OD-04` (sanal numpad opsiyonel, varsayılan kapalı) kararları kapatılmıştır. `test_currency_engine.js` (43/43), `verify_wcag.js` (83/83 renk kontrastı), `flutter analyze --no-pub`, `flutter test` ve `git status --short` çıktıları doğrulama sonrası birebir güncellenmiştir.  
> 3. Uygulama kaynak koduna (`lib/`, `test/`, `pubspec.yaml`, backend) dokunulmamış, `git add` / `commit` / `push` çalıştırılmamıştır; Faz 1.2 kodlaması ayrı onay beklemektedir.

---

## 1. Yönetici Özeti ve Denetim Metodolojisi

Bu hedefli denetim, MARKET MMS projesinin UX teslimatında yer alan 4 kritik teknik eksene odaklanmıştır:
1. **Currency Engine (`shared.js`):** Sayısal sınırlar, IEEE-754 kayan nokta riskleri, binlik/ondalık ayırıcı açıkları, case sensitivity ve `BigInt` gereksinimi.
2. **WCAG Kontrast Doğrulaması (`verify_wcag.js` & `shared.css`):** İlk denetimde test edilen 32 temel kombinasyonun ötesinde hover, active, disabled, placeholder, error, modal, demo bar ve Dark inline `var(--success/warning/danger)` durumlarının gerçek CSS/HTML yüzeyleri üzerinden analizi ve sRGB doğrusal dönüşüm eşiği (`0.04045`). *(Tamamlanan v1.2 sonucunda `verify_wcag.js` 83/83 PASS seviyesine çıkarılmıştır; bkz. Bölüm 6–7.)*
3. **Ekran Ergonomisi ve Responsive Yapı:** 10 HTML ekranındaki dokunmatik hedef boyutları ($\ge 48\times 48\text{ px}$ kuralı), CSS px vs Flutter logical pixel ayrımı, CSS breakpoint eksikliği ve simülasyon vs gerçek etkileşim analizi.
4. **Ürün Kararları ve Mimari Sınırlar:** İade işleminin dağıtık/çevrimdışı bağlantı gereksinimi, tek ödeme yöntemi, kasiyer rolü yokluğu, donanımsal banka POS dışılığı, `12.50 TL` standardı ve B-2/B-3 maddelerinin statü düzeltmesi.

### 1.1 Bulguların Sınıflandırma Kriterleri
Her bulgu iki katı kategoriden birine atanmıştır:
- **`[ZORUNLU]` (Mandatory Defect):** Veri bütünlüğü, finansal kesinlik, erişilebilirlik ihlali veya sistem çökmesine yol açabilecek, üretime/pilota geçmeden önce mutlaka düzeltilmesi gereken kusurlar.
- **`[İYİLEŞTİRME]` (Enhancement / Recommendation):** Sistemin çalışmasını durdurmayan ancak kod kalitesini, lokalizasyon toleransını veya tasarım sistemi tutarlılığını artıran öneriler.

---

## 2. Bölüm 1: Currency Engine (`shared.js`) Derinlemesine Denetimi

`docs/ui-ux/visual-designs/shared.js` dosyasındaki `parseToCents()` fonksiyonu, talimat verilen 14 kritik girdi ile izole Node.js çalışma ortamında test edilmiş ve aşağıdaki gerçek çıktılar elde edilmiştir:

### 2.1 14 Hedefli Test Girdisinin Gerçek Sonuç Tablosu

| Test Girdisi | Varsayılan (`allowNegative=false`) | İzinli (`allowNegative=true`) | Beklenen Davranış ve Açıklama | Denetim Teşhisi |
|---|---|---|---|:---:|
| `90071992547409.91` | `9007199254740991 kuruş` | `9007199254740991 kuruş` | $2^{53}-1$ (Max Safe Integer) sınırına tam oturur. | **BAŞARILI** |
| `90071992547409.92` | `HATA: Güvenli kuruş tamsayı sınırı aşıldı` | `HATA: Güvenli kuruş tamsayı sınırı aşıldı` | $2^{53}$ sınırını aştığı için güvenle reddedilir. | **BAŞARILI** |
| `1,250.00` | `125000 kuruş` | `125000 kuruş` | Standart binlik virgülü temizlenip kuruşa çevrilir. | **BAŞARILI** |
| `12,50` | `1250 kuruş` | `1250 kuruş` | Türkçe tek virgül kullanıcı alışkanlığıyla noktaya çevrilir. | **BAŞARILI** |
| `1,25.00` | `12500 kuruş` | `12500 kuruş` | Hatalı binlik gruplaması (2 basamak). Kabul edildi! | **KRİTİK AÇIK** |
| `1,250,000.00` | `125000000 kuruş` | `125000000 kuruş` | Çift binlik virgülü temizlenir. | **BAŞARILI** |
| `12,34,567.89` | `123456789 kuruş` | `123456789 kuruş` | Hint sayı sistemi / hatalı gruplama. Kabul edildi! | **KRİTİK AÇIK** |
| `1.250,00` | `HATA: En fazla iki ondalık basamak...` | `HATA: En fazla iki ondalık basamak...` | Türkçe standart binlik formatı yanlış hata mesajıyla reddedildi. | **MANTIK HATASI** |
| `1,,250.00` | `125000 kuruş` | `125000 kuruş` | Ardışık çift virgül içeriyor ama kabul edildi! | **KRİTİK AÇIK** |
| `-0.50` | `HATA: Negatif değerlere izin verilmez` | `-50 kuruş` | Varsayılanda reddedilir, izinliyse negatif döner. | **BAŞARILI** |
| `12.345` | `HATA: En fazla iki ondalık basamak...` | `HATA: En fazla iki ondalık basamak...` | Alt kuruş girişi başarıyla engellenir. | **BAŞARILI** |
| `12TL` | `1200 kuruş` | `1200 kuruş` | Bitişik büyük TL temizlenir. | **BAŞARILI** |
| `12 TL` | `1200 kuruş` | `1200 kuruş` | Boşluklu büyük TL temizlenir. | **BAŞARILI** |
| `12 Tl` | `HATA: Geçersiz sayısal format...` | `HATA: Geçersiz sayısal format...` | Küçük 'l' harfi (`Tl`) yüzünden reddedildi! | **HATALI RED** |

---

### 2.2 Currency Engine Bulguları ve Düzeltme Önerileri

#### BULGU 1.1: Ardışık ve Hatalı Binlik Ayırıcılarının Denetlenmeden Silinmesi
- **Dosya ve Satır:** [`docs/ui-ux/visual-designs/shared.js`](./visual-designs/shared.js#L94-L107)
- **Mevcut Davranış:**  
  Satır 100'deki kontrol `if (commaCount > 1 && dotCount === 0)` şeklindedir. Eğer girdide ondalık nokta varsa (`dotCount === 1`), virgül sayısının 1'den fazla olması veya ardışık gelmesi denetlenmez. Satır 107'de doğrudan `normalized = cleaned.replace(/,/g, '');` çalıştırılır.
- **Risk:**  
  `1,,250.00` gibi açıkça hatalı/bozuk girişler ile `1,25.00` veya `12,34,567.89` gibi geçersiz basamak gruplamaları sessizce kabul edilerek yanlış finansal tutarlara dönüştürülür.
- **Önerilen Düzeltme:**  
  Binlik virgülleri kontrolsüzce silinmemeli; regex ile 3'lü basamak blokları doğrulanmalıdır:
  ```javascript
  // Sadece geçerli binlik bloklarına izin ver: 1,250.00 veya 1,250,000.00
  if (commaCount > 0 && dotCount === 1) {
    if (!/^\d{1,3}(,\d{3})+(\.\d{1,2})?$/.test(cleaned)) {
      return { valid: false, error: 'Geçersiz binlik ayırıcı formatı (Örn: 1,250.00)' };
    }
    normalized = cleaned.replace(/,/g, '');
  }
  ```
- **Sınıflandırma:** **`[ZORUNLU]`**

---

#### BULGU 1.2: `12 Tl` (Mixed Case) Para Birimi Ekinin Reddedilmesi
- **Dosya ve Satır:** [`docs/ui-ux/visual-designs/shared.js`](./visual-designs/shared.js#L79-L81)
- **Mevcut Davranış:**  
  Kod yalnızca `cleaned.endsWith('TL') || cleaned.endsWith('tl')` kontrolü yapmaktadır. `Tl` veya `tL` yazıldığında ek silinmemekte ve sonraki sayısal regex kontrolü (`/^\d+(\.\d+)?$/`) harf içerdiği için girdi reddedilmektedir.
- **Risk:**  
  Kullanıcı veya barkod cihazı arayüze `12 Tl` yazdığında sistem "Geçersiz sayısal format veya yabancı karakter" hatası vererek kullanıcıyı engeller.
- **Önerilen Düzeltme:**  
  Büyük/küçük harf duyarsız (case-insensitive) regex ile temizleme yapılmalıdır:
  ```javascript
  cleaned = cleaned.replace(/tl$/i, '').trim();
  ```
- **Sınıflandırma:** **`[ZORUNLU]`**

---

#### BULGU 1.3: Türkçe Standart Formatının (`1.250,00`) Yanlış Hata Mesajıyla Çarpıtılması
- **Dosya ve Satır:** [`docs/ui-ux/visual-designs/shared.js`](./visual-designs/shared.js#L105-L125)
- **Mevcut Davranış:**  
  Girdide 1 nokta ve 1 virgül olduğunda (Örn: `1.250,00`), kod noktanın her zaman ondalık ayırıcı olduğunu varsaymakta ve virgülü silmektedir. Sonuç `1.25000` olmakta; split sonrasında ondalık hane 5 basamak (`25000`) çıktığı için kullanıcıya "En fazla iki ondalık basamak girilebilir" şeklinde yanıltıcı bir hata dönmektedir.
- **Risk:**  
  Türkiye'deki muhasebe ve perakende standardı olan "nokta binlik, virgül ondalık" (`1.250,00 TL`) formatını giren kullanıcılar, sistemin neyi reddettiğini anlayamaz.
- **Önerilen Düzeltme:**  
  Eğer tek nokta ve tek virgül varsa ve virgül noktadan sonra geliyorsa (ve virgülden sonra en fazla 2 basamak varsa), noktanın binlik, virgülün ondalık olduğu algılanmalıdır:
  ```javascript
  if (dotCount === 1 && commaCount === 1) {
    const dotIdx = cleaned.indexOf('.');
    const commaIdx = cleaned.indexOf(',');
    if (commaIdx > dotIdx) { // Örn: 1.250,50
      normalized = cleaned.replace('.', '').replace(',', '.');
    }
  }
  ```
- **Sınıflandırma:** **`[İYİLEŞTİRME]`**

---

#### BULGU 1.4: `Number` Aritmetiği vs `BigInt` Kullanımının Teknik Değerlendirmesi
- **Mevcut Durum:**  
  `shared.js`, JavaScript'in yerel `Number` türünü ve `Number.isSafeInteger()` sınırını ($2^{53} - 1 = 9,007,199,254,740,991$) kullanmaktadır.
- **Sınır Analizi:**  
  $9,007,199,254,740,991\text{ kuruş} \approx 90\text{ trilyon TL}$'dir. Küçük ve orta ölçekli bir perakende marketin tekil fiş tutarı ($0.50\text{ TL}$ – $50,000.00\text{ TL}$) veya yıllık cirosu ($100,000,000.00\text{ TL}$) bu sınırın trilyonda biri seviyesindedir.
- **Olası Precision Kaybı Riski:**  
  Satır 139'daki `totalCents = (intLiras * 100) + decKurus` işleminde, eğer kullanıcı kazaen barkod okuyucuyla fiyat alanına 16 basamaklı bir EAN/IMEI kodu okutursa (`intLiras > 90071992547409`), $100$ ile çarpım $2^{53}$ sınırını aşar. Bu durumda IEEE-754 mantissa yuvarlaması nedeniyle alt kuruşlarda 1-2 kuruşluk kayma yaşanabilir; ancak satır 140'taki `!Number.isSafeInteger(totalCents)` denetimi bunu yakalayarak hataya düşürmektedir.
- **Teknik Karar ve Gerekçe:**  
  - JavaScript prototipinde `BigInt` kullanılması zorunlu değildir; çünkü `BigInt`, `JSON.stringify` ile doğrudan serileştirilemez (`TypeError: Do not know how to serialize a BigInt`), Riverpod ve Flutter web köprülerinde ek tip dönüşümü gerektirir.
  - Asıl çözüm, girdi kutusuna azami karakter sınırı (Örn: `maxlength="12"`, yani azami 9.99 milyar TL) koymaktır.
  - Ancak Dart/Flutter tarafında (`lib/` ve `packages/mms_client_storage`), 64-bit signed integer (`int` / `BIGINT`) kullanılması mimari anayasa gereği zorunludur.
- **Sınıflandırma:** **`[İYİLEŞTİRME]`**

---

## 3. Bölüm 2: WCAG 2.1 AA Doğrulaması ve `shared.css` Karşılaştırması

### 3.1 WCAG sRGB Doğrusal Dönüşüm Eşik Değeri Analizi
[`docs/ui-ux/visual-designs/verify_wcag.js`](./visual-designs/verify_wcag.js#L8-L11) dosyasında kullanılan fonksiyon:
```javascript
function sRGBtoLin(c) {
  c = c / 255;
  return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}
```

- **Standart Karşılaştırması:**  
  - **W3C WCAG 2.0 / 2.1 Spesifikasyonu:** Eşik değeri olarak resmi metinde `0.03928` tanımlanmıştır.
  - **IEC 61966-2-1:1999 (Resmi sRGB Standardı):** Eşik değeri olarak `0.04045` tanımlanmıştır. ($0.04045 \approx 12.92 \times 0.0031308$).
- **8-Bit Tamsayı Renklerdeki ($0..255$) Matematiksel Etkisi:**  
  - $R=10 \implies 10 / 255 = 0.0392157$. Bu değer hem $\le 0.03928$ hem de $\le 0.04045$ olduğu için her iki formülde de **doğrusal bölmeye** ($c / 12.92$) girer.
  - $R=11 \implies 11 / 255 = 0.0431373$. Bu değer hem $> 0.03928$ hem de $> 0.04045$ olduğu için her iki formülde de **üstel fonksiyona** ($((c+0.055)/1.055)^{2.4}$) girer.
  - **Sonuç:** Web ve CSS ortamında kullanılan tüm 8-bit hex renklerde (`#000000` - `#FFFFFF`), eşik değerinin `0.03928` veya `0.04045` olması **matematiksel olarak 1 bit dahi fark yaratmaz**. `verify_wcag.js` betiğinin kullandığı formül W3C WCAG resmi şartnamesine %100 sadıktır.

---

### 3.2 İlk Denetim Anındaki CSS Sınıfı Teşhis Tablosu *(Tarihsel Tespit — Bölüm 6–7'de Giderildi)*

İlk denetimde `verify_wcag.js` yalnızca 32 temel kombinasyonu test etmişti ve aşağıdaki eksikler tespit edilmişti *(bu açıkların tamamı v1.2 düzeltmesiyle `shared.css`, 10 HTML ekranı ve `verify_wcag.js` 83/83 kapsamıyla giderilmiştir; güncel tablo Bölüm 7.2'dedir)*:

| Tema | UI Bileşeni ve Durum | CSS Sınıfı / Seçici | Ön Plan (FG) | Arka Plan (BG) | Kontrast Oranı | WCAG Eşiği | Değerlendirme & Statü |
|---|---|---|:---:|:---:|:---:|:---:|:---:|
| **Light** | Buton Normal (Cash) | `.btn-cash` | `#FFFFFF` | `#047857` | **5.48:1** | $\ge 4.5:1$ | ✅ PASS AA (Test edilmiş) |
| **Light** | Buton Hover (Cash) | `.btn-cash:hover` | `#FFFFFF` | `#065F46` | **7.68:1** | $\ge 4.5:1$ | ✅ PASS AAA (Yeni Doğrulandı) |
| **Light** | Buton Normal (Card) | `.btn-card` | `#FFFFFF` | `#2563EB` | **5.17:1** | $\ge 4.5:1$ | ✅ PASS AA (Test edilmiş) |
| **Light** | Buton Hover (Card) | `.btn-card:hover` | `#FFFFFF` | `#1D4ED8` | **6.70:1** | $\ge 4.5:1$ | ✅ PASS AA (Yeni Doğrulandı) |
| **Light** | Buton Normal (Danger) | `.btn-danger` | `#FFFFFF` | `#B91C1C` | **6.47:1** | $\ge 4.5:1$ | ✅ PASS AA (Test edilmiş) |
| **Light** | Buton Hover (Danger) | `.btn-danger:hover` | `#FFFFFF` | `#991B1B` | **8.31:1** | $\ge 4.5:1$ | ✅ PASS AAA (Yeni Doğrulandı) |
| **Light** | Buton Normal (Secondary) | `.btn-secondary` | `#0F172A` | `#FFFFFF` | **17.85:1** | $\ge 4.5:1$ | ✅ PASS AAA (Test edilmiş) |
| **Light** | Buton Hover (Secondary) | `.btn-secondary:hover` | `#0F172A` | `#F1F5F9` | **16.30:1** | $\ge 4.5:1$ | ✅ PASS AAA (Yeni Doğrulandı) |
| **Light** | Buton Disabled | `.btn:disabled` | *Tanımsız* | *Tanımsız* | *Tarayıcı Varsayılanı* | N/A (Muaf) | ⚠️ **CSS'TE EKSİK** |
| **Light** | Input Placeholder | `.input-text::placeholder` | *Tanımsız* | `#FFFFFF` | *Tarayıcı Varsayılanı* | $\ge 4.5:1$ | ⚠️ **CSS'TE EKSİK** |
| **Light** | Input Error Durumu | `.input-error` | *Tanımsız* | *Tanımsız* | *Tanımsız* | $\ge 3.0:1$ | ⚠️ **CSS'TE EKSİK** |
| **Light** | Demo Uyarı Çubuğu Metni | `.demo-disclaimer-bar` | `#B45309` | `#FFFBEB` | **4.84:1** | $\ge 4.5:1$ | ✅ PASS AA (Yeni Doğrulandı) |
| **Light** | Demo Uyarı Çubuğu Sınırı | `.demo-disclaimer-bar` | `#FDE68A` | `#FFFBEB` | **1.21:1** | Dekoratiftir | ℹ️ Non-essential |
| **Light** | Modal Başlık Metni | `.modal-header` | `#0F172A` | `#F1F5F9` | **16.03:1** | $\ge 4.5:1$ | ✅ PASS AAA (Yeni Doğrulandı) |
| **Light** | Modal Banknot Butonu | `.banknote-btn` | `#0F172A` | `#F1F5F9` | **16.03:1** | $\ge 4.5:1$ | ✅ PASS AAA (Yeni Doğrulandı) |
| **Light** | Tablo Satır Hover Metni | `.mms-table tr:hover td` | `#0F172A` | `#F8FAFC` (blended) | **17.11:1** | $\ge 4.5:1$ | ✅ PASS AAA (Yeni Doğrulandı) |
| **Dark** | Buton Normal (Card) | `.btn-card` | `#FFFFFF` | `#1D4ED8` | **6.70:1** | $\ge 4.5:1$ | ✅ PASS AA (Test edilmiş) |
| **Dark** | Buton Normal (Secondary) | `.btn-secondary` | `#F8FAFC` | `#1E293B` | **13.98:1** | $\ge 4.5:1$ | ✅ PASS AAA (Test edilmiş) |
| **Dark** | Buton Hover (Secondary) | `.btn-secondary:hover` | `#F8FAFC` | `#0F172A` | **17.06:1** | $\ge 4.5:1$ | ✅ PASS AAA (Yeni Doğrulandı) |
| **Dark** | Buton Disabled | `.btn:disabled` | *Tanımsız* | *Tanımsız* | *Tarayıcı Varsayılanı* | N/A (Muaf) | ⚠️ **CSS'TE EKSİK** |
| **Dark** | Demo Uyarı Çubuğu Metni | `body.dark .demo-disclaimer-bar` | `#FBBF24` | `#1C1917` | **10.48:1** | $\ge 4.5:1$ | ✅ PASS AAA (Yeni Doğrulandı) |
| **Dark** | Modal Başlık Metni | `.modal-header` | `#F8FAFC` | `#0F172A` | **16.29:1** | $\ge 4.5:1$ | ✅ PASS AAA (Yeni Doğrulandı) |
| **Dark** | Modal Banknot Butonu | `.banknote-btn` | `#F8FAFC` | `#0F172A` | **16.29:1** | $\ge 4.5:1$ | ✅ PASS AAA (Yeni Doğrulandı) |
| **Dark** | Tablo Satır Hover Metni | `.mms-table tr:hover td` | `#F8FAFC` | `#232D3F` (blended) | **12.88:1** | $\ge 4.5:1$ | ✅ PASS AAA (Yeni Doğrulandı) |
| **Dark** | Rozet (Subtle Yüzeyde) | `.badge-online` on `#0F172A` | `#34D399` | `#0D3325` (blended) | **7.82:1** | $\ge 4.5:1$ | ✅ PASS AAA (Yeni Doğrulandı) |
| **Dark** | Rozet (Subtle Yüzeyde) | `.badge-offline` on `#0F172A`| `#FBBF24` | `#302318` (blended) | **9.05:1** | $\ge 4.5:1$ | ✅ PASS AAA (Yeni Doğrulandı) |
| **Dark** | Rozet (Subtle Yüzeyde) | `.badge-outbox` on `#0F172A` | `#60A5FA` | `#13264F` (blended) | **5.79:1** | $\ge 4.5:1$ | ✅ PASS AA (Yeni Doğrulandı) |
| **Dark** | Rozet (Subtle Yüzeyde) | `.badge-danger` on `#0F172A` | `#F87171` | `#301A24` (blended) | **5.88:1** | $\ge 4.5:1$ | ✅ PASS AA (Yeni Doğrulandı) |

---

### 3.3 WCAG Bulguları ve Düzeltme Önerileri

#### BULGU 2.1: Buton Disabled ve Active Durumlarının CSS'te Tanımsız Olması
- **Dosya ve Satır:** [`docs/ui-ux/visual-designs/shared.css`](./visual-designs/shared.css#L137-L190)
- **Mevcut Davranış:**  
  CSS dosyasında `.btn:disabled`, `.btn[disabled]` veya `.btn:active` sözde sınıfları (pseudo-classes) tanımlanmamıştır.
- **Risk:**  
  Bir buton `disabled` yapıldığında tarayıcının varsayılan grileştirmesi (User-Agent style) devreye girer. Özellikle Dark temada tarayıcı varsayılanları okunaksız hale gelebilir.
- **Önerilen Düzeltme:**  
  Tasarım sistemine açıkça disabled ve active durum tokenları eklenmelidir:
  ```css
  .btn:disabled {
    opacity: 0.45;
    cursor: not-allowed;
    pointer-events: none;
  }
  .btn:active {
    transform: scale(0.98);
  }
  ```
- **Sınıflandırma:** **`[İYİLEŞTİRME]`**

---

#### BULGU 2.2: Input Placeholder ve Doğrulama Hata Durumunun (Error State) Tanımsız Olması
- **Dosya ve Satır:** [`docs/ui-ux/visual-designs/shared.css`](./visual-designs/shared.css#L220-L235)
- **Mevcut Davranış:**  
  `.input-text` için `::placeholder` ve `.input-error` kuralları yazılmamıştır.
- **Risk:**  
  Farklı tarayıcılarda placeholder metinleri (örneğin Safari veya eski Edge) düşük kontrastla ($< 4.5:1$) görüntülenebilir. Hatalı tutar girildiğinde input çerçevesini kırmızıya boyayacak bir `.input-error` sınıfı bulunmamaktadır.
- **Önerilen Düzeltme:**  
  ```css
  .input-text::placeholder {
    color: var(--text-muted);
    opacity: 1;
  }
  .input-text.input-error {
    border-color: var(--danger);
    box-shadow: 0 0 0 2px rgba(185, 28, 28, 0.2);
  }
  ```
- **Sınıflandırma:** **`[İYİLEŞTİRME]`**

---

## 4. Bölüm 3: Ekran Ergonomisi ve Viewport Denetimi

### 4.1 $48\times 48\text{ CSS px}$ Altındaki Dokunmatik Kontrollerin Tam Listesi

Mobil cihazlarda ve dokunmatik POS ekranlarında el/parmak ergonomisi standardı (WCAG 2.5.5 Target Size Enhanced) $\ge 48\times 48\text{ dp/px}$ olmalıdır. Yapılan taramada aşağıdaki kontrollerin bu sınırın altında kaldığı tespit edilmiştir:

| Ekran Dosyası | Satır No | Kontrol / Buton Tanımı | Mevcut Ölçü | Hedeflenen Standart | Sapma Durumu |
|---|:---:|---|:---:|:---:|:---:|
| [`mob-01-dashboard.html`](./visual-designs/mob-01-dashboard.html) | Satır 64 | Mobil Header Tema Butonu | `height: 28px; padding: 2px 8px;` | $\ge 48\times 48\text{ px}$ | $-20\text{ px}$ yetersiz |
| [`mob-02-barcode-scan.html`](./visual-designs/mob-02-barcode-scan.html) | Satır 68 | Kamera Fener Aç/Kapa Butonu | `height: 28px; padding: 2px 8px;` | $\ge 48\times 48\text{ px}$ | $-20\text{ px}$ yetersiz |
| [`mob-02-barcode-scan.html`](./visual-designs/mob-02-barcode-scan.html) | Satır 71 | Mobil Header Tema Butonu | `height: 28px; padding: 2px 8px;` | $\ge 48\times 48\text{ px}$ | $-20\text{ px}$ yetersiz |
| [`mob-02-barcode-scan.html`](./visual-designs/mob-02-barcode-scan.html) | Satır 102 | Sepete Git Alt Butonu | `height: 44px;` | $\ge 48\times 48\text{ px}$ | $-4\text{ px}$ yetersiz |
| [`mob-02-barcode-scan.html`](./visual-designs/mob-02-barcode-scan.html) | Satır 105 | Stok Gör Alt Butonu | `height: 44px;` | $\ge 48\times 48\text{ px}$ | $-4\text{ px}$ yetersiz |
| [`mob-03-cart-checkout.html`](./visual-designs/mob-03-cart-checkout.html)| Satır 46 | Sepeti Temizle Butonu | `height: 28px; padding: 2px 8px;` | $\ge 48\times 48\text{ px}$ | $-20\text{ px}$ yetersiz |
| [`mob-03-cart-checkout.html`](./visual-designs/mob-03-cart-checkout.html)| Satır 49 | Mobil Header Tema Butonu | `height: 28px; padding: 2px 8px;` | $\ge 48\times 48\text{ px}$ | $-20\text{ px}$ yetersiz |
| [`mob-03-cart-checkout.html`](./visual-designs/mob-03-cart-checkout.html)| Satır 67, 69 | Sepet Miktar Butonları (`-` ve `+`) | `width: 40px; height: 40px;` | $\ge 48\times 48\text{ px}$ | **$-8\text{ px}$ yetersiz** |
| [`mob-03-cart-checkout.html`](./visual-designs/mob-03-cart-checkout.html)| Satır 85, 87 | Sepet Miktar Butonları (`-` ve `+`) | `width: 40px; height: 40px;` | $\ge 48\times 48\text{ px}$ | **$-8\text{ px}$ yetersiz** |
| [`mob-03-cart-checkout.html`](./visual-designs/mob-03-cart-checkout.html)| Satır 103, 105| Sepet Miktar Butonları (`-` ve `+`) | `width: 40px; height: 40px;` | $\ge 48\times 48\text{ px}$ | **$-8\text{ px}$ yetersiz** |
| [`mob-03-cart-checkout.html`](./visual-designs/mob-03-cart-checkout.html)| Satır 127, 130| Nakit ve Kart Tahsilat Butonları | `height: 46px;` | $\ge 48\times 48\text{ px}$ | $-2\text{ px}$ yetersiz |
| [`mob-04-stock-view.html`](./visual-designs/mob-04-stock-view.html) | Satır 60 | Barkod Tara Üst Butonu | `height: 28px; padding: 2px 8px;` | $\ge 48\times 48\text{ px}$ | $-20\text{ px}$ yetersiz |
| [`mob-04-stock-view.html`](./visual-designs/mob-04-stock-view.html) | Satır 63 | Mobil Header Tema Butonu | `height: 28px; padding: 2px 8px;` | $\ge 48\times 48\text{ px}$ | $-20\text{ px}$ yetersiz |
| [`win-02-pos.html`](./visual-designs/win-02-pos.html) | Satır 224-265 | Masaüstü POS Sepet Miktar (`-`/`+`)| `height: 28px; padding: 2px 8px;` | $\ge 40\times 40\text{ px}$ (Touch: 48)| $-12\text{ px}$ yetersiz |
| [`win-04-payment-modal.html`](./visual-designs/win-04-payment-modal.html)| Satır 52 | Hızlı Banknot Butonları | `height: 44px;` | $\ge 48\times 48\text{ px}$ | $-4\text{ px}$ yetersiz |
| [`shared.css`](./visual-designs/shared.css) | Satır 221 | Standart Metin Girdisi (`.input-text`) | `height: 40px;` | Masaüstü: 40 / Mobil: 48 | Mobilde $-8\text{ px}$ yetersiz |

---

### 4.2 Dokümantasyondaki $40\times 40\text{ px}$ ve $48\times 48\text{ px}$ Tutarsızlığı
- **Tespit:**  
  `UX_FINAL_DELIVERY_REPORT.md` (v1.4) ve `UX_INDEPENDENT_REVIEW_PACKAGE.md` dokümanlarında mobil dokunma hedeflerinin istisnasız $\ge 48\times 48\text{ dp/px}$ olduğu iddia edilmiştir.
- **Gerçek:**  
  Yukarıdaki tabloda görüldüğü üzere `mob-03-cart-checkout.html` ekranında en yoğun kullanılan miktar artırma/azaltma butonları fiilen `width: 40px; height: 40px;` olarak yazılmıştır. Başlıklardaki butonlar ise $28\text{ px}$'dir.
- **Sınıflandırma:** **`[ZORUNLU]`** (Flutter UI implementasyonunda bu butonlar mutlaka `minWidth: 48, minHeight: 48` yapılmalıdır).

---

### 4.3 CSS Px ile Flutter Logical Pixel (dp) Ayrımı
1. **Masaüstü Ekranlarda:**  
   Windows'ta $1920\times 1080$ çözünürlüklü $15.6''$ bir POS dokunmatik monitöründe piksel yoğunluğu $\sim 141\text{ PPI}$'dır. Eğer Windows ölçeklemesi %100 ise, $1\text{ CSS px} = 1\text{ fiziksel piksel}$ olur. Bu durumda $40\text{ px}$, fiziksel olarak $\frac{40}{141} \times 25.4 \approx 7.2\text{ mm}$ yapar. Bu boyut, insan parmağının temas yüzeyi olan $9-10\text{ mm}$'nin altındadır ve yanlış dokunmalara yol açar.
2. **Flutter Çözümü:**  
   Flutter'da boyutlar cihazın mantıksal pikseline (`dp`) göredir. Flutter uygulamasında kasa butonları `kMinInteractiveDimension` ($48\text{ dp}$) veya daha büyük ($52-64\text{ dp}$) tutulmalı; masaüstü fare kullanımı ile dokunmatik monitör kullanımı ayrıştırılmalıdır.

---

### 4.4 Responsive CSS Breakpoint Analizi
- **Tespit:**  
  `shared.css` ve 10 HTML dosyasında **hiçbir `@media` sorgusu (CSS media query) bulunmamaktadır**.
- **Mevcut Davranış:**  
  - Windows ekranları (`desktop-layout`), ekran genişliği $1366\text{ px}$ altına indiğinde kırılma yaşamamakta; elemanlar taşma veya dikey kaydırmaya girmektedir.
  - Mobil ekranlar (`.mobile-frame`), $390\times 800\text{ px}$ sabit boyutlu bir maket konteyneri içindedir. Ekran genişliği $360\text{ px}$ olan gerçek Android cihazlarda yatay taşma oluşacaktır.
- **Sınıflandırma:** **`[İYİLEŞTİRME]`** (HTML prototipleri görsel vitrin ve tasarım konsepti sunduğu için affedilebilir; ancak Flutter tarafında `LayoutBuilder` ve `MediaQuery` ile adaptif breakpoint yönetimi zorunludur).

---

### 4.5 Gerçek Etkileşimler vs Simülasyon Ayrımı

| Ekran | Gerçek JavaScript Etkileşimi | Statik / Simülasyon / Mock Davranış |
|---|---|---|
| `win-01-dashboard.html` | Tema değiştirme (`toggleTheme`) | Tüm istatistik kartları ve grafik alanları statik HTML. |
| `win-02-pos.html` | Tema değiştirme | Sepet satırları sabit HTML; barkod inputu ve `<button>` hızlı tuşlar statiktir; kısayol ipuçları `main_shell_screen.dart` (`F1/F2/F9/F10/ESC`) ile hizalıdır. |
| `win-03-product-search.html` | Tema değiştirme | Arama inputu ve kategori select elemanı tabloyu filtrelemez (statik liste). |
| `win-04-payment-modal.html` | **GERÇEK ETKİLEŞİM:** `F10` Nakit / `F9` Kart radio seçimi (`setPaymentMethod`), `setAmount()` banknot doldurma, `parseToCents()` / `formatKurus()` ile canlı para üstü & `.is-error` / `.is-info` kutusu, `Escape`/`Enter`/`F9`/`F10` klavye dinleyicileri. | Satış tamamlama sonrası DB/yazıcı yerine tarayıcı `alert()` simülasyonu gösterir. |
| `win-05-sales-history.html` | Tema değiştirme | "İade Al" ve "Fiş Önizleme" butonları `alert(...)` gösterir; `BR-POS-09` Hub LAN uyarısı eklenmiştir. |
| `win-06-stock-management.html`| Tema değiştirme | "Mal Kabul" `alert(...)` açar; stok filtre/tablo statik HTML'dir *(fiziksel sayım / AUDIT kaldırılmıştır)*. |
| `mob-01-dashboard.html` | Tema değiştirme | Özet kartları ve navigasyon statik linklerden ibarettir. |
| `mob-02-barcode-scan.html` | Tema değiştirme, lazer animasyonu | Kamera akışı yoktur (CSS yeşil çizgi animasyonudur); fener butonu `alert(...)` verir. |
| `mob-03-cart-checkout.html` | Tema değiştirme | Miktar `+` / `-` butonları işlevsizdir; tahsilat butonları `alert(...)` simülasyonu üretir. |
| `mob-04-stock-view.html` | Tema değiştirme | Arama alanı filtreleme yapmaz; stok hareket listesi statik HTML'dir. |
| `index.html` | **GERÇEK ETKİLEŞİM:** Global tema yönetimi, iframe üzerinden 10 ekranı dinamik yükleme. | Ekran katalog vitrinidir. |

---

## 5. Bölüm 4: Ürün Kararları ve Mimari Sınırlar

### 5.1 İade İşleminin Merkezi Bağlantı Gereksinimi (`BR-POS-09` & `BR-POS-10`)
- **İş Kuralı:**  
  `BUSINESS_RULES_SPEC.md` uyarınca iade işlemi orijinal fiş referansıyla (`sale_id`) yapılır. İade edilecek miktar, orijinal satış miktarından önceki iadeler düşüldükten sonra kalan miktarı aşamaz:
  $$\text{İade Edilebilir Miktar} = \text{Orijinal Satış Miktarı} - \sum \text{Önceki İadeler}$$
- **Mimari Risk (Dağıtık Çevrimdışı İade Tehlikesi):**  
  Eğer bir mobil istemci çevrimdışıyken (Windows Hub'a bağlı değilken) iade işlemi yapmaya izin verilirse; aynı fiş hem kasada hem de telefonda eşzamanlı olarak iade edilebilir ve mükerrer para iadesi (çift stok girişi ve kasa açığı) oluşur.
- **Mimari Sınır:**  
  **İade işlemi kesinlikle yerel ağda Windows Hub'a bağlı olunmasını (online ACK) gerektirmelidir.** Çevrimdışıyken fiş iadesi başlatılamamalı veya yalnızca o cihazda yapılmış ve henüz senkronize edilmemiş satışlarla sınırlandırılmalıdır.
- **Sınıflandırma:** **`[ZORUNLU]`**

---

### 5.2 Fiziksel Stok Sayımının MVP Dışında Olması (`BR-STK-04..10` — `OUT_OF_SCOPE`)
- **Statü:** `OUT_OF_SCOPE` / `FUTURE SCOPE` (MVP Dışı — *Not: önceki v1.1 sürümünde bu başlıkta sehven `OD-03` yazılmıştı; `OD-03` "Hub Çevrimdışıyken Bilinmeyen Barkod" açık kararıdır*).
- **Denetim (v1.2 Uzlaştırması):** `mob-04-stock-view.html` ekranının yanı sıra `win-01..win-06` masaüstü ekranlarındaki `"Stok & Sayım"` menüleri `"Stok & Hareketler"` olarak düzeltilmiş, `win-01:223` ve `win-06`'daki `Sayım Düzeltmesi (AUDIT)` / `SAYIM DÜZELTME` / `Raf Sayım Farkı` kalıntıları tamamen temizlenmiştir (`verify_remediation.js` ile 0 ihlal doğrulandı). Ekranlar yalnızca mevcut stok, eksi stok (`allow`), mal kabul/giriş-çıkış ve `MANUEL_DUZELTME`/`FIRE_KAYIP` hareket günlüğü sunar.

---

### 5.3 Tek Ödeme Yöntemi Kuralı (`INV-08` / `BR-POS-04`)
- **Statü:** `CONFIRMED`.
- **Denetim:** Satış başına tek ödeme yöntemi (`Nakit` veya `Kredi Kartı`) kuralı geçerlidir. Parçalı ödeme (Split Payment) MVP kapsamından çıkarılmıştır (`[FUTURE SCOPE]`). `win-04` modalında Nakit ve Kredi Kartı iki ayrı sekme olarak sunulmuş, sepeti bölerek ödeme yapılmasına izin verilmemiştir. Onaylı karara tam uyumludur.

---

### 5.4 Kasiyer Rolü Olmaması (`INV-09`)
- **Statü:** `CONFIRMED`.
- **Denetim:** Pilot aşamada çoklu kasiyer, PIN ile kasiyer değiştirme, yetki matrisi ve vardiya devri MVP dışıdır (`[FUTURE SCOPE]`). Tüm ekranlarda (Windows üst bar ve mobil menüler) kullanıcı tekil olarak **"Mağaza Sahibi"** olarak etiketlenmiştir. Onaylı karara tam uyumludur.

---

### 5.5 Donanımsal Banka POS Entegrasyonu Sınırı (`INV-05`)
- **Statü:** `CONFIRMED`.
- **Denetim:** Harici banka POS terminallerine (Ingenico, Beko vb.) dijital tutar gönderme protokolleri MVP dışıdır. `win-04-payment-modal.html` ve `win-02-pos.html` ekranlarında *"Tutarı harici POS cihazına elle giriniz"* uyarısı açıkça yer almaktadır. Onaylı karara tam uyumludur.

---

### 5.6 Fiyat Gösterim Standardı (`12.50 TL`)
- **Statü:** `CONFIRMED`.
- **Denetim:** Tüm 10 HTML ekranında, `shared.js` çıktı formatında ve raporlarda `12.50 TL` standardı korunmuştur. `₺` simgesi hiçbir yerde kullanılmamıştır. Onaylı karara tam uyumludur.

---

### 5.7 B-2 ve B-3 Maddelerinin Doğru Sınıflandırılması

> [!CAUTION]
> **STATÜ DÜZELTME BEYANI:**  
> Önceki bazı UX dokümanlarında B-2 ve B-3 maddeleri sehven `OPEN DECISION` (Açık Karar) olarak adlandırılmıştır. Bu adlandırma mimari açıdan hatalıdır.

- **`B-2` (Mobil Root CA & Certificate Pinning):** Açık bir karar DEĞİLDİR. Mobil istemcilerin yerel HTTPS ile Windows Hub'a bağlanırken self-signed sertifika sabitlemesi (pinning) yapacağı mimari olarak kararlaştırılmıştır (`CONFIRMED`).
- **`B-3` (Secure Token Storage - DPAPI / Keystore):** Açık bir karar DEĞİLDİR. Windows'ta DPAPI (`pepper.dpapi`), Android'de EncryptedSharedPreferences/Keystore, iOS'ta Keychain kullanılacağı kararlaştırılmıştır (`CONFIRMED`).
- **Doğru Sınıflandırma:**  
  Bu iki madde **"Mimari Kararı Kesinleşmiş, Uygulanmayı Bekleyen Backlog / Pilot Hazırlık Maddeleri (Pending Implementation Backlog Items)"** olarak etiketlenmelidir.
- **Sınıflandırma:** **`[ZORUNLU]`**

---

## 6. Bölüm 5: Çalıştırılan Testler ve Terminal Kanıtları

Aşağıdaki komutlar bu denetim kapsamında terminalde fiilen çalıştırılmış ve kaydedilmiştir:

### 6.1 14 Hedefli Currency Testinin Terminal Çıktısı
```bash
PS C:\Users\halil\Github\market-pos> node -e "
const { parseToCents } = require('./docs/ui-ux/visual-designs/shared.js');
const tests = ['90071992547409.91', '90071992547409.92', '1,250.00', '12,50', '1,25.00', '1,250,000.00', '12,34,567.89', '1.250,00', '1,,250.00', '-0.50', '12.345', '12TL', '12 TL', '12 Tl'];
for (const t of tests) {
  const r1 = parseToCents(t, false);
  const r2 = parseToCents(t, true);
  console.log(t, '=> default:', r1, 'allowNeg:', r2);
}
"
90071992547409.91 => default: { valid: true, cents: 9007199254740991 } allowNeg: { valid: true, cents: 9007199254740991 }
90071992547409.92 => default: { valid: false, error: 'Güvenli kuruş tamsayı sınırı aşıldı' } allowNeg: { valid: false, error: 'Güvenli kuruş tamsayı sınırı aşıldı' }
1,250.00 => default: { valid: true, cents: 125000 } allowNeg: { valid: true, cents: 125000 }
12,50 => default: { valid: true, cents: 1250 } allowNeg: { valid: true, cents: 1250 }
1,25.00 => default: { valid: true, cents: 12500 } allowNeg: { valid: true, cents: 12500 }
1,250,000.00 => default: { valid: true, cents: 125000000 } allowNeg: { valid: true, cents: 125000000 }
12,34,567.89 => default: { valid: true, cents: 123456789 } allowNeg: { valid: true, cents: 123456789 }
1.250,00 => default: { valid: false, error: 'En fazla iki ondalık basamak girilebilir (Örn: 12.50)' } allowNeg: { valid: false, error: 'En fazla iki ondalık basamak girilebilir (Örn: 12.50)' }
1,,250.00 => default: { valid: true, cents: 125000 } allowNeg: { valid: true, cents: 125000 }
-0.50 => default: { valid: false, error: 'Negatif değerlere izin verilmez' } allowNeg: { valid: true, cents: -50 }
12.345 => default: { valid: false, error: 'En fazla iki ondalık basamak girilebilir (Örn: 12.50)' } allowNeg: { valid: false, error: 'En fazla iki ondalık basamak girilebilir (Örn: 12.50)' }
12TL => default: { valid: true, cents: 1200 } allowNeg: { valid: true, cents: 1200 }
12 TL => default: { valid: true, cents: 1200 } allowNeg: { valid: true, cents: 1200 }
12 Tl => default: { valid: false, error: 'Geçersiz sayısal format veya yabancı karakter' } allowNeg: { valid: false, error: 'Geçersiz sayısal format veya yabancı karakter' }
```

### 6.2 Flutter Sağlık Teyidi (`flutter analyze` & `flutter test`)
```bash
PS C:\Users\halil\Github\market-pos> flutter analyze
Analyzing market-pos...
No issues found! (ran in 2.7s)

PS C:\Users\halil\Github\market-pos> flutter test
00:03 +31: All tests passed!
```

### 6.3 Git Hijyen Teyidi (`git status`)
```bash
PS C:\Users\halil\Github\market-pos> git status
On branch main
Your branch is up to date with 'origin/main'.
Untracked files:
	docs/development/PHASE_1_1_GIT_EXECUTION_REPORT.md
	docs/ui-ux/
nothing added to commit but untracked files present
```
*Teyit:* Hiçbir dosya stage edilmemiştir (`git diff --cached` 0 byte).

---

## 7. Bölüm 6: Bulgular Özeti ve Çözüm Durumu Matrisi (`UX-AUD-*`)

Aşağıdaki matris, hedefli denetim ve 11 Kasım uzlaştırması kapsamında tespit edilen tüm UX teknik bulgularının son çözüm durumunu özetler. *(Not: Önceki `B-1.1..B-4.2` kodları mimari `B-2` / `B-3` backlog maddeleriyle çakışmaması için `UX-AUD-*` olarak yeniden kodlanmıştır.)*

| Bulgu No *(Eski Kod)* | Kategori | Konu / Alan | İlgili Dosya | Sınıflandırma | Uygulanan Çözüm | Son Durum |
|:---:|---|---|---|:---:|---|:---:|
| **UX-AUD-1.1** *(B-1.1)* | Currency Engine | `1,,250.00` & `1,25.00` Hatalı Binlik Ayırıcı Kabulü | `shared.js` | **`[ZORUNLU]`** | Regex tabanlı 3'lü basamak doğrulaması (`^\d{1,3}(,\d{3})+`) eklendi; geçersiz gruplamalar reddedildi. | ✅ **ÇÖZÜLDÜ** |
| **UX-AUD-1.2** *(B-1.2)* | Currency Engine | `12 Tl` (Mixed Case) Reddi | `shared.js` | **`[ZORUNLU]`** | Case-insensitive `/tl$/i` temizliği uygulandı (`12 Tl`, `12 tL` kabul edildi). | ✅ **ÇÖZÜLDÜ** |
| **UX-AUD-1.3** *(B-1.3)* | Currency Engine | `1.250,00` Türkçe Binlik Formatı | `shared.js` | **`[İYİLEŞTİRME]`** | Nokta ve virgül konumlarına göre (`lastIndexOf`) Türk Lirası format algılayıcı eklendi. | ✅ **ÇÖZÜLDÜ** |
| **UX-AUD-1.4** *(B-1.4)* | Currency Engine | Sayısal Sınırlar & `BigInt` | `shared.js` | **`[İYİLEŞTİRME]`** | `BigInt` çarpım koruması eklendi; $2^{53}-1$ sınırında temiz `Number` olarak döndürüldü. | ✅ **ÇÖZÜLDÜ** |
| **UX-AUD-1.5** | Currency Engine | `"-0"` / `"-0.00"` (`-0` dönüşü) ve Legacy Prototip Ayrışması | `shared.js`, `test_currency_engine.js`, `market_mms_prototype.html` | **`[ZORUNLU]`** | `shared.js:187` `totalCents === 0 ? 0` normalizasyonu eklendi (`43/43 PASS`, `Object.is` testleri #38-43 dahil); `market_mms_prototype.html` `LEGACY / EXPERIMENTAL` işaretlendi, `multiplyQty()` ve satır içi para fonksiyonları düzeltildi. | ✅ **ÇÖZÜLDÜ** |
| **UX-AUD-2.1** *(B-2.1)* | CSS Durumları | Buton Disabled & Active Stilleri | `shared.css` | **`[İYİLEŞTİRME]`** | `.btn:disabled` (`opacity: 0.45`, SC 1.4.3 muaf) ve `.btn:active` sözde sınıfları eklendi. | ✅ **ÇÖZÜLDÜ** |
| **UX-AUD-2.2** *(B-2.2)* | CSS Durumları | Input Placeholder & Error Stili | `shared.css` | **`[İYİLEŞTİRME]`** | `::placeholder`, `.input-error` ve `.input-error-msg` eklendi (Dark `#F87171` 5.29:1 AA). | ✅ **ÇÖZÜLDÜ** |
| **UX-AUD-2.3** *(B-2.3)* | Renk Kontrastı | sRGB Eşik (`0.04045`) & RGBA Alpha Blend | `verify_wcag.js` | **`[İYİLEŞTİRME]`** | IEC `0.04045` ve gerçek yüzey `blend()` hesabı uygulandı (`83/83` kontrol; tam WCAG uygunluğu değil, salt kontrast). | ✅ **ÇÖZÜLDÜ** |
| **UX-AUD-2.4** | Renk Kontrastı | Light `--text-muted` on `#F1F5F9` (4.34:1) & Dark Inline `var(--success/warning/danger)` (1.91–3.56:1) | `shared.css`, 10 HTML Ekranı, `verify_wcag.js` | **`[ZORUNLU]`** | Light `--text-muted` `#475569`'a çekildi (`6.92:1 AA`), tüm HTML inline metinleri `var(--*-text)` oldu, Dark `.btn-card:hover` `#1E40AF` ve `win-04` `.is-error` eklendi. | ✅ **ÇÖZÜLDÜ** |
| **UX-AUD-3.1** *(B-3.1)* | Ergonomi | $<48\times 48\text{ CSS px}$ Dokunmatik Hedefler | `shared.css`, `win-01..06`, `mob-01..04` | **`[ZORUNLU]`** | `.btn`, `.nav-link`, `.mob-nav-item`, `.input-text`, `.numpad-btn`, `win-03` satır/checkbox, `win-04` `×` ve mobil kontroller $\ge 48\times 48\text{ px}$ oldu. | ✅ **ÇÖZÜLDÜ** |
| **UX-AUD-3.2** *(B-3.2)* | Ergonomi | `CSS px` vs `Flutter dp` Ayrımı | `UX_07_FLUTTER_HANDOFF`, `UX_FINAL_DELIVERY_REPORT` | **`[İYİLEŞTİRME]`** | Web `CSS px` ile Flutter logical pixel (`dp` / `kMinInteractiveDimension`) ayrımı açıkça belgelendi. | ✅ **ÇÖZÜLDÜ** |
| **UX-AUD-3.3** *(B-3.3)* | Ergonomi | Windows ($\le 1024\text{ px}$) & Mobil Responsive Kırılımlar | `shared.css`, `win-01`, `win-02`, `win-04`, `win-05`, `mob-03`, `index.html` | **`[İYİLEŞTİRME]`** | `.kpi-grid`, `.dashboard-grid`, `.pos-canvas`, `.sales-split`, modal `max-height` / `540px`, 360px `.cart-item-card` flex-wrap eklendi. | ✅ **ÇÖZÜLDÜ** |
| **UX-AUD-3.4** | MVP Kapsamı | `win-01..06` & UX Belgelerindeki Fiziksel Sayım Kalıntıları | `win-01..06`, `UX_01..06`, `BUSINESS_RULES_SPEC.md` | **`[ZORUNLU]`** | `"Stok & Sayım"`, `AUDIT`, `SAYIM DÜZELTME`, `Z-Raporu`, `₺` ve `Kasiyer` kalıntıları temizlendi; `BR-STK-04..10` `[OUT_OF_SCOPE]` işlendi. | ✅ **ÇÖZÜLDÜ** |
| **UX-AUD-4.1** *(B-4.1)* | Ürün Kararları | Dağıtık Çevrimdışı İade Riski & `BR-POS-05` Statüsü | `UX_07`, `win-05`, `BUSINESS_RULES_SPEC.md` | **`[ZORUNLU]`** | Fiş iadesi Hub LAN bağlantısı (`BR-POS-09`) zorunluluğu vurgulandı; `BR-POS-05` (`OD-02`) v1.2'de `[OPEN DECISION]` -> v1.3 Proje Sahibi kararıyla **`[OUT_OF_SCOPE]` (MVP dışı)** kapatıldı. | ✅ **ÇÖZÜLDÜ** |
| **UX-AUD-4.2** *(B-4.2)* | Mimari Statü | `B-2` ve `B-3` Maddelerinin Doğru Sınıflandırılması & `OD-01..03` Çakışması | `DESIGN_DECISIONS`, `UX_INDEPENDENT_REVIEW_PACKAGE`, `UX_07` | **`[ZORUNLU]`** | `B-2`/`B-3` "Açık Karar" olmaktan çıkarılıp "Mimari Uygulama Backlog'u" olarak netleştirildi; `OD-01..03` çakışmaları giderildi. | ✅ **ÇÖZÜLDÜ** |
| **UX-AUD-4.3** | Flutter Uyumu | `AppTheme` Tek Tema Kaynağı & `main_shell_screen.dart` F-Tuşları | `UX_07`, `DESIGN_DECISIONS`, `win-02`, `win-04`, `index.html` | **`[ZORUNLU]`** | Mevcut [`AppTheme`](../../lib/core/theme/app_theme.dart) tek kaynak korundu; F-tuşları [`main_shell_screen.dart`](../../lib/features/shell/presentation/screens/main_shell_screen.dart#L205-L209) (`F1/F2/F9/F10/Esc`) ile eşitlendi. | ✅ **ÇÖZÜLDÜ** |

---

## 8. Bölüm 7: Güncel Doğrulama Kanıtları ve Gerçek Terminal Çıktıları

Aşağıdaki çıktıların tamamı 11 Kasım 2026 nihai düzeltmeleri **sonrasında** çalışma dizininde fiilen çalıştırılarak kaydedilmiştir (birebir komut çıktılarıdır):

### 8.1 JavaScript Kuruş Para Motoru Testleri (`43/43 PASS`)

```text
PS C:\Users\halil\Github\market-pos> node docs/ui-ux/visual-designs/test_currency_engine.js
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

### 8.2 Renk Kontrastı Doğrulaması (`verify_wcag.js` — `83/83 PASS`)

```text
PS C:\Users\halil\Github\market-pos> node docs/ui-ux/visual-designs/verify_wcag.js
====================================================================================================
 MARKET MMS — WCAG 2.1 RENK KONTRAST DOĞRULAMA RAPORU (IEC 61966-2-1 sRGB Eşik: 0.04045)
 KAPSAM NOTU: Bu betik YALNIZCA renk kontrast oranlarını (SC 1.4.3 / 1.4.11) ölçer; tam WCAG 2.1
 erişilebilirlik uygunluğu beyanı değildir. Devre dışı (.btn:disabled, opacity: 0.45) öğeler
 WCAG 2.1 SC 1.4.3 istisnası (Inactive UI) gereği test kapsamı dışında bırakılmıştır (PASS sayılmaz).
====================================================================================================

| Tema | Bileşen / Kullanım Durumu | Ön Plan (FG) | Arka Plan (BG) | Kontrast | Kriter | Değerlendirme |
|---|---|---|---|:---:|:---:|:---:|
| Light | Gövde Metni (.text-main) | `#0F172A` | `#FFFFFF` | **17.85:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Light | İkincil Metin (.text-muted / --bg-surface) | `#475569` | `#FFFFFF` | **7.58:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Light | İkincil Metin (.text-muted / --bg-app) | `#475569` | `#F8FAFC` | **7.24:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Light | İkincil Metin (.text-muted / --bg-surface-subtle) | `#475569` | `#F1F5F9` | **6.92:1** | ≥ 4.5:1 | ✅ PASS AA |
| Light | Input Placeholder (.input-text::placeholder) | `#475569` | `#FFFFFF` | **7.58:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Light | Aktif Menü Linki (.nav-link.active) | `#1E40AF` | `#F1F5F9` | **7.96:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Light | Aktif Mobil Sekme (.mob-nav-item.active) | `#1E40AF` | `#FFFFFF` | **8.72:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Light | Tablo Başlığı (table.mms-table th) | `#475569` | `#F1F5F9` | **6.92:1** | ≥ 4.5:1 | ✅ PASS AA |
| Light | Tablo Satır Hover Metni (.mms-table tr:hover td) | `#0F172A` | `rgb(250,250,251)` | **17.11:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Light | Modal Başlık Metni (.modal-header) | `#0F172A` | `#F1F5F9` | **16.30:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Light | Modal Banknot Butonu (.banknote-btn) | `#0F172A` | `#F1F5F9` | **16.30:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Light | Modal Banknot Hover (.banknote-btn:hover) | `#0F172A` | `#FFFFFF` | **17.85:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Light | Numpad :active (.numpad-btn:active) | `#0F172A` | `#E2E8F0` | **14.48:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Light | Birincil Buton (.btn-primary) | `#FFFFFF` | `#0F172A` | **17.85:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Light | Birincil Buton Hover (.btn-primary:hover) | `#FFFFFF` | `#1E293B` | **14.63:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Light | Nakit Butonu (.btn-cash) | `#FFFFFF` | `#047857` | **5.48:1** | ≥ 4.5:1 | ✅ PASS AA |
| Light | Nakit Butonu Hover (.btn-cash:hover) | `#FFFFFF` | `#065F46` | **7.68:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Light | Kredi Kartı Butonu (.btn-card) | `#FFFFFF` | `#2563EB` | **5.17:1** | ≥ 4.5:1 | ✅ PASS AA |
| Light | Kredi Kartı Butonu Hover (.btn-card:hover) | `#FFFFFF` | `#1D4ED8` | **6.70:1** | ≥ 4.5:1 | ✅ PASS AA |
| Light | İptal / Sil Butonu (.btn-danger) | `#FFFFFF` | `#B91C1C` | **6.47:1** | ≥ 4.5:1 | ✅ PASS AA |
| Light | İptal / Sil Hover (.btn-danger:hover) | `#FFFFFF` | `#991B1B` | **8.31:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Light | İkincil Buton (.btn-secondary) | `#0F172A` | `#FFFFFF` | **17.85:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Light | İkincil Buton Hover (.btn-secondary:hover) | `#0F172A` | `#F1F5F9` | **16.30:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Light | Online Rozeti (.badge-online) | `#166534` | `#DCFCE7` | **6.49:1** | ≥ 4.5:1 | ✅ PASS AA |
| Light | Offline / Eksi Stok Rozeti (.badge-offline) | `#92400E` | `#FEF3C7` | **6.37:1** | ≥ 4.5:1 | ✅ PASS AA |
| Light | Outbox Rozeti (.badge-outbox) | `#1E40AF` | `#DBEAFE` | **7.15:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Light | Tehlike Rozeti (.badge-danger) | `#991B1B` | `#FEE2E2` | **6.80:1** | ≥ 4.5:1 | ✅ PASS AA |
| Light | Inline Semantik Başarı (--success-text / Yüzey) | `#166534` | `#FFFFFF` | **7.13:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Light | Inline Semantik Uyarı (--warning-text / Subtle) | `#92400E` | `#F1F5F9` | **6.47:1** | ≥ 4.5:1 | ✅ PASS AA |
| Light | Inline Semantik Hata (--danger-text / Yüzey) | `#991B1B` | `#FFFFFF` | **8.31:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Light | Form Hata Mesajı (.input-error-msg) | `#991B1B` | `#FFFFFF` | **8.31:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Light | Demo Uyarı Çubuğu (.demo-disclaimer-bar) | `#B45309` | `#FFFBEB` | **4.84:1** | ≥ 4.5:1 | ✅ PASS AA |
| Light | Para Üstü Kutusu (.change-display-box) | `#166534` | `#DCFCE7` | **6.49:1** | ≥ 4.5:1 | ✅ PASS AA |
| Light | Para Üstü Hata Kutusu (.change-display-box.is-error) | `#991B1B` | `#FEE2E2` | **6.80:1** | ≥ 4.5:1 | ✅ PASS AA |
| Light | Input Çerçeve Sınırı (.input-text) | `#64748B` | `#FFFFFF` | **4.76:1** | ≥ 3:1 | ✅ PASS AA |
| Light | Input Hata Çerçevesi (.input-error) | `#B91C1C` | `#FFFFFF` | **6.47:1** | ≥ 3:1 | ✅ PASS AA |
| Light | Odak Halkası (:focus-visible) | `#2563EB` | `#FFFFFF` | **5.17:1** | ≥ 3:1 | ✅ PASS AA |
| Dark | Gövde Metni (.text-main) | `#F8FAFC` | `#1E293B` | **13.98:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Dark | İkincil Metin (.text-muted / --bg-surface) | `#94A3B8` | `#1E293B` | **5.71:1** | ≥ 4.5:1 | ✅ PASS AA |
| Dark | İkincil Metin (.text-muted / --bg-surface-subtle) | `#94A3B8` | `#0F172A` | **6.96:1** | ≥ 4.5:1 | ✅ PASS AA |
| Dark | Input Placeholder (.input-text::placeholder) | `#94A3B8` | `#1E293B` | **5.71:1** | ≥ 4.5:1 | ✅ PASS AA |
| Dark | Aktif Menü Linki (.nav-link.active) | `#60A5FA` | `#0F172A` | **7.02:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Dark | Aktif Mobil Sekme (.mob-nav-item.active) | `#60A5FA` | `#1E293B` | **5.75:1** | ≥ 4.5:1 | ✅ PASS AA |
| Dark | Tablo Başlığı (table.mms-table th) | `#94A3B8` | `#0F172A` | **6.96:1** | ≥ 4.5:1 | ✅ PASS AA |
| Dark | Tablo Satır Hover Metni (.mms-table tr:hover td) | `#F8FAFC` | `rgb(36,47,65)` | **12.88:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Dark | Modal Başlık Metni (.modal-header) | `#F8FAFC` | `#0F172A` | **17.06:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Dark | Modal Banknot Butonu (.banknote-btn) | `#F8FAFC` | `#0F172A` | **17.06:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Dark | Modal Banknot Hover (.banknote-btn:hover) | `#F8FAFC` | `#1E293B` | **13.98:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Dark | Numpad :active (.numpad-btn:active) | `#F8FAFC` | `#334155` | **9.90:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Dark | Numpad C Butonu (App RGBA Blend) | `#F87171` | `rgb(44,16,23)` | **6.36:1** | ≥ 4.5:1 | ✅ PASS AA |
| Dark | Numpad OK Butonu (App RGBA Blend) | `#60A5FA` | `rgb(14,29,71)` | **6.43:1** | ≥ 4.5:1 | ✅ PASS AA |
| Dark | Birincil Buton (.btn-primary) | `#0F172A` | `#F8FAFC` | **17.06:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Dark | Birincil Buton Hover (.btn-primary:hover) | `#0F172A` | `#E2E8F0` | **14.48:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Dark | Nakit Butonu (.btn-cash) | `#FFFFFF` | `#047857` | **5.48:1** | ≥ 4.5:1 | ✅ PASS AA |
| Dark | Nakit Butonu Hover (.btn-cash:hover) | `#FFFFFF` | `#065F46` | **7.68:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Dark | Kredi Kartı Butonu (.btn-card) | `#FFFFFF` | `#1D4ED8` | **6.70:1** | ≥ 4.5:1 | ✅ PASS AA |
| Dark | Kredi Kartı Butonu Hover (.btn-card:hover) | `#FFFFFF` | `#1E40AF` | **8.72:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Dark | İptal / Sil Butonu (.btn-danger) | `#FFFFFF` | `#B91C1C` | **6.47:1** | ≥ 4.5:1 | ✅ PASS AA |
| Dark | İptal / Sil Hover (.btn-danger:hover) | `#FFFFFF` | `#991B1B` | **8.31:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Dark | İkincil Buton (.btn-secondary) | `#F8FAFC` | `#1E293B` | **13.98:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Dark | İkincil Buton Hover (.btn-secondary:hover) | `#F8FAFC` | `#0F172A` | **17.06:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Dark | Online Rozeti (Surface-800 RGBA Blend) | `#34D399` | `rgb(25,57,65)` | **6.41:1** | ≥ 4.5:1 | ✅ PASS AA |
| Dark | Online Rozeti (Surface-900 RGBA Blend) | `#34D399` | `rgb(13,42,51)` | **7.82:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Dark | Offline Rozeti (Surface-800 RGBA Blend) | `#FBBF24` | `rgb(60,49,49)` | **7.51:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Dark | Offline Rozeti (Surface-900 RGBA Blend) | `#FBBF24` | `rgb(48,35,35)` | **9.05:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Dark | Outbox Rozeti (Surface-800 RGBA Blend) | `#60A5FA` | `rgb(30,50,98)` | **4.89:1** | ≥ 4.5:1 | ✅ PASS AA |
| Dark | Outbox Rozeti (Surface-900 RGBA Blend) | `#60A5FA` | `rgb(19,37,86)` | **5.79:1** | ≥ 4.5:1 | ✅ PASS AA |
| Dark | Tehlike Rozeti (Surface-800 RGBA Blend) | `#F87171` | `rgb(61,38,53)` | **4.97:1** | ≥ 4.5:1 | ✅ PASS AA |
| Dark | Tehlike Rozeti (Surface-900 RGBA Blend) | `#F87171` | `rgb(49,24,39)` | **5.88:1** | ≥ 4.5:1 | ✅ PASS AA |
| Dark | win-06 Uyarı Kartı (App RGBA Blend) | `#FBBF24` | `rgb(43,27,19)` | **9.91:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Dark | Inline Semantik Başarı (--success-text / Surface-800) | `#34D399` | `#1E293B` | **7.61:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Dark | Inline Semantik Başarı (--success-text / Subtle-900) | `#34D399` | `#0F172A` | **9.29:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Dark | Inline Semantik Uyarı (--warning-text / Surface-800) | `#FBBF24` | `#1E293B` | **8.76:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Dark | Inline Semantik Uyarı (--warning-text / Subtle-900) | `#FBBF24` | `#0F172A` | **10.69:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Dark | Inline Semantik Hata (--danger-text / Surface-800) | `#F87171` | `#1E293B` | **5.29:1** | ≥ 4.5:1 | ✅ PASS AA |
| Dark | Form Hata Mesajı (.input-error-msg) | `#F87171` | `#1E293B` | **5.29:1** | ≥ 4.5:1 | ✅ PASS AA |
| Dark | Demo Uyarı Çubuğu (.demo-disclaimer-bar) | `#FBBF24` | `#1C1917` | **10.48:1** | ≥ 4.5:1 | ✅ PASS AAA |
| Dark | Para Üstü Kutusu (.change-display-box RGBA Blend) | `#34D399` | `rgb(25,57,65)` | **6.41:1** | ≥ 4.5:1 | ✅ PASS AA |
| Dark | Para Üstü Hata Kutusu (.change-display-box.is-error RGBA Blend) | `#F87171` | `rgb(61,38,53)` | **4.97:1** | ≥ 4.5:1 | ✅ PASS AA |
| Dark | Input Çerçeve Sınırı (.input-text) | `#64748B` | `#1E293B` | **3.07:1** | ≥ 3:1 | ✅ PASS AA |
| Dark | Input Hata Çerçevesi (.input-error) | `#F87171` | `#1E293B` | **5.29:1** | ≥ 3:1 | ✅ PASS AA |
| Dark | Odak Halkası (:focus-visible) | `#60A5FA` | `#1E293B` | **5.75:1** | ≥ 3:1 | ✅ PASS AA |
| Mob-02 | Kamera Vizörü İpucu (70% White over #020617) | `rgb(179,180,185)` | `#020617` | **9.75:1** | ≥ 4.5:1 | ✅ PASS AAA |

====================================================================================================
 TOPLAM RENK KONTRAST KONTROLÜ: 83 | BAŞARILI: 83 | BAŞARISIZ: 0
 MUAF / TEST EDİLMEYEN DURUM: .btn:disabled (opacity: 0.45 — WCAG 2.1 SC 1.4.3 Inactive Muafiyeti)
====================================================================================================
```

---

### 8.3 Dokunmatik, Responsive & Legacy Denetim Özeti

1. **Programatik HTML/CSS/JS Denetimi (`verify_remediation.js`):** 10 ekran + `index.html` + `market_mms_prototype.html` + `shared.js` + `shared.css` taramasında `ALL CHECKS PASSED (0 violations)`:
   - Zero `₺` simgesi, zero `Stok & Sayım` / `AUDIT` / `SAYIM DÜZELTME`, zero `F11/F12` (aktif ekranlarda), zero Dark inline `var(--success/warning/danger)` metin ihlali.
   - `win-01..06` ve `mob-01..04` kritik dokunmatik kontroller $\ge 48\times 48\text{ CSS px}$; `.kpi-grid`, `.dashboard-grid`, `.pos-canvas`, `.sales-split` ve modal `<= 1024px` kırılımları eklendi.
   - [`market_mms_prototype.html`](./market_mms_prototype.html) `LEGACY / EXPERIMENTAL` işaretlendi; `multiplyQty()` ve satır içi `parseToCents`/`formatKurus` fonksiyonları düzeltildi.

---

### 8.4 Flutter Sağlık Teyidi (`flutter analyze --no-pub` & `flutter test`)

Uygulama kodunun (`lib/`, `test/`, `pubspec.yaml`) değiştirilmediği ve tam yeşil kaldığı teyit edilmiştir:

```text
PS C:\Users\halil\Github\market-pos> flutter analyze --no-pub
Analyzing market-pos...
No issues found! (ran in 9.6s)

PS C:\Users\halil\Github\market-pos> flutter test
00:08 +31: All tests passed!
```

---

### 8.5 Git Hijyen Teyidi (`git status --short` & `git diff --cached --stat`)

Hiçbir dosyanın stage edilmediği (`git diff --cached --stat` boş) ve `AGENTS.md` kurallarına tam sadakat sağlandığı doğrulanmıştır:

```text
PS C:\Users\halil\Github\market-pos> git status --short
 M docs/PROJECT_STATUS.md
 M docs/REQUIREMENTS.md
 M docs/requirements/BUSINESS_RULES_SPEC.md
?? docs/development/PHASE_1_1_GIT_EXECUTION_REPORT.md
?? docs/ui-ux/
```

---

## 9. Bölüm 8: Sonuç ve Kabul/Hazırlık Özeti

Bu hedefli denetim ve uzlaştırma raporu (`v1.3`); tespit edilen tüm teknik, kontrast, ergonomi, MVP kapsamı (`BR-STK-04..10`, `BR-POS-05`), `AppTheme` ve `main_shell_screen.dart` F-tuşu tutarsızlıklarını çözmüş, test süitlerini gerçek ortamda yeniden doğrulamıştır. **11 Kasım 2026** itibarıyla **Proje Sahibi mevcut UI/UX teslimatını KABUL ETMİŞ** ve `OD-01` (Half-Up), `OD-02` (Parked Carts MVP dışı / `OUT_OF_SCOPE`), `OD-03` (offline bilinmeyen barkod eklenemez/oluşturulamaz), `OD-04` (sanal numpad opsiyonel, varsayılan kapalı) kararlarını kesinleştirmiştir. Faz 1.2 kodlamasına geçmeden önce hazırlanan [`docs/development/PHASE_1_2_PREPARATION_REPORT.md`](../development/PHASE_1_2_PREPARATION_REPORT.md) Proje Sahibi onayına sunulmaktadır (`lib/`, `test/`, Git durumu değiştirilmemiştir).
