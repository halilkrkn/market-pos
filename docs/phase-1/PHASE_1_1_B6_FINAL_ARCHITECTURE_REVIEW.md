# MARKET MMS — FAZ 1.1 B-6 FINAL MİMARİ İNCELEME RAPORU

**Rapor Tarihi:** 6 Kasım 2026  
**Aşama:** Faz 1.1 — Windows Client Foundation (B-6 Final Architecture Review)  
**İncelenen Modül:** [`lib/core/storage/local_database_service.dart`](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart)  
**İnceleme Amacı:** Kod değişikliği yapılmaksızın son B-6 remediation implementasyonunun Future semantiği, sorgu tahliyesi (query drain) ve kapanış timeout mekanizması açısından mimari denetimi.  
**Kural:** Kaynak kodda hiçbir değişiklik yapılmamış; yeni test veya bağımlılık eklenmemiştir.

---

## Yönetici Özeti ve Sınıflandırma Tablosu

| İnceleme Konusu | Değerlendirme Kriteri | Sınıflandırma | Temel Gerekçe |
|---|---|:---:|---|
| **A. Initialize / Close Future Semantics** | In-flight başlatma/kapanış sıralaması, kapalı DB dönmeme garantisi, çoklu path yönetimi | **PARTIAL** | Kapanış varken başlatma ve sıralı geçişler güvenle yönetilmektedir. Ancak eşzamanlı farklı path taleplerinde in-flight Future'ın path doğrulaması yapmaması ve `closeActive()` ile `initialize()` yarışında çağrıcıya kapalı instance dönmesi riski bulunmaktadır. |
| **B. Active Query Drain** | `_activeQueryCount` kapsamı, repository ve database getter'ları üzerinden doğrudan erişim | **PARTIAL** | Diagnostics sorguları (`getPendingOutboxCount`, vb.) `_runQuery` ile başarıyla izlenmekte ve tahliye edilmektedir. Ancak `repository` ve `database` getter'ları üzerinden doğrudan çalıştırılan asıl iş yükü sorguları bu sayacın dışındadır ve kapanış sırasında `ConnectionClosedException` alabilir. |
| **C. Graceful Close Timeout** | Sonsuz bekleme riski, kontrollü timeout, veri bütünlüğü ve hata raporlama | **PARTIAL** | 2 saniyelik kontrollü timeout mekanizması mevcuttur; aktif sorgular nedeniyle sonsuz bekleme (deadlock) riski yoktur. Ancak timeout anında telemetri/log üretilmemekte (silent swallow) ve `_db.close()` çağrısının kendi timeout'u bulunmamaktadır. |

---

## 1. Konu A: Initialize / Close Future Semantics (PARTIAL)

### 1.1. Initialize Devam Ederken Close Çağrıldığında Dönen Değer
Kod akışı incelendiğinde ([`lib/core/storage/local_database_service.dart#L90-L106`](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L90-L106)):
```dart
final future = _performInitialize(customPath);
_initializationFuture = future;

try {
  final service = await future;
  _instance = service;
  return service;
} ...
```
Başlatma işlemi in-flight iken eşzamanlı olarak [`closeActive()`](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L262-L283) çağrıldığında:
```dart
static Future<void> closeActive() async {
  if (_initializationFuture != null) {
    try {
      final service = await _initializationFuture!;
      await service.close();
    } catch (_) {}
    return;
  } ...
}
```
- `closeActive()`, in-flight olan `_initializationFuture`'ın bitmesini bekler (`await _initializationFuture!`) ve açılan nesneyi hemen `service.close()` ile kapatır.
- **Çağrıcıya Ne Döner?**
  `LocalDatabaseService.initialize()` çağrısını başlatan birinci çağrıcı, `await future` tamamlandığında `service` nesnesini teslim alır. Ancak tam o esnada `closeActive()` devreye girerek bu nesneyi kapattığı için birinci çağrıcının elindeki nesnenin `service.isClosed` değeri `true` haline gelmiş olabilir.
