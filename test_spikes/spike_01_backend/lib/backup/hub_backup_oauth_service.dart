import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mms_client_storage/mms_client_storage.dart';

import 'hub_backup_oauth_store.dart';

/// İstemciye / UI'a döndürülen sterilize OAuth durumu; ham `access_token` veya
/// `refresh_token` ASLA içermez (`OV-01`).
class HubBackupOAuthStatus {
  final bool connected;
  final String? accountEmail;
  final String? scope;
  final String? folderId;
  final bool needsReauth;
  final String? lastErrorCode;
  final DateTime? connectedAtUtc;
  final DateTime? expiresAtUtc;

  const HubBackupOAuthStatus({
    required this.connected,
    this.accountEmail,
    this.scope,
    this.folderId,
    this.needsReauth = false,
    this.lastErrorCode,
    this.connectedAtUtc,
    this.expiresAtUtc,
  });

  static const disconnected = HubBackupOAuthStatus(connected: false);

  factory HubBackupOAuthStatus.fromCredentials(HubBackupOAuthCredentials creds) =>
      HubBackupOAuthStatus(
        connected: !creds.needsReauth,
        accountEmail: creds.accountEmail,
        scope: creds.scope,
        folderId: creds.folderId,
        needsReauth: creds.needsReauth,
        lastErrorCode: creds.lastErrorCode,
        connectedAtUtc: creds.connectedAtUtc,
        expiresAtUtc: creds.expiresAtUtc,
      );

  Map<String, dynamic> toJson() => {
        'connected': connected,
        'account_email': accountEmail,
        'scope': scope,
        'folder_id': folderId,
        'needs_reauth': needsReauth,
        'last_error_code': lastErrorCode,
        'connected_at_utc': connectedAtUtc?.toUtc().toIso8601String(),
        'expires_at_utc': expiresAtUtc?.toUtc().toIso8601String(),
      };
}

/// Faz B-2 (`ADR-023`, `OV-01`, `OV-02`): Hub Google Drive OAuth yaşam döngüsü.
///
/// Windows UI tarayıcı PKCE kodunu Hub'a devreder (`connectWithPkce`); token takası,
/// yenileme ve DPAPI saklama yalnızca Hub servisi tarafından yürütülür.
class HubBackupOAuthService {
  static final Uri defaultTokenEndpoint =
      Uri.parse('https://oauth2.googleapis.com/token');
  static final Uri defaultRevokeEndpoint =
      Uri.parse('https://oauth2.googleapis.com/revoke');

  final HubBackupOAuthStore store;
  final http.Client httpClient;
  final Uri tokenEndpoint;
  final Uri revokeEndpoint;
  final DateTime Function() clock;
  Future<String>? _refreshInFlight;

  HubBackupOAuthService({
    required this.store,
    required this.httpClient,
    Uri? tokenEndpoint,
    Uri? revokeEndpoint,
    DateTime Function()? clock,
  })  : tokenEndpoint = tokenEndpoint ?? defaultTokenEndpoint,
        revokeEndpoint = revokeEndpoint ?? defaultRevokeEndpoint,
        clock = clock ?? (() => DateTime.now().toUtc());

  Future<HubBackupOAuthStatus> getStatus() async {
    final creds = await store.load();
    if (creds == null) return HubBackupOAuthStatus.disconnected;
    return HubBackupOAuthStatus.fromCredentials(creds);
  }

