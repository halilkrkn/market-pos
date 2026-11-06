# AGENTS.md — MARKET MANAGEMENT SYSTEM (MARKET MMS)
# Merkezi Proje Anayasası ve Ortak Yapay Zekâ Geliştirme Kuralları

Bu belge, **MARKET MANAGEMENT SYSTEM (MARKET MMS)** projesinde görev alan tüm yapay zekâ asistanları (Antigravity, Gemini, Claude, Copilot vb.) ve insan geliştiriciler için **araçtan bağımsız, birincil ve bağlayıcı ortak anayasadır**.

---

## 1. Project Overview (Proje Genel Bakışı)

- **Resmi Ürün Adı:** **MARKET MANAGEMENT SYSTEM (MARKET MMS)**
- **Repository / Klasör Adı:** `market-pos` (Geriye dönük teknik uyumluluk için korunmaktadır).
- **Ürün Konsepti:** Küçük ve orta ölçekli perakende marketlerin günlük satış, dinamik sepet, stok, fiyat, barkod, dashboard ve kasa operasyonlarını kesintisiz yönetmek üzere tasarlanmış profesyonel bir **Market Yönetim SaaS Platformudur**.
- **Donanımsal Sınır (Banka POS Sınırı):** MARKET MMS bir banka POS cihazı değildir. Banka POS terminallerine (Ingenico, Beko vb.) tutar gönderme, mali donanımsal iletişim ve harici banka entegrasyonları **MVP kapsamı dışındadır**. Tutar POS cihazına gerekirse elle girilir.
- **Pilot Mimari Hedefi:** Pilot aşamada **Windows Local Master Hub** mimarisi esastır. Sistem, mağaza içinde internet bağlantısı kopsa dahi yerel ağda tam yetkiyle çalışır.
- **Ana ve Bağlayıcı Doküman:** [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](./MARKET_POS_AI_STUDIO_BUILD_PLANI.md) (**v1.4**, 6 Kasım 2026).
- **Canlı Proje Durumu:** [`docs/PROJECT_STATUS.md`](./docs/PROJECT_STATUS.md).

---

## 2. Technology Stack (Onaylanmış Teknoloji Yığını)

Projede yalnızca mimari olarak doğrulanmış ve kod tabanında aktif olan teknolojiler kullanılır. Kullanılmayan veya ertelenen teknolojiler aktif stack gibi gösterilemez:

| Katman / Rol | Onaylanmış Teknoloji | Not ve Durum |
|---|---|---|
| **İstemci Çerçevesi** | Flutter (Dart SDK 3.13.x+, Flutter SDK 3.47.x+) | Windows masaüstü (`market_pos.exe`), Android ve iOS ortak istemci tabanı |
| **Uç / Yerel Depolama** | Drift + SQLite (WAL Modu) | Windows'ta `%LOCALAPPDATA%\MarketMMS\client_local.db`, mobil cihazlarda `mms_client.db` (`packages/mms_client_storage`) |
| **Merkezi Sunucu API (Pilot)**| Dart Shelf HTTPS API | Bağımsız Dart backend çalıştırılabilir dosyası (`%PROGRAMDATA%\MarketMMS\bin\mms_backend.exe`, `test_spikes/spike_01_backend`) |
| **Merkezi Depolama (Pilot)**| Merkezi SQLite (WAL Modu, Tekil Yazıcı) | `%PROGRAMDATA%\MarketMMS\data\market_master.db` (Yalnızca Windows Service erişir) |
| **Windows Servis Sarmalayıcı**| WinSW (Windows Service Wrapper) | `MarketMMSService` arka plan servisi kurulumu ve otomatik kurtarma |
| **Durum Yönetimi** | Riverpod | Test edilebilir, reaktif durum yönetimi |
| **Navigasyon** | go_router | Deklaratif yönlendirme ve derin bağlantı uyumu |
| **Barkod Girişi** | PC'de USB HID (Klavye taklidi); Mobilde Kamera | Otomatik ürün bulma ve sepet oluşturma |
| **Harici Yedekleme** | Google Drive API (`drive.file`) | Canlı senkronizasyon için DEĞİL; bağımsız şifreli SQLite anlık görüntüsü için |
| **Gelecek SaaS Hedefi** | PostgreSQL / Supabase | Çok şubeli zincir ve bulut SaaS fazı için veri modeli uyumlu tutulur; **pilot aşamasında aktif değildir** |

