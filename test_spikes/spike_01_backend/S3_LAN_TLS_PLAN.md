# MARKET MMS — SPIKE-01: Aşama S-3 (LAN TLS Security) Uygulama ve Doğrulama Planı

**Tarih:** 5 Kasım 2026  
**Aşama:** Faz 0 / SPIKE-01 / Aşama S-3  
**Hedef Modül:** `test_spikes/spike_01_backend/`  
**Referans Dokümanlar:** `MARKET_POS_AI_STUDIO_BUILD_PLANI.md` (v1.2), `SECURITY_REMEDIATION_PLAN.md` (Rev. 3), `S2_FINAL_SECURITY_REVIEW.md`  
**Uygulanan Standartlar:** Clean Architecture, `code-quality`, `test-first`, `systematic-debugging`, `documentation`

---

## 1. Amaç ve Kapsam

Bu plan; MARKET MMS Windows Local Master Hub prototipinin yerel ağ (LAN) üzerindeki tüm veri ve kimlik doğrulama trafiğini **TLS 1.3 / HTTPS** koruması altına alması için gereken teknik tasarım, sertifika otoritesi (CA) mimarisi, istemci sertifika sabitleme (certificate pinning) ve test senaryolarını belirler.

### 1.1 Kapsam İçi
- Yerel Kök Sertifika Otoritesi (Local Root CA) ve yaprak sunucu sertifikası (Leaf Server Certificate) üretimi ve yönetimi.
- CA özel anahtarı (`ca.key`) ile sunucu özel anahtarının (`server.key`) tam ayrımı.
- Dart Shelf HTTP sunucusunun `SecurityContext` ile TLS 1.3 HTTPS modunda başlatılması.
- Hassas API trafiğinin (`/api/v1/*`, Bearer Token, `X-Admin-Secret`) şifresiz HTTP üzerinden iletilmesinin engellenmesi.
- Dart/Flutter istemcilerinde işletim sistemi sertifika deposuna bağımlı olmayan `SecurityContext(withTrustedRoots: false)` ve SHA-256 fingerprint tabanlı sertifika sabitleme (pinning).
- `badCertificateCallback` içerisinde koşulsuz `true` kullanımının kesin olarak yasaklanması ve katı doğrulama.
- Kesintisiz yaprak sertifika yenileme (Leaf renewal) ve çift güvenli (Dual-Trust) CA rotasyonu tasarımı.
- TDD yaklaşımıyla en az 12 güvenlik doğrulama senaryosunun test edilmesi.

### 1.2 Kapsam Dışı (Sonraki Aşamalara Bırakılanlar)
- Optik QR kod tabanlı dinamik cihaz eşleştirme el sıkışması (Aşama S-4).
- Tek kullanımlık 6 haneli PIN ve oturum yönetimi (Aşama S-4).
- Windows Service `LocalService` hesabı ve `icacls` NTFS izinleri (Aşama S-5).
- Ana MMS Flutter UI arayüz kodları.

---

## 2. Onaylanmış Mimari Kararlarla Karşılaştırma

