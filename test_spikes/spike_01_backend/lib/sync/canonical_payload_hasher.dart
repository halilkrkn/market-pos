import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Desteklenen Hub receipt/hash doğrulama sonucu.
enum ReceiptHashMatchResult {
  matched,
  mismatched,
  unverifiable,
}

/// MARKET MMS — Versiyonlu, Serileştirme Bağımsız Canonical Payload Hash Sözleşmesi.
///
/// İstemci ve Hub arasında JSON boşlukları veya nesne anahtar sırasından bağımsız
/// deterministik SHA-256 doğrulaması sağlar ve geriye dönük v1 legacy satırlarını
/// tahmin üretmeden (fail-closed) doğrular.
class CanonicalPayloadHasher {
  CanonicalPayloadHasher._();

  static const String hashVersionV2Canonical = 'v2_canonical';
  static const String hashVersionV1Legacy = 'v1_legacy';

  static const Set<String> supportedOperationTypes = {
    'SALE_CREATE',
    'SALE_CANCEL',
    'SALE_REFUND',
    'PRODUCT_UPSERT',
    'STOCK_RECEIPT',
  };

  static final RegExp sha256HexPattern = RegExp(r'^[0-9a-fA-F]{64}$');

  static bool isValidSha256Hex(String? value) {
    if (value == null) return false;
    return sha256HexPattern.hasMatch(value.trim());
  }

  /// `/api/v1/sales` gövdesindeki işlem türünü belirler.
  static String resolveSaleOperationType(Map<String, dynamic> body) {
    final rawType = body['operation_type'];
    if (rawType is String && rawType.isNotEmpty) {
      return rawType;
    }
    if (body.containsKey('refund_id')) {
      return 'SALE_REFUND';
    }
    if (body.containsKey('reason') && !body.containsKey('total_amount')) {
      return 'SALE_CANCEL';
    }
    return 'SALE_CREATE';
  }

  /// JSON değerini deterministik canonical yapıya dönüştürür:
  /// - Map anahtarları leksikografik olarak sıralanır ve değerleri özyinelemeli normalize edilir.
  /// - List eleman sırası korunur, öğeleri özyinelemeli normalize edilir.
  /// - Primitif tipler korunur.
  static dynamic canonicalizeJsonValue(dynamic value) {
    if (value is Map) {
      final sortedKeys = value.keys.map((k) => k.toString()).toList()..sort();
      final result = <String, dynamic>{};
      for (final key in sortedKeys) {
        final rawVal = value.containsKey(key) ? value[key] : null;
        result[key] = canonicalizeJsonValue(rawVal);
      }
      return result;
    }
    if (value is List) {
      return value.map(canonicalizeJsonValue).toList(growable: false);
    }
    return value;
  }

  /// v2_canonical sözleşmesine göre 4 işlem türünün tamamı için SHA-256 hash üretir.
  static String computeCanonicalV2({
    required String operationType,
    required Map<String, dynamic> body,
  }) {
    late final Map<String, dynamic> rawCanonical;

    switch (operationType) {
      case 'SALE_CREATE':
        rawCanonical = <String, dynamic>{
          'hash_version': hashVersionV2Canonical,
          'operation_type': 'SALE_CREATE',
          'client_seq': body['client_seq'],
          'total_amount': body['total_amount'],
          'payment_method': body['payment_method'],
          'items': canonicalizeJsonValue(body['items']),
        };
        break;
      case 'SALE_CANCEL':
        rawCanonical = <String, dynamic>{
          'hash_version': hashVersionV2Canonical,
          'operation_type': 'SALE_CANCEL',
          'client_seq': body['client_seq'],
          'sale_id': body['sale_id'],
          'target_client_seq': body['target_client_seq'],
          'reason': body['reason'],
        };
        break;
      case 'SALE_REFUND':
        rawCanonical = <String, dynamic>{
          'hash_version': hashVersionV2Canonical,
          'operation_type': 'SALE_REFUND',
          'client_seq': body['client_seq'],
          'refund_id': body['refund_id'],
          'sale_id': body['sale_id'],
          'target_client_seq': body['target_client_seq'],
          'total_refund_amount': body['total_refund_amount'],
          'reason': body['reason'],
          'items': canonicalizeJsonValue(body['items']),
        };
        break;
      case 'PRODUCT_UPSERT':
        rawCanonical = <String, dynamic>{
          'hash_version': hashVersionV2Canonical,
          'operation_type': 'PRODUCT_UPSERT',
          'client_seq': body['client_seq'],
          'product': canonicalizeJsonValue(body['product']),
        };
        break;
      case 'STOCK_RECEIPT':
        rawCanonical = <String, dynamic>{
          'hash_version': hashVersionV2Canonical,
          'operation_type': 'STOCK_RECEIPT',
          'client_seq': body['client_seq'],
          'receipt_id': body['receipt_id'],
          'product_id': body['product_id'],
          'quantity': body['quantity'],
          'unit': body['unit'],
          'unit_purchase_price': body['unit_purchase_price'],
          'note': body['note'],
        };
        break;
      default:
        throw ArgumentError('Desteklenmeyen işlem türü: $operationType');
    }

    final normalized = canonicalizeJsonValue(rawCanonical);
    return sha256.convert(utf8.encode(jsonEncode(normalized))).toString();
  }

