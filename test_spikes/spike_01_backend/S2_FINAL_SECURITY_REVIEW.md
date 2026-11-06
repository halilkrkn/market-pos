# MARKET MMS — SPIKE-01: Aşama S-2 Final Güvenlik Denetimi (Security Review)

**Denetim Tarihi:** 5 Kasım 2026  
**Denetlenen Modül:** MARKET MMS — Windows Local Master Hub Backend Spike (SPIKE-01)  
**Denetim Kapsamı:** `test_spikes/spike_01_backend/`  
**Denetçi Modeli:** Antigravity AI Security Auditor  
**Denetim Türü:** Salt Okunur Güvenlik ve Kod İncelemesi (Read-Only Security Audit)  
**Referans Plan:** `test_spikes/spike_01_backend/SECURITY_REMEDIATION_PLAN.md` (Rev. 3)  
**Uygulanan Standartlar:** `code-quality`, `systematic-debugging`, `documentation`

---

## 1. Yönetici Özeti ve Nihai Karar

Aşama S-2 (Device Token Security) kapsamında geliştirilen kriptografik token üretimi, Windows DPAPI entegrasyonu, salt/pepper hashleme, sabit zamanlı karşılaştırma ve token yaşam döngüsü uç noktaları salt okunur olarak denetlenmiştir.

