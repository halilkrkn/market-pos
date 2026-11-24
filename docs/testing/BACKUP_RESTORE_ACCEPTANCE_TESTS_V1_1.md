# Backup & Restore Acceptance Tests v1.1 — MARKET MMS

**Doküman Kodu:** `BACKUP_RESTORE_ACCEPTANCE_TESTS_V1_1.md`  
**Belge Sürümü:** v1.1 (Kanonik Doğrulama ve Saha Kabul Planı — Owner `OV-01…05` Uyumlu)  
**Tarih:** 22 Kasım 2026  
**Durum:** **ACTIVE v1.1** — `BK-001…BK-032` Faz B-1…B-5 boyunca koşturulur; **`BK-PAT-01…BK-PAT-18`** saha kabulüne kadar **`BLOCKED`** durumundadır.  
**Ana Karar Kaydı:** [`ADR-023 — Hub-Centric Google Drive Backup & Restore`](../decisions/023-hub-centric-google-drive-backup-restore.md)  
**Eşlik Eden Belgeler:**  
- [`GOOGLE_DRIVE_BACKUP_ARCHITECTURE_V1_1.md`](../architecture/GOOGLE_DRIVE_BACKUP_ARCHITECTURE_V1_1.md)  
- [`AUTOMATED_BACKUP_SCHEDULING_SPEC_V1_1.md`](../architecture/AUTOMATED_BACKUP_SCHEDULING_SPEC_V1_1.md)  
- Ayrı Korunan Hat A / Genel Saha Planı: [`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`](../../PHYSICAL_ACCEPTANCE_TEST_PLAN.md) (`PAT-01…PAT-18` — **değiştirilmez ve yeniden kullanılmaz**)

---

## 1. Amaç ve Kapsam

Bu belge, **Çalışma Hattı B — Google Drive Backup & Restore** mimarisinin (**v1.1**) gerçek market pilotu öncesinde eksiksiz doğrulanması için **32 Otomatik Kabul Testi (`BK-001…BK-032`)** ile **18 Fiziksel Kabul Testini (`BK-PAT-01…BK-PAT-18`)** tanımlar.

> [!IMPORTANT]
> **Bağlayıcı Denetim Beyanı:**
> 1. **Mock/Fake Sınırı:** Otomatik testlerde kullanılan sahte HTTP istemcileri, sahte clock veya bellek içi mock nesneler **gerçek Google Drive API, gerçek Google Cloud OAuth 2.0, Windows Service Control Manager (`MarketMMSService` / `LocalService` DPAPI/ACL) veya gerçek fiziksel Android cihaz testlerinin yerine ASLA geçemez**.
> 2. **Kimlik Ayrımı:** Mevcut [`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`](../../PHYSICAL_ACCEPTANCE_TEST_PLAN.md) içindeki **`PAT-01…PAT-18`** kimlikleri (`PAT-13`, `PAT-16`, `PAT-18` dahil) **KESİNLİKLE değiştirilmez ve yeniden kullanılmaz**. Hat B fiziksel testleri yalnızca **`BK-PAT-01…BK-PAT-18`** kimlik uzayını kullanır.
> 3. **Dürüst Raporlama:** *(23 Kasım 2026 notu: Aşağıdaki cümleler 22 Kasım salt-okunur denetiminin tarihsel kaydıdır. Güncel gerçek test sonuçları için [`FINAL_PILOT_READINESS_REPORT.md`](../FINAL_PILOT_READINESS_REPORT.md) esastır.)* 22 Kasım 2026 tarihli bu salt-okunur denetimde hiçbir test çalıştırılmamıştır. Eski raporlardaki test sayıları (`774` / `806` geçer) bu denetimde yeniden doğrulanmamıştır. v1.1 mimarisi henüz kodlanmadığından yeni yeteneklere ait testler `FAIL (Kod Eksik / Hatalı)` veya temel motor testleri `NOT RUN` olarak işaretlenmiştir.

---

## 2. Terimler ve Tanımlar

| Terim | Açıklama |
|---|---|
| **`PASS`** | Repository kod kanıtı eksiksiz VE gerçek otomatik/fiziksel test çıktısıyla doğrulanmış. |
| **`FAIL`** | Repository incelemesinde doğrulanmış hata veya eksik implementasyon saptanmış. |
| **`BLOCKED`** | Harici bağımlılık, kimlik bilgisi (`C1/C2`), ikinci Windows PC, fiziksel Android veya Windows SCM kurulumu nedeniyle doğrulanamıyor. |
| **`NOT RUN`** | İlgili kod/test temeli mevcut ancak bu denetim sırasında test çalıştırılmadı. |
| **`NOT APPLICABLE`** | Mevcut test kapsamı veya aşama için uygulanabilir değil. |
| **`TEST_ONLY` Drive Klasörü** | Fiziksel retention/temizlik testlerinin (`BK-PAT-10/11`) gerçek mağaza yedeklerine zarar vermeden yürütülmesi için oluşturulan izole test hesabı/klasörü. |
| **Gerçek FFI SQLite** | `AGENTS.md` §8 gereği SQLite WAL eşzamanlılığı, kilit ve crash recovery testlerinde in-memory mock yerine kullanılan gerçek yerel C SQLite sürücüsü. |

---

## 3. Gereksinimler ve Test İzolasyonu Kuralları

1. **Sistem Saati Değiştirilmez:** Fiziksel kabul testlerinde (`BK-PAT-*`) Windows veya Android cihazın sistem saati kesinlikle ileri/geri alınmaz; zamanlama testleri pencere gözlemi, yapılandırılabilir pencere veya kontrollü sunucu başlat/durdur senaryolarıyla yürütülür.
2. **Gerçek Kullanıcı Yedekleri Silinmez:** Fiziksel retention ve silme testleri (`BK-PAT-10`, `BK-PAT-11`) **yalnızca izole `TEST_ONLY` Google Drive klasörü/test veritabanı** üzerinde yapılır; gerçek market verisi veya kullanıcı yedekleri asla silinmez.
3. **`MarketMmsSpike01` Korunması:** Mevcut `MarketMmsSpike01` servisine Owner'ın `D1` temizlik adımı olmadan testlerde dokunulmaz.
4. **Sır Gizliliği:** Test kanıt dosyalarında token, `refresh_token`, `pepper`, `admin_secret`, `server.key` veya Recovery Password açık metin olarak ekran görüntüsü/log içine basılamaz.

---

## 4. Mimari / Teknik Tasarım (Kabul Testi Matrisi)

### 4.1. Otomatik Kabul Testleri (`BK-001…BK-032`)

> **Durum Notu:** Mevcut kodda yalnızca `MMSBAK01` temel kripto/motoru (`backup_crypto.dart`, `database_backup_engine.dart`) vardır; bu temel testler bu salt-okunur denetimde çalıştırılmadığı için `NOT RUN` (bazı alt özellikleri v1.1 için eksik/uyumsuz olduğundan `FAIL`) durumundadır.

#### `BK-001` — `MMSBAK02` Şifreleme ve Bütünlük Doğrulama
- **Test ID:** `BK-001`
- **Amaç:** Hub merkezi SQLite snapshot'ının `MMSBAK02` (min 12 karakterli Portable Recovery Password, `PBKDF2-HMAC-SHA256` 600k `KEK`, rastgele `DEK`, `package:cryptography` `AES-256-GCM` akışlı AEAD) ile şifrelenip geri çözülebildiğini ve `< 12` karakter parolanın reddedildiğini doğrulamak.
- **Ön koşullar:** Gerçek FFI SQLite test DB (`market_master.db`) ve geçerli Portable Recovery Password.
- **Test adımları:** (1) DB üzerinde satış/ürün oluştur. (2) `VACUUM INTO` + `MMSBAK02` paket üret. (3) Magic `MMSBAK02`, `format_version=2`, `key_version>=1`, `backup_id` alanlarını ve `DEK` sarma üstbilgisini kontrol et. (4) Doğru parolayla çöz ve SHA-256 + `PRAGMA integrity_check` çalıştır.
- **Beklenen sonuç:** Paket başarıyla şifrelenir, çözülür, `PRAGMA integrity_check = ok` döner ve açık metin DB içindeki tüm veriler birebir eşleşir.
- **Kanıt türü:** Otomatik birim/entegrasyon testi çıktısı (`dart test`), hex/başlık doğrulama.
- **Test ortamı:** Windows/Dart test runner + gerçek FFI SQLite.
- **Durum:** **`FAIL`** *(v1.1 `MMSBAK02` DEK/KEK formatı henüz implemente edilmedi; yalnızca `MMSBAK01` mevcut)*.

#### `BK-002` — Yanlış Portable Recovery Password ve Canlı DB Koruması
- **Test ID:** `BK-002`
- **Amaç:** Yanlış kurtarma parolasıyla geri yükleme denemesinde HMAC doğrulamasının fail-closed reddettiğini ve canlı DB'ye dokunulmadığını doğrulamak.
- **Ön koşullar:** Geçerli `MMSBAK02` / `MMSBAK01` paketi ve aktif satış içeren canlı FFI SQLite DB.
- **Test adımları:** (1) Canlı DB durumunu ve hash'ini kaydet. (2) Yanlış parolayla Hub restore çağır. (3) Hata kodunu ve canlı DB'nin duraklatılmadığını/değişmediğini kontrol et.
- **Beklenen sonuç:** `ERR_DECRYPTION_FAILED` döner; HMAC tek bit dahi yanlışsa çözme başlatılmaz; canlı DB hash'i ve kayıtları %100 aynı kalır.
- **Kanıt türü:** Otomatik test logu, DB öncesi/sonrası checksum kanıtı.
- **Test ortamı:** Dart test runner + gerçek FFI SQLite.
- **Durum:** **`NOT RUN`** *(Temel HMAC reddi `s5a4_backup_restore_test.dart` içinde mevcut ancak çalıştırılmadı; `MMSBAK02` uyarlaması eksik)*.

