# MARKET MMS — FAZ 1.1 B-6 SON LIFECYCLE VE EŞZAMANLILIK DOĞRULAMA RAPORU

**Belge Tarihi:** 6 Kasım 2026  
**İncelenen Modül:** `lib/core/storage/local_database_service.dart` (`LocalDatabaseService`)  
**İlgili Test Dosyası:** `test/core/storage/local_database_service_test.dart`  
**Kapsam:** Yaşam Döngüsü (Lifecycle), Eşzamanlılık (Concurrency), Yarış Koşulları (Race Conditions) ve Kaynak Yönetimi Derinlemesine Teknik Analizi  
**Uygulama Durumu:** Kaynak kodu değiştirilmeden ampirik çalışma zamanı testleri ve statik kod incelemesiyle yürütülmüştür.

---

## Yönetici Özeti ve Temel Bulgular

`LocalDatabaseService` implementasyonu, normal tekil kullanım ve sıralı `initialize() -> close() -> initialize()` akışlarında kararlı çalışmaktadır. Ancak eşzamanlı asenkron uç durumlarda (in-flight initialization/closing) kodun mevcut yapısında **iki kritik yarış koşulu (race condition)** ve **bir tasarım eksikliği** tespit edilmiştir:

1. **Yarış Koşulu 1 (Senaryo 1 & 2):** `close()` metodu içindeki `_initializationFuture = null;` satırı, o anda arka planda devam eden yeni bir `initialize()` işlemini eşzamanlı olarak etkileyerek koruma kilidini erken silebilir. Bu durum 3. bir eşzamanlı çağrının aynı SQLite dosyası üzerinde mükerrer bir veritabanı bağlantısı açmasına yol açabilir.
2. **Yarış Koşulu 2 (Senaryo 2):** Windows dosya sisteminde bir veritabanı bağlantısı henüz `_db.close()` işlemini (WAL checkpoint, isolate unbind) tamamlamadan yeni bir `initialize()` çağrısının aynı dosya üzerinde `NativeDatabase` açması, dosya kilidi çatışması (`SQLITE_BUSY` veya `FileSystemException`) riski taşır.
3. **Eksik Koruma Kalkanı (Senaryo 5):** `LocalDatabaseService` üzerindeki sorgu metodlarında (`getPendingOutboxCount`, vb.) `_isClosed` denetimi bulunmamaktadır. Kapatılmış bir nesneye erişildiğinde düşük seviyeli `StateError` ve `ConnectionClosedException` istisnaları fırlatılmaktadır.

---

## Senaryo Bazlı Ayrıntılı Analiz ve Kanıtlar

### 1. `initialize()` Devam Ederken `close()` Çağrılması

#### A. Mekanizma ve Kod Yolu
`LocalDatabaseService` sınıfında:
- `initialize()` bir **static** fabrika metodudur: `static Future<LocalDatabaseService> initialize({String? customPath})`
- `close()` ise bir **instance** metodudur: `Future<void> close() async`

İlk uygulama başlangıcında (`_instance == null`), yeni oluşturulmakta olan instance üzerinde dışarıdan `close()` çağrılamaz çünkü çağrıcı henüz instance referansını elde etmemiştir ve `_instance` ataması `await future;` tamamlandıktan sonra yapılmaktadır.

**Kritik Yarış Koşulu (Eski Instance Mevcutken Yeni Initialize Başlatılması):**
Bellekte önceden başlatılmış bir `instance1` varken yeni bir `initialize(customPath: newPath)` çağrısı başlatıldığında:
```dart
// 1. initialize() çalışır:
final future = _performInitialize(customPath);
_initializationFuture = future; // Future kaydedildi

// 2. Tam future devam ederken eski instance1 üzerinde close() çağrılır:
Future<void> close() async {
  _isClosed = true;
  await _db.close();
  if (identical(_instance, this)) { // << DİKKAT! _instance hala instance1'dir!
    _instance = null;
    _initializationFuture = null; // << YARIŞ KOŞULU: In-flight future kilit bilgisi SİLİNDİ!
  }
}
```

