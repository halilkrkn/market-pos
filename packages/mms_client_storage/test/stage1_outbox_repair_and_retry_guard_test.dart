import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _device = 'POS-STAGE1-UNIT';

void main() {
  late Directory tempDir;
  late ClientDatabase db;
  late ClientStorageRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mms_stage1_unit_');
    db = ClientDatabase(File(p.join(tempDir.path, 'client_stage1.db')));
    repo = ClientStorageRepository(db);
    await repo.initializeDevice(_device);
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AUD-HIGH-01: Karma FAILED_PERMANENT + RETRY kuyruğu ve stok koruması', () {
    test(
        '1. [seq=1 FAILED_PERMANENT, seq=2 RETRY (attemptCount > 0), seq=3 SALE_CREATE] durumunda onarım her iki PRODUCT_UPSERT kaydını düzeltir, seq=1 başlangıç stoğunu korur ve fazladan op eklemez',
        () async {
      final prod = await repo.createProduct(
        name: 'Karma Kuyruk Ürünü',
        price: 2500,
        barcode: '8690001110001',
        initialStock: 10000,
        deviceId: _device,
      );
      await repo.updateProduct(
        id: prod.id,
        barcode: '8690001110002',
        deviceId: _device,
      );
      await repo.createOfflineSale(
        deviceId: _device,
        paymentMethod: 'CASH',
        items: [CartItemInput.units(prod.id, 3)],
      );
      expect((await repo.getProductById(prod.id))!.stock, equals(7000));

      final beforeOps = await (db.select(db.outboxOperations)
            ..where((o) => o.deviceId.equals(_device))
            ..orderBy([(o) => OrderingTerm.asc(o.clientSeq)]))
          .get();
      expect(beforeOps, hasLength(3));
      final op1Id = beforeOps[0].operationId;
      final op2Id = beforeOps[1].operationId;

      await (db.update(db.outboxOperations)
            ..where((o) => o.operationId.equals(op1Id)))
          .write(const OutboxOperationsCompanion(
        status: Value('FAILED_PERMANENT'),
        lastError: Value('Kalıcı Hata [409]: {"code":"ERR_DUPLICATE_BARCODE"}'),
      ));
      await (db.update(db.outboxOperations)
            ..where((o) => o.operationId.equals(op2Id)))
          .write(OutboxOperationsCompanion(
        status: const Value('RETRY'),
        attemptCount: const Value(2),
        nextRetryAt: Value(DateTime.now().add(const Duration(minutes: 5))),
        lastError: const Value('HTTP 503'),
      ));

      // Barkod onarımı
      await repo.updateProduct(
        id: prod.id,
        barcode: '8690001234567',
        deviceId: _device,
      );

      final afterOps = await (db.select(db.outboxOperations)
            ..where((o) => o.deviceId.equals(_device))
            ..orderBy([(o) => OrderingTerm.asc(o.clientSeq)]))
          .get();
      expect(afterOps, hasLength(3), reason: 'Fazladan seq=4 eklenmemeli');

      final repaired1 = afterOps[0];
      final repaired2 = afterOps[1];
      expect(repaired1.operationId, equals(op1Id));
      expect(repaired1.clientSeq, equals(1));
      expect(repaired1.status, equals('PENDING'));
      expect(repaired1.attemptCount, equals(0));
      expect(repaired1.lastError, isNull);

      expect(repaired2.operationId, equals(op2Id));
      expect(repaired2.clientSeq, equals(2));
      expect(repaired2.status, equals('PENDING'));
      expect(repaired2.attemptCount, equals(0));
      expect(repaired2.nextRetryAt, isNull);
      expect(repaired2.lastError, isNull);

      final prodPayload1 =
          (jsonDecode(repaired1.payload) as Map<String, dynamic>)['product']
              as Map<String, dynamic>;
      final prodPayload2 =
          (jsonDecode(repaired2.payload) as Map<String, dynamic>)['product']
              as Map<String, dynamic>;

      expect(prodPayload1['barcode'], equals('8690001234567'));
      expect(prodPayload2['barcode'], equals('8690001234567'));
      expect(
        prodPayload1['stock'],
        equals(10000),
        reason: 'seq=1 başlangıç stoğunu (10000) korumalı; 7000 yazılmamalı',
      );
    });
  });

  group('AUD-MED-02: retryFailedPermanentOperation durum ve protokol hata koruması', () {
    test('2. Olmayan operationId veya FAILED_PERMANENT dışındaki durumlar StateError fırlatır ve kaydı bozmaz', () async {
      await expectLater(
        repo.retryFailedPermanentOperation('op_non_existent'),
        throwsA(isA<StateError>()),
      );

      final prod = await repo.createProduct(
        name: 'Durum Koruma Ürünü',
        price: 1500,
        barcode: '8690002220001',
        deviceId: _device,
      );
      expect(prod.price, equals(1500));

      final op = (await db.select(db.outboxOperations).get()).single;

      for (final nonFailedStatus in ['PENDING', 'RETRY', 'IN_PROGRESS', 'SYNCED']) {
        await (db.update(db.outboxOperations)
              ..where((o) => o.operationId.equals(op.operationId)))
            .write(OutboxOperationsCompanion(
          status: Value(nonFailedStatus),
          attemptCount: const Value(3),
          lastError: const Value('Korunan durum'),
        ));

        await expectLater(
          repo.retryFailedPermanentOperation(op.operationId),
          throwsA(isA<StateError>()),
          reason: '$nonFailedStatus durumundaki kayıt yeniden denenememeli',
        );

        final unchanged = await (db.select(db.outboxOperations)
              ..where((o) => o.operationId.equals(op.operationId)))
            .getSingle();
        expect(unchanged.status, equals(nonFailedStatus));
        expect(unchanged.attemptCount, equals(3));
        expect(unchanged.lastError, equals('Korunan durum'));
      }
    });

    test(
        '3. ERR_IDEMPOTENCY_* ve ERR_CLIENT_SEQ_GAP hataları doğrudan yeniden denenemez; veri hatası olmayan kalıcı hatalar yeniden denenebilir',
        () async {
      await repo.createProduct(
        name: 'Protokol Koruma Ürünü',
        price: 2000,
        barcode: '8690003330001',
        deviceId: _device,
      );
      final op = (await db.select(db.outboxOperations).get()).single;

      for (final blockedError in [
        'Kalıcı Hata [409]: {"code":"ERR_IDEMPOTENCY_PAYLOAD_MISMATCH"}',
        'Kalıcı Hata [409]: {"code":"ERR_IDEMPOTENCY_HASH_UNVERIFIABLE"}',
        'Kalıcı Hata [409]: {"code":"ERR_CLIENT_SEQ_GAP"}',
      ]) {
        await (db.update(db.outboxOperations)
              ..where((o) => o.operationId.equals(op.operationId)))
            .write(OutboxOperationsCompanion(
          status: const Value('FAILED_PERMANENT'),
          attemptCount: const Value(1),
          lastError: Value(blockedError),
        ));

        await expectLater(
          repo.retryFailedPermanentOperation(op.operationId),
          throwsA(isA<StateError>()),
          reason: '$blockedError doğrudan PENDING yapılmamalı',
        );

        final kept = await (db.select(db.outboxOperations)
              ..where((o) => o.operationId.equals(op.operationId)))
            .getSingle();
        expect(kept.status, equals('FAILED_PERMANENT'));
        expect(kept.lastError, equals(blockedError));
      }

      // Sunucu tarafında giderilmiş normal çakışma (örn. başka üründeki barkod kaldırıldı) yeniden denenebilir
      await (db.update(db.outboxOperations)
            ..where((o) => o.operationId.equals(op.operationId)))
          .write(const OutboxOperationsCompanion(
        status: Value('FAILED_PERMANENT'),
        attemptCount: Value(1),
        lastError: Value('Kalıcı Hata [409]: {"code":"ERR_DUPLICATE_BARCODE"}'),
      ));

      await repo.retryFailedPermanentOperation(op.operationId);
      final recovered = await (db.select(db.outboxOperations)
            ..where((o) => o.operationId.equals(op.operationId)))
          .getSingle();
      expect(recovered.status, equals('PENDING'));
      expect(recovered.attemptCount, equals(0));
      expect(recovered.nextRetryAt, isNull);
      expect(recovered.lastError, isNull);
    });
  });
}
