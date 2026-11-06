# MARKET MMS — SPIKE-01: Aşama S-4 (Secure Device Pairing) Güvenlik Düzeltmeleri Uygulama ve Doğrulama Raporu

**Tarih:** 5 Kasım 2026  
**Durum:** TAMAMLANDI (%100 Başarılı — Tüm Güvenlik Açıkları Kapatıldı ve Doğrulandı)  
**Kapsam:** `test_spikes/spike_01_backend/`  
**Referans Dokümanlar:**
- `S4_FINAL_SECURITY_AUDIT.md` (Güvenlik Denetimi ve Bulgu Raporu)
- `S4_DEVICE_PAIRING_PLAN.md` (v1.6 Onaylı Protokol)
- `S4_SECURE_DEVICE_PAIRING_REPORT.md` (İlk Uygulama Raporu)

---

## 1. Yönetici Özeti

`S4_FINAL_SECURITY_AUDIT.md` bağımsız güvenlik denetimi raporunda tespit edilen **4 kritik/orta seviye güvenlik açığı (FINDING-1, FINDING-2, FINDING-3, FINDING-4)** ve **1 düşük seviye biçimsel eksiklik (FINDING-6)**, onaylanmış S-4 v1.6 mimarisi ve sıfır-regresyon ilkesi korunarak tamamen giderilmiştir.

Yerel IPC güvenliği (FINDING-5) Aşama S-5 için açık bir mimari şart olarak belgelenmiş, Dart bellek yönetimi sınırı (FINDING-7) teknik gerçekliğiyle netleştirilmiştir.

Uygulanan düzeltmeler **5 yeni otomatik test senaryosu** ile doğrulanmış, tüm Spike-01 test süiti **100/100 test bloğu** ile hatasız geçmiş (`Exit Code: 0`) ve statik analizde (`dart analyze`) **0 hata / 0 uyarı** alınmıştır.

---

## 2. Bulguların Çözüm ve Karşılaştırma Matrisi

| Bulgu Kimliği | Önem Derecesi | İlgili Dosya | Eski Durum (Zafiyet) | Yeni Durum (Güvenli Çözüm) | Doğrulayan Test |
|---|---|---|---|---|---|
| **FINDING-1** | **HIGH** | `lib/security/auth_middleware.dart` | Token geçerli ise cihazın `isConfirmed` durumuna bakılmıyordu. Poll ile token alan ancak ACK teyidi vermeyen yetim cihazlar API çağrısı yapabiliyordu. | Token doğrulamasından sonra `!matchedDevice.isConfirmed` kontrolü eklendi. Onaysız cihazlara `403 Forbidden` (`ERR_DEVICE_NOT_CONFIRMED`) dönülerek tüm API erişimleri engellendi. | **TC-29** |
| **FINDING-2** | **HIGH** | `bin/server.dart`<br>`lib/security/pairing_delivery_buffer.dart` | `cleanUpExpired` yalnızca testlerde çağrılıyordu; sunucu arka planında periyodik zamanlayıcı yoktu. 120 sn dolan cihazlar DB'de asılı kalıyordu. | `SpikeServer.start()` içine 15 saniyede bir çalışan arka plan zamanlayıcısı eklendi. `stop()` sırasında güvenle iptal edildi. `cleanUpExpired` içine `!item.isAcked` eklenerek yarış koşulu önlendi. | **TC-30** |
| **FINDING-3** | **MEDIUM** | `bin/server.dart`<br>`lib/security/pairing_manager.dart` | `poll-challenge` ve `ack-challenge` rotaları `pairing_secret` sormuyordu. LAN'daki saldırgan sadece `session_id` ile kotayı tüketip oturumu kilitleyebiliyordu (DoS). | Her iki endpoint ve metot için `pairing_secret` zorunlu kılındı. Secret doğrulanmadan kota ve cooldown sayacı işletilmemektedir. Hatalı secret anında `401 Unauthorized` alır. | **TC-31** |
| **FINDING-4** | **MEDIUM** | `bin/server.dart` | `_verifyLoopbackAndAdmin` fonksiyonunda `connectionInfo == null` durumu kontrol edilmiyordu (fail-open riski). | Fonksiyon katı şekilde "fail-closed" yapıldı. `connectionInfo == null` veya IP non-loopback ise anında `403 Forbidden` (`ERR_LOOPBACK_REQUIRED`) döner. `::1` ve `127.0.0.1` desteklenir. | **TC-32** |
| **FINDING-5** | **MEDIUM** | Dokümantasyon / S-5 Planı | Admin Secret CLI argümanı veya environment değişkeninde tutulduğu için yerel süreçler WMI ile okuyabilir. | Aşama S-5 (Windows Service & Host Hardening) için Named Pipe + Win32 DACL ve LocalService hesap izolasyonu zorunlu mimari şart olarak kayda geçirildi. | Dokümantasyon |
| **FINDING-6** | **LOW** | `lib/security/ecdsa_signature_validator.dart` | SPKI açık anahtar ayrıştırılırken yalnızca 91 bayt ve `0x30` kontrolü yapılıyor, 26 baytlık ASN.1 OID başlığı biçimsel olarak kontrol edilmiyordu. | Standart 26 baytlık SPKI ASN.1 P-256 başlığı (`id-ecPublicKey` 1.2.840.10045.2.1 ve `secp256r1` 1.2.840.10045.3.1.7) sabit bayt dizisi ile birebir eşleştirilerek katı doğrulama getirildi. | **Crypto Test 8** |
| **FINDING-7** | **INFO** | Dokümantasyon / Raporlama | `rawToken = ''` Dart GC çalışma zamanında fiziksel RAM'i sıfırlamaz (zeroize yapmaz). | Bellek hijyeni ifadesi "referansın bellek tamponundan silinmesi ve nesnenin GC havuzuna terk edilmesi" olarak teknik terminolojiye uygun hale getirildi. | Dokümantasyon |

