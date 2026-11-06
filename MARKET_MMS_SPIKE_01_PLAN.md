# MARKET MMS — SPIKE-01 TEKNİK DOĞRULAMA PLANI
## Dart AOT, Shelf, Drift/SQLite ve Windows Service Entegrasyon Prototipi

**Doküman Kodu:** `MARKET_MMS_SPIKE_01_PLAN.md`  
**Sürüm:** 1.1 (Revize Edilmiş Teknik Şartname)  
**Tarih:** 5 Kasım 2026  
**Aşama:** Faz 0 — Açık Teknik Konular ve Spike Doğrulama Planı  
**Durum:** Onaylandı — Prototip Geliştirme ve Doğrulama Aşaması  
**Doğrulanan Çalışma Zamanı:** Dart SDK `v3.13.7 (stable)`, Flutter `v3.47.9 (stable)` on Windows x64  
**Hedef Klasör:** `test_spikes/spike_01_backend/`  

---

## 1. Amaç ve Kapsam

### 1.1 Amaç
Bu teknik test planının amacı; MARKET MANAGEMENT SYSTEM (MMS) için kabul edilen **"Windows Local Master Hub üzerinde bağımsız Dart AOT derlemesi, Shelf HTTP Server, Drift/SQLite ve Windows Service barındırma"** mimari modelinin gerçek Windows işletim sistemi dinamikleri altındaki uygulanabilirliğini, sınırlarını, kaza kurtarma yeteneklerini ve SQLite eşzamanlılık davranışını izole bir prototip üzerinden **kanıt temelli olarak ölçmek, doğrulamak ve risk sınırlarını çizmektir**.

### 1.2 Kapsam Sınırları
- Bu plan, henüz **üretim koduna dokunulmadan** ve **Faz 0 resmi olarak kapatılmadan** önce yürütülecek izole bir laboratuvar şartnamesidir.
- Prototip, yalnızca `test_spikes/spike_01_backend/` adındaki bağımsız dizin altında çalıştırılacak; ana Flutter uygulama iskeletine veya mevcut mimari dokümanlara hiçbir yan etki yapmayacaktır.
- `SQLITE_BUSY` riskinin sıfırlandığına dair peşinen kanıtsız bir garanti verilmez; SQLite dosya tabanlı mimarisinin eşzamanlılık sınırları dürüstçe ölçülecektir.
- WinSW veya başka bir wrapper peşinen nihai çözüm olarak kabul edilmez; alternatif servis yönetim yöntemleri nesnel kriterlerle karşılaştırılır.

---

## 2. Bağımlılık Sürümleri ve Çözümleme Stratejisi

### 2.1 Doğrulanmış Paket Bağımlılıkları (5 Kasım 2026 İtibarıyla)

Prototip kapsamında kullanılacak paketlerin yerel geliştirme ortamı (`Dart 3.13.7 stable`) ve `pub.dev` uyumluluğu doğrulanmıştır:

| Paket / Kütüphane Adı | Hedef Sürüm | Kaynak / Doğrulama Tarihi | Rolü ve İnceleme Gerekçesi |
| :--- | :---: | :---: | :--- |
| **Dart SDK (Windows x64)** | `3.13.7` | `dart --version` (5 Kasım 2026) | Dart AOT makine kodu derleyicisi (`dart compile exe`) ve yerel I/O altyapısı. |
| **`package:shelf`** | `^1.4.1` | `pub.dev` (Kararlı) | Arka plan sürecinde HTTP pipeline, middleware ve request/response işleme. |
| **`package:shelf_router`** | `^1.1.4` | `pub.dev` (Kararlı) | REST uç noktalarının (`/health`, `/sales`, `/sync/push`, `/backup`) rotalanması. |
| **`package:shelf_cors_headers`** | `^0.1.5` | `pub.dev` (Kararlı) | Yerel loopback ve LAN çağrıları için HTTP CORS başlıkları (tarayıcı uyumu). |
| **`package:sqlite3`** | `^2.4.6` | `pub.dev` (Kararlı) | SQLite C kütüphanesi ile Dart FFI üzerinden doğrudan iletişim. |
| **`package:drift`** | `^2.20.0` | `pub.dev` / `drift.simonbinder.eu` | Tip güvenli SQL sorguları, şema yönetimi ve `NativeDatabase.createInBackground`. |
| **`package:drift_dev`** | `^2.20.0` | `pub.dev` (Dev Dependency) | Veritabanı tablolarının derleme zamanı kod üretimi (`build_runner` ile). |
| **`package:async`** | `^2.11.0` | `pub.dev` (Kararlı) | Asenkron kuyruk (`AsyncQueue`), FIFO işlem sırası ve `CancelableOperation`. |
| **`sqlite3.dll` (Precompiled)**| `v3.45+` | `sqlite.org` resmi x64 release | WAL modu, `busy_timeout` ve Online Backup API desteği sunan C kütüphanesi. |