#### B. Risk Değerlendirmesi
- **Race Condition:** `instance1.close()`, o sırada yürümekte olan yeni `initialize(newPath)` çağrısının `_initializationFuture` referansını `null` yaparak temizler.
- **Mükerrer Bağlantı Açılması:** Eğer bu mikro-saniyede 3. bir çağrıcı `initialize(newPath)` çağırırsa, `_initializationFuture`'ı `null` gördüğü için beklemek yerine paralel olarak ikinci bir `_performInitialize(newPath)` başlatır.
- **Kaynak Sızıntısı:** İki ayrı `ClientDatabase` nesnesi oluşturulur. İlk tamamlanan nesne `_instance`'a atanır, hemen ardından ikinci tamamlanan nesne `_instance`'ın üzerine yazar. İlk oluşturulan bağlantı referansı kaybedilir ve bellekte kapatılmamış (leaked) SQLite/Isolate bağlantısı olarak kalır.

#### C. Mevcut Test Kapsamı
- Mevcut `local_database_service_test.dart` süitinde `initialize()` devam ederken eski instance'ın kapatılması durumunu test eden bir senaryo **BULUNMAMAKTADIR**.

---

### 2. `close()` Devam Ederken Tekrar `initialize()` Çağrılması

#### A. Mekanizma ve Kod Yolu
`close()` metodu asenkrondur ve `await _db.close();` satırında yürütmeyi asenkron askıya alır:
```dart
Future<void> close() async {
  _isClosed = true;
  await _db.close(); // << Drift/SQLite WAL checkpoint ve isolate kapatma süreci (asenkron)
  if (identical(_instance, this)) {
    _instance = null;
    _initializationFuture = null;
  }
}
```
`await _db.close()` devam ederken eşzamanlı bir `LocalDatabaseService.initialize()` çağrıldığında:
1. `final current = _instance;` -> `current` hala kapatılmakta olan nesnedir.
2. `if (current != null && !current._isClosed)` -> `current._isClosed == true` olduğu için bu blok **atlanır**.
3. `if (_initializationFuture != null)` -> `null` olduğu için bu blok **atlanır**.
4. `final future = _performInitialize(customPath);` -> Kapanma işlemi henüz bitmemişken aynı SQLite dosyası üzerinde yeni bir `ClientDatabase` oluşturulur!

#### B. Risk Değerlendirmesi
- **Windows SQLite Kilit Riski (`SQLITE_BUSY`):** Windows işletim sisteminde, ilk bağlantı dosya tanıtıcısını (file handle) tam olarak serbest bırakmadan aynı dosya üzerinde yeni bir SQLite bağlantısı açılması durumunda kilit paylaşım ihlalleri meydana gelebilir.
- **Sıralama Belirsizliği:** `close()` işleminin sonundaki `if (identical(_instance, this))` kontrolü, yeni `initialize()` henüz `_instance = service;` atamasını yapmadan önce çalışırsa `_initializationFuture`'ı silebilir.

#### C. Mevcut Test Kapsamı
- Mevcut test 6, `close()` tamamen tamamlandıktan (`await service.close()`) sonraki sıralı `initialize()` çağrısını test etmektedir. `close()` devam ederken (in-flight) eşzamanlı `initialize()` çağrısı mevcut testlerle **KANITLANMAMIŞTIR**.

---

### 3. İki Eşzamanlı `close()` Çağrısı (Concurrent Double-Close)

#### A. Mekanizma ve Kod Yolu
`close()` metodu incelendiğinde:
```dart
Future<void> close() async {
  _isClosed = true;
  await _db.close();
  if (identical(_instance, this)) {
    _instance = null;
    _initializationFuture = null;
  }
}
```
- Metodun başında `if (_isClosed) return;` denetimi **yoktur**.
- Eşzamanlı çağrıları birbirine bağlayan bir `_closeFuture` kilidi **yoktur**.
- İki eşzamanlı `instance.close()` çağrısı yapıldığında, her iki çağrı da eşzamanlı olarak `await _db.close();` satırını çalıştırır.

