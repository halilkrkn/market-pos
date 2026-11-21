# MARKET MMS — RELEASE 1.0 / PHASE 1 TESLİMAT DOĞRULAMA VE DURUM SABİTLEME RAPORU

- **Tarih:** 21 Kasım 2026
- **Kapsam:** Release 1.0 Yazılım Teslimat Denetimi (GitHub `main` / commit `a02a3c66edb3d580c047a02557057acf7d6fa573` sonrası salt-okunur doğrulama)
- **Resmî Release 1.0 Durumu:** **`TECHNICALLY COMPLETE — PHYSICAL VALIDATION REQUIRED`**
- **Politika:** Bu rapor salt-okunur denetim çıktısıdır. Hiçbir mevcut kaynak/test/konfigürasyon/doküman dosyası değiştirilmemiş, veritabanı/token/pepper/sertifika/imza anahtarına dokunulmamış, `MarketMmsSpike01` servisi korunmuş ve Git commit/push/reset/clean/checkout yapılmamıştır.

---

## 1. Git ve Commit Doğrulaması

| Denetim Kalemi | Gözlenen Durum | Statü |
|---|---|---|
| Aktif branch ve remote takibi | `git branch --show-current` → `main`; `git status -sb` → `## main...origin/main` (`https://github.com/halilkrkn/market-pos.git`) | `VERIFIED` |
| `HEAD` == `origin/main` eşleşmesi | Yerel `HEAD` = `a02a3c66edb3d580c047a02557057acf7d6fa573`; `origin/main` = `a02a3c66edb3d580c047a02557057acf7d6fa573` | `VERIFIED` |
| Commit mesajı ve kapsamı | `a02a3c6 feat(market-mms): complete release 1.0 software implementation` (`54` dosya: `40` güncellenen, `14` yeni; önceki commit `1615606`) | `VERIFIED` |
| Çalışma ağacı temizliği (tracked / staged) | `STAGED_COUNT=0`, `UNSTAGED_MODIFIED_COUNT=0` (hiçbir izlenen dosyada değişiklik yok) | `VERIFIED` |
| Commit dışı yerel dosyaların korunumu | `.vscode/settings.json`, `run_windows_client.bat`, `start_master_hub.bat`, `stop_master_hub.bat` untracked olarak aynen korundu | `VERIFIED` |
| Hassas dosyalar ve test servisi korunumu | Veritabanı, token, pepper, sertifika, signing key dosyası commit'te yok (`SENSITIVE_MATCHES=0`); `MarketMmsSpike01` dokunulmadı (`Running/Automatic`) | `VERIFIED` |

---

## 2. Dokümantasyon Tutarlılığı

### 2.1 İncelenen Belgeler ve Gerçek Konumlar
- Kök belgeler: `PHYSICAL_ACCEPTANCE_TEST_PLAN.md`, `OWNER_ACTION_CHECKLIST.md` (`VERIFIED`)
- `docs/` belgeleri: `docs/RELEASE_1_0_FINAL_DELIVERY_REPORT.md`, `docs/MASTER_ROADMAP.md`, `docs/LIVE_PROJECT_STATUS.md`, `docs/PILOT_TECHNICAL_REMEDIATION_REPORT.md`, `docs/PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md`, `docs/PILOT_PROTOCOL_BLOCKERS_FINAL_REVIEW_REPORT.md` (`VERIFIED`)
- ADR gerçek konumları (`docs/decisions/`):
  - `docs/decisions/README.md` (`ADR-001…ADR-021` indeksi) (`VERIFIED`)
  - `docs/decisions/020-android-background-backup-workmanager.md` (`ADR-020`) (`VERIFIED`)
  - `docs/decisions/021-hybrid-hub-google-drive-live-sync.md` (`ADR-021`) (`VERIFIED`)
- Sürüm kılavuzları: `docs/release/ANDROID_RELEASE.md`, `docs/release/WINDOWS_HUB_RELEASE.md` (`VERIFIED`)

