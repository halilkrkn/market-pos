# ADR 018: Hub Keşfinde TLS — İstemci Tarafı Şema Seçimi ve Manuel Eşleştirme Protokolü (TLS-DISC)

- **Durum:** **CONFIRMED** — Bölüm 2.1 (eşleştirilmiş cihaz keşfinde yalnızca `https://`) **CONFIRMED**; Bölüm 2.2 (**Seçenek C: UDP protokolünde değişiklik yok**) Owner kararı ile **CONFIRMED**
- **Tarih:** 2026-11-21
- **Karar Vericiler:** Owner (Onay — §2.1 + §2.2 Seçenek C), Öneren: Claude Code / Uygulayan: Antigravity
- **İlgili:** ADR-012, ADR-015 (REL-01: üretimde TLS zorunlu), ADR-017 (TLS pin sınıflandırması)

---

## 1. Bağlam

UDP keşif yanıtı (`lib/discovery/discovery_responder.dart`) şu alanları taşır: `service`, `protocol_version` (`"1.0"`), `hub_id`, `http_port`, `server_time`, `server_ips`. Şema/TLS bilgisi yoktur.

İstemci (`UdpHubDiscoveryClient`) adayları sabit `defaultScheme = 'http'` ile `http://<ip>:<port>` olarak üretiyordu. Oysa:
- Üretim Hub'ı yalnızca TLS konuşur (REL-01, `environment: production` → TLS zorunlu);
- Release APK'da cleartext kapalıdır (`usesCleartextTraffic=false`).

**Sonuç:** Üretimde otomatik keşif Hub'ı bulsa bile hiçbir adaya bağlanamaz; Faz 1 "Otomatik Hub Keşfi" yalnızca TLS'siz geliştirme Hub'ında çalışıyordu. Bu durum otomatik testlerde görünmüyordu çünkü testler TLS'siz Hub kullanıyor.

## 2. Karar

### 2.1 Uygulandı — istemci tarafı şema seçimi (protokol DEĞİŞMEDİ)
- Cihaz eşleştirilmişse (kurulumda CA pin'i var) keşif adayları **yalnızca `https://`** olarak üretilir; sağlık kontrolü mevcut sabitlenmiş TLS istemcisiyle (`apiClientProvider`) yapılır. HTTPS başarısızsa **HTTP'ye düşülmez** (downgrade yok).
- Pin yoksa (geliştirme Hub'ı, ilk kurulum) davranış değişmez: `http://`.
- Şema her keşif turunda güncel pin'e göre çözülür (`UdpHubDiscoveryClient.schemeResolver`); sağlayıcı pin'i `watch` etmez, böylece eşleştirme sonrası bağlantı yöneticisi yeniden kurulup durumunu kaybetmez.
- Eski Hub'larla tam uyumlu: yanıt biçimi aynı, eski Hub'lar da TLS açıkken HTTPS kabul eder.
- **Testler:** `test/features/sync/discovery_tls_scheme_test.dart` (5; `HubConnectionNotifier.discoverAndConnect` yalnızca `https://` yoklar, hatada `http://` fallback yapmaz), `test/features/security/pairing_qr_payload_test.dart` (2; `ca_fingerprint` normalleştirme ve `UNKNOWN` -> `null`), `test_spikes/spike_01_backend/test/hub_discovery_responder_test.dart` (7; UDP yanıtında `tls`/`ca_sha256` yok, `protocol_version: "1.0"`).

### 2.2 Owner Kararı — Keşif Yanıtına TLS Alanı Eklenmemesi (**CONFIRMED — Seçenek C**)

| Seçenek | Açıklama | Durum |
|---|---|---|
| A. Ek alan | Yanıta `tls` ve `ca_sha256` eklenmesi | Seçilmedi |
| B. Sürüm artırımı | `protocol_version: "1.1"` | Seçilmedi |
| **C. Değişiklik yok** | UDP discovery `protocol_version: "1.0"` ile değişmeden kalır; TLS ve CA pin kurulumu eşleştirme akışı üzerinden yapılır | **CONFIRMED** |

### 2.3 Eşleştirme QR/JSON Uyumluluğu ve Tespit Edilen Pilot Bloklayıcıları (`P-BLOCK-1..3`)

- **QR / JSON Yük Ayrıştırma Düzeltmesi:** `PairingQrPayload` artık Hub'ın `/api/v1/pairing/session` yanıtındaki `ca_fingerprint` (ve `caFingerprint`) anahtarını okur; `UNKNOWN` veya boş değerleri `caSha256 = null` olarak temizler.
- **Manuel Eşleştirme Gerçeği:** Windows yönetim paneli (`pairing_approval_panel.dart`) ekrana kopyalanabilir JSON/QR metni üretir; yerleşik QR görseli (`qr_flutter`) yoktur. Android ilk kurulumda metni yapıştırarak veya harici araçla oluşturulan QR'ı tarayarak eşleşir.
- **Açık Pilot Bloklayıcıları (Protokol/Güvenlik Dokunulmazlığı Nedeniyle Owner Kararı Gerektirir):**
  1. **`P-BLOCK-1` (PEM vs DER Parmak İzi Uyuşmazlığı):** Hub `server.dart` `/api/v1/pairing/session` içinde `ca_fingerprint` değerini CA PEM dosyasının ham baytlarından hesaplıyor; Android istemcisi (`MmsPinnedTlsClientFactory` / `DevicePairingClient`) ise X.509 sertifika DER baytlarının SHA-256 özetini bekliyor. İki özet farklı olduğu için QR içindeki `ca_fingerprint` doğrudan pin ile eşleşmez.
  2. **`P-BLOCK-2` (İlk `/pairing/ca-cert` İsteğinde Leaf Pin Takılması):** `DevicePairingClient`, `initialCaPem == null && expectedCaSha256 != null` durumunda CA PEM'i indirmek için `MmsPinnedTlsClientFactory.createClient(PinnedTlsConfig(expectedSha256Hex: expectedCaSha256))` kurar. CA PEM henüz olmadığı için istemci doğrudan leaf sertifikayı CA SHA-256 ile karşılaştırır ve kendi `ca-cert` indirme isteğini reddeder; ayrıca `resolvedCaPem` alındıktan sonra HTTP istemcisini yenilemez.
  3. **`P-BLOCK-3` (`hub_url` Loopback Üretimi):** `server.dart` `/api/v1/pairing/session`, oturumu Windows üzerindeki yerel kasadan açıldığında `req.requestedUri` üzerinden `hub_url: "https://127.0.0.1:8945"` üretir. Android tarafında `HubUrlValidator(allowLoopback: false)` loopback adresi reddettiğinden operatör Android'de Hub'ın LAN IP'sini elle girmelidir.

## 3. Sonuçlar
- Keşif protokolü değişmeden eşleştirilmiş cihazlarda HTTPS zorunluluğu ve downgrade koruması doğrulandı; gerçek Wi-Fi + QR eşleştirme (`PAT-03`, `PAT-12`) yukarıdaki `P-BLOCK-1..3` Owner kararı ve fiziksel donanım eksikliği nedeniyle **BLOCKED**.
- Owner kararı: `OWNER_ACTION_CHECKLIST.md` → `A4` ve `P-BLOCK-1..3`.
