import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/features/security/data/hub_pairing_admin_client.dart';

/// Faz 7B — Windows Owner eşleştirme onay/red arayüzünün veri katmanı (TDD).
void main() {
  const secret = 'owner_admin_secret_x';
  final requests = <http.Request>[];

  HubPairingAdminClient clientWith(http.Response Function(http.Request) handler) {
    requests.clear();
    return HubPairingAdminClient(
      hubBaseUrl: 'https://127.0.0.1:8945',
      httpClient: MockClient((req) async {
        requests.add(req);
        return handler(req);
      }),
    );
  }

  test('1. Bekleyen talepler admin secret başlığıyla listelenir', () async {
    final c = clientWith((_) => http.Response(
          jsonEncode({
            'requests': [
              {
                'session_id': 's1',
                'device_id': 'AND-01',
                'name': 'Kasa Telefon',
                'platform': 'ANDROID',
                'fingerprint': 'AB:CD',
                'created_at': '2026-11-21T10:00:00.000',
              },
            ],
          }),
          200,
        ));

    final list = await c.listPendingRequests(adminSecret: secret);

    expect(list.single.deviceId, 'AND-01');
    expect(list.single.publicKeyFingerprint, 'AB:CD');
    expect(requests.single.url.path, '/api/v1/pairing/requests');
    expect(requests.single.headers['x-mms-admin-secret'], secret);
    expect(requests.single.headers['authorization'], isNull, reason: 'Cihaz token\'ı admin uçlarına gönderilmemeli');
  });

  test('2. Onay ve red doğru uca session_id ile gönderilir', () async {
    final c = clientWith((_) => http.Response(jsonEncode({'status': 'OK'}), 200));
    await c.approve(sessionId: 's1', adminSecret: secret);
    await c.reject(sessionId: 's2', adminSecret: secret);
    expect(requests[0].url.path, '/api/v1/pairing/approve');
    expect(jsonDecode(requests[0].body), {'session_id': 's1'});
    expect(requests[1].url.path, '/api/v1/pairing/reject');
    expect(jsonDecode(requests[1].body), {'session_id': 's2'});
  });

  test('3. Yanlış admin secret, loopback dışı erişim ve kapalı admin anlaşılır hatalara çevrilir', () async {
    final cases = {
      403: 'ERR_INVALID_ADMIN_SECRET',
      401: 'ERR_ADMIN_SECRET_REQUIRED',
      503: 'ERR_ADMIN_NOT_CONFIGURED',
    };
    for (final entry in cases.entries) {
      final c = clientWith((_) => http.Response(jsonEncode({'code': entry.value, 'message': 'x'}), entry.key));
      await expectLater(
        c.listPendingRequests(adminSecret: secret),
        throwsA(isA<HubPairingAdminException>().having((e) => e.code, 'code', entry.value)),
      );
    }
  });

  test('4. Yeni eşleştirme oturumu QR yükünü döner; pairing secret loglanabilir metinde değil yalnızca yükte bulunur', () async {
    final c = clientWith((_) => http.Response(
          jsonEncode({
            'v': 1,
            'hub_url': 'https://192.168.1.10:8945',
            'ca_fingerprint': 'FF' * 32,
            'session_id': 'sess_9',
            'pairing_secret': 'top_secret_pairing',
            'expires_at': 1890000000,
          }),
          201,
        ));
    final session = await c.createSession(adminSecret: secret);
    expect(session.sessionId, 'sess_9');
    expect(jsonDecode(session.qrPayload)['pairing_secret'], 'top_secret_pairing');
    expect(session.toString(), isNot(contains('top_secret_pairing')));
  });

  test('5. Admin secret boşsa ağ isteği yapılmaz', () async {
    final c = clientWith((_) => http.Response('{}', 200));
    await expectLater(
      c.listPendingRequests(adminSecret: '  '),
      throwsA(isA<HubPairingAdminException>().having((e) => e.code, 'code', 'ERR_ADMIN_SECRET_REQUIRED')),
    );
    expect(requests, isEmpty);
  });
}
