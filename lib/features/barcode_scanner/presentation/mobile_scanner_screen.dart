import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/theme/design_tokens.dart';
import '../domain/camera_barcode_debounce.dart';
import '../domain/camera_scan_result.dart';
import '../domain/continuous_scan_session.dart';

/// Android ve iOS cihazlarda POS ve ürün tanımlama akışlarınca ortak kullanılan
/// tam ekran kamera barkod tarayıcı ekranı.
class MobileScannerScreen extends StatefulWidget {
  final String title;
  final String subtitle;

  /// Verilirse ekran sürekli tarama modunda çalışır: kamera açık kalır, her kabul
  /// edilen barkod bu geri çağırımla işlenir ve sonucu ekranda gösterilir.
  final Future<ScanFeedback> Function(String barcode)? onContinuousBarcode;

  /// `true` olduğunda yalnızca QR kodları taranır ve ürün barkodu sanitizasyonu
  /// (64 karakter sınırı) uygulanmaz; cihaz eşleştirme JSON/URL yükleri desteklenir.
  final bool rawQrMode;

  static const int maxRawQrPayloadLength = 4096;

  /// Ham QR kod değerini sanitizasyon olmadan yalnızca boşluk kırpıp
  /// uzunluk üst sınırıyla ([maxRawQrPayloadLength]) doğrular.
  @visibleForTesting
  static String? extractRawQrPayload(String? rawValue) {
    if (rawValue == null) return null;
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty || trimmed.length > maxRawQrPayloadLength) {
      return null;
    }
    return trimmed;
  }

  const MobileScannerScreen({
    super.key,
    this.title = 'Kamera ile Barkod Tara',
    this.subtitle = 'Barkodu çerçeve içerisine yerleştirin',
    this.onContinuousBarcode,
    this.rawQrMode = false,
  });

  @override
  State<MobileScannerScreen> createState() => _MobileScannerScreenState();
}

class _MobileScannerScreenState extends State<MobileScannerScreen> {
  final CameraBarcodeDebounce _debounce = CameraBarcodeDebounce();
  MobileScannerController? _controller;
  ContinuousScanSession? _session;
  ScanFeedback? _feedback;
  bool _hasCompleted = false;
  bool _torchEnabled = false;

  bool get _isContinuous => widget.onContinuousBarcode != null;

