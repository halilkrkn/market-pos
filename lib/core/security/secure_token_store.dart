import 'dart:async';

/// Güvenli depo okunamadığında/bozulduğunda fırlatılır (fail-closed).
/// Mesaj asla sır değeri içermez.
class SecureStorageException implements Exception {
  final String message;
  final String? code;
  const SecureStorageException(this.message, {this.code});

  @override
  String toString() => 'SecureStorageException: $message';
}

/// B-3 Donanım / İşletim Sistemi Destekli Güvenli Token Depolama Sözleşmesi.
///
/// Raw device token ve özel anahtarlar asla plain-text yapılandırma dosyasına
/// veya log çıktısına yazılmaz.
abstract class SecureTokenStore {
  String get backendLabel;

  Future<void> saveDeviceToken(String deviceId, String token);
  Future<String?> readDeviceToken(String deviceId);
  Future<void> deleteDeviceToken(String deviceId);

  Future<void> saveSecret(String key, String value);
  Future<String?> readSecret(String key);
  Future<void> deleteSecret(String key);
}

/// Testler ve desteklenmeyen masaüstü platformlar için RAM içi geçici depo.
class InMemorySecureTokenStore implements SecureTokenStore {
  final Map<String, String> _values = <String, String>{};

  @override
  String get backendLabel => 'Bellek İçi Test Deposu';

  String _tokenKey(String deviceId) => 'token::$deviceId';

  @override
  Future<void> saveDeviceToken(String deviceId, String token) async {
    _values[_tokenKey(deviceId)] = token;
  }

  @override
  Future<String?> readDeviceToken(String deviceId) async =>
      _values[_tokenKey(deviceId)];

  @override
  Future<void> deleteDeviceToken(String deviceId) async {
    _values.remove(_tokenKey(deviceId));
  }

  @override
  Future<void> saveSecret(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<String?> readSecret(String key) async => _values[key];

  @override
  Future<void> deleteSecret(String key) async {
    _values.remove(key);
  }
}
