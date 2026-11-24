/// Bir ürünün yerel katalog değişikliklerinin (PRODUCT_UPSERT Outbox kayıtları) Hub'a
/// gönderim durumu. Barkod ekleme/silme dahil tüm ürün kartı değişikliklerini kapsar.
enum ProductCatalogSyncState {
  /// Gönderilmeyi bekleyen PRODUCT_UPSERT yok; yerel ürün Hub ile eşitlenmiş kabul edilir.
  synced,

  /// Kuyrukta bekleyen (PENDING / IN_PROGRESS) değişiklik var.
  pending,

  /// Gönderim denendi, geçici hata nedeniyle yeniden denenecek (RETRY).
  retrying,

  /// Kalıcı hata (FAILED_PERMANENT): otomatik gönderilmeyecek, kullanıcı/teknik müdahale gerekir.
  failed,
}

/// Ürün bazlı katalog senkron durumu (genel Outbox rozetinden bağımsız).
class ProductCatalogSyncStatus {
  final ProductCatalogSyncState state;

  /// Henüz Hub tarafından onaylanmamış PRODUCT_UPSERT sayısı.
  final int unsyncedOperationCount;

  /// En son başarısız denemenin hata özeti (varsa).
  final String? lastError;

  const ProductCatalogSyncStatus({
    required this.state,
    this.unsyncedOperationCount = 0,
    this.lastError,
  });

  static const synced = ProductCatalogSyncStatus(state: ProductCatalogSyncState.synced);

  bool get hasUnsyncedChanges => state != ProductCatalogSyncState.synced;
}
