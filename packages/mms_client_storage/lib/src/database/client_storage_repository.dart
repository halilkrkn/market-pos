import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import 'client_database.dart';
import '../models/cart_item_input.dart';
import '../models/sale_transaction_result.dart';

class ClientStorageRepository {
  static const int quantityScale = CartItemInput.scale; // 1000 (3 ondalık hane ölçeği)
  static const int _maxSafeInt = 9223372036854775807; // 2^63 - 1 (64-bit signed int max)

  final ClientDatabase db;

  ClientStorageRepository(this.db);

  /// S5A-3: Satış işlem yükünün (payload) kanonik SHA-256 hash özetini üretir (Backend ile %100 uyumlu)
  static String computeSaleRequestHash(Map<String, dynamic> body) {
    final canonical = {
      'client_seq': body['client_seq'],
      'total_amount': body['total_amount'],
      'payment_method': body['payment_method'],
      'items': body['items'],
    };
    return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
  }

  /// Cihazın senkronizasyon durumunu başlatır veya mevcut olanı döner
  Future<ClientSyncState> initializeDevice(String deviceId) async {
    final existing = await (db.select(db.clientSyncStates)
          ..where((s) => s.deviceId.equals(deviceId)))
        .getSingleOrNull();

    if (existing != null) {
      return existing;
    }

    final newState = ClientSyncStatesCompanion(
      deviceId: Value(deviceId),
      currentClientSeq: const Value(0),
      lastSyncedSeq: const Value(0),
      updatedAt: Value(DateTime.now()),
    );

    await db.into(db.clientSyncStates).insert(newState);
    return (await (db.select(db.clientSyncStates)
          ..where((s) => s.deviceId.equals(deviceId)))
        .getSingle());
  }

  /// Cihazın senkronizasyon durumunu döner
  Future<ClientSyncState?> getSyncState(String deviceId) async {
    return (db.select(db.clientSyncStates)..where((s) => s.deviceId.equals(deviceId)))
        .getSingleOrNull();
  }

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

    final saleTimestamp = occurredAt ?? DateTime.now();

