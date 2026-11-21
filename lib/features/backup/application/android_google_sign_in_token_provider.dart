import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../../../core/logging/redacting_logger.dart';
import '../../../core/security/secure_token_store.dart';

/// Android Credential Manager / Google Sign-In üzerinden dönen hesap özeti.
class AndroidGoogleAccount {
  final String id;
  final String email;
  final String? displayName;
  final Object? rawAccount;

  const AndroidGoogleAccount({
    required this.id,
    required this.email,
    this.displayName,
    this.rawAccount,
  });
}

/// `google_sign_in` v7+ eklentisini test edilebilirlik amacıyla izole eden adaptör.
abstract class GoogleSignInClientAdapter {
  Future<void> initialize({required String serverClientId});
  Future<AndroidGoogleAccount?> attemptLightweightAuthentication();
  Future<AndroidGoogleAccount> authenticate();
  Future<String?> authorizationForScopes(
    AndroidGoogleAccount account,
    List<String> scopes,
  );
  Future<String> authorizeScopes(
    AndroidGoogleAccount account,
    List<String> scopes,
  );
  Future<void> clearAuthorizationToken(String accessToken);
  Future<void> signOut();
  Future<void> disconnect();
}

/// Gerçek Android cihazda `GoogleSignIn.instance` (v7+) API'sini çağıran adaptör.
class PluginGoogleSignInClientAdapter implements GoogleSignInClientAdapter {
  GoogleSignInAuthorizationClient _resolveAuthClient(
    AndroidGoogleAccount account,
  ) {
    final raw = account.rawAccount;
    if (raw is GoogleSignInAccount) {
      return raw.authorizationClient;
    }
    return GoogleSignIn.instance.authorizationClient;
  }

  AndroidGoogleAccount _toDomainAccount(GoogleSignInAccount account) {
    return AndroidGoogleAccount(
      id: account.id,
      email: account.email,
      displayName: account.displayName,
      rawAccount: account,
    );
  }

  @visibleForTesting
  DriveBackupException mapError(Object error) {
    if (error is DriveBackupException) return error;
    if (error is MissingPluginException) {
      return const DriveBackupException(
        'ERR_DRIVE_GMS_UNAVAILABLE',
        'Google Play Hizmetleri veya Google Sign-In eklentisi bu cihazda kullanılabilir değil.',
      );
    }
    if (error is GoogleSignInException) {
      switch (error.code) {
        case GoogleSignInExceptionCode.clientConfigurationError:
          return const DriveBackupException(
            'ERR_DRIVE_NOT_CONFIGURED',
            'Google Drive OAuth istemci yapılandırması geçersiz (Web client ID veya APK SHA-1 parmak izi uyuşmuyor).',
          );
        case GoogleSignInExceptionCode.providerConfigurationError:
          return const DriveBackupException(
            'ERR_DRIVE_GMS_UNAVAILABLE',
            'Bu cihazda Google Play Hizmetleri (GMS) eksik veya güncel değil.',
          );
        case GoogleSignInExceptionCode.uiUnavailable:
          return const DriveBackupException(
            'ERR_DRIVE_REAUTH_REQUIRED',
            'Google Drive oturumu ön plan kullanıcı onayı gerektiriyor; lütfen hesabı yeniden bağlayın.',
          );
        case GoogleSignInExceptionCode.canceled:
          return const DriveBackupException(
            'ERR_OAUTH_DENIED',
            'Google Drive yetkilendirmesi kullanıcı tarafından iptal edildi.',
          );
        case GoogleSignInExceptionCode.userMismatch:
          return const DriveBackupException(
            'ERR_DRIVE_REAUTH_REQUIRED',
            'Google hesabı oturumu değişti; lütfen hesabı yeniden bağlayın.',
          );
        case GoogleSignInExceptionCode.interrupted:
        case GoogleSignInExceptionCode.unknownError:
          return const DriveBackupException(
            'ERR_DRIVE_UNAVAILABLE',
            'Google yetkilendirme işlemi tamamlanamadı; bağlantıyı kontrol edip tekrar deneyin.',
          );
      }
    }
    if (error is PlatformException) {
      final code = error.code.toLowerCase();
      final msg = (error.message ?? '').toLowerCase();
      if (code.contains('gms') ||
          code.contains('play_services') ||
          code.contains('service_missing') ||
          code.contains('service_disabled') ||
          code.contains('service_invalid') ||
          code.contains('api_unavailable') ||
          msg.contains('play services') ||
          msg.contains('google play')) {
        return const DriveBackupException(
          'ERR_DRIVE_GMS_UNAVAILABLE',
          'Bu cihazda Google Play Hizmetleri (GMS) kullanılamıyor.',
        );
      }
      if (code.contains('cancel')) {
        return const DriveBackupException(
          'ERR_OAUTH_DENIED',
          'Google Drive yetkilendirmesi kullanıcı tarafından iptal edildi.',
        );
      }
      if (code.contains('developer_error') ||
          code.contains('client_config') ||
          msg.contains('developer_error') ||
          msg.contains('10:')) {
        return const DriveBackupException(
          'ERR_DRIVE_NOT_CONFIGURED',
          'Android OAuth istemci veya SHA-1 yapılandırması doğrulanamadı.',
        );
      }
      return const DriveBackupException(
        'ERR_DRIVE_UNAVAILABLE',
        'Google yetkilendirme servisiyle iletişim kurulamadı.',
      );
    }
    return const DriveBackupException(
      'ERR_DRIVE_UNAVAILABLE',
      'Google yetkilendirme servisi geçici olarak erişilemiyor.',
    );
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      throw mapError(e);
    }
  }

  @override
  Future<void> initialize({required String serverClientId}) {
    return _guard(
      () => GoogleSignIn.instance.initialize(serverClientId: serverClientId),
    );
  }

  @override
  Future<AndroidGoogleAccount?> attemptLightweightAuthentication() {
    return _guard(() async {
      final future = GoogleSignIn.instance.attemptLightweightAuthentication();
      if (future == null) return null;
      final account = await future;
      return account == null ? null : _toDomainAccount(account);
    });
  }

  @override
  Future<AndroidGoogleAccount> authenticate() {
    return _guard(() async {
      final account = await GoogleSignIn.instance.authenticate();
      return _toDomainAccount(account);
    });
  }

  @override
  Future<String?> authorizationForScopes(
    AndroidGoogleAccount account,
    List<String> scopes,
  ) {
    return _guard(() async {
      final auth =
          await _resolveAuthClient(account).authorizationForScopes(scopes);
      return auth?.accessToken;
    });
  }

  @override
  Future<String> authorizeScopes(
    AndroidGoogleAccount account,
    List<String> scopes,
  ) {
    return _guard(() async {
      final auth = await _resolveAuthClient(account).authorizeScopes(scopes);
      return auth.accessToken;
    });
  }

  @override
  Future<void> clearAuthorizationToken(String accessToken) {
    return _guard(
      () => GoogleSignIn.instance.authorizationClient
          .clearAuthorizationToken(accessToken: accessToken),
    );
  }

  @override
  Future<void> signOut() {
    return _guard(() => GoogleSignIn.instance.signOut());
  }

  @override
  Future<void> disconnect() {
    return _guard(() => GoogleSignIn.instance.disconnect());
  }
}

