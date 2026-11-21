# ARCHITECTURE_REVIEW.md — MARKET MMS Mimari Değerlendirmesi

*Tarih: 21 Kasım 2026 (3. oturumda güncellendi: §5 AV-8…AV-18, §6 TD-1/TD-7, §10) · Hazırlayan: Claude Code (Opus 5.5) · Kapsam: `lib/`, `packages/mms_client_storage`, `packages/mms_contracts`, `test_spikes/spike_01_backend` (Windows Master Hub)*

Bu belge kod tabanının **gerçek** durumunu değerlendirir; kanıtlar dosya yolları ve ölçümlerle verilir. Değerlendirme sırasında uygulanan düzeltmeler §9'dadır.

---

## 1. Genel Görünüm

```
┌──────────────────────── Android / Windows istemci (Flutter, lib/) ────────────────────────┐
│ presentation (ekranlar, widget'lar) → application (Riverpod StateNotifier'lar, servisler) │
│        → domain (saf modeller: CartState, Money, StockReceiptInput, …)                     │
│        → data / infrastructure (LocalPosRepository, UdpHubDiscoveryClient, DPAPI/Keystore)│
└───────────────────────────────┬───────────────────────────────────────────────────────────┘
                                │ (paket bağımlılığı)
        packages/mms_client_storage — Drift/SQLite yerel DB, Outbox/FIFO, ClientSyncService,
        HttpSyncTransport, S5A-4 yedekleme motoru, zamanlanmış yedek, USB aktarım, Drive yükleyici
        packages/mms_contracts — saf Dart ortak sözleşmeler (OutboxSummary)
                                │ HTTPS (LAN) — TLS pin, Bearer cihaz token'ı, X-MMS-Tenant/Store
┌───────────────────────────────┴──────── Windows Master Hub (Dart Shelf, WinSW servis) ──────┐
│ bin/server.dart (rotalar + iş kuralları) · lib/db (Drift, WriteQueue tek yazıcı)            │
│ lib/security (token, pepper/DPAPI, pairing, TLS) · lib/service (lifecycle, admission gate)  │
│ lib/discovery (UDP) · lib/sync (kanonik hash, sequence denetimi) · lib/config (REL-01)      │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
```

- Android cihazlar birbirleriyle değil, yalnızca Hub ile senkronize olur (doğrulandı: istemcide eşler arası kod yok).
- Hub merkezi otoritedir; istemciler yerel SQLite üzerinde offline çalışır ve Outbox'ı FIFO `client_seq` sırasıyla gönderir.

## 2. Katman Sorumlulukları — Değerlendirme

| Katman | Beklenen | Gerçek durum | Sonuç |
|---|---|---|---|
| Presentation | UI, kullanıcı etkileşimi; SQL/HTTP yok | SQL veya ham HTTP çağrısı **yok** (grep: `customSelect`, `customStatement`, `db.select` presentation altında 0). 2 yerde UI, servis sağlayıcısı üzerinden repository'ye doğrudan erişiyor: `stock/presentation/screens/stock_screen.dart` (`getPriceHistory`), `diagnostics/presentation/widgets/diagnostics_export_card.dart` | Büyük ölçüde uyumlu; 2 küçük sızıntı (TD-5) |
| Application | İş akışı orkestrasyonu | `CartNotifier`, `StockReceiptNotifier`, `BackgroundSyncCoordinator`, `ClientBackupService`, `BackupScheduleController` | Uyumlu |
| Domain | Saf Dart | 8 domain dosyasından 1'i `flutter/material` (düzeltildi, §9), 2'si `flutter/foundation` (`@immutable`, `listEquals`) ve 4'ü `mms_client_storage` modelleri (`kCountableStockUnits`, `SyncBatchResult`) kullanıyor | Kısmen uyumlu (TD-4) |
| Data / Infrastructure | Repository uygulamaları, Drift, HTTP | `mms_client_storage` paketi + `features/*/data`, `features/sync/infrastructure` | Uyumlu; ancak paket bir "storage + sync + backup" monolitine dönüştü (TD-2) |

**Repository sözleşmeleri:** `pos/domain/pos_repository.dart` (port) ↔ `pos/data/local_pos_repository.dart` (adapter) doğru konumda. Diğer modüller (katalog, stok, satış) doğrudan `ClientStorageRepository` somut sınıfını kullanıyor; port tanımı yok. Pilot için kabul edilebilir (YAGNI); test edilebilirlik gerçek FFI SQLite ile sağlanıyor.

