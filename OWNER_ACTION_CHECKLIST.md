# MARKET MMS — Owner (Proje Sahibi) İşlem Listesi

*Tarih: 21 Kasım 2026 (Release 1.0 Güncellemesi) · Kaynaklar: [`docs/RELEASE_1_0_FINAL_DELIVERY_REPORT.md`](docs/RELEASE_1_0_FINAL_DELIVERY_REPORT.md), [`docs/PILOT_TECHNICAL_REMEDIATION_REPORT.md`](docs/PILOT_TECHNICAL_REMEDIATION_REPORT.md)*

Bu listede **sizin** karar, gizli anahtar, ortam temizliği veya fiziksel test gerektiren maddeleriniz yer alır. **`P-BLOCK-1..3` (`DEC-REV-1..5`), Android arka plan yedeği (`ADR-020`), Google Drive listeleme/indirme/kontrollü geri yükleme (`Faz C`) ve Google Drive hibrit canlı senkronizasyon (`ADR-021`) teknik olarak uygulanmış ve otomatik testlerle doğrulanmıştır; ancak fiziksel kabul testleri (`PAT-01…18`) henüz çalıştırılmadığı için sistem henüz sahaya / üretime tam hazır ilan edilmemiştir (`TECHNICALLY COMPLETE — PHYSICAL VALIDATION REQUIRED`).**

> **Bu belgede hiçbir gerçek parola, token, sertifika veya özel anahtar yoktur; eklemeyin.**

**Önerilen sıra:**
1. Kararlar (A).
2. Üretim anahtarları ve sertifikalar (B).
3. Temizlik (D).
4. Pilot donanımı ve fiziksel kabul testleri (E).
5. Google Drive (C) en sona kalabilir.

---

## Özet Tablo

| # | Madde | Tür | Engellediği iş | Öncelik |
|---|---|---|---|---|
| A1 | ADR-015…021 kararları ve `DEC-REV-1..5` | **Kapsam Onaylı / Teknik Tamam** | Mimari kayıtlar + `P-BLOCK-1..3`, `ADR-020`, `ADR-021` teknik kodlama tamamlandı (`PAT-01..18` saha onayı bekleniyor) | **Orta** |
| A2 | Değişikliklerin commit edilmesi | Karar | Sürüm takibi (Owner açık onayından sonra) | Yüksek |
| A3 | Kategori/KDV senkronu (ADR-019) | **DEFERRED_POST_PILOT** | Pilotta %20 KDV kısıtlarıyla kabul; pilot sonrası migrasyon | Orta (pilot sonrası) |
| A4 | Discovery TLS protokol kararı (ADR-018 §2.2) & `P-BLOCK-1..3` | **IMPLEMENTED (Otomatik Testli)** | İlk eşleştirmede TLS/QR (`DEC-REV-1..5` kodlandı; `PAT-03`, `PAT-12` bekleniyor) | **Saha Testi (`PAT-03`)** |
| A5 | Android kapalıyken arka plan yedek (`ADR-020`) | **IMPLEMENTED (`JobScheduler`)** | `MmsBackgroundBackupJobService` + headless engine ile harici bağımlılıksız uygulandı (`PAT-16` bekleniyor) | **Saha Testi (`PAT-16`)** |
| A6 | Google Drive Yedek + Hibrit Canlı Senkron (`ADR-021`) | **IMPLEMENTED (Otomatik Testli)** | Drive `listRemoteBackups`, `.part` indirme/restore (`PAT-17`) ve `MMSENV01` hibrit canlı senkron (`PAT-18`) uygulandı; OAuth (`C1/C2`) + `drive_live_sync_secret_v1` bekleniyor | **Orta (`C1/C2`, `PAT-13/17/18`)** |
| A7 | QR görseli paketi | Karar + bağımlılık | Windows ekranında QR görüntüsü | Düşük |
| A8 | Güncelleme paketi imzalama | Karar + sertifika | İmzalı güncelleme | Orta |
| B1 | Android üretim imza anahtarı | Gizli anahtar | Release APK | **Engelleyici** |
| B2 | Hub TLS sertifikaları (CA + sunucu) | Sertifika | Üretim Hub'ı, eşleştirme | **Engelleyici** |
| C1 | Google Cloud projesi | Hesap | Drive yedeği | Düşük |
| C2 | Google OAuth yapılandırması | Hesap | Drive yedeği | Düşük |
| D1 | `MarketMmsSpike01` servisinin kaldırılması | Temizlik | Port/çakışma riski | Orta |
| D2 | Manuel test token'larının iptali/rotasyonu | Güvenlik | Bilinen token ile erişim | **Yüksek** |
| D3 | Şifresiz test DB kopyalarının kaldırılması | Güvenlik | Veri sızıntısı | Yüksek |
| D4 | Eski şifresiz restore koruyucu kopyaları | Güvenlik | Veri sızıntısı | Orta |
| E1 | Pilot ortamı ve donanım | Donanım | Tüm fiziksel kabul testleri | **Engelleyici** |
| E2 | Faz kabulleri | Karar | "Kullanıma hazır" kararı | Son adım |