### 2.2 Ana İlke ve Kapsam Uyum Kontrolleri
- **Release 1.0 teslimat durumu ve fiziksel doğrulama sınırı:** `RELEASE_1_0_FINAL_DELIVERY_REPORT.md`, `LIVE_PROJECT_STATUS.md`, `MASTER_ROADMAP.md` ve `OWNER_ACTION_CHECKLIST.md` belgeleri durumu `TECHNICALLY COMPLETE — PHYSICAL VALIDATION REQUIRED` ve `FAZ KABULÜ BEKLİYOR` olarak korur; `MASTER_ROADMAP.md` içindeki Faz 1–7 kabul sütunları değiştirilmemiştir (`VERIFIED`).
- **`PAT-01…PAT-18` durumu:** `PHYSICAL_ACCEPTANCE_TEST_PLAN.md:3,326` üzerinde `PAT-01…PAT-18` maddelerinin tamamı `BLOCKED` (çalıştırılmadı) olarak korunmaktadır (`VERIFIED`).
- **`ADR-021` Hub-öncelikli Google Drive hibrit canlı senkronizasyon:** Hub birincil otorite (`HubStatus == Online` iken 0 Drive trafiği), `MMSENV01` zarf kriptografisi, `tlsPinMismatch`/`tlsCertError`/`401-403` durumlarında fallback yasağı, non-LWW `PRODUCT_UPSERT` çakışma bayrağı ve echo-loop/`outbox_operations` korunumu hem `ADR-021`'de hem `LIVE_PROJECT_STATUS.md` ve `RELEASE_1_0_FINAL_DELIVERY_REPORT.md`'de doğru belgelenmiştir (`VERIFIED`).

### 2.3 Tespit Edilen Dokümantasyon Tutarsızlıkları ve Eski İfadeler *(Kod/doküman bu denetimde değiştirilmemiştir)*
1. **`PAT-16` Android `JobScheduler` Job ID uyuşmazlığı:** `PHYSICAL_ACCEPTANCE_TEST_PLAN.md:293` manuel test komutunda `202611` (`adb shell cmd jobscheduler run -f com.marketmms.market_pos 202611`) yazarken, gerçek Kotlin kodu `android/app/src/main/kotlin/com/marketmms/market_pos/MmsBackgroundBackupJobService.kt:26` içinde `JOB_ID = 70201` tanımlıdır. Yanlış ID fiziksel `PAT-16` testini doğrudan başarısız gösterir (`NOT_VERIFIED` · `REQUIRES_OWNER_APPROVAL`).
2. **`PAT-16` / `PAT-17` tanım kayması:** `docs/RELEASE_1_0_FINAL_DELIVERY_REPORT.md:117` satırında `PAT-16` "Windows FFI canlı doğrulaması" ve `PAT-17` "re-pairing çökme kurtarması" olarak geçerken; `PHYSICAL_ACCEPTANCE_TEST_PLAN.md:287-307` içinde `PAT-16` "Android Uygulama Kapalıyken Arka Plan Şifreli Yedekleme" ve `PAT-17` "Google Drive Gerçek Hesap ile Yedek Listeleme, Kesintili İndirme ve Kontrollü Geri Yükleme" olarak tanımlıdır (`NOT_VERIFIED` · `REQUIRES_OWNER_APPROVAL`).
3. **`OWNER_ACTION_CHECKLIST.md` iç çelişkileri (eski bölümler güncellenmemiş):**
   - Özet tablo satır `A1`, `A4`, `A5`, `A6` (satır `22, 25–27`) Release 1.0 (`P-BLOCK-1..3`, `ADR-020 JobScheduler`, `ADR-021`) uygulamalarını yansıtırken; detay bölüm `A1` tablosu (satır `56–61`) hâlâ `ADR-018 P-BLOCK-1..3` için düzeltme onayı beklediğini, `ADR-020`'nin `DEFERRED_POST_PILOT` ("uygulama açıkken yedek sınırı") olduğunu ve yalnızca `PAT-01…PAT-15` bulunduğunu yazmakta; `ADR-021` satırını ise hiç içermemektedir (`NOT_VERIFIED` · `REQUIRES_OWNER_APPROVAL`).
   - `A2` (satır `65–66`): Hâlâ "~200 commit edilmemiş dosya ve commit edilmedi" bilgisini taşır (`NOT_VERIFIED`).
   - `A6` detay bölümü (satır `100–110`) ve `C` bölümü (satır `14, 177–180`): Release 1.0 hibrit Drive canlı senkronizasyonu (`ADR-021`) ile ilişkili ortak `drive_live_sync_secret_v1` kararını/kapsamını açıklamadan Drive'ı yalnızca opsiyonel yedekleme olarak listeler (`NOT_VERIFIED` · `REQUIRES_OWNER_APPROVAL`).
