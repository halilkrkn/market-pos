import 'money.dart';
import 'pos_exceptions.dart';

/// POS sepeti ve katalog araması için saf Dart değişmez ürün modeli.
class PosProduct {
  final String id;
  final String? primaryBarcode;
  final String name;
  final int priceCents;
  final String priceVersionId;
  final int stockMilli;
  final String stockUnit;
  final String pricingUnit;
  final int conversionFactorNumerator;
  final int conversionFactorDenominator;
  final bool isActive;

  const PosProduct({
    required this.id,
    required this.primaryBarcode,
    required this.name,
    required this.priceCents,
    required this.priceVersionId,
    required this.stockMilli,
    required this.stockUnit,
    required this.pricingUnit,
    required this.conversionFactorNumerator,
    required this.conversionFactorDenominator,
    required this.isActive,
  });

  bool get isStockNonPositive => stockMilli <= 0;

  /// Verilen satış miktarının rasyonel birim dönüşüm paydasına tam bölünüp
  /// bölünmediğini taşma korumalı biçimde doğrular (`R-03`).
  void validateQuantityConversion(int quantityMilli) {
    if (quantityMilli <= 0 || quantityMilli > Money.maxQuantityMilli) {
      throw PosDomainException(
        'Miktar 0\'dan büyük ve en fazla ${Money.maxQuantityMilli ~/ Money.quantityScale} olabilir.',
      );
    }
    if (conversionFactorNumerator <= 0 || conversionFactorDenominator <= 0) {
      throw PosDomainException(
        '"$name" ürününün birim dönüşüm katsayısı geçersiz ($conversionFactorNumerator/$conversionFactorDenominator).',
      );
    }
    if (quantityMilli > Money.maxSafeInt ~/ conversionFactorNumerator) {
      throw const PosDomainException(
        'Miktar ve birim katsayısı çarpımı tamsayı sınırını aşıyor.',
      );
    }
    final prodMilli = quantityMilli * conversionFactorNumerator;
    if (prodMilli % conversionFactorDenominator != 0) {
      throw PosDomainException(
        '"$name" için girilen miktar stok birimine ($stockUnit) tam bölünmüyor (payda: $conversionFactorDenominator).',
      );
    }
  }

  /// Stok düşüm miktarını (`stock_unit` milli-birim) hesaplar.
  int calculateStockDeltaMilli(int quantityMilli) {
    validateQuantityConversion(quantityMilli);
    return (quantityMilli * conversionFactorNumerator) ~/
        conversionFactorDenominator;
  }
}
