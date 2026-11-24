import 'package:mms_client_storage/mms_client_storage.dart';

class CatalogState {
  final bool isLoading;
  final List<LocalProduct> products;
  final List<LocalCategory> categories;
  final String? selectedCategoryId;
  final String? searchQuery;
  final bool? filterIsActive;
  final String? errorMessage;
  final String? successMessage;

  /// Ürün bazlı katalog (PRODUCT_UPSERT) Hub gönderim durumları; yalnızca eşitlenmemiş
  /// ürünleri içerir. Liste satırlarında ürün bazlı rozet için kullanılır.
  final Map<String, ProductCatalogSyncStatus> catalogSyncStatus;

  const CatalogState({
    this.isLoading = false,
    this.products = const [],
    this.categories = const [],
    this.selectedCategoryId,
    this.searchQuery,
    this.filterIsActive,
    this.errorMessage,
    this.successMessage,
    this.catalogSyncStatus = const {},
  });

  CatalogState copyWith({
    bool? isLoading,
    List<LocalProduct>? products,
    List<LocalCategory>? categories,
    String? selectedCategoryId,
    bool clearCategory = false,
    String? searchQuery,
    bool? filterIsActive,
    String? errorMessage,
    String? successMessage,
    bool clearMessages = false,
    Map<String, ProductCatalogSyncStatus>? catalogSyncStatus,
  }) {
    return CatalogState(
      isLoading: isLoading ?? this.isLoading,
      products: products ?? this.products,
      categories: categories ?? this.categories,
      selectedCategoryId: clearCategory ? null : (selectedCategoryId ?? this.selectedCategoryId),
      searchQuery: searchQuery ?? this.searchQuery,
      filterIsActive: filterIsActive ?? this.filterIsActive,
      errorMessage: clearMessages ? null : (errorMessage ?? this.errorMessage),
      successMessage: clearMessages ? null : (successMessage ?? this.successMessage),
      catalogSyncStatus: catalogSyncStatus ?? this.catalogSyncStatus,
    );
  }
}
