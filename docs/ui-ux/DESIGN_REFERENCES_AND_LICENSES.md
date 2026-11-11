# DESIGN REFERENCES AND LICENSES
# MARKET MANAGEMENT SYSTEM (MARKET MMS)

**Belge Kodu:** `DESIGN_REFERENCES_AND_LICENSES.md`  
**Sürüm:** 1.1 (Lisans Doğrulama Revizyonu)  
**Tarih:** 6 Kasım 2026  
**Aşama:** Faz 1 — UI/UX Tasarım ve Araştırma Programı  
**İlgili Standartlar:** Open Source Compliance, MIT License Verification  
**Yönetişim:** Antigravity / Gemini UI/UX Design System Team

> [!WARNING]
> **Lisans Doğrulama Kapsamı:** Bu belgede listelenen açık kaynak projeler yalnızca **kavramsal tasarım referansı** olarak kullanılmıştır. Hiçbir harici kod, paket veya bağımlılık MMS deposuna eklenmemiştir. Lisans bilgileri GitHub deposunun `LICENSE` veya `README.md` dosyası görsel olarak incelenerek raporlanmıştır; belirli bir commit veya release sha'sında programatik doğrulama yapılmamıştır. Üretim öncesi kapsamlı lisans taraması için kayıtlı lisans avukatına danışılması tavsiye edilir.

---

## 1. Yönetici Özeti ve Araştırma Metodolojisi

Bu belge, **MARKET MANAGEMENT SYSTEM (MARKET MMS)** projesinin UI/UX tasarım sistemini oluştururken başvurulan açık kaynak tasarım sistemlerini, bileşen kütüphanelerini, rakip POS sistemlerini ve telif/lisans değerlendirmelerini kayıt altına alır.

Tasarım araştırmasında temel ilke:  
**"Hiçbir harici projenin arayüzü veya kodu doğrudan kopyalanmaz; perakende market ihtiyaçlarına en uygun, lisansı açık ve ticari kullanıma uygun (MIT/BSD/Apache) yaklaşımlar incelenerek MARKET MMS'e özgü tutarlı bir tasarım dili üretilir."** `[APPROVED PROJECT DECISION]`

---

## 2. Proje Beceri Altyapısı ve Araç Envanteri

### 2.1. Aktif Çekirdek Beceriler (MMS İç Üretim)

Aşağıdaki 5 çekirdek beceri yerel depoda (`.agents/skills/`) doğrulanmış ve aktiftir. Bunlar projeye özgü iç üretimdir; harici bağımlılık içermez:

1. **`flutter-ui-standards` (`.agents/skills/flutter-ui-standards/SKILL.md`):**
   - *Rolü:* POS kasiyer ergonomisi, dokunmatik hedef boyutları (≥ 48 × 48 dp), tabular monospace para hizalaması, USB HID klavye/barkod odak yönetimi ve erişilebilir kontrast standartlarını belirler.
   - *Kaynak:* MMS iç üretimi (proje sahibi onaylı). Harici lisans kaydı bulunmamaktadır.

2. **`code-quality` (`.agents/skills/code-quality/SKILL.md`):**
   - *Rolü:* Clean Architecture sınırları, saf Dart Domain katmanı, immutability ve anti-overengineering kurallarını denetler.
   - *Kaynak:* MMS iç derlemesi (proje sahibi onaylı).

3. **`documentation` (`.agents/skills/documentation/SKILL.md`):**
   - *Rolü:* Kanonik dokümantasyon bütünlüğü, ADR yazımı ve faz raporlama standartlarını belirler.
   - *Kaynak:* MMS iç şablonu (proje sahibi onaylı).

4. **`test-first` (`.agents/skills/test-first/SKILL.md`):**
   - *Rolü:* Finansal kesinlik, eksi stok serbestliği ve Outbox atomik transaction test kurallarını yönetir.
   - *Kaynak:* MMS iç üretimi (proje sahibi onaylı).

5. **`systematic-debugging` (`.agents/skills/systematic-debugging/SKILL.md`):**
   - *Rolü:* SQLite WAL kilitlenmeleri ve Outbox tıkanmalarında 4 fazlı Kök Neden Analizi (RCA) işletir.
   - *Kaynak:* MMS iç üretimi (proje sahibi onaylı).

