# ADR 017: Şifresiz Snapshot Ucunun Kapatılması ve TLS Pin / Sertifika Doğrulama Sınıflandırması

- **Durum:** **PARTIALLY_CONFIRMED / IN_REVIEW** (Snapshot endpoint loopback + `ADMIN_SECRET` koruması **CONFIRMED**; TLS sınıflandırma düzeltmesi uygulandı ve otomatik soket testleriyle doğrulandı — gerçek cihaz/sertifika rotasyonu PAT-12 **BLOCKED**, nihai onay Owner incelemesinde)
- **Tarih:** 2026-11-21
- **Karar Vericiler:** Owner (Snapshot onayı), Öneren: Claude Code / Uygulayan: Antigravity (TLS sınıflandırma düzeltmesi)

---

## 1. Bağlam

1. **SEC-SNAP (`CONFIRMED`):** `POST /api/v1/backup/snapshot`, geçerli **herhangi bir** cihaz token'ı ile `VACUUM INTO` üzerinden merkezi `market_master.db`'nin **şifresiz** kopyasını Hub diskine yazıyor ve dosya yolunu döndürüyordu.
2. **TLS-PIN / CA-Pin Sınıflandırma Hatası (Düzeltildi):** Önceki implementasyonda `MmsPinnedTlsClientFactory` (`lib/core/security/tls_pinned_client_factory.dart`), CA PEM + CA parmak izi verildiği durumda dahi `badCertificateCallback` içinde sunulan leaf SHA-256 ile CA SHA-256 değerini karşılaştırıyordu ve reddedilen tüm el sıkışma hatalarını `TlsPinMismatchException` olarak fırlatıyordu. Bu durum:
   - Aynı CA ile imzalı sertifikadaki IP SAN eksikliğini, hostname/SAN uyuşmazlığını veya süre dolumunu yanlışlıkla "pin mismatch" gibi gösteriyordu;
   - Çoklu CA PEM bloğunda sabitlenmeyen ekstra sertifikaların güven bağlamına sızmasına karşı yalıtım içermiyordu.

## 2. Karar

1. **Snapshot Ucu (`CONFIRMED`):** `/api/v1/backup/snapshot` yalnızca **loopback + yapılandırılmış `ADMIN_SECRET`** ile çağrılabilir (`_verifyLoopbackAndAdmin`). Cihaz token'ı tek başına 401/403 alır ve diske dosya yazılmaz.
2. **CA-Pin vs Leaf-Pin İzolasyonu (`MmsPinnedTlsClientFactory`):**
   - `expectedSha256Hex` CA PEM içindeki bir sertifikayla eşleşiyorsa (`expectedMatchesCaPem`), **yalnızca** eşleşen CA sertifikası `SecurityContext(withTrustedRoots: false)` içine yüklenir (CA-bundle smuggling önlenir). Bu modda `badCertificateCallback` **hiçbir zaman** `true` dönmez ve yaprak ile CA SHA-256 değerini karşılaştırmaz.
   - Aynı CA tarafından yenilenen, geçerli tarihli ve SAN eşleşen sunucu sertifikaları BoringSSL doğrulamasından geçer ve **kabul edilir** (yeniden eşleştirme gerekmez).
   - CA PEM yoksa veya pin CA ile eşleşmiyorsa doğrudan yaprak SHA-256 sabitlemesi uygulanır; uyuşmazlık `TlsPinMismatchException(reason: TlsPinMismatchReason.leafPinMismatch)` üretir.
