
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/features/stock/application/stock_receipt_notifier.dart';
import 'package:market_pos/features/stock/domain/stock_receipt_input.dart';

/// Faz 2 §4.3 — Mevcut ürüne barkodla stok girişi (domain + application, TDD).
void main() {
  group('StockReceiptInput.parse', () {
    test('adet biriminde tam sayı ve TL alış fiyatı kuruşa çevrilir', () {
      final r = StockReceiptInput.parse(
        rawQuantity: '2',
        rawPurchasePrice: '7,50',
        rawNote: '  İrsaliye 42 ',
        stockUnit: 'adet',
      );
      expect(r.isValid, isTrue);
      expect(r.quantityMilli, 2000);
      expect(r.purchasePriceCents, 750);
      expect(r.note, 'İrsaliye 42');
    });

    test('kg biriminde 1,250 kabul edilir; alış fiyatı opsiyoneldir', () {
      final r = StockReceiptInput.parse(
        rawQuantity: '1,250',
        rawPurchasePrice: '',
        stockUnit: 'kg',
      );
      expect(r.isValid, isTrue);
      expect(r.quantityMilli, 1250);
      expect(r.purchasePriceCents, isNull);
    });

    test('Geçersiz miktarlar anlaşılır mesajla reddedilir', () {
      expect(StockReceiptInput.parse(rawQuantity: '', stockUnit: 'adet').errorMessage, isNotNull);
      expect(StockReceiptInput.parse(rawQuantity: '0', stockUnit: 'adet').errorMessage, isNotNull);
      expect(StockReceiptInput.parse(rawQuantity: 'abc', stockUnit: 'adet').errorMessage, isNotNull);
      expect(
        StockReceiptInput.parse(rawQuantity: '1,5', stockUnit: 'adet').errorMessage,
        contains('adet'),
      );
      expect(
        StockReceiptInput.parse(rawQuantity: '1', rawPurchasePrice: 'x', stockUnit: 'adet').errorMessage,
        contains('Alış fiyatı'),
      );
    });
  });

  group('StockReceiptNotifier', () {
    late LocalDatabaseService localDb;
    late StockReceiptNotifier notifier;
    const deviceId = 'POS-AND-STOCK';

    setUp(() async {
      localDb = LocalDatabaseService.forTesting(
        NativeDatabase.memory(),
        path: 'C:\\Users\\Mock\\AppData\\Local\\MarketMMS\\stock_receipt_test.db',
      );
      final repo = localDb.repository;
      await repo.initializeDevice(deviceId);
      await repo.createProduct(
        name: 'Su 0.5L',
        price: 1000,
        barcode: '8690000000011',
        initialStock: 5000,
      );
      notifier = StockReceiptNotifier(repository: repo, readDeviceId: () => deviceId);
    });

    tearDown(() async {
      notifier.dispose();
      await localDb.close();
    });

    test('Barkod okutulunca ürün adı, barkodu ve mevcut stoğu gösterilir', () async {
      await notifier.lookupBarcode(' 8690000000011\n');
      final s = notifier.state;
      expect(s.phase, StockReceiptPhase.productFound);
      expect(s.product!.name, 'Su 0.5L');
      expect(s.product!.stock, 5000);
      expect(s.scannedBarcode, '8690000000011');
    });

    test('Bilinmeyen barkod anlaşılır uyarı ve yeni ürün önerisi üretir', () async {
      await notifier.lookupBarcode('8699999999994');
      expect(notifier.state.phase, StockReceiptPhase.notFound);
      expect(notifier.state.scannedBarcode, '8699999999994');
      expect(notifier.state.message, contains('bulunamadı'));
    });

    test('Kaydet: 5 + 2 = 7, yeni ürün oluşmaz, hareket ve outbox yazılır', () async {
      await notifier.lookupBarcode('8690000000011');
      final ok = await notifier.submit(rawQuantity: '2', rawPurchasePrice: '7,50');

      expect(ok, isTrue);
      expect(notifier.state.phase, StockReceiptPhase.saved);
      expect(notifier.state.product!.stock, 7000);

      final db = localDb.database;
      expect(await db.select(db.localProducts).get(), hasLength(1));
      final movements = await (db.select(db.localStockMovements)
            ..where((m) => m.movementType.equals('GIRIS')))
          .get();
      expect(movements.single.purchasePrice, 750);
      final ops = await (db.select(db.outboxOperations)
            ..where((o) => o.operationType.equals('STOCK_RECEIPT')))
          .get();
      expect(ops.single.deviceId, deviceId);
    });

    test('Kaydet’e çift dokunma tek stok hareketi oluşturur', () async {
      await notifier.lookupBarcode('8690000000011');
      await Future.wait([
        notifier.submit(rawQuantity: '2'),
        notifier.submit(rawQuantity: '2'),
      ]);
      final db = localDb.database;
      final movements = await (db.select(db.localStockMovements)
            ..where((m) => m.movementType.equals('GIRIS')))
          .get();
      expect(movements, hasLength(1));
      expect((await localDb.repository.getProductById(movements.single.productId))!.stock, 7000);
    });

    test('Ardışık iki ayrı giriş iki ayrı hareket olarak saklanır', () async {
      await notifier.lookupBarcode('8690000000011');
      await notifier.submit(rawQuantity: '2');
      await notifier.submit(rawQuantity: '3');
      final db = localDb.database;
      final movements = await (db.select(db.localStockMovements)
            ..where((m) => m.movementType.equals('GIRIS')))
          .get();
      expect(movements, hasLength(2));
      expect(notifier.state.product!.stock, 10000);
    });

    test('Geçersiz miktar hiçbir şey yazmaz ve hata gösterir', () async {
      await notifier.lookupBarcode('8690000000011');
      final ok = await notifier.submit(rawQuantity: '1,5');
      expect(ok, isFalse);
      expect(notifier.state.message, isNotNull);
      expect((await localDb.repository.getProductByBarcode('8690000000011'))!.stock, 5000);
    });

    test('Ürün seçilmeden kaydetme reddedilir', () async {
      expect(await notifier.submit(rawQuantity: '1'), isFalse);
    });
  });
}
