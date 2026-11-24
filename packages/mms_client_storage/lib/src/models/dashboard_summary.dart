import '../database/client_database.dart';

/// Dashboard ürün ve stok özet metrikleri (500 ürün sınırı olmadan tam SQL aggregate).
class DashboardProductSummary {
  final int activeProductCount;
  final int criticalStockCount;
  final int negativeStockCount;
  final List<LocalProduct> criticalProducts;

  const DashboardProductSummary({
    required this.activeProductCount,
    required this.criticalStockCount,
    required this.negativeStockCount,
    required this.criticalProducts,
  });
}

/// Günlük net satış toplamı ve fiş adedi (Dashboard 7 günlük grafik kovası).
class DashboardDailySalesTotal {
  final DateTime date;
  final int totalCents;
  final int count;

  const DashboardDailySalesTotal({
    required this.date,
    required this.totalCents,
    required this.count,
  });
}

/// Dashboard satış özet metrikleri (2000 satış sınırı olmadan tam SQL aggregate).
class DashboardSalesSummary {
  final int todaySalesTotalCents;
  final int todaySalesCount;
  final int todayCashTotalCents;
  final int todayCardTotalCents;
  final List<DashboardDailySalesTotal> dailyTotals;

  const DashboardSalesSummary({
    required this.todaySalesTotalCents,
    required this.todaySalesCount,
    required this.todayCashTotalCents,
    required this.todayCardTotalCents,
    required this.dailyTotals,
  });
}
