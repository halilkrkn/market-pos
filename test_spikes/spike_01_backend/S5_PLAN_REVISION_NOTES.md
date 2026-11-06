# MARKET MMS — SPIKE-01 / S-5 Plan Revizyon Notları (v1.9 -> v2.0)

**Tarih:** 5 Kasım 2026  
**İlgili Doküman:** [`S5_WINDOWS_SERVICE_PLAN.md`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/S5_WINDOWS_SERVICE_PLAN.md) (v2.0)  
**Çalışma Kapsamı:** Salt Okunur Dokümantasyon Revizyonu (Kaynak kod, test kodu, native DLL, EXE, PowerShell veya servis yapılandırması üretilmemiştir)

---

## 1. Revizyon Genel Bakışı ve Amaç

Kullanıcının **"S-5 Plan v1.9 → v2.0 Düzeltme Talimatı"** ve teknik incelemede tespit edilen 6 kritik bulgu (F1 – F6) doğrultusunda, `S5_WINDOWS_SERVICE_PLAN.md` belgesi **v2.0** sürümüne yükseltilmiştir.

Bu revizyon; yükseltilmemiş standart kullanıcı (Medium Integrity Level) Flutter UI'nin UAC gerektirmeden broker yanıtını alabileceği Response Pipe DACL ve 5 katmanlı süreç güvenliği modelini, 12 saniyelik birleşik shutdown drain protokolü ile veritabanı yaşam döngüsü arasındaki kesin kuralları (timeout anında checkpoint yasağı, WAL korunması, exit 101 ve sonraki açılışta otomatik crash recovery), SQLite 3.46.1 sürüm gerekçesini ve 24 sembollük C export doğrulamasını, NTFS ACL'lerinde bildirimsel SID denetimi ile gerçek `MmsTestStandardUser` hesabı üzerinden yapılan dinamik efektif erişim testlerinin ayrımını, Named Pipe sunucu ve istemci izinlerinin çekirdek düzeyindeki kesin ayrımını ve 50 senaryoya genişletilmiş iki kategorili (Real VM vs Mock) test matrisini bağlayıcı standart haline getirmiştir.

---

## 2. v1.9 Bulgularının v2.0'da Ele Alınışı

### 2.1. F1 — Response Pipe DACL ve Normal UI Erişimi [BLOCKER]
- **v1.9 Bulgusu:** Önceki taslaklardaki `D:P(A;;GA;;;SY)(A;;0x00120083;;;BA)` DACL'ı yalnızca `SYSTEM` ve `BUILTIN\Administrators` izinlerini içermekteydi. Normal kasiyer oturumunda yükseltilmemiş standart kullanıcı (Medium Integrity) olarak çalışan Flutter UI'nin token'ında `BA` bulunmadığı için, normal UI kendi oluşturduğu pipe'ı yönetemez veya OTS (Over-The-Shoulder) UAC senaryosunda broker yanıtını okuyamazdı.
- **v2.0 Çözümü (Bölüm 3.2):**
  1. **DACL Yeniden Yapılandırıldı:**  
     `D:P(A;;0x12019b;;;<CURRENT_USER_SID>)(A;;0x12019b;;;BA)(A;;GA;;;SY)`  
     Standart kullanıcı (`CURRENT_USER_SID`) ve elevated broker (`BA`) için açık okuma/yazma/senkronizasyon yetkisi sağlandı; kalıtım `P` bayrağı ile kesildi.
  2. **Sunucu ve İstemci Hakları Ayrıştırıldı:**  
     Normal UI `CreateNamedPipeW` ile sunucu olarak pipe açar ve nesne sahibi olur. Elevated broker `CreateFileW` ile istemci olarak bağlanır (`0x00100003` talep eder).
  3. **Temel Güvenlik İlkesi Vurgulandı:**  
     Windows DACL'ın **yalnızca Token SID denetimi yaptığı, süreç kimliğini (PID) veya bütünlük seviyesini (Integrity Level) denetleyemeyeceği** açık bir mimari kısıt olarak belgelendi.
  4. **Aynı Oturumdaki Diğer Süreçlere Karşı 5 Katmanlı Güvenlik:**
     - 128-bit CSPRNG rastgele pipe adı (`MarketMMS_BrokerResponse_<UUIDv4>`).
     - `FILE_FLAG_FIRST_PIPE_INSTANCE` ile ilk ve tek sunucu olma garantisi.
     - `GetNamedPipeClientProcessId` ile çekirdek düzeyinde PID doğrulaması; uyumsuzlukta anında `DisconnectNamedPipe` ve re-listen.
     - `hProcess` tutamacının yanıt onaylanana kadar açık tutulması ve fail-closed takibi.
     - 256-bit CSPRNG oturum nonce'ı (Medium IL süreçler Windows MIC gereği High IL broker belleğini okuyamaz).
  5. **UAC Hata Yönetimi:** UAC iptali (`ERROR_CANCELLED` / 1223), broker erken çöküşü, bağlantı ve okuma zaman aşımları fail-closed temizlikle kapsandı.
  6. **Alternatif IPC Değerlendirmesi:** Anonymous Pipe'ın UAC `runas` sınırını handle aktarımı yasağı nedeniyle geçemeyeceği kanıtlandı.

