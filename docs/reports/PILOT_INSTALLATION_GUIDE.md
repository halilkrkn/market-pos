# MARKET MMS — İkinci Windows Bilgisayarda Pilot Kurulum ve Kaldırma Kılavuzu

*Tarih: 25 Kasım 2026 · Hedef: Geliştirme bilgisayarından tamamen bağımsız, temiz bir Windows 10/11 (x64) pilot bilgisayarında gerçek mağaza/pilot kurulumu.*

> [!IMPORTANT]
> **Geliştirme ve Pilot Ortamlarının Kesin Ayrımı:** Geliştirme bilgisayarındaki `MarketMMS_Isolated_Test` dizini, test SQLite veritabanları, test TLS sertifikaları ve test kimlik bilgileri **pilot bilgisayara kesinlikle taşınmamalıdır**. Pilot bilgisayarda temiz veritabanı, yeni TLS sertifikaları ve yeni kurulum yapılır.

---

## 1. Kurulum Öncesi Pilot Bilgisayar Kontrol Listesi (§15.3)

Kuruluma başlamadan önce pilot Windows bilgisayarda aşağıdaki **9 kontrolü** read-only çalıştırın ve sonuçları kaydedin:

```powershell
# Yönetici PowerShell üzerinden pilot bilgisayar ön kontrolü (değişiklik yapmaz)
Get-CimInstance Win32_OperatingSystem | Select-Object Caption, OSArchitecture, Version
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Get-Service -Name "MarketMms*" -ErrorAction SilentlyContinue
Get-NetTCPConnection -LocalPort 8945 -State Listen -ErrorAction SilentlyContinue
Get-NetUDPEndpoint -LocalPort 8946 -ErrorAction SilentlyContinue
Get-NetConnectionProfile | Select-Object Name, InterfaceAlias, NetworkCategory
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "169.254.*" } | Select-Object InterfaceAlias, IPAddress
Get-PSDrive C | Select-Object @{N='FreeGB';E={[math]::Round($_.Free/1GB,2)}}
Test-Path "$env:ProgramData\MarketMMS"; Test-Path "$env:LOCALAPPDATA\MarketMMS"
```

