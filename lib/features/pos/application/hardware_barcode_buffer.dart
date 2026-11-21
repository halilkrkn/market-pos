import '../domain/barcode_input_sanitizer.dart';

/// Harici HID (USB / Bluetooth-OTG) barkod okuyucu karakter akışı tamponu.
///
/// Kasa ekranında barkod kutusu odaklı değilken donanım tarayıcısından
/// milisaniyeler içinde gelen karakter dizisini toplar; manuel yavaş tuşlamaları
/// veya tekil Enter basımlarını barkod olarak yorumlamaz.
class HardwareBarcodeBuffer {
  final Duration maxInterKeyGap;
  final int minLength;
  final int maxLength;
  final DateTime Function() _now;

  final StringBuffer _buffer = StringBuffer();
  DateTime? _lastKeyAt;

  HardwareBarcodeBuffer({
    this.maxInterKeyGap = const Duration(milliseconds: 120),
    this.minLength = 4,
    this.maxLength = BarcodeInputSanitizer.maxLength,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  static final RegExp _singlePrintableAsciiRegex = RegExp(r'^[\x21-\x7E]$');

  bool get hasBufferedInput => _buffer.isNotEmpty;

  /// Tek bir donanım tuşu karakterini tampona ekler.
  void feedCharacter(String char) {
    if (!_singlePrintableAsciiRegex.hasMatch(char)) {
      return;
    }

    final current = _now();
    if (_lastKeyAt != null && current.difference(_lastKeyAt!) > maxInterKeyGap) {
      _buffer.clear();
    }

    if (_buffer.length < maxLength) {
      _buffer.write(char);
      _lastKeyAt = current;
    }
  }

  /// Sonlandırıcı tuş (`Enter` / `Tab`) geldiğinde tamponu doğrular ve tüketir.
  String? commit() {
    final raw = _buffer.toString();
    final lastKeyAt = _lastKeyAt;
    reset();

    if (raw.length < minLength || lastKeyAt == null) {
      return null;
    }
    if (_now().difference(lastKeyAt) > maxInterKeyGap * 2) {
      return null;
    }

    final sanitized = BarcodeInputSanitizer.sanitize(raw);
    return sanitized.isValid ? sanitized.normalized : null;
  }

  void reset() {
    _buffer.clear();
    _lastKeyAt = null;
  }
}
