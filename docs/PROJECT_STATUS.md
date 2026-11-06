# PROJECT_STATUS.md — Market POS (MMS) Mevcut Durum Raporu

*Bu belge her yeni yapay zekâ geliştirme oturumunda durum kontrolü amacıyla okunmalıdır.*  
*Son güncelleme: 5 Kasım 2026*

---

## 1. Aktif Aşama
**Faz 1 — MVP Uygulama ve Doğrulama**
- **Faz 1.1 (Windows Client Foundation):** **TAMAMLANDI** (`docs/phase-1/PHASE_1_1_IMPLEMENTATION_REPORT.md` - 6 Kasım 2026).
- **Faz 1.2 (Kasa Satış Ekranı & Sepet Yönetimi):** Planlandı (Kullanıcı Onayı Bekleniyor).

---

## 2. Mevcut Durum ve Ürün Tanımı

- **Ürün Konsepti:** **Market Management System (MMS)** — Profesyonel Market Yönetim SaaS Uygulaması. (Teknik klasör ve repo adı olarak `market-pos` korunmaktadır).
- **Pilot Mimarisi:** **Windows Local Master Hub** mimarisi esastır. Windows bilgisayar üzerinde bağımsız bir Windows Service merkezi API'yi ve merkezi SQLite veri tabanını yönetir. Uç cihazlar (Windows Flutter masaüstü, Android, iOS telefonlar) kendi yerel Drift + SQLite veri tabanlarına sahiptir ve yerel ağ (LAN) üzerinden Merkezi API ile senkronize olur.
- **Faz 1.1 Doğrulaması:** Flutter Windows masaüstü uygulaması (`market_pos.exe`) başarıyla derlenmiş, çalıştırılmış, `mms_client_storage` (51 test), `spike_01_backend` (139 test) ve `market_pos` (13 test) olmak üzere toplam 203 otomatik test %100 yeşil olarak doğrulanmıştır. Clean Architecture sınırları ve merkezi DB doğrudan erişim yasağı eksiksiz korunmaktadır.
- **Ana Proje Dokümanı:** [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](../MARKET_POS_AI_STUDIO_BUILD_PLANI.md) (**v1.2.2**, 5 Kasım 2026) bağlayıcı ana referans olarak güncellenmiştir.
- **Yerel Depolama Teknik Doğrulaması:** [`docs/architecture/LOCAL_STORAGE_TECHNICAL_VALIDATION.md`](./architecture/LOCAL_STORAGE_TECHNICAL_VALIDATION.md) Windows, Android, iOS ve Web platformları için Drift + SQLite depolama mimarisini, kaza kurtarmayı ve WAL eşzamanlılığını tanımlar.
- **Yedekleme ve Geri Yükleme Protokolü:** [`docs/architecture/BACKUP_RESTORE_PROTOCOL.md`](./architecture/BACKUP_RESTORE_PROTOCOL.md) bağımsız Windows SQLite ve mobil SQLite anlık görüntülerinin (`VACUUM INTO`) Google Drive hedefli yedekleme tasarımını tanımlar.
- **Yedekleme Karar Kayıtları:** [`docs/architecture/BACKUP_RESTORE_DECISIONS.md`](./architecture/BACKUP_RESTORE_DECISIONS.md) 8 mimari kararı gerekçelendirir.
- **Yedekleme Bağımsız Teknik Doğrulama Raporu:** [`docs/architecture/BACKUP_RESTORE_TECHNICAL_VALIDATION.md`](./architecture/BACKUP_RESTORE_TECHNICAL_VALIDATION.md) felaket senaryolarının teknik analizini içerir.
- **Mimari Uyum ve Windows Master Hub Raporu:** [`MARKET_MMS_ARCHITECTURE_ALIGNMENT_REVIEW.md`](../MARKET_MMS_ARCHITECTURE_ALIGNMENT_REVIEW.md) Windows Service, Merkezi API, Merkezi SQLite ve yerel LAN senkronizasyon mimarisini belgeler.
- **Veri Modeli ve Senkronizasyon Matrisi:** [`MARKET_MMS_DATA_MODEL_SYNC_REVIEW.md`](../MARKET_MMS_DATA_MODEL_SYNC_REVIEW.md) 25 tablonun Merkez vs Mobil sorumluluklarını ve senkronizasyon yönlerini tanımlar.
- **Teknik Spike Planı:** [`MARKET_MMS_PHASE_0_TECHNICAL_SPIKE_PLAN.md`](../MARKET_MMS_PHASE_0_TECHNICAL_SPIKE_PLAN.md) SPIKE-01 (Windows Service), SPIKE-02 (LAN Discovery) ve SPIKE-03 (Yerel TLS & iOS) doğrulama planını içerir (henüz icra edilmemiştir).
- **Antigravity Beceri Altyapısı ve Kayıt Defteri:** [`.agents/registry/SKILL_REGISTRY.md`](../.agents/registry/SKILL_REGISTRY.md) 5 çekirdek beceriyi (`code-quality`, `test-first`, `systematic-debugging`, `flutter-ui-standards`, `documentation`) içerir.
- **Offline Senkronizasyon Protokolü:** [`docs/architecture/OFFLINE_SYNC_PROTOCOL.md`](./architecture/OFFLINE_SYNC_PROTOCOL.md) Outbox durum makinesi, deterministik FIFO, yerel ağ senkronizasyonu ve çakışma matrisi mimari tasarımını tanımlar.
- **Senkronizasyon Karar Kayıtları:** [`docs/architecture/OFFLINE_SYNC_DECISIONS.md`](./architecture/OFFLINE_SYNC_DECISIONS.md) senkronizasyon mimari kararlarını gerekçelendirir.
- **Senkronizasyon Teknik Doğrulama Raporu:** [`docs/architecture/OFFLINE_SYNC_TECHNICAL_VALIDATION.md`](./architecture/OFFLINE_SYNC_TECHNICAL_VALIDATION.md) protokolün bağımsız teknik denetim raporudur.
- **Mantıksal Veri Modeli Taslağı:** [`docs/architecture/DATA_MODEL.md`](./architecture/DATA_MODEL.md) 25 tablodan oluşan operasyonel veri modeli taslağını tanımlar (şema detayları, kısıtlar ve alan adları Aşama 6B-2 ve Faz 1 spike sürecinde kesinleştirilecektir).
- **Veri Modeli Karar Kayıtları:** [`docs/architecture/DATA_MODEL_DECISIONS.md`](./architecture/DATA_MODEL_DECISIONS.md) veri modeli mimari kararlarını gerekçelendirir.
- **İş Kuralları Şartnamesi:** [`docs/requirements/BUSINESS_RULES_SPEC.md`](./requirements/BUSINESS_RULES_SPEC.md) pilot ve gelecek SaaS için iş kurallarını tanımlar.
- **İş Gereksinimleri Keşif Dokümanı:** [`docs/requirements/PHASE_0_BUSINESS_DISCOVERY.md`](./requirements/PHASE_0_BUSINESS_DISCOVERY.md) iş kararlarını konsolide etmiştir.
- **Çoklu Cihaz Yaklaşımı:** Windows bilgisayar ve mobil telefonlar aynı temel market yönetim işlevlerine (ürün, satış, stok, dashboard, raporlama) sahiptir. Barkod girişi PC'de USB HID, mobilde kamera ile sağlanır.
- **Banka POS Kapsamı:** Banka POS terminali entegrasyonu ilk sürümün kapsamı dışındadır.
- **Uygulama Durumu:** **Henüz hiçbir Windows Service, Flutter/Dart veya C# uygulama kodu yazılmamıştır; yedekleme veya senkronizasyon motoru kodlanmamış ya da çalıştırılmamıştır.** Tüm maddeler şu anda mimari tasarım ve dokümantasyon aşamasındadır.
- **Proje İskeleti:** Henüz `flutter create` çalıştırılmamıştır.

