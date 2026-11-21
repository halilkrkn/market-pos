import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// Windows Masaüstü POS görünümü (USB HID barkod odağı, F1/F2/F9/F10/Esc kısayolları ve 60/40 panel).
class DesktopPosView extends StatelessWidget {
  final TextEditingController barcodeController;
  final FocusNode barcodeFocusNode;
  final bool enableBarcodeAutofocus;
  final CartState cartState;
  final bool showVirtualNumpad;
  final SystemStatus systemStatus;
  final SyncCoordinatorState? syncState;
  final VoidCallback onSubmitBarcode;
  final ValueChanged<String> onAppendNumpadChar;
  final VoidCallback onBackspaceNumpad;
  final VoidCallback onClearBarcode;
  final VoidCallback onToggleVirtualNumpad;
  final VoidCallback onOpenProductSearch;
  final VoidCallback onOpenHelpDialog;
  final VoidCallback onOpenDefaultQuantityDialog;
  final ValueChanged<CartItem> onEditItemQuantity;
  final VoidCallback onOpenClearCartDialog;
  final ValueChanged<PaymentMethod> onOpenPaymentDialog;
  final VoidCallback onHandleEscape;
  final VoidCallback onRetrySync;
  final VoidCallback onClearMessages;
  final ValueChanged<String> onSelectProduct;
  final ValueChanged<String> onIncrementProduct;
  final ValueChanged<String> onDecrementProduct;
  final ValueChanged<String> onRemoveProduct;

