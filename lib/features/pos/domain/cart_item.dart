import 'money.dart';
import 'pos_exceptions.dart';
import 'pos_product.dart';

/// Sepet içindeki tekil ürün satırını temsil eden saf Dart değişmez varlık (`BR-POS-11`).
class CartItem {
  final String productId;
  final String? barcode;
  final String productName;
  final int unitPriceCents;
  final String priceVersionId;
  final String pricingUnit;
  final String stockUnit;
  final int currentStockMilli;
  final int conversionFactorNumerator;
  final int conversionFactorDenominator;
  final int quantityMilli;

  CartItem({
    required this.productId,
    required this.barcode,
    required this.productName,
    required this.unitPriceCents,
    required this.priceVersionId,
    required this.pricingUnit,
    required this.stockUnit,
    required this.currentStockMilli,
    required this.conversionFactorNumerator,
    required this.conversionFactorDenominator,
    required this.quantityMilli,
  }) {
    if (productId.isEmpty) {
      throw const PosDomainException('Ürün kimliği boş olamaz.');
    }
    if (unitPriceCents < 0) {
      throw PosDomainException('Birim fiyat negatif olamaz: $unitPriceCents');
    }
    if (quantityMilli <= 0 || quantityMilli > Money.maxQuantityMilli) {
      throw PosDomainException(
        'Sepet satırı miktarı geçersiz: $quantityMilli',
      );
    }
    if (conversionFactorNumerator <= 0 || conversionFactorDenominator <= 0) {
      throw PosDomainException(
        'Geçersiz birim dönüşüm oranı: $conversionFactorNumerator/$conversionFactorDenominator',
      );
    }
  }

  factory CartItem.fromProduct(
    PosProduct product, {
    int quantityMilli = Money.quantityScale,
  }) {
    if (!product.isActive) {
      throw PosDomainException(
        'Pasif ürün satışa eklenemez: ${product.name}',
      );
    }
    if (product.priceCents < 0) {
      throw PosDomainException(
        'Negatif fiyatlı ürün satışa eklenemez: ${product.name}',
      );
    }
    product.validateQuantityConversion(quantityMilli);
    return CartItem(
      productId: product.id,
      barcode: product.primaryBarcode,
      productName: product.name,
      unitPriceCents: product.priceCents,
      priceVersionId: product.priceVersionId,
      pricingUnit: product.pricingUnit,
      stockUnit: product.stockUnit,
      currentStockMilli: product.stockMilli,
      conversionFactorNumerator: product.conversionFactorNumerator,
      conversionFactorDenominator: product.conversionFactorDenominator,
      quantityMilli: quantityMilli,
    );
  }

  /// Half-Up satır toplamı (kuruş).
  int get lineTotalCents => Money.calculateLineTotalHalfUp(
        unitPriceCents: unitPriceCents,
        quantityMilli: quantityMilli,
      );

  /// Satış tamamlandığında stoktan düşülecek milli-birim miktarı.
  int get stockDeltaMilli =>
      (quantityMilli * conversionFactorNumerator) ~/ conversionFactorDenominator;

  /// Satış sonrası beklenen stok düzeyi (`INV-04`: eksiye düşebilir).
  int get projectedRemainingStockMilli => currentStockMilli - stockDeltaMilli;

  bool get isCurrentStockNonPositive => currentStockMilli <= 0;

  bool get isNegativeStockAfterCart => projectedRemainingStockMilli < 0;

  void validateConversionForQuantity(int newQuantityMilli) {
    if (newQuantityMilli <= 0 || newQuantityMilli > Money.maxQuantityMilli) {
      throw const PosDomainException(
        'Miktar 0\'dan büyük ve izin verilen üst sınır içinde olmalıdır.',
      );
    }
    if (newQuantityMilli > Money.maxSafeInt ~/ conversionFactorNumerator) {
      throw const PosDomainException(
        'Miktar ve birim katsayısı çarpımı tamsayı sınırını aşıyor.',
      );
    }
    final prodMilli = newQuantityMilli * conversionFactorNumerator;
    if (prodMilli % conversionFactorDenominator != 0) {
      throw PosDomainException(
        '"$productName" için girilen miktar stok birimine ($stockUnit) tam bölünmüyor (payda: $conversionFactorDenominator).',
      );
    }
    // Çarpım taşma ön kontrolü
    Money.calculateLineTotalHalfUp(
      unitPriceCents: unitPriceCents,
      quantityMilli: newQuantityMilli,
    );
  }

  CartItem copyWith({int? quantityMilli}) {
    final nextQty = quantityMilli ?? this.quantityMilli;
    validateConversionForQuantity(nextQty);
    return CartItem(
      productId: productId,
      barcode: barcode,
      productName: productName,
      unitPriceCents: unitPriceCents,
      priceVersionId: priceVersionId,
      pricingUnit: pricingUnit,
      stockUnit: stockUnit,
      currentStockMilli: currentStockMilli,
      conversionFactorNumerator: conversionFactorNumerator,
      conversionFactorDenominator: conversionFactorDenominator,
      quantityMilli: nextQty,
    );
  }
}

