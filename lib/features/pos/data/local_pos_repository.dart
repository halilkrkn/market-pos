import 'package:drift/drift.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../../../core/storage/local_database_service.dart';
import '../domain/cart_state.dart';
import '../domain/pos_exceptions.dart';
import '../domain/pos_product.dart';
import '../domain/pos_repository.dart';

/// `LocalDatabaseService` ve `ClientStorageRepository` üzerine kurulu POS veri adaptörü.
///
/// Dual SQLite ilkesi (`INV-02`) gereği yalnızca istemci yerel veritabanına
/// (`client_local.db`) erişir; merkezi `market_master.db` ile doğrudan bağ kurmaz.
class LocalPosRepository implements PosRepository {
  final LocalDatabaseService localDbService;

  const LocalPosRepository(this.localDbService);

  @override
  Future<BarcodeLookupResult> findByBarcode(String barcode) async {
    final trimmed = barcode.trim();
    if (trimmed.isEmpty) {
      throw const PosDomainException('Barkod boş olamaz.');
    }

    return localDbService.runOperation(() async {
      final db = localDbService.database;

      // 1. Tek doğruluk kaynağı: LocalProductBarcodes (aktif ve pasif kayıtlar birlikte kontrol edilir)
      final barcodeRow = await (db.select(db.localProductBarcodes)
            ..where((b) => b.barcode.equals(trimmed)))
          .getSingleOrNull();

      if (barcodeRow != null) {
        if (!barcodeRow.isActive) {
          // Bilinçli pasifleştirilen barkod stale primary kolondan sızdırılamaz
          return BarcodeLookupResult.notFoundOffline(trimmed);
        }

        final product = await (db.select(db.localProducts)
              ..where((p) => p.id.equals(barcodeRow.productId)))
            .getSingleOrNull();
        if (product == null) {
          return BarcodeLookupResult.notFoundOffline(trimmed);
        }
        final mapped = _mapProduct(product, resolvedBarcode: trimmed);
        if (!product.isActive) {
          return BarcodeLookupResult.inactiveProduct(mapped, trimmed);
        }
        return BarcodeLookupResult.found(mapped, trimmed);
      }

      // 2. Yalnızca LocalProductBarcodes içinde kaydı olmayan ürünler için birincil barkod yedeği
      final fallbackProduct = await (db.select(db.localProducts)
            ..where((p) => p.barcode.equals(trimmed))
            ..limit(1))
          .getSingleOrNull();

      if (fallbackProduct == null) {
        return BarcodeLookupResult.notFoundOffline(trimmed);
      }

      final mapped = _mapProduct(fallbackProduct, resolvedBarcode: trimmed);
      if (!fallbackProduct.isActive) {
        return BarcodeLookupResult.inactiveProduct(mapped, trimmed);
      }
      return BarcodeLookupResult.found(mapped, trimmed);
    });
  }

  static const int maxSearchLimit = 200;
  static const int _unicodeScanChunkSize = 200;
  static final RegExp _asciiOnlyRegex = RegExp(r'^[\x00-\x7F]+$');

