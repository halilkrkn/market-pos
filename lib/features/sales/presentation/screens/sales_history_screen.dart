import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/platform/mms_ui_profile.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/debouncer.dart';
import '../../../pos/domain/money.dart';
import '../../application/sales_history_state.dart';
import '../../domain/models/sale_history_filter.dart';
import '../../sales_providers.dart';
import '../widgets/sale_detail_dialog.dart';
import '../widgets/sale_status_badge.dart';

/// MARKET MMS — Satış Geçmişi ve Finansal Raporlar Ekranı (Modern Emerald)
class SalesHistoryScreen extends ConsumerStatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  ConsumerState<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends ConsumerState<SalesHistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Debouncer _searchDebouncer = Debouncer();

  @override
  void initState() {
    super.initState();
    final initialQuery = ref.read(salesHistoryProvider).filter.searchQuery;
    if (initialQuery != null && initialQuery.isNotEmpty) {
      _searchController.text = initialQuery;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = ref.read(salesHistoryProvider);
      ref
          .read(salesHistoryProvider.notifier)
          .loadSales(silent: current.sales.isNotEmpty);
    });
  }

  @override
  void dispose() {
    _searchDebouncer.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    _searchDebouncer.run(() {
      if (!mounted) return;
      final currentFilter = ref.read(salesHistoryProvider).filter;
      ref
          .read(salesHistoryProvider.notifier)
          .setFilter(currentFilter.copyWith(searchQuery: val));
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _searchDebouncer.runImmediate(() {
      if (!mounted) return;
      final currentFilter = ref.read(salesHistoryProvider).filter;
      ref
          .read(salesHistoryProvider.notifier)
          .setFilter(currentFilter.copyWith(searchQuery: ''));
    });
  }

  void _onPaymentMethodFilterChanged(String? method) {
    final currentFilter = ref.read(salesHistoryProvider).filter;
    ref
        .read(salesHistoryProvider.notifier)
        .setFilter(
          SaleHistoryFilter(
            startDate: currentFilter.startDate,
            endDate: currentFilter.endDate,
            paymentMethod: method == 'ALL' ? null : method,
            status: currentFilter.status,
            searchQuery: currentFilter.searchQuery,
          ),
        );
  }

  void _onStatusFilterChanged(String? status) {
    final currentFilter = ref.read(salesHistoryProvider).filter;
    ref
        .read(salesHistoryProvider.notifier)
        .setFilter(
          SaleHistoryFilter(
            startDate: currentFilter.startDate,
            endDate: currentFilter.endDate,
            paymentMethod: currentFilter.paymentMethod,
            status: status == 'ALL' ? null : status,
            searchQuery: currentFilter.searchQuery,
          ),
        );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final activeFilter = ref.read(salesHistoryProvider).filter;
    final initialRange =
        (activeFilter.startDate != null && activeFilter.endDate != null)
            ? DateTimeRange(
                start: activeFilter.startDate!,
                end: activeFilter.endDate!,
              )
            : DateTimeRange(
                start: now.subtract(const Duration(days: 7)),
                end: now,
              );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initialRange,
    );

    if (!mounted || picked == null) return;

    final currentFilter = ref.read(salesHistoryProvider).filter;
    ref
        .read(salesHistoryProvider.notifier)
        .setFilter(
          currentFilter.copyWith(
            startDate: DateTime(
              picked.start.year,
              picked.start.month,
              picked.start.day,
              0,
              0,
              0,
            ),
            endDate: DateTime(
              picked.end.year,
              picked.end.month,
              picked.end.day,
              23,
              59,
              59,
            ),
          ),
        );
  }

  void _clearDateFilter() {
    final currentFilter = ref.read(salesHistoryProvider).filter;
    ref
        .read(salesHistoryProvider.notifier)
        .setFilter(currentFilter.copyWith(clearDates: true));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(salesHistoryProvider);
    final colors = context.mmsColors;
    final uiProfile = ref.watch(mmsUiProfileProvider);
    final isCompact = context.windowClass == MmsWindowClass.compact;
    final touchButtonHeight = (isCompact || uiProfile.isMobile) ? 48.0 : 40.0;

    final activeFilterCount =
        (state.filter.paymentMethod != null ? 1 : 0) +
        (state.filter.status != null ? 1 : 0) +
        (state.filter.startDate != null ? 1 : 0);

    final header = AppPageHeader(
      title: 'Kasa ve Finansal Raporlar',
      subtitle:
          'Tamamlanan satış kayıtları, iptal/iade işlemleri ve fiş inceleme',
      actions: [
        AppIconButton(
          icon: Icons.refresh_rounded,
          tooltip: 'Yenile',
          bordered: true,
          size: (isCompact || uiProfile.isMobile) ? 48 : 44,
          onPressed: () => ref.read(salesHistoryProvider.notifier).loadSales(),
        ),
      ],
    );

    final filterBar = AppFilterBar(
      searchField: AppSearchField(
        controller: _searchController,
        hintText: 'Fiş No veya Kasa ID ile ara...',
        onChanged: _onSearchChanged,
        onClear: _clearSearch,
      ),
      activeFilterCount: activeFilterCount,
      filterSheetTitle: 'Satış Filtreleri',
      filters: [
        AppDropdown<String>(
          value: state.filter.paymentMethod ?? 'ALL',
          items: const [
            DropdownMenuItem(value: 'ALL', child: Text('Ödeme: Tümü')),
            DropdownMenuItem(value: 'CASH', child: Text('Nakit')),
            DropdownMenuItem(value: 'CARD', child: Text('Kredi Kartı')),
          ],
          onChanged: _onPaymentMethodFilterChanged,
        ),
        AppDropdown<String>(
          value: state.filter.status ?? 'ALL',
          items: const [
            DropdownMenuItem(value: 'ALL', child: Text('Durum: Tümü')),
            DropdownMenuItem(value: 'COMPLETED', child: Text('Tamamlandı')),
            DropdownMenuItem(value: 'CANCELLED', child: Text('İptal Edildi')),
            DropdownMenuItem(value: 'REFUNDED', child: Text('İade Edildi')),
            DropdownMenuItem(value: 'PARTIALLY_REFUNDED', child: Text('Kısmi İade')),
          ],
          onChanged: _onStatusFilterChanged,
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppButton(
              label: state.filter.startDate != null
                  ? '${state.filter.startDate!.toFormattedShortDate()} - ${state.filter.endDate!.toFormattedShortDate()}'
                  : 'Tarih Aralığı',
              icon: Icons.date_range_rounded,
              variant: AppButtonVariant.secondary,
              minHeight: 48,
              onPressed: _pickDateRange,
            ),
            if (state.filter.startDate != null) ...[
              const SizedBox(width: 4),
              AppIconButton(
                icon: Icons.clear_rounded,
                tooltip: 'Tarih Filtresini Temizle',
                onPressed: _clearDateFilter,
              ),
            ],
          ],
        ),
      ],
    );

    if (isCompact) {
      return Scaffold(
        backgroundColor: colors.background,
        body: RefreshIndicator(
          onRefresh: () => ref.read(salesHistoryProvider.notifier).loadSales(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(MmsSpacing.md),
            children: [
              header,
              const SizedBox(height: MmsSpacing.md),
              if (state.errorMessage != null) ...[
                AppErrorState(
                  message: state.errorMessage!,
                  inline: true,
                  onRetry: () =>
                      ref.read(salesHistoryProvider.notifier).loadSales(),
                ),
                const SizedBox(height: MmsSpacing.sm),
              ],
              _buildResponsiveKpiGrid(context, state),
              const SizedBox(height: MmsSpacing.sm),
              filterBar,
              const SizedBox(height: MmsSpacing.sm),
              if (state.isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: MmsSpacing.xl),
                  child: AppLoadingState(message: 'Satış geçmişi yükleniyor...'),
                )
              else if (state.sales.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: MmsSpacing.lg),
                  child: AppEmptyState(
                    icon: Icons.inbox_outlined,
                    title: 'Kriterlere uygun satış kaydı bulunamadı.',
                    description: 'Arama terimini veya ödeme/tarih filtrelerini değiştirmeyi deneyin.',
                  ),
                )
              else
                ...state.sales.map(
                  (sale) => Padding(
                    padding: const EdgeInsets.only(bottom: MmsSpacing.xs),
                    child: _buildMobileSaleCard(
                      context,
                      sale,
                      minButtonHeight: touchButtonHeight,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.background,
      body: Padding(
        padding: const EdgeInsets.all(MmsSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: MmsSpacing.md),

            if (state.errorMessage != null) ...[
              AppErrorState(
                message: state.errorMessage!,
                inline: true,
                onRetry: () =>
                    ref.read(salesHistoryProvider.notifier).loadSales(),
              ),
              const SizedBox(height: MmsSpacing.sm),
            ],

            // 1. Duyarlı KPI Özet Kartları
            _buildResponsiveKpiGrid(context, state),
            const SizedBox(height: MmsSpacing.md),

            // 2. Duyarlı Filtreleme Çubuğu
            filterBar,
            const SizedBox(height: MmsSpacing.md),

            // 3. Fiş Listesi (Masaüstü Tablo / Tablet Kartlar)
            Expanded(
              child: state.isLoading
                  ? const AppLoadingState(
                      message: 'Satış geçmişi yükleniyor...',
                    )
                  : state.sales.isEmpty
                  ? const AppEmptyState(
                      icon: Icons.inbox_outlined,
                      title: 'Kriterlere uygun satış kaydı bulunamadı.',
                      description: 'Arama terimini veya ödeme/tarih filtrelerini değiştirmeyi deneyin.',
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth >= 740) {
                          return _buildDesktopSalesTable(context, state);
                        }
                        return _buildMobileSalesCards(context, state);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResponsiveKpiGrid(
    BuildContext context,
    SalesHistoryState state,
  ) {
    final cards = [
      AppStatCard(
        title: 'Toplam Satış Adedi',
        value: '${state.totalSalesCount}',
        icon: Icons.receipt_outlined,
        tone: AppBadgeTone.info,
      ),
      AppStatCard(
        title: 'Brüt Satış Cirosu',
        value: Money.formatCents(state.totalGrossAmount),
        icon: Icons.point_of_sale_outlined,
        tone: AppBadgeTone.success,
      ),
      AppStatCard(
        title: 'İptal Edilen Tutar',
        value: Money.formatCents(state.totalCancelledAmount),
        icon: Icons.cancel_outlined,
        tone: AppBadgeTone.danger,
      ),
      AppStatCard(
        title: 'Net Satış Cirosu',
        value: Money.formatCents(
          state.totalGrossAmount - state.totalCancelledAmount,
        ),
        icon: Icons.account_balance_wallet_outlined,
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
                  SizedBox(width: 204, child: cards[i]),
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

  Widget _buildDesktopSalesTable(
    BuildContext context,
    SalesHistoryState state,
  ) {
    final colors = context.mmsColors;

    return AppDataTable(
      header: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              'Fiş No & Zaman',
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
              'Ödeme & Kasa',
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
              'Tutar',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 120),
        ],
      ),
      itemCount: state.sales.length,
      itemBuilder: (context, index) {
        final sale = state.sales[index];
        final isCancelled = sale.status == 'CANCELLED';

        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MmsSpacing.md,
            vertical: MmsSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: sale.paymentMethod == 'CARD'
                            ? colors.infoBg
                            : colors.successBg,
                        borderRadius: BorderRadius.circular(MmsRadius.sm),
                      ),
                      child: Icon(
                        sale.paymentMethod == 'CARD'
                            ? Icons.credit_card_rounded
                            : Icons.payments_outlined,
                        color: sale.paymentMethod == 'CARD'
                            ? colors.infoText
                            : colors.successText,
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: MmsSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sale.id,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              color: colors.textPrimary,
                              fontFeatures: MmsTypography.tabularFigures,
                            ),
                          ),
                          Text(
                            'Tarih: ${sale.createdAt.toFormattedDateTime()} • #${sale.clientSeq}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: colors.textSecondary,
                              fontFeatures: MmsTypography.tabularFigures,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sale.paymentMethod == 'CARD' ? 'Kredi Kartı' : 'Nakit',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      sale.deviceId,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SaleStatusBadge.fromStatus(sale.status),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  Money.formatCents(sale.totalAmount),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    fontFeatures: MmsTypography.tabularFigures,
                    color: isCancelled
                        ? colors.textTertiary
                        : colors.textPrimary,
                    decoration: isCancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              const SizedBox(width: MmsSpacing.sm),
              SizedBox(
                width: 108,
                child: AppButton(
                  label: 'Fiş Detay',
                  variant: AppButtonVariant.secondary,
                  minHeight: 40,
                  onPressed: () => _openSaleDetail(sale),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMobileSalesCards(BuildContext context, SalesHistoryState state) {
    final isMobile = ref.watch(mmsUiProfileProvider).isMobile ||
        context.windowClass == MmsWindowClass.compact;
    return RefreshIndicator(
      onRefresh: () => ref.read(salesHistoryProvider.notifier).loadSales(),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.sales.length,
        separatorBuilder: (_, _) => const SizedBox(height: MmsSpacing.xs),
        itemBuilder: (context, index) => _buildMobileSaleCard(
          context,
          state.sales[index],
          minButtonHeight: isMobile ? 48.0 : 40.0,
        ),
      ),
    );
  }

  Widget _buildMobileSaleCard(
    BuildContext context,
    LocalSale sale, {
    double minButtonHeight = 48.0,
  }) {
    final colors = context.mmsColors;
    final isCancelled = sale.status == 'CANCELLED';

    return AppCard(
      padding: const EdgeInsets.all(MmsSpacing.md),
      onTap: () => _openSaleDetail(sale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  sale.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: colors.textPrimary,
                    fontFeatures: MmsTypography.tabularFigures,
                  ),
                ),
              ),
              const SizedBox(width: MmsSpacing.xs),
              SaleStatusBadge.fromStatus(sale.status),
            ],
          ),
          const SizedBox(height: MmsSpacing.xs),
          Text(
            '${sale.createdAt.toFormattedDateTime()} • ${sale.paymentMethod == 'CARD' ? 'Kart' : 'Nakit'} • #${sale.clientSeq}',
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
              fontFeatures: MmsTypography.tabularFigures,
            ),
          ),
          const SizedBox(height: MmsSpacing.sm),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    Money.formatCents(sale.totalAmount),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      fontFeatures: MmsTypography.tabularFigures,
                      color: isCancelled
                          ? colors.textTertiary
                          : colors.textPrimary,
                      decoration: isCancelled
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: MmsSpacing.xs),
              AppButton(
                label: 'Fiş Detay',
                variant: AppButtonVariant.secondary,
                minHeight: minButtonHeight,
                onPressed: () => _openSaleDetail(sale),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openSaleDetail(LocalSale sale) async {
    await ref.read(salesHistoryProvider.notifier).selectSale(sale.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => SaleDetailDialog(saleId: sale.id),
    );
  }
}
