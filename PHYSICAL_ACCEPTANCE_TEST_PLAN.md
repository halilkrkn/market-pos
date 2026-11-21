# MARKET MMS — Fiziksel Kabul Test Planı (Saha / Pilot)

*Tarih: 21 Kasım 2026 · Hazırlayan: Claude Code · Durum: **Hiçbiri çalıştırılmadı (BLOCKED — gerçek donanım/ortam gerekir)***

Bu plan, otomatik testlerin doğrulayamadığı her şeyi gerçek cihazda doğrulamak içindir.

- **Önerilen Yürütme Sırası:** `PAT-12 (adım 1: CA zinciri ve /health)` → `PAT-08` → `PAT-10` → `PAT-11` → `PAT-03` → `PAT-12 (adım 2–5: sabitlenmiş cihaz doğrulaması ve rotasyon)` → `PAT-01`, `PAT-02`, `PAT-04..07`, `PAT-09`, `PAT-14`, `PAT-15`, `PAT-16` → `PAT-13` → `PAT-17` → `PAT-18` (Google Drive ve hibrit canlı senkronizasyon — `C1/C2` OAuth kurulumu tamamlandığında).
- **Bağımlılık Notu (`PAT-12` adım 1 vs 2–5):** `PAT-12` adım 1 eşleştirmeden bağımsız olarak Hub sertifika zincirini tarayıcıdan doğrular; ancak adım 2–5 eşleştirilmiş cihaz gerektirdiğinden mutlaka `PAT-03` (`P-BLOCK-1..3` / `DEC-REV-1..5` kodda uygulanmış olup gerçek LAN/Android doğrulaması `PAT-03` içinde yürütülür) sonrasında çalıştırılır.

**Genel ön koşullar (tüm testler):**
1. `OWNER_ACTION_CHECKLIST.md` B1 (Android imza anahtarı) ve B2 (Hub TLS sertifikaları) tamamlanmış olmalı.
2. Hub temiz bir DB ile kurulmuş olmalı; manuel test DB'si ve token'ları **kullanılmaz**.
3. Test öncesi Hub'dan şifreli yedek alınmalı (`POST /api/v1/admin/backup`).
4. Her test için kanıt klasörü açılmalı: `pilot_kanit/PAT-xx_<tarih>/`.

**Kayıt formatı (her test sonunda doldurun):**

| Alan | Değer |
|---|---|
| Test ID / tarih / saat | |
| Uygulayan | |
| Cihazlar (model, Android/Windows sürümü, uygulama sürümü) | |
| Hub sürümü ve `hub_id` | |
| Sonuç | GEÇTİ / KALDI / KISMEN |
| Kanıt dosyaları | ekran görüntüsü, log, tanı raporu |
| Not / sapma | |

**Genel başarısızlık prosedürü:**
1. Durun. Kayıtları **silmeyin**; Outbox'ı temizlemeyin.
2. Tanılama → **Maskeli Tanı Raporunu Dışa Aktar** ile raporu alın.
3. Hub logunu kopyalayın: `%ProgramData%\MarketMMS\logs`.
4. Sorunu test ID'siyle kaydedin. Veri tutarsızlığı varsa satış yapmaya devam etmeden destekle iletişime geçin.

---

## PAT-01 — Android kamera ile barkod tarama (sürekli tarama ve sepet)
- **Ön koşullar:** Release APK kurulu ve cihaz eşleştirilmiş. Katalogda en az 3 barkodlu ürün var.
- **Donanım:** Kameralı Android cihaz; gerçek ürünler (EAN-13); katalogda olmayan bir barkod.
- **Adımlar:**
  1. POS → kamera ile tara. İlk açılışta kamera iznini verin.
  2. Ürün A'yı okutun. Sepette 1 adet görünmeli.
  3. Ürün A'yı tekrar okutun. Miktar **2** olmalı ve yeni satır açılmamalı.
  4. Ürün B'yi okutun.
  5. Aynı barkodu kameranın önünde 2 saniye tutun. Çift ekleme olmamalı (debounce).
  6. Katalogda olmayan barkodu okutun.
  7. Az ışıkta ve eğik açıyla okutmayı deneyin.