  static String _escapeLikePattern(String input) => input
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  @override
  Future<List<PosProduct>> searchActiveProducts(
    String query, {
    int limit = 50,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(
        limit,
        'limit',
        'Arama limiti 1 veya daha büyük olmalıdır.',
      );
    }
    final effectiveLimit = limit > maxSearchLimit ? maxSearchLimit : limit;
    final normalizedQuery = query.trim().toLowerCase();

    return localDbService.runOperation(() async {
      final db = localDbService.database;

      if (normalizedQuery.isEmpty) {
        final matched = await (db.select(db.localProducts)
              ..where((p) => p.isActive.equals(true))
              ..orderBy([(p) => OrderingTerm.asc(p.name)])
              ..limit(effectiveLimit))
            .get();
        return _resolveProducts(db, matched);
      }

      // ASCII sorgular için SQLite LIKE + EXISTS pushdown ile bellek kullanımını sınırla
      if (_asciiOnlyRegex.hasMatch(normalizedQuery)) {
        final pattern = '%${_escapeLikePattern(normalizedQuery)}%';
        final idRows = await db.customSelect(
          r'''
          SELECT p.id
          FROM local_products p
          WHERE p.is_active = 1
            AND (
              LOWER(p.name) LIKE ?1 ESCAPE '\'
              OR EXISTS (
                SELECT 1 FROM local_product_barcodes b
                WHERE b.product_id = p.id
                  AND b.is_active = 1
                  AND LOWER(b.barcode) LIKE ?1 ESCAPE '\'
              )
              OR (
                p.barcode IS NOT NULL
                AND LOWER(p.barcode) LIKE ?1 ESCAPE '\'
                AND NOT EXISTS (
                  SELECT 1 FROM local_product_barcodes db
                  WHERE db.barcode = p.barcode
                    AND db.is_active = 0
                )
              )
            )
          ORDER BY p.name ASC
          LIMIT ?2
          ''',
          variables: [
            Variable.withString(pattern),
            Variable.withInt(effectiveLimit),
          ],
          readsFrom: {db.localProducts, db.localProductBarcodes},
        ).get();

        if (idRows.isEmpty) {
          return const <PosProduct>[];
        }

        final matchedIds = idRows.map((row) => row.read<String>('id')).toList();
        final matchedProducts = await (db.select(db.localProducts)
              ..where((p) => p.id.isIn(matchedIds))
              ..orderBy([(p) => OrderingTerm.asc(p.name)]))
            .get();
        return _resolveProducts(db, matchedProducts);
      }

      // Türkçe/Unicode büyük-küçük harf katlaması için sayfalı (bounded) tarama
      final results = <PosProduct>[];
      var offset = 0;
      while (results.length < effectiveLimit) {
        final chunk = await (db.select(db.localProducts)
              ..where((p) => p.isActive.equals(true))
              ..orderBy([(p) => OrderingTerm.asc(p.name)])
              ..limit(_unicodeScanChunkSize, offset: offset))
            .get();
        if (chunk.isEmpty) {
          break;
        }

        final barcodeContext = await _loadBarcodeContext(db, chunk);
        for (final prod in chunk) {
          final resolved = _resolveSingleProduct(prod, barcodeContext);
          final productActiveBarcodes =
              barcodeContext.activeByProduct[prod.id] ??
                  const <LocalProductBarcode>[];
          final matches = prod.name.toLowerCase().contains(normalizedQuery) ||
              (resolved.fallbackBarcode != null &&
                  resolved.fallbackBarcode!
                      .toLowerCase()
                      .contains(normalizedQuery)) ||
              productActiveBarcodes.any(
                (b) => b.barcode.toLowerCase().contains(normalizedQuery),
              );

          if (matches) {
            results.add(resolved.product);
            if (results.length >= effectiveLimit) {
              break;
            }
          }
        }

        if (chunk.length < _unicodeScanChunkSize) {
          break;
        }
        offset += _unicodeScanChunkSize;
      }

      return results;
    });
  }

  Future<List<PosProduct>> _resolveProducts(
    ClientDatabase db,
    List<LocalProduct> products,
  ) async {
    if (products.isEmpty) {
      return const <PosProduct>[];
    }
    final context = await _loadBarcodeContext(db, products);
    return products
        .map((prod) => _resolveSingleProduct(prod, context).product)
        .toList(growable: false);
  }

  Future<_BarcodeContext> _loadBarcodeContext(
    ClientDatabase db,
    List<LocalProduct> products,
  ) async {
    final productIds = products.map((p) => p.id).toList(growable: false);
    final fallbackBarcodes = products
        .map((p) => p.barcode)
        .whereType<String>()
        .toSet()
        .toList(growable: false);

    final barcodeRows = await (db.select(db.localProductBarcodes)
          ..where((b) {
            final byProduct = b.productId.isIn(productIds);
            if (fallbackBarcodes.isEmpty) {
              return byProduct;
            }
            return byProduct |
                (b.barcode.isIn(fallbackBarcodes) & b.isActive.equals(false));
          }))
        .get();

    final activeByProduct = <String, List<LocalProductBarcode>>{};
    final deactivatedBarcodes = <String>{};
    for (final row in barcodeRows) {
      if (row.isActive) {
        activeByProduct.putIfAbsent(row.productId, () => []).add(row);
      } else {
        deactivatedBarcodes.add(row.barcode);
      }
    }

    return _BarcodeContext(
      activeByProduct: activeByProduct,
      deactivatedBarcodes: deactivatedBarcodes,
    );
  }

