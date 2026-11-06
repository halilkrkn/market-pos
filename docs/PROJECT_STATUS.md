# PROJECT_STATUS.md — Market POS (MMS) Mevcut Durum Raporu

*Bu belge her yeni yapay zekâ geliştirme oturumunda durum kontrolü amacıyla okunmalıdır.*  
*Son güncelleme: 6 Kasım 2026*

---

## 1. Aktif Aşama
**Faz 1 — MVP Uygulama ve Doğrulama**
- **Faz 1.1 (Windows Client Foundation):** **TAMAMLANDI ve KABUL EDİLDİ** (Commit `8676586`, Tag `v1.1.0-windows-client-foundation`, `docs/phase-1/PHASE_1_1_IMPLEMENTATION_REPORT.md` - 6 Kasım 2026).
- **DT-01.1 (Agent Governance Audit):** **TAMAMLANDI** (`docs/development/DT_01_1_AGENT_GOVERNANCE_AUDIT.md` - 6 Kasım 2026).
- **DT-01.2 (Skills Security & License Review / Activation / Verification):** **TAMAMLANDI** (`docs/compliance/DT_01_2_FINAL_VERIFICATION_AUDIT.md` - 6 Kasım 2026).
- **DT-01.3 (Documentation Reconciliation):** **TEKNİK ÇALIŞMA TAMAMLANDI** (Proje Sahibi Kabulü Bekleniyor).
- **DT-01.4 (Instruction Infrastructure Integration):** Henüz Başlamadı (Planlandı).
- **Faz 1.2 (Kasa Satış Ekranı & Sepet Yönetimi):** Planlandı (Kullanıcı Onayı Bekleniyor).

---

## 2. Mevcut Durum ve Ürün Tanımı

- **Ürün Konsepti:** **Market Management System (MMS)** — Profesyonel Market Yönetim SaaS Uygulaması. (Teknik klasör ve repo adı olarak `market-pos` korunmaktadır).
- **Pilot Mimarisi:** **Windows Local Master Hub** mimarisi esastır. Windows bilgisayar üzerinde bağımsız bir Windows Service (Dart Shelf HTTPS API, `bin\mms_backend.exe`) merkezi API'yi ve merkezi SQLite veri tabanını (`%PROGRAMDATA%\MarketMMS\data\market_master.db`) tekil yazıcı (Single-Writer) olarak yönetir. Uç cihazlar (Windows Flutter masaüstünde `%LOCALAPPDATA%\MarketMMS\client_local.db`, Android ve iOS telefonlarda yerel `mms_client.db`) kendi yerel Drift + SQLite veri tabanlarına sahiptir ve yerel ağ (LAN) üzerinden Merkezi API ile senkronize olur. Gelecek çok şubeli SaaS aşaması için Supabase PostgreSQL/Auth hedefi korunur.
- **Faz 1.1 Doğrulaması:** Flutter Windows masaüstü uygulaması (`market_pos.exe`) başarıyla derlenmiş, çalıştırılmış; `packages/mms_client_storage` (51 test), `test_spikes/spike_01_backend` (139 test) ve `market_pos` root istemci (31 test) olmak üzere **toplam 221 otomatik test %100 yeşil** olarak doğrulanmıştır. Clean Architecture sınırları ve merkezi DB doğrudan erişim yasağı eksiksiz korunmaktadır.
- **Spike-01 Doğrulaması:** S5A serisi (S5A-1'den S5A-5'e kadar) tamamlanmış, Dart Shelf backend mimarisi ve SQLite WAL tekil yazıcı eşzamanlılığı 139 testle doğrulanmıştır. **S5A-5 Sonucu: KOŞULLU PİLOT HAZIRLIĞI (READY FOR PILOT WITH CONDITIONS)** seviyesindedir. Gerçek pilot henüz başlamamıştır.
- **Açık Teknik Koşullar (Pilot Öncesi Zorunlu Maddeler):**
  1. **B-2:** Mobil istemcilerde (Android/iOS) Root CA sertifika sabitleme (Certificate Pinning) entegrasyonu.
  2. **B-3:** Güvenli token ve sır depolama (Windows DPAPI, Android Keystore, iOS Keychain).
  3. **SCM Entegrasyonu:** Gerçek Windows Service Control Manager (SCM) servis kurulum, başlatma, durdurma ve kaza kurtarma testleri (Spike aşamasında bağımsız process/WinSW test edilmiştir).
  4. **Yetki ve Güvenlik:** Standart (non-admin) Windows kullanıcısı yetki ve dizin erişim kontrolü (ACL) testleri (`%PROGRAMDATA%\MarketMMS`).
  5. **Fiziksel Mobil Cihaz Testleri:** Gerçek Android ve iOS cihazlarla yerel Wi-Fi mDNS / Dinamik QR eşleştirme ve ağ kopma/bağlanma testleri.
  6. **Eşleştirme Yetkilendirmesi:** Cihaz eşleştirme rotalarına özel token kısıtlaması (route-specific pairing token restriction).
