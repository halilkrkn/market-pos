# MARKET MMS — SPIKE-01: Aşama S-2 (Device Token Security) Uygulama ve Doğrulama Raporu

**Tarih:** 5 Kasım 2026  
**Proje:** Market Management System (MMS) — Local Master Hub Backend Spike (SPIKE-01)  
**Kapsam:** `test_spikes/spike_01_backend/`  
**Referans Plan:** `test_spikes/spike_01_backend/SECURITY_REMEDIATION_PLAN.md` (Rev. 3)  
**Uygulanan Standartlar:** Clean Architecture, TDD (`test-first`), `code-quality`, `systematic-debugging`, `documentation`

---

## 1. Yönetici Özeti

`SECURITY_AUDIT_REPORT.md` denetiminde tespit edilen yüksek riskli bulgular doğrultusunda, istemci cihazların (Windows Kasa, Android El Terminali, iOS Raporlama) Windows Local Master Hub ile haberleşmesinde kullanılan **Device Token** mimarisi uçtan uca kriptografik güvenlik standartlarına kavuşturulmuştur.

Önceki prototipte açık metin (plaintext) olarak SQLite `devices.token` tablosunda saklanan, zayıf entropili (`Random()`) üretilen ve çalınması durumunda iptal/yenileme mekanizması bulunmayan yapı tamamen tasfiye edilmiştir. Yerine; 256-bit CSPRNG entropili token üretimi, cihaz bazında benzersiz 128-bit salt, sunucu bazında Windows DPAPI ile korunan 256-bit pepper, SHA-256 özetleme, sabit zamanlı (constant-time) doğrulama, atomik token yenileme ve kalıcı denetim (audit log) altyapısı getirilmiştir.

TDD metodolojisiyle hazırlanan **20/20 yeni doğrulama senaryosu** ve projenin mevcut tüm test paketleri (toplam **50/50 test**) sıfır hata ve sıfır regresyonla doğrulanmıştır.

---

## 2. DPAPI Implementasyon Detayları (Win32 Crypt32 & Kernel32 FFI)

Windows Local Master Hub mimarisinde sunucu genelindeki sır olan `pepper` (biber) değerinin güvenliğini sağlamak için Windows Data Protection API (DPAPI) implemente edilmiştir. Harici paket bağımlılığı (`pubspec.yaml` şişmesi) oluşturmamak adına, Dart'ın yerel FFI (`dart:ffi`) yeteneği kullanılarak Win32 API'leri doğrudan bağlanmıştır.

### 2.1 Bağlanan Win32 API Fonksiyonları
- **`Crypt32.dll`**:
  - `CryptProtectData`: Bellekteki düz metin veriyi DPAPI ile şifreler.
  - `CryptUnprotectData`: DPAPI ile şifrelenmiş bayt dizisini çözer.
- **`Kernel32.dll`**:
  - `LocalAlloc`: Win32 unmanaged heap üzerinde `DATA_BLOB` bellek alanı tahsis eder.
  - `LocalFree`: Bellek sızıntılarını önlemek için tahsis edilen unmanaged belleği serbest bırakır.

### 2.2 Güvenlik Bayrakları ve Kapsam Seçimi
```dart
// Windows DPAPI Bayrakları:
// CRYPTPROTECT_LOCAL_MACHINE (0x04): DPAPI anahtarını makine seviyesinde kilitler.
// Windows Service (LocalService / SYSTEM) hesabı altında çalışırken çözülebilirliği garanti eder.
// CRYPTPROTECT_UI_FORBIDDEN (0x01): GUI uyarı/onay kutularının açılmasını yasaklar (headless servis uyumu).
```

### 2.3 Pepper Yaşam Döngüsü ve Hata Yönetimi (`PepperManager`)
- **Yeni Kurulum:** İlk başlangıçta diskte pepper dosyası (`pepper.dpapi`) yoksa, 256-bit (32 byte) kriptografik rastgele bayt üretilir (`Random.secure()`). Bu değer DPAPI `CryptProtectData` ile şifrelenir ve diske atomik yazılır.
- **Servis Başlangıcı:** Servis her başladığında diskteki şifreli dosya okunur ve DPAPI `CryptUnprotectData` ile çözülerek RAM belleğinde tutulur.
- **Bozulma ve Şifre Çözülememe Durumu:** Pepper dosyası manipüle edilmişse, bozulmuşsa veya başka bir makineden kopyalanmışsa `PepperSecurityException` fırlatılır. **Asla açık metin fallback veya varsayılan bir parola oluşturulmaz; servis güvenli biçimde başlamayı reddeder.**

