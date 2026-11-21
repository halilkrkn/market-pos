import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/platform/mms_ui_profile.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../catalog/presentation/screens/catalog_screen.dart';
import '../../../dashboard/presentation/screens/dashboard_screen.dart';
import '../../../diagnostics/presentation/screens/diagnostics_view.dart';
import '../../../pos/presentation/screens/pos_screen.dart';
import '../../../sales/presentation/screens/sales_history_screen.dart';
import '../../../setup/presentation/widgets/first_setup_wizard_dialog.dart';
import '../../../setup/setup_providers.dart';
import '../../../stock/presentation/screens/stock_screen.dart';
import '../../domain/app_destination.dart';
import '../../shell_providers.dart';
import '../widgets/desktop_shell_layout.dart';
import '../widgets/mobile_shell_layout.dart';

/// MARKET MMS — Platform ve Pencere Sınıfı Duyarlı Uygulama İskeleti.
///
/// Windows masaüstü ([DesktopShellLayout]) ile Android telefon/tablet
/// ([MobileShellLayout]) navigasyon kabuklarını ayırır; aktif ekran durumu
/// [activeDestinationProvider] üzerinden yönetilir ve tüm modüller ortak
/// Riverpod state / domain katmanını tüketir.
class MainShellScreen extends ConsumerWidget {
  const MainShellScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiProfile = ref.watch(mmsUiProfileProvider);
    final selectedDestination = ref.watch(activeDestinationProvider);
    final windowClass = context.windowClass;
    final setupConfig = ref.watch(setupConfigProvider);
    final showSetupBanner =
        ref.watch(setupWizardBannerEnabledProvider) &&
        !setupConfig.isSetupCompleted;

    void selectDestination(AppDestination destination) {
      if (ref.read(activeDestinationProvider) == destination) return;
      ref.read(activeDestinationProvider.notifier).state = destination;
    }

    final colors = context.mmsColors;
    final innerContent = _buildContent(selectedDestination, selectDestination);

    final content = showSetupBanner
        ? Column(
            children: [
              Material(
                color: colors.infoBg,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: MmsSpacing.md,
                    vertical: MmsSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.storefront_rounded,
                        size: 18,
                        color: colors.infoText,
                      ),
                      const SizedBox(width: MmsSpacing.sm),
                      Expanded(
                        child: Text(
                          'İlk mağaza/cihaz kurulumu henüz tamamlanmadı.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: colors.infoText,
                          ),
                        ),
                      ),
                      TextButton(
                        key: const Key('shell_setup_wizard_cta'),
                        onPressed: () => FirstSetupWizardDialog.show(context),
                        child: const Text('Kurulumu Tamamla'),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(child: innerContent),
            ],
          )
        : innerContent;

    if (uiProfile.useMobileLayout(windowClass)) {
      return MobileShellLayout(
        selectedDestination: selectedDestination,
        onSelectDestination: selectDestination,
        child: content,
      );
    }

    return DesktopShellLayout(
      selectedDestination: selectedDestination,
      onSelectDestination: selectDestination,
      child: content,
    );
  }

  Widget _buildContent(
    AppDestination destination,
    ValueChanged<AppDestination> onSelectDestination,
  ) {
    switch (destination) {
      case AppDestination.pos:
        return const PosScreen();
      case AppDestination.dashboard:
        return DashboardScreen(
          onNavigateToPos: () => onSelectDestination(AppDestination.pos),
          onNavigateToStock: () => onSelectDestination(AppDestination.stock),
          onNavigateToSales: () => onSelectDestination(AppDestination.sales),
        );
      case AppDestination.catalog:
        return const CatalogScreen();
      case AppDestination.stock:
        return const StockScreen();
      case AppDestination.sales:
        return const SalesHistoryScreen();
      case AppDestination.diagnostics:
        return const DiagnosticsView();
    }
  }
}