  bool get _isSupportedPlatform => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    if (_isSupportedPlatform) {
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        detectionTimeoutMs: 250,
        facing: CameraFacing.back,
        formats: widget.rawQrMode
            ? const [BarcodeFormat.qrCode]
            : const <BarcodeFormat>[],
      );
    }
    final onBarcode = widget.onContinuousBarcode;
    if (onBarcode != null) {
      _session = ContinuousScanSession(
        debounce: _debounce,
        onBarcode: onBarcode,
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _complete(CameraScanResult result) {
    if (_hasCompleted || !mounted) return;
    _hasCompleted = true;
    final controller = _controller;
    if (controller != null) {
      unawaited(controller.stop().catchError((_) {}));
    }
    Navigator.of(context).pop(result);
  }

  void _handleCapture(BarcodeCapture capture) {
    if (_hasCompleted) return;
    if (widget.rawQrMode) {
      for (final barcode in capture.barcodes) {
        final candidate = barcode.rawValue ?? barcode.displayValue;
        final payload = MobileScannerScreen.extractRawQrPayload(candidate);
        if (payload != null) {
          _complete(CameraScanResult.scanned(payload));
          return;
        }
      }
      return;
    }
    final session = _session;
    if (session != null) {
      unawaited(_handleContinuousCapture(session, capture));
      return;
    }
    for (final barcode in capture.barcodes) {
      final candidate = barcode.rawValue ?? barcode.displayValue;
      final normalized = _debounce.acceptRaw(candidate);
      if (normalized != null) {
        _complete(CameraScanResult.scanned(normalized));
        return;
      }
    }
  }

  Future<void> _handleContinuousCapture(
    ContinuousScanSession session,
    BarcodeCapture capture,
  ) async {
    for (final barcode in capture.barcodes) {
      final feedback = await session.handleRaw(
        barcode.rawValue ?? barcode.displayValue,
      );
      if (feedback == null) continue;
      unawaited(
        feedback.isSuccess
            ? HapticFeedback.mediumImpact()
            : HapticFeedback.heavyImpact(),
      );
      if (mounted && !_hasCompleted) {
        setState(() => _feedback = feedback);
      }
      return;
    }
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.toggleTorch();
      if (mounted) {
        setState(() => _torchEnabled = !_torchEnabled);
      }
    } catch (e) {
      debugPrint('[MobileScannerScreen] Fener değiştirilemedi: ${e.runtimeType}');
    }
  }

  Future<void> _switchCamera() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.switchCamera();
    } catch (e) {
      debugPrint('[MobileScannerScreen] Kamera değiştirilemedi: ${e.runtimeType}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;

    if (!_isSupportedPlatform || _controller == null) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(title: Text(widget.title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(MmsSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AppCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.no_photography_outlined,
                      size: 40,
                      color: colors.warningText,
                    ),
                    const SizedBox(height: MmsSpacing.md),
                    Text(
                      'Bu platformda dahili kamera tarayıcı desteklenmiyor.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: MmsSpacing.xs),
                    Text(
                      'Windows masaüstünde USB HID barkod okuyucu veya manuel giriş kullanabilirsiniz.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: MmsSpacing.md),
                    AppButton(
                      label: 'Geri Dön',
                      minHeight: 48,
                      onPressed: () => _complete(
                        const CameraScanResult.unsupportedPlatform(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _handleCapture,
            errorBuilder: (context, error) => _buildErrorState(error),
          ),

          // Tarama kılavuz çerçevesi
          IgnorePointer(
            child: Center(
              child: Container(
                width: widget.rawQrMode ? 240 : 260,
                height: widget.rawQrMode ? 240 : 160,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(MmsRadius.lg),
                  border: Border.all(color: colors.limeAccent, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 12,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Üst kontrol çubuğu (>= 48dp dokunma hedefleri)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(MmsSpacing.sm),
                padding: const EdgeInsets.symmetric(
                  horizontal: MmsSpacing.sm,
                  vertical: MmsSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(MmsRadius.md),
                ),
                child: Row(
                  children: [
                    IconButton(
                      key: const Key('scanner_close_button'),
                      tooltip: 'Kapat',
                      onPressed: () =>
                          _complete(const CameraScanResult.cancelled()),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.close_rounded),
                    ),
                    const SizedBox(width: MmsSpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            widget.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: const Key('scanner_torch_button'),
                      tooltip: _torchEnabled ? 'Flaşı Kapat' : 'Flaşı Aç',
                      onPressed: _toggleTorch,
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        foregroundColor: _torchEnabled
                            ? colors.limeAccent
                            : Colors.white,
                      ),
                      icon: Icon(
                        _torchEnabled
                            ? Icons.flash_on_rounded
                            : Icons.flash_off_rounded,
                      ),
                    ),
                    IconButton(
                      key: const Key('scanner_switch_camera_button'),
                      tooltip: 'Kamera Değiştir',
                      onPressed: _switchCamera,
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.cameraswitch_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Alt şerit: manuel girişe dönüş veya sürekli modda geri bildirim + Bitti
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(MmsSpacing.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_isContinuous && _feedback != null) ...[
                      _ContinuousFeedbackBanner(feedback: _feedback!),
                      const SizedBox(height: MmsSpacing.sm),
                    ],
                    SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        key: const Key('scanner_manual_fallback_button'),
                        onPressed: () =>
                            _complete(const CameraScanResult.cancelled()),
                        icon: Icon(
                          _isContinuous
                              ? Icons.check_circle_outline_rounded
                              : Icons.keyboard_alt_outlined,
                        ),
                        label: Text(
                          _isContinuous
                              ? 'Taramayı Bitir'
                              : 'Manuel Girişe Dön',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.78),
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(MmsRadius.md),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(MobileScannerException error) {
    final isPermissionDenied =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    final isUnsupported = error.errorCode == MobileScannerErrorCode.unsupported;
    final String message;
    final CameraScanResult result;

    if (isPermissionDenied) {
      message = 'Kamera izni reddedildi. Lütfen cihaz ayarlarından Market MMS için kamera iznini etkinleştirin veya manuel girişi kullanın.';
      result = CameraScanResult.permissionDenied(message);
    } else if (isUnsupported) {
      message = 'Bu cihazda kullanılabilir kamera bulunamadı.';
      result = CameraScanResult.unsupportedPlatform(message);
    } else {
      message =
          'Kamera başlatılamadı. Manuel barkod girişi ile devam edebilirsiniz.';
      result = CameraScanResult.error(message);
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MmsSpacing.lg),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(MmsSpacing.lg),
          decoration: BoxDecoration(
            color: const Color(0xFF17211E),
            borderRadius: BorderRadius.circular(MmsRadius.lg),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isPermissionDenied
                    ? Icons.lock_outline_rounded
                    : Icons.videocam_off_outlined,
                color: Colors.amberAccent,
                size: 38,
              ),
              const SizedBox(height: MmsSpacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: MmsSpacing.md),
              SizedBox(
                height: 48,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _complete(result),
                  child: const Text('Manuel Girişe Dön'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sürekli taramada son okumanın sonucunu (eklendi / bulunamadı / hata) gösterir.
class _ContinuousFeedbackBanner extends StatelessWidget {
  final ScanFeedback feedback;

  const _ContinuousFeedbackBanner({required this.feedback});

  @override
  Widget build(BuildContext context) {
    final (Color background, IconData icon) = switch (feedback.kind) {
      ScanFeedbackKind.success => (
        const Color(0xFF1B5E20),
        Icons.check_circle_rounded,
      ),
      ScanFeedbackKind.notFound => (
        const Color(0xFF8A4B00),
        Icons.help_outline_rounded,
      ),
      ScanFeedbackKind.error => (
        const Color(0xFF8E1B1B),
        Icons.error_outline_rounded,
      ),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('scanner_continuous_feedback'),
        padding: const EdgeInsets.symmetric(
          horizontal: MmsSpacing.md,
          vertical: MmsSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: background.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(MmsRadius.md),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: MmsSpacing.sm),
            Expanded(
              child: Text(
                feedback.message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
