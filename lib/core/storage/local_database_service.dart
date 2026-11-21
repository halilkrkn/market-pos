import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

import '../constants/app_constants.dart';

/// MARKET MMS - İstemci Yerel Veritabanı Yaşam Döngüsü Durumları
enum LocalDatabaseLifecycleState {
  uninitialized,
  initializing,
  ready,
  closing,
  closed,
  failed,
}

/// Veritabanı kapalıyken işlem yapılmaya çalışıldığında fırlatılan kontrollü istisna
class DatabaseClosedException implements Exception {
  final String message;
  const DatabaseClosedException([
    this.message = 'LocalDatabaseService kapatılmıştır; bu bağlantı üzerinden işlem yapılamaz.',
  ]);

  @override
  String toString() => 'DatabaseClosedException: $message';
}

/// MARKET MMS - İstemci Yerel Drift + SQLite Veritabanı Servisi
///
/// DİKKAT: Bu servis YALNIZCA istemci yerel veritabanı olan `client_local.db` ile çalışır.
/// Merkezi sunucu veritabanına (`market_master.db`) doğrudan bağlantı KESİNLİKLE YASAKTIR.
///
/// B-6 FINAL REMEDIATION:
/// - Yaşam döngüsü koordinasyonu (Uninitialized, Initializing, Ready, Closing, Closed, Failed).
/// - Tekil initialization Future ile eşzamanlı açılışların tekilleştirilmesi.
/// - Devam eden close varken initialize çağrılarının eski bağlantının kapanmasını beklemesi.
/// - Devam eden initialize varken closeActive çağrılarının deterministik sırayla tamamlanması (otomatik re-init kaldırıldı).
/// - Eşzamanlı close çağrılarının aynı Future'ı paylaşması ve idempotency.
/// - Yürütülmekte olan (in-flight) sorguların kapanış öncesi kontrollü tahliyesi (drain).
/// - Repository operasyonlarının otomatik olarak drain mekanizmasına dahil edilmesi (`_TrackedClientStorageRepository`).
/// - Farklı DB path taleplerinde eşzamanlı çağrıların deterministik sırayla yönetilmesi.
/// - Graceful close timeout telemetri ve `_db.close()` emniyet timeout'u.
/// - DB close timeout sonrası veri bütünlüğü koruması (timeout durumunda yeni initialize engellenir).
/// - Test amaçlı `resetForTesting()` metodunun tüm durum ve timeout değerlerini sıfırlaması.
class LocalDatabaseService {
  ClientDatabase _db;
  late ClientStorageRepository _repository;
  final String _databasePath;
  bool _isClosed = false;

  int _activeQueryCount = 0;
  Completer<void>? _activeQueriesDrainedCompleter;
  Future<void>? _closeFuture;

  static const Duration defaultDrainTimeout = Duration(seconds: 2);
  static const Duration defaultDbCloseTimeout = Duration(seconds: 5);

  /// Drain timeout süresi (test ortamında override edilebilir)
  static Duration drainTimeout = defaultDrainTimeout;

  /// `_db.close()` emniyet timeout süresi (test ortamında override edilebilir)
  static Duration dbCloseTimeout = defaultDbCloseTimeout;

  static LocalDatabaseService? _instance;
  static Future<LocalDatabaseService>? _initializationFuture;
  static String? _initializingPath;
  static Future<void>? _activeCloseFuture;
  static bool _hasCloseTimedOut = false;

  LocalDatabaseService._(
    this._db,
    this._databasePath,
  );

  void _initRepository() {
    _repository = _TrackedClientStorageRepository(this, _db);
  }

