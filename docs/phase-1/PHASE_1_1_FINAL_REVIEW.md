# MARKET MANAGEMENT SYSTEM (MMS)
## FAZ 1.1 — Nihai Mimari ve Güvenlik İnceleme Raporu (Final Architecture Review)

**Tarih:** 6 Kasım 2026  
**İnceleme Kapsamı:** Faz 1.1 — Windows Client Foundation İmplementasyonu  
**Durum:** TAMAMLANDI (Salt İnceleme — Kod Değişikliği Yapılmadı)  
**Doküman Sürümü:** 1.0  

---

## 1. Yönetici Özeti

Bu inceleme, Faz 1.1 kapsamında oluşturulan gerçek Flutter Windows masaüstü istemcisi, `packages/mms_client_storage` entegrasyonu, `lib/core/network/api_client.dart` ağ katmanı ve `test_spikes/spike_01_backend` merkezi sunucusu arasındaki mimari, güvenlik ve veri bütünlüğü sınırlarını doğrulamak amacıyla icra edilmiştir.

> [!IMPORTANT]
> **Kural Uyumu:** Bu görev salt teknik inceleme ve durum tespiti olarak yürütülmüştür. Hiçbir kaynak kodunda, konfigürasyonda veya veritabanı şemasında değişiklik yapılmamıştır.

---

## 2. Detaylı Mimari ve Güvenlik Değerlendirmesi

### 2.1. Paket Mimarisi ve Sınırlar

- **Hedef Dört Paket Durumu:**
  1. `mms_client_storage`: **MEVCUT.** Bağımsız Dart paketi olarak `packages/mms_client_storage` altında yaşamaktadır. İstemci SQLite veritabanı (`client_local.db`), Outbox kuyruğu, kesirli miktar/birim dönüşümü ve şifreli yedekleme motorunu barındırır (51 test yeşil).
  2. `mms_domain`: **FİZİKSEL PAKET OLARAK MEVCUT DEĞİL.** Domain modelleri (`CartItemInput`, `SaleTransactionResult`, `SyncResponse`) şu anda `mms_client_storage/lib/src/models/` altında, arayüz canlılık modeli ise `lib/features/diagnostics/domain/system_status.dart` içinde saf Dart sınıfları olarak konumlanmıştır.
  3. `mms_contracts`: **FİZİKSEL PAKET OLARAK MEVCUT DEĞİL.** API DTO'ları ve JSON kontratları `test_spikes/spike_01_backend` ve `mms_client_storage` modelleri arasında paylaşılmaktadır.
  4. `mms_server`: **FİZİKSEL PAKET OLARAK MEVCUT DEĞİL (Spike altında).** Merkezi Shelf HTTPS sunucusu, WinSW servis wrapper'ı ve `market_master.db` tekil yazıcısı `test_spikes/spike_01_backend` dizinindedir.

- **Backend Neden Hâlâ `test_spikes` Altında?**
  Faz 0 kapsamında SPIKE-01 olarak başlatılan teknik araştırma projesi, S1..S5A aşamaları boyunca sürekli olgunlaştırılarak kurumsal nitelikte bir Windows Service backend'ine dönüştürülmüştür (139 test yeşil). Faz 1.1 kısıtları ("Mevcut kodları silme, taşıma veya yeniden yazma") gereği, dosya yolu taşınmamış ve mevcut çalışan test orkestrasyonu riske atılmamıştır.

- **Faz 1.2 İçin Yeterlilik ve Paket İhtiyacı:**
  Mevcut yapı **Faz 1.2 (Kasa Satış Ekranı & Sepet Yönetimi) için tamamen yeterlidir.** Faz 1.2 doğrudan `mms_client_storage` paketinin `ClientStorageRepository` API'sini (`createLocalSale`, `findProductByBarcode` vb.) tüketecektir. Şu aşamada erken bir `mms_domain` veya `mms_contracts` paket ayrımı yapmak gereksiz soyutlama ve paket enflasyonu yaratacaktır.

---

### 2.2. API Güvenliği (`lib/core/network/api_client.dart`)

