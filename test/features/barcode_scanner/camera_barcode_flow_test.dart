import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/app/app.dart';
import 'package:market_pos/core/network/api_client.dart';
import 'package:market_pos/core/platform/mms_ui_profile.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/features/barcode_scanner/barcode_scanner_providers.dart';
import 'package:market_pos/features/barcode_scanner/domain/camera_barcode_debounce.dart';
import 'package:market_pos/features/barcode_scanner/domain/camera_scan_result.dart';
import 'package:market_pos/features/barcode_scanner/domain/continuous_scan_session.dart';
import 'package:market_pos/features/pos/pos_providers.dart';
import 'package:market_pos/features/barcode_scanner/presentation/camera_barcode_scanner_service.dart';
import 'package:market_pos/features/catalog/presentation/screens/catalog_screen.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

class _FakeCameraBarcodeScannerService implements CameraBarcodeScannerService {
  CameraScanResult nextResult;
  int callCount = 0;

  /// Sürekli taramada sırayla "okunacak" barkodlar (null ise [nextResult] barkodu).
  List<String>? continuousBarcodes;
  final List<ScanFeedback> feedbacks = [];

  _FakeCameraBarcodeScannerService(this.nextResult);

  @override
  Future<CameraScanResult> scanContinuously(
    BuildContext context, {
    required Future<ScanFeedback> Function(String barcode) onBarcode,
    String title = 'Sürekli Barkod Tarama',
    String subtitle = 'Ürünleri sırayla çerçeveye hizalayın',
  }) async {
    callCount++;
    if (!nextResult.isScanned) return nextResult;
    for (final barcode in continuousBarcodes ?? [nextResult.barcode!]) {
      feedbacks.add(await onBarcode(barcode));
    }
    return const CameraScanResult.cancelled();
  }

  @override
  Future<CameraScanResult> scanBarcode(
    BuildContext context, {
    String title = 'Kamera ile Barkod Tara',
    String subtitle = 'Barkodu çerçeve içerisine yerleştirin',
  }) async {
    callCount++;
    return nextResult;
  }

  @override
  Future<CameraScanResult> scanQrCode(
    BuildContext context, {
    String title = 'QR Kod Tara',
    String subtitle = 'QR kodu çerçeve içerisine yerleştirin',
  }) async {
    callCount++;
    return nextResult;
  }
}

