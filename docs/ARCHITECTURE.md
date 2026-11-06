# ARCHITECTURE.md — Teknik Mimari Özeti

Bu belge, [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](../MARKET_POS_AI_STUDIO_BUILD_PLANI.md) (**v1.2**) belgesinde kesinleşen mimari kararların teknik özetidir.

---

## 1. Ürün ve Mimari Vizyon

Proje teknik adı `market-pos` olarak korunmakla birlikte, ürün bir **Market Management System (MMS)** olarak tasarlanmaktadır. 
- Windows masaüstü bilgisayar ve mobil telefonlar **aynı temel yeteneklere** (ürün, satış, stok, dashboard, raporlama) sahiptir.
- Banka POS terminali / Ingenico cihaz entegrasyonu ilk sürümün kapsamı dışındadır.

---

## 2. Temel Teknoloji Kararları

| Alan | Seçilen Teknoloji | Not / Doğrulama Durumu |
|---|---|---|
| **Ürün Tipi** | Market Management System (MMS) | Pilot tek market; SaaS ve çok şubeli genişlemeye hazır mimari |
| **Uygulama Çerçevesi** | Flutter (Dart) | Windows masaüstü, Android ve iOS |
| **Uç / Yerel Depolama** | Drift + SQLite (WAL Modu) | Mobil cihazlarda ve masaüstünde yerel operasyonel veri tabanı |
| **Merkezi Depolama (Pilot)** | Merkezi SQLite (WAL Modu) | Windows Service tarafından tekil yazıcı (Single-Writer) olarak yönetilen master defter |
| **Gelecek Merkezi Depolama (SaaS)**| PostgreSQL / Supabase | Çok şubeli zincir ve bulut SaaS fazı için şema uyumluluğu korunur |
| **Kimlik ve Eşleştirme (Pilot)**| Yerel API & Cihaz Eşleştirme | Pilot tek Owner hesabı; eşleştirme ve yerel kimlik yöntemi açık konudur |
| **Gelecek Kimlik (SaaS)**| Supabase Auth | E-posta/şifre, rol ve üyelik yönetimi |
| **Ağ ve Senkronizasyon** | Yerel Wi-Fi / LAN API | İnternet olmadan mağaza içi LAN üzerinden; Windows kapalıyken offline Outbox |
| **Durum Yönetimi** | Riverpod | Test edilebilir, reaktif durum yönetimi |
| **Navigasyon** | go_router | Deklaratif yönlendirme, derin bağlantı uyumu |
| **Barkod Girişi** | PC'de USB HID; Mobilde Kamera | Otomatik ürün bulma ve sepet oluşturma |
| **Ürün Öneri API** | Open Food Facts API | Barkod okutulduğunda ürün bilgisi önerme (fiyat/stok elle girilir) |
| **Yedekleme** | Windows Service + Google Drive | Merkezi ve mobil ayrık SQLite yedekleri + Şifreli bağımsız Google Drive yedeği |

---

## 3. Mimari Model: Feature-First + Clean Architecture

Proje dizin yapısı özellik odaklı (feature-first) modüllere ve modül içinde 3 Clean Architecture katmanına ayrılır:

```text
lib/
├── app/               # Router, tema, bootstrap
├── core/              # Ortak yardımcılar, hata tipleri, network
├── features/          # auth, tenants, stores, products, inventory, sales, dashboard, sync, backup vb.
│   └── <feature>/
│       ├── domain/        # Entity, value object, repository arayüzleri
│       ├── data/          # Repository implementasyonları, Drift DAO, Yerel API DTO (Gelecek SaaS için Supabase DTO)
│       └── presentation/  # Sayfalar, widget'lar, Riverpod provider'ları
└── infrastructure/    # database (Drift), Windows Service API istemcisi (Gelecek SaaS için Supabase istemcisi), platform donanım köprüleri
```

### Bağımlılık Yönü
- `presentation` $\longrightarrow$ `domain`
- `data` $\longrightarrow$ `domain`
- `domain` katmanı hiçbir dış kütüphaneye (Flutter UI, Drift, Supabase) doğrudan bağımlı değildir (saf Dart).

---

