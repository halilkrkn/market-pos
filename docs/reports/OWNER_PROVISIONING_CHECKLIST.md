# MARKET MMS — Owner (Proje Sahibi) Provizyon ve Güvenlik Kontrol Listesi

*Tarih: 25 Kasım 2026 · Kapsam: Yalnızca Owner yetkisi ve gizli anahtar sorumluluğu gerektiren manuel adımlar. **Bu dosyaya veya Git deposuna hiçbir parola, keystore, token, private key veya client secret eklemeyin.***

---

## 1. Üretim Android Upload Keystore Oluşturma (`B1` — BLOCKER)

Android Release APK üretimi (`android/app/build.gradle.kts#L74-L87`) fail-closed çalışır; üretim keystore'u olmadan APK derlenmez.

1. Depo **dışında** güvenli bir klasör oluşturun (ör. `C:\MarketMMS-Secrets\`).
2. Parolayı komut satırı argümanı olarak yazmadan (`-storepass` / `-keypass` **kullanmadan**, etkileşimli gizli istemle — terminal geçmişine yazılmaması için) çalıştırın:

```powershell
New-Item -ItemType Directory -Path "C:\MarketMMS-Secrets" -Force | Out-Null
keytool -genkeypair -v -keystore "C:\MarketMMS-Secrets\market_mms_upload.jks" `
  -keyalg RSA -keysize 4096 -validity 10000 -alias market_mms
```

3. Parmak izlerini (`SHA-1` ve `SHA-256`) okuyup denetim/Google Cloud OAuth kaydınız için saklayın (parola etkileşimli sorulur):

```powershell
keytool -list -v -keystore "C:\MarketMMS-Secrets\market_mms_upload.jks" -alias market_mms
```

4. `c:\Users\halil\Github\market-pos\android\key.properties` dosyasını oluşturun (`.gitignore` satır 96 tarafından korunur):

```properties
storeFile=C:\\MarketMMS-Secrets\\market_mms_upload.jks
storePassword=<GIZLI_STORE_PAROLANIZ>
keyAlias=market_mms
keyPassword=<GIZLI_KEY_PAROLANIZ>
```

5. Release APK'yı üretin ve imza sertifikasını doğrulayın:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\package_android_release.ps1
& "$env:LOCALAPPDATA\Android\Sdk\build-tools\36.0.0\apksigner.bat" verify --print-certs "dist\android_release\market_mms_v1.0.0-b1.apk"
```

> [!CAUTION]
> `market_mms_upload.jks` ve parolalarını en az iki ayrı şifreli çevrimdışı yedekte saklayın. Kaybolursa kurulu Android uygulamaları güncellenemez.

---

## 2. Pilot PC İçin Üretim Hub TLS Sertifikalarını Üretme (`B2` — BLOCKER)

> **Kural:** Geliştirme bilgisayarındaki `MarketMMS_Isolated_Test` test sertifikalarını **asla** pilot bilgisayara taşımayın.

1. Güvenli (tercihen Hub dışındaki) bir bilgisayarda OpenSSL 3.x (`C:\Program Files\Git\usr\bin\openssl.exe`) ile **Root CA** üretin:

```powershell
$caDir = "C:\MarketMMS-Pilot-CA-Offline"
New-Item -ItemType Directory -Path $caDir -Force | Out-Null
& "C:\Program Files\Git\usr\bin\openssl.exe" req -x509 -newkey rsa:2048 -nodes `
  -keyout "$caDir\ca.key" -out "$caDir\ca.crt" -days 3650 `
  -subj "/CN=Market MMS Pilot Root CA" `
  -addext "basicConstraints=critical,CA:TRUE" `
  -addext "keyUsage=critical,keyCertSign,cRLSign"
```

2. Pilot Hub PC'nin sabit LAN IPv4 adresini (ör. `192.168.1.50`) ve bilgisayar adını ekleyerek **Sunucu Sertifikası** üretin (**`IP:127.0.0.1` zorunludur**, yoksa Hub açılışta `exit 78` ile durur):

```powershell
$srvOut = "C:\MarketMMS-Pilot-Certs-Export"
New-Item -ItemType Directory -Path $srvOut -Force | Out-Null
$lanIp = "192.168.1.50" # Pilot PC'nin gercek sabit LAN IP'si ile degistirin

& "C:\Program Files\Git\usr\bin\openssl.exe" req -new -newkey rsa:2048 -nodes `
  -keyout "$srvOut\server.key" -out "$caDir\server.csr" `
  -subj "/CN=localhost" `
  -addext "subjectAltName=IP:127.0.0.1,IP:$lanIp,DNS:localhost" `
  -addext "keyUsage=digitalSignature,keyEncipherment" `
  -addext "extendedKeyUsage=serverAuth"

& "C:\Program Files\Git\usr\bin\openssl.exe" x509 -req -in "$caDir\server.csr" `
  -CA "$caDir\ca.crt" -CAkey "$caDir\ca.key" -CAcreateserial `
  -out "$srvOut\server.crt" -days 365 -copy_extensions copy

Copy-Item "$caDir\ca.crt" "$srvOut\ca.crt" -Force
```

3. **Yalnızca** `ca.crt`, `server.crt` ve `server.key` dosyalarını pilot PC'deki `C:\ProgramData\MarketMMS\certs\` klasörüne kopyalayın. **`ca.key` dosyasını pilot PC'ye kesinlikle koymayın.**

---

## 3. Pilot PC Ağ Profili ve Güvenlik Duvarı Onayı

- Pilot PC'de aktif Wi-Fi/Ethernet ağını Windows Ayarları'ndan **Özel (Private)** yapın.
- Hub PC için modem/router üzerinden **statik DHCP rezervasyonu** tanımlayın ve router'da **AP / Client Isolation** kapalı olsun.
- Geliştirme bilgisayarında fiziksel Android testini kendi ağınızda yapmak isterseniz, yalnızca o test için `Public` Wi-Fi profilini geçici `Private` yapıp test bitiminde karar verin (`MarketMmsSpike01` ve `8085` portuna yine dokunmayın).

---

## 4. Hub Portable Recovery Password Tanımlama (`B3` — BLOCKER)

- Pilot PC'de kurulum ve İlk Owner Bootstrap tamamlandıktan hemen sonra Windows Client → **Sistem Durumu** → **Merkezi Hub Yedekleme (Google Drive)** → **Taşınabilir Kurtarma Parolası** alanından en az **12 karakterli** güçlü bir parola cümlesi kaydedin.
- Parolayı kağıda yazıp mağaza kasası dışında güvenli bir yerde saklayın; tanımlanmadan Hub otomatik/manuel yedek almaz (`ERR_RECOVERY_KEY_NOT_CONFIGURED`).

---

## 5. Google Cloud OAuth Yapılandırması (`C1 / C2` — Google Drive Kullanılacaksa)

Yerel LAN senkronizasyonu ve şifreli yerel `.mmsbak` yedekleme için zorunlu değildir; ancak uzak Google Drive yedekleme ve Hibrit Drive LiveSync için gereklidir:

1. 2FA korumalı mağaza Google hesabıyla Google Cloud Console projesi açın ve **Google Drive API**'yi etkinleştirin.
2. OAuth Consent Screen'i yalnızca `https://www.googleapis.com/auth/drive.file` kapsamıyla **`In production`** durumuna alın.
3. Aynı projede:
   - **Desktop App** Client ID/Secret (Windows `package_windows_release.ps1 -GoogleDriveClientId ... -GoogleDriveClientSecret ...`),
   - **Android** OAuth Client ID (`com.marketmms.market_pos` + `B1` Release `SHA-1`),
   - **Web Application** Client ID (`package_android_release.ps1 -GoogleDriveWebClientId ...` — Web `client_secret` **asla** APK'ya konulmaz) oluşturun.

---

## 6. Nihai Fiziksel Kabul İmzası

- [ ] `B1` Android Release APK üretildi, SHA-256 ve imza sertifikası doğrulandı.
- [ ] `B2` Pilot PC TLS sertifikaları (`ca.crt`, `server.crt`, `server.key`) yerleştirildi (`ca.key` hariç tutuldu).
- [ ] `B3` Portable Recovery Password tanımlandı ve fiziksel yedeği saklandı.
- [ ] (Kullanılacaksa) `C1/C2` Google Cloud OAuth tanımlandı ve release paketleri yeniden derlendi.
- [ ] [`PILOT_ACCEPTANCE_TEST_PLAN.md`](./PILOT_ACCEPTANCE_TEST_PLAN.md) içindeki **15/15** pilot kabul kriteri fiziksel donanımda `PASS` olarak doğrulandı.
