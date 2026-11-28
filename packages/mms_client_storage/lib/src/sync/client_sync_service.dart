import 'dart:convert';
import 'dart:math';
import 'package:drift/drift.dart';

import '../database/client_database.dart';
import '../database/client_storage_repository.dart';
import '../models/downloaded_sale_payload.dart';
import '../models/sync_response.dart';
import 'sync_transport.dart';

class SyncBatchResult {
  final int syncedCount;
  final int retriedCount;
  final int permanentFailedCount;
  final bool hasMore;
  final String? lastError;

  /// Faz 7B: Hub sertifikası sabitlenen parmak iziyle uyuşmadığı için tur durdu.
  final bool tlsPinMismatch;

  /// ADR-017: Güvenilen kök CA altındaki sertifika doğrulaması (SAN/IP/hostname/tarih)
  /// başarısız olduğu için tur durdu.
  final bool tlsCertError;

  /// `OV-03`: Hub geri yükleme sonrası kayıp yerel Outbox geçmişi nedeniyle fail-closed durdu.
  final bool postRestoreHistoryMissing;

  /// `OV-03`: Geri yükleme uzlaştırması ile yeniden kuyruğa alınan `SYNCED` işlem sayısı.
  final int postRestoreRequeuedCount;

  const SyncBatchResult({
    required this.syncedCount,
    required this.retriedCount,
    required this.permanentFailedCount,
    required this.hasMore,
    this.lastError,
    this.tlsPinMismatch = false,
    this.tlsCertError = false,
    this.postRestoreHistoryMissing = false,
    this.postRestoreRequeuedCount = 0,
  });

  bool get isCleanSuccess =>
      retriedCount == 0 &&
      permanentFailedCount == 0 &&
      !postRestoreHistoryMissing;
}

class PostRestoreReconcileOutcome {
  final bool reconcileRequired;
  final bool historyMissing;
  final int requeuedCount;
  final String? targetEpoch;
  final String? error;

  const PostRestoreReconcileOutcome({
    required this.reconcileRequired,
    this.historyMissing = false,
    this.requeuedCount = 0,
    this.targetEpoch,
    this.error,
  });
}

class ClientSyncService {
  final ClientStorageRepository repository;
  final SyncTransport transport;
  final String deviceId;
  final String deviceToken;
  final String? Function()? readDeviceToken;
  final String hubUrl;
  final Duration baseBackoff;
  final Duration maxBackoff;
  final Duration requestTimeout;
  final Duration catalogSyncTimeout;
  final int catalogPageSize;

