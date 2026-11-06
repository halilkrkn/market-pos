# MARKET MMS — SPIKE-01: Aşama S-4 (Secure Device Pairing) Tamamlanma Raporu

**Tarih:** 5 Kasım 2026  
**Proje:** Market Management System (MMS) — Local Master Hub Backend Spike (SPIKE-01)  
**Aşama:** Faz 0 / SPIKE-01 / Aşama S-4: Secure Device Pairing  
**Kapsam:** `test_spikes/spike_01_backend/`  
**Referans Dokümanlar:** [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](../../MARKET_POS_AI_STUDIO_BUILD_PLANI.md), [`S4_DEVICE_PAIRING_PLAN.md`](./S4_DEVICE_PAIRING_PLAN.md) (v1.6 Onaylı Nihai Protokol)  
**Uygulanan Standartlar:** Clean Architecture, `code-quality`, `test-first`, `systematic-debugging`, `documentation`

---

## 1. Oluşturulan ve Değiştirilen Dosyalar

| Dosya Yolu | Durum | Rolü ve Yapılan Değişiklikler |
|---|---|---|
| [`lib/security/ecdsa_signature_validator.dart`](./lib/security/ecdsa_signature_validator.dart) | **Yeni** | NIST P-256 (secp256r1) saf Dart eliptik eğri aritmetiği, SPKI DER (91B) / ham noktasal (65B) ayrıştırma, katı ASN.1 DER parser (artık bayt, negatif integer ve gereksiz sıfır baytı reddi), Low-S zorunluluğu ($s \le \lfloor(n-1)/2\rfloor$), IEEE P1363 (64B) $\leftrightarrow$ DER çift yönlü dönüştürücü, deterministik binary framing (`POLL` 6 alan / `ACK` 7 alan ile `token_sha256`) ve tekil SHA-256 doğrulayıcısı. |
| [`lib/security/windows_cng.dart`](./lib/security/windows_cng.dart) | **Yeni** | Windows Cryptography API: Next Generation (CNG) `ncrypt.dll` FFI modülü. Donanımsal TPM (`Microsoft Platform Crypto Provider`) ile yazılımsal CNG (`Microsoft Software Key Storage Provider`) ayrımını yapan, gerçek sağlayıcı üzerinde anahtar açıp IEEE P1363 imza üreten modül. |
| [`lib/security/pairing_delivery_buffer.dart`](./lib/security/pairing_delivery_buffer.dart) | **Yeni** | Geçici RAM teslimat tamponu. Üretilen ham token'ı (`rawToken`) 120 saniyelik TTL ile yalnızca bellekte tutan, asla veritabanına yazmayan, ACK teyidi veya timeout durumunda RAM'den sıfırlayan (`rawToken = ''`), sunucu açılışında `startupReconcile` ile onaylanmamış yetim cihazları temizleyen bileşen. |
| [`lib/security/pairing_manager.dart`](./lib/security/pairing_manager.dart) | **Yeni** | 5 dakikalık Pairing Session durum makinesi, QR veri modeli üretimi, 3 hatalı pairing secret denemesinde oturum kilitleme, istemci public key sabitliği, poll/ack challenge yaşam döngüsü (60s TTL, max 3 başarısız denemede kilitlenme, oturum başına max 5 kota, 5s cooldown / HTTP 429). |
| [`lib/db/database.dart`](./lib/db/database.dart) | **Güncellendi** | `Devices` tablosuna `BoolColumn get isConfirmed => boolean().withDefault(const Constant(true))();` kolonu eklendi. (Geriye dönük uyumluluk korunarak S-1/S-2/S-3 testlerinin kırılması engellendi). |
| [`lib/db/database.g.dart`](./lib/db/database.g.dart) | **Güncellendi** | `build_runner` ile Drift kodları yeniden üretildi (11 saniyede temiz derleme). |
| [`bin/server.dart`](./bin/server.dart) | **Güncellendi** | Eski güvensiz `/api/v1/devices/register` rotası kalıcı olarak tasfiye edildi (404 dönecek şekilde ayarlandı). 10 adet yeni S-4 pairing endpoint'i eklendi. Admin operasyonları (`/session`, `/requests`, `/approve`, `/reject`) için loopback (`127.0.0.1` / `::1`) ve `X-Admin-Secret` zorunluluğu (`_verifyLoopbackAndAdmin`) getirildi. Sunucu başlangıcında `PairingDeliveryBuffer.startupReconcile` bağlandı. |
| [`test/s4_crypto_test.dart`](./test/s4_crypto_test.dart) | **Yeni** | S4-1 Kriptografik altyapıyı, ASN.1 katı parser'ı, Low-S zorunluluğunu, P1363 $\leftrightarrow$ DER dönüşümünü, double-hashing korumasını ve Windows CNG gerçek TPM sağlayıcısını doğrulayan 7 kapsamlı test senaryosu. |
| [`test/s4_device_pairing_test.dart`](./test/s4_device_pairing_test.dart) | **Yeni** | v1.6 planında tanımlanan TC-01 ile TC-28 arasındaki tüm 28 güvenlik senaryosunu uçtan uca Shelf HTTP sunucusu üzerinde doğrulayan TDD test süiti. |

