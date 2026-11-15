import 'package:mms_contracts/mms_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('OutboxSummary Model Birim Testleri (mms_contracts)', () {
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
}
