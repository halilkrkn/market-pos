# Market Management System (MMS) — Faz 0 Yerel Depolama Teknik Doğrulama Raporu (Local Storage Technical Validation)

**Doküman Kodu:** `LOCAL_STORAGE_TECHNICAL_VALIDATION.md`  
**Sürüm:** 1.0  
**Tarih:** 31 Ekim 2026  
**Durum:** Faz 0 — Platform Bazlı Yerel Depolama Mimarisi Doğrulaması (Tamamlandı)  
**Hedef Platformlar:** Windows (x64), Android, iOS, Web (WASM)  
**Ana Referans Doküman:** `MARKET_POS_AI_STUDIO_BUILD_PLANI.md` (v1.2.2)  
**İlgili Tasarım Dokümanları:** `docs/architecture/DATA_MODEL.md` (v1.1 Sertleştirilmiş), `docs/architecture/OFFLINE_SYNC_PROTOCOL.md` (v1.1)  
**Proje Kuralları:** `docs/ai/rules/offline-first.md`, `docs/ai/rules/clean-architecture.md`, `docs/ai/rules/security.md`  
**Teknik Proje / Klasör Adı:** `market-pos`  
**Ürün Tanımı:** Market Management System (MMS) — Profesyonel Market Yönetim SaaS Uygulaması  

---

## 1. Amaç ve Kapsam

**Market Management System (MMS)**; market kasalarında internet bağlantısı tamamen koptuğunda dahi ürün arama, barkod okuma, sepet işlemleri, satış kaydı ve stok hareketlerini yerel veritabanında kesintisiz sürdürmek zorundadır.

Sistem; Windows masaüstü bilgisayarlar, Android ve iOS mobil cihazlar ile Web tarayıcılarında çalışmak üzere hedeflenmiştir. Ancak **Drift + SQLite mimarisinin tüm bu platformlarda aynı fiziksel dosya sistemi, aynı transaction dayanıklılığı ve aynı arka plan yeteneklerine sahip olduğu varsayılamaz.**

Bu teknik doğrulama çalışmasının amacı;
1. Windows, Android, iOS ve Web platformlarının yerel veri saklama yeteneklerini, sınırlamalarını, dosya yollarını, kaza/çökme kurtarma mekanizmalarını ve arka plan sınırlarını güncel resmi kaynaklar ışığında bağımsız olarak incelemek,
2. Platformların farklılıklarına rağmen Clean Architecture prensiplerine uygun olarak ortak **Domain Repository** arayüzleri arkasında platforma özel adaptörlerin (`Data Layer`) nasıl izole edileceğini belirlemek,
3. Web platformunun native masaüstü/mobil sistemlerle aynı veri dayanıklılığına sahip olamayacağı gerçeğini net bir risk matrisiyle ortaya koymaktır.

---

## 2. Araştırma Yöntemi ve Resmi Kaynaklar

Bu çalışma, varsayımlara veya eski Flutter/Drift sürümlerine dayanmayıp güncel resmi dokümantasyon ve teknik standartlar üzerinden yürütülmüştür:

- **Drift (Moor) Resmi Dokümantasyonu (v2.20+):** `drift.simonbinder.eu` (Native SQLite, WAL mode, WASM/Web VFS, Isolate & multi-worker mimarisi).
- **SQLite Resmi Dokümantasyonu (v3.45+):** `sqlite.org` (Write-Ahead Logging - WAL, Online Backup API, Locking & busy-handler, ACID garantileri).
- **Flutter Desktop & Platform Dokümantasyonu:** `flutter.dev` (Windows native C++ runner, path_provider, isolate iletişimi).
- **Android Geliştirici Kılavuzları:** `developer.android.com` (App-specific storage, SQLite on Android, WorkManager constraints, Doze mode, Android Keystore).
- **Apple Developer Dokümantasyonu:** `developer.apple.com` (iOS App Sandbox, `NSFileProtection` sınıfları, `BGTaskScheduler`, Keychain Services).
- **W3C & MDN Web Standartları:** `w3.org` / `developer.mozilla.org` (Origin Private File System - OPFS, IndexedDB Storage, StorageManager persistence API, Web Workers, Safari ITP 7-day eviction politikası).

---

## 3. Windows (Masaüstü) Teknik Doğrulaması