### 2.2. F2 — Shutdown Timeout ve Veritabanı Yaşam Döngüsü [BLOCKER]
- **v1.9 Bulgusu:** Shutdown drain süresi ile veritabanı kapatma ve WAL checkpoint adımları arasındaki sınır belirsizdi; drain zaman aşımına uğradığında aktif yazma işlemi sürerken checkpoint çalıştırılması veri tabanında tutarsızlığa yol açabilirdi.
- **v2.0 Çözümü (Bölüm 6.1):**
  1. **Tüm Yazmaların WriteQueue Kapsamında Olduğunun Kanıtı:** HTTP API satışları, Named Pipe IPC eşleştirme/iptal işlemleri, audit logları ve senkronizasyon yazmalarının istisnasız tekil `WriteQueue` üzerinden yürütüldüğü, hiçbir bileşenin doğrudan SQLite'a yazamayacağı kurala bağlandı.
  2. **`HttpServer.close(force: false)` vs `force: true` Ayrımı:** Kapanışın başında dinleyici soket `force: false` ile kapatılarak mevcut aktif isteklerin yanıtlarını göndermesi beklenir; drain timeout olduğunda ise askıda kalan soketler `force: true` ile zorla düşürülür.
  3. **Drain Başarılı Olduğunda (<= 12.0s):** Tüm yazmalar diske commit edilir, HTTP kapanışı biter, `PRAGMA wal_checkpoint(TRUNCATE)` çalıştırılır, `database.close()` temiz yürütülür ve süreç `exit(0)` ile sonlanır (`TC-S5-05`).
  4. **Drain Timeout Olduğunda (> 12.0s):**
     - **KESİN CHECKPOINT YASAĞI:** Aktif işlem sürerken `PRAGMA wal_checkpoint` kesinlikle çalıştırılmaz!
     - **KESİN DB CLOSE YASAĞI:** Normal `database.close()` çağrılmaz (rollback veya kilitlenme önlenir).
     - **WAL KORUNMASI:** Diskteki `market_master.db-wal` dosyası korunur.
     - Süreç kontrollü sonlandırma koduyla kapatılır: `exit(101)` (`TC-S5-38`).
     - **Otomatik Crash Recovery:** Sonraki açılışta `sqlite3_open_v2` WAL'daki tüm geçerli commit'leri otomatik kurtarır; veri kaybı sıfırdır (`TC-S5-47`).

