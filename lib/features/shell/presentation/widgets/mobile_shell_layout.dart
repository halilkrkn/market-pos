import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../domain/app_destination.dart';
import '../app_nav_items.dart';
import 'cashier_header_bar.dart';

/// Android Telefon ve Tablet uygulama kabuğu.
///
/// Masaüstü klavye kısayol alt çubuğunu göstermez; telefonlarda dokunmatik alt
/// navigasyon çubuğu, Android tabletlerde yan `NavigationRail` kullanır.
class MobileShellLayout extends StatelessWidget {
  final AppDestination selectedDestination;
  final ValueChanged<AppDestination> onSelectDestination;
  final Widget child;

  const MobileShellLayout({
    super.key,
    required this.selectedDestination,
    required this.onSelectDestination,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    final windowClass = context.windowClass;
    final isCompact = windowClass == MmsWindowClass.compact;
    final selectedIndex = selectedDestination.navIndex;
    final isDiagnostics = selectedDestination == AppDestination.diagnostics;

    // Android Tablet / Yatay Geniş Ekran (>= 600px): Yan NavigationRail + Kısayol Çubuğu Yok
    if (!isCompact) {
      return Scaffold(
        key: const Key('mobile_tablet_shell'),
        backgroundColor: colors.background,
        body: Column(
          children: [
            CashierHeaderBar(
              showBrandLogo: true,
              isDiagnosticsSelected: isDiagnostics,
              onOpenDiagnostics: () =>
                  onSelectDestination(AppDestination.diagnostics),
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
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: colors.border,
                  ),
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Android Telefon (< 600px): Kompakt Üst Çubuk + Alt NavigationBar + SafeArea
    return Scaffold(
      key: const Key('mobile_phone_shell'),
      backgroundColor: colors.background,
      body: Column(
        children: [
          CashierHeaderBar(
            showBrandLogo: true,
            isDiagnosticsSelected: isDiagnostics,
            onOpenDiagnostics: () =>
                onSelectDestination(AppDestination.diagnostics),
          ),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: AppNavigation.buildMobileBottomBar(
        context: context,
        items: kAppNavItems,
        selectedIndex: selectedIndex,
        onSelect: (idx) => onSelectDestination(AppDestinationX.fromIndex(idx)),
      ),
    );
  }
}
