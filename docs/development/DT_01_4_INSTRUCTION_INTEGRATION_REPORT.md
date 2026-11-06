# DT-01.4: Instruction Infrastructure Integration Report

**Rapor Tarihi:** 6 Kasım 2026  
**Görev Kodu:** DT-01.4 (Merkezi Yapay Zekâ Talimat Altyapısı Entegrasyonu)  
**Kanonik Referanslar:** [`AGENTS.md`](../../AGENTS.md), [`GEMINI.md`](../../GEMINI.md), [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](../../MARKET_POS_AI_STUDIO_BUILD_PLANI.md) (v1.4)  
**Yazar/Model:** Antigravity (Pair Programming AI)  
**Değerlendirme Sonucu:** **TAM BAŞARILI (ALL PASS)** — Proje Sahibi İncelemesine ve Onayına Hazır

---

## 1. Yönetici Özeti

DT-01.4 kapsamında, MARKET MANAGEMENT SYSTEM (MMS) projesinin merkezi yapay zekâ anayasasını oluşturan kök [`AGENTS.md`](../../AGENTS.md) ve Antigravity/Gemini arayüz entegrasyonunu yöneten [`GEMINI.md`](../../GEMINI.md) dosyaları baştan sona yeniden yapılandırılmıştır.

Bu çalışma ile:
- Tüm yapay zekâ asistanları ve geliştiriciler için tekil, bağlayıcı ve araçtan bağımsız **Merkezi Proje Anayasası** tesis edilmiştir.
- Onaylanmış mimari kararlar (Windows Local Master Hub, dual SQLite, masaüstü loopback izolasyonu, kuruş bazlı tamsayı para standardı, S5A-4 AES-256-CBC yedekleme kriptografisi, 5 aktif beceri) talimatlara işlenmiştir.
- `AGENTS.md` ile `GEMINI.md` arasındaki yetki ve hiyerarşi netleştirilmiş; `GEMINI.md` bir kopya olmaktan çıkarılıp IDE yönlendirici talimatına dönüştürülmüştür.
- Faz kabul yetkisinin ve commit/push onayının **yalnızca proje sahibine ait olduğu** ve yapay zekâların kendi kendilerine faz kabul edemeyecekleri tartışmasız bir anayasal kural hâline getirilmiştir.
- Açık teknik koşullar (B-2, B-3, SCM, ACL, Mobil Wi-Fi, Eşleştirme Tokenı) tamamlanmamış olarak korunmuş, S5A-5 statüsü **READY FOR PILOT WITH CONDITIONS** olarak teyit edilmiştir.
- Kaynak koduna, testlere, paketlere, bağımlılıklara ve `.agents/` dosyalarına dokunulmamış; hiçbir Git işlemi (stage/commit/push) yürütülmemiştir (`git diff --cached` 0 bayttır).

---

## 2. Denetim ve Doğrulama Matrisi

| # | Denetim Maddesi | Hedef ve Doğrulama Standardı | Uygulanan Entegrasyon | Sonuç |
|:---:|:---|:---|:---|:---:|
| **1** | **Önceki AGENTS / GEMINI Durumu** | Eski Faz 0 çelişkileri, bayat Supabase pilot referansları ve eksik başlıkların analizi. | Eski içerik incelendi, geçerli kurallar korunup 15 ana başlık altında modernize edildi. | **PASS** |
| **2** | **Yeni AGENTS.md Bölüm Listesi** | 15 zorunlu başlığın (Bölüm 1'den 15'e) eksiksiz yapılandırılması. | 15 bölüm tam hiyerarşiyle ve bağlayıcı olarak yazıldı. | **PASS** |
| **3** | **GEMINI.md Entegrasyonu ve Hiyerarşi** | AGENTS.md'nin kopyası olmama, IDE keşif davranışına uyum, AGENTS.md'yi anayasa olarak tanıma. | GEMINI.md yönlendirici rehber olarak yapılandırıldı, çelişkili veya kopya kural üretilmedi. | **PASS** |
| **4** | **Beş Çekirdek Becerinin Entegrasyonu** | 5 aktif becerinin tetiklenme senaryolarının tanımlanması ve kademeli yükleme (progressive disclosure). | Beceriler tetiklenme koşullarıyla tanımlandı; körlemesine toplu çağırma engellendi. | **PASS** |
| **5** | **Git ve Kullanıcı Onay Kuralları** | Faz kabul yetkisinin kullanıcıya ait olması; `git add .` ve force push yasağı, 10 adımlı otomasyon. | Katı Git otomasyon protokolü belgelendi; DT-01.4'te Git komutu çalıştırılmadı. | **PASS** |
| **6** | **Mevcut Dokümantasyonla Tutarlılık** | DT-01.3 dokümanlarıyla (`BUILD_PLANI` v1.4, `ARCHITECTURE.md`, `PROJECT_STATUS.md`) tam uyum. | DB yolları, para tipleri ve yedekleme kriptografisi %100 senkronize edildi. | **PASS** |
| **7** | **Açık Teknik Koşulların Korunması** | B-2, B-3, SCM, ACL, Mobil Wi-Fi ve Pairing Token koşullarının tamamlanmamış kalması. | Koşullar açık olarak korundu; pilot öncesi zorunlu şartlar olarak mühürlendi. | **PASS** |
| **8** | **Değiştirilen Dosyaların İzolasyonu** | Yalnızca `AGENTS.md` ve `GEMINI.md` dosyalarının güncellenmesi. | Yalnızca belirtilen 2 dosya güncellendi; kod, test veya paketlere dokunulmadı. | **PASS** |
| **9** | **Git Status ve Diff Temizliği** | `git diff --cached` 0 bayt olmalı; hiçbir dosya stage edilmemelidir. | `git diff --cached` 0 bayt olarak doğrulandı. | **PASS** |
| **10** | **Proje Sahibi Faz Kabul Sınırı** | DT-01.4 teknik tamamlanmasının faz kabulü sayılmaması ilkesi. | Rapor ve yanıtta faz kabulünün yalnızca kullanıcıya ait olduğu açıkça vurgulandı. | **PASS** |

