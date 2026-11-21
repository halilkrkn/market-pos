import '../sync/tls_errors.dart';

/// Taşıma katmanı hata türü. Faz 7B: TLS pin uyuşmazlığı sıradan ağ hatasından ayrılır.
/// ADR-017: Güvenilen CA altındaki sertifika doğrulama hatası (`tlsCertError`) ayrıca sınıflanır.
enum SyncFailureKind { none, network, tlsHandshake, tlsPinMismatch, tlsCertError }

class SyncResponse {
  final int statusCode;
  final String body;
  final Map<String, String> headers;
  final bool isNetworkError;
  final String? errorMessage;
  final SyncFailureKind failureKind;

  const SyncResponse({
    required this.statusCode,
    required this.body,
    this.headers = const {},
    this.isNetworkError = false,
    this.errorMessage,
    this.failureKind = SyncFailureKind.none,
  });

  bool get isTlsPinMismatch => failureKind == SyncFailureKind.tlsPinMismatch;
  bool get isTlsCertError => failureKind == SyncFailureKind.tlsCertError;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
  bool get isIdempotentReplay => headers['x-mms-idempotent-replay'] == 'true';
  bool get isConflict => statusCode == 409;
  bool get isBadRequest => statusCode == 400;
  bool get isTransientError =>
      isNetworkError ||
      statusCode == 408 ||
      statusCode == 429 ||
      statusCode == 503 ||
      statusCode == 500 ||
      statusCode == 502 ||
      statusCode == 504;

  /// 401 (token geçersiz/iptal), 403 (yetki veya tenant/store uyuşmazlığı) ve
  /// 426 (TLS zorunlu) yanıtları veri hatası değildir; yapılandırma düzeltilince
  /// aynı işlem başarıyla gönderilebilir. Outbox kaydı kalıcı başarısız sayılmaz.
  bool get isAuthOrTransportPolicyHold =>
      statusCode == 401 || statusCode == 403 || statusCode == 426;

  factory SyncResponse.networkError(
    String message, {
    SyncFailureKind kind = SyncFailureKind.network,
  }) {
    return SyncResponse(
      statusCode: 0,
      body: '',
      isNetworkError: true,
      errorMessage: message,
      failureKind: kind,
    );
  }

  factory SyncResponse.tlsPinMismatch(TlsPinMismatchException e) =>
      SyncResponse.networkError(e.message, kind: SyncFailureKind.tlsPinMismatch);

  factory SyncResponse.tlsCertError(TlsCertificateValidationException e) =>
      SyncResponse.networkError(e.message, kind: SyncFailureKind.tlsCertError);
}
