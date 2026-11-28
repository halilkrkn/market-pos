import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import 'client_database.dart';
import '../models/cart_item_input.dart';
import '../models/payment_method.dart';
import '../models/price_changed_exception.dart';
import '../models/product_catalog_sync_status.dart';
import '../models/refund_item_input.dart';
import '../models/sale_detail_models.dart';
import '../models/dashboard_summary.dart';
import '../models/sale_transaction_result.dart';
import '../models/stock_receipt_result.dart';
import '../models/downloaded_sale_payload.dart';
import '../models/hub_connection_config.dart';
import '../models/hub_url_validator.dart';
import 'package:mms_contracts/mms_contracts.dart';

class PostRestoreHistoryMissingException implements Exception {
  final String code;
  final String message;

  const PostRestoreHistoryMissingException(this.code, this.message);

  @override
  String toString() => 'PostRestoreHistoryMissingException [$code]: $message';
}

class ClientStorageRepository {
  static const int quantityScale =
      CartItemInput.scale; // 1000 (3 ondalık hane ölçeği)
  static const int _maxSafeInt =
      9223372036854775807; // 2^63 - 1 (64-bit signed int max)
  static const int _minSafeInt =
      -9223372036854775808; // -2^63 (64-bit signed int min)
  static const int _maxAmountCents =
      100000000000; // 1 milyar TL (10^11 kuruş) üst tutar sınırı
  static final Random _secureRandom = Random.secure();
  static int _idNonceCounter = 0;

  static String _nextUniqueToken() {
    _idNonceCounter = (_idNonceCounter + 1) & 0x7fffffff;
    final randHex =
        _secureRandom.nextInt(0x10000000).toRadixString(16).padLeft(7, '0');
    return '${_idNonceCounter.toRadixString(36)}_$randHex';
  }

  final ClientDatabase db;

  ClientStorageRepository(this.db);

  /// S5A-3: Satış işlem yükünün (payload) kanonik SHA-256 hash özetini üretir (Backend ile %100 uyumlu)
  static String computeSaleRequestHash(Map<String, dynamic> body) {
    final opType = body['operation_type'] as String? ??
        (body.containsKey('refund_id')
            ? 'SALE_REFUND'
            : (body.containsKey('reason') && !body.containsKey('total_amount')
                ? 'SALE_CANCEL'
                : 'SALE_CREATE'));

    if (opType == 'SALE_CANCEL') {
      final canonical = {
        'operation_type': 'SALE_CANCEL',
        'client_seq': body['client_seq'],
        'sale_id': body['sale_id'],
        'reason': body['reason'],
      };
      return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
    } else if (opType == 'SALE_REFUND') {
      final canonical = {
        'operation_type': 'SALE_REFUND',
        'client_seq': body['client_seq'],
        'refund_id': body['refund_id'],
        'sale_id': body['sale_id'],
        'total_refund_amount': body['total_refund_amount'],
        'items': body['items'],
      };
      return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
    }

    final canonical = {
      'client_seq': body['client_seq'],
      'total_amount': body['total_amount'],
      'payment_method': body['payment_method'],
      'items': body['items'],
    };
    return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
  }

  /// Cihazın senkronizasyon durumunu başlatır veya mevcut olanı döner.
  /// Self-healing: Mevcut outbox kayıtları varsa currentClientSeq en az MAX(client_seq) olarak onarılır.
  Future<ClientSyncState> initializeDevice(String deviceId) async {
    final maxSeqExp = db.outboxOperations.clientSeq.max();
    final maxOutboxRow = await (db.selectOnly(db.outboxOperations)
          ..addColumns([maxSeqExp])
          ..where(db.outboxOperations.deviceId.equals(deviceId)))
        .getSingle();
    final maxOutboxSeq = maxOutboxRow.read(maxSeqExp) ?? 0;

    final existing = await (db.select(db.clientSyncStates)
          ..where((s) => s.deviceId.equals(deviceId)))
        .getSingleOrNull();

    final now = DateTime.now();

    // Self-healing: İade edilmiş yerel satış durumlarını doğrula ve onar
    await reconcileSaleStatuses();

    if (existing != null) {
      if (existing.currentClientSeq < maxOutboxSeq) {
        // Self-healing: Geride kalmış sequence değerini onar (lastSyncedSeq korunur)
        await (db.update(db.clientSyncStates)
              ..where((s) => s.deviceId.equals(deviceId)))
            .write(
          ClientSyncStatesCompanion(
            currentClientSeq: Value(maxOutboxSeq),
            updatedAt: Value(now),
          ),
        );
        return (await (db.select(db.clientSyncStates)
              ..where((s) => s.deviceId.equals(deviceId)))
            .getSingle());
      }
      return existing;
    }

    final newState = ClientSyncStatesCompanion(
      deviceId: Value(deviceId),
      currentClientSeq: Value(maxOutboxSeq),
      lastSyncedSeq: const Value(0),
      updatedAt: Value(now),
    );

    await db.into(db.clientSyncStates).insert(newState);
    return (await (db.select(db.clientSyncStates)
          ..where((s) => s.deviceId.equals(deviceId)))
        .getSingle());
  }

  /// Cihazın senkronizasyon durumunu döner
  Future<ClientSyncState?> getSyncState(String deviceId) async {
    return (db.select(db.clientSyncStates)
          ..where((s) => s.deviceId.equals(deviceId)))
        .getSingleOrNull();
  }

  /// Monotonik artan sonraki istemci sıra numarasını (client_seq) güvenli bir şekilde tahsis eder.
  /// Formül: max(current_client_seq, MAX(outbox_operations.client_seq)) + 1
  /// Not: Bu metot mutlaka çağıran operasyonun atomik db.transaction bloğu içinde çalıştırılmalıdır.
  Future<int> allocateNextClientSeq(String deviceId,
      {DateTime? occurredAt}) async {
    final effectiveNow = occurredAt ?? DateTime.now();

    // 1. Outbox'taki fiili en yüksek sıra numarasını bul
    final maxSeqExp = db.outboxOperations.clientSeq.max();
    final maxOutboxRow = await (db.selectOnly(db.outboxOperations)
          ..addColumns([maxSeqExp])
          ..where(db.outboxOperations.deviceId.equals(deviceId)))
        .getSingle();
    final maxOutboxSeq = maxOutboxRow.read(maxSeqExp) ?? 0;

    // 2. client_sync_states tablosundaki kayıtlı sırayı al
    final existingState = await (db.select(db.clientSyncStates)
          ..where((s) => s.deviceId.equals(deviceId)))
        .getSingleOrNull();

    final stateSeq = existingState?.currentClientSeq ?? 0;
    final lastSynced = existingState?.lastSyncedSeq ?? 0;

    // 3. Gerçek zemin: İkisinin en büyüğü + 1
    final baseSeq = maxOutboxSeq > stateSeq ? maxOutboxSeq : stateSeq;
    final nextSeq = baseSeq + 1;

    // 4. client_sync_states tablosunu atomik olarak güncelle/ekle (lastSyncedSeq korunur)
    await db.into(db.clientSyncStates).insertOnConflictUpdate(
          ClientSyncStatesCompanion(
            deviceId: Value(deviceId),
            currentClientSeq: Value(nextSeq),
            lastSyncedSeq: Value(lastSynced),
            updatedAt: Value(effectiveNow),
          ),
        );

    return nextSeq;
  }

  Future<int> _allocateNextClientSeq(String deviceId, {DateTime? occurredAt}) =>
      allocateNextClientSeq(deviceId, occurredAt: occurredAt);

  /// S5A-3: Tek bir atomik SQLite transaction içinde çevrimdışı satış oluşturur:
  /// 1. client_seq artırımı (monotonic & persistent)
  /// 2. local_sales kaydı
  /// 3. local_sale_items kayıtları (fiyat, birim ve ürün adı snapshotları; kesirli miktar hesabı)
  /// 4. local_stock_movements kayıtları (negatif satış stok hareketi, milli-birim)
  /// 5. local_products tablosunda stok düşümü (ALLOW politikası: eksiye düşebilir)
  /// 6. outbox_operations kaydı (PENDING durumu)
  /// 7. client_sync_states tablosunda currentClientSeq güncellemesi
  Future<SaleTransactionResult> createOfflineSale({
    required String deviceId,
    required String paymentMethod,
    required List<CartItemInput> items,
    String? customOperationId,
    DateTime? occurredAt,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError('Satış en az bir ürün içermelidir.');
    }
    if (deviceId.trim().isEmpty) {
      throw ArgumentError('Cihaz kimliği boş olamaz.');
    }
    final canonicalPaymentMethod = PaymentMethod.parse(paymentMethod).code;

    // Transaction açılmadan önce yinelenen ürün ve miktar sınırlarını doğrula
    final seenProductIds = <String>{};
    for (final item in items) {
      if (!seenProductIds.add(item.productId)) {
        throw ArgumentError(
          'Aynı ürün aynı satışta birden fazla kalem olarak eklenemez: ${item.productId}',
        );
      }
      if (item.quantity <= 0 || item.quantity > CartItemInput.maxQuantity) {
        throw ArgumentError(
          'Geçersiz satış miktarı (${item.quantity}): ${item.productId}',
        );
      }
      if (item.expectedUnitPrice != null && item.expectedUnitPrice! < 0) {
        throw ArgumentError(
          'Beklenen birim fiyat negatif olamaz: ${item.expectedUnitPrice}',
        );
      }
    }

    final saleTimestamp = occurredAt ?? DateTime.now();

    return await db.transaction(() async {
      // A. Cihaz senkronizasyon sıra numarasını (client_seq) güvenli ve kilitli olarak tahsis et
      final nextSeq =
          await _allocateNextClientSeq(deviceId, occurredAt: saleTimestamp);
      final uniqueToken = _nextUniqueToken();
      final saleId =
          'csale_${saleTimestamp.microsecondsSinceEpoch}_${nextSeq}_$uniqueToken';
      final operationId = customOperationId ??
          'op_${saleTimestamp.microsecondsSinceEpoch}_${nextSeq}_$uniqueToken';

      var calculatedTotalAmount = 0;
      final itemResults = <SaleTransactionItemResult>[];
      final payloadItems = <Map<String, dynamic>>[];

      // B. Sepetteki her ürünün mevcudiyetini ve aktifliğini doğrula, snapshot al
      for (final item in items) {
        final product = await (db.select(db.localProducts)
              ..where((p) => p.id.equals(item.productId)))
            .getSingleOrNull();

        if (product == null) {
          throw StateError(
              'Ürün yerel veritabanında bulunamadı: ${item.productId}');
        }

        if (!product.isActive) {
          throw StateError(
              'Pasif ürün satılamaz: ${product.name} (${product.id})');
        }

        final unitPrice =
            product.price; // Kuruş bazlı (Ör: 200 TL/kg = 20000 kuruş)
        if (unitPrice < 0 || unitPrice > _maxAmountCents) {
          throw ArgumentError(
            'Geçersiz ürün birim fiyatı ($unitPrice): ${product.name} (${product.id})',
          );
        }
        final priceVersionId =
            product.priceVersionId; // S5A-3: Fiyat sürüm kimliği

        // Faz 1.2 Güvenilirlik: Sepet snapshot'ı ile DB güncel fiyatı/sürümü tutarlılık kontrolü
        final priceChanged = item.expectedUnitPrice != null &&
            unitPrice != item.expectedUnitPrice;
        final versionChanged = item.expectedPriceVersionId != null &&
            priceVersionId != item.expectedPriceVersionId;
        if (priceChanged || versionChanged) {
          throw PriceChangedException(
            productId: product.id,
            productName: product.name,
            expectedUnitPrice: item.expectedUnitPrice,
            actualUnitPrice: unitPrice,
            expectedPriceVersionId: item.expectedPriceVersionId,
            actualPriceVersionId: priceVersionId,
            message:
                '"${product.name}" ürününün fiyatı veya sürümü değiştiği için '
                'satış mevcut tutarla tamamlanamaz. Lütfen sepeti güncelleyin.',
          );
        }

        // S5A-3: Çarpım öncesi Integer Overflow kontrolü
        if (unitPrice > 0 &&
            item.quantity > (_maxSafeInt - (quantityScale ~/ 2)) ~/ unitPrice) {
          throw ArgumentError(
              'Birim fiyat ve miktar çarpımı tamsayı sınırını aşıyor (Integer Overflow).');
        }

        // Kesirli miktar hesabı: itemTotal = ((unitPrice * quantity) + 500) ~/ 1000 (Standart ticari yuvarlama)
        final itemTotal =
            ((unitPrice * item.quantity) + (quantityScale ~/ 2)) ~/
                quantityScale;
        if (itemTotal < 0 || itemTotal > _maxAmountCents) {
          throw ArgumentError(
              'Satır tutarı izin verilen üst sınırı aşıyor: $itemTotal');
        }

        // Toplam sepet tutarı taşma ve üst sınır kontrolü
        if (calculatedTotalAmount > _maxSafeInt - itemTotal ||
            calculatedTotalAmount + itemTotal > _maxAmountCents) {
          throw ArgumentError(
              'Toplam sepet tutarı tamsayı veya tutar sınırını aşıyor.');
        }
        calculatedTotalAmount += itemTotal;

        // Birim dönüşümü: 1 pricing_unit = (num / den) stock_unit
        final num = product.conversionFactorNumerator;
        final den = product.conversionFactorDenominator;
        if (num <= 0 || den <= 0) {
          throw StateError(
              'Geçersiz birim dönüşüm katsayısı ($num / $den): ${product.name}');
        }

        // Dönüşüm öncesi taşma kontrolü
        if (num > 0 && item.quantity > _maxSafeInt ~/ num) {
          throw ArgumentError(
              'Miktar ve birim katsayısı çarpımı tamsayı sınırını aşıyor (Integer Overflow).');
        }

        final prodMilli = item.quantity * num;
        if (prodMilli % den != 0) {
          throw ArgumentError(
            'Miktar (${item.quantity}), ürün stok birimine (${product.stockUnit}) kayıpsız dönüştürülemiyor. Kalan: ${prodMilli % den}',
          );
        }
        final stockDelta = prodMilli ~/ den;
        if (stockDelta > 0 && product.stock < _minSafeInt + stockDelta) {
          throw ArgumentError(
            'Stok azaltma işlemi 64-bit tamsayı alt sınırını aşıyor (Integer Underflow): ${product.name}',
          );
        }

        itemResults.add(SaleTransactionItemResult(
          productId: product.id,
          productName: product.name,
          unitSnapshot: product.pricingUnit,
          priceVersionId: priceVersionId,
          unitPrice: unitPrice,
          quantity: item.quantity,
          totalPrice: itemTotal,
          stockDelta: stockDelta,
          stockUnit: product.stockUnit,
        ));

        payloadItems.add({
          'product_id': product.id,
          'price_version_id': priceVersionId,
          'quantity': item.quantity,
          'unit_price': unitPrice,
          'total_price': itemTotal,
          'unit': product.pricingUnit,
        });
      }

      // C. local_sales tablosuna ekle
      await db.into(db.localSales).insert(
            LocalSalesCompanion(
              id: Value(saleId),
              deviceId: Value(deviceId),
              clientSeq: Value(nextSeq),
              totalAmount: Value(calculatedTotalAmount),
              paymentMethod: Value(canonicalPaymentMethod),
              status: const Value('COMPLETED'),
              createdAt: Value(saleTimestamp),
            ),
          );

      // D. Kalemleri, stok hareketlerini ve ürün stok güncellemelerini işle
      for (final item in itemResults) {
        final itemId = 'citem_${saleId}_${item.productId}';
        await db.into(db.localSaleItems).insert(
              LocalSaleItemsCompanion(
                id: Value(itemId),
                saleId: Value(saleId),
                productId: Value(item.productId),
                productNameSnapshot: Value(item.productName),
                unitSnapshot: Value(item.unitSnapshot),
                priceVersionId: Value(item.priceVersionId),
                unitPrice: Value(item.unitPrice),
                quantity: Value(item.quantity),
                totalPrice: Value(item.totalPrice),
              ),
            );

        final movementId = 'csm_${saleId}_${item.productId}';
        await db.into(db.localStockMovements).insert(
              LocalStockMovementsCompanion(
                id: Value(movementId),
                productId: Value(item.productId),
                quantity: Value(-item.stockDelta),
                unit: Value(item.stockUnit),
                movementType: const Value('SATIS'),
                referenceId: Value(saleId),
                createdAt: Value(saleTimestamp),
              ),
            );

        // S5A-3: ALLOW politikası — Stok yetersiz olsa bile düşer, eksiye izin verilir
        final currentProd = await (db.select(db.localProducts)
              ..where((p) => p.id.equals(item.productId)))
            .getSingle();

        if ((item.stockDelta > 0 &&
                currentProd.stock < _minSafeInt + item.stockDelta) ||
            (item.stockDelta < 0 &&
                currentProd.stock > _maxSafeInt + item.stockDelta)) {
          throw ArgumentError(
            'Stok güncelleme işlemi 64-bit tamsayı sınırını aşıyor: ${item.productName}',
          );
        }
        final updatedStock = currentProd.stock - item.stockDelta;
        await (db.update(db.localProducts)
              ..where((p) => p.id.equals(item.productId)))
            .write(
          LocalProductsCompanion(
            stock: Value(updatedStock),
            updatedAt: Value(saleTimestamp),
          ),
        );
      }

      // E. Değiştirilemez Outbox Payload'ı ve SHA-256 Özeti oluştur
      final outboxPayloadMap = {
        'operation_id': operationId,
        'client_seq': nextSeq,
        'total_amount': calculatedTotalAmount,
        'payment_method': canonicalPaymentMethod,
        'items': payloadItems,
      };

      final payloadJsonStr = jsonEncode(outboxPayloadMap);
      final payloadHash = computeSaleRequestHash(outboxPayloadMap);

      // F. outbox_operations tablosuna ekle
      await db.into(db.outboxOperations).insert(
            OutboxOperationsCompanion(
              operationId: Value(operationId),
              deviceId: Value(deviceId),
              clientSeq: Value(nextSeq),
              operationType: const Value('SALE_CREATE'),
              payload: Value(payloadJsonStr),
              payloadHash: Value(payloadHash),
              occurredAt: Value(saleTimestamp),
              status: const Value('PENDING'),
              attemptCount: const Value(0),
              createdAt: Value(saleTimestamp),
            ),
          );

      // G. client_sync_states tablosu _allocateNextClientSeq tarafından atomik olarak güncellendi

      return SaleTransactionResult(
        saleId: saleId,
        deviceId: deviceId,
        clientSeq: nextSeq,
        totalAmount: calculatedTotalAmount,
        paymentMethod: canonicalPaymentMethod,
        operationId: operationId,
        items: itemResults,
        createdAt: saleTimestamp,
        isCommitted: true,
      );
    });
  }

