# MARKET MMS — Faz S-1 Son Güvenlik İncelemesi (Final Security Review)

**Belge Türü:** Güvenlik Doğrulama ve Kod Denetim Raporu  
**Tarih:** 5 Kasım 2026  
**Denetlenen Aşama:** Faz S-1 (API Security Hardening)  
**Denetim Kapsamı:** Salt Okunur İnceleme (`bin/server.dart`, `lib/security/*`, `test/s1_api_hardening_test.dart`)  
**Sınıflandırma Tipleri:**  
- **`VERIFIED`**: Kod ve testlerle kanıtlanmış, beklenen güvenlik standardını tam sağlayan maddeler.  
- **`NOT VERIFIED`**: Henüz tam olarak ayrıştırılmamış, eksik veya bir sonraki fazlara bağımlı maddeler.  
- **`FAILED`**: Güvenlik açığı veya işlevsel hata barındıran maddeler.

---

## 1. CORS Güvenlik Doğrulaması

### 1.1. Windows Localhost Erişimi Çalışıyor mu?
- **Durum:** **`VERIFIED`**
- **Teknik İnceleme:**  
  [`lib/security/secure_cors_middleware.dart`](./lib/security/secure_cors_middleware.dart) incelendiğinde:
  ```dart
  const allowedOrigins = [
    'http://localhost',
    'http://127.0.0.1',
    'https://localhost',
    'https://127.0.0.1',
  ];
  ```
  İstek başlığındaki `Origin` değeri bu yerel adreslerden biriyle başladığında (`startsWith`):
  - Normal isteklerde `Access-Control-Allow-Origin: <origin>` ve `Access-Control-Allow-Credentials: true` başlıkları eklenmektedir.
  - Preflight (`OPTIONS`) isteklerinde `200 OK` ile birlikte `GET, POST, OPTIONS` ve gerekli başlıklar (`Origin, Content-Type, Authorization`) döndürülmektedir.
  - Windows masaüstü Flutter uygulaması yerel soket üzerinden (`dart:io`) çalıştığında zaten `Origin` göndermez ve tarayıcı kısıtlamalarına tabi değildir.
- **Sonuç:** Windows masaüstü ve localhost tarayıcı/webview erişimi tam uyumlu ve çalışır durumdadır.

---

### 1.2. Android / iOS Cihazların LAN Üzerinden API Erişimi CORS Nedeniyle Engelleniyor mu?
- **Durum:** **`VERIFIED`**
- **Teknik İnceleme:**  
  - **Native Mobil İstemci Davranışı:** Android ve iOS üzerinde çalışan yerel Flutter uygulamaları (`dart:io` `HttpClient`, OkHttp, URLSession) web tarayıcısı değildir; HTTP isteklerinde varsayılan olarak bir `Origin` başlığı göndermezler ve CORS güvenlik sınırlarını uygulamazlar.
  - **Middleware Davranışı:** `secure_cors_middleware.dart` içinde `final origin = request.headers['origin'];` kontrol edilir. `origin == null` olduğunda middleware isteği **asla bloklamaz, 403 veya hata döndürmez**; doğrudan `await innerHandler(request)` çağırarak isteği API rotalarına iletir.
  - **Mobil Web Tarayıcısı İstisnası:** Yalnızca mobil cihazdaki bir web tarayıcısından (örn. Chrome/Safari) `http://192.168.1.x:8080` adresine web sayfası üzerinden cross-origin fetch yapılırsa tarayıcı isteği engeller; bu durum tasarlanan MMS mobil POS mimarisi için beklenen ve istenen güvenlik davranışıdır.
- **Sonuç:** Android ve iOS yerel mobil POS terminallerinin LAN üzerinden API erişimi CORS tarafından engellenmemektedir.

---

### 1.3. CORS'un API Yetkilendirmesinin Yerine Geçmediği Doğrulanıyor mu?
- **Durum:** **`VERIFIED`**
- **Teknik İnceleme:**  
  `bin/server.dart` pipeline sırası:
  ```dart
  final pipeline = Pipeline()
      .addMiddleware(createSecureCorsMiddleware())
      .addMiddleware(createBodyLimitMiddleware(maxBytes: 2 * 1024 * 1024))
      .addMiddleware(createAuthMiddleware(
        db: db,
        isDraining: () => writeQueue.isDraining,
        publicPaths: ['/health'],
      ))
      .addHandler(_router.call);
  ```
  CORS middleware'i en dış katmandadır ve yalnızca HTTP başlıklarını yönetir. İsteğin gövdesi ve yetkisi `createAuthMiddleware` tarafından denetlenir. `Origin` başlığı `http://127.0.0.1` olsa dahi, geçerli bir `Authorization: Bearer <token>` başlığı içermeyen hiçbir korumalı endpoint çağrılamaz.  
  Bu durum `test/s1_api_hardening_test.dart` Test 1 (`/devices/register` -> 401) ve Test 4 (`/admin/shutdown` -> 401) ile doğrulanmıştır.
