# Sorun Giderme Kılavuzu — MARKET MMS

*Okuyucu: Market sahibi ve teknik destek. Sürüm: 21 Kasım 2026.* Tüm durumlar **Tanılama** ekranında ve kasiyer başlığındaki durum rozetinde görünür. Kasa, Hub'a bağlı olmasa da satış yapmaya devam eder; işlemler yerelde güvenle saklanır.

| Belirti (rozet / mesaj) | Olası neden | Çözüm |
|---|---|---|
| **Çevrimdışı • N** | Hub kapalı, Wi-Fi/LAN yok, IP değişti | Hub bilgisayarını ve servisi kontrol edin; Tanılama → Hub kartındaki keşif düğmesiyle yeniden arayın veya IP'yi elle girin. Satış yapmaya devam edebilirsiniz; N bekleyen işlem bağlantı gelince sırayla gönderilir. |
| **Sertifika Uyuşmuyor** / "GÜVENLİK: HUB SERTİFİKASI UYUŞMUYOR" | Bağlanılan sunucunun TLS sertifikası eşleştirmedeki parmak iziyle uyuşmuyor: yanlış Hub, Hub sertifikası CA dışında yenilendi veya ağda araya giren bir cihaz var | **Bu bir ağ arızası değildir.** Hub sertifikasını siz yenilemediyseniz ağı kontrol edin ve destek alın. Yeniledinizse cihazı yeniden eşleştirin. Bekleyen işlemler silinmez; güvenlik nedeniyle o sunucuya gönderilmez. |
| **Yetki Gerekli** / "CİHAZ YETKİSİ GEREKLİ" | Cihaz token'ı yok, iptal edildi veya süresi doldu (401/403) | Cihazı Owner onayıyla yeniden eşleştirin. Kayıtlar korunur ve eşleştirme sonrası gönderilir. |
| **N Hata** / "KALICI KUYRUK HATASI" | Hub bir işlemi kalıcı olarak reddetti (400/409); FIFO gereği sonraki işlemler bekler | Tanılama → Outbox hata ayrıntısına bakın. `ERR_CLIENT_SEQ_GAP` veya `ERR_IDEMPOTENCY_CONFLICT` görülürse destekle iletişime geçin; kayıtları silmeyin. |
| "DURAKLATILDI (BAKIM / GERİ YÜKLEME)" | Geri yükleme sürüyor | Geri yükleme bitince otomatik devam eder. |
| "Ürün kataloğu indirilemedi" | Hub'dan indirme hatası (uplink başarılı olabilir) | Hub servisinin çalıştığını kontrol edin; bir sonraki turda tekrar denenir. |
| Otomatik yedek kırmızı uyarı | Disk dolu, USB çıkarıldı, parola güvenli depoda yok | [`BACKUP_AND_RESTORE_GUIDE.md`](./BACKUP_AND_RESTORE_GUIDE.md) §6 hata kodları |
| Kamera barkodu okumuyor | Kamera izni yok, ışık yetersiz | Android Ayarlar → Uygulamalar → MARKET MMS → Kamera izni; barkodu çerçeveye ortalayın. Elle barkod girişi her zaman çalışır. |
| "Ürün bulunamadı" (satışta) | Barkod katalogda yok | Offline iken bilinmeyen barkod sepete eklenemez (OD-03). Katalog → Yeni Ürün Ekle. |
| Stok girişinde "Pasif ürüne stok girişi yapılamaz" | Ürün pasife alınmış | Katalogdan ürünü aktifleştirin. |
| "Şu anda başka bir yedekleme/geri yükleme işlemi sürüyor" | Yedek ve geri yükleme aynı anda çalışmaz (BK-LOCK) | İşlem bitince tekrar deneyin. |
| "Güncelleme manifesti güvenli değil" | Manifestteki indirme adresi HTTPS değil veya geçerli SHA-256 özeti yok | Güncelleme paketini yalnızca güvenilir kaynaktan alın; manifesti düzeltin (bkz. `docs/release/WINDOWS_HUB_RELEASE.md`). |
| Android'de Hub otomatik bulunamıyor (eşleştirilmiş cihaz) | Keşif artık eşleştirilmiş cihazlarda yalnızca HTTPS dener (ADR-018); Hub sertifikası yoksa veya router UDP yayınını engelliyorsa bağlantı kurulamaz | Hub'ın TLS ile çalıştığını ve firewall kurallarının (TCP 8945 / UDP 8946, yerel alt ağ) uygulandığını kontrol edin; gerekirse Hub adresini elle girin. |

## Hub (Windows servisi)

- Servis durumu: `Get-Service MarketMMSService`. Loglar: `%ProgramData%\MarketMMS\logs`.
- Kurulum/güncelleme betiği "GUNCELLEME BASARISIZ: Onceki surume geri donuldu" derse: önceki sürüm çalışıyordur; yeni sürümün logunu inceleyin (bkz. `docs/release/WINDOWS_HUB_RELEASE.md` §5).
- Betikler Windows PowerShell 5.1 ile çalışır (UTF-8 BOM'lu). Betik ayrıştırma hatası ("string is missing the terminator") görürseniz dosya BOM'suz kaydedilmiş demektir; depodaki sürümü kullanın.
- Sağlık: tarayıcıda `https://127.0.0.1:8945/health` → `"status":"UP"`; `backup.overdue: true` ise otomatik yedek gecikmiş demektir.
- Servis başlamıyorsa (çıkış kodu 78): `hub_config.json` geçersiz (bilinmeyen anahtar, port çakışması, sertifika yok, üretimde TLS kapalı). Mesaj servis logundadır.
- Yeni cihaz eşleştirme: Hub bilgisayarındaki Windows uygulamasında **Tanılama → Cihaz Eşleştirme Onayları**; admin secret `%ProgramData%\MarketMMS\security\admin_secret.txt` içindedir (`setup_service_acls.ps1` ile ACL korumalı; gerçek ACL doğrulaması fiziksel olarak yapılmadı).

## Destek için bilgi toplama

Tanılama → **Maskeli Tanı Raporunu Dışa Aktar**. Rapor token, parola ve gizli anahtar içermez.