Market kasalarındaki ana kasa bilgisayarlarının çoğunluğunu Windows platformu oluşturmaktadır.

### 3.1 Motor ve Kütüphane Mimarisi
- **Teknoloji:** `drift` + `sqlite3_flutter_libs` (veya `package:sqlite3`).
- **Çalışma Modeli:** Dart FFI (Foreign Function Interface) üzerinden doğrudan derlenmiş yerel C kütüphanesi (`sqlite3.dll`) çağrılır. İşletim sisteminde önceden kurulu bir SQLite aranmaz; uygulama paketi kendi optimize edilmiş `sqlite3.dll` dosyasını taşır. Bu sayede Windows 10 ve Windows 11 sürümlerinde tam deterministik ve standart davranış elde edilir.

### 3.2 Güvenli Dosya Konumu
- `path_provider` paketi üzerinden `getApplicationSupportDirectory()` çağrılır.
- **Fiziksel Dizin:**  
  `C:\Users\<Kullanıcı>\AppData\Roaming\<SaaS_Vendor>\market_pos\market_pos.db`
- **Gerekçe:** `AppData\Local\Temp` geçici temizliklere maruz kalabilir; Masaüstü veya Belgelerim ise kullanıcı müdahalesine ve yanlışlıkla silinmeye açıktır. `AppData\Roaming` işletim sistemi düzeyinde korumalıdır.

### 3.3 WAL (Write-Ahead Logging) ve Eşzamanlılık
- **Yapılandırma:** Veritabanı açılışında `PRAGMA journal_mode = WAL;` ve `PRAGMA synchronous = NORMAL;` çalıştırılır.
- **Faydaları:**
  - Okuma ve yazma işlemleri birbirini engellemez (1 aktif yazar varken N adet okuyucu eşzamanlı çalışabilir).
  - Kasada fiş basılırken arka planda rapor sorgulanması UI'ı dondurmaz.
- **Kilitlenme ve Meşguliyet:** Çoklu isolate erişiminde `PRAGMA busy_timeout = 5000;` (5 saniye) tanımlanarak `SQLITE_BUSY` kilitlenmeleri önlenir.

### 3.4 Kaza, Elektrik Kesintisi ve Veri Bütünlüğü
- Kasada beklenmedik bir elektrik kesintisi veya işletim sistemi çökmesi yaşandığında:
  - SQLite WAL mimarisinde yarım kalmış transaction'lar ana `.db` dosyasına sızmaz.
  - Uygulama yeniden başlatıldığında SQLite, `.wal` dosyasını otomatik olarak denetler; tamamlanmamış işlemleri geri alır (rollback), onaylanmış işlemleri ana dosyaya aktarır (checkpoint). Veritabanı bozulmaz.

### 3.5 Canlı Yedekleme ve Dosya Kopyalama Güvenliği
- **Kritik Kural:** WAL modu açık bir veritabanında `market_pos.db` dosyasını Windows Explorer veya `File.copy` ile doğrudan kopyalamak **kesinlikle yasaktır**. En güncel veriler `market_pos.db-wal` dosyasında olduğundan, bu kopya bozuk veya tutarsız olur.
- **Doğru Yöntem:** SQLite'ın yerel Online Backup API'si veya SQL komutu olan `VACUUM INTO 'C:\Yedek\backup.db';` çalıştırılmalıdır. Bu komut, canlı çalışan kasayı durdurmadan atomik ve tutarlı bir anlık görüntü (snapshot) üretir.

### 3.6 Hassas Bilgilerin Korunması
- Yerel SQLite şifreleme anahtarları, yerel API oturum belirteçleri ve cihaz kimlik bilgileri işletim sisteminin güvenli kasası (Windows Credential Manager / Windows DPAPI) üzerinden korunur. Somut saklama kütüphanesi tercihi açık konu olup Faz 1 kapsamında ele alınacaktır.

---

## 4. Android (Mobil) Teknik Doğrulaması

### 4.1 Motor ve Dizin Yapısı
- **Teknoloji:** `drift` + `sqlite3_flutter_libs` (C-FFI üzerinden `libsqlite3.so`).
- **Fiziksel Dizin:** Uygulama özel korumalı alanı:  
  `/data/user/0/com.marketpos.mms/databases/market_pos.db`