---

## 3. Ayrıntılı Değerlendirme Raporu

### 3.1. Önceki AGENTS / GEMINI Durumu Analizi
- **Önceki AGENTS.md:** 80 satırdan ibaretti; `MARKET_POS_AI_STUDIO_BUILD_PLANI.md` v1.2'ye ve Faz 0'a referans veriyordu. Supabase API'sini doğrudan data ve domain kurallarında anarak pilot aşamasındaki Windows Local Master Hub mimarisiyle çelişiyordu. Git commit mesajları dışında kapsamlı bir Git otomasyonu, yasaklı eylemler listesi veya beceri tetiklenme matrisi barındırmıyordu.
- **Önceki GEMINI.md:** 41 satırdan ibaretti; projeyi Faz 0 olarak gösteriyor, beceri altyapısını içermiyor ve Antigravity'nin gerçek dosya keşif davranışını tanımlamıyordu.
- **Uygulanan İyileştirme:** Eski belgelerdeki tüm geçerli ilkeler (Clean Architecture bağımlılık yönü, kuruş hassasiyeti, eksi stok serbestliği, fiziksel satışların silinmemesi, kullanıcı onayı) muhafaza edilmiş; yeni mimari gerçekler ve 15 zorunlu başlık eklenmiştir.

### 3.2. Yeni AGENTS.md Bölüm Hiyerarşisi
Yeni [`AGENTS.md`](../../AGENTS.md) 15 ana bölümden oluşmaktadır:
1. **1. Project Overview:** Ürün adı MARKET MMS, repo `market-pos`, SaaS konsepti, banka POS cihaz entegrasyonu dışılığı ve Windows Local Master Hub pilotu.
2. **2. Technology Stack:** Flutter/Dart, Drift + SQLite, Shelf HTTPS API (`bin\mms_backend.exe`), WinSW, Riverpod, go_router, USB HID/kamera, Google Drive.
3. **3. Architecture Rules:** Modüler Feature-first + Clean Architecture, Presentation $\rightarrow$ Application $\rightarrow$ Domain bağımlılık yönü, saf Dart Domain, YAGNI/KISS.
4. **4. Data Integrity:** Floating point yasağı, kuruş bazlı tamsayı (`BIGINT`/`int`) standardı, snapshot fiyat ve ad, atomik yerel transaction, fiziksel satış dokunulmazlığı, idempotency, eksi stok `allow` ve alt kuruş yuvarlama için `OPEN DECISION`.
5. **5. Offline-First:** Dual SQLite (`%PROGRAMDATA%\MarketMMS\data\market_master.db` vs `%LOCALAPPDATA%\MarketMMS\client_local.db` ve `mms_client.db`), loopback masaüstü izolasyonu, servis kapalıyken satış yapabilme, LAN vs WAN ayrımı, FIFO ve ACK şartı.
6. **6. Security:** Secure by default, yerel HTTPS, açık B-2 (Certificate Pinning) ve B-3 (DPAPI, Keystore, Keychain) koşulları, log ve Git sır yasağı, READY FOR PILOT WITH CONDITIONS sınırı.
7. **7. Backup and Restore:** S5A-4 doğrulanmış AES-256-CBC, PKCS#7, PBKDF2 600.000 iterasyon, HMAC-SHA256 Encrypt-then-MAC, `MMSBAK01` başlığı, `VACUUM INTO` ve koruyucu güvenlik yedeği.
8. **8. Testing Strategy:** TDD Red-Green-Refactor, gerçek FFI SQLite zorunluluğu, test çalıştırmadan iddiada bulunmama ilkesi.
9. **9. Error Handling and Logging:** Hataları yutmama, kullanıcı dostu mesajlar, geçici/kalıcı hata ayrımı, 4 fazlı RCA.
10. **10. Documentation Standards:** `docs/` kanonik fihristi, ADR zorunluluğu, `docs/PROJECT_STATUS.md` canlı takibi, şeffaflık ilkesi.
11. **11. Skills Integration:** 5 çekirdek becerinin (`code-quality`, `test-first`, `systematic-debugging`, `flutter-ui-standards`, `documentation`) tetiklenme senaryoları ve kademeli yükleme (progressive disclosure).
12. **12. Development Workflow:** 8 adımlı geliştirme döngüsü (kullanıcı onayı, test, analiz, rapor).
13. **13. Git Automation Rules:** Faz kabulü olmadan commit yapmama, `git add .` yasağı, force push yasağı, 10 adımlı açık staging ve commit protokolü.
14. **14. Forbidden Actions:** 10 maddelik kesin yapay zekâ yasaklar listesi.
15. **15. Phase Acceptance:** 5 maddelik kesin faz kabul kriterleri ve proje sahibi tekil onay yetkisi.

