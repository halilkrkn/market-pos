import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import 'client_database.dart';
import '../models/cart_item_input.dart';
import '../models/payment_method.dart';
import '../models/price_changed_exception.dart';
import '../models/refund_item_input.dart';
import '../models/sale_detail_models.dart';
import '../models/sale_transaction_result.dart';
import '../models/stock_receipt_result.dart';
import '../models/downloaded_sale_payload.dart';
import '../models/hub_connection_config.dart';
import '../models/hub_url_validator.dart';
import 'package:mms_contracts/mms_contracts.dart';

class ClientStorageRepository {
  static const int quantityScale = CartItemInput.scale; // 1000 (3 ondalık hane ölçeği)
  static const int _maxSafeInt = 9223372036854775807; // 2^63 - 1 (64-bit signed int max)
  static const int _minSafeInt = -9223372036854775808; // -2^63 (64-bit signed int min)
  static const int _maxAmountCents = 100000000000; // 1 milyar TL (10^11 kuruş) üst tutar sınırı
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
        await (db.update(db.clientSyncStates)..where((s) => s.deviceId.equals(deviceId))).write(
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
    return (db.select(db.clientSyncStates)..where((s) => s.deviceId.equals(deviceId)))
        .getSingleOrNull();
  }

  /// Monotonik artan sonraki istemci sıra numarasını (client_seq) güvenli bir şekilde tahsis eder.
  /// Formül: max(current_client_seq, MAX(outbox_operations.client_seq)) + 1
  /// Not: Bu metot mutlaka çağıran operasyonun atomik db.transaction bloğu içinde çalıştırılmalıdır.
  Future<int> allocateNextClientSeq(String deviceId, {DateTime? occurredAt}) async {
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
      final nextSeq = await _allocateNextClientSeq(deviceId, occurredAt: saleTimestamp);
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
          throw StateError('Ürün yerel veritabanında bulunamadı: ${item.productId}');
        }

        if (!product.isActive) {
          throw StateError('Pasif ürün satılamaz: ${product.name} (${product.id})');
        }

        final unitPrice = product.price; // Kuruş bazlı (Ör: 200 TL/kg = 20000 kuruş)
        if (unitPrice < 0 || unitPrice > _maxAmountCents) {
          throw ArgumentError(
            'Geçersiz ürün birim fiyatı ($unitPrice): ${product.name} (${product.id})',
          );
        }
        final priceVersionId = product.priceVersionId; // S5A-3: Fiyat sürüm kimliği

        // Faz 1.2 Güvenilirlik: Sepet snapshot'ı ile DB güncel fiyatı/sürümü tutarlılık kontrolü
        final priceChanged =
            item.expectedUnitPrice != null && unitPrice != item.expectedUnitPrice;
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
        if (unitPrice > 0 && item.quantity > (_maxSafeInt - (quantityScale ~/ 2)) ~/ unitPrice) {
          throw ArgumentError('Birim fiyat ve miktar çarpımı tamsayı sınırını aşıyor (Integer Overflow).');
        }

        // Kesirli miktar hesabı: itemTotal = ((unitPrice * quantity) + 500) ~/ 1000 (Standart ticari yuvarlama)
        final itemTotal = ((unitPrice * item.quantity) + (quantityScale ~/ 2)) ~/ quantityScale;
        if (itemTotal < 0 || itemTotal > _maxAmountCents) {
          throw ArgumentError('Satır tutarı izin verilen üst sınırı aşıyor: $itemTotal');
        }

