# PHASE C — Windows Installer: Kapsam Taslağı

- **Durum:** **TASLAK — Owner onayı bekliyor.** Bu belge bir şartname önerisidir; **installer geliştirmesi başlamadı**. Kod, betik veya bağımlılık değişikliği içermez.
- **Tarih:** 23 Kasım 2026 (2. tur)
- **Okuyucu:** Owner (kapsam onayı) ve installer'ı geliştirecek/inceleyecek mühendis.
- **İlgili belgeler:** [`MASTER_ROADMAP.md`](../MASTER_ROADMAP.md) Faz 7, [`WINDOWS_HUB_RELEASE.md`](../release/WINDOWS_HUB_RELEASE.md), [`PRODUCTION_DEPLOYMENT_RUNBOOK.md`](../PRODUCTION_DEPLOYMENT_RUNBOOK.md), [`OWNER_ACTION_CHECKLIST.md`](../../OWNER_ACTION_CHECKLIST.md), [`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`](../../PHYSICAL_ACCEPTANCE_TEST_PLAN.md) (`PAT-08…PAT-10`).

---

## 1. Terim ayrımı: "Faz C" / "C1–C2" / "PHASE C" aynı şey değildir

Projede "C" harfi üç farklı anlamda kullanılmıştır. Bu belge yalnızca üçüncüsünü tanımlar; ilk ikisinin anlamı **değişmez**.

| Terim | Nerede | Anlamı | Durum |
|---|---|---|---|
| **Faz C (tarihsel, Release 1.0)** | `LIVE_PROJECT_STATUS.md` (21 Kasım 2026 Faz A–F), `BACKUP_AND_RESTORE_GUIDE.md` §4 | İstemci **Google Drive şifreli yedek listeleme / `.part` sürdürmeli indirme / doğrulamalı geri yükleme** | Kodlandı; saha doğrulaması `PAT-17` **BLOCKED** |
| **Faz A–D (eşleştirme protokolü)** | `PILOT_PROTOCOL_BLOCKERS_*` belgeleri | TLS bootstrap protokol adımları (Faz C = CA-pinned HTTPS istemcisinin kurulması) | Kodlandı (`P-BLOCK-2`) |
| **`C1` / `C2` (Owner aksiyonları)** | `OWNER_ACTION_CHECKLIST.md` | `C1` Google Cloud projesi, `C2` Google OAuth yapılandırması (Desktop + Android + Web client ID) | Owner aksiyonu, **değişmedi** |
| **PHASE C — Windows Installer** | Bu belge | Windows Master Hub + Windows Client için kurulum/güncelleme/kaldırma paketi | **Şartname taslağı**; `MASTER_ROADMAP.md` Faz 7 "Windows Hub installer" maddesinin alt kapsamı |

Öneri: İleride karışıklığı önlemek için bu fazın belgelerde **"PHASE C (Windows Installer)"** veya **"INST"** önekiyle anılması.

## 2. Bugünkü durum (kodla doğrulanmış)