### 2.2 Dart AOT ve Native Asset / DLL Yükleme Yaklaşımı
1. **Dart AOT Derlemesi:**
   `dart compile exe bin/server.dart -o build/spike_service.exe` komutu ile saf x64 makine kodu üretilir; hedef makinede Dart VM veya Flutter SDK aranmaz.
2. **Native Assets Durumu:**
   Dart 3.2+ ile tanıtılan deneysel Native Assets (`hook/build.dart`) özelliği CLI derlemelerinde incelenecektir. Ancak temiz hedef Windows makinelerinde harici C++ derleyici veya MSVC bağımlılığı doğurmaması için spike kapsamında **deterministik dinamik yükleme** temel yaklaşım olarak kullanılacaktır:
   ```dart
   import 'dart:ffi';
   import 'dart:io';
   import 'package:path/path.dart' as p;
   import 'package:sqlite3/open.dart';

   void configureSqliteNative() {
     open.overrideFor(OperatingSystem.windows, () {
       final exeDir = p.dirname(Platform.resolvedExecutable);
       final dllPath = p.join(exeDir, 'sqlite3.dll');
       if (!File(dllPath).existsSync()) {
         throw FileSystemException('Kritik Hata: sqlite3.dll bulunamadı!', dllPath);
       }
       return DynamicLibrary.open(dllPath);
     });
   }
   ```

---

## 3. Windows Service Barındırma ve Güvenlik İncelemesi

### 3.1 Servis Yönetim Alternatifleri

| Yaklaşım | Çalışma Modeli | Avantajlar | Riskler / Dezavantajlar | Spike Değerlendirmesi |
| :--- | :--- | :--- | :--- | :--- |
| **WinSW 2.x (v2.12.0)** | .NET Framework 4.6.1 tabanlı wrapper | Windows 10/11'de ek runtime istemez; XML ile servis yaşam döngüsü, hata kurtarma ve log rotasyonu son derece olgundur. | Harici wrapper process gerektirir; .NET Framework sürüm bağımlılığı. | **Birincil Aday** |
| **WinSW 3.x (Alpha 11)** | Native C++ Core / .NET Core tabanlı | YAML desteği, modern mimari. | Henüz resmî olarak **alpha/önizleme** aşamasındadır; üretim MMS için stabilite riski taşır. | **Karşılaştırmalı Aday** |
| **NSSM (v2.24)** | Saf C tabanlı hafif wrapper | ~300 KB hafiflik, sıfır runtime, GUI ve CLI desteği. | 2017'den beri güncellenmemiştir; Windows 11 I/O yönlendirmelerinde nadir hatalar raporlanmıştır. | **Yedek Aday** |
| **Native Win32 FFI** | Dart FFI (`package:win32`) ile SCM API | Sıfır harici wrapper dosyası; saf Dart çözümü. | SCM 30 sn handshake kuralı; Dart event loop blokajında servisin Windows tarafından öldürülme riski çok yüksektir. | **Yüksek Riskli (Yalnızca incelenecek)** |

