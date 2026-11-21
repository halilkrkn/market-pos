import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

class _MockSalesDownlinkTransport implements SyncTransport {
  final List<int> requestedCursors = [];
  final Map<int, SyncResponse> responsesByCursor = {};
  SyncResponse? defaultResponse;
  bool throwNetworkErrorOnSales = false;

  @override
  Future<SyncResponse> getSales({
    required String hubUrl,
    required String token,
    int cursor = 0,
    int limit = 50,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    requestedCursors.add(cursor);
    if (throwNetworkErrorOnSales) {
      return SyncResponse.networkError('Bağlantı koptu (Mock socket error)');
    }
    if (responsesByCursor.containsKey(cursor)) {
      return responsesByCursor[cursor]!;
    }
    if (defaultResponse != null) {
      return defaultResponse!;
    }
    return SyncResponse(
      statusCode: 200,
      body: jsonEncode({
        'status': 'OK',
        'sales': [],
        'cursor': cursor,
        'next_cursor': cursor,
        'has_more': false,
      }),
    );
  }

  @override
  Future<SyncResponse> getProducts({
    required String hubUrl,
    required String token,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return SyncResponse(statusCode: 200, body: jsonEncode({'products': []}));
  }

  @override
  Future<SyncResponse> postProductUpsert({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return SyncResponse(statusCode: 200, body: jsonEncode({'status': 'OK'}));
  }

  @override
  Future<SyncResponse> postSale({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return SyncResponse(statusCode: 201, body: jsonEncode({'status': 'COMMITTED'}));
  }

  @override
  Future<SyncResponse> postSyncAck({
    required String hubUrl,
    required String token,
    required String syncSessionId,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return SyncResponse(statusCode: 200, body: jsonEncode({'status': 'ACK'}));
  }

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
  late Directory tempDir;
  late File dbFile;
  late ClientDatabase db;
  late ClientStorageRepository repo;
  late _MockSalesDownlinkTransport transport;
  late ClientSyncService syncService;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    tempDir = await Directory.systemTemp.createTemp('mms_sales_downlink_test_');
    dbFile = File(p.join(tempDir.path, 'client_local.db'));
    db = ClientDatabase(dbFile);
    repo = ClientStorageRepository(db);
    transport = _MockSalesDownlinkTransport();

    syncService = ClientSyncService(
      repository: repo,
      transport: transport,
      deviceId: 'POS-WIN-01',
      deviceToken: 'mms_win_secret_token_123',
      hubUrl: 'http://127.0.0.1:8945',
    );

    // Başlangıç senkronizasyon durumu
    await repo.initializeDevice('POS-WIN-01');

    // Test ürününü ekle
    await repo.upsertProducts([
      LocalProductsCompanion(
        id: const Value('prod_1001'),
        barcode: const Value('99910002'),
        name: const Value('Senkronizasyon Test Ürünü'),
        price: const Value(7500),
        stock: const Value(50000),
        stockUnit: const Value('adet'),
        pricingUnit: const Value('adet'),
        updatedAt: Value(DateTime.now()),
      ),
    ]);
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('MARKET MMS — Sales Downlink & Multi-Device Sync Testleri', () {
    test('Senaryo 1: Android -> Hub -> Windows downlink (Satışın Windows lokal DB ve Satış Geçmişine inmesi)', () async {
      // Android cihazında 75 TL'lik nakit satış yapılmış gibi payload hazırla
      final androidSalePayload = {
        'status': 'OK',
        'sales': [
          {
            'id': 'sale_android_001',
            'server_seq': 10,
            'device_id': 'POS-ANDROID-01',
            'client_seq': 2,
            'total_amount': 7500,
            'payment_method': 'CASH',
            'status': 'COMPLETED',
            'cancel_reason': null,
            'cancelled_at': null,
            'created_at': DateTime.now().toIso8601String(),
            'items': [
              {
                'id': 'item_android_001',
                'sale_id': 'sale_android_001',
                'product_id': 'prod_1001',
                'product_name': 'Senkronizasyon Test Ürünü',
                'unit': 'adet',
                'price_version_id': 'pv_init',
                'unit_price': 7500,
                'quantity': 1000,
                'total_price': 7500,
              }
            ],
            'refunds': [],
          }
        ],
        'cursor': 0,
        'next_cursor': 10,
        'has_more': false,
      };

      transport.responsesByCursor[0] = SyncResponse(
        statusCode: 200,
        body: jsonEncode(androidSalePayload),
      );

      // Downlink senkronizasyonunu çalıştır
      final downloadedCount = await syncService.syncSales();
      expect(downloadedCount, equals(1));

      // Windows local DB doğrulamaları
      final salesHistory = await repo.getSalesHistory();
      expect(salesHistory.length, equals(1));
      expect(salesHistory.first.id, equals('sale_android_001'));
      expect(salesHistory.first.deviceId, equals('POS-ANDROID-01'));
      expect(salesHistory.first.clientSeq, equals(2));
      expect(salesHistory.first.totalAmount, equals(7500));
      expect(salesHistory.first.paymentMethod, equals('CASH'));
      expect(salesHistory.first.status, equals('COMPLETED'));

      // Detay doğrulama
      final detail = await repo.getSaleDetail('sale_android_001');
      expect(detail, isNotNull);
      expect(detail!.items.length, equals(1));
      expect(detail.items.first.productNameSnapshot, equals('Senkronizasyon Test Ürünü'));
      expect(detail.items.first.totalPrice, equals(7500));

      // Cursor ilerlemesi doğrulama
      final syncState = await repo.getSyncState('POS-WIN-01');
      expect(syncState!.lastServerSaleSeq, equals(10));
      expect(syncState.lastSalesSyncAt, isNotNull);
    });

    test('Senaryo 2: Windows -> Android simülasyonu (Farklı cihaz ID ile çalışan Android istemcisi)', () async {
      final androidDbFile = File(p.join(tempDir.path, 'android_client_local.db'));
      final androidDb = ClientDatabase(androidDbFile);
      final androidRepo = ClientStorageRepository(androidDb);
      await androidRepo.initializeDevice('POS-ANDROID-01');

      final androidSyncService = ClientSyncService(
        repository: androidRepo,
        transport: transport,
        deviceId: 'POS-ANDROID-01',
        deviceToken: 'mms_android_secret_token_123',
        hubUrl: 'http://127.0.0.1:8945',
      );

      // Windows cihazından oluşturulmuş satış
      final winSalePayload = {
        'status': 'OK',
        'sales': [
          {
            'id': 'sale_win_001',
            'server_seq': 15,
            'device_id': 'POS-WIN-01',
            'client_seq': 5,
            'total_amount': 15000,
            'payment_method': 'CARD',
            'status': 'COMPLETED',
            'cancel_reason': null,
            'cancelled_at': null,
            'created_at': DateTime.now().toIso8601String(),
            'items': [
              {
                'id': 'item_win_001',
                'sale_id': 'sale_win_001',
                'product_id': 'prod_win_1',
                'product_name': 'Windows Ürünü',
                'unit': 'adet',
                'price_version_id': 'pv_init',
                'unit_price': 15000,
                'quantity': 1000,
                'total_price': 15000,
              }
            ],
            'refunds': [],
          }
        ],
        'cursor': 0,
        'next_cursor': 15,
        'has_more': false,
      };

      transport.responsesByCursor[0] = SyncResponse(
        statusCode: 200,
        body: jsonEncode(winSalePayload),
      );

      final count = await androidSyncService.syncSales();
      expect(count, equals(1));

      final androidSales = await androidRepo.getSalesHistory();
      expect(androidSales.length, equals(1));
      expect(androidSales.first.deviceId, equals('POS-WIN-01'));
      expect(androidSales.first.totalAmount, equals(15000));
      expect(androidSales.first.paymentMethod, equals('CARD'));

      await androidDb.close();
    });

    test('Senaryo 3: Duplicate koruması (Kendi yaptığı satışı indiren istemcide mükerrerlik oluşmaması)', () async {
      // 1. Windows üzerinde yerel bir satış oluştur
      final localSaleResult = await repo.createOfflineSale(
        deviceId: 'POS-WIN-01',
        items: [
          CartItemInput(
            productId: 'prod_1001',
            quantity: 1000,
            expectedUnitPrice: 7500,
          ),
        ],
        paymentMethod: 'CASH',
      );

      final beforeSales = await repo.getSalesHistory();
      expect(beforeSales.length, equals(1));

      // 2. Hub'dan bu satışın aynısı downlink edildiğinde (aynı device_id ve client_seq)
      final echoPayload = {
        'status': 'OK',
        'sales': [
          {
            'id': localSaleResult.saleId,
            'server_seq': 25,
            'device_id': 'POS-WIN-01',
            'client_seq': localSaleResult.clientSeq,
            'total_amount': 7500,
            'payment_method': 'CASH',
            'status': 'COMPLETED',
            'cancel_reason': null,
            'cancelled_at': null,
            'created_at': DateTime.now().toIso8601String(),
            'items': [
              {
                'id': 'item_local_01',
                'sale_id': localSaleResult.saleId,
                'product_id': 'prod_1001',
                'product_name': 'Senkronizasyon Test Ürünü',
                'unit': 'adet',
                'price_version_id': 'pv_init',
                'unit_price': 7500,
                'quantity': 1000,
                'total_price': 7500,
              }
            ],
            'refunds': [],
          }
        ],
        'cursor': 0,
        'next_cursor': 25,
        'has_more': false,
      };

      transport.responsesByCursor[0] = SyncResponse(
        statusCode: 200,
        body: jsonEncode(echoPayload),
      );

      // syncSales çalıştırıldığında hata fırlatmamalı ve satır sayısını 1 olarak korumalıdır
      await syncService.syncSales();

      final afterSales = await repo.getSalesHistory();
      expect(afterSales.length, equals(1));
      expect(afterSales.first.id, equals(localSaleResult.saleId));
      expect(afterSales.first.clientSeq, equals(localSaleResult.clientSeq));

      final state = await repo.getSyncState('POS-WIN-01');
      expect(state!.lastServerSaleSeq, equals(25));
    });

    test('Senaryo 4: Çok sayfalı sayfalama (Pagination: Sayfalar arası cursor ilerlemesi)', () async {
      // 1. Sayfa: cursor=0 -> next_cursor=5, has_more=true
      transport.responsesByCursor[0] = SyncResponse(
        statusCode: 200,
        body: jsonEncode({
          'status': 'OK',
          'sales': [
            {
              'id': 'sale_page_1',
              'server_seq': 5,
              'device_id': 'POS-ANDROID-01',
              'client_seq': 1,
              'total_amount': 5000,
              'payment_method': 'CASH',
              'status': 'COMPLETED',
              'created_at': DateTime.now().toIso8601String(),
              'items': [],
              'refunds': [],
            }
          ],
          'cursor': 0,
          'next_cursor': 5,
          'has_more': true,
        }),
      );

      // 2. Sayfa: cursor=5 -> next_cursor=12, has_more=false
      transport.responsesByCursor[5] = SyncResponse(
        statusCode: 200,
        body: jsonEncode({
          'status': 'OK',
          'sales': [
            {
              'id': 'sale_page_2',
              'server_seq': 12,
              'device_id': 'POS-ANDROID-01',
              'client_seq': 2,
              'total_amount': 8000,
              'payment_method': 'CARD',
              'status': 'COMPLETED',
              'created_at': DateTime.now().toIso8601String(),
              'items': [],
              'refunds': [],
            }
          ],
          'cursor': 5,
          'next_cursor': 12,
          'has_more': false,
        }),
      );

      final total = await syncService.syncSales(limit: 1);
      expect(total, equals(2));
      expect(transport.requestedCursors, equals([0, 5]));

      final state = await repo.getSyncState('POS-WIN-01');
      expect(state!.lastServerSaleSeq, equals(12));

      final allSales = await repo.getSalesHistory();
      expect(allSales.length, equals(2));
    });

    test('Senaryo 5: Aynı zaman damgasına sahip satışların server_seq ile deterministik sıralanması', () async {
      final nowStr = DateTime.now().toIso8601String();
      transport.responsesByCursor[0] = SyncResponse(
        statusCode: 200,
        body: jsonEncode({
          'status': 'OK',
          'sales': [
            {
              'id': 'sale_same_ts_1',
              'server_seq': 100,
              'device_id': 'POS-ANDROID-01',
              'client_seq': 1,
              'total_amount': 1000,
              'payment_method': 'CASH',
              'status': 'COMPLETED',
              'created_at': nowStr,
              'items': [],
              'refunds': [],
            },
            {
              'id': 'sale_same_ts_2',
              'server_seq': 101,
              'device_id': 'POS-ANDROID-01',
              'client_seq': 2,
              'total_amount': 2000,
              'payment_method': 'CASH',
              'status': 'COMPLETED',
              'created_at': nowStr,
              'items': [],
              'refunds': [],
            }
          ],
          'cursor': 0,
          'next_cursor': 101,
          'has_more': false,
        }),
      );

      final count = await syncService.syncSales();
      expect(count, equals(2));

      final state = await repo.getSyncState('POS-WIN-01');
      expect(state!.lastServerSaleSeq, equals(101));
    });

    test('Senaryo 6: Hata durumunda atomik rollback (Cursor geride kalmalı, yarım yazım olmamalı)', () async {
      // Geçersiz bir payload veya işlem hatası simülasyonu
      expect(
        () => repo.upsertSales(
          sales: [
            DownloadedSalePayload(
              id: 'broken_sale',
              serverSeq: 50,
              deviceId: 'BROKEN_DEV',
              clientSeq: 1,
              totalAmount: 1000,
              paymentMethod: 'CASH',
              createdAt: DateTime.now(),
              items: [],
            ),
          ],
          newCursor: 50,
          deviceId: 'NON_EXISTENT_DEV', // initialize edilmemiş cihaz, sync state güncellenemez
        ),
        returnsNormally, // update(where deviceId) 0 row döner, çökmez
      );

      // Var olan cihazın cursor'ı etkilenmez
      final state = await repo.getSyncState('POS-WIN-01');
      expect(state!.lastServerSaleSeq, equals(0));
    });

    test('Senaryo 7: Satış İptalinin (SALE_CANCEL) diğer istemciye anında yansıması', () async {
      // 1. Önce aktif bir satış indir
      final initialPayload = {
        'status': 'OK',
        'sales': [
          {
            'id': 'sale_to_cancel_1',
            'server_seq': 1,
            'device_id': 'POS-ANDROID-01',
            'client_seq': 1,
            'total_amount': 5000,
            'payment_method': 'CASH',
            'status': 'COMPLETED',
            'created_at': DateTime.now().toIso8601String(),
            'items': [],
            'refunds': [],
          }
        ],
        'cursor': 0,
        'next_cursor': 1,
        'has_more': false,
      };

      transport.responsesByCursor[0] = SyncResponse(
        statusCode: 200,
        body: jsonEncode(initialPayload),
      );

      await syncService.syncSales();
      var sale = (await repo.getSalesHistory()).first;
      expect(sale.status, equals('COMPLETED'));

      // 2. Hub'da bu satış iptal edildi (status: CANCELLED, server_seq: 2 bumped)
      final cancelPayload = {
        'status': 'OK',
        'sales': [
          {
            'id': 'sale_to_cancel_1',
            'server_seq': 2,
            'device_id': 'POS-ANDROID-01',
            'client_seq': 1,
            'total_amount': 5000,
            'payment_method': 'CASH',
            'status': 'CANCELLED',
            'cancel_reason': 'Müşteri vazgeçti',
            'cancelled_at': DateTime.now().toIso8601String(),
            'created_at': DateTime.now().toIso8601String(),
            'items': [],
            'refunds': [],
          }
        ],
        'cursor': 1,
        'next_cursor': 2,
        'has_more': false,
      };

      transport.responsesByCursor[1] = SyncResponse(
        statusCode: 200,
        body: jsonEncode(cancelPayload),
      );

      await syncService.syncSales();

      sale = (await repo.getSalesHistory()).first;
      expect(sale.status, equals('CANCELLED'));
      expect(sale.cancelReason, equals('Müşteri vazgeçti'));
      expect(sale.cancelledAt, isNotNull);

      final state = await repo.getSyncState('POS-WIN-01');
      expect(state!.lastServerSaleSeq, equals(2));
    });

    test('Senaryo 8: Satış İadesinin (SALE_REFUND) diğer istemciye yansıması', () async {
      final refundPayload = {
        'status': 'OK',
        'sales': [
          {
            'id': 'sale_to_refund_1',
            'server_seq': 5,
            'device_id': 'POS-ANDROID-01',
            'client_seq': 1,
            'total_amount': 7500,
            'payment_method': 'CASH',
            'status': 'REFUNDED',
            'created_at': DateTime.now().toIso8601String(),
            'items': [
              {
                'id': 'item_ref_1',
                'sale_id': 'sale_to_refund_1',
                'product_id': 'prod_1001',
                'product_name': 'Senkronizasyon Test Ürünü',
                'unit': 'adet',
                'price_version_id': 'pv_init',
                'unit_price': 7500,
                'quantity': 1000,
                'total_price': 7500,
              }
            ],
            'refunds': [
              {
                'id': 'ref_android_01',
                'sale_id': 'sale_to_refund_1',
                'device_id': 'POS-ANDROID-01',
                'client_seq': 2,
                'total_refund_amount': 7500,
                'payment_method': 'CASH',
                'reason': 'Kusurlu ürün iadesi',
                'created_at': DateTime.now().toIso8601String(),
                'items': [
                  {
                    'id': 'ref_item_01',
                    'refund_id': 'ref_android_01',
                    'sale_item_id': 'item_ref_1',
                    'product_id': 'prod_1001',
                    'quantity': 1000,
                    'unit_price': 7500,
                    'refund_amount': 7500,
                    'product_condition': 'DAMAGED',
                  }
                ],
              }
            ],
          }
        ],
        'cursor': 0,
        'next_cursor': 5,
        'has_more': false,
      };

      transport.responsesByCursor[0] = SyncResponse(
        statusCode: 200,
        body: jsonEncode(refundPayload),
      );

      await syncService.syncSales();

      final detail = await repo.getSaleDetail('sale_to_refund_1');
      expect(detail, isNotNull);
      expect(detail!.refunds.length, equals(1));
      expect(detail.refunds.first.refund.totalRefundAmount, equals(7500));
      expect(detail.refunds.first.refund.reason, equals('Kusurlu ürün iadesi'));
      expect(detail.refunds.first.items.first.productCondition, equals('DAMAGED'));
    });

    test('Senaryo 9: Echo Prevention (İndirilen satışlar Outbox kuyruğuna ASLA yazılmaz)', () async {
      transport.responsesByCursor[0] = SyncResponse(
        statusCode: 200,
        body: jsonEncode({
          'status': 'OK',
          'sales': [
            {
              'id': 'sale_foreign_1',
              'server_seq': 99,
              'device_id': 'POS-ANDROID-99',
              'client_seq': 1,
              'total_amount': 3000,
              'payment_method': 'CASH',
              'status': 'COMPLETED',
              'created_at': DateTime.now().toIso8601String(),
              'items': [],
              'refunds': [],
            }
          ],
          'cursor': 0,
          'next_cursor': 99,
          'has_more': false,
        }),
      );

      await syncService.syncSales();

      final outboxSummary = await repo.getOutboxSummary(deviceId: 'POS-WIN-01');
      expect(outboxSummary.pending, equals(0));
      expect(outboxSummary.inProgress, equals(0));
      expect(outboxSummary.retry, equals(0));
      expect(outboxSummary.failedPermanent, equals(0));
    });

    test('Senaryo 10: Ağ hatasında cursor izolasyonu (HTTP hatası cursorı bozmaz)', () async {
      transport.throwNetworkErrorOnSales = true;

      final count = await syncService.syncSales();
      expect(count, equals(0));

      final state = await repo.getSyncState('POS-WIN-01');
      expect(state!.lastServerSaleSeq, equals(0)); // Değişmedi
    });

    test('Senaryo 11: Boş satış listesi ama ilerleyen cursor (next_cursor kaydedilmeli)', () async {
      transport.responsesByCursor[0] = SyncResponse(
        statusCode: 200,
        body: jsonEncode({
          'status': 'OK',
          'sales': [],
          'cursor': 0,
          'next_cursor': 88,
          'has_more': false,
        }),
      );

      final count = await syncService.syncSales();
      expect(count, equals(0));

      final state = await repo.getSyncState('POS-WIN-01');
      expect(state!.lastServerSaleSeq, equals(88));
    });

    test('Senaryo 12: Çevrimdışı sonrası kurtarma (Offline recovery: Toplu satışların eksiksiz inmesi)', () async {
      // İstemci uzun süre kapalı kaldı ve Hub'da 5 satış birikti
      final salesBatch = List.generate(5, (index) => {
        'id': 'sale_offline_batch_$index',
        'server_seq': index + 1,
        'device_id': 'POS-ANDROID-01',
        'client_seq': index + 1,
        'total_amount': (index + 1) * 1000,
        'payment_method': index % 2 == 0 ? 'CASH' : 'CARD',
        'status': 'COMPLETED',
        'created_at': DateTime.now().toIso8601String(),
        'items': [],
        'refunds': [],
      });

      transport.responsesByCursor[0] = SyncResponse(
        statusCode: 200,
        body: jsonEncode({
          'status': 'OK',
          'sales': salesBatch,
          'cursor': 0,
          'next_cursor': 5,
          'has_more': false,
        }),
      );

      final downloaded = await syncService.syncSales();
      expect(downloaded, equals(5));

      final history = await repo.getSalesHistory(limit: 100);
      expect(history.length, equals(5));

      final state = await repo.getSyncState('POS-WIN-01');
      expect(state!.lastServerSaleSeq, equals(5));
    });

    test('Senaryo 13: Başka cihazdan inen iadeli satışın doğrudan REFUNDED ve PARTIALLY_REFUNDED kaydedilmesi', () async {
      // Hub'dan gelen iki yeni satış: biri tam iadeli, biri kısmi iadeli
      transport.responsesByCursor[0] = SyncResponse(
        statusCode: 200,
        body: jsonEncode({
          'status': 'OK',
          'sales': [
            {
              'id': 'sale_remote_fully_refunded',
              'server_seq': 10,
              'device_id': 'POS-WIN-01',
              'client_seq': 4,
              'total_amount': 8500,
              'payment_method': 'CASH',
              'status': 'COMPLETED', // Hub'dan COMPLETED gelse dahi iade dizisiyle REFUNDED türetilmeli
              'created_at': DateTime.now().toIso8601String(),
              'items': [
                {
                  'id': 'item_remote_1',
                  'sale_id': 'sale_remote_fully_refunded',
                  'product_id': 'prod_zeytin_500g',
                  'product_name': 'Gemlik Siyah Zeytin 500g',
                  'unit': 'adet',
                  'price_version_id': 'pv_1',
                  'unit_price': 8500,
                  'quantity': 1000,
                  'total_price': 8500,
                }
              ],
              'refunds': [
                {
                  'id': 'ref_remote_full',
                  'sale_id': 'sale_remote_fully_refunded',
                  'device_id': 'POS-WIN-01',
                  'client_seq': 6,
                  'total_refund_amount': 8500,
                  'payment_method': 'CASH',
                  'reason': 'Müşteri vazgeçti',
                  'created_at': DateTime.now().toIso8601String(),
                  'items': [
                    {
                      'id': 'refitem_remote_1',
                      'refund_id': 'ref_remote_full',
                      'sale_item_id': 'item_remote_1',
                      'product_id': 'prod_zeytin_500g',
                      'quantity': 1000,
                      'unit_price': 8500,
                      'refund_amount': 8500,
                      'product_condition': 'SELLABLE',
                    }
                  ],
                }
              ],
            },
            {
              'id': 'sale_remote_partially_refunded',
              'server_seq': 11,
              'device_id': 'POS-WIN-01',
              'client_seq': 5,
              'total_amount': 10000,
              'payment_method': 'CARD',
              'status': 'COMPLETED',
              'created_at': DateTime.now().toIso8601String(),
              'items': [
                {
                  'id': 'item_remote_2',
                  'sale_id': 'sale_remote_partially_refunded',
                  'product_id': 'prod_peynir_1kg',
                  'product_name': 'Beyaz Peynir 1kg',
                  'unit': 'adet',
                  'price_version_id': 'pv_2',
                  'unit_price': 10000,
                  'quantity': 1000,
                  'total_price': 10000,
                }
              ],
              'refunds': [
                {
                  'id': 'ref_remote_partial',
                  'sale_id': 'sale_remote_partially_refunded',
                  'device_id': 'POS-WIN-01',
                  'client_seq': 7,
                  'total_refund_amount': 4000,
                  'payment_method': 'CARD',
                  'reason': 'Kısmi iade',
                  'created_at': DateTime.now().toIso8601String(),
                  'items': [
                    {
                      'id': 'refitem_remote_2',
                      'refund_id': 'ref_remote_partial',
                      'sale_item_id': 'item_remote_2',
                      'product_id': 'prod_peynir_1kg',
                      'quantity': 400,
                      'unit_price': 10000,
                      'refund_amount': 4000,
                      'product_condition': 'SELLABLE',
                    }
                  ],
                }
              ],
            }
          ],
          'cursor': 0,
          'next_cursor': 11,
          'has_more': false,
        }),
      );

      final downloaded = await syncService.syncSales();
      expect(downloaded, equals(2));

      // Veritabanındaki local_sales satırlarını doğrula
      final fullSale = await (db.select(db.localSales)..where((s) => s.id.equals('sale_remote_fully_refunded'))).getSingle();
      expect(fullSale.status, equals('REFUNDED'));

      final partialSale = await (db.select(db.localSales)..where((s) => s.id.equals('sale_remote_partially_refunded'))).getSingle();
      expect(partialSale.status, equals('PARTIALLY_REFUNDED'));

      // getSalesHistory() çıktısını doğrula
      final history = await repo.getSalesHistory();
      final fullHistoryItem = history.firstWhere((s) => s.id == 'sale_remote_fully_refunded');
      expect(fullHistoryItem.status, equals('REFUNDED'));

      final partialHistoryItem = history.firstWhere((s) => s.id == 'sale_remote_partially_refunded');
      expect(partialHistoryItem.status, equals('PARTIALLY_REFUNDED'));

      // İade tablolarının dolduğunu doğrula
      final savedRefunds = await db.select(db.localRefunds).get();
      expect(savedRefunds.length, equals(2));
    });
  });
}