  /// Legacy v1 `/api/v1/sales` hash sözleşmesi (geriye dönük uyumlu doğrulama).
  static String computeLegacyV1SaleHash(Map<String, dynamic> body) {
    final opType = resolveSaleOperationType(body);

    if (opType == 'SALE_CANCEL') {
      final canonical = {
        'operation_type': 'SALE_CANCEL',
        'client_seq': body['client_seq'],
        'sale_id': body['sale_id'],
        'reason': body['reason'],
      };
      return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
    } else if (opType == 'SALE_REFUND') {
      final canonical = {
        'operation_type': 'SALE_REFUND',
        'client_seq': body['client_seq'],
        'refund_id': body['refund_id'],
        'sale_id': body['sale_id'],
        'total_refund_amount': body['total_refund_amount'],
        'items': body['items'],
      };
      return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
    }

    final canonical = {
      'client_seq': body['client_seq'],
      'total_amount': body['total_amount'],
      'payment_method': body['payment_method'],
      'items': body['items'],
    };
    return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
  }

  /// Legacy v1 `PRODUCT_UPSERT` ham gövde hash hesabı.
  static String computeLegacyV1RawBodyHash(String rawBody) {
    return sha256.convert(utf8.encode(rawBody)).toString();
  }

  /// Saklanan makbuz kaydı ile gelen isteği karşılaştırır.
  ///
  /// Hash eksik veya geçersizse ASLA tahmin yürütmez; `unverifiable` döner.
  static ReceiptHashMatchResult verifyAgainstStoredReceipt({
    required String operationType,
    required Map<String, dynamic> incomingBody,
    required String rawBody,
    required int? storedClientSeq,
    required String? storedOperationType,
    required String? storedRequestHash,
    required String? storedHashVersion,
    required Map<String, dynamic>? cachedResultPayload,
  }) {
    if (storedOperationType != null &&
        storedOperationType.isNotEmpty &&
        storedOperationType != operationType) {
      return ReceiptHashMatchResult.mismatched;
    }

    String? effectiveHash = storedRequestHash;
    String? effectiveVersion = storedHashVersion;

    // Yalnızca henüz v2 kolonları doldurulmamış ham test/legacy eklemelerinde
    // result_payload içindeki __request_hash alanı v1_legacy olarak değerlendirilir.
    if (!isValidSha256Hex(effectiveHash)) {
      final canInspectLegacyPayload = storedClientSeq == null &&
          (storedRequestHash == null || storedRequestHash.trim().isEmpty) &&
          (storedHashVersion == null || storedHashVersion.trim().isEmpty);
      if (canInspectLegacyPayload && cachedResultPayload != null) {
        final payloadHash = cachedResultPayload['__request_hash'] as String?;
        if (isValidSha256Hex(payloadHash)) {
          effectiveHash = payloadHash!.toLowerCase();
          effectiveVersion =
              (cachedResultPayload['__hash_version'] as String?) ??
                  hashVersionV1Legacy;
        }
      }
    }

    if (!isValidSha256Hex(effectiveHash) ||
        effectiveVersion == null ||
        effectiveVersion.trim().isEmpty) {
      return ReceiptHashMatchResult.unverifiable;
    }

    final normalizedStored = effectiveHash!.trim().toLowerCase();

    if (effectiveVersion == hashVersionV2Canonical) {
      if (!supportedOperationTypes.contains(operationType)) {
        return ReceiptHashMatchResult.unverifiable;
      }
      final incomingV2 = computeCanonicalV2(
        operationType: operationType,
        body: incomingBody,
      ).toLowerCase();
      return _constantTimeHexEquals(normalizedStored, incomingV2)
          ? ReceiptHashMatchResult.matched
          : ReceiptHashMatchResult.mismatched;
    }

    if (effectiveVersion == hashVersionV1Legacy) {
      if (operationType == 'PRODUCT_UPSERT') {
        final legacyRaw = computeLegacyV1RawBodyHash(rawBody).toLowerCase();
        if (_constantTimeHexEquals(normalizedStored, legacyRaw)) {
          return ReceiptHashMatchResult.matched;
        }
        // JSON yeniden serileştirilmişse canonical v2 uyumu yoksa v1 mismatch kabul edilir.
        return ReceiptHashMatchResult.mismatched;
      }

      final legacySale = computeLegacyV1SaleHash(incomingBody).toLowerCase();
      return _constantTimeHexEquals(normalizedStored, legacySale)
          ? ReceiptHashMatchResult.matched
          : ReceiptHashMatchResult.mismatched;
    }

    return ReceiptHashMatchResult.unverifiable;
  }

  static bool _constantTimeHexEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
