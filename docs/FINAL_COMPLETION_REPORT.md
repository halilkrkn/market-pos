# MARKET MMS — Son Tamamlama, Üretim Hazırlığı ve Saha Kabulü Raporu

> [!NOTE]
> **Bu rapor 21 Kasım 2026 tarihli tarihsel kayıttır.** Güncel durum (Hat A + Hat B / ADR-023, 23 Kasım 2026, gerçek test sonuçları) için: [`FINAL_PILOT_READINESS_REPORT.md`](./FINAL_PILOT_READINESS_REPORT.md).

*Tarih: 21 Kasım 2026 (3. oturum) · Hazırlayan: Claude Code (Opus 5.5)*
*Kapsam: "Son Tamamlama, Üretim Hazırlığı ve Saha Kabulü Ana Talimatı" §1–§23*
*Okuyucu: Proje Sahibi (Owner) ve projeyi devralacak geliştiriciler*

Bu rapor, aynı tarihli 2. oturum raporunun yerini alır. 2. oturumun bulguları bu oturumda yeniden doğrulandı (§2).

> **Sonraki Oturum Güncellemesi (21 Kasım 2026 — Teknik Düzeltme ve ADR Uyum):** ADR-015…020 kapsamındaki Owner kararları, `BackupOperationLock` heartbeat/60 sn sertleştirmesi, TLS CA/SAN/hata yüzeyi sınıflandırma düzeltmesi, `ca_fingerprint` QR uyumu + `P-BLOCK-1..3` tespiti, Android Keystore hata eşlemesi, `minSdk 24` düzeltmesi ve pilot %20 KDV kısıtları için güncel kanıt raporu [`PILOT_TECHNICAL_REMEDIATION_REPORT.md`](./PILOT_TECHNICAL_REMEDIATION_REPORT.md) dosyasına yansıtılmıştır. Güncel sıralı otomatik doğrulama **730 geçti / 0 başarısız / 0 atlanan** (276 + 215 + 7 + 232) ve statik analiz 0 hata/uyarıdır; **fiziksel kabul testleri (PAT-01…15) hâlâ BLOCKED durumdadır.**

**Git:** Hiçbir dosya stage, commit veya push edilmedi.
**Silme:** Gerçek veri, yedek, servis veya kimlik silinmedi ya da değiştirilmedi.

**Durum sözlüğü:**

| Durum | Anlamı |
|---|---|
| **VERIFIED** | Otomatik testle veya bu oturumda çalıştırılarak kanıtlandı |
| **COMPLETED** | Kod yazıldı ve testli; gerçek ortamda doğrulanmadı |
| **PARTIALLY_COMPLETED** | Bir kısmı yapıldı |
| **NOT_STARTED** | Başlanmadı |
| **BLOCKED** | Donanım, hesap veya anahtar gerektiği için yapılamadı |
| **OWNER_APPROVAL_REQUIRED** | Owner kararı bekliyor |

---

## 1. Yönetici Özeti

| Soru | Cevap |
|---|---|
| **Yazılım tamamlandı mı?** | **Evet, Owner kararı gerektirenler hariç.** Bekleyen kararlar: kategori/KDV senkronu, Android'de uygulama kapalıyken yedek, Android Drive, QR görseli, keşif protokolüne TLS alanı. Bunlar tasarlandı ama uygulanmadı (§17). |
| **Otomatik testler başarılı mı?** | **Evet.** 4 süitte toplam **700 test geçti, 0 başarısız** (önceki: 660). Statik analizde hata yok (§15). |
| **Gerçek market ortamında kullanıma hazır mı?** | **Hayır.** Fiziksel kabul testlerinin hiçbiri yapılmadı (PAT-01…15). Android imza anahtarı ve Hub TLS sertifikaları henüz sağlanmadı. |

**Bu oturumun en önemli sonucu:** Önceki raporda "tamamlandı" görünen ama gerçek üretim kurulumunda **çalışmayacak** üç nokta bulundu ve düzeltildi:
1. **Kurulum betikleri ayrıştırılamıyordu (PS-BOM).**
   - `setup_service_acls.ps1` ve `uninstall_mms_service.ps1`, Windows'un varsayılan kabuğu olan PowerShell 5.1'de hiç çalışmıyordu. Bu makinede PowerShell 7 yok.
   - Kurulum betiği ACL betiğini çağırdığı için Hub kurulumu da çalışmazdı.
2. **QR ile eşleştirmede TLS pin kurulamazdı (PAIR-CA).**
   - Üretim Hub'ı eşleştirme QR'ına CA parmak izini koyamıyordu (`ca_fingerprint: "UNKNOWN"`).
3. **Otomatik Hub keşfi üretimde bağlanamazdı (AV-12).**
   - Keşif adayları her zaman `http://` olarak deneniyordu. Üretim Hub'ı ise yalnızca TLS kabul ediyor.

**Ek güvenlik ve veri bütünlüğü düzeltmeleri:**
- Android'in Google otomatik yedeği açıktı. Şifresiz yerel veritabanı ve cihaz kimliği buluta veya yeni telefona kopyalanabiliyordu.
- Restore öncesi alınan koruyucu kopya şifresiz kalıyordu.
- Yedek ile restore aynı anda çalışabiliyordu; aralarında kilit yoktu.
- Drive yükleyicisi, dosyanın gerçekten şifreli olduğunu kontrol etmiyordu.
- Firewall kuralları tüm uzak adreslere açıktı.
- Güncelleme manifesti HTTP indirme adresini ve SHA-256 özeti olmayan paketi kabul ediyordu.
- Kurulum betiği güncellemede servisi durdurmadan dosya kopyalıyordu ve başarısız güncellemeden geri dönüş yoktu.

---

## 2. Önceki Rapor ile Depo Karşılaştırması (§1)