void main() {
  group('Faz 4: Saf Dart Kamera Barkod Debounce & Temizlik Testleri', () {
    test('ardışık aynı kareyi soğuma süresi boyunca bastırır, süre dolunca tekrar kabul eder', () {
      var now = DateTime(2026, 11, 20, 12, 0, 0);
      final debounce = CameraBarcodeDebounce(
        cooldown: const Duration(milliseconds: 1500),
        clock: () => now,
      );

      expect(debounce.acceptRaw('\x028690001122334\r\n'), '8690001122334');
      now = now.add(const Duration(milliseconds: 500));
      expect(debounce.acceptRaw('8690001122334'), isNull);

      // Farklı barkod bekleme süresinden bağımsız kabul edilir
      expect(debounce.acceptRaw('8690009998887'), '8690009998887');

      now = now.add(const Duration(milliseconds: 1600));
      expect(debounce.acceptRaw('8690009998887'), '8690009998887');
    });

    test('boş veya geçersiz barkod karelerini reddeder', () {
      final debounce = CameraBarcodeDebounce();
      expect(debounce.acceptRaw(null), isNull);
      expect(debounce.acceptRaw('   \r\n'), isNull);
      expect(debounce.acceptRaw('869 123'), isNull);
    });

    test('PlatformCameraBarcodeScannerService Windows/masaüstünde unsupportedPlatform döner', () async {
      const service = PlatformCameraBarcodeScannerService(
        isSupportedOverride: _alwaysFalse,
      );
      final navigatorKey = GlobalKey<NavigatorState>();
      expect(service.isSupported, isFalse);
      final res = CameraScanResult.unsupportedPlatform();
      expect(res.status, CameraScanStatus.unsupportedPlatform);
      expect(navigatorKey.currentContext, isNull);
    });
  });

  group('Faz 4: POS ve Ürün Tanımlama Kamera Akışı Testleri', () {
    late LocalDatabaseService localDb;
    late MmsApiClient apiClient;

    setUp(() async {
      localDb = LocalDatabaseService.forTesting(
        NativeDatabase.memory(),
        path: 'C:\\Users\\Mock\\AppData\\Local\\MarketMMS\\faz4_test.db',
      );
      final repo = localDb.repository;
      await repo.initializeDevice('POS-AND-01');
      final cat = await repo.createCategory(name: 'İçecekler');
      await repo.upsertProducts(
        [
          LocalProductsCompanion(
            id: const Value('prod_ayran'),
            barcode: const Value('8690123456789'),
            name: const Value('Ayran 300ml'),
            price: const Value(1250),
            priceVersionId: const Value('pv_ayran_1'),
            stock: const Value(20000),
            stockUnit: const Value('adet'),
            pricingUnit: const Value('adet'),
            conversionFactorNumerator: const Value(1),
            conversionFactorDenominator: const Value(1),
            categoryId: Value(cat.id),
            isActive: const Value(true),
            updatedAt: Value(DateTime(2026, 11, 20, 12, 0)),
          ),
        ],
        barcodes: const [
          LocalProductBarcodesCompanion(
            id: Value('bc_ayran'),
            productId: Value('prod_ayran'),
            barcode: Value('8690123456789'),
            isPrimary: Value(true),
            isActive: Value(true),
          ),
        ],
      );

      final mockClient = MockClient(
        (_) async => http.Response(
          jsonEncode({'status': 'HEALTHY', 'sqlite_version': '3.46.0'}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      apiClient = MmsApiClient(
        client: mockClient,
        baseUrl: 'http://192.168.1.50:8945',
        deviceId: 'POS-AND-01',
      );
    });

    tearDown(() async {
      await localDb.close();
    });

    testWidgets(
      '1. Android POS (390x844 ve 360x640): Kamera ile okutulan barkod ürünü doğrudan sepete ekler, Windows gizler',
      (WidgetTester tester) async {
        final fakeScanner = _FakeCameraBarcodeScannerService(
          const CameraScanResult.scanned('8690123456789'),
        );

        // Windows masaüstü: kamera düğmesi görünmez
        tester.view.physicalSize = const Size(1280, 720);
        tester.view.devicePixelRatio = 1.0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              localDatabaseServiceProvider.overrideWithValue(localDb),
              apiClientProvider.overrideWithValue(apiClient),
              mmsUiProfileProvider.overrideWithValue(const MmsUiProfile.desktop()),
              cameraBarcodeScannerProvider.overrideWithValue(fakeScanner),
            ],
            child: const MarketPosApp(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('pos_camera_scan_button')), findsNothing);

        // Android telefon (360x640 dar telefon dahil sıfır overflow)
        for (final size in [const Size(360, 640), const Size(390, 844)]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                localDatabaseServiceProvider.overrideWithValue(localDb),
                apiClientProvider.overrideWithValue(apiClient),
                mmsUiProfileProvider.overrideWithValue(const MmsUiProfile.mobile()),
                cameraBarcodeScannerProvider.overrideWithValue(fakeScanner),
              ],
              child: const MarketPosApp(),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'POS kamera $size overflow');
        }

        final camBtn = find.byKey(const Key('pos_camera_scan_button'));
        expect(camBtn, findsOneWidget);
        expect(tester.getSize(camBtn).height, greaterThanOrEqualTo(48));

        await tester.tap(camBtn);
        await tester.pumpAndSettle();

        expect(fakeScanner.callCount, 1);
        expect(find.text('Ayran 300ml'), findsOneWidget);
        expect(find.text('12.50 TL'), findsWidgets);

        // İzin reddi senaryosunda anlaşılır uyarı gösterilir, sepet korunur
        fakeScanner.nextResult = const CameraScanResult.permissionDenied();
        await tester.tap(camBtn);
        await tester.pumpAndSettle();
        expect(find.textContaining('Kamera izni'), findsOneWidget);
        expect(find.text('Ayran 300ml'), findsOneWidget);

        addTearDown(tester.view.resetPhysicalSize);
      },
    );

    testWidgets(
      '1b. Android POS sürekli tarama: aynı ürün iki kez okutulunca tek satırda miktar 2 olur, bilinmeyen barkod uyarılır (offline)',
      (WidgetTester tester) async {
        final fakeScanner = _FakeCameraBarcodeScannerService(
          const CameraScanResult.scanned('8690123456789'),
        )..continuousBarcodes = ['8690123456789', '8690123456789', '8699999999994'];

        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              localDatabaseServiceProvider.overrideWithValue(localDb),
              apiClientProvider.overrideWithValue(apiClient),
              mmsUiProfileProvider.overrideWithValue(const MmsUiProfile.mobile()),
              cameraBarcodeScannerProvider.overrideWithValue(fakeScanner),
            ],
            child: const MarketPosApp(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('pos_camera_scan_button')));
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(MarketPosApp)),
        );
        final cart = container.read(cartProvider);
        expect(cart.items, hasLength(1), reason: 'Aynı ürün yeni satır açmamalı');
        expect(cart.items.single.quantityMilli, 2000);

        expect(fakeScanner.feedbacks.map((f) => f.kind).toList(), [
          ScanFeedbackKind.success,
          ScanFeedbackKind.success,
          ScanFeedbackKind.notFound,
        ]);
        expect(fakeScanner.feedbacks[1].message, contains('Ayran 300ml'));
        expect(fakeScanner.feedbacks.last.message, contains('8699999999994'));
      },
    );

    testWidgets(
      '2. Katalog & Ürün Formu (390x844): Kamera ile yeni barkod tarama formu doldurur ve ürün kaydedilir',
      (WidgetTester tester) async {
        final fakeScanner = _FakeCameraBarcodeScannerService(
          const CameraScanResult.scanned('8699988776655'),
        );

        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              localDatabaseServiceProvider.overrideWithValue(localDb),
              apiClientProvider.overrideWithValue(apiClient),
              mmsUiProfileProvider.overrideWithValue(const MmsUiProfile.mobile()),
              cameraBarcodeScannerProvider.overrideWithValue(fakeScanner),
            ],
            child: const MaterialApp(home: CatalogScreen()),
          ),
        );
        await tester.pumpAndSettle();

        final identifyBtn = find.byKey(const Key('catalog_camera_identify_button'));
        expect(identifyBtn, findsOneWidget);
        expect(tester.getSize(identifyBtn).height, greaterThanOrEqualTo(48));

        await tester.tap(identifyBtn);
        await tester.pumpAndSettle();

        expect(find.text('Yeni Ürün Tanımla'), findsOneWidget);
        final textFields = find.byType(TextFormField);
        expect(
          tester.widget<TextFormField>(textFields.at(2)).controller?.text,
          '8699988776655',
        );
        expect(find.byKey(const Key('product_barcode_camera_button')), findsOneWidget);

        await tester.enterText(textFields.at(0), 'Meyve Suyu 1L');
        await tester.enterText(textFields.at(1), '34.50');
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Başlangıç Stoğu (Tam Sayı)'),
          '10',
        );
        await tester.enterText(
          find.byKey(const Key('product_purchase_price_field')),
          '27,40',
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Kaydet'));
        await tester.tap(find.text('Kaydet'));
        await tester.pumpAndSettle();

        expect(find.text('Meyve Suyu 1L'), findsOneWidget);
        expect(find.text('34.50 TL'), findsOneWidget);

        // Faz 2 §4.2.6–9: barkodla kalıcı kayıt, başlangıç alış fiyatı ve Hub'a Outbox kaydı
        final repo = localDb.repository;
        final saved = await repo.getProductByBarcode('8699988776655');
        expect(saved, isNotNull);
        expect(saved!.stock, 10000);
        final db = localDb.database;
        final initial = await (db.select(db.localStockMovements)
              ..where((m) => m.productId.equals(saved.id)))
            .getSingle();
        expect(initial.movementType, 'BASLANGIC_STOK');
        expect(initial.purchasePrice, 2740);
        final upserts = await (db.select(db.outboxOperations)
              ..where((o) => o.operationType.equals('PRODUCT_UPSERT')))
            .get();
        expect(upserts.where((o) => o.payload.contains('8699988776655')), hasLength(1));
      },
    );

    testWidgets(
      '3. Ürün Formu kamera ile katalogda kayıtlı barkod okunduğunda uyarır',
      (WidgetTester tester) async {
        final fakeScanner = _FakeCameraBarcodeScannerService(
          const CameraScanResult.scanned('8690123456789'),
        );

        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              localDatabaseServiceProvider.overrideWithValue(localDb),
              apiClientProvider.overrideWithValue(apiClient),
              mmsUiProfileProvider.overrideWithValue(const MmsUiProfile.mobile()),
              cameraBarcodeScannerProvider.overrideWithValue(fakeScanner),
            ],
            child: const MaterialApp(home: CatalogScreen()),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Yeni Ürün'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('product_barcode_camera_button')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('product_existing_barcode_notice')),
          findsOneWidget,
        );
        expect(find.textContaining('Ayran 300ml'), findsWidgets);
      },
    );
  });
}

bool _alwaysFalse() => false;
