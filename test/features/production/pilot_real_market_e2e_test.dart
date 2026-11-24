import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/app/app.dart';
import 'package:market_pos/core/network/api_client.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/core/utils/user_friendly_error_mapper.dart';
import 'package:market_pos/features/backup/application/background_backup_scheduler.dart';
import 'package:market_pos/features/backup/backup_providers.dart';
import 'package:market_pos/features/catalog/catalog_providers.dart';
import 'package:market_pos/features/dashboard/dashboard_providers.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:market_pos/features/pos/pos_providers.dart';
import 'package:market_pos/features/sales/presentation/screens/sales_history_screen.dart';
import 'package:market_pos/features/sales/sales_providers.dart';
import 'package:market_pos/features/stock/stock_providers.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

class _SpyBackgroundBackupScheduler implements BackgroundBackupScheduler {
  int getStatusCalls = 0;

  @override
  bool get isPlatformSupported => true;

  @override
  Future<BackgroundBackupScheduleStatus> cancelPeriodic() async {
    return BackgroundBackupScheduleStatus.idle;
  }

  @override
  Future<BackgroundBackupScheduleStatus> getStatus() async {
    getStatusCalls++;
    return BackgroundBackupScheduleStatus.idle;
  }

  @override
  Future<BackgroundBackupScheduleStatus> schedulePeriodic({
    required Duration interval,
    BackgroundBackupConstraints constraints = const BackgroundBackupConstraints(),
  }) async {
    return BackgroundBackupScheduleStatus(
      isScheduled: true,
      supportedOnPlatform: true,
      intervalMinutes: interval.inMinutes,
      constraints: constraints,
    );
  }
}