### 3.2 Güvenlik, İzinler ve Çalışma Hesabı
- **Çalışma Hesabı (Service Account):**
  - Servis kesinlikle tam yetkili `LocalSystem` hesabıyla **çalıştırılmamalıdır**.
  - En az yetki ilkesi (Least Privilege) uyarınca **`NT AUTHORITY\LocalService`** veya **`NT AUTHORITY\NetworkService`** hesabı altında çalıştırılacaktır.
- **Dosya Sistemi Erişim İzinleri (NTFS ACLs):**
  - Merkezi veritabanı dizini: `%PROGRAMDATA%\MarketMMS\Data\`
  - ACL Kuralı: Yalnızca `Administrators` ve `NT AUTHORITY\LocalService` hesaplarına `Full Control / Modify` hakkı tanınır; standart Windows kullanıcılarının (kasiyerler) doğrudan dosya değiştirmesi engellenir:
    ```cmd
    icacls "%PROGRAMDATA%\MarketMMS\Data" /grant "NT AUTHORITY\LocalService:(OI)(CI)F"
    ```
- **Windows Güvenlik Duvarı (Firewall) Kapsamı:**
  - Güvenlik duvarı kuralı asla genel (Public) ağlara açık bırakılmamalıdır.
  - Yalnızca `Private` ve `Domain` ağ profillerine izin verilecek şekilde yapılandırılmalıdır:
    ```cmd
    netsh advfirewall firewall add rule name="Market MMS Local Hub" dir=in action=allow protocol=TCP localport=8080 profile=private,domain
    ```
- **Kimlik Doğrulama ve CORS Sınırları:**
  - **Kritik İlke:** CORS (`Cross-Origin Resource Sharing`), yalnızca web tarayıcıları için bir güvenlik mekanizmasıdır; native Flutter/Dart HTTP istemcileri veya Curl çağrıları CORS kurallarını doğrudan atlar.
  - Bu nedenle **CORS kesinlikle bir kimlik doğrulama veya yetkilendirme aracı olarak kullanılamaz**.
  - Yetkilendirme; HTTP Header üzerinden iletilen kriptografik **Bearer Device Token** (`Authorization: Bearer <token>`) ile API middleware düzeyinde doğrulanacaktır. Yetkisiz LAN istemcileri `HTTP 401/403` ile reddedilecektir.

---

## 4. SQLite Yazma Koordinasyonu ve Worker Isolate

### 4.1 SQLite Eşzamanlılık Sınırları
- SQLite WAL modunda paralel okuma desteklenir; ancak yazma anında dosya düzeyinde `EXCLUSIVE` kilit alınır.
- `PRAGMA busy_timeout = 5000;` ayarı kilit çakışmalarını 5 saniyeye kadar bekletir; ancak yoğun eşzamanlı yazmada zaman aşımı oluşursa `SQLITE_BUSY` hatası kaçınılmazdır.
- **Gerçekçi Tasarım:** Spike'ın amacı kilitlenmenin "asla olmayacağını" varsaymak değil, yük altında yazılımsal kuyrukla bu hatayı en aza indirmek ve oluştuğunda sistemli yönetmektir.

### 4.2 Worker Isolate ve `NativeDatabase.createInBackground`
Dart tek iş parçacıklı event loop mimarisine sahiptir. SQLite disk I/O işlemleri ana isolate'te çalıştırılırsa, HTTP sunucusu gelen isteklere yanıt veremez ve geçici donmalar oluşur.
- **Çözüm:** Drift'in yerleşik `NativeDatabase.createInBackground(dbFile)` API'si kullanılacaktır.
- Bu mekanizma, SQLite bağlantısını otomatik olarak arka planda bağımsız bir Dart Isolate içine taşır; Shelf HTTP sunucusu ile veritabanı arasındaki iletişim izole mesaj portları üzerinden asenkron yürütülür.

### 4.3 Gelişmiş Tekil Yazıcı Kuyruğu (WriteQueue) Şartnamesi
Prototipte test edilecek yazma kuyruğu aşağıdaki yeteneklere sahip olmalıdır:
1. **FIFO Sıralaması:** Gelen yazma işlemleri sırayla işletilir.
2. **Kaza ve İptal Yönetimi (Cancellation):** İstemci bağlantıyı kopardığında henüz başlamamış kuyruk görevleri iptal edilebilir.
3. **Geçici Hata ve Retry Politikası:** `SqliteException(5)` (`SQLITE_BUSY`) hatası alındığında, üstel geri çekilme (exponential backoff: 50ms, 150ms, 300ms) ile en fazla 3 kez tekrar denenir; başarısız olursa istemciye `HTTP 503 Service Unavailable` dönülür.
4. **Güvenli Kapanış (Graceful Shutdown / Drain):** Servis durdurma sinyali (`SIGTERM`) aldığında, kuyruk yeni istekleri kabul etmeyi durdurur (`HTTP 503`), ancak kuyrukta bekleyen mevcut işlemleri 5 saniyelik bir zaman aşımı içinde tamamlar.

---

## 5. Test Senaryoları ve Doğrulama Adımları

---

### Test Senaryosu 1: Temiz Windows (Zero-SDK) Dağıtım ve Servis Kurulumu
- **Ortam:** Hiçbir SDK kurulu olmayan saf Windows 10/11 x64 VM.
- **Adımlar:**
  1. Derlenen paket (`spike_service.exe`, `sqlite3.dll`, `winsw.exe`, `winsw.xml`) sanal makinede `C:\MarketMMS\Service\` klasörüne kopyalanır.
  2. Yönetici komut satırından `winsw.exe install` ve `winsw.exe start` çalıştırılır.
  3. `LocalService` hesabı izinleri ve servis durumu denetlenir (`sc.exe query MarketMmsSpike`).
  4. Yerel loopback çağrısı yapılır: `curl http://127.0.0.1:8080/health`.
