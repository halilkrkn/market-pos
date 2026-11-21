import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/logging/redacting_logger.dart';
import '../../../core/security/client_ecdsa_p256.dart';
import '../../../core/security/secure_token_store.dart';
import '../../../core/security/tls_pinned_client_factory.dart';

class DevicePairingException implements Exception {
  final String code;
  final String message;

  const DevicePairingException(this.code, this.message);

  @override
  String toString() => 'DevicePairingException($code): $message';
}

class DevicePairingResult {
  final String sessionId;
  final String deviceId;
  final String publicKeyFingerprint;
  final String? caCertPem;
  final String? caSha256;
  final bool confirmed;

  const DevicePairingResult({
    required this.sessionId,
    required this.deviceId,
    required this.publicKeyFingerprint,
    this.caCertPem,
    this.caSha256,
    required this.confirmed,
  });
}

/// S-4 Güvenli Cihaz Eşleştirme İstemcisi (Hub Pairing Client).
///
/// ECDSA P-256 anahtar çiftini güvenli depoda saklar,
/// `/api/v1/pairing/request` -> `/poll-challenge` -> `/poll` -> `/ack-challenge` -> `/ack`
/// el sıkışmasını uygular ve alınan ham device token'ı yalnızca [SecureTokenStore]'a yazar.
class DevicePairingClient {
  final SecureTokenStore tokenStore;
  final RedactingLogger logger;
  final http.Client Function({PinnedTlsConfig? tlsOverride}) clientFactory;
  final Future<void> Function(Duration duration) delay;

  DevicePairingClient({
    required this.tokenStore,
    required this.logger,
    http.Client Function({PinnedTlsConfig? tlsOverride})? clientFactory,
    Future<void> Function(Duration duration)? delay,
  })  : clientFactory = clientFactory ?? _defaultClientFactory,
        delay = delay ?? Future<void>.delayed;

  static http.Client _defaultClientFactory({PinnedTlsConfig? tlsOverride}) {
    if (tlsOverride != null) {
      return MmsPinnedTlsClientFactory.createClient(tlsOverride);
    }
    return http.Client();
  }

  static String privateKeyStorageKey(String deviceId) =>
      'ecdsa_p256_priv::$deviceId';

  Future<ClientEcdsaP256KeyPair> getOrCreateKeyPair(String deviceId) async {
    final keyName = privateKeyStorageKey(deviceId);
    final storedHex = await tokenStore.readSecret(keyName);
    if (storedHex != null && storedHex.trim().isNotEmpty) {
      logger.registerSensitiveValue(storedHex);
      return ClientEcdsaP256KeyPair.fromPrivateKeyHex(storedHex);
    }
    final generated = ClientEcdsaP256KeyPair.generate();
    final privHex = generated.toPrivateKeyHex();
    logger.registerSensitiveValue(privHex);
    await tokenStore.saveSecret(keyName, privHex);
    return generated;
  }

