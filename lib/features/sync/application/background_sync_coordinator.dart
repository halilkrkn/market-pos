import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../domain/sync_coordinator_state.dart';

/// ClientSyncService üretici factory tipi (testlerde mock veya custom parametre enjeksiyonu için)
typedef ClientSyncServiceFactory = ClientSyncService Function({
  required ClientStorageRepository repository,
  required SyncTransport transport,
  required String deviceId,
  required String deviceToken,
  String? Function()? readDeviceToken,
  required String hubUrl,
});

/// MARKET MMS - Windows İstemcisi Arka Plan Senkronizasyon Koordinatörü (Background Sync Coordinator)
///
/// Faz 1.3.1.2 gereksinimleri:
/// - 5 tetikleyici olayı tek senkronizasyon akışında yönetir:
///   1. Başarılı yerel satış (saleCommitted)
///   2. Uygulama ilk açılışı (startup)
///   3. Uygulama arka plandan aktif olduğunda (appResumed)
///   4. Her 30 saniyede bir periyodik sayaç (periodic)
///   5. Ağ/LAN bağlantısı yeniden kurulduğunda (connectivityRestored)
/// - Concurrency ve Deterministic FIFO:
///   - Eşzamanlı çağrıları Future tabanlı Single-Flight Coalescing ile tekilleştirir.
///   - Yürütülen bir senkronizasyon varken gelen çağrılar en fazla 1 ardıl (trailing) senkronizasyon olarak kuyruklanır.
///   - Sıra atlamaz, ClientSyncService'in deterministik FIFO (client_seq ASC) ve FAILED_PERMANENT head-of-line blocking kurallarını korur.
/// - Güvenlik ve Kimlik Doğrulama:
///   - deviceToken eksik veya boşsa Outbox kayıtlarına KESİNLİKLE DOKUNMAZ; `authRequired` durumu döner.
///   - Hub'dan 200/201 ACK gelmeden hiçbir işlem SYNCED yapılamaz.
class BackgroundSyncCoordinator extends StateNotifier<SyncCoordinatorState> {
  static const int maxConsecutiveDrainPasses = 50;

  final ClientStorageRepository repository;
  final SyncTransport transport;
  final String deviceId;
  final String? Function() readDeviceToken;
  final String hubUrl;
  final String? Function()? readHubUrl;
  final bool Function()? isHubUrlReady;
  final bool allowLoopbackHubUrl;
  final ClientSyncServiceFactory? syncServiceFactory;
  final MmsDriveLiveSyncEngine? driveLiveSyncEngine;
  final bool isDriveFallbackStandby;
  final FutureOr<void> Function(SyncBatchResult? result)? onSyncCompleted;
  final FutureOr<void> Function(String failedUrl, String? errorMessage)?
      onHubNetworkUnreachable;
  final Duration periodicInterval;
  final bool autoStartTimer;
  final bool enableLifecycleListener;

  /// Yalnızca test ortamında _executeSyncCycle başlangıcında dış hata enjeksiyonu için
  @visibleForTesting
  final FutureOr<void> Function()? onCycleStart;

  // Single-Flight Coalescing mekanizması değişkenleri
  Completer<SyncBatchResult?>? _activeCompleter;
  Future<SyncBatchResult?>? _activeSyncFuture;
  bool _trailingSyncRequested = false;
  SyncTriggerReason? _trailingReason;
  Completer<SyncBatchResult?>? _trailingCompleter;

  Timer? _periodicTimer;
  AppLifecycleListener? _lifecycleListener;
  bool _isDisposed = false;
  bool _maintenancePaused = false;

  /// Faz 7A: Geri yükleme/bakım sırasında senkronizasyon duraklatıldı mı?
  bool get isPausedForMaintenance => _maintenancePaused;

