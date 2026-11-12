import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/money.dart';
import '../../domain/pos_product.dart';
import '../../domain/pos_repository.dart';

/// Yerel ürün kataloğunda isim ve aktif barkoda göre arama diyalogu (`OD-03`).
class ProductSearchDialog extends StatefulWidget {
  final PosRepository repository;
  final ValueChanged<PosProduct> onSelectProduct;

  const ProductSearchDialog({
    super.key,
    required this.repository,
    required this.onSelectProduct,
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
    final generation = ++_searchGeneration;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final items = await widget.repository.searchActiveProducts(query);
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

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Dialog(
        key: const Key('product_search_dialog'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          width: 720,
          height: 540,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Yerel Ürün Kataloğu Arama',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textMainLight,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kapat (Esc)',
                    onPressed: () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('product_search_input'),
                controller: _queryController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Ürün adı veya barkod ile yerel katalogda ara...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: _runSearch,
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.posInfoBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.25),
                  ),
                ),
                child: const Text(
                  'Yalnızca yerel veritabanındaki aktif ürünler gösterilir. Çevrimdışı yeni ürün oluşturulamaz; Master Hub bağlantısı gerekir.',
                  style: TextStyle(fontSize: 12.5, color: AppTheme.textMainLight),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildBody()),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Kapat [Esc]'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Text(
          _errorMessage!,
          style: const TextStyle(color: AppTheme.posDangerText),
        ),
      );
    }
    if (_results.isEmpty) {
      return const Center(
        child: Text(
          'Yerel katalogda eşleşen aktif ürün bulunamadı.',
          style: TextStyle(color: AppTheme.textMutedLight),
        ),
      );
    }

    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final product = _results[index];
        final isLowOrNeg = product.isStockNonPositive;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMainLight,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 12,
                      children: [
                        Text(
                          product.primaryBarcode ?? 'Barkodsuz',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.textMutedLight,
                            fontFeatures: AppTheme.tabularFiguresFeature,
                          ),
                        ),
                        Text(
                          'Stok: ${Money.formatMilliWithUnit(product.stockMilli, product.stockUnit)}${isLowOrNeg ? ' (allow)' : ''}',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: isLowOrNeg
                                ? AppTheme.posWarningText
                                : AppTheme.statusOnline,
                            fontFeatures: AppTheme.tabularFiguresFeature,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                Money.formatCents(product.priceCents),
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textMainLight,
                  fontFeatures: AppTheme.tabularFiguresFeature,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                key: Key('search_add_${product.id}'),
                onPressed: () {
                  widget.onSelectProduct(product);
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(118, 48),
                ),
                child: const Text('Sepete Ekle'),
              ),
            ],
          ),
        );
      },
    );
  }
}