---

## 3. Architecture Rules (Mimari ve Kod Organizasyonu Standartları)

- **Mimari Model:** Paket tabanlı, modüler ve **Feature-First + Clean Architecture** yaklaşımı uygulanır.
- **Bağımlılık Yönü İlkesi:**
  $$\text{presentation} \longrightarrow \text{application} \longrightarrow \text{domain} \longleftarrow \text{data} \longleftarrow \text{infrastructure}$$
  Dış katmanlar iç katmanlara bağımlı olabilir; iç katmanlar dış katmanlardan tamamen habersizdir.
- **Domain Katmanı:** Saf Dart ile yazılır. Kesinlikle `flutter/material.dart`, Drift, SQLite, Shelf veya Supabase kütüphanelerine bağımlı olamaz. Entity, value object ve repository sözleşmelerini (ports) barındırır.
- **Data & Infrastructure Katmanları:** Domain repository arayüzlerinin somut sınıflarını (adapters), Drift DAO tablolarını ve Windows Master Hub HTTP/REST istemcisini barındırır.
- **Presentation Katmanı:** Ekranlar, responsive widget'lar ve Riverpod provider'larını içerir. UI katmanı doğrudan veritabanı sorgusu veya HTTP çağrısı yapamaz; domain use-case ve sözleşmelerini tüketir.
- **SOLID ve Clean Code:** Her sınıf tek bir sorumluluk üstlenir (SRP). Fonksiyonlar net ve okunabilir tutulur.
- **YAGNI ve KISS:** Erken optimizasyonlardan, premature soyutlamalardan, yapay mikroservislerden ve kullanılmayan sınıf/paket enflasyonundan kesinlikle kaçınılır.

---

## 4. Data Integrity (Veri Bütünlüğü ve Finansal Kesinlik Kuralları)

Aşağıdaki veri bütünlüğü kuralları tüm katmanlarda bağlayıcıdır:

1. **Kuruş Tamsayı Standardı (`CONFIRMED`):** Para hesaplamalarında ve veri modellerinde kayan noktalı sayı (`double`) aritmetiği **KESİNLİKLE YASAKTIR**.
   - Tüm parasal tutarlar kuruş bazlı tamsayılarla (`BIGINT` / `int`) veya özel Value Object (`Money`) ile saklanır ve hesaplanır (Örnek: 150.50 TL = `15050` kuruş).
2. **Snapshot Fiyat ve İsim:** Satış tamamlandığında, ürünün satış anındaki birim fiyatı ve adı `sale_items` satırına snapshot olarak kopyalanır. Ürünün gelecekte fiyatının değişmesi geçmiş satışları etkileyemez.
3. **Atomik Yerel Transaction:** Bir satış tamamlandığında; satış kaydı (`sales`), sepet satırları (`sale_items`), stok düşüş hareketi (`stock_movements`) ve senkronizasyon kuyruk kaydı (`sync_operations` / `outbox_operations`) **aynı yerel transaction içinde atomik olarak** işlenir. Kısmi yazım kesinlikle engellenir.
4. **Geçmişin Korunması ve Fiziksel Satış Dokunulmazlığı:** Gerçekleşmiş fiziksel satış kayıtları stok çakışması veya ağ senkronizasyonu gerekçesiyle **ASLA SİLİNEMEZ**. Satış ve stok hareketleri append-only tutulur; iptal ve iadeler ters hareketlerle (`CANCELLED`, `REFUND`) izlenir.
5. **Idempotency Koruması:** Her satış ve kuyruk işlemi cihazda üretilen benzersiz bir `idempotency_key` (UUID v4) taşır. Ağ tekrarında sunucu ikinci bir satış veya mükerrer stok düşüşü oluşturamaz.
6. **Eksi Stok ve Uyuşmazlık Yönetimi:** Eksi stok politikası `allow` olup, raftan fiziksel satışın faturadan önce yapılabilmesine izin verilir. Oluşan stok uyuşmazlıkları `audit_logs` tablosuna yazılır ve dashboard'da düzeltme bildirimi olarak sunulur.
7. **Alt Kuruş Yuvarlama Kararı (`OPEN DECISION`):** Kesirli miktar, gramaj veya birim maliyet çarpmalarında ortaya çıkabilecek alt kuruşların yuvarlama yöntemi (Half-Up vb.) proje sahibi tarafından henüz onaylanmamış olup **`OPEN DECISION`** statüsündedir; onaylanmamış bir yuvarlama yöntemi kesinleşmiş kural olarak uygulanamaz.

