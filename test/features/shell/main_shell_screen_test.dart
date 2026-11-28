import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/app/app.dart';
import 'package:market_pos/core/network/api_client.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:market_pos/features/shell/presentation/widgets/cashier_header_bar.dart';
import 'package:market_pos/features/sync/domain/sync_coordinator_state.dart';
import 'package:market_pos/features/sync/sync_providers.dart';

void main() {
  group('MainShellScreen & MarketPosApp - Windows Arayüz Temeli Testleri', () {
    late LocalDatabaseService localDb;
    late MmsApiClient apiClient;

    setUp(() async {
      localDb = LocalDatabaseService.forTesting(
        NativeDatabase.memory(),
        path: 'C:\\Users\\Mock\\AppData\\Local\\MarketMMS\\client_local.db',
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

    Widget createTestApp() {
      return ProviderScope(
        overrides: [
          localDatabaseServiceProvider.overrideWithValue(localDb),
          apiClientProvider.overrideWithValue(apiClient),
        ],
        child: const MarketPosApp(),
      );
    }

    testWidgets('1. Temel Arayüz İskeleti: Başlık, Durum Rozeti ve Navigasyon Rayı render edilir',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Başlık ve terminal bilgisi doğrula
      expect(find.text('MARKET MANAGEMENT SYSTEM'), findsOneWidget);
      expect(find.textContaining('POS-WIN-01'), findsWidgets);

      // Durum rozeti doğrula (Header ve Kart içerisinde 2 adet bulunur)
      expect(find.text('ÇEVRİMİÇİ (HUB CANLI)'), findsAtLeastNWidgets(1));

      // Outbox senkronizasyon kuyruk rozeti doğrula (Header içerisinde)
      expect(find.text('SENKRONİZE'), findsOneWidget);

      // Navigasyon Rayı elemanları
      expect(find.text('Kasa (Satış)'), findsOneWidget);
      expect(find.text('Ürünler'), findsOneWidget);
      expect(find.text('Raporlar'), findsOneWidget);
      expect(find.text('Ayarlar ve Sistem'), findsOneWidget);

      // Varsayılan açılış ekranı: Kasa (Satış) POS
      expect(find.byKey(const Key('barcode_input_field')), findsOneWidget);

      // Onaylı alt kısayollar: yalnız F1, F2, F9, F10, Esc
      expect(find.text('F1'), findsOneWidget);
      expect(find.text('F2'), findsOneWidget);
      expect(find.text('F9'), findsOneWidget);
      expect(find.text('F10'), findsOneWidget);
      expect(find.text('Esc'), findsOneWidget);

      // Ayarlar ve Sistem sekmesine geçince sade Ayarlar ve Sistem ekranı render edilir
      await tester.tap(find.text('Ayarlar ve Sistem'));
      await tester.pumpAndSettle();

      expect(find.text('Ayarlar ve Sistem'), findsAtLeastNWidgets(1));
      expect(find.text('Bağlantı & Senkronizasyon Durumu'), findsOneWidget);
      expect(find.text('Gelişmiş ve Teknik Destek'), findsOneWidget);
    });

    testWidgets('2. Modül Geçişleri: Ürünler ve Raporlar MVP kapsamıyla uyumlu placeholder gösterir',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Açılışta Kasa (Satış) POS aktiftir
      expect(find.byKey(const Key('barcode_input_field')), findsOneWidget);

      // 'Ürünler' sekmesine tıkla -> MVP dışı 'stok sayımı' kalıntısı olmamalı
      await tester.tap(find.text('Ürünler'));
      await tester.pumpAndSettle();
      expect(find.text('Ürün ve Stok Yönetimi'), findsOneWidget);
      expect(find.textContaining('stok sayımı'), findsNothing);

      // 'Raporlar' sekmesine tıkla -> MVP dışı 'Z-Raporu' / 'KDV dökümü' olmamalı
      await tester.tap(find.text('Raporlar'));
      await tester.pumpAndSettle();
      expect(find.text('Kasa ve Finansal Raporlar'), findsOneWidget);
      expect(find.textContaining('Z-Raporu'), findsNothing);
      expect(find.textContaining('KDV dökümü'), findsNothing);

      // Tekrar 'Kasa (Satış)' sekmesine dön
      await tester.tap(find.text('Kasa (Satış)'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('barcode_input_field')), findsOneWidget);
    });

    testWidgets('3. Yenileme Butonu: Ayarlar ve Sistem sekmesinde sağlık kontrolü tetiklenir',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ayarlar ve Sistem'));
      await tester.pumpAndSettle();

      // Durumu Yenile butonuna tıkla
      final refreshButton = find.byKey(const Key('refresh_button'));
      expect(refreshButton, findsOneWidget);

      await tester.tap(refreshButton);
      await tester.pumpAndSettle();

      // Çevrimiçi rozeti korunmalı
      expect(find.text('ÇEVRİMİÇİ (HUB CANLI)'), findsAtLeastNWidgets(1));
    });

    testWidgets(
        '4. Startup Provider Yaşam Döngüsü: CashierHeaderBar render edildiğinde BackgroundSyncCoordinator erken başlatılır',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // ProviderScope içindeki container'a erişerek koordinatörün oluşturulmuş ve başlatılmış olduğunu doğrula
      final element = tester.element(find.byType(CashierHeaderBar));
      final container = ProviderScope.containerOf(element);
      final coordinatorState =
          container.read(backgroundSyncCoordinatorProvider);

      expect(coordinatorState, isNotNull);
      // Başlangıçta startup ve ardından Hub bağlantısı doğrulandığında connectivityRestored tetiklenir
      expect(
        coordinatorState.lastTriggerReason,
        anyOf(
          SyncTriggerReason.startup,
          SyncTriggerReason.connectivityRestored,
        ),
      );
    });
  });
}
