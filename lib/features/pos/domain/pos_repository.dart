import 'package:mms_client_storage/payment_method.dart';

import 'cart_state.dart';
import 'pos_product.dart';

export 'package:mms_client_storage/payment_method.dart' show PaymentMethod;

enum BarcodeLookupStatus { found, inactiveProduct, notFoundOffline }

/// Barkod sorgusunun saf Dart sonucu (`OD-03`, `BR-PROD-03`).
class BarcodeLookupResult {
  final BarcodeLookupStatus status;
  final PosProduct? product;
  final String barcode;

  const BarcodeLookupResult._({
    required this.status,
    required this.barcode,
    this.product,
  });

  const BarcodeLookupResult.found(PosProduct product, String barcode)
    : this._(
        status: BarcodeLookupStatus.found,
        product: product,
        barcode: barcode,
      );

  const BarcodeLookupResult.inactiveProduct(PosProduct product, String barcode)
    : this._(
        status: BarcodeLookupStatus.inactiveProduct,
        product: product,
        barcode: barcode,
      );

  const BarcodeLookupResult.notFoundOffline(String barcode)
    : this._(status: BarcodeLookupStatus.notFoundOffline, barcode: barcode);
}

/// Tamamlanan yerel satış kalemi özeti (saf Dart).
class PosCompletedSaleItem {
  final String productId;
  final String productName;
  final String unitSnapshot;
  final int unitPriceCents;
  final int quantityMilli;
  final int totalPriceCents;

  const PosCompletedSaleItem({
    required this.productId,
    required this.productName,
    required this.unitSnapshot,
    required this.unitPriceCents,
    required this.quantityMilli,
    required this.totalPriceCents,
  });
}

/// Atomik çevrimdışı satışın saf Dart sonuç modeli.
class PosCompletedSale {
  final String saleId;
  final String deviceId;
  final int clientSeq;
  final int totalAmountCents;
  final PaymentMethod paymentMethod;
  final int? cashReceivedCents;
  final int? cashChangeCents;
  final String operationId;
  final DateTime createdAt;
  final List<PosCompletedSaleItem> items;

  const PosCompletedSale({
    required this.saleId,
    required this.deviceId,
    required this.clientSeq,
    required this.totalAmountCents,
    required this.paymentMethod,
    this.cashReceivedCents,
    this.cashChangeCents,
    required this.operationId,
    required this.createdAt,
    required this.items,
  });
}

/// POS katmanı için soyut repository sözleşmesi (Domain Port).
abstract interface class PosRepository {
  Future<BarcodeLookupResult> findByBarcode(String barcode);

  Future<List<PosProduct>> searchActiveProducts(String query, {int limit = 50});

  Future<PosCompletedSale> completeOfflineSale({
    required String deviceId,
    required CartState cart,
    required PaymentMethod paymentMethod,
    int? cashReceivedCents,
    required bool externalPosConfirmed,
  });
}
