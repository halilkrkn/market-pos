import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/core/logging/redacting_logger.dart';
import 'package:market_pos/core/platform/mms_ui_profile.dart';
import 'package:market_pos/core/security/secure_token_store.dart';
import 'package:market_pos/core/security/security_providers.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/core/theme/app_theme.dart';
import 'package:market_pos/features/backup/application/android_google_sign_in_token_provider.dart';
import 'package:market_pos/features/backup/application/google_drive_connect_service.dart';
import 'package:market_pos/features/backup/backup_providers.dart';
import 'package:market_pos/features/backup/presentation/widgets/external_backup_section.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

class _FakeGoogleSignInAdapter implements GoogleSignInClientAdapter {
  int initCount = 0;
  String? lastServerClientId;
  int authenticateCount = 0;
  int lightweightCount = 0;
  int authorizeScopesCount = 0;
  int authorizationForScopesCount = 0;
  int clearTokenCount = 0;
  int signOutCount = 0;
  int disconnectCount = 0;

  List<String>? lastRequestedScopes;
  String? lastClearedToken;

  AndroidGoogleAccount? accountToReturn = const AndroidGoogleAccount(
    id: 'gid-101',
    email: 'kasa.sahibi@example.com',
    displayName: 'Market Sahibi',
  );
  AndroidGoogleAccount? lightweightAccountToReturn;

  String interactiveAccessToken = 'ya29.interactive-token-secret-123';
  String? silentAccessToken = 'ya29.silent-token-secret-456';

  Object? initError;
  Object? authenticateError;
  Object? authorizeScopesError;
  Object? authorizationForScopesError;
  Object? disconnectError;

  @override
  Future<void> initialize({required String serverClientId}) async {
    initCount++;
    lastServerClientId = serverClientId;
    if (initError != null) throw initError!;
  }

  @override
  Future<AndroidGoogleAccount?> attemptLightweightAuthentication() async {
    lightweightCount++;
    return lightweightAccountToReturn;
  }

  @override
  Future<AndroidGoogleAccount> authenticate() async {
    authenticateCount++;
    if (authenticateError != null) throw authenticateError!;
    return accountToReturn!;
  }

  @override
  Future<String?> authorizationForScopes(
    AndroidGoogleAccount account,
    List<String> scopes,
  ) async {
    authorizationForScopesCount++;
    lastRequestedScopes = List<String>.unmodifiable(scopes);
    if (authorizationForScopesError != null) throw authorizationForScopesError!;
    return silentAccessToken;
  }

  @override
  Future<String> authorizeScopes(
    AndroidGoogleAccount account,
    List<String> scopes,
  ) async {
    authorizeScopesCount++;
    lastRequestedScopes = List<String>.unmodifiable(scopes);
    if (authorizeScopesError != null) throw authorizeScopesError!;
    return interactiveAccessToken;
  }

  @override
  Future<void> clearAuthorizationToken(String accessToken) async {
    clearTokenCount++;
    lastClearedToken = accessToken;
  }

  @override
  Future<void> signOut() async {
    signOutCount++;
  }

  @override
  Future<void> disconnect() async {
    disconnectCount++;
    if (disconnectError != null) throw disconnectError!;
  }
}

class _FakeLiveSyncDriveServer {
  final Map<String, Uint8List> files = <String, Uint8List>{};
  final Map<String, Map<String, dynamic>> meta = <String, Map<String, dynamic>>{};
  final Map<String, String> uploadSessions = <String, String>{};
  int _seq = 0;
  int apiRequestCount = 0;
  bool forceNextGet401 = false;

