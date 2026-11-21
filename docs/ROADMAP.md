# ROADMAP.md — Geliştirme Yol Haritası (Faz 0–8)

Bu belge, [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](../MARKET_POS_AI_STUDIO_BUILD_PLANI.md) (**v1.4**) Bölüm 9'da tanımlanan 9 fazlık geliştirme yol haritasının çalışma amaçlı görünümüdür. 

> [!IMPORTANT]
> Ürün bir **Market Management System (MMS)** olarak konumlandırılmıştır. Pilot aşamada **Windows Local Master Hub** mimarisi esastır; çok şubeli SaaS fazı için bulut hazır mimari korunur. MVP hedef platformları **Windows masaüstü (`market_pos.exe`) ve Android** ortak istemci tabanıdır; iOS desteği ise gelecekte (Post-MVP / Ticari Hazırlık) değerlendirilecek kapsamdadır. Fazların ana numaralandırması ve kabul kriterleri ana doküman ile tam uyumludur.

---

## Faz 0 — Planlama ve Mimari Kararlar
**Durum:** ✅ TAMAMLANDI (4 Kasım 2026)  
**Açıklama:** Veri modelleri, tenant izolasyonu, stok/satış iş kuralları, PC ve telefonda eşit çoklu cihaz modeli, offline çakışma çözümü, platform depolama doğrulamaları ve SPIKE-01 (Dart Shelf + SQLite single-writer) 139 testle tamamlanmıştır.

---