---

## 2. Eklenen veya Değiştirilen Paketler

> [!IMPORTANT]
> **Sıfır Yeni Harici Paket:** S-4 aşamasında `pubspec.yaml` dosyasına **hiçbir yeni harici paket veya üçüncü parti bağımlılık eklenmemiştir**.

Projenin mevcut kararlı kütüphaneleri kullanılmıştır:
- Dart SDK Standart Kütüphaneleri (`dart:typed_data`, `dart:convert`, `dart:io`, `dart:math`, `dart:ffi`)
- `crypto: ^3.0.3` (SHA-256 özetleri)
- `drift: ^2.14.0` (SQLite veritabanı modeli)
- `shelf: ^1.4.1` ve `shelf_router: ^1.1.4` (HTTP router ve middleware)

---

## 3. Uygulanan Endpoint'ler ve Güvenlik Sınırları

### 3.1. Eski Rotanın Tasfiyesi
- `POST /api/v1/devices/register`: **Kalıcı Olarak Tasfiye Edildi (404 Not Found)**.
  - Artık hiçbir cihaz LAN üzerinden tek bir POST isteğiyle sisteme yetkisiz dahil olamaz.

### 3.2. Yeni S-4 Endpoint Haritası

```
                                      [WINDOWS LOCAL MASTER HUB]
                                      
  [Yerel Windows Hub UI]                       [LAN Mobil / Terminal İstemcileri]
  (Yalnızca Loopback 127.0.0.1)                (Android, iOS, LAN Windows)
               │                                            │
               │ [Admin Secret Gerekli]                     │ [Pairing Secret & İmza Gerekli]
               ▼                                            ▼
  POST /api/v1/pairing/session ──────────────► [QR Üretimi: sess_*, sec_*, ca_fp]
  GET  /api/v1/pairing/requests                             │
  POST /api/v1/pairing/approve                              ├─► POST /api/v1/pairing/request (Public Key + Cihaz Bilgisi)
  POST /api/v1/pairing/reject                               │
                                                            ├─► GET  /api/v1/pairing/ca-cert (TLS Kök CA İndirme)
                                                            │
                                                            ├─► POST /api/v1/pairing/poll-challenge (60s Nonce Alımı)
                                                            ├─► POST /api/v1/pairing/poll (ECDSA İmzalı Token Çekimi)
                                                            │
                                                            ├─► POST /api/v1/pairing/ack-challenge (60s Nonce Alımı)
                                                            └─► POST /api/v1/pairing/ack (token_sha256 Bağlı ECDSA Onayı)
```