### 2.3. F3 — SQLite 3.46.1 Sürüm Gerekçesi ve Export Doğrulaması [HIGH]
- **v1.9 Bulgusu:** "Resmi ABI uyumluluğu" iddiası teknik kanıt olmadan kullanılmıştı; derlenmiş DLL hash'inin derleme öncesinde varsayılması ve donanım durability sınırlarının belirtilmemesi eksikti.
- **v2.0 Çözümü (Bölüm 10.1 & 10.2):**
  1. **Teknik Gerekçe:** SQLite'ın 2004'ten bu yana süregelen C ABI geriye dönük uyumluluk taahhüdü ve `package:sqlite3` FFI dinamik sembol çağrı mekanizması açıklandı.
  2. **24 Temel C Export Sembolü:** `package:sqlite3` tarafından tüketilen 24 temel fonksiyon (`sqlite3_open_v2`, `sqlite3_prepare_v3`, `sqlite3_step`, `sqlite3_wal_checkpoint_v2`, vb.) listelendi ve `dumpbin /EXPORTS` ile doğrulanma kriteri getirildi (`TC-S5-49`).
  3. **Hash Ayrımı:** Kaynak arşiv SHA-256'sı (`92ffb1b5904efebfa9bf864e4324f46927952bbff6909477b85e0bf5ff1237a7`) sabitlendi; derlenmiş DLL hash'inin S5-3 implementasyon adımında derleme makinesinde hesaplanacağı açıkça belirtildi.
  4. **FULL Durability ve Fiziksel Donanım Sınırları:** `PRAGMA synchronous=FULL` (2) ile her commit anında `FlushFileBuffers` çağrıldığı; ancak tüketici disklerinin donanım önbellekleri (write-cache) ve sanallaştırma katmanları nedeniyle sahada UPS ve Power Loss Protection (PLP) destekli kurumsal SSD kullanımının zorunlu olduğu belgelendi (`TC-S5-50`).

### 2.4. F4 — ACL Gerçek Efektif Erişim Doğrulaması [HIGH]
- **v1.9 Bulgusu:** `Get-Acl` veya `icacls` metin çıktısı denetimi "gerçek erişim testi" gibi sunulmuştu; reparse point TOCTOU riski ve dizin güvenlik modeli açıklanmamıştı.
- **v2.0 Çözümü (Bölüm 9.2 & 9.3):**
  1. **Bildirimsel SID Denetimi vs Dinamik Efektif Erişim Ayrıldı:**  
     - Bildirimsel denetim (`TC-S5-25`): `Get-Acl` ile ACE girdilerinde yetkisiz SID bulunmadığı doğrulanır.
     - Dinamik efektif erişim testi (`TC-S5-26`): Gerçek `MmsTestStandardUser` hesabı üzerinden 6 ayrı dosya erişim testi (root traverse, bin traverse, broker RX başarılı; data, certs, security reddi) koşulur.
  2. **TOCTOU ve Kurulum Güvenlik Modeli:** Kök dizinin sahibi Administrators grubudur; standart kullanıcıların kök dizine yazma izni bulunmadığından denetim ile ACL uygulaması arasında junction/symlink yerleştirilemeyeceği açıklandı.
  3. **Her Komutun Çıkış Kodu Kontrolü:** `Invoke-AclCommand` içinde `$p.ExitCode -ne 0` kontrolü korunarak tüm adımlarda fail-closed davranışı güvenceye alındı.

### 2.5. F5 — Named Pipe Server/Client İzinleri ve Gerçek Testler [HIGH]
- **v1.9 Bulgusu:** Sunucu ve istemci izinleri ile `FILE_CREATE_PIPE_INSTANCE` (0x0004) gereksinimi net ayrılmamıştı.
- **v2.0 Çözümü (Bölüm 4.3):**
  1. Sunucunun pipe'ı açarken `FILE_CREATE_PIPE_INSTANCE` kullandığı, ancak istemcilere verilen `0x0012019b` maskesinde 0x0004 bitinin kesinlikle sıfır olduğu netleştirildi.
  2. İstemcinin `CreateFileW` ile `0x00100003` talep ettiğinde başarılı bağlandığı; ancak aynı istemcinin `CreateNamedPipeW` ile ikinci sunucu instance açma girişiminin çekirdek tarafından `ERROR_ACCESS_DENIED` (5) ile reddedildiği açıklandı (`TC-S5-35`).
  3. TC-S5-35 (Named Pipe Server/Client İzinleri) ile TC-S5-41 (Standart Kullanıcı UAC İptali) kapsamları tamamen ayrıştırıldı.

