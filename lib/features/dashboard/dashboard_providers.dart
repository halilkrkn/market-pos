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
/// gerçek zamanlı Dashboard özetini hesaplar. Sahte veri üretmez.
final dashboardSnapshotProvider = FutureProvider<DashboardSnapshot>((ref) async {
  // Sistem durumu yenilendiğinde (satış, iptal, iade, ürün/stok, sync sonrası) güncellenir
  ref.watch(systemStatusProvider.select((s) => s.localSalesCount));
  ref.watch(systemStatusProvider.select((s) => s.localProductsCount));
  ref.watch(systemStatusProvider.select((s) => s.localMetricsRevision));

  final dbService = ref.watch(localDatabaseServiceProvider);
  final repo = dbService.repository;

  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final sevenDaysAgo = todayStart.subtract(const Duration(days: 6));

  final periodSales = await repo.getSalesHistory(
    startDate: sevenDaysAgo,
    limit: 2000,
  );
  final recentSales = periodSales.isNotEmpty
      ? periodSales.take(8).toList()
      : await repo.getSalesHistory(limit: 8);
  final refundTotalsBySaleId = await repo.getRefundTotalsBySaleIds(
    periodSales.map((s) => s.id),
  );
  final activeProducts = await repo.getProducts(isActive: true, limit: 500);

  int todayTotal = 0;
  int todayCount = 0;
  int todayCash = 0;
  int todayCard = 0;

  // Son 7 günün kova haritası
  final dayTotals = <DateTime, int>{};
  final dayCounts = <DateTime, int>{};
  for (int i = 0; i < 7; i++) {
    final day = sevenDaysAgo.add(Duration(days: i));
    dayTotals[day] = 0;
    dayCounts[day] = 0;
  }

  for (final sale in periodSales) {
    if (sale.status == 'CANCELLED' || sale.status == 'REFUNDED') continue;
    final refundedCents = refundTotalsBySaleId[sale.id] ?? 0;
    final netAmountCents =
        (sale.totalAmount - refundedCents).clamp(0, sale.totalAmount);
    if (netAmountCents <= 0) continue;

    final localCreatedAt = sale.createdAt.toLocal();
    final saleDay = DateTime(
      localCreatedAt.year,
      localCreatedAt.month,
      localCreatedAt.day,
    );

    if (saleDay == todayStart) {
      todayTotal += netAmountCents;
      todayCount++;
      if (sale.paymentMethod == 'CASH') {
        todayCash += netAmountCents;
      } else {
        todayCard += netAmountCents;
      }
    }

    if (dayTotals.containsKey(saleDay)) {
      dayTotals[saleDay] = dayTotals[saleDay]! + netAmountCents;
      dayCounts[saleDay] = dayCounts[saleDay]! + 1;
    }
  }

  final trend = List.generate(7, (i) {
    final day = sevenDaysAgo.add(Duration(days: i));
    return DailySalesBucket(
      date: day,
      totalCents: dayTotals[day] ?? 0,
      count: dayCounts[day] ?? 0,
    );
  });

  final criticalProducts = activeProducts
      .where((p) => p.stock <= kCriticalStockThresholdMilli)
      .toList()
    ..sort((a, b) => a.stock.compareTo(b.stock));

  final negativeCount = activeProducts.where((p) => p.stock < 0).length;

  return DashboardSnapshot(
    todaySalesTotalCents: todayTotal,
    todaySalesCount: todayCount,
    todayCashTotalCents: todayCash,
    todayCardTotalCents: todayCard,
    activeProductCount: activeProducts.length,
    criticalStockCount: criticalProducts.length,
    negativeStockCount: negativeCount,
    last7DaysTrend: trend,
    recentSales: recentSales.take(8).toList(),
    criticalProducts: criticalProducts.take(8).toList(),
  );
});
