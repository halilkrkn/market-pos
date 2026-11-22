/// Teknik istisna, ağ ve SQLite hata mesajlarını sade, anlaşılır Türkçe
/// kullanıcı mesajlarına dönüştüren ve gizli anahtar/token bilgilerini
/// maskeleyen saf Dart yardımcı sınıf.
abstract final class UserFriendlyErrorMapper {
  /// Ham hata metnindeki gizli kimlik doğrulama ve sır bilgilerini maskeler.
  static String redactSecrets(String raw) {
    var text = raw;
    text = text.replaceAll(
      RegExp(r'Bearer\s+[A-Za-z0-9_\-\.]+', caseSensitive: false),
      'Bearer [REDACTED]',
    );
    text = text.replaceAll(
      RegExp(r'mms_dt_[A-Za-z0-9_\-]+'),
      'mms_dt_[REDACTED]',
    );
    text = text.replaceAll(
      RegExp(
        r'(token|secret|password|pairing_secret|private_key)\s*[:=]\s*[^\s,;]+',
        caseSensitive: false,
      ),
      r'$1: [REDACTED]',
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
