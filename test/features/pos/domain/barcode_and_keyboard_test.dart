import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/app/app.dart';
import 'package:market_pos/core/network/api_client.dart';
import 'package:market_pos/core/platform/mms_ui_profile.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:market_pos/features/pos/application/cart_notifier.dart';
import 'package:market_pos/features/pos/application/hardware_barcode_buffer.dart';
import 'package:market_pos/features/pos/domain/barcode_input_sanitizer.dart';
import 'package:market_pos/features/pos/domain/cart_state.dart';
import 'package:market_pos/features/pos/domain/pos_product.dart';
import 'package:market_pos/features/pos/domain/pos_repository.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

class _SanitizingPosRepo implements PosRepository {
  final Map<String, PosProduct> products;

  _SanitizingPosRepo(this.products);

  @override
  Future<BarcodeLookupResult> findByBarcode(String barcode) async {
    final found = products[barcode];
    if (found == null) {
      return BarcodeLookupResult.notFoundOffline(barcode);
    }
    if (!found.isActive) {
      return BarcodeLookupResult.inactiveProduct(found, barcode);
    }
    return BarcodeLookupResult.found(found, barcode);
  }

  @override
  Future<List<PosProduct>> searchActiveProducts(
    String query, {
    int limit = 50,
  }) async {
    return products.values.where((p) => p.isActive).toList();
  }

  @override
  Future<PosCompletedSale> completeOfflineSale({
    required String deviceId,
    required CartState cart,
    required PaymentMethod paymentMethod,
    int? cashReceivedCents,
    required bool externalPosConfirmed,
  }) {
    throw UnimplementedError();
  }
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  group('Faz 3.1: BarcodeInputSanitizer ve HardwareBarcodeBuffer Birim Testleri', () {
    test('BarcodeInputSanitizer kontrol karakterlerini temizler ve geçersiz biçimleri reddeder', () {
      final cleanEan = BarcodeInputSanitizer.sanitize('\x028690504018241\r\n\x03');
      expect(cleanEan.isValid, isTrue);
      expect(cleanEan.normalized, '8690504018241');

      final code128 = BarcodeInputSanitizer.sanitize('  ITEM-99_A \t\x1D');
      expect(code128.isValid, isTrue);
      expect(code128.normalized, 'ITEM-99_A');

      final empty = BarcodeInputSanitizer.sanitize(' \r\n\t\x02\x03 ');
      expect(empty.isValid, isFalse);
      expect(empty.status, BarcodeValidationStatus.empty);

      final withSpaces = BarcodeInputSanitizer.sanitize('8690 5040');
      expect(withSpaces.isValid, isFalse);
      expect(withSpaces.status, BarcodeValidationStatus.invalidFormat);

      final tooLong = BarcodeInputSanitizer.sanitize('1' * 65);
      expect(tooLong.isValid, isFalse);
      expect(tooLong.status, BarcodeValidationStatus.invalidFormat);
    });

    test('HardwareBarcodeBuffer hızlı HID taramasını toplar; yavaş veya kısa girdileri eler', () {
      var now = DateTime(2026, 11, 20, 10, 0, 0);
      final buffer = HardwareBarcodeBuffer(clock: () => now);

      for (final ch in '8690101'.split('')) {
        buffer.feedCharacter(ch);
        now = now.add(const Duration(milliseconds: 12));
      }
      expect(buffer.hasBufferedInput, isTrue);
      expect(buffer.commit(), '8690101');
      // Çift Enter (\r\n) tekrar tetikleme üretmemeli
      expect(buffer.commit(), isNull);

      // Yavaş manuel basımlar zaman aşımı nedeniyle önceki tamponu sıfırlar
      buffer.feedCharacter('8');
      now = now.add(const Duration(milliseconds: 250));
      buffer.feedCharacter('9');
      expect(buffer.commit(), isNull);

      // Kısa gürültü (< 4 karakter) reddedilir
      buffer.feedCharacter('1');
      buffer.feedCharacter('2');
      buffer.feedCharacter('3');
      expect(buffer.commit(), isNull);
    });

    test('CartNotifier.scanBarcode HID kontrol karakterli barkodu ekler, bozuk formatı reddeder', () async {
      const sut = PosProduct(
        id: 'prod_sut',
        primaryBarcode: '8690101',
        name: 'Tam Yağlı Süt 1L',
        priceCents: 3250,
        priceVersionId: 'pv_1',
        stockMilli: 10000,
        stockUnit: 'adet',
        pricingUnit: 'adet',
        conversionFactorNumerator: 1,
        conversionFactorDenominator: 1,
        isActive: true,
      );
      final notifier = CartNotifier(
        repository: _SanitizingPosRepo({'8690101': sut}),
        readDeviceId: () => 'POS-TEST-01',
      );

      final added = await notifier.scanBarcode('\x02 8690101 \r\n\x03');
      expect(added, isTrue);
      expect(notifier.state.items.single.productId, 'prod_sut');

      final invalid = await notifier.scanBarcode('8690 101');
      expect(invalid, isFalse);
      expect(notifier.state.errorMessage, contains('Geçersiz barkod biçimi'));
      expect(notifier.state.items.single.quantityMilli, 1000);
    });
  });

