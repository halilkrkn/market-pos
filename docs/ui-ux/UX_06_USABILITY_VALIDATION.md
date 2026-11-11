# UX_06_USABILITY_VALIDATION.md — MARKET MMS KULLANILABİLİRLİK DEĞERLENDİRMESİ
# Market Management System (Market MMS) — Usability Heuristics Evaluation, WCAG Audit & Validation Methodology

- **Doküman Versiyonu:** v1.2 (11 Kasım 2026 Uzlaştırma Revizyonu)
- **Revizyon Notu:** v1.1 kurgusal metodoloji düzeltmelerini korur. v1.2 uzlaştırmasıyla: `12.50 TL` formatına ve `Mağaza Sahibi (INV-09)` terminolojisine uyarlandı, MVP dışı `Z-Raporu` ve `Mobil stok sayımı` senaryoları çıkarıldı, renk kontrastı bölümü güncel [`shared.css`](./visual-designs/shared.css) / [`verify_wcag.js`](./visual-designs/verify_wcag.js) (83 kontrol) ile eşitlendi ve pilot saha testi faz referansı `ROADMAP.md` uyumlu olarak **Faz 7 (Pilot Hazırlık & Saha Doğrulaması)** olarak düzeltildi.
- **Bağlayıcı Temel:** [`AGENTS.md`](../../AGENTS.md), [`UX_03_DESIGN_SYSTEM.md`](./UX_03_DESIGN_SYSTEM.md), [`DESIGN_DECISIONS.md`](./DESIGN_DECISIONS.md)

---

## 1. Metodoloji ve Kapsamın Tanımlanması

> [!IMPORTANT]
> **Bu belgede yapılan tüm değerlendirmeler uzman sezgisel analizidir (Expert Heuristic Evaluation).** Gerçek kullanıcılarla yapılmış gözetimli kullanılabilirlik testi (moderated usability test) veya alan araştırması (field study) bu aşamada gerçekleştirilmemiştir. Gerçek kasiyer davranışı, hata oranları ve görev tamamlama süreleri ancak pilot mağaza kurulumunda ölçülebilir.

| Değerlendirme Türü | Bu Belgede Yapıldı mı? |
|---|---|
| Uzman Sezgisel Değerlendirme (Heuristic Eval.) | ✅ Evet — tasarım şartnamesi üzerinde |
| WCAG Kontrast Hesaplaması | ✅ Evet — matematiksel formülle, bkz. UX_03 |
| İnteraktif Prototip Üzerinde Test | ✅ Evet — HTML prototipi (tasarım demosu) |
| Gerçek Kullanıcı Testi | ❌ Hayır — pilot aşamaya ertelenmiştir |
| Alan / Saha Araştırması | ❌ Hayır — pilot aşamaya ertelenmiştir |
| Gerçek TCT Ölçümü | ❌ Hayır — hedefler ve hipotezler sunulmuştur |

---

## 2. Nielsen Norman 10 Usability Heuristics — Uzman Değerlendirmesi

Değerlendirme; tasarım şartnameleri (`UX_02`, `UX_03`, `UX_04`) ve etkileşimli prototip (`market_mms_prototype.html`) üzerinde gerçekleştirilmiştir. Puanlama subjektiftir; gerçek kullanıcı testi ile doğrulanması gerekir.

