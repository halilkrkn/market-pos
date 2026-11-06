import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// Cihaz belirteçlerinin (Device Token) 256-bit üretimi, salt/pepper ile hash'lenmesi
/// ve sabit zamanlı (constant-time) doğrulanmasını yöneten servis.
class TokenManager {
  static final Random _secureRandom = Random.secure();

  /// 256-bit (32 byte) kriptografik entropiye sahip, tahmin edilemez Bearer Token üretir.
  /// Format: 'mms_dt_' + Base64Url (padding'siz, 43 karakter)
  static String generateToken() {
    final bytes = List<int>.generate(32, (_) => _secureRandom.nextInt(256));
    final tokenBase = base64UrlEncode(bytes).replaceAll('=', '');
    return 'mms_dt_$tokenBase';
  }

  /// Her cihaz için benzersiz 128-bit (16 byte / 32 hex karakter) kriptografik salt üretir.
  static String generateSalt() {
    final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Token'ı cihaz salt'ı ve sunucu pepper'ı ile SHA-256 algoritmasını kullanarak özetler.
  /// Formül: SHA-256(rawToken + ':' + salt + ':' + pepper)
  static String hashToken({
    required String rawToken,
    required String salt,
    required String pepper,
  }) {
    final payload = utf8.encode('$rawToken:$salt:$pepper');
    return sha256.convert(payload).toString();
  }

  /// Sabit zamanlı (constant-time) karşılaştırma ile zamanlama analizi (timing attack) saldırılarını önler.
  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  /// Gelen Bearer token'ı doğrular.
  static bool verifyToken({
    required String rawToken,
    required String salt,
    required String expectedHash,
    required String pepper,
  }) {
    final candidateHash = hashToken(
      rawToken: rawToken,
      salt: salt,
      pepper: pepper,
    );

    return constantTimeEquals(
      utf8.encode(candidateHash),
      utf8.encode(expectedHash),
    );
  }
}