  /// Canlı Masaüstü / Mobil Ortamı İçin Üretim Başlatıcısı
  ///
  /// Windows üzerinde `%LOCALAPPDATA%\MarketMMS\client_local.db` konumunu hedefler.
  static Future<LocalDatabaseService> initialize({
    String? customPath,
  }) async {
    // 0. DB close timeout oluştuysa veri bütünlüğünü korumak için yeni bağlantı açma
    if (_hasCloseTimedOut) {
      throw StateError(
        'Veritabanı önceki kapatma işlemi sırasında zaman aşımına uğradı '
        '(Drift isolate yanıt vermedi). Veri bütünlüğünü korumak için yeni '
        'bağlantı açılması engellendi. Uygulamayı yeniden başlatınız.',
      );
    }

    // 1. Devam eden bir kapanış işlemi varsa eski bağlantının tamamen kapanmasını bekle
    if (_activeCloseFuture != null) {
      await _activeCloseFuture;
    }

    // Kapanış bittikten sonra tekrar timeout kontrolü
    if (_hasCloseTimedOut) {
      throw StateError(
        'Veritabanı kapatma işlemi sırasında zaman aşımına uğradı. '
        'Veri bütünlüğünü korumak için yeni bağlantı açılamaz.',
      );
    }

    // 2. Zaten başlatılmış ve henüz kapatılmamış bir örnek varsa kontrol et
    final current = _instance;
    if (current != null && !current._isClosed) {
      if (customPath == null || customPath == current._databasePath) {
        return current;
      }
      // Farklı bir path talep edildiyse önce mevcut açık bağlantıyı deterministik olarak kapat
      await current.close();
    }

    // 3. Devam eden bir başlatma Future'ı varsa eşzamanlı çağrıları yönet
    if (_initializationFuture != null) {
      final requestedPath = customPath ?? _resolveDefaultDatabasePath();
      if (_initializingPath == requestedPath) {
        // Aynı path için devam eden başlatma: mevcut Future'ı paylaş
        return _initializationFuture!;
      } else {
        // Farklı path: mevcut başlatmanın tamamlanmasını bekle, sonra kapat ve yeni path aç
        try {
          final existingService = await _initializationFuture!;
          if (!existingService._isClosed) {
            await existingService.close();
          }
        } catch (_) {
          // Mevcut başlatma başarısız olduysa devam et
        }
        return initialize(customPath: customPath);
      }
    }

    // 4. Tekil başlatma Future'ını oluştur
    final resolvedPath = customPath ?? _resolveDefaultDatabasePath();
    _initializingPath = resolvedPath;
    final future = _performInitialize(customPath);
    _initializationFuture = future;

    try {
      final service = await future;
      _instance = service;
      return service;
    } catch (e) {
      _instance = null;
      rethrow;
    } finally {
      if (identical(_initializationFuture, future)) {
        _initializationFuture = null;
        _initializingPath = null;
      }
    }
  }

  static Future<LocalDatabaseService> _performInitialize(String? customPath) async {
    final String resolvedPath;

    if (customPath != null && customPath.isNotEmpty) {
      resolvedPath = customPath;
    } else {
      resolvedPath = _resolveDefaultDatabasePath();
    }

    final dbFile = File(resolvedPath);
    if (!dbFile.parent.existsSync()) {
      dbFile.parent.createSync(recursive: true);
    }

    final db = ClientDatabase(dbFile);
    final service = LocalDatabaseService._(
      db,
      resolvedPath,
    );
    service._initRepository();
    return service;
  }

  /// Birim ve Entegrasyon Testleri İçin In-Memory / Test Başlatıcısı
  factory LocalDatabaseService.forTesting(QueryExecutor executor, {String path = ':memory:'}) {
    final db = ClientDatabase.forTesting(executor);
    final service = LocalDatabaseService._(
      db,
      path,
    );
    service._initRepository();
    return service;
  }

  /// Platforma göre standart `client_local.db` dosya yolunu dışarıya açık çözer.
  static String resolveDefaultDatabasePath() => _resolveDefaultDatabasePath();