  http.Client createClient() => MockClient((req) async {
        apiRequestCount++;
        if (forceNextGet401) {
          forceNextGet401 = false;
          return http.Response('Unauthorized', 401);
        }
        if (req.method == 'GET' && req.url.path == '/drive/v3/files') {
          final q = req.url.queryParameters['q'] ?? '';
          if (q.contains('application/vnd.google-apps.folder')) {
            return http.Response(
              jsonEncode({
                'files': [
                  {'id': 'live-folder-1'},
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({'files': meta.values.toList()}),
            200,
          );
        }
        if (req.method == 'POST' && req.url.path == '/upload/drive/v3/files') {
          final initMeta = jsonDecode(req.body) as Map<String, dynamic>;
          final sessionId = 'live_sess_${++_seq}';
          uploadSessions[sessionId] = jsonEncode(initMeta);
          return http.Response(
            '',
            200,
            headers: {
              'location':
                  'https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&session=$sessionId',
            },
          );
        }
        if (req.method == 'PUT' && req.url.path == '/upload/drive/v3/files') {
          final sessionId = req.url.queryParameters['session']!;
          final initMeta =
              jsonDecode(uploadSessions[sessionId]!) as Map<String, dynamic>;
          final fileId = 'live_file_${++_seq}';
          final bytes = Uint8List.fromList(req.bodyBytes);
          files[fileId] = bytes;
          meta[fileId] = {
            'id': fileId,
            'name': initMeta['name'],
            'appProperties': initMeta['appProperties'],
          };
          return http.Response(jsonEncode({'id': fileId}), 200);
        }
        if (req.method == 'GET' &&
            req.url.path.startsWith('/drive/v3/files/') &&
            req.url.queryParameters['alt'] == 'media') {
          final fileId = req.url.pathSegments.last;
          final bytes = files[fileId];
          if (bytes == null) return http.Response('Not Found', 404);
          return http.Response.bytes(bytes, 200);
        }
        return http.Response('Not Found', 404);
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ADR-022 Phase 2 — Android Google Drive OAuth (google_sign_in)', () {
    test('1. Boş serverClientId durumunda fail-closed (ERR_DRIVE_NOT_CONFIGURED)', () async {
      final adapter = _FakeGoogleSignInAdapter();
      final store = InMemorySecureTokenStore();
      final provider = AndroidGoogleSignInTokenProvider(
        serverClientId: '   ',
        adapter: adapter,
        secureStore: store,
      );

      expect(provider.isConfigured, isFalse);
      await expectLater(
        () => provider.connect(),
        throwsA(
          isA<DriveBackupException>()
              .having((e) => e.code, 'code', 'ERR_DRIVE_NOT_CONFIGURED'),
        ),
      );
      await expectLater(
        () => provider.accessToken(),
        throwsA(
          isA<DriveBackupException>()
              .having((e) => e.code, 'code', 'ERR_DRIVE_NOT_CONFIGURED'),
        ),
      );
      expect(adapter.initCount, 0);
    });

    test(
      '2. connect() yalnızca drive.file ister, token RAM\'de kalır ve SecureStore\'a access_token yazılmaz',
      () async {
        final adapter = _FakeGoogleSignInAdapter();
        final store = InMemorySecureTokenStore();
        final logger = RedactingLogger();
        var now = DateTime.utc(2026, 11, 22, 10, 0);

        final provider = AndroidGoogleSignInTokenProvider(
          serverClientId: 'web-client-id-123.apps.googleusercontent.com',
          adapter: adapter,
          secureStore: store,
          logger: logger,
          clock: () => now,
        );

        await provider.connect();

        expect(adapter.initCount, 1);
        expect(
          adapter.lastServerClientId,
          'web-client-id-123.apps.googleusercontent.com',
        );
        expect(adapter.authenticateCount, 1);
        expect(adapter.authorizeScopesCount, 1);
        expect(adapter.lastRequestedScopes, [googleDriveFileScope]);

        expect(await provider.isConnected(), isTrue);
        expect(
          await store.readSecret(
            AndroidGoogleSignInTokenProvider.connectedFlagSecretKey,
          ),
          'true',
        );
        expect(
          await store.readSecret(
            AndroidGoogleSignInTokenProvider.connectedEmailHintKey,
          ),
          'kasa.sahibi@example.com',
        );
        // Sır olmayan bayrak dışındaki refresh/access token alanlarına yazılmaz.
        expect(
          await store.readSecret(GoogleDriveConnectService.refreshTokenSecretKey),
          isNull,
        );
        // Erişim token'ı loglayıcıda otomatik maskelenir.
        expect(
          logger.redact('Authorization Bearer ${adapter.interactiveAccessToken}'),
          isNot(contains(adapter.interactiveAccessToken)),
        );
      },
    );

    test(
      '3. RAM önbellek isabeti ve forceRefresh: true -> clearAuthorizationToken + authorizationForScopes',
      () async {
        final adapter = _FakeGoogleSignInAdapter();
        final store = InMemorySecureTokenStore();
        var now = DateTime.utc(2026, 11, 22, 10, 0);

        final provider = AndroidGoogleSignInTokenProvider(
          serverClientId: 'web-client.apps.googleusercontent.com',
          adapter: adapter,
          secureStore: store,
          clock: () => now,
        );

        await provider.connect();
        expect(
          await provider.accessToken(),
          adapter.interactiveAccessToken,
        );
        expect(adapter.authorizationForScopesCount, 0);

        // Süre dolmadan yeniden çağrı RAM önbelleğinden döner.
        now = now.add(const Duration(minutes: 20));
        expect(
          await provider.accessToken(),
          adapter.interactiveAccessToken,
        );
        expect(adapter.authorizationForScopesCount, 0);

        // 401 sonrası forceRefresh: true eski token'ı temizler ve sessiz yeniler.
        adapter.silentAccessToken = 'ya29.refreshed-token-789';
        final refreshed = await provider.accessToken(forceRefresh: true);
        expect(refreshed, 'ya29.refreshed-token-789');
        expect(adapter.clearTokenCount, 1);
        expect(adapter.lastClearedToken, adapter.interactiveAccessToken);
        expect(adapter.authorizationForScopesCount, 1);

        // TTL (50 dk) dolduğunda da sessiz yenileme çalışır.
        now = now.add(const Duration(minutes: 55));
        adapter.silentAccessToken = 'ya29.ttl-renewed-999';
        final renewed = await provider.accessToken();
        expect(renewed, 'ya29.ttl-renewed-999');
        expect(adapter.authorizationForScopesCount, 2);
      },
    );

    test(
      '4. Sessiz yenileme null döndüğünde ERR_DRIVE_REAUTH_REQUIRED fırlatılır',
      () async {
        final adapter = _FakeGoogleSignInAdapter();
        final store = InMemorySecureTokenStore();
        final provider = AndroidGoogleSignInTokenProvider(
          serverClientId: 'web-client.apps.googleusercontent.com',
          adapter: adapter,
          secureStore: store,
        );

        await provider.connect();
        adapter.silentAccessToken = null;

        await expectLater(
          () => provider.accessToken(forceRefresh: true),
          throwsA(
            isA<DriveBackupException>()
                .having((e) => e.code, 'code', 'ERR_DRIVE_REAUTH_REQUIRED'),
          ),
        );
      },
    );

    test(
      '5. Soğuk başlatma: attemptLightweightAuthentication başarı ve null senaryoları',
      () async {
        final adapter = _FakeGoogleSignInAdapter()
          ..lightweightAccountToReturn = const AndroidGoogleAccount(
            id: 'gid-202',
            email: 'sube@example.com',
          )
          ..silentAccessToken = 'ya29.cold-start-ok';
        final store = InMemorySecureTokenStore();
        await store.saveSecret(
          AndroidGoogleSignInTokenProvider.connectedFlagSecretKey,
          'true',
        );

        final provider = AndroidGoogleSignInTokenProvider(
          serverClientId: 'web-client.apps.googleusercontent.com',
          adapter: adapter,
          secureStore: store,
        );

        expect(await provider.isConnected(), isTrue);
        expect(await provider.accessToken(), 'ya29.cold-start-ok');
        expect(adapter.lightweightCount, 1);

        // Oturum sessiz geri yüklenemezse ERR_DRIVE_REAUTH_REQUIRED döner.
        final failedAdapter = _FakeGoogleSignInAdapter()
          ..lightweightAccountToReturn = null;
        final failedProvider = AndroidGoogleSignInTokenProvider(
          serverClientId: 'web-client.apps.googleusercontent.com',
          adapter: failedAdapter,
          secureStore: store,
        );
        await expectLater(
          () => failedProvider.accessToken(),
          throwsA(
            isA<DriveBackupException>()
                .having((e) => e.code, 'code', 'ERR_DRIVE_REAUTH_REQUIRED'),
          ),
        );
      },
    );

    test(
      '6. disconnect() uzak iptali dener, çevrimdışı hatada signOut() fallback yapar ve yerel DB/Outbox\'a dokunmaz',
      () async {
        final adapter = _FakeGoogleSignInAdapter()
          ..disconnectError = const DriveBackupException(
            'ERR_DRIVE_UNAVAILABLE',
            'Ağ yok',
          );
        final store = InMemorySecureTokenStore();
        final localDb = LocalDatabaseService.forTesting(NativeDatabase.memory());
        addTearDown(() async => localDb.close());

        await localDb.repository.upsertProducts([
          LocalProductsCompanion(
            id: const Value('prod-keep'),
            barcode: const Value('8690000000011'),
            name: const Value('Korunan Ürün'),
            price: const Value(1500),
            stock: const Value(10000),
            updatedAt: Value(DateTime.utc(2026, 11, 22, 10, 0)),
          ),
        ]);
        await localDb.repository.createOfflineSale(
          deviceId: 'DEV-AND-1',
          paymentMethod: 'CASH',
          items: [CartItemInput.units('prod-keep', 1)],
        );

        final provider = AndroidGoogleSignInTokenProvider(
          serverClientId: 'web-client.apps.googleusercontent.com',
          adapter: adapter,
          secureStore: store,
        );
        await provider.connect();
        expect(await provider.isConnected(), isTrue);

        await provider.disconnect();

        expect(adapter.clearTokenCount, 1);
        expect(adapter.disconnectCount, 1);
        expect(adapter.signOutCount, 1);
        expect(await provider.isConnected(), isFalse);
        expect(
          await store.readSecret(
            AndroidGoogleSignInTokenProvider.connectedFlagSecretKey,
          ),
          isNull,
        );
        // Yerel satış ve Outbox kesinlikle korunur.
        expect(
          await localDb.repository.getUnsyncedOutboxOperations('DEV-AND-1'),
          hasLength(1),
        );
      },
    );

    test(
      '7. PluginGoogleSignInClientAdapter GMS/Config/Cancel/UI hatalarını güvenli kodlara eşler ve token sızdırmaz',
      () {
        final pluginAdapter = PluginGoogleSignInClientAdapter();

        expect(
          pluginAdapter.mapError(MissingPluginException('No plugin')).code,
          'ERR_DRIVE_GMS_UNAVAILABLE',
        );
        expect(
          pluginAdapter
              .mapError(
                const GoogleSignInException(
                  code: GoogleSignInExceptionCode.clientConfigurationError,
                  description: 'secret-token-leak-test',
                ),
              )
              .code,
          'ERR_DRIVE_NOT_CONFIGURED',
        );
        expect(
          pluginAdapter
              .mapError(
                const GoogleSignInException(
                  code: GoogleSignInExceptionCode.providerConfigurationError,
                ),
              )
              .code,
          'ERR_DRIVE_GMS_UNAVAILABLE',
        );
        expect(
          pluginAdapter
              .mapError(
                const GoogleSignInException(
                  code: GoogleSignInExceptionCode.uiUnavailable,
                ),
              )
              .code,
          'ERR_DRIVE_REAUTH_REQUIRED',
        );
        expect(
          pluginAdapter
              .mapError(
                const GoogleSignInException(
                  code: GoogleSignInExceptionCode.canceled,
                ),
              )
              .code,
          'ERR_OAUTH_DENIED',
        );
        expect(
          pluginAdapter
              .mapError(
                const GoogleSignInException(
                  code: GoogleSignInExceptionCode.userMismatch,
                ),
              )
              .code,
          'ERR_DRIVE_REAUTH_REQUIRED',
        );
        expect(
          pluginAdapter
              .mapError(PlatformException(code: 'SERVICE_MISSING', message: 'gms missing'))
              .code,
          'ERR_DRIVE_GMS_UNAVAILABLE',
        );
        expect(
          pluginAdapter
              .mapError(PlatformException(code: 'DEVELOPER_ERROR', message: '10: sha1 mismatch'))
              .code,
          'ERR_DRIVE_NOT_CONFIGURED',
        );

        final mapped = pluginAdapter.mapError(
          PlatformException(code: 'INTERNAL', message: 'raw-secret-ya29.abc'),
        );
        expect(mapped.code, 'ERR_DRIVE_UNAVAILABLE');
        expect(mapped.message, isNot(contains('ya29.abc')));
      },
    );

    testWidgets(
      '8. ExternalBackupSection Android mobil profilde bağlan / kaldır butonunu gösterir ve banner fail-safe çalışır',
      (tester) async {
        await tester.runAsync(() async {
          final tempDir = Directory.systemTemp.createTempSync('mms_adr022_ui_');
          final store = InMemorySecureTokenStore();
          final adapter = _FakeGoogleSignInAdapter();
          final dummyDb = LocalDatabaseService.forTesting(
            NativeDatabase.memory(),
            path: p.join(tempDir.path, 'ui_android.db'),
          );
          final fakeDrive = _FakeLiveSyncDriveServer();
          final driveHttp = fakeDrive.createClient();

          addTearDown(() async {
            await dummyDb.close();
            driveHttp.close();
            if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
          });

          // A) Yapılandırılmamış (MMS_GDRIVE_WEB_CLIENT_ID boş) Android -> gdrive_not_configured_banner
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                mmsUiProfileProvider.overrideWithValue(const MmsUiProfile.mobile()),
                localDatabaseServiceProvider.overrideWithValue(dummyDb),
                secureTokenStoreProvider.overrideWithValue(store),
                driveIsAndroidPlatformProvider.overrideWithValue(true),
                googleDriveWebClientIdProvider.overrideWithValue(''),
                googleSignInClientAdapterProvider.overrideWithValue(adapter),
              ],
              child: MaterialApp(
                theme: AppTheme.lightTheme,
                home: const Scaffold(
                  body: SingleChildScrollView(child: ExternalBackupSection()),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(find.byKey(const Key('gdrive_not_configured_banner')), findsOneWidget);
          expect(find.byKey(const Key('gdrive_connect_button')), findsNothing);

          // B) Yapılandırılmış Android -> gdrive_connect_button görünür, bağlanır ve kaldırır
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                mmsUiProfileProvider.overrideWithValue(const MmsUiProfile.mobile()),
                localDatabaseServiceProvider.overrideWithValue(dummyDb),
                secureTokenStoreProvider.overrideWithValue(store),
                driveIsAndroidPlatformProvider.overrideWithValue(true),
                googleDriveWebClientIdProvider
                    .overrideWithValue('web-client-android.apps.googleusercontent.com'),
                googleSignInClientAdapterProvider.overrideWithValue(adapter),
              ],
              child: MaterialApp(
                theme: AppTheme.lightTheme,
                home: const Scaffold(
                  body: SingleChildScrollView(child: ExternalBackupSection()),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump();

          expect(find.byKey(const Key('gdrive_connect_button')), findsOneWidget);
          expect(find.text("Google Drive'ı Bağla"), findsOneWidget);

          await tester.tap(find.byKey(const Key('gdrive_connect_button')));
          await tester.pump();
          await tester.pump();

          expect(adapter.authenticateCount, 1);
          expect(adapter.authorizeScopesCount, 1);
          expect(find.text('Bağlantıyı Kaldır'), findsOneWidget);
          expect(find.byKey(const Key('gdrive_list_backups_button')), findsOneWidget);

          await tester.tap(find.byKey(const Key('gdrive_connect_button')));
          await tester.pump();
          await tester.pump();

          expect(adapter.disconnectCount, 1);
          expect(find.text("Google Drive'ı Bağla"), findsOneWidget);

          await tester.pumpWidget(const SizedBox.shrink());
        });
      },
    );

    test(
      '9. ADR-021 + ADR-022 E2E: Hub healthy iken 0 Drive çağrısı, Hub offline iken MMSENV01 yüklenir/401 yenilenir, TLS/Auth reddinde 0 Drive çağrısı',
      () async {
        final tempDir = Directory.systemTemp.createTempSync('mms_adr022_e2e_');
        final dbService = await LocalDatabaseService.initialize(
          customPath: p.join(tempDir.path, 'android_e2e.db'),
        );
        final store = InMemorySecureTokenStore();
        final adapter = _FakeGoogleSignInAdapter()
          ..silentAccessToken = 'ya29.recovered-after-401';
        final fakeDrive = _FakeLiveSyncDriveServer();
        final driveHttp = fakeDrive.createClient();

        addTearDown(() async {
          driveHttp.close();
          await LocalDatabaseService.closeActive();
          LocalDatabaseService.resetForTesting();
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });

        const tenantId = 'tenant-e2e';
        const storeId = 'store-e2e';
        const deviceId = 'DEV-ANDROID-01';
        const liveSecret = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

        final tokenProvider = AndroidGoogleSignInTokenProvider(
          serverClientId: 'web-client-e2e.apps.googleusercontent.com',
          adapter: adapter,
          secureStore: store,
        );
        await tokenProvider.connect();

        final connectCountAfterAuth = adapter.authorizationForScopesCount;
        final registry = DriveAuthorizedDeviceRegistry([
          DriveAuthorizedDevice(
            deviceId: deviceId,
            tenantId: tenantId,
            storeId: storeId,
            status: DriveSyncDeviceStatus.active,
            updatedAtUtc: DateTime.utc(2026, 11, 22, 10, 0),
          ),
        ]);

        final engine = MmsDriveLiveSyncEngine(
          repository: dbService.repository,
          transport: GoogleDriveLiveEnvelopeTransport(
            tokenProvider: tokenProvider,
            httpClient: driveHttp,
            baseDelay: Duration.zero,
          ),
          ledger: DriveLiveSyncLedger(
            File(p.join(tempDir.path, 'live_ledger.json')),
          ),
          deviceRegistry: registry,
          tenantId: tenantId,
          storeId: storeId,
          localDeviceId: deviceId,
          readLiveSyncSecret: () async => liveSecret,
          kdfIterations: 100,
        );

        await dbService.repository.upsertProducts([
          LocalProductsCompanion(
            id: const Value('prod-adr022'),
            barcode: const Value('8698888777666'),
            name: const Value('E2E Ürün'),
            price: const Value(2000),
            stock: const Value(10000),
            updatedAt: Value(DateTime.utc(2026, 11, 22, 10, 0)),
          ),
        ]);
        await dbService.repository.createOfflineSale(
          deviceId: deviceId,
          paymentMethod: 'CASH',
          items: [CartItemInput.units('prod-adr022', 1)],
        );

        // A) Hub sağlıklı iken 0 Drive çağrısı ve fallback kapalı
        final healthyState = await engine.recordHubHealthy();
        expect(healthyState.driveFallbackActive, isFalse);
        expect(fakeDrive.apiRequestCount, 0);

        // B) TLS pin/Auth hatasında Drive fallback ASLA açılmaz (0 Drive çağrısı)
        final secState = await engine.recordHubFailure(
          isSecurityHold: true,
          isAuthFailure: false,
        );
        final authState = await engine.recordHubFailure(
          isSecurityHold: false,
          isAuthFailure: true,
        );
        expect(secState.driveFallbackActive, isFalse);
        expect(authState.driveFallbackActive, isFalse);
        expect(fakeDrive.apiRequestCount, 0);
        expect(adapter.authorizationForScopesCount, connectCountAfterAuth);

        // C) 2 ardışık ağ hatası -> Drive fallback açılır ve 401 anında forceRefresh çalışıp MMSENV01 yüklenir!
        fakeDrive.forceNextGet401 = true;
        final fail1 = await engine.recordHubFailure(
          isSecurityHold: false,
          isAuthFailure: false,
        );
        expect(fail1.driveFallbackActive, isFalse);
        final fail2 = await engine.recordHubFailure(
          isSecurityHold: false,
          isAuthFailure: false,
        );
        expect(fail2.driveFallbackActive, isTrue);

        final liveCycle = await engine.runDriveFallbackCycle();

        expect(liveCycle.uploadedCount, 1);
        expect(liveCycle.hasErrors, isFalse);
        expect(fakeDrive.files, hasLength(1));
        expect(adapter.clearTokenCount, 1);
        expect(adapter.authorizationForScopesCount, connectCountAfterAuth + 1);
        // Hub ACK henüz alınmadığından Outbox PENDING kalır!
        expect(
          await dbService.repository.getUnsyncedOutboxOperations(deviceId),
          hasLength(1),
        );
      },
    );
  });
}