void main() {
  group('Pilot 1.0 Gerçek Market Uçtan Uca Kalite & Regresyon Süiti', () {
    late Directory tempDir;
    late LocalDatabaseService localDb;
    late MmsApiClient offlineApiClient;

    const deviceId = 'POS-PILOT-E2E';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('mms_real_market_e2e_');
      localDb = LocalDatabaseService.forTesting(
        NativeDatabase.memory(),
        path: p.join(tempDir.path, 'client_local.db'),
      );
      await localDb.repository.initializeDevice(deviceId);

      offlineApiClient = MmsApiClient(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({'status': 'DRAINING'}),
            503,
            headers: {'content-type': 'application/json'},
          );
        }),
        baseUrl: 'https://127.0.0.1:8945',
        deviceId: deviceId,
      );
    });

    tearDown(() async {
      await localDb.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets(
      '1. Otomatik zamanlanmış yedek & JobScheduler açılışta Kasa sekmesinde başlatılır',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 720);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final spyScheduler = _SpyBackgroundBackupScheduler();
        final onlineMockClient = MmsApiClient(
          client: MockClient((request) async {
            return http.Response(
              jsonEncode({'status': 'UP', 'sqlite_version': '3.45.1'}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
          baseUrl: 'https://127.0.0.1:8945',
          deviceId: deviceId,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              localDatabaseServiceProvider.overrideWithValue(localDb),
              apiClientProvider.overrideWithValue(onlineMockClient),
              backupRootDirectoryProvider.overrideWithValue(
                Directory(p.join(tempDir.path, 'backups')),
              ),
              backgroundBackupSchedulerProvider.overrideWithValue(spyScheduler),
              backupAutoScheduleLifecycleEnabledProvider.overrideWithValue(true),
            ],
            child: const MarketPosApp(),
          ),
        );
        for (var i = 0; i < 25 && spyScheduler.getStatusCalls == 0; i++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          });
          await tester.pump();
        }
        await tester.pumpAndSettle();

        // Kullanıcı Sistem & Tanı sekmesine hiç geçmeden arka plan zamanlayıcısı çalışır
        expect(find.text('Kasa (Satış)'), findsOneWidget);
        expect(spyScheduler.getStatusCalls, greaterThanOrEqualTo(1));
      },
    );

    test(
      '2. Dashboard net ciro hesaplaması: Kısmi iade, tam iade (REFUNDED) ve iptal (CANCELLED) kuruş hassasiyetinde doğrudur',
      () async {
        final repo = localDb.repository;
        final prod = await repo.createProduct(
          name: 'Çaykur Tiryaki 1kg',
          price: 2500, // 25.00 TL birim fiyatla net hesap testi
          barcode: '8690101000011',
          initialStock: 100000,
          deviceId: deviceId,
        );

        // Satış 1 (CASH): 2 adet = 50.00 TL (COMPLETED kalır)
        await repo.createOfflineSale(
          deviceId: deviceId,
          paymentMethod: 'CASH',
          items: [CartItemInput.units(prod.id, 2)],
        );

        // Satış 2 (CARD): 4 adet = 100.00 TL -> 1 adet iade (25.00 TL) => net 75.00 TL (PARTIALLY_REFUNDED)
        final partialSale = await repo.createOfflineSale(
          deviceId: deviceId,
          paymentMethod: 'CARD',
          items: [CartItemInput.units(prod.id, 4)],
        );
        final partialDetail = await repo.getSaleDetail(partialSale.saleId);
        await repo.refundSale(
          saleId: partialSale.saleId,
          items: [
            RefundItemInput(
              saleItemId: partialDetail!.items.first.id,
              quantity: 1000,
              productCondition: 'SELLABLE',
            ),
          ],
          reason: 'Müşteri 1 paketi iade etti',
          deviceId: deviceId,
        );

        // Satış 3 (CASH): 2 adet = 50.00 TL -> Tamamı iade => status REFUNDED, net 0
        final fullRefundSale = await repo.createOfflineSale(
          deviceId: deviceId,
          paymentMethod: 'CASH',
          items: [CartItemInput.units(prod.id, 2)],
        );
        final fullRefundDetail = await repo.getSaleDetail(fullRefundSale.saleId);
        await repo.refundSale(
          saleId: fullRefundSale.saleId,
          items: [
            RefundItemInput(
              saleItemId: fullRefundDetail!.items.first.id,
              quantity: 2000,
              productCondition: 'DAMAGED',
            ),
          ],
          reason: 'Ambalaj hasarlı',
          deviceId: deviceId,
        );

        // Satış 4 (CARD): 3 adet = 75.00 TL -> Tam satış iptali => CANCELLED
        final cancelledSale = await repo.createOfflineSale(
          deviceId: deviceId,
          paymentMethod: 'CARD',
          items: [CartItemInput.units(prod.id, 3)],
        );
        await repo.cancelSale(
          saleId: cancelledSale.saleId,
          reason: 'Yanlış okutma iptali',
          deviceId: deviceId,
        );

        final container = ProviderContainer(
          overrides: [
            localDatabaseServiceProvider.overrideWithValue(localDb),
            apiClientProvider.overrideWithValue(offlineApiClient),
          ],
        );
        addTearDown(container.dispose);

        container.read(systemStatusProvider);
        await container.read(systemStatusProvider.notifier).refreshStatus();

        final snapshot = await container.read(dashboardSnapshotProvider.future);
        expect(snapshot.todaySalesTotalCents, equals(12500)); // 50.00 + 75.00 TL
        expect(snapshot.todayCashTotalCents, equals(5000));
        expect(snapshot.todayCardTotalCents, equals(7500));
        expect(snapshot.todaySalesCount, equals(2));
        expect(snapshot.last7DaysTrend.last.totalCents, equals(12500));
        expect(snapshot.last7DaysTrend.last.count, equals(2));
      },
    );

    test(
      '3. Çapraz ekran reaktivitesi: Ürün ekle -> Stok girişi -> Satış -> İade -> İptal Outbox ve tüm modülleri günceller',
      () async {
        final container = ProviderContainer(
          overrides: [
            localDatabaseServiceProvider.overrideWithValue(localDb),
            apiClientProvider.overrideWithValue(offlineApiClient),
          ],
        );
        addTearDown(container.dispose);

        // Modülleri canlı tut (UI ekranları açıkmış gibi dinle)
        container.listen(systemStatusProvider, (_, _) {});
        container.listen(catalogProvider, (_, _) {});
        container.listen(stockOverviewProvider, (_, _) {});
        container.listen(dashboardSnapshotProvider, (_, _) {});
        container.listen(salesHistoryProvider, (_, _) {});

        await container.read(catalogProvider.notifier).init();
        await container.read(systemStatusProvider.notifier).refreshStatus();

        // A. Ürün Ekle
        final created = await container.read(catalogProvider.notifier).createProduct(
              name: 'Pilot Maden Suyu 200ml',
              price: 1500, // 15.00 TL
              barcode: '8699990000011',
              initialStock: 10000, // 10 adet
            );
        expect(created, isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(container.read(systemStatusProvider).outboxSummary.totalUnsynced, equals(1));
        var dash = await container.read(dashboardSnapshotProvider.future);
        expect(dash.activeProductCount, equals(1));
        var stockData = await container.read(stockOverviewProvider.future);
        expect(stockData.products.single.stock, equals(10000));

        // B. Barkodla Stok Girişi (+5 adet -> 15 adet)
        await container.read(stockReceiptProvider.notifier).lookupBarcode('8699990000011');
        final rcptOk = await container
            .read(stockReceiptProvider.notifier)
            .submit(rawQuantity: '5', rawPurchasePrice: '8,50', rawNote: 'İrsaliye-1');
        expect(rcptOk, isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(container.read(systemStatusProvider).outboxSummary.totalUnsynced, equals(2));
        stockData = await container.read(stockOverviewProvider.future);
        expect(stockData.products.single.stock, equals(15000));
        expect(
          container.read(catalogProvider).products.single.stock,
          equals(15000),
        );

        // C. POS Satışı (2 adet -> 13 adet, 30.00 TL)
        final scanned = await container
            .read(cartProvider.notifier)
            .scanBarcode('8699990000011');
        expect(scanned, isTrue);
        container.read(cartProvider.notifier).incrementProduct(
              stockData.products.single.id,
            );
        final completed = await container.read(cartProvider.notifier).completeSale(
              paymentMethod: PaymentMethod.cash,
              cashReceivedCents: 5000,
            );
        expect(completed, isNotNull);
        expect(completed!.cashChangeCents, equals(2000));
        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(container.read(systemStatusProvider).outboxSummary.totalUnsynced, equals(3));
        dash = await container.read(dashboardSnapshotProvider.future);
        expect(dash.todaySalesTotalCents, equals(3000));
        expect(
          container.read(catalogProvider).products.single.stock,
          equals(13000),
        );

        // D. Kısmi İade (1 adet SELLABLE -> stok 14 adet, net ciro 15.00 TL)
        final saleId1 = completed.saleId;
        final saleDetail1 = await localDb.repository.getSaleDetail(saleId1);
        final refunded = await container.read(salesHistoryProvider.notifier).refundSale(
          saleId: saleId1,
          items: [
            RefundItemInput(
              saleItemId: saleDetail1!.items.first.id,
              quantity: 1000,
              productCondition: 'SELLABLE',
            ),
          ],
          reason: 'Müşteri 1 şişe iade etti',
        );
        expect(refunded, isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(container.read(systemStatusProvider).outboxSummary.totalUnsynced, equals(4));
        dash = await container.read(dashboardSnapshotProvider.future);
        expect(dash.todaySalesTotalCents, equals(1500));
        expect(
          container.read(catalogProvider).products.single.stock,
          equals(14000),
        );

        // E. İkinci satış (1 adet) + Tam İptal -> stok tekrar 14 adet
        await container.read(cartProvider.notifier).scanBarcode('8699990000011');
        final completed2 = await container.read(cartProvider.notifier).completeSale(
              paymentMethod: PaymentMethod.card,
              externalPosConfirmed: true,
            );
        expect(completed2, isNotNull);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final cancelled = await container.read(salesHistoryProvider.notifier).cancelSale(
              saleId: completed2!.saleId,
              reason: 'Kasiyer iptali',
            );
        expect(cancelled, isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(container.read(systemStatusProvider).outboxSummary.totalUnsynced, equals(6));
        dash = await container.read(dashboardSnapshotProvider.future);
        expect(dash.todaySalesTotalCents, equals(1500));
        expect(
          container.read(catalogProvider).products.single.stock,
          equals(14000),
        );
      },
    );

    test(
      '4. Bilinmeyen barkod OD-03 mesajı ve UserFriendlyErrorMapper önek temizliği',
      () async {
        final container = ProviderContainer(
          overrides: [
            localDatabaseServiceProvider.overrideWithValue(localDb),
            apiClientProvider.overrideWithValue(offlineApiClient),
          ],
        );
        addTearDown(container.dispose);

        final ok = await container
            .read(cartProvider.notifier)
            .scanBarcode('8699999888777');
        expect(ok, isFalse);
        final err = container.read(cartProvider).errorMessage!;
        expect(err, contains('Ürünler'));
        expect(err, contains('Master Hub'));

        expect(
          UserFriendlyErrorMapper.map(StateError('Satış tutarı 0 olamaz')),
          equals('Satış tutarı 0 olamaz'),
        );
        expect(
          UserFriendlyErrorMapper.map(ArgumentError('Geçersiz miktar')),
          equals('Geçersiz miktar'),
        );
        expect(
          UserFriendlyErrorMapper.map(Exception('Özel hata açıklaması')),
          equals('Özel hata açıklaması'),
        );
      },
    );

    testWidgets(
      '5. Satış Geçmişi tarih aralığı seçicisi Türkçe başlık ve düğme etiketleriyle açılır',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              localDatabaseServiceProvider.overrideWithValue(localDb),
              apiClientProvider.overrideWithValue(offlineApiClient),
            ],
            child: const MaterialApp(
              home: SalesHistoryScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Tarih Aralığı'));
        await tester.pumpAndSettle();

        expect(find.text('Tarih Aralığı Seçin'), findsOneWidget);
        expect(find.text('Uygula'), findsOneWidget);

        // Manuel giriş moduna geçince Türkçe Başlangıç / Bitiş etiketleri görünür
        await tester.tap(find.byIcon(Icons.edit_outlined));
        await tester.pumpAndSettle();
        expect(find.text('Başlangıç Tarihi'), findsOneWidget);
        expect(find.text('Bitiş Tarihi'), findsOneWidget);
      },
    );
  });
}
