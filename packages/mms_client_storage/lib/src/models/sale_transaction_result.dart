class SaleTransactionItemResult {
  final String productId;
  final String productName;
  final String unitSnapshot; // 'adet', 'kg', 'l', vb. (pricing_unit)
  final String priceVersionId; // S5A-3: Fiyat sürüm kimliği
  final int unitPrice; // Kuruş bazlı birim fiyat (Ör: 20000 = 200 TL/kg)
  final int quantity; // Milli-birim bazlı miktar (Ör: 500 = 0.5 kg, 1000 = 1 adet)
  final int totalPrice; // Kuruş bazlı satır toplamı: ((unitPrice * quantity) + 500) ~/ 1000
  final int stockDelta; // stock_unit cinsinden stok düşüş miktarı (milli-birim)
  final String stockUnit; // Ürünün stok birimi ('g', 'adet', 'l')

  const SaleTransactionItemResult({
    required this.productId,
    required this.productName,
    required this.unitSnapshot,
    this.priceVersionId = 'pv_init',
    required this.unitPrice,
    required this.quantity,
    required this.totalPrice,
    this.stockDelta = 0,
    this.stockUnit = 'adet',
  });

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'product_name': productName,
        'unit': unitSnapshot,
        'price_version_id': priceVersionId,
        'unit_price': unitPrice,
        'quantity': quantity,
        'total_price': totalPrice,
        'stock_delta': stockDelta,
        'stock_unit': stockUnit,
      };
}

class SaleTransactionResult {
  final String saleId;
  final String deviceId;
  final int clientSeq;
  final int totalAmount; // Kuruş bazlı toplam tutar
  final String paymentMethod;
  final String operationId;
  final List<SaleTransactionItemResult> items;
  final DateTime createdAt;
  final bool isCommitted;

  const SaleTransactionResult({
    required this.saleId,
    required this.deviceId,
    required this.clientSeq,
    required this.totalAmount,
    required this.paymentMethod,
    required this.operationId,
    required this.items,
    required this.createdAt,
    this.isCommitted = true,
  });

  Map<String, dynamic> toJson() => {
        'sale_id': saleId,
        'device_id': deviceId,
        'client_seq': clientSeq,
        'total_amount': totalAmount,
        'payment_method': paymentMethod,
        'operation_id': operationId,
        'created_at': createdAt.toIso8601String(),
        'items': items.map((i) => i.toJson()).toList(),
      };
}