- **Kapatılmış veya Geçersiz DB Instance Döndürülmeme Kanıtı:**
  - Standart kullanımda ve sıralı çağrılarda: [`initialize()`](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L76-L83) başında `if (current != null && !current._isClosed)` denetimi yapılır. Eğer bellekteki mevcut instance kapanmışsa (`_isClosed == true`), bu instance **ASLA** geri döndürülmez; atlanarak yeni bir veritabanı açılır.
  - Ancak eşzamanlı `initialize()` ve `closeActive()` yarışında, `initialize()` başarıyla tamamlanan nesneyi dönerken hemen arkasından nesne kapatıldığı için çağrıcı `isClosed == true` olan bir nesne tutabilir. Bu nesneyle sorgu atılmaya çalışıldığında `DatabaseClosedException` fırlatılır. Veri bozulması veya çökme olmaz; fakat çağrıcı beklenmedik bir şekilde kapalı instance ile karşılaşır.

### 1.2. Eşzamanlı Initialize ve Close İşlemlerinin Olası Sıralamaları
1. **`initialize()` -> `close()` (Sıralı):** Tamamen deterministik. `initialize()` açar, `close()` kapatır, referans temizlenir. (**PASS**)
2. **`close()` sürerken `initialize()` çağrılması:** `_activeCloseFuture != null` kontrolü sayesinde yeni başlatma işlemi eski SQLite dosya kilitleri ve WAL checkpoint'i tamamen serbest bırakılana kadar bekletilir. Dosya kilit çatışması (`SQLITE_BUSY`) yaşanmaz. (**PASS**)
3. **`initialize()` sürerken `closeActive()` çağrılması:** `_initializationFuture` beklenir ve açılışı takiben kapatma yapılır; arkada kapatılmamış öksüz bağlantı bırakılmaz. (**PASS**)
4. **`initialize()` sürerken eski bir nesnenin `instanceOld.close()` çağrılması:** `instanceOld.close()` artık `_initializationFuture`'a dokunmadığı için (`identical` kontrolü kaldırıldığı için) devam eden yeni açılışı bozmaz. (**PASS**)

### 1.3. Farklı DB Path Taleplerinde Eşzamanlı Çağrılar
Kod incelendiğinde ([`lib/core/storage/local_database_service.dart#L86-L88`](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L86-L88)):
```dart
// 3. Devam eden bir başlatma Future'ı varsa eşzamanlı çağrıları ona bağla
if (_initializationFuture != null) {
  return _initializationFuture!;
}
```
- **Kritik Mimari Tespit:** `_initializationFuture` statik değişkeni, hangi path için başlatıldığını (`customPath`) saklamamaktadır.
- Eğer Çağrıcı A `initialize(customPath: 'dbA.db')` çağırır ve bu işlem sürerken Çağrıcı B eşzamanlı olarak `initialize(customPath: 'dbB.db')` çağırırsa:
  - Çağrıcı B, `_initializationFuture != null` kontrolüne takılır ve doğrudan Çağrıcı A'nın Future'ına bağlanır.
  - Sonuç olarak Çağrıcı B, `'dbB.db'` talep etmesine rağmen `'dbA.db'` veritabanı örneğini alır!
- **MMS Mimarisindeki Durumu:** Market POS masaüstü uygulamasında tek bir istemci veritabanı (`client_local.db`) kullanıldığı için canlı çalışma ortamında bu durum bir aksamaya yol açmaz. Ancak çoklu tenant veya test senaryolarında farklı path'lerin eşzamanlı başlatılması durumunda bir yarış koşuludur.
- **Sonuç:** Bu kısıt nedeniyle Konu A **PARTIAL** olarak derecelendirilmiştir.

---

## 2. Konu B: Active Query Drain (PARTIAL)

