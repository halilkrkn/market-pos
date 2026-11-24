import 'package:mms_client_storage/mms_client_storage.dart';

/// İstemcinin Merkezi Master Hub ile olan bağlantı çözümleme ve sağlık yaşam döngüsü aşaması.
enum HubConnectionPhase {
  unconfigured,
  discovering,
  verifying,
  connected,
  offline,
  needsDiscovery,
}

/// Manuel Hub adresi bağlantı denemesi sonucu.
class HubManualConnectResult {
  final bool isSuccess;
  final String? normalizedUrl;
  final String message;

  const HubManualConnectResult({
    required this.isSuccess,
    this.normalizedUrl,
    required this.message,
  });
}

/// İstemcinin aktif Hub bağlantı yapılandırması ve durum özeti (saf Dart domain state).
class HubConnectionState {
  final HubConnectionPhase phase;
  final String? activeHubUrl;
  final String? hubId;
  final HubUrlSource? source;
  final DateTime? lastVerifiedAt;
  final DateTime? lastCheckedAt;
  final bool isInitialized;
  final bool isBusy;
  final String? errorMessage;

  const HubConnectionState({
    required this.phase,
    this.activeHubUrl,
    this.hubId,
    this.source,
    this.lastVerifiedAt,
    this.lastCheckedAt,
    this.isInitialized = false,
    this.isBusy = false,
    this.errorMessage,
  });

  const HubConnectionState.initial()
      : phase = HubConnectionPhase.unconfigured,
        activeHubUrl = null,
        hubId = null,
        source = null,
        lastVerifiedAt = null,
        lastCheckedAt = null,
        isInitialized = false,
        isBusy = false,
        errorMessage = null;

  bool get hasActiveHubUrl =>
      activeHubUrl != null && activeHubUrl!.trim().isNotEmpty;

  String? get sourceDisplayLabel => switch (source) {
        HubUrlSource.discovered => 'Otomatik Keşif',
        HubUrlSource.lastVerified => 'Son Doğrulanan',
        HubUrlSource.manual => 'Manuel',
        HubUrlSource.configured => 'Yapılandırma',
        HubUrlSource.localhostFallback => 'Yerel Masaüstü',
        null => null,
      };

  HubConnectionState copyWith({
    HubConnectionPhase? phase,
    String? activeHubUrl,
    bool clearActiveHubUrl = false,
    String? hubId,
    bool clearHubId = false,
    HubUrlSource? source,
    bool clearSource = false,
    DateTime? lastVerifiedAt,
    bool clearLastVerifiedAt = false,
    DateTime? lastCheckedAt,
    bool clearLastCheckedAt = false,
    bool? isInitialized,
    bool? isBusy,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return HubConnectionState(
      phase: phase ?? this.phase,
      activeHubUrl:
          clearActiveHubUrl ? null : (activeHubUrl ?? this.activeHubUrl),
      hubId: clearHubId ? null : (hubId ?? this.hubId),
      source: clearSource ? null : (source ?? this.source),
      lastVerifiedAt:
          clearLastVerifiedAt ? null : (lastVerifiedAt ?? this.lastVerifiedAt),
      lastCheckedAt:
          clearLastCheckedAt ? null : (lastCheckedAt ?? this.lastCheckedAt),
      isInitialized: isInitialized ?? this.isInitialized,
      isBusy: isBusy ?? this.isBusy,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is HubConnectionState &&
            other.phase == phase &&
            other.activeHubUrl == activeHubUrl &&
            other.hubId == hubId &&
            other.source == source &&
            other.lastVerifiedAt == lastVerifiedAt &&
            other.lastCheckedAt == lastCheckedAt &&
            other.isInitialized == isInitialized &&
            other.isBusy == isBusy &&
            other.errorMessage == errorMessage);
  }

  @override
  int get hashCode => Object.hash(
        phase,
        activeHubUrl,
        hubId,
        source,
        lastVerifiedAt,
        lastCheckedAt,
        isInitialized,
        isBusy,
        errorMessage,
      );

  @override
  String toString() {
    return 'HubConnectionState(phase: $phase, activeHubUrl: $activeHubUrl, '
        'hubId: $hubId, source: $source, isInitialized: $isInitialized, '
        'isBusy: $isBusy, errorMessage: $errorMessage)';
  }
}
