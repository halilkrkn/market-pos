import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/core/security/secure_token_store.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/features/backup/application/backup_schedule_controller.dart';
import 'package:market_pos/features/backup/application/client_backup_service.dart';
import 'package:market_pos/features/setup/domain/app_setup_config.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

/// BK-LOCK — İstemcide yedek ve geri yükleme aynı anda çalışmaz (gerçek FFI SQLite).
///
/// Senaryolar: restore sürerken zamanlanmış yedek tetiklenmesi; arka plan işçisi
/// (ayrı isolate) yedek alırken kullanıcının restore başlatması.
void main() {
  late Directory tempDir;
  late LocalDatabaseService dbService;
  late ClientBackupService backupService;
  late Completer<void> syncPaused;
  late Completer<void> releasePause;
  var pauseCalls = 0;
  const password = 'Lock_Test_Password_2026!';
  final setup = AppSetupConfig.initial().copyWith(
    deviceId: 'DEV-LOCK-01',
    tenantId: 'tenant-l',
    storeId: 'store-l',
  );

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    LocalDatabaseService.resetForTesting();
    tempDir = await Directory.systemTemp.createTemp('mms_client_lock_');
    dbService = await LocalDatabaseService.initialize(customPath: p.join(tempDir.path, 'client_local.db'));
    await dbService.repository.upsertProducts([
      LocalProductsCompanion(
        id: const Value('p1'),
        name: const Value('Ürün'),
        price: const Value(1000),
        stock: const Value(1000),
        updatedAt: Value(DateTime.now()),
      ),
    ]);
    pauseCalls = 0;
    syncPaused = Completer<void>();
    releasePause = Completer<void>()..complete();
    backupService = ClientBackupService(
      dbService: dbService,
      backupRootDir: Directory(p.join(tempDir.path, 'backups')),
      readSetupConfig: () => setup,
      kdfIterations: 1000,
      databaseTypeOverride: DatabaseType.clientLocal,
      pauseSync: () async {
        pauseCalls++;
        if (!syncPaused.isCompleted) syncPaused.complete();
        await releasePause.future;
      },
      resumeSync: () {},
    );
  });

  tearDown(() async {
    await dbService.close();
    LocalDatabaseService.resetForTesting();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {
      // Windows dosya kilidi; geçici dizin.
    }
  });

  test('1. Restore sürerken yedek isteği ERR_BACKUP_OPERATION_BUSY alır; restore bitince yedek alınır', () async {
    final backup = await backupService.createEncryptedBackup(password: password);
    releasePause = Completer<void>(); // restore senkron duraklatmada bekletilir

    final restoreFuture = backupService.restoreEncryptedBackup(backupId: backup.backupId, password: password);
    await syncPaused.future;

    await expectLater(
      backupService.createEncryptedBackup(password: password),
      throwsA(isA<BackupException>().having((e) => e.code, 'code', BackupOperationLock.busyErrorCode)),
    );

    releasePause.complete();
    await restoreFuture;
    final after = await backupService.createEncryptedBackup(password: password);
    expect(after.backupId, isNotEmpty);
    expect(backupService.operationLockFile.existsSync(), isFalse, reason: 'kilit bırakıldı');
  });

  test('2. Başka isolate/süreç yedek alırken restore reddedilir; senkron duraklatılmaz, canlı DB değişmez', () async {
    final backup = await backupService.createEncryptedBackup(password: password);
    await dbService.repository.createOfflineSale(
      deviceId: setup.deviceId,
      paymentMethod: 'CASH',
      items: [CartItemInput.units('p1', 1)],
    );

    final foreign = await BackupOperationLock(backupService.operationLockFile).acquire(BackupOperationKind.backup);
    try {
      await expectLater(
        backupService.restoreEncryptedBackup(backupId: backup.backupId, password: password),
        throwsA(isA<BackupException>()
            .having((e) => e.code, 'code', BackupOperationLock.busyErrorCode)
            .having((e) => e.message, 'message', contains('yedekleme'))),
      );
    } finally {
      await foreign.release();
    }
    expect(pauseCalls, 0, reason: 'reddedilen restore senkronizasyonu durdurmamalı');
    expect((await dbService.repository.getOutboxSummary()).totalUnsynced, greaterThan(0));
  });

  test('3. Kilit tutulurken zamanlanmış tur hata kaydetmez (yanıltıcı "başarısız" ve 30 dk gecikme yok)', () async {
    final secureStore = InMemorySecureTokenStore();
    final controller = BackupScheduleController(
      backupService: backupService,
      secureStore: secureStore,
      settingsStore: ClientBackupScheduleSettingsStore(File(p.join(tempDir.path, 'settings.json'))),
      stateStore: BackupScheduleStateStore(File(p.join(tempDir.path, 'state.json'))),
      checkInterval: const Duration(hours: 1),
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    final foreign = await BackupOperationLock(backupService.operationLockFile).acquire(BackupOperationKind.restore);
    try {
      await controller.enable(intervalHours: 24, password: password); // açılış turu tetiklenir
      await controller.waitForIdle();
      expect(controller.state.scheduleState.history, isEmpty);
      expect(controller.state.scheduleState.lastFailureAt, isNull);
    } finally {
      await foreign.release();
    }
  });

  test('4. Kilitli restore sırasında yedekten sonraki Outbox işlemleri ve client_seq korunur', () async {
    await dbService.repository.initializeDevice(setup.deviceId);
    await dbService.repository.createOfflineSale(
      deviceId: setup.deviceId,
      paymentMethod: 'CASH',
      items: [CartItemInput.units('p1', 1)],
    ); // seq 1
    final backup = await backupService.createEncryptedBackup(password: password);

    // Yedekten sonra bekleyen offline satış (seq 2)
    await dbService.repository.createOfflineSale(
      deviceId: setup.deviceId,
      paymentMethod: 'CASH',
      items: [CartItemInput.units('p1', 1)],
    );

    releasePause = Completer<void>();
    final restoreFuture = backupService.restoreEncryptedBackup(
      backupId: backup.backupId,
      password: password,
    );
    await syncPaused.future;

    // Restore sürerken ikinci backup reddedilir.
    await expectLater(
      backupService.createEncryptedBackup(password: password),
      throwsA(isA<BackupException>().having((e) => e.code, 'code', BackupOperationLock.busyErrorCode)),
    );

    releasePause.complete();
    final restored = await restoreFuture;
    expect(restored.backupId, backup.backupId);

    final outboxAfter = await (dbService.database.select(dbService.database.outboxOperations)
          ..where((o) => o.deviceId.equals(setup.deviceId))
          ..orderBy([(o) => OrderingTerm.asc(o.clientSeq)]))
        .get();
    expect(outboxAfter.map((o) => o.clientSeq), [1, 2]);
    expect(outboxAfter[1].status, 'PENDING');

    final syncState = await dbService.repository.getSyncState(setup.deviceId);
    expect(syncState!.currentClientSeq, greaterThanOrEqualTo(2));

    final nextSale = await dbService.repository.createOfflineSale(
      deviceId: setup.deviceId,
      paymentMethod: 'CASH',
      items: [CartItemInput.units('p1', 1)],
    );
    expect(nextSale.clientSeq, 3);
  });

  test('5. ADR-016 H-4: Kilit tutulurken prune, export, import ve delete işlemlerinin tamamı ERR_BACKUP_OPERATION_BUSY döner', () async {
    final held = await BackupOperationLock(backupService.operationLockFile)
        .acquire(BackupOperationKind.restore);
    final extDir = Directory(p.join(tempDir.path, 'usb'))..createSync(recursive: true);
    final dummyFile = File(p.join(extDir.path, 'dummy.mmsbak'))..writeAsStringSync('not_real');
    try {
      for (final call in [
        () => backupService.pruneExpiredBackups(const RetentionPolicy()),
        () => backupService.exportLatestBackupTo(extDir),
        () => backupService.importBackupFile(dummyFile),
        () => backupService.deleteBackup('any_id'),
      ]) {
        await expectLater(
          call(),
          throwsA(isA<BackupException>().having((e) => e.code, 'code', BackupOperationLock.busyErrorCode)),
        );
      }
    } finally {
      await held.release();
    }
  });
}
