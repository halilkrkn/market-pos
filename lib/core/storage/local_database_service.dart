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
  final ClientDatabase _db;
  late final ClientStorageRepository _repository;
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

  /// Bağlantının kapatılıp kapatılmadığı
  bool get isClosed => _isClosed;

  /// Aktif yürütülmekte olan sorgu/operasyon sayısı (diagnostics ve drain izleme amaçlı)
  int get activeQueryCount => _activeQueryCount;

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

  /// Bekleyen senkronize edilmemiş outbox kayıt sayısı
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

  _TrackedClientStorageRepository(this._service, ClientDatabase db) : super(db);

  @override
  Future<ClientSyncState> initializeDevice(String deviceId) =>
      _service.runOperation(() => super.initializeDevice(deviceId));

  @override
  Future<ClientSyncState?> getSyncState(String deviceId) =>
      _service.runOperation(() => super.getSyncState(deviceId));

  @override
  Future<SaleTransactionResult> createOfflineSale({
    required String deviceId,
    required String paymentMethod,
    required List<CartItemInput> items,
    String? customOperationId,
    DateTime? occurredAt,
  }) =>
      _service.runOperation(() => super.createOfflineSale(
            deviceId: deviceId,
            paymentMethod: paymentMethod,
            items: items,
            customOperationId: customOperationId,
            occurredAt: occurredAt,
          ));

  @override
  Future<void> upsertProducts(
    List<LocalProductsCompanion> products, {
    List<LocalProductBarcodesCompanion>? barcodes,
  }) =>
      _service.runOperation(() => super.upsertProducts(products, barcodes: barcodes));

  @override
  Future<LocalProduct?> getProductByBarcode(String barcode) =>
      _service.runOperation(() => super.getProductByBarcode(barcode));

  @override
  Future<List<LocalProductBarcode>> getBarcodesForProduct(String productId) =>
      _service.runOperation(() => super.getBarcodesForProduct(productId));

  @override
  Future<OutboxOperation?> getNextUnsyncedOutboxOperation(
    String deviceId, {
    DateTime? now,
  }) =>
      _service.runOperation(() => super.getNextUnsyncedOutboxOperation(deviceId, now: now));

  @override
  Future<List<OutboxOperation>> getUnsyncedOutboxOperations(String deviceId) =>
      _service.runOperation(() => super.getUnsyncedOutboxOperations(deviceId));

  @override
  Future<void> markOutboxInProgress(String operationId) =>
      _service.runOperation(() => super.markOutboxInProgress(operationId));

  @override
  Future<void> markOutboxSynced(
    String operationId, {
    required int clientSeq,
    required String deviceId,
    DateTime? acknowledgedAt,
  }) =>
      _service.runOperation(() => super.markOutboxSynced(
            operationId,
            clientSeq: clientSeq,
            deviceId: deviceId,
            acknowledgedAt: acknowledgedAt,
          ));

  @override
  Future<void> markOutboxRetry(
    String operationId, {
    required int attemptCount,
    required Duration backoff,
    required String error,
    DateTime? now,
  }) =>
      _service.runOperation(() => super.markOutboxRetry(
            operationId,
            attemptCount: attemptCount,
            backoff: backoff,
            error: error,
            now: now,
          ));

  @override
  Future<void> markOutboxPermanentFail(
    String operationId, {
    required String error,
  }) =>
      _service.runOperation(() => super.markOutboxPermanentFail(operationId, error: error));

  @override
  Future<List<OutboxOperation>> getFailedPermanentOperations(String deviceId) =>
      _service.runOperation(() => super.getFailedPermanentOperations(deviceId));

  @override
  Future<void> retryFailedPermanentOperation(String operationId) =>
      _service.runOperation(() => super.retryFailedPermanentOperation(operationId));

  @override
  Future<void> updateAndRetryFailedOperation(
    String operationId, {
    required Map<String, dynamic> correctedPayload,
  }) =>
      _service.runOperation(() => super.updateAndRetryFailedOperation(
            operationId,
            correctedPayload: correctedPayload,
          ));

  @override
  Future<int> recoverStuckInProgressOperations(String deviceId) =>
      _service.runOperation(() => super.recoverStuckInProgressOperations(deviceId));
}
