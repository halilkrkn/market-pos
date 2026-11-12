import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../diagnostics/application/system_status_notifier.dart';
import '../../domain/cart_item.dart';
import '../../domain/cart_state.dart';
import '../../domain/money.dart';
import '../../domain/pos_repository.dart';
import '../../pos_providers.dart';
import '../widgets/cart_item_row.dart';
import '../widgets/help_shortcuts_dialog.dart';
import '../widgets/payment_dialog.dart';
import '../widgets/product_search_dialog.dart';
import '../widgets/quantity_edit_dialog.dart';
import '../widgets/virtual_numpad_panel.dart';

/// Faz 1.2 Kasa Satış (POS) Ekranı — Windows Masaüstü Çift Panelli Ergonomi.
class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();
  int _activeModalCount = 0;

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    super.dispose();
  }

  bool get _isIdle => _activeModalCount == 0;

  void _refocusBarcodeIfIdle() {
    if (!mounted || !_isIdle) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isIdle && _barcodeFocusNode.canRequestFocus) {
        _barcodeFocusNode.requestFocus();
      }
    });
  }

  Future<T?> _showPosModal<T>(
    WidgetBuilder builder, {
    bool barrierDismissible = true,
  }) async {
    if (!mounted) return null;
    _activeModalCount++;
    _barcodeFocusNode.canRequestFocus = false;
    _barcodeFocusNode.unfocus();
    try {
      return await showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: builder,
      );
    } finally {
      _activeModalCount--;
      if (mounted && _isIdle) {
        _barcodeFocusNode.canRequestFocus = true;
        _refocusBarcodeIfIdle();
      }
    }
  }

  Future<void> _submitBarcode() async {
    if (!_isIdle) return;
    final raw = _barcodeController.text.trim();
    if (raw.isEmpty) {
      _refocusBarcodeIfIdle();
      return;
    }
    _barcodeController.clear();
    await ref.read(cartProvider.notifier).scanBarcode(raw);
    _refocusBarcodeIfIdle();
  }

  void _appendNumpadChar(String value) {
    final nextText = _barcodeController.text + value;
    _barcodeController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
  }

  void _backspaceNumpad() {
    final text = _barcodeController.text;
    if (text.isEmpty) return;
    final nextText = text.substring(0, text.length - 1);
    _barcodeController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
  }

  Future<void> _openProductSearchDialog() async {
    if (!_isIdle) return;
    final repo = ref.read(posRepositoryProvider);
    await _showPosModal<void>(
      (_) => ProductSearchDialog(
        repository: repo,
        onSelectProduct: (product) {
          ref.read(cartProvider.notifier).addProduct(product);
        },
      ),
    );
  }

  Future<void> _openQuantityDialog([CartItem? targetItem]) async {
    if (!_isIdle) return;
    final item = targetItem ?? ref.read(cartProvider).selectedItem;
    if (item == null) return;

    await _showPosModal<void>(
      (_) => QuantityEditDialog(
        item: item,
        onValidateAndApply: (rawQuantity) {
          final ok = ref.read(cartProvider.notifier).updateQuantityFromInput(
                productId: item.productId,
                rawQuantity: rawQuantity,
              );
          if (!ok) {
            return ref.read(cartProvider).errorMessage ?? 'Miktar güncellenemedi.';
          }
          return null;
        },
      ),
    );
  }

  Future<void> _openClearCartDialog() async {
    if (!_isIdle || ref.read(cartProvider).isEmpty) return;
    final confirmed = await _showPosModal<bool>(
      (dialogContext) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(dialogContext).pop(false),
        },
        child: AlertDialog(
          key: const Key('clear_cart_confirm_dialog'),
          title: const Text('Sepeti Temizle'),
          content: const Text(
            'Sepetteki tüm ürünleri kaldırmak istediğinize emin misiniz?',
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Vazgeç [Esc]'),
            ),
            ElevatedButton(
              key: const Key('clear_cart_confirm_yes'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.statusOffline,
                foregroundColor: Colors.white,
              ),
              child: const Text('Sepeti Temizle'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      ref.read(cartProvider.notifier).clearCart();
    }
  }

  Future<void> _openPaymentDialog(PaymentMethod method) async {
    if (!_isIdle) return;
    final cartState = ref.read(cartProvider);
    if (!cartState.canCheckout) return;

    await _showPosModal<PosCompletedSale>(
      (_) => PaymentDialog(
        totalCents: cartState.totalCents,
        initialMethod: method,
        onConfirmSale: ({
          required paymentMethod,
          cashReceivedCents,
          required externalPosConfirmed,
        }) async {
          final notifier = ref.read(cartProvider.notifier);
          final sale = await notifier.completeSale(
            paymentMethod: paymentMethod,
            cashReceivedCents: cashReceivedCents,
            externalPosConfirmed: externalPosConfirmed,
          );
          final err = mounted ? ref.read(cartProvider).errorMessage : null;
          return (sale: sale, errorMessage: err);
        },
      ),
      barrierDismissible: false,
    );
  }

  Future<void> _openHelpDialog() async {
    if (!_isIdle) return;
    await _showPosModal<void>((_) => const HelpShortcutsDialog());
  }

  void _handleEscapeWhenIdle() {
    if (!_isIdle) return;
    if (_barcodeController.text.isNotEmpty) {
      _barcodeController.clear();
    }
    ref.read(cartProvider.notifier).clearMessages();
    _refocusBarcodeIfIdle();
  }

  @override
  Widget build(BuildContext context) {
    final cartState = ref.watch(cartProvider);
    final prefsState = ref.watch(posPreferencesProvider);
    final systemStatus = ref.watch(systemStatusProvider);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f1): _openHelpDialog,
        const SingleActivator(LogicalKeyboardKey.f2): () => _openQuantityDialog(),
        const SingleActivator(LogicalKeyboardKey.f9): () =>
            _openPaymentDialog(PaymentMethod.card),
        const SingleActivator(LogicalKeyboardKey.f10): () =>
            _openPaymentDialog(PaymentMethod.cash),
        const SingleActivator(LogicalKeyboardKey.escape): _handleEscapeWhenIdle,
      },
      child: Column(
        children: [
          _buildBarcodeToolbar(prefsState.showVirtualNumpad),
          if (cartState.errorMessage != null)
            _buildFeedbackBanner(
              message: cartState.errorMessage!,
              bgColor: AppTheme.posDangerBg,
              borderColor: AppTheme.posDangerText,
              textColor: AppTheme.posDangerText,
              icon: Icons.error_outline,
            ),
          if (cartState.infoMessage != null)
            _buildFeedbackBanner(
              message: cartState.infoMessage!,
              bgColor: AppTheme.posCashBg,
              borderColor: AppTheme.posCashAction,
              textColor: AppTheme.posCashText,
              icon: Icons.check_circle_outline,
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 900;
                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 6,
                        child: _buildCartPanel(cartState),
                      ),
                      const VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: AppTheme.borderSubtle,
                      ),
                      Expanded(
                        flex: 4,
                        child: _buildActionPanel(
                          cartState: cartState,
                          showNumpad: prefsState.showVirtualNumpad,
                          pendingOutboxCount: systemStatus.pendingOutboxCount,
                        ),
                      ),
                    ],
                  );
                }

                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 360,
                        child: _buildCartPanel(cartState),
                      ),
                      const Divider(height: 1, color: AppTheme.borderSubtle),
                      _buildActionPanel(
                        cartState: cartState,
                        showNumpad: prefsState.showVirtualNumpad,
                        pendingOutboxCount: systemStatus.pendingOutboxCount,
                        embedScrollable: true,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarcodeToolbar(bool showVirtualNumpad) {
    final barcodeField = TextField(
      key: const Key('barcode_input_field'),
      controller: _barcodeController,
      focusNode: _barcodeFocusNode,
      autofocus: true,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        fontFeatures: AppTheme.tabularFiguresFeature,
      ),
      decoration: const InputDecoration(
        hintText: 'Barkod okutun veya yazıp Enter tuşuna basın...',
        prefixIcon: Icon(Icons.qr_code_scanner),
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
      onSubmitted: (_) => _submitBarcode(),
    );

    final addButton = ElevatedButton.icon(
      key: const Key('barcode_add_button'),
      onPressed: _submitBarcode,
      icon: const Icon(Icons.add),
      label: const Text('Ekle'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        minimumSize: const Size(88, 48),
      ),
    );

    final searchButton = OutlinedButton.icon(
      key: const Key('open_product_search_button'),
      onPressed: _openProductSearchDialog,
      icon: const Icon(Icons.search),
      label: const Text('Ürün Ara'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(124, 48),
      ),
    );

    final numpadToggle = InkWell(
      key: const Key('virtual_numpad_toggle'),
      onTap: () {
        ref.read(posPreferencesProvider.notifier).toggleVirtualNumpad();
        _refocusBarcodeIfIdle();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: showVirtualNumpad ? AppTheme.posInfoBg : AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: showVirtualNumpad
                ? AppTheme.primaryBlue
                : AppTheme.borderSubtle,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dialpad,
              size: 18,
              color: showVirtualNumpad
                  ? AppTheme.primaryBlue
                  : AppTheme.textMutedLight,
            ),
            const SizedBox(width: 6),
            Text(
              'Sanal Numpad',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: showVirtualNumpad
                    ? AppTheme.primaryBlue
                    : AppTheme.textMainLight,
              ),
            ),
          ],
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppTheme.cardBgLight,
        border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 760) {
            return Row(
              children: [
                Expanded(child: barcodeField),
                const SizedBox(width: 10),
                addButton,
                const SizedBox(width: 10),
                searchButton,
                const SizedBox(width: 12),
                numpadToggle,
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              barcodeField,
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  addButton,
                  searchButton,
                  numpadToggle,
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFeedbackBanner({
    required String message,
    required Color bgColor,
    required Color borderColor,
    required Color textColor,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(bottom: BorderSide(color: borderColor, width: 1.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Kapat',
            onPressed: () {
              ref.read(cartProvider.notifier).clearMessages();
              _refocusBarcodeIfIdle();
            },
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: textColor,
            ),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildCartPanel(CartState cartState) {
    return Container(
      color: AppTheme.cardBgLight,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: AppTheme.surfaceLight,
              border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 560) {
                  return const Row(
                    children: [
                      SizedBox(
                        width: 32,
                        child: Text(
                          '#',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMutedLight,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: Text(
                          'Ürün & Birim Fiyat',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMutedLight,
                          ),
                        ),
                      ),
                      Text(
                        'Miktar',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMutedLight,
                        ),
                      ),
                      SizedBox(width: 96),
                      SizedBox(
                        width: 112,
                        child: Text(
                          'Tutar',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMutedLight,
                          ),
                        ),
                      ),
                      SizedBox(width: 56),
                    ],
                  );
                }

                return const Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Sepet Kalemleri',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMutedLight,
                        ),
                      ),
                    ),
                    Text(
                      'Tutar',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMutedLight,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Expanded(
            child: cartState.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shopping_cart_outlined,
                          size: 48,
                          color: AppTheme.textMutedLight,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Sepet boş. Barkod okutun veya "Ürün Ara" ile ürün ekleyin.',
                          style: TextStyle(
                            fontSize: 14.5,
                            color: AppTheme.textMutedLight,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: cartState.items.length,
                    itemBuilder: (context, index) {
                      final item = cartState.items[index];
                      return CartItemRow(
                        index: index,
                        item: item,
                        isSelected: cartState.selectedItem?.productId == item.productId,
                        onSelect: () {
                          ref
                              .read(cartProvider.notifier)
                              .selectProduct(item.productId);
                          _refocusBarcodeIfIdle();
                        },
                        onIncrement: () {
                          ref
                              .read(cartProvider.notifier)
                              .incrementProduct(item.productId);
                          _refocusBarcodeIfIdle();
                        },
                        onDecrement: () {
                          ref
                              .read(cartProvider.notifier)
                              .decrementProduct(item.productId);
                          _refocusBarcodeIfIdle();
                        },
                        onEditQuantity: () {
                          ref
                              .read(cartProvider.notifier)
                              .selectProduct(item.productId);
                          _openQuantityDialog(item);
                        },
                        onRemove: () {
                          ref
                              .read(cartProvider.notifier)
                              .removeProduct(item.productId);
                          _refocusBarcodeIfIdle();
                        },
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: AppTheme.surfaceLight,
              border: Border(top: BorderSide(color: AppTheme.borderSubtle)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Toplam: ${cartState.lineCount} Kalem',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textMainLight,
                      fontFeatures: AppTheme.tabularFiguresFeature,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  key: const Key('clear_cart_button'),
                  onPressed: cartState.isEmpty ? null : _openClearCartDialog,
                  icon: const Icon(Icons.clear_all),
                  label: const Text('Sepeti Temizle'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.posDangerText,
                    minimumSize: const Size(140, 48),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionPanel({
    required CartState cartState,
    required bool showNumpad,
    required int pendingOutboxCount,
    bool embedScrollable = false,
  }) {
    final topSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: AppTheme.cardBgLight,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: Text(
                'Bekleyen Outbox: $pendingOutboxCount',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMainLight,
                  fontFeatures: AppTheme.tabularFiguresFeature,
                ),
              ),
            ),
            OutlinedButton.icon(
              key: const Key('help_button'),
              onPressed: _openHelpDialog,
              icon: const Icon(Icons.help_outline, size: 18),
              label: const Text('Yardım [F1]'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(120, 48),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (cartState.hasNegativeStockItems) ...[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.posWarningBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.statusWarning),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: AppTheme.posWarningText,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Eksi stok uyarısı (allow): Satış engellenmez ancak stok eksiye düşecektir.',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.posWarningText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (showNumpad) ...[
          VirtualNumpadPanel(
            onDigitOrChar: _appendNumpadChar,
            onBackspace: _backspaceNumpad,
            onClear: () => _barcodeController.clear(),
            onSubmit: _submitBarcode,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );

    return Container(
      color: AppTheme.surfaceLight,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (embedScrollable)
            topSection
          else
            Expanded(
              child: SingleChildScrollView(
                child: topSection,
              ),
            ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.cardBgLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.primaryDark, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'ÖDENECEK TOPLAM TUTAR',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMutedLight,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  Money.formatCents(cartState.totalCents),
                  key: const Key('pos_grand_total'),
                  style: const TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textMainLight,
                    fontFeatures: AppTheme.tabularFiguresFeature,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  key: const Key('cash_pay_button'),
                  onPressed: cartState.canCheckout
                      ? () => _openPaymentDialog(PaymentMethod.cash)
                      : null,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(120, 64),
                    backgroundColor: AppTheme.posCashAction,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFCBD5E1),
                    disabledForegroundColor: const Color(0xFF475569),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'NAKİT',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '[F10]',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  key: const Key('card_pay_button'),
                  onPressed: cartState.canCheckout
                      ? () => _openPaymentDialog(PaymentMethod.card)
                      : null,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(120, 64),
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFCBD5E1),
                    disabledForegroundColor: const Color(0xFF475569),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'KREDİ KARTI',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        '[F9 • Elle Giriş]',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

