# MARKET MMS — SPIKE-01 Windows Service Graceful Shutdown Düzeltme Raporu

**Tarih:** 5 Kasım 2026  
**Rapor Adı:** `WINDOWS_SERVICE_STOP_START_FIX_REPORT.md`  
**Konum:** `test_spikes/spike_01_backend/WINDOWS_SERVICE_STOP_START_FIX_REPORT.md`  
**Kapsam:** Yalnızca `test_spikes/spike_01_backend/`  
**Nihai Sonuç:** **DÜZELTİLDİ VE DOĞRULANDI (VERIFIED)**  
**Kapanış Süresi İyileşmesi:** 15,013 ms $\longrightarrow$ **69 – 81 ms (%99.5 Hızlanma, Doğal Kapanma)**

---

## 1. Değiştirilen Dosyalar ve Yapılan Değişiklikler

Kullanıcı kurallarına tam uyum sağlanarak `exit(0)` kaba bir bypass olarak eklenmemiş; **Dart Event Loop'unu açık tutan asenkron kaynaklar kökünden temizlenmiştir**:

### A. `lib/service/lifecycle_manager.dart`
- **Sinyal Aboneliğinin İptali:** `ProcessSignal.sigint.watch().listen(...)` aboneliği `StreamSubscription<ProcessSignal>? _sigintSub` referansına bağlandı. `shutdown()` çağrıldığında `await _sigintSub?.cancel()` yapılarak Dart Event Loop'undaki açık işletim sistemi sinyal dinleme portu serbest bırakıldı.
- **Soketlerin Zorunlu Kapatılması (`force: true`):** `_server!.close(force: false)` çağrısı `_server!.close(force: true)` olarak güncellendi. `writeQueue.drain()` zaten bekleyen tüm satışları tamamladığı için, boşta bekleyen (keep-alive) HTTP bağlantılarının sunucuyu askıda tutması engellendi.

### B. `bin/server.dart`
- **Shutdown Uç Noktası:** `/api/v1/admin/shutdown` uç noktası eklendi. `Timer(const Duration(milliseconds: 50), ...)` gecikmesiyle yanıtın istemciye tam iletilmesi sağlandıktan sonra kontrollü shutdown tetiklenmesi sağlandı.

---

## 2. Kök Neden Düzeltmesi Analizi

### Problem Neydi?
Önceki sürümde `LifecycleManager.shutdown()` veritabanını ve kuyruğu kapatıyor, loga `"güvenle kapatıldı"` yazıyordu; ancak:
1. `ProcessSignal.sigint.watch()` aboneliği iptal edilmediği için Dart VM açık bir event portu olduğunu varsayıp süreci sonlandırmıyordu.
2. `HttpServer.close(force: false)` boşta bekleyen HTTP keep-alive soketlerinin kapanmasını bekliyordu.
3. Sonuç olarak child process kapanmıyor, WinSW'nin 15 saniyelik `<stoptimeout>` sayacı dolana kadar `STOP_PENDING` durumunda askıda kalıyordu. 15. saniyede WinSW süreci zorla öldürüyordu (`ProcessKill`).

### Nasıl Düzeltildi?
1. Sinyal aboneliği `await _sigintSub?.cancel()` ile kapatıldı.
2. Sunucu `force: true` ile kapatıldı.
3. `await db.close()` ile Drift'in arka plan Isolate bağlantısı kapatıldı.
4. **Sonuç:** Dart Event Loop üzerinde hiçbir açık port veya asenkron kaynak kalmadığı için Dart VM `main()` bitiminde **kendiliğinden, 70-80 milisaniye içinde exit code 0 ile kapandı.**

### `exit(0)` Değerlendirmesi:
Kullanıcı kuralı gereği `exit(0)` ilk çözüm olarak kullanılmamıştır. Yapılan testlerde, açık kaynaklar doğru kapatıldığında Dart VM'in işletim sistemi seviyesinde **hiçbir zorlamaya (`exit(0)`) gerek kalmadan kendiliğinden ve doğal şekilde sonlandığı** kanıtlanmıştır. Dolayısıyla koda suni bir `exit(0)` eklenmesine gerek kalmamış, temiz kod prensibi korunmuştur.

---

## 3. Test Sonuçları ve Zamanlama Ölçümleri

