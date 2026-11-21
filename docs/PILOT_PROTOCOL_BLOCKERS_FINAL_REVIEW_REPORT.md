# MARKET MMS — `P-BLOCK-1..3` Son Teknik İnceleme ve Uygulama Öncesi Doğrulama Raporu

**Belge Durumu:** `OWNER REVIEW REQUIRED` (Salt Okunur Teknik İnceleme Raporu — Kodlama Yetkisi Verilmedi)  
**Tarih:** 21 Kasım 2026  
**Hedef Tasarım Dokümanı:** [`PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md`](./PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md)

> [!CAUTION]
> Bu rapor salt okunur inceleme ve doğrulama çıktısıdır. Hiçbir kaynak kodu, test, konfigürasyon, veritabanı, sertifika, secret, token veya `MarketMmsSpike01` servisi değiştirilmemiş; hiçbir test/build çalıştırılmamış; hiçbir Git `stage`/`commit`/`push`/`reset`/`checkout`/`clean` yapılmamıştır. `DEC-REV-1..6` kararlarının hiçbiri onaylanmış sayılmaz.

---

## 1. İncelenen Dokümanlar ve Salt Okunur Kod/Konfigürasyon Kaynakları

### 1.1 İncelenen Dokümanlar
- [`docs/PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md`](./PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md) (nihai güncellenen tam sürüm)
- [`docs/PILOT_PROTOCOL_BLOCKERS_ANALYSIS.md`](./PILOT_PROTOCOL_BLOCKERS_ANALYSIS.md) (önceki analiz taslağı)
- [`docs/PILOT_TECHNICAL_REMEDIATION_REPORT.md`](./PILOT_TECHNICAL_REMEDIATION_REPORT.md) (ADR-015…020 uygulama raporu ve 730 testlik baz çizgisi)
- [`docs/LIVE_PROJECT_STATUS.md`](./LIVE_PROJECT_STATUS.md) ve [`docs/PROJECT_STATUS.md`](./PROJECT_STATUS.md)
- [`docs/decisions/015-rel01-single-hub-config.md`](./decisions/015-rel01-single-hub-config.md) (`ADR-015`), [`017-snapshot-endpoint-and-tls-pin-classification.md`](./decisions/017-snapshot-endpoint-and-tls-pin-classification.md) (`ADR-017`), [`018-discovery-tls-scheme.md`](./decisions/018-discovery-tls-scheme.md) (`ADR-018`)
- [`OWNER_ACTION_CHECKLIST.md`](../OWNER_ACTION_CHECKLIST.md) (`B1`, `B2`, `D1..D4`, `E1`)
- [`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`](../PHYSICAL_ACCEPTANCE_TEST_PLAN.md) (`PAT-01..15`)

