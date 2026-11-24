/// Teknik istisna, ağ ve SQLite hata mesajlarını sade, anlaşılır Türkçe
/// kullanıcı mesajlarına dönüştüren ve gizli anahtar/token/dosya yolu bilgilerini
/// maskeleyen saf Dart yardımcı sınıf.
abstract final class UserFriendlyErrorMapper {
  static String _redactFilesystemPath(String rawPath) {
    final normalized = rawPath.trim();
    if (normalized.isEmpty) return '[REDACTED_PATH]';
    final sepIndex = normalized.lastIndexOf(RegExp(r'[/\\]'));
    if (sepIndex < 0 || sepIndex == normalized.length - 1) {
      return '[REDACTED_PATH]';
    }
    final basename = normalized.substring(sepIndex + 1);
    return basename.isEmpty ? '[REDACTED_PATH]' : '[REDACTED_PATH]/$basename';
  }

  /// Ham hata metnindeki gizli kimlik doğrulama, sır ve tam dosya yolu bilgilerini maskeler.
  static String redactSecrets(String raw) {
    var text = raw;
    // PEM ozel anahtar bloklarini temizle
    text = text.replaceAll(
      RegExp(
        r'-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----',
      ),
      '[REDACTED_PRIVATE_KEY]',
    );
    // JSON tirnakli gizli alanlari maskele
    text = text.replaceAllMapped(
      RegExp(
        r'("(?:auth_code|code|pairing_secret|device_token|access_token|accessToken|refresh_token|refreshToken|token|password|backupPassword|backup_password|recovery_password|recoveryPassword|privateKey|private_key|client_secret|clientSecret|admin_secret|adminSecret|live_sync_secret|dpapi_secret|signing_key|code_verifier|x-mms-admin-secret|x-admin-secret|api_key|upload_id|session|signature|sig|secret|pepper)"\s*:\s*)"[^"]*"',
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}"[REDACTED]"',
    );
    text = text.replaceAll(
      RegExp(r'Bearer\s+[A-Za-z0-9_\-\.]+', caseSensitive: false),
      'Bearer [REDACTED]',
    );
    text = text.replaceAll(
      RegExp(r'mms_dt_[A-Za-z0-9_\-]+'),
      'mms_dt_[REDACTED]',
    );
    // Google OAuth access token, refresh token ve client secret kaliplari
    text = text.replaceAll(
      RegExp(r'\bya29\.[A-Za-z0-9_\-\.]+'),
      'ya29.[REDACTED]',
    );
    text = text.replaceAll(
      RegExp(r'\b1//[A-Za-z0-9_\-\.]+'),
      '1//[REDACTED]',
    );
    text = text.replaceAll(
      RegExp(r'\bGOCSPX-[A-Za-z0-9_\-]+'),
      'GOCSPX-[REDACTED]',
    );
    // URL sorgu parametrelerindeki hassas oauth/drive/admin parametrelerini maskele
    text = text.replaceAllMapped(
      RegExp(
        r"""([?&])(code|auth_code|access_token|refresh_token|device_token|token|client_secret|admin_secret|live_sync_secret|dpapi_secret|signing_key|recovery_password|pairing_secret|private_key|code_verifier|api_key|key|upload_id|session|signature|sig|pepper|password|secret)=([^&#\s"'`\)\]]*)""",
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}${m.group(2)}=[REDACTED]',
    );
    text = text.replaceAllMapped(
      RegExp(
        r"""\b(access_token|refresh_token|device_token|token|client_secret|admin_secret|live_sync_secret|dpapi_secret|signing_key|recovery_password|pairing_secret|private_key|code_verifier|x-mms-admin-secret|x-admin-secret|api_key|auth_code|upload_id|pepper|secret|password)\s*([:=])\s*(?!\[REDACTED\])([^\s,&;"'`\)\]]+)""",
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}${m.group(2)} [REDACTED]',
    );
    // Stack trace ve file:/// URI icindeki tam yerel yollar
    text = text.replaceAllMapped(
      RegExp(
        r"""file:///(?:[A-Za-z]:[\\/][^\s"'`\)\]\r\n]+|(?:data|Users|home|var|private|tmp|opt|etc|root|storage|mnt|sdcard|Library|Volumes|proc)/[^\s"'`\)\]\r\n]+)""",
      ),
      (m) => 'file:///${_redactFilesystemPath(m.group(0)!.substring(8))}',
    );
    // Cift veya tek tirnakli (bosluk icerebilen) Windows/POSIX dosya yollari
    text = text.replaceAllMapped(
      RegExp(
        r'"((?:(?<![A-Za-z0-9_])[A-Za-z]:[\\/]|\\\\|/(?:data|Users|home|var|private|tmp|opt|etc|root|storage|mnt|sdcard|Library|Volumes|proc)/)[^"\r\n]+)"',
      ),
      (m) => '"${_redactFilesystemPath(m.group(1)!)}"',
    );
    text = text.replaceAllMapped(
      RegExp(
        r"'((?:(?<![A-Za-z0-9_])[A-Za-z]:[\\/]|\\\\|/(?:data|Users|home|var|private|tmp|opt|etc|root|storage|mnt|sdcard|Library|Volumes|proc)/)[^'\r\n]+)'",
      ),
      (m) => "'${_redactFilesystemPath(m.group(1)!)}'",
    );
    // Tirnaksiz Windows surucu (C:\ veya C:/) ve UNC yollari
    text = text.replaceAllMapped(
      RegExp(r"""(?<![A-Za-z0-9_])(?:[A-Za-z]:[\\/]|\\\\)[^\s"'`\)\]\r\n,;]+"""),
      (m) => _redactFilesystemPath(m.group(0)!),
    );
    // Tirnaksiz Android / macOS / POSIX yerel kok dosya yollari (URL disinda)
    text = text.replaceAllMapped(
      RegExp(
        r"""(?<![A-Za-z0-9:/\.\[])/(?:data|Users|home|var|private|tmp|opt|etc|root|storage|mnt|sdcard|Library|Volumes|proc)/[^\s"'`\)\]\r\n,;]+""",
      ),
      (m) => _redactFilesystemPath(m.group(0)!),
    );
    return text;
  }

