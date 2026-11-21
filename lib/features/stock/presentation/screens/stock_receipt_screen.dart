import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/platform/mms_ui_profile.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../barcode_scanner/barcode_scanner_providers.dart';
import '../../../barcode_scanner/domain/camera_scan_result.dart';
import '../../../catalog/catalog_providers.dart';
import '../../../catalog/presentation/widgets/product_edit_dialog.dart';
import '../../../pos/domain/money.dart';
import '../../application/stock_receipt_notifier.dart';
import '../../stock_providers.dart';
import '../widgets/stock_movement_labels.dart';

/// Stok Girişi — Mevcut ürüne barkodla stok ekleme (Faz 2 §4.3).
///
/// Yeni ürün OLUŞTURMAZ; bulunan ürünün stoğuna girilen miktarı ekler ve her
/// girişi ayrı bir `GIRIS` hareketi olarak saklar. Tamamen offline çalışır;
/// kayıtlar Outbox (`STOCK_RECEIPT`) ile Hub'a aktarılır.
class StockReceiptScreen extends ConsumerStatefulWidget {
  const StockReceiptScreen({super.key});

  @override
  ConsumerState<StockReceiptScreen> createState() => _StockReceiptScreenState();
}

class _StockReceiptScreenState extends ConsumerState<StockReceiptScreen> {
  final _barcodeController = TextEditingController();
  final _barcodeFocus = FocusNode();
  final _quantityController = TextEditingController();
  final _quantityFocus = FocusNode();
  final _purchaseController = TextEditingController();
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocus.dispose();
    _quantityController.dispose();
    _quantityFocus.dispose();
    _purchaseController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _lookup(String raw) async {
    if (raw.trim().isEmpty) return;
    await ref.read(stockReceiptProvider.notifier).lookupBarcode(raw);
    _barcodeController.clear();
    if (!mounted) return;
    if (ref.read(stockReceiptProvider).phase == StockReceiptPhase.productFound) {
      _quantityController.clear();
      _purchaseController.clear();
      _noteController.clear();
      _quantityFocus.requestFocus();
    } else {
      _barcodeFocus.requestFocus();
    }
  }

  Future<void> _scanWithCamera() async {
    final result = await ref.read(cameraBarcodeScannerProvider).scanBarcode(
          context,
          title: 'Stok Girişi için Barkod Tara',
          subtitle: 'Stoğu artırılacak ürünün barkodunu okutun',
        );
    if (!mounted) return;
    switch (result.status) {
      case CameraScanStatus.scanned:
        await _lookup(result.barcode!);
        break;
      case CameraScanStatus.cancelled:
        break;
      case CameraScanStatus.permissionDenied:
      case CameraScanStatus.error:
      case CameraScanStatus.unsupportedPlatform:
        AppSnackbar.show(
          context,
          message: result.errorMessage ?? 'Kamera ile barkod okunamadı.',
          tone: AppBadgeTone.warning,
        );
    }
  }

  Future<void> _submit() async {
    final ok = await ref.read(stockReceiptProvider.notifier).submit(
          rawQuantity: _quantityController.text,
          rawPurchasePrice: _purchaseController.text,
          rawNote: _noteController.text,
        );
    if (!mounted || !ok) return;
    _quantityController.clear();
    _purchaseController.clear();
    _noteController.clear();
    _barcodeFocus.requestFocus();
  }

