/// Kalıcı senkronizasyon hatası (`FAILED_PERMANENT`) bulunan Outbox kaleminin
/// sunum katmanı için salt-okunur domain özeti.
class FailedOutboxItem {
  final String operationId;
  final String operationType;
  final int clientSeq;
  final String? lastError;

  const FailedOutboxItem({
    required this.operationId,
    required this.operationType,
    required this.clientSeq,
    this.lastError,
  });

  /// Protokol seviyesi idempotency veya sequence gap hataları doğrudan
  /// yeniden denenemez (`AUD-MED-02`).
  bool get isProtocolConflictNonRetryable {
    final err = lastError;
    if (err == null || err.isEmpty) return false;
    return err.contains('ERR_IDEMPOTENCY_') ||
        err.contains('ERR_CLIENT_SEQ_GAP');
  }
}
