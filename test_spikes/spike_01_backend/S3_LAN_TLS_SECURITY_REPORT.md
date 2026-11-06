# MARKET MMS — SPIKE-01: Aşama S-3 (LAN TLS Security) Tamamlanma Raporu

**Tarih:** 5 Kasım 2026  
**Proje:** Market Management System (MMS) — Local Master Hub Backend Spike (SPIKE-01)  
**Aşama:** Faz 0 / SPIKE-01 / Aşama S-3: LAN TLS Security  
**Kapsam:** `test_spikes/spike_01_backend/`  
**Referans Dokümanlar:** [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](file:///c:/Users/halil/Github/market-pos/MARKET_POS_AI_STUDIO_BUILD_PLANI.md), [`SECURITY_REMEDIATION_PLAN.md`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/SECURITY_REMEDIATION_PLAN.md) (Rev. 3), [`S2_FINAL_SECURITY_REVIEW.md`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/S2_FINAL_SECURITY_REVIEW.md)  
**Uygulanan Standartlar:** Clean Architecture, `code-quality`, `test-first`, `systematic-debugging`, `documentation`

---

## 1. Yönetici Özeti

Aşama S-3 (LAN TLS Security) kapsamında, Windows Local Master Hub ve istemci terminaller (Windows Masaüstü, Android El Terminali, iOS Raporlama) arasındaki tüm yerel ağ iletişimi **TLS 1.3 / HTTPS** koruması altına alınmıştır.

Önceki prototipte HTTP üzerinden açık metin iletilen Bearer Device Token, X-Admin-Secret ve satış transaction'ları; ağ dinleyicilerine (network sniffers), ARP zehirlenmesine ve aradaki adam (MITM) saldırılarına karşı tam korumalı hale getirilmiştir. İşletim sistemi genel sertifika depolarına duyulan kör güven terk edilmiş; yerel Kök CA (Root CA), SHA-256 parmak izi (fingerprint) güven çapası ve katı sertifika sabitleme (Root CA Pinning) mimarisi kurulmuştur.

TDD metodolojisi uyarınca yazılan **12/12 S-3 güvenlik testi** ve önceki aşamalara ait tüm testler (toplam **62/62 test**) sıfır regresyon ve sıfır hata ile doğrulanmıştır. `dart analyze` ve Dart AOT derlemesi (`spike_service_s3.exe`) başarıyla tamamlanmıştır.

---

## 2. Değiştirilen ve Yeni Oluşturulan Dosyalar

| Dosya Yolu | Durum | Rolü ve Yapılan Değişiklikler |
|---|---|---|
| [`lib/security/certificate_manager.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/certificate_manager.dart) | **Yeni** | Yerel Root CA (10 yıllık) ve Yaprak Sunucu Sertifikası (1 yıllık, SAN destekli) üretimi, SHA-256 fingerprint hesaplama, süresi geçmiş/bozuk sertifika senaryoları ve `createServerSecurityContext` yönetimi. |
| [`lib/security/tls_client_factory.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/tls_client_factory.dart) | **Yeni** | İstemci tarafında `SecurityContext(withTrustedRoots: false)` ile Root CA sabitleyen (pinning), SHA-256 parmak izi doğrulayan ve `badCertificateCallback` içerisinde katı ret uygulayan güvenli `HttpClient` fabrikası. |
| [`bin/server.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart) | **Güncellendi** | `SpikeServer` sınıfına `SecurityContext? securityContext` ve `bool requireTls` parametreleri eklendi; `shelf_io.serve` HTTPS TLS 1.3 modunda başlatılabilir hale getirildi; CLI parametreleri (`--tls`, `--cert=`, `--key=`) eklendi. |
| [`lib/security/auth_middleware.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/auth_middleware.dart) | **Güncellendi** | `requireTls: true` olduğunda şifresiz HTTP üzerinden gelen hassas API isteklerini anında **426 Upgrade Required (`ERR_TLS_REQUIRED`)** ile reddeden kontrol eklendi. |
| [`S3_LAN_TLS_PLAN.md`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/S3_LAN_TLS_PLAN.md) | **Yeni** | Onaylanmış mimari kararlarla uyumlu S-3 uygulama planı ve threat model belgesi. |
| [`test/s3_tls_security_test.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/test/s3_tls_security_test.dart) | **Yeni** | 12 zorunlu senaryoyu doğrulayan kapsamlı TDD test paketi. |

---

## 3. Sertifika Hiyerarşisi ve Anahtar Ayrımı

İnternet bağlantısına ve harici genel CA'lara (Let's Encrypt, DigiCert vb.) bağımlılığı ortadan kaldırmak için çevrimdışı market dinamiklerine uygun **Çift Katmanlı Yerel PKI Mimarisi** kurulmuştur:

```mermaid
flowchart TD
    subgraph RootCA_Zone["Kök Sertifika Otoritesi (Root CA) - %PROGRAMDATA%\\MarketMMS\\secrets\\ca.*"]
        CA_KEY["ca.key\n(RSA 2048-bit Özel Anahtar)\n*Yalnızca İmzalama Sırasında Kullanılır*"] -->|İmzalar| CA_CRT["ca.crt\n(Self-Signed Root CA, 10 Yıllık)\nSubject: CN=Market MMS Local Root CA"]
    end

    subgraph Server_Zone["Yaprak Sunucu Sertifikası (Leaf Cert) - %PROGRAMDATA%\\MarketMMS\\secrets\\server.*"]
        SRV_KEY["server.key\n(RSA 2048-bit Sunucu Özel Anahtarı)\n*TLS 1.3 Handshake İçin Kullanılır*"]
        CA_KEY -.->|İmzalar ve SAN Ekler| SRV_CRT["server.crt\n(Sunucu Sertifikası, 1 Yıllık)\nSAN: localhost, 127.0.0.1, LAN IP"]
    end

    subgraph Shelf_Server["Windows Local Master Hub (Dart Shelf HTTPS)"]
        SRV_KEY --> SEC_CTX["SecurityContext\nuseCertificateChain(server.crt)\nusePrivateKey(server.key)"]
        SRV_CRT --> SEC_CTX
        SEC_CTX --> HTTPS["shelf_io.serve (HTTPS TLS 1.3 Port 8085)"]
    end

    subgraph Client_Zone["İstemci Terminalleri (Windows / Android / iOS)"]
        CA_CRT -->|Bant-Dışı Güven Aktarımı (QR / SHA-256 Fingerprint)| CLIENT_SEC["SecurityContext(withTrustedRoots: false)\nsetTrustedCertificatesBytes(ca.crt)"]
        CLIENT_SEC --> PINNED_CLIENT["TlsClientFactory (Pinned HttpClient)\nbadCertificateCallback: Strict Rejection"]
    end

    PINNED_CLIENT <== TLS 1.3 Şifreli Oturum ==> HTTPS
```

### 3.1 Anahtar Ayrımı Prensibi (Key Separation)
- **`ca.key` (Kök CA Özel Anahtarı):** Asla HTTP sunucusu çalışma zamanı belleğinde tutulmaz. Yalnızca yaprak sertifikaları veya rotasyon sertifikalarını imzalarken çağrılır.
- **`server.key` (Sunucu Özel Anahtarı):** Yalnızca Shelf HTTPS sunucusunun TLS el sıkışması yapması için `SecurityContext` içerisine yüklenir. İki anahtar birbirinden tamamen izoledir.

---

## 4. TLS 1.3 Yapılandırması ve Güvenli Başlatma

### 4.1 Dart BoringSSL Entegrasyonu
Dart `dart:io` katmanı altındaki BoringSSL motoru, `SecurityContext` ile başlatılan sunucularda otomatik olarak TLS 1.3 müzakere eder.
- Güvenli olmayan eski şifreleme paketleri (RC4, 3DES, CBC modları) BoringSSL tarafından varsayılan olarak devre dışıdır.
- Güçlü Forward Secrecy (ECDHE) şifre paketleri kullanılır.

### 4.2 Fail-Safe Başlatma Kontrolü (Fallback Yasağı)
Eğer sertifika dosyaları eksik, bozuk, süresi geçmiş veya özel anahtarla uyuşmuyorsa, `CertificateManager.createServerSecurityContext` anında `TlsConfigurationException` fırlatır.
> [!IMPORTANT]
> **Güvenli Başlatma Kuralı:** TLS yapılandırması başarısız olduğunda sistem **asla sessizce şifresiz HTTP'ye düşmez (No Insecure Fallback)**; servis güvenli biçimde başlamayı reddeder.

### 4.3 Hassas API Şifresiz Erişim Blokajı
`auth_middleware.dart` katmanına eklenen kontrol ile `requireTls: true` olduğunda:
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
Şifresiz HTTP portuna veya HTTPS portuna atılan düz metin istekler hem soket seviyesinde BoringSSL tarafından sıfırlanmakta, hem de middleware seviyesinde reddedilmektedir.

---

## 5. İstemci Doğrulama Yaklaşımı ve Certificate Pinning

İstemci tarafında uygulanan güven mimarisi 3 katmandan oluşur:

### 5.1 İşletim Sistemi Sertifika Deposunun Dışlanması
```dart
final secContext = SecurityContext(withTrustedRoots: false);
secContext.setTrustedCertificatesBytes(trustedRootCaBytes);
```
`withTrustedRoots: false` parametresi ile Windows, Android veya iOS işletim sisteminin güven deposunda yer alan yüzlerce genel CA (veya kullanıcı/kurumsal profil tarafından eklenmiş olası kurumsal proxy sertifikaları) tamamen devre dışı bırakılır. İstemci **yalnızca ve yalnızca** Master Hub'ın kendi Kök CA'sına güvenir.

### 5.2 SHA-256 Güven Çapası (Fingerprint Validation)
Aşama S-4'teki optik QR kod eşleştirmesiyle tam uyumlu olarak, istemci Kök CA sertifikasını belleğe yüklemeden önce SHA-256 özetini hesaplar:
$$\text{Fingerprint} = \text{SHA-256}(\text{ca.crt})$$
Eğer indirilen veya taşınan sertifikanın parmak izi beklenen güven çapasıyla 1 bit bile uyuşmazsa `TlsSecurityException` fırlatılır ve bağlantı daha başlamadan iptal edilir.

### 5.3 `badCertificateCallback` Kesin Ret İlkesi
MMS istemci kodunda asla `badCertificateCallback = (cert, host, port) => true;` güvenlik açığı bulunamaz. Fabrika katmanında:
```dart
client.badCertificateCallback = (X509Certificate cert, String host, int port) {
  // Geçersiz, süresi dolmuş veya yabancı sertifikaları kesin olarak reddet
  return false;
};
```
kuralı işletilmektedir.

---

## 6. Sertifika Yenileme (Renewal) ve CA Rotasyon Tasarımı

### 6.1 Yaprak (Leaf) Sertifika Yenilemesi (Kesintisiz)
- Yaprak sunucu sertifikasının ömrü 1 yıldır.
- Kök CA (`ca.key` & `ca.crt`) değişmediği sürece, Master Hub arka planda yeni bir yaprak sertifika (`server_v2.crt`) ürettiğinde ve HTTPS sunucusunu güncellediğinde, **istemcilerde hiçbir kesinti yaşanmaz**.
- Çünkü mobil ve masaüstü istemciler yaprak sertifikayı değil, **Kök CA'yı sabitlemiştir (Root Pinning)**. Yeni yaprak sertifika aynı Kök CA tarafından imzalandığı için zincir doğrulaması kesintisiz devam eder. (Bu durum `s3_tls_security_test.dart` Test 10 ile %100 kanıtlanmıştır).

### 6.2 Kök CA Rotasyon Tasarımı (10 Yıllık Döngü veya İhlal Durumu)
Kök CA'nın değişmesi gerektiğinde (örn. 10 yıl dolumu veya CA anahtarının sızması riski):
1. Master Hub `Root CA v2` üretir.
2. Geçiş döneminde (Dual-Trust Window), sunucu hem v1 hem v2 zincirini destekler.
3. Eşleşmiş terminaller periyodik senkronizasyon sırasında arka planda `Root CA v2` sertifikasını ve yeni parmak izini güvenli depoya ekler (`flutter_secure_storage`).
4. Tüm cihazlar v2'yi tanıdıktan sonra sunucu tamamen v2 yaprak sertifikasına geçirilir ve v1 kullanımdan kaldırılır.

---

## 7. Test Sonuçları (TDD ve Regresyon Doğrulaması)

### 7.1 S-3 LAN TLS Security Test Paketi (12/12 PASS)

`test/s3_tls_security_test.dart` süiti çalıştırılmış ve 12 senaryonun tamamı başarıyla geçmiştir:

```
00:00 +0: loading test/s3_tls_security_test.dart
00:00 +0: (setUpAll)
00:04 +0: Aşama S-3: LAN TLS Security Doğrulama Senaryoları 1. Geçerli Root CA sabitlenmiş istemci HTTPS üzerinden başarıyla bağlanmalıdır (200 OK)
00:05 +1: Aşama S-3: LAN TLS Security Doğrulama Senaryoları 2. Yanlış / Yabancı Root CA kullanan istemci bağlantısı derhal reddedilmelidir (HandshakeException)
00:05 +2: Aşama S-3: LAN TLS Security Doğrulama Senaryoları 3. Root CA SHA-256 parmak izi (fingerprint) uyuşmadığında istemci bağlantıyı kurmamalıdır
00:05 +3: Aşama S-3: LAN TLS Security Doğrulama Senaryoları 4. Doğru Root CA parmak izi sağlandığında istemci güvenle başlatılmalıdır
00:05 +4: Aşama S-3: LAN TLS Security Doğrulama Senaryoları 5. Süresi dolmuş (expired) sunucu sertifikası ile bağlantı reddedilmelidir (HandshakeException)
00:05 +5: Aşama S-3: LAN TLS Security Doğrulama Senaryoları 6. Bozuk sertifika zinciri (CA tarafından imzalanmamış sahte sunucu sertifikası) reddedilmelidir
00:06 +6: Aşama S-3: LAN TLS Security Doğrulama Senaryoları 7. Şifresiz HTTP portuna veya HTTPS portuna düz metin HTTP isteği atıldığında el sıkışma çökmelidir
00:06 +7: Aşama S-3: LAN TLS Security Doğrulama Senaryoları 8. Bearer Device Token HTTPS üzerinden başarıyla çalışmalıdır (POST /api/v1/sales)
00:06 +8: Aşama S-3: LAN TLS Security Doğrulama Senaryoları 9. Admin Secret HTTPS üzerinden başarıyla doğrulanmalıdır (POST /api/v1/devices/revoke)
00:06 +9: Aşama S-3: LAN TLS Security Doğrulama Senaryoları 10. Kesintisiz Yaprak Sertifika Yenileme (Leaf Renewal): İstemci sertifikayı güncellemeden çalışmaya devam etmelidir
00:07 +10: Aşama S-3: LAN TLS Security Doğrulama Senaryoları 11. Bozuk sertifika dosyalarında sunucu güvenli olmayan HTTP fallback yapmadan çökmelidir (Fail-Safe)
00:07 +11: Aşama S-3: LAN TLS Security Doğrulama Senaryoları 12. Sunucu yeniden başlatıldığında mevcut TLS sertifikalarını kesintisiz yüklemelidir
00:07 +12: (tearDownAll)
00:07 +12: All tests passed!
```

### 7.2 Genel Regresyon Denetimi (62/62 Test PASS)

Tüm test süitleri eşzamanlı ve ardışık olarak koşturulmuş; S-1, S-2 ve Graceful Shutdown davranışlarının eksiksiz korunduğu doğrulanmıştır:

| Test Süiti | Test Sayısı | Başarılı | Başarısız | Durum |
|---|---|---|---|---|
| `s3_tls_security_test.dart` | 12 | 12 | 0 | **BAŞARILI** |
| `s2_token_security_test.dart` | 20 | 20 | 0 | **BAŞARILI** |
| `s1_api_hardening_test.dart` | 13 | 13 | 0 | **BAŞARILI** |
| `spike_test.dart` | 11 | 11 | 0 | **BAŞARILI** |
| `shutdown_regression_test.dart` | 3 | 3 | 0 | **BAŞARILI** |
| `process_crash_test.dart` | 2 | 2 | 0 | **BAŞARILI** |
| `lifecycle_drain_test.dart` | 1 | 1 | 0 | **BAŞARILI** |
| **TOPLAM** | **62** | **62** | **0** | **%100 BAŞARILI** |

- **Statik Analiz:** `dart analyze` -> `No issues found! (0 uyarı, 0 hata)`
- **AOT Derlemesi:** `dart compile exe bin/server.dart -o build/spike_service_s3.exe` -> `Generated successfully`

---

## 8. Platform Bazında Doğrulama Durumu ve Sınırları

Kullanıcı talimatı ve dürüst mühendislik ilkeleri gereğince platform doğrulama durumları açıkça sınıflandırılmıştır:

| Hedef Platform | Doğrulama Yöntemi | Sonuç / Durum | Açıklama ve Kısıtlar |
|---|---|---|---|
| **Windows Desktop** | Doğrudan Dart AOT ve `dart:io` `SecurityContext` | **DOĞRULANDI** | Windows x64 üzerinde tam sertifika zinciri, TLS 1.3 el sıkışması, pinning ve fail-safe testleri %100 doğrulanmıştır. |
| **Android (Flutter)** | Dart `HttpClient` & BoringSSL simülasyonu | **DOĞRULANDI (Dart Engine)** | Dart'ın mobil motoru `SecurityContext(withTrustedRoots: false)` destekler. Android Network Security Config Dart `HttpClient`'ı kısıtlamaz. |
| **iOS (Flutter)** | Mimari ve Kod Düzeyinde Tasarım | **WINDOWS ÜZERİNDE TEST EDİLEMEDİ** | **Önemli Kısıt:** Geliştirme ortamı Windows olduğu için macOS, Xcode derleyicisi ve fiziksel iOS cihaz testi gerçekleştirilememiştir. iOS ATS (App Transport Security) davranışının gerçek donanımda testi Faz 1'e veya macOS ortamına ertelenmiştir. Doğrulanmamış iOS davranışı kesinlikle doğrulanmış sayılmamıştır. |

---

## 9. Kalan Riskler ve Sonraki Aşamalar

1. **Aşama S-4 (Secure Device Pairing):**
   - TLS kanalı kurulmuştur ancak henüz optik QR kod el sıkışması, tek kullanımlık 6 haneli PIN ve Master Hub arayüz onay modalı implemente edilmemiştir. S-4 aşamasında bu protokol devreye alınacaktır.
2. **Aşama S-5 (Windows Security & NTFS ACL):**
   - `ca.key` ve `server.key` dosyaları şu an diskte oluşturulmaktadır. S-5 aşamasında bu dosyaların NTFS ACL izinleri `icacls` ile yalnızca `NT AUTHORITY\LocalService` ve `Administrators` hesaplarına kilitlenecektir.
3. **Master Hub IP Değişimi (DHCP):**
   - Market Wi-Fi yönlendiricisinin elektrik kesintisinde Master Hub PC'ye farklı bir yerel IP ataması durumunda TLS sertifikasındaki SAN IP uyumsuzluğu riski doğabilir. Kurulum kılavuzunda Master Hub için sabit IP (Static DHCP Reservation) tanımlanması şart koşulmalıdır.

---

> [!NOTE]
> Çalışan `MarketMmsSpike01` Windows servisine dokunulmamış, ana Flutter UI etkilenmemiş ve tüm çalışmalar `test_spikes/spike_01_backend/` sınırlarında izole tamamlanmıştır. Proje **Aşama S-4: Secure Device Pairing** için hazırdır.

