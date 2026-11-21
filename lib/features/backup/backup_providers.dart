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
import '../sync/sync_providers.dart';
import 'application/backup_schedule_controller.dart';
import 'application/client_backup_service.dart';
import 'application/google_drive_connect_service.dart';

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

/// Faz 7D: Google Cloud OAuth "Desktop app" istemci kimliği. Owner tarafından
/// oluşturulup derlemede `--dart-define=MMS_GDRIVE_CLIENT_ID=...` ile verilir.
/// Boşsa Drive yedeği devre dışıdır (BLOCKED: dış kaynak).
const String kGoogleDriveClientId = String.fromEnvironment('MMS_GDRIVE_CLIENT_ID');
const String kGoogleDriveClientSecret = String.fromEnvironment('MMS_GDRIVE_CLIENT_SECRET');

final googleDriveConnectServiceProvider = Provider<GoogleDriveConnectService>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return GoogleDriveConnectService(
    clientId: kGoogleDriveClientId,
    clientSecret: kGoogleDriveClientSecret.isEmpty ? null : kGoogleDriveClientSecret,
    secureStore: ref.watch(secureTokenStoreProvider),
    httpClient: client,
  );
});

final driveUploadLedgerProvider = Provider<DriveUploadLedger>((ref) {
  final dbService = ref.watch(localDatabaseServiceProvider);
  return DriveUploadLedger(File(p.join(dbService.dataDirectoryPath, 'drive_upload_ledger.json')));
});

/// Drive yapılandırılmamışsa `null`; yerel yedekleme bundan etkilenmez.
final googleDriveUploaderProvider = Provider<GoogleDriveBackupUploader?>((ref) {
  final connect = ref.watch(googleDriveConnectServiceProvider);
  if (!connect.isConfigured) return null;
  final secureStore = ref.watch(secureTokenStoreProvider);
  final client = http.Client();
  ref.onDispose(client.close);
  return GoogleDriveBackupUploader(
    tokenProvider: GoogleOAuthRefreshTokenProvider(
      clientId: connect.clientId,
      clientSecret: connect.clientSecret,
      readRefreshToken: () => secureStore.readSecret(GoogleDriveConnectService.refreshTokenSecretKey),
      httpClient: client,
    ),
    httpClient: client,
    ledger: ref.watch(driveUploadLedgerProvider),
  );
});

/// Faz 3: Zamanlanmış yerel yedek denetleyicisi. Başarılı yerel yedekten sonra (Drive
/// bağlıysa) henüz yüklenmemiş son 3 yedek Drive'a gönderilir; Drive hatası yerel
/// yedeği başarısız yapmaz.
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
    afterSuccess: (_) async {
      final uploader = ref.read(googleDriveUploaderProvider);
      if (uploader == null) return;
      if (!await ref.read(googleDriveConnectServiceProvider).isConnected()) return;
      final local = await backupService.listBackups();
      await uploader.uploadPending([
        for (final b in local.take(3)) (file: b.file, manifest: b.manifest),
      ]);
    },
  );
  if (dbService.databasePath != ':memory:') {
    controller.initialize();
  }
  return controller;
});
