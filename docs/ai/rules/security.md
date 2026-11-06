# Güvenlik ve Çoklu Kiracı (Security & Multi-Tenancy)

Bu belge, **Market POS (MMS)** projesinin veri izolasyonu, kimlik doğrulama, yetkilendirme ve gizlilik standartlarını tanımlar.

---

## 1. Çoklu Market (Multi-Tenant) İzolasyonu

- Sistem veri modeli baştan çoklu marketi (SaaS) destekleyecek şekilde tasarlanmıştır:
  - `tenant`: İşletme veya market grubu.
  - `store`: Fiziksel şube/mağaza.
  - `user`: Sistem kullanıcısı.
  - `device`: Kasayı veya uygulamayı çalıştıran cihaz.
- Bütün veri tabloları (`categories`, `products`, `sales`, `stock_movements`, vb.) zorunlu olarak `tenant_id` alanı taşır.
- **İstemci Güvensizliği İlkesi:** İstemciden gelen `tenant_id` parametresi tek başına yetki kanıtı sayılamaz.
- **Veri İzolasyonu (Pilot ve Gelecek SaaS):**
  - Pilot aşamasında veri izolasyonu Windows Local Master Hub API'sinin iş kuralları seviyesinde sorumluluğudur; merkezi API veri erişiminde tenant ve store sınırlarını uygular.
  - Gelecek bulut SaaS aşamasında merkezi veritabanında her tablo için **Supabase Row Level Security (RLS)** politikaları uygulanır ve doğrulanır.

---

## 2. Kimlik Doğrulama, Eşleştirme ve Sır Depolama

- **Pilot Kimlik Modeli:** Pilot aşaması tek işletme sahibi (Owner) hesabı ile yürütülür. Kasiyer ve personel rolleri MVP kapsamı dışındadır (`CONFIRMED`).
- **Dinamik QR Kod ve Eşleştirme:** Mobil cihazlar, Windows ana kasa ekranında gösterilen dinamik QR kod ve tek seferlik eşleştirme token'ı aracılığıyla yerel ağ üzerinden sisteme dahil edilir.
- **Güvenli Sır Depolama (Koşul B-3):** Cihaz token'ları, API anahtarları ve şifreleme anahtarları işletim sisteminin yerel güvenli depolama mekanizmalarında saklanmalıdır:
  - Windows: **DPAPI** (`pepper.dpapi`)
  - Android: **Android Keystore**
  - iOS: **iOS Keychain**
- **Mobil Sertifika Sabitleme (Koşul B-2):** Mobil cihazların mağaza içi Wi-Fi / LAN üzerinden Windows Master Hub HTTPS API'sine güvenle bağlanabilmesi için yerel Root CA sertifika sabitlemesi (Certificate Pinning) zorunludur.
- **Gelecek SaaS Kimlik Modeli:** Çok şubeli ve bulut SaaS aşamasında kullanıcı kimlik doğrulama altyapısı olarak **Supabase Auth** devreye alınacaktır.

---

## 3. Gizli Bilgilerin Korunması

- API anahtarları, servis anahtarları, `pepper.dpapi`, veritabanı şifreleri ve Google Drive OAuth sırları **asla** kaynak koduna veya Git deposuna yazılmaz.
- Ortam değişkenleri `.env` dosyaları üzerinden yerel geliştirmede yönetilir; bu dosyalar `.gitignore` ile dışarıda bırakılır. Projede yalnızca sır içermeyen `.env.example` şablonu paylaşılabilir.

---

## 4. Google Drive OAuth ve Yedekleme Güvenliği

- Google Drive yedekleme entegrasyonunda OAuth token'ları güvenli platform anahtarlıklarında (secure storage) saklanır.
- Alınan SQLite canlı anlık görüntüleri (`VACUUM INTO`), harici Google Drive alanına aktarılmadan önce istemci tarafında S5A-4 standardında **AES-256-CBC** (PKCS#7 padding, PBKDF2-HMAC-SHA256 600.000 iterasyon, 16 bayt salt ve IV) ve **HMAC-SHA256 Encrypt-then-MAC** ile şifrelenir ve dosya bütünlüğü doğrulanır.

---

## 5. Denetim Kayıtları (Audit Logs)

- Kritik işlemler (fiyat değişimi, manuel stok düzeltmesi, iade işlemi, negatif stok uyuşmazlığı, kullanıcı yetki değişimi) `audit_logs` tablosuna zaman damgası, kullanıcı ve cihaz bilgisi ile kaydedilir.