  BackgroundSyncCoordinator({
    required this.repository,
    required this.transport,
    required this.deviceId,
    required this.readDeviceToken,
    this.hubUrl = '',
    this.readHubUrl,
    this.isHubUrlReady,
    this.allowLoopbackHubUrl = true,
    this.syncServiceFactory,
    this.driveLiveSyncEngine,
    this.isDriveFallbackStandby = false,
    this.onSyncCompleted,
    this.onHubNetworkUnreachable,
    this.periodicInterval = const Duration(seconds: 30),
    this.autoStartTimer = true,
    this.enableLifecycleListener = true,
    @visibleForTesting this.onCycleStart,
  }) : super(SyncCoordinatorState.initial().copyWith(
          driveSyncUiStatus: isDriveFallbackStandby
              ? HybridDriveSyncUiStatus.driveStandby
              : HybridDriveSyncUiStatus.hubPrimary,
        )) {
    _initPeriodicTimer();
    _initLifecycleListener();
  }

  /// Test doğrulamaları için aktif veya ardıl senkronizasyon durumları
  @visibleForTesting
  bool get hasActiveSync => _activeSyncFuture != null;

  @visibleForTesting
  bool get hasTrailingSync => _trailingCompleter != null;

  void _initPeriodicTimer() {
    if (autoStartTimer && periodicInterval > Duration.zero) {
      _periodicTimer = Timer.periodic(periodicInterval, (_) {
        triggerSync(reason: SyncTriggerReason.periodic);
      });
    }
  }

  void _initLifecycleListener() {
    if (enableLifecycleListener) {
      try {
        _lifecycleListener = AppLifecycleListener(
          onResume: () {
            triggerSync(reason: SyncTriggerReason.appResumed);
          },
        );
      } catch (_) {
        // Binding henüz başlatılmamış test ortamlarında sessizce atla
      }
    }
  }

  /// Güvenli token okuyucu: Beklenmeyen depolama/okuma istisnalarını yakalar
  ({String? token, String? readError}) _safeReadToken() {
    try {
      final raw = readDeviceToken();
      final trimmed = raw?.trim();
      return (token: trimmed, readError: null);
    } catch (e) {
      return (token: null, readError: e.toString());
    }
  }

  /// Dinamik Hub adresini güvenli ve tek merkezden çözer.
  ///
  /// [readHubUrl] tanımlıysa onun dönüşü esas alınır ve null/boş değerde asla
  /// statik [hubUrl] fallback'ine düşülmez.
  ({String? url, bool notReady, String? readError}) _safeResolveHubUrl() {
    try {
      if (isHubUrlReady != null && !isHubUrlReady!()) {
        return (url: null, notReady: true, readError: null);
      }
      final raw = readHubUrl != null ? readHubUrl!() : hubUrl;
      final normalized = HubUrlValidator.tryNormalize(
        raw,
        allowLoopback: allowLoopbackHubUrl,
      );
      return (url: normalized, notReady: false, readError: null);
    } catch (e) {
      return (url: null, notReady: false, readError: e.toString());
    }
  }

  void _cancelTrailingRequests() {
    if (_trailingCompleter != null && !_trailingCompleter!.isCompleted) {
      _trailingCompleter!.complete(null);
    }
    _trailingCompleter = null;
    _trailingSyncRequested = false;
    _trailingReason = null;
  }

