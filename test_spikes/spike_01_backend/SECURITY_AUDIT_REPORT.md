# MARKET MMS — SPIKE-01 Güvenlik Denetim Raporu (Security Audit)

**Tarih:** 5 Kasım 2026  
**Rapor Adı:** `SECURITY_AUDIT_REPORT.md`  
**Konum:** `test_spikes/spike_01_backend/SECURITY_AUDIT_REPORT.md`  
**Denetim Türü:** Salt Okunur (Read-Only) Statik Kod ve Mimari Güvenlik Denetimi  
**Kapsam:** `test_spikes/spike_01_backend/` (Dart Shelf API, SQLite Drift, WinSW Yapılandırması)  
**Denetçi Metodolojisi:** OWASP API Security Top 10, CWE / SANS Top 25 ve Windows Least Privilege İlkeleri  

---

## 1. Yönetici Özeti

MARKET MMS SPIKE-01 prototipi, teknik fizibilite (yüksek throughput, tekil yazıcı kuyruğu, `SQLITE_BUSY` eliminasyonu, atomik transaction ve process crash recovery) açısından üstün bir başarı sergilemiştir. 

Ancak bir "mimari prototip" olarak geliştirildiği için, **üretim ve pilot güvenlik kontrolleri henüz koda eklenmemiştir**. Yapılan denetimde:
- **3 adet CRITICAL (Kritik)**,
- **4 adet HIGH (Yüksek)**,
- **4 adet MEDIUM (Orta)**,
- **3 adet LOW (Düşük)**,
- **2 adet INFO (Bilgilendirme)**

seviyesinde bulgu tespit edilmiştir. **Mevcut haliyle prototip, canlı bir market pilot ortamına doğrudan dağıtılmaya GÜVENLİK AÇISINDAN HAZIR DEĞİLDİR.** Pilot dağıtımı öncesinde özellikle kimlik doğrulamasız cihaz kaydı, SQL/Path enjeksiyonu ve ağ şifrelemesi açıklarının giderilmesi zorunludur.

---

## 2. İncelenen Alanlar ve Kod Bulguları

### A. Device Authentication (Cihaz Kimlik Doğrulama)
1. **Token Üretimi:** Prototipte sunucu tarafında kriptografik token üretim mekanizması (`Random.secure()`, UUIDv4 veya HMAC) **yoktur**. İstemci veya test kodu dilediği string'i token olarak iletmektedir.
2. **Token Saklama:** `lib/db/database.dart` içindeki `Devices` tablosunda token alanı düz metin (`TextColumn get token => text()()`) olarak saklanmaktadır. Veritabanına salt-okunur erişen biri tüm cihaz token'larını görebilir.
3. **Token Karşılaştırma:** `auth_middleware.dart` satır 56'da `d.token.equals(token)` SQL sorgusu ile aranmaktadır. Sabit zamanlı (constant-time) güvenli string kıyaslaması yapılmamaktadır.
4. **Cihaz Yetki İptali (Revocation):** `Devices.isActive = false` kontrolü başarıyla çalışmaktadır; iptal edilen cihazlar anında `403 DEVICE_REVOKED` almaktadır. Ancak cihazın yerel satış hakkını koruyup yalnızca merkezi API'yi kesme kuralı başarılı olmakla birlikte, iptal token'ının blacklist/cache kontrolü yoktur (her istek doğrudan DB sorgusu yapar).
5. **Eşleştirme (Pairing):** Cihaz kaydı sırasında işletme sahibinin fiziksel onayını gerektiren bir PIN, OTP veya Master Hub ekranı onay adımı bulunmamaktadır.

