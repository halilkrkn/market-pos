import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import 'app/app.dart';
import 'core/logging/redacting_logger.dart';
import 'core/security/android_keystore_token_store.dart';
import 'core/security/secure_token_store.dart';
import 'core/security/security_providers.dart';
import 'core/security/windows_dpapi_token_store.dart';
import 'core/storage/local_database_service.dart';
import 'core/theme/theme_preference_store.dart';
import 'core/theme/theme_provider.dart';
import 'core/utils/user_friendly_error_mapper.dart';
import 'features/backup/backup_providers.dart';
import 'features/diagnostics/application/system_status_notifier.dart';
import 'features/security/data/device_pairing_client.dart';
import 'features/setup/data/local_setup_config_store.dart';
import 'features/setup/setup_providers.dart';
import 'features/shell/presentation/windows/windows_tray_providers.dart';
import 'features/sync/application/hub_connection_notifier.dart';
import 'features/sync/data/drive_authorized_registry_store.dart';
import 'features/sync/sync_providers.dart';

export 'features/backup/application/background_backup_scheduler.dart'
    show mmsBackgroundBackupEntrypoint;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 0. Önceki çökmeden yarım kalmış bir restore journal'ı varsa DB açılmadan kurtar
  try {
    final defaultDbPath = LocalDatabaseService.resolveDefaultDatabasePath();
    DatabaseBackupEngine.recoverPendingRestoreSync(File(defaultDbPath));
  } catch (e) {
    debugPrint(
      '[Main] Bekleyen restore kurtarma uyarısı: ${UserFriendlyErrorMapper.redactSecrets(e.toString())}',
    );
  }

  // 1. İstemci Yerel SQLite Veritabanını (client_local.db) Başlat
  final localDbService = await LocalDatabaseService.initialize();
  final dataDirectory = Directory(localDbService.dataDirectoryPath);

  // 1.1 Kurulum ve şube/tenant profilini yükle (client_config.json)
  final setupStore = FileSetupConfigStore.inDirectory(dataDirectory);
  var initialSetupConfig = await setupStore.load();

  // 1.2 Geriye dönük uyumluluk: Daha önce outbox kaydı olmadan eklenmiş ürünleri kuyruğa ekle
  try {
    await localDbService.repository.reconcileUnsyncedProducts(
      initialSetupConfig.deviceId,
    );
  } catch (e) {
    debugPrint(
      '[Main] Ürün mutabakatı uyarısı: ${UserFriendlyErrorMapper.redactSecrets(e.toString())}',
    );
  }

  // 1.3 B-3 OS/Donanım destekli güvenli token deposunu başlat ve crash recovery re-pairing uzlaştır
  final SecureTokenStore tokenStore = Platform.isWindows
      ? WindowsDpapiTokenStore.inDirectory(dataDirectory)
      : (Platform.isAndroid
            ? const AndroidKeystoreTokenStore()
            : InMemorySecureTokenStore());

  try {
    final pairingReconciler = DevicePairingClient(
      tokenStore: tokenStore,
      logger: RedactingLogger(),
    );
    await pairingReconciler.reconcileStagedPairingOnStartup(
      deviceId: initialSetupConfig.deviceId,
      onPromoteTlsPinning: (sha256Hex, caPem) async {
        final promoted = initialSetupConfig.copyWith(
          tlsPinningEnabled: true,
          pinnedCaSha256: sha256Hex,
          pinnedCaPem: caPem,
          updatedAt: DateTime.now().toUtc(),
        );
        await setupStore.save(promoted);
        initialSetupConfig = promoted;
      },
      onPromoteHubUrl: (hubUrl) async {
        await localDbService.repository.saveStoredHubConnection(
          hubUrl: hubUrl,
          source: HubUrlSource.manual,
          allowLoopback: HubConnectionBootstrapper.defaultAllowLoopbackForPlatform(),
          now: DateTime.now().toUtc(),
        );
      },
    );
  } catch (e) {
    debugPrint(
      '[Main] Bekleyen re-pairing uzlaştırma uyarısı: ${UserFriendlyErrorMapper.redactSecrets(e.toString())}',
    );
  }

  String? initialStoredToken;
  try {
    initialStoredToken =
        await tokenStore.readDeviceToken(initialSetupConfig.deviceId);
  } catch (e) {
    debugPrint(
      '[Main] Güvenli token okuma uyarısı: ${UserFriendlyErrorMapper.redactSecrets(e.toString())}',
    );
  }

  // 1.4 Kalıcı Hub bağlantı yapılandırmasını platform güvenlik politikasıyla yükle
  final initialHubConnectionState =
      await HubConnectionBootstrapper.loadInitialState(
    repository: localDbService.repository,
  );

  // 1.5 Kalıcı tema tercihini ve yetkili Drive cihaz kayıt defterini yükle
  final themeStore = FileThemePreferenceStore.inDirectory(dataDirectory);
  final initialThemeMode = await themeStore.load();
  final registryStore =
      FileDriveAuthorizedRegistryStore.inDirectory(dataDirectory);
  final initialRegistry = await registryStore.load();

  // 2. Kök Uygulamayı Riverpod ProviderScope ile Başlat
  final autoDiscoveryEnabled =
      !HubConnectionBootstrapper.defaultAllowLoopbackForPlatform();

  runApp(
    ProviderScope(
      overrides: [
        localDatabaseServiceProvider.overrideWithValue(localDbService),
        setupConfigStoreProvider.overrideWithValue(setupStore),
        initialSetupConfigProvider.overrideWithValue(initialSetupConfig),
        setupWizardBannerEnabledProvider.overrideWithValue(true),
        secureTokenStoreProvider.overrideWithValue(tokenStore),
        initialStoredDeviceTokenProvider.overrideWithValue(initialStoredToken),
        initialHubConnectionStateProvider
            .overrideWithValue(initialHubConnectionState),
        hubAutoDiscoveryLifecycleEnabledProvider
            .overrideWithValue(autoDiscoveryEnabled),
        backupAutoScheduleLifecycleEnabledProvider.overrideWithValue(true),
        windowsTrayLifecycleEnabledProvider
            .overrideWithValue(Platform.isWindows),
        themePreferenceStoreProvider.overrideWithValue(themeStore),
        initialThemeModeProvider.overrideWithValue(initialThemeMode),
        driveAuthorizedRegistryStoreProvider.overrideWithValue(registryStore),
        initialDriveAuthorizedRegistryProvider
            .overrideWithValue(initialRegistry),
      ],
      child: const MarketPosApp(),
    ),
  );
}
