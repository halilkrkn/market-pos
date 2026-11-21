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

  const SyncCoordinatorState({
    required this.status,
    required this.isSyncing,
    this.lastTriggerReason,
    this.lastSyncTime,
    this.lastResult,
    this.errorMessage,
    this.hasPendingTrailingSync = false,
    this.downlinkError,
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
          downlinkError == other.downlinkError;

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
      );

  @override
  String toString() {
    return 'SyncCoordinatorState(status: $status, isSyncing: $isSyncing, '
        'lastTriggerReason: $lastTriggerReason, lastSyncTime: $lastSyncTime, '
        'lastResult: $lastResult, errorMessage: $errorMessage, '
        'hasPendingTrailingSync: $hasPendingTrailingSync, downlinkError: $downlinkError)';
  }
}
