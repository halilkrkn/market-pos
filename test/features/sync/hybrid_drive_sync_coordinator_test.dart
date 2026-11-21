import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/core/theme/app_theme.dart';
import 'package:market_pos/features/diagnostics/domain/system_status.dart';
import 'package:market_pos/features/diagnostics/presentation/screens/diagnostics_view.dart';
import 'package:market_pos/features/sync/application/background_sync_coordinator.dart';
import 'package:market_pos/features/sync/domain/sync_coordinator_state.dart';
import 'package:market_pos/features/sync/sync_providers.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

class _ControllableHubTransport implements SyncTransport {
  SyncResponse nextSaleResponse = const SyncResponse(
    statusCode: 201,
    body: '{"status":"COMMITTED"}',
  );
  SyncResponse nextProductsResponse = const SyncResponse(
    statusCode: 200,
    body: '{"products":[],"sync_session_id":"s1"}',
  );
  SyncResponse nextSalesDownlinkResponse = const SyncResponse(
    statusCode: 200,
    body: '{"status":"OK","sales":[],"next_cursor":0,"has_more":false}',
  );
  int hubCalls = 0;

  @override
  Future<SyncResponse> postSale({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    hubCalls++;
    return nextSaleResponse;
  }

  @override
  Future<SyncResponse> postProductUpsert({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    hubCalls++;
    return nextSaleResponse;
  }

  @override
  Future<SyncResponse> postStockReceipt({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    hubCalls++;
    return nextSaleResponse;
  }

  @override
  Future<SyncResponse> getProducts({
    required String hubUrl,
    required String token,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    hubCalls++;
    return nextProductsResponse;
  }

  @override
  Future<SyncResponse> getSales({
    required String hubUrl,
    required String token,
    int cursor = 0,
    int limit = 50,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    hubCalls++;
    return nextSalesDownlinkResponse;
  }

  @override
  Future<SyncResponse> postSyncAck({
    required String hubUrl,
    required String token,
    required String syncSessionId,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return const SyncResponse(statusCode: 200, body: '{"status":"ACK"}');
  }

  @override
  void close() {}
}

class _InMemoryCoordDriveTransport implements DriveLiveEnvelopeTransport {
  final Map<String, ({String fileName, Uint8List bytes, Map<String, String> appProperties})>
      stored = {};
  int uploadCalls = 0;
  int listCalls = 0;
  int _seq = 0;
  bool failNext = false;

  @override
  Future<String> ensureSyncFolder() async {
    if (failNext) throw const DriveBackupException('ERR_DRIVE_UNAVAILABLE', 'Offline Drive');
    return 'drive-live-folder';
  }

  @override
  Future<String> uploadEnvelope({
    required String folderId,
    required String fileName,
    required Uint8List bytes,
    required Map<String, String> appProperties,
  }) async {
    uploadCalls++;
    if (failNext) throw const DriveBackupException('ERR_DRIVE_UNAVAILABLE', 'Upload error');
    final id = 'env_${++_seq}';
    stored[id] = (
      fileName: fileName,
      bytes: Uint8List.fromList(bytes),
      appProperties: Map<String, String>.from(appProperties),
    );
    return id;
  }

  @override
  Future<List<DriveRemoteEnvelopeEntry>> listEnvelopes({
    required String folderId,
    required String tenantId,
    required String storeId,
  }) async {
    listCalls++;
    if (failNext) throw const DriveBackupException('ERR_DRIVE_UNAVAILABLE', 'List error');
    return [
      for (final e in stored.entries)
        if (DriveRemoteEnvelopeEntry.tryParse({
              'id': e.key,
              'name': e.value.fileName,
              'appProperties': e.value.appProperties,
            })
            case final parsed?)
          if (parsed.tenantId == tenantId && parsed.storeId == storeId) parsed,
    ];
  }

  @override
  Future<Uint8List> downloadEnvelope({required String fileId}) async =>
      stored[fileId]!.bytes;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  TestWidgetsFlutterBinding.ensureInitialized();

  const tenantId = 't-coord-1';
  const storeId = 's-coord-1';
  const localDev = 'dev-coord-local';
  const liveSecret = 'CoordLiveSecret_2026!';

  group('ADR-021 §6.6–6.7 Senaryolar 24–26 — Coordinator Hibrit Geçişler & 10 UI Durumu', () {
    test('S24–S25: HubPrimary/DriveStandby -> HubOfflineConfirmed -> DriveFallbackActive/Synced -> HubReconciling -> HubReconciled',
        () async {
      final tmp = Directory.systemTemp.createTempSync('mms_hybrid_coord_');
      final db = ClientDatabase.forTesting(NativeDatabase.memory());
      final repo = ClientStorageRepository(db);
      final driveTransport = _InMemoryCoordDriveTransport();
      final hubTransport = _ControllableHubTransport();
      final registry = DriveAuthorizedDeviceRegistry()
        ..authorizeDevice(deviceId: localDev, tenantId: tenantId, storeId: storeId)
        ..authorizeDevice(deviceId: 'dev-peer', tenantId: tenantId, storeId: storeId);

      final engine = MmsDriveLiveSyncEngine(
        repository: repo,
        transport: driveTransport,
        ledger: DriveLiveSyncLedger(File(p.join(tmp.path, 'ledger.json'))),
        deviceRegistry: registry,
        tenantId: tenantId,
        storeId: storeId,
        localDeviceId: localDev,
        readLiveSyncSecret: () async => liveSecret,
        kdfIterations: 100,
      );

      final coordinator = BackgroundSyncCoordinator(
        repository: repo,
        transport: hubTransport,
        deviceId: localDev,
        readDeviceToken: () => 'tok-valid',
        hubUrl: 'https://127.0.0.1:8443',
        syncServiceFactory: ({
          required repository,
          required transport,
          required deviceId,
          required deviceToken,
          readDeviceToken,
          required hubUrl,
        }) =>
            ClientSyncService(
          repository: repository,
          transport: transport,
          deviceId: deviceId,
          deviceToken: deviceToken,
          readDeviceToken: readDeviceToken,
          hubUrl: hubUrl,
          baseBackoff: Duration.zero,
          maxBackoff: Duration.zero,
        ),
        driveLiveSyncEngine: engine,
        isDriveFallbackStandby: true,
        autoStartTimer: false,
        enableLifecycleListener: false,
      );

      final observedStates = <HybridDriveSyncUiStatus>[];
      final sub = coordinator.addListener(
        (s) => observedStates.add(s.driveSyncUiStatus),
        fireImmediately: true,
      );

      addTearDown(() async {
        sub();
        coordinator.dispose();
        await db.close();
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });

      await repo.upsertProducts([
        LocalProductsCompanion(
          id: const Value('prod_1'),
          barcode: const Value('8690001'),
          name: const Value('Ekmek'),
          price: const Value(1000),
          stock: const Value(50000),
          updatedAt: Value(DateTime.utc(2026, 11, 21, 10, 0)),
        ),
      ]);

      // Başlangıçta standby
      expect(observedStates.first, HybridDriveSyncUiStatus.driveStandby);

      // 1. Hub kesintisi (1. deneme): eşik (2) aşılmadığı için hubOfflineConfirmed, Drive trafik = 0
      hubTransport.nextProductsResponse =
          const SyncResponse(statusCode: 503, body: '', errorMessage: 'Hub ulaşılamıyor');
      await coordinator.triggerSync(reason: SyncTriggerReason.manual);
      expect(coordinator.state.driveSyncUiStatus, HybridDriveSyncUiStatus.hubOfflineConfirmed);
      expect(driveTransport.uploadCalls, 0);
      expect(driveTransport.listCalls, 0);

      // Yerel satış üret (offline) -> Outbox PENDING (client_seq = 1)
      await repo.createOfflineSale(
        deviceId: localDev,
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_1', 1)],
      );

      // 2. Hub kesintisi (2. deneme): eşik aşıldı -> DriveFallbackActive -> DriveSyncing -> DriveSynced
      hubTransport.nextSaleResponse =
          const SyncResponse(statusCode: 503, body: '', errorMessage: 'Hub hala kapalı');
      await coordinator.triggerSync(reason: SyncTriggerReason.manual);
      expect(observedStates, containsAllInOrder([
        HybridDriveSyncUiStatus.driveStandby,
        HybridDriveSyncUiStatus.hubOfflineConfirmed,
        HybridDriveSyncUiStatus.driveFallbackActive,
        HybridDriveSyncUiStatus.driveSyncing,
        HybridDriveSyncUiStatus.driveSynced,
      ]));
      expect(driveTransport.uploadCalls, 1);

      // CRITICAL INVARIANT: Yerel Outbox Hub ACK görmeden SYNCED OLMAMALI!
      expect(await repo.getUnsyncedOutboxOperations(localDev), hasLength(1));

      // 3. Drive geçici hata -> driveOfflineError
      driveTransport.failNext = true;
      await coordinator.triggerSync(reason: SyncTriggerReason.manual);
      expect(coordinator.state.driveSyncUiStatus, HybridDriveSyncUiStatus.driveOfflineError);
      driveTransport.failNext = false;

      // 4. Master Hub geri döner -> hubReconciling -> hubReconciled ve Outbox SYNCED!
      hubTransport.nextSaleResponse = const SyncResponse(
        statusCode: 201,
        body: '{"status":"COMMITTED"}',
      );
      hubTransport.nextProductsResponse = const SyncResponse(
        statusCode: 200,
        body: '{"products":[],"sync_session_id":"s-rec-1"}',
      );
      await coordinator.triggerSync(reason: SyncTriggerReason.connectivityRestored);
      expect(observedStates, containsAllInOrder([
        HybridDriveSyncUiStatus.hubReconciling,
        HybridDriveSyncUiStatus.hubReconciled,
      ]));
      expect(coordinator.state.driveSyncUiStatus, HybridDriveSyncUiStatus.hubReconciled);
      expect(await repo.getUnsyncedOutboxOperations(localDev), isEmpty);
    });

    test('S25b: TLS Pin ve Auth reddi güvenlik durdurmalarında ASLA Drive fallback açılmaz', () async {
      final tmp = Directory.systemTemp.createTempSync('mms_hybrid_sec_');
      final db = ClientDatabase.forTesting(NativeDatabase.memory());
      final repo = ClientStorageRepository(db);
      final driveTransport = _InMemoryCoordDriveTransport();
      final hubTransport = _ControllableHubTransport();
      final registry = DriveAuthorizedDeviceRegistry()
        ..authorizeDevice(deviceId: localDev, tenantId: tenantId, storeId: storeId);

      final engine = MmsDriveLiveSyncEngine(
        repository: repo,
        transport: driveTransport,
        ledger: DriveLiveSyncLedger(File(p.join(tmp.path, 'ledger.json'))),
        deviceRegistry: registry,
        tenantId: tenantId,
        storeId: storeId,
        localDeviceId: localDev,
        readLiveSyncSecret: () async => liveSecret,
        kdfIterations: 100,
      );

      final coordinator = BackgroundSyncCoordinator(
        repository: repo,
        transport: hubTransport,
        deviceId: localDev,
        readDeviceToken: () => 'tok-valid',
        hubUrl: 'https://127.0.0.1:8443',
        driveLiveSyncEngine: engine,
        autoStartTimer: false,
        enableLifecycleListener: false,
      );

      addTearDown(() async {
        coordinator.dispose();
        await db.close();
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });

      hubTransport.nextProductsResponse = SyncResponse.tlsPinMismatch(
        const TlsPinMismatchException(host: '127.0.0.1', port: 8443, presentedSha256: 'AA'),
      );
      for (var i = 0; i < 3; i++) {
        await coordinator.triggerSync(reason: SyncTriggerReason.manual);
        expect(coordinator.state.status, SyncCoordinatorStatus.tlsPinMismatch);
        expect(coordinator.state.driveSyncUiStatus, HybridDriveSyncUiStatus.hubPrimary);
      }
      expect(driveTransport.uploadCalls, 0);
      expect(driveTransport.listCalls, 0);
    });

    testWidgets('S26: DiagnosticsView Hibrit / Drive durumunu (10 durum ve çakışma uyarısı) render eder',
        (tester) async {
      for (final uiStatus in HybridDriveSyncUiStatus.values) {
        final conflictCount =
            uiStatus == HybridDriveSyncUiStatus.driveConflictDetected ? 2 : 0;
        final syncState = SyncCoordinatorState.initial().copyWith(
          driveSyncUiStatus: uiStatus,
          driveConflictCount: conflictCount,
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              backgroundSyncCoordinatorProvider.overrideWith((_) {
                throw UnimplementedError();
              }),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) => SingleChildScrollView(
                    child: const DiagnosticsView().buildSyncCoordinatorCardForTest(
                      context,
                      ref,
                      syncState,
                      SystemStatus.initial(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byKey(const Key('diagnostics_drive_live_sync_row')), findsOneWidget);
        expect(find.text(uiStatus.label), findsOneWidget);
        if (conflictCount > 0) {
          expect(find.byKey(const Key('diagnostics_drive_conflict_banner')), findsOneWidget);
        } else {
          expect(find.byKey(const Key('diagnostics_drive_conflict_banner')), findsNothing);
        }
      }
    });
  });
}