- **TLS Sertifika Doğrulaması:**
  `MmsApiClient` varsayılan olarak standart `http.Client()` kullanmaktadır. S3 aşamasında geliştirilen `tls_client_factory.dart` (özel MMS Root CA sertifika sabitlemesi - Certificate Pinning) henüz `MmsApiClient` içine bağlanmamıştır.
- **S3 Root CA Güven Modeliyle Uyum:**
  Şu anda tam uyumlu değildir; işletim sisteminin standart güven deposuna veya yerel HTTP loopback bağlantısına dayanmaktadır.
- **HTTPS Zorunluluğu:**
  HTTPS zorunlu değildir. `AppConstants.defaultBackendBaseUrl` değeri `http://127.0.0.1:8080` (HTTP loopback) olarak ayarlanmıştır. Windows yerel makinesinde çalışan Master Hub için mimari olarak HTTP loopback kabul edilebilir olsa da, uzak LAN üzerinden bağlanacak istemciler için HTTPS zorunluluğu istemci tarafında kodlanmamıştır.
- **Device Token Saklama ve Sızıntı Riski:**
  - Token, istemci başlatılırken in-memory (RAM) argümanı olarak geçirilmektedir. Henüz Windows DPAPI veya Credential Manager üzerinde kalıcı şifreli depolamaya alınmamıştır.
  - `lib/core/network/api_client.dart:161` satırında:
    ```dart
    throw AuthenticationException(
      'Yetkilendirme hatası (Kod: ${response.statusCode}): ${response.body}',
      statusCode: response.statusCode,
    );
    ```
    Eğer sunucu 401/403 yanıt gövdesinde istek başlıklarını veya token ayrıntılarını yankılarsa (echo), bu durum istisna mesajına ve istemci loglarına sızabilir.
- **HTTP 503 ve Zaman Aşımı (Timeout) Yönetimi:**
  Tamamen doğrudur. GET `/health` isteğinde 503 yanıtı `CentralHealthResponse.draining(...)` olarak yakalanmakta, UI `DRAINING` moduna geçmektedir. Normal API çağrılarında ise `ServiceDrainingException` fırlatılmaktadır. `TimeoutException` güvenle `NetworkException` ve `unreachable` durumuna dönüştürülmektedir.
- **Offline Davranışı:**
  Sunucu kapalıyken `SocketException` yakalanarak `BackendConnectionState.offline` üretilmekte, arayüz çökmemekte ve yerel veritabanı kesintisiz çalışmayı sürdürmektedir.

---

### 2.3. Yerel Veritabanı (`lib/core/storage/local_database_service.dart`)

- **Kullanılan Veritabanı:** Gerçek `client_local.db` kullanılmaktadır.
- **Veritabanı Yolu:** Windows ortamında `%LOCALAPPDATA%\MarketMMS\client_local.db` yoluna doğru şekilde çözümlenmektedir.
- **Çoklu Bağlantı (Connection Leak) Riski:**
  `LocalDatabaseService.initialize()` fonksiyonu bir singleton deseni ile korunmamaktadır. Normal akışta `main.dart` tek bir örnek oluşturup Riverpod üzerinden enjekte etse de, başka bir kod parçası `initialize()` metodunu tekrar çağırırsa aynı SQLite dosyasına ikinci bir `ClientDatabase` bağlantısı açılabilir. SQLite WAL modu bu durumu tolere etse de `busy_timeout` kilitlenme riskini artırır.
- **Merkezi DB'ye Doğrudan Erişim:**
  **SIFIR ERİŞİM.** Windows Flutter UI içerisinde `market_master.db` dosyasına veya `test_spikes/spike_01_backend` DB modellerine hiçbir referans, import veya SQL bağlantısı bulunmamaktadır.
- **Outbox ve Satış Transaction Hazırlığı:**
  `ClientStorageRepository` üzerinden `createLocalSale` (kesirli miktar, birim dönüşümü, outbox payload SHA-256 hash, stok düşümü) Faz 1.2'nin kullanımına eksiksiz hazır durumdadır.

---

### 2.4. Yedekleme Kriptografisi (`packages/mms_client_storage/.../backup_crypto.dart`)

