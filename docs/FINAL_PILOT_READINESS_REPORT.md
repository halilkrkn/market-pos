# MARKET MMS — Nihai Pilot Hazırlık Raporu (Hat A + Hat B)

- **Güncelleme:** 23 Kasım 2026, 2. tur — Commit öncesi bağımsız inceleme bulgularının (S1–S6) ve ikincil barkod arayüzü eksikliğinin giderilmesi
- **Önceki sürüm:** 23 Kasım 2026 1. tur (Hat A + Hat B devralma turu) — tarihsel içerik **Ek-23K** bölümünde, o tarihin sayılarıyla korunmuştur.
- **Hazırlayan:** Claude Code
- **Repository / Dal / HEAD:** `C:\Users\halil\Github\market-pos` · `main` · `817f881` (bu turda **commit / stage / push / reset / checkout / clean / stash yapılmadı**)
- **Okuyucu:** Owner (commit ve pilot kararları) ve bağımsız teknik inceleyici.

---

## A. Genel Sonuç

| Soru | Cevap |
|---|---|
| **Durum** | **Kısmen tamamlandı.** Yazılım ve otomatik test kapsamındaki tüm maddeler (S1–S6, ikincil barkod UI, dokümantasyon) tamamlandı ve gerçek koşumlarla doğrulandı. Fiziksel doğrulama gerektiren maddeler (gerçek Windows Service/LocalService, gerçek Google Drive/OAuth, fiziksel Android/kamera) **çalıştırılmadı — `BLOCKED`**. |
| **Otomatik testler** | Son kod durumunda her takımın en az bir tam koşumu tamamen yeşil: **898 geçti / 0 atlanan** (`mms_client_storage` 248 · `mms_contracts` 7 · Hub 292 · kök 351). Aynı koşum dizisinin paralel `mms_client_storage` koşusunda bu turda **dokunulmamış** `backup_operation_lock_test` #14 **1 kez kaldı** (kararsız; `-j 1` ve tekrarlarda geçti — §E, §H) (§E). |
| **Pilot hazırlığına etkisi** | Pilot öncesi iki ciddi risk kapandı: Hub yedek zamanlayıcısının servisi düşürebilmesi (S1) ve hatırlanmayan parolayla Drive yedeği oluşabilmesi (S2). İkincil barkod artık gerçekten ekrandan yönetilebiliyor. **Proje yine de pilota hazır DEĞİLDİR:** `PAT-01…PAT-20` ve `BK-PAT-01…BK-PAT-18` fiziksel testlerinin hiçbiri yapılmadı; Owner adımları `B1`, `B2`, `B3`, `C1/C2`, `D1–D4`, `E1/E2` bekliyor. |
| **Commit önerisi** | Kod ve testler **bağımsız incelemeye ve commit'e hazır**; önerilen mantıksal gruplar §I'da. Commit kararı Owner'ındır. |

---

## B. S1–S6 Bulgu Sonuçları

### S1 — Hub zamanlayıcısının yakalanmamış asenkron hatası
- **Önceki problem:** `HubBackupOrchestrator.start()` her dakika `evaluateTick()` çağırıyor, sonucunu beklemiyor ve hata yakalamıyordu. Kilit meşgulken (`ERR_BACKUP_OPERATION_BUSY`), kurtarma parolası kasası okunamazken (`ERR_DPAPI_RECOVERY_KEY`) veya durum dosyası G/Ç hatasında fırlayan hata yakalanmamış zone hatası olarak Hub sürecini sonlandırabiliyordu.
- **Değişiklik:** Tek güvenli giriş noktası `runGuardedTick()` (dakikalık tur + servis açılışı aynı yol). Kilit çakışması hata sayılmaz → iş kaydı oluşturmadan sonraki tura ertelenir. Diğer hatalar yakalanır, aynı hata bir kez loglanır (sessizce yutulmaz), `GET /api/v1/backup/status` → `scheduler_last_error` ile raporlanır; başarılı turda temizlenir. Önceki tur sürerken yeni tur başlamaz. `INITIAL_ENABLE` kilit meşgulse zamanlama yine kaydedilir, tur `CATCH_UP` ile yakalar (`IMP-08`).
- **Değişen dosyalar:** `test_spikes/spike_01_backend/lib/backup/hub_backup_orchestrator.dart`, `test_spikes/spike_01_backend/bin/server.dart`.
- **Testler:** `test_spikes/spike_01_backend/test/hub_backup_s1_s6_hardening_test.dart` → S1 grubu 7 test: kilit başka **yedek** işleminde (eski 24 s yerel yedek/retention) ve **restore** işleminde iken erteleme + kilit boşalınca çalışma; manuel yedekle çakışma; okunamayan kurtarma parolası (tek log, düzeltilince devam); gerçek durum dosyası hatası; gerçek yedekleme hatası (Drive 5xx → `RETRY_PENDING`); gerçek `Timer.periodic` altında yakalanmamış hata olmaması.
- **Gerçek sonuç:** Hepsi geçti. **RED doğrulaması yapıldı:** Eski `Timer` davranışı geçici olarak geri konunca `Timer.periodic` testi "yakalanmamış hata" ile **KALDI**; düzeltmeyle geçti.
- **Kalan risk:** Gerçek `LocalService` altında uzun süreli çalışma (`BK-PAT-18`) **BLOCKED**. `scheduler_last_error` henüz Windows ekranında gösterilmiyor (yalnız API alanı).

### S2 — Manuel yedekte kayıtlı olmayan parola
- **Önceki problem:** `POST /api/v1/backup/run` gövdedeki `recovery_password` değerini kullanıyordu; Windows ekranı parola alanı doluysa kaydedilmemiş metni gönderiyordu.
- **Değişiklik:** Orkestratör `triggerBackup` / `retryExistingJob` parola parametresi almaz; her zaman Hub'da kayıtlı DPAPI parolasını kullanır. `/backup/run` gövdesinde `recovery_password` varsa (yerel admin veya uzak OWNER) `400 ERR_RECOVERY_PASSWORD_NOT_ACCEPTED`; kayıtlı parola yoksa mevcut sözleşmeyle `400 ERR_RECOVERY_KEY_REQUIRED` (fail-closed). Başarılı yanıt `recovery_key_source: HUB_STORED_DPAPI` içerir. Windows ekranında kaydetme ve yedekleme ayrıldı: alanda kaydedilmemiş metin varken veya Hub'da kayıtlı parola yokken yedek başlatılmaz; istemci istekte parola göndermez (`IMP-09`).
- **Değişen dosyalar:** `bin/server.dart`, `lib/backup/hub_backup_orchestrator.dart` (Hub); `lib/features/backup/data/hub_backup_client.dart`, `lib/features/backup/presentation/widgets/hub_central_backup_card.dart` (Windows UI).
- **Testler:** `hub_backup_s1_s6_hardening_test.dart` S2 grubu 6 test (kayıtlı parola yokken red; kayıtlı parolayla yedek + **paketin kayıtlı parolayla çözülüp başka parolayla çözülemediği**; uzak OWNER farklı parola → red, kayıtlı parola değişmez, iş oluşmaz; Windows/loopback kaydedilmemiş parola → red, parola kaydedilmez; parolasız istek + kayıtlı parola yok → fail-closed; CASHIER → 403). `test/features/backup/hub_central_backup_ui_test.dart` 2 yeni widget testi (kaydedilmemiş metinle yedek engeli → kaydet → parolasız istek; kayıtlı parola yokken istek gönderilmez).
- **Gerçek sonuç:** Hepsi geçti. (RED ayrı koşulmadı; davranış yeni.)
- **Kalan risk:** Eski S5A-4 ucu `POST /api/v1/admin/backup` açık `backup_password` kabul etmeye devam ediyor (23 Kasım `IMP-01` kararı; yalnız loopback+admin). Bu tur kapsamı dışında bırakıldı; Owner isterse aynı kurala alınabilir.