  /// Senkronizasyonu belirtilen tetikleyici nedeni ile başlatır veya devam eden işleme eklemler (Coalescing).
  Future<SyncBatchResult?> triggerSync({
    SyncTriggerReason reason = SyncTriggerReason.manual,
  }) {
    if (_isDisposed) {
      return Future.value(null);
    }

    // Faz 7A: Restore/bakım sırasında yeni tur başlatılmaz; Outbox'a dokunulmaz.
    if (_maintenancePaused) {
      return Future.value(null);
    }

    // 0. Dinamik Hub Adresi Başlatma ve Geçerlilik Koruması
    final hubCheck = _safeResolveHubUrl();
    if (hubCheck.notReady) {
      _cancelTrailingRequests();
      return Future.value(null);
    }
    if (hubCheck.readError != null || hubCheck.url == null) {
      final isCurrentlySyncing = _activeSyncFuture != null;
      state = state.copyWith(
        status: SyncCoordinatorStatus.networkError,
        isSyncing: isCurrentlySyncing,
        hasPendingTrailingSync: false,
        lastTriggerReason: reason,
        errorMessage: hubCheck.readError != null
            ? 'Hub adresi okunurken hata oluştu: ${hubCheck.readError}'
            : 'Hub adresi henüz yapılandırılmadı veya platform politikasınca engellendi.',
      );
      _cancelTrailingRequests();
      return Future.value(null);
    }

    // 1. Kimlik Doğrulama ve Token Okuma Kontrolü
    final tokenCheck = _safeReadToken();
    if (tokenCheck.readError != null) {
      // Beklenmeyen depolama/okuma hatası: error durumu
      final isCurrentlySyncing = _activeSyncFuture != null;
      state = state.copyWith(
        status: SyncCoordinatorStatus.error,
        isSyncing: isCurrentlySyncing,
        hasPendingTrailingSync: false,
        lastTriggerReason: reason,
        errorMessage:
            'Cihaz yetkilendirme anahtarı okunurken hata oluştu: ${tokenCheck.readError}',
      );
      if (_trailingCompleter != null && !_trailingCompleter!.isCompleted) {
        _trailingCompleter!.complete(null);
      }
      _trailingCompleter = null;
      _trailingSyncRequested = false;
      _trailingReason = null;
      return Future.value(null);
    }

    final token = tokenCheck.token;
    if (token == null || token.isEmpty) {
      // Normal token eksikliği: authRequired durumu
      final isCurrentlySyncing = _activeSyncFuture != null;
      state = state.copyWith(
        status: SyncCoordinatorStatus.authRequired,
        isSyncing: isCurrentlySyncing,
        hasPendingTrailingSync: false,
        lastTriggerReason: reason,
        errorMessage:
            'Cihaz yetkilendirme anahtarı (deviceToken) eksik veya boş. Senkronizasyon için geçerli token gereklidir.',
      );

      // Bekleyen ardıl istek varsa token olmadığı için güvenle iptal et
      if (_trailingCompleter != null && !_trailingCompleter!.isCompleted) {
        _trailingCompleter!.complete(null);
      }
      _trailingCompleter = null;
      _trailingSyncRequested = false;
      _trailingReason = null;
      return Future.value(null);
    }

    // 2. Single-Flight Coalescing: Zaten yürütülmekte olan aktif bir senkronizasyon var mı?
    if (_activeSyncFuture != null) {
      _trailingSyncRequested = true;

      // Öncelikli neden ataması (Satış ve bağlantı kurtarma önceliklidir)
      if (_trailingReason == null ||
          reason == SyncTriggerReason.saleCommitted ||
          reason == SyncTriggerReason.connectivityRestored) {
        _trailingReason = reason;
      }

      state = state.copyWith(hasPendingTrailingSync: true);

      _trailingCompleter ??= Completer<SyncBatchResult?>();
      return _trailingCompleter!.future;
    }

    // 3. Yeni bir senkronizasyon döngüsü başlat
    final completer = Completer<SyncBatchResult?>();
    _activeCompleter = completer;
    final syncFuture = completer.future;
    _activeSyncFuture = syncFuture;

    unawaited(_executeSyncCycle(token, reason, completer).catchError((Object error, StackTrace stack) {
      debugPrint('[BackgroundSyncCoordinator] _executeSyncCycle unhandled error: $error\n$stack');
      if (!_isDisposed) {
        try {
          state = state.copyWith(
            status: SyncCoordinatorStatus.error,
            isSyncing: false,
            errorMessage: 'Senkronizasyon döngüsünde kritik hata: $error',
            hasPendingTrailingSync: false,
          );
        } catch (_) {}
      }
      if (!completer.isCompleted) {
        completer.complete(null);
      }
      if (_trailingCompleter != null && !_trailingCompleter!.isCompleted) {
        _trailingCompleter!.complete(null);
      }
      _trailingCompleter = null;
      _trailingSyncRequested = false;
      _trailingReason = null;
      if (_activeCompleter == completer) {
        _activeCompleter = null;
        _activeSyncFuture = null;
      }
    }));

    return syncFuture;
  }