  /// Platforma Göre Standart Veritabanı Yolunu Çözümler
  static String _resolveDefaultDatabasePath() {
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        return p.join(
          localAppData,
          AppConstants.appDataFolderName,
          AppConstants.localDatabaseName,
        );
      }
    }

    if (Platform.isAndroid) {
      return '/data/data/com.marketmms.market_pos/app_flutter/${AppConstants.localDatabaseName}';
    }

    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    return p.join(home, '.marketmms', AppConstants.localDatabaseName);
  }

  /// Kapalı bağlantı kontrolü
  void _ensureOpen() {
    if (_isClosed) {
      throw const DatabaseClosedException();
    }
  }

  /// İç diagnostics sorguları için aktif sorgu sayacı takipçisi
  Future<T> _runQuery<T>(Future<T> Function() query) async {
    return runOperation(query);
  }

  /// İş mantığı operasyonlarını (satış, outbox, stok, ürün güncelleme vb.)
  /// aktif sorgu sayacına dahil ederek kapanış sırasında kontrollü tahliye sağlar.
  Future<T> runOperation<T>(Future<T> Function() operation) async {
    _ensureOpen();
    _activeQueryCount++;
    try {
      return await operation();
    } finally {
      _activeQueryCount--;
      _checkDrainCompleted();
    }
  }

  /// Drain tamamlanma kontrolü
  void _checkDrainCompleted() {
    if (_activeQueryCount == 0 && _activeQueriesDrainedCompleter != null) {
      if (!_activeQueriesDrainedCompleter!.isCompleted) {
        _activeQueriesDrainedCompleter!.complete();
      }
    }
  }

  /// Doğrudan Drift DB örneği (Kapalı bağlantıda erişilirse [DatabaseClosedException] fırlatır)
  ClientDatabase get database {
    _ensureOpen();
    return _db;
  }

  /// Yüksek seviyeli storage repository (Tüm operasyonlar otomatik olarak drain sayacına tabidir)
  ClientStorageRepository get repository {
    _ensureOpen();
    return _repository;
  }

  /// Dosya konumu
  String get databasePath => _databasePath;

  /// Veritabanı ve yardımcı yapılandırma dosyalarının bulunduğu kök klasör
  String get dataDirectoryPath =>
      _databasePath == ':memory:' ? Directory.systemTemp.path : p.dirname(_databasePath);

  /// Bağlantının kapatılıp kapatılmadığı
  bool get isClosed => _isClosed;

  /// Aktif yürütülmekte olan sorgu/operasyon sayısı (diagnostics ve drain izleme amaçlı)
  int get activeQueryCount => _activeQueryCount;

  /// WAL modu açıkken tutarlı canlı anlık görüntü (`VACUUM INTO`) üretir.
  Future<void> vacuumInto(String snapshotPath) {
    return _runQuery(() async {
      final outFile = File(snapshotPath);
      if (outFile.existsSync()) {
        outFile.deleteSync();
      }
      if (!outFile.parent.existsSync()) {
        outFile.parent.createSync(recursive: true);
      }
      try {
        await _db.customStatement('PRAGMA wal_checkpoint(PASSIVE);');
      } catch (_) {
        // Checkpoint bilgilendirme amaçlıdır; VACUUM INTO salt okunur tutarlıdır.
      }
      final escaped = snapshotPath.replaceAll("'", "''");
      await _db.customStatement("VACUUM INTO '$escaped'");
    });
  }

  /// Kontrollü geri yükleme (restore) öncesi canlı veritabanı bağlantılarını askıya alır.
  Future<void> suspendForRestore() async {
    if (_databasePath == ':memory:') {
      throw StateError('Bellek içi veritabanı geri yükleme için askıya alınamaz.');
    }
    if (_isClosed) return;
    if (_closeFuture != null) {
      await _closeFuture!;
      return;
    }

    _isClosed = true;

    if (_activeQueryCount > 0) {
      final drainCompleter = Completer<void>();
      _activeQueriesDrainedCompleter = drainCompleter;
      if (_activeQueryCount > 0) {
        await drainCompleter.future.timeout(
          drainTimeout,
          onTimeout: () {
            stderr.writeln(
              '[LocalDatabaseService] UYARI: Restore öncesi $_activeQueryCount '
              'aktif işlem tahliye süresi doldu.',
            );
          },
        );
      }
    }

    try {
      await _db.customStatement('PRAGMA wal_checkpoint(TRUNCATE);');
    } catch (_) {}

    await _db.close().timeout(dbCloseTimeout);
    _closeFuture = null;
    _activeQueriesDrainedCompleter = null;
  }

  /// Kontrollü geri yükleme (restore) sonrasında yeni veritabanı dosyasını aynı servis örneğinde açar.
  Future<void> resumeAfterRestore() async {
    if (_databasePath == ':memory:') {
      throw StateError('Bellek içi veritabanı geri yükleme sonrası yeniden açılamaz.');
    }
    if (!_isClosed) return;

    final reopenedDb = ClientDatabase(File(_databasePath));
    _db = reopenedDb;
    (_repository as _TrackedClientStorageRepository).rebind(reopenedDb);
    _isClosed = false;
    _closeFuture = null;
    _activeQueriesDrainedCompleter = null;
  }

  /// Mevcut nesnenin yaşam döngüsü durumu
  LocalDatabaseLifecycleState get lifecycleState {
    if (_hasCloseTimedOut) return LocalDatabaseLifecycleState.failed;
    if (_isClosed) return LocalDatabaseLifecycleState.closed;
    if (_closeFuture != null) return LocalDatabaseLifecycleState.closing;
    return LocalDatabaseLifecycleState.ready;
  }

  /// Mevcut tekil örnek (varsa)
  static LocalDatabaseService? get currentInstance => _instance;

  /// Sistemin genel statik yaşam döngüsü durumu
  static LocalDatabaseLifecycleState get currentLifecycleState {
    if (_hasCloseTimedOut) return LocalDatabaseLifecycleState.failed;
    if (_activeCloseFuture != null) return LocalDatabaseLifecycleState.closing;
    if (_initializationFuture != null) return LocalDatabaseLifecycleState.initializing;
    final current = _instance;
    if (current == null) return LocalDatabaseLifecycleState.uninitialized;
    return current.lifecycleState;
  }

  /// DB close zaman aşımına uğramış mı?
  static bool get hasCloseTimedOut => _hasCloseTimedOut;

  /// Test amaçlı tekil örneği, tüm yaşam döngüsü Future'larını ve timeout değerlerini sıfırlar
  static void resetForTesting() {
    _instance = null;
    _initializationFuture = null;
    _initializingPath = null;
    _activeCloseFuture = null;
    _hasCloseTimedOut = false;
    drainTimeout = defaultDrainTimeout;
    dbCloseTimeout = defaultDbCloseTimeout;
  }

  /// Bekleyen senkronize edilmemiş outbox kayıt sayısı (Yalnızca PENDING durumundakiler)
  Future<int> getPendingOutboxCount() {
    return _runQuery(() async {
      final countExp = _db.outboxOperations.operationId.count();
      final query = _db.selectOnly(_db.outboxOperations)
        ..addColumns([countExp])
        ..where(_db.outboxOperations.status.equals('PENDING'));
      final result = await query.getSingle();
      return result.read(countExp) ?? 0;
    });
  }

  /// Senkronizasyon kuyruğundaki operasyonların durum bazlı detaylı özeti (PENDING, RETRY, IN_PROGRESS, FAILED_PERMANENT)
  Future<OutboxSummary> getOutboxSummary({String? deviceId}) {
    return _repository.getOutboxSummary(deviceId: deviceId);
  }

  /// Yerel satış sayısı
  Future<int> getLocalSalesCount() {
    return _runQuery(() async {
      final countExp = _db.localSales.id.count();
      final query = _db.selectOnly(_db.localSales)..addColumns([countExp]);
      final result = await query.getSingle();
      return result.read(countExp) ?? 0;
    });
  }

  /// Önbellekteki ürün sayısı
  Future<int> getLocalProductsCount() {
    return _runQuery(() async {
      final countExp = _db.localProducts.id.count();
      final query = _db.selectOnly(_db.localProducts)..addColumns([countExp]);
      final result = await query.getSingle();
      return result.read(countExp) ?? 0;
    });
  }

  /// Aktif veya başlatılmakta olan veritabanı örneğini deterministik olarak kapatır
  static Future<void> closeActive() async {
    // 1. Devam eden bir başlatma varsa önce tamamlanmasını bekle, ardından kapat
    if (_initializationFuture != null) {
      try {
        final service = await _initializationFuture!;
        await service.close();
      } catch (_) {}
      return;
    }

    // 2. Halihazırda kapanmakta olan bir bağlantı varsa onun tamamlanmasını bekle
    if (_activeCloseFuture != null) {
      await _activeCloseFuture;
      return;
    }

    // 3. Açık örnek varsa kapat
    final current = _instance;
    if (current != null) {
      await current.close();
    }
  }

  /// Veritabanını güvenle kapatır, eşzamanlı çağrıları tekilleştirir ve tekil örneği temizler
  Future<void> close() async {
    if (_isClosed) return;
    if (_closeFuture != null) {
      return _closeFuture!;
    }

    final future = _performClose();
    _closeFuture = future;
    _activeCloseFuture = future;

    try {
      await future;
    } finally {
      if (identical(_activeCloseFuture, future)) {
        _activeCloseFuture = null;
      }
    }
  }

  Future<void> _performClose() async {
    _isClosed = true;

    // Yürütülmekte olan in-flight sorgular/operasyonlar varsa tamamlanmaları için süre tanı (Drain)
    if (_activeQueryCount > 0) {
      final drainCompleter = Completer<void>();
      _activeQueriesDrainedCompleter = drainCompleter;
      if (_activeQueryCount > 0) {
        await drainCompleter.future.timeout(
          drainTimeout,
          onTimeout: () {
            stderr.writeln(
              '[LocalDatabaseService] UYARI: $_activeQueryCount aktif sorgu/operasyon '
              '${drainTimeout.inSeconds}s drain süresi içinde tamamlanamadı. '
              'Zorla kapatmaya geçiliyor. (path: $_databasePath)',
            );
          },
        );
      }
    }

    try {
      await _db.close().timeout(
        dbCloseTimeout,
        onTimeout: () {
          _hasCloseTimedOut = true;
          stderr.writeln(
            '[LocalDatabaseService] UYARI: _db.close() ${dbCloseTimeout.inSeconds}s '
            'emniyet süresi içinde tamamlanamadı. Drift isolate yanıt vermiyor olabilir. '
            '(path: $_databasePath)',
          );
        },
      );
    } finally {
      if (identical(_instance, this)) {
        _instance = null;
      }
    }
  }
}

