# MARKET MMS — SPIKE-01: Aşama S-4 (Secure Device Pairing) Son Güvenlik Denetimi Raporu

**Tarih:** 5 Kasım 2026  
**Denetim Türü:** Statik Kod Analizi, Kriptografik Bağımsız Doğrulama ve Tehdit Modeli İncelemesi (Salt Okunur)  
**Denetlenen Kapsam:** `test_spikes/spike_01_backend/`  
**Referans Dokümanlar:**
- `S4_DEVICE_PAIRING_PLAN.md` (v1.6 Onaylı Protokol)
- `S4_SECURE_DEVICE_PAIRING_REPORT.md`
- `lib/security/ecdsa_signature_validator.dart`
- `lib/security/windows_cng.dart`
- `lib/security/pairing_delivery_buffer.dart`
- `lib/security/pairing_manager.dart`
- `lib/security/auth_middleware.dart`
- `bin/server.dart`
- `test/s4_crypto_test.dart`
- `test/s4_device_pairing_test.dart`

---

## 1. Test Sonuçlarının Bağımsız Doğrulanması

### 1.1. 28 Senaryo ve 24/26 Test Farkının Açıklaması

`S4_DEVICE_PAIRING_PLAN.md` (v1.6) içinde **TC-01 ile TC-28 arasında 28 adet iş ve güvenlik kabul kriteri** tanımlanmıştır. 

`test/s4_device_pairing_test.dart` dosyasındaki test blokları incelendiğinde toplam **26 adet `test(...)` bloğu** bulunmaktadır:
1. **TC-07, TC-08 ve TC-09:** Token üretim, teslim ve onay akışı sıralı bir protokol olduğundan, bu üç kriter tek bir uçtan uca senaryoda (`TC-07 / TC-08 / TC-09: Başarılı Eşleştirme, Token Teslimatı ve ACK ile Bellek Hijyeni`, satır 367–450) birleştirilmiştir.
   - **TC-07:** Challenge üretimi ve Hub onay kontrolü.
   - **TC-08:** İmzalı Poll ile token teslimatı (`mms_dt_*`).
   - **TC-09:** İmzalı ACK sonrası ham token'ın RAM tamponundan silinmesi (`isNull`).
2. Bu nedenle $28 - 2 = 26$ test bloğu oluşturulmuştur. Her 28 senaryonun tüm kabul kriterleri ayrı ayrı `expect(...)` fonksiyonlarıyla eksiksiz doğrulanmaktadır.

### 1.2. Gerçek Toplam Test Sayısı ve Dağılımı

Tüm depodaki test dosyaları satır bazında `Select-String` ile taranarak fiili `test(...)` sayıları doğrulanmıştır:

| Test Dosyası | Test Bloğu Sayısı | Kapsam | Durum |
|---|---|---|---|
| `test/lifecycle_drain_test.dart` | 1 | Graceful Shutdown & WriteQueue Drain | **PASSED** |
| `test/process_crash_test.dart` | 2 | 3 Ardışık OS Crash/Recovery Döngüsü | **PASSED** |
| `test/s1_api_hardening_test.dart` | 13 | S-1 API Güvenliği, Rate Limit, Input Sanitization | **PASSED** |
| `test/s2_token_security_test.dart` | 20 | S-2 PBKDF2/SHA-256, Salt, DPAPI Pepper, Revocation | **PASSED** |
| `test/s3_tls_security_test.dart` | 12 | S-3 TLS 1.3, Root CA Pinning, MITM Reddi | **PASSED** |
| `test/s4_crypto_test.dart` | 7 | S-4 Kriptografi, ASN.1 Strict DER, Low-S, Windows TPM | **PASSED** |
| `test/s4_device_pairing_test.dart` | 26 | S-4 TC-01..TC-28 Protokol, Eşleştirme, Token Teslimatı | **PASSED** |
| `test/shutdown_regression_test.dart` | 3 | Kapanma Regresyon Testleri | **PASSED** |
| `test/spike_test.dart` | 11 | Eşzamanlı Yük (4 İstemci P50/P95/P99) ve 10 İstemci Stres | **PASSED** |
| **GENEL TOPLAM** | **95** | **Tüm Spike-01 Fonksiyonel ve Güvenlik Altyapısı** | **%100 PASSED** |

