# ROADMAP.md — Geliştirme Yol Haritası (Faz 0–8)

Bu belge, [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](../MARKET_POS_AI_STUDIO_BUILD_PLANI.md) (**v1.4**) Bölüm 9'da tanımlanan 9 fazlık geliştirme yol haritasının çalışma amaçlı görünümüdür. 

> [!IMPORTANT]
> Ürün bir **Market Management System (MMS)** olarak konumlandırılmıştır. Pilot aşamada **Windows Local Master Hub** mimarisi esastır; çok şubeli SaaS fazı için bulut hazır mimari korunur. Fazların sırası, kapsamı ve kabul kriterleri ana doküman ile tam uyumludur.

---

## Faz 0 — Planlama ve Mimari Kararlar
**Durum:** ✅ TAMAMLANDI (4 Kasım 2026)  
**Açıklama:** Veri modelleri, tenant izolasyonu, stok/satış iş kuralları, PC ve telefonda eşit çoklu cihaz modeli, offline çakışma çözümü, platform depolama doğrulamaları ve SPIKE-01 (Dart Shelf + SQLite single-writer) 139 testle tamamlanmıştır.

---

## Faz 1 — Temel Altyapı ve MVP Uygulama
**Durum:** 🔄 DEVAM EDİYOR  
- [x] **Faz 1.1 — Windows Client Foundation:** TAMAMLANDI ve KABUL EDİLDİ (Commit `8676586`, Tag `v1.1.0-windows-client-foundation`, 221 yeşil test).
- [x] **DT-01.1 — Agent Governance Audit:** TAMAMLANDI.
- [x] **DT-01.2 — Skills Security & License Review / Activation:** TAMAMLANDI (5 beceri aktif).
- [x] **DT-01.3 — Documentation Reconciliation:** Teknik Çalışma Tamamlandı (Proje Sahibi Kabulü Bekleniyor).
- [ ] **DT-01.4 — Instruction Infrastructure Integration:** Henüz Başlamadı (Planlandı).
- [ ] **Faz 1.2 — Kasa Satış Ekranı & Sepet Yönetimi:** Planlandı (Kullanıcı Onayı Bekleniyor).

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
**Durum:** ⏳ Bekliyor  
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
**Durum:** ⏳ Bekliyor  
- Hızlı sepet ve satış ekranı (PC ve Mobil)
- Barkodla satış (aynı barkodda miktar artırma)
- Toplam hesaplama (kuruş bazlı tam sayı, `double` yok; alt kuruş yuvarlama: `OPEN DECISION`)
- Satış tamamlama ve atomik transaction ile stok düşüşü
- Stok hareketleri geçmişi (`stock_movements`, 9 hareket türü)
- Satış geçmişi ve fiş detayları
- Tekrarlanan işlemlere karşı idempotency (`idempotency_key`)
- Eksi stok politikası (`allow`) ve uyuşmazlık denetim izi
- *Not:* Banka POS terminali entegrasyonu ilk sürümün kapsamı dışındadır.

---

## Faz 5 — Offline ve Senkronizasyon
**Durum:** ⏳ Bekliyor  
- Yerel kalıcı FIFO işlem kuyruğu (`device_id`, monotonik artan `client_seq`, `operation_id`)
- Mağaza içi yerel ağ (Wi-Fi / LAN) üzerinden Windows Master Hub API senkronizasyonu
- Sunucu onayı (ACK) gelmeden `SYNCED` işaretlenmeme garantisi
- Tekrarlanan iletimlerde mükerrerlik koruması (`idempotency_key`)
- Çakışma tespiti (fiziksel satışlar asla silinmez)
- Çoklu cihaz senaryoları ve denetim kayıtları (`audit_logs`)
- Senkronizasyon durumu arayüzü ve kuyruk izleme (kiralama/retry detayları: `OPEN DECISION`)
- Veri kurtarma ve kaza testleri

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
**Durum:** ⏳ Bekliyor (Açık teknik koşulların karşılanması şartıyla)  
- Arkadaşın marketinde kontrollü kurulum (Windows Master Hub ve telefonlar devrede)
- B-2 sertifika sabitleme, B-3 güvenli token depolama, SCM ve ACL koşullarının sahada doğrulanması
- Gerçek ürün, kamera/barkod ve satış verileriyle kullanım
- Elektrik ve yerel ağ kesintisi senaryoları
- Çoklu cihaz eşzamanlı satış testleri
- Kullanıcı geri bildirimleri
- Performans, güvenlik ve kullanılabilirlik iyileştirmeleri

---

## Faz 8 — Ticari Hazırlık
**Durum:** ⏳ Bekliyor  
- Paketleme ve kurulum (Windows installer, Mobil APK/bundle)
- Platforma uygun güncelleme sistemi
- Çok şubeli zincir marketler için bulut SaaS altyapısı (Supabase PostgreSQL / Auth geçişi)
- Müşteri ve SaaS abonelik yönetimi
- İzleme ve hata raporlama
- Teknik ve kullanıcı dokümantasyonu
- Destek ve yedekleme prosedürleri
- Pilot sonrası ticari fiyatlandırma ve satış planı
