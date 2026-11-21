class DownloadedSaleItemPayload {
  final String id;
  final String saleId;
  final String productId;
  final String productName;
  final String unit;
  final String priceVersionId;
  final int unitPrice;
  final int quantity;
  final int totalPrice;

  const DownloadedSaleItemPayload({
    required this.id,
    required this.saleId,
    required this.productId,
    required this.productName,
    this.unit = 'adet',
    this.priceVersionId = 'pv_init',
    required this.unitPrice,
    required this.quantity,
    required this.totalPrice,
  });

  factory DownloadedSaleItemPayload.fromJson(Map<String, dynamic> json) {
    return DownloadedSaleItemPayload(
      id: json['id'] as String,
      saleId: json['sale_id'] as String,
      productId: json['product_id'] as String,
      productName: json['product_name'] as String? ?? 'Ürün',
      unit: json['unit'] as String? ?? 'adet',
      priceVersionId: json['price_version_id'] as String? ?? 'pv_init',
      unitPrice: json['unit_price'] as int,
      quantity: json['quantity'] as int,
      totalPrice: json['total_price'] as int,
    );
  }
}

class DownloadedRefundItemPayload {
  final String id;
  final String refundId;
  final String? saleItemId;
  final String productId;
  final int quantity;
  final int unitPrice;
  final int refundAmount;
  final String productCondition;

  const DownloadedRefundItemPayload({
    required this.id,
    required this.refundId,
    this.saleItemId,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.refundAmount,
    this.productCondition = 'SELLABLE',
  });

  factory DownloadedRefundItemPayload.fromJson(Map<String, dynamic> json) {
    return DownloadedRefundItemPayload(
      id: json['id'] as String,
      refundId: json['refund_id'] as String,
      saleItemId: json['sale_item_id'] as String?,
      productId: json['product_id'] as String,
      quantity: json['quantity'] as int,
      unitPrice: json['unit_price'] as int,
      refundAmount: json['refund_amount'] as int,
      productCondition: json['product_condition'] as String? ?? 'SELLABLE',
    );
  }
}

class DownloadedRefundPayload {
  final String id;
  final String saleId;
  final String deviceId;
  final int clientSeq;
  final int totalRefundAmount;
  final String paymentMethod;
  final String reason;
  final DateTime createdAt;
  final List<DownloadedRefundItemPayload> items;

  const DownloadedRefundPayload({
    required this.id,
    required this.saleId,
    required this.deviceId,
    required this.clientSeq,
    required this.totalRefundAmount,
    required this.paymentMethod,
    required this.reason,
    required this.createdAt,
    this.items = const [],
  });

  factory DownloadedRefundPayload.fromJson(Map<String, dynamic> json) {
    return DownloadedRefundPayload(
      id: json['id'] as String,
      saleId: json['sale_id'] as String,
      deviceId: json['device_id'] as String,
      clientSeq: json['client_seq'] as int,
      totalRefundAmount: json['total_refund_amount'] as int,
      paymentMethod: json['payment_method'] as String,
      reason: json['reason'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      items: (json['items'] as List<dynamic>?)
              ?.map((item) => DownloadedRefundItemPayload.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

class DownloadedSalePayload {
  final String id;
  final int serverSeq;
  final String deviceId;
  final int clientSeq;
  final int totalAmount;
  final String paymentMethod;
  final String status;
  final String? cancelReason;
  final DateTime? cancelledAt;
  final DateTime createdAt;
  final List<DownloadedSaleItemPayload> items;
  final List<DownloadedRefundPayload> refunds;

  const DownloadedSalePayload({
    required this.id,
    required this.serverSeq,
    required this.deviceId,
    required this.clientSeq,
    required this.totalAmount,
    required this.paymentMethod,
    this.status = 'COMPLETED',
    this.cancelReason,
    this.cancelledAt,
    required this.createdAt,
    this.items = const [],
    this.refunds = const [],
  });

  factory DownloadedSalePayload.fromJson(Map<String, dynamic> json) {
    return DownloadedSalePayload(
      id: json['id'] as String,
      serverSeq: json['server_seq'] as int? ?? 0,
      deviceId: json['device_id'] as String,
      clientSeq: json['client_seq'] as int,
      totalAmount: json['total_amount'] as int,
      paymentMethod: json['payment_method'] as String,
      status: json['status'] as String? ?? 'COMPLETED',
      cancelReason: json['cancel_reason'] as String?,
      cancelledAt: json['cancelled_at'] != null ? DateTime.parse(json['cancelled_at'] as String) : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      items: (json['items'] as List<dynamic>?)
              ?.map((item) => DownloadedSaleItemPayload.fromJson(item as Map<String, dynamic>))
              .toList() ??
          const [],
      refunds: (json['refunds'] as List<dynamic>?)
              ?.map((ref) => DownloadedRefundPayload.fromJson(ref as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}
