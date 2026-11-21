import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/core/constants/app_constants.dart';
import 'package:market_pos/core/logging/redacting_logger.dart';
import 'package:market_pos/core/security/android_keystore_token_store.dart';
import 'package:market_pos/core/security/secure_token_store.dart';
import 'package:market_pos/core/security/security_providers.dart';
import 'package:market_pos/core/security/windows_dpapi_token_store.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/features/backup/application/backup_schedule_controller.dart';
import 'package:market_pos/features/backup/application/client_backup_service.dart';
import 'package:market_pos/features/setup/domain/app_setup_config.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

class _FailingTokenStore extends InMemorySecureTokenStore {
  @override
  Future<String?> readDeviceToken(String deviceId) async =>
      throw const FileSystemException('Keystore erişilemedi');
}

/// Faz 7B — Token güvenliği: derlemeye gömülü token yok, güvenli depo hatasında fail-closed.
void main() {
  test('Derlemeye gömülü varsayılan cihaz token’ı bulunmaz', () {
    expect(AppConstants.defaultDeviceToken, isEmpty);
    const state = DeviceAuthState(deviceId: 'POS-1', backendLabel: 'test');
    expect(state.effectiveToken, isNull,
        reason: 'Saklı token yoksa bilinen bir token’a düşülmemeli');
  });

  test('Güvenli depo okuma hatasında token kullanılmaz, hata maskeli loglanır ve uygulama çökmez', () async {
    final logger = RedactingLogger();
    final notifier = DeviceAuthNotifier(
      store: _FailingTokenStore(),
      logger: logger,
      deviceId: 'POS-1',
    );
    await notifier.loadForDevice('POS-1');

    expect(notifier.state.isLoaded, isTrue);
    expect(notifier.state.effectiveToken, isNull);
    expect(notifier.state.storageError, isNotNull);
    expect(
      logger.entries.where((e) => e.level == RedactedLogLevel.error),
      isNotEmpty,
    );
    notifier.dispose();
  });

  test(
    'Bozuk DPAPI dosyası sessizce boş kabul edilmez; yazma diğer sırları silmez (fail-closed)',
    () async {
      final dir = await Directory.systemTemp.createTemp('mms_dpapi_test_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File(p.join(dir.path, WindowsDpapiTokenStore.defaultFileName));
      await file.writeAsString('{bozuk-json');
      final store = WindowsDpapiTokenStore(storageFile: file);

      await expectLater(store.readSecret('any'), throwsA(isA<SecureStorageException>()));
      await expectLater(
        store.saveSecret('pin', 'value'),
        throwsA(isA<SecureStorageException>()),
      );
      expect(await file.readAsString(), '{bozuk-json',
          reason: 'Bozuk depo üzerine yazılarak mevcut sırlar yok edilmemeli');
    },
    skip: !Platform.isWindows,
  );

  group('ADR-020: AndroidKeystoreTokenStore fail-closed hata eşleme', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AndroidKeystoreTokenStore.defaultChannel, null);
    });

    test('PlatformException ve MissingPluginException ham haliyle sızmaz, SecureStorageException fırlatır', () async {
      const secretPayload = 'super_secret_token_9911';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AndroidKeystoreTokenStore.defaultChannel, (call) async {
        throw PlatformException(
          code: 'KEYSTORE_LOCKED',
          message: 'Android KeyStore kilitli ($secretPayload)',
          details: 'detail_$secretPayload',
        );
      });

      const store = AndroidKeystoreTokenStore();
      for (final op in [
        () => store.saveSecret('k', secretPayload),
        () => store.readSecret('k'),
        () => store.deleteSecret('k'),
      ]) {
        try {
          await op();
          fail('SecureStorageException fırlatılmalıydı');
        } on SecureStorageException catch (e) {
          expect(e.code, 'KEYSTORE_LOCKED');
          expect(e.message, isNot(contains(secretPayload)));
        }
      }

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AndroidKeystoreTokenStore.defaultChannel, null);

      for (final op in [
        () => store.saveSecret('k', secretPayload),
        () => store.readSecret('k'),
        () => store.deleteSecret('k'),
      ]) {
        await expectLater(
          op(),
          throwsA(
            isA<SecureStorageException>()
                .having((e) => e.code, 'code', 'MISSING_PLUGIN')
                .having((e) => e.message, 'message', isNot(contains(secretPayload))),
          ),
        );
      }
    });

    test('BackupScheduleController ve DeviceAuthNotifier Keystore hatasını yakalayıp fail-closed davranır', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AndroidKeystoreTokenStore.defaultChannel, (call) async {
        throw PlatformException(code: 'AEAD_FAILED', message: 'Keystore decrypt failed');
      });

      const store = AndroidKeystoreTokenStore();
      final logger = RedactingLogger();
      final authNotifier = DeviceAuthNotifier(
        store: store,
        logger: logger,
        deviceId: 'AND-01',
      );
      await authNotifier.loadForDevice('AND-01');
      expect(authNotifier.state.isLoaded, isTrue);
      expect(authNotifier.state.effectiveToken, isNull);
      expect(authNotifier.state.storageError, isNotNull);
      expect(logger.entries.where((e) => e.level == RedactedLogLevel.error), isNotEmpty);
      authNotifier.dispose();

      LocalDatabaseService.resetForTesting();
      final tempDir = await Directory.systemTemp.createTemp('mms_adr020_');
      addTearDown(() async {
        LocalDatabaseService.resetForTesting();
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final dbService = await LocalDatabaseService.initialize(customPath: p.join(tempDir.path, 'client_local.db'));
      final backupService = ClientBackupService(
        dbService: dbService,
        backupRootDir: Directory(p.join(tempDir.path, 'backups')),
        readSetupConfig: () => AppSetupConfig.initial().copyWith(deviceId: 'AND-01'),
        kdfIterations: 1000,
      );

      var failChannel = true;
      final controller = BackupScheduleController(
        backupService: backupService,
        secureStore: store,
        settingsStore: ClientBackupScheduleSettingsStore(File(p.join(tempDir.path, 'sched_settings.json'))),
        stateStore: BackupScheduleStateStore(File(p.join(tempDir.path, 'sched_state.json'))),
      );
      addTearDown(() async {
        await controller.waitForIdle();
        controller.dispose();
      });

      await expectLater(
        controller.enable(intervalHours: 24, password: 'BackupPassword123!'),
        throwsA(isA<SecureStorageException>()),
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AndroidKeystoreTokenStore.defaultChannel, (call) async {
        if (call.method == 'saveSecret') return null;
        if (call.method == 'readSecret' && failChannel) {
          throw PlatformException(code: 'KEYSTORE_UNAVAILABLE', message: 'Biometric/Keystore error');
        }
        return null;
      });

      await controller.enable(intervalHours: 24, password: 'BackupPassword123!');
      await controller.waitForIdle();
      failChannel = true;
      final run = await controller.runNow();
      expect(run, isNotNull);
      expect(run!.success, isFalse);
      expect(run.errorCode, 'ERR_SECURE_STORE');
    });
  });
}
