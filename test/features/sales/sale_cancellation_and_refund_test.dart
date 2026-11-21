import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/core/network/api_client.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:market_pos/features/sales/presentation/screens/sales_history_screen.dart';
import 'package:market_pos/features/sales/presentation/widgets/sale_detail_dialog.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

void main() {
  group('FAZ 1.3.3 & 1.3.4: Satış İptali ve Kısmi İade UI Testleri', () {
    late LocalDatabaseService localDb;
    late MmsApiClient apiClient;
    late LocalProduct testProduct;

    const testDeviceId = 'POS-WIN-01';

    setUp(() async {
      localDb = LocalDatabaseService.forTesting(
        NativeDatabase.memory(),
        path: 'C:\\Users\\Mock\\AppData\\Local\\MarketMMS\\client_local.db',
      );

      final mockClient = MockClient((request) async => http.Response('{}', 200));
      apiClient = MmsApiClient(
        client: mockClient,
        baseUrl: 'https://127.0.0.1:8443',
        deviceId: testDeviceId,
      );

      final repo = localDb.repository;
      await repo.initializeDevice(testDeviceId);

      testProduct = await repo.createProduct(
        name: 'Zeytin 500g',
        price: 4000, // 40.00 TL
        barcode: '8690099',
        initialStock: 30000, // 30 adet
      );

      await repo.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [
          CartItemInput.units(testProduct.id, 2), // 2 adet = 80.00 TL
        ],
      );
    });

    tearDown(() async {
      await localDb.close();
    });

    Widget createTestWidget() {
      return ProviderScope(
        overrides: [
          localDatabaseServiceProvider.overrideWithValue(localDb),
          apiClientProvider.overrideWithValue(apiClient),
        ],
        child: const MaterialApp(
          home: SalesHistoryScreen(),
        ),
      );
    }

    testWidgets('Tam Satış İptali Akışı (FAZ 1.3.3): Fiş detayından iptal onaylanır',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Fiş detayını aç
      await tester.tap(find.text('Fiş Detay'));
      await tester.pumpAndSettle();

      // "Satışı İptal Et" butonuna tıkla
      expect(find.text('Satışı İptal Et'), findsOneWidget);
      await tester.tap(find.text('Satışı İptal Et'));
      await tester.pumpAndSettle();

      // İptal diyaloğu açılır
      expect(find.text('Tam Satış İptali'), findsOneWidget);

      // Gerekçe girmeden onayla -> validasyon hatası
      await tester.tap(find.text('İptali Onayla'));
      await tester.pumpAndSettle();
      expect(find.text('Lütfen geçerli bir iptal gerekçesi giriniz.'), findsOneWidget);

      // Gerekçe gir
      await tester.enterText(find.byType(TextFormField).last, 'Müşteri vazgeçti');
      await tester.pumpAndSettle();

      await tester.tap(find.text('İptali Onayla'));
      await tester.pumpAndSettle();

      // Fiş detayı güncellenmeli: Durum İPTAL EDİLDİ olmalı
      expect(
        find.descendant(
          of: find.byType(SaleDetailDialog),
          matching: find.text('İPTAL EDİLDİ'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('İptal Nedeni: Müşteri vazgeçti'), findsOneWidget);

      // İptal edildikten sonra "Satışı İptal Et" butonu kaybolmalıdır
      expect(find.text('Satışı İptal Et'), findsNothing);

      // Kapat
      await tester.tap(find.text('Kapat'));
      await tester.pumpAndSettle();

      // Ana listede ortak etiketli İPTAL EDİLDİ rozeti görünmeli
      expect(find.text('İPTAL EDİLDİ'), findsOneWidget);
    });

    testWidgets('Kısmi İade Akışı (FAZ 1.3.4): 1 adet ürün iadesi tamamlanır',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Fiş detayını aç
      await tester.tap(find.text('Fiş Detay'));
      await tester.pumpAndSettle();

      // "Kısmi İade Yap" butonuna tıkla
      expect(find.text('Kısmi İade Yap'), findsOneWidget);
      await tester.tap(find.text('Kısmi İade Yap'));
      await tester.pumpAndSettle();

      // İade diyaloğu açılır
      expect(find.text('Kısmi Ürün İadesi'), findsOneWidget);

      // 1 adet ekle (+ butonu)
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();

      // Önizleme tutarı 40.00 TL olmalı
      expect(find.text('40.00 TL'), findsWidgets);

      // Gerekçe gir
      await tester.enterText(find.byType(TextFormField).last, 'Müşteri 1 adedini iade etti');
      await tester.pumpAndSettle();

      // İadeyi Tamamla
      await tester.tap(find.text('İadeyi Tamamla'));
      await tester.pumpAndSettle();

      // Fiş detayında Yapılan İadeler bölümü görünmeli
      expect(find.text('Yapılan İadeler'), findsOneWidget);
      expect(find.textContaining('-40.00 TL'), findsOneWidget);
      expect(find.text('40.00 TL'), findsWidgets); // Net tutar 40.00 TL
    });
  });
}