/// ADR-022 Seçenek A: Android için `google_sign_in` v7+ `DriveAccessTokenProvider`
/// uyarlayıcısı.
///
/// Güvenlik ve OAuth sınırları:
/// - Yalnızca `https://www.googleapis.com/auth/drive.file` kapsamı istenir (`ADR-011`).
/// - Kısa ömürlü `access_token` yalnızca RAM'de tutulur; asla `SecureTokenStore`,
///   disk veya SQLite'a yazılmaz ve loglara sızdırılmaz.
/// - `SecureTokenStore` içinde yalnızca sır olmayan `gdrive_connected_v1` bayrağı ve
///   isteğe bağlı `gdrive_account_email_v1` ipucu tutulur.
class AndroidGoogleSignInTokenProvider implements DriveAccessTokenProvider {
  static const String connectedFlagSecretKey = 'gdrive_connected_v1';
  static const String connectedEmailHintKey = 'gdrive_account_email_v1';
  static const Duration tokenCacheTtl = Duration(minutes: 50);

  final String serverClientId;
  final GoogleSignInClientAdapter adapter;
  final SecureTokenStore secureStore;
  final RedactingLogger? logger;
  final DateTime Function() clock;

  bool _initialized = false;
  Future<void>? _initInFlight;
  AndroidGoogleAccount? _currentAccount;
  String? _cachedToken;
  DateTime? _expiresAt;

