# PHASE_B5_PILOT_ACCEPTANCE_REPORT.md — Faz 8 (`Hat B / Faz B-5`) Fiziksel Saha & Pilot Kabul Raporu

- **Faz:** Faz 8 — Fiziksel Pilot Kabul Hazırlığı (`BK-PAT-01…BK-PAT-18` ve Saha Kapısı)
- **Genel Durum:** **`BLOCKED`** (**`OWNER ACTION REQUIRED`** — Gerçek Windows Service SCM, NTFS ACL, canlı Google Cloud OAuth/Drive hesapları, ikinci temiz Windows PC ve fiziksel Android cihaz gereklidir)
- **Zorunlu Etiket İlkesi:** Bu rapordaki hiçbir fiziksel/saha maddesi otomatik mock/loopback testlerine dayanarak `PHYSICALLY_VERIFIED` işaretlenmemiştir.
- **23 Kasım 2026 güncellemesi:** Durum değişmedi — `BK-PAT-01…18` hâlâ **`BLOCKED / NOT RUN`**. Yeni ön koşul: **`B3` Portable Recovery Password** (tanımlanmadan Hub yedeği alınmaz). Fiziksel test sırası ve Owner adımları [`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`](../../PHYSICAL_ACCEPTANCE_TEST_PLAN.md) "Hat B" bölümünde; yazılım doğrulama sonuçları [`FINAL_PILOT_READINESS_REPORT.md`](../FINAL_PILOT_READINESS_REPORT.md).

---

## 1. Hat B Fiziksel Kabul Test Matrisi (`BK-PAT-01…BK-PAT-18`)