  /// Windows PKCE el sıkışmasından gelen `authCode` + `codeVerifier` ile token
  /// takası yapar ve DPAPI+entropy kasasına kaydeder.
  Future<HubBackupOAuthStatus> connectWithPkce({
    required String authCode,
    required String codeVerifier,
    required String redirectUri,
    required String clientId,
    String? clientSecret,
    String? accountEmail,
    String? folderId,
  }) async {
    if (authCode.trim().isEmpty || codeVerifier.trim().isEmpty) {
      throw const HubBackupOAuthException(
        'ERR_INVALID_PKCE_HANDOFF',
        'auth_code ve code_verifier zorunludur.',
      );
    }
    if (redirectUri.trim().isEmpty || clientId.trim().isEmpty) {
      throw const HubBackupOAuthException(
        'ERR_INVALID_PKCE_HANDOFF',
        'redirect_uri ve client_id zorunludur.',
      );
    }

    final resp = await httpClient.post(
      tokenEndpoint,
      body: {
        'grant_type': 'authorization_code',
        'code': authCode.trim(),
        'code_verifier': codeVerifier.trim(),
        'redirect_uri': redirectUri.trim(),
        'client_id': clientId.trim(),
        if (clientSecret != null && clientSecret.isNotEmpty)
          'client_secret': clientSecret,
      },
    );

    final body = _decodeJsonMap(resp.body);
    final accessToken = body['access_token'];
    final refreshToken = body['refresh_token'];
    if (resp.statusCode != 200 || accessToken is! String || accessToken.isEmpty) {
      throw HubBackupOAuthException(
        'ERR_OAUTH_EXCHANGE_FAILED',
        'Google OAuth kod takası başarısız (HTTP ${resp.statusCode}: ${body['error'] ?? 'unknown'}).',
      );
    }
    if (refreshToken is! String || refreshToken.isEmpty) {
      throw const HubBackupOAuthException(
        'ERR_OAUTH_NO_REFRESH_TOKEN',
        'Google kalıcı refresh_token döndürmedi; lütfen yeniden onay verin.',
      );
    }

    final grantedScope = (body['scope'] as String?) ?? googleDriveFileScope;
    if (!_hasDriveFileScope(grantedScope)) {
      throw HubBackupOAuthException(
        'ERR_OAUTH_SCOPE_INSUFFICIENT',
        'Beklenen drive.file izni verilmedi: $grantedScope',
      );
    }

    final expiresInSec = (body['expires_in'] as num?)?.toInt() ?? 3600;
    final nowUtc = clock().toUtc();
    final credentials = HubBackupOAuthCredentials(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAtUtc: nowUtc.add(Duration(seconds: expiresInSec)),
      accountEmail: (accountEmail != null && accountEmail.trim().isNotEmpty)
          ? accountEmail.trim()
          : (body['email'] as String?),
      scope: grantedScope,
      folderId: folderId,
      connectedAtUtc: nowUtc,
      needsReauth: false,
      lastErrorCode: null,
    );
    await store.save(credentials);
    return HubBackupOAuthStatus.fromCredentials(credentials);
  }