- **Ana Proje Dokümanı:** [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](../MARKET_POS_AI_STUDIO_BUILD_PLANI.md) (**v1.4**, 6 Kasım 2026) bağlayıcı ana referans olarak mutabakat altına alınmıştır.
- **Yerel Depolama Teknik Doğrulaması:** [`docs/architecture/LOCAL_STORAGE_TECHNICAL_VALIDATION.md`](./architecture/LOCAL_STORAGE_TECHNICAL_VALIDATION.md) Windows, Android, iOS ve Web platformları için Drift + SQLite depolama mimarisini, kaza kurtarmayı ve WAL eşzamanlılığını tanımlar.
- **Yedekleme ve Geri Yükleme Protokolü:** [`docs/architecture/BACKUP_RESTORE_PROTOCOL.md`](./architecture/BACKUP_RESTORE_PROTOCOL.md) bağımsız Windows SQLite ve mobil SQLite anlık görüntülerinin (`VACUUM INTO`) S5A-4 standardında AES-256-CBC + HMAC-SHA256 (Encrypt-then-MAC) ile şifrelenerek Google Drive hedefli yedekleme tasarımını tanımlar.
- **Yedekleme Karar Kayıtları:** [`docs/architecture/BACKUP_RESTORE_DECISIONS.md`](./architecture/BACKUP_RESTORE_DECISIONS.md) mimari kararları gerekçelendirir.
- **Yedekleme Bağımsız Teknik Doğrulama Raporu:** [`docs/architecture/BACKUP_RESTORE_TECHNICAL_VALIDATION.md`](./architecture/BACKUP_RESTORE_TECHNICAL_VALIDATION.md) felaket senaryolarının teknik analizini içerir.
- **Mimari Uyum ve Windows Master Hub Raporu:** [`MARKET_MMS_ARCHITECTURE_ALIGNMENT_REVIEW.md`](../MARKET_MMS_ARCHITECTURE_ALIGNMENT_REVIEW.md) Windows Service, Merkezi API, Merkezi SQLite ve yerel LAN senkronizasyon mimarisini belgeler.
- **Veri Modeli ve Senkronizasyon Matrisi:** [`MARKET_MMS_DATA_MODEL_SYNC_REVIEW.md`](../MARKET_MMS_DATA_MODEL_SYNC_REVIEW.md) 25 tablonun Merkez vs Mobil sorumluluklarını ve senkronizasyon yönlerini tanımlar.
- **Teknik Spike Durumu:** SPIKE-01 (Windows Service & SQLite Single-Writer) başarıyla tamamlanmış ve 139 test ile doğrulanmıştır. SPIKE-02 (LAN Discovery & QR Pairing) ve SPIKE-03 (Mobil TLS & iOS İzni) planlanmıştır.
- **Antigravity Beceri Altyapısı ve Kayıt Defteri:** [`.agents/registry/SKILL_REGISTRY.md`](../.agents/registry/SKILL_REGISTRY.md) 5 çekirdek beceriyi (`code-quality`, `test-first`, `systematic-debugging`, `flutter-ui-standards`, `documentation`) içerir; DT-01.2 ile aktif edilmiştir.
- **Offline Senkronizasyon Kuralları:** [`docs/architecture/OFFLINE_SYNC_PROTOCOL.md`](./architecture/OFFLINE_SYNC_PROTOCOL.md) kalıcı `device_id`, monotonik artan `client_seq`, `operation_id`, deterministik FIFO işlem sırası, sunucu onayı (ACK) gelmeden `SYNCED` işaretlenmeme ve `idempotency_key` ile mükerrer işlem koruma kurallarını tanımlar. (Worker kiralama ve üstel geri çekilme detayları `OPEN DECISION` seviyesindedir).
- **Senkronizasyon Karar Kayıtları:** [`docs/architecture/OFFLINE_SYNC_DECISIONS.md`](./architecture/OFFLINE_SYNC_DECISIONS.md) senkronizasyon mimari kararlarını gerekçelendirir.
- **Senkronizasyon Teknik Doğrulama Raporu:** [`docs/architecture/OFFLINE_SYNC_TECHNICAL_VALIDATION.md`](./architecture/OFFLINE_SYNC_TECHNICAL_VALIDATION.md) protokolün bağımsız teknik denetim raporudur.
- **Mantıksal Veri Modeli Taslağı:** [`docs/architecture/DATA_MODEL.md`](./architecture/DATA_MODEL.md) 25 tablodan oluşan operasyonel veri modelini tanımlar.
- **Veri Modeli Karar Kayıtları:** [`docs/architecture/DATA_MODEL_DECISIONS.md`](./architecture/DATA_MODEL_DECISIONS.md) veri modeli mimari kararlarını gerekçelendirir.
- **İş Kuralları Şartnamesi:** [`docs/requirements/BUSINESS_RULES_SPEC.md`](./requirements/BUSINESS_RULES_SPEC.md) pilot ve gelecek SaaS için 159 iş kuralı ve 21 NFR tanımlar.
- **İş Gereksinimleri Keşif Dokümanı:** [`docs/requirements/PHASE_0_BUSINESS_DISCOVERY.md`](./requirements/PHASE_0_BUSINESS_DISCOVERY.md) iş kararlarını konsolide etmiştir.
- **Çoklu Cihaz Yaklaşımı:** Windows bilgisayar ve mobil telefonlar aynı temel market yönetim işlevlerine (ürün, satış, stok, dashboard, raporlama) sahiptir. Barkod girişi PC'de USB HID, mobilde kamera ile sağlanır.
- **Banka POS Kapsamı:** Banka POS terminali entegrasyonu ilk sürümün kapsamı dışındadır.