İlgili kaynak kod: [`lib/security/dpapi.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/dpapi.dart), [`lib/security/pepper_manager.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/pepper_manager.dart).

---

## 3. Token Üretim, Salt/Pepper ve Hash Mimarisi

Cihaz belirteçleri aşağıdaki kriptografik tasarım ilkeleriyle yeniden yapılandırılmıştır:

```
[İstemci Cihaz]
      │ (Bearer mms_dt_<Base64URL_256bit>)
      ▼
[Master Hub RAM]
      │
      ├─► rawToken (256-bit CSPRNG)
      ├─► salt     (128-bit hex - DB'den)
      └─► pepper   (256-bit - DPAPI'den)
            │
            ▼
   SHA-256(rawToken : salt : pepper)
            │
            ▼ candidateHash
            │
      [Constant-Time Equality Check] ◄─── DB: tokenHash
            │
      ┌─────┴─────┐
      ▼           ▼
   (Eşleşti)   (Eşleşmedi)
     200 OK      401 Unauthorized
```

### 3.1 Token Formatı (`TokenManager.generateToken`)
- **Entropi Kaynağı:** `Random.secure()` (İşletim sistemi CSPRNG: Windows `BCryptGenRandom` / `CryptGenRandom`).
- **Entropi Büyüklüğü:** 256 bit (32 byte).
- **Format:** `mms_dt_` + Base64URL (padding-free, 43 karakter URL-safe).
- **Tahmin Edilemezlik:** $2^{256}$ olası kombinasyon; kaba kuvvet (brute-force) veya tahmin saldırılarına karşı mutlak matematiksel direnç.

### 3.2 Benzersiz Cihaz Tuzu (`TokenManager.generateSalt`)
- Her cihaz kaydında bağımsız 128 bitlik (16 byte) rastgele tuz üretilir ve 32 karakterlik hex dizesi olarak saklanır.
- Önceden hesaplanmış gökkuşağı tabloları (rainbow tables) ve cihazlar arası toplu parola kırıcıları tamamen etkisiz kılınmıştır.

### 3.3 Sabit Zamanlı Karşılaştırma (`TokenManager.constantTimeEquals`)
Zamanlama analizi (timing attacks) ile token karakterlerinin sırayla tahmin edilmesini engellemek için Dart API seviyesinde XOR tabanlı sabit zamanlı karşılaştırıcı uygulanmıştır:
```dart
static bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var result = 0;
  for (var i = 0; i < a.length; i++) {
    result |= a[i] ^ b[i];
  }
  return result == 0;
}
```

---

## 4. Veritabanı Şema Değişiklikleri (`database.dart`)

Drift SQLite şeması, token güvenliği ve denetim izlenebilirliği gereksinimlerine göre güncellenmiştir.

### 4.1 `devices` Tablosundaki Değişiklikler
- **Kaldırılan Sütun:**
  - `token` (Text) — **Açık metin token sütunu SQLite veritabanından tamamen silinmiştir.**
- **Eklenen Sütunlar:**
  - `tokenHash` (Text): SHA-256(rawToken:salt:pepper) özet değeri.
  - `salt` (Text): Cihaza özel 128-bit hex tuzu.
  - `lastUsedAt` (DateTime, nullable): Cihazın Master Hub'a son başarılı istek attığı zaman damgası.
  - `expiresAt` (DateTime, nullable): Belirteç son geçerlilik tarihi (opsiyonel oturum sınırlaması).
  - `role` (Text): Cihaz rolü (`CASHIER`, `ADMIN`, `TERMINAL`).

### 4.2 Yeni Tablo: `device_audit_logs`
Cihazların yaşam döngüsündeki kritik güvenlik hareketlerini (kayıt, yenileme, yetki iptali) izlemek üzere denetim defteri tablosu oluşturulmuştur:
- `id` (Integer, autoIncrement, Primary Key)
- `deviceId` (Text): İşlem gören cihazın tekil kimliği
- `action` (Text): `REGISTER`, `RENEW`, `REVOKE`
- `details` (Text, nullable): Olay detayı (**kesinlikle açık token veya hash içermez**)
- `createdAt` (DateTime): İşlem zamanı

