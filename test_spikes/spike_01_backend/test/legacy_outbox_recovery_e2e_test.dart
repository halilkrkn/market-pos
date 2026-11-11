import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:http/http.dart' as http;
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/pepper_manager.dart';
import '../lib/security/token_manager.dart';

void main() {
  late Directory tempDir;
  late File masterDbFile;
  late File clientDbFile;
  late SpikeDatabase masterDb;
  late WriteQueue masterWriteQueue;
  late PepperManager pepperManager;
  late SpikeServer server;
  late ClientDatabase clientDb;
  late ClientStorageRepository clientRepo;
  late ClientSyncService syncService;

  const testPort = 8967;
  const hubUrl = 'http://127.0.0.1:$testPort';
  const deviceId = 'DEV_WIN_RECOVERY';
  const rawToken = 'mms_pat_legacy_recovery_e2e_token';

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    configureSqliteNative();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mms_legacy_recovery_e2e_');
    masterDbFile = File(p.join(tempDir.path, 'market_master.db'));
    clientDbFile = File(p.join(tempDir.path, 'client_local.db'));
    final pepperFile = File(p.join(tempDir.path, 'pepper.dpapi'));

    pepperManager = PepperManager(pepperFile)..initialize();
    masterDb = SpikeDatabase(masterDbFile);
    masterWriteQueue = WriteQueue();

    await masterDb.into(masterDb.products).insert(
          ProductsCompanion(
            id: const Value('prod_et'),
            barcode: const Value('869001'),
            name: const Value('Kuşbaşı Et'),
            price: const Value(20000), // 200.00 TL/kg
            priceVersionId: const Value('pv_init'),
            stock: const Value(50000000), // 50,000 g = 50,000,000 milli-g
            stockUnit: const Value('g'),
            pricingUnit: const Value('kg'),
            conversionFactorNumerator: const Value(1000),
            conversionFactorDenominator: const Value(1),
            isActive: const Value(true),
          ),
        );

    await masterDb.into(masterDb.products).insert(
          ProductsCompanion(
            id: const Value('prod_su'),
            barcode: const Value('869002'),
            name: const Value('Su 0.5L'),
            price: const Value(500), // 5.00 TL/adet
            priceVersionId: const Value('pv_init'),
            stock: const Value(100000), // 100 adet = 100,000 milli-adet
            stockUnit: const Value('adet'),
            pricingUnit: const Value('adet'),
            conversionFactorNumerator: const Value(1),
            conversionFactorDenominator: const Value(1),
            isActive: const Value(true),
          ),
        );

    final salt = TokenManager.generateSalt();
    final tokenHash = TokenManager.hashToken(
      rawToken: rawToken,
      salt: salt,
      pepper: pepperManager.pepper,
    );

    await masterDb.into(masterDb.devices).insert(
          DevicesCompanion(
            deviceId: Value(deviceId),
            name: const Value('Legacy Recovery Test Hub Client'),
            tokenHash: Value(tokenHash),
            salt: Value(salt),
            isActive: const Value(true),
            isConfirmed: const Value(true),
            role: const Value('CASHIER'),
          ),
        );

    server = SpikeServer(
      db: masterDb,
      dbFile: masterDbFile,
      writeQueue: masterWriteQueue,
      backupDirectory: p.join(tempDir.path, 'backups'),
      adminSecret: 'legacy_recovery_admin_secret_2026!',
      pepperManager: pepperManager,
    );
    await server.start(address: InternetAddress.loopbackIPv4, port: testPort);

    clientDb = ClientDatabase(clientDbFile);
    clientRepo = ClientStorageRepository(clientDb);
    syncService = ClientSyncService(
      repository: clientRepo,
      transport: HttpSyncTransport(),
      deviceId: deviceId,
      deviceToken: rawToken,
      hubUrl: hubUrl,
      baseBackoff: const Duration(milliseconds: 50),
      maxBackoff: const Duration(milliseconds: 500),
    );
  });

  tearDown(() async {
    await clientDb.close();
    await server.stop();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('E2E Legacy CREDIT_CARD Outbox Onarımı, Rollback ve FIFO Devamı', () {
    test(
      '1-11 + FIFO: CREDIT_CARD -> FAILED_PERMANENT -> Rollback & Kontrollü CARD Onarımı -> Live Hub Sync -> Replay & FIFO',
      () async {
        // Ön adım: Ürün kataloğunu Master Hub'dan istemciye çek
        final syncedProducts = await syncService.syncProducts();
        expect(syncedProducts, equals(2));

        // ---------------------------------------------------------------------
        // ADIM 1: Yerel DB'de CREDIT_CARD içeren eski bir Outbox satış kaydı oluştur
        // ---------------------------------------------------------------------
        const legacyOpId = 'op_legacy_e2e_1';
        const legacySaleId = 'csale_legacy_e2e_1';
        final occurredAt = DateTime.now().subtract(const Duration(days: 1));
        final legacyPayloadMap = <String, dynamic>{
          'operation_id': legacyOpId,
          'client_seq': 1,
          'total_amount': 20000,
          'payment_method': 'CREDIT_CARD',
          'items': [
            {
              'product_id': 'prod_et',
              'price_version_id': 'pv_init',
              'quantity': 1000, // 1.000 kg -> 1,000,000 milli-g
              'unit_price': 20000,
              'total_price': 20000,
              'unit': 'kg',
            },
          ],
        };
        final legacyPayloadJson = jsonEncode(legacyPayloadMap);
        final legacyHash = ClientStorageRepository.computeSaleRequestHash(legacyPayloadMap);

        await clientDb.into(clientDb.localSales).insert(
              LocalSalesCompanion(
                id: const Value(legacySaleId),
                deviceId: const Value(deviceId),
                clientSeq: const Value(1),
                totalAmount: const Value(20000),
                paymentMethod: const Value('CREDIT_CARD'),
                status: const Value('COMPLETED'),
                createdAt: Value(occurredAt),
              ),
            );
        await clientDb.into(clientDb.localSaleItems).insert(
              LocalSaleItemsCompanion(
                id: const Value('citem_legacy_e2e_1'),
                saleId: const Value(legacySaleId),
                productId: const Value('prod_et'),
                productNameSnapshot: const Value('Kuşbaşı Et'),
                unitSnapshot: const Value('kg'),
                priceVersionId: const Value('pv_init'),
                unitPrice: const Value(20000),
                quantity: const Value(1000),
                totalPrice: const Value(20000),
              ),
            );
        await clientDb.into(clientDb.localStockMovements).insert(
              LocalStockMovementsCompanion(
                id: const Value('csm_legacy_e2e_1'),
                productId: const Value('prod_et'),
                quantity: const Value(-1000000), // -1,000 g
                unit: const Value('g'),
                movementType: const Value('SATIS'),
                referenceId: const Value(legacySaleId),
                createdAt: Value(occurredAt),
              ),
            );
        await (clientDb.update(clientDb.localProducts)..where((p) => p.id.equals('prod_et')))
            .write(const LocalProductsCompanion(stock: Value(49000000)));
        await (clientDb.update(clientDb.clientSyncStates)..where((s) => s.deviceId.equals(deviceId)))
            .write(const ClientSyncStatesCompanion(currentClientSeq: Value(1)));
        await clientDb.into(clientDb.outboxOperations).insert(
              OutboxOperationsCompanion(
                operationId: const Value(legacyOpId),
                deviceId: const Value(deviceId),
                clientSeq: const Value(1),
                operationType: const Value('SALE_CREATE'),
                payload: Value(legacyPayloadJson),
                payloadHash: Value(legacyHash),
                occurredAt: Value(occurredAt),
                status: const Value('PENDING'),
              ),
            );

        // ---------------------------------------------------------------------
        // ADIM 2: Master Hub'a ilk gönderim -> ERR_INVALID_PAYMENT_METHOD (400) -> FAILED_PERMANENT
        // ---------------------------------------------------------------------
        final firstSync = await syncService.syncPendingOutbox();
        expect(firstSync.syncedCount, equals(0));
        expect(firstSync.permanentFailedCount, equals(1));
        expect(firstSync.lastError, contains('ERR_INVALID_PAYMENT_METHOD'));

        final opFailed = await (clientDb.select(clientDb.outboxOperations)
              ..where((o) => o.operationId.equals(legacyOpId)))
            .getSingle();
        expect(opFailed.status, equals('FAILED_PERMANENT'));
        expect(opFailed.lastError, contains('ERR_INVALID_PAYMENT_METHOD'));
        expect(opFailed.payloadHash, equals(legacyHash));

        // ---------------------------------------------------------------------
        // ADIM 3: İlgili yerel satışın ve stok hareketinin korunduğunu doğrula
        // ---------------------------------------------------------------------
        final preservedSale = await (clientDb.select(clientDb.localSales)
              ..where((s) => s.id.equals(legacySaleId)))
            .getSingle();
        final preservedItems = await clientDb.select(clientDb.localSaleItems).get();
        final preservedMovements = await clientDb.select(clientDb.localStockMovements).get();
        final preservedMeat = await (clientDb.select(clientDb.localProducts)
              ..where((p) => p.id.equals('prod_et')))
            .getSingle();
        expect(preservedSale.status, equals('COMPLETED'));
        expect(preservedSale.totalAmount, equals(20000));
        expect(preservedItems.length, equals(1));
        expect(preservedMovements.length, equals(1));
        expect(preservedMovements.single.quantity, equals(-1000000));
        expect(preservedMeat.stock, equals(49000000));
        expect(await masterDb.select(masterDb.sales).get(), isEmpty);
        expect(await masterDb.select(masterDb.processedOperations).get(), isEmpty);

        // ---------------------------------------------------------------------
        // FIFO DOĞRULAMA: Yeni geçerli CASH satış (seq 2) ekle; seq 1 FAILED_PERMANENT
        // iken seq 2 kesinlikle senkronize edilememeli!
        // ---------------------------------------------------------------------
        final cashSale2 = await clientRepo.createOfflineSale(
          deviceId: deviceId,
          paymentMethod: 'CASH',
          items: [CartItemInput.units('prod_su', 2)], // 1000 kuruş
        );
        expect(cashSale2.clientSeq, equals(2));

        final blockedSync = await syncService.syncPendingOutbox();
        expect(blockedSync.syncedCount, equals(0));
        expect(blockedSync.permanentFailedCount, equals(1));
        expect(blockedSync.hasMore, isTrue);
        expect(await masterDb.select(masterDb.sales).get(), isEmpty);

        final op2StillPending = await (clientDb.select(clientDb.outboxOperations)
              ..where((o) => o.operationId.equals(cashSale2.operationId)))
            .getSingle();
        expect(op2StillPending.status, equals('PENDING'));

        // ---------------------------------------------------------------------
        // ROLLBACK DOĞRULAMA: Onarım sırasında DB hatası oluşursa rollback çalışmalı
        // ---------------------------------------------------------------------
        final repairedPayloadMap = <String, dynamic>{
          ...legacyPayloadMap,
          'payment_method': 'CARD',
        };
        await clientDb.customStatement(
          "CREATE TEMP TRIGGER trg_e2e_fail_sale_repair BEFORE UPDATE ON local_sales BEGIN SELECT RAISE(ABORT, 'Simüle E2E DB hatası'); END;",
        );
        await expectLater(
          () => clientRepo.updateAndRetryFailedOperation(
            legacyOpId,
            correctedPayload: repairedPayloadMap,
          ),
          throwsA(anything),
        );

        final opAfterFail = await (clientDb.select(clientDb.outboxOperations)
              ..where((o) => o.operationId.equals(legacyOpId)))
            .getSingle();
        final saleAfterFail = await (clientDb.select(clientDb.localSales)
              ..where((s) => s.id.equals(legacySaleId)))
            .getSingle();
        expect(opAfterFail.payload, equals(legacyPayloadJson));
        expect(opAfterFail.payloadHash, equals(legacyHash));
        expect(opAfterFail.status, equals('FAILED_PERMANENT'));
        expect(saleAfterFail.paymentMethod, equals('CREDIT_CARD'));

        await clientDb.customStatement('DROP TRIGGER temp.trg_e2e_fail_sale_repair;');

        // ---------------------------------------------------------------------
        // ADIM 4-7: Kontrollü CARD onarımı, hash yeniden hesabı, kimlik korunumu, PENDING geçişi
        // ---------------------------------------------------------------------
        await clientRepo.updateAndRetryFailedOperation(
          legacyOpId,
          correctedPayload: repairedPayloadMap,
        );

        final opRepaired = await (clientDb.select(clientDb.outboxOperations)
              ..where((o) => o.operationId.equals(legacyOpId)))
            .getSingle();
        final saleRepaired = await (clientDb.select(clientDb.localSales)
              ..where((s) => s.id.equals(legacySaleId)))
            .getSingle();
        final expectedClientHash = ClientStorageRepository.computeSaleRequestHash(repairedPayloadMap);
        final expectedServerHash = SpikeServer.computeSaleRequestHash(repairedPayloadMap);

        expect(expectedClientHash, equals(expectedServerHash));
        expect(opRepaired.payloadHash, equals(expectedServerHash));
        expect(opRepaired.payloadHash, isNot(equals(legacyHash)));
        expect(opRepaired.operationId, equals(legacyOpId));
        expect(opRepaired.deviceId, equals(deviceId));
        expect(opRepaired.clientSeq, equals(1));
        expect(opRepaired.status, equals('PENDING'));
        expect(opRepaired.attemptCount, equals(0));
        expect(opRepaired.nextRetryAt, isNull);
        expect(opRepaired.lastError, isNull);
        expect(
          (jsonDecode(opRepaired.payload) as Map<String, dynamic>)['payment_method'],
          equals('CARD'),
        );
        expect(saleRepaired.paymentMethod, equals('CARD'));

        // ---------------------------------------------------------------------
        // ADIM 8-9: Master Hub'a FIFO (seq 1 CARD, sonra seq 2 CASH) gönderimi ve doğrulaması
        // ---------------------------------------------------------------------
        final recoverySync = await syncService.syncPendingOutbox();
        expect(recoverySync.syncedCount, equals(2));
        expect(recoverySync.retriedCount, equals(0));
        expect(recoverySync.permanentFailedCount, equals(0));
        expect(recoverySync.hasMore, isFalse);

        final masterSales = await (masterDb.select(masterDb.sales)
              ..where((s) => s.deviceId.equals(deviceId))
              ..orderBy([(s) => OrderingTerm.asc(s.clientSeq)]))
            .get();
        expect(masterSales.length, equals(2));
        expect(masterSales[0].clientSeq, equals(1));
        expect(masterSales[0].paymentMethod, equals('CARD'));
        expect(masterSales[0].totalAmount, equals(20000));
        expect(masterSales[1].clientSeq, equals(2));
        expect(masterSales[1].paymentMethod, equals('CASH'));
        expect(masterSales[1].totalAmount, equals(1000));

        final masterMovements = await masterDb.select(masterDb.stockMovements).get();
        expect(masterMovements.length, equals(2));
        final masterMeat = await (masterDb.select(masterDb.products)
              ..where((p) => p.id.equals('prod_et')))
            .getSingle();
        final masterWater = await (masterDb.select(masterDb.products)
              ..where((p) => p.id.equals('prod_su')))
            .getSingle();
        expect(masterMeat.stock, equals(49000000));
        expect(masterWater.stock, equals(98000));

        // ---------------------------------------------------------------------
        // ADIM 10: Aynı payload tekrar gönderildiğinde duplicate satış/stok oluşmamalı (Idempotent Replay)
        // ---------------------------------------------------------------------
        final replayRes = await http.post(
          Uri.parse('$hubUrl/api/v1/sales'),
          headers: {
            'authorization': 'Bearer $rawToken',
            'x-device-id': deviceId,
            'content-type': 'application/json',
          },
          body: opRepaired.payload,
        );
        expect(replayRes.statusCode, equals(200));
        expect(replayRes.headers['x-mms-idempotent-replay'], equals('true'));

        expect((await masterDb.select(masterDb.sales).get()).length, equals(2));
        expect((await masterDb.select(masterDb.stockMovements).get()).length, equals(2));
        expect((await masterDb.select(masterDb.processedOperations).get()).length, equals(2));
        final masterMeatAfterReplay = await (masterDb.select(masterDb.products)
              ..where((p) => p.id.equals('prod_et')))
            .getSingle();
        expect(masterMeatAfterReplay.stock, equals(49000000));

        // ---------------------------------------------------------------------
        // ADIM 11: Yerel satış ve Outbox ACK tutarlılığını doğrula
        // ---------------------------------------------------------------------
        final finalLocalSale1 = await (clientDb.select(clientDb.localSales)
              ..where((s) => s.id.equals(legacySaleId)))
            .getSingle();
        final finalOutboxRows = await (clientDb.select(clientDb.outboxOperations)
              ..where((o) => o.deviceId.equals(deviceId))
              ..orderBy([(o) => OrderingTerm.asc(o.clientSeq)]))
            .get();
        final finalSyncState = await clientRepo.getSyncState(deviceId);

        expect(finalLocalSale1.paymentMethod, equals('CARD'));
        expect(finalLocalSale1.status, equals('COMPLETED'));
        expect(finalLocalSale1.totalAmount, equals(20000));
        expect((await clientDb.select(clientDb.localStockMovements).get()).length, equals(2));

        expect(finalOutboxRows.length, equals(2));
        for (final row in finalOutboxRows) {
          expect(row.status, equals('SYNCED'));
          expect(row.acknowledgedAt, isNotNull);
          expect(row.lastError, isNull);
        }
        expect(finalSyncState!.lastSyncedSeq, equals(2));
      },
    );
  });
}

