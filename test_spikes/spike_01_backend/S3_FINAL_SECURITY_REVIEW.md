# MARKET MMS — SPIKE-01: Aşama S-3 (LAN TLS Security) Nihai Güvenlik Denetim Raporu

**Tarih:** 5 Kasım 2026  
**Denetçi:** Baş Güvenlik ve Mimarlık Mühendisi (Antigravity AI)  
**Proje:** Market Management System (MMS) — Local Master Hub Backend Spike (SPIKE-01)  
**Aşama:** Faz 0 / SPIKE-01 / Aşama S-3: LAN TLS Security  
**Kapsam:** `test_spikes/spike_01_backend/`  
**Denetim Türü:** Salt Okunur Güvenlik Denetimi (Read-Only Security Audit)  
**Referans Dokümanlar:**
- [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](../../MARKET_POS_AI_STUDIO_BUILD_PLANI.md) (v1.2)
- [`SECURITY_REMEDIATION_PLAN.md`](./SECURITY_REMEDIATION_PLAN.md) (Rev. 3)
- [`S3_LAN_TLS_PLAN.md`](./S3_LAN_TLS_PLAN.md)
- [`S3_LAN_TLS_SECURITY_REPORT.md`](./S3_LAN_TLS_SECURITY_REPORT.md)
- [`S2_FINAL_SECURITY_REVIEW.md`](./S2_FINAL_SECURITY_REVIEW.md)
**İncelenen Kod Dosyaları:**
- [`lib/security/certificate_manager.dart`](./lib/security/certificate_manager.dart)
- [`lib/security/tls_client_factory.dart`](./lib/security/tls_client_factory.dart)
- [`lib/security/auth_middleware.dart`](./lib/security/auth_middleware.dart)
- [`bin/server.dart`](./bin/server.dart)
- [`test/s3_tls_security_test.dart`](./test/s3_tls_security_test.dart)

---

## 1. Yönetici Özeti ve Nihai Karar

Aşama S-3 (LAN TLS Security) kapsamında gerçekleştirilen teknik implementasyon ve test paketleri titizlikle incelenmiştir. Yapılan denetimde; yerel Kök CA (Root CA) hiyerarşisi, RSA 2048-bit yaprak sunucu sertifikaları, SAN (Subject Alternative Name) desteği, SHA-256 fingerprint güven çapası, istemci Kök CA sabitlemesi (`withTrustedRoots: false`), fail-safe başlatma kontrolleri ve kesintisiz yaprak sertifika yenileme mimarisinin başarılı bir şekilde kurulduğu tespit edilmiştir.

Bununla birlikte, ağ güvenliği katmanında ve protokol düzeyinde **iki kritik mimari bulgu** saptanmıştır:
1. **Şifresiz HTTP Üzerinden Başlık Sızıntısı (Ağ Seviyesi Riski):** `auth_middleware.dart` katmanında bulunan `426 Upgrade Required (ERR_TLS_REQUIRED)` yanıtı uygulama katmanında üretilmektedir. Bir istemci şifresiz HTTP portuna istek attığında, `Authorization: Bearer <token>` veya `X-Admin-Secret` başlıkları HTTP sunucusu tarafından okunmadan önce yerel ağ kablosu ve Wi-Fi ortamında açık metin olarak iletilmiş olur. 426 kontrolü bir ağ dinleyicisine (sniffer) karşı koruma sağlamaz.
2. **TLS 1.2 / TLS 1.3 Protokol Müzakeresi:** Dart `dart:io` katmanının BoringSSL motoru TLS 1.3'ü öncelikli desteklemekle birlikte, güçlü AEAD şifre paketleriyle TLS 1.2 bağlantılarını da kabul etmektedir. Dart SDK'da TLS 1.2'yi tamamen devre dışı bırakan bir API mevcut değildir.

### Nihai Denetim Kararı

> [!IMPORTANT]
> **NİHAİ KARAR: APPROVED WITH CONDITIONS (ŞARTLI ONAYLANDI)**  
> Aşama S-3 mimari tasarımı ve kod kalitesi genel hatlarıyla onaylanmıştır. Ancak Aşama S-4 ve Aşama S-5'e geçilmeden önce, **LAN üzerinde şifresiz HTTP dinleyicisinin tamamen kapatılması** ve istemcilerin yalnızca güvenli TLS portuna bağlanması şart koşulmuştur.

---

## 2. Kritik Güvenlik Analizi: Şifresiz HTTP ve 426 Öncesi Başlık Sızıntısı