/// Tüm operasyonları `LocalDatabaseService.runOperation` üzerinden yürüten sarmalayıcı repository.
/// Bu sayede doğrudan `service.repository.xxx()` çağrıları da otomatik olarak aktif sorgu sayacına
/// ve graceful shutdown tahliye (drain) mekanizmasına dahil edilir.
class _TrackedClientStorageRepository extends ClientStorageRepository {
  final LocalDatabaseService _service;
  ClientStorageRepository _delegate;

  _TrackedClientStorageRepository(this._service, ClientDatabase db)
      : _delegate = ClientStorageRepository(db),
        super(db);

  @override
  ClientDatabase get db => _service._db;

  void rebind(ClientDatabase newDb) {
    _delegate = ClientStorageRepository(newDb);
  }

  @override
  Future<ClientSyncState> initializeDevice(String deviceId) =>
      _service.runOperation(() => _delegate.initializeDevice(deviceId));

  @override
  Future<int> allocateNextClientSeq(String deviceId, {DateTime? occurredAt}) =>
      _service.runOperation(
        () => _delegate.allocateNextClientSeq(deviceId, occurredAt: occurredAt),
      );

  @override
  Future<ClientSyncState?> getSyncState(String deviceId) =>
      _service.runOperation(() => _delegate.getSyncState(deviceId));

