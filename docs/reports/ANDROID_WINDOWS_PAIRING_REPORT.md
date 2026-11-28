# ANDROID & WINDOWS PAIRING REPORT

- **Durum:** `PASS (Kriptografik eşleştirme, CA bootstrap ve TLS pin doğrulaması testlerle doğrulandı)` / `PENDING (Fiziksel Android kamera QR tarama testi henüz yapılmadı)`
- **Tarih:** 2026-11-28
- **Kapsam:** Windows Owner loopback bootstrap, Kök CA indir & sabitle akışı, Android ECDSA P-256 challenge/poll/ACK eşleştirmesi

## Yapılan değişiklikler

1. **Loopback HTTPS Admin İstemci Sabitlemesi:**
   - [pairing_approval_panel.dart](file:///c:/Users/halil/Github/market-pos/lib/features/security/presentation/widgets/pairing_approval_panel.dart): `hubPairingAdminClientProvider` her zaman `https://127.0.0.1:<port>` kullanır; eski `http://` veya şemasız URL kalıntısı HTTP'ye düşüşe yol açamaz.
2. **TLS Kök CA İndir ve Sabitle Akışı (`ALT-BOOT-2` + X.509 Ön Doğrulama):**
   - [device_pairing_client.dart](file:///c:/Users/halil/Github/market-pos/lib/features/security/data/device_pairing_client.dart): `fetchAndVerifyRootCaCert(...)` eklendi (`GET /api/v1/pairing/ca-cert`, `MmsX509PreValidator.validateRootCaDer`, `SHA-256` parmak izi denetimi ve sabitlenen sertifika ile sıkı `MmsPinnedTlsClientFactory` `/health` doğrulaması).
   - [device_security_card.dart](file:///c:/Users/halil/Github/market-pos/lib/features/security/presentation/widgets/device_security_card.dart): `_saveTlsPin` içinde parmak izi değiştiğinde uyumsuz eski `pinnedCaPem` temizlenir; `_bootstrapRootCaAndPin()` ve `Key('bootstrap_ca_pin_button')` (`'Kök CA İndir ve Sabitle'`) eklendi.
3. **Güvenlik Sınırlarının Korunması:**
   - Emekli `/api/v1/devices/register` kapalı kaldı (kimliksiz `401`, yetkili `404 ERR_ENDPOINT_RETIRED`).
   - TLS doğrulaması veya Android `usesCleartextTraffic` gevşetilmedi.

## Değiştirilen dosyalar

- [pairing_approval_panel.dart](file:///c:/Users/halil/Github/market-pos/lib/features/security/presentation/widgets/pairing_approval_panel.dart)
- [device_pairing_client.dart](file:///c:/Users/halil/Github/market-pos/lib/features/security/data/device_pairing_client.dart)
- [device_security_card.dart](file:///c:/Users/halil/Github/market-pos/lib/features/security/presentation/widgets/device_security_card.dart)
- Testler: [connectivity_recovery_tls_pairing_test.dart](file:///c:/Users/halil/Github/market-pos/test/features/security/connectivity_recovery_tls_pairing_test.dart), [stage6_live_tls_e2e_bidirectional_sync_test.dart](file:///c:/Users/halil/Github/market-pos/test_spikes/spike_01_backend/test/stage6_live_tls_e2e_bidirectional_sync_test.dart)

## Çalıştırılan testler

- `test_spikes\spike_01_backend\test\s4_device_pairing_test.dart` (`TC-01`..`TC-34`)
- `test_spikes\spike_01_backend\test\stage6_live_tls_e2e_bidirectional_sync_test.dart` (Windows Owner bootstrap + Android QR pairing + 5 sn challenge cooldown + ACK sonrası ham token bellek temizliği + sahte CA reddi)
- `test\features\security\connectivity_recovery_tls_pairing_test.dart`
- `test\features\security\hub_pairing_admin_client_test.dart`
- `test\features\security\pairing_approval_panel_test.dart`
- `test\features\security\pairing_qr_payload_test.dart`
- `test\features\security\pblock_1_2_client_test.dart`
- `test\features\security\stage4_windows_role_provider_rbac_test.dart`

## Test sonuçları

- `test_spikes\spike_01_backend` (8 süit, `task-2353`): `+108: All tests passed!`.
- Kök Flutter 14 test süiti (`task-2378`): `+102: All tests passed!`.

## Başarısız testler

- Otomatik testlerde başarısız test yok (`0` fail).

## Bilinen riskler

- `poll-challenge` ve `ack-challenge` arka uçta ortak 5 saniyelik oturum başı cooldown kuralına tabidir; istemcinin arka arkaya hızlı çağrı yapması `429` üretebilir (testlerde doğrulandı; gerçek akışta kullanıcı/poll arası süre bu eşiği doğal olarak geçer, ancak hızlı ardışık otomatik poll->ack durumunda bekleme/yeniden deneme izlenmelidir).
- Bu bilgisayarda USB ile bağlı fiziksel Android cihaz yok (`adb devices` boş).

## Fiziksel olarak doğrulanan işlemler

- Gerçek `SpikeServer` HTTPS soketi üzerinde OpenSSL 3.5.9 TEST_ONLY sertifikası ile Windows Owner bootstrap (`mms_dt_...`), Android ECDSA P-256 eşleştirme oturumu, Owner onayı, 7 alanlı ACK doğrulaması ve güvenilmeyen CA reddi (`stage6_live_tls_e2e_bidirectional_sync_test.dart`).

## Henüz doğrulanmayan işlemler

- Fiziksel Android cihaza `MarketMMS-1.0.1-b2-android-TEST_ONLY.apk` kurulumu.
- Windows UI üzerinde `Kök CA İndir ve Sabitle` + Owner eşleştirme QR üretimi.
- Fiziksel Android kamerayla QR tarama, Windows'tan onaylama ve token kaydı.