### 1.2 Salt Okunur İncelenen Kaynak Kod ve Bağımlılık Dosyaları
- [`pubspec.yaml`](../pubspec.yaml), [`packages/mms_client_storage/pubspec.yaml`](../packages/mms_client_storage/pubspec.yaml), [`test_spikes/spike_01_backend/pubspec.yaml`](../test_spikes/spike_01_backend/pubspec.yaml)
- [`lib/core/security/tls_pinned_client_factory.dart`](../lib/core/security/tls_pinned_client_factory.dart)
- [`lib/core/security/client_ecdsa_p256.dart`](../lib/core/security/client_ecdsa_p256.dart)
- [`lib/core/security/secure_token_store.dart`](../lib/core/security/secure_token_store.dart), [`windows_dpapi_token_store.dart`](../lib/core/security/windows_dpapi_token_store.dart), [`android_keystore_token_store.dart`](../lib/core/security/android_keystore_token_store.dart)
- [`lib/features/security/data/device_pairing_client.dart`](../lib/features/security/data/device_pairing_client.dart), [`domain/pairing_qr_payload.dart`](../lib/features/security/domain/pairing_qr_payload.dart)
- [`lib/features/security/presentation/widgets/device_security_card.dart`](../lib/features/security/presentation/widgets/device_security_card.dart), [`pairing_approval_panel.dart`](../lib/features/security/presentation/widgets/pairing_approval_panel.dart)
- [`lib/features/setup/domain/app_setup_config.dart`](../lib/features/setup/domain/app_setup_config.dart), [`data/local_setup_config_store.dart`](../lib/features/setup/data/local_setup_config_store.dart), [`application/setup_config_notifier.dart`](../lib/features/setup/application/setup_config_notifier.dart)
- [`lib/features/sync/application/hub_connection_notifier.dart`](../lib/features/sync/application/hub_connection_notifier.dart), [`sync_providers.dart`](../lib/features/sync/sync_providers.dart)
- [`test_spikes/spike_01_backend/lib/security/certificate_manager.dart`](../test_spikes/spike_01_backend/lib/security/certificate_manager.dart), [`pairing_manager.dart`](../test_spikes/spike_01_backend/lib/security/pairing_manager.dart), [`pairing_delivery_buffer.dart`](../test_spikes/spike_01_backend/lib/security/pairing_delivery_buffer.dart)
- [`test_spikes/spike_01_backend/lib/config/hub_config.dart`](../test_spikes/spike_01_backend/lib/config/hub_config.dart), [`lib/discovery/discovery_responder.dart`](../test_spikes/spike_01_backend/lib/discovery/discovery_responder.dart), [`lib/db/database.dart`](../test_spikes/spike_01_backend/lib/db/database.dart), [`bin/server.dart`](../test_spikes/spike_01_backend/bin/server.dart)

---

## 2. `P-BLOCK-1` Teknik Değerlendirmesi

