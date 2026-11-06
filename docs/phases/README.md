# Faz Yönetimi ve Aşamalar İndeksi (Phases Index)

Bu dizin, **Market Management System (MMS)** projesinin [`docs/ROADMAP.md`](../ROADMAP.md) belgesinde tanımlanan 9 fazlık geliştirme yaşam döngüsünü, her fazın resmi açılış hedeflerini, test sonuçlarını ve kapanış raporlarını standartlaştırılmış şablonlarla takip eder.

---

## 1. Faz Yaşam Döngüsü ve Geçiş Kuralları

1. **Katı Sıralama Kuralı:** Faz kabul kriterleri eksiksiz karşılanmadan ve kullanıcıdan açık onay alınmadan sonraki faza geçilemez.
2. **Kodlama Kısıtı:** Faz 0 resmi olarak kapatılmadan Flutter/Dart kaynak kodu yazılamaz.
3. **Kapanış Raporu Zorunluluğu:** Her faz bitiminde [`PHASE-TEMPLATE.md`](./PHASE-TEMPLATE.md) şablonu kullanılarak detaylı bir kapanış raporu hazırlanmalıdır.

---

## 2. Faz Durum Özeti

| Faz | Faz Başlığı | Durum | Kapanış Raporu / Not |
| :---: | :--- | :---: | :--- |
| **Faz 0** | Planlama ve Mimari Kararlar | **🔄 Aktif (Devam Ediyor)** | Dokümantasyon, veri modeli ve spike planları tamamlanıyor. |
| **Faz 1** | Temel Altyapı (Flutter İskeleti, Drift, Riverpod) | ⏳ Bekliyor | Faz 0 kapanış onayı bekleniyor. |
| **Faz 2** | Kimlik, Tenant, Cihaz Eşleştirme ve Yerel Güvenlik | ⏳ Bekliyor | — |
| **Faz 3** | Ürün ve Kategori Yönetimi (USB HID & Kamera Barkod) | ⏳ Bekliyor | — |
| **Faz 4** | Stok ve Satış (Sepet, Kuruş Hesabı, Atomik Transaction) | ⏳ Bekliyor | — |
| **Faz 5** | Offline ve Senkronizasyon (Outbox, ACK, Çakışma Yönetimi)| ⏳ Bekliyor | — |
| **Faz 6** | Dashboard ve Bağımsız Google Drive Yedekleme | ⏳ Bekliyor | — |
| **Faz 7** | Pilot Market Kurulumu ve Saha Testleri | ⏳ Bekliyor | — |
| **Faz 8** | Ticari Hazırlık, Paketleme ve Çok Şubeli SaaS Genişlemesi | ⏳ Bekliyor | — |

