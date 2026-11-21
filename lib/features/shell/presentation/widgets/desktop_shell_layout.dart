import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../domain/app_destination.dart';
import '../app_nav_items.dart';
import 'cashier_header_bar.dart';

/// Windows Masaüstü uygulama kabuğu (Sol Emerald Sidebar / Dar Pencerede Rail + Kısayol Alt Çubuğu).
class DesktopShellLayout extends ConsumerWidget {
  final AppDestination selectedDestination;
  final ValueChanged<AppDestination> onSelectDestination;
  final Widget child;

  const DesktopShellLayout({
    super.key,
    required this.selectedDestination,
    required this.onSelectDestination,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.mmsColors;
    final windowClass = context.windowClass;
    final selectedIndex = selectedDestination.navIndex;

    // Geniş Masaüstü (>= 1024px): Executive Emerald Sol Sidebar + Kısayol Çubuğu
    if (windowClass == MmsWindowClass.expanded) {
      return Scaffold(
        backgroundColor: colors.background,
        body: Row(
          children: [
            AppNavigation.buildDesktopSidebar(
              context: context,
              items: kAppNavItems,
              selectedIndex: selectedIndex,
              onSelect: (idx) =>
                  onSelectDestination(AppDestinationX.fromIndex(idx)),
              footer: _buildSidebarThemeSwitcher(context, ref),
            ),
            Expanded(
              child: Column(
                children: [
                  CashierHeaderBar(
                    showBrandLogo: false,
                    isDiagnosticsSelected:
                        selectedDestination == AppDestination.diagnostics,
                  ),
                  Expanded(child: child),
                  _buildShortcutFooter(context),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Ara Genişlik Masaüstü Penceresi (600px - 1023px): NavigationRail + Kısayol Çubuğu
    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          CashierHeaderBar(
            showBrandLogo: true,
            isDiagnosticsSelected:
                selectedDestination == AppDestination.diagnostics,
          ),
          Expanded(
            child: Row(
              children: [
                AppNavigation.buildTabletRail(
                  context: context,
                  items: kAppNavItems,
                  selectedIndex: selectedIndex,
                  onSelect: (idx) =>
                      onSelectDestination(AppDestinationX.fromIndex(idx)),
                ),
                VerticalDivider(width: 1, thickness: 1, color: colors.border),
                Expanded(child: child),
              ],
            ),
          ),
          _buildShortcutFooter(context),
        ],
      ),
    );
  }

  Widget _buildSidebarThemeSwitcher(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final colors = context.mmsColors;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(MmsRadius.md),
      ),
      child: Row(
        children: [
          _sidebarThemeOption(
            icon: Icons.light_mode_rounded,
            tooltip: 'Açık Tema',
            selected: themeMode == ThemeMode.light,
            accent: colors.limeAccent,
            onTap: () => ref
                .read(themeModeProvider.notifier)
                .setThemeMode(ThemeMode.light),
          ),
          _sidebarThemeOption(
            icon: Icons.dark_mode_rounded,
            tooltip: 'Koyu Tema',
            selected: themeMode == ThemeMode.dark,
            accent: colors.limeAccent,
            onTap: () => ref
                .read(themeModeProvider.notifier)
                .setThemeMode(ThemeMode.dark),
          ),
          _sidebarThemeOption(
            icon: Icons.brightness_auto_rounded,
            tooltip: 'Sistem Teması',
            selected: themeMode == ThemeMode.system,
            accent: colors.limeAccent,
            onTap: () => ref
                .read(themeModeProvider.notifier)
                .setThemeMode(ThemeMode.system),
          ),
        ],
      ),
    );
  }

  Widget _sidebarThemeOption({
    required IconData icon,
    required String tooltip,
    required bool selected,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(MmsRadius.sm),
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(MmsRadius.sm),
            ),
            child: Icon(
              icon,
              size: 17,
              color: selected ? accent : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShortcutFooter(BuildContext context) {
    final colors = context.mmsColors;

    return Container(
      key: const Key('desktop_shortcut_footer'),
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(
        horizontal: MmsSpacing.md,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceSubtle,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: MmsSpacing.md,
          runSpacing: MmsSpacing.xxs,
          children: [
            Wrap(
              spacing: MmsSpacing.md,
              runSpacing: MmsSpacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _buildKeyHint(context, 'F1', 'Yardım'),
                _buildKeyHint(context, 'F2', 'Miktar'),
                _buildKeyHint(context, 'F9', 'Kart'),
                _buildKeyHint(context, 'F10', 'Nakit'),
                _buildKeyHint(context, 'Esc', 'İptal'),
              ],
            ),
            Text(
              'MARKET MMS v1.0.0 • On-Premises Local Master Hub Mimarisi',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: colors.textTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyHint(BuildContext context, String keyName, String action) {
    final colors = context.mmsColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: colors.borderStrong),
          ),
          child: Text(
            keyName,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
              fontFeatures: MmsTypography.tabularFigures,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          action,
          style: TextStyle(
            fontSize: 11.5,
            color: colors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