### 3.3. GEMINI.md İçeriği ve AGENTS.md İlişkisi
[`GEMINI.md`](../../GEMINI.md) dosyası, `AGENTS.md` anayasasını Antigravity IDE ve Gemini modeli için operasyonel hâle getiren odaklı bir yönlendirme rehberi olarak yapılandırılmıştır:
- Proje kimliğini tanımlar ve kök `AGENTS.md` belgesini tek doğruluk kaynağı (anayasa) olarak tayin eder.
- Antigravity IDE'nin gerçek dosya keşif davranışını açıklar (`AGENTS.md` ve `GEMINI.md` otomatik bağlama girer; diğer belgeler bağlantılar üzerinden talep edildikçe taranır).
- 5 adımlı çalışma disiplini (Bağlamı incele $\rightarrow$ İsteği analiz et $\rightarrow$ Değişiklik öncesi incele $\rightarrow$ Gerçek test çıktısıyla raporla $\rightarrow$ Kullanıcı onayına saygı duy).
- Kanonik dokümantasyon haritasına doğrudan bağlantılar sağlar.
- 5 çekirdek beceriyi listeler ve kullanım durumlarını açıklar.
- Açık teknik koşulların korunmasını ve Git otomasyon sınırlarını Gemini için bağlayıcı kılar.

### 3.4. Beş Beceri (Agent Skills) Entegrasyonu
`.agents/registry/SKILL_REGISTRY.md` altındaki 5 becerinin tamamı `AGENTS.md` ve `GEMINI.md` içine entegre edilmiştir:
- **`code-quality`:** Dart/Flutter kodu, Clean Architecture katman sınırları, saf Dart domain modelleri, refactoring.
- **`test-first`:** Yeni iş kuralları, para matematiği (kuruş), sepet, stok, outbox kuyruğu geliştirilirken TDD.
- **`systematic-debugging`:** Test hataları, SQLite WAL kilitlenmesi, senkronizasyon aksamaları ve beklenmeyen sistem arızalarında 4 fazlı RCA.
- **`flutter-ui-standards`:** Kasa ekranı, dokunmatik buton ergonomisi ($\ge 48\times 48\text{ dp}$), tabular monospace para hizalaması ve USB HID barkod odak yönetimi.
- **`documentation`:** Mimari kararlar (ADR), faz açılış/kapanış raporları ve izlenebilirlik güncellemeleri.
- **Kural:** Beceriler her istekte körlemesine çağrılamaz; kademeli yükleme (progressive disclosure) esastır.

### 3.5. Git ve Kullanıcı Onay Kuralları
- **Kesin Anayasal Kural:** Faz kabul yetkisi ve commit/push yetkisi **yalnızca proje sahibine aittir**.
- Kullanıcı açık onay vermeden staging (`git add`), commit veya push yapılamaz.
- `git add .` veya `git add -A` kullanılamaz; dosyalar tek tek incelenerek açık listeyle stage edilir.
- Force push ve commit geçmişini değiştirmek kesinlikle yasaktır.
- DT-01.4 oturumunda hiçbir Git otomasyonu fiilen çalıştırılmamış, kural yalnızca belgelenmiştir.

