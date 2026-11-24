import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/platform/mms_ui_profile.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../barcode_scanner/barcode_scanner_providers.dart';
import '../../../barcode_scanner/domain/camera_scan_result.dart';
import '../../../pos/domain/barcode_input_sanitizer.dart';
import '../../application/product_barcode_details.dart';
import '../../catalog_providers.dart';

/// Ürün kartı — birincil + ikincil barkod yönetimi (BR-PROD-02 / BR-PROD-15).
///
/// - Birincil barkodu gösterir; ikincil barkodları listeler, ekler ve (onayla) siler.
/// - Barkod girişi: elle/USB-HID okuyucu veya (destekleyen cihazda) kamera ile tarama.
/// - Değişiklikler yerel SQLite'a ve aynı transaction'da PRODUCT_UPSERT Outbox kaydına
///   yazılır (offline-first); Hub'a gönderim durumu ÜRÜN BAZINDA gösterilir.
class ProductBarcodesDialog extends ConsumerStatefulWidget {
  final String productId;

  const ProductBarcodesDialog({super.key, required this.productId});

  @override
  ConsumerState<ProductBarcodesDialog> createState() => _ProductBarcodesDialogState();
}

class _ProductBarcodesDialogState extends ConsumerState<ProductBarcodesDialog> {
  final _barcodeController = TextEditingController();

