# Güvenlik ve Çoklu Kiracı (Security & Multi-Tenancy)

Bu belge, **Market POS** projesinin veri izolasyonu, kimlik doğrulama, yetkilendirme ve gizlilik standartlarını tanımlar.

---

## 1. Çoklu Market (Multi-Tenant) İzolasyonu

- Sistem veri modeli baştan çoklu marketi (SaaS) destekleyecek şekilde tasarlanmıştır:
  - `tenant`: İşletme veya market grubu.
  - `store`: Fiziksel şube/mağaza.
  - `user`: Sistem kullanıcısı.
  - `device`: Kasayı veya uygulamayı çalıştıran cihaz.
- Bütün veri tabloları (`categories`, `products`, `sales`, `stock_movements`, vb.) zorunlu olarak `tenant_id` alanı taşır.
- **İstemci Güvensizliği İlkesi:** İstemciden gelen `tenant_id` parametresi tek başına yetki kanıtı sayılamaz.
- **Supabase Row Level Security (RLS):** Merkezi veritabanında her tablo için RLS politikaları yazılır ve test edilir. Bir marketin kullanıcısı veya cihazı, başka bir marketin verisini kesinlikle sorgulayamaz ve değiştiremez.

---

## 2. Kimlik Doğrulama ve Yetkilendirme

- Kullanıcı kimlik doğrulama altyapısı olarak **Supabase Auth** kullanılır.
- Kullanıcıların şubelerdeki rolleri (`Owner`, `Manager`, `Cashier`) iş kuralları ve veri erişim sınırlarıyla güvenceye alınır. Sadece arayüzde buton gizlemek yetkilendirme sayılmaz.

---

## 3. Gizli Bilgilerin Korunması

- API anahtarları, Supabase Service Role anahtarları, veritabanı şifreleri ve Google Drive OAuth sırları **asla** kaynak koduna veya Git deposuna yazılmaz.
- Ortam değişkenleri `.env` dosyaları üzerinden yerel geliştirmede yönetilir; bu dosyalar `.gitignore` ile dışarıda bırakılır. Projede yalnızca sır içermeyen `.env.example` şablonu paylaşılabilir.

---

## 4. Google Drive OAuth ve Yedekleme Güvenliği

- Google Drive yedekleme entegrasyonunda OAuth token'ları güvenli platform anahtarlıklarında (secure storage) saklanır.
- Alınan yedek dosyaları dışarı aktarılmadan önce mümkünse şifrelenir ve dosya bütünlük kontrolü (checksum) ile korunur.

---

## 5. Denetim Kayıtları (Audit Logs)

- Kritik işlemler (fiyat değişimi, manuel stok düzeltmesi, iade işlemi, kullanıcı yetki değişimi) `audit_logs` tablosuna zaman damgası, kullanıcı ve cihaz bilgisi ile kaydedilir.

