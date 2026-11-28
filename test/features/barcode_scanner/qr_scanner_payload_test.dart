import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/features/barcode_scanner/domain/camera_barcode_debounce.dart';
import 'package:market_pos/features/barcode_scanner/presentation/mobile_scanner_screen.dart';
import 'package:market_pos/features/security/domain/pairing_qr_payload.dart';

void main() {
  group('QR Kod Tarayıcı Ham Yük & Barkod Sanitizasyonu Ayrımı', () {
    final pairingJson = jsonEncode({
      'session_id': 'pair-sess-9876543210-abcdef',
      'pairing_secret': 'secret-pairing-token-0123456789abcdef0123456789',
      'hub_url': 'https://192.168.1.42:8945',
      'ca_sha256':
          'a3f1c2d4e5b60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
      'device_name': 'Kasa-Android-01',
      'expires_at': '2026-11-28T18:00:00Z',
    });

    test('rawQrMode (~260 karakterlik PairingQrPayload JSON) kesilmeden kabul edilir ve parse edilir', () {
      expect(pairingJson.length, greaterThan(220));
      expect(pairingJson.length, lessThan(4096));

      final extracted = MobileScannerScreen.extractRawQrPayload('  $pairingJson\n');
      expect(extracted, pairingJson);

      final parsed = PairingQrPayload.parse(extracted!);
      expect(parsed.sessionId, 'pair-sess-9876543210-abcdef');
      expect(
        parsed.pairingSecret,
        'secret-pairing-token-0123456789abcdef0123456789',
      );
      expect(parsed.hubUrl, 'https://192.168.1.42:8945');
      expect(
        parsed.normalizedCaSha256,
        'a3f1c2d4e5b60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90'
            .toUpperCase(),
      );
    });

    test('rawQrMode boş veya 4096 karakteri aşan yükleri reddeder', () {
      expect(MobileScannerScreen.extractRawQrPayload(null), isNull);
      expect(MobileScannerScreen.extractRawQrPayload('   \r\n '), isNull);
      expect(MobileScannerScreen.extractRawQrPayload('x' * 4097), isNull);
      expect(MobileScannerScreen.extractRawQrPayload('x' * 4096), hasLength(4096));
    });

    test('normal ürün barkodu modu 64 karakter sınırını ve sanitizasyonu korumaya devam eder', () {
      final debounce = CameraBarcodeDebounce();

      // Uzun eşleştirme JSON verisi ürün barkodu modunda reddedilir.
      expect(debounce.acceptRaw(pairingJson), isNull);
      // 65 karakterlik ham barkod reddedilir.
      expect(debounce.acceptRaw('8' * 65), isNull);
      // 64 karakter sınırındaki geçerli ürün barkodu ve EAN-13 kabul edilir.
      expect(debounce.acceptRaw('8690504012345\r\n'), '8690504012345');
      expect(debounce.acceptRaw('A' * 64), 'A' * 64);
    });
  });
}