### B. HTTP API Security (Uç Nokta Güvenliği)
1. **Açık Bırakılan Uç Noktalar:** `bin/server.dart` satır 291'de `publicPaths: ['/health', '/api/v1/devices/register']` tanımlanmıştır. Bu durum, ağdaki herhangi bir cihazın hiçbir yetkilendirme olmadan `/api/v1/devices/register` çağırabilmesine neden olmaktadır.
2. **Yönetim Uç Noktası Koruması:** `/api/v1/admin/shutdown` uç noktası herhangi bir geçerli token ile çağrılabilmektedir. Rol ayrımı (RBAC - Owner vs Cashier) ve kaynak IP kısıtlaması (sadece `127.0.0.1`) yoktur; kasadaki sıradan bir telefon tüm market backend'ini durdurabilir.
3. **CORS Yapılandırması:** `bin/server.dart` satır 287'de `.addMiddleware(corsHeaders())` varsayılan ayarlarla eklenmiştir. Bu ayar `Access-Control-Allow-Origin: *` üretir. Kasiyerin telefonunda veya PC tarayıcısında açılan kötü amaçlı bir web sayfası, tarayıcı üzerinden yerel backend'e istek atabilir.
4. **Gövde Boyutu Sınırı:** Shelf üzerinde `maxRequestBodySize` kısıtı yoktur. `req.readAsString()` çağrısı yüzlerce megabaytlık istekleri belleğe alabilir; Out-Of-Memory (OOM) çökmesine yol açabilir.

### C. Windows Security (İşletim Sistemi ve Servis Güvenliği)
1. **Servis Hesabı:** `service_wrapper/MarketMmsSpike01.xml` içinde özel bir hesap tanımlanmadığı için WinSW servisi varsayılan olarak **`NT AUTHORITY\SYSTEM` (LocalSystem)** altında çalışmaktadır. LocalSystem, işletim sistemindeki en yüksek yetkili hesaptır.
2. **NTFS İzinleri:** Veritabanı ve log dosyaları `c:\Users\halil\Github\market-pos\test_spikes\spike_01_backend\` altında yer almaktadır. Bu dizin yerel standart Windows kullanıcılarına (`CodexSandboxUsers`) okuma yetkisi vermektedir.
3. **Güvenlik Duvarı:** Windows Güvenlik Duvarı port kuralı açıldığında ağ profilinin `Private` (Özel Ağ) yerine yanlışlıkla `Public` seçilmesi riski mevcuttur.

### D. Secrets ve Logging (Gizli Bilgiler ve Log Güvenliği)
1. **Log Sanitization:** `bin/server.dart` içerisinde Bearer Token veya kredi kartı/satış verisi loglanmamaktadır (Temiz).
2. **Hata Mesajlarında Bilgi İfşası (Information Disclosure):** `bin/server.dart` satır 228'de yakalanan hatalar `e.toString()` şeklinde doğrudan HTTP 500 gövdesine yazılmaktadır. SQLite dosya yolları, tablo isimleri ve stack trace istemciye sızmaktadır.
3. **Log Dosyası İzinleri:** `service_wrapper/logs/` klasörüne standart kullanıcılar erişebilmektedir.

### E. SQLite ve Veri Güvenliği
1. **SQL Injection Riski:** `bin/server.dart` satır 247'de:
   ```dart
   await db.customStatement("VACUUM INTO '$targetPath';");
   ```
   `targetPath` doğrudan JSON gövdesinden alınarak raw SQL içerisine birleştirilmiştir. Tek tırnak (`'`) ile SQL enjeksiyonu yapılabilir.
2. **Rastgele Dosya Silme / Yazma (Arbitrary File Overwrite):** Satır 241'de `if (targetFile.existsSync()) targetFile.deleteSync();` komutu ile istemciden gelen dosya yolu doğrudan silinmekte ve üzerine SQLite yedeği yazılmaktadır.
3. **Veritabanı Şifreleme:** `crash_master.db` ve `-wal` dosyaları disk üzerinde şifresiz (plaintext) durmaktadır.

### F. Network Security (Ağ Güvenliği)
1. **IP Dinleme (Binding):** Sunucu `InternetAddress.anyIPv4` (0.0.0.0) üzerinde dinlemektedir. Yönetim uç noktaları (`/admin/shutdown`, `/backup/snapshot`) ile istemci uç noktaları (`/sales`) aynı port ve aynı arayüzde açıktır.
2. **Şifresiz Ağ İletişimi (Cleartext HTTP):** Tüm iletişim düz metin HTTP üzerinden gerçekleşmektedir. Wi-Fi ağını dinleyen biri Bearer token'ları ve müşteri sepetlerini görebilir.