- **Kabul Kriteri:**
  - Servis durumunun `RUNNING` olması.
  - `/health` uç noktasının HTTP 200 dönmesi.
  - Eksik C++ çalışma zamanı hatası (`vcruntime140.dll` eksikliği) durumunun tespit edilip belgelenmesi.

---

### Test Senaryosu 2: Servis Kaza Kurtarma ve SCM Yeniden Başlatma
- **Amaç:** Servis süreci çöktüğünde SCM'nin toparlanma davranışını ve SQLite WAL otomatik kurtarmasını test etmek.
- **Adımlar:**
  1. Servis aktifken Görev Yöneticisi'nden `spike_service.exe` süreci zorla öldürülür (`taskkill /F /IM spike_service.exe`).
  2. Windows Olay Günlüğü (Application Event Log) ve WinSW log dosyası incelenir.
  3. Servisin SCM tarafından yeniden başlatılma süresi ölçülür.
  4. Yeniden açılışta `GET /health` ile SQLite `PRAGMA integrity_check` çağrılır.
- **Kabul Kriteri:**
  - Servisin konfigüre edilen sürede (ör. 10 saniye içinde) otomatik yeniden başlaması.
  - `integrity_check` sonucunun `"ok"` dönmesi.

---

### Test Senaryosu 3: Transaction Ortasında Kaza ve Veri Bütünlüğü
- **Amaç:** Yarım kalmış transaction'ların veri tabanını bozmadığını kanıtlamak.
- **Adımlar:**
  1. 100 kalemlik toplu bir satış transaction'ı başlatılır (`BEGIN IMMEDIATE`).
  2. 50. kalem yazıldıktan sonra kasıtlı olarak süreç `exit(1)` ile sonlandırılır.
  3. Servis yeniden başlatılır.