### 1.3. Çalıştırma Komutu ve Çıkış Kodu Kanıtı

Test süitinin gerçek çalıştırma çıktısı ve işletim sistemi çıkış kodu (`Exit Code: 0`):
```shell
$ cd test_spikes\spike_01_backend; dart test
00:37 +95: All tests passed!
$ echo $LASTEXITCODE
0
```
Testlerin yalnızca dosya olarak oluşturulmadığı; süreçlerin gerçek SQLite WAL veritabanı, gerçek `ncrypt.dll` TPM donanımı ve yerel TCP soketleri üzerinde yürütüldüğü doğrulanmıştır.

---

## 2. Admin Secret ve IPC Güvenlik Denetimi

### 2.1. Admin Secret Yönetimi ve Saklama Analizi

1. **Windows Service admin secret değerini nerede tutuyor?**
   - `bin/server.dart` satır 47 ve 1130'da `SpikeServer.adminSecret` adıyla canlı süreç RAM'inde tutulmaktadır.
   - Değer başlangıçta `--admin-secret=` komut satırı argümanından veya `Platform.environment['ADMIN_SECRET']` ortam değişkeninden okunmaktadır.
2. **Flutter Windows UI bu değeri nasıl elde ediyor?**
   - Şu anki Spike-01 bir backend prototipidir; Flutter UI uygulaması henüz bulunmamaktadır.
   - UI ile backend arasındaki güvenli sırlar aktarım mekanizması henüz kodlanmamıştır.
3. **Secret nasıl aktarılıyor (Dosya, Environment, DPAPI, Named Pipe)?**
   - Şu anda **yalnızca Environment değişkeni veya CLI argümanı** ile aktarılmaktadır.
   - Dosya tabanlı, DPAPI korumalı veya Named Pipe üzerinden aktarım henüz mevcut değildir.
4. **Secret normal kullanıcı süreçleri tarafından okunabilir mi?**
   - **EVET.** Windows işletim sisteminde aynı kullanıcı oturumunda çalışan herhangi bir yetkisiz süreç, `Get-CimInstance Win32_Process` (WMI) veya `ProcessCommandLine` API'si üzerinden başka bir sürecin komut satırı argümanlarını ve ortam değişkenlerini okuyabilmektedir.
5. **Başka bir yerel süreç loopback üzerinden yönetici endpoint'lerine erişebilir mi?**
   - Eğer yerel makinedeki bir süreç yukarıdaki yöntemle `adminSecret` değerini okursa veya tahmin ederse, `127.0.0.1:8085` üzerindeki admin endpoint'lerine (`/session`, `/approve`, `/reject`) istek göndererek yetkisiz onay verebilir.
6. **Named Pipe + ACL korumalı IPC yaklaşımı v1.6 planında bulunuyorsa uygulanmış mı?**
   - `S4_DEVICE_PAIRING_PLAN.md` Bölüm 6.2'de *Dinamik Ephemeral IPC Token Dosyası* ve *Windows Named Pipe + DACL* modelleri tasarlanmış, ancak Bölüm 1.2 "Kapsam Dışı" maddesinde Windows Service hesabı ve DACL izinlerinin **Aşama S-5 kapsamına bırakıldığı** belirtilmiştir. Kodda henüz Named Pipe veya DACL uygulanmamıştır.
