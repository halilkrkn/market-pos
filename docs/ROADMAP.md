# ROADMAP.md — Geliştirme Yol Haritası (Faz 0–8)

Bu belge, [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](../MARKET_POS_AI_STUDIO_BUILD_PLANI.md) (**v1.2**) Bölüm 9'da tanımlanan 9 fazlık geliştirme yol haritasının çalışma amaçlı görünümüdür. 

> [!IMPORTANT]
> Ürün artık bir **Market Management System (MMS)** olarak konumlandırılmıştır. Fazların sırası, kapsamı ve kabul kriterleri ana doküman ile birebir aynıdır; yeni faz veya özellik eklenemez.

---

## Faz 0 — Planlama ve Mimari Kararlar
**Durum:** 🔄 Devam Ediyor  
**Açıklama:** Veri modelleri, tenant izolasyonu, stok/satış iş kuralları, PC ve telefonda eşit çoklu cihaz modeli, offline çakışma çözümü ve platform depolama doğrulamalarının tamamlanması.  
**Kural:** Faz 0 kabul kriterleri dokümante edilmeden ürün kodlamasına başlanmayacaktır.

---

## Faz 1 — Temel Altyapı
**Durum:** ⏳ Bekliyor  
- Flutter proje iskeleti
- Katman ve modül sınırları (Clean Architecture)
- Drift ve migration sistemi
- Riverpod ve go_router
- Hata yönetimi ve logging
- Tema ve ortak responsive UI bileşenleri
- Otomatik test altyapısı

---

## Faz 2 — Kimlik, Tenant ve Cihazlar
**Durum:** ⏳ Bekliyor  
- Supabase Auth entegrasyonu
- Tenant ve store modeli
- Kullanıcı üyelikleri ve temel yetkiler
- Cihaz kaydı (Windows PC ve telefonlar)
- Tenant izolasyonu ve RLS güvenlik testleri

---

## Faz 3 — Ürün ve Kategori Yönetimi
**Durum:** ⏳ Bekliyor  
- Kategori CRUD (PC ve Mobil)
- Ürün CRUD (PC ve Mobil)
- Barkod okuma: PC'de USB HID, telefonda kamera
- Open Food Facts entegrasyonu ve öneri akışı
- Birim, gramaj ve maliyet yönetimi
- Fiyat düzenleme ve fiyat geçmişi
- Stok görüntüleme
- Pasifleştirme ve veri doğrulamaları

---

## Faz 4 — Stok ve Satış
**Durum:** ⏳ Bekliyor  
- Hızlı sepet ve satış ekranı (PC ve Mobil)
- Barkodla satış (aynı barkodda miktar artırma)
- Toplam hesaplama (kuruş bazlı tam sayı, `double` yok)
- Satış tamamlama ve atomik transaction ile stok düşüşü
- Stok hareketleri geçmişi
- Satış geçmişi
- Tekrarlanan işlemlere karşı idempotency
- *Not:* Banka POS terminali entegrasyonu bu sürümün kapsamı dışındadır.

---

## Faz 5 — Offline ve Senkronizasyon
**Durum:** ⏳ Bekliyor  
- Yerel kalıcı işlem kuyruğu (`sync_operations`)
- Otomatik arka plan senkronizasyonu
- Tekrar deneme politikası (exponential backoff)
- Çakışma tespiti (satışlar asla silinmez)
- Çoklu cihaz senaryoları ve audit kayıtları
- Senkronizasyon durumu arayüzü
- Veri kurtarma testleri

---

## Faz 6 — Dashboard ve Yedekleme
**Durum:** ⏳ Bekliyor  
- Satış ve stok dashboard'u (PC ve Mobil)
- Finansal ayrım: Ciro, brüt kâr ve net kâr
- Kritik stoklar ve son hareketler
- Cihaz bağlantı durumları
- Supabase yerleşik yedekleme yapılandırması
- Google Drive bağımsız otomatik yedekleme
- Yedekleme geçmişi ve geri yükleme testleri

---

## Faz 7 — Pilot
**Durum:** ⏳ Bekliyor  
- Arkadaşın marketinde kontrollü kurulum (PC ve telefonlar devrede)
- Gerçek ürün, kamera/barkod ve satış verileriyle kullanım
- Elektrik ve internet kesintisi senaryoları
- Çoklu cihaz eşzamanlı satış testleri
- Kullanıcı geri bildirimleri
- Performans, güvenlik ve kullanılabilirlik iyileştirmeleri

---

## Faz 8 — Ticari Hazırlık
**Durum:** ⏳ Bekliyor  
- Paketleme ve kurulum (Windows installer, Mobil APK/bundle)
- Platforma uygun güncelleme sistemi
- Müşteri ve SaaS abonelik yönetimi
- İzleme ve hata raporlama
- Teknik ve kullanıcı dokümantasyonu
- Destek ve yedekleme prosedürleri
- Pilot sonrası ticari fiyatlandırma ve satış planı