Uygulama kodunda (`auth_middleware.dart` satır 39-49) şu mekanizma bulunmaktadır:
```dart
if (requireTls && request.requestedUri.scheme != 'https') {
  return Response(
    426,
    body: jsonEncode({
      'error': 'UPGRADE_REQUIRED',
      'code': 'ERR_TLS_REQUIRED',
      'message': 'Hassas API ve kimlik doğrulama işlemleri yalnızca TLS 1.3 / HTTPS üzerinden kabul edilir.',
    }),
    headers: {'content-type': 'application/json'},
  );
}
```

### 2.1 Ağ Protokolü Gerçeği
- Bir istemci (örneğin Android el terminali veya Windows masaüstü) yanlışlıkla veya kötü niyetli bir yönlendirme sonucu `http://192.168.1.100:8080/api/v1/sales` adresine `POST` isteği gönderdiğinde; HTTP protokolünün doğası gereği istek satırı, URI ve tüm HTTP başlıkları (`Authorization: Bearer <token>`, `X-Admin-Secret: <secret>`) TCP soketi üzerinden **açık metin (cleartext)** olarak ağ ortamına gönderilir.
- Dart Shelf sunucusu TCP paketlerini alıp HTTP isteğini parse ettikten sonra `request.requestedUri.scheme != 'https'` koşulunu çalıştırır ve 426 döner.
- **Sonuç:** Sunucu 426 ile isteği reddetmiş olsa dahi, cihaz token'ı veya admin secret LAN üzerindeki bir ARP zehirleme (ARP spoofing) veya Wi-Fi dinleme aracı tarafından **çoktan yakalanmış (sniffed)** durumdadır!

### 2.2 Çözüm ve Mimari Kural
- HTTP uygulama katmanındaki `426 Upgrade Required` kontrolü, ağ seviyesindeki veri sızıntısını engelleyemez.
- **Kural:** Master Hub üretim ortamında LAN ağ kartı (`0.0.0.0`) üzerinde **asla şifresiz bir HTTP dinleyici açmamalıdır**.
- Sunucu yalnızca `SecurityContext` ile sarmalanmış TLS soketini (`https://0.0.0.0:8085`) dinlemelidir. TLS soketine düz HTTP ile bağlanan istemciler TLS el sıkışma aşamasında (`ClientHello`) soket hatası alır ve hiçbir HTTP başlığı ağ kablosuna/havaya dökülemez.

---

## 3. 12 Kritik Denetim Maddesinin Ayrıntılı Değerlendirmesi

### Madde 1: HTTP listener LAN üzerinden erişilebilir mi?
- **Durum:** `VERIFIED`
- **İnceleme:** `bin/server.dart` dosyasındaki `SpikeServer.start()` metodu incelendiğinde, `shelf_io.serve` çağrısına `securityContext: securityContext` parametresi verildiğinde sunucunun yalnızca tek bir TLS soketi açtığı görülmüştür. TLS aktifken sunucu ek bir şifresiz HTTP portu dinlememektedir. İstemciler aynı porta düz HTTP ile bağlandığında el sıkışma soket seviyesinde çökmektedir (Bkz. `s3_tls_security_test.dart` Test 7).
- **Not:** CLI parametrelerinde `--tls` verilmediğinde sunucu şifresiz HTTP modunda açılabilmektedir; ancak TLS etkinleştirildiğinde LAN'da açık bir HTTP dinleyici kalmamaktadır.

### Madde 2: HTTP üzerinden Bearer Token veya X-Admin-Secret gönderilmesi teknik olarak engelleniyor mu?
- **Durum:** `PARTIALLY VERIFIED`
- **İnceleme:** HTTPS soketi üzerinde TLS şifrelemesi çalıştığı için açık metin gönderimi teknik olarak engellenmektedir. Ancak sunucunun şifresiz HTTP modunda açıldığı veya ilave bir HTTP yönlendirme portunun açık tutulduğu senaryolarda; `auth_middleware.dart` içerisindeki 426 kontrolü ağ seviyesinde başlık aktarımını engelleyememektedir. İstemci isteği yolladığı anda başlıklar kablodan geçmiş olur.

### Madde 3: HTTP isteğine 426 dönülmesi öncesinde hassas header'ların ağ üzerinden açık iletilmesi riski var mı?
- **Durum:** `VULNERABLE` (Mimari Değerlendirme / Ağ Katmanı Gerçeği)
- **İnceleme:** Evet, bu risk HTTP/1.1 mimarisi gereği mevcuttur. İstemci şifresiz HTTP kullandığı anda, sunucu 426 dönene kadar `Authorization` veya `X-Admin-Secret` başlıkları LAN üzerinde açık iletilir. Bu nedenle 426 yanıtına birincil güvenlik kalkanı olarak güvenilemez. Tek geçerli çözüm, LAN'da şifresiz dinleyiciyi tamamen kapatmaktır.

