import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/system_status.dart';

/// Canlılık / Durum Rozeti (Online, Offline, Draining, Checking)
class StatusBadge extends StatelessWidget {
  final BackendConnectionState state;

  const StatusBadge({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor;
    final Color textColor;
    final IconData icon;
    final String label;

    switch (state) {
      case BackendConnectionState.online:
        bgColor = isDark ? AppTheme.badgeSuccessDarkBg : AppTheme.badgeSuccessBg;
        textColor = isDark ? AppTheme.badgeSuccessDarkText : AppTheme.badgeSuccessText;
        icon = Icons.cloud_done;
        label = 'ÇEVRİMİÇİ (HUB CANLI)';
        break;
      case BackendConnectionState.offline:
        bgColor = isDark ? AppTheme.badgeErrorDarkBg : AppTheme.badgeErrorBg;
        textColor = isDark ? AppTheme.badgeErrorDarkText : AppTheme.badgeErrorText;
        icon = Icons.cloud_off;
        label = 'ÇEVRİMDIŞI (LOKAL ÇALIŞIYOR)';
        break;
      case BackendConnectionState.draining:
        bgColor = isDark ? AppTheme.badgeWarningDarkBg : AppTheme.badgeWarningBg;
        textColor = isDark ? AppTheme.badgeWarningDarkText : AppTheme.badgeWarningText;
        icon = Icons.hourglass_top;
        label = 'BAKIMDA (503 DRAINING)';
        break;
      case BackendConnectionState.checking:
        bgColor = isDark ? AppTheme.badgeNeutralDarkBg : AppTheme.badgeNeutralBg;
        textColor = isDark ? AppTheme.badgeNeutralDarkText : AppTheme.badgeNeutralText;
        icon = Icons.sync;
        label = 'KONTROL EDİLİYOR...';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: textColor.withValues(alpha: 0.3), width: 1.5),
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}
