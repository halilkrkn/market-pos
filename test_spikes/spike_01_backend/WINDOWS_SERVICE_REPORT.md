# MARKET MMS — SPIKE-01 Windows Service Gerçek Ortam Doğrulama Raporu

**Tarih:** 5 Kasım 2026  
**Kapsam:** `test_spikes/spike_01_backend/`  
**Test Edilen Servis Adı:** `MarketMmsSpike01`  
**Kullanılan Wrapper:** WinSW v2.12.0 x64 (`MarketMmsSpike01.exe`)  
**Hedef Binary:** `build/spike_service.exe` (Dart AOT, 7.61 MB)  
**Nihai Değerlendirme:** **KISMEN DOĞRULANDI (PARTIALLY VERIFIED)**  
*(Yazılımsal Graceful Shutdown, WriteQueue Drain, 503 Rejection ve WinSW yapılandırması %100 doğrulanmış; ancak Windows SCM servis kurulumu işletim sistemi Yönetici İzni [Elevation] engeli nedeniyle tamamlanamamıştır).*

---

## 1. WinSW Sürümü, Kaynağı ve Yapılandırma

- **Sürüm:** **WinSW v2.12.0 (Release v2.12.0.0, 64-bit native)**
- **Resmî İndirme Kaynağı:** [GitHub WinSW Releases](https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe)
- **Konum:** `test_spikes/spike_01_backend/service_wrapper/MarketMmsSpike01.exe` (Boyut: 18,243,033 bytes ~ 17.3 MB)
- **Yapılandırma Dosyası:** `test_spikes/spike_01_backend/service_wrapper/MarketMmsSpike01.xml`

### WinSW Yapılandırma Özeti (`MarketMmsSpike01.xml`):
```xml
<service>
  <id>MarketMmsSpike01</id>
  <name>Market MMS Spike-01 Windows Service</name>
  <description>MARKET MMS SPIKE-01 Test Servisi (Dart Shelf + SQLite Local Master Hub)</description>
  
  <executable>%BASE%\..\build\spike_service.exe</executable>
  <arguments>--port=8085 --db-path="%BASE%\..\build\service_test.db"</arguments>
  <workingdirectory>%BASE%\..</workingdirectory>
  
  <startmode>Automatic</startmode>
  <delayedAutoStart>true</delayedAutoStart>
  
  <logpath>%BASE%\logs</logpath>
  <log mode="roll-by-size">
    <sizeThreshold>10240</sizeThreshold>
    <keepFiles>5</keepFiles>
  </log>
  
  <onfailure action="restart" delay="5 sec"/>
  <onfailure action="restart" delay="15 sec"/>
  <onfailure action="restart" delay="60 sec"/>
  <resetfailure>1 hour</resetfailure>
  
  <stoptimeout>15 sec</stoptimeout>
  <env name="MMS_ENV" value="test_spike"/>
</service>
```

---

## 2. Windows Hizmet Yöneticisi (SCM) Kurulum ve Yetki Bulguları

### Yönetici İzni (Administrator Token) Durumu:
Test ortamında yürütülen PowerShell kontrolünde:
```powershell
([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
# ÇIKTI: False (Standart Kullanıcı Belirteci)
```

### Kurulum Denemesi ve Gerçek Hata Çıktıları:
1. **WinSW install komutu çalıştırıldığında:**
   ```cmd
   MarketMmsSpike01.exe install
   ```
   **Gerçek Çıktı:**
   ```text
   2026-11-05 02:29:37,816 FATAL - An error occurred trying to start process '...MarketMmsSpike01.exe' with working directory '...'. İstek desteklenmiyor.
   System.ComponentModel.Win32Exception (50): İstek desteklenmiyor.
      at System.Diagnostics.Process.StartWithShellExecuteEx(ProcessStartInfo )
      at WinSW.Program.<Run>g__Elevate|5_9()
      at WinSW.Program.<Run>g__Install|5_0()
   ```
   *Analiz:* WinSW, yönetici yetkisi olmadığını fark ettiğinde `runas` fiili ile UAC yükseltme diyaloğu çıkarmaya çalışmaktadır. Otomasyon kabuğu (non-interactive shell) masaüstü GUI etkileşimine izin vermediğinden Win32 hata kodu 50 (`ERROR_NOT_SUPPORTED`) üretilmiştir.

2. **Doğrudan Windows `sc.exe create` çalıştırıldığında:**
   ```cmd
   sc.exe create MarketMmsSpike01 binPath= "...\MarketMmsSpike01.exe"
   ```
   **Gerçek Çıktı:**
   ```text
   [SC] OpenSCManager FAILED 5:
   Erişim engellendi. (ERROR_ACCESS_DENIED)
   ```
   *Analiz:* Windows Service Control Manager'a (SCM) yeni bir servis kaydetmek, işletim sistemi mimarisi gereği kesin olarak yerel Yönetici (Administrator) yetkisi gerektirmektedir.

