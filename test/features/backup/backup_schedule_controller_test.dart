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

/// Faz 3 — İstemci (Windows/Android) zamanlanmış yerel yedekleme (TDD, gerçek FFI SQLite).
void main() {
  late Directory tempDir;
  late LocalDatabaseService dbService;
  late ClientBackupService backupService;
  late InMemorySecureTokenStore secureStore;
  late File settingsFile;
  late File stateFile;
  final setup = AppSetupConfig.initial().copyWith(
    deviceId: 'DEV-SCHED-01',
    tenantId: 'tenant-s',
    storeId: 'store-s',
  );

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    LocalDatabaseService.resetForTesting();
    tempDir = await Directory.systemTemp.createTemp('mms_client_sched_');
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
    backupService = ClientBackupService(
      dbService: dbService,
      backupRootDir: Directory(p.join(tempDir.path, 'backups')),
      readSetupConfig: () => setup,
      kdfIterations: 1000,
      databaseTypeOverride: DatabaseType.clientLocal,
    );
    secureStore = InMemorySecureTokenStore();
    settingsFile = File(p.join(tempDir.path, 'backup_schedule_settings.json'));
    stateFile = File(p.join(tempDir.path, 'backup_schedule_state.json'));
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

  BackupScheduleController controller({Future<void> Function(BackupResult)? afterSuccess}) =>
      BackupScheduleController(
        backupService: backupService,
        secureStore: secureStore,
        settingsStore: ClientBackupScheduleSettingsStore(settingsFile),
        stateStore: BackupScheduleStateStore(stateFile),
        checkInterval: const Duration(hours: 1),
        afterSuccess: afterSuccess,
      );

  test('1. Zayıf parola ile otomatik yedekleme etkinleştirilemez; hiçbir şey saklanmaz', () async {
    final c = controller();
    addTearDown(c.dispose);
    await c.initialize();

    await expectLater(c.enable(intervalHours: 24, password: '123'), throwsA(isA<BackupException>()));
    expect(await secureStore.readSecret(BackupScheduleController.passwordSecretKey), isNull);
    expect(c.state.settings.enabled, isFalse);
  });

  test('2. Etkinleştirme: parola yalnızca güvenli depoda tutulur, ilk yedek hemen alınır, durum kalıcıdır', () async {
    final c = controller();
    addTearDown(c.dispose);
    await c.initialize();

    await c.enable(intervalHours: 24, password: 'Otomatik#Yedek2026');
    await c.waitForIdle();

    expect(await secureStore.readSecret(BackupScheduleController.passwordSecretKey), 'Otomatik#Yedek2026');
    expect(settingsFile.readAsStringSync(), isNot(contains('Otomatik#Yedek2026')),
        reason: 'Parola düz metin ayar dosyasına yazılmamalı');
    expect(await backupService.listBackups(), hasLength(1));
    expect(c.state.scheduleState.lastSuccessAt, isNotNull);
    expect(c.state.scheduleState.history.single.trigger, BackupTrigger.scheduled);
    expect(c.state.isSchedulerActive, isTrue);
  });

  test('3. Yeniden başlatmada ayarlar yüklenir; aralık dolmadıysa ikinci yedek alınmaz', () async {
    final c1 = controller();
    await c1.initialize();
    await c1.enable(intervalHours: 24, password: 'Otomatik#Yedek2026');
    await c1.waitForIdle();
    c1.dispose();

    final c2 = controller();
    addTearDown(c2.dispose);
    await c2.initialize();
    await c2.waitForIdle();

    expect(c2.state.settings.enabled, isTrue);
    expect(c2.state.settings.intervalHours, 24);
    expect(await backupService.listBackups(), hasLength(1));
  });

  test('4. Parola güvenli depodan kaybolursa yedek başarısız olur ve kullanıcıya anlaşılır hata gösterilir', () async {
    final c = controller();
    addTearDown(c.dispose);
    await c.initialize();
    await c.enable(intervalHours: 24, password: 'Otomatik#Yedek2026');
    await c.waitForIdle();
    await secureStore.deleteSecret(BackupScheduleController.passwordSecretKey);

    final record = await c.runNow();

    expect(record!.success, isFalse);
    expect(record.errorCode, 'ERR_SCHEDULE_PASSWORD_MISSING');
    expect(c.state.scheduleState.lastErrorCode, 'ERR_SCHEDULE_PASSWORD_MISSING');
    expect(c.state.scheduleState.consecutiveFailures, 1);
  });

  test('5. Devre dışı bırakma zamanlayıcıyı durdurur ve parolayı güvenli depodan siler', () async {
    final c = controller();
    addTearDown(c.dispose);
    await c.initialize();
    await c.enable(intervalHours: 12, password: 'Otomatik#Yedek2026');
    await c.waitForIdle();

    await c.disable();

    expect(c.state.settings.enabled, isFalse);
    expect(c.state.isSchedulerActive, isFalse);
    expect(await secureStore.readSecret(BackupScheduleController.passwordSecretKey), isNull);
  });

  test('6. Uzak yedek adımı (Drive) başarısız olsa da yerel yedek başarılı sayılır', () async {
    final c = controller(afterSuccess: (_) async => throw StateError('Drive bağlantısı yok'));
    addTearDown(c.dispose);
    await c.initialize();
    await c.enable(intervalHours: 24, password: 'Otomatik#Yedek2026');
    await c.waitForIdle();

    final last = c.state.scheduleState.history.first;
    expect(last.success, isTrue);
    expect(last.postProcessError, contains('Drive bağlantısı yok'));
  });

  test('7. Desteklenmeyen sıklık reddedilir', () async {
    final c = controller();
    addTearDown(c.dispose);
    await c.initialize();
    await expectLater(c.enable(intervalHours: 5, password: 'Otomatik#Yedek2026'), throwsA(isA<BackupException>()));
  });
}
