# MARKET MMS — SPIKE-01 / Aşama S-5
# Windows Service & Host Hardening — Teknik Uygulama Planı

**Sürüm:** v2.0 (Üretim Seviyesi Windows Servis, Standart UI UAC Broker İletişimi, 12s Birleşik Drain ve FULL Durability Mimarisi)  
**Tarih:** 5 Kasım 2026  
**Durum:** TASLAK / KULLANICI ONAYI BEKLİYOR  
**Kapsam:** `test_spikes/spike_01_backend/`  
**Referans Dokümanlar:**
- [`S4_DEVICE_PAIRING_PLAN.md`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/S4_DEVICE_PAIRING_PLAN.md) (v1.6)
- [`S4_FINAL_SECURITY_AUDIT.md`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/S4_FINAL_SECURITY_AUDIT.md)
- [`S4_SECURITY_FIX_REPORT.md`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/S4_SECURITY_FIX_REPORT.md)
- [`S4_FINAL_VERIFICATION_REPORT.md`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/S4_FINAL_VERIFICATION_REPORT.md)
- [`S5_PLAN_REVISION_NOTES.md`](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/S5_PLAN_REVISION_NOTES.md) (v2.0)

---

## 1. Mevcut Durum Analizi ve S-5 Gerekçesi

### 1.1. Spike-01 Aşama S-1..S-4 Kazanımları ve Doğru Kriptografik Tanımlar
Spike-01 sürecinde backend altyapısı aşağıdaki teknik olgunluğa getirilmiştir:
1. **S-1 (API Hardening):** Shelf HTTP API, girdi sanitizasyonu, 2 MB strict body limit, CORS kısıtlaması, fail-closed rate-limit ve zarif kapanma (`WriteQueue.drain`).
2. **S-2 (Token Security):** 256-bit CSPRNG token (`mms_dt_` + Base64URL 43 karakter), cihaz başına benzersiz 128-bit CSPRNG salt, Windows DPAPI (`CryptProtectData`/`LocalMachine`) korumalı 256-bit pepper, `SHA-256(rawToken : salt : pepper)` özetleme, sabit zamanlı (`_constantTimeEquals`) karşılaştırma ve anlık cihaz iptali (`revoke`). *(Not: Cihaz belirteçleri yüksek entropili 256-bit kriptografik dizeler olduğundan PBKDF2 değil, DPAPI pepper + salt destekli SHA-256 özetleme kullanılmıştır).*
3. **S-3 (LAN TLS Security):** Yerel HTTPS sunucusu, TLS 1.3 öncelikli ve güçlü AEAD paketleriyle TLS 1.2 desteği, çift katmanlı yerel PKI (10 yıllık RSA 2048-bit Root CA ve 1 yıllık SAN yaprak sunucu sertifikası), Root CA fingerprint sabitleme (pinning) ve MITM koruması.
4. **S-4 (Secure Device Pairing):** ECDSA P-256 imza doğrulama, katı ASN.1 DER ayrıştırma, Low-S zorunluluğu, deterministik 6/7 alanlı binary framing, token-bound ACK ve Windows TPM 2.0 (`ncrypt.dll`) donanımsal imza çıktısı doğrulaması.

### 1.2. Kapatılması Gereken Güvenlik Açıkları (FINDING-5 Mirası)
`S4_FINAL_VERIFICATION_REPORT.md` denetiminde tespit edilen ve Aşama S-5'e ertelenen kritik güvenlik sınırları:
1. **WMI ile CLI Parametresi İfşası:** Admin Secret önceki prototiplerde `--admin-secret=` argümanından veya `ADMIN_SECRET` ortam değişkeninden okunmaktaydı. Windows'ta aynı makinede çalışan herhangi bir standart kullanıcı süreci, `Get-CimInstance Win32_Process` (WMI) sorgusu ile sürecin `CommandLine` bilgisini kolayca okuyabilmektedir.
2. **TCP Loopback Güvenlik Sınırı Eksikliği:** TCP portu (`127.0.0.1:8085`), makinedeki tüm yerel süreçlerin soket açabildiği paylaşımlı bir alandır. IP loopback kontrolü, yetkisiz bir yerel süreç ile yetkili Flutter UI'ı birbirinden ayıramaz.
3. **Dosya İzinleri ve Veritabanı Korunmasızlığı:** `market_master.db`, SQLite WAL/SHM dosyaları, `server.key` ve `pepper.dpapi` standart Windows izinleriyle işletildiğinde kötü amaçlı bir yerel kullanıcı bu dosyaları doğrudan kopyalayabilir veya değiştirebilir.
4. **İşletim Sistemi Seviyesinde Yaşam Döngüsü Eksikliği:** Backend bir Windows Servisi olmadığında konsol oturumu kapandığında süreç sonlanır, elektrik kesintisi/reboot sonrası otomatik ayağa kalkamaz ve çökmelerde (crash) işletim sistemi düzeyinde otomatik kurtarma mekanizması bulunmaz.

---

## 2. Windows Kullanıcı, Servis SID ve Süreç Modeli

### 2.1. Windows Güvenlik İlkeleri (Principals) ve Service SID Mimarisi
NTFS ACL ve Win32 DACL kuralları oluşturulurken standart kullanıcı hesapları ile servis kimlikleri birbirinden kesin olarak ayrılmalıdır:
- **`Everyone` (`S-1-1-0`):** Yerel ve ağdaki tüm kullanıcıları ve servisleri kapsar.
- **`BUILTIN\Users` (`S-1-5-32-545`):** Makinedeki yerel standart kullanıcı hesaplarını temsil eder.
- **`BUILTIN\Administrators` (`S-1-5-32-544`):** Makinenin tam yönetim yetkisine sahip yerel yönetici grubudur.
- **`NT AUTHORITY\SYSTEM` (`S-1-5-18`):** İşletim sistemi çekirdeği ve yerleşik servis yürütme hesabıdır.
- **`NT AUTHORITY\LocalService` (`S-1-5-19`):** Ağda anonim, yerel makinede düşük haklara sahip paylaşımlı yerleşik servis hesabıdır.
- **`NT SERVICE\MarketMMSService` (Özel Service SID):** Windows SCM tarafından servise özel olarak atanan tekil güvenlik tanımlayıcısıdır (`SERVICE_SID_TYPE_UNRESTRICTED`).

> [!CRITICAL]
> **LocalService Ayrıştırılamazlığı ve Service SID Çözümü:**
> Standart `NT AUTHORITY\LocalService` hesabı Windows üzerindeki pek çok yerleşik servis tarafından ortaklaşa kullanılır. Yalnızca `LocalService` kimliğine güvenmek, aynı makinede çalışan başka bir servisin Market MMS Named Pipe'ına erişmesine zemin hazırlar.
> Bu sorunu çözmek için `MarketMMSService` servisi Windows SCM üzerinde `SERVICE_SID_TYPE_UNRESTRICTED` bayrağı ile yapılandırılır. Böylece Windows çekirdeği, yalnızca bu servise ve alt süreçlerine ait olan benzersiz bir SID (`NT SERVICE\MarketMMSService`, format: `S-1-5-80-X-Y-Z...`) üretir ve süreç token'ına ekler. Named Pipe DACL ve dosya izinlerinde genel LocalService yerine **bu benzersiz Service SID** kullanılır!

### 2.2. Service SID Etkinleşme Yaşam Döngüsü ve Kurulum Sırası
Microsoft dokümantasyonuna göre `sc.exe sidtype` ayarı çalışan bir servisin token'ını anında güncellemez; ayar yalnızca **servisin bir sonraki başlatılışında (SCM process creation)** yürürlüğe girer.

**v2.0 Doğrulanmış Kurulum Sırası:**
1. Servis WinSW v2.12.0 aracılığıyla SCM'ye kaydedilir: `mms_service.exe install`.
2. Service SID tipi atanır: `sc.exe sidtype MarketMMSService unrestricted`.
3. Yapılandırma teyit edilir: `sc.exe qsidtype MarketMMSService` çıktısında `SERVICE_SID_TYPE: UNRESTRICTED` doğrulanır.
4. `NT SERVICE\MarketMMSService` SID dizesi (`S-1-5-80-...`) çözümlenir.
5. `setup_service_acls.ps1` betiği bu çözümlenen Service SID ile çalıştırılarak NTFS izinleri tahsis edilir.
6. Servis başlatılır: `sc.exe start MarketMMSService`.

---

## 3. UAC ve Yönetim UI Mimarisi: Model B (Dual-Process)

v1.0'daki Model A (tüm UI'nin yönetici olarak çalışması) mimariden **kesin olarak kaldırılmıştır**. Yalnızca **Model B (Dual-Process / UAC Broker Mimarisi)** kullanılacaktır.