---

## A. Kararlar

### A1. ADR-015, 016, 017 (ve yeni 018, 019, 020) kararları
- **Neden gerekli?**
  - Bu kararlar kodda uygulandı ve testlerle doğrulandı. Ancak sizin onayınız olmadan `CONFIRMED` sayılmazlar.
  - 018 ve 020'de yalnızca bir kısım uygulandı. 019 yalnızca tasarım halinde.
- **Ne yapmalısınız?** Her ADR için "onaylıyorum", "düzeltilsin" veya "geri alınsın" deyin:

  | ADR | Konu | Kodda / Belgede Durum | Sizden İstenen |
  |---|---|---|---|
  | 015 (+Ek A/B) | Tek `hub_config.json`, `ROOT_CA_CERT_FILE` env fallback temizliği, `tls` katı anahtar denetimi, fail-closed `503` | **CONFIRMED** (kodda uygulandı; fiziksel SCM/ACL **BLOCKED**) | Fiziksel kurulum testi E1 / PAT-08 ile doğrulanacak |
  | 016 (+Ek A/B) | Restore'da Outbox/seq koruması, zamanlanmış/USB/Drive yedek, **`BackupOperationLock` heartbeat + 60 sn kurtarma + Hub kilidi** | **CONFIRMED** (kodda uygulandı; Guide §7 düzeltildi) | Fiziksel USB ve restore süre ölçümü (PAT-07, PAT-14) |
  | 017 | Snapshot endpoint (`CONFIRMED`), **TLS CA/SAN/IP/Hostname/Tarih/MITM sınıflandırması** | **PARTIALLY_CONFIRMED / IN_REVIEW** (uygulandı; PAT-12 **BLOCKED**) | TLS sınıflandırmasını PAT-12 sonrası onaylayın |
  | 018 | Eşleştirilmiş keşifte `https://` zorunluluğu (§2.1) ve UDP Seçenek C (§2.2); `ca_fingerprint` ayrıştırma + **`P-BLOCK-1..3`** | **CONFIRMED** (§2.1 & Seçenek C) | **`P-BLOCK-1..3` protokol bloklayıcıları** için düzeltme onayı verin |
  | 019 | Kategori/KDV senkronu (`SYNC-CAT`) | **DEFERRED_POST_PILOT** (kod değişmedi) | Pilot boyunca 7 geçici %20 KDV kısıtını operasyonel olarak uygulayın |
  | 020 | Android kapalıyken yedek (`workmanager` ertelendi); Keystore hata eşleme | **DEFERRED_POST_PILOT** (hata eşleme uygulandı) | Pilot için "uygulama açıkken yedek" sınırını operasyonel kabul edin |
- **Etkilenen dosyalar:** `docs/decisions/015…020-*.md`, `docs/decisions/README.md`, `docs/PILOT_TECHNICAL_REMEDIATION_REPORT.md`.
- **Güvenlik uyarısı:** ADR-018 incelemesinde tespit edilen **`P-BLOCK-1..3`** çözülmeden gerçek LAN'da ilk TLS+QR eşleştirme akışı tam uçtan uca tamamlanamaz (bkz. A4).
- **Tamamlandığında yapılacak test:** Fiziksel kabul testleri `PAT-01…PAT-15` (şu an tamamı **BLOCKED**).