  ClientSyncService({
    required this.repository,
    required this.transport,
    required this.deviceId,
    required this.deviceToken,
    this.readDeviceToken,
    required this.hubUrl,
    this.baseBackoff = const Duration(seconds: 1),
    this.maxBackoff = const Duration(seconds: 60),
    this.requestTimeout = const Duration(seconds: 10),
    this.catalogSyncTimeout = const Duration(seconds: 30),
    this.catalogPageSize = 1000,
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

    // 1.5. OV-03: Hub yedek geri yüklemesi (`restore_epoch` değişimi veya `HWM` gerilemesi)
    // sonrası Hub'da bulunmayan geçmiş `SYNCED` işlemleri özgün kimlikleriyle yeniden kuyruğa al.
    final reconcileOutcome = await reconcilePostRestoreIfNeeded();
    if (reconcileOutcome.historyMissing) {
      return SyncBatchResult(
        syncedCount: 0,
        retriedCount: 0,
        permanentFailedCount: 0,
        hasMore: true,
        lastError: reconcileOutcome.error,
        postRestoreHistoryMissing: true,
        postRestoreRequeuedCount: reconcileOutcome.requeuedCount,
      );
    }

    var synced = 0;
    var retried = 0;
    var failed = 0;
    var pinMismatch = false;
    var certError = false;
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

      // Token geçerliliği kontrolü: Her yeni HTTP isteğinden önce token güncelliği doğrulanır.
      // Token kaybolmuş veya geçersizleşmişse işlem IN_PROGRESS yapılmaz, ağa istek atılmaz
      // ve henüz gönderilmemiş kayıtlar PENDING/RETRY durumunda korunur.
      final String? currentToken;
      try {
        currentToken =
            readDeviceToken != null ? readDeviceToken!() : deviceToken;
      } catch (e) {
        stopError = 'Cihaz yetkilendirme anahtarı okunurken hata oluştu: $e';
        break;
      }

      if (currentToken == null || currentToken.isEmpty) {
        stopError =
            'Cihaz yetkilendirme anahtarı (deviceToken) geçersiz veya silindi; batch durduruldu.';
        break;
      }

      // 3. İşlemi IN_PROGRESS yap
      await repository.markOutboxInProgress(op.operationId);

      // 4. Hub API'ye gönder (İşlem tipine göre ilgili rotaya yönlendir)
      final SyncResponse resp;
      if (op.operationType == 'PRODUCT_UPSERT') {
        resp = await transport.postProductUpsert(
          hubUrl: hubUrl,
          token: currentToken,
          payload: op.payload,
          timeout: requestTimeout,
        );
      } else if (op.operationType == 'CATEGORY_UPSERT') {
        if (transport is CatalogExtendedSyncTransport) {
          resp = await (transport as CatalogExtendedSyncTransport)
              .postCategoryUpsert(
            hubUrl: hubUrl,
            token: currentToken,
            payload: op.payload,
            timeout: requestTimeout,
          );
        } else {
          resp = SyncResponse.networkError(
            'CATEGORY_UPSERT mevcut taşıyıcı tarafından desteklenmiyor.',
          );
        }
      } else if (op.operationType == 'STOCK_RECEIPT') {
        resp = await transport.postStockReceipt(
          hubUrl: hubUrl,
          token: currentToken,
          payload: op.payload,
          timeout: requestTimeout,
        );
      } else {
        resp = await transport.postSale(
          hubUrl: hubUrl,
          token: currentToken,
          payload: op.payload,
          timeout: requestTimeout,
        );
      }

      // 5. Yanıtı değerlendir
      if (resp.isTlsPinMismatch) {
        // Faz 7B: Güvenlik hatası. Kayıt korunur (RETRY), uyuşmayan sunucuya hızlı
        // tekrar denemeyle bağlanılmaz; en uzun bekleme uygulanır ve durum ayrıca raporlanır.
        final errText = 'TLS_PIN_MISMATCH: ${resp.errorMessage}';
        await repository.markOutboxRetry(
          op.operationId,
          attemptCount: op.attemptCount + 1,
          backoff: maxBackoff,
          error: errText,
          now: effectiveNow,
        );
        retried++;
        pinMismatch = true;
        stopError = errText;
        break;
      } else if (resp.isTlsCertError) {
        // ADR-017: SAN/IP/hostname/süre hatası; pin uyuşmazlığından ayrılır, ancak
        // fail-closed kalır (HTTP fallback yok, Outbox RETRY korunur, maxBackoff).
        final errText = 'TLS_CERT_ERROR: ${resp.errorMessage}';
        await repository.markOutboxRetry(
          op.operationId,
          attemptCount: op.attemptCount + 1,
          backoff: maxBackoff,
          error: errText,
          now: effectiveNow,
        );
        retried++;
        certError = true;
        stopError = errText;
        break;
      } else if (resp.isSuccess) {
        // Başarılı ACK veya İdempotent Replay (200 / 201)
        await repository.markOutboxSynced(
          op.operationId,
          clientSeq: op.clientSeq,
          deviceId: deviceId,
          acknowledgedAt: effectiveNow,
        );
        synced++;
      } else if (resp.isTransientError || resp.isAuthOrTransportPolicyHold) {
        // Geçici hata (Ağ kesilmesi, zaman aşımı, HTTP 503 / 500) veya
        // kimlik/TLS politikası bekletmesi (401 / 403 / 426): kayıt asla FAILED_PERMANENT
        // yapılmaz; token yenileme, yeniden eşleştirme veya TLS düzeltmesi sonrası aynı
        // client_seq ile tekrar gönderilir.
        final nextAttempt = op.attemptCount + 1;
        final backoffMs = min(
          maxBackoff.inMilliseconds,
          baseBackoff.inMilliseconds * (1 << min(nextAttempt - 1, 10)),
        );
        final backoff = Duration(milliseconds: backoffMs);
        final errText = resp.isAuthOrTransportPolicyHold
            ? 'Yetki/TLS bekletmesi [HTTP ${resp.statusCode}]: kayıt korunuyor, cihaz yetkilendirmesi düzeltilince yeniden gönderilecek. ${resp.body}'
            : (resp.errorMessage ?? 'HTTP ${resp.statusCode}: ${resp.body}');

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

    if (reconcileOutcome.targetEpoch != null &&
        remainingCount == 0 &&
        retried == 0 &&
        failed == 0 &&
        !pinMismatch &&
        !certError) {
      await repository.saveStoredRestoreEpoch(
        deviceId,
        reconcileOutcome.targetEpoch!,
      );
    }

    return SyncBatchResult(
      syncedCount: synced,
      retriedCount: retried,
      permanentFailedCount: failed,
      hasMore: remainingCount > 0,
      lastError: stopError,
      tlsPinMismatch: pinMismatch,
      tlsCertError: certError,
      postRestoreHistoryMissing: false,
      postRestoreRequeuedCount: reconcileOutcome.requeuedCount,
    );
  }

  /// `OV-03`: Hub'ın `restore_epoch` ve `high_water_mark_seq` durumunu denetler;
  /// eski yedeğe dönüş tespit edilirse `/api/v1/sync/receipts` üzerinden eksik
  /// işlemleri doğrulayıp yerel `SYNCED` kayıtlarını atomik olarak yeniden kuyruğa alır.
  Future<PostRestoreReconcileOutcome> reconcilePostRestoreIfNeeded() async {
    if (transport is! PostRestoreSyncTransport) {
      return const PostRestoreReconcileOutcome(reconcileRequired: false);
    }
    final postRestoreTransport = transport as PostRestoreSyncTransport;

    final String? currentToken;
    try {
      currentToken = readDeviceToken != null ? readDeviceToken!() : deviceToken;
    } catch (_) {
      return const PostRestoreReconcileOutcome(reconcileRequired: false);
    }
    if (currentToken == null || currentToken.isEmpty) {
      return const PostRestoreReconcileOutcome(reconcileRequired: false);
    }

    final stateResp = await postRestoreTransport.getDeviceState(
      hubUrl: hubUrl,
      token: currentToken,
      timeout: requestTimeout,
    );
    if (!stateResp.isSuccess) {
      return PostRestoreReconcileOutcome(
        reconcileRequired: false,
        error: stateResp.errorMessage ?? 'HTTP ${stateResp.statusCode}',
      );
    }

    final Map<String, dynamic> stateData;
    try {
      stateData = jsonDecode(stateResp.body) as Map<String, dynamic>;
    } catch (_) {
      return const PostRestoreReconcileOutcome(reconcileRequired: false);
    }

    final hubRestoreEpoch =
        (stateData['restore_epoch'] as String?)?.trim() ?? 'epoch_0';
    final hubHwm = (stateData['high_water_mark_seq'] as num?)?.toInt() ?? 0;

    final storedEpoch = await repository.getStoredRestoreEpoch(deviceId);
    final localState = await repository.getSyncState(deviceId);
    final localLastSyncedSeq = localState?.lastSyncedSeq ?? 0;

    final epochChanged = storedEpoch != null && storedEpoch != hubRestoreEpoch;
    final hwmRegressed = hubHwm < localLastSyncedSeq;

    if (!epochChanged && !hwmRegressed) {
      if (storedEpoch == null) {
        await repository.saveStoredRestoreEpoch(deviceId, hubRestoreEpoch);
      }
      return const PostRestoreReconcileOutcome(reconcileRequired: false);
    }

    final localSyncedAfterHwm = await repository.getSyncedOutboxOperations(
      deviceId,
      afterSeq: hubHwm,
    );
    final candidateSeqSet = <int>{
      if (hubHwm < localLastSyncedSeq)
        for (var seq = hubHwm + 1; seq <= localLastSyncedSeq; seq++) seq,
      for (final op in localSyncedAfterHwm) op.clientSeq,
    };
    final candidateSeqs = candidateSeqSet.toList()..sort();

    if (candidateSeqs.isEmpty) {
      return PostRestoreReconcileOutcome(
        reconcileRequired: true,
        targetEpoch: hubRestoreEpoch,
      );
    }

    final missingSeqs = <int>[];
    for (var i = 0; i < candidateSeqs.length; i += 500) {
      final batch = candidateSeqs.sublist(
        i,
        min(i + 500, candidateSeqs.length),
      );
      final recResp = await postRestoreTransport.postSyncReceipts(
        hubUrl: hubUrl,
        token: currentToken,
        deviceId: deviceId,
        clientSeqs: batch,
        timeout: requestTimeout,
      );
      if (!recResp.isSuccess) {
        return PostRestoreReconcileOutcome(
          reconcileRequired: true,
          error: recResp.errorMessage ??
              'Makbuz doğrulaması başarısız (HTTP ${recResp.statusCode}).',
        );
      }
      final recBody = jsonDecode(recResp.body) as Map<String, dynamic>;
      final receipts = (recBody['receipts'] as List?) ?? const [];
      for (final r in receipts) {
        if (r is Map && r['status'] == 'NOT_FOUND') {
          final seq = (r['client_seq'] as num?)?.toInt();
          if (seq != null && seq > 0) {
            missingSeqs.add(seq);
          }
        }
      }
    }

    if (missingSeqs.isEmpty) {
      return PostRestoreReconcileOutcome(
        reconcileRequired: true,
        targetEpoch: hubRestoreEpoch,
      );
    }

    try {
      final requeued = await repository.requeueOperationsForPostRestore(
        deviceId: deviceId,
        missingSeqs: missingSeqs,
      );
      return PostRestoreReconcileOutcome(
        reconcileRequired: true,
        requeuedCount: requeued,
        targetEpoch: hubRestoreEpoch,
      );
    } on PostRestoreHistoryMissingException catch (e) {
      return PostRestoreReconcileOutcome(
        reconcileRequired: true,
        historyMissing: true,
        error: e.message,
      );
    }
  }

  /// S5A-3: Henüz Hub'a iletilmemiş veya onaylanmamış bekleyen ürün sync oturumunu ACK eder
  Future<bool> _tryAcknowledgePendingSyncSession() async {
    final syncState = await repository.getSyncState(deviceId);
    final pendingId = syncState?.pendingSyncSessionId;
    if (pendingId == null || pendingId.isEmpty) return true;

    final String? currentToken;
    try {
      currentToken =
          readDeviceToken != null ? readDeviceToken!() : deviceToken;
    } catch (_) {
      return false;
    }
    if (currentToken == null || currentToken.isEmpty) return false;

    final resp = await transport.postSyncAck(
      hubUrl: hubUrl,
      token: currentToken,
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

  /// S5A-3 + MMS-001 + MMS-005: Merkezi sunucudaki güncel kategori, ürün ve fiyat
  /// listesini (büyük kataloglarda sayfalı olarak) çeker ve yerel cache'i atomik olarak günceller.
  Future<int> syncProducts({DateTime? now}) async {
    final effectiveNow = now ?? DateTime.now();

    // Varsa önceki tamamlanmamış ACK'yı gönder
    await _tryAcknowledgePendingSyncSession();

    final String? currentToken;
    try {
      currentToken =
          readDeviceToken != null ? readDeviceToken!() : deviceToken;
    } catch (_) {
      throw StateError('Cihaz yetkilendirme anahtarı okunamadı.');
    }
    if (currentToken == null || currentToken.isEmpty) {
      throw StateError('Cihaz yetkilendirme anahtarı (deviceToken) eksik veya boş.');
    }

    final effectiveCatalogTimeout =
        catalogSyncTimeout > requestTimeout ? catalogSyncTimeout : requestTimeout;
    final pageLimit = catalogPageSize > 0 ? catalogPageSize : 1000;

    final categoriesById = <String, LocalCategoriesCompanion>{};
    final productCompanions = <LocalProductsCompanion>[];
    final barcodeCompanions = <LocalProductBarcodesCompanion>[];
    String? syncSessionId;

    void collectCatalogPage(Map<String, dynamic> data) {
      final rawCategories = data['categories'] as List<dynamic>? ?? const [];
      for (final rawCat in rawCategories) {
        if (rawCat is! Map) continue;
        final cMap = Map<String, dynamic>.from(rawCat);
        final catId = (cMap['id'] as String?)?.trim();
        final catName = (cMap['name'] as String?)?.trim();
        if (catId == null || catId.isEmpty || catName == null || catName.isEmpty) {
          continue;
        }
        final rawParentId = (cMap['parent_id'] as String?)?.trim();
        final parentId =
            (rawParentId == null || rawParentId.isEmpty) ? null : rawParentId;
        final isActive = cMap['is_active'] as bool? ?? true;
        final createdAt = DateTime.tryParse(cMap['created_at'] as String? ?? '') ??
            effectiveNow;
        final updatedAt = DateTime.tryParse(cMap['updated_at'] as String? ?? '') ??
            effectiveNow;

        categoriesById[catId] = LocalCategoriesCompanion(
          id: Value(catId),
          name: Value(catName),
          parentId: Value(parentId),
          isActive: Value(isActive),
          createdAt: Value(createdAt),
          updatedAt: Value(updatedAt),
        );
      }

      final productsJson = data['products'] as List<dynamic>? ?? const [];
      final pageSessionId = data['sync_session_id'] as String?;
      if (pageSessionId != null && pageSessionId.isNotEmpty) {
        syncSessionId = pageSessionId;
      }

      for (final p in productsJson) {
        final pMap = p as Map<String, dynamic>;
        final pId = pMap['id'] as String;
        final rawPrimaryBarcode = (pMap['barcode'] as String?)?.trim();
        final pBarcode = (rawPrimaryBarcode == null ||
                rawPrimaryBarcode.isEmpty ||
                rawPrimaryBarcode == pId)
            ? null
            : rawPrimaryBarcode;
        final isActive = pMap['is_active'] as bool? ?? true;
        final priceVersionId = pMap['price_version_id'] as String? ?? 'pv_init';
        final hasCategoryId = pMap.containsKey('category_id');
        final rawCategoryId = (pMap['category_id'] as String?)?.trim();
        final effectiveCategoryId =
            (rawCategoryId == null || rawCategoryId.isEmpty)
                ? null
                : rawCategoryId;

        productCompanions.add(LocalProductsCompanion(
          id: Value(pId),
          barcode: Value(pBarcode),
          name: Value(pMap['name'] as String),
          categoryId: hasCategoryId
              ? Value(effectiveCategoryId)
              : const Value.absent(),
          price: Value(pMap['price'] as int),
          priceVersionId: Value(priceVersionId),
          stock: Value(pMap['stock'] as int),
          stockUnit: Value(pMap['stock_unit'] as String? ?? 'adet'),
          pricingUnit: Value(pMap['pricing_unit'] as String? ?? 'adet'),
          conversionFactorNumerator:
              Value(pMap['conversion_factor_numerator'] as int? ?? 1),
          conversionFactorDenominator:
              Value(pMap['conversion_factor_denominator'] as int? ?? 1),
          // Hub şeması KDV oranı taşımıyorsa yerel oran korunur (20'ye sıfırlanmaz).
          vatRate: pMap['vat_rate'] is int
              ? Value(pMap['vat_rate'] as int)
              : const Value.absent(),
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

        // Ek alternatif barkodlar varsa SSOT tablosuna ekle (Hub prodId placeholder'ı atlanır)
        final extraBarcodes = pMap['barcodes'] as List<dynamic>?;
        if (extraBarcodes != null) {
          for (var i = 0; i < extraBarcodes.length; i++) {
            final extraBc = extraBarcodes[i].toString().trim();
            if (extraBc.isEmpty || extraBc == pId || extraBc == pBarcode) {
              continue;
            }
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

    if (transport is CatalogExtendedSyncTransport) {
      final pagedTransport = transport as CatalogExtendedSyncTransport;
      var offset = 0;
      while (true) {
        final resp = await pagedTransport.getProductsPage(
          hubUrl: hubUrl,
          token: currentToken,
          limit: pageLimit,
          offset: offset,
          timeout: effectiveCatalogTimeout,
        );
        if (!resp.isSuccess) {
          if (resp.isTlsPinMismatch) {
            throw StateError(
              'Ürün senkronizasyonu TLS hatası [TLS_PIN_MISMATCH]: ${resp.errorMessage}',
            );
          }
          if (resp.isTlsCertError) {
            throw StateError(
              'Ürün senkronizasyonu TLS hatası [TLS_CERT_ERROR]: ${resp.errorMessage}',
            );
          }
          throw StateError(
            'Ürün senkronizasyonu başarısız oldu [${resp.statusCode}]: ${resp.errorMessage ?? resp.body}',
          );
        }

        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        collectCatalogPage(data);

        final hasMore = data['has_more'] == true;
        final pageProducts = data['products'] as List<dynamic>? ?? const [];
        final nextOffset =
            (data['next_offset'] as num?)?.toInt() ?? (offset + pageProducts.length);
        if (!hasMore || pageProducts.isEmpty || nextOffset <= offset) {
          break;
        }
        offset = nextOffset;
      }
    } else {
      final resp = await transport.getProducts(
        hubUrl: hubUrl,
        token: currentToken,
        timeout: effectiveCatalogTimeout,
      );

      if (!resp.isSuccess) {
        if (resp.isTlsPinMismatch) {
          throw StateError(
            'Ürün senkronizasyonu TLS hatası [TLS_PIN_MISMATCH]: ${resp.errorMessage}',
          );
        }
        if (resp.isTlsCertError) {
          throw StateError(
            'Ürün senkronizasyonu TLS hatası [TLS_CERT_ERROR]: ${resp.errorMessage}',
          );
        }
        throw StateError(
          'Ürün senkronizasyonu başarısız oldu [${resp.statusCode}]: ${resp.errorMessage ?? resp.body}',
        );
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      collectCatalogPage(data);
    }

    // Atomik SQLite transaction: Kategoriler (FK sırası) + Ürünler + Barkodlar
    // birlikte güncellenir (yarım kalan sync cache'i bozamaz).
    final categoryCompanions = categoriesById.values.toList(growable: false);
    await repository.db.transaction(() async {
      if (categoryCompanions.isNotEmpty) {
        await repository.upsertCategories(categoryCompanions);
      }
      await repository.upsertProducts(
        productCompanions,
        barcodes: barcodeCompanions,
        deactivateRemovedBarcodes: true,
      );
    });

    final syncState = await repository.getSyncState(deviceId);
    if (syncState == null) {
      await repository.initializeDevice(deviceId);
    }

    // Yerel commit tamamlandı: Henüz sunucuya ACK gönderilmeden önce pendingSyncSessionId kaydet
    final completedSessionId = syncSessionId;
    await (repository.db.update(repository.db.clientSyncStates)..where((s) => s.deviceId.equals(deviceId))).write(
          ClientSyncStatesCompanion(
            pendingSyncSessionId: Value(completedSessionId),
            updatedAt: Value(effectiveNow),
          ),
        );

    // 2. Aşama: İstemci yerel veritabanına başarıyla yazdıktan sonra Hub'a authenticated ACK gönderir
    if (completedSessionId != null && completedSessionId.isNotEmpty) {
      final ackResp = await transport.postSyncAck(
        hubUrl: hubUrl,
        token: currentToken,
        syncSessionId: completedSessionId,
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

  /// Hub'dan satışları cursor tabanlı olarak indirir ve yerel SQLite'a işler.
  /// Echo prevention: İndirilen satışlar asla outbox'a eklenmez.
  /// Monotonik server_seq cursor'ı sayesinde satış iptalleri ve iadeleri de eksiksiz yakalanır.
  Future<int> syncSales({
    DateTime? now,
    int limit = 50,
  }) async {
    final effectiveNow = now ?? DateTime.now();

    final String? currentToken;
    try {
      currentToken = readDeviceToken != null ? readDeviceToken!() : deviceToken;
    } catch (e) {
      return 0;
    }

    if (currentToken == null || currentToken.isEmpty) {
      return 0;
    }

    var syncState = await repository.getSyncState(deviceId);
    if (syncState == null) {
      syncState = await repository.initializeDevice(deviceId);
    }

    var currentCursor = syncState.lastServerSaleSeq;
    var totalDownloaded = 0;
    var hasMore = true;

    while (hasMore) {
      final resp = await transport.getSales(
        hubUrl: hubUrl,
        token: currentToken,
        cursor: currentCursor,
        limit: limit,
        timeout: requestTimeout,
      );

      if (!resp.isSuccess) {
        if (resp.isTlsPinMismatch) {
          throw StateError('Satış senkronizasyonu TLS hatası [TLS_PIN_MISMATCH]: ${resp.errorMessage}');
        }
        if (resp.isTlsCertError) {
          throw StateError('Satış senkronizasyonu TLS hatası [TLS_CERT_ERROR]: ${resp.errorMessage}');
        }
        break;
      }

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final rawSales = body['sales'] as List<dynamic>? ?? [];
      final nextCursor = body['next_cursor'] as int? ?? currentCursor;
      hasMore = body['has_more'] as bool? ?? false;

      if (rawSales.isNotEmpty) {
        final salesPayloads = rawSales
            .map((s) => DownloadedSalePayload.fromJson(s as Map<String, dynamic>))
            .toList();

        await repository.upsertSales(
          sales: salesPayloads,
          newCursor: nextCursor,
          deviceId: deviceId,
          syncedAt: effectiveNow,
        );

        totalDownloaded += salesPayloads.length;
      } else {
        if (nextCursor > currentCursor) {
          await (repository.db.update(repository.db.clientSyncStates)
                ..where((s) => s.deviceId.equals(deviceId)))
              .write(
            ClientSyncStatesCompanion(
              lastServerSaleSeq: Value(nextCursor),
              lastSalesSyncAt: Value(effectiveNow),
              updatedAt: Value(effectiveNow),
            ),
          );
        }
      }

      currentCursor = nextCursor;

      if (rawSales.isEmpty) {
        break;
      }
    }

    return totalDownloaded;
  }
}