### 2.1. `_activeQueryCount` Kapsamı
`_activeQueryCount` sayacı ve `_runQuery` metodu incelendiğinde ([`lib/core/storage/local_database_service.dart#L170-L183`](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L170-L183)):
```dart
Future<T> _runQuery<T>(Future<T> Function() query) async {
  _ensureOpen();
  _activeQueryCount++;
  try {
    return await query();
  } finally {
    _activeQueryCount--;
    if (_activeQueryCount == 0 && _activeQueriesDrainedCompleter != null) {
      if (!_activeQueriesDrainedCompleter!.isCompleted) {
        _activeQueriesDrainedCompleter!.complete();
      }
    }
  }
}
```
Bu mekanizmayı yalnızca aşağıdaki 3 metot kullanmaktadır:
1. `getPendingOutboxCount()` ([`L230-L239`](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L230-L239))
2. `getLocalSalesCount()` ([`L242-L249`](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L242-L249))
3. `getLocalProductsCount()` ([`L252-L259`](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L252-L259))

### 2.2. Repository ve Database Üzerinden Yapılan İşlemler
[`database`](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L186-L189) ve [`repository`](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L192-L195) erişimleri:
```dart
ClientDatabase get database {
  _ensureOpen();
  return _db;
}

ClientStorageRepository get repository {
  _ensureOpen();
  return _repository;
}
```
- **Sorgu Tahliyesini Atlama Durumu:** **EVET, tamamen atlamaktadır.**
- Getter çağrıldığında yalnızca anlık `_ensureOpen()` denetimi yapılır.
- Çağrıcı `repository` veya `database` referansını aldıktan sonra gerçekleştirdiği uzun soluklu yazma, outbox ekleme veya satış transaction operasyonları `_activeQueryCount` sayacını **artırmaz**.
- Dolayısıyla `service.close()` çağrıldığında, `_performClose()` metodu `_activeQueryCount == 0` görür ve beklemeksizin anında `await _db.close();` satırına geçer.

### 2.3. Gerçek Risk Değerlendirmesi
- **Risk Seviyesi:** **ORTA.**
- **Etki:** Bir kasa satışı veya outbox kuyruğa yazma transaction'ı sürerken arka planda veya kullanıcı çıkışında `close()` tetiklenirse, SQLite bağlantısı transaction ortasında kapatılır.
- **Veri Bütünlüğü:** SQLite WAL modunda yarıda kalan transaction'lar otomatik olarak geri alınır (rollback); dolayısıyla diskteki dosya bozulmaz. Ancak Flutter istemcisi unhandled `ConnectionClosedException` istisnasıyla karşılaşır ve işlem başarısız olur.

### 2.4. Mevcut Mimariye En Uygun Çözüm Önerisi (Kod Değişikliği Yapılmadı)
Clean Architecture sınırlarını ihlal etmeden en temiz iki çözüm yaklaşımı:
1. **Repository Delegasyon Sarmalayıcısı (Decorator Pattern):** `LocalDatabaseService`, doğrudan repository nesnesini dışarı açmak yerine operasyonları `_runQuery` üzerinden delegasyonla yürütebilir veya `ClientStorageRepository` içerisine bir `activeOperationTracker` entegre edilebilir.
2. **Drift Transaction Kancası:** `ClientDatabase` sınıfına bir `activeTransactionCount` özelliği eklenerek, `_performClose` sırasında hem `_activeQueryCount == 0` hem de `_db.activeTransactionCount == 0` olana kadar beklenmesi sağlanabilir.

---

## 3. Konu C: Graceful Close Timeout (PARTIAL)

### 3.1. Aktif Sorgu Tamamlanmazsa Close Davranışı ve Sonsuz Bekleme
Kod akışı incelendiğinde ([`lib/core/storage/local_database_service.dart#L309-L318`](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L309-L318)):
```dart
if (_activeQueryCount > 0) {
  final drainCompleter = Completer<void>();
  _activeQueriesDrainedCompleter = drainCompleter;
  if (_activeQueryCount > 0) {
    await drainCompleter.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );
  }
}
```
- **Sonsuz Bekleme (Deadlock / Hang) Riski:** **YOKTUR (%0).**
- `timeout(const Duration(seconds: 2), onTimeout: () {})` ifadesi, aktif sorgular tamamlanmasa dahi maksimum 2 saniye sonra beklemeden çıkar.
- 2 saniye dolduğunda `await drainCompleter.future` bloke kalmaz ve doğrudan `await _db.close();` satırına geçer.

