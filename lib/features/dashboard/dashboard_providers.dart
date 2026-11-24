import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../diagnostics/application/system_status_notifier.dart';

/// Kritik stok eşiği (milli-birim: 5000 = 5 adet/kg/L)
const int kCriticalStockThresholdMilli = 5000;

class DailySalesBucket {
  final DateTime date;
  final int totalCents;
  final int count;

  const DailySalesBucket({
    required this.date,
    required this.totalCents,
    required this.count,
  });
}

class DashboardSnapshot {
  final int todaySalesTotalCents;
  final int todaySalesCount;
  final int todayCashTotalCents;
  final int todayCardTotalCents;
  final int activeProductCount;
  final int criticalStockCount;
  final int negativeStockCount;
  final List<DailySalesBucket> last7DaysTrend;
  final List<LocalSale> recentSales;
  final List<LocalProduct> criticalProducts;

  const DashboardSnapshot({
    required this.todaySalesTotalCents,
    required this.todaySalesCount,
    required this.todayCashTotalCents,
    required this.todayCardTotalCents,
    required this.activeProductCount,
    required this.criticalStockCount,
    required this.negativeStockCount,
    required this.last7DaysTrend,
    required this.recentSales,
    required this.criticalProducts,
  });
}

/// Mevcut yerel Drift SQLite verilerinden (local_sales, local_products)
/// sınırsız SQL aggregate sorgularıyla gerçek zamanlı Dashboard özetini hesaplar. Sahte veri üretmez.
final dashboardSnapshotProvider = FutureProvider<DashboardSnapshot>((ref) async {
  // Sistem durumu yenilendiğinde (satış, iptal, iade, ürün/stok, sync sonrası) güncellenir
  ref.watch(systemStatusProvider.select((s) => s.localSalesCount));
  ref.watch(systemStatusProvider.select((s) => s.localProductsCount));
  ref.watch(systemStatusProvider.select((s) => s.localMetricsRevision));

  final dbService = ref.watch(localDatabaseServiceProvider);
  final repo = dbService.repository;

  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);

  final productSummary = await repo.getDashboardProductSummary(
    criticalStockThresholdMilli: kCriticalStockThresholdMilli,
    previewLimit: 8,
  );
  final salesSummary = await repo.getDashboardSalesSummary(
    todayStart: todayStart,
    trendDays: 7,
  );
  final recentSales = await repo.getSalesHistory(limit: 8);

  return DashboardSnapshot(
    todaySalesTotalCents: salesSummary.todaySalesTotalCents,
    todaySalesCount: salesSummary.todaySalesCount,
    todayCashTotalCents: salesSummary.todayCashTotalCents,
    todayCardTotalCents: salesSummary.todayCardTotalCents,
    activeProductCount: productSummary.activeProductCount,
    criticalStockCount: productSummary.criticalStockCount,
    negativeStockCount: productSummary.negativeStockCount,
    last7DaysTrend: salesSummary.dailyTotals
        .map((d) => DailySalesBucket(
              date: d.date,
              totalCents: d.totalCents,
              count: d.count,
            ))
        .toList(),
    recentSales: recentSales,
    criticalProducts: productSummary.criticalProducts,
  );
});