4. **`ADR-021` Drive klasör adı farkı:** `docs/decisions/021-hybrid-hub-google-drive-live-sync.md:41` klasör adını `MMS LiveSync/` olarak belirtirken, gerçek uygulama kodu `packages/mms_client_storage/lib/src/sync/hybrid_drive_live_sync.dart:878` `GoogleDriveLiveEnvelopeTransport.folderName = 'MARKET MMS LiveSync'` kullanır (`NOT_VERIFIED`).
5. **Commit-öncesi Git durum ifadelerinin güncelliğini yitirmesi:** `docs/RELEASE_1_0_FINAL_DELIVERY_REPORT.md:9,34,123` ve `docs/LIVE_PROJECT_STATUS.md:4,22,28` artık `a02a3c6` `origin/main`'e push edildiği için tarih dışı kalan "commit/push yapılmamıştır / `origin/main` `8454933`" ifadelerini taşır (`NOT_VERIFIED`).
6. **`PHYSICAL_ACCEPTANCE_TEST_PLAN.md` eski referanslar:** Önerilen yürütme sırası (satır `7–8`) `PAT-16..PAT-18`'i içermez; `PAT-03` 2. adım (satır `81`) sanki `P-BLOCK-1..3` hâlâ düzeltilmemiş gibi yönlendirme içerir (`NOT_VERIFIED` · `REQUIRES_OWNER_APPROVAL`).
7. **`PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md` ve `FINAL_REVIEW_REPORT.md` iç çelişkisi:** `docs/PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md:8-10` ve `docs/PILOT_PROTOCOL_BLOCKERS_FINAL_REVIEW_REPORT.md:7-8` bloklarındaki eski "hiçbir kaynak/test dosyası değiştirilmemiştir / salt okunur" uyarıları satır `3` içindeki güncel `IMPLEMENTED` statüsüyle çelişmektedir (`NOT_VERIFIED`).
8. **Hub `server.crt` `IP:127.0.0.1` loopback SAN ve `advertise_host` dokümantasyon eksikliği:** `OWNER_ACTION_CHECKLIST.md:164` (`B2`), `docs/release/WINDOWS_HUB_RELEASE.md` ve `test_spikes/spike_01_backend/config/hub_config.example.json` belgeleri yeni eklenen `advertise_host` anahtarını ve `HUB-T07` tarafından startup'ta çıkış kodu `78` ile zorunlu kılınan `IP:127.0.0.1` loopback SAN şartını henüz açıklamamaktadır (`NOT_VERIFIED` · `REQUIRES_OWNER_APPROVAL`).

---

## 3. Test Sonuçları ve Doğrulama Seviyesi