---

## 3. Tehdit Modeli ve Senaryo Analizleri

| Senaryo No | Tehdit Senaryosu | Mevcut Koruma | Kalan Güvenlik Açığı / Risk | Risk Seviyesi |
| :-: | :--- | :--- | :--- | :---: |
| **S-01** | **Aynı Wi-Fi ağına bağlanan yetkisiz bir cihaz (Müşteri veya saldırgan)** | Korumalı uç noktalarda Token kontrolü var. | `/api/v1/devices/register` açık olduğu için saldırgan kendini sisteme yetkili cihaz olarak kaydedebilir. | **CRITICAL** |
| **S-02** | **Kasiyerin mobil cihazının çalınması veya kaybolması** | `Devices.isActive = false` yapılarak erişim `403` ile kesilebilir. | Token cihazda düz metin saklanıyorsa ve hızlıca iptal edilmezse, Master Hub'a yetkisiz satış/stok müdahalesi yapılabilir. | **MEDIUM** |
| **S-03** | **Device Token'ın ele geçirilmesi (Ağ dinleme - Sniffing)** | Yok (HTTP kullanılmaktadır). | HTTP üzerinden giden `Authorization: Bearer <token>` başlığı Wi-Fi paket yakalama (Wireshark) ile doğrudan okunabilir ve taklit edilebilir. | **HIGH** |
| **S-04** | **Windows PC'yi kullanan kısıtlı yerel Windows kullanıcısı** | Yok. | SQLite `.db` ve `.db-wal` dosyaları NTFS seviyesinde kısıtlanmamıştır; dosyayı kopyalayıp tüm satış/cihaz geçmişini açabilir. | **HIGH** |
| **S-05** | **Servisin uzaktan durdurulması (Denial of Service - DoS)** | Token doğrulaması var. | Herhangi bir geçerli token'a sahip cihaz `/api/v1/admin/shutdown` çağırarak tüm market kasalarını kilitleyebilir. | **HIGH** |
| **S-06** | **Rastgele dosya silme ve sistem dosyasını bozma** | Token doğrulaması var. | `/api/v1/backup/snapshot` parametresine `C:\Windows\...` yazılarak yetkili servis (`LocalSystem`) eliyle kritik sistem dosyaları ezilebilir. | **CRITICAL** |
| **S-07** | **Ağ trafiğinin değiştirilmesi (Man-in-the-Middle - MITM)** | Idempotency key mükerrerliği önler. | TLS olmadığı için satış fiyatı veya kalemleri ağ üzerinde değiştirilebilir (fiyat manipülasyonu). | **HIGH** |

---

## 4. Önceliklendirilmiş Güvenlik Bulguları Matrisi

### [SEC-01] Kimlik Doğrulamasız ve Kısıtlamasız Cihaz Kaydı (Device Registration Bypass)
- **Öncelik:** **CRITICAL**
- **Etkilenen Bölüm:** `bin/server.dart` (satır 68–90 ve satır 291)
- **Mevcut Davranış:** `/api/v1/devices/register` uç noktası `publicPaths` listesindedir. İsteyen herkes HTTP POST ile `device_id`, `name` ve `token` göndererek veritabanına `isActive: true` kaydı ekleyebilmektedir. Üstelik `insertOnConflictUpdate` kullanıldığı için mevcut meşru bir cihazın token'ını ezebilmektedir.
- **Gerçek Saldırı Senaryosu:** Marketin "Müşteri Wi-Fi" ağına veya ortak ağa bağlanan bir saldırgan, bir curl komutuyla sisteme `DEV_HACKER` cihazını ekler veya mevcut `DEV_KASA_1` kaydını kendi token'ı ile güncelleyerek kasayı devre dışı bırakır.
- **Kanıt Türü:** **KANITLANMIŞ AÇIK**
- **Önerilen Çözüm:** İlk cihaz eşleştirme (Pairing) işlemi Master Hub ekranında tek kullanımlık 6 haneli bir eşleşme kodu (PIN/OTP) girilmeden veya Master Hub arayüzünden "Onayla" butonuna basılmadan aktif edilmemelidir.
- **Pilot İçin Zorunlu mu?:** **EVET (ZORUNLU)**

