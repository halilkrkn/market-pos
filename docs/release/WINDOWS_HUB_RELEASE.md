# Windows Master Hub Kurulum, Güncelleme ve Servis Kılavuzu — MARKET MMS

*Son güncelleme: 21 Kasım 2026 (3. oturum) — REL-01 (ADR-015 + Ek A)*

## 1. Tek Yapılandırma Kaynağı (REL-01)

Tüm ayarlar `%ProgramData%\MarketMMS\config\hub_config.json` dosyasındadır. Servis (WinSW `MarketMMSService.xml`) yalnızca `--config=...` geçirir. Şablon: `test_spikes/spike_01_backend/config/hub_config.example.json`.

| Anahtar | Varsayılan | Not |
|---|---|---|
| `environment` | `production` | Üretimde TLS ve tenant/store başlık zorunluluğu kapatılamaz |
| `port` / `discovery_port` | 8945 / 8946 | Firewall betiği bu değerleri okur |
| `db_path`, `backup_dir`, `pepper_file` | `..\data`, `..\backups`, `..\security` | Göreli yollar config klasörüne göredir |
| `admin_secret_file` | `..\security\admin_secret.txt` | Kurulumda rastgele üretilir; düz metin `admin_secret` anahtarı **reddedilir** |
| `tls.enabled/cert/key` | `true`, `..\certs\server.crt/.key` | Dosya yoksa servis açılmaz (çıkış kodu 78) |
| `tls.ca_cert` | `..\certs\ca.crt` | **Üretimde zorunlu (PAIR-CA, 21.11.2026).** Eşleştirme QR'ındaki CA parmak izi ve `/api/v1/pairing/ca-cert` bu dosyadan gelir; yoksa QR ile eşleştirmede TLS pin kurulamazdı. Yalnızca **genel** CA sertifikası — `ca.key` Hub diskinde bulunmamalıdır (ACL betiği bulursa kurulumu durdurur). Eski `ROOT_CA_CERT_FILE` ortam değişkeni geliştirme için korunur |
| `tenant_id`, `store_id`, `hub_id` | — | Mağaza kimliği; istemci kurulum değerleriyle aynı olmalı |

Bilinmeyen anahtarlar (yazım hataları) açılışı durdurur.

## 2. Kurulum (Yönetici PowerShell)

```powershell
cd test_spikes\spike_01_backend
.\scripts\build_aot.ps1                 # mms_backend.exe
# Sertifikaları %ProgramData%\MarketMMS\certs\ altına yerleştirin (server.crt / server.key)
.\scripts\install_mms_service.ps1        # dizinler + ACL + config + admin secret + servis + health check
..\..\scripts\configure_hub_firewall.ps1 # TCP/UDP portları hub_config.json'dan
```

Kurulum betiği (v2.1):
- Mevcut `hub_config.json` ve `admin_secret.txt` dosyalarını **asla ezmez** (güncellemede ayarlar korunur).
- Sertifika yoksa, çalışan servise dokunmadan durur (fail-closed).
- WinSW `install`/`start` çıkış kodlarını kontrol eder; servis `Running` değilse veya port yanıt vermiyorsa hata verir.
- Betikler **Windows PowerShell 5.1** ile çalışır (Unicode içerenler UTF-8 BOM'ludur). PowerShell 7 gerekmez.

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