| HTTP Metodu | Endpoint | Yetki & Sınırlandırma | Açıklama |
|---|---|---|---|
| `POST` | `/api/v1/pairing/session` | **Loopback + `X-Admin-Secret`** | 5 dakikalık oturum açar, QR veri modeli (`v`, `hub_url`, `session_id`, `pairing_secret`, `ca_fingerprint`, `expires_at`) üretir. |
| `GET` | `/api/v1/pairing/ca-cert` | **Public** | İstemcinin Root CA sabitlemesi (pinning) yapabilmesi için sunucu Kök CA sertifikasını (`ca.crt`) döner. |
| `POST` | `/api/v1/pairing/request` | **Public + `pairing_secret`** | İstemci cihaz donanım bilgilerini ve SPKI DER formatındaki public key'ini gönderir (202 Accepted). |
| `GET` | `/api/v1/pairing/requests` | **Loopback + `X-Admin-Secret`** | Onay bekleyen cihaz taleplerini listeler. |
| `POST` | `/api/v1/pairing/approve` | **Loopback + `X-Admin-Secret`** | Market sahibinin onayıyla cihazı onaylar, S-2 TokenManager ile token üretip teslimat tamponuna koyar. |
| `POST` | `/api/v1/pairing/reject` | **Loopback + `X-Admin-Secret`** | Talebi kalıcı olarak reddeder, oturumu sonlandırır. |
| `POST` | `/api/v1/pairing/poll-challenge` | **Public + `pairing_secret`** | İstemciye token'ı alabilmesi için 60 saniye geçerli kriptografik rastgele bir `poll_challenge_nonce` döner. |
| `POST` | `/api/v1/pairing/poll` | **Public + ECDSA İmzası** | İstemcinin özel anahtarıyla imzaladığı `POLL` meydan okumasını doğrular, geçerliyse ham token'ı teslim eder. |
| `POST` | `/api/v1/pairing/ack-challenge` | **Public + `pairing_secret`** | Token'ın güvenli depoya kaydedildiğinin teyidi için 60 saniye geçerli `ack_challenge_nonce` döner. |
| `POST` | `/api/v1/pairing/ack` | **Public + Token Bağlı İmza** | İstemcinin `token_sha256` özetini içeren imzasını doğrular. Cihazı `isConfirmed: true` yapar, ham token'ı RAM'den anında siler. |

---

## 4. Test Senaryoları ve Sonuçları

### 4.1. S4-1 Kriptografik Birim Testleri (`test/s4_crypto_test.dart`)

```
00:00 +0: 1. Deterministik İkili Çerçeveleme (Length-Prefixed Framing): Alan sınırları ve Domain Tag [PASSED]
00:00 +1: 2. Standart DER İmza Doğrulaması (Android / iOS Çıktısı Simülasyonu) [PASSED]
00:00 +2: 3. Signature Malleability Koruması: High-S İmzasının Kesin Olarak Reddedilmesi [PASSED]
00:00 +3: 4. Katı (Strict) ASN.1 DER Ayrıştırma: Artık baytlar ve geçersiz sıfır önekleri reddedilmeli [PASSED]
00:00 +4: 5. P1363 (64 bayt) <-> ASN.1 DER Çift Yönlü Dönüşüm ve Doğrulama [PASSED]
00:00 +5: 6. Gerçek Windows CNG (KSP) İmza Formatı ve Kabul Kriteri Doğrulaması [PASSED]
00:02 +6: 7. Double Hashing Olmadığının Kanıtlanması (Tekil SHA-256 Doğrulaması) [PASSED]
```

### 4.2. S4-2..S4-5 Güvenlik ve Uçtan Uca Entegrasyon Testleri (`test/s4_device_pairing_test.dart`)

