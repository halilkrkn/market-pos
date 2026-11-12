/// Satış sırasında sepet fiyatı/sürümü ile güncel yerel DB fiyatı/sürümü uyuşmadığında fırlatılır.
class PriceChangedException implements Exception {
  final String productId;
  final String productName;
  final int? expectedUnitPrice;
  final int actualUnitPrice;
  final String? expectedPriceVersionId;
  final String actualPriceVersionId;
  final String message;

  const PriceChangedException({
    required this.productId,
    required this.productName,
    required this.expectedUnitPrice,
    required this.actualUnitPrice,
    required this.expectedPriceVersionId,
    required this.actualPriceVersionId,
    required this.message,
  });

  @override
  String toString() => 'PriceChangedException: $message';
}