  Future<void> _executeSyncCycle(
    String token,
    SyncTriggerReason currentReason,
    Completer<SyncBatchResult?> currentCompleter, {
    int consecutiveDrainCount = 0,
  }) async {
    SyncBatchResult? result;

    try {
      if (_isDisposed) {
        if (!currentCompleter.isCompleted) {
          currentCompleter.complete(null);
        }
        return;
      }

      state = state.copyWith(
        status: SyncCoordinatorStatus.syncing,
        isSyncing: true,
        lastTriggerReason: currentReason,
        errorMessage: null,
        hasPendingTrailingSync: _trailingSyncRequested,
      );

      // Dış hata enjeksiyon noktası (Servis/ağ öncesi doğrudan döngü gövdesi exception simülasyonu)
      if (onCycleStart != null) {
        await onCycleStart!();
      }

      String? executionError;
      String? downlinkError;
      String? attemptedHubUrl;
      var downlinkAttempted = false;
      var pulledProductsCount = 0;
      var pulledSalesCount = 0;

      try {
        final cycleHubCheck = _safeResolveHubUrl();
        final effectiveHubUrl = cycleHubCheck.url;
        if (cycleHubCheck.notReady ||
            cycleHubCheck.readError != null ||
            effectiveHubUrl == null) {
          executionError = cycleHubCheck.readError ??
              'Hub adresi henüz yapılandırılmadı veya platform politikasınca engellendi.';
        } else {
          attemptedHubUrl = effectiveHubUrl;
          // 1. Service factory veya constructor oluşturulması try-catch kapsamında
          final ClientSyncService service;
          if (syncServiceFactory != null) {
            service = syncServiceFactory!(
              repository: repository,
              transport: transport,
              deviceId: deviceId,
              deviceToken: token,
              readDeviceToken: readDeviceToken,
              hubUrl: effectiveHubUrl,
            );
          } else {
            service = ClientSyncService(
              repository: repository,
              transport: transport,
              deviceId: deviceId,
              deviceToken: token,
              readDeviceToken: readDeviceToken,
              hubUrl: effectiveHubUrl,
            );
          }

        result = await service.syncPendingOutbox();

        // Faz 7A: Downlink hataları sessizce yutulmaz; durumda raporlanır.
        final downlinkErrors = <String>[];
        downlinkAttempted = true;
        // Merkezi ürün kataloğu snapshot'ını çek ve güncelle
        try {
          pulledProductsCount = await service.syncProducts();
        } catch (prodSyncErr) {
          debugPrint('[BackgroundSyncCoordinator] Ürün kataloğu senkronizasyonu uyarısı: $prodSyncErr');
          downlinkErrors.add('Ürün kataloğu indirilemedi: $prodSyncErr');
        }

        // Satışların çoklu cihaz senkronizasyonu (downlink) çek ve güncelle
        try {
          pulledSalesCount = await service.syncSales();
        } catch (salesSyncErr) {
          debugPrint('[BackgroundSyncCoordinator] Satış senkronizasyonu uyarısı: $salesSyncErr');
          downlinkErrors.add('Satış geçmişi indirilemedi: $salesSyncErr');
        }
        downlinkError = downlinkErrors.isEmpty ? null : downlinkErrors.join(' | ');
        }
      } catch (e, stack) {
        debugPrint('[BackgroundSyncCoordinator] Senkronizasyon yürütme hatası: $e\n$stack');
        executionError = e.toString();
      }

      // EĞER DISPOSE EDİLDİYSE: Arka plandaki işlem asla state değiştirmemeli ve completer'ları tekrar tamamlamamalıdır
      if (_isDisposed) {
        if (!currentCompleter.isCompleted) {
          currentCompleter.complete(result);
        }
        return;
      }

      // Durumu sonuca ve güncel token durumuna göre belirle
      final tokenCheck = _safeReadToken();
      final bool hasTokenReadError = tokenCheck.readError != null;
      final String? currentToken = tokenCheck.token;
      final bool isTokenMissing = currentToken == null || currentToken.isEmpty;

      final bool downlinkPinMismatch =
          downlinkError?.contains('[TLS_PIN_MISMATCH]') == true;
      final bool downlinkCertError =
          downlinkError?.contains('[TLS_CERT_ERROR]') == true;

      final SyncCoordinatorStatus newStatus;
      if (hasTokenReadError) {
        newStatus = SyncCoordinatorStatus.error;
      } else if (isTokenMissing) {
        newStatus = SyncCoordinatorStatus.authRequired;
      } else if (executionError != null) {
        newStatus = SyncCoordinatorStatus.error;
      } else if (result != null) {
        if (result.tlsPinMismatch || downlinkPinMismatch) {
          // Faz 7B: Güvenlik hatası; sıradan ağ hatası gibi gösterilmez.
          newStatus = SyncCoordinatorStatus.tlsPinMismatch;
        } else if (result.tlsCertError || downlinkCertError) {
          // ADR-017: SAN/IP/hostname/tarih doğrulama hatası ayrı sınıflanır.
          newStatus = SyncCoordinatorStatus.tlsCertError;
        } else if (result.permanentFailedCount > 0) {
          newStatus = SyncCoordinatorStatus.permanentError;
        } else if (result.retriedCount > 0) {
          newStatus = SyncCoordinatorStatus.networkError;
        } else {
          newStatus = SyncCoordinatorStatus.idle;
        }
      } else if (downlinkPinMismatch) {
        newStatus = SyncCoordinatorStatus.tlsPinMismatch;
      } else if (downlinkCertError) {
        newStatus = SyncCoordinatorStatus.tlsCertError;
      } else {
        newStatus = SyncCoordinatorStatus.idle;
      }

      final bool isSecurityHold =
          downlinkPinMismatch ||
          downlinkCertError ||
          (result?.tlsPinMismatch == true) ||
          (result?.tlsCertError == true);
      final bool isAuthHold =
          hasTokenReadError ||
          isTokenMissing ||
          (result?.lastError?.contains('Yetki/TLS bekletmesi') == true &&
              !isSecurityHold);
      final bool isDownlinkAuthError =
          downlinkError != null &&
          (downlinkError.contains('401') ||
              downlinkError.contains('403') ||
              downlinkError.contains('426') ||
              downlinkError.contains('Yetki'));
      final bool isDownlinkNetworkError =
          downlinkError != null &&
          !downlinkPinMismatch &&
          !downlinkCertError &&
          !isDownlinkAuthError &&
          (downlinkError.contains('SocketException') ||
              downlinkError.contains('TimeoutException') ||
              downlinkError.contains('ClientException') ||
              downlinkError.contains('Ağ bağlantı hatası') ||
              downlinkError.contains('zaman aşımı'));

      final now = DateTime.now();
      var nextDriveUiStatus = state.driveSyncUiStatus;
      var nextDriveConflictCount = state.driveConflictCount;
      var nextLastDriveSyncTime = state.lastDriveSyncTime;
      var nextLastHubReconciledTime = state.lastHubReconciledTime;

      final engine = driveLiveSyncEngine;
      if (engine != null) {
        final bool hubReachable =
            executionError == null &&
            !isSecurityHold &&
            !isAuthHold &&
            result != null &&
            result.retriedCount == 0 &&
            downlinkError == null;

        if (isSecurityHold || isAuthHold) {
          await engine.recordHubFailure(
            isSecurityHold: isSecurityHold,
            isAuthFailure: isAuthHold,
            isPaused: _maintenancePaused,
          );
          nextDriveUiStatus = HybridDriveSyncUiStatus.hubPrimary;
        } else if (hubReachable) {
          final preLedger = await engine.getLedgerState();
          if (preLedger.driveFallbackActive ||
              preLedger.pendingHubReconciliation) {
            if (!_isDisposed) {
              state = state.copyWith(
                driveSyncUiStatus: HybridDriveSyncUiStatus.hubReconciling,
              );
            }
            final rec = await engine.reconcileWithMasterHub(
              pushOutboxToHub: () async => result!.syncedCount,
              pullProductsFromHub: () async => pulledProductsCount,
              pullSalesFromHub: () async => pulledSalesCount,
              isOutboxEmptyOrAllSynced: () =>
                  result!.retriedCount == 0 && !result.hasMore,
            );
            if (rec.reconciled) {
              nextDriveUiStatus = HybridDriveSyncUiStatus.hubReconciled;
              nextDriveConflictCount = 0;
              nextLastHubReconciledTime = now;
            } else {
              nextDriveUiStatus = HybridDriveSyncUiStatus.hubReconciling;
            }
          } else {
            await engine.recordHubHealthy();
            nextDriveUiStatus = isDriveFallbackStandby
                ? HybridDriveSyncUiStatus.driveStandby
                : HybridDriveSyncUiStatus.hubPrimary;
          }
        } else {
          final afterFail = await engine.recordHubFailure(
            isSecurityHold: false,
            isAuthFailure: false,
            isPaused: _maintenancePaused,
          );
          if (!afterFail.driveFallbackActive) {
            nextDriveUiStatus = HybridDriveSyncUiStatus.hubOfflineConfirmed;
          } else {
            if (!_isDisposed) {
              state = state.copyWith(
                driveSyncUiStatus: HybridDriveSyncUiStatus.driveFallbackActive,
              );
            }
            if (!_isDisposed) {
              state = state.copyWith(
                driveSyncUiStatus: HybridDriveSyncUiStatus.driveSyncing,
              );
            }
            try {
              final driveRes = await engine.runDriveFallbackCycle();
              final postLedger = await engine.getLedgerState();
              nextDriveConflictCount = postLedger.unresolvedConflicts.length;
              if (driveRes.hasErrors) {
                nextDriveUiStatus = HybridDriveSyncUiStatus.driveOfflineError;
              } else if (nextDriveConflictCount > 0 || driveRes.hasConflicts) {
                nextDriveUiStatus =
                    HybridDriveSyncUiStatus.driveConflictDetected;
              } else {
                nextDriveUiStatus = HybridDriveSyncUiStatus.driveSynced;
                nextLastDriveSyncTime = now;
              }
            } catch (e) {
              debugPrint('[BackgroundSyncCoordinator] Drive fallback hatası: $e');
              nextDriveUiStatus = HybridDriveSyncUiStatus.driveOfflineError;
            }
          }
        }
      }

      if (_isDisposed) {
        if (!currentCompleter.isCompleted) {
          currentCompleter.complete(result);
        }
        return;
      }

      state = state.copyWith(
        status: newStatus,
        isSyncing: false,
        lastSyncTime:
            (result != null && result.syncedCount > 0) ? now : state.lastSyncTime,
        lastResult: result,
        errorMessage: hasTokenReadError
            ? 'Cihaz yetkilendirme anahtarı okunurken hata oluştu: ${tokenCheck.readError}'
            : (isTokenMissing
                ? 'Cihaz yetkilendirme anahtarı (deviceToken) eksik veya boş.'
                : (executionError ?? result?.lastError)),
        hasPendingTrailingSync:
            _trailingSyncRequested && !isTokenMissing && !hasTokenReadError,
        downlinkError: downlinkAttempted ? downlinkError : state.downlinkError,
        driveSyncUiStatus: nextDriveUiStatus,
        driveConflictCount: nextDriveConflictCount,
        lastDriveSyncTime: nextLastDriveSyncTime,
        lastHubReconciledTime: nextLastHubReconciledTime,
      );

      // 2. Callback izolasyonu: onSyncCompleted hatası veya gecikmesi coordinator'ı kilitlememelidir
      _dispatchSyncCompletedCallback(result);
      if (attemptedHubUrl != null &&
          !isSecurityHold &&
          !isAuthHold &&
          !isDownlinkAuthError &&
          newStatus != SyncCoordinatorStatus.permanentError &&
          (newStatus == SyncCoordinatorStatus.networkError ||
              isDownlinkNetworkError)) {
        _dispatchHubUnreachableCallback(
          attemptedHubUrl,
          executionError ?? result?.lastError ?? downlinkError,
        );
      }

      // 3. Aktif çağırıcıyı MUTLAKA tamamla
      if (!currentCompleter.isCompleted) {
        currentCompleter.complete(result);
      }

      // 4. Ardıl (Trailing) senkronizasyon kontrolü
      final postCycleHubCheck = _safeResolveHubUrl();
      final isHubMissingOrUnready = postCycleHubCheck.notReady ||
          postCycleHubCheck.readError != null ||
          postCycleHubCheck.url == null;

      if (_trailingSyncRequested && !_isDisposed) {
        _trailingSyncRequested = false;

        // Token veya Hub URL eksikliği varsa ardıl işlemi iptal et
        if (hasTokenReadError || isTokenMissing || isHubMissingOrUnready) {
          final trailing = _trailingCompleter;
          _trailingCompleter = null;
          _trailingReason = null;
          _trailingSyncRequested = false;
          if (_activeCompleter == currentCompleter) {
            _activeCompleter = null;
            _activeSyncFuture = null;
          }
          state = state.copyWith(hasPendingTrailingSync: false);
          if (trailing != null && !trailing.isCompleted) {
            trailing.complete(null);
          }
          return;
        }

        final nextReason = _trailingReason ?? SyncTriggerReason.manual;
        _trailingReason = null;
        final nextCompleter =
            _trailingCompleter ?? Completer<SyncBatchResult?>();
        _trailingCompleter = null;
        _activeCompleter = nextCompleter;
        _activeSyncFuture = nextCompleter.future;

        try {
          await _executeSyncCycle(currentToken, nextReason, nextCompleter);
        } finally {
          if (!nextCompleter.isCompleted) {
            nextCompleter.complete(null);
          }
          if (_activeCompleter == nextCompleter) {
            _activeCompleter = null;
            _activeSyncFuture = null;
          }
        }
      } else if (!hasTokenReadError &&
          !isTokenMissing &&
          !isHubMissingOrUnready &&
          result != null &&
          result.hasMore &&
          result.isCleanSuccess &&
          result.syncedCount > 0 &&
          consecutiveDrainCount < maxConsecutiveDrainPasses &&
          !_maintenancePaused &&
          !_isDisposed) {
        // Birikmiş büyük kuyruklar için kesintisiz ardışık tahliye (Backlog drain)
        // İlerleme ve Token garantisi: Token geçerli olmalı, en az 1 kayıt aktarılmış olmalı ve limit aşılmamalıdır
        final drainCompleter = Completer<SyncBatchResult?>();
        _activeCompleter = drainCompleter;
        _activeSyncFuture = drainCompleter.future;
        try {
          await _executeSyncCycle(
            currentToken, // GÜNCEL TOKEN İLE DEVAM ET!
            currentReason,
            drainCompleter,
            consecutiveDrainCount: consecutiveDrainCount + 1,
          );
        } finally {
          if (!drainCompleter.isCompleted) {
            drainCompleter.complete(null);
          }
          if (_activeCompleter == drainCompleter) {
            _activeCompleter = null;
            _activeSyncFuture = null;
          }
        }
      } else {
        if (_activeCompleter == currentCompleter) {
          _activeCompleter = null;
          _activeSyncFuture = null;
        }
        _trailingCompleter = null;
      }
    } catch (unexpectedError, unexpectedStack) {
      debugPrint(
        '[BackgroundSyncCoordinator] Senkronizasyon döngüsünde kritik beklenmeyen hata: $unexpectedError\n$unexpectedStack',
      );
      if (!_isDisposed) {
        try {
          state = state.copyWith(
            status: SyncCoordinatorStatus.error,
            isSyncing: false,
            errorMessage:
                'Senkronizasyon döngüsünde beklenmeyen hata: $unexpectedError',
            hasPendingTrailingSync: false,
          );
        } catch (_) {}
      }
      if (!currentCompleter.isCompleted) {
        currentCompleter.complete(result);
      }
      if (_trailingCompleter != null && !_trailingCompleter!.isCompleted) {
        _trailingCompleter!.complete(null);
      }
      _trailingCompleter = null;
      _trailingSyncRequested = false;
      _trailingReason = null;
      if (_activeCompleter == currentCompleter) {
        _activeCompleter = null;
        _activeSyncFuture = null;
      }
    }
  }

