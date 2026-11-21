# LIVE_PROJECT_STATUS.md — MARKET MMS Canlı Proje Durumu (20 Kasım 2026)

> [!IMPORTANT]
> **21 Kasım 2026 — Bütünleşik Teknik Düzeltme, ADR Uyum ve Pilot Hazırlık Oturumu:** ADR-015…020 kapsamındaki Owner kararları kod ve dokümantasyonla uyumlu hale getirildi: (1) ADR-015 (`CONFIRMED`): `--config=` modunda ve eşleştirme/revocation uçlarında env fallback kaldırıldı, `/devices/revoke` loopback korumasına alındı, sıkı `tls` anahtar denetimi ve fail-closed `503 ERR_CA_CERT_UNAVAILABLE` eklendi; (2) ADR-016 (`CONFIRMED`): `BackupOperationLock` heartbeat (10 sn) + 60 sn kurtarma + sahip doğrulamalı `.recovering` mutex + 5 sn 0-bayt kurtarma ile sertleştirildi, Hub/istemci bakım ve saklama temizliği ortak kilide bağlandı, kılavuz §7 referansı düzeltildi; (3) ADR-017 (`PARTIALLY_CONFIRMED / IN_REVIEW`): `MmsPinnedTlsClientFactory` içindeki CA-pin/leaf-pin karışıklığı, CA-bundle sızması ve `_PinRejectionLog` paralellik yarışı giderildi; IP SAN, hostname SAN, süre dolumu/henüz geçersiz, aynı-CA yenileme, yabancı CA, CA öz-sunumu, leaf pin uyuşmazlığı ve MITM durumları `TlsCertificateValidationException` (`TLS_CERT_ERROR`) ve `TlsPinMismatchException` (`TLS_PIN_MISMATCH`) olarak ayrıştırılıp UI/sağlık/sync katmanlarına taşındı; (4) ADR-018 (`CONFIRMED` Seçenek C): UDP discovery korundu, `PairingQrPayload` `ca_fingerprint` ve `UNKNOWN` çözümlemesi düzeltildi, **`P-BLOCK-1..3`** Owner karar bloklayıcıları olarak belgelendi; (5) ADR-019 (`DEFERRED_POST_PILOT`): 7 geçici %20 KDV kısıtı, 8 risk ve 9 kalıcı tasarım gereksinimi belgelendi (kod/şema değişmedi); (6) ADR-020 (`DEFERRED_POST_PILOT`): `AndroidKeystoreTokenStore` fail-closed `SecureStorageException` hata eşlemesi eklendi, `minSdk 24 (Android 7.0)` belgelendi. Sıralı doğrulama: **730 test geçti / 0 başarısız / 0 atlanan** (Uygulama 276 · Client Storage 215 · Contracts 7 · Hub 232); statik analizlerde 0 hata/uyarı (Uygulama 0, Contracts 0, Client Storage 16 önceden var olan `sqlite3 dispose` info, Hub 18 önceden var olan `sqlite3 dispose` info). Ayrıntılar: [`PILOT_TECHNICAL_REMEDIATION_REPORT.md`](./PILOT_TECHNICAL_REMEDIATION_REPORT.md). **Fiziksel kabul testleri (PAT-01…15) henüz yapılmadı (`BLOCKED`); proje üretime hazır değildir ve stage/commit yapılmamıştır.**
>
> **21 Kasım 2026 (3. oturum) — Son Tamamlama, Üretim Hazırlığı ve Saha Kabulü:** Önceki raporun test sayıları bu çalışma ağacında yeniden doğrulandı (243 / 191 / 7 / 219 = 660, 0 başarısız). Raporda olmayan **10 bulgu** düzeltildi: (0) **üretim Hub'ı eşleştirme kök CA yolunu hiç almıyordu → QR `ca_fingerprint: UNKNOWN`, TLS pin kurulamazdı (PAIR-CA; `tls.ca_cert` eklendi, üretimde zorunlu)**; (1) Android otomatik Google yedeği açıktı → şifresiz DB + `device_id` cihaz dışına çıkabiliyordu; (2) restore koruyucu kopyası şifresiz kalıyordu → şifreli `.mmsbak`; (3) restore sırasında zamanlanmış yedek yanıltıcı hata veriyordu → dosya kilidi (BK-LOCK); (4) Drive yükleyicisi dosyanın şifreli olduğunu doğrulamıyordu; (5) keşif adayları her zaman `http://` → üretimde (TLS) otomatik keşif bağlanamıyordu; (6) `setup_service_acls.ps1` ve `uninstall_mms_service.ps1` Windows PowerShell 5.1'de **ayrıştırılamıyordu**; (7) kurulum betiği güncellemede ikilileri servis durmadan kopyalıyordu, geri dönüş yoktu; (8) firewall kuralları tüm uzak adreslere açıktı; (9) güncelleme manifesti HTTP indirme adresi/SHA-256'sız kabul ediliyordu. Ek: Hub `/pairing/reject` bozuk gövdede 500 dönüyordu. Yeni testlerle **700 geçti / 0 başarısız**. ADR-018/019/020 eklendi (PROPOSED). Fiziksel kabul **BLOCKED**; stage/commit yapılmadı. Rapor: [`FINAL_COMPLETION_REPORT.md`](./FINAL_COMPLETION_REPORT.md).
>
> **21 Kasım 2026 (2. oturum) — Nihai Teknik Denetim:** Önceki raporun test sayıları bağımsız olarak yeniden doğrulandı (224 / 146 / 210 / 7). Ek olarak **2 kritik hata** (istemci restore'unda bekleyen Outbox/`client_seq` kaybı — ADR-BAK-03 uygulanmamıştı; kasiyer token'ıyla şifresiz merkezi DB snapshot'ı) ve 4 yüksek/orta bulgu düzeltildi. **Zamanlanmış yedek** (Hub + istemci), **USB aktarımı**, **Google Drive altyapısı** (gerçek OAuth hesabı BLOCKED), **TLS pin uyuşmazlığı durumu** ve **Windows Owner eşleştirme onay/red ekranı** eklendi. Mimari değerlendirme: [`ARCHITECTURE_REVIEW.md`](./ARCHITECTURE_REVIEW.md). Kararlar: ADR-016, ADR-017 (PROPOSED). Güncel tek rapor: [`FINAL_COMPLETION_REPORT.md`](./FINAL_COMPLETION_REPORT.md). Fiziksel cihaz/servis/USB/Drive hesabı testleri **BLOCKED**; hiçbir faz Owner tarafından kabul edilmiş sayılmaz; stage/commit yapılmadı.
>
> **21 Kasım 2026 Güncellemesi — Birleştirilmiş Tamamlama Çalışması:** Faz 2 (stok girişi, sürekli kamera taraması, yeni ürün alış fiyatı), Faz 7A (STOCK_RECEIPT delta senkronizasyonu, stok ezilme düzeltmeleri, 401/403/426 bekletme, downlink hata görünürlüğü, kimlik değişikliği koruması, yedekleme isolate'i), Faz 7B (`adm_sec` fallback ve gömülü cihaz token'ı kaldırıldı, güvenli depo fail-closed, tenant/store başlık zorunluluğu) ve Faz 7C (REL-01 tek yapılandırma kaynağı, Android release imza/cleartext sertleştirmesi) uygulandı ve otomatik testlerle doğrulandı. Google Drive, USB ve tüm fiziksel cihaz/servis testleri **BLOCKED / NOT_STARTED**. Ayrıntılar, test sayıları ve Owner kararları: [`docs/FINAL_COMPLETION_REPORT.md`](./FINAL_COMPLETION_REPORT.md). Aşağıdaki 20 Kasım bölümleri tarihsel kayıttır; Faz 1–7 alt aşamalarının çoğu kodda mevcut olup fiziksel kabul testleri beklemektedir. Hiçbir değişiklik stage/commit edilmemiştir.

*Bu belge 20 Kasım 2026 itibarıyla güncel proje ilerlemesini, doğrulama düzeylerini ve **Faz 1–7 Ana Yol Haritası** durumunu izler.*  
*Tarihsel 15 Kasım 2026 MVP durum kaydı için bkz.: [`docs/PROJECT_STATUS.md`](./PROJECT_STATUS.md)*  
*Bağlayıcı 7 Fazlı Yol Haritası için bkz.: [`docs/MASTER_ROADMAP.md`](./MASTER_ROADMAP.md)*

---

## Özet Durum Panosu *(Tarihsel 20 Kasım 2026 Özeti — Güncel Teknik Durum için Yukarıdaki Notlar ve [`PILOT_TECHNICAL_REMEDIATION_REPORT.md`](./PILOT_TECHNICAL_REMEDIATION_REPORT.md) Esastır)*

- **Tarihsel Ana Faz Kaydı (20 Kasım):** **Faz 1 — Otomatik Hub Keşfi ve Bağlantı Yönetimi** (kodda Faz 1–7 ve 7A–7D çalışmaları eklenmiş olsa da Owner tarafından resmî faz kabulü **verilmemiştir**, `PAT-01…15` **BLOCKED**).
- **Son Tamamlanan Teknik Çalışma:** **21 Kasım 2026 — ADR-015…020 Bütünleşik Teknik Düzeltme ve Denetim İyileştirmeleri** *(otomatik testlerle doğrulandı; fiziksel donanım/kabul testi bekleniyor)*.
- **Git Çalışma Alanı:** Çalışma ağacı unstaged durumdadır; **stage/commit/push yapılmamıştır** (`git diff --cached` boş).

---

## 1. Tamamlanan ve Git Geçmişine (`origin/main`) Kabul / Push Edilmiş Çalışmalar

Son ortak `origin/main` commit'i: `8454933df95c6de04813d3eb9499331ec86471dc` (15 Kasım 2026). Aşağıdaki çekirdek MVP temeli kullanıcı kabulüyle depoya kaydedilmiştir:

- **Planlama, Mimari & SPIKE-01 (Tarihsel Faz 0):** İş kuralları (`BUSINESS_RULES_SPEC.md`), mantıksal veri modeli (`DATA_MODEL.md`), offline senkronizasyon ve şifreli yedekleme protokolleri, Dart Shelf + SQLite WAL single-writer backend altyapısı.
- **Windows Client Foundation (Commit `8676586`, Tag `v1.1.0-windows-client-foundation`):** `packages/mms_client_storage`, Drift yerel SQLite ve Windows masaüstü istemci temeli.
- **Yönetişim & UI/UX Programı (Commitler `50343d9`, `6b7898c`, `2db892d`, `32111b8`, `9ad09fc`, `1a3f8e5`):** 5 çekirdek Agent Skill, dokümantasyon uzlaştırması ve 32 HTML/CSS/JS UI/UX prototipi (`OD-01` Half-Up yuvarlama + `12.50 TL`, `OD-02` Parked Carts kapsam dışı, `OD-03` offline bilinmeyen barkod engeli, `OD-04` sanal numpad opsiyonel/kapalı kararları).
- **PaymentMethod Standardizasyonu & Legacy Outbox Recovery (Commit `b069d5b`):** Kanonik `'CASH'`/`'CARD'` ödeme sözleşmesi ve atomik outbox kurtarma akışı.
- **Kasa Satış Ekranı & Sepet Yönetimi (Commit `e9e1df5`):** `PosScreen`, `CartNotifier`, `PaymentDialog`, snapshot fiyat güvencesi (`PriceChangedException`), klavye kısayolları (`F1`, `F2`, `F9`, `F10`, `Esc`).
- **Outbox Status Summary & Diagnostics (Commit `8454933`):** `packages/mms_contracts` ve `OutboxStatusBadge`.

---

## 2. Kullanıcı Tarafından Fiziksel / Manuel Olarak Doğrulanmış İşler

Commit `8454933` sonrasında geliştirilen ve çalışma alanında yer alan işlevlerden aşağıdakiler doğrudan kullanıcı tarafından manuel/fiziksel testlerle doğrulanmıştır:

- [x] **Ürün Senkronizasyonu:** Ürün oluşturma, FIFO Outbox `PRODUCT_UPSERT` ve Hub ürün snapshot indirme akışı manuel kabul testinden geçmiştir.
- [x] **Android Satışının Windows Tarafında Görünmesi:** Android cihazda yapılan satışın Master Hub üzerinden satış uplink → downlink akışıyla Windows istemcisine ulaştığı kullanıcı tarafından doğrulanmıştır.
- [x] **Windows Satış Geçmişinde İade Durumu Görünürlüğü:** Windows Satış Geçmişi ekranında iade edilen satışların `İADE EDİLDİ` rozetiyle gösterilmesi kullanıcı tarafından manuel olarak doğrulanmıştır.

---

## 3. Antigravity Raporuna Göre Tamamlanan — Henüz Bağımsız / Kullanıcı Tarafından Doğrulanmamış İşler

> [!WARNING]
> Bu bölümdeki çalışmalar önceki Antigravity oturumlarının geliştirme, otomatik test ve build raporlarına dayanmaktadır. **Bağımsız doğrulanmış veya kullanıcı tarafından nihai kabulü verilmiş sayılmazlar**; ayrıca çalışma ağacında unstaged durumda beklemektedirler.

- **Arka Plan Senkronizasyonu, Satış Geçmişi, İptal/İade ve Katalog Altyapısı:**
  - `BackgroundSyncCoordinator` (periyodik 30 sn zamanlayıcı, lifecycle, connectivity restore, single-flight, trailing sync).
  - Satış Geçmişi (`SalesHistoryScreen`), Dashboard → Son Satışlar (`SaleDisplayStatus` / `SaleStatusBadge`), tam satış iptali (`SALE_CANCEL`), kısmi ürün iadesi (`SALE_REFUND` + `SELLABLE`/`DAMAGED` ayrımı), Ürün/Kategori Katalog CRUD (`CatalogScreen`), çoklu barkod ve fiyat geçmişi (`LocalPriceHistory`).
- **Satış Downlink ve `SALE_REFUND` FK / Android İade Düzeltmesi:**
  - `GET /api/v1/sales` (cursor tabanlı satış indirme) ve echo-prevention koruması.
  - `SALE_REFUND` Foreign Key çözümlemesi (`device_id` + `target_client_seq`).
  - `reconcileSaleStatuses()`, `upsertSales()` yeni/mevcut satış durum türetmesi, Hub `SALE_REFUND` sonrası `sales.status` güncellemesi ve `GET /api/v1/sales` içinde `effectiveStatus` türetmesi.
  - Android Release APK ([`build/app/outputs/flutter-apk/app-release.apk`](../build/app/outputs/flutter-apk/app-release.apk)): 20 Kasım 2026 tarihli derlemenin başarılı olduğu Antigravity tarafından raporlanmıştır *(fiziksel Android cihaz üzerinde kabul testi henüz beklenmektedir)*.
- **Faz 1.1 — Hub-side UDP Discovery Responder (Yalnızca Windows Tarafı):**
  - [`test_spikes/spike_01_backend/lib/discovery/discovery_responder.dart`](../test_spikes/spike_01_backend/lib/discovery/discovery_responder.dart): Saf Dart `RawDatagramSocket` ile UDP `8946` dinleyicisi, `DISCOVER_MMS_HUB` komutuna unicast JSON yanıt (`service`, `protocol_version`, `hub_id`, `http_port: 8945`, `server_time`, `server_ips` sanal adaptör filtreli).
  - [`test_spikes/spike_01_backend/bin/server.dart`](../test_spikes/spike_01_backend/bin/server.dart): `SpikeServer.start()` / `stop()` yaşam döngüsü entegrasyonu, `--discovery-port` ve `--no-discovery` bayrakları.
  - [`test_spikes/spike_01_backend/test/hub_discovery_responder_test.dart`](../test_spikes/spike_01_backend/test/hub_discovery_responder_test.dart): 7 senaryo ve ilgili backend regresyon testlerinin geçtiği raporlanmıştır.
  - **Windows Gerçek Ortam Doğrulaması (Antigravity Tarafından Yürütüldü):** Güncel `mms_backend.exe` derlendi; kontrollü shutdown/restart yapıldı; TCP `8945` (`0.0.0.0`) ve UDP `8946` (`0.0.0.0`) dinlemesi, `/health` (`200 UP`), `192.168.1.255` ve `255.255.255.255` UDP broadcast yanıtları ve dönen IP'lerle (`192.168.1.158`, `192.168.84.2`, `172.19.64.1`) HTTP `/health` erişimi Windows makinesi üzerinde doğrulanmıştır. *(Not: `build_aot.ps1` çalıştırıldığında arka plandaki eski `MarketMmsSpike01` süreci `sqlite3.dll` dosyasını kilitlediği için betik 59. satırda kopyalama hatası verdi; ancak diskteki `sqlite3.dll` SHA-256 hash'inin özdeş olduğu doğrulandı.)*

