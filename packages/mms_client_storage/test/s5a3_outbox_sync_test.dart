import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

/// Testler için senaryo simülasyonu yapabilen kontrollü transport
class MockSyncTransport implements SyncTransport {
  final List<Map<String, dynamic>> recordedCalls = [];
  final Map<int, SyncResponse> scriptedResponses = {};
  SyncResponse? defaultResponse;
  bool shouldThrowSocketException = false;
  int callCount = 0;

  @override
  Future<SyncResponse> postSale({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    callCount++;
    final body = jsonDecode(payload) as Map<String, dynamic>;
    final clientSeq = body['client_seq'] as int;

    recordedCalls.add({
      'hubUrl': hubUrl,
      'token': token,
      'payload': body,
      'clientSeq': clientSeq,
    });

    if (shouldThrowSocketException) {
      return SyncResponse.networkError('Ağ kesintisi: Bağlantı koptu.');
    }

    if (scriptedResponses.containsKey(clientSeq)) {
      return scriptedResponses[clientSeq]!;
    }

    if (defaultResponse != null) {
      return defaultResponse!;
    }

    // Varsayılan başarılı yanıt (201 Created)
    return SyncResponse(
      statusCode: 201,
      body: jsonEncode({
        'status': 'COMMITTED',
        'client_seq': clientSeq,
        'committed_at': DateTime.now().toIso8601String(),
      }),
    );
  }

  String? nextSyncSessionId = 'sync_sess_test_1001';

  @override
  Future<SyncResponse> getProducts({
    required String hubUrl,
    required String token,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return SyncResponse(
      statusCode: 200,
      body: jsonEncode({
        'status': 'OK',
        if (nextSyncSessionId != null) 'sync_session_id': nextSyncSessionId,
        'products': [
          {
            'id': 'prod_online_1',
            'barcode': '8699999',
            'name': 'Online Senkronize Ürün',
            'price': 4200,
            'stock': 100000,
            'stock_unit': 'adet',
            'pricing_unit': 'adet',
            'vat_rate': 20,
            'is_active': true,
            'barcodes': ['8699999', '86999998888'],
          }
        ],
      }),
    );
  }

  final List<String> acknowledgedSyncSessions = [];
  bool failNextSyncAck = false;

  @override
  Future<SyncResponse> postSyncAck({
    required String hubUrl,
    required String token,
    required String syncSessionId,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (failNextSyncAck) {
      return SyncResponse.networkError('Sync ACK ağ hatası simülasyonu');
    }
    acknowledgedSyncSessions.add(syncSessionId);
    return SyncResponse(
      statusCode: 200,
      body: jsonEncode({
        'status': 'ACKNOWLEDGED',
        'sync_session_id': syncSessionId,
      }),
    );
  }

  @override
  void close() {}
}

void main() {
  late Directory tempDir;
  late File dbFile;
  late ClientDatabase db;
  late ClientStorageRepository repo;
  late MockSyncTransport transport;
  late ClientSyncService syncService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mms_outbox_sync_test_');
    dbFile = File(p.join(tempDir.path, 'client_local.db'));
    db = ClientDatabase(dbFile);
    repo = ClientStorageRepository(db);
    transport = MockSyncTransport();

    syncService = ClientSyncService(
      repository: repo,
      transport: transport,
      deviceId: 'DEV_WIN1',
      deviceToken: 'TOKEN_VALID_SECRET_123',
      hubUrl: 'https://127.0.0.1:8443',
      baseBackoff: const Duration(milliseconds: 100),
      maxBackoff: const Duration(seconds: 2),
    );

    // Test ürününü ekle (Fiyat: 10.00 TL = 1000 kuruş, Stok: 100 adet = 100000 milli-birim)
    await repo.upsertProducts([
      LocalProductsCompanion(
        id: const Value('prod_1'),
        barcode: const Value('8690001'),
        name: const Value('Test Ürün'),
        price: const Value(1000),
        stock: const Value(100000),
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

  group('Aşama S-5A-3: Outbox Senkronizasyon Motoru ve Hata Senaryoları', () {
    test('5. Servis yeniden erişilebilir olduğunda Outbox kayıtlarının başarıyla gönderilmesi ve SYNCED olması', () async {
      // 1. İstemci çevrimdışıyken 2 satış oluşturur (1 adet ve 2 adet)
      await repo.createOfflineSale(
        deviceId: 'DEV_WIN1',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_1', 1)], // 1000 kuruş
      );
      await repo.createOfflineSale(
        deviceId: 'DEV_WIN1',
        paymentMethod: 'CREDIT_CARD',
        items: [CartItemInput.units('prod_1', 2)], // 2000 kuruş
      );

      // İki operasyon da PENDING durumda
      var unsynced = await repo.getUnsyncedOutboxOperations('DEV_WIN1');
      expect(unsynced.length, equals(2));

      // 2. Senkronizasyon motorunu çalıştır
      final result = await syncService.syncPendingOutbox();

      expect(result.syncedCount, equals(2));
      expect(result.retriedCount, equals(0));
      expect(result.permanentFailedCount, equals(0));
      expect(result.hasMore, isFalse);

      // 3. Veritabanındaki Outbox kayıtlarının SYNCED olduğunu ve acknowledgedAt set edildiğini doğrula
      final allOutbox = await db.select(db.outboxOperations).get();
      for (final op in allOutbox) {
        expect(op.status, equals('SYNCED'));
        expect(op.acknowledgedAt, isNotNull);
        expect(op.lastError, isNull);
      }

      // 4. ClientSyncState tablosundaki lastSyncedSeq değerinin 2 olduğunu doğrula
      final state = await repo.getSyncState('DEV_WIN1');
      expect(state!.lastSyncedSeq, equals(2));
    });

    test('6. ACK kaybı sonrası aynı payload ile tekrar gönderimde Idempotent Replay başarılı ACK sayılmalıdır', () async {
      // Satış oluştur
      final sale = await repo.createOfflineSale(
        deviceId: 'DEV_WIN1',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_1', 1)],
      );

      // Sunucu 200 OK ve x-mms-idempotent-replay başlığı dönüyor simülasyonu
      transport.scriptedResponses[sale.clientSeq] = SyncResponse(
        statusCode: 200,
        headers: {'x-mms-idempotent-replay': 'true', 'content-type': 'application/json'},
        body: jsonEncode({
          'status': 'COMMITTED',
          'sale_id': 'sale_cached_123',
          'client_seq': sale.clientSeq,
          'total_amount': 1000,
        }),
      );

      final result = await syncService.syncPendingOutbox();

      expect(result.syncedCount, equals(1));
      expect(result.isCleanSuccess, isTrue);

      final op = await (db.select(db.outboxOperations)..where((o) => o.operationId.equals(sale.operationId))).getSingle();
      expect(op.status, equals('SYNCED'));
      expect(op.acknowledgedAt, isNotNull);
    });

    test('8. Birden fazla Outbox kaydının sıra (client_seq ASC) korunarak gönderilmesi ve hata anında sıra kilitlenmesi', () async {
      // 3 ardışık satış oluştur: seq 1, seq 2, seq 3
      for (var i = 1; i <= 3; i++) {
        await repo.createOfflineSale(
          deviceId: 'DEV_WIN1',
          paymentMethod: 'CASH',
          items: [CartItemInput.units('prod_1', 1)],
        );
      }

      // seq 1 için geçici HTTP 503 Service Draining hatası simüle et
      transport.scriptedResponses[1] = const SyncResponse(
        statusCode: 503,
        body: '{"error":"SERVICE_DRAINING"}',
      );

      // Senkronizasyonu başlat
      final result = await syncService.syncPendingOutbox();

      expect(result.syncedCount, equals(0));
      expect(result.retriedCount, equals(1));
      expect(transport.callCount, equals(1)); // Yalnızca seq 1 denendi! Seq 2 veya 3 asla çağrılmadı!

      // seq 1 RETRY durumuna geçti
      final op1 = await (db.select(db.outboxOperations)..where((o) => o.clientSeq.equals(1))).getSingle();
      expect(op1.status, equals('RETRY'));
      expect(op1.attemptCount, equals(1));
      expect(op1.nextRetryAt, isNotNull);

      // seq 2 ve seq 3 PENDING olarak kaldı (Sıra atlanmadı!)
      final op2 = await (db.select(db.outboxOperations)..where((o) => o.clientSeq.equals(2))).getSingle();
      final op3 = await (db.select(db.outboxOperations)..where((o) => o.clientSeq.equals(3))).getSingle();
      expect(op2.status, equals('PENDING'));
      expect(op3.status, equals('PENDING'));

      // Şimdi seq 1 hatasını düzelt (sunucu tekrar açıldı)
      transport.scriptedResponses.remove(1);

      // Bekleme süresi sonrasında (simüle zaman) tekrar senkronize et
      final futureTime = DateTime.now().add(const Duration(seconds: 5));
      final secondSync = await syncService.syncPendingOutbox(now: futureTime);

      expect(secondSync.syncedCount, equals(3)); // 1, 2, 3 sırayla gönderildi
      expect(secondSync.hasMore, isFalse);

      // Sıranın [1, 2, 3] olarak gönderildiğini doğrula
      final sentSeqs = transport.recordedCalls.map((c) => c['clientSeq'] as int).toList();
      expect(sentSeqs, equals([1, 1, 2, 3])); // İlk deneme seq 1, sonra 1, 2, 3
    });

    test('11 & Outbox Recovery: Kalıcı hata (FAILED_PERMANENT), kuyruk kilitlemesi, hata incelemesi ve düzeltme sonrası kurtarma', () async {
      // Seq 1 (Geçerli) ve Seq 2 (Bozuk/Uyuşmaz) oluştur
      await repo.createOfflineSale(
        deviceId: 'DEV_WIN1',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_1', 1)],
      );
      final sale2 = await repo.createOfflineSale(
        deviceId: 'DEV_WIN1',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_1', 2)],
      );

      // Seq 1 başarılı olsun, Seq 2 için 409 Payload Mismatch dönsün
      transport.scriptedResponses[sale2.clientSeq] = const SyncResponse(
        statusCode: 409,
        body: '{"error":"CONFLICT","code":"ERR_IDEMPOTENCY_PAYLOAD_MISMATCH"}',
      );

      // 1. Senkronizasyon çalıştır
      final result1 = await syncService.syncPendingOutbox();
      expect(result1.syncedCount, equals(1)); // Seq 1 başarılı
      expect(result1.permanentFailedCount, equals(1)); // Seq 2 kalıcı hata aldı

      // 2. Seq 2'nin FAILED_PERMANENT durumuna geçtiğini ve hatasının incelenebildiğini doğrula
      final failedOps = await repo.getFailedPermanentOperations('DEV_WIN1');
      expect(failedOps.length, equals(1));
      expect(failedOps.first.operationId, equals(sale2.operationId));
      expect(failedOps.first.lastError, contains('ERR_IDEMPOTENCY_PAYLOAD_MISMATCH'));

      // 3. Kuyruk kilitlemesi kontrolü: Yeni bir Seq 3 satışı ekle
      final sale3 = await repo.createOfflineSale(
        deviceId: 'DEV_WIN1',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_1', 1)],
      );

      // Tekrar senkronizasyon çalıştır: Seq 2 FAILED_PERMANENT olduğu için Seq 3 ASLA gönderilmemeli, kuyruk durmalı
      final result2 = await syncService.syncPendingOutbox();
      expect(result2.syncedCount, equals(0));
      expect(result2.permanentFailedCount, equals(1));
      expect(result2.lastError, contains('kuyruk durduruldu'));

      final op3 = await (db.select(db.outboxOperations)..where((o) => o.operationId.equals(sale3.operationId))).getSingle();
      expect(op3.status, equals('PENDING')); // Seq 3 gönderilmedi, bekliyor

      // 4. Hata Kurtarma: Kalıcı hata incelendi ve düzeltildi (ör. sunucu sorunu giderildi veya işlem PENDING'e alındı)
      transport.scriptedResponses.remove(sale2.clientSeq); // Hata çözüldü
      await repo.retryFailedPermanentOperation(sale2.operationId);

      final op2Recovered = await (db.select(db.outboxOperations)..where((o) => o.operationId.equals(sale2.operationId))).getSingle();
      expect(op2Recovered.status, equals('PENDING'));
      expect(op2Recovered.lastError, isNull);

      // 5. Kuyruğun tekrar akmaya başladığını doğrula: Seq 2 ve Seq 3 sırayla gönderilir
      final result3 = await syncService.syncPendingOutbox();
      expect(result3.syncedCount, equals(2)); // Seq 2 ve Seq 3 gönderildi
      expect(result3.isCleanSuccess, isTrue);

      final state = await repo.getSyncState('DEV_WIN1');
      expect(state!.lastSyncedSeq, equals(3));
    });

    test('Sunucudan ürün listesini çekme ve iki aşamalı ACK ile yerel cache güncelleme (syncProducts)', () async {
      transport.acknowledgedSyncSessions.clear();
      transport.nextSyncSessionId = 'sync_sess_test_1001';

      final count = await syncService.syncProducts();
      expect(count, equals(1));

      final cached = await (db.select(db.localProducts)..where((p) => p.id.equals('prod_online_1'))).getSingleOrNull();
      expect(cached, isNotNull);
      expect(cached!.name, equals('Online Senkronize Ürün'));
      expect(cached.price, equals(4200));
      expect(cached.stockUnit, equals('adet'));
      expect(cached.pricingUnit, equals('adet'));
      expect(cached.isActive, isTrue);

      // İlgili barkodların da local_product_barcodes tablosuna eklendiğini doğrula
      final barcodes = await repo.getBarcodesForProduct('prod_online_1');
      expect(barcodes.length, equals(2));
      expect(barcodes.map((b) => b.barcode).toSet(), containsAll(['8699999', '86999998888']));

      // ACK gönderilmiş ve onaylanmış olmalı
      expect(transport.acknowledgedSyncSessions, contains('sync_sess_test_1001'));

      final state = await repo.getSyncState('DEV_WIN1');
      expect(state!.lastProductSyncAt, isNotNull);
      expect(state.pendingSyncSessionId, isNull);
    });

    test('Product Sync ACK kesintisi: ACK iletimi başarısız olduğunda yerel ürünler korunur ve sonraki döngüde ACK tamamlanır', () async {
      transport.acknowledgedSyncSessions.clear();
      transport.nextSyncSessionId = 'sync_sess_interrupted_999';
      transport.failNextSyncAck = true; // ACK gönderiminde ağ hatası simülasyonu

      // Ürün senkronizasyonu çalıştır (ürünler yerel DB'ye kaydedilir ancak ACK gitmez)
      final count = await syncService.syncProducts();
      expect(count, equals(1));

      // Ürün yerelde başarıyla mevcuttur
      final cached = await (db.select(db.localProducts)..where((p) => p.id.equals('prod_online_1'))).getSingleOrNull();
      expect(cached, isNotNull);

      // Ancak ACK başarısız olduğu için pendingSyncSessionId veritabanında saklanır
      final stateBefore = await repo.getSyncState('DEV_WIN1');
      expect(stateBefore!.pendingSyncSessionId, equals('sync_sess_interrupted_999'));

      // Şimdi ağ düzeldi, senkronizasyon tekrar çalıştığında ACK otomatik olarak gönderilir
      transport.failNextSyncAck = false;
      await syncService.syncPendingOutbox();

      expect(transport.acknowledgedSyncSessions, contains('sync_sess_interrupted_999'));

      final stateAfter = await repo.getSyncState('DEV_WIN1');
      expect(stateAfter!.pendingSyncSessionId, isNull);
    });

    test('Outbox Geçici Hata Ayrımı: HTTP 408 ve HTTP 429 yanıtları RETRY yapılır; FAILED_PERMANENT yapılmaz', () async {
      // Seq 1 (408 Timeout) ve Seq 2 (429 Rate Limit) için iki satış oluştur
      final sale1 = await repo.createOfflineSale(
        deviceId: 'DEV_WIN1',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_1', 1)],
      );
      final sale2 = await repo.createOfflineSale(
        deviceId: 'DEV_WIN1',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_1', 1)],
      );

      // seq 1 için HTTP 408 simüle et
      transport.scriptedResponses[sale1.clientSeq] = const SyncResponse(
        statusCode: 408,
        body: '{"error":"REQUEST_TIMEOUT"}',
      );

      final result1 = await syncService.syncPendingOutbox();
      expect(result1.syncedCount, equals(0));
      expect(result1.retriedCount, equals(1));
      expect(result1.permanentFailedCount, equals(0));

      // seq 1 RETRY durumuna geçti (FAILED_PERMANENT değil!)
      final op1 = await (db.select(db.outboxOperations)..where((o) => o.operationId.equals(sale1.operationId))).getSingle();
      expect(op1.status, equals('RETRY'));
      expect(op1.attemptCount, equals(1));

      // seq 1'i başarılı yap, seq 2 için HTTP 429 simüle et
      transport.scriptedResponses.remove(sale1.clientSeq);
      transport.scriptedResponses[sale2.clientSeq] = const SyncResponse(
        statusCode: 429,
        body: '{"error":"RATE_LIMITED"}',
      );

      final futureTime = DateTime.now().add(const Duration(seconds: 10));
      final result2 = await syncService.syncPendingOutbox(now: futureTime);
      expect(result2.syncedCount, equals(1)); // seq 1 başarıyla gitti
      expect(result2.retriedCount, equals(1)); // seq 2 RETRY oldu
      expect(result2.permanentFailedCount, equals(0)); // seq 2 ASLA kalıcı hata olmadı

      final op2 = await (db.select(db.outboxOperations)..where((o) => o.operationId.equals(sale2.operationId))).getSingle();
      expect(op2.status, equals('RETRY'));
      expect(op2.attemptCount, equals(1));
    });

    test('Outbox Kalıcı Hata: HTTP 400 Bad Request yanıtı FAILED_PERMANENT olarak işaretlenir', () async {
      final sale = await repo.createOfflineSale(
        deviceId: 'DEV_WIN1',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_1', 1)],
      );

      transport.scriptedResponses[sale.clientSeq] = const SyncResponse(
        statusCode: 400,
        body: '{"error":"BAD_REQUEST","code":"ERR_PRICE_VERSION_EXPIRED_FOR_DEVICE"}',
      );

      final result = await syncService.syncPendingOutbox();
      expect(result.syncedCount, equals(0));
      expect(result.retriedCount, equals(0));
      expect(result.permanentFailedCount, equals(1));

      final op = await (db.select(db.outboxOperations)..where((o) => o.operationId.equals(sale.operationId))).getSingle();
      expect(op.status, equals('FAILED_PERMANENT'));
      expect(op.lastError, contains('ERR_PRICE_VERSION_EXPIRED_FOR_DEVICE'));
    });
  });
}
