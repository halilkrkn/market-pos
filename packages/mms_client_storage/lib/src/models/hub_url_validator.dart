/// Geçersiz veya platform politikasına aykırı Hub adresi hatası.
class HubUrlValidationException implements Exception {
  final String message;
  final String? rawUrl;

  const HubUrlValidationException(this.message, {this.rawUrl});

  @override
  String toString() => rawUrl == null
      ? 'HubUrlValidationException: $message'
      : 'HubUrlValidationException: $message ($rawUrl)';
}

/// Hub temel URL değerlerini doğrulayan ve normalize eden saf Dart yardımcısı.
class HubUrlValidator {
  const HubUrlValidator._();

  /// Host adının loopback veya belirtilmemiş (unspecified) adres olup olmadığını denetler.
  static bool isLoopbackOrUnspecifiedHost(String host) {
    var normalized = host.trim().toLowerCase();
    if (normalized.startsWith('[') && normalized.endsWith(']')) {
      normalized = normalized.substring(1, normalized.length - 1);
    }
    final zoneSeparator = normalized.indexOf('%');
    if (zoneSeparator != -1) {
      normalized = normalized.substring(0, zoneSeparator);
    }
    if (normalized.isEmpty) return true;

    if (normalized == 'localhost' ||
        normalized == 'localhost.localdomain' ||
        normalized.endsWith('.localhost')) {
      return true;
    }

    if (normalized == '::1' ||
        normalized == '0:0:0:0:0:0:0:1' ||
        normalized == '::' ||
        normalized == '0:0:0:0:0:0:0:0') {
      return true;
    }

    if (normalized.startsWith('::ffff:')) {
      return _isIpv4LoopbackOrUnspecified(normalized.substring(7));
    }

    return _isIpv4LoopbackOrUnspecified(normalized);
  }

  static bool _isIpv4LoopbackOrUnspecified(String host) {
    if (host == '2130706433' || host == '0') return true;
    final parts = host.split('.');
    if (parts.length < 2 || parts.length > 4) return false;
    final octets = <int>[];
    for (final part in parts) {
      final parsed = int.tryParse(part);
      if (parsed == null || parsed < 0 || parsed > 255) return false;
      octets.add(parsed);
    }
    if (octets[0] == 127) return true;
    return octets.length == 4 && octets.every((octet) => octet == 0);
  }