### S3 — Retention sırasında durum dosyası yazma yarışı
- **Önceki problem:** Retention durumu okuyor, Drive silmelerini bekliyor, sonra eski nesnenin tamamını geri yazıyordu; arada değişen zamanlama ayarı (veya iş kaydı) kayboluyordu. Ayrıca `save` önce dosyayı silip sonra `rename` ediyordu (çökme penceresi).
- **Değişiklik:** `HubBackupStateStore.update()` — dosya yolu başına tek sıralı yazma kuyruğu, dönüştürücü her zaman güncel durumu alır; `upsertJob`, `updateSchedule`, `patchJobs` bu kuyruğu kullanır. Retention Drive silmesini kuyruk dışında bekler, sonra yalnızca budanan işlerin alanını ve **yalnızca kayıt hâlâ aynı Drive dosyasını/yerel yolu gösteriyorsa** temizler. Gece yarısı devri ve `configureSchedule` alan bazlı. Windows'ta `rename` hedefin üzerine atomik yazdığı doğrulandı ("önce sil" kaldırıldı). 12 durumlu makine değişmedi (`IMP-10`).
- **Değişen dosyalar:** `lib/backup/hub_backup_state_store.dart`, `lib/backup/hub_backup_orchestrator.dart`.
- **Testler:** S3 grubu 3 test: retention Drive silmesini beklerken zamanlama değişikliği + iş güncellemesi (yeniden başlatma sonrası okuma ile) kaybolmaz; iki farklı store örneğiyle 25 eşzamanlı güncelleme + zamanlama kayıpsız; dönüştürücü ortasında hata → disk değişmez, `.tmp` kalmaz, sonraki güncelleme çalışır.
- **Gerçek sonuç:** Hepsi geçti. **RED doğrulaması yapıldı:** kuyruksuz oku-yaz geçici olarak geri konunca eşzamanlılık testi **KALDI**.
- **Kalan risk:** Kuyruk süreç içidir; aynı dosyaya yazan ikinci bir süreç yoktur (yalnız Hub servisi yazar).

### S4 — Legacy machine key restore güvenlik kopyası
- **Önceki problem:** `legacy_machine_key: true` restore'unda koruyucu kopyanın da makine pepper'ıyla şifrelendiği kılavuzda yoktu.
- **Değişiklik:** Kod değişmedi. Davranış `LP-05` testine eklenen doğrulamayla sabitlendi (koruyucu kopya pepper ile açılır, Portable Recovery Password ile açılmaz) ve `BACKUP_AND_RESTORE_GUIDE.md` §7'ye makine bağımlılığı, aynı makinede geri dönüş adımı ve bilgisayar değişiminde "hemen yeni taşınabilir yedek al" talimatı yazıldı (`IMP-11`).
- **Değişen dosyalar:** `docs/operations/BACKUP_AND_RESTORE_GUIDE.md`, `test_spikes/spike_01_backend/test/legacy_backup_portable_key_test.dart`.
- **Gerçek sonuç:** `legacy_backup_portable_key_test` 7/7 geçti.
- **Kalan risk:** Gerçek `LocalService` + gerçek eski yedekle saha doğrulaması **BLOCKED**.

### S5 — Hub ve eski istemci Drive yedeklerinin aynı klasörde olması
- **Önceki problem:** Hub (`ResumableDriveUploader`) ve eski istemci (`GoogleDriveBackupUploader`) aynı `MARKET MMS Yedekleri` klasörünü kullanıyordu. İstemci geri yükleme listesi Hub (merkezi DB) yedeklerini de gösterebiliyordu (filtreler `null` alanları geçiriyordu). Silme açısından: istemci yalnızca kendi yüklediği bozuk kopyayı siler, Hub retention yalnızca kendi kaydındaki dosya kimliklerini siler — karşılıklı silme riski bulunmadı.
- **Değişiklik:** Hub yedekleri `MARKET MMS Yedekleri/Hub` alt klasörüne yüklenir (ebeveyn-farkındalıklı arama/oluşturma) ve `appProperties.mms_backup_source = HUB_CENTRAL` taşır. Eski istemci kökte kalır (cihazlarda geçiş yok); istemci listesi işaretli veya `hub_backup_` önekli dosyaları dışlar. OAuth kasasındaki klasör önbelleği yalnızca `folder_layout = HUB_SUBFOLDER_V1` ise kullanılır → eski kök önbelleği ilk yedekte otomatik olarak yeni alt klasöre geçer. Kökte kalan eski Hub dosyaları taşınmaz/silinmez; Hub kaydındaki dosya kimliğiyle retention/geri yükleme sürer. LiveSync klasörü ve OAuth/kasa ayrımı değişmedi (`IMP-13`).
- **Değişen dosyalar:** `packages/mms_client_storage/lib/src/backup/resumable_drive_uploader.dart`, `google_drive_backup.dart`; `test_spikes/spike_01_backend/lib/backup/hub_backup_oauth_store.dart`, `hub_backup_oauth_service.dart`, `hub_backup_orchestrator.dart`, `bin/server.dart`.
- **Testler:** `packages/mms_client_storage/test/s5_drive_folder_separation_test.dart` (4 test: klasör adları, Hub tanıma, istemci listesinin Hub dosyalarını dışlaması, varsayılan yükleyici davranışının değişmemesi); Hub S5 testi (eski kök önbelleği → kök altında `Hub` arama/oluşturma, `parents`, kaynak işareti, kasanın yeni düzenle güncellenmesi, ikinci yedekte klasör aramasının tekrarlanmaması). `hub_backup_b3_orchestrator_test.dart` yardımcısı önbelleği Hub düzeninde işaretleyecek şekilde güncellendi (test amacı değişmedi).
- **Gerçek sonuç:** Hepsi geçti. Gerçek Google Drive hesabında test **yapılmadı**.
- **Kalan risk:** Gerçek Drive'da `drive.file` görünürlüğü ve klasör oluşturma (`BK-PAT-02`) **BLOCKED**. Mimari taslaktaki `{tenant_store}` alt seviyesi uygulanmadı (pilot tek-tenant).

### S6 — E2E testinin üretim Hub'a yazabilmesi
- **Önceki problem:** `MMS_E2E_HUB_URL` + token verilirse test, adresin üretim Hub'ı olup olmadığını denetlemeden ürün/satış yazabiliyordu (koruma yalnız dokümantasyondaydı).
- **Değişiklik:** `integration_test/support/e2e_hub_target_guard.dart`: Hiçbir Hub isteğinden önce `MMS_E2E_HUB_ALLOWLIST` (`host:port`, zorunlu, örtük port yok) ve `MMS_E2E_EXPECTED_HUB_ID` (zorunlu, `E2E-`/`TEST-` öneki; `MMS-HUB-MASTER` gibi üretim kimlikleri reddedilir) denetlenir. Yazmalardan önce salt-okunur `GET /api/v1/sync/device-state` ile Hub'ın `hub_id` değeri birebir eşleşmelidir. Keşifle bulunan adres de allowlist'e tabidir. Gerçek uygulama DB yolu açılmadan reddedilir. Varsayılan fail-closed (`IMP-14`). Hub kodu değişmedi.
- **Değişen dosyalar:** `integration_test/android_full_e2e_verification_test.dart`, yeni `integration_test/support/e2e_hub_target_guard.dart`.
- **Testler:** `test/integration_support/e2e_hub_target_guard_test.dart` 8 birim testi (kabul; eksik allowlist/kimlik; üretim kimlikleri; allowlist dışı host/port/örtük port; bozuk girdi/şema; kimlik eşleşmesi yazma yapmadan; aynı adreste üretim Hub; 401/ağ hatası/bozuk yanıt).
- **Gerçek sonuç:** Hepsi geçti. E2E testinin kendisi fiziksel cihazda **çalıştırılmadı** (`PAT-20` **BLOCKED**).
- **Kalan risk:** Koruma, test Hub'ının `E2E-`/`TEST-` önekli `HUB_ID` ile başlatılmasına dayanır; Owner üretim Hub'ına bu önekli kimlik verirse koruma aşılır (dokümante edildi).

