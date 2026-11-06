# Test ve Doğrulama Stratejisi (Testing Strategy)

Bu belge, **Market POS (MMS)** projesinde kalite güvencesi, test seviyeleri ve test edilebilirlik standartlarını belirler.

---

## 1. Risk Temelli Test Yaklaşımı

Sabit ve yapay bir "yüzde X test kapsamı" kuralı yerine, projenin en kritik ve finansal risk taşıyan alanlarına odaklanan risk temelli bir test stratejisi uygulanır.

Öncelikli test alanları:
1. **Finansal Doğruluk (`CONFIRMED`):** Para hesaplamaları, sepet ara toplamı, miktar ve genel satış toplamı hesaplarının kuruş bazlı tamsayılarla (`int` / `BIGINT`) yapılması; `double` aritmetiği kesinlikle kullanılmaz. Satış anındaki birim fiyat ve ad snapshot olarak korunur.
   - *Not 1:* Alt kuruş kesirli işlemler için uygulanacak yuvarlama yöntemi henüz onaylanmamış olup `OPEN DECISION` statüsündedir.
   - *Not 2:* Vergi (KDV), indirim, kampanya ve benzeri finansal kurallar henüz onaylanmış MVP gereksinimi değildir; bu tür ek hesaplamalar onaylandığı takdirde test kapsamına alınacak açık/öneri (`OPEN`/`PROPOSED`) konularıdır. Henüz onaylanmamış özellikler için zorunlu test kuralı işletilemez.
2. **Atomik Veri Yazımı (`CONFIRMED`):** Satış, sepet satırları, stok düşümü ve senkronizasyon kuyruğu yazımının aynı yerel transaction içinde tamamlanması.
3. **Senkronizasyon ve Idempotency (`CONFIRMED`):** Tekrarlanan isteklerin mükerrer satış veya mükerrer stok düşümü oluşturmaması (`idempotency_key`), kalıcı cihaz kimliği (`device_id`) ve monotonik sayaç (`client_seq`), deterministik FIFO sırası ve sunucu ACK gelmeden `SYNCED` işaretlenmeme garantisi.
4. **Çoklu Kiracı İzolasyonu:** Pilot aşamasında Windows Master Hub API tenant doğrulaması; gelecek SaaS aşamasında Supabase RLS politikalarının farklı marketlerin verisini kesin olarak izole ettiğinin doğrulanması.

---

## 2. Test Seviyeleri

### 2.1 Birim Testleri (Unit Tests)
- `domain` katmanındaki entity, value object (ör. `Money`) ve saf Dart iş kuralları için yazılır.
- Dış bağımlılıklar (repository arayüzleri) mock'lanır.
- Hızlı çalışmalı ve dış servislere/veritabanına ihtiyaç duymamalıdır.

### 2.2 Entegrasyon Testleri (Integration Tests)
- Drift yerel veritabanı DAO sorguları ve şema migration testleri (`packages/mms_client_storage`).
- **Gerçek FFI SQLite Zorunluluğu:** SQLite WAL eşzamanlılığı, `PRAGMA busy_timeout = 5000;`, kaza kurtarma (crash recovery) ve çoklu işlem kilitlenmesi testleri mutlaka gerçek FFI SQLite sürücüsü ile test edilmelidir. Basit mock'lar SQLite eşzamanlılık ve lock davranışını simüle edemez.
- Windows Master Hub (Dart Shelf) merkezi API entegrasyonu, Single-Writer yazma kuyruğu ve dinamik token doğrulama testleri (`test_spikes/spike_01_backend`).
- Kalıcı senkronizasyon kuyruğu (Outbox) FIFO sıralı aktarım, `idempotency_key` ve ACK teyidi testleri. (Worker kiralama ve yeniden deneme mekanizmaları `OPEN DECISION` statüsündedir).
- Gelecek SaaS için Supabase veri erişim katmanı ve RLS politikalarının testleri.

### 2.3 Widget ve UI Testleri (Gerektiğinde)
- Kritik kullanıcı akışları: Barkod okuma sonrası sepetin güncellenmesi, hızlı tuşlar, hata ve çevrimdışı uyarılarının doğru gösterimi.

### 2.4 Uçtan Uca (E2E) ve Senaryo Testleri
- Barkod okuma $\rightarrow$ Sepete ekleme $\rightarrow$ Satışı tamamlama $\rightarrow$ Stok hareketi kontrolü.
- Mağaza içi yerel ağı (Wi-Fi / LAN) kesme $\rightarrow$ Çevrimdışı satış yapma $\rightarrow$ Ağı yeniden bağlama $\rightarrow$ Master Hub'da satışı doğrulama.
- `VACUUM INTO` anlık görüntü alma ve S5A-4 standardında AES-256-CBC, PKCS#7 padding, PBKDF2-HMAC-SHA256 ve HMAC-SHA256 Encrypt-then-MAC şifreli Google Drive yedekleme/geri yükleme senaryosu.

---

## 3. Test Edilebilirlik Kuralları

- Kod yazılırken bağımlılık enjeksiyonuna (Dependency Injection / Riverpod) uygun olarak tasarlanmalıdır.
- Testlerde rastgele zaman veya donanım bağımlılıklarından kaçınılmalı, zaman ve cihaz kimlikleri mock'lanabilir olmalıdır.
