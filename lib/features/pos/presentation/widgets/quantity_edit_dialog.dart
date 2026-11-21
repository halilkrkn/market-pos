import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../domain/cart_item.dart';
import '../../domain/money.dart';

/// `F2` veya satır miktar tıklamasıyla açılan miktar düzenleme penceresi (milli ölçek `1000`).
class QuantityEditDialog extends StatefulWidget {
  final CartItem item;
  final String? Function(String rawQuantity) onValidateAndApply;
  final bool showKeyboardHints;

  const QuantityEditDialog({
    super.key,
    required this.item,
    required this.onValidateAndApply,
    this.showKeyboardHints = true,
  });

  @override
  State<QuantityEditDialog> createState() => _QuantityEditDialogState();
}

class _QuantityEditDialogState extends State<QuantityEditDialog> {
  late final TextEditingController _controller;
  String? _inlineError;

  @override
  void initState() {
    super.initState();
    final initialText = Money.formatMilliNumber(widget.item.quantityMilli);
    _controller = TextEditingController(text: initialText)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: initialText.length,
      );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final error = widget.onValidateAndApply(_controller.text);
    if (error != null) {
      setState(() {
        _inlineError = error;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    final hasRatio = widget.item.conversionFactorDenominator > 1;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: AppDialog(
        key: const Key('quantity_edit_dialog'),
        title:
            widget.showKeyboardHints ? 'Miktar Düzenle [F2]' : 'Miktar Düzenle',
        icon: Icons.scale_rounded,
        iconColor: colors.emerald,
        maxWidth: 420,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.item.productName,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Birim: ${widget.item.pricingUnit} • 0 girilirse satır sepetten silinir.',
              style: TextStyle(
                fontSize: 12.5,
                color: colors.textSecondary,
              ),
            ),
            if (hasRatio) ...[
              const SizedBox(height: 4),
              Text(
                'Dönüşüm oranı paydası: ${widget.item.conversionFactorDenominator} (${widget.item.stockUnit})',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.warningText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: MmsSpacing.md),
            TextField(
              key: const Key('quantity_edit_input'),
              controller: _controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
                fontFeatures: MmsTypography.tabularFigures,
              ),
              decoration: InputDecoration(
                labelText: 'Miktar (${widget.item.pricingUnit})',
                hintText: 'Ör: 1, 0.5, 0.345',
                errorText: _inlineError,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
        actions: [
          AppButton(
            label: widget.showKeyboardHints ? 'İptal [Esc]' : 'İptal',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          AppButton(
            key: const Key('quantity_edit_confirm'),
            label: 'Uygula',
            variant: AppButtonVariant.emerald,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