---

## C. İkincil Barkod Kullanıcı Arayüzü

- **Bulgu doğrulandı:** 23 Kasım 1. tur itibarıyla `CatalogNotifier.addProductBarcode/removeProductBarcode` hiçbir ekrandan çağrılmıyordu; önceki raporların "arayüze bağlandı" ifadesi yanlıştı (`PHASE_A1_DELIVERY_REPORT.md` düzeltildi).
- **Eklenen ekranlar/girişler:**
  - Ürün Kataloğu masaüstü tablosunda her satırda **Barkodları Yönet** düğmesi; dar ekran/Android ürün kartında 48 dp **Barkodları Yönet** düğmesi.
  - Ürün düzenleme (detay) diyaloğunda **İkincil Barkodları Yönet** düğmesi.
  - Yeni `ProductBarcodesDialog` (mevcut `AppDialog`/`AppButton` tasarım sistemi; yeni ekran/rota veya paralel state yönetimi yok — mevcut `CatalogNotifier` kullanılır).
- **Kullanıcı işlemleri:** Birincil barkodu görme; ikincil barkodları listeleme; elle/USB-HID okuyucu (Enter ile) veya destekleyen cihazda **Kamera ile Tara** ile ekleme; onay diyaloğuyla (Vazgeç/Sil) silme; diyalog içinde anlaşılır başarı/hata mesajı.
- **İş kuralları:** Birincil barkod ikincil eklenemez; aynı ürüne tekrar eklenemez ("zaten ekli"); başka ürüne kayıtlı barkod eklenemez (ürün adı gösterilir); geçersiz biçim (`BarcodeInputSanitizer`) reddedilir. Kurallar depo katmanında da zorlanır (mesajlar ayrıştırıldı). Silme BR-PROD-15 gereği pasife alma.
- **Outbox ve senkron:** Ekleme/silme mevcut yolu kullanır: yerel SQLite + aynı transaction'da `PRODUCT_UPSERT` Outbox (FIFO `client_seq`, `operation_id`). Hub erişilemezken işlem yerelde hemen geçerlidir. **Ürün bazlı senkron durumu** (`ProductCatalogSyncStatus`: eşit / bekliyor / yeniden denenecek / kalıcı hata + son hata) diyalogda ve liste satırında rozet olarak gösterilir; genel Outbox rozetine bağımlı değildir.
- **9.4 — Outbox bloke iken barkodun geri dönmesi:** İncelendi ve doğrulandı. Veri kaybı **vardı**: Hub snapshot silinen barkodu yerelde yeniden aktifleştiriyor; kullanıcı bu sırada aynı ürüne başka bir barkod değişikliği yaparsa yeni `PRODUCT_UPSERT` geri gelen barkodu taşıyıp Hub'a **kalıcı olarak geri yazıyordu** (koruma kapatılarak koşulan geçici RED testinde yük `['…301', '…399', '…400']` olarak gözlendi). Düzeltme: gönderilmemiş `PRODUCT_UPSERT` kaydı olan ürünlerin barkod kümesi ve birincil barkodu Hub snapshot'ı ile ezilmez (Faz 7A bekleyen stok koruması ile aynı ilke; şema/veri modeli değişmedi). Outbox onaylanınca sonraki senkronda Hub verisi yeniden uygulanır; silinen barkod geri görünmez (`IMP-15`).
- **Testler:** `packages/mms_client_storage/test/secondary_barcode_pending_sync_test.dart` (5 test; RED doğrulandı), `test/features/catalog/secondary_barcode_ui_test.dart` (12 widget testi: görüntüleme, ekleme/offline + ürün rozeti, silme iptali, silme, aynı ürüne tekrar, başka ürünün barkodu, birincil çakışma, geçersiz biçim, Outbox kalıcı hata bildirimi + senkron sonrası eşit durum, dar/touch düzen, 1024 px masaüstünde rozet taşmaması, ürün düzenleme ekranından giriş).
- **Tam takımın yakaladığı regresyon:** İlk tam koşumda `open_food_facts_test` → "2. Harici API hatası…" **KALDI**: yeni rozet 1024 px masaüstü satırında 22 px taşma yapıyordu. Rozet `Flexible` yapıldı; taşmayı yeniden üreten test eklendi (düzeltmesiz **KALDI**, düzeltmeyle geçti).
- **Fiziksel test gereksinimleri:** Kamera taraması ve iki cihaz arası gerçek senkron **test edilmedi** → `PAT-19` (adımlar yeni ekrana ve 9.4 senaryosuna göre güncellendi) **BLOCKED**.

---

## D. Dokümantasyon

| Belge | Değişiklik |
|---|---|
| `OWNER_ACTION_CHECKLIST.md` | Bayat "806/806", `PAT-01…18`, "ADR-022 henüz kodlanmamıştır", "çalışma ağacı temiz" ifadeleri düzeltildi; A1 tablosuna ADR-023 eklendi; 23 Kasım 2. tur notu ve güncel sayılar |
| `docs/IMPLEMENTATION/PHASE_A1_DELIVERY_REPORT.md` | İkincil barkod UI iddiası düzeltildi; §5 gerçek UI eklendi |
| `docs/FINAL_PILOT_READINESS_REPORT.md` | Bu rapor (A–I); 23 Kasım içeriği Ek-23K'da düzeltme notlarıyla |
| `docs/architecture/GOOGLE_DRIVE_BACKUP_ARCHITECTURE_V1_1.md` | Entropy (`IMP-12`): koddaki `MarketMMS:HubBackupDriveOAuth:v1` / `MarketMMS:HubBackupRecoveryKey:v1` yazıldı; `MMS-HUB-BACKUP-OAUTH-V1|<tenant>|<store>` uygulanmamış taslak olarak işaretlendi; güvenlik değerlendirmesi ve kodun neden değişmediği. Klasör düzeni (`/Hub`) |
| `docs/operations/BACKUP_AND_RESTORE_GUIDE.md` | §1.1 merkezi Hub yedeği (kayıtlı parola, zamanlayıcı davranışı), §4 Drive klasörleri tablosu, §7 S4 koruyucu kopya, yeni hata kodları |
| `docs/decisions/023-…md` | §6 23 Kasım 2. tur uygulama notları |
| `docs/IMPLEMENTATION/MASTER_IMPLEMENTATION_DECISIONS.md` | §4 `IMP-08…IMP-15` |
| `docs/testing/BK_TEST_ID_TRACEABILITY.md` (yeni) | Şartname `BK-001…032` ↔ gerçek test etiketleri ↔ `BK-PAT`; yeniden numaralandırma yok; otomatik testi olmayan maddeler açıkça (`BK-020` Hub red yolu, `BK-005`/`BK-023` Hub kısmı vb.) |
| `docs/phases/PHASE_C_WINDOWS_INSTALLER_SCOPE_DRAFT.md` (yeni) | "Faz C" (tarihsel Drive restore) / eşleştirme Faz A–D / `C1-C2` (Google OAuth) / PHASE C (Installer) ayrımı; ön koşullar, kapsam, kapsam dışı, kabul kriterleri. **Installer geliştirmesi başlamadı.** |
| `PHYSICAL_ACCEPTANCE_TEST_PLAN.md` | `PAT-19` yeni ekran + 9.4 adımı; `PAT-20` allowlist/beklenen kimlik + negatif kontrol |
| `docs/LIVE_PROJECT_STATUS.md` | 23 Kasım 2. tur özeti |