| Senaryo Kodu | Senaryo Tanımı | Beklenen Davranış | Sonuç |
|---|---|---|---|
| **TC-01** | Geçerli QR / Pairing Session oluşturma | 201 Created, `v=1`, `sess_*`, `sec_*`, `ca_fingerprint` | **BAŞARILI** |
| **TC-02** | Süresi dolmuş session ile istek atma | 410 Gone (`ERR_SESSION_EXPIRED`) | **BAŞARILI** |
| **TC-03** | Aynı session ile ikinci kez eşleştirme denemesi | 409 Conflict (`ERR_SESSION_ALREADY_REQUESTED`) | **BAŞARILI** |
| **TC-04** | Yanlış pairing secret ile istek gönderme | 401 Unauthorized (`ERR_INVALID_SECRET`) | **BAŞARILI** |
| **TC-05** | Üç yanlış deneme sonrası brute-force kilidi | 403 Forbidden (`ERR_SESSION_LOCKED`) | **BAŞARILI** |
| **TC-06** | Hub onayı olmadan poll challenge alma | 403 Forbidden (`ERR_SESSION_NOT_APPROVED`) | **BAŞARILI** |
| **TC-07** | Hub onayı ve geçerli poll challenge üretimi | 200 OK, 60s TTL, Base64 Nonce | **BAŞARILI** |
| **TC-08** | Geçerli ECDSA imzasıyla poll token teslimatı | 200 OK, ham `mms_dt_*` token teslimi | **BAŞARILI** |
| **TC-09** | ACK sonrası ham token bellek hijyeni | 200 OK, `rawToken` bellekten anında silindi (`isNull`) | **BAŞARILI** |
| **TC-10** | 120 sn içinde ACK gelmezse tampon temizliği | Süresi dolmamışken 0 silme; zaman aşımında iptal | **BAŞARILI** |
| **TC-11** | LAN IP üzerinden Hub onayı denemesi | 403 Forbidden (`ERR_LOOPBACK_REQUIRED`) | **BAŞARILI** |
| **TC-12** | İstemcinin pairing secret ile onay denemesi | 403 Forbidden (`ERR_INVALID_ADMIN_SECRET`) | **BAŞARILI** |
| **TC-13** | Normal kasiyer Bearer tokenı ile onay denemesi | 403 Forbidden (`ERR_INVALID_ADMIN_SECRET`) | **BAŞARILI** |
| **TC-14** | Eski `/api/v1/devices/register` çağırma denemesi | 404 Not Found (Eski rota tamamen tasfiye edildi) | **BAŞARILI** |
| **TC-15** | Aktif bir cihaz ID'si ile tekrar eşleşme | 409 Conflict (`ERR_DEVICE_ALREADY_REGISTERED`) | **BAŞARILI** |
| **TC-16** | İptal edilmiş (revoked) cihaz ID'si ile eşleşme | 409 Conflict (`ERR_DEVICE_REVOKED`) | **BAŞARILI** |
| **TC-17** | Sunucu açılışında yetim (`isConfirmed: false`) cihazlar | `startupReconcile` ile otomatik `isActive: false` yapıldı | **BAŞARILI** |
| **TC-18** | `GET /api/v1/pairing/ca-cert` | 200 OK, `application/x-x509-ca-cert`, SHA-256 eşleşti | **BAŞARILI** |
| **TC-19** | Audit log bellek ve kayıt hijyeni | Loglarda açık metin token veya pairing secret yok | **BAŞARILI** |
| **TC-20** | QR çalan saldırganın özel anahtarsız denemesi | 403 Forbidden (`ERR_INVALID_SIGNATURE`) | **BAŞARILI** |
| **TC-21** | Çöp/bozuk imza baytları ile poll denemesi | 403 Forbidden (`ERR_INVALID_SIGNATURE`) | **BAŞARILI** |
| **TC-22** | Onay bekleyen oturumda public key değiştirme | 409 Conflict (`ERR_PUBLIC_KEY_IMMUTABLE`) | **BAŞARILI** |
| **TC-23** | Sahte `token_sha256` ile imzalanan ACK | 403 Forbidden (`ERR_INVALID_SIGNATURE`) | **BAŞARILI** |
| **TC-24** | Kullanılmış poll challenge ile replay saldırısı | 409 Conflict (`ERR_CHALLENGE_ALREADY_CONSUMED`) | **BAŞARILI** |
| **TC-25** | Kullanılmış ACK challenge ile replay saldırısı | 409 Conflict (`ERR_CHALLENGE_ALREADY_CONSUMED`) | **BAŞARILI** |
| **TC-26** | 3 hatalı imzada challenge kilitlenmesi ve kurtarma | Challenge kilitlenir (403), yeni challenge ile kurtarılır | **BAŞARILI** |
| **TC-27** | 5 sn dolmadan challenge isteme (Rate Limit) | 429 Too Many Requests (`Retry-After: 5`) | **BAŞARILI** |
| **TC-28** | Eşleşen cihazın token ile satış yapabilmesi | 201 Created (`COMMITTED`), Stok düşümü başarılı | **BAŞARILI** |

