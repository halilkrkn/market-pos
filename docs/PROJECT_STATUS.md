# PROJECT_STATUS.md — Market POS (MMS) Mevcut Durum Raporu

*Bu belge her yeni yapay zekâ geliştirme oturumunda durum kontrolü amacıyla okunmalıdır.*  
*Son güncelleme: 13 Kasım 2026*

---

## 1. Aktif Aşama
**Faz 1 — MVP Uygulama ve Doğrulama**
- **Git & Depo Durumu:** Aktif dal `main`, son commit `e9e1df5` (`HEAD == origin/main` — Faz 1.2 POS Kasa Satış Ekranı & Sepet Yönetimi başarıyla tamamlandı ve push edildi).
- **Faz 1.1 (Windows Client Foundation):** **TAMAMLANDI ve KABUL EDİLDİ** (Commit `8676586`, Tag `v1.1.0-windows-client-foundation`, `docs/phase-1/PHASE_1_1_IMPLEMENTATION_REPORT.md` - 6 Kasım 2026).
- **DT-01.1 (Agent Governance Audit):** **TAMAMLANDI** (`docs/development/DT_01_1_AGENT_GOVERNANCE_AUDIT.md` - 6 Kasım 2026).
- **DT-01.2 (Skills Security & License Review / Activation / Verification):** **TAMAMLANDI ve PUSH EDİLDİ** (Commit `50343d9`, `docs/compliance/DT_01_2_FINAL_VERIFICATION_AUDIT.md`).
- **DT-01.3 (Documentation Reconciliation):** **TAMAMLANDI ve PUSH EDİLDİ** (Commit `6b7898c`, `docs/development/DT_01_3_FINAL_REVIEW_REPORT.md`).
- **DT-01.4 (Instruction Infrastructure Integration):** **TAMAMLANDI ve PUSH EDİLDİ** (Commitler `2db892d` & `32111b8`, `docs/development/DT_01_4_FINAL_GOVERNANCE_AUDIT.md`).
- **UI/UX Tasarım ve Prototip Programı (`docs/ui-ux/`):** **TAMAMLANDI, KABUL EDİLDİ VE PUSH EDİLDİ (Commitler `9ad09fc` ve `1a3f8e5`)** *(32 prototip ve Flutter Handoff şartnamesi kabul edildi; `OD-01` Half-Up + `12.50 TL`, `OD-02` Parked Carts MVP dışı, `OD-03` offline bilinmeyen barkod eklenemez/oluşturulamaz, `OD-04` sanal numpad opsiyonel & varsayılan kapalı kararları kesinleşti; fiziksel cihaz ve saha kullanıcı testleri Faz 7 Pilot kapsamındadır)*.
- **Faz 1.2 Öncesi `PaymentMethod` Standardizasyonu ve Legacy Outbox Recovery:** **TAMAMLANDI, KABUL EDİLDİ VE PUSH EDİLDİ (Commit `b069d5b`)** *(Tüm katmanlarda yalnızca `'CASH'` ve `'CARD'` sözleşmesi, backend `400 ERR_INVALID_PAYMENT_METHOD` reddi ve `updateAndRetryFailedOperation()` atomik transaction + rollback + FIFO + canlı Master Hub E2E kurtarma akışı doğrulandı; 235 otomatik test %100 yeşil; bkz. [`PHASE_1_2_PAYMENT_CONTRACT_FIX_REPORT.md`](./development/PHASE_1_2_PAYMENT_CONTRACT_FIX_REPORT.md), [`PHASE_1_2_LEGACY_OUTBOX_RECOVERY_REPORT.md`](./development/PHASE_1_2_LEGACY_OUTBOX_RECOVERY_REPORT.md), [`PHASE_1_2_PAYMENT_METHOD_GIT_EXECUTION_REPORT.md`](./development/PHASE_1_2_PAYMENT_METHOD_GIT_EXECUTION_REPORT.md))*.
- **Faz 1.2 (Kasa Satış Ekranı & Sepet Yönetimi):** **TAMAMLANDI, KABUL EDİLDİ VE PUSH EDİLDİ (13 Kasım 2026 — Commit `e9e1df5`)** *(POS ana kasa ekranı, sepet motoru, klavye kısayolları F1, F2, F9, F10 ve Esc, barkod arama, `PaymentDialog` CASH/CARD, snapshot fiyat ve priceVersionId güvencesi `PriceChangedException`, 64-bit tamsayı taşma koruması, `_nextUniqueToken()` benzersizliği; root 67, storage 63, backend 144 olmak üzere toplam 274 otomatik test %100 yeşil, Windows debug derlemesi başarılı; bkz. [`PHASE_1_2_IMPLEMENTATION_REPORT.md`](./development/PHASE_1_2_IMPLEMENTATION_REPORT.md), [`PHASE_1_2_RELIABILITY_FIX_REPORT.md`](./development/PHASE_1_2_RELIABILITY_FIX_REPORT.md), [`PHASE_1_2_FINAL_CODE_REVIEW_REPORT.md`](./development/PHASE_1_2_FINAL_CODE_REVIEW_REPORT.md), [`PHASE_1_2_GIT_STAGING_REPORT.md`](./development/PHASE_1_2_GIT_STAGING_REPORT.md))*.
- **Faz 1.3 (Kasa Senkronizasyonu & Satış Geçmişi / İptal-İade):** **PLANLANDI — SIRADAKİ AKTİF AŞAMA** *(Dört onaylı alt aşama: 1.3.1 Outbox ve arka plan senkronizasyonu, 1.3.2 Satış geçmişi ve fiş detayları, 1.3.3 Tam satış iptali, 1.3.4 Kısmi ürün iadesi)*.
- **Faz 1.4 Adayı (Ürün ve Kategori Yönetimi):** Değerlendirme adayıdır; henüz başlatma kararı verilmemiştir (Katalog CRUD, çoklu barkod tanımlama, fiyat geçmişi - Main Shell Tab 1).