---

## 3. Faz 0 ve Faz 1 Durum Takibi

### Faz 0 — Planlama ve Mimari Kararlar (TAMAMLANDI)
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
- [x] Mantıksal veri modeli operasyonel taslağının hazırlanması (`DATA_MODEL.md`)
- [x] Offline senkronizasyon ve outbox kuyruğu protokolü tasarımı (`OFFLINE_SYNC_PROTOCOL.md`, `OFFLINE_SYNC_DECISIONS.md`)
- [x] Windows, Android, iOS ve Web için yerel depolama doğrulaması (`LOCAL_STORAGE_TECHNICAL_VALIDATION.md` tamamlandı)
- [x] Merkezi ve yerel yedekleme protokolü tasarımı (`BACKUP_RESTORE_PROTOCOL.md` Google Drive hedefli mimari tasarım)
- [x] Windows Local Master Hub mimari uyumu ve veri/senkronizasyon matrisi dokümantasyonu
- [x] Antigravity klasör yapısı, 5 çekirdek beceri ve `SKILL_REGISTRY.md` entegrasyonu
- [x] Aşama 6B-1: Dokümantasyon mimari senkronizasyonunun tamamlanması
- [x] Aşama 6B-2: Karara bağlanmamış veri modeli ve teknik konuların değerlendirilmesi
- [x] Faz 0 Teknik Spike'ı (SPIKE-01): Dart Shelf AOT + SQLite single-writer başarıyla tamamlandı (139 test).
- [x] Faz 0 kabul kriterlerinin eksiksiz tamamlanması ve kapanış onayı

### Faz 1 — Temel Altyapı ve MVP Uygulama (DEVAM EDİYOR)
- [x] **Faz 1.1 — Windows Client Foundation:** TAMAMLANDI ve KABUL EDİLDİ (`mms_client_storage` paketi, Drift yerel SQLite, `market_pos.exe` Windows release derlemesi, 221 yeşil test).
- [x] **DT-01.1 — Agent Governance Audit:** TAMAMLANDI (Merkezi talimat mimarisi analiz edildi).
- [x] **DT-01.2 — Skills Security & License Review:** TAMAMLANDI (5 beceri incelendi, lisanslandı ve aktif edildi).
- [x] **DT-01.3 — Documentation Reconciliation:** **TEKNİK ÇALIŞMA TAMAMLANDI** (Proje Sahibi Kabulü Bekleniyor).
- [ ] **DT-01.4 — Instruction Infrastructure Integration:** Henüz Başlamadı (Planlandı).
- [ ] **Faz 1.2 — Kasa Satış Ekranı & Sepet Yönetimi:** Planlandı (Kullanıcı Onayı Bekleniyor).

---

## 4. Bir Sonraki Görev

1. **DT-01.3 Kabulü:** Proje sahibinin dokümantasyon mutabakatı ve son inceleme raporunu (`docs/development/DT_01_3_FINAL_REVIEW_REPORT.md`) incelemesi ve kabul onayı vermesi.
2. **DT-01.4 Başlatılması:** Proje sahibi onayının ardından `AGENTS.md` ve `GEMINI.md` talimat dosyalarının mutabakata varılan yeni mimari kurallarla güncellenmesi.
3. **Faz 1.2 Kullanıcı Onayı:** Talimat altyapısı tamamlandıktan sonra Faz 1.2 (Kasa Satış Ekranı & Sepet Yönetimi) uygulama geliştirmesine geçilmesi.
