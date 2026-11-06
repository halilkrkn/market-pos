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
        baseUrl: 'http://127.0.0.1:8080',
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

      // Navigasyon Rayı elemanları
      expect(find.text('Kasa (Satış)'), findsOneWidget);
      expect(find.text('Ürünler'), findsOneWidget);
      expect(find.text('Raporlar'), findsOneWidget);
      expect(find.text('Sistem & Tanı'), findsOneWidget);

      // Varsayılan açık olan Tanılama Kartı
      expect(find.text('Sistem Durumu ve Altyapı Tanılama'), findsOneWidget);
      expect(find.text('Merkezi Shelf HTTPS/HTTP Sunucusu (Master Hub)'), findsOneWidget);
      expect(find.text('İstemci Yerel Depolaması (client_local.db)'), findsOneWidget);
    });

    testWidgets('2. Modül Geçişleri: Kasa ve Ürün sekmelerine tıklandığında placeholder gösterilir',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // 'Kasa (Satış)' sekmesine tıkla
      await tester.tap(find.text('Kasa (Satış)'));
      await tester.pumpAndSettle();

      // Faz 1.2 placeholder'ı görüntülenmeli
      expect(find.text('Kasa / Satış Modülü (POS)'), findsOneWidget);
      expect(find.text('Faz 1.2 — Satış Ekranı & Sepet Yönetimi'), findsOneWidget);

      // Tekrar 'Sistem & Tanı' sekmesine dön
      await tester.tap(find.text('Sistem & Tanı'));
      await tester.pumpAndSettle();

      expect(find.text('Sistem Durumu ve Altyapı Tanılama'), findsOneWidget);
    });

    testWidgets('3. Yenileme Butonu: Durumu Yenile butonuna tıklandığında sağlık kontrolü tetiklenir',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Durumu Yenile butonuna tıkla
      final refreshButton = find.byKey(const Key('refresh_button'));
      expect(refreshButton, findsOneWidget);

      await tester.tap(refreshButton);
      await tester.pumpAndSettle();

      // Çevrimiçi rozeti korunmalı
      expect(find.text('ÇEVRİMİÇİ (HUB CANLI)'), findsAtLeastNWidgets(1));
    });
  });
}