| Mimari Kriter | Onaylanmış Karar (`ARCHITECTURE.md` & `BUILD_PLANI.md`) | S-3 Tasarımı ve Yaklaşımı | Uyum Durumu |
|---|---|---|---|
| **Local Master Hub Mimarisi** | Windows PC yerel merkezi sunucudur; harici bulut/proxy bağımlılığı yoktur. | Nginx veya IIS gibi harici ters proxy kullanılmaz; doğrudan Dart Shelf `SecurityContext` ile HTTPS sunulur. | **TAM UYUMLU** |
| **Dart AOT & Shelf** | Tek parça, hafif ve bağımsız çalışabilir binary backend. | Ekstra ağır kütüphaneler eklenmez; Dart'ın yerel BoringSSL TLS motoru kullanılır. | **TAM UYUMLU** |
| **Offline-First Bütünlüğü** | İnternet olmasa dahi yerel LAN üzerinde satış ve yönetim çalışır. | Yerel Root CA kullanılır; genel internet sertifika otoritelerine (Let's Encrypt vb.) ihtiyaç duyulmaz. | **TAM UYUMLU** |
| **Fiziksel Güven Çapası (Trust Anchor)** | QR kod ile optik bant-dışı (out-of-band) güven aktarımı. | Root CA SHA-256 fingerprint'i hesaplanır; istemci bağlanmadan önce parmak izini doğrular. | **TAM UYUMLU** |
| **Geriye Dönük Uyumluluk (Loopback)** | Windows yerel masaüstü UI için sıfır gecikmeli loopback desteği. | Loopback trafiğinde isteğe bağlı şifresiz test kanalı korunur; LAN üzerinde ise TLS zorunlu tutulur. | **TAM UYUMLU** |

---

## 3. Sertifika ve Güven Mimarisi (CA Hierarchy)

```
       [ Yerel Root CA ] (Ömür: 10 Yıl, ca.key + ca.crt)
              │
              │ (İmzalama)
              ▼
   [ Yaprak Sunucu Sertifikası ] (Ömür: 1 Yıl, server.key + server.crt)
       SAN: DNS:localhost, IP:127.0.0.1, IP:192.168.1.x
              │
              ├─────────────────────────────────────────┐
              ▼ (TLS 1.3 HTTPS Sunumu)                  ▼ (Bant-Dışı QR / Güven Çapası)
     [ Shelf HTTPS Server ]                   [ SHA-256 Fingerprint ]
              ▲                                         │
              │                                         │
       (TLS 1.3 Handshake)                              ▼
              │                                [ Mobil & Windows İstemci ]
              └───────────────────────────────   SecurityContext(withTrustedRoots: false)
                                                 setTrustedCertificatesBytes(ca.crt)
                                                 badCertificateCallback: Strict Rejection
```

### 3.1 Anahtar Ayrımı
- `ca.key`: Yalnızca yaprak sertifikaları ve rotasyon sertifikalarını imzalamak için kullanılır. Sunucu çalışma zamanında HTTP isteklerini işlerken bu anahtarı belleğe almaz.
- `server.key`: Sunucunun TLS el sıkışmasında kullandığı özel anahtardır.
- Her iki anahtar RSA-2048 veya üzeri standartta üretilir.

### 3.2 İstemci Doğrulama ve Certificate Pinning Stratejisi
1. **İşletim Sistemi Deposu By-pass:** İstemci, `SecurityContext(withTrustedRoots: false)` başlatarak Windows/Android/iOS işletim sistemi sertifika deposundaki bilinmeyen/güvenilmeyen kök sertifikaları reddeder.
2. **Kök CA Sabitleme (Root CA Pinning):** İstemci yalnızca Master Hub'ın kendi Root CA'sını (`ca.crt`) güvenilir kabul eder.
3. **Parmak İzi Doğrulaması:** İstemci, indirdiği kök CA'nın SHA-256 özetini güven çapasıyla karşılaştırır.
4. **Yaprak Sertifika Yenileme Bağımsızlığı:** Sunucu sertifikası 1 yıl sonra yenilendiğinde, aynı Root CA tarafından imzalandığı sürece istemcilerde hiçbir kesinti veya konfigürasyon değişikliği gerekmez.

---

## 4. Platform Bazında İstemci Doğrulama Yaklaşımı

- **Windows Masaüstü:** Dart/Flutter `dart:io` `SecurityContext` yerel BoringSSL üzerinden sorunsuz çalışır.
- **Android:** Dart `HttpClient` doğrudan BoringSSL kullanır. Android OS Network Security Config kuralları Dart'ın özel `SecurityContext`'ini engellemez.
- **iOS:** iOS platformunda ATS (App Transport Security) varsayılan olarak yerel CA'ları kısıtlayabilir; `dart:io` katmanı BoringSSL ile çalıştığından özel root cert kabul edilir. Ancak Windows ortamında Xcode derlemesi ve fiziksel iOS cihaz testi yapılamadığından bu durum raporda açıkça **"Windows üzerinden test edilemedi (Simüle/Kod Düzeyinde)"** olarak belirtilecektir.

---

## 5. TDD Test-First Senaryoları (`test/s3_tls_security_test.dart`)

1. **TC-01: Başarılı TLS 1.3 Bağlantısı:** Geçerli Root CA'yı sabitleyen istemci, HTTPS üzerinden 200 OK yanıtı alır.
2. **TC-02: Yanlış / Yabancı Kök CA Reddi:** Farklı bir CA ile sunulan sertifikaya bağlanan istemci `HandshakeException` ile bağlantıyı anında koparır.
3. **TC-03: Yanlış Parmak İzi (Fingerprint) Reddi:** Güven çapası parmak izi uyuşmadığında istemci bağlantıyı başlatmaz.
4. **TC-04: Süresi Dolmuş (Expired) Sertifika Reddi:** Geçerlilik süresi bitmiş sertifika ile yapılan el sıkışma reddedilir.
5. **TC-05: Bozuk Sertifika Zinciri Reddi:** Sertifika zinciri bozuk veya imza geçersiz olduğunda el sıkışma başarısız olur.
6. **TC-06: Şifresiz HTTP Hassas API Blokajı:** Şifresiz HTTP portuna gelen yetkilendirme (`Bearer` token veya `X-Admin-Secret`) istekleri reddedilir.
7. **TC-07: TLS 1.3 Protokol Denetimi:** Sunucu ve istemci arasındaki bağlantının TLS 1.3 müzakere ettiği doğrulanır.
8. **TC-08: TLS Üzerinden Bearer Token Doğrulaması:** Yetkili kasiyer token'ı HTTPS üzerinden satış işlemini başarıyla tamamlar.
9. **TC-09: TLS Üzerinden Admin Secret Doğrulaması:** Admin secret HTTPS üzerinden güvenle iletilir ve doğrulanır.
10. **TC-10: Kesintisiz Yaprak Sertifika Yenileme (Leaf Renewal):** Sunucu sertifikası yenilendiğinde, Root CA sabitlenmiş istemci kesinti yaşamadan çalışmaya devam eder.
11. **TC-11: Sunucu Yeniden Başlama ve Sertifika Yükleme:** Sunucu yeniden başlatıldığında TLS sertifikalarını sorunsuz yükler.
12. **TC-12: Regresyon Güvencesi:** Önceki 50 testin tamamı (S-1, S-2, crash, drain, shutdown) sıfır kırılma ile çalışmaya devam eder.

---

## 6. Uygulama Adımları

1. **Adım 1:** `lib/security/certificate_manager.dart` sınıfının yazılması (Root CA ve Leaf cert üretimi, SHA-256 fingerprint, SecurityContext oluşturma).
2. **Adım 2:** `lib/security/tls_client_factory.dart` sınıfının yazılması (Katı pinning'li `HttpClient`).
3. **Adım 3:** `test/s3_tls_security_test.dart` test dosyasının TDD RED aşamasında yazılması.
4. **Adım 4:** `bin/server.dart` ve `auth_middleware.dart` sınıflarının HTTPS `SecurityContext` desteği ve TLS zorunluluğu ile güncellenmesi (GREEN aşaması).
5. **Adım 5:** Tüm test paketlerinin koşturulması ve doğrulanması.
6. **Adım 6:** `S3_LAN_TLS_SECURITY_REPORT.md` raporunun oluşturulması.

