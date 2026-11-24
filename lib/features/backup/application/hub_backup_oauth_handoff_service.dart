import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mms_client_storage/mms_client_storage.dart';

/// Hub tarafında OAuth bağlama sonucu (ham token asla istemciye dönülmez).
class HubBackupOAuthStatusInfo {
  final bool connected;
  final String? accountEmail;
  final String? scope;
  final String? folderId;
  final bool needsReauth;
  final String? lastErrorCode;
  final DateTime? connectedAtUtc;
  final DateTime? expiresAtUtc;

  const HubBackupOAuthStatusInfo({
    required this.connected,
    this.accountEmail,
    this.scope,
    this.folderId,
    this.needsReauth = false,
    this.lastErrorCode,
    this.connectedAtUtc,
    this.expiresAtUtc,
  });

  factory HubBackupOAuthStatusInfo.fromJson(Map<String, dynamic> json) =>
      HubBackupOAuthStatusInfo(
        connected: (json['connected'] as bool?) ?? false,
        accountEmail: json['account_email'] as String?,
        scope: json['scope'] as String?,
        folderId: json['folder_id'] as String?,
        needsReauth: (json['needs_reauth'] as bool?) ?? false,
        lastErrorCode: json['last_error_code'] as String?,
        connectedAtUtc: json['connected_at_utc'] is String
            ? DateTime.tryParse(json['connected_at_utc'] as String)?.toUtc()
            : null,
        expiresAtUtc: json['expires_at_utc'] is String
            ? DateTime.tryParse(json['expires_at_utc'] as String)?.toUtc()
            : null,
      );
}

/// Windows Masaüstü UI -> Master Hub PKCE el sıkışma devri (`OV-01`, `OV-02`).
///
/// Tarayıcıda alınan `authorization_code` + `code_verifier` doğrulanmış Hub
/// loopback HTTPS ucu `POST /api/v1/backup/oauth/connect` üzerine aktarılır.
/// UI bu akışta Google `/token` endpoint'ini çağırmaz ve Hub token'ı saklamaz.
class HubBackupOAuthHandoffService {
  final String clientId;
  final String? clientSecret;
  final String Function() readHubUrl;
  final Map<String, String> Function() buildAuthHeaders;
  final http.Client httpClient;
  final Future<void> Function(Uri url) openBrowser;
  final bool? isWindowsOverride;

  HubBackupOAuthHandoffService({
    required this.clientId,
    this.clientSecret,
    required this.readHubUrl,
    required this.buildAuthHeaders,
    required this.httpClient,
    Future<void> Function(Uri url)? openBrowser,
    this.isWindowsOverride,
  }) : openBrowser = openBrowser ?? _openWithSystemBrowser;

  bool get isSupportedPlatform => isWindowsOverride ?? Platform.isWindows;
  bool get isConfigured => isSupportedPlatform && clientId.trim().isNotEmpty;

