# MARKET MMS — SPIKE-01 / Faz S-1 API Security Hardening Raporu

**Belge Türü:** Güvenlik Sıkılaştırma ve Doğrulama Raporu  
**Tarih:** 5 Kasım 2026  
**Aktif Aşama:** Faz S-1 (API Security Hardening)  
**Referans Plan:** [`test_spikes/spike_01_backend/SECURITY_REMEDIATION_PLAN.md`](./SECURITY_REMEDIATION_PLAN.md)  
**Durum:** Başarıyla Tamamlandı (27/27 Test Başarılı, `dart analyze` 0 Hata)

---

## 1. Yönetici Özeti

Bu çalışma kapsamında, `SECURITY_AUDIT_REPORT.md` raporunda tespit edilen ve Faz S-1 kapsamına giren tüm API uç nokta güvenlik açıkları Test-Driven Development (TDD) metodolojisiyle kapatılmış ve doğrulanmıştır.

Mevcut SPIKE-01 mimarisi (Dart AOT + Shelf + Drift SQLite tekil yazıcı kuyruğu, idempotency, WAL kurtarma ve graceful shutdown) korunmuş, hiçbir harici paket bağımlılığı eklenmeden yerel Dart ve Shelf altyapısı kullanılmıştır.

---

## 2. Kapatılan Güvenlik Açıkları ve Uygulanan Çözümler

| Güvenlik Açığı / Tehdit | Önceki Durum (Savunmasız) | S-1 Sonrası Durum (Sıkılaştırılmış) | Çözüm Yöntemi |
| :--- | :--- | :--- | :--- |
| **1. Yetkisiz Cihaz Kaydı (SEC-01 Ön Tedbir)** | `/api/v1/devices/register` rotası `publicPaths` içindeydi; LAN'daki herhangi bir istemci token üretip yetkili cihaz kaydedebiliyordu. | Endpoint `publicPaths` listesinden çıkarıldı. Artık yetkisiz istekler doğrudan `401 Unauthorized` ile reddedilir. | `createAuthMiddleware` içinde public path koruması. (Faz S-4'te yerini TLS tabanlı PIN/OTP handshake'e bırakacaktır). |
| **2. Backup SQL Injection & Arbitrary File Overwrite (SEC-02)** | İstemciden gelen `target_path` doğrudan SQLite `VACUUM INTO '$targetPath'` komutuna veriliyor ve hedef dosya varsa `deleteSync()` ile siliniyordu. | `target_path` parametresi dosya yazımı için reddedildi. Şüpheli SQL injection karakterleri (`'`, `;`, `--`, null byte) anında `400 Bad Request` alır. Yedek dosyası sunucuda güvenli zaman damgasıyla (`mms_backup_YYYYMMDD_HHMMSS.db`) oluşturulur. | Sunucu tarafı path sanitizasyonu ve sabit korumalı dizin (`backupDirectory`). |
| **3. Admin Shutdown Uç Noktası Yetkisizliği (SEC-04)** | LAN üzerindeki herhangi bir Bearer token sahibi `/api/v1/admin/shutdown` çağırarak servisi kapatabiliyordu. | Çift kilitli koruma (Dual-Guard): 1) IPv4 (`127.0.0.1`) ve IPv6 (`::1`, `0:0:0:0:0:0:0:1`) soket seviyesinde loopback denetimi. 2) Zorunlu admin yetkilendirmesi. Uzak IP'ler `403 Forbidden`, yetkisizler `401` alır. | `shelf.io.connection_info` üzerinden gerçek soket IP kontrolü. |
| **4. HTTP 500 Hata Mesajlarında Bilgi Sızıntısı (SEC-07)** | Hata oluştuğunda `e.toString()` ile SQLite hata mesajları, tablo adları, dosya yolları ve dahili exception detayları istemciye dönülüyordu. | İstemciye yalnızca `{"error": "TRANSACTION_FAILED", "code": "ERR_TRANSACTION_FAILED", "message": "İşlem sunucu hatası nedeniyle tamamlanamadı."}` dönülür. Stack trace veya dosya yolu kesinlikle sızmaz. | Generic JSON hata maskelemesi ve sunucu tarafı güvenli stderr loglaması. |
| **5. İstek Gövdesi Boyut Sınırı (2 MB DoS Koruması) (SEC-09)** | İstek gövdesi boyutu sınırsızdı; bellek şişirme veya DoS saldırısına açıktı. | İki katmanlı denetim: 1) `Content-Length > 2 MB` olduğunda gövde okunmadan anında `413 Payload Too Large`. 2) Chunked stream aktarımlarında stream sayaç ile okunur; 2 MB aşıldığı milisaniyede stream kesilir ve bağlantı sonlandırılır. | `createBodyLimitMiddleware` (Stream transformer ile anında TCP abort). |
| **6. CORS Wildcard Kullanımı (SEC-08)** | `corsHeaders()` varsayılan olarak `Access-Control-Allow-Origin: *` başlığı dönüyordu. | Wildcard `*` tamamen kaldırıldı. Yalnızca `127.0.0.1` ve `localhost` origin'lerine izin verilir; harici origin'lere hiçbir CORS başlığı eklenmez. | `createSecureCorsMiddleware` ile origin denetimi. |
| **7. Health Endpoint Sürüm Bilgisi İfşası (SEC-12)** | `/health` çıktısında gerçek SQLite sürüm numarası (`3.45.1`) dönülüyordu. | Sürüm numarası `'masked'` olarak gizlendi; saldırganların sürüm taraması yapması engellendi. | `sqlite_version: 'masked'` (Mevcut test uyumluluğu korundu). |
| **8. Hassas Veri Loglama Hijyeni** | Token ve PIN loglanma riski. | Kod tabanı denetlendi; hiçbir konsol veya hata loguna raw token veya PIN yazılmadığı garanti altına alındı. | Log filtreleme ve maskeleme standartları. |

