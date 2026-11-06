# GEMINI.md — Antigravity / Gemini Çalışma Yönergeleri

Bu belge, **Google Antigravity IDE** ve bu ortamda görev alan **Gemini** modeli için özel çalışma ve araç entegrasyon talimatlarını belirler.

---

## 1. Proje Kimliği ve Ana Kural Hiyerarşisi

- **Ürün Konsepti:** **MARKET MANAGEMENT SYSTEM (MARKET MMS)** — Profesyonel Market Yönetim SaaS Platformu.
- **Repository / Dizin:** `market-pos`.
- **Birincil Anayasa:** Projenin tek, birincil ve bağlayıcı ortak kurallar dizini kök dizindeki [`AGENTS.md`](./AGENTS.md) ve [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](./MARKET_POS_AI_STUDIO_BUILD_PLANI.md) (**v1.4**) belgeleridir.
- **Çelişki Yasağı:** `GEMINI.md`, `AGENTS.md` anayasasının bir kopyası değildir; onunla çelişen hiçbir bağımsız kural, varsayım veya mimari istisna üretemez. Herhangi bir çelişki tespit edildiğinde sessizce seçim yapılmaz, durum raporlanır ve proje sahibinin kararı beklenir.

> [!NOTE]
> **Antigravity Dosya Keşif Davranışı:**  
> Antigravity IDE ortamında kök dizindeki `AGENTS.md` ve `GEMINI.md` dosyaları sistem tarafından otomatik olarak çalışma bağlamına dahil edilir. Alt dizinlerdeki detay şartnameler (`docs/`), mimari kurallar (`docs/ai/rules/*.md`) ve beceri dosyaları (`.agents/skills/*`) ise otomatik yüklenmez; bu belgedeki ve `AGENTS.md` içindeki markdown bağlantıları üzerinden gerektiğinde taranır.

---

## 2. Gemini İçin Adım Adım Çalışma Protokolü

Gemini, kullanıcıdan gelen her talimatta aşağıdaki 5 adımlı disiplini tavizsiz uygular:

1. **Bağlamı ve Canlı Durumu İncele:**
   - Herhangi bir işleme başlamadan önce [`docs/PROJECT_STATUS.md`](./docs/PROJECT_STATUS.md) belgesi okunarak projenin aktif aşaması, tamamlanan bileşenler ve izin verilen operasyonel sınırlar teyit edilir.
2. **Kullanıcı İsteğini ve Kapsamı Analiz Et:**
   - İstek doğrudan uygulama kodu yazmayı içerse dahi, onaylanmış iş kuralları ve ilgili fazın kabul kriterleri incelenmeden, kullanıcıdan açık onay alınmadan kod yazımına başlanamaz.
3. **Değişiklik Öncesi Statik İnceleme:**
   - Değiştirilecek veya oluşturulacak dosyaların mevcut durumu, etkileyeceği diğer modüller ve Clean Architecture katman sınırları tespit edilir.
4. **Gerçek Doğrulama ve Rapor Sunma:**
   - Yapılan her değişiklikten sonra etkilenen dosya yolları, içerik durumu ve fiilen çalıştırılan testlerin gerçek terminal komut çıktıları raporlanır. Test çalıştırılmadan "testler geçti" iddiasında bulunulamaz.
5. **Kullanıcı Onayı Sınırına Saygı:**
   - Mimari kararlar değiştirilemez, yeni paket eklenemez, faz atlanamaz veya kullanıcı adına faz kabul edilemez.

---

## 3. Dokümantasyon Yönlendirme Haritası

Gemini, görev türüne göre aşağıdaki kanonik dokümanları referans alır:

- **Canlı Proje Durumu ve Faz Takibi:** [`docs/PROJECT_STATUS.md`](./docs/PROJECT_STATUS.md)
- **Teknik Mimari ve Sistem Tasarımı:** [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md)
- **Bağlayıcı Ana Plan ve Yol Haritası:** [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](./MARKET_POS_AI_STUDIO_BUILD_PLANI.md) (v1.4) ve [`docs/ROADMAP.md`](./docs/ROADMAP.md)
- **Geliştirici Kurulum ve Standartlar Kılavuzu:** [`docs/DEVELOPMENT_GUIDE.md`](./docs/DEVELOPMENT_GUIDE.md)
- **Ürün Kapsamı ve Modül Özeti:** [`docs/PROJECT_OVERVIEW.md`](./docs/PROJECT_OVERVIEW.md)
- **İş Kuralları ve Gereksinim Şartnamesi:** [`docs/requirements/BUSINESS_RULES_SPEC.md`](./docs/requirements/BUSINESS_RULES_SPEC.md)
- **Mimari Kurallar:**
  - Clean Architecture: [`docs/ai/rules/clean-architecture.md`](./docs/ai/rules/clean-architecture.md)
  - SOLID İlkeleri: [`docs/ai/rules/solid.md`](./docs/ai/rules/solid.md)
  - Clean Code: [`docs/ai/rules/clean-code.md`](./docs/ai/rules/clean-code.md)
  - Offline-First: [`docs/ai/rules/offline-first.md`](./docs/ai/rules/offline-first.md)
  - Güvenlik ve Yetkilendirme: [`docs/ai/rules/security.md`](./docs/ai/rules/security.md)
  - Test Stratejisi: [`docs/ai/rules/testing.md`](./docs/ai/rules/testing.md)
  - Proje İlkeleri: [`docs/ai/rules/project-principles.md`](./docs/ai/rules/project-principles.md)
