# MARKET MMS — Sahip (Halil) Fiziksel Test Uygulama Rehberi (`OWNER_PHYSICAL_TEST_CHECKLIST`)

**Tarih:** 2026-11-27

**Hedef Kullanıcı:** Proje Sahibi (Halil)

**Amaç:** Konakta non-admin / dış donanım sınırları nedeniyle çalıştırılamayan tüm kurulum, TLS, Android release APK, çoklu cihaz saha testi ve Google Drive kabul adımlarını **sıralı, güvenli ve tek-adım kontrollü** biçimde yürütmek.

> [!CAUTION]
> Bu rehberdeki fiziksel adımlar uygulanırken **tek seferde yalnızca bir test adımı** çalıştırın ve sonucunu kaydedin. Gerçek veri içeren bir PC'de çalışacaksanız Adım 1 emniyet yedeğini atlamayın!

---

## Adım 1 — Kurulum Öncesi Emniyet Yedeği (Zorunlu Ön-Uçuş)

Gerçek `C:\Users\%USERNAME%\AppData\Local\MarketMMS\client_local.db` veriniz varsa **önce güvenli Online Backup API yedeğini alın**:

```powershell
$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$bakDir = "$env:USERPROFILE\MarketMMS_PreInstall_Backups"
$bakPath = "$bakDir\client_local_$stamp.db"
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\dev_test\backup_client_db_safe.ps1 `
  -SourceDbPath "$env:LOCALAPPDATA\MarketMMS\client_local.db" `
  -OutputBackupPath $bakPath
Get-Content "$bakPath.sha256"
```

Doğrulama:
- Çıktıda `INTEGRITY_CHECK=ok`, `SOURCE_UNTOUCHED=True` ve üretilen `.sha256` yan dosyasını görün.
- Eski bir deneme servisi kaldıysa (`sc.exe query MarketMmsSpike01`) kaldırılmış olduğundan emin olun (**D1**).
- Ağ profilinizin **Private** olduğunu doğrulayın: `Get-NetConnectionProfile` (`NetworkCategory : Private`).

---

## Adım 2 — Temiz Test VM veya Yönetici Windows PC'de MSI Kurulumu (`PAT-21`)

1. Release MSI bütünlüğünü doğrulayın (`dist\installer_v1_0_0_tray\SHA256SUMS.txt` ile eşleşmeli):
   ```powershell
   Get-FileHash dist\installer_v1_0_0_tray\MarketMMS-Setup-1.0.0-x64.msi -Algorithm SHA256
   # Beklenen: 183B014FD6ED80785E4302388A2362D020DAD300D3BDEE21317450EE73CA820C
   ```
   *(Not: Release MSI henüz ticari OV/EV sertifika ile imzalı değildir — UAC / SmartScreen uyarısında yayımcı doğrulanmadığı görünecektir; ticari dağıtım öncesi `signtool` + timestamp ile imzalayın.)*
2. **Yönetici (Run as Administrator) Windows PowerShell 5.1** açın. Temiz bir VM üzerinde tüm yaşam döngüsünü tek komutla doğrulamak için anahtar-teslim betiği kullanabilirsiniz:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\dev_test\run_vm_fresh_install_acceptance.ps1 -LiveVmExecution -ConfirmCleanTestVm
   ```
   Veya elle kurmak için:
   ```powershell
   msiexec /i dist\installer_v1_0_0_tray\MarketMMS-Setup-1.0.0-x64.msi /qn ALLOW_DEFERRED_TLS_START=1 HUB_PORT=8945 DISCOVERY_PORT=8946 /L*v "%TEMP%\MarketMMS_Install.log"
   ```
3. Beklenen sonuç: `ExitCode 0`, `C:\Program Files\MarketMMS\client\market_pos.exe` mevcut, `C:\ProgramData\MarketMMS\` altında 11 dizin ve `config\install_manifest.json` (`PENDING_TLS_PROVISIONING`) oluşmuş, `MarketMmsSpike01` oluşturulmamış.

---

## Adım 3 — OpenSSL `3.5.9` ile TLS Sertifika Provizyonu & ACL Uygulaması (`PAT-22`, `PAT-25`)

> [!IMPORTANT]
> `C:\OpenSSL\bin\openssl.exe` (`0.9.8k`) **KULLANMAYIN**! SAN ve modern TLS uzantıları için `C:\Program Files\Git\usr\bin\openssl.exe` (`3.5.9`) kullanın.

1. Çevrimdışı Root CA (`ca.key` + `ca.crt`) ile Hub'ın gerçek **Private LAN IP** adresini ve `127.0.0.1` loopback'ini içeren SAN profilini (`subjectAltName=IP:127.0.0.1,IP:<LAN_IP>,DNS:localhost`) üreterek yalnızca **`ca.crt`**, **`server.crt`** (saf PEM `-notext`) ve **`server.key`** dosyalarını `C:\ProgramData\MarketMMS\certs\` dizinine yerleştirin (`ca.key`'i asla Hub diskinde bırakmayın!).
2. Yönetici PowerShell ile ACL ve servis doğrulamasını yapın:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\MarketMMS\hub_scripts\setup_service_acls.ps1" -BaseDir "C:\ProgramData\MarketMMS" -ServiceName "MarketMMSService"
   Start-Service MarketMMSService
   Get-Service MarketMMSService
   sc.exe qsidtype MarketMMSService
   ```
