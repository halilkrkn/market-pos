# MARKET MMS — İkinci PC Pilot Kabul Test Planı (§15.5)

*Tarih: 25 Kasım 2026 · Kural: Gerçek fiziksel pilot donanımında yürütülmeden hiçbir madde `PASS` olarak işaretlenemez. Şu an tüm maddeler **`NOT RUN / PENDING PHYSICAL TEST`** durumundadır.*

---

## 1. Pilot Kabul Kriterleri Matrisi (15 Zorunlu Kriter)

| # | Kriter | Ön Koşul & Adımlar | Beklenen Doğrulama Kanıtı | Durum |
|---|---|---|---|---|
| **1** | **Windows MSI Kurulumu** | Pilot PC ön kontrolü (§15.3) geçilir; SHA-256 doğrulanır; `msiexec /i MarketMMS-Setup-1.0.0-x64.msi /l*v install.log` çalıştırılır. | `msi_install.log` çıkış kodu `0`; `%ProgramFiles%\MarketMMS\client\market_pos.exe` ve `%ProgramData%\MarketMMS\` oluşur. | `NOT RUN / PENDING PHYSICAL TEST` |
| **2** | **Windows Hub Service Başlangıcı** | `ca.crt`, `server.crt`, `server.key` yerleştirilir; ACL uygulanır; `MarketMMSService.exe start` çalıştırılır. | `Get-Service MarketMMSService` → `Running`; HTTPS `https://127.0.0.1:8945/health` (CA pinned) `200 UP`; PC yeniden başlatıldığında servis otomatik açılır. | `NOT RUN / PENDING PHYSICAL TEST` |
| **3** | **Windows Client Başlangıcı** | Masaüstü kısayolundan `market_pos.exe` açılır; kurulum sihirbazı tamamlanır; ilk OWNER bootstrap yapılır. | Uygulama açılır, `%LOCALAPPDATA%\MarketMMS\client_local.db` oluşur, Hub bağlantısı `Çevrimiçi` ve rol `OWNER` görünür. | `NOT RUN / PENDING PHYSICAL TEST` |
| **4** | **System Tray ve Otomatik Başlatma** | (a) Küçült ve X ile tepsiye gizle; (b) tepsi simgesine çift tıkla aç; (c) sağ tık menüsündeki Hub/Sync/Yedek durumlarını doğrula; (d) Ayarlar'dan Otomatik Başlat'ı aç ve Windows oturumunu yeniden başlat; (e) tepsiden **Uygulamadan Çık** seç. | X/küçült uygulamayı kapatmaz; çift tık öne getirir; oturum açılışında client açılır (kapatılınca açılmaz); kontrollü çıkışta `market_pos.exe` temiz kapanır ve bekleyen Outbox korunur. | `NOT RUN / PENDING PHYSICAL TEST` |
| **5** | **Android APK Kurulumu** | İmzalı üretim `market_mms_v1.0.0-b1.apk` SHA-256 doğrulamasıyla Android 7.0+ cihaza kurulur. | Uygulama açılır; `adb shell dumpsys package com.marketmms.market_pos` üzerinde `versionName=1.0.0` ve `usesCleartextTraffic=false` doğrulanır. | `NOT RUN / PENDING PHYSICAL TEST` |
| **6** | **Android Cihaz Eşleştirme** | Windows ekranında QR üretilir; Android kamera ile QR taranır; Windows'tan onaylanır. | Android `TLS Pin Aktif (B-2)`, `Keystore Hazır (B-3)` ve Hub `Bağlı` durumuna geçer; düz HTTP denemesi engellenir. | `NOT RUN / PENDING PHYSICAL TEST` |
| **7** | **Ürün ve Kategori Yönetimi** | Windows'tan 2 ürün + ikincil barkod + kategori eklenir; Android'den 1 ürün eklenir. | İki cihaz da ürünleri ve fiyatları (kuruş bazlı, 2 ondalık TL) eksiksiz senkronize eder. | `NOT RUN / PENDING PHYSICAL TEST` |
| **8** | **Barkodla Satış** | Windows'ta USB HID barkod okuyucuyla, Android'de kamera tarayıcıyla sepete ürün eklenip Nakit + Kart satış tamamlanır. | Snapshot fiyat/ad `sale_items`'a yazılır; para üstü ve toplam tutar Half-Up kuruş kuralına uyar. | `NOT RUN / PENDING PHYSICAL TEST` |
| **9** | **Stok Güncelleme** | Stok girişi (`STOCK_RECEIPT`) + satış + kısmi iade (`SELLABLE` vs `DAMAGED`) + tam iptal uygulanır. | Stok bakiyesi her iki cihazda ve Hub'da aynı atomik sonuca ulaşır; satış kaydı asla silinmez. | `NOT RUN / PENDING PHYSICAL TEST` |
| **10** | **Offline Satış** | Android Wi-Fi kapatılır (veya Hub servisi durdurulur); Windows ve Android'de ayrı ayrı satış ve stok işlemi yapılır. | Her iki cihaz da kesintisiz satış yapar; işlemler yerel Outbox'ta `PENDING` olarak birikir. | `NOT RUN / PENDING PHYSICAL TEST` |
| **11** | **Yeniden Bağlantı ve Senkronizasyon** | Wi-Fi / Hub servisi tekrar açılır; otomatik reconnect + FIFO Outbox aktarımı gözlenir. | Outbox `0` bekleyene düşer; Hub `processed_operations` üzerinde `client_seq` boşluksuz ilerler; mükerrer kayıt oluşmaz. | `NOT RUN / PENDING PHYSICAL TEST` |
| **12** | **Çoklu Cihaz Veri Tutarlılığı** | Windows + Android üzerinde tüm ürün stokları, satış geçmişi ve Dashboard net ciro tutarları karşılaştırılır. | İptal/iade sonrası net ciro, stok ve satış sayıları iki cihazda birebir eşleşir. | `NOT RUN / PENDING PHYSICAL TEST` |
| **13** | **Backup Oluşturma** | Hub Portable Recovery Password (12+ krk) kaydedilir; manuel Hub yedeği (`MMSBAK02`) + istemci yerel yedeği (`MMSBAK01`) alınır; (Drive bağlıysa Drive yüklemesi) doğrulanır. | `COMPLETED_UPLOADED` veya yerel şifreli `.mmsbak` dosyası oluşur; yanlış parola reddedilir. | `NOT RUN / PENDING PHYSICAL TEST` |
| **14** | **Restore ve Reconciliation** | Test amaçlı yeni bir işlem eklenir, ardından önceki şifreli Hub yedeğinden geri yükleme (`restore`) çalıştırılır; istemci cihazların `restore_epoch` değişimi sonrası mutabakatı gözlenir. | `PRAGMA integrity_check` = `ok`; Hub eski duruma döner; cihazların restore sonrası kayıp `SYNCED` işlemleri güvenli biçimde uzlaştırılır / uyarılır. | `NOT RUN / PENDING PHYSICAL TEST` |
| **15** | **Güvenli Kaldırma ve Veri Koruma** | `msiexec /x` (varsayılan `PURGE_USER_DATA=0`) ile uygulama kaldırılır. | Servis ve firewall kuralları kalkar; `HKCU\...\Run\MarketMMSClient` temizlenir; `C:\ProgramData\MarketMMS\data\market_master.db` ve `%LOCALAPPDATA%\MarketMMS\client_local.db` **korunur**. | `NOT RUN / PENDING PHYSICAL TEST` |

---

## 2. Yürütme Protokolü

- Testler **tek adım protokolü** ile sırayla yürütülür; bir adım başarısız olursa sonraki adıma geçilmez, kök neden incelenir.
- Her test adımında: tarih/saat, cihaz kimliği, ekran/log görüntüsü ve (varsa) `backup_id` / `sale_id` kanıt olarak kaydedilir.
- Kriter `1–15` tamamı **`PASS`** olmadan pilot ortamı "canlıya hazır" kabul edilmez.
