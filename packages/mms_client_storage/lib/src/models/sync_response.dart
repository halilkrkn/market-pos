class SyncResponse {
  final int statusCode;
  final String body;
  final Map<String, String> headers;
  final bool isNetworkError;
  final String? errorMessage;

  const SyncResponse({
    required this.statusCode,
    required this.body,
    this.headers = const {},
    this.isNetworkError = false,
    this.errorMessage,
  });

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

  factory SyncResponse.networkError(String message) {
    return SyncResponse(
      statusCode: 0,
      body: '',
      isNetworkError: true,
      errorMessage: message,
    );
  }
}
