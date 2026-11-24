import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mms_client_storage/mms_client_storage.dart';

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

enum StagedPairingStage {
  pollReceived('POLL_RECEIVED'),
  ackPending('ACK_PENDING'),
  ackConfirmed('ACK_CONFIRMED');

  final String wireValue;
  const StagedPairingStage(this.wireValue);

  static StagedPairingStage? fromWire(String? raw) {
    for (final s in values) {
      if (s.wireValue == raw) return s;
    }
    return null;
  }
}

class StagedPairingRecord {
  final StagedPairingStage stage;
  final String sessionId;
  final String pairingSecret;
  final String token;
  final String caSha256;
  final String caPem;
  final String hubUrl;
  final String? ackChallengeId;
  final String? ackSignatureB64;
  final DateTime stagedAtUtc;

  const StagedPairingRecord({
    required this.stage,
    required this.sessionId,
    required this.pairingSecret,
    required this.token,
    required this.caSha256,
    required this.caPem,
    required this.hubUrl,
    this.ackChallengeId,
    this.ackSignatureB64,
    required this.stagedAtUtc,
  });

  StagedPairingRecord copyWith({
    StagedPairingStage? stage,
    String? ackChallengeId,
    String? ackSignatureB64,
  }) =>
      StagedPairingRecord(
        stage: stage ?? this.stage,
        sessionId: sessionId,
        pairingSecret: pairingSecret,
        token: token,
        caSha256: caSha256,
        caPem: caPem,
        hubUrl: hubUrl,
        ackChallengeId: ackChallengeId ?? this.ackChallengeId,
        ackSignatureB64: ackSignatureB64 ?? this.ackSignatureB64,
        stagedAtUtc: stagedAtUtc,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'stage': stage.wireValue,
        'session_id': sessionId,
        'pairing_secret': pairingSecret,
        'token': token,
        'ca_sha256': caSha256,
        'ca_pem': caPem,
        'hub_url': hubUrl,
        if (ackChallengeId != null) 'ack_challenge_id': ackChallengeId,
        if (ackSignatureB64 != null) 'ack_signature_b64': ackSignatureB64,
        'staged_at_utc': stagedAtUtc.toUtc().toIso8601String(),
      };

  static StagedPairingRecord? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final d = jsonDecode(raw);
      if (d is! Map) return null;
      final m = Map<String, dynamic>.from(d);
      final stage = StagedPairingStage.fromWire(m['stage'] as String?);
      final sessionId = m['session_id'] as String?;
      final pairingSecret = m['pairing_secret'] as String?;
      final token = m['token'] as String?;
      final caSha256 = m['ca_sha256'] as String?;
      final caPem = m['ca_pem'] as String?;
      final hubUrl = m['hub_url'] as String?;
      if (stage == null ||
          sessionId == null ||
          pairingSecret == null ||
          token == null ||
          caSha256 == null ||
          caPem == null ||
          hubUrl == null) {
        return null;
      }
      return StagedPairingRecord(
        stage: stage,
        sessionId: sessionId,
        pairingSecret: pairingSecret,
        token: token,
        caSha256: caSha256,
        caPem: caPem,
        hubUrl: hubUrl,
        ackChallengeId: m['ack_challenge_id'] as String?,
        ackSignatureB64: m['ack_signature_b64'] as String?,
        stagedAtUtc: DateTime.tryParse(m['staged_at_utc'] as String? ?? '')?.toUtc() ??
            DateTime.now().toUtc(),
      );
    } on FormatException {
      return null;
    }
  }
}

enum StagedPairingReconcileOutcome {
  none,
  rolledBackPreAck,
  reconciledViaAckReplay,
  reconciledViaFreshAckChallenge,
  reconciledViaTokenProbe,
  promotedConfirmed,
  deferredOffline,
}

/// S-4 / P-BLOCK-1 / P-BLOCK-2 Güvenli Cihaz Eşleştirme İstemcisi (Hub Pairing Client).
///
/// - `ALT-BOOT-2` izole bootstrap (`GET /api/v1/pairing/ca-cert`, zero secrets, DIRECT,
///   sıkıştırma/gövde/redirect/mutlak-5s duvar saati limitleri)
/// - Katman 1 + Katman 2 (`MmsX509PreValidator`) + BoringSSL CA-pinned el sıkışması
/// - 4 aşamalı crash-safe `POLL_RECEIVED -> ACK_PENDING -> ACK_CONFIRMED -> P1..P4`
///   re-pairing durum makinesi ve başlangıç uzlaştırması (`reconcileStagedPairingOnStartup`).
class DevicePairingClient {
  static const int maxBootstrapCertBytes = 65536;