| # | Sezgisel İlke | Tasarım Şartnamesindeki Karşılığı | Uzman Değerlendirmesi | Riskler / Açık Maddeler |
|---|---|---|---|---|
| **1** | Sistem Durumunun Görünürlüğü | Hub Bağlantı Durumu (Online/Offline rozeti), Outbox bekleyen sayısı, anlık sepet toplamı güncellemesi. | 🟢 İyi tasarlanmış | Rozet tasarımı ve yeri proje sahibi onayını bekliyor. |
| **2** | Sistem ile Gerçek Dünya Uyumu | Türkiye perakende terminolojisi (Fiş, Kuruş, İade). `12.50 TL` para formatı (`₺` ve virgül ondalık yerine standart nokta + `TL`). *(Z-Raporu / KDV MVP dışıdır.)* | 🟡 Kısmen | `Z-Raporu` ve KDV gösterimi kapsam dışıdır; kalan alanlarda tutarlılık doğrulandı. |
| **3** | Kullanıcı Kontrolü ve Özgürlük | Satır silme, modal ESC ile kapama (`F1/F2/F9/F10/Esc` `main_shell_screen.dart` uyumlu). | 🟡 Kısmen | Parked Carts (`OD-02`) 11 Kasım 2026 kararıyla MVP dışı bırakılmıştır. ESC davranışı bağlama göre tutarlı uygulanmalıdır. |
| **4** | Tutarlılık ve Standartlar | Renk semantiği (Yeşil=Nakit, Mavi=Kart, Sarı=Uyarı, Kırmızı=İptal). Monospace Tabular hizalama. | 🟡 Kısmen | `shared.css` v1.2 kontrast düzeltmeleri tamamlandı; `AppTheme` ile birleştirme Faz 1.2'de doğrulanacaktır. |
| **5** | Hata Önleme | Sepet temizleme onay diyalogu. Eksik ödeme tutarında onay butonu bloke. Offline bilinmeyen barkod ekleme engeli (`OD-03`). | 🟡 Kısmen | Debounce süresi ve sepet temizleme onayı implementasyon aşamasında netleşir; `OD-03` gereği bilinmeyen barkod offline eklenemez. |
| **6** | Hatırlama Yerine Tanıma | Hızlı ürün butonları (`[UX PROPOSAL]`). Klavye kısayol listesi görünür bar. | 🟡 Kısmen | Hızlı ürün buton listesi Faz 1.2 UI önerisidir; kısayollar `main_shell_screen.dart` (`F1/F2/F9/F10/Esc`) ile hizalıdır. |
| **7** | Kullanım Esnekliği ve Verimlilik | Fiziksel klavye + USB HID barkod okuyucu temel yöntemdir; sanal numpad opsiyonel olup varsayılan kapalıdır (`OD-04`). | 🟡 Kısmen | Birden fazla girdi yöntemi (HID + klavye + opsiyonel dokunmatik/fare) arasındaki odak geçişleri gerçek Windows/dokunmatik testinde doğrulanmalıdır. |
| **8** | Estetik ve Minimalist Tasarım | Sade, dekorasyonsuz Slate tabanlı zemin. Yalnızca işlevsel bileşenler. | 🟢 İyi tasarlanmış | UI/UX konsepti Proje Sahibi tarafından kabul edilmiştir; final Flutter render'ı Faz 1.2'de üretilecektir. |
| **9** | Hata Teşhis ve Kurtarma | Ham hata mesajları (SQLite, HTTP) kullanıcıya gösterilmez; anlaşılır Türkçe mesajlar önerilmiştir. | 🟡 Kısmen | Gerçek hata mesajı içerikleri (`OD-03` Hub bağlantı uyarısı dâhil) Faz 1.2+ implementasyonunda tamamlanır. |
| **10** | Yardım ve Dokümantasyon | `F1` kısayolu (`main_shell_screen.dart`) ile yardım paneli önerisi; form placeholder'ları. | 🟡 Kısmen | Yardım içeriği Faz 1.2'de doldurulacaktır. |

**Özet:** 10 ilkenin 3'ü iyi tasarlanmış, 7'si kısmen karşılanmış durumdadır. `OD-01`..`OD-04` kararları 11 Kasım 2026'da Proje Sahibi tarafından kapatılmış olmakla birlikte gerçek fiziksel cihaz ve kullanıcı testi (Faz 7 Pilot) henüz yapılmadığı için ilkeler uygulamalı test öncesi nihai sayılmaz.

---

## 3. Görev Tamamlama Süresi — Hedefler ve Hipotezler

> [!WARNING]
> Aşağıdaki değerler **tasarım hedefleri ve test hipotezleridir**; gerçek kullanıcı veya bağımsız benchmark ölçümü değildir. v1.0'daki "İnteraktif Prototip Ölçümü" etiketi yanıltıcıydı ve kaldırılmıştır.

