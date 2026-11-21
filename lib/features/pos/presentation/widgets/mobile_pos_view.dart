import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../diagnostics/domain/system_status.dart';
import '../../../sync/domain/sync_coordinator_state.dart';
import '../../domain/cart_item.dart';
import '../../domain/cart_state.dart';
import '../../domain/money.dart';
import '../../domain/pos_repository.dart';
import 'pos_cart_panel.dart';
import 'virtual_numpad_panel.dart';

/// Android Telefon ve Tablet için tek elle kullanım odaklı dokunmatik POS görünümü.
///
/// Masaüstü kısayol etiketlerini (`F1/F2/F9/F10/Esc`) içermez; tüm dokunma
/// hedefleri `>= 48dp` standardındadır ve telefonda ödeme barı başparmak
/// erişiminde (`sticky thumb-zone`) sabit kalır.
class MobilePosView extends StatelessWidget {
  final TextEditingController barcodeController;
  final FocusNode barcodeFocusNode;
  final CartState cartState;
  final bool showVirtualNumpad;
  final SystemStatus systemStatus;
  final SyncCoordinatorState? syncState;
  final VoidCallback onSubmitBarcode;
  final ValueChanged<String> onAppendNumpadChar;
  final VoidCallback onBackspaceNumpad;
  final VoidCallback onClearBarcode;
  final VoidCallback? onOpenCameraScanner;
  final VoidCallback onToggleVirtualNumpad;
  final VoidCallback onOpenProductSearch;
  final ValueChanged<CartItem> onEditItemQuantity;
  final VoidCallback onOpenClearCartDialog;
  final ValueChanged<PaymentMethod> onOpenPaymentDialog;
  final VoidCallback onRetrySync;
  final VoidCallback onClearMessages;
  final ValueChanged<String> onSelectProduct;
  final ValueChanged<String> onIncrementProduct;
  final ValueChanged<String> onDecrementProduct;
  final ValueChanged<String> onRemoveProduct;

