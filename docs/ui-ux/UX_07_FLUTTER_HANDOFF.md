# UX_07_FLUTTER_HANDOFF.md — FLUTTER GELİŞTİRİCİSİ DEVİR KILAVUZU
# Market Management System (Market MMS) — Flutter Developer Handoff & Technical Integration Reference

- **Doküman Versiyonu:** v1.4 (`PaymentMethod` Sözleşme Standardizasyonu — 11 Kasım 2026)
- **Revizyon Notu:** v1.1 bağımlılık şeffaflığını ve v1.2 `AppTheme` / `main_shell_screen.dart` uzlaştırmasını korur. v1.3 ile Proje Sahibi UX kabulü ve `OD-01..OD-04` kesinleşen kararları (`Half-Up`, `Parked Carts` MVP dışı, `offline` bilinmeyen barkod eklenemez/oluşturulamaz, sanal numpad opsiyonel ve varsayılan kapalı) devir kılavuzuna işlenmiştir. v1.4 ile Faz 1.2 öncesi standardize edilen kanonik `PaymentMethod` sözleşmesi (`'CASH'` / `'CARD'`; `CREDIT_CARD`/`NAKIT` *obsolete*) handoff referansına eklenmiştir.
- **Önemli Kısıt:** Bu kılavuz mimari şartname ve tasarım handoff referansıdır. Proje sahibinin açık onayı olmadan `lib/`, `test/` veya `pubspec.yaml` üzerinde değişiklik başlatılamaz.

---

## 1. Mevcut Proje Bağımlılıkları (Gerçek pubspec.yaml)

Aşağıdaki bağımlılıklar `pubspec.yaml` üzerinde doğrulanmıştır (6 Kasım 2026):

```yaml
# Mevcut bağımlılıklar (doğrulanmış)
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  drift: ^2.20.0          # Yerel SQLite ORM (client_local.db)
  flutter_riverpod: ^2.5.1 # Durum yönetimi
  http: ^1.2.2             # Loopback HTTPS API istemcisi
  path: ^1.9.0
  mms_client_storage:
    path: packages/mms_client_storage  # Yerel yedekleme motoru (AES-256-CBC)
```

**Eksik Paketler (Şu an projede bulunmayan — önerilecekse proje sahibi onayı gerekir):**

| Paket | İşlev | Mevcut mu? |
|---|---|---|
| `go_router` | Deklaratif rota yönetimi | ❌ Yok |
| Özel font (`Roboto Mono` vb.) | Monospace tipografi | ❌ Yok |
| `google_sign_in` | Google Drive yedekleme OAuth | ❌ Yok |

> [!WARNING]
> UX_02_INFORMATION_ARCHITECTURE.md belgesi `go_router` rotalarını şartname olarak içermektedir. Ancak `go_router` mevcut `pubspec.yaml`'de yoktur. Bu rota yapısı bir tasarım önerisidir; eklenmesi için proje sahibi onayı gerekir.

---

## 2. Mimari Sınırlar ve Clean Architecture (Onaylanmış)

Aşağıdaki bağımlılık yönü kuralı `AGENTS.md` anayasasından gelmekte olup değiştirilemez:

$$\text{presentation} \longrightarrow \text{application} \longrightarrow \text{domain (Saf Dart)} \longleftarrow \text{data} \longleftarrow \text{infrastructure}$$

**Kesin Kurallar:**
1. **Domain katmanı saf Dart'tır** — `flutter/material.dart`, `drift`, `http` veya diğer framework bağımlılıkları kesinlikle import edilemez.
2. **Presentation katmanı doğrudan veritabanına erişemez** — `client_local.db`'ye yalnızca Drift DAO'ları üzerinden erişilir, presentation katmanı bunları doğrudan çağıramaz.
3. **Windows UI `market_master.db`'ye hiçbir koşulda doğrudan erişemez** — Merkezi DB yalnızca `MarketMMSService` Windows Servisi üzerinden erişilebilir; Flutter UI loopback HTTPS API kullanır.
4. **Mobil istemciler kendi yerel DB'lerini kullanır** — Android/iOS cihazlar kendi `mms_client.db` dosyalarına Drift üzerinden bağlanır; birbirleriyle değil, yalnızca Master Hub ile senkronize olur.