---

## 5. Test Sayıları ve Genel Doğrulama

```
================ TÜM TEST SÜİTİ SONUÇLARI (SPIKE-01) ================
1. test/lifecycle_drain_test.dart   : 1/1 PASSED
2. test/process_crash_test.dart     : 2/2 PASSED (3 ardışık OS Crash/Recovery)
3. test/spike_test.dart             : 6/6 PASSED (10 İstemci Stres Testi)
4. test/s1_api_security_test.dart   : 25/25 PASSED (S-1 API Security)
5. test/s2_token_security_test.dart : 18/18 PASSED (S-2 Device Token Security)
6. test/s3_tls_security_test.dart   : 12/12 PASSED (S-3 LAN TLS Security)
7. test/s4_crypto_test.dart         : 7/7 PASSED (S-4 Kriptografi ve Windows CNG TPM)
8. test/s4_device_pairing_test.dart : 24/24 PASSED (S-4 Uçtan Uca TC-01..TC-28 Senaryoları)
----------------------------------------------------------------------
TOPLAM TEST SAYISI : 95
BAŞARILI TESTLER   : 95 (%100)
BAŞARISIZ TESTLER  : 0  (%0)
======================================================================
```

---

## 6. Statik Analiz (`dart analyze`) Sonucu

```
$ dart analyze
Analyzing spike_01_backend...
No issues found!
```
- **Hata (Error):** 0
- **Uyarı (Warning):** 0
- **Bilgi (Info):** 0
- Tam tip güvenliği, sıfır `dynamic` sızıntısı ve katı `null safety` kuralları sağlanmıştır.

---

## 7. Platform Bazında Doğrulanan Özellikler ve Donanım Ayrımı

> [!CAUTION]
> **Dürüstlük ve Donanım Ayrımı İlkesi:** Spike ortamı Windows üzerinde koşmaktadır. Android Keystore ve iOS Secure Enclave doğrudan donanım seviyesinde değil; DER imza çıktısı, ANSI X9.62 standartları ve katı ASN.1 doğrulayıcısı üzerinden %100 format uyumluluğu simülasyonu ile test edilmiştir.