- **UTF-8'den Bağımsız Byte-Düzeyi PEM vs Binary DER Tespiti ([§2.1](./PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md#L44-L60)):** Önceki taslaktaki `utf8.decode` başarısızlığı üzerinden fallback yapan yaklaşım kaldırıldı. Yeni tasarım girdi ham baytlarını ilk adımda BOM (`0xEF 0xBB 0xBF`) veya ASCII `-----BEGIN ` / `-----END ` dizisi için tarar. Yalnızca PEM adayı `utf8.decode(..., allowMalformed: false)` çalıştırır (hatada DER fallback yapılmaz); ikili DER yolu ise **`utf8.decode` hiç çağrılmadan** doğrudan `0x30` (`SEQUENCE`), canonical minimal DER length ve `headerLength + contentLength == rawBytes.length` ile doğrulanır. Böylece yüksek bitli (`>= 0x80`) ham binary X.509 DER dosyaları UTF-8 çözümlemesinden etkilenmezken `F-1` (`"0x30 comment trap\n-----BEGIN..."`) tuzağı PEM yoluna yönlendirilir.
- **Dar Kapsamlı `MmsX509PreValidator` ve ASN.1/DER Sınırları ([§2.2](./PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md#L61-L96)):** `MmsX509PreValidator` yalnızca 3 dar görevle sınırlandırıldı: (1) `ca.crt` için TLS öncesi X.509v3 yapı/tarih/uzantı ön kontrolü, (2) Bootstrap Faz B (`B-CB-5`) için `ca.subjectDer == leaf.issuerDer` bayt ön filtresi, (3) Hub tarafında `server.crt` IPv4 SAN (`0x87`, 4 bayt) çıkarımı. Özyinelemesiz cursor (`4..65536` byte, `depth <= 8`, `headerEnd + contentLength <= parentEnd`, `cursor == containerEnd`, indefinite length `0x80` reddi, minimal `INTEGER`/`BIT STRING`, non-canonical `critical: FALSE` reddi, duplicate OID reddi, UTC-only tarih) ve fail-closed `X509PreValidationException` tanımlandı.
- **DN Eşitliği vs Kriptografik İmza & CA OOB vs TLS Sunucu Doğrulaması Ayrımı ([§2.2.B](./PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md#L72-L82)):** `issuerDer == subjectDer` ve `ca.subjectDer == leaf.issuerDer` eşitliklerinin **imza doğrulaması olmadığı** korundu. İki doğrulama düzlemi kesin ayrıldı: `ca.crt` doğrulaması OOB SHA-256 `constantTimeEquals` + `MmsX509PreValidator` ile; `server.crt` imza, `server.key` sahipliği (`CertificateVerify`), geçerlilik ve SAN IP doğrulaması ise Faz C/D'de **BoringSSL** (`SecurityContext(withTrustedRoots: false)`, `badCertificateCallback => false`) tarafından yapılır.
- **Ortak Test CA ve Gerçek X.509 Test Vektörleri ([§2.3](./PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md#L97-L119)):** `TV-DER-01..05` (Katman 1 konteyner/hash) ile `TV-X509-01..09` (Katman 2 gerçek X.509v3 + binary DER sınırları) ayrıştırıldı; `kSharedTestRootCaPem` + `kSharedTestRootCaDerBytes` için test özel anahtarının üretimde kullanım yasağı ve `CertificateManager.generateRootCa` `-addext` zorunluluğu korundu.

---

## 3. `P-BLOCK-2` Teknik Değerlendirmesi

- **`ALT-BOOT-2` İzolasyonu ve TLS Gevşetme Yasağı ([§3.1](./PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md#L133-L154)):** Bootstrap istemcisi yalnızca `GET https://<targetHost>:<targetPort>/api/v1/pairing/ca-cert` uç noktasına erişebilir; hiçbir `device_token`, `pairing_secret`, `admin_secret`, `session_id`, `device_id`, `tenant_id`, `store_id`, `client_public_key`, `Authorization` veya çerez taşımaz ve `finally` bloğunda `close(force: true)` ile yok edilir. Faz C/D (`/request`, `/poll*`, `/ack*`) ve normal senkronizasyon istemcilerinde `badCertificateCallback => true` veya leaf bypass kesinlikle yasaktır.
- **Bootstrap Proxy, Sıkıştırma, Çelişkili Gövde, Redirect ve Mutlak Timeout ([§3.3](./PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md#L171-L187)):**
  - **Proxy Yasağı:** `bootstrapClient.findProxy = (Uri _) => 'DIRECT';` ile sistem/env proxy (`HTTP_PROXY`/`HTTPS_PROXY`) atlanır.
  - **Sıkıştırma Yasağı:** `bootstrapClient.autoUncompress = false;` + `Accept-Encoding: identity` zorunludur; `Content-Encoding` başlığı `'identity'` dışında bir değer taşıyorsa gövde okunmadan `INVALID_CA_CERT` ile reddedilir.
  - **Gövde Sınırı & Çelişkili Başlık:** `contentLength == 0 || contentLength < -1 || contentLength > 65536` ön reddi; `65.537`'nci baytta ve `totalBytes > contentLength` anında stream iptali; `onDone`'da `totalBytes == 0` veya `contentLength >= 0 && totalBytes != contentLength` çelişkisinde `INVALID_CA_CERT`.
  - **Redirect & Timeout:** `followRedirects = false`, `maxRedirects = 0` (`3xx` → `BOOTSTRAP_REDIRECT_FORBIDDEN`), `5s` TCP/TLS ve header timeout'u + `Stream.timeout` yerine sıfırlanmayan **`Timer(Duration(seconds: 5))`** mutlak duvar saati body timeout'u (`BOOTSTRAP_TIMEOUT`).
- **Crash-Safe Re-pairing — `ACK_PENDING` ve Sunucu İdempotent `/ack` ([§3.4](./PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md#L188-L266)):**
  - **Giderilen Kritik Çökme Boşluğu:** Önceki `POLL_RECEIVED → ACK_CONFIRMED` akışında **Hub `/ack`'yı başarıyla işleyip Android yanıtı alamadan çökerse**, Android açılışta `POLL_RECEIVED`'ı silip yeni token'ı kaybediyor; Hub ise mevcut [`pairing_manager.dart:504,549,574`](../test_spikes/spike_01_backend/lib/security/pairing_manager.dart#L504-L581) kodunda `409 CHALLENGE_ALREADY_CONSUMED` / `410 TOKEN_BUFFER_EXPIRED` döndürüyordu.
  - **Yeni Protokol:** İstemci `/ack` göndermeden **hemen önce** `pairing_staged::<deviceId>` kaydını kalıcı **`ACK_PENDING`** (`ack_challenge_id`, `ack_signature_b64`, `session_id`, `pairing_secret`, `token`, `ca_sha256`, `ca_pem`, `hub_url`) durumuna günceller. Hub ise ilk `/ack` sonrası ham token'ı RAM'den silmeye devam ederken `PairingSession` üzerinde `confirmedTokenSha256` + `confirmedAckChallengeId` + `confirmedAckChallengeNonce` özetini oturum TTL süresince saklar; tekrar gelen aynı `/ack` isteğinde imzayı yeniden doğrulayarak mükerrer DB yazımı olmadan idempotent **`200 OK` (`idempotent_replay: true`)** döner (imza geçersizse `403`).
  - **Startup Reconciliation & Değişmezler:** `ACK_PENDING` durumunda açılışta aynı `/ack` güvenli tekrar gönderilir (TTL/restart durumunda `Bearer <staged.token>` yoklamasıyla doğrulanır). Yeni token, pin ve Hub URL terfisi (`P1..P4`) yalnızca `ACK_CONFIRMED` sonrası çalıştırılır; öncesinde eski aktif kimlik/pin/URL %100 korunur. `outbox_operations`, `client_seq`, `device_id`, `tenant_id` ve `store_id` asla sıfırlanmaz.
- **Windows Localhost TLS & Hata Kategorisi Ayrımı ([§3.5](./PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md#L267-L277)):** `server.crt` içinde `IP:127.0.0.1` Loopback SAN eksikliği Hub startup'ta çıkış kodu `78` ile durdururken; yalnızca LAN / `advertise_host` SAN uyuşmazlığı Hub'ı tamamen kapatmaz (`503 ERR_ADVERTISE_HOST_SAN_MISMATCH`).

---

## 4. `P-BLOCK-3` Teknik Değerlendirmesi

- **`GetAdaptersAddresses` + `GetIfEntry2` (`MIB_IF_ROW2.HardwareInterface`) Gerekliliği ([§4.1](./PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md#L280-L306)):** `GetAdaptersAddresses` tek başına fiziksel donanım ayrımını garanti etmez (`IfType == 6` Hyper-V `vEthernet` veya yazılım köprülerinde de raporlanır). Bu nedenle `iphlpapi.dll` üzerinde **`GetAdaptersAddresses` + `GetIfEntry2` (veya `GetIfTable2`) birlikte** kullanılacaktır. Adaptör IPv4 bilgileri ile donanım bayrakları (`HardwareInterface`, `ConnectorPresent`, `PhysicalMediumType`, `TunnelType`) birincil `Luid` (`NET_LUID`) ve ikincil `IfIndex` (`NET_IFINDEX`) anahtarıyla birleştirilir; ayrıca çalışma zamanında Dart `NetworkInterface.list` `(index, address)` çıktısıyla çapraz doğrulanır.
- **Hyper-V Host `vEthernet` LAN Bağlantısının Korunması ([§4.2](./PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md#L307-L341)):** Fiziksel NIC'in Hyper-V External Virtual Switch'e bağlandığı Windows makinelerde IPv4 yığını `vEthernet (<SwitchAdı>)` üzerinde (`HardwareInterface == 0`, `IfType == 6`) taşınır. İki kademeli seçim modeli tanımlandı: Tier 1 (`HardwareInterface == 1`) SAN adayları varsa öncelik alır; hiç Tier 1 SAN adayı yoksa, izole/NAT/VPN listesinde olmayan (`Default Switch`, `WSL`, `Docker`, `VMnet`, `WireGuard`, `Tailscale` hariç) ve **IPv4 adresi `server.crt` SAN içinde bulunan** Tier 2 host `vEthernet`/Bridge adaptörü geçerli LAN adayı olarak kabul edilir.
- **`UNVERIFIED` Windows x64 FFI Sınırı ve Fail-Closed Davranış ([§4.1](./PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md#L298-L306)):** `IP_ADAPTER_ADDRESSES_LH`, `IP_ADAPTER_UNICAST_ADDRESS_LH` ve `MIB_IF_ROW2` struct boyut ve offset'leri **`UNVERIFIED`** olarak korundu. Kodlama fazında MSVC/WinSDK `sizeof`/`offsetof` kontrolü ve gerçek Windows x64 FFI testi zorunludur; çalışma zamanında FFI/cross-check hatasında sessiz varsayım veya `127.0.0.1` fallback'i yapılmaz, fail-closed **`503 ERR_HUB_LAN_IP_UNAVAILABLE`** dönülür.
- **`advertise_host` Çift Doğrulaması ve UDP v1.0 Korunumu ([§4.3](./PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md#L342-L362)):** `advertise_host` hem `server.crt` SAN üyeliği hem canlı yerel aktif (Tier 1 veya Tier 2) IPv4 üyeliği için çift doğrulanır. Loopback SAN eksikliği (`exit 78`) ile LAN SAN uyuşmazlığı (Hub açık kalır, `/pairing/session` `503`) ayrı hata kategorileri olarak korundu. `HubDiscoveryResponder.getLocalLanIps()` ve 6 alanlı UDP `HUB_DISCOVERY_V1` v1.0 protokolü değiştirilmeden korundu.

---

## 5. Yeni Teknik Bulgular ve Çözülen Riskler Özeti

1. **UTF-8 Çözümleme Bağımlılığı → [§2.1](./PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md#L44-L60):** Binary DER ayrıştırma yolu artık `utf8.decode` çağrısı veya hatası üzerinden karar vermez; ham byte taraması (BOM / `-----BEGIN ` / `-----END `) PEM ile binary DER'i deterministik ayırır.
2. **Bootstrap Proxy, Sıkıştırma ve Çelişkili Gövde Açığı → [§3.3](./PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md#L171-L187):** `findProxy = DIRECT`, `autoUncompress = false`, `Accept-Encoding: identity`, `Content-Encoding` reddi ve `totalBytes != contentLength` kontrolü eklendi.
3. **Hub `/ack` İşleyip Android Yanıt Alamadan Çökme Açığı → [§3.4](./PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md#L188-L266):** Kalıcı `ACK_PENDING` durumu + Hub tarafında imza yeniden doğrulamalı idempotent `/ack` (ve TTL içi `/ack-challenge`) + re-pairing eski token korunumu eklendi.
4. **`GetAdaptersAddresses` `IfType == 6` ve Hyper-V Host `vEthernet` Yanlış Eleme Riski → [§4.1–4.2](./PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md#L280-L341):** `GetIfEntry2` (`MIB_IF_ROW2.HardwareInterface`) `Luid`/`IfIndex` birleşimi + Tier 1/Tier 2 kuralı ile hem sanal adaptör sızıntısı önlendi hem Hyper-V External `vEthernet` host LAN bağlantısı korundu.
5. **Loopback SAN vs LAN SAN Kapanma Kategorisi Ayrımı → [§3.5](./PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md#L267-L277) & [§4.3](./PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md#L342-L362):** `IP:127.0.0.1` eksikliği startup `exit 78`; LAN/`advertise_host` SAN uyuşmazlığı Hub'ı kapatmadan `/pairing/session` üzerinde `503 ERR_ADVERTISE_HOST_SAN_MISMATCH`.
6. **Önceki Çözümler (Korunan):** DN eşitliği vs BoringSSL imza ayrımı ([§2.2.B](./PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md#L72-L82)), Slowloris mutlak 5s `Timer` ([§3.3](./PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md#L171-L187)), `127.0.0.1` SAN kesim öncesi temizliği (`HUB-T03` vs `HUB-T05`, [§4.3](./PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md#L342-L362)).

---

## 6. Açık Kalan `UNVERIFIED` Maddeler

1. **`UNVERIFIED` — 64-Bit Windows `iphlpapi.dll` `GetAdaptersAddresses` & `GetIfEntry2` (`MIB_IF_ROW2`) FFI ABI Offset'leri ([§4.1](./PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md#L298-L306)):** Salt okunur tasarım revizyonu olduğu ve derleme/test çalıştırılmadığı için `IP_ADAPTER_ADDRESSES_LH`, `IP_ADAPTER_UNICAST_ADDRESS_LH` ve `MIB_IF_ROW2` (`InterfaceLuid`, `InterfaceIndex`, `InterfaceAndOperStatusFlags`, `TunnelType`) x64 struct boyut ve offset'leri gerçek Windows x64 ortamında doğrulanmamıştır. Uygulama fazında MSVC/WinSDK referansı, canlı Windows x64 FFI testi ve `NetworkInterface.list` çapraz doğrulaması zorunludur.
2. **`UNVERIFIED` — Gerçek Android Cihaz / BoringSSL / Router Ortamı:** OpenSSL ile üretilmiş `B2` sertifikalarının Android 7.0+ (`minSdk 24`) BoringSSL üzerinde ağ rotasyonu ve Wi-Fi keşif davranışı `PAT-03`, `PAT-11`, `PAT-12` yapılmadığı için sahada henüz doğrulanmamıştır.

---

## 7. Güvenlik Tehdit Modeli (`M1..M7`)

- **Engellenen Vektörler:** Sahte CA/sunucu (`M1`), JSON `ca_fingerprint`/`http://` manipülasyonu (`M2`), mevcut cihazda sessiz re-pairing (`M3`/`M7` kısmen), `3xx` redirect / proxy tüneli / `http://` downgrade (`M4`), gzip bombası / çelişkili `Content-Length` / `>64 KB` / Slowloris damla DoS (`M5`), `CA:FALSE` / eksik `keyCertSign` / bozuk X.509 (`M6`), `/ack` yanıt kaybı / çökme kaynaklı token-pin uyumsuzluğu ve Outbox/kimlik kaybı (`M7`).
- **Engellenemeyen Artık Riskler:** İlk eşleştirmede Windows Host OS veya fiziksel OOB kanalının tamamen ele geçirilmesi (`M3`), ağ seviyesi availability DoS / AP izolasyonu, fiziksel OS keystore/DPAPI disk bozulması ve kapsam dışı `L-3` (`windows_dpapi_token_store.dart:251-261`).

---

## 8. Test Matrisi ve Gerçek Durum Ayrımı

| Test Grubu | Kapsam | Mevcut Gerçek Durum |
|---|---|---|
| **Mevcut Kodlanmış Baz Çizgisi** | `PILOT_TECHNICAL_REMEDIATION_REPORT.md` kapsamındaki 730 test | Önceki oturumda geçmiştir; **bu salt okunur görevde `0` test çalıştırılmıştır** (P-BLOCK-1..3 düzeltmelerini henüz içermez). |
| **Planlanan Hub Testleri (`HUB-T01..T09b`, `NET-01..08`)** | Mevcut ID'ler korundu; yeni eklenenler: **`HUB-T01d`** (UTF-8 bağımsız binary DER/PEM), **`HUB-T04c`** (`MIB_IF_ROW2.HardwareInterface` / `GetIfEntry2`), **`HUB-T04d`** (Hyper-V host External `vEthernet` `NET-02b`), **`HUB-T09b`** (idempotent `/ack` replay & re-pairing token korunumu) | **`PLANNED — NOT CODED / NOT RUN`** |
| **Planlanan İstemci Testleri (`APP-T01..T18`)** | Mevcut ID'ler korundu; yeni eklenenler: **`APP-T01c`** (binary DER/PEM sınırları), **`APP-T05b`** (proxy `DIRECT`), **`APP-T15c`** (`Content-Encoding`/çelişkili `Content-Length`), **`APP-T16c`** (`ACK_PENDING` yanıt kaybı), **`APP-T16d`** (`P1..P4` terfi çökmesi), **`APP-T16e`** (idempotent `/ack` & TTL/restart yoklaması) | **`PLANNED — NOT CODED / NOT RUN`** |
| **Denetim Kontrol Listesi (`AUD-01..25`)** | Bağımsız güvenlik doğrulama maddeleri ([§6.3](./PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md#L483-L490)) | Tasarım doğrulama listesi (`DEC-REV-5` sonrası koda eşlenecek). |
| **Fiziksel Saha Kabul Testleri (`PAT-01..15`)** | Gerçek donanım, `B1`, `B2`, `D1..D4`, `E1` gerektiren saha testleri ([§6.4](./PILOT_PROTOCOL_BLOCKERS_FINAL_DESIGN.md#L491-L515)) | **`BLOCKED — NOT RUN`** |

---

## 9. Owner Karar Tablosu (`DEC-REV-1..6`)

Hiçbir karar otomatik onaylanmamıştır; `DEC-REV-5`, `DEC-REV-1..4` kesin Owner onayı almadan `BLOCKED` kalır; `DEC-REV-6`, fiziksel kabul testleri ve üretim ön koşulları tamamlanana kadar `BLOCKED` kalır.

| ID | Durum | Teknik Karar | Çözülen Problem | Kalan Risk | Ön Koşullar | Owner'dan Beklenen Açık Karar |
|---|---|---|---|---|---|---|
| **`DEC-REV-1`** | **`APPROVAL REQUIRED`** *(Recommended)* | UTF-8 bağımsız byte-düzeyi PEM/DER ayrıştırma (`TV-DER-01..05`), 3-görevli dar `MmsX509PreValidator` (`TV-X509-01..09`), DN≠imza kuralı, BoringSSL zincir doğrulaması ve OOB CA vs TLS sunucu ayrımı; `generateRootCa` `-addext`. | `P-BLOCK-1` SHA-256 uyuşmazlığı, `F-1` `'0'` tuzağı, binary DER UTF-8 bağımlılığı, `CA:FALSE`/bozuk CA kabulü. | `MmsX509PreValidator` kriptografik imza doğrulamaz (BoringSSL doğrular); test CA anahtarı üretimde yasak kalmalıdır. | Owner yazılı onayı. | `P-BLOCK-1` tasarımının ve ortak test CA sözleşmesinin onaylanması. |
| **`DEC-REV-2`** | **`APPROVAL REQUIRED`** *(Recommended)* | `ALT-BOOT-2` sıfır-sır yalnızca `/pairing/ca-cert`, `B-CB-1..6`, `findProxy = DIRECT`, `autoUncompress = false`, `Content-Encoding` ≠ `identity` reddi, `contentLength != totalBytes` ve `65.537` byte kesicisi, mutlak 5s `Timer`, Faz C/D/sync TLS gevşetme yasağı. | `P-BLOCK-2` bootstrap paradoksu, `F-2` blind-TOFU, `F-3`, proxy sızması, gzip bombası, çelişkili gövde ve Slowloris. | `M3` (Host OS / OOB tamamen ele geçirilirse ilk kurulumda yakalanamaz); LAN flood availability DoS. | `DEC-REV-1` + Owner yazılı onayı. | `ALT-BOOT-2` izolasyonu ile proxy/sıkıştırma/gövde/timeout kurallarının onaylanması. |
| **`DEC-REV-3`** | **`APPROVAL REQUIRED`** *(Recommended)* | Re-pairing onay kapısı; `POLL_RECEIVED → ACK_PENDING → ACK_CONFIRMED → P1..P4` + Startup Reconciliation; sunucu idempotent `/ack` (`confirmedTokenSha256`) ve re-pairing eski token korunumu; Outbox/`client_seq`/kimlik değişmezliği; Loopback SAN (`exit 78`) vs LAN SAN (`503`) ayrımı. | Hub `/ack` işleyip Android yanıt alamadan çökme senaryosu, erken token ezme (`device_pairing_client.dart:213`), 3-depo uyumsuzluğu, `F-5`/`F-6`/`F-7` ve `127.0.0.1` SAN hatası. | `L-3` DPAPI tekil anahtar borcu kapsam dışı açık kalır; `B2` `server.crt` `IP:127.0.0.1` içermelidir. | `DEC-REV-2` + `B2` sertifikalarında `IP:127.0.0.1` SAN. | `ACK_PENDING` akışı, idempotent `/ack` ve Loopback vs LAN SAN hata ayrımının onaylanması. |
| **`DEC-REV-4`** | **`APPROVAL REQUIRED`** *(Recommended)* | `GetAdaptersAddresses` + `GetIfEntry2` (`MIB_IF_ROW2.HardwareInterface`) `Luid`/`IfIndex` birleşimi + `NetworkInterface.list` çapraz kontrolü; Tier 1 fiziksel + Tier 2 SAN-doğrulamalı Hyper-V host `vEthernet`; `advertise_host` çift doğrulaması; UDP v1.0 6 alan korunumu. | `P-BLOCK-3` `127.0.0.1` QR sızıntısı, `IfType == 6` yanıltması, Hyper-V External `vEthernet` yanlış elenmesi, stale `advertise_host`. | Windows x64 FFI struct offset'leri **`UNVERIFIED`**; uygulama fazında canlı Windows x64 FFI testiyle doğrulanmalıdır. | Owner yazılı onayı (`hub_config.dart` `advertise_host` izni dahil). | `GetAdaptersAddresses` + `GetIfEntry2`, Hyper-V host `vEthernet` kuralı, `advertise_host` ve UDP v1.0 korunumunun onaylanması. |
| **`DEC-REV-5`** | **`BLOCKED`** | `P-BLOCK-1..3` düzeltmelerinin ve planlanan yeni TDD testlerinin (`HUB-T01..T09b`, `NET-01..08`, `APP-T01..T18`) ayrı bir uygulama görevinde kodlanması. | Tasarım kesinleşmeden ve Owner onayı olmadan koda geçilmesinin önlenmesi. | Onaysız kodlama protokol ve güvenlik tutarsızlığı doğurur. | **`DEC-REV-1..4` kararlarının TAMAMININ kesin Owner onayı**. | `DEC-REV-1..4` onaylandıktan sonra ayrı TDD kodlama görevine yetki verilmesi. |
| **`DEC-REV-6`** | **`BLOCKED`** | Gerçek cihazlarda tek seferde bir adımla `PAT-01..15` kabul testlerinin yürütülmesi ve pilot/üretim ilanı. | Saha donanımı, APK imzası, BoringSSL, Windows x64 FFI, SCM/ACL/Firewall ve mağaza Wi-Fi risklerinin kanıtlanması. | Tüm `PAT-01..15` testleri `BLOCKED — NOT RUN` durumundadır. | `DEC-REV-1..5` + canlı Windows x64 FFI doğrulaması + `B1`, `B2`, `D1..D4`, `E1` ön koşulları. | Ön koşullar tamamlandığında adım adım `PAT-01..15` başlatılması ve faz kabulleri. |

---

## 10. Kodlama Öncesi Kalan Blokajlar

1. **Owner Tasarım Onayı:** `DEC-REV-1..4` için açık yazılı Owner kararı ve ardından ayrı görev olarak `DEC-REV-5` kodlama yetkisi.
2. **Üretim Anahtar ve Sertifikaları:** `OWNER_ACTION_CHECKLIST.md` `B1` (`android/key.properties` + `.jks`) ve `B2` (`ca.crt` [`CA:TRUE`, `keyCertSign`, `cRLSign`, SAN yok] + `server.crt` [`IP:127.0.0.1` + LAN SAN] + `server.key`).
3. **Ortam Temizliği ve Donanım:** `D1..D4` (`MarketMmsSpike01` ve test kalıntıları için ayrı Owner kararı) ve `E1` pilot donanımı.
4. **Canlı Windows x64 FFI Doğrulaması:** Uygulama aşamasında `GetAdaptersAddresses` ve `GetIfEntry2` (`MIB_IF_ROW2`) bellek offset'lerinin `UNVERIFIED` durumdan canlı testle çıkarılması.

**TASARIM REVİZYONU TAMAMLANDI — OWNER KARARI BEKLENİYOR — KODLAMA YETKİSİ VERİLMEDİ.**
