/// MARKET MMS - İstemci API İstisna Tipleri
abstract class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException: $message (Status: $statusCode)';
}

/// Ağ / Bağlantı kurulamadı (Servis kapalı, offline, socket hatası)
class NetworkException extends ApiException {
  const NetworkException(super.message, {super.statusCode});
}

/// Sunucu 503 Draining durumunda (Yedekleme, restore veya kapanma süreci)
class ServiceDrainingException extends ApiException {
  const ServiceDrainingException(super.message, {super.statusCode = 503});
}

/// Kimlik Doğrulama / Yetkilendirme Hatası (401 Unauthorized, 403 Revoked)
class AuthenticationException extends ApiException {
  const AuthenticationException(super.message, {super.statusCode});
}

/// Sunucu İşlem Hatası (400 Bad Request, 409 Conflict, 500 Internal Error)
class ServerResponseException extends ApiException {
  final Map<String, dynamic>? responseData;

  const ServerResponseException(
    super.message, {
    super.statusCode,
    this.responseData,
  });
}
