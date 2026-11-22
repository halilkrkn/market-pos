import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import '../../../core/utils/user_friendly_error_mapper.dart';
import '../data/catalog_repository.dart';
import 'catalog_state.dart';

class CatalogNotifier extends StateNotifier<CatalogState> {
  final CatalogRepository _repository;
  final String _deviceId;
  final void Function()? onProductChanged;
  int _loadEpoch = 0;

  CatalogNotifier(
    this._repository,
    this._deviceId, {
    this.onProductChanged,
  }) : super(const CatalogState()) {
    init();
  }

  Future<void> init() async {
    await Future.wait([
      loadCategories(),
      loadProducts(),
    ]);
  }

  Future<void> loadCategories() async {
    try {
      final categories = await _repository.getCategories(includeInactive: true);
      if (!mounted) return;
      state = state.copyWith(categories: categories);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        errorMessage: UserFriendlyErrorMapper.map(
          e,
          fallback: 'Kategoriler yüklenemedi.',
        ),
      );
    }
  }

  Future<void> loadProducts({bool silent = false}) async {
    if (!mounted) return;
    final requestEpoch = ++_loadEpoch;
    if (!silent) {
      state = state.copyWith(isLoading: true, clearMessages: true);
    }
    try {
      final products = await _repository.getProducts(
        searchQuery: state.searchQuery,
        categoryId: state.selectedCategoryId,
        isActive: state.filterIsActive,
      );
      if (!mounted || requestEpoch != _loadEpoch) return;
      state = state.copyWith(isLoading: false, products: products);
    } catch (e) {
      if (!mounted || requestEpoch != _loadEpoch) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: UserFriendlyErrorMapper.map(
          e,
          fallback: 'Ürünler yüklenirken bir hata oluştu.',
        ),
      );
    }
  }

  void setSearchQuery(String? query) {
    state = state.copyWith(searchQuery: query?.trim());
    loadProducts();
  }

  void setCategoryFilter(String? categoryId) {
    if (categoryId == null || categoryId.isEmpty) {
      state = state.copyWith(clearCategory: true);
    } else {
      state = state.copyWith(selectedCategoryId: categoryId);
    }
    loadProducts();
  }

  void setActiveFilter(bool? isActive) {
    state = state.copyWith(filterIsActive: isActive);
    loadProducts();
  }

  // --- Kategori İşlemleri ---
  Future<bool> createCategory({required String name, String? parentId}) async {
    try {
      await _repository.createCategory(name: name, parentId: parentId);
      await loadCategories();
      if (!mounted) return false;
      state = state.copyWith(successMessage: 'Kategori başarıyla oluşturuldu.');
      return true;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(
        errorMessage: UserFriendlyErrorMapper.map(
          e,
          fallback: 'Kategori oluşturulamadı.',
        ),
      );
      return false;
    }
  }

  Future<bool> updateCategory({
    required String id,
    required String name,
    String? parentId,
    bool? isActive,
  }) async {
    try {
      await _repository.updateCategory(
        id: id,
        name: name,
        parentId: parentId,
        isActive: isActive,
      );
      await loadCategories();
      if (!mounted) return false;
      state = state.copyWith(successMessage: 'Kategori başarıyla güncellendi.');
      return true;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(
        errorMessage: UserFriendlyErrorMapper.map(
          e,
          fallback: 'Kategori güncellenemedi.',
        ),
      );
      return false;
    }
  }

  Future<bool> deactivateCategory(String id) async {
    try {
      await _repository.deactivateCategory(id);
      await loadCategories();
      if (!mounted) return false;
      state = state.copyWith(successMessage: 'Kategori pasife alındı.');
      return true;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(
        errorMessage: UserFriendlyErrorMapper.map(
          e,
          fallback: 'Kategori pasife alınamadı.',
        ),
      );
      return false;
    }
  }

  // --- Ürün İşlemleri ---
  Future<bool> createProduct({
    required String name,
    required int price,
    String? barcode,
    String? categoryId,
    int initialStock = 0,
    String stockUnit = 'adet',
    String pricingUnit = 'adet',
    int vatRate = 20,
    int? initialPurchasePrice,
  }) async {
    state = state.copyWith(isLoading: true, clearMessages: true);
    try {
      await _repository.createProduct(
        name: name,
        price: price,
        barcode: barcode,
        categoryId: categoryId,
        initialStock: initialStock,
        stockUnit: stockUnit,
        pricingUnit: pricingUnit,
        vatRate: vatRate,
        initialPurchasePrice: initialPurchasePrice,
        deviceId: _deviceId,
      );
      await loadProducts();
      if (!mounted) return false;
      onProductChanged?.call();
      state = state.copyWith(
        isLoading: false,
        successMessage: '"$name" ürünü başarıyla oluşturuldu.',
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(
        isLoading: false,
        errorMessage: UserFriendlyErrorMapper.map(
          e,
          fallback: 'Ürün oluşturulamadı.',
        ),
      );
      return false;
    }
  }

  Future<bool> updateProduct({
    required String id,
    String? name,
    int? price,
    String? categoryId,
    String? barcode,
    String? stockUnit,
    String? pricingUnit,
    int? vatRate,
    bool? isActive,
    String? priceChangeReason,
  }) async {
    state = state.copyWith(isLoading: true, clearMessages: true);
    try {
      await _repository.updateProduct(
        id: id,
        name: name,
        price: price,
        categoryId: categoryId,
        barcode: barcode,
        stockUnit: stockUnit,
        pricingUnit: pricingUnit,
        vatRate: vatRate,
        isActive: isActive,
        priceChangeReason: priceChangeReason,
        deviceId: _deviceId,
      );
      await loadProducts();
      if (!mounted) return false;
      onProductChanged?.call();
      state = state.copyWith(
        isLoading: false,
        successMessage: 'Ürün bilgileri başarıyla güncellendi.',
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(
        isLoading: false,
        errorMessage: UserFriendlyErrorMapper.map(
          e,
          fallback: 'Ürün güncellenemedi.',
        ),
      );
      return false;
    }
  }

  Future<bool> deactivateProduct(String id) async {
    try {
      await _repository.deactivateProduct(id, deviceId: _deviceId);
      await loadProducts();
      if (!mounted) return false;
      onProductChanged?.call();
      state = state.copyWith(successMessage: 'Ürün pasife alındı.');
      return true;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(
        errorMessage: UserFriendlyErrorMapper.map(
          e,
          fallback: 'Ürün pasife alınamadı.',
        ),
      );
      return false;
    }
  }

  /// Merkezi Hub ile manuel katalog senkronizasyonu
  Future<void> syncCatalogWithHub(Future<void> Function() syncAction) async {
    state = state.copyWith(isLoading: true, clearMessages: true);
    try {
      await syncAction();
      await Future.wait([
        loadCategories(),
        loadProducts(),
      ]);
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        successMessage: 'Ürün kataloğu Hub ile başarıyla senkronize edildi.',
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: UserFriendlyErrorMapper.map(
          e,
          fallback: 'Katalog senkronizasyonu şu anda tamamlanamadı.',
        ),
      );
    }
  }

  Future<List<LocalPriceHistoryData>> getPriceHistory(String productId) async {
    try {
      return await _repository.getPriceHistory(productId);
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
          errorMessage: UserFriendlyErrorMapper.map(
            e,
            fallback: 'Fiyat geçmişi yüklenemedi.',
          ),
        );
      }
      return [];
    }
  }
}