  AndroidGoogleSignInTokenProvider({
    required this.serverClientId,
    required this.adapter,
    required this.secureStore,
    this.logger,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  bool get isConfigured => serverClientId.trim().isNotEmpty;

  Future<void> ensureInitialized() async {
    if (!isConfigured) {
      throw const DriveBackupException(
        'ERR_DRIVE_NOT_CONFIGURED',
        'Android Google Drive Web OAuth kimliği (MMS_GDRIVE_WEB_CLIENT_ID) tanımlı değil.',
      );
    }
    if (_initialized) return;
    final inFlight = _initInFlight;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final future = () async {
      await adapter.initialize(serverClientId: serverClientId.trim());
      _initialized = true;
    }();
    _initInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_initInFlight, future)) {
        _initInFlight = null;
      }
    }
  }

  Future<bool> isConnected() async {
    if (_currentAccount != null) return true;
    try {
      final flag = await secureStore.readSecret(connectedFlagSecretKey);
      return flag == 'true';
    } on SecureStorageException catch (e) {
      logger?.error('drive_auth', 'Google Drive bağlantı durumu okunamadı: $e');
      return false;
    }
  }

  Future<String?> connectedEmailHint() async {
    final current = _currentAccount?.email;
    if (current != null && current.trim().isNotEmpty) return current;
    try {
      final stored = await secureStore.readSecret(connectedEmailHintKey);
      return (stored != null && stored.trim().isNotEmpty) ? stored : null;
    } on SecureStorageException {
      return null;
    }
  }

  /// Ön planda kullanıcı etkileşimli hesap seçimi + `drive.file` kapsam izni.
  Future<void> connect() async {
    await ensureInitialized();
    final account = await adapter.authenticate();
    final token = await adapter.authorizeScopes(
      account,
      const [googleDriveFileScope],
    );
    if (token.trim().isEmpty) {
      throw const DriveBackupException(
        'ERR_DRIVE_REAUTH_REQUIRED',
        'Google Drive erişim anahtarı alınamadı; lütfen hesabı yeniden bağlayın.',
      );
    }
    _currentAccount = account;
    _cacheAccessToken(token);
    await secureStore.saveSecret(connectedFlagSecretKey, 'true');
    if (account.email.trim().isNotEmpty) {
      await secureStore.saveSecret(
        connectedEmailHintKey,
        account.email.trim(),
      );
    }
  }

  @override
  Future<String> accessToken({bool forceRefresh = false}) async {
    if (!isConfigured) {
      throw const DriveBackupException(
        'ERR_DRIVE_NOT_CONFIGURED',
        'Android Google Drive Web OAuth kimliği (MMS_GDRIVE_WEB_CLIENT_ID) tanımlı değil.',
      );
    }
    final cached = _cachedToken;
    if (!forceRefresh &&
        cached != null &&
        _expiresAt != null &&
        clock().isBefore(_expiresAt!)) {
      return cached;
    }

    await ensureInitialized();

    if (forceRefresh && cached != null) {
      try {
        await adapter.clearAuthorizationToken(cached);
      } catch (e) {
        logger?.warning(
          'drive_auth',
          'Önbellekteki Google Drive erişim anahtarı temizlenemedi: $e',
        );
      } finally {
        clearCachedAccessToken();
      }
    }

    var account = _currentAccount;
    if (account == null) {
      final String? flag;
      try {
        flag = await secureStore.readSecret(connectedFlagSecretKey);
      } on SecureStorageException catch (e) {
        logger?.error(
          'drive_auth',
          'Google Drive bağlantı durumu güvenli depodan okunamadı: $e',
        );
        throw const DriveBackupException(
          'ERR_DRIVE_REAUTH_REQUIRED',
          'Güvenli depo okunamadı; Google Drive hesabını yeniden bağlayın.',
        );
      }
      if (flag != 'true') {
        throw const DriveBackupException(
          'ERR_DRIVE_NOT_AUTHORIZED',
          'Google Drive yetkilendirmesi yapılmamış. Owner, Ayarlar > Yedekleme bölümünden Google hesabını bağlamalıdır.',
        );
      }
      account = await adapter.attemptLightweightAuthentication();
      if (account == null) {
        throw const DriveBackupException(
          'ERR_DRIVE_REAUTH_REQUIRED',
          'Google Drive oturumu yeniden doğrulama bekliyor; lütfen hesabı tekrar bağlayın.',
        );
      }
      _currentAccount = account;
    }

    final freshToken = await adapter.authorizationForScopes(
      account,
      const [googleDriveFileScope],
    );
    if (freshToken == null || freshToken.trim().isEmpty) {
      clearCachedAccessToken();
      throw const DriveBackupException(
        'ERR_DRIVE_REAUTH_REQUIRED',
        'Google Drive yetkisi yenilenemedi; lütfen hesabı yeniden bağlayın.',
      );
    }
    _cacheAccessToken(freshToken);
    return freshToken;
  }

  /// Uzak OAuth erişimini iptal eder (ağ/servis hatasında yerel oturumu da temizler).
  /// Yerel `.mmsbak` dosyalarına, Outbox kayıtlarına veya `client_seq` değerine dokunmaz.
  Future<void> disconnect() async {
    final cached = _cachedToken;
    clearCachedAccessToken();
    if (cached != null) {
      try {
        await adapter.clearAuthorizationToken(cached);
      } catch (e) {
        logger?.warning(
          'drive_auth',
          'Google Drive erişim anahtarı önbellekten temizlenemedi: $e',
        );
      }
    }

    try {
      await adapter.disconnect();
    } catch (e) {
      logger?.warning(
        'drive_auth',
        'Google Drive uzak erişim iptali tamamlanamadı; yerel oturum kapatılıyor: $e',
      );
      try {
        await adapter.signOut();
      } catch (signOutError) {
        logger?.warning(
          'drive_auth',
          'Yerel Google Sign-In oturumu kapatılamadı: $signOutError',
        );
      }
    } finally {
      _currentAccount = null;
      try {
        await secureStore.deleteSecret(connectedFlagSecretKey);
      } catch (_) {}
      try {
        await secureStore.deleteSecret(connectedEmailHintKey);
      } catch (_) {}
    }
  }

  void clearCachedAccessToken() {
    _cachedToken = null;
    _expiresAt = null;
  }

  void _cacheAccessToken(String token) {
    logger?.registerSensitiveValue(token);
    _cachedToken = token;
    _expiresAt = clock().add(tokenCacheTtl);
  }
}
