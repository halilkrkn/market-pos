import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/core/network/api_client.dart';
import 'package:market_pos/core/security/secure_token_store.dart';
import 'package:market_pos/core/security/security_providers.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/core/theme/app_theme.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:market_pos/features/diagnostics/domain/system_status.dart';
import 'package:market_pos/features/diagnostics/presentation/screens/diagnostics_view.dart';
import 'package:market_pos/features/setup/data/local_setup_config_store.dart';
import 'package:market_pos/features/setup/domain/app_setup_config.dart';
import 'package:market_pos/features/setup/setup_providers.dart';
import 'package:market_pos/features/sync/application/hub_connection_notifier.dart';
import 'package:market_pos/features/sync/domain/hub_connection_state.dart';
import 'package:market_pos/features/sync/domain/sync_coordinator_state.dart';
import 'package:market_pos/features/sync/sync_providers.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

class _NoopSyncTransport implements SyncTransport {
  @override
  void close() {}

  @override
  Future<SyncResponse> getProducts({
    required String hubUrl,
    required String token,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(statusCode: 200, body: '{"products":[]}');

  @override
  Future<SyncResponse> getSales({
    required String hubUrl,
    required String token,
    int cursor = 0,
    int limit = 50,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      SyncResponse(
        statusCode: 200,
        body: jsonEncode({'sales': const [], 'next_cursor': cursor, 'has_more': false}),
      );

  @override
  Future<SyncResponse> postProductUpsert({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(statusCode: 200, body: '{"status":"COMMITTED"}');

  @override
  Future<SyncResponse> postSale({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(statusCode: 201, body: '{"status":"COMMITTED"}');

  @override
  Future<SyncResponse> postStockReceipt({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(statusCode: 200, body: '{"status":"COMMITTED"}');

  @override
  Future<SyncResponse> postSyncAck({
    required String hubUrl,
    required String token,
    required String syncSessionId,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(statusCode: 200, body: '{"status":"ACKNOWLEDGED"}');
}

void main() {
  group('AUD-MED-02: DiagnosticsView kalıcı hata Yeniden Dene koruması', () {
    late Directory tempDir;
    late LocalDatabaseService localDb;
    const deviceId = 'POS-UI-RETRY-GUARD';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('mms_diag_retry_guard_');
      localDb = LocalDatabaseService.forTesting(
        NativeDatabase.memory(),
        path: p.join(tempDir.path, 'client_local.db'),
      );
      await localDb.repository.initializeDevice(deviceId);
    });

    tearDown(() async {
      await localDb.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets(
      'ERR_IDEMPOTENCY_* ve ERR_CLIENT_SEQ_GAP kayıtlarında Yeniden Dene düğmesi devre dışıdır; normal kalıcı hatada çalışır',
      (WidgetTester tester) async {
        final now = DateTime.utc(2026, 11, 24, 1, 0);
        await localDb.database.into(localDb.database.outboxOperations).insert(
              OutboxOperationsCompanion.insert(
                operationId: 'op_idem_blocked',
                deviceId: deviceId,
                clientSeq: 1,
                operationType: 'SALE_CREATE',
                payload: '{"operation_id":"op_idem_blocked","client_seq":1}',
                payloadHash:
                    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                occurredAt: now,
                status: const Value('FAILED_PERMANENT'),
                attemptCount: const Value(1),
                lastError: const Value(
                  'Kalıcı Hata [409]: {"code":"ERR_IDEMPOTENCY_PAYLOAD_MISMATCH"}',
                ),
                createdAt: Value(now),
              ),
            );
        await localDb.database.into(localDb.database.outboxOperations).insert(
              OutboxOperationsCompanion.insert(
                operationId: 'op_gap_blocked',
                deviceId: deviceId,
                clientSeq: 2,
                operationType: 'PRODUCT_UPSERT',
                payload: '{"operation_id":"op_gap_blocked","client_seq":2}',
                payloadHash:
                    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                occurredAt: now,
                status: const Value('FAILED_PERMANENT'),
                attemptCount: const Value(1),
                lastError: const Value(
                  'Kalıcı Hata [409]: {"code":"ERR_CLIENT_SEQ_GAP"}',
                ),
                createdAt: Value(now),
              ),
            );
        await localDb.database.into(localDb.database.outboxOperations).insert(
              OutboxOperationsCompanion.insert(
                operationId: 'op_dup_allowed',
                deviceId: deviceId,
                clientSeq: 3,
                operationType: 'PRODUCT_UPSERT',
                payload: '{"operation_id":"op_dup_allowed","client_seq":3}',
                payloadHash:
                    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
                occurredAt: now,
                status: const Value('FAILED_PERMANENT'),
                attemptCount: const Value(1),
                lastError: const Value(
                  'Kalıcı Hata [409]: {"code":"ERR_DUPLICATE_BARCODE"}',
                ),
                createdAt: Value(now),
              ),
            );

        final apiClient = MmsApiClient(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({'status': 'HEALTHY', 'service': 'MARKET_MMS_HUB'}),
              200,
              headers: const {'content-type': 'application/json'},
            ),
          ),
          baseUrl: 'http://192.168.1.50:8945',
          deviceId: deviceId,
        );

        final status = SystemStatus.initial(
          backendUrl: 'http://192.168.1.50:8945',
          deviceId: deviceId,
          localDbPath: localDb.databasePath,
        ).copyWith(
          outboxSummary: const OutboxSummary(
            pending: 0,
            retry: 0,
            failedPermanent: 3,
            inProgress: 0,
          ),
          localMetricsRevision: 1,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              localDatabaseServiceProvider.overrideWithValue(localDb),
              apiClientProvider.overrideWithValue(apiClient),
              syncTransportProvider.overrideWithValue(_NoopSyncTransport()),
              setupConfigStoreProvider.overrideWithValue(
                InMemorySetupConfigStore(
                  AppSetupConfig.initial(deviceId: deviceId),
                ),
              ),
              initialSetupConfigProvider.overrideWithValue(
                AppSetupConfig.initial(deviceId: deviceId),
              ),
              secureTokenStoreProvider.overrideWithValue(
                InMemorySecureTokenStore(),
              ),
              initialHubConnectionStateProvider.overrideWithValue(
                const HubConnectionState(
                  phase: HubConnectionPhase.connected,
                  activeHubUrl: 'http://192.168.1.50:8945',
                  source: HubUrlSource.manual,
                  isInitialized: true,
                ),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) => SingleChildScrollView(
                    child: const DiagnosticsView().buildSyncCoordinatorCardForTest(
                      context,
                      ref,
                      SyncCoordinatorState.initial(),
                      status,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final idemBtn = tester.widget<OutlinedButton>(
          find.byKey(const Key('retry_failed_op_op_idem_blocked')),
        );
        final gapBtn = tester.widget<OutlinedButton>(
          find.byKey(const Key('retry_failed_op_op_gap_blocked')),
        );
        final dupBtn = tester.widget<OutlinedButton>(
          find.byKey(const Key('retry_failed_op_op_dup_allowed')),
        );

        expect(
          idemBtn.onPressed,
          isNull,
          reason: 'ERR_IDEMPOTENCY_* kaydında Yeniden Dene devre dışı olmalı',
        );
        expect(
          gapBtn.onPressed,
          isNull,
          reason: 'ERR_CLIENT_SEQ_GAP kaydında Yeniden Dene devre dışı olmalı',
        );
        expect(dupBtn.onPressed, isNotNull);

        await tester.tap(find.byKey(const Key('retry_failed_op_op_dup_allowed')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final rows = await localDb.database.select(localDb.database.outboxOperations).get();
        final byId = {for (final r in rows) r.operationId: r};

        expect(byId['op_idem_blocked']!.status, equals('FAILED_PERMANENT'));
        expect(
          byId['op_idem_blocked']!.lastError,
          contains('ERR_IDEMPOTENCY_PAYLOAD_MISMATCH'),
        );
        expect(byId['op_gap_blocked']!.status, equals('FAILED_PERMANENT'));
        expect(
          byId['op_gap_blocked']!.lastError,
          contains('ERR_CLIENT_SEQ_GAP'),
        );
        expect(byId['op_dup_allowed']!.status, equals('PENDING'));
        expect(byId['op_dup_allowed']!.lastError, isNull);
      },
    );
  });
}