  /// Windows üzerinde tarayıcı PKCE akışını başlatır ve alınan kodu + doğrulayıcıyı
  /// Hub'a devreder (yalnızca Windows masaüstünde desteklenir).
  Future<HubBackupOAuthStatusInfo> connectViaWindowsBrowser({
    Duration timeout = const Duration(minutes: 5),
    String? accountEmail,
  }) async {
    if (!isSupportedPlatform) {
      throw const DriveBackupException(
        'ERR_HUB_OAUTH_WINDOWS_ONLY',
        'Merkezi Hub Google Drive bağlantısı yalnızca Windows masaüstü istemcisi üzerinden başlatılabilir.',
      );
    }
    if (clientId.trim().isEmpty) {
      throw const DriveBackupException(
        'ERR_DRIVE_NOT_CONFIGURED',
        'Google OAuth istemci kimliği tanımlı değil.',
      );
    }

    final callbackServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final flow = GoogleOAuthDesktopFlow(
        clientId: clientId,
        clientSecret: clientSecret,
        httpClient: httpClient,
      );
      final redirectUri = 'http://127.0.0.1:${callbackServer.port}/';
      final session = flow.begin(redirectUri: redirectUri);
      await openBrowser(session.authorizationUri);

      final request = await callbackServer.first.timeout(timeout);
      final callback = request.requestedUri;
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(
          '<html><body><h3>MARKET MMS: Google Drive yetkilendirmesi Master Hub\'a aktarıldı. Bu pencereyi kapatabilirsiniz.</h3></body></html>',
        );
      await request.response.close();

      final params = callback.queryParameters;
      if (params['state'] != session.state) {
        throw const DriveBackupException(
          'ERR_OAUTH_STATE_MISMATCH',
          'Google yetkilendirme yanıtı doğrulanamadı (state uyuşmuyor).',
        );
      }
      if (params['error'] != null) {
        throw DriveBackupException(
          'ERR_OAUTH_DENIED',
          'Google yetkilendirmesi reddedildi: ${params['error']}',
        );
      }
      final code = params['code'];
      if (code == null || code.isEmpty) {
        throw const DriveBackupException(
          'ERR_OAUTH_DENIED',
          'Google yetkilendirme kodu alınamadı.',
        );
      }

      return await handoffAuthorizationCodeToHub(
        authCode: code,
        codeVerifier: session.codeVerifier,
        redirectUri: redirectUri,
        accountEmail: accountEmail,
      );
    } on TimeoutException {
      throw const DriveBackupException(
        'ERR_OAUTH_TIMEOUT',
        'Google yetkilendirmesi zaman aşımına uğradı.',
      );
    } finally {
      await callbackServer.close(force: true);
    }
  }

  /// Alınan PKCE `auth_code` + `code_verifier` bilgisini doğrudan Hub'a devreder.
  Future<HubBackupOAuthStatusInfo> handoffAuthorizationCodeToHub({
    required String authCode,
    required String codeVerifier,
    required String redirectUri,
    String? accountEmail,
  }) async {
    final hubUrl = readHubUrl().trim();
    if (hubUrl.isEmpty) {
      throw const DriveBackupException(
        'ERR_HUB_UNAVAILABLE',
        'Master Hub adresi tanımlı değil.',
      );
    }

    final uri = Uri.parse('$hubUrl/api/v1/backup/oauth/connect');
    final resp = await httpClient.post(
      uri,
      headers: {
        'content-type': 'application/json',
        ...buildAuthHeaders(),
      },
      body: jsonEncode({
        'auth_code': authCode,
        'code_verifier': codeVerifier,
        'redirect_uri': redirectUri,
        'client_id': clientId,
        if (clientSecret != null && clientSecret!.isNotEmpty)
          'client_secret': clientSecret,
        if (accountEmail != null && accountEmail.isNotEmpty)
          'account_email': accountEmail,
      }),
    );

    final body = _decodeMap(resp.body);
    if (resp.statusCode != 200) {
      throw DriveBackupException(
        (body['code'] as String?) ?? 'ERR_HUB_OAUTH_CONNECT',
        (body['message'] as String?) ??
            'Hub Google Drive bağlantısı tamamlanamadı (HTTP ${resp.statusCode}).',
      );
    }
    return HubBackupOAuthStatusInfo.fromJson(body);
  }

  static Future<void> _openWithSystemBrowser(Uri url) async {
    if (!Platform.isWindows) {
      throw const DriveBackupException(
        'ERR_HUB_OAUTH_WINDOWS_ONLY',
        'Tarayıcı yönlendirmesi yalnızca Windows üzerinde desteklenir.',
      );
    }
    await Process.start('rundll32', ['url.dll,FileProtocolHandler', url.toString()]);
  }

  static Map<String, dynamic> _decodeMap(String body) {
    if (body.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (e) {
      stderr.writeln(
        '[HubBackupOAuthHandoff] OAuth yanıtı ayrıştırılamadı: ${e.runtimeType}',
      );
    }
    return const {};
  }
}
