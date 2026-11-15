/// MARKET MMS - Senkronizasyon Kuyruğu Durum Özeti (Outbox Status Summary)
///
/// Senkronizasyon kuyruğundaki (outbox_operations) kayıtların durumlarına
/// göre dağılımını ve genel senkronizasyon durumunu gösteren değiştirilemez (immutable) saf Dart sözleşme modeli.
class OutboxSummary {
  /// Gönderilmeyi bekleyen (henüz işleme alınmamış) operasyon sayısı
  final int pending;

  /// Geçici hata alıp exponential backoff beklemesinde olan operasyon sayısı
  final int retry;

  /// Hub API'ye gönderilmekte olan (uçuş halindeki) operasyon sayısı
  final int inProgress;

  /// Kalıcı hata almış ve kuyruğu bloke etmiş (operatör müdahalesi bekleyen) operasyon sayısı
  final int failedPermanent;

  const OutboxSummary({
    required this.pending,
    required this.retry,
    required this.inProgress,
    required this.failedPermanent,
  });

  /// Sıfır sayaçlı boş özet
  const OutboxSummary.empty()
      : pending = 0,
        retry = 0,
        inProgress = 0,
        failedPermanent = 0;

  /// Bu dört durumdaki (PENDING + RETRY + IN_PROGRESS + FAILED_PERMANENT) toplam senkronize edilmemiş işlem sayısı
  int get totalUnsynced => pending + retry + inProgress + failedPermanent;

  /// FAILED_PERMANENT sayısı sıfırdan büyükse true (operatör müdahalesi gerektirir)
  bool get hasErrors => failedPermanent > 0;

  /// Kuyrukta senkronizasyon bekleyen veya işlenmekte olan işlem varsa true (PENDING, RETRY veya IN_PROGRESS)
  bool get hasPendingWork => pending > 0 || retry > 0 || inProgress > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OutboxSummary &&
          runtimeType == other.runtimeType &&
          pending == other.pending &&
          retry == other.retry &&
          inProgress == other.inProgress &&
          failedPermanent == other.failedPermanent;

  @override
  int get hashCode =>
      pending.hashCode ^
      retry.hashCode ^
      inProgress.hashCode ^
      failedPermanent.hashCode;

  @override
  String toString() =>
      'OutboxSummary(pending: $pending, retry: $retry, inProgress: $inProgress, failedPermanent: $failedPermanent, totalUnsynced: $totalUnsynced, hasErrors: $hasErrors, hasPendingWork: $hasPendingWork)';
}
