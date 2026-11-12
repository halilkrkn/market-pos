import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/cart_item.dart';
import '../../domain/money.dart';

/// POS sepet tablosundaki tekil ürün satırı (`>= 48x48 dp` dokunmatik kontroller).
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
    final hasNegativeStockWarning =
        item.isCurrentStockNonPositive || item.isNegativeStockAfterCart;
    final rowBg = isSelected ? AppTheme.posInfoBg : AppTheme.cardBgLight;

    return InkWell(
      key: Key('cart_row_${item.productId}'),
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: rowBg,
          border: Border(
            left: BorderSide(
              color: isSelected ? AppTheme.primaryBlue : Colors.transparent,
              width: 4,
            ),
            bottom: const BorderSide(color: AppTheme.borderSubtle),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final indexBadge = SizedBox(
              width: 32,
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMutedLight,
                  fontFeatures: AppTheme.tabularFiguresFeature,
                ),
              ),
            );

            final productDetails = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.productName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMainLight,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (item.barcode != null && item.barcode!.isNotEmpty)
                      Text(
                        item.barcode!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMutedLight,
                          fontFeatures: AppTheme.tabularFiguresFeature,
                        ),
                      ),
                    Text(
                      '${Money.formatCents(item.unitPriceCents)} / ${item.pricingUnit}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textMutedLight,
                        fontFeatures: AppTheme.tabularFiguresFeature,
                      ),
                    ),
                    if (hasNegativeStockWarning)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.posWarningBg,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: AppTheme.statusWarning.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          'Eksi Stok (allow): kalan ${Money.formatMilliWithUnit(item.projectedRemainingStockMilli, item.stockUnit)}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.posWarningText,
                            fontFeatures: AppTheme.tabularFiguresFeature,
                          ),
                        ),
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
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 72, minHeight: 48),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.borderSubtle),
                    ),
                    child: Text(
                      Money.formatMilliWithUnit(
                        item.quantityMilli,
                        item.pricingUnit,
                      ),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMainLight,
                        fontFeatures: AppTheme.tabularFiguresFeature,
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
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textMainLight,
                  fontFeatures: AppTheme.tabularFiguresFeature,
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
                foregroundColor: AppTheme.posDangerText,
                backgroundColor: AppTheme.posDangerBg,
              ),
              icon: const Icon(Icons.delete_outline, size: 22),
            );

            if (constraints.maxWidth >= 560) {
              return Row(
                children: [
                  indexBadge,
                  Expanded(
                    flex: 4,
                    child: productDetails,
                  ),
                  const SizedBox(width: 8),
                  quantityControls,
                  const SizedBox(width: 12),
                  lineTotalText,
                  const SizedBox(width: 8),
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
                    const SizedBox(width: 8),
                    removeButton,
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    quantityControls,
                    lineTotalText,
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

