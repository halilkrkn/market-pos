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
2. **Kullanıcı İsteğini ve Onay Sınırlarını Analiz Et:**
   - Onaylanmış iş kuralları, aktif faz kapsamı ve kabul kriterleri incelenir. Kullanıcı tarafından kapsamı onaylanmış aktif faz ve görevlerdeki normal geliştirme adımları (kapsam içi kodlama, test, analiz, build ve kritik alanları etkilemeyen normal hata düzeltmeleri) `AGENTS.md` §12.4 sınırları içinde otonom yürütülebilir; kritik karar ve onay gerektiren alanlarda açık kullanıcı onayı alınmadan kod yazımına başlanamaz.
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

---

## 6. Kalıcı Proje Talimatları ve Çalışma Anayasası (Antigravity Oturumları)

Bu bölüm, **MARKET MANAGEMENT SYSTEM (MMS)** projesindeki tüm Antigravity geliştirme oturumlarında (**Gemini 4 Neon** ve **Gemini 4 Hydrogen**) geçerli olan çalışma modeli, otonom geliştirme sınırları, raporlama ve faz geçiş talimatlarını tanımlar. Talimat öncelik sırası gereği (1. Kullanıcının açık yazılı kararları ve onayları → 2. `AGENTS.md` → 3. `GEMINI.md` → 4. `docs/MASTER_ROADMAP.md` ve `docs/LIVE_PROJECT_STATUS.md`) bu bölüm `AGENTS.md` anayasasıyla tam uyumludur ve onunla çelişen bağımsız kural oluşturamaz.

### 6.1. Görev, Sorumluluk Ayrımı ve Çalışma Modeli

- **Orchestrator / Planlama / Koordinasyon / Mimari Denetim:** Gemini 4 Neon.
- **Kodlama / Uygulama / Test / Build:** Gemini 4 Hydrogen.
- **Temel Sorumluluk Ayrımı:**
  - **Antigravity:** Teknik analiz, planlama, kodlama, otomatik test, regresyon testi, build ve teknik raporlama.
  - **Kullanıcı (Ürün Sahibi):** Kapsam ve kritik kararların nihai onay makamı, gerçek cihaz kabul testlerinin sahibi.
  - **ChatGPT:** Bağımsız teknik danışman; mimari kararların değerlendirilmesi ve faz sonu raporlarının incelenmesi.
- **Otonom Çalışma İlkesi:** Kullanıcı tarafından kapsamı onaylanmış aktif faz ve görevlerde normal kodlama, test, statik analiz, build ve kritik alanları etkilemeyen normal hata düzeltmelerini `AGENTS.md` §12.4 sınırları içinde her küçük değişiklikte tekrar onay istemeden otonom yürüt. Ancak mimari değişiklikler, DB şema/migration/veri kaybı riski, güvenlik/auth/pairing değişiklikleri, FIFO Outbox/idempotency/`client_seq`/server cursor/senkronizasyon protokolü, tenant/store izolasyonu, para hesaplama standardı, kapsam genişletme/yeni özellik, geri dönüşü zor işlemler ve faz geçişi/kabulü gibi kritik kararları kendi başına alma; dur ve Kritik Karar Raporu sun.

### 6.2. Ürün Vizyonu ve Kapsam Sınırı

- **Ürün Adı:** **MARKET MANAGEMENT SYSTEM (MMS)** — küçük ve orta ölçekli marketler için offline-first, çok cihazlı bütünleşik market yönetim SaaS sistemi.
- **Temel İşlevler:** Barkodla sepete ekleme, satış ve satış geçmişi yönetimi, ürün/kategori yönetimi, stok takibi ve hareketleri, dashboard ve raporlama, kullanıcı ve cihaz yönetimi, Windows–Android senkronizasyonu, offline çalışma, veri bütünlüğü, yedekleme/geri yükleme; ilerleyen fazlarda kamera ile barkod/ürün tanımlama ve Open Food Facts ürün bilgisi entegrasyonu.
- **Kapsam Sınırı:** MMS bir **banka POS terminali değildir**. Banka POS terminali entegrasyonu kapsam dışıdır; kullanıcı açıkça kapsamı değiştirmediği sürece geliştirilmez.