### 2.6. F6 — Genişletilmiş Test Planı (50 Senaryo)
- **v2.0 Çözümü (Bölüm 11):**
  - Test planı **50 senaryoya** yükseltildi.
  - Açıkça iki kategoriye ayrıldı:
    - **Kategori A: Gerçek Windows Test Ortamı (Real VM / Hardware):** SCM, Service SID, Win32 DACL, NTFS ACL, WinSW v2.12.0 döngüsü, hypervisor hard crash.
    - **Kategori B: Birim & Simülasyon Testleri (İzole Test Runner):** Dart Isolate event loop admission gate, JSON-RPC serializer/parser, in-flight accounting, UUID/token validatörleri, export symbol analyzer.
  - Yeni eklenen ve ayrıştırılan özel senaryolar:
    - `TC-S5-34`: Normal UI ile Başarılı Broker Response Pipe İletişimi
    - `TC-S5-35`: Server/Client Named Pipe İzinlerinin Gerçek Windows Doğrulaması
    - `TC-S5-38`: Shutdown Drain Timeout ve Aktif DB İşlemi (Checkpoint yasağı, WAL koruma, exit 101)
    - `TC-S5-41`: Normal UI Standart Kullanıcı UAC İptali (`ERROR_CANCELLED`)
    - `TC-S5-47`: Timeout Sonrası Yeniden Başlangıçta Otomatik SQLite Crash Recovery
    - `TC-S5-48`: Aynı Kullanıcı Oturumundaki Başka Süreçten Response Pipe Erişim Girişimi
    - `TC-S5-49`: SQLite 3.46.1 C Export Sembolleri Doğrulaması (`dumpbin /EXPORTS`)
    - `TC-S5-50`: SQLite PRAGMA synchronous=FULL Fiziksel VFS ve Flush Sınırları

---

## 3. Bulguların Giderilme Eşleştirme Tablosu

| Bulgu No | Kategori | İlgili Bölüm | Yapılan v2.0 Düzeltmesi | İlgili Testler |
|:---|:---|:---|:---|:---|
| **F1** | Response Pipe DACL & Normal UI [BLOCKER] | Bölüm 3.2 | DACL'a `CURRENT_USER_SID` eklendi; DACL'ın süreç doğrulayamama açığı 5 katmanlı savunmayla (128-bit UUID, FIRST_PIPE_INSTANCE, kernel PID, hProcess fail-closed, 256-bit Nonce) kapatıldı. UAC iptal ve hata akışları tanımlandı. | `TC-S5-34`, `TC-S5-36`, `TC-S5-41`, `TC-S5-44`, `TC-S5-48` |
| **F2** | Shutdown Timeout & DB Yaşam Döngüsü [BLOCKER] | Bölüm 6.1 | WriteQueue'nun tek yazma noktası olduğu kanıtlandı; HTTP force:false/true ayrıldı. 12s drain başarılıysa checkpoint ve DB close yapıldı; drain timeout olursa checkpoint yapılmayıp WAL korundu, süreç exit(101) ile kapatılıp otomatik crash recovery'ye devredildi. | `TC-S5-05`, `TC-S5-38`, `TC-S5-47` |
| **F3** | SQLite 3.46.1 Sürüm Gerekçesi [HIGH] | Bölüm 10.1, 10.2 | C ABI stabilitesi gerekçelendirildi; 24 export sembolü şart koşuldu. Kaynak ve çıktı hash'leri ayrıldı. FULL durability'nin NTFS, FlushFileBuffers, disk write-cache ve UPS sınırları açıklandı. | `TC-S5-40`, `TC-S5-42`, `TC-S5-46`, `TC-S5-49`, `TC-S5-50` |
| **F4** | Gerçek Efektif ACL Doğrulaması [HIGH] | Bölüm 9.2, 9.3 | Bildirimsel SID denetimi ile gerçek `MmsTestStandardUser` hesabı üzerinden dinamik erişim testleri ayrıldı. Reparse point TOCTOU analizi yapıldı. Her komutun çıkış kodu kontrolü ($LASTEXITCODE) korundu. | `TC-S5-25`, `TC-S5-26`, `TC-S5-45` |
| **F5** | Server/Client Named Pipe İzinleri [HIGH] | Bölüm 4.3 | Server'ın `FILE_CREATE_PIPE_INSTANCE` kullandığı, istemciye verilen `0x0012019b` maskesinde 0x0004 bitinin bulunmadığı açıklandı. İstemcinin ikinci instance açma denemesi gerçek Windows API davranışıyla modellendi. | `TC-S5-35` |
| **F6** | Test Planı ve Sınıflandırma | Bölüm 11 | Test sayısı 50'ye çıkarıldı. Gerçek Windows VM (Kategori A) ve Birim/Simülasyon (Kategori B) olarak kategorize edildi. | `TC-S5-01` – `TC-S5-50` |

