# Yedekleme ve Geri Yükleme Kılavuzu — MARKET MMS

*Okuyucu: Market sahibi (Owner) ve kurulumu yapan teknik destek. Sürüm: 23 Kasım 2026 (2. tur) (S1–S6 düzeltmeleri: kayıtlı parola zorunluluğu, zamanlayıcı dayanıklılığı, Drive klasör ayrımı, legacy restore koruyucu kopyası). Önceki: 21 Kasım 2026 Release 1.0.*

MARKET MMS'te iki tür veritabanı vardır:

| Nerede | Ne içerir | Kim yedekler |
|---|---|---|
| **Windows Hub** (`market_master.db`) | Tüm mağazanın ana kaydı (ürünler, tüm cihazların satışları, stok) | Hub servisi, otomatik |
| **Her kasa/telefon** (`client_local.db`) | O cihazın yerel kopyası ve Hub'a henüz gönderilmemiş işlemler | Uygulama, otomatik (açılırsa) + elle |

Asıl korunması gereken **Hub yedeğidir**. Cihaz yedekleri, internet/LAN kesikken yapılan ve henüz Hub'a ulaşmamış satışları korur.

---

## 1. Hub Otomatik Yedeği

- Kurulumdan sonra varsayılan olarak **24 saatte bir** alınır. Ayar: `%ProgramData%\MarketMMS\config\hub_config.json` → `backup_schedule` (bkz. [`WINDOWS_HUB_RELEASE.md`](../release/WINDOWS_HUB_RELEASE.md) §4.1).
- Yedekler şifrelidir (AES-256 + HMAC). Son 30 günün tüm yedekleri ve son 12 ayın her ayından bir yedek saklanır; daha eskiler otomatik silinir.
- **Şifreleme anahtarı (23 Kasım 2026, ADR-023 B1.7 / OV-05):** Hub yedekleri artık makineye bağlı `pepper.dpapi` ile **şifrelenmez**; Owner'ın belirlediği en az 12 karakterlik **Portable Recovery Password** kullanılır (Windows Hub ekranı → *Merkezi Hub Yedekleme* → Kurtarma Parolası, ya da loopback `POST /api/v1/backup/recovery-key`). Parola Hub'da yalnızca LocalMachine DPAPI ile korunan `backup_recovery_key.dpapi` kasasında durur; **kağıda yazıp güvenli yerde saklayın** — yeni bir bilgisayarda geri yükleme yalnızca bu parolayla mümkündür, unutulursa yedek açılamaz.
- **Kurtarma parolası tanımlanmadıysa** otomatik yedek alınmaz; durum `ERR_RECOVERY_KEY_NOT_CONFIGURED` hatasıyla `/health` → `backup.overdue = true` olarak görünür. Yeni sürümü kurduktan hemen sonra parolayı tanımlayın.
- Kontrol: Tanılama ekranında Hub durumu; veya Hub bilgisayarında `GET https://127.0.0.1:8945/api/v1/admin/backup/status`.

### 1.1. Merkezi Hub Google Drive Yedeği (`ADR-023`) — 23 Kasım 2026 (2. tur) güncellemesi

- **Yedek hangi parolayla şifrelenir? Her zaman Hub'da KAYITLI Portable Recovery Password ile.** Windows Hub ekranında önce parolayı yazıp **Kurtarma Anahtarını Kaydet**'e basın; **Hub Yedeği Başlat** ayrı bir adımdır.
  - Parola alanında kaydedilmemiş metin varken **Hub Yedeği Başlat** çalışmaz ("kaydedilmemiş metin var" uyarısı). Ya parolayı kaydedin ya da alanı temizleyin.
  - Hub'da kayıtlı parola yoksa manuel yedek başlatılmaz (`ERR_RECOVERY_KEY_REQUIRED`).
  - Uzak OWNER cihazı veya bir betik `POST /api/v1/backup/run` isteğine parola eklerse istek reddedilir (`ERR_RECOVERY_PASSWORD_NOT_ACCEPTED`). Bu sayede hatırlanmayan, kaydedilmemiş bir parolayla Drive yedeği oluşamaz. Başarılı yanıtta `recovery_key_source: HUB_STORED_DPAPI` yazar.
  - Kayıtlı parolayı değiştirirseniz **yeni** yedekler yeni parolayla şifrelenir; daha önce alınmış yedekler eski parolayla açılır. Her iki parolayı da saklayın.