| Süit / Kontrol | Önceki Bildirilen (`RELEASE_1_0_FINAL_DELIVERY_REPORT`) | Commit (`a02a3c6`) Öncesi Doğrulama (`task-843`/`848`) | Commit (`a02a3c6`) Sonrası Salt-Okunur Audit (`task-941`/`950`) | Doğrulama Statüsü |
|---|---|---|---|---|
| `packages/mms_contracts` | `7/7` (`dart analyze`: `0`) | `7/7` geçti (`dart analyze`: `No issues found!`) | Bu audit oturumunda tekrar koşulmadı *(commit öncesi son düzenlemeden sonra `x509_pre_validator.dart` dışı değişiklik yok)* | `NOT_VERIFIED` *(commit sonrası tam tekrar koşulmadı; commit öncesi `task-843` `VERIFIED`)* |
| `packages/mms_client_storage` (`225/225`) | `225/225` (`dart analyze` çıkış `0`, 16 pre-existing `sqlite3 dispose` info) | `225/225` geçti | `dart analyze lib/src/security/x509_pre_validator.dart` → `No issues found!` (`exit 0`) | Kısmi `VERIFIED` (`x509` analiz) · `225/225` tam tekrar `NOT_VERIFIED` *(comment trailing-space edit sonrası yalnızca `x509` analiz + alıcı/hub pblock testleri koşuldu)* |
| `test_spikes/spike_01_backend` (`245/245`) | `245/245` (`dart analyze` çıkış `0`, 18 pre-existing `sqlite3 dispose` info) | `245/245` geçti | `dart test test/pblock_1_3_hub_test.dart` → **`13/13` geçti** (`exit 0`) | `pblock_1_3_hub_test` (`13/13`) `VERIFIED` · kalan 232 test commit sonrası tekrar `NOT_VERIFIED` |
| Kök `market_pos` (`295/295`) | `295/295` (`flutter analyze`: `0`) | `295/295` geçti | `flutter test test/features/security/pblock_1_2_client_test.dart` → **`5/5` geçti** (`exit 0`) | `pblock_1_2_client_test` (`5/5`) `VERIFIED` · kalan 290 test commit sonrası tekrar `NOT_VERIFIED` |
| Toplam Dart/Flutter (`772/772`) | `772/772` | `772/772` (commit öncesi `a02a3c6` aşamasındaki 2-satır `//` yorum boşluk düzeltmesi hemen öncesinde koşuldu) | Hedefli `18/18` P-BLOCK/X.509 testi (`5 + 13`) + `x509` static analyze koşuldu ve geçti | Hedefli `18/18` `VERIFIED`; `772/772` commit sonrası tam koşum `NOT_VERIFIED` |
| Android `:app:compileDebugKotlin` | `BUILD SUCCESSFUL in 2m 28s` | `exit 0` (`task-848`) | Bu audit oturumunda tekrar koşulmadı *(Kotlin/Gradle dosyaları commit öncesi ve sonrası özdeş)* | `VERIFIED` (commit `a02a3c6` içeriğiyle birebir; commit sonrası tekrar çalıştırılmadı) |
| `integration_test/` (`2` dosya) & `PAT-01…PAT-18` | `BLOCKED — NOT RUN` | Çalıştırılmadı | Çalıştırılmadı | `BLOCKED` |

> **Önemli Doğruluk Notu:** Commit `a02a3c6` sırasında yalnızca `packages/mms_client_storage/lib/src/security/x509_pre_validator.dart` (satır `213` ve `218` yorum sonu boşluğu) ile 2 dokümandaki satır sonu boşluğu temizlenmiş; çalışma mantığı değişmemiştir. Buna karşın tam 4 paket (`772/772`) tekrar çalıştırması commit `a02a3c6` sonrasında yinelenmemiş, yalnızca doğrudan etkilenen `x509_pre_validator.dart` statik analizi ile `pblock_1_2_client_test.dart` (`5/5`) ve `pblock_1_3_hub_test.dart` (`13/13`) testleri commit sonrası güvenlik doğrulaması olarak çalıştırılıp geçmiştir.

---

## 4. Release 1.0 Mevcut Durumu

- **Kod ve Otomatik Test Tabanı:** Release 1.0 fazları (`Faz A–F`: `P-BLOCK-1..3`, `ADR-020` `JobScheduler`, Drive yedek listeleme/indirme/kontrollü restore, `ADR-021` hibrit Drive canlı senkronizasyon) GitHub `origin/main` üzerinde `a02a3c66edb3d580c047a02557057acf7d6fa573` commit'iyle sabitlenmiştir (`VERIFIED`).
- **Yol Haritası ve Kabul Statüsü:** Hiçbir `Faz 1–7` maddesi Owner tarafından resmî olarak kabul edilmemiştir; `TECHNICALLY COMPLETE — PHYSICAL VALIDATION REQUIRED` ve `FAZ KABULÜ BEKLİYOR` statüleri geçerlidir (`VERIFIED`).

---

## 5. Android Release Hazırlık Eksikleri

