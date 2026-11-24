import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('Faz A-1.2 & A-1.3: İkincil Barkod Outbox ve Sınırsız Dashboard Aggregate Testleri', () {
    late Directory tempDir;
    late File dbFile;
    late ClientDatabase db;
    late ClientStorageRepository repo;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mms_test_only_a1_client_');
      dbFile = File(p.join(tempDir.path, 'client_a1.db'));
      db = ClientDatabase(dbFile);
      repo = ClientStorageRepository(db);
      await repo.initializeDevice('POS-WIN-A1');
    });

    tearDown(() async {
      await db.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('addProductBarcode & removeProductBarcode deviceId ile atomik PRODUCT_UPSERT Outbox üretir ve mükerreri reddeder', () async {
      final p1 = await repo.createProduct(
        name: 'İkincil Barkodlu Kahve',
        price: 8500,
        barcode: '8690001110001',
        deviceId: 'POS-WIN-A1',
      );
      final p2 = await repo.createProduct(
        name: 'Diğer Ürün',
        price: 1500,
        barcode: '8690001110009',
        deviceId: 'POS-WIN-A1',
      );

      // Başka ürüne ait barkodu ekleme engellenmeli
      await expectLater(
        () => repo.addProductBarcode(
          productId: p1.id,
          barcode: p2.barcode!,
          deviceId: 'POS-WIN-A1',
        ),
        throwsArgumentError,
      );

      // Geçerli ikincil barkod ekleme -> PRODUCT_UPSERT outbox üretmeli
      await repo.addProductBarcode(
        productId: p1.id,
        barcode: '8690001110002',
        isPrimary: false,
        deviceId: 'POS-WIN-A1',
      );

      // İkincil barkodla ürün bulunabilmeli
      final byAlt = await repo.getProductByBarcode('8690001110002');
      expect(byAlt?.id, equals(p1.id));

      final ops = await (db.select(db.outboxOperations)
            ..where((o) => o.deviceId.equals('POS-WIN-A1'))
            ..orderBy([(o) => OrderingTerm.asc(o.clientSeq)]))
          .get();
      expect(ops.length, equals(3));
      expect(ops[2].operationType, equals('PRODUCT_UPSERT'));
      final upsertPayload = jsonDecode(ops[2].payload) as Map<String, dynamic>;
      expect(
        upsertPayload['product']['barcodes'],
        containsAll(['8690001110001', '8690001110002']),
      );

      // Kaldırıldığında pasife alınmalı ve yeni PRODUCT_UPSERT üretmeli
      final bcList = await repo.getBarcodesForProduct(p1.id);
      final altRow = bcList.firstWhere((b) => b.barcode == '8690001110002');
      await repo.removeProductBarcode(altRow.id, deviceId: 'POS-WIN-A1');

      expect(await repo.getProductByBarcode('8690001110002'), isNull);
      final opsAfterRemove = await (db.select(db.outboxOperations)
            ..where((o) => o.deviceId.equals('POS-WIN-A1'))
            ..orderBy([(o) => OrderingTerm.asc(o.clientSeq)]))
          .get();
      expect(opsAfterRemove.length, equals(4));
      final rmPayload = jsonDecode(opsAfterRemove[3].payload) as Map<String, dynamic>;
      expect(rmPayload['product']['barcodes'], equals(['8690001110001']));
    });

    test('getDashboardProductSummary 500+ ürünü (600 ürün) kesintisiz ve tam sayar', () async {
      final now = DateTime.now();
      await db.transaction(() async {
        // 550 normal stoklu + 50 kritik/negatif stoklu ürün (alfabede Z harfiyle sonda!)
        for (var i = 0; i < 600; i++) {
          final isCritical = i >= 550;
          final isNegative = i >= 590;
          final stockVal = isNegative ? -2000 : (isCritical ? 1000 : 20000);
          await db.into(db.localProducts).insert(
                LocalProductsCompanion.insert(
                  id: 'prod_dash_$i',
                  name: isCritical
                      ? 'ZZKritik Ürün ${i.toString().padLeft(4, '0')}'
                      : 'AAANormal Ürün ${i.toString().padLeft(4, '0')}',
                  barcode: Value('8695000${i.toString().padLeft(6, '0')}'),
                  price: 1000,
                  stock: stockVal,
                  updatedAt: Value(now),
                ),
              );
        }
      });

      final summary = await repo.getDashboardProductSummary(
        criticalStockThresholdMilli: 5000,
        previewLimit: 8,
      );
      expect(summary.activeProductCount, equals(600));
      expect(summary.criticalStockCount, equals(50));
      expect(summary.negativeStockCount, equals(10));
      expect(summary.criticalProducts.length, equals(8));
      expect(summary.criticalProducts.every((p) => p.stock == -2000), isTrue);
    });

    test('getDashboardSalesSummary 2000+ satışı (2050 satış) kesmeden ve iadeleri düşerek toplar', () async {
      final now = DateTime.now();
      final todayLocal = DateTime(now.year, now.month, now.day);
      final noonToday = todayLocal.add(const Duration(hours: 12));

      await db.into(db.localProducts).insert(
            LocalProductsCompanion.insert(
              id: 'prod_bulk_sale',
              name: 'Toplu Satış Ürünü',
              barcode: const Value('8697777000001'),
              price: 1000,
              stock: 5000000,
              updatedAt: Value(now),
            ),
          );

      // 2050 satış: 2048 normal CASH (her biri 1000 kuruş), 1 iptal (1000), 1 kısmi iadeli CARD (3000 - 1000 = 2000)
      await db.transaction(() async {
        for (var i = 1; i <= 2048; i++) {
          await db.into(db.localSales).insert(
                LocalSalesCompanion.insert(
                  id: 'sale_bulk_$i',
                  deviceId: 'POS-WIN-A1',
                  clientSeq: i,
                  totalAmount: 1000,
                  paymentMethod: 'CASH',
                  status: const Value('COMPLETED'),
                  createdAt: Value(noonToday),
                ),
              );
        }
        await db.into(db.localSales).insert(
              LocalSalesCompanion.insert(
                id: 'sale_bulk_2049',
                deviceId: 'POS-WIN-A1',
                clientSeq: 2049,
                totalAmount: 1000,
                paymentMethod: 'CASH',
                status: const Value('CANCELLED'),
                createdAt: Value(noonToday),
              ),
            );
        await db.into(db.localSales).insert(
              LocalSalesCompanion.insert(
                id: 'sale_bulk_2050',
                deviceId: 'POS-WIN-A1',
                clientSeq: 2050,
                totalAmount: 3000,
                paymentMethod: 'CARD',
                status: const Value('PARTIALLY_REFUNDED'),
                createdAt: Value(noonToday),
              ),
            );
        await db.into(db.localRefunds).insert(
              LocalRefundsCompanion.insert(
                id: 'ref_bulk_2050',
                saleId: 'sale_bulk_2050',
                deviceId: 'POS-WIN-A1',
                clientSeq: 2051,
                totalRefundAmount: 1000,
                paymentMethod: 'CARD',
                reason: 'Kısmi iade',
                createdAt: Value(noonToday),
              ),
            );
      });

      final summary = await repo.getDashboardSalesSummary(todayStart: todayLocal);
      // 2048 * 1000 + (3000 - 1000) = 2050000 kuruş, toplam geçerli fiş: 2049
      expect(summary.todaySalesCount, equals(2049));
      expect(summary.todayCashTotalCents, equals(2048000));
      expect(summary.todayCardTotalCents, equals(2000));
      expect(summary.todaySalesTotalCents, equals(2050000));
      expect(summary.dailyTotals.last.totalCents, equals(2050000));
      expect(summary.dailyTotals.last.count, equals(2049));
    });
  });
}