**Sayısal iddiaların doğrulanması.** 2. oturum raporundaki sayılar bu çalışma ağacında yeniden ölçüldü. Testler sıralı çalıştırıldı ve hepsi birebir doğrulandı:

| İddia | Rapordaki değer | Bu oturumda ölçülen | Sonuç |
|---|---|---|---|
| Uygulama testleri | 243 | 243 geçti, 0 başarısız | VERIFIED |
| İstemci depolama | 191 | 191 / 0 | VERIFIED |
| Contracts | 7 | 7 / 0 | VERIFIED |
| Hub | 219 | 219 / 0 | VERIFIED |
| Statik analiz | uygulama 0, Hub 18 info, depolama 16 info | Aynı | VERIFIED |
| Boş `catch (_) {}` sayısı | 48 | 48 | VERIFIED |
| APK son oturumda derlenmedi | — | Doğru. Bu oturumda derleme denendi (§11) | VERIFIED |

**Rapor ile kod arasındaki çelişkiler.** Gerçek kod esas alındı:

| Rapordaki ifade | Gerçek durum |
|---|---|
| §12: Kurulum betiği ve ACL betiği yazılım olarak tamam | ACL ve kaldırma betikleri PowerShell 5.1'de **ayrıştırılamıyordu**: 7 + 1 ayrıştırma hatası (AV-13). |
| §4: PAIR-UI "COMPLETED"; §2 Faz 1 "VERIFIED" | Üretimde QR'da CA parmak izi `UNKNOWN` çıkıyordu (AV-18). Keşif üretimde bağlanamıyordu (AV-12). Otomatik testler bunu yakalayamadı, çünkü testler TLS'siz Hub'la çalışıyor ya da CA yolunu doğrudan veriyor. |
| §11: "Yalnızca şifreli `.mmsbak` yüklenir" | Yalnızca çağıran tarafın alışkanlığıydı; kodda bir kontrol yoktu (AV-11). |
| §13: Release yapılandırması güvenli | Cleartext ve imza ayarları doğru. Ancak `allowBackup` ayarı varsayılan (açık) bırakılmıştı (AV-8). |
| §23: Koruyucu kopyalar şifresiz (risk olarak) | Doğru. Bu oturumda düzeltildi (AV-9). |

---

## 3. İlk 7 Fazın Doğrulanmış Durumu

Faz başlıkları ve kapsamları [`MASTER_ROADMAP.md`](./MASTER_ROADMAP.md) dosyasından alındı; **değiştirilmedi**.

| Faz | Başlık | Yazılım | Otomatik test | Fiziksel kabul | Owner kabulü |
|---|---|---|---|---|---|
| 1 | Otomatik Hub Keşfi ve Bağlantı Yönetimi | COMPLETED (bu oturumda üretim TLS keşfi düzeltildi) | VERIFIED (58 sync testi) | BLOCKED (PAT-03) | OWNER_APPROVAL_REQUIRED |
| 2 | Android ve Windows UI Ayrıştırması | COMPLETED | VERIFIED | BLOCKED | OWNER_APPROVAL_REQUIRED |
| 3 | Platform Özel Klavye ve Barkod İşlemleri | COMPLETED | VERIFIED | BLOCKED (PAT-01, PAT-02) | OWNER_APPROVAL_REQUIRED |
| 4 | Kamera ile Ürün Tanımlama | COMPLETED | VERIFIED | BLOCKED (PAT-01) | OWNER_APPROVAL_REQUIRED |
| 5 | Open Food Facts Entegrasyonu | COMPLETED | VERIFIED (sahte API; canlı çağrı yapılmadı) | BLOCKED | OWNER_APPROVAL_REQUIRED |
| 6 | Mobil Kullanılabilirlik ve Offline Deneyimi | COMPLETED | VERIFIED | BLOCKED (PAT-04) | OWNER_APPROVAL_REQUIRED |
| 7 | Üretim, Kurulum ve Dağıtım Hazırlığı | PARTIALLY_COMPLETED (betikler düzeltildi; imza anahtarı ve sertifika yok) | VERIFIED (yapılandırma, betik sırası, PS 5.1 ayrıştırma) | BLOCKED (PAT-08…12) | OWNER_APPROVAL_REQUIRED |

## 4. 7A–7D Teknik Tamamlama Durumu

| Paket | Kapsam | Yazılım | Otomatik | Fiziksel |
|---|---|---|---|---|
| **7A** | Backup/restore ve sync bütünlüğü | COMPLETED. Bu oturumda: koruyucu kopya şifreleme, BK-LOCK, motordaki boş catch'ler. | VERIFIED | BLOCKED (PAT-04, PAT-07, PAT-14) |
| **7B** | TLS, token, eşleştirme | COMPLETED. Bu oturumda: PAIR-CA, keşifte HTTPS, `/reject` 400. | VERIFIED | BLOCKED (PAT-03, PAT-12) |
| **7C** | Windows servis ve Android release | PARTIALLY_COMPLETED. Betikler v2.1 ve BOM; firewall alt ağ kısıtı; `allowBackup` kapalı. | VERIFIED (statik ve ayrıştırma) | BLOCKED: imza anahtarı (B1), sertifika (B2), SCM/ACL (PAT-08…10) |
| **7D** | Google Drive ve USB | COMPLETED. Bu oturumda: Drive için yalnızca-şifreli paket koruması. | VERIFIED (sahte Drive, geçici dizin) | BLOCKED: gerçek Google hesabı (C1/C2, PAT-13); fiziksel USB (PAT-07) |

---

## 5. Yapılan Kod Değişiklikleri (bu oturum)

