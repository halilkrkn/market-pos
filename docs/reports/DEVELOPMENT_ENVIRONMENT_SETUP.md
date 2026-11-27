# MARKET MMS — Geliştirme Bilgisayarı İzole Test Ortamı Kurulum Kılavuzu

*Tarih: 25 Kasım 2026 · Amaç: Mevcut geliştirme bilgisayarında korunan `MarketMmsSpike01` servisine (`TCP 8085`), gerçek `%LOCALAPPDATA%\MarketMMS\client_local.db` veritabanına ve üretim konfigürasyonuna **kesinlikle dokunmadan** tam izole Test Hub + Windows Client çalıştırmak.*

---

## 1. Geliştirme Ortamı ile Pilot Ortamının Kesin Sınırları

| Bileşen | Geliştirme İzole Test Ortamı (Bu PC) | İkinci PC Pilot Ortamı (Gerçek Pilot) |
|---|---|---|
| **Çalışma Dizini** | `%LOCALAPPDATA%\MarketMMS_Isolated_Test` | `%ProgramFiles%\MarketMMS` & `%ProgramData%\MarketMMS` |
| **Hub Çalışma Şekli** | Bağımsız `mms_backend.exe` süreci (`--config=`) | `MarketMMSService` Windows Service (WinSW) |
| **Portlar** | `TCP 8947` (HTTPS) / `UDP 8948` (Discovery) | `TCP 8945` (HTTPS) / `UDP 8946` (Discovery) |
| **Merkezi SQLite DB** | `...\MarketMMS_Isolated_Test\hub\data\market_master_test.db` | `%ProgramData%\MarketMMS\data\market_master.db` |
| **Windows Client DB** | `...\MarketMMS_Isolated_Test\client_win\MarketMMS\client_local.db` | `%LOCALAPPDATA%\MarketMMS\client_local.db` |
| **TLS Sertifikaları** | Test-only Root CA (`ca_offline\ca.key`) — **pilota taşınmaz!** | Pilot PC'ye özel üretilmiş üretim Root CA + SAN |
| **Google Drive / OAuth** | **Tamamen temizlenmiş / devre dışı** (`interval_hours: 0`) | İsteğe bağlı gerçek mağaza Google Cloud OAuth |
| **`MarketMmsSpike01` (`8085`)** | **Dokunulmaz (yan yana çalışır)** | Temiz pilot PC'de bulunmaz |

> [!CAUTION]
> Geliştirme ortamındaki `market_master_test.db`, `ca.crt`, `server.crt`, `server.key`, `admin_secret.txt` ve `pepper.dpapi` dosyaları **asla** pilot bilgisayara kopyalanmamalıdır.

---

## 2. İzole Test Hub'ı Başlatma ve Durdurma

### 2.1 Başlatma

Repository kök dizininde standart (yönetici yetkisi gerektirmeyen) bir PowerShell penceresinde çalıştırın:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\dev_test\start_isolated_test_hub.ps1
```

Bu betik otomatik olarak:
1. `TCP 8947` ve `UDP 8948` portlarının boş olduğunu doğrular (`8085/8945/8946` kullanımını güvenlik gereği reddeder).
2. `dist\windows_release_v1_0_0_tray\hub_bin\` içindeki `mms_backend.exe` ve `sqlite3.dll` dosyalarını `%LOCALAPPDATA%\MarketMMS_Isolated_Test\hub\` altındaki 3 çalışma konumuna (`bin\`, `bin\lib\`, `lib\`) kopyalar.
3. Git OpenSSL 3.x (`C:\Program Files\Git\usr\bin\openssl.exe`) ile test-only Root CA ve `IP:127.0.0.1,DNS:localhost,IP:<Wi-Fi-IP>` SAN'lı sunucu sertifikası üretir (`ca.key` `ca_offline\` içinde ayrı kalır).
4. `MMS_GDRIVE_*` ve diğer OAuth/üretim ortam değişkenlerini alt süreçten temizler.
5. `mms_backend.exe --config=...` sürecini başlatır, PID'i `hub\hub.pid` dosyasına yazar ve pinned TLS `GET https://127.0.0.1:8947/health` yanıtını doğrular (`200 UP`).

