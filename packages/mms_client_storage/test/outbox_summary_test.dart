import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:test/test.dart';

void main() {
  group('OutboxSummary Model Birim Testleri', () {
    test('1. Boş Outbox: tüm sayaçlar 0, totalUnsynced=0, hasErrors=false, hasPendingWork=false', () {
      const summary = OutboxSummary.empty();
      expect(summary.pending, 0);
      expect(summary.retry, 0);
      expect(summary.inProgress, 0);
      expect(summary.failedPermanent, 0);
      expect(summary.totalUnsynced, 0);
      expect(summary.hasErrors, isFalse);
      expect(summary.hasPendingWork, isFalse);
    });

    test('2. Yalnızca PENDING kayıtları: hasPendingWork=true, hasErrors=false', () {
      const summary = OutboxSummary(
        pending: 5,
        retry: 0,
        inProgress: 0,
        failedPermanent: 0,
      );
      expect(summary.totalUnsynced, 5);
      expect(summary.hasErrors, isFalse);
      expect(summary.hasPendingWork, isTrue);
    });

    test('3. Yalnızca RETRY kayıtları: hasPendingWork=true, hasErrors=false', () {
      const summary = OutboxSummary(
        pending: 0,
        retry: 3,
        inProgress: 0,
        failedPermanent: 0,
      );
      expect(summary.totalUnsynced, 3);
      expect(summary.hasErrors, isFalse);
      expect(summary.hasPendingWork, isTrue);
    });

    test('4. Yalnızca IN_PROGRESS kayıtları: hasPendingWork=true, hasErrors=false', () {
      const summary = OutboxSummary(
        pending: 0,
        retry: 0,
        inProgress: 2,
        failedPermanent: 0,
      );
      expect(summary.totalUnsynced, 2);
      expect(summary.hasErrors, isFalse);
      expect(summary.hasPendingWork, isTrue);
    });

    test('5. Yalnızca FAILED_PERMANENT kayıtları: hasErrors=true, hasPendingWork=false', () {
      const summary = OutboxSummary(
        pending: 0,
        retry: 0,
        inProgress: 0,
        failedPermanent: 4,
      );
      expect(summary.totalUnsynced, 4);
      expect(summary.hasErrors, isTrue);
      expect(summary.hasPendingWork, isFalse);
    });

    test('6. Dört durumun birlikte bulunması: totalUnsynced doğru toplamı verir', () {
      const summary = OutboxSummary(
        pending: 4,
        retry: 3,
        inProgress: 2,
        failedPermanent: 1,
      );
      expect(summary.totalUnsynced, 10);
      expect(summary.hasErrors, isTrue);
      expect(summary.hasPendingWork, isTrue);
    });

    test('7. Eşitlik (Equality) ve HashCode doğrulaması', () {
      const s1 = OutboxSummary(pending: 1, retry: 2, inProgress: 3, failedPermanent: 4);
      const s2 = OutboxSummary(pending: 1, retry: 2, inProgress: 3, failedPermanent: 4);
      const s3 = OutboxSummary(pending: 1, retry: 2, inProgress: 3, failedPermanent: 5);

      expect(s1, equals(s2));
      expect(s1.hashCode, equals(s2.hashCode));
      expect(s1, isNot(equals(s3)));
    });
  });

  group('ClientStorageRepository OutboxSummary SQLite Entegrasyon Testleri', () {
    late ClientDatabase db;
    late ClientStorageRepository repo;
    const testDeviceId = 'POS-TEST-01';

    setUp(() async {
      db = ClientDatabase.forTesting(NativeDatabase.memory());
      repo = ClientStorageRepository(db);
      await repo.initializeDevice(testDeviceId);
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> insertOutboxOp({
      required String id,
      required int seq,
      required String status,
      String deviceId = testDeviceId,
    }) async {
      await db.into(db.outboxOperations).insert(
            OutboxOperationsCompanion.insert(
              operationId: id,
              deviceId: deviceId,
              clientSeq: seq,
              operationType: 'SALE_CREATE',
              payload: '{"test": true}',
              payloadHash: 'hash_$id',
              occurredAt: DateTime.now(),
              status: drift_value(status),
            ),
          );
    }

    test('Senaryo 1: Boş Outbox - Tüm sayaçlar 0 döner', () async {
      final summary = await repo.getOutboxSummary(deviceId: testDeviceId);
      expect(summary.pending, 0);
      expect(summary.retry, 0);
      expect(summary.inProgress, 0);
      expect(summary.failedPermanent, 0);
      expect(summary.totalUnsynced, 0);
      expect(summary.hasErrors, isFalse);
      expect(summary.hasPendingWork, isFalse);
    });

    test('Senaryo 2: Yalnızca PENDING kayıtları sayılır', () async {
      await insertOutboxOp(id: 'op1', seq: 1, status: 'PENDING');
      await insertOutboxOp(id: 'op2', seq: 2, status: 'PENDING');

      final summary = await repo.getOutboxSummary(deviceId: testDeviceId);
      expect(summary.pending, 2);
      expect(summary.retry, 0);
      expect(summary.inProgress, 0);
      expect(summary.failedPermanent, 0);
      expect(summary.totalUnsynced, 2);
      expect(summary.hasPendingWork, isTrue);
      expect(summary.hasErrors, isFalse);
    });

    test('Senaryo 3: Yalnızca RETRY kayıtları sayılır', () async {
      await insertOutboxOp(id: 'op1', seq: 1, status: 'RETRY');
      await insertOutboxOp(id: 'op2', seq: 2, status: 'RETRY');
      await insertOutboxOp(id: 'op3', seq: 3, status: 'RETRY');

      final summary = await repo.getOutboxSummary(deviceId: testDeviceId);
      expect(summary.pending, 0);
      expect(summary.retry, 3);
      expect(summary.inProgress, 0);
      expect(summary.failedPermanent, 0);
      expect(summary.totalUnsynced, 3);
      expect(summary.hasPendingWork, isTrue);
      expect(summary.hasErrors, isFalse);
    });

    test('Senaryo 4: Yalnızca IN_PROGRESS kayıtları sayılır', () async {
      await insertOutboxOp(id: 'op1', seq: 1, status: 'IN_PROGRESS');

      final summary = await repo.getOutboxSummary(deviceId: testDeviceId);
      expect(summary.pending, 0);
      expect(summary.retry, 0);
      expect(summary.inProgress, 1);
      expect(summary.failedPermanent, 0);
      expect(summary.totalUnsynced, 1);
      expect(summary.hasPendingWork, isTrue);
      expect(summary.hasErrors, isFalse);
    });

    test('Senaryo 5: Yalnızca FAILED_PERMANENT kayıtları sayılır', () async {
      await insertOutboxOp(id: 'op1', seq: 1, status: 'FAILED_PERMANENT');

      final summary = await repo.getOutboxSummary(deviceId: testDeviceId);
      expect(summary.pending, 0);
      expect(summary.retry, 0);
      expect(summary.inProgress, 0);
      expect(summary.failedPermanent, 1);
      expect(summary.totalUnsynced, 1);
      expect(summary.hasErrors, isTrue);
      expect(summary.hasPendingWork, isFalse);
    });

    test('Senaryo 6 & 7: Dört durum birlikte bulunduğunda toplam ve durumlar eksiksiz hesaplanır', () async {
      await insertOutboxOp(id: 'op1', seq: 1, status: 'PENDING');
      await insertOutboxOp(id: 'op2', seq: 2, status: 'PENDING');
      await insertOutboxOp(id: 'op3', seq: 3, status: 'RETRY');
      await insertOutboxOp(id: 'op4', seq: 4, status: 'IN_PROGRESS');
      await insertOutboxOp(id: 'op5', seq: 5, status: 'FAILED_PERMANENT');
      // SYNCED olanlar totalUnsynced'a dahil edilmemeli
      await insertOutboxOp(id: 'op6', seq: 6, status: 'SYNCED');

      final summary = await repo.getOutboxSummary(deviceId: testDeviceId);
      expect(summary.pending, 2);
      expect(summary.retry, 1);
      expect(summary.inProgress, 1);
      expect(summary.failedPermanent, 1);
      expect(summary.totalUnsynced, 5);
      expect(summary.hasErrors, isTrue);
      expect(summary.hasPendingWork, isTrue);
    });

    test('Senaryo 8: Outbox değiştikten sonra özet anında güncellenir', () async {
      await insertOutboxOp(id: 'op1', seq: 1, status: 'PENDING');

      var summary = await repo.getOutboxSummary(deviceId: testDeviceId);
      expect(summary.pending, 1);
      expect(summary.inProgress, 0);

      // PENDING -> IN_PROGRESS
      await repo.markOutboxInProgress('op1');
      summary = await repo.getOutboxSummary(deviceId: testDeviceId);
      expect(summary.pending, 0);
      expect(summary.inProgress, 1);

      // IN_PROGRESS -> RETRY
      await repo.markOutboxRetry('op1', attemptCount: 1, backoff: const Duration(seconds: 5), error: 'Ağ hatası');
      summary = await repo.getOutboxSummary(deviceId: testDeviceId);
      expect(summary.inProgress, 0);
      expect(summary.retry, 1);

      // RETRY -> SYNCED
      await repo.markOutboxSynced('op1', clientSeq: 1, deviceId: testDeviceId);
      summary = await repo.getOutboxSummary(deviceId: testDeviceId);
      expect(summary.retry, 0);
      expect(summary.totalUnsynced, 0);
      expect(summary.hasPendingWork, isFalse);
    });

    test('Senaryo 9: Farklı cihaz ayrımı doğru çalışır', () async {
      await insertOutboxOp(id: 'op1', seq: 1, status: 'PENDING', deviceId: 'POS-01');
      await insertOutboxOp(id: 'op2', seq: 2, status: 'RETRY', deviceId: 'POS-02');

      final s1 = await repo.getOutboxSummary(deviceId: 'POS-01');
      expect(s1.pending, 1);
      expect(s1.retry, 0);
      expect(s1.totalUnsynced, 1);

      final s2 = await repo.getOutboxSummary(deviceId: 'POS-02');
      expect(s2.pending, 0);
      expect(s2.retry, 1);
      expect(s2.totalUnsynced, 1);

      // deviceId belirtilmezse genel toplam döner
      final sAll = await repo.getOutboxSummary();
      expect(sAll.pending, 1);
      expect(sAll.retry, 1);
      expect(sAll.totalUnsynced, 2);
    });
  });
}

Value<String> drift_value(String val) => Value(val);
