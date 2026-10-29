# GEMINI.md — Antigravity / Gemini Çalışma Yönergeleri

Bu belge, **Google Antigravity IDE** ve bu ortamda çalışan **Gemini** modeli için özel çalışma talimatlarını belirler.

---

## 1. Ortak Kurallara Erişim

Antigravity ortamında projenin ana kuralları tek doğruluk kaynağı olan [`AGENTS.md`](./AGENTS.md) ve [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](./MARKET_POS_AI_STUDIO_BUILD_PLANI.md) (**v1.2**) belgelerinde tanımlıdır. 

Proje ürün konsepti **Market Management System (MMS)**'dir. Teknik klasör adı `market-pos` olarak korunur.

> [!NOTE]
> Antigravity IDE, kök dizindeki `AGENTS.md` ve `GEMINI.md` dosyalarını otomatik olarak bağlama dahil eder. Alt dizinlerdeki detay kurallar ise (`docs/ai/rules/*.md`) doğrudan bu dosyalardaki bağlantılar üzerinden gerektiğinde okunur.

---

## 2. Gemini İçin Çalışma Protokolü

Herhangi bir görev icra edilirken şu adımlar sırasıyla uygulanmalıdır:

1. **Bağlamı ve Durumu İncele:**
   - Göreve başlamadan önce [`docs/PROJECT_STATUS.md`](./docs/PROJECT_STATUS.md) okunarak projenin aktif fazı (şu anda **Faz 0**) ve izin verilen işlem sınırları kontrol edilir.
2. **Kullanıcı İsteğini Analiz Et:**
   - İstek doğrudan kod üretmeyi içerse dahi, ilgili fazın kabul kriterleri ve iş kuralları netleşmeden kod yazımına başlanmaz.
3. **Değişiklik Öncesi İnceleme:**
   - Değiştirilecek veya oluşturulacak dosyaların mevcut durumu, etkileyeceği diğer modüller tespit edilir.
4. **İşlem ve Doğrulama Raporu Sunma:**
   - Yapılan her değişiklikten sonra etkilenen dosya yolları, içerik durumu ve doğrulama sonuçları kullanıcıya raporlanır.
5. **Kullanıcı Onayı Sınırı:**
   - Kullanıcının açık onayı olmadan mimari kararlar değiştirilemez, faz atlanamaz veya uygulama kodlamasına geçilemez.

---

## 3. İlgili Belgelerin Okunma Kriterleri

- **İş kuralları veya mimari bir konu ele alınırken:** [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) ve [`docs/ai/rules/clean-architecture.md`](./docs/ai/rules/clean-architecture.md).
- **Veritabanı, transaction ve senkronizasyon adımlarında:** [`docs/ai/rules/offline-first.md`](./docs/ai/rules/offline-first.md).
- **Yetkilendirme, RLS ve veri güvenliğinde:** [`docs/ai/rules/security.md`](./docs/ai/rules/security.md).
- **Test yazımında:** [`docs/ai/rules/testing.md`](./docs/ai/rules/testing.md).
- **Yeni mimari kararlar alındığında:** [`docs/decisions/ADR_TEMPLATE.md`](./docs/decisions/ADR_TEMPLATE.md) şablonu kullanılarak kayıt açılır.
