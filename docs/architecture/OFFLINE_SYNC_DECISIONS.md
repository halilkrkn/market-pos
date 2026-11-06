# Market Management System (MMS) — Offline Senkronizasyon Mimari Kararları (Offline Sync Architecture Decisions)

**Doküman Kodu:** `OFFLINE_SYNC_DECISIONS.md`  
**Sürüm:** 1.1 (Teknik Denetim Sonrası Sertleştirilmiş Sürüm)  
**Tarih:** 31 Ekim 2026  
**Durum:** Faz 0 — Senkronizasyon Mimari Karar Kayıtları (Teknik Doğrulama Tamamlandı)  
**Ana Referans Doküman:** `MARKET_POS_AI_STUDIO_BUILD_PLANI.md` (v1.2.2)  
**İlgili Tasarım Dokümanı:** `docs/architecture/OFFLINE_SYNC_PROTOCOL.md` (v1.1 Sertleştirilmiş)  
**Denetim Raporu:** `docs/architecture/OFFLINE_SYNC_TECHNICAL_VALIDATION.md` (v1.0)  
**Teknik Proje / Klasör Adı:** `market-pos`  
**Ürün Tanımı:** Market Management System (MMS) — Profesyonel Market Yönetim SaaS Uygulaması  

---

## 1. Amaç ve Kapsam

Bu doküman, **Market Management System (MMS)** projesinde offline-first mimarisi ve Outbox senkronizasyon protokolü tasarlanırken ve bağımsız denetimden geçirilirken alınan kesin teknik kararları, değerlendirilen alternatifleri ve tercih gerekçelerini kayıt altına alır.

> [!NOTE] Mimari Referans Notu (Windows Local Master Hub & SQLite)
> Bu dokümandaki kararlar MMS Outbox senkronizasyon mantığının temellerini oluşturur. Pilot mimarisinde merkezi sunucu **Windows Local Master Hub (Windows Service + Merkezi SQLite)** olarak çalışır; tüm uç cihazlar (Flutter Masaüstü, Android, iOS) yerel ağ (LAN) üzerinden bu yerel API'ye bağlanır. Dokümanda yer alan Supabase, PostgreSQL transaction, Edge Function ve PostgreSQL RLS referansları tarihsel tasarım ve **Gelecek SaaS** opsiyonu olarak muhafaza edilmektedir. Henüz kesinleşmemiş veri modeli şeması ve kuyruk alanları ise Aşama 6B-2 ve Faz 1'de ele alınacaktır.

---

## 2. Mimari Karar Kayıtları (Decisions)

---

### Karar 1: Meta-Veri Şeridi ve Medya Şeridi Ayrımı (`FND-SYNC-02`)
- **Bağlam:** Bir yandan kasada satış fişleri kesilirken, diğer yandan ürün görselleri veya katalog güncellemelerinin işlenmesi.
- **Değerlendirilen Alternatifler:**
  1. *İş Mantığına Göre Ayrım (Satış Şeridi vs. Ürün Şeridi):* Satışları bir şeride, ürün/fiyat güncellemelerini başka şeride koymak. Çevrimdışıyken açılan yeni bir ürünün hemen ardından yapılan satışta, satış şeridi ürün şeridini geçerse sunucuda foreign key ihlali oluşur.
  2. *İlişkisel Veri ve İkili Dosya (Blob) Ayrımı (Seçilen Yaklaşım):*  
     - **Lane 1 (Meta-Veri Şeridi):** Tüm ilişkisel tablolar (`products`, `prices`, `sales`, `refunds`, `stock_movements`). Tek bir ortak `client_sequence_number` ile kesin nedensel FIFO sırasıyla çalışır. Ürün ekleme küçük bir JSON olduğundan satışı geciktirmez.
     - **Lane 2 (Medya Şeridi):** Yalnızca `product_images` (JPEG/WebP ikili dosyaları). Arka planda asenkron çalışır; başarısız olması veya gecikmesi satış işlemlerini kesinlikle engellemez.
- **Tercih Gerekçesi:**
  - İlişkisel bütünlük ve nedensel sıralama %100 korunur.
  - Ağır medya transferleri kritik POS işlemlerini asla bloke edemez.
- **Durum:** `[CONFIRMED]`

---

### Karar 2: Yerel Atomik Transaction ile Outbox Yazımı
- **Bağlam:** Satış fişi kaydedildiğinde senkronizasyon kaydının tutarlılığı.
- **Karar:** `sales`, `sale_items`, `stock_movements` ve `sync_operations` tek bir SQLite transaction bloğu içinde kaydedilir.
- **Durum:** `[CONFIRMED]`

---

