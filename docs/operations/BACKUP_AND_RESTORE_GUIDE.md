# Yedekleme ve Geri Yükleme Kılavuzu — MARKET MMS

*Okuyucu: Market sahibi (Owner) ve kurulumu yapan teknik destek. Sürüm: 21 Kasım 2026 (3. oturum güncellemesi: §5.6, §6, §7).*

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
- Kontrol: Tanılama ekranında Hub durumu; veya Hub bilgisayarında `GET https://127.0.0.1:8945/api/v1/admin/backup/status`.

## 2. Kasa / Telefon Otomatik Yedeği

1. **Tanılama → Şifreli Yedekleme ve Kurtarma → Otomatik Yedekleme**.
2. Sıklığı seçin (6 / 12 / 24 saat) ve en az 8 karakterlik bir **yedek parolası** girin → **Otomatik Yedeklemeyi Aç**. İlk yedek hemen alınır.
3. Parola cihazın güvenli deposunda (Windows DPAPI / Android Keystore) saklanır; ekrana veya dosyaya yazılmaz. **Parolayı ayrıca not edin** — geri yükleme için gereklidir; kaybolursa yedek açılamaz.
4. Ekranda son başarılı yedek zamanı, son hata ve son 5 denemenin geçmişi görünür. Kırmızı uyarı çıkarsa §5'e bakın.
5. Android'de otomatik yedek **yalnızca uygulama açıkken** çalışır (ADR-020 pilot sonrasına ertelendi); uygulama kapalıyken yedek alınmaz, uygulama açıldığında gecikmiş yedek hemen başlatılır.
6. Aynı anda yalnızca bir yedek veya geri yükleme çalışır (hem istemci hem Hub ortak dosya kilidi kullanır). Geri yükleme sürerken zamanı gelen otomatik yedek hata vermeden atlanır ve bir sonraki kontrolde alınır.
7. Android'in kendi "Google yedeklemesi" bu uygulama için **kapalıdır**: yerel veritabanı şifresiz olarak Google hesabına veya yeni telefona kopyalanmaz (aynı cihaz kimliğinin iki telefonda çalışması senkronizasyonu bozardı). Telefon değişiminde cihaz Hub'a **yeniden eşleştirilir**.

## 3. USB Belleğe Yedek (Windows)

1. USB belleği takın. **Harici Yedek → USB / klasör yolu** alanına sürücü yolunu yazın (ör. `E:\MMS_Yedek`; klasör önceden oluşturulmuş olmalı).
2. **Son Yedeği Aktar**. Kopya yazıldıktan sonra geri okunup bayt bayt doğrulanır; ancak doğrulama başarılıysa dosya adıyla kaydedilir.
3. "Disk dolu" veya "hedef erişilemiyor" hatası alırsanız yarım dosya bırakılmaz; alanı boşaltıp veya USB'yi yeniden takıp tekrar deneyin.
4. Yedeği USB'den geri almak için dosya yolunu **İçe aktarılacak .mmsbak dosyası** alanına yazıp **USB'den İçe Aktar**. Eksik/yarım kopyalanmış veya başka cihaza/şubeye ait dosyalar reddedilir.

## 4. Google Drive (Şifreli Uzak Yedek)

> Drive **canlı senkronizasyon değildir**; yalnızca zaten şifreli yedek dosyaları yüklenir.

**Owner'ın bir kez yapması gerekenler (henüz yapılmadı — BLOCKED):**
1. Google Cloud Console'da bir proje oluşturun; **Google Drive API**'yi etkinleştirin.
2. OAuth izin ekranını yapılandırın; kapsam olarak yalnızca `https://www.googleapis.com/auth/drive.file` ekleyin.
3. **OAuth istemci kimliği → Uygulama türü: Masaüstü uygulaması** oluşturun.
4. İstemci kimliğini Windows derlemesine verin: `flutter build windows --release --dart-define=MMS_GDRIVE_CLIENT_ID=<id> --dart-define=MMS_GDRIVE_CLIENT_SECRET=<secret>` (masaüstü istemci "secret"ı Google'ın tanımıyla gizli sayılmaz ama depoya yazılmamalıdır).

**Sonrasında:** Tanılama → Harici Yedek → **Google Drive'ı Bağla** → tarayıcıda hesabı onaylayın. Her başarılı otomatik yedekten sonra henüz yüklenmemiş son 3 yedek "MARKET MMS Yedekleri" klasörüne yüklenir; aynı yedek iki kez yüklenmez; Drive'a ulaşılamazsa yerel yedek etkilenmez ve yükleme bir sonraki turda tekrar denenir.

Android'den Drive bağlantısı şu an desteklenmiyor (Owner kararı bekliyor: Google Sign-In paketi).

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

## 7. Koruyucu Kopyaların Saklanması ve Kurtarma Prosedürü

**Eski şifresiz kopyalar:** 21.11.2026 öncesi yapılan geri yüklemeler koruyucu kopyayı şifresiz `safety_snapshot_*.db` olarak bırakmıştır. Bu dosyalar otomatik silinmez veya dönüştürülmez (veri kaybı riski). Hub kopyaları cihaz token özetleri dahil tüm mağaza verisini içerir.

1. Koruyucu kopyaya ihtiyacınız olmadığından emin olun (son geri yüklemeden sonra satışlar normal ve Hub senkronu sağlıklıysa gerekmez).
2. Gerekebileceğini düşünüyorsanız önce yeni bir **şifreli** yedek alın ve USB'ye aktarın (§3).
3. Ardından `safety_snapshot_*.db` dosyalarını güvenli biçimde silin (Hub'da yönetici PowerShell: `Remove-Item "$env:ProgramData\MarketMMS\backups\safety_snapshots\*.db" -Confirm`). Bu işlem Owner kararıdır ([`OWNER_ACTION_CHECKLIST.md`](../../OWNER_ACTION_CHECKLIST.md)).

**Şifreli koruyucu kopyadan geri dönmek** (geri yüklemenin yanlış yapıldığı anlaşılırsa):
- *Kasa (Windows):* `safety` klasöründeki `.mmsbak` dosyasını **Harici Yedek → USB'den İçe Aktar** ile alın, ardından listeden **Geri Yükle** → ilk geri yüklemede kullandığınız parola.
- *Hub:* `.mmsbak` dosyasını `backups` klasörüne kopyalayın, `POST https://127.0.0.1:8945/api/v1/admin/restore` (admin secret ile). İlk yedek `/api/v1/admin/backup` üzerinden özel `backup_password` ile alındıysa koruyucu kopya da o parolayla şifrelenir ve geri dönerken aynı `backup_password` verilmelidir; özel parola verilmeden (veya zamanlanmış Hub yedeğiyle) alındıysa Hub'ın DPAPI pepper'ı kullanılır.
- Her iki durumda da Hub'a henüz gitmemiş işlemler korunur ve yeni bir koruyucu kopya alınır.
