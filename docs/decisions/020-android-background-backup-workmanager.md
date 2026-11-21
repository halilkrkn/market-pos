# ADR 020: Android'de Uygulama Kapalıyken Zamanlanmış Yedek ve Keystore Hata Eşleme

- **Durum:** **DEFERRED_POST_PILOT** (`workmanager` paketi ve `MainActivity.kt` eklenti yeniden tasarımı Owner kararıyla pilot sonrasına ertelendi; ADR-020 kapsamında **Keystore fail-closed hata eşleme** ve **`minSdk 24 / Android 7.0`** doküman düzeltmesi uygulandı)
- **Tarih:** 2026-11-21
- **Karar Vericiler:** Owner (WorkManager erteleme kararı), Öneren: Claude Code / Uygulayan: Antigravity
- **İlgili:** ADR-016 (zamanlanmış yedek, Ek A.2 BK-LOCK)

---

## 1. Bağlam
İstemci zamanlayıcısı (`BackupScheduleController`) Dart `Timer` ile çalışır; Android'de yalnızca uygulama açıkken tetiklenir. Açılışta gecikmiş yedek hemen alınır. Uygulama günlerce kapalı kalırsa (ör. tablet şarjda), Hub'a ulaşmamış satışların yerel şifreli kopyası oluşmaz.

## 2. Değerlendirme Kriterleri ve Bulgular

| Kriter | Bulgu / Tasarım |
|---|---|
| Uygulama kapalıyken çalışma | Yalnızca işletim sistemi zamanlayıcısıyla mümkün: **WorkManager** (`PeriodicWorkRequest`, en az 15 dk). Flutter tarafı için `workmanager` eklentisi veya ~80 satır Kotlin + `FlutterEngine` arka plan girişi. |
| Yeniden başlatma sonrası | WorkManager işleri cihaz yeniden başlatıldığında otomatik yeniden planlar (ek `RECEIVE_BOOT_COMPLETED` gerekmez; kütüphane kendi alıcısını ekler). |
| Pil optimizasyonları | Doze/App Standby işi erteleyebilir; yedek zaman-kritik değildir. Kısıtlar: `setRequiresBatteryNotLow(true)`, `setRequiresStorageNotLow(true)`. "Pil optimizasyonunu kapat" istenmemeli (Play politikası). |
| Ağ gereksinimi | Yerel şifreli yedek için **ağ gerekmez**. Drive yüklemesi ayrı, `NetworkType.UNMETERED/CONNECTED` kısıtlı ikinci iş olarak planlanmalı. |
| **Güvenli parola erişimi (kritik)** | Parola Android Keystore'da; erişim `MainActivity.configureFlutterEngine` içinde kayıtlı `MethodChannel` ile. **Arka plan `FlutterEngine`'inde bu kanal yoktur** → işçi parolayı okuyamaz. Çözüm: Keystore kanal kodu `MainActivity`'den bağımsız bir `FlutterPlugin` sınıfına taşınmalı ve hem ön plan hem arka plan motoruna kaydedilmeli. Bu yerel kod değişikliği fiziksel cihazda test edilmelidir. |
| Aynı anda birden fazla yedek | **Çözüldü (A):** `BackupOperationLock` dosya kilidi isolate/süreç sınırını aşar; ön plan zamanlayıcısı ve arka plan işçisi aynı kilidi kullanır. WorkManager tarafında `enqueueUniquePeriodicWork(..., KEEP)`. |
| Restore sırasında yedeğin durması | **Çözüldü (A):** Restore kilidi tutar; işçi `ERR_BACKUP_OPERATION_BUSY` alır ve zamanlanmış tur hata kaydetmeden atlanır. |
| Başarısız yedek sonrası retry | Mevcut `BackupSchedulePolicy` (30 dk bekleme) + WorkManager `Result.retry()` (üstel geri çekilme). Durum aynı `backup_schedule_state.json`'a yazılır. |
| Kullanıcıya durum/hata | Mevcut yedek ekranı aynı durum dosyasını okur (son başarı, hata kodu, geçmiş). İsteğe bağlı: hata durumunda yerel bildirim (ek izin `POST_NOTIFICATIONS`, API 33+). |
| Mevcut mimariyle uyum | İşçi **ikinci bir yedekleme motoru oluşturmaz**: aynı `ClientBackupService.createEncryptedBackup` → `DatabaseBackupEngine.createBackup` yolunu çağırır; DB'yi kendi isolate'inde açar (Drift/SQLite WAL çoklu bağlantıyı destekler; yazma yapılmaz, `VACUUM INTO` salt okunur). |

## 3. Karar

### A. Uygulandı (bağımlılıksız hazırlık)
- `BackupOperationLock` + `ClientBackupService` entegrasyonu + zamanlayıcının meşgulde atlaması (ADR-016 Ek A/B). Testler: `backup_operation_lock_test`, `client_backup_operation_lock_test`, `secure_storage_fail_closed_test`.

### B. Pilot Sonrasına Ertelenen Tasarım (`DEFERRED_POST_PILOT` — Kod/Bağımlılık Değiştirilmedi)
1. `workmanager` eklentisi (`pubspec.yaml` değiştirilmedi) ve Kotlin/arka plan motoru tasarımı.
2. Keystore `MethodChannel` kodunun `MainActivity.kt` içinden ayrı bir `FlutterPlugin` sınıfına taşınması (`MainActivity.kt` bu aşamada değiştirilmedi).
3. Arka plan giriş noktası: **önce kilidi alır**, sonra DB'yi açar → `createEncryptedBackup` → saklama politikası → durumu yazar → DB'yi kapatır → kilidi bırakır.
4. Ayarlar ekranında "uygulama kapalıyken de yedekle" anahtarı.
5. Fiziksel test: `PHYSICAL_ACCEPTANCE_TEST_PLAN.md` PAT-15 adım 4.

### C. Bu Oturumda Uygulanan Güvenlik ve Dokümantasyon Düzeltmeleri
- **Android Keystore Hata Eşleme (`AndroidKeystoreTokenStore`):** `PlatformException` ve `MissingPluginException` istisnaları artık ham bırakılmaz; sır değeri veya ham detay sızdırılmadan `SecureStorageException(message, code: ...)` nesnesine dönüştürülür. Böylece `BackupScheduleController` (`ERR_SECURE_STORE`) ve `DeviceAuthNotifier` Android'de de fail-closed hata yoluna güvenle girer (`secure_storage_fail_closed_test`).
- **`minSdk` Tutarlılığı:** Derlenmiş birleşik Android manifesti `android:minSdkVersion="24"` (Android 7.0) olduğu için checklist/runbook içindeki eski `Android 6.0 / API 23` ifadesi `minSdk 24 (Android 7.0)` olarak düzeltildi.

## 4. Sonuçlar
- Owner kararı: `OWNER_ACTION_CHECKLIST.md` → `A5`.
- **Operasyonel Sınır (Pilot İçin Geçerli):** Android'de otomatik zamanlanmış yedek yalnızca uygulama açıkken çalışır; uygulama kapalıyken yedek alınmaz, uygulama açıldığında gecikmiş yedek hemen başlatılır (`PAT-15` adım 1–3). Gerçek Android donanımında Keystore kalıcılığı (`PAT-11`) ve zamanlanmış yedek (`PAT-15`) **BLOCKED**.