### Madde 4: Tercih edilen çözüm HTTP listener'ı LAN'da tamamen kapatmak mı, yoksa yalnızca hassas veri içermeyen yönlendirme endpoint'i sunmak mı?
- **Durum:** `VERIFIED`
- **İnceleme:** Yapılan mimari analiz sonucunda; **LAN üzerinde HTTP dinleyicisinin tamamen kapatılması** ve yalnızca HTTPS portunun (`0.0.0.0:8085`) açık tutulması en güvenli çözüm olarak belirlenmiştir. İstemciler sunucu adresini Aşama S-4 kapsamında optik QR kod üzerinden `https://<ip>:<port>` olarak alacağından, şifresiz bir HTTP yönlendiricisine dahi ihtiyaç bulunmamaktadır. Windows masaüstü loopback UI için gerekirse yalnızca `127.0.0.1` adresine kilitli yerel HTTP kanalı açılabilir, bu kanal asla LAN'a açılmamalıdır.

### Madde 5: TLS gerçekten yalnızca TLS 1.3 kabul ediyor mu? TLS 1.2 bağlantısı ayrıca denenmiş mi?
- **Durum:** `PARTIALLY VERIFIED`
- **İnceleme:** OpenSSL 3.2.4 `s_client` ve Dart testleriyle yapılan prototip doğrulamalarında:
  - `-tls1_3` parametresi ile yapılan bağlantıda `TLS_CHACHA20_POLY1305_SHA256` şifresiyle TLS 1.3 başarıyla müzakere edilmiştir.
  - `-tls1_2` parametresi ile yapılan bağlantı zorlamasında Dart BoringSSL motorunun `ECDHE-RSA-AES256-GCM-SHA384` AEAD şifresiyle TLS 1.2 bağlantısını da kabul ettiği tespit edilmiştir.
  - Eski ve zayıf protokoller (SSLv3, TLS 1.0, TLS 1.1) reddedilmektedir.
  - Dart `SecurityContext` API'si TLS 1.2'yi tamamen devre dışı bırakacak bir protokol versiyonu filtresi (`minVersion / maxVersion`) sunmamaktadır. Dolayısıyla sistem TLS 1.3'ü önceliklendirmekte ancak güçlü TLS 1.2 bağlantılarını da kabul etmektedir.

### Madde 6: Root CA fingerprint doğrulaması gerçek sertifika üzerinden mi yapılıyor?
- **Durum:** `VERIFIED`
- **İnceleme:** `tls_client_factory.dart` (satır 19-31) ve `certificate_manager.dart` (satır 219-228) incelenmiştir. Kök CA sertifikasının ham bayt dizisi (`trustedRootCaBytes`) doğrudan `crypto.sha256` fonksiyonuna verilmekte ve elde edilen hash beklenen güven çapasıyla karşılaştırılmaktadır. Parmak izi eşleşmediğinde soket açılmadan `TlsSecurityException` fırlatıldığı `s3_tls_security_test.dart` Test 3 ile doğrulanmıştır.

### Madde 7: Sertifika hostname/IP SAN doğrulaması çalışıyor mu?
- **Durum:** `VERIFIED`
- **İnceleme:** `certificate_manager.dart` (satır 102-125), `sanList` içerisindeki IP adreslerini `IP:x.x.x.x` ve alan adlarını `DNS:hostname` formatına dönüştürerek OpenSSL `-addext subjectAltName=...` ve imzalama sırasında `-copy_extensions copy` ile yaprak sertifikaya işlemektedir. Dart `HttpClient` hedef URI adresini bu SAN girdileriyle eşleştirmektedir; uyuşmayan IP/alan adları `badCertificateCallback` tarafından anında reddedilmektedir.

### Madde 8: Yanlış CA, süresi dolmuş sertifika ve değiştirilmiş sertifika reddediliyor mu?
- **Durum:** `VERIFIED`
- **İnceleme:** `s3_tls_security_test.dart` test süiti altında:
  - Test 2: Saldırgan sahte Kök CA ile imzalanmış sunucu sertifikası meşru istemci tarafından `HandshakeException` ile reddedilmiştir.
  - Test 5: Süresi dolmuş (`-days -1`) sertifika `HandshakeException` ile reddedilmiştir.
  - Test 6: Bozuk zincir reddedilmiştir.
  - `tls_client_factory.dart` içerisindeki `client.badCertificateCallback` fonksiyonu koşulsuz olarak `return false;` dönmekte, geçersiz hiçbir sertifikaya bypass izni vermemektedir.

