# Windows Master Hub Kurulum, Güncelleme ve Servis Kılavuzu — MARKET MMS

*Son güncelleme: 21 Kasım 2026 (Phase 1.1 TLS & `advertise_host` güncellemesi) — REL-01 (ADR-015 + Ek A) & `P-BLOCK-1..3` (`DEC-REV-1..5`)*

## 1. Tek Yapılandırma Kaynağı (REL-01)

Tüm ayarlar `%ProgramData%\MarketMMS\config\hub_config.json` dosyasındadır. Servis (WinSW `MarketMMSService.xml`) yalnızca `--config=...` geçirir. Şablon: `test_spikes/spike_01_backend/config/hub_config.example.json`.

| Anahtar | Varsayılan | Not |
|---|---|---|
| `environment` | `production` | Üretimde TLS ve tenant/store başlık zorunluluğu kapatılamaz |
| `port` / `discovery_port` | 8945 / 8946 | Firewall betiği bu değerleri okur |
| `db_path`, `backup_dir`, `pepper_file` | `..\data`, `..\backups`, `..\security` | Göreli yollar config klasörüne göredir |
| `admin_secret_file` | `..\security\admin_secret.txt` | Kurulumda rastgele üretilir; düz metin `admin_secret` anahtarı **reddedilir** |
| `tls.enabled/cert/key` | `true`, `..\certs\server.crt/.key` | Dosya yoksa veya `server.crt` geçersizse / `IP:127.0.0.1` SAN taşımıyorsa servis açılmaz (**çıkış kodu `78`**) |
| `tls.ca_cert` | `..\certs\ca.crt` | **Üretimde zorunlu (PAIR-CA + `DEC-REV-1`).** Eşleştirme QR'ındaki CA parmak izi ve `/api/v1/pairing/ca-cert` bu dosyadan gelir; geçerli X.509v3 Root CA olmalıdır (`CA:TRUE`, `keyCertSign`, self-issued, yaprak SAN'sız). Yalnızca **genel** CA sertifikası — `ca.key` Hub diskinde bulunmamalıdır (ACL betiği bulursa kurulumu durdurur). `--config=` modunda `ROOT_CA_CERT_FILE` ortam değişkenine fallback yapılmaz |
| `advertise_host` | `null` *(isteğe bağlı)* | Çoklu NIC veya özel ağ durumlarında Hub'ın eşleştirme QR'ında duyuracağı sabit yerel LAN IPv4 adresi (ör. `"192.168.1.50"`). Loopback (`127.x`), APIPA (`169.254.x`), CGNAT (`100.64.0.0/10`), multicast/broadcast ve VirtualBox Host-Only (`192.168.56.x`) adresleri yapılandırma yüklenirken reddedilir (`HubConfigException`). `null` bırakıldığında Hub otomatik SAN ∩ aktif LAN IPv4 çözümlemesini işletir |
| `tenant_id`, `store_id`, `hub_id` | — | Mağaza kimliği; istemci kurulum değerleriyle aynı olmalı |

Bilinmeyen anahtarlar (yazım hataları) açılışı durdurur.

### 1.1 Üretim TLS Sertifika (SAN), `advertise_host`, Açılış (`exit 78`) ve Eşleştirme (`503`) Kuralları

Üretimde `tls.enabled = true` iken Hub sertifikaları ve LAN duyuru adresi şu katı **fail-closed** kurallara tabidir (`bin/server.dart`, `lib/config/hub_config.dart`, `lib/network/hub_lan_address_resolver.dart`):

