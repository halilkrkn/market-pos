import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'presentation/camera_barcode_scanner_service.dart';

/// Kamera ile barkod tarama servis sağlayıcısı.
///
/// Windows masaüstünde güvenli biçimde `unsupportedPlatform` döner; Android/iOS'ta
/// `MobileScannerScreen` üzerinden gerçek kamera taraması başlatır. Widget
/// testlerinde sahte/mock servis ile override edilebilir.
final cameraBarcodeScannerProvider = Provider<CameraBarcodeScannerService>(
  (ref) => const PlatformCameraBarcodeScannerService(),
);
