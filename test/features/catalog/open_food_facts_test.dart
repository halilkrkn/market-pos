import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/core/network/api_client.dart';
import 'package:market_pos/core/platform/mms_ui_profile.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/features/barcode_scanner/barcode_scanner_providers.dart';
import 'package:market_pos/features/barcode_scanner/domain/camera_scan_result.dart';
import 'package:market_pos/features/barcode_scanner/domain/continuous_scan_session.dart';
import 'package:market_pos/features/barcode_scanner/presentation/camera_barcode_scanner_service.dart';
import 'package:market_pos/features/catalog/catalog_providers.dart';
import 'package:market_pos/features/catalog/data/open_food_facts_client.dart';
import 'package:market_pos/features/catalog/domain/external_product_lookup_service.dart';
import 'package:market_pos/features/catalog/domain/external_product_suggestion.dart';
import 'package:market_pos/features/catalog/presentation/screens/catalog_screen.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';

class _FakeExternalLookupService implements ExternalProductLookupService {
  ExternalProductLookupResult Function(String barcode) handler;
  int callCount = 0;

  _FakeExternalLookupService(this.handler);

  @override
  Future<ExternalProductLookupResult> lookupByBarcode(String barcode) async {
    callCount++;
    return handler(barcode);
  }
}

class _FakeCameraScanner implements CameraBarcodeScannerService {
  final CameraScanResult result;
  _FakeCameraScanner(this.result);

  @override
  Future<CameraScanResult> scanBarcode(
    BuildContext context, {
    String title = 'Kamera ile Barkod Tara',
    String subtitle = 'Barkodu çerçeve içerisine yerleştirin',
  }) async {
    return result;
  }

  @override
  Future<CameraScanResult> scanQrCode(
    BuildContext context, {
    String title = 'QR Kod Tara',
    String subtitle = 'QR kodu çerçeve içerisine yerleştirin',
  }) async {
    return result;
  }

  @override
  Future<CameraScanResult> scanContinuously(
    BuildContext context, {
    required Future<ScanFeedback> Function(String barcode) onBarcode,
    String title = 'Sürekli Barkod Tarama',
    String subtitle = 'Ürünleri sırayla çerçeveye hizalayın',
  }) async =>
      const CameraScanResult.cancelled();
}