```
+----------------------------------------------------------------------------------------------------+
|                                      KULLANICI OTURUMU (Desktop)                                   |
|                                                                                                    |
|  +--------------------------------------------------+                                              |
|  |             ANA FLUTTER WINDOWS UI               |                                              |
|  |       Hesap: Standart Kullanıcı (Medium IL)      |                                              |
|  |                                                  |                                              |
|  |   - Kasiyer Satış İşlemleri                      |                                              |
|  |   - Barkod Okuma, Sepet, Fiş Basımı              |                                              |
|  |   - Yerel Drift SQLite DB (UI State)             |                                              |
|  +--------------------------------------------------+                                              |
|            │                                 │ (Yönetici İşlemi Gerektiğinde)                      |
|            │                                 │ 1. Response Pipe Aç: \\.\pipe\MarketMMS_BrokerResp_ |
|            │                                 │ 2. ShellExecuteEx("runas", "bin\broker\mms_broker") |
|            │                                 v                                                     |
|            │               +------------------------------------+                                  |
|            │               |       UAC ELEVATION PROMPT         |                                  |
|            │               |  "Bu uygulamanın cihazınızda       |                                  |
|            │               |   değişiklik yapmasına izin verin" |                                  |
|            │               +------------------------------------+                                  |
|            │                                 │ (İşletme Sahibi Onayı - Self veya OTS)              |
|            │                                 v                                                     |
|            │               +------------------------------------+                                  |
|            │               |      UAC ADMIN BROKER EXECUTABLE   |                                  |
|            │               |  (bin\broker\mms_admin_broker.exe) |                                  |
|            │               |     Hesap: Elevated Admin (High IL)|                                  |
|            │               +------------------------------------+                                  |
|            │ (HTTPS)                         │                                                     |
|            │ Device Token                    │ 1. Backend IPC: \\.\pipe\MarketMMS_Admin_IPC        |
|            │ mms_dt_*                        │ 2. Sonucu Response Pipe ile UI'a Gönder             |
|            v                                 v                                                     |
|   https://127.0.0.1:8085           \\.\pipe\MarketMMS_Admin_IPC                                    |
|            │                                 ▲                                                     |
+------------│---------------------------------│-----------------------------------------------------+
             │                                 │ (SCM Stop Çağrısı: Service SID Doğrulamalı)         |
             │                                 │ Rol: ROLE_SERVICE_STOP                              |
             │               +------------------------------------+                                  |
             │               |      WinSW STOP HELPER             |                                  |
             │               |       (bin\mms_stop_helper.exe)    |                                  |
             │               |   SID: NT SERVICE\MarketMMSService |                                  |
             │               +------------------------------------+                                  |
             │                                 │                                                     |
             ▼                                 ▼                                                     |
+----------------------------------------------------------------------------------------------------+
|               DART AOT BACKEND ENGINE (Hesap: LocalService + NT SERVICE\MarketMMSService)          |
+----------------------------------------------------------------------------------------------------+
```

### 3.1. Kasiyer ve Günlük Satış Deneyimi
- Kasiyer oturumu standart Windows kullanıcısıdır (`BUILTIN\Users`).
- Ana Flutter UI çift tıklandığında UAC uyarısı vermeden doğrudan standart kullanıcı yetkisiyle açılır (Medium Integrity Level).
- Satış işlemleri, fiş kesme, barkod okuma ve stok sorgulama işlemleri **Named Pipe üzerinden değil, yerel HTTPS API (`https://127.0.0.1:8085/api/v1/sales`) üzerinden cihaz token'ı (`mms_dt_*`) ile** yürütülür.
- **Kasiyerin günlük çalışmasında hiçbir şekilde UAC onayı veya Administrator şifresi gerekmez.**

### 3.2. Response Pipe Mimarisi ve Normal (Medium IL) UI Erişimi (F1 Analiz ve Tasarımı)

> [!CRITICAL]
> **F1 Bulgusu: `D:P(A;;GA;;;SY)(A;;0x00120083;;;BA)` DACL'ının Normal UI İle Çelişkisi ve Düzeltmesi:**
> Eğer Response Pipe DACL'ı yalnızca `SYSTEM` (`SY`) ve `BUILTIN\Administrators` (`BA`) ile sınırlandırılırsa, **yükseltilmemiş standart kullanıcı (Medium Integrity Level) olarak çalışan Flutter UI süreci kendi açtığı pipe'ı bile yönetemez veya OTS (Over-the-Shoulder) UAC senaryosunda broker yanıtını okuyamaz!**
> Standart kullanıcının token'ında `BUILTIN\Administrators` SID'si bulunmaz. Bu nedenle DACL, normal UI'nin kullanıcısını (`CURRENT_USER_SID`) açıkça içermek zorundadır.

#### 3.2.1. Pipe Sunucusu ve İstemcisi İzin Ayrımı
1. **Pipe Sunucusu (Normal Flutter UI):**
   - Normal UI süreci `CreateNamedPipeW` çağrısını kendi standart kullanıcı token'ı altında yapar.
   - Nesnenin sahibi otomatik olarak `CURRENT_USER_SID` olur.
   - Normal UI, pipe üzerinde `FILE_FLAG_FIRST_PIPE_INSTANCE | FILE_FLAG_OVERLAPPED | PIPE_REJECT_REMOTE_CLIENTS` bayraklarını kullanır.
2. **Pipe İstemcisi (Elevated Admin Broker):**
   - Broker, `ShellExecuteExW` ile UAC `runas` fiili üzerinden High Integrity Level ile başlatılır.
   - Broker, pipe'a `CreateFileW` ile bağlanır.
   - İstemci `dwDesiredAccess = (FILE_READ_DATA | FILE_WRITE_DATA | SYNCHRONIZE)` (`0x00100003`) talep eder.
3. **v2.0 Doğrulanmış Response Pipe SDDL DACL:**
   ```
   D:P(A;;0x12019b;;;<CURRENT_USER_SID>)(A;;0x12019b;;;BA)(A;;GA;;;SY)
   ```
   - **`<CURRENT_USER_SID>`:** Normal UI sürecini çalıştıran standart kullanıcıya okuma/yazma/senkronizasyon izni verir (`0x0012019b`).
   - **`BA` (`BUILTIN\Administrators`):** UAC ile yetkisi yükseltilen Admin Broker'a okuma/yazma/senkronizasyon izni verir (`0x0012019b`).
   - **`SY` (`NT AUTHORITY\SYSTEM`):** İşletim sistemi çekirdeğine tam denetim verir.
   - **`P` (Protected DACL):** Üst dizinlerden veya varsayılan nesnelerden izin kalıtımını kesin olarak engeller.
   - **`0x0004` (`FILE_CREATE_PIPE_INSTANCE`) Kesinlikle Yoktur:** Ne normal kullanıcıya ne de broker'a ikinci bir sunucu pipe açma yetkisi verilmez!

#### 3.2.2. Temel Güvenlik Prensibi: DACL Süreç Kimliğini Doğrulayamaz!
> [!IMPORTANT]
> **Windows Güvenlik Mimarisi Sınırı:**  
> Windows DACL yalnızca güvenlik tanımlayıcılarını (Token SID: Kullanıcı ve Gruplar) denetler; **süreç kimliğini (PID), çalıştırılabilir dosya yolunu, ikili hash değerini veya Integrity Level seviyesini denetleyemez!**  
> Bu nedenle DACL içine `<CURRENT_USER_SID>` eklendiğinde, aynı kullanıcı oturumunda çalışan **herhangi bir başka Medium Integrity süreç** de teorik olarak bu pipe'a `CreateFileW` ile bağlanma hakkına sahip olur.

#### 3.2.3. Aynı Oturumdaki Diğer Süreçlerin DoS / Ele Geçirme Riskine Karşı 5 Katmanlı Savunma
Market MMS, DACL'ın süreç doğrulayamama açığını şu 5 mekanizma ile tamamen kapatır:

1. **Kriptografik 128-bit CSPRNG Pipe Adı:**
   Pipe adı `\\.\pipe\MarketMMS_BrokerResponse_<UI_PID>_<UUIDv4>` formatındadır. 128 bitlik kriptografik rastgelelik ($1/2^{128}$) sayesinde oturumdaki yetkisiz süreçler pipe adını tahmin edemez. Windows'ta standart kullanıcılar diğer süreçlerin adlandırılmış pipe listesini dinamik olarak tarayamaz.
2. **`FILE_FLAG_FIRST_PIPE_INSTANCE` (Pipe Squatting Engeli):**
   Normal UI pipe'ı oluştururken bu bayrağı zorunlu kılar. Eğer kötü amaçlı bir süreç önceden bu isimde bir pipe açmışsa `CreateNamedPipeW` anında başarısız olur (`ERROR_ACCESS_DENIED` / `ERROR_PIPE_BUSY`). UI sahte pipe'a veri yazmaz.
3. **Çekirdek Düzeyinde PID Doğrulaması (`GetNamedPipeClientProcessId`):**
   Flutter UI, broker'ı `ShellExecuteExW` fonksiyonuna `SEE_MASK_NOCLOSEPROCESS` bayrağı vererek başlatır ve işletim sisteminden meşru broker'ın süreç tanıtıcısını (`pExecInfo.hProcess`) alır.
   `expectedBrokerPid = GetProcessId(pExecInfo.hProcess);`
   İstemci bağlandığı an UI `GetNamedPipeClientProcessId(hPipe, &clientPid)` çağırır.
   - **PID Eşleşmezse (`clientPid != expectedBrokerPid`):** UI anında `DisconnectNamedPipe(hPipe)` çağırır! Hiçbir veri okunmaz, hiçbir veri yazılmaz. Sahte istemci düşürülür. UI güvenlik olayı loglar ve yeniden dinlemeye geçer (re-listen bütçesi: azami 3 deneme, toplam 5.0 sn).
4. **`hProcess` Süreç Yaşam Döngüsü ve Fail-Closed Davranış:**
   `hProcess`, yanıt alınıp kriptografik olarak doğrulanana kadar kapatılmaz.
   - Eğer `ShellExecuteEx` başarısız olursa (`NULL` veya `INVALID_HANDLE_VALUE`), UI anında fail-closed davranır ve pipe'ı kapatır.
   - Broker beklenmedik biçimde çökerse (`WaitForSingleObject(hProcess, 0) == WAIT_OBJECT_0`), UI erken çıkışı tespit eder ve beklemeden işlemi iptal eder.
5. **256-bit CSPRNG Nonce ve Oturum Korelasyonu:**
   Broker komut satırına gizli bir oturum nonce'ı aktarılır:
   `mms_admin_broker.exe --action=approve --session-id=<id> --response-pipe=\\.\pipe\MarketMMS_BrokerResponse_<UUID> --nonce=<256-bit-hex> --request-id=<req_id>`
   - Windows Mandatory Integrity Control (MIC) uyarınca, Medium Integrity süreçler High Integrity bir sürecin belleğini (`VirtualAllocEx`/`ReadProcessMemory`) okuyamaz veya `PROCESS_VM_READ` tutamacı açamaz.
   - Broker'ın döneceği yanıt JSON-RPC mesajında `{"nonce": "<256-bit-hex>", "request_id": "<req_id>", "action": "approve", "token": "mms_dt_..."}` alanları birebir eşleşmek zorundadır. Nonce eşleşmezse yanıt çöpe atılır.

