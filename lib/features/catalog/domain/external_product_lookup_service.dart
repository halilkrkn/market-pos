import 'external_product_suggestion.dart';

/// Harici ürün bilgi servisi sözleşmesi (Clean Architecture Domain Port).
abstract interface class ExternalProductLookupService {
  Future<ExternalProductLookupResult> lookupByBarcode(String barcode);
}