void main() {
  group('Faz 5: OpenFoodFactsClient Birim Testleri', () {
    test('HTTP 200 ürün yanıtını ad, marka, kategori, görsel, içindekiler ve besin değerleriyle ayrıştırır', () async {
      final client = OpenFoodFactsClient(
        client: MockClient((request) async {
          expect(request.url.path, '/api/v2/product/8690504012345.json');
          expect(request.headers['User-Agent'], contains('MarketMMS'));
          return http.Response(
            jsonEncode({
              'status': 1,
              'product': {
                'code': '8690504012345',
                'product_name_tr': 'Sade Bisküvi',
                'product_name': 'Plain Biscuit',
                'brands': 'Eti',
                'categories': 'tr:Atıştırmalıklar, en:Biscuits',
                'image_front_small_url':
                    'https://images.openfoodfacts.org/example.jpg',
                'ingredients_text_tr': 'Buğday unu, bitkisel yağ, şeker',
                'quantity': '125 g',
                'nutriments': {
                  'energy-kcal_100g': 450,
                  'fat_100g': 14.5,
                  'carbohydrates_100g': 71,
                  'sugars_100g': 18.2,
                  'proteins_100g': 7.5,
                  'salt_100g': 0.8,
                },
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await client.lookupByBarcode('8690504012345');
      expect(result.isFound, isTrue);
      final s = result.suggestion!;
      expect(s.productName, 'Sade Bisküvi');
      expect(s.brand, 'Eti');
      expect(s.suggestedDisplayName, 'Eti Sade Bisküvi 125 g');
      expect(s.categories, ['Atıştırmalıklar', 'Biscuits']);
      expect(s.imageUrl, 'https://images.openfoodfacts.org/example.jpg');
      expect(s.ingredientsText, 'Buğday unu, bitkisel yağ, şeker');
      expect(s.suggestedUnit, 'g');
      expect(s.nutrition?.energyKcal100g, '450 kcal');
      expect(s.nutrition?.fat100g, '14.5 g');
      expect(s.nutrition?.proteins100g, '7.5 g');
    });

    test('404 veya status=0 yanıtında notFound döner, exception fırlatmaz', () async {
      final notFoundHttp = OpenFoodFactsClient(
        client: MockClient((_) async => http.Response('Not Found', 404)),
      );
      expect(
        (await notFoundHttp.lookupByBarcode('8690000000001')).status,
        ExternalProductLookupStatus.notFound,
      );

      final statusZero = OpenFoodFactsClient(
        client: MockClient(
          (_) async => http.Response(jsonEncode({'status': 0}), 200),
        ),
      );
      expect(
        (await statusZero.lookupByBarcode('8690000000001')).status,
        ExternalProductLookupStatus.notFound,
      );
    });

    test('ağ kesintisi, zaman aşımı ve bozuk JSON durumlarında güvenli error döner', () async {
      final offlineClient = OpenFoodFactsClient(
        client: MockClient((_) async => throw const SocketException('No route')),
      );
      final resOffline = await offlineClient.lookupByBarcode('8690504012345');
      expect(resOffline.status, ExternalProductLookupStatus.error);
      expect(resOffline.message, contains('elle tanımlayabilirsiniz'));

      final timeoutClient = OpenFoodFactsClient(
        client: MockClient((_) async => throw TimeoutException('timeout')),
      );
      expect(
        (await timeoutClient.lookupByBarcode('8690504012345')).status,
        ExternalProductLookupStatus.error,
      );

      final malformedClient = OpenFoodFactsClient(
        client: MockClient((_) async => http.Response('{invalid json', 200)),
      );
      expect(
        (await malformedClient.lookupByBarcode('8690504012345')).status,
        ExternalProductLookupStatus.error,
      );
    });

    test('geçersiz barkodda ağ çağrısı yapmadan invalidBarcode döner', () async {
      var called = false;
      final client = OpenFoodFactsClient(
        client: MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );
      final res = await client.lookupByBarcode('   ');
      expect(res.status, ExternalProductLookupStatus.invalidBarcode);
      expect(called, isFalse);
    });
  });

  group('Faz 5: ProductEditDialog Open Food Facts Öneri ve İş Kuralları Testleri', () {
    late LocalDatabaseService localDb;
    late MmsApiClient apiClient;

    setUp(() async {
      localDb = LocalDatabaseService.forTesting(
        NativeDatabase.memory(),
        path: 'C:\\Users\\Mock\\AppData\\Local\\MarketMMS\\faz5_test.db',
      );
      final repo = localDb.repository;
      await repo.initializeDevice('POS-AND-01');
      await repo.createCategory(name: 'İçecekler');

      apiClient = MmsApiClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'status': 'HEALTHY', 'sqlite_version': '3.46.0'}),
            200,
          ),
        ),
        baseUrl: 'http://192.168.1.50:8945',
        deviceId: 'POS-AND-01',
      );
    });

    tearDown(() async {
      await localDb.close();
    });

    testWidgets(
      '1. Kamera barkodu sonrası Open Food Facts önerisi gösterilir, fiyat/stok OTOMATİK DOLDURULMAZ, düzenleyerek kaydedilir',
      (WidgetTester tester) async {
        final fakeOff = _FakeExternalLookupService((barcode) {
          return ExternalProductLookupResult.found(
            ExternalProductSuggestion(
              barcode: barcode,
              productName: 'Doğal Maden Suyu',
              brand: 'Beypazarı',
              categories: const ['İçecekler', 'Maden Suyu'],
              imageUrl: 'https://images.openfoodfacts.org/water.jpg',
              ingredientsText: 'Doğal mineralli su',
              quantityText: '200 ml',
              suggestedUnit: 'ml',
              nutrition: const NutritionFactsSummary(
                energyKcal100g: '0 kcal',
                salt100g: '0.1 g',
              ),
            ),
          );
        });

        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              localDatabaseServiceProvider.overrideWithValue(localDb),
              apiClientProvider.overrideWithValue(apiClient),
              mmsUiProfileProvider.overrideWithValue(const MmsUiProfile.mobile()),
              cameraBarcodeScannerProvider.overrideWithValue(
                _FakeCameraScanner(
                  const CameraScanResult.scanned('8690562000018'),
                ),
              ),
              externalProductLookupServiceProvider.overrideWithValue(fakeOff),
              externalProductImageBuilderProvider.overrideWithValue(
                (_, url) => Icon(
                  Icons.local_drink_outlined,
                  key: ValueKey('mock_img_$url'),
                ),
              ),
            ],
            child: const MaterialApp(home: CatalogScreen()),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('catalog_camera_identify_button')));
        await tester.pumpAndSettle();

        expect(fakeOff.callCount, 1);
        expect(find.byKey(const Key('off_suggestion_card')), findsOneWidget);
        expect(find.textContaining('Marka: Beypazarı'), findsOneWidget);
        expect(
          find.textContaining('İçindekiler: Doğal mineralli su'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Satış fiyatı, maliyet ve stok otomatik doldurulmaz'),
          findsOneWidget,
        );

        // Kullanıcı formda aktar butonuna basmadan ürün adı boş ve fiyat boş
        final textFields = find.byType(TextFormField);
        expect(tester.widget<TextFormField>(textFields.at(0)).controller?.text, isEmpty);
        expect(tester.widget<TextFormField>(textFields.at(1)).controller?.text, isEmpty);

        // Öneriyi forma aktar -> yalnızca ad/birim/kategori dolar; fiyat ve stok otomatik atanmaz!
        final applyBtn = find.byKey(const Key('off_apply_suggestion_button'));
        await tester.ensureVisible(applyBtn);
        await tester.pumpAndSettle();
        await tester.tap(applyBtn);
        await tester.pumpAndSettle();

        expect(
          tester.widget<TextFormField>(textFields.at(0)).controller?.text,
          'Beypazarı Doğal Maden Suyu 200 ml',
        );
        expect(
          tester.widget<TextFormField>(textFields.at(1)).controller?.text,
          isEmpty,
        );
        expect(
          tester.widget<TextFormField>(textFields.at(3)).controller?.text,
          '0',
        );

        // Fiyat girmeden Kaydet denirse validation engellemeli (kullanıcı fiyatı belirler)
        await tester.tap(find.text('Kaydet'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Fiyat giriniz.'));
        await tester.pumpAndSettle();
        expect(find.text('Fiyat giriniz.'), findsOneWidget);

        // Kullanıcı önerilen adı düzenleyip fiyat & başlangıç stoğunu elle girerek kaydeder
        await tester.ensureVisible(textFields.at(0));
        await tester.enterText(
          textFields.at(0),
          'Beypazarı Sade Soda 200ml',
        );
        await tester.ensureVisible(textFields.at(1));
        await tester.enterText(textFields.at(1), '9.50');
        await tester.ensureVisible(textFields.at(3));
        await tester.enterText(textFields.at(3), '48');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Kaydet'));
        await tester.pumpAndSettle();

        expect(find.text('Beypazarı Sade Soda 200ml'), findsOneWidget);
        expect(find.text('9.50 TL'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '2. Harici API hatası / çevrimdışı durumda ürün oluşturma ENGELLENMEZ, elle kaydedilir',
      (WidgetTester tester) async {
        final failingOff = _FakeExternalLookupService(
          (barcode) => ExternalProductLookupResult.error(barcode),
        );

        tester.view.physicalSize = const Size(1024, 768);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              localDatabaseServiceProvider.overrideWithValue(localDb),
              apiClientProvider.overrideWithValue(apiClient),
              mmsUiProfileProvider.overrideWithValue(const MmsUiProfile.desktop()),
              externalProductLookupServiceProvider.overrideWithValue(failingOff),
            ],
            child: const MaterialApp(home: CatalogScreen()),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Yeni Ürün'));
        await tester.pumpAndSettle();

        final textFields = find.byType(TextFormField);
        await tester.enterText(textFields.at(2), '8690001112223');
        await tester.pumpAndSettle();

        final lookupBtn = find.byKey(const Key('product_off_lookup_button'));
        await tester.ensureVisible(lookupBtn);
        await tester.pumpAndSettle();
        await tester.tap(lookupBtn);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('off_lookup_status_banner')), findsOneWidget);
        expect(find.textContaining('elle girebilirsiniz'), findsOneWidget);

        // Hata olmasına rağmen ürün elle eksiksiz oluşturulur
        await tester.enterText(textFields.at(0), 'Manuel Kahve 100g');
        await tester.enterText(textFields.at(1), '85.00');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Kaydet'));
        await tester.pumpAndSettle();

        expect(find.text('Manuel Kahve 100g'), findsOneWidget);
        expect(find.text('85.00 TL'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
