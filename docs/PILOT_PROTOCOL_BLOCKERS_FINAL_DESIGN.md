# MARKET MMS — `P-BLOCK-1..3` Son Teknik Revizyon ve Güvenlik Tutarlılığı Tasarımı

**Belge Durumu:** `APPROVAL REQUIRED` (Uygulama Öncesi Nihai Tasarım Spesifikasyonu — Salt Okunur Revizyon; Owner Onayı Bekliyor)  
**Tarih:** 21 Kasım 2026  
**Kapsam:** `P-BLOCK-1` (UTF-8 Bağımsız DER/PEM Ayrıştırma, Dar Kapsamlı `MmsX509PreValidator` ve OOB CA vs TLS Doğrulama Ayrımı), `P-BLOCK-2` (`ALT-BOOT-2` İlk HTTPS Bootstrap, Proxy/Sıkıştırma/Gövde Sınırları, Mutlak Timeout/Slowloris, Crash-Safe `ACK_PENDING` Re-pairing & İdempotent `/ack`, Localhost SAN) ve `P-BLOCK-3` (`GetAdaptersAddresses` + `GetIfEntry2` `MIB_IF_ROW2.HardwareInterface` Fiziksel/Hyper-V Host Ayrımı, `advertise_host` Çift Doğrulama & `ADR-018` UDP Korunumu)  
**Bağlayıcı Referanslar:** [`AGENTS.md`](../AGENTS.md) | [`GEMINI.md`](../GEMINI.md) | [`PILOT_PROTOCOL_BLOCKERS_ANALYSIS.md`](./PILOT_PROTOCOL_BLOCKERS_ANALYSIS.md) | [`PILOT_TECHNICAL_REMEDIATION_REPORT.md`](./PILOT_TECHNICAL_REMEDIATION_REPORT.md) | [`PILOT_PROTOCOL_BLOCKERS_FINAL_REVIEW_REPORT.md`](./PILOT_PROTOCOL_BLOCKERS_FINAL_REVIEW_REPORT.md) | [`ADR-015`](./decisions/015-rel01-single-hub-config.md) | [`ADR-017`](./decisions/017-snapshot-endpoint-and-tls-pin-classification.md) | [`ADR-018`](./decisions/018-discovery-tls-scheme.md)

> [!CAUTION]
> **Yönetişim, Yetki Sınırı ve Salt Okunur Çalışma Beyanı:**  
> 1. Bu doküman **yalnızca salt okunur teknik analiz ve uygulama öncesi tasarım spesifikasyonudur**. Hiçbir kaynak kodu, test kodu, script, executable, yapılandırma dosyası (`pubspec.yaml`, Gradle, manifest, `hub_config.json`, WinSW `.xml`), SQLite veritabanı, safety snapshot, sertifika, private key, token, pepper veya `MarketMmsSpike01` servisi değiştirilmemiştir.  
> 2. **Bu doküman kendi kendine hiçbir Owner kararını onaylayamaz**, önceki taslaklara verilmiş değerlendirmeleri onay saymaz ve **kodlama / TDD aşamasına geçiş için otomatik yetki çıkarmaz**.  
> 3. **`DEC-REV-1..4` (`APPROVAL REQUIRED`)** ve **`DEC-REV-5..6` (`BLOCKED`)** kararlarının tamamı Owner onayı bekleyen durumdadır.  
> 4. Üretim Android signing key (`B1`), üretim OpenSSL TLS sertifikaları (`B2`) ve fiziksel kabul testleri (`PAT-01..15`) tamamlanmadan sistem pilota veya üretime hazır ilan edilemez.

---

## 1. Önceki Tasarımdan Değişen Noktalar ve Korunan Mimari Değişmezler

### 1.1 Önceki Tasarıma Göre Giderilen Teknik Boşluklar ve Çelişkiler

