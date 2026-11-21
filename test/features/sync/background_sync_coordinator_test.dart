import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/features/sync/application/background_sync_coordinator.dart';
import 'package:market_pos/features/sync/domain/sync_coordinator_state.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

/// Testler için senaryo simülasyonu sağlayan kontrollü SyncTransport
class _TestSyncTransport implements SyncTransport {
  final List<Map<String, dynamic>> recordedCalls = [];
  final Map<int, SyncResponse> scriptedResponses = {};
  SyncResponse? defaultResponse;
  Completer<SyncResponse>? delayCompleter;
  int callCount = 0;
  bool isClosed = false;
  SyncResponse? productsResponse;

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

    if (delayCompleter != null) {
      return delayCompleter!.future;
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

  @override
  Future<SyncResponse> postProductUpsert({
    required String hubUrl,
    required String token,
    required String payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    callCount++;
    final body = jsonDecode(payload) as Map<String, dynamic>;
    final clientSeq = body['client_seq'] as int? ?? 1;

    recordedCalls.add({
      'hubUrl': hubUrl,
      'token': token,
      'payload': body,
      'clientSeq': clientSeq,
      'type': 'PRODUCT_UPSERT',
    });

    if (delayCompleter != null) {
      return delayCompleter!.future;
    }

    if (scriptedResponses.containsKey(clientSeq)) {
      return scriptedResponses[clientSeq]!;
    }

    if (defaultResponse != null) {
      return defaultResponse!;
    }

    return SyncResponse(
      statusCode: 200,
      body: jsonEncode({
        'status': 'COMMITTED',
        'operation_type': 'PRODUCT_UPSERT',
        'client_seq': clientSeq,
      }),
    );
  }

  @override
  Future<SyncResponse> getProducts({
    required String hubUrl,
    required String token,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return productsResponse ??
        SyncResponse(
          statusCode: 200,
          body: jsonEncode({'products': [], 'sync_session_id': 'sync_1'}),
        );
  }

  @override
  Future<SyncResponse> getSales({
    required String hubUrl,
    required String token,
    int cursor = 0,
    int limit = 50,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return SyncResponse(
      statusCode: 200,
      body: jsonEncode({'status': 'OK', 'sales': [], 'next_cursor': cursor, 'has_more': false}),
    );
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
  void close() {
    isClosed = true;
  }
}

/// Ağ çağrısının başlamasını güvenli timeout ile bekleyen yardımcı fonksiyon
Future<void> _waitForTransportCall(
  _TestSyncTransport transport, {
  int targetCount = 1,
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (transport.callCount < targetCount) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(
        'transport.callCount >= $targetCount ($timeout) zaman aşımına uğradı.',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackgroundSyncCoordinator - Windows Arka Plan Senkronizasyon Koordinatörü Testleri', () {
    late LocalDatabaseService localDb;
    late _TestSyncTransport transport;
    const testDeviceId = 'POS-WIN-01';
    const testHubUrl = 'https://127.0.0.1:8443';
    const testValidToken = 'valid_bearer_token_xyz';

    setUp(() async {
      localDb = LocalDatabaseService.forTesting(
        NativeDatabase.memory(
          setup: (rawDb) {
            rawDb.execute('PRAGMA journal_mode = WAL;');
            rawDb.execute('PRAGMA synchronous = FULL;');
            rawDb.execute('PRAGMA busy_timeout = 5000;');
            rawDb.execute('PRAGMA foreign_keys = ON;');
          },
        ),
      );
      transport = _TestSyncTransport();

      // Test ürünleri ekle
      await localDb.repository.upsertProducts([
        LocalProductsCompanion(
          id: const Value('prod_su'),
          barcode: const Value('8690001'),
          name: const Value('Doğal Kaynak Suyu 0.5L'),
          price: const Value(500), // 5.00 TL
          priceVersionId: const Value('pv_1'),
          stock: const Value(10000),
          stockUnit: const Value('adet'),
          pricingUnit: const Value('adet'),
          conversionFactorNumerator: const Value(1),
          conversionFactorDenominator: const Value(1),
          vatRate: const Value(1),
          isActive: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      ]);
    });

    tearDown(() async {
      await localDb.close();
      await LocalDatabaseService.closeActive();
      LocalDatabaseService.resetForTesting();
    });

    test('1. Başlangıç Durumu: Doğru initial state ile başlar ve sayaçlar temizdir', () {
      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => testValidToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
      );

      expect(coordinator.state.status, SyncCoordinatorStatus.idle);
      expect(coordinator.state.isSyncing, isFalse);
      expect(coordinator.state.lastTriggerReason, isNull);
      expect(coordinator.state.lastSyncTime, isNull);
      expect(coordinator.state.lastResult, isNull);
      expect(coordinator.state.errorMessage, isNull);
      expect(coordinator.state.hasPendingTrailingSync, isFalse);

      coordinator.dispose();
    });

    test('2. Auth Token Eksik veya Boş İken: Outbox kayıtlarına KESİNLİKLE DOKUNMAZ ve authRequired döner', () async {
      // 1 satış oluştur
      await localDb.repository.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [
          CartItemInput.units('prod_su', 1),
        ],
      );

      final summaryBefore = await localDb.getOutboxSummary();
      expect(summaryBefore.pending, 1);

      // 2.1: deviceToken = null
      String? currentToken;
      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => currentToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
      );

      final resultNull = await coordinator.triggerSync(
        reason: SyncTriggerReason.startup,
      );

      expect(resultNull, isNull);
      expect(coordinator.state.status, SyncCoordinatorStatus.authRequired);
      expect(coordinator.state.isSyncing, isFalse);
      expect(coordinator.state.lastTriggerReason, SyncTriggerReason.startup);
      expect(coordinator.state.errorMessage, contains('deviceToken'));
      expect(transport.callCount, 0, reason: 'Token yokken Hub API çağrılamaz');

      // Outbox hala PENDING olmalı
      final summaryAfterNull = await localDb.getOutboxSummary();
      expect(summaryAfterNull.pending, 1);
      expect(summaryAfterNull.totalUnsynced, 1);

      // 2.2: deviceToken = whitespace/boş
      currentToken = '   ';
      final resultEmpty = await coordinator.triggerSync(
        reason: SyncTriggerReason.saleCommitted,
      );

      expect(resultEmpty, isNull);
      expect(coordinator.state.status, SyncCoordinatorStatus.authRequired);
      expect(transport.callCount, 0);

      final summaryAfterEmpty = await localDb.getOutboxSummary();
      expect(summaryAfterEmpty.pending, 1);

      coordinator.dispose();
    });

    test('3. Tetikleyici 1: Başarılı Yerel Satış (saleCommitted) senkronizasyonu tetikler ve Outbox SYNCED olur', () async {
      SyncBatchResult? reportedResult;
      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => testValidToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
        onSyncCompleted: (res) {
          reportedResult = res;
        },
      );

      // Satış oluştur
      await localDb.repository.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [
          CartItemInput.units('prod_su', 1),
        ],
      );

      final result = await coordinator.onSaleCommitted();

      expect(result, isNotNull);
      expect(result!.syncedCount, 1);
      expect(result.retriedCount, 0);
      expect(result.permanentFailedCount, 0);
      expect(result.isCleanSuccess, isTrue);

      expect(transport.callCount, 1);
      expect(transport.recordedCalls.first['token'], testValidToken);
      expect(transport.recordedCalls.first['clientSeq'], 1);

      // Veritabanında SYNCED olduğunu doğrula
      final summary = await localDb.getOutboxSummary();
      expect(summary.totalUnsynced, 0);
      expect(summary.pending, 0);

      // Koordinatör durumunu doğrula
      expect(coordinator.state.status, SyncCoordinatorStatus.idle);
      expect(coordinator.state.isSyncing, isFalse);
      expect(coordinator.state.lastTriggerReason, SyncTriggerReason.saleCommitted);
      expect(coordinator.state.lastSyncTime, isNotNull);
      expect(reportedResult, equals(result));

      coordinator.dispose();
    });

    test('3b. Faz 7A: Downlink (ürün snapshot) hatası sessizce yutulmaz, durumda raporlanır ve sonraki başarıda temizlenir', () async {
      transport.productsResponse = const SyncResponse(statusCode: 500, body: 'hub db kilitli');
      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => testValidToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
      );

      await coordinator.triggerSync(reason: SyncTriggerReason.manual);
      expect(coordinator.state.downlinkError, isNotNull);
      expect(coordinator.state.downlinkError, contains('500'));

      transport.productsResponse = null;
      await coordinator.triggerSync(reason: SyncTriggerReason.manual);
      expect(coordinator.state.downlinkError, isNull);

      coordinator.dispose();
    });

    test('4. Tetikleyici 2: Uygulama Başlangıcı (startup) tetiklendiğinde kuyruğu aktarır', () async {
      // Satış hazırla
      await localDb.repository.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CARD',
        items: [
          CartItemInput.units('prod_su', 2),
        ],
      );

      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => testValidToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
      );

      final result = await coordinator.onStartup();

      expect(result?.syncedCount, 1);
      expect(coordinator.state.lastTriggerReason, SyncTriggerReason.startup);
      expect(coordinator.state.status, SyncCoordinatorStatus.idle);

      coordinator.dispose();
    });

