import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/core/network/api_client.dart';
import 'package:market_pos/core/platform/mms_ui_profile.dart';
import 'package:market_pos/core/security/secure_token_store.dart';
import 'package:market_pos/core/security/security_providers.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/features/backup/backup_providers.dart';
import 'package:market_pos/features/backup/data/hub_backup_client.dart';
import 'package:market_pos/features/backup/presentation/widgets/hub_central_backup_card.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:market_pos/features/setup/data/local_setup_config_store.dart';
import 'package:market_pos/features/setup/domain/app_setup_config.dart';
import 'package:market_pos/features/setup/setup_providers.dart';
import 'package:market_pos/features/sync/application/hub_connection_notifier.dart';
import 'package:market_pos/features/sync/domain/hub_connection_state.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late LocalDatabaseService localDb;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('mms_test_only_stage2_ui_');
    localDb = LocalDatabaseService.forTesting(
      NativeDatabase.memory(),
      path: p.join(tempDir.path, 'client_local.db'),
    );
    await localDb.repository.initializeDevice('POS-WIN-DR-UI');
  });

  tearDown(() async {
    await localDb.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  testWidgets('AUD-CRIT-03 UI: Windows yeni PC kurulumunda Drive yedeklerini listeler, seçer ve drive_file_id ile geri yükler', (tester) async {
    Map<String, dynamic>? capturedRestoreBody;
    final backupClient = HubBackupClient(
      httpClient: MockClient((req) async {
        if (req.method == 'GET' && req.url.path == '/api/v1/backup/drive/list') {
          return http.Response(
            jsonEncode({
              'backups': [
                {
                  'drive_file_id': 'drv_remote_new_pc_1',
                  'file_name': 'hub_backup_bak_remote_1.mmsbak',
                  'backup_id': 'bak_remote_1',
                  'size_bytes': 262144,
                  'sha256_hex': 'a' * 64,
                  'schema_version': 4,
                  'hub_id': 'MMS-HUB-MASTER',
                  'created_time_utc': '2026-11-24T00:05:00Z',
                  'cached_locally': false,
                },
              ],
            }),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (req.method == 'POST' && req.url.path == '/api/v1/backup/restore') {
          expect(req.headers['x-mms-timestamp'], isNotNull);
          expect(req.headers['x-mms-nonce'], isNotNull);
          capturedRestoreBody = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'status': 'RESTORED',
              'backup_id': 'bak_remote_1',
              'restore_epoch': 'epoch_drive_restored_99',
              'safety_backup_encrypted': true,
              'invalidated_active_device_count': 1,
              'preserved_revoked_device_count': 0,
              'restored_at_utc': '2026-11-24T11:30:00Z',
            }),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{}', 200);
      }),
      readHubUrl: () => 'https://127.0.0.1:8945',
      readDeviceToken: () => 'tok_win_owner',
      tenantId: 't1',
      storeId: 's1',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localDatabaseServiceProvider.overrideWithValue(localDb),
          apiClientProvider.overrideWithValue(
            MmsApiClient(
              client: MockClient((_) async => http.Response('{}', 200)),
              baseUrl: 'https://127.0.0.1:8945',
              deviceId: 'POS-WIN-DR-UI',
            ),
          ),
          setupConfigStoreProvider.overrideWithValue(
            InMemorySetupConfigStore(AppSetupConfig.initial(deviceId: 'POS-WIN-DR-UI')),
          ),
          initialSetupConfigProvider.overrideWithValue(
            AppSetupConfig.initial(deviceId: 'POS-WIN-DR-UI'),
          ),
          backupRootDirectoryProvider.overrideWithValue(
            Directory(p.join(tempDir.path, 'backups')),
          ),
          backupKdfIterationsProvider.overrideWithValue(1000),
          secureTokenStoreProvider.overrideWithValue(InMemorySecureTokenStore()),
          initialHubConnectionStateProvider.overrideWithValue(
            const HubConnectionState(
              phase: HubConnectionPhase.connected,
              activeHubUrl: 'https://127.0.0.1:8945',
              source: HubUrlSource.manual,
              isInitialized: true,
            ),
          ),
          mmsUiProfileProvider.overrideWithValue(const MmsUiProfile.desktop()),
          hubBackupDeviceRoleProvider.overrideWithValue('OWNER'),
          backupListProvider.overrideWith((ref) async => const []),
          hubBackupClientProvider.overrideWithValue(backupClient),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: HubCentralBackupCard())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final listBtn = find.byKey(const Key('hub_drive_list_backups_button'));
    expect(listBtn, findsOneWidget);
    await tester.ensureVisible(listBtn);
    await tester.tap(listBtn);
    await tester.pumpAndSettle();

    final remoteRow = find.byKey(const Key('hub_drive_backup_item_drv_remote_new_pc_1'));
    expect(remoteRow, findsOneWidget);
    await tester.ensureVisible(remoteRow);
    await tester.tap(remoteRow);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('hub_restore_password_field')),
      'Portable-Recovery-Ui-2026!',
    );
    final restoreBtn = find.byKey(const Key('hub_restore_button'));
    await tester.ensureVisible(restoreBtn);
    await tester.tap(restoreBtn);
    await tester.pumpAndSettle();

    expect(capturedRestoreBody, isNotNull);
    expect(capturedRestoreBody!['backup_id'], equals('bak_remote_1'));
    expect(capturedRestoreBody!['drive_file_id'], equals('drv_remote_new_pc_1'));
    expect(
      capturedRestoreBody!['recovery_password'],
      equals('Portable-Recovery-Ui-2026!'),
    );
    expect(find.textContaining('epoch_drive_restored_99'), findsOneWidget);
  });
}
