import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('PaymentMethod Kanonik Sözleşme Doğrulaması', () {
    test('1. Pure Dart PaymentMethod yalnız CASH ve CARD değerlerini kanonik kabul eder', () {
      expect(PaymentMethod.cash.code, equals('CASH'));
      expect(PaymentMethod.card.code, equals('CARD'));
      expect(PaymentMethod.canonicalCodes, equals(['CASH', 'CARD']));

      expect(PaymentMethod.parse('CASH'), equals(PaymentMethod.cash));
      expect(PaymentMethod.parse('CARD'), equals(PaymentMethod.card));
      expect(PaymentMethod.isCanonical('CASH'), isTrue);
      expect(PaymentMethod.isCanonical('CARD'), isTrue);
      expect(PaymentMethod.tryParse('CARD'), equals(PaymentMethod.card));

      for (final invalid in [
        null,
        '',
        ' ',
        'cash',
        'card',
        'CREDIT_CARD',
        'NAKIT',
        'KART',
        123,
      ]) {
        expect(() => PaymentMethod.parse(invalid), throwsA(isA<ArgumentError>()));
        expect(PaymentMethod.tryParse(invalid), isNull);
        expect(PaymentMethod.isCanonical(invalid), isFalse);
      }

      // Salt-okunur tarihsel sınıflandırıcı eski verileri kaybetmeden okuyabilir
      expect(PaymentMethod.tryParseLegacyReadOnly('CREDIT_CARD'), equals(PaymentMethod.card));
      expect(PaymentMethod.tryParseLegacyReadOnly('NAKIT'), equals(PaymentMethod.cash));
      expect(PaymentMethod.tryParseLegacyReadOnly('CARD'), equals(PaymentMethod.card));
      expect(PaymentMethod.tryParseLegacyReadOnly('UNKNOWN'), isNull);
    });
  });

  group('ClientStorageRepository & Outbox PaymentMethod Sözleşme Testleri', () {
    late Directory tempDir;
    late ClientDatabase db;
    late ClientStorageRepository repo;

    setUp(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      tempDir = await Directory.systemTemp.createTemp('mms_pm_contract_');
      db = ClientDatabase(File(p.join(tempDir.path, 'client_local.db')));
      repo = ClientStorageRepository(db);

      await repo.upsertProducts([
        LocalProductsCompanion(
          id: const Value('prod_ekmek'),
          barcode: const Value('869000100001'),
          name: const Value('Somun Ekmek'),
          price: const Value(1250),
          stock: const Value(50000),
          stockUnit: const Value('adet'),
          pricingUnit: const Value('adet'),
          conversionFactorNumerator: const Value(1),
          conversionFactorDenominator: const Value(1),
          isActive: const Value(true),
        ),
      ]);
    });

    tearDown(() async {
      await db.close();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('2. CASH ve CARD satışları local_sales ve outbox payload içerisine kanonik yazılır ve SHA-256 korunur', () async {
      final cashSale = await repo.createOfflineSale(
        deviceId: 'POS-WIN-01',
        paymentMethod: PaymentMethod.cash.code,
        items: [CartItemInput.units('prod_ekmek', 2)],
      );
      final cardSale = await repo.createOfflineSale(
        deviceId: 'POS-WIN-01',
        paymentMethod: PaymentMethod.card.code,
        items: [CartItemInput.units('prod_ekmek', 1)],
      );

      expect(cashSale.paymentMethod, equals('CASH'));
      expect(cardSale.paymentMethod, equals('CARD'));

      final salesRows = await (db.select(db.localSales)
            ..orderBy([(s) => OrderingTerm.asc(s.clientSeq)]))
          .get();
      expect(salesRows.length, equals(2));
      expect(salesRows[0].paymentMethod, equals('CASH'));
      expect(salesRows[1].paymentMethod, equals('CARD'));

      final outboxRows = await repo.getUnsyncedOutboxOperations('POS-WIN-01');
      expect(outboxRows.length, equals(2));

      for (var i = 0; i < 2; i++) {
        final decoded = jsonDecode(outboxRows[i].payload) as Map<String, dynamic>;
        expect(decoded['payment_method'], equals(i == 0 ? 'CASH' : 'CARD'));
        expect(
          outboxRows[i].payloadHash,
          equals(ClientStorageRepository.computeSaleRequestHash(decoded)),
        );
      }
    });

    test('3. Yeni satışta CREDIT_CARD, NAKIT, küçük harf ve boş değerler reddedilir; DB/Outbox temiz kalır', () async {
      for (final invalidMethod in ['CREDIT_CARD', 'NAKIT', 'cash', 'card', '', 'BANK_TRANSFER']) {
        await expectLater(
          () => repo.createOfflineSale(
            deviceId: 'POS-WIN-01',
            paymentMethod: invalidMethod,
            items: [CartItemInput.units('prod_ekmek', 1)],
          ),
          throwsA(isA<ArgumentError>()),
        );
      }

      expect(await db.select(db.localSales).get(), isEmpty);
      expect(await db.select(db.outboxOperations).get(), isEmpty);
    });

    test('4. Eski kalıcı CREDIT_CARD Outbox kaydı bozulmaz, hash korunur ve ClientSyncService ile veri kaybı olmadan yönetilir', () async {
      await repo.initializeDevice('POS-WIN-01');
      final legacyPayloadMap = {
        'operation_id': 'op_legacy_cc_1',
        'client_seq': 1,
        'total_amount': 1250,
        'payment_method': 'CREDIT_CARD',
        'items': [
          {
            'product_id': 'prod_ekmek',
            'price_version_id': 'pv_init',
            'quantity': 1000,
            'unit_price': 1250,
            'total_price': 1250,
            'unit': 'adet',
          }
        ],
      };
      final legacyPayload = jsonEncode(legacyPayloadMap);
      final legacyHash = ClientStorageRepository.computeSaleRequestHash(legacyPayloadMap);
      final occurredAt = DateTime.now().subtract(const Duration(days: 1));

      await db.into(db.localSales).insert(
            LocalSalesCompanion(
              id: const Value('csale_legacy_cc_1'),
              deviceId: const Value('POS-WIN-01'),
              clientSeq: const Value(1),
              totalAmount: const Value(1250),
              paymentMethod: const Value('CREDIT_CARD'),
              status: const Value('COMPLETED'),
              createdAt: Value(occurredAt),
            ),
          );
      await db.into(db.outboxOperations).insert(
            OutboxOperationsCompanion(
              operationId: const Value('op_legacy_cc_1'),
              deviceId: const Value('POS-WIN-01'),
              clientSeq: const Value(1),
              operationType: const Value('SALE_CREATE'),
              payload: Value(legacyPayload),
              payloadHash: Value(legacyHash),
              occurredAt: Value(occurredAt),
              status: const Value('PENDING'),
            ),
          );

      // Eski kayıt okunurken otomatik dönüştürülmez; hash ve payload olduğu gibi korunur
      final unsyncedBefore = await repo.getUnsyncedOutboxOperations('POS-WIN-01');
      expect(unsyncedBefore.length, equals(1));
      expect(unsyncedBefore.first.payload, equals(legacyPayload));
      expect(unsyncedBefore.first.payloadHash, equals(legacyHash));
      expect(
        PaymentMethod.tryParseLegacyReadOnly(
          (await db.select(db.localSales).getSingle()).paymentMethod,
        ),
        equals(PaymentMethod.card),
      );

      // Senaryo A: Hub tarafından henüz işlenmemiş eski kayıt 400 ile reddedilirse veri silinmeden FAILED_PERMANENT olur
      final transportReject = _FakeSyncTransport(
        nextResponse: const SyncResponse(
          statusCode: 400,
          body: '{"error":"BAD_REQUEST","code":"ERR_INVALID_PAYMENT_METHOD"}',
        ),
      );
      final syncReject = ClientSyncService(
        repository: repo,
        transport: transportReject,
        deviceId: 'POS-WIN-01',
        deviceToken: 'tok',
        hubUrl: 'https://127.0.0.1:8443',
      );

      final failResult = await syncReject.syncPendingOutbox();
      expect(failResult.permanentFailedCount, equals(1));
      expect(transportReject.lastSentPayload, equals(legacyPayload));

      final opAfterReject = await (db.select(db.outboxOperations)
            ..where((o) => o.operationId.equals('op_legacy_cc_1')))
          .getSingle();
      expect(opAfterReject.status, equals('FAILED_PERMANENT'));
      expect(opAfterReject.payloadHash, equals(legacyHash));
      expect((await db.select(db.localSales).get()).length, equals(1));

      // Senaryo B: Operatör/geri yükleme sonrası Hub'da önceden commitlenmiş idempotent replay (200 OK) gelirse SYNCED olur
      await repo.retryFailedPermanentOperation('op_legacy_cc_1');
      final transportReplay = _FakeSyncTransport(
        nextResponse: const SyncResponse(
          statusCode: 200,
          body: '{"status":"COMMITTED","idempotent_replay":true}',
        ),
      );
      final syncReplay = ClientSyncService(
        repository: repo,
        transport: transportReplay,
        deviceId: 'POS-WIN-01',
        deviceToken: 'tok',
        hubUrl: 'https://127.0.0.1:8443',
      );
      final okResult = await syncReplay.syncPendingOutbox();
      expect(okResult.syncedCount, equals(1));

      final opAfterReplay = await (db.select(db.outboxOperations)
            ..where((o) => o.operationId.equals('op_legacy_cc_1')))
          .getSingle();
      expect(opAfterReplay.status, equals('SYNCED'));
    });

    test('5. updateAndRetryFailedOperation: durum/değişmez koruma, tek SQLite transaction, hata anında rollback ve local_sales tutarlılığı', () async {
      await repo.initializeDevice('POS-WIN-01');
      final occurredAt = DateTime.now().subtract(const Duration(hours: 2));
      final legacyPayloadMap = {
        'operation_id': 'op_legacy_repair_1',
        'client_seq': 1,
        'total_amount': 2500,
        'payment_method': 'CREDIT_CARD',
        'items': [
          {
            'product_id': 'prod_ekmek',
            'price_version_id': 'pv_init',
            'quantity': 2000,
            'unit_price': 1250,
            'total_price': 2500,
            'unit': 'adet',
          }
        ],
      };
      final legacyPayload = jsonEncode(legacyPayloadMap);
      final legacyHash = ClientStorageRepository.computeSaleRequestHash(legacyPayloadMap);

      await db.into(db.localSales).insert(
            LocalSalesCompanion(
              id: const Value('csale_legacy_repair_1'),
              deviceId: const Value('POS-WIN-01'),
              clientSeq: const Value(1),
              totalAmount: const Value(2500),
              paymentMethod: const Value('CREDIT_CARD'),
              status: const Value('COMPLETED'),
              createdAt: Value(occurredAt),
            ),
          );
      await db.into(db.localSaleItems).insert(
            LocalSaleItemsCompanion(
              id: const Value('citem_legacy_repair_1'),
              saleId: const Value('csale_legacy_repair_1'),
              productId: const Value('prod_ekmek'),
              productNameSnapshot: const Value('Somun Ekmek'),
              unitSnapshot: const Value('adet'),
              priceVersionId: const Value('pv_init'),
              unitPrice: const Value(1250),
              quantity: const Value(2000),
              totalPrice: const Value(2500),
            ),
          );
      await db.into(db.localStockMovements).insert(
            LocalStockMovementsCompanion(
              id: const Value('csm_legacy_repair_1'),
              productId: const Value('prod_ekmek'),
              quantity: const Value(-2000),
              unit: const Value('adet'),
              movementType: const Value('SATIS'),
              referenceId: const Value('csale_legacy_repair_1'),
              createdAt: Value(occurredAt),
            ),
          );
      await (db.update(db.localProducts)..where((p) => p.id.equals('prod_ekmek')))
          .write(const LocalProductsCompanion(stock: Value(48000)));
      await (db.update(db.clientSyncStates)..where((s) => s.deviceId.equals('POS-WIN-01')))
          .write(const ClientSyncStatesCompanion(currentClientSeq: Value(1)));
      await db.into(db.outboxOperations).insert(
            OutboxOperationsCompanion(
              operationId: const Value('op_legacy_repair_1'),
              deviceId: const Value('POS-WIN-01'),
              clientSeq: const Value(1),
              operationType: const Value('SALE_CREATE'),
              payload: Value(legacyPayload),
              payloadHash: Value(legacyHash),
              occurredAt: Value(occurredAt),
              status: const Value('FAILED_PERMANENT'),
              attemptCount: const Value(1),
              lastError: const Value('Kalıcı Hata [400]: ERR_INVALID_PAYMENT_METHOD'),
            ),
          );

      // İkinci satış (PENDING durumundaki bir kayıt onarıma açık olmamalıdır)
      final cashSale2 = await repo.createOfflineSale(
        deviceId: 'POS-WIN-01',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_ekmek', 1)],
      );
      expect(cashSale2.clientSeq, equals(2));

      final validCardRepairPayload = {
        ...legacyPayloadMap,
        'payment_method': 'CARD',
      };

      // A. Koruma kuralları: bulunmayan kayıt / FAILED_PERMANENT dışı kayıt / kimlik veya yöntem ihlalleri reddedilir
      await expectLater(
        () => repo.updateAndRetryFailedOperation(
          'op_non_existent',
          correctedPayload: {
            ...validCardRepairPayload,
            'operation_id': 'op_non_existent',
          },
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        () => repo.updateAndRetryFailedOperation(
          cashSale2.operationId,
          correctedPayload: {
            'operation_id': cashSale2.operationId,
            'client_seq': 2,
            'total_amount': 1250,
            'payment_method': 'CASH',
            'items': legacyPayloadMap['items'],
          },
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        () => repo.updateAndRetryFailedOperation(
          'op_legacy_repair_1',
          correctedPayload: {
            ...validCardRepairPayload,
            'operation_id': 'op_other',
          },
        ),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        () => repo.updateAndRetryFailedOperation(
          'op_legacy_repair_1',
          correctedPayload: {
            ...validCardRepairPayload,
            'client_seq': 99,
          },
        ),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        () => repo.updateAndRetryFailedOperation(
          'op_legacy_repair_1',
          correctedPayload: Map<String, dynamic>.from(legacyPayloadMap)..remove('payment_method'),
        ),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        () => repo.updateAndRetryFailedOperation(
          'op_legacy_repair_1',
          correctedPayload: {
            ...legacyPayloadMap,
            'payment_method': 'CASH', // CREDIT_CARD -> CASH sessiz dönüşümü yasak
          },
        ),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        () => repo.updateAndRetryFailedOperation(
          'op_legacy_repair_1',
          correctedPayload: {
            ...validCardRepairPayload,
            'total_amount': 9999, // Satış tutarı yerel kayıtla çelişirse transaction rollback çalışır
          },
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Başarısız denemelerden sonra eski payload, hash, statü ve yerel satış korunur
      final opAfterGuards = await (db.select(db.outboxOperations)
            ..where((o) => o.operationId.equals('op_legacy_repair_1')))
          .getSingle();
      expect(opAfterGuards.payload, equals(legacyPayload));
      expect(opAfterGuards.payloadHash, equals(legacyHash));
      expect(opAfterGuards.status, equals('FAILED_PERMANENT'));
      expect(opAfterGuards.attemptCount, equals(1));
      expect(opAfterGuards.lastError, contains('ERR_INVALID_PAYMENT_METHOD'));

      // B. Gerçek SQLite transaction rollback kanıtı:
      // Outbox satırı güncellendikten sonra ikinci adım (local_sales güncellemesi) trigger ile fail ederse
      // tüm transaction ROLLBACK edilmeli, outbox_operations eski payload ve hash ile kalmalıdır.
      await db.customStatement(
        "CREATE TEMP TRIGGER trg_abort_sale_repair BEFORE UPDATE ON local_sales BEGIN SELECT RAISE(ABORT, 'Simüle DB hatası'); END;",
      );

      await expectLater(
        () => repo.updateAndRetryFailedOperation(
          'op_legacy_repair_1',
          correctedPayload: validCardRepairPayload,
        ),
        throwsA(anything),
      );

      final opAfterRollback = await (db.select(db.outboxOperations)
            ..where((o) => o.operationId.equals('op_legacy_repair_1')))
          .getSingle();
      final saleAfterRollback = await (db.select(db.localSales)
            ..where((s) => s.id.equals('csale_legacy_repair_1')))
          .getSingle();
      expect(opAfterRollback.payload, equals(legacyPayload));
      expect(opAfterRollback.payloadHash, equals(legacyHash));
      expect(opAfterRollback.status, equals('FAILED_PERMANENT'));
      expect(opAfterRollback.attemptCount, equals(1));
      expect(opAfterRollback.lastError, contains('ERR_INVALID_PAYMENT_METHOD'));
      expect(saleAfterRollback.paymentMethod, equals('CREDIT_CARD'));

      // C. Engel kaldırılıp kontrollü onarım yapıldığında atomik olarak güncellenir
      await db.customStatement('DROP TRIGGER temp.trg_abort_sale_repair;');

      await repo.updateAndRetryFailedOperation(
        'op_legacy_repair_1',
        correctedPayload: validCardRepairPayload,
      );

      final opRepaired = await (db.select(db.outboxOperations)
            ..where((o) => o.operationId.equals('op_legacy_repair_1')))
          .getSingle();
      final saleRepaired = await (db.select(db.localSales)
            ..where((s) => s.id.equals('csale_legacy_repair_1')))
          .getSingle();
      final expectedRepairedHash = ClientStorageRepository.computeSaleRequestHash(validCardRepairPayload);
      final decodedRepaired = jsonDecode(opRepaired.payload) as Map<String, dynamic>;

      expect(decodedRepaired['payment_method'], equals('CARD'));
      expect(opRepaired.payloadHash, equals(expectedRepairedHash));
      expect(opRepaired.payloadHash, isNot(equals(legacyHash)));
      expect(opRepaired.operationId, equals('op_legacy_repair_1'));
      expect(opRepaired.deviceId, equals('POS-WIN-01'));
      expect(opRepaired.clientSeq, equals(1));
      expect(opRepaired.status, equals('PENDING'));
      expect(opRepaired.attemptCount, equals(0));
      expect(opRepaired.nextRetryAt, isNull);
      expect(opRepaired.lastError, isNull);
      expect(saleRepaired.paymentMethod, equals('CARD'));
      expect(saleRepaired.totalAmount, equals(2500));
    });

    test('6. FIFO bloklama ve onarım sonrası deterministik sırayla (client_seq ASC) senkronizasyon devamı', () async {
      await repo.initializeDevice('POS-WIN-01');
      final occurredAt = DateTime.now().subtract(const Duration(hours: 1));
      final legacyPayloadMap = {
        'operation_id': 'op_fifo_legacy_1',
        'client_seq': 1,
        'total_amount': 1250,
        'payment_method': 'CREDIT_CARD',
        'items': [
          {
            'product_id': 'prod_ekmek',
            'price_version_id': 'pv_init',
            'quantity': 1000,
            'unit_price': 1250,
            'total_price': 1250,
            'unit': 'adet',
          }
        ],
      };

      await db.into(db.localSales).insert(
            LocalSalesCompanion(
              id: const Value('csale_fifo_legacy_1'),
              deviceId: const Value('POS-WIN-01'),
              clientSeq: const Value(1),
              totalAmount: const Value(1250),
              paymentMethod: const Value('CREDIT_CARD'),
              status: const Value('COMPLETED'),
              createdAt: Value(occurredAt),
            ),
          );
      await (db.update(db.clientSyncStates)..where((s) => s.deviceId.equals('POS-WIN-01')))
          .write(const ClientSyncStatesCompanion(currentClientSeq: Value(1)));
      await db.into(db.outboxOperations).insert(
            OutboxOperationsCompanion(
              operationId: const Value('op_fifo_legacy_1'),
              deviceId: const Value('POS-WIN-01'),
              clientSeq: const Value(1),
              operationType: const Value('SALE_CREATE'),
              payload: Value(jsonEncode(legacyPayloadMap)),
              payloadHash: Value(ClientStorageRepository.computeSaleRequestHash(legacyPayloadMap)),
              occurredAt: Value(occurredAt),
              status: const Value('PENDING'),
            ),
          );

      // Sonraki geçerli CASH satış (client_seq = 2)
      final cashSale2 = await repo.createOfflineSale(
        deviceId: 'POS-WIN-01',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_ekmek', 2)],
      );
      expect(cashSale2.clientSeq, equals(2));

      final transport = _ScriptedPaymentValidatingTransport();
      final syncService = ClientSyncService(
        repository: repo,
        transport: transport,
        deviceId: 'POS-WIN-01',
        deviceToken: 'tok',
        hubUrl: 'https://127.0.0.1:8443',
      );

      // 1. İlk sync: seq 1 400 ERR_INVALID_PAYMENT_METHOD alır ve FAILED_PERMANENT olur; seq 2 gönderilemez
      final firstSync = await syncService.syncPendingOutbox();
      expect(firstSync.syncedCount, equals(0));
      expect(firstSync.permanentFailedCount, equals(1));
      expect(firstSync.hasMore, isTrue);
      expect(transport.attemptedSeqs, equals([1]));

      // 2. Tekrar sync denemesi: seq 1 FAILED_PERMANENT olduğu sürece seq 2 ASLA atlayıp gönderilemez
      final blockedSync = await syncService.syncPendingOutbox();
      expect(blockedSync.syncedCount, equals(0));
      expect(blockedSync.permanentFailedCount, equals(1));
      expect(blockedSync.lastError, contains('kuyruk durduruldu'));
      expect(transport.attemptedSeqs, equals([1]));

      final op2WhileBlocked = await (db.select(db.outboxOperations)
            ..where((o) => o.operationId.equals(cashSale2.operationId)))
          .getSingle();
      expect(op2WhileBlocked.status, equals('PENDING'));

      // 3. seq 1 kontrollü biçimde CARD olarak onarılır -> FIFO tekrar akar [1, 2]
      await repo.updateAndRetryFailedOperation(
        'op_fifo_legacy_1',
        correctedPayload: {
          ...legacyPayloadMap,
          'payment_method': 'CARD',
        },
      );

      final resumedSync = await syncService.syncPendingOutbox();
      expect(resumedSync.syncedCount, equals(2));
      expect(resumedSync.permanentFailedCount, equals(0));
      expect(resumedSync.hasMore, isFalse);
      expect(transport.attemptedSeqs, equals([1, 1, 2]));
      expect((await repo.getSyncState('POS-WIN-01'))!.lastSyncedSeq, equals(2));
    });
  });
}

class _ScriptedPaymentValidatingTransport implements SyncTransport {
  final List<int> attemptedSeqs = [];

  @override
  Future<SyncResponse> postSale({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final map = jsonDecode(payload) as Map<String, dynamic>;
    final seq = map['client_seq'] as int;
    attemptedSeqs.add(seq);

    if (!PaymentMethod.isCanonical(map['payment_method'])) {
      return const SyncResponse(
        statusCode: 400,
        body: '{"error":"BAD_REQUEST","code":"ERR_INVALID_PAYMENT_METHOD"}',
      );
    }

    return SyncResponse(
      statusCode: 201,
      body: jsonEncode({'status': 'COMMITTED', 'client_seq': seq}),
    );
  }

  @override
  Future<SyncResponse> getProducts({
    required String hubUrl,
    required String token,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(statusCode: 200, body: '{}');

  @override
  Future<SyncResponse> getSales({
    required String hubUrl,
    required String token,
    int cursor = 0,
    int limit = 50,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(statusCode: 200, body: '{"sales":[],"next_cursor":0,"has_more":false}');

  @override
  Future<SyncResponse> postSyncAck({
    required String hubUrl,
    required String token,
    required String syncSessionId,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(statusCode: 200, body: '{}');

  @override
  Future<SyncResponse> postProductUpsert({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(statusCode: 200, body: '{"status":"COMMITTED"}');

  @override
  Future<SyncResponse> postStockReceipt({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(statusCode: 200, body: '{"status":"COMMITTED"}');

  @override
  void close() {}
}

class _FakeSyncTransport implements SyncTransport {
  final SyncResponse nextResponse;
  String? lastSentPayload;

  _FakeSyncTransport({required this.nextResponse});

  @override
  Future<SyncResponse> postSale({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    lastSentPayload = payload;
    return nextResponse;
  }

  @override
  Future<SyncResponse> postProductUpsert({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    lastSentPayload = payload;
    return nextResponse;
  }

  @override
  Future<SyncResponse> getProducts({
    required String hubUrl,
    required String token,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(statusCode: 200, body: '{}');

  @override
  Future<SyncResponse> getSales({
    required String hubUrl,
    required String token,
    int cursor = 0,
    int limit = 50,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(statusCode: 200, body: '{"sales":[],"next_cursor":0,"has_more":false}');

  @override
  Future<SyncResponse> postSyncAck({
    required String hubUrl,
    required String token,
    required String syncSessionId,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(statusCode: 200, body: '{}');

  @override
  Future<SyncResponse> postStockReceipt({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(statusCode: 200, body: '{"status":"COMMITTED"}');

  @override
  void close() {}
}
