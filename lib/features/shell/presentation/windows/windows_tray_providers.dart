import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../backup/backup_providers.dart';
import '../../../diagnostics/application/system_status_notifier.dart';
import '../../../sync/sync_providers.dart';
import '../../shell_providers.dart';
import 'windows_desktop_shell_gateway.dart';
import 'windows_tray_controller.dart';
import 'windows_tray_models.dart';

/// Windows Sistem Tepsisi yaşam döngüsünün otomatik başlatılıp başlatılmayacağı
/// (`main.dart` içinde yalnızca Windows üzerinde `true` olarak override edilir).
final windowsTrayLifecycleEnabledProvider = Provider<bool>((ref) => false);

final windowsDesktopShellGatewayProvider =
    Provider<WindowsDesktopShellGateway>((ref) {
  final enabled = ref.watch(windowsTrayLifecycleEnabledProvider);
  if (enabled && Platform.isWindows) {
    return MethodChannelWindowsDesktopShellGateway();
  }
  return const NoopWindowsDesktopShellGateway();
});

final windowsTrayControllerProvider =
    StateNotifierProvider<WindowsTrayController, WindowsTrayState>((ref) {
  final gateway = ref.watch(windowsDesktopShellGatewayProvider);
  final dbService = ref.watch(localDatabaseServiceProvider);

  final controller = WindowsTrayController(
    gateway: gateway,
    onNavigate: (destination) {
      ref.read(activeDestinationProvider.notifier).state = destination;
    },
    onPauseSyncForExit: () async {
      await ref
          .read(backgroundSyncCoordinatorProvider.notifier)
          .pauseForMaintenance(timeout: const Duration(seconds: 5));
    },
    onWaitBackupIdleForExit: () async {
      await ref
          .read(backupScheduleControllerProvider.notifier)
          .waitForIdle()
          .timeout(const Duration(seconds: 5), onTimeout: () {});
    },
    onCloseDatabaseForExit: () async {
      await dbService.close();
    },
  );

  if (gateway.isSupported) {
    unawaited(controller.initialize());
  }

  return controller;
});