Kurulum şu anda **betik tabanlı** pilot paketiyle yapılır (installer yok):
- `scripts/package_windows_release.ps1` → `dist\windows_release\` (SHA-256 manifestli paket).
- `test_spikes/spike_01_backend/scripts/build_aot.ps1` → `mms_backend.exe` (Dart AOT) + `sqlite3.dll`.
- `test_spikes/spike_01_backend/scripts/install_mms_service.ps1` / `uninstall_mms_service.ps1` → WinSW ile `NT AUTHORITY\LocalService` Windows Service.
- `test_spikes/spike_01_backend/scripts/setup_service_acls.ps1` → `%ProgramData%\MarketMMS` NTFS ACL'leri.
- `scripts/configure_hub_firewall.ps1` → güvenlik duvarı kuralları.
- Tek yapılandırma kaynağı `hub_config.json` (`REL-01`), TLS sertifikaları `%ProgramData%\MarketMMS\certs\` (`B2`).

## 3. Ön koşullar (installer geliştirmesine başlamadan)

1. **`PAT-08…PAT-10`** (servis kurulumu, güncelleme/geri dönüş) betik tabanlı paketle sahada geçmiş olmalı — installer, sahada doğrulanmış adımları paketlemelidir.
2. **`D1`**: Geliştirme ortamındaki `MarketMmsSpike01` servisinin Owner tarafından kaldırılması (installer bu servisi **asla** otomatik kaldırmaz; bkz. §6).
3. **`B2`** üretim TLS sertifika yöntemi kesinleşmiş olmalı (installer sertifika üretmez; yerleştirme/doğrulama adımı sunar).
4. **Owner kararları (yeni):** (a) installer teknolojisi (ör. MSIX, Inno Setup, WiX — her biri yeni bağımlılık/araç demektir), (b) kod imzalama sertifikası, (c) Hub ve Windows Client'ın tek pakette mi ayrı paketlerde mi dağıtılacağı.
5. Commit öncesi bu turdaki S1–S6 düzeltmelerinin kabulü.

## 4. Kapsam (önerilen)

- Hub servis ikilileri (`mms_backend.exe`, `sqlite3.dll`, WinSW) ve Windows Client (Flutter Windows) kurulumu.
- `%ProgramData%\MarketMMS\{config,data,backups,security,certs,logs}` düzeninin oluşturulması ve mevcut `setup_service_acls.ps1` ile **aynı** ACL modeli (`SYSTEM`, `Administrators`, servis SID; `Users`/`Everyone` yok).
- `NT AUTHORITY\LocalService` ile servis kaydı, otomatik başlatma, kurtarma (restart) politikası; mevcut **12 saniyelik global kapanış bütçesine** uyan durdurma.
- `hub_config.json` için rehberli ilk değer üretimi (`REL-01` tek kaynak; ortam değişkeni karışımı yok).
- Güvenlik duvarı kuralları (mevcut betikle aynı portlar).
- **Yerinde güncelleme:** veri ve sırlar korunarak ikili değişimi + başarısızlıkta otomatik geri dönüş (`PAT-09`).
- **Kaldırma:** varsayılan olarak veri, yedekler ve sırlar **korunur**; tam silme yalnızca açık, ayrı onayla.
- Kısayollar ve Windows Client'ın Hub adresi/eşleştirme ilk açılış akışına yönlendirilmesi (eşleştirme mantığı değişmez).

## 5. Kapsam dışı

- Android APK dağıtımı (ayrı: `ANDROID_RELEASE.md`, `B1`).
- Otomatik güncelleme sunucusu / uzaktan güncelleme kanalı.
- Çok kiracılı (SaaS) kurulum, banka POS terminali entegrasyonu.
- Google Cloud / OAuth kurulumu (`C1/C2` Owner aksiyonu olarak kalır; Hub Drive bağlantısı uygulama içi PKCE ile yapılır).
- Şema/protokol/ADR değişiklikleri, yedek formatı değişiklikleri.
- Installer'ın sır üretmesi veya taşıması: `pepper.dpapi`, `backup_recovery_key.dpapi`, `backup_drive_oauth.dpapi` installer tarafından **oluşturulmaz, okunmaz, kopyalanmaz** (servis ilk çalışmada/uygulama içinden üretir).

## 6. Güvenlik ve veri koruma kuralları (bağlayıcı öneri)

- Güncelleme ve kaldırma `market_master.db`, `backups\`, `security\*.dpapi` dosyalarını **değiştirmez**; kabul testinde dosya karmaları öncesi/sonrası karşılaştırılır.
- `MarketMmsSpike01` veya başka bir MMS servisi algılanırsa installer **durur ve uyarır**; servisi durdurmaz/kaldırmaz/yeniden yapılandırmaz.
- Gerçek veritabanına yazan hiçbir "ilk kurulum demo verisi" eklenmez.
- İmzasız ikili ile üretim kurulumu yapılmaz (Owner kararı `3.4(b)` sonrası).

## 7. Kabul kriterleri (taslak)

| # | Kriter | Doğrulama |
|---|---|---|
| INST-AC-01 | Temiz Windows 10/11 PC'de teknik bilgisi olmayan kullanıcı Hub'ı yönetici onayı dışında ek komut çalıştırmadan kurar | Fiziksel test (yeni `PAT`) |
| INST-AC-02 | Servis `NT AUTHORITY\LocalService` ile çalışır; ACL'ler `setup_service_acls.ps1` modeliyle birebir | `icacls` çıktısı + `PAT-08` |
| INST-AC-03 | Yerinde güncelleme sonrası DB ve `security\*.dpapi` karmaları değişmez; servis 12 s içinde durur ve yeni sürümle açılır | Fiziksel test + karma karşılaştırması (`PAT-09`) |
| INST-AC-04 | Güncelleme başarısız olursa önceki sürüme otomatik dönülür, veri kaybı olmaz | Fiziksel test (`PAT-09` geri dönüş) |
| INST-AC-05 | Kaldırma varsayılan olarak veriyi korur; yeniden kurulumda aynı veriyle açılır | Fiziksel test |
| INST-AC-06 | `MarketMmsSpike01` mevcutsa kurulum durur ve kullanıcıya bildirir; o servise dokunulmaz | Fiziksel test (izole makinede) |
| INST-AC-07 | Kurulumdan sonra eşleştirme (`PAT-03`) ve TLS doğrulaması (`PAT-12`) değişmeden geçer | Fiziksel test |
| INST-AC-08 | Installer ve ikililer imzalıdır; SmartScreen/imza doğrulaması geçer | Fiziksel test |

Bu kriterlerin hiçbiri şu an **karşılanmış değildir**; installer yoktur.