## 4. Çoklu Market (Multi-Tenant) SaaS Tasarımı

- **Tenant:** Müşteri işletme veya market grubu.
- **Store:** Fiziksel şube/mağaza.
- **User & Membership:** Kullanıcı ve yetki ilişkisi.
- **Device:** İşlem yapan fiziksel cihaz (Windows PC, telefon veya tablet).
- Tenant/store veri izolasyonu korunacaktır; pilot tek tenant ve tek store ile başlayacaktır. Merkezi API, veri erişiminde tenant/store sınırlarını uygulamalıdır; gelecek bulut SaaS aşamasında ise Supabase RLS ile veri izolasyonu desteklenecektir.

---

## 5. Offline-First, Çoklu Cihaz ve Senkronizasyon

- **Windows Master Hub:** Windows bilgisayar ana sunucudur. Arka planda bağımsız bir Windows Service çalışır.
- **Single-Writer İlkesi:** Merkezi SQLite veritabanına tüm yazma işlemleri Windows Service API'si üzerinden yönetilir. Flutter Windows masaüstü arayüzü de yerel loopback API (`http://127.0.0.1:<port>`) üzerinden işlem yapar.
- **SQLite Kilitlenme ve Eşzamanlılık Yönetimi:** Kilitlenme riskini minimize etmek için WAL modu (`PRAGMA journal_mode = WAL;`), meşguliyet zaman aşımı (`PRAGMA busy_timeout = 5000;`), üstel geri çekilme (exponential backoff retry) ve atomik transaction yöneticisi zorunludur.
- **Yerel Ağda Kesintisiz Çalışma:** Mobil cihazlar mağaza içi Wi-Fi / LAN üzerinden Windows Service API'sine bağlanır; internet kesintisi mağaza içi iletişimi etkilemez.
- **Windows Kapalıyken Çalışma:** Windows PC kapalıyken mobil cihazlar yerel Drift/SQLite veritabanlarında satış yapar (`sync_operations` kuyruğuna yazar). Windows açıldığında Outbox işlemleri deterministik FIFO sırasıyla merkeze aktarılır.
- **Idempotency:** İşlemlerde `idempotency_key` kullanılarak tekrarlanan çağrıların çifte kayıt oluşturması önlenir.
- **Stok Çakışması:** Eksi stok politikası `allow` olup, gerçekleşmiş fiziksel satışlar çakışma durumunda asla silinmez; audit kaydı ve stok düzeltme bildirimi oluşturulur.

---

## 6. Dashboard ve Finansal Doğruluk

- Ciro, brüt kâr ve net kâr kavramları birbirinden ayrılır.
- Maliyet verisi girilmemiş ürünlerde gerçek kâr hesabı yapılmaz; genel işletme giderleri olmadan net kâr iddiasında bulunulamaz.
- Para değerleri kesinlik kaybını önleyen uygun veri tipleriyle tutulmalı, para hesaplamalarında floating-point aritmetiği kullanılmamalıdır. Gerektiğinde para değerleri kuruş bazlı tam sayılarla veya fixed-point tiplerle saklanabilir; gramaj, ağırlık, oran ve istatistik gibi alanlar için uygun sayısal temsil ayrıca belirlenir.

---

## 7. Henüz Kesinleşmemiş / Faz 0 Kapsamında Doğrulanacak Konular (Teknik Spike'lar)

1. **SPIKE-01 (Windows Service & SQLite):** Dart AOT + Shelf vs C# Worker mimari karşılaştırması ve SQLite WAL eşzamanlı yazma dayanıklılığı.
2. **SPIKE-02 (LAN Discovery & Pairing):** mDNS yayını ve router AP isolation engeli durumunda Dinamik QR kod doğrudan IP eşleştirmesinin saha testi.
3. **SPIKE-03 (Yerel TLS & iOS İzni):** Yerel ağda şifreli HTTPS iletişimi ve iOS 14+ `NSLocalNetworkUsageDescription` izin modelinin doğrulanması.
4. **Dağıtım Stratejisi:** Windows installer (Inno Setup / MSI) ve iOS TestFlight derleme altyapısı (GitHub Actions macOS Runner).
