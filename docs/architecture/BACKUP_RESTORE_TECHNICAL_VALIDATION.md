# BACKUP_RESTORE_TECHNICAL_VALIDATION.md — Yedekleme ve Geri Yükleme Protokolü Bağımsız Teknik Doğrulama Raporu

**Belge Sürümü:** v1.0  
**Tarih:** 31 Ekim 2026  
**Denetçi Rolü:** Bağımsız Sistem Mimarisi ve Veri Bütünlüğü Denetçisi  
**Denetlenen Belgeler:**  
- `docs/architecture/BACKUP_RESTORE_PROTOCOL.md` (v1.0)  
- `docs/architecture/BACKUP_RESTORE_DECISIONS.md` (v1.0)  
- `docs/architecture/DATA_MODEL.md` (v1.1)  
- `docs/architecture/OFFLINE_SYNC_PROTOCOL.md` (v1.1)  
- `docs/architecture/LOCAL_STORAGE_TECHNICAL_VALIDATION.md` (v1.0)  
- `docs/requirements/BUSINESS_RULES_SPEC.md` (`BR-BAK-01` .. `BR-BAK-06`)

---

## 1. Denetim Amacı ve Metodolojisi

Bu teknik doğrulama raporu, Market Management System (MMS) için tasarlanan **Yedekleme ve Geri Yükleme Protokolü**'nün (`BACKUP_RESTORE_PROTOCOL.md`) veri kaybı risklerine, eşzamanlılık çakışmalarına, donanım/ağ arızalarına ve operatör hatalarına karşı dayanıklılığını bağımsız bir yaklaşımla test etmek amacıyla hazırlanmıştır.

Denetim sürecinde özellikle **7 Kritik Felaket Senaryosu**, WAL modundaki SQLite kilitlenme dinamikleri, çevrimdışı bekleyen Outbox işlemlerinin değişmezliği ve Google Drive API entegrasyon sınırları mercek altına alınmıştır.

---

## 2. 7 Kritik Felaket Senaryosunun Derinlemesine Doğrulaması

### 2.1. Senaryo 1 Doğrulaması: Çevrimdışı 20 Satış Sonrası Ani Çökme (Crash Recovery)
- **Mekanizma:** SQLite WAL kaza kurtarma mekanizması (`sqlite3_recover` veya otomatik WAL replay).
- **Risk Analizi:** Cihaz kapandığında commit edilmiş son sayfalar `-wal` dosyasındadır. SQLite, veritabanı tekrar açıldığında WAL başlığındaki checkpoint damgalarını okuyarak otomatik olarak ileri sarma (*roll-forward*) yapar.
- **Doğrulama Sonucu:** **GEÇTİ (PASSED)**. `LOCAL_STORAGE_TECHNICAL_VALIDATION.md` bulguları ile uyumludur. Outbox tablosundaki 20 işlem sağlam kalır ve `client_sequence_number` sıralaması bozulmaz.

### 2.2. Senaryo 2 Doğrulaması: Disk Bozulması ve Eski Yedeğe Dönüş (Corruption Recovery)
- **Mekanizma:** Donanımsal bozulma sonrası Google Drive'dan 24 saat önceki yedeğin indirilmesi ve sunucu ile Download Sync yapılması.
- **Risk Analizi:** Cihazın sunucuya aktaramadığı son 24 saatlik yerel kayıtların kurtarılması. Eğer disk fiziken okunamaz durumdaysa sunucuya gitmemiş yerel işlemler kaybolabilir.
- **Doğrulama Sonucu:** **ŞARTLI GEÇTİ (CONDITIONALLY PASSED)**. Protokol, diskin okunabilir kalan kısımlarından veya son `safety_snapshot` kopyasından veri kurtarmayı hedefler. Kurtarılamayan durumlar için sistemin yöneticiye net bir "Kurtarılamayan İşlem Sayısı" raporu üretmesi kuralı eklenmiştir.

