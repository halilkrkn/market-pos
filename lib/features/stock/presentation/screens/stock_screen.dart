import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/platform/mms_ui_profile.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/debouncer.dart';
import '../../../../core/utils/user_friendly_error_mapper.dart';
import '../../../catalog/catalog_providers.dart';
import '../../../catalog/presentation/widgets/price_history_dialog.dart';
import '../../../catalog/presentation/widgets/product_edit_dialog.dart';
import '../../../dashboard/dashboard_providers.dart';
import '../../../diagnostics/application/system_status_notifier.dart';
import '../../../pos/domain/money.dart';
import '../../stock_providers.dart';
import '../widgets/stock_movement_labels.dart';
import 'stock_receipt_screen.dart';

/// MARKET MMS — Stok Durumu ve Hareket Geçmişi Ekranı
///
/// Yalnızca mevcut yerel `local_products` ve `local_stock_movements`
/// tablolarındaki gerçek verileri gösterir; uydurma stok işlemi eklemez.
class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});

  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final Debouncer _searchDebouncer = Debouncer();
  String _searchQuery = '';
  StockStatusFilter _filter = StockStatusFilter.all;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _searchDebouncer.dispose();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    final stockAsync = ref.watch(stockOverviewProvider);
    final uiProfile = ref.watch(mmsUiProfileProvider);
    final isCompact = context.windowClass == MmsWindowClass.compact;
    final touchIconSize = (isCompact || uiProfile.isMobile) ? 48.0 : 44.0;

    return Padding(
      padding: EdgeInsets.all(isCompact ? MmsSpacing.md : MmsSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppPageHeader(
            title: 'Stok Yönetimi',
            subtitle: 'Anlık ürün stok seviyeleri, kritik uyarılar ve hareket defteri',
            actions: [
              if (isCompact)
                AppIconButton(
                  key: const Key('stock_receipt_open_button'),
                  icon: Icons.move_to_inbox_rounded,
                  tooltip: 'Stok Girişi',
                  bordered: true,
                  size: touchIconSize,
                  onPressed: _openStockReceipt,
                )
              else
                AppButton(
                  key: const Key('stock_receipt_open_button'),
                  label: 'Stok Girişi',
                  icon: Icons.move_to_inbox_rounded,
                  variant: AppButtonVariant.emerald,
                  minHeight: touchIconSize,
                  onPressed: _openStockReceipt,
                ),
              const SizedBox(width: MmsSpacing.sm),
              AppIconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Stok Verilerini Yenile',
                bordered: true,
                size: touchIconSize,
                onPressed: () => ref.invalidate(stockOverviewProvider),
              ),
            ],
          ),
          const SizedBox(height: MmsSpacing.md),
          Expanded(
            child: stockAsync.when(
              loading: () => const AppLoadingState(
                message: 'Stok kayıtları yükleniyor...',
              ),
              error: (err, _) => AppErrorState(
                message: UserFriendlyErrorMapper.map(
                  err,
                  fallback: 'Stok kayıtları okunamadı. Lütfen tekrar deneyin.',
                ),
                onRetry: () => ref.invalidate(stockOverviewProvider),
              ),
              data: (data) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildKpiRow(context, data),
                  const SizedBox(height: MmsSpacing.md),
                  Container(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(MmsRadius.md),
                      border: Border.all(color: colors.border),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      tabs: [
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.inventory_2_rounded, size: 17),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Stok (${data.products.length})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.swap_vert_rounded, size: 17),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Hareketler (${data.movements.length})',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: MmsSpacing.md),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildStockLevelsTab(context, data),
                        _buildMovementsTab(context, data),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiRow(BuildContext context, StockOverviewData data) {
    final cards = [
      AppStatCard(
        title: 'İzlenen Ürün',
        value: '${data.products.length}',
        icon: Icons.inventory_2_rounded,
        tone: AppBadgeTone.info,
      ),
      AppStatCard(
        title: 'Kritik Stok (≤ 5)',
        value: '${data.criticalCount}',
        icon: Icons.warning_amber_rounded,
        tone: data.criticalCount > 0
            ? AppBadgeTone.warning
            : AppBadgeTone.success,
      ),
      AppStatCard(
        title: 'Eksi Stok (Allow)',
        value: '${data.negativeCount}',
        icon: Icons.trending_down_rounded,
        tone: data.negativeCount > 0
            ? AppBadgeTone.danger
            : AppBadgeTone.neutral,
      ),
      AppStatCard(
        title: 'Kayıtlı Hareket',
        value: '${data.movements.length}',
        icon: Icons.history_rounded,
        tone: AppBadgeTone.lime,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        if (w < 600) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: MmsSpacing.xs),
                  SizedBox(width: 192, child: cards[i]),
                ],
              ],
            ),
          );
        }

        final cols = w >= 920 ? 4 : 2;
        final itemWidth = (w - (MmsSpacing.sm * (cols - 1))) / cols;
        return Wrap(
          spacing: MmsSpacing.sm,
          runSpacing: MmsSpacing.sm,
          children: cards
              .map((c) => SizedBox(width: itemWidth, child: c))
              .toList(),
        );
      },
    );
  }

  Widget _buildStockLevelsTab(BuildContext context, StockOverviewData data) {
    final q = _searchQuery.trim().toLowerCase();
    final filtered = data.products.where((p) {
      final matchesQuery = q.isEmpty ||
          p.name.toLowerCase().contains(q) ||
          (p.barcode?.toLowerCase().contains(q) ?? false);
      if (!matchesQuery) return false;

      switch (_filter) {
        case StockStatusFilter.all:
          return true;
        case StockStatusFilter.critical:
          return p.stock <= kCriticalStockThresholdMilli;
        case StockStatusFilter.negative:
          return p.stock < 0;
        case StockStatusFilter.outOfStock:
          return p.stock == 0;
      }
    }).toList()
      ..sort((a, b) => a.stock.compareTo(b.stock));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppFilterBar(
          searchField: AppSearchField(
            controller: _searchController,
            hintText: 'Ürün adı veya barkod ara...',
            onChanged: (val) => _searchDebouncer.run(() {
              if (mounted) setState(() => _searchQuery = val);
            }),
            onClear: () {
              _searchController.clear();
              _searchDebouncer.runImmediate(() {
                if (mounted) setState(() => _searchQuery = '');
              });
            },
          ),
          activeFilterCount: _filter == StockStatusFilter.all ? 0 : 1,
          filterSheetTitle: 'Stok Filtreleri',
          filters: [
            AppDropdown<StockStatusFilter>(
              value: _filter,
              items: const [
                DropdownMenuItem(
                  value: StockStatusFilter.all,
                  child: Text('Durum: Tümü'),
                ),
                DropdownMenuItem(
                  value: StockStatusFilter.critical,
                  child: Text('Kritik (≤ 5)'),
                ),
                DropdownMenuItem(
                  value: StockStatusFilter.negative,
                  child: Text('Eksi Stok (< 0)'),
                ),
                DropdownMenuItem(
                  value: StockStatusFilter.outOfStock,
                  child: Text('Tükenen (= 0)'),
                ),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _filter = val);
              },
            ),
          ],
        ),
        const SizedBox(height: MmsSpacing.md),
        Expanded(
          child: filtered.isEmpty
              ? const AppEmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'Eşleşen stok kaydı bulunamadı',
                  description:
                      'Filtreleri temizleyebilir veya Katalog üzerinden yeni ürün ekleyebilirsiniz.',
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 720) {
                      return _buildDesktopStockTable(context, filtered);
                    }
                    return _buildMobileStockCards(context, filtered);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDesktopStockTable(
    BuildContext context,
    List<LocalProduct> items,
  ) {
    final colors = context.mmsColors;

    return AppDataTable(
      header: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              'Ürün & Barkod',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Mevcut Stok',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Durum',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Birim Fiyat',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 112),
        ],
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final p = items[index];
        final (label, tone) = _stockStatusBadge(p.stock);
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MmsSpacing.md,
            vertical: MmsSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      p.barcode ?? 'Barkodsuz',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textTertiary,
                        fontFeatures: MmsTypography.tabularFigures,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  Money.formatMilliWithUnit(p.stock, p.stockUnit),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: p.stock <= 0 ? colors.dangerText : colors.textPrimary,
                    fontFeatures: MmsTypography.tabularFigures,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AppBadge(label: label, tone: tone, compact: true),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  Money.formatCents(p.price),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                    fontFeatures: MmsTypography.tabularFigures,
                  ),
                ),
              ),
              SizedBox(
                width: 112,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AppIconButton(
                      icon: Icons.history_rounded,
                      tooltip: 'Fiyat Geçmişi',
                      onPressed: () => _openPriceHistory(p),
                    ),
                    AppIconButton(
                      icon: Icons.edit_outlined,
                      tooltip: 'Ürün Detay / Düzenle',
                      onPressed: () => _openProductEdit(p),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMobileStockCards(
    BuildContext context,
    List<LocalProduct> items,
  ) {
    final colors = context.mmsColors;

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(stockOverviewProvider),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: MmsSpacing.xs),
      itemBuilder: (context, index) {
        final p = items[index];
        final (label, tone) = _stockStatusBadge(p.stock);

        return AppCard(
          padding: const EdgeInsets.all(MmsSpacing.md),
          onTap: () => _openProductEdit(p),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: MmsSpacing.xs),
                  AppBadge(label: label, tone: tone, compact: true),
                ],
              ),
              const SizedBox(height: MmsSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Stok: ${Money.formatMilliWithUnit(p.stock, p.stockUnit)}',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: p.stock <= 0
                            ? colors.dangerText
                            : colors.emerald,
                        fontFeatures: MmsTypography.tabularFigures,
                      ),
                    ),
                  ),
                  Text(
                    Money.formatCents(p.price),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                      fontFeatures: MmsTypography.tabularFigures,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
      ),
    );
  }

  Widget _buildMovementsTab(BuildContext context, StockOverviewData data) {
    final colors = context.mmsColors;

    if (data.movements.isEmpty) {
      return const AppEmptyState(
        icon: Icons.swap_vert_rounded,
        title: 'Henüz stok hareketi kaydı yok',
        description:
            'Satış, iptal ve iade işlemlerinde oluşan stok hareketleri burada listelenir.',
      );
    }

    return AppDataTable(
      header: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              'Ürün / Tarih',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Hareket Türü',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Değişim',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
      itemCount: data.movements.length,
      itemBuilder: (context, index) {
        final m = data.movements[index];
        final prod = data.productById[m.productId];
        final isPositive = m.quantity > 0;
        final (typeLabel, tone) = stockMovementLabel(m.movementType);

        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MmsSpacing.md,
            vertical: MmsSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prod?.name ?? m.productId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      m.createdAt.toFormattedDateTime(),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.textTertiary,
                        fontFeatures: MmsTypography.tabularFigures,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AppBadge(label: typeLabel, tone: tone, compact: true),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  '${isPositive ? '+' : ''}${Money.formatMilliWithUnit(m.quantity, m.unit)}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: m.movementType == 'FIRE_KAYIP'
                        ? colors.warningText
                        : isPositive
                            ? colors.successText
                            : colors.dangerText,
                    fontFeatures: MmsTypography.tabularFigures,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  (String, AppBadgeTone) _stockStatusBadge(int stockMilli) {
    if (stockMilli < 0) return ('EKSİ STOK', AppBadgeTone.danger);
    if (stockMilli == 0) return ('TÜKENDİ', AppBadgeTone.danger);
    if (stockMilli <= kCriticalStockThresholdMilli) {
      return ('KRİTİK', AppBadgeTone.warning);
    }
    return ('NORMAL', AppBadgeTone.success);
  }

  Future<void> _openStockReceipt() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const StockReceiptScreen()),
    );
    if (mounted) ref.invalidate(stockOverviewProvider);
  }

  Future<void> _openPriceHistory(LocalProduct p) async {
    final history = await ref
        .read(localDatabaseServiceProvider)
        .repository
        .getPriceHistory(p.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => PriceHistoryDialog(
        productName: p.name,
        history: history,
      ),
    );
  }

  Future<void> _openProductEdit(LocalProduct p) async {
    final categories = ref.read(catalogProvider).categories;
    await showDialog<void>(
      context: context,
      builder: (_) => ProductEditDialog(
        product: p,
        categories: categories,
      ),
    );
    ref.invalidate(stockOverviewProvider);
  }
}