#### 3.2.4. UAC Hata ve Özel Durum Yönetimi
- **UAC İptali (Kullanıcı "Hayır" Butonuna Basarsa):**
  `ShellExecuteExW` çağrısı `SE_ERR_ACCESSDENIED` (`ERROR_CANCELLED`, Win32 Hata Kodu 1223) döndürür. UI bunu anında yakalar; pipe dinlemesini beklemeden derhal iptal eder, pipe tutamacını kapatır ve kasiyere *"Yönetici yetkilendirmesi kullanıcı tarafından iptal edildi"* mesajı gösterir (Sıfır kilitlenme, sıfır gecikme).
- **Broker Çökmesi:**
  Broker elevated başlatıldıktan sonra çökerse, `hProcess` sinyallenir. UI 10 saniyelik zaman aşımını beklemeden `hProcess` çıkış kodunu (`GetExitCodeProcess`) okur ve kullanıcıya hata raporlar.
- **Zaman Aşımı:**
  Broker 5.0 saniye içinde pipe'a bağlanmazsa veya bağlandıktan sonra 3.0 saniye içinde yanıt göndermezse UI bağlantıyı keser, `TerminateProcess(hProcess)` ile sarkan broker'ı temizler ve işlemi iptal eder.

#### 3.2.5. Alternatif IPC Mekanizmalarının Değerlendirilmesi
- **Anonymous Pipe (`CreatePipe`):** UAC `runas` mekanizmasında çağrı Secondary Logon (`appinfo.dll`) üzerinden işletim sistemine devredilir. Medium IL bir sürecin tutamaçları (handle inheritance) High IL alt sürece aktarılamaz (`ERROR_NO_TOKEN` / `ERROR_ACCESS_DENIED`). Bu nedenle Anonymous Pipe UAC sınırını geçemez.
- **Paylaşımlı Bellek (Shared Memory / MMF + Event):** Hem bellek nesnesi hem senkronizasyon olayları için ayrı DACL gerekir; aynı kullanıcı oturumundaki süreç izolasyonu sorunu aynen devam eder ve `GetNamedPipeClientProcessId` benzeri çekirdek PID doğrulama mekanizması bulunmaz.
- **Loopback TCP Soketi:** Makinedeki tüm yerel kullanıcılar ve yazılımlar tarafından dinlenebilir/taranabilir; süreç doğrulaması işletim sistemi düzeyinde doğrudan yapılamaz.
- **Sonuç:** Sayısal DACL'lı, rastgele UUID'li, `GetNamedPipeClientProcessId` denetimli ve Nonce korumalı **Named Pipe**, Windows üzerinde UAC sınırını geçen en güvenli ve standart IPC mekanizmasıdır.

---

## 4. Named Pipe Güvenliği, Doğrulama Sırası ve Sayısal Maskeli DACL

### 4.1. Kimlik Doğrulama Akış Sırası (F1 Düzeltmesi)
Standart `ConnectNamedPipe` akışında doğrudan `ImpersonateNamedPipeClient` çağrılması, istemci veri göndermeden önce impersonation yapılmasına ve yetki kargaşasına yol açabilir. 

**v2.0 Bağlayıcı Doğrulama Sırası:**
```
[İstemci Bağlandı: ConnectNamedPipe]
                 │
                 ▼
[Adım 1: Sınırlı İlk Mesaj Okuma: ReadFile (Maksimum 64 KB, 5.0s Timeout)]
                 │
                 ├── (Mesaj Okunamadı / Timeout / ERROR_MORE_DATA > 64KB)
                 │       └──> Fail-Closed: DisconnectNamedPipe + Pipe Kapat
                 │
                 ▼
[Adım 2: Native C İstemci Kimlik Doğrulama: AuthenticateNamedPipeClient]
                 │
                 ├── (ImpersonateNamedPipeClient Çağrısı)
                 │       │
                 │       ├── (OpenThreadToken ile İstemci Token'ı Alınır)
                 │       │
                 │       ├── (TokenGroups İçinde Service SID Denetimi Yapılır)
                 │       │       └──> Eşleşirse: client_role = ROLE_SERVICE_STOP
                 │       │
                 │       ├── (CheckTokenMembership ile BUILTIN\Administrators Denetimi)
                 │       │       └──> Eşleşirse: client_role = ROLE_ADMIN_BROKER
                 │       │
                 │       └── (RevertToSelf Çağrısı — Tek OS Thread Garantisi)
                 │               └──> Başarısız Olursa: ExitProcess(0xC0000005) [Fail-Closed]
                 │
                 ├── (Yetkisiz İstemci / Eşleşme Yok)
                 │       └──> client_role = ROLE_UNAUTHORIZED -> DisconnectNamedPipe
                 │
                 ▼
[Adım 3: JSON-RPC Ayrıştırma ve Rol Bazlı Yetkilendirme]
                 │
                 ├── ROLE_SERVICE_STOP: Yalnızca "system.shutdown" metodunu çalıştırabilir
                 ├── ROLE_ADMIN_BROKER: Yalnızca "pairing.approve", "pairing.reject", "device.revoke", "admin.backup" çalıştırabilir
                 │
                 ▼
[Adım 4: İşlem İcrası ve Yanıtın Yazılması (WriteFile)]
```

### 4.2. Service SID ve Native C Doğrulama Fonksiyonu
Aşağıdaki C kodu `pipe_auth_native.dll` içine derlenir ve Dart FFI tarafından çağrılır:

```c
// pipe_auth_native.c — Native C FFI Doğrulama Katmanı (v2.0)
#include <windows.h>
#include <sddl.h>

#define ROLE_UNAUTHORIZED 0
#define ROLE_ADMIN_BROKER 1
#define ROLE_SERVICE_STOP 2

__declspec(dllexport) DWORD AuthenticateNamedPipeClient(
    HANDLE hPipe,
    const wchar_t* expectedServiceSidStr,
    DWORD* outClientPid
) {
    if (hPipe == NULL || hPipe == INVALID_HANDLE_VALUE) return ROLE_UNAUTHORIZED;

    // 1. İstemci PID'sini Çekirdekten Al
    ULONG clientPid = 0;
    if (!GetNamedPipeClientProcessId(hPipe, &clientPid)) {
        return ROLE_UNAUTHORIZED;
    }
    if (outClientPid) *outClientPid = clientPid;

    // 2. İstemci Kimliğine Bürün (Impersonate)
    if (!ImpersonateNamedPipeClient(hPipe)) {
        return ROLE_UNAUTHORIZED;
    }

    DWORD detectedRole = ROLE_UNAUTHORIZED;
    HANDLE hToken = NULL;
    PSID pExpectedServiceSid = NULL;

    do {
        // İstemci thread token'ını aç
        if (!OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &hToken)) {
            break;
        }

        // A. Service SID Denetimi
        if (expectedServiceSidStr && ConvertStringSidToSidW(expectedServiceSidStr, &pExpectedServiceSid)) {
            DWORD dwLength = 0;
            GetTokenInformation(hToken, TokenGroups, NULL, 0, &dwLength);
            if (GetLastError() == ERROR_INSUFFICIENT_BUFFER && dwLength > 0) {
                PTOKEN_GROUPS pGroups = (PTOKEN_GROUPS)LocalAlloc(LPTR, dwLength);
                if (pGroups) {
                    if (GetTokenInformation(hToken, TokenGroups, pGroups, dwLength, &dwLength)) {
                        for (DWORD i = 0; i < pGroups->GroupCount; i++) {
                            if (EqualSid(pExpectedServiceSid, pGroups->Groups[i].Sid)) {
                                DWORD attrs = pGroups->Groups[i].Attributes;
                                if ((attrs & SE_GROUP_ENABLED) && !(attrs & SE_GROUP_USE_FOR_DENY_ONLY)) {
                                    detectedRole = ROLE_SERVICE_STOP;
                                    break;
                                }
                            }
                        }
                    }
                    LocalFree(pGroups);
                }
            }
        }
        if (detectedRole == ROLE_SERVICE_STOP) break;

        // B. Elevated Administrator Denetimi (CheckTokenMembership)
        PSID pAdminSid = NULL;
        SID_IDENTIFIER_AUTHORITY NtAuthority = SECURITY_NT_AUTHORITY;
        if (AllocateAndInitializeSid(&NtAuthority, 2, SECURITY_BUILTIN_DOMAIN_RID, DOMAIN_ALIAS_RID_ADMINS,
                                     0, 0, 0, 0, 0, 0, &pAdminSid)) {
            BOOL isMember = FALSE;
            // CheckTokenMembership hem grup üyeliğini hem de token'ın elevated/deny-only olmadığını teyit eder
            if (CheckTokenMembership(NULL, pAdminSid, &isMember) && isMember) {
                detectedRole = ROLE_ADMIN_BROKER;
            }
            FreeSid(pAdminSid);
        }

    } while (0);

    // Temizlik
    if (pExpectedServiceSid) LocalFree(pExpectedServiceSid);
    if (hToken) CloseHandle(hToken);

    // 3. Kimlikten Çık (RevertToSelf) — Fail-Closed
    if (!RevertToSelf()) {
        // Çekirdek impersonation'ı geri alamazsa yetki sızıntısını önlemek için süreci acil sonlandır!
        ExitProcess(0xC0000005);
    }

    return detectedRole;
}
```