**Uygulama (`lib/`, `android/`)**
- `android/app/src/main/AndroidManifest.xml`: `allowBackup="false"`, `fullBackupContent="false"`, `dataExtractionRules` eklendi.
- `android/app/src/main/res/xml/data_extraction_rules.xml`: Yeni dosya.
- `lib/features/backup/application/client_backup_service.dart`: Yedek ve restore `BackupOperationLock` ile sarıldı. `operationLockFile` eklendi.
- `lib/features/updates/domain/app_update_info.dart`: `integrityProblem` eklendi; SHA küçük harfe normalize ediliyor.
- `lib/features/updates/data/app_update_checker.dart`: Güvensiz manifest reddediliyor. Bozuk manifest ile ağ hatası ayrı raporlanıyor. `catch (_)` daraltıldı.
- `lib/features/sync/infrastructure/udp_hub_discovery_client.dart`: `schemeResolver` ve `effectiveScheme` eklendi.
- `lib/features/sync/application/hub_connection_notifier.dart`: `hubDiscoveryClientProvider` pin'e göre şema seçiyor. Yeniden kurulma (rebuild) olmuyor.

**İstemci depolama (`packages/mms_client_storage`)**
- `lib/src/backup/database_backup_engine.dart`:
  - `encryptSafetyBackup` ve `customSafetyBackupSealer` eklendi.
  - `RestoreResult.safetyBackupEncrypted` eklendi.
  - `_sealSafetyBackup` eklendi.
  - 22 boş `catch` loglayan yardımcılara çevrildi.
- `lib/src/backup/backup_operation_lock.dart`: Yeni dosya.
- `lib/src/backup/scheduled_backup.dart`: Kilit meşgulse zamanlanmış tur hata kaydedilmeden atlanıyor.
- `lib/src/backup/google_drive_backup.dart`: `_ensureEncryptedPackageFor` eklendi.
- `lib/mms_client_storage.dart`: Yeni dışa aktarım (export).

**Hub (`test_spikes/spike_01_backend`)**
- `bin/server.dart`:
  - `caCertPath` artık `main()`'den geçiriliyor (PAIR-CA).
  - Restore yanıtına `safety_backup_encrypted` eklendi.
  - `/pairing/reject` için gövde doğrulaması eklendi.
- `lib/config/hub_config.dart`: `tls.ca_cert` eklendi; üretimde zorunlu.
- `config/hub_config.example.json`: `"ca_cert": "../certs/ca.crt"` eklendi.
- `scripts/install_mms_service.ps1` (v2.1):
  - Önce yapılandırma, secret, TLS ve CA kontrolü yapılıyor.
  - Ardından servis durduruluyor, eski dosyalar `bin.previous` altına alınıyor, yeni dosyalar kopyalanıyor.
  - Kurulum ve başlatma çıkış kodları kontrol ediliyor.
  - Başarısız güncellemede otomatik geri dönüş yapılıyor.
- `scripts/setup_service_acls.ps1`, `uninstall_mms_service.ps1`, `build_aot.ps1`: Yalnızca UTF-8 BOM eklendi.

**Kök betikler ve yapılandırma**
- `scripts/configure_hub_firewall.ps1`: BOM eklendi. `-RemoteAddress` parametresi eklendi (varsayılan `LocalSubnet`).
- `scripts/package_android_release.ps1`, `scripts/package_windows_release.ps1`: Yalnızca BOM eklendi.
- `.gitignore`: `manual_test_env/` ve `.mms_backup_operation.lock` eklendi.

**Veritabanı ve protokol**
- Şema değişikliği **YOK** (istemci v4, Hub v3).
- Sync sözleşmesi **değişmedi**: Outbox, FIFO, `client_seq`, hash, cursor, keşif yanıtı aynı.

## 6. Düzeltilen Hatalar

