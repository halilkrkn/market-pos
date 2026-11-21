import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/user_friendly_error_mapper.dart';
import '../../../diagnostics/domain/system_status.dart';
import '../../../sync/domain/sync_coordinator_state.dart';
import '../../domain/cart_item.dart';
import '../../domain/cart_state.dart';
import 'cart_item_row.dart';

/// POS çevrimdışı durum, hata ve başarı şeritleri (Masaüstü ve Mobil ortak).
class PosStatusBanners extends StatelessWidget {
  final SystemStatus systemStatus;
  final SyncCoordinatorState? syncState;
  final CartState cartState;
  final VoidCallback onRetrySync;
  final VoidCallback onClearMessages;
  final VoidCallback? onOpenProductSearch;

  const PosStatusBanners({
    super.key,
    required this.systemStatus,
    this.syncState,
    required this.cartState,
    required this.onRetrySync,
    required this.onClearMessages,
    this.onOpenProductSearch,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    final showSearchFallback =
        cartState.errorMessage != null &&
        onOpenProductSearch != null &&
        cartState.errorMessage!.contains('bulunamadı');
    final failedPermanent = systemStatus.outboxSummary.failedPermanent;
    final hasPermanentSyncError =
        failedPermanent > 0 ||
        (syncState?.status == SyncCoordinatorStatus.permanentError);
    final String? syncAlertText = hasPermanentSyncError
        ? UserFriendlyErrorMapper.map(
            syncState?.errorMessage ??
                'Senkronizasyon kuyruğunda ${failedPermanent > 0 ? failedPermanent : 1} hatalı işlem bekliyor.',
            fallback: 'Senkronizasyon kuyruğunda kalıcı hata bulunuyor.',
          )
        : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (systemStatus.backendState == BackendConnectionState.offline)
          AppOfflineIndicator(
            pendingCount: systemStatus.pendingOutboxCount,
            failedCount: systemStatus.outboxSummary.failedPermanent,
            retryCount: systemStatus.outboxSummary.retry,
            onRetrySync: onRetrySync,
          ),
        if (syncAlertText != null)
          _FeedbackStrip(
            key: const Key('pos_sync_error_banner'),
            message: syncAlertText,
            bgColor: colors.dangerBg,
            borderColor: colors.danger,
            textColor: colors.dangerText,
            icon: Icons.sync_problem_rounded,
            action: OutlinedButton.icon(
              key: const Key('pos_sync_retry_button'),
              onPressed: onRetrySync,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(88, 48),
                foregroundColor: colors.dangerText,
                side: BorderSide(color: colors.danger),
                backgroundColor: colors.surface,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              icon: const Icon(Icons.sync_rounded, size: 17),
              label: const Text(
                'Tekrar Dene',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            onClose: onClearMessages,
          ),
        if (cartState.errorMessage != null)
          _FeedbackStrip(
            message: cartState.errorMessage!,
            bgColor: colors.dangerBg,
            borderColor: colors.danger,
            textColor: colors.dangerText,
            icon: Icons.error_outline_rounded,
            action: showSearchFallback
                ? OutlinedButton.icon(
                    key: const Key('error_banner_search_button'),
                    onPressed: onOpenProductSearch,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(88, 48),
                      foregroundColor: colors.dangerText,
                      side: BorderSide(color: colors.danger),
                      backgroundColor: colors.surface,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    icon: const Icon(Icons.search_rounded, size: 17),
                    label: const Text(
                      'Ürün Ara',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  )
                : null,
            onClose: onClearMessages,
          ),
        if (cartState.infoMessage != null)
          _FeedbackStrip(
            message: cartState.infoMessage!,
            bgColor: colors.successBg,
            borderColor: colors.emerald,
            textColor: colors.successText,
            icon: Icons.check_circle_outline_rounded,
            onClose: onClearMessages,
          ),
      ],
    );
  }
}

class _FeedbackStrip extends StatelessWidget {
  final String message;
  final Color bgColor;
  final Color borderColor;
  final Color textColor;
  final IconData icon;
  final Widget? action;
  final VoidCallback onClose;

  const _FeedbackStrip({
    super.key,
    required this.message,
    required this.bgColor,
    required this.borderColor,
    required this.textColor,
    required this.icon,
    this.action,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: MmsSpacing.md,
        vertical: MmsSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(bottom: BorderSide(color: borderColor, width: 1.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 20),
          const SizedBox(width: MmsSpacing.xs),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: MmsSpacing.xs),
            action!,
          ],
          IconButton(
            tooltip: 'Kapat',
            onPressed: onClose,
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: textColor,
            ),
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

/// Masaüstü ve mobil görünümler için ortak barkod giriş kutusu (`Key('barcode_input_field')`).
class PosBarcodeTextField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool autofocus;
  final String hintText;
  final double fontSize;
  final EdgeInsetsGeometry contentPadding;
  final double minClearButtonSize;
  final VoidCallback onSubmitted;
  final VoidCallback? onCleared;

  const PosBarcodeTextField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.autofocus,
    required this.hintText,
    required this.fontSize,
    required this.contentPadding,
    this.minClearButtonSize = 44,
    required this.onSubmitted,
    this.onCleared,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final hasText = value.text.isNotEmpty;
        return TextField(
          key: const Key('barcode_input_field'),
          controller: controller,
          focusNode: focusNode,
          autofocus: autofocus,
          textInputAction: TextInputAction.done,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
            fontFeatures: MmsTypography.tabularFigures,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: Icon(
              Icons.qr_code_scanner_rounded,
              color: colors.emerald,
            ),
            suffixIcon: hasText
                ? IconButton(
                    key: const Key('barcode_clear_button'),
                    tooltip: 'Barkod Alanını Temizle',
                    onPressed: () {
                      controller.clear();
                      onCleared?.call();
                    },
                    style: IconButton.styleFrom(
                      minimumSize: Size(minClearButtonSize, minClearButtonSize),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  )
                : null,
            contentPadding: contentPadding,
          ),
          onSubmitted: (_) => onSubmitted(),
        );
      },
    );
  }
}