### 4.3. Named Pipe Parametreleri ve Sayısal Maskeli Minimum DACL (F1 & F5)
> [!CRITICAL]
> **F1 & F5: GENERIC_WRITE Yasağı ve Sayısal Erişim Maskesi (0x0012019b):**
> Windows Named Pipe güvenliğinde `GENERIC_WRITE` hakkı `FILE_CREATE_PIPE_INSTANCE` (0x0004) hakkını içerir. SDDL dizesinde `FW` veya `GRGW` kullanılması, istemciye sunucu pipe instance'ı açma yetkisi verir.
> Bu nedenle SDDL'de harf kısaltmaları (`FW`) yerine kesin sayısal erişim maskesi (`0x0012019b`) kullanılır:
> - `FILE_READ_DATA`: 0x00000001
> - `FILE_WRITE_DATA`: 0x00000002
> - `FILE_READ_EA`: 0x00000008
> - `FILE_WRITE_EA`: 0x00000010
> - `FILE_READ_ATTRIBUTES`: 0x00000080
> - `FILE_WRITE_ATTRIBUTES`: 0x00000100
> - `READ_CONTROL`: 0x00020000
> - `SYNCHRONIZE`: 0x00100000
> **Toplam Maske:** `0x0012019b` (0x0004 `FILE_CREATE_PIPE_INSTANCE` kesinlikle 0'dır!).

Pipe `CreateNamedPipeW` ile şu katı parametrelerle oluşturulur:
- **`dwOpenMode`:** `PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED | FILE_FLAG_FIRST_PIPE_INSTANCE`
- **`dwPipeMode`:** `PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS`
- **`nMaxInstances`:** `1`
- **SDDL DACL (Backend Yönetim IPC):**
  ```
  D:P(A;;0x12019b;;;BA)(A;;0x12019b;;;<SERVICE_SID>)(A;;GA;;;SY)
  ```
- **Güvenlik Etkisi ve Sunucu/İstemci Ayrımı:**
  - Sunucu süreci (Backend) pipe nesnesini oluştururken çekirdekten `FILE_CREATE_PIPE_INSTANCE` (0x0004) yetkisi alır.
  - İstemciler (Admin Broker veya Stop Helper) `CreateFileW` çağrısında `GENERIC_WRITE` talep edemez; açıkça `dwDesiredAccess = (FILE_READ_DATA | FILE_WRITE_DATA | SYNCHRONIZE)` (`0x00100003`) talep eder.
  - İstemcinin token'ına `0x0012019b` tahsis edildiği için bağlantı başarılı olur. Ancak istemci `CreateNamedPipeW` çağırarak ikinci bir sunucu pipe instance'ı açmaya kalkışırsa, `0x0004` hakkı bulunmadığı için çekirdek çağrıyı anında **`ERROR_ACCESS_DENIED` (5)** ile reddeder!

---

## 5. Win32 FFI ve Asenkron OVERLAPPED I/O Tasarımı

Win32 bloklayıcı `ConnectNamedPipe` veya `ReadFile` çağrılarının Dart ana Isolate event loop'unu dondurmasını (UI ve HTTP isteklerinin askıya alınmasını) engellemek için **Worker Isolate + Win32 OVERLAPPED I/O** kullanılır:

```dart
// Native FFI Bağlantısı ve Worker Isolate Mimarisi
void _namedPipeWorkerIsolate(SendPort sendPort) {
  // 1. Pipe oluştur
  final hPipe = win32.CreateNamedPipeW(...);
  final hEvent = win32.CreateEventW(nullptr, TRUE, FALSE, nullptr);
  
  while (_isRunning) {
    final overlapped = calloc<OVERLAPPED>();
    overlapped.ref.hEvent = hEvent;
    
    // Asenkron Bağlantı Bekleme
    final connected = win32.ConnectNamedPipe(hPipe, overlapped);
    if (!connected) {
      final err = win32.GetLastError();
      if (err == ERROR_IO_PENDING) {
        // Event döngüsünü tıkamadan bekle
        win32.WaitForSingleObject(hEvent, 5000);
      } else if (err == ERROR_PIPE_CONNECTED) {
        // İstemci ConnectNamedPipe'tan önce bağlandı — normal durum
      }
    }
    
    // Mesaj Oku (Maksimum 64 KB)
    // Doğrula (AuthenticateNamedPipeClient)
    // Yanıt Gönder ve Bağlantıyı Kes (DisconnectNamedPipe)
  }
}
```

---

## 6. Graceful Shutdown ve 12 Saniyelik Birleşik Draining Mimarisi (F2 Tasarımı)

### 6.1. 12 Saniyelik Birleşik Drain Protokolü ve Veritabanı Yaşam Döngüsü (F2)

> [!CRITICAL]
> **F2: Drain Başarısı vs Drain Timeout Kesin Davranış Kuralları:**
> 1. **Tüm Yazma İşlemlerinin WriteQueue Kapsamında Olması:**
>    Market MMS mimarisinde HTTP API satışları, Named Pipe üzerinden gelen eşleştirme onayları / iptalleri, audit logları ve arka plan senkronizasyon yazmaları **istisnasız tekil `WriteQueue` üzerinden** yürütülür. Hiçbir bileşen `WriteQueue` dışından doğrudan SQLite bağlantısına yazma yapamaz.
> 2. **`HttpServer.close(force: false)` vs `force: true` Davranışı:**
>    - `force: false`: Dinleyici TCP soketini kapatır, yeni bağlantı kabul etmez; ancak işletim sistemi soket kuyruğunda kabul edilmiş aktif HTTP isteklerinin yanıtlarını tamamlayıp göndermesini bekler.
>    - `force: true`: Aktif TCP soketlerini derhal keser (RST/FIN), istemciye bağlantı hatası fırlatır.
> 3. **Drain Başarılıysa (<= 12.0s):**
>    - Kabul edilmiş satışlar WriteQueue'ya teslim edilir ve diske commit edilir.
>    - `HttpServer.close(force: false)` tamamlanır.
>    - Backend `PRAGMA wal_checkpoint(TRUNCATE);` komutunu işletir. Aktif okuyucular yoksa WAL dosyası sıfırlanarak ana veritabanına aktarılır.
>    - `database.close()` temiz bir şekilde yürütülür.
>    - Süreç `exit(0)` ile başarıyla sonlanır.
> 4. **Drain Zaman Aşımına Uğrarsa (Timeout > 12.0s):**
>    - **KESİN KURAL:** Aktif bir yazma işlemi sürerken veya kuyruk boşalmamışken **ASLA `PRAGMA wal_checkpoint` ÇALIŞTIRILMAZ!** Checkpoint çağrısı kilitlenmeye veya tutarsız sayfa aktarımına yol açabilir.
>    - **KESİN KURAL:** Normal `database.close()` çağrısı yapılmaz; veritabanı bağlantısı zorla kapatılarak uncommitted rollback tetiklenmez.
>    - **WAL DOSYASI KORUNUR:** Diskteki `market_master.db-wal` dosyası kesinlikle silinmez, üzerine yazılmaz veya bozulmaz.
>    - Kalan HTTP soketleri `HttpServer.close(force: true)` ile zorla düşürülür.
>    - Backend Windows Event Log'a kritik uyarı (Event ID 4005: `ERR_SHUTDOWN_DRAIN_TIMEOUT`) yazar.
>    - Süreç derhal kontrollü sonlandırma koduyla kapatılır: `exit(101)`.
>    - **Sonraki Açılışta Otomatik Crash Recovery:** Servis yeniden başladığında SQLite motoru `sqlite3_open_v2` çağrısında diskteki `-wal` dosyasını tespit eder. WAL içindeki tüm geçerli ve commit edilmiş transaction'lar ana veritabanına otomatik aktarılır (replay); yarım kalanlar geri alınır. **Veri kaybı kesinlikle sıfırdır!**

### 6.2. Senkron Admission Gate Uygulaması
```dart
// Atomik İstek Kabul Protokolü (Tekil Isolate Event Döngüsü)
class AdmissionGate {
  bool _isDraining = false;
  int _inFlightCount = 0;
  final Completer<void> _inFlightDrainCompleter = Completer<void>();

  // Senkron kabul denetimi — ASYNC GAP / AWAIT KESİNLİKLE YOKTUR!
  bool tryAcquireAdmission() {
    if (_isDraining) return false;
    _inFlightCount++;
    return true;
  }

  void releaseAdmission() {
    _inFlightCount--;
    if (_isDraining && _inFlightCount == 0) {
      if (!_inFlightDrainCompleter.isCompleted) {
        _inFlightDrainCompleter.complete();
      }
    }
  }

  // Shutdown komutu geldiğinde senkron olarak kapıyı kapatır
  void closeGate() {
    _isDraining = true;
    if (_inFlightCount == 0) {
      if (!_inFlightDrainCompleter.isCompleted) {
        _inFlightDrainCompleter.complete();
      }
    }
  }

  Future<void> waitForInFlightDrain() => _inFlightDrainCompleter.future;
}
```

### 6.3. Tekil Toplam Shutdown Deadline: 25.0 Saniye

$$\text{SCM / WinSW Timeout (25.0s)} > \text{Stop Helper Timeout (20.0s)} > \text{Backend Bütçesi (18.0s)} > \text{Birleşik Drain (12.0s)}$$

```
0.0s             2.0s                  8.0s              12.0s             16.0s      18.0s           20.0s             25.0s
├────────────────┼─────────────────────┼─────────────────┼─────────────────┼──────────┤───────────────┼─────────────────┤
│ Kapı Kapat     │ In-Flight Satış     │ WriteQueue      │ Drain Bitti     │ Temiz DB │ Stop Helper   │ WinSW           │
│ 503 Döner      │ HTTP close(force:F) │ Drain           │ Checkpoint      │ Kapanış  │ Timeout (20s) │ Terminate (25s) │
│                │                     │ (Toplam 12.0s)  │ (Veya Exit 101) │ Exit(0)  │               │                 │
└────────────────┴─────────────────────┴─────────────────┴─────────────────┴──────────┴───────────────┴─────────────────┘
```

---

## 7. HTTP Admin Endpoint Envanteri ve Kalıcı Tasfiyesi

Spike-01 Aşama S-4 ve öncesinden kalan HTTP tabanlı yönetim uç noktaları Shelf HTTP sunucusundan tamamen tasfiye edilmiştir. Bu rotalara gelecek istekler doğrudan **`404 Not Found`** veya **`403 Forbidden` (`ERR_ADMIN_IPC_ONLY`)** ile reddedilir:

1. `/api/v1/pairing/approve` -> Kaldırıldı. Artık Named Pipe JSON-RPC `pairing.approve` üzerinden çalışır.
2. `/api/v1/pairing/reject` -> Kaldırıldı. Artık Named Pipe JSON-RPC `pairing.reject` üzerinden çalışır.
3. `/api/v1/devices/revoke` -> Kaldırıldı. Artık Named Pipe JSON-RPC `device.revoke` üzerinden çalışır.
4. `/admin/backup` -> Kaldırıldı. Artık Named Pipe JSON-RPC `admin.backup` üzerinden çalışır.
5. `/admin/shutdown` -> Kaldırıldı. Artık Named Pipe JSON-RPC `system.shutdown` üzerinden çalışır.

> [!NOTE]
> `ADMIN_SECRET` ortam değişkeni, `--admin-secret=` komut satırı parametresi ve HTTP `X-Admin-Secret` başlığı mimariden kalıcı olarak silinmiştir.

---

## 8. WinSW v2.12.0 XML Yapılandırması (`mms_service.xml`)

WinSW v2.12.0 resmi şemasına tam uyumlu XML yapılandırması:

```xml
<service>
  <id>MarketMMSService</id>
  <name>Market MMS Backend Engine</name>
  <description>Market Management System Local POS Backend and Synchronization Service</description>
  
  <executable>%BASE%\bin\mms_backend.exe</executable>
  <arguments>--service-mode</arguments>
  <startmode>Automatic</startmode>
  
  <!-- WinSW v2.12.0 Domain ve User Ayrımı -->
  <serviceaccount>
    <domain>NT AUTHORITY</domain>
    <user>LocalService</user>
  </serviceaccount>

  <!-- Zarif Kapanma için Stop Helper Yapılandırması -->
  <stopexecutable>%BASE%\bin\mms_stop_helper.exe</stopexecutable>
  <stoparguments>--timeout=20</stoparguments>
  <stoptimeout>25sec</stoptimeout>

  <!-- Çökme Durumunda Kurtarma Politikası -->
  <onfailure action="restart" delay="5 sec"/>
  <onfailure action="restart" delay="10 sec"/>
  <onfailure action="none"/>
  <resetfailure>1 hour</resetfailure>

  <!-- Standart Günlük Yapılandırması -->
  <logpath>%BASE%\logs</logpath>
  <log mode="roll-by-size">
    <sizeThreshold>10240</sizeThreshold>
    <keepFiles>5</keepFiles>
  </log>
</service>
```

---

## 9. NTFS ACL Matrisi ve Uygulanabilir Kurulum Betiği (F4 Tasarımı)

### 9.1. Kesin NTFS Erişim Matrisi (Service SID ve Traverse Destekli)

| Dizin / Dosya | Service SID (`NT SERVICE\MarketMMSService`) | Administrators (`S-1-5-32-544`) | SYSTEM (`S-1-5-18`) | Users (`S-1-5-32-545`) / Everyone | İzin Türü ve Kapsam |
|---|---|---|---|---|---|
| `%PROGRAMDATA%\MarketMMS\` | **Traverse Only (`(NP)X`)** | Tam Yetki (`F`) | Tam Yetki (`F`) | **Traverse Only (`(NP)X`)** | Dizin Düzeyi (No Inherit) |
| `bin\` | Okuma & Çalıştırma (`RX`) | Tam Yetki (`F`) | Tam Yetki (`F`) | **Traverse Only (`(NP)X`)** | Dizin Düzeyi (No Inherit) |
| `bin\broker\` | Okuma & Çalıştırma (`RX`) | Tam Yetki (`F`) | Tam Yetki (`F`) | **Okuma & Çalıştırma (`RX`)** | `(OI)(CI)` (Yalnızca Broker için) |
| `config\` | Okuma (`R`) | Tam Yetki (`F`) | Tam Yetki (`F`) | **ERİŞİM YOK** | `(OI)(CI)` |
| `certs\` (`server.crt`, `server.key`)| Okuma (`R`) | Tam Yetki (`F`) | Tam Yetki (`F`) | **ERİŞİM YOK** | `(OI)(CI)` |
| `certs\ca.key` | **KESİNLİKLE BULUNMAZ** | **OFFLINE VAULT** | **OFFLINE VAULT** | **ERİŞİM YOK** | Diskten Yasaklı |
| `data\` (`*.db`, `*-wal`, `*-shm`) | Değiştirme / Yazma (`M`)| Tam Yetki (`F`) | Tam Yetki (`F`) | **ERİŞİM YOK** | `(OI)(CI)` |
| `security\pepper.dpapi` | Salt Okunur (`R`) | Tam Yetki (`F`) | Tam Yetki (`F`) | **ERİŞİM YOK** | Dosya Düzeyi (No Inherit) |
| `run\` | Değiştirme / Yazma (`M`)| Tam Yetki (`F`) | Tam Yetki (`F`) | **ERİŞİM YOK** | `(OI)(CI)` |
| `logs\` | Yazma / Ekleme (`M`) | Tam Yetki (`F`) | Tam Yetki (`F`) | **ERİŞİM YOK** | `(OI)(CI)` |
| `backups\` | Yazma / Değiştirme (`M`)| Tam Yetki (`F`) | Tam Yetki (`F`) | **ERİŞİM YOK** | `(OI)(CI)` |

### 9.2. Reparse Point TOCTOU ve Dizin Güvenlik Modeli (F4)
- **Kurulum Dizini Güvenlik Modeli:** `%PROGRAMDATA%\MarketMMS` dizini Administrator tarafından oluşturulur ve sahibi Administrators grubudur.
- **TOCTOU Analizi:** Standart kullanıcıların (`BUILTIN\Users`) kök dizinde veya üst dizinlerde `FILE_ADD_FILE`, `FILE_ADD_SUBDIRECTORY` veya `FILE_WRITE_DATA` izinleri bulunmaz. Dolayısıyla standart bir kullanıcının kontrol adımı ile ACL uygulama adımı arasında dizin ağacına kötü amaçlı bir junction veya sembolik bağ (symlink) yerleştirmesi teknik olarak imkansızdır.
- Buna rağmen `setup_service_acls.ps1` betiğinde reparse point denetimi **Adım 1** olarak işletilir ve tespit durumunda betik derhal fail-closed (`throw`) sonlanır.

### 9.3. İdempotent Kurulum Betiği (`setup_service_acls.ps1`)

```powershell
# setup_service_acls.ps1 — Service SID, Traverse ve Güvenlik Denetimli NTFS Betiği (v2.0)
$ErrorActionPreference = "Stop"
$baseDir = "$env:ProgramData\MarketMMS"
$serviceName = "MarketMMSService"

function Invoke-AclCommand {
    param([string]$cmd, [string[]]$cmdArgs)
    $p = Start-Process -FilePath $cmd -ArgumentList $cmdArgs -NoNewWindow -Wait -PassThru
    if ($p.ExitCode -ne 0) {
        throw "Komut basarisiz oldu ($cmd $($cmdArgs -join ' ')) - Cikis Kodu: $($p.ExitCode)"
    }
}

Write-Host "1. Reparse Point / Junction / Symlink Denetimi (Adim 1 - Oncelikli)..."
if (Test-Path $baseDir) {
    $allItems = Get-ChildItem -Path $baseDir -Recurse -Force -ErrorAction Stop
    foreach ($item in $allItems) {
        if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            throw "GUVENLIK IHLALI: Dizin agacinda reparse point tespit edildi! Konum: $($item.FullName)"
        }
    }
}