  @override
  Future<SaleTransactionResult> createOfflineSale({
    required String deviceId,
    required String paymentMethod,
    required List<CartItemInput> items,
    String? customOperationId,
    DateTime? occurredAt,
  }) =>
      _service.runOperation(
        () => _delegate.createOfflineSale(
          deviceId: deviceId,
          paymentMethod: paymentMethod,
          items: items,
          customOperationId: customOperationId,
          occurredAt: occurredAt,
        ),
      );

  @override
  Future<void> upsertProducts(
    List<LocalProductsCompanion> products, {
    List<LocalProductBarcodesCompanion>? barcodes,
  }) =>
      _service.runOperation(
        () => _delegate.upsertProducts(products, barcodes: barcodes),
      );

  @override
  Future<LocalProduct?> getProductByBarcode(String barcode) =>
      _service.runOperation(() => _delegate.getProductByBarcode(barcode));

  @override
  Future<List<LocalProductBarcode>> getBarcodesForProduct(String productId) =>
      _service.runOperation(() => _delegate.getBarcodesForProduct(productId));

  @override
  Future<OutboxOperation?> getNextUnsyncedOutboxOperation(
    String deviceId, {
    DateTime? now,
  }) =>
      _service.runOperation(
        () => _delegate.getNextUnsyncedOutboxOperation(deviceId, now: now),
      );