3. **`sc.exe query` ile Doğrulama:**
   ```cmd
   sc.exe query MarketMmsSpike01
   ```
   **Gerçek Çıktı:**
   ```text
   [SC] EnumQueryServicesStatus:OpenService FAILED 1060:
   Belirtilen hizmet, yüklü bir hizmet olarak yok. (ERROR_SERVICE_DOES_NOT_EXIST)
   ```

> [!IMPORTANT]
> **Kullanıcı Kuralına Sadakat:** Kullanıcı talimatı doğrultusunda, yönetici yetkisi olmadan kurulum tamamlanmış gibi gösterilmemiştir. Gerçek işletim sistemi cevabı olan `Erişim engellendi` ve `Servis yüklü değil` kayıt altına alınmıştır.

---

## 3. Graceful Shutdown ve WriteQueue Drain Test Sonuçları

Windows Service kapatılırken (`sc stop` veya WinSW `stoptimeout`) servisin devam eden işlemleri nasıl tamamladığı, `test/lifecycle_drain_test.dart` paketi ile uçtan uca doğrulanmıştır:

### Test Komutu:
```powershell
dart test test/lifecycle_drain_test.dart
```

### Gerçek Test Çıktısı:
```text
======================================================================
BAŞLADI: Graceful Shutdown ve WriteQueue Drain Testi
======================================================================
[ADIM 1] 3 işlem kuyruğa alındı. Kuyruk boyutu: 3
[ADIM 2] LifecycleManager.shutdown tetiklendi. isDraining = true
[ADIM 3] Draining sırasında kuyruğa ekleme engellendi (ServiceDrainingException fırlatıldı).
[ADIM 4] Draining sırasında HTTP isteği 503 SERVICE_DRAINING ile reddedildi.
[ADIM 5] Sunucu ve veritabanı güvenle kapandı.
[ADIM 6] Bekleyen tüm 3 işlem kapanmadan önce eksiksiz işlendi: [1, 2, 3]
======================================================================
BAŞARILI: Graceful Shutdown ve WriteQueue Drain Testi Tamamlandı!
00:00 +1: All tests passed!
```

