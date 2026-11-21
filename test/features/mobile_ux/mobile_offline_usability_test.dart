import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:market_pos/app/app.dart';
import 'package:market_pos/core/network/api_client.dart';
import 'package:market_pos/core/platform/mms_ui_profile.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/core/utils/debouncer.dart';
import 'package:market_pos/core/utils/user_friendly_error_mapper.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:market_pos/features/pos/application/cart_notifier.dart';
import 'package:market_pos/features/pos/data/local_pos_repository.dart';
import 'package:market_pos/features/sync/application/background_sync_coordinator.dart';
import 'package:market_pos/features/sync/domain/sync_coordinator_state.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

class _RecordingSyncTransport implements SyncTransport {
  final List<Map<String, dynamic>> postedSales = [];
  bool offline = true;

  @override
  Future<SyncResponse> postSale({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (offline) {
      return SyncResponse.networkError('SocketException: Connection refused');
    }
    final decoded = jsonDecode(payload) as Map<String, dynamic>;
    postedSales.add(decoded);
    return SyncResponse(
      statusCode: 201,
      body: jsonEncode({
        'status': 'CREATED',
        'sale_id': decoded['sale_id'] ?? 'synced_sale',
      }),
      headers: const {'content-type': 'application/json'},
    );
  }

  @override
  Future<SyncResponse> postProductUpsert({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      SyncResponse(statusCode: 200, body: '{}', headers: const {});

  @override
  Future<SyncResponse> getProducts({
    required String hubUrl,
    required String token,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      SyncResponse(
        statusCode: 200,
        body: jsonEncode({'products': <Object>[]}),
        headers: const {'content-type': 'application/json'},
      );

  @override
  Future<SyncResponse> getSales({
    required String hubUrl,
    required String token,
    int cursor = 0,
    int limit = 50,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      SyncResponse(
        statusCode: 200,
        body: jsonEncode({
          'sales': <Object>[],
          'next_cursor': cursor,
          'has_more': false,
        }),
        headers: const {'content-type': 'application/json'},
      );

  @override
  Future<SyncResponse> postSyncAck({
    required String hubUrl,
    required String token,
    required String syncSessionId,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      SyncResponse(statusCode: 200, body: '{}', headers: const {});

  @override
  Future<SyncResponse> postStockReceipt({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      const SyncResponse(statusCode: 200, body: '{"status":"COMMITTED"}');

  @override
  void close() {}
}

void main() {
  group('Faz 6: Hata Sadeleştirme & Debouncer Birim Testleri', () {
    test('UserFriendlyErrorMapper teknik hataları ve sırları temiz Türkçe mesaja dönüştürür', () {
      expect(
        UserFriendlyErrorMapper.map(
          'SocketException: Connection refused (errno = 111) Bearer mms_dt_secret123',
        ),
        contains('yerel ağ bağlantısı kurulamadı'),
      );
      expect(
        UserFriendlyErrorMapper.redactSecrets(
          'Authorization: Bearer abc.def-123 password=mySecretValue token: mms_dt_xyz',
        ),
        isNot(anyOf(contains('abc.def-123'), contains('mySecretValue'), contains('mms_dt_xyz'))),
      );
      expect(
        UserFriendlyErrorMapper.map('HandshakeException: CERTIFICATE_VERIFY_FAILED'),
        contains('TLS sertifika doğrulaması'),
      );
      expect(
        UserFriendlyErrorMapper.map('SqliteException(5): database is locked'),
        contains('Yerel veritabanı kısa süreli yoğun'),
      );
    });

    test('Debouncer ardışık çağrıları tekilleştirir ve runImmediate hemen çalıştırır', () async {
      final debouncer = Debouncer(delay: const Duration(milliseconds: 40));
      final calls = <String>[];

      debouncer.run(() => calls.add('a'));
      debouncer.run(() => calls.add('ab'));
      debouncer.run(() => calls.add('abc'));
      expect(calls, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(calls, ['abc']);

      debouncer.runImmediate(() => calls.add('clear'));
      expect(calls, ['abc', 'clear']);
      debouncer.dispose();
    });
  });

  group('Faz 6: Gerçek FFI SQLite Yeniden Başlatma & Kayıpsız Offline->Online Senkronizasyon', () {
    late Directory tempDir;
    late String dbPath;

    setUp(() {
      LocalDatabaseService.resetForTesting();
      tempDir = Directory.systemTemp.createTempSync('mms_faz6_restart_');
      dbPath = p.join(tempDir.path, 'client_local.db');
    });

    tearDown(() async {
      await LocalDatabaseService.closeActive();
      LocalDatabaseService.resetForTesting();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'çevrimdışı satışlar uygulama kapanıp açılsa da korunur; bağlantı gelince FIFO kayıpsız ve mükerrersız aktarılır',
      () async {
        const deviceId = 'POS-AND-RESTART-01';

        // 1. Oturum: Çevrimdışı satışlar yap ve veritabanını kapat (restart simülasyonu)
        final dbSession1 = await LocalDatabaseService.initialize(customPath: dbPath);
        await dbSession1.repository.initializeDevice(deviceId);
        await dbSession1.repository.upsertProducts(
          [
            LocalProductsCompanion(
              id: const Value('prod_su'),
              barcode: const Value('8690001000010'),
              name: const Value('Doğal Su 500ml'),
              price: const Value(500),
              priceVersionId: const Value('pv_su_1'),
              stock: const Value(10000), // 10 adet
              stockUnit: const Value('adet'),
              pricingUnit: const Value('adet'),
              conversionFactorNumerator: const Value(1),
              conversionFactorDenominator: const Value(1),
              isActive: const Value(true),
              updatedAt: Value(DateTime(2026, 11, 20, 12, 0)),
            ),
          ],
          barcodes: const [
            LocalProductBarcodesCompanion(
              id: Value('bc_su'),
              productId: Value('prod_su'),
              barcode: Value('8690001000010'),
              isPrimary: Value(true),
              isActive: Value(true),
            ),
          ],
        );

        final cart1 = CartNotifier(
          repository: LocalPosRepository(dbSession1),
          readDeviceId: () => deviceId,
          isHubOffline: () => true,
        );

        expect(await cart1.scanBarcode('8690001000010'), isTrue);
        final s1 = await cart1.completeSale(
          paymentMethod: PaymentMethod.cash,
          cashReceivedCents: 1000,
        );
        expect(s1, isNotNull);
        expect(cart1.state.infoMessage, contains('çevrimdışı kaydedildi'));

        expect(await cart1.scanBarcode('8690001000010'), isTrue);
        expect(await cart1.scanBarcode('8690001000010'), isTrue);
        final s2 = await cart1.completeSale(
          paymentMethod: PaymentMethod.card,
          externalPosConfirmed: true,
        );
        expect(s2, isNotNull);

        expect(await dbSession1.getLocalSalesCount(), 2);
        expect(await dbSession1.getPendingOutboxCount(), 2);
        await dbSession1.close();
        LocalDatabaseService.resetForTesting();

        // 2. Oturum: Uygulama yeniden açıldı -> veriler, stok ve bekleyen Outbox korunmuş olmalı
        final dbSession2 = await LocalDatabaseService.initialize(customPath: dbPath);
        expect(await dbSession2.getLocalSalesCount(), 2);
        expect(await dbSession2.getPendingOutboxCount(), 2);
        final persistedProduct =
            await dbSession2.repository.getProductById('prod_su');
        expect(persistedProduct?.stock, 7000); // 10 - 1 - 2 = 7 adet

        // Ağ yokken sync: kayıtlar kaybedilmez
        final transport = _RecordingSyncTransport();
        final coordinator = BackgroundSyncCoordinator(
          repository: dbSession2.repository,
          transport: transport,
          deviceId: deviceId,
          readDeviceToken: () => 'mms_dt_test_valid_token',
          hubUrl: 'http://192.168.1.50:8945',
          autoStartTimer: false,
          enableLifecycleListener: false,
        );
        addTearDown(coordinator.dispose);

        await coordinator.triggerSync(reason: SyncTriggerReason.startup);
        expect(transport.postedSales, isEmpty);
        final summaryWhileOffline = await dbSession2.getOutboxSummary();
        expect(summaryWhileOffline.totalUnsynced, 2);
        expect(summaryWhileOffline.failedPermanent, 0);

        // Tekrar deneme backoff süresinin dolduğunu simüle et ve bağlantıyı aç
        await dbSession2.database.update(dbSession2.database.outboxOperations).write(
              OutboxOperationsCompanion(
                nextRetryAt: Value(
                  DateTime.now().toUtc().subtract(const Duration(seconds: 5)),
                ),
              ),
            );
        transport.offline = false;
        final batch1 = await coordinator.triggerSync(
          reason: SyncTriggerReason.connectivityRestored,
        );
        expect(batch1, isNotNull);
        expect(batch1!.syncedCount, 2);
        expect(await dbSession2.getPendingOutboxCount(), 0);
        expect(transport.postedSales.length, 2);
        expect(transport.postedSales[0]['client_seq'], 1);
        expect(transport.postedSales[1]['client_seq'], 2);

        // Tekrar sync çağrıldığında mükerrer kayıt oluşturmaz
        final batch2 = await coordinator.triggerSync(
          reason: SyncTriggerReason.manual,
        );
        expect(batch2?.syncedCount ?? 0, 0);
        expect(transport.postedSales.length, 2);
      },
    );
  });

  group('Faz 6: Mobil Çevrimdışı UX, Durum Görünürlüğü ve Telefon/Tablet Regresyonları', () {
    late LocalDatabaseService localDb;
    late MmsApiClient offlineApiClient;

    setUp(() async {
      localDb = LocalDatabaseService.forTesting(
        NativeDatabase.memory(),
        path: 'C:\\Users\\Mock\\AppData\\Local\\MarketMMS\\faz6_ui.db',
      );
      final repo = localDb.repository;
      await repo.initializeDevice('POS-AND-01');
      await repo.upsertProducts(
        [
          LocalProductsCompanion(
            id: const Value('prod_ekmek'),
            barcode: const Value('8690000111222'),
            name: const Value('Tam Buğday Ekmek'),
            price: const Value(1500),
            priceVersionId: const Value('pv_ekmek_1'),
            stock: const Value(30000),
            stockUnit: const Value('adet'),
            pricingUnit: const Value('adet'),
            conversionFactorNumerator: const Value(1),
            conversionFactorDenominator: const Value(1),
            isActive: const Value(true),
            updatedAt: Value(DateTime(2026, 11, 20, 12, 0)),
          ),
        ],
        barcodes: const [
          LocalProductBarcodesCompanion(
            id: Value('bc_ekmek'),
            productId: Value('prod_ekmek'),
            barcode: Value('8690000111222'),
            isPrimary: Value(true),
            isActive: Value(true),
          ),
        ],
      );

      offlineApiClient = MmsApiClient(
        client: MockClient(
          (_) async => throw const SocketException('Connection refused (errno = 111)'),
        ),
        baseUrl: 'http://192.168.1.50:8945',
        deviceId: 'POS-AND-01',
        deviceToken: 'mms_dt_test_token_123',
      );
    });

    tearDown(() async {
      await localDb.close();
    });

    testWidgets(
      'Telefon (390x844 ve 360x640) & Tablet (800x1280): çevrimdışı satış, bekleyen sayı ve özet bottom sheet sıfır overflow ile çalışır',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              localDatabaseServiceProvider.overrideWithValue(localDb),
              apiClientProvider.overrideWithValue(offlineApiClient),
              mmsUiProfileProvider.overrideWithValue(const MmsUiProfile.mobile()),
            ],
            child: const MarketPosApp(),
          ),
        );
        await tester.pumpAndSettle();

        // Çevrimdışı şeridi ve mobil durum pill'i görünür
        expect(find.byKey(const Key('app_offline_indicator')), findsOneWidget);
        expect(find.byKey(const Key('mobile_status_pill')), findsOneWidget);
        expect(find.text('Çevrimdışı'), findsOneWidget);

        // Çevrimdışı satış yap -> anlaşılır çevrimdışı onay mesajı ve pill'de bekleyen sayacı görünür
        await tester.enterText(
          find.byKey(const Key('barcode_input_field')),
          '8690000111222',
        );
        await tester.tap(find.byKey(const Key('barcode_add_button')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('cash_pay_button')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('cash_received_input')),
          '20.00',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('payment_confirm_button')));
        await tester.pumpAndSettle();

        expect(find.textContaining('Satış çevrimdışı kaydedildi'), findsOneWidget);
        expect(find.text('Çevrimdışı • 1'), findsOneWidget);

        // Durum pill'ine tıkla -> Bağlantı ve Senkronizasyon Özet BottomSheet açılır (ham teknik SocketException yerine temiz Türkçe)
        await tester.tap(find.byKey(const Key('mobile_status_pill')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('mobile_connection_summary_sheet')), findsOneWidget);
        expect(find.byKey(const Key('summary_sheet_sync_now_button')), findsOneWidget);
        expect(find.byKey(const Key('summary_sheet_rediscover_button')), findsOneWidget);
        expect(find.textContaining('SocketException'), findsNothing);
        expect(tester.takeException(), isNull);

        // Bottom sheet'i kapat ve küçük telefon (360x640) + tablet (800x1280) doğrulaması yap
        Navigator.of(
          tester.element(find.byKey(const Key('mobile_connection_summary_sheet'))),
        ).pop();
        await tester.pumpAndSettle();

        for (final size in [const Size(360, 640), const Size(800, 1280)]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'Offline UI $size overflow');
        }
      },
    );
  });
}