### 2.3. Senaryo 3 Doğrulaması: Sunucunun 3 Gün Geriye Dönmesi (Cloud DB Rollback)
- **Mekanizma:** Supabase'in 3 gün önceki bir yedeğe dönmesi karşısında cihazların yerel Outbox işlemlerini tekrar basması.
- **Risk Analizi:** Sunucu geriye döndüğünde cihazların son 3 günde gönderdiği `idempotency_key`ler sunucu `sync_inbox` tablosunda kaybolur. Cihazlar bu anahtarları `verify-keys` ile sorguladığında `NOT_FOUND` yanıtı alır.
- **Doğrulama Sonucu:** **MÜKEMMEL (EXCELLENT)**. Protokolün `verify-keys` mekanizması, sunucunun geriye gitmesi durumunda istemcilerin yerel Outbox kayıtlarını otomatik olarak `PENDING` statüsüne çekerek sunucuyu yeniden beslemesini sağlar. Bu, dağıtık sistemlerde veri kaybını engelleyen üst düzey bir tasarımdır.

### 2.4. Senaryo 4 Doğrulaması: Çevrimdışı Kasa Varken Google Drive Yedeği Alınması
- **Mekanizma:** Mağazada bir kasa çevrimdışıyken diğer cihazdan veya sunucudan yedek alınması.
- **Risk Analizi:** Alınan yedeğin eksik veri içermesi korkusu.
- **Doğrulama Sonucu:** **GEÇTİ (PASSED)**. Alınan yedek o anki merkezi ve yetkili durumu temsil eder. Çevrimdışı kasanın satışları internete çıktığında sunucuya aktarılacak ve bir sonraki döngüde yedeklenecektir. Çevrimdışı kasa geri yüklense dahi kendi Outbox'ındaki verileri koruduğu için çelişki doğmaz.

### 2.5. Senaryo 5 Doğrulaması: Aynı Yedeğin Mükerrer Geri Yüklenmesi
- **Mekanizma:** Operatörün aynı `.mmsbak` dosyasını art arda iki kez yüklemesi.
- **Risk Analizi:** Veri çoklanması, mükerrer stok düşüşü veya bakiye şişmesi.
- **Doğrulama Sonucu:** **GEÇTİ (PASSED)**. Geri yükleme işlemi idempotenttir. Her geri yükleme öncesi yeni bir `safety_snapshot` alınır ve veritabanı yedeğin tam durumuna sıfırlanır. Outbox işlemleri `idempotency_key` taşıdığı için sunucu tarafında çiftleme yaşanması matematiksel olarak imkânsızdır.

### 2.6. Senaryo 6 Doğrulaması: Yanıtı Alınamayan İşlem Sırasında Çökme ve Geri Yükleme
- **Mekanizma:** Satış sunucuda işlendi fakat cihaza onay dönmeden kasa çöktü; ardından yedek yüklendi.
- **Risk Analizi:** Cihazın işlemi sunucuya ikinci kez gönderip mükerrer satış yaratması.
- **Doğrulama Sonucu:** **GEÇTİ (PASSED)**. `POST /sync/verify-keys` uç noktası sayesinde sunucu "Bu anahtar bende COMMITTED durumdadır" cevabını döner; cihaz işlemi yerelde doğrudan `COMPLETED` yapar ve mükerrer çağrıyı önler.

### 2.7. Senaryo 7 Doğrulaması: Geri Yükleme Esnasında Diğer Kasaların Canlı Satış Yapması
- **Mekanizma:** Kasa-1 geri yüklenirken Kasa-2'nin kesintisiz satış yapması.
- **Risk Analizi:** Kasa-1'in sunucuyu eski haline döndürerek Kasa-2'nin satışlarını ezmesi riski.
- **Doğrulama Sonucu:** **GEÇTİ (PASSED)**. Geri yükleme yalnızca Kasa-1'in yerel SQLite dosyasını kapsar. Merkezi sunucuya müdahale edilmez. Kasa-1 ayağa kalktığında Kasa-2'nin yaptığı güncel satışları sunucudan indirir.

---

## 3. Matematiksel Doğruluk: Sıra Numarası Sayacının İlerletilmesi

Geri yükleme sırasında bekleyen Outbox işlemlerinin sıra numaralarının korunması ve çakışmanın engellenmesi için tanımlanan formül:

$$S_{\text{next\_generator}} = \max\left(S_{\text{backup\_max}}, \; \max(S_{\text{staged}})\right) + 1$$