  /// Geçerli kısa ömürlü access_token döner; süresi 120 sn içine girdiyse yeniler.
  Future<String> getValidAccessToken({
    required String clientId,
    String? clientSecret,
    bool forceRefresh = false,
  }) async {
    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final existing = await store.load();
    if (existing == null) {
      throw const HubBackupOAuthException(
        'FAILED_AUTH',
        'Hub Google Drive hesabı henüz bağlanmamış.',
      );
    }
    final nowUtc = clock().toUtc();
    if (!forceRefresh &&
        !existing.needsReauth &&
        existing.accessToken.isNotEmpty &&
        existing.expiresAtUtc.isAfter(nowUtc.add(const Duration(seconds: 120)))) {
      return existing.accessToken;
    }

    final future = _performTokenRefresh(
      existing: existing,
      clientId: clientId,
      clientSecret: clientSecret,
    );
    _refreshInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
      }
    }
  }

  Future<String> _performTokenRefresh({
    required HubBackupOAuthCredentials existing,
    required String clientId,
    String? clientSecret,
  }) async {
    final nowUtc = clock().toUtc();
    final http.Response resp;
    try {
      resp = await httpClient
          .post(
            tokenEndpoint,
            body: {
              'grant_type': 'refresh_token',
              'refresh_token': existing.refreshToken,
              'client_id': clientId,
              if (clientSecret != null && clientSecret.isNotEmpty)
                'client_secret': clientSecret,
            },
          )
          .timeout(const Duration(seconds: 30));
    } on SocketException catch (e) {
      throw HubBackupOAuthException(
        'ERR_OAUTH_REFRESH_UNAVAILABLE',
        'Google OAuth token yenilemesi ağ hatası aldı: ${e.message}',
      );
    } on TimeoutException {
      throw const HubBackupOAuthException(
        'ERR_OAUTH_REFRESH_UNAVAILABLE',
        'Google OAuth token yenilemesi zaman aşımına uğradı.',
      );
    } on http.ClientException catch (e) {
      throw HubBackupOAuthException(
        'ERR_OAUTH_REFRESH_UNAVAILABLE',
        'Google OAuth istemci hatası: ${e.message}',
      );
    }

    final body = _decodeJsonMap(resp.body);
    if (resp.statusCode == 400 || resp.statusCode == 401 || resp.statusCode == 403) {
      await store.save(
        existing.copyWith(
          accessToken: '',
          needsReauth: true,
          lastErrorCode: 'FAILED_AUTH',
        ),
      );
      throw HubBackupOAuthException(
        'FAILED_AUTH',
        'Google Drive OAuth yenilemesi reddedildi (${body['error'] ?? resp.statusCode}); yeniden bağlanılmalıdır.',
      );
    }

    final accessToken = body['access_token'];
    if (resp.statusCode != 200 || accessToken is! String || accessToken.isEmpty) {
      throw HubBackupOAuthException(
        'ERR_OAUTH_REFRESH_UNAVAILABLE',
        'Google OAuth token yenilemesi geçici olarak başarısız (HTTP ${resp.statusCode}).',
      );
    }

    final expiresInSec = (body['expires_in'] as num?)?.toInt() ?? 3600;
    final rotatedRefresh = body['refresh_token'];
    final updated = existing.copyWith(
      accessToken: accessToken,
      refreshToken: (rotatedRefresh is String && rotatedRefresh.isNotEmpty)
          ? rotatedRefresh
          : existing.refreshToken,
      expiresAtUtc: nowUtc.add(Duration(seconds: expiresInSec)),
      needsReauth: false,
      clearLastError: true,
    );
    await store.save(updated);
    return updated.accessToken;
  }

  /// Bağlı folderId bilgisini DPAPI kasasında günceller.
  ///
  /// S5: Kaydedilen kimlik `MARKET MMS Yedekleri/Hub` alt klasörüdür; düzen işareti
  /// birlikte yazılır.
  Future<void> updateFolderId(String folderId) async {
    final existing = await store.load();
    if (existing == null) return;
    await store.save(existing.copyWith(
      folderId: folderId,
      folderLayout: HubBackupOAuthCredentials.hubSubfolderLayout,
    ));
  }

  /// S5: Yalnızca Hub alt klasör düzeninde kaydedilmiş klasör kimliğini döner.
  /// Eski (kök `MARKET MMS Yedekleri`) önbellek veya bağlantı yoksa `null` döner;
  /// yükleyici bu durumda Hub alt klasörünü bulur/oluşturur.
  Future<String?> getCachedHubFolderId() async {
    final creds = await store.load();
    if (creds == null) return null;
    if (creds.folderLayout != HubBackupOAuthCredentials.hubSubfolderLayout) return null;
    final id = creds.folderId;
    return (id != null && id.isNotEmpty) ? id : null;
  }

  /// Google OAuth token'ını mümkünse iptal eder ve DPAPI kasa dosyasını siler.
  Future<void> disconnect() async {
    final existing = await store.load();
    if (existing != null) {
      final token = existing.refreshToken.isNotEmpty
          ? existing.refreshToken
          : existing.accessToken;
      if (token.isNotEmpty) {
        try {
          await httpClient.post(
            revokeEndpoint,
            headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {'token': token},
          );
        } catch (_) {
          // Ağ yoksa yerel kasa yine de silinir.
        }
      }
    }
    await store.clear();
  }

  static bool _hasDriveFileScope(String scopeHeader) {
    final scopes = scopeHeader.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toSet();
    return scopes.contains(googleDriveFileScope) ||
        scopes.contains('https://www.googleapis.com/auth/drive');
  }

  static Map<String, dynamic> _decodeJsonMap(String body) {
    if (body.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (e) {
      stderr.writeln(
        '[HubBackupOAuthService] OAuth JSON yanıtı ayrıştırılamadı: ${e.runtimeType}',
      );
    }
    return const {};
  }
}