  /// Hub'dan gelen kategori listesini hiyerarşik `parentId` sırasını koruyarak
  /// atomik olarak yerel `LocalCategories` tablosuna işler.
  /// Echo prevention: İndirilen kategoriler asla Outbox'a yazılmaz; yerel
  /// senkronize edilmemiş `CATEGORY_UPSERT` değişiklikleri korunur.
  Future<void> upsertCategories(List<LocalCategoriesCompanion> categories) async {
    if (categories.isEmpty) return;

    await db.transaction(() async {
      final pendingCatOps = await (db.select(db.outboxOperations)
            ..where((o) =>
                o.status.isIn(_unsyncedOutboxStatuses) &
                o.operationType.equals('CATEGORY_UPSERT')))
          .get();
      final protectedCategoryIds = <String>{};
      for (final op in pendingCatOps) {
        try {
          final decoded = jsonDecode(op.payload);
          if (decoded is Map<String, dynamic>) {
            final cat = decoded['category'];
            if (cat is Map<String, dynamic> && cat['id'] is String) {
              protectedCategoryIds.add(cat['id'] as String);
            }
          }
        } catch (_) {
          // Bozuk outbox kaydı senkronizasyonu kesmez.
        }
      }

      final existingRows = await db.select(db.localCategories).get();
      final knownIds = <String>{for (final c in existingRows) c.id};

      final remaining = <LocalCategoriesCompanion>[
        for (final c in categories)
          if (c.id.present &&
              c.id.value.isNotEmpty &&
              !protectedCategoryIds.contains(c.id.value))
            c,
      ];

      while (remaining.isNotEmpty) {
        final ready = <LocalCategoriesCompanion>[];
        final nextRemaining = <LocalCategoriesCompanion>[];

        for (final cat in remaining) {
          final parentId = cat.parentId.present ? cat.parentId.value : null;
          if (parentId == null ||
              parentId.isEmpty ||
              knownIds.contains(parentId)) {
            ready.add(cat);
          } else {
            nextRemaining.add(cat);
          }
        }

        if (ready.isEmpty) {
          // Eksik veya döngüsel ebeveyn referansı varsa önce parentId olmadan ekle,
          // ardından bilinen ebeveynleri güncelle.
          for (final cat in nextRemaining) {
            final safeRow = cat.copyWith(parentId: const Value(null));
            await db.into(db.localCategories).insert(
                  safeRow,
                  onConflict: DoUpdate((_) => safeRow),
                );
            knownIds.add(cat.id.value);
          }
          for (final cat in nextRemaining) {
            final parentId = cat.parentId.present ? cat.parentId.value : null;
            if (parentId != null &&
                parentId.isNotEmpty &&
                parentId != cat.id.value &&
                knownIds.contains(parentId)) {
              await (db.update(db.localCategories)
                    ..where((c) => c.id.equals(cat.id.value)))
                  .write(LocalCategoriesCompanion(parentId: Value(parentId)));
            }
          }
          break;
        }

        await db.batch((b) {
          for (final cat in ready) {
            b.insert(
              db.localCategories,
              cat,
              onConflict: DoUpdate((_) => cat),
            );
          }
        });
        for (final cat in ready) {
          knownIds.add(cat.id.value);
        }
        remaining
          ..clear()
          ..addAll(nextRemaining);
      }
    });
  }

  /// Sunucudan gelen ürün listesini ve ilişkili barkodları atomik olarak günceller
  Future<void> upsertProducts(
    List<LocalProductsCompanion> products, {
    List<LocalProductBarcodesCompanion>? barcodes,
    bool deactivateRemovedBarcodes = false,
  }) async {
    await db.transaction(() async {
      // 9.4: Hub'a henüz gönderilmemiş (PRODUCT_UPSERT bekleyen) ürünlerin yerel barkod
      // kümesi ve birincil barkodu Hub snapshot'ı tarafından EZİLMEZ. Yerel niyet Outbox'ta
      // korunur; Hub onayladıktan sonraki ilk senkronda Hub verisi yeniden uygulanır.
      // (Faz 7A bekleyen stok koruması ile aynı ilke.)
      final pendingCatalogProductIds =
          await productIdsWithPendingCatalogChanges();
      bool isProtected(LocalProductBarcodesCompanion bc) =>
          bc.productId.present &&
          pendingCatalogProductIds.contains(bc.productId.value);

      await db.customStatement(
        'CREATE TABLE IF NOT EXISTS local_hub_synced_products (product_id TEXT PRIMARY KEY, synced_at TEXT NOT NULL);',
      );
      final hubSyncedRows = await db
          .customSelect('SELECT product_id FROM local_hub_synced_products;')
          .get();
      final hubSyncedIds =
          hubSyncedRows.map((r) => r.read<String>('product_id')).toSet();

      final hasBarcodes = barcodes != null && barcodes.isNotEmpty;
      final useTargetedLoad = products.length <= 500 &&
          (barcodes == null || barcodes.length <= 500);

      final List<LocalProductBarcode> existingBarcodes;
      if (barcodes == null ||
          (useTargetedLoad && !hasBarcodes && products.isEmpty)) {
        existingBarcodes = const <LocalProductBarcode>[];
      } else if (useTargetedLoad) {
        final targetProductIds = <String>{
          for (final p in products)
            if (p.id.present) p.id.value,
        };
        final targetBcValues = <String>{
          for (final bc in barcodes)
            if (!isProtected(bc) &&
                bc.barcode.present &&
                bc.barcode.value.isNotEmpty)
              bc.barcode.value,
        };
        if (targetProductIds.isEmpty && targetBcValues.isEmpty) {
          existingBarcodes = const <LocalProductBarcode>[];
        } else {
          existingBarcodes = await (db.select(db.localProductBarcodes)
                ..where((b) {
                  Expression<bool>? pred;
                  if (targetBcValues.isNotEmpty) {
                    pred = b.barcode.isIn(targetBcValues);
                  }
                  if (targetProductIds.isNotEmpty) {
                    final byProd = b.productId.isIn(targetProductIds);
                    pred = pred == null ? byProd : (pred | byProd);
                  }
                  return pred!;
                }))
              .get();
        }
      } else {
        existingBarcodes = await db.select(db.localProductBarcodes).get();
      }

      final barcodeByValue = <String, LocalProductBarcode>{};
      final activeBarcodesByProduct = <String, List<LocalProductBarcode>>{};
      final extraProductIdsFromBarcodeCollisions = <String>{};
      for (final b in existingBarcodes) {
        barcodeByValue[b.barcode] = b;
        extraProductIdsFromBarcodeCollisions.add(b.productId);
        if (b.isActive) {
          activeBarcodesByProduct
              .putIfAbsent(b.productId, () => <LocalProductBarcode>[])
              .add(b);
        }
      }

      final List<LocalProduct> existingProducts;
      if (useTargetedLoad) {
        final targetProductIds = <String>{
          ...extraProductIdsFromBarcodeCollisions,
          for (final p in products)
            if (p.id.present) p.id.value,
        };
        final targetPrimaryBarcodes = <String>{
          for (final p in products)
            if (p.barcode.present && p.barcode.value != null) p.barcode.value!,
        };
        if (targetProductIds.isEmpty && targetPrimaryBarcodes.isEmpty) {
          existingProducts = const <LocalProduct>[];
        } else {
          existingProducts = await (db.select(db.localProducts)
                ..where((p) {
                  Expression<bool>? pred;
                  if (targetProductIds.isNotEmpty) {
                    pred = p.id.isIn(targetProductIds);
                  }
                  if (targetPrimaryBarcodes.isNotEmpty) {
                    final byBc = p.barcode.isIn(targetPrimaryBarcodes);
                    pred = pred == null ? byBc : (pred | byBc);
                  }
                  return pred!;
                }))
              .get();
        }
      } else {
        existingProducts = await db.select(db.localProducts).get();
      }

      final productById = <String, LocalProduct>{
        for (final p in existingProducts) p.id: p,
      };
      final currentPrimaryBarcodeByProductId = <String, String?>{
        for (final p in existingProducts) p.id: p.barcode,
      };
      final productIdsByPrimaryBarcode = <String, Set<String>>{};
      for (final p in existingProducts) {
        final bc = p.barcode;
        if (bc != null) {
          productIdsByPrimaryBarcode
              .putIfAbsent(bc, () => <String>{})
              .add(p.id);
        }
      }

      final skippedCollisionBarcodes = <LocalProductBarcodesCompanion>{};
      final skippedDenormBarcodesByProduct = <String, Set<String>>{};
      final barcodeIdsToDelete = <String>{};
      final primaryBarcodesToClearById = <String>{};

      // Barkod çakışma kontrolleri: Ürünler yazılmadan önce doğrulanır
      if (barcodes != null) {
        final seenBarcodesInBatch = <String, String>{}; // barcode -> productId

        for (final bc in barcodes) {
          if (isProtected(bc))
            continue; // uygulanmayacak; yerel sahiplik korunur
          if (bc.barcode.present && bc.barcode.value.isNotEmpty) {
            final barcodeVal = bc.barcode.value;
            final prodIdVal = bc.productId.value;

            // 1. Snapshot içi çakışma kontrolü: Aynı liste içinde aynı barkod farklı ürüne verilemez
            if (seenBarcodesInBatch.containsKey(barcodeVal) &&
                seenBarcodesInBatch[barcodeVal] != prodIdVal) {
              throw StateError(
                'Barkod çakışması: Gelen listede "$barcodeVal" barkodu birden fazla ürüne ($prodIdVal ve ${seenBarcodesInBatch[barcodeVal]}) atanmış. '
                'İşlem atomik olarak iptal edildi.',
              );
            }
            seenBarcodesInBatch[barcodeVal] = prodIdVal;

            // 2. Mevcut veritabanı çakışma kontrolü:
            // Yerel bekleyen/FAILED_PERMANENT üründeki barkod başka ürüne ait Hub verisiyle
            // çakışırsa diğer ürünlerin senkronizasyonu kesilmez; yerel barkod korunur ve
            // yalnızca çakışan barkodun karşı ürüne yazılması ertelenir.
            final existingBc = barcodeByValue[barcodeVal];

            if (existingBc != null) {
              if (existingBc.productId != prodIdVal) {
                if (deactivateRemovedBarcodes &&
                    pendingCatalogProductIds.contains(existingBc.productId)) {
                  skippedCollisionBarcodes.add(bc);
                  skippedDenormBarcodesByProduct
                      .putIfAbsent(prodIdVal, () => <String>{})
                      .add(barcodeVal);
                  continue;
                }
                if (!existingBc.isActive || deactivateRemovedBarcodes) {
                  barcodeIdsToDelete.add(existingBc.id);
                  barcodeByValue.remove(barcodeVal);
                  if (currentPrimaryBarcodeByProductId[existingBc.productId] ==
                      barcodeVal) {
                    primaryBarcodesToClearById.add(existingBc.productId);
                    currentPrimaryBarcodeByProductId[existingBc.productId] =
                        null;
                    productIdsByPrimaryBarcode[barcodeVal]
                        ?.remove(existingBc.productId);
                  }
                } else {
                  throw StateError(
                    'Barkod çakışması: "$barcodeVal" barkodu zaten mevcut başka bir ürüne (${existingBc.productId}) atanmış. '
                    'Mevcut barkod sahipliği korunarak işlem atomik olarak iptal edildi.',
                  );
                }
              } else if (bc.id.present && existingBc.id != bc.id.value) {
                // Aynı ürünün mevcut barkodu: ID farkı varsa (örn: local create vs Hub sync ID) eski kaydı temizle
                barcodeIdsToDelete.add(existingBc.id);
                barcodeByValue.remove(barcodeVal);
              }
            }
          }
        }
      }

      // Faz 7A: Bekleyen yerel stok değişiklikleri Hub snapshot'ı tarafından ezilmez.
      final pendingStockProductIds = await productIdsWithUnsyncedStockChanges();

      final productsToUpsert = <LocalProductsCompanion>[];
      final upsertIndexByProductId = <String, int>{};
      final syncedProductIds = <String>[];

      for (final incoming in products) {
        var prod = incoming;
        if (prod.id.present) {
          final prodId = prod.id.value;
          final hasPendingStock = pendingStockProductIds.contains(prodId);
          final hasPendingCatalog = pendingCatalogProductIds.contains(prodId);
          final isNeverSyncedLocal = !hubSyncedIds.contains(prodId);
          if (hasPendingStock || hasPendingCatalog || isNeverSyncedLocal) {
            final local = productById[prodId];
            if (local != null) {
              if (hasPendingStock || isNeverSyncedLocal) {
                prod = prod.copyWith(stock: Value(local.stock));
              }
              if (hasPendingCatalog) {
                prod = prod.copyWith(
                  name: Value(local.name),
                  price: Value(local.price),
                  priceVersionId: Value(local.priceVersionId),
                  barcode: Value(currentPrimaryBarcodeByProductId[prodId]),
                  categoryId: Value(local.categoryId),
                  stockUnit: Value(local.stockUnit),
                  pricingUnit: Value(local.pricingUnit),
                  conversionFactorNumerator:
                      Value(local.conversionFactorNumerator),
                  conversionFactorDenominator:
                      Value(local.conversionFactorDenominator),
                  vatRate: Value(local.vatRate),
                  isActive: Value(local.isActive),
                );
              }
            }
          }

          if (!hasPendingCatalog &&
              prod.barcode.present &&
              prod.barcode.value != null) {
            final incomingBc = prod.barcode.value!;
            final skippedForThis = skippedDenormBarcodesByProduct[prodId];
            if (skippedForThis != null && skippedForThis.contains(incomingBc)) {
              prod = prod.copyWith(barcode: const Value(null));
            } else {
              final owners = productIdsByPrimaryBarcode[incomingBc];
              String? conflictingOwnerId;
              if (owners != null) {
                for (final ownerId in owners) {
                  if (ownerId != prodId) {
                    if (conflictingOwnerId != null) {
                      throw StateError(
                        'Bad state: Multiple elements for barcode "$incomingBc".',
                      );
                    }
                    conflictingOwnerId = ownerId;
                  }
                }
              }
              if (conflictingOwnerId != null) {
                if (pendingCatalogProductIds.contains(conflictingOwnerId)) {
                  prod = prod.copyWith(barcode: const Value(null));
                } else {
                  primaryBarcodesToClearById.add(conflictingOwnerId);
                  productIdsByPrimaryBarcode[incomingBc]
                      ?.remove(conflictingOwnerId);
                  currentPrimaryBarcodeByProductId[conflictingOwnerId] = null;
                  final batchIdx = upsertIndexByProductId[conflictingOwnerId];
                  if (batchIdx != null) {
                    productsToUpsert[batchIdx] = productsToUpsert[batchIdx]
                        .copyWith(barcode: const Value(null));
                  }
                }
              }
            }
          }

          final prevBarcode = currentPrimaryBarcodeByProductId[prodId];
          if (prod.barcode.present) {
            final nextBarcode = prod.barcode.value;
            if (prevBarcode != null && prevBarcode != nextBarcode) {
              productIdsByPrimaryBarcode[prevBarcode]?.remove(prodId);
            }
            if (nextBarcode != null) {
              productIdsByPrimaryBarcode
                  .putIfAbsent(nextBarcode, () => <String>{})
                  .add(prodId);
            }
            currentPrimaryBarcodeByProductId[prodId] = nextBarcode;
          }

          if (prodId.isNotEmpty) {
            upsertIndexByProductId[prodId] = productsToUpsert.length;
            syncedProductIds.add(prodId);
          }
        }
        productsToUpsert.add(prod);
      }

      final barcodeIdsToDeactivate = <String>[];
      final barcodesToUpsert = <LocalProductBarcodesCompanion>[];
      if (barcodes != null) {
        if (deactivateRemovedBarcodes) {
          final incomingByProduct = <String, Set<String>>{};
          for (final bc in barcodes) {
            if (bc.productId.present &&
                bc.barcode.present &&
                bc.barcode.value.isNotEmpty) {
              incomingByProduct
                  .putIfAbsent(bc.productId.value, () => <String>{})
                  .add(bc.barcode.value);
            }
          }
          for (final incoming in products) {
            if (!incoming.id.present) continue;
            final prodIdVal = incoming.id.value;
            if (pendingCatalogProductIds.contains(prodIdVal)) continue;
            final keepSet = incomingByProduct[prodIdVal] ?? const <String>{};
            final existingRows = activeBarcodesByProduct[prodIdVal];
            if (existingRows != null) {
              for (final row in existingRows) {
                if (!barcodeIdsToDelete.contains(row.id) &&
                    !keepSet.contains(row.barcode)) {
                  barcodeIdsToDeactivate.add(row.id);
                }
              }
            }
          }
        }
        for (final bc in barcodes) {
          if (isProtected(bc) || skippedCollisionBarcodes.contains(bc))
            continue;
          barcodesToUpsert.add(bc);
        }
      }

      const chunkSize = 500;
      if (barcodeIdsToDelete.isNotEmpty) {
        final deleteList = barcodeIdsToDelete.toList(growable: false);
        for (var i = 0; i < deleteList.length; i += chunkSize) {
          final end = (i + chunkSize < deleteList.length)
              ? i + chunkSize
              : deleteList.length;
          await (db.delete(db.localProductBarcodes)
                ..where((b) => b.id.isIn(deleteList.sublist(i, end))))
              .go();
        }
      }

      if (primaryBarcodesToClearById.isNotEmpty) {
        final clearList = primaryBarcodesToClearById.toList(growable: false);
        for (var i = 0; i < clearList.length; i += chunkSize) {
          final end = (i + chunkSize < clearList.length)
              ? i + chunkSize
              : clearList.length;
          await (db.update(db.localProducts)
                ..where((p) => p.id.isIn(clearList.sublist(i, end))))
              .write(const LocalProductsCompanion(barcode: Value(null)));
        }
      }

      if (barcodeIdsToDeactivate.isNotEmpty) {
        for (var i = 0; i < barcodeIdsToDeactivate.length; i += chunkSize) {
          final end = (i + chunkSize < barcodeIdsToDeactivate.length)
              ? i + chunkSize
              : barcodeIdsToDeactivate.length;
          await (db.update(db.localProductBarcodes)
                ..where(
                    (b) => b.id.isIn(barcodeIdsToDeactivate.sublist(i, end))))
              .write(const LocalProductBarcodesCompanion(
            isActive: Value(false),
            isPrimary: Value(false),
          ));
        }
      }

      for (var i = 0; i < productsToUpsert.length; i += chunkSize) {
        final end = (i + chunkSize < productsToUpsert.length)
            ? i + chunkSize
            : productsToUpsert.length;
        final chunk = productsToUpsert.sublist(i, end);
        await db.batch((b) {
          for (final prod in chunk) {
            b.insert(
              db.localProducts,
              prod,
              onConflict: DoUpdate((_) => prod),
            );
          }
        });
      }

      if (syncedProductIds.isNotEmpty) {
        const pairChunkSize = 400; // 400 * 2 = 800 <= 999 SQLite bind limiti
        final syncedAtIso = DateTime.now().toIso8601String();
        for (var i = 0; i < syncedProductIds.length; i += pairChunkSize) {
          final end = (i + pairChunkSize < syncedProductIds.length)
              ? i + pairChunkSize
              : syncedProductIds.length;
          final chunk = syncedProductIds.sublist(i, end);
          final placeholders = List.filled(chunk.length, '(?, ?)').join(', ');
          final args = <Object>[
            for (final id in chunk) ...[id, syncedAtIso],
          ];
          await db.customStatement(
            'INSERT OR REPLACE INTO local_hub_synced_products (product_id, synced_at) VALUES $placeholders;',
            args,
          );
        }
      }

      for (var i = 0; i < barcodesToUpsert.length; i += chunkSize) {
        final end = (i + chunkSize < barcodesToUpsert.length)
            ? i + chunkSize
            : barcodesToUpsert.length;
        final chunk = barcodesToUpsert.sublist(i, end);
        await db.batch((b) {
          for (final bc in chunk) {
            b.insert(
              db.localProductBarcodes,
              bc,
              onConflict: DoUpdate((_) => bc),
            );
          }
        });
      }
    });
  }