### Karar 3: Cihaz Bazında Monotonik Sıra Numarası (`client_sequence_number`) ve FIFO
- **Bağlam:** Aynı cihazdan çıkan işlemlerin sunucuya deterministik sıralamayla teslim edilmesi (`NEW-02`).
- **Karar:** Her cihaz kendi yerel SQLite sayacı ile bağımsız bir `client_sequence_number` üretir. Sunucu her cihazın kuyruğunu kendi içinde kesin FIFO sırasıyla kabul eder.
- **Durum:** `[CONFIRMED]`

---

### Karar 4: Sunucu Inbox Defteri (`processed_operations`) ve Çift Yönlü Idempotency
- **Bağlam:** Ağ kopmalarında istemcinin aynı satışı veya iadeyi birden fazla kez post etmesi (`BR-SYNC-03`).
- **Karar:** Sunucuda tüm cihaz işlemlerini kaydeden merkezi `processed_operations` tablosu tutulur. İstek hash'i doğrulanır; aynı istek tekrar gelirse işlem yinelenmez, önceki başarılı yanıt döndürülür.
- *Not:* Merkezi sunucu Inbox defteri (`processed_operations`) idempotency prensibi için mimari desendir; tablonun şeması ve sütun detayları Aşama 6B-2'de değerlendirilecek bir operasyonel taslaktır.
- **Durum:** `[CONFIRMED]`

---

### Karar 5: Sunucu Tarafı Atomik Inbox Transaction'ı (`FND-SYNC-05`)
- **Bağlam:** Sunucuda iş mantığı kaydı ile idempotency kaydının bütünlüğü.
- **Karar:**
  - *Pilot Mimari:* Merkezi Windows Local Master Hub üzerinde `sales` yazımı ile idempotency/inbox kontrolü **Windows Service API ve merkezi SQLite transaction'ı** içinde tek bir atomik blokta işletilir. Biri başarısız olursa tüm işlem geri alınır (rollback).
  - *Tarihsel / Gelecek SaaS Alternatifi:* Supabase Edge Function / PostgreSQL katmanında tek bir PostgreSQL transaction'ı içinde atomik işletim tasarımı Gelecek SaaS için opsiyonel mimari olarak muhafaza edilmektedir.
- **Durum:** `[CONFIRMED]`

---

### Karar 6: Kaza Kurtarma (Crash Recovery) ve Atomik Worker Kiralama (`FND-SYNC-03`)
- **Bağlam:** Eşzamanlı worker'ların aynı işlemi kapması ve çökme anında `SYNCING` durumunda asılı kalma riski.
- **Karar:**
  - `sync_operations` kuyruğu için worker kiralama ve kaza kurtarma mantığı tasarlanmıştır: Kiralama atomik tek bir sorguyla yapılır; geciken eski worker'ın bayat yanıtı elenir ve uygulama açılışında süresi dolmuş kilitler sıfırlanır.
  - *Mimari Açıklama:* Worker lease sütunlarının (`locked_by_worker_id`, `lease_expires_at`) fiziksel şemaya eklenmesi veya alternatif kuyruk yönetim teknikleri Aşama 6B-2 ve Faz 1 spike sürecinde değerlendirilecek bir tasarım önerisidir; şemaya kesinleşmiş kullanıcı kararı olarak dayatılmamıştır.
- **Durum:** `[CONFIRMED]`

---

### Karar 7: Hata Durumlarında `FAILED` ve `RETRY_EXHAUSTED` (DLQ) Ayrımı (`FND-SYNC-06`)
- **Bağlam:** Hataların teşhisi ve kuyruk akışı.
- **Karar:**
  - Kalıcı şema/doğrulama hataları doğrudan `FAILED` durumuna çekilir.
  - Geçici hatalar (ağ, 5xx) Full Jitter Exponential Backoff ile 10 kez denenir; 10 deneme bittiğinde `RETRY_EXHAUSTED` (DLQ) durumuna geçer ve operatör incelemesine sunulur. Bağımsız işlemler bloke edilmez.
- **Durum:** `[CONFIRMED]`

---

### Karar 8: Satış ve Stok Hareketlerinde Asla Silmeme ve Denetim Kaydı
- **Bağlam:** Çevrimdışı çoklu cihaz çakışmalarında gerçekleşmiş işlemlerin akıbeti (`BR-SYNC-06`).
- **Karar:** İki cihaz aynı son stoğu satsa dahi satış kayıtları kesinlikle silinemez. Stok negatif bakiyeye düşer; uyuşmazlık `audit_logs` tablosuna yazılır ve dashboard'da gösterilir.
- **Durum:** `[CONFIRMED]`

---