1. **`B1` — Üretim İmza Anahtarı Yok (`android/key.properties` & `.jks`):** Disk denetiminde `android_key_props_exists=False` gözlenmiştir. `android/app/build.gradle.kts:80-86` gereği `key.properties` olmadan `flutter build apk --release` fail-closed olarak durur (`BLOCKED` · `REQUIRES_OWNER_APPROVAL`).
2. **Sürüm Numarası Uyumsuzluğu (`pubspec.yaml:5` vs `package_android_release.ps1`):** `pubspec.yaml:5` hâlâ `version: 0.1.0+1` değerindedir; `scripts/package_android_release.ps1:3,45` çıktı dosyasını `market_mms_v1.0.0.apk` adıyla kopyalarken `flutter build apk --release` komutuna `--build-name`/`--build-number` geçirmez. Release 1.0 APK'nın uygulama içi sürüm metadatası `0.1.0` kalacaktır (`NOT_VERIFIED` · `REQUIRES_OWNER_APPROVAL`).
3. **Android NDK Sürüm Uyarısı:** `android/app/build.gradle.kts:29` içinde `ndkVersion = "27.0.11718014"` tanımlıdır; `:app:compileDebugKotlin` (`task-848`) sırasında `integration_test` ve `mobile_scanner` eklentilerinin `28.2.13676358` istediği Gradle uyarısı görülmüştür (`NOT_VERIFIED` · `REQUIRES_OWNER_APPROVAL`).
4. **Android Google Drive Doğrudan OAuth Akışı Eksikliği:** `lib/features/backup/application/google_drive_connect_service.dart:96-100` üzerinde `_openWithSystemBrowser` Windows dışında `ERR_DRIVE_PLATFORM_UNSUPPORTED` fırlatmaktadır ve `pubspec.yaml` içinde `google_sign_in` bağımlılığı yoktur; Android yalnızca `saveRefreshToken` manuel/harici token aktarımıyla veya ileri aşama SDK entegrasyonuyla bağlanabilir (`BLOCKED` · `REQUIRES_OWNER_APPROVAL`).
5. **Release APK Üretimi ve Fiziksel Cihaz Doğrulaması (`PAT-01`, `PAT-11`, `PAT-15`, `PAT-16`):** İmzalı Release APK derlemesi, `usesCleartextTraffic="false"` / `allowBackup="false"` merged manifest kontrolü, Android Keystore cihaz reboot kalıcılığı ve kapalı uygulamada `JobScheduler` (`JOB_ID = 70201`) çalıştırması fiziksel Android cihazda hiç denenmemiştir (`BLOCKED`).

---

## 6. Windows Master Hub Hazırlık Eksikleri

1. **`B2` — Üretim TLS Sertifikaları Yok:** `ca.crt`, `server.crt` (hem Hub LAN IP/hostname hem zorunlu `IP:127.0.0.1` loopback SAN içermeli) ve `server.key` dosyaları henüz hazırlanmamıştır (`BLOCKED` · `REQUIRES_OWNER_APPROVAL`).
2. **Eski Test Servisi Aktif & Üretim Servisi Kurulmamış (`D1` / `PAT-08`):** Denetimde `MarketMmsSpike01=Running/Automatic` ve `MarketMMSService=NOT_FOUND` olarak gözlenmiştir (`BLOCKED` · `REQUIRES_OWNER_APPROVAL`).
3. **Güncel AOT İkili (`mms_backend.exe`) Yeniden Derlenmemiş:** `test_spikes/spike_01_backend/build/mms_backend.exe` diskte bulunmakla birlikte `a02a3c6` sonrası güncel kaynak kodla `build_aot.ps1` çalıştırılarak yeniden derlendiği doğrulanmamıştır (`NOT_VERIFIED`).
4. **D2–D4 Test Kalıntıları Temizliği:** `manual_test_env/` test token'ları, şifresiz test DB kopyaları (`spike_master.db`, `market_master.db*`) ve eski koruyucu kopyalar Owner temizlik kararını beklemektedir (`REQUIRES_OWNER_APPROVAL`).
5. **Windows SCM / `LocalService` ACL / Firewall & Failover Fiziksel Doğrulaması (`PAT-08..10`):** PowerShell 5.1 kurulum, `bin.previous` rollback, standart kullanıcı erişim engeli ve Windows x64 `GetAdaptersAddresses`/`GetIfEntry2` canlı FFI saha testi fiziksel ortamda yürütülmemiştir (`BLOCKED`).
6. **Hub Yapılandırma Doküman Eksikliği ve Bilinen Düşük Borç:** `hub_config.example.json` ile `WINDOWS_HUB_RELEASE.md` henüz `advertise_host` ve `IP:127.0.0.1` SAN zorunluluğunu belgelememektedir (`NOT_VERIFIED`). Düşük öncelikli `L-3` (`WindowsDpapiTokenStore.readSecret`) açık teknik borç olarak durmaktadır (`NOT_VERIFIED`).

---

## 7. Google Drive OAuth ve Entegrasyon Hazırlık Eksikleri

