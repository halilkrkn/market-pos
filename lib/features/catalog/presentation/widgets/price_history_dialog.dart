import 'package:flutter/material.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../pos/domain/money.dart';

class PriceHistoryDialog extends StatelessWidget {
  final String productName;
  final List<LocalPriceHistoryData> history;

  const PriceHistoryDialog({
    super.key,
    required this.productName,
    required this.history,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;

    return AppDialog(
      title: 'Fiyat Değişiklik Geçmişi',
      subtitle: productName,
      icon: Icons.history_rounded,
      iconColor: colors.emerald,
      maxWidth: 600,
      maxHeight: 560,
      content: history.isEmpty
          ? const AppEmptyState(
              icon: Icons.history_rounded,
              title: 'Kayıtlı fiyat geçmişi bulunamadı.',
            )
          : ListView.separated(
              shrinkWrap: true,
              itemCount: history.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: colors.border),
              itemBuilder: (context, index) {
                final record = history[index];
                final isFirstRecord =
                    index == history.length - 1 && record.oldPrice == 0;
                final isIncrease = record.newPrice > record.oldPrice;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: MmsSpacing.sm),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isFirstRecord
                              ? colors.surfaceSubtle
                              : (isIncrease
                                    ? colors.dangerBg
                                    : colors.successBg),
                          borderRadius: BorderRadius.circular(MmsRadius.sm),
                        ),
                        child: Icon(
                          isFirstRecord
                              ? Icons.add_rounded
                              : (isIncrease
                                    ? Icons.trending_up_rounded
                                    : Icons.trending_down_rounded),
                          size: 18,
                          color: isFirstRecord
                              ? colors.textSecondary
                              : (isIncrease
                                    ? colors.dangerText
                                    : colors.successText),
                        ),
                      ),
                      const SizedBox(width: MmsSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: MmsSpacing.xs,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (record.oldPrice > 0) ...[
                                  Text(
                                    Money.formatCents(record.oldPrice),
                                    style: TextStyle(
                                      fontSize: 13,
                                      decoration: TextDecoration.lineThrough,
                                      color: colors.textTertiary,
                                      fontFeatures:
                                          MmsTypography.tabularFigures,
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 14,
                                    color: colors.textTertiary,
                                  ),
                                ],
                                Text(
                                  Money.formatCents(record.newPrice),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: colors.emerald,
                                    fontFeatures: MmsTypography.tabularFigures,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Tarih: ${record.changedAt.toFormattedDateTime()} | Sürüm: ${record.priceVersionId}',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colors.textSecondary,
                                fontFeatures: MmsTypography.tabularFigures,
                              ),
                            ),
                            if (record.reason != null &&
                                record.reason!.isNotEmpty)
                              Text(
                                'Gerekçe: ${record.reason}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontStyle: FontStyle.italic,
                                  color: colors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: MmsSpacing.xs),
                      AppBadge(
                        label: record.source,
                        tone: AppBadgeTone.neutral,
                        compact: true,
                      ),
                    ],
                  ),
                );
              },
            ),
      actions: [
        AppButton(
          label: 'Kapat',
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
