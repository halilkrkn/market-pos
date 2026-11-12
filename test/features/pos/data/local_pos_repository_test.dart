import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/features/pos/data/local_pos_repository.dart';
import 'package:market_pos/features/pos/domain/cart_state.dart';
import 'package:market_pos/features/pos/domain/pos_exceptions.dart';
import 'package:market_pos/features/pos/domain/pos_repository.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  group('Data - LocalPosRepository (Gerçek FFI SQLite WAL Entegrasyonu)', () {
    late Directory tempDir;
    late String dbPath;
    late LocalDatabaseService localDbService;
    late LocalPosRepository repo;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('mms_pos_data_test_');
      dbPath = p.join(tempDir.path, 'client_local.db');
      localDbService = await LocalDatabaseService.initialize(customPath: dbPath);
      repo = LocalPosRepository(localDbService);

      await localDbService.repository.upsertProducts(
        [
          const LocalProductsCompanion(
            id: Value('prod_ekmek'),
            barcode: Value('8690504018241'),
            name: Value('Somun Ekmek 200g'),
            price: Value(1250),
            priceVersionId: Value('pv_ekmek_1'),
            stock: Value(2000), // 2 adet (satış sonrası eksiye düşebilir - allow)
            stockUnit: Value('adet'),
            pricingUnit: Value('adet'),
            conversionFactorNumerator: Value(1),
            conversionFactorDenominator: Value(1),
            isActive: Value(true),
          ),
          const LocalProductsCompanion(
            id: Value('prod_elma'),
            barcode: Value('8690000000100'),
            name: Value('Elma Starking'),
            price: Value(12550),
            priceVersionId: Value('pv_elma_1'),
            stock: Value(5000), // 5.000 kg -> gram veya kg
            stockUnit: Value('kg'),
            pricingUnit: Value('kg'),
            conversionFactorNumerator: Value(1),
            conversionFactorDenominator: Value(1),
            isActive: Value(true),
          ),
          const LocalProductsCompanion(
            id: Value('prod_pasif'),
            barcode: Value('8690009990001'),
            name: Value('Pasif Ürün'),
            price: Value(9900),
            priceVersionId: Value('pv_pasif_1'),
            stock: Value(10000),
            stockUnit: Value('adet'),
            pricingUnit: Value('adet'),
            conversionFactorNumerator: Value(1),
            conversionFactorDenominator: Value(1),
            isActive: Value(false),
          ),
          const LocalProductsCompanion(
            id: Value('prod_koli_24'),
            barcode: Value('8690007770001'),
            name: Value('Gazoz Tekli'),
            price: Value(1500),
            priceVersionId: Value('pv_gazoz_1'),
            stock: Value(24000),
            stockUnit: Value('adet'),
            pricingUnit: Value('kutu'),
            conversionFactorNumerator: Value(1),
            conversionFactorDenominator: Value(1),
            isActive: Value(true),
          ),
        ],
        barcodes: const [
          LocalProductBarcodesCompanion(
            id: Value('bc_ekmek_1'),
            productId: Value('prod_ekmek'),
            barcode: Value('8690504018241'),
            isPrimary: Value(true),
            isActive: Value(true),
          ),
          LocalProductBarcodesCompanion(
            id: Value('bc_ekmek_alt'),
            productId: Value('prod_ekmek'),
            barcode: Value('8690504018249'),
            isPrimary: Value(false),
            isActive: Value(true),
          ),
          LocalProductBarcodesCompanion(
            id: Value('bc_elma_deactivated'),
            productId: Value('prod_elma'),
            barcode: Value('8690000000100'),
            isPrimary: Value(true),
            isActive: Value(false), // Bilinçli pasifleştirilmiş barkod fallback sızdırmamalı
          ),
          LocalProductBarcodesCompanion(
            id: Value('bc_elma_active'),
            productId: Value('prod_elma'),
            barcode: Value('8690000000101'),
            isPrimary: Value(true),
            isActive: Value(true),
          ),
          LocalProductBarcodesCompanion(
            id: Value('bc_pasif_1'),
            productId: Value('prod_pasif'),
            barcode: Value('8690009990001'),
            isPrimary: Value(true),
            isActive: Value(true),
          ),
        ],
      );
    });

    tearDown(() async {
      await localDbService.close();
      await LocalDatabaseService.closeActive();
      LocalDatabaseService.resetForTesting();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('Birincil, alternatif, pasif ve bilinmeyen barkod kurallarını uygular (R-01, OD-03)', () async {
      final byPrimary = await repo.findByBarcode('8690504018241');
      expect(byPrimary.status, equals(BarcodeLookupStatus.found));
      expect(byPrimary.product!.id, equals('prod_ekmek'));

      final byAlt = await repo.findByBarcode('8690504018249');
      expect(byAlt.status, equals(BarcodeLookupStatus.found));
      expect(byAlt.product!.id, equals('prod_ekmek'));

      // Pasifleştirilmiş barkod eski denormalize kolondan sızmamalı
      final byDeactivatedBarcode = await repo.findByBarcode('8690000000100');
      expect(byDeactivatedBarcode.status, equals(BarcodeLookupStatus.notFoundOffline));

      // Aktif ürün ikincil barkodu bulunur
      final byElmaActive = await repo.findByBarcode('8690000000101');
      expect(byElmaActive.status, equals(BarcodeLookupStatus.found));
      expect(byElmaActive.product!.id, equals('prod_elma'));

      // Pasif ürün yakalanır (R-01)
      final byPassiveProduct = await repo.findByBarcode('8690009990001');
      expect(byPassiveProduct.status, equals(BarcodeLookupStatus.inactiveProduct));
      expect(byPassiveProduct.product!.id, equals('prod_pasif'));

      // Bilinmeyen barkod offline ürün oluşturmaz (OD-03)
      final countBefore = await localDbService.getLocalProductsCount();
      final unknown = await repo.findByBarcode('8699999888877');
      expect(unknown.status, equals(BarcodeLookupStatus.notFoundOffline));
      expect(await localDbService.getLocalProductsCount(), equals(countBefore));
    });

    test('searchActiveProducts yalnızca aktif ürünleri isim ve aktif barkoda göre arar', () async {
      final allActive = await repo.searchActiveProducts('');
      expect(allActive.map((e) => e.id), isNot(contains('prod_pasif')));
      expect(allActive.length, equals(3));

      final byAltBarcode = await repo.searchActiveProducts('18249');
      expect(byAltBarcode.map((e) => e.id), equals(['prod_ekmek']));

      final byName = await repo.searchActiveProducts('starking');
      expect(byName.map((e) => e.id), equals(['prod_elma']));

      final passiveQuery = await repo.searchActiveProducts('Pasif');
      expect(passiveQuery, isEmpty);
    });

    test('Atomik satış, eksi stok, snapshot koruma, Half-Up, Outbox PENDING ve restart clientSeq (R-04, R-07)', () async {
      final breadLookup = await repo.findByBarcode('8690504018241');
      final elmaLookup = await repo.findByBarcode('8690000000101');
      final bread = breadLookup.product!;
      final elma = elmaLookup.product!;

      // 3 adet ekmek (stok 2 -> -1 eksiye düşmeli allow) + 0.345 kg elma (4330 kr Half-Up)
      var cart = CartState.empty()
          .addProduct(bread, quantityMilli: 3000) // 3 * 1250 = 3750 kr
          .addProduct(elma, quantityMilli: 345); // Half-Up: 4330 kr
      expect(cart.totalCents, equals(8080));

      // 1. Satış: CASH
      final sale1 = await repo.completeOfflineSale(
        deviceId: 'POS-WIN-01',
        cart: cart,
        paymentMethod: PaymentMethod.cash,
        cashReceivedCents: 10000,
        externalPosConfirmed: false,
      );

      expect(sale1.paymentMethod, equals(PaymentMethod.cash));
      expect(sale1.totalAmountCents, equals(8080));
      expect(sale1.cashReceivedCents, equals(10000));
      expect(sale1.cashChangeCents, equals(1920));
      expect(sale1.clientSeq, equals(1));

      // Fiyat değişse bile satış snapshot'ı korunur (BR-POS-11)
      await localDbService.repository.upsertProducts([
        const LocalProductsCompanion(
          id: Value('prod_ekmek'),
          barcode: Value('8690504018241'),
          name: Value('Somun Ekmek Zamlı'),
          price: Value(2000),
          priceVersionId: Value('pv_ekmek_2'),
          stock: Value(-1000),
          stockUnit: Value('adet'),
          pricingUnit: Value('adet'),
          conversionFactorNumerator: Value(1),
          conversionFactorDenominator: Value(1),
          isActive: Value(true),
        ),
      ]);

      final db = localDbService.database;
      final savedSales = await db.select(db.localSales).get();
      final savedItems = await db.select(db.localSaleItems).get();
      final savedMovements = await db.select(db.localStockMovements).get();
      final outboxOps = await localDbService.repository.getUnsyncedOutboxOperations('POS-WIN-01');
      final breadAfter = await (db.select(db.localProducts)
            ..where((t) => t.id.equals('prod_ekmek')))
          .getSingle();

      expect(savedSales.length, equals(1));
      expect(savedSales.single.paymentMethod, equals('CASH'));
      expect(savedSales.single.totalAmount, equals(8080));
      expect(savedItems.length, equals(2));
      final breadItem = savedItems.firstWhere((i) => i.productId == 'prod_ekmek');
      expect(breadItem.productNameSnapshot, equals('Somun Ekmek 200g'));
      expect(breadItem.unitPrice, equals(1250));
      expect(breadItem.totalPrice, equals(3750));
      expect(breadAfter.stock, equals(-1000)); // eksi stok izinli
      expect(savedMovements.length, equals(2));
      expect(savedMovements.first.movementType, equals('SATIS'));
      expect(outboxOps.length, equals(1));
      expect(outboxOps.single.status, equals('PENDING'));
      final payload1 = jsonDecode(outboxOps.single.payload) as Map<String, dynamic>;
      expect(payload1['payment_method'], equals('CASH'));
      expect(
        outboxOps.single.payloadHash,
        equals(ClientStorageRepository.computeSaleRequestHash(payload1)),
      );

      // Veritabanını kapat ve yeniden aç -> client_seq sürekliliği + 2. CARD satışı (R-07)
      await localDbService.close();
      await LocalDatabaseService.closeActive();
      LocalDatabaseService.resetForTesting();

      localDbService = await LocalDatabaseService.initialize(customPath: dbPath);
      repo = LocalPosRepository(localDbService);

      final breadReloaded = (await repo.findByBarcode('8690504018241')).product!;
      final cart2 = CartState.empty().addProduct(breadReloaded, quantityMilli: 1000);
      final sale2 = await repo.completeOfflineSale(
        deviceId: 'POS-WIN-01',
        cart: cart2,
        paymentMethod: PaymentMethod.card,
        cashReceivedCents: null,
        externalPosConfirmed: true,
      );

      expect(sale2.paymentMethod, equals(PaymentMethod.card));
      expect(sale2.clientSeq, equals(2));
      expect(sale2.totalAmountCents, equals(2000));

      final outboxAfter2 =
          await localDbService.repository.getUnsyncedOutboxOperations('POS-WIN-01');
      expect(outboxAfter2.length, equals(2));
      expect(outboxAfter2.map((e) => e.clientSeq), equals([1, 2]));
      final payload2 = jsonDecode(outboxAfter2[1].payload) as Map<String, dynamic>;
      expect(payload2['payment_method'], equals('CARD'));
      expect(
        outboxAfter2[1].payloadHash,
        equals(ClientStorageRepository.computeSaleRequestHash(payload2)),
      );
    });

    test('Transaction hatasında rollback gerçekleşir ve kısmi kayıt bırakılmaz', () async {
      // Sepete alındıktan sonra ürün DB'de pasife çekilirse createOfflineSale StateError fırlatır
      final gazoz = (await repo.findByBarcode('8690007770001')).product!;
      final cart = CartState.empty().addProduct(gazoz);

      await localDbService.repository.upsertProducts([
        const LocalProductsCompanion(
          id: Value('prod_koli_24'),
          barcode: Value('8690007770001'),
          name: Value('Gazoz Tekli'),
          price: Value(1500),
          priceVersionId: Value('pv_gazoz_1'),
          stock: Value(24000),
          stockUnit: Value('adet'),
          pricingUnit: Value('kutu'),
          conversionFactorNumerator: Value(1),
          conversionFactorDenominator: Value(1),
          isActive: Value(false),
        ),
      ]);

      await expectLater(
        () => repo.completeOfflineSale(
          deviceId: 'POS-WIN-01',
          cart: cart,
          paymentMethod: PaymentMethod.cash,
          cashReceivedCents: 2000,
          externalPosConfirmed: false,
        ),
        throwsA(anyOf(isA<PosDomainException>(), isA<StateError>())),
      );

      expect(await localDbService.getLocalSalesCount(), equals(0));
      expect(await localDbService.getPendingOutboxCount(), equals(0));
      expect(
        await localDbService.database.select(localDbService.database.localSaleItems).get(),
        isEmpty,
      );
      expect(
        await localDbService.database.select(localDbService.database.localStockMovements).get(),
        isEmpty,
      );
    });

    test('Sepet oluşturulduktan sonra ürün fiyatı/sürümü değişirse satış engellenir ve rollback yapılır', () async {
      final bread = (await repo.findByBarcode('8690504018241')).product!;
      final cart = CartState.empty().addProduct(bread, quantityMilli: 2000); // 25.00 TL (1250 kr)

      // Sepet açıkken ürün fiyatı 1250 -> 1900 ve sürümü pv_ekmek_1 -> pv_ekmek_zamli değişir
      await localDbService.repository.upsertProducts([
        const LocalProductsCompanion(
          id: Value('prod_ekmek'),
          barcode: Value('8690504018241'),
          name: Value('Somun Ekmek 200g'),
          price: Value(1900),
          priceVersionId: Value('pv_ekmek_zamli'),
          stock: Value(2000),
          stockUnit: Value('adet'),
          pricingUnit: Value('adet'),
          conversionFactorNumerator: Value(1),
          conversionFactorDenominator: Value(1),
          isActive: Value(true),
        ),
      ]);

      await expectLater(
        () => repo.completeOfflineSale(
          deviceId: 'POS-WIN-01',
          cart: cart,
          paymentMethod: PaymentMethod.cash,
          cashReceivedCents: 3000,
          externalPosConfirmed: false,
        ),
        throwsA(
          isA<PosDomainException>().having(
            (e) => e.message,
            'message',
            contains('değişti'),
          ),
        ),
      );

      expect(await localDbService.getLocalSalesCount(), equals(0));
      expect(await localDbService.getPendingOutboxCount(), equals(0));
    });

    test('searchActiveProducts limit ve SQL LIKE kaçış karakterlerini güvenle uygular', () async {
      final limited = await repo.searchActiveProducts('', limit: 2);
      expect(limited.length, equals(2));

      expect(
        () => repo.searchActiveProducts('', limit: 0),
        throwsArgumentError,
      );

      // % ve _ karakterleri wildcard olarak tüm ürünleri eşleştirmemelidir
      final wildcardQuery = await repo.searchActiveProducts('%');
      expect(wildcardQuery, isEmpty);
    });
  });
}

