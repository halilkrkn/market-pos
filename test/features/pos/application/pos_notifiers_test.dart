import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/features/pos/application/cart_notifier.dart';
import 'package:market_pos/features/pos/application/pos_preferences_notifier.dart';
import 'package:market_pos/features/pos/domain/cart_state.dart';
import 'package:market_pos/features/pos/domain/pos_product.dart';
import 'package:market_pos/features/pos/domain/pos_repository.dart';

class _FakePosRepository implements PosRepository {
  final Map<String, PosProduct> productsByBarcode;
  bool shouldFailSale = false;
  PaymentMethod? lastSubmittedMethod;
  int? lastCashReceivedCents;
  bool? lastExternalPosConfirmed;
  String? lastDeviceId;
  int saleCallCount = 0;

  _FakePosRepository(this.productsByBarcode);

  @override
  Future<BarcodeLookupResult> findByBarcode(String barcode) async {
    final prod = productsByBarcode[barcode];
    if (prod == null) {
      return BarcodeLookupResult.notFoundOffline(barcode);
    }
    if (!prod.isActive) {
      return BarcodeLookupResult.inactiveProduct(prod, barcode);
    }
    return BarcodeLookupResult.found(prod, barcode);
  }

  @override
  Future<List<PosProduct>> searchActiveProducts(
    String query, {
    int limit = 50,
  }) async {
    return productsByBarcode.values
        .where(
          (p) =>
              p.isActive && p.name.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
  }

  @override
  Future<PosCompletedSale> completeOfflineSale({
    required String deviceId,
    required CartState cart,
    required PaymentMethod paymentMethod,
    int? cashReceivedCents,
    required bool externalPosConfirmed,
  }) async {
    saleCallCount++;
    lastDeviceId = deviceId;
    lastSubmittedMethod = paymentMethod;
    lastCashReceivedCents = cashReceivedCents;
    lastExternalPosConfirmed = externalPosConfirmed;
    if (shouldFailSale) {
      throw StateError('Disk I/O hatası');
    }
    return PosCompletedSale(
      saleId: 'csale_test_$saleCallCount',
      deviceId: deviceId,
      clientSeq: saleCallCount,
      totalAmountCents: cart.totalCents,
      paymentMethod: paymentMethod,
      cashReceivedCents: cashReceivedCents,
      cashChangeCents: cashReceivedCents == null
          ? null
          : cashReceivedCents - cart.totalCents,
      operationId: 'op_test_$saleCallCount',
      createdAt: DateTime(2026, 11, 12),
      items: cart.items
          .map(
            (i) => PosCompletedSaleItem(
              productId: i.productId,
              productName: i.productName,
              unitSnapshot: i.pricingUnit,
              unitPriceCents: i.unitPriceCents,
              quantityMilli: i.quantityMilli,
              totalPriceCents: i.lineTotalCents,
            ),
          )
          .toList(),
    );
  }
}

void main() {
  const bread = PosProduct(
    id: 'prod_ekmek',
    primaryBarcode: '8690504018241',
    name: 'Somun Ekmek 200g',
    priceCents: 1250,
    priceVersionId: 'pv_1',
    stockMilli: 5000,
    stockUnit: 'adet',
    pricingUnit: 'adet',
    conversionFactorNumerator: 1,
    conversionFactorDenominator: 1,
    isActive: true,
  );

  const passiveTea = PosProduct(
    id: 'prod_pasif',
    primaryBarcode: '8690009990001',
    name: 'Pasif Çay',
    priceCents: 18500,
    priceVersionId: 'pv_1',
    stockMilli: 10000,
    stockUnit: 'adet',
    pricingUnit: 'adet',
    conversionFactorNumerator: 1,
    conversionFactorDenominator: 1,
    isActive: false,
  );

  group('Application - PosPreferencesNotifier (OD-04)', () {
    test(
      'Sanal numpad varsayılan olarak kapalı başlar ve toggle edilebilir',
      () {
        final prefs = PosPreferencesNotifier();
        expect(prefs.state.showVirtualNumpad, isFalse);

        prefs.toggleVirtualNumpad();
        expect(prefs.state.showVirtualNumpad, isTrue);

        prefs.setVirtualNumpad(false);
        expect(prefs.state.showVirtualNumpad, isFalse);
      },
    );
  });

  group('Application - CartNotifier', () {
    late _FakePosRepository repo;
    late CartNotifier notifier;
    var refreshCallCount = 0;

    setUp(() {
      refreshCallCount = 0;
      repo = _FakePosRepository({
        '8690504018241': bread,
        '8690009990001': passiveTea,
      });
      notifier = CartNotifier(
        repository: repo,
        readDeviceId: () => 'POS-WIN-01',
        onSaleCommitted: () async {
          refreshCallCount++;
        },
      );
    });

    test('Bilinen barkod eklenir, tekrarında satır birleşir; bilinmeyen/pasif reddedilir', () async {
      final ok1 = await notifier.scanBarcode('8690504018241');
      final ok2 = await notifier.scanBarcode('8690504018241');

      expect(ok1, isTrue);
      expect(ok2, isTrue);
      expect(notifier.state.items.length, equals(1));
      expect(notifier.state.items.single.quantityMilli, equals(2000));
      expect(notifier.state.totalCents, equals(2500));

      // Bilinmeyen barkod (OD-03)
      final unknownOk = await notifier.scanBarcode('8699999999999');
      expect(unknownOk, isFalse);
      expect(notifier.state.errorMessage, contains('Master Hub'));
      expect(notifier.state.items.length, equals(1));

      // Pasif ürün (R-01)
      final passiveOk = await notifier.scanBarcode('8690009990001');
      expect(passiveOk, isFalse);
      expect(notifier.state.errorMessage, contains('Pasif'));
      expect(notifier.state.items.length, equals(1));
    });

    test('F2 miktar güncelleme geçersiz girdide sepeti bozmaz, 0 girişinde satırı siler', () async {
      await notifier.scanBarcode('8690504018241');

      final invalidUpdate = notifier.updateQuantityFromInput(
        productId: 'prod_ekmek',
        rawQuantity: '1.2345',
      );
      expect(invalidUpdate, isFalse);
      expect(notifier.state.items.single.quantityMilli, equals(1000));
      expect(notifier.state.errorMessage, isNotNull);

      final validFractional = notifier.updateQuantityFromInput(
        productId: 'prod_ekmek',
        rawQuantity: '0.5',
      );
      expect(validFractional, isTrue);
      expect(notifier.state.items.single.quantityMilli, equals(500));
      expect(notifier.state.totalCents, equals(625));

      final zeroRemoves = notifier.updateQuantityFromInput(
        productId: 'prod_ekmek',
        rawQuantity: '0',
      );
      expect(zeroRemoves, isTrue);
      expect(notifier.state.items, isEmpty);
    });

    test('Nakit ve Kart doğrulamaları + başarılı satış sonrası sepet temizleme & refresh', () async {
      await notifier.scanBarcode('8690504018241'); // 1250 kr

      // Eksik nakit engellenir
      final shortCash = await notifier.completeSale(
        paymentMethod: PaymentMethod.cash,
        cashReceivedCents: 1000,
      );
      expect(shortCash, isNull);
      expect(repo.saleCallCount, equals(0));
      expect(notifier.state.errorMessage, isNotNull);

      // Kart manuel teyit olmadan engellenir
      final unconfirmedCard = await notifier.completeSale(
        paymentMethod: PaymentMethod.card,
        externalPosConfirmed: false,
      );
      expect(unconfirmedCard, isNull);
      expect(repo.saleCallCount, equals(0));

      // Geçerli nakit satış
      final completedCash = await notifier.completeSale(
        paymentMethod: PaymentMethod.cash,
        cashReceivedCents: 2000,
      );
      expect(completedCash, isNotNull);
      expect(completedCash!.cashChangeCents, equals(750));
      expect(repo.lastDeviceId, equals('POS-WIN-01'));
      expect(repo.lastSubmittedMethod, equals(PaymentMethod.cash));
      expect(notifier.state.items, isEmpty);
      expect(refreshCallCount, equals(1));

      // Repository hata verdiğinde sepet korunur
      await notifier.scanBarcode('8690504018241');
      repo.shouldFailSale = true;
      final failedCard = await notifier.completeSale(
        paymentMethod: PaymentMethod.card,
        externalPosConfirmed: true,
      );
      expect(failedCard, isNull);
      expect(notifier.state.items.length, equals(1));
      expect(notifier.state.isProcessing, isFalse);
      expect(notifier.state.errorMessage, isNotNull);
    });

    test('2. Eş zamanlı iki completeSale çağrısında ikinci satış engellenir', () async {
      final slowRepo = _FakePosRepository({'8690504018241': bread});
      final slowNotifier = CartNotifier(
        repository: _SlowPosRepository(slowRepo),
        readDeviceId: () => 'POS-WIN-01',
      );
      await slowNotifier.scanBarcode('8690504018241');

      final results = await Future.wait([
        slowNotifier.completeSale(
          paymentMethod: PaymentMethod.cash,
          cashReceivedCents: 2000,
        ),
        slowNotifier.completeSale(
          paymentMethod: PaymentMethod.cash,
          cashReceivedCents: 2000,
        ),
      ]);

      final succeeded = results.whereType<PosCompletedSale>().toList();
      expect(succeeded.length, equals(1));
      expect(slowRepo.saleCallCount, equals(1));
      expect(slowNotifier.state.items, isEmpty);
      expect(slowNotifier.state.isProcessing, isFalse);
    });

    test('3. Satış DB kaydı başarılıyken onSaleCommitted callback hatası satışı başarısız göstermez', () async {
      final throwingCallbackNotifier = CartNotifier(
        repository: repo,
        readDeviceId: () => 'POS-WIN-01',
        onSaleCommitted: () async {
          throw StateError('Durum yenileme ağ hatası');
        },
      );
      await throwingCallbackNotifier.scanBarcode('8690504018241');

      final completed = await throwingCallbackNotifier.completeSale(
        paymentMethod: PaymentMethod.card,
        externalPosConfirmed: true,
      );

      expect(completed, isNotNull);
      expect(repo.saleCallCount, equals(1));
      expect(throwingCallbackNotifier.state.items, isEmpty);
      expect(throwingCallbackNotifier.state.errorMessage, isNull);
      expect(throwingCallbackNotifier.state.lastCompletedSale, equals(completed));
    });
  });
}

class _SlowPosRepository implements PosRepository {
  final _FakePosRepository inner;

  _SlowPosRepository(this.inner);

  @override
  Future<BarcodeLookupResult> findByBarcode(String barcode) =>
      inner.findByBarcode(barcode);

  @override
  Future<List<PosProduct>> searchActiveProducts(String query, {int limit = 50}) =>
      inner.searchActiveProducts(query, limit: limit);

  @override
  Future<PosCompletedSale> completeOfflineSale({
    required String deviceId,
    required CartState cart,
    required PaymentMethod paymentMethod,
    int? cashReceivedCents,
    required bool externalPosConfirmed,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 25));
    return inner.completeOfflineSale(
      deviceId: deviceId,
      cart: cart,
      paymentMethod: paymentMethod,
      cashReceivedCents: cashReceivedCents,
      externalPosConfirmed: externalPosConfirmed,
    );
  }
}