---

## 4. Karar ve Risk Durumu Özeti

### 4.1. Açık Kalan Teknik Riskler (Open Technical Risks)
1. **Pipe Squatting DoS:** Kötü niyetli bir standart sürecin makine açılışında pipe adını servisten önce kapması riski. `FILE_FLAG_FIRST_PIPE_INSTANCE` sayesinde sahte pipe'a bağlanılmaz, Event ID 4001 basılır; **HTTPS satış API'si açık tutularak mağaza satışı korunur.**
2. **RevertToSelf Kernel Hatası:** Beklenmeyen bir çekirdek arızasında `RevertToSelf` başarısız olursa thread yetki sızıntısını önlemek için sürecin derhal `ExitProcess(0xC0000005)` ile çökertilmesi (Fail-Closed).
3. **Sürücü Donanım Yazma Önbelleği (Flush Sınırı):** Tüketici sınıfı SSD'lerde işletim sistemi `FlushFileBuffers` çağırsa bile disk denetleyicisinin veriyi hemen kalıcı ortama yazmama riski. Mağaza ana PC'sinde UPS ve kurumsal SSD kullanımı bağlayıcı tavsiye olarak korunmuştur.

### 4.2. Gerçek Windows VM Ortamında Doğrulanacak Başlıklar (Kategori A)
1. **Normal UI → Elevated Broker → Response Pipe İletişimi (`TC-S5-34`):** Standart kullanıcı oturumunda açılan pipe'a UAC ile yükseltilen broker'ın bağlanması ve PID/nonce doğrulaması.
2. **UAC İptal Davranışı (`TC-S5-41`):** Kasiyer UAC penceresinde "Hayır" dediğinde UI'nin kilitlenmeden `ERROR_CANCELLED` yakalayıp pipe'ı temizlemesi.
3. **Shutdown Drain Timeout ve Otomatik Crash Recovery (`TC-S5-38` & `TC-S5-47`):** 12s timeout durumunda WAL dosyasının bozulmadan korunması ve yeniden başlatmada verilerin eksiksiz kurtarılması.
4. **Gerçek Standart Kullanıcı Efektif ACL Erişimi (`TC-S5-26`):** `MmsTestStandardUser` ile root/bin traverse, broker RX ve data/certs/pepper için kernel `ERROR_ACCESS_DENIED` dönüşü.
5. **İkinci Sunucu Pipe Instance Reddi (`TC-S5-35`):** İstemcinin `0x0012019b` haklarıyla `CreateNamedPipeW` çağrısının Windows çekirdeğince `ERROR_ACCESS_DENIED` ile reddi.

---

## 5. Değişiklik Beyanı

> [!IMPORTANT]
> **Açık Beyan:** Bu revizyon sürecinde yalnızca `S5_WINDOWS_SERVICE_PLAN.md` ve `S5_PLAN_REVISION_NOTES.md` dokümanları güncellenmiştir. Proje kök dizininde veya alt dizinlerde **hiçbir kaynak kod dosyası, test dosyası, C/C++ başlığı, derleme çıktısı, PowerShell betiği veya servis yapılandırması dosyası oluşturulmamış, değiştirilmemiş veya çalıştırılmamıştır**.

---

> [!NOTE]
> Bu belge Aşama S-5 için bağlayıcı teknik uygulama planı **v2.0** revizyon notudur. Plan teknik, mimari ve güvenlik denetimlerinden geçirilerek eksiksiz hale getirilmiş olup, kullanıcıdan açık uygulama onayı alınana kadar geliştirme başlatılmayacaktır.
