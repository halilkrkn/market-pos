import 'camera_barcode_debounce.dart';

enum ScanFeedbackKind { success, notFound, error }

/// Sürekli tarama sırasında her okuma için kullanıcıya gösterilen sonuç.
class ScanFeedback {
  final ScanFeedbackKind kind;
  final String message;

  const ScanFeedback._(this.kind, this.message);

  const ScanFeedback.success(String message) : this._(ScanFeedbackKind.success, message);
  const ScanFeedback.notFound(String message) : this._(ScanFeedbackKind.notFound, message);
  const ScanFeedback.error(String message) : this._(ScanFeedbackKind.error, message);

  bool get isSuccess => kind == ScanFeedbackKind.success;
}

/// Kamera açık kaldığı sürece ardışık barkodları işleyen saf Dart oturum.
///
/// - Aynı barkodun ardışık karelerini [CameraBarcodeDebounce] soğuma süresinde bastırır.
/// - Bir barkod işlenirken gelen diğer kareleri bırakır (çift sepete ekleme olmaz).
/// - İşleyici hata verse bile oturum kilitlenmez.
class ContinuousScanSession {
  final CameraBarcodeDebounce debounce;
  final Future<ScanFeedback> Function(String barcode) onBarcode;

  bool _isProcessing = false;
  ScanFeedback? _lastFeedback;
  int _processedCount = 0;

  ContinuousScanSession({
    CameraBarcodeDebounce? debounce,
    required this.onBarcode,
  }) : debounce = debounce ?? CameraBarcodeDebounce();

  bool get isProcessing => _isProcessing;
  ScanFeedback? get lastFeedback => _lastFeedback;
  int get processedCount => _processedCount;

  /// Kameradan gelen ham değeri işler; yok sayılan kareler için `null` döner.
  Future<ScanFeedback?> handleRaw(String? raw) async {
    if (_isProcessing) return null;
    final barcode = debounce.acceptRaw(raw);
    if (barcode == null) return null;

    _isProcessing = true;
    try {
      final feedback = await onBarcode(barcode);
      _processedCount++;
      _lastFeedback = feedback;
      return feedback;
    } catch (_) {
      const feedback = ScanFeedback.error('Barkod işlenemedi. Lütfen tekrar okutun.');
      _lastFeedback = feedback;
      return feedback;
    } finally {
      _isProcessing = false;
    }
  }
}