| Görev Senaryosu | Tasarım Hedefi | Hipotez (Pilot öncesi uzman tahmini) | Doğrulama Yöntemi |
|---|---|---|---|
| Tek ürünlü nakit satış (barkod → ödeme → özet) | ≤ 4 saniye | Klavye kısayollarıyla 2–3 saniye mümkün görünmektedir | Pilot mağazada Mağaza Sahibi testi |
| 5 kalemli sepet + nakit/kart ödeme | ≤ 12 saniye | Hızlı ürün butonları ve klavye kısayollarıyla 7–10 saniye mümkün görünmektedir | Pilot mağazada Mağaza Sahibi testi |
| Miktar değiştirme (adet düzeltme) | ≤ 3 saniye | Satır içi +/- kontroller (`48×48 dp`) veya `F2` ile 1–2 saniye mümkün görünmektedir | Pilot mağazada Mağaza Sahibi testi |
| Hatalı satır iptali | ≤ 3 saniye | Satır silme butonu (`48×48 dp`) ile ≤ 2 saniye beklenmektedir | Pilot mağazada Mağaza Sahibi testi |
| Mobil barkodla stok & fiyat sorgulama *(Sayım MVP dışı)* | ≤ 5 saniye | Kamera tarama + salt okunur stok/audit görünümü (`mob-04`) | Pilot mağazada cihaz testi |

---

## 4. WCAG 2.1 Renk Kontrast Doğrulama Özeti (Güncel `shared.css` / `verify_wcag.js`)

> [!IMPORTANT]
> **Kapsam Sınırı:** Bu bölüm yalnızca sRGB bağıl parlaklık **renk kontrastı (SC 1.4.3 / SC 1.4.11)** doğrulamasını raporlar; tam WCAG 2.1 erişilebilirlik uygunluğu (ekran okuyucu/ARIA tam denetimi, donanımsal odak gezintisi vb.) olarak yorumlanamaz. `.btn:disabled` (`opacity: 0.45`) öğeleri WCAG 2.1 SC 1.4.3 Inactive istisnası kapsamındadır ve PASS olarak işaretlenmemiştir.

Tüm oranlar `verify_wcag.js` betiğinde IEC 61966-2-1 (`0.04045` sRGB eşiği) ve gerçek RGBA alpha birleştirmesi (`blend`) ile doğrulanmıştır. Light `--text-muted` token'ı `shared.css`'te `#64748B`'den `#475569`'a yükseltilerek (`AppTheme.textMutedLight` ile eşlenerek) `#F1F5F9` zeminindeki **4.34:1 FAIL** durumu **6.92:1 AA PASS** seviyesine çıkarılmış, HTML'deki Dark mod inline `var(--success/warning/danger)` metinleri `var(--*-text)` token'larına geçirilmiştir. Güncel 83 kontrol tablosu için bkz. [`UX_TARGETED_AUDIT_REPORT.md`](./UX_TARGETED_AUDIT_REPORT.md) ve [`visual-designs/verify_wcag.js`](./visual-designs/verify_wcag.js).

