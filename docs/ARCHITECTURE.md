# ARCHITECTURE.md — Teknik Mimari Özeti

Bu belge, [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](../MARKET_POS_AI_STUDIO_BUILD_PLANI.md) (**v1.4**) belgesinde kesinleşen mimari kararların teknik özetidir.

---

## 1. Ürün ve Mimari Vizyon

Proje teknik adı `market-pos` olarak korunmakla birlikte, ürün bir **Market Management System (MMS)** olarak geliştirilmektedir. 
- Windows masaüstü bilgisayar ve mobil telefonlar (Android/iOS) **aynı temel yeteneklere** (ürün, satış, stok, dashboard, raporlama) tam yetkiyle sahiptir.
- Banka POS terminali / Ingenico cihaz entegrasyonu ilk sürümün kapsamı dışındadır. Tutar POS cihazına gerekirse elle girilir.
- Pilot aşamada **Windows Local Master Hub** mimarisi esastır. Gelecekteki çok şubeli SaaS fazında ise bulut tabanlı merkezi veritabanı (Supabase PostgreSQL / Auth) devreye alınacaktır.

---

## 2. Temel Teknoloji Kararları

| Alan | Seçilen Teknoloji | Not / Doğrulama Durumu |
|---|---|---|
| **Ürün Tipi** | Market Management System (MMS) | Pilot tek market; SaaS ve çok şubeli genişlemeye hazır mimari |
| **Uygulama Çerçevesi** | Flutter (Dart) | Windows masaüstü, Android ve iOS ortak istemci tabanı |
| **Uç / Yerel Depolama** | Drift + SQLite (WAL Modu) | Mobil cihazlarda `mms_client.db`, Windows masaüstünde `%LOCALAPPDATA%\MarketMMS\client_local.db` (`packages/mms_client_storage`) |
| **Merkezi Depolama (Pilot)** | Merkezi SQLite (WAL Modu) | Windows Service tarafından tekil yazıcı (Single-Writer) olarak yönetilen master defter (`%PROGRAMDATA%\MarketMMS\data\market_master.db`) |
| **Merkezi Sunucu API (Pilot)**| Dart Shelf HTTPS API | Windows Service olarak çalışan bağımsız arka plan servisi (`%PROGRAMDATA%\MarketMMS\bin\mms_backend.exe`, `test_spikes/spike_01_backend`) |
| **Gelecek Merkezi Depolama (SaaS)**| PostgreSQL / Supabase | Çok şubeli zincir ve bulut SaaS fazı için şema uyumluluğu ve RLS desteği korunur |
| **Kimlik ve Eşleştirme (Pilot)**| Dinamik QR Kod & Token Eşleştirme | Pilot tek Owner hesabı; Windows ekranında gösterilen dinamik QR kod ile yerel cihaz eşleştirme |
| **Gelecek Kimlik (SaaS)**| Supabase Auth | E-posta/şifre, rol, üyelik ve çoklu şube yönetimi |
| **Ağ ve Senkronizasyon** | Yerel Wi-Fi / LAN HTTPS API | İnternet bağlantısı olmasa dahi mağaza içi LAN üzerinden; Windows kapalıyken yerel offline Outbox |
| **Durum Yönetimi** | Riverpod | Test edilebilir, reaktif durum yönetimi |
| **Navigasyon** | go_router | Deklaratif yönlendirme, derin bağlantı uyumu |
| **Barkod Girişi** | PC'de USB HID; Mobilde Kamera | Otomatik ürün bulma ve sepet oluşturma |
| **Ürün Öneri API** | Open Food Facts API | Barkod okutulduğunda ürün bilgisi önerme (fiyat/stok kullanıcı tarafından manuel girilir) |
| **Yedekleme** | Windows Service + Google Drive | Merkezi ve mobil ayrık SQLite canlı anlık görüntüleri (`VACUUM INTO`) + S5A-4 standardında AES-256-CBC, PKCS#7 padding, PBKDF2-HMAC-SHA256 (600.000 iterasyon) ve HMAC-SHA256 Encrypt-then-MAC şifreli bağımsız Google Drive yedeği |

---

## 3. Mimari Model: Paket Tabanlı Feature-First + Clean Architecture

Proje kaynak kodu, katı Clean Architecture sınırlarını koruyan paketli ve modüler bir mimariye sahiptir:

```text
market-pos/
├── packages/
│   └── mms_client_storage/    # Uç / Yerel Drift SQLite veritabanı, outbox işlem kuyruğu, şifreli yedekleme motoru (51 test)
├── test_spikes/
│   └── spike_01_backend/      # Dart Shelf HTTPS merkezi API, merkezi SQLite tekil yazıcı, dinamik QR ve token yönetimi (139 test)
├── lib/
│   ├── app/                   # Router (go_router), tema, bootstrap
│   ├── core/                  # Kuruş tam sayı para birimi, rasyonel oran, hata tipleri, network
│   ├── features/              # auth, tenants, stores, products, inventory, sales, dashboard, sync, backup
│   │   └── <feature>/
│   │       ├── domain/        # Entity, value object, repository sözleşmeleri (saf Dart)
│   │       ├── data/          # Repository implementasyonları, Drift DAO adaptörleri, Master Hub REST DTO'ları
│   │       └── presentation/  # Ekranlar, widget'lar, Riverpod provider'ları
│   └── infrastructure/        # Master Hub API istemcisi (REST), yerel donanım köprüleri (USB HID, kamera)
└── test/                      # İstemci unit ve widget testleri (31 test)
```

### Bağımlılık Yönü
$$\text{presentation} \longrightarrow \text{domain} \longleftarrow \text{data}$$

- **`domain` katmanı:** Saf Dart ile yazılır. Hiçbir dış kütüphaneye (Flutter UI, Drift, Shelf, Supabase) doğrudan bağımlı olamaz.
- **`data` katmanı:** Domain katmanındaki sözleşmeleri (interface) uygular. Yerel veri için `packages/mms_client_storage`'ı, uzaktan veri senkronizasyonu için Windows Master Hub API istemcisini kullanır.
- **`presentation` katmanı:** Yalnızca domain katmanındaki sözleşmeleri ve use case'leri tüketir. Doğrudan veritabanı tablolarına veya HTTP katmanına erişemez.

---

## 4. Çoklu Market (Multi-Tenant) SaaS Tasarımı

- **Tenant:** Müşteri işletme veya market grubu.
- **Store:** Fiziksel şube/mağaza.
- **User & Membership:** Kullanıcı ve yetki ilişkisi (Pilot aşamasında tek Owner hesabı).
- **Device:** İşlem yapan fiziksel cihaz (Windows PC, telefon veya tablet).
- **Veri İzolasyonu:** Bütün tablolarda `tenant_id` ve `store_id` alanları zorunludur. Pilot aşamasında veri izolasyonu Windows Master Hub API iş kuralları tarafından sağlanır. Gelecekteki SaaS fazında Supabase RLS ile çift katmanlı korunacaktır.

---

## 5. Offline-First, Çoklu Cihaz ve Senkronizasyon

- **Windows Master Hub:** Windows bilgisayar ana sunucudur. Arka planda bağımsız bir Windows Service (Dart Shelf HTTPS API) çalışır.
- **Ayrık Veritabanı Modeli (Dual SQLite Architecture):**
  - **Merkezi Sunucu Veritabanı:** `%PROGRAMDATA%\MarketMMS\data\market_master.db` dosyasında tutulur ve yalnızca Windows Service (tekil yazıcı) tarafından doğrudan erişilir.
  - **Uç / Yerel Veritabanı:** Her istemci kendi yerel veritabanına sahiptir (Windows Flutter masaüstünde `%LOCALAPPDATA%\MarketMMS\client_local.db`, Android ve iOS telefonlarda yerel `mms_client.db`).
  - **Masaüstü İzolasyonu:** Windows Flutter masaüstü kullanıcı arayüzü, sunucu veritabanı dosyasına doğrudan ASLA dokunmaz. Yerel loopback API (`http://127.0.0.1:<port>`) üzerinden haberleşir.
  - **Windows Servisi Kapalıyken Masaüstü:** Windows arka plan servisi kapalı olsa dahi Windows Flutter arayüzü kendi yerel Drift SQLite veritabanı üzerinde satış yapmaya devam edebilir; servis açıldığında loopback üzerinden outbox aktarımı yapılır.
- **Single-Writer ve Eşzamanlılık Yönetimi:**
  - Merkezi SQLite veritabanına tüm yazma işlemleri servis içindeki tekil yazıcı kuyruğu (Single-Writer Write Queue) üzerinden seri olarak yürütülür.
  - Kilitlenme riskine karşı WAL modu (`PRAGMA journal_mode = WAL;`) ve meşguliyet zaman aşımı (`PRAGMA busy_timeout = 5000;`) işletilir.