  group('Faz 3.2 & 3.3: Windows ve Android Platform Özel Klavye/Barkod Testleri', () {
    late Directory tempDir;
    late LocalDatabaseService localDb;
    late MmsApiClient apiClient;

    Future<void> simulateHidScan(WidgetTester tester, String digits) async {
      final keyMap = <String, LogicalKeyboardKey>{
        '0': LogicalKeyboardKey.digit0,
        '1': LogicalKeyboardKey.digit1,
        '2': LogicalKeyboardKey.digit2,
        '3': LogicalKeyboardKey.digit3,
        '4': LogicalKeyboardKey.digit4,
        '5': LogicalKeyboardKey.digit5,
        '6': LogicalKeyboardKey.digit6,
        '7': LogicalKeyboardKey.digit7,
        '8': LogicalKeyboardKey.digit8,
        '9': LogicalKeyboardKey.digit9,
      };
      for (final ch in digits.split('')) {
        await tester.sendKeyEvent(keyMap[ch]!);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
    }

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('mms_faz3_hid_test_');
      final dbFile = File(p.join(tempDir.path, 'client_local.db'));
      localDb = LocalDatabaseService.forTesting(
        NativeDatabase(dbFile),
        path: dbFile.path,
      );

      await localDb.repository.upsertProducts(
        [
          const LocalProductsCompanion(
            id: Value('prod_ekmek'),
            barcode: Value('8690504018241'),
            name: Value('Somun Ekmek 200g'),
            price: Value(1250),
            priceVersionId: Value('pv_1'),
            stock: Value(5000),
            stockUnit: Value('adet'),
            pricingUnit: Value('adet'),
            conversionFactorNumerator: Value(1),
            conversionFactorDenominator: Value(1),
            isActive: Value(true),
          ),
          const LocalProductsCompanion(
            id: Value('prod_su'),
            barcode: Value('8690000111222'),
            name: Value('Doğal Kaynak Suyu 1.5L'),
            price: Value(850),
            priceVersionId: Value('pv_su_1'),
            stock: Value(24000),
            stockUnit: Value('adet'),
            pricingUnit: Value('adet'),
            conversionFactorNumerator: Value(1),
            conversionFactorDenominator: Value(1),
            isActive: Value(true),
          ),
        ],
        barcodes: const [
          LocalProductBarcodesCompanion(
            id: Value('bc_ekmek'),
            productId: Value('prod_ekmek'),
            barcode: Value('8690504018241'),
            isPrimary: Value(true),
            isActive: Value(true),
          ),
          LocalProductBarcodesCompanion(
            id: Value('bc_su'),
            productId: Value('prod_su'),
            barcode: Value('8690000111222'),
            isPrimary: Value(true),
            isActive: Value(true),
          ),
        ],
      );

      final mockClient = MockClient(
        (request) async => http.Response(
          jsonEncode({'status': 'HEALTHY', 'sqlite_version': '3.46.0'}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      apiClient = MmsApiClient(
        client: mockClient,
        baseUrl: 'https://127.0.0.1:8443',
        deviceId: 'POS-TEST-01',
      );
    });

    tearDown(() async {
      await localDb.close();
      await LocalDatabaseService.closeActive();
      LocalDatabaseService.resetForTesting();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    Widget buildTestApp(MmsUiProfile profile) {
      return ProviderScope(
        overrides: [
          localDatabaseServiceProvider.overrideWithValue(localDb),
          apiClientProvider.overrideWithValue(apiClient),
          mmsUiProfileProvider.overrideWithValue(profile),
        ],
        child: const MarketPosApp(),
      );
    }

    testWidgets(
      'Windows Masaüstü (1280x720): Otomatik odak, odak dışı USB HID yakalama, arama Enter ve hata aksiyonu',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 720);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(buildTestApp(const MmsUiProfile.desktop()));
        await tester.pumpAndSettle();

        final barcodeFieldWidget = tester.widget<TextField>(
          find.byKey(const Key('barcode_input_field')),
        );
        expect(barcodeFieldWidget.autofocus, isTrue);
        expect(barcodeFieldWidget.focusNode!.hasFocus, isTrue);

        // Odak barkod kutusundan çıktığında da USB HID tarayıcı doğrudan sepete ekleyebilmeli
        barcodeFieldWidget.focusNode!.unfocus();
        await tester.pump();
        expect(barcodeFieldWidget.focusNode!.hasFocus, isFalse);

        await simulateHidScan(tester, '8690504018241');
        expect(find.text('Somun Ekmek 200g'), findsOneWidget);
        expect(barcodeFieldWidget.focusNode!.hasFocus, isTrue);

        // Bulunamayan barkod hata şeridinden "Ürün Ara" hızlı aksiyonu açılır
        await tester.enterText(
          find.byKey(const Key('barcode_input_field')),
          '9999999999999',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('error_banner_search_button')), findsOneWidget);
        await tester.tap(find.byKey(const Key('error_banner_search_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('product_search_dialog')), findsOneWidget);

        // Ürün arama diyalogunda tek eşleşmeye Enter basılınca doğrudan sepete eklenir ve kapanır
        await tester.enterText(
          find.byKey(const Key('product_search_input')),
          'Kaynak Suyu',
        );
        await tester.pumpAndSettle();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('product_search_dialog')), findsNothing);
        expect(find.text('Doğal Kaynak Suyu 1.5L'), findsOneWidget);
        // Modal kapanışı sonrası Windows'ta odak barkod kutusuna geri döner
        expect(barcodeFieldWidget.focusNode!.hasFocus, isTrue);
      },
    );

    testWidgets(
      'Android (390x844): Ekran klavyesi açılmaz, harici HID tarayıcı çalışır, F1/F9/F10 tetiklenmez',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(buildTestApp(const MmsUiProfile.mobile()));
        await tester.pumpAndSettle();

        final barcodeFieldWidget = tester.widget<TextField>(
          find.byKey(const Key('barcode_input_field')),
        );
        expect(barcodeFieldWidget.autofocus, isFalse);
        expect(barcodeFieldWidget.focusNode!.hasFocus, isFalse);

        // Harici Bluetooth / USB-OTG HID tarayıcı barkod kutusu odaksızken okuma yapar
        await simulateHidScan(tester, '8690504018241');
        expect(find.text('Somun Ekmek 200g'), findsOneWidget);
        // Android'de işlem sonrası barkod alanına zorla autofocus yapılmaz
        expect(barcodeFieldWidget.focusNode!.hasFocus, isFalse);

        // Android'de F1 / F2 / F9 / F10 masaüstü modalı tetiklemez
        await tester.sendKeyEvent(LogicalKeyboardKey.f1);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('help_shortcuts_dialog')), findsNothing);

        await tester.sendKeyEvent(LogicalKeyboardKey.f9);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('payment_dialog')), findsNothing);

        await tester.sendKeyEvent(LogicalKeyboardKey.f10);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('payment_dialog')), findsNothing);

        // Temizleme butonu alan dolunca >= 48dp boyutla görünür ve alanı temizler
        await tester.enterText(
          find.byKey(const Key('barcode_input_field')),
          '869000',
        );
        await tester.pumpAndSettle();
        final clearBtn = find.byKey(const Key('barcode_clear_button'));
        expect(clearBtn, findsOneWidget);
        expect(tester.getSize(clearBtn).height, greaterThanOrEqualTo(48));
        await tester.tap(clearBtn);
        await tester.pumpAndSettle();
        expect(barcodeFieldWidget.controller!.text, isEmpty);

        // Ürün Ara modalı Android'de [Esc] etiketi gizli ('Kapat') gelir, Esc ile kapanabilir
        await tester.tap(find.byKey(const Key('open_product_search_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('product_search_dialog')), findsOneWidget);
        expect(find.text('Kapat'), findsOneWidget);
        expect(find.text('Kapat [Esc]'), findsNothing);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('product_search_dialog')), findsNothing);
      },
    );
  });
}
