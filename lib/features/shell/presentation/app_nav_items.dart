import 'package:flutter/material.dart';

import '../../../core/design_system/design_system.dart';
import '../domain/app_destination.dart';

/// Ana modül gezinme öğeleri (ikon/etiket) — sunum katmanı meta verisi.
/// Sıra [AppDestination] enum sırasıyla birebir aynıdır.
const List<AppNavItem> kAppNavItems = [
  AppNavItem(
    label: 'Kasa (Satış)',
    shortLabel: 'Kasa',
    icon: Icons.shopping_cart_outlined,
    selectedIcon: Icons.shopping_cart_rounded,
  ),
  AppNavItem(
    label: 'Dashboard',
    shortLabel: 'Özet',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard_rounded,
  ),
  AppNavItem(
    label: 'Ürünler',
    shortLabel: 'Ürünler',
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2_rounded,
  ),
  AppNavItem(
    label: 'Stok',
    shortLabel: 'Stok',
    icon: Icons.warehouse_outlined,
    selectedIcon: Icons.warehouse_rounded,
  ),
  AppNavItem(
    label: 'Raporlar',
    shortLabel: 'Raporlar',
    icon: Icons.bar_chart_outlined,
    selectedIcon: Icons.bar_chart_rounded,
  ),
  AppNavItem(
    label: 'Ayarlar ve Sistem',
    shortLabel: 'Ayarlar',
    icon: Icons.settings_suggest_outlined,
    selectedIcon: Icons.settings_suggest_rounded,
  ),
];

extension AppDestinationNavItemX on AppDestination {
  AppNavItem get navItem => kAppNavItems[index];
}
