import 'package:mms_client_storage/mms_client_storage.dart';

/// Katalog ve barkod yönetimi domain depo sözleşmesi (DIP).
abstract interface class CatalogRepository {
  Future<List<LocalCategory>> getCategories({bool includeInactive = false});
  Future<LocalCategory?> getCategoryById(String id);
  Future<LocalCategory> createCategory({required String name, String? parentId});
  Future<void> updateCategory({
    required String id,
    required String name,
    String? parentId,
    bool? isActive,
  });
  Future<void> deactivateCategory(String id);

  Future<List<LocalProduct>> getProducts({
    String? searchQuery,
    String? categoryId,
    bool? isActive,
    int limit = 100,
    int offset = 0,
  });
  Future<LocalProduct?> getProductById(String id);
  Future<LocalProduct?> getProductByBarcode(String barcode);
  Future<LocalProduct> createProduct({
    required String name,
    required int price,
    String? barcode,
    String? categoryId,
    int initialStock = 0,
    String stockUnit = 'adet',
    String pricingUnit = 'adet',
    int conversionFactorNumerator = 1,
    int conversionFactorDenominator = 1,
    int vatRate = 20,
    int? initialPurchasePrice,
    String? deviceId,
  });
  Future<LocalProduct> updateProduct({
    required String id,
    String? name,
    int? price,
    String? categoryId,
    String? barcode,
    bool clearBarcode = false,
    String? stockUnit,
    String? pricingUnit,
    int? conversionFactorNumerator,
    int? conversionFactorDenominator,
    int? vatRate,
    bool? isActive,
    String? priceChangeReason,
    String? deviceId,
  });
  Future<void> deactivateProduct(String id, {String? deviceId});
  Future<List<LocalProductBarcode>> getBarcodesForProduct(String productId);
  Future<void> addProductBarcode({
    required String productId,
    required String barcode,
    bool isPrimary = false,
    String? deviceId,
  });
  Future<void> removeProductBarcode(String barcodeId, {String? deviceId});

  /// Ürün bazlı katalog (`PRODUCT_UPSERT`) Hub gönderim durumu.
  Future<ProductCatalogSyncStatus> getProductCatalogSyncStatus(String productId);

  /// Eşitlenmemiş katalog değişikliği olan ürünlerin durumları (liste rozetleri için).
  Future<Map<String, ProductCatalogSyncStatus>> getCatalogSyncStatusByProduct();
  Future<List<LocalPriceHistoryData>> getPriceHistory(String productId);
}
