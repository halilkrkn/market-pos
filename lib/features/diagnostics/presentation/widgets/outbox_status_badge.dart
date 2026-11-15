import 'package:flutter/material.dart';
import 'package:mms_contracts/mms_contracts.dart';

import '../../../../core/theme/app_theme.dart';

/// Senkronizasyon Kuyruk Durum Rozeti (OutboxStatusBadge)
///
/// Senkronizasyon kuyruğunun gerçek durumunu (Senkronize, Bekliyor, Hata, Kuyruk Okunamıyor)
/// kasiyer için sade, yüksek kontrastlı ve renk kodlu bir rozet olarak sunar.
class OutboxStatusBadge extends StatelessWidget {
  final OutboxSummary summary;

  /// Yerel veritabanı okunamadığında (localDbState == error) true geçilir.
  /// Boş Outbox verisinin yanlışlıkla "SENKRONİZE" gibi algılanmasını önler.
  final bool isDatabaseError;

  const OutboxStatusBadge({
    super.key,
    required this.summary,
    this.isDatabaseError = false,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor;
    final Color textColor;
    final IconData icon;
    final String label;

    if (isDatabaseError) {
      // 1. Veritabanı Hatası: Kuyruk okunamıyor (Kritik durum, yanıltıcı yeşil engellenir)
      bgColor = isDark ? AppTheme.badgeErrorDarkBg : AppTheme.badgeErrorBg;
      textColor = isDark ? AppTheme.badgeErrorDarkText : AppTheme.badgeErrorText;
      icon = Icons.cloud_off;
      label = 'KUYRUK OKUNAMIYOR';
    } else if (summary.hasErrors) {
      // 2. Kalıcı Hata Önceliği: FAILED_PERMANENT > 0 (Kırmızı uyarı)
      bgColor = isDark ? AppTheme.badgeErrorDarkBg : AppTheme.badgeErrorBg;
      textColor = isDark ? AppTheme.badgeErrorDarkText : AppTheme.badgeErrorText;
      icon = Icons.error_outline;
      label = '${summary.failedPermanent} HATA';
    } else if (summary.hasPendingWork) {
      // 3. Bekleyen İşlemler: PENDING / RETRY / IN_PROGRESS > 0 (Kehribar uyarı)
      bgColor = isDark ? AppTheme.badgeWarningDarkBg : AppTheme.badgeWarningBg;
      textColor = isDark ? AppTheme.badgeWarningDarkText : AppTheme.badgeWarningText;
      icon = Icons.sync;
      label = '${summary.totalUnsynced} BEKLİYOR';
    } else {
      // 4. Temiz Kuyruk / Senkronize: totalUnsynced == 0 (Yeşil nötr)
      bgColor = isDark ? AppTheme.badgeSuccessDarkBg : AppTheme.badgeSuccessBg;
      textColor = isDark ? AppTheme.badgeSuccessDarkText : AppTheme.badgeSuccessText;
      icon = Icons.cloud_done;
      label = 'SENKRONİZE';
    }

    return Tooltip(
      message: _buildTooltipMessage(),
      preferBelow: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: textColor.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: textColor),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  letterSpacing: 0.5,
                  fontFeatures: AppTheme.tabularFiguresFeature,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
