# DEVELOPMENT_GUIDE.md — MARKET MMS Geliştirici Kılavuzu

**Belge Sürümü:** v1.0  
**Tarih:** 4 Kasım 2026  
**Aşama:** Faz 1 — Geliştirme Ortamı, Kurulum ve Kodlama Standartları  
**Bağlayıcı Kurallar:** [`AGENTS.md`](../AGENTS.md), [`docs/ai/rules/clean-architecture.md`](./ai/rules/clean-architecture.md), [`docs/ai/rules/clean-code.md`](./ai/rules/clean-code.md)

---

## 1. Geliştirici Ortamı ve Ön Koşullar

MARKET MMS; Windows masaüstü, Android ve iOS platformlarını tek bir Flutter/Dart kod tabanından besleyecek biçimde tasarlanmaktadır.

### Minimum Sistem Gereksinimleri:
- **İşletim Sistemi:** Windows 10/11 x64 (Geliştirme ana makinesi).
- **Flutter SDK:** 3.47.x+ (Stable channel doğrulanmıştır: `Flutter 3.47.9`).
- **Dart SDK:** 3.13.x+ (Doğrulanmıştır: `Dart 3.13.7`).
- **C++ Build Tools:** Visual Studio 2022 (Windows masaüstü Flutter runner derlemesi için "Desktop development with C++").
- **Android Studio / Android SDK:** Android API Level 34+ (Mobilde kamera ve HID testi için).
- **Git:** 2.40+ (Conventional Commits standardı).

---

## 2. Mimari ve Dizin Mimarisi (Feature-First + Clean Architecture)

Proje kaynak kodu Faz 1.1 ile açılmış olup (`packages/mms_client_storage`, `test_spikes/spike_01_backend`, `lib`), aşağıdaki katı katman ve bağımlılık yönüne göre organize edilmektedir:

```text
lib/
├── app/               # Router (go_router), tema, provider gözlemcisi, bootstrap
├── core/              # Para (kuruş), rasyonel oran, hata tipleri, sabitler
├── features/          # auth, tenants, products, inventory, sales, dashboard, sync, backup
│   └── <feature_name>/
│       ├── domain/        # Saf Dart: Entity, Value Object, Repository arayüzleri
│       ├── data/          # Repository implementasyonları, Drift DAO, yerel DTO
│       └── presentation/  # Riverpod provider'ları, ekranlar, widget'lar
└── infrastructure/    # Windows Service yerel API istemcisi, platform donanım köprüleri
```

### Bağımlılık Yönü Kuralı:
$$\text{presentation} \longrightarrow \text{domain} \longleftarrow \text{data}$$

- **Domain Katmanı:** Saf Dart ile yazılır. Flutter UI (`package:flutter`), Drift veya HTTP kütüphanelerine doğrudan bağımlılık **kesinlikle içeremez**.
- **Data Katmanı:** Domain arayüzlerini somutlaştırır, veritabanı veya API haberleşmesini yönetir.
- **Presentation Katmanı:** Yalnızca Domain katmanındaki use-case ve entity'leri tüketir; doğrudan veritabanı tablolarına dokunamaz.

---

## 3. Kodlama ve Veri Standartları (Ironclad Rules)

1. **Kuruş Tamsayı Standardı:**
   - Para değişkenleri için `double` tipi KESİNLİKLE YASAKTIR.
   - Tüm para alanları `int` veya kuruş bazlı tamsayı Value Object (`Money`) olarak tanımlanır (12.50 TL = `1250`).
2. **Atomik Birimler ve Rasyonel Dönüşüm:**
   - Stokta tutulan miktar bölünemez en küçük atomik birimdir (Adet, Gram, Mililitre).
   - Koli/paket dönüşümlerinde floating-point bölme yapılmaz; `conversion_factor_numerator` ve `conversion_factor_denominator` tamsayı oranlarıyla rasyonel çarpma yapılır.
3. **Immutability (Değişmezlik):**
   - Domain entity'leri `immutable` olmalıdır (`@immutable` anotasyonu, `freezed` veya saf Dart final alanlar).
4. **Idempotency ve İşlem Sırası:**
   - Satış ve iadelerde cihazda tekil `idempotency_key` (UUID) ve artan `client_sequence_number` üretilmeden kuyruğa işlem yazılamaz.
5. **Kaza Kurtarma ve SQLite WAL:**
   - Yerel veritabanı açılışında `PRAGMA journal_mode = WAL;` ve `PRAGMA busy_timeout = 5000;` yapılandırması zorunludur.

---

## 4. Git İş Akışı ve Commit Standardı

- **Ana Dal:** `main`.
- **Commit Formatı:** Conventional Commits standardı zorunludur:
  - `feat: ...` (Yeni işlev)
  - `fix: ...` (Hata düzeltme)
  - `docs: ...` (Dokümantasyon değişikliği)
  - `refactor: ...` (İşlev değiştirmeyen kod düzenlemesi)
  - `test: ...` (Test ekleme veya güncelleme)
  - `chore: ...` (Yapılandırma, bağımlılık güncellemesi)
- **Güvenlik Kuralı:** `.env`, API secret'ları, Google Drive token'ları veya Windows yerel sertifikaları asla Git'e commit edilmez (`.gitignore` ile korunur).

---

## 5. Test Piramidi ve Kabul Kriterleri

- **Unit Testler (`test/unit/`):** Domain use-case'leri, para hesabı, pay/payda birim dönüşümleri ve sepet indirim mantığı için %100 kapsam hedeflenir.
- **Repository / DAO Testleri (`test/data/`):** Drift in-memory SQLite üzerinde transaction atomikliği, eksi stok serbestliği ve `idempotency_key` mükerrerlik testleri yapılır.
- **Integration Testler (`integration_test/`):** Barkod okutma, sepet satırı artırma, nakit para üstü hesaplama ve fiş kesme uçtan uca doğrulanır.

