import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/core/security/secure_token_store.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/core/theme/app_theme.dart';
import 'package:market_pos/features/backup/application/background_backup_scheduler.dart';
import 'package:market_pos/features/backup/application/backup_schedule_controller.dart';
import 'package:market_pos/features/backup/application/client_backup_service.dart';
import 'package:market_pos/features/backup/backup_providers.dart';
import 'package:market_pos/features/backup/presentation/widgets/backup_schedule_section.dart';
import 'package:market_pos/features/setup/domain/app_setup_config.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

class _ControllableSecureTokenStore implements SecureTokenStore {
  final Map<String, String> _values = <String, String>{};
  Object? readError;

  @override
  String get backendLabel => 'test_keystore';

  @override
  Future<void> saveDeviceToken(String deviceId, String token) async {
    _values['device_token:$deviceId'] = token;
  }

  @override
  Future<String?> readDeviceToken(String deviceId) async {
    if (readError != null) throw readError!;
    return _values['device_token:$deviceId'];
  }

  @override
  Future<void> deleteDeviceToken(String deviceId) async {
    _values.remove('device_token:$deviceId');
  }

  @override
  Future<void> saveSecret(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<String?> readSecret(String key) async {
    if (readError != null) throw readError!;
    return _values[key];
  }

  @override
  Future<void> deleteSecret(String key) async {
    _values.remove(key);
  }
}

class _FailingCreateBackupService extends ClientBackupService {
  _FailingCreateBackupService({
    required super.dbService,
    required super.backupRootDir,
    required super.readSetupConfig,
    super.kdfIterations,
    super.databaseTypeOverride,
  });

