# MARKET MMS — Fiziksel Kabul Test Planı (Saha / Pilot)

*Tarih: 21 Kasım 2026 (Son Güncelleme: 27 Kasım 2026 — `PAT-21…PAT-26` Windows MSI/TLS/ACL/Rollback/Uninstall kabul testleri eklendi; tüm senaryolar 11 standart alan ve dürüst `Otomatik Ön-Doğrulama` vs `Fiziksel Test` durumlarıyla hizalandı)*
*Hazırlayan: Antigravity / Proje Mühendislik Ekibi · Fiziksel Saha Durumu: **NOT RUN / PENDING PHYSICAL TEST (BLOCKED — gerçek donanım/ortam gerekir)***

Bu plan, otomatik testlerin, birim/entegrasyon doğrulamalarının ve izole sandbox simülasyonlarının yerine geçemeyecek tüm **gerçek cihaz, gerçek ağ, gerçek yönetici (`Administrator`) SCM/ACL/Firewall ve canlı Google Cloud OAuth** kabullerini doğrulamak içindir.

- **Önerilen Yürütme Sırası:** `PAT-21` → `PAT-22` (`PAT-12` adım 1 dahil) → `PAT-08` → `PAT-25` / `PAT-10` → `PAT-11` → `PAT-03` → `PAT-12` (adım 2–5) → `PAT-23` / `PAT-24` / `PAT-09` → `PAT-26` → `PAT-01`, `PAT-02`, `PAT-04..07`, `PAT-14..16`, `PAT-19`, `PAT-20` → `PAT-13` → `PAT-17` → `PAT-18` (Hat B `BK-PAT-01…18` ile birlikte).
- **Tek Seferde Bir Test Adımı Kuralı (`GEMINI.md` §6.8):** Kullanıcıya/operatöre sahada tek seferde bir test adımı verilir ve sonucu beklenir; sonucu teyit edilmeden sonraki adıma geçilmez.

## Genel Ön Koşullar (Tüm Fiziksel Testler İçin Zorunlu)
1. **Canlı DB Emniyet Yedeği:** Mevcut verisi olan makinede herhangi bir kurulum öncesi `scripts\dev_test\backup_client_db_safe.ps1` çalıştırılarak `client_local.db` yedeği ve `.sha256` doğrulanmalıdır.
2. **Dış Sağlama (`OWNER_ACTION_CHECKLIST.md` & `OWNER_PHYSICAL_TEST_CHECKLIST.md`):**
   - `B1`: Gerçek Android Release Keystore (`android/key.properties`).
   - `B2`: OpenSSL `3.5.9` ile üretilmiş geçerli `ca.crt`, `server.crt` (`IP:127.0.0.1` + LAN IP SAN zorunlu, `-notext` PEM) ve `server.key`.
   - `C1/C2`: Google Cloud Desktop/Android OAuth Client (`drive.file` kapsamı).
   - `D1`: Eski `MarketMmsSpike01` servisinin kaldırılmış olması.
   - `Ticari İmza (Opsiyonel/Önerilen)`: Windows OV/EV Authenticode imzalı MSI (yoksa UAC ekranında imzasız MSI onayı gerekir).
3. **Recovery Password:** 23 Kasım 2026 sonrası sürümde Hub yedeği almadan önce Portable Recovery Password (en az 12 karakter) tanımlanmalıdır (`POST /api/v1/backup/recovery-key`).
4. **Kanıt Klasörü:** Her test için ayrı klasör tutulur: `pilot_kanit/PAT-xx_<tarih>/`.

## Standart Test Kayıt Şablonu (11 Alanlı Kapsam + Saha Doldurma Tablosu)

Her test maddesi aşağıda 11 standart alanda tanımlanmıştır: **(1) Test ID**, **(2) Başlık**, **(3) Amaç**, **(4) Ön Koşullar**, **(5) Gerekli Cihaz / Ortam**, **(6) Adımlar**, **(7) Beklenen Sonuç**, **(8) Veri Bütünlüğü / Log Kontrolü**, **(9) Başarısızlık Durumunda Yapılacaklar**, **(10) Kanıt Türü**, **(11) Otomatik Ön-Doğrulama ve Fiziksel Test Durumu**.

| Kayıt Alanı (Saha Çıktısı) | Değer |
|---|---|
| Test ID / Tarih / Saat | |
| Uygulayan / Rol | |
| Cihazlar (Model, OS, App Sürümü) | |
| Hub Sürümü, `hub_id`, `restore_epoch` | |
| Fiziksel Sonuç (`PASS` / `FAIL` / `BLOCKED`) | |
| Kanıt Klasörü | |

---

## Hat A — İstemci, Ağ, Senkronizasyon ve Saha Operasyon Testleri (`PAT-01…PAT-20`)

### PAT-01 — Android kamera ile barkod tarama (sürekli tarama ve sepet)
1. **Test ID:** `PAT-01`
2. **Başlık:** Android kamera ile barkod tarama (sürekli tarama ve sepet)
3. **Amaç:** Gerçek cihaz kamerasıyla EAN-13 barkodların tekilleştirilerek sepete eklendiğini doğrulamak.
4. **Ön Koşullar:** Release APK (`PAT-11`) kurulu ve cihaz eşleştirilmiş (`PAT-03`); katalogda en az 3 barkodlu ürün var.
5. **Gerekli Cihaz / Ortam:** Kameralı fiziksel Android cihaz, gerçek EAN-13 etiketli ürünler, katalogda olmayan bir barkod.
6. **Adımlar:**
   1. POS → kamera ile tara, ilk açılışta kamera iznini verin.
   2. Ürün A'yı art arda 2 kez okutun (sepette 1 satır, miktar `2`).
   3. Ürün B'yi okutun.
   4. Aynı barkodu 2 sn sabit tutun (debounce kontrolü: çift ekleme olmamalı).
   5. Katalogda olmayan barkodu, ardından az ışık ve eğik açıyla geçerli barkodu okutun.
7. **Beklenen Sonuç:** Ürün A miktarı `2`, debounce çift eklemez, bilinmeyen barkodta *"Ürün bulunamadı"* görünür; 10 denemede en az 9 başarılı okuma.
8. **Veri Bütünlüğü / Log Kontrolü:** Sepet kalem sayısı, birim fiyat (`12.50 TL` formatında), istenmeyen sıfır/negatif satır yok.
9. **Başarısızlık Durumunda Yapılacaklar:** Kamera izni/ışığı doğrulayın, elle barkod girişini deneyin, okunamayan barkod türünü not edin.
10. **Kanıt Türü:** Sepet ekran görüntüleri, kısa video, cihaz modeli.
11. **Otomatik Ön-Doğrulama / Fiziksel Durum:** Otomatik: APK `allowBackup=false`, emülatörde açılış PASS (`CLIENT_APPLICATION_READINESS.md`) · **Fiziksel: NOT RUN / PENDING PHYSICAL TEST**.

### PAT-02 — Windows USB HID barkod okuyucu
1. **Test ID:** `PAT-02`
2. **Başlık:** Windows USB HID barkod okuyucu
3. **Amaç:** Klavye taklidi (`Enter` sonekli) USB barkod okuyucunun hızlı seri taramalarda karakter kaybetmeden çalıştığını doğrulamak.
4. **Ön Koşullar:** Windows masaüstü kasa (`market_pos.exe`) açık ve POS ekranında.
5. **Gerekli Cihaz / Ortam:** Windows kasa PC + USB HID barkod okuyucu (`Enter` sonekli).
6. **Adımlar:**
   1. Okuyucuyu Not Defteri'nde test edip `Enter` son ekini doğrulayın.
   2. POS ekranında Ürün A'yı 2 kez, arama kutusu odaktayken ve Stok Girişi ekranında okutun.
   3. Okuyucuyla 20 ürünü arka arkaya hızlıca tarayın.
7. **Beklenen Sonuç:** 20/20 taramada sıfır karakter kaybı, doğru ürün seçimi ve miktar artışı (`2`).
8. **Veri Bütünlüğü / Log Kontrolü:** Sepet/stok girişinde yanlış barkod parçalanması yok.
9. **Başarısızlık Durumunda Yapılacaklar:** TR-Q klavye düzenini ve HID karakterler arası gecikme (inter-character delay) ayarını kontrol edin.
10. **Kanıt Türü:** Sepet ekran görüntüsü, okuyucu modeli/sonek ayarı.
11. **Otomatik Ön-Doğrulama / Fiziksel Durum:** Otomatik: İzole Windows client `SMOKE_PASS` · **Fiziksel: NOT RUN / PENDING PHYSICAL TEST**.