        // Toplam sepet tutarı taşma ve üst sınır kontrolü
        if (calculatedTotalAmount > _maxSafeInt - itemTotal ||
            calculatedTotalAmount + itemTotal > _maxAmountCents) {
          throw ArgumentError('Toplam sepet tutarı tamsayı veya tutar sınırını aşıyor.');
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

        if ((item.stockDelta > 0 && currentProd.stock < _minSafeInt + item.stockDelta) ||
            (item.stockDelta < 0 && currentProd.stock > _maxSafeInt + item.stockDelta)) {
          throw ArgumentError(
            'Stok güncelleme işlemi 64-bit tamsayı sınırını aşıyor: ${item.productName}',
          );
        }
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

  /// Sunucudan gelen ürün listesini ve ilişkili barkodları atomik olarak günceller
  Future<void> upsertProducts(
    List<LocalProductsCompanion> products, {
    List<LocalProductBarcodesCompanion>? barcodes,
  }) async {
    await db.transaction(() async {
      // Barkod çakışma kontrolleri: Ürünler yazılmadan önce doğrulanır
      if (barcodes != null) {
        final seenBarcodesInBatch = <String, String>{}; // barcode -> productId

        for (final bc in barcodes) {
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

            // 2. Mevcut veritabanı çakışma kontrolü: Barkod başka ürüne aitse sahipliği çalma!
            final existingBc = await (db.select(db.localProductBarcodes)
                  ..where((b) => b.barcode.equals(barcodeVal)))
                .getSingleOrNull();

            if (existingBc != null) {
              if (existingBc.productId != prodIdVal) {
                throw StateError(
                  'Barkod çakışması: "$barcodeVal" barkodu zaten mevcut başka bir ürüne (${existingBc.productId}) atanmış. '
                  'Mevcut barkod sahipliği korunarak işlem atomik olarak iptal edildi.',
                );
              } else if (bc.id.present && existingBc.id != bc.id.value) {
                // Aynı ürünün mevcut barkodu: ID farkı varsa (örn: local create vs Hub sync ID) eski kaydı temizle
                await (db.delete(db.localProductBarcodes)
                      ..where((b) => b.id.equals(existingBc.id)))
                    .go();
              }
            }
          }
        }
      }

      // Faz 7A: Bekleyen yerel stok değişiklikleri Hub snapshot'ı tarafından ezilmez.
      final pendingStockProductIds = await productIdsWithUnsyncedStockChanges();

      for (final incoming in products) {
        var prod = incoming;
        if (prod.id.present && pendingStockProductIds.contains(prod.id.value)) {
          final local = await getProductById(prod.id.value);
          if (local != null) {
            prod = prod.copyWith(stock: Value(local.stock));
          }
        }
        await db.into(db.localProducts).insertOnConflictUpdate(prod);
        if (prod.id.present && prod.id.value.isNotEmpty) {
          await db.customStatement(
            'INSERT OR REPLACE INTO local_hub_synced_products (product_id, synced_at) VALUES (?, ?);',
            [prod.id.value, DateTime.now().toIso8601String()],
          );
        }
      }
      if (barcodes != null) {
        for (final bc in barcodes) {
          await db.into(db.localProductBarcodes).insertOnConflictUpdate(bc);
        }
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
                  (s.deviceId.equals(sale.deviceId) & s.clientSeq.equals(sale.clientSeq))))
            .getSingleOrNull();

        if (existing != null) {
          // Satış zaten mevcut (örneğin bu cihaz tarafından yapılmış veya önceki sync'te inmiş).
          // Durum, iptal nedeni veya iptal zamanı değişmişse güncelle.
          // DİKKAT: Hub'dan gelen durum 'COMPLETED' olsa dahi, eğer yerel satış
          // iade edilmişse ('REFUNDED' veya 'PARTIALLY_REFUNDED'), Hub durumu ile ezilmemelidir.
          // Ancak Hub'dan gelen durum 'CANCELLED' ise iptal her zaman önceliklidir (BR-POS-08).
          final effectiveStatus = (sale.status == 'CANCELLED')
              ? 'CANCELLED'
              : (existing.status == 'REFUNDED' || existing.status == 'PARTIALLY_REFUNDED')
                  ? existing.status
                  : sale.status;

          await (db.update(db.localSales)..where((s) => s.id.equals(existing.id))).write(
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
          final initialStatus = (sale.status != 'CANCELLED' && sale.refunds.isNotEmpty)
              ? (sale.refunds.fold(0, (sum, r) => sum + r.totalRefundAmount) >= sale.totalAmount
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
                    (r.deviceId.equals(ref.deviceId) & r.clientSeq.equals(ref.clientSeq))))
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
                      ..where((si) => si.saleId.equals(ref.saleId) & si.productId.equals(ri.productId)))
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
          final totalRef = sale.refunds.fold(0, (sum, r) => sum + r.totalRefundAmount);
          final derivedStatus = totalRef >= sale.totalAmount ? 'REFUNDED' : 'PARTIALLY_REFUNDED';
          await (db.update(db.localSales)..where((s) => s.id.equals(existing?.id ?? sale.id))).write(
            LocalSalesCompanion(status: Value(derivedStatus)),
          );
        }
      }

