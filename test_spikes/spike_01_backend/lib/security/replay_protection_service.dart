import 'dart:collection';

class ReplayCheckResult {
  final bool accepted;
  final String? code;
  final String? reason;

  const ReplayCheckResult._({
    required this.accepted,
    this.code,
    this.reason,
  });

  const ReplayCheckResult.accepted() : this._(accepted: true);

  const ReplayCheckResult.rejected(String reason, {String code = 'ERR_REPLAY_DETECTED'})
      : this._(accepted: false, code: code, reason: reason);
}

/// Faz B-4: Kritik Hub yedekleme/restore/OAuth/rol değiştirme mutasyonları için
/// `X-MMS-Timestamp` (±300s) ve `X-MMS-Nonce` (600s TTL tek kullanımlık) replay koruması.
class ReplayProtectionService {
  static const Duration defaultMaxClockSkew = Duration(seconds: 300);
  static const Duration defaultNonceTtl = Duration(seconds: 600);
  static const int minNonceLength = 8;
  static const int maxNonceLength = 128;

  final Duration maxClockSkew;
  final Duration nonceTtl;
  final DateTime Function() clock;
  final LinkedHashMap<String, DateTime> _seenNonces = LinkedHashMap<String, DateTime>();

  ReplayProtectionService({
    this.maxClockSkew = defaultMaxClockSkew,
    this.nonceTtl = defaultNonceTtl,
    DateTime Function()? clock,
  }) : clock = clock ?? (() => DateTime.now().toUtc());

  ReplayCheckResult verifyAndConsume({
    required String? timestampHeader,
    required String? nonceHeader,
    String scopeKey = '',
  }) {
    final nowUtc = clock().toUtc();
    _evictExpired(nowUtc);

    final rawTs = timestampHeader?.trim();
    if (rawTs == null || rawTs.isEmpty) {
      return const ReplayCheckResult.rejected(
        'X-MMS-Timestamp başlığı zorunludur.',
      );
    }

    final parsedTs = _parseTimestampUtc(rawTs);
    if (parsedTs == null) {
      return const ReplayCheckResult.rejected(
        'X-MMS-Timestamp geçerli UTC ISO-8601 veya epoch ms formatında olmalıdır.',
      );
    }

    final skew = nowUtc.difference(parsedTs).abs();
    if (skew > maxClockSkew) {
      return ReplayCheckResult.rejected(
        'İstek zaman damgası izin verilen ±${maxClockSkew.inSeconds}s penceresi dışında (fark: ${skew.inSeconds}s).',
      );
    }

    final rawNonce = nonceHeader?.trim();
    if (rawNonce == null ||
        rawNonce.length < minNonceLength ||
        rawNonce.length > maxNonceLength ||
        rawNonce.contains(RegExp(r'\s'))) {
      return const ReplayCheckResult.rejected(
        'X-MMS-Nonce başlığı en az $minNonceLength karakterli benzersiz bir değer olmalıdır.',
      );
    }

    final compositeKey = scopeKey.isEmpty ? rawNonce : '$scopeKey::$rawNonce';
    if (_seenNonces.containsKey(compositeKey)) {
      return const ReplayCheckResult.rejected(
        'Yinelenen X-MMS-Nonce tespit edildi (replay saldırısı engellendi).',
      );
    }

    _seenNonces[compositeKey] = nowUtc.add(nonceTtl);
    return const ReplayCheckResult.accepted();
  }

  void _evictExpired(DateTime nowUtc) {
    while (_seenNonces.isNotEmpty) {
      final firstKey = _seenNonces.keys.first;
      final exp = _seenNonces[firstKey]!;
      if (exp.isAfter(nowUtc)) break;
      _seenNonces.remove(firstKey);
    }
  }

  static DateTime? _parseTimestampUtc(String raw) {
    final asInt = int.tryParse(raw);
    if (asInt != null) {
      if (asInt > 100000000000) {
        return DateTime.fromMillisecondsSinceEpoch(asInt, isUtc: true);
      }
      if (asInt > 1000000000) {
        return DateTime.fromMillisecondsSinceEpoch(asInt * 1000, isUtc: true);
      }
      return null;
    }
    return DateTime.tryParse(raw)?.toUtc();
  }
}
