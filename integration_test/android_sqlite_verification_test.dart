import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Android Cihaz Üzerinde Gerçek SQLite Native İşlemleri Doğrulaması', () {
    late LocalDatabaseService dbService;
    late ClientStorageRepository repo;

    setUpAll(() async {
      // 1. Android üzerinde gerçek client_local.db SQLite dosyasını başlat
      dbService = await LocalDatabaseService.initialize();
      repo = dbService.repository;
      await repo.initializeDevice('POS-ANDROID-01');
    });

    tearDownAll(() async {
      await dbService.close();
    });

    testWidgets('1. Kategori İşlemleri (Ekleme, Listeleme)', (tester) async {
      final cat1 = await repo.createCategory(name: 'İçecekler');
      final cat2 = await repo.createCategory(name: 'Unlu Mamuller');

      expect(cat1.id, isNotEmpty);
      expect(cat2.id, isNotEmpty);

      final categories = await repo.getCategories();
      expect(categories.any((c) => c.name == 'İçecekler'), isTrue);
      expect(categories.any((c) => c.name == 'Unlu Mamuller'), isTrue);
    });

    testWidgets('2. Ürün Ekleme, Listeleme ve Güncelleme', (tester) async {
      final categories = await repo.getCategories();
      final beverageCat = categories.firstWhere((c) => c.name == 'İçecekler');

      // Ürün Ekleme
      final product = await repo.createProduct(
        name: 'Doğal Kaynak Suyu 0.5L',
        price: 750, // 7.50 TL = 750 kuruş
        barcode: '8690001000999',
        categoryId: beverageCat.id,
        initialStock: 100000, // 100 adet
      );

      expect(product.id, isNotEmpty);
      expect(product.price, 750);

      // Ürün Listeleme
      final products = await repo.getProducts();
      final found = products.firstWhere((p) => p.id == product.id);
      expect(found.name, 'Doğal Kaynak Suyu 0.5L');
      expect(found.stock, 100000);

      // Ürün Güncelleme (Fiyat & İsim)
      await repo.updateProduct(
        id: product.id,
        name: 'Doğal Kaynak Suyu 0.5L (Cam Şişe)',
        price: 850,
      );

      final updated = await repo.getProductById(product.id);
      expect(updated, isNotNull);
      expect(updated!.name, 'Doğal Kaynak Suyu 0.5L (Cam Şişe)');
      expect(updated.price, 850);
    });

    testWidgets('3. Satış Oluşturma ve Stok Hareketleri', (tester) async {
      final products = await repo.getProducts();
      final product = products.firstWhere(
        (p) => p.name.contains('Doğal Kaynak Suyu'),
      );
      final initialStock = product.stock;

      // 2 adet satış yap (2000 milli-birim)
      final saleRes = await repo.createOfflineSale(
        deviceId: 'POS-ANDROID-01',
        paymentMethod: 'CASH',
        items: [
          CartItemInput.units(product.id, 2),
        ],
      );

      expect(saleRes.saleId, isNotEmpty);
      expect(saleRes.totalAmount, 850 * 2); // 1700 kuruş

      // Stok düşüşünü doğrula (100 - 2 = 98 adet -> 98000)
      final postSaleProduct = await repo.getProductById(product.id);
      expect(postSaleProduct!.stock, initialStock - 2000);

      // Stok hareketlerini doğrula
      final movements = await repo.getStockMovements(productId: product.id);
      expect(movements, isNotEmpty);
      expect(movements.first.quantity, -2000);
      expect(movements.first.movementType, 'SATIS');
    });

    testWidgets('4. Satış Geçmişi, İptal ve İade İşlemleri', (tester) async {
      // Satış Geçmişi Listeleme
      final sales = await repo.getSalesHistory();
      expect(sales, isNotEmpty);
      final lastSale = sales.first;

      // Tam Satış İptali
      await repo.cancelSale(
        saleId: lastSale.id,
        reason: 'Müşteri vazgeçti (Android Test)',
        deviceId: 'POS-ANDROID-01',
      );

      final saleDetail = await repo.getSaleDetail(lastSale.id);
      expect(saleDetail, isNotNull);
      expect(saleDetail!.sale.status, 'CANCELLED');
      expect(saleDetail.sale.cancelReason, 'Müşteri vazgeçti (Android Test)');

      // İptal sonrası stok geri yükleme kontrolü
      final product = await repo.getProductById(saleDetail.items.first.productId);
      expect(product!.stock, 100000); // 98'den tekrar 100'e döndü

      // Yeni bir satış ve Kısmi İade testi
      final newSaleRes = await repo.createOfflineSale(
        deviceId: 'POS-ANDROID-01',
        paymentMethod: 'CARD',
        items: [
          CartItemInput.units(product.id, 3), // 3 adet sat
        ],
      );

      final newSaleDetail = await repo.getSaleDetail(newSaleRes.saleId);
      final saleItemId = newSaleDetail!.items.first.id;

      // 1 adedini iade et
      final refundId = await repo.refundSale(
        saleId: newSaleRes.saleId,
        deviceId: 'POS-ANDROID-01',
        reason: 'Fazla alındı (Android Test)',
        items: [
          RefundItemInput(
            saleItemId: saleItemId,
            quantity: 1000,
            productCondition: 'SELLABLE',
          ),
        ],
      );

      expect(refundId, isNotEmpty);

      final refundedDetail = await repo.getSaleDetail(newSaleRes.saleId);
      expect(refundedDetail!.sale.status, 'COMPLETED'); // Kısmi iade sonrası satış durumu 'COMPLETED' kalır
      expect(refundedDetail.totalRefundedAmount, 850);
      expect(refundedDetail.refunds, isNotEmpty);
      expect(refundedDetail.refunds.first.refund.totalRefundAmount, 850);
    });

    testWidgets('5. Dashboard Verilerinin Yüklenmesi', (tester) async {
      // Dashboard KPI sorgularını doğrudan çalıştır
      final sales = await repo.getSalesHistory();
      final products = await repo.getProducts();

      expect(sales, isNotEmpty);
      expect(products, isNotEmpty);

      int dailyTotal = 0;
      int completedCount = 0;
      for (final s in sales) {
        if (s.status == 'COMPLETED' || s.status == 'REFUNDED') {
          dailyTotal += s.totalAmount;
          completedCount++;
        }
      }

      expect(completedCount, greaterThan(0));
      expect(dailyTotal, greaterThan(0));
    });
  });
}
