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

  const testDeviceId = 'DEV_TEST_01';

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mms_sales_catalog_test_');
    dbFile = File(p.join(tempDir.path, 'test_client.db'));
    db = ClientDatabase(dbFile);
    repo = ClientStorageRepository(db);
    await repo.initializeDevice(testDeviceId);
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('FAZ 1.4: Kategori ve Ürün Yönetimi', () {
    test('Kategori oluşturma, listeleme, güncelleme ve pasifleştirme', () async {
      final cat = await repo.createCategory(name: 'İçecekler');
      expect(cat.name, equals('İçecekler'));
      expect(cat.isActive, isTrue);

      final subCat = await repo.createCategory(name: 'Gazlı İçecekler', parentId: cat.id);
      expect(subCat.parentId, equals(cat.id));

      final allCats = await repo.getCategories();
      expect(allCats.length, equals(2));

      await repo.updateCategory(id: cat.id, name: 'Soğuk İçecekler');
      final updatedCat = await repo.getCategoryById(cat.id);
      expect(updatedCat?.name, equals('Soğuk İçecekler'));

      await repo.deactivateCategory(subCat.id);
      final activeCats = await repo.getCategories(includeInactive: false);
      expect(activeCats.length, equals(1));
      expect(activeCats.first.id, equals(cat.id));

      final allCatsWithInactive = await repo.getCategories(includeInactive: true);
      expect(allCatsWithInactive.length, equals(2));
    });

    test('Ürün oluşturma, barkod tekilliği ve fiyat geçmişi kaydı (BR-PROD-01..13)', () async {
      final cat = await repo.createCategory(name: 'Temel Gıda');

      final prod = await repo.createProduct(
        name: 'Ekmek 200g',
        price: 1000, // 10.00 TL
        barcode: '8690001',
        categoryId: cat.id,
        initialStock: 50000, // 50 adet
        stockUnit: 'adet',
        pricingUnit: 'adet',
      );

      expect(prod.name, equals('Ekmek 200g'));
      expect(prod.price, equals(1000));
      expect(prod.stock, equals(50000));
      expect(prod.isActive, isTrue);

      // İlk ürün kaydında fiyat geçmişi oluşmalıdır
      final history = await repo.getPriceHistory(prod.id);
      expect(history.length, equals(1));
      expect(history.first.oldPrice, equals(0));
      expect(history.first.newPrice, equals(1000));

      // Aynı barkodla ikinci ürün oluşturulamaz (BR-PROD-02)
      expect(
        () async => await repo.createProduct(
          name: 'Başka Ekmek',
          price: 1200,
          barcode: '8690001',
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Fiyat güncellemesi ve yeni priceVersionId kaydı (BR-PROD-13)
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final updated = await repo.updateProduct(
        id: prod.id,
        price: 1250, // 12.50 TL
        priceChangeReason: 'Maliyet artışı',
      );

      expect(updated.price, equals(1250));
      expect(updated.priceVersionId, isNot(equals(prod.priceVersionId)));

      final updatedHistory = await repo.getPriceHistory(prod.id);
      expect(updatedHistory.length, equals(2));
      expect(updatedHistory.first.newPrice, equals(1250));
      expect(updatedHistory.first.oldPrice, equals(1000));
      expect(updatedHistory.first.reason, equals('Maliyet artışı'));

      // Çoklu barkod ekleme
      await repo.addProductBarcode(productId: prod.id, barcode: '8690001_PROMO');
      final barcodes = await repo.getBarcodesForProduct(prod.id);
      expect(barcodes.length, equals(2));

      // Ürün pasifleştirme (Soft delete — BR-PROD-03)
      await repo.deactivateProduct(prod.id);
      final deactivated = await repo.getProductById(prod.id);
      expect(deactivated?.isActive, isFalse);
    });
  });

  group('FAZ 1.3.2, 1.3.3, 1.3.4: Satış Geçmişi, İptal ve İade', () {
    late LocalProduct milkProd;
    late LocalProduct breadProd;

    setUp(() async {
      milkProd = await repo.createProduct(
        name: 'Günlük Süt 1L',
        price: 3000, // 30.00 TL
        barcode: '8690002',
        initialStock: 100000, // 100 adet
      );

      breadProd = await repo.createProduct(
        name: 'Somun Ekmek',
        price: 1000, // 10.00 TL
        barcode: '8690003',
        initialStock: 50000, // 50 adet
      );
    });

    test('Satış geçmişi ve fiş detayları doğru döner (FAZ 1.3.2)', () async {
      final saleRes = await repo.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [
          CartItemInput.units(milkProd.id, 2), // 2 adet süt = 60.00 TL
          CartItemInput.units(breadProd.id, 1), // 1 adet ekmek = 10.00 TL
        ],
      );

      expect(saleRes.totalAmount, equals(7000));

      final history = await repo.getSalesHistory(paymentMethod: 'CASH');
      expect(history.length, equals(1));
      expect(history.first.id, equals(saleRes.saleId));
      expect(history.first.totalAmount, equals(7000));

      final detail = await repo.getSaleDetail(saleRes.saleId);
      expect(detail, isNotNull);
      expect(detail!.items.length, equals(2));
      expect(detail.netAmount, equals(7000));
      expect(detail.refunds.isEmpty, isTrue);
    });

    test('Tam Satış İptali: Stok iadesi, durum güncellemesi ve Outbox kaydı (FAZ 1.3.3)', () async {
      final initialMilkStock = (await repo.getProductById(milkProd.id))!.stock;

      final saleRes = await repo.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CARD',
        items: [CartItemInput.units(milkProd.id, 2)],
      );

      final milkStockAfterSale = (await repo.getProductById(milkProd.id))!.stock;
      expect(milkStockAfterSale, equals(initialMilkStock - 2000));

      // Satışı iptal et (BR-POS-08)
      await repo.cancelSale(
        saleId: saleRes.saleId,
        reason: 'Müşteri karttan çekilmediğini iddia etti, vazgeçti',
        deviceId: testDeviceId,
      );

      final cancelledSale = (await repo.getSaleDetail(saleRes.saleId))?.sale;
      expect(cancelledSale?.status, equals('CANCELLED'));
      expect(cancelledSale?.cancelReason, contains('Müşteri karttan'));
      expect(cancelledSale?.cancelledAt, isNotNull);

      // Stok iade kontrolü: 2000 milli-birim geri eklenmeli
      final milkStockAfterCancel = (await repo.getProductById(milkProd.id))!.stock;
      expect(milkStockAfterCancel, equals(initialMilkStock));

      // Mükerrer iptal engellenir
      expect(
        () async => await repo.cancelSale(
          saleId: saleRes.saleId,
          reason: 'İkinci kez iptal',
          deviceId: testDeviceId,
        ),
        throwsA(isA<StateError>()),
      );

      // Outbox'ta SALE_CANCEL operasyonu bulunmalı
      final outbox = await repo.getUnsyncedOutboxOperations(testDeviceId);
      expect(outbox.any((o) => o.operationType == 'SALE_CANCEL'), isTrue);
    });

    test('Kısmi İade: Satılabilir ürün stoku artırır, Outbox kaydı ekler (FAZ 1.3.4)', () async {
      final initialMilkStock = (await repo.getProductById(milkProd.id))!.stock;

      final saleRes = await repo.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [
          CartItemInput.units(milkProd.id, 3), // 3 adet = 90.00 TL
        ],
      );

      final detail = await repo.getSaleDetail(saleRes.saleId);
      final saleItemId = detail!.items.first.id;

      // 1 adet süt iadesi (Satılabilir / SELLABLE)
      final refundId = await repo.refundSale(
        saleId: saleRes.saleId,
        items: [
          RefundItemInput(
            saleItemId: saleItemId,
            quantity: 1000, // 1 adet
            productCondition: 'SELLABLE',
          ),
        ],
        reason: 'Fazla almış, ambalaj sağlam',
        deviceId: testDeviceId,
      );

      expect(refundId, isNotEmpty);

      // Stok 1 adet geri artmalı
      final stockAfterRefund = (await repo.getProductById(milkProd.id))!.stock;
      expect(stockAfterRefund, equals(initialMilkStock - 2000));

      final updatedDetail = await repo.getSaleDetail(saleRes.saleId);
      expect(updatedDetail!.totalRefundedAmount, equals(3000)); // 30.00 TL iade
      expect(updatedDetail.netAmount, equals(6000)); // 60.00 TL kalan
      expect(updatedDetail.refundedQuantityFor(saleItemId), equals(1000));
      expect(updatedDetail.returnableQuantityFor(updatedDetail.items.first), equals(2000));

      // İade edilebilir miktardan fazlası talep edilirse hata vermeli
      expect(
        () async => await repo.refundSale(
          saleId: saleRes.saleId,
          items: [
            RefundItemInput(saleItemId: saleItemId, quantity: 2001), // Kalan 2000
          ],
          reason: 'Fazla miktar',
          deviceId: testDeviceId,
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Kalan 2 adedi hasarlı/bozuk olarak iade et (DAMAGED)
      await repo.refundSale(
        saleId: saleRes.saleId,
        items: [
          RefundItemInput(
            saleItemId: saleItemId,
            quantity: 2000,
            productCondition: 'DAMAGED',
          ),
        ],
        reason: 'Sütü açınca bozuk koktuğunu söyledi',
        deviceId: testDeviceId,
      );

      // Hasarlı ürün için satılabilir stok ARTMAZ (BR-POS-10)
      final stockAfterDamaged = (await repo.getProductById(milkProd.id))!.stock;
      expect(stockAfterDamaged, equals(stockAfterRefund)); // Stok değişmemeli

      // Satışın tüm kalemleri iade edildiğinde satış REFUNDED olmalı
      final finalDetail = await repo.getSaleDetail(saleRes.saleId);
      expect(finalDetail!.sale.status, equals('REFUNDED'));
      expect(finalDetail.totalRefundedAmount, equals(9000));
      expect(finalDetail.netAmount, equals(0));
    });

    test('Kısmi İade Sonrası Tam Satış İptali: Yalnızca iade edilmemiş miktar stoğa döner', () async {
      final initialMilkStock = (await repo.getProductById(milkProd.id))!.stock;

      // 4 adet süt sat (120 TL)
      final saleRes = await repo.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units(milkProd.id, 4)],
      );

      final detail = await repo.getSaleDetail(saleRes.saleId);
      final saleItemId = detail!.items.first.id;

      // 1 adedini iade et (SELLABLE) -> Stok 1 adet geri artar
      await repo.refundSale(
        saleId: saleRes.saleId,
        items: [
          RefundItemInput(saleItemId: saleItemId, quantity: 1000, productCondition: 'SELLABLE'),
        ],
        reason: '1 adedini hemen iade etti',
        deviceId: testDeviceId,
      );

      final stockAfter1Refund = (await repo.getProductById(milkProd.id))!.stock;
      expect(stockAfter1Refund, equals(initialMilkStock - 3000));

      // Şimdi satışı tamamen iptal et -> Yalnızca kalan 3 adet stoğa iade edilmeli!
      // (1 adet zaten daha önce iade edildiği için toplam stok initial'ı aşmamalı)
      await repo.cancelSale(
        saleId: saleRes.saleId,
        reason: 'Fiş komple iptal',
        deviceId: testDeviceId,
      );

      final finalStock = (await repo.getProductById(milkProd.id))!.stock;
      expect(finalStock, equals(initialMilkStock)); // Asla initialStock + 1000 olmamalı!
    });

    test('getRefundTotalsBySaleIds iade toplamlarını doğru toplar', () async {
      expect(await repo.getRefundTotalsBySaleIds(const []), isEmpty);

      final saleWithRefunds = await repo.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CARD',
        items: [CartItemInput.units(milkProd.id, 3)], // 90.00 TL
      );
      final saleWithoutRefunds = await repo.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units(milkProd.id, 1)], // 30.00 TL
      );

      final detail = await repo.getSaleDetail(saleWithRefunds.saleId);
      final itemId = detail!.items.first.id;
      await repo.refundSale(
        saleId: saleWithRefunds.saleId,
        items: [
          RefundItemInput(saleItemId: itemId, quantity: 1000, productCondition: 'SELLABLE'),
        ],
        reason: '1. kısmi iade',
        deviceId: testDeviceId,
      );
      await repo.refundSale(
        saleId: saleWithRefunds.saleId,
        items: [
          RefundItemInput(saleItemId: itemId, quantity: 500, productCondition: 'DAMAGED'),
        ],
        reason: '2. kısmi iade',
        deviceId: testDeviceId,
      );

      final totals = await repo.getRefundTotalsBySaleIds([
        saleWithRefunds.saleId,
        saleWithoutRefunds.saleId,
        'non_existing_sale',
      ]);
      expect(totals[saleWithRefunds.saleId], equals(4500)); // 30.00 + 15.00 TL
      expect(totals.containsKey(saleWithoutRefunds.saleId), isFalse);
      expect(totals.containsKey('non_existing_sale'), isFalse);
    });
  });
}