**Kalan dokümantasyon borçları:** `BACKUP_RESTORE_ACCEPTANCE_TESTS_V1_1.md` içindeki test etiketleri yeniden adlandırılmadı (izlenebilirlik tablosu esas); `LIVE_PROJECT_STATUS.md` ve `MASTER_ROADMAP.md`'deki eski (21–22 Kasım) sayılar tarihsel not olarak duruyor; `BK-020`/`BK-005`/`BK-023` Hub kısımları için otomatik test borcu.

---

## E. Test Sonuçları (23 Kasım 2026 (2. tur) — son kod durumunda, sıralı, aynı anda tek takım)

Tüm testler geçici dizinlerde sentetik veriyle çalıştı. Gerçek DB, gerçek Drive, gerçek OAuth, `MarketMmsSpike01` kullanılmadı. Önceki koşumların sayıları bu tabloya karıştırılmadı.

| # | Paket | Komut | PASS | FAIL | SKIP | Süre |
|---|---|---|---|---|---|---|
| 1 | `packages/mms_client_storage` | `dart test` (varsayılan paralel) | 247 | **1** — `backup_operation_lock_test.dart` › *14. … eşzamanlı kurtarmayı tek kazananla sınırlar* (`.recovering` dosyası geride kaldı) | 0 | 69 s |
| 1a | `packages/mms_client_storage` (yeniden) | `dart test -j 1` | **248** | 0 | 0 | 111 s |
| 1b | `packages/mms_client_storage` (yeniden ×3) | `dart test` | 3/3 tam takım geçti | 0 | 0 | — |
| 1c | yalnız #14 (izole ×16) | `dart test test/backup_operation_lock_test.dart --plain-name "14. Sahip"` | 16/16 | 0 | 0 | — |
| 2 | `packages/mms_contracts` | `dart test` | **7** | 0 | 0 | 3 s |
| 3 | Hub `test_spikes/spike_01_backend` | `dart test -j 1` | **292** | 0 | 0 | 285 s |
| 4 | Kök `market_pos` | `flutter test -j 1` | **351** | 0 | 0 | 220 s |

**Gerçek toplam (son kod, her takımın yeşil tam koşumu):** 248 + 7 + 292 + 351 = **898 geçti, 0 atlanan.** Bu turda eklenen testler bu sayıya dahildir (Hub +17 = `hub_backup_s1_s6_hardening_test`; paket +9 = S5 4 + barkod 5; kök +23 = barkod UI 12 + E2E koruma 8 + S2 UI 2 + 1 taşma testi; ayrıca `LP-05` mevcut teste ek doğrulama). Önceki turun 850 toplamıyla karıştırılmamalıdır (farklı kod durumu).

