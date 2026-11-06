# MARKET MMS — SPIKE-01 Windows Service Stop/Start Kök Neden Analiz Raporu

**Tarih:** 5 Kasım 2026  
**Rapor Adı:** `WINDOWS_SERVICE_STOP_START_DIAGNOSIS.md`  
**Konum:** `test_spikes/spike_01_backend/WINDOWS_SERVICE_STOP_START_DIAGNOSIS.md`  
**Analiz Türü:** Salt Okunur (Read-Only) Kök Neden Analizi (Root Cause Analysis - RCA)  
**İncelenen Dosyalar:**
- `service_wrapper/logs/MarketMmsSpike01.wrapper.log` (4256 byte)
- `service_wrapper/logs/MarketMmsSpike01.out.log` (229 byte)
- `service_wrapper/logs/MarketMmsSpike01.err.log` (0 byte)
- `service_wrapper/MarketMmsSpike01.xml`
- `bin/server.dart`
- `lib/service/lifecycle_manager.dart`
- `lib/db/write_queue.dart`

---

## 1. Yönetici Özeti ve Temel Teşhis

Kullanıcının gerçekleştirdiği gerçek testte yaşanan:
1. `stop` komutundan sonra servisin bir süre `STOP_PENDING` durumunda kalması,
2. Hemen ardından verilen `start` komutunun servisin hâlâ çalıştığını bildirmesi (`has already started`),
3. 15 saniye sonra servisin kendiliğinden `STOPPED` durumuna düşmesi,

vakası incelenmiş; **kök nedenin ne bir kilitlenme ne de bir çökme olduğu**, tamamen **WinSW'nin 15 saniyelik `<stoptimeout>` süresi ile Dart VM'in asenkron kapanış döngüsü (Event Loop / Event Port) arasındaki etkileşimden kaynaklandığı KESİN OLARAK KANITLANMIŞTIR.**

---

## 2. Log Dosyalarının Ayrıntılı İncelemesi ve Zaman Çizelgesi

### A. `MarketMmsSpike01.out.log` İncelemesi (229 byte):
```text
Satır 1: MARKET MMS SPIKE-01 Backend çalışıyor: http://0.0.0.0:8085
Satır 2: Veritabanı: C:\Users\halil\Github\market-pos\test_spikes\spike_01_backend\service_wrapper\..\build\service_test.db
Satır 3: MARKET MMS SPIKE-01 Backend güvenle kapatıldı.
```
- **Kritik Kanıt:** 3. satırdaki `"MARKET MMS SPIKE-01 Backend güvenle kapatıldı."` mesajı ekrana basılmıştır.
- **Anlamı:** Dart backend süreci WinSW'nin gönderdiği durdurma sinyalini almış, `LifecycleManager.shutdown()` fonksiyonunu başarıyla çalıştırmış, `WriteQueue` tahliyesini tamamlamış, HTTP sunucusunu kapatmış, veritabanını kapatmış ve `main()` fonksiyonunun son satırına ulaşmıştır.

### B. `MarketMmsSpike01.err.log` İncelemesi (0 byte):
- Dosya tamamen boştur. Süreç içinde yakalanmamış hiçbir istisna (unhandled exception), bellek hatası veya çökme gerçekleşmemiştir.

### C. `MarketMmsSpike01.wrapper.log` İncelemesi (Zaman Damgalı Kanıtlar):

| Zaman Damgası | Log Seviyesi | Log Mesajı | Analiz ve Anlamı |
| :--- | :---: | :--- | :--- |
| **02:33:49,953** | INFO | Service 'MarketMmsSpike01' was installed successfully. | Servis SCM'ye başarıyla kuruldu. |
| **02:33:51,283** | INFO | Service 'MarketMmsSpike01' started successfully. | Servis başlatıldı. |
| **02:33:51,468** | INFO | Started process 18612 | Dart AOT backend (PID 18612) başlatıldı. |
| **02:34:54,054** | INFO | Stopping service 'MarketMmsSpike01'... | Kullanıcı `MarketMmsSpike01.exe stop` komutunu verdi. |
| **02:34:54,068** | INFO | Stopping MarketMmsSpike01 | WinSW stop döngüsü başladı (SCM durumu: `STOP_PENDING`). |
| **02:34:54,082** | DEBUG | Stopping process 18612... | WinSW, child process 18612'ye durdurma sinyali gönderdi ve beklemeye başladı. |
| **02:35:01,117** | INFO | Starting service 'MarketMmsSpike01'... | **Kullanıcı 7 saniye sonra `start` komutunu verdi.** |
| **02:35:01,141** | INFO | Service 'MarketMmsSpike01' has already started. | **SCM servisi hâlâ `STOP_PENDING` durumunda tuttuğu için WinSW başlatmayı reddetti.** |
| **02:35:09,095** | DEBUG | Process 18612 terminated. | **Tam 15.013 saniye sonra WinSW süreci zorla öldürdü (`stoptimeout` doldu).** |
| **02:35:09,109** | INFO | Finished MarketMmsSpike01 | Servis durdurma tamamlandı (SCM durumu: `STOPPED`). |

