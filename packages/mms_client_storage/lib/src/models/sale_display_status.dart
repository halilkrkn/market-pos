import 'sale_detail_models.dart';

/// MARKET MMS — Satış Durum Gösterimi Ortak Domain Modeli
///
/// Dashboard ve Satış Geçmişi ekranlarında ortak kullanılan kanonik satış durumları:
/// - Normal satış: `TAMAMLANDI`
/// - Tamamen iade edilmiş satış: `İADE EDİLDİ`
/// - Kısmi iade edilmiş satış: `KISMİ İADE`
/// - İptal edilmiş satış: `İPTAL EDİLDİ`
enum SaleDisplayStatus {
  completed('TAMAMLANDI'),
  refunded('İADE EDİLDİ'),
  partiallyRefunded('KISMİ İADE'),
  cancelled('İPTAL EDİLDİ');

  final String label;
  const SaleDisplayStatus(this.label);

  /// Ham veritabanı durum kodundan (`local_sales.status`) gösterim durumunu çözümler.
  static SaleDisplayStatus fromStatus(String? status) {
    switch (status?.toUpperCase()) {
      case 'CANCELLED':
        return SaleDisplayStatus.cancelled;
      case 'REFUNDED':
        return SaleDisplayStatus.refunded;
      case 'PARTIALLY_REFUNDED':
      case 'PARTIAL_REFUND':
        return SaleDisplayStatus.partiallyRefunded;
      case 'COMPLETED':
      default:
        return SaleDisplayStatus.completed;
    }
  }

  /// Satış tutarı ve iade bilgileri ile detaylı durum çözümler.
  static SaleDisplayStatus resolve({
    required String status,
    int totalAmount = 0,
    int totalRefundedAmount = 0,
    bool hasRefunds = false,
  }) {
    final upper = status.toUpperCase();
    if (upper == 'CANCELLED') {
      return SaleDisplayStatus.cancelled;
    }
    if (upper == 'REFUNDED' ||
        (totalRefundedAmount >= totalAmount && totalAmount > 0)) {
      return SaleDisplayStatus.refunded;
    }
    if (upper == 'PARTIALLY_REFUNDED' ||
        upper == 'PARTIAL_REFUND' ||
        (totalRefundedAmount > 0 && totalRefundedAmount < totalAmount) ||
        hasRefunds) {
      return SaleDisplayStatus.partiallyRefunded;
    }
    return SaleDisplayStatus.completed;
  }

  /// [SaleWithDetails] nesnesinden iade kalemlerini de dikkate alarak kesin durum üretir.
  static SaleDisplayStatus fromSaleWithDetails(SaleWithDetails detail) {
    return resolve(
      status: detail.sale.status,
      totalAmount: detail.sale.totalAmount,
      totalRefundedAmount: detail.totalRefundedAmount,
      hasRefunds: detail.refunds.isNotEmpty,
    );
  }
}
