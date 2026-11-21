import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mms_client_storage/mms_client_storage.dart';

import '../../core/security/security_providers.dart';
import 'application/android_google_sign_in_token_provider.dart';
import 'application/google_drive_connect_service.dart';

/// Windows Masaüstü (loopback + PKCE) Google Cloud OAuth istemci kimlikleri.
const String kGoogleDriveClientId = String.fromEnvironment('MMS_GDRIVE_CLIENT_ID');
const String kGoogleDriveClientSecret = String.fromEnvironment('MMS_GDRIVE_CLIENT_SECRET');

/// Android `google_sign_in` v7+ (ADR-022) için aynı Google Cloud projesinden
/// alınmış zorunlu Web application Client ID (`serverClientId`).
/// APK içine Web client_secret KESİNLİKLE konulmaz.
const String kGoogleDriveWebClientId = String.fromEnvironment('MMS_GDRIVE_WEB_CLIENT_ID');

final googleDriveClientIdProvider = Provider<String>((ref) => kGoogleDriveClientId);
final googleDriveClientSecretProvider = Provider<String>((ref) => kGoogleDriveClientSecret);
final googleDriveWebClientIdProvider = Provider<String>((ref) => kGoogleDriveWebClientId);

/// Testlerde Android OAuth akışını masaüstü host üzerinde simüle edebilmek için platform bayrağı.
final driveIsAndroidPlatformProvider = Provider<bool>((ref) => Platform.isAndroid);

final googleSignInClientAdapterProvider = Provider<GoogleSignInClientAdapter>((ref) {
  return PluginGoogleSignInClientAdapter();
});

/// ADR-022: Android üzerinde `google_sign_in` v7+ tabanlı token sağlayıcısı (Windows'ta `null`).
final androidGoogleSignInTokenProvider = Provider<AndroidGoogleSignInTokenProvider?>((ref) {
  if (!ref.watch(driveIsAndroidPlatformProvider)) return null;
  return AndroidGoogleSignInTokenProvider(
    serverClientId: ref.watch(googleDriveWebClientIdProvider),
    adapter: ref.watch(googleSignInClientAdapterProvider),
    secureStore: ref.watch(secureTokenStoreProvider),
    logger: ref.watch(redactingLoggerProvider),
  );
});

final googleDriveConnectServiceProvider = Provider<GoogleDriveConnectService>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  final isAndroid = ref.watch(driveIsAndroidPlatformProvider);
  final androidProvider = ref.watch(androidGoogleSignInTokenProvider);
  final clientId = ref.watch(googleDriveClientIdProvider);
  final clientSecret = ref.watch(googleDriveClientSecretProvider);

  return GoogleDriveConnectService(
    clientId: clientId,
    clientSecret: clientSecret.isEmpty ? null : clientSecret,
    secureStore: ref.watch(secureTokenStoreProvider),
    httpClient: client,
    androidTokenProvider: androidProvider,
    isAndroidOverride: isAndroid,
  );
});

/// Windows ve Android için ortak Drive erişim token sağlayıcısı.
/// İlgili platform OAuth kimliği yapılandırılmamışsa fail-safe `null` döner.
final driveAccessTokenProvider = Provider<DriveAccessTokenProvider?>((ref) {
  final connect = ref.watch(googleDriveConnectServiceProvider);
  if (!connect.isConfigured) return null;
  if (connect.isAndroidMode) {
    return connect.androidTokenProvider;
  }

  final secureStore = ref.watch(secureTokenStoreProvider);
  final client = http.Client();
  ref.onDispose(client.close);
  return GoogleOAuthRefreshTokenProvider(
    clientId: connect.clientId,
    clientSecret: connect.clientSecret,
    readRefreshToken: () =>
        secureStore.readSecret(GoogleDriveConnectService.refreshTokenSecretKey),
    httpClient: client,
  );
});