**Dependency Injection:** Riverpod `Provider`'ları kompozisyon kökü olarak tutarlı kullanılıyor. `localDatabaseServiceProvider` ve `secureTokenStoreProvider` uygulama başlangıcında override ediliyor (`lib/main.dart`).

## 3. Modüller Arası Bağımlılıklar

`lib/features/*` altında göreli import sayımı (seçilmiş kenarlar):

| Kaynak → Hedef | Adet | Değerlendirme |
|---|---|---|
| `diagnostics → sync` | 10 | Tanılama ekranı durum gösterdiği için beklenen |
| `pos → sync` | 7 | Satış sonrası senkron tetikleme; kabul edilebilir |
| `pos → diagnostics` | 6 | `localDatabaseServiceProvider` / `apiClientProvider` **diagnostics** altında tanımlı (TD-3) |
| `stock → catalog` / `stock → pos` | 5 / 4 | Ürün düzenleme diyaloğu ve `Money` biçimlendirme yeniden kullanılıyor |
| `catalog → pos` | 5 | `Money` ve `PosProduct` paylaşımı |
| `backup → sync` | 1 | Restore sırasında senkron duraklatma (bu oturumda eklendi) |

**Döngüsel paket bağımlılığı:** `mms_client_storage` **dev_dependency** olarak `spike_01_backend`'e, `spike_01_backend` ise **dependency** olarak `mms_client_storage`'a bağlı. Üretim kodunda döngü yok (yalnızca test entegrasyonu), ancak Hub artık S5A-4 motorunu ve zamanlanmış yedek mantığını bu paketten aldığı için paket adı ("client storage") sorumluluğu yansıtmıyor (TD-2).

## 4. Doğru Uygulanan Prensipler

- **Para:** Tüm tutarlar kuruş `int`; Half-Up `((unitPrice * quantity) + 500) ~/ 1000` (`client_storage_repository.dart`, `cart_state.dart`, Hub `server.dart`). `double` para aritmetiği bulunamadı.
- **Atomiklik:** Satış, iade, iptal, ürün ve stok girişi; stok + hareket + Outbox kaydı tek `db.transaction` içinde. Stok artışı SQL seviyesinde `stock = stock + ?` (kayıp güncelleme yok).
- **FIFO / idempotency:** `client_seq` monoton, `UNIQUE(device_id, client_seq)`; Hub `processed_operations` + kanonik hash; sequence gap (`ERR_CLIENT_SEQ_GAP`), idempotency conflict (`409`) ve Hub rewind ayrımı korunuyor.
- **Tek yazıcı:** Hub tüm yazmaları `WriteQueue` ile seri yürütüyor; zamanlanmış yedeğin `VACUUM INTO`'su da aynı kuyruktan geçiyor.
- **Güvenli varsayılanlar:** REL-01 üretimde TLS ve tenant/store başlıklarını zorunlu tutuyor; admin uçları loopback + secret; güvenli depo fail-closed.
- **Test altyapısı:** Gerçek FFI SQLite (WAL), gerçek TLS soketleri (OpenSSL ile üretilen sertifikalar), gerçek Hub HTTP sunucusu.

## 5. Tespit Edilen Mimari İhlaller ve Hatalar

