import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/core/logging/diagnostics_report_exporter.dart';
import 'package:market_pos/core/logging/redacting_logger.dart';
import 'package:market_pos/core/network/api_client.dart';
import 'package:market_pos/core/platform/mms_ui_profile.dart';
import 'package:market_pos/core/security/client_ecdsa_p256.dart';
import 'package:market_pos/core/security/secure_token_store.dart';
import 'package:market_pos/core/security/security_providers.dart';
import 'package:market_pos/core/security/tls_pinned_client_factory.dart';
import 'package:market_pos/core/security/windows_dpapi_token_store.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/core/theme/app_theme.dart';
import 'package:market_pos/features/backup/application/client_backup_service.dart';
import 'package:market_pos/features/backup/backup_providers.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:market_pos/features/diagnostics/domain/system_status.dart';
import 'package:market_pos/features/diagnostics/presentation/screens/diagnostics_view.dart';
import 'package:market_pos/features/security/data/device_pairing_client.dart';
import 'package:market_pos/features/security/domain/pairing_qr_payload.dart';
import 'package:market_pos/features/setup/application/setup_config_notifier.dart';
import 'package:market_pos/features/setup/data/local_setup_config_store.dart';
import 'package:market_pos/features/setup/domain/app_setup_config.dart';
import 'package:market_pos/features/setup/setup_providers.dart';
import 'package:market_pos/features/sync/application/hub_connection_notifier.dart';
import 'package:market_pos/features/sync/domain/hub_connection_state.dart';
import 'package:market_pos/features/sync/domain/sync_coordinator_state.dart';
import 'package:market_pos/features/updates/data/app_update_checker.dart';
import 'package:market_pos/features/updates/domain/app_update_info.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Faz 7.1: Çoklu Şube / Tenant Kurulum Yapılandırması', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('mms_faz7_setup_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'FileSetupConfigStore ayarları client_config.json içine atomik kaydeder ve yeniden yükler',
      () async {
        final store = FileSetupConfigStore.inDirectory(tempDir);
        final notifier = SetupConfigNotifier(
          store: store,
          initialState: await store.load(),
        );
        expect(notifier.state.isSetupCompleted, isFalse);

        await notifier.completeInitialSetup(
          tenantId: 'tenant-anatolia',
          storeId: 'store-042',
          storeName: 'Kadıköy Şubesi',
          deviceId: 'POS-KDK-01',
          deviceName: 'Kasa 1',
        );
        await notifier.updateTlsPinning(
          enabled: true,
          sha256Hex: 'ab:cd:${'ef' * 30}',
        );

        final reloadedStore = FileSetupConfigStore.inDirectory(tempDir);
        final reloaded = await reloadedStore.load();
        expect(reloaded.isSetupCompleted, isTrue);
        expect(reloaded.tenantId, 'tenant-anatolia');
        expect(reloaded.storeId, 'store-042');
        expect(reloaded.storeName, 'Kadıköy Şubesi');
        expect(reloaded.deviceId, 'POS-KDK-01');
        expect(reloaded.deviceName, 'Kasa 1');
        expect(reloaded.tlsPinningEnabled, isTrue);
        expect(reloaded.normalizedPinSha256, hasLength(64));
      },
    );

    test('bozuk client_config.json çökmeden varsayılan ayarlara döner', () async {
      final store = FileSetupConfigStore.inDirectory(tempDir);
      store.configFile.writeAsStringSync('{corrupt-json');
      final loaded = await store.load();
      expect(loaded.isSetupCompleted, isFalse);
      expect(loaded.tenantId, AppSetupConfig.defaultTenantId);
    });
  });

  group('Faz 7.2: Gerçek FFI S5A-4 Şifreli Yedekleme ve Rollback-Safe Kurtarma', () {
    late Directory tempDir;
    late String dbPath;

    setUp(() {
      LocalDatabaseService.resetForTesting();
      tempDir = Directory.systemTemp.createTempSync('mms_faz7_backup_');
      dbPath = p.join(tempDir.path, 'client_local.db');
    });

    tearDown(() async {
      await LocalDatabaseService.closeActive();
      LocalDatabaseService.resetForTesting();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'şifreli yedek alır, yanlış parolayı reddeder, doğru parolayla geri yükleyip Outbox ve DB şemasını korur',
      () async {
        const setup = AppSetupConfig(
          isSetupCompleted: true,
          tenantId: 'tenant-1',
          storeId: 'store-1',
          storeName: 'Merkez',
          deviceId: 'POS-BAK-01',
          deviceName: 'Ana Kasa',
        );

        final dbService = await LocalDatabaseService.initialize(
          customPath: dbPath,
        );
        expect(dbService.database.schemaVersion, 4);
        await dbService.repository.initializeDevice(setup.deviceId);

        await dbService.repository.upsertProducts(
          <LocalProductsCompanion>[
            LocalProductsCompanion(
              id: const Value('prod_cay'),
              barcode: const Value('8690505000011'),
              name: const Value('Rize Turist Çayı 500g'),
              price: const Value(9500),
              priceVersionId: const Value('pv_cay_1'),
              stock: const Value(15000),
              stockUnit: const Value('adet'),
              pricingUnit: const Value('adet'),
              conversionFactorNumerator: const Value(1),
              conversionFactorDenominator: const Value(1),
              isActive: const Value(true),
              updatedAt: Value(DateTime(2026, 11, 20, 12, 0)),
            ),
          ],
          barcodes: const <LocalProductBarcodesCompanion>[
            LocalProductBarcodesCompanion(
              id: Value('bc_cay'),
              productId: Value('prod_cay'),
              barcode: Value('8690505000011'),
              isPrimary: Value(true),
              isActive: Value(true),
            ),
          ],
        );

        await dbService.repository.createOfflineSale(
          deviceId: setup.deviceId,
          paymentMethod: PaymentMethod.cash.code,
          items: <CartItemInput>[
            CartItemInput(
              productId: 'prod_cay',
              quantity: 1000,
              expectedUnitPrice: 9500,
              expectedPriceVersionId: 'pv_cay_1',
            ),
          ],
        );
        expect(await dbService.getLocalSalesCount(), 1);
        expect((await dbService.getOutboxSummary(deviceId: setup.deviceId)).totalUnsynced, 1);

        final backupDir = Directory(p.join(tempDir.path, 'backups'));
        final backupService = ClientBackupService(
          dbService: dbService,
          backupRootDir: backupDir,
          readSetupConfig: () => setup,
          kdfIterations: 1000,
          databaseTypeOverride: DatabaseType.clientLocal,
        );

        final backup = await backupService.createEncryptedBackup(
          password: 'StrongPassword#2026',
        );
        final listed = await backupService.listBackups();
        expect(listed, hasLength(1));

        // Paket içeriğinin şifreli olduğunu ve düz SQLite başlığı/veri içermediğini doğrula
        final rawPackage = listed.first.file.readAsBytesSync();
        expect(ascii.decode(rawPackage.sublist(0, 8)), 'MMSBAK01');
        expect(
          utf8.decode(rawPackage, allowMalformed: true),
          isNot(contains('SQLite format 3')),
        );
        expect(
          utf8.decode(rawPackage, allowMalformed: true),
          isNot(contains('Rize Turist Çayı 500g')),
        );

        // Yedek sonrası yeni bir değişiklik yapıp geri yüklemenin önceki duruma döndüğünü test et
        await dbService.repository.createProduct(
          name: 'Geçici Sonraki Ürün',
          price: 1000,
          barcode: '8699999999999',
          deviceId: setup.deviceId,
        );
        expect(await dbService.getLocalProductsCount(), 2);

        // Yanlış parola reddedilmeli ve canlı DB zarar görmemeli
        await expectLater(
          () => backupService.restoreEncryptedBackup(
            backupId: backup.backupId,
            password: 'WrongPassword!',
          ),
          throwsA(isA<BackupException>()),
        );
        expect(dbService.isClosed, isFalse);
        expect(await dbService.getLocalProductsCount(), 2);

        // Doğru parola ile geri yükleme canlı DB'yi durdurup yeniden açmalı
        final restore = await backupService.restoreEncryptedBackup(
          backupId: backup.backupId,
          password: 'StrongPassword#2026',
        );
        expect(restore.backupId, backup.backupId);
        expect(File(restore.safetyBackupPath).existsSync(), isTrue);
        expect(dbService.isClosed, isFalse);
        expect(dbService.database.schemaVersion, 4);
        expect(await dbService.getLocalProductsCount(), 1);
        expect(await dbService.getLocalSalesCount(), 1);
        // Faz 7A / ADR-BAK-03: Yedekten SONRA oluşan ve Hub'a ulaşmamış PRODUCT_UPSERT
        // Outbox kaydı restore'da silinmez (satış + ürün = 2 bekleyen işlem). Ürün kaydı
        // senkronizasyon sonrası Hub snapshot'ıyla yerel kataloğa geri gelir.
        expect((await dbService.getOutboxSummary(deviceId: setup.deviceId)).totalUnsynced, 2);

        await dbService.close();
      },
    );
  });

  group('Faz 7.3: B-3 Secure Storage, S-4 Pairing & Maskeli Tanı', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('mms_faz7_sec_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    if (Platform.isWindows) {
      test(
        'B-3 WindowsDpapiTokenStore CurrentUser DPAPI ile düz metin olmadan token saklar ve çözer',
        () async {
          final store = WindowsDpapiTokenStore.inDirectory(tempDir);
          const rawToken = 'mms_win_live_secret_998877';

          await store.saveDeviceToken('POS-DPAPI-01', rawToken);
          final diskContent = store.storageFile.readAsStringSync();
          expect(diskContent, isNot(contains(rawToken)));

          final freshReader = WindowsDpapiTokenStore.inDirectory(tempDir);
          expect(await freshReader.readDeviceToken('POS-DPAPI-01'), rawToken);

          await freshReader.deleteDeviceToken('POS-DPAPI-01');
          expect(await freshReader.readDeviceToken('POS-DPAPI-01'), isNull);
        },
      );
    }

    test(
      'S-4 ECDSA P-256 anahtar çifti, QR ayrıştırma ve DevicePairingClient el sıkışması tokenı güvenli depoya yazar',
      () async {
        final keyPair = ClientEcdsaP256KeyPair.generate();
        expect(keyPair.publicKeySpkiBytes.length, 91);
        expect(keyPair.publicKeyFingerprintBytes.length, 32);
        final restoredKeyPair =
            ClientEcdsaP256KeyPair.fromPrivateKeyHex(keyPair.toPrivateKeyHex());
        expect(
          restoredKeyPair.publicKeySpkiBytes,
          equals(keyPair.publicKeySpkiBytes),
        );
        final directSig = keyPair.signCanonicalPayload(
          keyPair.buildPollPayload(
            sessionId: 'sess_direct',
            challengeId: 'ch_1',
            challengeNonce: List<int>.filled(32, 3),
          ),
        );
        expect(directSig[0], 0x30);

        final jsonQr = PairingQrPayload.parse(
          jsonEncode(<String, dynamic>{
            'session_id': 'sess_01',
            'pairing_secret': 'sec_xyz',
            'hub_url': 'https://192.168.1.50:8945',
            'ca_sha256': 'AA:BB:${'CC' * 30}',
          }),
        );
        expect(jsonQr.sessionId, 'sess_01');
        expect(jsonQr.pairingSecret, 'sec_xyz');
        expect(jsonQr.hubUrl, 'https://192.168.1.50:8945');

        final uriQr = PairingQrPayload.parse(
          'marketmms://pair?session_id=sess_02&pairing_secret=sec_abc&hub_url=https://10.0.0.5:8945',
        );
        expect(uriQr.sessionId, 'sess_02');
        expect(uriQr.pairingSecret, 'sec_abc');

        final tokenStore = InMemorySecureTokenStore();
        final logger = RedactingLogger();
        var pollChallengeAttempts = 0;
        var ackChallengeAttempts = 0;

        final pairingClient = DevicePairingClient(
          tokenStore: tokenStore,
          logger: logger,
          delay: (_) async {},
          clientFactory: ({PinnedTlsConfig? tlsOverride}) {
            return MockClient((request) async {
              if (request.url.path == '/api/v1/pairing/ca-cert') {
                return http.Response('NO_CERT', 404);
              }
              if (request.url.path == '/api/v1/pairing/request') {
                final body = jsonDecode(request.body) as Map<String, dynamic>;
                expect(body['key_algorithm'], 'ECDSA_P256');
                final spki = base64Decode(body['client_public_key'] as String);
                expect(spki.length, 91);
                return http.Response(
                  jsonEncode({'status': 'PENDING_APPROVAL'}),
                  202,
                );
              }
              if (request.url.path == '/api/v1/pairing/poll-challenge') {
                pollChallengeAttempts++;
                if (pollChallengeAttempts == 1) {
                  return http.Response(
                    jsonEncode({'error': 'SESSION_NOT_APPROVED'}),
                    403,
                  );
                }
                return http.Response(
                  jsonEncode({
                    'poll_challenge_id': 'ch_poll_1',
                    'poll_challenge_nonce': base64Encode(List<int>.filled(32, 7)),
                  }),
                  200,
                );
              }
              if (request.url.path == '/api/v1/pairing/poll') {
                final body = jsonDecode(request.body) as Map<String, dynamic>;
                final derSig = base64Decode(body['signature'] as String);
                expect(derSig[0], 0x30);
                expect(derSig.length, inInclusiveRange(68, 72));
                return http.Response(
                  jsonEncode({
                    'status': 'PAIRED',
                    'device_id': 'POS-AND-99',
                    'token': 'paired_raw_token_secret_123',
                  }),
                  200,
                );
              }
              if (request.url.path == '/api/v1/pairing/ack-challenge') {
                ackChallengeAttempts++;
                if (ackChallengeAttempts == 1) {
                  return http.Response(
                    jsonEncode({
                      'error': 'CHALLENGE_COOLDOWN_ACTIVE',
                      'retry_after_seconds': 5,
                    }),
                    429,
                  );
                }
                return http.Response(
                  jsonEncode({
                    'ack_challenge_id': 'ch_ack_1',
                    'ack_challenge_nonce': base64Encode(List<int>.filled(32, 9)),
                  }),
                  200,
                );
              }
              if (request.url.path == '/api/v1/pairing/ack') {
                final body = jsonDecode(request.body) as Map<String, dynamic>;
                final derSig = base64Decode(body['signature'] as String);
                expect(derSig[0], 0x30);
                return http.Response(
                  jsonEncode({'status': 'CONFIRMED'}),
                  200,
                );
              }
              return http.Response('Not Found', 404);
            });
          },
        );

        final result = await pairingClient.pairDevice(
          hubBaseUrl: 'https://192.168.1.50:8945',
          sessionId: 'sess_01',
          pairingSecret: 'sec_xyz',
          deviceId: 'POS-AND-99',
          deviceName: 'Kasa Mobil',
          platformName: 'android',
        );

        expect(result.confirmed, isTrue);
        expect(
          await tokenStore.readDeviceToken('POS-AND-99'),
          'paired_raw_token_secret_123',
        );

        // MmsApiClient dinamik token okumalı ve kimlik doğrulamalı uçta Authorization başlığı göndermeli
        String? capturedAuthHeader;
        final apiClient = MmsApiClient(
          client: MockClient((req) async {
            capturedAuthHeader = req.headers['Authorization'];
            return http.Response(
              jsonEncode({'products': <Object>[]}),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }),
          baseUrl: 'https://192.168.1.50:8945',
          deviceId: 'POS-AND-99',
          readDeviceToken: () => 'paired_raw_token_secret_123',
        );
        final productsResp = await apiClient.get('/api/v1/products');
        expect(productsResp['products'], isEmpty);
        expect(capturedAuthHeader, 'Bearer paired_raw_token_secret_123');

        // Maskeli tanı dışa aktarımında hiçbir secret görünmemeli
        logger.error(
          'sync',
          'Hata: Bearer paired_raw_token_secret_123 pairing_secret="sec_xyz"',
        );
        final exportedFile = await DiagnosticsReportExporter.exportToDirectory(
          outputDir: tempDir,
          logger: logger,
          setupConfig: AppSetupConfig.initial(deviceId: 'POS-AND-99'),
          systemStatus: SystemStatus.initial(
            backendUrl: 'https://192.168.1.50:8945',
            deviceId: 'POS-AND-99',
            localDbPath: '/tmp/client_local.db',
          ).copyWith(errorMessage: 'token=paired_raw_token_secret_123'),
          hubState: const HubConnectionState.initial(),
          syncState: SyncCoordinatorState.initial(),
          tokenBackendLabel: 'Test Vault',
          hasStoredToken: true,
        );
        final exportedRaw = exportedFile.readAsStringSync();
        expect(exportedRaw, isNot(contains('paired_raw_token_secret_123')));
        expect(exportedRaw, isNot(contains('sec_xyz')));
        expect(exportedRaw, contains('[REDACTED]'));
        expect(sha256.convert(utf8.encode(exportedRaw)).bytes, hasLength(32));
      },
    );
  });

  group('Faz 7.4: Sürüm Manifest Kontrolü', () {
    test('AppUpdateChecker SemVer ve çevrimdışı durumları doğru sınıflar', () async {
      final availableChecker = AppUpdateChecker(
        currentVersion: '1.0.0',
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'latest_version': '1.2.0',
              'min_supported_version': '1.0.0',
              'mandatory': false,
            }),
            200,
          );
        }),
      );
      final avail = await availableChecker.checkManifestUrl(
        'https://192.168.1.50:8945/manifest.json',
      );
      expect(avail.availability, AppUpdateAvailability.updateAvailable);

      final requiredChecker = AppUpdateChecker(
        currentVersion: '1.0.0',
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'latest_version': '2.0.0',
              'min_supported_version': '1.5.0',
              'mandatory': true,
            }),
            200,
          );
        }),
      );
      final reqRes = await requiredChecker.checkManifestUrl(
        'https://192.168.1.50:8945/manifest.json',
      );
      expect(reqRes.availability, AppUpdateAvailability.updateRequired);

      final offlineChecker = AppUpdateChecker(
        currentVersion: '1.0.0',
        client: MockClient((_) async => throw const SocketException('offline')),
      );
      final offRes = await offlineChecker.checkManifestUrl(
        'https://192.168.1.50:8945/manifest.json',
      );
      expect(offRes.availability, AppUpdateAvailability.unavailable);
    });
  });

  group('Faz 7 UI Widget & Sıfır Taşma Testleri (Desktop 1280x800 & Mobile 390x844)', () {
    late Directory tempDir;
    late LocalDatabaseService localDb;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('mms_faz7_ui_');
      localDb = LocalDatabaseService.forTesting(
        NativeDatabase.memory(),
        path: p.join(tempDir.path, 'client_local.db'),
      );
      await localDb.repository.initializeDevice('POS-UI-01');
    });

    tearDown(() async {
      await localDb.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    Widget buildDiagnosticsHarness({required MmsUiProfile profile}) {
      final setupStore = InMemorySetupConfigStore(
        AppSetupConfig.initial(deviceId: 'POS-UI-01'),
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
        deviceId: 'POS-UI-01',
      );

      return ProviderScope(
        overrides: [
          localDatabaseServiceProvider.overrideWithValue(localDb),
          apiClientProvider.overrideWithValue(apiClient),
          setupConfigStoreProvider.overrideWithValue(setupStore),
          initialSetupConfigProvider.overrideWithValue(
            AppSetupConfig.initial(deviceId: 'POS-UI-01'),
          ),
          backupRootDirectoryProvider.overrideWithValue(
            Directory(p.join(tempDir.path, 'backups')),
          ),
          backupKdfIterationsProvider.overrideWithValue(1000),
          secureTokenStoreProvider.overrideWithValue(InMemorySecureTokenStore()),
          mmsUiProfileProvider.overrideWithValue(profile),
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
          home: const Scaffold(body: DiagnosticsView()),
        ),
      );
    }

    testWidgets(
      'Masaüstü (1280x800): Kurulum Sihirbazı ve Maskeli Tanı Raporu taşmasız çalışır',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          buildDiagnosticsHarness(profile: const MmsUiProfile.desktop()),
        );
        await tester.pumpAndSettle();

        final wizardBtn = find.byKey(const Key('open_setup_wizard_button'));
        await tester.scrollUntilVisible(
          wizardBtn,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        await tester.tap(wizardBtn);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('setup_tenant_id_field')),
          'tenant-istanbul',
        );
        await tester.enterText(
          find.byKey(const Key('setup_store_id_field')),
          'store-besiktas',
        );
        await tester.enterText(
          find.byKey(const Key('setup_store_name_field')),
          'Beşiktaş Merkez',
        );
        await tester.tap(find.byKey(const Key('setup_wizard_save_button')));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.textContaining('store-besiktas'), findsOneWidget);

        final exportBtn = find.byKey(const Key('diagnostics_export_logs_button'));
        await tester.scrollUntilVisible(
          exportBtn,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.runAsync(() async {
          await tester.tap(exportBtn);
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('diagnostics_export_banner')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Android Mobil (390x844): Tüm Faz 7 üretim ve güvenlik kartları taşmasız görünür',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          buildDiagnosticsHarness(profile: const MmsUiProfile.mobile()),
        );
        await tester.pumpAndSettle();

        final exportBtn = find.byKey(const Key('diagnostics_export_logs_button'));
        await tester.scrollUntilVisible(
          exportBtn,
          350,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('diagnostics_store_setup_card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('diagnostics_backup_card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('diagnostics_security_card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('diagnostics_update_card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('diagnostics_export_card')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