1. **`C1 / C2` — Google Cloud Projesi ve OAuth `client_id` Yok:** Gerçek Google Cloud projesi, `drive.file` kapsamlı OAuth izin ekranı ve `--dart-define=MMS_GDRIVE_CLIENT_ID=...` yapılandırması tanımlanmamıştır (`BLOCKED` · `REQUIRES_OWNER_APPROVAL`).
2. **Android Tarafı Drive OAuth Yöntem Boşluğu:** Windows loopback OAuth çalışacak şekilde tasarlanmıştır ancak Android cihazlarda doğrudan tarayıcı/SDK OAuth akışı `pubspec.yaml`'da `google_sign_in` olmadığı için kapalıdır; Owner'ın tek-Windowslı / harici-token mı yoksa `google_sign_in` eklentili tam mobil OAuth mu istediği netleştirilmelidir (`BLOCKED` · `REQUIRES_OWNER_APPROVAL`).
3. **Paylaşılan `drive_live_sync_secret_v1` ve `DriveAuthorizedDeviceRegistry` Saha Dağıtım Akışı:** 2 cihazlı Drive canlı senkronizasyonunun (`ADR-021`) ilk kurulumda cihazlar arası güvenli ortak sır (`drive_live_sync_secret_v1`) paylaşım ve yetkilendirme prosedürü gerçek cihazlarda sınanmamıştır (`NOT_VERIFIED` · `REQUIRES_OWNER_APPROVAL`).
4. **Gerçek Drive API Fiziksel Testleri (`PAT-13`, `PAT-17`, `PAT-18`):** OAuth token yenileme/iptal, `.part` indirme, ön doğrulamalı restore ve 2 cihazlı Hub-kapalı hibrit canlı senkron + Hub dönüş uzlaştırması yalnızca mock/yerel testlerde geçmiştir; gerçek Google API üzerinde çalıştırılmamıştır (`BLOCKED`).

---

## 8. Fiziksel Test Engelleri

- Tüm **`PAT-01…PAT-18`** testleri donanım (`E1`), Android signing key (`B1`), Hub TLS sertifikaları (`B2`), Drive OAuth (`C1/C2`) ve test servisi kaldırma (`D1`) ön koşulları nedeniyle `BLOCKED` durumundadır.
- **`PAT-16` bloklayıcı plan hatası:** `PHYSICAL_ACCEPTANCE_TEST_PLAN.md:293` komutu yanlış Job ID (`202611`) içerdiğinden düzeltilmeden yürütülemez (`REQUIRES_OWNER_APPROVAL`).
- **`RELEASE_1_0_FINAL_DELIVERY_REPORT.md:117` ↔ `PHYSICAL_ACCEPTANCE_TEST_PLAN.md` uyumsuzluğu:** Windows FFI (`HUB-T04c`) ve crash-safe re-pairing (`APP-T16`) için ayrı fiziksel test kontrol adımlarının netleştirilmesi gerekir (`REQUIRES_OWNER_APPROVAL`).

---

## 9. Pilot Öncesi Owner Kararları

1. **Doküman & Test Planı Uzlaştırma Onayı (`REQUIRES_OWNER_APPROVAL`):**
   - `PHYSICAL_ACCEPTANCE_TEST_PLAN.md:293` `PAT-16` Job ID'sinin `70201` olarak düzeltilmesi, yürütme sırasına `PAT-16..18` eklenmesi ve `PAT-03` notunun güncellenmesi.
   - `RELEASE_1_0_FINAL_DELIVERY_REPORT.md`, `OWNER_ACTION_CHECKLIST.md`, `LIVE_PROJECT_STATUS.md`, `ADR-021` (`'MARKET MMS LiveSync'`) ve `WINDOWS_HUB_RELEASE.md` / `hub_config.example.json` (`advertise_host` + `IP:127.0.0.1` SAN) tutarsızlıklarının senkronize edilmesi.