  @override
  Future<List<OutboxOperation>> getUnsyncedOutboxOperations(String deviceId) =>
      _service.runOperation(
        () => _delegate.getUnsyncedOutboxOperations(deviceId),
      );

  @override
  Future<void> markOutboxInProgress(String operationId) =>
      _service.runOperation(() => _delegate.markOutboxInProgress(operationId));

  @override
  Future<void> markOutboxSynced(
    String operationId, {
    required int clientSeq,
    required String deviceId,
    DateTime? acknowledgedAt,
  }) =>
      _service.runOperation(
        () => _delegate.markOutboxSynced(
          operationId,
          clientSeq: clientSeq,
          deviceId: deviceId,
          acknowledgedAt: acknowledgedAt,
        ),
      );

  @override
  Future<void> markOutboxRetry(
    String operationId, {
    required int attemptCount,
    required Duration backoff,
    required String error,
    DateTime? now,
  }) =>
      _service.runOperation(
        () => _delegate.markOutboxRetry(
          operationId,
          attemptCount: attemptCount,
          backoff: backoff,
          error: error,
          now: now,
        ),
      );

  @override
  Future<void> markOutboxPermanentFail(
    String operationId, {
    required String error,
  }) =>
      _service.runOperation(
        () => _delegate.markOutboxPermanentFail(operationId, error: error),
      );

  @override
  Future<List<OutboxOperation>> getFailedPermanentOperations(String deviceId) =>
      _service.runOperation(
        () => _delegate.getFailedPermanentOperations(deviceId),
      );

  @override
  Future<void> retryFailedPermanentOperation(String operationId) =>
      _service.runOperation(
        () => _delegate.retryFailedPermanentOperation(operationId),
      );

  @override
  Future<void> updateAndRetryFailedOperation(
    String operationId, {
    required Map<String, dynamic> correctedPayload,
  }) =>
      _service.runOperation(
        () => _delegate.updateAndRetryFailedOperation(
          operationId,
          correctedPayload: correctedPayload,
        ),
      );

  @override
  Future<int> recoverStuckInProgressOperations(String deviceId) =>
      _service.runOperation(
        () => _delegate.recoverStuckInProgressOperations(deviceId),
      );

  @override
  Future<void> reconcileSaleStatuses() =>
      _service.runOperation(() => _delegate.reconcileSaleStatuses());

  @override
  Future<OutboxSummary> getOutboxSummary({String? deviceId}) =>
      _service.runOperation(() => _delegate.getOutboxSummary(deviceId: deviceId));

  @override
  Future<List<LocalSale>> getSalesHistory({
    DateTime? startDate,
    DateTime? endDate,
    String? paymentMethod,
    String? status,
    String? searchQuery,
    int limit = 50,
    int offset = 0,
  }) =>
      _service.runOperation(
        () => _delegate.getSalesHistory(
          startDate: startDate,
          endDate: endDate,
          paymentMethod: paymentMethod,
          status: status,
          searchQuery: searchQuery,
          limit: limit,
          offset: offset,
        ),
      );