    return await db.transaction(() async {
      // A. Cihaz senkronizasyon durumunu kilitli olarak oku ve artır
      var syncState = await (db.select(db.clientSyncStates)
            ..where((s) => s.deviceId.equals(deviceId)))
          .getSingleOrNull();

      if (syncState == null) {
        syncState = await initializeDevice(deviceId);
      }

      final nextSeq = syncState.currentClientSeq + 1;
      final saleId = 'csale_${saleTimestamp.microsecondsSinceEpoch}_$nextSeq';
      final operationId = customOperationId ?? 'op_${saleTimestamp.microsecondsSinceEpoch}_$nextSeq';

      var calculatedTotalAmount = 0;
      final itemResults = <SaleTransactionItemResult>[];
      final payloadItems = <Map<String, dynamic>>[];

      // B. Sepetteki her ürünün mevcudiyetini ve aktifliğini doğrula, snapshot al
      for (final item in items) {
        final product = await (db.select(db.localProducts)
              ..where((p) => p.id.equals(item.productId)))
            .getSingleOrNull();

        if (product == null) {
          throw StateError('Ürün yerel veritabanında bulunamadı: ${item.productId}');
        }

        if (!product.isActive) {
          throw StateError('Pasif ürün satılamaz: ${product.name} (${product.id})');
        }

        final unitPrice = product.price; // Kuruş bazlı (Ör: 200 TL/kg = 20000 kuruş)
        final priceVersionId = product.priceVersionId; // S5A-3: Fiyat sürüm kimliği

        // S5A-3: Çarpım öncesi Integer Overflow kontrolü
        if (unitPrice > 0 && item.quantity > (_maxSafeInt - (quantityScale ~/ 2)) ~/ unitPrice) {
          throw ArgumentError('Birim fiyat ve miktar çarpımı tamsayı sınırını aşıyor (Integer Overflow).');
        }

        // Kesirli miktar hesabı: itemTotal = ((unitPrice * quantity) + 500) ~/ 1000 (Standart ticari yuvarlama)
        final itemTotal = ((unitPrice * item.quantity) + (quantityScale ~/ 2)) ~/ quantityScale;

        // Toplam sepet tutarı taşma kontrolü
        if (calculatedTotalAmount > _maxSafeInt - itemTotal) {
          throw ArgumentError('Toplam sepet tutarı tamsayı sınırını aşıyor (Integer Overflow).');
        }
        calculatedTotalAmount += itemTotal;

        // Birim dönüşümü: 1 pricing_unit = (num / den) stock_unit
        final num = product.conversionFactorNumerator;
        final den = product.conversionFactorDenominator;
        if (num <= 0 || den <= 0) {
          throw StateError('Geçersiz birim dönüşüm katsayısı ($num / $den): ${product.name}');
        }

        // Dönüşüm öncesi taşma kontrolü
        if (num > 0 && item.quantity > _maxSafeInt ~/ num) {
          throw ArgumentError('Miktar ve birim katsayısı çarpımı tamsayı sınırını aşıyor (Integer Overflow).');
        }

        final prodMilli = item.quantity * num;
        if (prodMilli % den != 0) {
          throw ArgumentError(
            'Miktar (${item.quantity}), ürün stok birimine (${product.stockUnit}) kayıpsız dönüştürülemiyor. Kalan: ${prodMilli % den}',
          );
        }
        final stockDelta = prodMilli ~/ den;

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
              paymentMethod: Value(paymentMethod),
              status: const Value('COMPLETED'),
              createdAt: Value(saleTimestamp),
            ),
          );

      // D. Kalemleri, stok hareketlerini ve ürün stok güncellemelerini işle
      for (final item in itemResults) {
        final itemId = 'citem_${saleTimestamp.microsecondsSinceEpoch}_${item.productId}';
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

        final movementId = 'csm_${saleTimestamp.microsecondsSinceEpoch}_${item.productId}';
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

        final updatedStock = currentProd.stock - item.stockDelta;
        await (db.update(db.localProducts)..where((p) => p.id.equals(item.productId))).write(
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
        'payment_method': paymentMethod,
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

      // G. client_sync_states tablosunda currentClientSeq değerini güncelle
      await (db.update(db.clientSyncStates)..where((s) => s.deviceId.equals(deviceId))).write(
            ClientSyncStatesCompanion(
              currentClientSeq: Value(nextSeq),
              updatedAt: Value(saleTimestamp),
            ),
          );

      return SaleTransactionResult(
        saleId: saleId,
        deviceId: deviceId,
        clientSeq: nextSeq,
        totalAmount: calculatedTotalAmount,
        paymentMethod: paymentMethod,
        operationId: operationId,
        items: itemResults,
        createdAt: saleTimestamp,
        isCommitted: true,
      );
    });
  }

  /// Sunucudan gelen ürün listesini ve ilişkili barkodları atomik olarak günceller
  Future<void> upsertProducts(
    List<LocalProductsCompanion> products, {
    List<LocalProductBarcodesCompanion>? barcodes,
  }) async {
    await db.transaction(() async {
      for (final prod in products) {
        await db.into(db.localProducts).insertOnConflictUpdate(prod);
      }
      if (barcodes != null) {
        for (final bc in barcodes) {
          await db.into(db.localProductBarcodes).insertOnConflictUpdate(bc);
        }
      }
    });
  }

  /// Barkod üzerinden ürün arar (SSOT: LocalProductBarcodes tablosu)
  Future<LocalProduct?> getProductByBarcode(String barcode) async {
    final barcodeRow = await (db.select(db.localProductBarcodes)
          ..where((b) => b.barcode.equals(barcode) & b.isActive.equals(true)))
        .getSingleOrNull();

    if (barcodeRow != null) {
      return (db.select(db.localProducts)..where((p) => p.id.equals(barcodeRow.productId)))
          .getSingleOrNull();
    }

    // Doğrudan primary barcode kolonundan yedek arama (denormalize hızlı arama)
    return (db.select(db.localProducts)..where((p) => p.barcode.equals(barcode)))
        .getSingleOrNull();
  }

