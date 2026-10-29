# Offline-First ve Senkronizasyon Kuralları

Bu belge, **Market POS** projesinde internet kesintilerinde yerel çalışabilirlik, çoklu cihaz senkronizasyonu ve veri tutarlılığı kurallarını belirler.

---

## 1. Temel İlke ve Yerel Veritabanı

- Uygulama, internet bağlantısı olmasa dahi satış, ürün arama, barkod okuma ve stok hareketlerini kesintisiz yürütebilmelidir.
- Mobil ve masaüstü istemcilerde yerel veri tabanı olarak **Drift + SQLite** kullanılır.
- Web ortamında SQLite/WASM veya uyumlu adaptörler platform doğrulama adımlarıyla netleştirilecektir.

---

## 2. Atomik Yerel Transaction

- Bir satış tamamlandığında;
  1. `sales` kaydı,
  2. `sale_items` satırları,
  3. `stock_movements` (stok düşüşü) kaydı,
  4. `sync_operations` (senkronizasyon kuyruğu) kaydı,
  **aynı yerel transaction içinde** atomik olarak yazılmalıdır.
- Kısmi yazım (satışın kaydedilip stoğun düşmemesi veya senkronizasyon kaydının oluşmaması) kesinlikle engellenmelidir.

---

## 3. Kalıcı Senkronizasyon Kuyruğu ve Tekrar Deneme

- Yerel veritabanında gerçekleştirilen her kritik işlem için `sync_operations` tablosunda bekleyen bir kayıt oluşturulur.
- Senkronizasyon servisi internet erişimi tespit ettiğinde bu kuyruktaki işlemleri sırayla Supabase merkezi veritabanına aktarır.
- Ağ hatası durumunda işlem silinmez; artan aralıklarla (exponential backoff) tekrar denenir.

---

## 4. Idempotency (Mükerrerlik Koruması)

- Her satış işlemi, cihazda üretilen benzersiz bir `idempotency_key` taşır.
- Ağ kesintisi veya tekrar deneme nedeniyle aynı satış merkezi veritabanına birden fazla kez iletilirse, ikinci istek yeni bir satış veya stok düşümü yaratmaz; ilk işlemin sonucunu döndürür.

---

## 5. Çoklu Cihazın Çevrimdışı Sınırları ve Çakışma Yönetimi

- İki bağımsız çevrimdışı cihaz aynı üründen kalan son stoğu eşzamanlı olarak satabilir. Cihazlar birbirinden habersiz olduğundan çevrimdışıyken bunun engellenmesi fiziksel olarak imkansızdır.
- **Kural:** Bağlantı geldiğinde her iki satış da gerçekte gerçekleşmiş fiziksel işlem olarak korunur; **satışlar asla çakışma nedeniyle silinmez**.
- Oluşan stok uyuşmazlığı tespit edilir, denetim kaydına (`audit_logs`) alınır ve yetkili kullanıcıya stok düzeltme bildirimi olarak yansıtılır.
- Ürün ve geçmiş satış kayıtları sessizce güncellenemez veya silinemez; izlenebilir ters kayıt / düzeltme hareketi oluşturulur.

