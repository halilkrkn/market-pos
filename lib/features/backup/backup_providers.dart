import 'dart:io';

import 'package:flutter/foundation.dart';
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
import 'application/background_backup_scheduler.dart';
import 'application/backup_schedule_controller.dart';
import 'application/client_backup_service.dart';
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
    afterSuccess: (_) async {
      final uploader = ref.read(googleDriveUploaderProvider);
      if (uploader == null) return;
      try {
        if (!await ref.read(googleDriveConnectServiceProvider).isConnected()) {
          return;
        }
        final local = await backupService.listBackups();
        await uploader.uploadPending([
          for (final b in local.take(3)) (file: b.file, manifest: b.manifest),
        ]);
      } catch (e) {
        // ADR-022 fail-safe: arka plan yerel yedekleme başarısı Drive/OAuth
        // hatasından etkilenmez; bir sonraki ön plan açılışında tekrar denenir.
        final redacted = ref.read(redactingLoggerProvider).redact(e.toString());
        debugPrint('[BackupSchedule] Drive yüklemesi atlandı (yerel yedek korundu): $redacted');
      }
    },
  );
  if (dbService.databasePath != ':memory:') {
    controller.initialize();
  }
  return controller;
});