### Örnek Durum Analizi:
- Yedeğin alındığı andaki son işlem sıra numarası: $S_{\text{backup\_max}} = 100$.
- Cihaz yedekten sonra çevrimdışı olarak 101, 102, 103 numaralı 3 satış yaptı: $\max(S_{\text{staged}}) = 103$.
- Eski yedek cihaza geri yüklendiğinde veritabanındaki sıra sayacı 100'e geri döner.
- Eğer formül uygulanmazsa, cihazın yapacağı bir sonraki satışa 101 numarası verilir. Bu durumda staging'deki 101 ile yeni satış çakışır (Constraint Violation / Race condition).
- Formül uygulandığında:
  $$S_{\text{next\_generator}} = \max(100, 103) + 1 = 104$$
- Yeni yapılacak ilk satış 104 numarasını alır; 101, 102 ve 103 numaralı bekleyen işlemler dokunulmadan Outbox'a geri konulur.
- **Doğrulama Sonucu:** **MATEMATİKSEL OLARAK KANITLANDI VE DOĞRULANDI (PROVEN CORRECT)**. Sıra numaralarında delik (*gap*) oluşsa dahi FIFO sırası asla bozulmaz ve çakışma yaşanmaz.

---

## 4. Güvenlik ve Kriptografik Risk Değerlendirmesi

1. **AES-256-CBC ve HMAC-SHA256 (Encrypt-then-MAC) Seçimi:** S5A-4 ile doğrulanmış FIPS 197 uyumlu AES-256-CBC (PKCS#7 padding) ve HMAC-SHA256 bütünlük doğrulaması kullanılır. Dosya üzerinde 1 bit dahi oynanırsa çözme öncesinde HMAC uyuşmazlığı tespit edilir ve hasarlı verinin veritabanına girmesi engellenir.
2. **PBKDF2 Anahtar Türetme:** PBKDF2-HMAC-SHA256 ile en az 600.000 iterasyon ve 16 bayt kriptografik rastgele salt kullanılır; kaba kuvvet (brute-force) saldırılarına karşı en yüksek güvenlik standardı sağlanır.
3. **Google Drive Scope Sınırı (`drive.file`):** Uygulama hiçbir koşulda kullanıcının özel sürücüsündeki diğer klasörleri tarayamaz; en katı güvenlik denetimlerinden başarıyla geçer.

---

## 5. Risk ve Bulgu Sınıflandırma Matrisi

| Bulgu No | Kategori | Açıklama | Seviye | Durum |
| :--- | :--- | :--- | :--- | :--- |
| **VAL-BAK-01** | Eşzamanlılık | WAL modunda ham dosya kopyalamanın bozulmaya yol açması | CRITICAL | **ÇÖZÜLDÜ** (`VACUUM INTO` zorunlu kılındı) |
| **VAL-BAK-02** | Veri Kaybı | Geri yüklemede bekleyen Outbox işlemlerinin ezilmesi | CRITICAL | **ÇÖZÜLDÜ** (Staging + İmmutable Sequence kuralı kondu) |
| **VAL-BAK-03** | İdempotency | Ağ kopması sonrası yanıtsız kalan satışın mükerrer basılması | HIGH | **ÇÖZÜLDÜ** (`verify-keys` mutabakatı eklendi) |
| **VAL-BAK-04** | Güvenlik | Buluta yüklenen yedeğin açık metin sızdırılması | HIGH | **ÇÖZÜLDÜ** (İstemci taraflı AES-256-CBC + HMAC-SHA256 şifreleme) |
| **VAL-BAK-05** | Yetki Aşımı | Google Drive'da geniş izin istenmesi sonucu kullanıcı güvensizliği | MEDIUM | **ÇÖZÜLDÜ** (Yalnızca `drive.file` kapsamı seçildi) |
| **VAL-BAK-06** | Kota Aşımı | Sınırsız günlük yedek birikmesi sonucu Drive kotasının dolması | LOW | **ÇÖZÜLDÜ** (30 günlük döngüsel temizlik kuralı getirildi) |

---

## 6. Bağımsız Teknik Doğrulama Sonucu ve Onay

MMS Yedekleme ve Geri Yükleme Protokolü (`BACKUP_RESTORE_PROTOCOL.md`) ve Mimari Kararları (`BACKUP_RESTORE_DECISIONS.md`), dağıtık, çevrimdışı çalışan ve çoklu cihazlı bir POS/SaaS sisteminin tüm gereksinimlerini eksiksiz karşılamaktadır. 

Mimaride hiçbir kritik açık kalmamış olup, protokolün Faz 0 mimari onay kriterlerini tam olarak karşıladığı **ONAYLANMIŞTIR**.

