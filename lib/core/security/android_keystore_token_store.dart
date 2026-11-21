import 'package:flutter/services.dart';

import 'secure_token_store.dart';

/// B-3 Android Keystore Donanım/OS Destekli Güvenli Token Deposu.
///
/// Kotlin tarafında `MainActivity` üzerinden `AndroidKeyStore` AES-256-GCM
/// anahtarı ve özel (`MODE_PRIVATE`) `SharedPreferences` köprüsünü kullanır.
class AndroidKeystoreTokenStore implements SecureTokenStore {
  static const MethodChannel defaultChannel =
      MethodChannel('com.marketmms.market_pos/secure_storage');

  final MethodChannel _channel;

  const AndroidKeystoreTokenStore({MethodChannel? channel})
      : _channel = channel ?? defaultChannel;

  @override
  String get backendLabel => 'Android Keystore (AES-GCM)';

  String _tokenKey(String deviceId) => 'device_token::$deviceId';

  @override
  Future<void> saveDeviceToken(String deviceId, String token) =>
      saveSecret(_tokenKey(deviceId), token);

  @override
  Future<String?> readDeviceToken(String deviceId) =>
      readSecret(_tokenKey(deviceId));

  @override
  Future<void> deleteDeviceToken(String deviceId) =>
      deleteSecret(_tokenKey(deviceId));

  Future<T?> _invoke<T>(String method, Map<String, String> arguments) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      throw const SecureStorageException(
        'Android Keystore güvenli depo eklentisi bu ortamda kullanılamıyor.',
        code: 'MISSING_PLUGIN',
      );
    } on PlatformException catch (e) {
      final rawCode = e.code.trim();
      final safeCode = rawCode.isEmpty ? 'ANDROID_KEYSTORE_ERROR' : rawCode;
      throw SecureStorageException(
        'Android Keystore güvenli depo hatası ($safeCode).',
        code: safeCode,
      );
    }
  }

  @override
  Future<void> saveSecret(String key, String value) async {
    await _invoke<void>('saveSecret', <String, String>{
      'key': key,
      'value': value,
    });
  }

  @override
  Future<String?> readSecret(String key) {
    return _invoke<String>('readSecret', <String, String>{
      'key': key,
    });
  }

  @override
  Future<void> deleteSecret(String key) async {
    await _invoke<void>('deleteSecret', <String, String>{
      'key': key,
    });
  }
}
