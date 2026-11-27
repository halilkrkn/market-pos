import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/features/backup/application/backup_schedule_controller.dart';
import 'package:market_pos/features/diagnostics/domain/system_status.dart';
import 'package:market_pos/features/shell/domain/app_destination.dart';
import 'package:market_pos/features/shell/presentation/windows/windows_desktop_shell_gateway.dart';
import 'package:market_pos/features/shell/presentation/windows/windows_tray_controller.dart';
import 'package:market_pos/features/shell/presentation/windows/windows_tray_models.dart';
import 'package:market_pos/features/sync/domain/hub_connection_state.dart';
import 'package:market_pos/features/sync/domain/sync_coordinator_state.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

class _FakeWindowsShellGateway implements WindowsDesktopShellGateway {
  final List<String> calls = <String>[];
  final List<WindowsTrayStatusSnapshot> pushedSnapshots =
      <WindowsTrayStatusSnapshot>[];
  Future<void> Function(WindowsTrayMenuAction action)? actionHandler;

  bool initReturn = true;
  bool autoStartValue = false;
  bool setAutoStartReturn = true;
  bool throwOnSetAutoStart = false;

  @override
  bool get isSupported => true;

  @override
  void setActionHandler(
    Future<void> Function(WindowsTrayMenuAction action)? handler,
  ) {
    actionHandler = handler;
  }

  @override
  Future<bool> initializeTray() async {
    calls.add('initializeTray');
    return initReturn;
  }

  @override
  Future<void> updateTrayStatus(WindowsTrayStatusSnapshot snapshot) async {
    calls.add('updateTrayStatus');
    pushedSnapshots.add(snapshot);
  }

  @override
  Future<void> showWindow() async {
    calls.add('showWindow');
  }

  @override
  Future<void> hideToTray() async {
    calls.add('hideToTray');
  }

  @override
  Future<void> confirmExit() async {
    calls.add('confirmExit');
  }

  @override
  Future<bool> getAutoStartEnabled() async {
    calls.add('getAutoStartEnabled');
    return autoStartValue;
  }

  @override
  Future<bool> setAutoStartEnabled(bool enabled) async {
    calls.add('setAutoStartEnabled:$enabled');
    if (throwOnSetAutoStart) {
      throw StateError('Registry write blocked');
    }
    if (setAutoStartReturn) {
      autoStartValue = enabled;
    }
    return setAutoStartReturn;
  }
}

