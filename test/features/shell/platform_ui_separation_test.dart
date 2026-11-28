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
import 'package:market_pos/core/theme/design_tokens.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:market_pos/features/pos/presentation/widgets/desktop_pos_view.dart';
import 'package:market_pos/features/pos/presentation/widgets/mobile_pos_view.dart';
import 'package:market_pos/features/shell/domain/app_destination.dart';
import 'package:market_pos/features/shell/presentation/screens/main_shell_screen.dart';
import 'package:market_pos/features/shell/presentation/widgets/desktop_shell_layout.dart';
import 'package:market_pos/features/shell/presentation/widgets/mobile_shell_layout.dart';
import 'package:market_pos/features/shell/shell_providers.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

void main() {
  group('Faz 2: MmsUiProfile Birim Testleri', () {
    test('detectCurrentPlatform Android/iOS ve Masaüstü profillerini doğru ayırır', () {
      final android = MmsUiProfile.detectCurrentPlatform(
        isAndroidOverride: true,
        isIosOverride: false,
      );
      final windows = MmsUiProfile.detectCurrentPlatform(
        isAndroidOverride: false,
        isIosOverride: false,
      );

      expect(android.isMobile, isTrue);
      expect(android.isDesktop, isFalse);
      expect(android.showKeyboardShortcuts, isFalse);
      expect(android.enableHardwareBarcodeAutofocus, isFalse);
      expect(android.minTouchTarget, 48.0);
      expect(android.useMobileLayout(MmsWindowClass.compact), isTrue);
      expect(android.useMobileLayout(MmsWindowClass.medium), isTrue);
      expect(android.useMobileLayout(MmsWindowClass.expanded), isTrue);
      expect(android.showDesktopShortcutFooter(MmsWindowClass.expanded), isFalse);

      expect(windows.isDesktop, isTrue);
      expect(windows.isMobile, isFalse);
      expect(windows.showKeyboardShortcuts, isTrue);
      expect(windows.enableHardwareBarcodeAutofocus, isTrue);
      expect(windows.useMobileLayout(MmsWindowClass.expanded), isFalse);
      expect(windows.useMobileLayout(MmsWindowClass.medium), isFalse);
      expect(windows.useMobileLayout(MmsWindowClass.compact), isTrue);
      expect(windows.showDesktopSidebar(MmsWindowClass.expanded), isTrue);
      expect(windows.showDesktopShortcutFooter(MmsWindowClass.medium), isTrue);
    });
  });

  group('Faz 2: Android ve Windows UI Ayrıştırması Widget & Regresyon Testleri', () {
    late LocalDatabaseService localDb;
    late MmsApiClient apiClient;

    setUp(() async {
      localDb = LocalDatabaseService.forTesting(
        NativeDatabase.memory(),
        path: 'C:\\Users\\Mock\\AppData\\Local\\MarketMMS\\faz2_client.db',
      );

      final repo = localDb.repository;
      await repo.initializeDevice('POS-AND-01');
      final cat = await repo.createCategory(name: 'İçecekler');
      await repo.upsertProducts(
        [
          LocalProductsCompanion(
            id: const Value('prod_sut'),
            barcode: const Value('8690101'),
            name: const Value('Tam Yağlı Süt 1L'),
            price: const Value(3250),
            priceVersionId: const Value('pv_sut_1'),
            stock: const Value(12000),
            stockUnit: const Value('adet'),
            pricingUnit: const Value('adet'),
            conversionFactorNumerator: const Value(1),
            conversionFactorDenominator: const Value(1),
            categoryId: Value(cat.id),
            isActive: const Value(true),
            updatedAt: Value(DateTime(2026, 11, 20, 10, 0)),
          ),
        ],
        barcodes: const [
          LocalProductBarcodesCompanion(
            id: Value('bc_sut'),
            productId: Value('prod_sut'),
            barcode: Value('8690101'),
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
            'sqlite_version': '3.46.0',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      apiClient = MmsApiClient(
        client: mockClient,
        baseUrl: 'http://192.168.1.50:8080',
        deviceId: 'POS-AND-01',
      );
    });

    tearDown(() async {
      await localDb.close();
    });

    Widget buildApp({required MmsUiProfile profile}) {
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
      '1. Android Telefon (390x844): MobileShell, >=48dp hedefler, sabit ödeme barı ve tek-el satış akışı',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(buildApp(profile: const MmsUiProfile.mobile()));
        await tester.pumpAndSettle();

        // Mobil kabuk & MobilePosView aktif, masaüstü öğeleri yok
        expect(find.byType(MobileShellLayout), findsOneWidget);
        expect(find.byType(DesktopShellLayout), findsNothing);
        expect(find.byKey(const Key('mobile_phone_shell')), findsOneWidget);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.byKey(const Key('desktop_shortcut_footer')), findsNothing);
        expect(find.byType(MobilePosView), findsOneWidget);
        expect(find.byType(DesktopPosView), findsNothing);
        expect(find.textContaining('[F10]'), findsNothing);
        expect(find.textContaining('[F9]'), findsNothing);
        expect(find.textContaining('[F1]'), findsNothing);

        // Sabit thumb-zone ödeme barı kaydırmadan ekranda görünür
        final stickyBarFinder = find.byKey(const Key('mobile_sticky_checkout_bar'));
        expect(stickyBarFinder, findsOneWidget);
        final stickyRect = tester.getRect(stickyBarFinder);
        expect(stickyRect.bottom, lessThanOrEqualTo(844.0));

        // Dokunmatik hedefler >= 48dp
        expect(
          tester.getSize(find.byKey(const Key('header_theme_toggle'))).width,
          greaterThanOrEqualTo(48),
        );
        expect(
          tester.getSize(find.byKey(const Key('header_theme_toggle'))).height,
          greaterThanOrEqualTo(48),
        );
        expect(
          tester.getSize(find.byKey(const Key('header_diagnostics_button'))).width,
          greaterThanOrEqualTo(48),
        );
        expect(
          tester.getSize(find.byKey(const Key('header_diagnostics_button'))).height,
          greaterThanOrEqualTo(48),
        );
        expect(
          tester.getSize(find.byKey(const Key('barcode_add_button'))).height,
          greaterThanOrEqualTo(48),
        );
        expect(
          tester.getSize(find.byKey(const Key('open_product_search_button'))).height,
          greaterThanOrEqualTo(48),
        );
        expect(
          tester.getSize(find.byKey(const Key('virtual_numpad_toggle'))).height,
          greaterThanOrEqualTo(48),
        );
        expect(
          tester.getSize(find.byKey(const Key('cash_pay_button'))).height,
          greaterThanOrEqualTo(56),
        );
        expect(
          tester.getSize(find.byKey(const Key('card_pay_button'))).height,
          greaterThanOrEqualTo(56),
        );

        // Barkodla ürün ekle ve tek-el mobil ödeme akışını doğrula
        await tester.enterText(
          find.byKey(const Key('barcode_input_field')),
          '8690101',
        );
        await tester.tap(find.byKey(const Key('barcode_add_button')));
        await tester.pumpAndSettle();

        expect(find.text('Tam Yağlı Süt 1L'), findsOneWidget);
        expect(find.text('32.50 TL'), findsWidgets);

        await tester.tap(find.byKey(const Key('cash_pay_button')));
        await tester.pumpAndSettle();

        final dialogFinder = find.byKey(const Key('payment_dialog'));
        expect(dialogFinder, findsOneWidget);
        expect(
          find.descendant(of: dialogFinder, matching: find.text('NAKİT')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: dialogFinder, matching: find.text('KART')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: dialogFinder, matching: find.text('İptal')),
          findsOneWidget,
        );
        expect(find.textContaining('[F10]'), findsNothing);
        expect(find.textContaining('[F9]'), findsNothing);
        expect(find.textContaining('[Esc]'), findsNothing);

        await tester.enterText(
          find.byKey(const Key('cash_received_input')),
          '50.00',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('payment_confirm_button')));
        await tester.pumpAndSettle();

        expect(await localDb.getLocalSalesCount(), 1);

        // Raporlar sekmesine geç -> satış yansımalı ve Fiş Detay butonu >= 48dp olmalı
        final container = ProviderScope.containerOf(
          tester.element(find.byType(MainShellScreen)),
        );
        expect(container.read(activeDestinationProvider), AppDestination.pos);

        await tester.tap(find.text('Raporlar'));
        await tester.pumpAndSettle();
        expect(container.read(activeDestinationProvider), AppDestination.sales);
        expect(find.text('32.50 TL'), findsWidgets);
        final receiptBtn = find.widgetWithText(OutlinedButton, 'Fiş Detay');
        expect(receiptBtn, findsOneWidget);
        expect(tester.getSize(receiptBtn).height, greaterThanOrEqualTo(48));

        // Kalan tüm modülleri gez
        for (final tab in ['Özet', 'Ürünler', 'Stok', 'Kasa']) {
          await tester.tap(find.text(tab));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$tab overflow');
        }
        await tester.tap(find.byKey(const Key('header_diagnostics_button')));
        await tester.pumpAndSettle();
        expect(
          container.read(activeDestinationProvider),
          AppDestination.diagnostics,
        );
        expect(
          tester.widget<NavigationBar>(find.byType(NavigationBar)).indicatorColor,
          Colors.transparent,
        );
        expect(find.text('Ayarlar ve Sistem'), findsOneWidget);

        await tester.tap(find.text('Kasa'));
        await tester.pumpAndSettle();
        expect(container.read(activeDestinationProvider), AppDestination.pos);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '2. Android Küçük & Ultra Dar Telefon (360x640 ve 320x640): Numpad açıkken bile sıfır overflow',
      (WidgetTester tester) async {
        for (final size in [const Size(360, 640), const Size(320, 640)]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(buildApp(profile: const MmsUiProfile.mobile()));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'POS başlangıç $size overflow',
          );

          // Numpad açıkken de taşma olmamalı
          await tester.tap(find.byKey(const Key('virtual_numpad_toggle')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('virtual_numpad_panel')), findsOneWidget);
          expect(
            tester.takeException(),
            isNull,
            reason: 'POS numpad açık $size overflow',
          );
          await tester.tap(find.byKey(const Key('virtual_numpad_toggle')));
          await tester.pumpAndSettle();

          for (final tab in ['Özet', 'Ürünler', 'Stok', 'Raporlar']) {
            await tester.tap(find.text(tab));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$tab $size overflow');
          }
          await tester.tap(find.byKey(const Key('header_diagnostics_button')));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'Sistem & Tanı $size overflow',
          );

          await tester.tap(find.text('Kasa'));
          await tester.pumpAndSettle();
        }
        addTearDown(tester.view.resetPhysicalSize);
      },
    );

    testWidgets(
      '3. Android Tablet (800x1280 ve 1024x768): NavigationRail, masaüstü kısayol footer yok ve sıfır overflow',
      (WidgetTester tester) async {
        for (final size in [const Size(800, 1280), const Size(1024, 768)]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(buildApp(profile: const MmsUiProfile.mobile()));
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('mobile_tablet_shell')), findsOneWidget);
          expect(find.byType(DesktopShellLayout), findsNothing);
          expect(find.byType(NavigationRail), findsOneWidget);
          expect(find.byKey(const Key('desktop_shortcut_footer')), findsNothing);
          expect(find.byType(MobilePosView), findsOneWidget);
          expect(find.textContaining('[F10]'), findsNothing);
          expect(find.textContaining('[F9'), findsNothing);
          expect(find.byKey(const Key('help_button')), findsNothing);
          expect(tester.takeException(), isNull, reason: 'Tablet POS $size overflow');

          for (final tab in [
            'Dashboard',
            'Ürünler',
            'Stok',
            'Raporlar',
            'Ayarlar ve Sistem',
            'Kasa (Satış)',
          ]) {
            await tester.tap(find.text(tab).first);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: 'Tablet $tab $size');
          }
        }
        addTearDown(tester.view.resetPhysicalSize);
      },
    );

    testWidgets(
      '4. Windows Masaüstü Regresyon (1280x720): Emerald Sidebar, Kısayol Çubuğu ve DesktopPosView korunur',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 720);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(buildApp(profile: const MmsUiProfile.desktop()));
        await tester.pumpAndSettle();

        expect(find.byType(DesktopShellLayout), findsOneWidget);
        expect(find.byType(MobileShellLayout), findsNothing);
        expect(find.byKey(const Key('desktop_shortcut_footer')), findsOneWidget);
        expect(find.byType(DesktopPosView), findsOneWidget);
        expect(find.byKey(const Key('help_button')), findsOneWidget);
        expect(find.text('[F10]'), findsOneWidget);
        expect(find.text('[F9 • Elle Giriş]'), findsOneWidget);

        final desktopContainer = ProviderScope.containerOf(
          tester.element(find.byType(MainShellScreen)),
        );
        expect(
          desktopContainer.read(activeDestinationProvider),
          AppDestination.pos,
        );
        await tester.tap(find.text('Dashboard'));
        await tester.pumpAndSettle();
        expect(
          desktopContainer.read(activeDestinationProvider),
          AppDestination.dashboard,
        );
        await tester.tap(find.text('Kasa (Satış)'));
        await tester.pumpAndSettle();
        expect(
          desktopContainer.read(activeDestinationProvider),
          AppDestination.pos,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