### A2. Değişikliklerin commit edilmesi
- **Neden gerekli?**
  - Çalışma ağacında birkaç oturumdan birikmiş, henüz commit edilmemiş değişiklikler var. Sayı: yaklaşık 200 dosya.
  - Talimat gereği hiçbir dosya stage, commit veya push edilmedi.
- **Ne yapmalısınız?**
  - `git status` ile değişiklikleri gözden geçirin.
  - Commit'leri mantıksal parçalara bölmeyi değerlendirin. Örnek bölümler: Hub, depolama paketi, uygulama, belgeler.
- **Etkilenen:** Tüm depo.
- **Güvenlik uyarısı:**
  - Commit öncesi `git status --ignored` ile şu dosyaların listede **olmadığını** doğrulayın: `manual_test_env/`, `*.db`, `*.key`, `pepper.dpapi`, `android/key.properties`.
  - `.gitignore` bunları dışlıyor. `manual_test_env/` bu oturumda eklendi.
- **Tamamlandığında yapılacak test:** Temiz bir klonda dört test süitini çalıştırın:
  - `flutter test`
  - `packages/mms_client_storage` → `flutter test`
  - `packages/mms_contracts` → `dart test`
  - Hub → `dart test -j 1`

### A3. Kategori / KDV senkronizasyonu kararı (SYNC-CAT, ADR-019 — **DEFERRED_POST_PILOT**)
- **Karar Durumu:** Owner kararıyla pilot sonrasına **ertelendi**. Şema v3 → v4, `CATEGORY_UPSERT`, `PRODUCT_UPSERT` değişiklikleri ve kısmi KDV senkronizasyonu pilotta uygulanmayacaktır.
- **Pilot İçin Bağlayıcı 7 Geçici %20 KDV Operasyonel Kısıtı:**
  1. Tüm ürünler cihazlar arasında varsayılan **%20 KDV** varsayımıyla yönetilir; çoklu KDV (%0, %1, %10) senkronize edilmez.
  2. Hub `products` tablosunda `vat_rate` ve `category_id` sütunu ile `categories` tablosu yoktur.
  3. Yeni kurulan veya yeniden eşleştirilen her cihaz tüm ürünleri `%20` KDV ve `category_id = null` olarak alır.
  4. Bir cihazda yerel değiştirilen KDV oranı veya kategori diğer cihazlara ve Hub'a taşınmaz.
  5. Satış toplamları (kuruş) doğrudur ancak çoklu KDV mağazada KDV dökümü tutarsız olabilir → resmî mali beyan doğrudan çoklu cihaz KDV raporuna dayandırılmamalıdır.
  6. Restore mevcut cihazda yerel KDV'yi korur; cihaz değişiminde eski yerel KDV geri gelmez.
  7. Pilot sonrası ADR-019 migrasyonu başlatılmadan önce doğrulanmış şifreli `.mmsbak` Hub yedeği alınmalıdır.
- **Pilot Sonrası Uygulama Kapsamı (9 Kalıcı Gereksinim):** Ayrıntılı liste [`docs/decisions/019-category-vat-sync.md`](docs/decisions/019-category-vat-sync.md) §2 içindedir.

### A4. Discovery TLS (ADR-018 **CONFIRMED — Seçenek C**) ve `P-BLOCK-1..3` (`DEC-REV-1..5` Uygulandı)
- **Durum (Release 1.0):** `DEC-REV-1..5` kapsamındaki tüm `P-BLOCK-1..3` düzeltmeleri (`extractCanonicalSingleCertDer`, dar `MmsX509PreValidator`, `ALT-BOOT-2`, crash-safe `ACK_PENDING` + idempotent `/ack`, Windows `GetAdaptersAddresses`+`GetIfEntry2` x64 FFI + `advertise_host`) kodlandı ve otomatik testlerden geçti (`HUB-T01..T09b`, `APP-T01..T18`).
- **Sizden İstenen:** Gerçek donanımda `PAT-03` ve `PAT-12` fiziksel kabul testlerinin yürütülmesi (`DEC-REV-6`).

