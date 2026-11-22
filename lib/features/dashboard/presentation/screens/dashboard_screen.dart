import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/platform/mms_ui_profile.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/user_friendly_error_mapper.dart';
import '../../../diagnostics/application/system_status_notifier.dart';
import '../../../pos/domain/money.dart';
import '../../../sales/presentation/widgets/sale_detail_dialog.dart';
import '../../../sales/presentation/widgets/sale_status_badge.dart';
import '../../../sales/sales_providers.dart';
import '../../dashboard_providers.dart';

/// MARKET MMS — Operasyonel Dashboard Ekranı
///
/// Yalnızca yerel SQLite veritabanındaki gerçek satış, ürün ve stok
/// kayıtlarından beslenir; sahte KPI veya kurgusal grafik üretmez.
class DashboardScreen extends ConsumerWidget {
  final VoidCallback? onNavigateToPos;
  final VoidCallback? onNavigateToStock;
  final VoidCallback? onNavigateToSales;

  const DashboardScreen({
    super.key,
    this.onNavigateToPos,
    this.onNavigateToStock,
    this.onNavigateToSales,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(dashboardSnapshotProvider);
    final systemStatus = ref.watch(systemStatusProvider);
    final uiProfile = ref.watch(mmsUiProfileProvider);
    final isCompact = context.windowClass == MmsWindowClass.compact;
    final useTouchSizes = isCompact || uiProfile.isMobile;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(dashboardSnapshotProvider);
        await ref.read(systemStatusProvider.notifier).refreshStatus();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(isCompact ? MmsSpacing.md : MmsSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppPageHeader(
              title: 'Mağaza Özeti',
              subtitle:
                  'Günlük kasa performansı, kritik stok uyarıları ve son işlemler',
              actions: [
                if (onNavigateToPos != null)
                  AppButton(
                    label: isCompact ? 'Kasa' : 'Kasaya Geç',
                    icon: Icons.point_of_sale_rounded,
                    variant: AppButtonVariant.emerald,
                    minHeight: 48,
                    onPressed: onNavigateToPos,
                  ),
                AppIconButton(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Özeti Yenile',
                  bordered: true,
                  size: useTouchSizes ? 48 : 44,
                  onPressed: () {
                    ref.invalidate(dashboardSnapshotProvider);
                    ref.read(systemStatusProvider.notifier).refreshStatus();
                  },
                ),
              ],
            ),
            const SizedBox(height: MmsSpacing.lg),
            snapshotAsync.when(
              loading: () => const AppLoadingState(
                message: 'Mağaza verileri hazırlanıyor...',
              ),
              error: (err, _) => AppErrorState(
                message: UserFriendlyErrorMapper.map(
                  err,
                  fallback: 'Dashboard verileri şu anda yüklenemedi. Lütfen tekrar deneyin.',
                ),
                onRetry: () => ref.invalidate(dashboardSnapshotProvider),
              ),
              data: (data) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Duyarlı KPI Grid
                  _buildKpiGrid(context, data),
                  const SizedBox(height: MmsSpacing.lg),

                  // 2. Satış Trend Grafiği + Operasyonel Özet
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 900;
                      if (isWide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 7,
                              child: _buildTrendCard(context, data),
                            ),
                            const SizedBox(width: MmsSpacing.md),
                            Expanded(
                              flex: 4,
                              child: _buildOperationalSummaryCard(
                                context,
                                data,
                                systemStatus.pendingOutboxCount,
                              ),
                            ),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildTrendCard(context, data),
                          const SizedBox(height: MmsSpacing.md),
                          _buildOperationalSummaryCard(
                            context,
                            data,
                            systemStatus.pendingOutboxCount,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: MmsSpacing.lg),

                  // 3. Son Satışlar & Kritik Stok Uyarıları
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 900;
                      if (isWide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 6,
                              child: _buildRecentSalesCard(context, ref, data),
                            ),
                            const SizedBox(width: MmsSpacing.md),
                            Expanded(
                              flex: 5,
                              child: _buildCriticalStockCard(context, data),
                            ),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildRecentSalesCard(context, ref, data),
                          const SizedBox(height: MmsSpacing.md),
                          _buildCriticalStockCard(context, data),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiGrid(BuildContext context, DashboardSnapshot data) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cols = width >= 960
            ? 4
            : width >= 460
                ? 2
                : 1;
        final spacing = MmsSpacing.sm;
        final itemWidth = (width - (spacing * (cols - 1))) / cols;

        final cards = [
          AppStatCard(
            title: 'Günlük Satış Toplamı',
            value: Money.formatCents(data.todaySalesTotalCents),
            subtitle: 'İptaller hariç net tutar',
            icon: Icons.payments_rounded,
            tone: AppBadgeTone.success,
            onTap: onNavigateToSales,
          ),
          AppStatCard(
            title: 'Günlük Satış Adedi',
            value: '${data.todaySalesCount}',
            subtitle: 'Bugün tamamlanan fiş',
            icon: Icons.receipt_long_rounded,
            tone: AppBadgeTone.info,
            onTap: onNavigateToSales,
          ),
          AppStatCard(
            title: 'Aktif Ürün Sayısı',
            value: '${data.activeProductCount}',
            subtitle: 'Satışa hazır katalog',
            icon: Icons.inventory_2_rounded,
            tone: AppBadgeTone.lime,
            onTap: onNavigateToStock,
          ),
          AppStatCard(
            title: 'Kritik Stok Uyarısı',
            value: '${data.criticalStockCount}',
            subtitle: data.negativeStockCount > 0
                ? '${data.negativeStockCount} ürün eksi stokta'
                : 'Eşik: ≤ 5 birim',
            icon: Icons.warning_amber_rounded,
            tone: data.criticalStockCount > 0
                ? AppBadgeTone.warning
                : AppBadgeTone.neutral,
            onTap: onNavigateToStock,
          ),
        ];

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards
              .map((c) => SizedBox(width: itemWidth, child: c))
              .toList(),
        );
      },
    );
  }