---

## 3. Mevcut `AppTheme` ile Tasarım Token Uzlaştırması

> [!IMPORTANT]
> **Tek Tema Kaynağı Kuralı (`AppTheme`):**  
> Depoda halihazırda [`lib/core/theme/app_theme.dart`](../../lib/core/theme/app_theme.dart) içinde **`AppTheme`** sınıfı (`AppTheme.lightTheme`, `AppTheme.tabularFiguresFeature` vb.) mevcuttur ve `lib/app/app.dart` tarafından aktif kullanılmaktadır.  
> **Paralel ikinci bir tema sistemi (ör. ayrı bir `AppColors` / `AppTypography` ikiz hiyerarşisi) OLUŞTURULMAMALIDIR.** UX tasarım token'ları Faz 1.2+ kapsamında mevcut `AppTheme` yapısına static alanlar, `AppTheme.darkTheme` ve gerekirse `ThemeExtension` olarak entegre edilecektir. Aşağıdaki Dart kodu **uygulama dışı devir eşleme önerisidir (`[HANDOFF ÖNERİSİ]`)**.

### 3.1. Mevcut `AppTheme` Sabitleri ve UX Token Eşlemesi (`shared.css` v1.2 Hizalı)

| CSS Token (`shared.css`) | Light HEX | Dark HEX | Mevcut `AppTheme` Karşılığı | Uzlaştırma / Faz 1.2 Eylemi |
|---|---|---|---|---|
| `--bg-app` | `#F8FAFC` | `#090D16` | `AppTheme.surfaceLight` (`0xFFF8FAFC`) | Light birebir eşleşir; Dark `bgDark` `AppTheme` içine eklenir. |
| `--bg-surface` | `#FFFFFF` | `#1E293B` | `AppTheme.cardBgLight` (`Colors.white`) | Light birebir eşleşir; Dark `surfaceDark` `AppTheme` içine eklenir. |
| `--border-subtle` | `#E2E8F0` | `#334155` | `AppTheme.borderSubtle` (`0xFFCBD5E1`) | Mevcut Slate 300 korunabilir; Dark için `#334155` eklenir. |
| `--text-main` | `#0F172A` | `#F8FAFC` | `AppTheme.textMainLight` (`0xFF0F172A`) | Light birebir eşleşir; Dark için `#F8FAFC` eklenir. |
| `--text-muted` | **`#475569`** | `#94A3B8` | `AppTheme.textMutedLight` (`0xFF475569`) | **Tam eşit:** `shared.css` `#64748B`'den `#475569`'a çekilerek `AppTheme` ile hizalandı (`#F1F5F9` üzerinde **6.92:1 AA**). |
| `--accent` / `--accent-text` | `#2563EB` / `#1E40AF` | `#1D4ED8` / `#60A5FA` | `AppTheme.primaryBlue` (`0xFF1E40AF`) | Ana marka mavisi `AppTheme.primaryBlue` korunur; buton/Dark tonlar yardımcı sabit eklenir. |
| `--success` / `--success-text` | `#047857` / `#166534` | `#047857` / `#34D399` | `AppTheme.statusOnline` (`0xFF15803D`) | POS büyük nakit aksiyonları için `#047857`, Dark metin için `#34D399` `AppTheme`'e eklenir. |
| `--warning` / `--warning-text` | `#B45309` / `#92400E` | `#B45309` / `#FBBF24` | `AppTheme.statusWarning` (`0xFFB45309`) | Light birebir eşleşir; Dark uyarı metinlerinde **mutlaka `#FBBF24`** kullanılır (`#B45309` Dark yüzeyde FAIL olur). |
| `--danger` / `--danger-text` | `#B91C1C` / `#991B1B` | `#B91C1C` / `#F87171` | `AppTheme.statusOffline` (`0xFFB91C1C`) | Light buton/border birebir eşleşir; Dark hata metinlerinde **mutlaka `#F87171`** kullanılır (`#B91C1C` Dark yüzeyde FAIL olur). |

