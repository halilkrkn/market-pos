# MARKET MMS — Pilot Protokol Bloklayıcıları Analizi ve Revize Çözüm Tasarımı (`P-BLOCK-1..3`)

**Belge Durumu:** `OWNER REVIEW REQUIRED` (Son Tutarlılık ve Güvenlik Revizyonu Tamamlandı — Kod Uygulaması Öncesi Onay Bekliyor)  
**Tarih:** 21 Kasım 2026  
**İlgili Sistem:** MARKET MANAGEMENT SYSTEM (`market-pos`) — Windows Master Hub (`test_spikes/spike_01_backend`) + Android / Windows Flutter İstemci (`lib/`, `packages/mms_client_storage`)  
**Bağlayıcı Referanslar:** [`ADR-015`](./decisions/015-rel01-single-hub-config.md) | [`ADR-018`](./decisions/018-discovery-tls-scheme.md) | [`docs/PILOT_TECHNICAL_REMEDIATION_REPORT.md`](./PILOT_TECHNICAL_REMEDIATION_REPORT.md) | Bağımsız Güvenlik Denetçisi Bulguları (`F-1..F-7`)

---

## 1. Yönetici Özeti ve Owner Karar Durumu (`DEC-PBLOCK-1..5`)

Bu doküman, `P-BLOCK-1`, `P-BLOCK-2` ve `P-BLOCK-3` protokol bloklayıcıları için ilk analiz, bağımsız güvenlik denetimi (`F-1..F-7`), Owner Final Değerlendirmesi ve **Son Tutarlılık / Güvenlik İncelemesi (`ADR-015`, `ADR-018`)** sonrasında nihai hale getirilmiş teknik tasarım spesifikasyonudur.

| Karar Kimliği | Konu | Owner Kararı | Bu Revizyondaki Yansıması |
|---|---|---|---|
| **`DEC-PBLOCK-1`** | CA fingerprint kanonikleştirme (`P-BLOCK-1`) | **Onaylandı** | Hub ve Android için özdeş X.509 ASN.1 DER SHA-256 kanonu, katı PEM/BOM/`F-1` `'0'` tuzağı/`certCount != 1` ayrıştırması, `503 ERR_CA_CERT_UNAVAILABLE` ve ortak doğrulanmış test vektörleri (`TV-DER-01..05`) tanımlandı (Bölüm 2). |
| **`DEC-PBLOCK-2`** | 4 Aşamalı CA Bootstrap, Manuel OOB Doğrulama & Bootstrap Güvenlik Sınırı (`P-BLOCK-2`) | **Koşullu Onay** | Owner'ın **10 zorunlu güven koşulu**, QR görsel olmadan **ilk sürüm manuel OOB fingerprint çapraz doğrulama akışı** (`ADR-018` §2.3 uyumu), **7 bootstrap güvenlik sınırı** (`HTTP redirect`, cross-host redirect, beklenmeyen/çoklu PEM, uyuşmazlık, `close(force: true)` zorunluluğu, geçici istemci izolasyonu) ve eşzamanlı CA + fingerprint MITM analizi eklendi (Bölüm 3). |
| **`DEC-PBLOCK-3`** | Deterministik Hub LAN IP Seçimi & UDP Değişmezliği (`P-BLOCK-3`) | **Revizyonla Onay** | `ADR-018` Seçenek C gereği **UDP `HUB_DISCOVERY_V1` protokolü ve `server_ips` alanı kesinlikle değiştirilmez**. 5 adımlı deterministik LAN IP seçimi (`advertise_host` + SAN → `server.crt SAN ∩ aktif fiziksel NIC` → tekil aday → belirsiz çoklu adayda `503 ERR_HUB_LAN_IP_AMBIGUOUS` → aday yoksa `503 ERR_HUB_LAN_IP_UNAVAILABLE`) yalnızca `/api/v1/pairing/session` `hub_url` üretimi için çalışır (Bölüm 4). |
| **`DEC-PBLOCK-4`** | TDD Uygulama Görevi | **Onaylandı** | Tasarım Owner onayını aldıktan sonra ayrı bir TDD uygulama görevinde (`P-BLOCK-1..3` + `F-1..F-7`) gerçekleştirilecektir. Bu görev sırasında **sıfır kod/konfigürasyon değişikliği** yapılmıştır. |
| **`DEC-PBLOCK-5`** | `WindowsDpapiTokenStore.readSecret` (`L-3`) | **Ertelendi** | Mevcut `P-BLOCK-1..3` uygulama kapsamının dışında tutuldu; ayrı bakım işi olarak kayıt altına alındı (Bölüm 9). |

### Kapsam ve Değişmez Sınırlar
- Bu çalışma **yalnızca dokümantasyon ve tasarım revizyonudur**. Kaynak kodu, testler, veritabanları, `MarketMmsSpike01` servisi, sertifikalar, secret'lar ve Git geçmişi değiştirilmemiştir.
- `ADR-015` (tek doğrulanmış `hub_config.json`), `ADR-018` (§2.1 yalnızca `https://` discovery, §2.2 Seçenek C UDP değişmezliği) ve önceki Owner kararlarıyla **çelişen hiçbir protokol değişikliği veya onaysız kapsam genişlemesi** içermez.
- Mevcut Outbox, FIFO `client_seq`, idempotency, server cursor, integer kuruş + Half-Up rounding ve tek-yazarlı SQLite protokolleri korunmaktadır.
- Sistem henüz fiziksel kabul testlerinden geçmediği için üretime veya pilota hazır ilan edilmemektedir.

---

## 2. `P-BLOCK-1` — CA Fingerprint Hesaplama Uyuşmazlığı (`DEC-PBLOCK-1` — Onaylandı)

### 2.1 Kök Neden ve Kanıtlanan Kod Konumları

1. **Hub tarafı ham dosya byte'larını hash'liyor:**  
   `test_spikes/spike_01_backend/lib/security/certificate_manager.dart` (`L220-230`) içindeki `computeSha256Fingerprint(List<int> certBytes)` metodu sertifika içeriğini ayrıştırmadan doğrudan aldığı byte dizisinin SHA-256 özetini hesaplamaktadır. `test_spikes/spike_01_backend/bin/server.dart` (`L772-780`) içindeki `/api/v1/pairing/session` route'u `caFile.readAsBytesSync()` ile okunan UTF-8 PEM metnini (`-----BEGIN CERTIFICATE-----\n...` başlığı, satır sonu karakterleri ve varsa yorum/BOM dahil) doğrudan bu metoda vermektedir.
2. **Android tarafı kanonik X.509 DER byte'larını hash'liyor:**  
   `lib/core/security/tls_pinned_client_factory.dart` (`extractPemCertificatesDer`, `computeSha256Hex`) sertifikadan yalnızca Base64 gövdesini çözerek elde ettiği **X.509 ASN.1 DER** byte dizisinin SHA-256 özetini almaktadır.
3. **Sonuç:** Aynı `ca.crt` dosyası için Hub ve Android tamamen farklı SHA-256 değerleri üretir; aynı PEM dosyasının LF vs CRLF kopyaları veya UTF-8 BOM eklenmesi bile Hub özetini değiştirir.
4. **Hata yönetimi ve `F-1` (`0x30`) tuzağı:**
   - `server.dart` (`L773`) yalnızca `FileSystemException` yakalamakta; ayrıştırma veya sertifika format hatası fırlatılırsa `503 ERR_CA_CERT_UNAVAILABLE` yerine beklenmeyen `500` veya `'UNKNOWN'` sızıntısı riski oluşmaktadır.
   - `certificate_manager.dart` içinde yalnızca `bytes[0] == 0x30` kontrolüne dayalı bir DER sezgiseli kullanılması **`F-1` zafiyetine** yol açar: `0x30` ASCII `'0'` karakteridir; ilk satırında `'01 - Pilot Root CA'` veya `'0x30...'` yorumu ya da metadata bulunan bir PEM dosyasının ilk byte'ı da `0x30` olduğu için dosya yanlışlıkla DER sanılıp ham metin üzerinden hash'lenir.

### 2.2 Kanonik Tasarım: Katı X.509 DER Çıkarımı ve SHA-256 Sözleşmesi

Hub ve Android aşağıdaki özdeş kanonizasyon algoritmasını kullanacaktır (`normalizeCertificateToDerBytes`):

1. **Tek Tip Çıktı Formatı:**  
   İç karşılaştırma ve protokol (`ca_fingerprint`) formatı **64 karakter küçük veya büyük harfe duyarsız 16'lık (hex) kanonik DER SHA-256** değeridir (protokol JSON çıktısında 64 karakter büyük harf `^[0-9A-F]{64}$` önerilir; istemci doğrulamasında `:` ayracı ve boşluklar temizlenip büyük harfe normalize edilir).
2. **PEM Öncelikli ve Katı Ayrıştırma Sırası:**
   - Adım 1: Girdi UTF-8 BOM (`0xEF, 0xBB, 0xBF`) içeriyorsa soyularak UTF-8 (`allowMalformed: true`) okunur.
   - Adım 2: `-----BEGIN CERTIFICATE-----` ve `-----END CERTIFICATE-----` işaretçileri taranır.
     - **Sertifika olmayan PEM blokları reddedilir:** `-----BEGIN PRIVATE KEY-----`, `-----BEGIN RSA PRIVATE KEY-----`, `-----BEGIN EC PRIVATE KEY-----`, `-----BEGIN CERTIFICATE REQUEST-----` veya eşleşmeyen `BEGIN`/`END` etiketleri varsa `TlsConfigurationException` / `FormatException` fırlatılır.
     - **Çoklu sertifika zinciri reddedilir (`certCount != 1`):** `ca.crt` dosyasında 0 veya 1'den fazla (`>= 2`) `CERTIFICATE` bloğu bulunması belirsiz/zincir dosya sayılır; fail-closed reddedilir (sessizce ilk sertifikayı alıp diğerlerini yoksaymak yasaktır).
     - **Base64 + ASN.1 DER doğrulaması:** Tek sertifika bloğunun içindeki tüm whitespace (`\r`, `\n`, boşluk, tab) temizlenir; sıkı Base64 decode edilir. Boş veri veya Base64 hatası reddedilir. Çözülen byte dizisi aşağıda tanımlı sıkı ASN.1 X.509 `SEQUENCE` uzunluk doğrulamasından geçirilmeden kabul edilmez.
   - Adım 3: Yalnızca hiçbir PEM `-----BEGIN ...-----` etiketi bulunmuyorsa girdi **ham ASN.1 DER adayı** olarak değerlendirilir ve **`F-1` korumalı katı ASN.1 TLV doğrulamasından** geçirilir:
     - İlk byte `0x30` (`SEQUENCE` tag) olmalıdır.
     - Uzunluk (length octets) ASN.1 DER kurallarına göre çözülür (`< 0x80` kısa biçim veya `0x81..0x84` uzun biçim, minimal kodlama).
     - `headerLength + contentLength == bytes.length` birebir eşitliği zorunludur ve en az 2 byte iç yapı bulunmalıdır (`bytes.length >= 4`).
     - Bu kontrol ASCII `'0'` ile başlayan (`"01 - ..."` -> `bytes[0] == 0x30`) herhangi bir düz metni veya kırpılmış/artık byte içeren dosyayı %100 kesinlikle reddeder.
