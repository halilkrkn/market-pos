import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/core/network/api_client.dart';
import 'package:market_pos/core/security/secure_token_store.dart';
import 'package:market_pos/core/security/security_providers.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:market_pos/features/setup/domain/app_setup_config.dart';
import 'package:market_pos/features/setup/setup_providers.dart';
import 'package:market_pos/features/sync/data/drive_authorized_registry_store.dart';
import 'package:market_pos/features/sync/data/hub_live_drive_config_client.dart';
import 'package:market_pos/features/sync/domain/hub_connection_state.dart';
import 'package:market_pos/features/sync/application/hub_connection_notifier.dart';
import 'package:market_pos/features/sync/sync_providers.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

class _FakeCleanSyncTransport implements SyncTransport {
  @override
  Future<SyncResponse> postSale({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(statusCode: 201, body: '{"status":"COMMITTED"}');

  @override
  Future<SyncResponse> postProductUpsert({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(statusCode: 200, body: '{"status":"COMMITTED"}');

  @override
  Future<SyncResponse> postStockReceipt({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(statusCode: 200, body: '{"status":"COMMITTED"}');

  @override
  Future<SyncResponse> getProducts({
    required String hubUrl,
    required String token,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(
        statusCode: 200,
        body: '{"products":[],"sync_session_id":"s1"}',
      );

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
        body: jsonEncode({
          'status': 'OK',
          'sales': <dynamic>[],
          'last_server_sale_seq': cursor,
          'has_more': false,
        }),
      );

  @override
  Future<SyncResponse> postSyncAck({
    required String hubUrl,
    required String token,
    required String syncSessionId,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(statusCode: 200, body: '{"status":"ACK"}');

  @override
  void close() {}
}

class _SharedInMemoryDriveTransport implements DriveLiveEnvelopeTransport {
  final Map<String, ({String fileName, Uint8List bytes, Map<String, String> appProperties})>
      stored = {};
  int _seq = 0;

  @override
  Future<String> ensureSyncFolder() async => 'drive-folder-k05';

  @override
  Future<String> uploadEnvelope({
    required String folderId,
    required String fileName,
    required Uint8List bytes,
    required Map<String, String> appProperties,
  }) async {
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

  const tenantId = 'tenant-k05-client';
  const storeId = 'store-k05-client';
  const validSecret = 'SharedLiveDriveSecret_2026_AtLeast32Chars!!';

  group('K-05 İstemci Provizyon & Kalıcı Cihaz Kayıt Defteri Testleri', () {
    test('FileDriveAuthorizedRegistryStore atomik yazma ve okuma döngüsü ACTIVE/REVOKED durumlarını korur', () async {
      final dir = Directory.systemTemp.createTempSync('mms_k05_reg_store_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final store = FileDriveAuthorizedRegistryStore.inDirectory(dir);
      final emptyLoaded = await store.load();
      expect(emptyLoaded.all, isEmpty);

      final reg = DriveAuthorizedDeviceRegistry()
        ..authorizeDevice(
          deviceId: 'DEV-A',
          tenantId: tenantId,
          storeId: storeId,
          updatedAtUtc: DateTime.utc(2026, 11, 22, 1, 0),
        )
        ..authorizeDevice(
          deviceId: 'DEV-B',
          tenantId: tenantId,
          storeId: storeId,
          updatedAtUtc: DateTime.utc(2026, 11, 22, 1, 5),
        )
        ..revokeDevice('DEV-B', updatedAtUtc: DateTime.utc(2026, 11, 22, 1, 10));

      await store.save(reg);
      final reloaded = await store.load();
      expect(reloaded.find('DEV-A')?.isActive, isTrue);
      expect(reloaded.find('DEV-B')?.status, DriveSyncDeviceStatus.revoked);

      // Bozuk JSON dosyası uygulamayı çökertmez
      final file = File(p.join(dir.path, FileDriveAuthorizedRegistryStore.defaultFileName));
      await file.writeAsString('{corrupt_json', flush: true);
      final recovered = await store.load();
      expect(recovered.all, isEmpty);
    });

    test('HubLiveDriveConfigClient yanıt ayrıştırma, 404 uyumu, tenant/store ve zayıf sır reddini doğrular', () async {
      // 1. Geçerli 200 OK yanıtı
      final okClient = HubLiveDriveConfigClient(
        httpClient: MockClient((req) async {
          expect(req.url.path, '/api/v1/sync/live-drive-config');
          expect(req.headers['authorization'], 'Bearer tok_a');
          expect(req.headers['x-mms-tenant-id'], tenantId);
          expect(req.headers['x-mms-store-id'], storeId);
          return http.Response(
            jsonEncode({
              'version': 1,
              'tenant_id': tenantId,
              'store_id': storeId,
              'hub_id': 'HUB-1',
              'live_sync_secret': validSecret,
              'authorized_devices': [
                {
                  'device_id': 'DEV-A',
                  'tenant_id': tenantId,
                  'store_id': storeId,
                  'status': 'ACTIVE',
                  'updated_at': '2026-11-22T01:00:00Z',
                },
                {
                  'device_id': 'DEV-B',
                  'tenant_id': tenantId,
                  'store_id': storeId,
                  'status': 'ACTIVE',
                  'updated_at': '2026-11-22T01:01:00Z',
                },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(okClient.close);

      final cfg = await okClient.fetchConfig(
        hubUrl: 'https://192.168.1.50:8945',
        deviceToken: 'tok_a',
        tenantId: tenantId,
        storeId: storeId,
      );
      expect(cfg, isNotNull);
      expect(cfg!.liveSyncSecret, validSecret);
      expect(cfg.authorizedDevices, hasLength(2));

      // 2. 404 eski Hub -> null döner (hata fırlatmaz)
      final oldHubClient = HubLiveDriveConfigClient(
        httpClient: MockClient((_) async => http.Response('{}', 404)),
      );
      addTearDown(oldHubClient.close);
      expect(
        await oldHubClient.fetchConfig(
          hubUrl: 'https://192.168.1.50:8945',
          deviceToken: 'tok_a',
          tenantId: tenantId,
          storeId: storeId,
        ),
        isNull,
      );

      // 3. Tenant/Store uyuşmazlığı -> reddedilir
      final wrongTenantClient = HubLiveDriveConfigClient(
        httpClient: MockClient((_) async => http.Response(
              jsonEncode({
                'tenant_id': 'other-tenant',
                'store_id': storeId,
                'live_sync_secret': validSecret,
                'authorized_devices': <dynamic>[],
              }),
              200,
            )),
      );
      addTearDown(wrongTenantClient.close);
      await expectLater(
        () => wrongTenantClient.fetchConfig(
          hubUrl: 'https://192.168.1.50:8945',
          deviceToken: 'tok_a',
          tenantId: tenantId,
          storeId: storeId,
        ),
        throwsA(isA<StateError>()),
      );

      // 4. Zayıf sır (< 32 karakter) -> reddedilir
      final weakSecretClient = HubLiveDriveConfigClient(
        httpClient: MockClient((_) async => http.Response(
              jsonEncode({
                'tenant_id': tenantId,
                'store_id': storeId,
                'live_sync_secret': 'short_secret',
                'authorized_devices': <dynamic>[],
              }),
              200,
            )),
      );
      addTearDown(weakSecretClient.close);
      await expectLater(
        () => weakSecretClient.fetchConfig(
          hubUrl: 'https://192.168.1.50:8945',
          deviceToken: 'tok_a',
          tenantId: tenantId,
          storeId: storeId,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('2 cihaz uçtan uca Hub provizyonu: MMSENV01 zarf paylaşımı ve iptal sonrası ERR_DEVICE_UNAUTHORIZED / REVOKED', () async {
      final tmpDir = Directory.systemTemp.createTempSync('mms_k05_e2e_');
      addTearDown(() {
        if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
      });

      final dbFileA = File(p.join(tmpDir.path, 'dev_a.db'));
      final dbFileB = File(p.join(tmpDir.path, 'dev_b.db'));
      final localDbA = LocalDatabaseService.forTesting(
        NativeDatabase(dbFileA),
        path: dbFileA.path,
      );
      final localDbB = LocalDatabaseService.forTesting(
        NativeDatabase(dbFileB),
        path: dbFileB.path,
      );
      addTearDown(() async {
        await localDbA.close();
        await localDbB.close();
      });

      Future<void> seedProduct(ClientStorageRepository repo) async {
        await repo.upsertProducts([
          LocalProductsCompanion(
            id: const Value('prod_1'),
            barcode: const Value('8690001'),
            name: const Value('Süt 1L'),
            price: const Value(3500),
            stock: const Value(20000),
            updatedAt: Value(DateTime.utc(2026, 11, 22, 1, 0)),
          ),
        ]);
      }

      await seedProduct(localDbA.repository);
      await seedProduct(localDbB.repository);

      var deviceAIsActiveOnHub = true;
      final mockHubHttp = MockClient((req) async {
        if (req.url.path == '/api/v1/sync/live-drive-config') {
          return http.Response(
            jsonEncode({
              'version': 1,
              'tenant_id': tenantId,
              'store_id': storeId,
              'hub_id': 'HUB-MASTER',
              'live_sync_secret': validSecret,
              'authorized_devices': [
                {
                  'device_id': 'DEV-A',
                  'tenant_id': tenantId,
                  'store_id': storeId,
                  'status': deviceAIsActiveOnHub ? 'ACTIVE' : 'REVOKED',
                  'updated_at': '2026-11-22T01:00:00Z',
                },
                {
                  'device_id': 'DEV-B',
                  'tenant_id': tenantId,
                  'store_id': storeId,
                  'status': 'ACTIVE',
                  'updated_at': '2026-11-22T01:00:00Z',
                },
              ],
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      });

      final storeA = InMemorySecureTokenStore();
      final storeB = InMemorySecureTokenStore();
      final regStoreA = FileDriveAuthorizedRegistryStore(
        file: File(p.join(tmpDir.path, 'reg_a.json')),
      );
      final regStoreB = FileDriveAuthorizedRegistryStore(
        file: File(p.join(tmpDir.path, 'reg_b.json')),
      );

      ProviderContainer buildContainer({
        required LocalDatabaseService localDb,
        required InMemorySecureTokenStore secureStore,
        required FileDriveAuthorizedRegistryStore regStore,
        required String deviceId,
        required String token,
      }) {
        return ProviderContainer(
          overrides: [
            localDatabaseServiceProvider.overrideWithValue(localDb),
            secureTokenStoreProvider.overrideWithValue(secureStore),
            initialSetupConfigProvider.overrideWithValue(
              AppSetupConfig(
                isSetupCompleted: true,
                tenantId: tenantId,
                storeId: storeId,
                deviceId: deviceId,
              ),
            ),
            initialStoredDeviceTokenProvider.overrideWithValue(token),
            hubAllowLoopbackPolicyProvider.overrideWithValue(false),
            hubAutoDiscoveryLifecycleEnabledProvider.overrideWithValue(false),
            initialHubConnectionStateProvider.overrideWithValue(
              const HubConnectionState(
                phase: HubConnectionPhase.connected,
                activeHubUrl: 'https://192.168.1.50:8945',
                hubId: 'HUB-MASTER',
                source: HubUrlSource.discovered,
                isInitialized: true,
              ),
            ),
            syncTransportProvider.overrideWithValue(_FakeCleanSyncTransport()),
            driveAuthorizedRegistryStoreProvider.overrideWithValue(regStore),
            hubLiveDriveConfigClientProvider.overrideWithValue(
              HubLiveDriveConfigClient(httpClient: mockHubHttp),
            ),
            apiClientProvider.overrideWith(
              (ref) => MmsApiClient(
                client: mockHubHttp,
                readBaseUrl: () => ref.read(hubConnectionProvider).activeHubUrl,
                allowLoopback: false,
                deviceId: deviceId,
                deviceToken: token,
              ),
            ),
          ],
        );
      }

      final containerA = buildContainer(
        localDb: localDbA,
        secureStore: storeA,
        regStore: regStoreA,
        deviceId: 'DEV-A',
        token: 'tok_a',
      );
      final containerB = buildContainer(
        localDb: localDbB,
        secureStore: storeB,
        regStore: regStoreB,
        deviceId: 'DEV-B',
        token: 'tok_b',
      );
      addTearDown(containerA.dispose);
      addTearDown(containerB.dispose);

      // 1. Her iki cihaz da sağlıklı Hub sync sonrası ortak secret & peer registry alır
      await containerA.read(backgroundSyncCoordinatorProvider.notifier).triggerSync();
      await containerB.read(backgroundSyncCoordinatorProvider.notifier).triggerSync();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(await storeA.readSecret(kDriveLiveSyncSecretKey), validSecret);
      expect(await storeB.readSecret(kDriveLiveSyncSecretKey), validSecret);
      expect(containerA.read(driveAuthorizedRegistryProvider).find('DEV-B')?.isActive, isTrue);
      expect(containerB.read(driveAuthorizedRegistryProvider).find('DEV-A')?.isActive, isTrue);

      // 2. Hub artık erişilemez olsun -> Cihaz A satış yapar ve MMSENV01 zarfı Drive'a yükler, Cihaz B kabul eder
      final driveTransport = _SharedInMemoryDriveTransport();
      final engineA = MmsDriveLiveSyncEngine(
        repository: localDbA.repository,
        transport: driveTransport,
        ledger: DriveLiveSyncLedger(File(p.join(tmpDir.path, 'ledger_a.json'))),
        deviceRegistry: containerA.read(driveAuthorizedRegistryProvider),
        tenantId: tenantId,
        storeId: storeId,
        localDeviceId: 'DEV-A',
        readLiveSyncSecret: () => storeA.readSecret(kDriveLiveSyncSecretKey),
        kdfIterations: 100,
      );
      var engineB = MmsDriveLiveSyncEngine(
        repository: localDbB.repository,
        transport: driveTransport,
        ledger: DriveLiveSyncLedger(File(p.join(tmpDir.path, 'ledger_b.json'))),
        deviceRegistry: containerB.read(driveAuthorizedRegistryProvider),
        tenantId: tenantId,
        storeId: storeId,
        localDeviceId: 'DEV-B',
        readLiveSyncSecret: () => storeB.readSecret(kDriveLiveSyncSecretKey),
        kdfIterations: 100,
      );

      await localDbA.repository.createOfflineSale(
        deviceId: 'DEV-A',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_1', 2)],
      );

      await engineA.recordHubFailure(
        isSecurityHold: false,
        isAuthFailure: false,
      );
      await engineA.recordHubFailure(
        isSecurityHold: false,
        isAuthFailure: false,
      );
      final upA = await engineA.runDriveFallbackCycle();
      expect(upA.uploadedCount, 1);

      await engineB.recordHubFailure(
        isSecurityHold: false,
        isAuthFailure: false,
      );
      await engineB.recordHubFailure(
        isSecurityHold: false,
        isAuthFailure: false,
      );
      final downB = await engineB.runDriveFallbackCycle();
      expect(downB.appliedCount, 1);
      expect(downB.hasErrors, isFalse);
      expect((await localDbB.repository.getProductById('prod_1'))!.stock, 18000);

      // 3. Hub DEV-A'yı iptal eder -> Cihaz B snapshot'ı uygular ve DEV-A'nın yeni zarfını reddeder
      deviceAIsActiveOnHub = false;
      final cfgResp = await HubLiveDriveConfigClient(httpClient: mockHubHttp).fetchConfig(
        hubUrl: 'https://192.168.1.50:8945',
        deviceToken: 'tok_b',
        tenantId: tenantId,
        storeId: storeId,
      );
      await containerB.read(driveAuthorizedRegistryNotifierProvider.notifier).applyHubSnapshot(
            devices: cfgResp!.authorizedDevices,
            localDeviceId: 'DEV-B',
            tenantId: tenantId,
            storeId: storeId,
          );
      expect(
        containerB.read(driveAuthorizedRegistryProvider).find('DEV-A')?.status,
        DriveSyncDeviceStatus.revoked,
      );

      // DEV-A'nın yeni bir satışı daha Drive'a yüklenir
      await localDbA.repository.createOfflineSale(
        deviceId: 'DEV-A',
        paymentMethod: 'CARD',
        items: [CartItemInput.units('prod_1', 1)],
      );
      final upA2 = await engineA.runDriveFallbackCycle();
      expect(upA2.uploadedCount, 1);

      engineB = MmsDriveLiveSyncEngine(
        repository: localDbB.repository,
        transport: driveTransport,
        ledger: DriveLiveSyncLedger(File(p.join(tmpDir.path, 'ledger_b.json'))),
        deviceRegistry: containerB.read(driveAuthorizedRegistryProvider),
        tenantId: tenantId,
        storeId: storeId,
        localDeviceId: 'DEV-B',
        readLiveSyncSecret: () => storeB.readSecret(kDriveLiveSyncSecretKey),
        kdfIterations: 100,
      );
      await engineB.recordHubFailure(
        isSecurityHold: false,
        isAuthFailure: false,
      );
      await engineB.recordHubFailure(
        isSecurityHold: false,
        isAuthFailure: false,
      );
      final downB2 = await engineB.runDriveFallbackCycle();
      expect(downB2.appliedCount, 0);
      expect(downB2.rejectedSecurityCount, greaterThan(0));
      expect(downB2.hasErrors, isFalse);
      expect(
        () => containerB.read(driveAuthorizedRegistryProvider).requireAuthorized(
              deviceId: 'DEV-A',
              tenantId: tenantId,
              storeId: storeId,
            ),
        throwsA(
          isA<DriveSyncSecurityException>().having(
            (e) => e.code,
            'code',
            'ERR_DEVICE_REVOKED',
          ),
        ),
      );
      expect((await localDbB.repository.getProductById('prod_1'))!.stock, 18000);
    });
  });
}