  void _dispatchIsolatedCallback(
    FutureOr<void> Function() action,
    String callbackName,
  ) {
    try {
      final callbackResult = action();
      if (callbackResult is Future) {
        callbackResult.catchError((Object error, StackTrace stack) {
          debugPrint(
            '[BackgroundSyncCoordinator] $callbackName asenkron hata: $error\n$stack',
          );
        });
      }
    } catch (e, stack) {
      debugPrint(
        '[BackgroundSyncCoordinator] $callbackName senkron hata: $e\n$stack',
      );
    }
  }

  void _dispatchSyncCompletedCallback(SyncBatchResult? result) {
    final cb = onSyncCompleted;
    if (cb == null) return;
    _dispatchIsolatedCallback(() => cb(result), 'onSyncCompleted');
  }

  void _dispatchHubUnreachableCallback(String failedUrl, String? errorMessage) {
    final cb = onHubNetworkUnreachable;
    if (cb == null) return;
    _dispatchIsolatedCallback(
      () => cb(failedUrl, errorMessage),
      'onHubNetworkUnreachable',
    );
  }

  /// Faz 7A — Restore güvenliği: Geri yükleme öncesi çağrılır.
  ///
  /// Yeni senkronizasyon turu başlatılmaz, ardıl istekler iptal edilir ve devam
  /// eden tur (Hub yanıtı + yerel ACK yazımı) tamamlanana kadar beklenir. Böylece
  /// veritabanı duraklatılırken yarıda kalmış bir `IN_PROGRESS`/ACK yazımı oluşmaz.
  Future<void> pauseForMaintenance({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    _maintenancePaused = true;
    _cancelTrailingRequests();
    final active = _activeSyncFuture;
    if (active != null) {
      try {
        await active.timeout(timeout);
      } on TimeoutException {
        debugPrint(
          '[BackgroundSyncCoordinator] Bakım öncesi aktif tur ${timeout.inSeconds}s içinde bitmedi; '
          'duraklatma yine de uygulanıyor (Outbox kaydı RETRY/IN_PROGRESS olarak korunur).',
        );
      }
    }
    if (_isDisposed) return;
    state = state.copyWith(
      status: SyncCoordinatorStatus.paused,
      isSyncing: false,
      hasPendingTrailingSync: false,
      errorMessage: 'Geri yükleme/bakım nedeniyle senkronizasyon geçici olarak duraklatıldı.',
    );
  }

  /// Faz 7A — Restore sonrası senkronizasyonu yeniden etkinleştirir.
  void resumeAfterMaintenance({bool triggerSync = true}) {
    if (!_maintenancePaused) return;
    _maintenancePaused = false;
    if (_isDisposed) return;
    state = state.copyWith(
      status: SyncCoordinatorStatus.idle,
      isSyncing: false,
      errorMessage: null,
    );
    if (triggerSync) {
      this.triggerSync(reason: SyncTriggerReason.manual);
    }
  }

  /// Olay kısayolları (Event Convenience Hooks)
  Future<SyncBatchResult?> onStartup() =>
      triggerSync(reason: SyncTriggerReason.startup);

  Future<SyncBatchResult?> onAppResumed() =>
      triggerSync(reason: SyncTriggerReason.appResumed);

  Future<SyncBatchResult?> onPeriodicTimer() =>
      triggerSync(reason: SyncTriggerReason.periodic);

  Future<SyncBatchResult?> onSaleCommitted() =>
      triggerSync(reason: SyncTriggerReason.saleCommitted);

  Future<SyncBatchResult?> onConnectivityRestored() =>
      triggerSync(reason: SyncTriggerReason.connectivityRestored);

  @override
  void dispose() {
    _isDisposed = true;
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _lifecycleListener?.dispose();
    _lifecycleListener = null;

    // Aktif yürütülmekte olan ağ çağrısının çağırıcı Future'ı ağ yanıtı beklenmeden sonlandırılır
    if (_activeCompleter != null && !_activeCompleter!.isCompleted) {
      _activeCompleter!.complete(null);
    }
    _activeCompleter = null;

    // Bekleyen ardıl Future'lar da sonlandırılır
    if (_trailingCompleter != null && !_trailingCompleter!.isCompleted) {
      _trailingCompleter!.complete(null);
    }
    _trailingCompleter = null;
    _activeSyncFuture = null;

    super.dispose();
  }
}