- **Sonuç:** CORS bir yetkilendirme mekanizması olarak kullanılmamakta, yalnızca tarayıcı tabanlı CSRF/XSS köken filtrelemesi sağlamaktadır.

---

## 2. Shutdown (Kontrollü Kapanma) Güvenlik Doğrulaması

### 2.1. Yönetici Sırrı Normal Cihaz Token'ından Ayrı mı?
- **Durum:** **`NOT VERIFIED`** *(Kısmen Eksik — S-2 / S-4 Kapsamında Ayrıştırılmalı)*
- **Teknik İnceleme:**  
  [`bin/server.dart`](./bin/server.dart) satır 259-269 incelendiğinde:
  ```dart
  // B. Yetkilendirme Kontrolü
  final authenticatedDeviceId = req.context['authenticated_device_id'];
  if (authenticatedDeviceId == null) {
    return Response(
      401,
      body: jsonEncode({
        'error': 'UNAUTHORIZED',
        'code': 'ERR_UNAUTHORIZED',
        'message': 'Shutdown işlemi için yetkilendirme gereklidir.',
      }),
      headers: {'content-type': 'application/json'},
    );
  }
  ```
  Shutdown uç noktası isteği yapan istemcinin doğrulanmış bir cihaz olmasını (`authenticatedDeviceId != null`) şart koşmaktadır. Ancak:
  - Cihazın rolü (`role == 'ADMIN'`) sorgulanmamaktadır.
  - Normal bir kasiyer mobil cihaz token'ı ile yerel bilgisayardan (loopback üzerinden) shutdown çağrıldığında istek kabul edilecektir.
  - Yöneticiye özel ayrı bir sır (admin secret / passphrase) henüz normal terminal token'larından ayrılmamıştır.
- **Gerekli İyileştirme:** Faz S-2 / S-4 aşamasında `Devices` tablosuna `role` sütunu eklenmeli veya shutdown için `%ProgramData%\MarketMMS\secrets\local_admin.token` dosyasından okunan tekil bir yerel admin anahtarı aranmalıdır.

---

### 2.2. Yönetici Sırrı Güvenli Saklanıyor mu?
- **Durum:** **`NOT VERIFIED`** *(Faz S-2 Bağımlılığı)*
- **Teknik İnceleme:**  
  Mevcut S-1 durumunda özel bir admin sırrı tanımlı olmayıp, yetkilendirme SQLite `Devices` tablosundaki `token` sütunu üzerinden yürütülmektedir. Bu token'lar halen açık metin (plaintext) saklanmaktadır. Token'ların SHA-256 hash, salt ve Windows DPAPI pepper ile saklanması **Faz S-2** kapsamındadır.
- **Sonuç:** Sırrın güvenli saklanması S-1 kapsamında tamamlanmamıştır; S-2'de çözülecektir.

---

### 2.3. Loglara veya İstemci Yanıtlarına Sızıyor mu?
- **Durum:** **`VERIFIED`**
- **Teknik İnceleme:**  
  - **İstemci Yanıtı:** `/api/v1/admin/shutdown` uç noktası başarılı olduğunda yalnızca `{"status": "SHUTTING_DOWN", "timestamp": "..."}` döner. Token, yetki bilgisi veya cihaz kimliği yanıtta yer almaz.
  - **Log Çıktısı:** `Timer(const Duration(milliseconds: 50), () => lifecycle.shutdown(reason: 'Admin HTTP shutdown'));` çağrılır. Konsola ve log dosyalarına hiçbir token veya yetkilendirme başlığı yazılmaz.
- **Sonuç:** Kapanma sürecinde hassas bilgi sızıntısı bulunmamaktadır.

---