  /// Teknik hata/exception metnini kullanıcı dostu Türkçe mesaja çevirir.
  static String map(
    Object error, {
    String fallback =
        'İşlem sırasında bir sorun oluştu. Lütfen tekrar deneyin.',
  }) {
    final redacted = redactSecrets(error.toString()).trim();
    if (redacted.isEmpty) return fallback;
    final lower = redacted.toLowerCase();

    if (lower.contains('socketexception') ||
        lower.contains('connection refused') ||
        lower.contains('failed host lookup') ||
        lower.contains('network is unreachable') ||
        lower.contains('errno = 10061') ||
        lower.contains('errno = 111') ||
        lower.contains('errno = 101')) {
      return 'Master Hub ile yerel ağ bağlantısı kurulamadı. Çevrimdışı çalışma kesintisiz sürer; ağ bağlantısını kontrol edip tekrar deneyin.';
    }

    if (lower.contains('timeoutexception') ||
        lower.contains('timed out') ||
        lower.contains('zaman aşımı')) {
      return 'Master Hub yanıt süresi aşıldı. Ağ bağlantınızı kontrol edip tekrar deneyin.';
    }

    if (lower.contains('tls_pin_mismatch') ||
        lower.contains('tlspinmismatchexception') ||
        lower.contains('parmak izi') ||
        lower.contains('pinning')) {
      return 'Güvenlik uyarısı: Hub TLS sertifika parmak izi sabitlenen değerle uyuşmuyor. Sistem & Tanı ekranından cihaz eşleştirmesini kontrol edin.';
    }

    if (lower.contains('tls_cert_error') ||
        lower.contains('tlscertificatevalidationexception') ||
        lower.contains('sertifika doğrulama') ||
        lower.contains('ip adresini (san)') ||
        lower.contains('handshakeexception') ||
        lower.contains('certificate') ||
        lower.contains('tlsexception') ||
        lower.contains('tlsvers')) {
      return 'Güvenli TLS sertifika doğrulaması başarısız oldu (SAN/IP, sunucu adı veya geçerlilik tarihi). Sertifika ayarlarını kontrol edin.';
    }

    if (lower.contains('401') ||
        lower.contains('403') ||
        lower.contains('unauthorized') ||
        lower.contains('device_revoked') ||
        lower.contains('devicetoken') ||
        lower.contains('yetkilendirme')) {
      return 'Cihaz yetkilendirme anahtarı geçersiz veya eksik. Sistem & Tanı ekranından cihazı yeniden eşleştirin.';
    }

    if (lower.contains('503') ||
        lower.contains('service draining') ||
        lower.contains('draining')) {
      return 'Master Hub şu anda bakım veya geri yükleme modunda. İşlemler yerel kuyrukta güvenle bekliyor.';
    }

    if (lower.contains('sqliteexception') ||
        lower.contains('database is locked') ||
        lower.contains('busy')) {
      return 'Yerel veritabanı kısa süreli yoğun. Lütfen birkaç saniye sonra tekrar deneyin.';
    }

    if (lower.contains('formatexception') ||
        lower.contains('unexpected character')) {
      return 'Sunucu yanıtı beklenmeyen biçimde geldi. Tekrar deneyin.';
    }

    // Yığın izi (stack trace) veya aşırı teknik sınıf adlarını gizle
    var firstLine = redacted.split('\n').first.trim();
    const technicalPrefixes = <String>[
      'Bad state:',
      'Invalid argument(s):',
      'RangeError:',
      'Exception:',
    ];
    for (final prefix in technicalPrefixes) {
      if (firstLine.startsWith(prefix)) {
        firstLine = firstLine.substring(prefix.length).trim();
        break;
      }
    }
    if (firstLine.isEmpty || firstLine.contains('#0 ') || firstLine.length > 220) {
      return fallback;
    }

    return firstLine;
  }
}