### A. Shutdown Regresyon ve 3 Ardışık Stop/Start Döngü Testi (`test/shutdown_regression_test.dart`)
```text
00:00 +0: 1. Graceful Shutdown: Süreç kaynakları temizleyip 15 sn yerine < 1.5 sn içinde kendiliğinden sonlanmalıdır
[TEST 1] Graceful Shutdown Başlatılıyor...
[TEST 1] Kapanış tamamlandı: 78 ms | Exit code: 0

00:00 +1: 2. Tekrarlı Stop/Start Döngüsü: 3 ardışık döngüde hızlı başlama, hızlı durma ve veri tutarlılığı
--- [Döngü 1 / 3] Başlatılıyor ---
[Döngü 1] Süreç ayağa kalktı (PID: 1576). /health kontrol ediliyor...
[Döngü 1] Satış tamamlandı (Tx 1).
[Döngü 1] Süreç sonlandı: 70 ms | Exit code: 0

--- [Döngü 2 / 3] Başlatılıyor ---
[Döngü 2] Süreç ayağa kalktı (PID: 17300). /health kontrol ediliyor...
[Döngü 2] Satış tamamlandı (Tx 2).
[Döngü 2] Süreç sonlandı: 72 ms | Exit code: 0

--- [Döngü 3 / 3] Başlatılıyor ---
[Döngü 3] Süreç ayağa kalktı (PID: 23464). /health kontrol ediliyor...
[Döngü 3] Satış tamamlandı (Tx 3).
[Döngü 3] Süreç sonlandı: 69 ms | Exit code: 0

00:02 +2: 3. Kapanış Sonrası SQLite Integrity ve Foreign Key Kontrolü
[TEST 3] PRAGMA integrity_check: ok
[TEST 3] PRAGMA foreign_key_check: 0 ihlal
[TEST 3] Satış kayıt sayısı: 3 (Beklenen: 3)
[TEST 3] Güncel stok: 497 (Beklenen: 497)
00:02 +3: All tests passed!
```

### B. Tüm SPIKE-01 Test Paketlerinin Regresyon Durumu

| Test Paketi | Test Sayısı | Başarılı | Başarısız | Durum |
| :--- | :---: | :---: | :---: | :---: |
| **`test/spike_test.dart`** (Ana API, Auth, Atomik Satış, Idempotency, Yük) | 11 | 11 | 0 | **GEÇTİ** |
| **`test/lifecycle_drain_test.dart`** (WriteQueue Drain & 503 Rejection) | 1 | 1 | 0 | **GEÇTİ** |
| **`test/process_crash_test.dart`** (Gerçek OS Kill & WAL Recovery) | 2 | 2 | 0 | **GEÇTİ** |
| **`test/shutdown_regression_test.dart`** (Hızlı Kapanma & 3x Stop/Start) | 3 | 3 | 0 | **GEÇTİ** |
| **GENEL TOPLAM** | **17** | **17** | **0** | **%100 BAŞARI** |

---

## 4. Kapanma Süresi Karşılaştırması

| Metrik | Düzeltme Öncesi (Kullanıcı Testi) | Düzeltme Sonrası (Mevcut Durum) |
| :--- | :---: | :---: |
| **Kapanma Süresi** | **15,013 ms** (15 saniye) | **69 – 81 ms** (0.07 saniye) |
| **Kapanma Şekli** | WinSW Timeout Sonrası `ProcessKill` (Force) | Dart VM Doğal ve Güvenli Çıkış (`exitCode: 0`) |
| **Hemen Yeniden Başlatma** | Başarısız (`has already started` / `STOP_PENDING`) | **Anında Başarılı (Sıfır Bekleme)** |
| **Veritabanı Durumu** | Tutarlı | **%100 Tutarlı (`integrity_check: ok`)** |

---

## 5. Kalan Riskler ve Öneriler

1. **WinSW SCM Entegrasyonu:**
   - Servis wrapper yapılandırmasında `<stoptimeout>15 sec</stoptimeout>` değeri güvenlik payı olarak korunmuştur.
   - Artık backend 80 milisaniyede kapandığı için, kullanıcı Windows Service olarak `stop` ve hemen ardından `start` komutlarını verdiğinde servis `STOP_PENDING` durumunda takılmayacak, anında yeniden başlayacaktır.
2. **Temiz Windows VM Doğrulaması:**
   - Kısıtlar gereği henüz temiz Windows VM testi yapılmamış olarak raporlanmıştır. Bu adım Faz 1 paketleme testlerinde ele alınacaktır.