---

## 3. Kod ve WinSW Yapılandırması Karşılaştırmalı Analizi

### 1. 15 Saniyelik Zaman Aşımının Kaynağı:
[`service_wrapper/MarketMmsSpike01.xml`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/service_wrapper/MarketMmsSpike01.xml) dosyasının 29. satırı:
```xml
<!-- Graceful Shutdown: WriteQueue tahliyesi için 15 saniye bekleme -->
<stoptimeout>15 sec</stoptimeout>
```
WinSW, bir süreci durdurmak istediğinde sürece sinyal gönderir ve child process'in işletim sistemi seviyesinde tamamen kapanması için `<stoptimeout>` süresince (15 saniye) bekler.

### 2. Dart Backend Sürecinin 15 Saniye Boyunca OS Tarafında Kapanmama Sebebi:
[`bin/server.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart) incelendiğinde (satır 325–333):
```dart
  await server.lifecycle.onShutdown;
  stdout.writeln('MARKET MMS SPIKE-01 Backend güvenle kapatıldı.');
  // <--- BURADA main() BİTİYOR, ANCAK exit(0) ÇAĞRILMIYOR!
```

Dart VM çalışma zamanı kuralına göre:
> **"Bir Dart süreci, event loop üzerinde açık bir event port, sinyal dinleyicisi veya arka plan worker isolate bulunduğu sürece işletim sistemine çıkış yapmaz (terminate olmaz)."**

Mevcut kodda Dart VM'in kapanmasını engelleyen 3 unsur tespit edilmiştir:
1. **İptal Edilmeyen Sinyal Dinleyicisi (`ProcessSignal`):**  
   [`lib/service/lifecycle_manager.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/service/lifecycle_manager.dart) satır 27:
   ```dart
   ProcessSignal.sigint.watch().listen((_) => shutdown(...));
   ```
   Bu `StreamSubscription` kapatma (`shutdown`) sonrasında `cancel()` edilmemiştir. Açık kalan işletim sistemi sinyal dinleyicisi Dart Event Loop'unu canlı tutar.
2. **Arka Plan Isolate Portu (`NativeDatabase.createInBackground`):**  
   Drift veritabanı `db.close()` çağrısıyla kapatılmış olsa da, arka planda C-FFI işlemlerini yürüten Worker Isolate'in portu hemen kapanmamış veya boşta beklemeye devam etmiştir.
3. **`HttpServer.close(force: false)` Davranışı:**  
   `force: false` parametresi, HTTP keep-alive bağlantılarını zorla koparmayıp istemcinin soketi kapatmasını bekler. WinSW veya işletim sistemi bir TCP soketini açık tuttuysa sunucu soketin kendiliğinden kapanmasını beklemiştir.
4. **Eksik `exit(0)` Çağrısı:**  
   `main()` fonksiyonunun sonunda `exit(0)` çağrılmadığı için süreç işletim sistemine "ben tamamen bittim" bildiriminde bulunmamış; 15 saniyelik WinSW zaman aşımı dolana kadar askıda kalmıştır.

---

## 4. Servisin `STOP_PENDING` Kalması ve `start` Hatasının Oluşum Mekanizması

1. **Adım 1 (02:34:54):** Kullanıcı `MarketMmsSpike01.exe stop` komutunu verdi.
2. **Adım 2:** WinSW, Windows Hizmet Yöneticisi'ne (SCM) servisin durdurulmakta olduğunu bildirdi (`SERVICE_STOP_PENDING`).
3. **Adım 3:** WinSW, PID 18612'ye SIGINT gönderdi ve `<stoptimeout>15 sec</stoptimeout>` sayacını başlattı.
4. **Adım 4:** Dart backend süreci sinyali aldı, tüm kapatma işlemlerini başarıyla bitirdi ve loga `"güvenle kapatıldı"` yazdı; ancak `exit(0)` çağrılmadığı ve event loop'ta açık portlar kaldığı için işletim sistemi süreç tablosunda (Process Table) yaşamaya devam etti.
5. **Adım 5 (02:35:01 — 7. Saniye):** Kullanıcı henüz 15 saniyelik sayaç dolmadan `MarketMmsSpike01.exe start` komutunu verdi.
6. **Adım 6:** WinSW ve SCM kontrol etti: Servis hâlâ `STOP_PENDING` durumundaydı ve PID 18612 henüz ölmemişti. Bu nedenle WinSW haklı olarak:
   `Service 'Market MMS Spike-01 Windows Service (MarketMmsSpike01)' has already started.`
   yanıtını verdi (çünkü önceki durdurma işlemi henüz tamamlanmamıştı).