    test('5. Tetikleyici 3: Uygulama Arka Plandan Aktif Olduğunda (appResumed) tetiklenir', () async {
      await localDb.repository.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [
          CartItemInput.units('prod_su', 1),
        ],
      );

      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => testValidToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
      );

      final result = await coordinator.onAppResumed();

      expect(result?.syncedCount, 1);
      expect(coordinator.state.lastTriggerReason, SyncTriggerReason.appResumed);

      coordinator.dispose();
    });

    test('6. Tetikleyici 4: 30 Saniyelik Periyodik Sayaç ve Otomatik Tetikleme', () async {
      // 6.1: onPeriodicTimer() doğrudan çağrısı
      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => testValidToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
      );

      final result = await coordinator.onPeriodicTimer();
      expect(result?.syncedCount, 0);
      expect(coordinator.state.lastTriggerReason, SyncTriggerReason.periodic);
      coordinator.dispose();

      // 6.2: Gerçek periyodik sayaç zamanlaması (Deterministik tamamlanma ve yarış durumu korumalı)
      final syncCompletedCompleter = Completer<void>();
      final timedCoordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => testValidToken,
        hubUrl: testHubUrl,
        periodicInterval: const Duration(milliseconds: 30),
        autoStartTimer: true,
        enableLifecycleListener: false,
        onSyncCompleted: (_) {
          if (!syncCompletedCompleter.isCompleted) {
            syncCompletedCompleter.complete();
          }
        },
      );

      // İlk periyodik senkronizasyonun tamamlanmasını deterministik olarak bekle
      await syncCompletedCompleter.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () =>
            throw TimeoutException('Periyodik sayaç 3 saniye içinde tamamlanamadı.'),
      );

      // Senkronizasyon tamamlandığında durumun deterministik olduğunu doğrula (DOĞAL CLEANUP: dispose öncesi)
      expect(timedCoordinator.state.lastTriggerReason, SyncTriggerReason.periodic);
      expect(timedCoordinator.state.isSyncing, isFalse);
      expect(timedCoordinator.state.status, SyncCoordinatorStatus.idle);
      expect(timedCoordinator.state.hasPendingTrailingSync, isFalse);
      expect(timedCoordinator.hasActiveSync, isFalse);
      expect(timedCoordinator.hasTrailingSync, isFalse);

      // İkinci bir periyodik timer tetiklemesiyle yarışmaması için hemen dispose et
      timedCoordinator.dispose();

      // Dispose sonrasında da referansların temiz kaldığını doğrula
      expect(timedCoordinator.hasActiveSync, isFalse);
      expect(timedCoordinator.hasTrailingSync, isFalse);
    });

    test('7. Tetikleyici 5: Yerel Ağ / Bağlantı Kurtarma (connectivityRestored) tetiklenir', () async {
      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => testValidToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
      );

      final result = await coordinator.onConnectivityRestored();

      expect(result?.syncedCount, 0);
      expect(coordinator.state.lastTriggerReason, SyncTriggerReason.connectivityRestored);

      coordinator.dispose();
    });

    test('8. Concurrency ve Future-Tabanlı Single-Flight Coalescing: Eşzamanlı çağrılar tekilleşir ve ardıl 1 sync olarak yürütülür', () async {
      // Bekletici completer ile ilk senkronizasyonu havada asılı tut
      final delayCompleter = Completer<SyncResponse>();
      transport.delayCompleter = delayCompleter;

      // 1 satış ekle
      await localDb.repository.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [
          CartItemInput.units('prod_su', 1),
        ],
      );

      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => testValidToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
      );

      // İlk çağrı başlatılır ve ağda bekler
      final future1 = coordinator.triggerSync(reason: SyncTriggerReason.startup);

      // Event loop'un transport.postSale'e ulaşmasını bekle (DB hazırlığı tamamlanıp ağ çağrısı başladığında)
      await _waitForTransportCall(transport);

      // Koordinatörün aktif senkronizasyon modunda ve ağ çağrısında olduğunu doğrula
      expect(transport.callCount, 1, reason: 'İlk senkronizasyon ağ çağrısına başlamış olmalı');
      expect(coordinator.state.isSyncing, isTrue);
      expect(coordinator.state.status, SyncCoordinatorStatus.syncing);
      expect(coordinator.state.hasPendingTrailingSync, isFalse);

      // İlk çağrı henüz ağda beklerken kasada 2. bir satış tamamlanır ve 2. ile 3. çağrılar gelir
      await localDb.repository.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CARD',
        items: [
          CartItemInput.units('prod_su', 2),
        ],
      );

      final future2 = coordinator.triggerSync(reason: SyncTriggerReason.saleCommitted);
      final future3 = coordinator.triggerSync(reason: SyncTriggerReason.periodic);

      // Eşzamanlı çağrılar coalescing ile birleşti ve trailing bayrağı kalktı
      expect(coordinator.state.hasPendingTrailingSync, isTrue);
      expect(transport.callCount, 1, reason: 'İlk çağrı sürerken yeni ağ çağrısı başlatılmamalı');

      // İlk çağrıyı serbest bırak
      transport.delayCompleter = null; // Trailing için gecikmesiz çalışsın
      delayCompleter.complete(
        SyncResponse(
          statusCode: 201,
          body: jsonEncode({
            'status': 'COMMITTED',
            'client_seq': 1,
            'committed_at': DateTime.now().toIso8601String(),
          }),
        ),
      );

      // Gerçek ClientSyncService.syncPendingOutbox() davranışı doğrulaması:
      // ClientSyncService, döngü içinde (maxBatch=100) veritabanındaki en eski senkronize edilmemiş kaydı iteratif olarak çeker.
      // İlk HTTP çağrısı ağda asılıyken veritabanına eklenen 2. satış (seq 2), ilk batch döngüsünün sonraki iterasyonunda
      // doğrudan yakalanır ve İLK BATCH DÖNGÜSÜ İÇERİSİNDE senkronize edilir (Backlog drain veya trailing'e kalmadan).
      // Bu nedenle future1, her iki satışı (seq 1 ve seq 2) tamamlayarak syncedCount: 2 döner.
      final res1 = await future1;
      expect(res1?.syncedCount, 2);

      // future2 ve future3 ise eşzamanlı coalescing ile birleştirilen ardıl (trailing) senkronizasyon döngüsünü bekler.
      // Trailing sync çalıştığında kuyruk ilk batch tarafından zaten boşaltılmış olduğundan syncedCount: 0 döner ve teyit sağlar.
      final res2 = await future2;
      final res3 = await future3;

      expect(res2, equals(res3), reason: 'Birleşen çağrılar aynı ardıl sonucu almalıdır');
      expect(res2?.syncedCount, 0, reason: 'Ardıl tur tüm kuyruk boşaldığında 0 senkronize döner');
      expect(transport.callCount, 2, reason: 'İki işlem için tam olarak 2 API gönderimi yapılmıştır');

      // Son durumun temiz olduğunu doğrula
      expect(coordinator.state.status, SyncCoordinatorStatus.idle);
      expect(coordinator.state.isSyncing, isFalse);
      expect(coordinator.state.hasPendingTrailingSync, isFalse);

      coordinator.dispose();
    });

    test('9. Katı Deterministik FIFO Sırası Korunur (client_seq ASC)', () async {
      // 3 satış art arda ekle (seq 1, seq 2, seq 3)
      for (var i = 1; i <= 3; i++) {
        await localDb.repository.createOfflineSale(
          deviceId: testDeviceId,
          paymentMethod: 'CASH',
          items: [
            CartItemInput.units('prod_su', i),
          ],
        );
      }

      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => testValidToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
      );

      final result = await coordinator.triggerSync();

      expect(result?.syncedCount, 3);
      expect(transport.callCount, 3);

      // Gönderim sırasını kontrol et: 1 -> 2 -> 3
      expect(transport.recordedCalls[0]['clientSeq'], 1);
      expect(transport.recordedCalls[1]['clientSeq'], 2);
      expect(transport.recordedCalls[2]['clientSeq'], 3);

      final summary = await localDb.getOutboxSummary();
      expect(summary.totalUnsynced, 0);

      coordinator.dispose();
    });

    test('10. FAILED_PERMANENT Durumunda Head-of-Line Blocking: Sonraki client_seq işlemlerine ASLA geçilemez', () async {
      // seq 1 ve seq 2 oluştur
      final sale1 = await localDb.repository.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [
          CartItemInput.units('prod_su', 1),
        ],
      );

      await localDb.repository.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [
          CartItemInput.units('prod_su', 2),
        ],
      );

      // seq 1'i kalıcı hata durumuna sok
      await localDb.repository.markOutboxPermanentFail(
        sale1.operationId,
        error: 'Şema uyuşmazlığı: Geçersiz barkod formatı (400)',
      );

      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => testValidToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
      );

      final result = await coordinator.triggerSync();

      expect(result?.permanentFailedCount, 1);
      expect(transport.callCount, 0, reason: 'Kalıcı hata baştayken hiçbir işlem gönderilmemeli');
      expect(coordinator.state.status, SyncCoordinatorStatus.permanentError);
      expect(coordinator.state.errorMessage, contains('FAILED_PERMANENT'));

      final summary = await localDb.getOutboxSummary();
      expect(summary.failedPermanent, 1);
      expect(summary.pending, 1, reason: 'seq 2 beklemeye devam etmelidir');

      coordinator.dispose();
    });

    test('11. Geçici Ağ Hatasında RETRY ve Hub ACK Olmadan SYNCED Yapılmaması', () async {
      // 503 Service Unavailable dönecek şekilde ayarla
      transport.defaultResponse = SyncResponse(
        statusCode: 503,
        body: jsonEncode({'error': 'Server maintenance / Draining'}),
      );

      await localDb.repository.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [
          CartItemInput.units('prod_su', 1),
        ],
      );

      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => testValidToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
      );

      final result = await coordinator.triggerSync();

      expect(result?.syncedCount, 0);
      expect(result?.retriedCount, 1);
      expect(coordinator.state.status, SyncCoordinatorStatus.networkError);

      // İşlemin SYNCED OLMADIĞINI, RETRY olduğunu doğrula
      final summary = await localDb.getOutboxSummary();
      expect(summary.retry, 1);
      expect(summary.totalUnsynced, 1);

      coordinator.dispose();
    });

    test('12. Kaynak Tahliyesi: dispose() sayacı ve dinleyicileri temizler, bellek sızıntısı yapmaz', () {
      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => testValidToken,
        hubUrl: testHubUrl,
        periodicInterval: const Duration(seconds: 30),
        autoStartTimer: true,
        enableLifecycleListener: true,
      );

      expect(() => coordinator.dispose(), returnsNormally);
      expect(coordinator.triggerSync(), completion(isNull));
    });

    test('13. Code Review 1: Sync service factory exception güvenliği (try-catch & Future tamamlama)', () async {
      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => testValidToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
        syncServiceFactory: ({
          required repository,
          required transport,
          required deviceId,
          required deviceToken,
          required hubUrl,
          readDeviceToken,
        }) {
          throw StateError('Simüle edilmiş factory çökmesi');
        },
      );

      final result = await coordinator.triggerSync();

      expect(result, isNull);
      expect(coordinator.state.status, SyncCoordinatorStatus.error);
      expect(coordinator.state.isSyncing, isFalse);
      expect(coordinator.state.errorMessage, contains('Simüle edilmiş factory çökmesi'));

      coordinator.dispose();
    });

    test('14. Code Review 2: Factory parametre/yapılandırma exception güvenliği (ArgumentError try-catch koruması)', () async {
      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => testValidToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
        syncServiceFactory: ({
          required repository,
          required transport,
          required deviceId,
          required deviceToken,
          required hubUrl,
          readDeviceToken,
        }) {
          throw ArgumentError('Geçersiz sunucu URL formatı');
        },
      );

      final result = await coordinator.triggerSync();

      expect(result, isNull);
      expect(coordinator.state.status, SyncCoordinatorStatus.error);
      expect(coordinator.state.isSyncing, isFalse);
      expect(coordinator.state.errorMessage, contains('Geçersiz sunucu URL formatı'));

      coordinator.dispose();
    });

    test('15. Code Review 3: Hata sonrasında yeni sync tetiklenebilmesi garanti edilir', () async {
      var shouldThrow = true;
      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => testValidToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
        syncServiceFactory: ({
          required repository,
          required transport,
          required deviceId,
          required deviceToken,
          required hubUrl,
          readDeviceToken,
        }) {
          if (shouldThrow) {
            throw StateError('Geçici servis oluşturma hatası');
          }
          return ClientSyncService(
            repository: repository,
            transport: transport,
            deviceId: deviceId,
            deviceToken: deviceToken,
            readDeviceToken: readDeviceToken,
            hubUrl: hubUrl,
          );
        },
      );

      // İlk çağrı hata alır
      final firstResult = await coordinator.triggerSync();
      expect(firstResult, isNull);
      expect(coordinator.state.status, SyncCoordinatorStatus.error);
      expect(coordinator.state.isSyncing, isFalse);

      // Hata giderildiğinde ikinci çağrı güvenle çalışmalıdır
      shouldThrow = false;
      final secondResult = await coordinator.triggerSync();
      expect(secondResult, isNotNull);
      expect(coordinator.state.status, SyncCoordinatorStatus.idle);
      expect(coordinator.state.isSyncing, isFalse);

      coordinator.dispose();
    });

    test('16. Code Review 4: Aktif sync sırasında token kaybı tutarlılığı ve yetkisiz outbox dokunulmazlığı', () async {
      final delayCompleter = Completer<SyncResponse>();
      transport.delayCompleter = delayCompleter;

      // 1 satış oluştur
      await localDb.repository.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [
          CartItemInput.units('prod_su', 1),
        ],
      );

      String? currentToken = testValidToken;
      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => currentToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
      );

      // İlk sync başlar ve ağ çağrısında bekler
      final future1 = coordinator.triggerSync(reason: SyncTriggerReason.startup);

      await _waitForTransportCall(transport);

      expect(coordinator.state.isSyncing, isTrue);

      // Aktif sync havadayken token kaybolur (örn: oturum kapandı)
      currentToken = null;

      // Bu sırada yeni bir trigger gelir
      final future2 = coordinator.triggerSync(reason: SyncTriggerReason.saleCommitted);

      // ÖNEMLİ: Aktif sync hala havada olduğundan isSyncing: true korunmalıdır!
      expect(coordinator.state.isSyncing, isTrue);
      expect(coordinator.state.status, SyncCoordinatorStatus.authRequired);

      // future2 token olmadığı için hemen null ile tamamlanır
      final res2 = await future2;
      expect(res2, isNull);

      // İlk çağrıyı serbest bırak
      transport.delayCompleter = null;
      delayCompleter.complete(
        SyncResponse(
          statusCode: 201,
          body: jsonEncode({
            'status': 'COMMITTED',
            'client_seq': 1,
            'committed_at': DateTime.now().toIso8601String(),
          }),
        ),
      );

      final res1 = await future1;
      expect(res1?.syncedCount, 1);

      // İlk işlem bittikten sonra token olmadığı için ardıl işlem çalışmaz
      // ve coordinator temizce isSyncing: false, status: authRequired durumuna geçer
      expect(coordinator.state.isSyncing, isFalse);
      expect(coordinator.state.status, SyncCoordinatorStatus.authRequired);

      coordinator.dispose();
    });

    test('17. Code Review 5: Callback izolasyonu (onSyncCompleted exception ve asenkron gecikme kilit yapmaz)', () async {
      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => testValidToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
        onSyncCompleted: (result) async {
          // Asenkron gecikme ve hata simülasyonu
          await Future<void>.delayed(const Duration(milliseconds: 10));
          throw StateError('Simüle edilmiş UI callback hatası');
        },
      );

      // Callback exception fırlatsa dahi triggerSync kilitlenmeden tamamlanmalıdır
      final result = await coordinator.triggerSync();

      expect(result, isNotNull);
      expect(coordinator.state.status, SyncCoordinatorStatus.idle);
      expect(coordinator.state.isSyncing, isFalse);

      coordinator.dispose();
    });

    test('18. Code Review 6: Backlog drain sırasında ilerleme olmaması durumunda sonsuz döngü koruması', () async {
      var callIndex = 0;
      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => testValidToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
        syncServiceFactory: ({
          required repository,
          required transport,
          required deviceId,
          required deviceToken,
          required hubUrl,
          readDeviceToken,
        }) {
          callIndex++;
          return _FakeProgresslessSyncService(repository: repository, transport: transport);
        },
      );

      final result = await coordinator.triggerSync();

      // hasMore: true olmasına rağmen syncedCount: 0 olduğu için drain döngüsü durmalıdır
      expect(result?.hasMore, isTrue);
      expect(result?.syncedCount, 0);
      expect(callIndex, 1, reason: 'İlerleme yokken ardışık drain döngüsüne girilmemelidir');
      expect(coordinator.state.status, SyncCoordinatorStatus.idle);
      expect(coordinator.state.isSyncing, isFalse);

      coordinator.dispose();
    });

    test('19. Code Review 7: Dispose sırasında bekleyen trailing Future güvenli sonlandırılır', () async {
      final delayCompleter = Completer<SyncResponse>();
      transport.delayCompleter = delayCompleter;

      await localDb.repository.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [
          CartItemInput.units('prod_su', 1),
        ],
      );

      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => testValidToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
      );

      // İlk sync başlar
      final future1 = coordinator.triggerSync();

      await _waitForTransportCall(transport);

      // Ardıl sync kuyruklanır
      final trailingFuture = coordinator.triggerSync(reason: SyncTriggerReason.saleCommitted);

      // Uygulama kapatılır / dispose çağrılır
      coordinator.dispose();

      // Trailing future kilitli kalmadan null ile tamamlanmalıdır
      final trailingResult = await trailingFuture;
      expect(trailingResult, isNull);

      // İlk future da serbest bırakılır
      transport.delayCompleter = null;
      delayCompleter.complete(
        SyncResponse(
          statusCode: 201,
          body: jsonEncode({
            'status': 'COMMITTED',
            'client_seq': 1,
            'committed_at': DateTime.now().toIso8601String(),
          }),
        ),
      );

      await future1;
    });

    test('20. Code Review 8: Backlog drain öncesi token kontrolü ve token kaybı koruması', () async {
      // 2 satış oluştur (seq 1 ve seq 2)
      await localDb.repository.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [
          CartItemInput.units('prod_su', 1),
        ],
      );
      await localDb.repository.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [
          CartItemInput.units('prod_su', 2),
        ],
      );

      String? currentToken = testValidToken;
      var batchCallCount = 0;

      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () {
          // İlk ağ çağrısı tamamlandıktan sonra token kaybolur
          if (transport.callCount >= 1) {
            currentToken = null;
          }
          return currentToken;
        },
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
        syncServiceFactory: ({
          required repository,
          required transport,
          required deviceId,
          required deviceToken,
          required hubUrl,
          readDeviceToken,
        }) {
          return _CustomBatchSizeSyncService(
            repository: repository,
            transport: transport,
            batchSize: 1, // Her turda yalnızca 1 işlem aktarır
            readDeviceToken: readDeviceToken,
            onSyncInvoked: () {
              batchCallCount++;
            },
          );
        },
      );

      // İlk sync döngüsü başlatılır
      final result = await coordinator.triggerSync();

      // İlk batch başarılı (syncedCount: 1, hasMore: true)
      expect(result?.syncedCount, 1);
      expect(result?.hasMore, isTrue);

      // İkinci batch (backlog drain) KESİNLİKLE başlamamalıdır
      expect(batchCallCount, 1, reason: 'Token null iken 2. backlog drain batch başlatılamaz');
      expect(transport.callCount, 1, reason: 'Yalnızca ilk işlem için 1 transport çağrısı yapılmalıdır');

      // Coordinator authRequired durumunda kalmalıdır
      expect(coordinator.state.status, SyncCoordinatorStatus.authRequired);
      expect(coordinator.state.isSyncing, isFalse);

      // 2. satış (seq 2) veritabanında PENDING olarak korunmalıdır
      final summary = await localDb.getOutboxSummary();
      expect(summary.pending, 1, reason: 'İkinci satış yetkisiz aktarılmamalı, PENDING kalmalıdır');
      expect(summary.totalUnsynced, 1);

      coordinator.dispose();
    });

    test('21. Code Review 9: Dispose çağrıldığında aktif ve trailing Future ağ yanıtı beklenmeden sonlandırılır', () async {
      final delayCompleter = Completer<SyncResponse>();
      transport.delayCompleter = delayCompleter;

      await localDb.repository.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [
          CartItemInput.units('prod_su', 1),
        ],
      );

      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => testValidToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
      );

      // 1. Aktif ağ çağrısını başlat
      final activeFuture = coordinator.triggerSync();

      await _waitForTransportCall(transport);

      // 2. Trailing çağrıyı başlat
      final trailingFuture = coordinator.triggerSync(reason: SyncTriggerReason.saleCommitted);

      // 3. Ağ yanıtı henüz gelmeden coordinator dispose edilir
      coordinator.dispose();

      // 4. İki Future da ağ yanıtı beklenmeden DERHAL null ile tamamlanmalıdır
      final activeResult = await activeFuture;
      final trailingResult = await trailingFuture;

      expect(activeResult, isNull, reason: 'Aktif çağırıcı dispose edildiğinde askıda kalmadan null döner');
      expect(trailingResult, isNull, reason: 'Trailing çağırıcı dispose edildiğinde askıda kalmadan null döner');

      // 5. Ağ yanıtı daha sonra serbest bırakıldığında arka plandaki işlem unhandled exception fırlatmaz
      transport.delayCompleter = null;
      delayCompleter.complete(
        SyncResponse(
          statusCode: 201,
          body: jsonEncode({
            'status': 'COMMITTED',
            'client_seq': 1,
            'committed_at': DateTime.now().toIso8601String(),
          }),
        ),
      );

      // Arka plan microtask'larının temizce sonlanması için kısa süre tanı
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });

    test('22. Code Review 10: Token okuyucusu başlangıç hata yönetimi (readDeviceToken exception -> error)', () async {
      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () {
          throw StateError('Güvenli depolama erişim hatası (DPAPI read failed)');
        },
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
      );

      final result = await coordinator.triggerSync();

      expect(result, isNull);
      expect(coordinator.state.status, SyncCoordinatorStatus.error,
          reason: 'Depolama hatası authRequired değil, error durumuna geçmelidir');
      expect(coordinator.state.isSyncing, isFalse);
      expect(coordinator.state.errorMessage, contains('DPAPI read failed'));
      expect(transport.callCount, 0, reason: 'Token hatası varken transport çağrılamaz');

      coordinator.dispose();
    });

    test('23. Code Review 11: Token okuyucusu sync sonrası hata yönetimi (sync sonrası token okuma hatası)', () async {
      await localDb.repository.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [
          CartItemInput.units('prod_su', 1),
        ],
      );

      var readCount = 0;
      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () {
          readCount++;
          // İlk tur (triggerSync ve syncPendingOutbox) başarılı, senkronizasyon sonrasındaki okuma hata fırlatır
          if (readCount > 2) {
            throw StateError('Token cache corrupted');
          }
          return testValidToken;
        },
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
      );

      final result = await coordinator.triggerSync();

      expect(result, isNotNull);
      expect(result?.syncedCount, 1);
      // Senkronizasyon sonrası token okunamadığı için coordinator error durumuna geçmelidir
      expect(coordinator.state.status, SyncCoordinatorStatus.error);
      expect(coordinator.state.errorMessage, contains('Token cache corrupted'));
      expect(coordinator.state.isSyncing, isFalse);

      coordinator.dispose();
    });

    test('24. Code Review 12: Beklenmeyen asenkron exception durumunda aktif Future tamamlanır ve isSyncing takılı kalmaz', () async {
      await localDb.repository.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [
          CartItemInput.units('prod_su', 1),
        ],
      );

      var shouldThrow = true;

      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => testValidToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
        syncServiceFactory: ({
          required repository,
          required transport,
          required deviceId,
          required deviceToken,
          required hubUrl,
          readDeviceToken,
        }) {
          if (shouldThrow) {
            return _AsyncThrowingSyncService(
              repository: repository,
              transport: transport,
              deviceId: deviceId,
              deviceToken: deviceToken,
              readDeviceToken: readDeviceToken,
              hubUrl: hubUrl,
            );
          }
          return ClientSyncService(
            repository: repository,
            transport: transport,
            deviceId: deviceId,
            deviceToken: deviceToken,
            readDeviceToken: readDeviceToken,
            hubUrl: hubUrl,
          );
        },
      );

      final syncFuture = coordinator.triggerSync(reason: SyncTriggerReason.startup);

      // Asenkron exception fırlatılmasına rağmen Future askıda kalmamalı ve tamamlanmalıdır
      final result = await syncFuture;

      expect(result, isNull, reason: 'İstisna fırlatan asenkron işlem null sonuçla tamamlanmalıdır');
      expect(coordinator.state.isSyncing, isFalse, reason: 'isSyncing bayrağı false olmalıdır');
      expect(coordinator.state.status, SyncCoordinatorStatus.error, reason: 'Durum error olmalıdır');
      expect(coordinator.state.errorMessage, contains('Beklenmeyen asenkron veritabanı / soket çökmesi'));

      // Gerçek kurtarma (recovery) doğrulaması:
      // Hata durumu düzeldiğinde (shouldThrow = false) sonraki senkronizasyon başarılı şekilde tamamlanmalı
      shouldThrow = false;
      final secondResult = await coordinator.triggerSync(reason: SyncTriggerReason.manual);

      expect(secondResult, isNotNull);
      expect(secondResult?.syncedCount, 1);
      expect(coordinator.state.isSyncing, isFalse);
      expect(coordinator.state.status, SyncCoordinatorStatus.idle);
      expect(coordinator.state.errorMessage, isNull);

      final outbox1 = await (localDb.repository.db.select(localDb.repository.db.outboxOperations)
            ..where((o) => o.clientSeq.equals(1)))
          .getSingle();
      expect(outbox1.status, 'SYNCED');

      final outboxSummary = await localDb.repository.getOutboxSummary(deviceId: testDeviceId);
      expect(outboxSummary.pending, 0);
      expect(outboxSummary.inProgress, 0);
      expect(outboxSummary.retry, 0);

      coordinator.dispose();
    });

    test('25. Regresyon Test A: Aynı batch içerisinde HTTP istekleri arasında token kaybı koruması (Doğal batch boyutu)', () async {
      String? currentToken = testValidToken;

      // 1. İki satış Outbox içerisinde PENDING durumda
      await localDb.repository.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [
          CartItemInput.units('prod_su', 1),
        ],
      );
      await localDb.repository.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CARD',
        items: [
          CartItemInput.units('prod_su', 2),
        ],
      );

      final delayCompleter = Completer<SyncResponse>();
      transport.delayCompleter = delayCompleter;

      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => currentToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
      );

      // 2. Senkronizasyon başlatılır
      final syncFuture = coordinator.triggerSync(reason: SyncTriggerReason.startup);

      // 3. İlk HTTP isteği gönderilir ve bekletilir
      await _waitForTransportCall(transport);
      expect(transport.callCount, 1, reason: 'İlk satış ağ isteğine başlamış olmalı');

      // 4. İlk istek başarılı ACK alır ve hemen ardından token geçersiz hale getirilir
      transport.delayCompleter = null;
      currentToken = null; // Token ilk HTTP isteği yanıtından sonra kaybolur!

      delayCompleter.complete(
        SyncResponse(
          statusCode: 201,
          body: jsonEncode({
            'status': 'COMMITTED',
            'client_seq': 1,
            'committed_at': DateTime.now().toIso8601String(),
          }),
        ),
      );

      final result = await syncFuture;

      // 6. İkinci HTTP isteğinin KESİNLİKLE gönderilmediği doğrulanır
      expect(transport.callCount, 1, reason: 'İkinci HTTP isteği KESİNLİKLE gönderilmemelidir');

      // Beklenen sonuçlar:
      // - İlk satış SYNCED
      final outbox1 = await (localDb.repository.db.select(localDb.repository.db.outboxOperations)
            ..where((o) => o.clientSeq.equals(1)))
          .getSingle();
      expect(outbox1.status, 'SYNCED');

      // - İkinci satış PENDING (IN_PROGRESS veya FAILED yapılmamalıdır)
      final outbox2 = await (localDb.repository.db.select(localDb.repository.db.outboxOperations)
            ..where((o) => o.clientSeq.equals(2)))
          .getSingle();
      expect(outbox2.status, 'PENDING');

      // - Coordinator durumu authRequired
      expect(coordinator.state.status, SyncCoordinatorStatus.authRequired);

      // - isSyncing false
      expect(coordinator.state.isSyncing, isFalse);

      // - Bekleyen trailing işlem yok
      expect(coordinator.state.hasPendingTrailingSync, isFalse);
      expect(result?.syncedCount, 1);

      coordinator.dispose();
    });

    test('26. Regresyon Test B: Token kaybında trailing işlemin temizlenmesi ve state tutarlılığı', () async {
      String? currentToken = testValidToken;

      await localDb.repository.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [
          CartItemInput.units('prod_su', 1),
        ],
      );

      final delayCompleter = Completer<SyncResponse>();
      transport.delayCompleter = delayCompleter;

      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => currentToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
      );

      // 1. Bir senkronizasyon aktif olsun
      final activeFuture = coordinator.triggerSync(reason: SyncTriggerReason.startup);
      await _waitForTransportCall(transport);
      expect(coordinator.state.isSyncing, isTrue);

      // 2. İkinci bir triggerSync() çağrısıyla trailing işlem oluşturulsun
      final trailingFuture = coordinator.triggerSync(reason: SyncTriggerReason.saleCommitted);
      expect(coordinator.state.hasPendingTrailingSync, isTrue);
      expect(coordinator.state.isSyncing, isTrue);

      // 3. Token geçersiz hale getirilsin
      currentToken = null;

      // 4. Aktif işlem tamamlansın
      transport.delayCompleter = null;
      delayCompleter.complete(
        SyncResponse(
          statusCode: 201,
          body: jsonEncode({
            'status': 'COMMITTED',
            'client_seq': 1,
            'committed_at': DateTime.now().toIso8601String(),
          }),
        ),
      );

      final activeResult = await activeFuture;
      expect(activeResult?.syncedCount, 1);

      // Beklenen:
      // - Trailing Future tamamlanmalı
      final trailingResult = await trailingFuture;
      expect(trailingResult, isNull);

      // - hasPendingTrailingSync == false
      expect(coordinator.state.hasPendingTrailingSync, isFalse);

      // - isSyncing == false
      expect(coordinator.state.isSyncing, isFalse);

      // - status == authRequired
      expect(coordinator.state.status, SyncCoordinatorStatus.authRequired);

      // - Ağ çağrısı yalnız 1 adet olmalı (trailing çalışmamalı)
      expect(transport.callCount, 1);

      // - Sonraki geçerli token ile yeni senkronizasyon başlatılabilmeli
      currentToken = testValidToken;
      final resumedResult = await coordinator.triggerSync(reason: SyncTriggerReason.manual);
      expect(coordinator.state.status, SyncCoordinatorStatus.idle);
      expect(resumedResult?.syncedCount, 0);

      coordinator.dispose();
    });

    test('27. Regresyon Test C: Token okuyucu exception fırlattığında trailing işlemin temizlenmesi ve state tutarlılığı', () async {
      String? currentToken = testValidToken;
      bool shouldThrow = false;

      await localDb.repository.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [
          CartItemInput.units('prod_su', 1),
        ],
      );

      final delayCompleter = Completer<SyncResponse>();
      transport.delayCompleter = delayCompleter;

      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () {
          if (shouldThrow) {
            throw StateError('DPAPI donanım anahtarlık erişim arızası');
          }
          return currentToken;
        },
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
      );

      // 1. Bir senkronizasyon aktif olsun
      final activeFuture = coordinator.triggerSync(reason: SyncTriggerReason.startup);
      await _waitForTransportCall(transport);
      expect(coordinator.state.isSyncing, isTrue);

      // 2. İkinci bir triggerSync() çağrısıyla trailing işlem oluşturulsun
      final trailingFuture = coordinator.triggerSync(reason: SyncTriggerReason.saleCommitted);
      expect(coordinator.state.hasPendingTrailingSync, isTrue);

      // 3. Token okuyucu exception fırlatır duruma getirilsin
      shouldThrow = true;

      // 4. Aktif işlem tamamlansın
      transport.delayCompleter = null;
      delayCompleter.complete(
        SyncResponse(
          statusCode: 201,
          body: jsonEncode({
            'status': 'COMMITTED',
            'client_seq': 1,
            'committed_at': DateTime.now().toIso8601String(),
          }),
        ),
      );

      final activeResult = await activeFuture;
      expect(activeResult?.syncedCount, 1);

      // Beklenen:
      // - Trailing Future tamamlanmalı
      final trailingResult = await trailingFuture;
      expect(trailingResult, isNull);

      // - hasPendingTrailingSync == false
      expect(coordinator.state.hasPendingTrailingSync, isFalse);

      // - isSyncing == false
      expect(coordinator.state.isSyncing, isFalse);

      // - status == error
      expect(coordinator.state.status, SyncCoordinatorStatus.error);
      expect(coordinator.state.errorMessage, contains('DPAPI donanım anahtarlık erişim arızası'));

      // - Ağ çağrısı yalnız 1 adet olmalı (trailing çalışmamalı)
      expect(transport.callCount, 1);

      // - Token okuyucu düzeldiğinde yeni senkronizasyon başlatılabilmeli
      shouldThrow = false;
      final recoveredResult = await coordinator.triggerSync(reason: SyncTriggerReason.manual);
      expect(coordinator.state.status, SyncCoordinatorStatus.idle);
      expect(recoveredResult?.syncedCount, 0);

      coordinator.dispose();
    });

    test('28. Regresyon Test D: _executeSyncCycle dış döngü beklenmeyen exception koruması (Dış catch, kontrollü trailing Future tamamlama ve kurtarma)', () async {
      await localDb.repository.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [
          CartItemInput.units('prod_su', 1),
        ],
      );

      final cycle1StartedCompleter = Completer<void>();
      final cycle1ProceedCompleter = Completer<void>();
      var shouldThrowInCycle = true;

      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => testValidToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
        onCycleStart: () async {
          if (shouldThrowInCycle) {
            if (!cycle1StartedCompleter.isCompleted) {
              cycle1StartedCompleter.complete();
            }
            // İlk döngüyü kontrollü olarak beklet
            await cycle1ProceedCompleter.future;
            throw StateError('Simüle edilmiş döngü başlangıç / state yönetimi çökmesi');
          }
        },
      );

      // 1. İlk senkronizasyon çağrısını başlat
      final syncFuture1 = coordinator.triggerSync(reason: SyncTriggerReason.startup);

      // 2. İlk döngünün onCycleStart kancasına ulaştığını bekle
      await cycle1StartedCompleter.future;
      expect(coordinator.hasActiveSync, isTrue, reason: 'İlk senkronizasyon aktif olmalıdır');
      expect(coordinator.state.isSyncing, isTrue, reason: 'isSyncing true olmalıdır');

      // 3. İlk senkronizasyon askıdayken ikinci triggerSync() çağrısını yap (Gerçek Trailing Coalescing)
      final syncFuture2 = coordinator.triggerSync(reason: SyncTriggerReason.manual);

      // 4. İlk döngüyü serbest bırakmadan önce trailing ve active durumlarını kesin olarak doğrula
      expect(coordinator.hasActiveSync, isTrue, reason: 'İlk senkronizasyon hâlâ aktif olmalıdır');
      expect(coordinator.hasTrailingSync, isTrue, reason: 'İkinci çağrı trailing olarak kuyruğa alınmış olmalıdır');
      expect(coordinator.state.hasPendingTrailingSync, isTrue, reason: 'hasPendingTrailingSync true olmalıdır');

      // 5. İlk döngüyü serbest bırak ve StateError fırlatmasını sağla
      cycle1ProceedCompleter.complete();

      // 6. Her iki Future da kontrolsüz / unhandled exception OLMADAN null ile tamamlanmalıdır
      final result1 = await syncFuture1;
      final result2 = await syncFuture2;

      // Beklenen doğrulamalar:
      // - Aktif ve trailing Future'ların ikisi de null ile tamamlanır
      expect(result1, isNull, reason: 'İlk işlem null ile tamamlanmalıdır');
      expect(result2, isNull, reason: 'Trailing işlem null ile tamamlanmalıdır');
      // - isSyncing, hasPendingTrailingSync, hasActiveSync ve hasTrailingSync temizliği
      expect(coordinator.state.isSyncing, isFalse, reason: 'isSyncing false olmalıdır');
      expect(coordinator.state.hasPendingTrailingSync, isFalse, reason: 'hasPendingTrailingSync false olmalıdır');
      expect(coordinator.hasActiveSync, isFalse, reason: 'hasActiveSync false olmalıdır');
      expect(coordinator.hasTrailingSync, isFalse, reason: 'hasTrailingSync false olmalıdır');
      // - Status error ve hata mesajı doğrulaması
      expect(coordinator.state.status, SyncCoordinatorStatus.error);
      expect(coordinator.state.errorMessage, contains('Simüle edilmiş döngü başlangıç / state yönetimi çökmesi'));

      // 7. Coordinator kilitlenmemeli: Hata sonrasında yeni sync başlatıp başarılı recovery'yi doğrula
      shouldThrowInCycle = false;
      final recoveredResult = await coordinator.triggerSync(reason: SyncTriggerReason.manual);

      expect(recoveredResult, isNotNull);
      expect(recoveredResult?.syncedCount, 1);
      expect(coordinator.state.isSyncing, isFalse);
      expect(coordinator.state.status, SyncCoordinatorStatus.idle);
      expect(coordinator.state.errorMessage, isNull);
      expect(coordinator.hasActiveSync, isFalse);
      expect(coordinator.hasTrailingSync, isFalse);

      // 8. Outbox kaydının SYNCED olduğunu doğrula
      final outbox1 = await (localDb.repository.db.select(localDb.repository.db.outboxOperations)
            ..where((o) => o.clientSeq.equals(1)))
          .getSingle();
      expect(outbox1.status, 'SYNCED', reason: 'Outbox kaydı SYNCED olmalıdır');

      coordinator.dispose();
    });

    test('29. Faz 7A Restore Güvenliği: pauseForMaintenance devam eden turun bitmesini bekler, yeni tur başlatmaz', () async {
      final delayCompleter = Completer<SyncResponse>();
      transport.delayCompleter = delayCompleter;
      await localDb.repository.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_su', 1)],
      );

      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => testValidToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
      );

      final inFlight = coordinator.triggerSync(reason: SyncTriggerReason.startup);
      await _waitForTransportCall(transport);

      var pauseCompleted = false;
      final pauseFuture = coordinator.pauseForMaintenance().then((_) => pauseCompleted = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(pauseCompleted, isFalse, reason: 'Ağda bekleyen tur bitmeden restore başlamamalı');
      expect(coordinator.isPausedForMaintenance, isTrue);

      transport.delayCompleter = null;
      delayCompleter.complete(SyncResponse(
        statusCode: 201,
        body: jsonEncode({'status': 'COMMITTED', 'client_seq': 1}),
      ));
      await inFlight;
      await pauseFuture;
      expect(pauseCompleted, isTrue);

      final callsBefore = transport.callCount;
      await localDb.repository.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_su', 1)],
      );
      final whilePaused = await coordinator.triggerSync(reason: SyncTriggerReason.saleCommitted);
      expect(whilePaused, isNull);
      expect(transport.callCount, callsBefore, reason: 'Bakım sırasında Hub\'a istek gönderilmemeli');
      expect(coordinator.state.status, SyncCoordinatorStatus.paused);

      coordinator.dispose();
    });

    test('30. Faz 7A Restore Güvenliği: resumeAfterMaintenance sonrası senkronizasyon yeniden çalışır', () async {
      await localDb.repository.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_su', 1)],
      );
      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => testValidToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
      );

      await coordinator.pauseForMaintenance();
      expect(await coordinator.triggerSync(), isNull);
      expect(transport.callCount, 0);

      coordinator.resumeAfterMaintenance(triggerSync: false);
      expect(coordinator.isPausedForMaintenance, isFalse);
      expect(coordinator.state.status, SyncCoordinatorStatus.idle);

      final result = await coordinator.triggerSync(reason: SyncTriggerReason.manual);
      expect(result?.syncedCount, 1);
      expect(transport.callCount, 1);

      coordinator.dispose();
    });

    test('31. Faz 7B: TLS pin uyuşmazlığı ayrı durum (tlsPinMismatch) olarak raporlanır, sıradan ağ hatası gibi gösterilmez', () async {
      transport.defaultResponse = SyncResponse.tlsPinMismatch(
        TlsPinMismatchException(host: '127.0.0.1', port: 8443, presentedSha256: 'AA' * 32),
      );
      await localDb.repository.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_su', 1)],
      );
      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => testValidToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
      );

      final result = await coordinator.triggerSync();

      expect(result?.tlsPinMismatch, isTrue);
      expect(coordinator.state.status, SyncCoordinatorStatus.tlsPinMismatch);
      expect(coordinator.state.status, isNot(SyncCoordinatorStatus.networkError));
      expect(coordinator.state.errorMessage, contains('TLS_PIN_MISMATCH'));

      coordinator.dispose();
    });

    test('32. WP-1 DHCP/Ağ Köprüsü: onHubNetworkUnreachable yalnızca ağ/downlink hatalarında tetiklenir; TLS ve Auth hatalarında ASLA tetiklenmez', () async {
      final unreachableEvents = <({String url, String? err})>[];

      // 1. Uplink networkError (503) -> tetiklenmeli
      await localDb.repository.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_su', 1)],
      );
      transport.defaultResponse = const SyncResponse(
        statusCode: 503,
        body: '',
        errorMessage: 'SocketException: Connection refused',
      );
      final coordinator = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: transport,
        deviceId: testDeviceId,
        readDeviceToken: () => testValidToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
        syncServiceFactory: ({
          required repository,
          required transport,
          required deviceId,
          required deviceToken,
          readDeviceToken,
          required hubUrl,
        }) =>
            ClientSyncService(
          repository: repository,
          transport: transport,
          deviceId: deviceId,
          deviceToken: deviceToken,
          readDeviceToken: readDeviceToken,
          hubUrl: hubUrl,
          baseBackoff: Duration.zero,
          maxBackoff: Duration.zero,
        ),
        onHubNetworkUnreachable: (url, err) {
          unreachableEvents.add((url: url, err: err));
        },
      );
      addTearDown(coordinator.dispose);

      await coordinator.triggerSync(reason: SyncTriggerReason.manual);
      expect(coordinator.state.status, SyncCoordinatorStatus.networkError);
      expect(unreachableEvents, hasLength(1));
      expect(unreachableEvents.single.url, testHubUrl);

      // 2. TLS Pin Mismatch -> KESİNLİKLE tetiklenmemeli
      unreachableEvents.clear();
      transport.defaultResponse = SyncResponse.tlsPinMismatch(
        TlsPinMismatchException(host: '127.0.0.1', port: 8443, presentedSha256: 'AA' * 32),
      );
      await coordinator.triggerSync(reason: SyncTriggerReason.manual);
      expect(coordinator.state.status, SyncCoordinatorStatus.tlsPinMismatch);
      expect(unreachableEvents, isEmpty);

      // 3. TLS Cert Error -> KESİNLİKLE tetiklenmemeli
      transport.defaultResponse = SyncResponse.tlsCertError(
        const TlsCertificateValidationException(
          kind: TlsCertificateFailureKind.ipAddressMismatch,
          host: '127.0.0.1',
          port: 8443,
        ),
      );
      await coordinator.triggerSync(reason: SyncTriggerReason.manual);
      expect(coordinator.state.status, SyncCoordinatorStatus.tlsCertError);
      expect(unreachableEvents, isEmpty);

      // 4. Downlink SocketException (outbox boşken bile) -> tetiklenmeli
      transport.defaultResponse = null;
      transport.productsResponse = const SyncResponse(
        statusCode: 0,
        body: '',
        errorMessage: 'Ağ bağlantı hatası (SocketException): Network is unreachable',
        failureKind: SyncFailureKind.network,
      );
      final emptyCoord = BackgroundSyncCoordinator(
        repository: localDb.repository,
        transport: _EmptyOutboxNetworkDownlinkTransport(),
        deviceId: 'POS-OTHER-01',
        readDeviceToken: () => testValidToken,
        hubUrl: testHubUrl,
        autoStartTimer: false,
        enableLifecycleListener: false,
        onHubNetworkUnreachable: (url, err) {
          unreachableEvents.add((url: url, err: err));
        },
      );
      addTearDown(emptyCoord.dispose);
      await emptyCoord.triggerSync(reason: SyncTriggerReason.periodic);
      expect(unreachableEvents, hasLength(1));
      expect(unreachableEvents.single.url, testHubUrl);
    });
  });
}