**Kararsız test (#14) değerlendirmesi:** Bu turda `BackupOperationLock` ve testine **dokunulmadı**. Aynı gün ~5 paralel tam koşumda 1 kez kaldı; izole ve `-j 1` koşumlarda hiç kalmadı. Muhtemel kök neden (kod incelemesi, doğrulanmadı): Windows'ta `_releaseRecoveryMutex` dosyayı silerken başka bir isolate aynı dosyayı okuyorsa paylaşım ihlali oluşur ve `catch (_)` bunu yutar; `.recovering` dosyası kalır. Etkisi: bir sonraki *eski kilit kurtarması* `recoveryLockStaleAfter` süresi dolana kadar "meşgul" döner, sonra kendiliğinden toparlanır; veri kaybı yok. Öneri §H.

**Ara koşum (dürüstlük notu):** Aynı gün ilk tam koşumda kök takım `flutter test` (paralel) ile **1 başarısız** test verdi (§C'deki 22 px taşma regresyonu; gerçek hata). Düzeltildi, yeni test eklendi ve yukarıdaki son koşum yapıldı. İlk koşumdaki diğer takımlar: `mms_client_storage` 248/248, `mms_contracts` 7/7, Hub 292/292.

**Hedefli RED doğrulamaları (geçici değişiklik → test → geri alma, dosya karması ile geri yükleme doğrulandı):** S1 Timer testi, S3 eşzamanlılık testi, 9.4 geri gelme ve kalıcı geri yazma, 1024 px rozet taşması — hepsi düzeltme olmadan **KALDI**. S2/S5/S6 testleri yeni davranışı sınar; ayrı RED koşulmadı.

---

## F. Build ve Analiz

| Hedef | Komut | Sonuç |
|---|---|---|
| Statik analiz — kök `market_pos` | `flutter analyze` (integration_test dahil) | **0 sorun** |
| Statik analiz — `mms_client_storage` | `dart analyze` | **0 sorun** |
| Statik analiz — `mms_contracts` | `dart analyze` | **0 sorun** |
| Statik analiz — Hub | `dart analyze` | **0 sorun** |
| Windows Master Hub AOT | `dart build cli -t bin/server.dart -o <scratchpad>` | **Çıkış 0** (15 s), `bundle\bin\server.exe` üretildi; çıktı scratchpad'de kaldı ve silindi. `MarketMmsSpike01`'in kullandığı `build\spike_service.exe` **yeniden derlenmedi/değiştirilmedi** |
| Windows istemci (debug) | `flutter build windows --debug` | **Çıkış 0** (44 s), `build\windows\x64\runner\Debug\market_pos.exe` |
| Android istemci (debug APK) | `flutter build apk --debug` | **Çıkış 0** (65 s), `build\app\outputs\flutter-apk\app-debug.apk` (199.038.087 bayt ≈ 189,8 MiB) |

Release APK ve imzalı Windows paketi üretilmedi (`B1`/`B2` Owner adımı).

---

## G. Koruma Kontrolleri

| Kontrol | Sonuç | Yöntem |
|---|---|---|
| 4 korunan dosya (`.vscode/settings.json`, `run_windows_client.bat`, `start_master_hub.bat`, `stop_master_hub.bat`) | **Değişmedi** | Oturum başı ve sonu SHA-256 karşılaştırması: 4/4 OK |
| `MarketMmsSpike01` | **Dokunulmadı** — `Running`, `Automatic`. Yalnız salt-okunur `Get-Service`/`Win32_Service` sorgusu yapıldı. Servis `build\spike_service.exe` (5 Kasım tarihli) ve `build\service_test.db` kullanıyor; DB'nin son yazımı 13:51 (oturum başlangıcı 19:54'ten önce) | Komut geçmişi + dosya zaman damgaları |
| Gerçek veritabanları | **Dokunulmadı.** `%ProgramData%\MarketMMS` bu makinede yok; tüm testler geçici dizinlerde (`mms_test_only_*`) veya bellek içi SQLite ile çalıştı. **Not:** Mevcut bir Hub testi her tam koşumda `test_spikes/spike_01_backend/backups/` altına bir test anlık görüntüsü bırakıyor (bu turdan önce de: 21 Kasım'dan beri 88 dosya; bu turun iki koşumu 2 dosya ekledi; git tarafından yok sayılıyor, gerçek veri değil; silinmedi) | `find` + `git check-ignore` |
| Gerçek Google Drive / OAuth | **Kullanılmadı.** Tüm Drive/Google çağrıları `MockClient`; gerçek token yok | Test kodu |
| Sırlar (token, kurtarma parolası, pepper, sertifika, imza anahtarı) | **Değişmedi.** Depoda değişmiş `.dpapi/.key/.crt/.jks` yok; DPAPI testleri yalnız geçici dizindeki sentetik dosyalarla | `find -newer` |
| Sistem saati | Değiştirilmedi (testler sahte saat kullanır) | — |
| E2E testleri | `android_full_e2e_verification_test.dart` cihazda **çalıştırılmadı**; yeni koruma onu üretim Hub'a karşı fail-closed yapar (S6) | Birim testleri |
| Git | **Yazma yok:** HEAD `817f881`; stage alanı boş; commit/push/reset/checkout/clean/stash yapılmadı | `git rev-parse`, `git diff --cached` (salt-okunur) |
| Geçici RED değişiklikleri | 5 geçici kaynak değişikliği ve 1 geçici test dosyası RED kontrolü için kullanıldı; hepsi geri alındı/silindi, karma karşılaştırmasıyla doğrulandı | `diff -q` |

**Bu turda değiştirilen dosyalar (başlangıçta zaten değiştirilmiş/izlenmeyen durumdaydı — önceki tur değişiklikleri korunarak üzerine eklendi):** `OWNER_ACTION_CHECKLIST.md`, `PHYSICAL_ACCEPTANCE_TEST_PLAN.md`, `docs/IMPLEMENTATION/MASTER_IMPLEMENTATION_DECISIONS.md`, `docs/IMPLEMENTATION/PHASE_A1_DELIVERY_REPORT.md`, `docs/LIVE_PROJECT_STATUS.md`, `docs/architecture/GOOGLE_DRIVE_BACKUP_ARCHITECTURE_V1_1.md`, `docs/decisions/023-…md`, `docs/operations/BACKUP_AND_RESTORE_GUIDE.md`, `docs/FINAL_PILOT_READINESS_REPORT.md`, `integration_test/android_full_e2e_verification_test.dart`, `lib/core/storage/local_database_service.dart`, `lib/features/backup/data/hub_backup_client.dart`, `lib/features/backup/presentation/widgets/hub_central_backup_card.dart`, `lib/features/catalog/application/catalog_notifier.dart`, `lib/features/catalog/data/catalog_repository.dart`, `packages/mms_client_storage/lib/mms_client_storage.dart`, `…/backup/resumable_drive_uploader.dart`, `…/database/client_storage_repository.dart`, `test/features/backup/hub_central_backup_ui_test.dart`, `test_spikes/spike_01_backend/bin/server.dart`, `…/lib/backup/hub_backup_oauth_service.dart`, `hub_backup_oauth_store.dart`, `hub_backup_orchestrator.dart`, `hub_backup_state_store.dart`, `…/test/hub_backup_b3_orchestrator_test.dart`, `legacy_backup_portable_key_test.dart`.

**Bu turda ilk kez değiştirilen izlenen dosyalar:** `lib/features/catalog/application/catalog_state.dart`, `lib/features/catalog/presentation/screens/catalog_screen.dart`, `lib/features/catalog/presentation/widgets/product_edit_dialog.dart`, `packages/mms_client_storage/lib/src/backup/google_drive_backup.dart`.

**Yeni dosyalar:** `lib/features/catalog/application/product_barcode_details.dart`, `lib/features/catalog/presentation/widgets/product_barcodes_dialog.dart`, `packages/mms_client_storage/lib/src/models/product_catalog_sync_status.dart`, `integration_test/support/e2e_hub_target_guard.dart`, testler (`hub_backup_s1_s6_hardening_test.dart`, `s5_drive_folder_separation_test.dart`, `secondary_barcode_pending_sync_test.dart`, `secondary_barcode_ui_test.dart`, `test/integration_support/e2e_hub_target_guard_test.dart`), dokümanlar (`docs/testing/BK_TEST_ID_TRACEABILITY.md`, `docs/phases/PHASE_C_WINDOWS_INSTALLER_SCOPE_DRAFT.md`).


---

## H. Kalan İşler

**Otomatik testle doğrulanamayanlar / doğrulanmayanlar:**
- Gerçek `NT AUTHORITY\LocalService` altında zamanlayıcı, DPAPI kasaları, ACL ve reboot kalıcılığı (`BK-PAT-01`, `BK-PAT-18`).
- Gerçek Google Drive: `Hub` alt klasörü oluşturma/görünürlük, resumable yükleme, kota/yetki hataları, retention (`BK-PAT-02/04/05/10/11`, yalnız `TEST_ONLY` klasör).
- Kamera ile ikincil barkod taraması ve iki cihaz arası barkod senkronu (`PAT-19`).
- E2E testinin fiziksel Android + izole TEST Hub koşumu (`PAT-20`).
- Otomatik test borcu: Hub `ResumableDriveUploader` VERIFYING red yolu (`BK-020`), Hub merkezi restore tenant/store uyuşmazlığı (`BK-005`) ve rollback (`BK-023`).

**Owner işlemleri:** `A2` commit kararı; `D1–D4` (ör. `MarketMmsSpike01` kaldırma — bu turda servise dokunulmadı), `B2`, `B1`, `B3` Portable Recovery Password, `C1/C2`, Windows Hub ekranından Drive bağlantısı; PHASE C kapsam taslağının onayı; `E1/E2`.

**Pilot engelleyicileri:** Tüm `PAT-01…PAT-20` ve `BK-PAT-01…18` fiziksel testleri; `B1`, `B2`, `B3`; Hat B için `C1/C2`.

**Açık karar önerileri (uygulanmadı):**
1. Eski S5A-4 `POST /api/v1/admin/backup` açık `backup_password` kabulü — S2 ile aynı kurala alınsın mı?
2. `scheduler_last_error` Windows Hub ekranında gösterilsin mi (şu an yalnız API)?
3. İki Hub yedek zamanlayıcısı (eski 24 s yerel + ADR-023 00:00) birlikte çalışıyor (23 Kasım açık konusu, değişmedi).
4. Bekleyen `PRODUCT_UPSERT` sırasında Hub'dan gelen **diğer ürün alanları** (ad/fiyat) hâlâ geçici olarak uygulanıyor; 9.4 koruması yalnız barkod kümesi + birincil barkod için eklendi. Aynı "sonraki yerel değişiklik eski değeri geri yazar" riski bu alanlar için de teorik olarak vardır; fiyat/finansal davranışı etkilediği için Owner kararı olmadan değiştirilmedi.

**Bu turda ortaya çıkan ek bulgular (düzeltilmedi, kapsam dışı):**
5. **Kararsız kilit testi** `backup_operation_lock_test` #14 (§E). Öneri: `_releaseRecoveryMutex` silme işleminde Windows paylaşım ihlaline karşı kısa yeniden deneme; eşzamanlılık primitifi olduğu için ayrı, odaklı bir değişiklik ve inceleme gerektirir.
6. **Test hijyeni:** `backupDirectory` vermeyen bir Hub testi her tam koşumda `test_spikes/spike_01_backend/backups/` altına şifresiz test anlık görüntüsü bırakıyor (git-ignored, 88 dosya birikmiş). Öneri: ilgili testleri geçici dizine yönlendirmek; biriken dosyaların silinmesi Owner kararı.

---

## I. Commit Önerisi

- **Commit için hazır mı?** **Evet, yazılım ve otomatik test açısından** (son koşum: 898/898 son tam koşumlar; 1 bilinen kararsız kilit testi (§E); 4 projede statik analiz temiz; Hub AOT, Windows debug, Android debug APK derlendi). Fiziksel testler yapılmadığı için bu bir **pilot kabulü değildir**.
- **Engelleyici madde:** Yok (commit açısından). Kararsız kilit testi (§H-5) bu turun kodundan bağımsızdır; commit sonrası ayrı iş olarak izlenmelidir. Owner'ın 23 Kasım değişikliklerini de bu commit setine dahil edip etmeyeceğine karar vermesi gerekir; iki turun değişiklikleri aynı dosyalarda iç içedir.
- **Değişiklik kapsamı (bu tur):** Hub yedek orkestratörü/durum deposu/OAuth kasası/sunucu uçları; `mms_client_storage` Drive yükleyici/istemci listesi + katalog senkron koruması + yeni model; uygulamada katalog UI (yeni diyalog, ekran girişleri), yedek kartı/istemcisi, E2E koruması; testler; dokümanlar.
- **Önerilen mantıksal commit grupları (sıra önerisi):**
  1. `fix(hub-backup): S1 guarded scheduler tick, S3 serialized state store writes` — `hub_backup_orchestrator.dart` (S1/S3 kısımları), `hub_backup_state_store.dart`, `bin/server.dart` (açılış + `scheduler_last_error`), ilgili testler.
  2. `fix(hub-backup): S2 manual backup uses stored recovery password only` — `bin/server.dart` (`/backup/run`), orkestratör imzaları, `hub_backup_client.dart`, `hub_central_backup_card.dart`, S2 testleri.
  3. `feat(drive): S5 separate Hub backups into "MARKET MMS Yedekleri/Hub"` — `resumable_drive_uploader.dart`, `google_drive_backup.dart`, OAuth store/service, sunucu yükleyici kurulumu, S5 testleri, `b3` test yardımcısı.
  4. `test(e2e): S6 fail-closed E2E Hub target guard` — `integration_test/**`, `test/integration_support/**`.
  5. `feat(catalog): secondary barcode management UI + pending PRODUCT_UPSERT barcode protection` — `client_storage_repository.dart`, `product_catalog_sync_status.dart`, export, `local_database_service.dart`, `lib/features/catalog/**`, barkod testleri.
  6. `docs: S1–S6 decisions, guide, traceability, PHASE C draft, report` — tüm `.md` değişiklikleri.
  *(Not: Aynı dosyada birden çok gruba ait satırlar var — örn. `hub_backup_orchestrator.dart` S1/S2/S3/S5. Kısmi stage (`git add -p`) gerektirmemek için 1–3'ü tek "hub backup hardening" commit'inde birleştirmek daha güvenlidir.)*
- **Kullanıcıdan beklenen kararlar:** (1) commit/gruplama, (2) §H açık karar önerileri 1–4, (3) PHASE C kapsam taslağının onayı, (4) fiziksel test takvimi.


---

## Ek-23K. 23 Kasım 2026 1. Tur (Tarihsel — sayılar o koşumlara aittir)

> Bu ek, raporun 23 Kasım 1. tur sürümünün içeriğidir. Test sayıları ve durumlar **1. tur koşumlarına** aittir; güncel sonuçlar §E–§F'dedir. 23 Kasım 2. tur bağımsız incelemesinde yanlış veya eksik bulunan ifadeler yerinde **"2. tur düzeltmesi"** notuyla işaretlenmiştir.

### Ek-23K · 2. Bu Turda Bulunan ve Düzeltilen Sorunlar

| # | Sorun | Risk | Düzeltme | Doğrulayan test |
|---|---|---|---|---|
| 1 | Önceki tur `setup_service_acls.ps1`'e `backups\` ekleyip dosyanın **UTF-8 BOM'unu kaldırmıştı** | Windows PowerShell 5.1 Türkçe karakterli betiği yanlış kod sayfasıyla okur → ACL kurulum adımı sahada bozulabilir | BOM geri eklendi, içerik aynı; PowerShell AST `0` hata | `rel01_hub_config_test` (ilk tam Hub koşumunda **KALDI**, düzeltme sonrası geçti) |
| 2 | Eski Hub yedek uçları (`/api/v1/admin/backup`, `/admin/restore`) ve eski 24 saatlik zamanlayıcı parola yoksa **makineye bağlı `pepper.dpapi`** kullanıyordu | Yeni PC'de açılamayan yedek (ADR-023 `B1.7` ihlali) | Portable Recovery Password (`backup_recovery_key.dpapi`); yoksa `412 ERR_RECOVERY_KEY_NOT_CONFIGURED` (fail-closed); açık parola <12 → `400`; eski pepper yedekleri yalnız aynı makinede `legacy_machine_key: true` ile (`IMP-01/02`) | Yeni `legacy_backup_portable_key_test` (`LP-01…07`), güncellenen `hub_scheduled_backup_test` |
| 3 | Merkezi restore ucunda uzak `OWNER` cihazı **keyfi `package_path`** (UNC dahil) verebiliyor, **`kdf_iterations`** istekten alınıyordu | UNC yolu ile servis hesabının SMB/NTLM bilgisinin dışarı sızması; safety snapshot şifrelemesinin zayıflatılması | `package_path` yalnız loopback+admin; UNC/göreli yol `400`; `backup_id` regex; PBKDF2 turu yalnız sunucu ayarı (`IMP-03`) | `hub_backup_b4_rbac_restore_test` (3 yeni red senaryosu) |
| 4 | Drive retention eski yedeği Drive'dan silip **durum kaydını güncellemiyordu** | Silinmiş yedek listede geri yüklenebilir görünür; her turda tekrar silme denemesi; "min 1 geçerli yedek" hesabı sapar | Yalnız başarıyla silinenlerin `driveFileId` alanı temizlenir; 12 durum korunur (`IMP-04`) | Yeni `BK-033` |
| 5 | Son barkod silindiğinde Hub eski birincil barkoda geri düşüyordu | Silinen barkod Hub'da aktif kalır ve ürün indirmesinde istemciye geri dirilir (sessiz veri sapması) | `barcodes` alanı gönderen istemcide eski barkoda geri düşülmez (`IMP-05`) | Genişletilen `phase_a1_shutdown_and_barcode_test` |
| 6 | `android_full_e2e_verification_test.dart` uygulamanın **gerçek `client_local.db`** dosyasını kullanıyor, URL verilmezse LAN'da keşfettiği (üretim olabilecek) Hub'a test satışı gönderebiliyordu | Gerçek mağaza verisine test verisi yazılması | İzole geçici SQLite; `MMS_E2E_HUB_URL` zorunlu, keşif yalnız `MMS_E2E_ALLOW_DISCOVERY=true`; sabit `schemaVersion: 2` düzeltildi (`IMP-06`). **23 Kasım 2. tur: URL+token verilince üretim Hub'a yazma hâlâ mümkündü → teknik koruma eklendi (S6, `IMP-14`)** | `flutter analyze` (cihaz koşumu `BLOCKED` — `PAT-20`) |

Önceki raporun istediği diğer A-1.4 düzeltmeleri (gömülü token kaldırma, `VACUUM INTO`, `PARTIALLY_REFUNDED`) kodda doğrulandı.

---

### Ek-23K · 3. Gerçek Test ve Analiz Sonuçları (bu turda çalıştırıldı, sıralı)

Tüm testler geçici dizinlerde, izole test verisiyle çalıştı. `MarketMmsSpike01` servisine, `%ProgramData%\MarketMMS` altındaki gerçek verilere, sırlara ve Google Drive'a dokunulmadı (test kodunda bu yolları kullanan test yok — tarandı).

| # | Paket / Adım | Komut | Sonuç |
|---|---|---|---|
| 1 | `mms_contracts` | `dart test` | **7/7 geçti** |
| 2 | `mms_client_storage` | `dart analyze` · `dart test -j 1` | **0 sorun** · **239/239 geçti** |
| 3a | Hub (ilk koşum, devralınan durum) | `dart analyze` · `dart test -j 1` | 0 sorun · **265 geçti / 1 KALDI** (`rel01` BOM — Sorun #1) |
| 3b | Hub (düzeltmeler sonrası, hedefli) | 10 dosya: `legacy_backup_portable_key`, `hub_scheduled_backup`, `phase_a1_shutdown_and_barcode`, `rel01_hub_config`, `s5a4`, `bk02_1`, `s5a5`, `s1_api_hardening`, `stock_receipt_api`, `product_upsert` | **85/85 geçti** |
| 3c | Hub (tüm düzeltmeler sonrası, tam takım) | `dart analyze` · `dart test -j 1` | **0 sorun** · **274/274 geçti** |
| 3d | Hub (tam koşumdan sonra eklenen tam yığın test) | `dart test test/a1_secondary_barcode_full_stack_e2e_test.dart` | **1/1 geçti** |
| 4 | Kök Flutter (`market_pos`) | `flutter analyze` (integration_test dahil) · `flutter test -j 1` | **0 sorun** · **329/329 geçti** |
| 5 | Derleme | bkz. §3.1 | bkz. §3.1 |

**Toplam (son durum):** 7 + 239 + 274 + 1 + 329 = **850 otomatik test geçti, 0 başarısız.** PBKDF2 zamanlamasına duyarlı testler sıralı koşumlarda kararsızlık göstermedi; tekrar çalıştırma gerekmedi.

**Dürüstlük notları:**
- `mms_client_storage` ve `mms_contracts` bu turda kod değişikliğinden **önce** çalıştırıldı; bu turda bu iki pakette kod değişmedi.
- `integration_test/android_full_e2e_verification_test.dart` **cihazda çalıştırılmadı** (fiziksel Android + izole TEST Hub gerekir) — yalnızca statik analizden geçti.
- TDD istisnası: Sorun #2–#5 için yeni testler düzeltmeyle birlikte yazıldı; düzeltme öncesi ayrı bir RED koşumu yapılmadı. Sorun #1'in RED kanıtı tam Hub koşumundaki gerçek başarısızlıktır.

#### Ek-23K · 3.1 Derleme Kontrolleri

| Hedef | Komut | Sonuç |
|---|---|---|
| `mms_contracts` analizi | `dart analyze` | **0 sorun** |
| Windows Master Hub AOT | `dart build cli -t bin/server.dart -o <geçici scratch dizini>` | **Çıkış 0**, `bundle\bin\server.exe` üretildi (kurulu servise/`%ProgramData%`'ya kopyalanmadı; geçici çıktı silindi) |
| Windows istemci | `flutter build windows --debug` | **Çıkış 0**, `build\windows\x64\runner\Debug\market_pos.exe` (20,0 s) |
| Android istemci | `flutter build apk --debug` | **Çıkış 0**, `build\app\outputs\flutter-apk\app-debug.apk` (69,8 s) |
| PowerShell betiği | `Parser::ParseFile(setup_service_acls.ps1)` | **0 AST hatası**, UTF-8 BOM mevcut |

Release APK (imzalı) ve Windows release paketi bu turda üretilmedi: `B1` imza anahtarı ve `B2` sertifikaları Owner adımıdır.

---

### Ek-23K · 4. Talimattaki Maddelerin Durumu

Durum etiketleri: **`AUTOMATED_TESTED`** = gerçek FFI SQLite / gerçek HTTP sunucusu / mock Google HTTP ile otomatik doğrulandı · **`BLOCKED`** = gerçek donanım, servis, OAuth veya Drive gerektirir, çalıştırılmadı.

#### Ek-23K · Hat A — Core Market System

| Madde | Yazılım | Otomatik kanıt | Saha |
|---|---|---|---|
| A-1 Hub kapanış lifecycle + SIGINT | Kod incelemesiyle doğrulandı: SIGINT → `shutdown(exitProcess: true)` → `onBeforeDrain` (orkestratör/zamanlayıcı/discovery) aynı 12 s bütçe → drain → WAL `TRUNCATE` → `db.close()`; zaman aşımında DB kapatılmaz, çıkış `101` | `phase_a1_shutdown…`, `lifecycle_drain_test`, `shutdown_regression_test`, `s5a2_durability…` | Gerçek WinSW Stop / derlenmiş süreçte SIGINT **BLOCKED** (`PAT-09`, `BK-PAT-07`) |
| A-2 `SpikeServer.stop()` + `LifecycleManager` zinciri | Tek yol (`stop()` → `shutdown(exitProcess:false)`) | Aynı testler | — |
| A-3 İkincil barkod Outbox + Hub uçtan uca | Veri/senkron katmanı tamam + Sorun #5 düzeltildi. **2. tur düzeltmesi: kullanıcı arayüzü YOKTU** (§C) | `a1_secondary_barcode_full_stack_e2e_test` (gerçek istemci + gerçek Hub), `phase_a1_*`, `product_upsert_test` | `PAT-19` **BLOCKED** |
| A-4 Dashboard limit kaynaklı eksik sayım | SQL aggregate (500/2000 sınırı yok) | `dashboard_unlimited_aggregates_test`, `phase_a1_barcode_and_dashboard_test` (600 ürün) | — |
| A-5 `android_full_e2e_verification_test.dart` | Token, `VACUUM INTO`, `PARTIALLY_REFUNDED` doğrulandı + Sorun #6 düzeltildi | `flutter analyze` | Cihaz koşumu **BLOCKED** (`PAT-20`) |
| A-6 Windows/Android ürün oluşturma → senkron | Tamam | `s5a5_pilot_end_to_end_test` (4 cihaz, gerçek Hub), tam yığın barkod testi | `PAT-03`, `PAT-05` **BLOCKED** |
| A-7 Çevrimdışı satış, barkod, tekrar okutma, stok | Tamam | `pos_notifiers_test` (2. okutma → 2 adet), `continuous_scan_session_test`, `s5a5` (çevrimdışı satış, stok açığı, idempotent replay), tam yığın barkod testi | Kamera / USB-BT okuyucu `PAT-01`, `PAT-02` **BLOCKED** |

#### Ek-23K · Hat B — Backup & Restore

| Madde | Yazılım | Otomatik kanıt | Saha |
|---|---|---|---|
| B-1 `MMSBAK02` DEK/KEK | Tamam (`package:cryptography` AES-256-GCM, PBKDF2 600k) | `mmsbak_v2_and_retention_test` | `BK-PAT-02` **BLOCKED** |
| B-2 `MMSBAK01` geriye dönük okuma | Korundu | `mmsbak_v2_…`, `bk02_1` (v1→v2 restore), `LP-05` | — |
| B-3 Portable Recovery Password + LocalMachine DPAPI | Tamam (min 12) | `hub_backup_b2/b3` (gerçek DPAPI, test kullanıcısı süreci) | Gerçek `LocalService` **BLOCKED** (`BK-PAT-01`) |
| B-4 Eski uçlardaki pepper fallback'i | **Bu turda düzeltildi** (Sorun #2) | `LP-01…07`, `hub_scheduled_backup_test` | — |
| B-5 Disk alanı kontrolü | Tamam (`2.5×(db+wal)+64 MiB`) | `hub_backup_b1_test` `BK-005`, `BK-017` | `BK-PAT-06` **BLOCKED** |
| B-6 Yerel retention 7 gün | Tamam (yüklenmemiş paket ve son geçerli yedek korunur) | `mmsbak_v2_and_retention_test` | — |
| B-7 Drive retention ≥1 geçerli yedek | Tamam + Sorun #4 düzeltildi | `BK-018/019`, `BK-033` | `BK-PAT-10/11` **BLOCKED** (yalnız `TEST_ONLY` klasör) |
| B-8 Resumable upload, 4 MiB, `308`, oturum kurtarma | Tamam | `resumable_drive_uploader_test` (mock HTTP) | `BK-PAT-04` **BLOCKED** |
| B-9 12 durum + crash recovery | Tamam | `hub_backup_b3` `BK-006`, `BK-010` | `BK-PAT-08` **BLOCKED** |
| B-10 00:00 günlük, ilk yedek, retry/backoff | Tamam (servis başlangıcında `recoverOnStartup` + `start` bağlı) | `BK-007/009`, `BK-008/028` (sahte saat) | `BK-PAT-03` **BLOCKED** (saat değiştirilmez) |
| B-11 OAuth handoff + LocalService DPAPI/ACL | Tamam; ACL betiği BOM düzeltildi | `hub_backup_b2_oauth_test` (mock Google), PS AST | `BK-PAT-01`, `PAT-10` **BLOCKED** |
| B-12 Yeni PC restore, re-pair, sequence, `restore_epoch` | Tamam | `BK-025`, `post_restore_reconciliation_test` (`OV-03`) | `BK-PAT-13/14` **BLOCKED** |
| B-13 RBAC + replay protection | Tamam + Sorun #3 sertleştirmesi | `hub_backup_b4` `BK-022…025` | `BK-PAT-15` **BLOCKED** |
| B-14 Safety snapshot, rollback, bütünlük | Tamam | `BK-025`, `s5a4`, `LP-04` | `BK-PAT-17` **BLOCKED** |

---

### Ek-23K · 5. Değiştirilen / Eklenen Dosyalar (bu tur)

**Kod:**
- `test_spikes/spike_01_backend/bin/server.dart` — `IMP-01/02/03/05`
- `test_spikes/spike_01_backend/lib/backup/hub_backup_orchestrator.dart` — `IMP-04`
- `test_spikes/spike_01_backend/scripts/setup_service_acls.ps1` — yalnızca UTF-8 BOM geri eklendi
- `integration_test/android_full_e2e_verification_test.dart` — `IMP-06`

**Testler:**
- Yeni: `test_spikes/spike_01_backend/test/legacy_backup_portable_key_test.dart`, `test_spikes/spike_01_backend/test/a1_secondary_barcode_full_stack_e2e_test.dart`
- Güncellenen: `hub_scheduled_backup_test.dart`, `hub_backup_b3_orchestrator_test.dart` (`BK-033`), `hub_backup_b4_rbac_restore_test.dart`, `phase_a1_shutdown_and_barcode_test.dart`

**Dokümanlar:** `docs/LIVE_PROJECT_STATUS.md`, `OWNER_ACTION_CHECKLIST.md`, `PHYSICAL_ACCEPTANCE_TEST_PLAN.md`, `docs/IMPLEMENTATION/MASTER_IMPLEMENTATION_DECISIONS.md` (§3 `IMP-01…07`), `docs/IMPLEMENTATION/MASTER_IMPLEMENTATION_BASELINE.md`, `PHASE_A1/B1/B2/B3/B4_*_REPORT.md` ekleri, `docs/decisions/023-…md` §5, `docs/decisions/016-…md` (pepper notu), `docs/operations/BACKUP_AND_RESTORE_GUIDE.md`, `docs/testing/BACKUP_RESTORE_ACCEPTANCE_TESTS_V1_1.md` (bayat durum notu), bu rapor.

**Dokunulmayanlar (doğrulandı):** `.vscode/settings.json`, `run_windows_client.bat`, `start_master_hub.bat`, `stop_master_hub.bat` (değişiklik tarihleri 16–21 Kasım); `MarketMmsSpike01` servisi; gerçek DB'ler, token, pepper, sertifika, imza anahtarları; Google Drive. Git'te stage/commit/push/reset/stash yapılmadı.

---

### Ek-23K · 6. Owner'ın Bilmesi Gereken Davranış Değişikliği

**Yeni Hub sürümü kurulduğunda, Portable Recovery Password tanımlanana kadar hiçbir Hub yedeği alınmaz** — `hub_config.json` varsayılanıyla açık olan eski 24 saatlik yerel yedek dahil. Önceki sürüm bu yedeği sessizce makineye bağlı pepper ile alıyordu (yeni PC'de açılamaz). Yeni davranış ADR-023 `B1.7` gereği fail-closed'dur ve `/health` → `backup.overdue = true`, `last_error_code = ERR_RECOVERY_KEY_NOT_CONFIGURED` olarak görünür. **Kurulumdan hemen sonra `OWNER_ACTION_CHECKLIST.md` → `B3` uygulanmalıdır.** Şu an çalışan `MarketMmsSpike01` ikilisi değişmediği için bu davranış yeni sürüm kurulana kadar etkili değildir.

---

### Ek-23K · 7. Açık Konular ve Kalan Riskler (düzeltilmedi — karar veya saha gerektirir)

1. **İki Hub yedek zamanlayıcısı birlikte çalışır:** eski aralıklı yerel yedek (`MMSBAK01`, `backup_schedule.interval_hours`, varsayılan 24) ve yeni ADR-023 orkestratörü (`MMSBAK02` + Drive, 00:00). İkisi de artık kurtarma parolasını kullanır. Öneri: `BK-PAT-02/03` sahada geçene kadar eski yerel yedek açık kalsın; sonrasında Owner `interval_hours: 0` ile kapatmaya karar verebilir. **Owner kararı.**
2. **Barkodsuz ürün yer tutucusu:** Hub, barkodsuz ürünlerde (ve artık son barkodu silinen ürünlerde) `barcode = ürün kimliği` saklar ve istemciye bu değeri gönderir. Önceden var olan davranış; işlevsel risk yok, ürün detayında barkod olarak ürün kimliği görünebilir. Pilot sonrası iyileştirme.
3. **Gönderilemeyen yerel ürün düzenlemesi geçici geri dönüş:** Senkron döngüsü önce Outbox gönderip sonra ürün çeker; Outbox bir hatayla bloke olursa çekme işlemi bekleyen yerel ürün düzenlemesini (ör. silinen barkod) Hub değeriyle geçici olarak geri getirir. Outbox gönderildiğinde düzelir (tam anlık görüntü yükü). Önceden var olan tasarım; veri kaybı yok. **2. tur düzeltmesi: "veri kaybı yok" değerlendirmesi yanlıştı** — bu sırada yapılan bir sonraki barkod değişikliği geri gelen barkodu Hub'a kalıcı olarak geri yazıyordu; barkodlar için düzeltildi (§C, `IMP-15`). Diğer ürün alanları için açık karar §H-4.
4. **`HubBackupClient.restoreFromBackup(packagePath:)`** parametresi duruyor; yalnızca Hub bilgisayarında loopback + admin secret çağrısında işe yarar (uzak cihazda `403`).
5. **Fiziksel / dış bağımlılıklar:** `B1` Android imza, `B2` TLS, `B3` kurtarma parolası, `C1/C2` Google Cloud OAuth, `D1–D4` temizlik, ikinci temiz Windows PC, fiziksel Android `OWNER`/`CASHIER` cihazları, USB/Bluetooth okuyucu, `TEST_ONLY` Drive klasörü.

---

### Ek-23K · 8. Owner İçin Sıradaki Adımlar

1. Bu turdaki değişiklikleri gözden geçirip commit kararı verin (`OWNER_ACTION_CHECKLIST.md` `A2`).
2. `D1–D4` → `B2` + `B1` → yeni Hub sürümü kurulumu → **`B3` Portable Recovery Password** → `C1/C2` → Windows Hub ekranından Google Drive bağlantısı.
3. Fiziksel testler: [`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`](../PHYSICAL_ACCEPTANCE_TEST_PLAN.md) — `PAT-01…PAT-20` ve Hat B `BK-PAT-01…18` (ayrıntılı adımlar [`BACKUP_RESTORE_ACCEPTANCE_TESTS_V1_1.md`](testing/BACKUP_RESTORE_ACCEPTANCE_TESTS_V1_1.md) §4.2). Gerçek Google Drive hesabında retention/silme testleri yalnızca `TEST_ONLY` klasörde yapılır; sistem saati değiştirilmez.
4. Tüm kritik testler geçtikten sonra resmî faz kabulü (`E2`).
