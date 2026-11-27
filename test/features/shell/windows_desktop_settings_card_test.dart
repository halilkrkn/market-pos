import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/core/platform/mms_ui_profile.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/core/theme/app_theme.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:market_pos/features/shell/presentation/windows/windows_desktop_settings_card.dart';
import 'package:market_pos/features/shell/presentation/windows/windows_desktop_shell_gateway.dart';
import 'package:market_pos/features/shell/presentation/windows/windows_tray_controller.dart';
import 'package:market_pos/features/shell/presentation/windows/windows_tray_models.dart';
import 'package:market_pos/features/shell/presentation/windows/windows_tray_providers.dart';
import 'package:drift/native.dart';

class _WidgetTestShellGateway implements WindowsDesktopShellGateway {
  bool autoStart = false;
  int hideCount = 0;
  int confirmExitCount = 0;

  @override
  bool get isSupported => true;

  @override
  void setActionHandler(
    Future<void> Function(WindowsTrayMenuAction action)? handler,
  ) {}

  @override
  Future<bool> initializeTray() async => true;

  @override
  Future<void> updateTrayStatus(WindowsTrayStatusSnapshot snapshot) async {}

  @override
  Future<void> showWindow() async {}

  @override
  Future<void> hideToTray() async {
    hideCount++;
  }

  @override
  Future<void> confirmExit() async {
    confirmExitCount++;
  }

  @override
  Future<bool> getAutoStartEnabled() async => autoStart;

  @override
  Future<bool> setAutoStartEnabled(bool enabled) async {
    autoStart = enabled;
    return true;
  }
}

void main() {
  testWidgets(
    'WindowsDesktopSettingsCard otomatik başlatmayı kullanıcı anahtarıyla yönetir ve kontrollü çıkış sunar',
    (WidgetTester tester) async {
      final db = LocalDatabaseService.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final gw = _WidgetTestShellGateway();

      final controller = WindowsTrayController(
        gateway: gw,
        onNavigate: (_) {},
        onPauseSyncForExit: () async {},
        onWaitBackupIdleForExit: () async {},
        onCloseDatabaseForExit: () async {},
      );
      await controller.initialize();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mmsUiProfileProvider.overrideWithValue(
              const MmsUiProfile.desktop(),
            ),
            localDatabaseServiceProvider.overrideWithValue(db),
            windowsTrayLifecycleEnabledProvider.overrideWithValue(true),
            windowsDesktopShellGatewayProvider.overrideWithValue(gw),
            windowsTrayControllerProvider.overrideWith((ref) => controller),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(
              body: SingleChildScrollView(
                child: WindowsDesktopSettingsCard(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('TEPSİ AKTİF'), findsOneWidget);
      final switchWidget = tester.widget<SwitchListTile>(
        find.byKey(const Key('windows_autostart_switch')),
      );
      expect(switchWidget.value, isFalse);

      // Dokunmatik hedef yüksekliği (>= 48dp)
      final exitSize = tester.getSize(
        find.byKey(const Key('windows_controlled_exit_button')),
      );
      expect(exitSize.height, greaterThanOrEqualTo(48));

      await tester.tap(find.byKey(const Key('windows_autostart_switch')));
      await tester.pumpAndSettle();
      expect(gw.autoStart, isTrue);

      await tester.tap(
        find.byKey(const Key('windows_minimize_to_tray_button')),
      );
      await tester.pumpAndSettle();
      expect(gw.hideCount, equals(1));

      await tester.tap(
        find.byKey(const Key('windows_controlled_exit_button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(gw.confirmExitCount, equals(1));
    },
  );
}