  Future<DevicePairingResult> pairDevice({
    required String hubBaseUrl,
    required String sessionId,
    required String pairingSecret,
    required String deviceId,
    required String deviceName,
    required String platformName,
    String? expectedCaSha256,
    String? initialCaPem,
    Duration requestTimeout = const Duration(seconds: 8),
    int maxApprovalRetries = 20,
  }) async {
    logger.registerSensitiveValue(pairingSecret);
    final cleanBaseUrl = hubBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final normalizedPin = expectedCaSha256 == null
        ? null
        : PinnedTlsConfig.normalizeHex(expectedCaSha256);

    final tlsOverride = (normalizedPin != null && normalizedPin.isNotEmpty)
        ? PinnedTlsConfig(
            caCertPem: initialCaPem,
            expectedSha256Hex: normalizedPin,
          )
        : null;

    final client = clientFactory(tlsOverride: tlsOverride);
    try {
      String? resolvedCaPem = initialCaPem;

      // 1. Varsa Hub Kök CA sertifikasını indir ve parmak izini doğrula
      if (resolvedCaPem == null || resolvedCaPem.isEmpty) {
        try {
          final certResp = await client
              .get(Uri.parse('$cleanBaseUrl/api/v1/pairing/ca-cert'))
              .timeout(requestTimeout);
          if (certResp.statusCode == 200 &&
              certResp.body.contains('BEGIN CERTIFICATE')) {
            final ders =
                MmsPinnedTlsClientFactory.extractPemCertificatesDer(certResp.body);
            if (ders.isNotEmpty && normalizedPin != null && normalizedPin.isNotEmpty) {
              final matches = ders.any(
                (der) =>
                    MmsPinnedTlsClientFactory.computeSha256Hex(der) ==
                    normalizedPin,
              );
              if (!matches) {
                throw const DevicePairingException(
                  'CA_PIN_MISMATCH',
                  'Hub CA sertifikasının SHA-256 parmak izi beklenen değerle uyuşmuyor.',
                );
              }
            }
            resolvedCaPem = certResp.body;
          }
        } catch (e) {
          if (e is DevicePairingException) rethrow;
          // ca-cert endpoint opsiyonel/mock ortamlarda olmayabilir; TLS handshake sabitlemesi devam eder.
        }
      }

      // 2. Kalıcı ECDSA P-256 anahtar çifti
      final keyPair = await getOrCreateKeyPair(deviceId);

      // 3. /api/v1/pairing/request
      await _postJson(
        client,
        '$cleanBaseUrl/api/v1/pairing/request',
        <String, dynamic>{
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'device_id': deviceId,
          'name': deviceName,
          'platform': platformName,
          'key_algorithm': 'ECDSA_P256',
          'client_public_key': keyPair.publicKeySpkiBase64,
        },
        timeout: requestTimeout,
        expectedStatuses: const <int>{200, 202},
      );
      logger.info('pairing', 'Eşleştirme talebi gönderildi (session=$sessionId).');

      // 4. /api/v1/pairing/poll-challenge (onay ve rate-limit beklemeli)
      final pollChallenge = await _postWithRetry(
        client,
        '$cleanBaseUrl/api/v1/pairing/poll-challenge',
        <String, dynamic>{
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
        },
        timeout: requestTimeout,
        maxRetries: maxApprovalRetries,
      );

      final pollChallengeId = pollChallenge['poll_challenge_id'] as String?;
      final pollNonceB64 = pollChallenge['poll_challenge_nonce'] as String?;
      if (pollChallengeId == null || pollNonceB64 == null) {
        throw const DevicePairingException(
          'INVALID_POLL_CHALLENGE',
          'Hub geçersiz poll meydan okuması döndürdü.',
        );
      }

      // 5. /api/v1/pairing/poll (Low-S ASN.1 DER imza)
      final pollPayload = keyPair.buildPollPayload(
        sessionId: sessionId,
        challengeId: pollChallengeId,
        challengeNonce: base64Decode(pollNonceB64),
      );
      final pollSig = keyPair.signCanonicalPayload(pollPayload);

      final pollResult = await _postJson(
        client,
        '$cleanBaseUrl/api/v1/pairing/poll',
        <String, dynamic>{
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
          'poll_challenge_id': pollChallengeId,
          'signature': base64Encode(pollSig),
        },
        timeout: requestTimeout,
      );

      final rawToken = pollResult['token'] as String?;
      if (rawToken == null || rawToken.isEmpty) {
        throw const DevicePairingException(
          'MISSING_TOKEN',
          'Hub eşleştirme yanıtında cihaz token bulunamadı.',
        );
      }
      logger.registerSensitiveValue(rawToken);

      // 6. Token'ı hemen güvenli OS deposuna yaz (ACK öncesi dayanıklılık)
      await tokenStore.saveDeviceToken(deviceId, rawToken);

      // 7. /api/v1/pairing/ack-challenge (cooldown 429 beklemeli)
      final ackChallenge = await _postWithRetry(
        client,
        '$cleanBaseUrl/api/v1/pairing/ack-challenge',
        <String, dynamic>{
          'session_id': sessionId,
          'pairing_secret': pairingSecret,
        },
        timeout: requestTimeout,
        maxRetries: maxApprovalRetries,
      );

      final ackChallengeId = ackChallenge['ack_challenge_id'] as String?;
      final ackNonceB64 = ackChallenge['ack_challenge_nonce'] as String?;
      if (ackChallengeId == null || ackNonceB64 == null) {
        throw const DevicePairingException(
          'INVALID_ACK_CHALLENGE',
          'Hub geçersiz ACK meydan okuması döndürdü.',
        );
      }

      // 8. /api/v1/pairing/ack (Token-Bound 7 alanlı imza)
      final ackPayload = keyPair.buildAckPayload(
        sessionId: sessionId,
        challengeId: ackChallengeId,
        challengeNonce: base64Decode(ackNonceB64),
        rawToken: rawToken,
      );
      final ackSig = keyPair.signCanonicalPayload(ackPayload);

      await _postJson(
        client,
        '$cleanBaseUrl/api/v1/pairing/ack',
        <String, dynamic>{
          'session_id': sessionId,
          'ack_challenge_id': ackChallengeId,
          'signature': base64Encode(ackSig),
        },
        timeout: requestTimeout,
      );

      logger.info('pairing', 'Cihaz eşleştirme ACK teyidi tamamlandı.');

      String? computedCaSha = normalizedPin;
      if ((computedCaSha == null || computedCaSha.isEmpty) &&
          resolvedCaPem != null &&
          resolvedCaPem.isNotEmpty) {
        final ders =
            MmsPinnedTlsClientFactory.extractPemCertificatesDer(resolvedCaPem);
        if (ders.isNotEmpty) {
          computedCaSha = MmsPinnedTlsClientFactory.computeSha256Hex(ders.first);
        }
      }

      return DevicePairingResult(
        sessionId: sessionId,
        deviceId: deviceId,
        publicKeyFingerprint: keyPair.publicKeyFingerprintHex,
        caCertPem: resolvedCaPem,
        caSha256: computedCaSha,
        confirmed: true,
      );
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> _postWithRetry(
    http.Client client,
    String url,
    Map<String, dynamic> body, {
    required Duration timeout,
    required int maxRetries,
  }) async {
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      final resp = await client
          .post(
            Uri.parse(url),
            headers: const <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);

      final parsed = _decodeBody(resp.body);
      if (resp.statusCode == 200 || resp.statusCode == 202) {
        return parsed;
      }

      final errorCode = parsed['error']?.toString() ?? 'HTTP_${resp.statusCode}';
      final shouldRetry =
          resp.statusCode == 429 ||
          (resp.statusCode == 403 && errorCode == 'SESSION_NOT_APPROVED');
      if (!shouldRetry || attempt == maxRetries) {
        throw DevicePairingException(
          errorCode,
          parsed['message']?.toString() ??
              'Eşleştirme isteği başarısız oldu (${resp.statusCode}).',
        );
      }

      final retryAfter = (parsed['retry_after_seconds'] as num?)?.toInt() ?? 2;
      await delay(Duration(seconds: retryAfter < 1 ? 1 : retryAfter));
    }

    throw const DevicePairingException(
      'PAIRING_TIMEOUT',
      'Eşleştirme onayı zaman aşımına uğradı.',
    );
  }

  Future<Map<String, dynamic>> _postJson(
    http.Client client,
    String url,
    Map<String, dynamic> body, {
    required Duration timeout,
    Set<int> expectedStatuses = const <int>{200},
  }) async {
    final resp = await client
        .post(
          Uri.parse(url),
          headers: const <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);

    final parsed = _decodeBody(resp.body);
    if (!expectedStatuses.contains(resp.statusCode)) {
      throw DevicePairingException(
        parsed['error']?.toString() ?? 'HTTP_${resp.statusCode}',
        parsed['message']?.toString() ??
            'Eşleştirme adımı reddedildi (${resp.statusCode}).',
      );
    }
    return parsed;
  }

  Map<String, dynamic> _decodeBody(String raw) {
    if (raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return <String, dynamic>{};
  }
}
