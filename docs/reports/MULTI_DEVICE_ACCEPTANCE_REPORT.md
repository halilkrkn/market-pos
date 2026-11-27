# MARKET MMS — Çoklu Cihaz ve Çevrimdışı Senkronizasyon Kabul Raporu (`MULTI_DEVICE_ACCEPTANCE_REPORT`)

**Tarih:** 2026-11-27

**Kapsam:** Stage J — Canlı İzole Master Hub (`https://127.0.0.1:8947`, `UDP 8948`) Üzerinde §13.1–§13.5 Uçtan Uca Çoklu İstemci (Windows + Android Simülasyon SQLite), Idempotency, Kesinti/Yeniden Başlatma ve RBAC/İptal Doğrulaması

**Durum:** İzole canlı Hub üzerinde **2/2 E2E test paketi (`STAGE_J_LIVE_EXIT=0`, `00:44 +2 All tests passed!`)** geçti; gerçek fiziksel Wi-Fi LAN üzerinden Android telefon testleri (`PAT-03..PAT-06`, `PAT-19`) konakta fiziksel cihaz bağlı olmadığı için **BLOCKED**.

---

## 1. Yürütme Özeti ve İzolasyon Kanıtı

- **Çalıştırılan Canlı E2E Testleri (`MMS_ISOLATED_LIVE_E2E=true`):**
  1. [`test/features/production/isolated_live_hub_e2e_test.dart`](file:///c:/Users/halil/Github/market-pos/test/features/production/isolated_live_hub_e2e_test.dart) — `+1 PASS` (`00:15`)
  2. [`test/features/production/stage_j_multidevice_live_e2e_test.dart`](file:///c:/Users/halil/Github/market-pos/test/features/production/stage_j_multidevice_live_e2e_test.dart) — `+1 PASS` (`00:44`, toplam `+2`, çıkış kodu `0`)
- **Statik Analiz (`dart analyze`):** `No issues found!`
- **İzole Hub Yapılandırması:** `%LOCALAPPDATA%\MarketMMS_Isolated_Test\hub\bin\mms_backend.exe` (`TCP 8947` HTTPS + `UDP 8948` discovery, `tenant_id=tenant-isolated-test`, `store_id=store-isolated-test-01`, `hub_id=MMS-HUB-ISOLATED-TEST`).
- **Temizlik Teyidi:** `stop_isolated_test_hub.ps1` sonrasında `TCP_8947_LISTEN=0`, `UDP_8948_EP=0`, `MMS_BACKEND_PROCS=0`.

---

## 2. §13.1 – §13.5 Kapsam Matrisi ve Doğrulanan Davranışlar

| Bölüm | Doğrulanan Gerçek İş Kuralları & Kanıt | Durum |
|---|---|---|
| **§13.1 Satış, Kuruş + Half-Up, İade ve Fiyat Snapshot** | - `CASH` ve `CARD` satışları uçtan uca commit edildi.<br>- Geçersiz ödeme yöntemleri (`SPLIT`, eski `'NAKIT'`) `PaymentMethod.parse` / `createOfflineSale` tarafından `ArgumentError` ile reddedildi *(Açık kapsam notu: v1.0 sözleşmesinde satır/sepet indirimi ve parçalı `SPLIT` ödeme bulunmamaktadır; yalnızca `'CASH'` ve `'CARD'` desteklenir)*.<br>- **Half-Up Kuruş Doğrulaması:** `301` kuruş/kg × `500` milli (`0.500 kg`) → `((301 * 500) + 500) ~/ 1000 = 151` kuruş doğrulandı.<br>- Fiyat artışı (`4500` → `5500` kuruş) sonrası geçmiş satış kalemi `unitPrice = 4500` olarak korundu; eski fiyatla (`expectedUnitPrice: 4500`) sepet tamamlanması `PriceChangedException` fırlattı.<br>- **İade (`SELLABLE` vs `DAMAGED`):** `4` adetlik satıştan `1` adet `SELLABLE` iade stoğu `6000 -> 7000` yaptı; `1` adet `DAMAGED` iade `FIRE_KAYIP` oluşturup satılabilir stoğu `7000`'de bıraktı; kalan `2` yerine `3` adet iade denemesi `ArgumentError` ile reddedildi; satış `totalRefundedAmount=9000`, `netAmount=9000`, `SaleDisplayStatus.partiallyRefunded` durumunda ikinci istemciye senkronlandı. | **PASS** *(İndirim/Split v1.0 sözleşmesi dışıdır)* |
| **§13.2 Ürün, Stok Girişi, İkincil Barkod, Eksi Stok & Pasif Ürün** | - Ürün oluşturma, fiyat güncelleme, `receiveStock` (`+5000` → `7000 -> 12000` `STOCK_RECEIPT` sync).<br>- `addProductBarcode` ile ikincil barkod eklendi ve Android simülasyon istemcisinden `getProductByBarcode` ile okundu; aynı barkodu başka ürüne ekleme `ArgumentError` ile reddedildi.<br>- Eksi stok politikası (`allow`): `1000` stoklu üründen `3000` satış yerel ve Hub/Android tarafında **`-2000`** olarak uzlaştırıldı.<br>- `deactivateProduct` sonrası yeni satış `StateError` ile reddedildi, geçmiş satış detayı korundu. | **PASS** |
| **§13.3 Eşzamanlı Çoklu Cihaz Senkronizasyonu, Idempotency & Replay Koruması** | - Windows ve Android istemcileri eşzamanlı (`Future.wait`) satış itip `syncProducts()` yaptığında stok `12000 - 2000 - 3000 = 7000` olarak tekilleşti *(önemli gözlem: ilk yerel ürün üretiminde oluşturucu cihaz bir kez `syncProducts()` çalıştırdığında `local_hub_synced_products` tablosu kaydolur; öncesinde `upsertProducts` yerel başlangıç stoğunu `isNeverSyncedLocal` olarak korur)*.<br>- Aynı `(device_id, client_seq)` tekrar gönderiminde `200` + `x-mms-idempotent-replay: true` döndü; tutar değiştirildiğinde (`tampered`) `409 Conflict` verdi.<br>- Aynı `X-MMS-Nonce` ile `/api/v1/devices/role` tekrarı `403 ERR_REPLAY_DETECTED` ile reddedildi. | **PASS** |
| **§13.4 Canlı Hub Durdurma → Disk DB Kapat/Aç → Hub Restart → Uzlaştırma** | - Canlı Hub (`PID 7940`) `stop_isolated_test_hub.ps1` ile durduruldu, `/health` erişilemezliği doğrulandı.<br>- Hub kapalıyken her iki istemcide offline satışlar üretildi; `winDb` ve `andRawDb` kapatıldı, `LocalDatabaseService.resetForTesting()` çağrıldı ve her iki SQLite dosyası diskten yeniden açıldı (`pending = 1` korundu).<br>- İzole Hub (`PID 9228`) `mms_backend.exe --config=hub_config.json` ile yeniden başlatıldı, `/health 200 UP` sonrası iki cihazın outbox'ı **`0` bekleyen** duruma indi ve stok `4000` ile satış geçmişleri her iki cihazda birebir eşitlendi. | **PASS** |
| **§13.5 RBAC (`OWNER` vs `CASHIER`), Yetkisiz Erişim & Cihaz İptali** | - `CASHIER` cihazı `POST /api/v1/devices/role` çağrısında `403 ERR_OWNER_ROLE_REQUIRED` aldı.<br>- Tokensız `GET /api/v1/products` `401 Unauthorized` döndü.<br>- `POST /api/v1/devices/revoke` ile iptal edilen `CASHIER` cihazın sonraki API isteği anında `401/403` ile engellendi. | **PASS** |

---

## 3. Açık Fiziksel Test Sınırı (`BLOCKED`)

- Bu rapordaki tüm senaryolar konak loopback `https://127.0.0.1:8947` / `UDP 8948` üzerinde iki ayrı FFI SQLite istemcisiyle doğrulanmıştır.
- Gerçek Wi-Fi / router alt ağı üzerinden fiziksel Android telefon(lar) ile eşzamanlı satış, UDP discovery ve QR/kamera akışları (`PAT-03`, `PAT-04`, `PAT-05`, `PAT-06`, `PAT-19`) **fiziksel Android cihaz ve mağaza LAN ortamı gerektirdiğinden `BLOCKED` (yapılmadı)** statüsündedir.