### PAT-03 — Android Wi-Fi üzerinden Hub keşfi ve QR eşleştirme
1. **Test ID:** `PAT-03`
2. **Başlık:** Android Wi-Fi üzerinden Hub keşfi ve QR eşleştirme
3. **Amaç:** Gerçek LAN/Wi-Fi üzerinde UDP `8946` keşfini, `qr_flutter` QR + `server.crt` LAN IP SAN doğrulamasını ve Root CA pinlemeyi doğrulamak.
4. **Ön Koşullar:** `PAT-08`, `PAT-22` (`ca.crt`, `server.crt` LAN IPv4 SAN ile) ve `PAT-25` (`8945`/`8946` firewall, Private profil) tamamlanmış olmalı.
5. **Gerekli Cihaz / Ortam:** Windows Hub PC + aynı LAN'daki fiziksel Android cihaz (AP/client isolation kapalı).
6. **Adımlar:**
   1. Windows Tanılama → Cihaz Eşleştirme → yeni oturum (`PairingApprovalPanel` QR + JSON).
   2. Android sihirbazında QR tarayın/metni yapıştırın (`hub_url` mutlaka `https://<LAN_IP>:8945` olmalı, `127.0.0.1` veya Hyper-V `172.x` olmamalı).
   3. Windows'tan **Onayla** deyin.
   4. Android Tanılama'da `ca_fingerprint` değerinin dolu olduğunu doğrulayın; CA yoksa `503 ERR_CA_CERT_UNAVAILABLE` beklendiğini teyit edin.
   5. Android uygulamasını kapatıp açın → **Keşfet** ile `<= 5 sn` içinde tekrar HTTPS bağlantı kurun; mümkünse DHCP IP değişimi test edin.
7. **Beklenen Sonuç:** `ca_fingerprint` boş/`UNKNOWN` olmaz, `http://` düşüşü olmaz, 3 denemede `<= 5 sn` keşif + eşleşme.
8. **Veri Bütünlüğü / Log Kontrolü:** `%ProgramData%\MarketMMS\logs` içinde `PAIRING` kayıtları (parola/token sızıntısı yok).
9. **Başarısızlık Durumunda Yapılacaklar:** `Get-NetFirewallRule -DisplayName MarketMMS*`, ağ profilinin `Private` olması ve router isolation ayarını kontrol edin.
10. **Kanıt Türü:** QR ve Tanılama ekran görüntüleri, Hub `PAIRING` log kesiti.
11. **Otomatik Ön-Doğrulama / Fiziksel Durum:** Otomatik: İzole Hub `UDP 8948` keşfi + `DevicePairingClient` PASS · **Fiziksel: NOT RUN / PENDING PHYSICAL TEST**.

