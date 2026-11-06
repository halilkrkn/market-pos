/// Merkezi Sunucu Sağlık Durumu Yanıt Modeli
class CentralHealthResponse {
  final bool isHealthy;
  final String status;
  final String service;
  final String sqliteVersion;
  final int latencyMs;
  final DateTime checkedAt;
  final String? errorMessage;

  const CentralHealthResponse({
    required this.isHealthy,
    required this.status,
    required this.service,
    required this.sqliteVersion,
    required this.latencyMs,
    required this.checkedAt,
    this.errorMessage,
  });

  factory CentralHealthResponse.unreachable({
    required String errorMessage,
    int latencyMs = 0,
  }) {
    return CentralHealthResponse(
      isHealthy: false,
      status: 'OFFLINE',
      service: 'UNKNOWN',
      sqliteVersion: 'UNKNOWN',
      latencyMs: latencyMs,
      checkedAt: DateTime.now(),
      errorMessage: errorMessage,
    );
  }

  factory CentralHealthResponse.draining({
    required String errorMessage,
    int latencyMs = 0,
  }) {
    return CentralHealthResponse(
      isHealthy: false,
      status: 'DRAINING',
      service: 'MARKET_MMS_HUB',
      sqliteVersion: 'UNKNOWN',
      latencyMs: latencyMs,
      checkedAt: DateTime.now(),
      errorMessage: errorMessage,
    );
  }

  factory CentralHealthResponse.fromJson(
    Map<String, dynamic> json, {
    required int latencyMs,
  }) {
    return CentralHealthResponse(
      isHealthy: json['status'] == 'HEALTHY' || json['status'] == 'OK',
      status: json['status'] as String? ?? 'UNKNOWN',
      service: json['service'] as String? ?? 'UNKNOWN',
      sqliteVersion: json['sqlite_version'] as String? ?? 'UNKNOWN',
      latencyMs: latencyMs,
      checkedAt: DateTime.now(),
    );
  }
}
