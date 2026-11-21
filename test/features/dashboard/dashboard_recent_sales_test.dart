import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/core/network/api_client.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

void main() {
  group('MARKET MMS — Dashboard Son Satışlar Durum Gösterimi Testleri', () {
    late LocalDatabaseService localDb;
    late MmsApiClient apiClient;
    const testDeviceId = 'POS-WIN-01';

    setUp(() async {
      localDb = LocalDatabaseService.forTesting(
        NativeDatabase.memory(),
        path: 'C:\\Users\\Mock\\AppData\\Local\\MarketMMS\\client_local.db',
      );

      final mockClient =
          MockClient((request) async => http.Response('{"status":"UP"}', 200));
      apiClient = MmsApiClient(
        client: mockClient,
        baseUrl: 'http://127.0.0.1:8945',
        deviceId: testDeviceId,
      );

      final repo = localDb.repository;
      await repo.initializeDevice(testDeviceId);

      // Test ürünü ekle
      final prod = await repo.createProduct(
        name: 'Çay 1Kg',
        price: 12000, // 120.00 TL
        barcode: '86900010001',
        initialStock: 100000,
      );

      // 1. Normal satış (TAMAMLANDI)
      await repo.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units(prod.id, 1)],
      );

      // 2. İptal edilen satış (İPTAL EDİLDİ)
      final cancelSaleRes = await repo.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units(prod.id, 1)],
      );
      await repo.cancelSale(
        saleId: cancelSaleRes.saleId,
        reason: 'Yanlış barkod okutuldu',
        deviceId: testDeviceId,
      );

      // 3. Tam iade edilen satış (İADE EDİLDİ)
      final fullRefundSaleRes = await repo.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CARD',
        items: [CartItemInput.units(prod.id, 1)],
      );
      final fullDetail = await repo.getSaleDetail(fullRefundSaleRes.saleId);
      await repo.refundSale(
        saleId: fullRefundSaleRes.saleId,
        items: [
          RefundItemInput(
            saleItemId: fullDetail!.items.first.id,
            quantity: fullDetail.items.first.quantity,
          ),
        ],
        reason: 'Müşteri iade etti',
        deviceId: testDeviceId,
      );

      // 4. Kısmi iade edilen satış (KISMİ İADE) - 3 adet satılıp 1 adedi iade edildi
      final partialRefundSaleRes = await repo.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units(prod.id, 3)],
      );
      final partialDetail = await repo.getSaleDetail(partialRefundSaleRes.saleId);
      await repo.refundSale(
        saleId: partialRefundSaleRes.saleId,
        items: [
          RefundItemInput(
            saleItemId: partialDetail!.items.first.id,
            quantity: 1000, // 3 adetten 1 adedi iade
          ),
        ],
        reason: '1 paket iade',
        deviceId: testDeviceId,
      );
    });

    tearDown(() async {
      await localDb.close();
      await LocalDatabaseService.closeActive();
      LocalDatabaseService.resetForTesting();
    });

    Widget createTestWidget() {
      return ProviderScope(
        overrides: [
          localDatabaseServiceProvider.overrideWithValue(localDb),
          apiClientProvider.overrideWithValue(apiClient),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: DashboardScreen(),
          ),
        ),
      );
    }

    testWidgets(
        'Dashboard Son Satışlar kartında TAMAMLANDI, İPTAL EDİLDİ, İADE EDİLDİ ve KISMİ İADE rozetleri doğru render edilir',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Son Satışlar kartı başlığı render edilmeli
      expect(find.text('Son Satışlar'), findsOneWidget);

      // 4 kanonik durum etiketi de Son Satışlar listesinde görünmeli
      expect(find.text('TAMAMLANDI'), findsOneWidget);
      expect(find.text('İPTAL EDİLDİ'), findsOneWidget);
      expect(find.text('İADE EDİLDİ'), findsOneWidget);
      expect(find.text('KISMİ İADE'), findsOneWidget);
    });

    testWidgets(
        'Dashboard Son Satışlar listesindeki bir fişe tıklandığında Fiş Detay modalı açılır',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Son Satışlar listesindeki bir satış satırına tıkla
      final saleRowFinder = find.text('KISMİ İADE');
      expect(saleRowFinder, findsOneWidget);
      await tester.ensureVisible(saleRowFinder);
      await tester.pumpAndSettle();

      await tester.tap(saleRowFinder);
      await tester.pumpAndSettle();

      // Fiş detay modalı açılmalı ve kalemler ile rozet doğrulanmalı
      expect(find.textContaining('Fiş Detayı:'), findsOneWidget);
      expect(find.text('Kapat'), findsOneWidget);

      // Kapat butonuna tıkla
      await tester.tap(find.text('Kapat'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Fiş Detayı:'), findsNothing);
    });
  });
}
