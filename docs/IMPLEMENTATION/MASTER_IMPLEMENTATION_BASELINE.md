# MARKET MMS — Master Implementation Baseline (`Faz 0`)

- **Tarih:** 22 Kasım 2026
- **Kapsam:** Çalışma Hattı A (Core Market System Pilot Kapanışı) + Çalışma Hattı B (Hub-Centric Google Drive Backup & Restore)
- **Başlangıç Doğrulama Yöntemi:** Salt-okunur repository ve Git durum denetimi (uygulama kodu, veritabanı, servis, sır veya protected dosyaya dokunulmadan).

---

## 1. Git ve Çalışma Ağacı Temel Hattı (`Baseline`)

- **Aktif Dal (`git branch --show-current`):** `main`
- **Son Ortak Commit (`git rev-parse --short HEAD`):** `817f881`
- **Önceki Denetim Turundan Gelen Dokümantasyon Değişiklikleri (henüz stage/commit edilmemiştir):**
  - `M docs/decisions/README.md` (`ADR-023` kaydı)
  - `?? docs/architecture/GOOGLE_DRIVE_BACKUP_ARCHITECTURE_V1_1.md`
  - `?? docs/architecture/AUTOMATED_BACKUP_SCHEDULING_SPEC_V1_1.md`
  - `?? docs/testing/BACKUP_RESTORE_ACCEPTANCE_TESTS_V1_1.md`
  - `?? docs/decisions/023-hub-centric-google-drive-backup-restore.md`

### Korunan 4 Untracked Dosya (Dokunulmaz)
| Dosya | Durum | Koruma Kuralı |
|---|---|---|
| [`.vscode/settings.json`](../../.vscode/settings.json) | Mevcut (`True`) | Değiştirilmeyecek, taşınmayacak, silinmeyecek |
| [`run_windows_client.bat`](../../run_windows_client.bat) | Mevcut (`True`) | Değiştirilmeyecek, taşınmayacak, silinmeyecek |
| [`start_master_hub.bat`](../../start_master_hub.bat) | Mevcut (`True`) | Değiştirilmeyecek, taşınmayacak, silinmeyecek |
| [`stop_master_hub.bat`](../../stop_master_hub.bat) | Mevcut (`True`) | Değiştirilmeyecek, taşınmayacak, silinmeyecek |

---

## 2. Paket, Şema ve Mimari Envanter

| Paket / Modül | Konum | `schemaVersion` / Başlıca Rol | Faz 0 Notu |
|---|---|---|---|
| `mms_contracts` | [`packages/mms_contracts`](../../packages/mms_contracts/pubspec.yaml) | Ortak sync / outbox sözleşmeleri | Korumalı, sade kalır |
| `mms_client_storage` | [`packages/mms_client_storage`](../../packages/mms_client_storage/pubspec.yaml) | `ClientDatabase.schemaVersion = 4`, `OutboxOperations`, `LocalProductBarcodes`, `MMSBAK01`, `MMSENV01` | Faz 3'te yalnızca `cryptography` paketi (güvenilir AEAD/PBKDF2) değerlendirilir |
| `spike_01_backend` | [`test_spikes/spike_01_backend`](../../test_spikes/spike_01_backend/pubspec.yaml) | `SpikeDatabase.schemaVersion = 3`, Dart Shelf HTTPS Hub, `WriteQueue`, `LifecycleManager`, `WindowsDpapi` | Faz 2 (`A-1.2`)'de `ProductBarcodes` ile `schemaVersion = 4`'e yükseltilecek |
| `market_pos` (kök) | [`pubspec.yaml`](../../pubspec.yaml) | Windows + Android Flutter uygulaması (Riverpod) | Faz 7'de Hub/Legacy backup UI ayrıştırması yapılacak |

### Mevcut Kriptografi Bağımlılıkları
- Pub cache'te `crypto` (`3.0.7` / `3.0.8`) mevcuttur; `cryptography` veya `pointycastle` henüz `pubspec.yaml` dosyalarında yer almamaktadır. Faz 3 (`B-1.1` `MMSBAK02`) içinde trusted AEAD + key wrapping için `cryptography` kullanımı doğrulanacaktır.

