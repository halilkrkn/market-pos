# MARKET MANAGEMENT SYSTEM (MMS)

**Market Management System (MMS)**, küçük ve orta ölçekli perakende marketlerin günlük satış, stok, fiyat, barkod, dashboard ve kasa operasyonlarını yönetmek üzere geliştirilen profesyonel bir market yönetim yazılımıdır.

> [!NOTE]
> Teknik proje ve Git deposu adı olarak `market-pos` korunmaktadır. Ürünün resmi adı **MARKET MANAGEMENT SYSTEM (MMS)**'tir. MMS bir banka POS cihazı değildir; harici banka terminalleriyle donanımsal iletişim MVP kapsamı dışındadır.

---

## 1. Mimari Genel Bakış: Windows Local Master Hub

MMS, mağaza içinde internet bağlantısı kopsa dahi kesintisiz çalışmayı garanti eden **On-Premises Local Master Hub** mimarisine sahiptir:

```text
               +-----------------------------------------------------+
               |         Windows Bilgisayar (Master Sunucu)          |
               |                                                     |
               |  +--------------------+    +---------------------+  |
               |  | Flutter Desktop UI |    |   Windows Service   |  |
               |  +---------+----------+    |   (Arka Plan API)   |  |
               |            |               +----------+----------+  |
               |            +--- Loopback (HTTP) ------+             |
               |                                       |             |
               |                       [Merkezi SQLite (WAL)]        |
               +---------------------------------------+-------------+
                                                       |
                             Yerel Wi-Fi / LAN (HTTP / WebSocket)
                                                       |
               +---------------------------------------+-------------+
               |                                                     |
    +----------+-----------+                              +----------+-----------+
    | Android Kasa Cihazı  |                              |   iOS Kasa Cihazı    |
    | (Drift + Yerel SQLite)                              | (Drift + Yerel SQLite)
    +----------------------+                              +----------------------+
```

- **Merkezi Düğüm:** Mağazadaki Windows bilgisayar ana sunucudur. Arka planda bağımsız bir **Windows Service** çalışır.
- **Tekil Yazıcı (Single-Writer):** Merkezi SQLite veritabanına tüm yazma işlemleri Windows Service API'si üzerinden yönetilir. Flutter masaüstü arayüzü de yerel API üzerinden işlem yapar.
- **Yerel Senkronizasyon:** Mobil cihazlar (Android/iOS), internet olmasa dahi mağaza içi Wi-Fi / LAN üzerinden Windows Service API'sine bağlanır.
- **Windows Kapalıyken Satış:** Windows kapalıyken mobil cihazlar yerel Drift + SQLite veritabanlarında satış yapmaya devam eder; Windows açıldığında bekleyen Outbox işlemlerini aktarır.
- **Google Drive Yedekleme:** Canlı senkronizasyon için değil; merkezi veritabanının `VACUUM INTO` ile alınan şifreli (S5A-4 standardında `AES-256-CBC` + `HMAC-SHA256`) bağımsız yedeklemesi için kullanılır.
- **SaaS Hazırlığı:** Gelecekte bulut tabanlı çok şubeli SaaS modeline geçişi kolaylaştırmak amacıyla `tenant_id` ve `store_id` sınırları korunur.

---

## 2. Temel Teknoloji Yığını

| Alan | Seçilen Teknoloji | Not |
| :--- | :--- | :--- |
| **İstemci Çerçevesi** | Flutter (Dart) | Windows, Android ve iOS |
| **Uç Depolama** | Drift + SQLite (WAL Modu) | Mobil ve masaüstü yerel veri tabanı |
| **Merkezi Depolama** | Merkezi SQLite (Windows Service) | Tekil yazıcı ile yönetilen master defter |
| **Durum Yönetimi** | Riverpod | Reaktif ve test edilebilir durum yönetimi |
| **Yönlendirme** | go_router | Deklaratif navigasyon |
| **Barkod Girişi** | PC'de USB HID; Mobilde Kamera | Otomatik ürün arama ve ekleme |
| **Harici Yedekleme** | Google Drive API (`drive.file`) | İstemci taraflı AES-256-CBC + HMAC-SHA256 şifreleme |

---

## 3. Dokümantasyon Haritası

Proje dokümantasyonu `docs/` klasörü altında kanonik olarak organize edilmiştir:

- **[Proje Genel Bakış](docs/PROJECT_OVERVIEW.md):** Ürün vizyonu, kapsamı ve modül özeti.
- **[Gereksinimler](docs/REQUIREMENTS.md):** 10 modüllük bağlayıcı iş gereksinimleri fihristi.
- **[Mimari Dokümanı](docs/ARCHITECTURE.md):** Teknik mimari, katmanlar ve veri akışları.
- **[Geliştirme Kılavuzu](docs/DEVELOPMENT_GUIDE.md):** Kurulum, kodlama standartları ve test kılavuzu.
- **[Yol Haritası](docs/ROADMAP.md):** Faz 0–8 aşamaları.
- **[Proje Durumu](docs/PROJECT_STATUS.md):** Canlı proje fazı ve durum takibi.
- **[Veri Modeli Şartnamesi](docs/architecture/DATA_MODEL.md):** v1.1 sertleştirilmiş 25 tabloluk mantıksal model.
- **[Offline Sync Şartnamesi](docs/architecture/OFFLINE_SYNC_PROTOCOL.md):** Outbox kuyruğu, idempotency ve FIFO protokolü.
- **[Yedekleme Şartnamesi](docs/architecture/BACKUP_RESTORE_PROTOCOL.md):** Google Drive ve yerel kaza kurtarma protokolü.

---

## 4. Geliştirme ve Katkı Kuralları

Projeye katkı sağlayan tüm geliştiriciler ve yapay zekâ asistanları için kök dizindeki [`AGENTS.md`](./AGENTS.md) dosyası **birincil ve bağlayıcı ortak kurallar dizinidir**:

1. **Önce İş Kuralları, Sonra Kod:** İlgili modülün iş kuralları dokümante edilmeden kod yazılamaz.
2. **Faz Bazlı İlerleme:** Faz kabul kriterleri eksiksiz karşılanmadan ve kullanıcıdan açık onay alınmadan sonraki faza geçilemez. (Faz 0 ve Faz 1.1 tamamlanmıştır; Faz 1.2 için kullanıcı onayı esastır).
3. **Kuruş Tamsayı Standardı:** Para hesaplamalarında kesinlikle kayan noktalı (`double`) sayı aritmetiği kullanılmaz; tüm tutarlar kuruş tamsayı (`BIGINT` / `int`) tutulur.
4. **Geçmişin Korunması:** Fiziksel satış fişleri ve stok hareketleri çakışma durumunda asla silinemez.

