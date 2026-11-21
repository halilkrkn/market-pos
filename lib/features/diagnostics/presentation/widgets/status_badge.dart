import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';
import '../../domain/system_status.dart';

/// Hub Canlılık / Bağlantı Durumu Rozeti (Modern Emerald WCAG AAA)
class StatusBadge extends StatelessWidget {
  final BackendConnectionState state;
  final bool compact;

  const StatusBadge({
    super.key,
    required this.state,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final (AppBadgeTone tone, IconData icon, String label, String shortLabel) =
        switch (state) {
      BackendConnectionState.online => (
          AppBadgeTone.success,
          Icons.cloud_done_rounded,
          'ÇEVRİMİÇİ (HUB CANLI)',
          'ÇEVRİMİÇİ',
        ),
      BackendConnectionState.offline => (
          AppBadgeTone.danger,
          Icons.cloud_off_rounded,
          'ÇEVRİMDIŞI (LOKAL ÇALIŞIYOR)',
          'ÇEVRİMDIŞI',
        ),
      BackendConnectionState.draining => (
          AppBadgeTone.warning,
          Icons.hourglass_top_rounded,
          'BAKIMDA (503 DRAINING)',
          'BAKIMDA',
        ),
      BackendConnectionState.checking => (
          AppBadgeTone.neutral,
          Icons.sync_rounded,
          'KONTROL EDİLİYOR...',
          'KONTROL',
        ),
      BackendConnectionState.tlsPinMismatch => (
          AppBadgeTone.danger,
          Icons.gpp_bad_rounded,
          'SERTİFİKA UYUŞMUYOR',
          'PIN UYUŞMUYOR',
        ),
      BackendConnectionState.tlsCertError => (
          AppBadgeTone.warning,
          Icons.verified_user_outlined,
          'SERTİFİKA HATASI (SAN/TARİH)',
          'SERTİFİKA HATASI',
        ),
    };

    return Tooltip(
      message: label,
      child: AppBadge(
        label: compact ? shortLabel : label,
        tone: tone,
        icon: icon,
        compact: compact,
      ),
    );
  }
}