1. **Zorunlu `IP:127.0.0.1` Loopback SAN (Hub Açılış Fail-Fast — Çıkış Kodu `78`):**
   - Windows yerel kasa istemcisi ve yerel yönetim/eşleştirme uçları `https://127.0.0.1:<port>` adresine bağlanır.
   - Bu nedenle `server.crt` sertifikasının X.509 `subjectAltName` (`iPAddress`) listesinde **`IP:127.0.0.1`** bulunması **mutlak zorunludur** (yalnızca `DNS:localhost` yeterli değildir).
   - `server.crt` eksikse (`ERR_SERVER_CERT_NOT_FOUND`), bozuk DER/PEM ise (`ERR_SERVER_CERT_INVALID`) veya `IP:127.0.0.1` SAN içermiyorsa (**`ERR_SERVER_CERT_MISSING_LOOPBACK_SAN`**), Hub servisi açılışta **çıkış kodu `78`** ile fail-fast olarak durur.
2. **LAN IPv4 ve Hostname SAN Gereksinimi:**
   - Mobil ve ağ üzerindeki istemcilerin TLS sertifikasını doğrulayabilmesi için `server.crt` `subjectAltName` alanında **en az bir aktif LAN IPv4 adresi** (ör. `IP:192.168.1.50`) yer almalıdır; isteğe bağlı olarak yerel hostname (`DNS:localhost,DNS:<hub-hostname>`) da eklenebilir.
   - Örnek güvenli SAN uzantısı (OpenSSL):
     ```text
     subjectAltName=IP:127.0.0.1,IP:192.168.1.50,DNS:localhost,DNS:MARKET-HUB-01
     ```
   - Kök CA (`ca.crt`) X.509v3 (`basicConstraints=critical,CA:TRUE`, `keyUsage=critical,keyCertSign,cRLSign`) olarak ayrı üretilmeli, yaprak SAN taşımamalı ve `ca.key` Hub makinesinde **asla** tutulmamalıdır.
3. **`advertise_host` Çift Doğrulama Koşulu (`SAN` + Aktif Yerel Arayüz):**
   - `hub_config.json` içinde `advertise_host` belirtilmişse bu IPv4 adresi hem `server.crt` SAN IPv4 listesinde bulunmalı hem de Hub makinesinde aktif bir ağ arayüzüne (`OperStatus = Up`, `DadState = Preferred`, non-loopback) atanmış olmalıdır.
   - `advertise_host` `null` (veya tanımsız) ise Hub, Windows x64 `iphlpapi.dll` (`GetAdaptersAddresses` + `GetIfEntry2`) üzerinden `server.crt` LAN IPv4 SAN kümesiyle kesişen aktif fiziksel NIC'i (**Tier 1**: Ethernet/Wi-Fi, `HardwareInterface = true`) veya host LAN sanal anahtarını (**Tier 2**: Hyper-V External vEthernet, RFC1918) otomatik seçer; loopback, APIPA, VPN (WireGuard/Tailscale/OpenVPN), WSL, Docker, VirtualBox ve VMware adaptörlerini dışlar.
4. **Hub Startup Fail (`exit 78`) vs Eşleştirme `HTTP 503` Ayrımı:**
   - **Startup Fail (`exit 78`):** `tls.enabled=true` iken `server.crt`/`server.key`/`ca.crt` eksikse, `hub_config.json` geçersizse veya `server.crt` içinde **`IP:127.0.0.1` SAN yoksa** Hub hiç başlamaz.
   - **Hub Ayakta Kalır, Eşleştirme `HTTP 503` Döner:** Hub yerel kasayı (`127.0.0.1`) kesintiye uğratmamak için LAN SAN / `advertise_host` uyuşmazlığında açılışta `stderr`'e `[WARN] ERR_ADVERTISE_HOST_SAN_MISMATCH` yazar ve çalışmaya devam eder; ancak `POST /api/v1/pairing/session` çağrısı **`HTTP 503`** ile fail-closed reddedilir (QR içine asla `127.0.0.1` veya `UNKNOWN` sızdırılmaz).

