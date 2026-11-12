import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File dbFile;
  late ClientDatabase db;
  late ClientStorageRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mms_reliability_test_');
    dbFile = File(p.join(tempDir.path, 'client_local.db'));
    db = ClientDatabase(dbFile);
    repo = ClientStorageRepository(db);

    await repo.upsertProducts([
      LocalProductsCompanion(
        id: const Value('prod_ekmek'),
        barcode: const Value('8690504018241'),
        name: const Value('Somun Ekmek'),
        price: const Value(1250),
        priceVersionId: const Value('pv_1'),
        stock: const Value(10000),
        stockUnit: const Value('adet'),
        pricingUnit: const Value('adet'),
        conversionFactorNumerator: const Value(1),
        conversionFactorDenominator: const Value(1),
        isActive: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
      LocalProductsCompanion(
        id: const Value('prod_su'),
        barcode: const Value('869000500001'),
        name: const Value('Su 0.5L'),
        price: const Value(500),
        priceVersionId: const Value('pv_su_1'),
        stock: const Value(10000),
        stockUnit: const Value('adet'),
        pricingUnit: const Value('adet'),
        conversionFactorNumerator: const Value(1),
        conversionFactorDenominator: const Value(1),
        isActive: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
      LocalProductsCompanion(
        id: const Value('prod_neg_price'),
        barcode: const Value('8690000000999'),
        name: const Value('Negatif Fiyatlı Ürün'),
        price: const Value(-500),
        priceVersionId: const Value('pv_neg'),
        stock: const Value(5000),
        stockUnit: const Value('adet'),
        pricingUnit: const Value('adet'),
        conversionFactorNumerator: const Value(1),
        conversionFactorDenominator: const Value(1),
        isActive: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
      LocalProductsCompanion(
        id: const Value('prod_min_stock'),
        barcode: const Value('8690000000888'),
        name: const Value('Alt Sınır Stoklu Ürün'),
        price: const Value(1000),
        priceVersionId: const Value('pv_min'),
        stock: const Value(-9223372036854775800),
        stockUnit: const Value('adet'),
        pricingUnit: const Value('adet'),
        conversionFactorNumerator: const Value(1),
        conversionFactorDenominator: const Value(1),
        isActive: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
      LocalProductsCompanion(
        id: const Value('prod_huge_price'),
        barcode: const Value('8690000000777'),
        name: const Value('Taşma Sınırı Ürün'),
        price: const Value(9223372036854775807),
        priceVersionId: const Value('pv_huge'),
        stock: const Value(5000),
        stockUnit: const Value('adet'),
        pricingUnit: const Value('adet'),
        conversionFactorNumerator: const Value(1),
        conversionFactorDenominator: const Value(1),
        isActive: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
      LocalProductsCompanion(
        id: const Value('prod_lossy'),
        barcode: const Value('869000700007'),
        name: const Value('Kayıplı Oran Ürün'),
        price: const Value(1000),
        priceVersionId: const Value('pv_lossy'),
        stock: const Value(5000),
        stockUnit: const Value('adet'),
        pricingUnit: const Value('paket'),
        conversionFactorNumerator: const Value(1),
        conversionFactorDenominator: const Value(3),
        isActive: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    ]);
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Phase 1.2 Reliability - ClientStorageRepository', () {
    test('1. Sepet fiyatı veya priceVersionId DBde değişirse satış sessizce tamamlanmaz', () async {
      // Fiyat değişikliği senaryosu: sepet 1250 kr iken DB 1800 kr olur
      await expectLater(
        () => repo.createOfflineSale(
          deviceId: 'POS-WIN-01',
          paymentMethod: 'CASH',
          items: [
            CartItemInput(
              productId: 'prod_ekmek',
              quantity: 1000,
              expectedUnitPrice: 1100, // DB'de 1250
              expectedPriceVersionId: 'pv_1',
            ),
          ],
        ),
        throwsA(isA<PriceChangedException>()),
      );

      // Aynı fiyat ama farklı priceVersionId senaryosu
      await expectLater(
        () => repo.createOfflineSale(
          deviceId: 'POS-WIN-01',
          paymentMethod: 'CARD',
          items: [
            CartItemInput(
              productId: 'prod_ekmek',
              quantity: 1000,
              expectedUnitPrice: 1250,
              expectedPriceVersionId: 'pv_old', // DB'de pv_1
            ),
          ],
        ),
        throwsA(isA<PriceChangedException>()),
      );

      expect(await db.select(db.localSales).get(), isEmpty);
      expect(await db.select(db.outboxOperations).get(), isEmpty);
    });

    test('4 & 5. Negatif/sıfır miktar ve negatif birim fiyat kesinlikle reddedilir', () async {
      expect(() => CartItemInput(productId: 'prod_ekmek', quantity: 0), throwsArgumentError);
      expect(() => CartItemInput(productId: 'prod_ekmek', quantity: -1000), throwsArgumentError);
      expect(
        () => CartItemInput(
          productId: 'prod_ekmek',
          quantity: CartItemInput.maxQuantity + 1,
        ),
        throwsArgumentError,
      );

      await expectLater(
        () => repo.createOfflineSale(
          deviceId: 'POS-WIN-01',
          paymentMethod: 'CASH',
          items: [CartItemInput.units('prod_neg_price', 1)],
        ),
        throwsArgumentError,
      );

      expect(await db.select(db.localSales).get(), isEmpty);
      expect(await db.select(db.outboxOperations).get(), isEmpty);
    });

    test('6. Integer overflow (fiyat*miktar) ve underflow (stok çıkarma) güvenli reddedilir', () async {
      // Overflow
      await expectLater(
        () => repo.createOfflineSale(
          deviceId: 'POS-WIN-01',
          paymentMethod: 'CASH',
          items: [CartItemInput.units('prod_huge_price', 2)],
        ),
        throwsArgumentError,
      );

      // Underflow: stok -9223372036854775800 iken 1000 düşmek 64-bit alt sınırı aşar
      await expectLater(
        () => repo.createOfflineSale(
          deviceId: 'POS-WIN-01',
          paymentMethod: 'CASH',
          items: [CartItemInput.units('prod_min_stock', 1)],
        ),
        throwsArgumentError,
      );

      expect(await db.select(db.localSales).get(), isEmpty);
      expect(await db.select(db.outboxOperations).get(), isEmpty);
    });

    test('7. Aynı ürünün aynı zaman damgalı farklı satışlarında ve farklı cihazlarda ID çakışması oluşmaz', () async {
      final fixedTime = DateTime.utc(2026, 11, 12, 12, 0, 0);

      final sale1 = await repo.createOfflineSale(
        deviceId: 'POS-WIN-01',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_ekmek', 1)],
        occurredAt: fixedTime,
      );
      final sale2 = await repo.createOfflineSale(
        deviceId: 'POS-WIN-01',
        paymentMethod: 'CARD',
        items: [CartItemInput.units('prod_ekmek', 2)],
        occurredAt: fixedTime,
      );
      final saleOtherDevice = await repo.createOfflineSale(
        deviceId: 'POS-MOB-01',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_ekmek', 1)],
        occurredAt: fixedTime,
      );

      expect(sale1.saleId, isNot(equals(sale2.saleId)));
      expect(sale1.saleId, isNot(equals(saleOtherDevice.saleId)));
      expect(sale1.operationId, isNot(equals(saleOtherDevice.operationId)));

      final allItems = await db.select(db.localSaleItems).get();
      final allMovements = await db.select(db.localStockMovements).get();
      expect(allItems.length, equals(3));
      expect(allMovements.length, equals(3));
    });

    test('8. Duplicate productId transaction açılmadan reddedilir ve kısmi kayıt oluşmaz', () async {
      await expectLater(
        () => repo.createOfflineSale(
          deviceId: 'POS-WIN-01',
          paymentMethod: 'CASH',
          items: [
            CartItemInput.units('prod_ekmek', 1),
            CartItemInput.units('prod_ekmek', 2),
          ],
        ),
        throwsArgumentError,
      );

      expect(await db.select(db.localSales).get(), isEmpty);
      expect(await db.select(db.outboxOperations).get(), isEmpty);
      expect(await repo.getSyncState('POS-WIN-01'), isNull);
    });

    test('12. Çok kalemli transaction ortasında hata oluşursa 1. kalemin stoğu dahi tamamen rollback edilir', () async {
      final ekmekBefore = await (db.select(db.localProducts)
            ..where((t) => t.id.equals('prod_ekmek')))
          .getSingle();

      // 1. kalem geçerli (prod_ekmek), 2. kalem birim bölünememeden hata verir (prod_lossy)
      await expectLater(
        () => repo.createOfflineSale(
          deviceId: 'POS-WIN-01',
          paymentMethod: 'CASH',
          items: [
            CartItemInput.units('prod_ekmek', 2),
            CartItemInput.units('prod_lossy', 1),
          ],
        ),
        throwsArgumentError,
      );

      final ekmekAfter = await (db.select(db.localProducts)
            ..where((t) => t.id.equals('prod_ekmek')))
          .getSingle();
      expect(ekmekAfter.stock, equals(ekmekBefore.stock));
      expect(await db.select(db.localSales).get(), isEmpty);
      expect(await db.select(db.localSaleItems).get(), isEmpty);
      expect(await db.select(db.localStockMovements).get(), isEmpty);
      expect(await db.select(db.outboxOperations).get(), isEmpty);
    });
  });
}

