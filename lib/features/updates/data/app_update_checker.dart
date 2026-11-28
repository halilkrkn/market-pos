import 'dart:convert';

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../core/constants/app_constants.dart';
import '../domain/app_update_info.dart';

/// Hub, yerel ağ dağıtım adresi veya GitHub Releases üzerinden sürüm kontrolü
/// yapan servis.
///
/// Offline ortamda asla istisna fırlatarak uygulama açılışını engellemez ve
/// SHA-256 doğrulaması bulunmayan paketleri fail-closed reddeder.
class AppUpdateChecker {
  final http.Client? client;
  final String currentVersion;
  final int? currentBuildNumber;
  final Duration timeout;

  static final RegExp _windowsMsiPattern = RegExp(
    r'^MarketMMS-Setup-.*\.msi$',
    caseSensitive: false,
  );
  static final RegExp _androidApkPattern = RegExp(
    r'^MarketMMS-.*-android.*\.apk$',
    caseSensitive: false,
  );
  static final RegExp _shaLinePattern = RegExp(
    r'^([0-9a-fA-F]{64})\s+\*?(.+)$',
  );

  const AppUpdateChecker({
    this.client,
    this.currentVersion = AppConstants.appVersion,
    this.currentBuildNumber,
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

  /// GitHub Releases API üzerinden platforma uygun paketi (`MarketMMS-Setup-*.msi`
  /// veya `MarketMMS-*-android*.apk`) ve `SHA256SUMS.txt` doğrulama özetini denetler.
  ///
  /// Fail-closed: `SHA256SUMS.txt` eksik, bozuk, HTTPS dışı veya paket özeti
  /// eşleşmiyorsa asla güncelleme önermez (`AppUpdateAvailability.unavailable` döner).
  Future<AppUpdateCheckResult> checkGitHubRelease({
    required TargetPlatform platform,
    bool includePrereleases = AppConstants.includePrereleaseUpdates,
    String apiUrl = AppConstants.githubReleasesApiUrl,
  }) async {
    final assetPattern = _assetPatternForPlatform(platform);
    if (assetPattern == null) {
      return AppUpdateCheckResult(
        currentVersion: currentVersion,
        availability: AppUpdateAvailability.unavailable,
        message: 'Bu platform için otomatik uzaktan güncelleme desteklenmiyor.',
      );
    }

    final apiUri = Uri.tryParse(apiUrl.trim());
    if (apiUri == null || apiUri.scheme != 'https' || apiUri.host.isEmpty) {
      return AppUpdateCheckResult(
        currentVersion: currentVersion,
        availability: AppUpdateAvailability.unavailable,
        message: 'Güncelleme adresi HTTPS değil; güvenli denetim reddedildi.',
      );
    }

    final ownsClient = client == null;
    final activeClient = client ?? http.Client();
    try {
      final resp = await activeClient
          .get(
            apiUri,
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'MarketMMS',
            },
          )
          .timeout(timeout);

      if (resp.statusCode != 200) {
        return AppUpdateCheckResult(
          currentVersion: currentVersion,
          availability: AppUpdateAvailability.unavailable,
          message:
              'Güncelleme sunucusundan yanıt alınamadı (HTTP ${resp.statusCode}).',
        );
      }

      final decoded = jsonDecode(resp.body);
      if (decoded is! List) {
        return AppUpdateCheckResult(
          currentVersion: currentVersion,
          availability: AppUpdateAvailability.unavailable,
          message: 'GitHub Releases yanıtı beklenen liste formatında değil.',
        );
      }

      final selected = _selectLatestEligibleRelease(
        decoded,
        includePrereleases: includePrereleases,
      );
      if (selected == null) {
        return AppUpdateCheckResult(
          currentVersion: currentVersion,
          availability: AppUpdateAvailability.upToDate,
          message: 'Uygulama güncel (v$currentVersion).',
        );
      }

      final release = selected.release;
      final latestSem = selected.version;
      final rawTag = (release['tag_name'] as String?)?.trim() ?? '';
      final normalizedVersion = rawTag.replaceFirst(RegExp(r'^[vV]'), '');
      final assetsRaw = release['assets'];
      if (assetsRaw is! List) {
        return AppUpdateCheckResult(
          currentVersion: currentVersion,
          availability: AppUpdateAvailability.unavailable,
          message: 'Sürüm varlık listesi bulunamadı.',
        );
      }

      String? installerName;
      String? installerUrl;
      String? shaSumsUrl;
      for (final rawAsset in assetsRaw) {
        if (rawAsset is! Map<String, dynamic>) continue;
        final name = (rawAsset['name'] as String?)?.trim() ?? '';
        final url = (rawAsset['browser_download_url'] as String?)?.trim() ?? '';
        if (name.isEmpty || url.isEmpty) continue;
        if (name.toLowerCase() == 'sha256sums.txt') {
          shaSumsUrl = url;
        } else if (installerName == null && assetPattern.hasMatch(name)) {
          installerName = name;
          installerUrl = url;
        }
      }

      if (installerName == null || installerUrl == null || shaSumsUrl == null) {
        return AppUpdateCheckResult(
          currentVersion: currentVersion,
          availability: AppUpdateAvailability.unavailable,
          message:
              'Sürüm paketi veya SHA256SUMS.txt doğrulama dosyası eksik.',
        );
      }

      final shaSumsUri = Uri.tryParse(shaSumsUrl);
      if (shaSumsUri == null ||
          shaSumsUri.scheme != 'https' ||
          shaSumsUri.host.isEmpty) {
        return AppUpdateCheckResult(
          currentVersion: currentVersion,
          availability: AppUpdateAvailability.unavailable,
          message:
              'SHA256SUMS.txt adresi HTTPS değil; güncelleme reddedildi.',
        );
      }

      final shaResp = await activeClient
          .get(
            shaSumsUri,
            headers: const {'User-Agent': 'MarketMMS'},
          )
          .timeout(timeout);
      if (shaResp.statusCode != 200) {
        return AppUpdateCheckResult(
          currentVersion: currentVersion,
          availability: AppUpdateAvailability.unavailable,
          message:
              'SHA256SUMS.txt doğrulama dosyası indirilemedi (HTTP ${shaResp.statusCode}).',
        );
      }

      final expectedSha = parseSha256FromSums(shaResp.body, installerName);
      if (expectedSha == null) {
        return AppUpdateCheckResult(
          currentVersion: currentVersion,
          availability: AppUpdateAvailability.unavailable,
          message:
              'SHA256SUMS.txt içinde $installerName için geçerli özet bulunamadı.',
        );
      }

      final manifest = AppUpdateManifest(
        latestVersion: normalizedVersion,
        minSupportedVersion: '0.0.0',
        downloadUrl: installerUrl,
        sha256Checksum: expectedSha,
        releaseNotes: (release['body'] as String?)?.trim(),
        assetFileName: installerName,
      );

      final problem = manifest.integrityProblem;
      if (problem != null) {
        return AppUpdateCheckResult(
          currentVersion: currentVersion,
          availability: AppUpdateAvailability.unavailable,
          message:
              'Güncelleme manifesti güvenli değil, dikkate alınmadı: $problem',
        );
      }

      final currentSem = SemanticVersion.parse(_effectiveCurrentVersion());
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

  /// `SHA256SUMS.txt` içeriğinden hedef dosya adına ait 64 karakterlik hex
  /// SHA-256 özetini çıkarır. Bulunamazsa `null` döner.
  static String? parseSha256FromSums(String body, String targetFileName) {
    final expectedBase = p.basename(targetFileName.trim());
    if (expectedBase.isEmpty) return null;

    String? caseInsensitiveMatch;
    for (final rawLine in const LineSplitter().convert(body)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final match = _shaLinePattern.firstMatch(line);
      if (match == null) continue;
      final hash = match.group(1)!.toLowerCase();
      final rawFile = match.group(2)!.trim();
      final base = p.basename(rawFile);
      if (base == expectedBase) {
        return hash;
      }
      if (caseInsensitiveMatch == null &&
          base.toLowerCase() == expectedBase.toLowerCase()) {
        caseInsensitiveMatch = hash;
      }
    }
    return caseInsensitiveMatch;
  }

  RegExp? _assetPatternForPlatform(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.windows => _windowsMsiPattern,
      TargetPlatform.android => _androidApkPattern,
      _ => null,
    };
  }

  String _effectiveCurrentVersion() {
    if (!currentVersion.contains('+') && !currentVersion.contains('-')) {
      final resolvedBuild = currentBuildNumber ??
          (currentVersion == AppConstants.appVersion
              ? AppConstants.appBuildNumber
              : null);
      if (resolvedBuild != null) {
        return '$currentVersion+$resolvedBuild';
      }
    }
    return currentVersion;
  }

  _SelectedRelease? _selectLatestEligibleRelease(
    List<dynamic> releases, {
    required bool includePrereleases,
  }) {
    _SelectedRelease? best;
    for (final item in releases) {
      if (item is! Map<String, dynamic>) continue;
      if (item['draft'] == true) continue;
      if (!includePrereleases && item['prerelease'] == true) continue;
      final rawTag = (item['tag_name'] as String?)?.trim();
      if (rawTag == null || rawTag.isEmpty) continue;
      final SemanticVersion parsed;
      try {
        parsed = SemanticVersion.parse(rawTag);
      } on FormatException {
        continue;
      }
      if (best == null || parsed > best.version) {
        best = _SelectedRelease(release: item, version: parsed);
      }
    }
    return best;
  }

  AppUpdateCheckResult _invalidManifest(String reason) => AppUpdateCheckResult(
        currentVersion: currentVersion,
        availability: AppUpdateAvailability.unavailable,
        message: 'Güncelleme manifesti geçersiz: $reason',
      );
}

class _SelectedRelease {
  final Map<String, dynamic> release;
  final SemanticVersion version;

  const _SelectedRelease({required this.release, required this.version});
}