- **Kabul Kriteri:**
  - Tamamlanmamış 50 kalemin hiçbirinin veritabanında kalmaması (tam atomik rollback).
  - Veritabanı dosyasının bozulmaması; SQLite WAL kurtarma mekanizmasının tutarlı duruma dönmesi.

---

### Test Senaryosu 4: Eşzamanlı Yük ve Performans Profili (Baseline vs. Stres)
Testler iki ayrı yük fazında icra edilecek; keyfî eşikler yerine gerçek gecikme persentilleri (P50, P95, P99) ölçülecektir:

- **Faz 4.A — Normal Mağaza Yükü (Baseline):**
  - **Profil:** 1 Windows UI (loopback) + 3 Mobil İstemci (LAN simülasyonu).
  - **Yük:** 4 eşzamanlı istemciden 5 dakika boyunca toplam 500 satış işlemi.
- **Faz 4.B — Stres ve Sınır Testi (Burst):**
  - **Profil:** 10 eşzamanlı istemci.
  - **Yük:** Eşzamanlı 1.000 satış fişi, 3.000 sepet kalemi ve 3.000 stok hareketi.
- **Ölçülecek ve Raporlanacak Metrikler:**
  - Gecikme Dağılımı: **P50 (Medyan), P95 ve P99** yanıt süreleri (ms).
  - Kaynak Kullanımı: Boşta ve yük altında RAM (Working Set vs. Private Bytes) ve CPU kullanımı (%).
  - Throughput: Saniyedeki işlem adedi (TPS).
  - Hata Oranı: `SQLITE_BUSY` ve HTTP 5xx hata yüzdesi.
- **Zorunlu Kriter:** Veri bütünlüğü performanstan bağımsız olarak %100 olmalıdır (başarılı dönen tüm satışlar veritabanında eksiksiz doğrulanmalıdır).

---

### Test Senaryosu 5: ACK Kaybı ve Mükerrer Gönderim (Idempotency) Testi
- **Amaç:** Ağ kopmasında istemcinin tekrar gönderdiği satışların çift kayıt yaratmadığını doğrulamak.
- **Adımlar:**
  1. İstemci `POST /sales` ile `idempotency_key = "DEV1:101"` satışını gönderir.
  2. Sunucu satışı yazar; ancak ağ simülatörü HTTP yanıtını düşürür (ACK kaybolur).
  3. İstemci aynı `idempotency_key` ile isteği tekrar gönderir.
- **Kabul Kriteri:**
  - Sunucunun `processed_operations` defterinden mükerrerliği tespit etmesi.
  - İkinci kez stok düşülmemesi; önceki başarılı yanıtın dönülmesi.
  - Veritabanında mükerrer satış fişi oluşmaması.

---

### Test Senaryosu 6: Canlı Yedekleme (`VACUUM INTO`) ve Kontrollü Geri Yükleme
- **Amaç:** Canlı satış akarken hot snapshot alınabildiğini ve geri yüklenebildiğini kanıtlamak.
- **Adımlar:**
  1. Test Senaryosu 4 aktifken eşzamanlı olarak `POST /backup/snapshot` tetiklenir (`VACUUM INTO 'C:\Backups\snapshot.db'`).
  2. Alınan `snapshot.db` üzerinde `PRAGMA integrity_check;` çalıştırılır.
  3. Snapshot içerisindeki toplam satış adedi ve ciro, snapshot anındaki ana veritabanı ile karşılaştırılır.
  4. **Kontrollü Restore Testi:**
     - Restore öncesi koruyucu güvenlik yedeği alınır (`pre_restore_safety_snapshot.db`).
     - Servis durdurulur; `snapshot.db` ana dosya üzerine yazılır.
     - Servis başlatılır ve veri doğrulaması yapılır.
- **Kabul Kriteri:**
  - Canlı yedekleme anında satış işlemlerinin dosya kilit hatası (`ERROR_SHARING_VIOLATION`) almaması.
  - Snapshot dosyasının %100 sağlam ve tutarlı olması.

---