```dart
// [HANDOFF ÖNERİSİ — lib/core/theme/app_theme.dart içerisine eklenti konsepti]
// Mevcut AppTheme sınıfını korur; paralel ikinci bir tema sınıfı AÇILMAZ.
class AppTheme {
  // ... Mevcut doğrulanmış Light sabitleri aynen korunur (app_theme.dart L9-25):
  // primaryBlue (#1E40AF), primaryDark (#0F172A), surfaceLight (#F8FAFC),
  // cardBgLight (#FFFFFF), textMainLight (#0F172A), textMutedLight (#475569),
  // borderSubtle (#CBD5E1), statusOnline (#15803D), statusOffline (#B91C1C),
  // statusWarning (#B45309), tabularFiguresFeature.

  // [FAZ 1.2+ EKLEME ÖNERİSİ] Dark Mod & Semantik Metin / Rozet Token'ları:
  static const Color bgDark = Color(0xFF090D16);
  static const Color surfaceDark = Color(0xFF1E293B);
  static const Color surfaceSubtleDark = Color(0xFF0F172A);
  static const Color borderSubtleDark = Color(0xFF334155);
  static const Color textMainDark = Color(0xFFF8FAFC);
  static const Color textMutedDark = Color(0xFF94A3B8);

  static const Color posCashAction = Color(0xFF047857);
  static const Color posCardActionLight = Color(0xFF2563EB);
  static const Color posCardActionDark = Color(0xFF1D4ED8);

  static const Color statusOnlineTextDark = Color(0xFF34D399);
  static const Color statusWarningTextDark = Color(0xFFFBBF24);
  static const Color statusDangerTextDark = Color(0xFFF87171);
  static const Color accentTextDark = Color(0xFF60A5FA);

  // static ThemeData get darkTheme => ... (Light ile aynı buton boyutları >=48dp ve tabularFiguresFeature)
}
```

### 3.2. Tipografi & Tabular Figures (Mevcut `AppTheme.tabularFiguresFeature` Üzerinden)

`lib/core/theme/app_theme.dart` (L23-25) halihazırda `static const List<FontFeature> tabularFiguresFeature = [FontFeature.tabularFigures()];` sabitini tanımlamaktadır ve `CashierHeaderBar` gibi widget'larda doğrudan kullanılmaktadır (`fontFeatures: AppTheme.tabularFiguresFeature`).
- **Ayrı `AppTypography` sınıfı yerine:** Para gösterimleri (`12.50 TL`) için mevcut `Theme.of(context).textTheme` stilleri `.copyWith(fontFeatures: AppTheme.tabularFiguresFeature)` ile kullanılmalı veya `AppTheme` içine ek `TextStyle` getter'ları tanımlanmalıdır.
- **`RobotoMono` Font Notu:** Özel font (`RobotoMono`) eklenmesi zorunlu değildir ve mevcut `pubspec.yaml`'da bulunmamaktadır; eklenecekse proje sahibi onayı gerekir. Sistem varsayılanı + `AppTheme.tabularFiguresFeature` kuruş basamaklarını dikeyde eksiksiz hizalar.

### 3.3 Dokunmatik Hedefler ve Flutter Logical Pixel (dp) Standardı

> [!IMPORTANT]
> **CSS Px vs Flutter Logical Pixel (dp) Ayrımı:**  
> Web prototiplerinde kullanılan $1\text{ CSS px}$ ($96\text{ DPI}$ standardı), mobil ve dokunmatik cihazlardaki fiziksel milimetre ölçüsüne doğrudan eşit değildir.  
> Flutter'da tüm UI boyutlandırmaları `dp` (device-independent pixel / logical pixel) cinsindendir ve Flutter motoru ekran yoğunluğuna göre (`MediaQuery.of(context).devicePixelRatio`) fiziksel piksel dönüşümünü otomatik yönetir.