  /// Bir ürüne ait tüm barkodları döner
  Future<List<LocalProductBarcode>> getBarcodesForProduct(String productId) async {
    return (db.select(db.localProductBarcodes)
          ..where((b) => b.productId.equals(productId) & b.isActive.equals(true)))
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
              (o.nextRetryAt.isNull() | o.nextRetryAt.isSmallerOrEqualValue(effectiveNow)))
          ..orderBy([(o) => OrderingTerm.asc(o.clientSeq)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Cihaza ait tüm gönderilmemiş işlemleri döner
  Future<List<OutboxOperation>> getUnsyncedOutboxOperations(String deviceId) async {
    return (db.select(db.outboxOperations)
          ..where((o) =>
              o.deviceId.equals(deviceId) &
              (o.status.equals('PENDING') | o.status.equals('RETRY') | o.status.equals('IN_PROGRESS') | o.status.equals('FAILED_PERMANENT')))
          ..orderBy([(o) => OrderingTerm.asc(o.clientSeq)]))
        .get();
  }

  /// Outbox operasyonunu IN_PROGRESS olarak işaretler
  Future<void> markOutboxInProgress(String operationId) async {
    await (db.update(db.outboxOperations)..where((o) => o.operationId.equals(operationId))).write(
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
      await (db.update(db.outboxOperations)..where((o) => o.operationId.equals(operationId))).write(
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
        await (db.update(db.clientSyncStates)..where((s) => s.deviceId.equals(deviceId))).write(
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

    await (db.update(db.outboxOperations)..where((o) => o.operationId.equals(operationId))).write(
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
    await (db.update(db.outboxOperations)..where((o) => o.operationId.equals(operationId))).write(
          OutboxOperationsCompanion(
            status: const Value('FAILED_PERMANENT'),
            lastError: Value(error),
          ),
        );
  }

  /// S5A-3: Kalıcı hata almış (FAILED_PERMANENT) operasyonları döner (Hata incelemesi için)
  Future<List<OutboxOperation>> getFailedPermanentOperations(String deviceId) async {
    return (db.select(db.outboxOperations)
          ..where((o) => o.deviceId.equals(deviceId) & o.status.equals('FAILED_PERMANENT'))
          ..orderBy([(o) => OrderingTerm.asc(o.clientSeq)]))
        .get();
  }

  /// S5A-3: Hata giderildikten sonra FAILED_PERMANENT operasyonu PENDING durumuna geri alır (Kuyruğu tekrar başlatır)
  Future<void> retryFailedPermanentOperation(String operationId) async {
    await (db.update(db.outboxOperations)..where((o) => o.operationId.equals(operationId))).write(
          const OutboxOperationsCompanion(
            status: Value('PENDING'),
            attemptCount: Value(0),
            nextRetryAt: Value(null),
            lastError: Value(null),
          ),
        );
  }

  /// S5A-3: Düzeltilmiş yeni bir işlem yükü ile kalıcı hatalı operasyonu günceller ve yeniden dener
  Future<void> updateAndRetryFailedOperation(
    String operationId, {
    required Map<String, dynamic> correctedPayload,
  }) async {
    final payloadStr = jsonEncode(correctedPayload);
    final payloadHash = computeSaleRequestHash(correctedPayload);

    await (db.update(db.outboxOperations)..where((o) => o.operationId.equals(operationId))).write(
          OutboxOperationsCompanion(
            payload: Value(payloadStr),
            payloadHash: Value(payloadHash),
            status: const Value('PENDING'),
            attemptCount: const Value(0),
            nextRetryAt: const Value(null),
            lastError: const Value(null),
          ),
        );
  }

  /// Uygulama başladığında kilitli/yarıda kalmış IN_PROGRESS işlemlerini kurtarır (Crash Recovery)
  Future<int> recoverStuckInProgressOperations(String deviceId) async {
    final stuckOps = await (db.select(db.outboxOperations)
          ..where((o) => o.deviceId.equals(deviceId) & o.status.equals('IN_PROGRESS')))
        .get();

    for (final op in stuckOps) {
      final targetStatus = op.attemptCount > 0 ? 'RETRY' : 'PENDING';
      await (db.update(db.outboxOperations)..where((o) => o.operationId.equals(op.operationId))).write(
            OutboxOperationsCompanion(
              status: Value(targetStatus),
              lastError: const Value('Uygulama çökmesi sonrası IN_PROGRESS durumundan kurtarıldı.'),
            ),
          );
    }

    return stuckOps.length;
  }
}