Kaynak şartname: [`BACKUP_RESTORE_ACCEPTANCE_TESTS_V1_1.md`](file:///c:/Users/halil/Github/market-pos/docs/testing/BACKUP_RESTORE_ACCEPTANCE_TESTS_V1_1.md) §4.2. (Hat A'nın mevcut [`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`](file:///c:/Users/halil/Github/market-pos/PHYSICAL_ACCEPTANCE_TEST_PLAN.md) içindeki `PAT-01…PAT-18` kimlik uzayı korunmuştur ve çakıştırılmamıştır.)

| Test ID | Kapsam | Ön Koşullar / Engelleyiciler | Durum |
|---|---|---|---|
| **`BK-PAT-01`** | Windows UI PKCE → `MarketMMSService` (`LocalService`) Token Devri ve Reboot Kalıcılığı (`backup_drive_oauth.dpapi` + `icacls`) | `MarketMMSService` kurulumu (`D1`), TLS (`B2`), Google OAuth (`C1/C2`), reboot testi | **`BLOCKED`** |
| **`BK-PAT-02`** | İlk Etkinleştirmede Başlangıç Yedeği (`INITIAL_ENABLE`) ve Gerçek Drive Upload/Download (`MMSBAK02`) | `BK-PAT-01` + gerçek Google Drive (`TEST_ONLY`/pilot hesabı) | **`BLOCKED`** |
| **`BK-PAT-03`** | Katılımsız Günlük `00.00` Zamanlama ve Ertesi Sabah `CATCH_UP` Gözlemi *(Sistem Saati Değiştirilmez)* | 2 ardışık doğal gece gözlem penceresi | **`BLOCKED`** |
| **`BK-PAT-04`** | Gerçek Ağ Kesintisi Sırasında 4 MB Chunked Resumable Upload & Kaldığı Yerden Devam (`HTTP 308`) | `> 12 MB` test paketi + gerçek ağ kesintisi + gerçek Drive | **`BLOCKED`** |
| **`BK-PAT-05`** | Gerçek Google Drive Kota Dolu (`403 storageQuotaExceeded`) & OAuth Yetki İptali (`FAILED_AUTH`) | Dolu izole test Drive hesabı + Google Güvenlik izin kaldırma | **`BLOCKED`** |
| **`BK-PAT-06`** | Disk Dolu (`ERR_INSUFFICIENT_DISK_SPACE` / `ERR_DISK_FULL`) Gerçek Windows Birimi Testi | Küçük test VHD / sınırlı birim | **`BLOCKED`** |
| **`BK-PAT-07`** | Aktif Upload Sırasında `MarketMMSService` Graceful Shutdown (`< 12s`) & Aynı `backup_id` Devamı | Kurulmuş `MarketMMSService` + `Stop-Service` / `Start-Service` | **`BLOCKED`** |
| **`BK-PAT-08`** | Upload/Encrypt Ortasında Güç Kesintisi / Süreç Çökmesi (PBKDF2 600k Tekrarsız Crash Recovery) | `MarketMMSService` + WinSW crash recovery gözlemi | **`BLOCKED`** |
| **`BK-PAT-09`** | Hub Geri Yükleme Sırasında Eşzamanlı Backup/Sync Çakışma Koruması (`409` / Outbox koruma) | Fiziksel Windows Hub + Android `OWNER` cihazı | **`BLOCKED`** |
| **`BK-PAT-10`** | İzole `TEST_ONLY` Drive Klasöründe 30 Günlük + 12 Takvim Ayı Retention Doğrulaması *(Saat Değiştirilmez)* | İzole `TEST_ONLY` Google Drive klasörü | **`BLOCKED`** |
| **`BK-PAT-11`** | İzole `TEST_ONLY` Drive Klasöründe Son Geçerli Yedek Koruması (*>= 1 `COMPLETED_UPLOADED`*) | İzole `TEST_ONLY` Google Drive klasörü | **`BLOCKED`** |
| **`BK-PAT-12`** | Yanlış Portable Recovery Password ile Fiziksel Restore Reddi + Şifreli Safety Snapshot Kontrolü | Fiziksel Windows Hub + canlı mağaza DB yedeği | **`BLOCKED`** |
| **`BK-PAT-13`** | İkinci Temiz Windows PC'de Sıfırdan Hub Restore (`MMSBAK02`) + Toplu Cihaz Re-pairing (`OV-03`/`OV-04`) | İkinci temiz Windows PC / VM + fiziksel Android cihaz | **`BLOCKED`** |
| **`BK-PAT-14`** | Hub Restore Sonrası Çevrimdışı Android Satışlarının Kayıpsız `OV-03` Outbox Uzlaştırması | Fiziksel Windows Hub + fiziksel Android cihaz | **`BLOCKED`** |
| **`BK-PAT-15`** | Android Bakım / Yönetim UI Fiziksel Doğrulaması (`OWNER` uzaktan tetik vs `CASHIER` 403/kısıt banner'ı) | Fiziksel Windows Hub + `OWNER` & `CASHIER` Android telefonları | **`BLOCKED`** |
| **`BK-PAT-16`** | Android Eski Yerel (`Legacy Yerel Cihaz Yedeği (S5A-4)`) `.mmsbak` Dosyalarının Korunması ve İzolasyonu | Önceden yerel `.mmsbak` bulunduran fiziksel Android cihaz | **`BLOCKED`** |
| **`BK-PAT-17`** | Pre-Restore Şifreli Safety Snapshot'tan Geri Dönüş (Yanlış Yedek Restore'unu Geri Alma) | Fiziksel Windows Hub PC | **`BLOCKED`** |
| **`BK-PAT-18`** | Katılımsız (`Unattended`, Kullanıcı Oturumu Kapalı) Windows Service Uzun Süreli Kararlılık & Drive Upload | Windows Hub PC login ekranında gece gözlemi | **`BLOCKED`** |

---

## 2. Eşlik Eden Owner Ön Koşulları & Hat A Saha Blokajları

Ayrıntılı yönergeler için [`OWNER_ACTION_CHECKLIST.md`](file:///c:/Users/halil/Github/market-pos/OWNER_ACTION_CHECKLIST.md) ve [`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`](file:///c:/Users/halil/Github/market-pos/PHYSICAL_ACCEPTANCE_TEST_PLAN.md) belgelerine uyulur:

| Grup | Kapsam | Durum |
|---|---|---|
| **`D1–D4` Ortam Temizliği** | `MarketMmsSpike01` servisinin kaldırılması (yalnızca Owner izniyle), manuel test token/DB/şifresiz kopya temizliği | **`BLOCKED`** |
| **`B2` Hub Üretim TLS Sertifikaları** | OpenSSL `ca.crt`, `server.crt` (`IP:127.0.0.1` + LAN IP SAN), `server.key`; `ca.key` Hub dışında kalır | **`BLOCKED`** |
| **`B1` Android Üretim İmza Anahtarı** | `.jks` + `android/key.properties` ve Release APK derlemesi | **`BLOCKED`** |
| **`C1/C2` Google Cloud OAuth** | `"In production"` OAuth ekranı, yalnız `drive.file` kapsamı, Desktop Client ID (Hub backup + canlı sync) & Android/Web Client ID | **`BLOCKED`** |
| **`PAT-01…PAT-18` (Hat A)** | Kamera barkod tarama, USB HID okuyucu, LAN/QR eşleştirme, `MarketMMSService` SCM/ACL (`setup_service_acls.ps1`), çoklu cihaz satış/stok | **`BLOCKED`** |

---

## 3. Saha Kabulünde Uyulması Zorunlu Koruma Kuralları

1. **`MarketMmsSpike01` İzolasyonu:** `D1` adımı Owner tarafından bilinçli olarak yürütülene dek bu servise dokunulmaz.
2. **Sistem Saati Sabitliği:** `BK-PAT-03`, `BK-PAT-10`, `BK-PAT-11` sırasında Windows veya Android sistem saati ASLA ileri/geri alınmaz.
3. **`TEST_ONLY` Klasör Ayrımı:** `BK-PAT-10` ve `BK-PAT-11` retention temizlik testleri yalnızca izole `TEST_ONLY` Google Drive klasöründe çalıştırılır; gerçek mağaza yedekleri ASLA silinmez.
4. **Sır Hijyeni:** `pilot_kanit/` kanıt ekran görüntüsü ve loglarında OAuth token, `refresh_token`, `pepper`, `admin_secret`, `server.key` veya Portable Recovery Password açık metin olarak yer alamaz.
5. **Tek Adım Saha Protokolü (`GEMINI.md` §6.8):** Fiziksel kabul testleri proje sahibine tek seferde bir test adımı olarak verilir ve gerçek sonuç bildirilmeden başarılı kabul edilmez.
