import 'dart:convert';
import 'dart:math';
import 'package:drift/drift.dart';

import '../database/client_database.dart';
import '../database/client_storage_repository.dart';
import 'sync_transport.dart';

class SyncBatchResult {
  final int syncedCount;
  final int retriedCount;
  final int permanentFailedCount;
  final bool hasMore;
  final String? lastError;

  const SyncBatchResult({
    required this.syncedCount,
    required this.retriedCount,
    required this.permanentFailedCount,
    required this.hasMore,
    this.lastError,
  });

  bool get isCleanSuccess => retriedCount == 0 && permanentFailedCount == 0;
}

class ClientSyncService {
  final ClientStorageRepository repository;
  final SyncTransport transport;
  final String deviceId;
  final String deviceToken;
  final String hubUrl;
  final Duration baseBackoff;
  final Duration maxBackoff;
  final Duration requestTimeout;

  ClientSyncService({
    required this.repository,
    required this.transport,
    required this.deviceId,
    required this.deviceToken,
    required this.hubUrl,
    this.baseBackoff = const Duration(seconds: 1),
    this.maxBackoff = const Duration(seconds: 60),
    this.requestTimeout = const Duration(seconds: 10),
  });

  /// S5A-3: Outbox kuyruğundaki bekleyen işlemleri katı FIFO (client_seq ASC) sırasıyla gönderir
  Future<SyncBatchResult> syncPendingOutbox({
    DateTime? now,
    int maxBatch = 100,
  }) async {
    final effectiveNow = now ?? DateTime.now();

    // 0. Varsa önceki yarıda kalmış ürün senkronizasyon oturumunu onayla (Product Sync ACK)
    await _tryAcknowledgePendingSyncSession();

    // 1. Crash recovery: Uygulama yeniden başladığında yarıda kalmış IN_PROGRESS işlemlerini düzelt
    await repository.recoverStuckInProgressOperations(deviceId);

    var synced = 0;
    var retried = 0;
    var failed = 0;
    String? stopError;

    for (var i = 0; i < maxBatch; i++) {
      // 2. Cihaz için senkronize edilmemiş EN KÜÇÜK client_seq'e sahip işlemi bul
      final oldestUnsynced = await (repository.db.select(repository.db.outboxOperations)
            ..where((o) =>
                o.deviceId.equals(deviceId) &
                (o.status.equals('PENDING') | o.status.equals('RETRY') | o.status.equals('FAILED_PERMANENT')))
            ..orderBy([(o) => OrderingTerm.asc(o.clientSeq)])
            ..limit(1))
          .getSingleOrNull();

      if (oldestUnsynced == null) {
        // Gönderilecek başka işlem kalmadı
        break;
      }

      // KURAL: Eğer sıradaki en küçük işlem FAILED_PERMANENT durumundaysa,
      // deterministik FIFO gereği kuyruk durur; sonraki sıralara ASLA geçilemez!
      if (oldestUnsynced.status == 'FAILED_PERMANENT') {
        stopError = 'client_seq ${oldestUnsynced.clientSeq} kalıcı hata (FAILED_PERMANENT) durumunda; kuyruk durduruldu: ${oldestUnsynced.lastError}';
        failed++;
        break;
      }

      // Sıradaki en küçük işlemin retry zamanı dolmuş mu kontrol et
      if (oldestUnsynced.nextRetryAt != null && oldestUnsynced.nextRetryAt!.isAfter(effectiveNow)) {
        // En küçük sıra henüz retry beklemesinde, sıra atlayamayız! (Deterministic FIFO)
        stopError = 'client_seq ${oldestUnsynced.clientSeq} için retry bekleme süresi henüz dolmadı.';
        retried++;
        break;
      }

      final op = oldestUnsynced;

      // 3. İşlemi IN_PROGRESS yap
      await repository.markOutboxInProgress(op.operationId);

      // 4. Hub API'ye gönder (HTTPS POST /api/v1/sales)
      final resp = await transport.postSale(
        hubUrl: hubUrl,
        token: deviceToken,
        payload: op.payload,
        timeout: requestTimeout,
      );

      // 5. Yanıtı değerlendir
      if (resp.isSuccess) {
        // Başarılı ACK veya İdempotent Replay (200 / 201)
        await repository.markOutboxSynced(
          op.operationId,
          clientSeq: op.clientSeq,
          deviceId: deviceId,
          acknowledgedAt: effectiveNow,
        );
        synced++;
      } else if (resp.isTransientError) {
        // Geçici hata (Ağ kesilmesi, zaman aşımı, HTTP 503 / 500)
        final nextAttempt = op.attemptCount + 1;
        final backoffMs = min(
          maxBackoff.inMilliseconds,
          baseBackoff.inMilliseconds * (1 << min(nextAttempt - 1, 10)),
        );
        final backoff = Duration(milliseconds: backoffMs);
        final errText = resp.errorMessage ?? 'HTTP ${resp.statusCode}: ${resp.body}';

        await repository.markOutboxRetry(
          op.operationId,
          attemptCount: nextAttempt,
          backoff: backoff,
          error: errText,
          now: effectiveNow,
        );
        retried++;
        stopError = errText;
        // Sıra bütünlüğünü korumak için sonraki client_seq'e GEÇİLEMEZ
        break;
      } else {
        // Kalıcı hata (400 Bad Request veya 409 Mismatch)
        final errText = 'Kalıcı Hata [${resp.statusCode}]: ${resp.body}';
        await repository.markOutboxPermanentFail(op.operationId, error: errText);
        failed++;
        stopError = errText;
        // Kalıcı hatada sıra kilitlenir, audit bildirilir
        break;
      }
    }

    final remainingCount = (await (repository.db.select(repository.db.outboxOperations)
              ..where((o) =>
                  o.deviceId.equals(deviceId) &
                  (o.status.equals('PENDING') | o.status.equals('RETRY') | o.status.equals('FAILED_PERMANENT'))))
            .get())
        .length;

    return SyncBatchResult(
      syncedCount: synced,
      retriedCount: retried,
      permanentFailedCount: failed,
      hasMore: remainingCount > 0,
      lastError: stopError,
    );
  }

