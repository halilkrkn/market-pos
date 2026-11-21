# MARKET MMS — Üretim, Kurulum ve Dağıtım Kılavuzu

Bu kılavuz, **MARKET MANAGEMENT SYSTEM (MARKET MMS)** sisteminin Windows Local Master Hub, Windows Masaüstü Kasa İstemcisi ve Android El Terminali istemcisi için pilot/üretim ortamı kurulumunu, güvenlik yapılandırmasını (`B-2`, `B-3`, `S-4`) ve yedekleme/kurtarma (`S5A-4`) prosedürlerini tanımlar.

---

> **21.11.2026 (Teknik Düzeltme Oturumu) Güncellemesi:** `hub_config.json` tek kaynak kuralından env fallback temizliği (ADR-015), `BackupOperationLock` heartbeat + 60 sn kurtarma ve Hub kilit entegrasyonu (ADR-016), TLS CA/SAN/tarih hata sınıflandırması (ADR-017), Android Keystore fail-closed hata eşleme + `minSdk 24 (Android 7.0)` (ADR-020 `DEFERRED_POST_PILOT`) ve pilot için onaylanan **%20 KDV geçici operasyonel kısıtları** (ADR-019 `DEFERRED_POST_PILOT`) dokümante edilmiştir. Güncel bütünleşik rapor: [`PILOT_TECHNICAL_REMEDIATION_REPORT.md`](./PILOT_TECHNICAL_REMEDIATION_REPORT.md). **Fiziksel kabul testleri (PAT-01…15) henüz çalıştırılmamıştır; sistem üretime hazır değildir.**
>
> **21.11.2026 (3. oturum) güncellemesi:** Kurulum betiği v2.1 (güncellemede önce servis durdurma, `bin.previous` ile otomatik geri dönüş), tüm `.ps1` betikleri Windows PowerShell 5.1 uyumlu (UTF-8 BOM), firewall yalnızca yerel alt ağ, Android otomatik (Google) yedekleme kapalı, restore koruyucu kopyası şifreli. Adım adım saha kabulü: [`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`](../PHYSICAL_ACCEPTANCE_TEST_PLAN.md). Owner'ın yapması gerekenler: [`OWNER_ACTION_CHECKLIST.md`](../OWNER_ACTION_CHECKLIST.md).

## 1. Mimari Özet

- **Merkezi Sunucu (Windows Local Master Hub):** `mms_backend.exe` (Dart Shelf HTTPS API, TCP `8945`, UDP LAN Keşif `8946`) + `%PROGRAMDATA%\MarketMMS\data\market_master.db` (tekil SQLite WAL yazıcı).
- **Windows Masaüstü İstemci:** `market_pos.exe` + `%LOCALAPPDATA%\MarketMMS\client_local.db` (Hub'a HTTP/HTTPS loopback üzerinden bağlanır; doğrudan `market_master.db`'ye erişmez).
- **Android Mobil İstemci:** Offline-first yerel Drift SQLite (`client_local.db`) + kamera barkod/QR tarama + LAN keşfi (`UDP 8946`) + güvenli token depolama (`AndroidKeyStore`).

---

## 2. Windows Master Hub Kurulum Adımları (Yönetici PowerShell)

1. **Release Paketini Hazırlayın:**
   ```powershell
   .\scripts\package_windows_release.ps1
   ```