3. **Fail-Closed Hub Davranışı (`503 ERR_CA_CERT_UNAVAILABLE`):**
   - `server.dart` içinde `/api/v1/pairing/session` ve `/api/v1/pairing/ca-cert` rotaları `FileSystemException`, `TlsConfigurationException` ve `FormatException` istisnalarının tamamını yakalar.
   - Hatalı, boş, çoklu-sertifikalı, private key içeren veya okunamayan `ca.crt` durumunda Hub asla `'UNKNOWN'`, sahte özet veya HTTP `200`/`500` üretmez; daima **`503 ERR_CA_CERT_UNAVAILABLE`** ile durur.

### 2.3 Hub ↔ Android Ortak Test Vektörleri (`TV-DER-01..05`)

Aşağıdaki tüm SHA-256 değerleri, deterministik 14 byte'lık geçerli bir ASN.1 DER `SEQUENCE` yapısı üzerinde doğrulanmış kesin test vektörleridir (uygulamada gerçek `TestCaPem` X.509 sertifikalarıyla birlikte regresyon süitinde birebir koşturulacaktır):

- **Temel Kanonik ASN.1 DER Baytları (`14 byte`):**  
  `30 0C 30 0A 02 01 01 06 03 55 1D 11 05 00`  
  *(Dış `SEQUENCE` [uzunluk 12], iç `SEQUENCE` [uzunluk 10]: `INTEGER 1`, `OID 2.5.29.17` (`subjectAltName`), `NULL`)*
- **Base64 Karşılığı:** `MAwwCgIBAQYDVR0RBQA=`

| Vektör ID | Girdi Biçimi / İçerik Varyasyonu | Beklenen Kanonik Çıktı (`DER SHA-256`) | Eski/Hatalı Ham Hash (Regresyon Kanıtı) |
|---|---|---|---|
| **`TV-DER-01`** | Ham ASN.1 DER baytları (`30 0C ... 05 00`) | **GEÇERLİ** — `75920A4AF20B64B42B647CDFC23AA88C31C41D3EC7508B71D3501638FA433316` (Kolonlu: `75:92:0A:4A:F2:0B:64:B4:2B:64:7C:DF:C2:3A:A8:8C:31:C4:1D:3E:C7:50:8B:71:D3:50:16:38:FA:43:33:16`) | Aynı |
| **`TV-DER-02`** | Standart Unix LF PEM (`-----BEGIN CERTIFICATE-----\nMAwwCgIBAQYDVR0RBQA=\n-----END CERTIFICATE-----\n`) | **GEÇERLİ** — `75920A4AF20B64B42B647CDFC23AA88C31C41D3EC7508B71D3501638FA433316` | Ham UTF-8 hash'i `A9B04113C7A4CA21FA3A0C285FF9B813C6BB19DC4308D4FFA51D6DAC6CA11049` (Uyuşmazlık!) |
| **`TV-DER-03`** | UTF-8 BOM (`0xEF 0xBB 0xBF`) + `"01 - Pilot Root CA"` yorumu + Windows CRLF (`\r\n`) PEM | **GEÇERLİ** — `75920A4AF20B64B42B647CDFC23AA88C31C41D3EC7508B71D3501638FA433316` (BOM ve yorum soyulur, canonical DER hash'lenir) | Ham UTF-8 hash'i `EB827DB9C79D0F00875BF0FB5E508081B9847DEFDF40055FA4DCA06AA23069FB` |
| **`TV-DER-04`** | `F-1` `'0'` (`0x30`) Tuzağı: `"0x30 comment trap\n-----BEGIN CERTIFICATE-----\nMAwwCgIBAQYDVR0RBQA=\n-----END CERTIFICATE-----\n"` | **GEÇERLİ** — `75920A4AF20B64B42B647CDFC23AA88C31C41D3EC7508B71D3501638FA433316` (Önce PEM etiketi arandığı için yorumdaki `0x30` tuzağına düşmez) | İlk byte `0x30` olduğu için naive sezgisel ham hash üretirdi: `A201165E602A282374E8FE2802EBDB0992C2B744AA52A6D3597A5536389ECE4A` |
| **`TV-DER-05`** | Negatif/Fail-Closed Durumlar: `(a)` 2 `CERTIFICATE` bloğu içeren bundle; `(b)` `BEGIN PRIVATE KEY`; `(c)` boş/bozuk Base64; `(d)` ASN.1 uzunluğu byte sayısına uymayan kırpılmış DER (`30 10 ...`) veya non-`0x30` metin (`"0123invalid"`) | **RED (Fail-Closed):** `FormatException` / `TlsConfigurationException` fırlatılır. Hub `/pairing/session` ve `/pairing/ca-cert` üzerinde **`503 ERR_CA_CERT_UNAVAILABLE`** döner; Android sertifikayı ve pini kabul etmez. | — |

---

## 3. `P-BLOCK-2` — İlk Pairing, OOB Manuel Doğrulama ve Bootstrap Güvenlik Sınırı (`DEC-PBLOCK-2`)

### 3.1 Kök Neden ve Mevcut Koddaki Kritik Bulgular (`F-2..F-7`)

1. **Faz A→D Kopukluğu ve Pinli Client Yenilenmemesi (`device_pairing_client.dart`):**  
   `pairDevice()` içinde `initialCaPem == null` iken `createPinnedClient` (`L99-105`) geçici bir yaprak-pin (`cert.sha256` leaf pin) kurmakta; ardından `L113`'te `/api/v1/pairing/ca-cert` çağrısı yapılıp CA PEM alınsa bile hata yutulmakta (`L135`) ve **aynı HTTPS `client` örneği kapatılıp CA-pinned yeni bir `client` ile değiştirilmeden** `/request`, `/poll*` ve `/ack*` isteklerine devam edilmektedir.
2. **Blind-TOFU Zafiyeti (`F-2`, `device_pairing_client.dart L258-267`):**  
   `expectedCaSha256` null olduğunda (ör. `ca_fingerprint: "UNKNOWN"` veya eksik pin durumunda) sistem TLS sertifikasını doğrulamadan kabullenip yaprak/sunucu sertifikası üzerinden özeti kaydetmektedir.
3. **Downgrade ve Loopback Sızıntısı (`F-4`, `F-6`):**
   - `device_security_card.dart` (`L96, L128`): `qr.hubUrl ?? activeHubUrl` fallback'i, kullanıcı daha önce düz IP (`http://192.168.1.x:8945`) girdiyse TLS eşleştirmeyi `http://` ile çalıştırabilmektedir (`F-4`).
   - `pairing_approval_panel.dart` (`L16-26`): `hubPairingAdminClientProvider` host'u `127.0.0.1` yaparken scheme'i `AppConstants.windowsLocalhostFallbackUrl`'den (`http://`) miras aldığından TLS açıkken Windows UI yerel admin çağrılarında `http://` kullanabilmektedir (`F-6`).
4. **Re-pairing Bayat Pin ve Pin Kaybı (`F-5`, `F-7`):**
   - `device_security_card.dart` (`L116`): `initialCaPem: qr.caPem ?? setup.pinnedCaPem` satırı, Hub CA sertifikası değişmiş olsa bile Android'in eski `setup.pinnedCaPem` sertifikasını yeniden kullanmasına yol açar (`F-5`).
   - `device_security_card.dart` (`L42-63`) + `setup_config_notifier.dart` (`L124-125`): `_saveTlsPin` çağrısı `caCertPem` parametresini geçirmediği için `clearPinnedCaPem: true` tetiklenir ve CA pinning devre dışı kalır (`F-7`).

### 3.2 Owner'ın 10 Zorunlu Koşuluna Uygun 4 Aşamalı CA Bootstrap Modeli

4 aşamalı mimari (**Faz A: Tek Amaçlı Bootstrap CA İndirme → Faz B: OOB Pin Doğrulama & Re-pairing Çakışma Kapısı → Faz C: Soket Kapatma & CA-Pinned Client Kurulumu → Faz D: Pinli Eşleştirme Değişimi**) korunur ve aşağıdaki **10 bağlayıcı koşul** her adımda zorunlu kılınır:

| Owner Koşulu | Bağlayıcı Tasarım Kuralı ve Uygulama Noktası |
|---|---|
| **1. Güvenilir fingerprint kaynağının açık tanımı** | Tek güvenilir CA fingerprint kaynağı: Windows Master Hub dosya sistemindeki yetkili Root CA sertifikası (`ca.crt`) üzerinden Bölüm 2'deki kanonik DER SHA-256 ile üretilen ve Hub'ın yalnızca `127.0.0.1` loopback + `requireAdminSession` korumalı yerel oturumu aracılığıyla Windows Owner arayüzünde (`PairingApprovalPanel`) sunulan `ca_fingerprint` değeridir. |
| **2. `/pairing/session` HTTP yanıtı ağ üzerinden güvenilir sayılmaz** | Ağ üzerinden (LAN HTTP/HTTPS veya herhangi bir ağ/kopya kanalından) alınan `/pairing/session` JSON yanıtı içindeki `ca_fingerprint` değeri **tek başına güven kökü değildir**. Android asla ağdan `/pairing/session` çekip içindeki `ca_fingerprint`'e güvenerek bootstrap başlatamaz; manuel aktarılan JSON yükündeki `ca_fingerprint` dahi Owner'ın girdiği/onayladığı OOB değerle eşleşmedikçe güvenilir kabul edilmez. |
| **3. İlk sürüm için güvenilir OOB aktarım kanalı (Manuel + İsteğe Bağlı Harici QR)** | `ADR-018` §2.3 gereği uygulamada henüz yerleşik QR görseli (`qr_flutter`) yoktur. İlk sürümde birincil güvenilir kaynak, **Owner'ın Hub Windows `PairingApprovalPanel` ekranında doğrudan gördüğü `ca_fingerprint` + `hub_url` değerlerini Android kullanıcı arayüzündeki güvenilir OOB fingerprint alanına girmesi / ekranla gözle doğrulamasıdır** (Bölüm 3.3). |
| **4. Güvenilir OOB fingerprint yoksa eşleştirme başlamaz (`CA_PIN_REQUIRED`)** | Kullanıcı tarafından güvenilir OOB fingerprint sağlanmamış/onaylanmamışsa ya da değer `null`, boş, `'UNKNOWN'` veya 64-hex dışında bir biçimdeyse Android istemci **hiçbir HTTP/HTTPS eşleştirme isteği başlatmaz** (`CA_PIN_REQUIRED`). `ca_fingerprint` mevcutken `http://` hedefi (`F-4`) kesinlikle reddedilir (`TLS_SCHEME_REQUIRED`). |
| **5. Pinsiz HTTPS'de blind-TOFU kesinlikle yasaktır (`F-2`)** | `DevicePairingClient` ve `MmsPinnedTlsClientFactory` içindeki tüm TOFU/fingerprint-çıkarma fallback'leri kaldırılır. `expectedCaSha256` null iken `badCertificateCallback` sertifika kabul edemez, leaf/CA özeti üretemez ve `paired` konumuna geçemez. |
| **6. CA fingerprint uyuşmazlığında fail-closed davranış (`CA_PIN_MISMATCH`)** | Faz A'da `GET /api/v1/pairing/ca-cert` yanıtıyla alınan gövde Bölüm 2 algoritmasıyla ayrıştırılır (`certCount == 1`). Hesaplanan kanonik DER SHA-256 değeri, OOB `expectedCaSha256` ile **sabit zamanlı (`constantTimeEquals`)** karşılaştırılır. Eşleşmezse `CA_PIN_MISMATCH` hatasıyla fail-closed kesilir; sertifika kaydedilmez ve Faz C/D çalıştırılmaz. |
| **7. Bootstrap bağlantısı tek amaçlıdır, izole yaşar ve hemen kapatılır** | Faz A'daki geçici `HttpClient` **yalnızca `/api/v1/pairing/ca-cert` indirmek amacıyla** ayrı bir `_fetchBootstrapCaCertPem(...)` metodu içinde yerel değişken olarak açılır (`followRedirects = false`, `persistentConnection = false`, `idleTimeout = Duration.zero`, gövde `<= 64 KB`, **sıfır `pairing_secret`/`device_id`/token**). İşlem bitiminde veya herhangi bir hata/redirect/timeout halinde `finally` bloğunda **`close(force: true)`** ile zorla kapatılır; metot dışına referansı sızdırılamaz (Bölüm 3.5). |
| **8. Sonraki tüm pairing istekleri CA-pinned HTTPS istemcisinden geçer** | Faz C'de doğrulanmış `caCertPem` + `expectedCaSha256` kullanılarak `SecurityContext(withTrustedRoots: false)` + `setTrustedCertificatesBytes(...)` ile **yeni bir CA-pinned `HttpClient`** kurulur. `/api/v1/pairing/request`, `/poll-challenge`, `/poll`, `/ack-challenge` ve `/ack` yalnızca bu CA-pinned istemci üzerinden yürütülür (`F-3` uyumu için `clientFactory` Faz C sonrası tekrar çağrılır; eski leaf-pin override'ı kaldırılır). |
| **9. SAN, hostname/IP ve geçerlilik tarihleri (`notBefore`/`notAfter`) korunur** | `SecurityContext` içine yalnızca OOB pinle doğrulanmış `ca.crt` yüklendiğinde Dart / BoringSSL TLS doğrulayıcısı `server.crt`'nin **CA imzasını, SAN (`iPAddress`/`dNSName`) hedef eşleşmesini ve `notBefore`/`notAfter` geçerlilik tarihlerini** doğal olarak zorlar. `badCertificateCallback` **daima `false`** döndürerek bu kontrollerin hiçbirini baypas etmez. |
| **10. Re-pairing sırasında pin uyuşmazlığında otomatik kabul YASAKTIR** | Cihazda önceden kayıtlı bir CA pini (`setup.pinnedCaSha256`) varsa ve yeni eşleştirmedeki `expectedCaSha256` bundan farklıysa: **(a)** eski `setup.pinnedCaPem` yeni bağlantıya enjekte edilmez (`F-5` fix); **(b)** yeni fingerprint de eski pini sessizce ezip otomatik kabul edilmez! Kullanıcıya **açık CA Değişikliği Onayı (`REPAIRING_CA_CHANGE_CONFIRMATION_REQUIRED`)** sunulur (eski vs yeni SHA-256 gösterilerek); yalnızca açık onay ve Outbox güvenlik uygunluğu sonrası eski pin sıfırlanır ve Faz A→B→C→D yürütülür. |