---

## 3. Faz 0 Durum Takibi

*(Not: Aşağıdaki `[x]` işaretleri ilgili konunun mimari tasarım ve şartname dokümantasyonunun tamamlandığını ifade eder; kod implementasyonu Faz 1'dedir.)*

- [x] Temel ürün vizyonunun belirlenmesi (Market Management System - MMS, pilot market + SaaS hedefi)
- [x] İlk sürüm özelliklerinin belirlenmesi (ürün, stok, satış, dashboard, ciro/kâr ayrımı)
- [x] Çoklu cihazın yerel çalışma modeli (Drift + SQLite, PC ve telefon eşit işlev, offline-first)
- [x] Çoklu market SaaS kararı (tenant, store, user, device modeli)
- [x] Windows SQLite ve Mobil SQLite + Google Drive bağımsız yedekleme hedefinin tasarlanması
- [x] Ortak yapay zekâ talimat mimarisinin kurulması ve v1.2'ye uyarlanması
- [x] Tenant ve şube izolasyonu iş kurallarının netleştirilmesi (`BUSINESS_RULES_SPEC.md`)
- [x] Ürün birimleri, barkod ilişkisi ve kesirli miktar kuralları (`BUSINESS_RULES_SPEC.md`)
- [x] Satış, sepet ve stok düşümü iş kurallarının yazılması (`BUSINESS_RULES_SPEC.md`)
- [x] Offline çakışma tespiti ve çözüm kurallarının netleştirilmesi (`BUSINESS_RULES_SPEC.md`)
- [x] Yedekleme sıklığı, saklama politikası ve geri yükleme prosedürünün detaylandırılması (`BUSINESS_RULES_SPEC.md`)
- [x] Mantıksal veri modeli operasyonel taslağının hazırlanması (`DATA_MODEL.md` — Aşama 6B-2 ve Faz 1 doğrulamasına tabi taslak)
- [x] Offline senkronizasyon ve outbox kuyruğu protokolü tasarımı (`OFFLINE_SYNC_PROTOCOL.md`, `OFFLINE_SYNC_DECISIONS.md`)
- [x] Windows, Android, iOS ve Web için yerel depolama doğrulaması (`LOCAL_STORAGE_TECHNICAL_VALIDATION.md` tamamlandı)
- [x] Merkezi ve yerel yedekleme protokolü tasarımı (`BACKUP_RESTORE_PROTOCOL.md` Google Drive hedefli mimari tasarım)
- [x] Windows Local Master Hub mimari uyumu ve veri/senkronizasyon matrisi dokümantasyonu
- [x] Antigravity klasör yapısı, 5 çekirdek beceri ve `SKILL_REGISTRY.md` entegrasyonu
- [x] Aşama 6B-1: Dokümantasyon mimari senkronizasyonunun tamamlanması
- [ ] Aşama 6B-2: Karara bağlanmamış veri modeli ve teknik konuların değerlendirilmesi
- [ ] Faz 0 Teknik Spike'larının (SPIKE-01, SPIKE-02, SPIKE-03) doğrulanması
- [ ] Dağıtım ve uzaktan güncelleme yaklaşımının netleştirilmesi
- [ ] Faz 0 kabul kriterlerinin eksiksiz tamamlanması ve kapanış onayı

---

## 4. Bir Sonraki Görev

**Aşama 6B-2 — Karara Bağlanmamış Veri Modeli ve Teknik Konuların Değerlendirilmesi:**
1. 25 tabloluk şema taslağının Merkez/Uç ayrımı, `tenant_id` kullanımı, `BIGINT` gereksinimi ve pay/payda modelinin incelenmesi.
2. Yerel tek Owner kimlik modelinin teknik yaklaşımı.
3. Idempotency mekanizması ve Inbox defteri (`processed_operations`) yapısı.
4. Worker lease mantığı ve kuyruk yönetimi.
5. Geri yükleme sonrası sayaç ilerletme formülü ile senkronize edilmemiş yerel satışların kurtarılması ayrımı.
6. Yetkisi kaldırılan cihazlardaki yerel satışların güvenli kurtarma akışı.

> [!IMPORTANT]
> Aşama 6B-1 yalnızca dokümantasyon senkronizasyonudur. Aşama 6B-2 değerlendirmesi yapılmadan, Faz 0 teknik spike'ları tamamlanmadan ve kullanıcıdan açık onay alınmadan **Faz 1 uygulama kodlamasına başlanamaz**.