### 3.6. Mevcut Dokümantasyonla Tutarlılık
DT-01.3 kapsamında güncellenen kanonik belgelerle (`MARKET_POS_AI_STUDIO_BUILD_PLANI.md` v1.4, `docs/ARCHITECTURE.md`, `docs/PROJECT_STATUS.md`, `docs/ROADMAP.md` vb.) tam mutabakat sağlanmıştır:
- Merkezi veritabanı yolu: `%PROGRAMDATA%\MarketMMS\data\market_master.db`
- Masaüstü yerel veritabanı yolu: `%LOCALAPPDATA%\MarketMMS\client_local.db`
- Para temsili: Kuruş tamsayı (`BIGINT` / `int`) ve `double` yasağı
- Alt kuruş yuvarlama: `OPEN DECISION`
- Yedekleme şifrelemesi: AES-256-CBC, PKCS#7, PBKDF2 600k, HMAC-SHA256 Encrypt-then-MAC
- Outbox: Monotonik persistent `client_seq`, `device_id`, `idempotency_key`, FIFO, ACK şartı; worker lease/backoff için `OPEN DECISION`.

### 3.7. Açık Teknik Koşulların Korunması
Aşağıdaki 6 teknik koşul hem `AGENTS.md` hem de `GEMINI.md` içinde **açık ve tamamlanmamış** olarak muhafaza edilmiştir:
1. **B-2:** Mobil istemcilerde Root CA doğrulama ve Certificate Pinning.
2. **B-3:** Windows DPAPI (`pepper.dpapi`), Android Keystore ve iOS Keychain güvenli token depolama.
3. **SCM:** Gerçek Windows Service Control Manager servis kurulum, başlatma, restart ve crash recovery testleri.
4. **ACL:** Standart Windows kullanıcısıyla `%PROGRAMDATA%\MarketMMS` gerçek erişim kontrol testleri.
5. **Mobil Wi-Fi:** Fiziksel Android/iOS cihazlarla gerçek yerel Wi-Fi mDNS / QR eşleştirme testleri.
6. **Pairing:** Cihaz eşleştirme rotalarına özel token kısıtlama doğrulaması.
- **S5A-5 Statüsü:** **READY FOR PILOT WITH CONDITIONS** olarak teyit edilmiştir.

---

## 4. Değiştirilen Dosyalar ve Git Durum Çıktıları

### Değiştirilen Dosyalar
- [`AGENTS.md`](file:///c:/Users/halil/Github/market-pos/AGENTS.md) (Güncellendi — Merkezi Proje Anayasası, 15 bölüm)
- [`GEMINI.md`](file:///c:/Users/halil/Github/market-pos/GEMINI.md) (Güncellendi — Antigravity / Gemini Araç Entegrasyon Rehberi)
- [`docs/development/DT_01_4_INSTRUCTION_INTEGRATION_REPORT.md`](file:///c:/Users/halil/Github/market-pos/docs/development/DT_01_4_INSTRUCTION_INTEGRATION_REPORT.md) (Oluşturuldu — Doğrulama Raporu)

### `git status --short`
```text
 M AGENTS.md
 M GEMINI.md
 M MARKET_POS_AI_STUDIO_BUILD_PLANI.md
 M README.md
 M docs/ARCHITECTURE.md
 M docs/DEVELOPMENT_GUIDE.md
 M docs/PROJECT_OVERVIEW.md
 M docs/PROJECT_STATUS.md
 M docs/REQUIREMENTS.md
 M docs/ROADMAP.md
 M docs/ai/rules/clean-architecture.md
 M docs/ai/rules/offline-first.md
 M docs/ai/rules/project-principles.md
 M docs/ai/rules/security.md
 M docs/ai/rules/testing.md
 M docs/architecture/BACKUP_RESTORE_DECISIONS.md
 M docs/architecture/BACKUP_RESTORE_PROTOCOL.md
 M docs/architecture/BACKUP_RESTORE_TECHNICAL_VALIDATION.md
 M docs/decisions/README.md
 M docs/requirements/BUSINESS_RULES_SPEC.md
 M docs/requirements/PHASE_0_BUSINESS_DISCOVERY.md
?? .agents/
?? docs/compliance/
?? docs/development/
?? docs/phase-1/PHASE_1_1_GIT_EXECUTION_REPORT.md
```

### `git diff --cached`
```text
(Boş — 0 bayt. Hiçbir dosya stage edilmemiştir.)
```

---

## 5. Proje Sahibi Faz Kabul Bildirimi

DT-01.4 kapsamındaki tüm teknik entegrasyon ve dokümantasyon çalışmaları eksiksiz tamamlanmıştır.

> [!CRITICAL]
> **DT-01.4 teknik çalışmasının tamamlanması, fazın kabul edildiği anlamına gelmez. Faz kabul yetkisi münhasıran proje sahibine aittir.**

Proje sahibinin bu raporu inceleyerek onay vermesi beklenmektedir.