3. **7 TLS Durumunun Ayrıştırılması (Fail-Closed, HTTP Fallback Yok):**
   - **Aynı CA ile yenilenmiş geçerli sertifika:** Kabul edilir (`200`).
   - **Farklı CA / güven zinciri hatası / olası MITM** (`unable to get local issuer certificate`, `self signed certificate` vb. — sahte CA'da IP SAN uyuşmasa dahi zincir kontrolü önceliklidir): `TlsPinMismatchException(..., reason: TlsPinMismatchReason.untrustedCaChain)` (`TLS_PIN_MISMATCH`).
   - **Doğrudan leaf pin uyuşmazlığı:** `TlsPinMismatchException(..., reason: TlsPinMismatchReason.leafPinMismatch)`.
   - **Güvenilen CA altında Hub IP adresinin SAN'da bulunmaması:** `TlsCertificateValidationException(kind: TlsCertificateFailureKind.ipAddressMismatch)`.
   - **Güvenilen CA altında Hostname/SAN uyuşmazlığı:** `TlsCertificateValidationException(kind: TlsCertificateFailureKind.hostnameMismatch)`.
   - **Güvenilen CA altında süresi dolmuş / henüz geçerli olmayan sertifika:** `TlsCertificateValidationException(kind: certificateExpired / certificateNotYetValid)`.
4. **Senkron, Outbox, Sağlık ve UI Yüzeyi (`H-1`, `H-2` Düzeltmeleri Dahil):**
   - **Paralel İstek ve Ham `HandshakeException` Koruması:** `_PinRejectionLog`, endpoint başına tek yuva yerine bounded FIFO kuyruk + `_inFlight` sayaçlıdır; paralel isteklerde red kaydı kaybolmaz. CA öz-sunumu (`KEY_USAGE_BIT_INCORRECT` dahil) ve paralel yarış artıkları `TlsPinMismatchException(untrustedCaChain)` / `TlsCertificateValidationException` olarak fail-closed sınıflanır. `MmsApiClient.checkHealth` ve `get`/`post` ham `HandshakeException` sızdırmaz.
   - `HttpSyncTransport` → `TlsPinMismatchException` için `SyncFailureKind.tlsPinMismatch`; `TlsCertificateValidationException` için `SyncFailureKind.tlsCertError` (HTTP fallback yok).
   - `ClientSyncService`: her iki TLS durumunda da Outbox satırını **silmez/kilitlemez** (`RETRY`, `maxBackoff`, `client_seq` korunur); `tlsPinMismatch` → `'TLS_PIN_MISMATCH: ...'`, `tlsCertError` → `'TLS_CERT_ERROR: ...'`. Outbox boşken `syncProducts` ve `syncSales` içindeki TLS hataları da yutulmaz (`StateError` ile yukarı taşınır).
   - **Sağlık, Koordinatör ve UI:** `BackendConnectionState` (`tlsPinMismatch`, `tlsCertError`), `SyncCoordinatorStatus` (`tlsPinMismatch`, `tlsCertError`), `StatusBadge`, `DiagnosticsView` ve `_CompactStatusPill` bu iki durumu sıradan `'ÇEVRİMDIŞI'`/'`'AĞ HATASI'` rozetlerinden ayrı gösterir; düzeltme sonrası `sync_providers` otomatik reconnect tetikler. `UserFriendlyErrorMapper` uzun Türkçe pin ve SAN/sertifika uyarılarını 220 karakter kesmesine takılmadan çevirir (`formatException` dahil).
5. Discovery yanıtına TLS alanı eklenmedi (ADR-018 §2.2 Seçenek C).

## 3. Sonuçlar

- Uyuşmayan veya doğrulanamayan sunucuya istek gövdesi ve `Authorization` başlığı gönderilmez; `http://` fallback yapılmaz.
- **Testler:** `s1_api_hardening_test` #3b, `tls_pinned_client_factory_test` (5 gerçek soket testi: CA/leaf/rotated/IP-SAN/hostname/expired/notYetValid/yabancı CA+expired/CA öz-sunumu/MITM/bundle-smuggling/6x paralel istek + gerçek soket `MmsApiClient`), `tls_pin_mismatch_sync_test` (5), `api_client_test` (#3b, #10, #11), `tls_error_surface_test` (4), `background_sync_coordinator_test` (#31 dahil).
- **Açık / BLOCKED:** Gerçek Android–Hub sertifika rotasyonu ve sahadaki LAN IP SAN testi (`PHYSICAL_ACCEPTANCE_TEST_PLAN.md` PAT-12).
