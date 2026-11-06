# MARKET MMS — FAZ 1.1 B-6 KOD VE GIT REPOSITORY İNCELEME RAPORU

**Rapor Tarihi:** 6 Kasım 2026  
**Aşama:** Faz 1.1 — Windows Client Foundation (B-6 Concurrency & Lifecycle Audit)  
**İnceleme Kapsamı:** Git repository ve versiyon takip durumu, `.gitignore` kuralları, `LocalDatabaseService` ve ilgili depolama bileşenlerinin kaynak kod mimarisi, test derleme hatası analizi.  
**İşlem Sınırı:** Yalnızca inceleme ve raporlama yapılmıştır; hiçbir dosya değiştirilmemiş, silinmemiş, taşınmamış, stage edilmemiş veya commit oluşturulmamıştır.

---

## 1. Git Repository Durumu

Aşağıdaki komutlar terminal üzerinde yürütülmüş ve repository durumu doğrulanmıştır:

### 1.1. Komut Çıktıları

1. **`git rev-parse --show-toplevel`**
   ```text
   C:/Users/halil/Github/market-pos
   ```

2. **`git branch --show-current`**
   ```text
   main
   ```

3. **`git log --oneline -5`**
   ```text
   73021fe docs(rules): align payment, role and tax requirements
   0d1c0af chore(setup): initialize market-pos mms v1.2 documentation and agent architecture
   ```

4. **`git remote -v`**
   ```text
   origin  https://github.com/halilkrkn/market-pos.git (fetch)
   origin  https://github.com/halilkrkn/market-pos.git (push)
   ```

5. **`git ls-files` (Takip Edilen Dosyalar - 18 Dosya)**
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

