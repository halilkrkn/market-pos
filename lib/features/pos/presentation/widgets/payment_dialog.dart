import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../domain/money.dart';
import '../../domain/pos_repository.dart';

/// Tek ödeme modalı: kanonik `CASH` (`F10`) veya `CARD` (`F9`), `Esc` ile güvenli iptal.
class PaymentDialog extends StatefulWidget {
  final int totalCents;
  final PaymentMethod initialMethod;
  final bool showKeyboardHints;
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
    this.showKeyboardHints = true,
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
    final colors = context.mmsColors;

    return PopScope(
      canPop: !_isSubmitting,
      child: CallbackShortcuts(
        bindings: widget.showKeyboardHints
            ? {
                const SingleActivator(LogicalKeyboardKey.escape): () {
                  if (!_isSubmitting) Navigator.of(context).pop();
                },
                const SingleActivator(LogicalKeyboardKey.f10): () =>
                    _selectPaymentMethod(PaymentMethod.cash),
                const SingleActivator(LogicalKeyboardKey.f9): () =>
                    _selectPaymentMethod(PaymentMethod.card),
              }
            : const {},
        child: FocusScope(
          autofocus: widget.showKeyboardHints,
          child: AppDialog(
            key: const Key('payment_dialog'),
            title: 'Ödeme ve Tahsilat',
            icon: Icons.point_of_sale_rounded,
            iconColor: colors.emerald,
            maxWidth: 580,
            onClose: _isSubmitting ? null : () => Navigator.of(context).pop(),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(MmsSpacing.md),
                    decoration: BoxDecoration(
                      color: colors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(MmsRadius.md),
                      border: Border.all(color: colors.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          'Ödenecek Tutar:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.textSecondary,
                          ),
                        ),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              Money.formatCents(widget.totalCents),
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                color: colors.textPrimary,
                                fontFeatures: MmsTypography.tabularFigures,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: MmsSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('payment_method_cash'),
                          onPressed: _isSubmitting
                              ? null
                              : () => _selectPaymentMethod(PaymentMethod.cash),
                          icon: const Icon(Icons.payments_outlined, size: 19),
                          label: Text(
                            widget.showKeyboardHints ? 'NAKİT [F10]' : 'NAKİT',
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(110, 50),
                            backgroundColor:
                                _selectedMethod == PaymentMethod.cash
                                    ? colors.successBg
                                    : colors.surface,
                            foregroundColor:
                                _selectedMethod == PaymentMethod.cash
                                    ? colors.successText
                                    : colors.textPrimary,
                            side: BorderSide(
                              color: _selectedMethod == PaymentMethod.cash
                                  ? colors.emerald
                                  : colors.borderStrong,
                              width:
                                  _selectedMethod == PaymentMethod.cash ? 2 : 1,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: MmsSpacing.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('payment_method_card'),
                          onPressed: _isSubmitting
                              ? null
                              : () => _selectPaymentMethod(PaymentMethod.card),
                          icon: const Icon(Icons.credit_card_rounded, size: 19),
                          label: Text(
                            widget.showKeyboardHints ? 'KART [F9]' : 'KART',
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(110, 50),
                            backgroundColor:
                                _selectedMethod == PaymentMethod.card
                                    ? colors.infoBg
                                    : colors.surface,
                            foregroundColor:
                                _selectedMethod == PaymentMethod.card
                                    ? colors.infoText
                                    : colors.textPrimary,
                            side: BorderSide(
                              color: _selectedMethod == PaymentMethod.card
                                  ? colors.info
                                  : colors.borderStrong,
                              width:
                                  _selectedMethod == PaymentMethod.card ? 2 : 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MmsSpacing.md),
                  if (_selectedMethod == PaymentMethod.cash)
                    _buildCashSection(context)
                  else
                    _buildCardSection(context),
                  if (_submitError != null) ...[
                    const SizedBox(height: MmsSpacing.sm),
                    AppErrorState(message: _submitError!, inline: true),
                  ],
                ],
              ),
            ),
            actions: [
              OutlinedButton(
                key: const Key('payment_cancel_button'),
                onPressed:
                    _isSubmitting ? null : () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(100, 52),
                ),
                child: Text(
                  widget.showKeyboardHints ? 'İptal [Esc]' : 'İptal',
                ),
              ),
              ElevatedButton(
                key: const Key('payment_confirm_button'),
                onPressed: _canSubmit ? _submit : null,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(180, 52),
                  backgroundColor: _selectedMethod == PaymentMethod.cash
                      ? colors.emerald
                      : colors.primary,
                  foregroundColor: _selectedMethod == PaymentMethod.cash
                      ? colors.onEmerald
                      : colors.onPrimary,
                  disabledBackgroundColor: colors.neutralBg,
                  disabledForegroundColor: colors.textTertiary,
                ),
                child: _isSubmitting
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: colors.onPrimary,
                        ),
                      )
                    : const Text('SATIŞI TAMAMLA'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCashSection(BuildContext context) {
    final colors = context.mmsColors;
    final received = _parsedCashCents;
    final bool hasInput = _cashController.text.trim().isNotEmpty;

    Widget statusBox;
    if (!hasInput) {
      statusBox = _buildChangeBox(
        title: 'Alınan Nakit Tutarı Giriniz',
        amountText: '0.00 TL',
        bgColor: colors.surfaceSubtle,
        borderColor: colors.border,
        textColor: colors.textSecondary,
      );
    } else if (received == null) {
      statusBox = _buildChangeBox(
        title: 'Geçersiz TL Biçimi',
        amountText: 'Ör: 50.00',
        bgColor: colors.dangerBg,
        borderColor: colors.danger,
        textColor: colors.dangerText,
      );
    } else if (received < widget.totalCents) {
      statusBox = _buildChangeBox(
        title: 'Eksik Tutar (Satış Onayı Kilitli)',
        amountText: Money.formatCents(widget.totalCents - received),
        bgColor: colors.dangerBg,
        borderColor: colors.danger,
        textColor: colors.dangerText,
      );
    } else {
      statusBox = _buildChangeBox(
        title: 'Verilecek Para Üstü',
        amountText: Money.formatCents(received - widget.totalCents),
        bgColor: colors.successBg,
        borderColor: colors.emerald,
        textColor: colors.successText,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: MmsSpacing.xs,
          runSpacing: MmsSpacing.xs,
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
        const SizedBox(height: MmsSpacing.sm),
        TextField(
          key: const Key('cash_received_input'),
          controller: _cashController,
          autofocus: widget.showKeyboardHints,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: colors.textPrimary,
            fontFeatures: MmsTypography.tabularFigures,
          ),
          decoration: const InputDecoration(
            labelText: 'Müşteriden Alınan Nakit (TL)',
            hintText: 'Ör: 100.00',
          ),
          onChanged: (_) => setState(() {
            _submitError = null;
          }),
          // R-06: USB HID Enter sızıntısı tutarı doğrulamadan satışı asla otomatik tamamlamaz
          onSubmitted: (_) => setState(() {}),
        ),
        const SizedBox(height: MmsSpacing.sm),
        statusBox,
      ],
    );
  }

  Widget _buildCardSection(BuildContext context) {
    final colors = context.mmsColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(MmsSpacing.md),
          decoration: BoxDecoration(
            color: colors.infoBg,
            borderRadius: BorderRadius.circular(MmsRadius.sm),
            border: Border.all(color: colors.info.withValues(alpha: 0.4)),
          ),
          child: Text(
            'Harici banka POS terminaline otomatik tutar gönderilmez (INV-05). '
            'Tahsil edilecek tutarı harici POS cihazına elle giriniz.',
            style: TextStyle(
              fontSize: 13.5,
              color: colors.infoText,
              height: 1.45,
            ),
          ),
        ),
        const SizedBox(height: MmsSpacing.sm),
        Material(
          color: colors.surfaceSubtle,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MmsRadius.sm),
            side: BorderSide(color: colors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: CheckboxListTile(
            key: const Key('card_manual_confirm_checkbox'),
            value: _externalPosConfirmed,
            activeColor: colors.emerald,
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
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
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
        minimumSize: const Size(80, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          fontFeatures: MmsTypography.tabularFigures,
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
      padding: const EdgeInsets.symmetric(
        vertical: MmsSpacing.md,
        horizontal: MmsSpacing.md,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(MmsRadius.md),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: textColor,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              amountText,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: textColor,
                fontFeatures: MmsTypography.tabularFigures,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