| Kullanım Alanı | Ön Plan | Arka Plan | Hesaplanan Oran | Normal Metin AA (4.5:1) | UI Sınırı (3.0:1) |
|---|---|---|---|---|---|
| Ana metin (Light) | `#0F172A` | `#FFFFFF` | **17.85:1** | ✅ AAA | ✅ |
| Ana metin (Light Bg) | `#0F172A` | `#F8FAFC` | **17.06:1** | ✅ AAA | ✅ |
| Ana metin (Dark) | `#F8FAFC` | `#1E293B` | **13.98:1** | ✅ AAA | ✅ |
| İkincil metin (Light — Surface & Subtle) | `#475569` | `#FFFFFF` / `#F1F5F9` | **7.58:1** / **6.92:1** | ✅ AAA / ✅ AA | ✅ |
| İkincil metin (Dark) | `#94A3B8` | `#1E293B` | **5.71:1** | ✅ AA | ✅ |
| Nakit buton (Light & Dark) | `#FFFFFF` | `#047857` | **5.48:1** | ✅ AA | ✅ |
| Nakit buton Hover (Light & Dark) | `#FFFFFF` | `#065F46` | **7.68:1** | ✅ AAA | ✅ |
| Kart butonu (Light) | `#FFFFFF` | `#2563EB` | **5.17:1** | ✅ AA | ✅ |
| Kart butonu (Dark / Hover) | `#FFFFFF` | `#1D4ED8` / `#1E40AF` | **6.70:1** / **8.72:1** | ✅ AA / ✅ AAA | ✅ |
| Tehlike / İptal (Light & Dark) | `#FFFFFF` | `#B91C1C` | **6.47:1** | ✅ AA | ✅ |
| Inline Dark Durum Metinleri (`--success/warning/danger-text`) | `#34D399` / `#FBBF24` / `#F87171` | `#1E293B` | **7.61:1** / **8.76:1** / **5.29:1** | ✅ AAA / ✅ AA | ✅ |
| Para üstü kutusu (Light) | `#166534` | `#DCFCE7` | **6.49:1** | ✅ AA | ✅ |
| Para üstü kutusu (Dark RGBA Blend) | `#34D399` | `rgb(25,57,65)` | **6.41:1** | ✅ AA | ✅ |
| Para üstü Hata kutusu (Dark RGBA Blend) | `#F87171` | `rgb(61,38,53)` | **4.97:1** | ✅ AA | ✅ |
| Offline rozet (Light) | `#92400E` | `#FEF3C7` | **6.37:1** | ✅ AA | ✅ |
| Outbox rozet (Light) | `#1E40AF` | `#DBEAFE` | **7.15:1** | ✅ AAA | ✅ |

**Özet:** Güncel `shared.css` / HTML düzeltmeleri sonrasında `verify_wcag.js` kapsamındaki **83/83** renk kontrast kontrolü geçmektedir (Light `#475569` dahil, `btn:disabled` muaf).

---

## 5. Hata Önleme Mekanizmaları — Tasarım Hipotezleri

Aşağıdakiler UI tasarımında yer alan hata önleme mekanizmaları ve bunların beklenen etkisidir. Gerçek etkinlikleri implementasyon sonrası doğrulanacaktır.

| Mekanizma | Tasarım Hipotezi | Gerçek Etkinlik |
|---|---|---|
| Sepet temizleme onay diyalogu | Yanlışlıkla sepet temizleme olaylarını azaltır | Pilot mağaza testinde doğrulanacak |
| Eksik ödeme tutarında bloke | Tutarın yetersiz olduğu nakit satışları önler | Implementasyon sonrası test edilecek |
| Barkod debounce filtresi | Aynı barkodun 200–300 ms içinde çift eklenmesini önler | Gerçek HID okuyucuyla test edilecek |
| Offline outbox garantisi | Hub erişilemeyen durumda satış verisi yerel SQLite WAL'a yazılır | Mimarinin garantisi; ağ kesintisi testleriyle doğrulanacak |

> [!CAUTION]
> "Elektrik kesintisinde veri kaybı imkânsızdır" iddiası kaldırılmıştır. SQLite WAL modu ve Drift transaction semantiği güçlü koruma sağlar ancak güç kesintilerinin etkisi gerçek donanım üzerinde test edilmelidir (özellikle OS write-back cache ve UPS yokluğunda).

---

## 6. Pilot Mağaza Test Planı (Planlanan — Henüz Yapılmamış)

| Test Türü | Hedef Kapsam | Planlanan Aşama (`ROADMAP.md`) |
|---|---|---|
| Mağaza Sahibi (`INV-09`) moderated usability testi | Nakit/kart satış akışı, hata kurtarma | Faz 7 Pilot |
| Fiziksel Android/iOS alan testi | Kamera barkod tarama, mobil stok görüntüleme & mDNS | Faz 7 Pilot |
| HID barkod okuyucu odak testi | Farklı USB okuyucu markaları, Windows 10/11 | Faz 7 Pilot |
| Ağ kesintisi senaryosu | Outbox senkronizasyonu, offline çalışma | Faz 7 Pilot |
| Uzun süreli dayanıklılık (soak test) | 8 saatlik çalışma, bellek / CPU kullanımı | Faz 7 Pilot |
