import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../domain/cart_item.dart';
import '../../domain/money.dart';

/// POS sepet tablosundaki tekil ürün satırı (`>= 48x48 dp` dokunmatik kontroller, Light/Dark uyumlu).
class CartItemRow extends StatelessWidget {
  final int index;
  final CartItem item;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onEditQuantity;
  final VoidCallback onRemove;

  const CartItemRow({
    super.key,
    required this.index,
    required this.item,
    required this.isSelected,
    required this.onSelect,
    required this.onIncrement,
    required this.onDecrement,
    required this.onEditQuantity,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    final hasNegativeStockWarning =
        item.isCurrentStockNonPositive || item.isNegativeStockAfterCart;
    final rowBg = isSelected ? colors.successBg : colors.surface;

    return InkWell(
      key: Key('cart_row_${item.productId}'),
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: MmsSpacing.md,
          vertical: MmsSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: rowBg,
          border: Border(
            left: BorderSide(
              color: isSelected ? colors.emerald : Colors.transparent,
              width: 4,
            ),
            bottom: BorderSide(color: colors.border),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final indexBadge = SizedBox(
              width: 32,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: colors.textTertiary,
                  fontFeatures: MmsTypography.tabularFigures,
                ),
              ),
            );

            final productDetails = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.productName,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: MmsSpacing.xs,
                  runSpacing: MmsSpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (item.barcode != null && item.barcode!.isNotEmpty)
                      Text(
                        item.barcode!,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                          fontFeatures: MmsTypography.tabularFigures,
                        ),
                      ),
                    Text(
                      '${Money.formatCents(item.unitPriceCents)} / ${item.pricingUnit}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                        fontFeatures: MmsTypography.tabularFigures,
                      ),
                    ),
                    if (hasNegativeStockWarning)
                      AppBadge(
                        label:
                            'Eksi Stok (allow): kalan ${Money.formatMilliWithUnit(item.projectedRemainingStockMilli, item.stockUnit)}',
                        tone: AppBadgeTone.warning,
                        compact: true,
                      ),
                  ],
                ),
              ],
            );

            // Miktar kontrolleri (>= 48x48 dp)
            final quantityControls = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  key: Key('qty_minus_${item.productId}'),
                  onPressed: onDecrement,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    fixedSize: const Size(48, 48),
                    padding: EdgeInsets.zero,
                    backgroundColor: colors.surface,
                  ),
                  child: const Text(
                    '-',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  key: Key('qty_value_${item.productId}'),
                  onTap: onEditQuantity,
                  borderRadius: BorderRadius.circular(MmsRadius.sm),
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 72,
                      minHeight: 48,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(MmsRadius.sm),
                      border: Border.all(color: colors.borderStrong),
                    ),
                    child: Text(
                      Money.formatMilliWithUnit(
                        item.quantityMilli,
                        item.pricingUnit,
                      ),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                        fontFeatures: MmsTypography.tabularFigures,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                OutlinedButton(
                  key: Key('qty_plus_${item.productId}'),
                  onPressed: onIncrement,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    fixedSize: const Size(48, 48),
                    padding: EdgeInsets.zero,
                    backgroundColor: colors.surface,
                  ),
                  child: const Text(
                    '+',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );

            final lineTotalText = SizedBox(
              width: 112,
              child: Text(
                Money.formatCents(item.lineTotalCents),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                  fontFeatures: MmsTypography.tabularFigures,
                ),
              ),
            );

            final removeButton = IconButton(
              key: Key('remove_item_${item.productId}'),
              tooltip: 'Satırı Sil',
              onPressed: onRemove,
              style: IconButton.styleFrom(
                minimumSize: const Size(48, 48),
                fixedSize: const Size(48, 48),
                foregroundColor: colors.dangerText,
                backgroundColor: colors.dangerBg,
              ),
              icon: const Icon(Icons.delete_outline_rounded, size: 22),
            );

            if (constraints.maxWidth >= 560) {
              return Row(
                children: [
                  indexBadge,
                  Expanded(flex: 4, child: productDetails),
                  const SizedBox(width: MmsSpacing.xs),
                  quantityControls,
                  const SizedBox(width: MmsSpacing.sm),
                  lineTotalText,
                  const SizedBox(width: MmsSpacing.xs),
                  removeButton,
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: indexBadge,
                    ),
                    Expanded(child: productDetails),
                    const SizedBox(width: MmsSpacing.xs),
                    removeButton,
                  ],
                ),
                const SizedBox(height: MmsSpacing.xs),
                Wrap(
                  spacing: MmsSpacing.xs,
                  runSpacing: MmsSpacing.xs,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [quantityControls, lineTotalText],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