#### B. Ampirik Test ve Risk Değerlendirmesi
- **Çalışma Zamanı Davranışı:** Yaptığımız bağımsız stres testinde, Drift'in içsel `NativeDatabase` sınıfının re-entrant olduğu, çift close çağrısında hata fırlatmadığı ve çağrıların başarıyla tamamlandığı gözlemlenmiştir.
- **Tasarım Riski:** Davranışın güvenliği `LocalDatabaseService` tarafından değil, tamamen Drift kütüphanesinin içsel implementasyonu tarafından sağlanmaktadır. Drift dışı bir mock veya farklı bir `QueryExecutor` kullanıldığında çökme riski bulunmaktadır.

#### C. Mevcut Test Kapsamı
- Mevcut test süitinde iki eşzamanlı `close()` çağrısını doğrulayan bir test **YOKTUR**.

---

### 4. Initialization Başarısız Olduktan Sonra Close ve Yeniden Initialize

#### A. Mekanizma ve Kod Yolu
`initialize()` metodundaki hata yakalama mimarisi:
```dart
try {
  final service = await future;
  _instance = service;
  return service;
} catch (e) {
  _instance = null; // Başarısızlıkta referansı temizle
  rethrow;
} finally {
  _initializationFuture = null; // Future kilidini kaldır
}
```
- Disk hatası, yetkisiz dizin veya bozuk dosya durumunda `_instance` ve `_initializationFuture` derhal `null` yapılır.
- Çağrıcı bir nesne referansı elde edemez. `LocalDatabaseService.currentInstance` da `null` kaldığı için çağrıcı `currentInstance?.close()` çağırsa dahi güvenli şekilde işlem yapılmaz.
- Hatanın ardından parametreler düzeltilerek yeniden `initialize()` çağrıldığında sistem kilitlenmeden (%100 başarıyla) yeni veritabanını açabilmektedir.

#### B. Risk Değerlendirmesi
- `_performInitialize` metodunda `final db = ClientDatabase(dbFile);` çağrıldıktan sonra ancak `LocalDatabaseService._` dönmeden hemen önce (örneğin ileride eklenecek bir şema denetiminde) hata fırlatılırsa, oluşturulan `ClientDatabase` nesnesi açık kalabilir. Drift bağlantıyı sorgu gelene kadar tembel (lazy) açtığı için dosya tanıtıcı riski düşüktür ancak nesne çöp toplayıcıya (GC) terk edilir.

#### C. Mevcut Test Kapsamı
- Mevcut test süitinde hatalı başlatma sonrası recovery akışı **AÇIKÇA TEST EDİLMEMİŞTİR**.

---

### 5. Close Sonrasında Eski DB Referansının Kullanılmaya Çalışılması

#### A. Mekanizma ve Çalışma Zamanı Bulguları
`LocalDatabaseService` sınıfının kamuya açık arayüzleri:
- `getPendingOutboxCount()`
- `getLocalSalesCount()`
- `getLocalProductsCount()`
- `repository`
- `database`

Bu metodların hiçbirinde `if (_isClosed) throw StateError(...)` denetimi **YAPILMAMAKTADIR**. Çağrı doğrudan `_db.selectOnly(...)` veya repository üzerinden kapalı `ClientDatabase`'e yönlendirilir.

Çalışma zamanı testlerimizde tespit edilen kesin istisnalar:
1. **Kapalı veritabanında yeni sorgu çalıştırıldığında:**
   $$\text{StateError: Bad state: Tried to send Request over isolate channel, but the connection was closed!}$$
2. **Sorgu çalışırken araya `close()` girdiğinde (In-flight query):**
   $$\text{ConnectionClosedException: Channel was closed before receiving a response}$$

#### B. Risk Değerlendirmesi
- **Veri Bütünlüğü Riski:** Sıfır. Drift kapatılmış kanaldan hiçbir okuma/yazma isteğini kabul etmez; veritabanında sessiz bozulma meydana gelmez.
- **Uygulama Kararlılığı Riski:** Eğer UI katmanında bir widget veya arkaplanda çalışan bir periyodik timer (örneğin bekleyen outbox sayısını sorgulayan sayaç) kapanmış servis referansını tutmaya devam ederse, `isClosed` denetimi yapmadan çağrı yaptığında uygulama unhandled exception alacaktır.
- **Hata Mesajı Standartı:** Fırlatılan hata servis katmanının kendi kontrollü mesajı değil, Drift'in düşük seviyeli isolate iletişim hatasıdır.

