import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/constants/app_constants.dart';
import '../domain/app_update_info.dart';

/// Hub veya yerel ağ dağıtım adresinden sürüm manifesti kontrol eden servis.
///
/// Offline ortamda asla istisna fırlatarak uygulama açılışını engellemez.
class AppUpdateChecker {
  final http.Client? client;
  final String currentVersion;
  final Duration timeout;

  const AppUpdateChecker({
    this.client,
    this.currentVersion = AppConstants.appVersion,
    this.timeout = const Duration(seconds: 5),
  });

  Future<AppUpdateCheckResult> checkManifestUrl(String manifestUrl) async {
    final trimmed = manifestUrl.trim();
    if (trimmed.isEmpty) {
      return AppUpdateCheckResult(
        currentVersion: currentVersion,
        availability: AppUpdateAvailability.unavailable,
        message: 'Güncelleme manifest adresi tanımlı değil.',
      );
    }

    final ownsClient = client == null;
    final activeClient = client ?? http.Client();
    try {
      final resp = await activeClient.get(Uri.parse(trimmed)).timeout(timeout);
      if (resp.statusCode != 200) {
        return AppUpdateCheckResult(
          currentVersion: currentVersion,
          availability: AppUpdateAvailability.unavailable,
          message: 'Sürüm sunucusundan yanıt alınamadı (HTTP ${resp.statusCode}).',
        );
      }

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        return AppUpdateCheckResult(
          currentVersion: currentVersion,
          availability: AppUpdateAvailability.unavailable,
          message: 'Güncelleme manifesti geçersiz JSON formatında.',
        );
      }

      final manifest = AppUpdateManifest.fromJson(decoded);
      final problem = manifest.integrityProblem;
      if (problem != null) {
        return AppUpdateCheckResult(
          currentVersion: currentVersion,
          availability: AppUpdateAvailability.unavailable,
          message: 'Güncelleme manifesti güvenli değil, dikkate alınmadı: $problem',
        );
      }
      final currentSem = SemanticVersion.parse(currentVersion);
      final latestSem = SemanticVersion.parse(manifest.latestVersion);
      final minSem = SemanticVersion.parse(manifest.minSupportedVersion);

      if (currentSem < minSem) {
        return AppUpdateCheckResult(
          currentVersion: currentVersion,
          availability: AppUpdateAvailability.updateRequired,
          manifest: manifest,
          message:
              'Zorunlu sürüm güncellemesi gerekiyor (Mevcut: $currentVersion, Minimum: ${manifest.minSupportedVersion}).',
        );
      }
      if (latestSem > currentSem) {
        return AppUpdateCheckResult(
          currentVersion: currentVersion,
          availability: AppUpdateAvailability.updateAvailable,
          manifest: manifest,
          message:
              'Yeni sürüm hazır: v${manifest.latestVersion} (Mevcut: v$currentVersion).',
        );
      }

      return AppUpdateCheckResult(
        currentVersion: currentVersion,
        availability: AppUpdateAvailability.upToDate,
        manifest: manifest,
        message: 'Uygulama güncel (v$currentVersion).',
      );
    } on FormatException catch (e) {
      return _invalidManifest(e.message);
    } on TypeError catch (e) {
      return _invalidManifest('alan türü hatalı ($e)');
    } on Exception {
      // Ağ / zaman aşımı / TLS: uygulama açılışını asla engellemez.
      return AppUpdateCheckResult(
        currentVersion: currentVersion,
        availability: AppUpdateAvailability.unavailable,
        message: 'Sürüm kontrolü çevrimdışı veya ağ erişilemiyor.',
      );
    } finally {
      if (ownsClient) {
        activeClient.close();
      }
    }
  }

  AppUpdateCheckResult _invalidManifest(String reason) => AppUpdateCheckResult(
        currentVersion: currentVersion,
        availability: AppUpdateAvailability.unavailable,
        message: 'Güncelleme manifesti geçersiz: $reason',
      );
}
