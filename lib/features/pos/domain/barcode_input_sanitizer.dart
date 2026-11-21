/// Barkod giriş doğrulama sonucu durumları (`OD-03`, Faz 3).
enum BarcodeValidationStatus {
  valid,
  empty,
  invalidFormat,
}

/// Normalizasyon ve doğrulama sonucu üretilen değer nesnesi.
class BarcodeSanitizationResult {
  final BarcodeValidationStatus status;
  final String normalized;
  final String? errorMessage;

  const BarcodeSanitizationResult._({
    required this.status,
    required this.normalized,
    this.errorMessage,
  });

  const BarcodeSanitizationResult.valid(String normalized)
    : this._(
        status: BarcodeValidationStatus.valid,
        normalized: normalized,
      );

  const BarcodeSanitizationResult.empty()
    : this._(
        status: BarcodeValidationStatus.empty,
        normalized: '',
        errorMessage: 'Lütfen geçerli bir barkod giriniz.',
      );

  const BarcodeSanitizationResult.invalidFormat()
    : this._(
        status: BarcodeValidationStatus.invalidFormat,
        normalized: '',
        errorMessage:
            'Geçersiz barkod biçimi. Lütfen barkodu tekrar okutun veya kontrol edin.',
      );

  bool get isValid => status == BarcodeValidationStatus.valid;
}

/// Saf Dart barkod normalizasyonu ve kontrol karakteri temizliği.
///
/// USB HID ve Bluetooth donanımsal barkod okuyucularının eklediği kontrol
/// karakterlerini (`STX`/`ETX`/`GS`/`\r`/`\n`/`\t`) arındırır ve geçerli
/// yazdırılabilir barkod biçimini doğrular.
abstract final class BarcodeInputSanitizer {
  static const int maxLength = 64;

  static final RegExp _controlCharsRegex = RegExp(r'[\x00-\x1F\x7F]');
  static final RegExp _printableAsciiNoSpaceRegex = RegExp(r'^[\x21-\x7E]+$');

  /// Girdideki ASCII kontrol karakterlerini temizler.
  static String stripControlChars(String raw) =>
      raw.replaceAll(_controlCharsRegex, '');

  /// Barkod girdisini normalize eder ve format güvenliğini doğrular.
  static BarcodeSanitizationResult sanitize(String raw) {
    final cleaned = stripControlChars(raw).trim();
    if (cleaned.isEmpty) {
      return const BarcodeSanitizationResult.empty();
    }
    if (cleaned.length > maxLength ||
        !_printableAsciiNoSpaceRegex.hasMatch(cleaned)) {
      return const BarcodeSanitizationResult.invalidFormat();
    }
    return BarcodeSanitizationResult.valid(cleaned);
  }
}