---

## 5. Offline-First ve Senkronizasyon Standartları

- **Ayrık Veritabanı Modeli (Dual SQLite):**
  - Merkezi master veritabanı: `%PROGRAMDATA%\MarketMMS\data\market_master.db` (Yalnızca Windows backend servisi doğrudan erişir).
  - Masaüstü uç veritabanı: `%LOCALAPPDATA%\MarketMMS\client_local.db` (Windows Flutter UI buraya bağlanır).
  - Mobil uç veritabanı: Android ve iOS cihazların yerel `mms_client.db` veritabanı.
- **Masaüstü Arayüz İzolasyonu:** Windows Flutter masaüstü kullanıcı arayüzü, sunucu veritabanı dosyasına (`market_master.db`) doğrudan **ASLA ERİŞEMEZ**. Yerel loopback API (`http://127.0.0.1:<port>`) üzerinden haberleşir.
- **Windows Kapalıyken Çalışma:** Windows Service kapalı veya ulaşılamaz olduğunda dahi, Windows masaüstü arayüzü ve mobil telefonlar kendi yerel Drift SQLite veritabanlarında satış yapmaya devam eder; işlemler yerel Outbox kuyruğuna yazılır.
- **Topoloji:** Mobil cihazlar birbirleriyle doğrudan senkronize olmaz. Tüm istemciler mağaza içi yerel Wi-Fi / LAN üzerinden Windows Master Hub API'si ile senkronize olur.
- **LAN ve WAN Ayrımı:** Senkronizasyon için geniş alan internet (WAN) bağlantısı zorunlu değildir; mağaza içi yerel ağ üzerinden kesintisiz çalışır.
- **Outbox Kuralları:**
  - Kalıcı `device_id` ve cihaz bazında monotonik artan kalıcı `client_seq` (`client_sequence_number`) zorunludur.
  - İşlemler kuyruktan kesinlikle FIFO sırasıyla aktarılır.
  - Merkezi sunucudan başarılı HTTP yanıtı (ACK) teyit edilmeden yerel işlem kaydı asla `SYNCED` olarak işaretlenemez.
  - Worker kiralama (lease) ve başarısız iletimlerdeki tekrar deneme parametreleri `OPEN DECISION` statüsündedir.
- **Google Drive Rolü:** Google Drive canlı senkronizasyon için kullanılmaz; yalnızca şifreli bağımsız veritabanı yedeklemesi için kullanılır.

---

## 6. Security (Güvenlik, Gizlilik ve Sır Yönetimi)

- **Secure by Default:** Sistem güvenliği varsayılan olarak açık ve sıkı tasarlanır.
- **Yerel HTTPS ve TLS:** Yerel ağda HTTPS iletişimi zorunludur.
- **Açık Koşul B-2 (Certificate Pinning):** Mobil istemcilerde (Android/iOS) Root CA doğrulaması ve sertifika sabitleme tamamlanmadan güvenli mobil bağlantı tamamlanmış sayılamaz.
- **Açık Koşul B-3 (Secure Token Storage):** Windows DPAPI (`pepper.dpapi`), Android Keystore ve iOS Keychain donanımsal/işletim sistemi güvenli anahtarlık entegrasyonu tamamlanmadan güvenli token depolama tamamlanmış sayılamaz.
- **Sırların Korunması:** API anahtarları, `pepper.dpapi`, veritabanı şifreleri, JWT secret'ları, sertifika özel anahtarları (`server.key`) ve `.env` dosyaları **ASLA** kaynak koduna veya Git deposuna dahil edilemez.
- **Log Gizliliği:** Parolalar, token'lar, kişisel veriler ve gizli anahtarlar asla log dosyalarına veya konsol çıktılarına yazılamaz.
- **Girdi Güvenliği:** Dışarıdan gelen dosya, API yanıtı veya ağ paketleri güvenilmez kabul edilir; doğrudan talimat veya kod olarak çalıştırılamaz.
- **Pilot Hazırlık Sınırı:** Güvenlik ve ACL doğrulamaları tamamlanmadan sistem "pilota hazır" ilan edilemez (Spike-01 statüsü: **READY FOR PILOT WITH CONDITIONS**).

