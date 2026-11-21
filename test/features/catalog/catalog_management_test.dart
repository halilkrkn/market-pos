import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/core/network/api_client.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/features/catalog/presentation/screens/catalog_screen.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

void main() {
  group('FAZ 1.4: Ürün ve Kategori Yönetimi UI Testleri', () {
    late LocalDatabaseService localDb;
    late MmsApiClient apiClient;

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

      final cat = await repo.createCategory(name: 'Unlu Mamuller');
      await repo.createProduct(
        name: 'Simit',
        price: 1500, // 15.00 TL
        barcode: '8690077',
        categoryId: cat.id,
        initialStock: 100000,
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
          home: CatalogScreen(),
        ),
      );
    }

    testWidgets('Katalog ekranı ve ürün listesi render edilir',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Başlık
      expect(find.text('Ürün ve Stok Yönetimi'), findsOneWidget);

      // Sekmeler
      expect(find.text('Ürün Kataloğu'), findsOneWidget);
      expect(find.text('Kategoriler'), findsOneWidget);

      // Ürün
      expect(find.text('Simit'), findsOneWidget);
      expect(find.text('15.00 TL'), findsOneWidget);
      expect(find.text('Unlu Mamuller'), findsOneWidget);
      expect(find.text('AKTİF'), findsOneWidget);
    });

    testWidgets('Yeni ürün oluşturma akışı (BR-PROD-01)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // "Yeni Ürün" butonuna tıkla
      await tester.tap(find.text('Yeni Ürün'));
      await tester.pumpAndSettle();

      expect(find.text('Yeni Ürün Tanımla'), findsOneWidget);

      // Formu doldur
      final textFields = find.byType(TextFormField);
      await tester.enterText(textFields.at(0), 'Poğaça'); // Ad
      await tester.enterText(textFields.at(1), '20.00'); // Fiyat
      await tester.enterText(textFields.at(2), '8690088'); // Barkod
      await tester.pumpAndSettle();

      // Kaydet
      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();

      // Listede yeni ürün görünmeli
      expect(find.text('Poğaça'), findsOneWidget);
      expect(find.text('20.00 TL'), findsOneWidget);
    });

    testWidgets('Kategoriler sekmesi ve yeni kategori ekleme akışı (BR-PROD-14)',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Kategoriler sekmesine geç
      await tester.tap(find.text('Kategoriler'));
      await tester.pumpAndSettle();

      expect(find.text('Unlu Mamuller'), findsOneWidget);

      // "Yeni Kategori" butonuna tıkla
      await tester.tap(find.text('Yeni Kategori'));
      await tester.pumpAndSettle();

      expect(find.text('Yeni Kategori Ekle'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'Tatlılar');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Kaydet'));
      await tester.pumpAndSettle();

      expect(find.text('Tatlılar'), findsOneWidget);
    });
  });
}