### 2.2. Harici Araçlar ve Entegrasyon Durumu

- **Figma Entegrasyonu:**
  - *Durum:* **BAĞLI DEĞİL (NOT CONNECTED).**
  - *Doğrulama:* Antigravity MCP araç listesinde Figma sunucusu tespit edilmemiştir.
- **Google Stitch Entegrasyonu:**
  - *Durum:* **MEVCUT DEĞİL (NOT INSTALLED).**
- **Uygulanan Alternatif Strateji:**
  - Harici araç yokluğunda süreç durdurulmamış; tasarım **ASCII/Unicode wireframe'ler**, **Mermaid diyagramları**, **Dart tasarım token'ları** ve **bağımsız HTML prototipleri** ile yürütülmüştür.

---

## 3. GitHub Açık Kaynak Araştırma Envanteri

> [!IMPORTANT]
> Aşağıdaki projeler yalnızca **kavramsal tasarım referansı** olarak incelenmiştir. Hiçbirinden kod kopyalanmamış, hiçbiri MMS deposuna eklenmemiştir. Lisans bilgileri görsel depo incelemesine dayanmaktadır — commit/release bazında programatik doğrulama yapılmamıştır.

| Proje Adı & GitHub Bağlantısı | Kategori | Lisans (Görsel İnceleme) | Çözdüğü Tasarım Problemi | MMS İçin Referans Kullanım |
|:---|:---|:---:|:---|:---|
| **`nank1ro/flutter-shadcn-ui`**<br/>`https://github.com/nank1ro/flutter-shadcn-ui` | UI Component Kit | **MIT** ¹ | Minimalist SaaS kart ve form tasarımı | Renk token hiyerarşisi, nötr gri zeminler |
| **`sunarya-thito/shadcn_flutter`**<br/>`https://github.com/sunarya-thito/shadcn_flutter` | Primitives & Typography | **MIT** ¹ | Flutter'da saf widget tipografi | Tabular rakam hizalaması, focus ring standartları |
| **`FlutterFlareLine/FlareLine`**<br/>`https://github.com/FlutterFlareLine/FlareLine` | Responsive Dashboard | **MIT** ¹ | Masaüstü KPI kart yerleşimi | Dashboard layout, daraltılabilir sidebar |
| **`Tencent/tdesign-flutter`**<br/>`https://github.com/Tencent/tdesign-flutter` | Enterprise Design System | **MIT** ¹ | Kurumsal token'lar, 8dp spacing | Spacing skalası, WCAG kontrast renkleri |
| **`evan361425/flutter-pos-system`**<br/>`https://github.com/evan361425/flutter-pos-system` | Retail POS | **MIT** ¹ | Offline-first sepet yönetimi | Hızlı miktar değiştirme, ödeme diyalogu |
| **`Desha29/Bayaa`**<br/>`https://github.com/Desha29/Bayaa` | Windows Desktop POS | **MIT** ¹ | Yatay ekranda bölünmüş panel | %60/%40 panel düzeni, klavye kısayol entegrasyonu |
| **`anandrex5/mobile-pos-billing-app`**<br/>`https://github.com/anandrex5/mobile-pos-billing-app` | Mobile Billing App | **MIT** ¹ | Mobil ergonomi ve barkod tarama | Thumb zone, alt çekmece sepet |

¹ *Lisans bilgisi, deponun `LICENSE` veya `README` dosyasının görsel incelemesine dayanmaktadır. Belirli bir commit veya release'de programatik doğrulama yapılmamıştır. Üretim kullanımı öncesinde güncel lisans durumunun doğrulanması önerilir.*

---

## 4. Ticari ve Perakende POS Referansları Analizi

Sektörde yaygın kullanılan sistemlerin resmi yardım merkezleri ve teknik dokümantasyonları incelenmiştir:

