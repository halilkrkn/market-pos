import 'package:flutter/foundation.dart';

/// Open Food Facts ürün besin değerleri özeti (100g/100ml bazında Salt Okuma).
@immutable
class NutritionFactsSummary {
  final String? energyKcal100g;
  final String? fat100g;
  final String? carbohydrates100g;
  final String? sugars100g;
  final String? proteins100g;
  final String? salt100g;

  const NutritionFactsSummary({
    this.energyKcal100g,
    this.fat100g,
    this.carbohydrates100g,
    this.sugars100g,
    this.proteins100g,
    this.salt100g,
  });

  bool get isEmpty =>
      energyKcal100g == null &&
      fat100g == null &&
      carbohydrates100g == null &&
      sugars100g == null &&
      proteins100g == null &&
      salt100g == null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NutritionFactsSummary &&
          runtimeType == other.runtimeType &&
          energyKcal100g == other.energyKcal100g &&
          fat100g == other.fat100g &&
          carbohydrates100g == other.carbohydrates100g &&
          sugars100g == other.sugars100g &&
          proteins100g == other.proteins100g &&
          salt100g == other.salt100g;

  @override
  int get hashCode => Object.hash(
    energyKcal100g,
    fat100g,
    carbohydrates100g,
    sugars100g,
    proteins100g,
    salt100g,
  );
}

/// Harici ürün bilgi kaynağından (Open Food Facts) dönen kullanıcı düzenlemesine
/// tabi ürün öneri modeli. Satış fiyatı, maliyet veya stok bilgisi ASLA içermez.
@immutable
class ExternalProductSuggestion {
  final String barcode;
  final String productName;
  final String? brand;
  final List<String> categories;
  final String? imageUrl;
  final String? ingredientsText;
  final String? quantityText;
  final String? suggestedUnit;
  final NutritionFactsSummary? nutrition;
  final String sourceLabel;

  const ExternalProductSuggestion({
    required this.barcode,
    required this.productName,
    this.brand,
    this.categories = const [],
    this.imageUrl,
    this.ingredientsText,
    this.quantityText,
    this.suggestedUnit,
    this.nutrition,
    this.sourceLabel = 'Open Food Facts',
  });

  /// Marka ve ürün adını tekrar etmeden formda düzenlenebilir öneri adına birleştirir.
  String get suggestedDisplayName {
    final cleanName = productName.trim();
    final cleanBrand = brand?.trim() ?? '';
    final cleanQty = quantityText?.trim() ?? '';

    var base = cleanName;
    if (cleanBrand.isNotEmpty) {
      final lowerName = cleanName.toLowerCase();
      final lowerBrand = cleanBrand.toLowerCase();
      if (cleanName.isEmpty) {
        base = cleanBrand;
      } else if (!lowerName.contains(lowerBrand)) {
        base = '$cleanBrand $cleanName';
      }
    }

    if (cleanQty.isNotEmpty &&
        !base.toLowerCase().contains(cleanQty.toLowerCase())) {
      base = '$base $cleanQty'.trim();
    }
    return base.trim();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExternalProductSuggestion &&
          runtimeType == other.runtimeType &&
          barcode == other.barcode &&
          productName == other.productName &&
          brand == other.brand &&
          listEquals(categories, other.categories) &&
          imageUrl == other.imageUrl &&
          ingredientsText == other.ingredientsText &&
          quantityText == other.quantityText &&
          suggestedUnit == other.suggestedUnit &&
          nutrition == other.nutrition &&
          sourceLabel == other.sourceLabel;

  @override
  int get hashCode => Object.hash(
    barcode,
    productName,
    brand,
    Object.hashAll(categories),
    imageUrl,
    ingredientsText,
    quantityText,
    suggestedUnit,
    nutrition,
    sourceLabel,
  );
}

enum ExternalProductLookupStatus {
  found,
  notFound,
  invalidBarcode,
  error,
}

@immutable
class ExternalProductLookupResult {
  final ExternalProductLookupStatus status;
  final String barcode;
  final ExternalProductSuggestion? suggestion;
  final String? message;

  const ExternalProductLookupResult._({
    required this.status,
    required this.barcode,
    this.suggestion,
    this.message,
  });

  ExternalProductLookupResult.found(ExternalProductSuggestion suggestion)
    : this._(
        status: ExternalProductLookupStatus.found,
        barcode: suggestion.barcode,
        suggestion: suggestion,
      );

  const ExternalProductLookupResult.notFound(String barcode, {String? message})
    : this._(
        status: ExternalProductLookupStatus.notFound,
        barcode: barcode,
        message:
            message ??
            'Bu barkod Open Food Facts kataloğunda bulunamadı. Ürün bilgilerini elle girebilirsiniz.',
      );

  const ExternalProductLookupResult.invalidBarcode(
    String barcode, {
    String? message,
  }) : this._(
         status: ExternalProductLookupStatus.invalidBarcode,
         barcode: barcode,
         message:
             message ?? 'Harici sorgu için geçerli bir barkod giriniz.',
       );

  const ExternalProductLookupResult.error(String barcode, {String? message})
    : this._(
        status: ExternalProductLookupStatus.error,
        barcode: barcode,
        message:
            message ??
            'Open Food Facts bağlantısı kurulamadı. Çevrimdışı olarak ürün bilgilerini elle girebilirsiniz.',
      );

  bool get isFound =>
      status == ExternalProductLookupStatus.found && suggestion != null;
}