- **Zamanlayıcı davranışı:** Hub her dakika zamanlamayı kontrol eder. O sırada başka bir yedek/geri yükleme/temizlik işlemi kilidi tutuyorsa (ör. eski 24 saatlik yerel yedek, manuel yedek, restore) tur hata vermeden **bir sonraki dakikaya ertelenir**. Kurtarma parolası kasası okunamıyor gibi gerçek bir hata olursa Hub servisi **çalışmaya devam eder**, hata bir kez günlüğe yazılır ve `GET /api/v1/backup/status` yanıtında `scheduler_last_error` alanında görünür; sorun giderilince sonraki turda otomatik düzelir.
- **Drive klasörü:** Merkezi Hub yedekleri `MARKET MMS Yedekleri/Hub` alt klasörüne yüklenir (bkz. §4 Drive klasörleri).

## 2. Kasa / Telefon Otomatik Yedeği

1. **Tanılama → Şifreli Yedekleme ve Kurtarma → Otomatik Yedekleme**.
2. Sıklığı seçin (6 / 12 / 24 saat) ve en az 8 karakterlik bir **yedek parolası** girin → **Otomatik Yedeklemeyi Aç**. İlk yedek hemen alınır.
3. Parola cihazın güvenli deposunda (Windows DPAPI / Android Keystore) saklanır; ekrana veya dosyaya yazılmaz. **Parolayı ayrıca not edin** — geri yükleme için gereklidir; kaybolursa yedek açılamaz.
4. Ekranda son başarılı yedek zamanı, son hata ve son 5 denemenin geçmişi görünür. Kırmızı uyarı çıkarsa §5'e bakın.
5. **Android Arka Plan Zamanlayıcısı (`ADR-020` — Release 1.0):** Android 7.0+ (`minSdk 24`) cihazlarda otomatik yedekleme artık **uygulama kapalıyken de** Android sistem `JobScheduler` (`MmsBackgroundBackupJobService`) + arka plan `FlutterEngine` üzerinden çalışır (`setPersisted(true)` ile cihaz yeniden başlatmada korunur). Aynı ortak dosya kilidini (`BackupOperationLock`) kullanır; Keystore erişilemezse asla şifresiz yedek almaz (**fail-closed**). İlk zamanlandığında ve Tanılama ekranında sonraki çalışma / son arka plan sonucu görünür (`PAT-16` ile sahada doğrulanmalıdır).
6. Aynı anda yalnızca bir yedek veya geri yükleme çalışır (hem istemci hem Hub ortak dosya kilidi kullanır). Geri yükleme sürerken zamanı gelen otomatik yedek hata vermeden atlanır ve bir sonraki kontrolde alınır.
7. Android'in kendi "Google yedeklemesi" bu uygulama için **kapalıdır**: yerel veritabanı şifresiz olarak Google hesabına veya yeni telefona kopyalanmaz (aynı cihaz kimliğinin iki telefonda çalışması senkronizasyonu bozardı). Telefon değişiminde cihaz Hub'a **yeniden eşleştirilir**.

## 3. USB Belleğe Yedek (Windows)

1. USB belleği takın. **Harici Yedek → USB / klasör yolu** alanına sürücü yolunu yazın (ör. `E:\MMS_Yedek`; klasör önceden oluşturulmuş olmalı).
2. **Son Yedeği Aktar**. Kopya yazıldıktan sonra geri okunup bayt bayt doğrulanır; ancak doğrulama başarılıysa dosya adıyla kaydedilir.
3. "Disk dolu" veya "hedef erişilemiyor" hatası alırsanız yarım dosya bırakılmaz; alanı boşaltıp veya USB'yi yeniden takıp tekrar deneyin.
4. Yedeği USB'den geri almak için dosya yolunu **İçe aktarılacak .mmsbak dosyası** alanına yazıp **USB'den İçe Aktar**. Eksik/yarım kopyalanmış veya başka cihaza/şubeye ait dosyalar reddedilir.

