# PROJECT_STATUS.md — Market POS (MMS) Mevcut Durum Raporu

*Bu belge her yeni yapay zekâ geliştirme oturumunda durum kontrolü amacıyla okunmalıdır.*  
*Son güncelleme: 30 Ekim 2026*

---

## 1. Aktif Aşama
**Faz 0 — Planlama ve Mimari Kararlar** (Devam Ediyor)

---

## 2. Mevcut Durum ve Ürün Tanımı

- **Ürün Konsepti:** **Market Management System (MMS)** — Profesyonel Market Yönetim SaaS Uygulaması. (Teknik klasör ve repo adı olarak `market-pos` korunmaktadır).
- **Ana Proje Dokümanı:** [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](../MARKET_POS_AI_STUDIO_BUILD_PLANI.md) (**v1.2**, 30 Ekim 2026) bağlayıcı ana referans olarak güncellenmiştir.
- **Arşiv:** 
  - v1.0 belgesi: [`docs/archive/MARKET_POS_AI_STUDIO_BUILD_PLANI_v1.0.md`](./archive/MARKET_POS_AI_STUDIO_BUILD_PLANI_v1.0.md)
  - v1.1 belgesi: [`docs/archive/MARKET_POS_AI_STUDIO_BUILD_PLANI_v1.1.md`](./archive/MARKET_POS_AI_STUDIO_BUILD_PLANI_v1.1.md)
- **Çoklu Cihaz Yaklaşımı:** Windows bilgisayar ve mobil telefonlar aynı temel market yönetim işlevlerine (ürün, satış, stok, dashboard, raporlama) sahiptir. Barkod girişi PC'de USB HID, mobilde kamera ile sağlanır.
- **Banka POS Kapsamı:** Banka POS terminali entegrasyonu ilk sürümün kapsamı dışındadır.
- **Git Altyapısı:** Depo `main` dalında başlatılmış, `.gitignore` devrededir; henüz `git add` veya `git commit` **yapılmamıştır**.
- **Kaynak Kodu:** **Henüz hiçbir Flutter/Dart uygulama kodu yazılmamıştır.**
- **Proje İskeleti:** Henüz `flutter create` çalıştırılmamıştır.

---

## 3. Faz 0 Durum Takibi

- [x] Temel ürün vizyonunun belirlenmesi (Market Management System - MMS, pilot market + SaaS hedefi)
- [x] İlk sürüm özelliklerinin belirlenmesi (ürün, stok, satış, dashboard, ciro/kâr ayrımı)
- [x] Çoklu cihazın yerel çalışma modeli (Drift + SQLite, PC ve telefon eşit işlev, offline-first)
- [x] Çoklu market SaaS kararı (tenant, store, user, device modeli)
- [x] Supabase + Google Drive bağımsız yedekleme hedefi
- [x] Ortak yapay zekâ talimat mimarisinin kurulması ve v1.2'ye uyarlanması
- [ ] Kesin veri modeli, alan tipleri ve ilişkilerin belirlenmesi
- [ ] Tenant ve şube izolasyonu kurallarının netleştirilmesi
- [ ] Ürün birimleri, barkod ilişkisi ve kesirli miktar kuralları
- [ ] Satış, sepet ve stok düşümü iş kurallarının yazılması
- [ ] Offline çakışma tespiti ve çözüm kurallarının netleştirilmesi
- [ ] Yedekleme sıklığı, saklama politikası ve geri yükleme prosedürünün detaylandırılması
- [ ] Windows, Android, iOS ve Web için yerel depolama doğrulaması
- [ ] Dağıtım ve uzaktan güncelleme yaklaşımının netleştirilmesi
- [ ] Faz 0 kabul kriterlerinin eksiksiz tamamlanması

---

## 4. Bir Sonraki Görev

**Faz 0 — İş Kuralları ve Veri Modeli:**
Ana plandaki 12 adet Faz 0 kabul kriterine yanıt veren detaylı iş kurallarının ve veri modellerinin dokümante edilmesi.

> [!WARNING]
> Faz 0 kabul kriterleri eksiksiz dokümante edilmeden ve kullanıcı onayı alınmadan **Faz 1'e geçilemez ve Flutter kodlamasına başlanamaz**.