| Kod | Bulgu | Önem | Durum |
|---|---|---|---|
| AV-1 | `shell/domain/app_destination.dart` `flutter/material` (ikonlar) içe aktarıyordu | Orta (katman ihlali) | **Düzeltildi** (§9) |
| AV-2 | İstemci restore'u ADR-BAK-03'ü uygulamıyordu: yedekten sonra oluşan Hub'a ulaşmamış Outbox işlemleri siliniyor, `client_seq` geriye alınıyordu → satış kaybı + `409` kuyruk kilidi | **Kritik** (veri bütünlüğü) | **Düzeltildi** (`ClientRestoreReconciler`) |
| AV-3 | Restore hazırlık aşamasında hata (disk dolu) olursa canlı DB/Hub duraklatılmış kalıyordu | Yüksek | **Düzeltildi** |
| AV-4 | İstemci restore'u sırasında arka plan senkronizasyonu durdurulmuyordu (yarım ACK yazımı riski) | Yüksek | **Düzeltildi** (`pauseForMaintenance`) |
| AV-5 | Restore'da şube (store) kontrolü yalnızca Hub rotasında elle yapılıyordu; istemcide yoktu | Orta | **Düzeltildi** (motor `expectedStoreId`) |
| AV-6 | TLS pin uyuşmazlığı sıradan ağ hatası gibi raporlanıyordu | Yüksek (güvenlik görünürlüğü) | **Düzeltildi** |
| AV-7 | `/api/v1/backup/snapshot` kasiyer token'ıyla şifresiz merkezi DB kopyası üretiyordu | **Kritik** (güvenlik) | **Düzeltildi** (loopback + admin) |
| AV-8 | Android `allowBackup` varsayılanı (açık): şifresiz yerel DB, kurulum ve `device_id` Google bulut yedeğine / yeni cihaza kopyalanabiliyordu → veri sızıntısı + iki cihazda aynı kimlik (sıra çakışması) | **Yüksek** (güvenlik + veri bütünlüğü) | **Düzeltildi** (3. oturum) |
| AV-9 | Restore koruyucu kopyası (`safety`) şifresiz ve kalıcı | Yüksek (Hub kopyası token hash/salt içerir) | **Düzeltildi** (şifreli `.mmsbak`; eski kopyalara dokunulmadı) |
| AV-10 | Restore sırasında zamanlanmış yedek kapalı DB'ye çarpıp "başarısız" kaydediliyordu; süreçler arası yedek kilidi yoktu | Orta | **Düzeltildi** (`BackupOperationLock`) |
| AV-11 | Drive yükleyicisi dosyanın şifreli paket olduğunu doğrulamıyordu (yorumda iddia, kodda yok) | Orta (savunma derinliği) | **Düzeltildi** |
| AV-12 | Keşif adayları sabit `http://`: üretim Hub'ı TLS-only, release APK cleartext kapalı → otomatik keşif üretimde bağlanamıyordu | **Yüksek** (işlev) | **Düzeltildi** (istemci tarafı, protokol değişmedi; ADR-018) |
| AV-13 | `setup_service_acls.ps1` / `uninstall_mms_service.ps1` Windows PowerShell 5.1'de ayrıştırılamıyordu (BOM'suz UTF-8 `—` → `”`) → kurulum varsayılan kabukta çalışmazdı | **Kritik** (kurulum) | **Düzeltildi** (UTF-8 BOM + regresyon testi) |
| AV-14 | Kurulum betiği güncellemede ikilileri servis durmadan kopyalıyordu (exe kilitli → güncelleme başarısız); geri dönüş yoktu; WinSW çıkış kodları kontrol edilmiyordu | Yüksek | **Düzeltildi** (v2.1; gerçek SCM'de BLOCKED) |
| AV-15 | Firewall kuralları tüm uzak adreslere açıktı | Orta | **Düzeltildi** (`LocalSubnet` varsayılanı) |
| AV-16 | Güncelleme manifesti HTTP indirme adresi ve SHA-256'sız kabul ediliyordu; bozuk manifest "çevrimdışı" diye raporlanıyordu | Orta | **Düzeltildi** |
| AV-17 | Hub `/pairing/reject` bozuk gövdede 500 dönüyordu | Düşük | **Düzeltildi** (400) |
| AV-18 | **PAIR-CA:** Üretim `main()` eşleştirme kök CA yolunu `SpikeServer`'a hiç geçirmiyordu; `hub_config.json`'da anahtar yoktu → QR `ca_fingerprint: "UNKNOWN"`, `/pairing/ca-cert` 404 → QR eşleştirmede TLS pin kurulamazdı | **Kritik** (üretim eşleştirmesi) | **Düzeltildi** (`tls.ca_cert`, üretimde zorunlu; ADR-015 Ek A.5) |

## 6. Teknik Borçlar

| Kod | Borç | Etki | Öneri |
|---|---|---|---|
| TD-1 | `bin/server.dart` 4.051 satır (21.11.2026 ölçümü): rota tanımları, doğrulama, iş kuralları ve `main` tek dosyada (SRP ihlali) | Bakım zorluğu, birleştirme çatışması riski | Rota gruplarını (`pairing`, `sales`, `stock`, `admin/backup`) ayrı `Router` modüllerine bölmek. Davranış değiştirmeyen saf yeniden düzenleme olduğundan ayrı bir iterasyonda, tam Hub regresyonu ile yapılmalı |
| TD-2 | `ClientStorageRepository` 2.414 satır; paket depolama + senkron + yedekleme + Drive içeriyor | Sınıf düzeyinde SRP ihlali | Satış/iade, katalog, stok ve Hub bağlantı ayarları için ayrı repository sınıfları; paketi `mms_storage` + `mms_backup` olarak ayırma (Owner kararı: paket yapısı) |
| TD-3 | `localDatabaseServiceProvider` ve `apiClientProvider` `diagnostics` modülünde tanımlı | Gereksiz modül bağımlılığı (`pos → diagnostics`) | `core/providers` altına taşınması |
| TD-4 | Domain'de `flutter/foundation` (`@immutable`, `listEquals`) ve `mms_client_storage` model kullanımı | Domain Flutter SDK'sına bağlı | `meta` + kendi eşitlik yardımcıları; düşük öncelik |
| TD-5 | 2 UI noktasında repository'ye doğrudan erişim | Katman sızıntısı (küçük) | İlgili notifier'a metot eklenmesi |
| TD-6 | `_TrackedClientStorageRepository` her repository metodunu elle sarmalıyor | Yeni metot eklenince unutulma riski (şu an tüm metotlar kapsanıyor — doğrulandı) | Kod üretimi veya `noSuchMethod` yerine merkezi `runOperation` kullanımı |
| TD-7 | ~~48~~ → **26** adet `catch (_) {}` (3. oturumda yedek motorundaki 22'sinin tamamı loglayan `_deleteQuietly/_deleteQuietlySync`'e çevrildi; kalan: uygulama 12, Hub 12, depolama 2) | Hata gizleme riski; AGENTS.md §9 ile çelişir | Kalanların loglamaya çevrilmesi (çoğu test/teardown dışı temizlik ve UDP gönderim döngüsü) |
| TD-8 | Hub'da 18, depolama paketinde 16 `deprecated_member_use` (sqlite3 `dispose`) | Gelecek sürümde derleme kırılması | Bu oturumda yedek motorundaki 6 kullanım `close()` yapıldı |
| TD-9 | Kategori ve KDV Hub senkronizasyonu yok (SYNC-CAT) | Çok cihazda kategori ayrışması | Owner erteledi |

## 7. Performans ve Bakım Riskleri

- **Hub token doğrulama O(n):** `auth_middleware.dart` her istekte tüm cihazların hash'ini dener. Pilot ölçeğinde (≤ 10 cihaz) sorun değil; cihaz sayısı artarsa token öneki indeksi gerekir.
- **PBKDF2-600k:** Artık UI isolate dışında (`Isolate.run`). Zamanlanmış yedekler Hub'da servis isolate'ini bloke etmiyor.
- **Snapshot koruması:** `productIdsWithUnsyncedStockChanges` her ürün senkronunda bekleyen tüm Outbox payload'larını JSON olarak çözer; kuyruk çok büyürse maliyet artar (izlenmeli).
- **Restore güvenlik yedekleri** (`backups/safety`) şifresiz ve canlı DB ile aynı diskte birikir; saklama politikası bunları kapsamıyor.

## 8. Modül Değerlendirmesi (talimat §4.3)

| Modül | Kod | Değerlendirme |
|---|---|---|
| Sales | `features/pos`, `features/sales`, Hub `/api/v1/sales` | Olgun; satış/iptal/iade atomik, FK çözümlemesi testli |
| Products / Categories | `features/catalog` | Ürün Hub'a senkron; kategori yalnızca yerel (TD-9) |
| Inventory | `features/stock` | Stok girişi delta senkronlu (ADR-013), hareket defteri |
| Users | — | Kullanıcı/rol yönetimi **yok**; cihaz rolü (`CASHIER`) Hub'da mevcut. Kapsam dışı/Owner kararı |
| Reports | `features/dashboard`, `features/sales` | KPI ve satış geçmişi; dışa aktarım yok |
| Sync | `features/sync`, `ClientSyncService` | FIFO, retry, pin uyuşmazlığı, bakım duraklatma |
| Backup | `features/backup`, `mms_client_storage/lib/src/backup` | Şifreli yerel, zamanlanmış, USB, Drive (OAuth BLOCKED) |
| Setup | `features/setup` | Kurulum sihirbazı, kimlik değişikliği koruması |
| Diagnostics | `features/diagnostics` | Kapsamlı; ancak sağlayıcı kökü olarak da kullanılıyor (TD-3) |

Yalnızca görünüm için yeni klasör/Gradle modülü **oluşturulmadı** (talimat §4.3).

## 9. Bu Oturumda Yapılan Mimari Düzeltmeler

1. **AV-1:** `kAppNavItems` (ikon/etiket) `shell/presentation/app_nav_items.dart`'a taşındı; `AppDestination` + `AppDestinationX` (saf Dart) domain'de kaldı.
2. **AV-2:** `packages/mms_client_storage/lib/src/backup/client_restore_reconciler.dart` (SRP: yalnızca restore öncesi Outbox/sayaç birleştirme). Motor, istemci DB türlerinde varsayılan olarak çağırır.
3. **AV-3:** Restore iki aşamaya ayrıldı: *hazırlık* (güvenlik yedeği, birleştirme, journal — canlı dosyaya dokunulmaz; hata → canlı DB yeniden açılır) ve *swap* (mevcut rollback mantığı).
4. **AV-4:** `BackgroundSyncCoordinator.pauseForMaintenance/resumeAfterMaintenance`; orkestrasyon widget'ta değil `ClientBackupService`'te (uygulama katmanı).
5. **AV-5/DRY:** Hub restore rotasındaki elle yazılmış store ön kontrolü kaldırıldı; motorun `expectedStoreId` parametresi kullanılıyor.
6. **AV-6:** `TlsPinMismatchException` (paket), `SyncFailureKind`, `SyncCoordinatorStatus.tlsPinMismatch`, `CentralHealthResponse.tlsPinMismatch`.
7. **AV-7:** Snapshot ucu admin'e kapatıldı.
8. **DRY:** Hub manuel ve zamanlanmış yedek tek yol `createEncryptedHubBackup()`; Hub ve istemci aynı `ScheduledBackupRunner`/`BackupSchedulePolicy`'yi kullanıyor.

TD-1/TD-2 gibi büyük yeniden yapılandırmalar bilinçli olarak **yapılmadı**: davranış değiştirmeden çok sayıda dosyayı etkiler ve faz kabulü öncesi regresyon riski taşır.

## 10. 3. Oturum (21.11.2026) — Ek Düzeltmeler ve Değerlendirme

- **Katman sınırları korundu:** Yeni kilit (`BackupOperationLock`) ve güvenlik kopyası şifreleme altyapı/paket katmanında; uygulama katmanı (`ClientBackupService`) yalnızca orkestrasyon yapar. UI'ya iş kuralı eklenmedi.
- **Yeni soyutlama yok:** Yeni arayüz/sınıf hiyerarşisi eklenmedi. Güvenlik kopyası şifreleme mevcut `BackupCryptoService.encryptPackage` + `LocalStorageProvider.saveBackup` yolunu yeniden kullanır (DRY); Drive koruması mevcut `extractManifestWithoutDecryption`'ı kullanır.
- **Keşif şeması (AV-12):** Sağlayıcı pin'i `watch` etmez (aksi halde eşleştirme sonrası `hubConnectionProvider` yeniden kurulup durumunu kaybederdi); şema her keşif turunda `schemeResolver` ile okunur.
- **Bağımlılık eklenmedi:** WorkManager, Google Sign-In, QR ve dosya seçici paketleri Owner kararına bırakıldı (ADR-019/020, `OWNER_ACTION_CHECKLIST.md`).
- **Bilinçli olarak yapılmayanlar:** TD-1/TD-2 (büyük dosyaların bölünmesi), TD-3 (sağlayıcı kökünün taşınması), TD-5 — davranış değiştirmeyen geniş yeniden düzenlemeler faz kabulü öncesi regresyon riski taşır.
- **Kalan mimari gözlem:** Hub'da kategori ve KDV sütunu yok; istemci `PRODUCT_UPSERT`'te gönderiyor, Hub düşürüyor → yeni cihazlar KDV %20 varsayılanıyla başlar (ADR-019, Owner kararı).
- **Güncelleme hattı:** Uygulama içi güncelleme yalnızca sürüm bildirimi yapar (indirme/kurulum yok); Hub'da `/api/v1/updates/manifest.json` rotası **yok** (kart, URL boşsa bu adresi dener ve "yanıt alınamadı" gösterir). Paket imzalama (kod imzalama sertifikası) yok — Owner kararı.
