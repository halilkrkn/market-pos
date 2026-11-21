import 'package:meta/meta.dart';

/// Kalıcı Hub bağlantı adresinin hangi kaynaktan elde edildiğini belirtir.
enum HubUrlSource {
  discovered('discovered'),
  lastVerified('last_verified'),
  manual('manual'),
  configured('configured'),
  localhostFallback('localhost_fallback');

  const HubUrlSource(this.storageValue);

  /// Veritabanında saklanan kararlı metin değeri.
  final String storageValue;

  /// Saklanan metin değerini [HubUrlSource] enum değerine çevirir.
  static HubUrlSource? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final normalized = raw.trim().toLowerCase();
    for (final value in HubUrlSource.values) {
      if (value.storageValue == normalized ||
          value.name.toLowerCase() == normalized) {
        return value;
      }
    }
    return null;
  }
}

/// İstemci yerel veritabanında kalıcı olarak saklanan Hub bağlantı kaydı.
@immutable
class StoredHubConnection {
  final String hubUrl;
  final String? hubId;
  final HubUrlSource source;
  final DateTime? lastVerifiedAt;
  final DateTime updatedAt;

  const StoredHubConnection({
    required this.hubUrl,
    this.hubId,
    required this.source,
    this.lastVerifiedAt,
    required this.updatedAt,
  });

  StoredHubConnection copyWith({
    String? hubUrl,
    String? hubId,
    bool clearHubId = false,
    HubUrlSource? source,
    DateTime? lastVerifiedAt,
    bool clearLastVerifiedAt = false,
    DateTime? updatedAt,
  }) {
    return StoredHubConnection(
      hubUrl: hubUrl ?? this.hubUrl,
      hubId: clearHubId ? null : (hubId ?? this.hubId),
      source: source ?? this.source,
      lastVerifiedAt:
          clearLastVerifiedAt ? null : (lastVerifiedAt ?? this.lastVerifiedAt),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is StoredHubConnection &&
            other.hubUrl == hubUrl &&
            other.hubId == hubId &&
            other.source == source &&
            other.lastVerifiedAt == lastVerifiedAt &&
            other.updatedAt == updatedAt);
  }

  @override
  int get hashCode =>
      Object.hash(hubUrl, hubId, source, lastVerifiedAt, updatedAt);

  @override
  String toString() {
    return 'StoredHubConnection(hubUrl: $hubUrl, hubId: $hubId, '
        'source: ${source.storageValue}, lastVerifiedAt: $lastVerifiedAt, '
        'updatedAt: $updatedAt)';
  }
}