### Test Senaryosu 7: Ağ Güvenliği ve Yetkisiz Cihaz Reddi Testi
- **Amaç:** Wi-Fi ağına sızan yabancı bir cihazın API'ye yazma yapamadığını doğrulamak.
- **Adımlar:**
  1. Yetkilendirme token'ı taşımayan yabancı bir istemciden `POST /sales` çağrısı yapılır.
  2. Geçersiz veya süresi dolmuş token ile çağrı yapılır.
  3. Yalnızca geçerli cihaz token'ına sahip istemciden çağrı yapılır.
- **Kabul Kriteri:**
  - Yetkisiz isteklerin `HTTP 401 Unauthorized` ile reddedilmesi; veritabanına erişememesi.

---

## 6. Prototip Dosya ve Klasör Yapısı

Prototip çalışmaları için belirlenen tek standart dizin:

```text
test_spikes/spike_01_backend/
├── bin/
│   └── server.dart                   # Shelf HTTP sunucusu ve REST rotaları
├── lib/
│   ├── db/
│   │   ├── database.dart             # Drift şeması ve NativeDatabase konfigürasyonu
│   │   └── write_queue.dart          # Gelişmiş WriteQueue (Retry, Drain, Cancel)
│   ├── security/
│   │   └── auth_middleware.dart      # Bearer Token ve cihaz doğrulama filtresi
│   └── service/
│       └── lifecycle_manager.dart    # Graceful shutdown ve sinyal yakalama
├── test_client/
│   └── stress_tester.dart            # Normal ve stres yükü simülatörü (P50/P95/P99 ölçer)
├── service_wrapper/
│   ├── winsw.exe                     # WinSW çalıştırılabilir dosyası
│   ├── winsw.xml                     # Windows Service konfigürasyon dosyası
│   └── sqlite3.dll                   # x64 SQLite C kütüphanesi
├── pubspec.yaml                      # Spike paket bağımlılıkları
└── build.ps1                         # AOT derleme ve VM dağıtım hazırlık betiği
```

---

## 7. Riskler ve Gerçekçi Sınırlar

1. **`SQLITE_BUSY` Kaçınılmazlığı:** Yazılımsal kuyruk bulunsa dahi, disk I/O darboğazlarında veya uzun süren bakım sorgularında kuyruk zaman aşımları yaşanabilir. Bu durum sistemli bir retry ve `HTTP 503` hata yanıtı ile istemci tarafında yönetilmelidir.
2. **Kurtarılamayan İstemci Outbox Riski:** Eğer bir mobil cihaz Master Hub ile senkronize olmadan fiziksel olarak parçalanır veya kalıcı olarak bozulursa, o cihazdaki bekleyen yerel satışların kurtarılması fiziksel olarak imkansızdır. Sistem mutlak sıfır veri kaybı garantisi veremez.
3. **C++ Redistributable Bağımlılığı:** Temiz Windows sistemlerinde `sqlite3.dll` çalışabilmesi için Microsoft Visual C++ 2015-2022 Redistributable paketinin kurulu olması gerekebilir; Inno Setup yükleyicisinde bu kontrol zorunlu tutulmalıdır.
4. **WinSW Alpha Riski:** WinSW 3.x henüz alpha aşamasında olduğundan, spike sonuçları doğrulanana kadar üretim adayı olarak WinSW 2.x (.NET 4.6.1) esas alınacaktır.

---

## 8. Sonraki Adım ve Ön Koşullar

Bu plan bir hazırlık ve doğrulama şartnamesidir. Prototip kodlamasına başlamadan önce:
- [ ] Kullanıcının bu revize test planını onaylaması.
- [ ] Testlerin icra edileceği temiz Windows sanal makinesinin (VM) veya test ortamının hazır edilmesi.
- [ ] `test_spikes/spike_01_backend/` dizini altında izole prototip kodlarının oluşturulması için onay verilmesi.

*Kullanıcının onayı beklenmektedir; onay verilmeden kodlama aşamasına geçilmeyecektir.*