7. **Loopback kontrolü ve admin secret her yönetici endpoint'inde uygulanıyor mu?**
   - Evet, tüm admin endpoint'lerinde (`/session`, `/requests`, `/approve`, `/reject`) `_verifyLoopbackAndAdmin` çağrılmaktadır.
   - **ANCAK KRİTİK BİR EKSİK TESPİT EDİLMİŞTİR:** `bin/server.dart` satır 101-120'de, eğer `req.context['shelf.io.connection_info']` null gelirse loopback kontrolü atlanmakta (`fail-open`) ve yalnızca secret denetlenmektedir (Bkz. Bulgu FINDING-4).

---

## 3. ECDSA Bağımsız Kriptografik Doğrulama

### 3.1. RFC 6979 Resmi Test Vektörleri ile Bağımsız Doğrulama

`EcdsaSignatureValidator` motoru, resmi IETF RFC 6979 Bölüm A.2.5 (NIST P-256 / SHA-256) standart test vektörleriyle bağımsız bir betik üzerinden denetlenmiştir:

- **Anahtar Çifti:**
  - $d =$ `C9AFA9D845BA75166B5C215767B1D6934E50C3DB36E89B127B8A622B120F6721`
  - $U_x =$ `60FED4BA255A9D31C961EB74C6356D68C049B8923B61FA6CE669622E60F29FB6`
  - $U_y =$ `7903FE1008B8BC99A41AE9E95628BC64F2F1B20C2D7E9F5177A3C294D4462299`
- **Vektör 1 (Mesaj: "test" - Doğal Low-S):**
  - $r =$ `F1ABB023518351CD71D881567B1EA663ED3EFCF6C5132B354F28D3B0B7D38367`
  - $s =$ `019F4113742A2B14BD25926B49C649155F267E60D3814B4C0CC84250E46F0083`
  - **Sonuç:** `EcdsaSignatureValidator.verifySignature` -> **`true` (%100 BAŞARILI)**.
