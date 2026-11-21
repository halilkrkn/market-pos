import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/platform/mms_ui_profile.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../barcode_scanner/barcode_scanner_providers.dart';
import '../../../barcode_scanner/domain/camera_scan_result.dart';
import '../../../barcode_scanner/domain/continuous_scan_session.dart';
import '../../../diagnostics/application/system_status_notifier.dart';
import '../../../shell/domain/app_destination.dart';
import '../../../shell/shell_providers.dart';
import '../../../sync/domain/sync_coordinator_state.dart';
import '../../../sync/sync_providers.dart';
import '../../application/hardware_barcode_buffer.dart';
import '../../domain/barcode_input_sanitizer.dart';
import '../../domain/cart_item.dart';
import '../../domain/money.dart';
import '../../domain/pos_repository.dart';
import '../../pos_providers.dart';
import '../widgets/desktop_pos_view.dart';
import '../widgets/help_shortcuts_dialog.dart';
import '../widgets/mobile_pos_view.dart';
import '../widgets/payment_dialog.dart';
import '../widgets/product_search_dialog.dart';
import '../widgets/quantity_edit_dialog.dart';

/// MARKET MMS — Kasa / POS Ekranı Koordinatörü.
///
/// Windows masaüstünde [DesktopPosView] (çift panel, USB HID odağı, kısayollar),
/// Android telefon ve tablette [MobilePosView] (tek elle kullanım, başparmak
/// bölgesi sabit ödeme barı, harici HID tarayıcı desteği) görünümlerini ortak
/// [cartProvider] üzerinden sunar.
class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();
  final HardwareBarcodeBuffer _hidBuffer = HardwareBarcodeBuffer();
  int _activeModalCount = 0;
  bool _isSubmittingBarcode = false;

  static final Map<LogicalKeyboardKey, String> _digitKeyFallback = {
    LogicalKeyboardKey.digit0: '0',
    LogicalKeyboardKey.digit1: '1',
    LogicalKeyboardKey.digit2: '2',
    LogicalKeyboardKey.digit3: '3',
    LogicalKeyboardKey.digit4: '4',
    LogicalKeyboardKey.digit5: '5',
    LogicalKeyboardKey.digit6: '6',
    LogicalKeyboardKey.digit7: '7',
    LogicalKeyboardKey.digit8: '8',
    LogicalKeyboardKey.digit9: '9',
    LogicalKeyboardKey.numpad0: '0',
    LogicalKeyboardKey.numpad1: '1',
    LogicalKeyboardKey.numpad2: '2',
    LogicalKeyboardKey.numpad3: '3',
    LogicalKeyboardKey.numpad4: '4',
    LogicalKeyboardKey.numpad5: '5',
    LogicalKeyboardKey.numpad6: '6',
    LogicalKeyboardKey.numpad7: '7',
    LogicalKeyboardKey.numpad8: '8',
    LogicalKeyboardKey.numpad9: '9',
  };

  static final Set<LogicalKeyboardKey> _functionKeys = {
    LogicalKeyboardKey.f1,
    LogicalKeyboardKey.f2,
    LogicalKeyboardKey.f3,
    LogicalKeyboardKey.f4,
    LogicalKeyboardKey.f5,
    LogicalKeyboardKey.f6,
    LogicalKeyboardKey.f7,
    LogicalKeyboardKey.f8,
    LogicalKeyboardKey.f9,
    LogicalKeyboardKey.f10,
    LogicalKeyboardKey.f11,
    LogicalKeyboardKey.f12,
  };

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleHardwareKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeyEvent);
    _hidBuffer.reset();
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    super.dispose();
  }

  bool get _isIdle => _activeModalCount == 0;

  void _refocusBarcodeIfIdle() {
    final keepFocus = ref.read(mmsUiProfileProvider).keepBarcodeFieldFocused;
    if (!mounted || !_isIdle || !keepFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isIdle && _barcodeFocusNode.canRequestFocus) {
        _barcodeFocusNode.requestFocus();
      }
    });
  }

  String? _extractHidCharacter(KeyDownEvent event) {
    final char = event.character;
    if (char != null &&
        char.length == 1 &&
        RegExp(r'^[\x21-\x7E]$').hasMatch(char)) {
      return char;
    }
    return _digitKeyFallback[event.logicalKey];
  }

  bool _hasActiveEditableFocus() {
    if (_barcodeFocusNode.hasFocus) return true;
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return false;
    return focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null ||
        focusContext.findAncestorStateOfType<EditableTextState>() != null;
  }

  bool _handleHardwareKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!mounted || !_isIdle) {
      _hidBuffer.reset();
      return false;
    }
    if (ref.read(activeDestinationProvider) != AppDestination.pos) {
      _hidBuffer.reset();
      return false;
    }

    final uiProfile = ref.read(mmsUiProfileProvider);
    if (!uiProfile.enableGlobalHidScannerCapture) return false;

    if (_hasActiveEditableFocus()) {
      _hidBuffer.reset();
      return false;
    }

    final hardwareKeyboard = HardwareKeyboard.instance;
    if (hardwareKeyboard.isControlPressed ||
        hardwareKeyboard.isAltPressed ||
        hardwareKeyboard.isMetaPressed) {
      _hidBuffer.reset();
      return false;
    }

    if (_functionKeys.contains(event.logicalKey)) {
      _hidBuffer.reset();
      return false;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _hidBuffer.reset();
      if (!uiProfile.enableDesktopFunctionShortcuts) {
        _handleEscapeWhenIdle();
        return true;
      }
      return false;
    }

    final isTerminator =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
        (event.logicalKey == LogicalKeyboardKey.tab &&
            _hidBuffer.hasBufferedInput);
    if (isTerminator) {
      final scanned = _hidBuffer.commit();
      if (scanned != null) {
        unawaited(_submitScannedBarcode(scanned));
        return true;
      }
      return false;
    }

    final ch = _extractHidCharacter(event);
    if (ch != null) {
      _hidBuffer.feedCharacter(ch);
    }
    return false;
  }

  Future<T?> _showPosModal<T>(
    WidgetBuilder builder, {
    bool barrierDismissible = true,
  }) async {
    if (!mounted) return null;
    _hidBuffer.reset();
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
    if (!_isIdle || _isSubmittingBarcode) return;
    final raw = _barcodeController.text;
    if (BarcodeInputSanitizer.stripControlChars(raw).trim().isEmpty) {
      _barcodeController.clear();
      _refocusBarcodeIfIdle();
      return;
    }
    _barcodeController.clear();
    await _submitScannedBarcode(raw);
  }

  Future<void> _submitScannedBarcode(String raw) async {
    if (!_isIdle || _isSubmittingBarcode) return;
    _isSubmittingBarcode = true;
    try {
      await ref.read(cartProvider.notifier).scanBarcode(raw);
    } finally {
      _isSubmittingBarcode = false;
      _refocusBarcodeIfIdle();
    }
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
    final showKeyboardHints =
        ref.read(mmsUiProfileProvider).showKeyboardShortcuts;
    await _showPosModal<void>(
      (_) => ProductSearchDialog(
        repository: repo,
        showKeyboardHints: showKeyboardHints,
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
    final showKeyboardHints =
        ref.read(mmsUiProfileProvider).showKeyboardShortcuts;

    await _showPosModal<void>(
      (_) => QuantityEditDialog(
        item: item,
        showKeyboardHints: showKeyboardHints,
        onValidateAndApply: (rawQuantity) {
          final ok = ref
              .read(cartProvider.notifier)
              .updateQuantityFromInput(
                productId: item.productId,
                rawQuantity: rawQuantity,
              );
          if (!ok) {
            return ref.read(cartProvider).errorMessage ??
                'Miktar güncellenemedi.';
          }
          return null;
        },
      ),
    );
  }

  Future<void> _openClearCartDialog() async {
    if (!_isIdle || ref.read(cartProvider).isEmpty) return;
    final colors = context.mmsColors;
    final showKeyboardHints =
        ref.read(mmsUiProfileProvider).showKeyboardShortcuts;

    final confirmed = await _showPosModal<bool>(
      (dialogContext) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(dialogContext).pop(false),
        },
        child: AppDialog(
          key: const Key('clear_cart_confirm_dialog'),
          title: 'Sepeti Temizle',
          icon: Icons.delete_sweep_rounded,
          iconColor: colors.danger,
          maxWidth: 440,
          content: Text(
            'Sepetteki tüm ürünleri kaldırmak istediğinize emin misiniz?',
            style: TextStyle(fontSize: 14, color: colors.textSecondary),
          ),
          actions: [
            AppButton(
              label: showKeyboardHints ? 'Vazgeç [Esc]' : 'Vazgeç',
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            AppButton(
              key: const Key('clear_cart_confirm_yes'),
              label: 'Sepeti Temizle',
              variant: AppButtonVariant.danger,
              onPressed: () => Navigator.of(dialogContext).pop(true),
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
    final showKeyboardHints =
        ref.read(mmsUiProfileProvider).showKeyboardShortcuts;

    await _showPosModal<PosCompletedSale>(
      (_) => PaymentDialog(
        totalCents: cartState.totalCents,
        initialMethod: method,
        showKeyboardHints: showKeyboardHints,
        onConfirmSale:
            ({
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

  Future<void> _openCameraBarcodeScanner() async {
    if (!_isIdle || _isSubmittingBarcode) return;
    _hidBuffer.reset();
    _activeModalCount++;
    _barcodeFocusNode.canRequestFocus = false;
    _barcodeFocusNode.unfocus();

    CameraScanResult scanResult;
    try {
      // Faz 2 §4.1: Kamera açık kalır; her okunan ürün doğrudan sepete eklenir,
      // aynı ürün tekrar okutulunca satır miktarı artar.
      scanResult = await ref.read(cameraBarcodeScannerProvider).scanContinuously(
        context,
        title: 'Kasada Barkod Tara',
        subtitle: 'Ürünleri sırayla çerçeveye hizalayın; bitince "Taramayı Bitir"',
        onBarcode: _addCameraBarcodeToCart,
      );
    } finally {
      _activeModalCount--;
      if (mounted && _isIdle) {
        _barcodeFocusNode.canRequestFocus = true;
        _refocusBarcodeIfIdle();
      }
    }

    if (!mounted) return;
    switch (scanResult.status) {
      case CameraScanStatus.scanned:
        if (scanResult.barcode != null) {
          await _addCameraBarcodeToCart(scanResult.barcode!);
        }
        break;
      case CameraScanStatus.permissionDenied:
      case CameraScanStatus.error:
      case CameraScanStatus.unsupportedPlatform:
        AppSnackbar.show(
          context,
          message:
              scanResult.errorMessage ?? 'Kamera ile barkod okunamadı.',
          tone: AppBadgeTone.warning,
        );
        break;
      case CameraScanStatus.cancelled:
        break;
    }
  }

  /// Kamera ile okunan barkodu yerel katalogda arar ve sepete ekler; tarayıcıda
  /// gösterilecek geri bildirimi döner. İnternet/Hub gerektirmez.
  Future<ScanFeedback> _addCameraBarcodeToCart(String barcode) async {
    final notifier = ref.read(cartProvider.notifier);
    final added = await notifier.scanBarcode(barcode);
    final cart = ref.read(cartProvider);
    if (added) {
      final item = cart.selectedItem;
      if (item == null) return const ScanFeedback.success('Ürün sepete eklendi.');
      return ScanFeedback.success(
        'Sepete eklendi: ${item.productName} · '
        '${Money.formatMilliWithUnit(item.quantityMilli, item.pricingUnit)}',
      );
    }
    final message = cart.errorMessage ?? 'Barkod sepete eklenemedi.';
    return message.contains('bulunamadı')
        ? ScanFeedback.notFound('Ürün bulunamadı: $barcode')
        : ScanFeedback.error(message);
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
    final syncState = ref.watch(backgroundSyncCoordinatorProvider);
    final uiProfile = ref.watch(mmsUiProfileProvider);
    final useMobilePos = uiProfile.useMobileLayout(context.windowClass);

    void toggleNumpad() {
      ref.read(posPreferencesProvider.notifier).toggleVirtualNumpad();
      _refocusBarcodeIfIdle();
    }

    void retrySync() {
      ref.read(systemStatusProvider.notifier).refreshStatus();
      ref
          .read(backgroundSyncCoordinatorProvider.notifier)
          .triggerSync(reason: SyncTriggerReason.manual);
    }

    void clearMessages() {
      ref.read(cartProvider.notifier).clearMessages();
      _refocusBarcodeIfIdle();
    }

    void selectProduct(String productId) {
      ref.read(cartProvider.notifier).selectProduct(productId);
      _refocusBarcodeIfIdle();
    }

    void incrementProduct(String productId) {
      ref.read(cartProvider.notifier).incrementProduct(productId);
      _refocusBarcodeIfIdle();
    }

    void decrementProduct(String productId) {
      ref.read(cartProvider.notifier).decrementProduct(productId);
      _refocusBarcodeIfIdle();
    }

    void editItemQuantity(CartItem item) {
      ref.read(cartProvider.notifier).selectProduct(item.productId);
      _openQuantityDialog(item);
    }

    void removeProduct(String productId) {
      ref.read(cartProvider.notifier).removeProduct(productId);
      _refocusBarcodeIfIdle();
    }

    if (useMobilePos) {
      return MobilePosView(
        barcodeController: _barcodeController,
        barcodeFocusNode: _barcodeFocusNode,
        cartState: cartState,
        showVirtualNumpad: prefsState.showVirtualNumpad,
        systemStatus: systemStatus,
        syncState: syncState,
        onSubmitBarcode: _submitBarcode,
        onAppendNumpadChar: _appendNumpadChar,
        onBackspaceNumpad: _backspaceNumpad,
        onClearBarcode: _barcodeController.clear,
        onOpenCameraScanner: uiProfile.supportsCameraBarcodeScanning
            ? _openCameraBarcodeScanner
            : null,
        onToggleVirtualNumpad: toggleNumpad,
        onOpenProductSearch: _openProductSearchDialog,
        onEditItemQuantity: editItemQuantity,
        onOpenClearCartDialog: _openClearCartDialog,
        onOpenPaymentDialog: _openPaymentDialog,
        onRetrySync: retrySync,
        onClearMessages: clearMessages,
        onSelectProduct: selectProduct,
        onIncrementProduct: incrementProduct,
        onDecrementProduct: decrementProduct,
        onRemoveProduct: removeProduct,
      );
    }

    return DesktopPosView(
      barcodeController: _barcodeController,
      barcodeFocusNode: _barcodeFocusNode,
      enableBarcodeAutofocus: uiProfile.enableHardwareBarcodeAutofocus,
      cartState: cartState,
      showVirtualNumpad: prefsState.showVirtualNumpad,
      systemStatus: systemStatus,
      syncState: syncState,
      onSubmitBarcode: _submitBarcode,
      onAppendNumpadChar: _appendNumpadChar,
      onBackspaceNumpad: _backspaceNumpad,
      onClearBarcode: _barcodeController.clear,
      onToggleVirtualNumpad: toggleNumpad,
      onOpenProductSearch: _openProductSearchDialog,
      onOpenHelpDialog: _openHelpDialog,
      onOpenDefaultQuantityDialog: () => _openQuantityDialog(),
      onEditItemQuantity: editItemQuantity,
      onOpenClearCartDialog: _openClearCartDialog,
      onOpenPaymentDialog: _openPaymentDialog,
      onHandleEscape: _handleEscapeWhenIdle,
      onRetrySync: retrySync,
      onClearMessages: clearMessages,
      onSelectProduct: selectProduct,
      onIncrementProduct: incrementProduct,
      onDecrementProduct: decrementProduct,
      onRemoveProduct: removeProduct,
    );
  }
}
