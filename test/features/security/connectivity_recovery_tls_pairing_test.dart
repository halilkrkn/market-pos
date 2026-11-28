import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/core/constants/app_constants.dart';
import 'package:market_pos/core/logging/redacting_logger.dart';
import 'package:market_pos/core/security/android_keystore_token_store.dart';
import 'package:market_pos/core/security/secure_token_store.dart';
import 'package:market_pos/core/security/windows_dpapi_token_store.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/core/theme/app_theme.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:market_pos/features/security/data/device_pairing_client.dart';
import 'package:market_pos/features/security/presentation/widgets/device_security_card.dart';
import 'package:market_pos/features/security/presentation/widgets/pairing_approval_panel.dart';
import 'package:market_pos/features/setup/setup_providers.dart';
import 'package:market_pos/features/sync/application/hub_connection_notifier.dart';
import 'package:market_pos/features/sync/domain/hub_connection_state.dart';
import 'package:market_pos/features/sync/infrastructure/udp_hub_discovery_client.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  group('AŞAMA 4 & 5 — HTTPS Normalizasyonu, Stale TTL ve Güvenli İlk Eşleştirme', () {
    test('HubUrlValidator.normalizeUserInput şemasız IP girdilerini hem Windows hem Android için HTTPS olarak normalize eder', () {
      expect(
        HubUrlValidator.normalizeUserInput('192.168.1.158', allowLoopback: false),
        'https://192.168.1.158:8945',
      );
      expect(
        HubUrlValidator.normalizeUserInput('192.168.1.158:8950', allowLoopback: true),
        'https://192.168.1.158:8950',
      );
      expect(
        HubUrlValidator.normalizeUserInput('127.0.0.1', allowLoopback: true),
        'https://127.0.0.1:8945',
      );
      expect(
        AppConstants.windowsLocalhostFallbackUrl,
        startsWith('https://'),
      );
    });

    test('DiscoveredHubCandidate varsayılan ve discovery yanıtı şemasını HTTPS üretir (HTTP düşüşü yok)', () {
      final withoutScheme = DiscoveredHubCandidate.tryFromUdpPayload(
        const <String, dynamic>{
          'service': 'market_mms_hub',
          'protocol_version': '1.0',
          'hub_id': 'MMS-HUB-MASTER',
          'http_port': 8945,
          'server_ips': <String>['192.168.1.158'],
        },
        responderIp: '192.168.1.158',
      );
      expect(withoutScheme, isNotNull);
      expect(
        withoutScheme!.candidateBaseUrls(allowLoopback: false),
        const <String>['https://192.168.1.158:8945'],
      );

      final withHttpsScheme = DiscoveredHubCandidate.tryFromUdpPayload(
        const <String, dynamic>{
          'service': 'market_mms_hub',
          'protocol_version': '1.0',
          'hub_id': 'MMS-HUB-MASTER',
          'http_port': 8945,
          'scheme': 'https',
          'server_ips': <String>['192.168.1.158'],
        },
        responderIp: '192.168.1.158',
        scheme: 'http',
      );
      expect(
        withHttpsScheme!.candidateBaseUrls(allowLoopback: false),
        const <String>['https://192.168.1.158:8945'],
      );
    });

    test('hubDiscoveryClientProvider eşleştirme öncesi dahi HTTPS şeması kullanır', () {
      final container = ProviderContainer(
        overrides: <Override>[pinnedTlsConfigProvider.overrideWithValue(null)],
      );
      addTearDown(container.dispose);

      final client = container.read(hubDiscoveryClientProvider) as UdpHubDiscoveryClient;
      expect(client.effectiveScheme, equals('https'));
    });

    test('HubConnectionBootstrapper.loadInitialState eski (stale) discovered kaydını TTL sonrası temizler', () async {
      final db = ClientDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = ClientStorageRepository(db);

      final staleTime = DateTime.utc(2026, 11, 20, 8, 0);
      await repo.saveStoredHubConnection(
        hubUrl: 'https://192.168.84.2:8945',
        hubId: 'OLD-STALE-HUB',
        source: HubUrlSource.discovered,
        allowLoopback: false,
        now: staleTime,
      );

      final loadedAfterTtl = await HubConnectionBootstrapper.loadInitialState(
        repository: repo,
        allowLoopback: false,
        maxDiscoveredAge: const Duration(hours: 24),
        now: () => DateTime.utc(2026, 11, 28, 3, 0),
      );

      expect(loadedAfterTtl.phase, HubConnectionPhase.unconfigured);
      expect(loadedAfterTtl.activeHubUrl, isNull);
      expect(await repo.getStoredHubConnection(allowLoopback: false), isNull);
    });

    test('hubPairingAdminClientProvider eski http activeHubUrl kalsa dahi loopback https://127.0.0.1 kullanır', () {
      final db = LocalDatabaseService.forTesting(
        NativeDatabase.memory(),
        path: 'mem_admin_https.db',
      );
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: <Override>[
          localDatabaseServiceProvider.overrideWithValue(db),
          initialHubConnectionStateProvider.overrideWithValue(
            const HubConnectionState(
              phase: HubConnectionPhase.offline,
              activeHubUrl: 'http://192.168.84.2:8945',
              isInitialized: true,
            ),
          ),
          pinnedTlsConfigProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);

      final adminClient = container.read(hubPairingAdminClientProvider);
      expect(adminClient.hubBaseUrl, equals('https://127.0.0.1:8945'));
    });

    testWidgets('DeviceSecurityCard Kök CA İndir ve Sabitle butonu görünür ve geçersiz pin ile fail-closed uyarır', (tester) async {
      final db = LocalDatabaseService.forTesting(
        NativeDatabase.memory(),
        path: 'mem_sec_card.db',
      );
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            localDatabaseServiceProvider.overrideWithValue(db),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(
              body: SingleChildScrollView(child: DeviceSecurityCard()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final btn = find.byKey(const Key('bootstrap_ca_pin_button'));
      expect(btn, findsOneWidget);
      await tester.enterText(find.byKey(const Key('tls_pin_sha256_field')), 'KISA');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('security_status_banner')), findsOneWidget);
      expect(find.textContaining('64 karakterli SHA-256'), findsOneWidget);
    });

    test('DevicePairingClient.fetchAndVerifyRootCaCert HTTP veya geçersiz pin ile fail-closed reddeder', () async {
      final pairingClient = DevicePairingClient(
        tokenStore: InMemorySecureTokenStore(),
        logger: RedactingLogger(),
      );

      await expectLater(
        () => pairingClient.fetchAndVerifyRootCaCert(
          hubBaseUrl: 'http://127.0.0.1:8945',
          expectedCaSha256Hex:
              '5C78095BCA8B2D8C419158C4E7433F99FAB9EBD32A7B5AE3815A2413E057FA2A',
        ),
        throwsA(
          isA<DevicePairingException>()
              .having((e) => e.code, 'code', 'TLS_SCHEME_REQUIRED'),
        ),
      );

      await expectLater(
        () => pairingClient.fetchAndVerifyRootCaCert(
          hubBaseUrl: 'https://127.0.0.1:8945',
          expectedCaSha256Hex: 'KISA_GECERSIZ',
        ),
        throwsA(
          isA<DevicePairingException>()
              .having((e) => e.code, 'code', 'CA_PIN_REQUIRED'),
        ),
      );
    });

    test('Windows DPAPI ve Android Keystore token store yaz/oku/sil + fail-closed eksik token', () async {
      if (Platform.isWindows) {
        final tempDir = await Directory.systemTemp.createTemp('mms_dpapi_test_');
        addTearDown(() async {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
        final store = WindowsDpapiTokenStore.inDirectory(tempDir);
        expect(await store.readDeviceToken('POS-WIN-TEST'), isNull);
        await store.saveDeviceToken('POS-WIN-TEST', 'tok_secret_win_123');
        expect(await store.readDeviceToken('POS-WIN-TEST'), 'tok_secret_win_123');
        final rawFile = await File(
          p.join(tempDir.path, WindowsDpapiTokenStore.defaultFileName),
        ).readAsString();
        expect(rawFile.contains('tok_secret_win_123'), isFalse);
        await store.deleteDeviceToken('POS-WIN-TEST');
        expect(await store.readDeviceToken('POS-WIN-TEST'), isNull);
      }

      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('com.marketmms.market_pos/secure_storage');
      final backing = <String, String>{};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final key = args['key'] as String;
        switch (call.method) {
          case 'saveSecret':
            backing[key] = args['value'] as String;
            return null;
          case 'readSecret':
            return backing[key];
          case 'deleteSecret':
            backing.remove(key);
            return null;
          default:
            return null;
        }
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      const androidStore = AndroidKeystoreTokenStore();
      expect(await androidStore.readDeviceToken('POS-AND-TEST'), isNull);
      await androidStore.saveDeviceToken('POS-AND-TEST', 'tok_secret_and_456');
      expect(
        await androidStore.readDeviceToken('POS-AND-TEST'),
        'tok_secret_and_456',
      );
      await androidStore.deleteDeviceToken('POS-AND-TEST');
      expect(await androidStore.readDeviceToken('POS-AND-TEST'), isNull);
    });
  });
}