      // İndirilen satışlar sonrası yerel iade durumlarını reconcile et
      await reconcileSaleStatuses();

      // 3. İstemci senkronizasyon durumunu güncelle
      final syncState = await getSyncState(deviceId);
      if (syncState != null) {
        await (db.update(db.clientSyncStates)..where((s) => s.deviceId.equals(deviceId))).write(
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
        parsedPaymentMethod = PaymentMethod.parse(correctedPayload['payment_method']);
      }

      int? repairedTotalAmount;
      if (isSaleCreate) {
        final rawTotalAmount = correctedPayload['total_amount'];
        final rawItems = correctedPayload['items'];
        if (rawTotalAmount is! int || rawTotalAmount <= 0) {
          throw ArgumentError('Onarım yükünde total_amount pozitif tamsayı olmalıdır.');
        }
        if (rawItems is! List || rawItems.isEmpty) {
          throw ArgumentError('Onarım yükünde en az bir satış kalemi (items) bulunmalıdır.');
        }
        repairedTotalAmount = rawTotalAmount;
      }

      final payloadStr = jsonEncode(correctedPayload);
      final payloadHash = computeSaleRequestHash(correctedPayload);

      await (db.update(db.outboxOperations)..where((o) => o.operationId.equals(operationId)))
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

      if (isSaleCreate && parsedPaymentMethod != null && repairedTotalAmount != null) {
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
          ..where((s) => s.deviceId.equals(deviceId) & s.clientSeq.equals(clientSeq)))
        .getSingleOrNull();
    if (localSale == null) return;

    if (repairedTotalAmount != localSale.totalAmount) {
      throw ArgumentError(
        'Onarım yükündeki total_amount ($repairedTotalAmount) yerel satış tutarıyla (${localSale.totalAmount}) uyuşmuyor.',
      );
    }

    final logicalPrior = PaymentMethod.tryParseLegacyReadOnly(localSale.paymentMethod);
    if (logicalPrior != null && logicalPrior != repairedMethod) {
      throw ArgumentError(
        'Satışın ödeme yöntemi (${localSale.paymentMethod}) farklı bir yönteme (${repairedMethod.code}) sessizce dönüştürülemez.',
      );
    }

    if (localSale.paymentMethod != repairedMethod.code) {
      await (db.update(db.localSales)..where((s) => s.id.equals(localSale.id)))
          .write(LocalSalesCompanion(paymentMethod: Value(repairedMethod.code)));
    }
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
          await (db.update(db.localSales)..where((s) => s.id.equals(sale.id))).write(
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
      query.where((s) => s.id.like('%$trimmed%') | s.deviceId.like('%$trimmed%'));
    }
    query.orderBy([(s) => OrderingTerm.desc(s.createdAt)]);
    query.limit(limit, offset: offset);
    return await query.get();
  }

