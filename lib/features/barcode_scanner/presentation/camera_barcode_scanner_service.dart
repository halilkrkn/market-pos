import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/camera_scan_result.dart';
import '../domain/continuous_scan_session.dart';
import 'mobile_scanner_screen.dart';

/// POS ve ürün tanımlama akışlarının tükettiği ortak kamera barkod tarama sözleşmesi.
abstract interface class CameraBarcodeScannerService {
  Future<CameraScanResult> scanBarcode(
    BuildContext context, {
    String title = 'Kamera ile Barkod Tara',
    String subtitle = 'Barkodu çerçeve içerisine yerleştirin',
  });

  /// Kamerayı kullanıcı kapatana kadar açık tutar; her kabul edilen barkod
  /// [onBarcode] ile işlenir (ör. sepete ekleme). Kapanış nedeni döner
  /// (`cancelled`, `permissionDenied`, `error`, `unsupportedPlatform`).
  Future<CameraScanResult> scanContinuously(
    BuildContext context, {
    required Future<ScanFeedback> Function(String barcode) onBarcode,
    String title = 'Sürekli Barkod Tarama',
    String subtitle = 'Ürünleri sırayla çerçeveye hizalayın',
  });
}

/// Platform farkındalıklı gerçek kamera barkod tarama servisi.
class PlatformCameraBarcodeScannerService
    implements CameraBarcodeScannerService {
  final bool Function()? isSupportedOverride;

  const PlatformCameraBarcodeScannerService({this.isSupportedOverride});

  bool get isSupported =>
      isSupportedOverride?.call() ?? (Platform.isAndroid || Platform.isIOS);

  @override
  Future<CameraScanResult> scanBarcode(
    BuildContext context, {
    String title = 'Kamera ile Barkod Tara',
    String subtitle = 'Barkodu çerçeve içerisine yerleştirin',
  }) async {
    if (!isSupported) {
      return const CameraScanResult.unsupportedPlatform();
    }

    final result = await Navigator.of(context).push<CameraScanResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MobileScannerScreen(title: title, subtitle: subtitle),
      ),
    );
    return result ?? const CameraScanResult.cancelled();
  }

  @override
  Future<CameraScanResult> scanContinuously(
    BuildContext context, {
    required Future<ScanFeedback> Function(String barcode) onBarcode,
    String title = 'Sürekli Barkod Tarama',
    String subtitle = 'Ürünleri sırayla çerçeveye hizalayın',
  }) async {
    if (!isSupported) {
      return const CameraScanResult.unsupportedPlatform();
    }

    final result = await Navigator.of(context).push<CameraScanResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MobileScannerScreen(
          title: title,
          subtitle: subtitle,
          onContinuousBarcode: onBarcode,
        ),
      ),
    );
    return result ?? const CameraScanResult.cancelled();
  }
}
