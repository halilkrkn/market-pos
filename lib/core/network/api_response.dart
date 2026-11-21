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

  /// Faz 7B: Hub sertifikası sabitlenen parmak iziyle uyuşmuyor (güvenlik hatası).
  factory CentralHealthResponse.tlsPinMismatch({
    required String errorMessage,
    int latencyMs = 0,
  }) {
    return CentralHealthResponse(
      isHealthy: false,
      status: 'TLS_PIN_MISMATCH',
      service: 'UNKNOWN',
      sqliteVersion: 'UNKNOWN',
      latencyMs: latencyMs,
      checkedAt: DateTime.now(),
      errorMessage: errorMessage,
    );
  }

  /// ADR-017: Kök CA doğrulandı ancak SAN/IP, hostname veya geçerlilik tarihi uyuşmuyor.
  factory CentralHealthResponse.tlsCertificateError({
    required String errorMessage,
    int latencyMs = 0,
  }) {
    return CentralHealthResponse(
      isHealthy: false,
      status: 'TLS_CERT_ERROR',
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
      isHealthy:
          json['status'] == 'HEALTHY' ||
          json['status'] == 'OK' ||
          json['status'] == 'UP',
      status: json['status'] as String? ?? 'UNKNOWN',
      service: json['service'] as String? ?? 'UNKNOWN',
      sqliteVersion: json['sqlite_version'] as String? ?? 'UNKNOWN',
      latencyMs: latencyMs,
      checkedAt: DateTime.now(),
    );
  }
}
