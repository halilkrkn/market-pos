import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/platform/mms_ui_profile.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/debouncer.dart';
import '../../../barcode_scanner/barcode_scanner_providers.dart';
import '../../../barcode_scanner/domain/camera_scan_result.dart';
import '../../../pos/domain/money.dart';
import '../../application/catalog_state.dart';
import '../../catalog_providers.dart';
import '../../../sync/domain/sync_coordinator_state.dart';
import '../../../sync/sync_providers.dart';
import '../widgets/category_edit_dialog.dart';
import '../widgets/price_history_dialog.dart';
import '../widgets/product_edit_dialog.dart';

/// MARKET MMS — Ürün ve Kategori Yönetimi Ekranı (Shopify Admin — Modern Emerald)
class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final Debouncer _searchDebouncer = Debouncer();

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
    final state = ref.watch(catalogProvider);
    final syncState = ref.watch(backgroundSyncCoordinatorProvider);
    final uiProfile = ref.watch(mmsUiProfileProvider);
    final colors = context.mmsColors;
    final isCompact = context.windowClass == MmsWindowClass.compact;
    final touchIconSize = (isCompact || uiProfile.isMobile) ? 48.0 : 44.0;

    return Scaffold(
      backgroundColor: colors.background,
      body: Padding(
        padding: EdgeInsets.all(isCompact ? MmsSpacing.md : MmsSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppPageHeader(
              title: 'Ürün ve Stok Yönetimi',
              subtitle: 'Ürün kartları, fiyat geçmişi, barkodlar ve kategori hiyerarşisi',
              actions: [
                if (!isCompact)
                  AppButton(
                    label: 'Hub Senkronizasyonu',
                    icon: Icons.cloud_sync_outlined,
                    variant: AppButtonVariant.secondary,
                    minHeight: uiProfile.minTouchTarget,
                    isLoading: syncState.isSyncing,
                    onPressed: () => ref
                        .read(catalogProvider.notifier)
                        .syncCatalogWithHub(
                          () => ref
                              .read(backgroundSyncCoordinatorProvider.notifier)
                              .triggerSync(reason: SyncTriggerReason.manual),
                        ),
                  )
                else
                  AppIconButton(
                    icon: Icons.cloud_sync_outlined,
                    tooltip: 'Hub ile Senkronize Et',
                    bordered: true,
                    size: touchIconSize,
                    onPressed: () => ref
                        .read(catalogProvider.notifier)
                        .syncCatalogWithHub(
                          () => ref
                              .read(backgroundSyncCoordinatorProvider.notifier)
                              .triggerSync(reason: SyncTriggerReason.manual),
                        ),
                  ),
                AppIconButton(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Yenile',
                  bordered: true,
                  size: touchIconSize,
                  onPressed: () => ref.read(catalogProvider.notifier).init(),
                ),
              ],
            ),
            const SizedBox(height: MmsSpacing.md),

            if (state.errorMessage != null) ...[
              AppErrorState(
                message: state.errorMessage!,
                inline: true,
                onRetry: () => ref.read(catalogProvider.notifier).init(),
              ),
              const SizedBox(height: MmsSpacing.sm),
            ],

            // Sekme Çubuğu
            Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(MmsRadius.md),
                border: Border.all(color: colors.border),
              ),
              child: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 18),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Ürün Kataloğu',
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
                        Icon(Icons.category_outlined, size: 18),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Kategoriler',
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

            // Sekme İçeriği
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildProductsTab(context, state),
                  _buildCategoriesTab(context, state),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // 1. ÜRÜNLER SEKMESİ
  // =========================================================================

  Widget _buildProductsTab(BuildContext context, CatalogState state) {
    final uiProfile = ref.watch(mmsUiProfileProvider);
    final activeFilterCount =
        (state.selectedCategoryId != null ? 1 : 0) +
        (state.filterIsActive != null ? 1 : 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (uiProfile.supportsCameraBarcodeScanning) ...[
          AppButton(
            key: const Key('catalog_camera_identify_button'),
            label: 'Kamera ile Ürün Tanımla',
            icon: Icons.qr_code_scanner_rounded,
            variant: AppButtonVariant.primary,
            minHeight: 48,
            expand: true,
            onPressed: () => _handleCameraProductIdentify(state),
          ),
          const SizedBox(height: MmsSpacing.sm),
        ],
        AppFilterBar(
          searchField: AppSearchField(
            controller: _searchController,
            hintText: 'Ürün adı, barkod veya ID ile ara...',
            onChanged: (val) => _searchDebouncer.run(() {
              if (!mounted) return;
              ref.read(catalogProvider.notifier).setSearchQuery(val);
            }),
            onClear: () {
              _searchController.clear();
              _searchDebouncer.runImmediate(() {
                if (mounted) {
                  ref.read(catalogProvider.notifier).setSearchQuery('');
                }
              });
            },
          ),
          activeFilterCount: activeFilterCount,
          filterSheetTitle: 'Ürün Filtreleri',
          filters: [
            AppDropdown<String?>(
              value: state.selectedCategoryId,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Kategori: Tümü'),
                ),
                ...state.categories.map(
                  (c) => DropdownMenuItem<String?>(
                    value: c.id,
                    child: Text(c.name),
                  ),
                ),
              ],
              onChanged: (val) =>
                  ref.read(catalogProvider.notifier).setCategoryFilter(val),
            ),
            AppDropdown<bool?>(
              value: state.filterIsActive,
              items: const [
                DropdownMenuItem<bool?>(
                  value: null,
                  child: Text('Durum: Tümü'),
                ),
                DropdownMenuItem<bool?>(
                  value: true,
                  child: Text('Yalnızca Aktif'),
                ),
                DropdownMenuItem<bool?>(
                  value: false,
                  child: Text('Yalnızca Pasif'),
                ),
              ],
              onChanged: (val) =>
                  ref.read(catalogProvider.notifier).setActiveFilter(val),
            ),
          ],
          primaryAction: AppButton(
            label: 'Yeni Ürün',
            icon: Icons.add_rounded,
            variant: AppButtonVariant.emerald,
            minHeight: 48,
            onPressed: () async {
              await showDialog<bool>(
                context: context,
                builder: (_) => ProductEditDialog(categories: state.categories),
              );
            },
          ),
        ),
        const SizedBox(height: MmsSpacing.md),
        Expanded(
          child: state.isLoading
              ? const AppLoadingState(message: 'Ürün kataloğu yükleniyor...')
              : state.products.isEmpty
              ? const AppEmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'Kayıtlı ürün bulunamadı.',
                  description: 'Yeni ürün tanımlayarak veya filtreleri sıfırlayarak kataloğu görüntüleyebilirsiniz.',
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 740) {
                      return _buildDesktopProductsTable(context, state);
                    }
                    return _buildMobileProductCards(context, state);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDesktopProductsTable(BuildContext context, CatalogState state) {
    final colors = context.mmsColors;

    return AppDataTable(
      header: Row(
        children: [
          Expanded(
            flex: 4,
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
              'Kategori',
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
              'Stok & KDV',
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
              'Satış Fiyatı',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 148),
        ],
      ),
      itemCount: state.products.length,
      itemBuilder: (context, index) {
        final prod = state.products[index];
        final category = _findCategory(state.categories, prod.categoryId);

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
                        color: prod.isActive
                            ? colors.successBg
                            : colors.dangerBg,
                        borderRadius: BorderRadius.circular(MmsRadius.sm),
                      ),
                      child: Icon(
                        Icons.shopping_bag_outlined,
                        size: 19,
                        color: prod.isActive
                            ? colors.successText
                            : colors.dangerText,
                      ),
                    ),
                    const SizedBox(width: MmsSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  prod.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: prod.isActive
                                        ? colors.textPrimary
                                        : colors.textTertiary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: MmsSpacing.xs),
                              AppBadge(
                                label: prod.isActive ? 'AKTİF' : 'PASİF',
                                tone: prod.isActive
                                    ? AppBadgeTone.success
                                    : AppBadgeTone.danger,
                                compact: true,
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Barkod: ${prod.barcode ?? "Yok"}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textTertiary,
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
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: category != null
                      ? AppBadge(
                          label: category.name,
                          tone: AppBadgeTone.neutral,
                          compact: true,
                        )
                      : Text(
                          'Genel',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colors.textTertiary,
                          ),
                        ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Money.formatMilliWithUnit(prod.stock, prod.stockUnit),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: prod.stock <= 0
                            ? colors.dangerText
                            : colors.textPrimary,
                        fontFeatures: MmsTypography.tabularFigures,
                      ),
                    ),
                    Text(
                      'KDV %${prod.vatRate}',
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
                child: Text(
                  Money.formatCents(prod.price),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: colors.emerald,
                    fontFeatures: MmsTypography.tabularFigures,
                  ),
                ),
              ),
              SizedBox(
                width: 148,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AppIconButton(
                      icon: Icons.history_rounded,
                      tooltip: 'Fiyat Değişiklik Geçmişi',
                      onPressed: () => _openPriceHistory(prod),
                    ),
                    AppIconButton(
                      icon: Icons.edit_outlined,
                      tooltip: 'Ürünü Düzenle',
                      onPressed: () => _openProductEdit(prod, state.categories),
                    ),
                    if (prod.isActive)
                      AppIconButton(
                        icon: Icons.archive_outlined,
                        tooltip: 'Pasife Al (Soft Delete)',
                        color: colors.dangerText,
                        onPressed: () => _confirmDeactivateProduct(prod),
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

  Widget _buildMobileProductCards(BuildContext context, CatalogState state) {
    final colors = context.mmsColors;

    return RefreshIndicator(
      onRefresh: () => ref.read(catalogProvider.notifier).init(),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.products.length,
        separatorBuilder: (_, _) => const SizedBox(height: MmsSpacing.xs),
        itemBuilder: (context, index) {
          final prod = state.products[index];
          final category = _findCategory(state.categories, prod.categoryId);

          return RepaintBoundary(
            key: ValueKey('mobile_prod_${prod.id}'),
            child: AppCard(
              padding: const EdgeInsets.all(MmsSpacing.md),
              onTap: () => _openProductEdit(prod, state.categories),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        prod.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: prod.isActive
                              ? colors.textPrimary
                              : colors.textTertiary,
                        ),
                      ),
                    ),
                    const SizedBox(width: MmsSpacing.xs),
                    Text(
                      Money.formatCents(prod.price),
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: colors.emerald,
                        fontFeatures: MmsTypography.tabularFigures,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: MmsSpacing.xs),
                Wrap(
                  spacing: MmsSpacing.xs,
                  runSpacing: MmsSpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AppBadge(
                      label: prod.isActive ? 'AKTİF' : 'PASİF',
                      tone: prod.isActive
                          ? AppBadgeTone.success
                          : AppBadgeTone.danger,
                      compact: true,
                    ),
                    if (category != null)
                      AppBadge(
                        label: category.name,
                        tone: AppBadgeTone.neutral,
                        compact: true,
                      ),
                    Text(
                      'Stok: ${Money.formatMilliWithUnit(prod.stock, prod.stockUnit)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: prod.stock <= 0
                            ? colors.dangerText
                            : colors.textSecondary,
                        fontFeatures: MmsTypography.tabularFigures,
                      ),
                    ),
                    Text(
                      'KDV %${prod.vatRate}',
                      style: TextStyle(fontSize: 12, color: colors.textTertiary),
                    ),
                  ],
                ),
                const SizedBox(height: MmsSpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Barkod: ${prod.barcode ?? "Yok"}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textTertiary,
                          fontFeatures: MmsTypography.tabularFigures,
                        ),
                      ),
                    ),
                    AppIconButton(
                      icon: Icons.history_rounded,
                      tooltip: 'Fiyat Değişiklik Geçmişi',
                      size: 48,
                      onPressed: () => _openPriceHistory(prod),
                    ),
                    AppIconButton(
                      icon: Icons.edit_outlined,
                      tooltip: 'Ürünü Düzenle',
                      size: 48,
                      onPressed: () => _openProductEdit(prod, state.categories),
                    ),
                    if (prod.isActive)
                      AppIconButton(
                        icon: Icons.archive_outlined,
                        tooltip: 'Pasife Al (Soft Delete)',
                        color: colors.dangerText,
                        size: 48,
                        onPressed: () => _confirmDeactivateProduct(prod),
                      ),
                  ],
                ),
              ],
            ),
            ),
          );
        },
      ),
    );
  }

  // =========================================================================
  // 2. KATEGORİLER SEKMESİ
  // =========================================================================

  Widget _buildCategoriesTab(BuildContext context, CatalogState state) {
    final colors = context.mmsColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: MmsSpacing.md,
            vertical: MmsSpacing.sm,
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: MmsSpacing.sm,
            runSpacing: MmsSpacing.xs,
            children: [
              Text(
                'Kategori Listesi ve Hiyerarşi (BR-PROD-14)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              AppButton(
                label: 'Yeni Kategori',
                icon: Icons.add_rounded,
                variant: AppButtonVariant.emerald,
                minHeight: 48,
                onPressed: () async {
                  await showDialog<bool>(
                    context: context,
                    builder: (_) => CategoryEditDialog(
                      existingCategories: state.categories,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: MmsSpacing.md),
        Expanded(
          child: state.categories.isEmpty
              ? const AppEmptyState(
                  icon: Icons.category_outlined,
                  title: 'Kayıtlı kategori bulunamadı.',
                  description: 'Ana ve alt kategoriler oluşturarak ürün kataloğunuzu düzenleyebilirsiniz.',
                )
              : AppDataTable(
                  header: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Kategori Adı & Hiyerarşi',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      Text(
                        'İşlemler',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  itemCount: state.categories.length,
                  itemBuilder: (context, index) {
                    final cat = state.categories[index];
                    final parent = _findCategory(
                      state.categories,
                      cat.parentId,
                    );

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: MmsSpacing.md,
                        vertical: MmsSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: cat.isActive
                                  ? colors.successBg
                                  : colors.dangerBg,
                              borderRadius: BorderRadius.circular(MmsRadius.sm),
                            ),
                            child: Icon(
                              cat.parentId == null
                                  ? Icons.folder_outlined
                                  : Icons.subdirectory_arrow_right_rounded,
                              size: 19,
                              color: cat.isActive
                                  ? colors.successText
                                  : colors.dangerText,
                            ),
                          ),
                          const SizedBox(width: MmsSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: MmsSpacing.xs,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      cat.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: cat.isActive
                                            ? colors.textPrimary
                                            : colors.textTertiary,
                                      ),
                                    ),
                                    AppBadge(
                                      label: cat.isActive ? 'AKTİF' : 'PASİF',
                                      tone: cat.isActive
                                          ? AppBadgeTone.success
                                          : AppBadgeTone.danger,
                                      compact: true,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  parent != null
                                      ? 'Üst Kategori: ${parent.name}'
                                      : 'Ana Kategori',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          AppIconButton(
                            icon: Icons.edit_outlined,
                            tooltip: 'Düzenle',
                            onPressed: () async {
                              await showDialog<bool>(
                                context: context,
                                builder: (_) => CategoryEditDialog(
                                  category: cat,
                                  existingCategories: state.categories,
                                ),
                              );
                            },
                          ),
                          if (cat.isActive)
                            AppIconButton(
                              icon: Icons.archive_outlined,
                              tooltip: 'Pasife Al',
                              color: colors.dangerText,
                              onPressed: () => _confirmDeactivateCategory(cat),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  LocalCategory? _findCategory(List<LocalCategory> categories, String? id) {
    if (id == null) return null;
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _openPriceHistory(LocalProduct prod) async {
    final history = await ref
        .read(catalogProvider.notifier)
        .getPriceHistory(prod.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) =>
          PriceHistoryDialog(productName: prod.name, history: history),
    );
  }

  Future<void> _openProductEdit(
    LocalProduct prod,
    List<LocalCategory> categories,
  ) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => ProductEditDialog(product: prod, categories: categories),
    );
  }

  Future<void> _handleCameraProductIdentify(CatalogState state) async {
    final scanResult = await ref.read(cameraBarcodeScannerProvider).scanBarcode(
      context,
      title: 'Kamera ile Ürün Tanımla',
      subtitle: 'Katalogda aramak veya yeni ürün eklemek için barkodu okutun',
    );
    if (!mounted) return;

    switch (scanResult.status) {
      case CameraScanStatus.scanned:
        final barcode = scanResult.barcode;
        if (barcode == null) return;
        final existing = await ref
            .read(catalogRepositoryProvider)
            .getProductByBarcode(barcode);
        if (!mounted) return;
        if (existing != null) {
          AppSnackbar.show(
            context,
            message: 'Ürün yerel katalogda bulundu: ${existing.name}',
            tone: AppBadgeTone.info,
          );
          await showDialog<bool>(
            context: context,
            builder: (_) => ProductEditDialog(
              product: existing,
              categories: state.categories,
            ),
          );
        } else {
          await showDialog<bool>(
            context: context,
            builder: (_) => ProductEditDialog(
              categories: state.categories,
              initialBarcode: barcode,
              autoLookupExternal: true,
            ),
          );
        }
        break;
      case CameraScanStatus.permissionDenied:
      case CameraScanStatus.error:
      case CameraScanStatus.unsupportedPlatform:
        AppSnackbar.show(
          context,
          message: scanResult.errorMessage ?? 'Kamera ile barkod okunamadı.',
          tone: AppBadgeTone.warning,
        );
        break;
      case CameraScanStatus.cancelled:
        break;
    }
  }

  Future<void> _confirmDeactivateProduct(LocalProduct prod) async {
    final colors = context.mmsColors;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: 'Ürünü Pasife Al',
        icon: Icons.archive_outlined,
        iconColor: colors.danger,
        maxWidth: 460,
        content: Text(
          '"${prod.name}" ürününü pasife almak istediğinize emin misiniz? Satış ekranında görünmeyecek ancak geçmiş fişlerde korunacaktır.',
          style: TextStyle(fontSize: 14, color: colors.textSecondary),
        ),
        actions: [
          AppButton(
            label: 'Vazgeç',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton(
            label: 'Pasife Al',
            variant: AppButtonVariant.danger,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(catalogProvider.notifier).deactivateProduct(prod.id);
    }
  }

  Future<void> _confirmDeactivateCategory(LocalCategory cat) async {
    final colors = context.mmsColors;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: 'Kategoriyi Pasife Al',
        icon: Icons.archive_outlined,
        iconColor: colors.danger,
        maxWidth: 460,
        content: Text(
          '"${cat.name}" kategorisini pasife almak istediğinize emin misiniz?',
          style: TextStyle(fontSize: 14, color: colors.textSecondary),
        ),
        actions: [
          AppButton(
            label: 'Vazgeç',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton(
            label: 'Pasife Al',
            variant: AppButtonVariant.danger,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(catalogProvider.notifier).deactivateCategory(cat.id);
    }
  }
}