---

## 3. Değiştirilen ve Eklenen Dosyalar

1. **`lib/security/body_limit_middleware.dart` (YENİ):**  
   Request body boyutunu hem `Content-Length` hem de stream okuma sırasında sınırlandıran Shelf Middleware'i. 2 MB üzeri aktarımlarda `PayloadTooLargeException` fırlatarak TCP bağlantısını anında sonlandırır.
2. **`lib/security/secure_cors_middleware.dart` (YENİ):**  
   Wildcard (`*`) içermeyen, yalnızca yerel loopback origin'lerine izin veren CORS middleware'i.
3. **`bin/server.dart` (GÜNCELLENDİ):**  
   - `/api/v1/devices/register` public yollardan çıkarıldı.
   - `/api/v1/backup/snapshot` client path kullanımından arındırıldı, SQLi karakter filtresi ve sunucu tarafı path üretimi eklendi.
   - `/api/v1/admin/shutdown` IPv4/IPv6 loopback ve auth kontrolleriyle çift kilitli hale getirildi.
   - `/api/v1/sales` catch bloğunda hata maskelemesi yapıldı.
   - `/health` çıktısındaki sürüm bilgisi maskelendi.
   - Middleware pipeline'ına `createSecureCorsMiddleware` ve `createBodyLimitMiddleware` dahil edildi.
4. **`test/s1_api_hardening_test.dart` (YENİ):**  
   Faz S-1 için TDD yaklaşımıyla yazılan 10 adet güvenlik regresyon testi.
5. **`test/spike_test.dart` (GÜNCELLENDİ):**  
   Grup 5 yedekleme testi, sunucunun ürettiği `backup_path` yolunu dinamik alacak şekilde güncellendi.

---

## 4. Test Sonuçları ve Doğrulama Matrisi

Tüm test paketleri `dart test` komutuyla çalıştırılmış ve **27 testin tamamı %100 başarıyla** geçmiştir:

```
00:09 +27: All tests passed!
```

