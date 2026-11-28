import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/core/logging/redacting_logger.dart';
import 'package:market_pos/core/security/device_role_resolver.dart';
import 'package:market_pos/core/security/security_providers.dart';
import 'package:market_pos/core/theme/app_theme.dart';
import 'package:market_pos/features/security/data/hub_pairing_admin_client.dart';
import 'package:market_pos/features/security/data/windows_zero_touch_bootstrapper.dart';
import 'package:market_pos/features/security/presentation/widgets/pairing_approval_panel.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Faz 7B — Windows Owner eşleştirme onay/red arayüzü (widget testi, sahte Hub).
void main() {
  testWidgets('Owner bekleyen talebi görür, onaylar; liste yenilenir ve sonuç gösterilir', (tester) async {
    var approved = <String>[];
    var pending = <Map<String, dynamic>>[
      {'session_id': 's1', 'device_id': 'AND-01', 'name': 'Kasa Telefon', 'platform': 'ANDROID', 'fingerprint': 'AB:CD'},
    ];
    final client = HubPairingAdminClient(
      hubBaseUrl: 'https://127.0.0.1:8945',
      httpClient: MockClient((req) async {
        if (req.headers['x-mms-admin-secret'] != 'dogru_anahtar') {
          return http.Response(jsonEncode({'code': 'ERR_INVALID_ADMIN_SECRET'}), 403);
        }
        if (req.url.path.endsWith('/requests')) return http.Response(jsonEncode({'requests': pending}), 200);
        if (req.url.path.endsWith('/approve')) {
          final id = (jsonDecode(req.body) as Map)['session_id'] as String;
          approved.add(id);
          pending = [];
          return http.Response(jsonEncode({'status': 'APPROVED'}), 200);
        }
        return http.Response('{}', 404);
      }),
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [hubPairingAdminClientProvider.overrideWithValue(client)],
      child: MaterialApp(theme: AppTheme.lightTheme, home: const Scaffold(body: SingleChildScrollView(child: PairingApprovalPanel()))),
    ));

    // Ana ekranda admin secret alanı görünmez; Gelişmiş / Manuel Kurtarma altındadır
    expect(find.byKey(const Key('pairing_admin_secret_field')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('pairing_manual_recovery_tile')));
    await tester.tap(find.byKey(const Key('pairing_manual_recovery_tile')));
    await tester.pumpAndSettle();

    // Yanlış anahtar → anlaşılır hata, liste boş
    await tester.enterText(find.byKey(const Key('pairing_admin_secret_field')), 'yanlis');
    await tester.ensureVisible(find.byKey(const Key('pairing_refresh_button')));
    await tester.tap(find.byKey(const Key('pairing_refresh_button')));
    await tester.pumpAndSettle();
    expect(find.text('Yönetici anahtarı hatalı.'), findsOneWidget);
    expect(find.byKey(const Key('pairing_approve_s1')), findsNothing);

    await tester.enterText(find.byKey(const Key('pairing_admin_secret_field')), 'dogru_anahtar');
    await tester.ensureVisible(find.byKey(const Key('pairing_refresh_button')));
    await tester.tap(find.byKey(const Key('pairing_refresh_button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kasa Telefon'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('pairing_approve_s1')));
    await tester.tap(find.byKey(const Key('pairing_approve_s1')));
    await tester.pumpAndSettle();
    expect(approved, ['s1']);
    expect(find.textContaining('onaylandı'), findsOneWidget);
    expect(find.byKey(const Key('pairing_approve_s1')), findsNothing);
  });

  testWidgets('A7: Yeni eşleştirme oturumu açıldığında QrImageView ve kopyalama butonu beyaz kartta gösterilir',
      (tester) async {
    final client = HubPairingAdminClient(
      hubBaseUrl: 'https://127.0.0.1:8945',
      httpClient: MockClient((req) async {
        if (req.headers['x-mms-admin-secret'] != 'dogru_anahtar') {
          return http.Response(jsonEncode({'code': 'ERR_INVALID_ADMIN_SECRET'}), 403);
        }
        if (req.url.path.endsWith('/pairing/session')) {
          return http.Response(
            jsonEncode({
              'session_id': 'sess_qr_1',
              'pairing_secret': 'secret_qr_abc',
              'hub_url': 'https://192.168.1.50:8945',
              'ca_fingerprint': 'AA:BB:CC:DD',
              'expires_at': 1893456000,
            }),
            201,
          );
        }
        return http.Response('{}', 404);
      }),
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [hubPairingAdminClientProvider.overrideWithValue(client)],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(
          body: SingleChildScrollView(child: PairingApprovalPanel()),
        ),
      ),
    ));

    await tester.ensureVisible(find.byKey(const Key('pairing_manual_recovery_tile')));
    await tester.tap(find.byKey(const Key('pairing_manual_recovery_tile')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pairing_admin_secret_field')), 'dogru_anahtar');
    await tester.ensureVisible(find.byKey(const Key('pairing_create_session_button')));
    await tester.tap(find.byKey(const Key('pairing_create_session_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pairing_qr_image_container')), findsOneWidget);
    expect(find.byKey(const Key('pairing_qr_image')), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.byKey(const Key('pairing_copy_payload_button')), findsOneWidget);
    expect(find.textContaining('ekran görüntüsünü paylaşmayın'), findsOneWidget);
  });

  testWidgets('ownerBootstrapCompleted == true olduğunda ilk kurulum ve admin secret gizlenir, QR Kod Oluştur görünür',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        deviceRoleProvider.overrideWith((ref) {
          final notifier = DeviceRoleNotifier(
            deviceId: 'WIN-OWNER-01',
            tenantId: 'default-tenant',
            storeId: 'default-store',
            logger: RedactingLogger(),
            readHubUrl: () => 'https://127.0.0.1:8945',
            readDeviceToken: () => 'tok_owner',
            httpClient: MockClient((_) async => http.Response(
              jsonEncode({
                'device_id': 'WIN-OWNER-01',
                'role': 'OWNER',
                'owner_bootstrap_completed': true,
              }),
              200,
            )),
          );
          notifier.state = const DeviceRoleState(
            verifiedRole: DeviceRoleState.roleOwner,
            status: DeviceRoleVerificationStatus.verified,
            boundDeviceId: 'WIN-OWNER-01',
            boundHubUrl: 'https://127.0.0.1:8945',
            boundToken: 'tok_owner',
            ownerBootstrapCompleted: true,
          );
          return notifier;
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: SingleChildScrollView(child: PairingApprovalPanel()),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pairing_admin_secret_field')), findsNothing);
    expect(find.byKey(const Key('zero_touch_connect_button')), findsNothing);
    expect(find.byKey(const Key('owner_bootstrap_button')), findsNothing);
    expect(find.byKey(const Key('pairing_create_session_button')), findsOneWidget);
    expect(find.text('QR Kod Oluştur'), findsOneWidget);
    expect(find.byKey(const Key('pairing_refresh_button')), findsOneWidget);
  });

  testWidgets('Zero-Touch UI: Ana ekranda admin secret yok, OWNER Bearer ile sıfır anahtar QR Kod Oluştur çalışır',
      (tester) async {
    String? seenAuthHeader;
    final client = HubPairingAdminClient(
      hubBaseUrl: 'https://127.0.0.1:8945',
      readBearerToken: () => 'tok_owner_zt_1',
      httpClient: MockClient((req) async {
        seenAuthHeader = req.headers['authorization'];
        if (req.url.path.endsWith('/pairing/session')) {
          return http.Response(
            jsonEncode({
              'session_id': 'sess_zt_1',
              'pairing_secret': 'sec_zt_1',
              'hub_url': 'https://192.168.1.50:8945',
              'ca_fingerprint': 'AA:BB',
              'expires_at': 1893456000,
            }),
            201,
          );
        }
        return http.Response('{}', 404);
      }),
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [hubPairingAdminClientProvider.overrideWithValue(client)],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: SingleChildScrollView(child: PairingApprovalPanel()),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pairing_admin_secret_field')), findsNothing);
    expect(find.byKey(const Key('zero_touch_connect_button')), findsOneWidget);
    expect(find.text('Ana Bilgisayarı Otomatik Bağla'), findsOneWidget);
    expect(find.text('Gelişmiş / Manuel Kurtarma'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pairing_create_session_button')));
    await tester.pumpAndSettle();
    expect(seenAuthHeader, equals('Bearer tok_owner_zt_1'));
    expect(find.byKey(const Key('pairing_qr_image')), findsOneWidget);
  });

  testWidgets('PairingApprovalPanel "Ana Bilgisayarı Otomatik Bağla" butonu sıfır anahtar akışını çalıştırır', (tester) async {
    var runnerCalled = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          windowsZeroTouchRunnerProvider.overrideWithValue(() async {
            runnerCalled++;
            return const WindowsZeroTouchResult(
              status: WindowsZeroTouchStatus.bootstrapped,
              caPinnedNow: true,
              deviceId: 'POS-WIN-UI',
              message: 'Ana bilgisayar bağlantısı otomatik olarak tamamlandı.',
            );
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: SingleChildScrollView(child: PairingApprovalPanel()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pairing_admin_secret_field')), findsNothing);
    final btn = find.byKey(const Key('zero_touch_connect_button'));
    expect(btn, findsOneWidget);
    await tester.tap(btn);
    await tester.pumpAndSettle();

    expect(runnerCalled, equals(1));
    expect(
      find.text('Ana bilgisayar bağlantısı otomatik olarak tamamlandı.'),
      findsOneWidget,
    );
  });
}