> [!NOTE]
> **Windows ve Android İstemci Yan Hatalarının (`F-6`, `F-7`) Kapsam İçi Düzeltilmesi:**  
> - `F-6` (`pairing_approval_panel.dart`): `hubPairingAdminClientProvider`, `pinnedTlsConfigProvider` aktif olduğunda `baseUrl` scheme'ini daima **`https://`** olarak zorlar (`https://127.0.0.1:<port>`).  
> - `F-7` (`device_security_card.dart` & `setup_config_notifier.dart`): Manuel TLS pin kaydetme ve eşleştirme tamamlandığında `caCertPem` bilgisi eksiksiz iletilir; PIN + PEM ikilisi kaybedilmez.

### 3.3 İlk Sürüm İçin Manuel Güvenli OOB Fingerprint Aktarım ve Doğrulama Akışı (`ADR-018` §2.3 Uyumu)

Uygulamada yerleşik QR görsel üretici bulunmadığından (`qr_flutter` paketi mevcut değildir ve kapsam genişlemesi olarak eklenmez), ilk pilot sürümünde güven zinciri **manuel güvenli OOB aktarım ve çapraz doğrulama** üzerine kurulur:

1. **Adım 1 — Hub Windows Owner Ekranında Açık Gösterim (`PairingApprovalPanel`):**  
   Owner "Yeni Eşleştirme Oturumu" başlattığında panel, yalnızca loopback+admin oturumuyla Hub'dan aldığı yanıtın şu alanlarını doğrudan ekranda okunabilir biçimde gösterir:
   - **Çözümlenen Hub Adresi (`hub_url`):** Örneğin `https://192.168.1.50:8945`
   - **Doğrulanacak CA Parmak İzi (`ca_fingerprint`):** 64-hex (gözle okuma kolaylığı için bloklanmış biçimde de gösterilebilir, örn. 8'li/kolonlu bloklar + ham 64-hex)
   - **Oturum Kimliği & Kısa Süreli Sır (`session_id`, `expires_at`):** Kopyalanabilir JSON payload yalnızca kolay veri taşıma içindir; tek başına güven kökü değildir.
2. **Adım 2 — Android Kullanıcısının Güvenilir OOB Girişi ve Karşılaştırması (`DeviceSecurityCard`):**  
   - **Senaryo A (Doğrudan Manuel Giriş / Ekran Teyidi):** Kullanıcı Android `DeviceSecurityCard` üzerindeki **`tls_pin_sha256_field` (Güvenilir OOB CA Fingerprint)** alanına Windows Owner ekranında gördüğü 64-hex parmak izini girer (veya halihazırda aynı Hub için önceden sabitlenmiş/doğrulanmış CA pinine sahipse onu teyit eder) ve eşleştirme yükünü (`session_id`, `pairing_secret`, `hub_url`) yapıştırır.
   - **Senaryo B (JSON Payload Yapıştırma / Harici QR Tarama):** Kullanıcı panoyla aktarılan JSON'u yapıştırsa dahi, Android **JSON içindeki `ca_fingerprint` değerine tek başına güvenmez**:
     - Kullanıcı `tls_pin_sha256_field` alanına Windows ekranından okuduğu CA parmak izini girdiyse / daha önce doğruladıysa, Android iki değeri (`userEnteredOobSha256` ile `payload.normalizedCaSha256`) `constantTimeEquals` ile karşılaştırır. Eşleşmezse **`OOB_FINGERPRINT_MISMATCH`** ile eşleştirmeyi daha Faz A başlamadan durdurur.
     - Eğer `tls_pin_sha256_field` boşsa ve cihazda eşleşen güvenilir pin yoksa: Android eşleştirmeyi başlatmaz (`CA_PIN_REQUIRED`); kullanıcıya Windows `PairingApprovalPanel` ekranındaki `ca_fingerprint` özetini birebir doğrulayıp girmesini / onaylamasını zorunlu kılar.
   - **Temel Kural:** Kopyala-yapıştır JSON yükünü paylaşma kanalı (ör. WhatsApp, e-posta, yerel paylaşım) ele geçirilmiş olsa bile, saldırganın yük içindeki `ca_fingerprint`'i değiştirmesi Windows ekranından manuel girilen/gözle doğrulanan OOB fingerprint ile **`OOB_FINGERPRINT_MISMATCH`** yaratarak yakalanır.
3. **Adım 3 — Fingerprint Eşleşmeden Güven İlişkisi Kurulmaması:**  
   Hem `userOob == payload.ca_fingerprint` (varsa) kontrolü hem de Faz A'da `/api/v1/pairing/ca-cert` yanıtından çıkarılan kanonik DER SHA-256 == OOB fingerprint eşleşmesi sağlanmadan:
   - `SecurityContext` oluşturulmaz,
   - `setupConfigProvider.updateTlsPinning(...)` çağrılmaz,
   - `/api/v1/pairing/request` gönderilmez ve token kaydedilmez.

### 3.4 Güven Zincirinin Kurulma Noktası ve Aktarım Varsayımları

1. **Güven Zinciri Kurulma Noktaları:**
   - **T0 — Fiziksel OOB Güven Kökü:** Windows Host makinesindeki `ca.crt` dosyasından türetilen kanonik DER SHA-256 değerinin `PairingApprovalPanel` üzerinde gösterilmesi ve Owner'ın bu parmak izini fiziksel olarak Android cihaza aktarması/onaylaması. *(Bu noktadan önce ağdan gelen hiçbir `ca_fingerprint` güvenilir sayılmaz.)*
   - **T1 — Faz B Kriptografik Bağlama:** Faz A yalnızca imzalanmamış bootstrap ile `GET /pairing/ca-cert` gövdesini indirir ve bağlantıyı hemen kapatır. Güven ilişkisi, indirilen sertifikanın kanonik DER SHA-256 özetinin T0 OOB fingerprint ile `constantTimeEquals` üzerinden eşleştiği **T1 anında** kurulur.
   - **T2 — Faz C→D Tam X.509 Zincir Doğrulaması:** T1'de doğrulanan `ca.crt`, izole `SecurityContext(withTrustedRoots: false)` içine yüklenir ve yeni CA-pinned `HttpClient` kurulur. `/request` sırasında BoringSSL `server.crt` imzasını, hedef SAN IP/DNS kaydını ve `notBefore`/`notAfter` geçerliliğini doğrular.
   - **T3 — Karşılıklı Owner Yetkilendirmesi (`/approve`):** İstemci açık anahtarını ve `pairing_secret`'ı T2 CA-pinned tünel içinden iletir; Owner Windows panelinde `device_name` ve `publicKeyFingerprint` özetini görerek onayladığında iki yönlü cihaz güveni tamamlanır.
2. **Aktarım Varsayımları:**
   - **Fiziksel Gözetim & Açık Metin Sınırı:** `pairing_secret` taşıyan JSON yalnızca Owner kontrolündeki ekrandan/cihazdan doğrudan aktarılmalı; umumi sohbet/e-posta kanallarına bırakılmamalıdır.
   - **Kısa Ömürlü Oturum (`expires_at`) ve Tam 64-Hex Zorunluluğu:** Kısaltılmış prefix pinleme yasaktır; tam 64 karakterlik hex özeti ve sınırlı oturum süresi zorunludur.

### 3.5 Bootstrap Güvenlik Sınırı ve Zorunlu Hata Matrisi

Bootstrap aşaması **en kısıtlı saldırı yüzeyine** sahip olacak şekilde aşağıdaki 7 zorunlu sınırla kapatılır (bölüm 6.3'teki test planıyla birebir eşlenir):

| # | Bootstrap Güvenlik Sınırı / Risk | Bağlayıcı Teknik Koruma | Beklenen Fail-Closed Davranış & Kod | Test ID |
|---|---|---|---|---|
| **1** | **HTTP Redirect (`301/302/303/307/308`)** | Bootstrap `HttpClientRequest.followRedirects = false` ve `maxRedirects = 0` sabitlenir. HTTP `200` dışındaki tüm durum kodları anında reddedilir. | `Location` başlığı okunmaz/takip edilmez; soket kapatılır. → **`BOOTSTRAP_REDIRECT_FORBIDDEN`** | **`APP-T04`** |
| **2** | **Başka Host'a veya `http://` Şemasına Redirect** | `3xx` yanıtındaki `Location` başka bir LAN/WAN host'una (`https://evil-host/...`) veya plaintext `http://` hedefine yönlendirse dahi `followRedirects = false` nedeniyle ikinci bağlantı asla açılmaz. | Redirect takip edilmez; açıkça cross-host/downgrade reddi raporlanır, soket kapatılır. → **`BOOTSTRAP_REDIRECT_FORBIDDEN`** | **`APP-T05`** |
| **3** | **Beklenmeyen Sertifika İçeriği** | `/pairing/ca-cert` yanıtı `<= 64 KB` sınırında okunur (`Content-Type`/gövde güvenilmez girdi sayılır). Boş gövde, HTML/JSON hata sayfası, `BEGIN PRIVATE KEY` / `CSR`, bozuk Base64 veya ASN.1 DER `SEQUENCE` TLV uzunluk kontrolünden geçmeyen baytlar reddedilir. | Hiçbir pin/PEM kaydedilmez; soket kapatılır, Faz C/D çalıştırılmaz. → **`INVALID_CA_CERT`** | **`APP-T06`** |
| **4** | **Birden Fazla Sertifika İçeren PEM (`certCount != 1`)** | Yanıtta 2 veya daha fazla `-----BEGIN CERTIFICATE-----` bloğu (zincir/bundle) varsa ilk sertifikayı seçip devam etmek kesinlikle yasaktır. | Belirsiz/bundle sertifika reddedilir; soket kapatılır. → **`INVALID_CA_CERT`** | **`APP-T07`** |
| **5** | **CA Fingerprint Uyuşmazlığı** | Geçerli tekil X.509 DER çıkarıldıktan sonra `SHA256(DER)` ile OOB `expectedCaSha256` `constantTimeEquals` ile karşılaştırılır. | Uyuşmazlıkta sertifika bellekten atılır, kaydedilmez, `/request` gönderilmez. → **`CA_PIN_MISMATCH`** | **`APP-T03`** |
| **6** | **Bootstrap Bağlantısının İşlem Sonunda Kapatılmaması Riski** | Bootstrap `HttpClient` üzerinde `idleTimeout = Duration.zero` ayarlanır; tüm istek `try { ... } finally { bootstrapClient.close(force: true); }` içine alınır. | Hem normal başarı yolunda hem redirect/timeout/format hatası/pin uyuşmazlığı dallarında soket `finally` içinde zorla kapatılır; bağlantı havuzu yaşayamaz. | **`APP-T08`** |
| **7** | **Sonraki İsteklerin Yanlışlıkla Geçici İstemciyi Kullanması Riski** | `bootstrapClient` yalnızca private `_fetchBootstrapCaCertPem(...)` metodu içindeki yerel değişkendir; `pairDevice` ana gövdesine nesne olarak geri döndürülmez. Faz D (`/request`, `/poll-challenge`, `/poll`, `/ack-challenge`, `/ack`) yalnızca Faz C'de kurulan yeni CA-pinned istemci referansını alır. | Statik/tip ve çalışma zamanı izolasyonu gereği Faz D isteklerinin geçici bootstrap istemcisini kullanması imkânsızdır (`createPinnedClient` yalnızca Faz C sonrası geçerli CA ile kurulup Faz D'de kullanılır). | **`APP-T09`** |

> [!IMPORTANT]
> Bootstrap bağlantısı **hiçbir koşulda güven ilişkisi kurmaz**. Yalnızca OOB fingerprint ile doğrulanacak ham CA sertifikasını indiren sıfır-sırrı (`pairing_secret`, `device_id`, `store_id` taşımayan) geçici taşıyıcıdır. Güven ilişkisi yalnızca **OOB fingerprint == İndirilen CA DER SHA-256** doğrulandıktan sonra ve yeni kurulan CA-pinned istemci üzerinde başlar.

### 3.6 MITM Saldırı Senaryoları (Eşzamanlı CA + Fingerprint Değişimi Dahil)

| Senaryo | Saldırgan Yeteneği | Saldırı Adımı ve Sistem Tepkisi | Kalan Risk / Sınır |
|---|---|---|---|
| **M1: Ağda Sahte TLS / Sahte `/ca-cert` veya Redirect Enjeksiyonu** | Aktif LAN MITM (ARP spoofing / sahte Hub IP / HTTP 302 enjeksiyonu). | Saldırgan sahte `CA'` sunar veya başka host'a `302` yönlendirir. Redirect anında reddedilir (`BOOTSTRAP_REDIRECT_FORBIDDEN`); sahte `CA'` ise Android'in OOB `H = SHA256(CA_gercek)` özetine takılır (`CA_PIN_MISMATCH`). | **Engellendi** (Kriptografik ve protokol olarak kırılmaz). |
| **M2: Ağdaki `/pairing/session` Yanıtını ve `/ca-cert`'yi Birlikte Değiştirme** | Aktif LAN MITM + ağ üzerinden JSON manipülasyonu. | Android ağdan `/pairing/session` çekmez ve kopyalanan JSON içindeki `ca_fingerprint`'i **tek başına güven kökü kabul etmez** (Bölüm 3.3). Owner'ın Windows ekranından girdiği OOB fingerprint ile JSON/sertifika uyuşmaz (`OOB_FINGERPRINT_MISMATCH` / `CA_PIN_MISMATCH`). Ayrıca `/pairing/session` `127.0.0.1` loopback + admin arkasındadır. | **Engellendi.** |
| **M3: Eşzamanlı Saldırı — Saldırgan Hem CA Sertifikasını Hem QR / Manuel `ca_fingerprint` Değerini Değiştirebilirse** | Yüksek yetenekli saldırgan: (a) Hub Windows makinesini ele geçirip `PairingApprovalPanel` ekranına sahte fingerprint/JSON yazar, VEYA (b) Owner'ın payload'u taşıdığı kanalı ele geçirip `CA'` + `SHA256(CA')` ikilisini sunar. | **Kriptografik Analiz:** `SHA256(CA') == ca_fingerprint'` eşleşeceğinden Phase A→B→C geçilir ve Faz D sahte sunucuyla konuşur. **TLS pinleme tek başına OOB kanalın ele geçirildiği saldırıyı kriptografik olarak yakalayamaz.** **Savunma Derinliği:** (1) Windows ekranı ile mesajlaşma kanalı ayrımı (`OOB_FINGERPRINT_MISMATCH`): Taşıma kanalındaki JSON değiştirilmişse bile Windows ekranındaki OOB fingerprint sabit kalacağından M3 yalnızca taşıma kanalında engellenir. (2) **Re-pairing kilidi (Koşul #10):** Mevcut cihazda kayıtlı pin farklıysa otomatik kabul yasaktır; alarm tetiklenir. (3) **Owner `/approve` doğrulaması:** Sahte Hub gerçek Master Hub token'ı/veritabanı üretemez; gerçek Hub'da Owner kendi başlatmadığı oturumu veya eşleşmeyen `publicKeyFingerprint`'i onaylamaz. | **OOB Bütünlük Sınırı:** İlk kurulumda Windows host OS ve doğrudan Owner gözlemi tamamen ele geçirilmişse güven sınırı aşılmış demektir. |
| **M4: TLS → Plaintext HTTP Downgrade (`F-4`, `F-6`)** | Önceden kalmış `http://` URL (`activeHubUrl`) veya `http://127.0.0.1` Windows fallback. | Koşul #4 (`F-4`) ve `F-6` gereği `ca_fingerprint` varken / pin aktifken `http://` şeması yasaktır. | **Engellendi.** |
| **M5: Re-pairing Sırasında Bayat Pin / Sessiz Değişim (`F-5`)** | Hub CA yenilenmiş veya kötü niyetli ikinci Hub aynı ağa sokulmuştur. | Koşul #10 gereği eski `setup.pinnedCaPem` enjekte edilmez (`F-5`) ve eski vs yeni fingerprint farkında kullanıcı açıkça onay vermezse otomatik kabul engellenir. | **Engellendi.** |

---

## 4. `P-BLOCK-3` — Hub LAN Adresi Üretimi ve `ADR-018` UDP Uyumluluğu (`DEC-PBLOCK-3`)

### 4.1 Kök Neden ve Windows Servis / Kullanıcı Oturumu Farkları

1. **`req.requestedUri.host` bağımlılığı (`server.dart L765-771`):**  
   Windows Master Hub üretimde `LocalService` (`MarketMMSService`, `ADR-015`) veya test ortamında arka plan servisi (`MarketMmsSpike01`, Session 0) altında çalışırken, Windows Masaüstü UI aynı makinede Session 1'de açılır ve admin API'sine `127.0.0.1` üzerinden istek atar. `req.requestedUri.host == '127.0.0.1'` olduğu için Hub QR/JSON içine `hub_url: "https://127.0.0.1:8945"` yazmaktadır.
2. **Sertifika SAN vs Ağ Adaptörü Uyumsuzluğu:**  
   Hyper-V, WSL2, VirtualBox veya VPN adaptörleri ile fiziksel NIC'ler arasında ayrım ve `server.crt` SAN IP kontrolü eksiktir.
3. **Owner Revizyon İlkesi (Heuristic Puanlama Yasağı + `ADR-018` UDP Değişmezliği):**  
   - Belirsiz çoklu ağ arayüzleri arasında yalnızca puanlama yaparak otomatik seçim yapılması **yasaktır**; Owner yapılandırması zorlanır.
   - `ADR-018` §2.2 (**CONFIRMED — Seçenek C**) gereği UDP `HUB_DISCOVERY_V1` protokolü ve payload formatı **değiştirilmeyecektir**. Gerekli LAN adresi seçimi `/api/v1/pairing/session` JSON yanıtı (`hub_url`) için işletilir.

### 4.2 Kesin 5 Adımlı Deterministik LAN IP Seçim Tasarımı (`/pairing/session` İçin)

Hub'da merkezi `HubLanAddressResolver` bileşeni oluşturulur ve **`POST /api/v1/pairing/session`** (ve Hub startup konfigürasyon doğrulaması) bu kesin 5 adımlı sırayı uygular:

1. **Adım 1 — Owner Tarafından Yapılandırılmış `advertise_host` (`hub_config.json`):**
   - `hub_config.dart` (`ADR-015`) içindeki `_allowedKeys` listesine opsiyonel `advertise_host` anahtarı eklenir.
   - Tanımlı ise boş olmamalıdır; **`127.0.0.0/8`, `::1` (loopback) veya `169.254.0.0/16` (link-local) kesinlikle reddedilir** (`HubConfigException`, çıkış kodu `78`).
   - **SAN Doğrulaması (`server.crt`):** `requireTls == true` iken `advertise_host` değerinin `server.crt` X.509 **Subject Alternative Name (SAN)** uzantısındaki `iPAddress` (IPv4 4-byte tag `0x87`) veya `dNSName` (tag `0x82`) kayıtlarından biriyle birebir eşleşmesi **zorunludur**. Eşleşmiyorsa Hub konfigürasyon yükleme ve pairing session üretiminde fail-closed davranır (`HubConfigException` / `503 ERR_ADVERTISE_HOST_SAN_MISMATCH`).
2. **Adım 2 — Sertifika SAN IP Adresleri ile Aktif Fiziksel NIC Adreslerinin Kesişimi:**
   - `advertise_host` tanımlı değilse Hub her `/pairing/session` çağrısında canlı olarak:
     - **(a)** `server.crt` X.509 DER yapısından SAN `iPAddress` IPv4 listesini (`sanIpv4s`, `127.x` ve `0.0.0.0` hariç) çıkarır;
     - **(b)** `NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false)` üzerinden aktif, link-local olmayan (`169.254.x` hariç), loopback olmayan (`127.x` hariç), sanal/tünel olmayan **fiziksel NIC IPv4** adreslerini toplar (`activePhysicalIpv4s`). Sanal/VPN filtrelemesi hem arayüz adına (`vEthernet`, `Hyper-V`, `WSL`, `VirtualBox`, `VMware`, `vbox`, `pseudo`, `Tap`, `Tun`, `WireGuard`, `wintun`, `Tailscale`, `OpenVPN`, `NordLynx`, `ZeroTier`, `Docker`, `Loopback`) hem sanal/VPN alt ağlarına (`169.254.0.0/16`, `192.168.56.0/24`, Tailscale/CGNAT `100.64.0.0/10`) uygulanır.
   - Kesişim kümesi hesaplanır: `candidates = sanIpv4s.intersection(activePhysicalIpv4s)`.
3. **Adım 3 — Tek ve Kesin Aday Varsa Otomatik Seçim:**
   - `candidates.length == 1` ise tekil IPv4 adresi deterministik olarak seçilir (`hub_url = "https://<selected_ip>:<port>"`).
4. **Adım 4 — Birden Fazla Belirsiz Aday Varsa Owner Yapılandırması Gerektiren Hata:**
   - `candidates.length > 1` ise (ör. hem Ethernet hem Wi-Fi aktif ve ikisi de `server.crt` SAN içinde) **heuristic puanlama yapılmaz**; belirsizlik Owner'a devredilir ve **`503 ERR_HUB_LAN_IP_AMBIGUOUS`** döndürülür. Hata JSON'u tespit edilen `candidates` listesini ve `hub_config.json` içine `advertise_host` ekleme talimatını içerir.
5. **Adım 5 — Geçerli Adres Bulunamazsa `503 ERR_HUB_LAN_IP_UNAVAILABLE`:**
   - `candidates.isEmpty` ise **asla `127.0.0.1` veya `req.requestedUri.host`'a sessizce düşülmez**; **`503 ERR_HUB_LAN_IP_UNAVAILABLE`** döndürülür.

### 4.3 `ADR-018` UDP Discovery (`HUB_DISCOVERY_V1`) Korunumu, `server_ips` ve Loopback Yasağı

1. **UDP Discovery Protokolü ve Payload Formatı Değiştirilmez (`ADR-018` Seçenek C):**
   - `test_spikes/spike_01_backend/lib/discovery/discovery_responder.dart` (`L135-142`) içinde zaten tanımlı olan 6 alanlı UDP yanıt şeması **hiçbir değişiklik olmadan korunur**:  
     `service` (`"market_mms_hub"`), `protocol_version` (`"1.0"`), `hub_id`, `http_port`, `server_time`, `server_ips`.
   - Yanıta `tls`, `tls_enabled`, `ca_sha256` veya başka **hiçbir yeni alan eklenmez**.
   - **`server_ips` alanının durumu:** `server_ips` alanı yeni bir öneri değildir; mevcut UDP `1.0` protokolünde zaten yer almaktadır ve `HubDiscoveryResponder.getLocalLanIps()` (`L153-189`) tarafından loopback (`127.*`), link-local (`169.254.*`), VirtualBox (`192.168.56.*`) ve `virtual`/`vbox`/`vmware`/`pseudo`/`vethernet` arayüzleri filtrelenerek doldurulur. Mevcut `discovery_responder.dart` davranışı (`protocol_version: "1.0"`, 6 alan, mevcut `server_ips` semantiği) ve `hub_discovery_responder_test.dart` sözleşmesi tamamen korunur.
2. **Gerekli LAN Adresinin `/api/v1/pairing/session` Üzerinden İletilmesi:**
   - Android eşleştirme akışının ihtiyaç duyduğu tekil, SAN doğrulamalı ve deterministik Hub adresi, UDP discovery yanıtını değiştirmek yerine **`/api/v1/pairing/session` JSON yanıtındaki `hub_url` alanı** üzerinden sağlanır.
   - Böylece `ADR-018` §2.2 Seçenek C ("UDP protokolünde değişiklik yok") kararıyla tam uyum içinde `P-BLOCK-3` çözülür.
3. **Android İstemcisine Loopback Gönderilmemesi & Windows Session 0 Uyumu:**
   - Ne `/api/v1/pairing/session` (`hub_url`) ne de UDP `server_ips` (`includeLoopback: false`, `127.` filtresi) Android istemcisine loopback (`127.0.0.1` / `::1`) iletemez. Windows Masaüstü admin istemcisi kendi yerel loopback çağrısını (`F-6`: `https://127.0.0.1:<port>`) ayrı tutar.
   - `MarketMMSService` / `MarketMmsSpike01` Session 0'da ağ hazır olmadan başlasa dahi her `/pairing/session` isteğinde canlı `NetworkInterface.list` yeniden okunduğu için stale cache sorunu oluşmaz.

### 4.4 VPN ve Sanal Adaptör Test Senaryoları Matrisi (`/pairing/session` LAN Seçimi İçin)

| ID | Adaptör / Topoloji Senaryosu | Beklenen `HubLanAddressResolver` ve `/pairing/session` Davranışı |
|---|---|---|
| **`NET-01`** | Windows'ta Hyper-V `vEthernet (Default Switch)` (`172.x`) + VirtualBox `192.168.56.1` + Aktif Fiziksel Ethernet `192.168.1.50` (`server.crt` SAN içinde) | Sanal adaptörler filtrelenir, kesişimde yalnızca `192.168.1.50` kalır (`candidates.length == 1`) → `hub_url: "https://192.168.1.50:8945"`. |
| **`NET-02`** | Aktif WireGuard (`10.8.0.2`) veya Tailscale CGNAT (`100.64.12.5`) veya OpenVPN TAP/TUN + Aktif Wi-Fi `192.168.1.60` (SAN içinde) | VPN/CGNAT `100.64.0.0/10` ve tünel adaptörleri elenir, kesişim `192.168.1.60` döner → `hub_url: "https://192.168.1.60:8945"`. |
| **`NET-03`** | Yalnızca VPN (`100.64.12.5`) ve WSL2 (`172.24.0.1`) aktif; fiziksel LAN bağlı değil ve `advertise_host` yok | `activePhysicalIpv4s` boş (`candidates.isEmpty`) → Loopback (`127.0.0.1`) DÖNMEZ; `/pairing/session` **`503 ERR_HUB_LAN_IP_UNAVAILABLE`** döndürür. |
| **`NET-04`** | Hem Ethernet (`192.168.1.50`) hem Wi-Fi (`192.168.1.51`) aktif ve ikisi de `server.crt` SAN içinde; `advertise_host` tanımsız | `candidates.length == 2` → Puanlama yapılmaz; **`503 ERR_HUB_LAN_IP_AMBIGUOUS`** + `[192.168.1.50, 192.168.1.51]` aday listesi döner. |
| **`NET-05`** | `NET-04` ortamında Owner `hub_config.json` içine `"advertise_host": "192.168.1.50"` yazar (`server.crt` SAN içinde mevcut) | Adım 1 devreye girer, SAN doğrulaması geçer → Deterministik olarak `hub_url: "https://192.168.1.50:8945"` üretilir (UDP yanıt formatı değişmez). |
| **`NET-06`** | Owner `"advertise_host": "192.168.1.99"` yazar ancak bu IP `server.crt` SAN içinde YOK (`requireTls: true`) | Adım 1 SAN doğrulamasını reddeder → **`503 ERR_ADVERTISE_HOST_SAN_MISMATCH`** (startup'ta da `HubConfigException` ile yakalanır). |
| **`NET-07`** | Fiziksel Ethernet DHCP ile yeni IP `192.168.1.77` almış, ancak `server.crt` yalnızca eski `192.168.1.50` SAN kaydına sahip | `SAN ∩ activePhysical` boş (`candidates.isEmpty`) → **`503 ERR_HUB_LAN_IP_UNAVAILABLE`** (Android'e sonradan SAN hatası verecek oturum üretilmez). |

---

## 5. Uçtan Uca Pairing Akış ve Güven Zinciri Diyagramları

### 5.1 Uçtan Uca Manuel OOB Doğrulamalı Pairing Sıra Diyagramı (`sequenceDiagram`)

```mermaid
sequenceDiagram
    autonumber
    actor Owner as "Owner (Windows Host)"
    participant WinUI as "Windows PairingApprovalPanel"
    participant Hub as "Windows Master Hub (Session 0)"
    participant Android as "Android Istemci (DevicePairingClient)"

    Note over WinUI,Hub: "F-6: Pin aktifken Windows local admin istemcisi yalnizca https://127.0.0.1 kullanir"
    Owner->>WinUI: "Yeni Cihaz Eslestirme Oturumu Baslat"
    WinUI->>Hub: "POST /api/v1/pairing/session (127.0.0.1 + Admin Token)"
    Hub->>Hub: "P-BLOCK-1: ca.crt kanonik ASN.1 DER SHA-256 hesapla (certCount == 1)"
    alt "ca.crt bozuk, coklu veya Private Key"
        Hub-->>WinUI: "503 ERR_CA_CERT_UNAVAILABLE (Fail-Closed)"
    else "P-BLOCK-3: 5 Adimli LAN IP Secimi (UDP degismez)"
        Hub->>Hub: "1. advertise_host+SAN -> 2. SAN kesisim Fiziksel NIC -> 3. Tekil?"
        alt "Coklu belirsiz aday (>1) veya Aday yok (0) veya SAN uyusmazligi"
            Hub-->>WinUI: "503 ERR_HUB_LAN_IP_AMBIGUOUS / UNAVAILABLE / SAN_MISMATCH"
        else "Gecerli LAN hub_url + Kanonik ca_fingerprint hazir"
            Hub-->>WinUI: "200 OK: hub_url, ca_fingerprint, session_id, pairing_secret"
            WinUI-->>Owner: "T0 (Guven Koku): Ekranda OOB ca_fingerprint + hub_url + kopyalanabilir JSON goster"
        end
    end

    Note over Owner,Android: "T0: Ilk surumde QR gorseli yok -> Manuel OOB Aktarim ve Ekran Teyidi"
    Owner->>Android: "Ekrandan okunan OOB ca_fingerprint degerini guvenilir alana gir + oturum JSON aktar"
    Android->>Android: "Agdan/JSON icinden gelen ca_fingerprint tek basina guvenilir degildir: OOB == JSON kontrol et"
    alt "OOB ca_fingerprint eksik veya JSON ile uyumsuz veya http:// (F-4)"
        Android-->>Owner: "FAIL-CLOSED: CA_PIN_REQUIRED / OOB_FINGERPRINT_MISMATCH / TLS_SCHEME_REQUIRED"
    else "OOB Dogrulamasi Gecti"
        alt "Re-pairing: Kayitli setup.pinnedCaSha256 != expectedCaSha256 (Kosul #10)"
            Android-->>Owner: "REPAIRING_CA_CHANGE_CONFIRMATION_REQUIRED (Eski vs Yeni SHA-256 goster)"
            Owner->>Android: "Acik CA Degisimi Onayi (veya Iptal)"
        end

        Note over Android,Hub: "FAZ A: Izole Tek Amacli Bootstrap (Zero Secrets, followRedirects=false, <=64KB)"
        Android->>Hub: "GET /api/v1/pairing/ca-cert (Yerel bootstrapClient)"
        Hub-->>Android: "200 OK: Tekil Root CA PEM (veya 3xx / 503)"
        Android->>Android: "FAZ C-Close: finally icinde bootstrapClient.close(force:true) her durumda"

        alt "HTTP 3xx / cross-host redirect / bozuk veya >1 sertifika"
            Android-->>Owner: "FAIL-CLOSED: BOOTSTRAP_REDIRECT_FORBIDDEN / INVALID_CA_CERT (Guven kurulmaz)"
        else "FAZ B (T1): Kanonik DER cikar -> actualSha256 == OOB expectedSha256 sabit zamanli dogrula"
            alt "T1 Uyusmazligi"
                Android-->>Owner: "FAIL-CLOSED: CA_PIN_MISMATCH (Hicbir pin/sir kaydedilmez)"
            else "T1 Eslesme Basarili -> FAZ C: Yeni CA-Pinned HttpClient Olustur"
                Android->>Android: "SecurityContext(withTrustedRoots:false) + setTrustedCertificatesBytes(caBytes)"
                Note over Android,Hub: "FAZ D (T2): Yalnizca Yeni CA-Pinned HTTPS (SAN, IP/Host, notBefore/notAfter zorunlu; badCertificateCallback=false)"
                Android->>Hub: "POST /api/v1/pairing/request (session_id, pairing_secret, device_pub_key)"
                Hub-->>Android: "202 Pending Approval"
                Owner->>WinUI: "T3: Talep listesinde device_name + publicKeyFingerprint gor ve Onayla"
                WinUI->>Hub: "POST /api/v1/pairing/approve (127.0.0.1 + Admin Token)"
                Android->>Hub: "POST /api/v1/pairing/poll-challenge & /poll & /ack (CA-Pinned HTTPS)"
                Hub-->>Android: "Device Token + Store/Tenant Kimlikleri"
                Android->>Android: "F-7: pinnedCaSha256 + pinnedCaPem + token guvenli kaydet"
            end
        end
    end
```

### 5.2 Bootstrap Güvenlik Sınırı ve Karar Kapıları (`flowchart TD`)

```mermaid
flowchart TD
    Start["Android Eslestirme Baslangici"] --> CheckOOB{"Kullanici Windows ekranindan OOB 64-hex fingerprint girdi mi ve payload https:// + uyumlu mu?"}
    CheckOOB -->|"Eksik / UNKNOWN / http://"| FailOOB["FAIL-CLOSED: CA_PIN_REQUIRED veya TLS_SCHEME_REQUIRED"]
    CheckOOB -->|"OOB != JSON ca_fingerprint"| FailOOBDiff["FAIL-CLOSED: OOB_FINGERPRINT_MISMATCH (Faz A Baslamaz)"]
    CheckOOB -->|"OOB Dogrulandi"| CheckExisting{"Onceki setup.pinnedCaSha256 var mi?"}
    CheckExisting -->|"Evet ve yeni != eski"| PromptRePair["REPAIRING_CA_CHANGE_CONFIRMATION_REQUIRED (Eski vs Yeni goster)"]
    PromptRePair -->|"Reddedildi"| Abort["Iptal (Mevcut pin korunur)"]
    PromptRePair -->|"Acik Onay + Outbox Uygun"| PhaseA["FAZ A: Yerel bootstrapClient ile GET /api/v1/pairing/ca-cert (followRedirects=false, max 64KB, zero secrets)"]
    CheckExisting -->|"Yok veya yeni == eski"| PhaseA
    PhaseA --> FinallyClose["try/finally: bootstrapClient.close(force:true) her durumda"]
    FinallyClose --> CheckStatus{"Status == 200 ve redirect yok mu?"}
    CheckStatus -->|"3xx / Cross-host / Hata"| FailRedir["FAIL-CLOSED: BOOTSTRAP_REDIRECT_FORBIDDEN"]
    CheckStatus -->|"200 OK"| ParseDer["FAZ B: Kanonik DER Cikar (certCount == 1)"]
    ParseDer -->|"Format Hatasi / >1 Sertifika / Private Key"| FailCert["FAIL-CLOSED: INVALID_CA_CERT"]
    ParseDer -->|"Gecerli Tekil DER"| ComparePin{"constantTimeEquals: DER_SHA256 == OOB_Fingerprint?"}
    ComparePin -->|"Hayir"| FailMismatch["FAIL-CLOSED: CA_PIN_MISMATCH (Guven Kurulmaz)"]
    ComparePin -->|"Evet (T1 Kuruldu)"| BuildPinned["FAZ C: YENI CA-Pinned HttpClient Kur (withTrustedRoots=false)"]
    BuildPinned --> PhaseD["FAZ D: /request -> /poll* -> /ack* (SAN + IP/Host + Tarihler Zorunlu)"]
    PhaseD --> SaveState["Basari: device_token + pinnedCaSha256 + pinnedCaPem Kaydet"]
```

---

## 6. Geriye Dönük Uyumluluk, Otomatik Test Planı ve Fiziksel Kabul Testleri

### 6.1 Geriye Dönük Uyumluluk Analizi

1. **UDP Discovery (`HUB_DISCOVERY_V1`, Port `8946`) Tam Korunum (`ADR-018` Seçenek C):**
   - Payload alanları (`service`, `protocol_version: "1.0"`, `hub_id`, `http_port`, `server_time`, `server_ips`) **birebir korunur**; hiçbir yeni alan eklenmez, sürüm yükseltilmez ve `HubDiscoveryResponder.getLocalLanIps()` davranışı kırılmaz.
   - `ADR-018` §2.1 uyarınca eşleştirilmiş Android cihazları keşifte `server_ips` içinden zaten yalnızca `https://` yoklar ve hatada HTTP fallback yapmaz.
2. **Eşleştirme Payload (`v: 1`) Uyumluluğu:** `PairingQrPayload` JSON şema alanları (`v`, `hub_url`, `ca_fingerprint`, `session_id`, `pairing_secret`, `expires_at`) ve sürüm `v: 1` değişmez. Hub tarafında yalnızca `ca_fingerprint` artık kanonik DER SHA-256 üretir ve `hub_url` loopback yerine çözümlenmiş LAN IP'sini taşır.
3. **Önceden Eşleştirilmiş Cihazlar ve Outbox Kuyruğu:** Halihazırda geçerli `device_id`, `device_token`, `client_seq`, `Outbox` kayıtları ve doğru `pinnedCaPem` ile çalışan cihazların senkronizasyonu etkilenmez. Re-pairing gerektiğinde Koşul #10 onay kapısı bekleyen Outbox işlemlerini ve mevcut pini koruyarak kontrollü geçiş sağlar.
4. **Fail-Closed Hata Semantikleri:** Blind-TOFU (`F-2`) ve `127.0.0.1` (`P-BLOCK-3`) sızıntılarının kapatılması sonucunda eksik OOB fingerprint, redirect saldırısı veya belirsiz çoklu-NIC durumları kasıtlı olarak fail-closed (`CA_PIN_REQUIRED`, `BOOTSTRAP_REDIRECT_FORBIDDEN`, `503 ERR_HUB_LAN_IP_AMBIGUOUS`) durdurulacaktır.

### 6.2 Hub Otomatik Test Senaryoları (Uygulama Fazı TDD Kapsamı)

| Test ID | Kapsanan Bileşen / Senaryo | Beklenen Sonuç |
|---|---|---|
| **`HUB-T01`** | `CertificateManager.computeSha256Fingerprint` üzerinde `TV-DER-01..04` (ham DER, LF PEM, BOM+CRLF PEM, `0x30` `'0'` yorum tuzağı) | Tüm geçerli girdilerde özdeş kanonik DER SHA-256 (`75920A4A...`) üretilir. |
| **`HUB-T02`** | `TV-DER-05`: Çoklu sertifika bundle (`>=2`), Private Key PEM, bozuk Base64, kırpılmış DER | `TlsConfigurationException` fırlatılır; `/pairing/session` ve `/pairing/ca-cert` **`503 ERR_CA_CERT_UNAVAILABLE`** döner. |
| **`HUB-T03`** | `/pairing/session` `127.0.0.1` loopback admin isteğiyle çağrıldığında `hub_url` üretimi (`P-BLOCK-3`) | `hub_url` içinde ASLA `127.0.0.1` bulunmaz; 5 adımlı çözümden çıkan deterministik LAN IP'si döner. |
| **`HUB-T04`** | `NET-01..03`: Hyper-V/VirtualBox/VPN (WireGuard, Tailscale `100.64.0.0/10`, OpenVPN) + fiziksel NIC ve sıfır fiziksel NIC testleri | Sanal/VPN arayüzler elenir; geçerli fiziksel aday yoksa **`503 ERR_HUB_LAN_IP_UNAVAILABLE`** döner. |
| **`HUB-T05`** | `NET-04..07`: Çift aktif fiziksel NIC (Ethernet + Wi-Fi ikisi de SAN'da) → `advertise_host` tanımlı → SAN dışı `advertise_host` | Belirsiz durumda puanlama yapılmaz **`503 ERR_HUB_LAN_IP_AMBIGUOUS`**; `advertise_host` SAN içindeyse seçilir; SAN dışındaysa **`503 ERR_ADVERTISE_HOST_SAN_MISMATCH`** (`HubConfigException`) döner. |
| **`HUB-T06`** | `discovery_responder.dart` `ADR-018` Seçenek C Regresyon Kilidi | UDP yanıtı tam olarak 6 mevcut alanı (`service`, `protocol_version: "1.0"`, `hub_id`, `http_port`, `server_time`, `server_ips`) içerir; `127.x` yoktur; `tls`/`ca_sha256` eklenmemiştir. |

### 6.3 Android & Windows UI Otomatik Test Senaryoları (Uygulama Fazı TDD & Bootstrap Sınır Kapsamı)

| Test ID | Kapsanan Bileşen / Senaryo | Beklenen Sonuç |
|---|---|---|
| **`APP-T01`** | Android DER çıkarımı üzerinde `TV-DER-01..05` | Hub ile bit-düzeyinde özdeş SHA-256 (`75920A4A...`); `TV-DER-05` fail-closed. |
| **`APP-T02`** | **OOB Doğrulama Eksikliği & Blind-TOFU Yasağı (`F-2`):** `expectedCaSha256 == null`/`'UNKNOWN'` veya manuel OOB != JSON `ca_fingerprint` | Faz A başlamaz, sıfır HTTP isteği atılır, **`CA_PIN_REQUIRED`** / **`OOB_FINGERPRINT_MISMATCH`** fırlatılır. |
| **`APP-T03`** | **CA Fingerprint Uyuşmazlığı (Bootstrap Sınırı #5):** Sahte/MITM CA sunan sunucuda Faz A `/ca-cert` yanıtı OOB `expectedCaSha256` ile uyuşmaz | **`CA_PIN_MISMATCH`** fırlatılır; pin/token kaydedilmez ve `/request` çağrılmaz. |
| **`APP-T04`** | **HTTP Redirect Reddi (Bootstrap Sınırı #1):** `/api/v1/pairing/ca-cert` uç noktasının aynı host üzerinde `301`/`302`/`307` redirect dönmesi | `followRedirects: false` zorlanır, redirect takip edilmez, **`BOOTSTRAP_REDIRECT_FORBIDDEN`** ile fail-closed durur. |
| **`APP-T05`** | **Başka Host'a / HTTP'ye Redirect Reddi (Bootstrap Sınırı #2):** `/ca-cert` yanıtının `Location: https://other-host/ca.crt` veya `Location: http://...` dönmesi | Hedef hosta bağlanılmaz ve downgrade yapılmaz; **`BOOTSTRAP_REDIRECT_FORBIDDEN`** fırlatılır ve ikinci soket açılmaz. |
| **`APP-T06`** | **Beklenmeyen Sertifika İçeriği (Bootstrap Sınırı #3):** `/ca-cert` gövdesinin boş, `> 64 KB`, HTML hata sayfası, `BEGIN PRIVATE KEY` veya bozuk ASN.1 DER dönmesi | **`INVALID_CA_CERT`** fırlatılır, Faz C/D başlamaz ve hiçbir ayar kaydedilmez. |
| **`APP-T07`** | **Çoklu Sertifika PEM Bundle Reddi (Bootstrap Sınırı #4):** `/ca-cert` gövdesinde `2` adet `CERTIFICATE` bloğu dönmesi | İlki seçilip devam edilmez; **`INVALID_CA_CERT`** fırlatılır ve işlem durdurulur. |
| **`APP-T08`** | **Bootstrap Soketinin Her Koşulda Kapatılması (Bootstrap Sınırı #6):** Başarı, redirect, bozuk PEM ve `CA_PIN_MISMATCH` senaryolarının tamamı | Spy/mock doğrulaması ile `bootstrapClient.close(force: true)` her senaryoda kesinlikle `1` kez çağrıldığı assert edilir. |
| **`APP-T09`** | **Bootstrap Sonrası İsteklerin Geçici İstemciyi Kullanmaması (Bootstrap Sınırı #7):** Faz A→B→C→D uçtan uca gerçek TLS akışı (`clientFactory` dahil `F-3`) | Geçici bootstrap istemcisinin yalnızca `GET /pairing/ca-cert` (1 istek) aldığı; `/request`, `/poll*`, `/ack*` isteklerinin **tamamının** Faz C sonrası kurulan yeni CA-pinned istemci (`withTrustedRoots: false`) üzerinden geçtiği assert edilir. |
| **`APP-T10`** | **SAN & Geçerlilik Tarihleri Koruması (Koşul #9):** CA pini doğru olsa bile `server.crt` SAN IP uyuşmazlığı veya `notAfter` süresi dolmuş olması | `badCertificateCallback` daima `false` döner; `HandshakeException` ile reddedilir. |
| **`APP-T11`** | **Re-pairing Pin Değişimi Onayı (Koşul #10 & `F-5`):** Kayıtlı `setup.pinnedCaSha256 != yeniExpectedCaSha256` durumu | Eski `pinnedCaPem` enjekte edilmez; açık kullanıcı onayı yoksa **`REPAIRING_CA_CHANGE_CONFIRMATION_REQUIRED`** ile durur; açık onay sonrası Faz A→D çalışır. |
| **`APP-T12`** | **`DeviceSecurityCard` & `PairingApprovalPanel` (`F-4`, `F-6`, `F-7` & OOB UI):** | `F-4`: `http://` fallback reddedilir; `F-6`: Windows admin pin aktifken `https://127.0.0.1` zorlar; `F-7`: `_saveTlsPin` `caCertPem` değerini korur; Windows paneli `ca_fingerprint` ve `hub_url`'i ekranda açık gösterir. |

### 6.4 Fiziksel Kabul Testleri (Saha Doğrulama — Tek Seferde Bir Adım)

Uygulama ve otomatik testler tamamlandıktan sonra Owner ile sırasıyla şu saha doğrulamaları koşulacaktır:

1. **`PAT-03` (Temiz Windows Hub Session & LAN IP + Ekranda OOB Fingerprint):** Windows servisi çalışırken `PairingApprovalPanel` üzerinden oturum açılır; `hub_url` değerinin `127.0.0.1` değil gerçek mağaza LAN IPv4 adresi (`https://192.168.x.y:8945`), ekranda gösterilen `ca_fingerprint` değerinin gerçek `ca.crt` kanonik DER SHA-256 özeti olduğu ve UDP discovery davranışının korunduğu doğrulanır.
2. **`PAT-08` (Android Sıfırdan Manuel OOB CA Bootstrap Eşleştirmesi):** Temiz Android cihazda Owner, Windows ekranından okuduğu `ca_fingerprint` değerini Android OOB güvenlik alanına girer ve oturum bilgisini aktarır; Faz A→B→C→D tamamlanır, Owner onaylar ve ilk sync gerçekleşir.
3. **`PAT-10` (Sahte / Yanlış OOB Fingerprint Reddi):** Windows ekranındakinden 1 karakter farklı OOB fingerprint ile eşleştirme denenir; Android'in `/request` veya `pairing_secret` göndermeden `OOB_FINGERPRINT_MISMATCH` / `CA_PIN_MISMATCH` vererek işlemi durdurduğu doğrulanır.
4. **`PAT-11` (VPN / Çoklu NIC Ortamında Deterministik Davranış):** VPN/sanal adaptör aktifken doğru fiziksel IP'nin seçildiği; çift fiziksel adaptör aktifse `503 ERR_HUB_LAN_IP_AMBIGUOUS` uyarısı verip `advertise_host` girilince deterministik olarak çözüldüğü doğrulanır.
5. **`PAT-12` (Hub CA Yenileme / Re-pairing Onay Kilidi):** Hub'da farklı bir Test CA ile oturum açıldığında Android'in eski pini sessizce ezmediği, açık eski vs yeni fingerprint uyarısı gösterdiği ve yalnızca Owner onayıyla yeniden eşleştiği doğrulanır.

---

## 7. Bağımsız Güvenlik Denetçisi Kontrol Listesi (`AUD-01..20`)

Kodlama aşaması tamamlandıktan sonra Bağımsız Güvenlik Denetçisi aşağıdaki maddeleri tek tek doğrulayacaktır:

- [ ] **`AUD-01` (`P-BLOCK-1`):** `certificate_manager.dart` kanonik ASN.1 DER byte'larını hash'liyor; `bytes[0] == 0x30` (`F-1`) sezgisel kontrolü kaldırılmış ve katı ASN.1 TLV uzunluk kontrolü eklenmiş.
- [ ] **`AUD-02` (`P-BLOCK-1`):** Hub ve Android PEM ayrıştırıcıları `certCount != 1`, `BEGIN PRIVATE KEY` ve bozuk Base64/ASN.1 girdilerini fail-closed reddediyor (`503 ERR_CA_CERT_UNAVAILABLE` / `INVALID_CA_CERT`).
- [ ] **`AUD-03` (`P-BLOCK-1`):** `TV-DER-01..05` ortak test vektörleri hem Hub hem Android test süitinde geçiyor.
- [ ] **`AUD-04` (`P-BLOCK-2` #1-#3, `ADR-018` §2.3):** Windows `PairingApprovalPanel` ekranda `ca_fingerprint` + `hub_url` gösteriyor; Android ağdan veya yapıştırılan JSON'dan gelen `ca_fingerprint`'i tek başına güven kökü saymıyor, kullanıcının girdiği/onayladığı OOB fingerprint ile çapraz doğruluyor.
- [ ] **`AUD-05` (`P-BLOCK-2` #4, `F-2`):** OOB fingerprint null, boş, `'UNKNOWN'` veya 64-hex dışındaysa sıfır HTTP isteğiyle `CA_PIN_REQUIRED` dönüyor; blind-TOFU yolunun tamamı silinmiş.
- [ ] **`AUD-06` (Bootstrap Sınırı #1-#2):** Bootstrap isteği `followRedirects = false` ile çalışıyor; aynı host veya başka host/http yönlendirmelerinde `BOOTSTRAP_REDIRECT_FORBIDDEN` ile fail-closed duruyor.
- [ ] **`AUD-07` (Bootstrap Sınırı #3-#4):** Bootstrap gövdesi `<= 64 KB`, boş/HTML/private-key ve çoklu-sertifika (`certCount != 1`) durumlarında `INVALID_CA_CERT` ile duruyor.
- [ ] **`AUD-08` (Bootstrap Sınırı #5):** `/pairing/ca-cert` kanonik DER özeti OOB pinle sabit zamanlı (`constantTimeEquals`) karşılaştırılıyor; uyuşmazlıkta `CA_PIN_MISMATCH` ile hiç veri kaydetmeden sonlanıyor.
- [ ] **`AUD-09` (Bootstrap Sınırı #6):** Bootstrap `HttpClient` yalnızca `_fetchBootstrapCaCertPem` içinde yerel değişken olarak açılıyor, sıfır sır taşıyor, `idleTimeout = Duration.zero` kullanıyor ve `finally` bloğunda `close(force: true)` ediliyor (testlerle doğrulanmış).
- [ ] **`AUD-10` (Bootstrap Sınırı #7, `F-3`):** Faz D istekleri (`/request`, `/poll*`, `/ack*`) asla geçici bootstrap istemcisini kullanamıyor; tamamen Faz C'de `SecurityContext(withTrustedRoots: false)` ile yeni kurulan CA-pinned istemciden geçiyor.
- [ ] **`AUD-11` (`P-BLOCK-2` #9):** CA-pinned istemcide `badCertificateCallback` daima `false` dönüyor; SAN IP/DNS uyuşmazlığı ve süresi dolmuş leaf sertifikalar reddediliyor.
- [ ] **`AUD-12` (`P-BLOCK-2` #10, `F-5`):** Re-pairing'de eski `setup.pinnedCaPem` yeni bağlantıya enjekte edilmiyor ve `setup.pinnedCaSha256 != yeniSha256` durumunda açık kullanıcı onayı olmadan otomatik kabul yapılmıyor.
- [ ] **`AUD-13` (`F-4`):** `DeviceSecurityCard._executePairing` içindeki `activeHubUrl` fallback'i `ca_fingerprint` mevcutken `http://` kullanamıyor.
- [ ] **`AUD-14` (`F-6`):** `pairing_approval_panel.dart` `hubPairingAdminClientProvider` pin aktifken `https://127.0.0.1` kullanıyor.
- [ ] **`AUD-15` (`F-7`):** `_saveTlsPin` `caCertPem` parametresini kaybetmiyor (`clearPinnedCaPem: true` tetiklemiyor).
- [ ] **`AUD-16` (`P-BLOCK-3`):** `HubLanAddressResolver` kesin 5 adımlı sırayı uyguluyor (`advertise_host` + SAN → `SAN ∩ aktif fiziksel NIC` → tekil → `503 AMBIGUOUS` → `503 UNAVAILABLE`); heuristic puanlama bulunmuyor.
- [ ] **`AUD-17` (`P-BLOCK-3`, `ADR-015`):** `advertise_host` `hub_config.json` `_allowedKeys` içine eklenmiş, loopback/APIPA yasaklanmış ve `server.crt` SAN ile doğrulanıyor.
- [ ] **`AUD-18` (`P-BLOCK-3`):** Android'e giden `/pairing/session` (`hub_url`) asla `127.0.0.1` / `169.254.x` içermiyor.
- [ ] **`AUD-19` (`ADR-018` Seçenek C):** UDP `HUB_DISCOVERY_V1` (`discovery_responder.dart`) yanıt formatı (6 mevcut alan + `server_ips` mevcut davranışı) tamamen değişmeden korunmuş, hiçbir yeni UDP alanı eklenmemiş.
- [ ] **`AUD-20` (Kapsam Sınırı & `DEC-PBLOCK-5`):** QR görsel paketi (`qr_flutter`), Outbox/sync değişikliği ve ertelenen `L-3` (`WindowsDpapiTokenStore`) bu kapsama dahil edilmemiş.

---

## 8. `ADR-015`, `ADR-018` ve Önceki Owner Kararları Tutarlılık Denetimi

| Kaynak Karar | Kararın Bağlayıcı Hükmü | Bu Belgedeki Önceki Hata / Tespit | Yapılan Düzeltme ve Uyum Durumu |
|---|---|---|---|
| **`ADR-018` §2.2 (Seçenek C — CONFIRMED)** | UDP `HUB_DISCOVERY_V1` yanıt formatı (`protocol_version: "1.0"`) değişmeyecek; yanıta `tls`/`ca_sha256` eklenmeyecek. Mevcut 6 alan: `service`, `protocol_version`, `hub_id`, `http_port`, `server_time`, `server_ips`. | Önceki taslağın 4.3 ve 6.2 bölümlerinde UDP şeması hatalı olarak `port, tls_enabled vb.` biçiminde yazılmış ve `HubLanAddressResolver`'ın UDP yanıtı `server_ips` sırasını da değiştireceği ifade edilmişti. | **Düzeltildi (%100 Uyumlu):** Hatalı `port`/`tls_enabled` ifadeleri kaldırıldı; `server_ips` alanının mevcut protokolde zaten var olduğu ve `discovery_responder.dart` davranışının hiç değiştirilmeyeceği açıkça belgelendi; LAN IP seçimi yalnızca `/api/v1/pairing/session` `hub_url` için sınırlandı. |
| **`ADR-018` §2.1 & §2.3 (CONFIRMED)** | Eşleştirilmiş cihaz keşfinde yalnızca `https://`; uygulamada QR görseli (`qr_flutter`) yok, manuel aktarım esastır. | Önceki metin OOB adımlarında ağırlıklı olarak "ekrandan QR okutma" dilini kullanıyordu. | **Düzeltildi (%100 Uyumlu):** QR görseli olmadığı dikkate alınarak ilk sürüm **manuel güvenli OOB aktarım ve ekran/uygulama çapraz doğrulama akışı** (`PairingApprovalPanel` gösterimi + Android OOB alanı) Bölüm 3.3'te netleştirildi; harici QR paketi eklenmedi. |
| **`ADR-015` (REL-01 — CONFIRMED)** | `--config=` tek `hub_config.json` kaynağı, env fallback yasağı, katı `_allowedKeys`, çıkış kodu `78`, `tls.ca_cert` zorunluluğu, `MarketMMSService` vs `MarketMmsSpike01`. | Ek `advertise_host` yapılandırma anahtarının `hub_config.dart` katı şema doğrulaması ve `LocalService`/Session 0 ile ilişkisi özetlenmişti. | **Teyit Edildi (%100 Uyumlu):** `advertise_host`, `hub_config.json` `_allowedKeys` altına eklendi, `ADR-015` çıkış kodu `78` / SAN doğrulama kuralına bağlandı; env fallback yasağı ve `MarketMmsSpike01` korunumu teyit edildi. |
| **Owner `DEC-PBLOCK-1..3`** | 1) DER SHA-256 + vektörler; 2) 10 koşullu CA bootstrap + MITM + re-pairing onayı; 3) 5 adımlı LAN IP (puanlama yok, ambiguous hata). | Bootstrap soketinin kapanmama/yanlış kullanım sınırları tek tek test ID'lerine bağlanmamıştı. | **Güçlendirildi (%100 Uyumlu):** Bölüm 3.5'te **7 bootstrap güvenlik sınırı** ve Bölüm 6.3'te `APP-T01..T12` test senaryoları eksiksiz tanımlandı. |
| **Owner `DEC-PBLOCK-4..5`** | TDD uygulama ayrı görevde; `L-3` (`WindowsDpapiTokenStore.readSecret`) ertelendi. | Mevcut oturumda kod/test çalıştırılmaması gerekiyor. | **Korundu (%100 Uyumlu):** Sıfır kod/test/git değişikliği; `L-3` kapsam dışı bırakıldı. |

---

## 9. Owner Onayı Gerektiren Açık Karar ve Geçiş Özeti

| Karar | Durum | Sonraki Adım |
|---|---|---|
| **`DEC-PBLOCK-1`** (Kanonik DER SHA-256 + `TV-DER-01..05`) | **Onaylandı** | Uygulama fazı TDD kapsamına alınacak. |
| **`DEC-PBLOCK-2`** (10 Koşullu 4 Aşamalı CA Bootstrap, Manuel OOB Çapraz Doğrulama & 7 Bootstrap Sınırı) | **Son İnceleme Onayı Bekliyor** | Owner bu revize tasarımı onayladıktan sonra uygulama fazına geçilecek. |
| **`DEC-PBLOCK-3`** (5 Adımlı Deterministik `/pairing/session` LAN IP + `ADR-018` UDP Değişmezliği) | **Son İnceleme Onayı Bekliyor** | Owner bu revize tasarımı onayladıktan sonra uygulama fazına geçilecek. |
| **`DEC-PBLOCK-4`** (TDD Uygulama Görevi Başlatma) | **Tasarım Onayı Bekliyor** | Owner bu dokümanı onayladığında ayrı bir TDD uygulama görevi açılacak. |
| **`DEC-PBLOCK-5`** (`L-3` `WindowsDpapiTokenStore.readSecret`) | **Ertelendi** | Ayrı bakım görevi olarak takip edilmeye devam edecek. |

**Nihai Belge Durumu:** `OWNER REVIEW REQUIRED`