2. **Dizin İzinlerini ve ACL İzolasyonunu Uygulayın:**
   ```powershell
   .\test_spikes\spike_01_backend\scripts\setup_service_acls.ps1
   ```
   Bu adım `C:\ProgramData\MarketMMS\` altında yalnızca `SYSTEM` ve `Administrators` erişimine izin verir; standart kasiyer Windows kullanıcılarının `market_master.db` veya `pepper.dpapi` dosyalarına erişmesini engeller.
3. **WinSW Windows Servisini Kurun ve Başlatın:**
   ```powershell
   .\test_spikes\spike_01_backend\scripts\install_mms_service.ps1
   ```
4. **Windows Güvenlik Duvarı Kurallarını Açın (`TCP 8945`, `UDP 8946`):**
   ```powershell
   .\scripts\configure_hub_firewall.ps1 -Profile Private
   ```
   Kurallar varsayılan olarak yalnızca yerel alt ağa açıktır (`-RemoteAddress LocalSubnet`). Not: 2. adım isteğe bağlıdır; kurulum betiği ACL betiğini zaten çağırır.
5. **Güncelleme:** Önce şifreli Hub yedeği alın, ardından `install_mms_service.ps1`'i yeniden çalıştırın. Başarısız güncellemede betik önceki ikililere otomatik döner (ayrıntı: [`release/WINDOWS_HUB_RELEASE.md`](./release/WINDOWS_HUB_RELEASE.md) §3).

---

## 3. Android Release APK Hazırlama

```powershell
.\scripts\package_android_release.ps1 -Version 1.0.0
```
Çıktılar `dist\android_release\` klasöründe (`market_mms_v1.0.0.apk`, `.sha256` ve örnek `manifest.json`) üretilir.

> **Not (Sürüm İmzalama):** `android/key.properties` yoksa release derlemesi **durur** (21.11.2026'da doğrulandı: `BUILD FAILED — Release imzalama yapılandırılmadı`). Üretim anahtarı Owner tarafından oluşturulur ([`release/ANDROID_RELEASE.md`](./release/ANDROID_RELEASE.md) §2); `key.properties` ve `.jks` Git'e eklenmez. Debug anahtarıyla imzalı paket dağıtılmaz.
>
> **Telefon değişimi:** Android otomatik yedeği kapalı olduğundan uygulama verisi yeni telefona kopyalanmaz. Yeni telefon kurulum sihirbazından geçer ve Hub'a yeniden eşleştirilir; eski telefonun Hub'a gitmemiş işlemi varsa önce senkronize edin.

---

## 4. İlk Kurulum ve Güvenlik Eşleştirmesi (`B-2`, `B-3`, `S-4`)

1. İlk açılışta **Mağaza ve Cihaz Kurulum Sihirbazı** (veya Tanı ekranı -> *Mağaza, Şube ve Cihaz Kurulumu*) üzerinden:
   - `Tenant ID` (İşletme)
   - `Store ID` ve Şube Adı
   - Benzersiz `Device ID` ve Cihaz Adı değerlerini kaydedin. Yapılandırma atomik olarak `client_config.json` dosyasına yazılır.
2. **S-4 Güvenli Cihaz Eşleştirme:**
   - Hub yönetiminden üretilen eşleştirme JSON/URL veya QR kodunu **Cihaz Güvenliği** kartında yapıştırın veya Android cihazda *QR ile Eşleştir* ile okutun.
   - İstemci yerel ECDSA P-256 anahtar çiftini üretir (`POLL`/`ACK` Low-S DER imzalama) ve alınan token'ı:
     - **Windows:** Windows DPAPI (`CurrentUser`, `secure_tokens.dpapi.json`) içinde saklar.
     - **Android:** `AndroidKeyStore` (`AES/GCM/NoPadding`) ile şifreleyip özel `SharedPreferences` içinde saklar.
   - Hub CA parmak izi (`SHA-256`, 64 hex karakter) sabitlenerek **`B-2 Certificate Pinning`** etkinleştirilir.

---

## 5. Şifreli Yedekleme ve Kurtarma (`S5A-4`)

- **Yedek Alma:** Tanı ekranı -> *Şifreli Yedekleme ve Kurtarma (S5A-4)* kartından en az 8 karakterli parola girerek `Şifreli Yedek Al` butonunu kullanın.
  - Canlı WAL veritabanından `VACUUM INTO` anlık görüntüsü alınır.
  - Paket `AES-256-CBC` + `PBKDF2-HMAC-SHA256 (600.000 tur)` + `HMAC-SHA256` Encrypt-then-MAC ile şifrelenir.
- **Geri Yükleme:** Seçilen yedek için `Geri Yükle` -> parola doğrulama -> `PRAGMA integrity_check` -> canlı DB bağlantısının kontrollü askıya alınması -> pre-restore güvenlik yedeği -> atomik dosya değişimi -> canlı DB'nin aynı oturumda yeniden açılması adımları işletilir.
- **Çökme Sonrası Kurtarma:** Uygulama açılışında `DatabaseBackupEngine.recoverPendingRestoreSync` otomatik çalışarak yarıda kalmış restore işlemlerini güvenli şekilde tamamlar veya geri alır. Yedekleme/restore dosya kilidi (`BackupOperationLock`) 10 sn heartbeat ile aktif işlemi korur; çöken süreç kilidi 60 sn sonra kurtarılır ve hem istemci hem Hub tarafında eşzamanlı çakışma engellenir.
- **Android Sınırı:** En az `minSdk 24 (Android 7.0)` gereklidir. Otomatik zamanlanmış yedek Android'de yalnızca uygulama açıkken çalışır (kapalıyken çalışma `ADR-020` ile pilot sonrasına ertelenmiştir).

---

## 5b. Pilot Operasyon Kısıtları (`ADR-019` — %20 KDV Modeli)

- Pilot sürümde Hub veritabanında `categories` tablosu ile `products.vat_rate` / `category_id` sütunları yoktur (`DEFERRED_POST_PILOT`).
- Tüm yeni/sıfırlanan cihazlar ürünleri **%20 KDV** ve `category_id = null` ile indirir; bir cihazda yerel değiştirilen %1/%10 KDV veya kategori diğer cihazlara ve Hub'a taşınmaz.
- Çoklu KDV oranlı mağazada KDV dökümleri cihazlar arasında farklılık gösterebileceğinden resmî mali beyan bu pilot KDV kırılımına dayandırılmamalıdır.
- **Google Drive Yedeği:** Başlangıç pilotunda isteğe bağlıdır; Hub zamanlanmış şifreli yedeği + USB aktarımı yeterlidir.
- **Eşleştirme Bloklayıcıları (`P-BLOCK-1..3`):** İlk TLS+QR eşleştirme öncesi Owner kararı bekleyen protokol bulguları [`OWNER_ACTION_CHECKLIST.md`](../OWNER_ACTION_CHECKLIST.md) §A4'te belgelenmiştir.

---

## 6. Pilot Öncesi Fiziksel Kabul Kontrol Listesi

- [ ] Windows Servis Yöneticisi (SCM) altında `MarketMMSService` servisinin otomatik başlama ve yeniden başlatma kurtarma testi.
- [ ] Standart (admin olmayan) Windows kullanıcısı ile `%PROGRAMDATA%\MarketMMS` erişim reddi (`ACL`) doğrulaması.
- [ ] Gerçek Windows–Android aynı yerel Wi-Fi üzerinde `UDP 8946` otomatik Hub keşfi + fiziksel kamera QR ile `S-4` eşleştirme doğrulaması.
- [ ] Gerçek LAN üzerinde HTTPS CA `B-2` Certificate Pinning + `B-3` Android Keystore yeniden başlatma sonrası token kalıcılık testi.
- [ ] Offline satış -> uygulama yeniden başlatma -> LAN dönüşünde FIFO senkronizasyon -> `S5A-4` yedek/geri yükleme doğrulaması.
- [ ] Tüm maddelerin ayrıntılı adımları, beklenen sonuçları ve kanıt formatı: [`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`](../PHYSICAL_ACCEPTANCE_TEST_PLAN.md) (PAT-01…PAT-15).
