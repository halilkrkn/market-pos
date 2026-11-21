import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import 'app/app.dart';
import 'core/security/android_keystore_token_store.dart';
import 'core/security/secure_token_store.dart';
import 'core/security/security_providers.dart';
import 'core/security/windows_dpapi_token_store.dart';
import 'core/storage/local_database_service.dart';
import 'features/diagnostics/application/system_status_notifier.dart';
import 'features/setup/data/local_setup_config_store.dart';
import 'features/setup/setup_providers.dart';
import 'features/sync/application/hub_connection_notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 0. Önceki çökmeden yarım kalmış bir restore journal'ı varsa DB açılmadan kurtar
  try {
    final defaultDbPath = LocalDatabaseService.resolveDefaultDatabasePath();
    DatabaseBackupEngine.recoverPendingRestoreSync(File(defaultDbPath));
  } catch (e) {
    debugPrint('[Main] Bekleyen restore kurtarma uyarısı: $e');
  }

  // 1. İstemci Yerel SQLite Veritabanını (client_local.db) Başlat
  final localDbService = await LocalDatabaseService.initialize();
  final dataDirectory = Directory(localDbService.dataDirectoryPath);

  // 1.1 Kurulum ve şube/tenant profilini yükle (client_config.json)
  final setupStore = FileSetupConfigStore.inDirectory(dataDirectory);
  final initialSetupConfig = await setupStore.load();

  // 1.2 Geriye dönük uyumluluk: Daha önce outbox kaydı olmadan eklenmiş ürünleri kuyruğa ekle
  try {
    await localDbService.repository.reconcileUnsyncedProducts(
      initialSetupConfig.deviceId,
    );
  } catch (e) {
    debugPrint('[Main] Ürün mutabakatı uyarısı: $e');
  }

  // 1.3 B-3 OS/Donanım destekli güvenli token deposunu başlat ve cihaz token'ını yükle
  final SecureTokenStore tokenStore = Platform.isWindows
      ? WindowsDpapiTokenStore.inDirectory(dataDirectory)
      : (Platform.isAndroid
            ? const AndroidKeystoreTokenStore()
            : InMemorySecureTokenStore());
  String? initialStoredToken;
  try {
    initialStoredToken =
        await tokenStore.readDeviceToken(initialSetupConfig.deviceId);
  } catch (e) {
    debugPrint('[Main] Güvenli token okuma uyarısı: $e');
  }

  // 1.4 Kalıcı Hub bağlantı yapılandırmasını platform güvenlik politikasıyla yükle
  final initialHubConnectionState =
      await HubConnectionBootstrapper.loadInitialState(
    repository: localDbService.repository,
  );

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
      ],
      child: const MarketPosApp(),
    ),
  );
}