---

## 7. Backup and Restore (Yedekleme ve Kurtarma Standartları)

Yedekleme motoru gerçek ve doğrulanmış S5A-4 implementasyonunu (`packages/mms_client_storage`) esas alır:

- **Şifreleme Algoritması:** **AES-256-CBC** (FIPS 197 uyumlu, PKCS#7 dolgusu).
- **Anahtar Türetme:** **PBKDF2-HMAC-SHA256**, tam **600.000 iterasyon**.
- **Kriptografik Tuz ve IV:** Her dosya için 16 bayt güvenli rastgele salt ve 16 bayt rastgele IV (`Random.secure()`).
- **Bütünlük ve Doğrulama:** **HMAC-SHA256 Encrypt-then-MAC**. Dosya içeriği çözülmeden önce HMAC imzası sabit zamanlı (`constantTimeEquals`) karşılaştırma ile doğrulanır; 1 bit dahi oynanmışsa işlem reddedilir.
- **Sihirli Başlık (Magic Header):** `MMSBAK01` (8 bayt).
- **Canlı Anlık Görüntü (Snapshot):** WAL modu aktifken ham SQLite dosyaları doğrudan kopyalanamaz; atomik `VACUUM INTO` işletilir.
- **Geri Yükleme Güvenliği:** Geri yükleme öncesinde canlı güvenlik yedeği (safety snapshot) alınır ve `PRAGMA integrity_check;` çalıştırılır. Bekleyen Outbox işlemleri korunur.

---

## 8. Testing Strategy (Test ve Kalite Güvencesi)

- **Test-First (TDD) Zorunluluğu:** Yeni bir iş kuralı veya finansal işlem geliştirilmeden önce testi yazılır (Red-Green-Refactor).
- **Kritik Test Kapsamı:** Para hesabı, atomik transaction, eksi stok serbestliği, idempotency ve senkronizasyon kuyruğu unit ve entegrasyon testleriyle doğrulanır.
- **Gerçek FFI SQLite Zorunluluğu:** SQLite WAL eşzamanlılığı, `PRAGMA busy_timeout = 5000;`, kaza kurtarma (crash recovery) ve çoklu işlem kilitlenmesi testlerinde **gerçek FFI SQLite sürücüsü zorunludur**; in-memory sahte mock'lar SQLite concurrency davranışını test edemez.
- **Doğruluk Beyanı İlkesi:** Otomatik testler fiilen çalıştırılıp çıktısı terminalde görülmeden "testler geçti" iddiasında bulunulamaz. Test sonuçları gerçek komut çıktılarıyla raporlanır.
- **Gereksiz Test Üretmeme:** Yalnızca gerçek iş kuralları ve riskli alanlar test edilir; framework'ün kendi widget çizimini veya standart getter/setter'ları test eden yapay test enflasyonundan kaçınılır.

---

## 9. Error Handling and Logging (Hata Yönetimi ve Günlükleme)

- **Hataları Yutmama İlkesi:** Hatalar sessizce geçiştirilemez (`catch (e) {}` kesinlikle yasaktır).
- **Kullanıcı Dostu Mesajlar:** Kullanıcı arayüzüne teknik stack trace veya ham SQL hataları yansıtılamaz; anlaşılır Türkçe hata mesajları sunulur.
- **Hata Sınıflandırması:** Geçici ağ hataları (`RETRY`) ile kalıcı şema/veri hataları (`FAILED_PERMANENT`) birbirinden ayrılır.
- **Sistematik Hata Analizi:** Beklenmeyen sistem arızalarında semptom bastırmak yerine 4 fazlı Kök Neden Analizi (RCA) işletilir.

---

## 10. Documentation Standards (Dokümantasyon İlkeleri)

- **Kanonik Fihrist:** Proje dokümantasyonu `docs/` klasörü altında tutulur.
- **Mimari Karar Kayıtları (ADR):** Mimariyi değiştiren her karar [`docs/decisions/ADR_TEMPLATE.md`](./docs/decisions/ADR_TEMPLATE.md) şablonu kullanılarak belgelenir.
- **Canlı Proje Takibi:** Aktif faz ve aşama durumu yalnızca [`docs/PROJECT_STATUS.md`](./docs/PROJECT_STATUS.md) üzerinden izlenir ve güncellenir.
- **Şeffaflık İlkesi:** Tamamlanmamış işler asla tamamlanmış gibi gösterilemez. Onaylanmamış teknik konular `OPEN DECISION` veya `PROPOSED` olarak etiketlenir.

---

## 11. Skills Integration (Aktif Beceri Altyapısı ve Tetiklenme Kuralları)

Projede, proje sahibi tarafından onaylanmış ve lisanslanmış **5 çekirdek beceri** [`.agents/registry/SKILL_REGISTRY.md`](./.agents/registry/SKILL_REGISTRY.md) altında aktiftir:

1. **`code-quality`** ([`.agents/skills/code-quality/SKILL.md`](./.agents/skills/code-quality/SKILL.md)):
   - *Tetiklenme:* Dart/Flutter kodu yazılırken, domain entity ve use-case tasarlanırken, refactoring ve kod inceleme yapılırken.
   - *Kapsam:* Clean Architecture sınırları, saf Dart domain, immutability, kuruş tamsayı ve anti-overengineering.
2. **`test-first`** ([`.agents/skills/test-first/SKILL.md`](./.agents/skills/test-first/SKILL.md)):
   - *Tetiklenme:* Yeni iş kuralı, sepet hesaplamaları, stok hareketleri, para matematiği veya outbox kuyruğu geliştirilirken.
   - *Kapsam:* Sıkı TDD Red-Green-Refactor döngüsü, risk temelli testler.
3. **`systematic-debugging`** ([`.agents/skills/systematic-debugging/SKILL.md`](./.agents/skills/systematic-debugging/SKILL.md)):
   - *Tetiklenme:* Başarısız testler, SQLite WAL kilitlenmesi, senkronizasyon aksamaları veya beklenmeyen sistem arızalarında.
   - *Kapsam:* 4 fazlı Kök Neden Analizi (RCA), hipotez doğrulama, sistematik düzeltme.
4. **`flutter-ui-standards`** ([`.agents/skills/flutter-ui-standards/SKILL.md`](./.agents/skills/flutter-ui-standards/SKILL.md)):
   - *Tetiklenme:* Kasa ekranı, responsive widget'lar, POS tuş takımı veya masaüstü/mobil arayüz tasarlanırken.
   - *Kapsam:* Dokunmatik kasa buton ergonomisi ($\ge 48\times 48\text{ dp}$), tabular monospace para hizalaması, USB HID klavye/barkod odak yönetimi, yüksek kontrast.
5. **`documentation`** ([`.agents/skills/documentation/SKILL.md`](./.agents/skills/documentation/SKILL.md)):
   - *Tetiklenme:* Mimari kararlar alınırken, ADR yazılırken, faz durum veya kabul raporları hazırlanırken.
   - *Kapsam:* Kanonik dokümantasyon bakımı, ADR şablonları, iş kuralı izlenebilirliği.

> [!IMPORTANT]
> **Kademeli Yükleme (Progressive Disclosure):** Beceriler her görevde körlemesine topluca çağrılamaz; yalnızca ilgili iş başladığında seçici olarak referans alınır. Beceriler kural ezemez, `AGENTS.md` anayasasına tabidir.

---

## 12. Development Workflow (Faz Bazlı Geliştirme Protokolü)

Herhangi bir geliştirme görevinde sırasıyla şu adımlar izlenir:
1. **Bağlam ve Gereksinim Analizi:** [`docs/PROJECT_STATUS.md`](./docs/PROJECT_STATUS.md) ve [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](./MARKET_POS_AI_STUDIO_BUILD_PLANI.md) okunarak aktif faz sınırları belirlenir.
2. **Mimari Değerlendirme:** Etkilenecek bileşenler ve Clean Architecture katmanları tespit edilir.
3. **Uygulama ve Test Planı:** Geliştirme adımları ve test senaryoları tasarlanır.
4. **Kullanıcı Onayı:** Kullanıcı onayı alınmadan mimari değişiklik yapılamaz, uygulama kodlamasına başlanamaz.
5. **Kapsamlı Uygulama:** Yalnızca onaylanan kapsamda kod yazılır.
6. **Otomatik Doğrulama:** `flutter test`, `flutter analyze` ve gerekirse build komutları çalıştırılır.
7. **Raporlama:** Yapılan değişiklikler, etkilenen dosyalar ve test çıktıları kullanıcıya sunulur.
8. **Faz Kabulü:** Faz kabul kararı kullanıcıya bırakılır.

---

## 13. Git Automation Rules (Git Yönetimi ve Otomasyon Kuralları)

> [!CRITICAL]
> **Faz Kabul ve Commit Yetkisi Yalnızca Proje Sahibine Aittir.**
> Kullanıcı açıkça kabul onayı vermeden hiçbir staging (`git add`), commit veya push işlemi yapılamaz.

Kullanıcı bir fazı kabul ettikten ve commit talimatı verdikten sonra aşağıdaki 10 adımlı otomasyon protokolü işletilir:
1. **Branch Kontrolü:** `git branch --show-current` ile doğru dalda (`main`) olunduğu doğrulanır.
2. **Uzak Depo ve Ağaç Kontrolü:** `git remote -v` ve `git status` çıktıları incelenir.
3. **Kalite Doğrulaması:** `flutter test` ve `flutter analyze` tam yeşil olmalıdır.
4. **Güvenlik ve Hijyen Taraması:** `.env`, `pepper.dpapi`, veritabanı, WAL/SHM, WinSW ikilileri veya secret dosyalarının stage edilmediği doğrulanır.
5. **Dosya Bazlı İnceleme:** Değişen her dosya `git diff` ile incelenir.
6. **Açık Staging:** `git add .` veya `git add -A` **KESİNLİKLE KULLANILMAZ**. Yalnızca incelenmiş dosyalar tek tek stage edilir (`git add path/to/file`).
7. **Atomik Commit:** Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`) standardında anlamlı commit mesajı yazılır.
8. **Push:** `git push origin main` çalıştırılır.
9. **Push Teyidi:** `git status` ile dalın `origin/main` ile eşitlendiği doğrulanır.
10. **Yürütme Raporu:** Commit hash'i ve stage edilen dosyalar raporlanır.

**Yasaklı Git Eylemleri:**
- Force push (`git push --force`) kesinlikle yasaktır.
- Git commit geçmişini yeniden yazmak (`rebase -i`, `reset --hard`) yasaktır.
- Her küçük aşama için otomatik tag oluşturulamaz; tag yalnızca büyük ana kilometre taşlarında (ör. `v1.1.0-windows-client-foundation`) proje sahibi onayıyla açılır.

---

## 14. Forbidden Actions (Yasaklı Eylemler Listesi)

Aşağıdaki eylemler tüm yapay zekâ asistanları için **kesinlikle yasaktır**:
1. Kullanıcının açık onayı olmadan kaynak kodu değiştirmek veya yeni kod dosyası oluşturmak.
2. Kullanıcının açık onayı olmadan mimari kararları değiştirmek.
3. Kullanıcı adına faz veya aşama kabulü ilan etmek.
4. Fiilen komut çalıştırmadan testlerin geçtiğini veya derlemenin başarılı olduğunu iddia etmek.
5. Fiziksel cihaz testi yapmadan mobil donanım veya ağ özelliklerinin doğrulandığını iddia etmek.
6. Secret, token, şifre, `pepper.dpapi` veya sertifika özel anahtarlarını depoya eklemek.
7. `git add .` veya force push çalıştırmak.
8. Projede onaylanmamış yeni teknolojileri (farklı veritabanı, alternatif framework vb.) kendiliğinden projeye eklemek.
9. YAGNI ve KISS ilkelerini ihlal ederek gereksiz soyutlama ve aşırı mühendislik yapmak.
10. Tamamlanmamış veya koşullu işleri tamamlanmış gibi göstermek.

---

## 15. Phase Acceptance (Faz Kabul Standartları)

Bir geliştirme fazı ancak ve ancak aşağıdaki koşulların tamamı sağlandığında kabul edilmiş sayılır:
1. Faz kapsamındaki tüm iş gereksinimleri ve kabul kriterleri eksiksiz karşılandığında,
2. İlgili tüm otomatik birim, entegrasyon ve analiz testleri %100 yeşil olduğunda,
3. Varsa açık kalan teknik riskler ve teknik borçlar şeffafça raporlandığında,
4. Etkilenen tüm dosya yolları listelendiğinde,
5. **Ve en önemlisi, Proje Sahibi açıkça "Kabul Edilmiştir" onayı verdiğinde.**

Yapay zekâ asistanları kendi kendilerine faz kabul edemez; her aşamanın nihai hakemi proje sahibidir.