class _EmptyOutboxNetworkDownlinkTransport extends _TestSyncTransport {
  @override
  Future<SyncResponse> getProducts({
    required String hubUrl,
    required String token,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return SyncResponse.networkError(
      'Ağ bağlantı hatası (SocketException): Network is unreachable',
    );
  }
}

class _AsyncThrowingSyncService extends ClientSyncService {
  _AsyncThrowingSyncService({
    required super.repository,
    required super.transport,
    required super.deviceId,
    required super.deviceToken,
    super.readDeviceToken,
    required super.hubUrl,
  });

  @override
  Future<SyncBatchResult> syncPendingOutbox({
    DateTime? now,
    int maxBatch = 100,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    throw StateError('Beklenmeyen asenkron veritabanı / soket çökmesi');
  }
}

class _CustomBatchSizeSyncService extends ClientSyncService {
  final int batchSize;
  final void Function() onSyncInvoked;

  _CustomBatchSizeSyncService({
    required super.repository,
    required super.transport,
    required this.batchSize,
    required this.onSyncInvoked,
    super.readDeviceToken,
  }) : super(
          deviceId: 'POS-WIN-01',
          deviceToken: 'token',
          hubUrl: 'https://127.0.0.1:8443',
        );

  @override
  Future<SyncBatchResult> syncPendingOutbox({
    DateTime? now,
    int maxBatch = 100,
  }) async {
    onSyncInvoked();
    return super.syncPendingOutbox(now: now, maxBatch: batchSize);
  }
}

class _FakeProgresslessSyncService extends ClientSyncService {
  _FakeProgresslessSyncService({
    required super.repository,
    required super.transport,
  }) : super(
          deviceId: 'POS-WIN-01',
          deviceToken: 'token',
          hubUrl: 'https://127.0.0.1:8443',
        );

  @override
  Future<SyncBatchResult> syncPendingOutbox({
    DateTime? now,
    int maxBatch = 100,
  }) async {
    return const SyncBatchResult(
      syncedCount: 0,
      retriedCount: 0,
      permanentFailedCount: 0,
      hasMore: true, // hasMore true ama syncedCount 0!
    );
  }
}
