# ADR-022: Android Google Drive OAuth Tasarımı (Yedekleme ve Hibrit Canlı Senkronizasyon)

- **Karar Kodu:** ADR-022
- **Durum:** `[CONFIRMED — TECHNICALLY IMPLEMENTED]` *(Owner tarafından **Seçenek A — `google_sign_in`** ve **Android Drive entegrasyonunun pilot kapsamına dahil edilmesi** kararlaştırılmıştır. 22.11.2026 Phase 2 implementasyonu kapsamında `pubspec.yaml`'a `google_sign_in: ^7.2.0` eklenmiş; `AndroidGoogleSignInTokenProvider`, `drive_auth_providers.dart`, `GoogleDriveConnectService`, `backup_providers.dart`, `sync_providers.dart`, `ExternalBackupSection` ve 9 otomatik test [unit + widget + `ADR-021` E2E + Android Debug APK derlemesi] başarıyla tamamlanmıştır. Gerçek Google Cloud kurulumu [`C1/C2`], Release keystore [`B1`] ve fiziksel cihaz testleri [`PAT-13/17/18`] Owner/donanım beklemektedir — **`BLOCKED`**.)*
- **Tarih:** 2026-11-22 *(İlk taslak: 2026-11-21)*
- **Karar Vericiler:** Proje Sahibi (Owner)
- **Onaylanan Yöntem:** **Seçenek A — Resmi `google_sign_in` (v7+ mimarisi: Android Credential Manager + Google Play Services `AuthorizationClient`)**
- **İlgili Mevcut Bileşenler (İncelenen):**
  - `lib/features/backup/application/google_drive_connect_service.dart`
  - `lib/features/backup/backup_providers.dart`
  - `lib/features/sync/sync_providers.dart`
  - `packages/mms_client_storage/lib/src/backup/google_drive_backup.dart`
  - `packages/mms_client_storage/lib/src/sync/hybrid_drive_live_sync.dart`
  - `android/app/src/main/kotlin/com/marketmms/market_pos/MmsSecureStorageChannelHandler.kt`
  - `android/app/src/main/kotlin/com/marketmms/market_pos/MmsBackgroundBackupJobService.kt`
  - `android/app/build.gradle.kts` (`applicationId = "com.marketmms.market_pos"`)

---

## 1. Owner Kararı ve Kapsam Sınırı

Owner tarafından Phase 1.1 Finalization kapsamında aşağıdaki kararlar kesinleştirilmiştir:

| Konu | Kesinleşen Karar |
|---|---|
| **Android Google Drive OAuth Yöntemi** | **Seçenek A — `google_sign_in`** |
| **Android Drive Entegrasyonu Pilot Kapsamı** | **Pilot kapsamına dahil** (Phase 2 implementasyonu ve `C1`/`C2`/`B1` + `PAT-13`/`PAT-17`/`PAT-18` sonrasında sahaya çıkar) |
| **Phase 1.1 Uygulama Sınırı** | **Yalnızca mimari karar ve teknik tasarım**; OAuth kodu yazılmaz, `pubspec.yaml`'a `google_sign_in` eklenmez, Google Cloud üzerinde işlem yapılmaz ve credential üretilmez |
| **ADR-021 Drive Klasör Adı** | `MARKET MMS LiveSync` (yedekler: `MARKET MMS Yedekleri`) |

---

## 2. Mevcut Kod Tabanı ve Platform Farklılıkları

### 2.1 Mevcut Google Drive Altyapısı
Release 1.0 kod tabanında Drive erişimi iki katmana ayrılmıştır:

1. **Ortak Transport ve Token Sözleşmesi (`packages/mms_client_storage`):**
   - `DriveAccessTokenProvider` arayüzü tek bir metot sunar: `Future<String> accessToken({bool forceRefresh = false})`.
   - `GoogleOAuthRefreshTokenProvider` bu arayüzü **Windows Desktop** için uygular: güvenli depodan okuduğu `refresh_token` (`gdrive_refresh_token_v1`) ile `https://oauth2.googleapis.com/token` ucundan kısa ömürlü `access_token` üretir, RAM'de önbellekler (`expires_in - 60 sn` güvenlik payı), `400/401` yanıtında `ERR_DRIVE_REAUTH_REQUIRED` fırlatır ve `revokeToken()` ile `https://oauth2.googleapis.com/revoke` ucunu çağırır.
   - Hem şifreli yedekleme (`GoogleDriveBackupUploader`, klasör: `"MARKET MMS Yedekleri"`) hem de `ADR-021` hibrit canlı senkronizasyon (`GoogleDriveLiveEnvelopeTransport`, klasör: `"MARKET MMS LiveSync"`) doğrudan `DriveAccessTokenProvider` soyutlamasına bağımlıdır.
2. **İstemci Bağlantı Servisi (`lib/features/backup/application/google_drive_connect_service.dart`):**
   - Windows'ta ephemeral `127.0.0.1:<port>` loopback HTTP dinleyicisi + PKCE (`GoogleOAuthDesktopFlow`) kullanır.
   - Yapılandırma `--dart-define=MMS_GDRIVE_CLIENT_ID=...` (opsiyonel `MMS_GDRIVE_CLIENT_SECRET`) üzerinden okunur (`backup_providers.dart:68-69`, `sync_providers.dart:40-41`).
   - `_openWithSystemBrowser` Windows dışında doğrudan `DriveBackupException('ERR_DRIVE_PLATFORM_UNSUPPORTED', ...)` fırlatır (`google_drive_connect_service.dart:96-100`).

### 2.2 Windows vs Android Platform Farklılıkları

| Boyut | Windows İstemci (Mevcut) | Android İstemci (Seçenek A — Phase 2 Hedefi) |
|---|---|---|
| **Yetkilendirme Mekanizması** | `127.0.0.1` loopback HTTP + PKCE (`GoogleOAuthDesktopFlow`) | Google, Android istemcilerde `127.0.0.1` loopback redirect'i ve gömülü WebView'ları desteklemez/yasaklar (RFC 8252). Bunun yerine `google_sign_in` (v7+) üzerinden **Credential Manager + Play Services `AuthorizationClient`** kullanılır. |
| **OAuth İstemci Kimliği** | Google Cloud **Desktop app** Client ID | Google Cloud **Android** OAuth Client ID (`com.marketmms.market_pos` + SHA-1) **VE** aynı projede **Web application** OAuth Client ID (`serverClientId`) |
| **Client Secret** | Opsiyonel (`MMS_GDRIVE_CLIENT_SECRET`, masaüstü public client) | Android APK içine **ASLA** `client_secret` konmaz; Play Services paket adı + APK imza sertifikası parmak izi ile doğrulama yapar. |
| **Token Modeli** | Kalıcı `refresh_token` (`WindowsDpapiTokenStore`) → `access_token` | İstemciye ham `refresh_token` **verilmez**; yalnızca kısa ömürlü `access_token` (`AuthorizationClient`) alınır ve RAM'de tutulur. |
| **Güvenli Depolama** | `WindowsDpapiTokenStore` (`CurrentUser` DPAPI) | `AndroidKeystoreTokenStore` → `MmsSecureStorageChannelHandler` (`AndroidKeyStore` AES-256-GCM + `SharedPreferences`) |
| **Arka Plan İşleri** | Uygulama içi zamanlayıcı + Windows Hub servisi | `MmsBackgroundBackupJobService` (`JobScheduler`, `JOB_ID = 70201`, headless `FlutterEngine`) |

---

## 3. Seçilen Mimari (`Seçenek A: google_sign_in`) — 14 Teknik Boyut

> [!NOTE]
> Aşağıdaki teknik tasarım `google_sign_in` **v7.x+** (ve `google_sign_in_android`) resmi eklenti mimarisine dayanır. Bu sürümde **kimlik doğrulama (Authentication — Credential Manager)** ile **API kapsam yetkilendirmesi (Authorization — `AuthorizationClient`)** kesin olarak ayrılmıştır.

### 3.1 Google Hesabı Seçimi ve Yetkilendirme
- **İki Aşamalı Akış (`google_sign_in` v7+):**
  1. **Başlatma:** Uygulama ön planda iken bir kez `await GoogleSignIn.instance.initialize(serverClientId: kGoogleDriveWebClientId)` çağrılır.
  2. **Kimlik Doğrulama (Hesap Seçimi):** Kullanıcı "Google Drive'ı Bağla" butonuna bastığında `await GoogleSignIn.instance.authenticate()` çağrılır. Android'de sistem **Credential Manager** hesap seçici alt sayfasını açar ve `GoogleSignInAccount` nesnesi döner.
  3. **API Yetkilendirmesi:** Hesap seçildikten sonra `account.authorizationClient.authorizeScopes([googleDriveFileScope])` çağrılır. Android **Google Play Services `AuthorizationClient`** üzerinden yalnızca gerekli Drive izni için rıza diyaloğu (gerekirse) gösterir ve `GoogleSignInClientAuthorization` (içinde `accessToken`) döner.
- **Ön Koşullar:** Aktif ön plan Android `Activity` bağlamı ve güncel **Google Play Services (GMS)** gereklidir. GMS bulunmayan (HMS-only / AOSP GMS'siz) endüstriyel el terminalleri Seçenek A ile **desteklenmez**.

### 3.2 Google Drive API Scope'ları (`Least Privilege`)
- **Tek Yetkili Kapsam (`ADR-011`):** Yalnızca `https://www.googleapis.com/auth/drive.file`.
- **Yasaklı Kapsamlar:** `https://www.googleapis.com/auth/drive`, `drive.readonly`, `drive.metadata` veya Drive dışı gereksiz kapsamlar kesinlikle talep edilmez.
- **`drive.file` Çapraz Cihaz Paylaşım Kuralı:** `drive.file`, yalnızca **aynı Google Cloud projesi** tarafından oluşturulmuş veya kullanıcıca açıkça seçilmiş klasör/dosyalara erişim izni verir. Windows Desktop OAuth Client ID, Android OAuth Client ID ve Android `serverClientId` (Web OAuth Client ID) **aynı Google Cloud projesi** altında oluşturulmalı ve tüm mağaza cihazları aynı Google hesabıyla yetkilendirilmelidir. Aksi hâlde bir cihazın `"MARKET MMS Yedekleri"` veya `"MARKET MMS LiveSync"` klasörüne yüklediği dosyaları diğer cihaz göremez. Bu davranış gerçek Google Cloud projesi üzerinde `PAT-18` ile fiziksel olarak doğrulanacaktır.

### 3.3 Access Token Edinimi
- **Ön Plan / Etkileşimli Bağlama:** `await account.authorizationClient.authorizeScopes(['https://www.googleapis.com/auth/drive.file'])` çağrısı `GoogleSignInClientAuthorization.accessToken` döndürür.
- **Sessiz Kontrol / Edinme:** Kullanıcı etkileşimi olmadan mevcut yetkiyi okumak için `await account.authorizationClient.authorizationForScopes(['https://www.googleapis.com/auth/drive.file'])` çağrılır; izin önceden verilmişse ve çözünürlük (resolution) gerekmiyorsa token döner, etkileşim gerekiyorsa `null` (veya yetkilendirme eksikliği) döner.
- **Mevcut Transport Sözleşmesiyle Uyum:** Phase 2'de `AndroidGoogleSignInTokenProvider implements DriveAccessTokenProvider` adaptörü yazılacaktır. `GoogleDriveBackupUploader` ve `GoogleDriveLiveEnvelopeTransport` sınıfları yalnızca `DriveAccessTokenProvider.accessToken({bool forceRefresh = false})` arayüzüne bağımlı olduğu için Drive upload/download ve `MMSENV01` zarf protokolü değiştirilmeden Android'e bağlanacaktır.

### 3.4 Access Token Expiration ve Yenileme
- **Yaşam Süresi:** Google OAuth 2.0 `access_token` değerleri kısa ömürlüdür (standart olarak yaklaşık **1 saat / 3600 saniye**).
- **RAM Önbelleği:** Alınan `accessToken` yalnızca bellek içi (RAM) önbellekte tutulur (muhafazakâr erken yenileme penceresi, ör. 50–55 dk veya Play Services önbelleği). Asla diske veya SQLite'a düz metin olarak yazılmaz.
- **Süre Dolumu ve `401 Unauthorized` Yenileme Akışı:**
  1. `GoogleDriveBackupUploader` veya `GoogleDriveLiveEnvelopeTransport` Drive REST API'den HTTP `401` aldığında (veya `forceRefresh: true` çağrıldığında),
  2. Önce önbellekteki bayat token temizlenir: `await GoogleSignIn.instance.clearAuthorizationToken(accessToken: staleToken)` (`google_sign_in` v7 API'si; altta Android `AuthorizationClient` / GoogleAuthUtil token önbelleğini temizler),
  3. Ardından tek seferlik sessiz yenileme denenir: `await account.authorizationClient.authorizationForScopes([googleDriveFileScope])`.
  4. Play Services yeni bir kısa ömürlü `access_token` üretebiliyorsa istek tek sefer tekrarlanır; üretemezse (`null` veya resolution gerekli hatası) sistem kullanıcıya **`ERR_DRIVE_REAUTH_REQUIRED`** ("Google Drive yetkisi yenilenemedi; lütfen hesabı yeniden bağlayın") döndürür.

### 3.5 Refresh Token Gereksinimi ve Gerçek Destek Durumu *(Kritik Doğruluk Notu)*
- **`google_sign_in` / `AuthorizationClient` İstemciye Ham `refresh_token` VERMEZ:**
  - Google'ın modern Android `AuthorizationClient` API'si ve Flutter `google_sign_in` (v7+) eklentisi, mobil istemciye kalıcı bir OAuth `refresh_token` teslim etmez; yalnızca kısa ömürlü `access_token` veya sunucuya gönderilmek üzere tek kullanımlık `serverAuthCode` üretir.
  - Bu nedenle Android istemcisi, Windows'taki `GoogleOAuthRefreshTokenProvider` gibi `gdrive_refresh_token_v1` anahtarına gerçek bir Google `refresh_token` yazıp `https://oauth2.googleapis.com/token` ucuna `grant_type=refresh_token` isteği **atamaz**.
- **Kalıcı Arka Plan Refresh Garantisi Yoktur:**
  - Play Services kendi sistem hesap oturumu üzerinden `authorizationForScopes(...)` çağrılarına sessizce yeni `access_token` basabilir; ancak şu durumlarda sessiz yenileme **kesinlikle durur** ve kullanıcının ön planda yeniden etkileşim vermesi gerekir (`hasResolution() == true`):
    - Cihazdan Google hesabının kaldırılması veya şifre/2FA güvenlik olayı,
    - Kullanıcının Google Hesap ayarlarından uygulama iznini iptal etmesi,
    - Google OAuth politikaları gereği rıza ekranının (consent) yeniden onay gerektirmesi,
    - **OAuth Consent Screen "Testing" Modu 7 Gün Kuralı:** Google Cloud OAuth izin ekranı `"Testing"` statüsünde bırakılırsa verilen yetkiler/tokenlar **7 gün sonra otomatik geçersiz olur**. Pilot ve üretimde OAuth izin ekranı mutlaka **`"In production"`** durumuna alınmalıdır (`drive.file` non-sensitive kapsam olduğundan tam CASA güvenlik denetimi gerektirmeden temel marka/gizlilik doğrulaması ile yayınlanabilir; ancak Google Cloud doğrulama süreci Owner sorumluluğundadır).

### 3.6 `serverAuthCode` (`authorizeServer`) ile `accessToken` (`authorizeScopes`) Farkı

| Özellik | `authorizeScopes` / `authorizationForScopes` → `accessToken` | `authorizeServer` → `serverAuthCode` |
|---|---|---|
| **Üretilen Değer** | Kısa ömürlü OAuth Bearer `access_token` (~1 saat) | Tek kullanımlık OAuth Authorization Code |
| **Kullanım Yeri** | Doğrudan Android istemcisinden `https://www.googleapis.com/drive/v3/...` çağrıları | Gizli `client_secret` barındıran **harici bir bulut backend sunucusuna** gönderilip `refresh_token` takası yapmak |
| **Gerekli Kimlik Sırrı** | APK'da secret gerekmez (Web `serverClientId` yalnızca `initialize` kimliği içindir) | Takas için Web Application OAuth **`client_secret`** zorunludur |
| **MARKET MMS Pilot Uyumu** | **SEÇİLEN MODEL (Phase 2).** Android cihazlar yerel Hub kapalıyken bile (`ADR-021`) doğrudan Drive API'ye erişebilmelidir. | **PİLOTTA KULLANILMAZ.** MMS'te bulut SaaS backend sunucusu yoktur (`AGENTS.md` §2); Android APK içine Web `client_secret` gömülmesi kesinlikle yasaktır; Windows Master Hub da her zaman internete/cihaza açık bir merkezi token proxy'si değildir (Hub kapalıyken `ADR-021` çalışmak zorundadır). |

### 3.7 Uygulama Yeniden Başlatıldığında Oturum Davranışı
- `google_sign_in` v7'de eski sürümlerdeki senkron `currentUser` alanı yoktur; oturum durumu akış tabanlıdır (`GoogleSignIn.instance.authenticationEvents`).
- **Soğuk Başlatma (Cold Start) Akışı (Phase 2 Tasarımı):**
  1. Ön plan uygulama başlatılırken `MMS_GDRIVE_WEB_CLIENT_ID` tanımlıysa `await GoogleSignIn.instance.initialize(serverClientId: ...)` çağrılır.
  2. Ardından `await GoogleSignIn.instance.attemptLightweightAuthentication()` çağrısı yapılarak önceki oturumun sessizce geri yüklenmesi denenir.
  3. **Önemli Kısıt:** Credential Manager `attemptLightweightAuthentication()` çağrısı her cihaz/OS durumunda sıfır-UI ile sessiz geri yüklemeyi **%100 garanti etmez** (ör. kullanıcı hesap çıkışında veya Credential Manager oturum süresi dolduğunda `null` veya etkileşim ihtiyacı dönebilir).
  4. Bu nedenle Android istemcisi `AndroidKeystoreTokenStore` / yerel ayarlar içinde yalnızca **sır olmayan bağlantı durumu bayrağını** (`gdrive_connected_v1` ve isteğe bağlı hesap e-posta ipucu) tutar. Böylece soğuk başlatmada sessiz geri yükleme başarısız olursa uygulama "hiç bağlanmadı" gibi davranmak yerine operatöre belirgin **`ERR_DRIVE_REAUTH_REQUIRED`** ("Google Drive oturumu yeniden doğrulama bekliyor") bildirir; **yerel POS satışı ve Windows Hub senkronizasyonu bundan asla etkilenmez.**

### 3.8 Android Keystore ile Güvenli Saklama
- Mevcut `MmsSecureStorageChannelHandler.kt` (`AndroidKeyStore`, 256-bit `market_mms_master_key_v1`, `AES/GCM/NoPadding`, 12B rastgele IV + 128-bit GCM etiketi, `SharedPreferences`) altyapısı aynen korunur.
- `AndroidManifest.xml` (`allowBackup="false"`, `fullBackupContent="false"`) ve `res/xml/data_extraction_rules.xml` (`cloud-backup` & `device-transfer` tüm alanlar hariç) sayesinde şifreli tercihler ve `device_id` asla Google bulut yedeğine çıkmaz.
- **Neyin Keystore'da Saklanacağı / Saklanmayacağı:**
  - **Saklanır:** `backup_schedule_password` (yedek parolası), `drive_live_sync_secret_v1` (`ADR-021` ortak zarf gizlisi), Hub cihaz token'ı, ECDSA anahtarları ve opsiyonel sır-olmayan `gdrive_connected_v1` bağlantı meta bilgisi.
  - **Saklanmaz:** Kısa ömürlü `access_token` diske veya Keystore'a **yazılmaz** (yalnızca RAM'de tutulur); Android'de `refresh_token` veya `client_secret` zaten **yoktur**.
- **Fail-Closed Kuralı:** `KEYSTORE_ERROR` / kilitli Keystore durumunda düz metin fallback kesinlikle yapılmaz.

### 3.9 Background `JobScheduler` / `WorkManager` Erişimi *(Kritik Mimari Sınır)*
- **Mevcut Durum (Doğrulanmış):** `MmsBackgroundBackupJobService.kt` (`JobScheduler`, kanonik `JOB_ID = 70201`, `mmsBackgroundBackupEntrypoint`) şu anda arka planda headless `FlutterEngine` ile **yalnızca yerel şifreli `.mmsbak` yedeği üretir** (`background_backup_scheduler.dart:481-542`); `GoogleDriveBackupUploader` çağırmaz ve Drive OAuth'a bağımlı değildir.
- **Seçenek A (`google_sign_in`) Altında Teknik Kısıt (Çözülmemiş / Doğrulanmamış Sınır):**
  1. Android işletim sistemi arka plan `JobService` / `WorkManager` süreçlerinden etkileşimli izin/hesap seçici diyaloğu (`AuthorizationResult.hasResolution() == true` / `PendingIntent`) başlatılmasına **kesinlikle izin vermez**; aktif bir ön plan `Activity` yoksa UI gerektiren her OAuth adımı başarısız olur.
  2. Flutter `google_sign_in_android` (v7+) eklentisi Credential Manager / `AuthorizationClient` akışlarını eklenti yaşam döngüsü üzerinden **`ActivityPluginBinding` (`Activity`)** bağlamına yaslanarak yürütür; uygulama tamamen kapalıyken (`Force Stop` veya process kill sonrası) başlatılan headless `FlutterEngine` içinde `Activity` **yoktur**.
  3. Native Android `Identity.getAuthorizationClient(applicationContext)` yalnızca `Context` kabul etse ve kullanıcı önceden izin verdiyse (`hasResolution() == false`) teorik olarak sessiz token dönebilse bile, bu davranış `google_sign_in` Dart paketi üzerinden headless engine'de **kanıtlanmamıştır** ve `hasResolution() == true` veya token geçersizliği anında yine başarısız olacaktır.
- **Sonuç ve Güvenli Tasarım Kararı:**
  - **Kanıtlanmamış özellik destekleniyor gösterilmez:** Uygulama tamamen kapalıyken (`JOB_ID = 70201`) **katılımsız arka plan Google Drive yüklemesi Seçenek A ile garanti EDİLMEZ** ve **Phase 2 spike/fiziksel doğrulama gerektiren çözülmemiş teknik konu** olarak işaretlenir.
  - **Pilot Güvenli Davranışı:**
    - `MmsBackgroundBackupJobService` (`JOB_ID = 70201`) uygulama kapalıyken bile her zaman **yerel şifreli `.mmsbak`** üretimini `MmsSecureStorageChannelHandler` ile sürdürür (yerel veri kaybı olmaz).
    - Arka planda alınan ve henüz Drive'a yüklenmemiş `.mmsbak` dosyaları, `DriveUploadLedger` idempotency kontrolü sayesinde kullanıcı uygulamayı bir sonraki açışında (ön planda geçerli `Activity` + `accessToken` varken) otomatik olarak Drive'a yüklenir.
    - Phase 2'de ek native `applicationContext` tabanlı sessiz token denemesi araştırılabilir; ancak herhangi bir `MISSING_ACTIVITY`, `RESOLUTION_REQUIRED` veya `401` hatasında worker **fail-closed** davranmalı, yerel `.mmsbak` başarısını bozmamalı ve ön planda `ERR_DRIVE_REAUTH_REQUIRED` uyarısı yakmalıdır.
  - `ADR-021` hibrit canlı senkronizasyon (`BackgroundSyncCoordinator`) ön plan uygulama koordinatörü içinde çalışır; ön planda açık POS oturumu varken `Activity` bağlamı mevcuttur.

### 3.10 Sign-Out ve OAuth Erişimini İptal Etme (`disconnect` vs `signOut`)
- **`signOut()` vs `disconnect()` Farkı (`google_sign_in` v7):**
  - `GoogleSignIn.instance.signOut()`: Yalnızca cihazdaki yerel Credential Manager oturum önbelleğini temizler; Google sunucularında önceden verilmiş `drive.file` yetkisini iptal **etmez**.
  - `GoogleSignIn.instance.disconnect()`: Play Services `AuthorizationClient.revokeAccess()` çağrısını tetikleyerek **Google sunucularındaki uygulama OAuth erişimini iptal eder** ve yerel oturumu/önbelleği sıfırlar.
- **MMS "Bağlantıyı Kaldır" (`disconnect`) Akışı (Phase 2):**
  1. RAM önbelleğindeki `accessToken` için `clearAuthorizationToken(...)` çağrılır ve bellek içi token sıfırlanır.
  2. `await GoogleSignIn.instance.disconnect()` çağrılır (internet yoksa veya Play Services uzak iptali başarısız olursa yakalanır, yine de yerel `signOut()` + `gdrive_connected_v1` temizliği yapılır ve operatöre Google Hesap ayarlarından erişimi doğrulama bilgisi gösterilir).
  3. Yerel `.mmsbak` yedekleri, `outbox_operations`, `client_seq` ve satış geçmişine **asla dokunulmaz**.
- **Uzaktan İptal:** Kullanıcı Google Hesap → Güvenlik → Üçüncü taraf erişimleri üzerinden yetkiyi kaldırırsa bir sonraki Drive isteğinde `401` + başarısız sessiz yenileme sonucu `ERR_DRIVE_REAUTH_REQUIRED` üretilir; yerel POS ve Hub senkronizasyonu etkilenmez.

### 3.11 Google Cloud OAuth Yapılandırması *(Owner Sorumluluğu — `C1`/`C2`)*
Owner kontrolündeki (2FA korumalı) mağazaya özel tek bir Google Cloud projesinde şu yapılandırma gerekir:

1. **API Etkinleştirme:** **Google Drive API** etkinleştirilir.
2. **OAuth Consent Screen:**
   - Uygulama adı/destek bilgisi doldurulur.
   - Kapsam olarak **yalnızca** `https://www.googleapis.com/auth/drive.file` eklenir.
   - 7 günlük otomatik iptal sınırından kaçınmak için durum `"Testing"` yerine **`"In production"`** statüsüne alınır.
3. **Aynı Projede 3 OAuth 2.0 Client ID:**
   - **Desktop app Client ID (Windows Hub/Kasa):** Mevcut `--dart-define=MMS_GDRIVE_CLIENT_ID=<desktop-id>` (opsiyonel `MMS_GDRIVE_CLIENT_SECRET`).
   - **Android OAuth Client ID (Geliştirme + Üretim ayrı):** Paket adı `com.marketmms.market_pos` + signing keystore **SHA-1** parmak izi.
   - **Web Application OAuth Client ID (`serverClientId` — ZORUNLU):** `google_sign_in` v7+, Android üzerinde `GoogleSignIn.instance.initialize(serverClientId: ...)` için **Web Client ID** (tür: Web application) bekler; verilmezse `GoogleSignInExceptionCode.clientConfigurationError` oluşur.
     - İstemci derlemesine `--dart-define=MMS_GDRIVE_WEB_CLIENT_ID=<web-client-id>` (veya ayrı belirlenen sabit anahtar) ile verilir.
     - Web Client ID'nin `client_secret` değeri Android APK'sına **KESİNLİKLE** konulmaz.
     - Saf Google Cloud OAuth kurulumu yeterlidir; Firebase (`google-services.json`) zorunlu **değildir** (ve `.gitignore` ile repo dışındadır).

### 3.12 Android `applicationId` ve SHA-1 / SHA-256 Fingerprint Gereksinimleri
- **Paket Adı (`applicationId`):** `com.marketmms.market_pos` (`android/app/build.gradle.kts:37`).
- **SHA-1 Parmak İzi (Zorunlu):** Google Cloud Console → *Credentials → Create OAuth client ID → Android* ekranı **SHA-1 certificate fingerprint** gerektirir. Google Play Services çağrıcı APK'nın paket adı + sertifika SHA-1 eşleşmesini kriptografik olarak doğrular; uyuşmazlıkta `clientConfigurationError` / `DEVELOPER_ERROR` / `10:` hatası oluşur.
- **SHA-256 Parmak İzi (Kayıt ve Gelecek Uyum):** Ham Google Cloud Android OAuth Client ID formu SHA-1 isterken; `keytool -list -v` çıktısındaki **SHA-256** parmak izinin de Owner sertifika envanterinde kayıt altına alınması gerekir (Play App Integrity doğrulaması, olası Firebase/Google App Links genişlemesi ve Release APK sertifika doğrulaması `PAT-11` için).
- **Play App Signing Notu:** Pilot APK doğrudan imzalanıp cihaza kurulacaksa (`market_mms_upload.jks`) Upload/Release keystore SHA-1'i yeterlidir; uygulama ileride Google Play Store üzerinden **Play App Signing** ile dağıtılırsa Play Console (*Release → Setup → App integrity*) üzerindeki **App signing key certificate SHA-1** değeri de Google Cloud Android OAuth Client ID listesine eklenmelidir.

### 3.13 Development ve Release Signing Ayrımı
- **Debug / Geliştirme Ortamı:** Yerel geliştirici `debug.keystore` (`alias: androiddebugkey`) parmak izi yalnızca geliştirme amaçlı **ayrı bir Debug Android OAuth Client ID** üzerinde kullanılır; debug SHA-1 üretim/pilot OAuth istemcisine kalıcı bağımlılık olarak karıştırılmaz.
- **Pilot / Release Ortamı (`B1`):** Owner'ın depo dışında oluşturacağı `C:\MarketMMS-Secrets\market_mms_upload.jks` anahtarının SHA-1 parmak izi **Üretim Android OAuth Client ID** ile eşleştirilir.
- **Gradle Fail-Closed Koruma:** `android/app/build.gradle.kts:74-87` `android/key.properties` olmadan Release paketlemeyi durdurur (`BUILD FAILED`); `key.properties` ve `*.jks` `.gitignore` ile repo dışında tutulur.

### 3.14 OAuth Yapılandırması Eksik Olduğunda Fail-Safe Davranış
Aşağıdaki eksikliklerin hiçbirinde uygulama çökmez, yerel POS satışı durmaz ve Hub senkronizasyonu etkilenmez:
1. **`MMS_GDRIVE_WEB_CLIENT_ID` (veya platform OAuth ID) derlemede verilmemişse:**
   - Android tarafında `googleDriveConnectService` yapılandırılmamış kabul edilir (`isConfigured == false`), `googleDriveUploaderProvider` ve `driveLiveSyncEngineProvider` `null` döner.
   - UI'da mevcut `gdrive_not_configured_banner` uyarısı gösterilir; yerel şifreli yedekleme ve Hub senkronizasyonu kesintisiz devam eder.
2. **Cihazda Google Play Services (GMS) yoksa veya güncel değilse:**
   - `GoogleSignIn.instance.initialize` / `authenticate` hatası yakalanır, maskelenir ve kullanıcı dostu Türkçe hata koduna (`ERR_DRIVE_GMS_UNAVAILABLE` / `ERR_DRIVE_PLATFORM_UNSUPPORTED`) eşlenir; hata yutulmaz ama uygulama çökmez.
3. **SHA-1 / `serverClientId` yanlış yapılandırılmışsa:**
   - `GoogleSignInExceptionCode.clientConfigurationError` yakalanır, açık `ERR_DRIVE_NOT_CONFIGURED` / `ERR_DRIVE_REAUTH_REQUIRED` mesajıyla Tanılama kartında raporlanır; yerel DB, Outbox ve Hub bağlantısı korunur.

---

## 4. Hub-First Hibrit Senkronizasyon (`ADR-021`) ve Kriptografik Ayrım ile Uyumluluk

`google_sign_in` entegrasyonu `AGENTS.md` §4–5 ve `ADR-021` değişmezlerini **asla** değiştiremez:

1. **Hub Birincil Otorite:** `HubStatus == Online` iken Android istemcisi Google Drive'a **0 canlı senkronizasyon isteği** atar; `authorizationForScopes` dahi Hub çevrimiçiyken canlı senkron için tetiklenmez.
2. **Güvenlik Hatasında Fallback Yasağı:** `tlsPinMismatch`, `tlsCertError` ve `401/403 authRequired` (Hub auth) durumlarında Drive fallback **kesinlikle** açılmaz.
3. **Outbox ve `client_seq` Dokunulmazlığı:** Drive'a yüklenen işlemler `outbox_operations` tablosunda `PENDING`/`RETRY` kalır; yalnızca Windows Master Hub'dan gerçek ACK alındığında `SYNCED` işaretlenir. Echo-loop önlemi değişmez.
4. **Yedek Parolası vs `drive_live_sync_secret_v1` Ayrımı:**
   - `.mmsbak` (`MMSBAK01`, `"MARKET MMS Yedekleri"`): `backup_schedule_password` + PBKDF2 600.000 tur.
   - `.mmsenv` (`MMSENV01`, `"MARKET MMS LiveSync"`): `drive_live_sync_secret_v1` + `MMS-LIVESYNC-ENV-V1|<tenantId>|<storeId>` domain ayırıcısı + `DriveAuthorizedDeviceRegistry` (`ACTIVE`/`REVOKED`).
5. **`drive_live_sync_secret_v1` Dağıtım İhtiyacı (Phase 2 Ön Kararı — `K-05`):**
   - Hub kapalıyken iki cihazın birbirinin `.mmsenv` zarflarını çözebilmesi için aynı `drive_live_sync_secret_v1` sırrını paylaşması gerekir.
   - Dağıtım yöntemi (Dağıtım Seçeneği 1: Hub üzerinden TLS-pinned teslim vs Dağıtım Seçeneği 2: Owner manuel/QR kurulumu) **Phase 2 başlamadan önce** Owner tarafından netleştirilmelidir.

---

## 5. Riskler ve Azaltma Önlemleri

| Risk | Etki | Azaltma Önlemi |
|---|---|---|
| **Uygulama kapalıyken (`JOB_ID = 70201`) `google_sign_in` headless Drive upload belirsizliği** | Telefon tamamen kapalıyken yerel `.mmsbak` alınır ama Drive'a otomatik upload bir sonraki ön plan açılışına kalabilir | Phase 2'de yerel yedek + ön planda kuyruklu Drive upload garantilenir; headless `AuthorizationClient(applicationContext)` spike başarılı olursa ayrıca belgelenir |
| **OAuth "Testing" modu 7 gün token iptali** | 7 gün sonra arka plan/sessiz Drive erişimi durur | Google Cloud OAuth Consent Screen'i üretim (`"In production"`) durumuna alma; `ERR_DRIVE_REAUTH_REQUIRED` UI uyarısı |
| **Yanlış SHA-1 veya eksik Web `serverClientId`** | Release APK üzerinde `clientConfigurationError` ile bağlanma kırılır | `B1` Release keystore SHA-1 + Web Client ID (`MMS_GDRIVE_WEB_CLIENT_ID`) kurulumu + `PAT-13` Android doğrulaması |
| **GMS (Play Services) olmayan Android cihaz** | `google_sign_in` cihazda çalışmaz | Donanım envanterinde (`E1`) GMS doğrulaması; yoksa `ERR_DRIVE_GMS_UNAVAILABLE` ile güvenli uyarı ve yerel/Hub devamlılığı |
| **Token veya `drive_live_sync_secret_v1` log sızıntısı** | Yetkisiz Drive erişimi | `RedactingLogger` ile maskeleme; access token yalnızca RAM'de; zero secret in Git/logs/SQLite |

---

## 6. Uygulama Durumu ve Açık Kalan Operasyonel Maddeler

Phase 2 yazılım geliştirme kapsamı (22.11.2026) tamamlanmıştır; fiziksel cihaz ve dış Google Cloud / sertifika adımları Owner aksiyonu beklemektedir:

| # | Konu | 22.11.2026 Yazılım Durumu | Kalan Dış / Saha Ön Koşulu |
|---|---|---|---|
| 1 | `pubspec.yaml` içine `google_sign_in: ^7.2.0` bağımlılığının eklenmesi | **Eklendi & Android Debug APK ile Derlendi** | — |
| 2 | `AndroidGoogleSignInTokenProvider`, `drive_auth_providers.dart`, `GoogleDriveConnectService`, `backup_providers.dart`, `sync_providers.dart`, `ExternalBackupSection` ve `android_google_sign_in_oauth_test.dart` (9 test) | **Kodlandı & Test Edildi (Tam Yeşil)** | Fiziksel GMS'li Android cihazda canlı doğrulama (`PAT-13`, `PAT-18`) |
| 3 | Headless `MmsBackgroundBackupJobService` (`70201`) içinden Drive yükleme kabiliyeti | **Güvenli Fallback Aktif (Garanti Edilmez)** | Yerel `.mmsbak` her durumda üretilir; bekleyen yüklemeler ön plan açılışında `DriveUploadLedger` ile idempotent tamamlanır |
| 4 | Google Cloud OAuth (`C1/C2`: Desktop + Android SHA-1 + Web `serverClientId`, "In production") | **Owner Aksiyonu (Dış Hesap)** | `B1` Release keystore sonrası Owner tarafından kurulacak |
| 5 | `drive_live_sync_secret_v1` dağıtım modeli (`K-05` Seçenek 1) | **Kodlandı & Test Edildi (Tam Yeşil)** | Hub TLS-pinned `GET /api/v1/sync/live-drive-config` + `FileDriveAuthorizedRegistryStore` |
| 6 | Fiziksel Android testleri (`PAT-13`, `PAT-16`, `PAT-17`, `PAT-18`) | **`BLOCKED — PHYSICAL HARDWARE REQUIRED`** | `B1` + `B2` + `C1/C2` sonrası gerçek cihazda yürütülecek |

---

**ADR-022 Durumu:** **`CONFIRMED — TECHNICALLY IMPLEMENTED`** *(Seçenek A `google_sign_in: ^7.2.0` yazılım implementasyonu ve 9 otomatik senaryosu + Android Debug APK derlemesi geçmiştir; gerçek Google Cloud `C1/C2` ve fiziksel cihaz saha doğrulaması `PAT-13/17/18` beklenmektedir.)*