- **Yerel Ağda (LAN) Kesintisiz Çalışma:** Mobil cihazlar mağaza içi Wi-Fi / LAN üzerinden HTTPS ile Windows Master Hub API'sine bağlanır. Mağazanın interneti kesilse dahi yerel ağ operasyonu kesintisiz devam eder.
- **Outbox ve Senkronizasyon Kuralları:**
  - **Kalıcı Kimlik ve Sıra:** Uç cihazlarda persistent `device_id` ve cihaz bazında monotonik artan `client_seq` (`client_sequence_number`) zorunludur.
  - **Deterministik FIFO:** Senkronizasyon işlemleri kuyruktan kesinlikle FIFO sırasıyla aktarılır.
  - **Sunucu Onayı (ACK):** Merkezi sunucudan başarılı HTTP yanıtı (ACK) alınmadan yerel kuyruk kaydı asla `SYNCED` olarak mühürlenemez.
  - **Idempotency (Mükerrerlik Koruması):** Her operasyon cihazda üretilen benzersiz bir `idempotency_key` (ve `operation_id`) taşır. Ağ kesintisi veya tekrar iletimlerde çifte satış veya mükerrer stok düşümü engellenir.
  - **Stok Çakışması ve Geçmişin Korunması:** Eksi stok politikası `allow` olup, gerçekleşmiş fiziksel satışlar çakışma durumunda asla silinmez. Stok uyuşmazlığı durumunda `audit_logs` kaydı oluşturulur ve market sahibine bildirim sunulur.
  - **Açık Tasarım Kararları (`OPEN DECISION`):** Kuyruk kiralama (lease) mekanizması, kaza sonrası kilit sıfırlama süreleri ve hata durumunda üstel geri çekilme (backoff) parametreleri henüz onaylanmamış olup `OPEN DECISION` statüsündedir.

---

## 6. Dashboard ve Finansal Doğruluk

- Ciro, brüt kâr ve net kâr kavramları birbirinden kesin olarak ayrılır.
- Maliyet verisi girilmemiş ürünlerde gerçek kâr hesabı yapılmaz; işletme giderleri (kira, fatura, personel vb.) sisteme girilmeden net kâr iddiasında bulunulamaz.
- **Kuruş Tamsayı Standardı (`CONFIRMED`):** Para değerleri ve hesaplamaları kesinlikle floating point (`double`) ile yapılamaz; kuruş bazlı tamsayılar (`int` / `BIGINT`) veya özel Value Object (`Money`) ile saklanır ve hesaplanır.
- **Snapshot Fiyat ve İsim (`CONFIRMED`):** Satış anındaki birim fiyat ve ürün adı satış satırına kopyalanır; gelecekteki fiyat değişiklikleri geçmiş satışları etkileyemez.
- **Alt Kuruş Yuvarlama Politikası (`OPEN DECISION`):** Kesirli miktar, gramaj veya birim maliyet çarpmalarında ortaya çıkabilecek alt kuruş kesirlerinin yuvarlama yöntemi (Half-Up vb.) proje sahibi tarafından henüz karara bağlanmamış olup `OPEN DECISION` statüsündedir.

---

## 7. Teknik Spike Durumu ve Pilot Öncesi Açık Koşullar

### Tamamlanan Spike'lar:
- **SPIKE-01 (Windows Service & SQLite Single-Writer):** **TAMAMLANDI ve DOĞRULANDI**
  - Dart Shelf HTTPS backend ve SQLite WAL tekil yazıcı mimarisi seçildi.
  - 139 birim ve entegrasyon testiyle doğrulandı (`test_spikes/spike_01_backend`).
  - S5A serisi (S5A-1'den S5A-5'e kadar) tamamlandı.
  - **S5A-5 Değerlendirmesi: KOŞULLU PİLOT HAZIRLIĞI (READY FOR PILOT WITH CONDITIONS)**.

### Açık Teknik Koşullar (Pilot Öncesi Karşılanması Gereken Zorunlu Maddeler):
1. **B-2 (Mobil Sertifika Sabitleme):** Mobil istemcilerde (Android/iOS) yerel HTTPS iletişimi için Root CA sertifika sabitleme (Certificate Pinning) entegrasyonu.
2. **B-3 (Güvenli Sır Depolama):** Windows DPAPI, Android Keystore ve iOS Keychain üzerinden güvenli token ve master key depolama.
3. **Gerçek Windows SCM Testleri:** Windows Service Control Manager üzerinde gerçek servis kurulumu, başlatma, durdurma ve otomatik yeniden başlatma (failure recovery) testleri.
4. **Non-Admin Windows ACL:** Windows üzerinde standart kullanıcı yetkileriyle `%PROGRAMDATA%\MarketMMS` dizin erişim ve yetki kısıtlama testleri.
5. **Fiziksel Mobil Cihaz Testleri:** Gerçek Android ve iOS cihazlar ile mağaza içi Wi-Fi mDNS / Dinamik QR eşleştirme ve ağ kopma/bağlanma testleri.
6. **Eşleştirme Rotası Kısıtlaması:** Dinamik QR kod ile cihaz eşleştirme uç noktalarına özel token kısıtlaması (route-specific pairing token restriction).

### Planlanan Spike'lar:
- **SPIKE-02 (LAN Discovery & QR Pairing):** mDNS yayını ve router AP isolation engeli durumunda Dinamik QR kod doğrudan IP eşleştirmesinin saha testi.
- **SPIKE-03 (Yerel TLS & iOS İzni):** Yerel ağda şifreli HTTPS iletişimi ve iOS 14+ `NSLocalNetworkUsageDescription` izin modelinin doğrulanması.