3. `https://127.0.0.1:8945/health` ve `https://<LAN_IP>:8945/health` çıktılarının `{"status":"UP",...}` döndüğünü doğrulayın (`PAT-12` adım 1).

---

## Adım 4 — Windows Güvenlik Duvarı & Yetki İzolasyonu Kontrolleri (`PAT-10`, `PAT-25`)

Yönetici PowerShell'de:
```powershell
Get-NetFirewallRule -DisplayName "*Market MMS*" | Format-Table DisplayName, Enabled, Profile, Direction, Action
icacls "C:\ProgramData\MarketMMS\security\admin_secret.txt"
icacls "C:\ProgramData\MarketMMS\certs\server.key"
```
Standart (admin olmayan) bir Windows kasiyer hesabı açıp `C:\ProgramData\MarketMMS\data` ve `security` klasörlerine girmeyi deneyin → **Erişim engellendi** olmalı.

---

## Adım 5 — Android Release Keystore İmzalama, Kurulum & QR Eşleştirme (`PAT-11`, `PAT-03`)

1. Gerçek yayın/pilot anahtarını oluşturup `android/key.properties` dosyasını doldurun (`git`'e eklemeyin!):
   - Ardından temiz imza ile üretim APK üretin:
     ```powershell
     flutter build apk --release
     ```
   - `C:\Users\halil\AppData\Local\Android\Sdk\build-tools\36.0.0\apksigner.bat verify --print-certs build\app\outputs\flutter-apk\app-release.apk` ile sertifikanın `CN=Android Debug` **olmadığını** doğrulayın.
2. APK'yı fiziksel Android telefona kurun (`adb install -r build\app\outputs\flutter-apk\app-release.apk`).
3. Aynı Wi-Fi ağında Windows uygulamasından Tanılama → Cihaz Eşleştirme açın; telefondan QR kodu okutup **`https://<LAN_IP>:8945`** adresiyle eşleşmeyi ve `ca_fingerprint` değerini onaylayın (`PAT-03`).

---

## Adım 6 — Google Drive OAuth & Recovery Password (`PAT-13`, `BK-PAT-*`)

1. Google Cloud Console'dan Masaüstü/Android OAuth Client (`drive.file` kapsamı) oluşturup `MMS_GDRIVE_CLIENT_ID` ile yapılandırın.
2. Windows uygulamasında **Merkezi Hub Yedekleme → Kurtarma Parolası** (en az 12 karakter) tanımlayın ve fiziksel olarak kasadan ayrı güvenli bir yerde saklayın.
3. Google Drive testlerini **yalnızca `TEST_ONLY` Google hesabı / klasörüyle** yürütün (`PAT-13`, `PAT-17`, `PAT-18`, `BK-PAT-01…18`).

---

## Adım 7 — Saha Kabul Test Sırası (`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`)

Aşağıdaki sırayla ilerleyip her adımın çıktısını `pilot_kanit/PAT-xx_<tarih>/` klasörüne kaydedin:

1. `PAT-21` → `PAT-22` → `PAT-08` → `PAT-25` / `PAT-10`
2. `PAT-11` → `PAT-03` → `PAT-12` (adım 2–5: pin & rotasyon)
3. `PAT-01` (Android kamera barkod) & `PAT-02` (Windows USB HID okuyucu)
4. `PAT-04` (LAN/Wi-Fi kesintisi), `PAT-05` (çoklu cihaz satış), `PAT-06` (eşzamanlı stok), `PAT-19` (ikincil barkod)
5. `PAT-23` (Upgrade) → `PAT-24` (Rollback test VM) → `PAT-09` (WinSW crash recovery) → `PAT-26` (Uninstall `PURGE_USER_DATA=0` & Reinstall)
6. `PAT-07` (USB yedek) → `PAT-14`..`PAT-16` (kesinti/arka plan yedek) → `PAT-13` / `PAT-17` / `PAT-18` & `BK-PAT-01…18`
7. *(Opsiyonel Test Hub doğrulaması)* `PAT-20` (`E2E-HUB-01` karşıtı gerçek Android integration testi)

---

## Sorun Giderme ve Acil Geri Dönüş

- **Kurulum `ExitCode 74` / `1603`:** `%TEMP%\MarketMMS_Install.log` ve `%ProgramData%\MarketMMS\logs\installer-diagnostics.log` ile `%ProgramData%\MarketMMS\run\installer_tx_state.json` dosyalarını inceleyin.
- **Hub açılmıyor (`ExitCode 78`):** `server.crt` dosyasında `IP:127.0.0.1` SAN eksik veya PEM içinde `-text` artığı vardır (`OpenSSL 3.5.9` + `-notext` ile yeniden üretin).
- **Android Hub'ı keşfedemiyor:** Router client isolation kapalı olmalı; Windows ağ profili **Private** ve `8945 TCP`/`8946 UDP` kuralları açık olmalıdır.
- **Veri tutarsızlığı şüphesi:** Hiçbir Outbox veya `.restore_journal` dosyasını silmeyin; servisi durdurmadan önce maskeli tanı raporunu dışa aktarın ve Adım 1 yedeğini saklayın.