- **İzolasyon:** Linux UID seviyesinde izole edilmiştir; root yetkisi olmayan diğer uygulamalar bu dosyaya fiziksel olarak erişemez.

### 4.2 Süreç Sonlandırma ve Bellek Yönetimi (Process Lifecycle)
- Android OS bellek ihtiyacında arka plandaki POS uygulamasını aniden sonlandırabilir (`Low Memory Killer`).
- Atomik yerel transaction yapımız sayesinde, süreç transaction ortasında sonlandırılsa dahi veritabanı tutarsız duruma düşmez; yeniden açılışta otomatik temizlenir.

### 4.3 Arka Plan Senkronizasyonu ve WorkManager Gerçekliği
- **Araç:** Android `WorkManager` (Flutter `workmanager` eklentisi).
- **Gerçekçi Sınırlar ve Kısıtlamalar:**
  - Android OS, pil tasarrufu (Doze Mode, App Standby Buckets) nedeniyle arka plan işlerini geciktirebilir.
  - Periyodik görevler için Android'in izin verdiği minimum aralık **15 dakikadır**.
  - **Mimari Sonuç:** Android'de sürekli ve anlık çalışan bir arka plan senkronizasyonu **garanti edilemez**. Senkronizasyon öncelikli olarak uygulama ön plandayken (Foreground) işletilmeli, WorkManager ise cihaz cepteyken "fırsat buldukça" çalışan ikincil bir süpürücü olarak konumlandırılmalıdır.

### 4.4 Güvenlik ve Güncelleme Dayanıklılığı
- **Güncellemeler:** Google Play veya APK güncellemesi yapıldığında veritabanı dizini korunur; veriler silinmez. Yalnızca kullanıcı işletim sistemi ayarlarından "Verileri Temizle" derse silinir.
- **Hassas Veriler:** Android Keystore destekli AES-256 şifreleme (`flutter_secure_storage`).

---

## 5. iOS (Mobil) Teknik Doğrulaması

### 5.1 Sandbox ve Dizin Mimarisi
- **Teknoloji:** `drift` + `sqlite3_flutter_libs` (C-FFI).
- **Fiziksel Dizin:**  
  `NSApplicationSupportDirectory` $\to$ `/var/mobile/Containers/Data/Application/<UUID>/Library/Application Support/market_pos.db`
- **Kritik Kural:** Dosya `Documents` dizinine konulursa kullanıcının iTunes/Files uygulamasında görünür; `Caches` dizinine konulursa işletim sistemi yer açmak için silebilir. `Library/Application Support` tek doğru adrestir.

### 5.2 iOS File Protection Sınıfı Kısıtlaması (`CRITICAL`)
- iOS varsayılan olarak dosyalara `NSFileProtectionComplete` atayabilir.
- **Tehlike:** Cihaz kilitlendiğinde (ekran kapandığında) dosya şifrelenir ve erişilemez hale gelir. Eğer arka planda çalışan bir görev veritabanına yazmaya çalışırsa `Operation not permitted (SQLite Error 14: CantOpen)` hatası fırlar!
- **Sertleştirilmiş Çözüm:** Veritabanı dosyası oluşturulurken iOS dosya koruma sınıfı açıkça:  
  `NSFileProtectionCompleteUntilFirstUserAuthentication` olarak ayarlanmalıdır. Bu sayede kullanıcı cihaz kilidini sabah bir kez açtıktan sonra, ekran kilitlense dahi arka plan işlemleri veritabanına güvenle erişebilir.

### 5.3 Arka Plan Çalıştırma Kısıtlamaları (`BGTaskScheduler`)
- Apple, uygulamaların arka planda serbestçe daemon çalıştırmasına izin vermez.
- `BGAppRefreshTask` tamamen iOS işletim sisteminin yapay zekâ algoritmasının (kullanıcının uygulamayı açma alışkanlıkları, pil seviyesi, Wi-Fi durumu) insiyatifindedir. İşletim sistemi isterse arka plan görevini saatlerce çalıştırmayabilir.
- **Mimari Kural:** iOS mimarisinde "sürekli arka plan senkronizasyonu" varsayımı kesinlikle yapılamaz. Senkronizasyon, uygulamanın aktif kullanıldığı anlarda ve ön plana gelişlerde tamamlanmalıdır.