**Flutter İmplementasyonu İçin Bağlayıcı Dokunmatik Kurallar:**
1. **Mobil Dokunmatik Hedef Sınırı:** Android ve iOS mobil arayüzlerindeki tüm tıklanabilir butonlar, sepet miktar artır/azalt düğmeleri, barkod tetikleyicileri ve tab bar elemanları en az **$48\times 48\text{ logical pixel}$** (`kMinInteractiveDimension`) boyutunda olmalıdır.
2. **Windows POS Dokunmatik Kiosk Desteği:** Windows masaüstü kasa uygulamasında dokunmatik POS monitörü kullanımı söz konusu olduğunda, sepet satırındaki miktar artır/azalt butonları ile ödeme butonları en az **$48\times 48\text{ dp}$** olarak boyutlandırılmalıdır (Salt fare ile kullanılan alanlar için $40\times 40\text{ dp}$ kabul edilebilir).
3. **Form Input Yükseklikleri:** Masaüstünde standart inputlar $40-48\text{ dp}$ yüksekliğinde olabilirken, mobil form alanları (`TextFormField`) dokunmatik ergonomi için en az **$48\text{ dp}$** olmalıdır.

---

## 4. Barkod Odak Yönetimi — Revize Mimari (Context-Aware Focus)

v1.0'daki "GestureDetector ile her tıklamada zorla barkod kutusuna dön" yaklaşımı kaldırılmıştır. Aşağıdaki context-aware model önerilmektedir:

```dart
// [HANDOFF ÖNERISI] — Context-aware focus yönetimi konsepti
// POS ekranı; hangi alt modun aktif olduğuna göre odağı yönetir.

enum PosInputMode {
  idle,          // Barkod alanı odaklı (varsayılan)
  productSearch, // Arama alanı odaklı
  quantityEdit,  // Miktar alanı odaklı
  payment,       // Ödeme modal alanı odaklı
}

// Temel prensipler:
// 1. Modal dışında: Kullanıcı bilinçli olarak başka alana geçmeye çalışıyorsa izin ver.
// 2. Modal kapandığında: idle moduna dön, barkod alanına odaklan.
// 3. HID okuyucu için: Barkod alanı her zaman odaklı olmalı (idle modunda).
// 4. Zorla odak zıplaması: Yalnızca idle modunda ve kullanıcı başka bir bileşene
//    bilinçsizce tıkladığında (örn. tablo arka planı).
```

**Önemli Not:** HID barkod okuyucusunun gerçek davranışı farklı üretici ve Windows sürümlerinde değişkenlik gösterebilir. Pilot aşamada gerçek donanımla test edilmesi zorunludur.

### 4.1. Klavye Kısayollarının `main_shell_screen.dart` İle Uzlaştırılması & Placeholder Borcu