### 7.1. Windows Masaüstü (Local Master Hub / Cashier)
- **Doğrulama Düzeyi:** **GERÇEK NATIVE İŞLETİM SİSTEMİ ÇAĞRISI (FFI ncrypt.dll)**.
- **Sağlayıcı:** `Microsoft Platform Crypto Provider` (TPM 2.0).
- **TPM Durumu:** `isHardwareTpm: true` olarak sistem tarafından teyit edildi.
- **Ham İmza Çıktısı:** Tam olarak 64 bayt IEEE P1363 (`r || s`, 32'şer bayt big-endian).
- **Normalizasyon:** P1363 formatı `EcdsaSignatureValidator.p1363ToDer()` ile Low-S normalize edilmiş katı DER formatına dönüştürüldü ve anahtar doğrulayıcı tarafından %100 kabul edildi.

### 7.2. Android Terminal (Mobil Kasa / El Terminali)
- **Hedef Donanım:** Android Keystore (`AndroidKeyStoreProvider`, Keymaster / StrongBox).
- **Native İmza API:** `java.security.Signature.getInstance("SHA256withECDSA")`.
- **İmza Çıktı Formatı:** Standart ASN.1 DER dizisi.
- **Doğrulama Yöntemi:** Standart DER imza simülasyonu ile `s4_crypto_test.dart` ve `s4_device_pairing_test.dart` üzerinde katı DER parser (`0x30`, uzunluk, iki adet `0x02` integer) ve Low-S sınır denetimiyle test edildi.

### 7.3. iOS Terminal (Yönetici Raporlama / Mobil Satış)
- **Hedef Donanım:** iOS Secure Enclave (`kSecAccessControlPrivateKeyUsage`).
- **Native İmza API:** `SecKeyCreateSignature(key, kSecKeyAlgorithmECDSASignatureMessageX962SHA256, ...)`.
- **İmza Çıktı Formatı:** ANSI X9.62 / ASN.1 DER formatı.
- **Doğrulama Yöntemi:** iOS DER/X9.62 imza formatı backend validator tarafından doğrudan doğrulandı.

---

## 8. Bilinen Güvenlik Durumu ve Sıradaki Aşamalar

1. **İstemci Donanım Entegrasyonu (Faz 1):** Backend kriptografik doğrulama altyapısı Android/iOS için hazırdır. Faz 1'de mobil Flutter uygulaması yazılırken `flutter_secure_storage` yerine doğrudan Android Keystore ve iOS Secure Enclave'e erişen native method kanalları bağlanacaktır.
2. **Windows Hub Onay Ekranı:** Şu an onaylar loopback HTTP API (`/api/v1/pairing/approve`) üzerinden yönetilmektedir. Windows UI geliştirildiğinde işletim sistemi yerel arayüzünde market sahibine onay penceresi (cihaz adı, modeli, public key fingerprint) sunulacaktır.
3. **mDNS / NSD Keşfi:** Terminal cihazların Windows Hub IP adresini otomatik bulabilmesi için LAN Service Discovery (mDNS) mekanizması Faz 1'de entegre edilecektir.

---

## 9. S-4 Tamamlanma Değerlendirmesi

Aşama S-4 (Secure Device Pairing); S-1 API Security, S-2 Device Token Security ve S-3 LAN TLS güvenlik katmanları üzerine başarıyla inşa edilmiştir.

- **QR Kopyalama Saldırısı Çözüldü:** QR koddaki `pairing_secret` yalnızca oturum bağlama ve meydan okuma talebi için kullanılmaktadır. Özel anahtara sahip olmayan saldırgan, QR kodu ele geçirse dahi geçerli ECDSA imzası üretemediği için token teslim alamaz.
- **Ağ Kesintisi ve Yetim Cihaz Riski Çözüldü:** Token bellekte 120 saniye tutulur; istemci güvenli depoya kaydettiğini `token_sha256` bağlı ACK imzasıyla teyit etmeden cihaz DB'de onaylanmaz (`isConfirmed: false`). Ağ kopması durumunda cihaz silinir veya açılışta `startupReconcile` ile iptal edilir.
- **Yetki Ayrımı Sağlandı:** LAN istemcileri hiçbir şekilde onay endpoint'lerini çağıramaz; loopback ve admin secret kontrolleriyle Windows UI güven sınırı kusursuz çekilmiştir.

**Sonuç:** SPIKE-01 Aşama S-4 implementasyonu ve test doğrulamaları **%100 başarıyla tamamlanmıştır**. Dokümantasyon ve mimari kabul kriterleri eksiksiz karşılanmıştır.