| # | Bölüm | Önceki Tasarımdaki Belirsizlik / Çelişki / Risk | Bu Nihai Revizyondaki Kesin Çözüm |
|---|---|---|---|
| **1** | **§2.1 (`P-BLOCK-1`)** | PEM ve binary DER ayrımı ilk adımda tüm girdiye `utf8.decode` çalıştırıp `FormatException` üzerinden fallback yapmaya bağımlıydı; saf binary DER (yüksek bitli ASN.1 baytları) ile bozuk metin/PEM sınırı tamamen UTF-8 çözümlemesinden bağımsız tanımlanmamıştı. | **UTF-8 Çözümlemesinden Bağımsız Byte-Düzeyi Sınıflandırma (`extractCanonicalSingleCertDer`):** Önce `rawBytes` üzerinde BOM (`0xEF 0xBB 0xBF`) veya ASCII `-----BEGIN ` / `-----END ` byte dizisi aranır. Yalnızca PEM yolu UTF-8 (`allowMalformed: false`) çözer; ikili DER yolu **`utf8.decode` hiç çağrılmadan** doğrudan `0x30` + canonical definite-length + `headerLength + contentLength == rawBytes.length` ile işlenir. |
| **2** | **§2.2 (`P-BLOCK-1`)** | `MmsX509PreValidator` kapsamı, kapsam dışı alanları, ASN.1/DER sayısal sınırları, hata davranışları ve CA OOB fingerprint doğrulaması vs sunucu TLS sertifikası doğrulaması ayrımı daha dar ve kesin hale getirilmeliydi. | `MmsX509PreValidator` yalnızca **3 dar görevle** sınırlandırıldı (Kök CA v3 yapısal ön kontrol, Faz B `ca.subjectDer == leaf.issuerDer` ön filtresi, `server.crt` IPv4 SAN çıkarımı). İmza/zincir doğrulaması **BoringSSL**'e bırakıldı; CA OOB doğrulaması ile `server.crt` TLS doğrulaması ayrı düzlem olarak kesinleştirildi. |
| **3** | **§3.1 & §3.3 (`P-BLOCK-2`)** | Bootstrap istemcisinde proxy (`HTTP_PROXY`/`HTTPS_PROXY`), otomatik gövde sıkıştırması (`autoUncompress` / `Content-Encoding`), kesilmiş/çelişkili `Content-Length` gövdeleri (`0 < totalBytes < Content-Length`) ve Slowloris tam olarak kapatılmamıştı. | `bootstrapClient.findProxy = (_) => 'DIRECT'`, `autoUncompress = false` + `Accept-Encoding: identity` (`Content-Encoding` ≠ `identity` anında ret), `contentLength != totalBytes` çelişkili gövde reddi, `65.537`'nci bayt akış kesicisi ve sıfırlanmayan **`Timer(Duration(seconds: 5))`** kesinleştirildi. Faz C/D ve normal sync istemcilerinde TLS gevşetme yasağı korundu. |
| **4** | **§3.4 (`P-BLOCK-2`)** | Mevcut `POLL_RECEIVED → ACK_CONFIRMED` akışında **Hub `/ack` isteğini başarıyla işleyip Android yanıtı alamadan çökerse**, açılışta `POLL_RECEIVED` silindiği için yeni token kaybediliyor ve sunucu aynı `/ack` tekrarında `409 CHALLENGE_ALREADY_CONSUMED` / `410 TOKEN_BUFFER_EXPIRED` veriyordu. | Kalıcı **`ACK_PENDING`** durumu (`/ack` gönderilmeden **hemen önce** yazılır) + **Sunucu Tarafı İdempotent `/ack`** (`confirmedTokenSha256` + `confirmedAckChallengeId` ile imza yeniden doğrulanıp mükerrer DB yazımı olmadan `200 OK` döner) + Startup Reconciliation yoklama yolu eklendi. Eski kimlik, Outbox, `client_seq`, `device_id`, `tenant_id`, `store_id` %100 korunur. |
| **5** | **§4.1 & §4.2 (`P-BLOCK-3`)** | `GetAdaptersAddresses` tek başına fiziksel donanım ayrımını garanti etmez (`IfType == 6` Hyper-V `vEthernet` veya köprülerde de raporlanır). Ayrıca Hyper-V External Switch (`vEthernet`) gerçek host LAN bağlantısı taşırken körükörüne elenebilirdi. | **`GetAdaptersAddresses` + `GetIfEntry2` (`MIB_IF_ROW2.InterfaceAndOperStatusFlags.HardwareInterface`)** `Luid`/`IfIndex` anahtarıyla birleştirildi. **Tier 1** (`HardwareInterface == 1`) öncelikli, yoksa **Tier 2** (izole/NAT olmayan, SAN IPv4'lü veya `advertise_host` eşleşmeli host `vEthernet`/Bridge) kabul edilecek şekilde tasarlandı. Windows x64 FFI offset'leri **`UNVERIFIED`** korundu ve fail-closed davranış tanımlandı. |
| **6** | **§3.5 & §4.3 (`advertise_host`)** | `advertise_host` veya LAN SAN uyuşmazlığında Hub'ın tamamen kapanıp kapanmayacağı ile `IP:127.0.0.1` Loopback SAN eksikliğinin hata kategorisi ayrılmalıydı. | **İki Ayrı Hata Kategorisi:** (1) `IP:127.0.0.1` SAN eksikliği Windows yerel admin/kasa TLS'ini kırdığı için **Startup Fail-Fast (çıkış `78`)**; (2) LAN / `advertise_host` SAN uyuşmazlığı Hub'ı **kapatmaz** (yerel POS ve geçerli cihazlar çalışmaya devam eder), startup'ta tanı uyarısı loglar ve `/pairing/session` isteğinde fail-closed **`503 ERR_ADVERTISE_HOST_SAN_MISMATCH`** döndürür. |
| **7** | **§6 & §9** | Yeni teknik bulgulara göre yeni test ID'leri, çalıştırılmış vs planlanmış vs bloklu test ayrımı ve `DEC-REV-1..6` tablosu güncellenmeliydi. | 8 yeni test (`HUB-T01d`, `APP-T01c`, `APP-T05b`, `APP-T15c`, `APP-T16c`, `APP-T16e`, `HUB-T09b`, `HUB-T04c`, `HUB-T04d`) mevcut ID'ler korunarak eklendi; test statüleri katı biçimde ayrıştırıldı ve `DEC-REV-1..6` güncellendi. |

### 1.2 Projede Korunan Değişmezler (Dokunulmaz Çekirdek Mimari)

Bu tasarım revizyonu aşağıdaki mevcut MARKET MMS mimarisi ve kurallarında **hiçbir değişiklik yapmaz**:
1. **Offline-First & Dual SQLite Mimarisi:** Windows Master Hub tek-yazarlı merkezi SQLite (`market_master.db`), Windows Desktop UI (`client_local.db` üzerinden loopback API) ve Android cihazların kendi yerel Drift/SQLite veritabanlarında çalışması.
2. **Merkezi Senkronizasyon Topolojisi:** Cihazların birbirleriyle P2P değil, yalnızca Windows Master Hub üzerinden senkronize olması.
3. **Veri & Senkronizasyon Sözleşmeleri:** `outbox_operations` kuyruğu, FIFO `client_seq`, `idempotency_key`, server cursor, `device_id` ve `tenant_id`/`store_id` kimlikleri, kuruş bazlı `int`/`BIGINT` para saklama ve Half-Up yuvarlama (`OD-01`).
4. **Kapsam Sınırları:** Tek tenant/store + Owner onay modeli; Google Drive'ın yalnızca şifreli `.mmsbak` yedekleme için kullanılması; pilot aşamada PostgreSQL/Supabase kullanılmaması; Banka POS terminali entegrasyonunun kapsam dışı kalması.
5. **`ADR-018` Seçenek C — UDP `HUB_DISCOVERY_V1` v1.0 Değişmezliği:** UDP keşif yanıtı mevcut **6 alanı** (`service`, `protocol_version`, `hub_id`, `http_port`, `server_time`, `server_ips`) ve `HubDiscoveryResponder.getLocalLanIps()` semantiği ile **aynen korunur**; yeni alan eklenmez, alan çıkarılmaz, şema değiştirilmez.

---

## 2. `P-BLOCK-1` — UTF-8 Bağımsız DER/PEM Ayrıştırma, Dar `MmsX509PreValidator` ve Doğrulama Ayrımı

### 2.1 Katman 1: UTF-8'den Bağımsız PEM/DER Tespiti ve Kanonik DER SHA-256

Hub ([`certificate_manager.dart`](../test_spikes/spike_01_backend/lib/security/certificate_manager.dart)) ve Android ([`tls_pinned_client_factory.dart`](../lib/core/security/tls_pinned_client_factory.dart)) aynı girdi baytları (`Uint8List rawBytes`) için bit-düzeyinde özdeş DER byte dizisi ve 64-karakter büyük harf hex SHA-256 üretmek amacıyla **UTF-8 çözümlemesinden bağımsız** aşağıdaki deterministik **Katman 1 (`extractCanonicalSingleCertDer`)** boru hattını uygular:

| Adım / Kural | Bağlayıcı Teknik Kural (Byte-Düzeyi Öncelik) | Ret Koşulu ve Hata Kodu |
|---|---|---|
| **1. Ham Boyut Sınırı** | `4 <= rawBytes.length <= 65536` (`64 KB`). Boş dosya veya `64 KB` üzeri girdi daha ayrıştırma başlamadan reddedilir. | `< 4` veya `> 65536` byte → `INVALID_CA_CERT` / `503 ERR_CA_CERT_UNAVAILABLE` |
| **2. UTF-8 Bağımsız Biçim Sınıflandırması (`isPemCandidate`)** | Ham baytlar **hiç `utf8.decode` çağrılmadan** taranır. Aşağıdaki üç koşuldan **herhangi biri** sağlanıyorsa girdi koşulsuz **PEM Metin Yolu**na alınır:<br>(a) İlk 3 bayt UTF-8 BOM (`0xEF, 0xBB, 0xBF`) ise;<br>(b) Ham byte dizisi ASCII `-----BEGIN ` (`2D 2D 2D 2D 2D 42 45 47 49 4E 20`) dizisini içeriyorsa;<br>(c) Ham byte dizisi ASCII `-----END ` (`2D 2D 2D 2D 2D 45 4E 44 20`) dizisini içeriyorsa.<br>*Not:* `F-1` `"0x30 comment trap\n-----BEGIN CERTIFICATE-----..."` girdisinin ilk baytı `0x30` olsa bile `-----BEGIN ` byte dizisini taşıdığı için kesinlikle **PEM Yolu**na girer; asla binary DER sanılmaz. | — |
| **3A. PEM Metin Yolu (Sıkı UTF-8 + Tek Blok + Strict Base64)** | Yalnızca **PEM Yolu**nda:<br>1. Başta `0xEF, 0xBB, 0xBF` varsa ilk 3 bayt soyulur.<br>2. `utf8.decode(textBytes, allowMalformed: false)` çalıştırılır (**hata verirse asla binary DER yoluna geri düşülmez!**).<br>3. Tüm `-----BEGIN <LABEL>-----` ve `-----END <LABEL>-----` blokları taranır; `CERTIFICATE` dışındaki her etiket (`PRIVATE KEY`, `RSA PRIVATE KEY`, `EC PRIVATE KEY`, `ENCRYPTED PRIVATE KEY`, `CERTIFICATE REQUEST`, `NEW CERTIFICATE REQUEST`, `PUBLIC KEY`, `X509 CRL`), açık/eşleşmeyen etiket ve birden fazla blok reddedilir (`certCount == 1` zorunlu).<br>4. Blok gövdesinden yalnızca ASCII whitespace (`\r`, `\n`, `0x20`, `\t`) silinir ve sıkı `base64.decode` çalıştırılır (`base64` içeriği dışı veya hatalı padding reddedilir). | `utf8.decode` `FormatException`, `certCount != 1`, yasak etiket, eşleşmeyen blok veya `base64.decode` hatası → `INVALID_CA_CERT` / `503 ERR_CA_CERT_UNAVAILABLE` |
| **3B. Ham İkili (Binary) DER Yolu (Sıfır UTF-8 Bağımlılığı)** | Yalnızca `isPemCandidate == false` (BOM yok VE `-----BEGIN `/`-----END ` byte dizisi yok) ise **`utf8.decode` hiç çağrılmadan** `rawBytes` doğrudan ikili ASN.1 DER adayına alınır:<br>1. `rawBytes[0] == 0x30` (`SEQUENCE`) olmalıdır.<br>2. Definite-length **minimal DER uzunluk** kontrolü yapılır (`0x80` indefinite yasak; `len < 128` tek bayt; `len >= 128` için `0x81..0x84` öncü `0x00` yok ve `len >= 128`).<br>3. **`headerLength + contentLength == rawBytes.length`** tam eşitliği zorunludur.<br>*Etki:* Yüksek bitli (`0x80..0xFF`) gerçek binary RSA/ECDSA DER sertifikaları UTF-8 çözümlemesinden etkilenmeden deterministik kabul edilir; `"0123invalid"` veya bozuk metinler ise `0x30` sonrası uzunluk/`header+content == length` testinden asla geçemez. | Non-`0x30` ilk bayt, indefinite length `0x80`, non-minimal length, truncated DER (`len < header + content`) veya trailing byte (`len > header + content`) → `INVALID_CA_CERT` / `503 ERR_CA_CERT_UNAVAILABLE` |
| **4. Dış `SEQUENCE` Doğrulaması ve Kanonik SHA-256** | 3A'dan çıkan çözülmüş DER baytları da Adım 3B'deki aynı dış `SEQUENCE` minimal DER uzunluk ve `header + content == length` kontrolünden geçirilir. Çıktı `sha256.convert(canonicalDer)` üzerinden 64 karakter `^[0-9A-F]{64}$` büyük harf hex olarak üretilir. | 64-hex dışı veya `'UNKNOWN'` → `CA_PIN_REQUIRED` / `503 ERR_CA_CERT_UNAVAILABLE` |

> [!IMPORTANT]
> **Katman 1 Sınır Beyanı:** Katman 1 yalnızca PEM/DER konteyner ayrıştırması yapar ve kanonik SHA-256 üretir; **girdinin gerçek bir X.509 sertifikası veya CA olduğunu kanıtlamaz**. 14-baytlık sentetik `TV-DER-01` vektörü Katman 1'den geçer ancak Katman 2'de (`TV-X509-07`) reddedilir.

---

### 2.2 Katman 2: Dar `MmsX509PreValidator` Kapsamı, ASN.1/DER Sınırları ve Doğrulama Ayrımı

#### A. Mevcut Bağımlılık Gerçeği ve `MmsX509PreValidator`'ın Dar Kapsamı
Projede mevcut bağımlılık dosyaları ([`pubspec.yaml`](../pubspec.yaml), [`packages/mms_client_storage/pubspec.yaml`](../packages/mms_client_storage/pubspec.yaml), [`test_spikes/spike_01_backend/pubspec.yaml`](../test_spikes/spike_01_backend/pubspec.yaml)) harici bir ASN.1/X.509 paketi içermemektedir. Sıfırdan genel amaçlı bir PKI/imza doğrulayıcı **yazılmamasına** karar verilmiştir. `MmsX509PreValidator` kapsamı **kesin biçimde yalnızca şu 3 dar görevle sınırlandırılmıştır**:

1. **Kök CA (`ca.crt`) TLS Öncesi Yapısal Ön Kontrolü:** Hub `/pairing/session`, `/pairing/ca-cert`, `HubConfig` TLS yüklemesi ve Android Faz B sırasında `ca.crt`'nin gerçek bir X.509v3 Root CA yapısında olduğunu doğrulamak (`BasicConstraints CA=true`, `KeyUsage keyCertSign`, UTC tarih aralığı, `version == v3`, `issuerDer == subjectDer`, SAN yokluğu).
2. **Bootstrap Faz B (`B-CB-5`) İsim Ön Filtresi:** El sıkışmada yakalanan sunucu yaprak sertifikasının (`capturedLeafDer`) ham `issuerDer` baytlarını çıkarıp indirilen `ca.crt` ham `subjectDer` baytlarıyla karşılaştırmak.
3. **Sunucu (`server.crt`) IPv4 SAN Çıkarımı (`P-BLOCK-2` / `P-BLOCK-3`):** Hub startup'ta `IP:127.0.0.1` SAN varlığını (`§3.5`) ve `/pairing/session`'da LAN IP kesişimini (`§4.4`) doğrulamak için `SubjectAltName` (`OID 2.5.29.17`) içindeki `iPAddress [7]` (`0x87`, 4 bayt IPv4) kayıtlarını okumak.

**Kapsam Dışı Olanlar (Açık Sınır):** `MmsX509PreValidator` **hiçbir zaman** RSA/ECDSA/EdDSA kriptografik imza doğrulaması, ara-CA (intermediate) çok katmanlı yol inşası (`RFC 5280 §6`), CRL/OCSP iptal sorgusu, Policy Constraints veya Name Constraints graf çözümlemesi yapmaz.

#### B. İki Ayrı Doğrulama Düzlemi ve DN Eşitliği vs Kriptografik İmza Ayrımı

**CA sertifikasının OOB fingerprint doğrulaması ile sunucu sertifikasının TLS doğrulaması birbirinden tamamen ayrı iki güvenlik düzlemidir ve hiçbir aşamada birbirinin yerine geçirilemez:**

| Doğrulama Düzlemi | Doğrulanan Nesne | Doğrulama Mekanizması | Gerçekleştiren Bileşen | Ne Zaman & Neyi Kanıtlar? |
|---|---|---|---|---|
| **Düzlem 1 — OOB CA Fingerprint Doğrulaması** | Kök CA sertifikası (`ca.crt`) | Katman 1 (`extractCanonicalSingleCertDer` + `constantTimeEquals(SHA256(DER), expectedCaSha256)`) + Katman 2 (`MmsX509PreValidator` X.509v3 CA yapı/tarih/uzantı kontrolü) | Hub `/pairing/session` & Android **Faz B** | İndirilen `ca.crt`'nin **Owner'ın Windows ekranından aktardığı OOB güven köküyle bit-düzeyinde özdeş** ve geçerli yapıda bir X.509v3 CA olduğunu kanıtlar. |
| **Düzlem 2 — Gerçek TLS Zincir ve Sunucu Doğrulaması** | Sunucu yaprak sertifikası (`server.crt`) + sunucu özel anahtarı (`server.key`) | `SecurityContext(withTrustedRoots: false)..setTrustedCertificatesBytes(verifiedCaPemBytes)` ve `badCertificateCallback => false` altında gerçek TLS el sıkışması (`X509_verify_cert` + TLS `CertificateVerify`) | **BoringSSL** (Android **Faz C/D**, normal sync istemcisi ve Windows loopback/Hub startup self-check) | `server.crt`'nin **gerçekten `ca.key` tarafından imzalandığını**, karşı sunucunun **`server.key` özel anahtarına sahip olduğunu**, sertifika tarihlerinin geçerli olduğunu ve **hedef IP SAN (`127.0.0.1` veya LAN IP) ile eşleştiğini** kriptografik olarak kanıtlar. |

**DN Bayt Eşitliği Kuralı (Korunur):**
- `issuerDer == subjectDer` (Kök CA öz-kontrolü) ve `caDer.subjectDer == leafDer.issuerDer` (`B-CB-5`) kontrolleri **yalnızca yapısal/isim ön filtresidir; kriptografik imza doğrulaması DEĞİLDİR**. Herhangi bir saldırgan sahte bir sertifikanın `Issuer` alanına gerçek CA'nın `Subject` baytlarını kopyalayabilir. Gerçek imza doğrulaması **yalnızca BoringSSL tarafından Faz C/D TLS el sıkışmasında** (ve Hub startup loopback/self-check doğrulamasında) gerçekleştirilir.

#### C. `MmsX509PreValidator` ASN.1/DER Ayrıştırma Sınırları ve Hata Davranışları

| Sınır / Denetim Alanı | Bağlayıcı ASN.1 / DER Teknik Sınırı | Hata Davranışı (Fail-Closed) |
|---|---|---|
| **Parser Mimarisi & Bellek Güvenliği** | Özyinelemesiz (iterative `cursor`, `start`, `end`) okuyucu; girdi `4..65536` byte; maksimum iç içe konteyner derinliği **`<= 8`**; her TLV okumada `headerEnd + contentLength <= parentEnd` kontrolü; her bileşik yapının sonunda `cursor == containerEnd` (artık bayt yasak). | `X509PreValidationException('INVALID_CA_CERT', ...)` → Hub: `503 ERR_CA_CERT_UNAVAILABLE`, Android: `DevicePairingException('INVALID_CA_CERT')` |
| **DER Kanonik Tag / Length / Primitive Kuralları** | Indefinite length (`0x80`) yasak; non-minimal uzunluk baytları yasak; `INTEGER (0x02)` boş olamaz ve gereksiz öncü `0x00`/`0xFF` içeremez; `BIT STRING (0x03)` en az 1 bayt (`unusedBits in 0..7`), boş `BIT STRING` yalnızca `03 01 00` ve son baytın kullanılmayan alt `unusedBits` bitleri `0` olmalıdır; `BOOLEAN (0x01)` uzunluğu `1` ve değeri yalnızca `0x00` veya `0xFF` olabilir. | `X509PreValidationException('INVALID_CA_CERT', ...)` |
| **Dış `Certificate` & `TBSCertificate` (`RFC 5280`)** | Dış `SEQUENCE`: tam 3 alan (`tbsCertificate 0x30`, `outerSignatureAlgorithm 0x30`, `signatureValue 0x03` boş olmayan ve `unusedBits == 0`).<br>`TBSCertificate`: `version [0] EXPLICIT` zorunlu ve `== 2` (**X.509 v3** — v1/v2 **RED**), `serialNumber 0x02` (`1..21` byte, boş/negatif RED), **`tbsSignatureAlgorithm == outerSignatureAlgorithm` ham DER bayt eşitliği zorunlu**, boş olmayan `issuer 0x30`, `validity 0x30`, boş olmayan `subject 0x30`, `subjectPublicKeyInfo 0x30` (`alg 0x30` + `key 0x03` boş olmayan), sıralı opsiyonel `[1]`/`[2]`, ve Root CA doğrulamasında zorunlu `[3] EXPLICIT Extensions (0xA3)`. | `X509PreValidationException('INVALID_CA_CERT', ...)` |
| **`Validity` (`UTCTime` / `GeneralizedTime`)** | Tam 2 zaman alanı (`notBefore`, `notAfter`). `UTCTime (0x17)`: tam 13 ASCII byte `YYMMDDHHMMSSZ` (`50..99` → `1950..1999`, `00..49` → `2000..2049`); `GeneralizedTime (0x18)`: tam 15 ASCII byte `YYYYMMDDHHMMSSZ`. Kesirli saniye, yerel saat ve `+HHMM`/`-HHMM` ofsetleri yasaktır. Kapalı geçerlilik aralığı: `!nowUtc.isBefore(notBefore) && !nowUtc.isAfter(notAfter)`. | Süre dolmuşsa `CA_CERT_EXPIRED`, henüz geçersizse `CA_CERT_NOT_YET_VALID` (Hub `/pairing/*`: `503 ERR_CA_CERT_UNAVAILABLE`) |
| **`Extensions` (Kök CA Modu)** | Her `Extension`: `extnID (0x06)`, opsiyonel `critical (0x01)` (**yalnızca `0xFF` kabul; `0x00` explicit `FALSE` non-canonical DER olarak RED**), `extnValue (0x04)`. Aynı OID tekrarı anında **RED**. Zorunlu:<br>1. `BasicConstraints` (`2.5.29.19`): `SEQUENCE` ilk elemanı `01 01 FF` (`cA == TRUE`) zorunlu; varsa `pathLenConstraint` (`>= 0`); artık alan RED.<br>2. `KeyUsage` (`2.5.29.15`): `BIT STRING` etkin bit sayısı `>= 6` ve MSB bit 5 (**`keyCertSign`**, `flags0 & 0x04 != 0`) zorunlu.<br>3. `SubjectAltName` (`2.5.29.17`) Root CA'da yasaktır (`OWNER_ACTION_CHECKLIST.md` §B2 uyumu). | `ERR_DUPLICATE_X509_EXTENSION`, `ERR_CA_BASIC_CONSTRAINTS_MISSING_OR_FALSE`, `ERR_CA_KEY_USAGE_MISSING_KEY_CERT_SIGN`, `INVALID_CA_CERT` → Hub `503 ERR_CA_CERT_UNAVAILABLE` |
| **Hub Startup vs Pairing Farkı** | `requireTls == true` iken Hub başlangıcında `ca.crt` veya `server.crt` X.509 yapı doğrulaması başarısızsa Hub başlamaz. | Hub startup: `HubConfigException` / `TlsConfigurationException` (çıkış `78`) |

---

### 2.3 Ortak Test Sertifikası (`kSharedTestRootCaPem`), `generateRootCa` ve Gerçek X.509 Test Vektörleri

1. **Ortak Gerçek Test CA Fikstürü (`kSharedTestRootCaPem`):**
   - Hub (`test_spikes/spike_01_backend/test/`) ve Android (`test/core/security/`) aynı deterministik gerçek **X.509v3 Root CA PEM** fikstürünü paylaşır (`RSA-2048`, `Version: 3`, `CN=MMS Canonical Test Root CA`, `BasicConstraints: critical, CA:TRUE`, `KeyUsage: critical, keyCertSign, cRLSign`, SAN yok, uzun geçerlilik penceresi).
   - Her iki taraf aynı `kSharedTestRootCaPem` dosyasını (ve BOM + CRLF + `"0x30 comment trap"` varyasyonunu) ve ham ikili **DER çıktısını (`kSharedTestRootCaDerBytes`, yüksek bitli `>= 0x80` baytlar içerir!)** Katman 1 + Katman 2'den geçirir; tüm varyantlar özdeş **`kSharedTestRootCaSha256`** değerini üretir.
   - **Test Anahtarı Sınırı:** Test CA özel anahtarları yalnızca geçici/otomatik testlerde bulunur; üretim Hub (`%ProgramData%\MarketMMS\certs\`) ortamında **KESİNLİKLE kullanılamaz**.
2. **`CertificateManager.generateRootCa` OpenSSL Güncelleme Zorunluluğu:**
   - Mevcut [`certificate_manager.dart:60-86`](../test_spikes/spike_01_backend/lib/security/certificate_manager.dart#L60-L86) `generateRootCa` komutuna `-addext basicConstraints=critical,CA:TRUE` ve `-addext keyUsage=critical,keyCertSign,cRLSign` zorunlu olarak eklenir; böylece üretilen her yerel test CA'sı Katman 2 ve BoringSSL ile %100 uyumlu olur.
3. **Katman 1 (`TV-DER-01..05`) vs Katman 2 Gerçek X.509 Vektörleri (`TV-X509-01..09`):**
   - **Sentetik 14-Bayt DER Vektörleri (`TV-DER-01..05` — Yalnızca Katman 1 Hash & Konteyner Testi):**
     - Baytlar: `30 0C 30 0A 02 01 01 06 03 55 1D 11 05 00` (`Base64: MAwwCgIBAQYDVR0RBQA=`), Beklenen SHA-256: `75920A4AF20B64B42B647CDFC23AA88C31C41D3EC7508B71D3501638FA433316`.
     - `TV-DER-01` (Ham DER), `TV-DER-02` (LF PEM; eski ham UTF-8 hash: `A9B04113C7A4CA21FA3A0C285FF9B813C6BB19DC4308D4FFA51D6DAC6CA11049`), `TV-DER-03` (UTF-8 BOM + yorum + CRLF; eski ham UTF-8 hash: `EB827DB9C79D0F00875BF0FB5E508081B9847DEFDF40055FA4DCA06AA23069FB`), `TV-DER-04` (`F-1` `"0x30 comment trap"`; eski ham hash: `A201165E602A282374E8FE2802EBDB0992C2B744AA52A6D3597A5536389ECE4A`), `TV-DER-05` (2 `CERTIFICATE` bloğu, `BEGIN PRIVATE KEY`, bozuk Base64, truncated DER, non-`0x30` metin, BOM + bozuk UTF-8, bozuk UTF-8 + `-----BEGIN CERTIFICATE-----`).
   - **Gerçek X.509v3 Test Vektörleri (`TV-X509-01..09` — Katman 2 + Binary DER Sınırları):**
     1. `TV-X509-01`: Geçerli X.509v3 Root CA (`kSharedTestRootCaPem` PEM **ve** ham yüksek-bitli binary DER kopyası) → **KABUL** (özdeş `kSharedTestRootCaSha256`).
     2. `TV-X509-02`: `CA:FALSE` yaprak sunucu sertifikası (`server.crt`) → **RED** (`ERR_CA_BASIC_CONSTRAINTS_MISSING_OR_FALSE`).
     3. `TV-X509-03`: `BasicConstraints CA:TRUE` var ama `keyCertSign` eksik CA (yalnızca `digitalSignature`) → **RED** (`ERR_CA_KEY_USAGE_MISSING_KEY_CERT_SIGN`).
     4. `TV-X509-04`: X.509 v1 sertifika (`Extensions` yok) → **RED** (`INVALID_CA_CERT`).
     5. `TV-X509-05`: Expired CA (`notAfter < nowUtc`) → **RED** (`CA_CERT_EXPIRED`).
     6. `TV-X509-06`: Not-yet-valid CA (`notBefore > nowUtc`) → **RED** (`CA_CERT_NOT_YET_VALID`).
     7. `TV-X509-07`: Sentetik 14-bayt DER (`TV-DER-01`) veya non-canonical `critical: FALSE`, duplicate OID, `outerSigAlg != tbsSigAlg`, trailing byte, derinlik > 8 → **RED** (`INVALID_CA_CERT`).
     8. `TV-X509-08`: Bozuk PEM / bozuk Base64 / UTF-8 dışı PEM / `-----BEGIN ` içeren bozuk baytlar → **RED** (`INVALID_CA_CERT`).
     9. `TV-X509-09`: Çoklu sertifika bundle (`certCount >= 2`) veya Root CA içinde `SubjectAltName` → **RED** (`INVALID_CA_CERT`).

### 2.4 `P-BLOCK-1` Hata Kodları ve Hub ↔ Android Sözleşmesi

| Durum | Hub API Kodu (`/pairing/session`, `/pairing/ca-cert`) | Android / Client Hatası |
|---|---|---|
| Geçersiz PEM/DER, `certCount != 1`, Private Key, bozuk Base64, bozuk UTF-8/BOM, trailing byte, derinlik aşımı | HTTP `503` · `ERR_CA_CERT_UNAVAILABLE` | `DevicePairingException('INVALID_CA_CERT', ...)` |
| `CA:FALSE` yaprak, `keyCertSign` eksik, v1 sertifika, duplicate OID, `outerSigAlg != tbsSigAlg`, CA'da SAN | HTTP `503` · `ERR_CA_CERT_UNAVAILABLE` | `DevicePairingException('INVALID_CA_CERT', ...)` |
| Süresi dolmuş (`notAfter < now`) veya henüz geçerli olmamış (`notBefore > now`) CA | HTTP `503` · `ERR_CA_CERT_UNAVAILABLE` | `DevicePairingException('CA_CERT_EXPIRED' / 'CA_CERT_NOT_YET_VALID', ...)` |
| `ca_fingerprint` eksik, `'UNKNOWN'` veya 64-hex değil | Hub `requireTls` açıkken `503 ERR_CA_CERT_UNAVAILABLE` (`'UNKNOWN'` yasak) | `DevicePairingException('CA_PIN_REQUIRED', ...)` (ağ isteği başlamaz) |

---

## 3. `P-BLOCK-2` — İlk HTTPS Bootstrap, Proxy/Sıkıştırma/Timeout, Crash-Safe `ACK_PENDING` Re-pairing ve Localhost SAN

### 3.1 `ALT-BOOT-2` Bootstrap İstemcisi Mutlak İzolasyonu ve TLS Gevşetme Yasağı

Mevcut [`DevicePairingClient.pairDevice`](../lib/features/security/data/device_pairing_client.dart#L81-L139) akışındaki bootstrap handoff boşluğunu gidermek için **`ALT-BOOT-2` (`RECOMMENDED`)** korunur:

- **Tek İzinli Endpoint:** `_fetchBootstrapCaCertPem(...)` metodu içindeki geçici `HttpClient` **yalnızca `GET https://<targetHost>:<targetPort>/api/v1/pairing/ca-cert`** çağrısı yapabilir. Başka bir yol, metod (`POST`/`PUT`) veya `http://` şeması çağrısı yapısal olarak engellenir.
- **Sıfır-Sır (Zero Secrets) Garantisi:** Bootstrap isteği sırasında **hiçbir** `device_token`, `pairing_secret`, `admin_secret`, `session_id`, `device_id`, `tenant_id`, `store_id`, `client_public_key`, `Authorization` başlığı veya çerez gönderilmez.
- **Yaşam Döngüsü ve Referans İzolasyonu:** `bootstrapClient` yerel değişkendir; metot dışına döndürülemez, yeniden kullanılamaz ve her çıkış dalında `finally { bootstrapClient.close(force: true); }` ile yok edilir.
- **Faz C / Faz D ve Normal Senkronizasyon İstemcilerinde TLS Gevşetme Yasağı:** CA sertifikası Faz B'de OOB pin + `MmsX509PreValidator` doğrulamasından geçtikten sonra Faz C'de `SecurityContext(withTrustedRoots: false)..setTrustedCertificatesBytes(verifiedCaPemBytes)` ile **yeni bir CA-pinned `HttpClient`** kurulur. Faz C/D (`/request`, `/poll-challenge`, `/poll`, `/ack-challenge`, `/ack`) istemcilerinde ve normal senkronizasyon (`MmsApiClient`, `HttpSyncTransport`) istemcilerinde **`badCertificateCallback` daima `false` döner**; TLS doğrulamasının gevşetilmesi (`=> true`), leaf-pin bypass'ı veya `http://` downgrade kesinlikle yasaktır.

#### `B-CB-1..6` Bootstrap TLS Callback Kesin Şartnamesi

| Kural | Kontrol Edilen Veri | Yapıldığı Aşama | Kabul Koşulu | Ret Koşulu | Hata Kodu | Test Senaryosu |
|---|---|---|---|---|---|---|
| **`B-CB-1`** | `expectedCaSha256`, `hubUri.scheme`, `hubUri.path` | Faz A (Soket açılmadan hemen önce + callback girişi) | `expectedCaSha256` 64-hex valid, şema `https`, hedef yol tam `/api/v1/pairing/ca-cert`. | Pin null/`'UNKNOWN'`/geçersiz hex veya `http://` şema veya başka path. | `CA_PIN_REQUIRED` / `TLS_SCHEME_REQUIRED` | `APP-T02`, `APP-T12` |
| **`B-CB-2`** | Callback parametreleri `(host, port)` vs `targetUri.host` & `effectivePort(targetUri)` | Faz A TLS `badCertificateCallback` içi | `host == targetUri.host && port == effectivePort(targetUri)`. | Farklı host veya porttan gelen el sıkışma (ör. proxy/yönlendirme girişimi). | `BOOTSTRAP_HOST_MISMATCH` (`HandshakeException` fail-closed) | `APP-T05`, `APP-T05b`, `APP-T09` |
| **`B-CB-3`** | `callbackInvocationCount` | Faz A TLS `badCertificateCallback` içi | Aynı izole bootstrap isteğinde ilk kez çağrılıyor (`++count == 1`). | `count > 1` (yeniden yönlendirme veya ikinci TLS oturumu). | `BOOTSTRAP_REDIRECT_FORBIDDEN` / `HandshakeException` | `APP-T04`, `APP-T05` |
| **`B-CB-4`** | `cert.der`, `cert.startValidity`, `cert.endValidity`, `nowUtc` | Faz A TLS `badCertificateCallback` içi | `cert.der.isNotEmpty`, `!nowUtc.isBefore(cert.startValidity.toUtc())`, `!nowUtc.isAfter(cert.endValidity.toUtc())`. | Boş DER veya süresi dolmuş (`expired`) ya da henüz geçerli olmamış (`notYetValid`) sunucu yaprak sertifikası. | `TLS_CERT_ERROR` (`certificateExpired` / `certificateNotYetValid`) | `APP-T10`, `APP-T09` |
| **`B-CB-5`** | `capturedLeafDer` (`issuerDer` baytları) vs indirilen `ca.crt` `subjectDer` baytları | Callback `capturedLeafDer = cert.der` alır; kontrol Faz B'de yapılır | `MmsX509PreValidator` her iki `Name` yapısını çıkarır ve `ca.subjectDer == leaf.issuerDer` eşleşir. *(Not: Yalnızca hızlı isim ön filtresidir; kriptografik CA→Leaf imza doğrulaması Faz C/D'de BoringSSL ile yapılır.)* | Yaprak `issuerDer` ile indirilen CA `subjectDer` uyuşmazsa (ör. self-signed ilgisiz yaprak). | `CA_PIN_MISMATCH` / `INVALID_CA_CERT` | `APP-T17`, `APP-T18` |
| **`B-CB-6`** | `bootstrapClient` (`idleTimeout = Duration.zero`, `persistentConnection = false`, `findProxy = DIRECT`, `autoUncompress = false`) | Faz A `try { ... } finally { bootstrapClient.close(force: true); }` | Tek istek sonrasında `close(force: true)` mutlaka 1 kez çağrılır; referans Faz C/D'ye sızmaz. | Referans sızması veya açık soket kalması (statik/tip izolasyonu ile engellenir). | — (Güvenlik garantisi) | `APP-T08`, `APP-T09` |

---

### 3.2 OOB Fingerprint Güven Kökü ve `M3` Güven Sınırı

- **Tek Güven Kökü:** Owner'ın Windows `PairingApprovalPanel` ekranında (`127.0.0.1` + `requireAdminSession` arkasında Hub dosya sistemindeki `ca.crt` üzerinden hesaplanıp gösterilen) doğrudan gördüğü **64-hex `ca_fingerprint`** değerini Android `DeviceSecurityCard` OOB güvenlik alanına fiziksel olarak aktarması/doğrulamasıdır.
- **Bağlayıcı Kurallar:**
  - Ağdan veya yapıştırılan JSON payload'dan gelen `ca_fingerprint` **tek başına güven kökü değildir**.
  - OOB fingerprint eksikse veya `'UNKNOWN'` ise **sıfır ağ isteğiyle** `CA_PIN_REQUIRED` döner.
  - OOB ve JSON `ca_fingerprint` uyuşmuyorsa Faz A başlamadan **`OOB_FINGERPRINT_MISMATCH`** ile durur.
  - Fingerprint 64 karakterlik hex SHA-256 (`^[0-9A-F]{64}$`) olmalıdır; kısalmış prefix yasaktır.
  - Karşılaştırma **constant-time (`constantTimeEquals`)** yapılır.
  - İndirilen gerçek CA sertifikasının Katman 1 kanonik DER SHA-256 özeti OOB pin ile karşılaştırılır; CA Katman 1+2 ve OOB pin doğrulaması geçilmeden hiçbir pin veya token kaydedilmez.
- **`M3` Saldırısı ve OOB Bütünlüğü Güven Sınırı (Gerçekçi Beyan):**
  - Saldırgan yalnızca taşıma/paylaşım kanalını değiştirirse `OOB_FINGERPRINT_MISMATCH` ile engellenir.
  - Ancak saldırgan Windows Hub işletim sistemini tamamen ele geçirmişse veya Owner'ın bizzat okuduğu OOB fingerprint'i ve sunulan CA'yı aynı anda kontrol edebiliyorsa (`M3`), ilk eşleştirmede kriptografik TLS pinleme bunu engelleyemez. Kalan savunma katmanları: mevcut cihazda Re-pairing kilidi ve gerçek Master Hub'da Owner `/approve` `publicKeyFingerprint` denetimidir.

---

### 3.3 Bootstrap HTTP İletişim Sınırları (Proxy, Sıkıştırma, Redirect, Çelişkili Gövde ve Mutlak Timeout)

Dart `dart:io` `HttpClient` incelemesinde yerleşik `responseHeaderTimeout`/`totalBodyTimeout` bulunmadığı, `Stream.timeout` metodunun her yeni chunk geldiğinde sıfırlandığı (Slowloris damla saldırısını durdurmadığı) ve `HttpClient.autoUncompress` ile sistem `findProxy`'nin varsayılan açık olduğu saptanmıştır. Bootstrap istemcisinde aşağıdaki **8 bağlayıcı HTTP sınırı** zorunludur:

| Koruma Alanı | Kullanılan Gerçek Dart Mekanizması | Kesin Sınır & İptal Davranışı | Hata Kodu |
|---|---|---|---|
| **1. Proxy Bypass Yasağı (`DIRECT`)** | `bootstrapClient.findProxy = (Uri _) => 'DIRECT';` | Sistem veya ortam değişkeni (`HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`) üzerinden HTTP `CONNECT` proxy tünellemesi tamamen devre dışı bırakılır. | `BOOTSTRAP_PROXY_FORBIDDEN` / `HandshakeException` |
| **2. Sıkıştırma (Compression) Yasağı** | `bootstrapClient.autoUncompress = false;` + istekte `request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');` | Yanıtta `Content-Encoding` başlığı mevcutsa ve trim/lowercase değeri `'identity'` dışında bir kodlama (`gzip`, `deflate`, `br`, `x-gzip` vb.) içeriyorsa **tek bayt gövde okunmadan** akış reddedilir ve soket kapatılır (decompression bomb & boyut çelişkisi engeli). | `INVALID_CA_CERT` |
| **3. TCP/TLS Bağlantı Timeout'u** | `bootstrapClient.connectionTimeout = const Duration(seconds: 5);` + `bootstrapClient.getUrl(uri).timeout(const Duration(seconds: 5))` | TCP kurulumu veya TLS el sıkışması 5 sn içinde bitmezse soket zorla kapatılır. | `BOOTSTRAP_TIMEOUT` |
| **4. HTTP Response Header Timeout'u** | `request.followRedirects = false; request.maxRedirects = 0; request.persistentConnection = false;` ardından `await request.close().timeout(const Duration(seconds: 5))` | Sunucu 5 sn içinde HTTP durum kodu ve başlıkları dönmezse `finally` içinde `close(force: true)` çalışır. | `BOOTSTRAP_TIMEOUT` |
| **5. Redirect ve Durum Kodu Reddi** | `response.statusCode` denetimi: `301/302/303/307/308` (`3xx`) ve `!= 200` | `Location` başlığı okunmaz/takip edilmez; soket `close(force: true)` ile kapatılır. | `BOOTSTRAP_REDIRECT_FORBIDDEN` (`3xx`) / `BOOTSTRAP_FETCH_FAILED` (`!= 200`) |
| **6. Ön `Content-Length` & `64 KB` Akış Sınırı** | Ön kontrol: `if (response.contentLength == 0 || response.contentLength < -1 || response.contentLength > 65536)` hemen reddet.<br>Akış içi: `totalBytes += chunk.length; if (totalBytes > 65536)` (**`65.537`'nci bayt**) → stream aboneliği anında iptal edilir. | `65.536` byte (`64 KB`) sınırı her durumda zorlanır; sahte küçük `Content-Length` veya chunked akış taşması durdurulur. | `INVALID_CA_CERT` |
| **7. Çelişkili HTTP Gövdesi (`Content-Length` Uyuşmazlığı) Reddi** | Akış içi: `if (response.contentLength > 0 && totalBytes > response.contentLength)` anında kes.<br>Akış bitişi (`onDone`): `if (totalBytes == 0 || (response.contentLength >= 0 && totalBytes != response.contentLength))` reddet. | Eksik gönderilmiş (erken `EOF`), boş veya bildirilen `Content-Length` değerinden fazla/az bayt içeren çelişkili yanıtlar asla sertifika ayrıştırıcısına verilmez. | `INVALID_CA_CERT` |
| **8. Mutlak Duvar Saati Body Timeout'u (Slowloris) & Kapatma** | `Stream.timeout` **YASAKTIR**. Stream dinlenirken **sıfırlanmayan tek seferlik `Timer(const Duration(seconds: 5), ...)`** + `Completer<Uint8List>` başlatılır; `finally { bodyTimer?.cancel(); await subscription?.cancel(); bootstrapClient.close(force: true); }`. | 5 sn duvar saati dolduğunda (saldırgan 1 byte/sn damlatsa bile) akış kesilir; tüm dallarda `close(force: true)` kesin çağrılır. | `BOOTSTRAP_TIMEOUT` |

---

### 3.4 Crash-Safe Re-pairing (`POLL_RECEIVED → ACK_PENDING → ACK_CONFIRMED → P1..P4`) ve Sunucu İdempotent `/ack`

#### Mevcut Depolama Mimarisi ve Önceki Tasarımdaki Kritik Çökme Boşluğu
Mevcut kod tabanında eşleştirme sonrası kalıcı durum **üç ayrı fiziksel depoda** tutulmaktadır:
1. **`device_token`** (`device_token::<deviceId>`): [`SecureTokenStore`](../lib/core/security/secure_token_store.dart) — Windows DPAPI (`secure_tokens.dpapi.json`) ve Android Keystore (`AndroidKeystoreTokenStore`).
2. **`pinnedCaSha256` & `pinnedCaPem`**: [`FileSetupConfigStore`](../lib/features/setup/data/local_setup_config_store.dart#L39-L84) (`client_config.json`, `.tmp` + rename).
3. **`activeHubUrl`**: SQLite `local_client_settings` ([`HubConnectionNotifier.setHubUrl`](../lib/features/sync/application/hub_connection_notifier.dart#L324-L366)).

**Tespit Edilen Çökme Açığı (Hub `/ack`'yı İşledi ama Android Yanıtı Alamadan Çöktü):**
- Mevcut [`DevicePairingClient.pairDevice`](../lib/features/security/data/device_pairing_client.dart#L213) `/poll` sonrasında aktif token'ı erken ezmektedir.
- Önceki `POLL_RECEIVED → ACK_CONFIRMED` tasarımında ise Android `/ack` isteğini göndermeden önce `POLL_RECEIVED` kaydında kalıyordu. Eğer **Hub `POST /api/v1/pairing/ack` isteğini başarıyla işleyip** (`challenge.isConsumed = true`, `deliveryBuffer.acknowledge()`, `devices.isConfirmed = true`, `session.status = completed`) HTTP `200 OK` dönerken **Android yanıtı alamadan çökerse / ağ koparsa**:
  1. Android yeniden başlatıldığında `POLL_RECEIVED` durumunu görüp kaydı siler ve Hub'ın zaten aktive ettiği yeni token'ı kaybederdi;
  2. Mevcut Hub kodunda ([`pairing_manager.dart:504,549,574`](../test_spikes/spike_01_backend/lib/security/pairing_manager.dart#L504-L581)) `/ack` tekrar gönderildiğinde `409 CHALLENGE_ALREADY_CONSUMED`, `410 TOKEN_BUFFER_EXPIRED` veya `/ack-challenge` tekrarında `403 SESSION_NOT_APPROVED` dönmektedir;
  3. Aynı şekilde Re-pairing sırasında Hub tarafında eski `devices` kaydının `/ack` teyit edilmeden geçersiz kılınması/çakışması risk oluşturur.

#### Çözüm 1: Sunucu (Hub) Tarafında İdempotent `/ack` ve Kimlik Korunumu
1. **Ham Token'ın RAM'den Silinmeye Devam Etmesi + Doğrulama Özetinin Korunması:**
   - Hub `/ack` isteğini ilk kez başarıyla doğrulayıp `deliveryBuffer.acknowledge` çalıştırdığında güvenlik kuralı gereği ham `rawToken` değerini RAM'den temizlemeye devam eder (`item.rawToken = ''`).
   - Ancak `PairingSession` üzerinde (5 dakikalık oturum TTL süresi dolana dek) yalnızca sırsız doğrulama özetleri saklanır: **`confirmedTokenSha256`** (`Uint8List`, 32 bayt), **`confirmedAckChallengeId`** (`String`) ve **`confirmedAckChallengeNonce`** (`Uint8List`).
2. **Aynı `/ack` İsteğinin Güvenli İdempotent Tekrarı (`POST /api/v1/pairing/ack`):**
   - `session.status == PairingSessionStatus.completed` iken aynı `session_id` + `ack_challenge_id == session.confirmedAckChallengeId` ile tekrar `POST /api/v1/pairing/ack` gelirse Hub `409 CHALLENGE_ALREADY_CONSUMED` veya `410 TOKEN_BUFFER_EXPIRED` **DÖNDÜRMEZ**.
   - Hub gelen `signature` alanını `session.clientPublicKeyBytes`, `session.confirmedAckChallengeNonce` ve `session.confirmedTokenSha256` üzerinden 7 alanlı Token-Bound ECDSA P-256 kanonik çerçevesiyle **yeniden kriptografik olarak doğrular** (`EcdsaSignatureValidator.verifySignature`):
     - İmza geçerliyse: Veritabanında mükerrer `isConfirmed`/audit yazımı yapmadan **HTTP `200 OK`** (`{"status": "CONFIRMED", "session_id": ..., "device_id": ..., "idempotent_replay": true}`) döner.
     - İmza geçersizse: **`403 INVALID_ACK_TOKEN_HASH_SIGNATURE`** döner (sahte replay engellenir).
     - `ack_challenge_id` bilinen son challenge değilse `404 CHALLENGE_NOT_FOUND` veya `409 CHALLENGE_ALREADY_CONSUMED` döner.
3. **Oturum TTL İçinde Yeni Challenge ile `/ack-challenge` Tekrarı:**
   - İstemci ilk `/ack` isteğini ağa yollayamadan çöktüyse ve 60 sn challenge süresi dolup 5 dk oturum TTL'i henüz dolmadıysa, `issueAckChallenge` `session.status == PairingSessionStatus.completed` durumunda da (yalnızca `pairing_secret` doğruysa ve kota dahilindeyse) yeni `ACK` challenge üretir; ardından gelen `/ack` imzası `confirmedTokenSha256` ile doğrulanarak idempotent **`200 OK`** döner.
4. **Re-pairing Sırasında Hub Tarafında Eski Cihaz Kaydının Korunması:**
   - Eğer aynı `device_id` ile daha önce eşleştirilmiş ve aktif (`isActive == true`, `isConfirmed == true`) bir cihaz yeniden eşleştirme onayından geçiyorsa, eski aktif `devices.tokenHash`/`salt` kaydı `/request`, `/approve` veya `/poll` aşamasında **bozulmaz/silinmez**; yeni `tokenHash`/`salt` yalnızca `/ack` kriptografik olarak doğrulandığında atomik SQLite transaction içinde güncellenir. (İptal edilmiş/`isActive == false` cihazlar için mevcut `DEVICE_ALREADY_REVOKED` engeli korunur.)

#### Çözüm 2: İstemci 4-Aşamalı Kalıcı Durum Makinesi (`POLL_RECEIVED → ACK_PENDING → ACK_CONFIRMED → P1..P4`)
1. **Çakışma Kapısı (Değişmez):** `setup.pinnedCaSha256 != null && setup.pinnedCaSha256 != expectedCaSha256` ise ağ isteği başlamadan `REPAIRING_CA_CHANGE_CONFIRMATION_REQUIRED` sorulur; reddedilirse hiçbir depo değiştirilmez.
2. **Aşama 1 — `POLL_RECEIVED` (`/poll` Başarısı):**
   - Aktif `device_token::<deviceId>`, `pinnedCaSha256`, `pinnedCaPem` ve `activeHubUrl` değerlerine **DOKUNULMAZ**.
   - `SecureTokenStore` içine `pairing_staged::<deviceId>` anahtarıyla şu JSON yazılır:
     `{"stage": "POLL_RECEIVED", "session_id": ..., "pairing_secret": ..., "token": rawToken, "ca_sha256": verifiedCaSha256, "ca_pem": verifiedCaPem, "hub_url": cleanBaseUrl}`.
3. **Aşama 2 — `ACK_PENDING` (`POST /api/v1/pairing/ack` Ağa Gönderilmeden HEMEN ÖNCE Kalıcı Yazım):**
   - `/ack-challenge` yanıtı alınıp 7 alanlı Token-Bound ECDSA P-256 `ackSignature` üretildikten sonra, **HTTP `/ack` isteği sokete yazılmadan hemen önce** `pairing_staged::<deviceId>` kaydı atomik olarak güncellenir:
     `stage = "ACK_PENDING"`, `ack_challenge_id = ackChallengeId`, `ack_signature_b64 = base64Encode(ackSig)`.
   - Bu anda dahi eski `device_token::<deviceId>`, `pinnedCaSha256`, `pinnedCaPem` ve `activeHubUrl` %100 korunmaktadır.
4. **Aşama 3 — `ACK_CONFIRMED` (Kesinleşme Noktası / Commit Point):**
   - `POST /api/v1/pairing/ack` (ilk çağrıda veya idempotent tekrarda) HTTP `200 OK` döndürdüğü anda `pairing_staged::<deviceId>` kaydı **`stage = "ACK_CONFIRMED"`** olarak güncellenir.
5. **Aşama 4 — İdempotent Terfi (`P1 → P2 → P3 → P4`):**
   - **P1:** `await tokenStore.saveDeviceToken(deviceId, staged.token)`
   - **P2:** `await setupConfigNotifier.updateTlsPinning(enabled: true, sha256Hex: staged.caSha256, caCertPem: staged.caPem)` (`client_config.json` `.tmp` + rename)
   - **P3:** `await hubConnectionNotifier.setHubUrl(staged.hubUrl, source: HubUrlSource.manual)`
   - **P4:** `await tokenStore.deleteSecret('pairing_staged::$deviceId')`
6. **Aşama 5 — Başlangıç ve Ağ Kurtarma Toparlanması (`reconcileStagedPairingOnStartup`):**
   - Uygulama açılışında senkronizasyon başlamadan önce `pairing_staged::<deviceId>` kontrol edilir:
     - **`stage == "POLL_RECEIVED"`:** `/ack` henüz hiç gönderilmemiştir → staging kaydı silinir, **eski aktif `device_token`, `pinnedCaSha256`, `pinnedCaPem` ve `activeHubUrl` korunur**.
     - **`stage == "ACK_PENDING"`:** İstemci `ack` gönderirken veya yanıtı beklerken çökmüştür. CA-pinned istemci (`staged.caPem` + `staged.caSha256`) üzerinden:
       1. Kayıtlı `(session_id, ack_challenge_id, ack_signature_b64)` ile aynı `POST /api/v1/pairing/ack` **idempotent olarak tekrar gönderilir**. `200 OK` dönerse → `ACK_CONFIRMED` → `P1..P4` tamamlanır.
       2. `410 CHALLENGE_EXPIRED` veya `404 CHALLENGE_NOT_FOUND` (ilk paket Hub'a ulaşmamış ve 60 sn challenge dolmuş) alınırsa, kayıtlı `pairing_secret` ve `token` ile yeni `/ack-challenge` + `/ack` gönderilir. `200 OK` → `ACK_CONFIRMED` → `P1..P4`.
       3. `404 SESSION_NOT_FOUND` veya `410 SESSION_EXPIRED` (5 dk oturum dolmuş veya Hub yeniden başlamış) alınırsa: yeni CA-pinned istemci + `Bearer <staged.token>` ile salt-okunur doğrulama yoklaması (`GET /api/v1/products?limit=1`) yapılır.
          - HTTP `200 OK`: Hub çökme öncesi `/ack`'yı SQLite'a (`isConfirmed = true`) işlemiştir → `ACK_CONFIRMED` → `P1..P4` tamamlanır.
          - HTTP `401` / `403`: Hub yeni token'ı aktive etmemiştir (unconfirmed temizlendi) → staging silinir, **eski aktif kimlik ve eski pin korunur**.
          - Ağ hatası (`SocketException` / `TimeoutException` — ör. Hub kapalı/LAN yok): `ACK_PENDING` **silinmez** ve **eski aktif kimlik/pin ezilmez**; cihaz çevrimdışı POS çalışmasına devam eder ve bir sonraki Hub erişiminde tekrar mutabakat yapar.
     - **`stage == "ACK_CONFIRMED"`:** `P1 → P2 → P3 → P4` idempotent biçimde tamamlanır.

#### 10 Hata ve Crash Durumu Matrisi (Outbox & Kimlik Dokunulmazlığı)

| # | Durum / Crash Senaryosu | `pinnedCaSha256` & `pinnedCaPem` | `device_token` & `activeHubUrl` | `outbox_operations`, `client_seq`, `device_id`, `tenant_id`, `store_id` | Yeniden Başlatma / Toparlanma |
|---|---|---|---|---|---|
| **1** | Re-pairing kullanıcı tarafından reddedildi | Eski değerler korunur | Eski değerler korunur | **Hiçbirine dokunulmaz (0 değişiklik)** | Eski pin + token ile normal sync devam eder |
| **2** | Faz A Bootstrap başarısız (`timeout`/`redirect`/`proxy`/`gzip`/`>64 KB`) | Eski değerler korunur | Eski değerler korunur | **Hiçbirine dokunulmaz** | Eski pin + token ile normal sync devam eder |
| **3** | CA fingerprint uyuşmadı (`CA_PIN_MISMATCH`) | Eski değerler korunur | Eski değerler korunur | **Hiçbirine dokunulmaz** | Eski pin + token ile normal sync devam eder |
| **4** | Faz D (`/request`, `/poll*`, `/ack`) kesin reddedildi (`401`/`403`/`409`) | Eski değerler korunur | Eski değerler korunur (`POLL_RECEIVED`/`ACK_PENDING` temizlenir) | **Hiçbirine dokunulmaz** | Eski pin + token ile normal sync devam eder |
| **5** | `/poll` sonrası, `/ack` gönderilmeden süreç çöktü (`POLL_RECEIVED`) | Eski değerler korunur | Eski aktif token korunur (`pairing_staged`=`POLL_RECEIVED`) | **Hiçbirine dokunulmaz** | Açılışta `POLL_RECEIVED` görülüp silinir; eski kimlik & pin korunur |
| **6** | **Hub `/ack`'yı işledi, Android yanıtı alamadan çöktü (`ACK_PENDING` — oturum aktif)** | Eski değerler korunur (mutabakat bitene dek) | Eski aktif token korunur (`pairing_staged`=`ACK_PENDING`) | **Hiçbirine dokunulmaz** | Açılışta aynı `/ack` idempotent tekrar gönderilir → Hub `200 OK` döner → `ACK_CONFIRMED` → `P1..P4` |
| **7** | **Hub `/ack`'yı işledi, Android yanıtı alamadan çöktü + Hub restart / TTL doldu** | Eski değerler korunur (yoklama bitene dek) | Eski aktif token korunur (`pairing_staged`=`ACK_PENDING`) | **Hiçbirine dokunulmaz** | `Bearer <staged.token>` yoklaması `200 OK` alırsa `P1..P4`; `401/403` ise eski kimliğe döner; ağ yoksa bekler |
| **8** | `/ack` sonrası `P1` ile `P2` arasında (`ACK_CONFIRMED`) süreç çöktü | Eski değer (`client_config.json`) sağlam | `P1` yazılmış; `pairing_staged`=`ACK_CONFIRMED` | **Hiçbirine dokunulmaz** | Açılışta `ACK_CONFIRMED` görülüp `P1→P2→P3→P4` tamamlanır |
| **9** | `/ack` sonrası `P2` (`client_config.json.tmp`) veya `P3` (`setHubUrl`) sırasında çöktü | Yeni veya eski (`.tmp` atomik rename sayesinde dosya bozulmaz) | `P1` yazılmış; `pairing_staged`=`ACK_CONFIRMED` | **Hiçbirine dokunulmaz** | Açılışta `ACK_CONFIRMED` görülüp `P1→P2→P3→P4` tamamlanır |
| **10** | Normal yeniden başlatma (`P4` tamamlanmış) | Yeni doğrulanmış CA | Yeni token + yeni Hub URL | **Hiçbirine dokunulmaz** | Yeni CA-pinned HTTPS ile normal sync devam eder |

> [!CRITICAL]
> **Değişmez Kural:** `outbox_operations`, `client_seq`, `device_id`, `tenant_id` ve `store_id` sıfırlamak veya değiştirmek hiçbir re-pairing veya crash recovery senaryosunun parçası **OLAMAZ**.

---

### 3.5 Windows Localhost TLS (`https://127.0.0.1`) ve Loopback SAN vs LAN SAN Hata Kategorileri

1. Windows'taki [`PairingApprovalPanel`](../lib/features/security/presentation/widgets/pairing_approval_panel.dart#L16-L26) ve yerel masaüstü kasa istemcisi `_verifyLoopbackAndAdmin` gereği `https://127.0.0.1:<port>` adresine CA-pinned HTTPS ile bağlanır (`F-6`).
2. BoringSSL, IP adresiyle açılan TLS bağlantılarında `DNS:localhost` kaydını IP eşleşmesi yerine kabul etmez; sunucu sertifikasının SAN uzantısında **`IP:127.0.0.1`** bulunmazsa `TlsCertificateValidationException(ipAddressMismatch)` fırlatır.
3. **Kategori Ayrımı — Loopback SAN Zorunluluğu vs LAN SAN Uyuşmazlığı:**
   - **Kategori A — Loopback SAN Eksikliği (`ERR_SERVER_CERT_MISSING_LOOPBACK_SAN` — Startup Fail-Fast):** `requireTls == true` iken Hub başlangıcında `server.crt` SAN uzantısında `IP:127.0.0.1` bulunmazsa Windows Host üzerindeki yerel yönetim paneli ve yerel masaüstü kasa çalışamayacağı için Hub **`HubConfigException` (çıkış kodu `78`)** ile başlangıcı durdurur.
   - **Kategori B — LAN SAN / `advertise_host` SAN Uyuşmazlığı (`ERR_ADVERTISE_HOST_SAN_MISMATCH`):** `IP:127.0.0.1` mevcutken yalnızca LAN IP veya `advertise_host` `server.crt` SAN içinde yoksa **Hub tamamen KAPANMAZ** (Windows yerel kasa, zamanlanmış yedekler ve geçerli SAN IP'li cihazlar kesintiye uğratılmaz). Başlangıçta tanı uyarısı loglanır; yalnızca `POST /api/v1/pairing/session` isteğinde fail-closed **`503 ERR_ADVERTISE_HOST_SAN_MISMATCH`** (veya **`503 ERR_HUB_LAN_IP_UNAVAILABLE`**) döndürülür.
4. **Loopback Sızma Yasağı:** `server.crt` içinde `IP:127.0.0.1` bulunması yalnızca Windows makine içi iletişim içindir. Android'e hiçbir koşulda (`hub_url` veya `server_ips` içinde) **`127.0.0.1` gönderilmez**.

---

## 4. `P-BLOCK-3` — Windows Network Adapter, `MIB_IF_ROW2.HardwareInterface` ve `advertise_host`

### 4.1 `GetAdaptersAddresses` Sınırı, `GetIfEntry2` Gerekliliği ve Adaptör-Donanım İlişkilendirmesi

Dart `dart:io` `NetworkInterface.list` yalnızca kullanıcı tarafından değiştirilebilen `name`, `index` ve `addresses` döndürür; sürücü/donanım ve IP yaşam döngüsü alanlarını açmaz. Ayrıca tek başına **`GetAdaptersAddresses` API'si de fiziksel donanım ayrımını garanti etmez**: Windows'ta Hyper-V `vEthernet` sanal anahtarları, bazı NDIS köprüleri ve kimi yazılım adaptörleri `IP_ADAPTER_ADDRESSES_LH.IfType == 6` (`IF_TYPE_ETHERNET_CSMACD`) raporlayabilir.

Bu nedenle `iphlpapi.dll` üzerinde **`GetAdaptersAddresses` + `GetIfEntry2` (veya `GetIfTable2`) birlikte kullanılır**:

| Veri Grubu | Kullanılan Windows API ve Alanlar | Amaç ve Değerlendirme |
|---|---|---|
| **Adaptör Adres ve Durum Bilgileri** | `iphlpapi.dll` → **`GetAdaptersAddresses`** (`IfIndex`, `Luid`, `IfType`, `OperStatus`, `Description`, `FriendlyName`, `FirstUnicastAddress` → `DadState`, `Ipv4Metric`, `FirstGatewayAddress`) | IPv4 unicast adreslerini (`AF_INET`), `OperStatus == IfOperStatusUp (1)`, `DadState == IpDadStatePreferred (4)`, sürücü `Description` ve `FriendlyName` alanlarını alır. |
| **Fiziksel Donanım Doğrulaması (`GetIfEntry2` / `GetIfTable2`)** | `iphlpapi.dll` → **`GetIfEntry2`** (hedef alınan adaptör başına `MIB_IF_ROW2.InterfaceLuid` / `InterfaceIndex` ile tekil sorgu; alternatif olarak toplu `GetIfTable2` + `FreeMibTable`) | `MIB_IF_ROW2` üzerinden:<br>1. **`InterfaceAndOperStatusFlags.HardwareInterface`** (bit 0: gerçek NDIS donanım arayüzü bayrağı);<br>2. **`InterfaceAndOperStatusFlags.ConnectorPresent`** (bit 2: fiziksel konnektör varlığı);<br>3. **`PhysicalMediumType`** (`NDIS_PHYSICAL_MEDIUM`) ve **`TunnelType`** (`TUNNEL_TYPE_NONE == 0`) alanlarını okur.<br>*Not:* Adaptör başına doğrudan `GetIfEntry2` çağrısı tüm tabloyu belleğe dökme gereksinimini azalttığı için tercih edilir; `GetIfTable2` ise eşdeğer bilgi kaynağını tek tabloda sunar. |
| **`GetIpForwardTable2` Kullanılmaması** | **KULLANILMAZ** | Mağaza içi internetsiz LAN ortamında varsayılan ağ geçidi bulunmayabilir ve tam-tünel VPN açıkken `0.0.0.0/0` rotası VPN tünelini işaretler; ayrıca çoklu NIC'te sessiz rota seçimi `ERR_HUB_LAN_IP_AMBIGUOUS` kuralını bozar. |

#### Adaptör IP Adresleri ile Fiziksel Donanım Bilgisinin İlişkilendirilmesi (Join Mekanizması)
1. `GetAdaptersAddresses` tarafından döndürülen her `IP_ADAPTER_ADDRESSES_LH` düğümünden birincil anahtar olarak 64-bit **`Luid`** (`NET_LUID`) ve ikincil anahtar olarak 32-bit **`IfIndex`** okunur.
2. Her adaptör için oluşturulan `MIB_IF_ROW2` yapısının `InterfaceLuid` alanı `Luid` ile doldurulur (`IfIndex` yedek eşleştirme olarak doğrulanır) ve `GetIfEntry2(&row)` çağrılır (dönüş `NO_ERROR == 0` değilse o adaptör güvenli biçimde donanım-doğrulanmamış / hata kabul edilir).
3. Aynı adaptörün `FirstUnicastAddress` bağlı listesindeki yalnızca `AF_INET` + `DadState == IpDadStatePreferred (4)` IPv4 adresleri o adaptörün `Luid`/`IfIndex` + `HardwareInterface` + `ConnectorPresent` + `TunnelType` + `Description` + `FriendlyName` kaydıyla bağlanır.
4. **Çalışma Zamanı Çapraz Doğrulama:** Elde edilen `(IfIndex, IPv4)` çiftleri Dart'ın MSVC ile derlenmiş yerleşik `NetworkInterface.list(type: InternetAddressType.IPv4)` çıktısıyla çapraz doğrulanır.

#### 64-Bit Windows FFI Offset'leri (`UNVERIFIED`) ve Fail-Closed Davranış
- `pubspec.yaml` içinde hazır `win32` paketi bulunmadığından `WindowsNetworkAdapterInspector` `dart:ffi` üzerinden `iphlpapi.dll` (`GetAdaptersAddresses`, `GetIfEntry2`) çağrısı yapacaktır.
- **`UNVERIFIED` Sınırı (Kesin Korunur):** `IP_ADAPTER_ADDRESSES_LH`, `IP_ADAPTER_UNICAST_ADDRESS_LH` ve **`MIB_IF_ROW2`** (özellikle `InterfaceLuid`, `InterfaceIndex`, `PhysicalMediumType`, `TunnelType`, `InterfaceAndOperStatusFlags` bitfield konumu ve toplam `sizeof(MIB_IF_ROW2)`) yapılarının **Windows x64 (`x86_64`) ABI hizalama ve byte offset'leri** bu salt okunur tasarım aşamasında doğrulanmamış olduğu için **`UNVERIFIED`** olarak işaretlidir.
- **Gerçek Windows x64 Doğrulama Gereksinimi ve Fail-Closed Davranış:**
  - Kodlama aşamasında her bir struct boyutu ve alan ofseti Windows SDK / MSVC C++ ile `sizeof` / `offsetof` karşılaştırması ve canlı Windows x64 FFI testleriyle doğrulanmadan üretime alınamaz.
  - Çalışma zamanında `GetAdaptersAddresses` veya `GetIfEntry2` sıfır dışı hata kodu dönerse, FFI işaretçi/dönüş doğrulaması başarısız olursa ya da `NetworkInterface.list` ile `(IfIndex, IPv4)` çapraz kontrolü uyuşmazsa **asla sessiz varsayım veya `127.0.0.1` fallback'i yapılmaz**; fail-closed olarak **`503 ERR_HUB_LAN_IP_UNAVAILABLE`** döndürülür.

---

### 4.2 İki Kademeli Adaptör Seçimi ve Hyper-V Host `vEthernet` LAN Bağlantısının Korunması

`HubLanAddressResolver` (`NetworkAdapterInspector` arayüzü ile test edilebilir) fiziksel donanımı doğrularken **Hyper-V External Virtual Switch gibi gerçek host LAN bağlantısı sağlayan `vEthernet` adaptörlerini yanlışlıkla elememek** için aşağıdaki **iki kademeli (Tier 1 / Tier 2)** kural setini uygular:

1. **Koşulsuz Elenenler (Tüm Katmanlar Dışı):**
   - `OperStatus != IfOperStatusUp (1)` veya `DadState != IpDadStatePreferred (4)`
   - Loopback (`127.0.0.0/8`), APIPA (`169.254.0.0/16`), `0.0.0.0/8`, multicast (`224.0.0.0/4`), broadcast (`255.255.255.255`), Tailscale/CGNAT (`100.64.0.0/10`), VirtualBox Host-Only (`192.168.56.0/24`)
   - `IfType` ∈ `{24 (Loopback), 131 (Tunnel), 23 (PPP)}` veya `MIB_IF_ROW2.TunnelType != 0`
   - İzole, NAT, VPN veya VM-özel adaptör kalıpları (`Description` / `FriendlyName`): `wireguard`, `wintun`, `tap-windows`, `openvpn`, `zerotier`, `tailscale`, `nordlynx`, `wsl`, `default switch`, `docker`, `virtualbox`, `vbox`, `vmware`, `vmnet`, `pseudo`, `teredo`, `6to4`, `ip-https` (ve Hyper-V `Internal`/`Private` switch belirteçleri).
2. **Tier 1 — Doğrulanmış Fiziksel Donanım NIC (`HardwareInterface == 1`):**
   - `IfType` ∈ `{6 (Ethernet), 71 (IEEE 802.11 Wi-Fi)}`, `MIB_IF_ROW2.HardwareInterface == 1` (ve `TunnelType == 0`), `OperStatus == Up`, `DadState == Preferred`, ve IPv4 adresi `sanLanIpv4s` (loopback/APIPA hariç `server.crt` IPv4 SAN kümesi) içinde.
3. **Tier 2 — Gerçek Host LAN Köprüsü / Hyper-V External `vEthernet` (`HardwareInterface == 0`, `IfType == 6`):**
   - Bir Windows kasasında Hyper-V **External Virtual Switch** (*"Allow management operating system to share this network adapter"*) etkinleştirildiğinde fiziksel Ethernet kartının IPv4 yığını `vEthernet (<SwitchAdı>)` adaptörüne taşınır ve `HardwareInterface == 0` raporlar.
   - Bu adaptör yukarıdaki **1. maddedeki yasaklı izole/NAT/VPN listesinde değilse**, `IfType == 6`, `OperStatus == Up`, `DadState == Preferred` koşullarını sağlıyorsa **ve IPv4 adresi `server.crt` SAN kümesinde (`sanLanIpv4s`) yer alıyorsa** Tier 2 geçerli LAN adayı olarak kabul edilir.
   - **Öncelik Kuralı (Tier 1 vs Tier 2):**
     - Eğer `sanLanIpv4s` ile kesişen **en az bir Tier 1 (`HardwareInterface == 1`)** aday varsa **yalnızca Tier 1 adayları değerlendirilir** (ikincil yazılım/sanal köprü gereksiz `AMBIGUOUS` üretmez).
     - Eğer `sanLanIpv4s` ile kesişen **hiç Tier 1 aday yoksa** (çünkü fiziksel NIC Hyper-V External Switch'e bağlıdır) **Tier 2 adayları değerlendirilir**:
       - `tier2SanCandidates.length == 1` (veya `advertise_host` ile seçilen bir Tier 2 adayı) → geçerli host LAN bağlantısı olarak kabul edilir (`201 Created`).
       - `tier2SanCandidates.length > 1` → `503 ERR_HUB_LAN_IP_AMBIGUOUS`.
       - Her iki katmanda da aday yoksa → `503 ERR_HUB_LAN_IP_UNAVAILABLE`.

| # | Ağ / Adaptör Durumu | İşlem Kuralı | Sonuç |
|---|---|---|---|
| **1** | Tek Tier 1 fiziksel NIC (Ethernet/Wi-Fi, `HardwareInterface == 1`, Up, Preferred, SAN içinde) | `tier1Candidates.length == 1` | Otomatik deterministik seçim (`https://<ip>:<port>`) |
| **2** | Birden fazla Tier 1 fiziksel NIC (Ethernet + Wi-Fi ikisi de SAN'da), `advertise_host` yok | Puanlama veya rota probu YASAK | **`503 ERR_HUB_LAN_IP_AMBIGUOUS`** |
| **3** | Yalnızca izole sanal/VPN adaptörler aktif (Hyper-V `Default Switch`, `WSL`, `WireGuard`, `VirtualBox`) | Tümü 1. maddede elenir | **`503 ERR_HUB_LAN_IP_UNAVAILABLE`** (`127.0.0.1` dönmez) |
| **4** | **Hyper-V External `vEthernet` (`HardwareInterface == 0`, `IfType == 6`) gerçek host LAN IP'si taşır (`sanLanIpv4s` içinde)** | Tier 1 SAN adayı yoksa Tier 2 devreye girer (`NET-02b` / `HUB-T04d`) | **`201 Created`** (yanlışlıkla elenmez!) |
| **5** | VPN / Tunnel (`IfType == 131/23`, `TunnelType != 0`, `WireGuard`, `OpenVPN`, `Tailscale 100.64.0.0/10`) | `IfType` + `TunnelType` + `Description` + alt ağ ile elenir | Aday dışı |
| **6** | `VirtualBox Host-Only` (`192.168.56.0/24`) / `VMware` (`VMnet`) | `Description` + alt ağ ile elenir | Aday dışı |
| **7** | `OperStatus != Up` veya `DadState != Preferred` (`Tentative`, `Duplicate`, `Deprecated`) | Koşulsuz elenir | Aday dışı |
| **8** | DHCP ile IP değişimi | Önbellek tutulmaz; her `/pairing/session` çağrısında canlı okunur | Yeni IP SAN'daysa seçilir; yoksa **`503 ERR_HUB_LAN_IP_UNAVAILABLE`** |
| **9** | APIPA (`169.254.0.0/16`), Loopback (`127.0.0.0/8`, `::1`), `0.0.0.0/8`, multicast/broadcast | Koşulsuz reddedilir | Asla Android'e gönderilmez |

---

### 4.3 `advertise_host` Çift Doğrulaması, Startup Politikası ve Seçim Davranışı

`hub_config.json` içindeki isteğe bağlı `advertise_host` ([`hub_config.dart`](../test_spikes/spike_01_backend/lib/config/hub_config.dart#L85-L100) `_allowedKeys` içine eklenecek) için **hem SAN üyeliği hem yerel aktiflik** çift doğrulaması zorunludur:
1. **Koşul 1 (SAN Üyeliği):** `requireTls == true` iken `server.crt` IP SAN kümesinde bulunmalıdır (`ERR_ADVERTISE_HOST_SAN_MISMATCH`).
2. **Koşul 2 (Canlı Yerel Aktiflik):** `WindowsNetworkAdapterInspector` üzerinden bu makinenin aktif (`OperStatus == Up`), `DadState == Preferred`, izinli Tier 1 veya Tier 2 yerel IPv4 adreslerinden biri olmalıdır (`ERR_ADVERTISE_HOST_NOT_LOCAL`).

| # | `advertise_host` / Ortam Durumu | Hub Startup (`requireTls == true`) | `POST /api/v1/pairing/session` Sonucu |
|---|---|---|---|
| **1** | `server.crt` SAN'da VAR ve yerel aktif (Tier 1 veya Tier 2 host LAN) IPv4 | Başarılı (`0`) | **`201 Created`** (`hub_url: "https://<advertise_host>:<port>"`) |
| **2** | `server.crt` SAN'da VAR ama makinede aktif DEĞİL (kablo çekili / eski DHCP / başka PC IP'si) | Başarılı (Session 0 ağ gecikmesini çökertmez; `WARN` loglar) | **`503 ERR_ADVERTISE_HOST_NOT_LOCAL`** |
| **3** | Yerel aktif IPv4 ama `server.crt` **LAN SAN'da YOK** (Loopback `IP:127.0.0.1` mevcut) | **Hub KAPANMAZ** (yerel Windows POS ve diğer işlemler çalışır; `CRITICAL` tanı uyarısı loglar) | **`503 ERR_ADVERTISE_HOST_SAN_MISMATCH`** |
| **4** | `server.crt` içinde **`IP:127.0.0.1` Loopback SAN YOK** | **Fail-Fast Çıkış Kodu `78`** (`ERR_SERVER_CERT_MISSING_LOOPBACK_SAN`) | Başlamaz |
| **5** | `advertise_host` sözdizimi bozuk veya `127.x` / `169.254.x` / `0.0.0.0` | **Fail-Fast Çıkış Kodu `78`** (`HubConfigException`) | Başlamaz |
| **6** | Birden fazla aktif fiziksel NIC + `advertise_host` geçerli (SAN + yerel aktif) | Başarılı (`0`) | **`201 Created`** (Owner belirsizliği çözer) |

#### `HUB-T03` vs `HUB-T05` (`IP:127.0.0.1` SAN Temizliği) & `ADR-018` UDP Değişmezliği
- `HubLanAddressResolver` kesişim hesaplamadan **önce** `server.crt` SAN IPv4 listesinden `127.0.0.0/8` ve `169.254.0.0/16` adreslerini çıkarır (`sanLanIpv4s`). Böylece `IP:127.0.0.1` + tek LAN IP içeren `server.crt` altında `HUB-T03` deterministik tek LAN IP döner; yalnızca `>= 2` gerçek LAN adayı varsa `HUB-T05` `503 ERR_HUB_LAN_IP_AMBIGUOUS` üretir.
- `HubDiscoveryResponder` ([`discovery_responder.dart:135-189`](../test_spikes/spike_01_backend/lib/discovery/discovery_responder.dart#L135-L189)) ve 6 alanlı UDP `HUB_DISCOVERY_V1` v1.0 yanıtı hiçbir değişiklik yapılmadan korunur.

---

## 5. Güvenlik Tehdit Modeli (`M1..M7`) ve Uçtan Uca Pairing Akışı

### 5.1 Gerçekçi Tehdit Modeli (`M1..M7`)

| ID | Saldırı & Saldırgan Yeteneği | Savunma Mekanizması | Savunmanın Sınırı | Hata Kodu | İlgili Testler |
|---|---|---|---|---|---|
| **`M1`** | **Sahte CA / Aktif LAN MITM:** Saldırgan ARP spoofing/sahte AP ile `/ca-cert` veya `/request` trafiğini yakalar. | Faz A sıfır-sır taşır; Faz B `SHA256(DER(CA')) != OOB`. Sahte Hub gerçek `ca.crt` yansıtsa bile Faz C/D'de BoringSSL `server.key` ve CA imzalı `server.crt` olmadan reddeder. | OOB parmak izi doğruluğu ve Hub `server.key`/`ca.key` gizliliği gerekir. | `CA_PIN_MISMATCH`, `TLS_PIN_MISMATCH` | `APP-T03`, `APP-T09`, `APP-T18` |
| **`M2`** | **JSON Payload Manipülasyonu:** Saldırgan paylaşım kanalında `ca_fingerprint` veya `http://` değiştirir. | Android JSON `ca_fingerprint`'i tek güven kökü saymaz; Owner OOB ile `constantTimeEquals` doğrular ve `http://` hedefini yasaklar. | Owner OOB değerini Windows ekranından bağımsız girmelidir. | `OOB_FINGERPRINT_MISMATCH`, `TLS_SCHEME_REQUIRED` | `APP-T02`, `APP-T12` |
| **`M3`** | **OOB Bütünlüğünün Ele Geçirilmesi / Host OS Compromise:** Saldırgan Windows Hub host OS'unu tamamen ele geçirip ekrana `CA'` + `SHA256(CA')` basar. | Önceden eşleştirilmiş cihazda `REPAIRING_CA_CHANGE_CONFIRMATION_REQUIRED` sessiz geçişi önler; gerçek Hub `/approve` tanımadığı isteği reddeder. | İlk eşleştirmede OOB kanalı ve Hub OS tamamen ele geçirilirse kriptografik pinleme bunu tespit edemez. | `REPAIRING_CA_CHANGE_CONFIRMATION_REQUIRED` | `APP-T11` |
| **`M4`** | **Redirect, Proxy Tünel & Downgrade (`F-4`, `F-6`):** `/ca-cert` `3xx` redirect, `HTTP_PROXY` MITM veya `http://` fallback. | `followRedirects = false`, `maxRedirects = 0`, `findProxy = DIRECT`, `B-CB-2`/`B-CB-3`, `http://` yasağı. | Ağ seviyesinde TCP paket düşürmeyi (availability DoS) önlemez. | `BOOTSTRAP_REDIRECT_FORBIDDEN`, `BOOTSTRAP_HOST_MISMATCH`, `TLS_SCHEME_REQUIRED` | `APP-T04`, `APP-T05`, `APP-T05b`, `APP-T12` |
| **`M5`** | **Slowloris, Sıkıştırma Bombası & Çelişkili/Sınırsız Gövde DoS:** Gzip bombası, sahte `Content-Length`, kesilmiş gövde veya damla akış. | `autoUncompress = false`, `Accept-Encoding: identity`, `Content-Encoding` reddi, `contentLength != totalBytes` reddi, `65.537`'nci bayt kesicisi, mutlak `Timer(5s)` + `close(force: true)`. | Yalnızca Android istemcisini korur; LAN ağ flood DoS'unu önlemez. | `BOOTSTRAP_TIMEOUT`, `INVALID_CA_CERT` | `APP-T08`, `APP-T14`, `APP-T14b`, `APP-T15`, `APP-T15b`, `APP-T15c` |
| **`M6`** | **CA Olmayan / Bozuk Sertifika Sunumu:** `CA:FALSE` yaprak, `keyCertSign` eksik, v1, expired, sentetik DER veya private key. | Katman 1 (UTF-8 bağımsız byte tespiti, strict PEM/Base64, minimal DER) + Katman 2 (dar `MmsX509PreValidator`: v3, `CA=true`, `keyCertSign`, tarih, `outerSigAlg == tbsSigAlg`, duplicate OID reddi) + BoringSSL imza doğrulaması. | Çalınmış gerçek `ca.key` ile imzalı sertifikalara karşı koruma sağlamaz. | `INVALID_CA_CERT`, `CA_CERT_EXPIRED`, `503 ERR_CA_CERT_UNAVAILABLE` | `HUB-T01b..T02c`, `APP-T06`, `APP-T07`, `APP-T17` |
| **`M7`** | **Re-pairing Sırasında `/ack` Yanıt Kaybı / Çökme (`F-5`, `F-7`):** Hub `/ack`'yı işler ancak Android yanıt alamadan çöker veya `P1..P4` yarım kalır. | `POLL_RECEIVED → ACK_PENDING → ACK_CONFIRMED → P1..P4`, sunucu tarafı idempotent `/ack` (imza re-verify) + Startup Reconciliation + Outbox/`client_seq`/kimlik dokunulmazlığı. | OS güvenli deposunun (`Keystore`/`DPAPI`) fiziksel disk bozulmasına karşı garanti vermez. | `REPAIRING_CA_CHANGE_CONFIRMATION_REQUIRED`, `PendingOutboxIdentityChangeException` | `HUB-T09b`, `APP-T11`, `APP-T16`, `APP-T16b..e` |

### 5.2 Uçtan Uca Pairing ve `ACK_PENDING` Çökme Kurtarma Akışı

```mermaid
sequenceDiagram
    autonumber
    actor Owner as "Owner (Windows Host)"
    participant WinUI as "Windows PairingApprovalPanel"
    participant Hub as "Windows Master Hub (Session 0)"
    participant Android as "Android Istemci (DevicePairingClient)"

    Note over WinUI,Hub: "IP:127.0.0.1 SAN eksikse Hub cikis 78 ile durur; LAN SAN uyusmazliginda 503 doner"
    Owner->>WinUI: "Yeni Cihaz Eslestirme Oturumu Baslat"
    WinUI->>Hub: "POST /api/v1/pairing/session (https://127.0.0.1 + Admin Token)"
    Hub->>Hub: "P-BLOCK-1 (K1+K2): DER SHA-256 + MmsX509PreValidator"
    Hub->>Hub: "P-BLOCK-3: GetAdaptersAddresses + GetIfEntry2 (HardwareInterface + Tier2 Host vEthernet) kesisim SAN"
    Hub-->>WinUI: "201 Created: hub_url (127.0.0.1 yok), ca_fingerprint, session_id, pairing_secret"
    WinUI-->>Owner: "T0: Ekranda OOB ca_fingerprint + hub_url + JSON goster"

    Owner->>Android: "OOB 64-hex ca_fingerprint + JSON aktar"
    Android->>Android: "OOB 64-hex + https:// + constantTimeEquals(OOB, JSON) + Re-pairing onay kapisi"
    Note over Android,Hub: "FAZ A (ALT-BOOT-2): Zero Secrets, findProxy=DIRECT, autoUncompress=false, followRedirects=false, <=64KB, 5s Timer"
    Android->>Hub: "GET /api/v1/pairing/ca-cert (Accept-Encoding: identity)"
    Hub-->>Android: "200 OK: Root CA PEM"
    Android->>Android: "finally: bootstrapClient.close(force:true); Faz B: K1+K2 + OOB SHA256 + B-CB-5"

    Note over Android,Hub: "FAZ C->D: Yeni CA-Pinned HttpClient (badCertificateCallback=false, BoringSSL tam imza/SAN/tarih)"
    Android->>Hub: "POST /api/v1/pairing/request"
    Hub-->>Android: "202 Pending Approval"
    Owner->>WinUI: "POST /api/v1/pairing/approve (T3)"
    Android->>Hub: "POST /api/v1/pairing/poll-challenge & /poll"
    Hub-->>Android: "Yeni Device Token"
    Android->>Android: "pairing_staged = POLL_RECEIVED (Eski token/pin/URL korunur)"
    Android->>Hub: "POST /api/v1/pairing/ack-challenge"
    Hub-->>Android: "ack_challenge_id + nonce"
    Android->>Android: "pairing_staged = ACK_PENDING (ack_challenge_id + ack_signature kaydedilir)"
    Android->>Hub: "POST /api/v1/pairing/ack"
    alt "Hub 200 OK isler ama Android yaniti alamadan coker"
        Hub->>Hub: "devices.isConfirmed=true; session.confirmedTokenSha256 sakla (rawToken silinir)"
        Note over Android,Hub: "Android Acilis: reconcileStagedPairingOnStartup (ACK_PENDING)"
        Android->>Hub: "Ayni POST /api/v1/pairing/ack (CA-Pinned Idempotent Replay)"
        Hub-->>Android: "200 OK (imza dogrulandi, idempotent_replay: true)"
    else "Normal 200 OK"
        Hub-->>Android: "200 OK (CONFIRMED)"
    end
    Android->>Android: "pairing_staged = ACK_CONFIRMED -> P1..P4 Idempotent Terfi (Outbox/client_seq korunur)"
```

---

## 6. Güncellenmiş Test Matrisi (`HUB-T*`, `NET-*`, `APP-T*`, `AUD-*`) ve `PAT-01..15`

> [!IMPORTANT]
> **Otomatik TDD Testleri vs Kodlanmış Baz Çizgisi vs Fiziksel Kabul Testleri Ayrımı (Dürüst Durum Beyanı):**
> - **Bu Görevde Çalıştırılan Testler:** **`0` test** (bu görev salt okunur tasarım revizyonudur; hiçbir test veya build çalıştırılmamıştır).
> - **Mevcut Kodlanmış Baz Çizgisi (Önceki Oturum Kanıtı):** [`PILOT_TECHNICAL_REMEDIATION_REPORT.md`](./PILOT_TECHNICAL_REMEDIATION_REPORT.md) kapsamındaki **730** mevcut otomatik test kodlanmış ve o oturumda geçmiştir; ancak `P-BLOCK-1..3` için aşağıda tanımlanan matrisi içermez.
> - **Planlanan Yeni/Revize Otomatik Testler (`HUB-T*`, `NET-*`, `APP-T*`):** Tamamı **`PLANNED — NOT CODED / NOT RUN`** durumundadır; kodlama ve çalıştırma ayrı bir Owner-onaylı TDD görevine tabidir.
> - **Fiziksel Saha Kabul Testleri (`PAT-01..15`):** Tamamı **`BLOCKED — NOT RUN`** durumundadır.

### 6.1 Hub Otomatik Test Matrisi (`HUB-T01..T09b` — `PLANNED / NOT CODED`) & Ağ Topolojisi (`NET-01..08`)

*(Mevcut `HUB-T01..T09` ve `NET-01..08` ID'leri korunmuş; UTF-8 bağımsız binary DER/PEM, `GetIfEntry2` `HardwareInterface`, Hyper-V host `vEthernet` ve idempotent `/ack` için yeni alt testler eklenmiştir.)*

| Test ID | Kapsam / Senaryo | Beklenen Doğrulama & Sonuç | Durum |
|---|---|---|---|
| **`HUB-T01`** | **Katman 1 `TV-DER-01..04` + Ortak `kSharedTestRootCaPem`:** Ham DER, LF PEM, BOM+CRLF PEM, `F-1` `'0'` (`0x30`) tuzağı | Tüm geçerli girdilerde özdeş `75920A4A...` (`TV-DER`) ve özdeş `kSharedTestRootCaSha256` üretilir. | `PLANNED — NOT CODED` |
| **`HUB-T01b`** | **Katman 2 Gerçek X.509v3 CA (`TV-X509-01`):** `CA:TRUE`, `keyCertSign`, geçerli tarihler | `MmsX509PreValidator` geçer; `/pairing/session` ve `/pairing/ca-cert` `201`/`200` döner. | `PLANNED — NOT CODED` |
| **`HUB-T01c`** | **CA–Leaf Kriptografik İmza Doğrulaması (vs DN Eşleşmesi):** Aynı Subject DN'li sahte CA2 tarafından imzalı `server.crt` | İsim (`issuer == subject`) aynı olsa dahi BoringSSL sahte sertifikayı reddeder; yalnızca gerçek `ca.key` imzalı `server.crt` geçer. | `PLANNED — NOT CODED` |
| **`HUB-T01d`** *(Yeni)* | **UTF-8 Bağımsız Binary DER / PEM Ayrıştırma Sınırları:** Yüksek bitli (`>= 0x80`) ham binary X.509v3 DER (`kSharedTestRootCaDerBytes`), `0x80` indefinite length, trailing byte, non-minimal length, derinlik > 8 | Ham binary DER `utf8.decode` çağrılmadan kabul edilir (`kSharedTestRootCaSha256`); bozuk DER sınır ihlalleri `503 ERR_CA_CERT_UNAVAILABLE` ile reddedilir. | `PLANNED — NOT CODED` |
| **`HUB-T02`** | **Katman 1 `TV-DER-05` & Katı UTF-8/BOM:** Çoklu sertifika, Private Key, bozuk Base64, truncated DER, BOM + bozuk UTF-8, bozuk UTF-8 + `-----BEGIN ` | `503 ERR_CA_CERT_UNAVAILABLE`. | `PLANNED — NOT CODED` |
| **`HUB-T02b`** | **Non-CA Sertifika Reddi (`TV-X509-02..04`, `TV-X509-07`):** `CA:FALSE` leaf, `keyCertSign` eksik CA, X.509 v1, duplicate OID, `outerSigAlg != tbsSigAlg`, non-canonical `critical: FALSE`, 14-bayt sentetik DER | `MmsX509PreValidator` reddeder → `503 ERR_CA_CERT_UNAVAILABLE`. | `PLANNED — NOT CODED` |
| **`HUB-T02c`** | **Expired / Not-Yet-Valid CA (`TV-X509-05..06`):** `notAfter < nowUtc` ve `notBefore > nowUtc` | `CA_CERT_EXPIRED` / `CA_CERT_NOT_YET_VALID` → `503 ERR_CA_CERT_UNAVAILABLE`. | `PLANNED — NOT CODED` |
| **`HUB-T03`** | **`127.0.0.1` SAN ile Tek Fiziksel NIC (`/pairing/session` `https://127.0.0.1` üzerinden):** SAN'da `IP:127.0.0.1` + `IP:192.168.1.50` | `127.0.0.1` kesişim öncesi çıkarılır; `hub_url` `https://192.168.1.50:8945` döner (`AMBIGUOUS` veya `127.0.0.1` sızıntısı olmaz). | `PLANNED — NOT CODED` |
| **`HUB-T04`** | **VPN / İzole Hyper-V / WSL / VirtualBox + Fiziksel NIC Kaybı (`NET-01..03`):** | Sanal/VPN adaptörler elenir (`NET-01`, `NET-02`); fiziksel/uygun aday yoksa `503 ERR_HUB_LAN_IP_UNAVAILABLE` (`NET-03`). | `PLANNED — NOT CODED` |
| **`HUB-T04b`** | **`DadState != Preferred` ve `OperStatus != Up` Reddi:** | Yalnızca `OperStatus == Up` ve `DadState == Preferred` olanlar aday olur. | `PLANNED — NOT CODED` |
| **`HUB-T04c`** *(Yeni)* | **Windows `MIB_IF_ROW2.HardwareInterface` (`GetIfEntry2`) & `Luid`/`IfIndex` Doğrulaması:** `IfType == 6` görünümlü izole yazılım adaptörü (`HardwareInterface == 0`) vs gerçek fiziksel NIC (`HardwareInterface == 1`) + canlı Windows x64 FFI/`NetworkInterface.list` çapraz kontrolü + FFI hata simülasyonu | Tier 1 `HardwareInterface == 1` seçilir; `GetIfEntry2` veya çapraz kontrol hatasında sessiz varsayım olmaz, fail-closed `503 ERR_HUB_LAN_IP_UNAVAILABLE`. *(Not: Windows x64 FFI offset'leri canlı Windows x64 testinde doğrulanacaktır.)* | `PLANNED — NOT CODED` (`UNVERIFIED` FFI) |
| **`HUB-T04d`** *(Yeni)* | **Hyper-V Host External `vEthernet` LAN Bağlantısı (`NET-02b`):** Fiziksel NIC Hyper-V External Switch'e bağlı olduğu için Tier 1 SAN adayı yok (`0`), `vEthernet (External Switch)` (`IfType == 6`, `HardwareInterface == 0`, `OperStatus == Up`, `DadState == Preferred`) `server.crt` SAN içindeki LAN IP'yi taşıyor (ve yanında `vEthernet (WSL)` mevcut) | `vEthernet (WSL)` elenir; `vEthernet (External Switch)` Tier 2 SAN adayı olarak kabul edilir ve `201 Created` (`https://<lan_ip>:<port>`) döner. | `PLANNED — NOT CODED` |
| **`HUB-T05`** | **Çoklu Fiziksel NIC + `advertise_host` (`NET-04..06`):** Ethernet + Wi-Fi aktif ve SAN'da → `advertise_host` tanımlı → **LAN SAN dışı `advertise_host`** | Belirsizde puanlama yok `503 ERR_HUB_LAN_IP_AMBIGUOUS` (`NET-04`); geçerli `advertise_host` seçilir (`NET-05`); LAN SAN dışındaysa **Hub ayakta kalır** ve `/pairing/session` `503 ERR_ADVERTISE_HOST_SAN_MISMATCH` (`NET-06`) döner. | `PLANNED — NOT CODED` |
| **`HUB-T06`** | **`ADR-018` UDP `HUB_DISCOVERY_V1` v1.0 Regresyon Kilidi:** `discovery_responder.dart` | Tam 6 alan, `127.x` yok, yeni alan yok. | `PLANNED — NOT CODED` |
| **`HUB-T07`** | **Windows `IP:127.0.0.1` Loopback SAN Eksikliği:** `server.crt` içinde `IP:127.0.0.1` yok (`DNS:localhost` tek başına) | Hub startup'ta **Fail-Fast Çıkış Kodu `78`** (`ERR_SERVER_CERT_MISSING_LOOPBACK_SAN`). | `PLANNED — NOT CODED` |
| **`HUB-T08`** | **DHCP IP Değişimi (`NET-07`):** Çalışan Hub NIC IP'si `192.168.1.50` → `192.168.1.77` değişir | Canlı sorgu sayesinde SAN'da varsa yeni IP döner; yoksa `503 ERR_HUB_LAN_IP_UNAVAILABLE`. | `PLANNED — NOT CODED` |
| **`HUB-T09`** | **Stale / Yerel Olmayan `advertise_host` (`NET-08`):** SAN'da var ama makinede aktif değil | Hub ayakta kalır; `/pairing/session` `503 ERR_ADVERTISE_HOST_NOT_LOCAL` döner. | `PLANNED — NOT CODED` |
| **`HUB-T09b`** *(Yeni)* | **Sunucu Tarafı İdempotent `POST /api/v1/pairing/ack` & Re-pairing Eski Token Korunumu:** Aynı `(session_id, ack_challenge_id, valid_signature)` ile 2. `/ack` + yanlış imzalı replay + challenge süresi dolmuşken session TTL içinde yeni `/ack-challenge` + re-pairing'de `/ack` öncesi eski token erişimi | Geçerli replay **`200 OK`** (`idempotent_replay: true`, DB çift yazım yok); bozuk imzada `403 INVALID_ACK_TOKEN_HASH_SIGNATURE`; `/ack` gelmeden eski cihaz token'ı geçerliliğini korur. | `PLANNED — NOT CODED` |

### 6.2 Android & Windows İstemci Otomatik Test Matrisi (`APP-T01..T18` + Ek Alt Testler — `PLANNED / NOT CODED`)

| Test ID | Kapsam / Senaryo | Beklenen Doğrulama & Sonuç | Durum |
|---|---|---|---|
| **`APP-T01`** / **`APP-T01b`** | Katman 1 `TV-DER-01..05` + strict UTF-8/BOM + Ortak `kSharedTestRootCaPem` (`TV-X509-01`) | Hub ile bit-düzeyinde özdeş SHA-256; bozuk girdiler fail-closed. | `PLANNED — NOT CODED` |
| **`APP-T01c`** *(Yeni)* | **İstemci Binary DER / PEM Ayrıştırma Sınırları:** Yüksek bitli ham binary DER `ca.crt` vs trailing byte vs non-minimal DER vs `-----BEGIN ` içeren bozuk UTF-8 | Binary DER `utf8.decode` olmadan kabul edilir; sınır ihlalleri `INVALID_CA_CERT` ile reddedilir. | `PLANNED — NOT CODED` |
| **`APP-T02`** / **`APP-T03`** | Eksik/`'UNKNOWN'` OOB pin, `OOB != JSON`, yanlış OOB fingerprint | Sıfır ağ isteğiyle `CA_PIN_REQUIRED` / `OOB_FINGERPRINT_MISMATCH`; Faz B'de `CA_PIN_MISMATCH`. | `PLANNED — NOT CODED` |
| **`APP-T04`** / **`APP-T05`** | Bootstrap aynı host `3xx` redirect ve cross-host / `http://` redirect | `followRedirects = false`, `B-CB-3` → `BOOTSTRAP_REDIRECT_FORBIDDEN`. | `PLANNED — NOT CODED` |
| **`APP-T05b`** *(Yeni)* | **Proxy Üzerinden Bootstrap Girişimi:** Ortam/sistem `HTTP_PROXY` / `HTTPS_PROXY` tanımlıyken Faz A bootstrap | `findProxy = (_) => 'DIRECT'` sayesinde istek proxy sunucusuna uğramaz (veya proxy taklidi `B-CB-2` ile reddedilir). | `PLANNED — NOT CODED` |
| **`APP-T06`** / **`APP-T07`** | Bozuk gövde, Private Key, Non-CA (`CA:FALSE`, `keyCertSign` yok, v1, expired/notYetValid), çoklu PEM (`certCount != 1`) | Katman 1/2 reddeder → `INVALID_CA_CERT` / `CA_CERT_EXPIRED` / `CA_CERT_NOT_YET_VALID`. | `PLANNED — NOT CODED` |
| **`APP-T08`** / **`APP-T09`** | Her dalda `close(force: true)` + İlk HTTPS Bootstrap (`ALT-BOOT-2` Faz A→B→C→D gerçek soket) | Soket `finally close(force: true)`; Faz C/D yalnızca yeni CA-pinned istemciden (`badCertificateCallback = false`) geçer. | `PLANNED — NOT CODED` |
| **`APP-T10`** | SAN IP/DNS uyuşmazlığı, expired/not-yet-valid `server.crt` (geçerli CA altında) | Faz D'de `TlsCertificateValidationException`. | `PLANNED — NOT CODED` |
| **`APP-T11`** | Re-pairing reddi ve Faz A/B/D hatasında pin korunumu | Eski `pinnedCaSha256`, `pinnedCaPem`, `device_token` korunur. | `PLANNED — NOT CODED` |
| **`APP-T12`** / **`APP-T13`** | `F-4`/`F-6`/`F-7` downgrade yasağı + Windows `https://127.0.0.1` (`IP:127.0.0.1` var vs yalnızca `DNS:localhost`) | `http://` hedefi `TLS_SCHEME_REQUIRED`; `IP:127.0.0.1` yoksa `ipAddressMismatch`. | `PLANNED — NOT CODED` |
| **`APP-T14`** / **`APP-T14b`** | Bağlantı/header `5s` timeout + Slowloris damla saldırısı (her 2 sn'de 1 bayt vs mutlak `Timer(5s)`) | 5 sn duvar saati dolunca `BOOTSTRAP_TIMEOUT` + stream iptali + `close(force: true)`. | `PLANNED — NOT CODED` |
| **`APP-T15`** / **`APP-T15b`** | Chunked `65.537` byte + sahte küçük `Content-Length: 100` üzerinde `65.537` byte | `65.537`'nci baytta stream iptali → `INVALID_CA_CERT` + `close(force: true)`. | `PLANNED — NOT CODED` |
| **`APP-T15c`** *(Yeni)* | **Sıkıştırılmış (`Content-Encoding: gzip/deflate/br`) veya Çelişkili HTTP Gövdesi:** (`a`) `Content-Encoding: gzip` + gzip gövde; (`b`) `Content-Length: 2048` bildirip `1200` baytta kapanan kesik gövde; (`c`) `Content-Length: 0` | `autoUncompress = false` + `Content-Encoding` kontrolü + `totalBytes != contentLength` denetimi hepsini anında **`INVALID_CA_CERT`** ile reddeder (`close(force: true)`). | `PLANNED — NOT CODED` |
| **`APP-T16`** / **`APP-T16b`** | Outbox/`client_seq`/kimlik korunumu + `/poll` sonrası `/ack` öncesi çökme (`POLL_RECEIVED`) | Outbox, `client_seq`, `device_id`, `tenant_id`, `store_id` 0 kayıp; açılışta `POLL_RECEIVED` silinir ve eski pin+token korunur. | `PLANNED — NOT CODED` |
| **`APP-T16c`** *(Yeni)* | **ACK Sunucuda İşlendi, İstemci Yanıt Alamadı (`ACK_PENDING`):** Hub `/ack` `200 OK` işler ancak soket Android `200`'ü kaydetmeden düşer/süreç çöker; ağ kapalıyken reboot vs Hub açıkken reboot | Ağ yokken eski aktif token/pin/URL + `ACK_PENDING` korunur; Hub'a erişilince aynı `/ack` gönderilir (`200 OK`), `ACK_CONFIRMED → P1..P4` tamamlanır. | `PLANNED — NOT CODED` |
| **`APP-T16d`** *(Yeni)* | **ACK Sonrası Yerel Terfi (`ACK_CONFIRMED → P1..P4`) Sırasında Çökme:** `P1` (`saveDeviceToken`) yazıldıktan sonra `P2` (`client_config.json`) veya `P3` (`setHubUrl`) öncesi çökme + yeniden başlatma | Açılışta `ACK_CONFIRMED` görülüp `P1→P2→P3→P4` tamamlanır; token/pin/URL uyumsuzluğu sıfırlanır, Outbox korunur. | `PLANNED — NOT CODED` |
| **`APP-T16e`** *(Yeni)* | **ACK Tekrar Gönderildi + Session TTL / Hub Restart Yoklaması:** (`a`) İdempotent `/ack` tekrarı `200 OK`; (`b`) TTL/restart sonrası `404`/`410` durumunda `Bearer <staged.token>` yoklamasıyla `200 OK` (terfi) vs `401` (eski kimliğe dönüş) | Her dalda kimlik tutarlılığı korunur; Outbox ve `client_seq` etkilenmez. | `PLANNED — NOT CODED` |
| **`APP-T17`** / **`APP-T18`** | Self-signed Hub sertifikası + Yabancı CA ve MITM (Faz A ve Faz D) | Faz B `CA_PIN_MISMATCH` / `ca.subject != leaf.issuer`; Faz D `untrustedCaChain`. | `PLANNED — NOT CODED` |

### 6.3 Bağımsız Güvenlik Denetçisi Kontrol Listesi (`AUD-01..25`)

- **`AUD-01..04` (`P-BLOCK-1`):** Katman 1 (UTF-8 bağımsız byte-düzeyi PEM/DER tespiti, `allowMalformed: false` yalnızca PEM'de, `certCount==1`, minimal DER length, `TV-DER-01..05`) ve Katman 2 (`MmsX509PreValidator` dar 3-görevli kapsam + `TV-X509-01..09` + BoringSSL imza doğrulaması) ayrı; DN eşitliği imza kanıtı sayılmıyor; OOB CA fingerprint doğrulaması ile TLS leaf doğrulaması birbirine karıştırılmıyor.
- **`AUD-05..12` (`P-BLOCK-2` Bootstrap):** Eksik OOB `CA_PIN_REQUIRED`; `ALT-BOOT-2` sıfır-sır taşıyor; `B-CB-1..6` eksiksiz; `findProxy = DIRECT`; `autoUncompress = false` + `Content-Encoding` reddi; `contentLength != totalBytes` ve `65.537`'nci bayt kesicisi; mutlak `Timer(5s)`; `3xx` redirect reddi; `finally close(force: true)`; Faz C/D ve normal sync istemcilerinde callback gevşetme yok (`false`).
- **`AUD-13..16` (`P-BLOCK-2` Re-pairing & Localhost SAN):** `POLL_RECEIVED → ACK_PENDING → ACK_CONFIRMED → P1..P4` aktif token/pin/URL'yi kesinleşme öncesi ezmiyor; sunucu `/ack` idempotent ve eski re-pairing token'ını koruyor; Outbox/`client_seq`/`device_id`/`tenant_id`/`store_id` dokunulmaz; `IP:127.0.0.1` Loopback SAN eksikliği exit `78`, LAN SAN uyuşmazlığı Hub kapatmadan `503`.
- **`AUD-17..23` (`P-BLOCK-3`):** `GetAdaptersAddresses` + `GetIfEntry2` (`MIB_IF_ROW2.HardwareInterface`) `Luid`/`IfIndex` ilişkilendirmesi; Windows x64 FFI offset'leri `UNVERIFIED` işaretli ve fail-closed; Tier 1 öncelikli + Tier 2 SAN-doğrulamalı Hyper-V External `vEthernet` korunmuş; `advertise_host` çift doğrulamalı; `127.0.0.1` SAN kesim öncesi temizliği (`HUB-T03`/`HUB-T05`); Android'e `127.0.0.1` yok; UDP v1.0 6 alan korunmuş.
- **`AUD-24..25` (Kapsam Sınırı):** Outbox/`client_seq`/idempotency/cursor/SQLite protokolleri, `qr_flutter` ve `L-3` kapsam dışı.

### 6.4 Fiziksel Kabul Testleri (`PAT-01..15` — Tamamı `BLOCKED — NOT RUN`)

> [!CAUTION]
> **Fiziksel Kabul Testi Gerçeği:** Aşağıdaki **15 fiziksel kabul testinin (`PAT-01..15`) HİÇBİRİ çalıştırılmamıştır** (`BLOCKED — NOT RUN`). Üretim signing key (`B1`), üretim OpenSSL sertifikaları (`B2`), temizlik (`D1..D4`) ve pilot donanımı (`E1`) sağlanmadan bu testler tamamlanmış ilan edilemez. (Kaynak: [`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`](../PHYSICAL_ACCEPTANCE_TEST_PLAN.md))

| Test ID | Amaç | Gereken Donanım | Gereken Sertifika / Key | Ön Koşullar | Beklenen Sonuç | Mevcut Durum |
|---|---|---|---|---|---|---|
| **`PAT-01`** | Android kamera barkod tarama & sepet debounce | Kameralı Android (`minSdk 24+`), EAN-13 ürünler | **`B1`**, **`B2`** (eşleştirilmiş) | APK kurulu, cihaz eşleştirilmiş, 3+ ürün | 9/10 ilk okuma, çift ekleme yok, bilinmeyen barkod reddi | **`BLOCKED — NOT RUN`** |
| **`PAT-02`** | Windows USB HID barkod okuyucu & hızlı tarama | Windows kasa, Enter son ekli USB HID okuyucu | Yok (yerel Windows) | POS ekranı açık, TR-Q uyumlu | 20/20 kayıpsız ürün ekleme & stok girişi | **`BLOCKED — NOT RUN`** |
| **`PAT-03`** | Android Wi-Fi keşfi, OOB CA bootstrap & eşleştirme | Windows Hub + Android aynı Wi-Fi (AP izolasyonu kapalı) | **`B1`**, **`B2`** (`ca.crt`, `server.crt`, `server.key`) | Firewall + Private ağ, **`P-BLOCK-1..3` uygulama & onay** | `127.0.0.1` yok, OOB doğrulama + Faz A→D + ≤5 sn `https://` keşif | **`BLOCKED — NOT RUN`** |
| **`PAT-04`** | Gerçek LAN kesintisi ve yeniden bağlantı | Windows kasa + Android + Wi-Fi/kablo | **`B1`**, **`B2`** | `PAT-03` geçmiş, cihazlar senkron | Kesintide Outbox artar, bağlantı gelince `0` kayıp / `0` çift kayıt | **`BLOCKED — NOT RUN`** |
| **`PAT-05`** | Çoklu Android cihazda eşzamanlı satış & %20 KDV sınırı | >= 2 Android + 1 Windows kasa | **`B1`**, **`B2`** | Stok=50, `ADR-019` operasyonel %20 KDV kuralı | Stok 50−15=35, tam tutarlı kuruş, `ERR_CLIENT_SEQ_GAP` yok | **`BLOCKED — NOT RUN`** |
| **`PAT-06`** | Çoklu cihazda eşzamanlı stok girişi & çift dokunma koruması | Android + Windows kasa | **`B1`**, **`B2`** | Ürün stoğu=5 | Stok 5+2+3=10, tam 2 `GIRIS` hareketi | **`BLOCKED — NOT RUN`** |
| **`PAT-07`** | Gerçek USB bellekte yedekleme & geri yükleme hataları | Windows kasa + normal USB + küçük/dolu USB | Yok (`E1` pilot ortamı) | Kasada en az 1 şifreli `.mmsbak` yedek | `ERR_DISK_FULL`, `ERR_TARGET_UNAVAILABLE`, Outbox korunumu, `.mmsbak` koruyucu | **`BLOCKED — NOT RUN`** |
| **`PAT-08`** | Gerçek Windows SCM kurulumu, reboot & güncelleme | Hub Windows 10/11 PC (Yönetici PS 5.1) | **`B2`** (`server.crt` [`IP:127.0.0.1` + LAN SAN], `server.key`, `ca.crt`) | **`D1` (`MarketMmsSpike01` kaldırılmış)** | `MarketMMSService` `Running`/`Automatic`, reboot'ta açılış, config hash sabit | **`BLOCKED — NOT RUN`** |
| **`PAT-09`** | Servis çökme kurtarma & başarısız güncelleme rollback | Hub PC (+ Android cihaz) | **`B1`**, **`B2`** | `PAT-08` geçmiş | 5/15/60 sn restart, veri kaybı yok, bozuk exe'de `bin.previous` dönüşü | **`BLOCKED — NOT RUN`** |
| **`PAT-10`** | Gerçek Windows ACL & firewall kapsam doğrulaması | Hub PC, standart kasiyer hesabı, aynı/farklı alt ağ cihaz | **`B2`** | `PAT-08` geçmiş | Kasiyere erişim engeli, `LocalSubnet` geçişi, `Public` profilde blok | **`BLOCKED — NOT RUN`** |
| **`PAT-11`** | Gerçek Android Release APK imzası, cleartext & Keystore kalıcılığı | Android cihaz (`minSdk 24+`) | **`B1`** (`key.properties` + `.jks`), **`B2`** | Release APK derlemesi başarılı | Debug imza yok, Google yedek kapalı, `http://` ret, reboot'ta token korunumu | **`BLOCKED — NOT RUN`** |
| **`PAT-12`** | Gerçek TLS sertifika rotasyonu, yabancı CA reddi & Re-pairing | Hub PC + eşleştirilmiş Android | **`B2`** (CA + rotasyon yaprağı + yabancı CA) + **`B1`** | Adım 1 bağımsız; adım 2–5 için `PAT-03` geçmiş | Aynı CA'da kesintisiz yenileme; yabancı CA'da `TLS_PIN_MISMATCH`; CA değişiminde onay | **`BLOCKED — NOT RUN`** |
| **`PAT-13`** | Gerçek Google OAuth & Drive şifreli yedek yükleme *(Opsiyonel)* | Windows kasa + internet + Google hesabı | **`C1` / `C2`** (`MMS_GDRIVE_CLIENT_ID`, `drive.file`) | C1+C2 yapılandırılmış | Yalnızca `drive.file` izni, `.mmsbak` yükleme, tekrar yüklememe | **`BLOCKED — NOT RUN`** |
| **`PAT-14`** | Restore sırasında süreç sonlandırma (elektrik kesintisi) | Windows kasa + düşük donanımlı Android | **`B1`** | Bekleyen 2 Outbox satırı + şifreli yedek | Journal kurtarması, `PRAGMA integrity_check=ok`, 2 Outbox korunumu, süre kaydı | **`BLOCKED — NOT RUN`** |
| **`PAT-15`** | Gerçek cihazda zamanlanmış yedek (uygulama açık / kapalı) | Android (`minSdk 24+`, şarjda) + Windows kasa | **`B1`** | 6 saatlik zamanlanmış yedek açık (`ADR-020` erteli) | Açıkken yedek & Lock koruması; kapalıyken açılışta gecikmiş yedek (Adım 4 `BLOCKED`) | **`BLOCKED — NOT RUN`** |

---

## 7. Geriye Dönük Uyumluluk

1. **`ADR-018` UDP `HUB_DISCOVERY_V1` v1.0:** Mevcut 6 alan (`service`, `protocol_version: "1.0"`, `hub_id`, `http_port`, `server_time`, `server_ips`) ve `HubDiscoveryResponder.getLocalLanIps()` davranışına hiç dokunulmaz.
2. **Pairing Payload (`v: 1`):** Mevcut JSON şeması değişmez; yalnızca Hub artık kanonik DER SHA-256 (`ca_fingerprint`) ve loopback olmayan deterministik LAN adresi (`hub_url`) üretir.
3. **Outbox, FIFO `client_seq`, Idempotency, Server Cursor, Tek-Yazarlı SQLite & Half-Up Kuruş:** Tamamı %100 korunur.
4. **Önceden Eşleştirilmiş Cihazların Günlük Senkronizasyonu:** Geçerli `device_token` + `pinnedCaPem` + `pinnedCaSha256` ile çalışan cihazların günlük senkronizasyonu hiçbir yeniden eşleştirme adımı gerektirmeden çalışmaya devam eder.

---

## 8. Açık Riskler ve `UNVERIFIED` / Fiziksel Doğrulama Gereksinimleri

1. **64-Bit Windows `GetAdaptersAddresses` & `GetIfEntry2` (`MIB_IF_ROW2`) FFI ABI Offset'leri (`UNVERIFIED`):** `IP_ADAPTER_ADDRESSES_LH`, `IP_ADAPTER_UNICAST_ADDRESS_LH` ve `MIB_IF_ROW2` (`InterfaceLuid`, `InterfaceIndex`, `InterfaceAndOperStatusFlags`, `TunnelType`) Windows x64 (`x86_64`) ABI offset'leri ve struct boyutları gerçek Windows x64 C++/MSVC referansı + canlı FFI testi + `NetworkInterface.list` çapraz kontrolüyle doğrulanana kadar **`UNVERIFIED`** kalır.
2. **Üretim İmza Anahtarı (`B1`) ve Üretim OpenSSL Sertifikaları (`B2`):** Owner tarafından sağlanmadan hiçbir release APK veya TLS fiziksel kabul testi yürütülemez.
3. **Çevre Temizliği (`D1..D4`):** Mevcut `MarketMmsSpike01` servisi, manuel test token'ları ve şifresiz test DB kopyaları yalnızca ayrı Owner kararıyla temizlenmelidir (bu görevde dokunulmamıştır).
4. **Fiziksel Mağaza Wi-Fi Topolojisi (`E1`):** Gerçek Android BoringSSL handshake, router AP izolasyonu, Windows Firewall profili ve düşük donanımlı Android PBKDF2 restore süreleri `PAT-01..15` (`BLOCKED — NOT RUN`) çalıştırılmadan doğrulanmış sayılmaz.
5. **Kapsam Dışı Teknik Borçlar:** `L-3` (`WindowsDpapiTokenStore.readSecret`), `ADR-019` (`DEFERRED_POST_PILOT`), `ADR-020` (`DEFERRED_POST_PILOT`).

---

## 9. Owner Onayı Gereken Kararlar (`DEC-REV-1..6`)

> [!IMPORTANT]
> Bu bölümdeki **hiçbir karar bu doküman tarafından otomatik olarak onaylanmamıştır**. `DEC-REV-5`, **`DEC-REV-1..4` kesin Owner onayı almadan `BLOCKED` kalacaktır**. `DEC-REV-6`, **fiziksel kabul testleri (`PAT-01..15`) ve üretim ön koşulları tamamlanana kadar `BLOCKED` kalacaktır**.

| Karar | Konu | Durum |
|---|---|---|
| **`DEC-REV-1`** | `P-BLOCK-1`: UTF-8 bağımsız DER/PEM ayrıştırma, dar `MmsX509PreValidator` ve OOB CA vs BoringSSL TLS ayrımı | **`APPROVAL REQUIRED`** |
| **`DEC-REV-2`** | `P-BLOCK-2`: `ALT-BOOT-2` izole bootstrap, proxy/sıkıştırma/gövde sınırları ve mutlak 5s timeout | **`APPROVAL REQUIRED`** |
| **`DEC-REV-3`** | `P-BLOCK-2`: Crash-safe `ACK_PENDING` re-pairing, idempotent `/ack`, Outbox/kimlik korunumu ve Loopback vs LAN SAN hata kategorisi ayrımı | **`APPROVAL REQUIRED`** |
| **`DEC-REV-4`** | `P-BLOCK-3`: `GetAdaptersAddresses` + `GetIfEntry2` (`HardwareInterface` + Hyper-V host `vEthernet`), `advertise_host` çift doğrulaması ve UDP v1.0 korunumu | **`APPROVAL REQUIRED`** |
| **`DEC-REV-5`** | TDD kodlama aşamasına geçiş yetkisi | **`BLOCKED`** *(DEC-REV-1..4 kesin Owner onayı bekler)* |
| **`DEC-REV-6`** | Fiziksel kabul testleri (`PAT-01..15`) ve pilot/üretim ilanı | **`BLOCKED`** *(Fiziksel testler ve B1/B2/D1..D4/E1 ön koşulları tamamlanana dek)* |

### Karar Detayları

1. **`DEC-REV-1` — DER, PEM ve X.509v3 İki Katmanlı CA Doğrulaması (`APPROVAL REQUIRED` · Teknik Öneri: `RECOMMENDED`)**
   - **Teknik karar:** Katman 1'de UTF-8 çözümlemesinden bağımsız byte-düzeyi PEM vs binary DER ayrıştırması (`TV-DER-01..05`); Katman 2'de yalnızca 3 dar görevle sınırlı `MmsX509PreValidator` (`v3`, `outerSigAlg == tbsSigAlg`, UTC `notBefore..notAfter`, `CA:TRUE`, `keyCertSign`, duplicate OID ve non-canonical `critical: FALSE` reddi) + `TV-X509-01..09`; DN eşitliğinin imza kanıtı sayılmayıp kriptografik TLS zincir doğrulamasının BoringSSL'e bırakılması; OOB CA fingerprint doğrulaması ile `server.crt` TLS doğrulamasının ayrı tutulması; `CertificateManager.generateRootCa` `-addext` uyumu ve `kSharedTestRootCaPem` sözleşmesi.
   - **Çözülen problem:** `P-BLOCK-1` Hub vs Android SHA-256 uyuşmazlığı, `F-1` `'0'` tuzağı, yüksek-bitli binary DER'in `utf8.decode` bağımlılığı, bozuk UTF-8/BOM sızıntısı ve `CA:FALSE` yaprak sertifikanın `ca.crt` sanılması.
   - **Kalan risk:** Saf Dart `MmsX509PreValidator` kriptografik imza doğrulamaz (BoringSSL'e bırakılır); özel test CA anahtarları üretim ortamında kullanılmamalıdır.
   - **Ön koşullar:** Owner yazılı onayı.
   - **Owner'dan beklenen açık karar:** Katman 1 + dar `MmsX509PreValidator` + BoringSSL ayrımı ve `kSharedTestRootCaPem` test sözleşmesinin onaylanıp onaylanmadığı.

2. **`DEC-REV-2` — `ALT-BOOT-2` İlk HTTPS Bootstrap ve Akış Sertleştirmesi (`APPROVAL REQUIRED` · Teknik Öneri: `RECOMMENDED`)**
   - **Teknik karar:** Normal ve Faz C/D istemcilerinde TLS doğrulaması gevşetilmeden, yalnızca `GET /api/v1/pairing/ca-cert` için sıfır-sır, `B-CB-1..6` koşullu, `findProxy = (_) => 'DIRECT'`, `autoUncompress = false` + `Accept-Encoding: identity` (`Content-Encoding` ≠ `identity` reddi), `contentLength != totalBytes` ve `65.537`'nci bayt akış kesicisi, redirect reddi, `5s` bağlantı/header + sıfırlanmayan `Timer(5s)` mutlak duvar saati body timeout'u ve `finally close(force: true)` ile bootstrap yürütülmesi.
   - **Çözülen problem:** `P-BLOCK-2` bootstrap handshake paradoksu, `F-2` blind-TOFU, `F-3` istemci yenilenmemesi, proxy sızması, gzip decompression bomb, çelişkili `Content-Length` yanıtları ve chunk-resetting Slowloris DoS.
   - **Kalan risk:** `M3` (Windows Host OS veya fiziksel OOB kanalının tamamen ele geçirilmesi durumunda ilk kurulumda kriptografik pinleme bunu yakalayamaz); LAN ağ seviyesi availability DoS.
   - **Ön koşullar:** `DEC-REV-1` ve Owner yazılı onayı.
   - **Owner'dan beklenen açık karar:** `ALT-BOOT-2` bootstrap izolasyon kurallarının, proxy/sıkıştırma/gövde sınırlarının ve mutlak `5s` timeout mekanizmasının onaylanıp onaylanmadığı.

3. **`DEC-REV-3` — Crash-Safe `ACK_PENDING` Re-pairing, İdempotent `/ack` ve Localhost SAN (`APPROVAL REQUIRED` · Teknik Öneri: `RECOMMENDED`)**
   - **Teknik karar:** `REPAIRING_CA_CHANGE_CONFIRMATION_REQUIRED` onay kapısı; 3 ayrı depoda eski token/pin/URL korunumu için `pairing_staged::$deviceId` (`POLL_RECEIVED → ACK_PENDING → ACK_CONFIRMED → P1..P4` + Startup Reconciliation); Hub tarafında `confirmedTokenSha256` + `confirmedAckChallengeId` ile imza re-verify destekli idempotent `/ack` (ve TTL içi `/ack-challenge`); re-pairing'de `/ack` öncesi eski Hub token'ının korunması; `outbox_operations`, `client_seq`, `device_id`, `tenant_id`, `store_id` değişmezliği; `IP:127.0.0.1` Loopback SAN eksikliğinde Hub exit `78` vs LAN SAN uyuşmazlığında Hub açık kalıp `503` üretmesi.
   - **Çözülen problem:** Hub `/ack` işleyip Android yanıt alamadan çöktüğünde yaşanan token kaybı ve `409`/`410` replay tıkanması, `device_pairing_client.dart:213` erken token ezme hatası, 3-depo çökme tutarsızlığı, `F-5`/`F-6`/`F-7` ve Windows localhost TLS `ipAddressMismatch`.
   - **Kalan risk:** `L-3` (`WindowsDpapiTokenStore.readSecret`) ayrı bakım borcu olarak açık kalır; `B2` üretim `server.crt` mutlaka `IP:127.0.0.1` içermelidir.
   - **Ön koşullar:** `DEC-REV-2` ve `B2` sertifikalarının `IP:127.0.0.1` SAN ile üretilmesi.
   - **Owner'dan beklenen açık karar:** `ACK_PENDING` durum makinesi, sunucu idempotent `/ack` protokolü ve Loopback SAN vs LAN SAN hata ayrımının onaylanıp onaylanmadığı.

4. **`DEC-REV-4` — Windows Network Adapter (`GetIfEntry2` / `HardwareInterface`) ve `advertise_host` (`APPROVAL REQUIRED` · Teknik Öneri: `RECOMMENDED`)**
   - **Teknik karar:** `GetAdaptersAddresses` + `GetIfEntry2` (`MIB_IF_ROW2.InterfaceAndOperStatusFlags.HardwareInterface`, `ConnectorPresent`, `TunnelType`) birleşiminin `Luid`/`IfIndex` ile ilişkilendirilmesi ve çalışma zamanında `NetworkInterface.list` çapraz doğrulaması; Tier 1 fiziksel NIC önceliği ve Tier 2 SAN-doğrulamalı Hyper-V External `vEthernet` host LAN bağlantısının korunması; `advertise_host` için **hem LAN SAN hem canlı yerel aktiflik** çift doğrulaması (LAN SAN eksikliğinde Hub kapanmaz, `/pairing/session` `503` döner); Windows x64 FFI offset'lerinin `UNVERIFIED` işaretlenip hatada fail-closed `503` dönmesi; `ADR-018` UDP v1.0 6 alanın korunması.
   - **Çözülen problem:** `P-BLOCK-3` `hub_url: 127.0.0.1` hatası, `GetAdaptersAddresses` tek başına donanım ayrımı yetersizliği, Hyper-V External Switch kullanan host kasaların yanlışlıkla dışlanması, VPN/WSL sızıntısı ve stale `advertise_host`.
   - **Kalan risk:** 64-bit Windows FFI struct offset'leri (`IP_ADAPTER_ADDRESSES_LH`, `IP_ADAPTER_UNICAST_ADDRESS_LH`, `MIB_IF_ROW2`) **`UNVERIFIED`** olup uygulama fazında MSVC/WinSDK + canlı Windows x64 FFI testleriyle doğrulanmalıdır.
   - **Ön koşullar:** Owner yazılı onayı (`hub_config.dart` `_allowedKeys` içine `advertise_host` eklenmesi dahil).
   - **Owner'dan beklenen açık karar:** `GetAdaptersAddresses` + `GetIfEntry2`, Tier 1/Tier 2 Hyper-V host `vEthernet` kuralı, `advertise_host` çift doğrulaması ve UDP v1.0 değişmezliğinin onaylanıp onaylanmadığı.

5. **`DEC-REV-5` — TDD Kodlama Aşamasına Geçiş Yetkisi (`BLOCKED`)**
   - **Teknik karar:** `HUB-T01..T09b`, `NET-01..08`, `APP-T01..T18` (tüm ek alt senaryolarla) testlerinin ve `P-BLOCK-1..3` düzeltmelerinin ayrı bir görevde TDD Red-Green-Refactor döngüsüyle kodlanması.
   - **Çözülen problem:** Owner onayı tamamlanmadan güvenlik ve protokol kodlamasına başlanmasının önlenmesi.
   - **Kalan risk:** Onaysız kodlama protokol ve güvenlik tutarsızlığı doğurur.
   - **Ön koşullar:** **`DEC-REV-1..4` kararlarının TAMAMININ Owner tarafından kesin olarak yazılı onaylanması** ve yeni kodlama görevinin verilmesi (bu koşul sağlanana kadar **`BLOCKED`**).
   - **Owner'dan beklenen açık karar:** `DEC-REV-1..4` kesin onaylandıktan sonra ayrı TDD kodlama görevine başlanıp başlanmayacağı.

6. **`DEC-REV-6` — Fiziksel Kabul Testleri (`PAT-01..15`) ve Pilot / Üretim İlanı (`BLOCKED`)**
   - **Teknik karar:** Gerçek Windows ve Android cihazlarda tek seferde bir adımla `PAT-01..15` saha kabul testlerinin yürütülmesi ve Owner kabulü sonrasında pilot/üretim ilanı.
   - **Çözülen problem:** Otomatik testlerin kapsayamadığı gerçek Android Release APK imzası, BoringSSL saha davranışı, gerçek Windows x64 donanım/Hyper-V adaptörleri, Windows SCM/ACL/Firewall ve mağaza Wi-Fi keşfinin doğrulanması.
   - **Kalan risk:** Mevcut durumda tüm `PAT-01..15` testleri **`BLOCKED — NOT RUN`** durumundadır ve hiçbir saha garantisi verilemez.
   - **Ön koşullar:** `DEC-REV-1..5` tamamlanması, canlı Windows x64 FFI doğrulamasının geçmesi, **`OWNER_ACTION_CHECKLIST.md` `B1`, `B2`, `D1..D4`, `E1`** üretim ön koşullarının tamamlanması (tümü tamamlanana kadar **`BLOCKED`**).
   - **Owner'dan beklenen açık karar:** Tüm teknik ve üretim ön koşulları tamamlandıktan sonra adım adım `PAT` kabul testlerinin başlatılması ve faz kabullerinin verilmesi.