#### `BK-003` — Portable Recovery Password (Makine Bağımsız Kurtarma)
- **Test ID:** `BK-003`
- **Amaç:** Zamanlanmış Hub yedeğinin `pepper.dpapi` olmadan başka bir `PepperManager` örneğiyle açılabildiğini doğrulamak.
- **Ön koşullar:** Hub zamanlanmış yedek motoru ve iki ayrı simüle makine dizini (`MachineA` ve `MachineB` — farklı `pepper.dpapi`).
- **Test adımları:** (1) `MachineA` Hub zamanlanmış yedeğini al (`backup_password` vermeden). (2) Oluşan `.mmsbak` dosyasını yalnızca Portable Recovery Password ile `MachineB`'de (`MachineA` `pepper.dpapi` olmadan) açmayı dene.
- **Beklenen sonuç:** Yedek `MachineA`'nın `pepper.dpapi`'sine bağımlı olmadan `MachineB`'de tamamen geri yüklenir (`server.dart:698` kusuru giderilmiş olmalıdır).
- **Kanıt türü:** Otomatik entegrasyon testi çıktısı.
- **Test ortamı:** Dart test runner + iki izole geçici klasör + gerçek FFI SQLite.
- **Durum:** **`FAIL`** *(Mevcut kod `server.dart:698,3774` nedeniyle zamanlanmış yedekte `pepperManager.pepper` kullanıyor)*.

#### `BK-004` — Eski Format (`MMSBAK01`) Geriye Dönük Uyumluluk
- **Test ID:** `BK-004`
- **Amaç:** v1.0 döneminde `MMSBAK01` ile alınmış yedeğin v1.1 restore motoru tarafından geri yüklenebildiğini doğrulamak.
- **Ön koşullar:** `MMSBAK01` fikstürü/paketi ve v1.1 `BackupCryptoService`.
- **Test adımları:** (1) `MMSBAK01` header'lı yedeği v1.1 restore hattına ver. (2) Doğru parolayla çöz ve FFI SQLite staging'e yaz. (3) `PRAGMA integrity_check` ve tablo sorgusu yap.
- **Beklenen sonuç:** Eski format otomatik tanınır, sorunsuz geri yüklenir; hata verilmez.
- **Kanıt türü:** Otomatik geriye dönük uyumluluk testi.
- **Test ortamı:** Dart test runner + gerçek FFI SQLite.
- **Durum:** **`NOT RUN`** *(`MMSBAK01` okuma mevcut, v1.1 ikili seçici eklendikten sonra regresyonu koşulacak)*.

