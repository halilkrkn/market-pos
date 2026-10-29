# AGENTS.md — Market POS (MMS) Ortak Yapay Zekâ Geliştirme Kuralları

Bu belge, **Market POS (Market Management System - MMS)** projesinde görev alan tüm yapay zekâ asistanları ve insan geliştiriciler için **araçtan bağımsız, birincil ve bağlayıcı ortak kurallar dizinidir**.

---

## 1. Ana Referans ve Proje Durumu

- **Ürün Konsepti:** **Market Management System (MMS)** — Profesyonel Market Yönetim SaaS Uygulaması. (Teknik klasör/proje adı olarak `market-pos` korunmaktadır).
- **Tek Bağlayıcı Proje Dokümanı:** [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](./MARKET_POS_AI_STUDIO_BUILD_PLANI.md) (**v1.2**, 30 Ekim 2026).
- **Mevcut Proje Durumu:** [`docs/PROJECT_STATUS.md`](./docs/PROJECT_STATUS.md) — **Faz 0: Planlama ve Mimari Kararlar**.
- **Yol Haritası:** [`docs/ROADMAP.md`](./docs/ROADMAP.md) — Faz 0–8 arası onaylanmış aşamalar.
- **Teknik Mimari Özeti:** [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md).

> [!IMPORTANT]
> Proje gereksinimleri, kapsamı veya mimarisine ilişkin herhangi bir kararda yalnızca `MARKET_POS_AI_STUDIO_BUILD_PLANI.md` belgesi geçerlidir. Bu belge ile çelişen hiçbir talimat, varsayım veya kod üretilemez.

---

## 2. Temel Çalışma Prensipleri

1. **Önce İş Kuralları, Sonra Kod:** İlgili modülün iş kuralları, veri sınırları ve kabul kriterleri dokümante edilmeden uygulama kodu yazılmaz.
2. **Faz Bazlı İlerleme:** Faz kabul kriterleri eksiksiz karşılanmadan ve kullanıcıdan açık onay alınmadan sonraki faza geçilmez. **Faz 0 tamamlanmadan Flutter/Dart kodlamasına başlanamaz.**
3. **Mimarinin Korunması:** Mimari kararlar keyfî olarak değiştirilemez. Değişiklik ihtiyacı doğarsa önce gerekçesi kullanıcıya sunulur, onay alınır ve mimari dokümanlar güncellenir.
4. **Kullanıcı Onayı İlkesi:** Dosya silme, mimariyi değiştirme veya faz geçişi gibi kritik adımlarda işlem öncesinde mutlaka kullanıcı onayı alınır.
5. **Gereksiz Karmaşıklıktan Kaçınma:** İlk sürümde ihtiyaç duyulmayan erken optimizasyonlar, yapay mikroservisler veya kullanılmayan soyutlamalar projeye dahil edilmez.
6. **Banka POS Sınırı:** Banka POS cihazı entegrasyonu ilk sürümün kapsamı dışındadır.

---

## 3. Mimari ve Kod Organizasyonu Sınırları

- **Mimari Model:** Feature-first + Clean Architecture.
- **Katman Bağımlılık Yönü:**
  $$\text{presentation} \longrightarrow \text{domain} \longleftarrow \text{data}$$
- **Domain Katmanı:** Entity, value object ve repository arayüzlerini içerir. Saf Dart ile yazılır; Flutter framework'üne, Drift veritabanına veya Supabase API'sine doğrudan bağımlılık içeremez.
- **Data Katmanı:** Domain repository arayüzlerinin somut implementasyonlarını, Drift yerel tablolarını, Supabase uzaktan veri kaynaklarını ve DTO eşlemelerini barındırır.
- **SOLID & Clean Code:** Her sınıf tek sorumluluk üstlenir; fonksiyonlar net ve okunabilir tutulur. Gereksiz soyutlama ve sınıf enflasyonundan kaçınılır.
- **Ayrıntılı Kurallar:**
  - Proje İlkeleri: [`docs/ai/rules/project-principles.md`](./docs/ai/rules/project-principles.md)
  - Clean Architecture: [`docs/ai/rules/clean-architecture.md`](./docs/ai/rules/clean-architecture.md)
  - SOLID İlkeleri: [`docs/ai/rules/solid.md`](./docs/ai/rules/solid.md)
  - Clean Code Standartları: [`docs/ai/rules/clean-code.md`](./docs/ai/rules/clean-code.md)

---

## 4. Çoklu Cihaz ve Offline-First Veri Bütünlüğü

- **Çoklu Cihaz Eşitliği:** Windows masaüstü bilgisayar ve mobil telefonlar aynı temel işlevleri (ürün, satış, stok, dashboard, raporlama) tam yetkiyle çalıştırır. Barkod okuma PC'de USB HID, mobilde kamera ile yapılır.
- **Yerel Veritabanı:** Mobil ve masaüstünde Drift + SQLite esastır. Web için platform uyumluluğu ve depolama mekanizması ayrıca doğrulanacaktır.
- **Yerel Transaction:** Satış, sepet detayları, ödeme ve stok hareketleri atomik transaction içinde işlenir.
- **Kalıcı İşlem Kuyruğu:** Çevrimdışı yapılan her işlem yerel kuyruğa yazılır; bağlantı sağlandığında merkezi veritabanına aktarılır.
- **Idempotency:** Satış işlemlerinde `idempotency_key` kullanılır; tekrarlanan isteklerin mükerrer satış veya stok düşümü yaratması engellenir.
- **Geçmişin Korunması:** Satış kayıtları stok çakışması nedeniyle silinemez. Stok hareketleri geçmişi sessizce değiştirilemez.
- **Ayrıntılı Kılavuz:** [`docs/ai/rules/offline-first.md`](./docs/ai/rules/offline-first.md)

---

## 5. Güvenlik, Çoklu Kiracı (Tenant) ve Gizlilik

- **Tenant İzolasyonu:** Her iş kaydı doğru tenant (ve gerekirse şube) ile ilişkilendirilir. İstemcinin ilettiği tenant kimliği tek başına güvenli kabul edilmez; Supabase Row Level Security (RLS) politikalarıyla korunur.
- **Gizli Bilgi Yasağı:** API anahtarları, şifreler, Google Drive OAuth sırları ve `.env` dosyaları asla kaynak koduna veya Git deposuna dahil edilmez.
- **Audit Kayıtları:** Kritik işlemler (fiyat değişimi, stok düzeltme, iade) denetim kayıtlarıyla izlenir.
- **Ayrıntılı Kılavuz:** [`docs/ai/rules/security.md`](./docs/ai/rules/security.md)

---

## 6. Test ve Doğrulama Beklentileri

- **Risk Temelli Test:** Kritik iş kuralları (para hesabı ve kesinlik doğrulaması, sepet toplamları, stok düşüşü, tenant yetki sınırları, senkronizasyon kuyruğu) unit ve entegrasyon testleriyle doğrulanır.
- **Hata Senaryoları:** Ağ kesintisi, yarıda kalan transaction, mükerrer barkod ve yetersiz stok senaryoları mutlaka test kapsamına alınır.
- **Ayrıntılı Kılavuz:** [`docs/ai/rules/testing.md`](./docs/ai/rules/testing.md)

---

## 7. Dosya Değişiklik ve Git Kuralları

- Dosya oluşturulmadan veya değiştirilmeden önce mevcut dosya içeriği incelenir.
- Yapılan değişiklikler ve doğrulama adımları her işlem sonunda raporlanır.
- Git commit mesajları Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`) standardına uygun yazılır.
