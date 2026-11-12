import 'cart_item.dart';
import 'money.dart';
import 'pos_exceptions.dart';
import 'pos_product.dart';
import 'pos_repository.dart';

/// POS sepetinin değişmez (immutable) durum modeli ve saf iş kuralları (`AGENTS.md` §3–4).
class CartState {
  static const Object _unset = Object();

  final List<CartItem> items;
  final String? selectedProductId;
  final bool isProcessing;
  final String? errorMessage;
  final String? infoMessage;
  final PosCompletedSale? lastCompletedSale;

  CartState._({
    required List<CartItem> items,
    this.selectedProductId,
    this.isProcessing = false,
    this.errorMessage,
    this.infoMessage,
    this.lastCompletedSale,
  }) : items = List<CartItem>.unmodifiable(items);

  factory CartState.empty({
    String? infoMessage,
    PosCompletedSale? lastCompletedSale,
  }) {
    return CartState._(
      items: const <CartItem>[],
      infoMessage: infoMessage,
      lastCompletedSale: lastCompletedSale,
    );
  }

  bool get isEmpty => items.isEmpty;

  int get lineCount => items.length;

  /// Kuruş cinsinden doğrulanmış sepet genel toplamı (`double` yok).
  int get totalCents {
    var sum = 0;
    for (final item in items) {
      sum = Money.safeAddCents(sum, item.lineTotalCents);
    }
    return sum;
  }

  bool get hasNegativeStockItems =>
      items.any((item) => item.isNegativeStockAfterCart || item.isCurrentStockNonPositive);

  /// Sepetin ödenebilir geçerli kalemlere sahip olup olmadığını doğrular (`0.00 TL` ve boş sepet hariç).
  bool get hasPayableItems =>
      items.isNotEmpty &&
      totalCents > 0 &&
      totalCents <= Money.maxTotalCents;

  /// İşlem devam etmiyorken ve sepet ödenebilir durumdayken ödeme başlatılabilir.
  bool get canCheckout => !isProcessing && hasPayableItems;

  CartItem? get selectedItem {
    if (items.isEmpty) return null;
    if (selectedProductId != null) {
      for (final item in items) {
        if (item.productId == selectedProductId) return item;
      }
    }
    return items.last;
  }

  /// Aktif ürünü sepete ekler; zaten varsa miktarı mevcut satırla birleştirir (`BR-POS-02`).
  CartState addProduct(
    PosProduct product, {
    int quantityMilli = Money.quantityScale,
  }) {
    if (!product.isActive) {
      throw PosDomainException('Pasif ürün satışa eklenemez: ${product.name}');
    }
    if (product.priceCents < 0) {
      throw PosDomainException(
        'Negatif fiyatlı ürün satışa eklenemez: ${product.name}',
      );
    }

    final existingIndex = items.indexWhere((i) => i.productId == product.id);
    if (existingIndex == -1) {
      final newItem = CartItem.fromProduct(
        product,
        quantityMilli: quantityMilli,
      );
      final nextItems = [...items, newItem];
      _validateCartTotal(nextItems);
      return copyWith(
        items: nextItems,
        selectedProductId: product.id,
        errorMessage: null,
        infoMessage: null,
      );
    }

    final existing = items[existingIndex];
    final combinedQty = existing.quantityMilli + quantityMilli;
    if (combinedQty > Money.maxQuantityMilli) {
      throw const PosDomainException('Sepet satır miktarı üst sınırı aşıyor.');
    }
    final updatedItem = existing.copyWith(quantityMilli: combinedQty);
    final nextItems = List<CartItem>.from(items)..[existingIndex] = updatedItem;
    _validateCartTotal(nextItems);
    return copyWith(
      items: nextItems,
      selectedProductId: product.id,
      errorMessage: null,
      infoMessage: null,
    );
  }

  /// Satır miktarını günceller; `quantityMilli <= 0` ise satırı sepetten kaldırır (`BR-POS-02`).
  CartState setQuantity({
    required String productId,
    required int quantityMilli,
  }) {
    final index = items.indexWhere((i) => i.productId == productId);
    if (index == -1) {
      throw const PosDomainException('Güncellenecek ürün sepette bulunamadı.');
    }
    if (quantityMilli <= 0) {
      return removeProduct(productId);
    }
    final updated = items[index].copyWith(quantityMilli: quantityMilli);
    final nextItems = List<CartItem>.from(items)..[index] = updated;
    _validateCartTotal(nextItems);
    return copyWith(
      items: nextItems,
      selectedProductId: productId,
      errorMessage: null,
      infoMessage: null,
    );
  }

  /// Satır miktarını `+1` birim (`1000` milli) artırır.
  CartState incrementProduct(String productId) {
    final index = items.indexWhere((i) => i.productId == productId);
    if (index == -1) return this;
    final current = items[index];
    final step = _stepSizeForItem(current);
    return setQuantity(
      productId: productId,
      quantityMilli: current.quantityMilli + step,
    );
  }

  /// Satır miktarını `1` adım azaltır; `<= 0` olursa satırı kaldırır.
  CartState decrementProduct(String productId) {
    final index = items.indexWhere((i) => i.productId == productId);
    if (index == -1) return this;
    final current = items[index];
    final step = _stepSizeForItem(current);
    return setQuantity(
      productId: productId,
      quantityMilli: current.quantityMilli - step,
    );
  }

  CartState removeProduct(String productId) {
    final nextItems = items.where((i) => i.productId != productId).toList();
    String? nextSelected = selectedProductId;
    if (nextSelected == productId) {
      nextSelected = nextItems.isEmpty ? null : nextItems.last.productId;
    }
    return copyWith(
      items: nextItems,
      selectedProductId: nextSelected,
      errorMessage: null,
      infoMessage: null,
    );
  }

  CartState selectProduct(String? productId) {
    return copyWith(selectedProductId: productId);
  }

  CartState copyWith({
    List<CartItem>? items,
    Object? selectedProductId = _unset,
    bool? isProcessing,
    Object? errorMessage = _unset,
    Object? infoMessage = _unset,
    Object? lastCompletedSale = _unset,
  }) {
    return CartState._(
      items: items ?? this.items,
      selectedProductId: identical(selectedProductId, _unset)
          ? this.selectedProductId
          : selectedProductId as String?,
      isProcessing: isProcessing ?? this.isProcessing,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      infoMessage: identical(infoMessage, _unset)
          ? this.infoMessage
          : infoMessage as String?,
      lastCompletedSale: identical(lastCompletedSale, _unset)
          ? this.lastCompletedSale
          : lastCompletedSale as PosCompletedSale?,
    );
  }

  static int _stepSizeForItem(CartItem item) {
    // Varsayılan tam birim adımı (+1000 milli); payda 1'den büyükse kayıpsız tam adım
    final den = item.conversionFactorDenominator;
    if (Money.quantityScale % den == 0) {
      return Money.quantityScale;
    }
    return den;
  }

  static void _validateCartTotal(List<CartItem> candidateItems) {
    var total = 0;
    for (final item in candidateItems) {
      total = Money.safeAddCents(total, item.lineTotalCents);
    }
    if (total > Money.maxTotalCents) {
      throw const PosDomainException(
        'Toplam sepet tutarı izin verilen üst sınırı aşıyor.',
      );
    }
  }
}

