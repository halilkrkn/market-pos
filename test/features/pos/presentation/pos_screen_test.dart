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
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:market_pos/features/pos/presentation/widgets/payment_dialog.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  group('Presentation - PosScreen & Ödeme / Klavye / FFI Entegrasyonu', () {
    late Directory tempDir;
    late LocalDatabaseService localDb;
    late MmsApiClient apiClient;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('mms_pos_widget_test_');
      final dbFile = File(p.join(tempDir.path, 'client_local.db'));
      localDb = LocalDatabaseService.forTesting(
        NativeDatabase(
          dbFile,
          setup: (rawDb) {
            rawDb.execute('PRAGMA journal_mode = WAL;');
            rawDb.execute('PRAGMA synchronous = FULL;');
            rawDb.execute('PRAGMA busy_timeout = 5000;');
            rawDb.execute('PRAGMA foreign_keys = ON;');
          },
        ),
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
            stock: Value(1000), // 1 adet -> 2 adet satılınca -1 eksiye düşer
            stockUnit: Value('adet'),
            pricingUnit: Value('adet'),
            conversionFactorNumerator: Value(1),
            conversionFactorDenominator: Value(1),
            isActive: Value(true),
          ),
          const LocalProductsCompanion(
            id: Value('prod_elma'),
            barcode: Value('8690000000101'),
            name: Value('Elma Starking Kg'),
            price: Value(12550),
            priceVersionId: Value('pv_1'),
            stock: Value(10000),
            stockUnit: Value('kg'),
            pricingUnit: Value('kg'),
            conversionFactorNumerator: Value(1),
            conversionFactorDenominator: Value(1),
            isActive: Value(true),
          ),
          const LocalProductsCompanion(
            id: Value('prod_pasif'),
            barcode: Value('8690009990001'),
            name: Value('Pasif Ürün'),
            price: Value(5000),
            priceVersionId: Value('pv_1'),
            stock: Value(5000),
            stockUnit: Value('adet'),
            pricingUnit: Value('adet'),
            conversionFactorNumerator: Value(1),
            conversionFactorDenominator: Value(1),
            isActive: Value(false),
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
            id: Value('bc_elma'),
            productId: Value('prod_elma'),
            barcode: Value('8690000000101'),
            isPrimary: Value(true),
            isActive: Value(true),
          ),
          LocalProductBarcodesCompanion(
            id: Value('bc_pasif'),
            productId: Value('prod_pasif'),
            barcode: Value('8690009990001'),
            isPrimary: Value(true),
            isActive: Value(true),
          ),
        ],
      );

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'status': 'HEALTHY',
            'service': 'MARKET_MMS_HUB',
            'sqlite_version': '3.45.1',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      apiClient = MmsApiClient(
        client: mockClient,
        baseUrl: 'http://127.0.0.1:8080',
        deviceId: 'POS-WIN-01',
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

    Widget buildTestApp() {
      return ProviderScope(
        overrides: [
          localDatabaseServiceProvider.overrideWithValue(localDb),
          apiClientProvider.overrideWithValue(apiClient),
        ],
        child: const MarketPosApp(),
      );
    }

    Future<void> scanBarcodeInUi(WidgetTester tester, String barcode) async {
      final field = find.byKey(const Key('barcode_input_field'));
      expect(field, findsOneWidget);
      await tester.enterText(field, barcode);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    testWidgets('1. Varsayılan POS açılışı, onaylı kapsam sınırları, OD-04 numpad ve >=48dp hedefler', (tester) async {
      tester.view.physicalSize = const Size(1280, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Açılışta Kasa (Satış) ekranı gelir
      expect(find.byKey(const Key('barcode_input_field')), findsOneWidget);

      // Kapsam dışı öğeler YOKTUR (OD-02 Parked Carts, F3/F4/F8, Hızlı Ürün Tuşları)
      expect(find.textContaining('Askıya Al'), findsNothing);
      expect(find.textContaining('F3'), findsNothing);
      expect(find.textContaining('F4'), findsNothing);
      expect(find.textContaining('F8'), findsNothing);
      expect(find.textContaining('Hızlı Ürün'), findsNothing);

      // OD-04: Sanal numpad varsayılan olarak kapalıdır, toggle ile açılır
      expect(find.byKey(const Key('virtual_numpad_panel')), findsNothing);
      final numpadToggle = find.byKey(const Key('virtual_numpad_toggle'));
      expect(numpadToggle, findsOneWidget);
      await tester.tap(numpadToggle);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('virtual_numpad_panel')), findsOneWidget);

      // Numpad tuşu ve ödeme butonları >= 48x48 dp dokunmatik hedef
      final cashBtnSize = tester.getSize(find.byKey(const Key('cash_pay_button')));
      final cardBtnSize = tester.getSize(find.byKey(const Key('card_pay_button')));
      final numBtnSize = tester.getSize(find.byKey(const Key('numpad_btn_7')));
      expect(cashBtnSize.height, greaterThanOrEqualTo(48));
      expect(cardBtnSize.height, greaterThanOrEqualTo(48));
      expect(numBtnSize.width, greaterThanOrEqualTo(48));
      expect(numBtnSize.height, greaterThanOrEqualTo(48));
    });

    testWidgets('2. Barkod ekleme, aynı ürün birleşimi, eksi stok uyarısı ve bilinmeyen/pasif reddi', (tester) async {
      tester.view.physicalSize = const Size(1280, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Aynı barkod 2 kez okutulur -> tek satırda birleşir, stok 1->-1 eksi uyarısı çıkar
      await scanBarcodeInUi(tester, '8690504018241');
      await scanBarcodeInUi(tester, '8690504018241');

      expect(find.text('Somun Ekmek 200g'), findsOneWidget);
      expect(find.text('25.00 TL'), findsWidgets);
      expect(find.textContaining('Eksi Stok'), findsOneWidget);

      // Satır içi +, -, Sil buton boyutları >= 48x48 dp ve gerçek etkileşim
      final plusBtn = find.byKey(const Key('qty_plus_prod_ekmek'));
      final minusBtn = find.byKey(const Key('qty_minus_prod_ekmek'));
      final delBtn = find.byKey(const Key('remove_item_prod_ekmek'));
      final plusSize = tester.getSize(plusBtn);
      final minusSize = tester.getSize(minusBtn);
      final delSize = tester.getSize(delBtn);
      expect(plusSize.width, greaterThanOrEqualTo(48));
      expect(plusSize.height, greaterThanOrEqualTo(48));
      expect(minusSize.width, greaterThanOrEqualTo(48));
      expect(minusSize.height, greaterThanOrEqualTo(48));
      expect(delSize.width, greaterThanOrEqualTo(48));
      expect(delSize.height, greaterThanOrEqualTo(48));

      await tester.tap(plusBtn);
      await tester.pumpAndSettle();
      expect(find.text('37.50 TL'), findsWidgets);

      await tester.tap(minusBtn);
      await tester.pumpAndSettle();
      expect(find.text('25.00 TL'), findsWidgets);

      await tester.tap(delBtn);
      await tester.pumpAndSettle();
      expect(find.text('Somun Ekmek 200g'), findsNothing);

      // Bilinmeyen barkod (OD-03) -> sepete eklemez, ürün oluşturmaz, net uyarı gösterir
      await scanBarcodeInUi(tester, '8699999999999');
      expect(find.textContaining('yerel katalogda bulunamadı'), findsOneWidget);
      expect(await localDb.getLocalProductsCount(), equals(3));

      // Pasif ürün (R-01) -> sepete eklemez
      await scanBarcodeInUi(tester, '8690009990001');
      expect(find.textContaining('Pasif ürün'), findsOneWidget);
    });

    testWidgets('3. F2 kesirli miktar (0.345 kg Half-Up), Ürün Arama, Sepet Temizleme onayı ve F1 Yardım', (tester) async {
      tester.view.physicalSize = const Size(1280, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      // Yerel Ürün Arama butonundan Elma ekle
      await tester.tap(find.byKey(const Key('open_product_search_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('product_search_dialog')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('product_search_input')), 'Elma');
      await tester.pumpAndSettle();
      expect(find.text('Elma Starking Kg'), findsOneWidget);
      expect(find.text('Pasif Ürün'), findsNothing);
      await tester.tap(find.byKey(const Key('search_add_prod_elma')));
      await tester.pumpAndSettle();

      // F2 ile miktar diyaloğunu aç ve 0.345 gir -> Half-Up: 43.30 TL
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quantity_edit_dialog')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('quantity_edit_input')), '0.345');
      await tester.tap(find.byKey(const Key('quantity_edit_confirm')));
      await tester.pumpAndSettle();

      expect(find.text('43.30 TL'), findsWidgets);

      // F1 Yardım aç ve Esc ile kapat
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('help_shortcuts_dialog')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('help_shortcuts_dialog')), findsNothing);

      // Sepeti Temizle onayı
      await tester.tap(find.byKey(const Key('clear_cart_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('clear_cart_confirm_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('clear_cart_confirm_yes')));
      await tester.pumpAndSettle();
      expect(find.text('0.00 TL'), findsWidgets);
    });

    testWidgets('4. F10 Nakit ödeme, eksik tutar kilidi, R-06 Enter koruması ve atomik DB kaydı', (tester) async {
      tester.view.physicalSize = const Size(1280, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await scanBarcodeInUi(tester, '8690504018241'); // 12.50 TL

      // F10 ile Nakit ödeme modalı açılır
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('payment_dialog')), findsOneWidget);

      // R-06: Modal açıkken barkod veya eksik tutar Enter'ı satışı tamamlamaz
      await tester.enterText(find.byKey(const Key('cash_received_input')), '10.00');
      await tester.pumpAndSettle();
      final confirmBtnLocked =
          tester.widget<ElevatedButton>(find.byKey(const Key('payment_confirm_button')));
      expect(confirmBtnLocked.onPressed, isNull);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(await localDb.getLocalSalesCount(), equals(0));

      // Esc ile modal kapanır, satış oluşmaz
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('payment_dialog')), findsNothing);
      expect(await localDb.getLocalSalesCount(), equals(0));

      // Tekrar F10 aç ve geçerli 50.00 TL ile satışı tamamla -> Para üstü 37.50 TL
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('cash_received_input')), '50.00');
      await tester.pumpAndSettle();
      expect(find.text('37.50 TL'), findsOneWidget);

      // R-06: Yeterli nakit varken bile Enter sızıntısı onay butonu basılmadan satışı tamamlamaz
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('payment_dialog')), findsOneWidget);
      expect(await localDb.getLocalSalesCount(), equals(0));

      await tester.tap(find.byKey(const Key('payment_confirm_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('payment_dialog')), findsNothing);
      expect(find.text('Bekleyen Outbox: 1'), findsOneWidget);
      expect(await localDb.getLocalSalesCount(), equals(1));
      expect(await localDb.getPendingOutboxCount(), equals(1));

      final sales = await localDb.database.select(localDb.database.localSales).get();
      expect(sales.single.paymentMethod, equals('CASH'));
      expect(sales.single.totalAmount, equals(1250));
    });

    testWidgets('5. F9 Kart ödeme, harici POS manuel giriş teyit zorunluluğu ve CARD outbox kaydı', (tester) async {
      tester.view.physicalSize = const Size(1280, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await scanBarcodeInUi(tester, '8690504018241'); // 12.50 TL

      // F9 ile Kart modalı açılır
      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('payment_dialog')), findsOneWidget);

      // Manuel POS teyidi işaretlenmeden onay butonu kilitlidir
      final cardConfirmBefore =
          tester.widget<ElevatedButton>(find.byKey(const Key('payment_confirm_button')));
      expect(cardConfirmBefore.onPressed, isNull);

      await tester.tap(find.byKey(const Key('card_manual_confirm_checkbox')));
      await tester.pumpAndSettle();

      final cardConfirmAfter =
          tester.widget<ElevatedButton>(find.byKey(const Key('payment_confirm_button')));
      expect(cardConfirmAfter.onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('payment_confirm_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('payment_dialog')), findsNothing);
      expect(await localDb.getLocalSalesCount(), equals(1));
      expect(await localDb.getPendingOutboxCount(), equals(1));
      final outbox = await localDb.repository.getUnsyncedOutboxOperations('POS-WIN-01');
      final payload = jsonDecode(outbox.single.payload) as Map<String, dynamic>;
      expect(payload['payment_method'], equals('CARD'));
      expect(
        outbox.single.payloadHash,
        equals(ClientStorageRepository.computeSaleRequestHash(payload)),
      );
    });

    testWidgets('6. Kart teyidi sonrası ödeme yöntemi değiştirilirse teyit sıfırlanır (Güvenlik #9)', (tester) async {
      tester.view.physicalSize = const Size(1280, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await scanBarcodeInUi(tester, '8690504018241');
      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('card_manual_confirm_checkbox')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ElevatedButton>(find.byKey(const Key('payment_confirm_button'))).onPressed,
        isNotNull,
      );

      // F10 ile Nakit'e geç, ardından F9 ile tekrar Kart'a dön -> Kart teyidi sıfırlanmış olmalı
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pumpAndSettle();

      final checkbox = tester.widget<CheckboxListTile>(
        find.byKey(const Key('card_manual_confirm_checkbox')),
      );
      expect(checkbox.value, isFalse);
      expect(
        tester.widget<ElevatedButton>(find.byKey(const Key('payment_confirm_button'))).onPressed,
        isNull,
      );
    });

    testWidgets('7. PaymentDialog callback exception fırlattığında kilitlenmez ve hata gösterir (Güvenlik #10)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PaymentDialog(
              totalCents: 1250,
              initialMethod: PaymentMethod.card,
              onConfirmSale: ({
                required paymentMethod,
                cashReceivedCents,
                required externalPosConfirmed,
              }) async {
                throw Exception('Beklenmeyen ödeme hatası');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('card_manual_confirm_checkbox')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('payment_confirm_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('payment_dialog')), findsOneWidget);
      expect(find.textContaining('hata'), findsWidgets);
      expect(
        tester.widget<ElevatedButton>(find.byKey(const Key('payment_confirm_button'))).onPressed,
        isNotNull,
      );
      expect(
        tester.widget<OutlinedButton>(find.byKey(const Key('payment_cancel_button'))).onPressed,
        isNotNull,
      );
    });

    testWidgets('8. Dar ekran POS toolbar ve sepet satırı sıfır overflow ile render edilir (#11)', (tester) async {
      tester.view.physicalSize = const Size(640, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await scanBarcodeInUi(tester, '8690504018241');
      expect(find.text('Somun Ekmek 200g'), findsOneWidget);
      expect(find.byKey(const Key('cash_pay_button')), findsOneWidget);
      expect(find.byKey(const Key('card_pay_button')), findsOneWidget);
    });

    testWidgets('9. Modal açıkken arka plan kısayolları ve sepet fiyatı değişikliği koruması çalışır', (tester) async {
      tester.view.physicalSize = const Size(1280, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();

      await scanBarcodeInUi(tester, '8690504018241'); // 12.50 TL

      // Ürün Arama modalı açıkken F1 veya F9 basıldığında arka plan modal açmaz
      await tester.tap(find.byKey(const Key('open_product_search_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('product_search_dialog')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('help_shortcuts_dialog')), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('payment_dialog')), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('product_search_dialog')), findsNothing);

      // Sepette ürün varken DB'de fiyat güncellenirse F10 ödeme modalı sessizce tamamlayamaz
      await localDb.repository.upsertProducts([
        const LocalProductsCompanion(
          id: Value('prod_ekmek'),
          barcode: Value('8690504018241'),
          name: Value('Somun Ekmek 200g'),
          price: Value(1750),
          priceVersionId: Value('pv_2'),
          stock: Value(1000),
          stockUnit: Value('adet'),
          pricingUnit: Value('adet'),
          conversionFactorNumerator: Value(1),
          conversionFactorDenominator: Value(1),
          isActive: Value(true),
        ),
      ]);

      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('cash_received_input')), '20.00');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('payment_confirm_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('payment_dialog')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('payment_dialog')),
          matching: find.textContaining('değişti'),
        ),
        findsOneWidget,
      );
      expect(await localDb.getLocalSalesCount(), equals(0));
    });
  });
}

