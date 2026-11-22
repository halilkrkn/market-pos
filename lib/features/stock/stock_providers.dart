import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../dashboard/dashboard_providers.dart';
import '../diagnostics/application/system_status_notifier.dart';
import '../sync/domain/sync_coordinator_state.dart';
import '../sync/sync_providers.dart';
import 'application/stock_receipt_notifier.dart';

enum StockStatusFilter {
  all,
  critical,
  negative,
  outOfStock,
}

class StockOverviewData {
  final List<LocalProduct> products;
  final List<LocalStockMovement> movements;
  final Map<String, LocalProduct> productById;
  final int criticalCount;
  final int negativeCount;
  final int outOfStockCount;

  const StockOverviewData({
    required this.products,
    required this.movements,
    required this.productById,
    required this.criticalCount,
    required this.negativeCount,
    required this.outOfStockCount,
  });
}

/// Mevcut yerel SQLite verilerinden (`local_products` ve `local_stock_movements`)
/// gerçek stok durumu ve hareket geçmişini okur.
final stockOverviewProvider = FutureProvider<StockOverviewData>((ref) async {
  ref.watch(systemStatusProvider.select((s) => s.localProductsCount));
  ref.watch(systemStatusProvider.select((s) => s.localSalesCount));
  ref.watch(systemStatusProvider.select((s) => s.localMetricsRevision));

  final repo = ref.watch(localDatabaseServiceProvider).repository;
  final products = await repo.getProducts(isActive: true, limit: 500);
  final movements = await repo.getStockMovements(limit: 150);

  final productMap = {for (final p in products) p.id: p};
  final criticalCount =
      products.where((p) => p.stock <= kCriticalStockThresholdMilli).length;
  final negativeCount = products.where((p) => p.stock < 0).length;
  final outOfStockCount = products.where((p) => p.stock == 0).length;

  return StockOverviewData(
    products: products,
    movements: movements,
    productById: productMap,
    criticalCount: criticalCount,
    negativeCount: negativeCount,
    outOfStockCount: outOfStockCount,
  );
});

/// Mevcut ürüne barkodla stok girişi akışı (Faz 2 §4.3).
final stockReceiptProvider = StateNotifierProvider.autoDispose<
    StockReceiptNotifier, StockReceiptState>((ref) {
  final repo = ref.watch(localDatabaseServiceProvider).repository;
  final apiClient = ref.watch(apiClientProvider);
  final syncCoordinator = ref.watch(backgroundSyncCoordinatorProvider.notifier);
  return StockReceiptNotifier(
    repository: repo,
    readDeviceId: () => apiClient.deviceId,
    onStockCommitted: () async {
      try {
        await ref.read(systemStatusProvider.notifier).refreshLocalMetrics();
      } catch (e, s) {
        debugPrint(
          '[stock_providers] onStockCommitted refreshLocalMetrics hatası: $e\n$s',
        );
      }
      ref.invalidate(stockOverviewProvider);
      try {
        await syncCoordinator.triggerSync(
          reason: SyncTriggerReason.productCommitted,
        );
      } catch (e, s) {
        debugPrint(
          '[stock_providers] onStockCommitted triggerSync hatası: $e\n$s',
        );
      }
    },
  );
});

/// Seçili ürünün son stok hareketleri (giriş geçmişi dahil).
final productStockMovementsProvider = FutureProvider.autoDispose
    .family<List<LocalStockMovement>, String>((ref, productId) async {
  ref.watch(stockReceiptProvider.select((s) => s.lastResult));
  final repo = ref.watch(localDatabaseServiceProvider).repository;
  return repo.getStockMovements(productId: productId, limit: 50);
});