## 4. Google Drive (Şifreli Uzak Yedekleme, Geri Yükleme ve Canlı Senkron Fallback)

> Drive **şifreli uzak yedek (.mmsbak)** ve **`ADR-021` hibrit canlı senkronizasyon fallback (`.mmsenv`)** sağlar; Windows Master Hub her koşulda birincil otoritedir.

**Owner'ın bir kez yapması gerekenler (henüz yapılmadı — BLOCKED `C1`/`C2`):**
1. Google Cloud Console'da bir proje oluşturun; **Google Drive API**'yi etkinleştirin.
2. OAuth izin ekranını yapılandırın; kapsam olarak yalnızca `https://www.googleapis.com/auth/drive.file` ekleyin.
3. **OAuth istemci kimliği** oluşturun (`MMS_GDRIVE_CLIENT_ID`, opsiyonel `MMS_GDRIVE_CLIENT_SECRET`).
4. Derlemeye `--dart-define=MMS_GDRIVE_CLIENT_ID=<id> --dart-define=MMS_GDRIVE_CLIENT_SECRET=<secret>` ile verin (depoya yazmayın).

**Drive klasörleri (23 Kasım 2026 (2. tur), S5 / `IMP-13`):**

| Klasör | İçerik | Yazan |
|---|---|---|
| `MARKET MMS Yedekleri/Hub` | Merkezi Hub yedekleri (`ADR-023`, `MMSBAK02`, `hub_backup_<id>.mmsbak`, `mms_backup_source = HUB_CENTRAL`) | Windows Master Hub servisi |
| `MARKET MMS Yedekleri` (kök) | Eski istemci (kasa/telefon) şifreli yedekleri (`ADR-016`) | Windows/Android istemci uygulaması |
| `MARKET MMS LiveSync` | `ADR-021` canlı senkron zarfları (`.mmsenv`) — yedek değildir | İstemciler (Hub erişilemezken) |

- Bu güncellemeden önce Hub yedekleri kök klasöre yükleniyordu. **Eski Hub dosyaları taşınmaz veya silinmez**; Hub kendi kayıtlarındaki dosya kimliğiyle bunları saklama politikasına göre yönetmeye ve geri yüklemeye devam eder. İlk yeni Hub yedeğinde `Hub` alt klasörü otomatik oluşturulur.
- Kasa/telefon **Drive Yedeklerinden Geri Yükle** listesi Hub yedeklerini göstermez (merkezi veritabanı bir kasaya geri yüklenemez).

**Uzak Yedek Yükleme ve Kontrollü Geri Yükleme (`Faz C`):**
- Her başarılı otomatik yedekten sonra henüz yüklenmemiş son 3 şifreli `.mmsbak` dosyası `"MARKET MMS Yedekleri"` klasörüne yüklenir; Drive'a ulaşılamazsa yerel yedek etkilenmez.
- Geri yüklemek için **Tanılama → Harici Yedek → Drive Yedeklerinden Geri Yükle**: liste indirilir, seçilen `.mmsbak` dosyası `.part` devam ettirmeli olarak indirilir, boyut + SHA-256 + parola + HMAC-SHA256 + cihaz/şube + `PRAGMA integrity_check` canlı DB durdurulmadan **önce** doğrulanır. Doğrulama geçerse ortak `BackupOperationLock` + koruyucu kopya + Outbox korumasıyla geri yüklenir (`PAT-17`). Bağlantıyı Kaldır (`disconnect`) OAuth token'ını iptal edip temizler.

**Hibrit Canlı Senkronizasyon Fallback (`ADR-021`):**
- Normalde yalnızca Master Hub kullanılır (Drive trafiği sıfırdır). Hub doğrulanmış biçimde ulaşılamaz olduğunda `MMSENV01` şifreli zarfları (`drive_live_sync_secret_v1`, yedek parolasından ayrı) kullanılır; TLS pin/sertifika veya `401/403` hatalarında **ASLA** Drive'a geçilmez. Hub döndüğünde veriler kontrollü olarak uzlaştırılır (`PAT-18`).

## 5. Geri Yükleme

