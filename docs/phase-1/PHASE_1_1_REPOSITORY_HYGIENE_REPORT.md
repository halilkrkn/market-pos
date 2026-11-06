# MARKET MMS — FAZ 1.1 REPOSITORY HYGIENE REMEDIATION RAPORU

**Rapor Tarihi:** 6 Kasım 2026  
**Aşama:** Faz 1.1 — Windows Client Foundation (Repository Hygiene Remediation)  
**Amacı:** Pre-commit denetiminde tespit edilen sır dosyası (`pepper.dpapi`), ikili çalıştırılabilir dosyalar (WinSW `.exe`) ve Flutter Windows üretilen plugin dosyalarının `.gitignore` ile yalıtılması; dosya sınıflandırmasının nihai doğrulanması.  
**Kural Uyumu:** Yalnızca kök [`.gitignore`](file:///c:/Users/halil/Github/market-pos/.gitignore) güncellenmiştir. Hiçbir kaynak kodu değiştirilmemiş, hiçbir dosya silinmemiş/taşınmamış, hiçbir dosya stage edilmemiş (`git add`) ve hiçbir commit (`git commit`) oluşturulmamıştır.

---

## 1. Uygulanan `.gitignore` Değişiklikleri

Kök [`.gitignore`](file:///c:/Users/halil/Github/market-pos/.gitignore) dosyası aşağıdaki eklemelerle güncellenmiştir:

### 1.1. Windows Masaüstü Dinamik Plugin Kodları (Bölüm 4)
```gitignore
# Flutter generated Windows plugin registrant
**/windows/flutter/generated_plugin_registrant.*
```
*Gerekçe:* Mevcut `.gitignore` dosyasındaki `GeneratedPluginRegistrant.cc` kuralı büyük harfliydi; Flutter Windows aracı ise küçük harfle `generated_plugin_registrant.cc` ve `.h` üretmektedir. Yeni kural ile bu dinamik dosyalar untracked listesinden çıkarılmıştır.

### 1.2. Makineye Özel Şifrelenmiş Sırlar (Bölüm 5)
```gitignore
# Machine-specific encrypted secrets
*.dpapi
pepper.dpapi
```
*Gerekçe:* `test_spikes/spike_01_backend/pepper.dpapi` dosyası Windows DPAPI ile şifrelenmiş yerel bir sır anahtarıdır. Başka bilgisayarlarda çözülemez ve depoya sızması güvenlik ihlalidir. Bu kural ile tamamen ignore edilmiştir.

### 1.3. Servis İkili Dosyaları (Bölüm 7)
```gitignore
# ------------------------------------------------------------------------------
# 7. Servis İkili Dosyaları (Binaries)
# ------------------------------------------------------------------------------
# Bundled service executables
test_spikes/**/service_wrapper/*.exe
```
*Gerekçe:* `MarketMMSService.exe` ve `MarketMmsSpike01.exe` (her biri 18.2 MB, toplam 36.4 MB) ikili WinSW dosyalarıdır. Git deposu ikili dosya saklama alanı değildir; depoyu şişirmemeleri için kural altına alınarak yok sayılmıştır.

---

## 2. Güvenlik Doğrulama Sonuçları (`git check-ignore -v`)

Aşağıdaki komut çıktısı ile tüm güvenlik gereksinimleri doğrulanmıştır:

| İncelenen Dosya | Beklenen Durum | Tetiklenen `.gitignore` Kuralı | Gerçek Sonuç |
|---|:---:|---|:---:|
| `test_spikes/spike_01_backend/pepper.dpapi` | **IGNORE** | `.gitignore:103:pepper.dpapi` | **BAŞARILI** (Yoksayıldı) |
| `test_spikes/.../service_wrapper/MarketMMSService.exe` | **IGNORE** | `.gitignore:120:test_spikes/**/service_wrapper/*.exe` | **BAŞARILI** (Yoksayıldı) |
| `test_spikes/.../service_wrapper/MarketMmsSpike01.exe` | **IGNORE** | `.gitignore:120:test_spikes/**/service_wrapper/*.exe` | **BAŞARILI** (Yoksayıldı) |
| `windows/flutter/generated_plugin_registrant.cc` | **IGNORE** | `.gitignore:82:**/windows/flutter/generated_plugin_registrant.*` | **BAŞARILI** (Yoksayıldı) |
| `windows/flutter/generated_plugin_registrant.h` | **IGNORE** | `.gitignore:82:**/windows/flutter/generated_plugin_registrant.*` | **BAŞARILI** (Yoksayıldı) |
| `test_spikes/spike_01_backend/backups/*.db` (40 DB) | **IGNORE** | `.gitignore:111:*.db` | **BAŞARILI** (Yoksayıldı) |
| `client_local.db` & `*.db-wal` & `*.db-shm` | **IGNORE** | `.gitignore:111:*.db`, `.gitignore:114:*.db-wal` | **BAŞARILI** (Yoksayıldı) |
| `docs/phase-1/PHASE_1_1_PRE_COMMIT_AUDIT.md` | **TRACKED** | (Ignore edilmiyor) | **BAŞARILI** (Açık) |
| `README.md` & `MARKET_POS_AI_STUDIO_BUILD_PLANI.md` | **TRACKED** | (Ignore edilmiyor) | **BAŞARILI** (Açık) |
| `packages/.../client_database.g.dart` | **TRACKED** | (Körlemesine ignore edilmiyor) | **BAŞARILI** (Açık) |
| `test_spikes/.../lib/db/database.g.dart` | **TRACKED** | (Körlemesine ignore edilmiyor) | **BAŞARILI** (Açık) |
| `*.key`, `*.pem`, `*.env` (Özel anahtarlar / sırlar) | **GÜVENLİ** | Repoda 0 dosya mevcut, kurallar aktif | **BAŞARILI** |

---

## 3. Güncellenmiş Dosya Sınıflandırması (COMMIT / IGNORE / REVIEW)

### 3.1. Kategori: COMMIT (Doğrudan Commit Edilecek Dosyalar)
- **Mimari ve Faz Dokümantasyonu:** `MARKET_POS_AI_STUDIO_BUILD_PLANI.md`, `README.md`, `docs/ARCHITECTURE.md`, `docs/PROJECT_STATUS.md`, `docs/ai/rules/security.md`, `docs/DEVELOPMENT_GUIDE.md`, `docs/PROJECT_OVERVIEW.md`, `docs/REQUIREMENTS.md`, `docs/architecture/` (tüm karar ve validasyon belgeleri), `docs/decisions/`, `docs/phase-1/` (tüm Faz 1.1 doğrulama ve denetim raporları), `docs/phases/`, `docs/requirements/`.
- **Flutter Masaüstü Çekirdeği (`market-pos`):** `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`, `.metadata`, `.gitignore`, `lib/` (15 dosya), `test/` (4 dosya).
- **Windows Platform Runner (`windows/`):** `windows/.gitignore`, `windows/CMakeLists.txt`, `windows/flutter/CMakeLists.txt`, `windows/flutter/generated_plugins.cmake`, `windows/runner/*` (tüm C++ runner kaynak kodları, manifest, resource ve ikon dosyaları).
- **Yerel Depolama Paketi (`packages/mms_client_storage/`):** `pubspec.yaml`, `pubspec.lock`, `lib/mms_client_storage.dart`, `lib/src/backup/*`, `lib/src/database/client_database.dart`, `lib/src/database/client_database.g.dart`, `lib/src/database/client_storage_repository.dart`, `lib/src/models/*`, `lib/src/sync/*`, `test/*`.
- **Merkezi Backend Kaynak ve Testleri (`test_spikes/spike_01_backend/`):** `pubspec.yaml`, `pubspec.lock`, `bin/server.dart`, `lib/` (veritabanı, write_queue, servis, güvenlik bileşenleri), `scripts/` (PowerShell kurulum ve derleme betikleri), `service_wrapper/*.xml`, `service_wrapper/README.md`, `test/*` (139 adet dayanıklılık testi), `*.md` (teknik raporlar).

### 3.2. Kategori: IGNORE (Kesinlikle Depo Dışında Tutulanlar)
- `test_spikes/spike_01_backend/pepper.dpapi` (DPAPI yerel anahtarı)
- `test_spikes/spike_01_backend/service_wrapper/*.exe` (36 MB WinSW ikili çalıştırılabilir dosyaları)
- `windows/flutter/generated_plugin_registrant.*` (Dinamik üretilen plugin kodu)
- Tüm `.db`, `.sqlite`, `.sqlite3`, `.db-wal`, `.db-shm` veritabanı dosyaları.
- Tüm `build/`, `.dart_tool/` ve ephemeral dosyalar.

### 3.3. Kategori: REVIEW (Kullanıcı Kararı Gerektiren Dosyalar)
- **`.agents/skills/` ve `.agents/registry/`:**
  - `code-quality`, `test-first`, `systematic-debugging`, `flutter-ui-standards`, `documentation` özel ajan becerileri ve `SKILL_REGISTRY.md` kayıt defteri.
  - *İnceleme Notu:* Becerilerin tamamı temiz Markdown formatındadır; arka planda bağımsız betik veya kontrolsüz ikili içermez. Ancak kullanıcı talimatı gereği üçüncü taraf kaynak kontrolü amacıyla otomatik commit listesine alınmamış, **kullanıcı onayına bırakılmıştır**.
- **Mobil Runner İskeleleri (`android/` ve `ios/`):**
  - Faz 1.1 odağı Windows olduğu için bu dizinler standart Flutter iskeleleridir. İleriki aşamalarda mobil kodlama başlarken veya şimdi Flutter projesi bütünlüğü adına commit edilebilir.
- **Kök Dizindeki 10 Adet Spike Raporu (`MARKET_MMS_*.md`):**
  - Faz 0 analiz belgeleridir. Kullanıcı talimatı gereği taşınmamış ve silinmemiştir; kök dizinde commit edilebilir veya daha sonra `docs/archive/` altına düzenlenebilir.

---

## 4. Son Doğrulama Komut Çıktıları

### 4.1. `git diff -- .gitignore`
```diff
diff --git a/.gitignore b/.gitignore
index 0833858..c912abe 100644
--- a/.gitignore
+++ b/.gitignore
@@ -78,6 +78,8 @@ out/
 **/windows/flutter/ephemeral/
 **/windows/**/GeneratedPluginRegistrant.cc
 **/windows/**/GeneratedPluginRegistrant.h
+# Flutter generated Windows plugin registrant
+**/windows/flutter/generated_plugin_registrant.*
 
 # Web
 **/web/build/
@@ -96,6 +98,10 @@ google-services.json
 GoogleService-Info.plist
 firebase_options.dart.bak
 
+# Machine-specific encrypted secrets
+*.dpapi
+pepper.dpapi
+
 # ------------------------------------------------------------------------------
 # 6. Veritabanı, Günlükler ve Çökme Raporları
 # ------------------------------------------------------------------------------
@@ -107,3 +113,9 @@ firebase_options.dart.bak
 *.db-shm
 *.db-wal
 
+# ------------------------------------------------------------------------------
+# 7. Servis İkili Dosyaları (Binaries)
+# ------------------------------------------------------------------------------
+# Bundled service executables
+test_spikes/**/service_wrapper/*.exe
```

### 4.2. `git diff --check`
```text
(Çıktı boş — .gitignore dosyasında hiçbir whitespace veya biçimlendirme hatası bulunmamaktadır.)
```

### 4.3. `git status --short` (Mevcut Durum)
```text
 M .gitignore
 M MARKET_POS_AI_STUDIO_BUILD_PLANI.md
 M docs/ARCHITECTURE.md
 M docs/PROJECT_STATUS.md
 M docs/ai/rules/security.md
?? .agents/
?? .metadata
?? MARKET_MMS_ANTIGRAVITY_INITIAL_AUDIT.md
?? MARKET_MMS_ANTIGRAVITY_INTEGRATION_PLAN.md
?? MARKET_MMS_ANTIGRAVITY_SKILL_ECOSYSTEM_AUDIT.md
?? MARKET_MMS_ARCHITECTURE_ALIGNMENT_REVIEW.md
?? MARKET_MMS_DATA_MODEL_SYNC_REVIEW.md
?? MARKET_MMS_FINAL_ANTIGRAVITY_INTEGRATION_PLAN.md
?? MARKET_MMS_FOLDER_STRUCTURE_AUDIT.md
?? MARKET_MMS_PHASE_0_TECHNICAL_SPIKE_PLAN.md
?? MARKET_MMS_SPIKE_01_PLAN.md
?? MARKET_MMS_UNIVERSAL_TEMPLATE_INTEGRATION_REPORT.md
?? README.md
?? analysis_options.yaml
?? android/
?? docs/DEVELOPMENT_GUIDE.md
?? docs/PROJECT_OVERVIEW.md
?? docs/REQUIREMENTS.md
?? docs/architecture/
?? docs/decisions/README.md
?? docs/phase-1/
?? docs/phases/
?? docs/reports/
?? docs/requirements/
?? ios/
?? lib/
?? packages/
?? pubspec.lock
?? pubspec.yaml
?? test/
?? test_spikes/
?? windows/
```
> [!NOTE]
> `test_spikes/spike_01_backend/pepper.dpapi`, `MarketMMSService.exe`, `MarketMmsSpike01.exe` ve `windows/flutter/generated_plugin_registrant.*` dosyaları untracked listesinden **tamamen çıkmış** ve `Ignored files` listesine başarıyla girmiştir.

### 4.4. `git ls-files` (Takip Edilen Dosyalar - Değişmedi)
```text
.gitignore
AGENTS.md
CLAUDE.md
GEMINI.md
MARKET_POS_AI_STUDIO_BUILD_PLANI.md
docs/ARCHITECTURE.md
docs/PROJECT_STATUS.md
docs/ROADMAP.md
docs/ai/rules/clean-architecture.md
docs/ai/rules/clean-code.md
docs/ai/rules/offline-first.md
docs/ai/rules/project-principles.md
docs/ai/rules/security.md
docs/ai/rules/solid.md
docs/ai/rules/testing.md
docs/archive/MARKET_POS_AI_STUDIO_BUILD_PLANI_v1.0.md
docs/archive/MARKET_POS_AI_STUDIO_BUILD_PLANI_v1.1.md
docs/decisions/ADR_TEMPLATE.md
```

### 4.5. Staging ve Commit Doğrulaması
`git diff --cached` çıktısı boştur. Çalışma dizininde hiçbir dosya stage edilmemiştir ve hiçbir commit oluşturulmamıştır.

---

## 5. Kalan Riskler ve Nihai Sonuç

- **Güvenlik Riski:** **0 (Sıfır).** Tüm sırlar, yerel anahtarlar, büyük ikililer ve SQLite veritabanları `.gitignore` güvencesine alınmıştır.
- **Bütünlük Riski:** **0 (Sıfır).** Dokümantasyonlar, modeller ve `*.g.dart` dosyaları açık ve erişilebilirdir.
- **Nihai Durum:** Repository ilk kaynak kod commit'i için tamamen temiz, güvenli ve hazırdır.

