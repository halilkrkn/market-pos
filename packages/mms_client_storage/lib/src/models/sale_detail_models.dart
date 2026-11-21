import '../database/client_database.dart';
import 'sale_display_status.dart';

class RefundWithItems {
  final LocalRefund refund;
  final List<LocalRefundItem> items;

  const RefundWithItems({
    required this.refund,
    required this.items,
  });
}

class SaleWithDetails {
  final LocalSale sale;
  final List<LocalSaleItem> items;
  final List<RefundWithItems> refunds;
  final List<LocalStockMovement> stockMovements;

  const SaleWithDetails({
    required this.sale,
    required this.items,
    this.refunds = const [],
    this.stockMovements = const [],
  });

  /// Bu satış için toplam yapılmış iade tutarı (kuruş)
  int get totalRefundedAmount =>
      refunds.fold(0, (sum, r) => sum + r.refund.totalRefundAmount);

  /// Kanonik gösterim durumu (TAMAMLANDI, İADE EDİLDİ, KISMİ İADE, İPTAL EDİLDİ)
  SaleDisplayStatus get displayStatus =>
      SaleDisplayStatus.fromSaleWithDetails(this);

  /// Kanonik gösterim durumu etiketi
  String get displayStatusLabel => displayStatus.label;

  /// İptal veya iadeler düşüldükten sonra kalan net tutar (kuruş)
  int get netAmount =>
      sale.status == 'CANCELLED' ? 0 : sale.totalAmount - totalRefundedAmount;

  /// Belirli bir satış kalemi için daha önce iade edilmiş miktar (milli-scale)
  int refundedQuantityFor(String saleItemId) {
    var total = 0;
    for (final r in refunds) {
      for (final item in r.items) {
        if (item.saleItemId == saleItemId) {
          total += item.quantity;
        }
      }
    }
    return total;
  }

  /// Belirli bir satış kalemi için kalan iade edilebilir miktar (milli-scale)
  int returnableQuantityFor(LocalSaleItem item) {
    if (sale.status == 'CANCELLED') return 0;
    final refunded = refundedQuantityFor(item.id);
    final remaining = item.quantity - refunded;
    return remaining > 0 ? remaining : 0;
  }
}