1. Tanılama → yedek listesinden **Geri Yükle** → parola.
2. Uygulama önce senkronizasyonu durdurur, yedeği çözer ve bütünlüğünü doğrular; bu adımlarda hata olursa **canlı veriye dokunulmaz**.
3. Mevcut veritabanının koruyucu kopyası alınır, sonra yedek atomik olarak yerine konur. Herhangi bir hata olursa önceki duruma otomatik dönülür. Elektrik kesilirse bir sonraki açılışta işlem otomatik tamamlanır veya geri alınır.
4. **Hub'a henüz gitmemiş satışlar silinmez** ve sıra numaraları korunur. Bu satışlar Hub'a gönderildikten sonra cihazın satış geçmişine Hub'dan geri gelir.
5. Başka cihaza veya başka şubeye ait yedek geri yüklenemez.
6. **Koruyucu (güvenlik) kopya:** Geri yükleme başarıyla bitince, geri yüklemeden ÖNCEKİ verinin koruyucu kopyası **şifreli** `.mmsbak` olarak saklanır (kasada uygulama veri klasöründeki `backups\safety`, Hub'da `backups\safety_snapshots`). Parolası, geri yüklediğiniz yedeğin parolasıdır. Şifreleme herhangi bir nedenle yapılamazsa geri yükleme yine tamamlanır, koruyucu kopya şifresiz `.db` olarak kalır ve uyarı gösterilir — bu durumda §7'deki temizlik adımını uygulayın.

## 6. Hata Kodları

| Kod | Anlamı | Ne yapılmalı |
|---|---|---|
| `ERR_DISK_FULL` | Hedefte yer yok | Disk/USB'de yer açın |
| `ERR_TARGET_UNAVAILABLE` | USB çıkarılmış / klasör yok | USB'yi takın, yolu kontrol edin |
| `ERR_SCHEDULE_PASSWORD_MISSING` | Otomatik yedek parolası güvenli depoda yok | Otomatik yedeklemeyi kapatıp parolayla yeniden açın |
| `ERR_INCOMPLETE_BACKUP` | Dosya yarım kopyalanmış | Yedeği kaynaktan yeniden kopyalayın |
| `ERR_STORE_ID_MISMATCH` / `ERR_DEVICE_ID_MISMATCH` | Başka şube/cihaz yedeği | Doğru yedeği seçin |
| `ERR_DECRYPTION_FAILED` | Parola yanlış veya dosya değiştirilmiş | Doğru parolayı girin |
| `ERR_DRIVE_REAUTH_REQUIRED` | Google yetkisi iptal/süresi dolmuş | Drive'ı yeniden bağlayın |
| `ERR_DRIVE_UNAVAILABLE` | Drive'a ulaşılamıyor | İnterneti kontrol edin; otomatik tekrar denenir |
| `ERR_BACKUP_OPERATION_BUSY` | Başka bir yedek veya geri yükleme sürüyor (istemci veya Hub) | İşlemin bitmesini bekleyip tekrar deneyin. Aktif işlem sürerken kilit nabız (heartbeat) ile korunur; çöken bir işlemden kalan kilit ise **60 saniye** sonra otomatik kurtarılır |
| `ERR_DRIVE_NOT_ENCRYPTED_PACKAGE` | Drive'a şifreli olmayan veya yanlış dosya gönderilmek istendi | Hiçbir şey yüklenmedi; destekle iletişime geçin |
| `ERR_RECOVERY_KEY_REQUIRED` | Merkezi Hub yedeği için Hub'da kayıtlı kurtarma parolası yok | Windows Hub ekranında parolayı kaydedin, sonra yedeği başlatın |
| `ERR_RECOVERY_PASSWORD_NOT_ACCEPTED` | `POST /api/v1/backup/run` isteğine parola eklendi | Parolayı istekte göndermeyin; önce `POST /api/v1/backup/recovery-key` ile kaydedin |
| `ERR_UNSAVED_RECOVERY_PASSWORD` | Windows ekranında parola alanında kaydedilmemiş metin varken yedek istendi | Önce **Kurtarma Anahtarını Kaydet** veya alanı temizleyin |

## 7. Koruyucu Kopyaların Saklanması ve Kurtarma Prosedürü

**Eski şifresiz kopyalar:** 21.11.2026 öncesi yapılan geri yüklemeler koruyucu kopyayı şifresiz `safety_snapshot_*.db` olarak bırakmıştır. Bu dosyalar otomatik silinmez veya dönüştürülmez (veri kaybı riski). Hub kopyaları cihaz token özetleri dahil tüm mağaza verisini içerir.

1. Koruyucu kopyaya ihtiyacınız olmadığından emin olun (son geri yüklemeden sonra satışlar normal ve Hub senkronu sağlıklıysa gerekmez).
2. Gerekebileceğini düşünüyorsanız önce yeni bir **şifreli** yedek alın ve USB'ye aktarın (§3).
3. Ardından `safety_snapshot_*.db` dosyalarını güvenli biçimde silin (Hub'da yönetici PowerShell: `Remove-Item "$env:ProgramData\MarketMMS\backups\safety_snapshots\*.db" -Confirm`). Bu işlem Owner kararıdır ([`OWNER_ACTION_CHECKLIST.md`](../../OWNER_ACTION_CHECKLIST.md)).

**Şifreli koruyucu kopyadan geri dönmek** (geri yüklemenin yanlış yapıldığı anlaşılırsa):
- *Kasa (Windows):* `safety` klasöründeki `.mmsbak` dosyasını **Harici Yedek → USB'den İçe Aktar** ile alın, ardından listeden **Geri Yükle** → ilk geri yüklemede kullandığınız parola.
- *Hub:* `.mmsbak` dosyasını `backups` klasörüne kopyalayın, `POST https://127.0.0.1:8945/api/v1/admin/restore` (admin secret ile). İlk yedek `/api/v1/admin/backup` üzerinden özel `backup_password` ile alındıysa koruyucu kopya da o parolayla şifrelenir ve geri dönerken aynı `backup_password` verilmelidir; özel parola verilmeden (veya zamanlanmış Hub yedeğiyle) alındıysa Hub'ın **Portable Recovery Password**'ü kullanılır (`backup_password` göndermeyin).
- *Hub — 23 Kasım 2026 öncesi alınmış eski yedekler:* Eski sürüm parolasız yedekleri makineye bağlı pepper ile şifreliyordu. Bu dosyalar yalnızca **aynı Hub bilgisayarında** ve isteğe açıkça `"legacy_machine_key": true` eklenerek geri yüklenebilir; başka bilgisayarda açılamaz. Parolasız yeni bir yedek almadan önce kurtarma parolasını tanımlayın (`ERR_RECOVERY_KEY_NOT_CONFIGURED` → `412`; 12 karakterden kısa `backup_password` → `400 ERR_WEAK_RECOVERY_PASSWORD`).
  - **Önemli — bu restore'un koruyucu kopyası da makineye bağlıdır (S4, otomatik testle doğrulandı: `LP-05`):** `legacy_machine_key: true` ile yapılan geri yüklemede, geri yükleme ÖNCESİ verinin koruyucu kopyası (`backups\safety_snapshots\*.mmsbak`) Portable Recovery Password ile **değil**, aynı makine pepper'ı ile şifrelenir. Bu kopya **yalnızca aynı Hub bilgisayarında** açılabilir; yeni bir bilgisayara taşınırsa açılamaz ve Portable Recovery Password ile çözülemez.
  - Bu koruyucu kopyadan geri dönmek gerekirse aynı Hub'da dosyayı `backups` klasörüne kopyalayıp `POST /api/v1/admin/restore` isteğine yine `"legacy_machine_key": true` ekleyin.
  - Bilgisayar değişimi planlanıyorsa: eski yedeği aynı makinede `legacy_machine_key` ile geri yükledikten sonra **hemen yeni bir Hub yedeği alın** (Portable Recovery Password ile şifrelenir) ve bu yeni yedeği taşıyın. Eski pepper'lı dosyalar ve bu koruyucu kopya yeni bilgisayarda kullanılamaz.
  - Fiziksel `LocalService` altında bu senaryo saha testinde henüz doğrulanmadı (`BK-PAT` kapsamı, **BLOCKED**); davranış otomatik test ortamında doğrulanmıştır.
- Her iki durumda da Hub'a henüz gitmemiş işlemler korunur ve yeni bir koruyucu kopya alınır.