İlgili kaynak kod: [`lib/db/database.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/db/database.dart).

---

## 5. Güvenlik Endpoint ve Yetkilendirme Değişiklikleri

### 5.1 Cihaz Kaydı (`POST /api/v1/devices/register`)
- Eşleştirme (pairing) anında sunucu 256-bit güvenli token ve benzersiz salt üretir.
- SQLite'a yalnızca `tokenHash` ve `salt` kaydedilir.
- Üretilen token istemciye yanıt olarak **yalnızca bir defa** döner.
- `device_audit_logs` tablosuna `REGISTER` eylemi yazılır.

### 5.2 Atomik Token Yenileme (`POST /api/v1/devices/renew-token`)
- Yalnızca geçerli Bearer token'a sahip cihazlar tarafından çağrılabilir.
- Yeni 256-bit token ve yeni salt üretilir.
- Yazıcı kuyruğu (`writeQueue`) içinde atomik olarak `tokenHash` ve `salt` güncellenir.
- Eski token anında geçersiz kılınır; tekrar kullanılamaz (tek seferlik oturum güvencesi).
- `device_audit_logs` tablosuna `RENEW` eylemi yazılır.
- İstemciye yeni token döner.

### 5.3 Cihaz İptali (`POST /api/v1/devices/revoke`)
- Yönetici yetkilendirmesi (`X-Admin-Secret`) veya loopback yönetim bağlamı gerektirir.
- Normal kasa token'ları cihaz iptal etme yetkisine sahip değildir.
- Cihazın `is_active` durumu `false` yapılır.
- `device_audit_logs` tablosuna iptal gerekçesiyle birlikte `REVOKE` eylemi yazılır.
- İptal edilen cihazın bir sonraki tüm istekleri **403 Forbidden (`DEVICE_REVOKED`)** ile anında engellenir.
- Zaten iptal edilmiş cihaz için mükerrer iptal isteği 400 `ALREADY_REVOKED` ile reddedilir.

---

## 6. Güvenlik Tehdit Analizleri

| Tehdit Modeli | Eski Durum (Zafiyet) | S-2 Sonrası Güvenlik Seviyesi |
|---|---|---|
| **SQLite DB Çalınması / Sızıntısı** | Saldırgan `spike_master.db` dosyasını çaldığında tüm cihaz token'larına düz metin erişir ve sahte satış yapabilirdi. | **Sıfır İhlal:** Veritabanında açık token yoktur. Hash'lerin kırılması için diskte ayrı saklanan ve Windows DPAPI LocalMachine ile şifreli `pepper` sırrına erişilmesi şarttır. |
| **Gökkuşağı Tabloları (Rainbow Tables)** | Sabit veya tuzsuz hash'ler önceden hesaplanmış tablolarla kırılabilirdi. | **Tamamen Engellendi:** Her cihaz için 128-bit rastgele salt kullanıldığından rainbow table saldırıları matematiksel olarak imkansızdır. |
| **Brute-Force & Sözlük Saldırıları** | Zayıf PIN veya tahmin edilebilir token'lar brute-force ile bulunabilirdi. | **$2^{256}$ Kombinasyon:** Token alanı 256 bit CSPRNG entropisine sahiptir; sözlük saldırısı yapılamaz. |
| **Zamanlama Analizi (Timing Attacks)** | String eşitlik operatörü (`==`) karakter karakter karşılaştırıp ilk uyumsuzlukta durarak token'ın adım adım tahminine yol açabilirdi. | **Sabit Zamanlı XOR:** `TokenManager.constantTimeEquals` boyutu kontrol edip tüm baytları XOR'layarak sabit sürede çalışır; sızıntı sıfırdır. |
| **Çalınan Cihazın Ağa Erişimi** | Token iptal edilemiyordu; çalınan cihaz Master Hub'a satış basabilirdi. | **Anında Bloklama:** `POST /api/v1/devices/revoke` ile anında `isActive=false` yapılır ve HTTP 403 döner. |
| **Log ve Hata Sızıntısı** | İstek başlıkları veya stack trace loglara açık token basabilirdi. | **Maskeleme:** HTTP 500 yanıtları sterilize edilmiştir; denetim loglarında ve hata metinlerinde token geçmez. |

---

## 7. 20 Test Senaryosu Doğrulama Sonuçları

`test/s2_token_security_test.dart` dosyasında uygulanan 20 güvenlik senaryosunun tamamı başarıyla geçmiştir:

```
00:00 +0: S-2 Device Token Security 20 Doğrulama Senaryosu 1. Token güvenli şekilde üretiliyor (256 bit entropi, CSPRNG)
00:00 +1: S-2 Device Token Security 20 Doğrulama Senaryosu 2. Üretilen token yeterli rastgeleliğe sahip (alfanümerik base64url)
00:00 +2: S-2 Device Token Security 20 Doğrulama Senaryosu 3. Aynı cihaz için art arda üretilen tokenlar birbirinden farklı
00:00 +3: S-2 Device Token Security 20 Doğrulama Senaryosu 4. SQLite veritabanı içerisinde AÇIK METİN TOKEN BULUNMUYOR
00:00 +4: S-2 Device Token Security 20 Doğrulama Senaryosu 5. Salt her cihaz bazında birbirinden farklı ve benzersizdir
00:00 +5: S-2 Device Token Security 20 Doğrulama Senaryosu 6. Doğru token ile korumalı API çağrısı kabul edilmelidir (200 OK)
00:00 +6: S-2 Device Token Security 20 Doğrulama Senaryosu 7. Yanlış token ile istek yapıldığında 401 Unauthorized dönmelidir
00:00 +7: S-2 Device Token Security 20 Doğrulama Senaryosu 8. İptal edilmiş (revoked) cihaz tokenı ile istek yapıldığında 403 Forbidden dönmelidir
00:00 +8: S-2 Device Token Security 20 Doğrulama Senaryosu 9. Süresi dolmuş (expired) token ile istek yapıldığında 401 Unauthorized dönmelidir
00:00 +9: S-2 Device Token Security 20 Doğrulama Senaryosu 10. Token yenileme (renew) işlemi başarıyla çalışmalı ve yeni token dönmelidir
00:01 +10: S-2 Device Token Security 20 Doğrulama Senaryosu 11. Eski token yenileme sonrasında kesinlikle KULLANILAMAZ olmalıdır (401)
00:01 +11: S-2 Device Token Security 20 Doğrulama Senaryosu 12. Eski tokenla yenileme işlemi tekrarlandığında ikinci token üretilmemelidir
00:01 +12: S-2 Device Token Security 20 Doğrulama Senaryosu 13. Token iptal (revoke) işlemi doğru çalışmalı ve audit kaydı oluşmalıdır
00:01 +13: S-2 Device Token Security 20 Doğrulama Senaryosu 14. İptal edilmiş token tekrar etkinleştirilemez olmalıdır
00:01 +14: S-2 Device Token Security 20 Doğrulama Senaryosu 15. Pepper Windows DPAPI LocalMachine üzerinden güvenli şekilde şifrelenip çözülüyor
00:01 +15: S-2 Device Token Security 20 Doğrulama Senaryosu 16. Bozuk veya çözülemeyen pepper dosyasında servis güvenli biçimde başlamayı REDDETMELİDİR
00:01 +16: S-2 Device Token Security 20 Doğrulama Senaryosu 17. Token ve Pepper hiçbir log veya hata çıktısında sızmamalıdır
00:01 +17: S-2 Device Token Security 20 Doğrulama Senaryosu 18. Mevcut S-1 API hardening kontrolleri çalışmaya devam etmelidir (Gövde sınırı, CORS, Shutdown)
00:01 +18: S-2 Device Token Security 20 Doğrulama Senaryosu 19. Eşzamanlı token yenileme ve satış istekleri veri tutarlılığını korumalıdır
00:01 +19: S-2 Device Token Security 20 Doğrulama Senaryosu 20. Uygulama yeniden başlatıldığında şifrelenmiş token doğrulaması kesintisiz çalışmalıdır
00:01 +20: All tests passed!
```

---

## 8. Genel Test Paketi Regresyon Denetimi (50/50 Test)

S-2 geliştirmelerinin önceki fazlarda inşa edilen mimariyi ve API sertleştirmelerini bozmadığını doğrulamak amacıyla `test_spikes/spike_01_backend/test/` altındaki tüm test dosyaları paralel ve ardışık olarak koşturulmuştur:

| Test Paketi | Kapsam | Test Sayısı | Durum |
|---|---|---|---|
| `s2_token_security_test.dart` | S-2 Token Güvenliği, DPAPI, Hash, Audit | 20 | **BAŞARILI** (0 hata) |
| `s1_api_hardening_test.dart` | S-1 Body Limit, CORS, Backup SQLi, Shutdown Loopback | 13 | **BAŞARILI** (0 hata) |
| `spike_test.dart` | SPIKE-01 Temel İşlevler, WAL, İdempotency, Stres | 11 | **BAŞARILI** (0 hata) |
| `shutdown_regression_test.dart` | Windows Service Graceful Shutdown (< 150 ms) | 3 | **BAŞARILI** (0 hata) |
| `process_crash_test.dart` | İşletim Sistemi Seviyesinde SIGKILL & WAL Recovery | 2 | **BAŞARILI** (0 hata) |
| `lifecycle_drain_test.dart` | WriteQueue Draining ve HTTP 503 İzolasyonu | 1 | **BAŞARILI** (0 hata) |
| **TOPLAM** | **SPIKE-01 Backend Süitinin Tamamı** | **50** | **%100 BAŞARILI** |

`dart analyze` denetiminde `test_spikes/spike_01_backend` genelinde **0 issue** (sıfır uyarı/hata) bildirilmiştir.

---

## 9. Dosya Değişiklikleri Özeti

| Dosya | Durum | İşlem Özeti |
|---|---|---|
| [`lib/security/dpapi.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/dpapi.dart) | Yeni | Win32 Crypt32 / Kernel32 FFI DPAPI protect/unprotect implementasyonu |
| [`lib/security/pepper_manager.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/pepper_manager.dart) | Yeni | DPAPI şifreli dosya yaşam döngüsü, bozulma reddi |
| [`lib/security/token_manager.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/token_manager.dart) | Yeni | 256-bit CSPRNG token, salt, SHA-256 hash ve sabit zamanlı doğrulama |
| [`lib/db/database.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/db/database.dart) | Güncellendi | `Devices.token` kaldırıldı; `tokenHash`, `salt` eklendi; `DeviceAuditLogs` tablosu eklendi |
| [`lib/db/database.g.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/db/database.g.dart) | Yenilendi | Drift code-generation çalıştırıldı |
| [`lib/security/auth_middleware.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/auth_middleware.dart) | Güncellendi | Hash/salt/pepper doğrulama, `DEVICE_REVOKED`, `TOKEN_EXPIRED` ve `lastUsedAt` güncellemeleri |
| [`bin/server.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart) | Güncellendi | `renew-token` ve `revoke` endpoint'leri, `register` hashleme, DPAPI pepper başlatma |
| [`test/s2_token_security_test.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/test/s2_token_security_test.dart) | Yeni | 20 senaryolu TDD doğrulama paketi |
| Diğer Test Dosyaları (`spike_test`, `s1_api`, `crash`, `shutdown`, `drain`) | Güncellendi | Yeni `DevicesCompanion` (hash/salt) şemasına ve port izolasyonuna uyarlandı |

---

## 10. Kalan Güvenlik Aşamaları ve Yol Haritası

- **Aşama S-3: LAN TLS Security (Sıradaki Aşama)**
  - Yerel sertifika otoritesi (CA) veya self-signed sertifika mekanizması.
  - Dart Shelf HTTP sunucusunun `SecurityContext` ile TLS 1.3 HTTPS moduna geçirilmesi.
  - Android, iOS ve Windows istemciler için yerel sertifika pinleme (certificate pinning).
- **Aşama S-4: Windows Service & OS Hardening**
  - Servis hesabının `LocalSystem` yerine kısıtlı `LocalService` hesabına taşınması.
  - SQLite ve Pepper dosyaları için Windows NTFS ACL kısıtlamaları (`icacls`).
  - Windows Güvenlik Duvarı (Windows Firewall) kural optimizasyonu.
- **Aşama S-5: Audit Logging & Monitoring**
  - Güvenlik ve denetim loglarının kalıcı Windows Event Log veya rotasyonlu dosyalara yazılması.

---

> [!NOTE]
> Bu aşamada çalışan `MarketMmsSpike01` Windows servisine hiçbir müdahale yapılmamış, ana MMS uygulaması etkilenmemiş ve `test_spikes/spike_01_backend/` sınırları titizlikle korunmuştur. Proje **Aşama S-3: LAN TLS Security** için tamamen hazırdır.