/// Eksi stok politika uyarı kutusu (Masaüstü ve Mobil ortak).
class PosNegativeStockWarning extends StatelessWidget {
  const PosNegativeStockWarning({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;

    return Container(
      padding: const EdgeInsets.all(MmsSpacing.sm),
      decoration: BoxDecoration(
        color: colors.warningBg,
        borderRadius: BorderRadius.circular(MmsRadius.sm),
        border: Border.all(color: colors.warning),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: colors.warningText),
          const SizedBox(width: MmsSpacing.xs),
          Expanded(
            child: Text(
              'Eksi stok uyarısı (allow): Satış engellenmez ancak stok eksiye düşecektir.',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: colors.warningText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Masaüstü ve mobil POS görünümlerince paylaşılan sepet listesi paneli.
class PosCartPanel extends StatelessWidget {
  final CartState cartState;
  final ValueChanged<String> onSelectProduct;
  final ValueChanged<String> onIncrementProduct;
  final ValueChanged<String> onDecrementProduct;
  final ValueChanged<CartItem> onEditQuantity;
  final ValueChanged<String> onRemoveProduct;
  final VoidCallback onClearCart;
  final bool showCompactClearInHeader;
  final bool showDesktopFooter;
  final Widget? emptyAction;

  const PosCartPanel({
    super.key,
    required this.cartState,
    required this.onSelectProduct,
    required this.onIncrementProduct,
    required this.onDecrementProduct,
    required this.onEditQuantity,
    required this.onRemoveProduct,
    required this.onClearCart,
    this.showCompactClearInHeader = false,
    this.showDesktopFooter = true,
    this.emptyAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;

    return Container(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: MmsSpacing.md,
              vertical: MmsSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: colors.surfaceSubtle,
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 560) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 32,
                          child: Text(
                            '#',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: Text(
                            'Ürün & Birim Fiyat',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                        Text(
                          'Miktar',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 96),
                        SizedBox(
                          width: 112,
                          child: Text(
                            'Tutar',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 56),
                      ],
                    ),
                  );
                }

                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        showCompactClearInHeader
                            ? 'Sepet (${cartState.lineCount} kalem)'
                            : 'Sepet Kalemleri',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    if (showCompactClearInHeader && !cartState.isEmpty)
                      TextButton.icon(
                        key: const Key('clear_cart_button'),
                        onPressed: onClearCart,
                        style: TextButton.styleFrom(
                          foregroundColor: colors.dangerText,
                          minimumSize: const Size(88, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        icon: const Icon(Icons.clear_all_rounded, size: 18),
                        label: const Text(
                          'Temizle',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      )
                    else
                      Text(
                        'Tutar',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          Expanded(
            child: cartState.isEmpty
                ? AppEmptyState(
                    icon: Icons.shopping_cart_outlined,
                    title:
                        'Sepet boş. Barkod okutun veya "Ürün Ara" ile ürün ekleyin.',
                    action: emptyAction,
                  )
                : ListView.builder(
                    itemCount: cartState.items.length,
                    itemBuilder: (context, index) {
                      final item = cartState.items[index];
                      return RepaintBoundary(
                        key: ValueKey('cart_row_${item.productId}'),
                        child: CartItemRow(
                          index: index,
                          item: item,
                          isSelected: cartState.selectedItem?.productId ==
                              item.productId,
                          onSelect: () => onSelectProduct(item.productId),
                          onIncrement: () => onIncrementProduct(item.productId),
                          onDecrement: () => onDecrementProduct(item.productId),
                          onEditQuantity: () => onEditQuantity(item),
                          onRemove: () => onRemoveProduct(item.productId),
                        ),
                      );
                    },
                  ),
          ),
          if (showDesktopFooter)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: MmsSpacing.md,
                vertical: MmsSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceSubtle,
                border: Border(top: BorderSide(color: colors.border)),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: MmsSpacing.xs,
                runSpacing: MmsSpacing.xs,
                children: [
                  Text(
                    'Toplam: ${cartState.lineCount} Kalem',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                      fontFeatures: MmsTypography.tabularFigures,
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const Key('clear_cart_button'),
                    onPressed: cartState.isEmpty ? null : onClearCart,
                    icon: const Icon(Icons.clear_all_rounded, size: 18),
                    label: const Text('Sepeti Temizle'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.dangerText,
                      side: BorderSide(
                        color: cartState.isEmpty
                            ? colors.border
                            : colors.danger.withValues(alpha: 0.5),
                      ),
                      minimumSize: const Size(136, 48),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