  final SecureTokenStore tokenStore;
  final RedactingLogger logger;
  final http.Client Function({PinnedTlsConfig? tlsOverride})? _customClientFactory;
  @visibleForTesting
  final HttpClient Function()? bootstrapRawClientFactory;
  final Future<void> Function(Duration duration) delay;
  final Duration bootstrapTimeout;
  final DateTime Function() nowUtc;

  /// Yalnızca crash-recovery birim testleri için aşama geçişi enjeksiyon kancası.
  @visibleForTesting
  final Future<void> Function(String stage)? onStagePersistedForTest;

  DevicePairingClient({
    required this.tokenStore,
    required this.logger,
    http.Client Function({PinnedTlsConfig? tlsOverride})? clientFactory,
    this.bootstrapRawClientFactory,
    Future<void> Function(Duration duration)? delay,
    this.bootstrapTimeout = const Duration(seconds: 5),
    DateTime Function()? nowUtc,
    @visibleForTesting this.onStagePersistedForTest,
  })  : _customClientFactory = clientFactory,
        delay = delay ?? Future<void>.delayed,
        nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  static String privateKeyStorageKey(String deviceId) =>
      'ecdsa_p256_priv::$deviceId';

  static String stagedPairingStorageKey(String deviceId) =>
      'pairing_staged::$deviceId';