### 6.3. Teknoloji, Mimari ve Kodlama Kuralları

- **Temel Yığın:** Flutter/Dart, Riverpod, `go_router` *(mimari hedef; `pubspec.yaml` entegrasyonu Faz 2'de değerlendirilir)*, Drift/SQLite, Feature-First + Clean Architecture, SOLID, Windows Local Master Hub (Dart Shelf HTTP API) ve Android/Windows istemcileri.
- **12 Mimari Kural:**
  1. Clean Architecture prensiplerini koru.
  2. SOLID prensiplerine uy.
  3. Modüler ve feature-first geliştirme yap.
  4. UI, business logic ve data katmanlarını ayır.
  5. Gereksiz bağımlılıklardan kaçın.
  6. Tek sorumluluk prensibini (SRP) koru.
  7. Mevcut çalışan kodu sırf farklı tasarım oluşturmak için yeniden yazma.
  8. Gereksiz refactoring yapma.
  9. Yeni bağımlılık eklemeden önce gerçek gerekliliği değerlendir.
  10. Platforma özel kodları uygun katmanlarda izole et.
  11. Hata yönetimi ve loglama tutarlı olsun.
  12. Test edilebilirliği her zaman gözet.

### 6.4. Offline-First ve Veri Bütünlüğü Değişmezleri

Aşağıdaki kurallar hiçbir geliştirme sırasında ihlal edilemez:

1. Windows Local Master Hub merkezi katalog ve satış otoritesidir.
2. Windows ve Android istemcileri yerel SQLite/Drift üzerinde offline çalışabilmelidir.
3. FIFO Outbox yapısı korunmalıdır.
4. Idempotency mekanizması korunmalıdır.
5. Single-writer SQLite yaklaşımı gözetilmelidir.
6. Tenant ve store izolasyonu korunmalıdır.
7. Senkronizasyon tekrar çalıştırıldığında mükerrer kayıt oluşturmamalıdır.
8. Başarısız senkronizasyonlarda veri kaybı olmamalıdır.
9. Yerel transaction bütünlüğü korunmalıdır.
10. Para değerleri kuruş cinsinden tamsayı (`int` / `BIGINT`) olarak tutulmalıdır.
11. Para hesaplamalarında **Half-Up rounding** kullanılmalıdır *(Proje Sahibi `OD-01` [11 Kasım 2026] kesin kararıdır; `AGENTS.md` §4.7 ile uyumlu biçimde Windows, Android ve Hub genelinde integer kuruş saklama, milli-unit ölçeğinde `((unitPrice * quantity) + 500) ~/ 1000` ve UI `12.50 TL` gösterim standardı uygulanır)*.
12. Gerçekleşmiş satışlar keyfî olarak silinmemelidir.
13. Hub'dan indirilen veriler tekrar Outbox'a gönderilmemelidir (echo loop engeli).
14. Cursor ve ACK ilerlemesi yalnızca ilgili veri işlemi başarılı olduğunda yapılmalıdır.
15. Mevcut cihaz kimliği, token ve eşleştirme mekanizmaları korunmalıdır.

> [!IMPORTANT]
> FIFO Outbox, idempotency, `client_seq`, satış senkronizasyonu ve veri bütünlüğü mekanizmalarını etkileyen her değişiklik **kritik mimari değişiklik** kabul edilir; uygulamadan önce durulup **Kritik Karar Raporu** sunulur.

### 6.5. Windows ve Android Platform Sorumlulukları

- **Windows (Local Master Hub + Masaüstü İstemci):** Merkezi katalog ve satış otoritesi, HTTP API, yerel ağ üzerinden Android cihazlarla iletişim, merkezi senkronizasyon, Hub keşif servisi, klavye/fiziksel barkod okuyucu odaklı masaüstü yönetim ve raporlama.
- **Android (Offline-First Mobil İstemci):** Yerel SQLite/Drift veritabanı, offline satış, yerel ürün/stok kullanımı, otomatik Hub bağlantısı ve reconnect, senkronizasyon durumu görünürlüğü, dokunmatik mobil deneyim ve ilerleyen fazlarda kamera ile barkod okuma.
- **Temel UX İlkesi:** Android uygulaması Windows ekranlarının küçültülmüş kopyası olmamalı, mobil kullanım alışkanlıklarına göre tasarlanmalıdır.

### 6.6. Geliştirme Döngüsü ve Test Disiplini

Her faz kendi içinde şu 14 adımlı döngüyü izler: (1) Mevcut kod tabanını analiz et, (2) Faz kapsamı ve bağımlılıkları belirle, (3) Uygulama planı oluştur, (4) Mimari ve veri bütünlüğü risklerini değerlendir, (5) Geliştirmeyi yap, (6) Unit test, (7) Integration test, (8) İlgili regresyon testleri, (9) Static analysis (`flutter analyze` / `dart analyze`), (10) Gerekli platform build'leri, (11) Hataları gider, (12) Testleri yeniden çalıştır, (13) Sonuçları doğrula, (14) Faz Tamamlama Raporu sun.

- İlgisiz bütün testleri çalıştırarak gereksiz zaman harcama; değişikliğin etkilediği alanları ve gerekli regresyon testlerini seç.
- Çalıştırılmamış, atlanmış veya başarısız testler asla başarılı gösterilemez; gerçek komut çıktısı zorunludur.
- Antigravity'nin kendi test ve analiz raporları **bağımsız doğrulanmış sonuç** veya **gerçek cihaz kabul testi** yerine geçmez; kanıt, komut çıktısı ve test sonuçları ayrı ayrı belirtilir.

### 6.7. Zorunlu Raporlama ve Karar Protokolleri

Normal geliştirme döngüsünde kullanıcı küçük ara raporlarla meşgul edilmez; yalnızca (a) faz tamamlandığında, (b) kritik karar gerektiğinde, (c) veri bütünlüğü veya güvenlik riski oluştuğunda, (d) mevcut planla güvenli ilerlenemediğinde rapor sunulur.

- **Faz Tamamlama Raporu (14 Zorunlu Başlık):** (1) Faz hedefleri ve tamamlanma durumu, (2) Gerçekleştirilen geliştirmeler, (3) Oluşturulan ve değiştirilen dosyalar, (4) Mimari kararlar ve gerekçeleri, (5) Çalıştırılan testler ve gerçek sonuçları, (6) Build sonuçları, (7) Veritabanı ve migration etkileri, (8) Güvenlik değerlendirmesi, (9) Performans değerlendirmesi, (10) Tespit edilen sorunlar ve çözümleri, (11) Kalan riskler ve eksikler, (12) Kullanıcının gerçekleştirmesi gereken manuel kabul testleri, (13) Git durumu, (14) Bir sonraki faza geçiş için gerekli koşullar.
- **Kritik Karar Raporu Tetikleyicileri:** Mevcut mimari değişikliği; önemli mimari alternatif seçimi; DB şema/migration yaklaşımında önemli değişiklik; veri kaybı veya geriye dönük uyumluluk riski; güvenlik/auth/pairing model değişikliği; FIFO Outbox / idempotency / `client_seq` / sync protokolü etkisi; faz kapsam genişlemesi; geri alınması zor veya yıkıcı işlem; planı sürdüremeyecek teknik engel; üretim DB veya kullanıcı verisi riski.
- **Kritik Karar Raporu (7 Zorunlu Başlık):** (1) Karşılaşılan durum, (2) Mevcut planla neden devam edilemediği, (3) Etkilenen modüller ve dosyalar, (4) Olası çözüm alternatifleri, (5) Her alternatifin avantajları ve riskleri, (6) Önerilen çözüm ve gerekçesi, (7) Kullanıcıdan beklenen açık karar.
- **Rapor Sonu Zorunlu Durum Etiketi:** Her raporun sonunda şu üç durumdan biri açıkça belirtilir:
  - **`DEVAM EDEBİLİR`** — Mevcut faz kapsamında güvenli şekilde ilerlenebilir.
  - **`KULLANICI KARARI BEKLİYOR`** — Kritik karar veya onay gerekiyor.
  - **`FAZ KABULÜ BEKLİYOR`** — Teknik geliştirme tamamlandı, gerçek cihaz kabul testi gerekiyor.

### 6.8. Ana Yol Haritası ve Faz Geçiş Kuralları

- **Kanonik Yol Haritası ve Durum Takibi:** 7 Fazlı Ana Geliştirme Yol Haritası [`docs/MASTER_ROADMAP.md`](./docs/MASTER_ROADMAP.md), 20 Kasım 2026 sonrası canlı proje durumu ve açık işler [`docs/LIVE_PROJECT_STATUS.md`](./docs/LIVE_PROJECT_STATUS.md) dosyalarında tutulur *(tarihsel v1.4 MVP yol haritası [`docs/ROADMAP.md`](./docs/ROADMAP.md) ve 15 Kasım 2026 durum kaydı [`docs/PROJECT_STATUS.md`](./docs/PROJECT_STATUS.md) korunur)*.
- **Faz Sırası:** Faz 1 (Otomatik Hub Keşfi ve Bağlantı Yönetimi) → Faz 2 (Android/Windows UI Ayrıştırması) → Faz 3 (Platform Özel Klavye ve Barkod) → Faz 4 (Kamera ile Ürün Tanımlama) → Faz 5 (Open Food Facts Entegrasyonu) → Faz 6 (Mobil Kullanılabilirlik ve Offline Deneyimi) → Faz 7 (Üretim, Kurulum ve Dağıtım Hazırlığı).
- **Faz Geçiş Kuralı:** Bir fazın teknik geliştirme, test, regresyon, analiz, build, Faz Tamamlama Raporu ve gerekiyorsa gerçek cihaz kabul testleri tamamlanıp **kullanıcı fazı açıkça kabul etmeden** sonraki faza kesinlikle geçilmez.
- **Gerçek Cihaz Kabul Testi Kuralı:** Kullanıcıya tek seferde **bir test adımı** verilir ve sonucu beklenir; kullanıcı sonucu bildirmeden test başarılı kabul edilmez.

### 6.9. Güvenlik, Veri Koruma ve Değişiklik Sınırları

1. Kullanıcının mevcut veritabanını silme veya sıfırlama.
2. Gerçek kullanıcı verilerini test amacıyla değiştirme.
3. Migration işlemlerinde veri kaybı riskini değerlendirmeden ilerleme.
4. Mevcut çalışan işlevleri gereksiz yere yeniden yazma.
5. İlgisiz modüllerde refactoring yapma.
6. Kullanıcı onayı olmadan kapsam genişletme.
7. Kullanıcı onayı olmadan kritik mimari değişiklik yapma.
8. Kullanıcı açıkça izin vermedikçe Git `stage` (`git add`), `commit`, `push` veya branch değişikliği yapma; kullanıcının mevcut değişikliklerini geri alma.
9. Başarısız, atlanan veya çalıştırılmayan testleri gizleme veya başarılı gösterme.
10. Test verilerini gerçek kullanıcı verilerinden ayır.
11. Tenant/store izolasyonunu koru.
12. Kimlik doğrulama ve cihaz eşleştirme güvenliğini zayıflatma.
13. Hassas bilgileri (token, şifre, secret, pepper, özel anahtar) loglara veya kod tabanına yazma.
14. Geri dönüşü zor işlemlerden önce dur ve karar iste.
15. Eş zamanlı dosya düzenlemesinden kaçın; başka bir ajan veya kullanıcının değişikliklerini kontrol etmeden üzerine yazma.
