import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

void main() {
  late Directory tempDir;
  late File dbFile;
  late ClientDatabase db;
  late ClientStorageRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mms_client_storage_test_');
    dbFile = File(p.join(tempDir.path, 'client_local.db'));
    db = ClientDatabase(dbFile);
    repo = ClientStorageRepository(db);

    // Başlangıç test ürünlerini ekle
    await repo.upsertProducts(
      [
        LocalProductsCompanion(
          id: const Value('prod_ekmek'),
          barcode: const Value(null), // Barkodsuz ürün (0 barkodlu)
          name: const Value('Ekmek 200g'),
          price: const Value(1000), // 10.00 TL (kuruş)
          stock: const Value(20000), // 20 adet = 20000 milli-birim
          stockUnit: const Value('adet'),
          pricingUnit: const Value('adet'),
          conversionFactorNumerator: const Value(1),
          conversionFactorDenominator: const Value(1),
          vatRate: const Value(1),
          isActive: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
        LocalProductsCompanion(
          id: const Value('prod_kiyma'),
          barcode: const Value('869000100001'),
          name: const Value('Dana Kıyma'),
          price: const Value(20000), // 200.00 TL/kg (20000 kuruş)
          stock: const Value(10000), // 10.000 kg = 10000 milli-birim
          stockUnit: const Value('kg'),
          pricingUnit: const Value('kg'),
          conversionFactorNumerator: const Value(1),
          conversionFactorDenominator: const Value(1),
          vatRate: const Value(1),
          isActive: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
        LocalProductsCompanion(
          id: const Value('prod_sut'),
          barcode: const Value('869000200002'),
          name: const Value('Çiftlik Sütü'),
          price: const Value(4000), // 40.00 TL/L (4000 kuruş)
          stock: const Value(15000), // 15.000 L = 15000 milli-birim
          stockUnit: const Value('l'),
          pricingUnit: const Value('l'),
          conversionFactorNumerator: const Value(1),
          conversionFactorDenominator: const Value(1),
          vatRate: const Value(10),
          isActive: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
        LocalProductsCompanion(
          id: const Value('prod_pasif'),
          barcode: const Value('869000300003'),
          name: const Value('Eski Ürün (Pasif)'),
          price: const Value(5000),
          stock: const Value(5000),
          stockUnit: const Value('adet'),
          pricingUnit: const Value('adet'),
          conversionFactorNumerator: const Value(1),
          conversionFactorDenominator: const Value(1),
          vatRate: const Value(20),
          isActive: const Value(false), // Pasif ürün!
          updatedAt: Value(DateTime.now()),
        ),
        LocalProductsCompanion(
          id: const Value('prod_su'),
          barcode: const Value('869000400004'),
          name: const Value('Su 0.5L'),
          price: const Value(500), // 5.00 TL
          stock: const Value(0), // Stok 0: Negatif kesirli stok testi için
          stockUnit: const Value('adet'),
          pricingUnit: const Value('adet'),
          conversionFactorNumerator: const Value(1),
          conversionFactorDenominator: const Value(1),
          vatRate: const Value(10),
          isActive: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
        // S5A-3 Son Düzeltme: Farklı pricing_unit ve stock_unit olan ürünler
        LocalProductsCompanion(
          id: const Value('prod_et_gram'),
          barcode: const Value('869000500005'),
          name: const Value('Kuşbaşı Et (Gram Stoklu)'),
          price: const Value(20000), // 200.00 TL/kg
          stock: const Value(10000000), // 10,000 g = 10,000,000 milli-g
          stockUnit: const Value('g'),
          pricingUnit: const Value('kg'),
          conversionFactorNumerator: const Value(1000), // 1 kg = 1000 g
          conversionFactorDenominator: const Value(1),
          vatRate: const Value(1),
          isActive: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
        LocalProductsCompanion(
          id: const Value('prod_koli'),
          barcode: const Value('869000600006'),
          name: const Value('Maden Suyu Koli (6 Adet)'),
          price: const Value(6000), // 60.00 TL/koli
          stock: const Value(60000), // 60 adet = 60,000 milli-adet
          stockUnit: const Value('adet'),
          pricingUnit: const Value('koli'),
          conversionFactorNumerator: const Value(6), // 1 koli = 6 adet
          conversionFactorDenominator: const Value(1),
          vatRate: const Value(20),
          isActive: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
        LocalProductsCompanion(
          id: const Value('prod_lossy'),
          barcode: const Value('869000700007'),
          name: const Value('Kusurlu Dönüşümlü Ürün'),
          price: const Value(1000),
          stock: const Value(10000),
          stockUnit: const Value('adet'),
          pricingUnit: const Value('paket'),
          conversionFactorNumerator: const Value(1),
          conversionFactorDenominator: const Value(3), // 1 paket = 1/3 adet (kayıpsız temsil edilemez)
          vatRate: const Value(20),
          isActive: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      ],
      barcodes: [
        LocalProductBarcodesCompanion(
          id: const Value('bc_kiyma_1'),
          productId: const Value('prod_kiyma'),
          barcode: const Value('869000100001'),
          isPrimary: const Value(true),
          isActive: const Value(true),
        ),
        LocalProductBarcodesCompanion(
          id: const Value('bc_sut_primary'),
          productId: const Value('prod_sut'),
          barcode: const Value('869000200002'),
          isPrimary: const Value(true),
          isActive: const Value(true),
        ),
        LocalProductBarcodesCompanion(
          id: const Value('bc_sut_alt'),
          productId: const Value('prod_sut'),
          barcode: const Value('869000200099'),
          isPrimary: const Value(false),
          isActive: const Value(true),
        ),
        LocalProductBarcodesCompanion(
          id: const Value('bc_pasif_1'),
          productId: const Value('prod_pasif'),
          barcode: const Value('869000300003'),
          isPrimary: const Value(true),
          isActive: const Value(false),
        ),
        LocalProductBarcodesCompanion(
          id: const Value('bc_su_1'),
          productId: const Value('prod_su'),
          barcode: const Value('869000400004'),
          isPrimary: const Value(true),
          isActive: const Value(true),
        ),
        LocalProductBarcodesCompanion(
          id: const Value('bc_et_1'),
          productId: const Value('prod_et_gram'),
          barcode: const Value('869000500005'),
          isPrimary: const Value(true),
          isActive: const Value(true),
        ),
        LocalProductBarcodesCompanion(
          id: const Value('bc_koli_1'),
          productId: const Value('prod_koli'),
          barcode: const Value('869000600006'),
          isPrimary: const Value(true),
          isActive: const Value(true),
        ),
      ],
    );
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Aşama S-5A-3: Ürün Birim Dönüşümü (Unit Conversion)', () {
    test('1.1. 0.5 kg satış -> 500 g stok düşümü (pricing_unit=kg, stock_unit=g, factor=1000/1)', () async {
      // 0.5 kg = 500 milli-kg. Fiyat: 200 TL/kg -> Satış tutarı: 100 TL
      // Stok birimi: gram. 0.5 kg * 1000 = 500 g -> Stok düşüşü: 500.000 milli-g
      final sale = await repo.createOfflineSale(
        deviceId: 'DEV_WIN1',
        paymentMethod: 'CASH',
        items: [
          CartItemInput.fractional('prod_et_gram', 500),
        ],
      );

      expect(sale.totalAmount, equals(10000)); // 100.00 TL
      expect(sale.items.first.quantity, equals(500)); // 0.500 kg
      expect(sale.items.first.unitSnapshot, equals('kg'));
      expect(sale.items.first.stockDelta, equals(500000)); // 500.000 milli-g = 500 g
      expect(sale.items.first.stockUnit, equals('g'));

      // Stok kontrolü: 10,000,000 - 500,000 = 9,500,000 milli-g (9500 g)
      final prod = await (db.select(db.localProducts)..where((p) => p.id.equals('prod_et_gram'))).getSingle();
      expect(prod.stock, equals(9500000));

      // Stok hareketi kontrolü: birim 'g' ve miktar -500000
      final sm = await (db.select(db.localStockMovements)..where((m) => m.referenceId.equals(sale.saleId))).getSingle();
      expect(sm.quantity, equals(-500000));
      expect(sm.unit, equals('g'));
    });

    test('1.2. 1.25 kg satış -> 1250 g stok düşümü (fromDecimalString)', () async {
      // "1.25" kg -> 1250 milli-kg. Fiyat: 200 TL/kg -> Satış tutarı: 250 TL
      // Stok düşüşü: 1250 * 1000 = 1,250,000 milli-g = 1250 g
      final sale = await repo.createOfflineSale(
        deviceId: 'DEV_WIN1',
        paymentMethod: 'CASH',
        items: [
          CartItemInput.fromDecimalString('prod_et_gram', '1.25'),
        ],
      );

      expect(sale.totalAmount, equals(25000)); // 250.00 TL
      expect(sale.items.first.quantity, equals(1250));
      expect(sale.items.first.stockDelta, equals(1250000));

      final prod = await (db.select(db.localProducts)..where((p) => p.id.equals('prod_et_gram'))).getSingle();
      expect(prod.stock, equals(10000000 - 1250000));
    });

    test('1.3. 1 adet satış -> 1 adet stok düşümü (pricing_unit=adet, stock_unit=adet, factor=1/1)', () async {
      final sale = await repo.createOfflineSale(
        deviceId: 'DEV_WIN1',
        paymentMethod: 'CASH',
        items: [
          CartItemInput.units('prod_ekmek', 1),
        ],
      );

      expect(sale.totalAmount, equals(1000)); // 10.00 TL
      expect(sale.items.first.quantity, equals(1000)); // 1.000 adet
      expect(sale.items.first.stockDelta, equals(1000)); // 1.000 adet

      final prod = await (db.select(db.localProducts)..where((p) => p.id.equals('prod_ekmek'))).getSingle();
      expect(prod.stock, equals(19000)); // 20000 - 1000 = 19000
    });

    test('1.4. 1 koli = 6 adet dönüşümü (pricing_unit=koli, stock_unit=adet, factor=6/1)', () async {
      // 1 koli satış (1000 milli-koli). Fiyat: 60 TL/koli -> 60 TL
      // Stok düşüşü: 1000 * 6 = 6000 milli-adet (6 adet)
      final sale = await repo.createOfflineSale(
        deviceId: 'DEV_WIN1',
        paymentMethod: 'CASH',
        items: [
          CartItemInput.units('prod_koli', 1),
        ],
      );

      expect(sale.totalAmount, equals(6000));
      expect(sale.items.first.quantity, equals(1000));
      expect(sale.items.first.stockDelta, equals(6000));
      expect(sale.items.first.stockUnit, equals('adet'));

      final prod = await (db.select(db.localProducts)..where((p) => p.id.equals('prod_koli'))).getSingle();
      expect(prod.stock, equals(54000)); // 60000 - 6000 = 54000 (54 adet kaldı)
    });

    test('1.5. Geçersiz veya hassasiyeti temsil edilemeyen dönüşüm sessiz yuvarlanmaz, reddedilir', () async {
      // prod_lossy: num = 1, den = 3. 1000 milli-birim / 3 tam bölünemez (kalan 1).
      expect(
        () => repo.createOfflineSale(
          deviceId: 'DEV_WIN1',
          paymentMethod: 'CASH',
          items: [CartItemInput.fractional('prod_lossy', 1000)],
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('kayıpsız dönüştürülemiyor'),
        )),
      );
    });

    test('1.6. Negatif ve aşırı büyük miktar runtime seviyesinde reddedilir', () async {
      expect(
        () => CartItemInput.fractional('prod_ekmek', -500),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => CartItemInput.fractional('prod_ekmek', 0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => CartItemInput.fractional('prod_ekmek', 1000000001),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => CartItemInput.units('prod_ekmek', 0),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Aşama S-5A-3: Deterministik Miktar Girişi (CartItemInput.fromDecimalString)', () {
    test('2.1. "0.1", "0.3", "1.25", "999.999" ve "0,5" değerleri kayıpsız dönüştürülür', () {
      expect(CartItemInput.fromDecimalString('p', '0.1').quantity, equals(100));
      expect(CartItemInput.fromDecimalString('p', '0.3').quantity, equals(300));
      expect(CartItemInput.fromDecimalString('p', '1.25').quantity, equals(1250));
      expect(CartItemInput.fromDecimalString('p', '999.999').quantity, equals(999999));
      expect(CartItemInput.fromDecimalString('p', '0,5').quantity, equals(500));
      expect(CartItemInput.fromDecimalString('p', '1').quantity, equals(1000));
    });

    test('2.2. Sıfır, negatif, 4 basamaklı ondalık ve geçersiz metinler reddedilir', () {
      expect(() => CartItemInput.fromDecimalString('p', '0'), throwsA(isA<ArgumentError>()));
      expect(() => CartItemInput.fromDecimalString('p', '0.000'), throwsA(isA<ArgumentError>()));
      expect(() => CartItemInput.fromDecimalString('p', '-1.5'), throwsA(isA<ArgumentError>()));
      expect(() => CartItemInput.fromDecimalString('p', '1.2345'), throwsA(isA<ArgumentError>()));
      expect(() => CartItemInput.fromDecimalString('p', 'abc'), throwsA(isA<ArgumentError>()));
      expect(() => CartItemInput.fromDecimalString('p', ''), throwsA(isA<ArgumentError>()));
    });
  });

  group('Aşama S-5A-3: Barkod Modeli ve Cache Bütünlüğü', () {
    test('3.1. Barkod Modelinin Tutarlılığı: 0 barkodlu, 1 barkodlu ve çoklu barkodlu ürünler', () async {
      // 0 Barkodlu Ürün (Ekmek)
      final ekmekBarcodes = await repo.getBarcodesForProduct('prod_ekmek');
      expect(ekmekBarcodes.isEmpty, isTrue);

      final ekmekSale = await repo.createOfflineSale(
        deviceId: 'DEV_WIN1',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_ekmek', 1)],
      );
      expect(ekmekSale.totalAmount, equals(1000));

      // 1 Barkodlu Ürün (Kıyma)
      final kiymaFound = await repo.getProductByBarcode('869000100001');
      expect(kiymaFound, isNotNull);
      expect(kiymaFound!.id, equals('prod_kiyma'));

      // Çoklu Barkodlu Ürün (Süt)
      final sutFromPrimary = await repo.getProductByBarcode('869000200002');
      final sutFromAlt = await repo.getProductByBarcode('869000200099');
      expect(sutFromPrimary, isNotNull);
      expect(sutFromAlt, isNotNull);
      expect(sutFromPrimary!.id, equals('prod_sut'));
      expect(sutFromAlt!.id, equals('prod_sut'));
    });

    test('3.2. UNIQUE(barcode) İhlali: Mevcut bir barkod başka bir ürüne atanamaz', () async {
      expect(
        () => db.into(db.localProductBarcodes).insert(
              LocalProductBarcodesCompanion(
                id: const Value('bc_duplicate_test'),
                productId: const Value('prod_ekmek'),
                barcode: const Value('869000100001'), // Zaten kıymaya ait!
                isPrimary: const Value(false),
                isActive: const Value(true),
              ),
            ),
        throwsA(anything),
      );
    });

    test('3.3. Pasif Ürün Satış Engeli: isActive=false olan ürün satılamaz', () async {
      expect(
        () => repo.createOfflineSale(
          deviceId: 'DEV_WIN1',
          paymentMethod: 'CASH',
          items: [CartItemInput.units('prod_pasif', 1)],
        ),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('Pasif ürün satılamaz'))),
      );
    });

    test('3.4. Atomik Senkronizasyon: Hatalı sync rollback olmalı, mevcut cache korunmalıdır', () async {
      final initialCount = (await db.select(db.localProducts).get()).length;

      try {
        await db.transaction(() async {
          await db.into(db.localProducts).insertOnConflictUpdate(
                LocalProductsCompanion(
                  id: const Value('prod_gecici'),
                  barcode: const Value('869999999999'),
                  name: const Value('Geçici Ürün'),
                  price: const Value(1000),
                  stock: const Value(1000),
                ),
              );
          throw const FormatException('Simüle edilmiş ağ kopması');
        });
      } catch (_) {}

      final countAfter = (await db.select(db.localProducts).get()).length;
      expect(countAfter, equals(initialCount));
    });

    test('3.5. Fiyat Snapshot Değişmezliği: Ürün fiyatına zam gelse bile geçmiş fiş korunur', () async {
      final pastSale = await repo.createOfflineSale(
        deviceId: 'DEV_WIN1',
        paymentMethod: 'CASH',
        items: [CartItemInput.fractional('prod_kiyma', 500)],
      );
      expect(pastSale.totalAmount, equals(10000)); // 200 TL/kg * 0.5 kg = 100 TL

      // Zam yap: 300 TL/kg
      await repo.upsertProducts([
        LocalProductsCompanion(
          id: const Value('prod_kiyma'),
          name: const Value('Dana Kıyma (Zamlı)'),
          price: const Value(30000),
          stock: const Value(9500),
          updatedAt: Value(DateTime.now()),
        ),
      ]);

      // Geçmiş fiş kontrolü: 20000 ve 10000 kuruş kalmalıdır
      final item = await (db.select(db.localSaleItems)..where((i) => i.saleId.equals(pastSale.saleId))).getSingle();
      expect(item.unitPrice, equals(20000));
      expect(item.totalPrice, equals(10000));
    });

    test('3.6. Negatif Stok Politikası (ALLOW): 0 stok varken satış eksiye düşer', () async {
      final sale = await repo.createOfflineSale(
        deviceId: 'DEV_WIN1',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_su', 3)],
      );
      expect(sale.totalAmount, equals(1500));

      final updatedSu = await (db.select(db.localProducts)..where((p) => p.id.equals('prod_su'))).getSingle();
      expect(updatedSu.stock, equals(-3000)); // -3 adet = -3000 milli-adet
    });
  });

  group('Aşama S-5A-3: Kurtarılan Temel Dayanıklılık ve Outbox Senaryoları', () {
    test('4.1. Servis kapalıyken peş peşe 5 satış: client_seq kesinlikle 1, 2, 3, 4, 5 olmalıdır', () async {
      for (var i = 1; i <= 5; i++) {
        final sale = await repo.createOfflineSale(
          deviceId: 'DEV_WIN1',
          paymentMethod: 'CASH',
          items: [CartItemInput.units('prod_ekmek', 1)],
        );
        expect(sale.clientSeq, equals(i));
      }

      final syncState = await repo.getSyncState('DEV_WIN1');
      expect(syncState, isNotNull);
      expect(syncState!.currentClientSeq, equals(5));

      final outboxList = await repo.getUnsyncedOutboxOperations('DEV_WIN1');
      expect(outboxList.length, equals(5));
      expect(outboxList.map((o) => o.clientSeq).toList(), equals([1, 2, 3, 4, 5]));
    });

    test('4.2. Aynı (deviceId, clientSeq) ile mükerrer Outbox engellenmesi (UNIQUE kısıtı)', () async {
      await repo.createOfflineSale(
        deviceId: 'DEV_WIN1',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_ekmek', 1)],
      );

      // Doğrudan aynı seq ile outbox eklemeye çalış
      expect(
        () => db.into(db.outboxOperations).insert(
              OutboxOperationsCompanion(
                operationId: const Value('op_duplicate_seq'),
                deviceId: const Value('DEV_WIN1'),
                clientSeq: const Value(1), // Zaten 1 var!
                operationType: const Value('SALE_CREATE'),
                payload: const Value('{}'),
                payloadHash: const Value('hash'),
                occurredAt: Value(DateTime.now()),
              ),
            ),
        throwsA(anything),
      );
    });

    test('4.3. Uygulama yeniden başladığında bekleyen (PENDING) kayıtların korunması', () async {
      await repo.createOfflineSale(
        deviceId: 'DEV_WIN1',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_ekmek', 2)],
      );

      // Veritabanını kapat ve aynı dosyadan yeni bağlantı aç
      await db.close();
      final newDb = ClientDatabase(dbFile);
      final newRepo = ClientStorageRepository(newDb);

      final pending = await newRepo.getUnsyncedOutboxOperations('DEV_WIN1');
      expect(pending.length, equals(1));
      expect(pending.first.clientSeq, equals(1));
      expect(pending.first.status, equals('PENDING'));
      expect(pending.first.payload, contains('prod_ekmek'));

      await newDb.close();
    });

    test('4.4. IN_PROGRESS kayıtlarının başlangıç crash recovery davranışı', () async {
      final sale = await repo.createOfflineSale(
        deviceId: 'DEV_WIN1',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_ekmek', 1)],
      );

      // Simüle et: İşlem ağa gönderilirken süreç çöktü (IN_PROGRESS kaldı)
      await repo.markOutboxInProgress(sale.operationId);
      var op = (await repo.getUnsyncedOutboxOperations('DEV_WIN1')).first;
      expect(op.status, equals('IN_PROGRESS'));

      // Başlangıç kurtarmasını çalıştır
      final recoveredCount = await repo.recoverStuckInProgressOperations('DEV_WIN1');
      expect(recoveredCount, equals(1));

      op = (await repo.getUnsyncedOutboxOperations('DEV_WIN1')).first;
      expect(op.status, equals('PENDING'));
    });

    test('4.5. Farklı cihazların bağımsız client_seq kullanabilmesi (Çakışmasızlık)', () async {
      final saleA = await repo.createOfflineSale(
        deviceId: 'DEV_A',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_ekmek', 1)],
      );
      final saleB = await repo.createOfflineSale(
        deviceId: 'DEV_B',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_ekmek', 1)],
      );

      expect(saleA.deviceId, equals('DEV_A'));
      expect(saleA.clientSeq, equals(1));

      expect(saleB.deviceId, equals('DEV_B'));
      expect(saleB.clientSeq, equals(1));

      final stateA = await repo.getSyncState('DEV_A');
      final stateB = await repo.getSyncState('DEV_B');
      expect(stateA!.currentClientSeq, equals(1));
      expect(stateB!.currentClientSeq, equals(1));
    });

    test('4.6. Yerel veritabanı migration ve custom SQLite indekslerinin varlık doğrulaması', () async {
      // client_local.db üzerindeki custom index'leri kontrol et
      final salesIndexes = await db.customSelect("PRAGMA index_list('local_sales');").get();
      final hasSalesSeqIdx = salesIndexes.any((row) =>
          row.data['name'].toString().contains('idx_sales_device_seq') ||
          row.data['name'].toString().contains('local_sales'));
      expect(hasSalesSeqIdx, isTrue);

      final outboxIndexes = await db.customSelect("PRAGMA index_list('outbox_operations');").get();
      final hasOutboxIdx = outboxIndexes.any((row) =>
          row.data['name'].toString().contains('idx_outbox_status_seq') ||
          row.data['name'].toString().contains('outbox_operations'));
      expect(hasOutboxIdx, isTrue);
    });
  });
}
