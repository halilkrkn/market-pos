import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../lib/backup/hub_backup_oauth_service.dart';
import '../lib/backup/hub_backup_oauth_store.dart';
import '../lib/backup/hub_backup_orchestrator.dart';
import '../lib/backup/hub_backup_state_store.dart';
import '../lib/backup/hub_recovery_key_store.dart';
import '../lib/backup/hub_restore_service.dart';
import '../lib/backup/hub_snapshot_service.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/auth_middleware.dart';
import '../lib/security/body_limit_middleware.dart';
import '../lib/security/certificate_manager.dart';
import '../lib/security/live_drive_secret_manager.dart';
import '../lib/security/pairing_delivery_buffer.dart';
import '../lib/security/pairing_manager.dart';
import '../lib/security/pepper_manager.dart';
import '../lib/security/replay_protection_service.dart';
import '../lib/security/secure_cors_middleware.dart';
import '../lib/security/token_manager.dart';
import '../lib/service/admission_gate.dart';
import '../lib/service/lifecycle_manager.dart';
import '../lib/discovery/discovery_responder.dart';
import '../lib/config/hub_config.dart';
import '../lib/network/hub_lan_address_resolver.dart';
import '../lib/sync/canonical_payload_hasher.dart';
import '../lib/sync/device_sequence_inspector.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

void configureSqliteNative() {
  // Dart Native Assets (sqlite3 3.x): SQLite C ikilisi derleme kancaları (build hooks)
  // aracılığıyla platforma göre otomatik bağlanır. Manuel override gerekmez.
}

class _IdempotencyConflictException implements Exception {
  final String idempotencyKey;
  _IdempotencyConflictException(this.idempotencyKey);
}

class _IdempotencyHashUnverifiableException implements Exception {
  final String idempotencyKey;
  _IdempotencyHashUnverifiableException(this.idempotencyKey);
}

class _SequenceGapException implements Exception {
  final String deviceId;
  final int expectedSeq;
  final int receivedSeq;
  final int highWaterMarkSeq;
  final int maxSeenSeq;

  _SequenceGapException({
    required this.deviceId,
    required this.expectedSeq,
    required this.receivedSeq,
    required this.highWaterMarkSeq,
    required this.maxSeenSeq,
  });
}

class _MutationTxResult {
  final bool isReplay;
  final String bodyJson;

  const _MutationTxResult({
    required this.isReplay,
    required this.bodyJson,
  });
}

class _ValidationException implements Exception {
  final int statusCode;
  final String code;
  final String message;
  _ValidationException(this.statusCode, this.code, this.message);
}

class SpikeServer {
  static const String defaultTenantId = 'default-tenant';
  static const String defaultStoreId = 'default-store';
  static const String defaultHubId = 'MMS-HUB-MASTER';

  SpikeDatabase db;
  final File? dbFile;
  final WriteQueue writeQueue;
  final LifecycleManager lifecycle;
  final String? backupDirectory;
  final String? adminSecret;
  final PepperManager pepperManager;
  final LiveDriveSecretManager liveDriveSecretManager;
  final SecurityContext? securityContext;
  final bool requireTls;
  final PairingManager pairingManager;
  final String? caCertPath;
  final String? serverCertPath;
  final String? advertiseHost;
  final HubLanAddressResolver? lanAddressResolver;
  final String tenantId;
  final String storeId;
  final String hubId;
  final bool requireTenantStoreHeaders;

  /// Faz 3: Zamanlanmış şifreli Hub yedeği politikası (`null`/kapalı → zamanlama yok).
  final BackupSchedulePolicy? backupSchedule;

  /// Zamanlayıcının "yedek zamanı geldi mi?" kontrol aralığı.
  final Duration backupCheckInterval;

  /// Merkezi restore öncesi safety snapshot'ın PBKDF2 tur sayısı. Yalnızca sunucu
  /// yapılandırmasından (testlerde hızlandırma için) gelir; istek gövdesiyle
  /// ZAYIFLATILAMAZ.
  final int hubRestoreSafetyKdfIterations;

  static const String backupScheduleStateFileName = 'backup_schedule_state.json';

  final bool allowAdminEnvFallback;
  final Map<String, String>? _environment;
  final String backupOAuthClientId;
  final String? backupOAuthClientSecret;
  late final HubBackupOAuthService hubBackupOAuthService;
  late final HubRecoveryKeyStore hubRecoveryKeyStore;
  late final HubBackupStateStore hubBackupStateStore;
  late final HubBackupOrchestrator hubBackupOrchestrator;
  late final ReplayProtectionService replayProtectionService;
  late final Router _router;
  HttpServer? _httpServer;
  Timer? _pairingCleanupTimer;
  HubDiscoveryResponder? _discoveryResponder;
  BackupScheduler? _backupScheduler;
  BackupScheduleState? _backupScheduleState;
  bool _resourcesStopped = false;

  /// Son bilinen zamanlanmış yedek durumu (izleme ve testler için).
  BackupScheduleState? get backupScheduleState => _backupScheduleState;

  /// Durum dosyası DB ile aynı (servis tarafından yazılabilir) dizinde tutulur;
  /// yedek hedefi erişilemez olsa bile hata kaydı kaybolmaz.
  File get backupScheduleStateFile => File(p.join(
        (dbFile ?? File(p.join(Directory.current.path, 'market_master.db'))).parent.path,
        backupScheduleStateFileName,
      ));

  Directory get _backupTargetDir =>
      Directory(backupDirectory ?? p.join(Directory.current.path, 'backups'));

  /// BK-LOCK: Hub manuel/zamanlanmış yedekleme ve restore işlemleri aynı kilit
  /// dosyasını paylaşır; eşzamanlı çalışma engellenir.
  File get backupOperationLockFile =>
      File(p.join(_backupTargetDir.path, BackupOperationLock.defaultFileName));

  BackupOperationLock get _backupOperationLock =>
      BackupOperationLock(backupOperationLockFile);

  HubDiscoveryResponder? get discoveryResponder => _discoveryResponder;

  static final Random _secureRandom = Random.secure();

  SpikeServer({
    required this.db,
    required this.writeQueue,
    this.dbFile,
    this.backupDirectory,
    this.adminSecret,
    PepperManager? pepperManager,
    LiveDriveSecretManager? liveDriveSecretManager,
    this.securityContext,
    this.requireTls = false,
    PairingManager? pairingManager,
    this.caCertPath,
    this.serverCertPath,
    this.advertiseHost,
    this.lanAddressResolver,
    LifecycleManager? lifecycle,
    String? tenantId,
    String? storeId,
    String? hubId,
    this.requireTenantStoreHeaders = false,
    this.backupSchedule,
    this.backupCheckInterval = const Duration(minutes: 5),
    this.hubRestoreSafetyKdfIterations = MmsbakV2Crypto.defaultPbkdf2Iterations,
    this.allowAdminEnvFallback = true,
    Map<String, String>? environment,
    String? backupOAuthClientId,
    String? backupOAuthClientSecret,
    HubBackupOAuthService? hubBackupOAuthService,
    HubRecoveryKeyStore? hubRecoveryKeyStore,
    HubBackupStateStore? hubBackupStateStore,
    HubBackupOrchestrator? hubBackupOrchestrator,
    ReplayProtectionService? replayProtectionService,
  })  : _environment = environment,
        backupOAuthClientId = backupOAuthClientId ??
            (environment ?? Platform.environment)['MMS_GDRIVE_CLIENT_ID'] ??
            (environment ?? Platform.environment)['GOOGLE_OAUTH_CLIENT_ID'] ??
            '',
        backupOAuthClientSecret = backupOAuthClientSecret ??
            (environment ?? Platform.environment)['MMS_GDRIVE_CLIENT_SECRET'] ??
            (environment ?? Platform.environment)['GOOGLE_OAUTH_CLIENT_SECRET'],
        pepperManager = _resolvePepperManager(pepperManager),
        liveDriveSecretManager = _resolveLiveDriveSecretManager(
          liveDriveSecretManager,
          pepperManager?.file,
          dbFile,
        ),
        pairingManager = pairingManager ?? PairingManager(),
        lifecycle = lifecycle ?? LifecycleManager(db: db, writeQueue: writeQueue),
        tenantId = (tenantId != null && tenantId.trim().isNotEmpty)
            ? tenantId.trim()
            : defaultTenantId,
        storeId = (storeId != null && storeId.trim().isNotEmpty)
            ? storeId.trim()
            : defaultStoreId,
        hubId = (hubId != null && hubId.trim().isNotEmpty)
            ? hubId.trim()
            : defaultHubId {
    final callerHook = this.lifecycle.onBeforeDrain;
    this.lifecycle.onBeforeDrain = () async {
      await _stopServerResources();
      if (callerHook != null) {
        await callerHook();
      }
    };
    this.hubBackupOAuthService = hubBackupOAuthService ??
        HubBackupOAuthService(
          store: HubBackupOAuthStore(
            File(p.join(_resolveSecurityDirPath(), HubBackupOAuthStore.defaultFileName)),
          ),
          httpClient: http.Client(),
        );
    this.hubRecoveryKeyStore = hubRecoveryKeyStore ??
        HubRecoveryKeyStore(
          File(p.join(_resolveSecurityDirPath(), HubRecoveryKeyStore.defaultFileName)),
        );
    this.hubBackupStateStore = hubBackupStateStore ??
        HubBackupStateStore(
          File(p.join(_backupTargetDir.path, HubBackupStateStore.defaultFileName)),
        );
    this.hubBackupOrchestrator = hubBackupOrchestrator ??
        HubBackupOrchestrator(
          snapshotService: HubSnapshotService(
            readDb: () => db,
            writeQueue: writeQueue,
            liveDbFile: dbFile ?? File(p.join(Directory.current.path, 'market_master.db')),
            backupDir: _backupTargetDir,
            hubId: this.hubId,
            tenantId: this.tenantId,
            storeId: this.storeId,
            appVersion: '1.0.0',
          ),
          stateStore: this.hubBackupStateStore,
          recoveryKeyStore: this.hubRecoveryKeyStore,
          oauthService: this.hubBackupOAuthService,
          uploader: ResumableDriveUploader(
            accessTokenProvider: ({bool forceRefresh = false}) =>
                this.hubBackupOAuthService.getValidAccessToken(
                      clientId: this.backupOAuthClientId,
                      clientSecret: this.backupOAuthClientSecret,
                      forceRefresh: forceRefresh,
                    ),
            httpClient: http.Client(),
            // S5: Merkezi Hub yedekleri eski istemci yedeklerinden ayrı alt klasöre
            // (`MARKET MMS Yedekleri/Hub`) yüklenir ve kaynak işareti taşır.
            folderName: MmsDriveBackupFolders.rootFolderName,
            subfolderName: MmsDriveBackupFolders.hubSubfolderName,
            extraAppProperties: const {
              MmsDriveBackupFolders.backupSourceProperty:
                  MmsDriveBackupFolders.hubBackupSource,
            },
          ),
          operationLock: _backupOperationLock,
          readSchemaVersion: () => db.schemaVersion,
          oauthClientId: this.backupOAuthClientId,
          oauthClientSecret: this.backupOAuthClientSecret,
        );
    this.replayProtectionService =
        replayProtectionService ?? ReplayProtectionService();
    _setupRoutes();
  }

  String _resolveSecurityDirPath() {
    final pepperFile = pepperManager.file;
    if (pepperFile.isAbsolute || pepperFile.path != 'pepper.dpapi') {
      return pepperFile.parent.path;
    }
    if (dbFile != null) {
      return dbFile!.parent.path;
    }
    return _backupTargetDir.path;
  }

  Future<void> _stopServerResources() async {
    if (_resourcesStopped) return;
    _resourcesStopped = true;
    await Future.wait<void>([
      hubBackupOrchestrator.shutdown(),
      if (_backupScheduler != null) _backupScheduler!.stop(),
    ]);
    _backupScheduler = null;
    _pairingCleanupTimer?.cancel();
    _pairingCleanupTimer = null;
    await _discoveryResponder?.stop();
    _discoveryResponder = null;
  }

  static PepperManager _resolvePepperManager(PepperManager? provided) {
    if (provided != null) {
      try {
        final _ = provided.pepper;
      } catch (_) {
        provided.initialize();
      }
      return provided;
    }
    final pepperPath = Platform.environment['PEPPER_FILE'] ?? 'pepper.dpapi';
    final pm = PepperManager(File(pepperPath));
    pm.initialize();
    return pm;
  }

  static LiveDriveSecretManager _resolveLiveDriveSecretManager(
    LiveDriveSecretManager? provided,
    File? pepperFileHint,
    File? dbFile,
  ) {
    if (provided != null) {
      try {
        final _ = provided.secret;
      } catch (_) {
        provided.initialize();
      }
      return provided;
    }
    if (dbFile == null) {
      final mgr = LiveDriveSecretManager.inMemory();
      mgr.initialize();
      return mgr;
    }
    final usePepperDir = pepperFileHint != null &&
        (pepperFileHint.isAbsolute || pepperFileHint.path != 'pepper.dpapi');
    final baseDir = usePepperDir
        ? pepperFileHint.parent.path
        : dbFile.parent.path;
    final mgr = LiveDriveSecretManager(
      File(p.join(baseDir, 'live_drive_sync_secret.dpapi')),
    );
    mgr.initialize();
    return mgr;
  }

  /// Zamanlama saldırılarını (timing attack) önleyen sabit zamanlı byte karşılaştırması
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  /// S5A-2: Satış işlem yükünün (payload) kanonik SHA-256 hash özetini üretir (Legacy v1 uyumluluğu)
  static String computeSaleRequestHash(Map<String, dynamic> body) {
    return CanonicalPayloadHasher.computeLegacyV1SaleHash(body);
  }

  /// BK-02.1: Pilot tek-tenant / tek-store Hub kimliğini `hub_metadata` ile doğrular veya ilk açılışta mühürler.
  Future<void> _verifyOrInitializeHubIdentity() async {
    await writeQueue.enqueue(() async {
      await db.transaction(() async {
        final existingTenant = await (db.select(db.hubMetadata)
              ..where((m) => m.key.equals('tenant_id')))
            .getSingleOrNull();
        final existingStore = await (db.select(db.hubMetadata)
              ..where((m) => m.key.equals('store_id')))
            .getSingleOrNull();

        if (existingTenant != null && existingTenant.value != tenantId) {
          throw StateError(
            'Hub Tenant Kimlik Uyuşmazlığı (Fail-Closed): DB tenant_id=${existingTenant.value}, yapılandırma=$tenantId.',
          );
        }
        if (existingStore != null && existingStore.value != storeId) {
          throw StateError(
            'Hub Store Kimlik Uyuşmazlığı (Fail-Closed): DB store_id=${existingStore.value}, yapılandırma=$storeId.',
          );
        }

        final now = DateTime.now();
        if (existingTenant == null) {
          await db.into(db.hubMetadata).insert(
                HubMetadataCompanion(
                  key: const Value('tenant_id'),
                  value: Value(tenantId),
                  updatedAt: Value(now),
                ),
              );
        }
        if (existingStore == null) {
          await db.into(db.hubMetadata).insert(
                HubMetadataCompanion(
                  key: const Value('store_id'),
                  value: Value(storeId),
                  updatedAt: Value(now),
                ),
              );
        }
        await db.into(db.hubMetadata).insertOnConflictUpdate(
              HubMetadataCompanion(
                key: const Value('hub_id'),
                value: Value(hubId),
                updatedAt: Value(now),
              ),
            );
      });
    });
  }