  @override
  Future<BackupResult> createEncryptedBackup({
    required String password,
    bool isMonthlyArchive = false,
  }) async {
    throw const BackupException(
      'ERR_DISK_FULL',
      'Test disk dolu hatası',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const setupConfig = AppSetupConfig(
    isSetupCompleted: true,
    tenantId: 'tenant-bg-1',
    storeId: 'store-bg-1',
    storeName: 'Merkez Şube',
    deviceId: 'dev-android-bg-01',
    deviceName: 'Kasa Mobil 1',
  );

  Future<
      ({
        Directory tempDir,
        LocalDatabaseService dbService,
        ClientBackupService backupService,
        Directory backupRootDir,
        File settingsFile,
        File stateFile,
        _ControllableSecureTokenStore secureStore,
      })> createHarness({bool failingBackupService = false}) async {
    final tempDir = Directory.systemTemp.createTempSync('mms_bg_backup_test_');
    final dbPath = p.join(tempDir.path, 'client_local.db');
    final dbService = await LocalDatabaseService.initialize(customPath: dbPath);
    final backupRootDir = Directory(p.join(tempDir.path, 'backups'));
    final backupService = failingBackupService
        ? _FailingCreateBackupService(
            dbService: dbService,
            backupRootDir: backupRootDir,
            readSetupConfig: () => setupConfig,
            kdfIterations: 1000,
            databaseTypeOverride: DatabaseType.mobileLocal,
          )
        : ClientBackupService(
            dbService: dbService,
            backupRootDir: backupRootDir,
            readSetupConfig: () => setupConfig,
            kdfIterations: 1000,
            databaseTypeOverride: DatabaseType.mobileLocal,
          );
    final settingsFile = File(p.join(tempDir.path, 'backup_schedule_settings.json'));
    final stateFile = File(p.join(tempDir.path, 'backup_schedule_state.json'));
    final secureStore = _ControllableSecureTokenStore();

    addTearDown(() async {
      await LocalDatabaseService.closeActive();
      LocalDatabaseService.resetForTesting();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    return (
      tempDir: tempDir,
      dbService: dbService,
      backupService: backupService,
      backupRootDir: backupRootDir,
      settingsFile: settingsFile,
      stateFile: stateFile,
      secureStore: secureStore,
    );
  }

  group('Faz B — BackgroundBackupWorkerExecutor & Scheduler', () {
    test('uygulama kapalıyken due backup şifreli üretir ve aralık içinde tekrar almaz (idempotency)', () async {
      final h = await createHarness();
      var now = DateTime.utc(2026, 11, 21, 10, 0, 0);
      await ClientBackupScheduleSettingsStore(h.settingsFile).save(
        const ClientBackupScheduleSettings(
          enabled: true,
          intervalHours: 6,
          backgroundWhenClosedEnabled: true,
        ),
      );
      await h.secureStore.saveSecret(
        BackupScheduleController.passwordSecretKey,
        'KasaParola2026!',
      );

      final uploadedIds = <String>[];
      final executor = BackgroundBackupWorkerExecutor(
        backupService: h.backupService,
        secureStore: h.secureStore,
        settingsStore: ClientBackupScheduleSettingsStore(h.settingsFile),
        stateStore: BackupScheduleStateStore(h.stateFile),
        afterSuccess: (res) async => uploadedIds.add(res.backupId),
        clock: () => now,
      );

      final first = await executor.executeTick();
      expect(first.kind, BackgroundWorkerOutcomeKind.success);
      expect(first.statusCode, 'SUCCESS');
      expect(first.shouldRetry, isFalse);
      expect(first.runRecord?.success, isTrue);
      expect(uploadedIds, hasLength(1));

      final backups = await h.backupService.listBackups();
      expect(backups, hasLength(1));
      expect(backups.first.file.path, endsWith('.mmsbak'));

      // 2 saat sonra henüz due değil -> idempotent atlanır
      now = now.add(const Duration(hours: 2));
      final second = await executor.executeTick();
      expect(second.kind, BackgroundWorkerOutcomeKind.skippedNotDue);
      expect(second.statusCode, 'SKIPPED_NOT_DUE');
      expect(second.shouldRetry, isFalse);
      expect(await h.backupService.listBackups(), hasLength(1));

      // 6 saat dolduğunda ikinci yedek üretilir
      now = now.add(const Duration(hours: 4));
      final third = await executor.executeTick();
      expect(third.kind, BackgroundWorkerOutcomeKind.success);
      expect(await h.backupService.listBackups(), hasLength(2));
    });

    test('BackupOperationLock başka işlemdeyken SKIPPED_LOCK_BUSY döner ve state hata sayacını artırmaz', () async {
      final h = await createHarness();
      final now = DateTime.utc(2026, 11, 21, 12, 0, 0);
      await ClientBackupScheduleSettingsStore(h.settingsFile).save(
        const ClientBackupScheduleSettings(
          enabled: true,
          intervalHours: 6,
        ),
      );
      await h.secureStore.saveSecret(
        BackupScheduleController.passwordSecretKey,
        'KasaParola2026!',
      );

      final heldLock = await BackupOperationLock(h.backupService.operationLockFile)
          .acquire(BackupOperationKind.restore);
      try {
        final executor = BackgroundBackupWorkerExecutor(
          backupService: h.backupService,
          secureStore: h.secureStore,
          settingsStore: ClientBackupScheduleSettingsStore(h.settingsFile),
          stateStore: BackupScheduleStateStore(h.stateFile),
          clock: () => now,
        );

        final res = await executor.executeTick();
        expect(res.kind, BackgroundWorkerOutcomeKind.skippedLockBusy);
        expect(res.statusCode, 'SKIPPED_LOCK_BUSY');
        expect(res.errorCode, BackupOperationLock.busyErrorCode);
        expect(res.shouldRetry, isTrue);
        expect(res.nextBackoffDelay, const Duration(minutes: 5));

        final state = await BackupScheduleStateStore(h.stateFile).load();
        expect(state.consecutiveFailures, 0);
        expect(await h.backupService.listBackups(), isEmpty);
      } finally {
        await heldLock.release();
      }
    });

    test('Keystore hatalarında fail-closed davranır ve asla şifresiz yedek oluşturmaz', () async {
      final h = await createHarness();
      await ClientBackupScheduleSettingsStore(h.settingsFile).save(
        const ClientBackupScheduleSettings(enabled: true, intervalHours: 6),
      );

      final executor = BackgroundBackupWorkerExecutor(
        backupService: h.backupService,
        secureStore: h.secureStore,
        settingsStore: ClientBackupScheduleSettingsStore(h.settingsFile),
        stateStore: BackupScheduleStateStore(h.stateFile),
      );

      // 1. SecureStorageException
      h.secureStore.readError =
          const SecureStorageException('Keystore kilitli', code: 'KEY_LOCKED');
      final r1 = await executor.executeTick();
      expect(r1.kind, BackgroundWorkerOutcomeKind.failedKeystoreUnavailable);
      expect(r1.statusCode, 'FAILED_KEYSTORE_UNAVAILABLE');
      expect(r1.errorCode, 'KEY_LOCKED');
      expect(r1.shouldRetry, isTrue);

      // 2. PlatformException
      h.secureStore.readError = PlatformException(code: 'ERR_KS_INIT');
      final r2 = await executor.executeTick();
      expect(r2.kind, BackgroundWorkerOutcomeKind.failedKeystoreUnavailable);
      expect(r2.statusCode, 'FAILED_KEYSTORE_UNAVAILABLE');
      expect(r2.errorCode, 'ERR_KS_INIT');
      expect(r2.shouldRetry, isTrue);

      // 3. MissingPluginException
      h.secureStore.readError = MissingPluginException();
      final r3 = await executor.executeTick();
      expect(r3.kind, BackgroundWorkerOutcomeKind.failedKeystoreUnavailable);
      expect(r3.statusCode, 'FAILED_KEYSTORE_MISSING_PLUGIN');
      expect(r3.shouldRetry, isFalse);

      // 4. Parola null/boş
      h.secureStore.readError = null;
      final r4 = await executor.executeTick();
      expect(r4.kind, BackgroundWorkerOutcomeKind.failedKeystoreUnavailable);
      expect(r4.statusCode, 'FAILED_PASSWORD_MISSING');
      expect(r4.shouldRetry, isFalse);

      // Hiçbir yedek (.mmsbak veya şifresiz .db) oluşturulmamış olmalı.
      if (h.backupRootDir.existsSync()) {
        expect(h.backupRootDir.listSync(recursive: true), isEmpty);
      }
    });

    test('computeBackoffDelay ve ardışık yedek hataları üstel geri çekilme uygular', () async {
      expect(BackgroundBackupWorkerExecutor.computeBackoffDelay(1), const Duration(minutes: 5));
      expect(BackgroundBackupWorkerExecutor.computeBackoffDelay(2), const Duration(minutes: 10));
      expect(BackgroundBackupWorkerExecutor.computeBackoffDelay(3), const Duration(minutes: 20));
      expect(BackgroundBackupWorkerExecutor.computeBackoffDelay(4), const Duration(minutes: 40));
      expect(BackgroundBackupWorkerExecutor.computeBackoffDelay(5), const Duration(minutes: 80));
      expect(BackgroundBackupWorkerExecutor.computeBackoffDelay(6), const Duration(minutes: 160));
      expect(BackgroundBackupWorkerExecutor.computeBackoffDelay(8), const Duration(minutes: 160));

      final h = await createHarness(failingBackupService: true);
      var now = DateTime.utc(2026, 11, 21, 14, 0, 0);
      await ClientBackupScheduleSettingsStore(h.settingsFile).save(
        const ClientBackupScheduleSettings(enabled: true, intervalHours: 6),
      );
      await h.secureStore.saveSecret(
        BackupScheduleController.passwordSecretKey,
        'KasaParola2026!',
      );

      final executor = BackgroundBackupWorkerExecutor(
        backupService: h.backupService,
        secureStore: h.secureStore,
        settingsStore: ClientBackupScheduleSettingsStore(h.settingsFile),
        stateStore: BackupScheduleStateStore(h.stateFile),
        clock: () => now,
      );

      final fail1 = await executor.executeTick();
      expect(fail1.kind, BackgroundWorkerOutcomeKind.failedRetryable);
      expect(fail1.shouldRetry, isTrue);
      expect(fail1.errorCode, 'ERR_DISK_FULL');
      expect(fail1.nextBackoffDelay, const Duration(minutes: 5));

      // failureRetryDelay (30 dk) sonrası ikinci hata -> 10 dk backoff
      now = now.add(const Duration(minutes: 31));
      final fail2 = await executor.executeTick();
      expect(fail2.kind, BackgroundWorkerOutcomeKind.failedRetryable);
      expect(fail2.nextBackoffDelay, const Duration(minutes: 10));
    });

    test('uygulama/süreç yeniden başlatma sonrasında zamanlama durumu ve OS job durumu korunur', () async {
      final h = await createHarness();
      final bgScheduler = InMemoryBackgroundBackupScheduler(
        clock: () => DateTime.utc(2026, 11, 21, 16, 0, 0),
      );

      final controller1 = BackupScheduleController(
        backupService: h.backupService,
        secureStore: h.secureStore,
        settingsStore: ClientBackupScheduleSettingsStore(h.settingsFile),
        stateStore: BackupScheduleStateStore(h.stateFile),
        backgroundScheduler: bgScheduler,
      );
      await controller1.initialize();
      await controller1.enable(intervalHours: 12, password: 'KasaParola2026!');
      await controller1.waitForIdle();
      controller1.dispose();

      // Uygulama kapalıyken arka plan işçisi bir sonuç kaydetmiş gibi simüle et.
      bgScheduler.recordWorkerOutcome(status: 'SUCCESS');

      // Yeni süreçte controller2 açılır
      final controller2 = BackupScheduleController(
        backupService: h.backupService,
        secureStore: h.secureStore,
        settingsStore: ClientBackupScheduleSettingsStore(h.settingsFile),
        stateStore: BackupScheduleStateStore(h.stateFile),
        backgroundScheduler: bgScheduler,
      );
      await controller2.initialize();
      await controller2.waitForIdle();
      addTearDown(controller2.dispose);

      expect(controller2.state.settings.enabled, isTrue);
      expect(controller2.state.settings.intervalHours, 12);
      expect(controller2.state.backgroundStatus.isScheduled, isTrue);
      expect(controller2.state.backgroundStatus.intervalMinutes, 720);
      expect(controller2.state.backgroundStatus.lastStatus, 'SUCCESS');
      expect(controller2.state.backgroundStatus.nextRunAtUtc, isNotNull);
    });

    test('MethodChannelBackgroundBackupScheduler kanal çağrılarını ve hataları güvenli yönetir', () async {
      const channel = MethodChannel('com.marketmms.market_pos/background_backup_test');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];

      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'schedulePeriodicBackup') {
          return <String, dynamic>{
            'isScheduled': true,
            'intervalMinutes': 360,
            'requiresNetwork': false,
            'requiresBatteryNotLow': true,
            'requiresStorageNotLow': true,
            'nextRunEpochMs': DateTime.utc(2026, 11, 22, 0, 0).millisecondsSinceEpoch,
          };
        }
        if (call.method == 'getScheduleStatus') {
          return <String, dynamic>{
            'isScheduled': true,
            'intervalMinutes': 360,
            'lastStatus': 'SUCCESS',
            'lastRunEpochMs': DateTime.utc(2026, 11, 21, 18, 0).millisecondsSinceEpoch,
          };
        }
        if (call.method == 'cancelPeriodicBackup') {
          return <String, dynamic>{'isScheduled': false, 'intervalMinutes': 360};
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      const scheduler = MethodChannelBackgroundBackupScheduler(
        channel: channel,
        platformOverride: true,
      );

      final scheduled = await scheduler.schedulePeriodic(interval: const Duration(hours: 6));
      expect(scheduled.isScheduled, isTrue);
      expect(scheduled.intervalMinutes, 360);
      expect(calls.last.arguments, containsPair('intervalMinutes', 360));

      final status = await scheduler.getStatus();
      expect(status.lastStatus, 'SUCCESS');
      expect(status.lastRunAtUtc, DateTime.utc(2026, 11, 21, 18, 0));

      final cancelled = await scheduler.cancelPeriodic();
      expect(cancelled.isScheduled, isFalse);

      // PlatformException durumu kontrollü BackupException'a çevrilir
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'ERR_JOB_DENIED', message: 'Denied');
      });
      await expectLater(
        () => scheduler.schedulePeriodic(interval: const Duration(hours: 6)),
        throwsA(isA<BackupException>().having((e) => e.code, 'code', 'ERR_JOB_DENIED')),
      );
    });

    testWidgets('BackupScheduleSection arka plan zamanlayıcı durumu, sonraki çalışma ve son sonucu gösterir',
        (tester) async {
      await tester.runAsync(() async {
        final tempDir = Directory.systemTemp.createTempSync('mms_bg_widget_');
        final dbService = LocalDatabaseService.forTesting(
          NativeDatabase.memory(),
          path: p.join(tempDir.path, 'widget_test.db'),
        );
        final backupService = ClientBackupService(
          dbService: dbService,
          backupRootDir: Directory(p.join(tempDir.path, 'backups')),
          readSetupConfig: () => setupConfig,
          kdfIterations: 1000,
          databaseTypeOverride: DatabaseType.mobileLocal,
        );
        final bgScheduler = InMemoryBackgroundBackupScheduler(
          clock: () => DateTime.utc(2026, 11, 21, 18, 0),
        );
        await bgScheduler.schedulePeriodic(interval: const Duration(hours: 6));
        bgScheduler.recordWorkerOutcome(status: 'SUCCESS');

        final controller = BackupScheduleController(
          backupService: backupService,
          secureStore: _ControllableSecureTokenStore(),
          settingsStore: ClientBackupScheduleSettingsStore(
            File(p.join(tempDir.path, 'settings.json')),
          ),
          stateStore: BackupScheduleStateStore(
            File(p.join(tempDir.path, 'state.json')),
          ),
          backgroundScheduler: bgScheduler,
        );
        await controller.initialize();
        await controller.refreshBackgroundStatus();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              backupScheduleControllerProvider.overrideWith((_) => controller),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const Scaffold(
                body: SingleChildScrollView(child: BackupScheduleSection()),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byKey(const Key('backup_bg_schedule_status_row')), findsOneWidget);
        expect(find.byKey(const Key('backup_bg_next_run_row')), findsOneWidget);
        expect(find.byKey(const Key('backup_bg_last_status_row')), findsOneWidget);
        expect(find.textContaining('ZAMANLANDI'), findsOneWidget);
        expect(find.textContaining('SUCCESS'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        if (controller.mounted) controller.dispose();
        await dbService.close();
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
    });
  });
}