  Future<void> _createNewProduct(String barcode) async {
    final categories = ref.read(catalogProvider).categories;
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => ProductEditDialog(
        categories: categories,
        initialBarcode: barcode,
        autoLookupExternal: true,
      ),
    );
    if (!mounted) return;
    if (created == true) {
      ref.invalidate(stockOverviewProvider);
    }
    // Ürün oluşturulduysa aynı barkodla tekrar sorgula; artık stok girişi yapılabilir.
    await _lookup(barcode);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    final state = ref.watch(stockReceiptProvider);
    final uiProfile = ref.watch(mmsUiProfileProvider);
    final isCompact = context.windowClass == MmsWindowClass.compact;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('Stok Girişi')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(isCompact ? MmsSpacing.md : MmsSpacing.xl),
          children: [
            Text(
              'Mevcut ürünün barkodunu okutun, gelen miktarı girin. Yeni ürün oluşturulmaz; '
              'miktar mevcut stoğa eklenir.',
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
            ),
            const SizedBox(height: MmsSpacing.md),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    key: const Key('stock_receipt_barcode_field'),
                    controller: _barcodeController,
                    focusNode: _barcodeFocus,
                    autofocus: !uiProfile.isMobile,
                    labelText: 'Barkod',
                    hintText: 'Okutun veya yazıp Enter’a basın',
                    prefixIcon: Icons.qr_code_2_rounded,
                    keyboardType: TextInputType.number,
                    onSubmitted: _lookup,
                  ),
                ),
                if (uiProfile.supportsCameraBarcodeScanning) ...[
                  const SizedBox(width: MmsSpacing.sm),
                  SizedBox(
                    height: 52,
                    child: AppButton(
                      key: const Key('stock_receipt_camera_button'),
                      label: 'Kamera',
                      icon: Icons.qr_code_scanner_rounded,
                      minHeight: 52,
                      onPressed: _scanWithCamera,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: MmsSpacing.md),
            if (state.phase == StockReceiptPhase.lookingUp)
              const LinearProgressIndicator(),
            if (state.message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: MmsSpacing.md),
                child: AppCard(
                  key: const Key('stock_receipt_message'),
                  child: Row(
                    children: [
                      Icon(
                        state.isError
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_rounded,
                        color: state.isError ? colors.warningText : colors.successText,
                      ),
                      const SizedBox(width: MmsSpacing.sm),
                      Expanded(
                        child: Text(
                          state.message!,
                          style: TextStyle(fontSize: 14, color: colors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (state.phase == StockReceiptPhase.notFound && state.scannedBarcode != null)
              Padding(
                padding: const EdgeInsets.only(bottom: MmsSpacing.md),
                child: AppButton(
                  key: const Key('stock_receipt_new_product_button'),
                  label: 'Yeni Ürün Ekle',
                  icon: Icons.add_box_outlined,
                  variant: AppButtonVariant.emerald,
                  expand: true,
                  onPressed: () => _createNewProduct(state.scannedBarcode!),
                ),
              ),
            if (state.product != null) ...[
              _ProductSummaryCard(product: state.product!),
              const SizedBox(height: MmsSpacing.md),
              AppTextField(
                key: const Key('stock_receipt_quantity_field'),
                controller: _quantityController,
                focusNode: _quantityFocus,
                labelText: 'Gelen Miktar (${state.product!.stockUnit})',
                hintText: state.product!.stockUnit == 'adet' ? 'ör. 2' : 'ör. 1,250',
                isNumeric: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: MmsSpacing.sm),
              AppTextField(
                key: const Key('stock_receipt_purchase_field'),
                controller: _purchaseController,
                labelText: 'Birim Alış Fiyatı (TL, opsiyonel)',
                hintText: 'ör. 7,50',
                isNumeric: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: MmsSpacing.sm),
              AppTextField(
                key: const Key('stock_receipt_note_field'),
                controller: _noteController,
                labelText: 'Açıklama (opsiyonel)',
                hintText: 'ör. İrsaliye no',
              ),
              const SizedBox(height: MmsSpacing.md),
              AppButton(
                key: const Key('stock_receipt_submit_button'),
                label: 'Stoğa Ekle',
                icon: Icons.add_circle_outline_rounded,
                expand: true,
                minHeight: 52,
                isLoading: state.phase == StockReceiptPhase.saving,
                onPressed: state.phase == StockReceiptPhase.saving ? null : _submit,
              ),
              const SizedBox(height: MmsSpacing.lg),
              _ProductMovementHistory(productId: state.product!.id),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProductSummaryCard extends StatelessWidget {
  final LocalProduct product;

  const _ProductSummaryCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    return AppCard(
      key: const Key('stock_receipt_product_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            product.name,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: MmsSpacing.xs),
          Text(
            'Barkod: ${product.barcode ?? '-'}',
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
          const SizedBox(height: MmsSpacing.xs),
          Text(
            'Mevcut stok: ${Money.formatMilliWithUnit(product.stock, product.stockUnit)}',
            key: const Key('stock_receipt_current_stock'),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: product.stock < 0 ? colors.dangerText : colors.textPrimary,
              fontFeatures: MmsTypography.tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductMovementHistory extends ConsumerWidget {
  final String productId;

  const _ProductMovementHistory({required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.mmsColors;
    final movementsAsync = ref.watch(productStockMovementsProvider(productId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Stok Hareket Geçmişi',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: MmsSpacing.sm),
        movementsAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => Text(
            'Hareket geçmişi yüklenemedi.',
            style: TextStyle(color: colors.dangerText),
          ),
          data: (movements) {
            if (movements.isEmpty) {
              return Text(
                'Bu ürün için henüz stok hareketi yok.',
                style: TextStyle(color: colors.textSecondary),
              );
            }
            return Column(
              key: const Key('stock_receipt_history'),
              children: [
                for (final m in movements)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      '${m.quantity > 0 ? '+' : ''}${Money.formatMilliWithUnit(m.quantity, m.unit)}'
                      ' · ${stockMovementLabel(m.movementType).$1}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontFeatures: MmsTypography.tabularFigures,
                        color: colors.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      [
                        m.createdAt.toFormattedDateTime(),
                        if (m.purchasePrice != null)
                          'Alış: ${Money.formatCents(m.purchasePrice!)}',
                        if (m.note != null) m.note!,
                      ].join(' · '),
                      style: TextStyle(fontSize: 12, color: colors.textSecondary),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