### Karar 9: Yedek Geri Yüklemede İşlem Değişmezliği ve Sayaç İlerletme (`FND-SYNC-01`)
- **Bağlam:** Eski bir yedek yüklendiğinde uç cihazdaki henüz buluta gitmemiş yerel satışların sıra numaraları ve kimlikleri.
- **Değerlendirilen Alternatifler:**
  1. *Bekleyen İşlemleri Yeniden Numaralandırmak:* Orijinal sıra numaralarını ve kimliklerini değiştirmek. Bu durum sunucuda daha önce işlenmiş işlemlerle çakışma, mükerrer kayıt ve sequence gap ihlallerine yol açar.
  2. *İşlem Değişmezliği ve Yalnızca Sayaç İlerletme (Seçilen Yaklaşım):*  
     - Bekleyen işlemlerin `id`, `idempotency_key`, `client_sequence_number` ve `payload` değerleri **KESİNLİKLE DEĞİŞTİRİLMEZ** (immutable).
     - Yeni yüklenen veritabanındaki sayaç tablosu (`device_sync_sequence`), yalnızca bundan sonra üretilecek yeni işlemleri üretmek üzere ileri sarılır:
       $$S_{\text{next\_generator}} = \max(S_{\text{backup\_max}}, \; \max(S_{\text{staged\_pending\_seq}})) + 1$$
     - Sunucu Inbox defteri ile mutabakat yapılarak mükerrer gönderim elenir.
- **Tercih Gerekçesi:**
  - Matematiksel kesinlik; double-restore senaryolarında dahi sıfır çakışma ve sıfır veri kaybı.
- **Durum:** `[CONFIRMED]`

---

### Karar 10: Çevrimdışı Cihaz İptali Tehdit Modeli ve Gerçeklik Sınırları (`FND-SYNC-04`)
- **Bağlam:** Çalınan veya yetkisi kaldırılan bir cihazın çevrimdışıyken durumu.
- **Karar:**
  - Çevrimdışı bir cihazın uzaktan anlık kilitlenemeyeceği fiziksel bir gerçektir.
  - Cihaz en fazla 7 günlük yerel oturum süresi (`expires_at`) boyunca çalışabilir; süre dolduğunda kendini yerel olarak kilitler (`BR-SEC-06`).
  - Ağ bağlantısı kurduğu ilk anda `HTTP 403 Forbidden` cevabı alır; cihazın Master Hub API erişim yetkisi derhal düşürülür; ancak yerel veritabanı silinmez, Outbox kayıtları ve bekleyen satışlar korunur (`BR-SEC-04`).
  - *Açık Konular (Aşama 6B-2):* İptal edilen cihazın istemci kullanıcı arayüzü davranışı (satış ekranının durumu veya kısıtlanması) ile iptal edilen cihazdaki henüz senkronize edilmemiş yerel satışların güvenli kurtarılması ve uzlaştırılması akışı kesinleşmiş kararlar olmayıp, Aşama 6B-2 değerlendirmesine bırakılmıştır.
- **Durum:** `[CONFIRMED]`

---

## 3. Henüz Kesinleşmemiş / Teknik Tasarımda Doğrulanacak Konular (`[PROPOSED]`)

1. **`sync_operations` Tablosu Temizleme ve Arşivleme Süresi:**
   - Tamamlanan (`COMPLETED`) Outbox kayıtlarının yerel SQLite boyutunu şişirmemesi için 30 gün sonra yerel temizlik (purge) yapılması önerilmektedir (`[PROPOSED]`).
2. **Sunucu Inbox Defteri (`processed_operations`) Partition Politikası:**
   - Yüksek hacimli satışlarda Supabase/PostgreSQL tarafında tablonun aylık `PARTITION BY RANGE (processed_at)` ile bölümlenmesi Gelecek SaaS için opsiyonel bir PostgreSQL optimizasyonu olarak önerilmektedir (`[PROPOSED]`). Pilot merkezi SQLite mimarisinde yerel dosya tabanlı depolama kullanıldığından PostgreSQL partition yapısı geçerli değildir; merkezi SQLite için temizlik ve indeksleme stratejisi Aşama 6B-2'de değerlendirilecektir.
3. **Mobil Arka Plan Senkronizasyon Periyodu:**
   - Mobil cihazlarda arka plan periyodik sync aralığının 15 dakika olarak ayarlanması önerilmektedir (`[PROPOSED]`).

---

## 4. Çelişki ve Tutarlılık İncelemesi

- **`BUSINESS_RULES_SPEC.md` v1.2 ile Tutarlılık:** Fiyat çakışması (`BR-SYNC-05`), çevrimdışı satışın silinemezliği (`BR-SYNC-06`), eksi stok serbestliği (`BR-STK-02`), yedek öncesi güvenlik snapshot'ı (`BR-BAK-05`) ve bekleyen kuyruk uzlaştırması (`BR-BAK-06`) şartnameyle %100 örtüşmektedir.
- **`DATA_MODEL.md` v1.1 ile Tutarlılık:** `sync_operations` tablosundaki `client_sequence_number`, `status`, `idempotency_key` alanları ve kısıtları protokolde operasyonel taslak olarak uygulanmıştır.
- **Sonuç:** Hiçbir çelişki bulunmamaktadır.
