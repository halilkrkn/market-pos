import 'package:flutter/material.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../../../../core/design_system/design_system.dart';

/// MARKET MMS — Ortak Satış Durumu Rozet Bileşeni
///
/// Dashboard (Son Satışlar), Satış Geçmişi ve Fiş Detay ekranlarında
/// satış durumunun tutarlı biçimde tek bir kaynaktan gösterilmesini sağlar.
///
/// Kanonik Etiketler ve Tonlar:
/// - Normal satış: `TAMAMLANDI` (success)
/// - Tamamen iade: `İADE EDİLDİ` (warning)
/// - Kısmi iade: `KISMİ İADE` (info)
/// - İptal: `İPTAL EDİLDİ` (danger)
class SaleStatusBadge extends StatelessWidget {
  final SaleDisplayStatus status;
  final bool compact;

  const SaleStatusBadge({
    super.key,
    required this.status,
    this.compact = true,
  });

  /// Ham veritabanı durum kodundan (`local_sales.status`) rozet üretir.
  factory SaleStatusBadge.fromStatus(
    String? rawStatus, {
    Key? key,
    bool compact = true,
  }) {
    return SaleStatusBadge(
      key: key,
      status: SaleDisplayStatus.fromStatus(rawStatus),
      compact: compact,
    );
  }

  /// [SaleWithDetails] nesnesinden iadeleri de dikkate alarak rozet üretir.
  factory SaleStatusBadge.fromDetails(
    SaleWithDetails details, {
    Key? key,
    bool compact = false,
  }) {
    return SaleStatusBadge(
      key: key,
      status: SaleDisplayStatus.fromSaleWithDetails(details),
      compact: compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case SaleDisplayStatus.cancelled:
        return AppBadge(
          label: status.label,
          tone: AppBadgeTone.danger,
          compact: compact,
        );
      case SaleDisplayStatus.refunded:
        return AppBadge(
          label: status.label,
          tone: AppBadgeTone.warning,
          compact: compact,
        );
      case SaleDisplayStatus.partiallyRefunded:
        return AppBadge(
          label: status.label,
          tone: AppBadgeTone.info,
          compact: compact,
        );
      case SaleDisplayStatus.completed:
        return AppBadge(
          label: status.label,
          tone: AppBadgeTone.success,
          compact: compact,
        );
    }
  }
}
