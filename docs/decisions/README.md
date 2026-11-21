# Mimari Karar Kayıtları (Architecture Decision Records - ADR)

Bu dizin, **Market Management System (MMS)** projesinde alınan tüm bağlayıcı mimari kararları, değerlendirilen alternatifleri, tercih gerekçelerini ve sonuçlarını standart ADR formatında kayıt altına alır.

---

## 1. Karar Durum Standartları

Her ADR belgesi aşağıdaki durumlardan birine sahiptir:
- **`[CONFIRMED]`**: Kullanıcı tarafından açıkça onaylanmış ve bağlayıcı kabul edilmiş mimari karar.
- **`[PARTIALLY_CONFIRMED / IN_REVIEW]`**: Kararın bir bölümü onaylanmış, kalan teknik/doğrulama adımları kullanıcı incelemesinde bekleyen karar.
- **`[PROPOSED]`**: Teknik analizle önerilen, kullanıcı değerlendirmesi veya teknik spike doğrulaması bekleyen karar.
- **`[DEFERRED_POST_PILOT]`**: Pilot sonrası döneme ertelenmiş karar; pilotta yalnızca belgelenen operasyonel sınırlar geçerlidir.
- **`[DEPRECATED]`**: Daha sonraki mimari revizyonlarla geçerliliğini yitirmiş eski karar.

---

## 2. Mevcut Karar Kayıtları İndeksi