  /// Tekil bir satışın tüm kalemlerini, iadelerini ve stok hareketlerini döner
  Future<SaleWithDetails?> getSaleDetail(String saleId) async {
    final sale = await (db.select(db.localSales)..where((s) => s.id.equals(saleId))).getSingleOrNull();
    if (sale == null) return null;

    final items = await (db.select(db.localSaleItems)..where((i) => i.saleId.equals(saleId))).get();

    final refunds = await (db.select(db.localRefunds)..where((r) => r.saleId.equals(saleId))).get();
    final refundsWithItems = <RefundWithItems>[];
    for (final ref in refunds) {
      final refItems = await (db.select(db.localRefundItems)..where((ri) => ri.refundId.equals(ref.id))).get();
      refundsWithItems.add(RefundWithItems(refund: ref, items: refItems));
    }

    final stockMovements = await (db.select(db.localStockMovements)..where((sm) => sm.referenceId.equals(saleId))).get();

    return SaleWithDetails(
      sale: sale,
      items: items,
      refunds: refundsWithItems,
      stockMovements: stockMovements,
    );
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
      final sale = await (db.select(db.localSales)..where((s) => s.id.equals(saleId))).getSingleOrNull();
      if (sale == null) {
        throw StateError('İptal edilecek satış bulunamadı: $saleId');
      }
      if (sale.status == 'CANCELLED') {
        throw StateError('Bu satış zaten iptal edilmiştir (BR-POS-08).');
      }

      // Kalemleri ve geçmiş iadeleri kontrol et
      final items = await (db.select(db.localSaleItems)..where((i) => i.saleId.equals(saleId))).get();
      final refunds = await (db.select(db.localRefunds)..where((r) => r.saleId.equals(saleId))).get();
      final refundedQtyByItemId = <String, int>{};
      for (final ref in refunds) {
        final refItems = await (db.select(db.localRefundItems)..where((ri) => ri.refundId.equals(ref.id))).get();
        for (final ri in refItems) {
          refundedQtyByItemId[ri.saleItemId] = (refundedQtyByItemId[ri.saleItemId] ?? 0) + ri.quantity;
        }
      }

      // Cihaz senkronizasyon sıra numarasını (client_seq) güvenli ve kilitli olarak tahsis et
      final nextSeq = await _allocateNextClientSeq(deviceId, occurredAt: effectiveTime);
      final uniqueToken = _nextUniqueToken();
      final operationId = 'op_cancel_${effectiveTime.microsecondsSinceEpoch}_${nextSeq}_$uniqueToken';

      // Stok iade hareketleri: Daha önce kısmi iade edilmemiş kalan miktar stoğa geri iade edilir
      for (final item in items) {
        final refundedQty = refundedQtyByItemId[item.id] ?? 0;
        final remainingQty = item.quantity - refundedQty;

        if (remainingQty > 0) {
          final product = await (db.select(db.localProducts)..where((p) => p.id.equals(item.productId))).getSingleOrNull();
          if (product != null) {
            final num = product.conversionFactorNumerator;
            final den = product.conversionFactorDenominator;
            final prodMilli = remainingQty * num;
            final stockDelta = prodMilli ~/ den;

            final movementId = 'csm_cancel_${saleId}_${item.productId}_$uniqueToken';
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
            await (db.update(db.localProducts)..where((p) => p.id.equals(item.productId))).write(
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
      final sale = await (db.select(db.localSales)..where((s) => s.id.equals(saleId))).getSingleOrNull();
      if (sale == null) {
        throw StateError('İade yapılacak satış bulunamadı: $saleId');
      }
      if (sale.status == 'CANCELLED') {
        throw StateError('İptal edilmiş bir satış üzerinden iade yapılamaz (BR-POS-08, BR-POS-09).');
      }

      // Mevcut iadeleri topla
      final existingRefunds = await (db.select(db.localRefunds)..where((r) => r.saleId.equals(saleId))).get();
      final refundedQtyByItemId = <String, int>{};
      for (final ref in existingRefunds) {
        final refItems = await (db.select(db.localRefundItems)..where((ri) => ri.refundId.equals(ref.id))).get();
        for (final ri in refItems) {
          refundedQtyByItemId[ri.saleItemId] = (refundedQtyByItemId[ri.saleItemId] ?? 0) + ri.quantity;
        }
      }

      // Cihaz senkronizasyon sıra numarasını (client_seq) güvenli ve kilitli olarak tahsis et
      final nextSeq = await _allocateNextClientSeq(deviceId, occurredAt: effectiveTime);
      final uniqueToken = _nextUniqueToken();
      final refundId = 'ref_${effectiveTime.microsecondsSinceEpoch}_${nextSeq}_$uniqueToken';
      final operationId = 'op_refund_${effectiveTime.microsecondsSinceEpoch}_${nextSeq}_$uniqueToken';

      var totalRefundAmount = 0;
      final refundItemCompanions = <LocalRefundItemsCompanion>[];
      final refundPayloadItems = <Map<String, dynamic>>[];

      for (final itemInput in items) {
        if (itemInput.quantity <= 0) {
          throw ArgumentError('İade miktarı sıfırdan büyük olmalıdır: ${itemInput.saleItemId}');
        }

        final saleItem = await (db.select(db.localSaleItems)..where((i) => i.id.equals(itemInput.saleItemId))).getSingleOrNull();
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
        final itemRefundAmount = ((saleItem.unitPrice * itemInput.quantity) + (quantityScale ~/ 2)) ~/ quantityScale;
        totalRefundAmount += itemRefundAmount;

        final refundItemId = 'refitem_${refundId}_${saleItem.id}';
        final condition = itemInput.productCondition == 'DAMAGED' ? 'DAMAGED' : 'SELLABLE';

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
        final product = await (db.select(db.localProducts)..where((p) => p.id.equals(saleItem.productId))).getSingleOrNull();
        if (product != null) {
          final num = product.conversionFactorNumerator;
          final den = product.conversionFactorDenominator;
          final prodMilli = itemInput.quantity * num;
          final stockDelta = prodMilli ~/ den;

          if (condition == 'SELLABLE') {
            // Tekrar satılabilir: MUSTERI_IADESI ve stok artar
            final smId = 'csm_ref_${refundId}_${saleItem.productId}_$uniqueToken';
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
            await (db.update(db.localProducts)..where((p) => p.id.equals(saleItem.productId))).write(
              LocalProductsCompanion(
                stock: Value(updatedStock),
                updatedAt: Value(effectiveTime),
              ),
            );
          } else {
            // Hasarlı/Bozuk: FIRE_KAYIP ve normal satılabilir stok ARTMAZ (BR-POS-10)
            final smId = 'csm_fire_${refundId}_${saleItem.productId}_$uniqueToken';
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
          paymentMethod: Value(sale.paymentMethod), // Orijinal ödeme yöntemi ile iade (BR-POS-09)
          reason: Value(trimReason),
          createdAt: Value(effectiveTime),
        ),
      );

      // LocalRefundItems kayıtlarını ekle
      for (final companion in refundItemCompanions) {
        await db.into(db.localRefundItems).insert(companion);
      }

      // Tüm kalemler %100 iade edilmiş mi kontrol et
      final allSaleItems = await (db.select(db.localSaleItems)..where((i) => i.saleId.equals(saleId))).get();
      final allFullyRefunded = allSaleItems.every((item) {
        final totalRef = refundedQtyByItemId[item.id] ?? 0;
        return totalRef >= item.quantity;
      });

      if (allFullyRefunded) {
        await (db.update(db.localSales)..where((s) => s.id.equals(saleId))).write(
          const LocalSalesCompanion(status: Value('REFUNDED')),
        );
      } else {
        await (db.update(db.localSales)..where((s) => s.id.equals(saleId))).write(
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

  Future<List<LocalCategory>> getCategories({bool includeInactive = false}) async {
    final query = db.select(db.localCategories);
    if (!includeInactive) {
      query.where((c) => c.isActive.equals(true));
    }
    query.orderBy([(c) => OrderingTerm.asc(c.name)]);
    return await query.get();
  }

  Future<LocalCategory?> getCategoryById(String id) async {
    return (db.select(db.localCategories)..where((c) => c.id.equals(id))).getSingleOrNull();
  }

  Future<LocalCategory> createCategory({
    required String name,
    String? parentId,
  }) async {
    final trimName = name.trim();
    if (trimName.isEmpty) {
      throw ArgumentError('Kategori adı boş olamaz.');
    }
    final now = DateTime.now();
    final catId = 'cat_${now.microsecondsSinceEpoch}_${_nextUniqueToken()}';

    final category = LocalCategoriesCompanion(
      id: Value(catId),
      name: Value(trimName),
      parentId: Value(parentId),
      isActive: const Value(true),
      createdAt: Value(now),
      updatedAt: Value(now),
    );

    await db.into(db.localCategories).insert(category);
    return (await getCategoryById(catId))!;
  }

  Future<void> updateCategory({
    required String id,
    required String name,
    String? parentId,
    bool? isActive,
  }) async {
    final trimName = name.trim();
    if (trimName.isEmpty) {
      throw ArgumentError('Kategori adı boş olamaz.');
    }
    final now = DateTime.now();
    await (db.update(db.localCategories)..where((c) => c.id.equals(id))).write(
      LocalCategoriesCompanion(
        name: Value(trimName),
        parentId: Value(parentId),
        isActive: isActive != null ? Value(isActive) : const Value.absent(),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> deactivateCategory(String id) async {
    // BR-PROD-14: Kategoriler fiziksel silinmez, pasife alınır
    await (db.update(db.localCategories)..where((c) => c.id.equals(id))).write(
      LocalCategoriesCompanion(
        isActive: const Value(false),
        updatedAt: Value(DateTime.now()),
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
      query.where((p) => p.name.like('%$trimmed%') | p.barcode.like('%$trimmed%') | p.id.like('%$trimmed%'));
    }
    query.orderBy([(p) => OrderingTerm.asc(p.name)]);
    query.limit(limit, offset: offset);
    return await query.get();
  }

  Future<LocalProduct?> getProductById(String id) async {
    return (db.select(db.localProducts)..where((p) => p.id.equals(id))).getSingleOrNull();
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
    int? initialPurchasePrice, // Kuruş, stok birimi başına (BASLANGIC_STOK hareketine yazılır)
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
      throw ArgumentError('Satış fiyatı sıfırdan büyük olmalıdır (BR-PROD-01).');
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
          throw ArgumentError('Bu barkod zaten başka bir ürüne kayıtlıdır: $trimBarcode (BR-PROD-02)');
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
          throw ArgumentError('Satış fiyatı sıfırdan büyük olmalıdır (BR-PROD-01).');
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
            reason: Value(priceChangeReason ?? 'Kullanıcı fiyat güncellemesi'),
            changedAt: Value(now),
          ),
        );
      }

      // Barkod kontrolü
      if (barcode != null && barcode.trim() != (current.barcode ?? '')) {
        final trimBarcode = barcode.trim();
        if (trimBarcode.isNotEmpty) {
          final existing = await (db.select(db.localProductBarcodes)
                ..where((b) => b.barcode.equals(trimBarcode) & b.productId.equals(id).not()))
              .getSingleOrNull();
          if (existing != null) {
            throw ArgumentError('Bu barkod zaten başka bir ürüne kayıtlıdır: $trimBarcode (BR-PROD-02)');
          }

          // Önceki barkodu pasife al veya birincil yap
          final currentBarcode = await (db.select(db.localProductBarcodes)
                ..where((b) => b.productId.equals(id) & b.barcode.equals(trimBarcode)))
              .getSingleOrNull();

          if (currentBarcode != null) {
            // Zaten bu ürüne ait alternatif barkod, primary yap
            await (db.update(db.localProductBarcodes)..where((b) => b.productId.equals(id))).write(
              const LocalProductBarcodesCompanion(isPrimary: Value(false)),
            );
            await (db.update(db.localProductBarcodes)..where((b) => b.id.equals(currentBarcode.id))).write(
              const LocalProductBarcodesCompanion(isPrimary: Value(true), isActive: Value(true)),
            );
          } else {
            // Yeni barkod ekle
            await (db.update(db.localProductBarcodes)..where((b) => b.productId.equals(id))).write(
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
        }
      }

      await (db.update(db.localProducts)..where((p) => p.id.equals(id))).write(
        LocalProductsCompanion(
          name: name != null && name.trim().isNotEmpty ? Value(name.trim()) : const Value.absent(),
          price: price != null ? Value(price) : const Value.absent(),
          priceVersionId: Value(newPriceVersionId),
          categoryId: categoryId != null ? Value(categoryId) : const Value.absent(),
          barcode: barcode != null ? Value(barcode.trim()) : const Value.absent(),
          stockUnit: stockUnit != null ? Value(stockUnit) : const Value.absent(),
          pricingUnit: pricingUnit != null ? Value(pricingUnit) : const Value.absent(),
          conversionFactorNumerator: conversionFactorNumerator != null ? Value(conversionFactorNumerator) : const Value.absent(),
          conversionFactorDenominator: conversionFactorDenominator != null ? Value(conversionFactorDenominator) : const Value.absent(),
          vatRate: vatRate != null ? Value(vatRate) : const Value.absent(),
          isActive: isActive != null ? Value(isActive) : const Value.absent(),
          updatedAt: Value(now),
        ),
      );

      final updatedProduct = (await getProductById(id))!;

      // Outbox kaydı: PRODUCT_UPSERT
      if (deviceId != null && deviceId.isNotEmpty) {
        final barcodes = await getBarcodesForProduct(id);
        final barcodeList = barcodes.map((b) => b.barcode).toList();
        if (updatedProduct.barcode != null && !barcodeList.contains(updatedProduct.barcode)) {
          barcodeList.add(updatedProduct.barcode!);
        }
        await _enqueueProductUpsertOutbox(
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
        await _enqueueProductUpsertOutbox(
          product: product,
          barcodes: barcodeList,
          deviceId: deviceId,
          occurredAt: now,
        );
      }
    });
  }

  /// Ürün oluşturma veya güncelleme işlemini atomik olarak Outbox tablosuna yazar
  Future<void> _enqueueProductUpsertOutbox({
    required LocalProduct product,
    required List<String> barcodes,
    required String deviceId,
    required DateTime occurredAt,
  }) async {
    final nextSeq = await _allocateNextClientSeq(deviceId, occurredAt: occurredAt);

    final effectiveBarcode = product.barcode ?? (barcodes.isNotEmpty ? barcodes.first : null);

    final outboxPayload = {
      'client_seq': nextSeq,
      'operation_id': 'op_prod_${product.id}_$nextSeq',
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
        operationId: Value('op_prod_${product.id}_$nextSeq'),
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
    final hubRows = await db.customSelect('SELECT product_id FROM local_hub_synced_products;').get();
    final hubSyncedIds = hubRows.map((r) => r.read<String>('product_id')).toSet();
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
      } catch (_) {}
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
  }) async {
    final trimBc = barcode.trim();
    if (trimBc.isEmpty) {
      throw ArgumentError('Barkod boş olamaz.');
    }
    await db.transaction(() async {
      final existing = await (db.select(db.localProductBarcodes)..where((b) => b.barcode.equals(trimBc))).getSingleOrNull();
      if (existing != null) {
        throw ArgumentError('Bu barkod zaten kayıtlıdır: $trimBc (BR-PROD-02)');
      }
      final now = DateTime.now();
      final uniqueToken = _nextUniqueToken();
      if (isPrimary) {
        await (db.update(db.localProductBarcodes)..where((b) => b.productId.equals(productId))).write(
          const LocalProductBarcodesCompanion(isPrimary: Value(false)),
        );
        await (db.update(db.localProducts)..where((p) => p.id.equals(productId))).write(
          LocalProductsCompanion(barcode: Value(trimBc), updatedAt: Value(now)),
        );
      }
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
    });
  }

  Future<void> removeProductBarcode(String barcodeId) async {
    // BR-PROD-15: Barkod tarihçesi korunur, pasife alınır
    await (db.update(db.localProductBarcodes)..where((b) => b.id.equals(barcodeId))).write(
      const LocalProductBarcodesCompanion(
        isActive: Value(false),
        isPrimary: Value(false),
      ),
    );
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
      throw ArgumentError('Stok giriş miktarı sıfırdan büyük ve üst sınırın altında olmalıdır: $quantityMilli');
    }
    if (unitPurchasePrice != null &&
        (unitPurchasePrice < 0 || unitPurchasePrice > _maxAmountCents)) {
      throw ArgumentError('Alış fiyatı geçersiz: $unitPurchasePrice');
    }
    final cleanNote = note?.trim();
    if (cleanNote != null && cleanNote.length > 200) {
      throw ArgumentError('Stok girişi açıklaması en fazla 200 karakter olabilir.');
    }
    final effectiveNote = (cleanNote == null || cleanNote.isEmpty) ? null : cleanNote;
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
        throw ArgumentError('Stok artışı 64-bit tamsayı sınırını aşıyor: ${product.name}');
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
      final nextSeq = await _allocateNextClientSeq(deviceId, occurredAt: timestamp);
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
              payloadHash: Value(sha256.convert(utf8.encode(payloadStr)).toString()),
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
              o.status.isIn(const ['PENDING', 'RETRY', 'IN_PROGRESS', 'FAILED_PERMANENT']) &
              o.operationType.isIn(const ['SALE_CREATE', 'SALE_CANCEL', 'SALE_REFUND', 'STOCK_RECEIPT'])))
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

    final source = HubUrlSource.tryParse(row.source) ?? HubUrlSource.lastVerified;
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
}
