# ADR 014: Tenant/Store Başlıklarının Zorunlu Kılınması

- **Durum:** CONFIRMED (Proje sahibi onayı: 21 Kasım 2026)
- **Tarih:** 2026-11-21
- **Karar Vericiler:** Proje Sahibi (Owner); uygulama: Claude Code

---

## 1. Bağlam

Hub, mağaza verisi rotalarında `X-MMS-Tenant-Id` / `X-MMS-Store-Id` başlıklarını yalnızca gönderildiğinde doğruluyordu (`REQUIRE_TENANT_STORE_HEADERS` varsayılan `false`); istemciler başlık göndermiyordu. Görev tanımı "eksik başlıklar reddedilmeli" gerektirir.

## 2. Karar

- İstemci `HttpSyncTransport.forStore(tenantId, storeId)` ile tüm senkronizasyon isteklerinde başlıkları gönderir (kurulum yapılandırmasından).
- Hub üretim giriş noktası varsayılan olarak başlıkları zorunlu tutar (`REQUIRE_TENANT_STORE_HEADERS` yalnızca açıkça `false` ise gevşer; `--allow-missing-tenant-store-headers` bayrağı uyarı loglar). `/api/v1/stock/` mağaza verisi önekine eklendi.
- REL-01 üretim yapılandırmasında (`environment: production`) bu zorunluluk kapatılamaz.

## 3. Sonuçlar

- **Olumlu:** Yanlış mağazaya ait istemci verisi okuyamaz/yazamaz (`403 ERR_TENANT_STORE_MISMATCH`, `403 ERR_TENANT_STORE_REQUIRED`).
- **Ödünleşim:** Bu sürümden önceki APK'lar başlık göndermez ve 403 alır. Eski APK'lar 403'ü kalıcı hata sayıp kaydı `FAILED_PERMANENT` yapabilir; veri silinmez, güncel APK kurulduktan sonra Tanılama ekranından yeniden denenebilir. **Hub ve tüm istemciler birlikte güncellenmelidir.** Yeni istemci 401/403/426 yanıtlarını artık kalıcı hata saymaz.

## 4. İlgili Kod / Test

- `lib/features/sync/sync_providers.dart`, `packages/mms_client_storage/lib/src/sync/sync_transport.dart`
- `test_spikes/spike_01_backend/lib/security/auth_middleware.dart`, `bin/server.dart` (`main`)
- `test_spikes/spike_01_backend/test/stock_receipt_api_test.dart` (Tenant/store izolasyonu grubu)