  @override
  Future<SaleWithDetails?> getSaleDetail(String saleId) =>
      _service.runOperation(() => _delegate.getSaleDetail(saleId));

  @override
  Future<void> cancelSale({
    required String saleId,
    required String reason,
    required String deviceId,
    DateTime? cancelledAt,
  }) =>
      _service.runOperation(
        () => _delegate.cancelSale(
          saleId: saleId,
          reason: reason,
          deviceId: deviceId,
          cancelledAt: cancelledAt,
        ),
      );

  @override
  Future<String> refundSale({
    required String saleId,
    required List<RefundItemInput> items,
    required String reason,
    required String deviceId,
    DateTime? createdAt,
  }) =>
      _service.runOperation(
        () => _delegate.refundSale(
          saleId: saleId,
          items: items,
          reason: reason,
          deviceId: deviceId,
          createdAt: createdAt,
        ),
      );

  @override
  Future<List<LocalCategory>> getCategories({bool includeInactive = false}) =>
      _service.runOperation(
        () => _delegate.getCategories(includeInactive: includeInactive),
      );

  @override
  Future<LocalCategory?> getCategoryById(String id) =>
      _service.runOperation(() => _delegate.getCategoryById(id));

  @override
  Future<LocalCategory> createCategory({
    required String name,
    String? parentId,
  }) =>
      _service.runOperation(
        () => _delegate.createCategory(name: name, parentId: parentId),
      );

  @override
  Future<void> updateCategory({
    required String id,
    required String name,
    String? parentId,
    bool? isActive,
  }) =>
      _service.runOperation(
        () => _delegate.updateCategory(
          id: id,
          name: name,
          parentId: parentId,
          isActive: isActive,
        ),
      );

  @override
  Future<void> deactivateCategory(String id) =>
      _service.runOperation(() => _delegate.deactivateCategory(id));

  @override
  Future<List<LocalProduct>> getProducts({
    String? searchQuery,
    String? categoryId,
    bool? isActive,
    int limit = 100,
    int offset = 0,
  }) =>
      _service.runOperation(
        () => _delegate.getProducts(
          searchQuery: searchQuery,
          categoryId: categoryId,
          isActive: isActive,
          limit: limit,
          offset: offset,
        ),
      );

  @override
  Future<LocalProduct?> getProductById(String id) =>
      _service.runOperation(() => _delegate.getProductById(id));

  @override
  Future<LocalProduct> createProduct({
    required String name,
    required int price,
    String? barcode,
    String? categoryId,
    int initialStock = 0,
    String stockUnit = 'adet',
    String pricingUnit = 'adet',
    int conversionFactorNumerator = 1,
    int conversionFactorDenominator = 1,
    int vatRate = 20,
    int? initialPurchasePrice,
    String? deviceId,
  }) =>
      _service.runOperation(
        () => _delegate.createProduct(
          name: name,
          price: price,
          barcode: barcode,
          categoryId: categoryId,
          initialStock: initialStock,
          stockUnit: stockUnit,
          pricingUnit: pricingUnit,
          conversionFactorNumerator: conversionFactorNumerator,
          conversionFactorDenominator: conversionFactorDenominator,
          vatRate: vatRate,
          initialPurchasePrice: initialPurchasePrice,
          deviceId: deviceId,
        ),
      );

  @override
  Future<LocalProduct> updateProduct({
    required String id,
    String? name,
    int? price,
    String? categoryId,
    String? barcode,
    String? stockUnit,
    String? pricingUnit,
    int? conversionFactorNumerator,
    int? conversionFactorDenominator,
    int? vatRate,
    bool? isActive,
    String? priceChangeReason,
    String? deviceId,
  }) =>
      _service.runOperation(
        () => _delegate.updateProduct(
          id: id,
          name: name,
          price: price,
          categoryId: categoryId,
          barcode: barcode,
          stockUnit: stockUnit,
          pricingUnit: pricingUnit,
          conversionFactorNumerator: conversionFactorNumerator,
          conversionFactorDenominator: conversionFactorDenominator,
          vatRate: vatRate,
          isActive: isActive,
          priceChangeReason: priceChangeReason,
          deviceId: deviceId,
        ),
      );