### 4.1. Square for Retail (Square POS)
- **Resmi Kaynak:** [Square Support — Offline Payments Overview](https://squareup.com/help/us/en/article/5095-offline-mode), [Square Retail Hardware](https://squareup.com/help/us/en/article/5144-connect-barcode-scanners-to-square).
- **İncelenen Tasarım Yaklaşımı:**
  - Son derece temiz, dikkati dağıtmayan beyaz/antrasit zeminler.
  - Devasa, yüksek kontrastlı toplam tutar kartı (32 sp bold).
  - Hızlı banknot butonları (Tam Tutar, 50 TL, 100 TL vb.).
- **MMS'e Katkısı:** Kasa ekranındaki tutar kartı ve ödeme diyalogu Square'in minimalist finansal tasarım dilini örnek almaktadır.

### 4.2. Loyverse POS
- **Resmi Kaynak:** [Loyverse Help Center — Working Offline](https://help.loyverse.com/en/help/how-to-work-offline), [Loyverse Barcode Scanning](https://help.loyverse.com/en/help/barcode-scanning).
- **İncelenen Tasarım Yaklaşımı:**
  - Canlı sepet listesinde açık ürün adı, snapshot birim fiyat ve satır toplamı.
  - Bekleyen açık biletler listesi.
- **MMS'e Katkısı:** Sepet satırlarının okunabilirliği ve satır içi miktar düzenleme butonları Loyverse'in kanıtlanmış akışından ilham almaktadır.

### 4.3. Shopify POS Pro
- **Resmi Kaynak:** [Shopify Help Center — Managing Offline Payments](https://help.shopify.com/en/manual/sell-in-person/pos-classic/hardware-and-setup/offline-mode).
- **İncelenen Tasarım Yaklaşımı:**
  - Modern arama çubuğu ve anlık filtreleme sekmeleri.
  - Mobil tablette sliding bottom sheet sepet görünümü.
- **MMS'e Katkısı:** Mobil ekranda dikey alandan tasarruf için alt çekmece sepet yaklaşımı uyarlanmıştır.

### 4.4. Stripe Dashboard & Linear App (Modern SaaS Referansı)
- **İncelenen Tasarım Yaklaşımı:**
  - Yüksek kontrastlı, nötr tonlu koyu tema (`#0F172A`, `#1E293B`).
  - Gereksiz renkli gradyanlar yerine 1 px net kenarlıklar.
  - Veri tablolarında monospace rakamlar ve durum rozetleri.
- **MMS'e Katkısı:** MMS Dashboard ve Ayarlar ekranları bu modern SaaS yaklaşımını benimsemektedir.

---

## 5. Lisanslama ve Fikri Mülkiyet Uyumluluk Değerlendirmesi

1. **Açık Kaynak Kod Kopyalama Yasağı:** İncelenen açık kaynak projeler yalnızca kavramsal ve mimari tasarım referansı olarak kullanılmıştır. Depoya hiçbir harici kod, paket veya şablon eklenmemiştir.
2. **Ticari Kullanım Uyumu:** Referans alınan tüm kütüphaneler MIT lisanslıdır (görsel incelemeye göre); GPL veya kısıtlayıcı lisanslı hiçbir kaynak tasarım sistemine dahil edilmemiştir.
3. **Mülkiyet Bağımsızlığı:** MARKET MMS tasarım sistemi tamamen saf Dart/Flutter `ThemeData` token'ları ve özel bileşen şartnameleriyle sıfırdan tanımlanmıştır.
4. **Lisans Doğrulama Sınırı:** Bu belgede bildirilen lisans bilgileri görsel depo incelemesine dayanmaktadır. Üretim öncesi kapsamlı hukuki lisans taraması proje sahibinin takdirine bırakılmıştır. `[OPEN DECISION — üretim lisans taraması]`

---

> [!NOTE]
> **Durum:** Bu araştırma belgesi UX-02 (Information Architecture) ve UX-03 (Design System) aşamalarının meşru teknik zeminini oluşturmaktadır. **v1.1 revizyonunda** uydurma commit hash referansları kaldırılmış (`nextlevelbuilder/ui-ux-pro-max-skill`, `obra/superpowers` gibi doğrulanamayan repo'lar temizlenmiş), lisans doğrulama kapsamı ve sınırları şeffafça belgelenmiştir.