  http.Client _createStrictPhaseCDClient({
    required Uint8List caCertBytes,
    required String expectedCaSha256Hex,
  }) {
    final customFactory = _customClientFactory;
    if (customFactory != null) {
      return customFactory(
        tlsOverride: PinnedTlsConfig(
          caCertPem: encodeDerCertificateAsPem(caCertBytes),
          expectedSha256Hex: expectedCaSha256Hex,
        ),
      );
    }
    return MmsPinnedTlsClientFactory.createStrictCaPinnedClient(
      caCertBytes: caCertBytes,
      expectedCaSha256Hex: expectedCaSha256Hex,
      nowUtc: nowUtc(),
    );
  }

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
    String? payloadCaSha256,
    String? existingPinnedCaSha256,
    bool allowCaChangeOnRepairing = false,
    Future<bool> Function(String oldCaSha256, String newCaSha256)? onConfirmCaChange,
    Future<void> Function(String sha256Hex, String caCertPem)? onPromoteTlsPinning,
    Future<void> Function(String hubUrl)? onPromoteHubUrl,
    Duration requestTimeout = const Duration(seconds: 8),
    int maxApprovalRetries = 20,
  }) async {
    logger.registerSensitiveValue(pairingSecret);
    final cleanBaseUrl = hubBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');

    // --- FAZ A: Sıfır Ağ İsteği Ön-Kontrolleri ---
    final normalizedPin = expectedCaSha256 == null
        ? ''
        : PinnedTlsConfig.normalizeHex(expectedCaSha256);
    if (normalizedPin == 'UNKNOWN' ||
        !RegExp(r'^[0-9A-F]{64}$').hasMatch(normalizedPin)) {
      throw const DevicePairingException(
        'CA_PIN_REQUIRED',
        'Güvenli eşleştirme için Hub kök CA SHA-256 parmak izi (64 hex) zorunludur.',
      );
    }

    final parsedUri = Uri.tryParse(cleanBaseUrl);
    if (parsedUri == null ||
        parsedUri.scheme.toLowerCase() != 'https' ||
        parsedUri.host.isEmpty) {
      throw const DevicePairingException(
        'TLS_SCHEME_REQUIRED',
        'TLS sabitlemesi etkinken şifresiz HTTP kullanılamaz; yalnızca https:// Hub adresi desteklenir.',
      );
    }

    if (payloadCaSha256 != null && payloadCaSha256.trim().isNotEmpty) {
      final normPayload = PinnedTlsConfig.normalizeHex(payloadCaSha256);
      if (normPayload == 'UNKNOWN' ||
          !constantTimeEqualsAscii(normPayload, normalizedPin)) {
        throw const DevicePairingException(
          'OOB_FINGERPRINT_MISMATCH',
          'QR/yük içindeki CA parmak izi doğrulanan Hub CA parmak iziyle uyuşmuyor.',
        );
      }
    }

    if (existingPinnedCaSha256 != null && existingPinnedCaSha256.trim().isNotEmpty) {
      final normExisting = PinnedTlsConfig.normalizeHex(existingPinnedCaSha256);
      if (normExisting.isNotEmpty && !constantTimeEqualsAscii(normExisting, normalizedPin)) {
        final confirmedChange = allowCaChangeOnRepairing ||
            (onConfirmCaChange != null &&
                await onConfirmCaChange(normExisting, normalizedPin));
        if (!confirmedChange) {
          throw const DevicePairingException(
            'REPAIRING_CA_CHANGE_CONFIRMATION_REQUIRED',
            'Mevcut sabitlenmiş Kök CA farklı. Re-pairing ile CA değiştirmek için açık kullanıcı onayı gereklidir.',
          );
        }
      }
    }

    // --- FAZ B: Root CA Elde Etme & Çift Katmanlı X.509v3 Doğrulaması ---
    final CanonicalCertDerResult canonicalCa;
    if (initialCaPem != null && initialCaPem.trim().isNotEmpty) {
      try {
        canonicalCa = extractCanonicalSingleCertDer(
          Uint8List.fromList(utf8.encode(initialCaPem)),
        );
        if (!constantTimeEqualsAscii(canonicalCa.sha256Hex, normalizedPin)) {
          throw const DevicePairingException(
            'CA_PIN_MISMATCH',
            'Sağlanan Hub CA sertifikasının SHA-256 parmak izi beklenen değerle uyuşmuyor.',
          );
        }
        MmsX509PreValidator.validateRootCaDer(
          canonicalCa.derBytes,
          nowUtc: nowUtc(),
        );
      } on X509ValidationException catch (e) {
        throw DevicePairingException(e.code, e.message);
      }
    } else {
      canonicalCa = await _fetchAndVerifyBootstrapCaCert(
        parsedHubBaseUri: parsedUri,
        expectedPinHex: normalizedPin,
      );
    }

    final canonicalCaPem = canonicalCa.toPem();

    // --- FAZ C: Katı CA-Pinned TLS İstemcisi (badCertificateCallback => false) ---
    final client = _createStrictPhaseCDClient(
      caCertBytes: canonicalCa.derBytes,
      expectedCaSha256Hex: normalizedPin,
    );

    final stagedKey = stagedPairingStorageKey(deviceId);
    try {
      final keyPair = await getOrCreateKeyPair(deviceId);

      // /api/v1/pairing/request
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

      // /api/v1/pairing/poll-challenge
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

      // /api/v1/pairing/poll
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

      // --- FAZ D / Aşama 1: POLL_RECEIVED (eski aktif device_token/pin/URL korunur!) ---
      var staged = StagedPairingRecord(
        stage: StagedPairingStage.pollReceived,
        sessionId: sessionId,
        pairingSecret: pairingSecret,
        token: rawToken,
        caSha256: normalizedPin,
        caPem: canonicalCaPem,
        hubUrl: cleanBaseUrl,
        stagedAtUtc: nowUtc(),
      );
      await tokenStore.saveSecret(stagedKey, jsonEncode(staged.toJson()));
      if (onStagePersistedForTest != null) {
        await onStagePersistedForTest!(staged.stage.wireValue);
      }

      try {
        // /api/v1/pairing/ack-challenge
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

        // 7-alanlı Token-Bound ACK imza çerçevesi
        final ackPayload = keyPair.buildAckPayload(
          sessionId: sessionId,
          challengeId: ackChallengeId,
          challengeNonce: base64Decode(ackNonceB64),
          rawToken: rawToken,
        );
        final ackSig = keyPair.signCanonicalPayload(ackPayload);
        final ackSigB64 = base64Encode(ackSig);

        // --- FAZ D / Aşama 2: ACK_PENDING (HTTP /ack gönderilmeden HEMEN ÖNCE kalıcı yazım!) ---
        staged = staged.copyWith(
          stage: StagedPairingStage.ackPending,
          ackChallengeId: ackChallengeId,
          ackSignatureB64: ackSigB64,
        );
        await tokenStore.saveSecret(stagedKey, jsonEncode(staged.toJson()));
        if (onStagePersistedForTest != null) {
          await onStagePersistedForTest!(staged.stage.wireValue);
        }

        // HTTP /ack isteği
        await _postJson(
          client,
          '$cleanBaseUrl/api/v1/pairing/ack',
          <String, dynamic>{
            'session_id': sessionId,
            'ack_challenge_id': ackChallengeId,
            'signature': ackSigB64,
          },
          timeout: requestTimeout,
        );

        // --- FAZ D / Aşama 3: ACK_CONFIRMED ---
        staged = staged.copyWith(stage: StagedPairingStage.ackConfirmed);
        await tokenStore.saveSecret(stagedKey, jsonEncode(staged.toJson()));
        if (onStagePersistedForTest != null) {
          await onStagePersistedForTest!(staged.stage.wireValue);
        }

        // --- FAZ D / Aşama 4: P1..P4 İdempotent Terfi ---
        await _promoteConfirmedStaging(
          deviceId: deviceId,
          staged: staged,
          onPromoteTlsPinning: onPromoteTlsPinning,
          onPromoteHubUrl: onPromoteHubUrl,
        );
      } on DevicePairingException catch (e) {
        // Kesin red (ACK öncesi) geldiyse ve stage hâlâ pollReceived ise temizle;
        // ACK_PENDING sırasında belirsiz/ağ hatasında kayıt reconciliation için korunur.
        final currentRaw = await tokenStore.readSecret(stagedKey);
        final current = StagedPairingRecord.tryParse(currentRaw);
        if (current?.stage == StagedPairingStage.pollReceived) {
          await tokenStore.deleteSecret(stagedKey);
        } else if (current?.stage == StagedPairingStage.ackPending &&
            (e.code == 'INVALID_ACK_TOKEN_HASH_SIGNATURE' ||
                e.code == 'SESSION_LOCKED')) {
          await tokenStore.deleteSecret(stagedKey);
        }
        rethrow;
      }

      logger.info('pairing', 'Cihaz eşleştirme ACK teyidi ve terfisi tamamlandı.');

      return DevicePairingResult(
        sessionId: sessionId,
        deviceId: deviceId,
        publicKeyFingerprint: keyPair.publicKeyFingerprintHex,
        caCertPem: canonicalCaPem,
        caSha256: normalizedPin,
        confirmed: true,
      );
    } finally {
      client.close();
    }
  }

  Future<void> _promoteConfirmedStaging({
    required String deviceId,
    required StagedPairingRecord staged,
    Future<void> Function(String sha256Hex, String caCertPem)? onPromoteTlsPinning,
    Future<void> Function(String hubUrl)? onPromoteHubUrl,
  }) async {
    // P1: Device Token -> SecureTokenStore
    await tokenStore.saveDeviceToken(deviceId, staged.token);
    if (onStagePersistedForTest != null) {
      await onStagePersistedForTest!('P1');
    }

    // P2: Pinned CA SHA-256 + PEM -> AppSetupConfig
    if (onPromoteTlsPinning != null) {
      await onPromoteTlsPinning(staged.caSha256, staged.caPem);
    }
    if (onStagePersistedForTest != null) {
      await onStagePersistedForTest!('P2');
    }

    // P3: Active Hub URL
    if (onPromoteHubUrl != null) {
      await onPromoteHubUrl(staged.hubUrl);
    }
    if (onStagePersistedForTest != null) {
      await onStagePersistedForTest!('P3');
    }

    // P4: Staging kaydını temizle
    await tokenStore.deleteSecret(stagedPairingStorageKey(deviceId));
  }

  /// Crash-Safe Re-pairing Başlangıç Uzlaştırması (`P-BLOCK-2` / `DEC-REV-3`).
  ///
  /// Uygulama açılışında senkronizasyon başlamadan önce çağrılır.
  /// `outbox_operations`, `client_seq`, `device_id`, `tenant_id` ve `store_id` alanlarına
  /// KESİNLİKLE DOKUNMAZ.
  Future<StagedPairingReconcileOutcome> reconcileStagedPairingOnStartup({
    required String deviceId,
    Future<void> Function(String sha256Hex, String caCertPem)? onPromoteTlsPinning,
    Future<void> Function(String hubUrl)? onPromoteHubUrl,
    Duration requestTimeout = const Duration(seconds: 6),
  }) async {
    final stagedKey = stagedPairingStorageKey(deviceId);
    final raw = await tokenStore.readSecret(stagedKey);
    final staged = StagedPairingRecord.tryParse(raw);
    if (staged == null) {
      if (raw != null) {
        await tokenStore.deleteSecret(stagedKey);
      }
      return StagedPairingReconcileOutcome.none;
    }
    logger.registerSensitiveValue(staged.token);
    logger.registerSensitiveValue(staged.pairingSecret);

    if (staged.stage == StagedPairingStage.pollReceived) {
      await tokenStore.deleteSecret(stagedKey);
      return StagedPairingReconcileOutcome.rolledBackPreAck;
    }

    if (staged.stage == StagedPairingStage.ackConfirmed) {
      await _promoteConfirmedStaging(
        deviceId: deviceId,
        staged: staged,
        onPromoteTlsPinning: onPromoteTlsPinning,
        onPromoteHubUrl: onPromoteHubUrl,
      );
      return StagedPairingReconcileOutcome.promotedConfirmed;
    }

    // stage == ackPending
    final CanonicalCertDerResult canonicalCa;
    try {
      canonicalCa = extractCanonicalSingleCertDer(
        Uint8List.fromList(utf8.encode(staged.caPem)),
      );
      if (!constantTimeEqualsAscii(
        canonicalCa.sha256Hex,
        PinnedTlsConfig.normalizeHex(staged.caSha256),
      )) {
        await tokenStore.deleteSecret(stagedKey);
        return StagedPairingReconcileOutcome.rolledBackPreAck;
      }
      MmsX509PreValidator.validateRootCaDer(canonicalCa.derBytes, nowUtc: nowUtc());
    } on X509ValidationException {
      await tokenStore.deleteSecret(stagedKey);
      return StagedPairingReconcileOutcome.rolledBackPreAck;
    }

    final client = _createStrictPhaseCDClient(
      caCertBytes: canonicalCa.derBytes,
      expectedCaSha256Hex: PinnedTlsConfig.normalizeHex(staged.caSha256),
    );
    try {
      final cleanBase = staged.hubUrl.trim().replaceAll(RegExp(r'/+$'), '');
      var sessionGone = false;

      // 1. Önce kayıtlı (session_id, ack_challenge_id, ack_signature_b64) ile idempotent /ack dene
      if (staged.ackChallengeId != null && staged.ackSignatureB64 != null) {
        try {
          await _postJson(
            client,
            '$cleanBase/api/v1/pairing/ack',
            <String, dynamic>{
              'session_id': staged.sessionId,
              'ack_challenge_id': staged.ackChallengeId,
              'signature': staged.ackSignatureB64,
            },
            timeout: requestTimeout,
          );
          final confirmed = staged.copyWith(stage: StagedPairingStage.ackConfirmed);
          await tokenStore.saveSecret(stagedKey, jsonEncode(confirmed.toJson()));
          await _promoteConfirmedStaging(
            deviceId: deviceId,
            staged: confirmed,
            onPromoteTlsPinning: onPromoteTlsPinning,
            onPromoteHubUrl: onPromoteHubUrl,
          );
          return StagedPairingReconcileOutcome.reconciledViaAckReplay;
        } on DevicePairingException catch (e) {
          if (e.code == 'SESSION_NOT_FOUND' || e.code == 'SESSION_EXPIRED') {
            sessionGone = true;
          } else if (e.code == 'INVALID_ACK_TOKEN_HASH_SIGNATURE' ||
              e.code == 'SESSION_LOCKED') {
            await tokenStore.deleteSecret(stagedKey);
            return StagedPairingReconcileOutcome.rolledBackPreAck;
          }
          // CHALLENGE_EXPIRED / CHALLENGE_NOT_FOUND -> Adım 2 yeni challenge dener
        } on Exception {
          // Ağ / Timeout / SocketException -> Offline korunur, eski kimlik bozulmaz!
          return StagedPairingReconcileOutcome.deferredOffline;
        }
      }

      // 2. Oturum hâlâ hayatta ise yeni /ack-challenge + /ack dene
      if (!sessionGone) {
        try {
          final ackCh = await _postJson(
            client,
            '$cleanBase/api/v1/pairing/ack-challenge',
            <String, dynamic>{
              'session_id': staged.sessionId,
              'pairing_secret': staged.pairingSecret,
            },
            timeout: requestTimeout,
          );
          final ackChId = ackCh['ack_challenge_id'] as String?;
          final ackNonceB64 = ackCh['ack_challenge_nonce'] as String?;
          if (ackChId != null && ackNonceB64 != null) {
            final keyPair = await getOrCreateKeyPair(deviceId);
            final ackPayload = keyPair.buildAckPayload(
              sessionId: staged.sessionId,
              challengeId: ackChId,
              challengeNonce: base64Decode(ackNonceB64),
              rawToken: staged.token,
            );
            final ackSigB64 = base64Encode(keyPair.signCanonicalPayload(ackPayload));
            await _postJson(
              client,
              '$cleanBase/api/v1/pairing/ack',
              <String, dynamic>{
                'session_id': staged.sessionId,
                'ack_challenge_id': ackChId,
                'signature': ackSigB64,
              },
              timeout: requestTimeout,
            );
            final confirmed = staged.copyWith(
              stage: StagedPairingStage.ackConfirmed,
              ackChallengeId: ackChId,
              ackSignatureB64: ackSigB64,
            );
            await tokenStore.saveSecret(stagedKey, jsonEncode(confirmed.toJson()));
            await _promoteConfirmedStaging(
              deviceId: deviceId,
              staged: confirmed,
              onPromoteTlsPinning: onPromoteTlsPinning,
              onPromoteHubUrl: onPromoteHubUrl,
            );
            return StagedPairingReconcileOutcome.reconciledViaFreshAckChallenge;
          }
        } on DevicePairingException catch (e) {
          if (e.code == 'SESSION_NOT_FOUND' || e.code == 'SESSION_EXPIRED') {
            sessionGone = true;
          } else {
            return StagedPairingReconcileOutcome.deferredOffline;
          }
        } on Exception {
          return StagedPairingReconcileOutcome.deferredOffline;
        }
      }

      // 3. Oturum TTL dolmuş veya Hub yeniden başlamışsa: Bearer <staged.token> yoklaması
      try {
        final probeResp = await client
            .get(
              Uri.parse('$cleanBase/api/v1/products?limit=1'),
              headers: <String, String>{
                'authorization': 'Bearer ${staged.token}',
                'accept': 'application/json',
              },
            )
            .timeout(requestTimeout);
        if (probeResp.statusCode == 200) {
          final confirmed = staged.copyWith(stage: StagedPairingStage.ackConfirmed);
          await tokenStore.saveSecret(stagedKey, jsonEncode(confirmed.toJson()));
          await _promoteConfirmedStaging(
            deviceId: deviceId,
            staged: confirmed,
            onPromoteTlsPinning: onPromoteTlsPinning,
            onPromoteHubUrl: onPromoteHubUrl,
          );
          return StagedPairingReconcileOutcome.reconciledViaTokenProbe;
        }
        if (probeResp.statusCode == 401 || probeResp.statusCode == 403) {
          await tokenStore.deleteSecret(stagedKey);
          return StagedPairingReconcileOutcome.rolledBackPreAck;
        }
        return StagedPairingReconcileOutcome.deferredOffline;
      } on Exception {
        return StagedPairingReconcileOutcome.deferredOffline;
      }
    } finally {
      client.close();
    }
  }

  /// `ALT-BOOT-2` İzole HTTPS Bootstrap İstemcisi (`B-CB-1..6`, 0 sır, DIRECT,
  /// sıkıştırma/gövde/redirect/mutlak-5s duvar saati limitleri).
  Future<CanonicalCertDerResult> _fetchAndVerifyBootstrapCaCert({
    required Uri parsedHubBaseUri,
    required String expectedPinHex,
  }) async {
    final targetUri = parsedHubBaseUri.replace(
      path: '/api/v1/pairing/ca-cert',
      query: null,
      fragment: null,
    );
    final effectivePort = targetUri.hasPort ? targetUri.port : 443;

    final rawBootstrapFactory = bootstrapRawClientFactory;
    final bootstrapClient = rawBootstrapFactory != null
        ? rawBootstrapFactory()
        : HttpClient(context: SecurityContext(withTrustedRoots: false));

    Uint8List? capturedLeafDer;
    var callbackCount = 0;
    StreamSubscription<List<int>>? sub;
    Timer? wallClockTimer;

    try {
      bootstrapClient.findProxy = (_) => 'DIRECT';
      bootstrapClient.autoUncompress = false;
      bootstrapClient.connectionTimeout = bootstrapTimeout;
      bootstrapClient.idleTimeout = Duration.zero;
      bootstrapClient.badCertificateCallback = (
        X509Certificate cert,
        String host,
        int port,
      ) {
        // B-CB-1 & B-CB-2: Yalnızca hedef host ve port
        if (host != targetUri.host || port != effectivePort) {
          return false;
        }
        // B-CB-6: Tek seferlik callback izni
        callbackCount++;
        if (callbackCount != 1) {
          return false;
        }
        // B-CB-4: Yaprak sertifika geçerlilik tarih penceresi
        final now = nowUtc();
        if (now.isBefore(cert.startValidity.toUtc()) ||
            now.isAfter(cert.endValidity.toUtc())) {
          return false;
        }
        final der = cert.der;
        if (der.length < 4 || der.length > maxBootstrapCertBytes) {
          return false;
        }
        // B-CB-5 için yaprak sertifikayı yakala
        capturedLeafDer = Uint8List.fromList(der);
        return true;
      };

      final HttpClientRequest request;
      try {
        request = await bootstrapClient.getUrl(targetUri).timeout(bootstrapTimeout);
      } on TimeoutException {
        throw const DevicePairingException(
          'BOOTSTRAP_TIMEOUT',
          'Hub Kök CA indirme bağlantısı zaman aşımına uğradı.',
        );
      }

      // Redirect, keep-alive, sıkıştırma ve gizli/token başlığı yasakları
      request.followRedirects = false;
      request.maxRedirects = 0;
      request.persistentConnection = false;
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      request.headers.set(HttpHeaders.connectionHeader, 'close');

      final HttpClientResponse response;
      try {
        response = await request.close().timeout(bootstrapTimeout);
      } on TimeoutException {
        throw const DevicePairingException(
          'BOOTSTRAP_TIMEOUT',
          'Hub Kök CA yanıt başlığı zaman aşımına uğradı.',
        );
      }

      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw DevicePairingException(
          'BOOTSTRAP_REDIRECT_FORBIDDEN',
          'Bootstrap uç noktası HTTP yönlendirmesi (${response.statusCode}) yapamaz.',
        );
      }
      if (response.statusCode != 200) {
        throw DevicePairingException(
          'BOOTSTRAP_FETCH_FAILED',
          'Hub Kök CA sertifikası indirilemedi (HTTP ${response.statusCode}).',
        );
      }

      final contentEncodings = response.headers[HttpHeaders.contentEncodingHeader];
      if (contentEncodings != null &&
          contentEncodings.any((v) => v.trim().toLowerCase() != 'identity')) {
        throw const DevicePairingException(
          'INVALID_CA_CERT',
          'Bootstrap yanıtında sıkıştırılmış HTTP gövdesi reddedildi.',
        );
      }

      final declaredLen = response.contentLength;
      if (declaredLen == 0 || declaredLen < -1 || declaredLen > maxBootstrapCertBytes) {
        throw DevicePairingException(
          'INVALID_CA_CERT',
          'Bootstrap Content-Length sınırı geçersiz ($declaredLen bayt).',
        );
      }

      // Mutlak (sıfırlanmayan) duvar saati body timeout'u (Slowloris koruması)
      final completer = Completer<Uint8List>();
      final builder = BytesBuilder(copy: false);
      var totalBytes = 0;

      void failWith(DevicePairingException err) {
        if (!completer.isCompleted) {
          completer.completeError(err);
        }
      }

      wallClockTimer = Timer(bootstrapTimeout, () {
        sub?.cancel();
        failWith(
          const DevicePairingException(
            'BOOTSTRAP_TIMEOUT',
            'Hub Kök CA indirme akışı mutlak zaman aşımı süresini aştı.',
          ),
        );
      });

      sub = response.listen(
        (chunk) {
          totalBytes += chunk.length;
          if (totalBytes > maxBootstrapCertBytes) {
            sub?.cancel();
            failWith(
              const DevicePairingException(
                'INVALID_CA_CERT',
                'Hub Kök CA sertifikası azami 64 KB (65.536 bayt) sınırını aştı.',
              ),
            );
            return;
          }
          if (declaredLen > 0 && totalBytes > declaredLen) {
            sub?.cancel();
            failWith(
              const DevicePairingException(
                'INVALID_CA_CERT',
                'Hub Kök CA yanıtı bildirilen Content-Length uzunluğunu aştı.',
              ),
            );
            return;
          }
          builder.add(chunk);
        },
        onError: (Object err) {
          if (!completer.isCompleted) {
            if (err is HttpException &&
                (declaredLen > 0 ||
                    err.message.toLowerCase().contains('content') ||
                    err.message.toLowerCase().contains('chunked'))) {
              completer.completeError(
                DevicePairingException(
                  'INVALID_CA_CERT',
                  'Hub Kök CA HTTP gövdesi çelişkili veya kesik (${err.message}).',
                ),
              );
              return;
            }
            completer.completeError(
              DevicePairingException(
                'BOOTSTRAP_FETCH_FAILED',
                'Hub Kök CA okunurken hata: ${err.runtimeType}',
              ),
            );
          }
        },
        onDone: () {
          if (totalBytes == 0 || (declaredLen >= 0 && totalBytes != declaredLen)) {
            failWith(
              const DevicePairingException(
                'INVALID_CA_CERT',
                'Hub Kök CA yanıt uzunluğu beklenen Content-Length ile uyuşmuyor veya boş.',
              ),
            );
            return;
          }
          if (!completer.isCompleted) {
            completer.complete(builder.takeBytes());
          }
        },
        cancelOnError: true,
      );

      final Uint8List downloadedBytes = await completer.future;

      // Katman 1: UTF-8'den bağımsız canonical tek-sertifika DER çıkarımı + OOB pin doğrulama
      final CanonicalCertDerResult canonical;
      try {
        canonical = extractCanonicalSingleCertDer(downloadedBytes);
      } on X509ValidationException catch (e) {
        throw DevicePairingException(e.code, e.message);
      }

      if (!constantTimeEqualsAscii(canonical.sha256Hex, expectedPinHex)) {
        throw const DevicePairingException(
          'CA_PIN_MISMATCH',
          'İndirilen Hub Kök CA sertifikasının SHA-256 parmak izi OOB değerle uyuşmuyor.',
        );
      }

      // Katman 2: Dar kapsamlı X.509v3 Root CA yapı/tarih/CA:TRUE/keyCertSign ön-kontrolü
      try {
        MmsX509PreValidator.validateRootCaDer(
          canonical.derBytes,
          nowUtc: nowUtc(),
        );
      } on X509ValidationException catch (e) {
        throw DevicePairingException(e.code, e.message);
      }

      // B-CB-5: Yaprak sertifikanın Issuer DN'i indirilen CA Subject DN'i ile eşit olmalı
      // (Yalnızca hızlı ön-filtredir; kriptografik imza doğrulaması Faz C/D BoringSSL tarafından yapılır).
      if (capturedLeafDer != null) {
        try {
          final caNames = MmsX509PreValidator.extractSubjectAndIssuerDer(canonical.derBytes);
          final leafNames = MmsX509PreValidator.extractSubjectAndIssuerDer(capturedLeafDer!);
          if (!constantTimeEqualsBytes(caNames.subjectDer, leafNames.issuerDer)) {
            throw const DevicePairingException(
              'CA_PIN_MISMATCH',
              'Sunucunun sunduğu yaprak sertifika indirilen Kök CA tarafından düzenlenmemiş.',
            );
          }
        } on X509ValidationException catch (e) {
          throw DevicePairingException(e.code, e.message);
        }
      }

      return canonical;
    } finally {
      wallClockTimer?.cancel();
      await sub?.cancel();
      bootstrapClient.close(force: true);
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
    } catch (e) {
      debugPrint(
        '[DevicePairingClient] Hub JSON yanıtı ayrıştırılamadı: ${e.runtimeType}',
      );
    }
    return <String, dynamic>{};
  }
}