  @override
  Future<void> deactivateProduct(String id, {String? deviceId}) =>
      _service.runOperation(
        () => _delegate.deactivateProduct(id, deviceId: deviceId),
      );

  @override
  Future<int> reconcileUnsyncedProducts(String deviceId) =>
      _service.runOperation(() => _delegate.reconcileUnsyncedProducts(deviceId));

  @override
  Future<void> addProductBarcode({
    required String productId,
    required String barcode,
    bool isPrimary = false,
  }) =>
      _service.runOperation(
        () => _delegate.addProductBarcode(
          productId: productId,
          barcode: barcode,
          isPrimary: isPrimary,
        ),
      );

  @override
  Future<void> removeProductBarcode(String barcodeId) =>
      _service.runOperation(() => _delegate.removeProductBarcode(barcodeId));

  @override
  Future<List<LocalPriceHistoryData>> getPriceHistory(String productId) =>
      _service.runOperation(() => _delegate.getPriceHistory(productId));

  @override
  Future<StockReceiptResult> receiveStock({
    required String receiptId,
    required String productId,
    required int quantityMilli,
    int? unitPurchasePrice,
    String? note,
    required String deviceId,
    DateTime? occurredAt,
  }) =>
      _service.runOperation(
        () => _delegate.receiveStock(
          receiptId: receiptId,
          productId: productId,
          quantityMilli: quantityMilli,
          unitPurchasePrice: unitPurchasePrice,
          note: note,
          deviceId: deviceId,
          occurredAt: occurredAt,
        ),
      );

  @override
  Future<Set<String>> productIdsWithUnsyncedStockChanges() =>
      _service.runOperation(() => _delegate.productIdsWithUnsyncedStockChanges());

  @override
  Future<List<LocalStockMovement>> getStockMovements({
    String? productId,
    int limit = 100,
    int offset = 0,
  }) =>
      _service.runOperation(
        () => _delegate.getStockMovements(
          productId: productId,
          limit: limit,
          offset: offset,
        ),
      );

  @override
  Future<void> upsertSales({
    required List<DownloadedSalePayload> sales,
    required int newCursor,
    required String deviceId,
    DateTime? syncedAt,
  }) =>
      _service.runOperation(
        () => _delegate.upsertSales(
          sales: sales,
          newCursor: newCursor,
          deviceId: deviceId,
          syncedAt: syncedAt,
        ),
      );

  @override
  Future<StoredHubConnection?> getStoredHubConnection({
    required bool allowLoopback,
  }) =>
      _service.runOperation(
        () => _delegate.getStoredHubConnection(allowLoopback: allowLoopback),
      );

  @override
  Future<StoredHubConnection> saveStoredHubConnection({
    required String hubUrl,
    String? hubId,
    required HubUrlSource source,
    bool allowLoopback = false,
    DateTime? verifiedAt,
    DateTime? now,
  }) =>
      _service.runOperation(
        () => _delegate.saveStoredHubConnection(
          hubUrl: hubUrl,
          hubId: hubId,
          source: source,
          allowLoopback: allowLoopback,
          verifiedAt: verifiedAt,
          now: now,
        ),
      );

  @override
  Future<StoredHubConnection> markHubConnectionVerified({
    required String hubUrl,
    String? hubId,
    HubUrlSource? source,
    bool allowLoopback = false,
    DateTime? verifiedAt,
  }) =>
      _service.runOperation(
        () => _delegate.markHubConnectionVerified(
          hubUrl: hubUrl,
          hubId: hubId,
          source: source,
          allowLoopback: allowLoopback,
          verifiedAt: verifiedAt,
        ),
      );

  @override
  Future<void> clearStoredHubConnection() =>
      _service.runOperation(() => _delegate.clearStoredHubConnection());
}