  const MobilePosView({
    super.key,
    required this.barcodeController,
    required this.barcodeFocusNode,
    required this.cartState,
    required this.showVirtualNumpad,
    required this.systemStatus,
    this.syncState,
    required this.onSubmitBarcode,
    required this.onAppendNumpadChar,
    required this.onBackspaceNumpad,
    required this.onClearBarcode,
    this.onOpenCameraScanner,
    required this.onToggleVirtualNumpad,
    required this.onOpenProductSearch,
    required this.onEditItemQuantity,
    required this.onOpenClearCartDialog,
    required this.onOpenPaymentDialog,
    required this.onRetrySync,
    required this.onClearMessages,
    required this.onSelectProduct,
    required this.onIncrementProduct,
    required this.onDecrementProduct,
    required this.onRemoveProduct,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isTabletWide = constraints.maxWidth >= 760;

        if (isTabletWide) {
          return _buildTabletLayout(context, colors);
        }

        return _buildPhoneLayout(context, colors, constraints.maxHeight);
      },
    );
  }

  Widget _buildPhoneLayout(
    BuildContext context,
    MmsColors colors,
    double availableHeight,
  ) {
    final toolbar = _buildMobileToolbar(context, colors);
    final banners = PosStatusBanners(
      systemStatus: systemStatus,
      syncState: syncState,
      cartState: cartState,
      onRetrySync: onRetrySync,
      onClearMessages: onClearMessages,
      onOpenProductSearch: onOpenProductSearch,
    );
    final cartPanel = PosCartPanel(
      cartState: cartState,
      onSelectProduct: onSelectProduct,
      onIncrementProduct: onIncrementProduct,
      onDecrementProduct: onDecrementProduct,
      onEditQuantity: onEditItemQuantity,
      onRemoveProduct: onRemoveProduct,
      onClearCart: onOpenClearCartDialog,
      showCompactClearInHeader: true,
      showDesktopFooter: false,
      emptyAction: AppButton(
        label: 'Ürün Ara ve Ekle',
        icon: Icons.search_rounded,
        variant: AppButtonVariant.emerald,
        onPressed: onOpenProductSearch,
      ),
    );
    final stickyCheckout = _buildStickyCheckoutBar(context, colors);

    // Ekran klavyesi açıkken viewport < 380px altına düşerse tek kaydırmalı güvenli akış
    if (availableHeight < 380) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            banners,
            toolbar,
            if (cartState.hasNegativeStockItems)
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  MmsSpacing.sm,
                  MmsSpacing.xs,
                  MmsSpacing.sm,
                  0,
                ),
                child: PosNegativeStockWarning(),
              ),
            SizedBox(height: 200, child: cartPanel),
            if (showVirtualNumpad)
              Padding(
                padding: const EdgeInsets.all(MmsSpacing.sm),
                child: VirtualNumpadPanel(
                  onDigitOrChar: onAppendNumpadChar,
                  onBackspace: onBackspaceNumpad,
                  onClear: onClearBarcode,
                  onSubmit: onSubmitBarcode,
                ),
              ),
            stickyCheckout,
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: (availableHeight * 0.32).clamp(96.0, 220.0),
          ),
          child: SingleChildScrollView(child: banners),
        ),
        toolbar,
        if (cartState.hasNegativeStockItems)
          const Padding(
            padding: EdgeInsets.fromLTRB(
              MmsSpacing.sm,
              MmsSpacing.xs,
              MmsSpacing.sm,
              0,
            ),
            child: PosNegativeStockWarning(),
          ),
        Expanded(
          child: showVirtualNumpad
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 4, child: cartPanel),
                    Divider(height: 1, color: colors.border),
                    Flexible(
                      flex: 6,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(MmsSpacing.sm),
                        child: VirtualNumpadPanel(
                          onDigitOrChar: onAppendNumpadChar,
                          onBackspace: onBackspaceNumpad,
                          onClear: onClearBarcode,
                          onSubmit: onSubmitBarcode,
                        ),
                      ),
                    ),
                  ],
                )
              : cartPanel,
        ),
        stickyCheckout,
      ],
    );
  }

  Widget _buildTabletLayout(BuildContext context, MmsColors colors) {
    final cartPanel = PosCartPanel(
      cartState: cartState,
      onSelectProduct: onSelectProduct,
      onIncrementProduct: onIncrementProduct,
      onDecrementProduct: onDecrementProduct,
      onEditQuantity: onEditItemQuantity,
      onRemoveProduct: onRemoveProduct,
      onClearCart: onOpenClearCartDialog,
      emptyAction: AppButton(
        label: 'Ürün Ara ve Ekle',
        icon: Icons.search_rounded,
        variant: AppButtonVariant.emerald,
        onPressed: onOpenProductSearch,
      ),
    );

    return Column(
      children: [
        PosStatusBanners(
          systemStatus: systemStatus,
          syncState: syncState,
          cartState: cartState,
          onRetrySync: onRetrySync,
          onClearMessages: onClearMessages,
          onOpenProductSearch: onOpenProductSearch,
        ),
        _buildMobileToolbar(context, colors, singleRowTablet: true),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 6, child: cartPanel),
              VerticalDivider(width: 1, thickness: 1, color: colors.border),
              Expanded(
                flex: 4,
                child: Container(
                  color: colors.background,
                  padding: const EdgeInsets.all(MmsSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AppBadge(
                                label:
                                    'Bekleyen Outbox: ${systemStatus.outboxSummary.totalUnsynced}',
                                icon: Icons.outbox_rounded,
                                tone: systemStatus.outboxSummary.totalUnsynced > 0
                                    ? AppBadgeTone.warning
                                    : AppBadgeTone.neutral,
                              ),
                              if (cartState.hasNegativeStockItems) ...[
                                const SizedBox(height: MmsSpacing.sm),
                                const PosNegativeStockWarning(),
                              ],
                              if (showVirtualNumpad) ...[
                                const SizedBox(height: MmsSpacing.sm),
                                VirtualNumpadPanel(
                                  onDigitOrChar: onAppendNumpadChar,
                                  onBackspace: onBackspaceNumpad,
                                  onClear: onClearBarcode,
                                  onSubmit: onSubmitBarcode,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: MmsSpacing.sm),
                      _buildTotalCard(context, colors, compact: false),
                      const SizedBox(height: MmsSpacing.sm),
                      _buildTouchPaymentButtons(context, colors),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileToolbar(
    BuildContext context,
    MmsColors colors, {
    bool singleRowTablet = false,
  }) {
    final barcodeField = PosBarcodeTextField(
      controller: barcodeController,
      focusNode: barcodeFocusNode,
      autofocus: false,
      hintText: 'Barkod okutun veya yazın...',
      fontSize: 15,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      minClearButtonSize: 48,
      onSubmitted: onSubmitBarcode,
      onCleared: onClearMessages,
    );

    final addButton = AppButton(
      key: const Key('barcode_add_button'),
      label: 'Ekle',
      icon: Icons.add_rounded,
      variant: AppButtonVariant.emerald,
      minHeight: 48,
      onPressed: onSubmitBarcode,
    );

    final Widget? cameraButton = onOpenCameraScanner == null
        ? null
        : SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              key: const Key('pos_camera_scan_button'),
              onPressed: onOpenCameraScanner,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
              label: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Kamera',
                  maxLines: 1,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(72, 48),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                elevation: 0,
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(MmsRadius.sm),
                ),
              ),
            ),
          );

    final searchButton = AppButton(
      key: const Key('open_product_search_button'),
      label: 'Ürün Ara',
      icon: Icons.search_rounded,
      variant: AppButtonVariant.secondary,
      minHeight: 48,
      expand: !singleRowTablet,
      onPressed: onOpenProductSearch,
    );

    final numpadButton = SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        key: const Key('virtual_numpad_toggle'),
        onPressed: onToggleVirtualNumpad,
        icon: Icon(
          Icons.dialpad_rounded,
          size: 18,
          color: showVirtualNumpad ? colors.successText : colors.textSecondary,
        ),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Numpad',
            maxLines: 1,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: showVirtualNumpad
                  ? colors.successText
                  : colors.textPrimary,
            ),
          ),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(72, 48),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          backgroundColor: showVirtualNumpad
              ? colors.successBg
              : colors.surfaceSubtle,
          side: BorderSide(
            color: showVirtualNumpad ? colors.emerald : colors.borderStrong,
            width: showVirtualNumpad ? 1.5 : 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MmsRadius.sm),
          ),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(MmsSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: singleRowTablet
          ? Row(
              children: [
                Expanded(child: barcodeField),
                const SizedBox(width: MmsSpacing.xs),
                addButton,
                if (cameraButton != null) ...[
                  const SizedBox(width: MmsSpacing.xs),
                  cameraButton,
                ],
                const SizedBox(width: MmsSpacing.xs),
                searchButton,
                const SizedBox(width: MmsSpacing.xs),
                numpadButton,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: barcodeField),
                    const SizedBox(width: MmsSpacing.xs),
                    addButton,
                  ],
                ),
                const SizedBox(height: MmsSpacing.xs),
                Row(
                  children: [
                    if (cameraButton != null) ...[
                      Expanded(child: cameraButton),
                      const SizedBox(width: MmsSpacing.xs),
                    ],
                    Expanded(child: searchButton),
                    const SizedBox(width: MmsSpacing.xs),
                    Expanded(child: numpadButton),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildStickyCheckoutBar(BuildContext context, MmsColors colors) {
    return Container(
      key: const Key('mobile_sticky_checkout_bar'),
      padding: const EdgeInsets.fromLTRB(
        MmsSpacing.sm,
        MmsSpacing.xs,
        MmsSpacing.sm,
        MmsSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.borderStrong, width: 1.2)),
        boxShadow: colors.subtleShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTotalCard(context, colors, compact: true),
          const SizedBox(height: MmsSpacing.xs),
          _buildTouchPaymentButtons(context, colors),
        ],
      ),
    );
  }

  Widget _buildTotalCard(
    BuildContext context,
    MmsColors colors, {
    required bool compact,
  }) {
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Ödenecek Toplam (${cartState.lineCount} kalem)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                  if (systemStatus.outboxSummary.totalUnsynced > 0)
                    Text(
                      'Bekleyen Outbox: ${systemStatus.outboxSummary.totalUnsynced}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: colors.warningText,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: MmsSpacing.xs),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  Money.formatCents(cartState.totalCents),
                  key: const Key('pos_grand_total'),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                    color: colors.textPrimary,
                    fontFeatures: MmsTypography.tabularFigures,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(MmsSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(MmsRadius.lg),
        border: Border.all(color: colors.primary, width: 1.8),
        boxShadow: colors.subtleShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: MmsSpacing.xs,
            runSpacing: 2,
            children: [
              Text(
                'Ara Toplam (${cartState.lineCount} kalem)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary,
                ),
              ),
              Text(
                'ÖDENECEK TOPLAM TUTAR',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: colors.emerald,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                Money.formatCents(cartState.totalCents),
                key: const Key('pos_grand_total'),
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                  color: colors.textPrimary,
                  fontFeatures: MmsTypography.tabularFigures,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTouchPaymentButtons(BuildContext context, MmsColors colors) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            key: const Key('cash_pay_button'),
            onPressed: cartState.canCheckout
                ? () => onOpenPaymentDialog(PaymentMethod.cash)
                : null,
            icon: const Icon(Icons.payments_outlined, size: 20),
            label: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'NAKİT',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(100, 56),
              backgroundColor: colors.emerald,
              foregroundColor: colors.onEmerald,
              disabledBackgroundColor: colors.neutralBg,
              disabledForegroundColor: colors.textTertiary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(MmsRadius.md),
              ),
            ),
          ),
        ),
        const SizedBox(width: MmsSpacing.xs),
        Expanded(
          child: ElevatedButton(
            key: const Key('card_pay_button'),
            onPressed: cartState.canCheckout
                ? () => onOpenPaymentDialog(PaymentMethod.card)
                : null,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(100, 56),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              backgroundColor: colors.primary,
              foregroundColor: colors.onPrimary,
              disabledBackgroundColor: colors.neutralBg,
              disabledForegroundColor: colors.textTertiary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(MmsRadius.md),
              ),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'KREDİ KARTI',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Elle Giriş', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