  /// Hub'dan indirilen satışları, kalemleri ve iadeleri atomik olarak yerel SQLite veritabanına işler.
  /// Echo prevention: İndirilen satışlar ASLA outbox_operations kuyruğuna yazılmaz!
  Future<void> upsertSales({
    required List<DownloadedSalePayload> sales,
    required int newCursor,
    required String deviceId,
    DateTime? syncedAt,
  }) async {
    final effectiveSyncedAt = syncedAt ?? DateTime.now();
    await db.transaction(() async {
      for (final sale in sales) {
        // 1. Satışın daha önce bu cihazda kaydedilip kaydedilmediğini denetle
        // (device_id + client_seq veya id eşleşmesi)
        final existing = await (db.select(db.localSales)
              ..where((s) =>
                  s.id.equals(sale.id) |
                  (s.deviceId.equals(sale.deviceId) &
                      s.clientSeq.equals(sale.clientSeq))))
            .getSingleOrNull();

        if (existing != null) {
          // Satış zaten mevcut (örneğin bu cihaz tarafından yapılmış veya önceki sync'te inmiş).
          // Durum, iptal nedeni veya iptal zamanı değişmişse güncelle.
          // DİKKAT: Hub'dan gelen durum 'COMPLETED' olsa dahi, eğer yerel satış
          // iade edilmişse ('REFUNDED' veya 'PARTIALLY_REFUNDED'), Hub durumu ile ezilmemelidir.
          // Ancak Hub'dan gelen durum 'CANCELLED' ise iptal her zaman önceliklidir (BR-POS-08).
          final effectiveStatus = (sale.status == 'CANCELLED')
              ? 'CANCELLED'
              : (existing.status == 'REFUNDED' ||
                      existing.status == 'PARTIALLY_REFUNDED')
                  ? existing.status
                  : sale.status;

          await (db.update(db.localSales)
                ..where((s) => s.id.equals(existing.id)))
              .write(
            LocalSalesCompanion(
              status: Value(effectiveStatus),
              cancelReason: Value(sale.cancelReason),
              cancelledAt: Value(sale.cancelledAt),
            ),
          );
        } else {
          // Başka bir cihazdan gelen yeni satış.
          // Yabancı anahtar (FK) kısıtlamalarını korumak için eksik ürünleri yerel önbelleğe ekle
          for (final item in sale.items) {
            final prod = await (db.select(db.localProducts)
                  ..where((p) => p.id.equals(item.productId)))
                .getSingleOrNull();
            if (prod == null) {
              await db.into(db.localProducts).insertOnConflictUpdate(
                    LocalProductsCompanion(
                      id: Value(item.productId),
                      name: Value(item.productName),
                      price: Value(item.unitPrice),
                      priceVersionId: Value(item.priceVersionId),
                      stock: const Value(0),
                      stockUnit: Value(item.unit),
                      pricingUnit: Value(item.unit),
                      updatedAt: Value(effectiveSyncedAt),
                    ),
                  );
            }
          }

          // local_sales tablosuna ekle
          final initialStatus = (sale.status != 'CANCELLED' &&
                  sale.refunds.isNotEmpty)
              ? (sale.refunds.fold(0, (sum, r) => sum + r.totalRefundAmount) >=
                      sale.totalAmount
                  ? 'REFUNDED'
                  : 'PARTIALLY_REFUNDED')
              : sale.status;

          await db.into(db.localSales).insert(
                LocalSalesCompanion(
                  id: Value(sale.id),
                  deviceId: Value(sale.deviceId),
                  clientSeq: Value(sale.clientSeq),
                  totalAmount: Value(sale.totalAmount),
                  paymentMethod: Value(sale.paymentMethod),
                  status: Value(initialStatus),
                  cancelReason: Value(sale.cancelReason),
                  cancelledAt: Value(sale.cancelledAt),
                  createdAt: Value(sale.createdAt),
                ),
              );

          // local_sale_items tablosuna ekle
          for (final item in sale.items) {
            await db.into(db.localSaleItems).insertOnConflictUpdate(
                  LocalSaleItemsCompanion(
                    id: Value(item.id),
                    saleId: Value(sale.id),
                    productId: Value(item.productId),
                    productNameSnapshot: Value(item.productName),
                    unitSnapshot: Value(item.unit),
                    priceVersionId: Value(item.priceVersionId),
                    unitPrice: Value(item.unitPrice),
                    quantity: Value(item.quantity),
                    totalPrice: Value(item.totalPrice),
                  ),
                );
          }
        }

        // 2. İadeleri (Refunds) atomik olarak işle
        for (final ref in sale.refunds) {
          final existingRef = await (db.select(db.localRefunds)
                ..where((r) =>
                    r.id.equals(ref.id) |
                    (r.deviceId.equals(ref.deviceId) &
                        r.clientSeq.equals(ref.clientSeq))))
              .getSingleOrNull();

          if (existingRef == null) {
            await db.into(db.localRefunds).insert(
                  LocalRefundsCompanion(
                    id: Value(ref.id),
                    saleId: Value(existing?.id ?? ref.saleId),
                    deviceId: Value(ref.deviceId),
                    clientSeq: Value(ref.clientSeq),
                    totalRefundAmount: Value(ref.totalRefundAmount),
                    paymentMethod: Value(ref.paymentMethod),
                    reason: Value(ref.reason),
                    createdAt: Value(ref.createdAt),
                  ),
                );

            for (final ri in ref.items) {
              // Eksik ürün varsa önbelleğe ekle
              final refProd = await (db.select(db.localProducts)
                    ..where((p) => p.id.equals(ri.productId)))
                  .getSingleOrNull();
              if (refProd == null) {
                await db.into(db.localProducts).insertOnConflictUpdate(
                      LocalProductsCompanion(
                        id: Value(ri.productId),
                        name: const Value('İade Edilen Ürün'),
                        price: Value(ri.unitPrice),
                        stock: const Value(0),
                        updatedAt: Value(effectiveSyncedAt),
                      ),
                    );
              }

              // SaleItemId doğrulaması (FK kısıtlaması için)
              String saleItemId = ri.saleItemId ?? '';
              LocalSaleItem? validSaleItem;
              if (saleItemId.isNotEmpty) {
                validSaleItem = await (db.select(db.localSaleItems)
                      ..where((si) => si.id.equals(saleItemId)))
                    .getSingleOrNull();
              }
              if (validSaleItem == null) {
                validSaleItem = await (db.select(db.localSaleItems)
                      ..where((si) =>
                          si.saleId.equals(ref.saleId) &
                          si.productId.equals(ri.productId)))
                    .getSingleOrNull();
                if (validSaleItem != null) {
                  saleItemId = validSaleItem.id;
                } else {
                  final anyItem = await (db.select(db.localSaleItems)
                        ..where((si) => si.saleId.equals(ref.saleId))
                        ..limit(1))
                      .getSingleOrNull();
                  if (anyItem != null) {
                    saleItemId = anyItem.id;
                  }
                }
              }

              if (saleItemId.isNotEmpty) {
                await db.into(db.localRefundItems).insertOnConflictUpdate(
                      LocalRefundItemsCompanion(
                        id: Value(ri.id),
                        refundId: Value(ref.id),
                        saleItemId: Value(saleItemId),
                        productId: Value(ri.productId),
                        quantity: Value(ri.quantity),
                        unitPrice: Value(ri.unitPrice),
                        refundAmount: Value(ri.refundAmount),
                        productCondition: Value(ri.productCondition),
                        createdAt: Value(ref.createdAt),
                      ),
                    );
              }
            }
          }
        }

        // Satış iptal edilmemişse ve iadeleri varsa durumunu otomatik güncelle (REFUNDED veya PARTIALLY_REFUNDED)
        if (sale.status != 'CANCELLED' && sale.refunds.isNotEmpty) {
          final totalRef =
              sale.refunds.fold(0, (sum, r) => sum + r.totalRefundAmount);
          final derivedStatus =
              totalRef >= sale.totalAmount ? 'REFUNDED' : 'PARTIALLY_REFUNDED';
          await (db.update(db.localSales)
                ..where((s) => s.id.equals(existing?.id ?? sale.id)))
              .write(
            LocalSalesCompanion(status: Value(derivedStatus)),
          );
        }
      }

      // İndirilen satışlar sonrası yerel iade durumlarını reconcile et
      await reconcileSaleStatuses();

      // 3. İstemci senkronizasyon durumunu güncelle
      final syncState = await getSyncState(deviceId);
      if (syncState != null) {
        await (db.update(db.clientSyncStates)
              ..where((s) => s.deviceId.equals(deviceId)))
            .write(
          ClientSyncStatesCompanion(
            lastServerSaleSeq: Value(newCursor),
            lastSalesSyncAt: Value(effectiveSyncedAt),
            updatedAt: Value(effectiveSyncedAt),
          ),
        );
      }
    });
  }

  /// Barkod üzerinden ürün arar (SSOT: LocalProductBarcodes tablosu)
  Future<LocalProduct?> getProductByBarcode(String barcode) async {
    final barcodeRow = await (db.select(db.localProductBarcodes)
          ..where((b) => b.barcode.equals(barcode) & b.isActive.equals(true)))
        .getSingleOrNull();

    if (barcodeRow != null) {
      return (db.select(db.localProducts)
            ..where((p) => p.id.equals(barcodeRow.productId)))
          .getSingleOrNull();
    }

    // Doğrudan primary barcode kolonundan yedek arama (denormalize hızlı arama)
    return (db.select(db.localProducts)
          ..where((p) => p.barcode.equals(barcode)))
        .getSingleOrNull();
  }

  /// Bir ürüne ait tüm barkodları döner
  Future<List<LocalProductBarcode>> getBarcodesForProduct(
      String productId) async {
    return (db.select(db.localProductBarcodes)
          ..where(
              (b) => b.productId.equals(productId) & b.isActive.equals(true)))
        .get();
  }