Write-Host "2. ca.key Guvenlik Denetimi (Adim 2 - Fail-Closed)..."
if (Test-Path $baseDir) {
    $caKeys = Get-ChildItem -Path $baseDir -Filter "ca.key" -Recurse -ErrorAction Stop
    if ($caKeys -and $caKeys.Count -gt 0) {
        throw "KRITIK GUVENLIK IHLALI: ca.key dosyasi sunucuda bulundu! Konum: $($caKeys[0].FullName)"
    }
}

Write-Host "3. Service SID Tanimlama ve Cozümleme..."
Invoke-AclCommand "sc.exe" @("sidtype", $serviceName, "unrestricted")
$ntAccount = New-Object System.Security.Principal.NTAccount("NT SERVICE\$serviceName")
try {
    $sidService = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier]).Value
    Write-Host "Service SID Basariyla Cozuldu: $sidService"
} catch {
    throw "Service SID cozumlenemedi! Servis SCM kaydi yapilmis olmalidir."
}

# Sabit SID Tanımları
$sidSystem = "*S-1-5-18"
$sidAdmin  = "*S-1-5-32-544"
$sidUsers  = "*S-1-5-32-545"

Write-Host "4. Dizin yapisi olusturuluyor..."
$dirs = @("bin", "bin\broker", "config", "certs", "data", "security", "logs", "backups", "run")
foreach ($d in $dirs) {
    $p = Join-Path $baseDir $d
    if (!(Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

Write-Host "5. Sahiplik ve Kalitim Kirma..."
Invoke-AclCommand "takeown" @("/F", $baseDir, "/A", "/R", "/D", "Y")
Invoke-AclCommand "icacls" @($baseDir, "/reset", "/T", "/C", "/Q")
Invoke-AclCommand "icacls" @($baseDir, "/inheritance:r", "/T", "/C", "/Q")

Write-Host "6. Service SID ve Traverse Tabanli Izinlerin Uygulanmasi..."
# Kok dizin: Service SID yalnizca Traverse ((NP)X), Users Traverse ((NP)X)
Invoke-AclCommand "icacls" @($baseDir, "/grant:r", "${sidSystem}:(OI)(CI)F", "/grant:r", "${sidAdmin}:(OI)(CI)F", "/grant", "*${sidService}:(NP)X", "/grant", "${sidUsers}:(NP)X")

# bin/: Users Traverse Only ((NP)X), Service SID RX
Invoke-AclCommand "icacls" @("$baseDir\bin", "/grant:r", "${sidSystem}:(OI)(CI)F", "/grant:r", "${sidAdmin}:(OI)(CI)F", "/grant:r", "*${sidService}:(OI)(CI)RX", "/grant", "${sidUsers}:(NP)X")

# bin/broker/: Users Read & Execute (RX), Service SID RX
Invoke-AclCommand "icacls" @("$baseDir\bin\broker", "/grant:r", "${sidSystem}:(OI)(CI)F", "/grant:r", "${sidAdmin}:(OI)(CI)F", "/grant:r", "*${sidService}:(OI)(CI)RX", "/grant:r", "${sidUsers}:(OI)(CI)RX")

# data/, logs/, backups/, run/: Service SID Modify (M), Users ERİŞİM YOK
Invoke-AclCommand "icacls" @("$baseDir\data", "/grant:r", "${sidSystem}:(OI)(CI)F", "/grant:r", "${sidAdmin}:(OI)(CI)F", "/grant:r", "*${sidService}:(OI)(CI)M")
Invoke-AclCommand "icacls" @("$baseDir\logs", "/grant:r", "${sidSystem}:(OI)(CI)F", "/grant:r", "${sidAdmin}:(OI)(CI)F", "/grant:r", "*${sidService}:(OI)(CI)M")
Invoke-AclCommand "icacls" @("$baseDir\backups", "/grant:r", "${sidSystem}:(OI)(CI)F", "/grant:r", "${sidAdmin}:(OI)(CI)F", "/grant:r", "*${sidService}:(OI)(CI)M")
Invoke-AclCommand "icacls" @("$baseDir\run", "/grant:r", "${sidSystem}:(OI)(CI)F", "/grant:r", "${sidAdmin}:(OI)(CI)F", "/grant:r", "*${sidService}:(OI)(CI)M")

# config/, certs/, security/: Service SID Read (R), Users ERİŞİM YOK
Invoke-AclCommand "icacls" @("$baseDir\config", "/grant:r", "${sidSystem}:(OI)(CI)F", "/grant:r", "${sidAdmin}:(OI)(CI)F", "/grant:r", "*${sidService}:(OI)(CI)R")
Invoke-AclCommand "icacls" @("$baseDir\certs", "/grant:r", "${sidSystem}:(OI)(CI)F", "/grant:r", "${sidAdmin}:(OI)(CI)F", "/grant:r", "*${sidService}:(OI)(CI)R")
Invoke-AclCommand "icacls" @("$baseDir\security", "/grant:r", "${sidSystem}:(OI)(CI)F", "/grant:r", "${sidAdmin}:(OI)(CI)F", "/grant:r", "*${sidService}:(OI)(CI)R")

Write-Host "7. Bildirimsel SID Denetimi..."
$criticalPaths = @("$baseDir\data", "$baseDir\config", "$baseDir\certs", "$baseDir\security", "$baseDir\run", "$baseDir\logs")
foreach ($p in $criticalPaths) {
    $acl = Get-Acl -Path $p
    foreach ($access in $acl.Access) {
        $sidVal = $access.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value
        if ($sidVal -eq "S-1-5-32-545" -or $sidVal -eq "S-1-1-0" -or $sidVal -eq "S-1-5-11") {
            throw "GUVENLIK IHLALI: $p dizininde yetkisiz SID izni tespit edildi: $sidVal"
        }
    }
}
Write-Host "NTFS ACL Guclendirmesi Basariyla Tamamlandi!"
```

---

## 10. SQLite Native DLL Derleme, FULL Durability ve AOT Paketleme (F3)

### 10.1. SQLite 3.46.1 Sürüm Seçimi ve Teknik Gerekçesi (F3)
- **Teknik Gerekçe:**
  SQLite projesi 2004 yılından (v3.0.0) bu yana katı C ABI geriye dönük uyumluluk taahhüdü vermektedir. Dart ekosistemindeki `package:sqlite3` (v2.4+) ve `drift` (v2.16+) kütüphaneleri, SQLite C API'sinin standart dinamik sembollerine FFI üzerinden bağlanır.
  SQLite 3.46.1 sürümü (Mayıs 2024), resmi amalgamation arşivinde güvenlik açıklarına (CVE-2023-7104) karşı yamalar içeren, Windows x64 üzerinde kararlılığı kanıtlanmış bir sürümdür.
- **Export Sembolleri Doğrulama Kriteri:**
  Derlenen `sqlite3.dll` dosyasının `package:sqlite3` tarafından tüketilen 24 temel C fonksiyonunu eksiksiz dışa aktardığı (export) doğrulanır:
  `sqlite3_open_v2`, `sqlite3_close_v2`, `sqlite3_prepare_v3`, `sqlite3_step`, `sqlite3_finalize`, `sqlite3_reset`, `sqlite3_column_count`, `sqlite3_column_name`, `sqlite3_column_type`, `sqlite3_column_blob`, `sqlite3_column_text`, `sqlite3_column_int64`, `sqlite3_column_double`, `sqlite3_bind_blob64`, `sqlite3_bind_text64`, `sqlite3_bind_int64`, `sqlite3_bind_double`, `sqlite3_bind_null`, `sqlite3_errmsg`, `sqlite3_errcode`, `sqlite3_libversion`, `sqlite3_sourceid`, `sqlite3_wal_checkpoint_v2`, `sqlite3_wal_autocheckpoint`.
  *(Doğrulama Komutu: `dumpbin.exe /EXPORTS bin\sqlite3.dll`)*

### 10.2. FULL Durability, Fiziksel Disk ve VFS Sınırları (F2 & F3)
> [!CRITICAL]
> **FULL Durability ve Fiziksel Donanım Sınırları:**
> Derleme parametresi **`/DSQLITE_DEFAULT_WAL_SYNCHRONOUS=2` (FULL)** olarak sabitlenmiştir. Her transaction commit anında Windows VFS katmanında `FlushFileBuffers` çağrılır.
> **Fiziksel Sınırlar ve Saha Uyarıları:**
> 1. **İşletim Sistemi ve Dosya Sistemi:** Windows üzerinde NTFS dosya sistemi zorunludur (FAT32/exFAT işlem günlükleme garantisi sunmaz).
> 2. **Sürücü Yazma Önbelleği (Disk Write Cache):** Tüketici sınıfı SSD veya HDD'lerde işletim sistemi `FlushFileBuffers` çağırsa bile sürücü donanım önbelleği veriyi henüz NAND/manyetik plakaya yazmadan tamamlandı yanıtı verebilir.
> 3. **Üretim Donanım Tavsiyesi:** Mağaza ana sunucu PC'lerinde elektrik kesintisine karşı **kesintisiz güç kaynağı (UPS)** ve veri kaybı korumalı (Power Loss Protection - PLP) kurumsal SSD kullanımı önerilir. Sanallaştırma ortamlarında (Hyper-V / ESXi) disk önbelleği "Write-Through" olarak yapılandırılmalıdır.

### 10.3. SQLite Build Manifesti
- **Kaynak Arşiv:** `https://sqlite.org/2024/sqlite-amalgamation-3460100.zip` (SQLite v3.46.1).
- **Kaynak Arşiv SHA-256:** `92ffb1b5904efebfa9bf864e4324f46927952bbff6909477b85e0bf5ff1237a7`.
- **Derleyici:** MSVC x64 v19.38+ (Visual Studio 2022 v17.8+ Build Tools).
- **Derleme Komutu:**
  ```cmd
  cl /O2 /LD /MT /DSQLITE_API=__declspec(dllexport) /DSQLITE_ENABLE_JSON1 /DSQLITE_ENABLE_FTS5 /DSQLITE_THREADSAFE=1 /DSQLITE_DEFAULT_WAL_SYNCHRONOUS=2 /DSQLITE_ENABLE_RTREE sqlite3.c /link /OUT:sqlite3.dll
  ```
- **Derlenmiş DLL SHA-256:**
  Derlenmiş ikili dosyanın hash'i önceden uydurulamaz. Aşama S5-3 implementasyon adımında gerçek derleme makinesinde `Get-FileHash bin\sqlite3.dll -Algorithm SHA256` ile üretilecek ve manifest'e kaydedilecektir.
- **Beklenen `sqlite3_sourceid()`:** `2024-08-13 09:16:32 96c97baa22ad2d3b3650bf83cf04934e7dda10d7401238db35caa40705182415`.

### 10.4. DLL Yükleme Güvenliği ve Anti-Hijacking
1. **Arama Politikası:** Win32 `SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_APPLICATION_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32)` zorunludur.
2. **Mutlak Yol Kanıtı:** Yüklenen modül `GetModuleFileNameW` ile sorgulanarak dosya yolunun `exeDir\sqlite3.dll` olduğu doğrulanır.
3. **Çalışma Zamanı Ayarları:** Her bağlantıda `PRAGMA synchronous = FULL;` uygulanır ve `SELECT * FROM pragma_synchronous;` sorgusuyla `2` değeri teyit edilir.

---

## 11. Genişletilmiş Test Planı (50 Senaryo) (F6)

Testler, **Kategori A: Gerçek Windows Test Ortamı (Real VM / Hardware)** ve **Kategori B: Birim & Simülasyon Testleri (İzole Test Runner)** olarak sınıflandırılmıştır.

| Test No | Senaryo Adı | Test Ortamı | Test Adımları | Beklenen Sonuç |
|---|---|---|---|---|
| **TC-S5-01** | Windows Açılışında Otomatik Başlama | Kategori A | VM reboot edilir; oturum açılmadan servis sorgulanır. | `Get-Service MarketMMSService` -> `Running`, `Automatic`. |
| **TC-S5-02** | SCM Manuel Başlatma ve Durdurma | Kategori A | `net stop` ve `net start` komutları işletilir. | Servis bütçelenmiş 18-20 sn içinde temiz durur ve başlar. |
| **TC-S5-03** | Process Crash ve Otomatik Recovery | Kategori A | `Stop-Process -Name mms_backend -Force` ile child öldürülür. | WinSW çöküşü algılar, 5 sn içinde süreci yeniden başlatır. |
| **TC-S5-04** | Ani Hypervisor Power-Off Sonrası Bütünlük | Kategori A | Satış commit edilir edilmez VM elektrik kesintisi simülasyonuyla kapatılır. | `synchronous=FULL` sayesinde son commit edilen satış eksiksiz bulunur; SQLite recovery tamamlanır. |
| **TC-S5-05** | Graceful Shutdown ve 12s Temiz Drain | Kategori A | SCM stop verilir; o anda 3 aktif satış transaction'ı bulunur. | Kabul edilmiş satışlar tamamlanır, yeni isteğe 503 döner, HTTP force:false kapanır, checkpoint ve DB close temiz biter (exit 0). |
| **TC-S5-06** | Standart Kullanıcının Hassas Dosyaları Okuyamaması | Kategori A | `testuser` ile `market_master.db`, `server.key`, `pepper.dpapi` açılmaya çalışılır. | `Access Denied` (Hata 5) alınır. |
| **TC-S5-07** | Standart Kullanıcının Admin Secret Elde Edememesi | Kategori A | `testuser` ile WMI `Win32_Process.CommandLine` taranır. | Komut satırında secret bulunamaz; WMI sızıntısı sıfırdır. |
| **TC-S5-08** | Yetkisiz Sürecin Named Pipe'a Erişememesi | Kategori A | Standart kullanıcı oturumunda pipe açılmaya çalışılır. | Windows kernel bağlantıyı `ERROR_ACCESS_DENIED` ile reddeder. |
| **TC-S5-09** | Yetkili Broker ile S-4 Eşleştirme ve ACK Teyidi | Kategori A | Broker IPC üzerinden onay verir; istemci Poll ve token-bound ACK tamamlar. | Oturum `completed` olur; token ile satış başarıyla yapılır (200 OK). |
| **TC-S5-10** | Filtrelenmiş / Medium Integrity Token Reddi | Kategori A | UAC onayı almamış admin (`SE_GROUP_USE_FOR_DENY_ONLY`) pipe'a `CreateFile` dener. | Windows kernel bağlantıyı `CreateFile` aşamasında `ERROR_ACCESS_DENIED` (5) ile reddeder. |
| **TC-S5-11** | Servis Kapalıyken API'nin Fail-Closed Davranışı | Kategori A | Servis durdurulur; mobil istemci istek gönderir. | Bağlantı derhal reddedilir (`ECONNREFUSED`); yarım işlem oluşmaz. |
| **TC-S5-12** | Bozuk TLS Sertifikasında Fail-Closed Başlatma | Kategori A | `server.key` bozulur; servis başlatılır. | HTTP moduna düşmez; hata logu basarak kapanır (`exit(1)`). |
| **TC-S5-13** | Çökme Sonrası SQLite WAL Kurtarma Doğrulaması | Kategori A | Satış anında `Stop-Process -Force` verilir; açılışta bakiye sorgulanır. | WAL'dan eksiksiz toparlanır, bakiye ve stok tutarlıdır. |
| **TC-S5-14** | Canlı Servis Sırasında VACUUM INTO Yedekleme | Kategori A | Eşzamanlı 4 satış varken IPC üzerinden backup tetiklenir. | Kilitlenme olmaksızın snapshot alınır; yedek DB doğrulanır. |
| **TC-S5-15** | Temiz Windows VM Üzerinde Sıfırdan Kurulum | Kategori A | Dart SDK bulunmayan temiz VM'de kurulum betiği çalıştırılır. | Servis kurulur, sertifikalar üretilir, mobil satış tamamlanır. |
| **TC-S5-16** | Pipe Squatting Sırasında HTTPS Satış Sürekliliği | Kategori A | Saldırgan önceden pipe açar; servis `FILE_FLAG_FIRST_PIPE_INSTANCE` ile dener. | Event Log 4001 basılır; IPC devre dışı kalır ancak **HTTPS satış API'si çalışmaya devam eder**. |
| **TC-S5-17** | RevertToSelf Gerçek Hata Dalı Çökme Testi | Kategori B | `SetMockRevertToSelfFailure(TRUE)` aktif alt süreç başlatılır; istemci bağlanır. | Alt süreç gerçek `RevertToSelf()` hata dalına girerek `ExitProcess(0xC0000005)` ile çöker; ana test runner etkilenmez. |
| **TC-S5-18** | Gerçek İstemci PID Doğrulaması | Kategori A | Payload içinde sahte `caller_pid` gönderilir. | Sahte PID dikkate alınmaz; kernel'in bildirdiği gerçek PID kaydedilir. |
| **TC-S5-19** | Asenkron OVERLAPPED ERROR_PIPE_CONNECTED Doğrulaması| Kategori A | İstemci `ConnectNamedPipe` öncesi bağlanır (Hata 535). | Sunucu durumu başarı kabul eder ve okuma döngüsünü aksatmaz. |
| **TC-S5-20** | ERROR_MORE_DATA ve Oversized Mesaj Koruması | Kategori A | Pipe'a 128 KB veri basılır; ardından geçerli istek atılır. | 128 KB istek `-32600` ile reddedilir ve pipe kesilir; normal istek 200 OK ile işlenir. |
| **TC-S5-21** | Pipe Bağlantısının Ani Kesilmesi (Broken Pipe) | Kategori A | İstemci isteği yazıp süreci anında abort eder. | Sunucu `ERROR_BROKEN_PIPE` yakalar, handle'ı temizler, yeni istemciye döner. |
| **TC-S5-22** | Eşzamanlı İki Admin Broker ve Seri İşlem Doğrulaması| Kategori A | İki broker aynı anda istek gönderir. | Backend seri kuyruğu sayesinde iki istek çakışmadan sırayla işlenir, doğru yanıtlar döner. |
| **TC-S5-23** | Shutdown Sırasında Yumuşak Draining (503 Yanıtı) | Kategori A | Kapanma başladıktan sonraki ilk 2 sn içinde yeni HTTP isteği atılır. | İstek 503 SERVICE_DRAINING (`Retry-After: 30`) alır; yarım işlem oluşmaz. |
| **TC-S5-24** | WinSW Stop Timeout ve Zorunlu Sonlandırma | Kategori A | Kasıtlı kilitlenen servise SCM stop verilir. | WinSW 25 sn sonra `TerminateProcess` ile öldürür; SCM asılı kalmaz. |
| **TC-S5-25** | NTFS ACL SID Tabanlı Bildirimsel Denetim | Kategori A | `setup_service_acls.ps1` sonrası tüm dizinlerde `Get-Acl` ile SID denetimi yapılır. | Kritik dizinlerde yalnızca SYSTEM, Administrators ve Service SID bulunur; Users/Everyone yoktur. |
| **TC-S5-26** | Gerçek Standart Kullanıcı Hesabı ile Dinamik Efektif Erişim | Kategori A | Gerçek `MmsTestStandardUser` hesabı ile root/bin traverse, broker RX, data/certs/pepper denenir. | Traverse ve broker RX başarılı; data/certs/pepper için kernel `ERROR_ACCESS_DENIED` döner. |
| **TC-S5-27** | Eksik veya Hash Uyuşmazlığı Olan sqlite3.dll | Kategori A | `bin/sqlite3.dll` silinir veya baytları değiştirilir. | Servis fallback yapmaz; açık hata basarak kapanır (`exit(1)`). |
| **TC-S5-28** | Temiz Windows VM Üzerinde Servis Kaldırma | Kategori A | `uninstall_mms_service.ps1` çalıştırılır. | Servis durur, SCM kaydı silinir, dosyalar temizlenir; süreç kalmaz. |
| **TC-S5-29** | Diğer LocalService Sürecinin Pipe Erişim Reddi | Kategori A | Farklı bir LocalService süreci pipe'a bağlanmayı dener. | Windows kernel Service SID uyuşmazlığı nedeniyle bağlantıyı `ERROR_ACCESS_DENIED` ile reddeder. |
| **TC-S5-30** | Stop Helper Service SID ile Shutdown Doğrulaması | Kategori A | `mms_stop_helper.exe` Service SID ile `system.shutdown` çağırır. | Sunucu Service SID'yi tanır (`ROLE_SERVICE_STOP`), kapanma sürecini başarıyla başlatır. |
| **TC-S5-31** | Named Pipe Uzak SMB Bağlantı Reddi | Kategori A | Ağdaki başka bir makineden `\\hub-pc\pipe\...` açılmaya çalışılır. | `PIPE_REJECT_REMOTE_CLIENTS` bayrağı sayesinde kernel bağlantıyı anında reddeder. |
| **TC-S5-32** | Impersonation Öncesi Mesaj Okuma Zorunluluğu | Kategori A | İstemci bağlanır ama veri göndermez; sunucu impersonate dener. | Sunucu veri gelmeden impersonate çağırmaz; 5 sn timeout sonrası bağlantıyı keser. |
| **TC-S5-33** | İstemci Yanıt Okumadığında Pipe Kilitlenme Koruması | Kategori A | İstemci isteği atar ama yanıtı okumayı reddeder. | Sunucu `WaitForSingleObject` ile 2.0s zaman aşımı sonrası `DisconnectNamedPipe` çağırır; worker kilitlenmez. |
| **TC-S5-34** | Normal UI ile Başarılı Broker Response Pipe İletişimi | Kategori A | Normal UI transient pipe açar, elevated broker bağlanır, yanıt yazar. | UI PID ve nonce doğrular, token'ı güvenle alır, pipe kapanır. |
| **TC-S5-35** | Server/Client Named Pipe İzinlerinin Gerçek Windows Doğrulaması | Kategori A | Client `CreateFileW(0x00100003)` ile bağlanır (Başarılı); ardından `CreateNamedPipeW` dener. | İstemcinin ikinci sunucu pipe instance açma girişimi çekirdekçe `ERROR_ACCESS_DENIED` (5) ile reddedilir. |
| **TC-S5-36** | Broker Response Pipe Bağlantı Yarışı ve Re-Listen | Kategori A | Sahte bir yerel istemci UI response pipe'ına bağlanır. | UI PID uyumsuzluğunu yakalar, bağlantıyı keser, re-listen yapar ve meşru broker'ın yanıtını alır. |
| **TC-S5-37** | Eski HTTP Admin Endpoint'lerinin Kapatılması | Kategori A | `/api/v1/pairing/approve` veya `/admin/shutdown` çağrılır. | HTTP Shelf sunucusu isteği 404/403 `ERR_ADMIN_IPC_ONLY` ile reddeder. |
| **TC-S5-38** | Shutdown Drain Timeout ve Aktif DB İşlemi (F2) | Kategori A | WriteQueue kuyruğunda kasten 15s gecikme yaratılarak 12s drain aşılır. | Checkpoint ve DB close işletilmez; WAL korunur; süreç `exit(101)` ile sonlanır. |
| **TC-S5-39** | WinSW v2.12.0 Gerçek XML Uyumluluğu | Kategori A | `mms_service.exe test` ile XML şeması doğrulanır. | WinSW v2.12.0 XML'i hatasız ayrıştırır ve başarıyla raporlar. |
| **TC-S5-40** | SQLite DLL Sürüm, Hash ve Gerçek Yükleme Yolu | Kategori A | `GetModuleFileNameW` ile bellekteki DLL yolu doğrulanır. | Yüklenen DLL'in `exeDir\sqlite3.dll` olduğu, SHA-256'nın uyuştuğu ve `sqlite3_libversion()` çıktısının `'3.46.1'` olduğu kanıtlanır. |
| **TC-S5-41** | Normal UI Standart Kullanıcı UAC İptali | Kategori A | Flutter UI broker tetikler, kullanıcı UAC prompt'unda "Hayır" der. | `ShellExecuteEx` `ERROR_CANCELLED` döner; UI pipe'ı anında temizler, kasiyere iptal bildirir. |
| **TC-S5-42** | SQLite PRAGMA synchronous=FULL Çalışma Zamanı Doğrulaması | Kategori A | Veritabanı başlatılır ve `PRAGMA synchronous;` sorgulanır. | Dönen değer kesin olarak `2` (`FULL`) olarak doğrulanır. |
| **TC-S5-43** | Shutdown Admission Race Condition Testi (F3) | Kategori B | 50 eşzamanlı satış isteği ile `closeGate()` aynı anda tetiklenir. | Sıfır satış kaybı; kapı kapanmadan girenler tamamlanır, sonrakiler 503 alır; sayaç 0'a iner. |
| **TC-S5-44** | Response Pipe Uzak SMB Reddi ve DoS Saldırı Sınırı | Kategori A | Ağdan SMB ile response pipe'a bağlanma ve peş peşe 5 sahte client denenir. | SMB kernel tarafından anında reddedilir; sahte istemciler 3 retry bütçesiyle düşürülür. |
| **TC-S5-45** | Reparse Point Önceliği ve Fail-Closed Denetim | Kategori A | Dizin ağacına junction konulur ve `setup_service_acls.ps1` çalıştırılır. | Betik reparse point'i recursive taramadan ÖNCE tespit eder ve fail-closed durdurur. |
| **TC-S5-46** | SQLite DLL Güvenli Dizin Arama ve Yükleme Testi | Kategori A | Sisteme sahte `sqlite3.dll` yerleştirilir; servis başlatılır. | `SetDefaultDllDirectories` sayesinde sahte DLL engellenir; yalnızca `bin\sqlite3.dll` yüklenir. |
| **TC-S5-47** | Timeout Sonrası Yeniden Başlangıçta Otomatik SQLite Crash Recovery (F2)| Kategori A | TC-S5-38 ile sonlanan servis yeniden başlatılır; satış kayıtları sorgulanır. | SQLite `sqlite3_open_v2` sırasında WAL'daki tüm commit edilmiş işlemleri otomatik kurtarır; 0 veri kaybı. |
| **TC-S5-48** | Aynı Kullanıcı Oturumundaki Başka Süreçten Response Pipe Erişim Girişimi (F1)| Kategori A | Standart kullanıcının açtığı sahte Medium IL süreç response pipe'a `CreateFileW` dener. | UI `clientPid != expectedBrokerPid` tespit eder, derhal `DisconnectNamedPipe` çağırır; veri sızmaz. |
| **TC-S5-49** | SQLite 3.46.1 C Export Sembolleri Doğrulaması (F3)| Kategori B | Derlenen `sqlite3.dll` üzerinde `dumpbin /EXPORTS` çalıştırılır. | `package:sqlite3` için gerekli 24 C API fonksiyonunun tamamının export edildiği doğrulanır. |
| **TC-S5-50** | SQLite PRAGMA synchronous=FULL Fiziksel VFS ve Flush Sınırları (F3)| Kategori B | VFS test ortamında commit çağrılarının işletim sistemi `FlushFileBuffers` tetikleme davranışı izlenir. | Her commit çağrısının diske senkronizasyon ürettiği doğrulanır. |

---

## 12. Uygulama Adımları ve Faz Bağımlılıkları

```
[S5-1: Win32 FFI & Native DLL (pipe_auth_native.c)]
       │
       ▼
[S5-2: Named Pipe Worker Isolate & JSON-RPC Protocol (Dart)]
       │
       ▼
[S5-3: SQLite 3.46.1 FULL Durability Build & Native Entegrasyon]
       │
       ▼
[S5-4: 12s Birleşik Draining Protokolü (AdmissionGate & WriteQueue)]
       │
       ▼
[S5-5: UAC Admin Broker (bin\broker\) & Sayısal Maskeli Response Pipe]
       │
       ▼
[S5-6: WinSW Stop Helper (bin\mms_stop_helper.exe)]
       │
       ▼
[S5-7: NTFS ACL Kurulum Betiği (setup_service_acls.ps1) & Service SID]
       │
       ▼
[S5-8: WinSW v2.12.0 Entegrasyonu & SCM Servis Kurulumu]
       │
       ▼
[S5-9: 50 Senaryolu Genişletilmiş Test Koşumu (Kategori A & B Doğrulaması)]
```

---

## 13. Kesinleşen Kararlar, Deney Başlıkları ve Riskler

### 13.1. Kesinleşen Mimari Kararlar
1. **Model B Zorunluluğu:** Standart kullanıcı oturumu korunur; yalnızca yönetim işlemleri için UAC Broker tetiklenir.
2. **Service SID Tabanlı Yetkilendirme:** Paylaşımlı `LocalService` yerine Windows SCM'nin servise atadığı tekil `NT SERVICE\MarketMMSService` kimliği esas alınır.
3. **Sayısal Maskeli Minimum DACL:** `GENERIC_WRITE` yasağı; istemcilere yalnızca `0x0012019b` açık hakları tahsis edilir (`FILE_CREATE_PIPE_INSTANCE` kesinlikle engellenir).
4. **12 Saniyelik Birleşik Drain:** HTTP soketi `force: false` ile kapatılır; drain başarılıysa checkpoint ve temiz kapanış yapılır; drain timeout olursa checkpoint yapılmaz, WAL korunur ve servis `exit(101)` ile kapanarak sonraki açılışta otomatik crash recovery'ye bırakılır.
5. **SQLite FULL Durability:** `/DSQLITE_DEFAULT_WAL_SYNCHRONOUS=2` derleme bayrağı ve çalışma zamanında `PRAGMA synchronous = FULL` (2) doğrulaması esastır.

### 13.2. Açık Kalan Riskler ve Saha Sınırları
1. **Pipe Squatting DoS:** Kötü niyetli bir standart sürecin makine açılışında pipe adını servisten önce kapması riski. `FILE_FLAG_FIRST_PIPE_INSTANCE` sayesinde sahte pipe'a bağlanılmaz, Event ID 4001 basılır; **HTTPS satış API'si açık tutularak mağaza satışı korunur.**
2. **RevertToSelf Kernel Hatası:** Beklenmeyen bir çekirdek arızasında `RevertToSelf` başarısız olursa thread yetki sızıntısını önlemek için sürecin derhal `ExitProcess(0xC0000005)` ile çökertilmesi (Fail-Closed).
3. **Sürücü Yazma Önbelleği (FlushFileBuffers Sınırı):** Tüketici sınıfı disklerde işletim sistemi diske yaz dese de disk önbelleğinde bekletilme riski. Çözüm: Mağaza ana PC'sinde UPS ve kurumsal SSD kullanımı önerilir.

---

> [!IMPORTANT]
> **Onay Bildirimi:** Bu belge Aşama S-5 için bağlayıcı teknik uygulama planı **v2.0**'dır. Plan teknik ve güvenlik açısından tam olgunluğa getirilmiş olup, kullanıcıdan açık geliştirme onayı alınana kadar kaynak kod yazımına veya servis kurulumuna kesinlikle başlanmayacaktır.
