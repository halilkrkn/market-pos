# MARKET MMS — SPIKE-01: Aşama S-4 (Secure Device Pairing) Son Doğrulama Denetimi Raporu

**Tarih:** 5 Kasım 2026  
**Denetim Türü:** Salt Okunur Bağımsız Güvenlik ve Kod Doğrulama Denetimi (Zero-Mutation Audit)  
**Denetlenen Kapsam:** `test_spikes/spike_01_backend/`  
**Referans Belgeler:**
- `S4_SECURITY_FIX_REPORT.md` (Güvenlik Düzeltmeleri Uygulama Raporu)
- `S4_FINAL_SECURITY_AUDIT.md` (Önceki Bağımsız Güvenlik Denetimi)
- `S4_DEVICE_PAIRING_PLAN.md` (v1.6 Onaylı Protokol)
- `lib/security/auth_middleware.dart`
- `lib/security/pairing_delivery_buffer.dart`
- `lib/security/pairing_manager.dart`
- `lib/security/ecdsa_signature_validator.dart`
- `lib/security/windows_cng.dart`
- `bin/server.dart`
- `test/s4_crypto_test.dart`
- `test/s4_device_pairing_test.dart`

---

## 1. Denetim Özeti ve Doğrulama Kapsamı

Bu denetim, `S4_SECURITY_FIX_REPORT.md` belgesinde uygulandığı ve kapatıldığı bildirilen güvenlik düzeltmelerini **kaynak kod düzeyinde satır satır, salt okunur olarak ve hiçbir dosya/kod değişikliği yapılmadan** bağımsız biçimde incelemek ve yürütülen test kanıtlarını doğrulamak amacıyla icra edilmiştir.

Yapılan bağımsız incelemede:
1. Kaynak kodda yapıldığı beyan edilen tüm kontrollerin fiilen mevcut olduğu ve doğru mantıkla işletildiği doğrulanmıştır.
2. Hata senaryolarında sistemin "fail-closed" davrandığı kanıtlanmıştır.
3. 9 test dosyasındaki toplam **100 test bloğunun** tamamı hatasız geçmiş (`Exit Code: 0`) ve statik analizde (`dart analyze`) **0 hata / 0 uyarı** alınmıştır.
4. Windows `ncrypt.dll` üzerinden yapılan çağrının makinedeki **gerçek fiziksel TPM 2.0 yongasını (`Microsoft Platform Crypto Provider`)** kullandığı donanımsal çıktıyla doğrulanmıştır.

---

## 2. Madde Madde Güvenlik Bulguları Bağımsız Denetimi

