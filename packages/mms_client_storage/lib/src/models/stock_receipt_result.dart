/// Mevcut ürüne stok girişi (`STOCK_RECEIPT`) işleminin sonucu.
class StockReceiptResult {
  final String receiptId;
  final String productId;
  final int quantityMilli;
  final int newStockMilli;
  final String stockUnit;

  /// Aynı `receiptId` daha önce uygulanmışsa `true`; bu durumda stok tekrar artırılmaz.
  final bool isDuplicate;

  /// Outbox'a yazılan işlem kimliği (yinelenen çağrılarda ilk kaydın kimliği).
  final String operationId;

  const StockReceiptResult({
    required this.receiptId,
    required this.productId,
    required this.quantityMilli,
    required this.newStockMilli,
    required this.stockUnit,
    required this.isDuplicate,
    required this.operationId,
  });
}

/// Yalnızca tam sayılı miktar kabul eden (kesirli girişe kapalı) stok birimleri.
const Set<String> kCountableStockUnits = {'adet', 'paket', 'kutu', 'koli'};
