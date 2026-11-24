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
  late Directory tempDir;
  late LocalDatabaseService localDb;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('mms_test_only_s4_win_rbac_');
    localDb = LocalDatabaseService.forTesting(
      NativeDatabase.memory(),
      path: p.join(tempDir.path, 'client_local.db'),
    );
    await localDb.repository.initializeDevice('WIN-TEST-01');
  });

  tearDown(() async {
    await localDb.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  List<Override> buildBaseOverrides({
    required MmsUiProfile profile,
    required InMemorySecureTokenStore tokenStore,
    required String? initialToken,
    required http.Client hubHttp,
    String deviceId = 'WIN-TEST-01',
    String? hubUrl = 'https://127.0.0.1:8945',
    DateTime Function()? clock,
  }) {
    return [
      localDatabaseServiceProvider.overrideWithValue(localDb),
      apiClientProvider.overrideWithValue(
        MmsApiClient(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({'status': 'UP', 'service': 'MARKET_MMS_HUB'}),
              200,
              headers: const {'content-type': 'application/json'},
            ),
          ),
          baseUrl: hubUrl ?? '',
          allowLoopback: true,
          deviceId: deviceId,
        ),
      ),
      setupConfigStoreProvider.overrideWithValue(
        InMemorySetupConfigStore(AppSetupConfig.initial(deviceId: deviceId)),
      ),
      initialSetupConfigProvider.overrideWithValue(
        AppSetupConfig.initial(deviceId: deviceId),
      ),
      backupRootDirectoryProvider.overrideWithValue(
        Directory(p.join(tempDir.path, 'backups')),
      ),
      backupKdfIterationsProvider.overrideWithValue(1000),
      secureTokenStoreProvider.overrideWithValue(tokenStore),
      initialStoredDeviceTokenProvider.overrideWithValue(initialToken),
      initialHubConnectionStateProvider.overrideWithValue(
        HubConnectionState(
          phase: hubUrl == null
              ? HubConnectionPhase.unconfigured
              : HubConnectionPhase.connected,
          activeHubUrl: hubUrl,
          source: hubUrl == null ? null : HubUrlSource.manual,
          isInitialized: true,
        ),
      ),
      mmsUiProfileProvider.overrideWithValue(profile),
      deviceRoleHttpClientProvider.overrideWithValue(hubHttp),
      backupListProvider.overrideWith((ref) async => const []),
      if (clock != null) deviceRoleClockProvider.overrideWithValue(clock),
    ];
  }

  group('AUD-MED-04 Client RBAC: Windows Role Provider Sabit OWNER Döndürmemelidir', () {
    testWidgets(
      '1. Token yoksa veya Hub erişilemezse Windows desktop fail-closed CASHIER döner ve OWNER butonlarını gizler',
      (tester) async {
        final store = InMemorySecureTokenStore();
        final mockHttp = MockClient((req) async {
          throw const SocketException('Hub unreachable in test');
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: buildBaseOverrides(
              profile: const MmsUiProfile.desktop(),
              tokenStore: store,
              initialToken: null,
              hubHttp: mockHttp,
            ),
            child: const MaterialApp(
              home: Scaffold(body: SingleChildScrollView(child: HubCentralBackupCard())),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(HubCentralBackupCard)),
        );
        expect(container.read(hubBackupDeviceRoleProvider), equals('CASHIER'));
        expect(find.byKey(const Key('hub_backup_owner_required_banner')), findsOneWidget);
        expect(find.byKey(const Key('hub_manual_backup_button')), findsNothing);
        expect(find.byKey(const Key('hub_oauth_connect_button')), findsNothing);
        expect(find.byKey(const Key('hub_save_recovery_key_button')), findsNothing);
        expect(find.byKey(const Key('hub_restore_button')), findsNothing);

        // Token mevcut ancak Hub erişilemez -> asla varsayılan OWNER kabul edilmez
        await store.saveDeviceToken('WIN-TEST-01', 'tok_unverified_1');
        await container.read(deviceAuthProvider.notifier).loadForDevice('WIN-TEST-01');
        await tester.pumpAndSettle();

        expect(container.read(hubBackupDeviceRoleProvider), equals('CASHIER'));
        expect(find.byKey(const Key('hub_manual_backup_button')), findsNothing);
        expect(find.byKey(const Key('hub_oauth_connect_button')), findsNothing);
      },
    );

    testWidgets(
      '2. Rol değişikliği, süresi dolmuş/geçersiz token, önbellek TTL ve token silmede fail-closed yenileme',
      (tester) async {
        final store = InMemorySecureTokenStore();
        await store.saveDeviceToken('WIN-TEST-01', 'tok_win_dynamic_1');
        var serverRole = 'CASHIER';
        var serverStatusCode = 200;
        var nowUtc = DateTime.utc(2026, 11, 24, 15, 0, 0);
        DateTime? expiresAtUtc;

        final mockHttp = MockClient((req) async {
          if (req.url.path == '/api/v1/devices/me') {
            expect(req.headers['authorization'], equals('Bearer tok_win_dynamic_1'));
            expect(req.headers['x-mms-tenant-id'], isNotEmpty);
            expect(req.headers['x-mms-store-id'], isNotEmpty);
            if (serverStatusCode != 200) {
              return http.Response(
                jsonEncode({
                  'code': serverStatusCode == 401 ? 'TOKEN_EXPIRED' : 'DEVICE_REVOKED',
                  'message': 'Yetkisiz',
                }),
                serverStatusCode,
              );
            }
            final exp = expiresAtUtc;
            return http.Response(
              jsonEncode({
                'device_id': 'WIN-TEST-01',
                'role': serverRole,
                'is_active': true,
                'is_confirmed': true,
                'owner_bootstrap_completed': true,
                if (exp != null) 'expires_at': exp.toUtc().toIso8601String(),
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }
          if (req.url.path == '/api/v1/backup/status') {
            if (serverRole != 'OWNER') {
              return http.Response(
                jsonEncode({'code': 'ERR_OWNER_ROLE_REQUIRED'}),
                403,
              );
            }
            return http.Response(
              jsonEncode({
                'oauth': {'connected': false},
                'has_recovery_key': false,
                'schedule': {'enabled': false},
              }),
              200,
            );
          }
          return http.Response('{}', 200);
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: buildBaseOverrides(
              profile: const MmsUiProfile.desktop(),
              tokenStore: store,
              initialToken: 'tok_win_dynamic_1',
              hubHttp: mockHttp,
              clock: () => nowUtc,
            ),
            child: const MaterialApp(
              home: Scaffold(body: SingleChildScrollView(child: HubCentralBackupCard())),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(HubCentralBackupCard)),
        );

        // 2a. Başlangıç CASHIER -> yönetim butonları gizli
        expect(container.read(hubBackupDeviceRoleProvider), equals('CASHIER'));
        expect(find.byKey(const Key('hub_oauth_connect_button')), findsNothing);
        expect(find.byKey(const Key('hub_manual_backup_button')), findsNothing);

        // 2b. Hub OWNER yaptığında Yenile -> OWNER açılır
        serverRole = 'OWNER';
        await tester.tap(find.byKey(const Key('hub_backup_refresh_button')));
        await tester.pumpAndSettle();

        expect(container.read(hubBackupDeviceRoleProvider), equals('OWNER'));
        expect(find.byKey(const Key('hub_oauth_connect_button')), findsOneWidget);
        expect(find.byKey(const Key('hub_save_recovery_key_button')), findsOneWidget);
        expect(find.byKey(const Key('hub_restore_button')), findsOneWidget);
        expect(find.byKey(const Key('hub_manual_backup_button')), findsOneWidget);

        // 2c. Hub CASHIER'a düşürdüğünde /backup/status 403 -> OWNER yetkisi anında düşer
        serverRole = 'CASHIER';
        await tester.tap(find.byKey(const Key('hub_backup_refresh_button')));
        await tester.pumpAndSettle();
        expect(container.read(hubBackupDeviceRoleProvider), equals('CASHIER'));
        expect(find.byKey(const Key('hub_oauth_connect_button')), findsNothing);

        // 2d. Token süresinin dolması durumunda önbellek süresi dolmadan fail-closed CASHIER olur
        serverRole = 'OWNER';
        expiresAtUtc = nowUtc.add(const Duration(minutes: 2));
        await tester.tap(find.byKey(const Key('hub_backup_refresh_button')));
        await tester.pumpAndSettle();
        expect(container.read(hubBackupDeviceRoleProvider), equals('OWNER'));

        nowUtc = nowUtc.add(const Duration(minutes: 3));
        container.invalidate(effectiveDeviceRoleProvider);
        await tester.pumpAndSettle();
        expect(container.read(hubBackupDeviceRoleProvider), equals('CASHIER'));
        expect(find.byKey(const Key('hub_oauth_connect_button')), findsNothing);

        // 2e. Geçersiz / 401 dönen token eski OWNER yetkisini geri getiremez
        expiresAtUtc = null;
        serverStatusCode = 401;
        await container.read(deviceRoleProvider.notifier).refreshRole(force: true);
        await tester.pumpAndSettle();
        expect(container.read(hubBackupDeviceRoleProvider), equals('CASHIER'));

        // 2f. Token tamamen silindiğinde fail-closed CASHIER olur
        serverStatusCode = 200;
        await container.read(deviceRoleProvider.notifier).refreshRole(force: true);
        await tester.pumpAndSettle();
        expect(container.read(hubBackupDeviceRoleProvider), equals('OWNER'));

        await container.read(deviceAuthProvider.notifier).clearStoredToken();
        await tester.pumpAndSettle();
        expect(container.read(hubBackupDeviceRoleProvider), equals('CASHIER'));
      },
    );

    testWidgets(
      '3. OWNER Bootstrap tamamlanınca token saklanır ve Windows role provider otomatik OWNER olur',
      (tester) async {
        final store = InMemorySecureTokenStore();
        final roleCheckHttp = MockClient((req) async {
          if (req.url.path == '/api/v1/devices/me' &&
              req.headers['authorization'] == 'Bearer tok_boot_owner_99') {
            return http.Response(
              jsonEncode({
                'device_id': 'WIN-TEST-01',
                'role': 'OWNER',
                'is_active': true,
                'is_confirmed': true,
                'owner_bootstrap_completed': true,
              }),
              200,
            );
          }
          return http.Response('{}', 401);
        });

        final adminClient = HubPairingAdminClient(
          hubBaseUrl: 'https://127.0.0.1:8945',
          httpClient: MockClient((req) async {
            if (req.url.path == '/api/v1/admin/owner/bootstrap') {
              return http.Response(
                jsonEncode({
                  'status': 'BOOTSTRAPPED',
                  'device_id': 'WIN-TEST-01',
                  'role': 'OWNER',
                  'token': 'tok_boot_owner_99',
                }),
                200,
              );
            }
            if (req.url.path == '/health') {
              return http.Response(
                jsonEncode({
                  'status': 'UP',
                  'restore_epoch': 'epoch_0',
                  'backup': {'recovery_key_configured': false},
                }),
                200,
              );
            }
            return http.Response('{}', 404);
          }),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...buildBaseOverrides(
                profile: const MmsUiProfile.desktop(),
                tokenStore: store,
                initialToken: null,
                hubHttp: roleCheckHttp,
              ),
              hubPairingAdminClientProvider.overrideWithValue(adminClient),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      HubCentralBackupCard(),
                      PairingApprovalPanel(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(HubCentralBackupCard)),
        );
        expect(container.read(hubBackupDeviceRoleProvider), equals('CASHIER'));

        await tester.enterText(
          find.byKey(const Key('pairing_admin_secret_field')),
          'admin_secret_123',
        );
        await tester.ensureVisible(find.byKey(const Key('owner_bootstrap_button')));
        await tester.tap(find.byKey(const Key('owner_bootstrap_button')));
        await tester.pumpAndSettle();

        expect(container.read(hubBackupDeviceRoleProvider), equals('OWNER'));
        expect(find.byKey(const Key('hub_oauth_connect_button')), findsOneWidget);
      },
    );

    testWidgets(
      '4. Android mobil profilinde de rol backend üzerinden doğrulanır (OWNER OAuthsuz tetik, CASHIER salt kısıtlı)',
      (tester) async {
        final store = InMemorySecureTokenStore();
        await store.saveDeviceToken('AND-MOB-01', 'tok_and_1');
        var role = 'OWNER';
        final mockHttp = MockClient((req) async {
          if (req.url.path == '/api/v1/devices/me') {
            return http.Response(
              jsonEncode({'device_id': 'AND-MOB-01', 'role': role}),
              200,
            );
          }
          return http.Response('{}', 200);
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: buildBaseOverrides(
              profile: const MmsUiProfile.mobile(),
              tokenStore: store,
              initialToken: 'tok_and_1',
              deviceId: 'AND-MOB-01',
              hubHttp: mockHttp,
            ),
            child: const MaterialApp(
              home: Scaffold(body: SingleChildScrollView(child: HubCentralBackupCard())),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('hub_manual_backup_button')), findsOneWidget);
        expect(find.byKey(const Key('hub_oauth_connect_button')), findsNothing);

        role = 'CASHIER';
        final container = ProviderScope.containerOf(
          tester.element(find.byType(HubCentralBackupCard)),
        );
        await container.read(deviceRoleProvider.notifier).refreshRole(force: true);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('hub_backup_cashier_restricted')), findsOneWidget);
      },
    );

    testWidgets(
      '5. 5 dk istemci cache süresi dolmadan sunucudan gelen 403 anında rolü CASHIER düşürür ve 401/403/unreachable/unauthenticated ayrılır',
      (tester) async {
        final store = InMemorySecureTokenStore();
        await store.saveDeviceToken('WIN-TEST-01', 'tok_cache_vs_403');
        var serverRole = 'OWNER';
        var meStatusCode = 200;
        var meThrowNetwork = false;
        var nowUtc = DateTime.utc(2026, 11, 24, 16, 0, 0);

        final mockHttp = MockClient((req) async {
          if (req.url.path == '/api/v1/devices/me') {
            if (meThrowNetwork) {
              throw const SocketException('Hub offline');
            }
            if (meStatusCode != 200) {
              return http.Response(
                jsonEncode({
                  'code': meStatusCode == 401 ? 'TOKEN_EXPIRED' : 'DEVICE_REVOKED',
                }),
                meStatusCode,
              );
            }
            return http.Response(
              jsonEncode({
                'device_id': 'WIN-TEST-01',
                'role': serverRole,
                'is_active': true,
                'is_confirmed': true,
                'expires_at':
                    nowUtc.add(const Duration(minutes: 30)).toUtc().toIso8601String(),
              }),
              200,
            );
          }
          if (req.url.path == '/api/v1/backup/run') {
            return http.Response(
              jsonEncode({
                'error': 'FORBIDDEN',
                'code': 'ERR_OWNER_ROLE_REQUIRED',
                'message': 'OWNER rolü gereklidir.',
              }),
              403,
            );
          }
          return http.Response('{}', 200);
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: buildBaseOverrides(
              profile: const MmsUiProfile.desktop(),
              tokenStore: store,
              initialToken: 'tok_cache_vs_403',
              hubHttp: mockHttp,
              clock: () => nowUtc,
            ),
            child: const MaterialApp(
              home: Scaffold(body: SingleChildScrollView(child: HubCentralBackupCard())),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(HubCentralBackupCard)),
        );
        expect(container.read(hubBackupDeviceRoleProvider), equals('OWNER'));
        expect(
          container.read(deviceRoleProvider).status.name,
          equals('verified'),
        );

        // Sadece 1 dakika geçti (5 dk cache hâlâ geçerli), ancak backend rolü düşürüldü ve 403 döndü:
        nowUtc = nowUtc.add(const Duration(minutes: 1));
        serverRole = 'CASHIER';
        await tester.ensureVisible(find.byKey(const Key('hub_manual_backup_button')));
        await tester.tap(find.byKey(const Key('hub_manual_backup_button')));
        await tester.pumpAndSettle();

        expect(container.read(hubBackupDeviceRoleProvider), equals('CASHIER'));
        expect(
          container.read(deviceRoleProvider).status.name,
          equals('unauthorized'),
        );
        expect(find.byKey(const Key('hub_backup_owner_required_banner')), findsOneWidget);

        // 401 vs 403 vs unreachable vs unauthenticated ayrımı (hepsi fail-closed CASHIER)
        meStatusCode = 401;
        await container.read(deviceRoleProvider.notifier).refreshRole(force: true);
        expect(container.read(deviceRoleProvider).status.name, equals('unauthorized'));
        expect(container.read(deviceRoleProvider).errorCode, equals('TOKEN_EXPIRED'));
        expect(container.read(hubBackupDeviceRoleProvider), equals('CASHIER'));

        meStatusCode = 403;
        await container.read(deviceRoleProvider.notifier).refreshRole(force: true);
        expect(container.read(deviceRoleProvider).status.name, equals('unauthorized'));
        expect(container.read(deviceRoleProvider).errorCode, equals('DEVICE_REVOKED'));
        expect(container.read(hubBackupDeviceRoleProvider), equals('CASHIER'));

        meStatusCode = 200;
        meThrowNetwork = true;
        await container.read(deviceRoleProvider.notifier).refreshRole(force: true);
        expect(container.read(deviceRoleProvider).status.name, equals('unreachable'));
        expect(container.read(hubBackupDeviceRoleProvider), equals('CASHIER'));

        meThrowNetwork = false;
        await container.read(deviceAuthProvider.notifier).clearStoredToken();
        await tester.pumpAndSettle();
        expect(
          container.read(deviceRoleProvider).status.name,
          equals('unauthenticated'),
        );
        expect(container.read(hubBackupDeviceRoleProvider), equals('CASHIER'));
      },
    );
  });
}