- **Beklenen sonuç:**
  - 2–4. adımlar doğru miktarlarla sonuçlanır; 5. adım tek ekleme yapar.
  - 6. adımda "Ürün bulunamadı" görünür ve sepete bir şey eklenmez.
- **Başarı kriteri:**
  - 10 okumanın en az 9'u ilk denemede doğru ürünü ekler.
  - Hiçbir çift ekleme olmaz.
- **Kanıt:** Sepet ekran görüntüleri, kısa video, cihaz modeli.
- **Başarısızlıkta:** Kamera iznini, odak ve ışığı kontrol edin. Elle barkod girişinin çalıştığını doğrulayın. Okunamayan barkod türünü kaydedin.

## PAT-02 — Windows USB HID barkod okuyucu
- **Ön koşullar:** Windows kasa uygulaması açık ve POS ekranında.
- **Donanım:** USB HID (klavye kipinde) barkod okuyucu. Okuyucu "Enter" son ekiyle yapılandırılmış olmalı.
- **Adımlar:**
  1. Okuyucuyu takın ve Not Defteri'nde okutup Enter eklendiğini doğrulayın.
  2. POS'ta Ürün A'yı iki kez okutun.
  3. Arama kutusu odaktayken okutun.
  4. Stok Girişi ekranında okutun.
  5. Okuyucuyla 20 ürünü arka arkaya hızlıca okutun.
- **Beklenen sonuç:**
  - 2. adımda miktar 2 olur.
  - 4. adımda doğru ürün açılır.
  - 5. adımda karakter kaybı veya karışma olmaz.
- **Başarı kriteri:** 20 okumanın 20'si de doğru ürün olmalı. Kayıp karakter olmamalı.
- **Kanıt:** Sepet ekran görüntüsü, okuyucu modeli, son ek ayarı.
- **Başarısızlıkta:** Okuyucunun klavye düzenini (TR-Q) ve son ekini kontrol edin. Karakter kaybı varsa okuyucu gecikme ayarını artırın ve tekrar ölçün.

## PAT-03 — Android Wi-Fi üzerinden Hub keşfi ve QR eşleştirme
- **Ön koşullar:**
  - Hub servisi çalışıyor ve firewall uygulanmış (`configure_hub_firewall.ps1`).
  - Ağ Windows'ta **Private** profilde.
  - `tls.ca_cert` yapılandırılmış.
