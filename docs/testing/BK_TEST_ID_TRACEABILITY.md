# BK Test Kimliği İzlenebilirlik Tablosu (Şartname ↔ Otomatik Test ↔ Fiziksel Test)

- **Tarih:** 23 Kasım 2026 (2. tur)
- **Okuyucu:** Owner ve teknik inceleyici.
- **Kaynak şartname:** [`BACKUP_RESTORE_ACCEPTANCE_TESTS_V1_1.md`](BACKUP_RESTORE_ACCEPTANCE_TESTS_V1_1.md) §4.1 (`BK-001…BK-032`) ve §4.2 (`BK-PAT-01…18`).
- **Gerçek test sonuçları:** [`FINAL_PILOT_READINESS_REPORT.md`](../FINAL_PILOT_READINESS_REPORT.md) §E (23 Kasım 2026 (2. tur) sıralı tam koşum).

## 1. Neden bu tablo gerekli?

Otomatik testlerin adlarındaki `BK-xxx` etiketleri, test dosyaları yazılırken **kendi sıralarıyla** verilmiş ve şartnamedeki numaralarla **örtüşmüyor**. Örnek: test etiketi `BK-004` "VACUUM INTO WriteQueue'yu bloklamaz" davranışını sınar; şartnamede `BK-004` ise "MMSBAK01 geriye dönük uyumluluk"tur.

Kural: **Hiçbir kimlik yeniden numaralandırılmadı.** Şartname kimlikleri ve mevcut test etiketleri olduğu gibi kalır; eşleşme yalnızca bu tabloda tutulur. Raporlarda "BK-xxx geçti" ifadesi kullanılırken **şartname kimliği** esas alınmalı ve test etiketi ayrıca belirtilmelidir.

Durum etiketleri:
- **OTOMATİK – PASS (23.11 2. tur)**: İlgili test(ler) 23 Kasım 2026 (2. tur) tam koşumunda geçti.
- **KISMİ**: Davranışın bir bölümü otomatik testle doğrulanıyor; eksik kısım belirtilmiştir.
- **OTOMATİK TEST YOK**: Kod mevcut olabilir ancak bu davranışı doğrudan sınayan otomatik test bulunamadı. PASS sayılmaz.
- **FİZİKSEL – BLOCKED**: Gerçek servis/cihaz/Drive gerektirir; çalıştırılmadı. **PASS değildir.**

Kısaltmalar: `b1`=`test_spikes/spike_01_backend/test/hub_backup_b1_test.dart`, `b2`=`…/hub_backup_b2_oauth_test.dart`, `b3`=`…/hub_backup_b3_orchestrator_test.dart`, `b4`=`…/hub_backup_b4_rbac_restore_test.dart`, `s1s6`=`…/hub_backup_s1_s6_hardening_test.dart`, `lp`=`…/legacy_backup_portable_key_test.dart`, `v2`=`packages/mms_client_storage/test/mmsbak_v2_and_retention_test.dart`, `upl`=`…/resumable_drive_uploader_test.dart`, `prr`=`…/post_restore_reconciliation_test.dart`, `prov`=`test/features/backup/hub_backup_b3_provider_test.dart`, `ui`=`test/features/backup/hub_central_backup_ui_test.dart`.

## 2. Şartname `BK-001…BK-032` eşleşmesi