6. **`git status --short`**
   ```text
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

7. **`git status --ignored --short` (Yok Sayılan Dosyalar)**
   ```text
   !! .dart_tool/
   !! .idea/
   !! android/app/src/main/java/
   !! android/gradle/wrapper/gradle-wrapper.jar
   !! android/gradlew
   !! android/gradlew.bat
   !! android/local.properties
   !! android/market_pos_android.iml
   !! build/
   !! ios/Flutter/Generated.xcconfig
   !! ios/Flutter/ephemeral/
   !! ios/Flutter/flutter_export_environment.sh
   !! ios/Runner/GeneratedPluginRegistrant.h
   !! ios/Runner/GeneratedPluginRegistrant.m
   !! market_pos.iml
   !! packages/mms_client_storage/.dart_tool/
   !! test_spikes/spike_01_backend/.dart_tool/
   !! test_spikes/spike_01_backend/backups/
   !! test_spikes/spike_01_backend/build/
   !! test_spikes/spike_01_backend/logs/
   !! test_spikes/spike_01_backend/service_wrapper/logs/
   !! windows/flutter/ephemeral/
   ```

8. **`git check-ignore -v` Çıktıları**
   ```text
   .gitignore:8:.dart_tool/                  .dart_tool
   .gitignore:10:build/                      build
   .gitignore:88:*.env                       .env
   .gitignore:10:build/                      test_spikes/spike_01_backend/build
   android/.gitignore:6:/local.properties    android/local.properties
   ```

---

## 2. Tracked / Untracked Dosya Durumu Değerlendirmesi

### 2.1. Neden Yalnızca 4 Dosya Değişik ve Diğerleri Untracked?
- **Repository Geçmişi:** Git log incelendiğinde depoda yalnızca 2 commit bulunmaktadır:
  1. `0d1c0af`: İlk kurulumda yalnızca mimari kural dosyaları, plan belgeleri ve `.gitignore` eklenmiştir.
  2. `73021fe`: Kural dokümanlarındaki kural güncellemeleri commitlenmiştir.
- **Kod Tarafında Initial Commit Yokluğu:** Spike (S1–S5A) ve Faz 1.1 aşamalarında üretilen kaynak kodlar (Flutter masaüstü kabuğu, Drift yerel depolama paketi, Dart backend servisi, testler) çalışma ağacında (working directory) üretilmiş; ancak proje kuralları ("Faz kabul kriterleri eksiksiz karşılanmadan ve kullanıcıdan açık onay alınmadan commit oluşturulamaz") gereği henüz `git add` ile stage edilmemiş ve commitlenmemiştir.
- **Değişik Olarak Görünen 4 Dosya:** `MARKET_POS_AI_STUDIO_BUILD_PLANI.md`, `docs/ARCHITECTURE.md`, `docs/PROJECT_STATUS.md` ve `docs/ai/rules/security.md` dosyaları ilk committe repoya dahil edilmiş dosyalar olduğu için yapılan revizyonlar Git tarafından `M` (Modified) olarak izlenmektedir.

### 2.2. Henüz Git Tarafından Takip Edilmeyen Önemli Proje Dosyaları
1. **Konfigürasyon & Paket Tanımları:** `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`
2. **Uygulama Kaynak Kodları (`lib/`):** Masaüstü kabuğu, tanılama ekranı, HTTP istemcisi ve `LocalDatabaseService` ([`lib/core/storage/local_database_service.dart`](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart))
3. **Uygulama Testleri (`test/`):** API istemci testleri ve `LocalDatabaseService` birim/yaşam döngüsü testleri ([`test/core/storage/local_database_service_test.dart`](file:///c:/Users/halil/Github/market-pos/test/core/storage/local_database_service_test.dart))
4. **Yerel Depolama Paketi (`packages/mms_client_storage/`):** Drift şemaları, tablolar, migration stratejileri, repository ve SQLite WAL yedekleme motoru.
5. **Sunucu Backend Kodu (`test_spikes/spike_01_backend/`):** Shelf HTTP sunucusu, WinSW servis wrapper'ı, master veritabanı motoru ve testleri.
6. **Platform Runner Dosyaları:** `windows/`, `android/`, `ios/`
7. **Faz 1 Dokümantasyonu:** `docs/phase-1/` altındaki tüm mimari inceleme ve doğrulama raporları.

---

## 3. `.gitignore` Değerlendirmesi

Kök dizindeki [`.gitignore`](file:///c:/Users/halil/Github/market-pos/.gitignore) dosyası 109 satırdan oluşmakta ve 6 temel kategori barındırmaktadır:
1. **Flutter & Dart Çıktıları:** `.dart_tool/`, `.packages`, `build/`, `.pub-cache/`, `.flutter-plugins` vb.
2. **İşletim Sistemi Geçici Dosyaları:** Windows (`Thumbs.db`, `Desktop.ini`), macOS (`.DS_Store`), Linux.
3. **Editör ve IDE:** `.idea/`, `*.iml`, `.vscode/*` (yalnızca gerekli launch/tasks/settings korunarak).
4. **Platform Özel Derleme Çıktıları:** Android (`.gradle/`, `local.properties`), iOS (`Pods/`, `ephemeral/`), Windows (`windows/flutter/ephemeral/`).
5. **Hassas Bilgiler ve Sırlar (Security):** `*.env`, `*.key`, `*.keystore`, `*.pem`, `google-services.json`, `GoogleService-Info.plist`.
6. **Veritabanı Dosyaları ve Günlükler:** `*.db`, `*.sqlite`, `*.sqlite3`, `*.db-wal`, `*.db-shm`, `*.log`.

**Değerlendirme:**
- `.gitignore` dosyası standart Flutter ve kurumsal güvenlik pratiklerine tamamen uygundur.
- `git status --ignored --short` ve `git check-ignore -v` çıktıları, geçici `build/`, `.dart_tool/`, `*.env` ve SQLite dosya kilitlerinin repoya sızmasını başarıyla engellediğini kanıtlamaktadır.

---

## 4. B-6 Kaynak Kod Mimari İncelemesi

İncelenen Dosyalar:
- [`lib/core/storage/local_database_service.dart`](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart)
- [`test/core/storage/local_database_service_test.dart`](file:///c:/Users/halil/Github/market-pos/test/core/storage/local_database_service_test.dart)
- [`packages/mms_client_storage/lib/src/database/client_database.dart`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/database/client_database.dart) *(Not: Projede dosya konumu `packages/mms_client_storage` altındadır)*
- [`packages/mms_client_storage/lib/src/database/client_storage_repository.dart`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/database/client_storage_repository.dart) *(Not: Projede dosya konumu `packages/mms_client_storage` altındadır)*

Aşağıdaki 8 kritik inceleme maddesi satır numaralarıyla değerlendirilmiştir:

### 4.1. `_initializingPath` ve `_initializationFuture` Farklı DB Path'lerinde Doğru Çalışıyor mu?
- **İlgili Satırlar:** `lib/core/storage/local_database_service.dart` [L58-L59](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L58-L59), [L100-L124](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L100-L124), [L127-L130](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L127-L130).
- **Değerlendirme:**
  - Aynı path ile gelen eşzamanlı çağrılarda (`_initializingPath == requestedPath`, L103) mevcut `_initializationFuture` başarıyla paylaşılır.
  - Farklı path talebinde (`else` bloğu, L111-L123) in-flight olan mevcut Future beklenir (`await _initializationFuture!`), açılan eski instance güvenle kapatılır (`await existingService.close()`) ve yeni path için yinelemeli olarak `initialize(customPath: customPath)` çağrılır.
  - **Tespit Edilen Mimari Sınır:** Eğer Çağrıcı A `pathA` ile açılış yaparken tam o anda Çağrıcı B `pathB` isterse; Çağrıcı B, Çağrıcı A'nın instance'ını kapatır. Çağrıcı A ise L135'teki `if (service._isClosed)` denetimine takılarak kendisi için `pathA`'yı yeniden açmaya çalışır. Market POS masaüstü mimarisinde tek bir yerel veritabanı (`client_local.db`) kullanıldığı için bu durum canlıda sorun teşkil etmez; ancak singleton modelde iki zıt path'in eşzamanlı istenmesi teorik bir ping-pong döngüsü riski taşır.

### 4.2. Initialize ve Close Eşzamanlı Çağrıldığında Çağrıcı Kapatılmış Instance Alabilir mi?
- **İlgili Satırlar:** `lib/core/storage/local_database_service.dart` [L105-L109](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L105-L109), [L133-L137](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L133-L137), [L348-L356](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L348-L356).
- **Değerlendirme:**
  - `closeActive()` metodu in-flight `_initializationFuture` varsa önce onun tamamlanmasını bekler ve ardından nesneyi kapatır (L350-L355).
  - `initialize()` tarafında ise Future tamamlandıktan hemen sonra `if (service._isClosed)` kontrolü bulunur (L107 ve L135). Eğer nesne kapatılmışsa otomatik olarak `initialize(customPath: customPath)` yeniden çağrılır.
  - **Tespit Edilen Semantik Çelişki:** Eğer bir bileşen uygulamayı kapatmak için `closeActive()` çağırırsa, devam eden `initialize()` çağrıcısı kapalı nesne almamak adına veritabanını **yeniden başlatır**. Bu durum çağrıcının kapalı nesne almasını önler; ancak `closeActive()` sonrasında sistemin `uninitialized/closed` kalması beklenirken arka planda veritabanının tekrar açılmasına yol açabilir.

### 4.3. `runOperation` Gerçek Satış, Stok Hareketi ve Outbox DB Operasyonlarının Tamamında Kullanılıyor mu?
- **İlgili Satırlar:** `lib/core/storage/local_database_service.dart` [L241-L250](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L241-L250).
- **Değerlendirme:**
  - **HAYIR, kullanılmamaktadır.** `runOperation` metodu yalnızca `LocalDatabaseService` içerisinde tanımlanmış ve `test/core/storage/local_database_service_test.dart` dosyasındaki testlerde çağrılmıştır.
  - Gerçek satış, stok hareketi ve Outbox operasyonları [`packages/mms_client_storage/lib/src/database/client_storage_repository.dart`](file:///c:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/database/client_storage_repository.dart) sınıfı içerisindedir (`createOfflineSale`, `upsertProducts`, `markOutboxSynced` vb.). Bu paket tamamen bağımsız bir saf Dart paketi olup `LocalDatabaseService`'ten haberdar değildir.

### 4.4. Doğrudan Database/Repository Erişimi Drain Mekanizmasını Atlayabiliyor mu?
- **İlgili Satırlar:** `lib/core/storage/local_database_service.dart` [L265-L277](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L265-L277).
- **Değerlendirme:**
  - **EVET, tamamen atlamaktadır.**
  - `database` ve `repository` getter'ları çağrıldığında yalnızca anlık `_ensureOpen()` kontrolü yapılır (L266, L275).
  - Çağrıcı `repository` referansını aldıktan sonra yürüttüğü uzun işlemler (örneğin 20 kalemli bir satış transaction'ı) `_activeQueryCount` sayacını **artırmaz**.
  - Dolayısıyla bu sırada `service.close()` çağrılırsa `_activeQueryCount == 0` görülür ve drain beklenmeksizin doğrudan `_db.close()` tetiklenir.

### 4.5. Drain Timeout Sonrasında Bağlantı Hâlâ Açıkken Yeni Initialize Çağrısı Yapılabiliyor mu?
- **İlgili Satırlar:** `lib/core/storage/local_database_service.dart` [L70-L73](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L70-L73), [L294](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L294), [L391-L428](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L391-L428).
- **Değerlendirme:**
  - `_performClose()` çalışırken `_activeCloseFuture` değişkeni set edilmiş durumdadır (L380).
  - Drain timeout (2s) aşılsa dahi akış henüz `_performClose()` içindedir ve hemen ardından `_db.close()` satırına geçer.
  - Bu esnada yeni bir `initialize()` çağrılırsa, L71'deki `if (_activeCloseFuture != null) await _activeCloseFuture;` kontrolüne takılır ve kapanış işleminin (`_performClose`) tamamen bitmesini ve `_activeCloseFuture`'ın `null` olmasını bekler.
  - Dolayısıyla drain timeout olsa dahi bağlantı kapatılmadan yeni bir `initialize` çağrısı araya giremez. (**GÜVENLİ**)

### 4.6. `_db.close()` Timeout Olduğunda Bağlantı Yaşam Döngüsü Güvenli Kalıyor mu?
- **İlgili Satırlar:** `lib/core/storage/local_database_service.dart` [L413-L427](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L413-L427).
- **Değerlendirme:**
  - `_db.close()` çağrısı 5 saniyelik timeout ile sarılmıştır (L413-L422). Timeout olduğunda uyarı yazılır ve akış `finally` bloğuna (L423) geçerek `_instance = null` yapar.
  - **Kritik Risk:** Eğer işletim sistemi düzeyinde SQLite dosyası kilitli kalmışsa veya Drift background isolate'i yanıt vermiyorsa, Dart tarafında nesne `null` yapılsa bile alttaki isolate SQLite dosyasını tutmaya devam edebilir. Hemen ardından yapılacak bir `initialize()` çağrısı dosya kilit çakışması (`SqliteException: database is locked / SQLITE_BUSY`) ile karşılaşabilir.

### 4.7. Statik Timeout Değişkenleri Testler Arasında Birbirini Etkileyebilir mi?
- **İlgili Satırlar:** `lib/core/storage/local_database_service.dart` [L63-L66](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L63-L66), [L308-L313](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L308-L313); `test/core/storage/local_database_service_test.dart` [L33-L34](file:///c:/Users/halil/Github/market-pos/test/core/storage/local_database_service_test.dart#L33-L34), [L469](file:///c:/Users/halil/Github/market-pos/test/core/storage/local_database_service_test.dart#L469).
- **Değerlendirme:**
  - `drainTimeout` ve `dbCloseTimeout` sınıfta `static` alanlar olarak tanımlanmıştır.
  - Test 19 içerisinde `LocalDatabaseService.drainTimeout = const Duration(milliseconds: 100);` atanmaktadır.
  - `test/core/storage/local_database_service_test.dart` içindeki `tearDown()` metodu bu değerleri 2s ve 5s olarak sıfırlamaktadır (L33-L34).
  - Ancak `resetForTesting()` metodu (L308-L313) bu timeout değişkenlerini sıfırlamamaktadır! Başka bir test dosyasında yalnızca `resetForTesting()` çağrılırsa ve önceki bir test hata verip `tearDown`'a ulaşamazsa, 100ms'lik timeout diğer test suitlerine sızabilir.

### 4.8. Eşzamanlı Close Çağrıları Tek Bir Kapanış İşlemi mi Yürütüyor?
- **İlgili Satırlar:** `lib/core/storage/local_database_service.dart` [L372-L389](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart#L372-L389).
- **Değerlendirme:**
  - **EVET, tek bir işlem yürütmektedir.**
  - `close()` metodu çağrıldığında ilk çağrıcı anında `_closeFuture = future;` ataması yapar (L379).
  - Devam eden bir kapanış varken gelen ikinci eşzamanlı çağrı L374'teki `if (_closeFuture != null) return _closeFuture!;` kontrolüyle aynı Future'ı paylaşır.
  - Kapanış bittikten sonra gelen çağrılar ise L373'teki `if (_isClosed) return;` ile güvenle no-op döner. (**GÜVENLİ**)

---

## 5. Test Derleme Hatası Analizi

### 5.1. Hatanın Kaynağı
Terminalde `flutter test test/core/storage/local_database_service_test.dart` çalıştırıldığında alınan hata:
```text
test/core/storage/local_database_service_test.dart:376:31: Error: 'isNotNull' is imported from both 'package:drift/src/runtime/query_builder/query_builder.dart' and 'package:matcher/src/core_matchers.dart'.
      expect(currentInstance, isNotNull);
                              ^^^^^^^^^
test/core/storage/local_database_service_test.dart:518:25: Error: 'isNotNull' is imported from both 'package:drift/src/runtime/query_builder/query_builder.dart' and 'package:matcher/src/core_matchers.dart'.
      expect(syncState, isNotNull);
                        ^^^^^^^^^
```

- **Neden:** `test/core/storage/local_database_service_test.dart` dosyasının 4. satırında `import 'package:drift/drift.dart' hide isNull;` bulunmaktadır.
- `drift` paketi SQL ifadeleri oluşturmak için `isNotNull` fonksiyonunu dışa aktarır.
- `flutter_test` (ve dolayısıyla `matcher`) paketi ise test assertion'ları için `isNotNull` matcher'ını dışa aktarır.
- Yalnızca `isNull` gizlendiği, `isNotNull` gizlenmediği için Dart derleyicisi 376 ve 518. satırlardaki `isNotNull` kullanımında isim çakışması (ambiguous import) hatası vermiştir.

### 5.2. Önerilen Düzeltme
`test/core/storage/local_database_service_test.dart` dosyasının 4. satırındaki drift importunun şu şekilde güncellenmesi gerekmektedir:
```dart
import 'package:drift/drift.dart' hide isNull, isNotNull;
```

### 5.3. Diğer Matcher Kullanımlarına Etkisi
- `isNotNull` Drift fonksiyonu test dosyasında hiçbir sorguda doğrudan kullanılmamaktadır (Drift sorgularında extension metodu olan `column.isNotNull()` kullanılır).
- Hiding işlemi yapıldığında test içerisindeki `expect(..., isNotNull)` ifadeleri doğrudan ve temiz biçimde `matcher` paketinin `isNotNull` nesnesine bağlanacaktır.
- Başka hiçbir matcher veya test senaryosu bu değişiklikten olumsuz etkilenmeyecektir.

---

## 6. Kritik ve Orta Öncelikli Riskler

| Risk | Öncelik | Açıklama |
|---|:---:|---|
| **Repository Getter Drain Bypassing** | **ORTA** | `localDbService.repository` üzerinden doğrudan çağrılan satış veya Outbox operasyonları `runOperation` ile sarılmazsa `_activeQueryCount` sayacına girmez ve close anında drain mekanizmasını atlar. |
| **CloseActive Sonrası İstem Dışı Re-Initialize** | **ORTA** | In-flight başlatma sürerken `closeActive()` çağrıldığında, `initialize()`'ın kapalı nesne dönmemek için re-initialize yapması sistemi kapatmak yerine yeniden açık duruma getirebilir. |
| **`resetForTesting()` Statik Timeout Sızıntısı** | **DÜŞÜK** | `resetForTesting()` metodunun `drainTimeout` ve `dbCloseTimeout` değerlerini sıfırlamaması, testler arası izolasyon bozulursa sonraki testleri etkileyebilir. |
| **`_db.close()` Timeout Sonrası Isolate Askıda Kalması** | **DÜŞÜK** | 5 saniyelik emniyet timeout'u sonrasında arka plandaki Drift isolate SQLite kilitlerini bırakmazsa hemen ardından gelen `initialize()` `database is locked` hatası alabilir. |

---

## 7. Bir Sonraki Güvenli İşlem Sırası

Kota ve onay sağlandığında uygulanması gereken deterministik adımlar:

1. **Test Import Düzeltmesi:**
   [`test/core/storage/local_database_service_test.dart`](file:///c:/Users/halil/Github/market-pos/test/core/storage/local_database_service_test.dart) 4. satırındaki import satırını `import 'package:drift/drift.dart' hide isNull, isNotNull;` olarak güncelle.
2. **`resetForTesting()` İyileştirmesi:**
   [`lib/core/storage/local_database_service.dart`](file:///c:/Users/halil/Github/market-pos/lib/core/storage/local_database_service.dart) içindeki `resetForTesting()` metoduna timeout sıfırlamasını ekle (`drainTimeout = const Duration(seconds: 2); dbCloseTimeout = const Duration(seconds: 5);`).
3. **Birim Testlerini Koştur ve Doğrula:**
   - `flutter test test/core/storage/local_database_service_test.dart` (22 testin tamamının PASSED olduğunu doğrula).
   - Kök dizin testlerini çalıştır: `flutter test`.
   - Paket testlerini çalıştır: `cd packages/mms_client_storage && dart test`.
   - Backend testlerini çalıştır: `cd test_spikes/spike_01_backend && dart test`.
4. **Statik Kod Analizini Yürüt:**
   - Kök dizinde `flutter analyze`.
   - Alt paketlerde `dart analyze`.
5. **Windows Release Build Doğrulaması:**
   - `flutter build windows --release`.
6. **Nihai Rapor:**
   - Doğrulama sonuçlarını [`docs/phase-1/PHASE_1_1_B6_FINAL_REMEDIATION_REPORT.md`](file:///c:/Users/halil/Github/market-pos/docs/phase-1/PHASE_1_1_B6_FINAL_REMEDIATION_REPORT.md) dosyasına kaydet.
7. **Git Initial Commit Hazırlığı:**
   - Faz 0 / Faz 1.1 kabul onayı sonrası `.gitignore` kontrolüyle temiz bir staging ve initial commit planla.

