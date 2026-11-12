import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/features/pos/domain/cart_item.dart';
import 'package:market_pos/features/pos/domain/cart_state.dart';
import 'package:market_pos/features/pos/domain/money.dart';
import 'package:market_pos/features/pos/domain/pos_exceptions.dart';
import 'package:market_pos/features/pos/domain/pos_product.dart';
import 'package:mms_client_storage/payment_method.dart';

void main() {
  group('Domain - Money & Miktar Hesaplamaları (OD-01)', () {
    test('Half-Up yuvarlama sınır değerlerini kuruş şaşmadan hesaplar', () {
      // (150 * 50) = 7500 -> +500 = 8000 ~/ 1000 = 8 kr (tam 0.500 sınır yukarı)
      expect(
        Money.calculateLineTotalHalfUp(unitPriceCents: 150, quantityMilli: 50),
        equals(8),
      );
      // (250 * 10) = 2500 -> +500 = 3000 ~/ 1000 = 3 kr (Banker's değil Half-Up)
      expect(
        Money.calculateLineTotalHalfUp(unitPriceCents: 250, quantityMilli: 10),
        equals(3),
      );
      // (100 * 4) = 400 -> +500 = 900 ~/ 1000 = 0 kr (0.400 aşağı)
      expect(
        Money.calculateLineTotalHalfUp(unitPriceCents: 100, quantityMilli: 4),
        equals(0),
      );
      // (12550 * 345) = 4329750 -> +500 = 4330250 ~/ 1000 = 4330 kr (43.30 TL)
      expect(
        Money.calculateLineTotalHalfUp(
          unitPriceCents: 12550,
          quantityMilli: 345,
        ),
        equals(4330),
      );
    });

    test('Negatif fiyat veya taşma sınırlarında ArgumentError fırlatır', () {
      expect(
        () => Money.calculateLineTotalHalfUp(
          unitPriceCents: -1,
          quantityMilli: 1000,
        ),
        throwsArgumentError,
      );
      expect(
        () => Money.calculateLineTotalHalfUp(
          unitPriceCents: 1250,
          quantityMilli: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => Money.calculateLineTotalHalfUp(
          unitPriceCents: Money.maxSafeInt,
          quantityMilli: 2000,
        ),
        throwsArgumentError,
      );
    });

    test('formatCents 12.50 TL standardını ve binlik ayracı doğru üretir', () {
      expect(Money.formatCents(0), equals('0.00 TL'));
      expect(Money.formatCents(99), equals('0.99 TL'));
      expect(Money.formatCents(1250), equals('12.50 TL'));
      expect(Money.formatCents(125000), equals('1,250.00 TL'));
      expect(Money.formatCents(1000000), equals('10,000.00 TL'));
      expect(Money.formatCents(-500), equals('-5.00 TL'));
      expect(Money.formatCents(-5), equals('-0.05 TL'));
    });

    test('parseLiraToCents yalnızca geçerli lira metnini kuruşa çevirir', () {
      expect(Money.parseLiraToCents('12.50'), equals(1250));
      expect(Money.parseLiraToCents('12,5'), equals(1250));
      expect(Money.parseLiraToCents('50'), equals(5000));
      expect(Money.parseLiraToCents('1,250.00'), equals(125000));
      expect(Money.parseLiraToCents('1.250,00 TL'), equals(125000));
      expect(Money.parseLiraToCents('0.00'), equals(0));

      expect(() => Money.parseLiraToCents(''), throwsArgumentError);
      expect(() => Money.parseLiraToCents('-10.00'), throwsArgumentError);
      expect(() => Money.parseLiraToCents('12.345'), throwsArgumentError);
      expect(() => Money.parseLiraToCents('1,25.00'), throwsArgumentError);
      expect(() => Money.parseLiraToCents('1,,250.00'), throwsArgumentError);
      expect(() => Money.parseLiraToCents('abc'), throwsArgumentError);
    });

    test('parseQuantityToMilli milli ölçekte (1000) deterministik çalışır', () {
      expect(Money.parseQuantityToMilli('1'), equals(1000));
      expect(Money.parseQuantityToMilli('0.5'), equals(500));
      expect(Money.parseQuantityToMilli('0,345'), equals(345));
      expect(Money.parseQuantityToMilli('0'), equals(0));

      expect(() => Money.parseQuantityToMilli('1.2345'), throwsArgumentError);
      expect(() => Money.parseQuantityToMilli('-1'), throwsArgumentError);
      expect(() => Money.parseQuantityToMilli(''), throwsArgumentError);
    });
  });

  group('Domain - CartState, PaymentMethod & İş Kuralları', () {
    const activeBread = PosProduct(
      id: 'prod_ekmek',
      primaryBarcode: '8690504018241',
      name: 'Somun Ekmek 200g',
      priceCents: 1250,
      priceVersionId: 'pv_1',
      stockMilli: 2000,
      stockUnit: 'adet',
      pricingUnit: 'adet',
      conversionFactorNumerator: 1,
      conversionFactorDenominator: 1,
      isActive: true,
    );

    const passiveProduct = PosProduct(
      id: 'prod_pasif',
      primaryBarcode: '8690009990001',
      name: 'Pasif Ürün',
      priceCents: 5000,
      priceVersionId: 'pv_1',
      stockMilli: 10000,
      stockUnit: 'adet',
      pricingUnit: 'adet',
      conversionFactorNumerator: 1,
      conversionFactorDenominator: 1,
      isActive: false,
    );

    const fractionalDivisibleFailProduct = PosProduct(
      id: 'prod_koli_3',
      primaryBarcode: '8690003330001',
      name: '3lü Paket Bölünmez',
      priceCents: 3000,
      priceVersionId: 'pv_1',
      stockMilli: 9000,
      stockUnit: 'adet',
      pricingUnit: 'koli',
      conversionFactorNumerator: 1,
      conversionFactorDenominator: 3,
      isActive: true,
    );

    test('PaymentMethod yalnızca kanonik CASH ve CARD değerlerini taşır', () {
      expect(PaymentMethod.cash.code, equals('CASH'));
      expect(PaymentMethod.card.code, equals('CARD'));
      expect(() => PaymentMethod.parse('CREDIT_CARD'), throwsArgumentError);
      expect(() => PaymentMethod.parse('NAKIT'), throwsArgumentError);
    });

    test('Aynı ürün tekrar eklendiğinde tek satırda birleşir (BR-POS-02)', () {
      var cart = CartState.empty();
      cart = cart.addProduct(activeBread);
      cart = cart.addProduct(activeBread);

      expect(cart.items.length, equals(1));
      expect(cart.items.first.quantityMilli, equals(2000));
      expect(cart.totalCents, equals(2500));
      expect(cart.selectedProductId, equals('prod_ekmek'));
    });

    test('Pasif ürün sepete eklenemez (BR-PROD-03, R-01)', () {
      final cart = CartState.empty();
      expect(
        () => cart.addProduct(passiveProduct),
        throwsA(isA<PosDomainException>()),
      );
      expect(cart.items, isEmpty);
    });

    test(
      'Birim dönüşüm paydasına tam bölünmeyen miktar sepete alınmaz (R-03)',
      () {
        final cart = CartState.empty();
        expect(
          () => cart.addProduct(
            fractionalDivisibleFailProduct,
            quantityMilli: 1000,
          ),
          throwsA(isA<PosDomainException>()),
        );
        expect(
          cart
              .addProduct(fractionalDivisibleFailProduct, quantityMilli: 3000)
              .items
              .length,
          equals(1),
        );
      },
    );

    test(
      'Eksi stok durumunda uyarı bayrağı açılır ama satış engellenmez (INV-04)',
      () {
        var cart = CartState.empty().addProduct(
          activeBread,
          quantityMilli: 3000,
        );
        final CartItem line = cart.items.single;

        expect(line.projectedRemainingStockMilli, equals(-1000));
        expect(line.isNegativeStockAfterCart, isTrue);
        expect(cart.hasNegativeStockItems, isTrue);
        expect(cart.canCheckout, isTrue);
      },
    );

    test(
      'Miktar 0 yapıldığında satır sepetten kaldırılır ve state immutabledır',
      () {
        final cart1 = CartState.empty().addProduct(
          activeBread,
          quantityMilli: 2000,
        );
        final cart2 = cart1.setQuantity(
          productId: 'prod_ekmek',
          quantityMilli: 0,
        );

        expect(cart1.items.length, equals(1));
        expect(cart2.items, isEmpty);
        expect(cart2.totalCents, equals(0));
        expect(cart2.canCheckout, isFalse);
      },
    );

    test('Toplam 0.00 TL olan sepet ödeme onayına kapatılır', () {
      const freeProduct = PosProduct(
        id: 'prod_free',
        primaryBarcode: '8690000000000',
        name: 'Bedelsiz Poşet',
        priceCents: 0,
        priceVersionId: 'pv_1',
        stockMilli: 10000,
        stockUnit: 'adet',
        pricingUnit: 'adet',
        conversionFactorNumerator: 1,
        conversionFactorDenominator: 1,
        isActive: true,
      );

      final cart = CartState.empty().addProduct(freeProduct);
      expect(cart.totalCents, equals(0));
      expect(cart.canCheckout, isFalse);
    });
  });
}