| Şartname ID | Kapsadığı davranış (şartname) | Otomatik test (dosya → test etiketi) | Durum | Fiziksel karşılık |
|---|---|---|---|---|
| BK-001 | `MMSBAK02` şifreleme ve bütünlük | `v2` → `BK-001`, `BK-003` | OTOMATİK – PASS (23.11 2. tur) | `BK-PAT-02` BLOCKED |
| BK-002 | Yanlış parola ve canlı DB koruması | `v2` → `BK-002` (yanlış parola/bit bozulması fail-closed); `b4` → `BK-025` | KISMİ — Hub merkezi restore'da yanlış parolanın canlı DB'ye dokunmadığını doğrudan sınayan test yok | `BK-PAT-12` BLOCKED |
| BK-003 | Portable Recovery Password (makine bağımsız) | `b4` → `BK-025` (yeni PC restore); `lp` → `LP-01…07`; `s1s6` → S2 "paket kayıtlı parolayla çözülür" | OTOMATİK – PASS (23.11 2. tur) (aynı süreçte farklı Hub kimliğiyle; gerçek ikinci PC değil) | `BK-PAT-13` BLOCKED |
| BK-004 | `MMSBAK01` geriye dönük uyumluluk | `v2` → `BK-001` (MMSBAK01 okuma); `lp` → `LP-05` | OTOMATİK – PASS (23.11 2. tur) | — |
| BK-005 | Cross-device vs farklı tenant/store reddi | İstemci: `packages/mms_client_storage/test/s5a4_backup_restore_test.dart`, `restore_outbox_preservation_test.dart`; Hub: `HubRestoreService` `ERR_TENANT_ID_MISMATCH` kodu | KISMİ — Hub merkezi restore için tenant/store uyuşmazlığı **otomatik test YOK** | — (ayrı fiziksel test tanımlı değil) |
| BK-006 | Yerel şifreleme başarısı vs Drive tamamlama ayrımı (`afterSuccess`) | `prov` → `BK-032` | OTOMATİK – PASS (23.11 2. tur) | — |
| BK-007 | 12 durumlu state machine | `b3` → `BK-006 & BK-016` | OTOMATİK – PASS (23.11 2. tur) | `BK-PAT-08` BLOCKED |
| BK-008 | İlk etkinleştirmede başlangıç yedeği (`INITIAL_ENABLE`) | `b3` → `BK-007 & BK-009` | OTOMATİK – PASS (23.11 2. tur) | `BK-PAT-02` BLOCKED |
| BK-009 | Yerel 00:00, `CATCH_UP` | `b3` → `BK-007 & BK-009`; `s1s6` → S1 kilit testleri (`SCHEDULED_DAILY`) | OTOMATİK – PASS (23.11 2. tur) (sahte saat) | `BK-PAT-03` BLOCKED (sistem saati değiştirilmez) |
| BK-010 | Retry backoff 5/10/20/40/80/160 | `b3` → `BK-008 & BK-028` | OTOMATİK – PASS (23.11 2. tur) | — |
| BK-011 | Kalıcı hata, 403 kota vs auth | `upl` → `BK-013`; `b3` → `BK-008 & BK-028` | OTOMATİK – PASS (23.11 2. tur) (mock HTTP) | `BK-PAT-05` BLOCKED |
| BK-012 | 4 MiB resumable upload, `HTTP 308` | `upl` → `BK-011` | OTOMATİK – PASS (23.11 2. tur) (mock HTTP) | `BK-PAT-04` BLOCKED |
| BK-013 | Oturum süresi dolması (404/410) | `upl` → `BK-012` | OTOMATİK – PASS (23.11 2. tur) | `BK-PAT-04` BLOCKED |
| BK-014 | Gün değişimi `SUPERSEDED` | `b3` → `BK-007 & BK-009` | OTOMATİK – PASS (23.11 2. tur) | — |
| BK-015 | Aşamalı crash recovery, PBKDF2 atlama | `b3` → `BK-010` | OTOMATİK – PASS (23.11 2. tur) | `BK-PAT-08` BLOCKED |
| BK-016 | Temp snapshot temizliği, atomik state | `b1` → `BK-005`; `b3` → `BK-006 & BK-016`; `s1s6` → S3 testleri | OTOMATİK – PASS (23.11 2. tur) | — |
| BK-017 | Disk alanı yetersizliği | `b1` → `BK-005`; `v2` → `BK-017` | OTOMATİK – PASS (23.11 2. tur) | `BK-PAT-06` BLOCKED |
| BK-018 | Drive vs yerel retention, takvim ayı arşivi | `v2` → `BK-018 & BK-019` | OTOMATİK – PASS (23.11 2. tur) | `BK-PAT-10` BLOCKED (`TEST_ONLY` klasör) |
| BK-019 | Son geçerli yedeğin korunması | `v2` → `BK-018 & BK-019`; `b3` → `BK-033` | OTOMATİK – PASS (23.11 2. tur) | `BK-PAT-11` BLOCKED |
| BK-020 | Drive `VERIFYING` reddi (size/md5 uyuşmazlığı) | `upl` → `BK-011` (yalnız başarılı doğrulama yolu); eski istemci: `google_drive_backup_test.dart` → `7.` (MD5 uyuşmazlığı → `ERR_DRIVE_VERIFY_FAILED`) | KISMİ — Hub `ResumableDriveUploader` VERIFYING **red yolu için otomatik test YOK** | — (ayrı fiziksel test tanımlı değil) |
| BK-021 | Windows PKCE → Hub handoff, ACL depolama | `b2` → `BK-021`, `BK-020` (DPAPI entropy) | KISMİ — handoff/DPAPI otomatik PASS (23.11 2. tur); NTFS ACL yalnız betik/AST | `BK-PAT-01`, `PAT-10` BLOCKED |
| BK-022 | Eski Android yerel yedek akışı izolasyonu (`B1.12`) | `prov` → `BK-032`; `ui` → `BK-029a` | KISMİ (UI ayrımı + Drive hatasının yerel yedeği bozmaması) | `BK-PAT-16` BLOCKED |
| BK-023 | Restore öncesi safety snapshot şifreleme, otomatik rollback | `b4` → `BK-025` (şifreli safety snapshot); `lp` → `LP-05` (legacy safety kopyası) | KISMİ — Hub merkezi restore rollback'i **otomatik test YOK** | `BK-PAT-17` BLOCKED |
| BK-024 | Yeni PC pepper değişimi, toplu cihaz geçersizleştirme | `b4` → `BK-025` | OTOMATİK – PASS (23.11 2. tur) | `BK-PAT-13` BLOCKED |
| BK-025 | Re-pairing, Outbox/`client_seq` uzlaştırması | `prr` → `BK-026`, `BK-027`; `bk02_1_hub_reconciliation_test.dart` | OTOMATİK – PASS (23.11 2. tur) | `BK-PAT-14` BLOCKED |
| BK-026 | Android backup UI ↔ Hub API uyumu | `ui` → `BK-029b`, `BK-031`; S2 UI testleri | OTOMATİK – PASS (23.11 2. tur) (widget/mock HTTP) | `BK-PAT-15` BLOCKED |
| BK-027 | `CASHIER` yetki sınırı görünümü | `ui` → `BK-029b`; `b4` → `BK-023` | OTOMATİK – PASS (23.11 2. tur) | `BK-PAT-15` BLOCKED |
| BK-028 | Çevrimdışı Hub modunda satışların yedekten etkilenmemesi | `b1` → `BK-004` (şifreleme WriteQueue'yu bloklamaz) | KISMİ — yedek sırasında satış kabulünü uçtan uca sınayan test yok | — (dolaylı: `BK-PAT-18`) BLOCKED |
| BK-029 | Drive indirme bozulması (`.part`, SHA-256) | İstemci: `google_drive_backup_test.dart` (13, 14) | KISMİ — Hub'da Drive'dan indirme akışı **yok** (Hub restore yerel paket/`backup_id` ile çalışır) | `BK-PAT-12` BLOCKED |
| BK-030 | Single-flight backup/restore çakışması | `b3` → `BK-014 & BK-015 & BK-030`; `s1s6` → S1 kilit testleri | OTOMATİK – PASS (23.11 2. tur) | `BK-PAT-09` BLOCKED |
| BK-031 | `OWNER`/`CASHIER` + replay protection | `b4` → `BK-022`, `BK-023`, `BK-024`; `ui` → `BK-031`; `s1s6` → S2 HTTP testleri | OTOMATİK – PASS (23.11 2. tur) | `BK-PAT-15` BLOCKED |
| BK-032 | Graceful shutdown + aynı `backup_id` ile devam | `b3` → `BK-014 & BK-015 & BK-030` | OTOMATİK – PASS (23.11 2. tur) (süreç içi; gerçek WinSW Stop değil) | `BK-PAT-07` BLOCKED |

## 3. Şartnamede olmayan ek otomatik testler

| Test etiketi | Dosya | Davranış |
|---|---|---|
| `BK-033` | `b3` | Drive retention silinen yedeğin `driveFileId` alanını temizler (`IMP-04`) |
| `LP-01…LP-07` | `lp` | Eski uçlarda pepper yerine Portable Recovery Password; `legacy_machine_key` (+ S4 koruyucu kopya) |
| S1 (7 test) | `s1s6` | Zamanlayıcı hatası Hub sürecini sonlandırmaz (`IMP-08`) |
| S2 (6 test) + UI (2 test) | `s1s6`, `ui` | Manuel yedek yalnız kayıtlı parola (`IMP-09`) |
| S3 (3 test) | `s1s6` | Durum deposu eşzamanlılığı (`IMP-10`) |
| S5 (1 + 4 test) | `s1s6`, `packages/mms_client_storage/test/s5_drive_folder_separation_test.dart` | Drive klasör ayrımı (`IMP-13`) |

## 4. Fiziksel testler

`BK-PAT-01…BK-PAT-18` ([şartname §4.2](BACKUP_RESTORE_ACCEPTANCE_TESTS_V1_1.md)) **hiçbiri çalıştırılmadı — tamamı `BLOCKED`.** Otomatik testlerin PASS olması bu fiziksel testlerin yerine geçmez.
