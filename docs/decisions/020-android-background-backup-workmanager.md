# ADR-020: Android Uygulama Kapalıyken Arka Plan Zamanlanmış Şifreli Yedekleme (`JobScheduler` + Headless `FlutterEngine`)

- **Durum:** **CONFIRMED — TECHNICALLY IMPLEMENTED** (21.11.2026 Release 1.0 Kapsamı; fiziksel cihaz testi `PAT-16` bekleniyor)
- **Tarih:** 2026-11-21
- **Etkilenen Alanlar:** `android/app/src/main/kotlin/com/marketmms/market_pos/`, `android/app/src/main/AndroidManifest.xml`, `lib/features/backup/`, `lib/main.dart`, `docs/operations/BACKUP_AND_RESTORE_GUIDE.md`

---

## 1. Bağlam ve Seçilen Mimari

Android 7.0+ (`minSdk 24`) cihazlarda yalnızca uygulama ön planda açıkken çalışan `Timer` tabanlı zamanlayıcı, kasa/telefon gün boyunca kapatıldığında zamanlı yedeklerin gecikmesine yol açmaktadır. Release 1.0 kapsamında Owner, uygulama kapalıyken de çalışan arka plan şifreli yedeklemeyi pilot kapsamına almıştır.

Harici `workmanager` pub paketine yeni ağ/Gradle bağımlılığı eklemek yerine (çevrimdışı Gradle derleme kırılganlığından kaçınmak ve doğrudan kontrol sağlamak için) **saf Android SDK `JobScheduler` (`JobService` + `setPersisted(true)`) + arka plan headless `FlutterEngine`** mimarisi tercih edilmiştir:

1. **`MmsSecureStorageChannelHandler.kt`:** `AndroidKeystore` + AES-256-GCM şifreli Depolama kanalı `MainActivity`'den ayrı, yeniden kullanılabilir sınıfa taşındı; hem ön plan `MainActivity` hem arka plan `MmsBackgroundBackupJobService` aynı kanalı kaydeder.
2. **`MmsBackgroundBackupJobService.kt` & `AndroidManifest.xml`:** `BIND_JOB_SERVICE` ve `RECEIVE_BOOT_COMPLETED` ile uygulama kapandıktan veya cihaz yeniden başlatıldıktan sonra bile (`setPersisted(true)`) OS tarafından zamanlı uyandırılır; arka plan `FlutterEngine` üzerinden `@pragma('vm:entry-point')` `mmsBackgroundBackupEntrypoint()` giriş noktasını başlatır.
3. **`BackgroundBackupWorkerExecutor` (`lib/features/backup/application/background_backup_scheduler.dart`):**
   - `ScheduledBackupRunner` + `BackupSchedulePolicy.isDue` ile aralık içi tekrar yedek almaz (**idempotent**).
   - Ön plan/geri yükleme ile ortak **`BackupOperationLock`** kullanır; kilit tutuluyorsa `SKIPPED_LOCK_BUSY` döner ve hata sayacını artırmaz.
   - `AndroidKeystoreTokenStore` okuma hatasında **fail-closed** (`FAILED_KEYSTORE_UNAVAILABLE`) durur; asla şifresiz `.db` yedeği üretmez.
   - Geçici disk/arka plan hatalarında üstel geri çekilme (`computeBackoffDelay`: 5 dk → 10 dk → 20 dk → 40 dk → 80 dk → 160 dk) hesaplar ve JobScheduler retry/reschedule sinyali döner.
4. **UI Durumu (`BackupScheduleSection`):** `backup_bg_schedule_status_row`, `backup_bg_next_run_row` ve `backup_bg_last_status_row` alanları üzerinden operatöre zamanlama durumunu gösterir.

---

## 2. Doğrulama Durumu

- Otomatik testler (`test/features/backup/workmanager_background_backup_test.dart`, `backup_schedule_controller_test.dart`, `client_backup_operation_lock_test.dart`, `secure_storage_fail_closed_test.dart`): birim, kilit çakışması, Keystore fail-closed, backoff, yeniden başlatma durumu, MethodChannel köprüsü ve widget render testleri geçti.
- **Fiziksel Doğrulama Sınırı:** Android cihazda `JobScheduler` uyandırma, zorla kapatma ve cihaz reboot persistence doğrulaması `PAT-16` ile sahada yapılacaktır (`BLOCKED — NOT RUN`).