- **Vektör 2 (Mesaj: "sample" - Ham Hali High-S):**
  - $r =$ `EFD48B2AACB6A8FD1140DD9CD45E81D69D2C877B56AAF991C34D0EA84EAF3716`
  - $s =$ `F7CB1C942D657C41D436C7A1B6E29F65F3E900DBB9AFF4064DC4AB2F843ACDA8`
  - **Ham High-S Testi:** `EcdsaSignatureValidator.p1363ToDer(..., normalizeHighS: false)` -> **Beklendiği gibi `FormatException: High-S tespit edildi` fırlatarak kesinlikle REDDETTİ**.
  - **Low-S Normalizasyonu ($s' = n - s$):** `EcdsaSignatureValidator.verifySignature` -> **`true` (%100 BAŞARILI)**.

### 3.2. Gerçek Windows Donanımı (TPM / CNG) Doğrulaması

`test/s4_crypto_test.dart` (Test 6) kapsamında Windows `ncrypt.dll` FFI ile `Microsoft Platform Crypto Provider` çağrılmış, makinedeki gerçek TPM 2.0 yongası üzerinde anahtar üretilmiş, 64 baytlık ham imza alınmış ve Dart validator tarafından doğrulanmıştır:
```
================ WINDOWS CNG DOĞRULAMA RAPORU ================
Sağlayıcı: Microsoft Platform Crypto Provider
Donanımsal TPM mi: true
Ham İmza Boyutu: 64 bayt
Hata Mesajı: Yok
===============================================================
```

### 3.3. Kriptografik Kriterlerin Denetim Tablosu

| Kriptografik Kriter | `ecdsa_signature_validator.dart` Karşılığı | Doğrulama Durumu |
|---|---|---|
| **P-256 Eğri Sabitleri** | `p`, `a`, `b`, `n`, `Gx`, `Gy` tam NIST FIPS 186-4 değerleri | **DOĞRULANDI** |
| **Strict DER Parser** | Artık bayt (`der.length != seqLen + 2`), negatif integer ve gereksiz sıfır baytı kontrolü | **DOĞRULANDI** |
| **Low-S Zorunluluğu** | $s > (n-1)/2$ ise `FormatException` fırlatılır; signature malleability engellenir | **DOĞRULANDI** |
| **P1363 $\leftrightarrow$ DER** | 64 bayt $r \parallel s$ ile ASN.1 Sequence çift yönlü hatasız çevrilir | **DOĞRULANDI** |
| **Aralık Denetimi** | $1 \le r < n$ ve $1 \le s < n$ ihlallerinde imza anında reddedilir | **DOĞRULANDI** |
| **Bozuk İmza Reddi** | Eksik bayt, bozuk ASN.1 başlığı, yanlış anahtar anında `false` döner | **DOĞRULANDI** |
| **Canonical Framing** | `domainTag` + 2 bayt uzunluk önekli deterministik binary framing | **DOĞRULANDI** |
| **Tekil SHA-256** | Payload yalnızca bir kez özetlenir (`sha256.convert(payload)`), double hashing yoktur | **DOĞRULANDI** |
| **SPKI Parsing** | 91 bayt SPKI ve 65 bayt ham nokta ayrıştırılır, `isOnCurve` denetlenir | **ŞARTLI DOĞRULANDI (Bkz. FINDING-6)** |

---

## 4. Pairing Saldırı Senaryoları Analizi

### 4.1. QR Kopyalama Saldırısı: Tam Engelleme vs Zorlaştırma Koşulları

> [!IMPORTANT]
> **Tehdit Analizi: QR Kopyalama Hangi Koşulda Engellenir, Hangi Koşulda Yalnızca Zorlaştırılır?**
>
> 1. **Meşru Cihazın Önce İstek Gönderdiği Durum (TAM ENGELLENİR):**
>    - Meşru kasa QR'ı tarar ve `client_public_key` ile `/request` atar. Oturum `pendingApproval` durumuna geçer ve açık anahtar kilitlenir (`binding immutability`).
>    - Saldırgan QR fotoğrafına veya verisine sahip olsa dahi, kendi anahtarını ekleyemez (409 Conflict). Meşru cihaz adına istek atsa bile, meşru cihazın **cihaz donanımındaki özel anahtarına (private key) sahip olamaz**.
>    - Bu nedenle `/poll` meydan okumasını imzalayamaz ve **asla token teslim alamaz**. Saldırı kriptografik olarak %100 engellenir.
>
> 2. **Saldırganın Yarış Koşuluyla Meşru Cihazdan Önce İstek Gönderdiği Durum (YALNIZCA ZORLAŞTIRILIR / İNSAN DOĞRULAMASINA BAĞLIDIR):**
>    - Saldırgan QR kodunu önceden ele geçirirse ve meşru kasadan önce `POST /api/v1/pairing/request` atarak kendi `attacker_public_key` değerini ve "Kasa 1" sahte adını kaydettirirse:
>    - Meşru kasa taradığında `409 Conflict: Bu oturum zaten bir cihaza bağlanmış` hatası alır.
>    - Hub ekranında onay bekleyen talep listelenir: `Kasa 1`, Parmak İzi: `A4:B2:...`.
>    - **Kritik Güvenlik Sınırı:** Eğer market sahibi Hub ekranındaki parmak izini meşru mobil cihazın ekranında gösterilen parmak iziyle karşılaştırmadan **körü körüne "Onayla" butonuna basarsa**, saldırgan kendi özel anahtarıyla challenge'ı imzalayarak token'ı alabilir!
>    - **Sonuç:** QR kodun çalınması halinde ilk istek aşamasındaki yarış saldırısı saf kriptografi ile tek başına engellenemez; **fiziksel bant dışı (out-of-band) parmak izi karşılaştırma prosedürüne tabidir**.

### 4.2. Diğer Saldırı Senaryolarının Değerlendirilmesi

| Saldırı Senaryosu | Mevcut Kod Davranışı | Güvenlik Değerlendirmesi |
|---|---|---|
| **Aynı Session İçin Eşzamanlı İstek** | `registerRequest` senkron çalışır; ilk istek durumu `pendingApproval` yapar, ikincisi `409 SESSION_ALREADY_BOUND` alır. | **GÜVENLİ** |
| **Aynı Challenge İçin Eşzamanlı Poll** | `verifyAndPollToken` içinde `challenge.isConsumed = true` senkron atanır; eşzamanlı ikinci istek `409 CHALLENGE_ALREADY_CONSUMED` alır. | **GÜVENLİ** |
| **Aynı Challenge İçin Eşzamanlı ACK** | `verifyAndAcknowledge` içinde `challenge.isConsumed = true` senkron atanır ve buffer silinir; ikinci istek 409 alır. | **GÜVENLİ** |
| **Challenge Replay Saldırısı** | Nonce ve challenge tek kullanımlıktır (`isConsumed: true`), tekrarında 409 döner. | **GÜVENLİ** |
| **Oturum / Kota Aşımı (Brute-force / DoS)** | 3 yanlış secret oturumu kilitler; 3 hatalı imza challenge'ı kilitler; oturum başına 5 kota sınırı vardır. | **GÜVENLİ** |
| **Sunucu Kapanırken Yarım Kalan Eşleşmeler** | `PairingDeliveryBuffer.startupReconcile` sunucu açılışında `isConfirmed: false` olan yetimleri otomatik `isActive: false` yapar. | **GÜVENLİ** |
| **ACK Sonrası Yeniden Token Alma** | ACK anında tampon temizlenir (`rawToken = ''`), tekrar eden poll 410 Gone alır. | **GÜVENLİ** |
| **İptal Edilen Cihazın Token Kullanması** | `auth_middleware` veritabanındaki `isActive: false` durumunu denetler ve 403 DEVICE_REVOKED döner. | **GÜVENLİ** |
| **ACK Öncesi Token Kullanımı** | Cihaz poll ile token'ı alıp ACK göndermeden API'ye giderse `isConfirmed: false` denetlenmediği için istek kabul edilir! | **GÜVENSİZ (Bkz. FINDING-1)** |

---

## 5. Token ve RAM Güvenliği İncelemesi

1. **Raw token hiçbir koşulda SQLite'a yazılıyor mu?**
   - **HAYIR.** Veritabanı işlemleri incelenmiştir; SQLite `devices` tablosuna yalnızca SHA-256 hash ve salt yazılmaktadır. Ham token veritabanı veya WAL dosyalarına asla yazılmaz.
2. **Token kalıcı log veya hata çıktısına sızabilir mi?**
   - **HAYIR.** `bin/server.dart` ve `pairing_manager.dart` içindeki audit log çağrıları yalnızca oturum kimliklerini ve genel durumları kaydeder. TC-19 log hijyeni testi bunu doğrulamıştır.
3. **ACK işlemi atomik mi?**
   - **EVET.** Bellek tamponu temizliği senkron yapılır, veritabanındaki `isConfirmed: true` güncellemesi ise `writeQueue` üzerinden atomik SQLite transaction ile işlenir.
4. **Eşzamanlı ACK istekleri çift başarı üretebilir mi?**
   - **HAYIR.** İlk ACK isteği `challenge.isConsumed = true` bayrağını ve `deliveryBuffer.remove(sessionId)` çağrısını çalıştırır. İkinci istek anında 409 Conflict alır.
5. **TTL temizliği güvenilir mi?**
   - **HAYIR (ÇALIŞMA ZAMANINDA EKSİK).** `cleanUpExpired` fonksiyonu yazılmıştır ancak sunucu arka planında periyodik olarak çağrılmamaktadır (Bkz. Bulgu FINDING-2).
6. **`rawToken = ''` bellek sıfırlama sınırının raporda ifadesi:**
   - Dart sanal makinesinde `String` nesneleri immutable heap yapılarıdır. `rawToken = ''` ataması fiziksel belleği sıfırlamaz (zeroize yapmaz); yalnızca nesne referansını kopararak Garbage Collector'a terk eder. Bu teknik gerçeklik raporda açıkça belirtilmelidir (Bkz. Bulgu FINDING-7).

---

## 6. Güvenlik Denetimi Bulguları (Bulgu Matrisi)

### [FINDING-1] Onaylanmamış Cihazların API Kullanabilmesi (Missing `isConfirmed` Check)
- **Önem Derecesi:** **HIGH**
- **Dosya & Satır:** [`lib/security/auth_middleware.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/auth_middleware.dart#L103-L128) (Satır 103–128)
- **Teknik Gerekçe:** `auth_middleware.dart` gelen Bearer token'ı doğruladıktan sonra yalnızca `!matchedDevice.isActive` ve `matchedDevice.expiresAt` alanlarını denetlemektedir. S-4 aşamasında eklenen `isConfirmed` alanı kontrol edilmemektedir.
- **Saldırı Senaryosu:** Hub yöneticisi onay verdiğinde cihaz DB'ye `isConfirmed: false` ve `isActive: true` olarak eklenir. Kötü niyetli veya manipüle edilmiş bir istemci `/poll` ile ham token'ı çeker, ancak bilerek `/ack` onayını göndermez. Token elinde olduğu için, henüz eşleştirme ACK teyidi tamamlanmamış bir cihaz satış transaction'ları dahil tüm yetkili API işlemlerini gerçekleştirebilir.
- **Önerilen Çözüm:** `auth_middleware.dart` içine şu kontrol eklenmelidir:
  ```dart
  if (!matchedDevice.isConfirmed) {
    return Response.forbidden(
      jsonEncode({
        'error': 'DEVICE_NOT_CONFIRMED',
        'code': 'ERR_DEVICE_NOT_CONFIRMED',
        'message': 'Cihazın eşleştirme ACK onayı henüz tamamlanmamıştır.',
        'device_id': matchedDevice.deviceId,
      }),
      headers: {'content-type': 'application/json'},
    );
  }
  ```

---

### [FINDING-2] Teslimat Zaman Aşımı Temizleyicisinin (`cleanUpExpired`) Periyodik Çalıştırılmaması
- **Önem Derecesi:** **HIGH**
- **Dosya & Satır:** [`bin/server.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart), [`lib/security/pairing_delivery_buffer.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/pairing_delivery_buffer.dart#L115) (Satır 115)
- **Teknik Gerekçe:** `PairingDeliveryBuffer.cleanUpExpired` metodu yalnızca birim testte (`test/s4_device_pairing_test.dart:454`) manuel olarak çağrılmıştır. Sunucu ana çalışma döngüsünde periyodik bir arka plan zamanlayıcısı (`Timer.periodic`) kurulmamıştır.
- **Saldırı Senaryosu:** Bir istemci onaylandıktan sonra 120 saniye içinde ACK göndermezse veya ağ kesilirse, o cihaz sunucu yeniden başlatılana kadar veritabanında `isActive: true` olarak asılı kalır. FINDING-1 açığıyla birleştiğinde bu yetim cihazlar süresiz olarak API çağrısı yapmaya devam edebilir.
- **Önerilen Çözüm:** `bin/server.dart` içinde `start()` metoduna periyodik temizleyici eklenmeli ve sunucu kapatılırken (`stop()`) iptal edilmelidir:
  ```dart
  _cleanupTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
    await pairingManager.deliveryBuffer.cleanUpExpired(db: db, writeQueue: writeQueue);
  });
  ```

---

### [FINDING-3] Meydan Okuma Endpoint'lerinde `pairing_secret` Kontrolü Eksikliği (DoS Riski)
- **Önem Derecesi:** **MEDIUM**
- **Dosya & Satır:** [`bin/server.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart#L414-L443) (Satır 414–443), [`lib/security/pairing_manager.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/pairing_manager.dart#L352-L373) (Satır 352–373, 469–496)
- **Teknik Gerekçe:** `issuePollChallenge` ve `issueAckChallenge` fonksiyonları `pairing_secret` doğrulaması yapmamaktadır; yalnızca `session_id` kabul etmektedir.
- **Saldırı Senaryosu:** Yerel ağdaki (LAN) saldırgan bir cihaz `session_id` değerini gözlemleyerek veya tahmin ederek 5 saniye aralıklarla 5 kez `POST /api/v1/pairing/poll-challenge` isteği gönderebilir. Oturumun 5 challenge kotası tükenir (`SESSION_CHALLENGE_QUOTA_EXHAUSTED`) ve oturum `locked` durumuna geçerek meşru cihazın token alması engellenir (Hizmet Dışı Bırakma - DoS).
- **Önerilen Çözüm:** `issuePollChallenge` ve `issueAckChallenge` metotlarına `required String pairingSecret` parametresi eklenmeli ve `session.pairingSecret != pairingSecret` durumunda 401 Unauthorized dönülmelidir.