### A5. Android Uygulama Kapalıyken Zamanlanmış Yedek (`ADR-020` — **IMPLEMENTED (`JobScheduler`)**)
- **Karar & Uygulama Durumu:** Harici pub paketi (`workmanager`) olmadan saf Android SDK `JobScheduler` (`MmsBackgroundBackupJobService`) + headless `FlutterEngine` + paylaşılan `MmsSecureStorageChannelHandler` (`AndroidKeystore`) + `BackgroundBackupWorkerExecutor` uygulandı; `BackupOperationLock` ve üstel geri çekilme (exponential backoff) entegre edildi ve 19 otomatik testle doğrulandı.
- **Sizden İstenen:** Fiziksel Android cihazda `PAT-16` ile uygulama kapalıyken yedekleme + yeniden başlatma kalıcılığının doğrulanması.

### A6. Android Drive SDK kararı
- **Neden gerekli?**
  - Google, Android'de loopback OAuth yönlendirmesini desteklemiyor.
  - Android'den Drive'a yedek göndermek için Google Sign-In SDK'sı gerekiyor.
- **Ne yapmalısınız?**
  - `google_sign_in` paketini onaylayın, ya da
  - Drive yedeğini yalnızca Windows'tan yapmaya karar verin. Mevcut durum budur ve Hub yedeği zaten tüm mağazayı kapsar.
- **Etkilenen dosyalar:** `pubspec.yaml`, Android yapılandırması, `google_drive_connect_service.dart`.
- **Güvenlik uyarısı:** Yeni bağımlılık eklenir. Kapsam yalnızca `drive.file` kalmalıdır.
- **Tamamlandığında yapılacak test:** PAT-13'ün Android varyantı.

### A7. QR görseli bağımlılığı
- **Neden gerekli?**
  - Windows eşleştirme ekranı şu an QR **içeriğini** kopyalanabilir metin olarak veriyor; ekrana QR **resmi** çizmiyor.
  - Android tarafı QR'ı mevcut kamera paketiyle (`mobile_scanner`) okuyabiliyor.
- **Ne yapmalısınız?** İki seçenek var:
  - QR çizmek için bir paket eklenmesini onaylayın (örneğin `qr_flutter`, saf Dart).
  - Ya da mevcut akışla devam edin: metni kopyalayıp başka bir araçla QR'a çevirin, veya Android'de metni yapıştırın.
- **Etkilenen dosyalar:** `pubspec.yaml`, `lib/features/security/presentation/widgets/pairing_approval_panel.dart`.
- **Güvenlik uyarısı:** QR içeriği tek kullanımlık ve süreli bir eşleştirme sırrı içerir. Ekran görüntüsünü paylaşmayın.
- **Tamamlandığında yapılacak test:** PAT-03, adım 4.

### A8. Güncelleme paketi imzalama ve merkezi hata izleme
- **Neden gerekli?**
  - Hub güncellemeleri `SHA256SUMS.txt` ile doğrulanıyor. Başarısız güncellemede önceki sürüme otomatik dönülüyor (bu oturumda eklendi).
  - Ancak kod imzalama yok.
  - Uygulama içi güncelleme denetimi yalnızca bildirim yapıyor. HTTP adres ve eksik SHA-256 artık reddediliyor.
  - Merkezi hata izleme yok. Şu an cihaz başına maskeli tanı raporu dışa aktarılabiliyor.
- **Ne yapmalısınız?** İki konuda karar verin:
  - **Kod imzalama sertifikası:** Ücretli. Windows'ta "bilinmeyen yayıncı" uyarısını kaldırır.
  - **Merkezi hata izleme:** Önerilen seçenek ücretsizdir ve dış servis gerektirmez: cihazların maskeli tanı raporlarını Hub'a göndermesi. Bu yeni bir Hub ucu demektir.
- **Güvenlik uyarısı:**
  - İmzalama anahtarı depoya konmamalı.
  - Dış hata izleme servisleri (Sentry vb.) cihaz verisini dışarı gönderir; KVKK değerlendirmesi gerektirir.
- **Tamamlandığında yapılacak test:** PAT-09 (güncelleme ve geri dönüş).

---

## B. Üretim Anahtarları ve Sertifikalar

