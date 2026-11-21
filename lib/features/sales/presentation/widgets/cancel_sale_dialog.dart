import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../sales_providers.dart';

class CancelSaleDialog extends ConsumerStatefulWidget {
  final String saleId;
  final int totalAmount;

  const CancelSaleDialog({
    super.key,
    required this.saleId,
    required this.totalAmount,
  });

  @override
  ConsumerState<CancelSaleDialog> createState() => _CancelSaleDialogState();
}

class _CancelSaleDialogState extends ConsumerState<CancelSaleDialog> {
  final _reasonController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _handleConfirm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
    });

    final success = await ref.read(salesHistoryProvider.notifier).cancelSale(
          saleId: widget.saleId,
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
      title: 'Tam Satış İptali',
      subtitle: 'Bu işlem geri alınamaz ve satılan ürünler stoğa iade edilir.',
      icon: Icons.cancel_outlined,
      iconColor: colors.danger,
      maxWidth: 480,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fiş No: ${widget.saleId}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
                fontFeatures: MmsTypography.tabularFigures,
              ),
            ),
            const SizedBox(height: MmsSpacing.md),
            Text(
              'İptal Gerekçesi (Zorunlu):',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: MmsSpacing.xs),
            TextFormField(
              controller: _reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Örn: Müşteri vazgeçti, yanlış fiş kesildi vb.',
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Lütfen geçerli bir iptal gerekçesi giriniz.';
                }
                if (val.trim().length < 3) {
                  return 'Gerekçe en az 3 karakter olmalıdır.';
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
          label: _isSubmitting ? 'İşleniyor...' : 'İptali Onayla',
          icon: Icons.check_rounded,
          variant: AppButtonVariant.danger,
          isLoading: _isSubmitting,
          onPressed: _handleConfirm,
        ),
      ],
    );
  }
}