---

## 4. Henüz Test Edilmemiş ve Başlanmamış İşler

### A. Fiziksel Cihazda Henüz Test Edilmemiş Açık Doğrulamalar
- [ ] **Faz 1.1 Gerçek Android Ağ Testi:** Fiziksel Android cihazdan yerel Wi-Fi ağı üzerinden UDP `8946` broadcast keşfinin ve Windows Firewall geçişinin çalışıp çalışmadığı **henüz test edilmemiştir** (şu ana kadar yalnızca Windows makinesi üzerinden doğrulandı).
- [ ] **Android İade Durumu Fiziksel Doğrulama:** 20 Kasım 2026 tarihli `app-release.apk` üzerinde iade edilen satışların `İADE EDİLDİ` / `KISMİ İADE` göründüğü fiziksel cihazda **henüz kullanıcı tarafından doğrulanmamıştır**.

### B. Henüz Başlanmamış Faz 1 Alt Aşamaları
- [ ] **Faz 1.2 — Client Storage ve Hub Adresi Saklama (HENÜZ BAŞLAMADI — SIRADAKİ GÖREV):**
  - Son başarılı Hub adresinin yerel kalıcı depolamada saklanması (`packages/mms_client_storage`).
  - Kayıtlı adresin yeniden doğrulanması.
  - Adres değişikliğinin güvenli yönetimi (migration gereksinimi ve geriye dönük uyumluluk analizi dahil).
  - Offline çalışma davranışının ve satış/outbox mekanizmalarının eksiksiz korunması.