### 2.4. Loopback Kontrolü IPv4 ve IPv6 İçin Doğru mu?
- **Durum:** **`VERIFIED`**
- **Teknik İnceleme:**  
  [`bin/server.dart`](./bin/server.dart) satır 242-257 incelendiğinde:
  ```dart
  final connectionInfo = req.context['shelf.io.connection_info'] as HttpConnectionInfo?;
  if (connectionInfo != null) {
    final remoteAddr = connectionInfo.remoteAddress;
    final isLoopback = remoteAddr.isLoopback ||
        remoteAddr.address == '127.0.0.1' ||
        remoteAddr.address == '::1' ||
        remoteAddr.address == '0:0:0:0:0:0:0:1' ||
        remoteAddr.address == '::ffff:127.0.0.1';

    if (!isLoopback) {
      return Response.forbidden(...);
    }
  }
  ```
  - Dart `InternetAddress.isLoopback` özelliği RFC 3330 (IPv4 `127.0.0.0/8`) ve RFC 4291 (IPv6 `::1`) standartlarını otomatik denetler.
  - Ek olarak sıkça karşılaşılan string formatları (`127.0.0.1`, `::1`, sıkıştırılmamış `0:0:0:0:0:0:0:1` ve çift yığın IPv4-mapped IPv6 `::ffff:127.0.0.1`) açıkça dahil edilmiştir.
  - `shelf.io.connection_info` doğrudan işletim sistemi TCP soketinden alındığından HTTP başlıkları (örn. `X-Forwarded-For`) ile sahtecilik (spoofing) yapılamaz.
- **Sonuç:** Loopback denetimi IPv4 ve IPv6 için doğru ve eksiksiz uygulanmıştır.

---

## 3. Backup (Yedekleme) Güvenlik Doğrulaması

### 3.1. İstemciden Gelen Hiçbir Veri SQL Sorgusuna veya Dosya Yoluna Ekleniyor mu?
- **Durum:** **`VERIFIED`**
- **Teknik İnceleme:**  
  [`bin/server.dart`](./bin/server.dart) satır 212-230 incelendiğinde:
  ```dart
  final targetDir = Directory(backupDirectory ?? p.join(Directory.current.path, 'backups'));
  if (!targetDir.existsSync()) {
    targetDir.createSync(recursive: true);
  }

  final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '');
  final safeFileName = 'mms_backup_$timestamp.db';
  final safeBackupPath = p.normalize(p.join(targetDir.path, safeFileName));

  await writeQueue.enqueue(() async {
    final escapedPath = safeBackupPath.replaceAll("'", "''");
    await db.customStatement("VACUUM INTO '$escapedPath';");
  });
  ```
  - Dosya adı yalnızca `mms_backup_` öneki, UTC zaman damgası rakamları (`0-9`) ve `.db` uzantısından oluşur.
  - Dosya yolu sunucunun belirlediği korumalı dizin (`targetDir`) ile birleştirilir.
  - İstemciden gelen `body['target_path']` verisi dosya yolu üretiminde veya SQL sorgusunda **KESİNLİKLE KULLANILMAZ**.
  - İstemci parametresi yalnızca kötü niyetli karakterler (`'`, `;`, `--`, null byte) içerip içermediğini tespit edip `400 Bad Request` döndürmek için denetlenir; temiz olsa dahi çöpe atılır.
- **Sonuç:** SQL enjeksiyonu ve keyfi dosya yolu sızması tamamen ortadan kaldırılmıştır.

---