---

### [SEC-02] `VACUUM INTO` Üzerinden SQL Injection ve Keyfi Dosya Ezme (Arbitrary File Overwrite)
- **Öncelik:** **CRITICAL**
- **Etkilenen Bölüm:** `bin/server.dart` (satır 236–258)
- **Mevcut Davranış:** 
  ```dart
  final targetFile = File(targetPath);
  if (targetFile.existsSync()) targetFile.deleteSync();
  await db.customStatement("VACUUM INTO '$targetPath';");
  ```
  `targetPath` doğrudan JSON parametresinden alınmakta ve raw SQL string'ine eklenmektedir.
- **Gerçek Saldırı Senaryosu:** 
  1. Saldırgan `target_path: "C:\\Users\\KasaPC\\Desktop\\önemli_dosya.txt"` göndererek hedef dosyayı sildirir.
  2. Saldırgan `target_path: "backup.db'; DROP TABLE sales; --"` göndererek SQL enjeksiyonu tetikleyebilir.
- **Kanıt Türü:** **KANITLANMIŞ AÇIK**
- **Önerilen Çözüm:** İstemciden dosya yolu kabul edilmemelidir. Yedekleme yolu sunucu tarafında sabit bir klasör (`%APPDATA%\MarketMMS\backups\`) ve güvenli zaman damgası (`backup_YYYYMMDD_HHMMSS.db`) ile sunucu tarafından üretilmelidir. Dosya yolu sanitization'dan geçirilmeli, tek tırnaklar kaçış karakteriyle korunmalıdır.
- **Pilot İçin Zorunlu mu?:** **EVET (ZORUNLU)**

---

### [SEC-03] Şifresiz HTTP İletişimi ve Ağ Dinleme (Cleartext Transmission of Sensitive Data)
- **Öncelik:** **CRITICAL**
- **Etkilenen Bölüm:** `bin/server.dart` (satır 297–300)
- **Mevcut Davranış:** Sunucu düz metin HTTP (`shelf_io.serve`) ile çalışmaktadır.
- **Gerçek Saldırı Senaryosu:** Market içi Wi-Fi ağına sızan veya aynı modeme bağlı bir saldırgan, `tcpdump` veya `Wireshark` ile ağ trafiğini izleyerek mobil cihazın ilettiği `Authorization: Bearer ...` token'ını ve satış verilerini düz metin olarak yakalar.
- **Kanıt Türü:** **KANITLANMIŞ AÇIK**
- **Önerilen Çözüm:** Pilot ortamında mobil cihazlar ile Master Hub arasında HTTPS (kendinden imzalı yerel sertifika / mTLS veya yerel CA) kullanılmalı ya da en azından istek yükü simetrik anahtarla (AES-GCM) şifrelenmelidir.
- **Pilot İçin Zorunlu mu?:** **EVET (ZORUNLU)**

---

### [SEC-04] Rol Ayrımı Olmayan Yönetim Uç Noktası (Yetkisiz Servis Durdurma - DoS)
- **Öncelik:** **HIGH**
- **Etkilenen Bölüm:** `bin/server.dart` (satır 271–282)
- **Mevcut Davranış:** `/api/v1/admin/shutdown` uç noktası herhangi bir geçerli token taşıyan istek tarafından çağrılabilmektedir. Kasiyer rolündeki bir mobil cihaz bu adrese POST atarak Windows Service'i kapatabilir.
- **Gerçek Saldırı Senaryosu:** Kötü niyetli bir personel, mesai bitiminde veya yoğun saatte cep telefonundan `/api/v1/admin/shutdown` isteği göndererek tüm marketin satış yapmasını engeller.
- **Kanıt Türü:** **KANITLANMIŞ AÇIK**
- **Önerilen Çözüm:** `/admin/*` uç noktaları LAN erişimine tamamen kapatılmalı, yalnızca yerel makineden (`127.0.0.1` / Loopback) gelen isteklere izin verilmeli veya `ROLE_OWNER` yetkisi aranmalıdır.
- **Pilot İçin Zorunlu mu?:** **EVET (ZORUNLU)**

---

### [SEC-05] Servisin `LocalSystem` En Yüksek Yetkiyle Çalışması (Privilege Escalation Riski)
- **Öncelik:** **HIGH**
- **Etkilenen Bölüm:** `service_wrapper/MarketMmsSpike01.xml`
- **Mevcut Davranış:** `<service>` tanımında özel hesap belirtilmediği için Windows Service Control Manager bu süreci `NT AUTHORITY\SYSTEM` olarak çalıştırmaktadır.
- **Gerçek Saldırı Senaryosu:** `SEC-02`'deki dosya silme/yazma açığı ile birleştiğinde, saldırgan Windows'un sistem dosyalarını silebilir veya DLL hijacking gerçekleştirebilir.
- **Kanıt Türü:** **KANITLANMIŞ MİMARİ RİSK**
- **Önerilen Çözüm:** Servis XML'ine `<serviceaccount>` eklenerek servisin kısıtlı `NT AUTHORITY\LocalService` veya özel yerel servis hesabı ile çalışması sağlanmalıdır.
- **Pilot İçin Zorunlu mu?:** **EVET (ZORUNLU)**

---

### [SEC-06] Token'ların Veritabanında Düz Metin (Plaintext) Saklanması
- **Öncelik:** **HIGH**
- **Etkilenen Bölüm:** `lib/db/database.dart` (satır 69)
- **Mevcut Davranış:** `Devices.token` kolonu ham metin olarak kaydedilmektedir.
- **Gerçek Saldırı Senaryosu:** Windows bilgisayara fiziksel veya uzaktan erişimi olan bir kişi, SQLite veritabanı dosyasını bir USB belleğe kopyalayıp DB Browser ile açtığında tüm mobil cihazların token'larını doğrudan ele geçirir.
- **Kanıt Türü:** **KANITLANMIŞ MİMARİ AÇIK**
- **Önerilen Çözüm:** Parolalarda olduğu gibi, Device Token'lar veritabanında asla açık metin tutulmamalı; güvenli bir hash (SHA-256 + salt veya Argon2) ile özetlenmiş olarak saklanmalıdır. Gelen token hash'lenerek karşılaştırılmalıdır.
- **Pilot İçin Zorunlu mu?:** **EVET (ZORUNLU)**

---

### [SEC-07] Hata Yanıtlarında İç Sistem Detaylarının Sızması (Information Leakage)
- **Öncelik:** **MEDIUM**
- **Etkilenen Bölüm:** `bin/server.dart` (satır 228)
- **Mevcut Davranış:** `catch (e) { return Response.internalServerError(body: jsonEncode({'message': e.toString()})); }`
- **Gerçek Saldırı Senaryosu:** Bir işlem hata verdiğinde dönen mesajda dosya yolları, işletim sistemi kullanıcı adı (`C:\Users\halil\...`) ve SQLite hata kodları istemciye döner. Saldırgan bu bilgileri sistem haritası çıkarmak için kullanır.
- **Kanıt Türü:** **KANITLANMIŞ AÇIK**
- **Önerilen Çözüm:** İstemciye yalnızca standart hata kodları (`TRANSACTION_FAILED`, `INTERNAL_ERROR`) dönülmeli; ayrıntılı hata metni ve stack trace yalnızca sunucu tarafındaki güvenli log dosyasına yazılmalıdır.
- **Pilot İçin Zorunlu mu?:** **EVET (ZORUNLU)**

---

### [SEC-08] Geniş CORS Politikası (`Access-Control-Allow-Origin: *`)
- **Öncelik:** **MEDIUM**
- **Etkilenen Bölüm:** `bin/server.dart` (satır 287)
- **Mevcut Davranış:** `corsHeaders()` varsayılan wildcard (`*`) ile çalışmaktadır.
- **Gerçek Saldırı Senaryosu:** Kasiyer veya market sahibi PC'de internette gezinirken kötü amaçlı bir web sitesine girerse, sitenin JavaScript kodu yerel ağdaki `http://127.0.0.1:8085` adresine istek atabilir.
- **Kanıt Türü:** **KANITLANMIŞ MİMARİ RİSK**
- **Önerilen Çözüm:** CORS başlıkları yalnızca yetkili yerel UI kaynaklarına kısıtlanmalı veya masaüstü/mobil native uygulamalar için CORS tamamen kapatılmalıdır.
- **Pilot İçin Zorunlu mu?:** **EVET (ZORUNLU)**

---

### [SEC-09] İstek Gövdesi Boyut Sınırı Eksikliği (Denial of Service - OOM)
- **Öncelik:** **MEDIUM**
- **Etkilenen Bölüm:** `bin/server.dart` (`req.readAsString()`)
- **Mevcut Davranış:** İstek gövdesinin uzunluğu kontrol edilmeden belleğe okunmaktadır.
- **Gerçek Saldırı Senaryosu:** Bir istemci 500 MB boyutunda sahte bir JSON göndererek Dart backend sürecinin Out-Of-Memory ile çökmesine sebep olabilir.
- **Kanıt Türü:** **KANITLANMIŞ RİSK**
- **Önerilen Çözüm:** Shelf pipeline'ına maksimum gövde boyutu sınırı (örneğin satış işlemleri için maks 1 MB) koyan bir middleware eklenmelidir.
- **Pilot İçin Zorunlu mu?:** **ÖNERİLİR**

---

### [SEC-10] Sabit Zamanlı Olmayan Token Karşılaştırması (Timing Attack)
- **Öncelik:** **LOW**
- **Etkilenen Bölüm:** `lib/security/auth_middleware.dart` (satır 56)
- **Mevcut Davranış:** Token doğrulaması SQL seviyesinde string karşılaştırmasıyla yapılmaktadır.
- **Gerçek Saldırı Senaryosu:** Yerel ağda mikrosaniye hassasiyetinde yanıt süresi ölçülerek token karakterleri tahmin edilmeye çalışılabilir.
- **Kanıt Türü:** **TEORİK RİSK** (Yerel ağ gecikmesi dalgalanmaları nedeniyle pratikte zordur).
- **Önerilen Çözüm:** Token'lar hash'lendikten sonra `crypto.fixedTimeComparison` ile karşılaştırılmalıdır.
- **Pilot İçin Zorunlu mu?:** Hayır (SaaS aşamasında zorunlu).

---

### [SEC-11] SQLite Veritabanı ve WAL Dosyalarının Şifresiz Olması
- **Öncelik:** **LOW**
- **Etkilenen Bölüm:** `test_spikes/spike_01_backend/data/`
- **Mevcut Davranış:** Standart SQLite dosya biçimi kullanılmaktadır.
- **Gerçek Saldırı Senaryosu:** Bilgisayarın sabit diski çalınırsa veriler okunabilir.
- **Kanıt Türü:** **BİLİNEN SINIR / TEORİK RİSK**
- **Önerilen Çözüm:** Windows seviyesinde BitLocker etkinleştirilmeli; ileride SQLCipher değerlendirilmelidir.
- **Pilot İçin Zorunlu mu?:** Hayır (Windows BitLocker yeterlidir).

---

### [SEC-12] `/health` Uç Noktasının Sürüm Bilgisi Sızdırması
- **Öncelik:** **INFO**
- **Etkilenen Bölüm:** `bin/server.dart` (satır 54)
- **Mevcut Davranış:** `/health` yanıtında SQLite sürümü açıkça dönmektedir.
- **Öneri:** Bilgi ifşasını en aza indirmek için yalnızca `status: UP` dönülmelidir.

---

## 5. Güvenlik İyileştirme Yol Haritası

### 1. Pilot Öncesi ZORUNLU Düzeltmeler (Faz 1 Başlangıç Şartları):
1. **Cihaz Kaydını Güvene Alma (SEC-01):** `/api/v1/devices/register` genel erişimden çıkarılmalı; Master Hub üzerinde PIN/Onay mekanizması kurulmalıdır.
2. **`VACUUM INTO` Güvenliği (SEC-02):** İstemciden dosya yolu alınması yasaklanmalı; yedekleme yolu sunucu tarafından sabit dizinde üretilmelidir.
3. **Yönetim Uç Noktalarını Yalıtma (SEC-04):** `/api/v1/admin/shutdown` ve `/backup/*` uç noktaları yalnızca `127.0.0.1` (localhost) erişimine izin vermelidir.
4. **Token Hashleme (SEC-06):** Veritabanında token'lar SHA-256 ile özetlenmiş saklanmalıdır.
5. **Hata Ayrıntılarını Gizleme (SEC-07):** HTTP 500 yanıtlarında `e.toString()` sızdırılmamalıdır.
6. **İstek Boyutu Limiti (SEC-09):** Maksimum 2 MB payload sınırı getirilmelidir.
7. **Servis Hesabı Kısıtlaması (SEC-05):** WinSW servisi `LocalSystem` yerine `LocalService` hesabına çekilmelidir.

### 2. Pilot Sırasında Uygulanabilecek İyileştirmeler (Faz 1 İçi):
1. **Yerel Ağ Şifrelemesi (HTTPS / TLS):** Mobil cihazlar ile Master Hub arasında yerel kendinden imzalı sertifika veya mTLS altyapısı kurulmalıdır.
2. **Wi-Fi Ağ Yalıtımı:** Market Wi-Fi modeminde POS cihazları için ayrı bir VLAN veya "Client Isolation" yapılandırılmalıdır.
3. **NTFS ACL İzinleri:** Kurulum script'inde `icacls` ile veritabanı klasörü yalnızca servis kullanıcısına kilitlenmelidir.

### 3. İleride SaaS / Bulut Mimarisine Geçişte Ele Alınacak Gereksinimler:
1. Supabase Auth ve JWT tabanlı çok kiracılı (multi-tenant) kimlik doğrulama.
2. Row Level Security (RLS) politikaları.
3. API Gateway seviyesinde Rate Limiting (Kaba kuvvet saldırı koruması).
4. SQLCipher ile uçtan uca yerel veritabanı şifreleme.

---

## 6. Nihai Değerlendirme ve Karar

### SPIKE-01 Prototipi Pilot Kullanım İçin Güvenlik Açısından Hazır mı?

**HAYIR, MEVCUT HALİYLE PİLOT KULLANIMA HAZIR DEĞİLDİR.**

**Gerekçeli Karar:**
SPIKE-01 prototipi, bir mimari ve performans spike'ı olarak görevini kusursuz yerine getirmiş; Dart + Shelf + SQLite mimarisinin Windows üzerinde bağımsız bir servis olarak yüksek hızda, atomik ve veri kayıpsız çalışabileceğini kanıtlamıştır.

Ancak prototip kodunda yer alan:
- **Herhangi bir cihazın şifresiz `/api/v1/devices/register` ile sisteme yetkili cihaz ekleyebilmesi**,
- **`/api/v1/backup/snapshot` üzerinden keyfi dosya silme ve SQL enjeksiyonu riski**,
- **Herhangi bir yetkili token ile `/api/v1/admin/shutdown` çağrılarak tüm market sisteminin uzaktan durdurulabilmesi**,
- **Ağ trafiğinin şifresiz HTTP olması**,

canlı bir market ortamında ciddi veri güvenliği, hizmet kesintisi ve istismar riskleri barındırmaktadır.

**Bu güvenlik açıkları mimari bir engel (showstopper) değildir;** kod seviyesinde birkaç middleware ve doğrulama kuralı ile kolayca çözülebilecek niteliktedir. Ancak bu düzeltmeler Faz 1 uygulama kodlaması kapsamında yapılmalı; pilot kurulmadan önce güvenlik gereksinimleri eksiksiz karşılanmalıdır.