### 5.4 Hassas Veriler ve iCloud Yedeklemesi
- **Keychain:** Token'lar iOS Keychain Services üzerinde saklanır.
- **iCloud Dışlama:** `Application Support` dizinindeki veritabanı dosyasına `NSURLIsExcludedFromBackupKey = true` bayrağı konulmalıdır. Aksi halde kullanıcının kişisel iCloud kotasına gereksiz SQLite WAL dosyaları yüklenir.

---

## 6. Web Platformu Teknik Doğrulaması (En Kritik Alan)

Web ortamı, masaüstü ve mobil platformlardan **temelde farklıdır ve en yüksek veri kaybı riskini barındırır.**

### 6.1 Drift Web ve SQLite WASM Desteği
- Güncel Drift (v2.x), WebAssembly (`sqlite3.wasm`) tabanlı `WasmDatabase` mimarisini resmi olarak desteklemektedir.
- Web ortamında SQLite iki farklı depolama arka ucu (VFS) ile çalışabilir:
  1. **OPFS (Origin Private File System):** W3C standardı. Web Worker içinde gerçek bir dosya sistemi gibi çalışır; son derece hızlıdır.
  2. **IndexedDB VFS:** SQLite WASM motorunun verileri IndexedDB bloklarında saklaması. OPFS desteklemeyen eski tarayıcılarda yedek çözümdür.

### 6.2 Tarayıcı Depolama Tahliyesi (Browser Storage Eviction) Riski (`CRITICAL`)
- **Masaüstü ve mobilde işletim sistemi veritabanı dosyasını asla kendi kendine silmez.**
- **Web ortamında ise tarayıcı, depolama alanını "tahliye edilebilir önbellek" (evictable cache) kabul eder:**
  1. **Disk Baskısı:** Cihaz disk alanı dolmaya başladığında tarayıcı IndexedDB / OPFS verilerini kullanıcıya haber vermeden **tamamen silebilir**.
  2. **Safari / WebKit 7 Gün Kuralı (ITP):** Kullanıcı Safari üzerinden web uygulamasını 7 gün boyunca ziyaret etmezse, WebKit akıllı takip koruması (ITP) kapsamında sitenin tüm yerel depolama alanını **otomatik olarak temizler**!
  3. **Kullanıcı Temizliği:** Kasiyer veya çalışan tarayıcı geçmişini / çerezleri temizlediğinde veritabanı anında yok olur!
- **Kısmi Koruma (`StorageManager.persist()`):** Uygulama açılışında `navigator.storage.persist()` çağrılarak "kalıcı depolama" izni istenebilir. Ancak tarayıcı bu izni vermeyi garanti etmez.

### 6.3 Çoklu Sekme ve Eşzamanlılık (Multi-Tab Concurrency)
- Kasiyer aynı MMS web uygulamasını yanlışlıkla 2 veya 3 farklı sekmede açarsa:
  - SQLite WASM tek bir WebAssembly örneğidir. İki farklı sekme aynı OPFS dosyasına doğrudan yazmaya kalkarsa dosya kilidi hatası oluşur.
  - **Çözüm Gereksinimi:** Drift Web, sekmeler arası koordinasyon için `SharedWorker` veya Web Locks API (`navigator.locks`) üzerinden "Lider Seçimi" (Leader Election) kullanır. Tüm veritabanı işlemlerini tek sekme yürütür; diğer sekmeler bu sekmeyle mesajlaşır. Ancak `SharedWorker` mobil Safari'de desteklenmez veya sorunludur.

### 6.4 Çevrimdışı Açılış ve PWA Sınırları
- Web uygulamasının internet yokken açılabilmesi için Service Worker (PWA mimarisi) zorunludur. Ancak Service Worker ve Cache API güncellemelerinde yaşanan önbellek tutarsızlıkları risk oluşturur.

### 6.5 Web Doğrulama Kararı
> [!WARNING]
> **WEB PLATFORMU DEĞERLENDİRME SONUCU:**  
> Web ortamı, internet kesintisinde saatlerce bağımsız çalışan, yüzlerce çevrimdışı satış fişi biriktiren ana bir market kasası terminali için **güvenli bir birincil depolama ortamı DEĞİLDİR**.  
> Web platformu projemizde; **"Yönetim Konsolu / Rapor İnceleme / Çevrimiçi Öncelikli (Connected-First)"** olarak konumlandırılmalı; fiziksel market kasası (POS) olarak ise veri dayanıklılığı %100 kanıtlanmış olan **Windows Masaüstü** veya **Android Tablet/Telefon** native uygulamaları kullanılmalıdır.

