import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../../pos/domain/barcode_input_sanitizer.dart';
import '../domain/stock_receipt_input.dart';

enum StockReceiptPhase { idle, lookingUp, productFound, notFound, saving, saved }

@immutable
class StockReceiptState {
  final StockReceiptPhase phase;
  final LocalProduct? product;
  final String? scannedBarcode;
  final String? message;
  final bool isError;
  final StockReceiptResult? lastResult;

  const StockReceiptState({
    this.phase = StockReceiptPhase.idle,
    this.product,
    this.scannedBarcode,
    this.message,
    this.isError = false,
    this.lastResult,
  });

  bool get canSubmit =>
      product != null &&
      (phase == StockReceiptPhase.productFound || phase == StockReceiptPhase.saved);

  StockReceiptState copyWith({
    StockReceiptPhase? phase,
    LocalProduct? product,
    bool clearProduct = false,
    String? scannedBarcode,
    String? message,
    bool clearMessage = false,
    bool? isError,
    StockReceiptResult? lastResult,
    bool clearLastResult = false,
  }) {
    return StockReceiptState(
      phase: phase ?? this.phase,
      product: clearProduct ? null : (product ?? this.product),
      scannedBarcode: scannedBarcode ?? this.scannedBarcode,
      message: clearMessage ? null : (message ?? this.message),
      isError: isError ?? this.isError,
      lastResult: clearLastResult ? null : (lastResult ?? this.lastResult),
    );
  }
}

/// Mevcut ürüne barkodla stok girişi akışını yönetir (Faz 2 §4.3).
///
/// Idempotency: Her giriş için bir `receiptId` üretilir ve yalnızca başarılı
/// kayıttan sonra yenilenir. Böylece çift dokunma veya hata sonrası tekrar
/// deneme aynı girişi ikinci kez uygulamaz.
class StockReceiptNotifier extends StateNotifier<StockReceiptState> {
  final ClientStorageRepository repository;
  final String Function() readDeviceId;
  final Future<void> Function()? onStockCommitted;

  static final Random _random = Random.secure();
  String _pendingReceiptId;
  bool _submitting = false;

  StockReceiptNotifier({
    required this.repository,
    required this.readDeviceId,
    this.onStockCommitted,
  })  : _pendingReceiptId = _newReceiptId(readDeviceId()),
        super(const StockReceiptState());

  static String _newReceiptId(String deviceId) {
    final nonce = _random.nextInt(0x7fffffff).toRadixString(36);
    final safeDevice = deviceId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return 'rcpt_${safeDevice}_${DateTime.now().microsecondsSinceEpoch}_$nonce';
  }

  Future<void> lookupBarcode(String rawBarcode) async {
    final sanitized = BarcodeInputSanitizer.sanitize(rawBarcode);
    if (!sanitized.isValid) {
      state = state.copyWith(
        phase: StockReceiptPhase.idle,
        clearProduct: true,
        message: sanitized.errorMessage ?? 'Geçersiz barkod.',
        isError: true,
      );
      return;
    }
    final barcode = sanitized.normalized;
    state = state.copyWith(
      phase: StockReceiptPhase.lookingUp,
      scannedBarcode: barcode,
      clearMessage: true,
      isError: false,
      clearLastResult: true,
    );

    final LocalProduct? product;
    try {
      product = await repository.getProductByBarcode(barcode);
    } catch (e, stack) {
      debugPrint('[StockReceipt] Barkod sorgu hatası: $e\n$stack');
      if (!mounted) return;
      state = state.copyWith(
        phase: StockReceiptPhase.idle,
        clearProduct: true,
        message: 'Barkod sorgulanırken beklenmeyen bir hata oluştu.',
        isError: true,
      );
      return;
    }
    if (!mounted) return;

    if (product == null) {
      state = state.copyWith(
        phase: StockReceiptPhase.notFound,
        clearProduct: true,
        message: 'Bu barkoda ($barcode) kayıtlı ürün bulunamadı. Yeni ürün olarak ekleyebilirsiniz.',
        isError: true,
      );
      return;
    }
    if (!product.isActive) {
      state = state.copyWith(
        phase: StockReceiptPhase.idle,
        clearProduct: true,
        message: '"${product.name}" pasif durumda; stok girişi yapılamaz.',
        isError: true,
      );
      return;
    }

    if (state.product?.id != product.id) {
      _pendingReceiptId = _newReceiptId(readDeviceId());
    }
    state = state.copyWith(
      phase: StockReceiptPhase.productFound,
      product: product,
      clearMessage: true,
      isError: false,
    );
  }

  /// Girilen miktarı seçili ürünün mevcut stoğuna ekler. Başarılıysa `true`.
  Future<bool> submit({
    required String rawQuantity,
    String? rawPurchasePrice,
    String? rawNote,
  }) async {
    final product = state.product;
    if (product == null || !state.canSubmit) {
      state = state.copyWith(message: 'Önce ürün barkodunu okutun.', isError: true);
      return false;
    }
    if (_submitting) return false; // Çift dokunma koruması
    final input = StockReceiptInput.parse(
      rawQuantity: rawQuantity,
      rawPurchasePrice: rawPurchasePrice,
      rawNote: rawNote,
      stockUnit: product.stockUnit,
    );
    if (!input.isValid) {
      state = state.copyWith(message: input.errorMessage, isError: true);
      return false;
    }

    _submitting = true;
    final receiptId = _pendingReceiptId;
    state = state.copyWith(phase: StockReceiptPhase.saving, clearMessage: true, isError: false);
    try {
      final result = await repository.receiveStock(
        receiptId: receiptId,
        productId: product.id,
        quantityMilli: input.quantityMilli!,
        unitPurchasePrice: input.purchasePriceCents,
        note: input.note,
        deviceId: readDeviceId(),
      );
      final refreshed = await repository.getProductById(product.id);
      _pendingReceiptId = _newReceiptId(readDeviceId());
      if (!mounted) return true;
      state = state.copyWith(
        phase: StockReceiptPhase.saved,
        product: refreshed ?? product,
        lastResult: result,
        message: result.isDuplicate
            ? 'Bu giriş daha önce kaydedilmişti; stok tekrar artırılmadı.'
            : 'Stok girişi kaydedildi.',
        isError: false,
      );
      final callback = onStockCommitted;
      if (callback != null) {
        await callback();
      }
      return true;
    } on ArgumentError catch (e) {
      if (mounted) {
        state = state.copyWith(
          phase: StockReceiptPhase.productFound,
          message: e.message?.toString() ?? 'Geçersiz stok girişi.',
          isError: true,
        );
      }
      return false;
    } on StateError catch (e) {
      if (mounted) {
        state = state.copyWith(
          phase: StockReceiptPhase.productFound,
          message: e.message,
          isError: true,
        );
      }
      return false;
    } catch (e, stack) {
      debugPrint('[StockReceipt] Kayıt hatası: $e\n$stack');
      if (mounted) {
        // receiptId korunur: kullanıcı tekrar denerse aynı giriş ikinci kez uygulanmaz.
        state = state.copyWith(
          phase: StockReceiptPhase.productFound,
          message: 'Stok girişi kaydedilemedi. Lütfen tekrar deneyin.',
          isError: true,
        );
      }
      return false;
    } finally {
      _submitting = false;
    }
  }

  void reset() {
    _pendingReceiptId = _newReceiptId(readDeviceId());
    state = const StockReceiptState();
  }
}
