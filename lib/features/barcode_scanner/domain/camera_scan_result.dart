/// Kamera barkod tarama işleminin sonuç durumları (`Faz 3` & `Faz 4`).
enum CameraScanStatus {
  scanned,
  cancelled,
  unsupportedPlatform,
  permissionDenied,
  error,
}

/// Paylaşımlı kamera barkod tarama akışının çıktı nesnesi.
class CameraScanResult {
  final CameraScanStatus status;
  final String? barcode;
  final String? errorMessage;

  const CameraScanResult._({
    required this.status,
    this.barcode,
    this.errorMessage,
  });

  const CameraScanResult.scanned(String barcode)
    : this._(status: CameraScanStatus.scanned, barcode: barcode);

  const CameraScanResult.cancelled()
    : this._(status: CameraScanStatus.cancelled);

  const CameraScanResult.unsupportedPlatform([String? message])
    : this._(
        status: CameraScanStatus.unsupportedPlatform,
        errorMessage:
            message ??
            'Kamera ile barkod tarama yalnızca Android ve iOS cihazlarda desteklenir.',
      );

  const CameraScanResult.permissionDenied([String? message])
    : this._(
        status: CameraScanStatus.permissionDenied,
        errorMessage:
            message ??
            'Kamera izni verilmedi. Ayarlardan kamera iznini etkinleştirip tekrar deneyin.',
      );

  const CameraScanResult.error(String message)
    : this._(status: CameraScanStatus.error, errorMessage: message);

  bool get isScanned => status == CameraScanStatus.scanned && barcode != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraScanResult &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          barcode == other.barcode &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(status, barcode, errorMessage);
}
