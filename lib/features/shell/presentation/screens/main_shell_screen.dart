import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../diagnostics/presentation/screens/diagnostics_view.dart';
import '../widgets/cashier_header_bar.dart';

/// MARKET MMS - Windows Masaüstü Ana İskelet Ekranı (Main Shell)
class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  int _selectedIndex = 3; // Faz 1.1'de Sistem Tanılama varsayılan aktiftir

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // 1. Üst Kasa Başlık Çubuğu
          const CashierHeaderBar(),

          // 2. Ana Gövde (Sol Menü + İçerik)
          Expanded(
            child: Row(
              children: [
                // Sol Navigasyon Rayı
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) {
                    setState(() {
                      _selectedIndex = index;
                    });
                  },
                  labelType: NavigationRailLabelType.all,
                  minWidth: 84,
                  backgroundColor: Colors.white,
                  indicatorColor: AppTheme.primaryBlue.withValues(alpha: 0.12),
                  selectedIconTheme: const IconThemeData(
                    color: AppTheme.primaryBlue,
                  ),
                  unselectedIconTheme: const IconThemeData(
                    color: AppTheme.textMutedLight,
                  ),
                  selectedLabelTextStyle: const TextStyle(
                    color: AppTheme.primaryBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  unselectedLabelTextStyle: const TextStyle(
                    color: AppTheme.textMutedLight,
                    fontSize: 11,
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.shopping_cart_outlined),
                      selectedIcon: Icon(Icons.shopping_cart),
                      label: Text('Kasa (Satış)'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.inventory_2_outlined),
                      selectedIcon: Icon(Icons.inventory_2),
                      label: Text('Ürünler'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.bar_chart_outlined),
                      selectedIcon: Icon(Icons.bar_chart),
                      label: Text('Raporlar'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_suggest_outlined),
                      selectedIcon: Icon(Icons.settings_suggest),
                      label: Text('Sistem & Tanı'),
                    ),
                  ],
                ),
                const VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: AppTheme.borderSubtle,
                ),

                // Sağ İçerik Alanı
                Expanded(child: _buildContent(_selectedIndex)),
              ],
            ),
          ),

          // 3. Alt Durum ve Kısayol Bilgi Çubuğu (Cashier Ergonomics)
          _buildShortcutFooter(context),
        ],
      ),
    );
  }

  Widget _buildContent(int index) {
    switch (index) {
      case 0:
        return _buildModulePlaceholder(
          title: 'Kasa / Satış Modülü (POS)',
          phase: 'Faz 1.2 — Satış Ekranı & Sepet Yönetimi',
          description: 'Bu modül Faz 1.2 kapsamında barkod okuyucu, dokunmatik sepet, kesirli miktar ve ödeme dialogu ile aktif edilecektir.',
          icon: Icons.shopping_cart_outlined,
        );
      case 1:
        return _buildModulePlaceholder(
          title: 'Ürün ve Stok Yönetimi',
          phase: 'Faz 2 — Ürün & Kategori Yönetimi',
          description: 'Merkezi Shelf API üzerinden ürün ekleme, fiyat güncelleme, stok sayımı ve birim dönüşümü işlemleri Faz 2\'de gelecektir.',
          icon: Icons.inventory_2_outlined,
        );
      case 2:
        return _buildModulePlaceholder(
          title: 'Kasa ve Finansal Raporlar',
          phase: 'Faz 3 — Raporlama & Dashboard',
          description: 'Gün sonu Z-Raporu, KDV dökümü, nakit/kart dağılımı ve kârlılık metrikleri Faz 3\'te eklenecektir.',
          icon: Icons.bar_chart_outlined,
        );
      case 3:
      default:
        return const DiagnosticsView();
    }
  }

  Widget _buildModulePlaceholder({
    required String title,
    required String phase,
    required String description,
    required IconData icon,
  }) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderSubtle),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: AppTheme.primaryBlue),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textMainLight,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                phase,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryBlue,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppTheme.textMutedLight,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShortcutFooter(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceLight,
        border: Border(top: BorderSide(color: AppTheme.borderSubtle, width: 1)),
      ),
      child: const Row(
        children: [
          _ShortcutItem(keyLabel: 'F1', text: 'Yardım'),
          _ShortcutItem(keyLabel: 'F2', text: 'Miktar'),
          _ShortcutItem(keyLabel: 'F9', text: 'Kart'),
          _ShortcutItem(keyLabel: 'F10', text: 'Nakit'),
          _ShortcutItem(keyLabel: 'Esc', text: 'İptal'),
          Spacer(),
          Text(
            'MARKET MMS v1.0.0 • On-Premises Local Master Hub Mimarisi',
            style: TextStyle(fontSize: 11, color: AppTheme.textMutedLight),
          ),
        ],
      ),
    );
  }
}

class _ShortcutItem extends StatelessWidget {
  final String keyLabel;
  final String text;

  const _ShortcutItem({required this.keyLabel, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 18),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: const Color(0xFFCBD5E1), width: 1),
            ),
            child: Text(
              keyLabel,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                color: AppTheme.textMainLight,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textMutedLight,
            ),
          ),
        ],
      ),
    );
  }
}