### B1. Android üretim imza anahtarı
- **Neden gerekli?**
  - `android/key.properties` olmadan release derlemesi **durur**. Bu 21.11.2026'da doğrulandı: `BUILD FAILED — Release imzalama yapılandırılmadı`.
  - Debug anahtarıyla üretim paketi üretilmez.
- **Ne yapmalısınız?** [`docs/release/ANDROID_RELEASE.md`](docs/release/ANDROID_RELEASE.md) §2'yi izleyin:
  1. `keytool` ile `.jks` dosyasını üretin.
  2. Dosyayı **depo dışında** saklayın. Örnek konum: `C:\MarketMMS-Secrets\`.
  3. `android/key.properties` dosyasını oluşturun.
- **Etkilenen dosyalar:** `android/key.properties` (Git'e girmez), `.jks` dosyası.
- **Güvenlik uyarısı:**
  - Anahtar ve parolalar kaybolursa kurulu uygulamalar **güncellenemez**. Şifreli iki ayrı yedek tutun.
  - Bu dosyaları kimseyle, yapay zekâ araçları dahil, paylaşmayın.
- **Tamamlandığında yapılacak test:**
  - `flutter build apk --release` başarılı olmalı.
  - Birleşik manifestte `usesCleartextTraffic="false"` ve `allowBackup="false"` olmalı.
  - Ardından PAT-11.

### B2. Windows Hub TLS sertifikaları (kök CA + sunucu)
- **Neden gerekli?**
  - Üretim Hub'ı TLS olmadan açılmaz.
  - Bu oturumdan itibaren `tls.ca_cert` (kök CA'nın **genel** sertifikası) da zorunlu. Bu dosya olmadan eşleştirme QR'ı CA parmak izi taşıyamaz ve cihazlar TLS pin kuramaz.
- **Ne yapmalısınız?**
  1. **Hub dışında** güvenli bir bilgisayarda OpenSSL ile şunları üretin:
     - Kök CA: `ca.key` ve `ca.crt`. Öneri: RSA 2048+, uzun ömürlü ve açık X.509 uzantılarıyla (`-addext "basicConstraints=critical,CA:TRUE"` `-addext "keyUsage=critical,keyCertSign,cRLSign"`); **`ca.crt` üzerinde sunucu SAN'ı bulunmamalıdır**.
     - Sunucu sertifikası: `server.key` ve `server.crt`. CA ile imzalanmalı (`keyUsage=digitalSignature,keyEncipherment`, `extendedKeyUsage=serverAuth`). `subjectAltName` alanına Hub'ın LAN IP adres(ler)i ve makine adı yazılmalı.
  2. `server.crt`, `server.key` ve `ca.crt` dosyalarını `%ProgramData%\MarketMMS\certs\` altına koyun.
  3. `ca.key` dosyasını **Hub'a koymayın**. Çevrimdışı ve şifreli saklayın. ACL betiği Hub'da `ca.key` bulursa kurulumu durdurur.
  4. `hub_config.json` → `tls` alanının `cert`, `key` ve `ca_cert` dosyalarını gösterdiğini kontrol edin.
- **Etkilenen dosyalar:** `%ProgramData%\MarketMMS\certs\*`, `config\hub_config.json`.
- **Güvenlik uyarısı:**
  - Sunucu sertifikasını aynı CA ile yenilerseniz cihazlar yeniden eşleştirme gerektirmez (otomatik testle doğrulandı).
  - CA'yı değiştirirseniz tüm cihazlar "Sertifika Uyuşmuyor" gösterir ve yeniden eşleştirilmelidir.
  - Hub'ın IP'si değişirse sunucu sertifikasındaki SAN alanını güncelleyin.
- **Tamamlandığında yapılacak test:** PAT-12, PAT-03.

---

## C. Google Drive (İlk Pilot İçin İsteğe Bağlı / Ertelenebilir)

> [!NOTE]
> Başlangıç pilotu için **Windows Hub zamanlanmış yerel şifreli yedeği + USB aktarımı** yeterlidir; Google Cloud/OAuth yapılandırması (`C1`, `C2`, `PAT-13`) pilotu bloklamaz ve en sona bırakılabilir.

### C1. Google Cloud projesi
- **Neden gerekli?** Drive yedeğinin yazılımı hazır ve testleri sahte Drive ile yapıldı. Gerçek hesapla hiç denenmedi.
- **Ne yapmalısınız?**
  1. Google Cloud Console'da bir proje oluşturun.
  2. **Google Drive API**'yi etkinleştirin.
- **Etkilenen:** Yok (dış hesap).
- **Güvenlik uyarısı:** Projeyi market adına açılmış, iki adımlı doğrulamalı bir hesapta oluşturun.
- **Tamamlandığında yapılacak test:** C2'den sonra PAT-13.

### C2. Google OAuth yapılandırması
- **Ne yapmalısınız?** [`docs/operations/BACKUP_AND_RESTORE_GUIDE.md`](docs/operations/BACKUP_AND_RESTORE_GUIDE.md) §4'ü izleyin:
  1. OAuth izin ekranını yapılandırın. Kapsam **yalnızca** `drive.file` olmalı.
  2. "Masaüstü uygulaması" türünde bir istemci kimliği oluşturun.
  3. Windows derlemesine `--dart-define=MMS_GDRIVE_CLIENT_ID=…` ile verin.
- **Etkilenen:** Derleme komutu. Kimlik depoya yazılmaz.
- **Güvenlik uyarısı:**
  - Geniş kapsam (`drive`) eklemeyin.
  - Masaüstü istemci "secret" değerini depoya yazmayın.
- **Tamamlandığında yapılacak test:** PAT-13. Yükleme, tekrar yüklenmeme ve bağlantı kesilmesi senaryolarını kapsar.

---

## D. Temizlik ve Güvenlik

### D1. `MarketMmsSpike01` spike servisinin kaldırılması
- **Neden gerekli?**
  - Bu makinede **kurulu ve çalışıyor**: Status `Running`, StartType `Automatic` (21.11.2026'da okunarak görüldü).
  - Bu bir test servisi (`MMS_ENV=test_spike`). Üretim servisiyle port veya DB çakışması yaratabilir.
- **Ne yapmalısınız?**
  1. Yönetici PowerShell açın.
  2. `Stop-Service MarketMmsSpike01` komutunu çalıştırın.
  3. `test_spikes\spike_01_backend\service_wrapper\MarketMmsSpike01.exe uninstall` komutunu çalıştırın.
  4. İsterseniz XML ve EXE dosyalarını depodan kaldırın.
- **Etkilenen:** Windows servis kaydı, `service_wrapper/MarketMmsSpike01.*`.
- **Güvenlik uyarısı:** Önce servisin kullandığı DB'de saklanması gereken veri olmadığını kontrol edin.
- **Tamamlandığında yapılacak test:** `Get-Service MarketMmsSpike01` "bulunamadı" demeli. Üretim servisi kurulduktan sonra PAT-08.

### D2. Manuel test token'larının iptali / rotasyonu
- **Neden gerekli?**
  - `manual_test_env/init_test_env.dart` dosyasında bilinen, düz metin test cihaz token'ları var.
  - `manual_test_env/write_scripts.py` dosyasında bir admin secret var.
  - Bu değerler manuel test DB'sinde geçerli.
- **Ne yapmalısınız?**
  - Bu DB ve token'ları **pilotta asla kullanmayın**.
  - Üretim Hub'ını temiz bir DB ile kurun. Kurulum betiği admin secret'ı rastgele üretir. Cihazları yeniden eşleştirin.
  - Manuel test Hub'ı açık kalacaksa, bu token'lara sahip cihazları iptal edin.
- **Etkilenen:** `manual_test_env/` (bu oturumda `.gitignore` kapsamına alındı; hiçbir dosya silinmedi).
- **Güvenlik uyarısı:** Bu dosyaları paylaşmayın ve commit etmeyin.
- **Tamamlandığında yapılacak test:** Bilinen test token'ıyla üretim Hub'ına istek atın. `401` dönmeli.

### D3. Şifresiz test DB kopyalarının güvenli biçimde kaldırılması
- **Neden gerekli?** Aşağıdaki dosyalar şifresiz SQLite ve cihaz token özetleri içerir. Hepsi Git dışında, ama diskte duruyor:
  - `manual_test_env/market_master.db*`
  - `manual_test_env/market_master.db.bak_before_cola_cleanup`
  - Kök dizindeki `spike_master.db`
  - `manual_test_env/pepper.key`. Bu dosya bir **pepper**; DB'deki token özetlerini anlamlı kılan sırdır.
- **Ne yapmalısınız?**
  1. Bu dosyalara ihtiyacınız olup olmadığına karar verin.
  2. Gerekliyse şifreli bir arşive taşıyın.
  3. Gereksizse silin. Örnek: `Remove-Item manual_test_env\market_master.db.bak_before_cola_cleanup -Confirm`.
  
  Silme kararı sizindir; dosyalara dokunulmadı.
- **Etkilenen:** Yalnızca yukarıdaki yerel dosyalar.
- **Güvenlik uyarısı:**
  - Bu dosyalar gerçek satış verisi içeriyorsa, silmeden önce şifreli yedek alın.
  - Silme işlemi **geri alınamaz**.
- **Tamamlandığında yapılacak test:** `git status --ignored` ile dosyaların gittiğini doğrulayın.

### D4. Eski şifresiz restore koruyucu kopyaları
- **Neden gerekli?**
  - 21.11.2026 öncesi yapılan restore'lar koruyucu kopyayı `safety_snapshot_*.db` olarak şifresiz bıraktı.
  - Yeni sürüm bu kopyaları artık şifreli tutuyor, ancak eski dosyalara dokunmadı.
- **Ne yapmalısınız?** [`BACKUP_AND_RESTORE_GUIDE.md`](docs/operations/BACKUP_AND_RESTORE_GUIDE.md) §7'deki prosedürü uygulayın.
- **Etkilenen:** Kasada `backups\safety\*.db`, Hub'da `backups\safety_snapshots\*.db`.
- **Güvenlik uyarısı:** Silmeden önce ihtiyaç olmadığından emin olun.
- **Tamamlandığında yapılacak test:** Bu klasörlerde `.db` kalmamalı.

---

## E. Pilot Ortamı, Fiziksel Testler ve Kabul

### E1. Pilot ortamı ve gerekli donanım
- **Neden gerekli?** Fiziksel kabul testlerinin **hiçbiri** yapılmadı. Liste: [`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`](PHYSICAL_ACCEPTANCE_TEST_PLAN.md), **`PAT-01…PAT-18`**.
- **Gerekli donanım:**
  - **Hub:** Windows 10/11 bilgisayar. Yönetici hesabı ve sabit LAN IP gerekli.
  - **Kasa:** En az bir Windows kasa bilgisayarı ve USB HID barkod okuyucu.
  - **Mobil:** Kameralı en az **iki** Android cihaz. Birleşik Android manifesti ve uygulama yapılandırması en az **minSdk 24 (Android 7.0)** gerektirir; Android 8 veya üzeri önerilir. Biri düşük donanımlı olmalı.
  - **Ağ:** Mağaza Wi-Fi router'ı. "AP/istemci izolasyonu" kapalı olmalı.
  - **Depolama:** En az bir USB bellek (FAT32/NTFS). Disk dolu testi için ayrıca küçük kapasiteli bir USB.
  - **Barkodlu ürünler:** Gerçek EAN-13 ürünler ve bilinmeyen bir barkod.
  - İsteğe bağlı: Google hesabı (C1/C2 tamamlandıysa).
- **Ne yapmalısınız?**
  1. B1 ve B2'yi tamamlayın.
  2. Hub'ı temiz DB ile kurun.
  3. `PAT-01…PAT-18`'i sırayla uygulayın ve her test için kanıtı kaydedin.
- **Güvenlik uyarısı:** Pilotu gerçek satış verisiyle değil, test ürünleriyle başlatın. Restore ve çökme testlerinden önce şifreli yedek alın.

### E2. Faz kabulleri
- **Neden gerekli?** Yol haritasındaki 7 fazın hiçbiri sizin tarafınızdan kabul edilmiş sayılmaz.
- **Ne yapmalısınız?** Fiziksel testler geçtikten sonra her faz için kabul kararı verin. Ardından `docs/MASTER_ROADMAP.md` dosyasındaki durum sütunu güncellenir.