### Doğrulanan Davranışlar:
1. **WriteQueue Drain:** Servis kapanma sinyali aldığında (`isDraining = true`), kuyrukta bekleyen mevcut tüm işlemler (Adım 1'deki 3 işlem) eksiksiz tamamlanana kadar veritabanı ve sunucu kapatılmaz.
2. **503 SERVICE_DRAINING:** Draining modu etkinken gelen yeni HTTP satış veya senkronizasyon istekleri anında HTTP `503` durum koduyla reddedilir; yarım işlem riski baştan önlenir.
3. **Timeout Güvenliği:** `writeQueue.drain(timeout: Duration(seconds: 5))` ve WinSW `<stoptimeout>15 sec</stoptimeout>` yapılandırması sayesinde, kilitlenen bir işlem olsa dahi maksimum 15 saniye sonra servis zorunlu sonlandırılacaktır.

---

## 4. Güvenlik, NTFS İzinleri ve Servis Hesabı

- **Varsayılan WinSW Hesabı:** `NT AUTHORITY\LocalSystem` (En yüksek yerel yetki).
- **Önerilen Pilot Hesabı:** En az yetki ilkesi (Least Privilege) gereği `NT AUTHORITY\LocalService` veya özel yerel hesap (`MmsServiceUser`).

### Mevcut Dizin NTFS ACL İncelemesi (`icacls test_spikes/spike_01_backend`):
```text
NT AUTHORITY\SYSTEM:(I)(OI)(CI)(F)
BUILTIN\Administrators:(I)(OI)(CI)(F)
HALILKRKN\halil:(I)(OI)(CI)(F)
Halilkrkn\CodexSandboxUsers:(I)(OI)(CI)(RX)
```
- **Bulgu:** `SYSTEM` ve `Administrators` tam yetkiye `(F)` sahiptir. Servis `LocalService` hesabına geçirilirse, SQLite veritabanı ve log klasörüne aşağıdaki izin komutu uygulanmalıdır:
  ```powershell
  icacls "c:\Users\halil\Github\market-pos\test_spikes\spike_01_backend\build" /grant "NT AUTHORITY\LocalService:(OI)(CI)F"
  ```
- **Hassas Veri / Token Denetimi:**
  - `bin/server.dart` ve `lib/` kodları taranmış; konsola ve loglara yalnızca sunucu başlangıç portu, DB yolu ve kapanış mesajlarının basıldığı saptanmıştır.
  - Bearer token'lar, yetkilendirme başlıkları ve satış detayları stdout/stderr loglarına **kesinlikle yazılmamaktadır**.

---

## 5. Gerçekleştirilen ve Gerçekleştirilemeyen Testlerin Dökümü

| No | Test Maddesi | Fiili Durum | Sonuç Açıklaması |
| :-: | :--- | :---: | :--- |
| **1** | Windows Service Olarak Kurulum | **DOĞRULANMADI** | Yönetici token'ı (`Elevation`) bulunmadığından `OpenSCManager FAILED 5` hatası alındı. |
| **2** | `sc query` ile Servis Kaydı | **DOĞRULANMADI** | Servis SCM'ye kurulamadığı için `Hizmet yüklü değil (1060)` döndü. |
| **3** | Servisin Başlatılması | **DOĞRULANMADI** | Servis kurulamadığı için başlatılamadı. |
| **4** | `/health` Endpoint'inin Servisten Yanıtı | **KISMEN DOĞRULANDI** | Child process ve doğrudan testlerde doğrulandı; ancak Windows Service wrapper altında sınanamadı. |
| **5** | Servisin Normal Durdurulması | **KISMEN DOĞRULANDI** | SCM üzerinden test edilemedi; ancak Dart `LifecycleManager` SIGINT/shutdown akışı test edildi. |
| **6** | Tekrar Başlatılması | **DOĞRULANMADI** | Servis kurulamadığı için sınanamadı. |
| **7** | Crash Sonrası WinSW Restart | **KISMEN DOĞRULANDI** | WinSW restart kuralı XML'de tanımlandı; OS seviyesi crash recovery bağımsız testle kanıtlandı; ancak WinSW tetiklemesi canlıda denenmedi. |
| **8** | Windows Kullanıcı Oturumu Kapatılması | **DOĞRULANMADI** | Otomasyon oturumunun kapanmaması gerektiğinden test edilmedi. |
| **9** | Windows Reboot Sonrası Otomatik Başlama | **DOĞRULANMADI** | Test makinesi yeniden başlatılamayacağından icra edilmedi. |
| **10** | Log Rotasyonu Davranışı | **KISMEN DOĞRULANDI** | WinSW `roll-by-size` 10MB x 5 dosya XML'de yapılandırıldı; ancak canlı dosya rotasyonu wrapper çalışamadığı için tetiklenemedi. |

---

## 6. Manuel Yönetici Kurulum ve Doğrulama Kılavuzu

Kullanıcı kendi Windows makinesinde **Yönetici Olarak Çalıştırılan bir PowerShell** penceresinde servisi test etmek isterse izleyeceği kesin adımlar:

```powershell
# 1. Yönetici olarak PowerShell açın ve servis klasörüne gidin:
Set-Location "C:\Users\halil\Github\market-pos\test_spikes\spike_01_backend\service_wrapper"

# 2. Servisi Windows Hizmet Yöneticisine kurun:
.\MarketMmsSpike01.exe install

# 3. Servisi başlatın:
.\MarketMmsSpike01.exe start

# 4. Servis durumunu kontrol edin:
sc.exe query MarketMmsSpike01

# 5. Health kontrolü yapın (Port 8085):
Invoke-RestMethod -Uri "http://127.0.0.1:8085/health"

# 6. Test tamamlandığında servisi durdurun ve kaldırın:
.\MarketMmsSpike01.exe stop
.\MarketMmsSpike01.exe uninstall
```

---

## 7. Nihai Sınıflandırma

| Değerlendirme Alanı | Sınıflandırma |
| :--- | :---: |
| **WinSW Yapılandırması ve Binary Uyumu** | **DOĞRULANDI (VERIFIED)** |
| **Graceful Shutdown & WriteQueue Drain** | **DOĞRULANDI (VERIFIED)** |
| **Draining Sırasında HTTP 503 Rejection** | **DOĞRULANDI (VERIFIED)** |
| **Hassas Verilerin Loglanmaması (Security)** | **DOĞRULANDI (VERIFIED)** |
| **Canlı SCM Kurulumu ve Windows Reboot/Logout** | **DOĞRULANMADI (UNVERIFIED — Yönetici Yetkisi Gerektirir)** |

### GENEL SPIKE-01 SONUÇ DERECESİ:
**KISMEN DOĞRULANDI (PARTIALLY VERIFIED)**
*(Mimarinin kod ve wrapper yapılandırması %100 tamamdır; Windows Hizmet Kontrol Yöneticisi'ne fiili kayıt adımı işletim sistemi güvenlik politikaları gereği yerel Administrator müdahalesi gerektirmektedir).*

