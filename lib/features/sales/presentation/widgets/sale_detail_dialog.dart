import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../pos/domain/money.dart';
import '../../sales_providers.dart';
import 'cancel_sale_dialog.dart';
import 'refund_sale_dialog.dart';
import 'sale_status_badge.dart';

class SaleDetailDialog extends ConsumerWidget {
  final String saleId;

  const SaleDetailDialog({
    super.key,
    required this.saleId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(salesHistoryProvider);
    final detail = state.selectedSaleDetail;
    final colors = context.mmsColors;

    if (detail == null || detail.sale.id != saleId) {
      return const Dialog(
        child: Padding(
          padding: EdgeInsets.all(MmsSpacing.xl),
          child: AppLoadingState(message: 'Fiş detayları yükleniyor...'),
        ),
      );
    }

    final sale = detail.sale;
    final formattedDate =
        sale.createdAt.toFormattedDateTime(includeSeconds: true);

    final isCancelled = sale.status == 'CANCELLED';
    final isRefunded = sale.status == 'REFUNDED';
    final hasReturnableItems =
        detail.items.any((i) => detail.returnableQuantityFor(i) > 0);

    return AppDialog(
      title: 'Fiş Detayı: ${sale.id}',
      subtitle: 'Tarih: $formattedDate | Kasa: ${sale.deviceId}',
      icon: Icons.receipt_long_rounded,
      iconColor: colors.emerald,
      maxWidth: 780,
      maxHeight: 820,
      onClose: () {
        ref.read(salesHistoryProvider.notifier).clearSelectedSale();
        Navigator.of(context).pop();
      },
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Satış Kalemleri',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                SaleStatusBadge.fromDetails(detail),
              ],
            ),
            const SizedBox(height: MmsSpacing.xs),
            Container(
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(MmsRadius.md),
              ),
              clipBehavior: Clip.antiAlias,
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(4),
                  1: FlexColumnWidth(2),
                  2: FlexColumnWidth(2),
                  3: FlexColumnWidth(2),
                },
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: colors.surfaceSubtle),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          'Ürün Adı',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          'Miktar',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          'Birim Fiyat',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          'Tutar',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  ...detail.items.map((item) {
                    final returnable = detail.returnableQuantityFor(item);
                    return TableRow(
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: colors.border)),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.productNameSnapshot,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textPrimary,
                                ),
                              ),
                              if (returnable < item.quantity)
                                Text(
                                  'Kalan iade: ${Money.formatMilliWithUnit(returnable, item.unitSnapshot)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.warningText,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            Money.formatMilliWithUnit(
                              item.quantity,
                              item.unitSnapshot,
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.textPrimary,
                              fontFeatures: MmsTypography.tabularFigures,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            Money.formatCents(item.unitPrice),
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.textPrimary,
                              fontFeatures: MmsTypography.tabularFigures,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            Money.formatCents(item.totalPrice),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                              fontFeatures: MmsTypography.tabularFigures,
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),

            // İptal Bilgisi
            if (isCancelled && sale.cancelReason != null) ...[
              const SizedBox(height: MmsSpacing.md),
              Container(
                padding: const EdgeInsets.all(MmsSpacing.sm),
                decoration: BoxDecoration(
                  color: colors.dangerBg,
                  borderRadius: BorderRadius.circular(MmsRadius.sm),
                  border:
                      Border.all(color: colors.danger.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: colors.dangerText,
                      size: 20,
                    ),
                    const SizedBox(width: MmsSpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'İptal Nedeni: ${sale.cancelReason}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: colors.dangerText,
                            ),
                          ),
                          if (sale.cancelledAt != null)
                            Text(
                              'İptal Zamanı: ${sale.cancelledAt!.toFormattedDateTime(includeSeconds: true)}',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colors.dangerText,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Yapılan İadeler
            if (detail.refunds.isNotEmpty) ...[
              const SizedBox(height: MmsSpacing.md),
              Text(
                'Yapılan İadeler',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: MmsSpacing.xs),
              ...detail.refunds.map((refundRec) {
                return Container(
                  margin: const EdgeInsets.only(bottom: MmsSpacing.xs),
                  padding: const EdgeInsets.all(MmsSpacing.sm),
                  decoration: BoxDecoration(
                    color: colors.warningBg,
                    borderRadius: BorderRadius.circular(MmsRadius.sm),
                    border: Border.all(
                      color: colors.warning.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'İade ID: ${refundRec.refund.id} | ${refundRec.refund.createdAt.toFormattedDateTime()}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: colors.warningText,
                              ),
                            ),
                          ),
                          const SizedBox(width: MmsSpacing.xs),
                          Text(
                            '-${Money.formatCents(refundRec.refund.totalRefundAmount)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: colors.dangerText,
                              fontFeatures: MmsTypography.tabularFigures,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Gerekçe: ${refundRec.refund.reason}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...refundRec.items.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(left: 8, top: 2),
                          child: Text(
                            '• Miktar: ${item.quantity / 1000} | Kondisyon: ${item.productCondition == 'SELLABLE' ? 'Tekrar Satılabilir' : 'Hasarlı (Fire)'} | İade: ${Money.formatCents(item.refundAmount)}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: colors.textPrimary,
                              fontFeatures: MmsTypography.tabularFigures,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],

            const SizedBox(height: MmsSpacing.md),

            // Finansal Özet
            Container(
              padding: const EdgeInsets.all(MmsSpacing.md),
              decoration: BoxDecoration(
                color: colors.surfaceSubtle,
                borderRadius: BorderRadius.circular(MmsRadius.md),
                border: Border.all(color: colors.border),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceAround,
                spacing: MmsSpacing.lg,
                runSpacing: MmsSpacing.sm,
                children: [
                  _summaryColumn(
                    context,
                    'Ödeme Yöntemi',
                    sale.paymentMethod == 'CARD' ? 'Kredi Kartı' : 'Nakit',
                  ),
                  _summaryColumn(
                    context,
                    'Brüt Satış',
                    Money.formatCents(sale.totalAmount),
                  ),
                  _summaryColumn(
                    context,
                    'Toplam İade',
                    Money.formatCents(detail.totalRefundedAmount),
                    valueColor: colors.dangerText,
                  ),
                  _summaryColumn(
                    context,
                    'Net Tutar',
                    Money.formatCents(detail.netAmount),
                    valueColor: colors.emerald,
                    large: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (!isCancelled)
          ElevatedButton.icon(
            onPressed: () async {
              final cancelled = await showDialog<bool>(
                context: context,
                builder: (_) => CancelSaleDialog(
                  saleId: sale.id,
                  totalAmount: sale.totalAmount,
                ),
              );
              if (cancelled == true && context.mounted) {
                ref.read(salesHistoryProvider.notifier).selectSale(sale.id);
              }
            },
            icon: const Icon(Icons.cancel_outlined, size: 18),
            label: const Text('Satışı İptal Et'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.dangerBg,
              foregroundColor: colors.dangerText,
              elevation: 0,
              minimumSize: const Size(140, 46),
            ),
          ),
        if (!isCancelled && !isRefunded && hasReturnableItems)
          ElevatedButton.icon(
            onPressed: () async {
              final refunded = await showDialog<bool>(
                context: context,
                builder: (_) => RefundSaleDialog(saleDetail: detail),
              );
              if (refunded == true && context.mounted) {
                ref.read(salesHistoryProvider.notifier).selectSale(sale.id);
              }
            },
            icon: const Icon(Icons.assignment_return_outlined, size: 18),
            label: const Text('Kısmi İade Yap'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.warningBg,
              foregroundColor: colors.warningText,
              elevation: 0,
              minimumSize: const Size(140, 46),
            ),
          ),
        AppButton(
          label: 'Kapat',
          variant: AppButtonVariant.secondary,
          minHeight: 46,
          onPressed: () {
            ref.read(salesHistoryProvider.notifier).clearSelectedSale();
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  Widget _summaryColumn(
    BuildContext context,
    String label,
    String value, {
    Color? valueColor,
    bool large = false,
  }) {
    final colors = context.mmsColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: large ? 16 : 14,
            fontWeight: FontWeight.w800,
            color: valueColor ?? colors.textPrimary,
            fontFeatures: MmsTypography.tabularFigures,
          ),
        ),
      ],
    );
  }
}
