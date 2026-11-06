# MARKET MMS — FAZ 1.1 GIT PRE-COMMIT DENETİM VE DOSYA SINIFLANDIRMA RAPORU

**Rapor Tarihi:** 6 Kasım 2026  
**Aşama:** Faz 1.1 — Windows Client Foundation (Git Pre-Commit Audit)  
**Amacı:** İlk kaynak kod commit'i öncesinde çalışma dizinindeki tüm dosyaların, `.gitignore` kurallarının, gizlilik/güvenlik gereksinimlerinin ve takip durumunun ayrıntılı denetimi.  
**Kural Uyumu:** Bu denetim sırasında hiçbir dosya değiştirilmemiş, silinmemiş, taşınmamış, stage edilmemiş (`git add`) veya commit oluşturulmamıştır (`git commit`). `.gitignore` değiştirilmemiştir.

---

## 1. Git Repository Durumu

### 1.1. `git status` Çıktısı
```text
On branch main
Your branch is up to date with 'origin/main'.

Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
	modified:   MARKET_POS_AI_STUDIO_BUILD_PLANI.md
	modified:   docs/ARCHITECTURE.md
	modified:   docs/PROJECT_STATUS.md
	modified:   docs/ai/rules/security.md

Untracked files:
  (use "git add <file>..." to include in what will be committed)
	.agents/
	.metadata
	MARKET_MMS_ANTIGRAVITY_INITIAL_AUDIT.md
	MARKET_MMS_ANTIGRAVITY_INTEGRATION_PLAN.md
	MARKET_MMS_ANTIGRAVITY_SKILL_ECOSYSTEM_AUDIT.md
	MARKET_MMS_ARCHITECTURE_ALIGNMENT_REVIEW.md
	MARKET_MMS_DATA_MODEL_SYNC_REVIEW.md
	MARKET_MMS_FINAL_ANTIGRAVITY_INTEGRATION_PLAN.md
	MARKET_MMS_FOLDER_STRUCTURE_AUDIT.md
	MARKET_MMS_PHASE_0_TECHNICAL_SPIKE_PLAN.md
	MARKET_MMS_SPIKE_01_PLAN.md
	MARKET_MMS_UNIVERSAL_TEMPLATE_INTEGRATION_REPORT.md
	README.md
	analysis_options.yaml
	android/
	docs/DEVELOPMENT_GUIDE.md
	docs/PROJECT_OVERVIEW.md
	docs/REQUIREMENTS.md
	docs/architecture/
	docs/decisions/README.md
	docs/phase-1/
	docs/phases/
	docs/reports/
	docs/requirements/
	ios/
	lib/
	packages/
	pubspec.lock
	pubspec.yaml
	test/
	test_spikes/
	windows/

no changes added to commit (use "git add" and/or "git commit -a")
```

### 1.2. `git diff --cached` Çıktısı
```text
(Çıktı boş — Staging alanında hiçbir dosya bulunmamaktadır.)
```

### 1.3. `git diff --stat` (Mevcut Takip Edilen 4 Dosya)
```text
 MARKET_POS_AI_STUDIO_BUILD_PLANI.md | 46 +++++++++++++-----------
 docs/ARCHITECTURE.md                | 48 +++++++++++++------------
 docs/PROJECT_STATUS.md              | 71 ++++++++++++++++++++++++++-----------
 docs/ai/rules/security.md           | 13 +++----
 4 files changed, 109 insertions(+), 69 deletions(-)
```

---

## 2. `.gitignore` Değerlendirmesi