  ProductBarcodeDetails? _details;
  bool _isLoading = true;
  bool _isBusy = false;
  String? _feedback;
  bool _feedbackIsError = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final details =
          await ref.read(catalogProvider.notifier).loadBarcodeDetails(widget.productId);
      if (!mounted) return;
      setState(() {
        _details = details;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _feedback = 'Barkod bilgileri yüklenemedi. Lütfen tekrar deneyin.';
        _feedbackIsError = true;
      });
    }
  }

  void _showFeedback(String message, {required bool isError}) {
    setState(() {
      _feedback = message;
      _feedbackIsError = isError;
    });
  }

  Future<void> _addBarcode([String? scanned]) async {
    final sanitized = BarcodeInputSanitizer.sanitize(scanned ?? _barcodeController.text);
    if (!sanitized.isValid) {
      _showFeedback(
        sanitized.errorMessage ?? 'Geçersiz barkod biçimi.',
        isError: true,
      );
      return;
    }
    setState(() => _isBusy = true);
    final result = await ref.read(catalogProvider.notifier).addProductBarcode(
          productId: widget.productId,
          barcode: sanitized.normalized,
        );
    if (!mounted) return;
    if (result.success) _barcodeController.clear();
    await _reload();
    if (!mounted) return;
    setState(() => _isBusy = false);
    _showFeedback(result.message, isError: !result.success);
  }

  Future<void> _scanWithCamera() async {
    final scan = await ref.read(cameraBarcodeScannerProvider).scanBarcode(
          context,
          title: 'İkincil Barkod Tara',
          subtitle: 'Ürüne eklenecek ikincil barkodu kamera çerçevesine hizalayın',
        );
    if (!mounted) return;
    switch (scan.status) {
      case CameraScanStatus.scanned:
        final raw = scan.barcode;
        if (raw == null) return;
        _barcodeController.text = raw;
        await _addBarcode(raw);
        break;
      case CameraScanStatus.permissionDenied:
      case CameraScanStatus.error:
      case CameraScanStatus.unsupportedPlatform:
        _showFeedback(scan.errorMessage ?? 'Kamera ile barkod okunamadı.', isError: true);
        break;
      case CameraScanStatus.cancelled:
        break;
    }
  }

  Future<void> _confirmRemove(LocalProductBarcode barcode) async {
    final colors = context.mmsColors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: 'İkincil Barkodu Sil',
        icon: Icons.delete_outline_rounded,
        iconColor: colors.danger,
        maxWidth: 440,
        content: Text(
          '${barcode.barcode} barkodu bu üründen kaldırılsın mı? Barkod geçmişi korunur; '
          'kaldırılan barkod satış ekranında artık bu ürünü bulmaz.',
          style: TextStyle(fontSize: 14, color: colors.textSecondary),
        ),
        actions: [
          AppButton(
            key: const Key('barcode_remove_cancel'),
            label: 'Vazgeç',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton(
            key: const Key('barcode_remove_confirm'),
            label: 'Sil',
            variant: AppButtonVariant.danger,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isBusy = true);
    final result =
        await ref.read(catalogProvider.notifier).removeProductBarcode(barcode.id);
    if (!mounted) return;
    await _reload();
    if (!mounted) return;
    setState(() => _isBusy = false);
    _showFeedback(result.message, isError: !result.success);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    final uiProfile = ref.watch(mmsUiProfileProvider);
    final details = _details;

    final Widget content;
    if (_isLoading) {
      content = const Padding(
        padding: EdgeInsets.all(MmsSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (details == null) {
      content = _InlineNotice(
        key: const Key('product_barcode_feedback'),
        tone: AppBadgeTone.danger,
        message: _feedback ?? 'Ürün bulunamadı.',
      );
    } else {
      content = SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SyncStatusNotice(status: details.syncStatus),
            const SizedBox(height: MmsSpacing.md),
            Text(
              'Birincil Barkod',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: MmsSpacing.xxs),
            Text(
              details.primaryBarcode ?? 'Tanımlı değil (ürün düzenleme ekranından eklenir)',
              key: const Key('product_primary_barcode'),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: details.primaryBarcode != null
                    ? colors.textPrimary
                    : colors.textTertiary,
                fontFeatures: MmsTypography.tabularFigures,
              ),
            ),
            const SizedBox(height: MmsSpacing.md),
            Text(
              'İkincil Barkodlar (${details.secondaryBarcodes.length})',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: MmsSpacing.xxs),
            if (details.secondaryBarcodes.isEmpty)
              Text(
                'Bu ürüne tanımlı ikincil barkod yok.',
                key: const Key('secondary_barcodes_empty'),
                style: TextStyle(fontSize: 13, color: colors.textTertiary),
              )
            else
              for (final bc in details.secondaryBarcodes)
                Container(
                  key: Key('secondary_barcode_row_${bc.barcode}'),
                  margin: const EdgeInsets.only(bottom: MmsSpacing.xxs),
                  padding: const EdgeInsets.only(left: MmsSpacing.sm),
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.border),
                    borderRadius: BorderRadius.circular(MmsRadius.sm),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.qr_code_2_rounded, size: 18, color: colors.textSecondary),
                      const SizedBox(width: MmsSpacing.xs),
                      Expanded(
                        child: Text(
                          bc.barcode,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                            fontFeatures: MmsTypography.tabularFigures,
                          ),
                        ),
                      ),
                      AppIconButton(
                        key: Key('remove_barcode_${bc.barcode}'),
                        icon: Icons.delete_outline_rounded,
                        tooltip: 'İkincil barkodu sil',
                        color: colors.dangerText,
                        size: uiProfile.isMobile ? 48 : 44,
                        onPressed: _isBusy ? null : () => _confirmRemove(bc),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: MmsSpacing.md),
            TextField(
              key: const Key('secondary_barcode_input'),
              controller: _barcodeController,
              enabled: !_isBusy,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _isBusy ? null : _addBarcode(),
              style: TextStyle(
                color: colors.textPrimary,
                fontFeatures: MmsTypography.tabularFigures,
              ),
              decoration: const InputDecoration(
                labelText: 'Yeni İkincil Barkod',
                hintText: 'Barkodu okutun veya yazın',
              ),
            ),
            const SizedBox(height: MmsSpacing.sm),
            Wrap(
              spacing: MmsSpacing.sm,
              runSpacing: MmsSpacing.xs,
              children: [
                AppButton(
                  key: const Key('secondary_barcode_add_button'),
                  label: 'Barkod Ekle',
                  icon: Icons.add_rounded,
                  variant: AppButtonVariant.emerald,
                  minHeight: 48,
                  isLoading: _isBusy,
                  onPressed: _isBusy ? null : () => _addBarcode(),
                ),
                if (uiProfile.supportsCameraBarcodeScanning)
                  AppButton(
                    key: const Key('secondary_barcode_camera_button'),
                    label: 'Kamera ile Tara',
                    icon: Icons.qr_code_scanner_rounded,
                    variant: AppButtonVariant.secondary,
                    minHeight: 48,
                    onPressed: _isBusy ? null : _scanWithCamera,
                  ),
              ],
            ),
            if (_feedback != null) ...[
              const SizedBox(height: MmsSpacing.sm),
              _InlineNotice(
                key: const Key('product_barcode_feedback'),
                tone: _feedbackIsError ? AppBadgeTone.danger : AppBadgeTone.success,
                message: _feedback!,
              ),
            ],
          ],
        ),
      );
    }

    return AppDialog(
      title: 'Barkod Yönetimi',
      subtitle: details?.product.name,
      icon: Icons.qr_code_2_rounded,
      iconColor: colors.emerald,
      maxWidth: 560,
      content: content,
      actions: [
        AppButton(
          key: const Key('product_barcodes_close'),
          label: 'Kapat',
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// Ürün bazlı Hub gönderim durumu (genel Outbox rozetinden bağımsız).
class _SyncStatusNotice extends StatelessWidget {
  final ProductCatalogSyncStatus status;

  const _SyncStatusNotice({required this.status});

  @override
  Widget build(BuildContext context) {
    final (tone, message) = switch (status.state) {
      ProductCatalogSyncState.synced => (
          AppBadgeTone.success,
          'Bu ürünün barkodları Hub ile eşitlendi.',
        ),
      ProductCatalogSyncState.pending => (
          AppBadgeTone.warning,
          'Hub\'a gönderilmeyi bekleyen ${status.unsyncedOperationCount} değişiklik var. '
              'Değişiklikler bu cihazda geçerlidir; Hub erişilebilir olduğunda otomatik '
              'gönderilir. Bu sürede Hub verisi bu ürünün barkodlarını değiştirmez.',
        ),
      ProductCatalogSyncState.retrying => (
          AppBadgeTone.warning,
          'Hub\'a gönderim başarısız oldu, otomatik olarak yeniden denenecek '
              '(${status.unsyncedOperationCount} bekleyen değişiklik).'
              '${status.lastError != null ? ' Son hata: ${status.lastError}' : ''}',
        ),
      ProductCatalogSyncState.failed => (
          AppBadgeTone.danger,
          'Bu ürünün değişiklikleri Hub\'a GÖNDERİLEMEDİ (kalıcı hata). Yerel değişiklik '
              'korunuyor ancak diğer cihazlara ulaşmayacak. Sistem & Tanı ekranındaki '
              'Outbox bölümünü kontrol edin.'
              '${status.lastError != null ? ' Hata: ${status.lastError}' : ''}',
        ),
    };
    return _InlineNotice(
      key: Key('product_barcode_sync_status_${status.state.name}'),
      tone: tone,
      message: message,
    );
  }
}

class _InlineNotice extends StatelessWidget {
  final AppBadgeTone tone;
  final String message;

  const _InlineNotice({super.key, required this.tone, required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    final (bg, border, fg, icon) = switch (tone) {
      AppBadgeTone.success => (
          colors.successBg,
          colors.success,
          colors.successText,
          Icons.check_circle_outline_rounded,
        ),
      AppBadgeTone.warning => (
          colors.warningBg,
          colors.warning,
          colors.warningText,
          Icons.schedule_rounded,
        ),
      AppBadgeTone.danger => (
          colors.dangerBg,
          colors.danger,
          colors.dangerText,
          Icons.error_outline_rounded,
        ),
      _ => (colors.infoBg, colors.info, colors.infoText, Icons.info_outline_rounded),
    };
    return Container(
      padding: const EdgeInsets.all(MmsSpacing.sm),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(MmsRadius.sm),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: MmsSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}