| # | Kontrol | Beklenen / Geçer Koşul |
|---|---|---|
| 1 | Windows Sürümü & Mimari | Windows 10 veya Windows 11, **64-bit (`x64`)** |
| 2 | Yönetici Yetkisi | Kurulum için Yönetici (`True`) — günlük kasa kullanımı standart kullanıcı olabilir |
| 3 | Korunan Servis Çakışması | `MarketMmsSpike01` **bulunmamalı** (varsa MSI kurulumu fail-closed durdurur) |
| 4 | Port Uygunluğu | `TCP 8945` ve `UDP 8946` **boş** olmalı |
| 5 | Ağ Profili | Aktif mağaza Wi-Fi/Ethernet profili **`Private`** olmalı (`Public` ise Private'a çevirin) |
| 6 | Sabit LAN IP & TLS | Pilot Hub PC için DHCP rezervasyonu veya statik LAN IPv4 (ör. `192.168.1.50`) |
| 7 | Disk Alanı | `C:` sürücüsünde en az **2 GB** boş alan (DB + yerel yedekler için) |
| 8 | Firewall | Windows Defender Firewall aktif; kurulum `MarketMMS-Hub-*` (`LocalSubnet`, `Private`) kurallarını otomatik ekler |
| 9 | Mevcut Veri / Güvenlik | Önceden `%ProgramData%\MarketMMS` veya `%LOCALAPPDATA%\MarketMMS` varsa **silmeyin**; upgrade/koruma kurallarını izleyin |

---

## 2. Dağıtım Paketleri ve Bütünlük (SHA-256) Doğrulaması

Pilot bilgisayara dosyaları kopyaladıktan sonra kurulumdan önce **mutlaka** SHA-256 hash doğrulaması yapın (MSI paketi Authenticode dijital imzalı değildir — `NotSigned`):

```powershell
Get-FileHash .\MarketMMS-Setup-1.0.0-x64.msi -Algorithm SHA256
# Beklenen (v1.0.0 tray dahil güncel MSI):
# A54DF1AC74CD48AA6974874004C962F249000BACB83CD9AE8C12B0F6BF65FD9C
```

Android tarafında Owner tarafından üretilen APK için:

```powershell
Get-Content .\market_mms_v1.0.0-b1.apk.sha256
Get-FileHash .\market_mms_v1.0.0-b1.apk -Algorithm SHA256
```

---

## 3. Adım Adım Windows Pilot Kurulumu

### Adım 1: TLS Sertifikalarını Güvenli Makinede Üretin (Owner)
[`OWNER_PROVISIONING_CHECKLIST.md`](./OWNER_PROVISIONING_CHECKLIST.md) §2 adımlarını izleyerek:
- Kök CA (`ca.key` + `ca.crt`) üretin (`ca.key` pilot PC'ye **kopyalanmaz**!).
- Sunucu sertifikası (`server.key` + `server.crt`) üretin; `subjectAltName` içinde **zorunlu `IP:127.0.0.1`** + pilot PC'nin **sabit LAN IPv4 adresi** + `DNS:localhost` bulunmalıdır.

### Adım 2: WiX v5 MSI Kurulumunu Çalıştırın (Yönetici)
```powershell
msiexec /i .\MarketMMS-Setup-1.0.0-x64.msi /l*v .\mms_install.log
```
- İlk kurulumda sertifikalar henüz `%ProgramData%\MarketMMS\certs\` altında değilse kurulum `PENDING_TLS_PROVISIONING` durumunda başarıyla tamamlanır (uygulama dosyaları, ACL'ler, firewall kuralları ve varsayılan `hub_config.json` + `admin_secret.txt` oluşturulur).

### Adım 3: TLS Sertifikalarını Yerleştirin ve Servisi Başlatın
1. `ca.crt`, `server.crt`, `server.key` dosyalarını `C:\ProgramData\MarketMMS\certs\` içine koyun (`ca.key` **KOYMAYIN**).
2. `C:\ProgramData\MarketMMS\config\hub_config.json` içinde `environment: "production"`, `port: 8945`, `discovery_port: 8946`, `tls.enabled: true`, `tls.ca_cert: "../certs/ca.crt"`, çoklu NIC varsa `advertise_host: "<SABIT-LAN-IP>"` olduğunu doğrulayın.
3. Yönetici PowerShell ile ACL'leri ve servisi başlatın:
   ```powershell
   & "C:\Program Files\MarketMMS\hub_scripts\setup_service_acls.ps1" -ProgramDataRoot "C:\ProgramData\MarketMMS" -ServiceName "MarketMMSService"
   & "C:\ProgramData\MarketMMS\bin\MarketMMSService.exe" start
   Get-Service MarketMMSService
   ```
4. Pinned health doğrulaması (`ca.crt` ile) veya Windows Client üzerinden doğrulayın.

### Adım 4: Windows Client Başlangıcı, İlk Owner Bootstrap ve Kurtarma Parolası
1. Masaüstü / Başlat Menüsü kısayolundan **Market MMS** (`C:\Program Files\MarketMMS\client\market_pos.exe`) uygulamasını açın.
2. **Kurulum Sihirbazı** ile mağaza adı, şube/tenant (`tenant-default` / `store-main-01` ile uyumlu) ve cihaz adını kaydedin.
3. **Sistem Durumu ve Altyapı Tanılama** sekmesine geçin:
   - `C:\ProgramData\MarketMMS\security\admin_secret.txt` dosyasındaki yönetici anahtarını (Yönetici olarak okuyup) kullanarak **İlk OWNER Kurulumu (Bootstrap)** işlemini tamamlayın.
   - **Merkezi Hub Yedekleme (Google Drive)** kartında **en az 12 karakterli Taşınabilir Kurtarma Parolası** belirleyip **Kurtarma Anahtarını Kaydet** düğmesine basın ve parolayı fiziksel kağıda yazıp güvenli saklayın (loglara veya Drive'a yazılmaz).
   - İsteğe bağlı olarak **Windows Masaüstü ve Sistem Tepsisi** kartından *Windows açılışında otomatik başlat* anahtarını kullanıcı tercihiyle açabilirsiniz.

### Adım 5: Google Drive Merkezi Backup Yapılandırması (İsteğe Bağlı / Önerilen)
- Google Cloud OAuth kurulumu (`C1/C2`) ile derlenmiş Windows Release kullanıyorsanız, **Merkezi Hub Yedekleme** kartında **Google Drive Bağla (Windows PKCE)** ile mağaza Drive hesabını yetkilendirin ve **00:00 Zamanlamayı Aç** ile günlük otomatik yedeklemeyi başlatın.

---

## 4. Android Pilot Kurulumu ve Eşleştirme

1. İmzalı üretim `market_mms_v1.0.0-b1.apk` dosyasını Android (7.0+ / `minSdk 24+`) cihaza yükleyin (SHA-256 doğrulamalı).
2. Android cihazı pilot Hub PC ile aynı mağaza Wi-Fi ağına (AP/İstemci izolasyonu kapalı) bağlayın.
3. Windows Client → **Sistem Durumu** → **Cihaz Eşleştirme Onayı** panelinde **Yeni Eşleştirme QR'ı Oluştur** düğmesine basın.
4. Android uygulamada **Eşleştirme QR'ını Tara** ile QR kodunu okutun ve Windows ekranından gelen cihazı **Onayla** ile onaylayın.
5. Android cihazda `TLS Pin Aktif (B-2)` ve `Güvenli Depo Hazır (B-3)` rozetlerinin yeşil olduğunu doğrulayın.

---

## 5. Güvenli Kaldırma ve Veri Koruma Prosedürü

1. **Veri Korumalı Standart Kaldırma (Önerilen):** Windows Ayarları → Yüklü Uygulamalar → **Market Management System (MMS)** → Kaldır (veya `msiexec /x MarketMMS-Setup-1.0.0-x64.msi`).
   - `MarketMMSService` durdurulur ve kaldırılır.
   - `MarketMMS-Hub-*` firewall kuralları kaldırılır.
   - `HKCU\...\Run\MarketMMSClient` ve yüklü kullanıcı profillerindeki otomatik başlatma kayıtları temizlenir.
   - **`C:\ProgramData\MarketMMS\data\market_master.db`**, `backups\`, `certs\`, `security\` ve `%LOCALAPPDATA%\MarketMMS\client_local.db` **KESİNLİKLE KORUNUR (silinmez)**.
2. **Tam Veri Temizliği (Yalnızca Geri Dönüşsüz İmha Gerektiğinde):** Varsayılan kaldırmada `PURGE_USER_DATA=0` olduğundan veri silinmez; veriyi de silmek için açıkça `PURGE_USER_DATA=1 CONFIRM_PURGE_TOKEN=CONFIRM_DELETE_ALL_MARKET_MMS_DATA` gerekir — öncesinde mutlaka şifreli `.mmsbak` yedeği dışa aktarın.
