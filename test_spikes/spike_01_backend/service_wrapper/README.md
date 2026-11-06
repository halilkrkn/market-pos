# MARKET MMS — Windows Service Entegrasyon Kılavuzu

Bu dizin, MARKET MMS Local Master Hub (Dart + Shelf + SQLite) bağımsız arka plan servisinin Windows Service olarak kurulması, yönetilmesi ve korunması için gereken yapılandırma ve yönergeleri içerir.

---

## 1. Servis Sarmalayıcı (Wrapper) Seçenekleri Karşılaştırması

| Kriter | WinSW v2.x | WinSW v3.x | NSSM (Non-Sucking Service Manager) |
| :--- | :--- | :--- | :--- |
| **Geliştirme / Bakım Durumu** | Kararlı, bakım modunda | Aktif geliştirme, modern .NET tabanlı | 2017'den beri güncellenmiyor (terk edilmiş) |
| **.NET Runtime Bağımlılığı** | .NET Framework 4.6.1+ (Win 10/11'de yerleşik) | .NET Core / .NET 6/7/8 runtime gerektirebilir (tek dosya paketi hariç) | Bağımlılık yok (Saf C/Win32) |
| **Graceful Shutdown Desteği** | `stoptimeout` ve `SIGINT/SIGTERM` benzeri sinyal üretimi | Gelişmiş sinyal yönetimi ve timeout desteği | `GenerateConsoleCtrlEvent` (bazen force kill ile sonlanabilir) |
| **Log Rotasyonu** | Yerleşik boyuta göre (roll-by-size) rotasyon | Gelişmiş yapılandırma ve log mekanizmaları | Basit stdout/stderr yönlendirme, rotasyon kısıtlı |
| **MMS Pilotu İçin Öneri** | **ÖNERİLEN (WinSW v2.11+)** — Windows 10/11 üzerinde ek runtime kurmadan çalışır | İkincil alternatif (Boyutu daha büyük single-file paket) | Önerilmez (Güvenlik yaması ve güncellemesi yok) |

---

## 2. Kurulum ve Yönetim Komutları

Yönetici (Administrator) yetkileriyle PowerShell veya CMD üzerinden:

### A. Servisi Kurma
```powershell
# winsw.exe dosyasını spike_service.exe ile aynı dizine kopyalayın
# winsw.exe adını MarketMmsLocalHub.exe, winsw.xml adını MarketMmsLocalHub.xml yapın
.\MarketMmsLocalHub.exe install
```

### B. Servisi Başlatma / Durdurma
```powershell
.\MarketMmsLocalHub.exe start
.\MarketMmsLocalHub.exe stop
.\MarketMmsLocalHub.exe restart
```

### C. Servisi Kaldırma
```powershell
.\MarketMmsLocalHub.exe uninstall
```

---

## 3. Güvenlik, İzinler ve Güvenlik Duvarı (Firewall)

### A. Windows Servis Hesabı
- Varsayılan olarak `NT AUTHORITY\LocalSystem` geniş yetkilere sahiptir.
- En az ayrıcalık (Least Privilege) ilkesi gereği servisin `NT AUTHORITY\LocalService` veya özel bir standart yerel kullanıcı (`MmsServiceUser`) hesabıyla çalıştırılması önerilir.

### B. NTFS Erişim İzinleri (ACL)
Veritabanı dosyası ve log dizini yalnızca servis hesabı ve Windows Yöneticileri tarafından okunup yazılabilmelidir:
```powershell
# data dizinine yetki verme
icacls "C:\MarketMMS\data" /grant "NT AUTHORITY\LocalService:(OI)(CI)F" /inheritance:r
icacls "C:\MarketMMS\data" /grant "BUILTIN\Administrators:(OI)(CI)F"
```

### C. Windows Güvenlik Duvarı Kuralı (Firewall)
Mobil cihazların (Android/iOS) yerel Wi-Fi ağı üzerinden Windows Service API'ye erişebilmesi için gelen kuralı eklenmelidir:
```powershell
netsh advfirewall firewall add rule name="Market MMS Local Master Hub (Port 8080)" dir=in action=allow protocol=TCP localport=8080 profile=private
```
> **Önemli:** Ağ profilinin `Public` değil, yalnızca `Private` (Özel Yerel Ağ) olarak seçildiğinden emin olunmalıdır.