  Response _idempotencyConflictResponse(String idempotencyKey) {
    return Response(
      409,
      body: jsonEncode({
        'error': 'CONFLICT',
        'code': 'ERR_IDEMPOTENCY_PAYLOAD_MISMATCH',
        'message':
            'Aynı idempotency key ($idempotencyKey) farklı bir işlem yükü ile tekrar gönderilemez.',
        'idempotency_key': idempotencyKey,
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _idempotencyHashUnverifiableResponse(String idempotencyKey) {
    return Response(
      409,
      body: jsonEncode({
        'error': 'CONFLICT',
        'code': 'ERR_IDEMPOTENCY_HASH_UNVERIFIABLE',
        'message':
            'Mevcut makbuz kaydının hash bilgisi eksik veya doğrulanamıyor ($idempotencyKey); güvenli replay reddedildi.',
        'idempotency_key': idempotencyKey,
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _sequenceGapResponse(_SequenceGapException e) {
    return Response(
      409,
      body: jsonEncode({
        'error': 'CONFLICT',
        'code': 'ERR_CLIENT_SEQ_GAP',
        'message':
            'Beklenmeyen client_seq (${e.receivedSeq}). Cihaz (${e.deviceId}) için beklenen ardışık sıra numarası: ${e.expectedSeq}.',
        'device_id': e.deviceId,
        'expected_client_seq': e.expectedSeq,
        'received_client_seq': e.receivedSeq,
        'high_water_mark_seq': e.highWaterMarkSeq,
        'max_seen_client_seq': e.maxSeenSeq,
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _validationErrorResponse(_ValidationException e) {
    final errorType = e.statusCode == 404
        ? 'NOT_FOUND'
        : (e.statusCode == 409 ? 'CONFLICT' : 'BAD_REQUEST');
    return Response(
      e.statusCode,
      body: jsonEncode({
        'error': errorType,
        'code': e.code,
        'message': e.message,
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// Hedef satışı önce doğrudan Hub ID ile, bulunamazsa `(device_id, target_client_seq)`
  /// ile çözümler. Bulunamazsa veya referans belirsizse fail-closed hata fırlatır.
  Future<Sale> _resolveTargetSaleInTx({
    required String deviceId,
    required String? rawSaleId,
    required int? targetClientSeq,
  }) async {
    final trimmedSaleId = rawSaleId?.trim();
    if (trimmedSaleId != null && trimmedSaleId.isNotEmpty) {
      final direct = await (db.select(db.sales)
            ..where((s) => s.id.equals(trimmedSaleId)))
          .getSingleOrNull();
      if (direct != null) {
        return direct;
      }
    }

    if (targetClientSeq != null) {
      final matches = await (db.select(db.sales)
            ..where((s) =>
                s.deviceId.equals(deviceId) & s.clientSeq.equals(targetClientSeq)))
          .get();
      if (matches.length == 1) {
        return matches.first;
      }
      if (matches.length > 1) {
        throw _ValidationException(
          409,
          'ERR_AMBIGUOUS_SALE_REFERENCE',
          'Hedef satış referansı belirsiz: device_id=$deviceId client_seq=$targetClientSeq için ${matches.length} satış bulundu.',
        );
      }
      throw _ValidationException(
        404,
        'ERR_SALE_NOT_FOUND',
        'Hedef satış bulunamadı (sale_id=$rawSaleId, device_id=$deviceId, target_client_seq=$targetClientSeq).',
      );
    }

    throw _ValidationException(
      404,
      'ERR_SALE_NOT_FOUND',
      'Hedef satış bulunamadı (sale_id=$rawSaleId).',
    );
  }

  /// İade kalemini orijinal satışın `sale_items` listesiyle eşleştirir.
  SaleItem? _matchSaleItem(
    List<SaleItem> saleItems, {
    String? saleItemId,
    String? productId,
  }) {
    final cleanItemId = saleItemId?.trim();
    if (cleanItemId != null && cleanItemId.isNotEmpty) {
      for (final si in saleItems) {
        if (si.id == cleanItemId) {
          if (productId != null &&
              productId.trim().isNotEmpty &&
              si.productId != productId.trim()) {
            throw _ValidationException(
              400,
              'ERR_INVALID_REFUND_ITEM',
              'sale_item_id ($cleanItemId) ile product_id ($productId) birbiriyle uyuşmuyor.',
            );
          }
          return si;
        }
      }
    }

    final cleanProductId = productId?.trim();
    if (cleanProductId != null && cleanProductId.isNotEmpty) {
      for (final si in saleItems) {
        if (si.productId == cleanProductId) {
          return si;
        }
      }
    }

    return null;
  }

  /// Ürün için fiyat sürümü tarihçe kaydını (çakışma korumalı anahtar dahil) döner.
  Future<ProductPriceHistory?> _findPriceHistoryVersionInTx({
    required String productId,
    required String priceVersionId,
  }) async {
    final scopedId = '$productId::$priceVersionId';
    return (db.select(db.productPriceHistories)
          ..where((h) =>
              h.productId.equals(productId) &
              (h.id.equals(priceVersionId) | h.id.equals(scopedId))))
        .getSingleOrNull();
  }

  /// Fiyat sürümünü `product_price_histories` tablosuna çakışmasız olarak ekler.
  /// Aynı `id` başka ürüne aitse (örn. varsayılan `pv_init`), `$productId::$priceVersionId`
  /// kapsamlı anahtarı kullanılır (şema değişikliği gerektirmez).
  Future<void> _insertPriceHistoryVersionIfAbsentInTx({
    required String productId,
    required String priceVersionId,
    required int price,
    required DateTime validFrom,
    DateTime? validUntil,
    required DateTime createdAt,
  }) async {
    final existingForProduct = await _findPriceHistoryVersionInTx(
      productId: productId,
      priceVersionId: priceVersionId,
    );
    if (existingForProduct != null) {
      if (validUntil != null && existingForProduct.validUntil == null) {
        await (db.update(db.productPriceHistories)
              ..where((h) => h.id.equals(existingForProduct.id)))
            .write(ProductPriceHistoriesCompanion(validUntil: Value(validUntil)));
      }
      return;
    }

    final collision = await (db.select(db.productPriceHistories)
          ..where((h) => h.id.equals(priceVersionId)))
        .getSingleOrNull();
    final storageId =
        collision == null ? priceVersionId : '$productId::$priceVersionId';

    await db.into(db.productPriceHistories).insert(
          ProductPriceHistoriesCompanion(
            id: Value(storageId),
            productId: Value(productId),
            price: Value(price),
            validFrom: Value(validFrom),
            validUntil: Value(validUntil),
            createdAt: Value(createdAt),
          ),
        );
  }

  Response _evaluateExistingReceipt({
    required ProcessedOperation existingOp,
    required String operationType,
    required Map<String, dynamic> incomingBody,
    required String rawBody,
    required String idempotencyKey,
  }) {
    Map<String, dynamic>? cachedJson;
    try {
      final decoded = jsonDecode(existingOp.resultPayload);
      if (decoded is Map<String, dynamic>) {
        cachedJson = decoded;
      }
    } catch (_) {
      cachedJson = null;
    }

    final match = CanonicalPayloadHasher.verifyAgainstStoredReceipt(
      operationType: operationType,
      incomingBody: incomingBody,
      rawBody: rawBody,
      storedClientSeq: existingOp.clientSeq,
      storedOperationType: existingOp.operationType,
      storedRequestHash: existingOp.requestHash,
      storedHashVersion: existingOp.hashVersion,
      cachedResultPayload: cachedJson,
    );

    switch (match) {
      case ReceiptHashMatchResult.matched:
        return Response.ok(
          existingOp.resultPayload,
          headers: {
            'content-type': 'application/json',
            'x-mms-idempotent-replay': 'true',
          },
        );
      case ReceiptHashMatchResult.mismatched:
        return _idempotencyConflictResponse(idempotencyKey);
      case ReceiptHashMatchResult.unverifiable:
        return _idempotencyHashUnverifiableResponse(idempotencyKey);
    }
  }

  Future<_MutationTxResult?> _checkExistingReceiptInTx({
    required String idempotencyKey,
    required String operationType,
    required Map<String, dynamic> incomingBody,
    required String rawBody,
  }) async {
    final checkAgain = await (db.select(db.processedOperations)
          ..where((o) => o.idempotencyKey.equals(idempotencyKey)))
        .getSingleOrNull();
    if (checkAgain == null) return null;

    Map<String, dynamic>? cachedJson;
    try {
      final decoded = jsonDecode(checkAgain.resultPayload);
      if (decoded is Map<String, dynamic>) {
        cachedJson = decoded;
      }
    } catch (_) {
      cachedJson = null;
    }

    final match = CanonicalPayloadHasher.verifyAgainstStoredReceipt(
      operationType: operationType,
      incomingBody: incomingBody,
      rawBody: rawBody,
      storedClientSeq: checkAgain.clientSeq,
      storedOperationType: checkAgain.operationType,
      storedRequestHash: checkAgain.requestHash,
      storedHashVersion: checkAgain.hashVersion,
      cachedResultPayload: cachedJson,
    );

    switch (match) {
      case ReceiptHashMatchResult.matched:
        return _MutationTxResult(
          isReplay: true,
          bodyJson: checkAgain.resultPayload,
        );
      case ReceiptHashMatchResult.mismatched:
        throw _IdempotencyConflictException(idempotencyKey);
      case ReceiptHashMatchResult.unverifiable:
        throw _IdempotencyHashUnverifiableException(idempotencyKey);
    }
  }

  Future<void> _assertExpectedClientSeqInTx(String deviceId, int clientSeq) async {
    final ops = await (db.select(db.processedOperations)
          ..where((o) => o.deviceId.equals(deviceId) & o.clientSeq.isNotNull()))
        .get();
    final summary = DeviceSequenceInspector.computeFromSeqs(
      ops.map((o) => o.clientSeq!),
    );
    final expectedSeq = summary.expectedNextClientSeq;
    if (clientSeq != expectedSeq) {
      throw _SequenceGapException(
        deviceId: deviceId,
        expectedSeq: expectedSeq,
        receivedSeq: clientSeq,
        highWaterMarkSeq: summary.contiguousHwm,
        maxSeenSeq: summary.maxSeenClientSeq,
      );
    }
  }

  Future<String> _commitReceiptAndAdvanceHwmInTx({
    required String operationId,
    required String deviceId,
    required String idempotencyKey,
    required int clientSeq,
    required String operationType,
    required String canonicalHash,
    required Map<String, dynamic> responsePayload,
    required DateTime committedAt,
  }) async {
    final encodedPayload = jsonEncode(responsePayload);

    await db.into(db.processedOperations).insert(
          ProcessedOperationsCompanion(
            operationId: Value(operationId),
            deviceId: Value(deviceId),
            idempotencyKey: Value(idempotencyKey),
            clientSeq: Value(clientSeq),
            operationType: Value(operationType),
            requestHash: Value(canonicalHash),
            hashVersion: const Value(CanonicalPayloadHasher.hashVersionV2Canonical),
            resultPayload: Value(encodedPayload),
            processedAt: Value(committedAt),
          ),
        );

    await DeviceSequenceInspector.recomputeAndPersistDeviceHwm(
      db,
      deviceId,
      committedAt: committedAt,
    );

    return encodedPayload;
  }

  String? get _effectiveAdminSecret =>
      adminSecret ??
      (allowAdminEnvFallback ? (_environment ?? Platform.environment)['ADMIN_SECRET'] : null);

  Response? _denyIfNotLoopback(Request req, {required String actionName}) {
    final connectionInfo = req.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    if (connectionInfo == null) {
      return Response.forbidden(
        jsonEncode({
          'error': 'FORBIDDEN',
          'code': 'ERR_LOOPBACK_REQUIRED',
          'message': '$actionName için bağlantı bilgisi doğrulanamadı. Yalnızca yerel makineden (loopback) erişilebilir.',
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final remoteAddr = connectionInfo.remoteAddress;
    final isLoopback = remoteAddr.isLoopback ||
        remoteAddr.address == '127.0.0.1' ||
        remoteAddr.address == '::1' ||
        remoteAddr.address == '0:0:0:0:0:0:0:1' ||
        remoteAddr.address == '::ffff:127.0.0.1';
    if (!isLoopback) {
      return Response.forbidden(
        jsonEncode({
          'error': 'FORBIDDEN',
          'code': 'ERR_LOOPBACK_REQUIRED',
          'message': '$actionName için yalnızca yerel makineden (loopback) erişilebilir.',
        }),
        headers: {'content-type': 'application/json'},
      );
    }
    return null;
  }

  /// Hub yönetimi için Loopback ve Admin Secret yetkilendirmesi denetler (Fail-Closed)
  Response? _verifyLoopbackAndAdmin(Request req, {String actionName = 'Bu işlem'}) {
    final loopbackDenied = _denyIfNotLoopback(req, actionName: actionName);
    if (loopbackDenied != null) return loopbackDenied;

    final effectiveAdminSecret = _effectiveAdminSecret;
    if (effectiveAdminSecret == null || effectiveAdminSecret.isEmpty) {
      return Response(
        503,
        body: jsonEncode({
          'error': 'ADMIN_DISABLED',
          'code': 'ERR_ADMIN_NOT_CONFIGURED',
          'message': 'Admin secret yapılandırılmamış ve güvenlik nedeniyle devre dışıdır.',
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final providedAdminSecret = req.headers['x-admin-secret'] ??
        req.headers['x-mms-admin-secret'] ??
        (req.headers['authorization']?.startsWith('Bearer ') == true
            ? req.headers['authorization']!.substring(7).trim()
            : null);

    if (providedAdminSecret == null || providedAdminSecret.isEmpty) {
      return Response(
        401,
        body: jsonEncode({
          'error': 'UNAUTHORIZED',
          'code': 'ERR_ADMIN_SECRET_REQUIRED',
          'message': '$actionName için admin secret gereklidir.',
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    if (!_constantTimeEquals(utf8.encode(providedAdminSecret), utf8.encode(effectiveAdminSecret))) {
      return Response(
        403,
        body: jsonEncode({
          'error': 'FORBIDDEN',
          'code': 'ERR_INVALID_ADMIN_SECRET',
          'message': 'Geçersiz admin secret.',
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    return null;
  }

  Response? _verifyOwnerOrLoopbackAdmin(Request req, {String actionName = 'Bu işlem'}) {
    final deviceId = req.context['authenticated_device_id'] as String?;
    final role = (req.context['authenticated_device_role'] as String?)?.toUpperCase();
    if (deviceId != null) {
      if (role == 'OWNER') {
        return null;
      }
      return Response(
        403,
        body: jsonEncode({
          'error': 'FORBIDDEN',
          'code': 'ERR_OWNER_ROLE_REQUIRED',
          'message': '$actionName için OWNER rolü gereklidir.',
          'device_id': deviceId,
          'role': role ?? 'CASHIER',
        }),
        headers: {'content-type': 'application/json'},
      );
    }
    return _verifyLoopbackAndAdmin(req, actionName: actionName);
  }

  static final RegExp _safeBackupIdPattern = RegExp(r'^[A-Za-z0-9_\-]{1,128}$');

  /// Merkezi restore `package_path` doğrulaması (bkz. `/api/v1/backup/restore`).
  Response? _validateRestorePackagePath(String packagePath, {required bool isRemoteDevice}) {
    Response deny(int status, String code, String message) => Response(
          status,
          body: jsonEncode({'error': 'INVALID_REQUEST', 'code': code, 'message': message}),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
    if (isRemoteDevice) {
      return deny(
        403,
        'ERR_PACKAGE_PATH_LOOPBACK_ONLY',
        'Dosya yolundan geri yükleme yalnızca Hub bilgisayarından yapılabilir; uzak cihazlar backup_id kullanmalıdır.',
      );
    }
    final normalized = packagePath.replaceAll('/', r'\');
    final isUncOrDevice = normalized.startsWith(r'\\');
    if (isUncOrDevice || !p.isAbsolute(packagePath) || packagePath.contains('\x00')) {
      return deny(
        400,
        'ERR_INVALID_PACKAGE_PATH',
        'Yedek paketi yerel ve mutlak bir dosya yolu olmalıdır (ağ/UNC yolu kabul edilmez).',
      );
    }
    return null;
  }

  Future<Map<String, dynamic>> _decodeJsonBodyOrEmpty(Request req) async {
    try {
      final raw = await req.readAsString();
      if (raw.trim().isEmpty) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      stderr.writeln(
        '[WARN] JSON istek gövdesi beklenen nesne biçiminde değil (${req.requestedUri.path}): ${decoded.runtimeType}',
      );
    } catch (e) {
      stderr.writeln(
        '[WARN] JSON istek gövdesi ayrıştırılamadı (${req.requestedUri.path}): ${e.runtimeType}',
      );
    }
    return const {};
  }

  Future<String> _readRestoreEpoch() async {
    try {
      final row = await (db.select(db.hubMetadata)
            ..where((m) => m.key.equals('restore_epoch')))
          .getSingleOrNull();
      final val = row?.value.trim();
      if (val != null && val.isNotEmpty) return val;
    } catch (e) {
      stderr.writeln('[WARN] restore_epoch metadata okunamadı: ${e.runtimeType}');
    }
    return 'epoch_0';
  }

  Future<Response?> _verifyReplayProtection(
    Request req, {
    required String actionName,
  }) async {
    final check = replayProtectionService.verifyAndConsume(
      timestampHeader: req.headers['x-mms-timestamp'],
      nonceHeader: req.headers['x-mms-nonce'],
      scopeKey: req.requestedUri.path,
    );
    if (check.accepted) return null;

    final actorId =
        (req.context['authenticated_device_id'] as String?) ?? 'HUB_ADMIN';
    if (!writeQueue.isDraining) {
      await writeQueue.enqueue(() async {
        await db.into(db.deviceAuditLogs).insert(
              DeviceAuditLogsCompanion(
                deviceId: Value(actorId),
                action: const Value('REPLAY_REJECTED'),
                details: Value('$actionName: ${check.reason}'),
              ),
            );
      }).catchError((_) {});
    }

    return Response(
      403,
      body: jsonEncode({
        'error': 'FORBIDDEN',
        'code': 'ERR_REPLAY_DETECTED',
        'message': '$actionName için replay koruması reddi: ${check.reason}',
      }),
      headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
    );
  }

  /// Kurtarma anahtarı tanımlı değilken parolasız eski S5A-4 yedek/restore çağrısı.
  static const String errRecoveryKeyNotConfigured = 'ERR_RECOVERY_KEY_NOT_CONFIGURED';

  /// Eski S5A-4 yedeklerinde zayıf (12 karakterden kısa) açık parola.
  static const String errWeakRecoveryPassword = 'ERR_WEAK_RECOVERY_PASSWORD';

  /// S5A-4: Merkezi DB'nin şifreli yedeği (manuel admin ucu ve eski aralıklı zamanlayıcı ortak yolu).
  /// VACUUM INTO tek yazıcı kuyruğundan geçer.
  ///
  /// ADR-023 B1.7 / OV-05 / S2: Her zaman Hub üzerinde kayıtlı Portable Recovery Password
  /// (`backup_recovery_key.dpapi`) kullanır; makineye bağlı `pepper.dpapi` veya istek içi
  /// parola kabul edilmez. Tanımlı değilse fail-closed [errRecoveryKeyNotConfigured] fırlatır.
  Future<BackupResult> createEncryptedHubBackup({
    bool isMonthlyArchive = false,
  }) {
    final targetLiveDb = dbFile ?? File(p.join(Directory.current.path, 'market_master.db'));
    return _backupOperationLock.synchronized(
      BackupOperationKind.backup,
      () async {
        final password = await _resolvePortableBackupPassword(
          null,
          enforceMinimumLength: true,
        );
        return DatabaseBackupEngine.createBackup(
          liveDbFile: targetLiveDb,
          executeVacuumInto: (snapPath) async {
            await writeQueue.enqueue(() async {
              final escaped = snapPath.replaceAll("'", "''");
              await db.customStatement("VACUUM INTO '$escaped';");
            });
          },
          deviceId: 'SERVER_HUB',
          tenantId: tenantId,
          storeId: storeId,
          databaseType: DatabaseType.centralMaster,
          schemaVersion: db.schemaVersion,
          appVersion: '1.0.0',
          backupPassword: password,
          storageProvider: LocalStorageProvider(_backupTargetDir),
          isMonthlyArchive: isMonthlyArchive,
        );
      },
    );
  }

  /// Açık parola → (yoksa) Portable Recovery Password kasası. Pepper fallback'i yoktur.
  ///
  /// [enforceMinimumLength] yalnızca YENİ yedek üretiminde uygulanır; eski
  /// (12 karakterden kısa parolayla alınmış) yedeklerin geri yüklenebilirliği korunur.
  Future<String> _resolvePortableBackupPassword(
    String? explicitPassword, {
    required bool enforceMinimumLength,
  }) async {
    if (explicitPassword != null) {
      if (enforceMinimumLength) {
        try {
          MmsbakV2Crypto.validateRecoveryPassword(explicitPassword);
        } on BackupCryptoException catch (e) {
          throw BackupException(errWeakRecoveryPassword, e.message);
        }
      }
      return explicitPassword;
    }
    final String? stored;
    try {
      stored = await hubRecoveryKeyStore.loadRecoveryPassword();
    } on HubRecoveryKeyException catch (e) {
      throw BackupException(e.code, e.message);
    }
    if (stored == null) {
      throw const BackupException(
        errRecoveryKeyNotConfigured,
        'Hub Portable Recovery Password tanımlı değil. Önce POST /api/v1/backup/recovery-key '
        'ile en az 12 karakterlik kurtarma parolası belirleyin.',
      );
    }
    if (enforceMinimumLength) {
      try {
        MmsbakV2Crypto.validateRecoveryPassword(stored);
      } on BackupCryptoException catch (e) {
        throw BackupException(errWeakRecoveryPassword, e.message);
      }
    }
    return stored;
  }

  /// Eski S5A-4 uçlarında [BackupException] kodunu HTTP durumuna eşler.
  static int _legacyBackupErrorStatus(String code, {required int fallback}) {
    if (code == BackupOperationLock.busyErrorCode) return 409;
    if (code == errRecoveryKeyNotConfigured ||
        code == 'ERR_RECOVERY_KEY_CORRUPTED' ||
        code == 'ERR_CORRUPT_RECOVERY_KEY' ||
        code == 'ERR_DPAPI_RECOVERY_KEY' ||
        code == errWeakRecoveryPassword) {
      return 412;
    }
    return fallback;
  }

  /// `/health` için hassas veri (yol, hata ayrıntısı) içermeyen yedek özeti.
  Map<String, dynamic> _publicBackupHealth({
    bool? recoveryKeyConfigured,
  }) {
    final policy = backupSchedule ?? BackupSchedulePolicy.disabled;
    final state = _backupScheduleState ?? BackupScheduleState.empty;
    return {
      'schedule_enabled': policy.enabled,
      'last_success_at': state.lastSuccessAt?.toUtc().toIso8601String(),
      'overdue': policy.isOverdue(state: state, now: DateTime.now().toUtc()),
      'consecutive_failures': state.consecutiveFailures,
      'last_error_code': state.lastErrorCode,
      if (recoveryKeyConfigured != null)
        'recovery_key_configured': recoveryKeyConfigured,
      if (hubBackupOrchestrator.lastSchedulerError != null)
        'central_scheduler_last_error_code':
            hubBackupOrchestrator.lastSchedulerError!.code,
    };
  }

  Future<void> _startBackupScheduler() async {
    final policy = backupSchedule;
    final store = BackupScheduleStateStore(backupScheduleStateFile);
    _backupScheduleState = await store.load();
    if (policy == null || !policy.enabled) return;

    final runner = ScheduledBackupRunner(
      readPolicy: () => policy,
      stateStore: store,
      createBackup: () => createEncryptedHubBackup(),
      pruneExpired: () async {
        try {
          return await _backupOperationLock.synchronized(
            BackupOperationKind.backup,
            () => RetentionPolicyManager(policy: policy.retention).executePruning(
              LocalStorageProvider(_backupTargetDir),
              databaseType: DatabaseType.centralMaster,
            ),
          );
        } on BackupException catch (e) {
          if (e.code == BackupOperationLock.busyErrorCode) {
            return const <String>[];
          }
          rethrow;
        }
      },
    );
    _backupScheduler = BackupScheduler(
      runner: runner,
      checkInterval: backupCheckInterval,
      onRun: (record) async {
        _backupScheduleState = await store.load();
        final outcome = record.success
            ? 'BAŞARILI (${record.backupId}, ${record.sizeBytes} bayt, temizlenen: ${record.prunedCount})'
            : 'BAŞARISIZ [${record.errorCode}] ${redactLogText(record.errorMessage ?? '')}';
        print('[BACKUP] Zamanlanmış Hub yedeği: $outcome');
      },
    )..start();
  }

  /// Çakışma ve üzerine yazmayı önleyen, mikrosaniye ve kriptografik nonce içeren benzersiz dosya adı üretici
  String _generateUniqueBackupPath(Directory targetDir) {
    while (true) {
      final now = DateTime.now().toUtc();
      final ts = now.toIso8601String().replaceAll(RegExp(r'[^0-9]'), '');
      final nonceBytes = List<int>.generate(4, (_) => _secureRandom.nextInt(256));
      final nonceHex = nonceBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final safeFileName = 'mms_backup_${ts}_$nonceHex.db';
      final safeBackupPath = p.normalize(p.join(targetDir.path, safeFileName));
      if (!File(safeBackupPath).existsSync()) {
        return safeBackupPath;
      }
    }
  }

  void _setupRoutes() {
    _router = Router();

    // 1. Health check (Sistem ve SQLite sürümü maskelenmiştir)
    _router.get('/health', (Request req) async {
      final restoreEpoch = await _readRestoreEpoch();
      var recoveryKeyConfigured = false;
      try {
        recoveryKeyConfigured = await hubRecoveryKeyStore.hasRecoveryPassword();
      } catch (_) {
        recoveryKeyConfigured = false;
      }
      return Response.ok(
        jsonEncode({
          'status': 'UP',
          'timestamp': DateTime.now().toIso8601String(),
          'sqlite_version': 'masked', // Sistem sürümü sızıntısını önlemek için maskelendi
          'restore_epoch': restoreEpoch,
          'queue_metrics': writeQueue.metrics.toJson(),
          'backup': _publicBackupHealth(
            recoveryKeyConfigured: recoveryKeyConfigured,
          ),
        }),
        headers: {'content-type': 'application/json'},
      );
    });


    // 2. Eski Cihaz Kaydı (S-4 ile tasfiye edildi - 404 Not Found)
    _router.post('/api/v1/devices/register', (Request req) async {
      return Response.notFound(
        jsonEncode({
          'error': 'NOT_FOUND',
          'code': 'ERR_ENDPOINT_RETIRED',
          'message': 'Eski cihaz kayıt endpoint’i kaldırılmıştır. Lütfen güvenli eşleştirme (/api/v1/pairing/*) protokolünü kullanın.',
        }),
        headers: {'content-type': 'application/json'},
      );
    });


    // -------------------------------------------------------------
    // S-4: GÜVENLİ CİHAZ EŞLEŞTİRME (PAIRING) PROTOKOLÜ (v1.6)
    // -------------------------------------------------------------

    // 1. Yeni Eşleştirme Oturumu Başlat (Hub Admin / Loopback)
    _router.post('/api/v1/pairing/session', (Request req) async {
      final authError = _verifyLoopbackAndAdmin(req, actionName: 'Eşleştirme oturumu oluşturma');
      if (authError != null) return authError;

      final scheme = requireTls ? 'https' : (req.requestedUri.scheme);
      final effectivePort = _httpServer?.port ?? req.requestedUri.port;

      String? resolvedCaFingerprint;
      if (caCertPath != null) {
        try {
          final caFile = File(caCertPath!);
          if (caFile.existsSync()) {
            resolvedCaFingerprint =
                CertificateManager.validateRootCaBytes(caFile.readAsBytesSync()).colonFingerprint;
          }
        } on X509ValidationException {
          resolvedCaFingerprint = null;
        } on FileSystemException {
          resolvedCaFingerprint = null;
        }
      }

      final String caFingerprint;
      if (resolvedCaFingerprint != null) {
        caFingerprint = resolvedCaFingerprint;
      } else if (requireTls) {
        return Response(
          503,
          body: jsonEncode({
            'error': 'CA_CERT_UNAVAILABLE',
            'code': 'ERR_CA_CERT_UNAVAILABLE',
            'message': 'TLS etkin ancak geçerli X.509v3 eşleştirme kök CA sertifikası doğrulanamadı; eşleştirme oturumu başlatılamaz.',
          }),
          headers: {'content-type': 'application/json'},
        );
      } else {
        caFingerprint = 'UNKNOWN';
      }

      final String hubUrl;
      if (requireTls) {
        final Set<String> sanIpv4s;
        if (serverCertPath != null) {
          final srvFile = File(serverCertPath!);
          if (!srvFile.existsSync()) {
            return Response(
              503,
              body: jsonEncode({
                'error': 'HUB_LAN_IP_UNAVAILABLE',
                'code': 'ERR_HUB_LAN_IP_UNAVAILABLE',
                'message': 'Sunucu TLS sertifika dosyası bulunamadı.',
              }),
              headers: {'content-type': 'application/json'},
            );
          }
          try {
            sanIpv4s = CertificateManager.extractServerCertSanIpv4s(srvFile.readAsBytesSync());
          } on X509ValidationException catch (e) {
            return Response(
              503,
              body: jsonEncode({
                'error': e.code,
                'code': e.code,
                'message': e.message,
              }),
              headers: {'content-type': 'application/json'},
            );
          }
        } else {
          // Eski birim testleriyle geriye dönük uyumluluk: yalnız serverCertPath + resolver veya non-loopback host varsa çözümlenir.
          final reqHost = req.requestedUri.host;
          sanIpv4s = HubLanAddressResolver.isDisqualifiedIpv4(reqHost)
              ? const <String>{}
              : <String>{reqHost};
        }

        final resolver = lanAddressResolver ??
            HubLanAddressResolver(inspector: WindowsNetworkAdapterInspector());
        try {
          final resolved = await resolver.resolve(
            serverCertSanIpv4s: sanIpv4s,
            advertiseHost: advertiseHost,
          );
          hubUrl = '$scheme://${resolved.ipAddress}:$effectivePort';
        } on HubLanResolutionException catch (e) {
          return Response(
            503,
            body: jsonEncode({
              'error': e.code,
              'code': e.code,
              'message': e.message,
            }),
            headers: {'content-type': 'application/json'},
          );
        }
      } else {
        final host = req.requestedUri.host;
        hubUrl = '$scheme://$host:$effectivePort';
      }

      final sessionData = pairingManager.createSession(
        hubUrl: hubUrl,
        caFingerprint: caFingerprint,
      );

      return Response(
        201,
        body: jsonEncode(sessionData),
        headers: {'content-type': 'application/json'},
      );
    });


    // 2. Kök CA Sertifikasını İndir (Public)
    _router.get('/api/v1/pairing/ca-cert', (Request req) async {
      String? canonicalPem;
      X509ValidationException? invalidCaError;
      if (caCertPath != null) {
        try {
          final caFile = File(caCertPath!);
          if (caFile.existsSync()) {
            final validated = CertificateManager.validateRootCaBytes(caFile.readAsBytesSync());
            canonicalPem = validated.canonical.toPem();
          }
        } on X509ValidationException catch (e) {
          invalidCaError = e;
        } on FileSystemException {
          canonicalPem = null;
        }
      }

      if (invalidCaError != null) {
        return Response(
          500,
          body: jsonEncode({
            'error': 'ERR_HUB_CA_CERT_INVALID',
            'code': 'ERR_HUB_CA_CERT_INVALID',
            'message': 'Hub kök CA sertifikası geçersiz (${invalidCaError.code}): ${invalidCaError.message}',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      if (canonicalPem == null) {
        return Response.notFound(
          jsonEncode({
            'error': 'NOT_FOUND',
            'code': 'ERR_CA_CERT_NOT_FOUND',
            'message': 'Kök CA sertifikası bulunamadı.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      return Response.ok(
        canonicalPem,
        headers: {'content-type': 'application/x-x509-ca-cert'},
      );
    });

    // 3. Eşleştirme Talebi Gönder (Public - HTTPS)
    _router.post('/api/v1/pairing/request', (Request req) async {
      try {
        final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
        final sessionId = body['session_id'] as String;
        final pairingSecret = body['pairing_secret'] as String;
        final deviceId = body['device_id'] as String;
        final name = body['name'] as String;
        final platform = body['platform'] as String? ?? 'UNKNOWN';
        final keyAlg = body['key_algorithm'] as String? ?? 'ECDSA_P256';

        final rawKey = body['client_public_key'];
        List<int> pubKeyBytes;
        if (rawKey is String) {
          pubKeyBytes = base64Decode(rawKey);
        } else if (rawKey is List) {
          pubKeyBytes = List<int>.from(rawKey);
        } else {
          return Response(400, body: jsonEncode({'error': 'INVALID_PUBLIC_KEY', 'message': 'Açık anahtar belirtilmedi.'}), headers: {'content-type': 'application/json'});
        }

        pairingManager.registerRequest(
          sessionId: sessionId,
          pairingSecret: pairingSecret,
          deviceId: deviceId,
          name: name,
          platform: platform,
          clientPublicKeyBytes: pubKeyBytes,
          keyAlgorithm: keyAlg,
        );

        return Response(
          202,
          body: jsonEncode({
            'status': 'PENDING_APPROVAL',
            'session_id': sessionId,
            'message': 'Eşleştirme talebi alındı. İşletme sahibi onayı bekleniyor.',
          }),
          headers: {'content-type': 'application/json'},
        );
      } on PairingException catch (e) {
        return Response(
          e.statusCode,
          body: jsonEncode({'error': e.code, 'message': e.message}),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        return Response(400, body: jsonEncode({'error': 'BAD_REQUEST', 'message': e.toString()}), headers: {'content-type': 'application/json'});
      }
    });

    // 4. Onay Bekleyen Talepleri Listele (Hub Admin / Loopback)
    _router.get('/api/v1/pairing/requests', (Request req) async {
      final authError = _verifyLoopbackAndAdmin(req, actionName: 'Eşleştirme taleplerini listeleme');
      if (authError != null) return authError;

      final requests = pairingManager.getPendingRequests();
      return Response.ok(
        jsonEncode({'requests': requests}),
        headers: {'content-type': 'application/json'},
      );
    });


    // 5. Talebi Onayla (Hub Admin / Loopback)
    _router.post('/api/v1/pairing/approve', (Request req) async {
      final authError = _verifyLoopbackAndAdmin(req, actionName: 'Eşleştirme onaylama');
      if (authError != null) return authError;

      try {
        final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
        final sessionId = body['session_id'] as String;
        final allowRePair = body['allow_re_pair'] == true;

        await pairingManager.approveSession(
          sessionId: sessionId,
          db: db,
          writeQueue: writeQueue,
          pepper: pepperManager.pepper,
          allowRePair: allowRePair,
        );

        return Response.ok(
          jsonEncode({
            'status': 'APPROVED',
            'session_id': sessionId,
            'message': 'Cihaz onaylandı. Token teslimat tamponuna alındı.',
          }),
          headers: {'content-type': 'application/json'},
        );
      } on PairingException catch (e) {
        return Response(
          e.statusCode,
          body: jsonEncode({'error': e.code, 'message': e.message}),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        if (e.toString().contains('DEVICE_ALREADY_EXISTS')) {
          return Response(409, body: jsonEncode({'error': 'DEVICE_ALREADY_EXISTS', 'message': 'Bu ID ile aktif bir cihaz zaten mevcut.'}), headers: {'content-type': 'application/json'});
        }
        if (e.toString().contains('DEVICE_ALREADY_REVOKED')) {
          return Response(409, body: jsonEncode({'error': 'DEVICE_ALREADY_REVOKED', 'message': 'İptal edilmiş bir cihaz yeniden eşleştirilemez.'}), headers: {'content-type': 'application/json'});
        }
        return Response(400, body: jsonEncode({'error': 'BAD_REQUEST', 'message': e.toString()}), headers: {'content-type': 'application/json'});
      }
    });

    // 6. Talebi Reddet (Hub Admin / Loopback)
    _router.post('/api/v1/pairing/reject', (Request req) async {
      final authError = _verifyLoopbackAndAdmin(req, actionName: 'Eşleştirme reddetme');
      if (authError != null) return authError;

      final String sessionId;
      try {
        final body = jsonDecode(await req.readAsString());
        final raw = body is Map ? body['session_id'] : null;
        if (raw is! String || raw.isEmpty) throw const FormatException('session_id zorunludur');
        sessionId = raw;
      } on FormatException catch (e) {
        return Response(400,
            body: jsonEncode({'error': 'BAD_REQUEST', 'message': 'Geçersiz istek gövdesi: ${e.message}'}),
            headers: {'content-type': 'application/json'});
      }

      try {
        await pairingManager.rejectSession(
          sessionId: sessionId,
          db: db,
          writeQueue: writeQueue,
        );

        return Response.ok(
          jsonEncode({
            'status': 'REJECTED',
            'session_id': sessionId,
            'message': 'Eşleştirme talebi reddedildi.',
          }),
          headers: {'content-type': 'application/json'},
        );
      } on PairingException catch (e) {
        return Response(
          e.statusCode,
          body: jsonEncode({'error': e.code, 'message': e.message}),
          headers: {'content-type': 'application/json'},
        );
      }
    });

    // 7. Poll Challenge İste (Public + pairing_secret)
    _router.post('/api/v1/pairing/poll-challenge', (Request req) async {
      try {
        final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
        final sessionId = body['session_id'] as String?;
        final pairingSecret = body['pairing_secret'] as String?;

        if (sessionId == null || sessionId.isEmpty) {
          return Response(400, body: jsonEncode({'error': 'INVALID_REQUEST', 'message': 'session_id gereklidir'}), headers: {'content-type': 'application/json'});
        }
        if (pairingSecret == null || pairingSecret.isEmpty) {
          return Response(401, body: jsonEncode({'error': 'INVALID_PAIRING_SECRET', 'message': 'pairing_secret gereklidir'}), headers: {'content-type': 'application/json'});
        }

        final challenge = pairingManager.issuePollChallenge(
          sessionId: sessionId,
          pairingSecret: pairingSecret,
        );

        return Response.ok(
          jsonEncode({
            'poll_challenge_id': challenge.challengeId,
            'poll_challenge_nonce': base64Encode(challenge.challengeNonce),
            'expires_in': 60,
          }),
          headers: {'content-type': 'application/json'},
        );
      } on PairingException catch (e) {
        final headers = <String, String>{'content-type': 'application/json'};
        if (e.statusCode == 429 && e.retryAfterSeconds != null) {
          headers['retry-after'] = e.retryAfterSeconds.toString();
        }
        return Response(
          e.statusCode,
          body: jsonEncode({
            'error': e.code,
            'message': e.message,
            if (e.retryAfterSeconds != null) 'retry_after_seconds': e.retryAfterSeconds,
          }),
          headers: headers,
        );
      } catch (e) {
        return Response(400, body: jsonEncode({'error': 'BAD_REQUEST', 'message': e.toString()}), headers: {'content-type': 'application/json'});
      }
    });

    // 8. Poll Token (Public - İmzalı Kanonik Çerçeve)
    _router.post('/api/v1/pairing/poll', (Request req) async {
      try {
        final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
        final sessionId = body['session_id'] as String;
        final pairingSecret = body['pairing_secret'] as String;
        final pollChallengeId = body['poll_challenge_id'] as String;

        final rawSig = body['signature'];
        List<int> sigBytes;
        if (rawSig is String) {
          sigBytes = base64Decode(rawSig);
        } else if (rawSig is List) {
          sigBytes = List<int>.from(rawSig);
        } else {
          return Response(400, body: jsonEncode({'error': 'INVALID_SIGNATURE', 'message': 'İmza belirtilmedi'}), headers: {'content-type': 'application/json'});
        }

        final rawToken = pairingManager.verifyAndPollToken(
          sessionId: sessionId,
          pairingSecret: pairingSecret,
          pollChallengeId: pollChallengeId,
          signatureBytes: sigBytes,
        );

        final session = pairingManager.getSession(sessionId);

        return Response.ok(
          jsonEncode({
            'status': 'PAIRED',
            'device_id': session.deviceId,
            'token': rawToken,
          }),
          headers: {'content-type': 'application/json'},
        );
      } on PairingException catch (e) {
        return Response(
          e.statusCode,
          body: jsonEncode({'error': e.code, 'message': e.message}),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        return Response(400, body: jsonEncode({'error': 'BAD_REQUEST', 'message': e.toString()}), headers: {'content-type': 'application/json'});
      }
    });

    // 9. ACK Challenge İste (Public + pairing_secret)
    _router.post('/api/v1/pairing/ack-challenge', (Request req) async {
      try {
        final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
        final sessionId = body['session_id'] as String?;
        final pairingSecret = body['pairing_secret'] as String?;

        if (sessionId == null || sessionId.isEmpty) {
          return Response(400, body: jsonEncode({'error': 'INVALID_REQUEST', 'message': 'session_id gereklidir'}), headers: {'content-type': 'application/json'});
        }
        if (pairingSecret == null || pairingSecret.isEmpty) {
          return Response(401, body: jsonEncode({'error': 'INVALID_PAIRING_SECRET', 'message': 'pairing_secret gereklidir'}), headers: {'content-type': 'application/json'});
        }

        final challenge = pairingManager.issueAckChallenge(
          sessionId: sessionId,
          pairingSecret: pairingSecret,
        );

        return Response.ok(
          jsonEncode({
            'ack_challenge_id': challenge.challengeId,
            'ack_challenge_nonce': base64Encode(challenge.challengeNonce),
            'expires_in': 60,
          }),
          headers: {'content-type': 'application/json'},
        );
      } on PairingException catch (e) {
        final headers = <String, String>{'content-type': 'application/json'};
        if (e.statusCode == 429 && e.retryAfterSeconds != null) {
          headers['retry-after'] = e.retryAfterSeconds.toString();
        }
        return Response(
          e.statusCode,
          body: jsonEncode({
            'error': e.code,
            'message': e.message,
            if (e.retryAfterSeconds != null) 'retry_after_seconds': e.retryAfterSeconds,
          }),
          headers: headers,
        );
      } catch (e) {
        return Response(400, body: jsonEncode({'error': 'BAD_REQUEST', 'message': e.toString()}), headers: {'content-type': 'application/json'});
      }
    });

    // 10. ACK Onayı (Public - Token-Bound İmzalı Çerçeve)
    _router.post('/api/v1/pairing/ack', (Request req) async {
      try {
        final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
        final sessionId = body['session_id'] as String;
        final ackChallengeId = body['ack_challenge_id'] as String;

        final rawSig = body['signature'];
        List<int> sigBytes;
        if (rawSig is String) {
          sigBytes = base64Decode(rawSig);
        } else if (rawSig is List) {
          sigBytes = List<int>.from(rawSig);
        } else {
          return Response(400, body: jsonEncode({'error': 'INVALID_SIGNATURE', 'message': 'İmza belirtilmedi'}), headers: {'content-type': 'application/json'});
        }

        final ackResult = await pairingManager.verifyAndAcknowledge(
          sessionId: sessionId,
          ackChallengeId: ackChallengeId,
          signatureBytes: sigBytes,
          db: db,
          writeQueue: writeQueue,
        );

        return Response.ok(
          jsonEncode({
            'status': 'CONFIRMED',
            'session_id': sessionId,
            'device_id': ackResult.deviceId,
            if (ackResult.idempotentReplay) 'idempotent_replay': true,
            'message': 'Teslimat teyidi tamamlandı. Cihaz başarıyla aktifleştirildi.',
          }),
          headers: {'content-type': 'application/json'},
        );
      } on PairingException catch (e) {
        return Response(
          e.statusCode,
          body: jsonEncode({'error': e.code, 'message': e.message}),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        return Response(400, body: jsonEncode({'error': 'BAD_REQUEST', 'message': e.toString()}), headers: {'content-type': 'application/json'});
      }
    });

    // 3. Token Yenileme (Renew Token - S-2)
    _router.post('/api/v1/devices/renew-token', (Request req) async {
      final deviceId = req.context['authenticated_device_id'] as String?;
      if (deviceId == null) {
        return Response(
          401,
          body: jsonEncode({
            'error': 'UNAUTHORIZED',
            'message': 'Token yenileme için yetkili bir cihaz oturumu gereklidir.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final newToken = TokenManager.generateToken();
      final newSalt = TokenManager.generateSalt();
      final newHash = TokenManager.hashToken(
        rawToken: newToken,
        salt: newSalt,
        pepper: pepperManager.pepper,
      );

      await writeQueue.enqueue(() async {
        await (db.update(db.devices)..where((d) => d.deviceId.equals(deviceId))).write(
              DevicesCompanion(
                tokenHash: Value(newHash),
                salt: Value(newSalt),
                lastUsedAt: Value(DateTime.now()),
              ),
            );
        await db.into(db.deviceAuditLogs).insert(
              DeviceAuditLogsCompanion(
                deviceId: Value(deviceId),
                action: const Value('RENEW'),
                details: const Value('Token başarıyla yenilendi.'),
              ),
            );
      });

      return Response.ok(
        jsonEncode({
          'status': 'RENEWED',
          'device_id': deviceId,
          'token': newToken,
        }),
        headers: {'content-type': 'application/json'},
      );
    });


    // 4. Token İptali (Revoke Device - S-2; loopback + admin secret zorunlu)
    _router.post('/api/v1/devices/revoke', (Request req) async {
      final loopbackDenied = _denyIfNotLoopback(req, actionName: 'Cihaz token iptali');
      if (loopbackDenied != null) return loopbackDenied;

      final effectiveAdminSecret = _effectiveAdminSecret;
      final providedAdminSecret = req.headers['x-admin-secret'] ??
          req.headers['x-mms-admin-secret'] ??
          (req.headers['authorization']?.startsWith('Bearer ') == true
              ? req.headers['authorization']!.substring(7).trim()
              : null);

      if (effectiveAdminSecret == null || effectiveAdminSecret.isEmpty) {
        return Response(
          503,
          body: jsonEncode({
            'error': 'REVOCATION_DISABLED',
            'code': 'ERR_ADMIN_SECRET_NOT_CONFIGURED',
            'message': 'Admin secret yapılandırılmadığı için cihaz iptal işlemi yapılamaz.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      if (providedAdminSecret == null || providedAdminSecret.isEmpty) {
        return Response(
          401,
          body: jsonEncode({
            'error': 'UNAUTHORIZED',
            'code': 'ERR_ADMIN_SECRET_REQUIRED',
            'message': 'Cihaz iptal işlemi için admin secret gereklidir.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      if (!_constantTimeEquals(utf8.encode(providedAdminSecret), utf8.encode(effectiveAdminSecret))) {
        return Response.forbidden(
          jsonEncode({
            'error': 'FORBIDDEN',
            'code': 'ERR_INVALID_ADMIN_SECRET',
            'message': 'Geçersiz admin secret.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final bodyStr = await req.readAsString();
      Map<String, dynamic> body = {};
      if (bodyStr.isNotEmpty) {
        try {
          body = jsonDecode(bodyStr) as Map<String, dynamic>;
        } catch (e) {
          stderr.writeln(
            '[WARN] İstek JSON gövdesi ayrıştırılamadı (${req.requestedUri.path}): ${e.runtimeType}',
          );
        }
      }

      final targetDeviceId = body['device_id'] as String?;
      if (targetDeviceId == null || targetDeviceId.isEmpty) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'INVALID_REQUEST',
            'message': 'device_id parametresi zorunludur.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final reason = body['reason'] as String? ?? 'Admin tarafından iptal edildi';

      final device = await (db.select(db.devices)..where((d) => d.deviceId.equals(targetDeviceId))).getSingleOrNull();
      if (device == null) {
        return Response(
          404,
          body: jsonEncode({
            'error': 'DEVICE_NOT_FOUND',
            'message': 'İptal edilecek cihaz bulunamadı.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      if (!device.isActive) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'ALREADY_REVOKED',
            'message': 'Cihaz zaten daha önce iptal edilmiştir.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      if (device.role.toUpperCase() == 'OWNER') {
        final activeOwners = await (db.select(db.devices)
              ..where((d) =>
                  d.isActive.equals(true) &
                  d.isConfirmed.equals(true) &
                  d.role.equals('OWNER')))
            .get();
        if (activeOwners.length <= 1 &&
            activeOwners.any((o) => o.deviceId == targetDeviceId)) {
          return Response(
            409,
            body: jsonEncode({
              'error': 'CONFLICT',
              'code': 'ERR_LAST_OWNER_PROTECTED',
              'message': 'Son aktif OWNER cihazı iptal edilemez.',
            }),
            headers: {'content-type': 'application/json'},
          );
        }
      }

      await writeQueue.enqueue(() async {
        await (db.update(db.devices)..where((d) => d.deviceId.equals(targetDeviceId))).write(
              const DevicesCompanion(isActive: Value(false)),
            );
        await db.into(db.deviceAuditLogs).insert(
              DeviceAuditLogsCompanion(
                deviceId: Value(targetDeviceId),
                action: const Value('REVOKE'),
                details: Value('İptal nedeni: $reason'),
              ),
            );
      });

      return Response.ok(
        jsonEncode({
          'status': 'REVOKED',
          'device_id': targetDeviceId,
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    // 4.0a. OV-04: Tek Seferlik, Tekrar Kullanılamaz Hub OWNER Bootstrap (Loopback + Admin Secret)
    _router.post('/api/v1/admin/owner/bootstrap', (Request req) async {
      final adminDenied = _verifyLoopbackAndAdmin(
        req,
        actionName: 'Tek seferlik OWNER bootstrap',
      );
      if (adminDenied != null) return adminDenied;

      final body = await _decodeJsonBodyOrEmpty(req);
      final targetDeviceId = (body['device_id'] as String?)?.trim() ?? '';
      final registerIfMissing = (body['register_if_missing'] as bool?) ?? false;
      final deviceName =
          (body['name'] as String?)?.trim() ?? 'Windows Master Hub (OWNER)';
      if (targetDeviceId.isEmpty) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'INVALID_REQUEST',
            'code': 'ERR_DEVICE_ID_REQUIRED',
            'message': 'device_id zorunludur.',
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      }

      try {
        String? issuedToken;
        await writeQueue.enqueue(() async {
          await db.transaction(() async {
            final sealed = await (db.select(db.hubMetadata)
                  ..where((m) => m.key.equals('owner_bootstrap_completed')))
                .getSingleOrNull();
            if (sealed != null && sealed.value == 'true') {
              throw _ValidationException(
                409,
                'ERR_OWNER_ALREADY_BOOTSTRAPPED',
                'Tek seferlik OWNER bootstrap daha önce tamamlanmıştır; tekrar kullanılamaz.',
              );
            }

            final existing = await (db.select(db.devices)
                  ..where((d) => d.deviceId.equals(targetDeviceId)))
                .getSingleOrNull();
            if (existing != null) {
              if (!existing.isActive) {
                throw _ValidationException(
                  409,
                  'ERR_DEVICE_REVOKED',
                  'İptal edilmiş cihaz OWNER yapılamaz.',
                );
              }
              await (db.update(db.devices)
                    ..where((d) => d.deviceId.equals(targetDeviceId)))
                  .write(const DevicesCompanion(
                role: Value('OWNER'),
                isConfirmed: Value(true),
              ));
            } else if (registerIfMissing) {
              final rawTok = TokenManager.generateToken();
              final salt = TokenManager.generateSalt();
              final tokHash = TokenManager.hashToken(
                rawToken: rawTok,
                salt: salt,
                pepper: pepperManager.pepper,
              );
              await db.into(db.devices).insert(
                    DevicesCompanion(
                      deviceId: Value(targetDeviceId),
                      name: Value(deviceName),
                      tokenHash: Value(tokHash),
                      salt: Value(salt),
                      isActive: const Value(true),
                      isConfirmed: const Value(true),
                      role: const Value('OWNER'),
                    ),
                  );
              issuedToken = rawTok;
            } else {
              throw _ValidationException(
                404,
                'ERR_DEVICE_NOT_FOUND',
                'Bootstrap edilecek cihaz bulunamadı: $targetDeviceId',
              );
            }

            final now = DateTime.now().toUtc();
            await db.into(db.hubMetadata).insertOnConflictUpdate(
                  HubMetadataCompanion(
                    key: const Value('owner_bootstrap_completed'),
                    value: const Value('true'),
                    updatedAt: Value(now),
                  ),
                );
            await db.into(db.hubMetadata).insertOnConflictUpdate(
                  HubMetadataCompanion(
                    key: const Value('owner_bootstrap_device_id'),
                    value: Value(targetDeviceId),
                    updatedAt: Value(now),
                  ),
                );
            await db.into(db.deviceAuditLogs).insert(
                  DeviceAuditLogsCompanion(
                    deviceId: Value(targetDeviceId),
                    action: const Value('OWNER_BOOTSTRAP'),
                    details: const Value('One-time Hub OWNER bootstrap sealed'),
                  ),
                );
          });
        });

        return Response.ok(
          jsonEncode({
            'status': 'BOOTSTRAPPED',
            'device_id': targetDeviceId,
            'role': 'OWNER',
            if (issuedToken != null) 'token': issuedToken,
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      } on _ValidationException catch (e) {
        return Response(
          e.statusCode,
          body: jsonEncode({'error': e.code, 'code': e.code, 'message': e.message}),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      }
    });

    // 4.0b. OV-04: Cihaz Rolü Değiştirme (OWNER veya Loopback + Admin + Replay)
    _router.post('/api/v1/devices/role', (Request req) async {
      final denied = _verifyOwnerOrLoopbackAdmin(
        req,
        actionName: 'Cihaz rolü yönetimi',
      );
      if (denied != null) return denied;
      final replayDenied = await _verifyReplayProtection(
        req,
        actionName: 'Cihaz rolü yönetimi',
      );
      if (replayDenied != null) return replayDenied;

      final body = await _decodeJsonBodyOrEmpty(req);
      final targetDeviceId = (body['device_id'] as String?)?.trim() ?? '';
      final nextRole = (body['role'] as String?)?.trim().toUpperCase() ?? '';
      if (targetDeviceId.isEmpty ||
          (nextRole != 'OWNER' && nextRole != 'CASHIER')) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'INVALID_REQUEST',
            'code': 'ERR_INVALID_ROLE',
            'message': 'device_id ve geçerli rol (OWNER / CASHIER) zorunludur.',
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      }

      final actorId =
          (req.context['authenticated_device_id'] as String?) ?? 'HUB_ADMIN';
      try {
        await writeQueue.enqueue(() async {
          await db.transaction(() async {
            final target = await (db.select(db.devices)
                  ..where((d) => d.deviceId.equals(targetDeviceId)))
                .getSingleOrNull();
            if (target == null) {
              throw _ValidationException(
                404,
                'ERR_DEVICE_NOT_FOUND',
                'Cihaz bulunamadı: $targetDeviceId',
              );
            }
            if (!target.isActive) {
              throw _ValidationException(
                409,
                'ERR_DEVICE_REVOKED',
                'İptal edilmiş cihazın rolü değiştirilemez.',
              );
            }
            if (target.role.toUpperCase() == 'OWNER' && nextRole == 'CASHIER') {
              final owners = await (db.select(db.devices)
                    ..where((d) =>
                        d.isActive.equals(true) &
                        d.isConfirmed.equals(true) &
                        d.role.equals('OWNER')))
                  .get();
              if (owners.length <= 1 &&
                  owners.any((o) => o.deviceId == targetDeviceId)) {
                throw _ValidationException(
                  409,
                  'ERR_LAST_OWNER_PROTECTED',
                  'Son aktif OWNER cihaz CASHIER rolüne düşürülemez.',
                );
              }
            }
            await (db.update(db.devices)
                  ..where((d) => d.deviceId.equals(targetDeviceId)))
                .write(DevicesCompanion(role: Value(nextRole)));
            await db.into(db.deviceAuditLogs).insert(
                  DeviceAuditLogsCompanion(
                    deviceId: Value(actorId),
                    action: const Value('DEVICE_ROLE_CHANGE'),
                    details: Value('target=$targetDeviceId role=$nextRole'),
                  ),
                );
          });
        });
        return Response.ok(
          jsonEncode({
            'status': 'UPDATED',
            'device_id': targetDeviceId,
            'role': nextRole,
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      } on _ValidationException catch (e) {
        return Response(
          e.statusCode,
          body: jsonEncode({'error': e.code, 'code': e.code, 'message': e.message}),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      }
    });

    // 4.0c. AUD-MED-04: Doğrulanmış Cihaz Kimliği & Yetkili Rol Kaynağı (Fail-Closed)
    _router.get('/api/v1/devices/me', (Request req) async {
      final deviceId = req.context['authenticated_device_id'] as String?;
      if (deviceId == null || deviceId.isEmpty) {
        return Response(
          401,
          body: jsonEncode({
            'error': 'UNAUTHORIZED',
            'code': 'ERR_AUTH_REQUIRED',
            'message': 'Cihaz rolü sorgulaması için geçerli bir cihaz oturumu gereklidir.',
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      }

      final device = await (db.select(db.devices)
            ..where((d) => d.deviceId.equals(deviceId)))
          .getSingleOrNull();
      if (device == null) {
        return Response(
          401,
          body: jsonEncode({
            'error': 'DEVICE_NOT_FOUND',
            'code': 'ERR_DEVICE_NOT_FOUND',
            'message': 'Yetkili cihaz kaydı bulunamadı.',
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      }

      final bootstrapMeta = await (db.select(db.hubMetadata)
            ..where((m) => m.key.equals('owner_bootstrap_completed')))
          .getSingleOrNull();
      final ownerBootstrapCompleted = bootstrapMeta?.value == 'true';
      final restoreEpoch = await _readRestoreEpoch();
      final canonicalRole =
          device.role.toUpperCase() == 'OWNER' ? 'OWNER' : 'CASHIER';

      return Response.ok(
        jsonEncode({
          'device_id': device.deviceId,
          'name': device.name,
          'role': canonicalRole,
          'is_active': device.isActive,
          'is_confirmed': device.isConfirmed,
          'owner_bootstrap_completed': ownerBootstrapCompleted,
          'restore_epoch': restoreEpoch,
          'expires_at': device.expiresAt?.toUtc().toIso8601String(),
          'tenant_id': tenantId,
          'store_id': storeId,
          'hub_id': hubId,
          'server_time': DateTime.now().toUtc().toIso8601String(),
        }),
        headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
      );
    });

    // 4.1. K-05: Live Drive Senkronizasyon Sırrı Rotasyonu (Loopback + Admin Secret)
    _router.post('/api/v1/admin/live-drive-secret/rotate', (Request req) async {
      final authError = _verifyLoopbackAndAdmin(
        req,
        actionName: 'Live Drive sır rotasyonu',
      );
      if (authError != null) return authError;

      final rotatedAt = DateTime.now().toUtc();
      await writeQueue.enqueue(() async {
        liveDriveSecretManager.rotate();
        await db.into(db.deviceAuditLogs).insert(
              DeviceAuditLogsCompanion(
                deviceId: const Value('HUB_ADMIN'),
                action: const Value('LIVE_DRIVE_SECRET_ROTATE'),
                details: const Value('Live Drive sync secret rotated by admin'),
                createdAt: Value(rotatedAt),
              ),
            );
      });

      return Response.ok(
        jsonEncode({
          'status': 'ROTATED',
          'rotated_at': rotatedAt.toIso8601String(),
        }),
        headers: {
          'content-type': 'application/json',
          'cache-control': 'no-store',
        },
      );
    });


    // 4.5. Ürün Listesi ve Fiyat Senkronizasyonu (S5A-3 İki Aşamalı İstemci Senkronizasyonu - Snapshot)
    _router.get('/api/v1/products', (Request req) async {
      final deviceId = req.context['authenticated_device_id'] as String?;
      final now = DateTime.now();

      final products = await db.select(db.products).get();
      final activeBarcodes = await (db.select(db.productBarcodes)
            ..where((b) => b.isActive.equals(true))
            ..orderBy([
              (b) => OrderingTerm.desc(b.isPrimary),
              (b) => OrderingTerm.asc(b.createdAt),
            ]))
          .get();
      final barcodesByProductId = <String, List<String>>{};
      for (final row in activeBarcodes) {
        final list = barcodesByProductId.putIfAbsent(row.productId, () => <String>[]);
        if (!list.contains(row.barcode)) {
          list.add(row.barcode);
        }
      }

      final items = products.map((p) {
        final combined = <String>[
          if (p.barcode.trim().isNotEmpty) p.barcode.trim(),
          ...?barcodesByProductId[p.id],
        ];
        final deduped = <String>[];
        for (final bc in combined) {
          if (bc.isNotEmpty && !deduped.contains(bc)) {
            deduped.add(bc);
          }
        }
        return {
          'id': p.id,
          'barcode': p.barcode,
          'name': p.name,
          'price': p.price,
          'price_version_id': p.priceVersionId,
          'stock': p.stock,
          'stock_unit': p.stockUnit,
          'pricing_unit': p.pricingUnit,
          'conversion_factor_numerator': p.conversionFactorNumerator,
          'conversion_factor_denominator': p.conversionFactorDenominator,
          'is_active': p.isActive,
          'barcodes': deduped,
          'updated_at': p.updatedAt.toIso8601String(),
        };
      }).toList();

      String? syncSessionId;
      if (deviceId != null) {
        syncSessionId = 'sync_${deviceId}_${now.microsecondsSinceEpoch}';
        await writeQueue.enqueue(() async {
          await db.into(db.productSyncSessions).insert(
                ProductSyncSessionsCompanion(
                  id: Value(syncSessionId!),
                  deviceId: Value(deviceId),
                  productCount: Value(items.length),
                  syncedAt: Value(now),
                  isAcknowledged: const Value(false),
                  createdAt: Value(now),
                ),
              );
        });
      }

      return Response.ok(
        jsonEncode({
          'status': 'OK',
          'products': items,
          'count': items.length,
          'synced_at': now.toIso8601String(),
          if (syncSessionId != null) 'sync_session_id': syncSessionId,
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    // 4.5.1. Çoklu Cihaz Satış Senkronizasyonu (Sales Downlink - Cursor Tabanlı)
    _router.get('/api/v1/sales', (Request req) async {
      final deviceId = req.context['authenticated_device_id'] as String?;
      if (deviceId == null) {
        return Response(
          401,
          body: jsonEncode({
            'error': 'UNAUTHORIZED',
            'code': 'ERR_AUTH_REQUIRED',
            'message': 'Cihaz yetkilendirmesi zorunludur.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final queryParams = req.requestedUri.queryParameters;
      final cursor = int.tryParse(queryParams['cursor'] ?? '0') ?? 0;
      final rawLimit = int.tryParse(queryParams['limit'] ?? '50') ?? 50;
      final limit = rawLimit.clamp(1, 100);

      final salesQuery = db.select(db.sales)
        ..where((s) => s.serverSeq.isBiggerThanValue(cursor))
        ..orderBy([(s) => OrderingTerm.asc(s.serverSeq)])
        ..limit(limit);

      final salesList = await salesQuery.get();

      final results = <Map<String, dynamic>>[];
      int maxSeq = cursor;

      for (final sale in salesList) {
        final currentSeq = sale.serverSeq ?? 0;
        if (currentSeq > maxSeq) {
          maxSeq = currentSeq;
        }

        final saleItems = await (db.select(db.saleItems)..where((i) => i.saleId.equals(sale.id))).get();
        final itemsPayload = <Map<String, dynamic>>[];

        for (final item in saleItems) {
          final prod = await (db.select(db.products)..where((p) => p.id.equals(item.productId))).getSingleOrNull();
          itemsPayload.add({
            'id': item.id,
            'sale_id': item.saleId,
            'product_id': item.productId,
            'product_name': prod?.name ?? 'Ürün',
            'unit': prod?.pricingUnit ?? 'adet',
            'price_version_id': prod?.priceVersionId ?? 'pv_init',
            'unit_price': item.unitPrice,
            'quantity': item.quantity,
            'total_price': item.totalPrice,
          });
        }

        final refunds = await (db.select(db.refunds)..where((r) => r.saleId.equals(sale.id))).get();
        final refundsPayload = <Map<String, dynamic>>[];
        int totalRefundedInSale = 0;
        for (final ref in refunds) {
          totalRefundedInSale += ref.totalRefundAmount;
          final refItems = await (db.select(db.refundItems)..where((ri) => ri.refundId.equals(ref.id))).get();
          refundsPayload.add({
            'id': ref.id,
            'sale_id': ref.saleId,
            'device_id': ref.deviceId,
            'client_seq': ref.clientSeq,
            'total_refund_amount': ref.totalRefundAmount,
            'payment_method': ref.paymentMethod,
            'reason': ref.reason,
            'created_at': ref.createdAt.toIso8601String(),
            'items': refItems.map((ri) => {
              'id': ri.id,
              'refund_id': ri.refundId,
              'sale_item_id': ri.saleItemId,
              'product_id': ri.productId,
              'quantity': ri.quantity,
              'unit_price': ri.unitPrice,
              'refund_amount': ri.refundAmount,
              'product_condition': ri.productCondition,
            }).toList(),
          });
        }

        String effectiveStatus = sale.status;
        if (effectiveStatus != 'CANCELLED' &&
            effectiveStatus != 'REFUNDED' &&
            refunds.isNotEmpty) {
          if (totalRefundedInSale >= sale.totalAmount) {
            effectiveStatus = 'REFUNDED';
          } else if (totalRefundedInSale > 0) {
            effectiveStatus = 'PARTIALLY_REFUNDED';
          }
        }

        results.add({
          'id': sale.id,
          'server_seq': currentSeq,
          'device_id': sale.deviceId,
          'client_seq': sale.clientSeq,
          'total_amount': sale.totalAmount,
          'payment_method': sale.paymentMethod,
          'status': effectiveStatus,
          'cancel_reason': sale.cancelReason,
          'cancelled_at': sale.cancelledAt?.toIso8601String(),
          'created_at': sale.createdAt.toIso8601String(),
          'items': itemsPayload,
          'refunds': refundsPayload,
        });
      }

      return Response.ok(
        jsonEncode({
          'status': 'OK',
          'sales': results,
          'count': results.length,
          'cursor': cursor,
          'next_cursor': maxSeq,
          'has_more': salesList.length == limit,
        }),
        headers: {'content-type': 'application/json'},
      );
    });


    // 4.6. Ürün Senkronizasyon Onayı (S5A-3 Product Sync ACK - Idempotent)
    _router.post('/api/v1/products/sync-ack', (Request req) async {
      final deviceId = req.context['authenticated_device_id'] as String?;
      if (deviceId == null) {
        return Response(
          401,
          body: jsonEncode({
            'error': 'UNAUTHORIZED',
            'code': 'ERR_AUTH_REQUIRED',
            'message': 'Ürün senkronizasyon onayı için yetkili bir cihaz oturumu gereklidir.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final bodyStr = await req.readAsString();
      Map<String, dynamic> body = {};
      if (bodyStr.isNotEmpty) {
        try {
          body = jsonDecode(bodyStr) as Map<String, dynamic>;
        } catch (e) {
          stderr.writeln(
            '[WARN] İstek JSON gövdesi ayrıştırılamadı (${req.requestedUri.path}): ${e.runtimeType}',
          );
        }
      }

      final syncSessionId = body['sync_session_id'] as String?;
      if (syncSessionId == null || syncSessionId.trim().isEmpty) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'BAD_REQUEST',
            'code': 'ERR_INVALID_REQUEST',
            'message': 'sync_session_id parametresi zorunludur.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final session = await (db.select(db.productSyncSessions)
            ..where((s) => s.id.equals(syncSessionId) & s.deviceId.equals(deviceId)))
          .getSingleOrNull();

      if (session == null) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'BAD_REQUEST',
            'code': 'ERR_INVALID_SYNC_SESSION',
            'message': 'Geçersiz veya bu cihaza ait olmayan senkronizasyon oturumu: $syncSessionId',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Idempotency: Eğer bu sync_session_id daha önce onaylanmışsa güvenle 200 OK dön
      if (session.isAcknowledged) {
        return Response.ok(
          jsonEncode({
            'status': 'ALREADY_ACKNOWLEDGED',
            'sync_session_id': syncSessionId,
            'synced_at': session.syncedAt.toIso8601String(),
            'acknowledged_at': session.acknowledgedAt?.toIso8601String(),
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final ackTime = DateTime.now();
      await writeQueue.enqueue(() async {
        await (db.update(db.productSyncSessions)..where((s) => s.id.equals(syncSessionId))).write(
              ProductSyncSessionsCompanion(
                isAcknowledged: const Value(true),
                acknowledgedAt: Value(ackTime),
              ),
            );

        final currentDev = await (db.select(db.devices)..where((d) => d.deviceId.equals(deviceId))).getSingleOrNull();
        final currentLastSync = currentDev?.lastProductSyncAt;
        if (currentLastSync == null || session.syncedAt.isAfter(currentLastSync)) {
          await (db.update(db.devices)..where((d) => d.deviceId.equals(deviceId))).write(
                DevicesCompanion(
                  lastProductSyncAt: Value(session.syncedAt),
                ),
              );
        }
      });

      return Response.ok(
        jsonEncode({
          'status': 'ACKNOWLEDGED',
          'sync_session_id': syncSessionId,
          'synced_at': session.syncedAt.toIso8601String(),
          'acknowledged_at': ackTime.toIso8601String(),
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    // 4.7. Ürün Ekleme / Güncelleme Senkronizasyonu (Outbox PRODUCT_UPSERT - Idempotent)
    _router.post('/api/v1/products/upsert', (Request req) async {
      final deviceId = req.context['authenticated_device_id'] as String?;
      if (deviceId == null) {
        return Response(
          401,
          body: jsonEncode({
            'error': 'UNAUTHORIZED',
            'code': 'ERR_AUTH_REQUIRED',
            'message': 'Ürün kaydı için yetkili bir cihaz oturumu gereklidir.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final bodyStr = await req.readAsString();
      Map<String, dynamic> body;
      try {
        body = jsonDecode(bodyStr) as Map<String, dynamic>;
      } catch (_) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'BAD_REQUEST',
            'code': 'ERR_INVALID_JSON',
            'message': 'Geçersiz JSON formatı.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final rawClientSeq = body['client_seq'];
      if (rawClientSeq is! int || rawClientSeq <= 0) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'BAD_REQUEST',
            'code': 'ERR_INVALID_CLIENT_SEQ',
            'message': 'client_seq pozitif bir tamsayı (> 0) olmalıdır.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }
      final clientSeq = rawClientSeq;

      final productData = body['product'] as Map<String, dynamic>?;
      if (productData == null) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'BAD_REQUEST',
            'code': 'ERR_INVALID_PRODUCT_DATA',
            'message': 'product nesnesi zorunludur.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final prodId = productData['id'] as String?;
      final name = productData['name'] as String?;
      final price = productData['price'] as int?;
      final barcode = productData['barcode'] as String?;

      if (prodId == null || prodId.trim().isEmpty) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'BAD_REQUEST',
            'code': 'ERR_INVALID_PRODUCT_ID',
            'message': 'Ürün kimliği (id) zorunludur.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }
      if (name == null || name.trim().isEmpty) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'BAD_REQUEST',
            'code': 'ERR_INVALID_NAME',
            'message': 'Ürün adı zorunludur.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }
      if (price == null || price <= 0) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'BAD_REQUEST',
            'code': 'ERR_INVALID_PRICE',
            'message': 'Fiyat pozitif bir kuruş tamsayısı olmalıdır (> 0).',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final operationId =
          body['operation_id'] as String? ?? 'op_prod_${deviceId}_${prodId}_$clientSeq';
      final idempotencyKey = '$deviceId:$clientSeq';
      final incomingCanonicalHash = CanonicalPayloadHasher.computeCanonicalV2(
        operationType: 'PRODUCT_UPSERT',
        body: body,
      );

      // Idempotency kontrolü (ProcessedOperations - replay & conflict önce çalışır)
      final existingOp = await (db.select(db.processedOperations)
            ..where((o) => o.idempotencyKey.equals(idempotencyKey)))
          .getSingleOrNull();

      if (existingOp != null) {
        return _evaluateExistingReceipt(
          existingOp: existingOp,
          operationType: 'PRODUCT_UPSERT',
          incomingBody: body,
          rawBody: bodyStr,
          idempotencyKey: idempotencyKey,
        );
      }

      try {
        final txResult = await writeQueue.enqueue(() async {
          return await db.transaction(() async {
            // Transaction içi tekrar kontrol
            final txReplay = await _checkExistingReceiptInTx(
              idempotencyKey: idempotencyKey,
              operationType: 'PRODUCT_UPSERT',
              incomingBody: body,
              rawBody: bodyStr,
            );
            if (txReplay != null) {
              return txReplay;
            }

            // BK-02.1 Karar 3: Katı sequence gap kontrolü
            await _assertExpectedClientSeqInTx(deviceId, clientSeq);

            final existingProduct = await (db.select(db.products)
                  ..where((p) => p.id.equals(prodId)))
                .getSingleOrNull();

            final now = DateTime.now();
            final hasBarcodesField = productData.containsKey('barcodes');
            final extraBarcodes = <String>[];
            if (hasBarcodesField && productData['barcodes'] != null) {
              final rawList = productData['barcodes'];
              if (rawList is! List) {
                throw _ValidationException(
                  400,
                  'ERR_INVALID_BARCODES',
                  'barcodes alanı metin listesi olmalıdır.',
                );
              }
              for (final entry in rawList) {
                if (entry is! String) {
                  throw _ValidationException(
                    400,
                    'ERR_INVALID_BARCODES',
                    'barcodes listesindeki tüm elemanlar metin olmalıdır.',
                  );
                }
                final clean = entry.trim();
                if (clean.isNotEmpty && !extraBarcodes.contains(clean)) {
                  extraBarcodes.add(clean);
                }
              }
            }

            // GAP-A01: `barcodes` alanını gönderen istemci ürünün TAM barkod kümesini
            // bildirir. Son barkod silindiyse (barcode boş + barcodes boş) eski barkoda
            // geri düşülmez; aksi halde silinen barkod Hub'da aktif kalır ve ürün
            // indirmesinde istemciye geri dirilirdi. Barkodsuz yeni ürünlerle aynı
            // `prodId` yer tutucusu kullanılır. `barcodes` alanı olmayan eski istemciler
            // için önceki davranış korunur.
            final effectiveBarcode = barcode?.trim().isNotEmpty == true
                ? barcode!.trim()
                : (extraBarcodes.isNotEmpty
                    ? extraBarcodes.first
                    : (hasBarcodesField ? prodId : (existingProduct?.barcode ?? prodId)));

            final allIncomingBarcodes = <String>[
              effectiveBarcode,
              for (final b in extraBarcodes)
                if (b != effectiveBarcode) b,
            ];

            // Başka bir üründe bu barkodlardan herhangi biri var mı?
            for (final candidateBc in allIncomingBarcodes) {
              final barcodeDuplicate = await (db.select(db.products)
                    ..where((p) => p.barcode.equals(candidateBc) & p.id.isNotValue(prodId)))
                  .getSingleOrNull();
              if (barcodeDuplicate != null) {
                throw _ValidationException(
                  409,
                  'ERR_DUPLICATE_BARCODE',
                  'Bu barkod ($candidateBc) başka bir üründe kayıtlı: ${barcodeDuplicate.name}',
                );
              }
              final secondaryDuplicate = await (db.select(db.productBarcodes)
                    ..where((b) =>
                        b.barcode.equals(candidateBc) & b.productId.isNotValue(prodId)))
                  .getSingleOrNull();
              if (secondaryDuplicate != null) {
                throw _ValidationException(
                  409,
                  'ERR_DUPLICATE_BARCODE',
                  'Bu barkod ($candidateBc) başka bir ürüne (${secondaryDuplicate.productId}) atanmış.',
                );
              }
            }

            final rawIncomingPv =
                (productData['price_version_id'] as String?)?.trim();
            final incomingPv =
                (rawIncomingPv != null && rawIncomingPv.isNotEmpty)
                    ? rawIncomingPv
                    : null;

            String priceVersionId;
            if (existingProduct != null) {
              if (existingProduct.price != price) {
                // Önceki aktif fiyat sürümünü tarihçede güvenceye al ve geçerlilik bitişini kapat.
                await _insertPriceHistoryVersionIfAbsentInTx(
                  productId: prodId,
                  priceVersionId: existingProduct.priceVersionId,
                  price: existingProduct.price,
                  validFrom: existingProduct.updatedAt,
                  validUntil: now,
                  createdAt: now,
                );
                await (db.update(db.productPriceHistories)
                      ..where((h) =>
                          h.productId.equals(prodId) & h.validUntil.isNull()))
                    .write(
                        ProductPriceHistoriesCompanion(validUntil: Value(now)));

                if (incomingPv != null &&
                    incomingPv != existingProduct.priceVersionId) {
                  final existingMatch = await _findPriceHistoryVersionInTx(
                    productId: prodId,
                    priceVersionId: incomingPv,
                  );
                  if (existingMatch == null || existingMatch.price == price) {
                    priceVersionId = incomingPv;
                  } else {
                    priceVersionId = 'pv_${now.microsecondsSinceEpoch}';
                  }
                } else {
                  priceVersionId = 'pv_${now.microsecondsSinceEpoch}';
                }

                await _insertPriceHistoryVersionIfAbsentInTx(
                  productId: prodId,
                  priceVersionId: priceVersionId,
                  price: price,
                  validFrom: now,
                  createdAt: now,
                );
              } else {
                priceVersionId = existingProduct.priceVersionId;
                if (incomingPv != null &&
                    incomingPv != existingProduct.priceVersionId) {
                  final existingMatch = await _findPriceHistoryVersionInTx(
                    productId: prodId,
                    priceVersionId: incomingPv,
                  );
                  if (existingMatch == null) {
                    await _insertPriceHistoryVersionIfAbsentInTx(
                      productId: prodId,
                      priceVersionId: existingProduct.priceVersionId,
                      price: existingProduct.price,
                      validFrom: existingProduct.updatedAt,
                      createdAt: now,
                    );
                    await _insertPriceHistoryVersionIfAbsentInTx(
                      productId: prodId,
                      priceVersionId: incomingPv,
                      price: price,
                      validFrom: now,
                      createdAt: now,
                    );
                    priceVersionId = incomingPv;
                  }
                }
              }

              await (db.update(db.products)..where((p) => p.id.equals(prodId))).write(
                ProductsCompanion(
                  name: Value(name),
                  barcode: Value(effectiveBarcode),
                  price: Value(price),
                  priceVersionId: Value(priceVersionId),
                  // Faz 7A (Owner onayı 21.11.2026): Mevcut ürünün stoğu istemcinin mutlak
                  // (bayat olabilecek) değeriyle EZİLMEZ. Stok yalnızca hareketlerle değişir:
                  // SALE_CREATE / SALE_CANCEL / SALE_REFUND / STOCK_RECEIPT.
                  stockUnit: Value(productData['stock_unit'] as String? ?? existingProduct.stockUnit),
                  pricingUnit: Value(productData['pricing_unit'] as String? ?? existingProduct.pricingUnit),
                  conversionFactorNumerator: Value(productData['conversion_factor_numerator'] as int? ?? existingProduct.conversionFactorNumerator),
                  conversionFactorDenominator: Value(productData['conversion_factor_denominator'] as int? ?? existingProduct.conversionFactorDenominator),
                  isActive: Value(productData['is_active'] as bool? ?? existingProduct.isActive),
                  updatedAt: Value(now),
                ),
              );
            } else {
              priceVersionId =
                  incomingPv ?? 'pv_init_${now.microsecondsSinceEpoch}';
              await db.into(db.products).insert(
                ProductsCompanion(
                  id: Value(prodId),
                  barcode: Value(effectiveBarcode),
                  name: Value(name),
                  price: Value(price),
                  priceVersionId: Value(priceVersionId),
                  stock: Value(productData['stock'] as int? ?? 0),
                  stockUnit: Value(productData['stock_unit'] as String? ?? 'adet'),
                  pricingUnit: Value(productData['pricing_unit'] as String? ?? 'adet'),
                  conversionFactorNumerator: Value(productData['conversion_factor_numerator'] as int? ?? 1),
                  conversionFactorDenominator: Value(productData['conversion_factor_denominator'] as int? ?? 1),
                  isActive: Value(productData['is_active'] as bool? ?? true),
                  updatedAt: Value(now),
                ),
              );

              await _insertPriceHistoryVersionIfAbsentInTx(
                productId: prodId,
                priceVersionId: priceVersionId,
                price: price,
                validFrom: now,
                createdAt: now,
              );
            }

            // GAP-A01: Çoklu/ikincil barkodları Hub product_barcodes tablosuna atomik işle
            if (hasBarcodesField) {
              final existingBcRows = await (db.select(db.productBarcodes)
                    ..where((b) => b.productId.equals(prodId)))
                  .get();
              for (final oldRow in existingBcRows) {
                if (!allIncomingBarcodes.contains(oldRow.barcode)) {
                  await (db.update(db.productBarcodes)
                        ..where((b) => b.id.equals(oldRow.id)))
                      .write(const ProductBarcodesCompanion(
                        isActive: Value(false),
                        isPrimary: Value(false),
                      ));
                }
              }
            } else {
              await (db.update(db.productBarcodes)
                    ..where((b) => b.productId.equals(prodId)))
                  .write(const ProductBarcodesCompanion(isPrimary: Value(false)));
            }

            for (var idx = 0; idx < allIncomingBarcodes.length; idx++) {
              final bcVal = allIncomingBarcodes[idx];
              final isPrimaryBc = bcVal == effectiveBarcode;
              final existingBc = await (db.select(db.productBarcodes)
                    ..where((b) => b.barcode.equals(bcVal)))
                  .getSingleOrNull();
              if (existingBc != null) {
                await (db.update(db.productBarcodes)
                      ..where((b) => b.id.equals(existingBc.id)))
                    .write(ProductBarcodesCompanion(
                      isPrimary: Value(isPrimaryBc),
                      isActive: const Value(true),
                    ));
              } else {
                final bcRowId = isPrimaryBc
                    ? 'bc_${prodId}_primary_${now.microsecondsSinceEpoch}'
                    : 'bc_${prodId}_alt_${idx}_${now.microsecondsSinceEpoch}';
                await db.into(db.productBarcodes).insert(
                  ProductBarcodesCompanion(
                    id: Value(bcRowId),
                    productId: Value(prodId),
                    barcode: Value(bcVal),
                    isPrimary: Value(isPrimaryBc),
                    isActive: const Value(true),
                    createdAt: Value(now),
                  ),
                );
              }
            }

            final res = {
              'status': 'COMMITTED',
              'operation_type': 'PRODUCT_UPSERT',
              'device_id': deviceId,
              'client_seq': clientSeq,
              'product_id': prodId,
              'price_version_id': priceVersionId,
              'processed_at': now.toIso8601String(),
              '__hash_version': CanonicalPayloadHasher.hashVersionV2Canonical,
              '__request_hash': incomingCanonicalHash,
            };

            final encoded = await _commitReceiptAndAdvanceHwmInTx(
              operationId: operationId,
              deviceId: deviceId,
              idempotencyKey: idempotencyKey,
              clientSeq: clientSeq,
              operationType: 'PRODUCT_UPSERT',
              canonicalHash: incomingCanonicalHash,
              responsePayload: res,
              committedAt: now,
            );

            return _MutationTxResult(isReplay: false, bodyJson: encoded);
          });
        });

        return Response.ok(
          txResult.bodyJson,
          headers: {
            'content-type': 'application/json',
            if (txResult.isReplay) 'x-mms-idempotent-replay': 'true',
          },
        );
      } on _IdempotencyConflictException catch (e) {
        return _idempotencyConflictResponse(e.idempotencyKey);
      } on _IdempotencyHashUnverifiableException catch (e) {
        return _idempotencyHashUnverifiableResponse(e.idempotencyKey);
      } on _SequenceGapException catch (e) {
        return _sequenceGapResponse(e);
      } on _ValidationException catch (e) {
        return Response(
          e.statusCode,
          body: jsonEncode({
            'error': 'BAD_REQUEST',
            'code': e.code,
            'message': e.message,
          }),
          headers: {'content-type': 'application/json'},
        );
      } catch (e, stack) {
        final safeErr = redactLogText('$e\n$stack');
        stderr.writeln('PRODUCT_UPSERT işlenirken beklenmeyen hata: $safeErr');
        return Response.internalServerError(
          body: jsonEncode({
            'error': 'INTERNAL_ERROR',
            'code': 'ERR_INTERNAL_SERVER_ERROR',
            'message': 'Ürün kaydedilirken sunucu hatası oluştu: ${redactLogText(e.toString())}',
          }),
          headers: {'content-type': 'application/json'},
        );
      }
    });


    // 4.8. Mevcut Ürüne Stok Girişi (Outbox STOCK_RECEIPT - Delta, Idempotent, FIFO)
    // Owner onayı (21.11.2026): Mutlak stok yerine delta taşır; aynı receipt_id ikinci kez uygulanmaz.
    _router.post('/api/v1/stock/receipts', (Request req) async {
      final deviceId = req.context['authenticated_device_id'] as String?;
      if (deviceId == null) {
        return Response(
          401,
          body: jsonEncode({
            'error': 'UNAUTHORIZED',
            'code': 'ERR_AUTH_REQUIRED',
            'message': 'Stok girişi için yetkili bir cihaz oturumu gereklidir.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final bodyStr = await req.readAsString();
      final Map<String, dynamic> body;
      try {
        body = jsonDecode(bodyStr) as Map<String, dynamic>;
      } catch (_) {
        return _validationErrorResponse(
          _ValidationException(400, 'ERR_INVALID_JSON', 'Geçersiz JSON formatı.'),
        );
      }

      final rawClientSeq = body['client_seq'];
      final receiptId = (body['receipt_id'] as String?)?.trim() ?? '';
      final productId = (body['product_id'] as String?)?.trim() ?? '';
      final rawQuantity = body['quantity'];
      final unit = (body['unit'] as String?)?.trim() ?? '';
      final rawPurchase = body['unit_purchase_price'];
      final rawNote = body['note'];

      _ValidationException? invalid;
      if (rawClientSeq is! int || rawClientSeq <= 0) {
        invalid = _ValidationException(400, 'ERR_INVALID_CLIENT_SEQ', 'client_seq pozitif bir tamsayı (> 0) olmalıdır.');
      } else if (receiptId.isEmpty || receiptId.length > 128) {
        invalid = _ValidationException(400, 'ERR_INVALID_RECEIPT_ID', 'receipt_id zorunludur (en fazla 128 karakter).');
      } else if (productId.isEmpty) {
        invalid = _ValidationException(400, 'ERR_INVALID_PRODUCT_ID', 'product_id zorunludur.');
      } else if (rawQuantity is! int || rawQuantity <= 0 || rawQuantity > 1000000000) {
        invalid = _ValidationException(400, 'ERR_INVALID_QUANTITY', 'quantity pozitif milli-birim tamsayısı olmalıdır.');
      } else if (unit.isEmpty) {
        invalid = _ValidationException(400, 'ERR_INVALID_UNIT', 'unit zorunludur.');
      } else if (rawPurchase != null &&
          (rawPurchase is! int || rawPurchase < 0 || rawPurchase > 100000000000)) {
        invalid = _ValidationException(
            400, 'ERR_INVALID_PURCHASE_PRICE', 'unit_purchase_price negatif olmayan kuruş tamsayısı olmalıdır.');
      } else if (rawNote != null && (rawNote is! String || rawNote.length > 200)) {
        invalid = _ValidationException(400, 'ERR_INVALID_NOTE', 'note en fazla 200 karakterlik metin olmalıdır.');
      }
      if (invalid != null) {
        return _validationErrorResponse(invalid);
      }
      final clientSeq = rawClientSeq as int;
      final quantity = rawQuantity as int;
      final purchasePrice = rawPurchase as int?;
      final note = rawNote as String?;
      final occurredAt = DateTime.tryParse(body['occurred_at'] as String? ?? '');

      final operationId = body['operation_id'] as String? ?? 'op_stock_$receiptId';
      final idempotencyKey = '$deviceId:$clientSeq';
      final incomingCanonicalHash = CanonicalPayloadHasher.computeCanonicalV2(
        operationType: 'STOCK_RECEIPT',
        body: body,
      );

      final existingOp = await (db.select(db.processedOperations)
            ..where((o) => o.idempotencyKey.equals(idempotencyKey)))
          .getSingleOrNull();
      if (existingOp != null) {
        return _evaluateExistingReceipt(
          existingOp: existingOp,
          operationType: 'STOCK_RECEIPT',
          incomingBody: body,
          rawBody: bodyStr,
          idempotencyKey: idempotencyKey,
        );
      }

      try {
        final txResult = await writeQueue.enqueue(() async {
          return await db.transaction(() async {
            final txReplay = await _checkExistingReceiptInTx(
              idempotencyKey: idempotencyKey,
              operationType: 'STOCK_RECEIPT',
              incomingBody: body,
              rawBody: bodyStr,
            );
            if (txReplay != null) {
              return txReplay;
            }

            await _assertExpectedClientSeqInTx(deviceId, clientSeq);

            final product = await (db.select(db.products)
                  ..where((p) => p.id.equals(productId)))
                .getSingleOrNull();
            if (product == null) {
              throw _ValidationException(
                  404, 'ERR_PRODUCT_NOT_FOUND', 'Stok girişi yapılacak ürün Hub üzerinde bulunamadı: $productId');
            }
            if (product.stockUnit != unit) {
              throw _ValidationException(
                422,
                'ERR_UNIT_MISMATCH',
                'Stok girişi birimi ($unit) ürünün stok birimiyle (${product.stockUnit}) uyuşmuyor.',
              );
            }

            final now = DateTime.now();
            final existingMovement = await (db.select(db.stockMovements)
                  ..where((m) => m.id.equals(receiptId)))
                .getSingleOrNull();

            final String status;
            final int newStock;
            // Yinelenen giriş aynı operation_id ile yeni client_seq'te gelebilir; makbuz PK'sı
            // (processed_operations.operation_id) çakışmasın diye seq ile ayrıştırılır.
            var receiptOperationId = '$operationId#seq$clientSeq';
            if (existingMovement != null) {
              // Aynı stok girişi farklı client_seq ile tekrar geldi: ikinci kez UYGULANMAZ,
              // ancak FIFO kuyruğu kilitlenmesin diye makbuz yazılır ve HWM ilerler.
              final same = existingMovement.movementType == 'GIRIS' &&
                  existingMovement.productId == productId &&
                  existingMovement.quantity == quantity;
              if (!same) {
                throw _ValidationException(
                  409,
                  'ERR_STOCK_RECEIPT_CONFLICT',
                  'receipt_id ($receiptId) farklı içerikle daha önce işlenmiş; stok değiştirilmedi.',
                );
              }
              status = 'DUPLICATE_RECEIPT_IGNORED';
              newStock = product.stock;
            } else {
              receiptOperationId = operationId;
              if (product.stock > 9223372036854775807 - quantity) {
                throw _ValidationException(422, 'ERR_STOCK_OVERFLOW', 'Stok artışı tamsayı sınırını aşıyor.');
              }
              // Read-modify-write yerine SQL seviyesinde atomik delta
              await db.customUpdate(
                'UPDATE products SET stock = stock + ?, updated_at = ? WHERE id = ?;',
                variables: [
                  Variable.withInt(quantity),
                  Variable.withDateTime(now),
                  Variable.withString(productId),
                ],
                updates: {db.products},
              );
              await db.into(db.stockMovements).insert(
                    StockMovementsCompanion(
                      id: Value(receiptId),
                      productId: Value(productId),
                      quantity: Value(quantity),
                      unit: Value(unit),
                      movementType: const Value('GIRIS'),
                      referenceId: Value(receiptId),
                      purchasePrice: Value(purchasePrice),
                      note: Value(note),
                      createdAt: Value(occurredAt ?? now),
                    ),
                  );
              status = 'COMMITTED';
              newStock = product.stock + quantity;
            }

            final res = {
              'status': status,
              'operation_type': 'STOCK_RECEIPT',
              'device_id': deviceId,
              'client_seq': clientSeq,
              'receipt_id': receiptId,
              'product_id': productId,
              'new_stock': newStock,
              'processed_at': now.toIso8601String(),
              '__hash_version': CanonicalPayloadHasher.hashVersionV2Canonical,
              '__request_hash': incomingCanonicalHash,
            };

            final encoded = await _commitReceiptAndAdvanceHwmInTx(
              operationId: receiptOperationId,
              deviceId: deviceId,
              idempotencyKey: idempotencyKey,
              clientSeq: clientSeq,
              operationType: 'STOCK_RECEIPT',
              canonicalHash: incomingCanonicalHash,
              responsePayload: res,
              committedAt: now,
            );
            return _MutationTxResult(isReplay: false, bodyJson: encoded);
          });
        });

        return Response.ok(
          txResult.bodyJson,
          headers: {
            'content-type': 'application/json',
            if (txResult.isReplay) 'x-mms-idempotent-replay': 'true',
          },
        );
      } on _IdempotencyConflictException catch (e) {
        return _idempotencyConflictResponse(e.idempotencyKey);
      } on _IdempotencyHashUnverifiableException catch (e) {
        return _idempotencyHashUnverifiableResponse(e.idempotencyKey);
      } on _SequenceGapException catch (e) {
        return _sequenceGapResponse(e);
      } on _ValidationException catch (e) {
        return _validationErrorResponse(e);
      } catch (e, stack) {
        stderr.writeln(
          'STOCK_RECEIPT işlenirken beklenmeyen hata: ${redactLogText('$e\n$stack')}',
        );
        return Response.internalServerError(
          body: jsonEncode({
            'error': 'INTERNAL_ERROR',
            'code': 'ERR_INTERNAL_SERVER_ERROR',
            'message': 'Stok girişi işlenirken sunucu hatası oluştu.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }
    });

    // 5. Atomik Satış ve Stok Düşümü (Idempotent)
    _router.post('/api/v1/sales', (Request req) async {
      // device_id ASLA istemci payload'ından alınmaz; kimliği doğrulanmış request context'ten alınır
      final deviceId = req.context['authenticated_device_id'] as String;
      final bodyStr = await req.readAsString();
      final Map<String, dynamic> body;
      try {
        final decoded = jsonDecode(bodyStr);
        if (decoded is! Map<String, dynamic>) {
          return Response(
            400,
            body: jsonEncode({
              'error': 'BAD_REQUEST',
              'code': 'ERR_INVALID_JSON',
              'message': 'İstek gövdesi geçerli bir JSON nesnesi olmalıdır.',
            }),
            headers: {'content-type': 'application/json'},
          );
        }
        body = decoded;
      } catch (_) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'BAD_REQUEST',
            'code': 'ERR_INVALID_JSON',
            'message': 'Geçersiz JSON formatı.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final rawClientSeq = body['client_seq'];
      if (rawClientSeq is! int || rawClientSeq <= 0) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'BAD_REQUEST',
            'code': 'ERR_INVALID_CLIENT_SEQ',
            'message': 'client_seq pozitif bir tamsayı (> 0) olmalıdır.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }
      final clientSeq = rawClientSeq;
      final operationType = CanonicalPayloadHasher.resolveSaleOperationType(body);
      if (operationType != 'SALE_CREATE' &&
          operationType != 'SALE_CANCEL' &&
          operationType != 'SALE_REFUND') {
        return Response(
          400,
          body: jsonEncode({
            'error': 'BAD_REQUEST',
            'code': 'ERR_UNSUPPORTED_OPERATION_TYPE',
            'message': 'Desteklenmeyen satış işlem türü: $operationType',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final operationId = body['operation_id'] as String? ?? 'op_${DateTime.now().microsecondsSinceEpoch}';
      final idempotencyKey = '$deviceId:$clientSeq';
      final incomingCanonicalHash = CanonicalPayloadHasher.computeCanonicalV2(
        operationType: operationType,
        body: body,
      );

      // A. Önce Idempotency kontrolü (Inbox defteri - replay & conflict önce çalışır)
      final existingOp = await (db.select(db.processedOperations)
            ..where((o) => o.idempotencyKey.equals(idempotencyKey)))
          .getSingleOrNull();

      if (existingOp != null) {
        return _evaluateExistingReceipt(
          existingOp: existingOp,
          operationType: operationType,
          incomingBody: body,
          rawBody: bodyStr,
          idempotencyKey: idempotencyKey,
        );
      }

      // B. FAZ 1.3.3 & BK-02.1.1: SALE_CANCEL İşlemi (Fail-Closed İş Bütünlüğü)
      if (operationType == 'SALE_CANCEL') {
        final saleId = body['sale_id'] as String?;
        final rawTargetClientSeq = body['target_client_seq'];
        if (rawTargetClientSeq != null && rawTargetClientSeq is! int) {
          return Response(
            400,
            body: jsonEncode({
              'error': 'BAD_REQUEST',
              'code': 'ERR_INVALID_CANCEL_REQUEST',
              'message': 'target_client_seq tamsayı olmalıdır.',
            }),
            headers: {'content-type': 'application/json'},
          );
        }
        final targetClientSeq = rawTargetClientSeq as int?;
        if (body.containsKey('reason') &&
            (body['reason'] is! String || (body['reason'] as String).trim().isEmpty)) {
          return Response(
            400,
            body: jsonEncode({
              'error': 'BAD_REQUEST',
              'code': 'ERR_INVALID_CANCEL_REQUEST',
              'message': 'İptal gerekçesi (reason) boş olamaz.',
            }),
            headers: {'content-type': 'application/json'},
          );
        }
        final reason = (body['reason'] as String?)?.trim() ?? 'İptal';

        if ((saleId == null || saleId.trim().isEmpty) && targetClientSeq == null) {
          return Response(
            400,
            body: jsonEncode({
              'error': 'BAD_REQUEST',
              'code': 'ERR_INVALID_CANCEL_REQUEST',
              'message': 'sale_id veya target_client_seq belirtilmelidir.',
            }),
            headers: {'content-type': 'application/json'},
          );
        }

        try {
          final txResult = await writeQueue.enqueue(() async {
            return await db.transaction(() async {
              final txReplay = await _checkExistingReceiptInTx(
                idempotencyKey: idempotencyKey,
                operationType: 'SALE_CANCEL',
                incomingBody: body,
                rawBody: bodyStr,
              );
              if (txReplay != null) {
                return txReplay;
              }

              // BK-02.1 Karar 3: Katı sequence gap kontrolü
              await _assertExpectedClientSeqInTx(deviceId, clientSeq);

              // BK-02.1.1: Satış bulunamazsa 404 ile transaction geri alınır
              final originalSale = await _resolveTargetSaleInTx(
                deviceId: deviceId,
                rawSaleId: saleId,
                targetClientSeq: targetClientSeq,
              );

              if (originalSale.status == 'CANCELLED') {
                throw _ValidationException(
                  409,
                  'ERR_SALE_ALREADY_CANCELLED',
                  'Bu satış (${originalSale.id}) zaten iptal edilmiştir; ikinci kez iptal edilemez.',
                );
              }
              if (originalSale.status == 'REFUNDED') {
                throw _ValidationException(
                  409,
                  'ERR_SALE_ALREADY_REFUNDED',
                  'Tamamen iade edilmiş satış (${originalSale.id}) iptal edilemez.',
                );
              }

              final saleItems = await (db.select(db.saleItems)
                    ..where((i) => i.saleId.equals(originalSale.id)))
                  .get();

              // Kısmi iade edilmiş kalemler (hem SELLABLE hem DAMAGED) tespit edilir
              final existingRefunds = await (db.select(db.refunds)
                    ..where((r) => r.saleId.equals(originalSale.id)))
                  .get();
              final refundedQtyBySaleItemId = <String, int>{};
              for (final ref in existingRefunds) {
                final refItems = await (db.select(db.refundItems)
                      ..where((ri) => ri.refundId.equals(ref.id)))
                    .get();
                for (final ri in refItems) {
                  final matched = _matchSaleItem(
                    saleItems,
                    saleItemId: ri.saleItemId,
                    productId: ri.productId,
                  );
                  if (matched != null) {
                    refundedQtyBySaleItemId[matched.id] =
                        (refundedQtyBySaleItemId[matched.id] ?? 0) + ri.quantity;
                  }
                }
              }

              if (saleItems.isNotEmpty &&
                  saleItems.every(
                    (si) => (refundedQtyBySaleItemId[si.id] ?? 0) >= si.quantity,
                  )) {
                throw _ValidationException(
                  409,
                  'ERR_SALE_ALREADY_REFUNDED',
                  'Satışın (${originalSale.id}) tüm kalemleri zaten iade edilmiştir.',
                );
              }

              const maxSafeInt = 0x7FFFFFFFFFFFFFFF;
              final updatedStocks = <String, int>{};
              final runningStockByProductId = <String, int>{};
              final stockRestores = <Map<String, dynamic>>[];

              // Doğrulama ve stok hesaplaması (yazım öncesi validasyon)
              for (var i = 0; i < saleItems.length; i++) {
                final item = saleItems[i];
                final alreadyRefunded = refundedQtyBySaleItemId[item.id] ?? 0;
                final remainingQty = item.quantity - alreadyRefunded;
                if (remainingQty <= 0) continue;

                final product = await (db.select(db.products)
                      ..where((p) => p.id.equals(item.productId)))
                    .getSingleOrNull();
                if (product == null) {
                  throw StateError(
                    'İptal edilecek satış kalemi ürünü bulunamadı: ${item.productId}',
                  );
                }

                final num = product.conversionFactorNumerator;
                final den = product.conversionFactorDenominator;
                if (num <= 0 || den <= 0) {
                  throw StateError('Geçersiz dönüşüm katsayısı ($num / $den): ${product.name}');
                }
                if (remainingQty > maxSafeInt ~/ num) {
                  throw _ValidationException(
                    400,
                    'ERR_ARITHMETIC_OVERFLOW',
                    'Birim dönüşümü çarpımında 64-bit tamsayı taşması riski: ${product.name}',
                  );
                }
                final stockDelta = (remainingQty * num) ~/ den;
                stockRestores.add({
                  'index': i,
                  'product': product,
                  'stockDelta': stockDelta,
                });
              }

              final maxSeqRow = await db.customSelect('SELECT COALESCE(MAX(server_seq), 0) as m FROM sales;').getSingle();
              final nextServerSeq = (maxSeqRow.data['m'] as int) + 1;

              await (db.update(db.sales)..where((s) => s.id.equals(originalSale.id))).write(
                SalesCompanion(
                  status: const Value('CANCELLED'),
                  cancelReason: Value(reason),
                  cancelledAt: Value(DateTime.now()),
                  serverSeq: Value(nextServerSeq),
                ),
              );

              for (final entry in stockRestores) {
                final idx = entry['index'] as int;
                final product = entry['product'] as Product;
                final stockDelta = entry['stockDelta'] as int;
                if (stockDelta > 0) {
                  await db.into(db.stockMovements).insert(
                        StockMovementsCompanion(
                          id: Value('sm_cancel_${originalSale.id}_${product.id}_${DateTime.now().microsecondsSinceEpoch}_$idx'),
                          productId: Value(product.id),
                          quantity: Value(stockDelta),
                          unit: Value(product.stockUnit),
                          movementType: const Value('SATIS_IPTALI'),
                          referenceId: Value(originalSale.id),
                        ),
                      );
                }

                final currentStock =
                    runningStockByProductId[product.id] ?? product.stock;
                final newStock = currentStock + stockDelta;
                runningStockByProductId[product.id] = newStock;
                await (db.update(db.products)..where((p) => p.id.equals(product.id)))
                    .write(ProductsCompanion(stock: Value(newStock)));
                updatedStocks[product.id] = newStock;
              }

              final committedAt = DateTime.now();
              final responsePayload = {
                'status': 'COMMITTED',
                'operation_type': 'SALE_CANCEL',
                'sale_id': originalSale.id,
                'device_id': deviceId,
                'client_seq': clientSeq,
                'reason': reason,
                'updated_stocks': updatedStocks,
                'committed_at': committedAt.toIso8601String(),
                '__hash_version': CanonicalPayloadHasher.hashVersionV2Canonical,
                '__request_hash': incomingCanonicalHash,
              };

              final encoded = await _commitReceiptAndAdvanceHwmInTx(
                operationId: operationId,
                deviceId: deviceId,
                idempotencyKey: idempotencyKey,
                clientSeq: clientSeq,
                operationType: 'SALE_CANCEL',
                canonicalHash: incomingCanonicalHash,
                responsePayload: responsePayload,
                committedAt: committedAt,
              );

              return _MutationTxResult(isReplay: false, bodyJson: encoded);
            });
          });

          if (txResult.isReplay) {
            return Response.ok(
              txResult.bodyJson,
              headers: {
                'content-type': 'application/json',
                'x-mms-idempotent-replay': 'true',
              },
            );
          }

          return Response(
            201,
            body: txResult.bodyJson,
            headers: {'content-type': 'application/json'},
          );
        } on _IdempotencyConflictException catch (e) {
          return _idempotencyConflictResponse(e.idempotencyKey);
        } on _IdempotencyHashUnverifiableException catch (e) {
          return _idempotencyHashUnverifiableResponse(e.idempotencyKey);
        } on _SequenceGapException catch (e) {
          return _sequenceGapResponse(e);
        } on _ValidationException catch (e) {
          return _validationErrorResponse(e);
        } catch (e) {
          final safeErr = redactLogText(e.toString());
          stderr.writeln('[ERROR] Satış iptal transaction hatası: $safeErr');
          return Response.internalServerError(
            body: jsonEncode({
              'error': 'TRANSACTION_FAILED',
              'code': 'ERR_TRANSACTION_FAILED',
              'message': 'Sunucu tarafında işlem işlenirken hata oluştu: $safeErr',
            }),
            headers: {'content-type': 'application/json'},
          );
        }
      }

      // C. FAZ 1.3.4 & BK-02.1.1: SALE_REFUND İşlemi (Fail-Closed Miktar/Tutar/Durum Bütünlüğü)
      if (operationType == 'SALE_REFUND') {
        final refundId = body['refund_id'] as String?;
        final saleId = body['sale_id'] as String?;
        final rawTotalRefundAmount = body['total_refund_amount'];
        final rawRefundItems = body['items'] as List?;
        final rawTargetClientSeq = body['target_client_seq'];
        if (rawTargetClientSeq != null && rawTargetClientSeq is! int) {
          return Response(
            400,
            body: jsonEncode({
              'error': 'BAD_REQUEST',
              'code': 'ERR_INVALID_REFUND_REQUEST',
              'message': 'target_client_seq tamsayı olmalıdır.',
            }),
            headers: {'content-type': 'application/json'},
          );
        }
        if (body.containsKey('reason') &&
            (body['reason'] is! String || (body['reason'] as String).trim().isEmpty)) {
          return Response(
            400,
            body: jsonEncode({
              'error': 'BAD_REQUEST',
              'code': 'ERR_INVALID_REFUND_REQUEST',
              'message': 'İade gerekçesi (reason) boş olamaz.',
            }),
            headers: {'content-type': 'application/json'},
          );
        }
        final reason = (body['reason'] as String?)?.trim() ?? 'İade';

        if (refundId == null ||
            refundId.trim().isEmpty ||
            rawRefundItems == null ||
            rawRefundItems.isEmpty) {
          return Response(
            400,
            body: jsonEncode({
              'error': 'BAD_REQUEST',
              'code': 'ERR_INVALID_REFUND_REQUEST',
              'message': 'refund_id ve en az bir kalem içeren items listesi zorunludur.',
            }),
            headers: {'content-type': 'application/json'},
          );
        }

        try {
          final txResult = await writeQueue.enqueue(() async {
            return await db.transaction(() async {
              final txReplay = await _checkExistingReceiptInTx(
                idempotencyKey: idempotencyKey,
                operationType: 'SALE_REFUND',
                incomingBody: body,
                rawBody: bodyStr,
              );
              if (txReplay != null) {
                return txReplay;
              }

              // BK-02.1 Karar 3: Katı sequence gap kontrolü
              await _assertExpectedClientSeqInTx(deviceId, clientSeq);

              final firstItemSaleId = rawRefundItems.first is Map
                  ? (rawRefundItems.first as Map)['sale_id'] as String?
                  : null;
              final rawSaleId = saleId ?? firstItemSaleId;
              final targetClientSeq = rawTargetClientSeq as int?;

              // BK-02.1.1: Satış bulunamazsa 404 ERR_SALE_NOT_FOUND ile rollback yapılır
              final origSale = await _resolveTargetSaleInTx(
                deviceId: deviceId,
                rawSaleId: rawSaleId,
                targetClientSeq: targetClientSeq,
              );
              final effectiveSaleId = origSale.id;

              if (origSale.status == 'CANCELLED') {
                throw _ValidationException(
                  409,
                  'ERR_SALE_ALREADY_CANCELLED',
                  'İptal edilmiş satış ($effectiveSaleId) üzerinden iade yapılamaz.',
                );
              }
              if (origSale.status == 'REFUNDED') {
                throw _ValidationException(
                  409,
                  'ERR_SALE_ALREADY_REFUNDED',
                  'Tamamen iade edilmiş satış ($effectiveSaleId) üzerinden yeni iade yapılamaz.',
                );
              }

              final saleItems = await (db.select(db.saleItems)
                    ..where((i) => i.saleId.equals(effectiveSaleId)))
                  .get();
              if (saleItems.isEmpty) {
                throw _ValidationException(
                  409,
                  'ERR_SALE_ITEMS_MISSING',
                  'Satışa ($effectiveSaleId) ait kalem bulunamadı.',
                );
              }

              final existingRefunds = await (db.select(db.refunds)
                    ..where((r) => r.saleId.equals(effectiveSaleId)))
                  .get();
              final totalAlreadyRefunded = existingRefunds.fold<int>(
                0,
                (sum, r) => sum + r.totalRefundAmount,
              );

              final refundedQtyBySaleItemId = <String, int>{};
              for (final ref in existingRefunds) {
                final refItems = await (db.select(db.refundItems)
                      ..where((ri) => ri.refundId.equals(ref.id)))
                    .get();
                for (final ri in refItems) {
                  final matched = _matchSaleItem(
                    saleItems,
                    saleItemId: ri.saleItemId,
                    productId: ri.productId,
                  );
                  if (matched != null) {
                    refundedQtyBySaleItemId[matched.id] =
                        (refundedQtyBySaleItemId[matched.id] ?? 0) + ri.quantity;
                  }
                }
              }

              if (totalAlreadyRefunded >= origSale.totalAmount ||
                  saleItems.every(
                    (si) => (refundedQtyBySaleItemId[si.id] ?? 0) >= si.quantity,
                  )) {
                throw _ValidationException(
                  409,
                  'ERR_SALE_ALREADY_REFUNDED',
                  'Satış ($effectiveSaleId) zaten tamamen iade edilmiştir.',
                );
              }

              var calculatedTotalRefundAmount = 0;
              final validatedItems = <Map<String, dynamic>>[];

              // Tüm iade kalemlerini herhangi bir DB yazımından ÖNCE doğrula
              for (var i = 0; i < rawRefundItems.length; i++) {
                final rawItem = rawRefundItems[i];
                if (rawItem is! Map<String, dynamic>) {
                  throw _ValidationException(
                    400,
                    'ERR_INVALID_REFUND_ITEM',
                    'İade kalemi geçerli bir JSON nesnesi olmalıdır.',
                  );
                }

                final pId = rawItem['product_id'] as String?;
                final rawSaleItemId = rawItem['sale_item_id'] as String?;
                final qty = rawItem['quantity'];
                if (qty is! int || qty <= 0) {
                  throw _ValidationException(
                    400,
                    'ERR_INVALID_REFUND_QUANTITY',
                    'İade miktarı pozitif bir tamsayı (> 0) olmalıdır: $qty',
                  );
                }

                final rawCondition = rawItem['product_condition'];
                if (rawCondition != null &&
                    rawCondition != 'SELLABLE' &&
                    rawCondition != 'DAMAGED') {
                  throw _ValidationException(
                    400,
                    'ERR_INVALID_PRODUCT_CONDITION',
                    'product_condition yalnızca SELLABLE veya DAMAGED olabilir: $rawCondition',
                  );
                }
                final condition = (rawCondition as String?) ?? 'SELLABLE';

                final matchedSaleItem = _matchSaleItem(
                  saleItems,
                  saleItemId: rawSaleItemId,
                  productId: pId,
                );
                if (matchedSaleItem == null) {
                  throw _ValidationException(
                    400,
                    'ERR_REFUND_ITEM_NOT_IN_SALE',
                    'İade edilmek istenen ürün ($pId) orijinal satış kalemlerinde bulunmuyor.',
                  );
                }

                final alreadyRefundedQty = refundedQtyBySaleItemId[matchedSaleItem.id] ?? 0;
                final maxReturnableQty = matchedSaleItem.quantity - alreadyRefundedQty;
                if (qty > maxReturnableQty) {
                  throw _ValidationException(
                    409,
                    'ERR_REFUND_EXCEEDS_SALE',
                    'İade miktarı ($qty), kalan iade edilebilir miktarı ($maxReturnableQty) aşıyor (product_id=${matchedSaleItem.productId}).',
                  );
                }
                refundedQtyBySaleItemId[matchedSaleItem.id] = alreadyRefundedQty + qty;

                final effectiveUnitPrice = matchedSaleItem.unitPrice;
                final providedUnitPrice = rawItem['unit_price'];
                if (providedUnitPrice != null &&
                    (providedUnitPrice is! int || providedUnitPrice != effectiveUnitPrice)) {
                  throw _ValidationException(
                    400,
                    'ERR_REFUND_UNIT_PRICE_MISMATCH',
                    'İade birim fiyatı ($providedUnitPrice), satış anı snapshot birim fiyatıyla ($effectiveUnitPrice) eşleşmiyor.',
                  );
                }

                const int maxSafeInt = 9223372036854775807;
                if (effectiveUnitPrice > 0 && qty > (maxSafeInt - 500) ~/ effectiveUnitPrice) {
                  throw _ValidationException(
                    400,
                    'ERR_INTEGER_OVERFLOW',
                    'Birim fiyat ve iade miktarı çarpımı güvenli tamsayı sınırını aşıyor.',
                  );
                }

                // Half-Up kuruş yuvarlama standardı (OD-01)
                final expectedItemRefundAmount = ((effectiveUnitPrice * qty) + 500) ~/ 1000;
                final providedRefundAmount = rawItem['refund_amount'];
                if (providedRefundAmount != null &&
                    (providedRefundAmount is! int ||
                        providedRefundAmount != expectedItemRefundAmount)) {
                  throw _ValidationException(
                    400,
                    'ERR_REFUND_AMOUNT_MISMATCH',
                    'Kalem iade tutarı ($providedRefundAmount), Half-Up beklenen tutarla ($expectedItemRefundAmount) eşleşmiyor.',
                  );
                }

                if (calculatedTotalRefundAmount > maxSafeInt - expectedItemRefundAmount) {
                  throw _ValidationException(
                    400,
                    'ERR_INTEGER_OVERFLOW',
                    'Toplam iade tutarı güvenli tamsayı sınırını aşıyor.',
                  );
                }
                calculatedTotalRefundAmount += expectedItemRefundAmount;

                final product = await (db.select(db.products)
                      ..where((p) => p.id.equals(matchedSaleItem.productId)))
                    .getSingleOrNull();
                if (product == null) {
                  throw StateError(
                    'İade kalemine ait ürün bulunamadı: ${matchedSaleItem.productId}',
                  );
                }

                final num = product.conversionFactorNumerator;
                final den = product.conversionFactorDenominator;
                if (num <= 0 || den <= 0) {
                  throw StateError('Geçersiz dönüşüm katsayısı ($num / $den): ${product.name}');
                }
                if (qty > maxSafeInt ~/ num) {
                  throw _ValidationException(
                    400,
                    'ERR_ARITHMETIC_OVERFLOW',
                    'Birim dönüşümü çarpımında 64-bit tamsayı taşması riski: ${product.name}',
                  );
                }
                if ((qty * num) % den != 0) {
                  throw _ValidationException(
                    400,
                    'ERR_UNIT_CONVERSION_PRECISION_LOSS',
                    'İade miktarı ($qty) ürünün dönüşüm katsayısı ($num/$den) ile tam bölünemediği için stok hassasiyet kaybı oluştu: ${product.name}',
                  );
                }
                final stockDelta = (qty * num) ~/ den;

                validatedItems.add({
                  'index': i,
                  'saleItem': matchedSaleItem,
                  'qty': qty,
                  'unitPrice': effectiveUnitPrice,
                  'refundAmount': expectedItemRefundAmount,
                  'condition': condition,
                  'product': product,
                  'stockDelta': stockDelta,
                });
              }

              if (rawTotalRefundAmount is! int || rawTotalRefundAmount <= 0) {
                throw _ValidationException(
                  400,
                  'ERR_INVALID_REFUND_TOTAL',
                  'total_refund_amount pozitif bir tamsayı (> 0) olmalıdır.',
                );
              }
              final totalRefundAmount = rawTotalRefundAmount;

              if (totalRefundAmount != calculatedTotalRefundAmount) {
                throw _ValidationException(
                  400,
                  'ERR_REFUND_TOTAL_MISMATCH',
                  'Toplam iade tutarı ($totalRefundAmount), kalem iade toplamlarıyla ($calculatedTotalRefundAmount) eşleşmiyor.',
                );
              }

              if (totalAlreadyRefunded + totalRefundAmount > origSale.totalAmount) {
                throw _ValidationException(
                  409,
                  'ERR_REFUND_EXCEEDS_SALE',
                  'Kümülatif iade tutarı (${totalAlreadyRefunded + totalRefundAmount}), satış toplam tutarını (${origSale.totalAmount}) aşıyor.',
                );
              }

              // Bütün doğrulamalar geçti — atomik yazımlar
              final now = DateTime.now();
              final updatedStocks = <String, int>{};
              final runningStockByProductId = <String, int>{};
              final maxSeqRow = await db.customSelect('SELECT COALESCE(MAX(server_seq), 0) as m FROM sales;').getSingle();
              final nextServerSeq = (maxSeqRow.data['m'] as int) + 1;

              await db.into(db.refunds).insert(
                RefundsCompanion(
                  id: Value(refundId.trim()),
                  saleId: Value(effectiveSaleId),
                  deviceId: Value(deviceId),
                  clientSeq: Value(clientSeq),
                  totalRefundAmount: Value(totalRefundAmount),
                  paymentMethod: Value(origSale.paymentMethod),
                  reason: Value(reason),
                  createdAt: Value(now),
                ),
              );

              for (final entry in validatedItems) {
                final idx = entry['index'] as int;
                final matchedSaleItem = entry['saleItem'] as SaleItem;
                final qty = entry['qty'] as int;
                final unitPrice = entry['unitPrice'] as int;
                final itemRefundAmount = entry['refundAmount'] as int;
                final condition = entry['condition'] as String;
                final product = entry['product'] as Product;
                final stockDelta = entry['stockDelta'] as int;

                await db.into(db.refundItems).insert(
                  RefundItemsCompanion(
                    id: Value('refitem_${refundId.trim()}_${matchedSaleItem.productId}_${now.microsecondsSinceEpoch}_$idx'),
                    refundId: Value(refundId.trim()),
                    saleItemId: Value(matchedSaleItem.id),
                    productId: Value(matchedSaleItem.productId),
                    quantity: Value(qty),
                    unitPrice: Value(unitPrice),
                    refundAmount: Value(itemRefundAmount),
                    productCondition: Value(condition),
                    createdAt: Value(now),
                  ),
                );

                if (condition == 'SELLABLE') {
                  await db.into(db.stockMovements).insert(
                        StockMovementsCompanion(
                          id: Value('sm_ref_${refundId.trim()}_${product.id}_${now.microsecondsSinceEpoch}_$idx'),
                          productId: Value(product.id),
                          quantity: Value(stockDelta),
                          unit: Value(product.stockUnit),
                          movementType: const Value('MUSTERI_IADESI'),
                          referenceId: Value(refundId.trim()),
                        ),
                      );

                  final baseStock = runningStockByProductId[product.id] ?? product.stock;
                  final newStock = baseStock + stockDelta;
                  runningStockByProductId[product.id] = newStock;
                  await (db.update(db.products)..where((p) => p.id.equals(product.id)))
                      .write(ProductsCompanion(stock: Value(newStock)));
                  updatedStocks[product.id] = newStock;
                } else {
                  await db.into(db.stockMovements).insert(
                        StockMovementsCompanion(
                          id: Value('sm_fire_${refundId.trim()}_${product.id}_${now.microsecondsSinceEpoch}_$idx'),
                          productId: Value(product.id),
                          quantity: Value(stockDelta),
                          unit: Value(product.stockUnit),
                          movementType: const Value('FIRE_KAYIP'),
                          referenceId: Value(refundId.trim()),
                        ),
                      );
                }
              }

              final allItemsFullyRefunded = saleItems.every(
                (si) => (refundedQtyBySaleItemId[si.id] ?? 0) >= si.quantity,
              );
              final newStatus =
                  (allItemsFullyRefunded || (totalAlreadyRefunded + totalRefundAmount) >= origSale.totalAmount)
                      ? 'REFUNDED'
                      : 'PARTIALLY_REFUNDED';

              await (db.update(db.sales)..where((s) => s.id.equals(effectiveSaleId))).write(
                SalesCompanion(
                  serverSeq: Value(nextServerSeq),
                  status: Value(newStatus),
                ),
              );

              final committedAt = DateTime.now();
              final responsePayload = {
                'status': 'COMMITTED',
                'operation_type': 'SALE_REFUND',
                'refund_id': refundId.trim(),
                'sale_id': effectiveSaleId,
                'device_id': deviceId,
                'client_seq': clientSeq,
                'total_refund_amount': totalRefundAmount,
                'reason': reason,
                'updated_stocks': updatedStocks,
                'committed_at': committedAt.toIso8601String(),
                '__hash_version': CanonicalPayloadHasher.hashVersionV2Canonical,
                '__request_hash': incomingCanonicalHash,
              };

              final encoded = await _commitReceiptAndAdvanceHwmInTx(
                operationId: operationId,
                deviceId: deviceId,
                idempotencyKey: idempotencyKey,
                clientSeq: clientSeq,
                operationType: 'SALE_REFUND',
                canonicalHash: incomingCanonicalHash,
                responsePayload: responsePayload,
                committedAt: committedAt,
              );

              return _MutationTxResult(isReplay: false, bodyJson: encoded);
            });
          });

          if (txResult.isReplay) {
            return Response.ok(
              txResult.bodyJson,
              headers: {
                'content-type': 'application/json',
                'x-mms-idempotent-replay': 'true',
              },
            );
          }

          return Response(
            201,
            body: txResult.bodyJson,
            headers: {'content-type': 'application/json'},
          );
        } on _IdempotencyConflictException catch (e) {
          return _idempotencyConflictResponse(e.idempotencyKey);
        } on _IdempotencyHashUnverifiableException catch (e) {
          return _idempotencyHashUnverifiableResponse(e.idempotencyKey);
        } on _SequenceGapException catch (e) {
          return _sequenceGapResponse(e);
        } on _ValidationException catch (e) {
          return _validationErrorResponse(e);
        } catch (e) {
          final safeErr = redactLogText(e.toString());
          stderr.writeln('[ERROR] Kısmi iade transaction hatası: $safeErr');
          return Response.internalServerError(
            body: jsonEncode({
              'error': 'TRANSACTION_FAILED',
              'code': 'ERR_TRANSACTION_FAILED',
              'message': 'Sunucu tarafında işlem işlenirken hata oluştu: $safeErr',
            }),
            headers: {'content-type': 'application/json'},
          );
        }
      }

      // D. FAZ 1.2 / 1.3: Normal Satış (SALE_CREATE)
      final rawTotalAmount = body['total_amount'];
      if (rawTotalAmount is! int || rawTotalAmount <= 0 || rawTotalAmount > 100000000000) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'BAD_REQUEST',
            'code': 'ERR_INVALID_TOTAL_AMOUNT',
            'message': 'total_amount pozitif ve geçerli bir tamsayı olmalıdır.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }
      final totalAmount = rawTotalAmount;

      final rawItems = body['items'];
      if (rawItems is! List || rawItems.isEmpty) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'BAD_REQUEST',
            'code': 'ERR_INVALID_ITEMS',
            'message': 'Satış en az bir kalem içermelidir.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }
      final items = rawItems;
      final rawPaymentMethod = body['payment_method'];

      // Kanonik ödeme yöntemi doğrulaması:
      // Yeni satışlarda yalnız 'CASH' ve 'CARD' kabul edilir; eksik, null, metin dışı
      // veya geçersiz/eski ('CREDIT_CARD', 'NAKIT') değerler asla sessizce 'CASH' yapılmaz.
      if (!PaymentMethod.isCanonical(rawPaymentMethod)) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'BAD_REQUEST',
            'code': 'ERR_INVALID_PAYMENT_METHOD',
            'message': 'Geçersiz veya eksik payment_method değeri. Yalnızca "CASH" veya "CARD" kabul edilir.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }
      final paymentMethod = PaymentMethod.parse(rawPaymentMethod).code;

      // B. Yeni işlem: Tekil yazıcı kuyruğunda atomik transaction işlet
      try {
        final txResult = await writeQueue.enqueue(() async {
          return await db.transaction(() async {
            final txReplay = await _checkExistingReceiptInTx(
              idempotencyKey: idempotencyKey,
              operationType: 'SALE_CREATE',
              incomingBody: body,
              rawBody: bodyStr,
            );
            if (txReplay != null) {
              return txReplay;
            }

            // BK-02.1 Karar 3: Katı sequence gap kontrolü
            await _assertExpectedClientSeqInTx(deviceId, clientSeq);

            int calculatedTotalAmount = 0;
            final itemValidations = <Map<String, dynamic>>[];

            for (final item in items) {
              if (item is! Map<String, dynamic>) {
                throw _ValidationException(400, 'ERR_INVALID_ITEM_FORMAT', 'Kalem formatı geçersiz.');
              }
              final pId = item['product_id'] as String?;
              final qty = item['quantity'] as int?;
              final uPrice = item['unit_price'] as int?;
              final tPrice = item['total_price'] as int?;
              final priceVersionId = item['price_version_id'] as String?;

              if (pId == null || pId.isEmpty) {
                throw _ValidationException(400, 'ERR_INVALID_PRODUCT_ID', 'Geçersiz ürün kimliği.');
              }
              if (qty == null || qty <= 0 || qty > 1000000000) {
                throw _ValidationException(400, 'ERR_INVALID_QUANTITY', 'Miktar pozitif ve geçerli bir tamsayı olmalıdır (> 0): $qty');
              }
              if (uPrice == null || uPrice < 0 || uPrice > 100000000000) {
                throw _ValidationException(400, 'ERR_INVALID_PRICE', 'Birim fiyat negatif veya aşırı büyük olamaz: $uPrice');
              }
              if (tPrice == null || tPrice < 0 || tPrice > 9223372036854775807) {
                throw _ValidationException(400, 'ERR_INVALID_TOTAL_PRICE', 'Satır tutarı negatif olamaz: $tPrice');
              }

              // S5A-3: Çarpım öncesi Integer Overflow kontrolü (Dart 64-bit int)
              const int maxSafeInt = 9223372036854775807;
              if (uPrice > 0 && qty > (maxSafeInt - 500) ~/ uPrice) {
                throw _ValidationException(400, 'ERR_INTEGER_OVERFLOW', 'Birim fiyat ve miktar çarpımı güvenli tamsayı sınırını aşıyor.');
              }

              final product = await (db.select(db.products)..where((p) => p.id.equals(pId))).getSingleOrNull();
              if (product == null) {
                throw StateError('Ürün bulunamadı: $pId. Satış transactionı iptal edildi.');
              }

              // S5A-3 (Topic 1): Fiyat Snapshot ve Fiyat Sürümü Doğrulaması
              if (priceVersionId == null || priceVersionId == product.priceVersionId) {
                // İstemci güncel fiyat sürümünü veya varsayılanı kullanıyorsa güncel fiyatla birebir eşleşmeli
                if (uPrice != product.price) {
                  throw _ValidationException(
                    400,
                    'ERR_UNRECOGNIZED_PRICE',
                    'Ürün ($pId) fiyatı ($uPrice) geçerli fiyat sürümü (${product.price}) ile uyuşmuyor.',
                  );
                }
              } else {
                // Belirtilen fiyat sürümü için geçmiş fiyat defteri doğrulaması
                final historyMatch = await _findPriceHistoryVersionInTx(
                  productId: pId,
                  priceVersionId: priceVersionId,
                );

                if (historyMatch == null) {
                  throw _ValidationException(
                    400,
                    'ERR_UNRECOGNIZED_PRICE_VERSION',
                    'Bilinmeyen veya ürünle eşleşmeyen fiyat sürümü: $priceVersionId (Ürün: $pId)',
                  );
                }

                if (uPrice != historyMatch.price) {
                  throw _ValidationException(
                    400,
                    'ERR_PRICE_MISMATCH',
                    'Ürün ($pId) fiyatı ($uPrice) belirtilen fiyat sürümü (${historyMatch.price}) ile uyuşmuyor.',
                  );
                }

                // Cihazın bu fiyat sürümünü kullanabilirliğini doğrula:
                // Cihazın son ürün senkronizasyon zamanı, fiyatın geçerlilik bitişinden (validUntil) sonra ise bu sürümü kullanamaz!
                final device = await (db.select(db.devices)..where((d) => d.deviceId.equals(deviceId))).getSingleOrNull();
                if (historyMatch.validUntil != null && device != null && device.lastProductSyncAt != null) {
                  if (device.lastProductSyncAt!.isAfter(historyMatch.validUntil!)) {
                    throw _ValidationException(
                      400,
                      'ERR_PRICE_VERSION_EXPIRED_FOR_DEVICE',
                      'Fiyat sürümü ($priceVersionId) bu cihaz için geçerli değildir; cihaz daha yeni bir ürün senkronizasyonu almıştır.',
                    );
                  }
                }
              }

              // S5A-3 (Topic 3): Tek Miktar Sözleşmesi — Miktar her zaman scale=1000'dir.
              // Geriye uyumluluk veya tahmin mantığı olmaksızın katı standart sözleşme formülü:
              final expectedTotalPrice = ((uPrice * qty) + 500) ~/ 1000;
              if (tPrice != expectedTotalPrice) {
                throw _ValidationException(
                  400,
                  'ERR_ITEM_TOTAL_MISMATCH',
                  'Satır tutarı hatalı. Gönderilen: $tPrice, beklenen (scale=1000): $expectedTotalPrice',
                );
              }

              // Toplam sepet tutarı ekleme öncesi overflow kontrolü
              if (calculatedTotalAmount > maxSafeInt - tPrice) {
                throw _ValidationException(400, 'ERR_INTEGER_OVERFLOW', 'Toplam sepet tutarı güvenli tamsayı sınırını aşıyor.');
              }
              calculatedTotalAmount += tPrice;

              // Birim ve Stok Dönüşümü (scale=1000 milli-birim)
              final num = product.conversionFactorNumerator;
              final den = product.conversionFactorDenominator;
              if (num <= 0 || den <= 0) {
                throw StateError('Geçersiz dönüşüm katsayısı ($num / $den): ${product.name}');
              }

              // Çarpım öncesi overflow kontrolü
              if (num > 0 && qty > maxSafeInt ~/ num) {
                throw _ValidationException(400, 'ERR_INTEGER_OVERFLOW', 'Miktar ve birim katsayısı çarpımı güvenli tamsayı sınırını aşıyor.');
              }

              final prodMilli = qty * num;
              if (prodMilli % den != 0) {
                throw _ValidationException(
                  400,
                  'ERR_UNIT_CONVERSION_PRECISION_LOSS',
                  'Miktar ($qty) ürün stok birimine (${product.stockUnit}) kayıpsız dönüştürülemiyor.',
                );
              }
              final stockDelta = prodMilli ~/ den;

              itemValidations.add({
                'product': product,
                'pId': pId,
                'qty': qty,
                'uPrice': uPrice,
                'tPrice': tPrice,
                'stockDelta': stockDelta,
              });
            }

            // Toplam sepet tutarı kontrolü
            if (calculatedTotalAmount != totalAmount) {
              throw _ValidationException(
                400,
                'ERR_TOTAL_AMOUNT_MISMATCH',
                'Sepet toplam tutarı hatalı. Gönderilen: $totalAmount, satır toplamları: $calculatedTotalAmount',
              );
            }

            final saleId = 'sale_${DateTime.now().microsecondsSinceEpoch}';
            final maxSeqRow = await db.customSelect('SELECT COALESCE(MAX(server_seq), 0) as m FROM sales;').getSingle();
            final nextServerSeq = (maxSeqRow.data['m'] as int) + 1;

            await db.into(db.sales).insert(
                  SalesCompanion(
                    id: Value(saleId),
                    deviceId: Value(deviceId),
                    clientSeq: Value(clientSeq),
                    totalAmount: Value(totalAmount),
                    paymentMethod: Value(paymentMethod),
                    serverSeq: Value(nextServerSeq),
                    status: const Value('COMPLETED'),
                  ),
                );

            final simulatedDelayMs = body['simulated_delay_ms'] as int? ?? 0;
            if (simulatedDelayMs > 0) {
              await Future.delayed(Duration(milliseconds: simulatedDelayMs));
            }

            final updatedStocks = <String, int>{};
            for (final item in itemValidations) {
              final product = item['product'] as Product;
              final pId = item['pId'] as String;
              final qty = item['qty'] as int;
              final uPrice = item['uPrice'] as int;
              final tPrice = item['tPrice'] as int;
              final stockDelta = item['stockDelta'] as int;

              await db.into(db.saleItems).insert(
                    SaleItemsCompanion(
                      id: Value('item_${DateTime.now().microsecondsSinceEpoch}_$pId'),
                      saleId: Value(saleId),
                      productId: Value(pId),
                      quantity: Value(qty),
                      unitPrice: Value(uPrice),
                      totalPrice: Value(tPrice),
                    ),
                  );

              await db.into(db.stockMovements).insert(
                    StockMovementsCompanion(
                      id: Value('sm_${DateTime.now().microsecondsSinceEpoch}_$pId'),
                      productId: Value(pId),
                      quantity: Value(-stockDelta),
                      unit: Value(product.stockUnit),
                      movementType: const Value('SATIS'),
                      referenceId: Value(saleId),
                    ),
                  );

              // S5A-2: Fiziksel satış stok yetersizliği nedeniyle ASLA reddedilmez;
              // eksiye düşebilir ve stok hareketi negatif olarak kaydedilir.
              final currentStock = product.stock;
              final newStock = currentStock - stockDelta;

              await (db.update(db.products)..where((p) => p.id.equals(pId)))
                  .write(ProductsCompanion(stock: Value(newStock)));
              updatedStocks[pId] = newStock;
            }

            final committedAt = DateTime.now();
            final responsePayload = {
              'status': 'COMMITTED',
              'operation_type': 'SALE_CREATE',
              'sale_id': saleId,
              'device_id': deviceId,
              'client_seq': clientSeq,
              'total_amount': totalAmount,
              'updated_stocks': updatedStocks,
              'committed_at': committedAt.toIso8601String(),
              '__hash_version': CanonicalPayloadHasher.hashVersionV2Canonical,
              '__request_hash': incomingCanonicalHash,
            };

            final encoded = await _commitReceiptAndAdvanceHwmInTx(
              operationId: operationId,
              deviceId: deviceId,
              idempotencyKey: idempotencyKey,
              clientSeq: clientSeq,
              operationType: 'SALE_CREATE',
              canonicalHash: incomingCanonicalHash,
              responsePayload: responsePayload,
              committedAt: committedAt,
            );

            return _MutationTxResult(isReplay: false, bodyJson: encoded);
          });
        });

        if (txResult.isReplay) {
          return Response.ok(
            txResult.bodyJson,
            headers: {
              'content-type': 'application/json',
              'x-mms-idempotent-replay': 'true',
            },
          );
        }

        // S5A-2: Commit-before-ACK (Drift SQLite transaction tamamlandıktan sonra 201 Created döner)
        return Response(
          201,
          body: txResult.bodyJson,
          headers: {'content-type': 'application/json'},
        );
      } on _IdempotencyConflictException catch (e) {
        return _idempotencyConflictResponse(e.idempotencyKey);
      } on _IdempotencyHashUnverifiableException catch (e) {
        return _idempotencyHashUnverifiableResponse(e.idempotencyKey);
      } on _SequenceGapException catch (e) {
        return _sequenceGapResponse(e);
      } on _ValidationException catch (e) {
        return Response(
          e.statusCode,
          body: jsonEncode({
            'error': 'BAD_REQUEST',
            'code': e.code,
            'message': e.message,
          }),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        stderr.writeln(
          '[ERROR] Satış transaction hatası: ${e.runtimeType} -> ${redactLogText(e.toString())}',
        );
        return Response.internalServerError(
          body: jsonEncode({
            'error': 'TRANSACTION_FAILED',
            'code': 'ERR_TRANSACTION_FAILED',
            'message': 'İşlem sunucu hatası nedeniyle tamamlanamadı.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }
    });

    // 5.1. BK-02.1: Authenticated Cihaz Sequence / High-Water Mark Durumu (Salt-Okunur)
    _router.get('/api/v1/sync/device-state', (Request req) async {
      final deviceId = req.context['authenticated_device_id'] as String?;
      if (deviceId == null) {
        return Response(
          401,
          body: jsonEncode({
            'error': 'UNAUTHORIZED',
            'code': 'ERR_AUTH_REQUIRED',
            'message': 'Cihaz senkronizasyon durumu için yetkili bir cihaz oturumu gereklidir.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final snapshot = await DeviceSequenceInspector.inspectDevice(db, deviceId);
      final hwm = snapshot.hwmSummary;
      final restoreEpoch = await _readRestoreEpoch();
      final rawRole =
          (req.context['authenticated_device_role'] as String?)?.toUpperCase();
      final canonicalRole = rawRole == 'OWNER' ? 'OWNER' : 'CASHIER';

      return Response.ok(
        jsonEncode({
          'device_id': deviceId,
          'role': canonicalRole,
          'tenant_id': tenantId,
          'store_id': storeId,
          'hub_id': hubId,
          'restore_epoch': restoreEpoch,
          'high_water_mark_seq': hwm.contiguousHwm,
          'max_seen_client_seq': hwm.maxSeenClientSeq,
          'expected_next_client_seq': hwm.expectedNextClientSeq,
          'committed_operation_count': hwm.committedOperationCount,
          'has_sequence_gaps': hwm.hasSequenceGaps,
          'missing_seq_sample': hwm.missingSeqSample,
          'unverifiable_receipt_count': snapshot.unverifiableReceiptCount,
          'latest_server_sale_seq': snapshot.latestServerSaleSeq,
          'last_committed_at': snapshot.lastCommittedAt?.toIso8601String(),
          'server_time': DateTime.now().toUtc().toIso8601String(),
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    // 5.1b. K-05: Authenticated & TLS-Pinned Live Drive Sync Konfigürasyonu Teslimi
    _router.get('/api/v1/sync/live-drive-config', (Request req) async {
      final deviceId = req.context['authenticated_device_id'] as String?;
      if (deviceId == null) {
        return Response(
          401,
          body: jsonEncode({
            'error': 'UNAUTHORIZED',
            'code': 'ERR_AUTH_REQUIRED',
            'message': 'Live Drive yapılandırması için yetkili bir cihaz oturumu gereklidir.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final devices = await (db.select(db.devices)
            ..orderBy([(d) => OrderingTerm.asc(d.deviceId)]))
          .get();
      final devicesJson = devices
          .map((d) => <String, dynamic>{
                'device_id': d.deviceId,
                'tenant_id': tenantId,
                'store_id': storeId,
                'status': (d.isActive && d.isConfirmed) ? 'ACTIVE' : 'REVOKED',
                'updated_at':
                    (d.lastUsedAt ?? d.createdAt).toUtc().toIso8601String(),
              })
          .toList();

      return Response.ok(
        jsonEncode({
          'version': 1,
          'tenant_id': tenantId,
          'store_id': storeId,
          'hub_id': hubId,
          'live_sync_secret': liveDriveSecretManager.secret,
          'authorized_devices': devicesJson,
          'server_time': DateTime.now().toUtc().toIso8601String(),
        }),
        headers: {
          'content-type': 'application/json',
          'cache-control': 'no-store',
        },
      );
    });

    // 5.2. BK-02.1: Authenticated İşlem Makbuzları Sorgulama (Salt-Okunur, Cihaz İzolasyonlu)
    _router.post('/api/v1/sync/receipts', (Request req) async {
      final deviceId = req.context['authenticated_device_id'] as String?;
      if (deviceId == null) {
        return Response(
          401,
          body: jsonEncode({
            'error': 'UNAUTHORIZED',
            'code': 'ERR_AUTH_REQUIRED',
            'message': 'Makbuz sorgulama için yetkili bir cihaz oturumu gereklidir.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final bodyStr = await req.readAsString();
      final Map<String, dynamic> body;
      try {
        final decoded = jsonDecode(bodyStr);
        if (decoded is! Map<String, dynamic>) {
          return Response(
            400,
            body: jsonEncode({
              'error': 'BAD_REQUEST',
              'code': 'ERR_INVALID_JSON',
              'message': 'İstek gövdesi geçerli bir JSON nesnesi olmalıdır.',
            }),
            headers: {'content-type': 'application/json'},
          );
        }
        body = decoded;
      } catch (_) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'BAD_REQUEST',
            'code': 'ERR_INVALID_JSON',
            'message': 'Geçersiz JSON formatı.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // İsteğe bağlı olarak gövdede device_id belirtilmişse kimliği doğrulanmış cihazla uyuşması zorunludur
      final requestedDeviceId = body['device_id'];
      if (requestedDeviceId != null && requestedDeviceId.toString().trim() != deviceId) {
        return Response(
          403,
          body: jsonEncode({
            'error': 'FORBIDDEN',
            'code': 'ERR_DEVICE_ID_MISMATCH',
            'message': 'Başka bir cihazın işlem makbuzları sorgulanamaz.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final rawClientSeqs = body['client_seqs'];
      if (rawClientSeqs is! List) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'BAD_REQUEST',
            'code': 'ERR_INVALID_CLIENT_SEQS',
            'message': 'client_seqs alanı pozitif tamsayılardan oluşan bir liste olmalıdır.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }
      if (rawClientSeqs.length > 500) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'BAD_REQUEST',
            'code': 'ERR_RECEIPTS_BATCH_TOO_LARGE',
            'message': 'Tek istekte en fazla 500 client_seq makbuzu sorgulanabilir.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final uniqueSeqs = <int>[];
      final seenSeqs = <int>{};
      for (final rawSeq in rawClientSeqs) {
        if (rawSeq is! int || rawSeq <= 0) {
          return Response(
            400,
            body: jsonEncode({
              'error': 'BAD_REQUEST',
              'code': 'ERR_INVALID_CLIENT_SEQS',
              'message': 'client_seqs listesindeki tüm değerler pozitif tamsayı (> 0) olmalıdır.',
            }),
            headers: {'content-type': 'application/json'},
          );
        }
        if (seenSeqs.add(rawSeq)) {
          uniqueSeqs.add(rawSeq);
        }
      }

      final snapshot = await DeviceSequenceInspector.inspectDevice(db, deviceId);
      final hwm = snapshot.hwmSummary;

      final receipts = <Map<String, dynamic>>[];
      if (uniqueSeqs.isNotEmpty) {
        final uniqueKeys = uniqueSeqs.map((s) => '$deviceId:$s').toList();
        final matchedOps = await (db.select(db.processedOperations)
              ..where((o) =>
                  o.deviceId.equals(deviceId) &
                  (o.clientSeq.isIn(uniqueSeqs) | o.idempotencyKey.isIn(uniqueKeys))))
            .get();

        final bySeq = <int, ProcessedOperation>{};
        for (final op in matchedOps) {
          if (op.clientSeq != null && op.clientSeq! > 0) {
            bySeq[op.clientSeq!] = op;
          } else {
            final sepIdx = op.idempotencyKey.lastIndexOf(':');
            if (sepIdx > 0 && sepIdx < op.idempotencyKey.length - 1) {
              final parsed = int.tryParse(op.idempotencyKey.substring(sepIdx + 1));
              if (parsed != null && parsed > 0) {
                bySeq.putIfAbsent(parsed, () => op);
              }
            }
          }
        }

        for (final seq in uniqueSeqs) {
          final op = bySeq[seq];
          if (op == null) {
            receipts.add({
              'client_seq': seq,
              'status': 'NOT_FOUND',
              'is_hash_verifiable': false,
            });
            continue;
          }

          final hasValidHash = CanonicalPayloadHasher.isValidSha256Hex(op.requestHash);
          final hasVersion = op.hashVersion != null && op.hashVersion!.trim().isNotEmpty;
          final verifiable = hasValidHash && hasVersion;

          if (!verifiable) {
            receipts.add({
              'client_seq': seq,
              'status': 'UNVERIFIABLE_LEGACY',
              'operation_id': op.operationId,
              'operation_type': op.operationType,
              'request_hash': null,
              'hash_version': null,
              'is_hash_verifiable': false,
              'processed_at': op.processedAt.toIso8601String(),
            });
          } else {
            receipts.add({
              'client_seq': seq,
              'status': 'FOUND',
              'operation_id': op.operationId,
              'operation_type': op.operationType,
              'request_hash': op.requestHash,
              'hash_version': op.hashVersion,
              'is_hash_verifiable': true,
              'processed_at': op.processedAt.toIso8601String(),
            });
          }
        }
      }

      final restoreEpoch = await _readRestoreEpoch();
      return Response.ok(
        jsonEncode({
          'device_id': deviceId,
          'tenant_id': tenantId,
          'store_id': storeId,
          'hub_id': hubId,
          'restore_epoch': restoreEpoch,
          'high_water_mark_seq': hwm.contiguousHwm,
          'max_seen_client_seq': hwm.maxSeenClientSeq,
          'expected_next_client_seq': hwm.expectedNextClientSeq,
          'has_sequence_gaps': hwm.hasSequenceGaps,
          'receipts': receipts,
          'server_time': DateTime.now().toUtc().toIso8601String(),
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    // 6. Canlı Snapshot / Yedekleme Uç Noktası (VACUUM INTO - Hardened & Çakışma Korumalı)
    _router.post('/api/v1/backup/snapshot', (Request req) async {
      // SEC-SNAP (Faz 7B): Bu uç ŞİFRESİZ bir merkezi DB kopyası (cihaz token hash/salt
      // değerleri dahil) üretir. Kasa cihazı token'ı ile erişilemez; yalnızca loopback +
      // yapılandırılmış ADMIN_SECRET (Owner) ile çağrılabilir. Rutin yedekler için şifreli
      // `/api/v1/admin/backup` ve zamanlanmış yedekleme kullanılır.
      final adminDenied = _verifyLoopbackAndAdmin(req, actionName: "Şifresiz bakım snapshot'ı");
      if (adminDenied != null) return adminDenied;

      final bodyStr = await req.readAsString();
      Map<String, dynamic> body = {};
      if (bodyStr.isNotEmpty) {
        try {
          body = jsonDecode(bodyStr) as Map<String, dynamic>;
        } catch (e) {
          stderr.writeln(
            '[WARN] İstek JSON gövdesi ayrıştırılamadı (${req.requestedUri.path}): ${e.runtimeType}',
          );
        }
      }

      // SQL Injection karakter kontrolü (Şüpheli karakterler anında 400 ile reddedilir)
      if (body.containsKey('target_path')) {
        final clientPath = body['target_path']?.toString() ?? '';
        if (clientPath.contains("'") ||
            clientPath.contains(';') ||
            clientPath.contains('--') ||
            clientPath.contains('\x00')) {
          return Response(
            400,
            body: jsonEncode({
              'error': 'INVALID_REQUEST',
              'code': 'ERR_MALICIOUS_INPUT',
              'message': 'Geçersiz yedekleme parametresi.',
            }),
            headers: {'content-type': 'application/json'},
          );
        }
      }

      // Güvenlik Kuralı: İstemcinin verdiği keyfi dosya yolu KESİNLİKLE kabul edilmez.
      // Dosya yolu sunucu tarafında sabit ve korumalı dizinde üretilir.
      // Not: /backup/snapshot eşzamanlı isteklerde writeQueue üzerinden sıralanır ve
      // benzersiz nonce dosya adı üretir; restore sırasında admissionGate + pauseForMaintenance ile engellenir.
      final targetDir = _backupTargetDir;
      try {
        if (!targetDir.existsSync()) {
          targetDir.createSync(recursive: true);
        }
        final safeBackupPath = _generateUniqueBackupPath(targetDir);

        await writeQueue.enqueue(() async {
          final escapedPath = safeBackupPath.replaceAll("'", "''");
          await db.customStatement("VACUUM INTO '$escapedPath';");
        });

        return Response.ok(
          jsonEncode({
            'status': 'SUCCESS',
            'backup_path': safeBackupPath,
            'timestamp': DateTime.now().toIso8601String(),
          }),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({
            'error': 'SNAPSHOT_FAILED',
            'message': 'Anlık görüntü yedeklemesi başarısız oldu.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }
    });

    // 6.1. S5A-4: Merkezi Veritabanı Şifreli Yedekleme (Encrypted Backup with Manifest)
    _router.post('/api/v1/admin/backup', (Request req) async {
      // SEC: Sabit varsayılan admin secret fallback'i kaldırıldı. Yalnızca loopback + yapılandırılmış
      // ADMIN_SECRET ile erişilir; yapılandırılmamışsa fail-closed 503 döner.
      final adminDenied = _verifyLoopbackAndAdmin(req, actionName: 'Yedekleme/geri yükleme yönetimi');
      if (adminDenied != null) return adminDenied;

      final bodyStr = await req.readAsString();
      Map<String, dynamic> body = {};
      if (bodyStr.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(bodyStr);
          if (decoded is! Map<String, dynamic>) {
            return Response(
              400,
              body: jsonEncode({
                'error': 'BAD_REQUEST',
                'code': 'ERR_INVALID_JSON',
                'message': 'İstek gövdesi JSON nesnesi olmalıdır.',
              }),
              headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
            );
          }
          body = decoded;
        } catch (_) {
          return Response(
            400,
            body: jsonEncode({
              'error': 'BAD_REQUEST',
              'code': 'ERR_INVALID_JSON',
              'message': 'Geçersiz JSON formatı.',
            }),
            headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
          );
        }
      }

      // S2: İstekle parola gönderilmesi (backup_password / recovery_password) reddedilir;
      // şifreleme yalnızca Hub DPAPI kasasında kayıtlı Portable Recovery Password kullanır.
      if (body.containsKey('backup_password') || body.containsKey('recovery_password')) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'INVALID_REQUEST',
            'code': 'ERR_BACKUP_PASSWORD_NOT_ACCEPTED',
            'message': 'İstek gövdesinde parola kabul edilmez; Hub yalnızca kayıtlı Kurtarma Parolasını kullanır.',
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      }

      final isMonthly = body['is_monthly_archive'] as bool? ?? false;

      try {
        final result = await createEncryptedHubBackup(
          isMonthlyArchive: isMonthly,
        );

        return Response.ok(
          jsonEncode({
            'status': 'SUCCESS',
            'backup_id': result.backupId,
            'manifest': result.manifest.toJson(),
            'created_at': result.createdAt.toIso8601String(),
            'recovery_key_source': 'HUB_STORED_DPAPI',
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      } on BackupException catch (e) {
        final status = _legacyBackupErrorStatus(e.code, fallback: 500);
        return Response(
          status,
          body: jsonEncode({
            'error': e.code == BackupOperationLock.busyErrorCode ? 'BACKUP_BUSY' : 'BACKUP_FAILED',
            'code': e.code,
            'message': e.message,
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      } catch (e) {
        stderr.writeln('[ERROR] POST /api/v1/admin/backup beklenmeyen hata: ${e.runtimeType}');
        return Response.internalServerError(
          body: jsonEncode({
            'error': 'BACKUP_FAILED',
            'code': 'ERR_BACKUP_INTERNAL',
            'message': 'Şifreli Hub yedeklemesi sırasında beklenmeyen bir sunucu hatası oluştu.',
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      }
    });

    // 6.2. S5A-4: Yedekleri Listeleme
    _router.get('/api/v1/admin/backups', (Request req) async {
      // SEC: Sabit varsayılan admin secret fallback'i kaldırıldı. Yalnızca loopback + yapılandırılmış
      // ADMIN_SECRET ile erişilir; yapılandırılmamışsa fail-closed 503 döner.
      final adminDenied = _verifyLoopbackAndAdmin(req, actionName: 'Yedekleme/geri yükleme yönetimi');
      if (adminDenied != null) return adminDenied;

      final storage = LocalStorageProvider(_backupTargetDir);
      final backups = await storage.listBackups();

      return Response.ok(
        jsonEncode({
          'status': 'SUCCESS',
          'count': backups.length,
          'backups': backups.map((b) => b.manifest.toJson()).toList(),
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    // 6.3. S5A-4 / AUD-MED-01: Kontrollü ve Koruyucu Yedekli Geri Yükleme (Restore)
    // HubRestoreService ortak çekirdeği üzerinden restore_epoch artırılır ve aktif
    // cihaz tokenları kontrollü geçersizleştirilir.
    _router.post('/api/v1/admin/restore', (Request req) async {
      // SEC: Sabit varsayılan admin secret fallback'i kaldırıldı. Yalnızca loopback + yapılandırılmış
      // ADMIN_SECRET ile erişilir; yapılandırılmamışsa fail-closed 503 döner.
      final adminDenied = _verifyLoopbackAndAdmin(req, actionName: 'Yedekleme/geri yükleme yönetimi');
      if (adminDenied != null) return adminDenied;

      final Map<String, dynamic> body;
      try {
        final decoded = jsonDecode(await req.readAsString());
        if (decoded is! Map<String, dynamic>) {
          return Response(
            400,
            body: jsonEncode({
              'error': 'BAD_REQUEST',
              'code': 'ERR_INVALID_JSON',
              'message': 'İstek gövdesi geçerli bir JSON nesnesi olmalıdır.',
            }),
            headers: {'content-type': 'application/json'},
          );
        }
        body = decoded;
      } on FormatException {
        return Response(
          400,
          body: jsonEncode({
            'error': 'BAD_REQUEST',
            'code': 'ERR_INVALID_JSON',
            'message': 'İstek gövdesi geçerli JSON biçiminde olmalıdır.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }
      final backupId = (body['backup_id'] as String?)?.trim();
      // ADR-023 B1.7: Varsayılan anahtar Portable Recovery Password'dür. Makineye bağlı
      // pepper yalnızca AYNI makinede alınmış eski S5A-4 yedeklerini açmak için ve yalnızca
      // açık `legacy_machine_key: true` onayıyla kullanılır (sessiz fallback yoktur).
      final explicitPassword = body['backup_password'] as String?;
      final useLegacyMachineKey = body['legacy_machine_key'] == true;

      if (backupId == null || backupId.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'BAD_REQUEST', 'message': 'backup_id parametresi zorunludur.'}),
          headers: {'content-type': 'application/json'},
        );
      }
      if (!_safeBackupIdPattern.hasMatch(backupId)) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'BAD_REQUEST',
            'code': 'ERR_INVALID_BACKUP_ID',
            'message': 'Geçersiz yedek kimliği.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final storage = LocalStorageProvider(_backupTargetDir);
      final targetLiveDb = dbFile ?? File(p.join(Directory.current.path, 'market_master.db'));

      try {
        final result = await _backupOperationLock.synchronized(
          BackupOperationKind.restore,
          () async {
            final effectivePassword = (explicitPassword == null && useLegacyMachineKey)
                ? pepperManager.pepper
                : await _resolvePortableBackupPassword(
                    explicitPassword,
                    enforceMinimumLength: false,
                  );

            File? packageFile;
            final hubCandidate =
                File(p.join(_backupTargetDir.path, 'hub_backup_$backupId.mmsbak'));
            if (await hubCandidate.exists()) {
              packageFile = hubCandidate;
            } else {
              final legacyCandidate = await storage.getBackupFile(backupId);
              if (await legacyCandidate.exists()) {
                packageFile = legacyCandidate;
              }
            }
            if (packageFile == null || !(await packageFile.exists())) {
              throw BackupException(
                'ERR_BACKUP_NOT_FOUND',
                'Yedek dosyası bulunamadı: $backupId',
              );
            }

            return HubRestoreService.restoreFromEncryptedPackage(
              packageFile: packageFile,
              recoveryPassword: effectivePassword,
              safetyBackupPassword: effectivePassword,
              liveDbFile: targetLiveDb,
              backupDir: _backupTargetDir,
              lock: _backupOperationLock,
              acquireLock: false,
              expectedTenantId: tenantId,
              expectedStoreId: storeId,
              expectedHubId: hubId,
              minSupportedSchemaVersion: 1,
              maxSupportedSchemaVersion: max(4, db.schemaVersion),
              kdfIterations: hubRestoreSafetyKdfIterations,
              pauseAndCloseLiveDb: () async {
                await lifecycle.admissionGate.pauseForMaintenance(allowedRemaining: 1);
                await writeQueue.pauseForMaintenance();
                try {
                  await db.checkpointWal(mode: 'TRUNCATE');
                } catch (e) {
                  stderr.writeln(
                    '[WARN] Admin restore öncesi WAL checkpoint uyarısı: ${e.runtimeType}',
                  );
                }
                await db.close();
              },
              reopenLiveDb: (File dbPath) async {
                final reopened = SpikeDatabase(dbPath);
                this.db = reopened;
                lifecycle.db = reopened;
                return reopened;
              },
              onDbReopened: (_, __) async {
                writeQueue.resumeAfterMaintenance();
                lifecycle.admissionGate.resumeAfterMaintenance();
                await _verifyOrInitializeHubIdentity();
              },
            );
          },
        );

        return Response.ok(
          jsonEncode({
            'status': 'RESTORED',
            'backup_id': result.backupId,
            'safety_backup_path': result.safetyBackupPath,
            'safety_backup_encrypted': result.safetyBackupEncrypted,
            'restored_at': result.restoredAtUtc.toIso8601String(),
            'restored_at_utc': result.restoredAtUtc.toIso8601String(),
            'restore_epoch': result.restoreEpoch,
            'invalidated_active_device_count': result.invalidatedActiveDeviceCount,
            'preserved_revoked_device_count': result.preservedRevokedDeviceCount,
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      } on BackupCryptoException catch (e) {
        writeQueue.resumeAfterMaintenance();
        lifecycle.admissionGate.resumeAfterMaintenance();
        return Response(
          400,
          body: jsonEncode({
            'error': 'RESTORE_FAILED',
            'code': 'ERR_DECRYPTION_FAILED',
            'message': e.message,
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      } on BackupException catch (e) {
        writeQueue.resumeAfterMaintenance();
        lifecycle.admissionGate.resumeAfterMaintenance();
        final status = _legacyBackupErrorStatus(e.code, fallback: 400);
        return Response(
          status,
          body: jsonEncode({
            'error': 'RESTORE_FAILED',
            'code': e.code,
            'message': e.message,
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      } catch (e) {
        writeQueue.resumeAfterMaintenance();
        lifecycle.admissionGate.resumeAfterMaintenance();
        return Response.internalServerError(
          body: jsonEncode({
            'error': 'INTERNAL_ERROR',
            'message': e.toString(),
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      }
    });

    // 6.3.1 Faz 3: Zamanlanmış yedek durumu ve geçmişi (Owner / loopback + admin)
    _router.get('/api/v1/admin/backup/status', (Request req) async {
      final adminDenied = _verifyLoopbackAndAdmin(req, actionName: 'Yedekleme durumu');
      if (adminDenied != null) return adminDenied;
      final policy = backupSchedule ?? BackupSchedulePolicy.disabled;
      final state = await BackupScheduleStateStore(backupScheduleStateFile).load();
      _backupScheduleState = state;
      return Response.ok(
        jsonEncode({
          'status': 'SUCCESS',
          'policy': policy.toJson(),
          'state': state.toJson(),
          'next_due_at': policy.nextDueAt(state)?.toUtc().toIso8601String(),
          'overdue': policy.isOverdue(state: state, now: DateTime.now().toUtc()),
          'backup_dir': _backupTargetDir.path,
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    // 6.4. S5A-4: Saklama Süresi Temizliği (Retention Prune)
    _router.post('/api/v1/admin/backup/prune', (Request req) async {
      // SEC: Sabit varsayılan admin secret fallback'i kaldırıldı. Yalnızca loopback + yapılandırılmış
      // ADMIN_SECRET ile erişilir; yapılandırılmamışsa fail-closed 503 döner.
      final adminDenied = _verifyLoopbackAndAdmin(req, actionName: 'Yedekleme/geri yükleme yönetimi');
      if (adminDenied != null) return adminDenied;

      final storage = LocalStorageProvider(_backupTargetDir);
      try {
        final pruned = await _backupOperationLock.synchronized(
          BackupOperationKind.backup,
          () => const RetentionPolicyManager().executePruning(storage),
        );

        return Response.ok(
          jsonEncode({
            'status': 'PRUNED',
            'count': pruned.length,
            'pruned_backup_ids': pruned,
          }),
          headers: {'content-type': 'application/json'},
        );
      } on BackupException catch (e) {
        final status = e.code == BackupOperationLock.busyErrorCode ? 409 : 500;
        return Response(
          status,
          body: jsonEncode({
            'error': e.code == BackupOperationLock.busyErrorCode ? 'BACKUP_BUSY' : 'PRUNE_FAILED',
            'code': e.code,
            'message': e.message,
          }),
          headers: {'content-type': 'application/json'},
        );
      }
    });

    // 6.5. Faz B-2: Hub Google Drive Backup OAuth PKCE Handoff ve Durumu (OV-01 & OV-02)
    _router.post('/api/v1/backup/oauth/connect', (Request req) async {
      final denied = _verifyOwnerOrLoopbackAdmin(
        req,
        actionName: 'Hub Google Drive OAuth bağlantısı',
      );
      if (denied != null) return denied;
      final replayDenied = await _verifyReplayProtection(
        req,
        actionName: 'Hub Google Drive OAuth bağlantısı',
      );
      if (replayDenied != null) return replayDenied;

      Map<String, dynamic> body;
      try {
        final raw = await req.readAsString();
        final decoded = raw.trim().isEmpty ? <String, dynamic>{} : jsonDecode(raw);
        if (decoded is! Map) {
          throw const FormatException('JSON nesnesi bekleniyor');
        }
        body = Map<String, dynamic>.from(decoded);
      } catch (_) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'INVALID_REQUEST',
            'code': 'ERR_INVALID_JSON',
            'message': 'Geçersiz JSON gövdesi.',
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      }

      final authCode = (body['auth_code'] as String?) ?? (body['code'] as String?) ?? '';
      final codeVerifier = (body['code_verifier'] as String?) ?? '';
      final redirectUri = (body['redirect_uri'] as String?) ?? '';
      final clientId = (body['client_id'] as String?) ?? '';
      final clientSecret = body['client_secret'] as String?;
      final accountEmail = body['account_email'] as String?;
      final folderId = body['folder_id'] as String?;

      try {
        final status = await hubBackupOAuthService.connectWithPkce(
          authCode: authCode,
          codeVerifier: codeVerifier,
          redirectUri: redirectUri,
          clientId: clientId,
          clientSecret: clientSecret,
          accountEmail: accountEmail,
          folderId: folderId,
        );
        final actorId =
            (req.context['authenticated_device_id'] as String?) ?? 'HUB_ADMIN';
        await writeQueue.enqueue(() async {
          await db.into(db.deviceAuditLogs).insert(
                DeviceAuditLogsCompanion(
                  deviceId: Value(actorId),
                  action: const Value('BACKUP_OAUTH_CONNECT'),
                  details: Value(
                    'Hub backup Drive OAuth connected (scope=${status.scope})',
                  ),
                ),
              );
        });
        return Response.ok(
          jsonEncode(status.toJson()),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      } on HubBackupOAuthException catch (e) {
        final statusCode = e.code == 'ERR_INVALID_PKCE_HANDOFF' ? 400 : 502;
        return Response(
          statusCode,
          body: jsonEncode({
            'error': 'OAUTH_CONNECT_FAILED',
            'code': e.code,
            'message': e.message,
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      }
    });

    _router.get('/api/v1/backup/oauth/status', (Request req) async {
      final denied = _verifyOwnerOrLoopbackAdmin(
        req,
        actionName: 'Hub Google Drive OAuth durumu',
      );
      if (denied != null) return denied;

      try {
        final status = await hubBackupOAuthService.getStatus();
        return Response.ok(
          jsonEncode(status.toJson()),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      } on HubBackupOAuthException catch (e) {
        return Response(
          500,
          body: jsonEncode({
            'error': 'OAUTH_STORE_ERROR',
            'code': e.code,
            'message': e.message,
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      }
    });

    _router.post('/api/v1/backup/oauth/disconnect', (Request req) async {
      final denied = _verifyOwnerOrLoopbackAdmin(
        req,
        actionName: 'Hub Google Drive OAuth bağlantısını kesme',
      );
      if (denied != null) return denied;
      final replayDenied = await _verifyReplayProtection(
        req,
        actionName: 'Hub Google Drive OAuth bağlantısını kesme',
      );
      if (replayDenied != null) return replayDenied;

      await hubBackupOAuthService.disconnect();
      final actorId =
          (req.context['authenticated_device_id'] as String?) ?? 'HUB_ADMIN';
      await writeQueue.enqueue(() async {
        await db.into(db.deviceAuditLogs).insert(
              DeviceAuditLogsCompanion(
                deviceId: Value(actorId),
                action: const Value('BACKUP_OAUTH_DISCONNECT'),
                details: const Value('Hub backup Drive OAuth disconnected'),
              ),
            );
      });
      return Response.ok(
        jsonEncode(HubBackupOAuthStatus.disconnected.toJson()),
        headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
      );
    });

    // 6.6. Faz B-3: Hub Merkezi Yedekleme 12-Durum Orkestrasyon Uçları
    _router.get('/api/v1/backup/status', (Request req) async {
      final denied = _verifyOwnerOrLoopbackAdmin(
        req,
        actionName: 'Hub merkezi yedekleme durumu',
      );
      if (denied != null) return denied;

      final oauthStatus = await hubBackupOAuthService.getStatus();
      final hasRecoveryKey = await hubRecoveryKeyStore.hasRecoveryPassword();
      final jobsSnap = await hubBackupOrchestrator.getStatusSnapshot();

      return Response.ok(
        jsonEncode({
          'oauth': oauthStatus.toJson(),
          'has_recovery_key': hasRecoveryKey,
          'schedule': jobsSnap.schedule.toJson(),
          'last_completed_date_local': jobsSnap.lastCompletedDateLocal,
          'last_completed_at_utc': jobsSnap.lastCompletedAtUtc?.toUtc().toIso8601String(),
          'latest_job': jobsSnap.latestJob?.toJson(),
          'jobs': jobsSnap.jobs.take(20).map((j) => j.toJson()).toList(),
          // S1: Son başarısız zamanlayıcı turu (yoksa null). Parola/token içermez.
          'scheduler_last_error': hubBackupOrchestrator.lastSchedulerError?.toJson(),
        }),
        headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
      );
    });

    _router.get('/api/v1/backup/list', (Request req) async {
      final denied = _verifyOwnerOrLoopbackAdmin(
        req,
        actionName: 'Hub merkezi yedek listesi',
      );
      if (denied != null) return denied;

      final jobsSnap = await hubBackupOrchestrator.getStatusSnapshot();
      return Response.ok(
        jsonEncode({
          'jobs': jobsSnap.jobs.map((j) => j.toJson()).toList(),
        }),
        headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
      );
    });

    // AUD-CRIT-03: Google Drive `MARKET MMS Yedekleri/Hub` merkezi yedeklerini listeler
    _router.get('/api/v1/backup/drive/list', (Request req) async {
      final denied = _verifyOwnerOrLoopbackAdmin(
        req,
        actionName: 'Google Drive merkezi Hub yedek listesi',
      );
      if (denied != null) return denied;

      try {
        final backups = await hubBackupOrchestrator.listDriveBackups();
        return Response.ok(
          jsonEncode({
            'backups': backups.map((b) => b.toJson()).toList(),
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      } on DriveResumableUploadException catch (e) {
        final status = e.kind == DriveUploadFailureKind.authFailure ? 401 : 502;
        return Response(
          status,
          body: jsonEncode({'error': e.code, 'code': e.code, 'message': e.message}),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      } on HubBackupOAuthException catch (e) {
        final status = e.code == 'FAILED_AUTH' ? 401 : 502;
        return Response(
          status,
          body: jsonEncode({'error': e.code, 'code': e.code, 'message': e.message}),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      }
    });

    _router.post('/api/v1/backup/recovery-key', (Request req) async {
      final denied = _verifyOwnerOrLoopbackAdmin(
        req,
        actionName: 'Hub katılımsız kurtarma anahtarı tanımlama',
      );
      if (denied != null) return denied;
      final replayDenied = await _verifyReplayProtection(
        req,
        actionName: 'Hub katılımsız kurtarma anahtarı tanımlama',
      );
      if (replayDenied != null) return replayDenied;

      final body = await _decodeJsonBodyOrEmpty(req);
      final password = (body['recovery_password'] as String?) ?? '';
      try {
        await hubRecoveryKeyStore.saveRecoveryPassword(password);
        hubBackupOrchestrator.clearTickErrorIfCodes(const {
          'ERR_RECOVERY_KEY_NOT_CONFIGURED',
          'ERR_RECOVERY_KEY_REQUIRED',
          'ERR_RECOVERY_KEY_CORRUPTED',
        });
        final actorId =
            (req.context['authenticated_device_id'] as String?) ?? 'HUB_ADMIN';
        await writeQueue.enqueue(() async {
          await db.into(db.deviceAuditLogs).insert(
                DeviceAuditLogsCompanion(
                  deviceId: Value(actorId),
                  action: const Value('BACKUP_RECOVERY_KEY_SET'),
                  details: const Value('Unattended Hub backup recovery key stored in DPAPI'),
                ),
              );
        });
        return Response.ok(
          jsonEncode({'has_recovery_key': true}),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      } on HubRecoveryKeyException catch (e) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'INVALID_RECOVERY_KEY',
            'code': e.code,
            'message': e.message,
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      }
    });

    _router.post('/api/v1/backup/schedule', (Request req) async {
      final denied = _verifyOwnerOrLoopbackAdmin(
        req,
        actionName: 'Hub merkezi yedekleme zamanlaması',
      );
      if (denied != null) return denied;
      final replayDenied = await _verifyReplayProtection(
        req,
        actionName: 'Hub merkezi yedekleme zamanlaması',
      );
      if (replayDenied != null) return replayDenied;

      final body = await _decodeJsonBodyOrEmpty(req);
      final enabled = (body['enabled'] as bool?) ?? false;
      final dailyHour = (body['daily_hour_local'] as num?)?.toInt() ?? 0;
      final dailyMinute = (body['daily_minute_local'] as num?)?.toInt() ?? 0;
      final uploadToDrive = (body['upload_to_drive'] as bool?) ?? true;
      final recoveryPassword = body['recovery_password'] as String?;
      final triggerInitial = (body['trigger_initial_if_due'] as bool?) ?? true;

      try {
        final next = await hubBackupOrchestrator.configureSchedule(
          enabled: enabled,
          dailyHourLocal: dailyHour,
          dailyMinuteLocal: dailyMinute,
          uploadToDrive: uploadToDrive,
          unattendedRecoveryPassword: recoveryPassword,
          triggerInitialIfDue: triggerInitial,
        );
        return Response.ok(
          jsonEncode({
            'schedule': next.schedule.toJson(),
            'latest_job': next.latestJob?.toJson(),
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      } on HubRecoveryKeyException catch (e) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'INVALID_SCHEDULE_CONFIG',
            'code': e.code,
            'message': e.message,
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      } on ArgumentError catch (e) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'INVALID_SCHEDULE_CONFIG',
            'code': 'ERR_INVALID_SCHEDULE',
            'message': e.message?.toString() ?? 'Geçersiz zamanlama parametresi.',
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      }
    });

    _router.post('/api/v1/backup/run', (Request req) async {
      final denied = _verifyOwnerOrLoopbackAdmin(
        req,
        actionName: 'Hub merkezi yedekleme başlatma',
      );
      if (denied != null) return denied;
      final replayDenied = await _verifyReplayProtection(
        req,
        actionName: 'Hub merkezi yedekleme başlatma',
      );
      if (replayDenied != null) return replayDenied;

      final body = await _decodeJsonBodyOrEmpty(req);
      // S2: Manuel yedek YALNIZCA Hub'da kayıtlı Portable Recovery Password ile
      // şifrelenir. İstekle parola gönderilmesi (yerel veya uzak OWNER) reddedilir;
      // böylece kullanıcının hatırlayamayacağı kaydedilmemiş bir parolayla Drive
      // yedeği oluşturulamaz. Parola önce POST /api/v1/backup/recovery-key ile kaydedilir.
      if (body.containsKey('recovery_password')) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'INVALID_REQUEST',
            'code': 'ERR_RECOVERY_PASSWORD_NOT_ACCEPTED',
            'message': 'Manuel yedek istekte gönderilen parolayı kullanmaz. Önce kurtarma '
                'parolasını kaydedin (POST /api/v1/backup/recovery-key); yedek kayıtlı '
                'parolayla şifrelenir.',
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      }

      try {
        final job = await hubBackupOrchestrator.triggerBackup(
          trigger: HubBackupTrigger.manual,
        );
        return Response.ok(
          jsonEncode({
            ...job.toJson(),
            // S2: Paketin hangi parolayla şifrelendiği açıkça belirtilir.
            'recovery_key_source': 'HUB_STORED_DPAPI',
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      } on BackupException catch (e) {
        final code = e.code == BackupOperationLock.busyErrorCode ? 409 : 400;
        return Response(
          code,
          body: jsonEncode({'error': e.code, 'code': e.code, 'message': e.message}),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      } on BackupCryptoException catch (e) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'INVALID_RECOVERY_PASSWORD',
            'code': 'ERR_WEAK_RECOVERY_PASSWORD',
            'message': e.message,
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      } on HubRecoveryKeyException catch (e) {
        return Response(
          400,
          body: jsonEncode({'error': e.code, 'code': e.code, 'message': e.message}),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      }
    });

    // 6.7. Faz B-4 & AUD-CRIT-03: Taşınabilir MMSBAK02/01 Paketinden (Yerel veya Google Drive)
    // Hub Geri Yükleme + restore_epoch + Token Geçersizleştirme
    _router.post('/api/v1/backup/restore', (Request req) async {
      final denied = _verifyOwnerOrLoopbackAdmin(
        req,
        actionName: 'Hub merkezi yedekten geri yükleme',
      );
      if (denied != null) return denied;
      final replayDenied = await _verifyReplayProtection(
        req,
        actionName: 'Hub merkezi yedekten geri yükleme',
      );
      if (replayDenied != null) return replayDenied;

      final body = await _decodeJsonBodyOrEmpty(req);
      final backupId = (body['backup_id'] as String?)?.trim() ?? '';
      final driveFileId = (body['drive_file_id'] as String?)?.trim() ?? '';
      final packagePath = (body['package_path'] as String?)?.trim() ?? '';
      final recoveryPassword = (body['recovery_password'] as String?) ?? '';

      if (recoveryPassword.isEmpty) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'INVALID_REQUEST',
            'code': 'ERR_RECOVERY_PASSWORD_REQUIRED',
            'message': 'Kurtarma parolası zorunludur.',
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      }

      // GÜVENLİK: Keyfi dosya yolu yalnızca Hub bilgisayarındaki loopback + admin
      // secret çağrısında (Windows UI, USB içe aktarma) kabul edilir. Uzak OWNER cihazı
      // yalnızca Hub yedek dizinindeki/Drive'daki `backup_id` veya `drive_file_id` seçebilir.
      // UNC / ağ yolları (`\\sunucu\paylaşım`) her durumda reddedilir.
      final isRemoteDevice = req.context['authenticated_device_id'] != null;
      if (packagePath.isNotEmpty) {
        final pathDenied = _validateRestorePackagePath(
          packagePath,
          isRemoteDevice: isRemoteDevice,
        );
        if (pathDenied != null) return pathDenied;
      }
      if (packagePath.isEmpty && backupId.isNotEmpty && !_safeBackupIdPattern.hasMatch(backupId)) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'INVALID_REQUEST',
            'code': 'ERR_INVALID_BACKUP_ID',
            'message': 'Geçersiz yedek kimliği.',
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      }
      if (driveFileId.isNotEmpty &&
          !ResumableDriveUploader.isValidDriveFileId(driveFileId)) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'INVALID_REQUEST',
            'code': 'ERR_INVALID_DRIVE_FILE_ID',
            'message': 'Geçersiz Google Drive dosya kimliği.',
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      }
      if (packagePath.isEmpty && backupId.isEmpty && driveFileId.isEmpty) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'INVALID_REQUEST',
            'code': 'ERR_BACKUP_SELECTOR_REQUIRED',
            'message': 'Geri yükleme için backup_id, drive_file_id veya package_path gereklidir.',
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      }

      final targetLiveDb =
          dbFile ?? File(p.join(Directory.current.path, 'market_master.db'));
      // `kdf_iterations` istek gövdesinden ALINMAZ (uzak çağıran safety snapshot
      // şifrelemesini zayıflatamaz); yalnızca sunucu yapılandırması kullanılır.
      final kdfIters = hubRestoreSafetyKdfIterations;
      Directory? tempDriveDownloadDir;
      try {
        final result = await _backupOperationLock.synchronized(
          BackupOperationKind.restore,
          () async {
            File? packageFile;
            if (packagePath.isNotEmpty) {
              final f = File(packagePath);
              if (await f.exists() && f.path.toLowerCase().endsWith('.mmsbak')) {
                packageFile = f;
              }
            } else {
              if (backupId.isNotEmpty) {
                final candidate = File(
                  p.join(_backupTargetDir.path, 'hub_backup_$backupId.mmsbak'),
                );
                if (await candidate.exists()) {
                  packageFile = candidate;
                } else {
                  try {
                    final legacyFile = await LocalStorageProvider(_backupTargetDir)
                        .getBackupFile(backupId);
                    if (await legacyFile.exists()) {
                      packageFile = legacyFile;
                    }
                  } catch (e) {
                    stderr.writeln(
                      '[WARN] Legacy yedek dosyası arama atlandı (backupId=$backupId): ${e.runtimeType}',
                    );
                  }
                }
              }

              // Yerel önbellekte yoksa (7+ gün temizliği veya yeni PC felaket kurtarma):
              // Google Drive'dan akışlı indir, boyut + SHA-256 + MMSBAK yapısı doğrula.
              if ((packageFile == null || !(await packageFile.exists())) &&
                  (driveFileId.isNotEmpty || backupId.isNotEmpty)) {
                tempDriveDownloadDir = await Directory.systemTemp.createTemp(
                  'mms_hub_drive_dl_',
                );
                final downloaded =
                    await hubBackupOrchestrator.downloadBackupFromDrive(
                  backupId: backupId.isEmpty ? null : backupId,
                  driveFileId: driveFileId.isEmpty ? null : driveFileId,
                  targetDir: tempDriveDownloadDir!,
                );
                packageFile = downloaded.file;
              }
            }

            if (packageFile == null || !(await packageFile.exists())) {
              throw const BackupException(
                'ERR_BACKUP_NOT_FOUND',
                'Geri yüklenecek yedek paketi bulunamadı.',
              );
            }

            return HubRestoreService.restoreFromEncryptedPackage(
              packageFile: packageFile,
              recoveryPassword: recoveryPassword,
              liveDbFile: targetLiveDb,
              backupDir: _backupTargetDir,
              lock: _backupOperationLock,
              acquireLock: false,
              expectedTenantId: tenantId,
              expectedStoreId: storeId,
              expectedHubId: hubId,
              maxSupportedSchemaVersion: max(4, db.schemaVersion),
              kdfIterations: kdfIters,
              pauseAndCloseLiveDb: () async {
                await lifecycle.admissionGate.pauseForMaintenance(allowedRemaining: 1);
                await writeQueue.pauseForMaintenance();
                try {
                  await db.checkpointWal(mode: 'TRUNCATE');
                } catch (e) {
                  stderr.writeln(
                    '[WARN] Admin restore öncesi WAL checkpoint uyarısı: ${e.runtimeType}',
                  );
                }
                await db.close();
              },
              reopenLiveDb: (File dbPath) async {
                final reopened = SpikeDatabase(dbPath);
                this.db = reopened;
                lifecycle.db = reopened;
                return reopened;
              },
              onDbReopened: (_, __) async {
                writeQueue.resumeAfterMaintenance();
                lifecycle.admissionGate.resumeAfterMaintenance();
                await _verifyOrInitializeHubIdentity();
              },
            );
          },
        );

        return Response.ok(
          jsonEncode(result.toJson(maskPaths: isRemoteDevice)),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      } on DriveResumableUploadException catch (e) {
        writeQueue.resumeAfterMaintenance();
        lifecycle.admissionGate.resumeAfterMaintenance();
        final int status;
        if (e.code == 'ERR_BACKUP_NOT_FOUND' || e.statusCode == 404) {
          status = 404;
        } else if (e.kind == DriveUploadFailureKind.authFailure) {
          status = 401;
        } else if (e.kind == DriveUploadFailureKind.integrityVerificationFailed ||
            e.kind == DriveUploadFailureKind.invalidInput) {
          status = 400;
        } else {
          status = 502;
        }
        return Response(
          status,
          body: jsonEncode({'error': e.code, 'code': e.code, 'message': e.message}),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      } on HubBackupOAuthException catch (e) {
        writeQueue.resumeAfterMaintenance();
        lifecycle.admissionGate.resumeAfterMaintenance();
        final status = e.code == 'FAILED_AUTH' ? 401 : 502;
        return Response(
          status,
          body: jsonEncode({'error': e.code, 'code': e.code, 'message': e.message}),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      } on BackupCryptoException catch (e) {
        writeQueue.resumeAfterMaintenance();
        lifecycle.admissionGate.resumeAfterMaintenance();
        return Response(
          400,
          body: jsonEncode({
            'error': 'RESTORE_DECRYPT_FAILED',
            'code': 'ERR_RESTORE_DECRYPT_FAILED',
            'message': e.message,
          }),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      } on BackupException catch (e) {
        writeQueue.resumeAfterMaintenance();
        lifecycle.admissionGate.resumeAfterMaintenance();
        final status = e.code == BackupOperationLock.busyErrorCode
            ? 409
            : (e.code == 'ERR_BACKUP_NOT_FOUND' ? 404 : 400);
        return Response(
          status,
          body: jsonEncode({'error': e.code, 'code': e.code, 'message': e.message}),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      } catch (e) {
        writeQueue.resumeAfterMaintenance();
        lifecycle.admissionGate.resumeAfterMaintenance();
        return Response.internalServerError(
          body: jsonEncode({'error': 'RESTORE_FAILED', 'message': e.toString()}),
          headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
        );
      } finally {
        if (tempDriveDownloadDir != null && await tempDriveDownloadDir!.exists()) {
          try {
            await tempDriveDownloadDir!.delete(recursive: true);
          } catch (e) {
            stderr.writeln(
              '[WARN] Geçici Drive indirme dizini silinemedi (${p.basename(tempDriveDownloadDir!.path)}): ${e.runtimeType}',
            );
          }
        }
      }
    });

    // 7. Kuyruk Metrikleri
    _router.get('/api/v1/metrics', (Request req) async {
      return Response.ok(
        jsonEncode({
          'queue_metrics': writeQueue.metrics.toJson(),
          'timestamp': DateTime.now().toIso8601String(),
        }),
        headers: {'content-type': 'application/json'},
      );
    });


    // 8. Kontrollü Kapanma Uç Noktası (Graceful Shutdown - Loopback ve Ayrı Admin Secret Korumalı)
    _router.post('/api/v1/admin/shutdown', (Request req) async {
      // A. Loopback Kontrolü (IPv4 ve IPv6)
      final connectionInfo = req.context['shelf.io.connection_info'] as HttpConnectionInfo?;
      if (connectionInfo != null) {
        final remoteAddr = connectionInfo.remoteAddress;
        final isLoopback = remoteAddr.isLoopback ||
            remoteAddr.address == '127.0.0.1' ||
            remoteAddr.address == '::1' ||
            remoteAddr.address == '0:0:0:0:0:0:0:1' ||
            remoteAddr.address == '::ffff:127.0.0.1';

        if (!isLoopback) {
          return Response.forbidden(
            jsonEncode({
              'error': 'FORBIDDEN',
              'code': 'ERR_LOOPBACK_REQUIRED',
              'message': 'Shutdown uç noktasına yalnızca yerel makineden (loopback) erişilebilir.',
            }),
            headers: {'content-type': 'application/json'},
          );
        }
      }

      // B. Güvenli Admin Secret Yapılandırma Kontrolü
      final effectiveAdminSecret = _effectiveAdminSecret;
      if (effectiveAdminSecret == null || effectiveAdminSecret.isEmpty) {
        return Response(
          503,
          body: jsonEncode({
            'error': 'SHUTDOWN_DISABLED',
            'code': 'ERR_SHUTDOWN_NOT_CONFIGURED',
            'message': 'Admin shutdown özelliği yapılandırılmamış ve güvenlik nedeniyle devre dışıdır.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // C. Admin Secret Yetkilendirmesi (Normal cihaz token'ları yetkisizdir)
      final providedAdminSecret = req.headers['x-admin-secret'] ??
          (req.headers['authorization']?.startsWith('Bearer ') == true
              ? req.headers['authorization']!.substring(7).trim()
              : null);

      if (providedAdminSecret == null || providedAdminSecret.isEmpty) {
        return Response(
          401,
          body: jsonEncode({
            'error': 'UNAUTHORIZED',
            'code': 'ERR_ADMIN_SECRET_REQUIRED',
            'message': 'Shutdown işlemi için admin secret gereklidir.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Sabit zamanlı karşılaştırma ile sırrın doğrulanması
      if (!_constantTimeEquals(utf8.encode(providedAdminSecret), utf8.encode(effectiveAdminSecret))) {
        return Response.forbidden(
          jsonEncode({
            'error': 'FORBIDDEN',
            'code': 'ERR_INVALID_ADMIN_SECRET',
            'message': 'Geçersiz admin secret. Normal cihaz tokenları ile shutdown yapılamaz.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Yanıtın sokete yazılması için 50 ms sonra shutdown tetikle
      Timer(const Duration(milliseconds: 50), () => lifecycle.shutdown(reason: 'Admin HTTP shutdown'));
      return Response.ok(
        jsonEncode({
          'status': 'SHUTTING_DOWN',
          'timestamp': DateTime.now().toIso8601String(),
        }),
        headers: {'content-type': 'application/json'},
      );
    });

  }

  Handler get handler {
    final pipeline = Pipeline()
        .addMiddleware(createAdmissionMiddleware(lifecycle.admissionGate))
        .addMiddleware(createSecureCorsMiddleware())
        .addMiddleware(createBodyLimitMiddleware(maxBytes: 2 * 1024 * 1024))
        .addMiddleware(createAuthMiddleware(
          dbProvider: () => db,
          isDraining: () => writeQueue.isDraining || !lifecycle.admissionGate.isOpen,
          pepperManager: pepperManager,
          writeQueue: writeQueue,
          requireTls: requireTls,
          expectedTenantId: tenantId,
          expectedStoreId: storeId,
          requireTenantStoreHeaders: requireTenantStoreHeaders,
          publicPaths: [
            '/health',
            '/api/v1/backup/snapshot', // SEC-SNAP: cihaz token'ı yerine loopback + admin secret
            '/api/v1/admin/shutdown',
            '/api/v1/admin/backup',
            '/api/v1/admin/backups',
            '/api/v1/admin/restore',
            '/api/v1/admin/backup/prune',
            '/api/v1/admin/backup/status',
            '/api/v1/admin/live-drive-secret/rotate',
            '/api/v1/admin/owner/bootstrap',
            '/api/v1/devices/revoke',
            '/api/v1/pairing/session',
            '/api/v1/pairing/requests',
            '/api/v1/pairing/approve',
            '/api/v1/pairing/reject',
            '/api/v1/pairing/ca-cert',
            '/api/v1/pairing/request',
            '/api/v1/pairing/poll-challenge',
            '/api/v1/pairing/poll',
            '/api/v1/pairing/ack-challenge',
            '/api/v1/pairing/ack',
          ],
          bearerOrAdminPaths: const [
            '/api/v1/devices/role',
            '/api/v1/backup/oauth/connect',
            '/api/v1/backup/oauth/disconnect',
            '/api/v1/backup/oauth/status',
            '/api/v1/backup/status',
            '/api/v1/backup/list',
            '/api/v1/backup/drive/list',
            '/api/v1/backup/recovery-key',
            '/api/v1/backup/schedule',
            '/api/v1/backup/run',
            '/api/v1/backup/restore',
          ],
        ))
        .addHandler(_router.call);
    return pipeline;
  }

  Future<void> start({
    InternetAddress? address,
    int port = 8080,
    Duration cleanupInterval = const Duration(seconds: 15),
    bool enableDiscovery = true,
    int discoveryPort = HubDiscoveryResponder.defaultDiscoveryPort,
  }) async {
    // P-BLOCK-2 / DEC-REV-3: TLS aktifken Loopback (`IP:127.0.0.1`) SAN zorunluluğu (Startup Fail-Fast Exit 78)
    // vs LAN SAN / advertise_host uyuşmazlığı (Hub açık kalır, tanı uyarısı loglanır).
    Set<String>? certSanIps;
    if (requireTls && serverCertPath != null) {
      final certFile = File(serverCertPath!);
      if (!certFile.existsSync()) {
        throw HubStartupArgException(
          78,
          'ERR_SERVER_CERT_NOT_FOUND: TLS sertifikası bulunamadı (${p.basename(serverCertPath!)}).',
        );
      }
      final Set<String> sanIps;
      try {
        sanIps = CertificateManager.extractServerCertSanIpv4s(certFile.readAsBytesSync());
      } on X509ValidationException catch (e) {
        throw HubStartupArgException(78, 'ERR_SERVER_CERT_INVALID (${e.code}): ${e.message}');
      }
      if (!sanIps.contains('127.0.0.1')) {
        throw const HubStartupArgException(
          78,
          'ERR_SERVER_CERT_MISSING_LOOPBACK_SAN: Windows yerel istemci ve yönetim paneli için server.crt SAN listesi IP:127.0.0.1 içermelidir.',
        );
      }
      if (advertiseHost != null && !sanIps.contains(advertiseHost)) {
        stderr.writeln(
          '[WARN] ERR_ADVERTISE_HOST_SAN_MISMATCH: advertise_host ($advertiseHost) server.crt SAN listesinde yok. '
          'Hub yerel POS için açık kalacak ancak /api/v1/pairing/session 503 dönecektir.',
        );
      }
      certSanIps = sanIps;
    }

    _resourcesStopped = false;
    // BK-02.1: Pilot tek-tenant / tek-store kimlik doğrulaması ve başlangıç mührü
    await _verifyOrInitializeHubIdentity();

    // S-4: Startup reconcile - sunucu açılışında onaylanmamış yarım kalan cihazları temizle
    await PairingDeliveryBuffer.startupReconcile(db: db, writeQueue: writeQueue);

    final host = address ?? InternetAddress.anyIPv4;
    _httpServer = await shelf_io.serve(
      handler,
      host,
      port,
      securityContext: securityContext,
    );
    lifecycle.attachServer(_httpServer!);

    // Faz 1.1: UDP Discovery dinleyicisini başlat
    if (enableDiscovery) {
      try {
        final effectiveResolver = lanAddressResolver ??
            (Platform.isWindows
                ? HubLanAddressResolver(inspector: WindowsNetworkAdapterInspector())
                : null);
        _discoveryResponder = HubDiscoveryResponder(
          httpPort: port,
          discoveryPort: discoveryPort,
          hubId: hubId,
          bindAddress: address,
          tlsEnabled: requireTls || securityContext != null,
          advertiseHost: advertiseHost,
          serverCertSanIpv4s: certSanIps,
          lanIpsProvider: effectiveResolver != null
              ? () => effectiveResolver.resolveDiscoveryLanIps(
                    advertiseHost: advertiseHost,
                    serverCertSanIpv4s: certSanIps,
                  )
              : null,
        );
        await _discoveryResponder!.start();
      } catch (e) {
        print('[WARN] UDP Discovery başlatılamadı: ${redactLogText(e.toString())}');
      }
    }

    // S1: Önce merkezi Drive yedekleme açılış kurtarması ve dakikalık zamanlayıcı başlatılır;
    // ardından eski 24 saatlik yerel zamanlayıcı başlar (açılış kilidi yarışı önlenir).
    await hubBackupOrchestrator.runGuardedTick(startup: true);
    hubBackupOrchestrator.start();
    // Faz 3: Zamanlanmış şifreli Hub yedeği (yedek hatası servisi durdurmaz)
    await _startBackupScheduler();

    // FINDING-2: Periyodik teslimat zaman aşımı temizleyicisi (15-30 sn)
    _pairingCleanupTimer?.cancel();
    _pairingCleanupTimer = Timer.periodic(cleanupInterval, (_) async {
      try {
        if (!writeQueue.isDraining) {
          await pairingManager.deliveryBuffer.cleanUpExpired(
            db: db,
            writeQueue: writeQueue,
          );
        }
      } catch (e) {
        print(
          '[WARN] Pairing delivery cleanup error: ${redactLogText(e.toString())}',
        );
      }
    });
  }

  static String _redactFilesystemPath(String rawPath) {
    final normalized = rawPath.trim();
    if (normalized.isEmpty) return '[REDACTED_PATH]';
    final sepIndex = normalized.lastIndexOf(RegExp(r'[/\\]'));
    if (sepIndex < 0 || sepIndex == normalized.length - 1) {
      return '[REDACTED_PATH]';
    }
    final basename = normalized.substring(sepIndex + 1);
    return basename.isEmpty ? '[REDACTED_PATH]' : '[REDACTED_PATH]/$basename';
  }

  /// Loglarda tam yerel dosya yolu, OAuth token, URL gizlileri ve admin sırlarını maskeler.
  static String redactLogText(String raw) {
    var text = raw;
    text = text.replaceAll(
      RegExp(
        r'-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----',
      ),
      '[REDACTED_PRIVATE_KEY]',
    );
    text = text.replaceAllMapped(
      RegExp(
        r'("(?:auth_code|code|pairing_secret|device_token|access_token|accessToken|refresh_token|refreshToken|token|password|backupPassword|backup_password|recovery_password|recoveryPassword|privateKey|private_key|client_secret|clientSecret|admin_secret|adminSecret|live_sync_secret|dpapi_secret|signing_key|code_verifier|x-mms-admin-secret|x-admin-secret|api_key|upload_id|session|signature|sig|secret|pepper)"\s*:\s*)"[^"]*"',
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}"[REDACTED]"',
    );
    text = text.replaceAll(
      RegExp(r'Bearer\s+[A-Za-z0-9_\-\.]+', caseSensitive: false),
      'Bearer [REDACTED]',
    );
    text = text.replaceAll(
      RegExp(r'mms_dt_[A-Za-z0-9_\-]+'),
      'mms_dt_[REDACTED]',
    );
    text = text.replaceAll(
      RegExp(r'\bya29\.[A-Za-z0-9_\-\.]+'),
      'ya29.[REDACTED]',
    );
    text = text.replaceAll(
      RegExp(r'\b1//[A-Za-z0-9_\-\.]+'),
      '1//[REDACTED]',
    );
    text = text.replaceAll(
      RegExp(r'\bGOCSPX-[A-Za-z0-9_\-]+'),
      'GOCSPX-[REDACTED]',
    );
    text = text.replaceAllMapped(
      RegExp(
        r"""([?&])(code|auth_code|access_token|refresh_token|device_token|token|client_secret|admin_secret|live_sync_secret|dpapi_secret|signing_key|recovery_password|pairing_secret|private_key|code_verifier|api_key|key|upload_id|session|signature|sig|pepper|password|secret)=([^&#\s"'`\)\]]*)""",
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}${m.group(2)}=[REDACTED]',
    );
    text = text.replaceAllMapped(
      RegExp(
        r"""\b(access_token|refresh_token|device_token|token|client_secret|admin_secret|live_sync_secret|dpapi_secret|signing_key|recovery_password|pairing_secret|private_key|code_verifier|x-mms-admin-secret|x-admin-secret|api_key|auth_code|upload_id|pepper|secret|password)\s*([:=])\s*(?!\[REDACTED\])([^\s,&;"'`\)\]]+)""",
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}${m.group(2)} [REDACTED]',
    );
    text = text.replaceAllMapped(
      RegExp(
        r"""file:///(?:[A-Za-z]:[\\/][^\s"'`\)\]\r\n]+|(?:data|Users|home|var|private|tmp|opt|etc|root|storage|mnt|sdcard|Library|Volumes|proc)/[^\s"'`\)\]\r\n]+)""",
      ),
      (m) => 'file:///${_redactFilesystemPath(m.group(0)!.substring(8))}',
    );
    text = text.replaceAllMapped(
      RegExp(
        r'"((?:(?<![A-Za-z0-9_])[A-Za-z]:[\\/]|\\\\|/(?:data|Users|home|var|private|tmp|opt|etc|root|storage|mnt|sdcard|Library|Volumes|proc)/)[^"\r\n]+)"',
      ),
      (m) => '"${_redactFilesystemPath(m.group(1)!)}"',
    );
    text = text.replaceAllMapped(
      RegExp(
        r"'((?:(?<![A-Za-z0-9_])[A-Za-z]:[\\/]|\\\\|/(?:data|Users|home|var|private|tmp|opt|etc|root|storage|mnt|sdcard|Library|Volumes|proc)/)[^'\r\n]+)'",
      ),
      (m) => "'${_redactFilesystemPath(m.group(1)!)}'",
    );
    text = text.replaceAllMapped(
      RegExp(r"""(?<![A-Za-z0-9_])(?:[A-Za-z]:[\\/]|\\\\)[^\s"'`\)\]\r\n,;]+"""),
      (m) => _redactFilesystemPath(m.group(0)!),
    );
    text = text.replaceAllMapped(
      RegExp(
        r"""(?<![A-Za-z0-9:/\.\[])/(?:data|Users|home|var|private|tmp|opt|etc|root|storage|mnt|sdcard|Library|Volumes|proc)/[^\s"'`\)\]\r\n,;]+""",
      ),
      (m) => _redactFilesystemPath(m.group(0)!),
    );
    return text;
  }

  Future<void> stop() async {
    await lifecycle.shutdown(reason: 'SpikeServer.stop', exitProcess: false);
  }
}

class HubStartupArgException implements Exception {
  final int exitCode;
  final String message;

  const HubStartupArgException(this.exitCode, this.message);

  @override
  String toString() => 'HubStartupArgException($exitCode): $message';
}

class ResolvedHubStartupConfig {
  final String? environmentName;
  final int port;
  final int discoveryPort;
  final bool enableDiscovery;
  final String dbPath;
  final String? backupDir;
  final String? adminSecret;
  final String? pepperPath;
  final String? certPath;
  final String? keyPath;
  final String? caCertPath;
  final String? advertiseHost;
  final bool enableTls;
  final String tenantId;
  final String storeId;
  final String hubId;
  final bool requireTenantStoreHeaders;
  final BackupSchedulePolicy backupSchedule;
  final bool loadedFromConfigFile;

  const ResolvedHubStartupConfig({
    this.environmentName,
    required this.port,
    required this.discoveryPort,
    required this.enableDiscovery,
    required this.dbPath,
    this.backupDir,
    this.adminSecret,
    this.pepperPath,
    this.certPath,
    this.keyPath,
    this.caCertPath,
    this.advertiseHost,
    required this.enableTls,
    required this.tenantId,
    required this.storeId,
    required this.hubId,
    required this.requireTenantStoreHeaders,
    required this.backupSchedule,
    required this.loadedFromConfigFile,
  });
}

/// REL-01: Başlangıç argümanlarını ve (yalnızca `--config=` verilmemişse) ortam
/// değişkenlerini çözümler. `--config=` verildiğinde `hub_config.json` TEK kaynak
/// olarak kullanılır; hiçbir ortam değişkeni (ör. `ROOT_CA_CERT_FILE`) sızmaz.
ResolvedHubStartupConfig resolveHubStartupConfig(
  List<String> args, {
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;

  // REL-01: --config verilirse TEK yapılandırma kaynağıdır. Ortam değişkenleri ve
  // diğer yapılandırma bayrakları birlikte kullanılamaz (çelişen değer riski).
  final configArg = args.where((a) => a.startsWith('--config=')).toList();
  if (configArg.isNotEmpty) {
    final otherFlags = args.where((a) => !a.startsWith('--config=')).toList();
    if (configArg.length > 1 || otherFlags.isNotEmpty) {
      throw HubStartupArgException(
        64,
        '[REL-01] --config yalnızca tek başına kullanılabilir; ek bayraklar: ${otherFlags.join(' ')}',
      );
    }
    final HubConfig cfg;
    try {
      cfg = HubConfig.load(
        File(configArg.single.substring('--config='.length).replaceAll('"', '')),
      );
    } on HubConfigException catch (e) {
      throw HubStartupArgException(
        78,
        '[REL-01] Hub yapılandırması geçersiz: ${e.message}',
      );
    }
    return ResolvedHubStartupConfig(
      environmentName: cfg.environment,
      port: cfg.port,
      discoveryPort: cfg.discoveryPort,
      enableDiscovery: cfg.enableDiscovery,
      dbPath: cfg.dbPath,
      backupDir: cfg.backupDir,
      adminSecret: cfg.readAdminSecret(),
      pepperPath: cfg.pepperPath,
      certPath: cfg.certPath,
      keyPath: cfg.keyPath,
      caCertPath: cfg.caCertPath,
      advertiseHost: cfg.advertiseHost,
      enableTls: cfg.enableTls,
      tenantId: cfg.tenantId,
      storeId: cfg.storeId,
      hubId: cfg.hubId,
      requireTenantStoreHeaders: cfg.requireTenantStoreHeaders,
      backupSchedule: cfg.backupSchedule,
      loadedFromConfigFile: true,
    );
  }

  int port = int.tryParse(env['PORT'] ?? '8080') ?? 8080;
  int discoveryPort = int.tryParse(env['DISCOVERY_PORT'] ?? '8946') ?? 8946;
  bool enableDiscovery = env['ENABLE_DISCOVERY'] != 'false';
  String dbPath = env['DB_PATH'] ?? 'spike_master.db';
  String? backupDir = env['BACKUP_DIR'];
  String? adminSecret = env['ADMIN_SECRET'];
  String? pepperPath = env['PEPPER_FILE'];
  String? certPath = env['TLS_CERT'];
  String? keyPath = env['TLS_KEY'];
  // Geliştirme / bayraklı mod için geriye dönük kök CA ortam değişkeni desteği.
  String? caCertPath = env['ROOT_CA_CERT_FILE'];
  String? advertiseHost = env['ADVERTISE_HOST'];
  bool enableTls = env['ENABLE_TLS'] == 'true';
  String tenantId = env['HUB_TENANT_ID'] ?? SpikeServer.defaultTenantId;
  String storeId = env['HUB_STORE_ID'] ?? SpikeServer.defaultStoreId;
  String hubId = env['HUB_ID'] ?? SpikeServer.defaultHubId;
  bool requireTenantStoreHeaders = env['REQUIRE_TENANT_STORE_HEADERS'] != 'false';
  // Faz 3: Geliştirme (bayraklı) modunda zamanlanmış yedek varsayılan kapalı; üretimde
  // (--config) varsayılan 24 saat. BACKUP_INTERVAL_HOURS / --backup-interval-hours ile açılır.
  BackupSchedulePolicy backupSchedule = BackupSchedulePolicy(
    interval: Duration(hours: int.tryParse(env['BACKUP_INTERVAL_HOURS'] ?? '0') ?? 0),
  );

  for (final arg in args) {
    if (arg.startsWith('--port=')) {
      port = int.tryParse(arg.substring(7)) ?? port;
    } else if (arg.startsWith('--discovery-port=')) {
      discoveryPort = int.tryParse(arg.substring(17)) ?? discoveryPort;
    } else if (arg == '--no-discovery') {
      enableDiscovery = false;
    } else if (arg.startsWith('--db-path=')) {
      dbPath = arg.substring(10);
    } else if (arg.startsWith('--backup-dir=')) {
      backupDir = arg.substring(13);
    } else if (arg.startsWith('--admin-secret=')) {
      adminSecret = arg.substring(15);
    } else if (arg.startsWith('--pepper-file=')) {
      pepperPath = arg.substring(14);
    } else if (arg.startsWith('--cert=')) {
      certPath = arg.substring(7);
      enableTls = true;
    } else if (arg.startsWith('--key=')) {
      keyPath = arg.substring(6);
      enableTls = true;
    } else if (arg.startsWith('--ca-cert=')) {
      caCertPath = arg.substring(10);
    } else if (arg.startsWith('--advertise-host=')) {
      advertiseHost = arg.substring('--advertise-host='.length);
    } else if (arg == '--tls') {
      enableTls = true;
    } else if (arg.startsWith('--tenant-id=')) {
      tenantId = arg.substring(12);
    } else if (arg.startsWith('--store-id=')) {
      storeId = arg.substring(11);
    } else if (arg.startsWith('--hub-id=')) {
      hubId = arg.substring(9);
    } else if (arg.startsWith('--backup-interval-hours=')) {
      final hours = int.tryParse(arg.substring('--backup-interval-hours='.length)) ?? 0;
      backupSchedule = BackupSchedulePolicy(interval: Duration(hours: hours.clamp(0, 168)));
    } else if (arg == '--require-tenant-store-headers') {
      requireTenantStoreHeaders = true;
    } else if (arg == '--allow-missing-tenant-store-headers') {
      // Yalnızca eski (başlık göndermeyen) istemcilerle geçiş dönemi için bilinçli gevşetme.
      requireTenantStoreHeaders = false;
      stderr.writeln('[UYARI] Tenant/store başlık zorunluluğu devre dışı bırakıldı (--allow-missing-tenant-store-headers).');
    }
  }

  return ResolvedHubStartupConfig(
    port: port,
    discoveryPort: discoveryPort,
    enableDiscovery: enableDiscovery,
    dbPath: dbPath,
    backupDir: backupDir,
    adminSecret: adminSecret,
    pepperPath: pepperPath,
    certPath: certPath,
    keyPath: keyPath,
    caCertPath: caCertPath,
    advertiseHost: advertiseHost,
    enableTls: enableTls,
    tenantId: tenantId,
    storeId: storeId,
    hubId: hubId,
    requireTenantStoreHeaders: requireTenantStoreHeaders,
    backupSchedule: backupSchedule,
    loadedFromConfigFile: false,
  );
}

Future<SpikeServer> startHubFromArgs(
  List<String> args, {
  Map<String, String>? environment,
}) async {
  configureSqliteNative();

  final startup = resolveHubStartupConfig(args, environment: environment);

  if (startup.loadedFromConfigFile) {
    stdout.writeln(
      '[REL-01] Yapılandırma yüklendi (${startup.environmentName}): '
      'port=${startup.port} tls=${startup.enableTls}',
    );
  }

  final dbFile = File(startup.dbPath);
  if (!dbFile.parent.existsSync()) {
    dbFile.parent.createSync(recursive: true);
  }
  final db = SpikeDatabase(dbFile);
  final queue = WriteQueue();

  // PepperManager başlat
  final pepperManager = PepperManager(File(startup.pepperPath ?? 'pepper.dpapi'));
  pepperManager.initialize();

  SecurityContext? securityContext;
  if (startup.enableTls) {
    if (startup.certPath == null || startup.keyPath == null) {
      throw TlsConfigurationException('TLS etkinleştirildi ancak --cert veya --key dosyaları belirtilmedi.');
    }
    securityContext = CertificateManager.createServerSecurityContext(
      certChainPath: startup.certPath!,
      privateKeyPath: startup.keyPath!,
    );
  }

  final server = SpikeServer(
    db: db,
    dbFile: dbFile,
    writeQueue: queue,
    backupDirectory: startup.backupDir,
    adminSecret: startup.adminSecret,
    pepperManager: pepperManager,
    securityContext: securityContext,
    requireTls: startup.enableTls,
    caCertPath: startup.caCertPath,
    serverCertPath: startup.certPath,
    advertiseHost: startup.advertiseHost,
    tenantId: startup.tenantId,
    storeId: startup.storeId,
    hubId: startup.hubId,
    requireTenantStoreHeaders: startup.requireTenantStoreHeaders,
    backupSchedule: startup.backupSchedule,
    allowAdminEnvFallback: !startup.loadedFromConfigFile,
    environment: environment,
  );
  await server.start(
    port: startup.port,
    enableDiscovery: startup.enableDiscovery,
    discoveryPort: startup.discoveryPort,
  );

  final schemeLabel = startup.enableTls ? 'https' : 'http';
  stdout.writeln('MARKET MMS SPIKE-01 Backend çalışıyor: $schemeLabel://0.0.0.0:${startup.port}');
  if (startup.enableDiscovery) {
    stdout.writeln('UDP Discovery dinleniyor: UDP 0.0.0.0:${startup.discoveryPort}');
  }
  stdout.writeln('Veritabanı: ${p.basename(startup.dbPath)}');

  return server;
}

void main(List<String> args) async {
  final SpikeServer server;
  try {
    server = await startHubFromArgs(args);
  } on HubStartupArgException catch (e) {
    stderr.writeln(e.message);
    exit(e.exitCode);
  } on TlsConfigurationException catch (e) {
    stderr.writeln('[ERR_TLS_CONFIG] ${e.message}');
    exit(78);
  } catch (e) {
    stderr.writeln('[ERR_HUB_STARTUP] ${SpikeServer.redactLogText(e.toString())}');
    exit(1);
  }

  await server.lifecycle.onShutdown;
  await server.stop();
  stdout.writeln('MARKET MMS SPIKE-01 Backend güvenle kapatıldı.');
  exit(server.lifecycle.exitCode);
}