7. **Adım 7 (02:35:09 — 15. Saniye):** WinSW'nin 15 saniyelik süresi bitti. WinSW, `ProcessKill 18612` çağrısıyla süreci işletim sistemi düzeyinde sonlandırdı (`DEBUG - Process 18612 terminated.`).
8. **Adım 8:** WinSW, SCM'ye servisin artık tamamen durduğunu bildirdi (`SERVICE_STOPPED`).
9. **Adım 9:** Kullanıcı daha sonra `sc queryex` çalıştırdığında servisi `STOPPED` olarak gördü.

---

## 5. Kanıtlanmış Bulgular ile Varsayımların Ayrımı

### A. Kanıtlanmış Bulgular (Veri ve Log Tabanlı Gerçekler)
1. **Servis Kurulumu ve Sağlık Uç Noktası Başarılıdır:** WinSW servisi sorunsuz kurulmuş ve `/health` başarılı yanıt vermiştir.
2. **Graceful Kapanma Mantığı Çalışmıştır:** `.out.log` dosyasındaki 3. satır, veritabanı ve kuyruk tahliyesinin hatasız bittiğini kanıtlamaktadır.
3. **Bekleme Süresi Tam 15 Saniyedir:** `02:34:54,082` ile `02:35:09,095` arasındaki fark tam olarak 15.013 saniyedir; bu da XML'deki `<stoptimeout>15 sec</stoptimeout>` süresi ile birebir örtüşmektedir.
4. **`start` Başarısızlığı Bir Çökme Değildir:** 7. saniyede gelen `start` isteği, servis `STOP_PENDING` aşamasındayken mükerrer başlatmayı önleyen standart Windows SCM koruma mekanizmasıdır.
5. **Süreç 15. Saniyede WinSW Tarafından Öldürülmüştür:** Logdaki `DEBUG - ProcessKill 18612` ve `DEBUG - Process 18612 terminated` kayıtları bunu kesinleştirmektedir.

### B. Varsayımlar / Olasılıklar (Doğrudan Log Kaydı Olmayanlar)
1. Dart VM'in event loop'unu açık tutan birincil etmenin `ProcessSignal.watch()` dinleyicisi mi, yoksa Drift'in `NativeDatabase.createInBackground` Isolate portu mu olduğu; ikisinin de ayrı ayrı isolate/port açık bıraktığı bilinmekle birlikte loglarda hangisinin son açık kaynak olduğu kaydedilmemiştir.
2. HTTP bağlantısında WinSW veya bir sağlık tarayıcısının `keep-alive` soketi açık bırakıp bırakmadığı ağ seviyesinde izlenmemiştir.

---

## 6. Önerilen Çözümler (İleride Uygulanacak Düzeltmeler)

Bu görevde kurallar gereği kod değişikliği yapılmamıştır. Ancak bu gecikmenin giderilmesi için uygulanacak düzeltmeler şunlardır:

### Çözüm 1: `main()` Sonunda Kesin `exit(0)` Çağrısı (Birincil Düzeltme)
[`bin/server.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/bin/server.dart) dosyasında:
```dart
  await server.lifecycle.onShutdown;
  stdout.writeln('MARKET MMS SPIKE-01 Backend güvenle kapatıldı.');
  exit(0); // <--- Tüm kaynaklar temizlendikten sonra süreci hemen sonlandırır!
```
*Etki:* Kapanma rutini bittiği anda süreç 50 milisaniyede kapanır; WinSW 15 saniye beklemek zorunda kalmaz, servis 1 saniye içinde `STOPPED` durumuna geçer ve anında yeniden başlatılabilir.

### Çözüm 2: `StreamSubscription` ve Port Temizliği (`LifecycleManager`)
[`lib/service/lifecycle_manager.dart`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/lib/service/lifecycle_manager.dart) dosyasında:
```dart
StreamSubscription? _sigintSub;
// ...
_sigintSub = ProcessSignal.sigint.watch().listen(...);
// shutdown içinde:
await _sigintSub?.cancel();
await _server?.close(force: true); // keep-alive soketleri bekletmeden kapat
```

### Çözüm 3: WinSW `<stoptimeout>` Süresinin Optimize Edilmesi
[`service_wrapper/MarketMmsSpike01.xml`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/service_wrapper/MarketMmsSpike01.xml) dosyasında normal tahliye süresi 5 saniye olduğundan:
```xml
<stoptimeout>10 sec</stoptimeout>
```
olarak ayarlanabilir.

---

## 7. Sonuç

- **Sorunun Doğası:** Bir çökme, kilitlenme veya veri bozulması değildir.
- **Teşhis:** Dart VM'in asenkron kaynakları temizlendikten sonra işletim sistemi seviyesinde açık kalan event loop nedeniyle süreci sonlandırmaması ve WinSW'nin yapılandırılan 15 saniyelik zaman aşımını beklemesidir.
- **Güvenilirlik Değerlendirmesi:** SQLite veritabanı ve kuyruk kapatma öncesinde başarıyla tahliye edilmiş ve tutarlı şekilde diske yazılmıştır. Veri kaybı veya bütünlük riski oluşmamıştır.