| Karar Kodu | Karar Başlığı | Durum | İlgili Belge |
| :--- | :--- | :---: | :--- |
| **ADR-001** | Feature-First + Clean Architecture Katman Ayrımı | **CONFIRMED** | [`docs/ARCHITECTURE.md`](../ARCHITECTURE.md) |
| **ADR-002** | Para Değerlerinde Kuruş Bazlı Tamsayı (`BIGINT`) Temsili | **CONFIRMED** | [`DATA_MODEL_DECISIONS.md`](../architecture/DATA_MODEL_DECISIONS.md) |
| **ADR-003** | Birleşik Barkod Yaşam Döngüsü ve Mutlak Tekillik | **CONFIRMED** | [`DATA_MODEL_DECISIONS.md`](../architecture/DATA_MODEL_DECISIONS.md) |
| **ADR-004** | Atomik Stok Birimi ve Rasyonel Pay/Payda Dönüşümü | **CONFIRMED** | [`DATA_MODEL_DECISIONS.md`](../architecture/DATA_MODEL_DECISIONS.md) |
| **ADR-005** | Eksi Stoğun Veritabanı Seviyesinde Serbest Bırakılması (`allow`) | **CONFIRMED** | [`DATA_MODEL_DECISIONS.md`](../architecture/DATA_MODEL_DECISIONS.md) |
| **ADR-006** | Satış Başına Tek Ödeme (Nakit/Kart) ve Koşullu Tablo CHECK Kısıtı | **CONFIRMED** | [`DATA_MODEL_DECISIONS.md`](../architecture/DATA_MODEL_DECISIONS.md) |
| **ADR-007** | Deterministik Cihaz Monotonik Sıra Numarası (`client_sequence_number` FIFO) | **CONFIRMED** | [`OFFLINE_SYNC_DECISIONS.md`](../architecture/OFFLINE_SYNC_DECISIONS.md) |
| **ADR-008** | Geri Yüklemede Bekleyen Outbox Dokunulmazlığı ve Sayacın İlerletilmesi | **CONFIRMED** | [`BACKUP_RESTORE_DECISIONS.md`](../architecture/BACKUP_RESTORE_DECISIONS.md) |
| **ADR-009** | Canlı SQLite Snapshot Alma Yöntemi: `VACUUM INTO` | **CONFIRMED** | [`BACKUP_RESTORE_DECISIONS.md`](../architecture/BACKUP_RESTORE_DECISIONS.md) |
| **ADR-010** | İstemci Taraflı Şifreleme (`AES-256-CBC` + `HMAC-SHA256`) | **CONFIRMED** | [`BACKUP_RESTORE_DECISIONS.md`](../architecture/BACKUP_RESTORE_DECISIONS.md) |
| **ADR-011** | Google Drive OAuth 2.0 En Dar Kapsam (`drive.file`) Kullanımı | **CONFIRMED** | [`BACKUP_RESTORE_DECISIONS.md`](../architecture/BACKUP_RESTORE_DECISIONS.md) |
| **ADR-012** | Windows Local Master Hub ve Single-Writer API Mimarisi | **CONFIRMED** | [`MARKET_MMS_ARCHITECTURE_ALIGNMENT_REVIEW.md`](../../MARKET_MMS_ARCHITECTURE_ALIGNMENT_REVIEW.md) |
| **ADR-013** | Stok Girişinde Delta Senkronizasyonu (`STOCK_RECEIPT`) ve Mutlak Stok Ezilmesinin Kaldırılması | **CONFIRMED** (21.11.2026) | [`013-stock-receipt-delta-sync.md`](./013-stock-receipt-delta-sync.md) |
| **ADR-014** | Tenant/Store Başlıklarının Zorunlu Kılınması | **CONFIRMED** (21.11.2026) | [`014-tenant-store-header-enforcement.md`](./014-tenant-store-header-enforcement.md) |
| **ADR-015** | REL-01 — Windows Hub için Tek Doğrulanmış Yapılandırma Kaynağı | **CONFIRMED** (21.11.2026; env fallback kaldırıldı; SCM/ACL fiziksel **BLOCKED**) | [`015-rel01-single-hub-config.md`](./015-rel01-single-hub-config.md) |
| **ADR-016** | Yedekleme Güvenilirliği — Restore'da Outbox Korunması, Zamanlanmış Yedek, USB ve Google Drive | **CONFIRMED** (21.11.2026; kilit heartbeat/60s + Hub kilidi + §7 düzeltmesi) | [`016-backup-reliability-restore-outbox-scheduled-usb-drive.md`](./016-backup-reliability-restore-outbox-scheduled-usb-drive.md) |
| **ADR-017** | Şifresiz Snapshot Ucunun Kapatılması ve TLS Pin / Sertifika Doğrulama Sınıflandırması | **PARTIALLY_CONFIRMED / IN_REVIEW** (Snapshot **CONFIRMED**; TLS sınıflandırma düzeltildi, PAT-12 **BLOCKED**) | [`017-snapshot-endpoint-and-tls-pin-classification.md`](./017-snapshot-endpoint-and-tls-pin-classification.md) |
| **ADR-018** | Hub Keşfinde TLS — İstemci Tarafı Şema Seçimi ve Manuel Eşleştirme Protokolü | **CONFIRMED** (21.11.2026; §2.1 & Seçenek C; `P-BLOCK-1..3` Owner kararı bekliyor) | [`018-discovery-tls-scheme.md`](./018-discovery-tls-scheme.md) |
| **ADR-019** | Kategori ve KDV Oranı Senkronizasyonu (SYNC-CAT) — Pilot %20 KDV Kısıtı | **DEFERRED_POST_PILOT** (21.11.2026; 7 kısıt / 8 risk / 9 gereksinim belgelendi) | [`019-category-vat-sync.md`](./019-category-vat-sync.md) |
| **ADR-020** | Android'de Uygulama Kapalıyken Zamanlanmış Yedek (WorkManager) | **DEFERRED_POST_PILOT** (21.11.2026; `workmanager` ertelendi; Keystore hata eşleme uygulandı) | [`020-android-background-backup-workmanager.md`](./020-android-background-backup-workmanager.md) |

---

## 3. Yeni Karar Ekleme Kuralı

Yeni bir mimari karar eklenirken [`ADR_TEMPLATE.md`](./ADR_TEMPLATE.md) şablonu kullanılmalı; kullanıcı onayı alınmadan durum `CONFIRMED` olarak işaretlenmemelidir.

