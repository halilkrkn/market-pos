import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../domain/barcode_input_sanitizer.dart';
import '../../domain/money.dart';
import '../../domain/pos_product.dart';
import '../../domain/pos_repository.dart';

/// Yerel ürün kataloğunda isim ve aktif barkoda göre arama diyalogu (`OD-03`).
class ProductSearchDialog extends StatefulWidget {
  final PosRepository repository;
  final ValueChanged<PosProduct> onSelectProduct;
  final bool showKeyboardHints;

  const ProductSearchDialog({
    super.key,
    required this.repository,
    required this.onSelectProduct,
    this.showKeyboardHints = true,
  });

  @override
  State<ProductSearchDialog> createState() => _ProductSearchDialogState();
}

class _ProductSearchDialogState extends State<ProductSearchDialog> {
  final TextEditingController _queryController = TextEditingController();
  List<PosProduct> _results = const <PosProduct>[];
  bool _isLoading = true;
  String? _errorMessage;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _runSearch('');
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String query) async {
    final cleanedQuery = BarcodeInputSanitizer.stripControlChars(query);
    final generation = ++_searchGeneration;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final items = await widget.repository.searchActiveProducts(cleanedQuery);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = items;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Yerel ürün kataloğu okunamadı.';
      });
    }
  }

  void _submitQuickMatch(String rawQuery) {
    if (_isLoading || _results.isEmpty) return;

    final normalizedQuery = BarcodeInputSanitizer.stripControlChars(rawQuery)
        .trim();
    if (_results.length == 1) {
      widget.onSelectProduct(_results.single);
      Navigator.of(context).pop();
      return;
    }

    if (normalizedQuery.isNotEmpty) {
      for (final product in _results) {
        if (product.primaryBarcode == normalizedQuery) {
          widget.onSelectProduct(product);
          Navigator.of(context).pop();
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: AppDialog(
        key: const Key('product_search_dialog'),
        title: 'Yerel Ürün Kataloğu Arama',
        subtitle: 'İsim veya aktif barkoda göre hızlı sepet ekleme',
        icon: Icons.search_rounded,
        iconColor: colors.emerald,
        maxWidth: 720,
        maxHeight: 580,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSearchField(
              key: const Key('product_search_input'),
              controller: _queryController,
              autofocus: true,
              hintText: 'Ürün adı veya barkod ile yerel katalogda ara...',
              onChanged: _runSearch,
              onSubmitted: _submitQuickMatch,
              onClear: () {
                _queryController.clear();
                _runSearch('');
              },
            ),
            const SizedBox(height: MmsSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: MmsSpacing.sm,
                vertical: MmsSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: colors.infoBg,
                borderRadius: BorderRadius.circular(MmsRadius.sm),
                border: Border.all(color: colors.info.withValues(alpha: 0.3)),
              ),
              child: Text(
                'Yalnızca yerel veritabanındaki aktif ürünler gösterilir. Çevrimdışı yeni ürün oluşturulamaz; Master Hub bağlantısı gerekir.',
                style: TextStyle(fontSize: 12, color: colors.infoText),
              ),
            ),
            const SizedBox(height: MmsSpacing.sm),
            Expanded(child: _buildBody(context)),
          ],
        ),
        actions: [
          AppButton(
            label: widget.showKeyboardHints ? 'Kapat [Esc]' : 'Kapat',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final colors = context.mmsColors;

    if (_isLoading) {
      return const AppLoadingState(message: 'Katalog taranıyor...');
    }
    if (_errorMessage != null) {
      return AppErrorState(
        message: _errorMessage!,
        onRetry: () => _runSearch(_queryController.text),
      );
    }
    if (_results.isEmpty) {
      return const AppEmptyState(
        icon: Icons.search_off_rounded,
        title: 'Yerel katalogda eşleşen aktif ürün bulunamadı.',
      );
    }

    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: colors.border),
      itemBuilder: (context, index) {
        final product = _results[index];
        final isLowOrNeg = product.isStockNonPositive;
        return LayoutBuilder(
          builder: (context, constraints) {
            final detailsColumn = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: constraints.maxWidth < 460 ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: MmsSpacing.sm,
                  runSpacing: 2,
                  children: [
                    Text(
                      product.primaryBarcode ?? 'Barkodsuz',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                        fontFeatures: MmsTypography.tabularFigures,
                      ),
                    ),
                    Text(
                      'Stok: ${Money.formatMilliWithUnit(product.stockMilli, product.stockUnit)}${isLowOrNeg ? ' (allow)' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isLowOrNeg
                            ? colors.warningText
                            : colors.successText,
                        fontFeatures: MmsTypography.tabularFigures,
                      ),
                    ),
                  ],
                ),
              ],
            );

            final priceText = Text(
              Money.formatCents(product.priceCents),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: colors.textPrimary,
                fontFeatures: MmsTypography.tabularFigures,
              ),
            );

            final addButton = ElevatedButton(
              key: Key('search_add_${product.id}'),
              onPressed: () {
                widget.onSelectProduct(product);
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.emerald,
                foregroundColor: colors.onEmerald,
                minimumSize: const Size(112, 48),
              ),
              child: const Text('Sepete Ekle'),
            );

            if (constraints.maxWidth < 460) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: MmsSpacing.xs + 2,
                  horizontal: MmsSpacing.xxs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    detailsColumn,
                    const SizedBox(height: MmsSpacing.xs),
                    Row(
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: priceText,
                          ),
                        ),
                        const SizedBox(width: MmsSpacing.xs),
                        addButton,
                      ],
                    ),
                  ],
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.symmetric(
                vertical: MmsSpacing.xs + 2,
                horizontal: MmsSpacing.xxs,
              ),
              child: Row(
                children: [
                  Expanded(child: detailsColumn),
                  const SizedBox(width: MmsSpacing.xs),
                  priceText,
                  const SizedBox(width: MmsSpacing.sm),
                  addButton,
                ],
              ),
            );
          },
        );
      },
    );
  }
}
