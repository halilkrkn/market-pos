import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../../../core/utils/user_friendly_error_mapper.dart';
import '../domain/catalog_repository.dart';
import 'catalog_state.dart';
import 'product_barcode_details.dart';

class CatalogNotifier extends StateNotifier<CatalogState> {
  final CatalogRepository _repository;
  final String _deviceId;
  final void Function()? onProductChanged;
  int _loadEpoch = 0;

  CatalogNotifier(this._repository, this._deviceId, {this.onProductChanged})
    : super(const CatalogState()) {
    init();
  }

  Future<void> init() async {
    await Future.wait([loadCategories(), loadProducts()]);
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
      final syncStatus = await _loadCatalogSyncStatusSafely();
      if (!mounted || requestEpoch != _loadEpoch) return;
      state = state.copyWith(
        isLoading: false,
        products: products,
        catalogSyncStatus: syncStatus,
      );
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
    bool clearBarcode = false,
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
        clearBarcode: clearBarcode,
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

  Future<Map<String, ProductCatalogSyncStatus>>
  _loadCatalogSyncStatusSafely() async {
    try {
      return await _repository.getCatalogSyncStatusByProduct();
    } catch (_) {
      // Rozet bilgisi yüklenemezse ürün listesi yine gösterilir.
      return const {};
    }
  }

  /// Ürün barkod yönetimi için güncel yerel durumu yükler (birincil + ikincil barkodlar
  /// ve ürün bazlı Hub gönderim durumu). Ürün bulunamazsa `null` döner.
  Future<ProductBarcodeDetails?> loadBarcodeDetails(String productId) async {
    final product = await _repository.getProductById(productId);
    if (product == null) return null;
    final barcodes = await _repository.getBarcodesForProduct(productId);
    final syncStatus = await _repository.getProductCatalogSyncStatus(productId);
    final primary =
        (product.barcode != null && product.barcode!.trim().isNotEmpty)
        ? product.barcode!.trim()
        : null;
    final secondary =
        barcodes.where((b) => !b.isPrimary && b.barcode != primary).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return ProductBarcodeDetails(
      product: product,
      primaryBarcode: primary,
      secondaryBarcodes: secondary,
      syncStatus: syncStatus,
    );
  }

  /// İkincil barkod ekler (yerel SQLite + PRODUCT_UPSERT Outbox, tek transaction).
  ///
  /// İş kuralları (BR-PROD-02) depo katmanında da zorlanır; burada kullanıcıya anlaşılır
  /// mesaj vermek için ön kontrol yapılır.
  Future<BarcodeMutationResult> addProductBarcode({
    required String productId,
    required String barcode,
  }) async {
    final trimmed = barcode.trim();
    if (trimmed.isEmpty) {
      return const BarcodeMutationResult.failure('Barkod boş olamaz.');
    }
    try {
      final product = await _repository.getProductById(productId);
      if (product == null) {
        return const BarcodeMutationResult.failure('Ürün bulunamadı.');
      }
      if (product.barcode?.trim() == trimmed) {
        return BarcodeMutationResult.failure(
          '$trimmed bu ürünün birincil barkodudur; ikincil barkod olarak eklenemez.',
        );
      }
      final owner = await _repository.getProductByBarcode(trimmed);
      if (owner != null && owner.id == productId) {
        return BarcodeMutationResult.failure('$trimmed bu ürüne zaten ekli.');
      }
      if (owner != null) {
        return BarcodeMutationResult.failure(
          '$trimmed başka bir ürüne kayıtlı: "${owner.name}". Aynı barkod iki ürüne atanamaz.',
        );
      }

      await _repository.addProductBarcode(
        productId: productId,
        barcode: trimmed,
        isPrimary: false,
        deviceId: _deviceId,
      );
      await loadProducts(silent: true);
      if (!mounted) {
        return const BarcodeMutationResult.success('Barkod ürüne eklendi.');
      }
      onProductChanged?.call();
      const message =
          'Barkod ürüne eklendi. Değişiklik bu cihazda hemen geçerlidir; '
          "Hub'a gönderim kuyruğa alındı.";
      state = state.copyWith(successMessage: message);
      return const BarcodeMutationResult.success(message);
    } catch (e) {
      final message = UserFriendlyErrorMapper.map(
        e,
        fallback: 'Barkod eklenemedi.',
      );
      if (mounted) state = state.copyWith(errorMessage: message);
      return BarcodeMutationResult.failure(message);
    }
  }

  /// İkincil barkodu pasife alır (BR-PROD-15: geçmiş korunur) ve PRODUCT_UPSERT kuyruğa alır.
  Future<BarcodeMutationResult> removeProductBarcode(String barcodeId) async {
    try {
      await _repository.removeProductBarcode(barcodeId, deviceId: _deviceId);
      await loadProducts(silent: true);
      if (!mounted) {
        return const BarcodeMutationResult.success('Barkod kaldırıldı.');
      }
      onProductChanged?.call();
      const message =
          'Barkod kaldırıldı. Değişiklik bu cihazda hemen geçerlidir; '
          "Hub'a gönderim kuyruğa alındı.";
      state = state.copyWith(successMessage: message);
      return const BarcodeMutationResult.success(message);
    } catch (e) {
      final message = UserFriendlyErrorMapper.map(
        e,
        fallback: 'Barkod kaldırılamadı.',
      );
      if (mounted) state = state.copyWith(errorMessage: message);
      return BarcodeMutationResult.failure(message);
    }
  }

  /// Merkezi Hub ile manuel katalog senkronizasyonu
  Future<void> syncCatalogWithHub(Future<void> Function() syncAction) async {
    state = state.copyWith(isLoading: true, clearMessages: true);
    try {
      await syncAction();
      await Future.wait([loadCategories(), loadProducts()]);
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