Yapılan inceleme sonucunda:
- Açık metin (plaintext) token saklama riski SQLite şemasından tamamen temizlenmiştir.
- 256-bit CSPRNG entropi ve 128-bit cihaz tuzu (salt) matematiksel olarak doğrulanmıştır.
- Yetkisiz istemcilerin açık cihaz kaydı yapması S-1'de olduğu gibi 401 Unauthorized ile engellenmektedir.
- Token yenileme eski token'ı anında geçersiz kılmakta ve veritabanı şeması gereği aynı anda birden fazla aktif token barındıramamaktadır.
- Ancak **Pepper dosyasının NTFS ACL kısıtlaması henüz kod düzeyinde uygulanmamış (S-4'e bırakılmış)** ve **cihaz kayıt (`register`) uç noktasında kasiyer/admin rol ayrımı henüz bulunmadığı** için onay şartlı olarak verilmiştir.

### Nihai Karar: **APPROVED WITH CONDITIONS** (Şartlı Onay)

---

## 2. 11 Denetim Maddesinin Detaylı Analizi

Aşağıdaki tabloda 11 güvenlik denetim maddesinin bulgu sınıflandırması özetlenmiştir:

| No | Denetim Maddesi | Güvenlik Durumu | Sınıflandırma |
|---|---|---|---|
| **1** | `/api/v1/devices/register` yetkisiz erişim kontrolü | Başlıksız istekler 401 ile engelleniyor; ancak authenticated kasiyer token'ı yeni cihaz kaydedebiliyor. | **PARTIALLY VERIFIED** |
| **2** | `/api/v1/devices/renew-token` çağrı yetkisi | Yalnızca request context'teki geçerli Bearer token sahibi cihaz için çalışıyor. | **VERIFIED** |
| **3** | `/api/v1/devices/revoke` admin yetkisi kontrolü | `X-Admin-Secret` doğrulanıyor; normal cihaz token'ları reddediliyor. | **VERIFIED** |
| **4** | Admin secret ve Shutdown mekanizması tutarlılığı | Her iki endpoint aynı secret'ı sabit zamanlı doğruluyor; shutdown loopback şartı ararken revoke aramıyor. | **VERIFIED** |
| **5** | Pepper dosyası NTFS ACL izinleri | Kod seviyesinde (`icacls` veya Win32 DACL) uygulanmamış; varsayılan izinler geçerli. S-4'e bırakılmış. | **NOT VERIFIED** |
| **6** | DPAPI LocalMachine güvenlik sınırları ve riskleri | Çevrimdışı disk hırsızlığına karşı tam koruma; yerel makinedeki yetkisiz kullanıcılara karşı ACL desteği şart. | **VERIFIED** |
| **7** | Token yenilemede atomiklik ve eski token durumu | Tekil yazıcı kuyruğunda atomik güncelleniyor; eski token anında 401'e düşüyor. | **VERIFIED** |
| **8** | Tekrarlanan yenilemede ikinci aktif token riski | DB şemasında tek bir `tokenHash` sütunu var; mükerrer/ikinci token oluşamaz. | **VERIFIED** |
| **9** | Log, hata mesajı veya audit'te açık bilgi sızıntısı | Hata yanıtlarında stack trace yok; audit tablosunda ve loglarda açık token/pepper kesinlikle yok. | **VERIFIED** |
| **10** | Veritabanında açık token kalıntısı ve şema durumu | `Devices.token` kaldırıldı; taze DB'de şema temiz; eski DB'ler için `onUpgrade` migration henüz yok. | **PARTIALLY VERIFIED** |
| **11** | Yeniden başlama sonrası pepper çözme ve token doğrulama | DB ve DPAPI pepper yeniden yükleme testlerinde (%100) başarıyla doğrulandı. | **VERIFIED** |

---

## 3. Bulguların Teknik Kanıtları ve Kod Analizi

### Madde 1: Cihaz Kaydı (`/api/v1/devices/register`)
- **İncelenen Dosyalar:** [`lib/security/auth_middleware.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/auth_middleware.dart#L25-L42), [`bin/server.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart#L104-L140)
- **Kod İncelemesi:**
  - `server.dart` içerisindeki `publicPaths` listesi: `['/health', '/api/v1/admin/shutdown', '/api/v1/devices/revoke']`.
  - `/api/v1/devices/register` public yollar arasında **değildir**. Dolayısıyla yetkisiz/başlıksız gelen tüm istekler `auth_middleware.dart` tarafından doğrudan **401 Unauthorized (`UNAUTHORIZED`)** ile kesilmektedir. Bu davranış `s1_api_hardening_test.dart` Test 1 ile doğrulanmıştır.
  - **Kalan Risk / Eksiklik:** Halihazırda sisteme kayıtlı geçerli bir Bearer token'a sahip herhangi bir cihaz (örneğin normal bir Kasa 1 terminali), `POST /api/v1/devices/register` endpoint'ini çağırarak sisteme yeni cihazlar ekleyebilir. Çünkü endpoint gövdesinde `role == 'ADMIN'` veya `X-Admin-Secret` kontrolü yapılmamaktadır.
  - **Sınıflandırma:** **PARTIALLY VERIFIED** (Yetkisiz dış ağa kapalı, ancak cihaz içi rol ayrımı henüz yok).

---

### Madde 2: Token Yenileme (`/api/v1/devices/renew-token`)
- **İncelenen Dosyalar:** [`bin/server.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart#L144-L188), [`lib/security/auth_middleware.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/auth_middleware.dart#L70-L90)
- **Kod İncelemesi:**
  - Endpoint istemciden gelen gövdede bir `device_id` parametresi kabul etmez. Cihaz kimliği doğrudan `req.context['authenticated_device_id']` üzerinden alınır.
  - Context ise yalnızca `auth_middleware` tarafından aktif, süresi dolmamış ve hash'i doğrulanan cihaz için set edilmektedir.
  - Başka bir cihaz adına yenileme yapılması teknik olarak imkânsızdır.
  - **Sınıflandırma:** **VERIFIED**

---

### Madde 3 & 4: Admin Yetkisi, İptal (`/api/v1/devices/revoke`) ve Shutdown Karşılaştırması
- **İncelenen Dosyalar:** [`bin/server.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart#L210-L280), [`bin/server.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart#L523-L585)
- **Kod İncelemesi:**
  - Hem `/api/v1/devices/revoke` hem de `/api/v1/admin/shutdown` endpoint'leri `effectiveAdminSecret` kontrolü yapar. Secret tanımlı değilse **503** ile kapanır.
  - İstek başlığında sağlanan sır (`x-admin-secret` veya `Bearer`), `_constantTimeEquals` fonksiyonu ile byte-byte XOR yapılarak sabit zamanda karşılaştırılır.
  - Normal bir kasiyer cihaz token'ı sağlandığında sır ile eşleşmeyeceği için anında **403 Forbidden (`ERR_INVALID_ADMIN_SECRET`)** döner.
  - **Mimari Farklılık:** `/api/v1/admin/shutdown` endpoint'i ek olarak `isLoopback` kontrolü yaparak LAN üzerinden gelen istekleri engeller. `/api/v1/devices/revoke` ise LAN'dan çağrılabilir durumdadır (S-3 TLS gelene kadar LAN üzerinde plaintext admin secret iletilmesi riski mevcuttur).
  - **Sınıflandırma:** **VERIFIED**

---

### Madde 5: Pepper Dosyası NTFS ACL İzinleri
- **İncelenen Dosyalar:** [`lib/security/pepper_manager.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/pepper_manager.dart#L39-L61)
- **Kod İncelemesi:**
  - `pepper_manager.dart` dosyayı oluştururken `file.writeAsBytesSync(encryptedBytes, flush: true)` yöntemini kullanır.
  - Dosya üzerinde Windows NTFS ACL (`icacls`, `SetNamedSecurityInfoW` vb.) çağrısı **yapılmamaktadır**. Dosya bulunduğu dizinin varsayılan erişim haklarını (Authenticated Users / Users oku yetkisi) miras almaktadır.
  - `S2_DEVICE_TOKEN_SECURITY_REPORT.md` raporu Bölüm 10'da bu konunun **Aşama S-4 (Windows Service & OS Hardening)** kapsamında ele alınacağı belirtilmiştir.
  - **Sınıflandırma:** **NOT VERIFIED** (S-4'e ertelenmiştir).

---

### Madde 6: DPAPI LocalMachine Güvenlik Sınırları ve Kalan Riskler
- **İncelenen Dosyalar:** [`lib/security/dpapi.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/dpapi.dart#L51-L69)
- **Analiz:**
  - `CRYPTPROTECT_LOCAL_MACHINE (0x04)` bayrağı kullanılmıştır.
  - **Güçlü Yönü:** Veritabanı ve pepper dosyası diski sökülüp başka bir makineye takıldığında veya dosya sisteminden kopyalandığında (offline hırsızlık), DPAPI anahtarı makineye bağlı olduğu için pepper çözülemez.
  - **Kalan Risk:** `LocalMachine` kapsamı, aynı Windows işletim sisteminde çalışan yerel kullanıcılara karşı bir izolasyon sağlamaz. Eğer yerel bir saldırgan makinede oturum açabilir veya unprivileged bir süreç çalıştırabilirse ve `pepper.dpapi` dosyasına okuma yetkisi varsa, Win32 `CryptUnprotectData` çağrısıyla pepper'ı çözebilir.
  - **Çözüm:** Bu risk ancak Aşama S-4'te NTFS ACL uygulanarak dosyanın sadece `NT SERVICE\MarketMmsService` ve `Administrators` hesaplarına kısıtlanmasıyla bertaraf edilebilir.
  - **Sınıflandırma:** **VERIFIED**

---

### Madde 7 & 8: Token Yenileme Atomikliği ve Tek Aktif Token Garantisi
- **İncelenen Dosyalar:** [`bin/server.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart#L165-L188), [`lib/db/database.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/db/database.dart#L66-L80)
- **Kod İncelemesi:**
  - `Devices` tablosunda `deviceId` primary key'dir. Tabloda tek bir `tokenHash` ve tek bir `salt` sütunu bulunmaktadır.
  - `renew-token` çağrıldığında yazıcı kuyruğu (`writeQueue.enqueue`) içerisinde tekil bir `UPDATE devices SET token_hash = ?, salt = ? WHERE device_id = ?` işletilir.
  - DB şeması gereği aynı cihaz için ikinci bir aktif token'ın saklanması fiziksel olarak mümkün değildir.
  - Eski token ile yapılan tüm sonraki çağrılar anında **401 Unauthorized (`DEVICE_NOT_FOUND`)** döner. (Bkz: `s2_token_security_test.dart` Test 10, 11, 12).
  - **Sınıflandırma:** **VERIFIED**

---

### Madde 9: Token ve Pepper Sızıntı Denetimi
- **İncelenen Dosyalar:** [`lib/security/auth_middleware.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/auth_middleware.dart), [`bin/server.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart), [`lib/db/database.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/db/database.dart#L83-L90)
- **Kod İncelemesi:**
  - `device_audit_logs` tablosuna yazılan kayıtlarda `details` sütunu yalnızca `"Cihaz başarıyla kaydedildi."`, `"Token başarıyla yenilendi."` ve `"İptal nedeni: ..."` ifadelerini içerir. Token veya hash yazılmaz.
  - `auth_middleware` hata mesajlarında yalnızca `{ "error": "DEVICE_NOT_FOUND", ... }` gibi standart JSON döndürülür; istemcinin yolladığı token asla yanıta geri yansıtılmaz.
  - Test 17 (`test/s2_token_security_test.dart`) yanıt gövdelerinde token veya pepper metninin geçmediğini kanıtlamıştır.
  - **Sınıflandırma:** **VERIFIED**

---

### Madde 10: SQLite Şema ve Migration Durumu
- **İncelenen Dosyalar:** [`lib/db/database.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/db/database.dart#L66-L80)
- **Kod İncelemesi:**
  - `Devices` tablosundan `token` sütunu kaldırılmıştır. `s2_token_security_test.dart` Test 4, SQLite tablosunu doğrudan ham SQL ile sorgulayarak `token` sütununun mevcut olmadığını ve hiçbir hücrede açık token bulunmadığını doğrulamıştır.
  - **Mimari Not:** Spike aşamasında veritabanı her testte sıfırdan oluşturulduğundan `schemaVersion = 1` korunmuştur. Eski bir SQLite dosyasındaki açık token sütununu yeni şemaya taşıyan bir `onUpgrade` migration kodu yazılmamıştır. Proje Faz 1'e geçtiğinde bu şema geçişi resmi migration olarak yazılmalıdır.
  - **Sınıflandırma:** **PARTIALLY VERIFIED**

---

### Madde 11: Yeniden Başlama ve Pepper Kurtarma
- **İncelenen Dosyalar:** [`test/s2_token_security_test.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/test/s2_token_security_test.dart#L495-L545), [`test/process_crash_test.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/test/process_crash_test.dart)
- **Kod İncelemesi:**
  - Sunucu durdurulup yeniden başlatıldığında (`test 20`), aynı veritabanı dosyası ve aynı DPAPI pepper dosyası kullanılarak önceden oluşturulmuş token başarıyla doğrulanmış ve 201 Created ile satış tamamlanmıştır.
  - `process_crash_test.dart` ve `shutdown_regression_test.dart` paketlerinde de süreç kapatılıp açıldıktan sonra token doğrulamasının kesintisiz çalıştığı tescil edilmiştir.
  - **Sınıflandırma:** **VERIFIED**

---

## 4. Şartlı Onay Gerekçeleri ve Sonraki Aşama Gereksinimleri

Aşama S-2, hedeflenen token güvenliği ve kriptografik standartları başarıyla karşılamıştır. Ancak üretim ortamı öncesinde aşağıdaki 3 şartın sonraki aşamalarda yerine getirilmesi zorunludur:

1. **Aşama S-3 Şartı (LAN TLS / HTTPS):**
   - Şu anda `POST /api/v1/devices/revoke` ve `POST /api/v1/devices/renew-token` HTTP üzerinden çalışmaktadır. LAN dinleyicilerinin (network sniffer) Bearer token veya `X-Admin-Secret` değerini ele geçirmesini önlemek için Aşama S-3'te TLS 1.3 HTTPS şifrelemesi ve sertifika pinleme eksiksiz uygulanmalıdır.
2. **Aşama S-4 Şartı (NTFS ACL & LocalService):**
   - `pepper.dpapi` dosyası ve `spike_master.db` veritabanı dosyasının işletim sistemi düzeyindeki okuma/yazma izinleri, `icacls` kullanılarak yalnızca yetkili servis hesabına (`LocalService` / `Administrators`) tahsis edilmelidir.
3. **Cihaz Kayıt Güvenliği Şartı (Pairing Mode):**
   - İlk kurulumda (bootstrap) ve yeni cihaz eklemede, normal kasiyer token'larının cihaz kaydetmesini önlemek için Master Hub üzerinde fiziksel bir "Eşleştirme Modu" (Pairing Mode) veya "Geçici PIN / Admin Onayı" mekanizması devreye alınmalıdır.

---

## 5. Sonuç

Aşama S-2: Device Token Security, SPIKE-01 prototipi için **APPROVED WITH CONDITIONS** statüsünde onaylanmıştır. Proje, plana uygun olarak **Aşama S-3: LAN TLS Security** çalışmalarına başlamaya hazırdır.

