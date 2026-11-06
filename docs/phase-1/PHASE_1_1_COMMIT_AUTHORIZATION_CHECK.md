# MARKET MMS — Faz 1.1 Commit Authorization Check

**Belge Sürümü:** 1.0  
**Tarih:** 6 Kasım 2026  
**Aşama:** Faz 1.1 — Windows Client Foundation (Nihai Commit Yetkilendirme Denetimi)  
**Durum:** Denetim Tamamlandı / Şartlı Onay (PARTIAL)  
**Referans Plan:** `MARKET_POS_AI_STUDIO_BUILD_PLANI.md` (v1.2)  
**İlgili Belgeler:** `docs/phase-1/PHASE_1_1_FINAL_PRE_COMMIT_REVIEW.md`, `docs/phase-1/PHASE_1_1_REPOSITORY_HYGIENE_REPORT.md`  

---

## 1. Genel Denetim Özeti ve Karar Matrisi

Bu rapor, Faz 1.1 kapsamında gerçekleştirilecek ilk kaynak kod commit'i öncesinde, yapay zekâ becerilerinin (Agent Skills) yasal telif/lisans durumunu, servis sarmalayıcısının (WinSW) ikili dosya sağlama güvenliğini ve 4 aşamalı commit planının izolasyon kurallarını kesinleştirmek üzere hazırlanmıştır.

### Başlık Bazında Değerlendirme Tablosu

| Denetim Başlığı | Değerlendirilen Kapsam | Sonuç | Temel Gerekçe |
| :--- | :--- | :---: | :--- |
| **1. Agent Skills Lisans Doğrulaması** | `.agents/skills/` altındaki 5 becerinin menşei, lisansı, telif bildirimi ve dosya durumu | **PARTIAL** | 3 becerinin üst repo/MIT lisansı doğrulanmış, ancak repoda resmi MIT `LICENSE` ve telif bildirimleri eksiktir; 2 beceri ise iç derleme olup harici repo URL'si bulunmamaktadır. |
| **2. WinSW Doğrulaması** | WinSW v2.12.0 resmi release, x64 mimarisi, resmi SHA256 ve betik doğrulama planı | **PASS** | Resmi GitHub release kaynağı, x64 mimarisi ve resmi SHA256 (`05b82d46...`) kesin olarak doğrulanmış, betik entegrasyonu tanımlanmıştır. |
| **3. Commit Planı İzolasyon Kontrolü** | 4 commit grubunun ayrımı, pubspec hiyerarşisi, çakışmasızlık, sır/ikili izolasyonu | **PASS** | Kök ve alt paket pubspec'leri ayrık, kümeler çakışmasız, `.gitignore` ilk commit'te, tüm sırlar/ikililer kesin olarak dışlanmıştır. |

---

## 2. Bölüm 1: Agent Skills Lisans ve Telif Doğrulaması (PARTIAL)

`.agents/skills/` dizini altında bulunan 5 adet yapay zekâ becerisi (`SKILL.md`) telif hakları, MIT lisans yükümlülükleri ve depo içi yasal bildirimler açısından incelenmiştir.

### 2.1. Beceri Bazında Lisans ve Provenance Denetimi