- **Mimari Karar Kayıtları:** Yeni mimari kararlarda [`docs/decisions/ADR_TEMPLATE.md`](./docs/decisions/ADR_TEMPLATE.md) kullanılır.

---

## 4. Aktif Becerilerin (Agent Skills) Kullanım İlkeleri

Projede [`.agents/registry/SKILL_REGISTRY.md`](./.agents/registry/SKILL_REGISTRY.md) altında kayıtlı 5 çekirdek beceri aktiftir. Gemini, bu becerileri körlemesine değil, **Kademeli Yükleme (Progressive Disclosure)** prensibiyle yalnızca ilgili görevde kullanır:

- **`code-quality`** ([`.agents/skills/code-quality/SKILL.md`](./.agents/skills/code-quality/SKILL.md)): Dart/Flutter kodlaması, refactoring, Clean Architecture sınırları ve saf Dart domain modelleri geliştirilirken.
- **`test-first`** ([`.agents/skills/test-first/SKILL.md`](./.agents/skills/test-first/SKILL.md)): İş kuralları, para matematiği (kuruş bazlı), sepet, stok veya outbox senkronizasyonu için TDD uygulanırken.
- **`systematic-debugging`** ([`.agents/skills/systematic-debugging/SKILL.md`](./.agents/skills/systematic-debugging/SKILL.md)): Test hataları, SQLite WAL kilitlenmeleri, senkronizasyon aksamaları veya beklenmeyen arızalarda 4 fazlı Kök Neden Analizi (RCA) yürütülürken.
- **`flutter-ui-standards`** ([`.agents/skills/flutter-ui-standards/SKILL.md`](./.agents/skills/flutter-ui-standards/SKILL.md)): Kasa ekranı, buton ergonomisi ($\ge 48\times 48\text{ dp}$), tabular monospace para hizalaması ve USB HID barkod odak yönetimi tasarlanırken.
- **`documentation`** ([`.agents/skills/documentation/SKILL.md`](./.agents/skills/documentation/SKILL.md)): ADR oluşturulurken, faz açılış/kapanış veya kabul raporları belgelenirken.

---

## 5. Güvenlik, Git ve Açık Teknik Koşullar

1. **Açık Teknik Koşulların Korunması:**
   Aşağıdaki açık teknik maddeler tamamlanmış gibi gösterilemez (Spike-01 sonucu: **READY FOR PILOT WITH CONDITIONS**):
   - **B-2:** Mobil istemcilerde Root CA doğrulaması ve sertifika sabitleme (Certificate Pinning).
   - **B-3:** Windows DPAPI (`pepper.dpapi`), Android Keystore ve iOS Keychain güvenli token depolama.
   - **SCM:** Gerçek Windows Service Control Manager servis kurulum, başlatma, restart ve crash recovery testleri.
   - **ACL:** Standart Windows kullanıcısıyla `%PROGRAMDATA%\MarketMMS` gerçek erişim kontrol testleri.
   - **Mobil:** Fiziksel Android/iOS cihazlarla gerçek yerel Wi-Fi mDNS / QR eşleştirme testleri.
   - **Pairing:** Cihaz eşleştirme rotalarına özel token kısıtlama doğrulaması.
2. **Git Disiplini:**
   - Faz kabul edilmeden commit veya push yapılamaz.
   - `git add .` veya `git add -A` yasaktır; yalnızca açık dosya listesi kullanılır.
   - Force push veya commit geçmişi değişikliği kesinlikle yasaktır.
   - Secret, pepper, özel anahtar veya veritabanı dosyaları asla commit edilemez.
3. **Faz Kabulü:**
   - Yapay zekâ kendi kendine faz kabul edemez; kabul yetkisi yalnızca proje sahibine aittir.