2. **Android Release Hazırlık Kararları (`REQUIRES_OWNER_APPROVAL`):**
   - `pubspec.yaml:5` `version: 1.0.0+1` güncellemesi (veya `package_android_release.ps1`'e `--build-name`/`--build-number` eklenmesi) ve `android/app/build.gradle.kts:29` `ndkVersion` (`28.2.13676358` yükseltmesi mi yoksa mevcut `27.0.11718014` mü) kararı.
   - **`B1` (Kritik Engel):** `market_mms_upload.jks` ve `android/key.properties` dosyalarının Owner tarafından depo dışında oluşturulması.
3. **Android Google Drive OAuth Kararı (`A6` / `C1–C2`) (`REQUIRES_OWNER_APPROVAL`):**
   - Android istemcide Google Drive için `google_sign_in` paketi eklenecek mi, yoksa Android Drive şifreli canlı senkron / yedekleme ilk pilotta devre dışı mı/manuel token aktarımına mı dayalı olacak?
   - `C1–C2` Google Cloud OAuth kurulumunun Day-1 pilot zorunluluğu mu yoksa Faz 3/sonradan etkinleştirilecek adım mı olacağı.
4. **Windows Hub Üretim Geçiş ve Temizlik Kararları (`B2`, `D1–D4`) (`REQUIRES_OWNER_APPROVAL`):**
   - `IP:127.0.0.1` + LAN IP/hostname SAN içeren `server.crt` + `ca.crt` üretimi (`B2`).
   - `MarketMmsSpike01` servisinin kaldırılma zamanı (`D1`) ve `manual_test_env/` + eski `safety_snapshot_*.db` dosyalarının temizlenmesi (`D2–D4`).
5. **Diğer Açık Pilot Kararları (`REQUIRES_OWNER_APPROVAL`):**
   - `A7` (QR görseli paketi eklenecek mi?), `A8` (kod imzalama / merkezi tanı ucu), `ADR-017` `PAT-12` sonrası kesin onay ve `ADR-019` (%20 KDV operasyonel sınırlarının pilotta kabulü).

---

## 10. Bir Sonraki Aşamaya Geçiş Önerisi

- **Phase 2 (Android Release Hazırlığı) Geçiş Değerlendirmesi:** **HENÜZ DOĞRUDAN GEÇİLEMEZ (`BLOCKED` / `REQUIRES_OWNER_APPROVAL`)** — yazılımsal özellik geliştirme ve Debug Kotlin derlemesi hazır olsa da:
  1. **Teknik/İmzalanabilir Release Engeli (`B1`):** `android/key.properties` ve `.jks` keystore olmadan Gradle `assembleRelease` / `flutter build apk --release` fail-closed olarak kırılır (`BUILD FAILED`).
  2. **Sürüm ve Kapsam Belirsizliği:** `pubspec.yaml:5` sürümü (`0.1.0+1`) ile Release 1.0 sürümleme uyumu ve Android tarafı Google Drive OAuth (`A6`: `google_sign_in` dahil edilecek mi?) netleşmeden üretilecek Release APK eksik veya yanlış sürüm etiketli olacaktır.
  3. **Saha Test Planı Düzeltmesi:** `PAT-16` (`202611` → `70201`) ve doküman tutarsızlıkları düzeltilmeden fiziksel kabul aşamasına güvenle geçilemez.

- **Önerilen Kontrollü Geçiş Sırası:**
  1. **Adım 1 (Owner Onayıyla Küçük Uyum Düzeltmesi — Phase 1.5):** Yukarıdaki 8 dokümantasyon/test-planı tutarsızlığının düzeltilmesi + `pubspec.yaml` `1.0.0+1` + `ndkVersion` kararının netleştirilmesi + tam `772/772` süitinin temiz commit sonrası tek sefer teyit edilmesi.
  2. **Adım 2 (Owner Gizli/Sertifika Hazırlığı):** Owner tarafından `B1` (`key.properties` + `.jks`) ve kararlaştırılırsa `A6`/`C1–C2` Drive OAuth seçiminin tamamlanması.
  3. **Adım 3 (Phase 2 — Android Release Derleme & Manifest Doğrulama):** `flutter build apk --release` / `package_android_release.ps1` çalıştırılıp `.sha256` ve birleşik manifestin (`usesCleartextTraffic="false"`, `allowBackup="false"`, gerçek imza sertifikası) doğrulanması, ardından `PAT-11` → `PAT-16` ile sahaya inilmesi.

---

**Audit Durumu:** **`TECHNICALLY COMPLETE — PHYSICAL VALIDATION REQUIRED`** · **`REQUIRES_OWNER_APPROVAL`**