#### `BK-005` — Cross-Device vs Farklı Tenant/Store Reddi
- **Test ID:** `BK-005`
- **Amaç:** Aynı `tenant_id`/`store_id` yeni Hub PC'ye restore kabul edilirken farklı mağaza/cihaz türü (`mobileLocal` → `centralMaster`) yedeklerinin reddedildiğini doğrulamak.
- **Ön koşullar:** Farklı `tenant_id`, farklı `store_id` ve `mobileLocal` tipinde 3 örnek paket.
- **Test adımları:** Her üç paketi Hub restore ucuna gönder.
- **Beklenen sonuç:** Sırasıyla `ERR_TENANT_ID_MISMATCH`, `ERR_STORE_ID_MISMATCH` ve `ERR_DATABASE_TYPE_MISMATCH` döner; canlı DB korunur.
- **Kanıt türü:** Otomatik test çıktısı.
- **Test ortamı:** Dart test runner.
- **Durum:** **`NOT RUN`** *(DatabaseType/Tenant/Store kontrolleri `database_backup_engine.dart:412-438`'de mevcut)*.

#### `BK-006` — Yerel Şifreleme Başarısı vs Google Drive Tamamlama Ayrımı (`afterSuccess` Kaldırımı)
- **Test ID:** `BK-006`
- **Amaç:** Drive upload başarısız olduğunda durumun asla `COMPLETED_UPLOADED` / `success: true` raporlanmadığını doğrulamak.
- **Ön koşullar:** Mock/Fake Drive sunucusu HTTP `503` veya ağ hatası döndürecek şekilde ayarlanmış Hub orkestratörü.
- **Test adımları:** (1) Zamanlanmış/manuel yedek tetikle. (2) Snapshot ve şifrelemenin bittiğini, upload'un `503` aldığını gözlemle. (3) State store ve `/api/v1/backup/status` yanıtını oku.
- **Beklenen sonuç:** Durum `RETRY_PENDING` (OAuth yoksa `LOCAL_ONLY_PENDING_UPLOAD`) olur; `lastSuccessAt` güncellenmez, `COMPLETED_UPLOADED` görünmez.
- **Kanıt türü:** Otomatik durum makinesi ve API JSON doğrulaması.
- **Test ortamı:** Dart test runner + sahte HTTP sunucu + gerçek FFI SQLite.
- **Durum:** **`FAIL`** *(Mevcut `scheduled_backup.dart:377-391` ve `backup_providers.dart:112-129` `afterSuccess` hatasını yutup `success: true` işliyor)*.

#### `BK-007` — 12 Durumlu Backup State Machine Geçiş Bütünlüğü
- **Test ID:** `BK-007`
- **Amaç:** Tüm 12 durum (`PENDING`..`SUPERSEDED`) arasında yalnızca geçerli geçişlerin mümkün olduğunu ve her geçişin atomik kaydedildiğini doğrulamak.
- **Ön koşullar:** State machine birim test takımı.
- **Test adımları:** Geçerli tam akış, geçici hata → retry, auth hatası → `LOCAL_ONLY_PENDING_UPLOAD`, cancel, superseded ve geçersiz geçiş denemelerini test et.
- **Beklenen sonuç:** Geçersiz geçişler reddedilir; tüm 12 enum durumu kapsanır.
- **Kanıt türü:** Otomatik birim testi.
- **Test ortamı:** Dart test runner.
- **Durum:** **`FAIL`** *(12 durumlu makine henüz kodda yok)*.

#### `BK-008` — İlk Etkinleştirmede Hemen Başlangıç Yedeği (`INITIAL_ENABLE`)
- **Test ID:** `BK-008`
- **Amaç:** Otomatik yedekleme kapalıyken açıldığında 00.00'ı beklemeden `trigger_reason = INITIAL_ENABLE` yedeği alındığını doğrulamak.
- **Ön koşullar:** Kontrol edilebilir saat (`clock = 2026-11-23 14:20` yerel), Drive mock 200 OK.
- **Test adımları:** (1) `PATCH /api/v1/backup/settings` ile `enabled = true` yap. (2) Hemen tetiklenen işin `trigger_reason` ve `next_scheduled_at` alanlarını incele.
- **Beklenen sonuç:** `INITIAL_ENABLE` anında çalışır ve `COMPLETED_UPLOADED` olur; sonraki çalışma `2026-11-24 00:00` yerel saat olur.
- **Kanıt türü:** Otomatik zamanlama testi.
- **Test ortamı:** Dart test runner + sahte clock + gerçek FFI SQLite.
- **Durum:** **`FAIL`** *(v1.1 `INITIAL_ENABLE` trigger'ı yok)*.

#### `BK-009` — Yerel `00.00` Zamanlama, OS Toleransı ve `CATCH_UP` Davranışı
- **Test ID:** `BK-009`
- **Amaç:** `00:00`–`00:15` penceresinde `SCHEDULED_DAILY`, ertesi sabah açılışta `CATCH_UP`, aynı günde çift çalışmama kuralını doğrulamak.
- **Ön koşullar:** Sahte yerel saat kontrolü (`clock`).
- **Test adımları:** (1) `00:07`'de tick → `SCHEDULED_DAILY` çalışır. (2) `00:12`'de ikinci tick → ikinci yedek açılmaz. (3) Ertesi gün `00:00`'da servis kapalı, `09:15`'te servis açılır → `CATCH_UP` çalışır. (4) Saat 1 saat geri alınsa bile bugünkü ikinci iş açılmaz.
- **Beklenen sonuç:** Yalnızca gün başına bir tamamlanmış günlük yedek üretilir; gecikmiş açılış `CATCH_UP` tetikler.
- **Kanıt türü:** Otomatik deterministik clock testi.
- **Test ortamı:** Dart test runner.
- **Durum:** **`FAIL`** *(Mevcut `BackupSchedulePolicy` rolling 24s kullanıyor)*.

#### `BK-010` — Retry Backoff Çizelgesi (`5, 10, 20, 40, 80, 160` dk → Gün Sonu Sabit `160` dk)
- **Test ID:** `BK-010`
- **Amaç:** Ardışık geçici hatalarda backoff adımlarının tam dakika dizisini izlediğini ve 6. denemeden sonra yerel `23:59:59`'a kadar 160 dk sabit kaldığını doğrulamak.
- **Ön koşullar:** Sahte saat + sahte HTTP `503` yanıtı.
- **Test adımları:** `00:00`'dan başlayarak 9 ardışık geçici hata simüle et ve her `next_retry_at` değerini kaydet.
- **Beklenen sonuç:** Sırasıyla `+5, +10, +20, +40, +80, +160, +160, +160` dk planlanır; gün sınırını aşmaz.
- **Kanıt türü:** Otomatik zamanlama birim testi.
- **Test ortamı:** Dart test runner.
- **Durum:** **`FAIL`** *(Mevcut `failureRetryDelay` sabit 30 dk)*.

#### `BK-011` — Kalıcı Hata ve HTTP 403 Kota vs Auth Ayrımı
- **Test ID:** `BK-011`
- **Amaç:** `403 storageQuotaExceeded` hatasının `ERR_DRIVE_QUOTA_EXCEEDED` dönüp token'ı koruduğunu; `401 invalid_grant` veya kalıcı hatanın ise otomatik retry'ı durdurup kullanıcı müdahalesi istediğini doğrulamak.
- **Ön koşullar:** İki ayrı mock HTTP yanıtı (Google Drive JSON quota `reason: storageQuotaExceeded` vs `403 insufficientPermissions` vs `401 invalid_grant`).
- **Test adımları:** Her hata yanıtını uploader'a ver, error code, `refresh_token` varlığı ve scheduler `next_retry_at` durumunu incele.
- **Beklenen sonuç:** Kota `403`'te token silinmez ve `RETRY_PENDING` olur; Auth hatasında `LOCAL_ONLY_PENDING_UPLOAD` / `REAUTH_REQUIRED` ve retry durur (`google_drive_backup.dart:544-548` hatası giderilir).
- **Kanıt türü:** Otomatik hata sınıflandırma testi.
- **Test ortamı:** Dart test runner + mock HTTP.
- **Durum:** **`FAIL`** *(Mevcut kod tüm `403`'leri `ERR_DRIVE_REAUTH_REQUIRED` yapıyor)*.

#### `BK-012` — 4 MB Chunked Resumable Upload & `HTTP 308` Offset Yönetimi
- **Test ID:** `BK-012`
- **Amaç:** Örn. 10 MB `.mmsbak` paketinin 4 MB (`4.194.304` B) parçalara bölünerek (`0..4194303`, `4194304..8388607`, `8388608..end`) `Content-Range` ile yüklendiğini ve `HTTP 308 Range` yanıtıyla offset tutulduğunu doğrulamak.
- **Ön koşullar:** 10 MB sentetik şifreli paket + stateful mock resumable upload sunucusu.
- **Test adımları:** Yüklemeyi çalıştır; 2. parçadan sonra ağ kesintisi simüle et; yeniden başlat ve giden HTTP başlıklarını incele.
- **Beklenen sonuç:** 1. parça tekrar gönderilmez, `Content-Range` `4194304` offset'inden devam eder, son parça 200 OK ve `VERIFYING` ile biter.
- **Kanıt türü:** Otomatik chunked upload testi.
- **Test ortamı:** Dart test runner + local mock HTTP server.
- **Durum:** **`FAIL`** *(Mevcut uploader tek seferde RAM PUT yapıyor)*.

#### `BK-013` — Resumable Session Expiry (`404`/`410`) Kurtarması ve Idempotency
- **Test ID:** `BK-013`
- **Amaç:** Upload ortasında session URI `404`/`410` döndürdüğünde aynı `backup_id` ile önce Drive'da arama yapılıp bulunmazsa yeni session açıldığını ve duplicate dosya oluşmadığını doğrulamak.
- **Ön koşullar:** Mock Drive sunucusu (Durum A: dosya Drive'da tamamlanmış; Durum B: dosya yok).
- **Test adımları:** Her iki durumda `PUT` çağrısına `410 Gone` döndür.
- **Beklenen sonuç:** Durum A'da mevcut `drive_file_id` bulunup `VERIFYING` → `COMPLETED_UPLOADED` geçilir; Durum B'de yeni session açılır ve tek dosya yaratılır.
- **Kanıt türü:** Otomatik mock sunucu testi.
- **Test ortamı:** Dart test runner.
- **Durum:** **`FAIL`** *(Kalıcı session ve 404/410 kurtarması mevcut değil)*.

#### `BK-014` — Gün Değişimi (`SUPERSEDED`) ve Eski Paketin Doğrulama Öncesi Korunması
- **Test ID:** `BK-014`
- **Amaç:** Gün `D-1`'den kalan `RETRY_PENDING` işinin gün `D` yedeği başladığında **hemen silinmediğini**, yalnızca `D` `COMPLETED_UPLOADED` olunca `SUPERSEDED` edildiğini doğrulamak.
- **Ön koşullar:** `D-1` şifreli `.mmsbak` ve session URI'si diskte mevcut; saat `00:01` gün `D` başlar ve ilk `D` upload'u `503` ile başarısız olur, ikinci deneme başarılı olur.
- **Test adımları:** (1) `D` upload'u `503` aldığında `D-1` dosya ve state varlığını kontrol et. (2) `D` başarılı olunca `D-1` durumunu kontrol et.
- **Beklenen sonuç:** `503` anında `D-1` dosyası ve oturumu hâlâ mevcut ve okunabilirdir; `D` doğrulandığında `D-1` `SUPERSEDED` olur.
- **Kanıt türü:** Otomatik gün geçişi entegrasyon testi.
- **Test ortamı:** Dart test runner + gerçek FFI SQLite.
- **Durum:** **`FAIL`** *(Henüz implemente edilmedi)*.

#### `BK-015` — Aşamalı Crash Recovery & Gereksiz PBKDF2 Atlaması
- **Test ID:** `BK-015`
- **Amaç:** `ENCRYPTED` / `UPLOADING` aşamasında süreç çöktükten sonra açılışta PBKDF2/AES şifrelemesi tekrarlanmadan aynı `backup_id` ile kalıcı offset'ten devam edildiğini doğrulamak.
- **Ön koşullar:** Sayaçlı KDF enstrümantasyonu (`kdfInvocationCount`) + kalıcı state store.
- **Test adımları:** (1) Backup başlat; `ENCRYPTED` sonrası `UPLOADING` %40'ta simüle edilmiş çökme tetikle (`kdfInvocationCount == 1`). (2) Yeni orkestratör örneğiyle startup reconcile çalıştır.
- **Beklenen sonuç:** Şifreli paket SHA-256 ile doğrulanır, **`kdfInvocationCount` `1` olarak kalır**, aynı `backup_id` upload'u tamamlanır.
- **Kanıt türü:** Otomatik sayaçlı crash recovery testi.
- **Test ortamı:** Dart test runner + gerçek FFI SQLite.
- **Durum:** **`FAIL`** *(Monolitik `createBackup` ayrıştırılmadı)*.

#### `BK-016` — Sahiplik Doğrulamalı Temp Snapshot Temizliği & Atomik State Reconcile
- **Test ID:** `BK-016`
- **Amaç:** Açılış uzlaştırmasında yalnızca sahipsiz/tamamlanmış işlere ait `.snap.db` dosyalarının silindiğini ve aktif bir işin snapshot'ına dokunulmadığını doğrulamak.
- **Ön koşullar:** Diskte 2 adet `.snap.db` (biri `COMPLETED_UPLOADED` yetimi, biri aktif kilitli `backup_id`).
- **Test adımları:** Startup reconcile çalıştır ve hangi dosyaların silindiğini denetle.
- **Beklenen sonuç:** Yetim dosya silinir, aktif sahipli `.snap.db` korunur; bozuk `state.json` varsa `.corrupt_*` karantinaya alınır.
- **Kanıt türü:** Otomatik dosya sistemi reconcile testi.
- **Test ortamı:** Dart test runner.
- **Durum:** **`FAIL`** *(Temp snapshot sahiplik uzlaştırması yok)*.

#### `BK-017` — Disk Alanı Yetersizliği (`ERR_DISK_FULL`) ve Sıfır Yarım Dosya
- **Test ID:** `BK-017`
- **Amaç:** Boş alan `< 2.5 × (DB+WAL)` iken veya yazım sırasında disk dolduğunda `ERR_DISK_FULL` üretildiğini ve yarım `.snap.db` / `.mmsbak` kalmadığını doğrulamak.
- **Ön koşullar:** Enjekte edilebilir disk alan ölçer + disk-full I/O simülasyonu.
- **Test adımları:** Hem ön kontrolde yetersiz alan hem `.tmp` yazımında `ENOSPC` simüle et.
- **Beklenen sonuç:** Her iki durumda `ERR_DISK_FULL` döner; geride bozuk yedek veya geçici dosya kalmaz.
- **Kanıt türü:** Otomatik test çıktısı.
- **Test ortamı:** Dart test runner + gerçek FFI SQLite.
- **Durum:** **`FAIL`** *(Ön disk alan kontrolü Hub/Engine'de yok)*.

#### `BK-018` — Drive vs Local Retention Ayrımı & Takvim Ayı Arşivi
- **Test ID:** `BK-018`
- **Amaç:** 30 takvim günü + 12 takvim ayı kuralının Drive üzerinde doğru çalıştığını, yerel disk önbelleğinin Drive arşivini silmediğini doğrulamak.
- **Ön koşullar:** 45 günlük ve 15 aylık sentetik Drive dosya listesi (`COMPLETED_UPLOADED`) + yerel disk dosyaları.
- **Test adımları:** Hem Drive retention planlayıcısını hem yerel önbellek temizleyicisini çalıştır.
- **Beklenen sonuç:** Son 30 gün tamamı ve 2..12. aylardan ay başına 1 geçerli arşiv Drive'da korunur; 13+ ay silinir; yerel önbellek Drive'ı bozmaz (`monthly * 30` gün sapması düzeltilir).
- **Kanıt türü:** Otomatik birim testi.
- **Test ortamı:** Dart test runner.
- **Durum:** **`FAIL`** *(Mevcut `backup_retention_policy.dart` yalnızca yerel disk + `*30` gün kullanıyor)*.

#### `BK-019` — Son Geçerli Yedeğin Korunması (*Last-Valid-Backup Invariant*)
- **Test ID:** `BK-019`
- **Amaç:** Tüm yedekler 12 aydan (ör. 18 aydan) eski olsa dahi sistemdeki en son geçerli `COMPLETED_UPLOADED` yedeğin ASLA silinmediğini doğrulamak.
- **Ön koşullar:** Tamamı 14–20 aylık 5 adet `COMPLETED_UPLOADED` yedek ve 1 yeni `FAILED` kayıt.
- **Test adımları:** Retention pruning çalıştır.
- **Beklenen sonuç:** İlk 4 eski yedek temizlenir, en yeni **1 geçerli `COMPLETED_UPLOADED` yedek kesinlikle korunur**; `FAILED` kayıt asla son geçerli yedek sayılmaz.
- **Kanıt türü:** Otomatik sınır durum testi.
- **Test ortamı:** Dart test runner.
- **Durum:** **`FAIL`** *(Mevcut `planPruning` satır 74-76 hepsini `toPrune`'a atıyor)*.

#### `BK-020` — Google Drive `VERIFYING` Reddi (`size` / `md5` Uyuşmazlığı)
- **Test ID:** `BK-020`
- **Amaç:** Drive'dan dönen metadata `size` veya `md5Checksum` yerel `.mmsbak` ile uyuşmazsa uzak bozuk dosyanın silinip `ERR_DRIVE_VERIFY_FAILED` → `RETRY_PENDING` geçildiğini doğrulamak.
- **Ön koşullar:** Son parça `200 OK` içinde farklı MD5 döndüren mock sunucu.
- **Test adımları:** Upload çalıştır ve sunucuya gelen `DELETE` isteği + job durumunu denetle.
- **Beklenen sonuç:** Bozuk uzak dosya silinir, iş `COMPLETED_UPLOADED` olmaz, `RETRY_PENDING` olarak planlanır.
- **Kanıt türü:** Otomatik mock HTTP doğrulama testi.
- **Test ortamı:** Dart test runner.
- **Durum:** **`NOT RUN`** *(Doğrulama ve silme mantığı `google_drive_backup.dart:516-524`'de temel olarak var, chunked v1.1 akışında test edilecek)*.

#### `BK-021` — Windows UI PKCE → Hub Loopback Handoff & ACL Depolama
- **Test ID:** `BK-021`
- **Amaç:** Windows UI'nın aldığı PKCE `code` + `code_verifier`'ı Hub `POST /api/v1/backup/oauth/connect` ucuna aktardığını, Hub'ın token takasını kendi yapıp `refresh_token`'ı yalnız Hub DPAPI/güvenli kasasına yazdığını doğrulamak.
- **Ön koşullar:** Mock Google Token Endpoint + test Hub sunucusu.
- **Test adımları:** PKCE devri yap; UI tarafında `refresh_token` diske yazılmadığını ve Hub kasa dosyasının oluştuğunu doğrula.
- **Beklenen sonuç:** UI'da `refresh_token` kalıntısı sıfır; Hub sonraki Drive çağrısında kendi sakladığı token'ı yenileyebilir.
- **Kanıt türü:** Otomatik entegrasyon testi.
- **Test ortamı:** Dart/Flutter test runner.
- **Durum:** **`FAIL`** *(Hub OAuth handoff uçları henüz yok)*.

#### `BK-022` — Eski Android Yerel Yedek Akışı İzolasyonu (`B1.12`)
- **Test ID:** `BK-022`
- **Amaç:** Hub-centric v1.1 modülleri eklendiğinde Android yerel `.mmsbak` dosyalarının silinmediğini ve Android lokal yedeklerinin Hub Drive klasörüne merkezi yedek gibi gönderilmediğini doğrulamak.
- **Ön koşullar:** Android yerel test dizininde 2 adet eski `.mmsbak` dosyası + v1.1 Hub yedek UI'ı.
- **Test adımları:** Uygulama açılışı, Hub backup durumu sorgusu ve eski yerel liste okumasını çalıştır.
- **Beklenen sonuç:** Eski `.mmsbak` dosyaları %100 korunur; Hub yedek geçmişiyle karışmaz.
- **Kanıt türü:** Otomatik regresyon testi.
- **Test ortamı:** Flutter test runner.
- **Durum:** **`FAIL`** *(UI ayrımı henüz yapılmadı)*.

#### `BK-023` — Restore Öncesi Safety Snapshot Şifreleme & Otomatik Rollback
- **Test ID:** `BK-023`
- **Amaç:** Restore swap aşamasında hata/integrite bozukluğu oluşursa `.swap_bak` veya şifreli *Safety Snapshot*'tan canlı DB'ye otomatik dönüldüğünü ve başarılı restore sonrasında safety kopyanın şifreli kaldığını doğrulamak.
- **Ön koşullar:** Gerçek FFI SQLite canlı DB + bozulmuş post-swap senaryosu.
- **Test adımları:** Başarılı restore ve enjekte edilmiş post-swap arızalı restore çalıştır.
- **Beklenen sonuç:** Başarılıda şifreli `safety_snapshot_*.mmsbak` üretilir; hatalıda canlı DB önceki haline kayıpsız döner.
- **Kanıt türü:** Otomatik entegrasyon testi.
- **Test ortamı:** Dart test runner + gerçek FFI SQLite.
- **Durum:** **`NOT RUN`** *(Temel mekanizma `restore_safety_snapshot_encryption_test.dart`'ta var; `MMSBAK02` uyumu kontrol edilecek)*.

#### `BK-024` — Restore Sonrası Yeni PC `pepper.dpapi` Değişimi & Toplu Cihaz Geçersizleştirme
- **Test ID:** `BK-024`
- **Amaç:** Yeni bir Windows PC'de yeni `pepper.dpapi` altında Hub veritabanı restore edildiğinde eski `devices` satırlarının aktif token ile kabul edilmediğini ve `HUB_RESTORE_PEPPER_ROTATION` işaretlemesiyle `restore_epoch` artığını doğrulamak.
- **Ön koşullar:** PC-1'de eşleştirilmiş Android cihaz token'ı + PC-1 Hub yedeği; PC-2'de taze `PepperManager`.
- **Test adımları:** (1) PC-1 yedeğini PC-2'ye restore et. (2) Eski token'la `/api/v1/sales` veya `/health` dışı uç çağır. (3) `devices` ve `device_audit_logs` tablolarını incele.
- **Beklenen sonuç:** Eski token `401`/`403` alır (sessiz auth açığı olmaz); tüm eski cihazlar re-pairing bekler duruma geçirilir ve `restore_epoch` artar.
- **Kanıt türü:** Otomatik çoklu-Hub entegrasyon testi.
- **Test ortamı:** Dart test runner + gerçek FFI SQLite.
- **Durum:** **`FAIL`** *(Hub restore sonrası otomatik cihaz invalidation / `restore_epoch` mekanizması yok)*.

#### `BK-025` — Restore Sonrası İstemci Re-pairing & Outbox / `client_seq` Uzlaştırması
- **Test ID:** `BK-025`
- **Amaç:** Hub 1 saat önceki yedeğe döndükten ve cihaz re-pairing yapıldıktan sonra, cihazın yedeğe girmemiş bekleyen satışlarını (ve Hub'da zaten işlenmiş ACK bekleyen satışları) mükerrer kayıt veya veri kaybı olmadan uzlaştırdığını doğrulamak.
- **Ön koşullar:** İstemcide 1 `SYNCED` (Hub'da kayıp), 1 `PENDING` satış; Hub yedeği restore edilmiş ve cihaz yeniden eşleştirilmiş.
- **Test adımları:** (1) İstemci re-pairing'in yerel `local_sales` / `outbox_operations` (`SYNCED` + `PENDING`) kayıtlarını silmediğini kontrol et. (2) `GET /api/v1/sync/device-state` (`restore_epoch`) + `POST /api/v1/sync/receipts` + kayıp `SYNCED` ops atomik re-queue + FIFO sync akışını çalıştır. (3) Eksik yerel yük durumunda fail-closed davrandığını ve tam geçmişte Hub toplam satış sayısı ile kuruş toplamlarının birebir tuttuğunu doğrula.
- **Beklenen sonuç:** Sıfır satış kaybı, sıfır mükerrer satış, `ERR_CLIENT_SEQ_GAP` çıkmadan temiz uzlaştırma (veya yerel geçmiş eksikse fail-closed hata, asla sahte başarı yok).
- **Kanıt türü:** Otomatik uçtan uca sync + restore testi.
- **Test ortamı:** Dart test runner + gerçek Hub & Client FFI SQLite.
- **Durum:** Faz B-4'te `OV-03` kapsamında doğrulanacaktır.

#### `BK-026` — Android Backup Yönetim UI & Hub Backup API Uyumu
- **Test ID:** `BK-026`
- **Amaç:** Android yönetim ekranının Hub `GET /api/v1/backup/status`, `GET /api/v1/backup/history`, `POST /api/v1/backup/trigger`, `PATCH /api/v1/backup/settings` uçlarını çağırıp Hub durumunu doğru yansıttığını, ancak Google OAuth bağlama butonunu göstermediğini doğrulamak.
- **Ön koşullar:** Widget test harness + mock Hub API + `MmsUiProfile.mobile()`.
- **Test adımları:** Ekranı `OWNER` ve `CASHIER` modlarında render et, ayar güncelle, manuel tetikle.
- **Beklenen sonuç:** Hub state doğru gösterilir; Windows OAuth yönlendirme bilgisi vardır; yerel DB Drive'a gönderilmez.
- **Kanıt türü:** Flutter widget + controller testi.
- **Test ortamı:** Flutter test runner.
- **Durum:** **`FAIL`** *(Mevcut widget'lar yalnızca yerel `ClientBackupService`'e bağlı)*.

#### `BK-027` — Android İstemci Backup UI `CASHIER` Yetki Sınırı Görünümü
- **Test ID:** `BK-027`
- **Amaç:** Cihaz rolü `CASHIER` iken yönetim UI mutasyonlarının kilitlendiğini ve sunucuya yetkisiz çağrı yapılsa dahi `403` mesajının düzgün Türkçe gösterildiğini doğrulamak.
- **Ön koşullar:** `CASHIER` cihaz bağlamı + widget testi.
- **Test adımları:** Hub ayar/restore butonlarını kontrol et; simüle `403 ERR_FORBIDDEN_ROLE` yanıtını UI'da test et.
- **Beklenen sonuç:** Ham exception/SQL mesajı gösterilmez, anlaşılır yetki uyarısı görünür.
- **Kanıt türü:** Flutter widget testi.
- **Test ortamı:** Flutter test runner.
- **Durum:** **`FAIL`** *(Rol bazlı Hub backup UI henüz yok)*.

#### `BK-028` — Çevrimdışı Hub Modunda Satışların Backup Kesintilerinden Etkilenmemesi
- **Test ID:** `BK-028`
- **Amaç:** Hub'da `VACUUM INTO` snapshot veya `MMSBAK02` şifreleme sürerken eşzamanlı POS `SALE_CREATE` isteklerinin `503` veya lock timeout almadan tamamlandığını doğrulamak.
- **Ön koşullar:** Gerçek FFI SQLite DB üzerinde çalışan `SpikeServer` + 20 eşzamanlı satış yükü.
- **Test adımları:** Arka planda Hub backup başlat, aynı anda `POST /api/v1/sales` serisi gönder.
- **Beklenen sonuç:** Tüm satışlar %100 `201 COMMITTED`, WAL tutarlılığı korunur, `SQLITE_BUSY` kırılması olmaz.
- **Kanıt türü:** Otomatik eşzamanlılık testi.
- **Test ortamı:** Dart test runner + gerçek FFI SQLite.
- **Durum:** **`NOT RUN`** *(Benzer eşzamanlılık `s5a4_central_restore_lifecycle_test.dart`'ta var; `MMSBAK02` & Drive akışı ile yeniden doğrulama gerekir)*.

#### `BK-029` — Drive İndirme Bozulması (`.part` Kurtarma & SHA-256 Reddi)
- **Test ID:** `BK-029`
- **Amaç:** Drive'dan restore için `.part` indirme sırasında bağlantı kesilip devam ettirildiğinde Range ile kaldığı yerden indiğini, hash bozulmuşsa `.part` dosyasının silindiğini doğrulamak.
- **Ön koşullar:** Stateful Range destekli mock Drive sunucusu.
- **Test adımları:** %50'de indirmeyi kes → devam ettir; ayrıca 1 byte bozuk içerikle SHA-256 uyumsuzluğu test et.
- **Beklenen sonuç:** Kesintisiz devam başarır; bozuk paket canlı DB'ye dokunmadan silinir.
- **Kanıt türü:** Otomatik test çıktısı.
- **Test ortamı:** Dart test runner.
- **Durum:** **`NOT RUN`** *(Range `.part` indirme `google_drive_backup.dart:628+` içinde mevcut, v1.1 ile yeniden koşulacak)*.

#### `BK-030` — Single-Flight Backup/Restore Çakışması *(Zorunlu Özel Test)*
- **Test ID:** `BK-030`
- **Amaç:** Hub üzerinde aktif bir **Backup** sürerken gelen **Restore** (veya tersi: aktif **Restore** sürerken gelen **Backup** / **Prune**) isteğinin tek-uçlu kilit (`BackupOperationLock`) ile çakışmasız reddedildiğini ve aktif işlemi bozmadığını doğrulamak.
- **Ön koşullar:** Yavaşlatılmış (`Completer` kontrollü) aktif backup / restore oturumuna sahip `SpikeServer` + gerçek FFI SQLite.
- **Test adımları:** (1) `POST /api/v1/backup/trigger` başlat ve kilit içinde beklet. (2) Eşzamanlı `POST /api/v1/backup/restore` gönder. (3) Tersini dene: aktif restore içinde `trigger` ve `prune` gönder. (4) Zamanlanmış tick'i tetikle.
- **Beklenen sonuç:** Eşzamanlı mutasyon istekleri `409 Conflict` (`ERR_BACKUP_OPERATION_BUSY`) döner; aktif işlem bozulmadan biter; zamanlanmış tur hata kaydetmeden atlanır; ikinci veritabanı/lock bozulması yaşanmaz.
- **Kanıt türü:** Otomatik eşzamanlılık & lock testi.
- **Test ortamı:** Dart test runner + gerçek FFI SQLite.
- **Durum:** **`NOT RUN`** *(`BackupOperationLock` var ancak yeni v1.1 Drive/Scheduler/Restore uçlarıyla bütünleşik test henüz yok — `FAIL` / geliştirme sonrası koşulacak)*.

#### `BK-031` — `OWNER`/`CASHIER` Yetkilendirme + Replay Protection *(Zorunlu Özel Test)*
- **Test ID:** `BK-031`
- **Amaç:** Backup/Restore/Settings/OAuth uçlarında `CASHIER` cihaz token'ının veya tekrarlanmış (`nonce` reuse) / süresi dolmuş (`timestamp > ±60s`) isteklerin **`HTTP 403`** döndürdüğünü ve **hiçbir state mutation gerçekleşmediğini** kanıtlamak.
- **Ön koşullar:** `SpikeServer` üzerinde iki doğrulanmış cihaz: `DEV_OWNER` (`role = 'OWNER'`) ve `DEV_CASHIER` (`role = 'CASHIER'`).
- **Test adımları:** (1) Her test öncesi DB `hub_metadata`, `devices`, `backup_jobs_state.json`, `gdrive_oauth_token.dpapi` ve `backups/` dizini snapshot/hash'ini al. (2) `DEV_CASHIER` ile `trigger`, `settings`, `restore`, `oauth/connect`, `oauth/disconnect` uçlarını çağır. (3) `DEV_OWNER` ile geçerli `X-MMS-Nonce` + `X-MMS-Timestamp` içeren isteği 1 kez gönder, aynı `nonce` ile birebir tekrar gönder (replay), ardından `timestamp` 5 dk eski bir istek gönder. (4) Her reddedilen çağrı sonrası DB/dosya/state store hash'lerini karşılaştır ve `device_audit_logs` satırlarını incele.
- **Beklenen sonuç:** Yetkisiz (`CASHIER`) ve replay/expired isteklerin tamamı **`HTTP 403`** (`ERR_FORBIDDEN_ROLE` / `ERR_REPLAY_DETECTED`) döner; backup başlatılmaz, ayar/token/DB değişmez (**zero state mutation**); reddedilen girişimler `device_audit_logs`'a kaydedilir.
- **Kanıt türü:** Otomatik güvenlik & state-invariance testi.
- **Test ortamı:** Dart test runner + gerçek FFI SQLite.
- **Durum:** **`FAIL`** *(Mevcut kodda RBAC route kontrolü ve replay protection hiç uygulanmamıştır)*.

#### `BK-032` — Graceful Shutdown + Aynı `backup_id` ile Güvenli Devam *(Zorunlu Özel Test)*
- **Test ID:** `BK-032`
- **Amaç:** Aktif chunked upload veya yedekleme sırasında servis kapanış sinyali (`SIGINT` / `/api/v1/admin/shutdown`) geldiğinde 15 sn WinSW sınırının altında (`< 12 sn`) temiz kapanıldığını, SQLite transaction'ının zorla kesilmediğini, kalıcı `RETRY_PENDING` yazıldığını ve servis açıldığında **aynı `backup_id`** + son `308` offset'inden güvenli devam edildiğini doğrulamak.
- **Ön koşullar:** Gerçek derlenmiş veya izole `SpikeServer` süreci + chunk 2'de duraklayan mock Drive sunucusu + gerçek FFI SQLite DB.
- **Test adımları:** (1) Backup başlat; chunk 1 (`308`, offset `4194304`) tamamlanıp chunk 2 aktarılırken `SIGINT` / shutdown gönder. (2) Süreç çıkış süresini ve çıkış kodunu ölç; `backup_jobs_state.json` içeriğini incele. (3) Eşzamanlı kısa bir `SALE_CREATE` tx varsa yarım kalmadığını `PRAGMA integrity_check = ok` ile doğrula. (4) Servisi yeniden başlat ve upload tamamlamasını izle.
- **Beklenen sonuç:** Kapanış **`< 12 sn`** (`exit 0`); state store kalıcı `RETRY_PENDING`, `backup_id` aynı ve `uploaded_bytes == 4194304`; açılışta chunk 1 tekrar atılmadan **aynı `backup_id`** ile chunk 2'den devam edilip `COMPLETED_UPLOADED` olur.
- **Kanıt türü:** Otomatik süreç yaşam döngüsü testi (`Process.start` / AOT `mms_backend.exe` + gerçek FFI SQLite).
- **Test ortamı:** Windows test ortamı + gerçek FFI SQLite.
- **Durum:** **`FAIL`** *(`bin/server.dart:4536-4539` shutdown hatası, iptal token'ı eksikliği ve chunked state yokluğu nedeniyle henüz geçemez)*.

---

### 4.2. Fiziksel Kabul Testleri (`BK-PAT-01…BK-PAT-18`)

> **Tüm `BK-PAT-01…BK-PAT-18` testlerinin güncel durumu: `BLOCKED`** (23 Kasım 2026: v1.1 Hub-centric backup kodu uygulanmış ve otomatik testlerle doğrulanmıştır — bkz. [`PHASE_B1…B4` raporları](../IMPLEMENTATION/) ve [`FINAL_PILOT_READINESS_REPORT.md`](../FINAL_PILOT_READINESS_REPORT.md); saha engelleri: `C1/C2` Google Cloud `"In production"` OAuth kimlikleri, `B2` Hub TLS üretim sertifikaları, `B1` Android keystore, gerçek Windows SCM kurulumu, ikinci temiz Windows PC ve bağlı fiziksel Android cihaz ortamda doğrulanmamıştır).
> **İzolasyon Kuralı:** `BK-PAT-10` ve `BK-PAT-11` testleri **yalnızca izole `TEST_ONLY` Google Drive klasöründe** yürütülür; **sistem saati ASLA değiştirilmez** ve **gerçek kullanıcı yedekleri ASLA silinmez**.

#### `BK-PAT-01` — Windows UI OAuth PKCE → `MarketMMSService` (`LocalService`) Token Devri ve Reboot Kalıcılığı
- **Test ID:** `BK-PAT-01`
- **Amaç:** Owner'ın Windows UI üzerinden yaptığı Google Drive bağlantısının `LocalService` servisine güvenle aktarılıp bilgisayar yeniden başlatıldıktan sonra dahi çalıştığını doğrulamak.
- **Ön koşullar:** Kurulmuş `MarketMMSService` (`NT AUTHORITY\LocalService`), üretim TLS (`B2`), Google Cloud OAuth (`C1/C2`), standart kasiyer ve yönetici Windows hesapları.
- **Test adımları:** (1) Windows UI Ayarlar → Hub Yedekleme → Google Drive Bağla (yalnızca `drive.file` kapsam ekranını doğrula). (2) `%ProgramData%\MarketMMS\security\gdrive_oauth_token.dpapi` oluştuğunu ve `icacls` çıktısında `Users`/`Everyone` olmadığını doğrula. (3) `%LOCALAPPDATA%\MarketMMS\` altında `refresh_token` sızmadığını kontrol et. (4) Windows PC'yi yeniden başlat ve servis açılışında kullanıcı login olmadan OAuth durumunun `CONNECTED` olduğunu doğrula.
- **Beklenen sonuç:** Reboot sonrası UI kapalıyken bile servis token'ı çözebilir ve `CONNECTED` kalır.
- **Kanıt türü:** `icacls` çıktısı, maskeli tanı ekranı, OAuth ekran görüntüsü.
- **Test ortamı:** Fiziksel Windows Hub PC (`MarketMMSService`).
- **Durum:** **`BLOCKED`**.

#### `BK-PAT-02` — İlk Etkinleştirmede Başlangıç Yedeği (`INITIAL_ENABLE`) ve Gerçek Drive Upload/Download
- **Test ID:** `BK-PAT-02`
- **Amaç:** Otomatik Hub yedeklemesi ilk kez açıldığında anında `INITIAL_ENABLE` yedeği alınıp gerçek Google Drive hesabına yüklendiğini ve geri indirilip açılabildiğini doğrulamak.
- **Ön koşullar:** `BK-PAT-01` geçti; test satışları içeren canlı `market_master.db`; Owner Portable Recovery Password girdi.
- **Test adımları:** (1) Otomatik yedeklemeyi aç. (2) Durum geçişlerini (`RUNNING` → `SNAPSHOT_CREATED` → `ENCRYPTED` → `UPLOADING` → `VERIFYING` → `COMPLETED_UPLOADED`) ve trigger=`INITIAL_ENABLE` değerini gözlemle. (3) Google Drive'da şifreli `.mmsbak` dosyasını kontrol et ve boyut/SHA-256 doğrulaması yap.
- **Beklenen sonuç:** Drive klasöründe şifreli paket oluşur, sonraki zamanlama bir sonraki yerel `00:00` olarak gösterilir.
- **Kanıt türü:** Drive klasör ekran görüntüsü, Hub backup geçmiş logu, hash çıktısı.
- **Test ortamı:** Fiziksel Windows Hub PC + gerçek Google Drive (`TEST_ONLY` / pilot hesap).
- **Durum:** **`BLOCKED`**.

#### `BK-PAT-03` — Katılımsız Günlük `00.00` Zamanlama ve Ertesi Sabah `CATCH_UP` Gözlemi *(Sistem Saati Değiştirilmez)*
- **Test ID:** `BK-PAT-03`
- **Amaç:** Windows PC başında kimse yokken servisin yerel saat `00.00` penceresinde otomatik yedek aldığını ve `00.00`'da PC kapalı tutulduğunda açılışta `CATCH_UP` aldığını doğrulamak.
- **Ön koşullar:** `BK-PAT-02` geçti; sistem saati **değiştirilmeden** 2 ardışık doğal gece penceresi.
- **Test adımları:** (1) Gece 1: Windows UI kapalı, PC açık bırak; sabah Drive ve Hub geçmişini kontrol et (`00:00–00:15` arası `SCHEDULED_DAILY` + `COMPLETED_UPLOADED`). (2) Gece 2: PC'yi `23:50`'de kapat; sabah `08:30`'da aç ve kullanıcı oturumu açmadan 15 dk sonra `CATCH_UP` kaydını kontrol et.
- **Beklenen sonuç:** Her iki gecede de katılımsız `COMPLETED_UPLOADED` yedek alınır; hiçbir gece çift veya eksik yedek olmaz.
- **Kanıt türü:** Hub log dosyaları, Drive zaman damgalı ekran görüntüsü.
- **Test ortamı:** Fiziksel Windows Hub PC (sistem saati sabit).
- **Durum:** **`BLOCKED`**.

#### `BK-PAT-04` — Gerçek Ağ Kesintisi Sırasında Chunked Resumable Upload & Kaldığı Yerden Devam
- **Test ID:** `BK-PAT-04`
- **Amaç:** En az 12–20 MB boyutlu gerçek Hub `.mmsbak` dosyası Drive'a yüklenirken modem/Wi-Fi kesilip geri açıldığında 4 MB chunk offset'inden devam ettiğini doğrulamak.
- **Ön koşullar:** Büyük test katalog/satış verisiyle > 12 MB `.mmsbak` dosyası.
- **Test adımları:** (1) Manuel Hub yedeği başlat. (2) %40–60 arası interneti kes; `RETRY_PENDING` ve kaydedilmiş byte offset'ini doğrula. (3) İnterneti geri ver ve retry tetiklendiğinde Drive'da tek dosya oluştuğunu ve `COMPLETED_UPLOADED` olduğunu doğrula.
- **Beklenen sonuç:** Tek dosya (`appProperties.mms_backup_id` tekil), checksum birebir eşleşir.
- **Kanıt türü:** Hub maskeli upload logu, Drive dosya detayı.
- **Test ortamı:** Fiziksel Windows Hub PC + gerçek Google Drive.
- **Durum:** **`BLOCKED`**.

#### `BK-PAT-05` — Gerçek Google Drive Kota Dolu (`403 storageQuotaExceeded`) & OAuth Yetki İptali (`REAUTH_REQUIRED`)
- **Test ID:** `BK-PAT-05`
- **Amaç:** Dolu bir test Drive hesabında kota uyarısının OAuth yetkisini bozmadığını, ayrıca Google Hesap Güvenliğinden izin kaldırıldığında `ERR_DRIVE_REAUTH_REQUIRED` geldiğini doğrulamak.
- **Ön koşullar:** Neredeyse dolu izole Google test hesabı + normal `TEST_ONLY` hesap.
- **Test adımları:** (1) Kota dolu hesaba yedek tetikle → `ERR_DRIVE_QUOTA_EXCEEDED` ve `CONNECTED` korumasını kontrol et. (2) Normal test hesabından Google Güvenlik → Market MMS erişimini kaldır → `ERR_DRIVE_REAUTH_REQUIRED` + `LOCAL_ONLY_PENDING_UPLOAD` durumunu ve yerel `.mmsbak` dosyasının sağlam kaldığını doğrula.
- **Beklenen sonuç:** Kota ve auth hataları doğru ayrışır; hiçbir senaryoda yanlış `COMPLETED` yazılmaz veya yerel yedek kaybolmaz.
- **Kanıt türü:** Android/Windows UI hata banner ekran görüntüleri, Hub durum yanıtı.
- **Test ortamı:** Fiziksel Windows Hub + gerçek Google hesapları.
- **Durum:** **`BLOCKED`**.

#### `BK-PAT-06` — Disk Dolu (`ERR_DISK_FULL`) Gerçek Windows Birimi Testi
- **Test ID:** `BK-PAT-06`
- **Amaç:** Hub yedek dizininin bulunduğu disk/VHD bölümü neredeyse doluyken snapshot/encrypt işleminin yarım dosya veya DB kilidi bırakmadan `ERR_DISK_FULL` döndürdüğünü doğrulamak.
- **Ön koşullar:** Hub test yedeği için küçük sınırlı VHD veya dolu test diski.
- **Test adımları:** Boş alan `< 2.5 × DB` iken manuel yedek tetikle; ardından satış yapmayı dene.
- **Beklenen sonuç:** `ERR_DISK_FULL` döner; POS satışları kesilmeden çalışır; artık `.snap.db` kalmaz.
- **Kanıt türü:** Windows PowerShell disk boyut çıktısı, Hub hata logu.
- **Test ortamı:** Fiziksel Windows Hub PC (izole test VHD).
- **Durum:** **`BLOCKED`**.

#### `BK-PAT-07` — Aktif Upload Sırasında Windows Service Graceful Shutdown & Restart (`BK-PAT-07` / Saha `BK-032`)
- **Test ID:** `BK-PAT-07`
- **Amaç:** `MarketMMSService` gerçek chunked upload yaparken `Stop-Service MarketMMSService` verildiğinde 15 sn WinSW sınırında hard-kill yemeden kapandığını ve `Start-Service` sonrası aynı `backup_id` ile bitirdiğini doğrulamak.
- **Ön koşullar:** Kurulmuş `MarketMMSService`, > 10 MB test paketi.
- **Test adımları:** (1) Upload başlat. (2) Aktifken `Measure-Command { Stop-Service MarketMMSService }` çalıştır. (3) Event Viewer ve WinSW logunda hard-kill olmadığını doğrula. (4) `Start-Service MarketMMSService` çalıştır ve aynı `backup_id`'nin Drive'da tamamlandığını kontrol et.
- **Beklenen sonuç:** Süre `< 15 sn` (`~12 sn`), SQLite `PRAGMA integrity_check = ok`, Drive'da tek dosya.
- **Kanıt türü:** PowerShell çıktı süresi, WinSW/Event Viewer logları.
- **Test ortamı:** Fiziksel Windows Hub PC.
- **Durum:** **`BLOCKED`**.

#### `BK-PAT-08` — Backup Sırasında Güç Kesintisi / Süreç Çökmesi (Crash Recovery)
- **Test ID:** `BK-PAT-08`
- **Amaç:** Yedekleme `ENCRYPTED` sonrası `UPLOADING` ortasındayken `Stop-Process -Force` ile öldürüldüğünde WinSW tarafından yeniden başlatılan servisin PBKDF2 tekrarlamadan aynı `backup_id` ile yüklemeyi bitirdiğini doğrulamak.
- **Ön koşullar:** `MarketMMSService` kurulu.
- **Test adımları:** Upload başladığında `Stop-Process -Name mms_backend -Force`; 5 sn sonra WinSW restartını, temp snapshot sahiplik temizliğini ve Drive tamamlamasını gözlemle.
- **Beklenen sonuç:** Geçici `.snap.db` varsa temizlenir; şifreli paket sağlam kaldığı için aynı `backup_id` tekrar şifrelenmeden Drive'a çıkar.
- **Kanıt türü:** Hub logu (`kdf_skipped` / `resumed_backup_id`), Drive dosya listesi.
- **Test ortamı:** Fiziksel Windows Hub PC.
- **Durum:** **`BLOCKED`**.

#### `BK-PAT-09` — Hub Geri Yükleme Sırasında Eşzamanlı Backup/Sync Çakışma Koruması
- **Test ID:** `BK-PAT-09`
- **Amaç:** Hub restore sürerken Android yönetim uygulamasından veya diğer istemciden tetiklenen manuel backup/satış senkronunun DB'yi bozmadığını doğrulamak.
- **Ön koşullar:** Fiziksel Windows Hub + Android `OWNER` cihazı.
- **Test adımları:** Windows'tan Hub restore başlat; tam o anda Android'den `Şimdi Yedekle` ve eşzamanlı offline satış gönder.
- **Beklenen sonuç:** Backup isteği `409 ERR_BACKUP_OPERATION_BUSY` alır, satış isteği `503` ile Android Outbox'ta güvenle bekler ve restore sonrası kayıpsız senkronize olur.
- **Kanıt türü:** Ekran görüntüleri, Hub logu, Android Outbox ve Hub satış sayısı.
- **Test ortamı:** Fiziksel Windows Hub + Android cihaz.
- **Durum:** **`BLOCKED`**.

#### `BK-PAT-10` — İzole `TEST_ONLY` Drive Klasöründe 30g/12a Retention Doğrulaması *(Saat Değiştirilmez, Gerçek Yedek Silinmez)*
- **Test ID:** `BK-PAT-10`
- **Amaç:** Gerçek Google Drive API üzerinde **yalnızca izole `TEST_ONLY` klasöründe** oluşturulan metadata/manifest tarihli test dosyalarının 30 günlük + 12 aylık politikaya göre budandığını doğrulamak.
- **Ön koşullar:** İzole `TEST_ONLY` Drive test klasörü; içinde yalnızca bu test için yüklenmiş tarihi manifestte/appProperties'te geriye işaretli sentetik `.mmsbak` test dosyaları (**cihaz saatine dokunulmaz, gerçek kullanıcı yedekleri kullanılmaz**).
- **Test adımları:** (1) `TEST_ONLY` klasörüne 40 adet sahte tarih etiketli (son 30 gün + 2..14 ay aralığında) sentetik test `.mmsbak` yükle. (2) Hub retention politikasını yalnızca `TEST_ONLY` klasör hedefli test modu/komutuyla çalıştır. (3) Klasörde kalan dosyaları say.
- **Beklenen sonuç:** Son 30 gün + 2..12. aydan ay başına 1 dosya kalır; 31+ gün ara günlükler ve 13+ ay arşivler silinir; **gerçek kullanıcı yedekleri ve sistem saati dokunulmaz**.
- **Kanıt türü:** `TEST_ONLY` klasör öncesi/sonrası dosya listesi çıktısı.
- **Test ortamı:** Gerçek Google Drive API (`TEST_ONLY` klasörü) + Hub test aracı.
- **Durum:** **`BLOCKED`**.

#### `BK-PAT-11` — İzole `TEST_ONLY` Drive Klasöründe Son Geçerli Yedek Koruması *(Saat Değiştirilmez, Gerçek Yedek Silinmez)*
- **Test ID:** `BK-PAT-11`
- **Amaç:** `TEST_ONLY` klasöründeki tüm geçerli test yedekleri 12 aydan eski tarih etiketine sahip olduğunda dahi **son geçerli 1 `COMPLETED_UPLOADED` yedeğin silinmediğini** gerçek Drive üzerinde doğrulamak.
- **Ön koşullar:** `TEST_ONLY` klasöründe tamamı 14–18 ay öncesine tarihlenmiş 3 sentetik test `.mmsbak` dosyası + sistem saati normal.
- **Test adımları:** Retention budamasını `TEST_ONLY` üzerinde çalıştır ve klasörü listele.
- **Beklenen sonuç:** En yeni 1 geçerli test `.mmsbak` dosyası kesinlikle korunur (`0` geçerli yedeğe asla düşülmez); diğer 2'si temizlenir.
- **Kanıt türü:** Drive `TEST_ONLY` klasörü öncesi/sonrası dosya listesi ve log.
- **Test ortamı:** Gerçek Google Drive API (`TEST_ONLY` klasörü).
- **Durum:** **`BLOCKED`**.

#### `BK-PAT-12` — Yanlış Kurtarma Parolası ve Bozuk İndirme ile Fiziksel Restore Reddi
- **Test ID:** `BK-PAT-12`
- **Amaç:** Gerçek Drive yedeği geri yüklenirken kasıtlı yanlış Portable Recovery Password girildiğinde canlı mağaza verilerinin bozulmadığını doğrulamak.
- **Ön koşullar:** Canlı satış içeren Hub + Drive'da şifreli `.mmsbak`.
- **Test adımları:** (1) Restore başlatıp bilerek yanlış parola gir. (2) Hemen ardından kasada satış yapıp DB sağlığını kontrol et. (3) Doğru parolayla Safety Snapshot'ın şifreli oluştuğunu doğrula.
- **Beklenen sonuç:** Yanlış parolada `ERR_DECRYPTION_FAILED`; canlı DB kesintisiz kalır.
- **Kanıt türü:** UI ekran görüntüleri, satış testi ve Hub logu.
- **Test ortamı:** Fiziksel Windows Hub PC.
- **Durum:** **`BLOCKED`**.

#### `BK-PAT-13` — Yeni Windows PC'de Sıfırdan Hub Restore + Portable Recovery + Toplu Cihaz Re-pairing
- **Test ID:** `BK-PAT-13`
- **Amaç:** Eski Hub PC disk arızası senaryosunda, temiz ikinci bir Windows PC'de yalnızca Portable Recovery Password ile Google Drive yedeğinin geri yüklenip mağazanın ayağa kalktığını doğrulamak.
- **Ön koşullar:** PC-1'de satış/ürün verisi + Drive `COMPLETED_UPLOADED` `MMSBAK02` yedek; tamamen temiz PC-2 (farklı `pepper.dpapi` ve `C:\ProgramData\MarketMMS`).
- **Test adımları:** (1) PC-2'ye `MarketMMSService` kur ve aynı mağaza Google hesabını bağla. (2) Drive yedeğini seç ve Portable Recovery Password girerek restore et. (3) Tüm ürünlerin, satışların ve stokların geldiğini doğrula. (4) Önceden PC-1 ile eşleştirilmiş Android cihazın eski token ile `401` alıp re-pairing gerektirdiğini doğrula ve QR ile PC-2'ye yeniden eşleştir.
- **Beklenen sonuç:** PC-1'in `pepper.dpapi`'si olmadan tüm veriler açılır; re-pairing sonrası Android sorunsuz senkron olur.
- **Kanıt türü:** PC-1 ve PC-2 DB ürün/satış sayım karşılaştırması, re-pairing QR ve Android eşleştirme kanıtı.
- **Test ortamı:** İki fiziksel Windows PC + fiziksel Android + gerçek Google Drive.
- **Durum:** **`BLOCKED`**.

#### `BK-PAT-14` — Restore Sonrası Çevrimdışı Android Satışlarının Kayıpsız Outbox Uzlaştırması
- **Test ID:** `BK-PAT-14`
- **Amaç:** Hub 1 saat önceki yedeğe döndükten sonra, o arada offline Android kasada yapılmış satışların re-pairing ardından Hub'a kayıpsız ve mükerrer olmadan aktarıldığını doğrulamak.
- **Ön koşullar:** Saat `10:00` yedeği Drive'da mevcut; saat `10:15`'te Hub çevrimdışı bırakılıp Android'de 3 offline satış yapılır; ardından Hub `10:00` yedeğine restore edilir.
- **Test adımları:** (1) Android'de `PENDING = 3` göründüğünü doğrula. (2) Android'i restore edilmiş Hub ile re-pair et (yerel DB'yi silmeden). (3) Senkronizasyonu bekle ve hem Hub hem Windows UI'da 3 satış + stok düşüşünü doğrula.
- **Beklenen sonuç:** 3 offline satışın tamamı Hub'a ulaşır; Outbox `0 PENDING` olur; mükerrer satış yoktur.
- **Kanıt türü:** Android ve Hub satış listesi/stok ekran görüntüleri, tanı raporu.
- **Test ortamı:** Fiziksel Windows Hub + fiziksel Android cihaz.
- **Durum:** **`BLOCKED`**.

#### `BK-PAT-15` — Android Bakım / Yönetim UI Fiziksel Doğrulaması (`OWNER` vs `CASHIER`)
- **Test ID:** `BK-PAT-15`
- **Amaç:** Fiziksel Android `OWNER` telefonunun Hub backup durumunu, son geçmişi, ayar değişimini ve manuel tetiklemeyi yönettiğini; `CASHIER` telefonunun ise `403` ile mutasyon yapamadığını doğrulamak.
- **Ön koşullar:** 1 adet `OWNER` Android cihazı + 1 adet `CASHIER` Android cihazı eşleştirilmiş.
- **Test adımları:** (1) `OWNER` telefondan Hub durum/geçmişi gör ve **Şimdi Yedekle** tetikle. (2) Google OAuth bağlama butonunun Android'de olmadığını (Windows Hub'a yönlendirdiğini) doğrula. (3) `CASHIER` telefondan mutasyonun kapalı/engelli olduğunu doğrula ve ağ testinde `CASHIER` token'ının Hub tarafından `403` aldığını teyit et.
- **Beklenen sonuç:** `OWNER` sorunsuz yönetir, `CASHIER` mutasyonları engellenir.
- **Kanıt türü:** Her iki cihazın ekran görüntüleri, Hub `device_audit_logs`.
- **Test ortamı:** Fiziksel Windows Hub + 2 fiziksel Android cihaz.
- **Durum:** **`BLOCKED`**.

#### `BK-PAT-16` — Android Eski Yerel Yedeklerin Korunması ve İzolasyonu (`B1.12`)
- **Test ID:** `BK-PAT-16`
- **Amaç:** v1.1 kurulumu veya güncellemesi yapılmış fiziksel Android cihazda önceden alınmış yerel `.mmsbak` dosyalarının silinmediğini ve istenirse yerel kurtarma yapılabildiğini doğrulamak.
- **Ön koşullar:** Cihazında v1.0 döneminden en az 1 yerel `.mmsbak` bulunduran Android cihaz.
- **Test adımları:** (1) v1.1 APK güncellemesini kur. (2) Tanılama → Eski Yerel Yedekler altında eski `.mmsbak`'ın hâlâ listelendiğini doğrula. (3) Eski yedeğin Hub Drive klasörüne merkezi yedek olarak karışmadığını kontrol et.
- **Beklenen sonuç:** Sıfır yerel yedek silinmesi; net ayrı UI gösterimi.
- **Kanıt türü:** Android dosya/ekran görüntüsü, Drive listesi.
- **Test ortamı:** Fiziksel Android cihaz + Windows Hub.
- **Durum:** **`BLOCKED`**.

#### `BK-PAT-17` — Gerçek Pre-Restore Safety Snapshot'tan Geri Dönüş (Yanlış Yedeği Geri Alma)
- **Test ID:** `BK-PAT-17`
- **Amaç:** İşletme sahibi yanlış tarihteki bir Hub yedeğini geri yükledikten hemen sonra, otomatik alınan şifreli *Safety Snapshot*'ı kullanarak restore öncesi duruma eksiksiz dönebildiğini doğrulamak.
- **Ön koşullar:** `T1` ve `T2` satışları olan canlı Hub + `T1` Drive yedeği.
- **Test adımları:** (1) `T1` yedeğini restore et (`T2` geçici görünmez). (2) `safety_snapshots\` içindeki yeni şifreli `MMSBAK02` safety kopyasını Portable Recovery Password ile restore et. (3) `T2` satışlarının geri geldiğini doğrula.
- **Beklenen sonuç:** `T2` durumu eksiksiz geri döner; güvenlik kopyası şifresiz `.db` bırakmaz.
- **Kanıt türü:** Safety dosya adı, Hub satış listesi ve hash doğrulaması.
- **Test ortamı:** Fiziksel Windows Hub PC.
- **Durum:** **`BLOCKED`**.

#### `BK-PAT-18` — Katılımsız (Unattended) Windows Service Uzun Süreli Kararlılık & Oturum Kapalı Çalışma
- **Test ID:** `BK-PAT-18`
- **Amaç:** Windows oturumu kilitliyken / hiçbir kullanıcı oturumu açık değilken dahi `MarketMMSService` servisinin günlük yedeği alıp Drive'a doğrulamalı olarak yüklediğini kanıtlamak.
- **Ön koşullar:** `BK-PAT-01..03` geçmiş; Hub PC yeniden başlatılıp Windows login ekranında (oturum açılmadan) bırakılır.
- **Test adımları:** (1) PC'yi aç ve Windows kullanıcı girişi yapmadan `00:00` penceresini veya planlı zamanı bekle. (2) Ertesi sabah Drive'da `COMPLETED_UPLOADED` yedeği ve Hub loglarında DPAPI/`LocalService` hatası olmadığını kontrol et.
- **Beklenen sonuç:** Kullanıcı etkileşimi olmadan servis kendi başına DB snapshot → şifreleme → Drive 4 MB chunked upload → doğrulamayı tamamlar.
- **Kanıt türü:** Event Viewer zaman damgaları, Hub logu, Drive dosyası.
- **Test ortamı:** Fiziksel Windows Hub PC (login ekranında).
- **Durum:** **`BLOCKED`**.

---

## 5. Hata Senaryoları (Test Yürütme Başarısızlık Prosedürü)

1. Herhangi bir `BK-PAT` testi kalırsa **veritabanı, `.mmsbak`, `.snap.db`, `backup_jobs_state.json` veya `outbox_operations` kayıtları ASLA silinmez**.
2. `%ProgramData%\MarketMMS\logs` ve istemci Maskeli Tanı Raporu toplanır.
3. Hata ilgili `BK-*` / `BK-PAT-*` kimliği ve tam log dökümüyle raporlanır.

---

## 6. Güvenlik Gereksinimleri

- Tüm fiziksel test kanıt klasörlerinde (`pilot_kanit/BK-PAT-xx/`) OAuth token, `pepper`, `admin_secret`, `server.key` veya Portable Recovery Password metinleri maskelenmiş olmalıdır.
- `TEST_ONLY` Drive hesabı/klasörü pilot mağazanın gerçek Google Drive hesabıyla karıştırılmamalıdır.

---

## 7. Veri Tutarlılığı

- Tüm `BK-001…BK-032` DB/crash/lock testleri **gerçek FFI SQLite sürücüsü** ile koşulmalıdır (`AGENTS.md` §8).
- Her test sonunda `PRAGMA integrity_check = ok`, kuruş toplam eşitliği (`int`), ve bekleyen Outbox satır sayısının değişmediği doğrulanmalıdır.

---

## 8. Geriye Dönük Uyumluluk

### 8.1. `PAT-01…PAT-18` Kimlik Uzayı Ayrımı

| Mevcut `PAT-*` Testi | Kapsamı | v1.1 `BK-PAT-*` İle İlişkisi |
|---|---|---|
| `PAT-13` | Mevcut istemci OAuth & Drive yükleme taslağı | **Değiştirilmez / Çakışmaz.** Hub-centric karşılığı **`BK-PAT-01`, `BK-PAT-02`, `BK-PAT-04`, `BK-PAT-05`** altında ayrı test edilir. |
| `PAT-16` | Android kapalıyken `JobScheduler` yerel yedek (`ADR-020`) | **Değiştirilmez / Çakışmaz.** Eski yerel yedek izolasyonu **`BK-PAT-16`**, Hub servisi unattended çalışması **`BK-PAT-18`** altındadır. |
| `PAT-18` | `ADR-021` Hibrit Hub + Drive Canlı Senkronizasyon | **Değiştirilmez / Çakışmaz.** Canlı sync konusu ayrıdır; yedekleme zamanlaması/kapatma **`BK-PAT-07`, `BK-PAT-18`** altındadır. |

### 8.2. Mevcut Repository Yedek / Kapanış Test Envanteri (22 Kasım 2026)
- `packages/mms_client_storage/test/`: `backup_file_transfer_test.dart` (10), `backup_isolate_responsiveness_test.dart` (1), `backup_operation_lock_test.dart` (14), `google_drive_backup_test.dart` (17), `restore_outbox_preservation_test.dart` (5), `restore_safety_snapshot_encryption_test.dart` (6), `s5a4_backup_restore_test.dart` (22), `scheduled_backup_runner_test.dart` (14). *(Bu denetimde çalıştırılmadı — `NOT RUN`)*
- `test/features/backup/`: `android_google_sign_in_oauth_test.dart` (9), `backup_schedule_controller_test.dart` (7), `client_backup_operation_lock_test.dart` (5), `drive_backup_restore_integration_test.dart` (4), `workmanager_background_backup_test.dart` (7). *(Bu denetimde çalıştırılmadı — `NOT RUN`)*
- `test_spikes/spike_01_backend/test/`: `hub_scheduled_backup_test.dart` (10), `lifecycle_drain_test.dart` (1), `s5a4_central_restore_lifecycle_test.dart` (1), `shutdown_regression_test.dart` (3). *(Bu denetimde çalıştırılmadı — `NOT RUN`)*

---

## 9. Kabul Kriterleri

- **Hat B Teknik Tamamlama:** `BK-001…BK-032` otomatik testlerinin %100'ü (`32/32`) gerçek FFI SQLite üzerinde son kod değişikliğinden sonra **`PASS`** olmalı ve sıfır `flutter/dart analyze` hatası verilmelidir.
- **Hat B Fiziksel Kabul:** `BK-PAT-01…BK-PAT-18` fiziksel testlerinin tamamı gerçek Windows Service, gerçek Google OAuth/Drive ve gerçek Android cihaz üzerinde **`PASS`** olmadan ve Owner onayı verilmeden pilot dağıtımı yapılmaz.

---

## 10. Test Referansları

- `BK-001..BK-007` ↔ Architecture v1.1 §4.3, §4.4, §4.8
- `BK-008..BK-020`, `BK-032` ↔ Scheduling Spec v1.1 §4.1..§4.7
- `BK-021..BK-031` ↔ Architecture v1.1 §4.2, §4.8, §4.9, §4.10
- `BK-PAT-01..BK-PAT-18` ↔ Architecture v1.1 + Scheduling Spec v1.1 Uçtan Uca Saha Doğrulaması

---

## 11. Açık Konular (`TBD` / `OPEN`)

1. `TEST_ONLY` retention testleri (`BK-PAT-10`, `BK-PAT-11`) için Hub test modunda `appProperties.mms_test_created_at` tarih okuma kancasının yalnızca debug/test bayrağıyla mı yoksa ayrı bir CLI doğrulama aracıyla mı yürütüleceği (üretim ikilisinde sahte tarih enjeksiyonunu önlemek için) kararlaştırılacaktır.
2. İkinci temiz fiziksel Windows PC veya temiz izole VM ortamının Owner tarafından `BK-PAT-13` için hazırlanması (`BLOCKED`).

---

## 12. Owner Kararları

| Konu | Owner Kararı | Durum |
|---|---|---|
| `PAT-01…PAT-18` ile Çakışmayan Ayrı `BK-001…BK-032` ve `BK-PAT-01…BK-PAT-18` Kimlikleri | Talep kapsamı gereği ayrıştırıldı | **`[CONFIRMED]`** |
| Sistem Saati Değiştirmeme & `TEST_ONLY` Klasörde Gerçek Yedek Silmeme Kuralı | Talep kapsamı gereği zorunlu | **`[CONFIRMED]`** |
| Mock Testlerin Fiziksel Drive / OAuth / Windows Service Testi Yerine Geçmemesi | Talep kapsamı gereği zorunlu | **`[CONFIRMED]`** |