| Hata Kodu | Nerede / HTTP | Neden | Çözüm |
|---|---|---|---|
| `ERR_SERVER_CERT_MISSING_LOOPBACK_SAN` | Hub açılışı (`exit 78`) | `server.crt` SAN listesinde `IP:127.0.0.1` yok | `server.crt` sertifikasını `IP:127.0.0.1` + LAN IP SAN ile yeniden imzalayın |
| `ERR_CA_CERT_UNAVAILABLE` | `POST /api/v1/pairing/session` (`503`) | `tls.ca_cert` eksik veya X.509v3 Root CA doğrulamasından geçmedi | Geçerli `ca.crt` dosyasını yerleştirin |
| `ERR_ADVERTISE_HOST_SAN_MISMATCH` | Açılışta `[WARN]`; `/pairing/session` (`503`) | `advertise_host` değeri `server.crt` IPv4 SAN listesinde yok | `server.crt` SAN listesini veya `advertise_host` değerini eşitleyin |
| `ERR_ADVERTISE_HOST_NOT_LOCAL` | `/pairing/session` (`503`) | `advertise_host` makinede aktif bir arayüzde atanmış değil (ör. DHCP değişimi) | Sabit LAN IP atayın veya `advertise_host` / `server.crt` güncelleyin |
| `ERR_HUB_LAN_IP_UNAVAILABLE` | `/pairing/session` (`503`) | `server.crt` SAN ile eşleşen aktif fiziksel/Tier-2 LAN IPv4 bulunamadı | `server.crt` içine aktif LAN IPv4 SAN ekleyin ve ağ bağlantısını doğrulayın |
| `ERR_HUB_LAN_IP_AMBIGUOUS` | `/pairing/session` (`503`) | Birden fazla aktif LAN arayüzü `server.crt` SAN ile eşleşiyor | `hub_config.json` içinde kullanılacak tek IP'yi `advertise_host` olarak tanımlayın |

## 2. Kurulum (Yönetici PowerShell)

```powershell
cd test_spikes\spike_01_backend
.\scripts\build_aot.ps1                 # mms_backend.exe
# Sertifikaları %ProgramData%\MarketMMS\certs\ altına yerleştirin (ca.crt / server.crt / server.key)
.\scripts\install_mms_service.ps1        # dizinler + ACL + sqlite3.dll + config + admin secret + servis + health check
..\..\scripts\configure_hub_firewall.ps1 # TCP/UDP portları hub_config.json'dan
```

