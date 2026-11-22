import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mms_client_storage/mms_client_storage.dart';

import '../../../core/security/secure_token_store.dart';
import 'android_google_sign_in_token_provider.dart';

/// Faz 7D & ADR-022 — Owner'ın Google hesabını (yalnızca `drive.file` izniyle) bağlaması.
///
/// - Windows: loopback (127.0.0.1) yönlendirme + PKCE; refresh token yalnızca
///   DPAPI güvenli deposuna yazılır.
/// - Android (ADR-022 Seçenek A): `google_sign_in` v7+ (`Credential Manager` +
///   `AuthorizationClient`); yalnızca kısa ömürlü access_token RAM'de tutulur.
class GoogleDriveConnectService {
  /// Güvenli depodaki refresh token anahtarı (Windows).
  static const String refreshTokenSecretKey = 'gdrive_refresh_token_v1';

  final String clientId;
  final String? clientSecret;
  final SecureTokenStore secureStore;
  final http.Client httpClient;
  final Future<void> Function(Uri url) openBrowser;
  final AndroidGoogleSignInTokenProvider? androidTokenProvider;
  final bool? isAndroidOverride;

  GoogleDriveConnectService({
    required this.clientId,
    required this.secureStore,
    required this.httpClient,
    this.clientSecret,
    Future<void> Function(Uri url)? openBrowser,
    this.androidTokenProvider,
    this.isAndroidOverride,
  }) : openBrowser = openBrowser ?? _openWithSystemBrowser;

  bool get isAndroidMode => isAndroidOverride ?? Platform.isAndroid;

  bool get isConfigured => isAndroidMode
      ? (androidTokenProvider?.isConfigured ?? false)
      : clientId.trim().isNotEmpty;

  Future<bool> isConnected() async {
    if (isAndroidMode) {
      return androidTokenProvider?.isConnected() ?? Future<bool>.value(false);
    }
    final token = await secureStore.readSecret(refreshTokenSecretKey);
    return token != null && token.isNotEmpty;
  }

  Future<void> connect({Duration timeout = const Duration(minutes: 5)}) async {
    if (isAndroidMode) {
      final provider = androidTokenProvider;
      if (provider == null || !provider.isConfigured) {
        throw const DriveBackupException(
          'ERR_DRIVE_NOT_CONFIGURED',
          'Android Google Drive Web OAuth kimliği (MMS_GDRIVE_WEB_CLIENT_ID) tanımlı değil (Owner işlemi gerekir).',
        );
      }
      await provider.connect();
      return;
    }
    if (!isConfigured) {
      throw const DriveBackupException(
        'ERR_DRIVE_NOT_CONFIGURED',
        'Google Cloud OAuth istemci kimliği tanımlı değil (Owner işlemi gerekir).',
      );
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final flow = GoogleOAuthDesktopFlow(clientId: clientId, clientSecret: clientSecret, httpClient: httpClient);
      final session = flow.begin(redirectUri: 'http://127.0.0.1:${server.port}/');
      await openBrowser(session.authorizationUri);

      final request = await server.first.timeout(timeout);
      final callback = request.requestedUri;
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write('<html><body><h3>MARKET MMS: Google Drive yetkilendirmesi alındı. Bu pencereyi kapatabilirsiniz.</h3></body></html>');
      await request.response.close();

      final tokens = await flow.complete(session, callback);
      final refresh = tokens.refreshToken;
      if (refresh == null || refresh.isEmpty) {
        throw const DriveBackupException(
          'ERR_OAUTH_NO_REFRESH_TOKEN',
          'Google kalıcı erişim (refresh token) vermedi; hesabı yeniden bağlayın.',
        );
      }
      await secureStore.saveSecret(refreshTokenSecretKey, refresh);
    } on TimeoutException {
      throw const DriveBackupException('ERR_OAUTH_TIMEOUT', 'Google yetkilendirmesi zaman aşımına uğradı.');
    } finally {
      await server.close(force: true);
    }
  }

  Future<void> saveRefreshToken(String refreshToken) async {
    final trimmed = refreshToken.trim();
    if (trimmed.isEmpty) {
      throw const DriveBackupException(
        'ERR_OAUTH_NO_REFRESH_TOKEN',
        'Google Drive refresh token boş olamaz.',
      );
    }
    await secureStore.saveSecret(refreshTokenSecretKey, trimmed);
  }

  Future<void> disconnect({DriveAccessTokenProvider? tokenProvider}) async {
    if (isAndroidMode) {
      await androidTokenProvider?.disconnect();
      return;
    }
    if (tokenProvider is GoogleOAuthRefreshTokenProvider) {
      await tokenProvider.revokeToken();
    }
    await secureStore.deleteSecret(refreshTokenSecretKey);
  }

  static Future<void> _openWithSystemBrowser(Uri url) async {
    if (!Platform.isWindows) {
      throw const DriveBackupException(
        'ERR_DRIVE_PLATFORM_UNSUPPORTED',
        'Google Drive bağlantısı yalnızca Windows ve Android uygulamalarından yapılabilir.',
      );
    }
    // url.dll FileProtocolHandler: kabuk (cmd) yorumlaması olmadan varsayılan tarayıcıyı açar.
    await Process.start('rundll32', ['url.dll,FileProtocolHandler', url.toString()]);
  }
}
