# PHASE 1.3.1.0 — WINDOWS HUB AUTHENTICATION VE HTTPS/TLS TASARIM İNCELEMESİ

**Belge Kimliği:** `PHASE_1_3_1_AUTH_TLS_DESIGN.md`  
**Tarih:** 15 Kasım 2026 (Revizyon: 03:15 — D1 Drift customUpdate Pozisyonel ? Değişken Eşleşmesi ve D3 pairing_secret & POST /api/v1/pairing/request Kod Uyumu)  
**Aşama:** Faz 1.3.1.0 — Güvenlik ve İletişim Temeli (Faz 1.3.1 Outbox & Arka Plan Senkronizasyonu Ön Koşulu)  
**İnceleme Türü:** Salt Okunur (Read-Only) Mimari, Güvenlik ve Tasarım Raporu  
**Referanslar:** [`AGENTS.md`](file:///c:/Users/halil/Github/market-pos/AGENTS.md) (Bölüm 2, 4, 5, 6), [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](file:///c:/Users/halil/Github/market-pos/MARKET_POS_AI_STUDIO_BUILD_PLANI.md) (v1.4, S5A serisi), [`PHASE_1_3_1_SYNC_TECHNICAL_ASSESSMENT.md`](file:///c:/Users/halil/Github/market-pos/docs/development/PHASE_1_3_1_SYNC_TECHNICAL_ASSESSMENT.md), [`PHASE_1_3_1_SYNC_DESIGN_DECISIONS_REVIEW.md`](file:///c:/Users/halil/Github/market-pos/docs/development/PHASE_1_3_1_SYNC_DESIGN_DECISIONS_REVIEW.md)

---

## 1. Mevcut Mimarinin Doğrulanmış Durumu

Proje anayasası ([`AGENTS.md`](file:///c:/Users/halil/Github/market-pos/AGENTS.md)) ve kod tabanında yapılan statik analiz sonucunda, Windows Local Master Hub ile Flutter masaüstü istemcisi arasındaki doğrulanmış mevcut durum aşağıdaki gibidir:

### 1.1. İstemci Tarafı (Windows Flutter UI — `market-pos`)
- **API İstemcisi:** [`lib/core/network/api_client.dart`](file:///c:/Users/halil/Github/market-pos/lib/core/network/api_client.dart#L13-L38) sınıfında `deviceToken` alanı bulunmaktadır; ancak [`apiClientProvider`](file:///c:/Users/halil/Github/market-pos/lib/features/diagnostics/application/system_status_notifier.dart#L9-L14) bu alanı `null` olarak başlatmaktadır.
- **Protokol:** [`lib/core/constants/app_constants.dart`](file:///c:/Users/halil/Github/market-pos/lib/core/constants/app_constants.dart#L7-L9) içinde `defaultBackendBaseUrl` değeri `http://127.0.0.1:8080` (şifresiz düz HTTP) olarak tanımlıdır.
- **Token ve Sertifika Depolama:** İstemci tarafında token saklamak veya Root CA doğrulamak için hiçbir kalıcı güvenli depolama mekanizması (DPAPI, Windows Credential Manager vb.) bulunmamaktadır.
- **Outbox Hata Sınıflandırması:** [`packages/mms_client_storage/lib/src/sync/client_sync_service.dart`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/sync/client_sync_service.dart#L120-L149) satır 142 gereğince, HTTP 401 veya 403 yanıtları geçici hata (`isTransientError`) kabul edilmemekte; doğrudan **kalıcı hata (`FAILED_PERMANENT`)** olarak işlenip **tüm kuyruğu kilitlemektedir**.

### 1.2. Sunucu Tarafı (Windows Local Master Hub — `test_spikes/spike_01_backend`)
- **Kimlik Doğrulama Middleware:** [`test_spikes/spike_01_backend/lib/security/auth_middleware.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/auth_middleware.dart#L51-L159), `/health` dışındaki tüm uç noktalarda (`POST /api/v1/sales` dahil) geçerli bir `Authorization: Bearer <token>` başlığı aramaktadır.
- **Token Doğrulama:** [`TokenManager.verifyToken`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/token_manager.dart#L46-L62), gelen Bearer token'ı sunucu `pepper`'ı ve cihaz `salt`'ı ile $\text{SHA-256}$ özetine tabi tutarak veritabanındaki (`db.devices`) aktif cihazlarla sabit zamanlı (`constantTimeEquals`) karşılaştırmaktadır. Eşleşme yoksa `401 Unauthorized (DEVICE_NOT_FOUND)` dönmektedir.
- **Loopback Koruması:** [`server.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart#L130-L175) üzerindeki `_verifyLoopbackAndAdmin` metodu, yönetimsel rotaları yalnızca `127.0.0.1` / `::1` loopback adresinden ve geçerli bir `x-admin-secret` ile kabul etmektedir.
- **TLS Altyapısı:** [`CertificateManager`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/certificate_manager.dart#L59-L158), OpenSSL kullanarak 10 yıllık Kök CA (`ca.crt`) ve 1 yıllık yaprak sunucu sertifikası (`server.crt`, SAN: `127.0.0.1`, `localhost`) üretebilmektedir.

> [!CRITICAL]
> **Mevcut Durum Çelişkisi:**  
> İstemci `http://` ve boş token ile çalışmakta; sunucu ise `POST /api/v1/sales` için geçerli Bearer token zorunlu tutmaktadır. Şu anki kod tabanında senkronizasyon tetiklendiği an, Hub `401` dönecek ve `ClientSyncService` işlemi kalıcı hata (`FAILED_PERMANENT`) sayarak Outbox kuyruğunu tamamen donduracaktır. Bu nedenle Faz 1.3.1 senkronizasyonundan önce **Cihaz Yetkilendirme** ve **HTTPS/TLS Temeli** çözülmek zorundadır.

---

## 2. Cihaz Bootstrap ve İlk Yetkilendirme Akışı (OD-SEC-01)

### 2.1. Tasarım Kararı: Tek Kullanımlık Kriptografik Bootstrap Anahtarı (OD-SEC-01)
Windows masaüstü istemcisi ile Hub aynı fiziksel makinede (Windows Local Master Hub) çalışsa dahi, arayüz sunucu veritabanına doğrudan bağlanamaz. İlk cihaz kaydı için **Tek Kullanımlık Kriptografik Bootstrap Anahtarı (One-Time Cryptographically Secure Bootstrap Secret)** standardı benimsenmiştir.

```
┌───────────────────────────────────────┐          ┌───────────────────────────────────────┐
│         Windows Flutter UI            │          │         Windows Master Hub            │
│          (market_pos.exe)             │          │          (mms_backend.exe)            │
└───────────────────┬───────────────────┘          └───────────────────┬───────────────────┘
                    │                                                  │
                    │ 1. Token Yok / İlk Kurulum Tespiti              │ Hub Kurulumu / İlk Servis Başlatma:
                    │    (device_token.dpapi bulunamadı)               │ - Cryptographically secure 256-bit key
                    │                                                  │ - Hash db.bootstrap_keys tablosuna
                    │                                                  │ - Ham anahtar %PROGRAMDATA%\MarketMMS\setup\
                    │                                                  │   bootstrap.key dosyasına (ACL: SYSTEM)
                    │                                                  │
                    │ 2. Kök CA'yı Diskten Oku (OD-SEC-02)            │
                    │    %PROGRAMDATA%\MarketMMS\certs\ca.crt          │
                    │                                                  │
                    │ 3. POST /api/v1/devices/local-bootstrap          │
                    │    Headers: x-bootstrap-secret: <key>            │
                    │    Body: { device_id: 'POS-WIN-01', role: 'pos' }│
                    │    [SADECE LOOPBACK 127.0.0.1 + HTTPS]           │
                    ├─────────────────────────────────────────────────>│
                    │                                                  │ 4. Loopback (127.0.0.1) Doğrulaması
                    │                                                  │ 5. SHA-256(secret + salt + pepper)
                    │                                                  │ 6. db.bootstrap_keys: is_used == false?
                    │                                                  │ 7. Transaction İçinde:
                    │                                                  │    - TokenManager.generateToken()
                    │                                                  │    - db.devices INSERT (Active, Confirmed)
                    │                                                  │    - db.bootstrap_keys UPDATE is_used=true
                    │                                                  │    - bootstrap.key DOSYASINI DİSKTEN SİL
                    │    201 Created:                                  │
                    │    { device_id, raw_token, expires_at: null }    │
                    │<─────────────────────────────────────────────────┤
                    │                                                  │
                    │ 8. Windows DPAPI (CurrentUser) ile Şifrele       │
                    │    %LOCALAPPDATA%\MarketMMS\device_token.dpapi   │
                    │                                                  │
                    │ 9. Outbox Senkronizasyonu Başlatılır             │
                    │    (Authorization: Bearer <token>)               │
                    ▼                                                  ▼
```

### 2.2. Bootstrap Anahtarının Güvenlik Yaşam Döngüsü

1. **Üretim (Generation):**
   - Hub servisinin kurulum aşamasında veya ilk ayağa kalkışında `Random.secure()` kullanılarak URL-safe Base64 formatında 256-bit entropiye sahip tek kullanımlık bir anahtar üretilir (`mms_boot_...`).
2. **Saklama (Storage):**
   - **Veritabanı:** Hub ham anahtarı veritabanında **ASLA DÜZ METİN OLARAK SAKLAMAZ**. Cihaz token'larında olduğu gibi $\text{SHA-256}(\text{rawKey} + \text{salt} + \text{pepper})$ özeti hesaplanarak `bootstrap_keys` tablosuna `is_used = FALSE`, `created_at = NOW()`, `expires_at = NOW() + 24_HOURS` alanlarıyla kaydedilir.
   - **Dosya Sistemi (Geçici):** Kurulum sihirbazının veya yetkili yöneticinin anahtarı okuyabilmesi için ham anahtar tek seferlik `%PROGRAMDATA%\MarketMMS\setup\bootstrap.key` dosyasına yazılır.
   - **NTFS ACL Koruması:** Bu dosyanın erişim izinleri Windows Access Control List (ACL) ile sınırlandırılır: Yalnızca `NT AUTHORITY\SYSTEM` ve `BUILTIN\Administrators` tam yetkiye sahiptir. Standart masaüstü kullanıcıları (Kasiyer hesapları) bu dosyayı doğrudan okuyamaz.
3. **Gösterim (Display):**
   - Anahtar, kurulumu gerçekleştiren yöneticiye kurulum konsolunda veya yönetici kurulum sihirbazında bir kez gösterilir.
4. **Tek Kullanımlık Tüketim (Single-Use Consumption):**
   - İstemci `POST /api/v1/devices/local-bootstrap` rotasına bu anahtarı `x-bootstrap-secret` başlığı ile iletir.
   - Hub, gelen anahtarı hash'leyerek veritabanında doğrular. `is_used == FALSE` ve `expires_at > NOW()` şartları sağlandığında:
     - Tek bir yerel SQLite transaction'ı içinde:
       - Cihaz için kalıcı `device_id`, salt ve Bearer token üretilip `devices` tablosuna yazılır.
       - `bootstrap_keys` kaydı `is_used = TRUE`, `used_at = NOW()`, `used_by_device = 'POS-WIN-01'` olarak güncellenir.
     - Disk üzerindeki geçici `%PROGRAMDATA%\MarketMMS\setup\bootstrap.key` dosyası anında kalıcı olarak silinir (`File.deleteSync()`).
5. **Yetkisiz Erişim ve Tekrar Kullanım Koruması (Replay & Brute-Force Protection):**
   - **Ağ İzolasyonu:** Bu rota dış ağa (LAN / Wi-Fi) tamamen kapalıdır. İstek `127.0.0.1` veya `::1` loopback dışından gelirse Hub `403 FORBIDDEN (ERR_LOOPBACK_REQUIRED)` döner.
   - **Brute-Force Koruması:** 3 hatalı denemeden sonra Hub bu rotayı 15 dakika boyunca geçici olarak kilitler (`429 TOO_MANY_REQUESTS`).
   - **Tekrar Kullanım Engeli:** Tüketilmiş bir anahtarla yapılan sonraki tüm çağrılar `403 FORBIDDEN (BOOTSTRAP_KEY_ALREADY_USED)` ile anında reddedilir.

### 2.3. Standart Windows Kullanıcısına Güvenli Anahtar Aktarımı

> [!WARNING]
> **ACL Sorunu — Standart Kullanıcı Bootstrap Dosyasını Okuyamaz:**  
> Bootstrap anahtarı `%PROGRAMDATA%\MarketMMS\setup\bootstrap.key` konumunda, yalnızca `SYSTEM` ve `BUILTIN\Administrators`'ın erişebildiği bir dosyada durur. Windows Kasa UI (`market_pos.exe`) standart `Kasiyer` kullanıcısı altında çalıştığında bu dosyayı **doğrudan okuyamaz**. Anahtarı uygulamaya log, veritabanı veya açık metin yapılandırma dosyası üzerinden aktarmak güvenlik açığı oluşturur.

İki aşamalı güvenli aktarım tasarımı benimsenmiştir:

```
                    KURULUM AŞAMASI (Yönetici tarafından bir kez çalıştırılır)
                    ──────────────────────────────────────────────────────────
  Yönetici Kurulum   Hub Servisi ilk başladığında bootstrap.key dosyasını
  Konsolu/Sihirbazı  ACL korumalı konumda üretir. Yönetici kurulum konsolunu
  (Elevated / Admin) Admin olarak çalıştırır ve anahtar değerini ekranda görür.
         │
         │ Yönetici anahtarı güvenli kanal üzerinden
         │ Windows UI'ya girmek için kasada hazır bekler.
         ▼

                    BOOTSTRAP AŞAMASI (Windows Kasa UI ilk açıldığında)
                    ──────────────────────────────────────────────────────
  Windows Kasa UI    "Cihaz Yapılandırılmamış" ekranında yöneticinin
  (Standart Kullanıcı) verdiği anahtarı, güvenli parola alanına girer.
         │
         │ Anahtar yalnızca uygulama bellekte tutar.
         │ ASLA disk, log veya DB'ye yazılmaz.
         │
         ▼
  POST /api/v1/devices/local-bootstrap (127.0.0.1 — HTTPS)
  x-bootstrap-secret: <anahtar>  ──────────────────────────> Hub doğrular, token döner.
         │
         ▼
  Token DPAPI (CurrentUser) ile %LOCALAPPDATA%\...\device_token.dpapi
  Bootstrap ekranı kapanır, Outbox senkronizasyonu başlar.
```

**Aktarım Kuralları, Güvenli Bellek Yönetimi ve Yaşam Döngüsü Kısıtlaması (D7):**
- Anahtar hiçbir zaman disk dosyasına, `app_config.json`'a, Drift tablosuna veya Flutter `SharedPreferences`'a **yazılmaz**.
- **Gerçekçi Bellek Güvenliği ve Katman Analizi:**
  Dart ve Flutter çalışma zamanında mutlak bir bellek sıfırlaması (zeroization) garantisi vermek mimari olarak mümkün değildir. Çünkü:
  1. *Flutter UI & `TextEditingController`:* Kullanıcının parola alanına girdiği veri `TextEditingController` ve `EditableText` widget'ı içinde dahili olarak `String` biçiminde tutulur. Render ağacında ve text layout katmanında kontrol dışı String kopyaları oluşur.
  2. *Dart String İmmutability:* Dart dilinde `String` nesneleri değiştirilemezdir (immutable). `String.replaceAll()` gibi işlemler mevcut String'i RAM'den silemez; yalnızca yeni String üretir ve eski metin Garbage Collector (GC) serbest bırakana kadar RAM'de kalır.
  3. *HTTP İstek Gövdeleri:* Dart `HttpClient` / `Stream<List<int>>` ve JSON serileştirme katmanlarında istek gövdesi oluşturulurken geçici arabellekler (buffers) oluşturulur.
  4. *`Uint8List.fillRange()` Kapsamı:* İstemci tarafında `Uint8List` bayt dizisi kullanılarak `fillRange(0, secretBytes.length, 0)` çalıştırılması, **yalnızca kontrolümüz altındaki o spesifik bayt dizisini** sıfırlar; UI katmanı veya HTTP motorunun dahili String/byte kopyalarını sıfırlayamaz.
- **Benimsenen Mimari Yaklaşım:** Mutlak zeroization iddiası yerine, **hassas verinin bellekteki yaşam süresini ve ayak izini en aza indirme (Lifecycle Minimization & Defense-in-Depth)** prensibi benimsenmiştir:
  - Giriş controller'ı işlem biter bitmez derhal `.clear()` ve `.dispose()` edilir.
  - İletim baytları (`Uint8List`) HTTP isteği biter bitmez `fillRange` ile sıfırlanır.
  - Bootstrap anahtarı tüketildikten sonra tek kullanımlık yapısı gereği sunucu tarafından geçersiz kılındığı için bellekte kalıntı kalsa dahi yeniden kullanılamaz (Replay Immunity).
- Bootstrap sonrasında dosya Hub tarafından silinir. Standart kullanıcı başarılı aktarımdan sonra anahtara herhangi bir kanaldan ulaşamaz; bu güvenli aktarımın bozulmadığını doğrular.
- Yöneticiye gereksiz kalıcı admin yetkisi **verilmez**. Yönetici, kasada kurulum süreci için tek seferlik yükseltilmiş bir konsol çalıştırır; standart kullanıcı hesabı korunur.

### 2.4. Bootstrap Çökme Kurtarması (Crash Recovery)

> [!IMPORTANT]
> **Atomiklik Sınırı:**  
> SQLite transaction (`is_used = TRUE`) ve dosya silme (`File.deleteSync()`) işlemleri farklı alt sistemlere aittir. SQLite transaction commit edildikten sonra servis çökerse, dosya disk üzerinde kalabilir. Bu durum güvenlik açığı oluşturur: `is_used = TRUE` kayıtlı anahtar, diskteki ham dosya üzerinden anlaşılabilir.

Çökme kurtarma için 3 katmanlı koruma tasarlanmıştır:

**Katman 1 — Veritabanı `is_used` Bayrağı Birincil Korumadır:**
- Bootstrap anahtarı Hub veritabanında `is_used = TRUE` durumuna geçtiği anda, diskteki dosyanın varlığından bağımsız olarak **tüketilmiş sayılır**.
- Servis yeniden başlatıldığında, her çağrıda önce veritabanı sorgulanır. `is_used = TRUE` ise istek `403 BOOTSTRAP_KEY_ALREADY_USED` ile reddedilir; diskteki dosya okunmaz.

**Katman 2 — Servis Başlangıcında Önleyici Temizlik:**
- Hub servisi her başladığında (crash sonrası da dahil) başlangıç rutini şu kontrolü çalıştırır:
  ```
  FOR EACH kayıt IN db.bootstrap_keys WHERE is_used = TRUE:
    IF Dosya(%PROGRAMDATA%\MarketMMS\setup\bootstrap.key) MEVCUT:
      Dosyayı sil (File.deleteSync())
      audit_log.write("bootstrap.key artık kaldırıldı — crash recovery")
  ```
- Bu rutin idempotent'tir: dosya yoksa sessizce geçer, birden fazla çalıştırılması sorun oluşturmaz.

**Katman 3 — Yeni Bootstrap Anahtarı Üretim Koşulları:**
- Mevcut bootstrap anahtarı (`is_used = FALSE`, `expires_at > NOW()`) geçerli olduğu sürece yeni anahtar üretilmez.
- Yeni anahtar yalnızca şu koşullarda üretilir:
  1. `is_used = TRUE` (Tüketilmiş — Başarılı bootstrap).
  2. `expires_at <= NOW()` (24 saat geçmiş — Süresi dolmuş, hiç kullanılmamış).
  3. Yönetici `POST /api/v1/admin/regenerate-bootstrap` çağırdığında (Kayıp anahtar durumu).
- Hiçbir durumda geçerli `is_used = FALSE` anahtar üzerine yeni anahtar yazılmaz; bu durum eski anahtarın iptal olmadan kaybolmasına yol açar.

### 2.5. Aşama Ayrımı (Bootstrap)
- **Mevcut Kodda Doğrulanan:** [`server.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart#L130) içinde loopback kontrolü (`_verifyLoopbackAndAdmin`) ve [`token_manager.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/token_manager.dart) içinde tuzlu token üretimi doğrulanmıştır.
- **Önerilen Yeni Davranış:** Hub kurulumunda tek kullanımlık `bootstrap.key` üretilmesi, ACL ile korunması, tüketildiğinde silinmesi; standart kullanıcıya GUI parola alanı üzerinden güvenli aktarım; servis başlangıcında crash recovery temizliği.
- **Henüz Uygulanmamış İş:** `bootstrap_keys` tablosu migration'ı; bootstrap Shelf handler'ı; Flutter kurulum sihirbazı (güvenli parola girişi); başlangıç temizlik rutini.

---

## 3. Token Yaşam Döngüsü ve Güvenli Saklama (OD-SEC-03 & DPAPI)

### 3.1. Tasarım Kararı: Süresiz, İptal Edilebilir Cihaz Token'ı (OD-SEC-03)
Perakende market kasalarında sabit cihazların 30 veya 90 günde bir token yenileme (refresh token) nedeniyle kilitlenmesi operasyonel risktir. Bu nedenle:
- Windows masaüstü istemcisi için üretilen cihaz token'ı **süresizdir (`expires_at = null`)**.
- Güvenlik sınırı, süreli token yerine **anlık cihaz bazlı iptal edilebilirlik (Revocation-Based Model)** ile sağlanır.
- Cihaz çalınması, kasanın devredilmesi veya arıza durumunda işletme sahibi Hub konsolundan cihazı pasife alır (`isActive = false`). Hub'daki `auth_middleware` veritabanındaki her istekte bu bayrağı kontrol ettiğinden, iptal edilen cihazın erişimi **sıfır gecikmeyle (anında)** kesilir (`403 DEVICE_REVOKED`).

### 3.2. Windows DPAPI Güvenlik Sınırları ve Kullanıcı Kapsamları

> [!WARNING]
> **Windows Kullanıcı Hesapları ve DPAPI İzolasyonu:**  
> Windows Service (`MarketMMSService`) genellikle arka planda `NT AUTHORITY\SYSTEM` (veya özel servis hesabı) altında çalışır.  
> Windows Flutter UI (`market_pos.exe`) ise oturum açmış interaktif masaüstü kullanıcısı (`Kasiyer`, `Yonetici` vb.) altında çalışır.  
> DPAPI `CurrentUser` kapsamı, şifreleme anahtarını doğrudan o anki Windows kullanıcısının kimlik bilgilerine ve SID'sine bağlar.  
> Dolayısıyla **`SYSTEM` hesabı ile şifrelenen bir veri `Kasiyer` kullanıcısı tarafından ÇÖZÜLEMEZ; `Kasiyer` tarafından şifrelenen bir veri de `SYSTEM` tarafından ÇÖZÜLEMEZ.**

Bu mimari gerçeklik doğrultusunda **iki bağımsız güvenlik sınırı** tasarlanmıştır:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ WINDOWS MASTER HUB GÜVENLİK SINIRI (Arka Plan Windows Service - SYSTEM Hesabı)          │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ • Çalışma Hesabı: NT AUTHORITY\SYSTEM                                                  │
│ • Korunan Varlık: Sunucu Pepper Anahtarı (pepper.dpapi)                                │
│ • Saklama Konumu: %PROGRAMDATA%\MarketMMS\security\pepper.dpapi                        │
│ • NTFS ACL: Yalnızca SYSTEM ve BUILTIN\Administrators (Standart kullanıcılara kapalı)  │
│ • DPAPI Kapsamı: spike_01_backend içindeki FFI CryptProtectData                        │
│   (cryptProtectLocalMachine veya SYSTEM hesabı CurrentUser)                             │
└────────────────────────────────────────────────────────────────────────────────────────┘

                                    AĞ VE PROTOKOL İZOLASYONU
                          (Yerel HTTPS 127.0.0.1:8443 — Bearer Token)

┌────────────────────────────────────────────────────────────────────────────────────────┐
│ WINDOWS İSTEMCİ GÜVENLİK SINIRI (Masaüstü Kullanıcı Arayüzü - Interaktif Kullanıcı)   │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ • Çalışma Hesabı: Oturum Açan Standart Windows Kullanıcısı (Kasiyer / Yonetici)        │
│ • Korunan Varlık: İstemci Cihaz Token'ı (device_token.dpapi)                           │
│ • Saklama Konumu: %LOCALAPPDATA%\MarketMMS\security\device_token.dpapi                 │
│ • NTFS ACL: Kullanıcının kendi yerel profil dizini (%LOCALAPPDATA% varsayılanı)        │
│ • DPAPI Kapsamı: CryptProtectData(dwFlags: CRYPTPROTECT_UI_FORBIDDEN [CurrentUser])     │
│ • Çapraz Erişim Yasağı: İstemci UI, Hub'ın pepper.dpapi dosyasına ASLA erişemez;       │
│   Hub servisi de istemcinin device_token.dpapi dosyasına doğrudan dokunmaz.            │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

#### Düz Metin Depolama Yasağı:
Token'ın veya sunucu sırlarının `client_local.db` içinde düz metin olarak veya şifresiz JSON/INI dosyalarında saklanması **KESİNLİKLE YASAKTIR**.

### 3.3. Cihaz Türüne Göre Token Yenileme ve Re-Authentication Ayrımı

Bir cihazın token'ı geçersizleştiğinde (`401 Unauthorized` + `ERR_INVALID_TOKEN`) veya silindiğinde, cihaz türüne göre iki **tamamen ayrık** yeniden yetkilendirme (re-authentication) akışı işletilir. İki cihaz türünün güvenlik sınırları ve kanalları birbirine karıştırılamaz:

```
┌──────────────────────────────────────────────────────────────┐          ┌──────────────────────────────────────────────────────────────┐
│                  WINDOWS MASAÜSTÜ YENİLEME                   │          │                     ANDROID MOBİL YENİLEME                   │
├──────────────────────────────────────────────────────────────┤          ├──────────────────────────────────────────────────────────────┤
│ 1. Tetikleyici: 401 ERR_INVALID_TOKEN                        │          │ 1. Tetikleyici: 401 ERR_INVALID_TOKEN                        │
│ 2. Güvenlik Kanalı: YALNIZCA Yerel Loopback (127.0.0.1)      │          │ 2. Güvenlik Kanalı: Yerel Wi-Fi / LAN (HTTPS — ca.crt)       │
│ 3. Yetkilendirme Aracı: Tek Kullanımlık Bootstrap Anahtarı   │          │ 3. Yetkilendirme Aracı: Dinamik QR Kod + pairing_secret      │
│ 4. Erişim Modeli: %PROGRAMDATA%\MarketMMS\setup\bootstrap.key │          │ 4. Erişim Modeli: Hub Konsolu "Cihazı Yeniden Eşleştir"      │
│    (NTFS ACL: Yalnızca SYSTEM / Administrator)               │          │    (Yönetici gözetiminde ekrandan kamera ile tarama)         │
│ 5. İstemci Deposu: Windows DPAPI (CurrentUser)               │          │ 5. İstemci Deposu: Android Keystore (AES-256-GCM)            │
└──────────────────────────────────────────────────────────────┘          └──────────────────────────────────────────────────────────────┘
```

#### Ayrım Kuralları:
1. **Windows İstemcisi:** Hub ile aynı fiziksel makinede çalıştığından kamera veya QR tarama donanımına ihtiyaç duymaz ve aramaz. Yönetici yetkisiyle üretilen tek kullanımlık 256-bit bootstrap anahtarı üzerinden loopback HTTPS rotasıyla (`POST /api/v1/devices/local-bootstrap`) yeni token edinir.
2. **Android İstemcisi:** Fiziksel olarak ayrı bir el terminali veya telefondur. Windows dosya sistemine (`%PROGRAMDATA%`) ve loopback arayüzüne (`127.0.0.1`) erişimi **YOKTUR**. Bu nedenle:
   - **Android için Windows bootstrap anahtarı KESİNLİKLE KULLANILAMAZ.**
   - Sunucu tarafında `POST /api/v1/devices/local-bootstrap` rotası yalnızca `127.0.0.1` adresinden gelen bağlantıları kabul eder; dış ağdan gelen istekleri doğrudan `403 FORBIDDEN_NON_LOOPBACK` ile düşürür.
   - Android istemcisi token yenilemek için mutlaka Hub konsolunda işletme sahibi tarafından başlatılan yeni bir QR eşleştirme oturumunu (`POST /api/v1/pairing/request`) tamamlamalıdır.

#### 4 Cihaz Durumunun Ayrılması ve Token Yenileme/Kayıt Protokolü (D4):

Hub tarafında bir cihaza token tahsis edilirken 4 farklı durum kesin olarak ayrılır; `UPDATE devices` sorgusunun 0 satır etkilemesi durumu koşulsuz olarak ele alınır:

1. **Durum 1 — Yeni Cihaz Kaydı (İlk Bootstrap veya İlk Eşleştirme):**
   - Cihaz `devices` tablosunda henüz kayıtlı değildir.
   - Bu akışta `UPDATE` çalıştırılmaz; doğrudan atomik `INSERT INTO devices (...)` çalıştırılır.
   - `INSERT` işlemi birincil anahtar çakışması (`device_id` zaten varsa) alırsa işlem `409 Conflict (DEVICE_ALREADY_EXISTS)` ile reddedilir.
2. **Durum 2 — Mevcut Cihazın Token Rotasyonu (Re-Authentication):**
   - Cihaz zaten kayıtlıdır ancak token'ı yenilenmektedir.
   - Atomik transaction içinde `UPDATE devices SET token_hash = :new_token_hash, salt = :new_salt, is_active = TRUE, updated_at = CURRENT_TIMESTAMP WHERE device_id = :device_id` çalıştırılır.
   - **Etkilenen Satır Kontrolü (`rowsAffected == 0`):** Eğer bu sorgu 0 satır etkilerse, cihaz veritabanında bulunamamıştır. Transaction derhal `ROLLBACK` edilir; işlem sessizce geçiştirilemez, `404 Not Found (ERR_DEVICE_NOT_FOUND)` dönülür.
3. **Durum 3 — İptal Edilmiş Cihazın Yeniden Eşleştirilmesi:**
   - Cihaz daha önce iptal edilmiştir (`is_active = FALSE`).
   - *Mevcut Kodda Doğrulanan Davranış:* [`server.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart#L838) içinde iptal edilmiş cihaz eşleştirilmek istendiğinde `409 Conflict (DEVICE_ALREADY_REVOKED)` hatası dönmektedir.
   - *Önerilen Yeni Davranış:* Güvenlik gereği iptal edilmiş cihaz otomatik re-auth olamaz; işletme sahibinin Hub konsolundan cihazı aktifleştirmesi (`is_active = TRUE`) veya yönetici onayıyla cihazı sistemden silip sıfırdan yeni cihaz olarak eşleştirmesi gerekir.
4. **Durum 4 — Cihaz Kaydının Bulunamaması:**
   - Token yenileme rotasına bilinmeyen bir `device_id` ile gelinirse `UPDATE` 0 satır döner; transaction iptal edilerek `401 Unauthorized (DEVICE_NOT_FOUND)` yanıtı verilir.

---

#### Atomik Token İptali, Güncelleme ve Tekrar Kullanım (Replay) Koruması (D3 & D4):

Eski token'ın iptali, yeni token'ın atanması ve yetkilendirme aracının (Bootstrap / pairing_secret) tüketilmesi tek bir transaction içinde bağlanır:

```sql
-- Yeni token tahsis edilirken Hub üzerinde çalışan atomik transaction:
BEGIN IMMEDIATE TRANSACTION;

-- [DURUM A: YENİ CİHAZ KAYDI]
-- Eğer ilk kurulum ise doğrudan INSERT:
INSERT INTO devices (
  device_id, name, role, token_hash, salt, is_active, is_confirmed, created_at, updated_at
) VALUES (
  :device_id, :device_name, :role, :token_hash, :salt, TRUE, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
);

-- [DURUM B: MEVCUT CİHAZ TOKEN ROTASYONU]
-- Eğer token yenileme ise UPDATE ve ETKİLENEN SATIR KONTROLÜ:
UPDATE devices
SET token_hash = :new_token_hash,
    salt       = :new_salt,
    is_active  = TRUE,
    revoked_at = NULL,
    updated_at = CURRENT_TIMESTAMP
WHERE device_id = :device_id;
-- Dart / FFI Kontrolü: IF (rowsAffected == 0) -> ROLLBACK ve ERR_DEVICE_NOT_FOUND fırlat!

-- [ADIM C: YETKİLENDİRME ARACININ ATOMİK TÜKETİMİ]
-- Windows Bootstrap Anahtarı İçin:
UPDATE bootstrap_keys
SET is_used = TRUE,
    used_at = CAST(strftime('%s', 'now') AS INTEGER),
    used_by_device = :device_id
WHERE key_hash = :bootstrap_key_hash
  AND is_used = FALSE
  AND expires_at > CAST(strftime('%s', 'now') AS INTEGER);
-- Dart Kontrolü: IF (rowsAffected == 0) -> ROLLBACK ve BOOTSTRAP_KEY_INVALID_OR_USED fırlat!

COMMIT;
```

##### Android Eşleştirme Sırrı (`pairing_secret`) Doğrulama ve Durum Protokolü (D3):
Mevcut Hub kodunda Android eşleştirme oturumları bellekteki `Map<String, PairingSession>` üzerinde yürütülür. Alanların görev ayrımı:
- **`session_id`:** Eşleştirme oturumunu tekil olarak tanımlar (Hub'ın hangi oturumu denetleyeceğini belirler).
- **`pairing_secret`:** QR kod üzerinden cihaza aktarılan ve oturumun ilk doğrulamasında kullanılan tek kullanımlık paylaşılan sırdır.

İstemci `POST /api/v1/pairing/request` çağrısıyla bu iki alanı sunar:
1. **Adım 1 — Yanlış Sır ve Sayaç Kilitlemesi:** Gelen `pairing_secret` oturumdaki değerle eşleşmezse, `session.failedSecretAttempts++` yapılır. Sayaç $\ge 3$ olduğunda `session.status = PairingSessionStatus.locked` yapılarak oturum kilitlenir (`401 Unauthorized (INVALID_PAIRING_SECRET)`). Kilitli oturum sonraki tüm isteklerde `403 Forbidden (SESSION_LOCKED)` ile geri çevrilir.
2. **Adım 2 — Doğru Sır ve Replay Koruması:** Gelen sır doğru ise `session.status == PairingSessionStatus.created` kontrol edilir; uygunsa anında `session.status = PairingSessionStatus.pendingApproval` durumuna geçirilir. Oturum daha önce talep edilmişse `409 Conflict (SESSION_ALREADY_BOUND)` fırlatılır.
3. **Adım 3 — Onay ve Cihaz Kaydı:** Hub yöneticisi `/api/v1/pairing/approve` onayını verdiğinde, `WriteQueue` aracılığıyla `devices` tablosuna atomik cihaz kaydı yukarıdaki SQL transaction'ı ile eklenir.

**Güvenlik ve Bütünlük Garantileri (D3 & D4):**
- **Atomiklik ve Yanlış Deneme Sayacı (D3):** Yanlış `pairing_secret` girildiğinde oturumun `failedSecretAttempts` sayacı artırılır; 3. hatalı denemede oturum kalıcı olarak kilitlenir (`PairingSessionStatus.locked`). 3. denemeden sonra doğru sır girilse dahi kilitli oturum açılamaz (`403 SESSION_LOCKED`).
- **Tekrar Kullanım (Replay) ve Eşzamanlılık Engeli:** İki eşzamanlı `POST /api/v1/pairing/request` isteğinden ilki `status = pendingApproval` yapar; ikincisi senkron kontrol sayesinde `SESSION_ALREADY_BOUND` (`409`) alır.
- **Süre Sonu Ayrımı:** 5 dakikalık oturum süresi dolduğunda (`session.isExpired`), `410 Gone (SESSION_EXPIRED)` hatası döner; bağlanmış (`409`) veya kilitlenmiş (`403`) oturumlardan açıkça ayrılır.
- **Eski Token'ın Derhal Hükümsüzleşmesi:** Token rotasyonunda eski hash ezildiği andan itibaren, eski token ile gelen tüm uçuş halindeki istekler Hub `auth_middleware` tarafından anında `401 Unauthorized (DEVICE_NOT_FOUND)` ile geri çevrilir.

### 3.4. Aşama Ayrımı (Token ve DPAPI)
- **Mevcut Kodda Doğrulanan:** [`test_spikes/spike_01_backend/lib/security/dpapi.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/dpapi.dart#L60-L130) FFI Win32 implementasyonu ve `CryptProtectData` çağrısı doğrulanmıştır.
- **Önerilen Yeni Davranış:** Windows UI için `CurrentUser` kapsamlı `DeviceTokenStorage` adapter'ı yazılması; Hub `pepper.dpapi` ile Client `device_token.dpapi` kapsamlarının ayrıştırılması; token'ın süresiz yapılıp iptal kontrolünün `auth_middleware` üzerinden işletilmesi.
- **Henüz Uygulanmamış İş:** `DeviceTokenStorage` sınıfının Flutter tarafında FFI ile implemente edilmesi ve Riverpod provider'ına bağlanması.

---

## 4. HTTPS, Yerel TLS ve Güven Mimarisi (OD-SEC-02, SAN & Özel Kök CA)

### 4.1. Tasarım Kararı: ACL Korumalı Dosyadan Kök CA Edinme (OD-SEC-02)
Windows masaüstü istemcisi, aynı işletim sisteminde kurulu Hub servisinin ürettiği Kök CA sertifikasını doğrudan yerel dosya sisteminden okur:
- **Konum:** `%PROGRAMDATA%\MarketMMS\certs\ca.crt`.
- **NTFS ACL:** Dosya genel okuma (`Everyone: Read`, `SYSTEM/Admin: Full Control`) izinlidir; Kök CA genel sertifika olduğu için gizlilik tehdidi oluşturmaz.
- **Sertifika Biçimi (Windows TLS API Beklentisi):** `%PROGRAMDATA%\MarketMMS\certs\ca.crt` dosyası OpenSSL tarafından üretilmiş standart **PEM formatındadır** (`-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----`). Dart `dart:io` `SecurityContext.setTrustedCertificatesBytes(rootCaBytes)` metodu Windows üzerinde BoringSSL/OpenSSL kullandığından doğrudan bu PEM kodlu baytları bekler ve hatasız işler.
- **Güven Modeli:** İstemci, bu sertifikayı işletim sistemi kök deposuna eklemek zorunda kalmadan doğrudan Dart `SecurityContext` nesnesine yükler.

### 4.2. "Private Root CA Trust Validation" vs "Leaf Certificate Pinning" Ayrımı

> [!IMPORTANT]
> **Kritik Kriptografik Düzeltme:**  
> `HttpSyncTransport.withCustomRootCa` ([`sync_transport.dart`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/sync/sync_transport.dart#L39-L55)) implementasyonu bir **Yaprak Sertifika Sabitlemesi (Leaf Certificate Pinning)** DEĞİLDİR; **İşletim Sistemi Köklerini Dışlayan Özel Kök CA Güven Doğrulamasıdır (Private Root CA Trust Validation with OS Root Exclusion)**.

İki kavram arasındaki mimari farklar:
1. **İşletim Sistemi Köklerini Dışlayan Özel Kök CA Doğrulaması (Kullandığımız Model):**
   ```dart
   final context = SecurityContext(withTrustedRoots: false);
   context.setTrustedCertificatesBytes(rootCaBytes); // Yalnızca Market MMS ca.crt'ye güven
   final ioClient = HttpClient(context: context);
   ioClient.badCertificateCallback = (cert, host, port) => false; // Asla bypass yok!
   ```
   - `withTrustedRoots: false`: Windows işletim sisteminin genel güven deposundaki (DigiCert, Let's Encrypt veya kurumsal ağlardaki araya girme/proxy kök sertifikaları) hiçbir sertifikaya güvenilmez. Yalnızca bizim 10 yıllık `ca.crt`'miz güven çapası (Trust Anchor) kabul edilir.
   - **Avantajı:** Hub yaprak sertifikası (`server.crt`) 1 yılda bir yenilendiğinde veya IP/SAN değişikliği sebebiyle yeniden üretildiğinde, aynı `ca.crt` tarafından imzalandığı sürece **istemcide hiçbir kesinti veya güncelleme gerekmez**.
2. **Yaprak Sertifika Sabitlemesi (Leaf Pinning - Tercih Edilmeyen Model):**
   - Yaprak sertifikanın (`server.crt`) ham baytlarını veya SHA-256 SPKI özetini istemci koduna sabitlemektir.
   - **Dezavantajı:** Sunucu sertifikası her yenilendiğinde veya IP değiştiğinde tüm istemcilerin anında bozulmasına (Handshake Exception) ve kilitlenmesine yol açar.

### 4.3. LAN IP Değişikliği, DNS ve Dinamik SAN Uyuşmazlığı Yönetimi
Perakende marketlerde modem/router yeniden başlatıldığında DHCP sunucusu ana bilgisayarın yerel IP adresini değiştirebilir (örn. `192.168.1.100` iken `192.168.1.105` olması).

**Tavizsiz İlke: Sertifika Doğrulamasını Kapatan Çözüm (`badCertificateCallback = true`) KESİNLİKLE YASAKTIR.**

Sertifika doğrulamasından ödün vermeden IP değişikliklerini yöneten 3 kademeli çözüm:
1. **Windows UI Loopback Sabitliği (Değişmez Adres):**  
   Windows Kasa UI (`market_pos.exe`), Hub ile aynı makinede çalıştığı için bağlantı adresi daima `https://127.0.0.1:8443` veya `https://localhost:8443`'tür. Bu adresler modemin LAN IP'sinden tamamen bağımsızdır ve asla değişmez.
2. **Sabit Makine Adı / mDNS Standardı (Mobil ve Harici Kasalar İçin):**  
   Yerel ağdaki istemciler değişken DHCP IP yerine Windows NetBIOS / Makine Adı (örn. `https://MARKET-KASA-01:8443`) veya mDNS (örn. `https://market-mms.local:8443`) üzerinden bağlanır.
3. **Servis Başlangıcında Dinamik Yaprak Sertifika Yenileme:**  
   Hub servisi (`mms_backend.exe`) her açılışında ana makinenin güncel IPv4 adreslerini tarar. Eğer makinenin yerel IP'si değişmişse, `CertificateManager`, **mevcut 10 yıllık Root CA'yı koruyarak** yaprak sertifikayı (`server.crt`) yeni IP'yi SAN listesine ekleyerek saniyeler içinde yeniden üretir. İstemciler `ca.crt`'ye güvendiği için yeni `server.crt` sıfır hatayla anında kabul edilir.

### 4.4. SAN (Subject Alternative Name) Zorunlu Kapsamı
`CertificateManager` tarafından üretilen `server.crt` sertifikasının SAN listesinde bulunması zorunlu adresler:
- `IP:127.0.0.1` (IPv4 Loopback)
- `IP:::1` (IPv6 Loopback)
- `DNS:localhost` (Standart yerel host)
- `IP:<Aktif_LAN_IPv4>` (Servisin tespit ettiği yerel ağ IP'si)
- `DNS:<Makine_Adi>` (Windows NetBIOS adı, örn. `MARKET-KASA-01`)
- `DNS:market-mms.local` (Yerel mDNS adı)

### 4.5. Aşama Ayrımı (HTTPS ve TLS)
- **Mevcut Kodda Doğrulanan:** [`CertificateManager`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/certificate_manager.dart) ile OpenSSL CA ve SAN'lı sunucu sertifikası üretimi; [`sync_transport.dart`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/sync/sync_transport.dart#L39) ile `HttpSyncTransport.withCustomRootCa` yapısı doğrulanmıştır.
- **Önerilen Yeni Davranış:** Windows istemcisinin `%PROGRAMDATA%\MarketMMS\certs\ca.crt` dosyasını okuyup `withCustomRootCa` ile bağlaması; `AppConstants.defaultBackendBaseUrl`'in `https://127.0.0.1:8443` yapılması; sunucu açılışında dinamik LAN IP tespiti ile SAN yenileme.
- **Henüz Uygulanmamış İş:** İstemci tarafında `ca.crt` okuyucu servis, URL sabitlerinin güncellenmesi, `server.dart` Shelf sunucusunun HTTPS portunda (`8443`) ayağa kaldırılması.

---

## 5. Hata Yönetimi, Outbox FIFO ve Kurtarma Stratejisi

### 5.1. 401/403 Yapılandırılmış Hata Kodu Ayrımı ve FIFO Askıya Alma

> [!CRITICAL]
> **Kalıcı Kilitlenme Tuzağı ve Kaba HTTP Kodu Varsayımı:**  
> Mevcut `ClientSyncService` (satır 142), HTTP 401 veya 403 yanıtı aldığında satışı doğrudan `FAILED_PERMANENT` yapmakta ve döngüyü kırmaktadır. Bu iki yönden hatalıdır:  
> 1. 401/403 yanıtları veri hatası değil, sistemsel yetki ve bağlantı durumudur. Satışı `FAILED_PERMANENT` yapmak, arkasındaki tüm bekleyen satışları da kilitler (Head-of-Line Blocking).  
> 2. Tüm 401 ve 403 yanıtları aynı anlama gelmez. HTTP durum koduna ek olarak yanıttaki **yapılandırılmış hata kodu (`error_code` / `error`)** çözümlenmeli ve her senaryo için farklı durum makinesi işletilmelidir.

#### Yapılandırılmış 401/403 Durum Ayrımı ve Gerçek Hub Yanıt Sözleşmesi (D2 & D5):

Kaynak kod doğrulaması ([`spike_01_backend/lib/security/auth_middleware.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/auth_middleware.dart#L50-L145)) sonucunda, Hub'ın hata yanıtlarında birincil JSON anahtarı olarak **`'error'`** alanını kullandığı (`{'error': '...'}`), `'error_code'` alanının ise mevcut Hub kodunda **bulunmadığı** doğrulanmıştır. Bazı uç noktalarda ek olarak `'code'` alanı sunulmaktadır.

Mevcut Hub kodunda fiilen üretilen hata kodları ile hedef mimari eşlemesi:

1. **`401 Unauthorized` — Yetkisiz İstek (Mevcut Hub Kodunda: `error: 'UNAUTHORIZED'` veya `error: 'INVALID_TOKEN'`):**
   - **Tetikleyici:** İstemci HTTP isteğinde `Authorization: Bearer <token>` başlığı göndermemiş, başlık boş veya hatalı formattadır.
   - **Sistemsel Durum:** `SyncAuthState.unconfigured` (veya token silinmiş/okunamamışsa `SyncAuthState.authRequired`).
   - **Hedef Outbox Davranışı:** İşlem `FAILED_PERMANENT` yapılmaz; `IN_PROGRESS` durumu güvenle `PENDING`'e çekilir (`error_category = 'AUTH_ERROR'`, `error_code = 'ERR_AUTH_REQUIRED'`). Kuyruk askıya alınır. Satış verisi dokunulmazdır; veri kaybı yaşanmaz.
   - **Kurtarma Yolu:** Bootstrap anahtarı ile ilk yetkilendirme veya token okunması; ardından otomatik devam.
   - **Kasa UI Bildirimi:** `[🔑 CİHAZ YETKİLENDİRMESİ GEREKLİ]`

2. **`401 Unauthorized` — Tanınmayan Cihaz / Süresi Dolan Token (Mevcut Hub Kodunda: `error: 'DEVICE_NOT_FOUND'` veya `error: 'TOKEN_EXPIRED'`):**
   - **Tetikleyici:** İstemci Bearer token göndermiştir; ancak Hub `TokenManager.verifyToken` veritabanındaki aktif cihazlar arasında bu token'ın hash eşleşmesini bulamamıştır (`DEVICE_NOT_FOUND`) veya cihazın süresi dolmuştur (`TOKEN_EXPIRED`). Hub mevcut kodda `ERR_INVALID_TOKEN` metnini değil, `DEVICE_NOT_FOUND` metnini üretir.
   - **Sistemsel Durum:** `SyncAuthState.authRequired`.
   - **Hedef Outbox Davranışı:** İşlem `FAILED_PERMANENT` yapılmaz; `IN_PROGRESS` durumu `PENDING`'e çevrilir (`error_category = 'AUTH_ERROR'`, `error_code = 'ERR_INVALID_TOKEN'`). Kuyruk duraklatılır (suspend).
   - **Kurtarma Yolu (Cihaz Türüne Göre Kesin Ayrık):**
     - *Windows İstemcisi:* Tek kullanımlık Windows bootstrap anahtarı ile loopback üzerinden yeni token edinilir (`POST /api/v1/devices/local-bootstrap`). Yeni token DPAPI'ye yazıldığı an Outbox otomatik devam eder.
     - *Android İstemcisi:* Hub konsolunda yeni QR eşleştirme oturumu ile token edinilir (`POST /api/v1/pairing/request`). Android için Windows bootstrap anahtarı **kesinlikle kullanılamaz**. Yeni token Android Keystore'a yazıldığı an Outbox otomatik devam eder.
   - **Kasa UI Bildirimi:** `[🔑 GEÇERSİZ TOKEN — YENİDEN YETKİLENDİRME GEREKLİ]`

3. **`403 Forbidden` — İptal Edilmiş Cihaz (Mevcut Hub Kodunda: `error: 'DEVICE_REVOKED'`):**
   - **Tetikleyici:** İstemci geçerli bir token göndermiştir; ancak Hub veritabanında `matchedDevice.isActive == false` durumundadır (`auth_middleware.dart` satır 103). İptal edilmiş cihaz mevcut Hub kodunda fiilen doğrulanmıştır.
   - **Sistemsel Durum:** `SyncAuthState.deviceRevoked`.
   - **Hedef Outbox Davranışı:** İşlem `FAILED_PERMANENT` yapılmaz; `IN_PROGRESS` durumu `PENDING`'e çevrilir (`error_category = 'AUTH_ERROR'`, `error_code = 'ERR_DEVICE_REVOKED'`). Kuyruk duraklatılır.
   - **Kurtarma Yolu:** Cihazda yeniden bootstrap **yapılmaz** (çünkü token geçerlidir). Yalnızca işletme sahibi Hub konsolundan cihazı tekrar aktifleştirir (`isActive = true`). İstemci yeniden denediğinde token geçerli olduğu için kuyruk kendiliğinden akar.
   - **Kasa UI Bildirimi:** `[🚫 CİHAZ ERİŞİMİ İPTAL EDİLDİ — HUB KONSOLUNDAN ETKİNLEŞTİRİN]`

4. **`403 Forbidden` — Yetersiz Yetki / Rol (Mevcut Kodda: UYGULANMAMIŞTIR; Hedef: `ERR_INSUFFICIENT_PERMISSION`):**
   - **Kaynak Kod Durumu:** Mevcut `auth_middleware.dart` istek bağlamına `authenticated_device_role` alanını eklemektedir ancak satış rotasında rol kontrolü (`role == 'pos'`) **henüz uygulanmamıştır (uygulanmamış geliştirme gereksinimi)**.
   - **Hedef Senaryo:** İstemci aktif bir cihaza aittir; ancak cihazın kayıtlı rolü (ör. `viewer`, `inventory_only`) satış senkronizasyonu yapmaya yetkili değildir.
   - **Sistemsel Durum:** `SyncAuthState.permissionDenied`.
   - **Hedef Outbox Davranışı:** `IN_PROGRESS → PENDING` (`error_category = 'AUTH_ERROR'`, `error_code = 'ERR_INSUFFICIENT_PERMISSION'`). Kuyruk duraklatılır.
   - **Kurtarma Yolu:** Hub konsolunda cihaz rolü `pos` olarak güncellenir.
   - **Kasa UI Bildirimi:** `[⛔ YETERSİZ YETKİ — CİHAZ ROLÜNÜ HUB'DAN GÜNCELLEYİN]`

5. **Bilinmeyen / Yapılandırılmamış 401/403 Yanıtları (`ERR_UNKNOWN_AUTH`):**
   - **Tetikleyici:** Yanıt gövdesi JSON formatında değilse (ör. ters proxy/ağ cihazı tarafından üretilen standart HTML 401/403 hata sayfası), gövde boşsa veya yukarıdaki tanınan kodların dışındaysa.
   - **Sistemsel Durum:** `SyncAuthState.unknownAuthError`.
   - **Hedef Outbox Davranışı:** `IN_PROGRESS → PENDING` (`error_category = 'AUTH_ERROR'`, `error_code = 'ERR_UNKNOWN_AUTH'`). Kuyruk duraklatılır.
   - **Kurtarma Yolu:** Otomatik döngüye girmez; operatör incelemesi istenir.
   - **Kasa UI Bildirimi:** `[⚠️ GÜVENLİK/BAĞLANTI HATASI — TANILAMA İNCELEMESİ GEREKİYOR]`

---

### 5.2. Outbox Authentication Kurtarması — Yapılandırılmış Hata Kodu ve Seçici Requeue Standardı (D2 & D6)

> [!IMPORTANT]
> **Hedef Akışta PENDING Tutulması ile Eski FAILED_PERMANENT Kayıtlarının Requeue İlişkisi (D6):**  
> - **Hedef Akış:** Yeni mimaride bir 401/403 hatası alındığında satış kayıtları `FAILED_PERMANENT` **yapılmaz**; doğrudan `PENDING`'de tutulur ve kuyruk askıya alınır. Cihaz yetkilendirildiğinde kuyruk zaten `PENDING` olan bu kayıtlardan akmaya devam eder.  
> - **Requeue Sorgusunun Amacı (Geriye Dönük Uzlaştırma):** Ancak mevcut `ClientSyncService` (satır 142) hatalı olarak 401/403 yanıtlarını doğrudan `FAILED_PERMANENT` yapmaktadır. Yeni sürüme geçiş anında veya önceki çökmelerden ötürü `FAILED_PERMANENT` kalmış kayıtların kuyruğu sonsuza dek dondurmasını engellemek için, yeni token yazıldığında `requeueAuthFailedOperations` sorgusu tek seferlik geriye dönük kurtarma (reconciliation) olarak işletilir.

**Hata Sınıflandırma Mantığı (Dart — D2 Doğrulaması):**
```dart
({String category, String code}) classifyHttpError(int statusCode, Map<String, dynamic>? body) {
  // Hub yanıt sözleşmesinde birincil alan 'error', ikincil fallback 'code'dur:
  final rawError = body?['error'] ?? body?['code'];
  final errorCode = rawError?.toString();

  if (statusCode == 401) {
    if (errorCode == 'UNAUTHORIZED' || errorCode == 'ERR_AUTH_REQUIRED') {
      return (category: 'AUTH_ERROR', code: 'ERR_AUTH_REQUIRED');
    } else if (errorCode == 'DEVICE_NOT_FOUND' ||
               errorCode == 'TOKEN_EXPIRED' ||
               errorCode == 'INVALID_TOKEN' ||
               errorCode == 'ERR_INVALID_TOKEN') {
      return (category: 'AUTH_ERROR', code: 'ERR_INVALID_TOKEN');
    }
    // Tanınmayan veya gövdesiz tüm 401 yanıtları bilinmeyen auth hatasıdır:
    return (category: 'AUTH_ERROR', code: 'ERR_UNKNOWN_AUTH');
  } else if (statusCode == 403) {
    if (errorCode == 'DEVICE_REVOKED' || errorCode == 'ERR_DEVICE_REVOKED') {
      return (category: 'AUTH_ERROR', code: 'ERR_DEVICE_REVOKED');
    } else if (errorCode == 'FORBIDDEN_ROLE' || errorCode == 'ERR_INSUFFICIENT_PERMISSION') {
      return (category: 'AUTH_ERROR', code: 'ERR_INSUFFICIENT_PERMISSION');
    }
    // Tanınmayan veya gövdesiz tüm 403 yanıtları bilinmeyen auth hatasıdır:
    return (category: 'AUTH_ERROR', code: 'ERR_UNKNOWN_AUTH');
  } else if (statusCode == 400 || statusCode == 409 || statusCode == 422) {
    return (category: 'DATA_ERROR', code: errorCode ?? 'ERR_INVALID_PAYLOAD');
  } else if (statusCode >= 500) {
    return (category: 'SERVER_ERROR', code: 'INTERNAL_SERVER_ERROR');
  }
  return (category: 'UNKNOWN', code: 'UNKNOWN');
}
```

**Atomik ve Seçici Kurtarma Sorgusu (Requeue):**

```sql
-- Yalnızca yeni token yazıldığında veya bootstrap başarılı olduğunda çalışır.
-- SADECE token geçersizliği kaynaklı standart AUTH_ERROR kayıtlarını kurtarır.
-- ERR_DEVICE_REVOKED, ERR_INSUFFICIENT_PERMISSION, ERR_UNKNOWN_AUTH, DATA_ERROR kayıtlarına ASLA dokunmaz.
BEGIN TRANSACTION;

UPDATE outbox_operations
SET status         = 'PENDING',
    error_message  = NULL,
    error_category = NULL,
    error_code     = NULL,
    retry_count    = 0
WHERE status = 'FAILED_PERMANENT'
  AND error_category = 'AUTH_ERROR'
  AND error_code IN ('ERR_AUTH_REQUIRED', 'ERR_INVALID_TOKEN');

-- Not (D8): İstemci yerel veritabanında (client_local.db) henüz audit_logs tablosu
-- bulunmamaktadır (uygulanmamış geliştirme gereksinimi). Denetim kaydı yerel tanılama
-- tablosu eklendiğinde devreye alınacaktır.

COMMIT;
```

**Kurtarma Tetiklenme ve Güvenlik Kuralları:**
1. **Token Yenileme:** Yalnızca yeni bootstrap tamamlandığında ve `device_token.dpapi` başarıyla yazıldığında otomatik requeue çalışır.
2. **Cihaz İptali (`ERR_DEVICE_REVOKED`):** Token yenileme ile kurtarılmaz; Hub konsolunda cihaz aktif edildikten sonra kuyruk yeniden başlatılır.
3. **Yetki Yetersizliği (`ERR_INSUFFICIENT_PERMISSION`):** Token yenileme ile kurtarılmaz; Hub konsolunda rol güncellendikten sonra operatör onayıyla kuyruk devam eder.
4. **Bilinmeyen Auth Hataları (`ERR_UNKNOWN_AUTH`):** Otomatik requeue yapılmaz; tanılama logları incelenmeden döngüye sokulamaz.
5. **Veri Hataları (`DATA_ERROR`):** Auth kurtarma sorgusu `DATA_ERROR` kayıtlarına asla dokunmaz; bu kayıtlar için `updateAndRetryFailedOperation` kullanılır.
6. **FIFO Garantisi:** Requeue edilen kayıtların `client_seq` numaraları kesinlikle değişmez; monotonik artan sıra korunur.

### 5.3. `IN_PROGRESS` Durumundan Güvenli `PENDING` Dönüşü, FIFO Koruması ve Idempotent Kurtarma

> [!CRITICAL]
> **Orphaned IN_PROGRESS ve Ağ Yanıtı Kaybı Senaryoları:**  
> Bir outbox işlemi atomik olarak rezerve edilip `IN_PROGRESS` yapıldığında Hub'a HTTPS isteği gönderilir. İki kritik sınır senaryosu yönetilmelidir:  
> 1. İstek uçuştayken Hub `401` veya `403` dönerse, kayıt `FAILED_PERMANENT` yapılmamalı ve `IN_PROGRESS` askıda kalmamalı; güvenle `PENDING`'e dönmelidir.  
> 2. Hub satışı başarıyla işleyip tam `200 OK` yanıtını dönerken ağ koparsa veya istemci çökerse, işlem Hub'da gerçekleşmiş fakat istemcide `IN_PROGRESS` kalmış olur.

`IN_PROGRESS → PENDING` geri dönüş ve idempotent kurtarma sözleşmesi:

```
1. SyncCoordinator atomik rezervasyonla işlemi alır:
   UPDATE outbox_operations SET status = 'IN_PROGRESS' ... (Bkz. Bölüm 5.6)

2a. Hub 401/403 döndüğünde (auth/erişim hatası):
    UPDATE outbox_operations
    SET status         = 'PENDING',
        error_category = 'AUTH_ERROR',
        error_code     = <classified_error_code>
    WHERE operation_id = ?  AND  status = 'IN_PROGRESS'
    -- client_seq değişmez; FIFO sırası korunur.
    -- SyncCoordinator SyncAuthState'i günceller ve timer'ı duraklatır.

2b. Hub 400/409 döndüğünde (veri hatası):
    UPDATE outbox_operations
    SET status         = 'FAILED_PERMANENT',
        error_category = 'DATA_ERROR',
        error_code     = <response_body.error_code>
    WHERE operation_id = ?  AND  status = 'IN_PROGRESS'
    -- Kuyruk kilitlenir (Head-of-Line Blocking); operatör müdahalesi gerekir.

2c. Servis çöktüğünde veya ağ yanıtı kaybolduğunda (IN_PROGRESS askıda kalırsa):
    -- Servis her açılışında başlangıç temizliği çalışır:
    UPDATE outbox_operations
    SET status = 'PENDING',
        updated_at = CURRENT_TIMESTAMP
    WHERE status = 'IN_PROGRESS';
    -- Bu kayıtlar tekrar denenir; Hub'daki '$deviceId:$clientSeq' idempotency sözleşmesi çift kaydı engeller.
```

**`$deviceId:$clientSeq` Idempotency Standardı ile Güvenli Tekrar Gönderim:**
- **Hub Sözleşmesi:** Hub üzerindeki satış senkronizasyonu (`spike_01_backend`), idempotency anahtarı olarak **KESİNLİKLE `$deviceId:$clientSeq`** formatını esas alır (`server.dart` satır 994). Outbox tablosundaki yerel `operation_id` ise yalnızca istemci içi UUID v4 birincil anahtardır; ağ seviyesindeki idempotency anahtarı değildir.
- **Ağ Yanıtı Kaybı Senaryosu:** Hub işlemi başarıyla tamamlayıp `sync_operations` tablosuna `$deviceId:$clientSeq` anahtarıyla kaydetmiş, ancak istemciye giden HTTP 200 yanıtı ağda kaybolmuş veya istemci yanıtı alamadan çökmüş olabilir.
- **Güvenli Kurtarma:** İstemci yeniden başladığında (2c adımı) `IN_PROGRESS` kayıt `PENDING`'e döner ve aynı `client_seq` ile Hub'a tekrar gönderilir. Hub, gelen `$deviceId:$clientSeq` anahtarının zaten işlenmiş olduğunu görür; **ikinci kez satış veya stok düşüşü ASLA yapmaz**, önceden oluşturulmuş sonucu veya `200 OK (ALREADY_PROCESSED)` yanıtını anında döner. İstemci bu teyidi alınca yerel kaydı `SYNCED` olarak işaretler. Çift stok düşüşü ve veri bozulması riski %100 önlenir.

**`client_seq` Bütünlüğü ve Kuyruk Durumlarının FIFO Davranışı:**
- `IN_PROGRESS → PENDING` dönüşünde `client_seq` değeri asla değişmez.
- Kuyruk durumlarının Head-of-Line Blocking davranışı:
  - `PENDING`: Rezervasyona açık tek durumdur.
  - `IN_PROGRESS`: Halihazırda uçuşta işlem vardır; tamamlanmadan (`SYNCED`) veya hata alıp `PENDING`'e dönmeden hiçbir sonraki `client_seq` işlenemez.
  - `RETRY`: Geçici ağ hatası almış ve üstel bekleme (backoff) sürecindeki kayıttır; süresi dolup başarıyla işlenmeden sonraki kayıtlar asla atlanamaz.
  - `FAILED_PERMANENT`: Kalıcı veri/şema hatasıdır; kuyruk kilitlenir. Operatör düzeltme yapana kadar sonraki hiçbir işlem rezerve edilemez.

### 5.4. `SyncCoordinator` Durum Makinesi ve 6 Durumlu Auth Mimarisi

```
                                  ┌──────────────────────────────────────────────┐
                                  │                SyncAuthState                 │
                                  └──────────────────────┬───────────────────────┘
                                                         │
         ┌───────────────────┬───────────────────────────┼───────────────────────────┬───────────────────┐
         │                   │                           │                           │                   │
         ▼                   ▼                           ▼                           ▼                   ▼
    UNCONFIGURED        AUTHENTICATED              AUTH_REQUIRED               DEVICE_REVOKED     PERMISSION_DENIED
    (token yok /        (token geçerli,           (401 geldi —                 (403 geldi —       (403 geldi —
     ilk kurulum)        senkronizasyon aktif)     token geçersiz/süresi doldu) cihaz pasif)       rol yetersiz)
         │                   │                           │                           │                   │
         │                   │                           │                           │                   │
         ▼                   ▼                           ▼                           ▼                   ▼
     Kuyruk kapalı      Outbox çalışır              Kuyruk askıda               Kuyruk askıda      Kuyruk askıda
     PENDING bekler     (FIFO, Mutex kilitli)       PENDING korunur             PENDING korunur    PENDING korunur
     UI: 🔑 KURULUM     UI: ✅ N bekliyor           UI: 🔑 YETKİ GEREKLİ        UI: 🚫 İPTAL       UI: ⛔ YETERSİZ YETKİ
                                                                                                         │
                                                                                                         ▼
                                                                                                UNKNOWN_AUTH_ERROR
                                                                                                (Bilinmeyen 401/403)
                                                                                                Kuyruk askıda / Tanılama
                                                                                                UI: ⚠️ GÜVENLİK HATASI
```

**6 Durumlu `SyncAuthState` Karşılaştırma Matrisi:**

| Durum (`SyncAuthState`) | HTTP Kodu | Yapılandırılmış `error_code` | Tetikleyici Sebep | Otomatik Requeue? | Kurtarma Yolu | Kasa Arayüzü Bildirimi |
|---|---|---|---|---|---|---|
| `unconfigured` | — / `401` | `ERR_AUTH_REQUIRED` | İlk kurulum; `device_token.dpapi` mevcut değil veya boş. | **HAYIR** (token yok) | Bootstrap anahtarı ile yetkilendirme | `🔑 Cihaz Kurulumu ve Yetkilendirme Gerekli` |
| `authenticated` | `200` / `201` | — | Token doğrulandı, cihaz aktif; senkronizasyon çalışıyor. | — | — | `✅ Senkronize (Bekleyen: N)` |
| `authRequired` | `401` | `ERR_INVALID_TOKEN` / `DEVICE_NOT_FOUND` | Token Hub tarafından tanınmadı veya süresi doldu. | **EVET** (Yeni token yazıldığında) | Yeni bootstrap anahtarı edinme | `🔑 Geçersiz Token — Yeniden Yetkilendirme Gerekli` |
| `deviceRevoked` | `403` | `ERR_DEVICE_REVOKED` | Cihaz işletme sahibi tarafından Hub'da pasifleştirildi. | **HAYIR** (Token aynı) | Hub konsolundan cihazı aktifleştirme | `🚫 Cihaz Erişimi İptal Edildi (Hub Konsolu)` |
| `permissionDenied` | `403` | `ERR_INSUFFICIENT_PERMISSION` | Cihaz rolü satış gönderme yetkisine sahip değil. | **HAYIR** (Yetki değişimi gerekir) | Hub konsolundan cihaz rolünü `pos` yapma | `⛔ Yetersiz Yetki — Cihaz Rolünü Güncelleyin` |
| `unknownAuthError` | `401` / `403` | `ERR_UNKNOWN_AUTH` | Yanıt gövdesi çözümlenemedi veya bilinmeyen hata kodu. | **KESİNLİKLE HAYIR** | Sistem tanılama paneli / Log incelemesi | `⚠️ Güvenlik/Bağlantı Hatası (Tanılama Gerekli)` |

**Kimlik Doğrulama Düzeldikten Sonra Kuyruk Devam Protokolü:**
1. `DeviceTokenStorage.writeToken()` başarılıyla yeni token'ı DPAPI ile kaydeder.
2. `SyncCoordinator`, `SyncAuthState.authenticated` durumuna geçer.
3. `requeueAuthFailedOperations()` seçici SQL sorgusu çalışır (yalnızca token geçersizliği kayıtları `PENDING`'e döner).
4. `SyncCoordinator` Outbox zamanlayıcısını (timer) derhal tetikler.
5. İlk işlenecek kayıt en düşük `client_seq` değerine sahip olandır (FIFO bozulmaz).

**Eşzamanlı Sync Çağrılarını Engelleme:**
- `SyncCoordinator` uygulama düzeyinde `Mutex` (`package:synchronized` veya Dart tabanlı semafor) ile korunur.
- Zamanlayıcı tetiklendiğinde kilit alınamazsa yeni döngü başlatılmaz; mevcut döngünün bitmesi beklenir.
- `SyncAuthState != authenticated` ise zamanlayıcı hiçbir ağ isteği üretmeden döner.

### 5.5. Kapsamlı Hata Matrisi ve Kurtarma Senaryoları (Güncellenmiş)

| Hata Türü | HTTP / İstisna | `error_category` | Yapılandırılmış `error_code` | Outbox Durumu | Kuyruk Davranışı | Kurtarma Yolu |
|---|---|---|---|---|---|---|
| **Eksik Token** | İstemci `token == null` | `AUTH_ERROR` | `ERR_AUTH_REQUIRED` | `PENDING` | Senkronizasyon başlamaz | Bootstrap anahtarı ile ilk yetkilendirme |
| **Geçersiz Token** | `401 Unauthorized` | `AUTH_ERROR` | `ERR_INVALID_TOKEN` | `PENDING` (IN_PROG → PENDING) | **Kuyruk Askıya Alınır** | Yeni bootstrap; token yazılınca seçici requeue |
| **İptal Edilmiş Cihaz** | `403 Forbidden` | `AUTH_ERROR` | `ERR_DEVICE_REVOKED` | `PENDING` (IN_PROG → PENDING) | **Kuyruk Askıya Alınır** | Hub konsolundan cihazı aktifleştirme (Token değişmez) |
| **Yetersiz Yetki / Rol** | `403 Forbidden` | `AUTH_ERROR` | `ERR_INSUFFICIENT_PERMISSION` | `PENDING` (IN_PROG → PENDING) | **Kuyruk Askıya Alınır** | Hub konsolundan cihaz rolünü güncelleme |
| **Bilinmeyen Auth Hatası** | `401` / `403` diğer | `AUTH_ERROR` | `ERR_UNKNOWN_AUTH` | `PENDING` (IN_PROG → PENDING) | **Kuyruk Askıya Alınır** | Tanılama paneli; otomatik requeue yapılmaz |
| **İş Kuralı / Fiyat Hatası** | `400 Bad Request` | `DATA_ERROR` | `ERR_PRICE_MISMATCH` vb. | `FAILED_PERMANENT` | **Kuyruk Kilitlenir** | `updateAndRetryFailedOperation` veya manuel iptal |
| **Idempotency Çakışması**| `409 Conflict` | `DATA_ERROR` | `ERR_IDEMPOTENCY_CONFLICT` | `FAILED_PERMANENT` | **Kuyruk Kilitlenir** | Operatör incelemesi |
| **TLS Sertifika Hatası** | `HandshakeException` | `NETWORK_ERROR` | `TLS_HANDSHAKE_FAILED` | `PENDING` | İstek gönderilmez | Hub servis SAN güncellemesi / `ca.crt` kontrolü |
| **Bağlantı Reddedildi** | `SocketException` | `NETWORK_ERROR` | `CONNECTION_REFUSED` | `RETRY` | Üstel gecikme (1s..60s) | Hub servisi açılınca otomatik devam |
| **Hub Aşırı Yük** | `503 Service Unavail`| `NETWORK_ERROR` | `SERVER_BUSY` | `RETRY` | Üstel gecikme (1s..60s) | Servis rahatlayınca otomatik devam |
| **Kategori Belirsiz** | Diğer istisnalar | `UNKNOWN` | `UNKNOWN` | `FAILED_PERMANENT` | **Kuyruk Kilitlenir** | Manuel operatör kararı |

---

### 5.6. ClientSyncService ve SyncCoordinator Çift Katmanlı Eşzamanlılık (Concurrency) Koruması

Outbox senkronizasyonunda yarış durumlarını (race conditions), aynı satışın paralel gönderilmesini ve FIFO sıra bozulmasını önlemek için **çift katmanlı eşzamanlılık koruması** tasarlanmıştır:

#### 1. Tek Çağrı Noktası İlkesi (Single Entry Point Architectural Rule):
- **Mimari Kural:** Kullanıcı arayüzü (UI) veya harici bileşenler, doğrudan `ClientSyncService.syncPendingOperations()` metodunu **ASLA DOĞRUDAN ÇAĞIRAMAZ**.
- Senkronizasyon tetiklemeleri (UI "Şimdi Senkronize Et" butonu, periyodik arka plan timer'ı, satış tamamlanma reaktif sinyali) **yalnızca ve yalnızca `SyncCoordinator` üzerinden yönlendirilir**.
- Riverpod bağımlılık enjeksiyonunda `clientSyncServiceProvider` presentation katmanına doğrudan expose edilmez; UI yalnızca `syncCoordinatorProvider` ile haberleşir.

#### 2. SyncCoordinator Seviyesinde Mutex (Orkestrasyon Koruması):
- `SyncCoordinator`, bir Dart `Lock` / `Mutex` nesnesi (`package:synchronized`) barındırır.
- Periyodik zamanlayıcı veya kullanıcı butonu tetiklendiğinde:
  ```dart
  if (_syncLock.locked) {
    // Halihazırda devam eden bir senkronizasyon döngüsü var; yeni istek atlanır.
    return;
  }
  await _syncLock.synchronized(() async {
    await _clientSyncService.syncPendingOperations();
  });
  ```
- Bu kilit, UI tetiklemesi ile arka plan zamanlayıcısının aynı anda iki paralel senkronizasyon döngüsü başlatmasını kesin olarak engeller.

#### 3. ClientSyncService Seviyesinde İç Eşzamanlılık Koruması (Defense-in-Depth):
- `ClientSyncService`, birim testlerinde veya izole çalıştırıldığında dahi kendi bütünlüğünü korumalıdır.
- Servis gövdesinde atomik bir `_isExecuting` bayrağı (veya iç `Lock`) bulunur:
  ```dart
  Future<SyncResult> syncPendingOperations() async {
    if (_isExecuting) {
      // Doğrudan çağrı gelse dahi ikinci paralel yürütme derhal engellenir.
      return SyncResult.alreadyRunning();
    }
    _isExecuting = true;
    try {
      return await _processOutboxLoop();
    } finally {
      _isExecuting = false;
    }
  }
  ```

#### 4. Aynı `client_seq` Kaydının Paralel Gönderiminin ve Sıra Bozulmasının Engellenmesi (Atomik FIFO ve RETRY Rezervasyonu — D1 & D6):

##### SQLite DateTime Saklama Biçimi ve CURRENT_TIMESTAMP Tip Afinitesi Analizi (D1):
- **Drift DateTime Yapılandırması:** [`packages/mms_client_storage/pubspec.yaml`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/pubspec.yaml) içinde `drift: ^2.20.0` ve [`client_database.dart`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/database/client_database.dart#L110) içinde `DateTimeColumn get nextRetryAt => dateTime().nullable()();` kullanıldığı doğrulanmıştır. Projede `store_date_time_values_as_text: true` içeren bir `build.yaml` bulunmamaktadır.
- **Gerçek SQLite Saklama Biçimi:** Drift, `dateTime()` sütunlarını varsayılan olarak SQLite'ta **UNIX EPOCH TIMESTAMP IN SECONDS (INTEGER)** olarak saklar (`toUtc().millisecondsSinceEpoch ~/ 1000`). Okuma esnasında `DateTime.fromMillisecondsSinceEpoch(val * 1000, isUtc: true)` ile nesneleştirilir. Dolayısıyla veritabanındaki `next_retry_at` sütunu bir `INTEGER`'dır.
- **`CURRENT_TIMESTAMP` Tip Afinitesi (Type Affinity) Hatası:**  
  SQLite'ın yerleşik `CURRENT_TIMESTAMP` fonksiyonu `'YYYY-MM-DD HH:MM:SS'` UTC formatında bir **TEXT** string döndürür.  
  SQLite Type Affinity kuralları (SQLite 3 Spec 4.3) uyarınca, bir sayısal değer (`INTEGER`), bir `TEXT` değeri ile karşılaştırıldığında sayısal değer **daima metinden küçük (`INTEGER < TEXT`) sayılır**.  
  Bu sebeple ham SQL'de `next_retry_at <= CURRENT_TIMESTAMP` yazılması durumunda, `next_retry_at` gelecekteki bir zaman olsa dahi (`1794709680 <= '2026-11-15 02:30:00'`) ifade **DAİMA TRUE** döner! Bu durum backoff bekleme süresini tamamen etkisiz kılarak hatalı erken rezervasyona yol açar.
- **Doğru Tarih Karşılaştırma Yöntemi:**
  1. *Parametreli UTC Saniye Değeri (Önerilen ve Taşınabilir):* Dart tarafından `final nowEpoch = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;` hesaplanır ve SQL'e **pozisyonel `?` yer tutucusu** ile verilir. Karşılaştırma `INTEGER <= INTEGER` olarak kesinleşir.
  2. *Yerel SQLite Fonksiyonu:* Ham SQL fonksiyonu gerekiyorsa, SQLite 3.38+ için `unixepoch()` veya eski SQLite sürümleri için `CAST(strftime('%s', 'now') AS INTEGER)` tamsayı fonksiyonları kullanılır. `CURRENT_TIMESTAMP` kesinlikle kullanılmaz.
- **Drift `customUpdate` Parametre Bağlama Uyumluluğu (D1 — Doğrulanmış):**
  Drift `customUpdate` API'si **pozisyonel `?` yer tutucularını** kullanır; **adlandırılmış `:param` söz dizimini desteklemez**. Parametreler `List<Variable<Object>>` listesi olarak sıralı şekilde bağlanır. API imzası: `Future<int> customUpdate(String query, {List<Variable<Object>> variables, Set<ResultSetImplementation>? updates})`. Bu nedenle SQL sorgusundaki `:now_epoch` adlandırılmış parametresi `?` ile değiştirilmeli ve Dart tarafında `variables: [Variable<int>(nowEpoch)]` listesiyle bağlanmalıdır.
- **NULL `nextRetryAt` Davranışı:**  
  `status = 'PENDING'` olan bir kayıtta `next_retry_at` daima `NULL`'dır ve ilk koşuldan doğrudan rezerve edilir.  
  `status = 'RETRY'` olan bir kayıtta `next_retry_at` normalde bir zaman damgası taşır; ancak olası bir veri tutarsızlığında kuyruğun sonsuza dek kilitlenmesini engellemek için `(next_retry_at IS NULL OR next_retry_at <= ?)` kuralı uygulanır.
- **Saat Dilimi Standardı:** Tüm tarih damgaları ve hesaplamalar kesinlikle **UTC (`isUtc: true`)** standardındadır. Yerel saat dilimi farkları veritabanı hesaplamalarına asla sokulmaz.

```sql
-- Koşullu Atomik FIFO ve RETRY Rezervasyon Sorgusu (Strict Head-of-Line Blocking — D1):
-- ? parametresi = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 (INTEGER)
-- Drift bağlama: variables: [Variable<int>(nowEpoch)]
UPDATE outbox_operations
SET status = 'IN_PROGRESS',
    updated_at = CAST(strftime('%s', 'now') AS INTEGER)
WHERE operation_id = (
  -- Kuyruktaki en küçük client_seq'e sahip aktif/bekleyen kaydı seç:
  SELECT operation_id FROM outbox_operations
  WHERE status IN ('PENDING', 'IN_PROGRESS', 'RETRY', 'FAILED_PERMANENT')
  ORDER BY client_seq ASC
  LIMIT 1
)
AND (
  status = 'PENDING'
  OR (status = 'RETRY' AND (next_retry_at IS NULL OR next_retry_at <= ?))
);
```

- **Drift Çağrı Örneği (Kesin Dart Kodu):**
  ```dart
  final nowEpoch = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  final int rowsUpdated = await db.customUpdate(
    'UPDATE outbox_operations '
    'SET status = \'IN_PROGRESS\', '
    '    updated_at = CAST(strftime(\'%s\', \'now\') AS INTEGER) '
    'WHERE operation_id = ('
    '  SELECT operation_id FROM outbox_operations '
    '  WHERE status IN (\'PENDING\', \'IN_PROGRESS\', \'RETRY\', \'FAILED_PERMANENT\') '
    '  ORDER BY client_seq ASC LIMIT 1'
    ') '
    'AND ('
    '  status = \'PENDING\' '
    '  OR (status = \'RETRY\' AND (next_retry_at IS NULL OR next_retry_at <= ?))'
    ')',
    variables: [Variable<int>(nowEpoch)],
    updates: {db.outboxOperations},
    updateKind: UpdateKind.update,
  );
  // rowsUpdated == 1: Rezervasyon başarılı
  // rowsUpdated == 0: Head-of-Line blocking veya başka worker kapılmış
  ```

- **Drift API Doğrulaması ve Etkilenen Satır Sayısı (`rowsUpdated` — D6):**  
  Drift `customUpdate` API imzası: `Future<int> customUpdate(String query, {List<Variable<Object>> variables, Set<ResultSetImplementation>? updates, UpdateKind? updateKind})`. Parametreler **pozisyonel `?` yer tutucuları** ile bağlanır; adlandırılmış `:param` söz dizimi Drift tarafından **desteklenmez**. Dönen `Future<int>` değeri SQLite `changes()` fonksiyonunun sonucudur (etkilenen satır sayısı).
  - Yukarıdaki Drift çağrı örneğinde görüldüğü gibi: `variables: [Variable<int>(nowEpoch)]` listesindeki ilk eleman, SQL sorgusundaki tek `?` yer tutucusuna bağlanır.
  - `updates: {db.outboxOperations}` parametresi Drift'in reaktif stream'lerini bilgilendirir; `updateKind: UpdateKind.update` parametresi ise stream güncelleme isabetini artırır.

- **Drift Transaction ve `BEGIN IMMEDIATE` Uyumu:**  
  Drift'in `db.transaction(() async { ... })` API'si Dart asenkron transaction yöneticisini kullanır. SQLite WAL modunda ham `BEGIN IMMEDIATE` çalıştırmak Drift'in iç bağlantı havuzu ve transaction durumu ile doğrulanmadan kesin uygulama kodu olarak iddia edilemez. Bu nedenle sistemde eşzamanlılık; uygulama düzeyinde `SyncCoordinator` Mutex'i (`package:synchronized`), `ClientSyncService` iç kilidi ve veritabanı düzeyinde `customUpdate` dönen `rowsUpdated` kontrolü ile üç kademeli (defense-in-depth) güvenceye alınır.

- **Kuyruk Durumlarının Deterministik Davranış Matrisi (D1):**

| En Düşük `client_seq` Kaydının Durumu | Rezervasyon Koşulu | `rowsUpdated` Sonucu | Kuyruk Davranışı |
|---|---|---|---|
| **`PENDING`** | Koşulsuz geçerli | `1` | Kayıt rezerve edilir (`IN_PROGRESS`); ağa gönderilir. |
| **`RETRY` (Süresi Dolmuş)** | `next_retry_at <= ?` (`nowEpoch`) | `1` | Kayıt rezerve edilir (`IN_PROGRESS`); yeniden ağa gönderilir. |
| **`RETRY` (Süresi Dolmamış)** | `next_retry_at > ?` (`nowEpoch`) | `0` | **Rezerve edilmez; kuyruk bloke edilir (Head-of-Line Blocking).** |
| **`IN_PROGRESS`** | Rezerve edilemez | `0` | **Rezerve edilmez; mevcut uçuş tamamlanana dek kuyruk bekler.** |
| **`FAILED_PERMANENT`** | Rezerve edilemez | `0` | **Rezerve edilmez; operatör çözene dek kuyruk kalıcı kilitlenir.** |
| **Daha yüksek `client_seq`** | Alt sorgu en küçüğü seçer | `0` | **Hiçbir koşulda öne geçemez, sıra atlayamaz.** |

#### 5. Idempotency Mekanizması ($deviceId:$clientSeq) vs Eşzamanlılık Kontrolü Ayrımı:
- **Idempotency Standardı:** Hub tarafındaki satış sözleşmesinde idempotency anahtarı **KESİNLİKLE `$deviceId:$clientSeq`** standardındadır (`server.dart` satır 994). Outbox tablosundaki yerel `operation_id` ise yalnızca istemci içi UUID v4 birincil anahtardır.
- `IN_PROGRESS` kurtarma ve ağ yanıtı kaybı senaryolarında, aynı `client_seq` ve aynı `$deviceId:$clientSeq` anahtarı ile tekrar gönderim yapıldığında Hub mükerrer satış veya çift stok düşüşü yapmaz; önceden üretilmiş `200 OK` yanıtını döner.
- **KRİTİK MİMARİ KURAL:** *Idempotency mekanizması, istemci tarafındaki eşzamanlılık (concurrency) kontrolünün YERİNE GEÇMEZ.*
- İstemci tarafındaki Mutex, servis kilidi ve atomik `IN_PROGRESS` rezervasyonu (`changes() == 1`); istemci içinde yarış durumlarını, mükerrer ağ trafiğini ve sıra bozulmasını önlemek için **birincil ve zorunlu koruma katmanıdır**. Idempotency ise yalnızca ağdaki paket tekrarlarının sunucu tarafındaki nihai filtresidir.

---

## 6. Android Cihaz Eşleştirme ve HTTPS/TLS Güven Mimarisi

> [!NOTE]
> **Windows Bootstrap ile Android Pairing Karıştırılmamalıdır.**  
> Windows Kasa UI, Hub ile aynı fiziksel makinede çalışır; loopback ve DPAPI kullanır.  
> Android cihazlar fiziksel olarak ayrıdır; yerel Wi-Fi / LAN üzerinden bağlanır; QR içinde gömülü CA ve Android Keystore kullanır.  
> İki sürecin güvenlik akışları tamamen ayrıdır.

### 6.1. Güven Zinciri Başlangıç Problemi ve QR Tabanlı Çözümü

> [!CRITICAL]
> **İlk Bağlantı Güven Problemi (Bootstrap Trust Problem):**  
> Android cihaz henüz Hub'ın `ca.crt` dosyasını bilmemektedir. Bu durumda:  
> — `badCertificateCallback = true` ile bağlanmak MITM saldırısına kapı açar. **Kesinlikle yasaktır.**  
> — HTTP üzerinden `ca.crt` indirip ardından HTTPS'e geçmek, güven zincirini başlatmak için güvensizdir.  
> — HTTPS üzerinden `ca.crt` indirip parmak izi doğrulamak, `badCertificateCallback` olmadan doğrudan çalışmaz.  
> **Çözüm: CA sertifikası ve eşleştirme bilgisi QR kodu içine gömülür. Ağ üzerinden CA alımı gerekmez.**

**QR Tabanlı Güven Zinciri Başlatma Modeli:**

Güven zincirine başlangıç noktası ağ üzerinden değil, **fiziksel QR kodu tarama** eylemi üzerinden sağlanır. Fiziksel eşleştirme güven modeli şu varsayıma dayanır: Yönetici Hub ekranında üretilen QR kodunu görmüş ve bunu meşru bir Android cihaza okutmuştur. Bu fiziksel yakınlık koşulu, QR içindeki CA ve parmak izinin aynı kaynaktan geldiğini garanti eder.

> [!WARNING]
> **QR'ın Sağladığı ve Sağlamadığı Güvence:**  
> QR içindeki CA sertifikası ve SHA-256 parmak izi **birbirini bağımsız olarak doğrulamaz**. İkisi de aynı kaynaktan, aynı QR içinde gelmektedir. Sahte bir QR kodu kendi CA'sını ve eşleşen parmak izini içerebilir.  
> Güvenlik modeli, **QR kodunun güvenilir bir fiziksel kaynaktan (Hub ekranından) okunduğu** varsayımına dayanır. QR'ı üreten Hub'ın kontrolündeki ekran güven çapasıdır.  
> Bu nedenle eşleştirme işlemi, Hub'ı yöneten yetkili kişi (İşletme Sahibi / Yönetici) gözetiminde ve Hub'ın kendi ekranından yapılmalıdır.

**QR Payload İçeriği ve Boyut Yönetimi (Pilot Standardı):**

Pilot aşamasında ağ bağımlılığını ve güvensiz geçici TLS bağlantılarını tamamen ortadan kaldırmak için **tek ve zorunlu standart** olarak tam CA sertifikasının QR içinde kompakt DER biçiminde taşınması benimsenmiştir:

```json
{
  "v": 1,
  "hub_url": "https://MARKET-KASA-01:8443",
  "session_id": "sess_9f8a12bc",
  "pairing_secret": "sec_8f9a2b13c4d5",
  "expires_at": 1731609600,
  "ca_der_b64": "<DER formatı Base64 — yakl. 1.2 KB>",
  "ca_fp_sha256": "AA:BB:CC:...:FF"
}
```
- **Alanların Görev Ayrımı:**
  - `session_id`: Hub üzerindeki eşleştirme oturumunu tekil olarak tanımlar (Hub'ın hangi oturumu denetleyeceğini ve kilitleyeceğini belirler).
  - `pairing_secret`: QR kod üzerinden cihaza aktarılan ve oturumun ilk doğrulamasında kullanılan tek kullanımlık sırdır (`sec_...`).
- **Boyut ve Tarama Kapasitesi:** Tipik QR kodu (Versiyon 40, ECC Hata Düzeltme Seviyesi L) yaklaşık 3–4 KB ikili veri taşıyabilmektedir. 1.2 KB'lık kompakt DER CA ve JSON üstveri tek bir QR kodu içinde rahatlıkla barındırılır; bilgisayar monitöründen cep telefonu veya el terminali kamerasıyla saniyeler içinde taranabilir.
- **Fiziksel Güven Modeli:** QR payload'ının asimetrik imzalanması tek başına ilk bağlantı güven sorununu çözemez; çünkü Android cihaz henüz Hub'ın genel anahtarına güvenmemektedir. Bu nedenle güven çapası **Fiziksel Yakınlık ve Hub Ekranı Güven Çapasıdır (Physical Proximity & Visual Out-of-Band Trust Anchor)**. İşletme sahibi Hub makinesinin kendi ekranında gösterilen dinamik QR kodunu yetkili cihazla bizzat tarar. Güvenilirlik fiziksel ekranın doğrudan kontrolünden kaynaklanır.

- **Android Eşleştirme Sırrı (Pairing Secret) Yanlış Deneme Sayacı ve Oturum Kilitleme Protokolü (D3):**

  > [!NOTE]
  > **Oturum Saklama Modeli:** Mevcut Hub kaynak kodu ([`pairing_manager.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/pairing_manager.dart#L102)) incelendiğinde, eşleştirme oturumları bellekteki `Map<String, PairingSession> _sessions` yapısında tutulmaktadır. Pilot aşamasında Hub tek Dart izolasyonunda (single-isolate) çalıştığından bu model yeterlidir; veritabanına taşınması gerekmemektedir.

  1. *Oturum Kimliği (`session_id`) ve Sır (`pairing_secret`) Zorunluluğu:* İstemci `POST /api/v1/pairing/request` gövdesinde `session_id` ve `pairing_secret` göndermek zorundadır. `session_id` olmadan Hub yanlış denemenin hangi oturuma ait olduğunu belirleyemez. Mevcut kod bu yaklaşımı doğrudan uygulamaktadır: `registerRequest` metodu `sessionId` parametresini zorunlu alır ve `getSession(sessionId)` ile oturumu bulur.
  2. *Yanlış Deneme Sayacı ve Bellek İçi Kilitleme:* [`PairingSession`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/pairing_manager.dart#L45-L76) sınıfı `failedSecretAttempts` tamsayı alanı taşır. Gelen `pairingSecret` yanlış ise Hub sayacı 1 artırır; eğer sayaç $\ge 3$ ise `session.status = PairingSessionStatus.locked` yaparak oturumu kilitler (HTTP `401 Unauthorized (INVALID_PAIRING_SECRET)`).
  3. *3 Deneme Sınırı ve Kilit Aşımı Koruması:* 3 hatalı denemeden sonra oturum kalıcı olarak kilitlenir (HTTP `403 Forbidden (SESSION_LOCKED)`). `getSession()` metodu ([satır 160-166](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/pairing_manager.dart#L160-L166)) kilitleme kontrolünü sıranın başında yapar; 3. denemeden sonra doğru secret girilse dahi kilitli oturum kesinlikle kabul edilmez.
  4. *Süre Sonu, Tüketilme ve Kilitlenme Durumlarının Kesin Ayrımı:*
     - `404 Not Found (SESSION_NOT_FOUND)`: Oturum kimliği `_sessions` map'inde bulunamadı ([satır 145-149](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/pairing_manager.dart#L145-L149)).
     - `410 Gone (SESSION_EXPIRED)`: 5 dakikalık oturum geçerlilik süresi doldu (`session.isExpired`, [satır 152-158](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/pairing_manager.dart#L152-L158)).
     - `409 Conflict (SESSION_ALREADY_BOUND)`: Oturum zaten bir cihaza bağlanmış (`session.status != PairingSessionStatus.created`, [satır 195-201](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/pairing_manager.dart#L195-L201)). İkinci bir cihazın aynı oturumu kullanması engellenir.
     - `403 Forbidden (SESSION_LOCKED)`: 3 hatalı deneme kotası aşılmış ve oturum kilitlenmiş ([satır 160-166](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/pairing_manager.dart#L160-L166)).
     - `401 Unauthorized (INVALID_PAIRING_SECRET)`: Eşleştirme sırrı yanlış ([satır 183-193](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/pairing_manager.dart#L183-L193)); yanıt gövdesinde kalan deneme hakkı bildirilebilir.
  5. *Eşzamanlılık Modeli (Dart Single-Isolate Güvencesi):* Dart'ın tek iş parçacıklı olay döngüsü (event loop) modeli sayesinde, bellekteki `PairingSession` nesnelerine erişim doğası gereği sıralıdır (sequential). İki eşzamanlı HTTP isteği geldiğinde Shelf her isteği ayrı bir `Future` olarak kuyruğa alır; ancak Dart izolasyonu bunları **sıralı olarak** yürütür. Bu nedenle:
     - `failedSecretAttempts++` işlemi ve ardından gelen `>= 3` kontrolü sıralı çalışır; lost update yarış durumu oluşmaz.
     - İki eşzamanlı `registerRequest` çağrısında ilki `status = PairingSessionStatus.created` kontrolünü geçip `pendingApproval` yapar; ikincisi `SESSION_ALREADY_BOUND` (409) alır.
     - `approveSession` çağrısında token üretimi ve DB yazımı `WriteQueue` üzerinden sıraya alınır; RAM tamponuna (`deliveryBuffer`) token kaydı tek seferde yapılır.
     - **KRİTİK MİMARİ KISITLAMA:** Bu eşzamanlılık güvencesi yalnızca Hub'ın **tek Dart izolasyonunda** çalıştığı pilot mimaride geçerlidir. Çoklu izolasyon veya çoklu Hub süreci mimarisine geçildiğinde bellekteki `Map` yapısı yeterli olmaz; veritabanı düzeyinde atomik güncelleme gerekir.
  6. *Hız Sınırlaması (Rate Limiting) Durumu:* Kaynak kod incelemesinde ([`spike_01_backend/bin/server.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart) ve [`pairing_manager.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/pairing_manager.dart)) Hub üzerinde IP bazlı bir rate limit middleware'inin **henüz bulunmadığı doğrulanmıştır**. Bu bir **uygulanmamış güvenlik gereksinimidir**; mevcut özellik değildir. Tasarım hedefi olarak IP bazında dakikada en fazla 5 istek kısıtı uygulanması planlanmaktadır. Oturum düzeyinde challenge kota kontrolü (`maxChallengesPerSession = 5`) ve cooldown (`challengeCooldown = 5 sn`) ise `_applyRateLimitAndQuota` metodu ile mevcuttur ([satır 634-663](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/pairing_manager.dart#L634-L663)).
- **Alternatiflerin Reddi:** Sertifikanın ağdan indirilmesi veya `badCertificateCallback = true` gibi geçici bypass yaklaşımları mimariden tamamen çıkarılmıştır; hiçbir koşulda desteklenmez.

### 6.2. Android Cihaz Eşleştirme Akışı

```
  Android Flutter UI                  Windows Master Hub
  (mobil_market_pos)                  (mms_backend.exe)
         │                                   │
         │                                   │  Hub: Yönetici "Yeni Cihaz Ekle"
         │                                   │  düğmesine basar.
         │                                   │  PairingManager.createSession()
         │                                   │  → pairing_secret (sec_...) üretilir (5 dk geçerli)
         │                                   │  → session_id + pairing_secret + CA DER + fp + hub_url
         │                                   │    QR payload'ına dahil edilir
         │                                   │  → Hub ekranında QR gösterilir
         │                                   │
         │  1. Yönetici gözetiminde QR taranır
         │     session_id, pairing_secret, hub_url, ca_der_b64, ca_fp_sha256 belleğe alınır
         │
         │  2. İstemci taraflı doğrulama (Kanonik DER baytları):
         │     derBytes = base64Decode(ca_der_b64)
         │     SHA-256(derBytes) == ca_fp_sha256?
         │     HAYIR → Hata: QR içeriği tutarsız, işlem iptal
         │     EVET  → Parmak izi doğrulandı (Kritik: PEM'den değil DER'den)
         │
         │  3. DER -> PEM Dönüşümü & SecurityContext oluşturulur:
         │     pemBytes = derToPemBytes(derBytes)  [PEM kodlama zorunludur]
         │     SecurityContext(withTrustedRoots: false)
         │     .setTrustedCertificatesBytes(pemBytes)
         │     badCertificateCallback = (cert, host, port) => false
         │     [Doğrudan DER verilmez; BoringSSL PEM bekler]
         │
         │  4. POST /api/v1/pairing/request                  │
         │     Headers: Authorization olmadan (pairing rotası)│
         │     Body: { session_id: "sess_9f8a12bc",          │
         │             pairing_secret: "sec_8f9a2b13c4d5",   │
         │             device_id: "ANDROID-<UUID>",           │
         │             name: "Samsung A54",                   │
         │             platform: "ANDROID",                   │
         │             client_public_key: "<ECDSA_P256_PUB>" }│
         │     [HTTPS — ca.crt PEM ile doğrulanmış TLS]       │
         ├───────────────────────────────────────────────────>│
         │                                                    │  PairingManager.registerRequest(...)
         │                                                    │  → Yanlış ise failedSecretAttempts++ (3 olunca kilitle)
         │                                                    │  → Doğru ise status = pendingApproval
         │<───────────────────────────────────────────────────┤
         │  202 Accepted: { status: 'PENDING_APPROVAL' }      │
         │                                                    │  Hub: Yönetici onaylar (/api/v1/pairing/approve)
         │                                                    │  → Token üretilir (RAM deliveryBuffer)
         │  5. Token teslimi (Challenge-Response & Poll):     │
         │     POST /api/v1/pairing/poll-challenge & poll     │
         │<───────────────────────────────────────────────────┤
         │  200 OK: { raw_token }                             │
         │                                                    │
         │  6. Kalıcı güvenli depoya yaz:                     │
         │     token     → Android Keystore (AES-256-GCM)     │
         │     ca_pem    → uygulamaya özel şifreli depo       │
         │     hub_url   → EncryptedSharedPreferences         │
         │                                                    │
         │  7. Bellek temizlenir (pairing_secret, session_id) │
         │                                                    │
         │  8. Normal senkronizasyon başlar                   │
         │     Authorization: Bearer <token>  [HTTPS — ca.crt]│
         ▼                                                    ▼
```

### 6.3. CA Sertifikasının Güvenli Aktarımı, DER/PEM Ayrımı ve TLS API Uyumluluğu

#### 1. Platform TLS API Beklentileri Doğrulaması (Dart SDK `dart:io`)

Dart SDK `dart:io` kütüphanesinin (`SecurityContext`) platform düzeyinde TLS sertifikası kabul kuralları resmi SDK dokümantasyonu doğrultusunda şöyledir:

| Platform | TLS Arka Uç Motoru | `setTrustedCertificatesBytes` Beklenen Biçim | Doğrudan DER Verilirse Davranış |
|---|---|---|---|
| **Android** | BoringSSL / OpenSSL | **PEM (ASCII kodlu X.509 baytları)** | `TlsException: Failure in setTrustedCertificates` (Hata!) |
| **Windows** | BoringSSL / OpenSSL | **PEM (`ca.crt` dosya içeriği baytları)** | `TlsException: Failure in setTrustedCertificates` (Hata!) |
| **Linux** | OpenSSL | **PEM** | `TlsException` |
| **iOS** *(Karşılaştırma)* | Apple SecureTransport | **Tekil DER baytları** (Apple Security framework kısıtı) | PEM verilirse SecureTransport çözümleyemez |

> [!CRITICAL]
> **Android ve Windows için PEM Zorunluluğu:**  
> Hem Windows hem de Android platformlarında Flutter/Dart `dart:io` motoru BoringSSL/OpenSSL bağlamını kullanır.  
> Bu motorlar `setTrustedCertificatesBytes(List<int> bytes)` metoduna doğrudan ikili DER baytları verildiğinde sertifika başlangıç başlığını (`-----BEGIN CERTIFICATE-----`) aramakta ve bulamayınca çökmektedir.  
> Dolayısıyla **hem Windows'ta hem de Android'de `SecurityContext.setTrustedCertificatesBytes` metoduna MUTLAKA PEM kodlu baytlar verilmelidir.**

---

#### 2. QR Eşleştirmede DER ve PEM Ayrımı Standardı

Android QR eşleştirme sürecinde DER ve PEM formatlarının rolleri kesin kurallarla ayrılmıştır:

1. **QR İçi Taşıma (Kompakt DER):**
   - QR kodunun boyutunu optimize etmek (~1.2 KB tasarruf sağlamak) amacıyla sertifika QR içinde **ikili DER biçiminde** ve Base64 kodlu (`ca_der_b64`) olarak taşınmaya devam eder.
   - PEM başlıkları ve satır sonları QR payload'ına eklenmez; böylece QR kodu mobil kameralar tarafından çok daha hızlı ve yüksek çözünürlük gerektirmeden taranır.
2. **SHA-256 Parmak İzi Doğrulaması (Kanonik DER):**
   - Parmak izi (`ca_fp_sha256`), QR'dan çözülen ham **ikili DER baytları** (`Uint8List`) üzerinden SHA-256 ile hesaplanır ve sabit zamanlı (`constantTimeEquals`) doğrulanır:
     ```dart
     final Uint8List derBytes = base64Decode(qrData['ca_der_b64']);
     final String computedFingerprint = sha256.convert(derBytes).toString().toUpperCase();
     if (!constantTimeEquals(computedFingerprint, qrData['ca_fp_sha256'])) {
       // Parmak izi tutarsız: QR sahte, değiştirilmiş veya bozulmuş!
       throw SecurityException('QR CA parmak izi uyuşmazlığı — işlem iptal edildi.');
     }
     ```
   - **Kritik Kural:** Parmak izi hesaplaması KESİNLİKLE PEM metni üzerinden yapılmaz; çünkü satır sonu karakterleri (`\r\n` vs `\n`) veya boşluk farklılıkları parmak izi özetini bozar.
   - **Kritik Kural:** Parmak izi doğrulaması başarıyla tamamlanmadan sertifika güvenilir kabul edilemez ve TLS güven deposuna eklenemez.
3. **DER → PEM Dönüştürme (TLS API Uyumluluğu):**
   - Parmak izi doğrulandıktan hemen sonra, DER baytları Dart TLS API'sinin beklediği PEM formatına dönüştürülür:
     ```dart
     List<int> derToPemBytes(Uint8List derBytes) {
       final b64 = base64Encode(derBytes);
       final buffer = StringBuffer('-----BEGIN CERTIFICATE-----\n');
       for (int i = 0; i < b64.length; i += 64) {
         buffer.writeln(b64.substring(i, math.min(i + 64, b64.length)));
       }
       buffer.write('-----END CERTIFICATE-----\n');
       return utf8.encode(buffer.toString());
     }
     ```
   - **İçerik Dokunulmazlığı:** Dönüşüm sırasında sertifikanın X.509 ASN.1 içeriği, genel anahtarı, geçerlilik süresi ve imzası en ufak biçimde değişmez; yalnızca ikili baytlar standart ASCII armoring ile sarılır.
4. **TLS Güven Deposuna Ekleme:**
   - Elde edilen `pemBytes`, `SecurityContext.setTrustedCertificatesBytes(pemBytes)` metoduna verilir.
   - Doğrudan DER baytları kesinlikle verilmez.
   - Şifreli depoya (`EncryptedSharedPreferences` / Android Keystore) dönüştürülmüş PEM baytları kaydedilir; böylece sonraki her bağlantıda tekrar dönüşüm yapma maliyeti sıfırlanır.

---

#### 3. Pilot Standart Güven Akışı (Tam Kök CA QR İçinde — Sıfır Ağ Bağımlılığı)

Pilot aşamasında tek ve zorunlu akış şöyledir:
1. `ca_der_b64` QR'dan base64 decode edilir (ham ikili DER baytları elde edilir).
2. `SHA-256(derBytes)` hesaplanır ve QR'daki `ca_fp_sha256` ile sabit zamanlı (`constantTimeEquals`) karşılaştırılır.
3. Eşleşmezse işlem tamamen iptal edilir; CA güven deposuna kesinlikle eklenmez.
4. Eşleşirse `derBytes` derhal standart PEM formatına dönüştürülür (`derToPemBytes`).
5. `pemBytes` uygulamaya özel şifreli Trust Store'a kaydedilir.
6. Sonraki tüm HTTPS bağlantıları bu PEM CA üzerinden işletim sistemi kökleri dışlanarak doğrulanır.
7. **Ağ üzerinden CA indirme veya geçici güvensiz el sıkışma (`badCertificateCallback = true`) kesinlikle yoktur.**

**Uygulamaya Özel CA Trust Store:**

Android, işletim sistemi genelindeki sertifika deposunu değiştirmeye ihtiyaç duymaz. CA yalnızca uygulamaya özel depoda tutulur:
- **Pilot için:** `EncryptedSharedPreferences` (Jetpack Security / `androidx.security`).
- **Üretim için:** Android Keystore destekli `KeyStore` ile şifrelenmiş özel alan.
- Flutter'da: `flutter_secure_storage` paketi bu iki altyapıyı soyutlar.
- Bu CA hiçbir surette sistem sertifika deposuna (`system trust store`) eklenmez.

---

#### 4. Kayıt Sonrası HTTPS Bağlantısı, CA Zinciri ve Hostname/IP SAN Doğrulaması

Sertifika kalıcı şifreli depoya yazıldıktan sonraki tüm API ve senkronizasyon bağlantılarında şu yapılandırma zorunludur:

```dart
// 1. Şifreli depodan PEM baytlarını oku:
final pemBytes = await secureStorage.readBytes('mms_ca_cert_pem');

// 2. OS köklerini tamamen dışlayan SecurityContext oluştur:
final context = SecurityContext(withTrustedRoots: false); // OS kökleri dışla
context.setTrustedCertificatesBytes(pemBytes);           // Yalnızca PEM kodlu Market MMS Root CA

// 3. Sertifika doğrulama bypass'ını kesinlikle kapat:
final httpClient = HttpClient(context: context)
  ..badCertificateCallback = (cert, host, port) => false; // Asla bypass yok!
```

Dart TLS motoru el sıkışmasında iki aşamalı tam doğrulama uygular:
- **Kök CA Zincir Doğrulaması (Chain of Trust):** Hub sunucusunun sunduğu yaprak sertifikanın (`server.crt`), yalnızca ve yalnızca güvenilen PEM formatındaki `ca.crt` tarafından imzalanmış olduğu kriptografik imza doğrulamasıyla teyit edilir. Başka hiçbir genel/özel CA kabul edilmez.
- **Hostname ve IP SAN Doğrulaması:** İstemcinin bağlandığı URI host bilgisi (`hub_url`), sunucu yaprak sertifikasındaki `Subject Alternative Name (SAN)` listesi ile (`DNS:MARKET-KASA-01`, `IP:192.168.1.100` vb.) tam olarak eşleşmek zorundadır.

---

#### 5. Sertifika Doğrulama Hatasında Kesin Bağlantı Kesme (Strict Termination / No Bypass)
- `badCertificateCallback` kesinlikle `false` döner. Kullanıcıya "Yine de devam et" seçeneği veya onay penceresi **ASLA SUNULMAZ**.
- Sertifika süresi dolmuşsa, imza geçersizse veya Hostname/IP SAN eşleşmezse Dart TLS motoru derhal `HandshakeException` / `TlsException` fırlatır.
- **Bağlantı anında ve kesin olarak kesilir (Hard Socket Termination).**
- Sunucuya hiçbir HTTP isteği, Bearer token veya satış verisi paketi iletilmez; aradaki adam (MITM) dinlemesi ve veri sızıntısı sıfıra indirilir.
- **Hata Günlükleme ve İstemci İzolasyonu (D8):** TLS el sıkışması başarısız olduğunda TCP/TLS soketi derhal kapatılır ve hiçbir HTTPS bağlantısı kurulamaz. Bu nedenle hata **Hub sunucusuna HTTP üzerinden BİLDİRİLEMEZ ve Hub audit log'una ASLA yazılamaz**. Ayrıca mevcut kod tabanında (`client_local.db` — [`client_database.dart`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/database/client_database.dart)) henüz yerel bir `audit_logs` tablosu **bulunmamaktadır (henüz uygulanmamış geliştirme gereksinimi)**. İstemci tarafında TLS el sıkışma hataları geçici olarak uygulama içi tanılama/log katmanında ele alınmalı; yerel denetim tablosu uygulama fazında eklenmelidir.
- Kasa arayüzünde `[🔒 GÜVENLİ BAĞLANTI HATASI (TLS)]` uyarısı verilir ve gerekiyorsa operatöre yeniden eşleştirme ekranı sunulur.
- **HTTP Fallback Yasağı:** Güvenli bağlantı kurulamadığında şifresiz HTTP'ye düşmek (`http://`) veya sertifika kontrolünü devre dışı bırakmak (`badCertificateCallback = true`) **KESİNLİKLE YASAKTIR**.

### 6.4. Android Yeniden Eşleştirme Senaryoları

| Senaryo | Trigger | Yeniden Eşleştirme? | Davranış |
|---|---|---|---|
| **Hub LAN IP değişti (makine adı aynı)** | DHCP yenileme | **HAYIR** | `DNS:MARKET-KASA-01` SAN'da; bağlantı kesintisiz devam eder |
| **Hub makine adı değişti** | Makine yeniden adlandırma | **EVET** | Yeni QR eşleştirme; eski `ca.crt` aynıysa token korunabilir |
| **Hub Root CA yenilendi** | `ca.crt` değişti | **EVET** | TLS `HandshakeException`; uygulama yeniden eşleştirme ekranını açar |
| **Hub adresi değişti (port dahil)** | Servis yapılandırma değişikliği | **EVET** | Yeni QR eşleştirme; CA aynıysa token korunabilir |
| **Cihaz Hub tarafından iptal edildi** | `403 ERR_DEVICE_REVOKED` | **HAYIR** | Hub konsolundan yeniden aktifleştirme; token korunur |
| **Token geçersiz** | `401 ERR_INVALID_TOKEN` | **EVET** | Yeni QR eşleştirme; yeni token |
| **Android cihaz fabrika ayarlarına döndü** | Keystore temizlendi | **EVET** | Yeni QR eşleştirme; token kayboldu |
| **SAN uyuşmazlığı (IP değişti, SAN güncellenmedi)** | `HandshakeException` | **HAYIR** | Hub servisi yeniden başlar, SAN güncellenir; token ve CA korunur |

### 6.5. Aşama Ayrımı (Android Pairing)
- **Mevcut Kodda Doğrulanan:** [`pairing_manager.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/security/pairing_manager.dart) `pairing_secret` tabanlı mobil eşleştirme mekanizması; `auth_middleware` Bearer token doğrulaması doğrulanmıştır.
- **Önerilen Yeni Davranış:** CA sertifikasının QR içine gömülmesi (Seçenek A); parmak izi QR'dan sabit zamanlı doğrulama; ağ üzerinden CA alımından vazgeçme; Android Keystore token saklaması; uygulamaya özel Trust Store.
- **Henüz Uygulanmamış İş:** Android Flutter istemcisinde QR payload parser; CA Trust Store kurulumu; `AndroidKeystoreTokenStorage`; parmak izi doğrulama akışı; yeniden eşleştirme tetikleyici.

---

## 7. Güvenlik Tehditleri ve Karşı Önlemler (Threat Model)

1. **Tehdit T-1: Token Çalınması (Credential Theft):**
   - *Risk:* Kasiyerin veya bilgisayara erişen birinin diskten token'ı alıp harici bir cihazdan sahte satış göndermesi.
   - *Önlem:* Token diskte düz metin olarak **asla** saklanmaz. Windows DPAPI `CurrentUser` ile şifrelenir (`%LOCALAPPDATA%\MarketMMS\security\device_token.dpapi`). Dosya başka bir Windows kullanıcısına veya makineye kopyalansa dahi çözülemez.
2. **Tehdit T-2: Yerel Ağda Araya Girme (MITM on LAN / Rogue Proxy):**
   - *Risk:* Mağaza yerel ağına bağlanan bir saldırganın DNS zehirlemesi veya sahte sertifika ile satış verilerini dinlemesi/değiştirmesi.
   - *Önlem:* `withTrustedRoots: false` ile işletim sistemi kökleri dışlanır, yalnızca Hub'ın özel Root CA'sı (`ca.crt`) kabul edilir. `badCertificateCallback` kesinlikle `false` döner.
3. **Tehdit T-3: Bootstrap Replay ve Sahte Cihaz Kaydı:**
   - *Risk:* Ağdaki yabancı bir cihazın bootstrap anahtarını tahmin etmesi veya tekrar kullanarak Hub'a yetkisiz cihaz kaydetmesi.
   - *Önlem:* Bootstrap rotası `127.0.0.1` loopback zorunludur (dış ağa kapalı). Anahtar veritabanında tuzlu hash olarak saklanır, tek kullanımlıktır, tüketildiğinde diskteki dosya silinir ve 3 hatalı denemede kilitlenir.
4. **Tehdit T-4: Head-of-Line Blokajı ve Outbox Kilitlenmesi:**
   - *Risk:* Yetkilendirme veya ağ hatalarının satış kayıtlarını kalıcı hatalı (`FAILED_PERMANENT`) yaparak kasayı kilitlemesi.
   - *Önlem:* 401/403 hataları `SyncAuthState.authRequired` / `deviceRevoked` olarak işlenir; `error_category = 'AUTH_ERROR'` ile işaretlenir; outbox kayıtları `PENDING`'de tutulur ve yetki sağlandığında otomatik devam eder.
5. **Tehdit T-5: Windows Kullanıcı Değişimi ve Servis Yetki Çatışması:**
   - *Risk:* Windows Service (`SYSTEM`) ile Windows UI (`Kasiyer`) DPAPI anahtarlarının birbirini çözememesi veya dosya izinlerinin çakışması.
   - *Önlem:* Servis sırrı (`pepper.dpapi`) `%PROGRAMDATA%` altında `SYSTEM` hesabı ve admin izinleriyle izole edilir. İstemci sırrı (`device_token.dpapi`) `%LOCALAPPDATA%` altında kullanıcı düzeyinde izole edilir. İki katman yalnızca yerel HTTPS API üzerinden haberleşir.
6. **Tehdit T-6: Android QR Sahtekârlığı (QR Spoofing):**
   - *Risk:* Saldırganın sahte QR kodu göstererek Android cihazı kendi sahte Hub'ına yönlendirmesi.
   - *Önlem:* Güven çapası doğrudan Hub ekranının fiziksel kontrolüdür (fiziksel yakınlık ve görsel kanal). QR içindeki `ca_der_b64` baytlarının SHA-256 özeti, QR'daki `ca_fp_sha256` ile sabit zamanlı (`constantTimeEquals`) doğrulanır. Parmak izi tutarsızsa işlem derhal reddedilir; sahte Root CA güven deposuna kesinlikle eklenmez.

---

## 8. Önerilen Bileşenler ve Kodlama Mimarisi

Faz 1.3.1 kodlamasında oluşturulacak ve genişletilecek mimari bileşenler:

```
lib/core/security/
├── device_token_storage.dart               # Token saklama arayüzü (Interface)
├── windows_dpapi_token_storage.dart        # Windows DPAPI CurrentUser somut implementasyonu (FFI Crypt32)
├── android_keystore_token_storage.dart     # Android Keystore somut implementasyonu (Faz 2 — Pilot)
└── in_memory_token_storage.dart            # Testler için bellekte saklama implementasyonu

lib/core/network/
├── root_ca_provider.dart                   # %PROGRAMDATA%\MarketMMS\certs\ca.crt okuyucu (Windows)
├── android_ca_provider.dart                # EncryptedSharedPreferences'tan ca.crt okuyucu (Android)
└── http_sync_transport_factory.dart        # withCustomRootCa ile HTTPS transport üretici

lib/features/sync/
├── application/
│   ├── sync_coordinator_notifier.dart       # Auth durumu, Outbox timer, FIFO mutex yönetim StateNotifier'ı
│   └── sync_providers.dart                  # Riverpod provider zinciri (Transport, Service, Coordinator)
└── domain/
    ├── sync_auth_state.dart                 # unconfigured, authenticated, authRequired, deviceRevoked, permissionDenied, unknownAuthError
    └── outbox_summary.dart                  # pending, retry, failedPermanent, totalUnsynced model nesnesi
```

---

## 9. Tasarım Kararları Özeti: Doğrulanan, Önerilen ve Uygulanmamış Alanlar Matrisi

| Güvenlik / Mimari Alanı | Mevcut Kodda Doğrulanan Özellik | Önerilen Yeni Davranış | Henüz Uygulanmamış İş |
|---|---|---|---|
| **Cihaz Bootstrap (OD-SEC-01)** | `server.dart`'ta loopback kontrolü ve `TokenManager` token hashleme. | Tek kullanımlık 256-bit bootstrap anahtarı; loopback `POST` rotası; crash recovery temizliği; standart kullanıcıya GUI aktarımı; `Uint8List` ile bellek yaşam süresini en aza indirme (D7). | `bootstrap_keys` tablosu; bootstrap Shelf handler'ı; Flutter kurulum sihirbazı; başlangıç temizlik rutini. |
| **Token Güvenliği & Cihaz Kaydı (OD-SEC-03 & D4)** | `dpapi.dart` FFI `CryptProtectData`; `TokenManager` Bearer token doğrulama; `renew-token` rotası. | Süresiz token; `isActive = false` iptal modeli; 4 cihaz durumunun ayrılması (Yeni cihaz INSERT, mevcut rotasyon UPDATE, iptal edilmiş cihaz, bulunamayan cihaz — D4); atomik iptal ve replay koruması. | `WindowsDpapiTokenStorage`; Riverpod provider entegrasyonu; atomik token rotasyonu ve 4 durumlu cihaz yönetimi. |
| **DPAPI İzolasyonu** | `spike_01_backend`'de `LocalMachine` kapsamlı pepper koruması. | Hub (`SYSTEM`/ProgramData) ve İstemci (`CurrentUser`/LocalAppData) için ayrı güvenlik sınırları. | Flutter UI projesine DPAPI FFI sarmalayıcısının taşınması. |
| **Kök CA Erişimi (OD-SEC-02)** | `CertificateManager` ile 10 yıllık Root CA üretimi. | Windows: `%PROGRAMDATA%\MarketMMS\certs\ca.crt` dosyasından; Android: QR DER bayt parmak izi doğrulaması sonrası Keystore'dan. | `RootCaProvider`; `AndroidCaProvider`; hata yönetimi. |
| **TLS Güven Modeli & Günlükleme (D8)** | `sync_transport.dart` `HttpSyncTransport.withCustomRootCa` fabrikası. | Özel Kök CA Güven Doğrulaması (OS kökleri dışlanır; leaf pinning yapılmaz; hostname/IP SAN ve zincir doğrulanır; hata anında kesin bağlantı kesilir; el sıkışma hatası Hub'a iletilemez). | İstemci bağlantısının fabrikaya geçirilmesi; istemci tarafında yerel denetim/tanılama tablosunun eklenmesi (D8). |
| **SAN & IP Yönetimi** | `CertificateManager.generateServerCertificate` SAN listesi. | Servis açılışında dinamik LAN IP tespiti ve SAN güncellemesi. | IP tespit fonksiyonu; otomatik yaprak sertifika yenileme. |
| **Outbox 401/403 Yönetimi (D2, D5, D6)** | `auth_middleware.dart` `{'error': ...}` yanıtları (`UNAUTHORIZED`, `INVALID_TOKEN`, `DEVICE_NOT_FOUND`, `DEVICE_REVOKED`); `ClientSyncService` HTTP durum kodları. | Yapılandırılmış hata sınıflandırması (`body['error'] ?? body['code']`); `IN_PROGRESS → PENDING`; `ERR_AUTH_REQUIRED` ve `ERR_INVALID_TOKEN` için seçici requeue (reconciliation); rol kontrolü (`ERR_INSUFFICIENT_PERMISSION`) önerisi. | `ClientSyncService` satır 142 düzeltmesi; `error_category`/`error_code` sütunları; rol bazlı yetkilendirme middleware'i (D5). |
| **SyncCoordinator Durum Makinesi** | Mevcut `ClientSyncService` döngüsü. | 6 durumlu `SyncAuthState` enum; `AUTH_REQUIRED`, `DEVICE_REVOKED`, `PERMISSION_DENIED`, `UNKNOWN_AUTH_ERROR` ayrımı; başlangıçta IN_PROGRESS temizliği. | `SyncCoordinatorNotifier` Riverpod StateNotifier. |
| **Eşzamanlılık ve FIFO Rezervasyonu (D1 & D6)** | `OutboxOperations` tablosunda `nextRetryAt` sütunu mevcuttur (`DateTimeColumn`). Drift varsayılanında SQLite'ta `INTEGER` unix epoch saniye saklandığı (`client_database.dart`), `CURRENT_TIMESTAMP` fonksiyonunun `TEXT` döndürdüğü ve `INTEGER < TEXT` tip afinitesi hatası nedeniyle backoff'u tamamen etkisiz kıldığı doğrulanmıştır. Drift `customUpdate` API'sinin adlandırılmış `:param` değil **pozisyonel `?` yer tutucuları** kullandığı doğrulanmıştır. `ClientSyncService` sıralı döngüsü. | Çift katmanlı koruma: Tek çağrı noktası kuralı, `SyncCoordinator` Mutex, `ClientSyncService` iç kilidi; SQLite tip afinitesi hatasını önleyen pozisyonel `?` tamsayı parametresi (`variables: [Variable<int>(nowEpoch)]`) ile koşullu atomik FIFO rezervasyonu (`PENDING` veya süresi dolmuş `RETRY` — D1); Drift `customUpdate` dönen `Future<int>` etkilenen satır sayısı kontrolü (`rowsUpdated == 1` — D6); `$deviceId:$clientSeq` Idempotency sözleşmesi ile güvenli kurtarma. | `Mutex` entegrasyonu; `ClientSyncService._isExecuting` kontrolü; pozisyonel `?` parametreli atomik rezervasyon SQL'i; UTC zaman standardizasyonu. |
| **Android Pairing & Eşleştirme Sırrı Sayacı (D3)** | `pairing_manager.dart`'ta `PairingSession` ile bellekte oturum yönetimi (`Map<String, PairingSession> _sessions`). `failedSecretAttempts` sayacı ve `PairingSessionStatus.locked` ile 3 denemede kilitleme mevcuttur. `getSession()` kilitleme kontrolünü sıranın başında yapar. Dart tek iş parçacıklı olay döngüsü (single-isolate event loop) sayesinde bellekteki sayaç ve durum güncellemeleri sıralı çalışır; lost update yarış durumu oluşmaz. Oturum düzeyinde challenge kota kontrolü (`maxChallengesPerSession = 5`) ve cooldown (`challengeCooldown = 5 sn`) mevcuttur. IP rate limiting middleware'i **mevcut değildir (uygulanmamış güvenlik gereksinimi)**. | İstemcinin `session_id` ve `pairing_secret` göndermesi zorunluluğu (mevcut kodda uygulanıyor); `registerRequest` ile `status != created` kontrolüyle ikinci cihaz bağlanması engeli (`409 SESSION_ALREADY_BOUND`); `approveSession` ile `WriteQueue` üzerinden atomik DB kaydı; `deliveryBuffer` ile RAM'de token teslimi; QR içinde kompakt DER Kök CA ve DER→PEM dönüşümü; Android Keystore token saklaması. | `spike_01_backend`'e IP bazlı rate limit middleware'inin eklenmesi **(uygulanmamış güvenlik gereksinimi)**; Android istemci `AndroidKeystoreTokenStorage`; DER parmak izi ve PEM dönüştürme akışı; çoklu izolasyona geçişte bellek içi `Map` yapısının veritabanına taşınması. |
| **HTTP Fallback Yasağı** | `AGENTS.md` Bölüm 6'da tanımlı. | `https://127.0.0.1:8443`; `badCertificateCallback = false` her iki platformda koşulsuz kapalıdır. | URL sabitlerinin güncellenmesi; HTTPS Shelf portunun açılması. |

---

## 10. Karar Önerileri ve Kesinleşen Standartlar

Proje sahibinin yönergeleri doğrultusunda kesinleşen 3 çekirdek güvenlik kararı:

1. **`OD-SEC-01` (Windows Masaüstü Bootstrap Standardı):**  
   Windows ilk kurulumunda tek kullanımlık, kriptografik olarak güvenli 256-bit bootstrap anahtarı kullanılacaktır. Anahtar kurulum esnasında `%PROGRAMDATA%\MarketMMS\setup\bootstrap.key` (NTFS ACL: Yalnızca SYSTEM/Admin) dosyasına yazılacak; loopback üzerinden `POST /api/v1/devices/local-bootstrap` rotasıyla bir kez tüketilecek ve işlem biter bitmez dosya diskten silinecektir. Arayüz tarafında bellek yaşam süresini en aza indirmek için `Uint8List` kullanılacak ve işlem sonrası bellek derhal sıfırlanacaktır (D7).
2. **`OD-SEC-02` (Kök CA Dağıtım ve Güven Standardı):**  
   Windows istemcisi, Hub tarafından üretilen Kök CA sertifikasını ACL korumalı `%PROGRAMDATA%\MarketMMS\certs\ca.crt` dosyasından yerel dosya sistemi üzerinden doğrudan okuyacaktır. İstemci işletim sistemi köklerine güvenmeyecek (`withTrustedRoots: false`), yalnızca bu özel Kök CA'ya güvenecek, ancak yaprak sertifika pinning yapmayarak sunucu sertifikası yenilenmelerinde kesinti yaşamayacaktır.
3. **`OD-SEC-03` (Cihaz Token Yaşam Döngüsü Standardı):**  
   Windows masaüstü istemcisi için periyodik süre dolumu olmayan, **süresiz** cihaz token'ı verilecektir. Güvenlik, cihaz bazlı anlık iptal edilebilirlik (`isActive = false`) ile sağlanacak; token istemci makinesinde Windows DPAPI `CurrentUser` kapsamı ile `%LOCALAPPDATA%\MarketMMS\security\device_token.dpapi` dosyasında saklanacaktır.

---

## 11. Faz 1.3.1 Uygulama Fazına Geçiş Kabul Kriterleri

Aşağıdaki kabul kriterleri karşılanmadan Faz 1.3.1 kodlama aşamasına başlanamaz:

- [x] `PHASE_1_3_1_AUTH_TLS_DESIGN.md` raporunda `OD-SEC-01`, `OD-SEC-02` ve `OD-SEC-03` kararlarının kesinleştirilmesi.
- [x] Windows Service (`SYSTEM`) ve Windows UI (`CurrentUser`) DPAPI güvenlik sınırlarının ve kullanıcı kapsamı farklarının belgelenmesi.
- [x] LAN IP / DHCP değişikliklerinde sertifika doğrulamasını kapatmadan dinamik SAN ve loopback ile çözümün tanımlanması.
- [x] 401/403 yanıtlarında Outbox kayıtlarının `FAILED_PERMANENT` yapılmayıp `PENDING`'de tutulması ve kuyruğun askıya alınması sözleşmesinin belirlenmesi.
- [x] Tanınan yapılandırılmış hata alanlarının (`body['error'] ?? body['code']`) eşleştirilmesi, tanınmayanların `ERR_UNKNOWN_AUTH` yapılması ve `requeueAuthFailedOperations` sorgusunun standart kodlarla (`ERR_AUTH_REQUIRED`, `ERR_INVALID_TOKEN`) birebir tutarlı tasarlanması (D2 & D5).
- [x] Tek kullanımlık bootstrap anahtarının üretim, saklama (`%PROGRAMDATA%\MarketMMS\setup\bootstrap.key`), tüketim, silinme ve crash recovery yaşam döngüsünün netleştirilmesi; Dart bellek katmanları ve yaşam süresi azaltma yaklaşımının tanımlanması (D7).
- [x] Standart Windows kullanıcısına bootstrap anahtarının güvenli aktarım protokolünün tanımlanması.
- [x] `withCustomRootCa` yönteminin leaf pinning değil, "Private Root CA Trust Validation" olduğunun kriptografik olarak açıklığa kavuşturulması.
- [x] Outbox hata sınıflandırmasında yapılandırılmış `error_category`/`error_code` standardının tanımlanması; `classifyHttpError` dönüş tipinin `({String category, String code})` olarak standartlaştırılması.
- [x] `IN_PROGRESS → PENDING` geri dönüş sözleşmesi ve servis çöküşü sonrası başlangıç temizliğinin tasarlanması.
- [x] Outbox FIFO ve atomik rezervasyon mekanizmasının tasarlanması: daha düşük `client_seq` tamamlanmadan sonraki işlemin rezerve edilmesinin engellenmesi, Head-of-Line blocking kuralı, `PENDING` ve süresi dolmuş `RETRY` ayrımı, SQLite tip afinitesi hatasını önleyen pozisyonel `?` tamsayı parametresinin (`variables: [Variable<int>(nowEpoch)]`) Drift `customUpdate` API'si ile uyumlu kullanımı ve dönen `Future<int>` satır sayısı kontrolünün tanımlanması (D1 & D6).
- [x] Hub idempotency sözleşmesinin `$deviceId:$clientSeq` standardına bağlanması; ağ yanıtı kaybı ve `IN_PROGRESS` kurtarma senaryolarında güvenli tekrar gönderim garantisinin belgelenmesi.
- [x] `SyncCoordinator` durum makinesinde 6 durumlu `SyncAuthState` mimarisinin, çift katmanlı eşzamanlılık engelinin (Mutex ve servis içi kilit) belirlenmesi.
- [x] Android ilk bağlantı güven zinciri için Seçenek B ve `badCertificateCallback = true` yaklaşımının tamamen kaldırılarak tek standart olan QR içinde kompakt DER CA (Seçenek A) ve fiziksel ekran güven modelinin benimsenmesi.
- [x] Android eşleştirme güvenlik kurallarının (`pairing_secret`, 5 dakika geçerlilik, tek kullanım, 3 hatalı deneme sınırı, `session_id` oturum bağlayıcılığı, bellek içi `PairingSession` durum makinesiyle eşzamanlı talep engeli) netleştirilmesi ve IP bazlı hız sınırlamasının henüz uygulanmamış bir güvenlik gereksinimi olduğunun açıkça belgelenmesi (D3).
- [x] Token yenilemede 4 cihaz durumunun (Yeni INSERT, rotasyon UPDATE, iptal edilmiş cihaz, bulunamayan cihaz) ve `rowsAffected == 0` kontrolünün tanımlanması (D4).
- [x] Android Kök CA için ikili ASN.1 DER bayt parmak izi gösterimi, Dart TLS API (`setTrustedCertificatesBytes`) uyumluluğu için DER→PEM dönüşümü, hostname/IP SAN ve zincir doğrulaması ile doğrulama hatasında bağlantının kesin kesilmesinin belgelenmesi.
- [x] TLS el sıkışma hatalarının Hub sunucusuna iletilemeyeceğinin, istemci tarafında da `audit_logs` tablosunun henüz mevcut olmadığının (uygulanmamış iş) ve HTTP fallback yasağının belgelenmesi (D8).
- [x] Cihaz türüne göre token yenileme (Windows loopback bootstrap vs Android QR/pairing_secret) ayrımı ve atomik iptal/replay korumasının tanımlanması.
- [x] Her tasarım maddesinde "Doğrulanan Özellik", "Önerilen Davranış" ve "Uygulanmamış İş" ayrımının yapılması.
- [ ] **Proje Sahibinin bu güncellenmiş tasarım dokümanını incelemesi ve açık onay vermesi.**

---

### 11.1. D1 — Outbox FIFO & SQLite DateTime Rezervasyon Doğrulama Test Senaryoları

Faz 1.3.1 kodlamasında `packages/mms_client_storage` altında uygulanacak zorunlu birim ve entegrasyon test senaryoları:

1. **Test D1-1 (Retry zamanı geçmiş kayıt):**  
   - *Girdi:* Kuyruktaki en küçük `client_seq` kaydı `status = 'RETRY'` ve `next_retry_at = now_epoch - 30` (geçmiş zaman).  
   - *Beklenen:* Atomik rezervasyon sorgusu kaydı başarıyla `IN_PROGRESS` durumuna geçirir; `rowsUpdated == 1` döner; işlem ağa gönderilmek üzere worker'a iletilir.
2. **Test D1-2 (Retry zamanı gelecekte olan kayıt — Head-of-Line Blocking):**  
   - *Girdi:* Kuyruktaki en küçük `client_seq = 1` kaydı `status = 'RETRY'` ve `next_retry_at = now_epoch + 60` (gelecek zaman). Kuyrukta arkasından gelen `client_seq = 2` kaydı ise `status = 'PENDING'`.  
   - *Beklenen:* Atomik rezervasyon sorgusu 0 satır günceller (`rowsUpdated == 0`). `client_seq = 1` rezerve edilmez; Head-of-Line blocking kuralı gereğince arkadaki `client_seq = 2` kaydı kesinlikle öne geçemez ve rezerve edilemez. Kuyruk beklemede kalır.
3. **Test D1-3 (Retry zamanı NULL olan kayıt kurtarma):**  
   - *Girdi:* Olası veri tutarsızlığı veya migration senaryosu; en küçük `client_seq` kaydı `status = 'RETRY'` ve `next_retry_at IS NULL`.  
   - *Beklenen:* `(next_retry_at IS NULL OR next_retry_at <= ?)` kuralı devreye girer; sorgu kaydı `IN_PROGRESS` olarak günceller (`rowsUpdated == 1`); kuyruk sonsuza dek kilitlenmekten kurtarılır.
4. **Test D1-4 (UTC sınırında ve saat dilimi değişiminde tarih karşılaştırması):**  
   - *Girdi:* Cihazın yerel saat dilimi değiştirilmiş (ör. UTC+3'ten UTC-5'e), kış saati/yaz saati geçişi yapılmış veya gün sonu (23:59:59 → 00:00:00) yaşanmış durum.  
   - *Beklenen:* Drift ve SQL karşılaştırması kesinlikle `toUtc().millisecondsSinceEpoch ~/ 1000` (saniye cinsinden tamsayı INTEGER) üzerinden yapıldığından yerel saat dilimi değişimlerinden ve metin biçimlendirme farklarından etkilenmez; zaman karşılaştırması deterministik olarak doğru çalışır.
5. **Test D1-5 (Aynı `client_seq` sırasındaki atomik rezervasyon yarışı):**  
   - *Girdi:* İki paralel senkronizasyon worker'ı veya eşzamanlı iki işlem aynı anda rezervasyon sorgusunu çalıştırır (`client_seq = 5`, `status = 'PENDING'`).  
   - *Beklenen:* SQLite transaction izolasyonu ve `status = 'PENDING'` koşulu sayesinde yalnızca İLK çalışan worker `rowsUpdated == 1` alır ve işlemi üstlenir; İKİNCİ çalışan worker ise kaydın durumu artık `IN_PROGRESS` olduğu için `rowsUpdated == 0` alır. Mükerrer işleme veya sıra atlama kesinlikle gerçekleşmez.

---

### 11.2. D3 — Android Pairing Eşleştirme Sırrı (`pairing_secret`) & Kilitleme Doğrulama Test Senaryoları

Faz 1.3.1 / Faz 2 Hub kodlamasında `test_spikes/spike_01_backend` ve Android istemci altında uygulanacak zorunlu test senaryoları:

1. **Test D3-1 (Birinci yanlış eşleştirme sırrı denemesi):**  
   - *Girdi:* İstemci geçerli bir `session_id` ve geçersiz `pairing_secret` ile eşleştirme talebi gönderir.  
   - *Beklenen:* Hub oturumu bellek içi `_sessions` map'inden bulur; `failedSecretAttempts` sayacını 1 artırır (`failedSecretAttempts = 1`). Yanıt: HTTP `401 Unauthorized` (`error: 'INVALID_PAIRING_SECRET'`, kalan hak: 2). Oturum henüz kilitlenmez.
2. **Test D3-2 (İkinci yanlış eşleştirme sırrı denemesi):**  
   - *Girdi:* İstemci aynı oturum için ikinci kez geçersiz `pairing_secret` gönderir.  
   - *Beklenen:* Hub `failedSecretAttempts` sayacını 1 artırır (`failedSecretAttempts = 2`). Yanıt: HTTP `401 Unauthorized` (`error: 'INVALID_PAIRING_SECRET'`, kalan hak: 1). Oturum henüz kilitlenmez.
3. **Test D3-3 (Üçüncü yanlış deneme ve otomatik oturum kilitleme):**  
   - *Girdi:* İstemci aynı oturum için üçüncü kez geçersiz `pairing_secret` gönderir.  
   - *Beklenen:* Hub `failedSecretAttempts` sayacını 1 artırır (`failedSecretAttempts = 3`); sayaç eşiğe ulaştığı için oturum durumunu `PairingSessionStatus.locked` yapar. Yanıt: HTTP `403 Forbidden` (`error: 'SESSION_LOCKED'`, `message: 'Oturum güvenlik nedeniyle kilitlendi'`).
4. **Test D3-4 (Kilitlenmiş oturuma doğru sır girilmesi):**  
   - *Girdi:* 3 hatalı denemeden sonra kilitlenmiş bir oturum için istemci bu kez DOĞRU `pairing_secret` değerini gönderir.  
   - *Beklenen:* `getSession()` metodu `session.status == PairingSessionStatus.locked` kontrolünü sır doğrulamasından ÖNCE çalıştırır; talep derhal reddedilir: HTTP `403 Forbidden` (`error: 'SESSION_LOCKED'`). Kilitli oturum kesinlikle açılamaz.
5. **Test D3-5 (Süresi dolmuş oturum):**  
   - *Girdi:* Oturum oluşturulduktan 5 dakika 1 saniye sonra istemci doğru `session_id` ve doğru sır ile istek yapar.  
   - *Beklenen:* Hub zaman aşımını doğrular (`session.isExpired`); durum `PairingSessionStatus.expired` yapılır ve istek reddedilir: HTTP `410 Gone` (`error: 'SESSION_EXPIRED'`).
6. **Test D3-6 (Daha önce bağlanmış oturum — Replay/Tekrar kullanım koruması):**  
   - *Girdi:* Zaten onay bekleyen veya onaylanmış bir oturum için (`session.status != PairingSessionStatus.created`), başka bir cihaz veya saldırgan aynı `session_id` ile tekrar istek gönderir.  
   - *Beklenen:* `registerRequest` içindeki `status != created` kontrolü devreye girer; talep reddedilir: HTTP `409 Conflict` (`error: 'SESSION_ALREADY_BOUND'`).
7. **Test D3-7 (İki eşzamanlı yanlış istek — Bellek içi yarış durumu koruması):**  
   - *Girdi:* İki paralel HTTP isteği aynı anda aynı `session_id` için yanlış sır gönderir (Başlangıç `failedSecretAttempts = 0`).  
   - *Beklenen:* Dart tek iş parçacıklı olay döngüsü (single-isolate event loop) sayesinde bellek içi sayaç artırma işlemleri sıralı işlenir; lost update yarış durumu oluşmaz; iki isteğin sonunda sayaç kesinlikle `2` olur.
8. **Test D3-8 (Aynı oturum için iki eşzamanlı doğru talep):**  
   - *Girdi:* İki paralel HTTP isteği aynı anda aynı `session_id` ve doğru sır ile cihaz kaydı (`registerRequest`) yapmaya çalışır.  
   - *Beklenen:* Sıralı olay döngüsünde BİRİNCİ istek `session.status = PairingSessionStatus.pendingApproval` atamasını yapar; İKİNCİ istek `status != created` durumunu görerek HTTP `409 Conflict` (`SESSION_ALREADY_BOUND`) ile reddedilir. Asla iki farklı cihaza aynı oturum üzerinden mükerrer onay/token verilmez.
9. **Test D3-9 (Aynı IP adresinden dakikada altı istek — Rate limiting):**  
   - *Girdi:* Aynı IP adresinden 60 saniye içerisinde 6 adet eşleştirme isteği gönderilir.  
   - *Beklenen:* Hub'a IP rate limiting middleware'i eklendiğinde **(henüz uygulanmamış güvenlik gereksinimi)**; ilk 5 istek normal işlenir, 6. istek ise oturum kontrolüne dahi girmeden HTTP `429 Too Many Requests` (`error: 'RATE_LIMIT_EXCEEDED'`) ile geri çevrilir.