Kök dizindeki [`.gitignore`](file:///c:/Users/halil/Github/market-pos/.gitignore) ve platform alt dizinlerindeki (`android/.gitignore`, `ios/.gitignore`, `windows/.gitignore`) kurallar kapsamlı biçimde denetlenmiştir.

### 2.1. Başarıyla Filtrelenen Alanlar (GÜÇLÜ YÖNLER)
- **Derleme Çıktıları:** `build/`, `.dart_tool/`, `ios/Flutter/ephemeral/`, `windows/flutter/ephemeral/` tamamen filtrelenmektedir.
- **İşletim Sistemi Geçici Dosyaları:** `Thumbs.db`, `Desktop.ini`, `.DS_Store` vb. filtrelenmektedir.
- **IDE Yapılandırmaları:** `.idea/`, `*.iml`, VS Code `.vscode/*` (yalnızca `launch.json`, `tasks.json` hariç tutularak) filtrelenmektedir.
- **Gerçek Veritabanları ve WAL Kilitleri:** `*.db`, `*.sqlite`, `*.sqlite3`, `*.db-wal`, `*.db-shm` kuralları sayesinde `test_spikes/spike_01_backend/backups/` altındaki 40 adet test yedek veritabanı Git tarafından başarıyla yok sayılmaktadır (`git status --ignored`).
- **Sertifikalar ve Standart Sırlar:** `*.env`, `*.key`, `*.keystore`, `*.pem`, `*.p12` kuralları aktiftir.

### 2.2. Tespit Edilen Kritik `.gitignore` Açıkları ve Riskler (EKSİKLER)
1. **`pepper.dpapi` Dosyası:**
   - `test_spikes/spike_01_backend/pepper.dpapi` (262 bayt), sunucu token hash'leme biberini saklayan Windows DPAPI şifreli bir ikili bloğudur.
   - Mevcut `.gitignore` dosyasında `*.dpapi` kuralı bulunmadığı için bu dosya şu anda **UNTRACKED** olarak görünmekte ve yanlışlıkla commit edilme riski taşımaktadır!
2. **WinSW İkili Çalıştırılabilir Dosyaları (18 MB x 2 = 36 MB):**
   - `test_spikes/spike_01_backend/service_wrapper/MarketMMSService.exe` (18.243.033 bayt)
   - `test_spikes/spike_01_backend/service_wrapper/MarketMmsSpike01.exe` (18.243.033 bayt)
   - `.gitignore` kök dizinde genel `*.exe` kuralı barındırmamaktadır (yalnızca `build/` ignore edilmektedir). Bu iki dosya Git deposuna girerse repository boyutunu kalıcı olarak 36 MB şişirecektir.
3. **Windows Flutter Plugin Registrant Büyük/Küçük Harf Uyuşmazlığı:**
   - `.gitignore` [L79-L80](file:///c:/Users/halil/Github/market-pos/.gitignore#L79-L80): `**/windows/**/GeneratedPluginRegistrant.cc` kuralı mevcuttur.
   - Ancak Flutter Windows aracı dosyayı küçük harfle üretmektedir: `windows/flutter/generated_plugin_registrant.cc` ve `.h`.
   - Bu nedenle `windows/flutter/generated_plugin_registrant.cc` dosyası ignore edilememekte ve untracked listesinde görünmektedir.

---

## 3. Dosya Sınıflandırması (COMMIT / IGNORE / REVIEW)

Tüm proje dizinleri ve dosyaları 3 kategoriye ayrılmıştır:
- **COMMIT:** Repoya dahil edilmesi gereken temiz kaynak kodları, konfigürasyonlar ve kurallar.
- **IGNORE:** `.gitignore` kapsamına alınması ve depoya ASLA girmemesi gereken dosyalar (sırlar, ikili dosyalar, derleme artıkları).
- **REVIEW:** İnceleme ve kullanıcı kararı gerektiren dosyalar (kök dizindeki spike markdown raporları, mobil runner iskeleleri).

### 3.1. Kategori: COMMIT (Doğrudan Commit Edilmesi Önerilenler)

#### A. Dokümantasyon, Mimari ve Proje Kuralları
- `MARKET_POS_AI_STUDIO_BUILD_PLANI.md` (Güncel mimari plan)
- `docs/ARCHITECTURE.md` (Teknik mimari)
- `docs/PROJECT_STATUS.md` (Faz ve durum takibi)
- `docs/ai/rules/security.md` (Güvenlik kuralları)
- `README.md` (Proje genel tanıtımı)
- `docs/DEVELOPMENT_GUIDE.md`
- `docs/PROJECT_OVERVIEW.md`
- `docs/REQUIREMENTS.md`
- `docs/architecture/` (Tüm mimari karar ve doğrulama belgeleri)
- `docs/decisions/README.md`
- `docs/phase-1/` (Faz 1.1'e ait tüm doğrulama, remediation ve audit raporları)
- `docs/phases/` ve `docs/requirements/`
- `.agents/skills/` (Özel ajan becerileri: `code-quality`, `documentation`, `flutter-ui-standards`, `systematic-debugging`, `test-first`)

#### B. Kök Flutter Masaüstü Uygulaması (`market-pos`)
- `pubspec.yaml` & `pubspec.lock` (Bağımlılık tanımları)
- `analysis_options.yaml` (Linter ve statik analiz kuralları)
- `.metadata` (Flutter araç versiyon metadatası)
- `lib/` (15 adet Dart kaynak dosyası):
  - `lib/main.dart`
  - `lib/app/app.dart`
  - `lib/core/constants/api_endpoints.dart`
  - `lib/core/constants/app_constants.dart`
  - `lib/core/network/api_client.dart`
  - `lib/core/network/api_exception.dart`
  - `lib/core/network/api_response.dart`
  - `lib/core/storage/local_database_service.dart`
  - `lib/core/theme/app_theme.dart`
  - `lib/features/diagnostics/application/system_status_notifier.dart`
  - `lib/features/diagnostics/domain/system_status.dart`
  - `lib/features/diagnostics/presentation/screens/diagnostics_view.dart`
  - `lib/features/diagnostics/presentation/widgets/status_badge.dart`
  - `lib/features/shell/presentation/screens/main_shell_screen.dart`
  - `lib/features/shell/presentation/widgets/cashier_header_bar.dart`
- `test/` (4 adet test dosyası):
  - `test/core/network/api_client_test.dart`
  - `test/core/storage/local_database_service_test.dart`
  - `test/features/diagnostics/system_status_notifier_test.dart`
  - `test/features/shell/main_shell_screen_test.dart`

#### C. Windows Masaüstü Runner Dosyaları (`windows/`)
- `windows/.gitignore`
- `windows/CMakeLists.txt`
- `windows/flutter/CMakeLists.txt`
- `windows/flutter/generated_plugins.cmake`
- `windows/runner/CMakeLists.txt`
- `windows/runner/Runner.rc`
- `windows/runner/flutter_window.cpp` & `.h`
- `windows/runner/main.cpp`
- `windows/runner/resource.h`
- `windows/runner/runner.exe.manifest`
- `windows/runner/utils.cpp` & `.h`
- `windows/runner/win32_window.cpp` & `.h`
- `windows/runner/resources/app_icon.ico`

#### D. İstemci Depolama Paketi (`packages/mms_client_storage/`)
- `packages/mms_client_storage/pubspec.yaml` & `pubspec.lock`
- `packages/mms_client_storage/lib/mms_client_storage.dart`
- `packages/mms_client_storage/lib/src/backup/*` (Tüm yedekleme motoru dosyaları)
- `packages/mms_client_storage/lib/src/database/client_database.dart`
- `packages/mms_client_storage/lib/src/database/client_database.g.dart`
- `packages/mms_client_storage/lib/src/database/client_storage_repository.dart`
- `packages/mms_client_storage/lib/src/models/*` (Sepet ve transaction modelleri)
- `packages/mms_client_storage/lib/src/sync/*` (Outbox ve transport servisleri)
- `packages/mms_client_storage/test/*` (4 adet kapsamlı test dosyası)

#### E. Merkezi Sunucu Kaynak Kodları ve Betikleri (`test_spikes/spike_01_backend/`)
*(Not: İkili `.exe` ve `pepper.dpapi` hariç tutularak)*
- `test_spikes/spike_01_backend/pubspec.yaml` & `pubspec.lock`
- `test_spikes/spike_01_backend/bin/server.dart`
- `test_spikes/spike_01_backend/lib/` (Tüm veritabanı, servis ve güvenlik modülleri)
- `test_spikes/spike_01_backend/scripts/` (PowerShell AOT derleme ve servis kurulum betikleri)
- `test_spikes/spike_01_backend/service_wrapper/*.xml` (WinSW XML servis konfigürasyonları)
- `test_spikes/spike_01_backend/service_wrapper/README.md`
- `test_spikes/spike_01_backend/test/` (Tüm Spike ve dayanıklılık testleri)
- `test_spikes/spike_01_backend/*.md` (Spike teknik raporları)

---

### 3.2. Kategori: IGNORE (Kesinlikle Depoya Girmemesi Gerekenler)

1. **`test_spikes/spike_01_backend/pepper.dpapi`**
   - **Sebep:** DPAPI ile şifrelenmiş makineye özel yerel sır dosyası. Depoya commitlenmesi güvenlik açığıdır ve başka makinelerde çözülemez.
   - **Aksiyon:** `.gitignore` dosyasına `*.dpapi` kuralı eklenmelidir.
2. **`test_spikes/spike_01_backend/service_wrapper/*.exe`**
   - `MarketMMSService.exe` (18 MB)
   - `MarketMmsSpike01.exe` (18 MB)
   - **Sebep:** Toplam 36 MB'lık üçüncü taraf ikili WinSW çalıştırılabilir dosyalarıdır. Git deposu ikili dosya depolama alanı değildir; release artifact olarak veya kurulum betiğiyle dışarıdan indirilmelidir.
   - **Aksiyon:** `.gitignore` dosyasına eklenmeli veya `service_wrapper/*.exe` olarak filtrelenmelidir.
3. **`windows/flutter/generated_plugin_registrant.cc` & `.h`**
   - **Sebep:** Flutter tarafından `flutter build` anında dinamik üretilen plugin kayıt kodudur.
   - **Aksiyon:** `.gitignore` dosyasına `windows/flutter/generated_plugin_registrant.*` kuralı eklenmelidir.

---

### 3.3. Kategori: REVIEW (Kullanıcı Kararı Gerektiren Dosyalar)

#### A. Kök Dizindeki 10 Adet Spike Rapor Dosyası:
Kök dizinde dağınık duran aşağıdaki raporlar doğrudan kökte mi tutulmalı, yoksa `docs/archive/` veya `docs/reports/` altına mı taşınmalıdır?
- `MARKET_MMS_ANTIGRAVITY_INITIAL_AUDIT.md`
- `MARKET_MMS_ANTIGRAVITY_INTEGRATION_PLAN.md`
- `MARKET_MMS_ANTIGRAVITY_SKILL_ECOSYSTEM_AUDIT.md`
- `MARKET_MMS_ARCHITECTURE_ALIGNMENT_REVIEW.md`
- `MARKET_MMS_DATA_MODEL_SYNC_REVIEW.md`
- `MARKET_MMS_FINAL_ANTIGRAVITY_INTEGRATION_PLAN.md`
- `MARKET_MMS_FOLDER_STRUCTURE_AUDIT.md`
- `MARKET_MMS_PHASE_0_TECHNICAL_SPIKE_PLAN.md`
- `MARKET_MMS_SPIKE_01_PLAN.md`
- `MARKET_MMS_UNIVERSAL_TEMPLATE_INTEGRATION_REPORT.md`
*Tavsiye:* Tarihsel dokümantasyon bütünlüğü için ilk commit'te mevcut konumlarıyla commit edilebilir veya temizlik için `docs/archive/phase-0/` altına taşınabilir.

#### B. Mobil Platform İskeleleri (`android/` ve `ios/`):
Faz 1.1'in odağı "Windows Client Foundation" olduğu için `android/` ve `ios/` dizinleri şu anda temel Flutter iskele kodlarıdır (henüz mobil platform kodu yazılmamıştır).
- *Tavsiye:* Flutter projesinin bütünlüğü ve Android/iOS derleme altyapısının korunması adına bu temel iskelelerin ilk commit'e dahil edilmesi uygundur.

---

## 4. Güvenlik ve Gizlilik Denetim Bulguları

| İnceleme Konusu | Durum | Risk Seviyesi | Bulgu / Önlem |
|---|:---:|:---:|---|
| **Gerçek SQLite Veritabanları (`*.db`)** | **GÜVENLİ** | YOK | Tüm test veritabanları `*.db` kuralıyla başarıyla ignore edilmektedir. Repoda 0 adet DB mevcuttur. |
| **WAL & SHM Dosyaları (`*.db-wal`)** | **GÜVENLİ** | YOK | `.gitignore` kuralları aktiftir; hiçbir kilit dosyası repoya sızmamaktadır. |
| **Sertifika ve Özel Anahtarlar (`*.key`, `*.pem`)** | **GÜVENLİ** | YOK | Repoda hiçbir özel anahtar veya sertifika dosyası bulunmamaktadır. |
| **Ortam Değişkenleri (`*.env`)** | **GÜVENLİ** | YOK | `ios/Flutter/ephemeral/` altındaki `.env` dosyası başarıyla ignore edilmektedir. |
| **DPAPI Sır Dosyası (`pepper.dpapi`)** | **RİSKLİ** | **YÜKSEK** | `*.dpapi` kuralı eksiktir! Commit öncesi `.gitignore`'a eklenmeli ve dosya repoya stage edilmemelidir. |
| **Büyük İkili Dosyalar (WinSW `.exe`)** | **RİSKLİ** | **ORTA** | 36 MB'lık iki `.exe` dosyası repo şişmesine yol açacaktır. Commit kapsamından çıkarılmalıdır. |

---

## 5. Çözülmesi Gereken Sorunlar (Commit Öncesi Aksiyonlar)

İlk commit öncesinde kullanıcının onaylaması gereken 3 mikro-düzeltme:

1. **`.gitignore` Güncellemesi:**
   Kök `.gitignore` dosyasının sonuna aşağıdaki kuralların eklenmesi:
   ```gitignore
   # 7. DPAPI ve Özel Sır Dosyaları
   *.dpapi
   pepper.dpapi

   # 8. Servis Wrapper İkili Dosyaları
   test_spikes/**/service_wrapper/*.exe

   # 9. Windows Küçük Harfli Plugin Registrant
   **/windows/flutter/generated_plugin_registrant.*
   ```
2. **Kök Raporlarının Konumu:**
   Kök dizindeki 10 adet `MARKET_MMS_*.md` dosyasının ilk commit'te mevcut halleriyle mi yoksa `docs/` altına taşınarak mı commit edileceğine karar verilmesi.
3. **Commit Stratejisi:**
   `git add .` komutu **ASLA** kullanılmamalıdır. Dosyalar modüler gruplar halinde açık dosya yollarıyla stage edilmelidir.

---

## 6. Commit İçin Önerilen Açık Dosya Yolları Listesi

Kullanıcı onayı alındıktan sonra çalıştırılması tavsiye edilen güvenli ve ayrıştırılmış commit aşamaları:

### Aşama 1: Proje Kuralları, Dokümantasyon ve Ajan Becerileri
```bash
git add \
  MARKET_POS_AI_STUDIO_BUILD_PLANI.md \
  README.md \
  docs/ \
  .agents/ \
  MARKET_MMS_*.md
git commit -m "docs(phase-1): finalize phase 1.1 architecture, documentation and agent skills"
```

### Aşama 2: İstemci Depolama Paketi (`mms_client_storage`)
```bash
git add \
  packages/mms_client_storage/pubspec.yaml \
  packages/mms_client_storage/pubspec.lock \
  packages/mms_client_storage/lib/ \
  packages/mms_client_storage/test/
git commit -m "feat(storage): implement client Drift SQLite storage, backup engine and outbox sync"
```

### Aşama 3: Merkezi Sunucu ve Dayanıklılık Doğrulamaları (`spike_01_backend`)
*(Not: `pepper.dpapi` ve `.exe` dosyaları hariç tutulmuştur)*
```bash
git add \
  test_spikes/spike_01_backend/pubspec.yaml \
  test_spikes/spike_01_backend/pubspec.lock \
  test_spikes/spike_01_backend/bin/ \
  test_spikes/spike_01_backend/lib/ \
  test_spikes/spike_01_backend/scripts/ \
  test_spikes/spike_01_backend/service_wrapper/*.xml \
  test_spikes/spike_01_backend/service_wrapper/README.md \
  test_spikes/spike_01_backend/test/ \
  test_spikes/spike_01_backend/*.md
git commit -m "feat(backend): add Shelf HTTPS master backend, WinSW service config and durability tests"
```

### Aşama 4: Flutter Windows Masaüstü Uygulaması ve Platform Dosyaları
```bash
git add \
  pubspec.yaml \
  pubspec.lock \
  analysis_options.yaml \
  .metadata \
  .gitignore \
  lib/ \
  test/ \
  windows/ \
  android/ \
  ios/
git commit -m "feat(client): implement Windows desktop foundation, shell UI and local DB service"
```

---

## 7. Nihai Öneri ve Durum Özeti

- Mevcut çalışma dizinindeki kodlar Faz 1.1 kabul kriterlerini %100 karşılamaktadır (221 test yeşil, release derlemesi başarılı).
- Ancak `pepper.dpapi` (DPAPI anahtarı) ve `service_wrapper/*.exe` (36 MB binary) dosyaları doğrudan `git add .` yapılması halinde depoya sızacaktır.
- **Tavsiye:** Önce `.gitignore` dosyasına yukarıda belirtilen 3 kural eklenmeli, ardından yukarıdaki modüler açık dosya yolları kullanılarak temiz ve profesyonel bir commit serisi oluşturulmalıdır.
- **Taahhüt:** Bu rapor tamamlandığında hiçbir dosya stage edilmemiş (`git status` temiz) ve hiçbir commit oluşturulmamıştır.

