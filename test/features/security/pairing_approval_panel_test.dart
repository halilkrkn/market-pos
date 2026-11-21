import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/core/theme/app_theme.dart';
import 'package:market_pos/features/security/data/hub_pairing_admin_client.dart';
import 'package:market_pos/features/security/presentation/widgets/pairing_approval_panel.dart';

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

    // Yanlış anahtar → anlaşılır hata, liste boş
    await tester.enterText(find.byKey(const Key('pairing_admin_secret_field')), 'yanlis');
    await tester.tap(find.byKey(const Key('pairing_refresh_button')));
    await tester.pumpAndSettle();
    expect(find.text('Yönetici anahtarı hatalı.'), findsOneWidget);
    expect(find.byKey(const Key('pairing_approve_s1')), findsNothing);

    await tester.enterText(find.byKey(const Key('pairing_admin_secret_field')), 'dogru_anahtar');
    await tester.tap(find.byKey(const Key('pairing_refresh_button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kasa Telefon'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pairing_approve_s1')));
    await tester.pumpAndSettle();
    expect(approved, ['s1']);
    expect(find.textContaining('onaylandı'), findsOneWidget);
    expect(find.byKey(const Key('pairing_approve_s1')), findsNothing);
  });
}