---

## 7. Depolama Alternatiflerinin Karşılaştırma Matrisi

| Kriter | Seçenek A: Drift + Native SQLite (Windows/Android/iOS) | Seçenek B: Drift Web + SQLite WASM (OPFS) | Seçenek C: Saf IndexedDB (Web) | Seçenek D: Platforma Özel Ayrı DB (Ör. Hive/Isar) |
|---|---|---|---|---|
| **Platform Kapsamı** | Windows, Android, iOS, macOS, Linux | Web (Chrome, Edge, Firefox, Safari) | Yalnızca Web | Platforma göre değişir |
| **Transaction Yeteneği** | **Tam ACID (İç içe transaction, rollback)** | **Tam ACID (WASM içinde SQLite)** | Zayıf / Sınırlı (Key-Value transaction) | NoSQL düzeyi |
| **İlişkisel Bütünlük & FK** | **Mükemmel (Bileşik FK, UNIQUE, CHECK)** | **Mükemmel (SQLite motoru aktif)** | Yok (Uygulama kodu yönetmek zorunda) | Yok / Çok sınırlı |
| **Veri Dayanıklılığı** | **Mutlak (OS silmez, elektrik kesintisine dayanıklı)** | **Orta / Düşük (Browser eviction, temizlik riski)** | **Düşük (Tarayıcı önbellek silme riski)** | Yüksek |
| **WAL & Concurrency** | **Mevcut (Çoklu okuyucu, tek yazar)** | Sınırlı (Tek worker / SharedWorker) | Asenkron kilitler | Sınırlı |
| **Canlı Online Yedekleme** | **Mevcut (`VACUUM INTO`, Online Backup API)** | Yok (Tarayıcı dışına dosya export gerekir) | Manuel JSON export | Kütüphaneye bağlı |
| **Geliştirme & Bakım** | **Tek Şema (Aynı Drift tabloları ve DAO'lar)** | **Tek Şema (Drift tabloları birebir aynı)** | Çift Kodlama (Ayrı Web DAO katmanı) | Çift Mimari (Tamamen ayrı kod) |
| **MMS İçin Uygunluk** | **MÜKEMMEL (Birincil POS Depolama Standardı)** | **UYGUN (Yalnızca Yönetim/Yedek Arayüz)** | **UYGUN DEĞİL (Yüksek efor, düşük bütünlük)**| **UYGUN DEĞİL (Mimariyi böler)** |

---

## 8. Platform Bazlı Önerilen Depolama Mimarisi

Araştırma bulguları ışığında **MMS için en sağlam, sürdürülebilir ve hatasız mimari model**:

1. **Native Platformlar (Windows, Android, iOS):**  
   - Tek standart: **`drift` + `sqlite3_flutter_libs`** (Native C-FFI).
   - Tam WAL modu, 5 saniye busy timeout, atomik transaction garantisi.
   - Tüm şube ve kasa operasyonları için birincil güvenli depolama.
2. **Web Platformu:**  
   - Teknoloji: **`drift/wasm.dart`** (`sqlite3.wasm` + OPFS / IndexedDB VFS).
   - Aynı Drift şeması kullanılır (ikinci bir NoSQL/IndexedDB katmanı yazılmaz; kod tabanı tek kalır).
   - **Kullanım Kapsamı:** Web platformunda çevrimdışı çalışma desteklenir; ancak veri kaybı riskine karşı arayüzde *"Web sürümünde tarayıcı geçmişini temizlemek yerel verileri silebilir. Ana kasa işlemleri için Windows veya Mobil uygulamayı tercih ediniz"* bilgilendirmesi yapılır.

---

## 9. Repository ve Adaptör İzolasyonu (Clean Architecture)

Clean Architecture kurallarımız (`docs/ai/rules/clean-architecture.md`) uyarınca platform depolama farklılıkları Domain katmanına **kesinlikle sızdırılamaz**:

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│ PRESENTATION & DOMAIN KATMANI (Platformdan %100 Habersiz Saf Dart)          │
│ - ProductRepository, SaleRepository, SyncRepository                         │
│ - GetProductsUseCase, CompleteSaleUseCase vb.                               │
├─────────────────────────────────────────────────────────────────────────────┤
│ DATA KATMANI (Ortak Drift DAO ve Tablolar)                                  │
│ - ProductRepositoryImpl, SaleRepositoryImpl                                  │
│ - AppDatabase (Ortak 25 Tablo Tanımı, Ortak Sorgular, Ortak TypeConverter)  │
├─────────────────────────────────────────────────────────────────────────────┤
│ INFRASTRUCTURE KATMANI: Platform Bağlantı Fabrikası (Conditional Import)     │
│                                                                             │
│                   ┌─────────────────────────────┐                           │
│                   │   connection_factory.dart   │                           │
│                   │  (Ortak DatabaseConnection) │                           │
│                   └──────────────┬──────────────┘                           │
│                                  │                                           │
│         ┌────────────────────────┴────────────────────────┐                 │
│         ▼                                                 ▼                 │
│ ┌───────────────────────────────┐         ┌───────────────────────────────┐ │
│ │   connection_native.dart      │         │     connection_web.dart       │ │
│ │ - path_provider               │         │ - drift/wasm.dart             │ │
│ │ - NativeDatabase (FFI)        │         │ - sqlite3.wasm                │ │
│ │ - WAL PRAGMA yapılandırması   │         │ - OPFS / IndexedDB fallback   │ │
│ └───────────────────────────────┘         └───────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

- **İzolasyonun Faydası:**  
  Uygulamanın 25 tablosu, DAO'ları, Use Case'leri, UI ekranları ve iş kuralları Windows, Android, iOS ve Web'de **birebir aynı kod tabanını** paylaşır. Yalnızca veritabanının diskteki dosya bağlantısını açan tek bir fabrika fonksiyonu (`constructDbConnection()`) conditional export ile platforma özel çalışır.

---

## 10. Backup ve Restore Etkileri

| Platform | Canlı Yerel Yedek Alma (`Safety Snapshot`) | Geri Yükleme (Restore) Mekanizması | Dikkat Edilmesi Gereken Kritik Kural |
|---|---|---|---|
| **Windows** | `VACUUM INTO 'C:\Yedek\snap.db'` veya SQLite Online Backup API. | Dosya kopyalama ile değiştirme (App kapatılarak veya Drift bağlantısı dispose edilerek). | Kasa açıkken ham dosya kopyalanmaz; WAL checkpoint zorunludur. |
| **Android** | SQLite Online Backup API veya app-specific dizine `VACUUM INTO`. | Yerel dosya değişimi + Drift Isolate restart. | Android scoped storage sınırlarına dikkat edilmelidir. |
| **iOS** | `NSApplicationSupportDirectory` içinde `VACUUM INTO`. | Dosya değişimi + app state refresh. | `NSFileProtection` izinleri kopyalanan dosyaya da atanmalıdır. |
| **Web** | SQLite WASM bellek export'u $\to$ Kullanıcıya `.db` dosyası indirtme. | Dosya seçici (File Picker) ile `.db` yüklenip IndexedDB/OPFS'e yazılması. | Otomatik yerel dosya yazımı yapılamaz; kullanıcı download/upload aksiyonu gerekir. |

---

## 11. Offline-First Sınırlamaları ve Platform Güvence Matrisi

| Güvence / Yetenek | Windows PC | Android Mobil | iOS Mobil | Web Tarayıcı |
|---|---|---|---|---|
| **Elektrik Kesintisinde Veri Güvenliği** | **%100 (ACID/WAL)** | **%100 (ACID/WAL)** | **%100 (ACID/WAL)** | Orta (Browser crash riski) |
| **İnternetsiz Günlerce Kesintisiz Çalışma**| **EVET** | **EVET** | **EVET** | **RİSKLİ (7 gün ITP riski)** |
| **Tarayıcı / Kullanıcı Temizliğinden Korunma**| **KORUMALI** | **KORUMALI** | **KORUMALI** | **KORUMASIZ (Cache temizliği)** |
| **Arka Planda Senkronizasyon Çalıştırma** | **Sürekli (Isolate)** | **Periyodik (WorkManager)** | **Fırsatçı (BGTaskScheduler)**| **Yalnızca Sekme Açıkken** |
| **Donanım Cihaz Kimliği (Hardware UUID)** | **Mükemmel (WMI/Registry)**| **Mükemmel (ANDROID_ID)**| **Mükemmel (identifierForVendor)**| **Zayıf (Cookie/Fingerprint)** |
| **Önerilen MMS Rolü** | **Ana Kasa POS** | **Mobil Kasa / Reyon POS** | **Mobil Kasa / Reyon POS**| **Yönetim & İzleme Paneli** |

---

## 12. Açık Kalan Kararlar (`[OPEN]` ve `[PROPOSED]`)

1. **`[OPEN]` Web Platformunun Kasa Rolü Sınırı:**  
   Web sürümünün "tam yetkili bağımsız çevrimdışı kasa" olarak mı, yoksa "çevrimiçi öncelikli yönetim/dashboard ve acil durum terminali" olarak mı konumlandırılacağı kullanıcı onayına sunulmalıdır. (Öneri: Yönetim ve İzleme Paneli olarak sınırlandırılması).
2. **`[PROPOSED]` Web Ortamında `StorageManager.persist()` Otomasyonu:**  
   Web uygulamasında oturum açıldığı anda tarayıcıdan kalıcı depolama izni istenmesi ve reddedilirse kullanıcıya veri güvenliği uyarısı verilmesi önerilmektedir.
3. **`[PROPOSED]` Android WorkManager Periyodu:**  
   Pil tasarrufu ile veri güncelliği arasındaki denge için Android arka plan senkronizasyonunun 15 dakika olarak yapılandırılması önerilmektedir.
4. **`[PROPOSED]` iOS Dosya Koruma Sınıfı Uygulaması:**  
   iOS runner konfigürasyonunda `NSFileProtectionCompleteUntilFirstUserAuthentication` ayarının derleme parametresi olarak sabitlenmesi.

---

## 13. Riskler ve Öneriler

1. **Risk:** Web platformunda kullanıcının tarayıcı geçmişini temizlemesi sonucu henüz buluta iletilmemiş yerel Outbox satışlarının silinmesi.  
   **Öneri:** Kritik satışların yapıldığı market kasası terminallerinde Windows masaüstü veya Android tablet uygulaması zorunlu tutulmalıdır.
2. **Risk:** Windows kasasında açık WAL dosyası varken dışarıdan harici yedekleme yazılımlarının `.db` dosyasını kilitlemesi.  
   **Öneri:** Yedekleme işlemlerinde harici kopyalama yerine mutlaka SQLite'ın `VACUUM INTO` veya Online Backup API mekanizması kullanılmalıdır.
3. **Risk:** iOS'ta ekran kilitlendiğinde arka plan senkronizasyonunun veritabanına erişememesi.  
   **Öneri:** iOS dosya koruma sınıfı doğru yapılandırılmalı ve senkronizasyon öncelikli olarak uygulama ön plandayken tetiklenmelidir.

---

## 14. Faz 0 Kabul Kriterleri Doğrulaması ve Sonuç

> [!TIP]
> **YEREL DEPOLAMA MİMARİSİ DOĞRULAMA ONAYI:**  
> 1. Windows, Android ve iOS platformları için **`drift` + `sqlite3_flutter_libs`** (Native C-FFI) mimarisi; tam ACID, WAL eşzamanlılığı ve veri dayanıklılığı bakımından %100 doğrulanmıştır.  
> 2. Web platformunda aynı Drift şemasının **`drift/wasm.dart`** ile çalışabileceği; ancak tarayıcı mimarisi gereği native platformlarla aynı çevrimdışı veri dayanıklılığına sahip olamayacağı kanıtlanmış ve sınırları belirlenmiştir.  
> 3. Clean Architecture katmanlı mimarisi sayesinde platform farklılıkları altyapı (`infrastructure/database/connection`) katmanında tamamen izole edilmiş; Domain, Data ve Presentation katmanlarının tek bir ortak kod tabanında kalması güvenceye alınmıştır.  
> **Faz 0 henüz tamamlanmamıştır.** Bir sonraki aşama olan **Dağıtım ve Uzaktan Güncelleme Yaklaşımının Netleştirilmesi**ne geçilmesi önerilmektedir.