### PAT-04 — Gerçek LAN/internet kesintisi ve yeniden bağlantı
1. **Test ID:** `PAT-04`
2. **Başlık:** Gerçek LAN/internet kesintisi ve yeniden bağlantı
3. **Amaç:** Fiziksel ağ kesintisinde her iki cihazın kesintisiz satış/kısmi iade yaptığını, uygulama kapanıp açılınca Outbox'ın korunduğunu ve bağlantı dönünce kayıpsız uzlaştığını doğrulamak.
4. **Ön Koşullar:** Windows ve Android eşleştirilmiş ve senkronize.
5. **Gerekli Cihaz / Ortam:** Hub PC + Android cihaz + Wi-Fi/router veya Hub LAN kablosu.
6. **Adımlar:**
   1. Wi-Fi'yi kapatın (veya Hub kablosunu çekin).
   2. Android'de 5, Windows'ta 5 satış (1'i kısmi iade) yapın; *"Çevrimdışı • N"* rozetini doğrulayın.
   3. Uygulamaları kapatıp yeniden açın; `N` sayacının değişmediğini görün.
   4. Ağı açıp 60 sn bekleyin; her iki cihazda diğerinin satışlarını ve `0` Outbox sayacını doğrulayın.
7. **Beklenen Sonuç:** `N` sıfırlanır, toplam 10 satış tam 1 kez kaydedilir, kuruş toplamları ve stoklar birebir tutar.
8. **Veri Bütünlüğü / Log Kontrolü:** `ERR_CLIENT_SEQ_GAP` veya `409` çakışması yok; kısmi iade `PARTIALLY_REFUNDED` tutarlı.
9. **Başarısızlık Durumunda Yapılacaklar:** Outbox satırlarını kesinlikle silmeyin; maskeli tanı raporu + Hub logunu alın.
10. **Kanıt Türü:** Çevrimdışı rozet ekran görüntüleri, Hub satış listesi, tanı raporları.
11. **Otomatik Ön-Doğrulama / Fiziksel Durum:** Otomatik: `Stage J` §13.4 canlı Hub stop + DB close/reopen + restart sync PASS (`MULTI_DEVICE_ACCEPTANCE_REPORT.md`) · **Fiziksel: NOT RUN / PENDING PHYSICAL TEST**.

### PAT-05 — Birden fazla Android cihazda eşzamanlı satış
1. **Test ID:** `PAT-05`
2. **Başlık:** Birden fazla Android cihazda eşzamanlı satış
3. **Amaç:** Eşzamanlı çoklu cihaz satışlarında stok tutarlılığını ve benzersiz `device_id`/`client_seq` akışını doğrulamak.
4. **Ön Koşullar:** 2 fiziksel Android + 1 Windows kasa eşleştirilmiş; test ürününün stoğu `50`.
5. **Gerekli Cihaz / Ortam:** Windows Hub PC + 2 fiziksel Android cihaz.
6. **Adımlar:**
   1. Üç cihazda aynı üründen eşzamanlı 5'er satış yapın (toplam `15`); 1 cihazı satış sırasında kısa süre çevrimdışı bırakıp yeniden bağlayın.
   2. Senkronizasyon sonrası Hub ve tüm cihazlarda stoğu ve KDV/kategori görünümünü kontrol edin.
7. **Beklenen Sonuç:** Stok `50 - 15 = 35` olur; her satış tam 1 kez kaydedilir (not: ADR-019 gereği pilotta ürünler `%20 KDV` ve `category_id = null` ile eşitlenir).
8. **Veri Bütünlüğü / Log Kontrolü:** `FAILED_PERMANENT = 0`; üç cihazda benzersiz `device_id`.
9. **Başarısızlık Durumunda Yapılacaklar:** Cihazların farklı `device_id` taşıdığını kontrol edin; çakışma varsa tekrar eşleştirin.
10. **Kanıt Türü:** Hub ürün stoğu ve 3 cihazın satış geçmişi ekran görüntüleri.
11. **Otomatik Ön-Doğrulama / Fiziksel Durum:** Otomatik: `Stage J` §13.3 eşzamanlı çoklu istemci PASS · **Fiziksel: NOT RUN / PENDING PHYSICAL TEST**.

### PAT-06 — Birden fazla cihazda eşzamanlı stok girişi
1. **Test ID:** `PAT-06`
2. **Başlık:** Birden fazla cihazda eşzamanlı stok girişi
3. **Amaç:** Eşzamanlı stok kabullerinde (`STOCK_RECEIPT`) çift tıklama idempotency ve toplama doğruluğunu doğrulamak.
4. **Ön Koşullar:** Test ürünü stoğu `5`.
5. **Gerekli Cihaz / Ortam:** 1 Windows + 1 Android eşleştirilmiş cihaz.
6. **Adımlar:**
   1. Bir cihazda `+2`, diğerinde `+3` stok girişi yapın; bir cihazda **Kaydet**'e hızlıca iki kez dokunun.
   2. Senkronizasyon sonrası Hub stoğunu ve hareket geçmişini kontrol edin.
7. **Beklenen Sonuç:** Stok `5 + 2 + 3 = 10` olur; tam 2 `GIRIS` hareketi oluşur; yeni sahte ürün oluşmaz.
8. **Veri Bütünlüğü / Log Kontrolü:** `receipt_id` idempotency korunur; çift hareket yazılmaz.
9. **Başarısızlık Durumunda Yapılacaklar:** `receipt_id` ve Outbox kayıtlarını rapora ekleyin.
10. **Kanıt Türü:** Stok hareket geçmişi + Hub ürün kartı ekran görüntüleri.
11. **Otomatik Ön-Doğrulama / Fiziksel Durum:** Otomatik: `Stage J` §13.2 `STOCK_RECEIPT` sync PASS · **Fiziksel: NOT RUN / PENDING PHYSICAL TEST**.

### PAT-07 — Gerçek USB bellekte yedekleme ve geri yükleme
1. **Test ID:** `PAT-07`
2. **Başlık:** Gerçek USB bellekte yedekleme ve geri yükleme
3. **Amaç:** Gerçek USB diske şifreli dışa aktarım, dolu disk / ani çıkarma fail-closed kontrolü ve güvenli geri yüklemeyi doğrulamak.
4. **Ön Koşullar:** Windows kasada yerel yedek mevcut.
5. **Gerekli Cihaz / Ortam:** 1 sağlam USB bellek + 1 neredeyse dolu küçük USB bellek.
6. **Adımlar:**
   1. Harici Yedek → USB → **Son Yedeği Aktar** işlemini 2 kez çalıştırın (ikincisi üzerine yazmamalı).
   2. Dolu USB'ye aktarımı deneyin (`ERR_DISK_FULL`, yarım `.tmp` yok).
   3. Kopyalama sırasında USB'yi çekin (`ERR_TARGET_UNAVAILABLE`, yarım dosya yok).
   4. Başka cihaz yedeğini içe aktarmayı deneyin (reddedilmeli); kendi yedeğinizi içe aktarıp **Geri Yükle** yapın.
7. **Beklenen Sonuç:** Yarım/bozuk dosya oluşmaz; kendi yedeği geri yüklerken bekleyen Outbox satışları ve koruyucu `.mmsbak` korunur.
8. **Veri Bütünlüğü / Log Kontrolü:** `PRAGMA integrity_check = ok`, `.tmp` kalıntısı yok.
9. **Başarısızlık Durumunda Yapılacaklar:** USB dosya sistemini (FAT32/NTFS) ve boş alanı kaydedin.
10. **Kanıt Türü:** USB dosya listesi (`dir`), hata ekran görüntüleri, `Get-FileHash`.
11. **Otomatik Ön-Doğrulama / Fiziksel Durum:** Otomatik: `BackupFileTransfer` ve `DiskSpaceChecker` birim testleri PASS · **Fiziksel: NOT RUN / PENDING PHYSICAL TEST**.

### PAT-08 — Gerçek Windows SCM kurulumu
1. **Test ID:** `PAT-08`
2. **Başlık:** Gerçek Windows SCM kurulumu
3. **Amaç:** `MarketMMSService`'in gerçek Windows Service Control Manager altında `NT AUTHORITY\LocalService`, `SID_TYPE=UNRESTRICTED` ve otomatik başlatma ile çalışmasını doğrulamak.
4. **Ön Koşullar:** `PAT-21`, `PAT-22` (`certs\server.crt`, `server.key`, `ca.crt`) tamamlanmış ve eski `MarketMmsSpike01` kaldırılmış olmalı.
5. **Gerekli Cihaz / Ortam:** Yönetici yetkili Hub bilgisayarı (Windows PowerShell 5.1).
6. **Adımlar:**
   1. Servis başlatma/güncelleme betiğini veya `sc.exe start MarketMMSService` komutunu çalıştırın (`PAT-21` sonrası TLS eklendiyse).
   2. `Get-Service MarketMMSService` (`Running`, `Automatic`) ve `sc.exe qsidtype MarketMMSService` (`UNRESTRICTED`) kontrol edin.
   3. `https://127.0.0.1:8945/health` kontrolü → `UP`.
   4. PC'yi yeniden başlatıp servisin kendiliğinden ayağa kalktığını doğrulayın; `hub_config.json` ve `admin_secret.txt` hash'lerini kaydedin.
7. **Beklenen Sonuç:** Servis reboot sonrası otomatik çalışır, `/health` `UP` döner ve kimlik/ayar dosyaları korunur.
8. **Veri Bütünlüğü / Log Kontrolü:** `HKLM:\SYSTEM\CurrentControlSet\Services\MarketMMSService\Parameters` altında `MmsAppVersion`, `MmsXmlSha256`, `MmsTxId` damgaları mevcut; `MarketMmsSpike01` yok.
9. **Başarısızlık Durumunda Yapılacaklar:** `%ProgramData%\MarketMMS\logs` ve `installer-diagnostics.log` dosyalarını toplayın.
10. **Kanıt Türü:** PowerShell çıktıları, `Get-Service` / `sc.exe qsidtype`, `/health` çıktısı.
11. **Otomatik Ön-Doğrulama / Fiziksel Durum:** Otomatik: B-1 + Stage H izole sandbox simülasyonu (`SIM_06`, `SIM_11`) PASS · **Fiziksel: NOT RUN / PENDING PHYSICAL TEST**.

### PAT-09 — Servis çökmesi, yeniden başlatma ve başarısız güncellemede geri dönüş
1. **Test ID:** `PAT-09`
2. **Başlık:** Servis çökmesi, yeniden başlatma ve başarısız güncellemede geri dönüş
3. **Amaç:** WinSW crash recovery (`5 sn`, `15 sn`, `60 sn` gecikme) ve kesinti anında gönderilen satışların veri kaybı olmadan işlenmesini doğrulamak.
4. **Ön Koşullar:** `PAT-08` geçmiş.
5. **Gerekli Cihaz / Ortam:** Yükseltilmiş Hub bilgisayarı + eşleştirilmiş Android cihaz.
6. **Adımlar:**
   1. Yönetici PowerShell ile `Stop-Process -Name mms_backend -Force` çalıştırıp WinSW'nin ~5 sn içinde yeniden başlattığını doğrulayın.
   2. 3 kez art arda öldürerek WinSW restart kurtarma döngüsünü gözlemleyin.
   3. Süreç kapalıyken Android'den 1 satış gönderin ve servis ayağa kalkınca satışın tam 1 kez kaydedildiğini görün (güncelleme geri dönüşü için bkz. `PAT-24`).
7. **Beklenen Sonuç:** `/health` kurtarma sonrası `UP`, Android satışı kayıpsız/tekrarsız işlenir.
8. **Veri Bütünlüğü / Log Kontrolü:** WinSW wrapper logları ve Windows Event Log (System) kontrol edilir.
9. **Başarısızlık Durumunda Yapılacaklar:** `bin.previous` içeriğini kontrol edin; veritabanına dokunmadan log alın.
10. **Kanıt Türü:** WinSW logları, Event Viewer ekran görüntüsü, `/health` çıktısı.
11. **Otomatik Ön-Doğrulama / Fiziksel Durum:** Otomatik: `MarketMMSService.xml` onfailure ayarları mevcut · **Fiziksel: NOT RUN / PENDING PHYSICAL TEST**.

### PAT-10 — Gerçek ACL ve firewall doğrulaması
1. **Test ID:** `PAT-10`
2. **Başlık:** Gerçek ACL ve firewall doğrulaması
3. **Amaç:** Standart kullanıcı oturumunda `%ProgramData%\MarketMMS` hassas dizinlerinin kapalı olduğunu ve Firewall'un yalnızca `Private` profilde aynı alt ağa izin verdiğini doğrulamak.
4. **Ön Koşullar:** `PAT-08` geçmiş; makinede yönetici olmayan (standart) ikinci bir Windows hesabı tanımlı.
5. **Gerekli Cihaz / Ortam:** Hub PC (standart hesap ile test) + aynı LAN ve farklı alt ağ/Public profil cihazları.
6. **Adımlar:**
   1. Standart kullanıcı ile `%ProgramData%\MarketMMS\data`, `security`, `config`, `certs` açmayı deneyin (*"Erişim engellendi"*).
   2. `icacls "%ProgramData%\MarketMMS\security"` çıktısında `Users`, `Everyone`, `Authenticated Users` olmadığını doğrulayın.
   3. Aynı alt ağdaki Android'in bağlandığını, farklı alt ağ ve `Public` ağ profilinde bağlantının engellendiğini doğrulayın, sonra `Private`'a dönün.
7. **Beklenen Sonuç:** Standart kullanıcı erişimi engellenir, firewall yalnızca Private + LocalSubnet üzerinde açıktır.
8. **Veri Bütünlüğü / Log Kontrolü:** `icacls` + `Get-NetFirewallRule` + `Get-NetFirewallAddressFilter` çıktıları doğrulanır.
9. **Başarısızlık Durumunda Yapılacaklar:** `setup_service_acls.ps1` ve `configure_hub_firewall.ps1` loglarını kaydedin.
10. **Kanıt Türü:** `icacls` ve `Get-NetFirewall*` çıktıları, erişim engeli ekran görüntüsü.
11. **Otomatik Ön-Doğrulama / Fiziksel Durum:** Otomatik: `Test 21/22` + Stage F `server.key` `icacls` PASS · **Fiziksel: NOT RUN / PENDING PHYSICAL TEST**.

### PAT-11 — Gerçek Android release APK kurulumu
1. **Test ID:** `PAT-11`
2. **Başlık:** Gerçek Android release APK kurulumu
3. **Amaç:** Gerçek release keystore ile imzalanmış APK'nın kurulduğunu, `allowBackup=false` / `usesCleartextTraffic=false` ile çalıştığını ve reboot sonrası Android Keystore sırrının korunduğunu doğrulamak.
4. **Ön Koşullar:** `B1` (`android/key.properties`) tamamlanmış ve ticari release `flutter build apk --release` üretilmiş olmalı *(Not: Stage I'deki APK `TEST-SIGNED ONLY` debug imzalıdır, gerçek mağaza testi için kullanılmaz)*.
5. **Gerekli Cihaz / Ortam:** Fiziksel Android telefon (`minSdk 24+`).
6. **Adımlar:**
   1. APK'yı `.sha256` doğrulayıp kurun; `apksigner verify --print-certs` ile debug sertifikası **olmadığını** doğrulayın.
   2. İlk açılış → `PAT-03` eşleştirmesini yapın.
   3. Sistem yedeklemesinde (`adb shell bmgr`) uygulama verisinin Google yedeğine dahil olmadığını ve `http://` Hub adresinin reddedildiğini görün.
   4. Telefonu yeniden başlatıp eşleşme durumunun korunduğunu doğrulayın.
7. **Beklenen Sonuç:** Release imzalı kurulum, Keystore kalıcılığı, HTTP ve yedekleme engeli çalışır.
8. **Veri Bütünlüğü / Log Kontrolü:** Loglarda token veya özel anahtar yer almaz.
9. **Başarısızlık Durumunda Yapılacaklar:** APK'yı silmeden tanı raporu alın.
10. **Kanıt Türü:** `apksigner` çıktısı, ekran görüntüleri, `bmgr` çıktısı.
11. **Otomatik Ön-Doğrulama / Fiziksel Durum:** Otomatik: Fail-closed signing guard (`Exit 1`) + `aapt2` (`allowBackup=false`, `usesCleartextTraffic=false`) + emülatör boot (`APP_PID=3757`) PASS · **Fiziksel: NOT RUN / PENDING PHYSICAL TEST**.

### PAT-12 — Gerçek TLS sertifikası ile bağlantı ve sertifika rotasyonu
1. **Test ID:** `PAT-12`
2. **Başlık:** Gerçek TLS sertifikası ile bağlantı ve sertifika rotasyonu
3. **Amaç:** Gerçek LAN/Android istemcinin Root CA pinleme altında sertifika rotasyonunu kesintisiz atlattığını ve sahte/farklı CA sertifikasını fail-closed reddettiğini doğrulamak.
4. **Ön Koşullar:** `PAT-22` ve (2–5. adımlar için) `PAT-03` tamamlanmış olmalı.
5. **Gerekli Cihaz / Ortam:** Hub PC + eşleştirilmiş Android cihaz.
6. **Adımlar:**
   1. *(Eşleştirme öncesi)* `https://<LAN_IP>:8945/health` adresini açıp `ca.crt` zincirini doğrulayın.
   2. *(PAT-03 sonrası)* Android Tanılama'da TLS durumunun **"Sabitlenmiş"** olduğunu görün.
   3. Hub `server.crt` sertifikasını aynı `ca.crt` ile yenileyip servisi yeniden başlatın → cihaz yeniden eşleşmeden bağlanmalı.
   4. Geçici olarak **farklı CA** imzalı sertifika takın → `TLS_PIN_MISMATCH` hatası görünmeli, `http://` düşüşü olmamalı ve bekleyen işlemler `RETRY` kalmalı.
   5. Doğru sertifikaya dönüp bekleyen işlemlerin gönderildiğini doğrulayın.
7. **Beklenen Sonuç:** Rotasyonda yeniden eşleşme gerekmez (`<= 1` tur gecikme); sahte CA'da Hub logunda cihaz isteği oluşmaz.
8. **Veri Bütünlüğü / Log Kontrolü:** Outbox verisi sıfır kayıpla gönderilir.
9. **Başarısızlık Durumunda Yapılacaklar:** `server.crt` SAN alanında aktif LAN IPv4 adresinin bulunduğunu doğrulayın.
10. **Kanıt Türü:** Rozet ekran görüntüleri, Hub erişim logu, Outbox sayacı.
11. **Otomatik Ön-Doğrulama / Fiziksel Durum:** Otomatik: Stage F TLS matrisi (`T1`–`T6` PASS, rotasyon `CC1DADC9...` PASS, wrong-CA & expired reject PASS) · **Fiziksel: NOT RUN / PENDING PHYSICAL TEST**.

### PAT-13 — Gerçek Google OAuth ve Drive yükleme
1. **Test ID:** `PAT-13`
2. **Başlık:** Gerçek Google OAuth ve Drive yükleme
3. **Amaç:** Canlı Google OAuth PKCE (`drive.file` kapsamı) yetkilendirmesi ile şifreli `.mmsbak` yüklemesi, yinelenmeme, kesinti dayanıklılığı ve `ERR_DRIVE_REAUTH_REQUIRED` akışını doğrulamak.
4. **Ön Koşullar:** `C1/C2` OAuth Client ID (`MMS_GDRIVE_CLIENT_ID`) tanımlanmış, internet aktif ve test Google hesabı hazır.
5. **Gerekli Cihaz / Ortam:** Hub PC + internet + Google hesabı.
6. **Adımlar:**
   1. Harici Yedek → **Google Drive'ı Bağla**; yalnızca `drive.file` izni istendiğini görün.
   2. Otomatik yedek alıp Drive'da `"MARKET MMS Yedekleri"` altında `.mmsbak` görün; 2. tetiklemede çift yükleme olmadığını doğrulayın.
   3. Yükleme sırasında interneti kesip yerel yedeğin başarılı kaldığını ve ağ dönünce upload'un tamamlandığını doğrulayın.
   4. Google hesap izinlerinden uygulamayı kaldırın (`ERR_DRIVE_REAUTH_REQUIRED`), ardından indirilen dosyayı USB içe aktarma ile test edin.
7. **Beklenen Sonuç:** Yalnızca şifreli `.mmsbak` yüklenir; Drive dosya boyutu ve MD5 yerel dosya ile birebir eşleşir.
8. **Veri Bütünlüğü / Log Kontrolü:** OAuth access/refresh token'lar loglarda maskelenir.
9. **Başarısızlık Durumunda Yapılacaklar:** Maskeli tanı raporunu alın; token veya secret dosyasını ellemeyin.
10. **Kanıt Türü:** Google izin ekranı ve Drive klasörü görüntüleri, `Get-FileHash -Algorithm MD5` çıktısı.
11. **Otomatik Ön-Doğrulama / Fiziksel Durum:** Otomatik: Mock OAuth PKCE / DPAPI / ResumableDriveUploader testleri PASS (`GOOGLE_DRIVE_ACCEPTANCE_REPORT.md`) · **Fiziksel: NOT RUN / PENDING PHYSICAL TEST (`BLOCKED` — gerçek OAuth kimlik bilgisi gerekli)**.

### PAT-14 — Restore sırasında uygulamanın kapanması (elektrik kesintisi)
1. **Test ID:** `PAT-14`
2. **Başlık:** Restore sırasında uygulamanın kapanması (elektrik kesintisi)
3. **Amaç:** Geri yükleme ortasında zorla sonlandırma sonrası restore journal kurtarmasını, PBKDF2 süresini ve bekleyen Outbox satışlarının korunumunu doğrulamak.
4. **Ön Koşullar:** Şifreli yedek mevcut ve yedek sonrası 2 adet gönderilmemiş satış Outbox'ta.
5. **Gerekli Cihaz / Ortam:** Windows kasa PC (Görev Yöneticisi) + düşük donanımlı fiziksel Android cihaz.
6. **Adımlar:**
   1. Geri Yükle'yi başlatın; ilerleme sırasında Görev Yöneticisi / Android *"Zorla durdur"* ile kapatın.
   2. Uygulamayı açıp journal kurtarmasının DB'yi sağlam açtığını (`PRAGMA integrity_check = ok`) ve 2 Outbox satışının durduğunu doğrulayın.
   3. Kesintisiz restore tamamlayıp toplam süreyi ve UI akıcılığını kaydedin.
7. **Beklenen Sonuç:** Veri bozulması ve Outbox kaybı olmaz; >60 sn sürede Owner onayı değerlendirilir.
8. **Veri Bütünlüğü / Log Kontrolü:** Tanı raporunda `PRAGMA integrity_check = ok`.
9. **Başarısızlık Durumunda Yapılacaklar:** `*.restore_journal`, `*.swap_bak`, `*.restore_staging.tmp` dosyalarını kesinlikle silmeden yedekleyin.
10. **Kanıt Türü:** Ekran kaydı, kronometre süresi, tanı raporu.
11. **Otomatik Ön-Doğrulama / Fiziksel Durum:** Otomatik: `restore_outbox_preservation_test.dart` & `restore_safety_snapshot_encryption_test.dart` PASS · **Fiziksel: NOT RUN / PENDING PHYSICAL TEST**.

### PAT-15 — Gerçek cihazda zamanlanmış yedek (uygulama açık / kapalı)
1. **Test ID:** `PAT-15`
2. **Başlık:** Gerçek cihazda zamanlanmış yedek (uygulama açık / kapalı)
3. **Amaç:** Açık/kapalı cihazda zamanlanmış yedeğin `BackupOperationLock` kilit çakışması yöneterek `.mmsbak` ürettiğini doğrulamak.
4. **Ön Koşullar:** Otomatik yedekleme açık (en az 8 karakter Keystore parolası); Android cihaz şarjda (`minSdk 24+`).
5. **Gerekli Cihaz / Ortam:** Fiziksel Android cihaz + Windows kasa.
6. **Adımlar:**
   1. Uygulama açıkken yedek döngüsünü doğrulayın.
   2. Restore başlatıp hemen ardından zamanlanmış yedeği tetikleyin (`BackupOperationLock` sebebiyle hata üretmeden atlamalı).
   3. Uygulamayı kapatıp periyodik iş (`PAT-16`) çalışmasını gözlemleyin.
7. **Beklenen Sonuç:** Kilit çakışmasında DB bozulmaz; yalnızca şifreli `.mmsbak` oluşur.
8. **Veri Bütünlüğü / Log Kontrolü:** `BackupOperationLock` heartbeat ve sıfır düz `.db` çıktısı.
9. **Başarısızlık Durumunda Yapılacaklar:** Arka plan pil kısıtlamalarını ve tanı loglarını kaydedin.
10. **Kanıt Türü:** Yedek geçmişi ekran görüntüsü, dosya listesi.
11. **Otomatik Ön-Doğrulama / Fiziksel Durum:** Otomatik: `backup_operation_lock_test.dart` & `scheduled_backup_runner_test.dart` PASS · **Fiziksel: NOT RUN / PENDING PHYSICAL TEST**.

### PAT-16 — Android Uygulama Kapalıyken Arka Plan Şifreli Yedekleme ve Yeniden Başlatma Kalıcılığı
1. **Test ID:** `PAT-16`
2. **Başlık:** Android Uygulama Kapalıyken Arka Plan Şifreli Yedekleme ve Yeniden Başlatma Kalıcılığı
3. **Amaç:** `MmsBackgroundBackupJobService` (`JobScheduler`, `JOB_ID = 70201`) servisinin uygulama tamamen kapalıyken ve reboot sonrası çalışmasını doğrulamak.
4. **Ön Koşullar:** Release APK kurulu, otomatik yedek parolası Keystore'da kayıtlı.
5. **Gerekli Cihaz / Ortam:** Fiziksel Android cihaz + USB hata ayıklama (`adb` yalnızca `jobscheduler` tetikleme/log için).
6. **Adımlar:**
   1. Tanılama → Otomatik Yedekleme'de *"Arka Plan Zamanlayıcı: ZAMANLANDI"* durumunu doğrulayın.
   2. Uygulamayı zorla durdurun ve Recents'tan kapatın.
   3. Süreyi bekleyin veya `adb shell cmd jobscheduler run -f com.marketmms.market_pos 70201` çalıştırın.
   4. Yeni `.mmsbak` oluştuğunu (`> 0` bayt) ve telefon yeniden başlatılınca zamanlamanın korunduğunu doğrulayın.
7. **Beklenen Sonuç:** Şifresiz `.db` bırakılmadan `.mmsbak` üretilir (`PRAGMA integrity_check = ok`); Keystore kilitliyse fail-closed olur.
8. **Veri Bütünlüğü / Log Kontrolü:** Şifreli paket çözülüp `integrity_check = ok` doğrulanır.
9. **Başarısızlık Durumunda Yapılacaklar:** Üretici pil optimizasyonu ayarını ("Kısıtlanmamış") ve `dumpsys jobscheduler` çıktısını alın.
10. **Kanıt Türü:** Zamanlama UI görüntüsü, dosya zaman damgası, `jobscheduler` çıktısı.
11. **Otomatik Ön-Doğrulama / Fiziksel Durum:** Otomatik: `workmanager_background_backup_test.dart` PASS · **Fiziksel: NOT RUN / PENDING PHYSICAL TEST**.

### PAT-17 — Google Drive Gerçek Hesap ile Yedek Listeleme, Kesintili İndirme ve Kontrollü Geri Yükleme
1. **Test ID:** `PAT-17`
2. **Başlık:** Google Drive Gerçek Hesap ile Yedek Listeleme, Kesintili İndirme ve Kontrollü Geri Yükleme
3. **Amaç:** Gerçek Drive listesinden yanlış parola reddini, doğru parolayla güvenlik kopyalı geri yüklemeyi ve OAuth bağlantısı kaldırmayı doğrulamak.
4. **Ön Koşullar:** `PAT-13` geçmiş ve Drive'da en az 1 şifreli `.mmsbak` var; yerel DB'de gönderilmemiş 1 test satışı mevcut.
5. **Gerekli Cihaz / Ortam:** Windows kasa (OAuth bağlı) + internet bağlantısı.
6. **Adımlar:**
   1. Tanılama → Harici Yedek → **Drive Yedeklerinden Geri Yükle** listesini açın.
   2. Önce bilerek **yanlış parola** girin (`ERR_DECRYPTION_FAILED`, canlı DB değişmemeli).
   3. Ardından **doğru parola** ile geri yükleyin; koruyucu `.mmsbak` oluşumunu ve bekleyen Outbox satışının korunduğunu görün.
   4. **Bağlantıyı Kaldır** (`disconnect`) ile token iptalini doğrulayın.
7. **Beklenen Sonuç:** Yanlış parola canlı veriye dokunmaz; doğru geri yüklemede Outbox korunur.
8. **Veri Bütünlüğü / Log Kontrolü:** Outbox sayacı ve `safety` klasörü dosya listesi doğrulanır.
9. **Başarısızlık Durumunda Yapılacaklar:** Maskeli tanı raporu alın.
10. **Kanıt Türü:** Geri yükleme öncesi/sonrası satış ve Outbox görüntüleri.
11. **Otomatik Ön-Doğrulama / Fiziksel Durum:** Otomatik: `drive_backup_restore_integration_test.dart` PASS + izole Hub backup/tamper/restore `PASS` · **Fiziksel: NOT RUN / PENDING PHYSICAL TEST (`BLOCKED` — canlı OAuth gerekli)**.

### PAT-18 — Hub Öncelikli Hibrit + Google Drive Canlı Senkronizasyon ve Hub Geri Dönüş Uzlaştırması
1. **Test ID:** `PAT-18`
2. **Başlık:** Hub Öncelikli Hibrit + Google Drive Canlı Senkronizasyon ve Hub Geri Dönüş Uzlaştırması
3. **Amaç:** Hub açıkken 0 Drive trafiği, Hub kapanınca Drive `.mmsenv` fallback senkronu ve Hub dönünce çakışma çözümü/uzlaştırmayı sahada doğrulamak.
4. **Ön Koşullar:** Aynı `tenant_id`/`store_id`, aynı Drive hesabı ve aynı `drive_live_sync_secret_v1` ile bağlı 2 cihaz; `PAT-13` tamamlanmış.
5. **Gerekli Cihaz / Ortam:** Windows Hub PC + 2 eşleştirilmiş istemci + internet.
6. **Adımlar:**
   1. Hub açıkken Cihaz A'da 1 satış yapın; Drive'a canlı zarf yazılmadığını görün (*"Hub Birincil"*).
   2. Windows Hub servisini durdurun; eşik aşılınca *"Google Drive Canlı Senkron Aktif (Fallback)"* geçişini gözlemleyin.
   3. Cihaz A'da 1 satış ve Cihaz B'de aynı üründe fiyat değişikliği yapıp Cihaz B'de görünmesini / non-LWW uyarısını doğrulayın.
   4. Windows Hub servisini başlatıp her iki cihazda *"Master Hub ile Uzlaştırıldı (Güncel)"* ve `0 PENDING` sonucunu teyit edin.
7. **Beklenen Sonuç:** Echo loop yok, mükerrer satış yok, Hub fiyat otoritesi korunur.
8. **Veri Bütünlüğü / Log Kontrolü:** Outbox `0 PENDING`, Hub satış toplamları tutarlı.
9. **Başarısızlık Durumunda Yapılacaklar:** `.mmsenv` dosyalarını ve maskeli tanı raporlarını inceleyin.
10. **Kanıt Türü:** Her durum geçişinde Tanılama ekran görüntüsü, Hub satış listesi.
11. **Otomatik Ön-Doğrulama / Fiziksel Durum:** Otomatik: `hybrid_drive_live_sync_test.dart` & `hybrid_drive_sync_coordinator_test.dart` PASS · **Fiziksel: NOT RUN / PENDING PHYSICAL TEST (`BLOCKED` — canlı OAuth gerekli)**.

### PAT-19 — İkincil Barkodun Çoklu Cihaz Senkronizasyonu (`GAP-A01`)
1. **Test ID:** `PAT-19`
2. **Başlık:** İkincil Barkodun Çoklu Cihaz Senkronizasyonu (`GAP-A01`)
3. **Amaç:** İkincil barkod ekleme/silme, çakışma (`409 ERR_DUPLICATE_BARCODE`), çevrimdışı ekleme ve yeniden dirilme önlemini sahada doğrulamak.
4. **Ön Koşullar:** `PAT-03` ile eşleştirilmiş 2 cihaz + Hub çalışıyor.
5. **Gerekli Cihaz / Ortam:** Windows Hub PC + 2 istemci + 2 farklı barkod etiketli tek test ürünü.
6. **Adımlar:**
   1. Cihaz A'da ürün oluşturun ve senkron olmasını bekleyin.
   2. İkincil barkod ekleyin; Cihaz B'de okutarak doğru fiyatla sepete geldiğini görün.
   3. Cihaz B'de başka ürüne aynı ikincil barkodu veya kendi birincil barkodunu ikincil eklemeyi deneyin (ikisi de reddedilmeli).
   4. Cihaz A'da ikincil barkodu silin → senkron sonrası Cihaz B'de artık bulunmamalı ve geri dirilmemeli.
   5. Uçak modunda barkod ekleyip o barkodla satış yapın, sonra ağı açıp FIFO uzlaştırmasını doğrulayın.
7. **Beklenen Sonuç:** Barkod ekleme/silme ve `409` reddi iki cihazda tutarlı; veri kaybı/dirilme yok.
8. **Veri Bütünlüğü / Log Kontrolü:** Hub `GET /api/v1/products` yanıtında `barcodes` dizisi tutarlı.
9. **Başarısızlık Durumunda Yapılacaklar:** İlgili ürünün Outbox satırını ve maskeli tanı raporunu alın.
10. **Kanıt Türü:** Ürün detay ve Outbox ekran görüntüleri, `GET /api/v1/products` JSON kesiti.
11. **Otomatik Ön-Doğrulama / Fiziksel Durum:** Otomatik: `Stage J` §13.2 ikincil barkod + `secondary_barcode_pending_sync_test.dart` PASS · **Fiziksel: NOT RUN / PENDING PHYSICAL TEST**.

### PAT-20 — `android_full_e2e_verification_test.dart` Cihaz Koşumu (Yalnız İzole TEST Hub)
1. **Test ID:** `PAT-20`
2. **Başlık:** `android_full_e2e_verification_test.dart` Cihaz Koşumu (Yalnız İzole TEST Hub)
3. **Amaç:** Fiziksel Android üzerinde tam integration test paketinin üretim DB'ye dokunmadan TEST Hub (`E2E-HUB-01`) karşıtı doğrulamasını çalıştırmak.
4. **Ön Koşullar:** Üretim Hub'ından ayrı bir TEST Hub (`HUB_ID=E2E-HUB-01`, `E2E-` önekli kimlik) + geçici test token'ı.
5. **Gerekli Cihaz / Ortam:** Fiziksel Android cihaz (USB `adb`) + izole TEST Hub.
6. **Adımlar:**
   1. Önce `MMS_E2E_EXPECTED_HUB_ID=E2E-YANLIS` ile çalıştırıp `E2eHubTargetRejected` fail-closed engelini doğrulayın.
   2. Ardından doğru `MMS_E2E_HUB_ALLOWLIST` ve `MMS_E2E_EXPECTED_HUB_ID=E2E-HUB-01` ile `flutter test integration_test/android_full_e2e_verification_test.dart -d <cihaz>` çalıştırın.
   3. Test sonunda geçici test token'ını TEST Hub'dan iptal edin.
7. **Beklenen Sonuç:** 10/10 adım geçer; kısmi iade `PARTIALLY_REFUNDED`; yedek `VACUUM INTO` + `integrity_check = ok`.
8. **Veri Bütünlüğü / Log Kontrolü:** Üretim `MMS-HUB-MASTER` kesinlikle reddedilir.
9. **Başarısızlık Durumunda Yapılacaklar:** Geçici token'ı hemen iptal edip test çıktısını kaydedin.
10. **Kanıt Türü:** Terminal test çıktısı (token maskeli).
11. **Otomatik Ön-Doğrulama / Fiziksel Durum:** Otomatik: Masaüstü izole E2E (`isolated_live_hub_e2e_test.dart` + `stage_j_multidevice_live_e2e_test.dart`) PASS · **Fiziksel: NOT RUN / PENDING PHYSICAL TEST**.

---

## Hat C — Windows Installer, Güvenlik & Yükseltme/Geri Alma Saha Testleri (`PAT-21…PAT-26`) *(27 Kasım 2026 Eklendi)*

### PAT-21 — Temiz Windows VM / PC Üzerinde MSI Fresh Install & Dizin/Manifest Doğrulaması
1. **Test ID:** `PAT-21`
2. **Başlık:** Temiz Windows VM / PC Üzerinde MSI Fresh Install & Dizin/Manifest Doğrulaması
3. **Amaç:** `dist\installer_v1_0_0_tray\MarketMMS-Setup-1.0.0-x64.msi` paketinin temiz ortamda hatasız (`ExitCode 0`) kurulduğunu ve `MarketMmsSpike01` oluşturmadığını doğrulamak.
4. **Ön Koşullar:** Temiz Windows 10/11 (x64) test makinesi veya VM; yönetici (`Administrator`) yetkisi; öncesinde `SHA256SUMS.txt` doğrulaması (`183B014FD6ED80785E4302388A2362D020DAD300D3BDEE21317450EE73CA820C`).
5. **Gerekli Cihaz / Ortam:** Yükseltilmiş Windows x64 ortamı + PowerShell 5.1.
6. **Adımlar:**
   1. Varsa yerel istemci verisini `scripts\dev_test\backup_client_db_safe.ps1` ile yedekleyin.
   2. `msiexec /i MarketMMS-Setup-1.0.0-x64.msi /qn ALLOW_DEFERRED_TLS_START=1 HUB_PORT=8945 DISCOVERY_PORT=8946 /L*v install.log` (veya `run_vm_fresh_install_acceptance.ps1 -LiveVmExecution -ConfirmCleanTestVm`) çalıştırın.
   3. `C:\Program Files\MarketMMS\client\market_pos.exe` ve `C:\ProgramData\MarketMMS` altında 11 alt dizin (`bin`, `bin\broker`, `bin\lib`, `lib`, `config`, `certs`, `data`, `security`, `logs`, `backups`, `run`) + `config\install_manifest.json` (`PENDING_TLS_PROVISIONING`) oluştuğunu doğrulayın.
7. **Beklenen Sonuç:** `ExitCode 0` (ExitCode 74 / 1603 yok); `MarketMMSService` kayıtlı (`Stopped` veya TLS varsa `Running`); `MarketMmsSpike01` kesinlikle yok.
8. **Veri Bütünlüğü / Log Kontrolü:** `install.log` içinde hata yok; `installer-diagnostics.log` gerekirse maskeli; `HKLM:\...\Parameters` kimlik damgaları yazılı.
9. **Başarısızlık Durumunda Yapılacaklar:** `%TEMP%` `install.log` ve `%ProgramData%\MarketMMS\logs\installer-diagnostics.log` + `run\installer_tx_state.json` alın; otomatik rollback sonrası artıkları inceleyin.
10. **Kanıt Türü:** `msiexec` exit kodu, `install.log` özeti, `Get-ChildItem`, `Get-Service`.
11. **Otomatik Ön-Doğrulama / Fiziksel Durum:** Otomatik: Stage G MSI tablo COM denetimi + Stage H `SIM_01..SIM_08` & `Phase C Tests 1-27` PASS · **Fiziksel: NOT RUN / PENDING PHYSICAL TEST**.

### PAT-22 — Üretim TLS Sertifika Provizyonu & Loopback/LAN SAN Zorunluluğu
1. **Test ID:** `PAT-22`
2. **Başlık:** Üretim TLS Sertifika Provizyonu & Loopback/LAN SAN Zorunluluğu
3. **Amaç:** `OpenSSL 3.5.9` ile üretilen sertifikaların gerçek `MarketMMSService` tarafından yüklendiğini ve `127.0.0.1` + LAN IP SAN kurallarına uyduğunu doğrulamak.
4. **Ön Koşullar:** `PAT-21` geçmiş (`PENDING_TLS_PROVISIONING`).
5. **Gerekli Cihaz / Ortam:** Hub bilgisayarı (`OpenSSL 3.5.9`, offline Root CA anahtarı kasa/USB dışında tutulur).
6. **Adımlar:**
   1. Geçerli LAN IPv4 + `IP:127.0.0.1,DNS:localhost` SAN'lı ve `-notext` temiz PEM formatlı `ca.crt`, `server.crt`, `server.key` dosyalarını `C:\ProgramData\MarketMMS\certs\` içine koyun (`ca.key` konmaz!).
   2. `setup_service_acls.ps1` çalıştırıp ardından `Start-Service MarketMMSService` yapın.
   3. `Invoke-WebRequest` / tarayıcı ile `https://127.0.0.1:8945/health` ve `https://<LAN_IP>:8945/health` uçlarından `UP` döndüğünü görün.
7. **Beklenen Sonuç:** Servis `Running`, `/health` `UP`, `ca.key` diskte yok.
8. **Veri Bütünlüğü / Log Kontrolü:** `logs\` içinde `ERR_SERVER_CERT_MISSING_LOOPBACK_SAN` (`Exit 78`) veya `ERR_ADVERTISE_HOST_SAN_MISMATCH` uyarısı olmamalı.
9. **Başarısızlık Durumunda Yapılacaklar:** Sertifikanın `IP:127.0.0.1` ve mevcut LAN IP'yi içerdiğini `openssl x509 -in server.crt -text -noout` ile kontrol edin; `0.9.8k` değil `3.5.9` kullandığınızdan emin olun.
10. **Kanıt Türü:** `openssl x509` SAN çıktısı (özel anahtar hariç), `/health` JSON çıktısı.
11. **Otomatik Ön-Doğrulama / Fiziksel Durum:** Otomatik: Stage F TLS matrisi (`T1`–`T6`, `ExitCode 78` fail-closed dahil) PASS (`TLS_HUB_READINESS.md`) · **Fiziksel: NOT RUN / PENDING PHYSICAL TEST**.

### PAT-23 — Windows MSI Sürüm Yükseltme (Upgrade) & Canlı DB/Ayar Korunumu
1. **Test ID:** `PAT-23`
2. **Başlık:** Windows MSI Sürüm Yükseltme (Upgrade) & Canlı DB/Ayar Korunumu
3. **Amaç:** Mevcut satış/stok verisi içeren çalışan `1.0.0` Hub kurulumunun yeni sürüm MSI ile yükseltilirken `.pre_upgrade` yedeği alıp kullanıcı verisini kaybetmeden geçiş yaptığını doğrulamak.
4. **Ön Koşullar:** `PAT-21` & `PAT-22` geçmiş, DB'de en az birkaç test ürünü ve satışı var.
5. **Gerekli Cihaz / Ortam:** Hub bilgisayarı (Yönetici PowerShell) + yeni sürüm (veya aynı UpgradeCode'lu daha yüksek `ProductVersion` test) MSI.
6. **Adımlar:**
   1. Yükseltme öncesi `hub_config.json`, `admin_secret.txt` ve `market_master.db` kayıt sayılarını not edin.
   2. Yeni sürüm MSI kurulumunu başlatın (`msiexec /i ... /qn /L*v upgrade.log`).
   3. Kurulum sonrası `HKLM:\...\MarketMMSService\Parameters\MmsAppVersion`, `bin.previous\`, `admin_secret.txt` hash değişmezliğini ve satış/stok sayılarını doğrulayın.
7. **Beklenen Sonuç:** Eski sürüm sorunsuz kaldırılıp yenisi başlar; satışlar, `admin_secret.txt`, `certs\` ve `hub_config.json` değişmeden kalır.
8. **Veri Bütünlüğü / Log Kontrolü:** `upgrade.log` + `.pre_upgrade` DB yedeği + `PRAGMA integrity_check = ok`.
9. **Başarısızlık Durumunda Yapılacaklar:** Geri alma olduysa `PAT-24` adımlarını izleyin; `data\` klasörüne dokunmayın.
10. **Kanıt Türü:** Yükseltme öncesi/sonrası DB satır sayıları, `MmsAppVersion` kayıt defteri çıktısı, hash karşılaştırması.
11. **Otomatik Ön-Doğrulama / Fiziksel Durum:** Otomatik: `Phase C Test 6-8` & `AUD-MED-05` `VACUUM INTO .pre_upgrade` PASS · **Fiziksel: NOT RUN / PENDING PHYSICAL TEST**.

### PAT-24 — Başarısız Upgrade Rollback & B-1 Deterministik SCM Kimlik Korunumu
1. **Test ID:** `PAT-24`
2. **Başlık:** Başarısız Upgrade Rollback & B-1 Deterministik SCM Kimlik Korunumu
3. **Amaç:** Yükseltme ortasında hata oluştuğunda `mms_installer_engine.ps1` geri alma motorunun eski `1.0.0` ikililerini, `Parameters` SCM damgasını, `bin`/`lib`/`admin_secret.txt` ACL'lerini ve servis çalışma durumunu güvenli biçimde geri yüklediğini doğrulamak.
4. **Ön Koşullar:** Yalnızca ayrılmış test VM'de uygulanır (`PAT-21/22` kurulu).
5. **Gerekli Cihaz / Ortam:** Temiz test Windows VM (Yönetici PowerShell).
6. **Adımlar:**
   1. Yükseltme sırasında kontrollü bir engel (`Migration` veya geçersiz paket/port çakışması) senaryosunda kurulumu başarısızlığa düşürün.
   2. Rollback tamamlandığında `Get-Service MarketMMSService` durumunun eski kurulum durumuna (`Running`) döndüğünü, `Parameters\MmsAppVersion = 1.0.0` olduğunu ve `icacls security\admin_secret.txt` çıktılarını doğrulayın.
   3. `https://127.0.0.1:8945/health` (`UP`) ve mevcut `market_master.db` veri bütünlüğünü teyit edin.
7. **Beklenen Sonuç:** Servis yabancı/bozuk bırakılmaz, ACL kaybı yaşanmaz, DB dokunulmaz.
8. **Veri Bütünlüğü / Log Kontrolü:** `installer-diagnostics.log` ve `installer_tx_state.json` (`ROLLED_BACK`) incelenir.
9. **Başarısızlık Durumunda Yapılacaklar:** `PARTIAL_ROLLBACK_FAILED` yazıldıysa logları incelemeden zorla `sc delete` yapmayın.
10. **Kanıt Türü:** `installer_tx_state.json`, `Get-ItemProperty HKLM:\...\Parameters`, `icacls` ve `/health`.
11. **Otomatik Ön-Doğrulama / Fiziksel Durum:** Otomatik: B-1 `Test 25` & `Test 27` (Senaryo A-J + 14 edge-case) + `SIM_13..SIM_14` PASS (`B1_DETERMINISTIC_SCM_REMEDIATION_REPORT.md`) · **Fiziksel: NOT RUN / PENDING PHYSICAL TEST**.

### PAT-25 — Gerçek Windows Service SID (`NT SERVICE\MarketMMSService`) ACL & Firewall Kural Doğrulaması
1. **Test ID:** `PAT-25`
2. **Başlık:** Gerçek Windows Service SID (`NT SERVICE\MarketMMSService`) ACL & Firewall Kural Doğrulaması
3. **Amaç:** Gerçek `sc.exe showsid MarketMMSService` SID çözümlemesinin `setup_service_acls.ps1` içinde ExitCode `1332` vermeden çalıştığını ve `8945 TCP` / `8946 UDP` kurallarının oluştuğunu doğrulamak.
4. **Ön Koşullar:** `PAT-21` geçmiş (`MarketMMSService` SCM'de kayıtlı ve `SID_TYPE=UNRESTRICTED`).
5. **Gerekli Cihaz / Ortam:** Hub bilgisayarı (Yönetici + Standart hesap).
6. **Adımlar:**
   1. `sc.exe showsid MarketMMSService` ile SID çözümlemesini ve `setup_service_acls.ps1` sonucunu (`ExitCode 0`) teyit edin.
   2. `bin\broker` (`Users:RX`), kök `ProgramData\MarketMMS` (`Users:(X)` non-inherited), `data`/`logs`/`backups`/`security`/`certs` (`Users` yok, `Service SID` uygun hakta) ve `admin_secret.txt` (`SYSTEM:F`, `Administrators:F`, `ServiceSID:R`) ACL'lerini inceleyin.
   3. `Get-NetFirewallRule -DisplayName "*Market MMS*"` ve `Get-NetFirewallPortFilter` ile `8945 TCP` ve `8946 UDP` kurallarını doğrulayın.
7. **Beklenen Sonuç:** Sıfır `1332` / `87` `icacls` hatası; `Users` yalnızca çalıştırma geçişine sahip; Firewall kuralları `Private` + `LocalSubnet`.
8. **Veri Bütünlüğü / Log Kontrolü:** Reparse point uyarısı ve `BUILTIN\Users` sızıntısı yok.
9. **Başarısızlık Durumunda Yapılacaklar:** `installer-diagnostics.log` ACL satırlarını kaydedip `PAT-10` kontrolünü yapın.
10. **Kanıt Türü:** `sc.exe showsid`, tüm alt klasörlerin `icacls` çıktıları, `Get-NetFirewallRule` çıktısı.
11. **Otomatik Ön-Doğrulama / Fiziksel Durum:** Otomatik: `Test 21/22` + Stage C audit PASS · **Fiziksel: NOT RUN / PENDING PHYSICAL TEST**.

### PAT-26 — Windows MSI Güvenli Kaldırma (`PURGE_USER_DATA=0`) & Temiz Yeniden Kurulum
1. **Test ID:** `PAT-26`
2. **Başlık:** Windows MSI Güvenli Kaldırma (`PURGE_USER_DATA=0`) & Temiz Yeniden Kurulum
3. **Amaç:** Standart MSI kaldırma sırasında `MarketMMSService` ve Firewall kurallarının kaldırıldığını, ancak `data\`, `backups\`, `certs\`, `security\` dizinlerinin korunup yeniden kurulumda kesintisiz devam ettiğini doğrulamak.
4. **Ön Koşullar:** `PAT-21` & `PAT-22` kurulu, DB'de test verisi ve `.mmsbak` yedeği mevcut.
5. **Gerekli Cihaz / Ortam:** Hub test makinesi / VM (Yönetici PowerShell).
6. **Adımlar:**
   1. `msiexec /x MarketMMS-Setup-1.0.0-x64.msi /qn PURGE_USER_DATA=0 /L*v uninstall.log` çalıştırın.
   2. `MarketMMSService` ve firewall kurallarının kalktığını, `bin\mms_backend.exe` silindiğini, buna karşın `data\market_master.db`, `backups\`, `security\admin_secret.txt` ve `certs\` dosyalarının korunduğunu doğrulayın.
   3. Aynı MSI ile tekrar kurulum (`msiexec /i ...`) yapıp mevcut veri ve sertifikalarla `/health` → `UP` olduğunu doğrulayın.
7. **Beklenen Sonuç:** Kullanıcı verisi %100 korunur, tekrar kurulum sonrası sistem aynı veritabanı ve `admin_secret` ile ayağa kalkar.
8. **Veri Bütünlüğü / Log Kontrolü:** `market_master.db` `Get-FileHash` ve tablo kayıt sayısı korunur; `uninstall.log` temiz.
9. **Başarısızlık Durumunda Yapılacaklar:** DB dosyalarını silmeyin, yedek kopya alıp `uninstall.log` sunun.
10. **Kanıt Türü:** Kaldırma öncesi/sonrası dizin listesi, DB hash'i, yeniden kurulum `/health` çıktısı.
11. **Otomatik Ön-Doğrulama / Fiziksel Durum:** Otomatik: Stage H `SIM_15..SIM_19` + `Phase C Test 9-11` PASS · **Fiziksel: NOT RUN / PENDING PHYSICAL TEST**.

---

## Hat B — Merkezi Hub Google Drive Yedekleme Fiziksel Testleri (`BK-PAT-01…BK-PAT-18`)

Ayrıntılı adımlar ve ön koşullar [`docs/testing/BACKUP_RESTORE_ACCEPTANCE_TESTS_V1_1.md`](docs/testing/BACKUP_RESTORE_ACCEPTANCE_TESTS_V1_1.md) §4.2'dedir. Tüm `BK-PAT-01…BK-PAT-18` senaryoları gerçek Google OAuth (`C1/C2`), Portable Recovery Password, `TEST_ONLY` Drive hesabı ve ikinci temiz Windows PC gerektirir.

| Test ID | Kapsam | Otomatik Ön-Doğrulama | Fiziksel Test Durumu |
|---|---|---|---|
| `BK-PAT-01` | Windows PKCE → `LocalService` token devri, reboot kalıcılığı | Mock OAuth & DPAPI PASS | **NOT RUN / PENDING PHYSICAL TEST** |
| `BK-PAT-02` | İlk etkinleştirme yedeği + gerçek Drive upload/download | Stage K yerel backup PASS | **NOT RUN / PENDING PHYSICAL TEST** |
| `BK-PAT-03` | Doğal gece `00:00` yedeği + ertesi sabah `CATCH_UP` (saat değiştirilmez) | Scheduler testleri PASS | **NOT RUN / PENDING PHYSICAL TEST** |
| `BK-PAT-04` | Ağ kesintisinde 4 MiB chunk + `HTTP 308` devam | `resumable_drive_uploader_test` PASS | **NOT RUN / PENDING PHYSICAL TEST** |
| `BK-PAT-05` | Drive kota dolu / OAuth iptali (`FAILED_QUOTA` / `FAILED_AUTH`) | B2 OAuth testleri PASS | **NOT RUN / PENDING PHYSICAL TEST** |
| `BK-PAT-06` | Gerçek disk dolu (`ERR_INSUFFICIENT_DISK_SPACE`) | `disk_space_checker_test` PASS | **NOT RUN / PENDING PHYSICAL TEST** |
| `BK-PAT-07` | Upload sırasında servis durdurma (<12 s), aynı `backup_id` ile devam | S1–S6 hardening PASS | **NOT RUN / PENDING PHYSICAL TEST** |
| `BK-PAT-08` | Güç kesintisi / süreç çökmesi sonrası aşamalı kurtarma | Lock crash recovery PASS | **NOT RUN / PENDING PHYSICAL TEST** |
| `BK-PAT-09` | Restore sırasında eşzamanlı yedek/sync koruması (`409`) | Stage2/B4 RBAC restore PASS | **NOT RUN / PENDING PHYSICAL TEST** |
| `BK-PAT-10` | `TEST_ONLY` klasörde 30 gün + 12 ay retention | Retention policy testleri PASS | **NOT RUN / PENDING PHYSICAL TEST** |
| `BK-PAT-11` | `TEST_ONLY` klasörde son geçerli yedek koruması | Retention guard testleri PASS | **NOT RUN / PENDING PHYSICAL TEST** |
| `BK-PAT-12` | Yanlış kurtarma parolası reddi + şifreli safety snapshot | Stage K canlı tamper/wrong-key PASS | **NOT RUN / PENDING PHYSICAL TEST** |
| `BK-PAT-13` | İkinci temiz PC'de restore + toplu re-pairing | `s5a4_central_restore` PASS | **NOT RUN / PENDING PHYSICAL TEST** |
| `BK-PAT-14` | Restore sonrası çevrimdışı Android satışlarının kayıpsız uzlaştırması (`OV-03`) | `post_restore_reconciliation` PASS | **NOT RUN / PENDING PHYSICAL TEST** |
| `BK-PAT-15` | Android `OWNER` uzaktan tetik vs `CASHIER` kısıtı | B4 RBAC testleri PASS | **NOT RUN / PENDING PHYSICAL TEST** |
| `BK-PAT-16` | Eski Android yerel `.mmsbak` dosyalarının korunması | `s5_drive_folder_separation` PASS | **NOT RUN / PENDING PHYSICAL TEST** |
| `BK-PAT-17` | Safety snapshot'tan geri dönüş | `restore_safety_snapshot` PASS | **NOT RUN / PENDING PHYSICAL TEST** |
| `BK-PAT-18` | Oturum kapalıyken uzun süreli servis kararlılığı | — (yalnız fiziksel/uzun koşum) | **NOT RUN / PENDING PHYSICAL TEST** |
