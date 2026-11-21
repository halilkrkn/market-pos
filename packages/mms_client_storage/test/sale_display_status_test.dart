import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:path/path.dart' as p;
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:test/test.dart';

void main() {
  group('MARKET MMS — SaleDisplayStatus Domain Model Testleri', () {
    test('1. fromStatus ham string değerlerini kanonik durumlara ve etiketlere dönüştürür', () {
      expect(SaleDisplayStatus.fromStatus('COMPLETED'), equals(SaleDisplayStatus.completed));
      expect(SaleDisplayStatus.fromStatus('COMPLETED').label, equals('TAMAMLANDI'));

      expect(SaleDisplayStatus.fromStatus('REFUNDED'), equals(SaleDisplayStatus.refunded));
      expect(SaleDisplayStatus.fromStatus('REFUNDED').label, equals('İADE EDİLDİ'));

      expect(SaleDisplayStatus.fromStatus('PARTIALLY_REFUNDED'), equals(SaleDisplayStatus.partiallyRefunded));
      expect(SaleDisplayStatus.fromStatus('PARTIALLY_REFUNDED').label, equals('KISMİ İADE'));

      expect(SaleDisplayStatus.fromStatus('PARTIAL_REFUND'), equals(SaleDisplayStatus.partiallyRefunded));
      expect(SaleDisplayStatus.fromStatus('PARTIAL_REFUND').label, equals('KISMİ İADE'));

      expect(SaleDisplayStatus.fromStatus('CANCELLED'), equals(SaleDisplayStatus.cancelled));
      expect(SaleDisplayStatus.fromStatus('CANCELLED').label, equals('İPTAL EDİLDİ'));

      // Null veya bilinmeyen durumlar güvenli biçimde completed döner
      expect(SaleDisplayStatus.fromStatus(null), equals(SaleDisplayStatus.completed));
      expect(SaleDisplayStatus.fromStatus('UNKNOWN'), equals(SaleDisplayStatus.completed));
    });

    test('2. resolve metodu tutar ve iade durumuna göre doğru durumu çözümler', () {
      // İptal önceliklidir
      expect(
        SaleDisplayStatus.resolve(status: 'CANCELLED', totalAmount: 10000, totalRefundedAmount: 5000),
        equals(SaleDisplayStatus.cancelled),
      );

      // Tam iade
      expect(
        SaleDisplayStatus.resolve(status: 'COMPLETED', totalAmount: 10000, totalRefundedAmount: 10000),
        equals(SaleDisplayStatus.refunded),
      );
      expect(
        SaleDisplayStatus.resolve(status: 'REFUNDED', totalAmount: 10000, totalRefundedAmount: 0),
        equals(SaleDisplayStatus.refunded),
      );

      // Kısmi iade
      expect(
        SaleDisplayStatus.resolve(status: 'COMPLETED', totalAmount: 10000, totalRefundedAmount: 3000),
        equals(SaleDisplayStatus.partiallyRefunded),
      );
      expect(
        SaleDisplayStatus.resolve(status: 'PARTIALLY_REFUNDED'),
        equals(SaleDisplayStatus.partiallyRefunded),
      );

      // Normal satış
      expect(
        SaleDisplayStatus.resolve(status: 'COMPLETED', totalAmount: 10000, totalRefundedAmount: 0),
        equals(SaleDisplayStatus.completed),
      );
    });

    test('3. SaleWithDetails üzerinden displayStatus ve displayStatusLabel doğru üretilir', () {
      final now = DateTime.now();
      final sale = LocalSale(
        id: 'sale_test_001',
        deviceId: 'POS-WIN-01',
        clientSeq: 1,
        totalAmount: 10000,
        paymentMethod: 'CASH',
        status: 'COMPLETED',
        createdAt: now,
      );

      // İadesiz satış
      final noRefundDetail = SaleWithDetails(sale: sale, items: const []);
      expect(noRefundDetail.displayStatus, equals(SaleDisplayStatus.completed));
      expect(noRefundDetail.displayStatusLabel, equals('TAMAMLANDI'));

      // Kısmi iadeli satış
      final partialRefundDetail = SaleWithDetails(
        sale: sale,
        items: const [],
        refunds: [
          RefundWithItems(
            refund: LocalRefund(
              id: 'ref_1',
              saleId: sale.id,
              deviceId: 'POS-WIN-01',
              clientSeq: 2,
              totalRefundAmount: 4000,
              paymentMethod: 'CASH',
              reason: 'Kısmi iade',
              createdAt: now,
            ),
            items: const [],
          ),
        ],
      );
      expect(partialRefundDetail.displayStatus, equals(SaleDisplayStatus.partiallyRefunded));
      expect(partialRefundDetail.displayStatusLabel, equals('KISMİ İADE'));

      // Tam iadeli satış
      final fullRefundDetail = SaleWithDetails(
        sale: sale,
        items: const [],
        refunds: [
          RefundWithItems(
            refund: LocalRefund(
              id: 'ref_2',
              saleId: sale.id,
              deviceId: 'POS-WIN-01',
              clientSeq: 3,
              totalRefundAmount: 10000,
              paymentMethod: 'CASH',
              reason: 'Tam iade',
              createdAt: now,
            ),
            items: const [],
          ),
        ],
      );
      expect(fullRefundDetail.displayStatus, equals(SaleDisplayStatus.refunded));
      expect(fullRefundDetail.displayStatusLabel, equals('İADE EDİLDİ'));
    });

    test('4. reconcileSaleStatuses ve getSalesHistory iade durumunu doğrudan veritabanında onarır ve döndürür', () async {
      final tempDir = await Directory.systemTemp.createTemp('mms_status_reconcile_test_');
      final dbFile = File(p.join(tempDir.path, 'reconcile_test.db'));
      final db = ClientDatabase(dbFile);
      final repo = ClientStorageRepository(db);

      try {
        final now = DateTime.now();

        // 1. Tam iadeli satış (başlangıçta COMPLETED olarak yazılmış)
        await db.into(db.localSales).insert(
          LocalSalesCompanion(
            id: const Value('sale_full_refund'),
            deviceId: const Value('POS-WIN-01'),
            clientSeq: const Value(1),
            totalAmount: const Value(8500),
            paymentMethod: const Value('CASH'),
            status: const Value('COMPLETED'), // Eski/unreconciled durum
            createdAt: Value(now),
          ),
        );
        await db.into(db.localRefunds).insert(
          LocalRefundsCompanion(
            id: const Value('ref_full_1'),
            saleId: const Value('sale_full_refund'),
            deviceId: const Value('POS-WIN-01'),
            clientSeq: const Value(2),
            totalRefundAmount: const Value(8500), // %100 iade
            paymentMethod: const Value('CASH'),
            reason: const Value('Müşteri vazgeçti'),
            createdAt: Value(now),
          ),
        );

        // 2. Kısmi iadeli satış (başlangıçta COMPLETED olarak yazılmış)
        await db.into(db.localSales).insert(
          LocalSalesCompanion(
            id: const Value('sale_partial_refund'),
            deviceId: const Value('POS-WIN-01'),
            clientSeq: const Value(3),
            totalAmount: const Value(10000),
            paymentMethod: const Value('CARD'),
            status: const Value('COMPLETED'), // Eski/unreconciled durum
            createdAt: Value(now.add(const Duration(seconds: 1))),
          ),
        );
        await db.into(db.localRefunds).insert(
          LocalRefundsCompanion(
            id: const Value('ref_partial_1'),
            saleId: const Value('sale_partial_refund'),
            deviceId: const Value('POS-WIN-01'),
            clientSeq: const Value(4),
            totalRefundAmount: const Value(4000), // Kısmi 40 TL iade
            paymentMethod: const Value('CARD'),
            reason: const Value('1 adet bozuk'),
            createdAt: Value(now.add(const Duration(seconds: 1))),
          ),
        );

        // 3. İptal edilmiş satış (iadesi olsa dahi CANCELLED kalmalıdır)
        await db.into(db.localSales).insert(
          LocalSalesCompanion(
            id: const Value('sale_cancelled'),
            deviceId: const Value('POS-WIN-01'),
            clientSeq: const Value(5),
            totalAmount: const Value(5000),
            paymentMethod: const Value('CASH'),
            status: const Value('CANCELLED'),
            cancelReason: const Value('Kasa hatası'),
            createdAt: Value(now.add(const Duration(seconds: 2))),
          ),
        );

        // 4. Normal tamamlanmış satış
        await db.into(db.localSales).insert(
          LocalSalesCompanion(
            id: const Value('sale_normal'),
            deviceId: const Value('POS-WIN-01'),
            clientSeq: const Value(6),
            totalAmount: const Value(3000),
            paymentMethod: const Value('CASH'),
            status: const Value('COMPLETED'),
            createdAt: Value(now.add(const Duration(seconds: 3))),
          ),
        );

        // getSalesHistory çağrısı öncesi local_sales tablosunu doğrula
        final rawFullSale = await (db.select(db.localSales)..where((s) => s.id.equals('sale_full_refund'))).getSingle();
        expect(rawFullSale.status, equals('COMPLETED'));

        // getSalesHistory çağrıldığında otomatik self-healing (reconcileSaleStatuses) çalışır
        final salesHistory = await repo.getSalesHistory();

        // 1. Liste üzerinde dönen durumlar:
        final fullSaleFromList = salesHistory.firstWhere((s) => s.id == 'sale_full_refund');
        expect(fullSaleFromList.status, equals('REFUNDED'));
        expect(SaleDisplayStatus.fromStatus(fullSaleFromList.status).label, equals('İADE EDİLDİ'));

        final partialSaleFromList = salesHistory.firstWhere((s) => s.id == 'sale_partial_refund');
        expect(partialSaleFromList.status, equals('PARTIALLY_REFUNDED'));
        expect(SaleDisplayStatus.fromStatus(partialSaleFromList.status).label, equals('KISMİ İADE'));

        final cancelledSaleFromList = salesHistory.firstWhere((s) => s.id == 'sale_cancelled');
        expect(cancelledSaleFromList.status, equals('CANCELLED'));
        expect(SaleDisplayStatus.fromStatus(cancelledSaleFromList.status).label, equals('İPTAL EDİLDİ'));

        final normalSaleFromList = salesHistory.firstWhere((s) => s.id == 'sale_normal');
        expect(normalSaleFromList.status, equals('COMPLETED'));
        expect(SaleDisplayStatus.fromStatus(normalSaleFromList.status).label, equals('TAMAMLANDI'));

        // 2. Veritabanındaki satırlar kalıcı olarak güncellenmiş olmalıdır:
        final healedFullSale = await (db.select(db.localSales)..where((s) => s.id.equals('sale_full_refund'))).getSingle();
        expect(healedFullSale.status, equals('REFUNDED'));

        final healedPartialSale = await (db.select(db.localSales)..where((s) => s.id.equals('sale_partial_refund'))).getSingle();
        expect(healedPartialSale.status, equals('PARTIALLY_REFUNDED'));

        // 3. Durum filtreleri test:
        final refundedOnly = await repo.getSalesHistory(status: 'REFUNDED');
        expect(refundedOnly.length, equals(1));
        expect(refundedOnly.first.id, equals('sale_full_refund'));

        final partialOnly = await repo.getSalesHistory(status: 'PARTIALLY_REFUNDED');
        expect(partialOnly.length, equals(1));
        expect(partialOnly.first.id, equals('sale_partial_refund'));

        final cancelledOnly = await repo.getSalesHistory(status: 'CANCELLED');
        expect(cancelledOnly.length, equals(1));
        expect(cancelledOnly.first.id, equals('sale_cancelled'));

        final completedOnly = await repo.getSalesHistory(status: 'COMPLETED');
        expect(completedOnly.length, equals(1));
        expect(completedOnly.first.id, equals('sale_normal'));
      } finally {
        await db.close();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });
}