---

### [FINDING-4] `_verifyLoopbackAndAdmin` İçinde `connectionInfo == null` Durumunda Açık Geçiş (Fail-Open)
- **Önem Derecesi:** **MEDIUM**
- **Dosya & Satır:** [`bin/server.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart#L101-L120) (Satır 101–120)
- **Teknik Gerekçe:** `_verifyLoopbackAndAdmin` fonksiyonunda `if (connectionInfo != null)` bloğu dışında bir loopback zorunluluğu yoktur. Eğer Shelf context'inde `connectionInfo` null gelirse kontrol atlanmakta ve doğrudan secret kontrolüne geçilmektedir.
- **Saldırı Senaryosu:** İleride eklenebilecek bir reverse proxy, port yönlendirici veya test katmanında `connectionInfo` null olursa, LAN üzerinden gelen istekler loopback kısıtlamasına takılmadan geçebilir.
- **Önerilen Çözüm:** Fonksiyon katı şekilde "fail-closed" yapılmalıdır:
  ```dart
  if (connectionInfo == null) {
    return Response.forbidden(jsonEncode({'error': 'LOOPBACK_INFO_MISSING'}));
  }
  ```

---

### [FINDING-5] Admin Secret Değerinin Komut Satırı ve Ortam Değişkeninde Tutulması (Local IPC Exposure)
- **Önem Derecesi:** **MEDIUM**
- **Dosya & Satır:** [`bin/server.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart#L1067-L1081) (Satır 1067, 1081)
- **Teknik Gerekçe:** `ADMIN_SECRET` şu anda `--admin-secret=` argümanından veya çevre değişkeninden okunmaktadır. v1.6 planında belirtilen NTFS DACL korumalı `admin_ephemeral.token` dosyası veya Win32 DACL Named Pipe (`\\.\pipe\MarketMMS_Admin_IPC`) henüz uygulanmamıştır (Aşama S-5 kapsamındadır).
- **Saldırı Senaryosu:** Aynı Windows makinesinde standart kullanıcı yetkisiyle çalışan zararlı bir süreç, komut satırı argümanlarını (WMI üzerinden) okuyarak secret'ı elde edebilir ve `127.0.0.1:8085` üzerindeki yönetici endpoint'lerini manipüle edebilir.
- **Önerilen Çözüm:** Aşama S-5 (Windows Service & Host Hardening) aşamasında Named Pipe + DACL veya DPAPI korumalı dosya entegrasyonu tamamlanmalıdır.

---

### [FINDING-6] SPKI Açık Anahtar Başlığının Gevşek Ayrıştırılması
- **Önem Derecesi:** **LOW**
- **Dosya & Satır:** [`lib/security/ecdsa_signature_validator.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/ecdsa_signature_validator.dart#L148-L152) (Satır 148–152)
- **Teknik Gerekçe:** `parsePublicKey` metodu SPKI formatı için yalnızca `bytes.length == 91 && bytes[0] == 0x30` kontrolü yapmakta, son 65 baytını uncompressed nokta kabul etmektedir. İlk 26 baytlık ASN.1 OID başlığı (`id-ecPublicKey` ve `secp256r1`) doğrulanmamaktadır.
- **Hafifletici Etken:** Son 65 bayt `_parseUncompressedPoint` içinde eğri denklemi kontrolünden (`isOnCurve`) geçtiği için geçersiz noktalar kabul edilmez. Ancak biçimsel katılık açısından başlık baytları da doğrulanmalıdır.
- **Önerilen Çözüm:** Standart 26 baytlık SPKI P-256 ASN.1 ön eki sabit bayt dizisi ile karşılaştırılmalıdır.

---

### [FINDING-7] Dart String İmmutability ve Yönetilen Bellek Sınırı
- **Önem Derecesi:** **INFORMATIONAL**
- **Dosya & Satır:** [`lib/security/pairing_delivery_buffer.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/pairing_delivery_buffer.dart#L89) (Satır 89, 131), [`S4_SECURE_DEVICE_PAIRING_REPORT.md`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/S4_SECURE_DEVICE_PAIRING_REPORT.md)
- **Teknik Gerekçe:** `rawToken = ''` işlemi yönetilen Dart çalışma zamanında yalnızca nesne referansını boşa çıkarır; heap üzerindeki baytları fiziksel olarak sıfırlamaz (zeroize yapmaz). Fiziksel RAM dökümü (memory dump) alan bir yönetici süreç GC çalışana kadar token baytlarını görebilir.
- **Açıklama:** Bu durum Dart dilinin managed memory mimarisinden kaynaklanan bilinen bir platform kısıtıdır. Raporlama belgelerinde "fiziksel bellek sıfırlama" tabiri yerine "referansın bellek tamponundan silinmesi" ifadesi kullanılmalıdır.

---

## 7. Kesin Denetim Kararı

Yapılan bağımsız kriptografik doğrulama, statik kod analizi, test yürütme sonuçları ve güvenlik tehdit modellemesi neticesinde:

# **KARAR: APPROVED WITH CONDITIONS (Şartlı Onay)**

### Şartlar ve Düzeltme Yol Haritası:
S-4 aşamasının temel kriptografik altyapısı, katı ASN.1 ayrıştırması, Low-S kuralları, tekil SHA-256 kullanımı ve Windows TPM donanım entegrasyonu kusursuz ve endüstri standardı kalitededir. Ancak Faz 1 istemci uygulaması veya üretim ortamına geçilmeden önce şu şartlar giderilmelidir:

1. **Öncelikli Şart (P0):** [`lib/security/auth_middleware.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/auth_middleware.dart) içine `isConfirmed == true` kontrolü eklenerek ACK almamış cihazların API çağrısı yapması engellenmelidir (FINDING-1).
2. **Öncelikli Şart (P0):** [`bin/server.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart) içine arka planda periyodik olarak çalışan ve 120 sn süresi dolan yetim cihazları temizleyen `cleanUpExpired` zamanlayıcısı eklenmelidir (FINDING-2).
3. **İkincil Şart (P1):** `poll-challenge` ve `ack-challenge` rotalarına `pairing_secret` doğrulama zorunluluğu getirilerek kota tüketme DoS riski bertaraf edilmelidir (FINDING-3).
4. **İkincil Şart (P1):** `_verifyLoopbackAndAdmin` fonksiyonu fail-closed mantığına geçirilmelidir (FINDING-4).
5. **Aşama S-5 Şartı (P2):** Windows Service ve Local IPC aşamasında (S-5) Named Pipe + Win32 DACL entegrasyonu tamamlanmalıdır (FINDING-5).

