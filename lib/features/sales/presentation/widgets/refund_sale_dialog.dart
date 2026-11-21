import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../pos/domain/money.dart';
import '../../sales_providers.dart';

class RefundSaleDialog extends ConsumerStatefulWidget {
  final SaleWithDetails saleDetail;

  const RefundSaleDialog({
    super.key,
    required this.saleDetail,
  });

  @override
  ConsumerState<RefundSaleDialog> createState() => _RefundSaleDialogState();
}

class _RefundSaleDialogState extends ConsumerState<RefundSaleDialog> {
  final _reasonController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;

  // saleItemId -> miktar (milli-scale)
  final Map<String, int> _selectedQuantities = {};
  // saleItemId -> 'SELLABLE' veya 'DAMAGED'
  final Map<String, String> _selectedConditions = {};

  @override
  void initState() {
    super.initState();
    for (final item in widget.saleDetail.items) {
      final returnable = widget.saleDetail.returnableQuantityFor(item);
      if (returnable > 0) {
        _selectedQuantities[item.id] = 0;
        _selectedConditions[item.id] = 'SELLABLE';
      }
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  int get _calculatedTotalRefundCents {
    var total = 0;
    for (final item in widget.saleDetail.items) {
      final qty = _selectedQuantities[item.id] ?? 0;
      if (qty > 0) {
        final itemRefund = Money.calculateLineTotalHalfUp(
          unitPriceCents: item.unitPrice,
          quantityMilli: qty,
        );
        total += itemRefund;
      }
    }
    return total;
  }

  Future<void> _handleConfirm() async {
    if (!_formKey.currentState!.validate()) return;

    final refundInputs = <RefundItemInput>[];
    for (final entry in _selectedQuantities.entries) {
      if (entry.value > 0) {
        refundInputs.add(
          RefundItemInput(
            saleItemId: entry.key,
            quantity: entry.value,
            productCondition: _selectedConditions[entry.key] ?? 'SELLABLE',
          ),
        );
      }
    }

    if (refundInputs.isEmpty) {
      AppSnackbar.show(
        context,
        message: 'Lütfen iade edilecek en az bir ürün ve miktar seçiniz.',
        tone: AppBadgeTone.danger,
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final success = await ref.read(salesHistoryProvider.notifier).refundSale(
          saleId: widget.saleDetail.sale.id,
          items: refundInputs,
          reason: _reasonController.text.trim(),
        );

    if (mounted) {
      setState(() {
        _isSubmitting = false;
      });
      if (success) {
        Navigator.of(context).pop(true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;

    return AppDialog(
      title: 'Kısmi Ürün İadesi',
      subtitle:
          'İade edilecek ürünleri, miktarları ve ürün kondisyonunu belirleyiniz.',
      icon: Icons.assignment_return_outlined,
      iconColor: colors.warning,
      maxWidth: 740,
      maxHeight: 780,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'İade Edilebilir Ürün Kalemleri:',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: MmsSpacing.xs),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.saleDetail.items.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: colors.border),
                itemBuilder: (context, index) {
                  final item = widget.saleDetail.items[index];
                  final maxReturnable =
                      widget.saleDetail.returnableQuantityFor(item);
                  final isReturnable = maxReturnable > 0;
                  final currentQty = _selectedQuantities[item.id] ?? 0;
                  final currentCondition =
                      _selectedConditions[item.id] ?? 'SELLABLE';

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: MmsSpacing.sm,
                      horizontal: MmsSpacing.xs,
                    ),
                    color: currentQty > 0
                        ? colors.successBg
                        : Colors.transparent,
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: MmsSpacing.sm,
                      runSpacing: MmsSpacing.xs,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.productNameSnapshot,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: colors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Birim: ${Money.formatCents(item.unitPrice)} | Satış: ${Money.formatMilliWithUnit(item.quantity, item.unitSnapshot)} | Kalan: ${Money.formatMilliWithUnit(maxReturnable, item.unitSnapshot)}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: colors.textSecondary,
                                  fontFeatures: MmsTypography.tabularFigures,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isReturnable)
                          Wrap(
                            spacing: MmsSpacing.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              AppDropdown<String>(
                                value: currentCondition,
                                items: [
                                  const DropdownMenuItem(
                                    value: 'SELLABLE',
                                    child: Text(
                                      'Sağlam (Rafa)',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'DAMAGED',
                                    child: Text(
                                      'Hasarlı (Fire)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colors.dangerText,
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _selectedConditions[item.id] = val;
                                    });
                                  }
                                },
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline),
                                    onPressed: currentQty > 0
                                        ? () {
                                            setState(() {
                                              final step =
                                                  item.unitSnapshot == 'kg' ||
                                                          item.unitSnapshot ==
                                                              'g'
                                                      ? 100
                                                      : 1000;
                                              final next = currentQty - step;
                                              _selectedQuantities[item.id] =
                                                  next < 0 ? 0 : next;
                                            });
                                          }
                                        : null,
                                  ),
                                  Container(
                                    constraints:
                                        const BoxConstraints(minWidth: 64),
                                    alignment: Alignment.center,
                                    child: Text(
                                      Money.formatMilliWithUnit(
                                        currentQty,
                                        item.unitSnapshot,
                                      ),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: colors.textPrimary,
                                        fontFeatures:
                                            MmsTypography.tabularFigures,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline),
                                    onPressed: currentQty < maxReturnable
                                        ? () {
                                            setState(() {
                                              final step =
                                                  item.unitSnapshot == 'kg' ||
                                                          item.unitSnapshot ==
                                                              'g'
                                                      ? 100
                                                      : 1000;
                                              final next = currentQty + step;
                                              _selectedQuantities[item.id] =
                                                  next > maxReturnable
                                                      ? maxReturnable
                                                      : next;
                                            });
                                          }
                                        : null,
                                  ),
                                ],
                              ),
                            ],
                          )
                        else
                          const AppBadge(
                            label: 'Tamamı İade Edildi',
                            tone: AppBadgeTone.neutral,
                            compact: true,
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Divider(height: MmsSpacing.lg, color: colors.border),
            Container(
              padding: const EdgeInsets.all(MmsSpacing.sm),
              decoration: BoxDecoration(
                color: colors.surfaceSubtle,
                borderRadius: BorderRadius.circular(MmsRadius.sm),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Hesaplanan İade Tutarı:',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(
                    Money.formatCents(_calculatedTotalRefundCents),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: colors.emerald,
                      fontFeatures: MmsTypography.tabularFigures,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MmsSpacing.sm),
            TextFormField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'İade Gerekçesi (Zorunlu)',
                hintText: 'Örn: Bozuk ürün, yanlış ürün, müşteri vazgeçti',
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Lütfen geçerli bir iade gerekçesi belirtiniz.';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        AppButton(
          label: 'Vazgeç',
          variant: AppButtonVariant.secondary,
          onPressed:
              _isSubmitting ? null : () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: _isSubmitting ? 'İşleniyor...' : 'İadeyi Tamamla',
          icon: Icons.check_rounded,
          variant: AppButtonVariant.emerald,
          isLoading: _isSubmitting,
          onPressed: _calculatedTotalRefundCents <= 0 ? null : _handleConfirm,
        ),
      ],
    );
  }
}