| Beceri | Belirtilen Kaynak | Doğrulanabilir Repository URL | Kaynak Commit / Tag | Resmi Lisans Durumu | Depo İçi LICENSE / Notice Durumu | Önerilen Karar |
| :--- | :--- | :--- | :--- | :--- | :--- | :---: |
| **`code-quality`** | MMS İlkeleri & Matt Pocock | **Doğrulanamadı** (Harici Dart/Clean Architecture reposu yok; MMS'e özgü derleme) | `v1.0 (Curated)` (İçsel etiket) | SKILL_REGISTRY tablosunda "MIT" beyan edilmiş | **YOK** (`LICENSE` dosyası, telif sahibi veya MIT metni bulunmuyor) | **DEFER** |
| **`test-first`** | `obra/superpowers` (Jesse Vincent) | `https://github.com/obra/superpowers` | `e9c3a1b` | Orijinal repo MIT lisanslıdır | **EKSİK** (Metin içinde anma var, ancak resmi MIT copyright ve permission notice dosyası yok) | **DEFER** |
| **`systematic-debugging`** | `obra/superpowers` (Jesse Vincent) | `https://github.com/obra/superpowers` | `e9c3a1b` | Orijinal repo MIT lisanslıdır | **EKSİK** (Metin içinde anma var, ancak resmi MIT copyright ve permission notice dosyası yok) | **DEFER** |
| **`flutter-ui-standards`** | `nextlevelbuilder/ui-ux-pro-max-skill` | `https://github.com/nextlevelbuilder/ui-ux-pro-max-skill` | `3b8d14e` | Orijinal repo MIT lisanslıdır | **EKSİK** (Metin içinde adaptasyon ifadesi var, ancak resmi telif metni ve LICENSE dosyası yok) | **DEFER** |
| **`documentation`** | Universal Project Template | **Doğrulanamadı** (Genel şablon konsepti, MMS'e özelleştirilmiş) | `v1.0-balanced` (Şablon sürümü) | Belirsiz (SKILL_REGISTRY tablosunda MIT) | **YOK** (Telif sahibi, repo URL veya lisans metni bulunmuyor) | **DEFER** |

### 2.2. MIT Lisansı Hukuki Yükümlülük Analizi

MIT Lisansı son derece izin verici olmakla birlikte, aşağıdaki tek ve bağlayıcı koşulu koşar:
> *"The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software."*

Mevcut depoda:
1. `.agents/` altında veya beceri klasörlerinde hiçbir `LICENSE` ya da `NOTICE` dosyası bulunmamaktadır.
2. `SKILL.md` dosyalarının başlığında telif hakkı sahibi (`Copyright (c) <Year> <Author>`) ve tam lisans izin metni yer almamaktadır.
3. `code-quality` ve `documentation` becerilerinin harici resmi bir kaynak repository URL'si bulunmamaktadır; bu metinler MMS iç standartları olarak yazılmıştır ancak harici üçüncü taraf isimleri anılarak lisans belirsizliği yaratılmıştır.

### 2.3. Bölüm 1 Sonucu ve Eylem Önerisi
Kullanıcı yönergesi uyarınca: *"Kaynağı veya lisansı doğrulanamayan becerileri COMMIT olarak sınıflandırma. Gerekirse DEFER öner."*

- **Nihai Karar:** `.agents/` dizini ve 5 becerinin tamamı ilk commit kapsamından çıkarılmış ve **DEFER** (ertelendi) olarak sınıflandırılmıştır.
- **Düzeltme Planı (Gelecek Aşama):**
  - Orijinal açık kaynak repolardan türetilen 3 beceri (`test-first`, `systematic-debugging`, `flutter-ui-standards`) için ilgili dizinlere resmi `LICENSE` dosyaları ve orijinal yazar attribution metinleri eklenmelidir.
  - MMS projesine özgü olan 2 beceri (`code-quality`, `documentation`) ise projenin kendi telifine (Proprietary / MMS Project) alınmalı veya açıkça lisanslandırılmalıdır.
  - Bu hukuki düzenleme tamamlandıktan sonra `.agents/` bağımsız bir commit ile depoya dahil edilecektir.

---

## 3. Bölüm 2: WinSW v2.12.0 Dağıtım ve Bütünlük Doğrulaması (PASS)

Windows arka plan servisinin çalıştırılmasında kullanılacak sarmalayıcı (wrapper) mimarisi ve sağlama protokolü incelenmiştir.

### 3.1. Resmi Release ve Mimari Doğrulaması

1. **Resmi Release Kaynağı:**  
   GitHub `winsw/winsw` resmi deposu, release etiketi `v2.12.0`:  
   `https://github.com/winsw/winsw/releases/tag/v2.12.0`
2. **Kullanılacak Yürütülebilir Dosya ve Mimari:**  
   - **Dosya:** `WinSW-x64.exe`
   - **Hedef Mimari:** `x64` (AMD64 / 64-bit Windows).
   - **Çalışma Ortamı:** .NET Framework 4.6.1+ tabanlıdır. Windows 10, Windows 11 ve Windows Server işletim sistemlerinde .NET Framework yerleşik olarak bulunduğu için ek runtime kurulumu gerektirmez.
3. **Resmi İndirme URL'si:**  
   `https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe`

### 3.2. Resmi SHA256 Sağlama Özeti

WinSW resmi GitHub sürümünde yayımlanan `WinSW-x64.exe` dosyasının doğrulanmış kriptografik özeti:
```text
05b82d46ad331cc16bdc00de5c6332c1ef818df8ceefcd49c726553209b3a0da
```
*(Not: Önceki taslak incelemede yer alan geçici referans özeti, resmi GitHub release varlığı ile doğrulanarak bu kesin değerle güncellenmiştir).*

### 3.3. Kurulum Betiği (`install_mms_service.ps1`) İleriye Dönük Doğrulama Tasarımı

Mevcut aşamada `test_spikes/spike_01_backend/scripts/install_mms_service.ps1` betiği **kesinlikle değiştirilmemiştir**. Gelecek Faz 1.2 veya Spike bakım aşamasında betiğin WinSW sağlama adımını şu mantıkla yürütmesi kararlaştırılmıştır:

```powershell
# Gelecek Entegrasyon Tasarımı (install_mms_service.ps1)
$expectedHash = "05B82D46AD331CC16BDC00DE5C6332C1EF818DF8CEEFCD49C726553209B3A0DA"
$downloadUrl = "https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe"

if (!(Test-Path $wrapperExeSrc)) {
    Write-Host "[INFO] WinSW sarmalayici bulunamadi, indiriliyor: $downloadUrl ..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $downloadUrl -OutFile $wrapperExeSrc -UseBasicParsing
    
    $actualHash = (Get-FileHash -Path $wrapperExeSrc -Algorithm SHA256).Hash
    if ($actualHash -ne $expectedHash) {
        Remove-Item $wrapperExeSrc -Force -ErrorAction SilentlyContinue
        throw "HATA: WinSW SHA256 butunluk dogrulamasi basarisiz oldu! Beklenen: $expectedHash, Alinan: $actualHash"
    }
    Write-Host "[OK] WinSW basariyla indirildi ve SHA256 ile dogrulandi." -ForegroundColor Green
}
```

---

## 4. Bölüm 3: Dört Mantıksal Commit Planının Son Kontrolü (PASS)

Dört commit grubunun sınırları, bağımlılık yönleri ve dosya izolasyon kuralları titizlikle denetlenmiştir.

### 4.1. Kritik İzolasyon Kriterleri Kontrol Listesi

- [x] **Kök `pubspec.yaml` ve `pubspec.lock` İzolasyonu:** Yalnızca ve sadece Commit 4 (Windows Client Foundation) grubunda yer almaktadır; diğer commit gruplarında bulunmamaktadır.
- [x] **Alt Paket `pubspec.yaml` ve `pubspec.lock` İzolasyonu:**
  - `packages/mms_client_storage/pubspec.*` yalnızca Commit 2'de yer almaktadır.
  - `test_spikes/spike_01_backend/pubspec.*` yalnızca Commit 3'te yer almaktadır.
- [x] **Kümeler Arası Çakışmasızlık (Disjoint Sets):** Hiçbir dosya iki farklı commit grubunda tekrarlanmamıştır; her dosya yalnızca tek bir commite aittir.
- [x] **Sır ve İkili Dosya İzolasyonu:** `pepper.dpapi`, WinSW `.exe` dosyaları, veritabanı dosyaları (`*.db`, `*.db-wal`, `*.db-shm`), `backups/`, `logs/`, `build/` ve `.dart_tool/` gruplardan tamamen dışlanmıştır.
- [x] **`.gitignore` Yerleşimi:** Depo hijyeninin en baştan itibaren korunması için kök `.gitignore` dosyası ilk commit'te (`Commit 1`) yer almaktadır.
- [x] **Agent Skills Düzenlemesi:** Lisans eksikliği bulunan `.agents/**` dosyaları Commit 1'den çıkarılmış ve **DEFER** edilmiştir.

---

### 4.2. Güncellenmiş ve Sertleştirilmiş 4 Commit Planı

#### Commit 1: Repository, Mimari Dokümantasyon ve Yapılandırma
- **Commit Mesajı:** `docs(setup): initialize MMS v1.3 architecture and canonical documentation`
- **Gerekçe:** Projenin kanonik şartnamesi (`BUILD_PLANI`), mimari referanslar, linter yapılandırması ve `.gitignore` kurallarını deponun omurgası olarak kaydeder. (`.agents/` lisans doğrulaması tamamlanana kadar hariç tutulmuştur).
- **Açık Dosya Listesi:**
  - `.gitignore` (M)
  - `.metadata` (??)
  - `analysis_options.yaml` (??)
  - `README.md` (??)
  - `MARKET_POS_AI_STUDIO_BUILD_PLANI.md` (M)
  - `MARKET_MMS_ANTIGRAVITY_INITIAL_AUDIT.md` (??)
  - `MARKET_MMS_ANTIGRAVITY_INTEGRATION_PLAN.md` (??)
  - `MARKET_MMS_ANTIGRAVITY_SKILL_ECOSYSTEM_AUDIT.md` (??)
  - `MARKET_MMS_ARCHITECTURE_ALIGNMENT_REVIEW.md` (??)
  - `MARKET_MMS_DATA_MODEL_SYNC_REVIEW.md` (??)
  - `MARKET_MMS_FINAL_ANTIGRAVITY_INTEGRATION_PLAN.md` (??)
  - `MARKET_MMS_FOLDER_STRUCTURE_AUDIT.md` (??)
  - `MARKET_MMS_PHASE_0_TECHNICAL_SPIKE_PLAN.md` (??)
  - `MARKET_MMS_SPIKE_01_PLAN.md` (??)
  - `MARKET_MMS_UNIVERSAL_TEMPLATE_INTEGRATION_REPORT.md` (??)
  - `docs/ARCHITECTURE.md` (M)
  - `docs/DEVELOPMENT_GUIDE.md` (??)
  - `docs/PROJECT_OVERVIEW.md` (??)
  - `docs/PROJECT_STATUS.md` (M)
  - `docs/REQUIREMENTS.md` (??)
  - `docs/ai/rules/security.md` (M)
  - `docs/architecture/` (?? - 11 dosya)
  - `docs/decisions/README.md` (??)
  - `docs/phase-1/` (?? - 14 dosya)
  - `docs/phases/` (?? - 2 dosya)
  - `docs/reports/` (?? - 1 dosya)
  - `docs/requirements/` (?? - 2 dosya)

#### Commit 2: Client Storage Paketi (`packages/mms_client_storage`)
- **Commit Mesajı:** `feat(storage): implement Drift client SQLite storage, backup engine, and outbox sync`
- **Gerekçe:** İstemci tarafı yerel SQLite depolama katmanını, Drift tablolarını, yerel yedekleme motorunu ve Outbox senkronizasyon kuyruğunu bağımsız Dart paketi olarak ekler.
- **Açık Dosya Listesi:**
  - `packages/mms_client_storage/pubspec.yaml`
  - `packages/mms_client_storage/pubspec.lock`
  - `packages/mms_client_storage/lib/`
  - `packages/mms_client_storage/test/`

#### Commit 3: Backend ve Servis Altyapısı (`test_spikes/spike_01_backend`)
- **Commit Mesajı:** `feat(backend): add Shelf HTTPS backend, service configs, and durability spike suite`
- **Gerekçe:** Faz 0 kapsamında doğrulanan bağımsız Dart Shelf HTTPS sunucusunu, Windows Service konfigürasyonlarını, PowerShell yönetim betiklerini ve 139 birim/entegrasyon testini içerir (`pepper.dpapi` ve `.exe` dosyaları hariç).
- **Açık Dosya Listesi:**
  - `test_spikes/spike_01_backend/pubspec.yaml`
  - `test_spikes/spike_01_backend/pubspec.lock`
  - `test_spikes/spike_01_backend/bin/`
  - `test_spikes/spike_01_backend/lib/`
  - `test_spikes/spike_01_backend/scripts/`
  - `test_spikes/spike_01_backend/service_wrapper/*.xml`
  - `test_spikes/spike_01_backend/service_wrapper/README.md`
  - `test_spikes/spike_01_backend/test/`
  - `test_spikes/spike_01_backend/*.md`

#### Commit 4: Windows Client Foundation (`lib`, `test`, platform dosyaları)
- **Commit Mesajı:** `feat(client): implement Flutter Windows client foundation, shell UI, and local database service`
- **Gerekçe:** Faz 1.1 kabul kriterlerini eksiksiz karşılayan kök Flutter uygulamasını, Windows runner C++ çekirdeğini, mobil iskelelerini, `LocalDatabaseService` yaşam döngüsü korumasını ve teşhis arayüzünü sunar.
- **Açık Dosya Listesi:**
  - `pubspec.yaml`
  - `pubspec.lock`
  - `lib/`
  - `test/`
  - `windows/CMakeLists.txt`
  - `windows/.gitignore`
  - `windows/flutter/CMakeLists.txt`
  - `windows/flutter/generated_plugins.cmake`
  - `windows/runner/`
  - `android/`
  - `ios/`

---

## 5. Ertelenen ve Reddedilen Dosyalar Envanteri

| Dosya / Dizin | Durum | Gerekçe |
| :--- | :---: | :--- |
| `.agents/skills/**` (5 Beceri) | **DEFER** | Orijinal MIT copyright bildirimleri ve yerel `LICENSE` dosyaları eklenene kadar ertelenmiştir. |
| `.agents/registry/SKILL_REGISTRY.md` | **DEFER** | Becerilerle birlikte senkron olarak depoya eklenecektir. |
| `test_spikes/**/pepper.dpapi` | **REJECT** | Makineye özgü şifrelenmiş DPAPI anahtarı (Gizli veri; asla depolanmaz). |
| `test_spikes/**/service_wrapper/*.exe` | **REJECT** | Önceden derlenmiş WinSW ikili dosyaları (Depo şişmesini önleme; script ile indirilir). |
| `windows/flutter/generated_plugin_registrant.*` | **REJECT** | Derleme anında Flutter motoru tarafından üretilen geçici dosya. |
| `ios/Runner/GeneratedPluginRegistrant.*` | **REJECT** | Derleme anında Flutter motoru tarafından üretilen geçici dosya. |
| `android/local.properties` | **REJECT** | Yerel Android SDK yolunu içeren makineye özgü dosya. |
| `android/gradle/wrapper/gradle-wrapper.jar` | **REJECT** | İkili jar dosyası. |
| `*.db`, `*.db-wal`, `*.db-shm` | **REJECT** | Çalışma anı SQLite veritabanı ve transaction günlükleri. |
| `build/`, `.dart_tool/` | **REJECT** | Derleme çıktıları ve paket çözümleme önbellekleri. |

---

## 6. Nihai Git Durum Doğrulaması

- **Staged Files (`git diff --cached`):** `0` (Hiçbir dosya stage edilmemiştir).
- **Kaynak Kod Değişikliği:** `0` (Hiçbir üretim veya test kodu değiştirilmemiştir).
- **Commit İşlemi:** Yapılmamıştır.
- **Sonraki Adım:** Kullanıcının bu denetim raporundaki PARTIAL değerlendirmesini ve DEFER önerisini onaylaması halinde, 4 aşamalı commit işlemi sırayla yürütülmeye hazırdır.