Depodaki [`lib/features/shell/presentation/screens/main_shell_screen.dart` (L205–209)](../../lib/features/shell/presentation/screens/main_shell_screen.dart#L205-L209) alt kısayol çubuğu halihazırda aşağıdaki tuş atamalarını göstermektedir; UX v1.1 taslaklarındaki `F11`/`F12` uyumsuzluğu giderilmiş ve tüm UX belgeleri/HTML ekranları mevcut Flutter koduna göre hizalanmıştır:

| Tuş | Mevcut `main_shell_screen.dart` (Esas Alınan) | Eski UX Draft (Kaldırıldı) | Faz 1.2 Handoff Durumu |
|---|---|---|---|
| `F1` | **Yardım** | Yardım | **Mevcut kodla uyumlu** — Kısayol/Yardım panelini açar. |
| `F2` | **Miktar** | Ürün Arama (`Miktar` F3 idi) | **Mevcut kodla uyumlu** — Seçili sepet satırı miktarını odaklar. |
| `F9` | **Kart (Kredi Kartı)** | Seçili Satırı Sil | **Mevcut kodla uyumlu** — Ödeme modalını Kredi Kartı (`INV-08`) seçili açar. |
| `F10` | **Nakit** | Sepeti Temizle | **Mevcut kodla uyumlu** — Ödeme modalını Nakit seçili açar. |
| `Esc` | **İptal** | Modal Kapat | **Mevcut kodla uyumlu** — Açık modalı kapatır / barkod odağına döner. |
| `F3` / `F8` | *(Henüz tanımlı değil)* | Çeşitli | `[UX PROPOSAL]`: `F3` Ürün Arama, `F8/Del` Satır Sil — Faz 1.2'de proje sahibi onayı gerektirir *(Not: `F4` Parked Carts `OD-02` kararıyla MVP dışındadır)*. |

> [!WARNING]
> **Faz 1.2'de Temizlenecek Mevcut Placeholder Metinleri (`main_shell_screen.dart`):**  
> Bu görev kapsamında `lib/` değiştirilmemiştir; ancak `main_shell_screen.dart` satır `112` ("*stok sayımı*") ve satır `119` ("*Z-Raporu, KDV dökümü*") metinleri MVP dışı (`OUT_OF_SCOPE`) özelliklere atıf yapmaktadır. Faz 1.2/2 uygulama kodlamasında bu placeholder metinler kanonik `BUSINESS_RULES_SPEC.md` v1.4 ile uyumlu hâle getirilmelidir.

---

## 5. Mevcut Riverpod Kullanımı (Doğrulanmış)

`flutter_riverpod: ^2.5.1` mevcut bağımlılıktır. `SystemStatusNotifier` gibi notifier'lar projede aktif olarak kullanılmaktadır (bkz. `test/features/diagnostics/system_status_notifier_test.dart`).

```dart
// [HANDOFF ÖNERISI] Sepet durumu için CartState yapısı konsepti
// INV-01 uyarınca: totalCents int tipindedir; double yasaktır.

class CartState {
  final List<CartItem> items; // CartItem domain entity'si
  final int totalCents;       // Kuruş tamsayı — double YASAK
  final bool isHubOnline;
  final int pendingOutbox;

  // Biçimlendirme — UI katmanında, domain'de değil (Standart: 12.50 TL [INV-01])
  String get formattedTotal {
    final liras = totalCents ~/ 100;
    final kurus = totalCents.remainder(100).abs();
    return '$liras.${kurus.toString().padLeft(2, '0')} TL';
    // double aritmetiği kullanılmaz!
  }
}
```

---

## 6. Mimari Özet ve Handoff Sınırları

| Madde | Durum |
|---|---|
| Clean Architecture katman ayrımı | Onaylanmış (`AGENTS.md`) — uyulması zorunlu |
| Domain katmanı saf Dart | Onaylanmış (`AGENTS.md`) — zorunlu |
| `drift` ile `client_local.db` | Mevcut bağımlılık, aktif kullanımda |
| `flutter_riverpod` state management | Mevcut bağımlılık, aktif kullanımda |
| `http` ile loopback API | Mevcut bağımlılık, aktif kullanımda |
| `go_router` navigasyon | ❌ `pubspec.yaml`'da yok (`UX_02` rota tablosu `[UX PROPOSAL]`dır) — eklenmesi proje sahibi onayını gerektirir |
| Özel fontlar (`RobotoMono`) | ❌ `pubspec.yaml`'da yok — eklenmesi opsiyoneldir; `AppTheme.tabularFiguresFeature` halihazırda mevcuttur |
| `AppTheme` (`lib/core/theme/app_theme.dart`) | ✅ **Mevcut & Tek Tema Kaynağı** (`#1E40AF`, `#475569`, `Size(64,52)`, `tabularFiguresFeature`) — paralel tema oluşturulmaz |
| Dark Tema & Inline Semantik Token'lar | ❌ Henüz Dart'ta yok — Faz 1.2'de `AppTheme` içine (`darkTheme` + `#34D399`/`#FBBF24`/`#F87171`) eklenmesi önerilir |
| Klavye Kısayolları (`F1/F2/F9/F10/Esc`) | ✅ Alt bar [`main_shell_screen.dart`](../../lib/features/shell/presentation/screens/main_shell_screen.dart#L205-L209)'ta tanımlı — tüm UX belgeleri bununla uzlaştırıldı (`F3`, `F8/Del` `[UX PROPOSAL]`; `F4` `OUT_OF_SCOPE`) |
| POS ekranı odak yönetimi | ❌ Henüz uygulanmadı — Faz 1.2 `[UX PROPOSAL]` |
| `B-2` Mobil Root CA Pinning | Kesinleşmiş mimari karar — pilot hazırlık güvenlik uygulama backlog maddesi *(Açık karar değildir)* |
| `B-3` Güvenli Token Depolama (DPAPI/Keystore) | Kesinleşmiş mimari karar — pilot hazırlık güvenlik uygulama backlog maddesi *(Açık karar değildir)* |
| İade İşlemi Ağ Kuralı | Windows Hub LAN bağlantısı (`ACK`) zorunludur (`BR-POS-09`) — offline iade yapılamaz |

---

## 7. Kesinleşen Proje Kararları (`OD-01` .. `OD-04` — 11 Kasım 2026)

1. **`OD-01` (Alt Kuruş Yuvarlama — ONAYLANDI):** **Half-Up** yuvarlama kullanılır (`packages/mms_client_storage/lib/src/database/client_storage_repository.dart:119` mevcut formülü ile uyumludur). Floating-point (`double`) aritmetiği yasaktır; integer/decimal güvenli yöntem, dahili integer kuruş (`int`) ve `12.50 TL` formatı zorunludur.
2. **`OD-02` (Parked Carts / `BR-POS-05` — MVP DIŞI):** MVP kapsamı dışındadır (`OUT_OF_SCOPE`). Faz 1.2'de sepet bekletme akışı, veritabanı taslak tablosu veya `F4` kısayolu kodlanmaz.
3. **`OD-03` (Offline Bilinmeyen Barkod / `BR-PROD-05` — ONAYLANDI):** Yerel DB'de (`getProductByBarcode`) bulunmayan barkod **offline oluşturulamaz** ve **offline sepete eklenemez**; kullanıcıya ürün oluşturmak için Master Hub bağlantısı gerektiği bildirilir. Yerel DB'de bulunan ürünler ise kesintisiz offline satılır.
4. **`OD-04` (Sanal Numpad — ONAYLANDI):** Masaüstünde opsiyoneldir ve **varsayılan olarak kapalıdır**. Fiziksel klavye ve USB HID barkod okuyucu temel kullanım yöntemidir.
5. **Kanonik `PaymentMethod` Sözleşmesi (Faz 1.2 Öncesi Standardizasyon — ONAYLANDI):** Saf Dart `PaymentMethod` (`package:mms_client_storage/payment_method.dart`, `mms_client_storage.dart` üzerinden de ihraç edilir) yalnızca `PaymentMethod.cash` (`'CASH'`) ve `PaymentMethod.card` (`'CARD'`) değerlerini üretir/kabul eder. Geçmiş doküman/test kalıntısı olan `'CREDIT_CARD'` ve `'NAKIT'` dizgeleri yürürlükten kaldırılmıştır (*obsolete*). UI katmanı domain/repository katmanına daima `'CASH'` veya `'CARD'` aktarır.

> [!NOTE]
> Bu kılavuzdaki tüm **yeni/önerilen** Dart eklenti taslakları tasarım handoff önerisidir; yalnızca `AppTheme` (`lib/core/theme/app_theme.dart`), `main_shell_screen.dart`, `drift`, `flutter_riverpod`, `http` ve `mms_client_storage` depoda fiilen mevcuttur. UI/UX teslimatı Proje Sahibi tarafından kabul edilmiş olup **Faz 1.2 uygulama kodlamasına geçilmeden önce** [`docs/development/PHASE_1_2_PREPARATION_REPORT.md`](../development/PHASE_1_2_PREPARATION_REPORT.md) raporuyla Faz 1.2 onayı alınmalıdır (`lib/` şu an değiştirilmemiştir).
