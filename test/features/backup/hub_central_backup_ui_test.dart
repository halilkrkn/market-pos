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
import 'package:market_pos/features/backup/presentation/widgets/backup_management_card.dart';
import 'package:market_pos/features/backup/presentation/widgets/hub_central_backup_card.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:market_pos/features/security/data/hub_pairing_admin_client.dart';
import 'package:market_pos/features/security/presentation/widgets/pairing_approval_panel.dart';
import 'package:market_pos/features/setup/data/local_setup_config_store.dart';
import 'package:market_pos/features/setup/domain/app_setup_config.dart';
import 'package:market_pos/features/setup/setup_providers.dart';
import 'package:market_pos/features/sync/application/hub_connection_notifier.dart';
import 'package:market_pos/features/sync/domain/hub_connection_state.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Faz B-4: HubCentralBackupCard UI Ayrımı & HubBackupClient Replay Başlıkları', () {
    late Directory tempDir;
    late LocalDatabaseService localDb;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('mms_test_only_b4_ui_');
      localDb = LocalDatabaseService.forTesting(
        NativeDatabase.memory(),
        path: p.join(tempDir.path, 'client_local.db'),
      );
      await localDb.repository.initializeDevice('POS-B4-UI-01');
    });

    tearDown(() async {
      await localDb.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    List<Override> commonUiOverrides({
      required MmsUiProfile profile,
      required String role,
    }) {
      return [
        localDatabaseServiceProvider.overrideWithValue(localDb),
        apiClientProvider.overrideWithValue(
          MmsApiClient(
            client: MockClient(
              (_) async => http.Response(
                jsonEncode({'status': 'HEALTHY', 'service': 'MARKET_MMS_HUB'}),
                200,
                headers: const {'content-type': 'application/json'},
              ),
            ),
            baseUrl: 'http://192.168.1.50:8945',
            deviceId: 'POS-B4-UI-01',
          ),
        ),
        setupConfigStoreProvider.overrideWithValue(
          InMemorySetupConfigStore(AppSetupConfig.initial(deviceId: 'POS-B4-UI-01')),
        ),
        initialSetupConfigProvider.overrideWithValue(
          AppSetupConfig.initial(deviceId: 'POS-B4-UI-01'),
        ),
        backupRootDirectoryProvider.overrideWithValue(
          Directory(p.join(tempDir.path, 'backups')),
        ),
        backupKdfIterationsProvider.overrideWithValue(1000),
        secureTokenStoreProvider.overrideWithValue(InMemorySecureTokenStore()),
        initialHubConnectionStateProvider.overrideWithValue(
          const HubConnectionState(
            phase: HubConnectionPhase.connected,
            activeHubUrl: 'http://192.168.1.50:8945',
            source: HubUrlSource.manual,
            isInitialized: true,
          ),
        ),
        mmsUiProfileProvider.overrideWithValue(profile),
        hubBackupDeviceRoleProvider.overrideWithValue(role),
        backupListProvider.overrideWith((ref) async => const []),
      ];
    }

    test('BK-031: HubBackupClient mutasyon isteklerine X-MMS-Timestamp ve benzersiz X-MMS-Nonce ekler', () async {
      final capturedNonces = <String>{};
      final capturedTs = <String>[];

      final client = HubBackupClient(
        httpClient: MockClient((req) async {
          final ts = req.headers['x-mms-timestamp'];
          final nonce = req.headers['x-mms-nonce'];
          expect(ts, isNotNull);
          expect(nonce, isNotNull);
          expect(nonce!.length, greaterThanOrEqualTo(16));
          capturedTs.add(ts!);
          expect(capturedNonces.add(nonce), isTrue);

          if (req.url.path == '/api/v1/backup/run') {
            return http.Response(
              jsonEncode({
                'backup_id': 'bak_ui_1',
                'trigger': 'MANUAL',
                'state': 'COMPLETED_UPLOADED',
                'scheduled_date_local': '2026-11-22',
                'created_at_utc': '2026-11-22T12:00:00Z',
                'updated_at_utc': '2026-11-22T12:01:00Z',
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'has_recovery_key': true}), 200);
        }),
        readHubUrl: () => 'https://127.0.0.1:8945',
        readDeviceToken: () => 'owner_tok_1',
        tenantId: 't1',
        storeId: 's1',
      );

      await client.setRecoveryKey('KurtarmaParolasi-2026!');
      final job = await client.triggerManualBackup();
      expect(job.state, equals(HubBackupJobState.completedUploaded));
      expect(capturedNonces.length, equals(2));
      expect(capturedTs.length, equals(2));
    });

    testWidgets('BK-029a: Windows masaüstü profilinde tam Merkezi Hub Yedekleme ve Legacy kart etiketi görünür', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: commonUiOverrides(
            profile: const MmsUiProfile.desktop(),
            role: 'OWNER',
          ),
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    HubCentralBackupCard(),
                    BackupManagementCard(),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Google Drive Yedekleme'), findsOneWidget);
      expect(find.text("Google Drive'a Bağlan"), findsOneWidget);
      expect(find.byKey(const Key('hub_oauth_connect_button')), findsOneWidget);
      expect(find.byKey(const Key('hub_save_recovery_key_button')), findsOneWidget);
      expect(find.byKey(const Key('hub_restore_button')), findsOneWidget);
      expect(find.text('Legacy Yerel Cihaz Yedeği (S5A-4)'), findsOneWidget);
    });

    testWidgets('BK-029b: Android profilinde CASHIER salt-kısıtlı görünür, OWNER ise OAuth olmadan uzaktan tetik görür', (tester) async {
      // 1. Android CASHIER -> Kısıtlı uyarı; Google Drive OAuth yok
      await tester.pumpWidget(
        ProviderScope(
          overrides: commonUiOverrides(
            profile: const MmsUiProfile.mobile(),
            role: 'CASHIER',
          ),
          child: const MaterialApp(
            home: Scaffold(body: HubCentralBackupCard()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('hub_backup_cashier_restricted')), findsOneWidget);
      expect(find.byKey(const Key('hub_oauth_connect_button')), findsNothing);
      expect(find.byKey(const Key('hub_manual_backup_button')), findsNothing);

      // 2. Android OWNER -> Uzaktan durum + tetik var, ancak Google Drive OAuth butonu kesinlikle YOK (OV-02)
      await tester.pumpWidget(
        ProviderScope(
          overrides: commonUiOverrides(
            profile: const MmsUiProfile.mobile(),
            role: 'OWNER',
          ),
          child: const MaterialApp(
            home: Scaffold(body: HubCentralBackupCard()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('hub_backup_refresh_button')), findsOneWidget);
      expect(find.byKey(const Key('hub_manual_backup_button')), findsOneWidget);
      expect(find.byKey(const Key('hub_oauth_connect_button')), findsNothing);
      expect(find.byKey(const Key('hub_restore_button')), findsNothing);
    });

    // S2: Kaydetme ve manuel yedekleme ayrı işlemlerdir; yedek yalnızca Hub'da KAYITLI
    // parolayla şifrelenir ve istemci /backup/run isteğinde parola göndermez.
    group('S2: Windows manuel Hub yedeği yalnızca kayıtlı kurtarma parolasını kullanır', () {
      Future<List<http.Request>> pumpCard(
        WidgetTester tester, {
        required bool Function() hasRecoveryKey,
        void Function()? onSave,
      }) async {
        final requests = <http.Request>[];
        final client = HubBackupClient(
          httpClient: MockClient((req) async {
            requests.add(req);
            switch (req.url.path) {
              case '/api/v1/backup/recovery-key':
                onSave?.call();
                return http.Response(jsonEncode({'has_recovery_key': true}), 200);
              case '/api/v1/backup/run':
                return http.Response(
                  jsonEncode({
                    'backup_id': 'bak_s2_ui',
                    'trigger': 'MANUAL',
                    'state': 'COMPLETED_UPLOADED',
                    'scheduled_date_local': '2026-11-22',
                    'created_at_utc': '2026-11-22T12:00:00Z',
                    'updated_at_utc': '2026-11-22T12:01:00Z',
                    'recovery_key_source': 'HUB_STORED_DPAPI',
                  }),
                  200,
                );
              default:
                return http.Response(
                  jsonEncode({
                    'oauth': {'connected': true},
                    'has_recovery_key': hasRecoveryKey(),
                    'schedule': {'enabled': false},
                  }),
                  200,
                );
            }
          }),
          readHubUrl: () => 'http://127.0.0.1:8945',
          readDeviceToken: () => null,
          readAdminSecret: () => 'admin_s2_ui',
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...commonUiOverrides(profile: const MmsUiProfile.desktop(), role: 'OWNER'),
              hubBackupClientProvider.overrideWithValue(client),
            ],
            child: const MaterialApp(
              home: Scaffold(body: SingleChildScrollView(child: HubCentralBackupCard())),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return requests;
      }

      Future<void> tapKey(WidgetTester tester, String key) async {
        await tester.ensureVisible(find.byKey(Key(key)));
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
      }

      String bannerText(WidgetTester tester) {
        final banner = find.byKey(const Key('hub_central_backup_banner'));
        expect(banner, findsOneWidget);
        return tester
            .widgetList<Text>(find.descendant(of: banner, matching: find.byType(Text)))
            .map((t) => t.data ?? '')
            .join(' ');
      }

      testWidgets('Kaydedilmemiş parola alanı doluyken yedek başlatılmaz; kaydettikten sonra '
          'parola göndermeden yedek alınır', (tester) async {
        var saved = false;
        final requests = await pumpCard(
          tester,
          hasRecoveryKey: () => saved,
          onSave: () => saved = true,
        );

        await tester.enterText(find.byKey(const Key('hub_recovery_key_field')), 'KaydedilmemisParola-2026');
        await tapKey(tester, 'hub_manual_backup_button');
        expect(requests.where((r) => r.url.path == '/api/v1/backup/run'), isEmpty);
        expect(bannerText(tester), contains('kaydedilmemiş'));

        await tapKey(tester, 'hub_save_recovery_key_button');
        final saveReq = requests.singleWhere((r) => r.url.path == '/api/v1/backup/recovery-key');
        expect(jsonDecode(saveReq.body)['recovery_password'], equals('KaydedilmemisParola-2026'));
        expect(
          tester.widget<TextField>(find.byKey(const Key('hub_recovery_key_field'))).controller!.text,
          isEmpty,
        );

        await tapKey(tester, 'hub_manual_backup_button');
        final runReq = requests.singleWhere((r) => r.url.path == '/api/v1/backup/run');
        expect((jsonDecode(runReq.body) as Map).containsKey('recovery_password'), isFalse);
        expect(bannerText(tester), contains('kayıtlı kurtarma parolasıyla şifrelendi'));
      });

      testWidgets("Hub'da kayıtlı parola yoksa (durum biliniyorsa) yedek isteği gönderilmez", (tester) async {
        final requests = await pumpCard(tester, hasRecoveryKey: () => false);
        await tapKey(tester, 'hub_backup_refresh_button');
        await tapKey(tester, 'hub_manual_backup_button');
        expect(requests.where((r) => r.url.path == '/api/v1/backup/run'), isEmpty);
        expect(bannerText(tester), contains('kayıtlı kurtarma parolası yok'));
      });
    });

    testWidgets('3.4: scheduler_last_error yönetim ekranında anlaşılır mesajla gösterilir ve başarılı çalışma sonrası temizlenir', (tester) async {
      var hasSchedulerError = true;
      final client = HubBackupClient(
        httpClient: MockClient((req) async {
          if (req.url.path == '/api/v1/backup/run') {
            hasSchedulerError = false;
            return http.Response(
              jsonEncode({
                'backup_id': 'bak_ok_34',
                'trigger': 'MANUAL',
                'state': 'COMPLETED_UPLOADED',
                'scheduled_date_local': '2026-11-24',
                'created_at_utc': '2026-11-24T01:00:00Z',
                'updated_at_utc': '2026-11-24T01:00:10Z',
              }),
              200,
              headers: const {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response(
            jsonEncode({
              'oauth': {'connected': true},
              'has_recovery_key': true,
              'schedule': {'enabled': true},
              'scheduler_last_error': hasSchedulerError
                  ? {
                      'code': 'ERR_INSUFFICIENT_DISK_SPACE',
                      'message': 'Yeterli disk alanı yok',
                      'at_utc': '2026-11-24T00:05:00Z',
                    }
                  : null,
            }),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
        readHubUrl: () => 'https://127.0.0.1:8945',
        readDeviceToken: () => 'tok_owner',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...commonUiOverrides(profile: const MmsUiProfile.desktop(), role: 'OWNER'),
            hubBackupClientProvider.overrideWithValue(client),
          ],
          child: const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: HubCentralBackupCard())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('hub_backup_refresh_button')));
      await tester.tap(find.byKey(const Key('hub_backup_refresh_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('hub_scheduler_last_error_banner')), findsOneWidget);
      expect(find.textContaining('yeterli boş alan yok'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('hub_manual_backup_button')));
      await tester.tap(find.byKey(const Key('hub_manual_backup_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('hub_scheduler_last_error_banner')), findsNothing);
    });

    testWidgets('5.4 & 6: Windows PairingApprovalPanel tek seferlik OWNER bootstrap ve /health kurtarma anahtarı durumu', (tester) async {
      final tokenStore = InMemorySecureTokenStore();
      var bootstrapped = false;
      final adminClient = HubPairingAdminClient(
        hubBaseUrl: 'https://127.0.0.1:8945',
        httpClient: MockClient((req) async {
          if (req.url.path == '/api/v1/admin/owner/bootstrap') {
            if (bootstrapped) {
              return http.Response(
                jsonEncode({
                  'code': 'ERR_OWNER_ALREADY_BOOTSTRAPPED',
                  'message': 'Daha önce mühürlendi.',
                }),
                409,
              );
            }
            bootstrapped = true;
            return http.Response(
              jsonEncode({
                'status': 'BOOTSTRAPPED',
                'device_id': 'POS-B4-UI-01',
                'role': 'OWNER',
                'token': 'owner_issued_tok_123',
              }),
              200,
            );
          }
          if (req.url.path == '/health') {
            return http.Response(
              jsonEncode({
                'status': 'UP',
                'backup': {'recovery_key_configured': false},
              }),
              200,
            );
          }
          return http.Response('{}', 200);
        }),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...commonUiOverrides(profile: const MmsUiProfile.desktop(), role: 'OWNER'),
            secureTokenStoreProvider.overrideWithValue(tokenStore),
            hubPairingAdminClientProvider.overrideWithValue(adminClient),
          ],
          child: const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: PairingApprovalPanel())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('pairing_manual_recovery_tile')),
      );
      await tester.tap(find.byKey(const Key('pairing_manual_recovery_tile')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('pairing_admin_secret_field')),
        'admin_secret_bootstrap',
      );
      await tester.ensureVisible(find.byKey(const Key('owner_bootstrap_button')));
      await tester.tap(find.byKey(const Key('owner_bootstrap_button')));
      await tester.pumpAndSettle();

      expect(await tokenStore.readDeviceToken('POS-B4-UI-01'), equals('owner_issued_tok_123'));
      expect(find.byKey(const Key('hub_recovery_key_health_badge')), findsOneWidget);

      // İkinci bootstrap çağrısı 409 reddedilir
      await tester.tap(find.byKey(const Key('owner_bootstrap_button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Daha önce mühürlendi'), findsOneWidget);
    });
  });
}