## Faz 1 — Temel Altyapı ve MVP Uygulama
**Durum:** 🔄 DEVAM EDİYOR  
- [x] **Faz 1.1 — Windows Client Foundation:** TAMAMLANDI ve KABUL EDİLDİ (Commit `8676586`, Tag `v1.1.0-windows-client-foundation`, 221 yeşil test).
- [x] **DT-01.1 — Agent Governance Audit:** TAMAMLANDI (`docs/development/DT_01_1_AGENT_GOVERNANCE_AUDIT.md`).
- [x] **DT-01.2 — Skills Security & License Review / Activation:** TAMAMLANDI ve PUSH EDİLDİ (Commit `50343d9`, 5 çekirdek beceri aktif).
- [x] **DT-01.3 — Documentation Reconciliation:** TAMAMLANDI ve PUSH EDİLDİ (Commit `6b7898c`).
- [x] **DT-01.4 — Instruction Infrastructure Integration:** TAMAMLANDI ve PUSH EDİLDİ (Commitler `2db892d` & `32111b8`).
- [x] **UI/UX Tasarım ve Prototip Programı (`docs/ui-ux/`):** TAMAMLANDI, KABUL EDİLDİ VE PUSH EDİLDİ (Commitler `9ad09fc` ve `1a3f8e5`; `OD-01..OD-04` kararları kesinleşti).
- [x] **Faz 1.2 Öncesi `PaymentMethod` Standardizasyonu:** TAMAMLANDI ve PUSH EDİLDİ (Commit `b069d5b`, 235 yeşil test).
- [x] **Faz 1.2 — Kasa Satış Ekranı & Sepet Yönetimi:** TAMAMLANDI, KABUL EDİLDİ ve PUSH EDİLDİ (13 Kasım 2026 — Commit `e9e1df5`, 274 yeşil test, Windows debug derlemesi başarılı). *(Hızlı sepet, barkodla satış, kuruş tam sayı hesabı, OD-01 Half-Up ve 12.50 TL standardı, CASH/CARD ödeme penceresi, atomik yerel transaction ile stok düşüşü ve yerel Outbox kaydı tamamlandı)*.
- [ ] **Faz 1.3 — Kasa Senkronizasyonu & Satış Geçmişi / İptal-İade:** 🔄 AKTİF AŞAMA
  - [x] **Faz 1.3.1.1 — Outbox Status Summary & Diagnostics:** TAMAMLANDI, KABUL EDİLDİ ve PUSH EDİLDİ (15 Kasım 2026 — Commit `8454933df95c6de04813d3eb9499331ec86471dc`, 173 yeşil test, 0 analyze hatası; 4 durumlu reaktif kuyruk özeti, saf Dart `packages/mms_contracts` sözleşme paketi, WCAG 2.1 AAA [>= 7.0:1] rozet renkleri, DB hatasında `KUYRUK OKUNAMIYOR` koruması).
  - [ ] **Faz 1.3.1.2 — Background Sync Coordinator & Worker:** HENÜZ UYGULANMADI (Planlandı — Sıradaki Geliştirme Görevi; `ClientSyncService` arka plan worker'ı, periyodik timer, otomatik kuyruk tüketim döngüsü).
  - [ ] **Faz 1.3.2 — Satış Geçmişi ve Fiş Detayları:** Planlandı (Main Shell Tab 2 satış listesi, fiş detay modalı, nakit/kart dökümü).
  - [ ] **Faz 1.3.3 — Tam Satış İptali:** Planlandı (`BR-POS-08` gerekçeli tam fiş iptali, stok iadesi ve audit kaydı).
  - [ ] **Faz 1.3.4 — Kısmi Ürün İadesi:** Planlandı (`BR-POS-09` kalem bazında iade, hasarlı/satılabilir durum ayrımı `BR-POS-10`).
- [ ] **Faz 1.4 Adayı — Ürün ve Kategori Yönetimi:** Değerlendirme adayı (Henüz başlatma kararı verilmedi; Katalog CRUD, çoklu barkod tanımlama, fiyat geçmişi - Main Shell Tab 1).

---

## Faz 2 — Kimlik, Tenant ve Cihazlar
**Durum:** ⏳ Bekliyor  
- Pilot için Dinamik QR Kod ve cihaz eşleştirme
- Tek işletme sahibi (Owner) hesabı ve yerel kimlik doğrulaması
- Tenant ve store modeli
- Cihaz kaydı ve kalıcı cihaz kimliği (`device_id`)
- Gelecek SaaS için Supabase Auth ve RLS politikaları

---

## Faz 3 — Ürün ve Kategori Yönetimi
**Durum:** ⏳ Bekliyor *(Katalog CRUD bileşeni Faz 1.4 Aday Kapsamı olarak değerlendirilmektedir)*  
- Kategori CRUD (PC ve Mobil)
- Ürün CRUD (PC ve Mobil)
- Barkod okuma: PC'de USB HID, telefonda kamera
- Open Food Facts entegrasyonu ve öneri akışı
- Birim, gramaj ve maliyet yönetimi (kesirli miktar, pay/payda)
- Fiyat düzenleme ve fiyat geçmişi (`price_history`)
- Stok görüntüleme
- Pasifleştirme ve veri doğrulamaları

---

## Faz 4 — Stok ve Satış
**Durum:** 🔄 Kısmen Tamamlandı (Temel satış motoru Faz 1.2'de uygulandı; geçmiş/iptal Faz 1.3 kapsamındadır)  
- [x] **Hızlı sepet ve satış ekranı:** Windows masaüstü için Faz 1.2 ile tamamlandı (`PosScreen`, `CartNotifier`); MVP platformu olan Android istemcisi için ortak Flutter tabanı üzerinden Windows çekirdek ve senkronizasyon adımlarının ardından devreye alınacaktır.
- [x] **Barkodla satış:** Faz 1.2 ile tamamlandı (aynı barkodda miktar artırma, bilinmeyen/pasif barkod engeli).
- [x] **Toplam hesaplama:** Faz 1.2 ile tamamlandı (kuruş bazlı tam sayı, `double` aritmetiği yok; alt kuruş yuvarlama `OD-01` Half-Up ve `12.50 TL` gösterim standardı **ONAYLANDI**).
- [x] **Satış tamamlama ve atomik transaction ile stok düşüşü:** Faz 1.2 ile tamamlandı (`LocalPosRepository.checkoutCart`).
- [x] **Tekrarlanan işlemlere karşı idempotency:** Faz 1.2 ile tamamlandı (`idempotency_key` UUID v4).
- [ ] **Eksi stok ve uyuşmazlık denetim izi:** Eksi stok satış serbestliği (`allow` politikası) ve kasa uyarısı Faz 1.2 ile uygulandı; stok uyuşmazlıklarının `audit_logs` kaydı ve denetim izi altyapısı henüz tamamlanmamıştır (planlandı).
- [ ] **Satış geçmişi ve fiş detayları:** Faz 1.3.2 kapsamında planlandı.
- [ ] **Stok hareketleri geçmişi (`stock_movements`):** Veritabanı ve transaction kaydı tamamlandı; arayüz geçmiş görünümü planlandı.
- *Not:* Banka POS terminali entegrasyonu ilk sürümün kapsamı dışındadır.

---

## Faz 5 — Offline ve Senkronizasyon
**Durum:** 🔄 Kısmen Tamamlandı (Yerel kuyruk ve rozet tamamlandı; arka plan worker Faz 1.3.1.2 kapsamındadır)  
- [x] **Yerel kalıcı FIFO işlem kuyruğu:** Faz 1.1 ve Faz 1.2 ile tamamlandı (`packages/mms_client_storage`, `outbox_operations` tablosu, `device_id`, monotonik artan `client_seq`, `operation_id`).
- [x] **Tekrarlanan iletimlerde mükerrerlik koruması:** Faz 1.2 ile tamamlandı (`idempotency_key`).
- [x] **Senkronizasyon durumu arayüzü ve kuyruk izleme:** Faz 1.3.1.1 ile tamamlandı (`OutboxStatusBadge`, 4 durumlu `OutboxSummary`, WCAG AAA kontrastı, DB hatasında `KUYRUK OKUNAMIYOR` koruması).
- [ ] **Arka plan senkronizasyon koordinatörü ve worker:** Faz 1.3.1.2 kapsamında **HENÜZ UYGULANMADI (Sıradaki Geliştirme Görevi)** (`ClientSyncService` timer, otomatik kuyruk aktarımı).
- [ ] **Mağaza içi yerel ağ (Wi-Fi / LAN) üzerinden Windows Master Hub API senkronizasyonu:** Spike-01 ile backend hazırlandı; istemci entegrasyonu Faz 1.3.1.2 ve devamında planlandı.
- [ ] **Sunucu onayı (ACK) gelmeden `SYNCED` işaretlenmeme garantisi:** Protokol tanımlandı, worker ile doğrulanacaktır.
- [ ] **Çakışma tespiti (fiziksel satışlar asla silinmez) ve denetim kayıtları (`audit_logs`):** Protokol hazırlandı, canlı senkronizasyon ile test edilecektir.
- [ ] **Veri kurtarma ve kaza testleri:** Depolama seviyesinde test edildi; canlı ağ E2E testi planlandı.

---

## Faz 6 — Dashboard ve Yedekleme
**Durum:** ⏳ Bekliyor  
- Satış ve stok dashboard'u (PC ve Mobil)
- Finansal ayrım: Ciro, brüt kâr ve net kâr
- Kritik stoklar ve son hareketler
- Cihaz bağlantı durumları ve outbox gecikme metrikleri
- Windows Service `VACUUM INTO` yerel SQLite canlı anlık görüntüsü
- Google Drive istemci taraflı S5A-4 standardında AES-256-CBC, PKCS#7 padding, PBKDF2-HMAC-SHA256 (600.000 iterasyon) ve HMAC-SHA256 Encrypt-then-MAC şifreli bağımsız otomatik yedekleme
- Yedekleme geçmişi ve geri yükleme testleri

---

## Faz 7 — Pilot
**Durum:** ⏳ Bekliyor (Açık teknik koşulların karşılanması şartıyla — Henüz tamamlanmamıştır)  
- Arkadaşın marketinde kontrollü kurulum (Windows Master Hub ve Android telefonlar devrede)
- B-2 sertifika sabitleme, B-3 güvenli token depolama, SCM ve ACL koşullarının sahada doğrulanması
- Gerçek ürün, kamera/barkod ve satış verileriyle kullanım
- Elektrik ve yerel ağ kesintisi senaryoları
- Çoklu cihaz eşzamanlı satış testleri
- Kullanıcı geri bildirimleri
- Performans, güvenlik ve kullanılabilirlik iyileştirmeleri

---

## Faz 8 — Ticari Hazırlık
**Durum:** ⏳ Bekliyor  
- Paketleme ve kurulum (Windows installer, Mobil APK/bundle; iOS değerlendirmesi)
- Platforma uygun güncelleme sistemi
- Çok şubeli zincir marketler için bulut SaaS altyapısı (Supabase PostgreSQL / Auth geçişi)
- Müşteri ve SaaS abonelik yönetimi
- İzleme ve hata raporlama
- Teknik ve kullanıcı dokümantasyonu
- Destek ve yedekleme prosedürleri
- Pilot sonrası ticari fiyatlandırma ve satış planı
