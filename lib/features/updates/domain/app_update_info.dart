/// MARKET MMS — İstemci Sürüm Kontrolü Alan Modelleri.
class AppUpdateManifest {
  final String latestVersion;
  final String minSupportedVersion;
  final String? downloadUrl;
  final String? sha256Checksum;
  final String? releaseNotes;
  final bool mandatory;
  final String? assetFileName;

  const AppUpdateManifest({
    required this.latestVersion,
    required this.minSupportedVersion,
    this.downloadUrl,
    this.sha256Checksum,
    this.releaseNotes,
    this.mandatory = false,
    this.assetFileName,
  });

  factory AppUpdateManifest.fromJson(Map<String, dynamic> json) {
    final latest = (json['latest_version'] as String?)?.trim() ?? '';
    final minSupported =
        (json['min_supported_version'] as String?)?.trim() ?? '0.0.0';
    if (latest.isEmpty) {
      throw const FormatException('Manifestte "latest_version" eksik.');
    }
    final rawUrl = (json['download_url'] as String?)?.trim();
    final rawSha = (json['sha256'] as String?)?.trim().toLowerCase();
    final rawAssetName = (json['asset_file_name'] as String?)?.trim();
    return AppUpdateManifest(
      latestVersion: latest,
      minSupportedVersion: minSupported,
      downloadUrl: (rawUrl == null || rawUrl.isEmpty) ? null : rawUrl,
      sha256Checksum: (rawSha == null || rawSha.isEmpty) ? null : rawSha,
      releaseNotes: (json['release_notes'] as String?)?.trim(),
      mandatory: json['mandatory'] as bool? ?? false,
      assetFileName: (rawAssetName == null || rawAssetName.isEmpty)
          ? null
          : rawAssetName,
    );
  }

  static final RegExp _sha256Hex = RegExp(r'^[0-9a-f]{64}$');

  /// UPD-SEC: İndirme adresi sunan manifest yalnızca HTTPS adres ve geçerli SHA-256
  /// özetiyle kabul edilir. Sorun yoksa `null`, varsa kullanıcıya gösterilecek neden.
  String? get integrityProblem {
    final url = downloadUrl;
    if (url == null) return null; // Yalnızca sürüm bilgisi; indirilecek paket yok.
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return 'İndirme adresi HTTPS değil; paket bütünlüğü taşıma sırasında korunamaz.';
    }
    final sha = sha256Checksum;
    if (sha == null || !_sha256Hex.hasMatch(sha)) {
      return 'Manifestte geçerli bir SHA-256 paket özeti yok; indirilen paket doğrulanamaz.';
    }
    return null;
  }
}

enum AppUpdateAvailability { upToDate, updateAvailable, updateRequired, unavailable }

class AppUpdateCheckResult {
  final String currentVersion;
  final AppUpdateAvailability availability;
  final AppUpdateManifest? manifest;
  final String message;

  const AppUpdateCheckResult({
    required this.currentVersion,
    required this.availability,
    this.manifest,
    required this.message,
  });
}

/// SemVer (`major.minor.patch`, opsiyonel `v` öneki ve `+N` / `-bN` derleme numarası)
/// karşılaştırma yardımcısı.
class SemanticVersion implements Comparable<SemanticVersion> {
  final int major;
  final int minor;
  final int patch;
  final int? buildNumber;

  const SemanticVersion(
    this.major,
    this.minor,
    this.patch, {
    this.buildNumber,
  });

  static final RegExp _buildSuffixPattern = RegExp(
    r'(?:\+(\d+)|-b(\d+)(?:$|[+.]))',
    caseSensitive: false,
  );

  static SemanticVersion parse(String raw) {
    final trimmed = raw.trim().replaceFirst(RegExp(r'^[vV]'), '');
    if (trimmed.isEmpty) {
      throw FormatException('Geçersiz SemVer sürümü: $raw');
    }
    final core = trimmed.split('+').first.split('-').first;
    final parts = core.split('.');
    if (parts.isEmpty) {
      throw FormatException('Geçersiz SemVer sürümü: $raw');
    }
    final major = int.parse(parts[0]);
    final minor = parts.length > 1 ? int.parse(parts[1]) : 0;
    final patch = parts.length > 2 ? int.parse(parts[2]) : 0;

    int? buildNumber;
    final buildMatch = _buildSuffixPattern.firstMatch(trimmed);
    if (buildMatch != null) {
      final digits = buildMatch.group(1) ?? buildMatch.group(2);
      if (digits != null) {
        buildNumber = int.parse(digits);
      }
    }

    return SemanticVersion(
      major,
      minor,
      patch,
      buildNumber: buildNumber,
    );
  }

  @override
  int compareTo(SemanticVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    if (buildNumber != null && other.buildNumber != null) {
      return buildNumber!.compareTo(other.buildNumber!);
    }
    return 0;
  }

  bool operator <(SemanticVersion other) => compareTo(other) < 0;
  bool operator >(SemanticVersion other) => compareTo(other) > 0;
  bool operator >=(SemanticVersion other) => compareTo(other) >= 0;
  bool operator <=(SemanticVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      other is SemanticVersion &&
      major == other.major &&
      minor == other.minor &&
      patch == other.patch &&
      buildNumber == other.buildNumber;

  @override
  int get hashCode => Object.hash(major, minor, patch, buildNumber);
}
