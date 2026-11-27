import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../diagnostics/presentation/widgets/diagnostics_card_helpers.dart';
import 'windows_tray_providers.dart';

/// Windows masaüstü istemcisi için Sistem Tepsisi, Otomatik Başlatma ve Kontrollü
/// Çıkış ayar kartı (yalnızca Windows masaüstü profilinde gösterilir).
class WindowsDesktopSettingsCard extends ConsumerWidget {
  const WindowsDesktopSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trayState = ref.watch(windowsTrayControllerProvider);
    final controller = ref.read(windowsTrayControllerProvider.notifier);
    final colors = context.mmsColors;

    final String trayBadgeLabel;
    final AppBadgeTone trayBadgeTone;
    if (!trayState.isSupported) {
      trayBadgeLabel = 'DESTEKLENMİYOR';
      trayBadgeTone = AppBadgeTone.neutral;
    } else if (trayState.isExiting) {
      trayBadgeLabel = 'KAPATILIYOR...';
      trayBadgeTone = AppBadgeTone.warning;
    } else if (trayState.isTrayActive) {
      trayBadgeLabel = 'TEPSİ AKTİF';
      trayBadgeTone = AppBadgeTone.success;
    } else {
      trayBadgeLabel = 'BAŞLATILMADI';
      trayBadgeTone = AppBadgeTone.warning;
    }

    return DiagnosticsSectionCard(
      key: const Key('windows_desktop_settings_card'),
      title: 'Windows Masaüstü ve Sistem Tepsisi',
      subtitle:
          'Pencere küçültme/kapatma (X) davranışı, oturum açılışında başlatma ve güvenli çıkış',
      trailing: AppBadge(
        label: trayBadgeLabel,
        tone: trayBadgeTone,
        icon: Icons.desktop_windows_rounded,
        compact: true,
      ),
      children: [
        DiagnosticsKeyValueRow(
          label: 'Sistem Tepsisi Davranışı',
          value: trayState.isTrayActive
              ? 'X / Küçült tepsiye gizler · Çift tık açar'
              : 'Tepsi simgesi etkin değil',
        ),
        const SizedBox(height: MmsSpacing.xs),
        Container(
          constraints: const BoxConstraints(minHeight: 56),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MmsRadius.sm),
            border: Border.all(color: colors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: colors.surfaceSubtle,
            child: SwitchListTile(
              key: const Key('windows_autostart_switch'),
              value: trayState.autoStartEnabled,
              onChanged:
                  (!trayState.isSupported ||
                      trayState.isAutoStartBusy ||
                      trayState.isExiting)
                  ? null
                  : (val) => controller.setAutoStartEnabled(val),
              title: Text(
                'Windows açılışında otomatik başlat',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              subtitle: Text(
                'Yalnızca mevcut Windows kullanıcısı için istemci arayüzünü başlatır (HKCU Run, yönetici yetkisi gerekmez). Master Hub servisi (MarketMMSService) bu ayardan bağımsızdır.',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ),
        ),
        if (trayState.lastError != null) ...[
          const SizedBox(height: MmsSpacing.sm),
          DiagnosticsInlineBanner(
            tone: AppBadgeTone.warning,
            message: trayState.lastError!,
          ),
        ],
        const SizedBox(height: MmsSpacing.md),
        Wrap(
          spacing: MmsSpacing.sm,
          runSpacing: MmsSpacing.sm,
          children: [
            AppButton(
              key: const Key('windows_minimize_to_tray_button'),
              label: 'Tepsiye Küçült',
              icon: Icons.minimize_rounded,
              variant: AppButtonVariant.secondary,
              minHeight: 48,
              onPressed: (!trayState.isSupported || trayState.isExiting)
                  ? null
                  : controller.hideToTray,
            ),
            AppButton(
              key: const Key('windows_controlled_exit_button'),
              label: 'Uygulamadan Güvenli Çık',
              icon: Icons.power_settings_new_rounded,
              variant: AppButtonVariant.danger,
              minHeight: 48,
              isLoading: trayState.isExiting,
              onPressed: trayState.isExiting
                  ? null
                  : controller.performControlledExit,
            ),
          ],
        ),
      ],
    );
  }
}
