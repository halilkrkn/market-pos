enum BackendConnectionState { checking, online, offline, draining }

enum LocalDatabaseState { initializing, ready, error }

/// MARKET MMS - Sistem Canlılık ve Tanılama Durumu (State Model)
class SystemStatus {
  final BackendConnectionState backendState;
  final LocalDatabaseState localDbState;
  final String backendUrl;
  final int backendLatencyMs;
  final String backendSqliteVersion;
  final String deviceId;
  final int pendingOutboxCount;
  final int localSalesCount;
  final int localProductsCount;
  final DateTime lastChecked;
  final String? errorMessage;
  final String localDbPath;

  const SystemStatus({
    required this.backendState,
    required this.localDbState,
    required this.backendUrl,
    required this.backendLatencyMs,
    required this.backendSqliteVersion,
    required this.deviceId,
    required this.pendingOutboxCount,
    required this.localSalesCount,
    required this.localProductsCount,
    required this.lastChecked,
    required this.localDbPath,
    this.errorMessage,
  });

  factory SystemStatus.initial({
    String backendUrl = 'http://127.0.0.1:8080',
    String deviceId = 'POS-WIN-01',
    String localDbPath = '',
  }) {
    return SystemStatus(
      backendState: BackendConnectionState.checking,
      localDbState: LocalDatabaseState.initializing,
      backendUrl: backendUrl,
      backendLatencyMs: 0,
      backendSqliteVersion: 'Bilinmiyor',
      deviceId: deviceId,
      pendingOutboxCount: 0,
      localSalesCount: 0,
      localProductsCount: 0,
      lastChecked: DateTime.now(),
      localDbPath: localDbPath,
    );
  }

  SystemStatus copyWith({
    BackendConnectionState? backendState,
    LocalDatabaseState? localDbState,
    String? backendUrl,
    int? backendLatencyMs,
    String? backendSqliteVersion,
    String? deviceId,
    int? pendingOutboxCount,
    int? localSalesCount,
    int? localProductsCount,
    DateTime? lastChecked,
    String? errorMessage,
    String? localDbPath,
  }) {
    return SystemStatus(
      backendState: backendState ?? this.backendState,
      localDbState: localDbState ?? this.localDbState,
      backendUrl: backendUrl ?? this.backendUrl,
      backendLatencyMs: backendLatencyMs ?? this.backendLatencyMs,
      backendSqliteVersion: backendSqliteVersion ?? this.backendSqliteVersion,
      deviceId: deviceId ?? this.deviceId,
      pendingOutboxCount: pendingOutboxCount ?? this.pendingOutboxCount,
      localSalesCount: localSalesCount ?? this.localSalesCount,
      localProductsCount: localProductsCount ?? this.localProductsCount,
      lastChecked: lastChecked ?? this.lastChecked,
      errorMessage: errorMessage,
      localDbPath: localDbPath ?? this.localDbPath,
    );
  }
}