- **Donanım:** Android cihaz ve Hub aynı Wi-Fi/LAN'da. Router'da istemci izolasyonu kapalı.
- **Adımlar:**
  1. Windows uygulamasında Tanılama → Cihaz Eşleştirme → yeni oturum açın (Windows `PairingApprovalPanel` `qr_flutter` ile canlı kare QR görseli çizer ve ayrıca kopyalanabilir eşleştirme JSON/metnini de sunar).
  2. Android'de kurulum sihirbazından eşleştirme metnini yapıştırarak veya harici QR taratarak başlatın (`P-BLOCK-1..3` / `DEC-REV-1..5` kodda uygulanmış olup `hub_url` alanı otomatik olarak `server.crt` SAN ile doğrulanan LAN IPv4 adresini taşımalıdır; `127.0.0.1` gelmesi başarısızlık/regresyon sayılır).
  3. Windows'ta bekleyen talebi görün ve **Onayla**'ya basın.
  4. Android'de eşleşme tamamlanmalı ve Tanılama'da CA parmak izi görünmeli (`ca_fingerprint` boş/`UNKNOWN` ise pin oluşmaz; `/pairing/session` üretim TLS'de CA yoksa `503 ERR_CA_CERT_UNAVAILABLE` dönmelidir).
  5. Android'de Hub adresini silin veya uygulamayı yeniden başlatın. Tanılama → Hub kartı → **Keşfet** (eşleştirilmiş cihaz yalnızca `https://` dener, UDP yanıtı `protocol_version: "1.0"` kalır).
  6. Hub'ın IP'sini (DHCP) değiştirin. Uygulamanın yeniden keşfettiğini doğrulayın.
- **Beklenen sonuç:**
  - `ca_fingerprint` `UNKNOWN` olmaz ve `503` sessiz geçilmez.
  - Keşif `https://<LAN IP>:8945` adresini bulur ve "Bağlı" görünür.
  - Sanal adaptör IP'leri (Hyper-V `172.x`) seçilmez.
- **Başarı kriteri:** 3 deneme içinde ≤ 5 sn'de bağlantı kurulur. HTTP'ye düşüş olmaz.
- **Kanıt:**
  - Eşleştirme ekranları.
  - Tanılama Hub kartı (adres, kaynak = discovered).
  - Hub logunda `PAIRING` kayıtları.
- **Başarısızlıkta:**
  - Firewall kuralını ve profilini kontrol edin. Komut: `Get-NetFirewallRule -DisplayName MarketMMS*`.
  - Router izolasyonunu kontrol edin.
  - Elle IP girerek bağlanabildiğini doğrulayın; bağlanabiliyorsa sorun keşiftedir, kaydedin.

## PAT-04 — Gerçek LAN/internet kesintisi ve yeniden bağlantı
- **Ön koşullar:** Android ve Windows kasa eşleştirilmiş ve senkron sağlıklı.
- **Donanım:** Router veya Hub'ın ağ kablosu.
- **Adımlar:**
  1. Wi-Fi'yi kapatın (veya Hub kablosunu çıkarın).
  2. Android'de 5, Windows'ta 5 satış yapın. Biri kısmi iade olsun.
  3. Rozet "Çevrimdışı • N" olmalı.
  4. Uygulamayı kapatıp açın; N değişmemeli.
  5. Bağlantıyı geri getirin ve 60 sn bekleyin.
  6. Hub'da satışları sayın. Her iki cihazın satış geçmişinde diğer cihazın satışlarını görün.
- **Beklenen sonuç:**
  - N, bağlantı gelince 0'a iner.
  - Satışlar Hub'da tam bir kez bulunur.
  - Stoklar doğru düşer.
- **Başarı kriteri:**
  - Kayıp ve çift kayıt yok.
  - `ERR_CLIENT_SEQ_GAP` / `409` yok.
  - Toplam tutar kuruş düzeyinde eşleşir.
- **Kanıt:** Rozet ekran görüntüleri; Hub satış listesi; her iki cihazın tanı raporu.
- **Başarısızlıkta:** Outbox'ı **silmeyin**. Tanı raporunu ve Hub logunu alın.

## PAT-05 — Birden fazla Android cihazda eşzamanlı satış
- **Ön koşullar:** 2 Android ve 1 Windows kasa eşleştirilmiş. Aynı üründen stok 50.
- **Donanım:** En az 2 Android cihaz.
- **Adımlar:**
  1. Üç cihazda aynı anda aynı ürünü satın. Her cihaz 5 satış yapsın, toplam 15.
  2. Bir cihazı satış sırasında çevrimdışı bırakın, sonra bağlayın.
  3. Hub'da ürün stoğunu kontrol edin.
- **Beklenen sonuç:**
  - Stok 50 − 15 = 35 olur.
  - Her satış bir kez kaydedilir.
  - KDV durumu: **ADR-019 pilotta ertelendiği için (`DEFERRED_POST_PILOT`)** çoklu KDV senkronu yapılmaz; yeni eşleştirilen tüm cihazlarda ürünler varsayılan **%20 KDV** ve `category_id = null` ile görünür. Bu beklenen geçici kısıt olarak kaydedilir.
- **Başarı kriteri:** Stok ve satış sayısı tam tutar; hata kuyruğu boş.
- **Kanıt:** Hub ürün kaydı; üç cihazın satış geçmişi.
- **Başarısızlıkta:** Cihazların `device_id` değerlerinin farklı olduğunu doğrulayın. Aynı kimlik varsa durun ve cihazı yeniden eşleştirin.

## PAT-06 — Birden fazla cihazda eşzamanlı stok girişi
- **Ön koşullar:** Ürün stoğu 5.
- **Donanım:** 2 cihaz (Android + Windows).
- **Adımlar:**
  1. İki cihazda aynı anda stok girişi yapın: biri +2, diğeri +3.
  2. Bir cihazda "Kaydet"e hızlıca iki kez dokunun.
  3. Senkron sonrası Hub stoğunu kontrol edin.
- **Beklenen sonuç:**
  - Stok 5 + 2 + 3 = **10** olur.
  - Çift dokunma tek hareket oluşturur.
  - Yeni ürün oluşmaz.
- **Başarı kriteri:** Stok 10; hareket geçmişinde tam 2 `GIRIS` kaydı.
- **Kanıt:** Stok hareket geçmişi ekranı; Hub ürün kaydı.
- **Başarısızlıkta:** Hareket kayıtlarının `receipt_id` değerlerini rapora ekleyin.

## PAT-07 — Gerçek USB bellekte yedekleme ve geri yükleme
- **Ön koşullar:** Windows kasada en az bir yerel yedek var.
- **Donanım:** Normal bir USB ve neredeyse dolu, küçük bir USB.
- **Adımlar:**
  1. Harici Yedek → USB yolu → **Son Yedeği Aktar**.
  2. Aynı işlemi tekrarlayın; üzerine yazmamalı.
  3. Küçük ve dolu USB ile deneyin: `ERR_DISK_FULL` gelmeli, yarım dosya kalmamalı.
  4. Kopyalama sırasında USB'yi çekin: `ERR_TARGET_UNAVAILABLE` gelmeli, `.tmp` kalmamalı.
  5. Başka bir cihazın yedeğini içe aktarmayı deneyin: reddedilmeli.
  6. USB'deki kendi yedeğinizi içe aktarıp **Geri Yükle**.
- **Beklenen sonuç:**
  - Doğrulanmış kopya oluşur ve hata kodları doğru çıkar.
  - Geri yükleme sonrası Hub'a gitmemiş satışlar korunur.
  - Koruyucu kopya `.mmsbak` olarak durur.
- **Başarı kriteri:** Hiçbir senaryoda yarım veya bozuk dosya "geçerli yedek" gibi görünmez.
- **Kanıt:** USB dosya listesi (`dir`), hata mesajı ekran görüntüleri, `Get-FileHash` çıktısı.
- **Başarısızlıkta:** USB dosya sistemini (FAT32/NTFS) ve kalan alanı kaydedin.

## PAT-08 — Gerçek Windows SCM kurulumu
- **Ön koşullar:**
  - Yönetici hesabı; `certs\server.crt`, `server.key` ve `ca.crt` yerinde.
  - `MarketMmsSpike01` kaldırılmış (Owner D1).
- **Donanım:** Hub bilgisayarı.
- **Adımlar:**
  1. Yönetici **Windows PowerShell 5.1**'de `.\scripts\install_mms_service.ps1` çalıştırın.
  2. `Get-Service MarketMMSService` → `Running`, `Automatic`.
  3. `sc.exe qsidtype MarketMMSService` → `UNRESTRICTED`.
  4. `https://127.0.0.1:8945/health` → `UP`.
  5. Bilgisayarı yeniden başlatın; servis kendiliğinden başlamalı.
  6. Betiği ikinci kez çalıştırın (güncelleme yolu). `hub_config.json` ve `admin_secret.txt` değişmemeli; `bin.previous` oluşmalı.
- **Beklenen sonuç:** Kurulum betiği `[SUCCESS]` ile biter; ayrıştırma hatası olmaz.
- **Başarı kriteri:**
  - Tüm adımlar geçer.
  - Config dosyalarının hash'i (`Get-FileHash`) güncelleme öncesi ve sonrası aynıdır.
- **Kanıt:** Betik çıktısı (transcript), `Get-Service` çıktısı, hash'ler.
- **Başarısızlıkta:** Betik çıktısını ve `%ProgramData%\MarketMMS\logs` klasörünü kaydedin. Servis kayıtlı kaldıysa `uninstall_mms_service.ps1` çalıştırın.

## PAT-09 — Servis çökmesi, yeniden başlatma ve başarısız güncellemede geri dönüş
- **Ön koşullar:** PAT-08 geçti.
- **Donanım:** Hub bilgisayarı.
- **Adımlar:**
  1. `Stop-Process -Name mms_backend -Force` ile süreci öldürün. WinSW onu 5 sn içinde yeniden başlatmalı.
  2. Üç kez art arda öldürün. Gecikmeler 5 sn, 15 sn ve 60 sn olmalı.
  3. Çökme anında bir Android satışı gönderin. Bağlantı gelince satış tam bir kez kaydedilmeli.
  4. Başarısız güncellemeyi deneyin: geçersiz bir `mms_backend.exe` ile betiği çalıştırın. Betik `GUNCELLEME BASARISIZ: Onceki surume geri donuldu` demeli ve servis eski sürümle çalışmalı.
- **Beklenen sonuç:** Servis kendini toparlar, veri kaybı olmaz, geri dönüş çalışır.
- **Başarı kriteri:** `/health` her adımdan sonra `UP` döner. Satış sayısı tutarlıdır.
- **Kanıt:** WinSW logları, Olay Görüntüleyicisi (System) kayıtları, `/health` çıktıları.
- **Başarısızlıkta:** `bin.previous` dosyalarını elle geri kopyalayın. Prosedür: `WINDOWS_HUB_RELEASE.md` §3.1.

## PAT-10 — Gerçek ACL ve firewall doğrulaması
- **Ön koşullar:** PAT-08 geçti. Yönetici olmayan bir Windows kullanıcısı (kasiyer) var.
- **Donanım:** Hub bilgisayarı; aynı LAN'da ve **farklı alt ağda** birer cihaz (mümkünse).
- **Adımlar:**
  1. Kasiyer hesabıyla `%ProgramData%\MarketMMS\data`, `security`, `config` ve `certs` klasörlerini açmayı deneyin. "Erişim engellendi" görmelisiniz.
  2. `icacls "%ProgramData%\MarketMMS\security"` çıktısında Users, Everyone veya Authenticated Users olmamalı.
  3. Aynı alt ağdaki Android Hub'a bağlanabilmeli.
  4. Farklı alt ağdaki cihaz bağlanamamalı (`LocalSubnet` kısıtı).
  5. Ağı **Public** profile alın; bağlantı kesilmeli. Sonra Private'a geri alın.
- **Beklenen sonuç:** ACL ve firewall yalnızca yetkili erişime izin verir.
- **Başarı kriteri:** 1–5. adımların tamamı beklendiği gibi sonuçlanır.
- **Kanıt:** `icacls` çıktıları, `Get-NetFirewallRule` / `Get-NetFirewallAddressFilter` çıktıları.
- **Başarısızlıkta:** `setup_service_acls.ps1` çıktısını kaydedin. Kasalar farklı VLAN'daysa `-RemoteAddress` parametresiyle yeniden yapılandırın.

## PAT-11 — Gerçek Android release APK kurulumu
- **Ön koşullar:** Owner B1 tamamlandı. `flutter build apk --release` başarılı.
- **Donanım:** Android cihaz.
- **Adımlar:**
  1. APK'yı `.sha256` dosyasıyla doğrulayıp kurun.
  2. `aapt dump badging` ile imzalayan sertifikayı kontrol edin; debug sertifikası **olmamalı**.
  3. İlk açılış → kurulum sihirbazı → eşleştirme (PAT-03).
  4. Ayarlar → Sistem → Yedekleme'de uygulamanın Google yedeğine dahil olmadığını doğrulayın. İsterseniz `adb shell bmgr` ile kontrol edin.
  5. `http://` bir Hub adresi girmeyi deneyin; release'te reddedilmeli veya bağlanmamalı.
  6. Cihazı yeniden başlatın; token korunmalı (Keystore).
- **Beklenen sonuç:** Kurulum, eşleştirme ve kalıcılık çalışır; cleartext ve otomatik yedek kapalıdır.
- **Başarı kriteri:** Tüm adımlar geçer.
- **Kanıt:** Sertifika parmak izi, ekran görüntüleri, `bmgr` çıktısı.
- **Başarısızlıkta:** APK'yı kaldırmadan tanı raporunu alın.

## PAT-12 — Gerçek TLS sertifikası ile bağlantı ve sertifika rotasyonu
- **Ön koşullar:** Owner B2 tamamlandı.
- **Donanım:** Hub ve eşleştirilmiş bir cihaz.
- **Adımlar:**
  1. *(Eşleştirme öncesi bağımsız çalışabilir)* Tarayıcıda veya Hub sertifika doğrulama aracında `https://<Hub IP>:8945/health` açın. Sertifika zinciri CA'ya gitmeli ve LAN IP SAN'ı bulunmalıdır.
  2. *(PAT-03 sonrası)* Cihazda Tanılama → TLS durumu "Sabitlenmiş" olmalı.
  3. *(PAT-03 sonrası)* Sunucu sertifikasını **aynı CA ile** yenileyin, servisi yeniden başlatın. Cihaz yeniden eşleştirme olmadan bağlanmalı.
  4. *(PAT-03 sonrası)* **Farklı bir CA** ile imzalı sertifika takın. Cihaz `TLS_PIN_MISMATCH` ("Sertifika Uyuşmuyor") göstermeli; IP/SAN uyuşmazlığında ise `TLS_CERT_ERROR` olarak ayrıştırılmalı ve hiçbir durumda `http://` fallback yapılmadan bekleyen işlemler `RETRY` olarak korunmalıdır.
  5. *(PAT-03 sonrası)* Doğru sertifikaya dönün. Bekleyen işlemler gönderilmeli.
- **Beklenen sonuç:** Rotasyon kesintisiz; yabancı sertifika ayrı hata olarak görünür.
- **Başarı kriteri:**
  - 3. adımda kesinti ≤ 1 senkron turu.
  - 4. adımda hiçbir isteğin Hub logunda görünmemesi.
- **Kanıt:** Rozet ekran görüntüleri, Hub logu, Outbox sayıları.
- **Başarısızlıkta:** Sertifikanın SAN alanını kontrol edin (Hub IP'si dahil mi?).

## PAT-13 — Gerçek Google OAuth ve Drive yükleme
- **Ön koşullar:** Owner `C1/C2` tamamlandı ve Windows derlemesi `MMS_GDRIVE_CLIENT_ID` ile yapıldı. *(Android `PAT-13` varyantı için ek olarak Phase 2 `ADR-022` [`google_sign_in`] implementasyonu, `B1` Release keystore SHA-1 kaydı ve `C1/C2` Web/Android OAuth yapılandırması gereklidir.)*
- **Donanım:** Windows kasa, internet bağlantısı, Google hesabı.
- **Adımlar:**
  1. Harici Yedek → **Google Drive'ı Bağla**. Tarayıcıda izin ekranında **yalnızca** `drive.file` izni istenmeli.
  2. Otomatik yedek alın. Drive'da "MARKET MMS Yedekleri" klasöründe `.mmsbak` görünmeli.
  3. Yedeği tekrar tetikleyin; aynı yedek iki kez yüklenmemeli.
  4. Yükleme sırasında interneti kesin. Yerel yedek başarılı sayılmalı ve sonraki turda yükleme tamamlanmalı.
  5. Google hesabından uygulama erişimini iptal edin. `ERR_DRIVE_REAUTH_REQUIRED` gelmeli.
  6. Drive'daki dosyayı indirip USB içe aktarma ile geri yükleyin.
- **Beklenen sonuç:** Yalnızca şifreli dosyalar yüklenir; tekrar yükleme yok; hata durumları doğru.
- **Başarı kriteri:** Drive'daki dosya boyutu ve MD5 değeri yerel dosyayla aynı.
- **Kanıt:** Drive klasörü ekran görüntüsü; `Get-FileHash -Algorithm MD5` çıktısı.
- **Başarısızlıkta:** Tanı raporunu alın. Token değerleri maskelidir; raporu düzenlemeyin.

## PAT-14 — Restore sırasında uygulamanın kapanması (elektrik kesintisi)
- **Ön koşullar:** Test cihazında şifreli yedek ve yedekten sonra yapılmış 2 senkronize olmamış satış var. Hub'dan şifreli yedek alındı.
- **Donanım:** Windows kasa (görev yöneticisi) ve düşük donanımlı Android.
- **Adımlar:**
  1. Geri Yükle'yi başlatın. İlerleme sırasında uygulamayı görev yöneticisinden sonlandırın (Android'de "Zorla durdur").
  2. Uygulamayı yeniden açın. Journal kurtarması restore'u ya tamamlamalı ya da geri almalı; DB açılmalı.
  3. Senkronize olmamış 2 satış hâlâ Outbox'ta olmalı (silinmemeli).
  4. Restore'u kesintisiz tekrarlayın ve **süreyi ölçün**. Bu sürüm koruyucu kopyayı da şifrelediği için ek PBKDF2 süresi beklenir.
  5. Restore sürerken arayüzün donmadığını doğrulayın.
- **Beklenen sonuç:** Veri kaybı yok; DB bozuk değil; Outbox korunur.
- **Başarı kriteri:**
  - `PRAGMA integrity_check` = ok (tanı raporu).
  - Düşük donanımlı Android'de toplam restore süresi kaydedilir. 60 sn'yi aşarsa "kabul edilebilir mi" kararı Owner'ındır.
- **Kanıt:** Ekran kaydı, süre ölçümü, tanı raporu.
- **Başarısızlıkta:** Uygulama veri klasöründeki `*.restore_journal`, `*.swap_bak` ve `*.restore_staging.tmp` dosyalarını **silmeyin**; klasörün kopyasını alıp destekle paylaşın.

## PAT-15 — Gerçek cihazda zamanlanmış yedek (uygulama açık / kapalı)
- **Ön koşullar:** Otomatik yedek 6 saatlik aralıkla açık (`minSdk 24 / Android 7.0+` cihaz).
- **Donanım:** Android cihaz (şarjda) ve Windows kasa.
- **Adımlar:**
  1. Uygulama açıkken 6 saat bekleyin (veya cihaz saatini ileri alın). Yedek alınmalı ve geçmişte görünmeli.
  2. Restore başlatıp hemen ardından zamanlanmış yedeği tetikleyin. Yedek hata **kaydetmeden** atlanmalı (`BackupOperationLock`, 10 sn heartbeat / 60 sn crash kurtarma).
  3. Uygulamayı kapatıp 12 saat bekleyin (veya `PAT-16` altında `adb cmd jobscheduler run` ile Android OS periyodik işini tetikleyin). **Güncel ADR-020 (Release 1.0):** `MmsBackgroundBackupJobService` (`JobScheduler` + headless `FlutterEngine`) uygulama kapalıyken dahi Keystore parolası ve ortak `BackupOperationLock` ile `.mmsbak` yedeğini üretir; `PAT-16` ile fiziksel doğrulama yapılır.

---

## PAT-16 — Android Uygulama Kapalıyken Arka Plan Şifreli Yedekleme ve Yeniden Başlatma Kalıcılığı
- **Ön koşullar:** Android Release APK (`minSdk 24`) kurulu; Otomatik Yedekleme açık (en az 8 karakter parola Keystore'da kayıtlı); cihaz şarjda / kısıtlar uygun.
- **Donanım:** Fiziksel Android cihaz ve USB hata ayıklama (yalnızca `jobscheduler` durumu / log kontrolü için).
- **Adımlar:**
  1. Tanılama → Otomatik Yedekleme ekranında `Arka Plan Zamanlayıcı (Uygulama Kapalıyken)` satırının **ZAMANLANDI** olduğunu doğrulayın.
  2. Uygulamayı **Zorla Durdur** (Recents'tan tamamen kaydırıp kapatın).
  3. Bekleme süresini bekleyin veya geliştirici testinde `adb shell cmd jobscheduler run -f com.marketmms.market_pos 70201` komutunu çalıştırın (`MmsBackgroundBackupChannelHandler.JOB_ID = 70201`).
  4. Uygulama kapalıyken yeni `.mmsbak` dosyasının oluştuğunu ve boyutunun > 0 olduğunu doğrulayın; cihazı yeniden başlatıp açılışta zamanlamanın (`setPersisted(true)`) korunduğunu teyit edin.
- **Beklenen sonuç:** Uygulama kapalıyken alınan yedek yalnızca şifreli `.mmsbak` üretir (`PRAGMA integrity_check = ok` çözülünce); kilit çakışması varsa atlanır; Keystore kilitliyse fail-closed olur (asla şifresiz `.db` bırakılmaz).
- **Kanıt:** Zamanlama UI ekran görüntüsü, dosya listesi/tarih damgası, Keystore hata varsa maskeli tanı raporu.

## PAT-17 — Google Drive Gerçek Hesap ile Yedek Listeleme, Kesintili İndirme ve Kontrollü Geri Yükleme
- **Ön koşullar:** `PAT-13` tamamlanmış ve Drive'da en az 1 şifreli `.mmsbak` yedeği mevcut; cihazda yerel veritabanında henüz Hub'a gitmemiş 1 test satışı var.
- **Donanım:** Windows kasa (veya OAuth bağlantılı istemci) ve internet bağlantısı.
- **Adımlar:**
  1. Tanılama → Harici Yedek → **Drive Yedeklerinden Geri Yükle** butonuna tıklayın; uzak yedek listesinin geldiğini doğrulayın.
  2. İlk denemede bilerek **yanlış parola** girin; sistemin canlı veritabanını duraklatmadan (`ERR_DECRYPTION_FAILED`) hatayı gösterdiğini ve verinin değişmediğini doğrulayın.
  3. Ardından **doğru parolayla** geri yüklemeyi başlatın (`downloadAndRestoreFromGoogleDrive`); süreç sonunda koruyucu `.mmsbak` güvenlik kopyasının üretildiğini, eski durumun geri geldiğini ve bekleyen Outbox satışının korunduğunu teyit edin.
  4. Bağlantıyı Kaldır (`disconnect`) seçildiğinde token iptalinin çalıştığını doğrulayın.
- **Beklenen sonuç:** Yanlış parola veya bozuk indirmede canlı veritabanına dokunulmaz; doğru geri yüklemede Outbox korunur.
- **Kanıt:** Geri yükleme öncesi/sonrası satış listesi, Outbox satırları ve `safety` klasörü dosya listesi.

## PAT-18 — Hub Öncelikli Hibrit + Google Drive Canlı Senkronizasyon ve Hub Geri Dönüş Uzlaştırması
- **Ön koşullar:** Aynı mağaza (`tenant_id`, `store_id`) ve Drive hesabına + aynı `drive_live_sync_secret_v1` sırrına bağlı 2 fiziksel cihaz (ör. Cihaz A Android ve Cihaz B Android/Windows); Cihaz A ve B normalde Hub'a bağlı.
- **Donanım:** Windows Master Hub PC + en az 2 istemci cihaz + internet erişimi.
- **Adımlar:**
  1. Hub açıkken Cihaz A'da 1 satış yapın; Tanılama'da durumun **Hub Birincil** veya **Google Drive Yedek Hat (Hazırda Bekliyor)** olduğunu ve Drive'a canlı zarf yazılmadığını doğrulayın.
  2. Windows Hub servisini durdurun. Her iki cihazda senkronizasyon döngüsünü çalıştırın ve eşik aşıldığında Tanılama'nın **Google Drive Canlı Senkron Aktif (Fallback)** durumuna geçtiğini gözlemleyin.
  3. Hub kapalıyken Cihaz A'da 1 satış ve Cihaz B'de aynı ürün üzerinde farklı fiyat değişikliği yapın; Cihaz A ve B'nin Drive üzerinden şifreli `.mmsenv` zarfını alıp `outbox_operations` satırlarını `PENDING` tuttuğunu ve çakışma uyarısı ürettiğini doğrulayın.
  4. Windows Hub servisini yeniden başlatın; her iki cihazın **Master Hub Döndü — Uzlaştırılıyor...** → **Master Hub ile Uzlaştırıldı (Güncel)** geçişini yaptığını, bekleyen satışların Hub'da birleştiğini ve ürün fiyatının Hub otoritesiyle tekilleştiğini doğrulayın.
- **Beklenen sonuç:** Hub varken 0 Drive sync trafiği; Hub kapalıyken veri kayıpsız/echo-loop'suz aktarım ve non-LWW çakışma bildirimi; Hub dönüşünde temiz reconciliation ve mükerrer satış yok.
- **Kanıt:** Tanılama UI ekran görüntüleri (her geçişte), Hub satış listesi ve her iki cihazın Outbox sayacı (`0 PENDING`).

---

## Durum Özeti

| Test | Durum | Bağımlılık |
|---|---|---|
| PAT-01 … PAT-18 | **BLOCKED** (çalıştırılmadı) | Owner B1, B2, C1, C2, D1, E1; `P-BLOCK-1..3` canlı `PAT-03` & `PAT-12`; Android arka plan iş planlayıcı (`PAT-16`); Google Drive OAuth & Hibrit Sync (`PAT-13`, `PAT-17`, `PAT-18`) |
