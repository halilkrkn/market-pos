import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import 'app_brand_logo.dart';
import 'app_buttons.dart';
import 'app_feedback.dart';

/// Standartlaştırılmış sayfa başlığı (Mobile-safe: Expanded + Wrap).
class AppPageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  const AppPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    final isCompact = context.windowClass == MmsWindowClass.compact;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isCompact ? 19 : 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: colors.textPrimary,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                ),
              ],
            ],
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(width: MmsSpacing.sm),
          Wrap(
            spacing: MmsSpacing.xs,
            runSpacing: MmsSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          ),
        ],
      ],
    );
  }
}

/// Standartlaştırılmış bölüm başlığı.
class AppSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const AppSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: MmsSpacing.xs),
          trailing!,
        ],
      ],
    );
  }
}

/// Duyarlı filtre çubuğu:
/// - Geniş ekran (>=720px): Tek satırda arama + inline filtreler + aksiyon.
/// - Mobil (<720px): Arama kutusu + "Filtreler" BottomSheet tetikleyici + primary aksiyon.
class AppFilterBar extends StatelessWidget {
  final Widget searchField;
  final List<Widget> filters;
  final Widget? primaryAction;
  final int activeFilterCount;
  final String filterSheetTitle;

  const AppFilterBar({
    super.key,
    required this.searchField,
    this.filters = const [],
    this.primaryAction,
    this.activeFilterCount = 0,
    this.filterSheetTitle = 'Filtrele',
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;

    return Container(
      padding: const EdgeInsets.all(MmsSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(MmsRadius.lg),
        border: Border.all(color: colors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 740) {
            return Row(
              children: [
                Expanded(child: searchField),
                for (final f in filters) ...[
                  const SizedBox(width: MmsSpacing.xs),
                  f,
                ],
                if (primaryAction != null) ...[
                  const SizedBox(width: MmsSpacing.sm),
                  primaryAction!,
                ],
              ],
            );
          }

          // Mobil / dar ekran düzeni: sıfır taşma!
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchField,
              if (filters.isNotEmpty || primaryAction != null) ...[
                const SizedBox(height: MmsSpacing.xs),
                Row(
                  children: [
                    if (filters.isNotEmpty)
                      Expanded(
                        child: AppButton(
                          label: activeFilterCount > 0
                              ? 'Filtreler ($activeFilterCount)'
                              : 'Filtreler',
                          icon: Icons.tune_rounded,
                          variant: AppButtonVariant.secondary,
                          minHeight: 48,
                          onPressed: () {
                            AppBottomSheet.show<void>(
                              context: context,
                              title: filterSheetTitle,
                              builder: (_) => Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (int i = 0; i < filters.length; i++) ...[
                                    if (i > 0)
                                      const SizedBox(height: MmsSpacing.sm),
                                    filters[i],
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    if (filters.isNotEmpty && primaryAction != null)
                      const SizedBox(width: MmsSpacing.xs),
                    if (primaryAction != null) Expanded(child: primaryAction!),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class AppNavItem {
  final String label;
  final String shortLabel;
  final IconData icon;
  final IconData selectedIcon;

  const AppNavItem({
    required this.label,
    required this.shortLabel,
    required this.icon,
    required this.selectedIcon,
  });
}

/// Adaptif Navigasyon Bileşeni:
/// - Desktop (>=1024px): Modern Emerald Forest Sol Sidebar
/// - Tablet (600–1023px): NavigationRail
/// - Mobil (<600px): Bottom NavigationBar
class AppNavigation {
  static Widget buildDesktopSidebar({
    required BuildContext context,
    required List<AppNavItem> items,
    required int selectedIndex,
    required ValueChanged<int> onSelect,
    required Widget footer,
  }) {
    final colors = context.mmsColors;

    return Container(
      width: 236,
      decoration: BoxDecoration(
        color: colors.sidebarBg,
        border: Border(
          right: BorderSide(
            color: colors.border.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Marka Logosu (orijinal logo, çerçevesiz, en-boy oranı korunmuş)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MmsSpacing.md,
              MmsSpacing.lg,
              MmsSpacing.md,
              MmsSpacing.md,
            ),
            child: const AppBrandLogo.lockup(
              size: 36,
              useLightText: true,
              compact: true,
              subtitle: 'Retail Operations',
            ),
          ),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: MmsSpacing.sm),

          // Menü Öğeleri
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: MmsSpacing.sm),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final isSelected = index == selectedIndex;

                return Padding(
                  padding: const EdgeInsets.only(bottom: MmsSpacing.xxs),
                  child: Material(
                    color: isSelected
                        ? colors.sidebarActiveBg
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(MmsRadius.md),
                    child: InkWell(
                      onTap: () => onSelect(index),
                      borderRadius: BorderRadius.circular(MmsRadius.md),
                      hoverColor: Colors.white.withValues(alpha: 0.06),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 46),
                        padding: const EdgeInsets.symmetric(
                          horizontal: MmsSpacing.sm,
                          vertical: MmsSpacing.xs + 2,
                        ),
                        child: Row(
                          children: [
                            // Kontrollü Lime Accent aktif çizgisi
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              width: 3,
                              height: isSelected ? 20 : 0,
                              margin: const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(
                                color: colors.limeAccent,
                                borderRadius: BorderRadius.circular(
                                  MmsRadius.pill,
                                ),
                              ),
                            ),
                            Icon(
                              isSelected ? item.selectedIcon : item.icon,
                              size: 20,
                              color: isSelected
                                  ? colors.limeAccent
                                  : colors.sidebarTextMuted,
                            ),
                            const SizedBox(width: MmsSpacing.sm),
                            Expanded(
                              child: Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: MmsTypography.fontFamily,
                                  fontSize: 13.5,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? colors.sidebarText
                                      : colors.sidebarTextMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          Divider(height: 1, color: Colors.white.withValues(alpha: 0.1)),
          Padding(padding: const EdgeInsets.all(MmsSpacing.sm), child: footer),
        ],
      ),
    );
  }

  static Widget buildTabletRail({
    required BuildContext context,
    required List<AppNavItem> items,
    required int selectedIndex,
    required ValueChanged<int> onSelect,
    Widget? trailing,
  }) {
    final colors = context.mmsColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: NavigationRail(
                selectedIndex: selectedIndex,
                onDestinationSelected: onSelect,
                labelType: NavigationRailLabelType.all,
                minWidth: 80,
                backgroundColor: colors.surface,
                indicatorColor: colors.emerald.withValues(alpha: 0.14),
                selectedIconTheme: IconThemeData(
                  color: colors.emerald,
                  size: 22,
                ),
                unselectedIconTheme: IconThemeData(
                  color: colors.textSecondary,
                  size: 22,
                ),
                selectedLabelTextStyle: TextStyle(
                  fontFamily: MmsTypography.fontFamily,
                  color: colors.primary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelTextStyle: TextStyle(
                  fontFamily: MmsTypography.fontFamily,
                  color: colors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                trailing: trailing != null
                    ? Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(
                              bottom: MmsSpacing.md,
                            ),
                            child: trailing,
                          ),
                        ),
                      )
                    : null,
                destinations: items
                    .map(
                      (i) => NavigationRailDestination(
                        icon: Icon(i.icon),
                        selectedIcon: Icon(i.selectedIcon),
                        label: Text(i.label),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget buildMobileBottomBar({
    required BuildContext context,
    required List<AppNavItem> items,
    required int selectedIndex,
    required ValueChanged<int> onSelect,
  }) {
    final colors = context.mmsColors;
    // Alt navigasyonda ilk 5 ana destinasyonu göster; Sistem & Tanı üst çubuktan da açılır
    final visibleItems = items.take(5).toList();
    final isOverflowDestination = selectedIndex >= visibleItems.length;
    final safeIndex = isOverflowDestination ? 0 : selectedIndex;

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: NavigationBar(
        selectedIndex: safeIndex,
        indicatorColor: isOverflowDestination ? Colors.transparent : null,
        onDestinationSelected: onSelect,
        destinations: visibleItems
            .map(
              (i) => NavigationDestination(
                icon: Icon(i.icon),
                selectedIcon: Icon(i.selectedIcon),
                label: i.shortLabel,
              ),
            )
            .toList(),
      ),
    );
  }
}