  /// S5A-3: Henüz Hub'a iletilmemiş veya onaylanmamış bekleyen ürün sync oturumunu ACK eder
  Future<bool> _tryAcknowledgePendingSyncSession() async {
    final syncState = await repository.getSyncState(deviceId);
    final pendingId = syncState?.pendingSyncSessionId;
    if (pendingId == null || pendingId.isEmpty) return true;

    final resp = await transport.postSyncAck(
      hubUrl: hubUrl,
      token: deviceToken,
      syncSessionId: pendingId,
      timeout: requestTimeout,
    );

    if (resp.isSuccess) {
      final now = DateTime.now();
      await (repository.db.update(repository.db.clientSyncStates)
            ..where((s) => s.deviceId.equals(deviceId)))
          .write(
        ClientSyncStatesCompanion(
          pendingSyncSessionId: const Value(null),
          lastProductSyncAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      return true;
    } else if (!resp.isTransientError) {
      // Kalıcı hata durumunda (örn: geçersiz sync_session_id) temizle
      await (repository.db.update(repository.db.clientSyncStates)
            ..where((s) => s.deviceId.equals(deviceId)))
          .write(
        const ClientSyncStatesCompanion(
          pendingSyncSessionId: Value(null),
        ),
      );
      return false;
    }
    return false;
  }

  /// S5A-3: Merkezi sunucudaki güncel ürün ve fiyat listesini çeker ve yerel cache'i atomik olarak günceller
  Future<int> syncProducts({DateTime? now}) async {
    final effectiveNow = now ?? DateTime.now();

    // Varsa önceki tamamlanmamış ACK'yı gönder
    await _tryAcknowledgePendingSyncSession();

    final resp = await transport.getProducts(
      hubUrl: hubUrl,
      token: deviceToken,
      timeout: requestTimeout,
    );

    if (!resp.isSuccess) {
      throw StateError('Ürün senkronizasyonu başarısız oldu [${resp.statusCode}]: ${resp.errorMessage ?? resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final productsJson = data['products'] as List<dynamic>? ?? [];
    final syncSessionId = data['sync_session_id'] as String?;

    final productCompanions = <LocalProductsCompanion>[];
    final barcodeCompanions = <LocalProductBarcodesCompanion>[];

    for (final p in productsJson) {
      final pMap = p as Map<String, dynamic>;
      final pId = pMap['id'] as String;
      final pBarcode = pMap['barcode'] as String?;
      final isActive = pMap['is_active'] as bool? ?? true;
      final priceVersionId = pMap['price_version_id'] as String? ?? 'pv_init';

      productCompanions.add(LocalProductsCompanion(
        id: Value(pId),
        barcode: Value(pBarcode),
        name: Value(pMap['name'] as String),
        price: Value(pMap['price'] as int),
        priceVersionId: Value(priceVersionId),
        stock: Value(pMap['stock'] as int),
        stockUnit: Value(pMap['stock_unit'] as String? ?? 'adet'),
        pricingUnit: Value(pMap['pricing_unit'] as String? ?? 'adet'),
        conversionFactorNumerator: Value(pMap['conversion_factor_numerator'] as int? ?? 1),
        conversionFactorDenominator: Value(pMap['conversion_factor_denominator'] as int? ?? 1),
        vatRate: Value(pMap['vat_rate'] as int? ?? 20),
        isActive: Value(isActive),
        updatedAt: Value(effectiveNow),
      ));

      // Ana barkod varsa SSOT tablosuna ekle
      if (pBarcode != null && pBarcode.isNotEmpty) {
        barcodeCompanions.add(LocalProductBarcodesCompanion(
          id: Value('bc_${pId}_primary'),
          productId: Value(pId),
          barcode: Value(pBarcode),
          isPrimary: const Value(true),
          isActive: Value(isActive),
          createdAt: Value(effectiveNow),
        ));
      }

      // Ek alternatif barkodlar varsa SSOT tablosuna ekle
      final extraBarcodes = pMap['barcodes'] as List<dynamic>?;
      if (extraBarcodes != null) {
        for (var i = 0; i < extraBarcodes.length; i++) {
          final extraBc = extraBarcodes[i].toString();
          if (extraBc != pBarcode) {
            barcodeCompanions.add(LocalProductBarcodesCompanion(
              id: Value('bc_${pId}_alt_$i'),
              productId: Value(pId),
              barcode: Value(extraBc),
              isPrimary: const Value(false),
              isActive: Value(isActive),
              createdAt: Value(effectiveNow),
            ));
          }
        }
      }
    }

    // Atomik SQLite transaction: Ya hepsi güncellenir ya hiçbiri (Yarım kalan sync cache'i bozamaz)
    await repository.upsertProducts(productCompanions, barcodes: barcodeCompanions);

    final syncState = await repository.getSyncState(deviceId);
    if (syncState == null) {
      await repository.initializeDevice(deviceId);
    }

    // Yerel commit tamamlandı: Henüz sunucuya ACK gönderilmeden önce pendingSyncSessionId kaydet
    await (repository.db.update(repository.db.clientSyncStates)..where((s) => s.deviceId.equals(deviceId))).write(
          ClientSyncStatesCompanion(
            pendingSyncSessionId: Value(syncSessionId),
            updatedAt: Value(effectiveNow),
          ),
        );

    // 2. Aşama: İstemci yerel veritabanına başarıyla yazdıktan sonra Hub'a authenticated ACK gönderir
    if (syncSessionId != null && syncSessionId.isNotEmpty) {
      final ackResp = await transport.postSyncAck(
        hubUrl: hubUrl,
        token: deviceToken,
        syncSessionId: syncSessionId,
        timeout: requestTimeout,
      );

      if (ackResp.isSuccess) {
        await (repository.db.update(repository.db.clientSyncStates)..where((s) => s.deviceId.equals(deviceId))).write(
              ClientSyncStatesCompanion(
                pendingSyncSessionId: const Value(null),
                lastProductSyncAt: Value(effectiveNow),
                updatedAt: Value(effectiveNow),
              ),
            );
      }
    }

    return productCompanions.length;
  }
}