- **Kullanılan Algoritma:** AES-256-CBC (PKCS#7 padding).
- **Kimlik Doğrulama / Bütünlük:** **Encrypt-then-MAC (HMAC-SHA256).** Şifreli paket, manifest ve başlıkların tümü HMAC ile mühürlenmektedir.
- **Anahtar Türetme (KDF):** PBKDF2-HMAC-SHA256.
- **İterasyon Sayısı:** **600.000 iterasyon** (`defaultPbkdf2Iterations = 600000`).
- **Timing Attack Koruması:** `constantTimeEquals` fonksiyonu ile sabit zamanlı HMAC karşılaştırması yapılmaktadır.
- **S5A-4 Uyumu:** S5A-4 güvenlik şartnamesine ve felaket kurtarma standartlarına **%100 uygundur.**

---

### 2.5. Tanılama (Diagnostics) Veri Kaynakları

Diagnostics ekranında (`diagnostics_view.dart`) gösterilen tüm metriklerin veri kaynağı net olarak ayrıştırılmıştır:

| Metrik | Kaynak Türü | Açıklama |
| :--- | :--- | :--- |
| **Hub Canlılık Durumu** | **Gerçek API** | Shelf sunucusuna `GET /health` çağrısı sonucu |
| **Hub Yanıt Gecikmesi (Latency)** | **Gerçek Ölçüm** | HTTP isteği öncesi/sonrası çalışan `Stopwatch` süresi (ms) |
| **Merkezi SQLite Sürümü** | **Gerçek API** | `/health` endpoint'inin döndürdüğü JSON içindeki `sqlite_version` |
| **Hub URL** | **Konfigürasyon** | `apiClient.baseUrl` (`http://127.0.0.1:8080`) |
| **Cihaz Kimliği (Device ID)** | **Varsayılan Değer** | `AppConstants.defaultDeviceId` (`POS-WIN-01` — henüz dinamik eşleşmedi) |
| **Yerel DB Durumu** | **Gerçek SQLite** | Drift veritabanının açık ve erişilebilir olma durumu |
| **Yerel DB Yolu** | **Gerçek Dosya Sistemi**| `%LOCALAPPDATA%\MarketMMS\client_local.db` |
| **Bekleyen Outbox Sayısı** | **Gerçek SQLite Sorgusu**| `SELECT COUNT(*) FROM outbox_operations WHERE status = 'PENDING'` |
| **Yerel Satış Sayısı** | **Gerçek SQLite Sorgusu**| `SELECT COUNT(*) FROM local_sales` |
| **Önbellek Ürün Sayısı** | **Gerçek SQLite Sorgusu**| `SELECT COUNT(*) FROM local_products` |
| **Alt Bar Kısayol Tuşları** | **Statik Görsel** | F1, F2, F9, F10 tuş etiketleri (henüz donanım klavye dinleyicisine bağlı değil) |

---

## 3. Bulgular ve Risk Sınıflandırması

### Bulgu 1: Yetkilendirme İstisnasında Ham Yanıt Gövdesi (Potential Token Leak)
- **Sınıflandırma:** `HIGH`
- **Dosya / Satır:** `lib/core/network/api_client.dart:161`
- **Mevcut Davranış:** Sunucu 401 veya 403 döndüğünde `AuthenticationException` mesajına `response.body` doğrudan eklenmektedir.
- **Risk:** Sunucu hata detayında istek başlıklarını veya hassas verileri yansıtırsa, loglama mekanizmalarında token veya gizli veriler açığa çıkabilir.
- **Önerilen Çözüm:** `response.body` metnini exception mesajına doğrudan yazmak yerine, hassas alanları filtreleyen veya yalnızca hata kodunu (`UNAUTHORIZED`, `TOKEN_EXPIRED`) içeren bir format kullanılmalıdır.
- **Faz 1.2'yi Engelliyor mu?** **HAYIR.** (Faz 1.2 yerel kasa satışıdır; yine de Faz 1.2 network entegrasyonundan önce düzeltilmelidir).

---

### Bulgu 2: S3 Root CA Sertifika Sabitlemesinin (Pinning) Bağlanmamış Olması
- **Sınıflandırma:** `HIGH`
- **Dosya / Satır:** `lib/core/network/api_client.dart:21-26`
- **Mevcut Davranış:** `MmsApiClient` varsayılan platform `http.Client()` kullanmaktadır. `test_spikes/spike_01_backend/lib/security/tls_client_factory.dart` içinde doğrulanmış özel Root CA güven bağlamı istemciye entegre edilmemiştir.
- **Risk:** Windows masaüstü istemcisi aynı makinede (localhost HTTP) çalışırken risk düşüktür; ancak yerel ağ (LAN) üzerinden HTTPS ile Hub'a bağlanıldığında self-signed MMS Root CA tanınmayabilir veya MitM saldırılarına açık kalabilir.
- **Önerilen Çözüm:** `MmsApiClient` sınıfına opsiyonel bir `SecurityContext` kabul eden fabrika metodu eklenmeli ve S3 Root CA sertifikası güvenli şekilde istemciye bağlanmalıdır.
- **Faz 1.2'yi Engelliyor mu?** **HAYIR.** (Faz 1.2 masaüstü loopback üzerinden test edilmektedir).

---

### Bulgu 3: İstemci Tarafında Device Token Kalıcı Depolamasının Bulunmaması
- **Sınıflandırma:** `HIGH`
- **Dosya / Satır:** `lib/core/network/api_client.dart:16`, `lib/features/diagnostics/application/system_status_notifier.dart:10`
- **Mevcut Davranış:** `deviceToken` yalnızca RAM'de tutulmaktadır. Şu anda `apiClientProvider` içinde token `null` olarak başlatılmaktadır.
- **Risk:** Cihaz eşleştirme (Pairing) yapıldıktan sonra uygulama kapatılıp açıldığında token kaybolacak ve her açılışta yeniden eşleştirme gerekecektir.
- **Önerilen Çözüm:** Windows üzerinde DPAPI tabanlı güvenli anahtar deposu (veya `flutter_secure_storage`) entegre edilerek eşleştirilen cihaz token'ı kalıcı olarak saklanmalıdır.
- **Faz 1.2'yi Engelliyor mu?** **HAYIR.** (Faz 1.2 yerel satış ve Outbox kuyruğu geliştirmesidir; senkronizasyon aşamasında zorunlu hale gelecektir).

---

### Bulgu 4: Merkezi Backend Kodlarının Hâlâ `test_spikes/` Klasöründe Bulunması
- **Sınıflandırma:** `MEDIUM`
- **Dosya / Satır:** `test_spikes/spike_01_backend/`
- **Mevcut Davranış:** Üretim seviyesinde çalışan Windows Service, WriteQueue ve Shelf API kodları `test_spikes` adı altında yaşamaktadır.
- **Risk:** Projeye yeni dahil olan geliştiriciler veya analiz araçları bu kodları geçici prototip zannedebilir; mimari netlik zayıflar.
- **Önerilen Çözüm:** Faz 1 tamamlandıktan sonra kontrollü bir Git taşıma operasyonuyla `test_spikes/spike_01_backend` dizini `packages/mms_server` veya `server/` olarak yeniden adlandırılmalı, test yolları güncellenmelidir.
- **Faz 1.2'yi Engelliyor mu?** **HAYIR.**

---

### Bulgu 5: Sabit Kodlanmış Hub URL ve Cihaz Kimliği (Hardcoded Defaults)
- **Sınıflandırma:** `MEDIUM`
- **Dosya / Satır:** `lib/core/constants/app_constants.dart:10-14`
- **Mevcut Davranış:** `defaultBackendBaseUrl = 'http://127.0.0.1:8080'` ve `defaultDeviceId = 'POS-WIN-01'` sabit kodlanmıştır.
- **Risk:** Farklı bir portta çalışan veya farklı bir IP'deki Hub'a bağlanmak için kaynak kod değişikliği gerekir; runtime konfigürasyonu yoktur.
- **Önerilen Çözüm:** Bir `app_settings.json` veya `SharedPreferences` tabanlı istemci ayar sağlayıcısı eklenerek IP/Port ve Kasa Numarasının UI/Ayar ekranından değiştirilebilmesi sağlanmalıdır.
- **Faz 1.2'yi Engelliyor mu?** **HAYIR.**

---

### Bulgu 6: `LocalDatabaseService` Singleton Koruması Eksikliği
- **Sınıflandırma:** `MEDIUM`
- **Dosya / Satır:** `lib/core/storage/local_database_service.dart:27`
- **Mevcut Davranış:** `initialize()` metodu statik factory olarak çalışmakta, önceden açılmış bir instance olup olmadığını denetlememektedir.
- **Risk:** Geliştiricinin yanlışlıkla farklı bir yerde tekrar `initialize()` çağırması halinde aynı dosya üzerinde birden fazla SQLite connection havuzu açılarak lock çekişmesine yol açabilir.
- **Önerilen Çözüm:** `_instance` değişkeni ile Singleton deseni uygulanmalı veya mevcut açık bağlantı varsa doğrudan o dönülmelidir.
- **Faz 1.2'yi Engelliyor mu?** **HAYIR.** (Riverpod `main.dart` üzerinden tek bir instance enjekte etmektedir).

---

### Bulgu 7: Alt Çubuk Klavye Kısayollarının (F1..F10) Statik Olması
- **Sınıflandırma:** `LOW`
- **Dosya / Satır:** `lib/features/shell/presentation/screens/main_shell_screen.dart:203`
- **Mevcut Davranış:** F1, F2, F9, F10 kısayol etiketleri yalnızca görsel bilgilendirme amaçlıdır; klavye olaylarını dinleyen bir `HardwareKeyboard` veya `FocusNode` yöneticisi henüz bağlanmamıştır.
- **Risk:** Kasiyer fiziksel klavyeden F10'a bastığında henüz hiçbir aksiyon gerçekleşmez.
- **Önerilen Çözüm:** Faz 1.2 kapsamında `FocusScope` ve global klavye dinleyicisi eklenerek kısayollar sepet ve ödeme aksiyonlarına bağlanmalıdır.
- **Faz 1.2'yi Engelliyor mu?** **HAYIR.** (Faz 1.2'nin doğrudan kendi geliştirme kapsamıdır).

