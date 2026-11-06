# BACKUP_RESTORE_DECISIONS.md — Market POS (MMS) Yedekleme ve Geri Yükleme Mimari Karar Kayıtları (ADR)

**Belge Sürümü:** v1.0  
**Tarih:** 31 Ekim 2026  
**Aşama:** Faz 0 — Mimari ve Teknik Protokol Tasarımı  
**İlgili Doküman:** [`docs/architecture/BACKUP_RESTORE_PROTOCOL.md`](./BACKUP_RESTORE_PROTOCOL.md)

---

## Karar Kayıtları Dizini

- [ADR-BAK-01: Bağımsız Google Drive Entegrasyonu ve Tenant Taşınabilirliği](#adr-bak-01-bağımsız-google-drive-entegrasyonu-ve-tenant-taşınabilirliği)
- [ADR-BAK-02: Yerel SQLite Snapshot Alma Yöntemi: `VACUUM INTO` ve Online Backup API](#adr-bak-02-yerel-sqlite-snapshot-alma-yöntemi-vacuum-into-ve-online-backup-api)
- [ADR-BAK-03: Geri Yükleme Sırasında Bekleyen Outbox İşlemlerinin Dokunulmazlığı ve Sayacın İlerletilmesi](#adr-bak-03-geri-yükleme-sırasında-bekleyen-outbox-işlemlerinin-dokunulmazlığı-ve-sayacın-ilerletilmesi)
- [ADR-BAK-04: Geri Yükleme Öncesi Canlı Güvenlik Yedeği (Pre-Restore Safety Snapshot) Zorunluluğu](#adr-bak-04-geri-yükleme-öncesi-canlı-güvenlik-yedeği-pre-restore-safety-snapshot-zorunluluğu)
- [ADR-BAK-05: Google Drive OAuth 2.0 En Dar Kapsam (`drive.file`) Kullanımı](#adr-bak-05-google-drive-oauth-20-en-dar-kapsam-drivefile-kullanımı)
- [ADR-BAK-06: İstemci Taraflı Zarf Şifreleme (Client-side Envelope Encryption with AES-256-GCM)](#adr-bak-06-istemci-taraflı-zarf-şifreleme-client-side-envelope-encryption-with-aes-256-gcm)
- [ADR-BAK-07: 30 Günlük Kayan Saklama ve Aylık Arşiv Politikası](#adr-bak-07-30-günlük-kayan-saklama-ve-aylık-arşiv-politikası)
- [ADR-BAK-08: Geri Yükleme Sonrası Deterministik Sunucu Mutabakatı (`POST /sync/verify-keys`)](#adr-bak-08-geri-yükleme-sonrası-deterministik-sunucu-mutabakatı-post-syncverify-keys)

---

### ADR-BAK-01: Bağımsız Google Drive Entegrasyonu ve Tenant Taşınabilirliği

- **Durum:** Onaylandı.
- **Bağlam:** Merkezi veritabanımız Supabase PostgreSQL üzerinde çalışmakta olup, Supabase altyapısı otomatik günlük imaj ve WAL tabanlı PITR (Point-in-Time Recovery) sağlamaktadır. Ancak SaaS mimarimizde tüm kiracılar aynı fiziksel veritabanı kümesini paylaşır. Bir market sahibinin kendi verilerine bağımsız erişimi, SaaS bağımlılığı (vendor lock-in) riski olmadan kendi mülkiyetindeki Google Drive hesabına aktarılabilmelidir.
- **Karar:**
  1. Supabase'in yönetilen PITR yedekleri yalnızca felaketten kurtarma (tüm sunucu çökmesi) için birincil altyapı güvencesi olarak kabul edilir.
  2. Her kiracı (tenant) için veriler mantıksal olarak izole edilir (`tenant_id`), şifrelenir ve market sahibinin kendi bağladığı Google Drive hesabına bağımsız `.mmsbak` arşivi olarak aktarılır.
- **Sonuçlar:** Market sahibi MMS SaaS aboneliğini sonlandırsa dahi tüm geçmiş satış, cari ve stok hareketlerinin şifreli ve doğrulanabilir yedeğine sahip olur.

---

### ADR-BAK-02: Yerel SQLite Snapshot Alma Yöntemi: `VACUUM INTO` ve Online Backup API

- **Durum:** Onaylandı.
- **Bağlam:** Masaüstü (Windows) ve mobil (Android/iOS) platformlarında Drift + SQLite veritabanı WAL (Write-Ahead Logging) modunda çalışır. WAL modunda işletim sistemi düzeyinde dosya kopyalamak (`File.copy('market_pos.db')`), uncheckpointed veriler `-wal` dosyasında kaldığı için bozuk veya eksik veritabanı üretir. Canlı kasa satışları yapılırken yedekleme yazma kilidi koymamalıdır.
- **Karar:**
  1. Yerel SQLite anlık görüntüleri için SQLite 3.27+ standardı olan `VACUUM INTO 'target_path.db';` SQL komutu birincil yöntem olarak belirlenmiştir.
  2. `VACUUM INTO`, aktif okuma ve yazma işlemlerini engellemeden (non-blocking) WAL dosyasındaki commit edilmiş tüm sayfaları temizleyip birleştirerek tek parçalı, optimize edilmiş ve tutarlı bir kopya üretir.
  3. Düşük bellekli veya özel C API seviyesinde kontrol gerektiren durumlarda SQLite Online Backup API (`sqlite3_backup_init`) alternatif sürücü olarak mimaride desteklenir.
- **Sonuçlar:** Kasa satışları anında bile sıfır bekleme süresi ve sıfır dosya bozulması ile tutarlı anlık görüntü alınır.

---

### ADR-BAK-03: Geri Yükleme Sırasında Bekleyen Outbox İşlemlerinin Dokunulmazlığı ve Sayacın İlerletilmesi

- **Durum:** Onaylandı.
- **Bağlam:** Bir cihaza geçmiş tarihli bir yedek geri yüklendiğinde, o yedeğin oluşturulduğu tarihten sonra cihazın çevrimdışıyken yaptığı satışlar yedeğin içinde yer almaz. Bu satışlar cihazın Outbox (`sync_operations`) kuyruğunda beklemektedir. Eski yedeğin doğrudan veritabanının üzerine yazılması bu bekleyen satışların silinmesine ve market için mali kayba neden olur.
- **Karar:**
  1. **Dokunulmazlık Kuralı (Immutability):** Bekleyen (`PENDING` veya `PROCESSING`) Outbox işlemlerinin `operation_id`, `idempotency_key`, `payload` ve `client_sequence_number` alanları kesinlikle değiştirilemez ve silinemez.
  2. **Staging Havuzu:** Geri yükleme başlamadan önce bekleyen işlemler geçici bir belleğe/dosyaya (`Staging`) alınır.
  3. **Deterministik Sayaç İlerlemesi:** Geri yüklenen veritabanındaki yerel sıra üreteci (`device_sync_sequence`) şu formülle güncellenir:
     $$S_{\text{next\_generator}} = \max\left(S_{\text{backup\_max}}, \; \max(S_{\text{staged}})\right) + 1$$
  4. Staging havuzundaki işlemler orijinal sıra numaralarıyla yeni veritabanının Outbox tablosuna geri eklenir.
- **Sonuçlar:** Hiçbir çevrimdışı satış kaybolmaz, sıra numarası çakışması yaşanmaz ve FIFO bütünlüğü korunur.

---

### ADR-BAK-04: Geri Yükleme Öncesi Canlı Güvenlik Yedeği (Pre-Restore Safety Snapshot) Zorunluluğu

- **Durum:** Onaylandı.
- **Bağlam:** Operatör veya kullanıcı yanlış bir yedek dosyasını seçebilir veya geri yükleme sırasında donanımsal bir arıza meydana gelebilir. Güvenlik mekanizması olmadan yapılan bir geri yükleme geri alınamaz veri kaybına yol açar.
- **Karar:**
  1. Geri yükleme prosedürünün 2. adımı olarak, mevcut canlı veritabanının `VACUUM INTO` ile atomik bir güvenlik görüntüsü (`safety_snapshot_*.db`) alınması zorunludur.
  2. Güvenlik yedeği diske başarıyla yazılmadan ve SHA-256 bütünlüğü doğrulanmadan asıl geri yükleme adımı başlatılamaz.
  3. Kullanıcı geri yüklenen durumdan memnun kalmazsa "Güvenlik Yedeğine Geri Dön" seçeneğiyle saniyeler içinde geri yükleme öncesi canlı duruma dönebilir.
- **Sonuçlar:** Operatör hatalarına karşı %100 geri alınabilir (*fail-safe*) işlem güvenliği sağlanır.

---

### ADR-BAK-05: Google Drive OAuth 2.0 En Dar Kapsam (`drive.file`) Kullanımı

- **Durum:** Onaylandı.
- **Bağlam:** Google Drive API farklı erişim izinleri (scopes) sunar: `drive` (tam erişim), `drive.readonly` (tüm Drive'ı okuma), `drive.file` (yalnızca uygulamanın oluşturduğu dosyalara erişim), `drive.appdata` (gizli uygulama klasörü). Market sahipleri ticari yazılımlara tüm kişisel veya kurumsal Drive içeriklerini açmak istemez; gizlilik ve güvenlik endişesi duyar.
- **Karar:**
  1. Yalnızca `https://www.googleapis.com/auth/drive.file` kapsamı istenir.
  2. Bu kapsam, MMS uygulamasının kullanıcının Drive'ındaki diğer kişisel veya iş dosyalarını görmesini, okumasını veya listelemesini kesinlikle engeller.
  3. Dosyalar, kullanıcının doğrudan görebileceği `/Market_POS_Backups/{tenant}/` klasöründe tutulur; böylece kullanıcı kendi dosyasını bağımsız olarak kopyalayabilir veya indirebilir.
- **Sonuçlar:** Maksimum kullanıcı güveni, en az yetki prensibi (*Principle of Least Privilege*) ve hızlı Google OAuth doğrulama onayı sağlanır.

---

### ADR-BAK-06: İstemci Taraflı Zarf Şifreleme (Client-side Envelope Encryption with AES-256-GCM)

- **Durum:** Onaylandı.
- **Bağlam:** Google Drive veya harici USB bellek gibi üçüncü taraf ortamlara yüklenen yedek dosyaları çalınabilir, sızdırılabilir veya yetkisiz personelin eline geçebilir. Düz metin SQLite veritabanı yedeği ciddi bir veri güvenliği açığıdır.
- **Karar:**
  1. Yedek dosyaları cihazdan çıkmadan önce istemci tarafında şifrelenir.
  2. Şifreleme standardı olarak doğrulanmış şifreleme sağlayan `AES-256-GCM` kullanılır.
  3. Her dosya için benzersiz bir DEK (Data Encryption Key) üretilir; DEK anahtarı yöneticinin şifresinden türetilen KEK (PBKDF2 + SHA-256 + 100.000 iterasyon) ile zarflanır.
  4. Dosyanın bütünlüğü GCM kimlik doğrulama etiketi (*Authentication Tag*) ve harici SHA-256 özeti ile iki kademeli olarak garanti edilir.
- **Sonuçlar:** Google veya harici depolama sağlayıcısı dahi yedek içeriğini açamaz; kurumsal düzeyde veri gizliliği sağlanır.

---

### ADR-BAK-07: 30 Günlük Kayan Saklama ve Aylık Arşiv Politikası

- **Durum:** Onaylandı.
- **Bağlam:** Her gün alınan yedekler sonsuza dek saklanırsa Google Drive depolama kotası hızla dolar ve gereksiz maliyet oluşur. Ancak geçmişe dönük vergi ve mali denetim ihtiyaçları için aylık özet kayıtların korunması gerekir.
- **Karar:**
  1. **Günlük Yedekler:** Son 30 gün boyunca saklanır. 30 günü aşan günlük dosyalar otomatik temizlik mekanizması ile silinir.
  2. **Aylık Arşiv:** Her ayın 1. günü alınan yedek `ARCHIVE` olarak etiketlenir ve silinmez.
  3. Aylık arşivlerin saklama süresi varsayılan olarak `[PROPOSED]` 12 ay olarak belirlenmiştir; işletmenin tercihine göre süresiz saklama `[OPEN]` bırakılmıştır.
- **Sonuçlar:** Depolama maliyeti ve kotası optimize edilirken yasal uyumluluk garanti edilir.

---

### ADR-BAK-08: Geri Yükleme Sonrası Deterministik Sunucu Mutabakatı (`POST /sync/verify-keys`)

- **Durum:** Onaylandı.
- **Bağlam:** Bir cihaz çökmeden veya geri yüklenmeden önce bir satışı sunucuya göndermiş, sunucu satışı işlemiş fakat ağ kesintisi nedeniyle onay yanıtı cihaza dönememiş olabilir. Geri yüklenen cihaz bu işlemi yerel olarak `PENDING` görür. Cihaz bunu tekrar gönderirse ve sunucu idempotent kontrolü yapmazsa veya cihaz boşuna tekrar denerse ağ ve işlem yükü oluşur.
- **Karar:**
  1. Geri yükleme sonrası internet bağlantısı kurulduğunda cihaz, bekleyen tüm işlemlerin `idempotency_key` listesini `POST /api/v1/sync/verify-keys` uç noktasına gönderir.
  2. Sunucu `sync_inbox` tablosunda kayıtlı olanları doğrudan `COMMITTED` olarak döner.
  3. Cihaz bu işlemleri yerelde yeniden sunucuya basmaz, doğrudan `status = 'COMPLETED'` yapar. Yalnızca sunucuda bulunmayan (`NOT_FOUND`) işlemler senkronizasyon kuyruğuna sokulur.
- **Sonuçlar:** Sıfır mükerrer gönderim, sıfır ağ israfı ve deterministik mutabakat sağlanır.