---

## 2. Mevcut Durum ve Ürün Tanımı

- **Ürün Konsepti:** **Market Management System (MMS)** — Profesyonel Market Yönetim SaaS Uygulaması. (Teknik klasör ve repo adı olarak `market-pos` korunmaktadır).
- **Pilot Mimarisi:** **Windows Local Master Hub** mimarisi esastır. Windows bilgisayar üzerinde bağımsız bir Windows Service (Dart Shelf HTTPS API, `bin\mms_backend.exe`) merkezi API'yi ve merkezi SQLite veri tabanını (`%PROGRAMDATA%\MarketMMS\data\market_master.db`) tekil yazıcı (Single-Writer) olarak yönetir. Uç cihazlar (Windows Flutter masaüstünde `%LOCALAPPDATA%\MarketMMS\client_local.db`, Android ve iOS telefonlarda yerel `mms_client.db`) kendi yerel Drift + SQLite veri tabanlarına sahiptir ve yerel ağ (LAN) üzerinden Merkezi API ile senkronize olur. Gelecek çok şubeli SaaS aşaması için Supabase PostgreSQL/Auth hedefi korunur.
- **Faz 1.1 Doğrulaması:** Flutter Windows masaüstü uygulaması (`market_pos.exe`) başarıyla derlenmiş, çalıştırılmış; `packages/mms_client_storage` (51 test), `test_spikes/spike_01_backend` (139 test) ve `market_pos` root istemci (31 test) olmak üzere **toplam 221 otomatik test %100 yeşil** olarak doğrulanmıştır. Clean Architecture sınırları ve merkezi DB doğrudan erişim yasağı eksiksiz korunmaktadır.
- **Faz 1.2 POS & Sepet Doğrulaması (Commit `e9e1df5`):** POS kasa ekranı (`PosScreen`), sepet durumu (`CartNotifier`), ödeme penceresi (`PaymentDialog`), fiyat tutarlılığı (`PriceChangedException`), 64-bit taşma kontrolleri ve test süitleri tamamlanmış; `market_pos` kök istemci (root: 67 test), `packages/mms_client_storage` (storage: 63 test) ve `test_spikes/spike_01_backend` (backend: 144 test) olmak üzere **toplam 274/274 otomatik test %100 yeşil**, 0 analyzer hatası ve Windows masaüstü debug derlemesi (`market_pos.exe`) başarıyla doğrulanmıştır.
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
- **İş Kuralları Şartnamesi:** [`docs/requirements/BUSINESS_RULES_SPEC.md`](./requirements/BUSINESS_RULES_SPEC.md) (**v1.6**, 12 Kasım 2026 uzlaştırmalı) pilot ve gelecek SaaS iş kurallarını tanımlar *(v1.4 ile `OD-01` Half-Up yuvarlama + `12.50 TL`, `OD-02`/`BR-POS-05` Parked Carts `[OUT_OF_SCOPE]`, `OD-03`/`BR-PROD-05`/`BR-SYNC-04` offline bilinmeyen barkod eklenemez/oluşturulamaz, `OD-04` sanal numpad opsiyonel/kapalı ve `BR-STK-04..10` `[OUT_OF_SCOPE]`; v1.5 ile `'CASH'`/`'CARD'` sözleşmesi; v1.6 ile Legacy Outbox Recovery `b069d5b` uyumu ve Bölüm 12–13 uzlaştırması kesinleşmiştir)*.
- **UI/UX Tasarım ve Karar Belgeleri (`docs/ui-ux/` — KABUL EDİLDİ VE PUSH EDİLDİ):** [`UX_FINAL_DELIVERY_REPORT.md`](./ui-ux/UX_FINAL_DELIVERY_REPORT.md) (**v1.7**), [`UX_TARGETED_AUDIT_REPORT.md`](./ui-ux/UX_TARGETED_AUDIT_REPORT.md) (**v1.3**), [`UX_FINAL_VERIFICATION_AND_RECONCILIATION_REPORT.md`](./ui-ux/UX_FINAL_VERIFICATION_AND_RECONCILIATION_REPORT.md) (**v1.2**), [`DESIGN_DECISIONS.md`](./ui-ux/DESIGN_DECISIONS.md) (**v1.4**) ve [`UX_07_FLUTTER_HANDOFF.md`](./ui-ux/UX_07_FLUTTER_HANDOFF.md) (**v1.4**) HTML/CSS/JS görsel prototipleriyle birlikte **11 Kasım 2026 tarihinde Proje Sahibi tarafından kabul edilmiştir** *(Commit `9ad09fc` ve `1a3f8e5` ile depoya kaydedilmiş ve `origin/main`'e push edilmiştir)*.
- **İş Gereksinimleri Keşif Dokümanı:** [`docs/requirements/PHASE_0_BUSINESS_DISCOVERY.md`](./requirements/PHASE_0_BUSINESS_DISCOVERY.md) iş kararlarını konsolide etmiştir.
- **Çoklu Cihaz Yaklaşımı:** Windows bilgisayar ve mobil telefonlar aynı temel market yönetim işlevlerine (ürün, satış, stok hareketleri/izleme, dashboard, raporlama — fiziksel stok sayımı MVP dışı) sahiptir. Barkod girişi PC'de USB HID, mobilde kamera ile sağlanır.
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
- [x] **Faz 1.1 — Windows Client Foundation:** TAMAMLANDI ve KABUL EDİLDİ (`mms_client_storage` paketi, Drift yerel SQLite, `market_pos.exe` Windows release derlemesi; Faz 1.1 kapanışında 221 test, 11 Kasım kontrolünde kök `flutter test` 31/31 test doğrulandı, commit `8676586`).
- [x] **DT-01.1 — Agent Governance Audit:** TAMAMLANDI (`docs/development/DT_01_1_AGENT_GOVERNANCE_AUDIT.md`).
- [x] **DT-01.2 — Skills Security & License Review:** TAMAMLANDI ve PUSH EDİLDİ (Commit `50343d9`).
- [x] **DT-01.3 — Documentation Reconciliation:** TAMAMLANDI ve PUSH EDİLDİ (Commit `6b7898c`).
- [x] **DT-01.4 — Instruction Infrastructure Integration:** TAMAMLANDI ve PUSH EDİLDİ (Commitler `2db892d`, `32111b8`).
- [x] **UI/UX Tasarım ve Prototip Programı (`docs/ui-ux/`):** **TAMAMLANDI, KABUL EDİLDİ VE PUSH EDİLDİ (Commitler `9ad09fc` ve `1a3f8e5`)**; `OD-01` (Half-Up, `12.50 TL`), `OD-02` (Parked Carts `OUT_OF_SCOPE`), `OD-03` (offline bilinmeyen barkod eklenemez/oluşturulamaz) ve `OD-04` (sanal numpad opsiyonel, varsayılan kapalı) kararları kesinleşti *(saha/donanım testleri Faz 7 Pilot)*.
- [x] **Faz 1.2 Öncesi `PaymentMethod` Standardizasyonu ve Legacy Outbox Recovery:** **TAMAMLANDI, KABUL EDİLDİ ve PUSH EDİLDİ (Commit `b069d5b` — 235 otomatik test %100 yeşil, `docs/development/PHASE_1_2_PAYMENT_CONTRACT_FIX_REPORT.md`, `PHASE_1_2_LEGACY_OUTBOX_RECOVERY_REPORT.md`, `PHASE_1_2_PAYMENT_METHOD_GIT_PREFLIGHT_REPORT.md`)**.
- [x] **Faz 1.2 — Kasa Satış Ekranı & Sepet Yönetimi:** **TAMAMLANDI, KABUL EDİLDİ ve PUSH EDİLDİ (13 Kasım 2026 — Commit `e9e1df5`)** *(POS ekranı, sepet durumu, klavye kısayolları F1, F2, F9, F10 ve Esc, barkod arama, `PaymentDialog` CASH/CARD, snapshot fiyat güvencesi `PriceChangedException`, 64-bit tamsayı taşma koruması, `_nextUniqueToken()` benzersizliği; root 67, storage 63, backend 144 olmak üzere toplam 274/274 otomatik test %100 yeşil, Windows debug derlemesi başarılı)*.
- [ ] **Faz 1.3 — Kasa Senkronizasyonu & Satış Geçmişi / İptal-İade:** **SIRADAKİ AKTİF AŞAMA (Planlandı)**:
  - [ ] **1.3.1 — Outbox ve Arka Plan Senkronizasyonu:** `ClientSyncService`'in Flutter UI'a bağlanması, arka plan worker'ı, canlı Outbox kuyruk derinliği rozeti.
  - [ ] **1.3.2 — Satış Geçmişi ve Fiş Detayları:** Main Shell Tab 2 satış listesi, fiş detay modalı, nakit/kart dökümü.
  - [ ] **1.3.3 — Tam Satış İptali:** `BR-POS-08` gerekçeli tam fiş iptali, stok iadesi ve audit kaydı.
  - [ ] **1.3.4 — Kısmi Ürün İadesi:** `BR-POS-09` kalem bazında iade, hasarlı/satılabilir durum ayrımı (`BR-POS-10`).
- [ ] **Faz 1.4 Adayı — Ürün ve Kategori Yönetimi:** Değerlendirme adayı (Henüz başlatma kararı verilmedi; Katalog CRUD, çoklu barkod tanımlama, fiyat geçmişi - Main Shell Tab 1).

---

## 4. Bir Sonraki Görev

1. **Faz 1.3 Hazırlığı (1.3.1 Outbox & Arka Plan Senkronizasyonu):** `ClientSyncService` ve `HttpSyncTransport` bileşenlerinin Flutter istemcisinde Riverpod provider ve arka plan worker'ı olarak entegre edilmesi; kasa başlık çubuğunda (`StatusBadge`) bekleyen Outbox işlem sayısının gösterilmesi.
2. **Kasa Satış Geçmişi & Fiş İnceleme (1.3.2):** Main Shell Tab 2 placeholder'ının yerine yerel satışları (`local_sales`, `local_sale_items`) listeleyen ve fiş detaylarını gösteren arayüzün geliştirilmesi.
3. **Satış İptali & İade Operasyonları (1.3.3 & 1.3.4):** `BR-POS-08` tam satış iptali ve `BR-POS-09` kısmi iade akışlarının test-first (TDD) ile hayata geçirilmesi.
4. **Faz 1.4 Hazırlığı:** Katalog CRUD kapsam değerlendirmesi Faz 1.3 tamamlandıktan sonra yapılacaktır.
