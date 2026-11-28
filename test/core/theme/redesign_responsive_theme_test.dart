import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/app/app.dart';
import 'package:market_pos/core/design_system/app_brand_logo.dart';
import 'package:market_pos/core/network/api_client.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/core/theme/theme_provider.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

void main() {
  group('Modern Emerald UI/UX Redesign — Responsive, Tema, Dashboard ve Stok Doğrulaması', () {
    late LocalDatabaseService localDb;
    late MmsApiClient apiClient;

    setUp(() async {
      localDb = LocalDatabaseService.forTesting(
        NativeDatabase.memory(),
        path: 'C:\\Users\\Mock\\AppData\\Local\\MarketMMS\\client_local.db',
      );

      final repo = localDb.repository;
      await repo.initializeDevice('POS-WIN-01');
      final cat = await repo.createCategory(name: 'Süt Ürünleri');
      final p1 = await repo.createProduct(
        name: 'Tam Yağlı Süt 1L',
        price: 3250,
        barcode: '8690101',
        categoryId: cat.id,
        initialStock: 3000, // 3 adet -> kritik stok
      );
      await repo.createOfflineSale(
        deviceId: 'POS-WIN-01',
        paymentMethod: 'CASH',
        items: [CartItemInput.units(p1.id, 1)],
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
        baseUrl: 'https://127.0.0.1:8443',
        deviceId: 'POS-WIN-01',
      );
    });

    tearDown(() async {
      await localDb.close();
    });

    Widget buildApp({ThemeMode initialTheme = ThemeMode.light}) {
      return ProviderScope(
        overrides: [
          localDatabaseServiceProvider.overrideWithValue(localDb),
          apiClientProvider.overrideWithValue(apiClient),
          themeModeProvider.overrideWith((_) => ThemeModeNotifier(initialTheme)),
        ],
        child: const MarketPosApp(),
      );
    }

    testWidgets('1. Windows Geniş Ekran (1440x900) — Tüm 6 ekran Light ve Dark temada taşmasız render edilir',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildApp(initialTheme: ThemeMode.light));
      await tester.pumpAndSettle();

      // Marka logosu görünür
      expect(find.byType(AppBrandLogo), findsAtLeastNWidgets(1));

      // Tüm 6 modüle geçiş yap ve gerçek verilerin taşmasız yüklendiğini doğrula
      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();
      expect(find.text('Mağaza Özeti'), findsOneWidget);
      expect(find.text('Tam Yağlı Süt 1L'), findsOneWidget);

      await tester.tap(find.text('Ürünler'));
      await tester.pumpAndSettle();
      expect(find.text('Ürün ve Stok Yönetimi'), findsOneWidget);

      await tester.tap(find.text('Stok'));
      await tester.pumpAndSettle();
      expect(find.text('Stok Yönetimi'), findsOneWidget);
      expect(find.text('Tam Yağlı Süt 1L'), findsOneWidget);

      await tester.tap(find.text('Raporlar'));
      await tester.pumpAndSettle();
      expect(find.text('Kasa ve Finansal Raporlar'), findsOneWidget);

      await tester.tap(find.text('Ayarlar ve Sistem').first);
      await tester.pumpAndSettle();
      expect(find.text('Ayarlar ve Sistem'), findsAtLeastNWidgets(1));

      final darkThemeChip = find.byKey(const Key('theme_mode_dark'));
      await tester.scrollUntilVisible(
        darkThemeChip,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Görünüm'), findsOneWidget);

      // Dark tema geçişi
      await tester.tap(darkThemeChip);
      await tester.pumpAndSettle();
      final ctxDark = tester.element(find.text('Görünüm'));
      expect(Theme.of(ctxDark).brightness, Brightness.dark);

      // System tema geçişi
      await tester.tap(find.byKey(const Key('theme_mode_system')));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(ctxDark);
      expect(container.read(themeModeProvider), ThemeMode.system);
    });

    testWidgets('2. Tablet (768x1024) — NavigationRail düzeninde tüm ekranlar sıfır taşma ile çalışır',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(768, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildApp(initialTheme: ThemeMode.dark));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsOneWidget);

      for (final tab in ['Dashboard', 'Ürünler', 'Stok', 'Raporlar', 'Ayarlar ve Sistem']) {
        await tester.tap(find.text(tab).first);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('3. Android Mobil (390x844) — Bottom NavigationBar ve mobil kartlar sıfır overflow',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildApp(initialTheme: ThemeMode.light));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);

      for (final tab in ['Özet', 'Ürünler', 'Stok', 'Raporlar']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
      }

      // Sistem & Tanı header ikonu üzerinden açılır
      await tester.tap(find.byKey(const Key('header_diagnostics_button')));
      await tester.pumpAndSettle();
      expect(find.text('Ayarlar ve Sistem'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('4. Ultra Dar Ekran (320x640) — Minimum hedef genişlikte sıfır RenderFlex overflow',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildApp(initialTheme: ThemeMode.dark));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Kasa (POS) 320px overflow');

      for (final tab in ['Özet', 'Ürünler', 'Stok', 'Raporlar']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$tab 320px overflow');
      }

      await tester.tap(find.byKey(const Key('header_diagnostics_button')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Sistem & Tanı 320px overflow');
    });
  });
}
