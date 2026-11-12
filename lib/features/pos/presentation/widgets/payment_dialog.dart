import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/money.dart';
import '../../domain/pos_repository.dart';

/// Tek ödeme modalı: kanonik `CASH` (`F10`) veya `CARD` (`F9`), `Esc` ile güvenli iptal.
class PaymentDialog extends StatefulWidget {
  final int totalCents;
  final PaymentMethod initialMethod;
  final Future<({PosCompletedSale? sale, String? errorMessage})> Function({
    required PaymentMethod paymentMethod,
    int? cashReceivedCents,
    required bool externalPosConfirmed,
  }) onConfirmSale;

  const PaymentDialog({
    super.key,
    required this.totalCents,
    required this.initialMethod,
    required this.onConfirmSale,
  });

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  late PaymentMethod _selectedMethod;
  final TextEditingController _cashController = TextEditingController();
  bool _externalPosConfirmed = false;
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _selectedMethod = widget.initialMethod;
  }

  @override
  void dispose() {
    _cashController.dispose();
    super.dispose();
  }

  int? get _parsedCashCents => Money.tryParseLiraToCents(_cashController.text);

  bool get _canSubmit {
    if (_isSubmitting || widget.totalCents <= 0) return false;
    if (_selectedMethod == PaymentMethod.cash) {
      final received = _parsedCashCents;
      return received != null && received >= widget.totalCents;
    }
    return _externalPosConfirmed;
  }

  void _setCashPreset(int cents) {
    setState(() {
      _submitError = null;
      _cashController.text = Money.formatCentsInput(cents);
      _cashController.selection = TextSelection.collapsed(
        offset: _cashController.text.length,
      );
    });
  }

  void _selectPaymentMethod(PaymentMethod method) {
    if (_isSubmitting) return;
    setState(() {
      _selectedMethod = method;
      _externalPosConfirmed = false;
      _submitError = null;
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      final result = await widget.onConfirmSale(
        paymentMethod: _selectedMethod,
        cashReceivedCents:
            _selectedMethod == PaymentMethod.cash ? _parsedCashCents : null,
        externalPosConfirmed:
            _selectedMethod == PaymentMethod.card && _externalPosConfirmed,
      );

      if (!mounted) return;
      if (result.sale != null) {
        Navigator.of(context).pop(result.sale);
        return;
      }

      setState(() {
        _isSubmitting = false;
        _submitError = result.errorMessage ??
            'Satış tamamlanamadı. Lütfen girilen bilgileri kontrol ediniz.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = 'Ödeme işlemi sırasında beklenmeyen bir hata oluştu.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSubmitting,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (!_isSubmitting) Navigator.of(context).pop();
          },
          const SingleActivator(LogicalKeyboardKey.f10): () =>
              _selectPaymentMethod(PaymentMethod.cash),
          const SingleActivator(LogicalKeyboardKey.f9): () =>
              _selectPaymentMethod(PaymentMethod.card),
        },
        child: FocusScope(
          autofocus: true,
          child: Dialog(
        key: const Key('payment_dialog'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 580),
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Ödeme ve Tahsilat',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textMainLight,
                      ),
                    ),
                    IconButton(
                      tooltip: 'İptal [Esc]',
                      onPressed:
                          _isSubmitting ? null : () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    const Text(
                      'Ödenecek Tutar:',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMutedLight,
                      ),
                    ),
                    Text(
                      Money.formatCents(widget.totalCents),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textMainLight,
                        fontFeatures: AppTheme.tabularFiguresFeature,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('payment_method_cash'),
                        onPressed: _isSubmitting
                            ? null
                            : () => _selectPaymentMethod(PaymentMethod.cash),
                        icon: const Icon(Icons.payments_outlined),
                        label: const Text('NAKİT [F10]'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(120, 50),
                          backgroundColor: _selectedMethod == PaymentMethod.cash
                              ? AppTheme.posCashBg
                              : AppTheme.cardBgLight,
                          foregroundColor: _selectedMethod == PaymentMethod.cash
                              ? AppTheme.posCashText
                              : AppTheme.textMainLight,
                          side: BorderSide(
                            color: _selectedMethod == PaymentMethod.cash
                                ? AppTheme.posCashAction
                                : AppTheme.borderSubtle,
                            width: _selectedMethod == PaymentMethod.cash ? 2 : 1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('payment_method_card'),
                        onPressed: _isSubmitting
                            ? null
                            : () => _selectPaymentMethod(PaymentMethod.card),
                        icon: const Icon(Icons.credit_card),
                        label: const Text('KART [F9]'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(120, 50),
                          backgroundColor: _selectedMethod == PaymentMethod.card
                              ? AppTheme.posInfoBg
                              : AppTheme.cardBgLight,
                          foregroundColor: _selectedMethod == PaymentMethod.card
                              ? AppTheme.primaryBlue
                              : AppTheme.textMainLight,
                          side: BorderSide(
                            color: _selectedMethod == PaymentMethod.card
                                ? AppTheme.primaryBlue
                                : AppTheme.borderSubtle,
                            width: _selectedMethod == PaymentMethod.card ? 2 : 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_selectedMethod == PaymentMethod.cash)
                  _buildCashSection()
                else
                  _buildCardSection(),
                if (_submitError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.posDangerBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.posDangerText),
                    ),
                    child: Text(
                      _submitError!,
                      style: const TextStyle(
                        color: AppTheme.posDangerText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: OutlinedButton(
                        key: const Key('payment_cancel_button'),
                        onPressed:
                            _isSubmitting ? null : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(100, 54),
                        ),
                        child: const Text('İptal [Esc]'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        key: const Key('payment_confirm_button'),
                        onPressed: _canSubmit ? _submit : null,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(180, 54),
                          backgroundColor: _selectedMethod == PaymentMethod.cash
                              ? AppTheme.posCashAction
                              : AppTheme.primaryBlue,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFFCBD5E1),
                          disabledForegroundColor: const Color(0xFF475569),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('SATIŞI TAMAMLA'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      ),
      ),
    );
  }

  Widget _buildCashSection() {
    final received = _parsedCashCents;
    final bool hasInput = _cashController.text.trim().isNotEmpty;

    Widget statusBox;
    if (!hasInput) {
      statusBox = _buildChangeBox(
        title: 'Alınan Nakit Tutarı Giriniz',
        amountText: '0.00 TL',
        bgColor: AppTheme.surfaceLight,
        borderColor: AppTheme.borderSubtle,
        textColor: AppTheme.textMutedLight,
      );
    } else if (received == null) {
      statusBox = _buildChangeBox(
        title: 'Geçersiz TL Biçimi',
        amountText: 'Ör: 50.00',
        bgColor: AppTheme.posDangerBg,
        borderColor: AppTheme.posDangerText,
        textColor: AppTheme.posDangerText,
      );
    } else if (received < widget.totalCents) {
      statusBox = _buildChangeBox(
        title: 'Eksik Tutar (Satış Onayı Kilitli)',
        amountText: Money.formatCents(widget.totalCents - received),
        bgColor: AppTheme.posDangerBg,
        borderColor: AppTheme.posDangerText,
        textColor: AppTheme.posDangerText,
      );
    } else {
      statusBox = _buildChangeBox(
        title: 'Verilecek Para Üstü',
        amountText: Money.formatCents(received - widget.totalCents),
        bgColor: AppTheme.posCashBg,
        borderColor: AppTheme.posCashAction,
        textColor: AppTheme.posCashText,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _presetButton('Tam Tutar', () => _setCashPreset(widget.totalCents)),
            _presetButton('50 TL', () => _setCashPreset(5000)),
            _presetButton('100 TL', () => _setCashPreset(10000)),
            _presetButton('200 TL', () => _setCashPreset(20000)),
            _presetButton('500 TL', () => _setCashPreset(50000)),
            _presetButton('Temizle', () {
              setState(() {
                _cashController.clear();
                _submitError = null;
              });
            }),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('cash_received_input'),
          controller: _cashController,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            fontFeatures: AppTheme.tabularFiguresFeature,
          ),
          decoration: const InputDecoration(
            labelText: 'Müşteriden Alınan Nakit (TL)',
            hintText: 'Ör: 100.00',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {
            _submitError = null;
          }),
          // R-06: USB HID Enter sızıntısı tutarı doğrulamadan satışı asla otomatik tamamlamaz
          onSubmitted: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        statusBox,
      ],
    );
  }

  Widget _buildCardSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.posInfoBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppTheme.primaryBlue.withValues(alpha: 0.4),
            ),
          ),
          child: const Text(
            'Harici banka POS terminaline otomatik tutar gönderilmez (INV-05). '
            'Tahsil edilecek tutarı harici POS cihazına elle giriniz.',
            style: TextStyle(
              fontSize: 13.5,
              color: AppTheme.textMainLight,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Material(
          color: AppTheme.surfaceLight,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: AppTheme.borderSubtle),
          ),
          clipBehavior: Clip.antiAlias,
          child: CheckboxListTile(
            key: const Key('card_manual_confirm_checkbox'),
            value: _externalPosConfirmed,
            onChanged: _isSubmitting
                ? null
                : (checked) {
                    setState(() {
                      _externalPosConfirmed = checked ?? false;
                      _submitError = null;
                    });
                  },
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              'Harici banka POS terminaline ${Money.formatCents(widget.totalCents)} tutarını elle girdiğimi ve ödemenin onaylandığını teyit ediyorum.',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMainLight,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _presetButton(String label, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: _isSubmitting ? null : onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(84, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          fontFeatures: AppTheme.tabularFiguresFeature,
        ),
      ),
    );
  }

  Widget _buildChangeBox({
    required String title,
    required String amountText,
    required Color bgColor,
    required Color borderColor,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: textColor,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            amountText,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: textColor,
              fontFeatures: AppTheme.tabularFiguresFeature,
            ),
          ),
        ],
      ),
    );
  }
}

