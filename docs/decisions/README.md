# Mimari Karar Kayıtları (Architecture Decision Records - ADR)

Bu dizin, **Market Management System (MMS)** projesinde alınan tüm bağlayıcı mimari kararları, değerlendirilen alternatifleri, tercih gerekçelerini ve sonuçlarını standart ADR formatında kayıt altına alır.

---

## 1. Karar Durum Standartları

Her ADR belgesi aşağıdaki durumlardan birine sahiptir:
- **`[CONFIRMED]`**: Kullanıcı tarafından açıkça onaylanmış ve bağlayıcı kabul edilmiş mimari karar.
- **`[PROPOSED]`**: Teknik analizle önerilen, kullanıcı değerlendirmesi veya teknik spike doğrulaması bekleyen karar.
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
| **ADR-010** | İstemci Taraflı Zarf Şifreleme (`AES-256-GCM` + `SHA-256`) | **CONFIRMED** | [`BACKUP_RESTORE_DECISIONS.md`](../architecture/BACKUP_RESTORE_DECISIONS.md) |
| **ADR-011** | Google Drive OAuth 2.0 En Dar Kapsam (`drive.file`) Kullanımı | **CONFIRMED** | [`BACKUP_RESTORE_DECISIONS.md`](../architecture/BACKUP_RESTORE_DECISIONS.md) |
| **ADR-012** | Windows Local Master Hub ve Single-Writer API Mimarisi | **PROPOSED** | [`MARKET_MMS_ARCHITECTURE_ALIGNMENT_REVIEW.md`](../../MARKET_MMS_ARCHITECTURE_ALIGNMENT_REVIEW.md) |

---

## 3. Yeni Karar Ekleme Kuralı

Yeni bir mimari karar eklenirken [`ADR_TEMPLATE.md`](./ADR_TEMPLATE.md) şablonu kullanılmalı; kullanıcı onayı alınmadan durum `CONFIRMED` olarak işaretlenmemelidir.