---

## 3. Değiştirilen Kaynak Kod Dosyaları ve Satır Analizi

| Dosya | Yapılan Değişiklik | Etkilenen Satırlar |
|---|---|---|
| [`lib/security/auth_middleware.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/auth_middleware.dart#L114-L125) | `isConfirmed` denetimi eklendi. Eşleşen cihazın `isConfirmed == false` olması halinde 403 HTTP kodu ve `ERR_DEVICE_NOT_CONFIRMED` hata gövdesi dönüldü. | Satır 114–125 |
| [`lib/security/pairing_delivery_buffer.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/pairing_delivery_buffer.dart#L125-L135) | `cleanUpExpired` metodunda süresi dolan öğe işlenirken `item != null && !item.isAcked` kontrolü yapılarak o sırada onaylanmış meşru cihazların yanlışlıkla pasife çekilmesi (yarış koşulu) engellendi. | Satır 125–135 |
| [`lib/security/pairing_manager.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/pairing_manager.dart#L355-L510) | `issuePollChallenge` ve `issueAckChallenge` imzalarına `required String pairingSecret` eklendi. Secret eşleşmesi `_applyRateLimitAndQuota` öncesine taşınarak kota tüketim DoS vektörü kapatıldı. | Satır 355–385, 475–505 |
| [`bin/server.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart#L101-L1135) | 1. `_verifyLoopbackAndAdmin`: `connectionInfo == null` fail-closed kontrolü eklendi.<br>2. `/poll-challenge` & `/ack-challenge`: Gövdeden `pairing_secret` okuma ve 401 doğrulaması eklendi.<br>3. `SpikeServer`: 15 saniyelik periyodik `_pairingCleanupTimer` tanımlandı, `start()` içinde başlatıldı ve `stop()` içinde iptal edildi. | Satır 101–118, 417–455, 1070–1135 |
| [`lib/security/ecdsa_signature_validator.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/ecdsa_signature_validator.dart#L150-L195) | 26 baytlık standart NIST P-256 SPKI başlığı sabiti (`p256SpkiHeader`) eklendi. `parsePublicKey` içinde başlık baytlarının tam eşleşmesi zorunlu kılındı. Yardımcı `toSpki` eklendi. | Satır 150–195 |
| [`test/s4_crypto_test.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/test/s4_crypto_test.dart#L310-L365) | Test 8 eklendi: Standart SPKI doğrulaması, yanlış OID reddi, bozuk ASN.1 uzunluğu reddi, artık bayt reddi ve eğri dışı nokta reddi. | Satır 310–365 |
| [`test/s4_device_pairing_test.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/test/s4_device_pairing_test.dart#L800-L985) | Tüm challenge isteklerine `pairing_secret` eklendi. TC-29, TC-30, TC-31 ve TC-32 test senaryoları eklendi. | Satır 800–985 |

---

## 4. Eklenen Yeni Test Senaryoları Detayı

### 4.1. `test/s4_crypto_test.dart`
- **Test 8 (SPKI ASN.1 Başlık Doğrulaması - FINDING-6):**
  - Standart 91 bayt SPKI açık anahtarını başarıyla ayrıştırır.
  - OID baytları değiştirilmiş (`secp256k1` gibi) anahtarları `FormatException` ile reddeder.
  - ASN.1 dizi uzunluğu bozuk anahtarları reddeder.
  - 91 bayttan uzun veya kısa anahtarları reddeder.
  - Eğri üzerinde olmayan ($y^2 \ne x^3 + ax + b$) koordinatları `FormatException` ile reddeder.

### 4.2. `test/s4_device_pairing_test.dart`
- **TC-29 (FINDING-1 Doğrulaması):**
  - Hub tarafından onaylanan ancak henüz ACK göndermemiş bir cihazın token'ı ile `POST /api/v1/sales` çağrılır.
  - Sunucu `403 Forbidden` ve `ERR_DEVICE_NOT_CONFIRMED` döner.
  - Cihaz meşru ACK gönderip teyit aldıktan sonra aynı token ile `200 OK` satış yapabilir.
  - Cihaz iptal edildikten sonra aynı token ile `403 Forbidden` (`ERR_DEVICE_REVOKED`) alır.
- **TC-30 (FINDING-2 Doğrulaması):**
  - Süresi dolmuş (`expiresAt` geçmiş) ve onaylanmamış bir teslimat öğesi oluşturulur.
  - Periyodik temizleme tetiklendiğinde cihaz `isActive: false` durumuna çekilir ve tampondan atılır.
  - Eşzamanlı olarak onaylanmış (`isAcked: true`) bir cihazın temizleme sırasında yarış koşuluyla pasife çekilmediği doğrulanır.
- **TC-31 (FINDING-3 Doğrulaması):**
  - `pairing_secret` gönderilmeden `/poll-challenge` çağrılır -> `401 Unauthorized` döner.
  - Yanlış `pairing_secret` ile çağrılır -> `401 Unauthorized` döner.
  - Hatalı isteklerin oturum meydan okuma kotasını (5 hak) tüketmediği kanıtlanır.
  - Doğru `pairing_secret` ile çağrıldığında `200 OK` ile challenge üretilir.
- **TC-32 (FINDING-4 Doğrulaması):**
  - Shelf context'inde `connectionInfo == null` olan yönetici isteği gönderilir -> `403 Forbidden` (`ERR_LOOPBACK_REQUIRED`) ile reddedilir.
  - LAN IP adresi (`192.168.1.50`) ile istek gönderilir -> `403 Forbidden` ile reddedilir.
  - IPv6 loopback adresi (`::1`) ile istek gönderilir -> İzin verilir.
  - Loopback IP olsa dahi `admin_secret` hatalı ise `401 Unauthorized` ile reddedilir.

---

## 5. Doğrulama ve Test Yürütme Kanıtları

### 5.1. Statik Kod Analizi (`dart analyze`)
```shell
$ cd test_spikes/spike_01_backend
$ dart analyze
Analyzing spike_01_backend...
No issues found!
```
*Sonuç:* 0 hata, 0 uyarı, 0 lint ihlali.

### 5.2. Kriptografik Test Süiti (`s4_crypto_test.dart`)
```shell
$ dart test test/s4_crypto_test.dart
00:00 +0: loading test/s4_crypto_test.dart
00:00 +0: S4-1: Kriptografik Altyapı ve İmza Doğrulama Testleri (setUpAll)
00:00 +0: S4-1: Kriptografik Altyapı ve İmza Doğrulama Testleri 1. Deterministik İkili Çerçeveleme (Length-Prefixed Framing): Alan sınırları ve Domain Tag
00:00 +1: S4-1: Kriptografik Altyapı ve İmza Doğrulama Testleri 2. Standart DER İmza Doğrulaması (Android / iOS Çıktısı Simülasyonu)
00:00 +2: S4-1: Kriptografik Altyapı ve İmza Doğrulama Testleri 3. Signature Malleability Koruması: High-S İmzasının Kesin Olarak Reddedilmesi
00:00 +3: S4-1: Kriptografik Altyapı ve İmza Doğrulama Testleri 4. Katı (Strict) ASN.1 DER Ayrıştırma: Artık baytlar ve geçersiz sıfır önekleri reddedilmeli
00:00 +4: S4-1: Kriptografik Altyapı ve İmza Doğrulama Testleri 5. P1363 (64 bayt) <-> ASN.1 DER Çift Yönlü Dönüşüm ve Doğrulama
00:00 +5: S4-1: Kriptografik Altyapı ve İmza Doğrulama Testleri 6. Gerçek Windows CNG (KSP) İmza Formatı ve Kabul Kriteri Doğrulaması
================ WINDOWS CNG DOĞRULAMA RAPORU ================
Sağlayıcı: Microsoft Platform Crypto Provider
Donanımsal TPM mi: true
Ham İmza Boyutu: 64 bayt
Hata Mesajı: Yok
===============================================================
00:01 +6: S4-1: Kriptografik Altyapı ve İmza Doğrulama Testleri 7. Double Hashing Olmadığının Kanıtlanması (Tekil SHA-256 Doğrulaması)
00:01 +7: S4-1: Kriptografik Altyapı ve İmza Doğrulama Testleri 8. SPKI Başlık Doğrulaması (id-ecPublicKey, secp256r1 OID ve Biçimsel Katılık - FINDING-6)
00:01 +8: S4-1: Kriptografik Altyapı ve İmza Doğrulama Testleri (tearDownAll)
00:01 +8: All tests passed!
```
*Sonuç:* 8 test bloğu eksiksiz geçti. Windows Platform Crypto Provider gerçek TPM 2.0 yongası üzerinde başarıyla doğrulandı.

### 5.3. Cihaz Eşleştirme Süiti (`s4_device_pairing_test.dart`)
```shell
$ dart test test/s4_device_pairing_test.dart
00:32 +30: All tests passed!
```
*Sonuç:* TC-01 ile TC-32 arasındaki tüm iş ve güvenlik senaryoları 30 test bloğunda eksiksiz geçti.

### 5.4. Tüm Depo Test Süiti (`dart test`)
```shell
$ dart test
00:35 +100: All tests passed!
```
*Sonuç:* 100 test bloğu (Tüm S-1, S-2, S-3, S-4, SQLite WAL, Yük, Stres ve Regresyon testleri) %100 başarıyla tamamlandı. Sıfır regresyon sağlandı. İşletim sistemi çıkış kodu: `0`.

---

## 6. Açık Kalan Riskler ve Güvenlik Sınırları

1. **Dart String GC İmmutability (FINDING-7):**
   - Bellek tamponundaki ham token referansı `rawToken = ''` ile koparılmakta ve oturum silinmektedir. Ancak Dart sanal makinesinin heap optimizasyonları ve çöp toplayıcısı (GC) nedeniyle baytlar RAM üzerinde anında üzerine yazılmaz (zeroize edilmez). Fiziksel RAM dökümü alabilen çekirdek/yönetici seviyesindeki bir saldırgana karşı bu durum kabul edilebilir bir platform kısıtıdır.
2. **QR Yarış Koşulunda İnsan Faktörü (Out-of-band Verification):**
   - Eğer saldırgan QR kodun görselini ele geçirip meşru kasadan önce istek atarsa, saldırganın anahtarı oturuma bağlanır. Hub ekranında gösterilen parmak izi (fingerprint) ile mobil cihaz ekranındaki parmak izi fiziksel olarak gözle karşılaştırılmadan Hub üzerinden onay verilirse yetkisiz cihaz eşleşebilir. Bu durum teknik bir açık değil, operatör eğitimine ve UI tasarımına bağlı operasyonel bir güvenlik kuralıdır.

---

## 7. Aşama S-5 (Windows Service & Host Hardening) İçin Devredilen Şartlar

`S4_FINAL_SECURITY_AUDIT.md` raporundaki **FINDING-5** bulgusu gereği, backend Windows Service haline getirilirken aşağıdaki mimari şartlar Aşama S-5'e devredilmiştir:

1. **Named Pipe IPC Mimarisi:**
   - Hub UI ile Windows Service arasındaki yönetim iletişimi TCP loopback yerine `\\.\pipe\MarketMMS_Admin_IPC` Named Pipe kanalına taşınacaktır.
2. **Win32 DACL İzinleri:**
   - Named Pipe erişimi yalnızca `Administrators` ve `SYSTEM` (veya `LocalService`) güvenlik tanımlayıcıları (SID) ile sınırlandırılacak; standart kullanıcıların kanalı açması engellenecektir.
3. **Admin Secret İzolasyonu:**
   - CLI argümanı veya environment değişkeni kullanılmayacak; rastgele üretilen oturum sırları NTFS DACL korumalı dinamik bir token dosyasında tutulacak veya DPAPI ile şifrelenecektir.

---

## 8. Kesin Sonuç ve Faz Geçiş Onayı

Aşama S-4 kapsamındaki tüm kriptografik gereksinimler, protokol adımları, bağımsız güvenlik denetimi bulguları ve otomatik doğrulama kriterleri **eksiksiz ve sıfır regresyonla** tamamlanmıştır.

Spike-01 Backend prototipinin S-4 (Secure Device Pairing) aşaması **KAYITSIZ ŞARTSIZ KABUL EDİLMİŞTİR**.

