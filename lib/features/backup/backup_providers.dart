import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

import '../../core/security/security_providers.dart';

import '../catalog/catalog_providers.dart';
import '../dashboard/dashboard_providers.dart';
import '../diagnostics/application/system_status_notifier.dart';
import '../sales/sales_providers.dart';
import '../setup/setup_providers.dart';
import '../stock/stock_providers.dart';
import '../sync/application/hub_connection_notifier.dart';
import '../sync/sync_providers.dart';
import 'application/background_backup_scheduler.dart';
import 'application/backup_schedule_controller.dart';
import 'application/client_backup_service.dart';
import 'application/hub_backup_oauth_handoff_service.dart';
import 'data/hub_backup_client.dart';
import 'drive_auth_providers.dart';

export 'drive_auth_providers.dart';

/// Yerel şifreli yedek dosyalarının saklanacağı klasör.
final backupRootDirectoryProvider = Provider<Directory>((ref) {
  final dbService = ref.watch(localDatabaseServiceProvider);
  return Directory(p.join(dbService.dataDirectoryPath, 'backups'));
});

/// PBKDF2-HMAC-SHA256 iterasyon sayısı (üretimde 600.000; testlerde override edilebilir).
final backupKdfIterationsProvider = Provider<int>((ref) {
  return BackupCryptoService.defaultPbkdf2Iterations;
});

final clientBackupServiceProvider = Provider<ClientBackupService>((ref) {
  final dbService = ref.watch(localDatabaseServiceProvider);
  final rootDir = ref.watch(backupRootDirectoryProvider);
  final kdfIterations = ref.watch(backupKdfIterationsProvider);

  return ClientBackupService(
    dbService: dbService,
    backupRootDir: rootDir,
    readSetupConfig: () => ref.read(setupConfigProvider),
    kdfIterations: kdfIterations,
    pauseSync: () =>
        ref.read(backgroundSyncCoordinatorProvider.notifier).pauseForMaintenance(),
    resumeSync: () =>
        ref.read(backgroundSyncCoordinatorProvider.notifier).resumeAfterMaintenance(),
  );
});

final backupListProvider = FutureProvider<List<BackupPackageInfo>>((ref) async {
  final service = ref.watch(clientBackupServiceProvider);
  return service.listBackups();
});

/// Geri yükleme sonrası yerel veriyi tüketen tüm Riverpod provider'larını yeniler.
void invalidatePostRestoreProviders(WidgetRef ref) {
  ref.invalidate(backupListProvider);
  ref.invalidate(systemStatusProvider);
  ref.invalidate(catalogProvider);
  ref.invalidate(salesHistoryProvider);
  ref.invalidate(stockOverviewProvider);
  ref.invalidate(dashboardSnapshotProvider);
}

final driveUploadLedgerProvider = Provider<DriveUploadLedger>((ref) {
  final dbService = ref.watch(localDatabaseServiceProvider);
  return DriveUploadLedger(File(p.join(dbService.dataDirectoryPath, 'drive_upload_ledger.json')));
});

/// Drive yapılandırılmamışsa `null`; yerel yedekleme bundan etkilenmez.
final googleDriveUploaderProvider = Provider<GoogleDriveBackupUploader?>((ref) {
  final tokenProvider = ref.watch(driveAccessTokenProvider);
  if (tokenProvider == null) return null;
  final client = http.Client();
  ref.onDispose(client.close);
  return GoogleDriveBackupUploader(
    tokenProvider: tokenProvider,
    httpClient: client,
    ledger: ref.watch(driveUploadLedgerProvider),
  );
});

final backgroundBackupSchedulerProvider =
    Provider<BackgroundBackupScheduler>((ref) {
  return const MethodChannelBackgroundBackupScheduler();
});

/// Uygulama açılışında zamanlanmış yerel / Android arka plan yedek denetleyicisinin
/// otomatik başlatılıp başlatılmayacağını denetler (`main.dart` içinde `true` yapılır).
final backupAutoScheduleLifecycleEnabledProvider = Provider<bool>((ref) {
  return false;
});

/// Faz 3 / ADR-020: Zamanlanmış yerel ve Android arka plan yedek denetleyicisi.
final backupScheduleControllerProvider =
    StateNotifierProvider<BackupScheduleController, BackupScheduleViewState>((ref) {
  final dbService = ref.watch(localDatabaseServiceProvider);
  final backupService = ref.watch(clientBackupServiceProvider);
  final controller = BackupScheduleController(
    backupService: backupService,
    secureStore: ref.watch(secureTokenStoreProvider),
    settingsStore: ClientBackupScheduleSettingsStore(
      File(p.join(dbService.dataDirectoryPath, 'backup_schedule_settings.json')),
    ),
    stateStore: BackupScheduleStateStore(
      File(p.join(dbService.dataDirectoryPath, 'backup_schedule_state.json')),
    ),
    backgroundScheduler: ref.watch(backgroundBackupSchedulerProvider),
  );
  if (dbService.databasePath != ':memory:') {
    controller.initialize();
  }
  return controller;
});

/// `OV-04`: Cihazın Master Hub üzerinden doğrulanmış rolü (`OWNER` veya `CASHIER`).
/// Token yoksa, süresi dolmuşsa veya Hub doğrulanamazsa fail-closed `CASHIER` döner.
final hubBackupDeviceRoleProvider = Provider<String>((ref) {
  return ref.watch(effectiveDeviceRoleProvider);
});

final hubBackupHttpClientProvider = Provider<http.Client>((ref) {
  return ref.watch(deviceRoleHttpClientProvider);
});

/// Merkezi Hub yedekleme HTTP istemcisi (`X-MMS-Timestamp` + `X-MMS-Nonce` replay korumalı).
final hubBackupClientProvider = Provider<HubBackupClient>((ref) {
  final setup = ref.watch(setupConfigProvider);
  final httpClient = ref.watch(hubBackupHttpClientProvider);
  return HubBackupClient(
    httpClient: httpClient,
    readHubUrl: () => ref.read(hubConnectionProvider).activeHubUrl ?? '',
    readDeviceToken: () => ref.read(effectiveDeviceTokenProvider),
    tenantId: setup.tenantId,
    storeId: setup.storeId,
  );
});

/// Windows masaüstü PKCE -> Hub DPAPI devir istemcisi (`OV-01`, `OV-02`).
final hubBackupOAuthHandoffServiceProvider =
    Provider<HubBackupOAuthHandoffService>((ref) {
  final client = ref.watch(hubBackupHttpClientProvider);
  final backupClient = ref.watch(hubBackupClientProvider);
  final isAndroid = ref.watch(driveIsAndroidPlatformProvider);
  final clientId = ref.watch(googleDriveClientIdProvider);
  final clientSecret = ref.watch(googleDriveClientSecretProvider);

  return HubBackupOAuthHandoffService(
    clientId: clientId,
    clientSecret: clientSecret.isEmpty ? null : clientSecret,
    readHubUrl: () => ref.read(hubConnectionProvider).activeHubUrl ?? '',
    buildAuthHeaders: () {
      final token = ref.read(effectiveDeviceTokenProvider);
      final setup = ref.read(setupConfigProvider);
      return {
        if (token != null && token.isNotEmpty) 'authorization': 'Bearer $token',
        'x-mms-tenant-id': setup.tenantId,
        'x-mms-store-id': setup.storeId,
        ...backupClient.buildReplayHeaders(),
      };
    },
    httpClient: client,
    isWindowsOverride: Platform.isWindows && !isAndroid,
  );
});