  const DesktopPosView({
    super.key,
    required this.barcodeController,
    required this.barcodeFocusNode,
    required this.enableBarcodeAutofocus,
    required this.cartState,
    required this.showVirtualNumpad,
    required this.systemStatus,
    this.syncState,
    required this.onSubmitBarcode,
    required this.onAppendNumpadChar,
    required this.onBackspaceNumpad,
    required this.onClearBarcode,
    required this.onToggleVirtualNumpad,
    required this.onOpenProductSearch,
    required this.onOpenHelpDialog,
    required this.onOpenDefaultQuantityDialog,
    required this.onEditItemQuantity,
    required this.onOpenClearCartDialog,
    required this.onOpenPaymentDialog,
    required this.onHandleEscape,
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

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f1): onOpenHelpDialog,
        const SingleActivator(LogicalKeyboardKey.f2):
            onOpenDefaultQuantityDialog,
        const SingleActivator(LogicalKeyboardKey.f9): () =>
            onOpenPaymentDialog(PaymentMethod.card),
        const SingleActivator(LogicalKeyboardKey.f10): () =>
            onOpenPaymentDialog(PaymentMethod.cash),
        const SingleActivator(LogicalKeyboardKey.escape): onHandleEscape,
      },
      child: Column(
        children: [
          PosStatusBanners(
            systemStatus: systemStatus,
            syncState: syncState,
            cartState: cartState,
            onRetrySync: onRetrySync,
            onClearMessages: onClearMessages,
            onOpenProductSearch: onOpenProductSearch,
          ),
          _buildBarcodeToolbar(context),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cartPanel = PosCartPanel(
                  cartState: cartState,
                  onSelectProduct: onSelectProduct,
                  onIncrementProduct: onIncrementProduct,
                  onDecrementProduct: onDecrementProduct,
                  onEditQuantity: onEditItemQuantity,
                  onRemoveProduct: onRemoveProduct,
                  onClearCart: onOpenClearCartDialog,
                );

                final isWide = constraints.maxWidth >= 880;
                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 6, child: cartPanel),
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: colors.border,
                      ),
                      Expanded(
                        flex: 4,
                        child: _buildActionPanel(context, embedScrollable: false),
                      ),
                    ],
                  );
                }

                // Dar masaüstü penceresi (600–879px): taşmasız dikey akış
                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: 320, child: cartPanel),
                      Divider(height: 1, color: colors.border),
                      _buildActionPanel(context, embedScrollable: true),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarcodeToolbar(BuildContext context) {
    final colors = context.mmsColors;

    final barcodeField = PosBarcodeTextField(
      controller: barcodeController,
      focusNode: barcodeFocusNode,
      autofocus: enableBarcodeAutofocus,
      hintText: 'Barkod okutun veya yazıp Enter tuşuna basın...',
      fontSize: 15.5,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      minClearButtonSize: 44,
      onSubmitted: onSubmitBarcode,
      onCleared: onClearMessages,
    );

    final addButton = AppButton(
      key: const Key('barcode_add_button'),
      label: 'Ekle',
      icon: Icons.add_rounded,
      variant: AppButtonVariant.emerald,
      onPressed: onSubmitBarcode,
    );

    final searchButton = AppButton(
      key: const Key('open_product_search_button'),
      label: 'Ürün Ara',
      icon: Icons.search_rounded,
      variant: AppButtonVariant.secondary,
      onPressed: onOpenProductSearch,
    );

    final numpadToggle = InkWell(
      key: const Key('virtual_numpad_toggle'),
      onTap: onToggleVirtualNumpad,
      borderRadius: BorderRadius.circular(MmsRadius.sm),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: showVirtualNumpad ? colors.successBg : colors.surfaceSubtle,
          borderRadius: BorderRadius.circular(MmsRadius.sm),
          border: Border.all(
            color: showVirtualNumpad ? colors.emerald : colors.borderStrong,
            width: showVirtualNumpad ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dialpad_rounded,
              size: 18,
              color: showVirtualNumpad
                  ? colors.successText
                  : colors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              'Sanal Numpad',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: showVirtualNumpad
                    ? colors.successText
                    : colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MmsSpacing.md,
        vertical: MmsSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 760) {
            return Row(
              children: [
                Expanded(child: barcodeField),
                const SizedBox(width: MmsSpacing.xs),
                addButton,
                const SizedBox(width: MmsSpacing.xs),
                searchButton,
                const SizedBox(width: MmsSpacing.xs),
                numpadToggle,
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              barcodeField,
              const SizedBox(height: MmsSpacing.xs),
              Wrap(
                spacing: MmsSpacing.xs,
                runSpacing: MmsSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [addButton, searchButton, numpadToggle],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActionPanel(
    BuildContext context, {
    required bool embedScrollable,
  }) {
    final colors = context.mmsColors;

    final topSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: MmsSpacing.xs,
          runSpacing: MmsSpacing.xs,
          children: [
            AppBadge(
              label: 'Bekleyen Outbox: ${systemStatus.pendingOutboxCount}',
              icon: Icons.outbox_rounded,
              tone: systemStatus.pendingOutboxCount > 0
                  ? AppBadgeTone.warning
                  : AppBadgeTone.neutral,
            ),
            OutlinedButton.icon(
              key: const Key('help_button'),
              onPressed: onOpenHelpDialog,
              icon: const Icon(Icons.help_outline_rounded, size: 18),
              label: const Text('Yardım [F1]'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(120, 48)),
            ),
          ],
        ),
        const SizedBox(height: MmsSpacing.sm),
        if (cartState.hasNegativeStockItems) ...[
          const PosNegativeStockWarning(),
          const SizedBox(height: MmsSpacing.sm),
        ],
        if (showVirtualNumpad) ...[
          VirtualNumpadPanel(
            onDigitOrChar: onAppendNumpadChar,
            onBackspace: onBackspaceNumpad,
            onClear: onClearBarcode,
            onSubmit: onSubmitBarcode,
          ),
          const SizedBox(height: MmsSpacing.sm),
        ],
      ],
    );

    return Container(
      color: colors.background,
      padding: const EdgeInsets.all(MmsSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (embedScrollable)
            topSection
          else
            Expanded(child: SingleChildScrollView(child: topSection)),
          const SizedBox(height: MmsSpacing.sm),

          // Toplam Ödenecek Tutar Kartı
          Container(
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
                        fontSize: 38,
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
          ),
          const SizedBox(height: MmsSpacing.sm),

          // Birincil Tahsilat Butonları (>=64dp Fitts yasası)
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  key: const Key('cash_pay_button'),
                  onPressed: cartState.canCheckout
                      ? () => onOpenPaymentDialog(PaymentMethod.cash)
                      : null,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(110, 64),
                    backgroundColor: colors.emerald,
                    foregroundColor: colors.onEmerald,
                    disabledBackgroundColor: colors.neutralBg,
                    disabledForegroundColor: colors.textTertiary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(MmsRadius.md),
                    ),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'NAKİT',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text('[F10]', style: TextStyle(fontSize: 11.5)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: MmsSpacing.sm),
              Expanded(
                child: ElevatedButton(
                  key: const Key('card_pay_button'),
                  onPressed: cartState.canCheckout
                      ? () => onOpenPaymentDialog(PaymentMethod.card)
                      : null,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(100, 64),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
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
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '[F9 • Elle Giriş]',
                          style: TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