### 2.1. FINDING-1 — Auth Middleware `isConfirmed` Denetimi
- **Doğrulama Sonucu:** **PASS**
- **Dosya ve Satır Numarası:** [`lib/security/auth_middleware.dart:116-128`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/auth_middleware.dart#L116-L128)
- **Teknik Gerekçe:**
  - `auth_middleware.dart` içinde token doğrulaması yapılıp `matchedDevice` bulunduktan hemen sonra satır 116'da `if (!matchedDevice.isConfirmed)` kontrolü işletilmektedir. Cihazın `isConfirmed` bayrağı `false` ise istek `403 Forbidden` ve `ERR_DEVICE_NOT_CONFIRMED` kodu ile derhal sonlandırılmaktadır.
  - Bu kontrol `!matchedDevice.isActive` kontrolünden sonra, token son kullanma tarihi (`expiresAt`) kontrolünden ve `innerHandler` çağrısından önce yer almaktadır. Dolayısıyla, kimlik doğrulaması gerektiren tüm normal API istekleri bu kurala istisnasız tabidir.
  - **Pairing Endpoint'lerinin Durumu:** `bin/server.dart:1054-1068` arasındaki `publicPaths` listesi incelenmiştir. `/api/v1/pairing/*` altındaki tüm rotalar `publicPaths` listesine dahil edildiğinden `auth_middleware` tarafından yanlışlıkla engellenmemektedir. Eşleştirme endpoint'leri kendi ayrık güvenlik mekanizmalarını (admin loopback veya ECDSA imza doğrulaması) kullanmaktadır.
  - **Özel Rotaların Durumu:** `/api/v1/devices/renew-token` rotası `publicPaths` içinde **değildir**; dolayısıyla henüz ACK teyidi almamış bir cihaz token yenileyemez. `/api/v1/devices/revoke` ise cihaz token'ı ile değil, doğrudan Admin Secret ile yetkilendirilen yönetsel bir rotadır.
- **İlgili Test Kanıtı:** `test/s4_device_pairing_test.dart:1318` (**TC-29**): Onaylanmış ancak ACK göndermemiş cihazın `POST /api/v1/sales` isteğinde `403 ERR_DEVICE_NOT_CONFIRMED` aldığı, ACK sonrası `200 OK` ile satış yapabildiği ve iptal sonrası `403 DEVICE_REVOKED` aldığı kanıtlanmıştır.
- **Kalan Risk:** Yok.

---

### 2.2. FINDING-2 — Arka Plan Teslimat Temizleyicisi (Cleanup Timer)
- **Doğrulama Sonucu:** **PASS**
- **Dosya ve Satır Numarası:** [`bin/server.dart:1092-1111`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart#L1092-L1111), [`lib/security/pairing_delivery_buffer.dart:115-153`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/pairing_delivery_buffer.dart#L115-L153)
- **Teknik Gerekçe:**
  - **Tekil Başlatma ve Sızıntı Koruması:** `bin/server.dart` satır 1092'de `_pairingCleanupTimer?.cancel()` çağrıldıktan sonra yeni `Timer.periodic` oluşturulmaktadır. Sunucu `start()` birden fazla kez çağrılsa dahi mükerrer zamanlayıcı oluşamaz.
  - **Durdurma Kontrolü:** `stop()` metodunda satır 1108'de `_pairingCleanupTimer?.cancel()` çalıştırılmakta ve referans `null` yapılmaktadır.
  - **Yarış Koşulu ve Eşzamanlı ACK Bütünlüğü:** `pairing_delivery_buffer.dart:129-130` satırlarında `final item = _buffer.remove(sessionId);` sonrasında `if (item != null && !item.isAcked)` kontrolü bulunmaktadır. Eğer temizleme döngüsü sırasında istemciden meşru ACK gelip işlendiyse (`item.isAcked = true`), temizleyici o öğeyi atlar ve onaylanmış cihazı yanlışlıkla pasife çekmez.
  - **Sunucu Çökme Koruması (Exception Handling):** `bin/server.dart:1094-1104` satırlarında zamanlayıcı gövdesi `try-catch` bloğuna alınmıştır; temizleme sırasında oluşabilecek beklenmeyen bir hata sunucuyu veya Dart isolate'ini düşüremez (`print('[WARN]...')` ile loglanır).
  - **Startup Reconcile ile Uyum:** `PairingDeliveryBuffer.startupReconcile`, `bin/server.dart:1080`'de HTTP soketi açılmadan ve timer başlatılmadan önce senkron olarak çalışmaktadır. Sunucu kapalıyken yarım kalan yetim cihazlar önce temizlenir; ardından periyodik temizleyici devreye girer. İkisi arasında hiçbir çakışma veya çelişki yoktur.
- **İlgili Test Kanıtı:** `test/s4_device_pairing_test.dart:1504` (**TC-30**): 120 saniyesi dolan cihazın arka planda pasife çekildiği ve eşzamanlı onaylanan cihazın pasife düşürülmediği doğrulanmıştır.
- **Kalan Risk:** Yok.

---

### 2.3. FINDING-3 — Challenge Endpoint'lerinde `pairing_secret` Doğrulaması (DoS Engelleme)
- **Doğrulama Sonucu:** **PASS**
- **Dosya ve Satır Numarası:** [`bin/server.dart:425-437, 517-529`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart#L425-L437), [`lib/security/pairing_manager.dart:352-373, 491-512`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/pairing_manager.dart#L352-L373)
- **Teknik Gerekçe:**
  - **Erken Doğrulama:** `bin/server.dart` içinde hem `/poll-challenge` hem `/ack-challenge` rotalarında `pairing_secret` gövdeden okunmakta; boş veya eksikse `401 Unauthorized` dönülmektedir.
  - **Kota ve Cooldown Korunması:** `pairing_manager.dart:353` ve satır 492'de `session.pairingSecret != pairingSecret` denetimi, `_applyRateLimitAndQuota` çağrısından **ÖNCE** yapılmaktadır. Parola uyuşmadığında `session.challengeCount` artırılmaz ve `session.lastChallengeIssuedAt` güncellenmez. Saldırganın yanlış secret ile istek atarak oturum kotasını (5 hak) tüketmesi veya meşru istemciye 5 saniyelik cooldown dayatması imkânsız kılınmıştır.
  - **Kilitlenme:** 3 hatalı denemeden sonra oturum kilitlenmektedir (`session.status = PairingSessionStatus.locked`).
  - **Paralel İstek Güvenliği:** Dart tek iş parçacıklı olay döngüsü (event loop) modelinde çalıştığından ve `_applyRateLimitAndQuota` senkron bir fonksiyon olduğundan, aynı anda gelen istekler sıralı işlenir; kota kontrolü ile artırımı arasında yarış koşulu oluşamaz.
- **İlgili Test Kanıtı:** `test/s4_device_pairing_test.dart:1568` (**TC-31**): Secret olmadan veya yanlış secret ile challenge istenemediği, 401 alındığı ve 5 challenge kotasının kesinlikle harcanmadığı doğrulanmıştır.
- **Kalan Risk:** Yok.

---

### 2.4. FINDING-4 — Fail-Closed Loopback Denetimi
- **Doğrulama Sonucu:** **PASS**
- **Dosya ve Satır Numarası:** [`bin/server.dart:101-130`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart#L101-L130)
- **Teknik Gerekçe:**
  - **Fail-Closed Mimarisi:** Satır 103'te `if (connectionInfo == null)` kontrolü yer alır. Bağlantı bilgisi alınamadığında istek açık bırakılmaz (`fail-open` hatası giderilmiştir); doğrudan `403 Forbidden` ve `ERR_LOOPBACK_REQUIRED` hatası fırlatılır.
  - **Adres Kapsamı:** Satır 114–120'de `remoteAddr.isLoopback`, IPv4 `127.0.0.1`, IPv6 `::1`, genişletilmiş `0:0:0:0:0:0:0:1` ve IPv4-eşlemeli `::ffff:127.0.0.1` adresleri eksiksiz desteklenmektedir.
  - **LAN Reddi:** Bu adresler haricindeki tüm yerel ağ (LAN) IP'leri (`192.168.x.x`, `10.x.x.x` vb.) satır 121'de `if (!isLoopback)` kontrolüyle `403 Forbidden` almaktadır.
  - **Bütüncül Uygulama:** Yönetici eşleştirme rotalarının tamamı (`/api/v1/pairing/session`, `/api/v1/pairing/requests`, `/api/v1/pairing/approve`, `/api/v1/pairing/reject`) en başta `_verifyLoopbackAndAdmin` çağrısı yapmaktadır.
  - **Sabit Zamanlı Karşılaştırma:** Satır 162'de Admin Secret doğrulaması `_constantTimeEquals` fonksiyonu (XOR akümülatörü) üzerinden yapılarak zamanlama saldırılarına (timing attacks) karşı korunmuştur.
- **İlgili Test Kanıtı:** `test/s4_device_pairing_test.dart:1631` (**TC-32**): `connectionInfo == null` durumunun 403 ile reddedildiği, LAN IP'nin reddedildiği, IPv6 `::1` loopback adresinin kabul edildiği doğrulanmıştır.
- **Kalan Risk:** Yok.

---

### 2.5. FINDING-6 — SPKI ASN.1 P-256 Başlık Katılığı
- **Doğrulama Sonucu:** **PASS**
- **Dosya ve Satır Numarası:** [`lib/security/ecdsa_signature_validator.dart:148-185`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/ecdsa_signature_validator.dart#L148-L185)
- **Teknik Gerekçe:**
  - Satır 148'de standart NIST P-256 SPKI DER 26 baytlık ASN.1 başlığı (`p256SpkiHeader`) tanımlanmıştır:
    - `0x30, 0x59` (SEQUENCE)
    - `0x30, 0x13` (AlgorithmIdentifier)
    - OID `1.2.840.10045.2.1` (`id-ecPublicKey`)
    - OID `1.2.840.10045.3.1.7` (`secp256r1`)
    - `0x03, 0x42, 0x00` (BIT STRING)
  - Satır 167–172'de SPKI boyutu 91 bayt olduğunda ilk 26 baytın `p256SpkiHeader` ile birebir eşleştiği `_listEquals` ile doğrulanmaktadır. Başlık uyuşmadığında veya farklı bir eğri OID'si içerdiğinde `FormatException` fırlatılır.
  - Kalan 65 bayt `_parseUncompressedPoint` fonksiyonuna iletilir. İlk baytın `0x04` olduğu doğrulanır ve koordinatların P-256 eğrisi üzerinde bulunduğu (`isOnCurve`) matematiksel olarak denetlenir.
  - 91 bayt veya 65 bayt dışında kalan tüm girdiler, artık bayt içerenler (92+ bayt) anında `FormatException` ile reddedilir.
  - Katı DER ayrıştırma, Low-S kuralı, P1363 $\leftrightarrow$ DER çift yönlü çevirimi ve tekil SHA-256 prensibi regresyonsuz korunmuştur.
- **İlgili Test Kanıtı:** `test/s4_crypto_test.dart:198-244` (**Test 8**): Geçerli 91 bayt SPKI kabulü, değiştirilmiş OID reddi, bozuk ASN.1 uzunluğu reddi, artık bayt reddi ve eğri dışı nokta reddi %100 başarıyla kanıtlanmıştır.
- **Kalan Risk:** Yok.

---

### 2.6. FINDING-5 — Admin Secret ve Yerel IPC Sınırı (S-5 Şartı)
- **Doğrulama Sonucu:** **PARTIAL / DEFERRED TO S-5 (Mimari Şart Olarak Ayrıldı)**
- **Dosya ve Satır Numarası:** [`bin/server.dart:1133-1135`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart#L1133-L1135), [`S4_SECURITY_FIX_REPORT.md:140-155`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/S4_SECURITY_FIX_REPORT.md#L140-L155)
- **Teknik Gerekçe:**
  - Spike-01 bir backend prototipidir. Admin Secret şu anda `--admin-secret=` argümanından veya `ADMIN_SECRET` çevre değişkeninden okunmaktadır.
  - Windows işletim sisteminde aynı oturumda çalışan standart kullanıcı haklarına sahip zararlı bir süreç, WMI (`Win32_Process`) veya `ProcessCommandLine` üzerinden komut satırı argümanlarını okuyabilir.
  - v1.6 planında ve denetim raporunda açıkça kararlaştırıldığı üzere, bu zafiyetin kalıcı çözümü olan **Windows Named Pipe (`\\.\pipe\MarketMMS_Admin_IPC`) + Win32 DACL ve LocalService hesap yalıtımı**, **Aşama S-5 (Windows Service & Host Hardening)** kapsamına bırakılmıştır.
- **Kalan Risk / Üretim Engeli:** **Bu mekanizma Aşama S-5 tamamlanmadan üretim ortamında kullanılamaz.**

---

### 2.7. FINDING-7 — Dart String İmmutability ve Yönetilen Bellek Sınırı
- **Doğrulama Sonucu:** **INFORMATIONAL (Doğrulandı)**
- **Dosya:** [`lib/security/pairing_delivery_buffer.dart:89, 131`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/pairing_delivery_buffer.dart#L89)
- **Açıklama:**
  - Dart sanal makinesinde `String` nesneleri heap üzerinde immutable olarak tahsis edilir. `rawToken = ''` ataması fiziksel RAM bloklarını üzerine yazarak sıfırlamaz (zeroize yapmaz); nesne referansını temizleyerek Garbage Collector'a terk eder.
  - Raporlama terminolojisinde bu durum "referansın bellek tamponundan silinmesi" olarak doğru ifadeye kavuşturulmuştur.

---

## 3. Test ve Doğrulama Kanıtlarının İncelemesi

### 3.1. Gerçek Test Bloklarının Dağılımı (100 Test Bloğu)

Tüm test dosyalarındaki `test(...)` çağrıları bağımsız PowerShell betiği ile taranarak doğrulanmıştır:

| Test Dosyası | Fiili Test Bloğu | Doğrulanan Kapsam | Durum |
|---|---|---|---|
| `test/lifecycle_drain_test.dart` | 1 | WriteQueue Drain & Graceful Shutdown | **PASSED** |
| `test/process_crash_test.dart` | 2 | 3 Ardışık OS Crash/Recovery Döngüsü | **PASSED** |
| `test/s1_api_hardening_test.dart` | 13 | S-1 API Sertleştirme, Rate Limit, Input Sanitization | **PASSED** |
| `test/s2_token_security_test.dart` | 20 | S-2 PBKDF2/SHA-256, Salt, DPAPI Pepper, Revocation | **PASSED** |
| `test/s3_tls_security_test.dart` | 12 | S-3 TLS 1.3, Root CA Pinning, MITM Reddi | **PASSED** |
| `test/s4_crypto_test.dart` | 8 | S-4 Kriptografi, RFC 6979, Strict DER, Low-S, TPM, SPKI (FINDING-6) | **PASSED** |
| `test/s4_device_pairing_test.dart` | 30 | S-4 TC-01..TC-32 Kabul Kriterleri, Protokol ve Güvenlik Düzeltmeleri | **PASSED** |
| `test/shutdown_regression_test.dart` | 3 | Çoklu Döngü Kapanma Regresyon Testleri | **PASSED** |
| `test/spike_test.dart` | 11 | Eşzamanlı Yük (4 İstemci P50/P95/P99) ve 10 İstemci Stres Testi | **PASSED** |
| **GENEL TOPLAM** | **100** | **Tüm Spike-01 Altyapısı** | **%100 PASSED** |

### 3.2. TC-01 ile TC-32 Kabul Kriterleri Eşleştirme Matrisi

`test/s4_device_pairing_test.dart` dosyasındaki test bloklarının kabul kriteri karşılıkları:

| Kabul Kriteri | Test Bloğu Satırı | Kapsanan Senaryo | Sonuç |
|---|---|---|---|
| **TC-01** | Satır 117 | Geçerli QR / Pairing Session oluşturma (201 Created) | **PASS** |
| **TC-02** | Satır 133 | Süresi dolmuş session ile istek atma (410 Gone) | **PASS** |
| **TC-03** | Satır 157 | Aynı session ile ikinci kez eşleştirme denemesi (409 Conflict) | **PASS** |
| **TC-04** | Satır 195 | Yanlış pairing secret ile istek gönderme (401 Unauthorized) | **PASS** |
| **TC-05** | Satır 215 | 3 yanlış deneme sonrası session kilitlenmeli (403 Forbidden) | **PASS** |
| **TC-06** | Satır 277 | Hub onayı olmadan poll challenge alınamamalı (403 Forbidden) | **PASS** |
| **TC-07 / 08 / 09** | Satır 306 | Sıralı Protokol: Onay, İmzalı Poll ile Token Teslimi, İmzalı ACK ile Bellek Hijyeni | **PASS** |
| **TC-10** | Satır 431 | 120 sn içinde ACK gelmezse tampon temizlenmeli ve cihaz iptal edilmeli | **PASS** |
| **TC-11** | Satır 462 | Loopback dışı IP ile /approve veya /session çağrısı reddedilmeli (403 Forbidden) | **PASS** |
| **TC-12** | Satır 482 | İstemci kendi pairing_secret değeri ile /approve çağıramaz (403 Forbidden) | **PASS** |
| **TC-13** | Satır 496 | Normal kasiyer tokenı ile /approve çağrılamaz (403 Forbidden) | **PASS** |
| **TC-14** | Satır 509 | Eski /api/v1/devices/register rotası 404 dönmeli, yeni cihaz kaydetmemeli | **PASS** |
| **TC-15** | Satır 531 | Aktif bir cihaz IDsi ile tekrar onaylama denenirse 409 Conflict döner | **PASS** |
| **TC-16** | Satır 574 | İptal edilmiş bir cihaz IDsi ile eşleşme denenirse 409 Conflict döner | **PASS** |
| **TC-17** | Satır 616 | Sunucu açılışında isConfirmed: false olan yetim cihazlar otomatik iptal edilmeli | **PASS** |
| **TC-18** | Satır 641 | GET /api/v1/pairing/ca-cert Kök CA sertifikasını dönmelidir | **PASS** |
| **TC-19** | Satır 648 | Audit kayıtlarında açık metin token veya secret bulunmamalıdır | **PASS** |
| **TC-20** | Satır 658 | QR kodunu kopyalayan saldırgan özel anahtara sahip olmadığı için token alamaz | **PASS** |
| **TC-21** | Satır 723 | Çöp/sahte imza ile poll çağrısı 403 ile reddedilmeli | **PASS** |
| **TC-22** | Satır 768 | Onay bekleyen veya onaylanmış oturumda public key değiştirilemez | **PASS** |
| **TC-23** | Satır 803 | Sahte token hash ile imzalanan ACK reddedilmeli (403 Forbidden) | **PASS** |
| **TC-24** | Satır 892 | Kullanılmış challenge nonce ile ikinci kez imza kabul edilmez (409 Conflict) | **PASS** |
| **TC-25** | Satır 958 | Kullanılmış bir ACK challenge ile tekrar teyit gönderilemez (409 Conflict) | **PASS** |
| **TC-26** | Satır 1055 | 3 hatalı imzada challenge kilitlenir; meşru istemci Hub onaysız kurtarır | **PASS** |
| **TC-27** | Satır 1150 | 5 sn dolmadan yeni challenge istenirse 429 Too Many Requests döner | **PASS** |
| **TC-28** | Satır 1189 | S-4 ile eşleştirilmiş cihaz aldığı token ile satış işlemi yapabilmelidir (200 OK) | **PASS** |
| **TC-29** | Satır 1318 | Onaylanmamış cihaz (isConfirmed: false) API kullanamaz (FINDING-1) | **PASS** |
| **TC-30** | Satır 1504 | Periyodik temizleme onaylanmamış süresi dolan cihazları pasifleştirir (FINDING-2) | **PASS** |
| **TC-31** | Satır 1568 | pairing_secret olmadan challenge üretilemez ve kota tüketilmez (FINDING-3) | **PASS** |
| **TC-32** | Satır 1631 | Null connectionInfo ve LAN IP fail-closed ile reddedilir, IPv6 kabul edilir (FINDING-4) | **PASS** |

> *Not:* TC-07, TC-08 ve TC-09 uçtan uca tekil bir protokol adımı olduğundan tek test bloğunda birleştirilmiştir. Toplam 32 kabul kriteri 30 test bloğunda tam kapsama ile doğrulanmaktadır.

### 3.3. Test Çalıştırma ve Çıkış Kodu Kanıtı

Test süiti yürütülmüş ve çıktısı doğrulanmıştır:
```shell
$ cd test_spikes/spike_01_backend; dart test
00:35 +100: All tests passed!
$ echo $LASTEXITCODE
0
```

### 3.4. Statik Kod Analizi Doğrulaması

```shell
$ cd test_spikes/spike_01_backend; dart analyze
Analyzing spike_01_backend...
No issues found!
```

### 3.5. Donanımsal Windows TPM Doğrulaması

Windows işletim sistemi üzerinde `ncrypt.dll` FFI katmanı üzerinden `Microsoft Platform Crypto Provider` çağrılmış, anakart üzerindeki gerçek fiziksel TPM 2.0 yongasında anahtar üretilip imzalanmıştır:
```
================ WINDOWS CNG DOĞRULAMA RAPORU ================
Sağlayıcı: Microsoft Platform Crypto Provider
Donanımsal TPM mi: true
Ham İmza Boyutu: 64 bayt
Hata Mesajı: Yok
===============================================================
```
Üretilen 64 bayt IEEE P1363 çıktısının katı DER formatına çevrilebildiği ve `EcdsaSignatureValidator` motoru tarafından doğrulandığı kanıtlanmıştır.

---

## 4. Kalan Riskler ve Üretim Şartları

1. **FINDING-5 (Admin Secret IPC İzolasyonu - KRİTİK ÜRETİM ENGELİ):**
   - Admin secret'ın CLI parametresi veya environment değişkeni üzerinden aktarılması durumu Spike-01 seviyesinde korunmaktadır. Bu durum geliştirme ortamında kabul edilebilir olmakla birlikte, üretimde aynı makinedeki zararlı süreçler tarafından WMI ile okunabilir.
   - **Şart:** Üretim dağıtımına izin verilmesi için **Aşama S-5 (Windows Service & Host Hardening)** tamamlanmalı, `\\.\pipe\MarketMMS_Admin_IPC` Named Pipe kanalı Win32 DACL ile sınırlandırılmalı ve backend `LocalService` hesabı altında izole edilmelidir.
2. **Fiziksel Bant Dışı Parmak İzi Doğrulaması (İnsan Faktörü):**
   - QR kodun görsel olarak kopyalanması ve meşru kasadan önce istek atılması yarışında sistem Hub ekranında açık anahtar parmak izini (`fingerprint`) gösterir. Market sahibi iki ekrandaki parmak izini fiziken karşılaştırmadan körü körüne "Onayla" butonuna basarsa yetkisiz cihaz eşleşebilir. Bu durum mobil/Windows UI seviyesinde kullanıcıyı zorunlu doğrulama adımına yönlendiren UI tasarımı ile güvenceye alınmalıdır.

---

## 5. Kesin Doğrulama Kararı

Yapılan bağımsız, salt okunur kod incelemesi, fail-closed mantık doğrulaması, test ve statik analiz yürütme sonuçları neticesinde:

# **KARAR: APPROVED WITH CONDITIONS (Şartlı Onay)**

### Şartlar:
1. **Aşama S-4 spike hedefleri, kriptografik altyapısı, token teslim güvenliği, bellek hijyeni ve güvenlik düzeltmeleri (FINDING-1, 2, 3, 4, 6) %100 BAŞARIYLA TAMAMLANMIŞ VE KABUL EDİLMİŞTİR.**
2. **FINDING-5 gereği:** Windows Service Named Pipe IPC (`\\.\pipe\MarketMMS_Admin_IPC`), Win32 DACL erişim izinleri ve güvenli admin secret aktarımı **Aşama S-5 tamamlanmadan sistem canlı market/üretim ortamına çıkarılamaz.**