  Widget _buildTrendCard(BuildContext context, DashboardSnapshot data) {
    final colors = context.mmsColors;
    final hasAnySales = data.last7DaysTrend.any((b) => b.totalCents > 0);
    final maxCents = data.last7DaysTrend.fold<int>(
      0,
      (prev, b) => math.max(prev, b.totalCents),
    );

    return AppCard(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            title: 'Son 7 Gün Satış Trendi',
            subtitle: 'Gerçek yerel satış kayıtlarından günlük ciro dağılımı',
            trailing: AppBadge(
              label: '7 Gün',
              tone: AppBadgeTone.neutral,
              compact: true,
            ),
          ),
          const SizedBox(height: MmsSpacing.lg),
          if (!hasAnySales)
            const SizedBox(
              height: 170,
              child: AppEmptyState(
                icon: Icons.bar_chart_rounded,
                title: 'Henüz 7 günlük satış verisi oluşmadı',
                description:
                    'Kasa ekranından satış gerçekleştirdikçe günlük trend burada görünür.',
              ),
            )
          else
            SizedBox(
              height: 196,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: data.last7DaysTrend.map((bucket) {
                  final ratio = maxCents > 0 ? bucket.totalCents / maxCents : 0.0;
                  final isToday = bucket == data.last7DaysTrend.last;
                  final dayLabel =
                      '${bucket.date.day.toString().padLeft(2, '0')}.${bucket.date.month.toString().padLeft(2, '0')}';

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Tooltip(
                        message:
                            '$dayLabel: ${Money.formatCents(bucket.totalCents)} (${bucket.count} satış)',
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (bucket.totalCents > 0)
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  Money.formatCents(bucket.totalCents)
                                      .replaceAll(' TL', ''),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: colors.textSecondary,
                                    fontFeatures: MmsTypography.tabularFigures,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 6),
                            Container(
                              height: math.max(8.0, 108.0 * ratio),
                              decoration: BoxDecoration(
                                color: isToday
                                    ? colors.emerald
                                    : colors.primary.withValues(alpha: 0.72),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6),
                                ),
                                border: isToday
                                    ? Border(
                                        top: BorderSide(
                                          color: colors.limeAccent,
                                          width: 3,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              dayLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isToday
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isToday
                                    ? colors.primary
                                    : colors.textTertiary,
                                fontFeatures: MmsTypography.tabularFigures,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOperationalSummaryCard(
    BuildContext context,
    DashboardSnapshot data,
    int pendingOutboxCount,
  ) {
    final colors = context.mmsColors;
    final total = data.todayCashTotalCents + data.todayCardTotalCents;
    final cashShare = total > 0 ? data.todayCashTotalCents / total : 0.0;

    return AppCard(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(
            title: 'Operasyonel Özet',
            subtitle: 'Bugünkü ödeme dağılımı ve kuyruk durumu',
          ),
          const SizedBox(height: MmsSpacing.md),
          _summaryRow(
            context,
            icon: Icons.payments_outlined,
            label: 'Nakit Tahsilat',
            value: Money.formatCents(data.todayCashTotalCents),
            accent: colors.emerald,
          ),
          const SizedBox(height: MmsSpacing.sm),
          _summaryRow(
            context,
            icon: Icons.credit_card_rounded,
            label: 'Kart Tahsilat',
            value: Money.formatCents(data.todayCardTotalCents),
            accent: colors.info,
          ),
          const SizedBox(height: MmsSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(MmsRadius.pill),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  Expanded(
                    flex: total > 0 ? math.max(1, (cashShare * 100).round()) : 1,
                    child: Container(
                      color: total > 0 ? colors.emerald : colors.border,
                    ),
                  ),
                  if (total > 0 && cashShare < 1)
                    Expanded(
                      flex: math.max(1, ((1 - cashShare) * 100).round()),
                      child: Container(color: colors.info),
                    ),
                ],
              ),
            ),
          ),
          Divider(height: MmsSpacing.xl, color: colors.border),
          _summaryRow(
            context,
            icon: Icons.outbox_rounded,
            label: 'Bekleyen Senkronizasyon',
            value: '$pendingOutboxCount kayıt',
            accent: pendingOutboxCount > 0 ? colors.warning : colors.success,
          ),
          const SizedBox(height: MmsSpacing.sm),
          _summaryRow(
            context,
            icon: Icons.inventory_rounded,
            label: 'Eksi Stokta Ürün',
            value: '${data.negativeStockCount} ürün',
            accent:
                data.negativeStockCount > 0 ? colors.danger : colors.success,
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color accent,
  }) {
    final colors = context.mmsColors;
    return Row(
      children: [
        Icon(icon, size: 18, color: accent),
        const SizedBox(width: MmsSpacing.xs),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
            fontFeatures: MmsTypography.tabularFigures,
          ),
        ),
      ],
    );
  }

  Widget _buildRecentSalesCard(
    BuildContext context,
    WidgetRef ref,
    DashboardSnapshot data,
  ) {
    final colors = context.mmsColors;

    return AppCard(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            title: 'Son Satışlar',
            subtitle: 'En güncel fiş kayıtları',
            trailing: onNavigateToSales != null
                ? TextButton(
                    onPressed: onNavigateToSales,
                    child: const Text('Tümünü Gör'),
                  )
                : null,
          ),
          const SizedBox(height: MmsSpacing.sm),
          if (data.recentSales.isEmpty)
            const AppEmptyState(
              icon: Icons.receipt_long_rounded,
              title: 'Henüz kayıtlı satış yok',
              description: 'Tamamlanan satışlar burada listelenecektir.',
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: data.recentSales.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: colors.border),
              itemBuilder: (context, index) {
                final sale = data.recentSales[index];
                final isCancelled = sale.status == 'CANCELLED';

                return InkWell(
                  onTap: () {
                    ref
                        .read(salesHistoryProvider.notifier)
                        .selectSale(sale.id);
                    showDialog<void>(
                      context: context,
                      builder: (_) => SaleDetailDialog(saleId: sale.id),
                    );
                  },
                  borderRadius: BorderRadius.circular(MmsRadius.sm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: MmsSpacing.sm,
                      horizontal: MmsSpacing.xxs,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: colors.surfaceSubtle,
                            borderRadius: BorderRadius.circular(MmsRadius.sm),
                          ),
                          child: Icon(
                            sale.paymentMethod == 'CASH'
                                ? Icons.payments_outlined
                                : Icons.credit_card_rounded,
                            size: 18,
                            color: colors.emerald,
                          ),
                        ),
                        const SizedBox(width: MmsSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '#${sale.clientSeq} • ${sale.paymentMethod == 'CASH' ? 'Nakit' : 'Kart'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textPrimary,
                                  fontFeatures: MmsTypography.tabularFigures,
                                ),
                              ),
                              Text(
                                sale.createdAt.toFormattedDateTime(),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: colors.textTertiary,
                                  fontFeatures: MmsTypography.tabularFigures,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: MmsSpacing.xs),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              Money.formatCents(sale.totalAmount),
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                decoration: isCancelled
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: isCancelled
                                    ? colors.textTertiary
                                    : colors.textPrimary,
                                fontFeatures: MmsTypography.tabularFigures,
                              ),
                            ),
                            const SizedBox(height: 2),
                            SaleStatusBadge.fromStatus(sale.status),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildCriticalStockCard(BuildContext context, DashboardSnapshot data) {
    final colors = context.mmsColors;

    return AppCard(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            title: 'Kritik Stok Uyarıları',
            subtitle: 'Stoku 5 birim veya altında olan aktif ürünler',
            trailing: onNavigateToStock != null
                ? TextButton(
                    onPressed: onNavigateToStock,
                    child: const Text('Stok Ekranı'),
                  )
                : null,
          ),
          const SizedBox(height: MmsSpacing.sm),
          if (data.criticalProducts.isEmpty)
            const AppEmptyState(
              icon: Icons.check_circle_outline_rounded,
              title: 'Kritik stok uyarısı yok',
              description: 'Tüm aktif ürünler kritik seviyenin üzerinde.',
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: data.criticalProducts.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: colors.border),
              itemBuilder: (context, index) {
                final product = data.criticalProducts[index];
                final isNegative = product.stock < 0;
                final isZero = product.stock == 0;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: MmsSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                            ),
                            if (product.barcode != null &&
                                product.barcode!.isNotEmpty)
                              Text(
                                product.barcode!,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: colors.textTertiary,
                                  fontFeatures: MmsTypography.tabularFigures,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: MmsSpacing.xs),
                      AppBadge(
                        label: Money.formatMilliWithUnit(
                          product.stock,
                          product.stockUnit,
                        ),
                        tone: isNegative || isZero
                            ? AppBadgeTone.danger
                            : AppBadgeTone.warning,
                        compact: true,
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
