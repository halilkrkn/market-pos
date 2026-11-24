import 'package:mms_client_storage/mms_client_storage.dart';

/// Ürün barkod yönetimi ekranının görüntülediği güncel yerel durum.
class ProductBarcodeDetails {
  final LocalProduct product;

  /// Birincil barkod (`local_products.barcode`); yoksa `null`.
  final String? primaryBarcode;

  /// Aktif ikincil barkodlar (birincil barkod hariç).
  final List<LocalProductBarcode> secondaryBarcodes;

  /// Ürünün katalog değişikliklerinin Hub'a gönderim durumu.
  final ProductCatalogSyncStatus syncStatus;

  const ProductBarcodeDetails({
    required this.product,
    required this.primaryBarcode,
    required this.secondaryBarcodes,
    required this.syncStatus,
  });
}

/// Barkod ekleme/silme işleminin kullanıcıya gösterilecek sonucu.
class BarcodeMutationResult {
  final bool success;
  final String message;

  const BarcodeMutationResult.success(this.message) : success = true;
  const BarcodeMutationResult.failure(this.message) : success = false;
}
