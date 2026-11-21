import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/features/security/domain/pairing_qr_payload.dart';

void main() {
  group('ADR-018: PairingQrPayload CA parmak izi çözümleme', () {
    const validSha = 'aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99:aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99';
    const expectedNormalized = 'AABBCCDDEEFF00112233445566778899AABBCCDDEEFF00112233445566778899';

    test('1. Hub tarafından üretilen ca_fingerprint ve caFingerprint alanlarını okur ve normalize eder', () {
      final fromSnake = PairingQrPayload.parse(jsonEncode({
        'session_id': 'sess-1',
        'pairing_secret': 'sec-1',
        'hub_url': 'https://192.168.1.50:8945',
        'ca_fingerprint': validSha,
      }));
      expect(fromSnake.caSha256, expectedNormalized);
      expect(fromSnake.normalizedCaSha256, expectedNormalized);

      final fromCamel = PairingQrPayload.parse(jsonEncode({
        'sessionId': 'sess-2',
        'pairingSecret': 'sec-2',
        'caFingerprint': ' $expectedNormalized ',
      }));
      expect(fromCamel.caSha256, expectedNormalized);
    });

    test('2. UNKNOWN veya boş ca_fingerprint / ca_sha256 değerlerini null olarak temizler', () {
      for (final rawVal in ['UNKNOWN', 'unknown', '  UnKnOwN ', '']) {
        final payload = PairingQrPayload.parse(jsonEncode({
          'session_id': 'sess-unk',
          'pairing_secret': 'sec-unk',
          'ca_fingerprint': rawVal,
        }));
        expect(payload.caSha256, isNull, reason: '"$rawVal" pin olarak kabul edilmemeli');
        expect(payload.normalizedCaSha256, isNull);
      }

      final uriPayload = PairingQrPayload.parse(
        'marketmms://pair?session_id=s3&pairing_secret=p3&ca_sha256=UNKNOWN',
      );
      expect(uriPayload.caSha256, isNull);
    });
  });
}