### 4.1. S-1 Güvenlik Test Paketi (`test/s1_api_hardening_test.dart`):
- [x] **Test 1:** Cihaz kayıt endpoint'i yetkisiz erişime KAPALI olmalıdır (`401 Unauthorized`).
- [x] **Test 2:** Backup endpoint'inde SQL Injection denemesi engellenmelidir (`400 Bad Request / ERR_MALICIOUS_INPUT`).
- [x] **Test 3:** Backup endpoint'i keyfi dosya yolu kabul etmemeli, sunucu güvenli dizinde üretmelidir.
- [x] **Test 4:** HTTP 500 hata yanıtlarında stack trace, dosya yolu veya dahili hata detayı sızmamalıdır.
- [x] **Test 5:** Request body boyutu Content-Length > 2 MB olduğunda `413 Payload Too Large` dönmelidir.
- [x] **Test 6:** Request body boyutu stream okuma sırasında 2 MB aşıldığında stream anında kesilmeli ve bağlantı sonlandırılmalıdır.
- [x] **Test 7:** CORS başlıklarında wildcard (`*`) bulunmamalıdır.
- [x] **Test 8:** Health endpoint'inde SQLite sürüm bilgisi maskelenmiş olmalıdır.
- [x] **Test 9:** Admin shutdown endpoint'ine yetkisiz (token olmadan) loopback isteği `401 Unauthorized` dönmelidir.
- [x] **Test 10:** Admin shutdown endpoint'i yetkili loopback isteğiyle başarıyla tetiklenebilmelidir (`200 OK`).

### 4.2. Mevcut SPIKE-01 Regresyon Paketleri:
- [x] `test/spike_test.dart`: 11/11 Test Başarılı (Atomik Satış, Stok Düşümü, Idempotency, Rollback, Snapshot, Normal ve Stres Yük Testleri).
- [x] `test/lifecycle_drain_test.dart`: 1/1 Test Başarılı (WriteQueue Drain ve HTTP 503 Draining).
- [x] `test/shutdown_regression_test.dart`: 3/3 Test Başarılı (Windows Service Graceful Shutdown < 1.5 sn, Stop/Start Döngüleri, SQLite Bütünlüğü).
- [x] `test/process_crash_test.dart`: 2/2 Test Başarılı (Gerçek OS `taskkill /F /T` ve WAL Otomatik Recovery).

### 4.3. Statik Analiz:
```bash
dart analyze
# Çıktı: Analyzing spike_01_backend... No issues found!
```

---

## 5. Kalan Riskler ve Sonraki Fazlar İçin Notlar

1. **Cihaz Kayıt Güvenliği (S-4'e Devir):**  
   Faz S-1 ile `/api/v1/devices/register` açık olmaktan çıkarılmış ve yetkilendirme arkasına alınmıştır. Ancak terminallerin ilk kurulumda işletme sahibi ekranından PIN/OTP ve optik QR güven çapası ile eşleştirilmesi protokolü **Faz S-4 (Secure Device Pairing)** kapsamında tamamlanacaktır.
2. **Açık Metin Token Saklama (S-2'ye Devir):**  
   Mevcut SQLite şemasında token'lar halen açık metin sütunundadır. Bu durum **Faz S-2 (Device Token Security)** ile `token_hash` (SHA-256) ve salt/pepper mimarisine taşınacaktır.
3. **LAN İletişim Şifrelemesi (S-3'e Devir):**  
   HTTP katmanı sıkılaştırılmıştır; ancak Wi-Fi üzerindeki verilerin dinlenmesini (sniffing) önleyecek yerel Root CA ve TLS 1.3 altyapısı **Faz S-3 (LAN TLS Security)** ile kurulacaktır.
4. **İşletim Sistemi Servis Hesabı (S-5'e Devir):**  
   Windows servisi henüz `LocalSystem` hesabındadır; `NT AUTHORITY\LocalService` hesabına geçiş ve NTFS ACL kilitlenmesi **Faz S-5 (Windows Security)** aşamasında uygulanacaktır.

---

## 6. Sonuç

Faz S-1 (API Security Hardening) hedefleri eksiksiz karşılanmış, sıfır kodlama uyarısı (`No issues found!`) ve %100 test başarısıyla tamamlanmıştır.

Faz S-2 (Device Token Security) geliştirmesine geçilmesi için kullanıcı onayı beklenmektedir.

