# Offline-First ve Senkronizasyon Kuralları

Bu belge, **Market POS (MMS)** projesinde internet ve yerel ağ kesintilerinde yerel çalışabilirlik, çoklu cihaz senkronizasyonu ve veri tutarlılığı kurallarını belirler.

---

## 1. Temel İlke ve Yerel Veritabanı

- Uygulama, internet bağlantısı veya mağaza içi yerel ağ olmasa dahi satış, ürün arama, barkod okuma ve stok hareketlerini kesintisiz yürütebilmelidir.
- Mobil (Android/iOS) ve masaüstü (Windows) istemcilerde yerel operasyonel veri tabanı olarak **Drift + SQLite** (`packages/mms_client_storage`, Windows'ta `%LOCALAPPDATA%\MarketMMS\client_local.db`, mobilde `mms_client.db`) kullanılır.
- SQLite açılışında WAL modu (`PRAGMA journal_mode = WAL;`) ve kilitlenme önleyici zaman aşımı (`PRAGMA busy_timeout = 5000;`) zorunludur.
- Web ortamında SQLite/WASM veya uyumlu adaptörler platform doğrulama adımlarıyla netleştirilecektir.

---

## 2. Atomik Yerel Transaction

- Bir satış tamamlandığında;
  1. `sales` kaydı,
  2. `sale_items` satırları (fiyat ve ürün adı anlık snapshot'ı ile),
  3. `stock_movements` (stok düşüşü) kaydı,
  4. `outbox_operations` / `sync_operations` (senkronizasyon kuyruğu) kaydı,
  **aynı yerel transaction içinde** atomik olarak yazılmalıdır.
- Kısmi yazım (satışın kaydedilip stoğun düşmemesi veya senkronizasyon kaydının oluşmaması) kesinlikle engellenmelidir.

---

## 3. Kalıcı Senkronizasyon Kuyruğu (Outbox)

- **Senkronizasyon Hedefi:** İstemciler mağaza içi yerel Wi-Fi / LAN üzerinden **Windows Local Master Hub API**'sine (Windows masaüstü ise loopback `127.0.0.1` üzerinden) bağlanır.
- **LAN ve WAN Ayrımı:** Senkronizasyon için geniş alan internet (WAN) bağlantısı zorunlu değildir. Mağazanın interneti kesilse dahi yerel Wi-Fi / LAN üzerinden senkronizasyon kesintisiz devam eder.
- **Onaylanmış Kuyruk Kuralları (`CONFIRMED`):**
  - **Persistent Kimlik ve Sayaç:** Cihazda kalıcı `device_id` ve monotonik artan `client_seq` (`client_sequence_number`) tutulur.
  - **Tekil Operasyon:** Her kuyruk kaydı tekil bir `operation_id` taşır.
  - **Deterministik FIFO:** İşlemler kuyruktan kesinlikle artan sıra numarasıyla (FIFO) sunucuya aktarılır.
  - **Sunucu Onayı (ACK) Şartı:** Merkezi sunucudan başarılı HTTP yanıtı (ACK) alınmadan yerel işlem kaydı asla `SYNCED` olarak mühürlenemez.
- **Açık Tasarım Kararları (`OPEN DECISION`):**
  - Worker kiralama (lease) mekanizması, kaza kurtarma kilit süreleri ve başarısız iletimlerdeki yeniden deneme / geri çekilme parametreleri henüz onaylanmamış olup `OPEN DECISION` statüsündedir.
- Gelecek çok şubeli SaaS aşamasında bu kuyruk bulut Supabase merkezi veritabanına aktarılacaktır.

---

## 4. Idempotency (Mükerrerlik Koruması)

- Her satış işlemi, cihazda üretilen benzersiz bir `idempotency_key` (UUID v4) taşır.
- Ağ kesintisi veya tekrar deneme nedeniyle aynı satış merkezi veritabanına birden fazla kez iletilirse, ikinci istek yeni bir satış veya mükerrer stok düşümü yaratmaz; ilk işlemin sonucunu döndürür.

---

## 5. Çoklu Cihazın Çevrimdışı Sınırları ve Çakışma Yönetimi

- İki bağımsız çevrimdışı cihaz aynı üründen kalan son stoğu eşzamanlı olarak satabilir. Cihazlar birbirinden habersiz olduğundan çevrimdışıyken bunun engellenmesi fiziksel olarak imkansızdır.
- **Kural:** Bağlantı geldiğinde her iki satış da gerçekte gerçekleşmiş fiziksel işlem olarak korunur; **fiziksel satışlar asla çakışma nedeniyle silinmez**.
- **Eksi Stok Politikası:** Stok seviyesinin sıfırın altına düşmesine izin verilir (`allow`).
- Oluşan stok uyuşmazlığı tespit edilir, denetim kaydına (`audit_logs`) alınır ve yetkili kullanıcıya stok sayımı ve düzeltme bildirimi olarak yansıtılır.
- Ürün ve geçmiş satış kayıtları sessizce güncellenemez veya silinemez; izlenebilir ters kayıt / düzeltme hareketi oluşturulur.