### Madde 9: Root CA private key bellekten ve diskten nasıl korunuyor?
- **Durum:** `PARTIALLY VERIFIED`
- **İnceleme:**
  - **Bellek Koruması:** `CertificateManager.createServerSecurityContext` yalnızca `server.crt` ve `server.key` dosyalarını yüklemektedir. `ca.key` sunucu çalışma zamanı belleğinde tutulmamakta, yalnızca yaprak sertifika üretimi sırasında harici OpenSSL alt sürecine parametre olarak iletilmektedir. Bu yönüyle anahtar ayrımı tamdır.
  - **Disk Koruması:** Disk üzerindeki `ca.key` dosyası şu an dosya sisteminde bulunmaktadır. Bu dosyanın NTFS ACL izinleriyle yalnızca `LocalService` ve `Administrators` hesaplarına kilitlenmesi mimari plana uygun olarak **Aşama S-5** kapsamına bırakılmıştır.

### Madde 10: TLS konfigürasyonu başarısız olduğunda açık HTTP'ye düşme riski var mı?
- **Durum:** `VERIFIED`
- **İnceleme:** `certificate_manager.dart` içerisindeki `createServerSecurityContext` fonksiyonu sertifika veya özel anahtar dosyalarının bulunamaması, boş olması veya bozuk olması durumunda `TlsConfigurationException` fırlatmaktadır. `bin/server.dart` bu hatayı yakalayıp sessizce HTTP'ye düşmemekte, süreç derhal sonlanmaktadır (Fail-Safe prensibi). Bu durum `s3_tls_security_test.dart` Test 11 ile test edilmiştir.

### Madde 11: Leaf sertifika yenilendiğinde istemciler kesintisiz güven doğrulayabiliyor mu?
- **Durum:** `VERIFIED`
- **İnceleme:** İstemci tarafında `TlsClientFactory.createPinnedClient`, yaprak sertifikanın kendisini değil, yerel Kök CA'yı sabitlemektedir (`secContext.setTrustedCertificatesBytes(trustedRootCaBytes)`). Sunucu yaprak sertifikası 1 yıl sonra aynı Kök CA tarafından imzalanarak yenilendiğinde istemcilerde hiçbir sertifika güncellemesi gerekmemektedir. Bu durum `s3_tls_security_test.dart` Test 10 (`server_v2.crt`) ile fiilen kanıtlanmıştır.

### Madde 12: S-1 ve S-2 mekanizmaları korundu mu?
- **Durum:** `VERIFIED`
- **İnceleme:** Tüm test süitleri koşturulmuş ve toplam **62/62 testin** başarıyla geçtiği doğrulanmıştır:
  - S-1 Korumaları: Backup path traversal koruması, mikrosaniye+kriptografik nonce ile çakışmasız dosya adı üretimi, admin shutdown loopback ve admin secret doğrulaması korunmuştur.
  - S-2 Korumaları: DPAPI pepper yönetimi, SHA-256 + salt + pepper token doğrulaması korunmuştur.
  - S-3 TLS testleri altında Bearer Token (Test 8) ve Admin Secret (Test 9) doğrulamalarının HTTPS üzerinden de eksiksiz çalıştığı teyit edilmiştir.

---

## 4. Denetim Özeti ve Sınıflandırma Tablosu