Kurulum betiği (`install_mms_service.ps1` + `setup_service_acls.ps1`):
- Mevcut `hub_config.json` ve `admin_secret.txt` dosyalarını **asla ezmez** (güncellemede ayarlar korunur).
- Sertifika yoksa, çalışan servise dokunmadan durur (fail-closed).
- Dart `sqlite3` native-asset ikilisini (`sqlite3.dll`) üretim dizininde **üç konuma** (`bin\`, `bin\lib\` ve `$TargetBaseDir\lib\`) kopyalar ve başarısızlıkta önceki `bin\` yedeğinden geri alır (`[ROLLBACK]`).
- `setup_service_acls.ps1`: `bin\lib` + `lib\` için Service SID'ye salt okuma/çalıştırma (`RX`, `Users` sıfır erişim), `security\` için `pepper.dpapi` + `live_drive_sync_secret.dpapi` oluşturma/rotasyon amacıyla `(OI)(CI)M` verir; `install_mms_service.ps1` ise `security\admin_secret.txt` dosyasını Service SID için salt okunur (`:R`) kilidiyle sınırlar.
- WinSW `install`/`start` çıkış kodlarını kontrol eder; servis `Running` değilse veya port yanıt vermiyorsa hata verir.
- Betikler **Windows PowerShell 5.1** ile çalışır (`setup_service_acls.ps1`, `build_aot.ps1`, `configure_hub_firewall.ps1`, `uninstall_mms_service.ps1` UTF-8 BOM'ludur; `install_mms_service.ps1` saf ASCII'dir). PowerShell 7 gerekmez.
- **OpenSSL Sürüm Notu:** Eski OpenSSL ikilileri `-addext` bayrağını desteklemiyorsa Kök CA (`ca.crt`) ve sunucu sertifikası (`server.crt`, zorunlu `IP:127.0.0.1` + LAN IP SAN) için `-config <dosya>.cnf -extensions v3_ca` / `-extfile <dosya>.cnf -extensions v3_req` kullanın.

### 2.1. Pilot Dağıtım Paketi (`scripts/package_windows_release.ps1`)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\package_windows_release.ps1 `
  -GoogleDriveClientId "<DESKTOP_CLIENT_ID>" `
  -GoogleDriveClientSecret "<DESKTOP_CLIENT_SECRET_OR_EMPTY>"
```

- Hub AOT derlemesini (`mms_backend.exe` + `sqlite3.dll`) geçici izole staging klasöründe (`$env:TEMP\mms_hub_aot_stage_*`) çalıştırır; çalışan bir test/geliştirme servisinin `sqlite3.dll` kilidine takılmaz.
- `-GoogleDriveClientId` / `-GoogleDriveClientSecret` verilirse Windows masaüstü istemci (`flutter build windows --release`) içine `--dart-define=MMS_GDRIVE_CLIENT_ID=...` / `MMS_GDRIVE_CLIENT_SECRET=...` ile gömülür (verilmezse fail-safe devre dışı kalır).
- Çıktı (`dist\windows_release\`): `client\` (`market_pos.exe` + Flutter runtime DLL'leri), `hub_bin\` (`mms_backend.exe`, `sqlite3.dll`, `lib\sqlite3.dll`, `MarketMMSService.exe`, `MarketMMSService.xml`, `hub_config.example.json`), `hub_scripts\` (4 Hub kurulum/ACL/güvenlik duvarı/kaldırma betiği) ve tüm paket dosyaları için `SHA256SUMS.txt`.

Firewall betiği varsayılan olarak yalnızca **Private** profilde ve yalnızca **yerel alt ağdan** (`-RemoteAddress LocalSubnet`) gelen bağlantılara izin verir. Kasalar farklı bir alt ağdaysa: `configure_hub_firewall.ps1 -RemoteAddress "192.168.10.0/24,192.168.20.0/24"`. Mağaza ağının Windows'ta **Özel (Private)** olarak işaretlendiğini kontrol edin.

## 3. Güncelleme

1. **Güncellemeden önce** şifreli Hub yedeği alın: `POST https://127.0.0.1:8945/api/v1/admin/backup` (admin secret) ve dosyayı USB'ye kopyalayın.
2. Yeni `mms_backend.exe` derleyin; `SHA256SUMS.txt` ile paket bütünlüğünü doğrulayın (`Get-FileHash`).
3. `install_mms_service.ps1` betiğini tekrar çalıştırın. Sıra: yapılandırma/secret/TLS kontrolü (servis çalışmaya devam eder) → servis durdurulur (en fazla 30 sn) → mevcut ikililer `bin.previous` altına saklanır → yeni ikililer kopyalanır → kurulum, SID, başlatma, sağlık kontrolü. Config, veri, yedek ve sertifika dizinlerine dokunulmaz.
4. Hub ilk açılışta DB şemasını additive olarak yükseltir (v2 → v3: `stock_movements.purchase_price`, `note`).
5. Android/Windows istemcilerini aynı sürüme güncelleyin.

> **Sürüm notu (21.11.2026):** Bu sürümden itibaren üretim yapılandırmasında `tls.ca_cert` zorunludur. Mevcut bir kurulumu güncellemeden önce `certs\ca.crt` dosyasını yerleştirip `hub_config.json` → `tls` nesnesine `"ca_cert": "../certs/ca.crt"` ekleyin. Eklenmezse kurulum betiği çalışan servise dokunmadan durur; ikili elle değiştirilirse yeni servis çıkış kodu 78 ile açılmaz.

### 3.1 Otomatik ve Manuel Geri Dönüş
- Yeni sürüm başlamaz veya sağlık kontrolü geçmezse betik **otomatik olarak** `bin.previous` ikililerine döner, servisi yeniden başlatır ve `GUNCELLEME BASARISIZ: Onceki surume geri donuldu` hatasıyla biter.
- **Sınır:** Veritabanı geri alınmaz. Yeni sürüm şemayı yükselttikten sonra çöktüyse eski ikili yükseltilmiş şemayla açılabilir (additive sütunlar yok sayılır) ancak yeni işlem türlerini (ör. `STOCK_RECEIPT`) tanımaz. Bu durumda 1. adımdaki yedekten geri yükleyin.
- Manuel geri dönüş: servisi durdurun, `bin.previous\*` dosyalarını `bin\` altına kopyalayın, `install_mms_service.ps1` yerine `bin\MarketMMSService.exe install` + `start` kullanın.
- İmzalı güncelleme paketi (kod imzalama sertifikası) henüz yok: Owner kararı (`OWNER_ACTION_CHECKLIST.md`).

## 4. Admin Uçları (yedekleme / geri yükleme)

`/api/v1/admin/backup|backups|restore|backup/prune` yalnızca **loopback** (127.0.0.1) ve yapılandırılmış admin secret ile çalışır; secret yoksa `503 ERR_ADMIN_NOT_CONFIGURED` döner. Eski koda gömülü `adm_sec` fallback'i kaldırıldı. Başlık: `x-mms-admin-secret` (veya `x-admin-secret`).

### 4.1 Zamanlanmış Hub Yedeği (ADR-016)

`hub_config.json` içinde:

```json
"backup_schedule": { "interval_hours": 24, "daily_retention_days": 30, "monthly_retention_months": 12 }
```

- Anahtar yoksa varsayılan **24 saatte bir** şifreli yedek alınır; `interval_hours: 0` zamanlamayı kapatır. Bilinmeyen anahtar veya aralık dışı değer servisi başlatmaz (REL-01 fail-fast).
- Yedekler `backup_dir` altına AES-256 + HMAC ile şifreli (`.mmsbak`) yazılır; parola DPAPI korumalı pepper'dır. Saklama politikası her başarılı yedekten sonra uygulanır.
- Durum: `GET https://127.0.0.1:8945/api/v1/admin/backup/status` (başlık `x-mms-admin-secret`). `/health` yanıtındaki `backup` alanı yol/hata ayrıntısı içermeden `last_success_at`, `overdue`, `consecutive_failures`, `last_error_code` döner.
- Yedek hedefi yazılamazsa (disk dolu, ağ sürücüsü yok) servis çalışmaya devam eder, hata durum dosyasına (`data\backup_schedule_state.json`) ve servis loguna yazılır, 30 dk sonra tekrar denenir.
- `POST /api/v1/backup/snapshot` (şifresiz bakım kopyası) artık yalnızca loopback + admin secret ile çalışır (ADR-017).

## 5. Geliştirme / Manuel Test Ortamı

`start_master_hub.bat` yalnızca geliştirme içindir (HTTP, TLS yok). Admin uçları için önce `set MMS_ADMIN_SECRET=...` tanımlayın. Release APK bu Hub'a yalnızca `MMS_ALLOW_CLEARTEXT=true` ile derlenmişse bağlanabilir (bkz. `ANDROID_RELEASE.md`).

## 6. Fiziksel Doğrulama Durumu

Gerçek SCM kurulum/güncelleme/kaldırma, otomatik geri dönüş, LocalService ACL, firewall profil/alt ağ kısıtı ve servis çökme kurtarma senaryoları **çalıştırılmadı (BLOCKED — yönetici yetkili kurulum ortamı gerekir)**. Otomatik testler yapılandırmayı, betik sırasını (statik) ve tüm betiklerin Windows PowerShell 5.1 ile ayrıştırılabildiğini doğrular. Adımlar: [`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`](../../PHYSICAL_ACCEPTANCE_TEST_PLAN.md) PAT-08…PAT-10.
