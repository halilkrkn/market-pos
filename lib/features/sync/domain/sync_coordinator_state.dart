import 'package:mms_client_storage/mms_client_storage.dart';

/// MARKET MMS - Senkronizasyon Koordinatörü Durumları
enum SyncCoordinatorStatus {
  /// Boşta, tetikleme bekliyor
  idle,

  /// Senkronizasyon aktif olarak yürütülüyor
  syncing,

  /// Cihaz yetkilendirme anahtarı (deviceToken) eksik veya boş; senkronizasyon durduruldu
  authRequired,

  /// Ağ veya sunucu bağlantı hatası (geçici hata, backoff devrede)
  networkError,

  /// Kalıcı veri/şema hatası (FAILED_PERMANENT, Head-of-Line blocking)
  permanentError,

  /// Beklenmeyen sistem veya veritabanı hatası
  error,

  /// Faz 7A: Geri yükleme/bakım nedeniyle senkronizasyon bilinçli olarak duraklatıldı
  paused,

  /// Faz 7B: Hub'ın sunduğu TLS sertifikası eşleştirmede sabitlenen parmak iziyle
  /// uyuşmuyor. Sıradan ağ hatası DEĞİLDİR; yeniden eşleştirme/Owner müdahalesi gerekir.
  tlsPinMismatch,

  /// ADR-017: Güvenilen kök CA altındaki sertifika doğrulaması (IP SAN, hostname
  /// veya geçerlilik tarihi) başarısız oldu.
  tlsCertError,
}

/// MARKET MMS - Senkronizasyon Tetikleme Nedenleri
enum SyncTriggerReason {
  /// Manuel / kullanıcı veya test tarafından açıkça tetiklendi
  manual,

  /// Uygulama ilk açılışı (Startup)
  startup,

  /// Uygulama arka plandan ön plana geçtiğinde (App Resumed)
  appResumed,

  /// Periyodik arka plan sayacı (30 saniyede bir)
  periodic,

  /// Başarılı yerel satış sonrası (Sale Committed)
  saleCommitted,

  /// Yeni ürün oluşturma veya güncelleme sonrası (Product Committed)
  productCommitted,

  /// Yerel ağ veya internet bağlantısı yeniden kurulduğunda (Connectivity Restored)
  connectivityRestored,
}

const Object _unset = Object();

/// ADR-021 §6.6: Hibrit Hub + Google Drive Canlı Senkronizasyon 10 UI Durumu.
enum HybridDriveSyncUiStatus {
  hubPrimary('Hub Birincil (Aktif)'),
  hubOfflineConfirmed('Hub Erişilemiyor (Doğrulandı)'),
  driveStandby('Google Drive Yedek Hat (Hazırda Bekliyor)'),
  driveFallbackActive('Google Drive Canlı Senkron Aktif (Fallback)'),
  driveSyncing('Google Drive Senkronize Ediliyor...'),
  driveSynced('Google Drive Güncel (Hub Bekleniyor)'),
  driveOfflineError('Google Drive Bağlantı Hatası'),
  driveConflictDetected('Google Drive Çakışma Tespit Edildi (Hub Bekleniyor)'),
  hubReconciling('Master Hub Döndü — Uzlaştırılıyor...'),
  hubReconciled('Master Hub ile Uzlaştırıldı (Güncel)');

  final String label;
  const HybridDriveSyncUiStatus(this.label);
}

/// MARKET MMS - Arka Plan Senkronizasyon Koordinatörü Durumu (Immutable State)
class SyncCoordinatorState {
  final SyncCoordinatorStatus status;
  final bool isSyncing;
  final SyncTriggerReason? lastTriggerReason;
  final DateTime? lastSyncTime;
  final SyncBatchResult? lastResult;
  final String? errorMessage;
  final bool hasPendingTrailingSync;

  /// Faz 7A: Hub'dan indirme (ürün snapshot / satış downlink) hatası. Uplink başarılı
  /// olsa bile kullanıcıya gösterilir; bir sonraki başarılı indirmede temizlenir.
  final String? downlinkError;

  /// ADR-021: Hibrit Hub / Google Drive canlı senkronizasyon durumu.
  final HybridDriveSyncUiStatus driveSyncUiStatus;
  final int driveConflictCount;
  final DateTime? lastDriveSyncTime;
  final DateTime? lastHubReconciledTime;