| No | Denetim Maddesi | Güvenlik Durumu | Açıklama ve Tespit |
|:--:|---|:---:|---|
| **1** | HTTP listener LAN üzerinden erişilebilir mi? | **VERIFIED** | TLS aktifken sunucu yalnızca HTTPS soketi açmaktadır; LAN üzerinde açıkta kalan ayrı bir HTTP dinleyicisi yoktur. |
| **2** | HTTP üzerinden token / admin secret gönderimi engelleniyor mu? | **PARTIALLY VERIFIED** | HTTPS soketi korur; ancak şifresiz HTTP portu açılırsa 426 yanıtı ağ kablosundaki veri sızıntısını engelleyemez. |
| **3** | HTTP 426 öncesi açık başlık sızıntısı riski | **VULNERABLE** | Mimari Risk: HTTP başlıkları TCP üzerinden sunucuya ulaştıktan sonra 426 üretildiği için ağ dinleyicilerine karşı 426 koruma sağlamaz. |
| **4** | Tercih edilen LAN mimarisi | **VERIFIED** | LAN üzerinde açık HTTP portunun tamamen kapatılması ve yalnızca TLS portunun dinlenmesi en güvenli çözümdür. |
| **5** | TLS 1.3 / TLS 1.2 protokol müzakeresi | **PARTIALLY VERIFIED** | TLS 1.3 önceliklidir ancak BoringSSL güçlü AEAD şifreleriyle TLS 1.2'yi de kabul etmektedir (Dart SDK kısıtı). |
| **6** | Root CA fingerprint doğrulaması | **VERIFIED** | Doğrudan ham sertifika baytları üzerinden SHA-256 hesaplanmakta ve doğrulanmaktadır. |
| **7** | Sertifika hostname/IP SAN doğrulaması | **VERIFIED** | SAN alanları OpenSSL `-addext` ile eklenmekte ve istemci tarafından doğrulanmaktadır. |
| **8** | Yanlış / süresi dolmuş sertifika reddi | **VERIFIED** | `badCertificateCallback` kesin ret vermekte ve hatalı sertifikalar `HandshakeException` ile düşmektedir. |
| **9** | Root CA private key bellek/disk koruması | **PARTIALLY VERIFIED** | Bellekte `ca.key` tutulmamaktadır; disk üzerindeki NTFS ACL izinlerinin kilitlenmesi Aşama S-5 kapsamındadır. |
| **10** | Hata durumunda HTTP fallback riski | **VERIFIED** | Sertifika/anahtar hatasında sunucu süreci çökmekte, kesinlikle sessiz güvensiz HTTP moduna düşmemektedir. |
| **11** | Leaf sertifika yenileme sürekliliği | **VERIFIED** | İstemciler Kök CA'yı sabitlediği (Root Pinning) için yaprak sertifika yenilemelerinde istemciler kesintiye uğramaz. |
| **12** | S-1 ve S-2 mekanizmalarının korunması | **VERIFIED** | DPAPI, token hashing, backup nonce ve admin loopback korumaları korunmuştur (62/62 test başarılı). |

---

## 5. Aşama S-4 ve S-5 İçin Bağlayıcı Şartlar ve Talimatlar

Bu denetim sonucunda Aşama S-4 (Secure Device Pairing) ve Aşama S-5 (Windows Security & LocalService) çalışmalarına başlanabilmesi için aşağıdaki şartlar getirilmiştir:

1. **LAN Üzerinde Şifresiz HTTP Kesinlikle Yasaktır (S-4 Kuralı):**
   Master Hub üretim modunda çalışırken LAN arayüzünde (`0.0.0.0`) şifresiz HTTP portu dinlemeyecektir. Aşama S-4'te oluşturulacak QR kod verisi içerisinde sunucu adresi doğrudan `https://` protokollü olarak yer alacaktır.
2. **Kök CA ve Sunucu Anahtarı NTFS İzinleri (S-5 Kuralı):**
   Aşama S-5'te `ca.key` ve `server.key` dosyalarının NTFS erişim izinleri `icacls` komutu ile kısıtlanmalı; yalnızca `NT AUTHORITY\LocalService` ve `BUILTIN\Administrators` hesaplarına tam yetki verilmeli, diğer tüm kullanıcılara erişim kapatılmalıdır.
3. **Statik LAN IP / DHCP Rezervasyonu Uyarısı:**
   Master Hub PC'nin yerel ağ IP'si değiştiğinde sertifikadaki IP SAN uyuşmazlığı yaşanmaması için kurulum belgelerine router üzerinde "Static DHCP IP Reservation" yapılması gerektiği açıkça eklenmelidir.
4. **iOS Platform Testi (Faz 1 Kuralı):**
   iOS platformunda `SecurityContext(withTrustedRoots: false)` davranışının fiziksel iPhone üzerinde doğrulanması, geliştirme ortamı Windows olduğu için macOS ve Xcode ortamının hazır olacağı Faz 1'e ertelenmiştir. Doğrulanmamış iOS işlevselliği dokümantasyonda "Windows ortamında test edilemedi" olarak kalmaya devam edecektir.

---

## 6. Sonuç

Aşama S-3 LAN TLS Security uygulaması, **şifresiz HTTP üzerinden 426 öncesi veri sızıntısı riskine karşı LAN üzerinde şifresiz dinleyici açılmaması** koşuluyla **ŞARTLI ONAYLANMIŞTIR (APPROVED WITH CONDITIONS)**.

Mevcut prototip; şifreli veri aktarımı, Root CA güven çapası ve kesintisiz sertifika yenileme mimarisini başarıyla sağlamaktadır. Proje, Aşama S-4: Secure Device Pairing (QR Kod & PIN tabanlı Master Hub eşleştirme) adımına geçmeye hazırdır.