| Kod | Önem | Hata | Düzeltme | Test |
|---|---|---|---|---|
| AV-13 PS-BOM | **Kritik** | ACL ve kaldırma betikleri PowerShell 5.1'de ayrıştırılamıyordu (BOM'suz UTF-8 dosyada `—` karakteri `”` olarak okunuyor) | Unicode içeren tüm `.ps1` dosyalarına UTF-8 BOM eklendi | `rel01` BOM testi; 7 betiğin tamamı 5.1 ayrıştırıcısında 0 hata |
| AV-18 PAIR-CA | **Kritik** | Üretim Hub'ı eşleştirme CA'sını bilmiyordu; QR'da parmak izi `UNKNOWN`, `/ca-cert` 404 | `tls.ca_cert` eklendi; üretimde zorunlu; kurulum `ca.crt` yoksa duruyor | `rel01` PAIR-CA (3) |
| AV-12 TLS-DISC | Yüksek | Keşif yalnızca `http://` deniyordu; TLS'li üretim Hub'ına bağlanamıyordu | Pin varsa `https://`, HTTP'ye düşüş yok | `discovery_tls_scheme_test` (4) |
| AV-8 SEC-ABK | Yüksek | Android otomatik yedek açıktı: şifresiz DB ve `device_id` buluta/yeni cihaza kopyalanabiliyordu | Manifest ayarları ve veri çıkarma kuralları | `android_release_hardening_test` (4); debug derlemede birleşik manifest kontrolü |
| AV-9 SEC-SAFETY | Yüksek | Restore koruyucu kopyası şifresiz ve kalıcıydı (Hub'da token özetleri dahil) | Başarılı restore sonrası şifreli `.mmsbak`; eski dosyalara dokunulmadı | `restore_safety_snapshot_encryption_test` (6), Hub restore testi |
| AV-14 | Yüksek | Kurulum betiği güncellemede kilitli exe'nin üzerine yazmaya çalışıyordu; geri dönüş ve çıkış kodu kontrolü yoktu | v2.1 | `rel01` kurulum sırası testi (statik) |
| AV-10 BK-LOCK | Orta | Restore sırasında zamanlanmış yedek yanıltıcı "başarısız" kaydı ve 30 dk bekleme üretiyordu; süreçler arası kilit yoktu | `BackupOperationLock` | `backup_operation_lock_test` (7), `client_backup_operation_lock_test` (3) |
| AV-11 | Orta | Drive'a şifresiz dosya yüklenebilirdi | Ağ isteğinden önce paket ve manifest doğrulaması | `google_drive_backup_test` 8b, 8c |
| AV-15 | Orta | Firewall kuralları tüm uzak adreslere açıktı | `LocalSubnet` varsayılanı | `rel01` firewall kontrolü |
| AV-16 UPD-SEC | Orta | Güncelleme manifesti HTTP adres / SHA'sız paket kabul ediyordu; bozuk manifest "çevrimdışı" görünüyordu | `integrityProblem` ve hata ayrımı | `app_update_checker_security_test` (7) |
| AV-17 | Düşük | `/pairing/reject` bozuk gövdede 500 dönüyordu | Gövde doğrulaması, 400 | s4 TC-34 |
| Hijyen | — | `manual_test_env/init_test_env.dart` ve `write_scripts.py` (bilinen token'lar, admin secret) `.gitignore` dışındaydı | Dizin yok sayıldı; dosyalara dokunulmadı | `git check-ignore` |
| Doküman | — | `WINDOWS_HUB_RELEASE.md` içinde `\b` karakteri backspace'e dönüşmüştü (`dataackup_…`) | Düzeltildi | — |

## 7. Güvenlik Değerlendirmesi

| Konu | Bulgu | Durum |
|---|---|---|
| Android imzalama | `key.properties` yoksa derleme duruyor. Debug imza ancak `MMS_ALLOW_DEBUG_SIGNING=true` ile açılıyor ve uyarı veriyor. | VERIFIED (derleme çalıştırıldı) |
| Cleartext | Release'de `false`. Debug'da `true` (yerel geliştirme Hub'ı için). | VERIFIED (kod ve manifest) |
| APK'ya gömülü sır | Token, admin secret veya OAuth secret yok. Drive istemci kimliği yalnızca `--dart-define` ile veriliyor. | VERIFIED (kod incelemesi) |
| Android otomatik yedek | Kapatıldı | VERIFIED (birleşik manifest) |
| TLS pin / rotasyon | Pin uyuşmazlığı ayrı hata olarak gösteriliyor. Aynı CA ile yenilenen sertifika kabul ediliyor. | VERIFIED (gerçek TLS soket testleri) |
| Eşleştirme | Süresi dolan oturum 410, yanlış secret 401, 3 yanlış denemede kilit, onaysız poll 403, kasiyer token'ı ile onay/red 403, reddedilen cihaz token alamıyor ve DB'ye yazılmıyor, denetim kaydı tutuluyor | VERIFIED (s4: TC-01…34) |
| Admin uçları | Loopback ve admin secret zorunlu. Snapshot ucu da artık admin (ADR-017). | VERIFIED |
| Hub sırları | Admin secret kriptografik rastgele üretiliyor ve ekrana yazılmıyor. Config içinde düz metin secret reddediliyor. Pepper DPAPI ile korunuyor; DPAPI hatasında sistem kapalı kalıyor (fail-closed). | VERIFIED (kod ve testler); gerçek ACL BLOCKED |
| TLS eksikliği | Üretimde TLS veya sertifika yoksa servis açılmıyor (çıkış kodu 78). CA eksikse de açılmıyor (yeni). | VERIFIED |
| Loglar | `RedactingLogger` token, parola ve özel anahtarı maskeliyor. Drive hata metinlerinde `ya29.` ve `1//` desenleri maskeleniyor. Eşleştirme denetim kayıtlarında açık token yok (TC-19). | VERIFIED |
| Kalan zayıflıklar | Hub token doğrulaması cihaz sayısıyla doğrusal (O(n)). Güncelleme paketlerinde kod imzası yok. `manual_test_env` içindeki bilinen test token'ları ve şifresiz DB kopyaları diskte duruyor. | OWNER_APPROVAL_REQUIRED (D2/D3, A8) |

## 8. Mimari Değerlendirme

Ayrıntı: [`ARCHITECTURE_REVIEW.md`](./ARCHITECTURE_REVIEW.md) §5 (AV-8…AV-18) ve §10.
- Clean Architecture katman sınırları korundu. Yeni kod ilgili katmanda; UI'ya iş kuralı eklenmedi.
- Yeni arayüz veya soyutlama eklenmedi. Mevcut şifreleme, depolama ve manifest yolları yeniden kullanıldı (DRY).
- Yeni bağımlılık eklenmedi.
- Teknik borçlar:
  - Boş `catch` sayısı 48'den **26**'ya indi.
  - `server.dart` 4.051 satır, `ClientStorageRepository` 2.414 satır. Bunlar bilinçli olarak bölünmedi; davranış değiştirmeyen geniş bir refactor faz kabulünden önce gereksiz risk taşır.

## 9. Backup / Restore Son Güvenlik Denetimi (§10)

| Kontrol | Kanıt | Durum |
|---|---|---|
| Restore öncesi koruyucu yedek | s5a4 #5, `restore_safety_snapshot_encryption_test` #1–2 | VERIFIED |
| Koruyucu yedeğin şifreli saklanması (**yeni**) | Aynı test #1–5; Hub restore testi `safety_backup_encrypted: true` | VERIFIED |
| Outbox kayıtlarının korunması (RST-OUTBOX) | `restore_outbox_preservation_test` #1–5 | VERIFIED |
| `client_seq` geriye gitmez | Aynı test #2 | VERIFIED |
| Tenant / store / cihaz doğrulaması (RST-STORE) | s5a4, `restore_outbox_preservation_test`, `backup_file_transfer_test` | VERIFIED |
| Restore sırasında sync duraklatma (RST-SYNC) | Koordinatör #29–30. Kilit artık duraklatmadan önce alınıyor (`client_backup_operation_lock_test` #2). | VERIFIED |
| Hata durumunda canlı DB'nin yeniden açılması (RST-PAUSE) | `restore_outbox_preservation_test` (`resumeLiveDb` sayacı) | VERIFIED |
| Atomik swap, rollback, journal kurtarma, WAL checkpoint | s5a4 #10, #17, #20, #21 | VERIFIED (simülasyon); gerçek çökme BLOCKED (PAT-14) |
| Şifreli yedek bütünlüğü (HMAC, yanlış parola) | s5a4 #6; safety #6 | VERIFIED |
| Snapshot ucu yetkilendirmesi (SEC-SNAP) | s1 #3b (kasiyer token'ı 401/403, diske yazım yok) | VERIFIED |
| Yedek ve restore'un aynı anda çalışmaması (**yeni**) | BK-LOCK testleri (isolate sınırı dahil) | VERIFIED |
| Eski şifresiz koruyucu kopyalar | Otomatik silinmedi veya dönüştürülmedi. Prosedür: `BACKUP_AND_RESTORE_GUIDE.md` §7 | OWNER_APPROVAL_REQUIRED (D4) |

**Ödünleşim:** Restore artık bir PBKDF2 türetmesi daha yapıyor. Bu işlem ayrı isolate'te çalıştığı için arayüz donmuyor; donma 750 ms altında kalıyor (test ediliyor). Düşük donanımlı Android'de ek süre ölçülmedi (PAT-14).

## 10. Google Drive (§6) ve USB (§11)

**Google Drive** — Yazılım: COMPLETED. Otomatik test: VERIFIED (sahte uç noktalar). Gerçek hesap: **BLOCKED** (C1/C2, PAT-13). Kod yeniden yazılmadı.

| Kontrol | Durum |
|---|---|
| PKCE (S256), `state` doğrulaması, yalnızca `drive.file` | VERIFIED (#9–10) |
| Refresh token yalnızca güvenli depoda; hesap iptalinde yeniden yetki istenmesi | VERIFIED (#11) |
| Resumable upload; tekrar yükleme engeli (yerel kayıt ve uzak `appProperties`) | VERIFIED (#1–3) |
| Boyut ve MD5 doğrulaması; uyuşmazlıkta uzak dosyanın silinmesi | VERIFIED (#1, #7) |
| 401'de token yenileme; 503'te üstel bekleme; gecikmiş yükleme kuyruğu | VERIFIED (#4, #5, #8) |
| Token maskeleme | VERIFIED (kod incelemesi) |
| **Yalnızca şifreli paket (yeni)** | VERIFIED (#8b, #8c) |
| Android'den Drive | NOT_STARTED. Google Sign-In SDK gerekiyor (A6). |

**USB** — Yazılım: COMPLETED. Otomatik test: VERIFIED (`backup_file_transfer_test` 10/10). Fiziksel: **BLOCKED** (PAT-07).
- Doğrulanan senaryolar: hedef dosyanın üzerine yazılmaması, disk dolu, aygıtın çıkarılması, yarım dosya kalmaması, geri okumayla SHA-256 doğrulaması, başka cihaz/şube yedeğinin reddi.
- Android'de USB desteği yok; SAF ile erişim kapsam dışı.

## 11. Android Production Release (§5)

| Adım | Sonuç |
|---|---|
| `flutter build apk --release` (`key.properties` yok) | **BUILD FAILED in 40s**: "Release imzalama yapılandırılmadı…". Beklenen davranış (fail-closed). Debug anahtarıyla production APK **üretilmedi**. |
| `flutter build apk --debug` | Başarılı (85 sn). Birleşik manifest: `allowBackup="false"`, `fullBackupContent="false"`, `dataExtractionRules`. Manifest değişikliğini doğrulamak için yapıldı. |
| Release APK | **BLOCKED**: Owner B1 (imza anahtarı) gerekiyor. |

## 12. Windows Hub (§5, §11)

| Konu | Durum |
|---|---|
| Tek yapılandırma kaynağı (`hub_config.json`), bilinmeyen anahtarın reddi, üretimde TLS + başlık + **CA zorunluluğu** | VERIFIED (`rel01` 13/13) |
| WinSW tanımı (tek üretim XML'i, LocalService, `--config`, yeniden başlatma politikası 5/15/60 sn) | VERIFIED (statik) |
| Kurulum, güncelleme ve kaldırma betikleri | COMPLETED (v2.1, PS 5.1 ayrıştırma testi geçiyor). Gerçek SCM: BLOCKED (PAT-08, PAT-09) |
| ACL (Users erişimi yok; `ca.key` bulunursa kurulum durur) ve firewall (Private + LocalSubnet) | COMPLETED (betik). Gerçek doğrulama: BLOCKED (PAT-10) |
| Zamanlanmış yedek | VERIFIED (`hub_scheduled_backup_test` 8/8) |
| `MarketMmsSpike01` servisi | Bu makinede **kurulu ve çalışıyor**. Owner onayı olmadığı için dokunulmadı (D1). |
| Üretim yapılandırması bu makinede | Yok (`%ProgramData%\MarketMMS\config\hub_config.json` mevcut değil). |

## 13. Sync ve Outbox Doğrulamaları (§15)

Sözleşmeler değişmedi. Talimatta istenen senaryoların hepsi otomatik testlerle kapsanıyor:

| Senaryo | Doğrulayan test(ler) |
|---|---|
| Duplicate barkod | İstemci: `product_catalog_outbox_sync_test` (barkod çakışması reddi), `outbox_sequence_recovery_test` Senaryo 8 (başarısız kayıtta Outbox tutarlılığı); Hub: `product_upsert_test` (409) |
| Eşzamanlı stok girişi | `stock_receipt_test` (aynı `receiptId` ile 5 eşzamanlı çağrı → 1 uygulama; iki bağlantıda kayıpsız) |
| Aynı / farklı içerikli receipt ID | `stock_receipt_test`, Hub `stock_receipt_api_test` |
| Outbox FIFO, kalıcı hatada kuyruğun kilitlenmesi | `s5a3_outbox_sync_test` #8, #11; `outbox_sequence_recovery_test` |
| Sequence gap | Hub `bk02_1_hub_reconciliation_test`, `bk02_1_1_…`, `stock_receipt_api_test` (`ERR_CLIENT_SEQ_GAP`) |
| Idempotency conflict, idempotent replay | `s5a3_outbox_sync_test` #6; Hub `product_upsert_test`, `s5a3_sales_validation_test` (`ERR_IDEMPOTENCY_PAYLOAD_MISMATCH`) |
| Hub rewind (Hub geri yüklemesi sonrası HWM uzlaştırması) | Hub `bk02_1_hub_reconciliation_test` (1.1–1.3) |
| Offline satış ve yeniden bağlantı | `sync_reconnect_lifecycle_test`, `mobile_offline_usability_test` |
| Restore sonrası Outbox | `restore_outbox_preservation_test` |
| Yetkisiz snapshot | Hub `s1_api_hardening_test` #3b |
| TLS pin mismatch, sertifika rotasyonu | `tls_pinned_client_factory_test` (gerçek soket), `tls_pin_mismatch_sync_test` |
| Store/tenant izolasyonu | Hub ADR-014 testleri (`stock_receipt_api_test`, `bk02_*`), restore store testleri |
| Token güvenliği | Hub `s2_token_security_test`, `secure_storage_fail_closed_test` |

## 14. TDD Uygulama Sonuçları (RED → GREEN → REFACTOR)

| İş | RED (gözlenen) | GREEN | Not |
|---|---|---|---|
| SEC-ABK manifest | Davranışsal: 2 test başarısız (`allowBackup` yok, kurallar dosyası yok) | 4/4 | — |
| SEC-SAFETY | Derleme (parametre yok). s5a4 #5 değişen davranışı doğruladı. | 6/6 | Hub doğrulamaları uygulamadan **sonra** eklendi (ayrı RED yok) |
| BK-LOCK (paket) | Derleme (tür yok) | 7/7 + zamanlayıcı 14/14 | Refactor: `catch (_)` yerine tipli yakalama |
| BK-LOCK (uygulama) | Derleme (`operationLockFile` yok) | 3/3 | — |
| PS-BOM | Davranışsal: 6 betik ihlal | GREEN | Kurulum sırası testi düzeltmeden **sonra** yazıldı (RED yok) |
| Firewall alt ağ | Test ve değişiklik aynı adımda (RED ayrıca çalıştırılmadı) | GREEN | — |
| Eşleştirme TC-33 | Regresyon (mevcut davranış doğruydu; yapay RED üretilmedi) | GREEN | — |
| Eşleştirme TC-34 | Davranışsal: HTTP 500 | 400 | — |
| UPD-SEC | Davranışsal: 5 test başarısız | 7/7 | — |
| Drive koruması | Davranışsal: şifresiz dosya yüklendi (8b), yanlış dosya kabul edildi (8c) | 13/13 | Fikstürler gerçek şifreli pakete çevrildi |
| TLS-DISC | Davranışsal: şema `http` | 4/4 | Test 2b (yeniden kurulmama) çözüm değiştikten **sonra** yazıldı (RED yok) |
| PAIR-CA | Derleme (`caCertPath` getter yok) | 13/13 (`rel01`) | `s5a1`, s3 ve s4 regresyonları geçti |
| Motordaki boş `catch`'ler | — | — | Saf refactor; s5a4 ve restore testleriyle korundu |

## 15. Otomatik Test Sonuçları

Testler sıralı çalıştırıldı: süitler birbirini beklerken koştu (aralarında eşzamanlı yük yok). Süit içinde dosyalar araç varsayılanıyla koşar: `flutter test` paralel, Hub `-j 1`. Ara sonuçlar gizlenmedi.

| Süit | Komut | Başlangıç (bu oturum) | Nihai: Geçen | Başarısız | Çalıştırılamayan |
|---|---|---|---|---|---|
| Uygulama | `flutter test` | 243 | **261** | 0 | 0 |
| İstemci depolama | `flutter test` (`packages/mms_client_storage`) | 191 | **206** | 0 | 0 |
| Contracts | `dart test` (`packages/mms_contracts`) | 7 | **7** | 0 | 0 |
| Hub | `dart test -j 1` (`test_spikes/spike_01_backend`) | 219 | **226** | 0 | 0 |
| **Toplam** | | **660** | **700** | **0** | 0 |
| Entegrasyon (`integration_test/`, 2 dosya) | Gerçek cihaz gerekir | — | — | — | 2 (BLOCKED) |
| PowerShell ayrıştırma (5.1) | `Parser::ParseFile` (7 betik) | 2 betikte 8 hata | 0 hata | — | — |
| Statik analiz | `flutter analyze` / `dart analyze` | uygulama 0 · depolama 16 info · contracts 0 · Hub 18 info | **Aynı** (yeni uyarı yok; hepsi önceden var olan `deprecated_member_use`) | — | — |

**Ara çalıştırmalar (gizlenmedi):**
1. **İlk nihai turda depolama süiti 205 geçti, 1 başarısız oldu.**
   - Başarısız test: `backup_isolate_responsiveness_test`, 30 sn varsayılan zaman aşımı.
   - Neden: Test üretim gücünde (600.000 iterasyon) çalışıyor. Restore artık üçüncü bir PBKDF2 türetmesi yapıyor (koruyucu kopya şifreleme). Aynı anda s5a4 #15'in 600k benchmark'ı paralel koşuyordu.
   - Düzeltme: Teste 3 dk zaman aşımı verildi. Asıl doğrulama (UI isolate donması < 750 ms) **gevşetilmedi**.
   - Yeniden çalıştırma: 206/0.
2. **İlk nihai turda Hub 223 geçti.** Sonra PAIR-CA düzeltmesi yapıldı ve Hub süiti baştan çalıştırıldı: 226/0.
3. **Bilinçli olarak güncellenen beklentiler** (gerekçeleri test içinde yazılı):
   - s5a4 #5: koruyucu kopya artık `.mmsbak`.
   - `google_drive_backup_test` fikstürleri: rastgele bayt yerine gerçek şifreli paket.
4. **Kendi hatalarım:**
   - Python ile yapılan düzenlemelerde iki kez kaçış karakteri hatası oldu: test başlığındaki `'` ve belgede `\b`. Bu, önceki oturumdan kalan bir `\b` bozulmasının da fark edilmesini sağladı.
   - Bu hatalar test veya analiz sırasında yakalandı ve düzeltildi.

## 16. Fiziksel Kabul Testleri (§16)

Plan: [`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`](../PHYSICAL_ACCEPTANCE_TEST_PLAN.md).
- Her test için ön koşul, donanım, adımlar, beklenen sonuç, başarı kriteri, kanıt ve başarısızlık prosedürü yazılı.
- Tümü **BLOCKED**. Hiçbiri çalıştırılmadı ve başarılı gösterilmiyor.

| ID | Test | ID | Test |
|---|---|---|---|
| PAT-01 | Android kamera barkodu | PAT-09 | Servis çökmesi ve güncelleme geri dönüşü |
| PAT-02 | Windows USB HID okuyucu | PAT-10 | Gerçek ACL ve firewall |
| PAT-03 | Android Wi-Fi keşfi ve QR eşleştirme | PAT-11 | Release APK kurulumu |
| PAT-04 | LAN/internet kesintisi | PAT-12 | Gerçek TLS ve rotasyon |
| PAT-05 | Çok cihazda eşzamanlı satış | PAT-13 | Gerçek Google OAuth ve Drive |
| PAT-06 | Çok cihazda eşzamanlı stok girişi | PAT-14 | Restore sırasında kapanma |
| PAT-07 | Gerçek USB yedek/restore | PAT-15 | Uygulama kapalıyken zamanlanmış yedek |
| PAT-08 | Gerçek SCM kurulumu | | |

## 17. Owner Kararları *(3. Oturum Snapshot'ı — Güncel Onaylı ADR Durumları ve Teknik Düzeltmeler için [`decisions/README.md`](./decisions/README.md) ve [`PILOT_TECHNICAL_REMEDIATION_REPORT.md`](./PILOT_TECHNICAL_REMEDIATION_REPORT.md) Esastır)*

Güncel işlem listesi: [`OWNER_ACTION_CHECKLIST.md`](../OWNER_ACTION_CHECKLIST.md).
- Not: Bu tablo 21.11.2026 3. oturum anlık kaydıdır; sonrasında Owner ADR-015 (`CONFIRMED`), ADR-016 (`CONFIRMED`), ADR-018 §2.1 & §2.2 Seçenek C (`CONFIRMED`), ADR-019 (`DEFERRED_POST_PILOT` — geçici %20 KDV kısıtları) ve ADR-020 (`DEFERRED_POST_PILOT`) yönünde karar vermiş, ADR-017 TLS sınıflandırması ve güvenlik/kilit sertleştirmeleri uygulanmıştır.

| ADR / konu | Amaç | Kodla uyum (3. oturum) | Uygulandı mı | Güvenlik / bütünlük etkisi | 3. oturum önerilen durum | Güncel durum (`README.md`) |
|---|---|---|---|---|---|---|
| ADR-015 (+Ek A) | Tek Hub yapılandırması; betikler; CA | Uyumlu | Evet | Olumlu (fail-fast, PS 5.1, alt ağ, CA) | CONFIRMED önerilir | **CONFIRMED** (+Ek B) |
| ADR-016 (+Ek A) | Restore Outbox, zamanlanmış/USB/Drive yedek, koruyucu kopya şifreleme, BK-LOCK, Android yedek kapalı | Uyumlu | Evet | Olumlu (veri kaybı ve sızıntı kapandı) | CONFIRMED önerilir | **CONFIRMED** (+Ek B) |
| ADR-017 | Snapshot ucunun kapatılması, pin sınıflandırması | Uyumlu | Evet | Olumlu | CONFIRMED önerilir | **PARTIALLY_CONFIRMED / IN_REVIEW** |
| ADR-018 | Keşifte TLS | 2.1 uyumlu | 2.1 evet, Seçenek C | Olumlu; downgrade yok | 2.1 CONFIRMED; 2.2 karar | **CONFIRMED (Seçenek C)** + `P-BLOCK-1..3` |
| ADR-019 | Kategori/KDV senkronu | Tasarım | Hayır | Pilotta %20 KDV kısıtı | PROPOSED | **DEFERRED_POST_PILOT** |
| ADR-020 | Android'de uygulama kapalıyken yedek | Hazırlık uyumlu | Hata eşleme evet; WorkManager hayır | Kilit + Keystore hata eşleme | PROPOSED | **DEFERRED_POST_PILOT** |
| QR, Drive SDK, kod imzalama, merkezi hata izleme | Yeni bağımlılık, servis veya sertifika | — | Hayır | — | — | Karar (A6–A8) |

**Talimattaki çelişki hakkında not:**
- §7, WorkManager için "gerekli bağımlılık ve mimari değişiklikleri yap" diyor. §17 ise "WorkManager bağımlılığı kararı"nı Owner işi olarak listeliyor. Owner'ın önceki talimatı da yeni bağımlılıkları Owner kararına bırakıyor.
- Bu yüzden bağımlılık eklenmedi. Bağımlılık gerektirmeyen her şey yapıldı: süreçler arası kilit ve restore/yedek dışlaması.
- Tasarım ADR-020'de. Kritik bulgu: Keystore kanalı `MainActivity`'de olduğu için arka plan işçisi parolayı okuyamaz. Önce bu taşınmalı.

## 18. Kalan Riskler

- **Yüksek**
  - Fiziksel kabul testlerinin hiçbiri yapılmadı.
  - Üretim imza anahtarı ve TLS sertifikaları yok.
  - KDV oranı cihazlar arasında tutarsız olabilir: yeni cihaz %20 varsayılanıyla başlıyor (ADR-019).
  - Bilinen test token'ları ve şifresiz test DB kopyaları diskte duruyor (D2/D3).
  - `MarketMmsSpike01` servisi çalışıyor (D1).
- **Orta**
  - Android'de uygulama kapalıyken yedek alınmıyor.
  - Düşük donanımlı Android'de restore süresi ölçülmedi.
  - Güncellemede veritabanı otomatik geri alınmıyor; önce şifreli yedek alınmalı (runbook).
  - Hub'da güncelleme manifesti rotası yok.
  - QR görseli yok.
  - Güncelleme paketlerinde kod imzası yok.
  - Eski şifresiz koruyucu kopyalar duruyor (D4).
- **Düşük**
  - Hub token doğrulaması O(n).
  - 26 boş `catch` kaldı.
  - `server.dart` ve `ClientStorageRepository` büyük (TD-1/TD-2).
  - 34 analiz uyarısı (info) var: `sqlite3 dispose` kullanımı ileride kaldırılacak.

## 19. Kullanıma Hazır Olma Değerlendirmesi

**Gerçek market ortamı için: HAZIR DEĞİL.** Yazılım tarafında bilinen ve açık kalmış kritik veya yüksek öncelikli bir hata yok. Ancak:
1. Release APK ve üretim Hub'ı, Owner'ın anahtar ve sertifikaları olmadan kurulamaz (B1, B2).
2. Kurulum betikleri, eşleştirme ve keşif bu oturumda düzeltildi. Gerçek donanımda **hiç** çalıştırılmadılar.
3. Mali tutarlılık için KDV senkronu kararı (ADR-019) pilot öncesi verilmeli.

| Kriter (§22) | Durum |
|---|---|
| Repository ve son rapor karşılaştırıldı | VERIFIED (§2) |
| Mimari ve güvenlik denetimi | COMPLETED (§7, §8) |
| Bağımsız kod işleri | COMPLETED (Owner kararı gerektirenler hariç) |
| Eksik otomatik testler yazıldı ve çalıştırıldı | VERIFIED (+40 test, 700/0) |
| Backup/restore güvenliği | VERIFIED (otomatik) · BLOCKED (fiziksel) |
| Sync/Outbox bütünlüğü korundu | VERIFIED (sözleşme değişmedi) |
| Üretim yapılandırması denetlendi | COMPLETED (3 üretim engeli düzeltildi) |
| Drive ve USB yazılım seviyesinde doğrulandı | VERIFIED (sahte servis) · BLOCKED (gerçek) |
| Fiziksel kabul planı | COMPLETED |
| Owner işlemleri tek listede | COMPLETED |
| Dokümantasyon güncellendi | COMPLETED |
| Tek nihai rapor | COMPLETED (bu belge) |

## 20. Önerilen Sonraki Adımlar

1. Owner aşağıdaki maddeleri tamamlar:
   - **D1, D2, D3** (temizlik ve güvenlik)
   - **B1, B2** (anahtar ve sertifikalar)
   - **A1** (ADR onayları)
   - **A3** (KDV kararı)
2. Değişiklikleri mantıksal commit'lere bölün (A2). Commit öncesi `git status --ignored` ile hassas dosyaların dışarıda kaldığını doğrulayın.
3. Pilot kurulum: tek Hub, bir Windows kasa ve iki Android. Önerilen sıra:
   1. PAT-12 → PAT-08 → PAT-10 → PAT-11 → PAT-03
   2. Ardından satış, stok, kesinti ve yedek testleri.
4. ADR-019 onaylanırsa SYNC-CAT'i ayrı bir TDD iterasyonunda uygulayın.
5. ADR-020 ve A5 onaylanırsa WorkManager entegrasyonunu yapın ve PAT-15'i uygulayın.
6. Google Drive (C1/C2, PAT-13) en son yapılabilir. Hub yedeği ve USB pilot için yeterlidir.

---

**İlgili belgeler:**
- [`OWNER_ACTION_CHECKLIST.md`](../OWNER_ACTION_CHECKLIST.md)
- [`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`](../PHYSICAL_ACCEPTANCE_TEST_PLAN.md)
- [`ARCHITECTURE_REVIEW.md`](./ARCHITECTURE_REVIEW.md)
- [`LIVE_PROJECT_STATUS.md`](./LIVE_PROJECT_STATUS.md)
- [`PROJECT_STATUS.md`](./PROJECT_STATUS.md)
- [`decisions/README.md`](./decisions/README.md)
- [`operations/BACKUP_AND_RESTORE_GUIDE.md`](./operations/BACKUP_AND_RESTORE_GUIDE.md)
- [`release/WINDOWS_HUB_RELEASE.md`](./release/WINDOWS_HUB_RELEASE.md)
- [`release/ANDROID_RELEASE.md`](./release/ANDROID_RELEASE.md)
- [`PRODUCTION_DEPLOYMENT_RUNBOOK.md`](./PRODUCTION_DEPLOYMENT_RUNBOOK.md)
