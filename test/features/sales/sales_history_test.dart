import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/core/network/api_client.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:market_pos/features/sales/application/sales_history_notifier.dart';
import 'package:market_pos/features/sales/data/sales_repository.dart';
import 'package:market_pos/features/sales/domain/models/sale_history_filter.dart';
import 'package:market_pos/features/sales/presentation/screens/sales_history_screen.dart';
import 'package:market_pos/features/sales/sales_providers.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

void main() {
  group('FAZ 1.3.2: Satış Geçmişi ve Fiş Detayları Testleri', () {
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

      // Test ürünleri oluştur
      final prod1 = await repo.createProduct(
        name: 'Süt 1L',
        price: 2500, // 25.00 TL
        barcode: '869001',
        initialStock: 20000,
      );

      final prod2 = await repo.createProduct(
        name: 'Ekmek 200g',
        price: 1000, // 10.00 TL
        barcode: '869002',
        initialStock: 50000,
      );

      // Satış 1: CASH 35.00 TL (1 süt + 1 ekmek)
      await repo.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [
          CartItemInput.units(prod1.id, 1),
          CartItemInput.units(prod2.id, 1),
        ],
      );

      // Satış 2: CARD 50.00 TL (2 süt)
      await repo.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CARD',
        items: [
          CartItemInput.units(prod1.id, 2),
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

    testWidgets('Satış geçmişi ekranında KPI özetleri ve satış listesi render edilir',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Başlık
      expect(find.text('Kasa ve Finansal Raporlar'), findsOneWidget);

      // KPI Kartları
      expect(find.text('Toplam Satış Adedi'), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // 2 satış

      // Brüt Ciro: 35.00 TL + 50.00 TL = 85.00 TL
      expect(find.text('85.00 TL'), findsWidgets);

      // Satış Listesi elemanları
      expect(find.text('Fiş Detay'), findsNWidgets(2));
      expect(find.text('35.00 TL'), findsOneWidget);
      expect(find.text('50.00 TL'), findsOneWidget);

      // Fiş Detay butonuna tıkla
      await tester.tap(find.text('Fiş Detay').first);
      await tester.pumpAndSettle();

      // Fiş modalı açılmalı ve kalemler görünmeli
      expect(find.textContaining('Fiş Detayı:'), findsOneWidget);
      expect(find.text('Satış Kalemleri'), findsOneWidget);
      expect(find.text('Kapat'), findsOneWidget);

      // Kapat butonuna tıkla
      await tester.tap(find.text('Kapat'));
      await tester.pumpAndSettle();
    });

    testWidgets('Ödeme yöntemi ve durum filtreleri listeyi doğru günceller',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Başlangıçta 2 satış var
      expect(find.text('Fiş Detay'), findsNWidgets(2));

      // Nakit filtrele
      await tester.tap(find.text('Ödeme: Tümü'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nakit').last);
      await tester.pumpAndSettle();

      expect(find.text('Fiş Detay'), findsOneWidget);
      expect(find.text('35.00 TL'), findsNWidgets(3));
      expect(find.text('50.00 TL'), findsNothing);
    });

    testWidgets(
        'Satış Geçmişi ekranında TAMAMLANDI, İPTAL EDİLDİ, İADE EDİLDİ ve KISMİ İADE rozetleri doğru render edilir',
        (WidgetTester tester) async {
      final repo = localDb.repository;
      final products = await repo.getProducts();
      final pId = products.first.id;

      // 1. İptal edilen satış oluştur
      final cancelSaleRes = await repo.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units(pId, 1)],
      );
      await repo.cancelSale(
        saleId: cancelSaleRes.saleId,
        reason: 'Müşteri vazgeçti',
        deviceId: testDeviceId,
      );

      // 2. Tam iade edilen satış oluştur
      final fullRefundSaleRes = await repo.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units(pId, 1)],
      );
      final fullDetail = await repo.getSaleDetail(fullRefundSaleRes.saleId);
      await repo.refundSale(
        saleId: fullRefundSaleRes.saleId,
        items: [
          RefundItemInput(
            saleItemId: fullDetail!.items.first.id,
            quantity: fullDetail.items.first.quantity,
          ),
        ],
        reason: 'Hatalı ürün',
        deviceId: testDeviceId,
      );

      // 3. Kısmi iade edilen satış oluştur (2 adet satıp 1 adedini iade et)
      final partialRefundSaleRes = await repo.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CARD',
        items: [CartItemInput.units(pId, 2)],
      );
      final partialDetail = await repo.getSaleDetail(partialRefundSaleRes.saleId);
      await repo.refundSale(
        saleId: partialRefundSaleRes.saleId,
        items: [
          RefundItemInput(
            saleItemId: partialDetail!.items.first.id,
            quantity: 1000, // 2 adetten 1 adedi iade
          ),
        ],
        reason: '1 adedi fazla alındı',
        deviceId: testDeviceId,
      );

      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Kanonik etiketlerin ekranda yer aldığını doğrula
      expect(find.text('TAMAMLANDI'), findsWidgets);
      expect(find.text('İPTAL EDİLDİ'), findsOneWidget);
      expect(find.text('İADE EDİLDİ'), findsOneWidget);
      expect(find.text('KISMİ İADE'), findsOneWidget);
    });

    testWidgets(
        'İade edilmiş satışlar fiş detayına girilmeden liste üzerinde doğrudan İADE EDİLDİ ve KISMİ İADE olarak gösterilir',
        (WidgetTester tester) async {
      final db = localDb.database;
      final now = DateTime.now();

      // Eski/unreconciled satış: status COMPLETED ancak local_refunds kaydı mevcut
      await db.into(db.localSales).insert(
        LocalSalesCompanion(
          id: const Value('csale_legacy_refunded'),
          deviceId: const Value(testDeviceId),
          clientSeq: const Value(50),
          totalAmount: const Value(7500),
          paymentMethod: const Value('CASH'),
          status: const Value('COMPLETED'), // DB'de henüz COMPLETED kalmış
          createdAt: Value(now),
        ),
      );
      await db.into(db.localRefunds).insert(
        LocalRefundsCompanion(
          id: const Value('ref_legacy_50'),
          saleId: const Value('csale_legacy_refunded'),
          deviceId: const Value(testDeviceId),
          clientSeq: const Value(51),
          totalRefundAmount: const Value(7500), // Tam iade
          paymentMethod: const Value('CASH'),
          reason: const Value('Müşteri iadesi'),
          createdAt: Value(now),
        ),
      );

      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Liste üzerinde fiş detayına girmeden doğrudan İADE EDİLDİ görünmelidir
      expect(find.text('İADE EDİLDİ'), findsOneWidget);

      // Durum filtresinden "İade Edildi" seçildiğinde listelenmelidir
      await tester.tap(find.text('Durum: Tümü'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('İade Edildi').last);
      await tester.pumpAndSettle();

      expect(find.text('İADE EDİLDİ'), findsOneWidget);
      expect(find.text('csale_legacy_refunded'), findsOneWidget);
      expect(find.text('75.00 TL'), findsWidgets);

      // Fiş Detay açıldığında da durumun tutarlı olduğu doğrulanır
      await tester.tap(find.text('Fiş Detay'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Fiş Detayı: csale_legacy_refunded'), findsOneWidget);
      // Hem arka plan listede hem açık diyalogda İADE EDİLDİ rozeti bulunur
      expect(find.text('İADE EDİLDİ'), findsNWidgets(2));

      await tester.tap(find.text('Kapat'));
      await tester.pumpAndSettle();
    });
  });

  group('Android 390x844 Raporlar Reaktif Yenileme ve Regresyon Testleri', () {
    late LocalDatabaseService localDb;
    late MmsApiClient apiClient;

    const androidDeviceId = 'POS-AND-01';
    const windowsHubDeviceId = 'POS-WIN-01';

    setUp(() async {
      localDb = LocalDatabaseService.forTesting(
        NativeDatabase.memory(),
        path: 'C:\\Users\\Mock\\AppData\\Local\\MarketMMS\\android_client.db',
      );
      await localDb.repository.initializeDevice(androidDeviceId);

      final mockClient = MockClient(
        (request) async => http.Response(
          '{"status":"OK","sqlite_version":"3.46.0"}',
          200,
        ),
      );
      apiClient = MmsApiClient(
        client: mockClient,
        baseUrl: 'http://192.168.1.100:8080',
        deviceId: androidDeviceId,
      );
    });

    tearDown(() async {
      await localDb.close();
    });

    testWidgets(
      'Boş yerel DB açılışında Hub downlink (upsertSales) sonrası Raporlar 390x844 ekranında otomatik güncellenir',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              localDatabaseServiceProvider.overrideWithValue(localDb),
              apiClientProvider.overrideWithValue(apiClient),
            ],
            child: const MaterialApp(
              home: SalesHistoryScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Kriterlere uygun satış kaydı bulunamadı.'), findsOneWidget);
        expect(find.text('Fiş Detay'), findsNothing);
        expect(tester.takeException(), isNull);

        // Windows Hub'dan Android'e 2 satış indir (downlink)
        final now = DateTime.now();
        await localDb.repository.upsertSales(
          sales: [
            DownloadedSalePayload(
              id: 'sale_win_001',
              serverSeq: 1,
              deviceId: windowsHubDeviceId,
              clientSeq: 1,
              totalAmount: 4500, // 45.00 TL
              paymentMethod: 'CASH',
              status: 'COMPLETED',
              createdAt: now.subtract(const Duration(minutes: 5)),
              items: [
                DownloadedSaleItemPayload(
                  id: 'sitem_win_001',
                  saleId: 'sale_win_001',
                  productId: 'prod_win_1',
                  productName: 'Çay 500g',
                  unitPrice: 4500,
                  quantity: 1000,
                  totalPrice: 4500,
                ),
              ],
            ),
            DownloadedSalePayload(
              id: 'sale_win_002',
              serverSeq: 2,
              deviceId: windowsHubDeviceId,
              clientSeq: 2,
              totalAmount: 12000, // 120.00 TL
              paymentMethod: 'CARD',
              status: 'COMPLETED',
              createdAt: now,
              items: [
                DownloadedSaleItemPayload(
                  id: 'sitem_win_002',
                  saleId: 'sale_win_002',
                  productId: 'prod_win_2',
                  productName: 'Zeytinyağı 1L',
                  unitPrice: 12000,
                  quantity: 1000,
                  totalPrice: 12000,
                ),
              ],
            ),
          ],
          newCursor: 2,
          deviceId: androidDeviceId,
        );

        // Sync turu tamamlandığında BackgroundSyncCoordinator.onSyncCompleted tarafından çağrılır
        final container = ProviderScope.containerOf(
          tester.element(find.byType(SalesHistoryScreen)),
        );
        await container.read(systemStatusProvider.notifier).refreshLocalMetrics();
        await tester.pumpAndSettle();

        expect(find.text('Kriterlere uygun satış kaydı bulunamadı.'), findsNothing);
        expect(find.text('Fiş Detay'), findsNWidgets(2));
        expect(find.text('sale_win_001'), findsOneWidget);
        expect(find.text('sale_win_002'), findsOneWidget);
        expect(find.text('45.00 TL'), findsOneWidget);
        expect(find.text('120.00 TL'), findsOneWidget);
        expect(find.text('165.00 TL'), findsWidgets); // Brüt ve Net KPI
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Satış sayısı değişmeden Hub downlink ile gelen iptal ve iade durumları 390x844 Raporlar ekranına yansır',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final now = DateTime.now();
        await localDb.repository.upsertSales(
          sales: [
            DownloadedSalePayload(
              id: 'sale_status_1',
              serverSeq: 1,
              deviceId: windowsHubDeviceId,
              clientSeq: 1,
              totalAmount: 5500,
              paymentMethod: 'CASH',
              status: 'COMPLETED',
              createdAt: now.subtract(const Duration(minutes: 2)),
            ),
            DownloadedSalePayload(
              id: 'sale_status_2',
              serverSeq: 2,
              deviceId: windowsHubDeviceId,
              clientSeq: 2,
              totalAmount: 9000,
              paymentMethod: 'CARD',
              status: 'COMPLETED',
              createdAt: now,
            ),
          ],
          newCursor: 2,
          deviceId: androidDeviceId,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              localDatabaseServiceProvider.overrideWithValue(localDb),
              apiClientProvider.overrideWithValue(apiClient),
            ],
            child: const MaterialApp(
              home: SalesHistoryScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('TAMAMLANDI'), findsNWidgets(2));
        expect(find.text('İPTAL EDİLDİ'), findsNothing);
        expect(find.text('İADE EDİLDİ'), findsNothing);

        // Toplam satış sayısı 2 iken sadece durumlar güncelleniyor
        await localDb.repository.upsertSales(
          sales: [
            DownloadedSalePayload(
              id: 'sale_status_1',
              serverSeq: 3,
              deviceId: windowsHubDeviceId,
              clientSeq: 1,
              totalAmount: 5500,
              paymentMethod: 'CASH',
              status: 'CANCELLED',
              cancelReason: 'Hub üzerinden iptal edildi',
              cancelledAt: now,
              createdAt: now.subtract(const Duration(minutes: 2)),
            ),
            DownloadedSalePayload(
              id: 'sale_status_2',
              serverSeq: 4,
              deviceId: windowsHubDeviceId,
              clientSeq: 2,
              totalAmount: 9000,
              paymentMethod: 'CARD',
              status: 'REFUNDED',
              createdAt: now,
            ),
          ],
          newCursor: 4,
          deviceId: androidDeviceId,
        );

        final container = ProviderScope.containerOf(
          tester.element(find.byType(SalesHistoryScreen)),
        );
        await container.read(systemStatusProvider.notifier).refreshLocalMetrics();
        await tester.pumpAndSettle();

        expect(find.text('TAMAMLANDI'), findsNothing);
        expect(find.text('İPTAL EDİLDİ'), findsOneWidget);
        expect(find.text('İADE EDİLDİ'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Aktif filtre, arama metni ve tarih aralığı senkronizasyon yenilemesinde ve ekrana tekrar girişte korunur',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final todayStart = DateTime(2026, 11, 20, 0, 0, 0);
        final todayEnd = DateTime(2026, 11, 20, 23, 59, 59);
        final inRangeTime = DateTime(2026, 11, 20, 10, 30, 0);
        final outOfRangeTime = DateTime(2026, 11, 10, 10, 30, 0);

        await localDb.repository.upsertSales(
          sales: [
            DownloadedSalePayload(
              id: 'sale_card_keep_1',
              serverSeq: 1,
              deviceId: windowsHubDeviceId,
              clientSeq: 1,
              totalAmount: 8000,
              paymentMethod: 'CARD',
              status: 'COMPLETED',
              createdAt: inRangeTime,
            ),
            DownloadedSalePayload(
              id: 'sale_card_old_out',
              serverSeq: 2,
              deviceId: windowsHubDeviceId,
              clientSeq: 2,
              totalAmount: 9900,
              paymentMethod: 'CARD',
              status: 'COMPLETED',
              createdAt: outOfRangeTime,
            ),
            DownloadedSalePayload(
              id: 'sale_cash_skip',
              serverSeq: 3,
              deviceId: windowsHubDeviceId,
              clientSeq: 3,
              totalAmount: 3000,
              paymentMethod: 'CASH',
              status: 'COMPLETED',
              createdAt: inRangeTime,
            ),
          ],
          newCursor: 3,
          deviceId: androidDeviceId,
        );

        final showSalesTab = ValueNotifier<bool>(true);
        addTearDown(showSalesTab.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              localDatabaseServiceProvider.overrideWithValue(localDb),
              apiClientProvider.overrideWithValue(apiClient),
            ],
            child: MaterialApp(
              home: ValueListenableBuilder<bool>(
                valueListenable: showSalesTab,
                builder: (_, visible, _) =>
                    visible ? const SalesHistoryScreen() : const Scaffold(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 390x844 mobil filtre sheet üzerinden ödeme yöntemi seç + arama + tarih aralığı uygula
        await tester.tap(find.text('Filtreler'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ödeme: Tümü'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Kredi Kartı').last);
        await tester.pumpAndSettle();
        // Bottom sheet'i kapat
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        // Arama kutusuna filtre metni gir
        await tester.enterText(find.byType(TextField).first, 'sale_card_keep');
        await tester.pumpAndSettle();

        // Tarih aralığı filtresini ayarla
        final container = ProviderScope.containerOf(
          tester.element(find.byType(SalesHistoryScreen)),
        );
        final currentFilter = container.read(salesHistoryProvider).filter;
        container.read(salesHistoryProvider.notifier).setFilter(
              currentFilter.copyWith(
                startDate: todayStart,
                endDate: todayEnd,
              ),
            );
        await tester.pumpAndSettle();

        expect(find.text('sale_card_keep_1'), findsOneWidget);
        expect(find.text('sale_card_old_out'), findsNothing);
        expect(find.text('sale_cash_skip'), findsNothing);

        // Yeni bir downlink: biri filtreye uyan CARD, diğeri uymayan CASH
        await localDb.repository.upsertSales(
          sales: [
            DownloadedSalePayload(
              id: 'sale_card_keep_2',
              serverSeq: 4,
              deviceId: windowsHubDeviceId,
              clientSeq: 4,
              totalAmount: 6400,
              paymentMethod: 'CARD',
              status: 'COMPLETED',
              createdAt: inRangeTime.add(const Duration(minutes: 5)),
            ),
            DownloadedSalePayload(
              id: 'sale_cash_skip_2',
              serverSeq: 5,
              deviceId: windowsHubDeviceId,
              clientSeq: 5,
              totalAmount: 4200,
              paymentMethod: 'CASH',
              status: 'COMPLETED',
              createdAt: inRangeTime.add(const Duration(minutes: 6)),
            ),
          ],
          newCursor: 5,
          deviceId: androidDeviceId,
        );

        await container.read(systemStatusProvider.notifier).refreshLocalMetrics();
        await tester.pumpAndSettle();

        // Aktif filtreler ve tarih aralığı korunmuş, yeni uyan satış gelmiş olmalı
        final afterSyncFilter = container.read(salesHistoryProvider).filter;
        expect(afterSyncFilter.paymentMethod, 'CARD');
        expect(afterSyncFilter.searchQuery, 'sale_card_keep');
        expect(afterSyncFilter.startDate, todayStart);
        expect(afterSyncFilter.endDate, todayEnd);
        expect(find.text('sale_card_keep_1'), findsOneWidget);
        expect(find.text('sale_card_keep_2'), findsOneWidget);
        expect(find.text('sale_cash_skip_2'), findsNothing);

        // Başka sekmeye geçip tekrar Raporlar ekranına dön (initState post-frame reload testi)
        showSalesTab.value = false;
        await tester.pumpAndSettle();

        // Metrics tetiklemeden doğrudan DB'ye yeni satış ekle
        await localDb.repository.upsertSales(
          sales: [
            DownloadedSalePayload(
              id: 'sale_card_keep_3',
              serverSeq: 6,
              deviceId: windowsHubDeviceId,
              clientSeq: 6,
              totalAmount: 11500,
              paymentMethod: 'CARD',
              status: 'COMPLETED',
              createdAt: inRangeTime.add(const Duration(minutes: 10)),
            ),
          ],
          newCursor: 6,
          deviceId: androidDeviceId,
        );

        showSalesTab.value = true;
        await tester.pumpAndSettle();

        // Tekrar girişte yeni veri yüklenmeli ve filtre/tarih/arama metni korunmalı
        final reenterFilter = container.read(salesHistoryProvider).filter;
        expect(reenterFilter.paymentMethod, 'CARD');
        expect(reenterFilter.searchQuery, 'sale_card_keep');
        expect(reenterFilter.startDate, todayStart);
        expect(reenterFilter.endDate, todayEnd);
        expect(find.text('Filtreler (2)'), findsOneWidget);
        expect(find.text('sale_card_keep_3'), findsOneWidget);
        expect(tester.widget<TextField>(find.byType(TextField).first).controller?.text,
            'sale_card_keep');
        expect(tester.takeException(), isNull);
      },
    );

    test(
      'SalesHistoryNotifier dispose sonrası tamamlanan istekte hata vermez ve eski sorgu yeni sonucu ezmez',
      () async {
        // 1. Dispose sonrası completion güvenliği
        final delayedCompleter = Completer<List<LocalSale>>();
        final disposeRepo = _FakeQueuedSalesRepository([
          delayedCompleter.future,
        ]);
        final disposedNotifier = SalesHistoryNotifier(disposeRepo, androidDeviceId);
        disposedNotifier.dispose();
        delayedCompleter.complete([
          _makeLocalSale('sale_after_dispose', 1000),
        ]);
        await Future<void>.delayed(Duration.zero);

        // 2. Eşzamanlı loadSales yarış koruması (_loadEpoch):
        // ilk (constructor) isteği daha geç dönsün, ikinci istek daha erken dönsün.
        final constructorCompleter = Completer<List<LocalSale>>();
        final newerCompleter = Completer<List<LocalSale>>();
        final raceRepo = _FakeQueuedSalesRepository([
          constructorCompleter.future,
          newerCompleter.future,
        ]);
        final raceNotifier = SalesHistoryNotifier(raceRepo, androidDeviceId);
        addTearDown(raceNotifier.dispose);

        final secondLoad = raceNotifier.loadSales(silent: true);
        newerCompleter.complete([_makeLocalSale('sale_newest', 5500)]);
        await secondLoad;

        // Şimdi ilk (eski) istek geç tamamlansın -> yeni sonucu ezmemeli
        constructorCompleter.complete([_makeLocalSale('sale_stale_old', 1200)]);
        await Future<void>.delayed(Duration.zero);

        expect(raceNotifier.state.sales.length, 1);
        expect(raceNotifier.state.sales.first.id, 'sale_newest');
        expect(raceNotifier.state.isLoading, isFalse);
      },
    );
  });
}

LocalSale _makeLocalSale(String id, int totalAmount) {
  return LocalSale(
    id: id,
    deviceId: 'POS-WIN-01',
    clientSeq: 1,
    totalAmount: totalAmount,
    paymentMethod: 'CASH',
    status: 'COMPLETED',
    createdAt: DateTime(2026, 11, 20, 12, 0),
  );
}

class _FakeQueuedSalesRepository implements SalesRepository {
  final List<Future<List<LocalSale>>> _queuedResponses;
  int _index = 0;

  _FakeQueuedSalesRepository(this._queuedResponses);

  @override
  Future<List<LocalSale>> getSales({
    SaleHistoryFilter? filter,
    int limit = 50,
    int offset = 0,
  }) {
    final i = _index < _queuedResponses.length ? _index++ : _queuedResponses.length - 1;
    return _queuedResponses[i];
  }

  @override
  Future<SaleWithDetails?> getSaleDetail(String saleId) async => null;

  @override
  Future<void> cancelSale({
    required String saleId,
    required String reason,
    required String deviceId,
  }) async {}

  @override
  Future<String> refundSale({
    required String saleId,
    required List<RefundItemInput> items,
    required String reason,
    required String deviceId,
  }) async =>
      'ref_mock';
}