  const SyncCoordinatorState({
    required this.status,
    required this.isSyncing,
    this.lastTriggerReason,
    this.lastSyncTime,
    this.lastResult,
    this.errorMessage,
    this.hasPendingTrailingSync = false,
    this.downlinkError,
    this.driveSyncUiStatus = HybridDriveSyncUiStatus.hubPrimary,
    this.driveConflictCount = 0,
    this.lastDriveSyncTime,
    this.lastHubReconciledTime,
  });

  /// Başlangıç durumu
  factory SyncCoordinatorState.initial() {
    return const SyncCoordinatorState(
      status: SyncCoordinatorStatus.idle,
      isSyncing: false,
      lastTriggerReason: null,
      lastSyncTime: null,
      lastResult: null,
      errorMessage: null,
      hasPendingTrailingSync: false,
      driveSyncUiStatus: HybridDriveSyncUiStatus.hubPrimary,
      driveConflictCount: 0,
    );
  }

  SyncCoordinatorState copyWith({
    SyncCoordinatorStatus? status,
    bool? isSyncing,
    Object? lastTriggerReason = _unset,
    Object? lastSyncTime = _unset,
    Object? lastResult = _unset,
    Object? errorMessage = _unset,
    bool? hasPendingTrailingSync,
    Object? downlinkError = _unset,
    HybridDriveSyncUiStatus? driveSyncUiStatus,
    int? driveConflictCount,
    Object? lastDriveSyncTime = _unset,
    Object? lastHubReconciledTime = _unset,
  }) {
    return SyncCoordinatorState(
      status: status ?? this.status,
      isSyncing: isSyncing ?? this.isSyncing,
      lastTriggerReason: identical(lastTriggerReason, _unset)
          ? this.lastTriggerReason
          : lastTriggerReason as SyncTriggerReason?,
      lastSyncTime: identical(lastSyncTime, _unset)
          ? this.lastSyncTime
          : lastSyncTime as DateTime?,
      lastResult: identical(lastResult, _unset)
          ? this.lastResult
          : lastResult as SyncBatchResult?,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      hasPendingTrailingSync:
          hasPendingTrailingSync ?? this.hasPendingTrailingSync,
      downlinkError: identical(downlinkError, _unset)
          ? this.downlinkError
          : downlinkError as String?,
      driveSyncUiStatus: driveSyncUiStatus ?? this.driveSyncUiStatus,
      driveConflictCount: driveConflictCount ?? this.driveConflictCount,
      lastDriveSyncTime: identical(lastDriveSyncTime, _unset)
          ? this.lastDriveSyncTime
          : lastDriveSyncTime as DateTime?,
      lastHubReconciledTime: identical(lastHubReconciledTime, _unset)
          ? this.lastHubReconciledTime
          : lastHubReconciledTime as DateTime?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncCoordinatorState &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          isSyncing == other.isSyncing &&
          lastTriggerReason == other.lastTriggerReason &&
          lastSyncTime == other.lastSyncTime &&
          lastResult == other.lastResult &&
          errorMessage == other.errorMessage &&
          hasPendingTrailingSync == other.hasPendingTrailingSync &&
          downlinkError == other.downlinkError &&
          driveSyncUiStatus == other.driveSyncUiStatus &&
          driveConflictCount == other.driveConflictCount &&
          lastDriveSyncTime == other.lastDriveSyncTime &&
          lastHubReconciledTime == other.lastHubReconciledTime;

  @override
  int get hashCode => Object.hash(
        status,
        isSyncing,
        lastTriggerReason,
        lastSyncTime,
        lastResult,
        errorMessage,
        hasPendingTrailingSync,
        downlinkError,
        driveSyncUiStatus,
        driveConflictCount,
        lastDriveSyncTime,
        lastHubReconciledTime,
      );

  @override
  String toString() {
    return 'SyncCoordinatorState(status: $status, isSyncing: $isSyncing, '
        'lastTriggerReason: $lastTriggerReason, lastSyncTime: $lastSyncTime, '
        'lastResult: $lastResult, errorMessage: $errorMessage, '
        'hasPendingTrailingSync: $hasPendingTrailingSync, downlinkError: $downlinkError, '
        'driveSyncUiStatus: $driveSyncUiStatus, driveConflictCount: $driveConflictCount, '
        'lastDriveSyncTime: $lastDriveSyncTime, lastHubReconciledTime: $lastHubReconciledTime)';
  }
}