  /// Verilen Hub URL'sini doğrular ve sonda `/` olmadan standart origin biçimine indirger.
  static String normalizeAndValidate(
    String rawUrl, {
    required bool allowLoopback,
  }) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      throw HubUrlValidationException('Hub adresi boş olamaz.', rawUrl: rawUrl);
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.trim().isEmpty) {
      throw HubUrlValidationException(
        'Geçerli bir Hub HTTP/HTTPS adresi girilmelidir.',
        rawUrl: rawUrl,
      );
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw HubUrlValidationException(
        'Hub adresi yalnızca http veya https protokolünü kullanabilir.',
        rawUrl: rawUrl,
      );
    }

    if (uri.userInfo.isNotEmpty) {
      throw HubUrlValidationException(
        'Hub adresi kullanıcı adı veya parola içeremez.',
        rawUrl: rawUrl,
      );
    }

    if (uri.hasQuery || uri.hasFragment) {
      throw HubUrlValidationException(
        'Hub temel adresi sorgu parametresi veya fragment içeremez.',
        rawUrl: rawUrl,
      );
    }

    final hasOnlyTrailingSlashes =
        uri.path.isEmpty || uri.path.replaceAll('/', '').isEmpty;
    if (!hasOnlyTrailingSlashes) {
      throw HubUrlValidationException(
        'Hub temel adresi alt yol (path) içeremez.',
        rawUrl: rawUrl,
      );
    }

    if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) {
      throw HubUrlValidationException(
        'Hub port numarası 1 ile 65535 arasında olmalıdır.',
        rawUrl: rawUrl,
      );
    }

    if (!allowLoopback && isLoopbackOrUnspecifiedHost(uri.host)) {
      throw HubUrlValidationException(
        'Bu platformda loopback veya 0.0.0.0 Hub adresi kullanılamaz.',
        rawUrl: rawUrl,
      );
    }

    final normalizedUri = Uri(
      scheme: scheme,
      host: uri.host.toLowerCase(),
      port: uri.hasPort ? uri.port : null,
    );
    return normalizedUri.toString();
  }

  /// Kullanıcı tarafından manuel girilen IP, host veya tam URL metnini
  /// (`192.168.1.50`, `192.168.1.50:8945`, `https://192.168.1.50:8945`, `https://hub.local:8443`)
  /// normalize edip platform politikasına göre doğrular. Şemasız girdiler
  /// varsayılan olarak `https://` şemasına yükseltilir.
  static String normalizeUserInput(
    String rawInput, {
    int defaultPort = 8945,
    String defaultScheme = 'https',
    required bool allowLoopback,
  }) {
    final normalizedDefaultScheme = defaultScheme.trim().toLowerCase();
    if (normalizedDefaultScheme != 'https' && normalizedDefaultScheme != 'http') {
      throw HubUrlValidationException(
        'Geçersiz varsayılan Hub protokolü: $defaultScheme',
        rawUrl: rawInput,
      );
    }

    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      throw HubUrlValidationException(
        'Hub adresi veya IP boş olamaz.',
        rawUrl: rawInput,
      );
    }

    if (trimmed.contains('://')) {
      return normalizeAndValidate(trimmed, allowLoopback: allowLoopback);
    }

    if (trimmed.contains('/') ||
        trimmed.contains('?') ||
        trimmed.contains('#') ||
        trimmed.contains('@')) {
      throw HubUrlValidationException(
        'Geçerli bir IP adresi, host adı veya http/https URL girilmelidir.',
        rawUrl: rawInput,
      );
    }

    final String candidate;
    if (trimmed.startsWith('[')) {
      final closeIdx = trimmed.indexOf(']');
      if (closeIdx == -1) {
        throw HubUrlValidationException(
          'Geçersiz IPv6 adresi biçimi.',
          rawUrl: rawInput,
        );
      }
      final remainder = trimmed.substring(closeIdx + 1);
      if (remainder.isEmpty) {
        candidate = '$normalizedDefaultScheme://$trimmed:$defaultPort';
      } else if (remainder.startsWith(':')) {
        final portPart = remainder.substring(1);
        if (portPart.isEmpty || int.tryParse(portPart) == null) {
          throw HubUrlValidationException(
            'Geçersiz port numarası.',
            rawUrl: rawInput,
          );
        }
        candidate = '$normalizedDefaultScheme://$trimmed';
      } else {
        throw HubUrlValidationException(
          'Geçersiz IPv6 veya port biçimi.',
          rawUrl: rawInput,
        );
      }
    } else {
      final firstColon = trimmed.indexOf(':');
      final lastColon = trimmed.lastIndexOf(':');
      if (firstColon != -1 && firstColon != lastColon) {
        candidate = '$normalizedDefaultScheme://[$trimmed]:$defaultPort';
      } else if (firstColon != -1) {
        final portPart = trimmed.substring(firstColon + 1);
        if (portPart.isEmpty || int.tryParse(portPart) == null) {
          throw HubUrlValidationException(
            'Geçersiz port numarası.',
            rawUrl: rawInput,
          );
        }
        candidate = '$normalizedDefaultScheme://$trimmed';
      } else {
        candidate = '$normalizedDefaultScheme://$trimmed:$defaultPort';
      }
    }

    return normalizeAndValidate(candidate, allowLoopback: allowLoopback);
  }

  /// Geçersiz veya platform politikasına aykırı URL için istisna fırlatmak yerine `null` döner.
  static String? tryNormalize(
    String? rawUrl, {
    required bool allowLoopback,
  }) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return null;
    try {
      return normalizeAndValidate(rawUrl, allowLoopback: allowLoopback);
    } on HubUrlValidationException {
      return null;
    }
  }

  /// URL'nin geçerli ve platform politikasına uygun olup olmadığını bildirir.
  static bool isValid(
    String? rawUrl, {
    required bool allowLoopback,
  }) {
    return tryNormalize(rawUrl, allowLoopback: allowLoopback) != null;
  }
}
