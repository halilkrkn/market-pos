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
| **Ürün Tipi** | Market Management System (MMS) | Çoklu market SaaS mimarisi |
| **Uygulama Çerçevesi** | Flutter (Dart) | Windows, Android, iOS ve Web hedefleri |
| **Yerel Veritabanı** | Drift + SQLite | Mobil ve Masaüstü birincil yerel depolama; Web için depolama doğrulaması Faz 0'da yapılacak |
| **Merkezi Veritabanı** | Supabase PostgreSQL | Çoklu tenant, RLS güvenlik politikaları |
| **Kimlik Doğrulama** | Supabase Auth | E-posta/şifre, rol ve üyelik yönetimi |
| **Durum Yönetimi** | Riverpod | Test edilebilir, reaktif durum yönetimi |
| **Navigasyon** | go_router | Deklaratif yönlendirme, derin bağlantı uyumu |
| **Barkod Girişi** | PC'de USB HID; Mobilde Kamera | Kamera ile ürün arama ve Open Food Facts önerisi |
| **Ürün Öneri API** | Open Food Facts API | Barkod okutulduğunda ürün bilgisi önerme (doğrulama gerektirir) |
| **Yedekleme** | Supabase + Google Drive | Merkezi veritabanı yedeği + harici bağımsız Google Drive yedekleme |

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
│       ├── data/          # Repository implementasyonları, Drift DAO, Supabase DTO
│       └── presentation/  # Sayfalar, widget'lar, Riverpod provider'ları
└── infrastructure/    # database (Drift), supabase istemcisi, platform donanım köprüleri
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
- Bütün veri modellerinde `tenant_id` zorunlu alandır; Supabase RLS ile veri izolasyonu veritabanı seviyesinde garanti altına alınır.

---

## 5. Offline-First, Çoklu Cihaz ve Senkronizasyon

- Yerel işlemler internet olmaksızın Drift/SQLite üzerinde yürütülür.
- Satış, stok düşümü ve `sync_operations` kuyruk kaydı aynı yerel transaction içinde atomik kaydedilir.
- Senkronizasyon servisi bekleyen işlemleri merkezi PostgreSQL'e aktarır.
- İşlemlerde `idempotency_key` kullanılarak tekrarlanan çağrıların çifte kayıt oluşturması önlenir.
- Stok çakışmalarında satışlar silinmez; denetim kaydı oluşturularak yetkili müdahalesi istenir.

---

## 6. Dashboard ve Finansal Doğruluk

- Ciro, brüt kâr ve net kâr kavramları birbirinden ayrılır.
- Maliyet verisi girilmemiş ürünlerde gerçek kâr hesabı yapılmaz; genel işletme giderleri olmadan net kâr iddiasında bulunulamaz.
- Para değerleri kesinlik kaybını önleyen uygun veri tipleriyle tutulmalı, para hesaplamalarında floating-point aritmetiği kullanılmamalıdır. Gerektiğinde para değerleri kuruş bazlı tam sayılarla veya fixed-point tiplerle saklanabilir; gramaj, ağırlık, oran ve istatistik gibi alanlar için uygun sayısal temsil ayrıca belirlenir.

---

## 7. Henüz Kesinleşmemiş / Faz 0 Kapsamında Doğrulanacak Konular

1. Web platformu için kalıcı depolama adaptörü (WASM/IndexedDB SQLite davranışı).
2. iOS paketleme ve derleme için yerel ortam gereksinimleri (macOS/Xcode).
3. Senkronizasyon katmanının saf özel modül olarak mı yoksa PowerSync gibi bir motorla mı destekleneceği (prototip doğrulaması).
4. Google Drive OAuth akışının masaüstü ve mobildeki yerel kimlik doğrulama detayları.
5. Kamera ile barkod okuma performansının düşük segment Android cihazlarda test edilmesi.