- [ ] **Faz 1.3 — Android Discovery ve Bağlantı Yönetimi (HENÜZ BAŞLAMADI):**
  - Android'de hardcoded `http://127.0.0.1:8945` varsayılanının kaldırılması.
  - UDP Discovery isteği ve Hub yanıtının doğrulanması.
  - Birden fazla IP adayı arasından HTTP `/health` geçen erişilebilir IP'nin seçilmesi.
  - Otomatik reconnect ve manuel IP fallback mekanizması ile UI durum göstergesi.
- [ ] **Faz 1.4 — Gerçek Android–Windows Kabul Testi (HENÜZ BAŞLAMADI).**

### C. Sonraki Ana Fazlar (Faz 2 – Faz 7)
- Faz 2 (UI Ayrıştırması), Faz 3 (Platform Klavye/Barkod), Faz 4 (Kamera ile Ürün Tanımlama), Faz 5 (Open Food Facts), Faz 6 (Mobil Kullanılabilirlik/Offline Deneyimi) ve Faz 7 (Üretim/Kurulum/Dağıtım) fazları Faz 1 kabul edilmeden **kesinlikle başlatılmayacaktır**.

---

## 5. Bilinen Teknik Riskler ve Açık Konular

1. **Çoklu Ağ Arayüzleri ve Sanal Adaptör Seçim Riski:** Windows test makinesinde aktif Wi-Fi (`192.168.1.158`) dışında ikinci arayüz (`Ethernet 3: 192.168.84.2`) ve Hyper-V (`172.19.64.1`) bulunmaktadır. Global broadcast (`255.255.255.255`) atıldığında kaynak IP bazen `172.19.64.1` olarak dönebilmektedir. Faz 1.3'te Android istemcisi hem UDP yanıtındaki `server_ips` listesini hem kaynak IP'yi değerlendirip yalnızca **HTTP `/health` doğrulaması başarılı olan adresi** seçmelidir.
2. **Windows Firewall Profili ve İkili Dosya Yolu:** Mevcut Wi-Fi profili `Public` olarak görünmektedir ve kural mevcut `build/mms_backend.exe` yolu üzerindeydi. Ağ `Private`/`Domain` olduğunda veya üretim kurulumunda `%PROGRAMDATA%\MarketMMS\bin\` kullanıldığında TCP `8945` + UDP `8946` kurallarının tanımlanması gerekecektir.
3. **`sqlite3.dll` Dosya Kilidi Riski:** `build_aot.ps1` çalıştırılırken eski `MarketMmsSpike01` süreci `sqlite3.dll`'i kilitleyebilmektedir; derleme öncesi aktif süreçlerin kontrollü durdurulması gerekir.
4. **Router AP Isolation / Android UDP Kısıtları:** Mağaza Wi-Fi modemlerinde istemci izolasyonu veya multicast/broadcast filtrelemesi varsa otomatik keşif başarısız olabilir; bu nedenle manuel IP fallback ve tam offline satış devamlılığı zorunludur.
5. **Çalışma Alanında Birikmiş Unstaged Değişiklikler:** `origin/main` üzerinde `59` değiştirilmiş ve `114+` takip edilmeyen dosya mevcuttur; eşzamanlı çalışma ve regresyon riski yüksektir.
6. **Pilot Öncesi Açık Güvenlik Koşulları (Faz 7 / Spike-01):** `B-2` Mobil Root CA Certificate Pinning, `B-3` Windows DPAPI / Android Keystore güvenli token depolama, `SCM` Windows Service yaşam döngüsü testi, `ACL` standart kullanıcı yetki testi ve route-specific pairing token doğrulaması henüz uygulanmamıştır.
7. **Dokümantasyon Tutarlılık Kararları (Kullanıcı Onayı Bekliyor):**
   - `AGENTS.md` – `GEMINI.md` talimat önceliği ve otonom çalışma sınırlarının uzlaştırılması.
   - `AGENTS.md` (Madde 4.7), `MARKET_POS_AI_STUDIO_BUILD_PLANI.md` (satır 258), `docs/ARCHITECTURE.md` (satır 106) ve `docs/ai/rules/testing.md` (satır 13) içindeki eski `OPEN DECISION` yuvarlama ifadelerinin kesinleşmiş **Half-Up** (`OD-01`) kararıyla güncellenmesi.
   - `go_router` paketinin henüz `pubspec.yaml` dosyasında ekli olmaması (Faz 2'de ele alınacak).

---

## 6. Bir Sonraki İş

1. Kullanıcının güncellenen kalıcı dokümantasyonu (`docs/MASTER_ROADMAP.md`, `docs/LIVE_PROJECT_STATUS.md`, `GEMINI.md` Bölüm 6.8 referansları) ve sunulan **iki karar önerisini** (`AGENTS.md`–`GEMINI.md` önceliği ve `Half-Up` doküman tutarlılığı) inceleyip onaylaması.
2. Kullanıcı onayı sonrasında **Faz 1.2 — Client Storage ve Hub Adresi Saklama** aşamasının planlanıp başlatılması.