  ({PosProduct product, String? fallbackBarcode}) _resolveSingleProduct(
    LocalProduct prod,
    _BarcodeContext context,
  ) {
    final activeBarcodes =
        context.activeByProduct[prod.id] ?? const <LocalProductBarcode>[];
    final primaryRow = activeBarcodes
        .where((b) => b.isPrimary)
        .cast<LocalProductBarcode?>()
        .firstWhere((_) => true, orElse: () => null);
    final fallbackBarcode = prod.barcode != null &&
            !context.deactivatedBarcodes.contains(prod.barcode)
        ? prod.barcode
        : null;
    final displayBarcode = primaryRow?.barcode ??
        (activeBarcodes.isNotEmpty
            ? activeBarcodes.first.barcode
            : fallbackBarcode);

    return (
      product: _mapProduct(prod, resolvedBarcode: displayBarcode),
      fallbackBarcode: fallbackBarcode,
    );
  }

  @override
  Future<PosCompletedSale> completeOfflineSale({
    required String deviceId,
    required CartState cart,
    required PaymentMethod paymentMethod,
    int? cashReceivedCents,
    required bool externalPosConfirmed,
  }) async {
    if (!cart.hasPayableItems) {
      throw const PosDomainException(
        'Satış tamamlanabilmesi için geçerli ve toplam tutarı pozitif bir sepet gerekir.',
      );
    }

    if (paymentMethod == PaymentMethod.cash) {
      if (cashReceivedCents == null || cashReceivedCents < cart.totalCents) {
        throw const PosDomainException(
          'Alınan nakit tutar toplam satış tutarından az olamaz.',
        );
      }
    } else {
      if (cashReceivedCents != null) {
        throw const PosDomainException(
          'Kart ödemesinde alınan nakit tutar gönderilemez.',
        );
      }
      if (!externalPosConfirmed) {
        throw const PosDomainException(
          'Harici POS terminaline tutarın manuel girildiği teyit edilmelidir.',
        );
      }
    }

    final seenProductIds = <String>{};
    final itemInputs = <CartItemInput>[];
    for (final item in cart.items) {
      if (!seenProductIds.add(item.productId)) {
        throw PosDomainException(
          'Sepette mükerrer ürün satırı bulundu: ${item.productName}',
        );
      }
      itemInputs.add(
        CartItemInput.fractional(
          item.productId,
          item.quantityMilli,
          expectedUnitPrice: item.unitPriceCents,
          expectedPriceVersionId: item.priceVersionId,
        ),
      );
    }

    final SaleTransactionResult result;
    try {
      result = await localDbService.repository.createOfflineSale(
        deviceId: deviceId,
        paymentMethod: paymentMethod.code,
        items: itemInputs,
      );
    } on PriceChangedException catch (e) {
      throw PosDomainException(e.message);
    }

    final cashChange = cashReceivedCents == null
        ? null
        : cashReceivedCents - result.totalAmount;

    return PosCompletedSale(
      saleId: result.saleId,
      deviceId: result.deviceId,
      clientSeq: result.clientSeq,
      totalAmountCents: result.totalAmount,
      paymentMethod: PaymentMethod.parse(result.paymentMethod),
      cashReceivedCents: cashReceivedCents,
      cashChangeCents: cashChange,
      operationId: result.operationId,
      createdAt: result.createdAt,
      items: result.items
          .map(
            (i) => PosCompletedSaleItem(
              productId: i.productId,
              productName: i.productName,
              unitSnapshot: i.unitSnapshot,
              unitPriceCents: i.unitPrice,
              quantityMilli: i.quantity,
              totalPriceCents: i.totalPrice,
            ),
          )
          .toList(),
    );
  }

  static PosProduct _mapProduct(
    LocalProduct row, {
    String? resolvedBarcode,
  }) {
    return PosProduct(
      id: row.id,
      primaryBarcode: resolvedBarcode ?? row.barcode,
      name: row.name,
      priceCents: row.price,
      priceVersionId: row.priceVersionId,
      stockMilli: row.stock,
      stockUnit: row.stockUnit,
      pricingUnit: row.pricingUnit,
      conversionFactorNumerator: row.conversionFactorNumerator,
      conversionFactorDenominator: row.conversionFactorDenominator,
      isActive: row.isActive,
    );
  }
}

class _BarcodeContext {
  final Map<String, List<LocalProductBarcode>> activeByProduct;
  final Set<String> deactivatedBarcodes;

  const _BarcodeContext({
    required this.activeByProduct,
    required this.deactivatedBarcodes,
  });
}

