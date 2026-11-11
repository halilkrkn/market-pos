import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  group('PaymentMethod Kanonik Sözleşmesi - Flutter İstemci Katmanı', () {
    late LocalDatabaseService localDbService;

    setUp(() async {
      localDbService = LocalDatabaseService.forTesting(
        NativeDatabase.memory(),
        path: ':memory:',
      );

      await localDbService.repository.upsertProducts([
        LocalProductsCompanion(
          id: const Value('prod_test_su'),
          barcode: const Value('869000500001'),
          name: const Value('Su 0.5L'),
          price: const Value(500),
          stock: const Value(20000),
          stockUnit: const Value('adet'),
          pricingUnit: const Value('adet'),
          conversionFactorNumerator: const Value(1),
          conversionFactorDenominator: const Value(1),
          isActive: const Value(true),
        ),
      ]);
    });

    tearDown(() async {
      await localDbService.close();
      await LocalDatabaseService.closeActive();
      LocalDatabaseService.resetForTesting();
    });

    test('1. LocalDatabaseService üzerinden CASH ve CARD satışları kanonik Outbox payload ve hash üretir', () async {
      final cashRes = await localDbService.repository.createOfflineSale(
        deviceId: 'POS-WIN-01',
        paymentMethod: PaymentMethod.cash.code,
        items: [CartItemInput.units('prod_test_su', 1)],
      );
      final cardRes = await localDbService.repository.createOfflineSale(
        deviceId: 'POS-WIN-01',
        paymentMethod: PaymentMethod.card.code,
        items: [CartItemInput.units('prod_test_su', 2)],
      );

      expect(cashRes.paymentMethod, equals('CASH'));
      expect(cardRes.paymentMethod, equals('CARD'));

      final outbox = await localDbService.repository.getUnsyncedOutboxOperations('POS-WIN-01');
      expect(outbox.length, equals(2));
      final p0 = jsonDecode(outbox[0].payload) as Map<String, dynamic>;
      final p1 = jsonDecode(outbox[1].payload) as Map<String, dynamic>;
      expect(p0['payment_method'], equals('CASH'));
      expect(p1['payment_method'], equals('CARD'));
      expect(outbox[0].payloadHash, equals(ClientStorageRepository.computeSaleRequestHash(p0)));
      expect(outbox[1].payloadHash, equals(ClientStorageRepository.computeSaleRequestHash(p1)));
    });

    test('2. Geçersiz ödeme yöntemleri (CREDIT_CARD, NAKIT vb.) istemci satış oluşturmada reddedilir', () async {
      for (final bad in ['CREDIT_CARD', 'NAKIT', 'cash', '']) {
        await expectLater(
          () => localDbService.repository.createOfflineSale(
            deviceId: 'POS-WIN-01',
            paymentMethod: bad,
            items: [CartItemInput.units('prod_test_su', 1)],
          ),
          throwsA(isA<ArgumentError>()),
        );
      }

      expect(await localDbService.getLocalSalesCount(), equals(0));
      expect(await localDbService.getPendingOutboxCount(), equals(0));
    });

    test('3. LocalDatabaseService.updateAndRetryFailedOperation eski CREDIT_CARD kaydını CARD olarak atomik onarır', () async {
      await localDbService.repository.initializeDevice('POS-WIN-01');
      final legacyPayload = <String, dynamic>{
        'operation_id': 'op_win_legacy_1',
        'client_seq': 1,
        'total_amount': 500,
        'payment_method': 'CREDIT_CARD',
        'items': [
          {
            'product_id': 'prod_test_su',
            'price_version_id': 'pv_init',
            'quantity': 1000,
            'unit_price': 500,
            'total_price': 500,
            'unit': 'adet',
          }
        ],
      };

      await localDbService.database.into(localDbService.database.localSales).insert(
            LocalSalesCompanion(
              id: const Value('csale_win_legacy_1'),
              deviceId: const Value('POS-WIN-01'),
              clientSeq: const Value(1),
              totalAmount: const Value(500),
              paymentMethod: const Value('CREDIT_CARD'),
              status: const Value('COMPLETED'),
              createdAt: Value(DateTime.now()),
            ),
          );
      await localDbService.database.into(localDbService.database.outboxOperations).insert(
            OutboxOperationsCompanion(
              operationId: const Value('op_win_legacy_1'),
              deviceId: const Value('POS-WIN-01'),
              clientSeq: const Value(1),
              operationType: const Value('SALE_CREATE'),
              payload: Value(jsonEncode(legacyPayload)),
              payloadHash: Value(ClientStorageRepository.computeSaleRequestHash(legacyPayload)),
              occurredAt: Value(DateTime.now()),
              status: const Value('FAILED_PERMANENT'),
              lastError: const Value('Kalıcı Hata [400]: ERR_INVALID_PAYMENT_METHOD'),
            ),
          );

      final repairedPayload = <String, dynamic>{
        ...legacyPayload,
        'payment_method': 'CARD',
      };
      await localDbService.repository.updateAndRetryFailedOperation(
        'op_win_legacy_1',
        correctedPayload: repairedPayload,
      );

      final op = await (localDbService.database.select(localDbService.database.outboxOperations)
            ..where((o) => o.operationId.equals('op_win_legacy_1')))
          .getSingle();
      final sale = await (localDbService.database.select(localDbService.database.localSales)
            ..where((s) => s.id.equals('csale_win_legacy_1')))
          .getSingle();

      expect(op.status, equals('PENDING'));
      expect(op.lastError, isNull);
      expect(op.payloadHash, equals(ClientStorageRepository.computeSaleRequestHash(repairedPayload)));
      expect((jsonDecode(op.payload) as Map<String, dynamic>)['payment_method'], equals('CARD'));
      expect(sale.paymentMethod, equals('CARD'));
    });
  });
}