void main() {
  group('WindowsTrayStatusFormatter', () {
    test('gerçek durumlara göre sahte başarı göstermeden Türkçe etiket üretir', () {
      final offlineSnap = WindowsTrayStatusFormatter.format(
        systemStatus: SystemStatus.initial().copyWith(
          backendState: BackendConnectionState.offline,
          outboxSummary: const OutboxSummary(
            pending: 3,
            retry: 1,
            inProgress: 0,
            failedPermanent: 0,
          ),
        ),
        hubConnection: const HubConnectionState(
          phase: HubConnectionPhase.offline,
          activeHubUrl: 'https://127.0.0.1:8945',
          isInitialized: true,
        ),
        syncState: SyncCoordinatorState.initial().copyWith(
          status: SyncCoordinatorStatus.networkError,
        ),
        backupState: BackupScheduleViewState.initial,
      );

      expect(offlineSnap.hubStatusLabel, equals('Hub Durumu: Çevrimdışı'));
      expect(
        offlineSnap.syncStatusLabel,
        equals('Senkronizasyon Durumu: Bekleyen (4)'),
      );
      expect(
        offlineSnap.backupStatusLabel,
        equals('Yedekleme Durumu: Otomatik Yedek Kapalı'),
      );

      final tlsMismatchSnap = WindowsTrayStatusFormatter.format(
        systemStatus: SystemStatus.initial().copyWith(
          backendState: BackendConnectionState.tlsPinMismatch,
        ),
        hubConnection: const HubConnectionState(
          phase: HubConnectionPhase.offline,
          activeHubUrl: 'https://127.0.0.1:8945',
          isInitialized: true,
        ),
        syncState: SyncCoordinatorState.initial().copyWith(
          status: SyncCoordinatorStatus.tlsPinMismatch,
        ),
        backupState: BackupScheduleViewState(
          settings: const ClientBackupScheduleSettings(
            enabled: true,
            intervalHours: 24,
          ),
          scheduleState: BackupScheduleState(
            lastSuccessAt:
                DateTime.now().toUtc().subtract(const Duration(hours: 40)),
          ),
        ),
      );

      expect(
        tlsMismatchSnap.hubStatusLabel,
        equals('Hub Durumu: TLS Pin Hatası'),
      );
      expect(
        tlsMismatchSnap.syncStatusLabel,
        equals('Senkronizasyon Durumu: TLS Pin Hatası'),
      );
      expect(
        tlsMismatchSnap.backupStatusLabel,
        equals('Yedekleme Durumu: Gecikmiş (24s)'),
      );
    });
  });

  group('WindowsTrayController', () {
    test('başlatmada otomatik başlatmayı kendiliğinden açmaz ve durumu okur', () async {
      final gw = _FakeWindowsShellGateway();
      final controller = WindowsTrayController(
        gateway: gw,
        onNavigate: (_) {},
        onPauseSyncForExit: () async {},
        onWaitBackupIdleForExit: () async {},
        onCloseDatabaseForExit: () async {},
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      expect(controller.state.isSupported, isTrue);
      expect(controller.state.isTrayActive, isTrue);
      expect(controller.state.autoStartEnabled, isFalse);
      expect(
        gw.calls,
        equals(['initializeTray', 'getAutoStartEnabled']),
      );
    });

    test('durum itme (pushStatus) aynı anlık görüntüyü mükerrer göndermez', () async {
      final gw = _FakeWindowsShellGateway();
      final controller = WindowsTrayController(
        gateway: gw,
        onNavigate: (_) {},
        onPauseSyncForExit: () async {},
        onWaitBackupIdleForExit: () async {},
        onCloseDatabaseForExit: () async {},
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      const snap = WindowsTrayStatusSnapshot(
        hubStatusLabel: 'Hub Durumu: Çevrimiçi',
        syncStatusLabel: 'Senkronizasyon Durumu: Güncel',
        backupStatusLabel: 'Yedekleme Durumu: Kapalı',
        tooltip: 'MARKET MMS',
      );
      await controller.pushStatus(snap);
      await controller.pushStatus(snap);

      expect(gw.pushedSnapshots.length, equals(1));
    });

    test('sağ tık menü eylemleri doğru ekrana yönlendirir ve pencereyi açar', () async {
      final gw = _FakeWindowsShellGateway();
      final destinations = <AppDestination>[];
      final controller = WindowsTrayController(
        gateway: gw,
        onNavigate: destinations.add,
        onPauseSyncForExit: () async {},
        onWaitBackupIdleForExit: () async {},
        onCloseDatabaseForExit: () async {},
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      await gw.actionHandler!(WindowsTrayMenuAction.openApp);
      await gw.actionHandler!(WindowsTrayMenuAction.openHubStatus);
      await gw.actionHandler!(WindowsTrayMenuAction.openSyncStatus);
      await gw.actionHandler!(WindowsTrayMenuAction.openBackupStatus);
      await gw.actionHandler!(WindowsTrayMenuAction.openSettings);

      expect(
        destinations,
        equals([
          AppDestination.diagnostics,
          AppDestination.diagnostics,
          AppDestination.diagnostics,
          AppDestination.diagnostics,
        ]),
      );
      expect(
        gw.calls.where((c) => c == 'showWindow').length,
        equals(5),
      );
    });

    test('otomatik başlatma kullanıcı isteğiyle açılıp kapatılır ve hata yutulmaz', () async {
      final gw = _FakeWindowsShellGateway();
      final controller = WindowsTrayController(
        gateway: gw,
        onNavigate: (_) {},
        onPauseSyncForExit: () async {},
        onWaitBackupIdleForExit: () async {},
        onCloseDatabaseForExit: () async {},
      );
      addTearDown(controller.dispose);

      await controller.initialize();

      await controller.setAutoStartEnabled(true);
      expect(controller.state.autoStartEnabled, isTrue);
      expect(controller.state.lastError, isNull);

      await controller.setAutoStartEnabled(false);
      expect(controller.state.autoStartEnabled, isFalse);
      expect(controller.state.lastError, isNull);

      gw.throwOnSetAutoStart = true;
      await controller.setAutoStartEnabled(true);
      expect(controller.state.autoStartEnabled, isFalse);
      expect(controller.state.lastError, isNotNull);
    });

    test(
      'kontrollü çıkış sırası senkron+yedek+DB kapanışını yürütür ve gerçek FFI SQLite Outbox verisini korur',
      () async {
        final tempDir = Directory.systemTemp.createTempSync('mms_tray_exit_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        final dbPath = p.join(tempDir.path, 'tray_test_client.db');
        final dbService = await LocalDatabaseService.initialize(customPath: dbPath);
        await dbService.repository.initializeDevice('POS-TRAY-TEST');
        final product = await dbService.repository.createProduct(
          name: 'Tepsi Test Ürünü',
          price: 1500,
          barcode: '8690000111222',
          initialStock: 10000,
          deviceId: 'POS-TRAY-TEST',
        );
        await dbService.repository.createOfflineSale(
          deviceId: 'POS-TRAY-TEST',
          paymentMethod: 'CASH',
          items: [CartItemInput.units(product.id, 2)],
        );

        final pendingBefore = await dbService.getPendingOutboxCount();
        expect(pendingBefore, equals(2)); // PRODUCT_UPSERT + SALE

        final gw = _FakeWindowsShellGateway();
        final order = <String>[];
        final controller = WindowsTrayController(
          gateway: gw,
          onNavigate: (_) {},
          onPauseSyncForExit: () async => order.add('pauseSync'),
          onWaitBackupIdleForExit: () async => order.add('waitBackup'),
          onCloseDatabaseForExit: () async {
            order.add('closeDb');
            await dbService.close();
          },
        );
        addTearDown(controller.dispose);

        await controller.initialize();

        // Eşzamanlı ikinci çağrı re-entrancy korumasıyla tekilleşir
        await Future.wait([
          gw.actionHandler!(WindowsTrayMenuAction.requestExit),
          controller.performControlledExit(),
        ]);

        expect(order, equals(['pauseSync', 'waitBackup', 'closeDb']));
        expect(gw.calls.where((c) => c == 'confirmExit').length, equals(1));
        expect(dbService.isClosed, isTrue);

        // Yeniden açıldığında Outbox ve satış kayıtları %100 korunmuş olmalı
        final reopened = await LocalDatabaseService.initialize(customPath: dbPath);
        addTearDown(() => reopened.close());
        expect(await reopened.getPendingOutboxCount(), equals(2));
        expect(await reopened.getLocalSalesCount(), equals(1));
      },
    );
  });
}