---

### Bulgu 8: `mms_domain` ve `mms_contracts` Fiziksel Paket Ayrımı
- **Sınıflandırma:** `INFO`
- **Dosya / Satır:** Proje geneli
- **Mevcut Davranış:** Domain kuralları ve DTO'lar `mms_client_storage` içinde saf Dart ile izole edilmiştir.
- **Değerlendirme:** Faz 1.1 aşamasında bu ayrımın fiziksel olarak yapılmaması **doğru bir karardır**. Erken optimizasyon ve gereksiz paket karmaşasını önlemiştir. Mobil istemciler ve SaaS aşamasına geçilirken bu paketlerin ayrılması değerlendirilmelidir.
- **Faz 1.2'yi Engelliyor mu?** **HAYIR.**

---

## 4. Faz 1.2 İçin Hazırlık ve Geçiş Önerisi

| Kriter | Durum | Açıklama |
| :--- | :---: | :--- |
| **Windows Flutter Temeli** | **HAZIR** | 1280x720 masaüstü pencere, Cashier Header ve NavigationRail çalışıyor. |
| **Yerel Veritabanı (client_local.db)** | **HAZIR** | Drift SQLite WAL modunda, tablolar ve indeksler oluşturuldu. |
| **Satış & Stok Motoru** | **HAZIR** | `CartItemInput`, kesirli miktar (`scale=1000`), birim dönüşümü ve Outbox transaction hazır. |
| **Test Güvenliği** | **HAZIR** | 203 otomatik test yeşil (%100 başarı). Sıfır regresyon. |
| **Doğrudan Master DB Erişimi** | **ENGELLENDİ** | Windows UI yalnızca yerel SQLite ve Shelf API kullanmaktadır. |

**Öneri:**  
Faz 1.1 mimari ve altyapı açısından **KABUL EDİLEBİLİR** durumdadır. Tespit edilen bulgular Faz 1.2'nin geliştirilmesini engellememektedir. Kullanıcı onayını müteakip doğrudan **Faz 1.2: Kasa Satış Ekranı & Sepet Yönetimi** aşamasına geçilebilir.