### 3.2. Hata Raporlama ve Veri Bütünlüğü Değerlendirmesi
- **Sessiz Yutma (Silent Swallow):** `onTimeout: () {}` bloğu boş bırakılmıştır. 2 saniye dolup zorla kapatmaya geçildiğinde sisteme hiçbir log, uyarı veya hata bildirilmemektedir. Kapanışın temiz mi bittiği yoksa timeout nedeniyle zorla mı kesildiği tespit edilememektedir.
- **`_db.close()` Kendi Timeout Koruması:** `await _db.close();` çağrısının kendi üzerinde bir timeout yoktur. Drift'in WAL dosyasını temizleme veya isolate bağlantısını kesme sürecinde işletim sistemi seviyesinde kilitlenme (örneğin harici bir antivirüs veya yedekleme aracının dosyayı exclusive kilitlemesi) oluşursa bu satır askıda kalabilir.

### 3.3. Drift Davranışıyla Uyumlu İyileştirme Önerisi (Kod Değişikliği Yapılmadı)
1. **Timeout Durumunda Telemetri/Uyarı:**
   ```dart
   await drainCompleter.future.timeout(
     const Duration(seconds: 2),
     onTimeout: () {
       // Uyarı logu veya diagnostics metriği:
       // "LocalDatabaseService.close: In-flight queries did not drain within 2s, proceeding with force close."
     },
   );
   ```
2. **`_db.close()` İçin Emniyet Timeout'u:**
   ```dart
   await _db.close().timeout(
     const Duration(seconds: 3),
     onTimeout: () {
       // Isolate yanıt vermezse UI thread'i kilitlememe emniyeti
     },
   );
   ```

---

## 4. Güvenlik Backlog Durumu (B-2 ve B-3)

Aşağıdaki güvenlik maddeleri silinmemiş, kapatılmamış ve mimari backlog'da açık tutulmaktadır:
- **B-2 (TLS Root CA Pinning):** İstemcinin merkezi Windows Hub HTTPS sertifikasını yerel gömülü Root CA üzerinden doğrulaması (LAN eşleştirme ve sertifika dağıtım fazında ele alınacaktır).
- **B-3 (DPAPI Secure Device Token Storage):** Windows üzerinde `deviceToken` değerinin DPAPI / Windows Credential Manager aracılığıyla şifreli olarak kalıcı saklanması (Cihaz eşleştirme fazında ele alınacaktır).

---

## 5. İnceleme Sonucu ve Tavsiye

| Madde | Durum | Açıklama |
|---|:---:|---|
| **A. Future Semantics** | **PARTIAL** | Tekil DB ve sıralı geçişler güvenli; concurrent farklı path eşleşmesi ve kapalı instance teslimi iyileştirmeye açık. |
| **B. Active Query Drain** | **PARTIAL** | Diagnostics sayaçları güvenle tahliye ediliyor; repository/database getter işlemleri sayaç dışı. |
| **C. Graceful Close Timeout** | **PARTIAL** | 2 sn timeout sonsuz beklemeyi başarıyla önlüyor; telemetri eksik ve `_db.close()` timeout'u yok. |

> [!NOTE]
> Mevcut kod canlı pilot ve Faz 1.1 masaüstü gereksinimleri için kararlı ve kullanılabilir durumdadır (216 test yeşil). Tespit edilen PARTIAL hususlar, uygulamanın normal akışını bozmayan ancak Faz 1.2+ veya multi-tenant/arka plan senkronizasyonu aşamalarında ele alınması tavsiye edilen mikro-mimari iyileştirmelerdir.

