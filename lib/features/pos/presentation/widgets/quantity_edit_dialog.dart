import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/cart_item.dart';
import '../../domain/money.dart';

/// `F2` veya satır miktar tıklamasıyla açılan miktar düzenleme penceresi (milli ölçek `1000`).
class QuantityEditDialog extends StatefulWidget {
  final CartItem item;
  final String? Function(String rawQuantity) onValidateAndApply;

  const QuantityEditDialog({
    super.key,
    required this.item,
    required this.onValidateAndApply,
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
    final hasRatio = widget.item.conversionFactorDenominator > 1;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: AlertDialog(
        key: const Key('quantity_edit_dialog'),
        title: const Text('Miktar Düzenle [F2]'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.item.productName,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMainLight,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Birim: ${widget.item.pricingUnit} • 0 girilirse satır sepetten silinir.',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textMutedLight,
                ),
              ),
              if (hasRatio) ...[
                const SizedBox(height: 4),
                Text(
                  'Dönüşüm oranı paydası: ${widget.item.conversionFactorDenominator} (${widget.item.stockUnit})',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.posWarningText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                key: const Key('quantity_edit_input'),
                controller: _controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  fontFeatures: AppTheme.tabularFiguresFeature,
                ),
                decoration: InputDecoration(
                  labelText: 'Miktar (${widget.item.pricingUnit})',
                  hintText: 'Ör: 1, 0.5, 0.345',
                  border: const OutlineInputBorder(),
                  errorText: _inlineError,
                ),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('İptal [Esc]'),
          ),
          ElevatedButton(
            key: const Key('quantity_edit_confirm'),
            onPressed: _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Uygula'),
          ),
        ],
      ),
    );
  }
}

