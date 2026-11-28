import 'package:mms_client_storage/mms_client_storage.dart';

import '../../../core/storage/local_database_service.dart';
import '../domain/catalog_repository.dart';

export '../domain/catalog_repository.dart';

class LocalCatalogRepository implements CatalogRepository {
  final LocalDatabaseService _dbService;

  LocalCatalogRepository(this._dbService);

  ClientStorageRepository get _repo => _dbService.repository;

  @override
  Future<List<LocalCategory>> getCategories({bool includeInactive = false}) =>
      _repo.getCategories(includeInactive: includeInactive);

  @override
  Future<LocalCategory?> getCategoryById(String id) =>
      _repo.getCategoryById(id);

  @override
  Future<LocalCategory> createCategory({
    required String name,
    String? parentId,
    String? deviceId,
  }) => _repo.createCategory(
    name: name,
    parentId: parentId,
    deviceId: deviceId,
  );

  @override
  Future<void> updateCategory({
    required String id,
    required String name,
    String? parentId,
    bool? isActive,
    String? deviceId,
  }) => _repo.updateCategory(
    id: id,
    name: name,
    parentId: parentId,
    isActive: isActive,
    deviceId: deviceId,
  );

  @override
  Future<void> deactivateCategory(String id, {String? deviceId}) =>
      _repo.deactivateCategory(id, deviceId: deviceId);

  @override
  Future<List<LocalProduct>> getProducts({
    String? searchQuery,
    String? categoryId,
    bool? isActive,
    int limit = 100,
    int offset = 0,
  }) => _repo.getProducts(
    searchQuery: searchQuery,
    categoryId: categoryId,
    isActive: isActive,
    limit: limit,
    offset: offset,
  );

  @override
  Future<LocalProduct?> getProductById(String id) => _repo.getProductById(id);

  @override
  Future<LocalProduct?> getProductByBarcode(String barcode) =>
      _repo.getProductByBarcode(barcode);

  @override
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
  }) => _repo.createProduct(
    initialPurchasePrice: initialPurchasePrice,
    name: name,
    price: price,
    barcode: barcode,
    categoryId: categoryId,
    initialStock: initialStock,
    stockUnit: stockUnit,
    pricingUnit: pricingUnit,
    conversionFactorNumerator: conversionFactorNumerator,
    conversionFactorDenominator: conversionFactorDenominator,
    vatRate: vatRate,
    deviceId: deviceId,
  );

  @override
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
  }) => _repo.updateProduct(
    id: id,
    name: name,
    price: price,
    categoryId: categoryId,
    barcode: barcode,
    clearBarcode: clearBarcode,
    stockUnit: stockUnit,
    pricingUnit: pricingUnit,
    conversionFactorNumerator: conversionFactorNumerator,
    conversionFactorDenominator: conversionFactorDenominator,
    vatRate: vatRate,
    isActive: isActive,
    priceChangeReason: priceChangeReason,
    deviceId: deviceId,
  );

  @override
  Future<void> deactivateProduct(String id, {String? deviceId}) =>
      _repo.deactivateProduct(id, deviceId: deviceId);

  @override
  Future<List<LocalProductBarcode>> getBarcodesForProduct(String productId) =>
      _repo.getBarcodesForProduct(productId);

  @override
  Future<void> addProductBarcode({
    required String productId,
    required String barcode,
    bool isPrimary = false,
    String? deviceId,
  }) => _repo.addProductBarcode(
    productId: productId,
    barcode: barcode,
    isPrimary: isPrimary,
    deviceId: deviceId,
  );

  @override
  Future<void> removeProductBarcode(String barcodeId, {String? deviceId}) =>
      _repo.removeProductBarcode(barcodeId, deviceId: deviceId);

  @override
  Future<ProductCatalogSyncStatus> getProductCatalogSyncStatus(
    String productId,
  ) => _repo.getProductCatalogSyncStatus(productId);

  @override
  Future<Map<String, ProductCatalogSyncStatus>>
  getCatalogSyncStatusByProduct() => _repo.getCatalogSyncStatusByProduct();

  @override
  Future<List<LocalPriceHistoryData>> getPriceHistory(String productId) =>
      _repo.getPriceHistory(productId);
}