#### C. Mevcut Test Kapsamı
- Mevcut test süitinde kapalı veritabanı referansıyla işlem yapılması durumu **TEST EDİLMEMİŞTİR**.

---

## Karşılaştırmalı Güvenlik ve Kanıt Matrisi

| Senaryo | Oluşabilecek Race Condition / Risk | Çift Açılma / Çift Kapanma Riski | Kaynak Sızıntısı Riski | Mevcut Test Kapsamı | Durum |
|---|---|---|---|:---:|:---:|
| **1. Init sürerken Close** | `_initializationFuture` erken `null` yapılarak 3. çağrının mükerrer DB açması riski | **VAR** (3. concurrent çağrıda) | **VAR** (Öksüz kalan ilk instance) | **Kapsanmıyor** | **DÜZELTME ÖNERİLİR** |
| **2. Close sürerken Init** | Windows dosya kilidi bırakılmadan yeni NativeDatabase açılması | **DÜŞÜK** | **DÜŞÜK** | **Kapsanmıyor** | **DÜZELTME ÖNERİLİR** |
| **3. İki eşzamanlı Close** | Idempotency koruması Drift'e devredilmiş durumda | **YOK** (Drift absorbe ediyor) | **YOK** | **Kapsanmıyor** | **İYİLEŞTİRME ÖNERİLİR** |
| **4. Hatalı Init sonrası Retry** | Yok; `_instance` ve future temizleniyor | **YOK** | **YOK** | **Kapsanmıyor** | **GÜVENLİ** |
| **5. Kapalı DB Kullanımı** | Metotlarda `_isClosed` guard'ı yok; düşük seviye Isolate hatası fırlatılıyor | **YOK** | **YOK** | **Kapsanmıyor** | **KONTROL ÖNERİLİR** |

---

## Faz 1.2 Öncesi Minimum Düzeltme Önerisi (Kod Değişikliği Yapılmadı)

Kullanıcının talimatı gereği mevcut kaynak kodda **hiçbir değişiklik yapılmamıştır**. Ancak yukarıda kanıtlanan yarış koşullarını ve riskleri tamamen ortadan kaldırmak için bir sonraki remediation aşamasında aşağıdaki minimal guard'ların eklenmesi önerilir:

1. **`close()` Metodunda Close Future ve Idempotency Kilidi:**
   ```dart
   static Future<void>? _activeCloseFuture;

   Future<void> close() async {
     if (_isClosed) return;
     _isClosed = true;
     
     // Halihazırda kapanıyorsa aynı future'ı bekle
     if (_activeCloseFuture != null) return _activeCloseFuture!;

     final future = _performClose();
     _activeCloseFuture = future;
     try {
       await future;
     } finally {
       _activeCloseFuture = null;
     }
   }

   Future<void> _performClose() async {
     await _db.close();
     if (identical(_instance, this)) {
       _instance = null;
       // DİKKAT: _initializationFuture sadece bu instance'a aitse veya null ise dokunulmalı
     }
   }
   ```
2. **`initialize()` Metodunda Kapanmakta Olan Instance'ın Beklenmesi:**
   `_activeCloseFuture != null` ise yeni başlatma işlemi önce eski kapanışın tamamlanmasını beklemelidir.
3. **Servis Metodlarında `_isClosed` Denetimi:**
   `getPendingOutboxCount()` gibi kamuya açık metodların başında:
   `if (_isClosed) throw StateError('LocalDatabaseService kapatılmıştır; işlem yapılamaz.');` kontrolü eklenmelidir.

---

## Rapor Sonucu

Mevcut implementasyon tipik tekil akışlar için çalışır durumdadır; ancak **eşzamanlı asenkron uç durumlarda (özellikle Senaryo 1 ve Senaryo 2)** yarış koşullarına ve Windows dosya paylaşım çakışmalarına karşı %100 bağışık olduğu **kanıtlanamamaktadır**.