### Mevcut Sync & Hub Uç Noktaları
- `GET /health`
- `GET /api/v1/sync/device-state` ([`server.dart`](../../test_spikes/spike_01_backend/bin/server.dart#L3419-L3455)) — `DeviceSequenceInspector` ile `high_water_mark_seq`, `max_seen_client_seq`, `expected_next_client_seq`, `has_sequence_gaps`, `latest_server_sale_seq` döner.
- `POST /api/v1/sync/receipts` ([`server.dart`](../../test_spikes/spike_01_backend/bin/server.dart#L3504-L3686)) — `client_seqs` bazında (`max 500`) `FOUND` / `NOT_FOUND` / `UNVERIFIABLE_LEGACY` makbuz durumunu döner.
- `GET /api/v1/sync/live-drive-config` ([`server.dart`](../../test_spikes/spike_01_backend/bin/server.dart#L3458-L3501)) — `ADR-021`/`K-05` Hub provizyonu (`OV-02` gereği backup OAuth'tan kesin olarak ayrı kalır).

---

## 3. Faz 0'da Tespit Edilen Kanonik Doküman Konumları ve Kaymalar (Faz 1'de Giderilecek)

1. **Dosya Yolu Notu:** `PHYSICAL_ACCEPTANCE_TEST_PLAN.md` ve `OWNER_ACTION_CHECKLIST.md` dosyaları `docs/` altında değil kök dizindedir ([`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`](../../PHYSICAL_ACCEPTANCE_TEST_PLAN.md), [`OWNER_ACTION_CHECKLIST.md`](../../OWNER_ACTION_CHECKLIST.md)).
2. **`LIVE_PROJECT_STATUS.md` Şema Sürümü Kayması:** [`docs/LIVE_PROJECT_STATUS.md`](../LIVE_PROJECT_STATUS.md#L4) satır 4'te `ClientDatabase.schemaVersion = 3` yazmaktadır; gerçek kodda [`client_database.dart`](../../packages/mms_client_storage/lib/src/database/client_database.dart#L256) `schemaVersion => 4` olarak tanımlıdır (Faz 8'de son güncel şema ve gerçek test sayılarıyla uzlaştırılacaktır).
3. **`BUSINESS_RULES_SPEC.md` Bölüm 13 Kayması:** [`docs/requirements/BUSINESS_RULES_SPEC.md`](../requirements/BUSINESS_RULES_SPEC.md#L530-L531) üst başlıkta **v1.7 (22 Kasım 2026)** iken Bölüm 13'te hâlâ *v1.6 / Faz 1.2 henüz başlamadı* tarihsel notu kalmıştır (Faz 1'de temizlenecektir).
4. **Önceki v1.1 Taslakları vs Owner Kararları (`OV-01..OV-05`, `GAP-A01`, `GAP-A03`):**
   - Önceki `v1.1` taslaklarında `OV-01` için `LocalService CurrentUser` birincil tercih, `POST /api/v1/sync/verify-keys` öneri ve `OV-06` olarak parola uzunluğu açık bırakılmıştı.
   - Owner kesin kararları doğrultusunda Faz 1'de tüm kanonik dokümanlar **LocalMachine DPAPI + `pOptionalEntropy` + sıkı NTFS ACL (`OV-01`)**, **`ADR-021`/`ADR-022` tam ayrımı (`OV-02`)**, **mevcut `/api/v1/sync/device-state` & `/api/v1/sync/receipts` + `restore_epoch` tabanlı tam işlem uzlaştırması (`OV-03`)**, **tek seferlik Windows Hub `OWNER` bootstrap + `CASHIER` varsayılanı (`OV-04`)**, **minimum 12 karakter Portable Recovery Password + bağımsız 7 günlük yerel önbellek (`OV-05`)**, **`GAP-A01` ikincil barkod sync** ve **`GAP-A03` E2E güncellemesi** ile kilitlenecektir.
5. **Üretim Ortamı Koruma Teyidi:** `MarketMmsSpike01` servisine, gerçek veritabanlarına, sırlara ve Google Drive'a dokunulmamıştır.

---

## 4. 23 Kasım 2026 Devralma Temel Hattı ve Kayma Kapanışı

- **HEAD / dal:** `817f881` / `main` (değişmedi; bu turda commit yapılmadı). Devralınan çalışma ağacı: 31 değiştirilmiş izlenen dosya + önceki aracın yeni dosyaları; bu turdaki ek değişiklikler [`FINAL_PILOT_READINESS_REPORT.md`](../FINAL_PILOT_READINESS_REPORT.md) §5'te.
- **Güncel şema (kodla doğrulandı):** `ClientDatabase.schemaVersion = 4` ([`client_database.dart:256`](../../packages/mms_client_storage/lib/src/database/client_database.dart#L256)), `SpikeDatabase.schemaVersion = 4` ([`database.dart:239`](../../test_spikes/spike_01_backend/lib/db/database.dart#L239), `A-1.2` ile v3→v4).
- **Kriptografi bağımlılığı:** `mms_client_storage` → `cryptography: ^2.7.0` (`MMSBAK02`).
- **Kayma durumu:**
  - §3.2 `LIVE_PROJECT_STATUS.md` şema kayması → **kapatıldı** (22 Kasım notuna düzeltme eklendi; 23 Kasım girişi güncel değerleri yazar).
  - §3.3 `BUSINESS_RULES_SPEC.md` Bölüm 13 → önceki turda düzeltilmiş (çalışma ağacı farkı mevcut).
  - §3.4 Owner kararları → `MASTER_IMPLEMENTATION_DECISIONS.md` §1 + §3 (`IMP-01…07`) ile kilitli; ADR-016'daki "Hub zamanlanmış yedek parolası: pepper" ifadesine ADR-023 `B1.7` üstünlük notu eklendi.
- **Korunan 4 dosya:** değiştirilmedi (değişiklik tarihleri 16–21 Kasım 2026).