  /// Cihaz için gönderilmeyi bekleyen bir sonraki Outbox işlemini döner (Deterministic FIFO: clientSeq ASC)
  Future<OutboxOperation?> getNextUnsyncedOutboxOperation(
    String deviceId, {
    DateTime? now,
  }) async {
    final effectiveNow = now ?? DateTime.now();
    return (db.select(db.outboxOperations)
          ..where((o) =>
              o.deviceId.equals(deviceId) &
              (o.status.equals('PENDING') | o.status.equals('RETRY')) &
              (o.nextRetryAt.isNull() |
                  o.nextRetryAt.isSmallerOrEqualValue(effectiveNow)))
          ..orderBy([(o) => OrderingTerm.asc(o.clientSeq)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Cihaza ait tüm gönderilmemiş işlemleri döner
  Future<List<OutboxOperation>> getUnsyncedOutboxOperations(
      String deviceId) async {
    return (db.select(db.outboxOperations)
          ..where((o) =>
              o.deviceId.equals(deviceId) &
              (o.status.equals('PENDING') |
                  o.status.equals('RETRY') |
                  o.status.equals('IN_PROGRESS') |
                  o.status.equals('FAILED_PERMANENT')))
          ..orderBy([(o) => OrderingTerm.asc(o.clientSeq)]))
        .get();
  }

  /// Senkronizasyon kuyruğundaki operasyonların durum bazlı özetini döner.
  ///
  /// Tüm tabloyu belleğe yüklemeden doğrudan SQLite üzerinde `GROUP BY status`
  /// ve `COUNT(operation_id)` çalıştırarak yüksek performanslı ve verimli sayım yapar.
  Future<OutboxSummary> getOutboxSummary({String? deviceId}) async {
    final countExp = db.outboxOperations.operationId.count();
    final statusCol = db.outboxOperations.status;

    final query = db.selectOnly(db.outboxOperations)
      ..addColumns([statusCol, countExp])
      ..groupBy([statusCol]);

    if (deviceId != null && deviceId.isNotEmpty) {
      query.where(db.outboxOperations.deviceId.equals(deviceId));
    }

    final rows = await query.get();

    var pending = 0;
    var retry = 0;
    var inProgress = 0;
    var failedPermanent = 0;

    for (final row in rows) {
      final status = row.read(statusCol);
      final count = row.read(countExp) ?? 0;
      switch (status) {
        case 'PENDING':
          pending = count;
          break;
        case 'RETRY':
          retry = count;
          break;
        case 'IN_PROGRESS':
          inProgress = count;
          break;
        case 'FAILED_PERMANENT':
          failedPermanent = count;
          break;
      }
    }

    return OutboxSummary(
      pending: pending,
      retry: retry,
      inProgress: inProgress,
      failedPermanent: failedPermanent,
    );
  }

  /// Outbox operasyonunu IN_PROGRESS olarak işaretler
  Future<void> markOutboxInProgress(String operationId) async {
    await (db.update(db.outboxOperations)
          ..where((o) => o.operationId.equals(operationId)))
        .write(
      const OutboxOperationsCompanion(status: Value('IN_PROGRESS')),
    );
  }

  /// Outbox operasyonunu başarılı ACK ile SYNCED olarak işaretler ve lastSyncedSeq günceller
  Future<void> markOutboxSynced(
    String operationId, {
    required int clientSeq,
    required String deviceId,
    DateTime? acknowledgedAt,
  }) async {
    final ackTime = acknowledgedAt ?? DateTime.now();

    await db.transaction(() async {
      await (db.update(db.outboxOperations)
            ..where((o) => o.operationId.equals(operationId)))
          .write(
        OutboxOperationsCompanion(
          status: const Value('SYNCED'),
          acknowledgedAt: Value(ackTime),
          lastError: const Value(null),
        ),
      );

      final state = await (db.select(db.clientSyncStates)
            ..where((s) => s.deviceId.equals(deviceId)))
          .getSingleOrNull();

      if (state != null && clientSeq > state.lastSyncedSeq) {
        await (db.update(db.clientSyncStates)
              ..where((s) => s.deviceId.equals(deviceId)))
            .write(
          ClientSyncStatesCompanion(
            lastSyncedSeq: Value(clientSeq),
            updatedAt: Value(ackTime),
          ),
        );
      }
    });
  }

  /// Outbox operasyonunu RETRY durumuna çeker ve exponential backoff belirler
  Future<void> markOutboxRetry(
    String operationId, {
    required int attemptCount,
    required Duration backoff,
    required String error,
    DateTime? now,
  }) async {
    final effectiveNow = now ?? DateTime.now();
    final nextRetry = effectiveNow.add(backoff);

    await (db.update(db.outboxOperations)
          ..where((o) => o.operationId.equals(operationId)))
        .write(
      OutboxOperationsCompanion(
        status: const Value('RETRY'),
        attemptCount: Value(attemptCount),
        nextRetryAt: Value(nextRetry),
        lastError: Value(error),
      ),
    );
  }

  /// Outbox operasyonunu kalıcı hata (400 / 409 mismatch) durumunda FAILED_PERMANENT işaretler
  Future<void> markOutboxPermanentFail(
    String operationId, {
    required String error,
  }) async {
    await (db.update(db.outboxOperations)
          ..where((o) => o.operationId.equals(operationId)))
        .write(
      OutboxOperationsCompanion(
        status: const Value('FAILED_PERMANENT'),
        lastError: Value(error),
      ),
    );
  }

  /// S5A-3: Kalıcı hata almış (FAILED_PERMANENT) operasyonları döner (Hata incelemesi için)
  Future<List<OutboxOperation>> getFailedPermanentOperations(
      String deviceId) async {
    return (db.select(db.outboxOperations)
          ..where((o) =>
              o.deviceId.equals(deviceId) & o.status.equals('FAILED_PERMANENT'))
          ..orderBy([(o) => OrderingTerm.asc(o.clientSeq)]))
        .get();
  }

  /// S5A-3: Hata giderildikten sonra FAILED_PERMANENT operasyonu PENDING durumuna geri alır (Kuyruğu tekrar başlatır)
  Future<void> retryFailedPermanentOperation(
    String operationId, {
    bool allowProtocolConflictOverride = false,
  }) async {
    await db.transaction(() async {
      final existing = await (db.select(db.outboxOperations)
            ..where((o) => o.operationId.equals(operationId)))
          .getSingleOrNull();

      if (existing == null) {
        throw StateError('Outbox operasyonu bulunamadı: $operationId');
      }
      if (existing.status != 'FAILED_PERMANENT') {
        throw StateError(
          'Yalnızca FAILED_PERMANENT durumundaki operasyonlar yeniden denenebilir (mevcut durum: ${existing.status}).',
        );
      }

      final lastErr = existing.lastError ?? '';
      if (!allowProtocolConflictOverride &&
          (lastErr.contains('ERR_IDEMPOTENCY_') ||
              lastErr.contains('ERR_CLIENT_SEQ_GAP'))) {
        throw StateError(
          'Protokol veya tekillik (ERR_IDEMPOTENCY / ERR_CLIENT_SEQ_GAP) uyuşmazlığı içeren kalıcı hatalar doğrudan yeniden denenemez; uzlaştırma gerekir: $operationId',
        );
      }

      await (db.update(db.outboxOperations)
            ..where((o) =>
                o.operationId.equals(operationId) &
                o.status.equals('FAILED_PERMANENT')))
          .write(
        const OutboxOperationsCompanion(
          status: Value('PENDING'),
          attemptCount: Value(0),
          nextRetryAt: Value(null),
          lastError: Value(null),
        ),
      );
    });
  }

  /// S5A-3: Kalıcı hatalı (`FAILED_PERMANENT`) operasyonu tek atomik SQLite
  /// transaction içinde doğrular, payload ve SHA-256 hash'i günceller ve
  /// yeniden senkronizasyon için `PENDING` durumuna geçirir.
  Future<void> updateAndRetryFailedOperation(
    String operationId, {
    required Map<String, dynamic> correctedPayload,
  }) async {
    await db.transaction(() async {
      final existing = await (db.select(db.outboxOperations)
            ..where((o) => o.operationId.equals(operationId)))
          .getSingleOrNull();

      if (existing == null) {
        throw StateError('Outbox operasyonu bulunamadı: $operationId');
      }
      if (existing.status != 'FAILED_PERMANENT') {
        throw StateError(
          'Yalnızca FAILED_PERMANENT durumundaki operasyonlar onarılabilir (mevcut durum: ${existing.status}).',
        );
      }
      if (correctedPayload['operation_id'] != existing.operationId) {
        throw ArgumentError(
          'Onarım yükünde operation_id değiştirilemez (beklenen: ${existing.operationId}).',
        );
      }
      if (correctedPayload['client_seq'] != existing.clientSeq) {
        throw ArgumentError(
          'Onarım yükünde client_seq değiştirilemez (beklenen: ${existing.clientSeq}).',
        );
      }

      final isSaleCreate = existing.operationType == 'SALE_CREATE';
      PaymentMethod? parsedPaymentMethod;
      if (isSaleCreate || correctedPayload.containsKey('payment_method')) {
        parsedPaymentMethod =
            PaymentMethod.parse(correctedPayload['payment_method']);
      }

      int? repairedTotalAmount;
      if (isSaleCreate) {
        final rawTotalAmount = correctedPayload['total_amount'];
        final rawItems = correctedPayload['items'];
        if (rawTotalAmount is! int || rawTotalAmount <= 0) {
          throw ArgumentError(
              'Onarım yükünde total_amount pozitif tamsayı olmalıdır.');
        }
        if (rawItems is! List || rawItems.isEmpty) {
          throw ArgumentError(
              'Onarım yükünde en az bir satış kalemi (items) bulunmalıdır.');
        }
        repairedTotalAmount = rawTotalAmount;
      }

      final payloadStr = jsonEncode(correctedPayload);
      final payloadHash = isSaleCreate
          ? computeSaleRequestHash(correctedPayload)
          : sha256.convert(utf8.encode(payloadStr)).toString();

      await (db.update(db.outboxOperations)
            ..where((o) => o.operationId.equals(operationId)))
          .write(
        OutboxOperationsCompanion(
          payload: Value(payloadStr),
          payloadHash: Value(payloadHash),
          status: const Value('PENDING'),
          attemptCount: const Value(0),
          nextRetryAt: const Value(null),
          lastError: const Value(null),
        ),
      );

      if (isSaleCreate &&
          parsedPaymentMethod != null &&
          repairedTotalAmount != null) {
        await _syncRepairedLocalSale(
          deviceId: existing.deviceId,
          clientSeq: existing.clientSeq,
          repairedMethod: parsedPaymentMethod,
          repairedTotalAmount: repairedTotalAmount,
        );
      }
    });
  }

  /// Legacy satışın yerel kaydını aynı transaction içinde kanonik sözleşmeyle
  /// eşitler; tutar veya ödeme ailesi uyuşmazlığında transaction rollback tetikler.
  Future<void> _syncRepairedLocalSale({
    required String deviceId,
    required int clientSeq,
    required PaymentMethod repairedMethod,
    required int repairedTotalAmount,
  }) async {
    final localSale = await (db.select(db.localSales)
          ..where((s) =>
              s.deviceId.equals(deviceId) & s.clientSeq.equals(clientSeq)))
        .getSingleOrNull();
    if (localSale == null) return;

    if (repairedTotalAmount != localSale.totalAmount) {
      throw ArgumentError(
        'Onarım yükündeki total_amount ($repairedTotalAmount) yerel satış tutarıyla (${localSale.totalAmount}) uyuşmuyor.',
      );
    }

    final logicalPrior =
        PaymentMethod.tryParseLegacyReadOnly(localSale.paymentMethod);
    if (logicalPrior != null && logicalPrior != repairedMethod) {
      throw ArgumentError(
        'Satışın ödeme yöntemi (${localSale.paymentMethod}) farklı bir yönteme (${repairedMethod.code}) sessizce dönüştürülemez.',
      );
    }

    if (localSale.paymentMethod != repairedMethod.code) {
      await (db.update(db.localSales)..where((s) => s.id.equals(localSale.id)))
          .write(
              LocalSalesCompanion(paymentMethod: Value(repairedMethod.code)));
    }
  }

  /// Uygulama başladığında kilitli/yarıda kalmış IN_PROGRESS işlemlerini kurtarır (Crash Recovery)
  Future<int> recoverStuckInProgressOperations(String deviceId) async {
    final stuckOps = await (db.select(db.outboxOperations)
          ..where((o) =>
              o.deviceId.equals(deviceId) & o.status.equals('IN_PROGRESS')))
        .get();

    for (final op in stuckOps) {
      final targetStatus = op.attemptCount > 0 ? 'RETRY' : 'PENDING';
      await (db.update(db.outboxOperations)
            ..where((o) => o.operationId.equals(op.operationId)))
          .write(
        OutboxOperationsCompanion(
          status: Value(targetStatus),
          lastError: const Value(
              'Uygulama çökmesi sonrası IN_PROGRESS durumundan kurtarıldı.'),
        ),
      );
    }

    return stuckOps.length;
  }

  // =========================================================================
  // FAZ 1.3.2: SATIŞ GEÇMİŞİ VE FİŞ DETAYLARI SORGULARI
  // =========================================================================

  /// Yerel veritabanındaki iade kayıtlarını (local_refunds) inceleyerek
  /// satışların durumunu (local_sales.status) günceller ve liste ile fiş detayı
  /// arasındaki veri tutarlılığını garanti eder.
  /// İptal edilmiş ('CANCELLED') satışların durumu ASLA değiştirilmez (BR-POS-08).
  Future<void> reconcileSaleStatuses() async {
    final allRefunds = await db.select(db.localRefunds).get();
    if (allRefunds.isEmpty) return;

    final totalRefundedBySaleId = <String, int>{};
    for (final ref in allRefunds) {
      totalRefundedBySaleId[ref.saleId] =
          (totalRefundedBySaleId[ref.saleId] ?? 0) + ref.totalRefundAmount;
    }

    for (final entry in totalRefundedBySaleId.entries) {
      final saleId = entry.key;
      final totalRefunded = entry.value;

      final sale = await (db.select(db.localSales)
            ..where((s) => s.id.equals(saleId)))
          .getSingleOrNull();

      if (sale != null && sale.status != 'CANCELLED') {
        final expectedStatus = totalRefunded >= sale.totalAmount
            ? 'REFUNDED'
            : (totalRefunded > 0 ? 'PARTIALLY_REFUNDED' : 'COMPLETED');

        if (sale.status != expectedStatus) {
          await (db.update(db.localSales)..where((s) => s.id.equals(sale.id)))
              .write(
            LocalSalesCompanion(status: Value(expectedStatus)),
          );
        }
      }
    }
  }

  /// Satış geçmişini filtreler ve sıralar (Sayfalama destekli)
  Future<List<LocalSale>> getSalesHistory({
    DateTime? startDate,
    DateTime? endDate,
    String? paymentMethod,
    String? status,
    String? searchQuery,
    int limit = 50,
    int offset = 0,
  }) async {
    // Liste sorgulanmadan önce iade edilmiş satışların durumunu gerçek verilerle güncelle
    await reconcileSaleStatuses();

    final query = db.select(db.localSales);
    if (startDate != null) {
      query.where((s) => s.createdAt.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query.where((s) => s.createdAt.isSmallerOrEqualValue(endDate));
    }
    if (paymentMethod != null && paymentMethod.isNotEmpty) {
      query.where((s) => s.paymentMethod.equals(paymentMethod));
    }
    if (status != null && status.isNotEmpty) {
      query.where((s) => s.status.equals(status));
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final trimmed = searchQuery.trim();
      query.where(
          (s) => s.id.like('%$trimmed%') | s.deviceId.like('%$trimmed%'));
    }
    query.orderBy([(s) => OrderingTerm.desc(s.createdAt)]);
    query.limit(limit, offset: offset);
    return await query.get();
  }

  /// Tekil bir satışın tüm kalemlerini, iadelerini ve stok hareketlerini döner
  Future<SaleWithDetails?> getSaleDetail(String saleId) async {
    final sale = await (db.select(db.localSales)
          ..where((s) => s.id.equals(saleId)))
        .getSingleOrNull();
    if (sale == null) return null;

    final items = await (db.select(db.localSaleItems)
          ..where((i) => i.saleId.equals(saleId)))
        .get();

    final refunds = await (db.select(db.localRefunds)
          ..where((r) => r.saleId.equals(saleId)))
        .get();
    final refundsWithItems = <RefundWithItems>[];
    for (final ref in refunds) {
      final refItems = await (db.select(db.localRefundItems)
            ..where((ri) => ri.refundId.equals(ref.id)))
          .get();
      refundsWithItems.add(RefundWithItems(refund: ref, items: refItems));
    }

    final stockMovements = await (db.select(db.localStockMovements)
          ..where((sm) => sm.referenceId.equals(saleId)))
        .get();

    return SaleWithDetails(
      sale: sale,
      items: items,
      refunds: refundsWithItems,
      stockMovements: stockMovements,
    );
  }

  Future<DashboardProductSummary> getDashboardProductSummary({
    int criticalStockThresholdMilli = 5000,
    int previewLimit = 8,
  }) async {
    final aggRow = await db.customSelect(
      '''
      SELECT
        COUNT(*) AS active_count,
        COALESCE(SUM(CASE WHEN stock <= ? THEN 1 ELSE 0 END), 0) AS critical_count,
        COALESCE(SUM(CASE WHEN stock < 0 THEN 1 ELSE 0 END), 0) AS negative_count
      FROM local_products
      WHERE is_active = 1;
      ''',
      variables: [Variable.withInt(criticalStockThresholdMilli)],
      readsFrom: {db.localProducts},
    ).getSingle();

    final criticalProducts = await (db.select(db.localProducts)
          ..where((p) =>
              p.isActive.equals(true) &
              p.stock.isSmallerOrEqualValue(criticalStockThresholdMilli))
          ..orderBy([
            (p) => OrderingTerm.asc(p.stock),
            (p) => OrderingTerm.asc(p.name),
          ])
          ..limit(previewLimit))
        .get();

    return DashboardProductSummary(
      activeProductCount: aggRow.read<int>('active_count'),
      criticalStockCount: aggRow.read<int>('critical_count'),
      negativeStockCount: aggRow.read<int>('negative_count'),
      criticalProducts: criticalProducts,
    );
  }

  Future<DashboardSalesSummary> getDashboardSalesSummary({
    required DateTime todayStart,
    int trendDays = 7,
  }) async {
    if (trendDays <= 0) {
      throw ArgumentError('trendDays pozitif olmalıdır: $trendDays');
    }

    await reconcileSaleStatuses();

    final todayLocal =
        DateTime(todayStart.year, todayStart.month, todayStart.day);
    final tomorrowStart =
        DateTime(todayLocal.year, todayLocal.month, todayLocal.day + 1);
    final firstDay = DateTime(
      todayLocal.year,
      todayLocal.month,
      todayLocal.day - (trendDays - 1),
    );

    final todayRow = await db.customSelect(
      '''
      WITH net_sales AS (
        SELECT
          s.payment_method,
          s.created_at,
          CASE
            WHEN s.status IN ('CANCELLED', 'REFUNDED') THEN 0
            WHEN s.total_amount - COALESCE(r.ref_sum, 0) > 0
              THEN s.total_amount - COALESCE(r.ref_sum, 0)
            ELSE 0
          END AS net_cents
        FROM local_sales s
        LEFT JOIN (
          SELECT sale_id, SUM(total_refund_amount) AS ref_sum
          FROM local_refunds
          GROUP BY sale_id
        ) r ON r.sale_id = s.id
        WHERE s.created_at >= ? AND s.created_at < ?
      )
      SELECT
        COALESCE(SUM(net_cents), 0) AS today_total,
        COALESCE(SUM(CASE WHEN net_cents > 0 THEN 1 ELSE 0 END), 0) AS today_count,
        COALESCE(SUM(CASE WHEN net_cents > 0 AND payment_method = 'CASH' THEN net_cents ELSE 0 END), 0) AS today_cash,
        COALESCE(SUM(CASE WHEN net_cents > 0 AND payment_method != 'CASH' THEN net_cents ELSE 0 END), 0) AS today_card
      FROM net_sales;
      ''',
      variables: [
        Variable.withDateTime(todayLocal),
        Variable.withDateTime(tomorrowStart),
      ],
      readsFrom: {db.localSales, db.localRefunds},
    ).getSingle();

    final dailyTotals = <DashboardDailySalesTotal>[];
    for (var i = 0; i < trendDays; i++) {
      final bucketStart =
          DateTime(firstDay.year, firstDay.month, firstDay.day + i);
      final bucketEnd =
          DateTime(firstDay.year, firstDay.month, firstDay.day + i + 1);
      final dayRow = await db.customSelect(
        '''
        WITH net_sales AS (
          SELECT
            CASE
              WHEN s.status IN ('CANCELLED', 'REFUNDED') THEN 0
              WHEN s.total_amount - COALESCE(r.ref_sum, 0) > 0
                THEN s.total_amount - COALESCE(r.ref_sum, 0)
              ELSE 0
            END AS net_cents
          FROM local_sales s
          LEFT JOIN (
            SELECT sale_id, SUM(total_refund_amount) AS ref_sum
            FROM local_refunds
            GROUP BY sale_id
          ) r ON r.sale_id = s.id
          WHERE s.created_at >= ? AND s.created_at < ?
        )
        SELECT
          COALESCE(SUM(net_cents), 0) AS total_cents,
          COALESCE(SUM(CASE WHEN net_cents > 0 THEN 1 ELSE 0 END), 0) AS sale_count
        FROM net_sales;
        ''',
        variables: [
          Variable.withDateTime(bucketStart),
          Variable.withDateTime(bucketEnd),
        ],
        readsFrom: {db.localSales, db.localRefunds},
      ).getSingle();

      dailyTotals.add(DashboardDailySalesTotal(
        date: bucketStart,
        totalCents: dayRow.read<int>('total_cents'),
        count: dayRow.read<int>('sale_count'),
      ));
    }

    return DashboardSalesSummary(
      todaySalesTotalCents: todayRow.read<int>('today_total'),
      todaySalesCount: todayRow.read<int>('today_count'),
      todayCashTotalCents: todayRow.read<int>('today_cash'),
      todayCardTotalCents: todayRow.read<int>('today_card'),
      dailyTotals: dailyTotals,
    );
  }

  /// Verilen satış kimlikleri için toplam iade tutarlarını (kuruş) döner.
  Future<Map<String, int>> getRefundTotalsBySaleIds(
    Iterable<String> saleIds,
  ) async {
    final uniqueIds = saleIds.where((id) => id.isNotEmpty).toSet().toList();
    if (uniqueIds.isEmpty) return const <String, int>{};

    final totals = <String, int>{};
    const chunkSize = 400;
    for (var offset = 0; offset < uniqueIds.length; offset += chunkSize) {
      final chunk = uniqueIds.sublist(
        offset,
        offset + chunkSize > uniqueIds.length
            ? uniqueIds.length
            : offset + chunkSize,
      );
      final rows = await (db.select(db.localRefunds)
            ..where((r) => r.saleId.isIn(chunk)))
          .get();
      for (final row in rows) {
        totals[row.saleId] = (totals[row.saleId] ?? 0) + row.totalRefundAmount;
      }
    }
    return totals;
  }

  // =========================================================================
  // FAZ 1.3.3: TAM SATIŞ İPTALİ (BR-POS-08)
  // =========================================================================

  /// Tam satış iptali:
  /// - Gerekçe zorunludur.
  /// - Mükerrer iptal engellenir.
  /// - Kısmi iade edilmiş kalemler dikkate alınarak kalan satılabilir miktar stoğa iade edilir.
  /// - `LocalStockMovements` tablosuna 'SATIS_IPTALI' eklenir.
  /// - `LocalSales.status = 'CANCELLED'` yapılır.
  /// - `OutboxOperations` tablosuna 'SALE_CANCEL' operasyonu eklenir.
  Future<void> cancelSale({
    required String saleId,
    required String reason,
    required String deviceId,
    DateTime? cancelledAt,
  }) async {
    final trimReason = reason.trim();
    if (trimReason.isEmpty) {
      throw ArgumentError('İptal gerekçesi boş olamaz (BR-POS-08).');
    }
    final effectiveTime = cancelledAt ?? DateTime.now();

    await db.transaction(() async {
      final sale = await (db.select(db.localSales)
            ..where((s) => s.id.equals(saleId)))
          .getSingleOrNull();
      if (sale == null) {
        throw StateError('İptal edilecek satış bulunamadı: $saleId');
      }
      if (sale.status == 'CANCELLED') {
        throw StateError('Bu satış zaten iptal edilmiştir (BR-POS-08).');
      }

      // Kalemleri ve geçmiş iadeleri kontrol et
      final items = await (db.select(db.localSaleItems)
            ..where((i) => i.saleId.equals(saleId)))
          .get();
      final refunds = await (db.select(db.localRefunds)
            ..where((r) => r.saleId.equals(saleId)))
          .get();
      final refundedQtyByItemId = <String, int>{};
      for (final ref in refunds) {
        final refItems = await (db.select(db.localRefundItems)
              ..where((ri) => ri.refundId.equals(ref.id)))
            .get();
        for (final ri in refItems) {
          refundedQtyByItemId[ri.saleItemId] =
              (refundedQtyByItemId[ri.saleItemId] ?? 0) + ri.quantity;
        }
      }

      // Cihaz senkronizasyon sıra numarasını (client_seq) güvenli ve kilitli olarak tahsis et
      final nextSeq =
          await _allocateNextClientSeq(deviceId, occurredAt: effectiveTime);
      final uniqueToken = _nextUniqueToken();
      final operationId =
          'op_cancel_${effectiveTime.microsecondsSinceEpoch}_${nextSeq}_$uniqueToken';

      // Stok iade hareketleri: Daha önce kısmi iade edilmemiş kalan miktar stoğa geri iade edilir
      for (final item in items) {
        final refundedQty = refundedQtyByItemId[item.id] ?? 0;
        final remainingQty = item.quantity - refundedQty;

        if (remainingQty > 0) {
          final product = await (db.select(db.localProducts)
                ..where((p) => p.id.equals(item.productId)))
              .getSingleOrNull();
          if (product != null) {
            final num = product.conversionFactorNumerator;
            final den = product.conversionFactorDenominator;
            final prodMilli = remainingQty * num;
            final stockDelta = prodMilli ~/ den;

            final movementId =
                'csm_cancel_${saleId}_${item.productId}_$uniqueToken';
            await db.into(db.localStockMovements).insert(
                  LocalStockMovementsCompanion(
                    id: Value(movementId),
                    productId: Value(item.productId),
                    quantity: Value(stockDelta), // Pozitif stok dönüşü
                    unit: Value(product.stockUnit),
                    movementType: const Value('SATIS_IPTALI'),
                    referenceId: Value(saleId),
                    createdAt: Value(effectiveTime),
                  ),
                );

            final updatedStock = product.stock + stockDelta;
            await (db.update(db.localProducts)
                  ..where((p) => p.id.equals(item.productId)))
                .write(
              LocalProductsCompanion(
                stock: Value(updatedStock),
                updatedAt: Value(effectiveTime),
              ),
            );
          }
        }
      }

      // Satış durumunu CANCELLED olarak güncelle
      await (db.update(db.localSales)..where((s) => s.id.equals(saleId))).write(
        LocalSalesCompanion(
          status: const Value('CANCELLED'),
          cancelReason: Value(trimReason),
          cancelledAt: Value(effectiveTime),
        ),
      );

      // Outbox kaydı ekle (SALE_CANCEL)
      final outboxPayload = {
        'operation_id': operationId,
        'operation_type': 'SALE_CANCEL',
        'client_seq': nextSeq,
        'target_client_seq': sale.clientSeq,
        'sale_id': saleId,
        'device_id': deviceId,
        'reason': trimReason,
        'cancelled_at': effectiveTime.toIso8601String(),
      };
      final payloadJsonStr = jsonEncode(outboxPayload);
      final payloadHash = computeSaleRequestHash(outboxPayload);

      await db.into(db.outboxOperations).insert(
            OutboxOperationsCompanion(
              operationId: Value(operationId),
              deviceId: Value(deviceId),
              clientSeq: Value(nextSeq),
              operationType: const Value('SALE_CANCEL'),
              payload: Value(payloadJsonStr),
              payloadHash: Value(payloadHash),
              occurredAt: Value(effectiveTime),
              status: const Value('PENDING'),
              attemptCount: const Value(0),
              createdAt: Value(effectiveTime),
            ),
          );
    });
  }

  // =========================================================================
  // FAZ 1.3.4: KISMİ İADE (BR-POS-09, BR-POS-10)
  // =========================================================================

  /// Kısmi iade işlemi:
  /// - Kalem ve miktar bazında iade yapılmasını sağlar.
  /// - İade miktarı, orijinal satış miktarı eksi önceki iadeleri aşamaz.
  /// - Kuruş Half-Up yuvarlama ile iade tutarı hesaplanır.
  /// - 'SELLABLE' ise MUSTERI_IADESI ve stok artar; 'DAMAGED' ise FIRE_KAYIP ve stok artmaz.
  /// - Tüm kalemler iade edilirse satış durumu 'REFUNDED' olur.
  /// - Outbox'a 'SALE_REFUND' operasyonu yazılır.
  Future<String> refundSale({
    required String saleId,
    required List<RefundItemInput> items,
    required String reason,
    required String deviceId,
    DateTime? createdAt,
  }) async {
    final trimReason = reason.trim();
    if (trimReason.isEmpty) {
      throw ArgumentError('İade gerekçesi boş olamaz (BR-POS-09).');
    }
    if (items.isEmpty) {
      throw ArgumentError('En az bir iade kalemi belirtilmelidir.');
    }
    final effectiveTime = createdAt ?? DateTime.now();

    return await db.transaction(() async {
      final sale = await (db.select(db.localSales)
            ..where((s) => s.id.equals(saleId)))
          .getSingleOrNull();
      if (sale == null) {
        throw StateError('İade yapılacak satış bulunamadı: $saleId');
      }
      if (sale.status == 'CANCELLED') {
        throw StateError(
            'İptal edilmiş bir satış üzerinden iade yapılamaz (BR-POS-08, BR-POS-09).');
      }

      // Mevcut iadeleri topla
      final existingRefunds = await (db.select(db.localRefunds)
            ..where((r) => r.saleId.equals(saleId)))
          .get();
      final refundedQtyByItemId = <String, int>{};
      for (final ref in existingRefunds) {
        final refItems = await (db.select(db.localRefundItems)
              ..where((ri) => ri.refundId.equals(ref.id)))
            .get();
        for (final ri in refItems) {
          refundedQtyByItemId[ri.saleItemId] =
              (refundedQtyByItemId[ri.saleItemId] ?? 0) + ri.quantity;
        }
      }

      // Cihaz senkronizasyon sıra numarasını (client_seq) güvenli ve kilitli olarak tahsis et
      final nextSeq =
          await _allocateNextClientSeq(deviceId, occurredAt: effectiveTime);
      final uniqueToken = _nextUniqueToken();
      final refundId =
          'ref_${effectiveTime.microsecondsSinceEpoch}_${nextSeq}_$uniqueToken';
      final operationId =
          'op_refund_${effectiveTime.microsecondsSinceEpoch}_${nextSeq}_$uniqueToken';

      var totalRefundAmount = 0;
      final refundItemCompanions = <LocalRefundItemsCompanion>[];
      final refundPayloadItems = <Map<String, dynamic>>[];

      var itemIndex = 0;
      for (final itemInput in items) {
        final currentItemIndex = itemIndex++;
        if (itemInput.quantity <= 0) {
          throw ArgumentError(
              'İade miktarı sıfırdan büyük olmalıdır: ${itemInput.saleItemId}');
        }

        final saleItem = await (db.select(db.localSaleItems)
              ..where((i) => i.id.equals(itemInput.saleItemId)))
            .getSingleOrNull();
        if (saleItem == null || saleItem.saleId != saleId) {
          throw ArgumentError('Geçersiz satış kalemi: ${itemInput.saleItemId}');
        }

        final alreadyRefunded = refundedQtyByItemId[saleItem.id] ?? 0;
        final maxReturnable = saleItem.quantity - alreadyRefunded;
        if (itemInput.quantity > maxReturnable) {
          throw ArgumentError(
            'İade miktarı (${itemInput.quantity / 1000}) kalan iade edilebilir miktarı (${maxReturnable / 1000}) aşıyor: ${saleItem.productNameSnapshot}',
          );
        }

        // Half-Up kuruş hesabı: ((unitPrice * quantity) + 500) ~/ 1000
        final itemRefundAmount = ((saleItem.unitPrice * itemInput.quantity) +
                (quantityScale ~/ 2)) ~/
            quantityScale;
        totalRefundAmount += itemRefundAmount;

        final refundItemId =
            'refitem_${refundId}_${saleItem.id}_$currentItemIndex';
        final condition =
            itemInput.productCondition == 'DAMAGED' ? 'DAMAGED' : 'SELLABLE';

        refundItemCompanions.add(
          LocalRefundItemsCompanion(
            id: Value(refundItemId),
            refundId: Value(refundId),
            saleItemId: Value(saleItem.id),
            productId: Value(saleItem.productId),
            quantity: Value(itemInput.quantity),
            unitPrice: Value(saleItem.unitPrice),
            refundAmount: Value(itemRefundAmount),
            productCondition: Value(condition),
            createdAt: Value(effectiveTime),
          ),
        );

        refundPayloadItems.add({
          'sale_item_id': saleItem.id,
          'product_id': saleItem.productId,
          'quantity': itemInput.quantity,
          'unit_price': saleItem.unitPrice,
          'refund_amount': itemRefundAmount,
          'product_condition': condition,
        });

        // Ürün stok ve stok hareketi:
        final product = await (db.select(db.localProducts)
              ..where((p) => p.id.equals(saleItem.productId)))
            .getSingleOrNull();
        if (product != null) {
          final num = product.conversionFactorNumerator;
          final den = product.conversionFactorDenominator;
          final prodMilli = itemInput.quantity * num;
          final stockDelta = prodMilli ~/ den;

          if (condition == 'SELLABLE') {
            // Tekrar satılabilir: MUSTERI_IADESI ve stok artar
            final smId =
                'csm_ref_${refundId}_${saleItem.productId}_$uniqueToken';
            await db.into(db.localStockMovements).insert(
                  LocalStockMovementsCompanion(
                    id: Value(smId),
                    productId: Value(saleItem.productId),
                    quantity: Value(stockDelta),
                    unit: Value(product.stockUnit),
                    movementType: const Value('MUSTERI_IADESI'),
                    referenceId: Value(refundId),
                    createdAt: Value(effectiveTime),
                  ),
                );

            final updatedStock = product.stock + stockDelta;
            await (db.update(db.localProducts)
                  ..where((p) => p.id.equals(saleItem.productId)))
                .write(
              LocalProductsCompanion(
                stock: Value(updatedStock),
                updatedAt: Value(effectiveTime),
              ),
            );
          } else {
            // Hasarlı/Bozuk: FIRE_KAYIP ve normal satılabilir stok ARTMAZ (BR-POS-10)
            final smId =
                'csm_fire_${refundId}_${saleItem.productId}_$uniqueToken';
            await db.into(db.localStockMovements).insert(
                  LocalStockMovementsCompanion(
                    id: Value(smId),
                    productId: Value(saleItem.productId),
                    quantity: Value(stockDelta),
                    unit: Value(product.stockUnit),
                    movementType: const Value('FIRE_KAYIP'),
                    referenceId: Value(refundId),
                    createdAt: Value(effectiveTime),
                  ),
                );
          }
        }

        // Güncel iade miktarını hafızada güncelle
        refundedQtyByItemId[saleItem.id] = alreadyRefunded + itemInput.quantity;
      }

      // LocalRefunds tablosuna ekle
      await db.into(db.localRefunds).insert(
            LocalRefundsCompanion(
              id: Value(refundId),
              saleId: Value(saleId),
              deviceId: Value(deviceId),
              clientSeq: Value(nextSeq),
              totalRefundAmount: Value(totalRefundAmount),
              paymentMethod: Value(sale
                  .paymentMethod), // Orijinal ödeme yöntemi ile iade (BR-POS-09)
              reason: Value(trimReason),
              createdAt: Value(effectiveTime),
            ),
          );

      // LocalRefundItems kayıtlarını ekle
      for (final companion in refundItemCompanions) {
        await db.into(db.localRefundItems).insert(companion);
      }

      // Tüm kalemler %100 iade edilmiş mi kontrol et
      final allSaleItems = await (db.select(db.localSaleItems)
            ..where((i) => i.saleId.equals(saleId)))
          .get();
      final allFullyRefunded = allSaleItems.every((item) {
        final totalRef = refundedQtyByItemId[item.id] ?? 0;
        return totalRef >= item.quantity;
      });

      if (allFullyRefunded) {
        await (db.update(db.localSales)..where((s) => s.id.equals(saleId)))
            .write(
          const LocalSalesCompanion(status: Value('REFUNDED')),
        );
      } else {
        await (db.update(db.localSales)..where((s) => s.id.equals(saleId)))
            .write(
          const LocalSalesCompanion(status: Value('PARTIALLY_REFUNDED')),
        );
      }

      // Outbox kaydı ekle (SALE_REFUND)
      final outboxPayload = {
        'operation_id': operationId,
        'operation_type': 'SALE_REFUND',
        'client_seq': nextSeq,
        'target_client_seq': sale.clientSeq,
        'refund_id': refundId,
        'sale_id': saleId,
        'device_id': deviceId,
        'total_refund_amount': totalRefundAmount,
        'payment_method': sale.paymentMethod,
        'reason': trimReason,
        'items': refundPayloadItems,
        'created_at': effectiveTime.toIso8601String(),
      };
      final payloadJsonStr = jsonEncode(outboxPayload);
      final payloadHash = computeSaleRequestHash(outboxPayload);

      await db.into(db.outboxOperations).insert(
            OutboxOperationsCompanion(
              operationId: Value(operationId),
              deviceId: Value(deviceId),
              clientSeq: Value(nextSeq),
              operationType: const Value('SALE_REFUND'),
              payload: Value(payloadJsonStr),
              payloadHash: Value(payloadHash),
              occurredAt: Value(effectiveTime),
              status: const Value('PENDING'),
              attemptCount: const Value(0),
              createdAt: Value(effectiveTime),
            ),
          );

      return refundId;
    });
  }

  // =========================================================================
  // FAZ 1.4: ÜRÜN VE KATEGORİ YÖNETİMİ (BR-PROD-01..16)
  // =========================================================================

  // --- Kategori İşlemleri ---

  Future<List<LocalCategory>> getCategories(
      {bool includeInactive = false}) async {
    final query = db.select(db.localCategories);
    if (!includeInactive) {
      query.where((c) => c.isActive.equals(true));
    }
    query.orderBy([(c) => OrderingTerm.asc(c.name)]);
    return await query.get();
  }

  Future<LocalCategory?> getCategoryById(String id) async {
    return (db.select(db.localCategories)..where((c) => c.id.equals(id)))
        .getSingleOrNull();
  }

  Future<LocalCategory> createCategory({
    required String name,
    String? parentId,
    String? deviceId,
  }) async {
    final trimName = name.trim();
    if (trimName.isEmpty) {
      throw ArgumentError('Kategori adı boş olamaz.');
    }
    final cleanParentId =
        (parentId != null && parentId.trim().isNotEmpty) ? parentId.trim() : null;
    final now = DateTime.now();
    final catId = 'cat_${now.microsecondsSinceEpoch}_${_nextUniqueToken()}';

    return db.transaction(() async {
      final category = LocalCategoriesCompanion(
        id: Value(catId),
        name: Value(trimName),
        parentId: Value(cleanParentId),
        isActive: const Value(true),
        createdAt: Value(now),
        updatedAt: Value(now),
      );

      await db.into(db.localCategories).insert(category);
      final saved = (await getCategoryById(catId))!;

      final cleanDeviceId = deviceId?.trim();
      if (cleanDeviceId != null && cleanDeviceId.isNotEmpty) {
        await _enqueueCategoryUpsertOutbox(
          category: saved,
          deviceId: cleanDeviceId,
          occurredAt: now,
        );
      }
      return saved;
    });
  }

  Future<void> updateCategory({
    required String id,
    required String name,
    String? parentId,
    bool? isActive,
    String? deviceId,
  }) async {
    final trimName = name.trim();
    if (trimName.isEmpty) {
      throw ArgumentError('Kategori adı boş olamaz.');
    }
    final cleanParentId =
        (parentId != null && parentId.trim().isNotEmpty) ? parentId.trim() : null;
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(db.localCategories)..where((c) => c.id.equals(id)))
          .write(
        LocalCategoriesCompanion(
          name: Value(trimName),
          parentId: Value(cleanParentId),
          isActive: isActive != null ? Value(isActive) : const Value.absent(),
          updatedAt: Value(now),
        ),
      );

      final cleanDeviceId = deviceId?.trim();
      if (cleanDeviceId != null && cleanDeviceId.isNotEmpty) {
        final updated = await getCategoryById(id);
        if (updated != null) {
          await _enqueueCategoryUpsertOutbox(
            category: updated,
            deviceId: cleanDeviceId,
            occurredAt: now,
          );
        }
      }
    });
  }

  Future<void> deactivateCategory(String id, {String? deviceId}) async {
    // BR-PROD-14: Kategoriler fiziksel silinmez, pasife alınır
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(db.localCategories)..where((c) => c.id.equals(id)))
          .write(
        LocalCategoriesCompanion(
          isActive: const Value(false),
          updatedAt: Value(now),
        ),
      );

      final cleanDeviceId = deviceId?.trim();
      if (cleanDeviceId != null && cleanDeviceId.isNotEmpty) {
        final updated = await getCategoryById(id);
        if (updated != null) {
          await _enqueueCategoryUpsertOutbox(
            category: updated,
            deviceId: cleanDeviceId,
            occurredAt: now,
          );
        }
      }
    });
  }

  Future<void> _enqueueCategoryUpsertOutbox({
    required LocalCategory category,
    required String deviceId,
    required DateTime occurredAt,
  }) async {
    final nextSeq =
        await _allocateNextClientSeq(deviceId, occurredAt: occurredAt);
    final uniqueToken = _nextUniqueToken();
    final operationId =
        'op_cat_${category.id}_${occurredAt.microsecondsSinceEpoch}_${nextSeq}_$uniqueToken';

    final outboxPayload = {
      'client_seq': nextSeq,
      'operation_id': operationId,
      'operation_type': 'CATEGORY_UPSERT',
      'category': {
        'id': category.id,
        'name': category.name,
        'parent_id': category.parentId,
        'is_active': category.isActive,
      },
    };

    final payloadStr = jsonEncode(outboxPayload);
    final payloadHash = sha256.convert(utf8.encode(payloadStr)).toString();

    await db.into(db.outboxOperations).insert(
          OutboxOperationsCompanion(
            operationId: Value(operationId),
            deviceId: Value(deviceId),
            clientSeq: Value(nextSeq),
            operationType: const Value('CATEGORY_UPSERT'),
            payload: Value(payloadStr),
            payloadHash: Value(payloadHash),
            occurredAt: Value(occurredAt),
            status: const Value('PENDING'),
            attemptCount: const Value(0),
            createdAt: Value(occurredAt),
          ),
        );
  }

  // --- Ürün İşlemleri ---

  Future<List<LocalProduct>> getProducts({
    String? searchQuery,
    String? categoryId,
    bool? isActive,
    int limit = 100,
    int offset = 0,
  }) async {
    final query = db.select(db.localProducts);
    if (isActive != null) {
      query.where((p) => p.isActive.equals(isActive));
    }
    if (categoryId != null && categoryId.isNotEmpty) {
      query.where((p) => p.categoryId.equals(categoryId));
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final trimmed = searchQuery.trim();
      query.where((p) =>
          p.name.like('%$trimmed%') |
          p.barcode.like('%$trimmed%') |
          p.id.like('%$trimmed%'));
    }
    query.orderBy([(p) => OrderingTerm.asc(p.name)]);
    query.limit(limit, offset: offset);
    return await query.get();
  }

  Future<LocalProduct?> getProductById(String id) async {
    return (db.select(db.localProducts)..where((p) => p.id.equals(id)))
        .getSingleOrNull();
  }

  Future<LocalProduct> createProduct({
    required String name,
    required int price, // Kuruş bazlı (> 0)
    String? barcode,
    String? categoryId,
    int initialStock = 0, // Milli-birim (1000 = 1 adet)
    String stockUnit = 'adet',
    String pricingUnit = 'adet',
    int conversionFactorNumerator = 1,
    int conversionFactorDenominator = 1,
    int vatRate = 20,
    int?
        initialPurchasePrice, // Kuruş, stok birimi başına (BASLANGIC_STOK hareketine yazılır)
    String? deviceId,
  }) async {
    final trimName = name.trim();
    if (trimName.isEmpty) {
      throw ArgumentError('Ürün adı boş olamaz (BR-PROD-01).');
    }
    if (initialPurchasePrice != null &&
        (initialPurchasePrice < 0 || initialPurchasePrice > _maxAmountCents)) {
      throw ArgumentError('Alış fiyatı geçersiz: $initialPurchasePrice');
    }
    if (price <= 0) {
      throw ArgumentError(
          'Satış fiyatı sıfırdan büyük olmalıdır (BR-PROD-01).');
    }
    if (vatRate < 0) {
      throw ArgumentError('KDV oranı negatif olamaz.');
    }

    final now = DateTime.now();
    final uniqueToken = _nextUniqueToken();
    final prodId = 'prod_${now.microsecondsSinceEpoch}_$uniqueToken';
    final priceVersionId = 'pv_${now.microsecondsSinceEpoch}_$uniqueToken';

    return await db.transaction(() async {
      // Barkod kontrolü
      if (barcode != null && barcode.trim().isNotEmpty) {
        final trimBarcode = barcode.trim();
        final existingBarcode = await (db.select(db.localProductBarcodes)
              ..where((b) => b.barcode.equals(trimBarcode)))
            .getSingleOrNull();
        if (existingBarcode != null) {
          throw ArgumentError(
              'Bu barkod zaten başka bir ürüne kayıtlıdır: $trimBarcode (BR-PROD-02)');
        }
        final existingPrimary = await (db.select(db.localProducts)
              ..where((p) => p.barcode.equals(trimBarcode)))
            .getSingleOrNull();
        if (existingPrimary != null) {
          throw ArgumentError(
              'Bu barkod zaten başka bir ürüne kayıtlıdır: $trimBarcode (BR-PROD-02)');
        }
      }

      final companion = LocalProductsCompanion(
        id: Value(prodId),
        barcode: Value(barcode?.trim()),
        name: Value(trimName),
        categoryId: Value(categoryId),
        price: Value(price),
        priceVersionId: Value(priceVersionId),
        stock: Value(initialStock),
        stockUnit: Value(stockUnit),
        pricingUnit: Value(pricingUnit),
        conversionFactorNumerator: Value(conversionFactorNumerator),
        conversionFactorDenominator: Value(conversionFactorDenominator),
        vatRate: Value(vatRate),
        isActive: const Value(true),
        updatedAt: Value(now),
      );

      await db.into(db.localProducts).insert(companion);

      if (barcode != null && barcode.trim().isNotEmpty) {
        final bcId = 'bc_${prodId}_$uniqueToken';
        await db.into(db.localProductBarcodes).insert(
              LocalProductBarcodesCompanion(
                id: Value(bcId),
                productId: Value(prodId),
                barcode: Value(barcode.trim()),
                isPrimary: const Value(true),
                isActive: const Value(true),
                createdAt: Value(now),
              ),
            );
      }

      // Fiyat geçmişi kaydı (BR-PROD-13)
      final priceHistId = 'ph_${prodId}_$uniqueToken';
      await db.into(db.localPriceHistory).insert(
            LocalPriceHistoryCompanion(
              id: Value(priceHistId),
              productId: Value(prodId),
              oldPrice: const Value(0),
              newPrice: Value(price),
              priceVersionId: Value(priceVersionId),
              source: const Value('MANUAL_UI'),
              reason: const Value('İlk ürün oluşturma'),
              changedAt: Value(now),
            ),
          );

      // Başlangıç stoğu hareketi
      if (initialStock != 0) {
        final smId = 'csm_init_${prodId}_$uniqueToken';
        await db.into(db.localStockMovements).insert(
              LocalStockMovementsCompanion(
                id: Value(smId),
                productId: Value(prodId),
                quantity: Value(initialStock),
                unit: Value(stockUnit),
                movementType: const Value('BASLANGIC_STOK'),
                referenceId: Value(prodId),
                purchasePrice: Value(initialPurchasePrice),
                createdAt: Value(now),
              ),
            );
      }

      final savedProduct = (await getProductById(prodId))!;

      // Outbox kaydı: PRODUCT_UPSERT
      if (deviceId != null && deviceId.isNotEmpty) {
        final barcodeList = barcode != null && barcode.trim().isNotEmpty
            ? [barcode.trim()]
            : <String>[];
        await _enqueueProductUpsertOutbox(
          product: savedProduct,
          barcodes: barcodeList,
          deviceId: deviceId,
          occurredAt: now,
        );
      }

      return savedProduct;
    });
  }

  Future<LocalProduct> updateProduct({
    required String id,
    String? name,
    int? price, // Kuruş (> 0)
    String? categoryId,
    String? barcode,
    bool clearBarcode = false,
    String? stockUnit,
    String? pricingUnit,
    int? conversionFactorNumerator,
    int? conversionFactorDenominator,
    int? vatRate,
    bool? isActive,
    String? priceChangeReason,
    String? deviceId,
  }) async {
    final now = DateTime.now();

    return await db.transaction(() async {
      final current = await getProductById(id);
      if (current == null) {
        throw StateError('Güncellenecek ürün bulunamadı: $id');
      }

      var newPriceVersionId = current.priceVersionId;
      final priceChanged = price != null && price != current.price;

      if (priceChanged) {
        if (price <= 0) {
          throw ArgumentError(
              'Satış fiyatı sıfırdan büyük olmalıdır (BR-PROD-01).');
        }
        final uniqueToken = _nextUniqueToken();
        newPriceVersionId = 'pv_${now.microsecondsSinceEpoch}_$uniqueToken';

        // BR-PROD-13: Fiyat geçmişine kaydet
        final priceHistId = 'ph_${id}_$uniqueToken';
        await db.into(db.localPriceHistory).insert(
              LocalPriceHistoryCompanion(
                id: Value(priceHistId),
                productId: Value(id),
                oldPrice: Value(current.price),
                newPrice: Value(price),
                priceVersionId: Value(newPriceVersionId),
                source: const Value('MANUAL_UI'),
                reason:
                    Value(priceChangeReason ?? 'Kullanıcı fiyat güncellemesi'),
                changedAt: Value(now),
              ),
            );
      }

      Value<String?> resolvedBarcodeColumn = const Value.absent();
      final trimBarcode = barcode?.trim() ?? '';

      if (clearBarcode && trimBarcode.isEmpty) {
        // Birincil barkod kullanıcı tarafından temizlendi: tarihçeyi koruyarak pasife al,
        // varsa aktif ilk ikincil barkodu birincil yap, yoksa null bırak.
        await (db.update(db.localProductBarcodes)
              ..where((b) => b.productId.equals(id) & b.isPrimary.equals(true)))
            .write(const LocalProductBarcodesCompanion(
          isActive: Value(false),
          isPrimary: Value(false),
        ));
        final remaining = await getBarcodesForProduct(id);
        if (remaining.isNotEmpty) {
          final promoted = remaining.first;
          await (db.update(db.localProductBarcodes)
                ..where((b) => b.id.equals(promoted.id)))
              .write(
                  const LocalProductBarcodesCompanion(isPrimary: Value(true)));
          resolvedBarcodeColumn = Value(promoted.barcode);
        } else {
          resolvedBarcodeColumn = const Value(null);
        }
      } else if (trimBarcode.isNotEmpty &&
          trimBarcode != (current.barcode ?? '')) {
        final existing = await (db.select(db.localProductBarcodes)
              ..where((b) =>
                  b.barcode.equals(trimBarcode) & b.productId.equals(id).not()))
            .getSingleOrNull();
        if (existing != null) {
          throw ArgumentError(
              'Bu barkod zaten başka bir ürüne kayıtlıdır: $trimBarcode (BR-PROD-02)');
        }
        final otherPrimary = await (db.select(db.localProducts)
              ..where(
                  (p) => p.barcode.equals(trimBarcode) & p.id.equals(id).not()))
            .getSingleOrNull();
        if (otherPrimary != null) {
          throw ArgumentError(
              'Bu barkod zaten başka bir ürüne kayıtlıdır: $trimBarcode (BR-PROD-02)');
        }

        // Önceki birincil barkodu tarihçeyi koruyarak pasife al (ikincil barkodlar aktif kalır)
        final priorPrimary = current.barcode?.trim();
        await (db.update(db.localProductBarcodes)
              ..where((b) =>
                  b.productId.equals(id) &
                  b.barcode.equals(trimBarcode).not() &
                  (priorPrimary != null && priorPrimary.isNotEmpty
                      ? (b.isPrimary.equals(true) |
                          b.barcode.equals(priorPrimary))
                      : b.isPrimary.equals(true))))
            .write(
          const LocalProductBarcodesCompanion(
            isActive: Value(false),
            isPrimary: Value(false),
          ),
        );

        final currentBarcode = await (db.select(db.localProductBarcodes)
              ..where((b) =>
                  b.productId.equals(id) & b.barcode.equals(trimBarcode)))
            .getSingleOrNull();

        if (currentBarcode != null) {
          // Zaten bu ürüne ait alternatif/eski barkod, primary yap
          await (db.update(db.localProductBarcodes)
                ..where((b) =>
                    b.productId.equals(id) &
                    b.id.equals(currentBarcode.id).not()))
              .write(
            const LocalProductBarcodesCompanion(isPrimary: Value(false)),
          );
          await (db.update(db.localProductBarcodes)
                ..where((b) => b.id.equals(currentBarcode.id)))
              .write(
            const LocalProductBarcodesCompanion(
                isPrimary: Value(true), isActive: Value(true)),
          );
        } else {
          // Yeni birincil barkod ekle
          await (db.update(db.localProductBarcodes)
                ..where((b) => b.productId.equals(id)))
              .write(
            const LocalProductBarcodesCompanion(isPrimary: Value(false)),
          );
          final uniqueToken = _nextUniqueToken();
          await db.into(db.localProductBarcodes).insert(
                LocalProductBarcodesCompanion(
                  id: Value('bc_${id}_$uniqueToken'),
                  productId: Value(id),
                  barcode: Value(trimBarcode),
                  isPrimary: const Value(true),
                  isActive: const Value(true),
                  createdAt: Value(now),
                ),
              );
        }
        resolvedBarcodeColumn = Value(trimBarcode);
      } else if (barcode != null && trimBarcode.isNotEmpty) {
        resolvedBarcodeColumn = Value(trimBarcode);
      }

      await (db.update(db.localProducts)..where((p) => p.id.equals(id))).write(
        LocalProductsCompanion(
          name: name != null && name.trim().isNotEmpty
              ? Value(name.trim())
              : const Value.absent(),
          price: price != null ? Value(price) : const Value.absent(),
          priceVersionId: Value(newPriceVersionId),
          categoryId:
              categoryId != null ? Value(categoryId) : const Value.absent(),
          barcode: resolvedBarcodeColumn,
          stockUnit:
              stockUnit != null ? Value(stockUnit) : const Value.absent(),
          pricingUnit:
              pricingUnit != null ? Value(pricingUnit) : const Value.absent(),
          conversionFactorNumerator: conversionFactorNumerator != null
              ? Value(conversionFactorNumerator)
              : const Value.absent(),
          conversionFactorDenominator: conversionFactorDenominator != null
              ? Value(conversionFactorDenominator)
              : const Value.absent(),
          vatRate: vatRate != null ? Value(vatRate) : const Value.absent(),
          isActive: isActive != null ? Value(isActive) : const Value.absent(),
          updatedAt: Value(now),
        ),
      );

      final updatedProduct = (await getProductById(id))!;

      // Outbox kaydı: PRODUCT_UPSERT (kalıcı hata durumunda yerinde onarım)
      if (deviceId != null && deviceId.isNotEmpty) {
        final barcodes = await getBarcodesForProduct(id);
        final barcodeList = <String>[
          if (updatedProduct.barcode != null &&
              updatedProduct.barcode!.trim().isNotEmpty)
            updatedProduct.barcode!.trim(),
        ];
        for (final bc in barcodes) {
          if (!barcodeList.contains(bc.barcode)) {
            barcodeList.add(bc.barcode);
          }
        }
        await _upsertOrRepairProductOutbox(
          product: updatedProduct,
          barcodes: barcodeList,
          deviceId: deviceId,
          occurredAt: now,
        );
      }

      return updatedProduct;
    });
  }

  Future<void> deactivateProduct(String id, {String? deviceId}) async {
    // BR-PROD-03: Soft delete
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(db.localProducts)..where((p) => p.id.equals(id))).write(
        LocalProductsCompanion(
          isActive: const Value(false),
          updatedAt: Value(now),
        ),
      );

      final product = await getProductById(id);
      if (product != null && deviceId != null && deviceId.isNotEmpty) {
        final barcodes = await getBarcodesForProduct(id);
        final barcodeList = barcodes.map((b) => b.barcode).toList();
        if (product.barcode != null && !barcodeList.contains(product.barcode)) {
          barcodeList.add(product.barcode!);
        }
        await _upsertOrRepairProductOutbox(
          product: product,
          barcodes: barcodeList,
          deviceId: deviceId,
          occurredAt: now,
        );
      }
    });
  }

  /// Kalıcı hata (`FAILED_PERMANENT`) almış veya bekleyen ürün `PRODUCT_UPSERT`
  /// kaydı varsa mevcut `operation_id` ve `client_seq` değerini koruyarak
  /// güncellenmiş ürün snapshot'ı ile FIFO kuyruğunu yerinde onarır; aksi halde yeni
  /// Outbox kaydı ekler.
  Future<void> _upsertOrRepairProductOutbox({
    required LocalProduct product,
    required List<String> barcodes,
    required String deviceId,
    required DateTime occurredAt,
  }) async {
    final cleanDeviceId = deviceId.trim();
    if (cleanDeviceId.isEmpty) return;

    final unsyncedForDevice = await (db.select(db.outboxOperations)
          ..where((o) =>
              o.deviceId.equals(cleanDeviceId) &
              o.operationType.equals('PRODUCT_UPSERT') &
              o.status.isIn(_unsyncedOutboxStatuses))
          ..orderBy([(o) => OrderingTerm.asc(o.clientSeq)]))
        .get();

    final matchingOps = unsyncedForDevice
        .where((o) => _productIdOfUpsertPayload(o.payload) == product.id)
        .toList();

    bool isNonRepairableProtocolError(OutboxOperation op) {
      final err = op.lastError ?? '';
      return err.contains('ERR_IDEMPOTENCY_') ||
          err.contains('ERR_CLIENT_SEQ_GAP');
    }

    OutboxOperation? firstRepairableFailed;
    for (final op in matchingOps) {
      if (op.status == 'FAILED_PERMANENT' &&
          !isNonRepairableProtocolError(op)) {
        firstRepairableFailed = op;
        break;
      }
    }

    if (firstRepairableFailed != null) {
      final effectiveBarcode =
          product.barcode ?? (barcodes.isNotEmpty ? barcodes.first : null);
      final maxUnsyncedSaleSeqForProduct = await _maxUnsyncedSaleSeqForProduct(
        deviceId: cleanDeviceId,
        productId: product.id,
      );

      bool isRepairableOp(OutboxOperation op) {
        if (op.clientSeq < firstRepairableFailed!.clientSeq) return false;
        if (op.status == 'IN_PROGRESS') return false;
        return !isNonRepairableProtocolError(op);
      }

      var repairedLastCoversCurrent = false;
      for (var i = 0; i < matchingOps.length; i++) {
        final op = matchingOps[i];
        if (!isRepairableOp(op)) continue;

        final existingProdMap = _productMapOfUpsertPayload(op.payload);
        // AUD-HIGH-01: Orijinal PRODUCT_UPSERT anındaki stok snapshot'ı korunur;
        // sonraki SALE_CREATE / STOCK_RECEIPT hareketlerinin Hub'da çift uygulanması önlenir.
        final preservedStock =
            (existingProdMap?['stock'] as num?)?.toInt() ?? product.stock;

        // Kuyrukta bu opsiyondan sonra bekleyen SALE_CREATE varsa satışın fiyat/birim
        // snapshot'ının Hub doğrulamasını bozmamak için op anındaki fiyat/birim korunur.
        final hasLaterSale = maxUnsyncedSaleSeqForProduct != null &&
            maxUnsyncedSaleSeqForProduct > op.clientSeq;

        final effectivePrice = hasLaterSale
            ? ((existingProdMap?['price'] as num?)?.toInt() ?? product.price)
            : product.price;
        final existingPv = existingProdMap?['price_version_id'];
        final effectivePriceVersionId = (hasLaterSale &&
                existingPv is String &&
                existingPv.trim().isNotEmpty)
            ? existingPv
            : product.priceVersionId;
        final existingStockUnit = existingProdMap?['stock_unit'];
        final effectiveStockUnit = (hasLaterSale &&
                existingStockUnit is String &&
                existingStockUnit.isNotEmpty)
            ? existingStockUnit
            : product.stockUnit;
        final existingPricingUnit = existingProdMap?['pricing_unit'];
        final effectivePricingUnit = (hasLaterSale &&
                existingPricingUnit is String &&
                existingPricingUnit.isNotEmpty)
            ? existingPricingUnit
            : product.pricingUnit;
        final effectiveConvNum = hasLaterSale
            ? ((existingProdMap?['conversion_factor_numerator'] as num?)
                    ?.toInt() ??
                product.conversionFactorNumerator)
            : product.conversionFactorNumerator;
        final effectiveConvDen = hasLaterSale
            ? ((existingProdMap?['conversion_factor_denominator'] as num?)
                    ?.toInt() ??
                product.conversionFactorDenominator)
            : product.conversionFactorDenominator;

        final refreshedPayload = {
          'client_seq': op.clientSeq,
          'operation_id': op.operationId,
          'operation_type': 'PRODUCT_UPSERT',
          'product': {
            'id': product.id,
            'name': product.name,
            'barcode': effectiveBarcode,
            'category_id': product.categoryId,
            'price': effectivePrice,
            'price_version_id': effectivePriceVersionId,
            'stock': preservedStock,
            'stock_unit': effectiveStockUnit,
            'pricing_unit': effectivePricingUnit,
            'conversion_factor_numerator': effectiveConvNum,
            'conversion_factor_denominator': effectiveConvDen,
            'vat_rate': product.vatRate,
            'is_active': product.isActive,
            'barcodes': barcodes,
          },
        };
        final payloadStr = jsonEncode(refreshedPayload);
        final payloadHash = sha256.convert(utf8.encode(payloadStr)).toString();
        await (db.update(db.outboxOperations)
              ..where((o) => o.operationId.equals(op.operationId)))
            .write(
          OutboxOperationsCompanion(
            payload: Value(payloadStr),
            payloadHash: Value(payloadHash),
            occurredAt: Value(occurredAt),
            status: const Value('PENDING'),
            attemptCount: const Value(0),
            nextRetryAt: const Value(null),
            lastError: const Value(null),
          ),
        );
        if (i == matchingOps.length - 1) {
          repairedLastCoversCurrent = effectivePrice == product.price &&
              effectivePriceVersionId == product.priceVersionId &&
              effectiveStockUnit == product.stockUnit &&
              effectivePricingUnit == product.pricingUnit &&
              effectiveConvNum == product.conversionFactorNumerator &&
              effectiveConvDen == product.conversionFactorDenominator;
        }
      }
      if (repairedLastCoversCurrent) return;
    }

    await _enqueueProductUpsertOutbox(
      product: product,
      barcodes: barcodes,
      deviceId: cleanDeviceId,
      occurredAt: occurredAt,
    );
  }

  /// Ürün oluşturma veya güncelleme işlemini atomik olarak Outbox tablosuna yazar
  Future<void> _enqueueProductUpsertOutbox({
    required LocalProduct product,
    required List<String> barcodes,
    required String deviceId,
    required DateTime occurredAt,
  }) async {
    final nextSeq =
        await _allocateNextClientSeq(deviceId, occurredAt: occurredAt);
    final uniqueToken = _nextUniqueToken();
    final operationId =
        'op_prod_${product.id}_${occurredAt.microsecondsSinceEpoch}_${nextSeq}_$uniqueToken';

    final effectiveBarcode =
        product.barcode ?? (barcodes.isNotEmpty ? barcodes.first : null);

    final outboxPayload = {
      'client_seq': nextSeq,
      'operation_id': operationId,
      'operation_type': 'PRODUCT_UPSERT',
      'product': {
        'id': product.id,
        'name': product.name,
        'barcode': effectiveBarcode,
        'category_id': product.categoryId,
        'price': product.price,
        'price_version_id': product.priceVersionId,
        'stock': product.stock,
        'stock_unit': product.stockUnit,
        'pricing_unit': product.pricingUnit,
        'conversion_factor_numerator': product.conversionFactorNumerator,
        'conversion_factor_denominator': product.conversionFactorDenominator,
        'vat_rate': product.vatRate,
        'is_active': product.isActive,
        'barcodes': barcodes,
      },
    };

    final payloadStr = jsonEncode(outboxPayload);
    final payloadHash = sha256.convert(utf8.encode(payloadStr)).toString();

    await db.into(db.outboxOperations).insert(
          OutboxOperationsCompanion(
            operationId: Value(operationId),
            deviceId: Value(deviceId),
            clientSeq: Value(nextSeq),
            operationType: const Value('PRODUCT_UPSERT'),
            payload: Value(payloadStr),
            payloadHash: Value(payloadHash),
            occurredAt: Value(occurredAt),
            status: const Value('PENDING'),
            attemptCount: const Value(0),
            createdAt: Value(occurredAt),
          ),
        );
  }

  /// Daha önce Outbox kaydı olmadan oluşturulmuş yerel ürünleri (örn: Test Ürün A)
  /// tespit eder ve güvenli bir şekilde Outbox kuyruğuna ekler (Idempotent).
  /// Hub'dan indirilen veya demo ürünler ASLA Outbox'a eklenmez.
  Future<int> reconcileUnsyncedProducts(String deviceId) async {
    final allProducts = await db.select(db.localProducts).get();
    if (allProducts.isEmpty) return 0;

    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS local_hub_synced_products (product_id TEXT PRIMARY KEY, synced_at TEXT NOT NULL);',
    );
    final hubRows = await db
        .customSelect('SELECT product_id FROM local_hub_synced_products;')
        .get();
    final hubSyncedIds =
        hubRows.map((r) => r.read<String>('product_id')).toSet();
    const legacyHubDemoIds = {
      'prod_sut_1l',
      'prod_ekmek_200g',
      'prod_cay_1kg',
      'prod_kola_330ml',
      'prod_dana_kiyma',
      'prod_yumurta_15li',
      'prod_zeytin_500g',
    };

    final existingOutbox = await (db.select(db.outboxOperations)
          ..where((o) =>
              o.deviceId.equals(deviceId) &
              o.operationType.equals('PRODUCT_UPSERT')))
        .get();

    final queuedProductIds = <String>{};
    for (final op in existingOutbox) {
      try {
        final decoded = jsonDecode(op.payload) as Map<String, dynamic>;
        final p = decoded['product'] as Map<String, dynamic>?;
        if (p != null && p['id'] != null) {
          queuedProductIds.add(p['id'] as String);
        }
      } catch (e) {
        // Outbox mutasyonunu engellemeden tanı izi bırak; ham payload yazılmaz.
        print(
          '[ClientStorageRepository] Outbox PRODUCT_UPSERT yükü ayrıştırılamadı (${op.operationId}): ${e.runtimeType}',
        );
      }
    }

    var reconciledCount = 0;
    final now = DateTime.now();

    for (final product in allProducts) {
      if (!queuedProductIds.contains(product.id) &&
          !hubSyncedIds.contains(product.id) &&
          !legacyHubDemoIds.contains(product.id)) {
        final barcodes = await getBarcodesForProduct(product.id);
        final barcodeList = barcodes.map((b) => b.barcode).toList();
        if (product.barcode != null && !barcodeList.contains(product.barcode)) {
          barcodeList.add(product.barcode!);
        }

        await db.transaction(() async {
          await _enqueueProductUpsertOutbox(
            product: product,
            barcodes: barcodeList,
            deviceId: deviceId,
            occurredAt: now,
          );
        });
        queuedProductIds.add(product.id);
        reconciledCount++;
      }
    }

    return reconciledCount;
  }

  Future<void> addProductBarcode({
    required String productId,
    required String barcode,
    bool isPrimary = false,
    String? deviceId,
  }) async {
    final trimBc = barcode.trim();
    if (trimBc.isEmpty) {
      throw ArgumentError('Barkod boş olamaz.');
    }
    await db.transaction(() async {
      final product = await getProductById(productId);
      if (product == null) {
        throw StateError('Barkod eklenecek ürün bulunamadı: $productId');
      }

      // BR-PROD-02: Ürünün birincil barkodu ikincil olarak tekrar eklenemez.
      if (!isPrimary &&
          product.barcode != null &&
          product.barcode!.trim() == trimBc) {
        throw ArgumentError(
          'Bu barkod ürünün birincil barkodudur; ikincil barkod olarak eklenemez: $trimBc (BR-PROD-02)',
        );
      }

      final existing = await (db.select(db.localProductBarcodes)
            ..where((b) => b.barcode.equals(trimBc)))
          .getSingleOrNull();
      if (existing != null) {
        if (existing.productId != productId) {
          throw ArgumentError(
              'Bu barkod başka bir ürüne kayıtlıdır: $trimBc (BR-PROD-02)');
        }
        if (existing.isActive) {
          throw ArgumentError(
              'Bu barkod bu ürüne zaten ekli: $trimBc (BR-PROD-02)');
        }
      }

      final otherPrimary = await (db.select(db.localProducts)
            ..where(
                (p) => p.barcode.equals(trimBc) & p.id.isNotValue(productId)))
          .getSingleOrNull();
      if (otherPrimary != null) {
        throw ArgumentError(
            'Bu barkod zaten başka bir ürüne kayıtlıdır: $trimBc (BR-PROD-02)');
      }

      final now = DateTime.now();
      final uniqueToken = _nextUniqueToken();
      if (isPrimary) {
        await (db.update(db.localProductBarcodes)
              ..where((b) => b.productId.equals(productId)))
            .write(
          const LocalProductBarcodesCompanion(isPrimary: Value(false)),
        );
        await (db.update(db.localProducts)
              ..where((p) => p.id.equals(productId)))
            .write(
          LocalProductsCompanion(barcode: Value(trimBc), updatedAt: Value(now)),
        );
      }

      if (existing != null &&
          existing.productId == productId &&
          !existing.isActive) {
        await (db.update(db.localProductBarcodes)
              ..where((b) => b.id.equals(existing.id)))
            .write(LocalProductBarcodesCompanion(
          isPrimary: Value(isPrimary),
          isActive: const Value(true),
        ));
      } else {
        await db.into(db.localProductBarcodes).insert(
              LocalProductBarcodesCompanion(
                id: Value('bc_${productId}_$uniqueToken'),
                productId: Value(productId),
                barcode: Value(trimBc),
                isPrimary: Value(isPrimary),
                isActive: const Value(true),
                createdAt: Value(now),
              ),
            );
      }

      final trimmedDeviceId = deviceId?.trim();
      if (trimmedDeviceId != null && trimmedDeviceId.isNotEmpty) {
        final updatedProduct = (await getProductById(productId))!;
        final activeBarcodes = await getBarcodesForProduct(productId);
        final barcodeList = <String>[
          if (updatedProduct.barcode != null &&
              updatedProduct.barcode!.trim().isNotEmpty)
            updatedProduct.barcode!.trim(),
        ];
        for (final bc in activeBarcodes) {
          if (!barcodeList.contains(bc.barcode)) {
            barcodeList.add(bc.barcode);
          }
        }
        await _upsertOrRepairProductOutbox(
          product: updatedProduct,
          barcodes: barcodeList,
          deviceId: trimmedDeviceId,
          occurredAt: now,
        );
      }
    });
  }

  Future<void> removeProductBarcode(
    String barcodeId, {
    String? deviceId,
  }) async {
    await db.transaction(() async {
      final existing = await (db.select(db.localProductBarcodes)
            ..where((b) => b.id.equals(barcodeId)))
          .getSingleOrNull();
      if (existing == null) return;

      final now = DateTime.now();
      // BR-PROD-15: Barkod tarihçesi korunur, pasife alınır
      await (db.update(db.localProductBarcodes)
            ..where((b) => b.id.equals(barcodeId)))
          .write(
        const LocalProductBarcodesCompanion(
          isActive: Value(false),
          isPrimary: Value(false),
        ),
      );

      final remaining = await getBarcodesForProduct(existing.productId);
      if (existing.isPrimary) {
        if (remaining.isNotEmpty) {
          final nextPrimary = remaining.first;
          await (db.update(db.localProductBarcodes)
                ..where((b) => b.id.equals(nextPrimary.id)))
              .write(
                  const LocalProductBarcodesCompanion(isPrimary: Value(true)));
          await (db.update(db.localProducts)
                ..where((p) => p.id.equals(existing.productId)))
              .write(LocalProductsCompanion(
            barcode: Value(nextPrimary.barcode),
            updatedAt: Value(now),
          ));
        } else {
          await (db.update(db.localProducts)
                ..where((p) => p.id.equals(existing.productId)))
              .write(LocalProductsCompanion(
            barcode: const Value(null),
            updatedAt: Value(now),
          ));
        }
      }

      final trimmedDeviceId = deviceId?.trim();
      if (trimmedDeviceId != null && trimmedDeviceId.isNotEmpty) {
        final updatedProduct = await getProductById(existing.productId);
        if (updatedProduct != null) {
          final barcodeList = <String>[
            if (updatedProduct.barcode != null &&
                updatedProduct.barcode!.trim().isNotEmpty)
              updatedProduct.barcode!.trim(),
          ];
          for (final bc in remaining) {
            if (!barcodeList.contains(bc.barcode)) {
              barcodeList.add(bc.barcode);
            }
          }
          await _upsertOrRepairProductOutbox(
            product: updatedProduct,
            barcodes: barcodeList,
            deviceId: trimmedDeviceId,
            occurredAt: now,
          );
        }
      }
    });
  }

  Future<List<LocalPriceHistoryData>> getPriceHistory(String productId) async {
    return (db.select(db.localPriceHistory)
          ..where((ph) => ph.productId.equals(productId))
          ..orderBy([
            (ph) => OrderingTerm.desc(ph.changedAt),
            (ph) => OrderingTerm.desc(ph.id),
          ]))
        .get();
  }

  /// Mevcut ürüne stok girişi (Faz 2 §4.3) — tek atomik transaction:
  /// 1. `local_products.stock` değerine delta eklenir (yeni ürün oluşturulmaz),
  /// 2. `receiptId` kimlikli `GIRIS` stok hareketi yazılır,
  /// 3. Delta taşıyan `STOCK_RECEIPT` Outbox kaydı FIFO `client_seq` ile kuyruğa eklenir.
  ///
  /// [receiptId] çağıran tarafından form oturumu başına bir kez üretilir ve idempotency
  /// anahtarıdır: aynı kimlikle tekrar çağrı stoğu ikinci kez artırmaz (`isDuplicate`).
  /// [quantityMilli] ürünün stok biriminde milli-birimdir (1000 = 1 adet / 1 kg).
  Future<StockReceiptResult> receiveStock({
    required String receiptId,
    required String productId,
    required int quantityMilli,
    int? unitPurchasePrice,
    String? note,
    required String deviceId,
    DateTime? occurredAt,
  }) async {
    final cleanReceiptId = receiptId.trim();
    if (cleanReceiptId.isEmpty) {
      throw ArgumentError('Stok girişi kimliği (receiptId) boş olamaz.');
    }
    if (deviceId.trim().isEmpty) {
      throw ArgumentError('Cihaz kimliği boş olamaz.');
    }
    if (quantityMilli <= 0 || quantityMilli > CartItemInput.maxQuantity) {
      throw ArgumentError(
          'Stok giriş miktarı sıfırdan büyük ve üst sınırın altında olmalıdır: $quantityMilli');
    }
    if (unitPurchasePrice != null &&
        (unitPurchasePrice < 0 || unitPurchasePrice > _maxAmountCents)) {
      throw ArgumentError('Alış fiyatı geçersiz: $unitPurchasePrice');
    }
    final cleanNote = note?.trim();
    if (cleanNote != null && cleanNote.length > 200) {
      throw ArgumentError(
          'Stok girişi açıklaması en fazla 200 karakter olabilir.');
    }
    final effectiveNote =
        (cleanNote == null || cleanNote.isEmpty) ? null : cleanNote;
    final timestamp = occurredAt ?? DateTime.now();
    final operationId = 'op_stock_$cleanReceiptId';

    return db.transaction(() async {
      // A. Idempotency: aynı giriş daha önce uygulanmış mı?
      final existing = await (db.select(db.localStockMovements)
            ..where((m) => m.id.equals(cleanReceiptId)))
          .getSingleOrNull();
      if (existing != null) {
        final sameReceipt = existing.movementType == 'GIRIS' &&
            existing.productId == productId &&
            existing.quantity == quantityMilli;
        if (!sameReceipt) {
          throw StateError(
            'Stok girişi kimliği ($cleanReceiptId) farklı içerikle daha önce kullanılmış; işlem uygulanmadı.',
          );
        }
        final current = await getProductById(productId);
        return StockReceiptResult(
          receiptId: cleanReceiptId,
          productId: productId,
          quantityMilli: quantityMilli,
          newStockMilli: current?.stock ?? 0,
          stockUnit: existing.unit,
          isDuplicate: true,
          operationId: operationId,
        );
      }

      // B. Ürün doğrulaması
      final product = await getProductById(productId);
      if (product == null) {
        throw StateError('Stok girişi yapılacak ürün bulunamadı: $productId');
      }
      if (!product.isActive) {
        throw StateError('Pasif ürüne stok girişi yapılamaz: ${product.name}');
      }
      if (kCountableStockUnits.contains(product.stockUnit) &&
          quantityMilli % quantityScale != 0) {
        throw ArgumentError(
          '"${product.stockUnit}" biriminde kesirli miktar girilemez: ${quantityMilli / quantityScale}',
        );
      }
      if (product.stock > _maxSafeInt - quantityMilli) {
        throw ArgumentError(
            'Stok artışı 64-bit tamsayı sınırını aşıyor: ${product.name}');
      }

      // C. Atomik artış (read-modify-write yerine SQL seviyesinde delta)
      await db.customUpdate(
        'UPDATE local_products SET stock = stock + ?, updated_at = ? WHERE id = ?;',
        variables: [
          Variable.withInt(quantityMilli),
          Variable.withDateTime(timestamp),
          Variable.withString(productId),
        ],
        updates: {db.localProducts},
      );

      // D. Ayrı stok hareketi
      await db.into(db.localStockMovements).insert(
            LocalStockMovementsCompanion(
              id: Value(cleanReceiptId),
              productId: Value(productId),
              quantity: Value(quantityMilli),
              unit: Value(product.stockUnit),
              movementType: const Value('GIRIS'),
              referenceId: Value(cleanReceiptId),
              purchasePrice: Value(unitPurchasePrice),
              note: Value(effectiveNote),
              createdAt: Value(timestamp),
            ),
          );

      // E. FIFO Outbox (delta semantiği — Hub'a mutlak stok gönderilmez)
      final nextSeq =
          await _allocateNextClientSeq(deviceId, occurredAt: timestamp);
      final payload = <String, dynamic>{
        'operation_id': operationId,
        'operation_type': 'STOCK_RECEIPT',
        'client_seq': nextSeq,
        'receipt_id': cleanReceiptId,
        'product_id': productId,
        'quantity': quantityMilli,
        'unit': product.stockUnit,
        'unit_purchase_price': unitPurchasePrice,
        'note': effectiveNote,
        'occurred_at': timestamp.toUtc().toIso8601String(),
      };
      final payloadStr = jsonEncode(payload);
      await db.into(db.outboxOperations).insert(
            OutboxOperationsCompanion(
              operationId: Value(operationId),
              deviceId: Value(deviceId),
              clientSeq: Value(nextSeq),
              operationType: const Value('STOCK_RECEIPT'),
              payload: Value(payloadStr),
              payloadHash:
                  Value(sha256.convert(utf8.encode(payloadStr)).toString()),
              occurredAt: Value(timestamp),
              status: const Value('PENDING'),
              attemptCount: const Value(0),
              createdAt: Value(timestamp),
            ),
          );

      final updated = (await getProductById(productId))!;
      return StockReceiptResult(
        receiptId: cleanReceiptId,
        productId: productId,
        quantityMilli: quantityMilli,
        newStockMilli: updated.stock,
        stockUnit: product.stockUnit,
        isDuplicate: false,
        operationId: operationId,
      );
    });
  }

  /// Henüz Hub tarafından onaylanmamış (SYNCED olmayan) ve stok değiştiren Outbox
  /// işlemlerinin etkilediği ürün kimlikleri. Hub snapshot'ı bu ürünlerin yerel
  /// stoğunu ezmemelidir; aksi halde bekleyen satış/giriş geçici olarak geri alınmış görünür.
  Future<Set<String>> productIdsWithUnsyncedStockChanges() async {
    final ops = await (db.select(db.outboxOperations)
          ..where((o) =>
              o.status.isIn(const [
                'PENDING',
                'RETRY',
                'IN_PROGRESS',
                'FAILED_PERMANENT'
              ]) &
              o.operationType.isIn(const [
                'SALE_CREATE',
                'SALE_CANCEL',
                'SALE_REFUND',
                'STOCK_RECEIPT'
              ])))
        .get();

    final productIds = <String>{};
    final cancelledSaleIds = <String>{};
    for (final op in ops) {
      final Map<String, dynamic> payload;
      try {
        payload = jsonDecode(op.payload) as Map<String, dynamic>;
      } on FormatException {
        continue; // Bozuk payload FIFO tarafından FAILED_PERMANENT olarak raporlanır
      }
      final directId = payload['product_id'];
      if (directId is String) productIds.add(directId);
      final items = payload['items'];
      if (items is List) {
        for (final item in items) {
          if (item is Map && item['product_id'] is String) {
            productIds.add(item['product_id'] as String);
          }
        }
      }
      if (op.operationType == 'SALE_CANCEL' && payload['sale_id'] is String) {
        cancelledSaleIds.add(payload['sale_id'] as String);
      }
    }
    if (cancelledSaleIds.isNotEmpty) {
      final items = await (db.select(db.localSaleItems)
            ..where((i) => i.saleId.isIn(cancelledSaleIds)))
          .get();
      productIds.addAll(items.map((i) => i.productId));
    }
    return productIds;
  }

  static const List<String> _unsyncedOutboxStatuses = [
    'PENDING',
    'RETRY',
    'IN_PROGRESS',
    'FAILED_PERMANENT',
  ];

  static String? _productIdOfUpsertPayload(String payload) {
    final prodMap = _productMapOfUpsertPayload(payload);
    final id = prodMap?['id'];
    return id is String ? id : null;
  }

  static Map<String, dynamic>? _productMapOfUpsertPayload(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map && decoded['product'] is Map) {
        return Map<String, dynamic>.from(decoded['product'] as Map);
      }
    } on FormatException {
      // Bozuk payload FIFO tarafından FAILED_PERMANENT olarak raporlanır.
    }
    return null;
  }

  Future<int?> _maxUnsyncedSaleSeqForProduct({
    required String deviceId,
    required String productId,
  }) async {
    final saleOps = await (db.select(db.outboxOperations)
          ..where((o) =>
              o.deviceId.equals(deviceId) &
              o.operationType.equals('SALE_CREATE') &
              o.status.isIn(_unsyncedOutboxStatuses)))
        .get();
    int? maxSeq;
    for (final op in saleOps) {
      try {
        final decoded = jsonDecode(op.payload);
        if (decoded is! Map) continue;
        final items = decoded['items'];
        if (items is! List) continue;
        final referencesProduct = items.any(
          (item) => item is Map && item['product_id'] == productId,
        );
        if (referencesProduct && (maxSeq == null || op.clientSeq > maxSeq)) {
          maxSeq = op.clientSeq;
        }
      } on FormatException {
        continue;
      }
    }
    return maxSeq;
  }

  /// Henüz Hub tarafından onaylanmamış PRODUCT_UPSERT kaydı bulunan ürün kimlikleri.
  ///
  /// 9.4: Hub katalog snapshot'ı bu ürünlerin yerel barkod kümesini ezmemelidir;
  /// aksi halde yerelde silinmiş (Hub'a henüz gitmemiş) bir barkod geçici olarak geri
  /// gelir ve sonraki bir yerel değişiklik onu kalıcı olarak Hub'a geri yazabilir.
  Future<Set<String>> productIdsWithPendingCatalogChanges() async {
    final ops = await (db.select(db.outboxOperations)
          ..where((o) =>
              o.status.isIn(_unsyncedOutboxStatuses) &
              o.operationType.equals('PRODUCT_UPSERT')))
        .get();
    final ids = <String>{};
    for (final op in ops) {
      final id = _productIdOfUpsertPayload(op.payload);
      if (id != null) ids.add(id);
    }
    return ids;
  }

  /// Ürün bazlı katalog senkron durumları (yalnızca eşitlenmemiş ürünler döner).
  Future<Map<String, ProductCatalogSyncStatus>>
      getCatalogSyncStatusByProduct() async {
    final ops = await (db.select(db.outboxOperations)
          ..where((o) =>
              o.status.isIn(_unsyncedOutboxStatuses) &
              o.operationType.equals('PRODUCT_UPSERT'))
          ..orderBy([(o) => OrderingTerm.asc(o.clientSeq)]))
        .get();
    final grouped = <String, List<OutboxOperation>>{};
    for (final op in ops) {
      final id = _productIdOfUpsertPayload(op.payload);
      if (id != null) grouped.putIfAbsent(id, () => []).add(op);
    }
    return grouped.map((id, list) => MapEntry(id, _summarizeCatalogOps(list)));
  }

  /// Tek bir ürünün katalog senkron durumu.
  Future<ProductCatalogSyncStatus> getProductCatalogSyncStatus(
      String productId) async {
    final all = await getCatalogSyncStatusByProduct();
    return all[productId] ?? ProductCatalogSyncStatus.synced;
  }

  static ProductCatalogSyncStatus _summarizeCatalogOps(
      List<OutboxOperation> ops) {
    if (ops.isEmpty) return ProductCatalogSyncStatus.synced;
    String? lastError;
    for (final op in ops) {
      if (op.lastError != null && op.lastError!.isNotEmpty)
        lastError = op.lastError;
    }
    final ProductCatalogSyncState state;
    if (ops.any((o) => o.status == 'FAILED_PERMANENT')) {
      state = ProductCatalogSyncState.failed;
    } else if (ops.any((o) => o.status == 'RETRY')) {
      state = ProductCatalogSyncState.retrying;
    } else {
      state = ProductCatalogSyncState.pending;
    }
    return ProductCatalogSyncStatus(
      state: state,
      unsyncedOperationCount: ops.length,
      lastError: lastError,
    );
  }

  /// Yerel stok hareket kayıtlarını (en yeniden eskiye) listeler
  Future<List<LocalStockMovement>> getStockMovements({
    String? productId,
    int limit = 100,
    int offset = 0,
  }) async {
    final query = db.select(db.localStockMovements);
    if (productId != null && productId.isNotEmpty) {
      query.where((m) => m.productId.equals(productId));
    }
    query.orderBy([
      (m) => OrderingTerm.desc(m.createdAt),
      (m) => OrderingTerm.desc(m.id),
    ]);
    query.limit(limit, offset: offset);
    return query.get();
  }

  static const String _hubConnectionSettingKey = 'hub_connection';

  /// Yerel istemci ayarlarından kalıcı Hub bağlantısını okur.
  ///
  /// [allowLoopback] `false` ise (Android) loopback veya `0.0.0.0` adresi tespit
  /// edildiğinde güvenli şekilde `null` döner.
  Future<StoredHubConnection?> getStoredHubConnection({
    required bool allowLoopback,
  }) async {
    final row = await (db.select(db.localClientSettings)
          ..where((s) => s.settingKey.equals(_hubConnectionSettingKey)))
        .getSingleOrNull();
    if (row == null) return null;

    final normalizedUrl = HubUrlValidator.tryNormalize(
      row.hubUrl,
      allowLoopback: allowLoopback,
    );
    if (normalizedUrl == null) return null;

    final source =
        HubUrlSource.tryParse(row.source) ?? HubUrlSource.lastVerified;
    return StoredHubConnection(
      hubUrl: normalizedUrl,
      hubId: row.hubId,
      source: source,
      lastVerifiedAt: row.lastVerifiedAt,
      updatedAt: row.updatedAt,
    );
  }

  /// Geçerli Hub bağlantısını `local_client_settings` tablosuna kalıcı olarak kaydeder.
  Future<StoredHubConnection> saveStoredHubConnection({
    required String hubUrl,
    String? hubId,
    required HubUrlSource source,
    bool allowLoopback = false,
    DateTime? verifiedAt,
    DateTime? now,
  }) async {
    final normalizedUrl = HubUrlValidator.normalizeAndValidate(
      hubUrl,
      allowLoopback: allowLoopback,
    );
    final cleanedHubId =
        hubId != null && hubId.trim().isNotEmpty ? hubId.trim() : null;
    final effectiveNow = now ?? DateTime.now();

    return db.transaction(() async {
      final existing = await (db.select(db.localClientSettings)
            ..where((s) => s.settingKey.equals(_hubConnectionSettingKey)))
          .getSingleOrNull();

      final effectiveVerifiedAt = verifiedAt ??
          (existing != null && existing.hubUrl == normalizedUrl
              ? existing.lastVerifiedAt
              : null);

      await db.into(db.localClientSettings).insertOnConflictUpdate(
            LocalClientSettingsCompanion(
              settingKey: const Value(_hubConnectionSettingKey),
              hubUrl: Value(normalizedUrl),
              hubId: Value(cleanedHubId),
              source: Value(source.storageValue),
              lastVerifiedAt: Value(effectiveVerifiedAt),
              updatedAt: Value(effectiveNow),
            ),
          );

      return StoredHubConnection(
        hubUrl: normalizedUrl,
        hubId: cleanedHubId,
        source: source,
        lastVerifiedAt: effectiveVerifiedAt,
        updatedAt: effectiveNow,
      );
    });
  }

  /// Doğrulanmış Hub bağlantısını `lastVerifiedAt` zaman damgasıyla günceller veya kaydeder.
  Future<StoredHubConnection> markHubConnectionVerified({
    required String hubUrl,
    String? hubId,
    HubUrlSource? source,
    bool allowLoopback = false,
    DateTime? verifiedAt,
  }) async {
    final normalizedUrl = HubUrlValidator.normalizeAndValidate(
      hubUrl,
      allowLoopback: allowLoopback,
    );
    final ts = verifiedAt ?? DateTime.now();

    return db.transaction(() async {
      final existing = await (db.select(db.localClientSettings)
            ..where((s) => s.settingKey.equals(_hubConnectionSettingKey)))
          .getSingleOrNull();

      final sameUrl = existing != null && existing.hubUrl == normalizedUrl;
      final effectiveSource = source ??
          (sameUrl
              ? (HubUrlSource.tryParse(existing.source) ??
                  HubUrlSource.lastVerified)
              : HubUrlSource.lastVerified);
      final cleanedHubId = hubId != null && hubId.trim().isNotEmpty
          ? hubId.trim()
          : (sameUrl ? existing.hubId : null);

      await db.into(db.localClientSettings).insertOnConflictUpdate(
            LocalClientSettingsCompanion(
              settingKey: const Value(_hubConnectionSettingKey),
              hubUrl: Value(normalizedUrl),
              hubId: Value(cleanedHubId),
              source: Value(effectiveSource.storageValue),
              lastVerifiedAt: Value(ts),
              updatedAt: Value(ts),
            ),
          );

      return StoredHubConnection(
        hubUrl: normalizedUrl,
        hubId: cleanedHubId,
        source: effectiveSource,
        lastVerifiedAt: ts,
        updatedAt: ts,
      );
    });
  }

  /// Kayıtlı kalıcı Hub bağlantı yapılandırmasını yerel ayarlardan temizler.
  Future<void> clearStoredHubConnection() async {
    await (db.delete(db.localClientSettings)
          ..where((s) => s.settingKey.equals(_hubConnectionSettingKey)))
        .go();
  }

  static String _restoreEpochSettingKey(String deviceId) =>
      'restore_epoch_$deviceId';

  /// `OV-03`: İstemcinin en son başarıyla uzlaştırdığı Hub `restore_epoch` değerini okur.
  Future<String?> getStoredRestoreEpoch(String deviceId) async {
    final row = await (db.select(db.localClientSettings)
          ..where(
              (s) => s.settingKey.equals(_restoreEpochSettingKey(deviceId))))
        .getSingleOrNull();
    final epoch = row?.hubId?.trim();
    if (epoch == null || epoch.isEmpty) return null;
    return epoch;
  }

  /// `OV-03`: Tüm eksik post-restore işlemleri Hub'a ACK ile teslim edildikten sonra
  /// yeni `restore_epoch` değerini kalıcı olarak kaydeder.
  Future<void> saveStoredRestoreEpoch(
      String deviceId, String restoreEpoch) async {
    final cleanEpoch = restoreEpoch.trim();
    if (cleanEpoch.isEmpty) return;
    await db.into(db.localClientSettings).insertOnConflictUpdate(
          LocalClientSettingsCompanion(
            settingKey: Value(_restoreEpochSettingKey(deviceId)),
            hubUrl: const Value('meta://restore_epoch'),
            hubId: Value(cleanEpoch),
            source: const Value('restore_epoch'),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
  }

  /// `OV-03`: İstemcide tam yük/hash ile korunan `SYNCED` Outbox kayıtlarını
  /// `client_seq ASC` sırasıyla döner.
  Future<List<OutboxOperation>> getSyncedOutboxOperations(
    String deviceId, {
    int afterSeq = 0,
  }) {
    return (db.select(db.outboxOperations)
          ..where((o) =>
              o.deviceId.equals(deviceId) &
              o.status.equals('SYNCED') &
              o.clientSeq.isBiggerThanValue(afterSeq))
          ..orderBy([(o) => OrderingTerm.asc(o.clientSeq)]))
        .get();
  }

  /// `OV-03`: Hub eski bir yedeğe döndüğünde (`restore_epoch` değişimi veya `HWM < local.lastSyncedSeq`)
  /// Hub'da bulunmayan (`NOT_FOUND`) geçmiş `SYNCED` işlemleri özgün `operation_id`,
  /// `device_id`, `client_seq`, `payload` ve `payload_hash` alanlarını koruyarak atomik
  /// olarak `PENDING` durumuna yeniden kuyruğa alır.
  ///
  /// Eksik aralıktaki herhangi bir `client_seq` yerel veritabanında yoksa veya ham `payload`/`payload_hash`
  /// boşsa fail-closed [PostRestoreHistoryMissingException] fırlatır ve hiçbir satırı değiştirmez.
  Future<int> requeueOperationsForPostRestore({
    required String deviceId,
    required List<int> missingSeqs,
  }) async {
    if (missingSeqs.isEmpty) return 0;
    final orderedMissing = missingSeqs.toSet().toList()..sort();

    return db.transaction(() async {
      final rows = await (db.select(db.outboxOperations)
            ..where((o) =>
                o.deviceId.equals(deviceId) & o.clientSeq.isIn(orderedMissing))
            ..orderBy([(o) => OrderingTerm.asc(o.clientSeq)]))
          .get();

      final bySeq = <int, OutboxOperation>{
        for (final r in rows) r.clientSeq: r
      };
      final opsToRequeue = <OutboxOperation>[];

      for (final seq in orderedMissing) {
        final op = bySeq[seq];
        if (op == null ||
            op.operationId.trim().isEmpty ||
            op.payload.trim().isEmpty ||
            op.payloadHash.trim().isEmpty) {
          throw PostRestoreHistoryMissingException(
            'ERR_POST_RESTORE_HISTORY_MISSING',
            'Hub geri yükleme sonrası uzlaştırma durduruldu: client_seq=$seq için yerel Outbox geçmişi veya işlem yükü eksik.',
          );
        }
        if (op.status == 'SYNCED') {
          opsToRequeue.add(op);
        }
      }

      if (opsToRequeue.isNotEmpty) {
        final ids = opsToRequeue.map((o) => o.operationId).toList();
        await (db.update(db.outboxOperations)
              ..where((o) => o.operationId.isIn(ids)))
            .write(
          const OutboxOperationsCompanion(
            status: Value('PENDING'),
            attemptCount: Value(0),
            nextRetryAt: Value(null),
            lastError: Value('POST_RESTORE_RECONCILE'),
          ),
        );
      }

      final state = await getSyncState(deviceId);
      if (state != null) {
        final targetHwm = orderedMissing.first - 1;
        if (targetHwm < state.lastSyncedSeq) {
          await (db.update(db.clientSyncStates)
                ..where((s) => s.deviceId.equals(deviceId)))
              .write(
            ClientSyncStatesCompanion(
              lastSyncedSeq: Value(targetHwm < 0 ? 0 : targetHwm),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
      }

      return opsToRequeue.length;
    });
  }
}