### 3.2. Dosya Oluşturma ve Üzerine Yazma Davranışı Güvenli mi?
- **Durum:** **`VERIFIED`**
- **Teknik İnceleme:**  
  - **Keyfi Dosya Silme Riski:** Önceki koddaki tehlikeli `targetFile.deleteSync()` çağrısı tamamen kaldırılmıştır.
  - **Dizin İzolasyonu:** Yedekler yalnızca sunucunun `backupDirectory` (varsayılan: `./backups`, prod: `%ProgramData%\MarketMMS\backups\`) dizini içinde oluşturulur.
  - **Üzerine Yazma (Overwrite) Davranışı:** Zaman damgası mikrosaniye/saniye hassasiyetinde üretildiği için her çağrıda yeni bir dosya adı oluşur. SQLite'ın `VACUUM INTO` mekanizması hedefte aynı isimde dosya varsa üzerine yazmaz, `SqliteException: output file already exists` hatası vererek mevcut dosyayı korur.
- **Sonuç:** Dosya oluşturma ve üzerine yazma mekanizması güvenlidir.

---

### 3.3. SQL Injection ve Path Traversal Testleri Yeterli mi?
- **Durum:** **`VERIFIED`** *(Temel Regresyon Kapsamı Sağlanmıştır; Ek Sınır Testleri Önerilmektedir)*
- **Mevcut Test Kapsamı ([`test/s1_api_hardening_test.dart`](./test/s1_api_hardening_test.dart)):**
  - **Test 2:** `maliciousSql = "'; DROP TABLE sales; --"` gönderilerek 400 Bad Request alındığı ve `products` tablosunun silinmediği doğrulanmıştır.
  - **Test 3:** `dangerousPath = p.join(tempDir.path, 'arbitrary_overwrite.db')` gönderilerek istemci yoluna dosya yazılmadığı (`existsSync() == false`) ve sunucunun güvenli dizinde oluşturduğu doğrulanmıştır.
- **Gerekli Görülen Ek Testler (Öneri):**
  1. *Çift Dizin Çıkışı (Path Traversal):* `../../etc/passwd` ve `..\..\Windows\System32\config\SAM` gibi açık traversal dizilimlerinin test edilmesi.
  2. *Alt Saniye Çakışması (Sub-second Race):* Çok hızlı iki ardışık yedekleme isteğinde dosya adı çakışması ve hata yönetimi testi.
  3. *Disk Doluluğu / Salt Okunur Klasör:* Yedekleme dizininin yazma izni kısıtlandığında sistemin güvenli hata döndürme testi.

---

## 4. Doğrulama Özeti Tablosu

| Konu No | Başlık | Durum | Gerekçe / Bulgular |
| :---: | :--- | :---: | :--- |
| **1.1** | CORS Windows Localhost | **`VERIFIED`** | `allowedOrigins` loopback adreslerini kapsıyor, preflight ve GET/POST başlıkları doğru. |
| **1.2** | CORS Android/iOS LAN Erişimi | **`VERIFIED`** | Native mobil istemciler `Origin` göndermez; middleware `origin == null` durumunda trafiği engellemez. |
| **1.3** | CORS vs. API Yetkilendirme | **`VERIFIED`** | CORS yetki yerine geçmez; `createAuthMiddleware` tüm korumalı uç noktalarda Bearer token doğrular. |
| **2.1** | Shutdown Yönetici Sırrı Ayrımı | **`NOT VERIFIED`** | Token kontrolü var ancak admin rolü veya ayrı admin sırrı ayrımı yapılmamış; S-2/S-4'te tamamlanmalıdır. |
| **2.2** | Shutdown Sırrının Güvenli Saklanması | **`NOT VERIFIED`** | Token'lar henüz veritabanında plaintext durumdadır; DPAPI ve hash saklama S-2 kapsamındadır. |
| **2.3** | Shutdown Log/Yanıt Sızıntısı | **`VERIFIED`** | Kapanma yanıtında ve konsol loglarında hiçbir token veya hassas bilgi yer almaz. |
| **2.4** | Shutdown IPv4 / IPv6 Loopback | **`VERIFIED`** | `isLoopback` ve `127.0.0.1`, `::1`, `0:0:0:0:0:0:0:1`, `::ffff:127.0.0.1` adresleri eksiksiz denetlenir. |
| **3.1** | Backup SQLi ve Client Path İzolasyonu | **`VERIFIED`** | İstemciden gelen yol yok sayılır; dosya adı sunucuda sadece rakamlardan üretilir, SQLi imkansızdır. |
| **3.2** | Backup Dosya Oluşturma / Overwrite | **`VERIFIED`** | `deleteSync()` kaldırıldı, yedekler izole klasörde zaman damgalı üretilir, mevcut dosya ezilmez. |
| **3.3** | Backup SQLi ve Traversal Testleri | **`VERIFIED`** | Temel SQLi ve traversal testleri başarılıdır; ek alt-saniye çakışma testleri önerilir. |

---

## 5. Sonuç ve Önerilen Sonraki Adım

Faz S-1 kapsamında uygulanan sıkılaştırmalar, temel API saldırı yüzeyini (SQLi, Arbitrary File Delete, DoS, Hata Sızıntısı, Wildcard CORS) başarıyla bertaraf etmiştir.

Denetimde **`NOT VERIFIED`** olarak işaretlenen maddeler (Yönetici rol/sır ayrımı ve token'ların hash/DPAPI ile saklanması), projenin ana güvenlik planına uygun olarak **Faz S-2 (Device Token Security)** aşamasında çözülecektir.

