import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/system_status.dart';

/// Canlılık / Durum Rozeti (Online, Offline, Draining, Checking)
class StatusBadge extends StatelessWidget {
  final BackendConnectionState state;

  const StatusBadge({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final Color bgColor;
    final Color textColor;
    final IconData icon;
    final String label;

    switch (state) {
      case BackendConnectionState.online:
        bgColor = const Color(0xFFDCFCE7); // Green 100
        textColor = AppTheme.statusOnline;
        icon = Icons.cloud_done;
        label = 'ÇEVRİMİÇİ (HUB CANLI)';
        break;
      case BackendConnectionState.offline:
        bgColor = const Color(0xFFFEE2E2); // Red 100
        textColor = AppTheme.statusOffline;
        icon = Icons.cloud_off;
        label = 'ÇEVRİMDIŞI (LOKAL ÇALIŞIYOR)';
        break;
      case BackendConnectionState.draining:
        bgColor = const Color(0xFFFEF3C7); // Amber 100
        textColor = AppTheme.statusWarning;
        icon = Icons.hourglass_top;
        label = 'BAKIMDA (503 DRAINING)';
        break;
      case BackendConnectionState.checking:
        bgColor = const Color(0xFFE2E8F0); // Slate 200
        textColor = const Color(0xFF475569);
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
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: textColor,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