### 2.2 Durdurma (Veritabanını Koruyarak)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\dev_test\stop_isolated_test_hub.ps1
```

Betik yalnızca `hub.pid` içindeki ve izole test dizininden çalışan `mms_backend.exe` sürecini durdurur. `market_master_test.db` dosyası korunur (otomatik silinmez).

---

## 3. İzole Windows Client'ı Başlatma ve System Tray Kullanımı

Gerçek `%LOCALAPPDATA%\MarketMMS\client_local.db` dosyasını korumak için Windows Client'ı doğrudan çift tıklamak yerine şu betikle başlatın:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\dev_test\start_isolated_windows_client.ps1
```

- **İstemci DB Yolu:** `%LOCALAPPDATA%\MarketMMS_Isolated_Test\client_win\MarketMMS\client_local.db`
- **Test Hub Bağlantısı:** Windows Client **Sistem Durumu ve Altyapı Tanılama** ekranından manuel olarak `https://127.0.0.1:8947` veya **QR / Eşleştirme** akışıyla Test Hub'a bağlanır (`start_isolated_test_hub.ps1` çıktısındaki `ca_cert_path` / QR üzerinden).
- **System Tray Kullanımı:**
  - Pencereyi küçültme veya `X` düğmesine basma uygulamayı kapatmaz, Sistem Tepsisine gizler.
  - Tepsi simgesine **çift tıklama** pencereyi geri getirir.
  - Tepsi simgesine **sağ tıklama** menüsü: `MARKET MMS'i Aç`, `Hub Durumu`, `Senkronizasyon Durumu`, `Yedekleme Durumu`, `Ayarlar`, `Uygulamadan Çık`.
  - **Uygulamadan Çık** (veya Ayarlar kartındaki **Uygulamadan Güvenli Çık**): aktif senkronizasyonu duraklatır, bekleyen yedek turunu bekler, yerel Drift SQLite bağlantısını (`Outbox` verileri korunarak) kapatır ve uygulamadan çıkar.
- **Otomatik Başlatma Uyarısı:** Test sırasında Windows açılışında otomatik başlatma varsayılan olarak kapalıdır; test amaçlı açarsanız test bitiminde aynı anahtardan tekrar kapatın.

---

## 4. Canlı 2-İstemcili Otomatik Uçtan Uca Testi Çalıştırma

Test Hub çalışır durumdayken gerçek FFI SQLite üzerinde iki ayrı cihazla (`WIN-TEST-*` ve `AND-SIM-*`) eşleştirme, ürün sync, barkodla satış, offline satış, reconnect ve idempotency testlerini koşmak için:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\dev_test\start_isolated_test_hub.ps1
$env:MMS_ISOLATED_LIVE_E2E = "true"
flutter test test/features/production/isolated_live_hub_e2e_test.dart
Remove-Item Env:MMS_ISOLATED_LIVE_E2E -ErrorAction SilentlyContinue
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\dev_test\stop_isolated_test_hub.ps1
```

---

## 5. Geliştirme Makinesinde Fiziksel Android Telefon Bağlantısı (Not)

Mevcut geliştirme bilgisayarında Wi-Fi ağ profili **`Public`** olarak görülmektedir ve Windows Firewall kurallarına güvenlik gereği müdahale edilmemiştir. Fiziksel bir Android telefondan geliştirme bilgisayarındaki izole Test Hub'a (`https://192.168.1.158:8947`) bağlanmak isterseniz, Owner olarak:
1. Wi-Fi profilini Windows Ayarları'ndan **Özel (Private)** konumuna almanız veya yalnızca geliştirme süresi boyunca `TCP 8947` / `UDP 8948` için yerel alt ağ (`LocalSubnet`) izni vermeniz,
2. Android cihazda üretim/saha keystore'u ile imzalanmış Release APK kullanmanız (Android Release `usesCleartextTraffic=false` olduğundan düz HTTP kullanılamaz) ve Test Hub QR kodunu okutmanız gerekir.
