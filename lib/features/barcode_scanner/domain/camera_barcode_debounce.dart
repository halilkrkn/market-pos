import '../../pos/domain/barcode_input_sanitizer.dart';

/// Kamera karelerinden (frame) gelen ardışık aynı barkodların
/// belirtilen bekleme penceresinde tekrar tetiklenmesini önleyen saf Dart yardımcı.
class CameraBarcodeDebounce {
  final Duration cooldown;
  final DateTime Function() _now;

  String? _lastBarcode;
  DateTime? _lastAcceptedAt;

  CameraBarcodeDebounce({
    this.cooldown = const Duration(milliseconds: 1500),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  /// Gelen ham barkodu temizler ve geçerliyse tekrar penceresini denetler.
  ///
  /// Geçersiz, boş veya bekleme süresi içinde tekrarlayan barkodlar için `null` döner.
  String? acceptRaw(String? rawValue, {DateTime? now}) {
    if (rawValue == null) return null;
    final sanitized = BarcodeInputSanitizer.sanitize(rawValue);
    if (!sanitized.isValid) return null;

    final timestamp = now ?? _now();
    if (_lastBarcode == sanitized.normalized && _lastAcceptedAt != null) {
      final elapsed = timestamp.difference(_lastAcceptedAt!);
      if (elapsed < cooldown) {
        return null;
      }
    }

    _lastBarcode = sanitized.normalized;
    _lastAcceptedAt = timestamp;
    return sanitized.normalized;
  }

  void reset() {
    _lastBarcode = null;
    _lastAcceptedAt = null;
  }
}
