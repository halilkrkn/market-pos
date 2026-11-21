import 'package:flutter/material.dart';
import 'package:mms_contracts/mms_contracts.dart';

import '../../../../core/design_system/design_system.dart';

/// Senkronizasyon Kuyruk Durum Rozeti (OutboxStatusBadge — Modern Emerald WCAG AAA)
class OutboxStatusBadge extends StatelessWidget {
  final OutboxSummary summary;
  final bool isDatabaseError;
  final bool compact;

  const OutboxStatusBadge({
    super.key,
    required this.summary,
    this.isDatabaseError = false,
    this.compact = false,
  });

  String _buildTooltipMessage() {
    if (isDatabaseError) {
      return 'Yerel veritabanı okunamadığı için senkronizasyon kuyruğu durumu belirlenemiyor.';
    }
    if (summary.totalUnsynced == 0) {
      return 'Tüm işlemler senkronize (Kuyruk boş)';
    }
    return 'Senkronizasyon Kuyruğu:\n'
        '• Bekleyen: ${summary.pending}\n'
        '• Tekrar: ${summary.retry}\n'
        '• İşlemde: ${summary.inProgress}\n'
        '• Kalıcı Hata: ${summary.failedPermanent}\n'
        'Toplam: ${summary.totalUnsynced} kayıt';
  }

  @override
  Widget build(BuildContext context) {
    final (
      AppBadgeTone tone,
      IconData icon,
      String label,
      String shortLabel,
    ) = isDatabaseError
        ? (AppBadgeTone.danger, Icons.cloud_off, 'KUYRUK OKUNAMIYOR', 'HATA')
        : summary.hasErrors
        ? (
            AppBadgeTone.danger,
            Icons.error_outline,
            '${summary.failedPermanent} HATA',
            '${summary.failedPermanent} HATA',
          )
        : summary.hasPendingWork
        ? (
            AppBadgeTone.warning,
            Icons.sync,
            '${summary.totalUnsynced} BEKLİYOR',
            '${summary.totalUnsynced} BEK.',
          )
        : (AppBadgeTone.success, Icons.cloud_done, 'SENKRONİZE', 'SENK.');

    return Tooltip(
      message: _buildTooltipMessage(),
      preferBelow: true,
      child: AppBadge(
        label: compact ? shortLabel : label,
        tone: tone,
        icon: icon,
        compact: compact,
      ),
    );
  }
}
