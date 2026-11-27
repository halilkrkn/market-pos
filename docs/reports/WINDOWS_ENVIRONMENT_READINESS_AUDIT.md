# WINDOWS ENVIRONMENT READINESS AUDIT (Aşama D)

**Tarih:** 2026-11-27

**Denetim Türü:** Tamamen salt okunur Windows ana makine denetimi (hiçbir sistem kaynağı değiştirilmedi)

---

## 1. Windows Servisleri ve Süreçler

| Kontrol | Bulgular | Durum |
|---|---|---|
| **`MarketMMSService`** | `Get-Service MarketMMSService` → **Mevcut değil (`NOT_PRESENT`)** | Temiz (kurulu değil) |
| **`MarketMmsSpike01`** | `Get-Service MarketMmsSpike01` → **Mevcut değil (`NOT_PRESENT`)** | **KORUNDU / OLUŞTURULMADI** |
| **İlgili WinSW / Hub / Client Süreçleri** | Çalışan `mms_backend`, `market_pos` veya `winsw` süreci **yok** | Temiz |
| **Yönetici / Sanallaştırma Bağlamı** | Kullanıcı: `HALILKRKN\halil` (`IS_ADMIN=False`), Windows 11 Pro Build `22631`; Hyper-V `vmms` = `Running` (`Get-VM` boş), `WindowsSandbox` yok | Standart oturum |

---

## 2. `C:\ProgramData\MarketMMS` Durumu (Salt Okunur Metadata)

25 Kasım 2026 tarihli başarısız MSI denemesinden (`ExitCode 74`) kalan 11 boş klasör ve 1 işlem günlüğü dosyası tespit edilmiştir (içeriğe müdahale edilmemiştir; hassas dosya yoktur):

| Yol | Tür | Boyut | Son Yazım (UTC) | Sahip (`Owner`) | ACL Kalıtım Korumalı (`Protected`) | `Users/Everyone` ACE | ReparsePoint |
|---|---|---|---|---|---|---|---|
| `C:\ProgramData\MarketMMS` | Dizin | — | `2026-11-24T23:22:18.3252640Z` | `NT AUTHORITY\SYSTEM` | **`False`** | Evet (Kalıtım: `Users:RX,W`) | `False` |
| `bin`, `bin\broker`, `bin\lib`, `lib`, `config`, `certs`, `data`, `security`, `logs`, `backups`, `run` | 11 Dizin (boş) | `0` | `2026-11-24T23:22:18.312–.497Z` | `NT AUTHORITY\SYSTEM` | **`False`** | Evet (Kalıtım) | `False` |
| `C:\ProgramData\MarketMMS\run\installer_tx_state.json` | Dosya | `493` B | `2026-11-24T23:27:16.8317420Z` | `NT AUTHORITY\SYSTEM` | **`False`** | Evet (Kalıtım) | `False` |

**Kritik Bulgular:**
- **DB / WAL / SHM:** Yok (`0` adet `.db`, `-wal`, `-shm` dosyası).
- **Sırlar & Sertifikalar (`certs\*`, `security\*`):** Yok (`ca.crt`, `server.crt`, `server.key`, `pepper.dpapi`, `admin_secret.txt` bulunmuyor).
- **Reparse Point:** `0` adet (`False`).
- **ACL Uyarısı (Canlı Kurulum Ön Koşulu):** Mevcut `C:\ProgramData\MarketMMS` ve `logs` dizinleri 25 Kasım `icacls /reset` başarısızlığından beri **`Protected=False` ve `Users:W` kalıtımı** ile durmaktadır. Yeni MSI kurulumu (`Step 6: ApplyAcls`) bu ACL'leri `/inheritance:r` ile kapatana kadar `MmsSafeDiagnosticLogWriter` güvenlik gereği bu konuma log yazmayı fail-closed reddedecektir; güncel `setup_service_acls.ps1` ise kurulum sırasında `takeown /A /R /D Y /SKIPSL` + `/reset /T` + `/inheritance:r` ile bunu otomatik onaracaktır.

---

## 3. `C:\Program Files\MarketMMS` Durumu

| Kontrol | Bulgular |
|---|---|
| `Test-Path 'C:\Program Files\MarketMMS'` | **`False`** (25 Kasım MSI rollback `FileRemove` ile tüm ikililer kaldırılmıştır; kurulum artığı yoktur) |

---

## 4. Firewall, Portlar ve Ağ Profili

| Bileşen | Durum | Detay |
|---|---|---|
| **TCP `8085`** *(Korunan Spike portu)* | `FREE` | Dinleyen süreç yok |
| **TCP `8945`** *(Üretim Hub HTTPS)* | `FREE` | Dinleyen süreç yok |
| **UDP `8946`** *(Üretim Hub Discovery)* | `FREE` | Dinleyen süreç yok |
| **TCP `8947` / UDP `8948`** *(İzole Test Hub)* | `FREE` | Dinleyen süreç yok |
| **Firewall Kuralları (`MarketMMS*`)** | `NONE` | Mevcut `MarketMMS` kuralı yok (değiştirilmedi) |
| **Aktif Ağ Profili** | **`Wi-Fi -> Private`** | `Get-NetConnectionProfile` üzerinde `Private` doğrulandı (`LocalSubnet` firewall kurallarıyla uyumlu) |

---

## 5. TLS Durumu (`C:\ProgramData\MarketMMS\certs\`)

- **`ca.crt`:** Yok (pilot/test kurulumu öncesi üretilmemiştir; `ca.key` disk üzerinde yoktur).
- **`server.crt`:** Yok.
- **`server.key`:** Yok.
- **Sonuç:** Kurulum bu durumda çalıştırılırsa `ALLOW_DEFERRED_TLS_START=1` sayesinde servis güvenli biçimde `PENDING_TLS_PROVISIONING` (`Stopped`) olarak bırakılacaktır; HTTPS dinleyici başlatılmayacaktır.
