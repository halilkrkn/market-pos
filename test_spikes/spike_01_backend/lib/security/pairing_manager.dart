import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import '../db/database.dart';
import '../db/write_queue.dart';
import 'ecdsa_signature_validator.dart';
import 'pairing_delivery_buffer.dart';
import 'token_manager.dart';

enum PairingSessionStatus {
  created,
  pendingApproval,
  approved,
  rejected,
  locked,
  expired,
  completed,
}

class PairingChallenge {
  final String challengeId;
  final Uint8List challengeNonce;
  final String operationType; // 'POLL' veya 'ACK'
  final DateTime createdAt;
  final DateTime expiresAt;
  int failedAttempts;
  bool isLocked;
  bool isConsumed;

  PairingChallenge({
    required this.challengeId,
    required this.challengeNonce,
    required this.operationType,
    required this.createdAt,
    required this.expiresAt,
    this.failedAttempts = 0,
    this.isLocked = false,
    this.isConsumed = false,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isValid => !isExpired && !isLocked && !isConsumed;
}

class PairingSession {
  final String sessionId;
  final String pairingSecret;
  final DateTime createdAt;
  final DateTime expiresAt;
  PairingSessionStatus status;
  int failedSecretAttempts;

  String? deviceId;
  String? deviceName;
  String? platform;
  Uint8List? clientPublicKeyBytes;
  String? clientPublicKeyFingerprint;

  int challengeCount;
  DateTime? lastChallengeIssuedAt;

  PairingChallenge? activePollChallenge;
  PairingChallenge? activeAckChallenge;

  PairingSession({
    required this.sessionId,
    required this.pairingSecret,
    required this.createdAt,
    required this.expiresAt,
    this.status = PairingSessionStatus.created,
    this.failedSecretAttempts = 0,
    this.challengeCount = 0,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class PairingException implements Exception {
  final String code;
  final String message;
  final int statusCode;
  final int? retryAfterSeconds;

  PairingException({
    required this.code,
    required this.message,
    required this.statusCode,
    this.retryAfterSeconds,
  });

  @override
  String toString() => 'PairingException($statusCode, $code): $message';
}

/// S-4: Güvenli Cihaz Eşleştirme (Secure Device Pairing) Oturum ve Meydan Okuma Yöneticisi
class PairingManager {
  static const Duration sessionTtl = Duration(minutes: 5);
  static const Duration challengeTtl = Duration(seconds: 60);
  static const int maxChallengesPerSession = 5;
  static const Duration challengeCooldown = Duration(seconds: 5);

  final Map<String, PairingSession> _sessions = {};
  final PairingDeliveryBuffer deliveryBuffer = PairingDeliveryBuffer();
  final Random _secureRandom = Random.secure();

  // --- Oturum Yönetimi ---

  /// Yeni 5 dakika geçerli Pairing Session ve QR Veri Modeli üretir.
  Map<String, dynamic> createSession({
    required String hubUrl,
    required String caFingerprint,
    Duration ttl = sessionTtl,
  }) {
    final now = DateTime.now();
    final sessionBytes = List<int>.generate(12, (_) => _secureRandom.nextInt(256));
    final secretBytes = List<int>.generate(12, (_) => _secureRandom.nextInt(256));

    final sessionId = 'sess_${sessionBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    final pairingSecret = 'sec_${secretBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    final expiresAt = now.add(ttl);

    final session = PairingSession(
      sessionId: sessionId,
      pairingSecret: pairingSecret,
      createdAt: now,
      expiresAt: expiresAt,
      status: PairingSessionStatus.created,
    );

    _sessions[sessionId] = session;

    return {
      'v': 1,
      'hub_url': hubUrl,
      'ca_fingerprint': caFingerprint,
      'session_id': sessionId,
      'pairing_secret': pairingSecret,
      'expires_at': expiresAt.millisecondsSinceEpoch ~/ 1000,
    };
  }

  /// Oturumu ID ile getirir ve genel TTL kontrolü uygular.
  PairingSession getSession(String sessionId) {
    final session = _sessions[sessionId];
    if (session == null) {
      throw PairingException(
        code: 'SESSION_NOT_FOUND',
        message: 'Eşleştirme oturumu bulunamadı',
        statusCode: 404,
      );
    }
    if (session.isExpired) {
      session.status = PairingSessionStatus.expired;
      throw PairingException(
        code: 'SESSION_EXPIRED',
        message: 'Eşleştirme oturumunun 5 dakikalık süresi doldu',
        statusCode: 410,
      );
    }
    if (session.status == PairingSessionStatus.locked) {
      throw PairingException(
        code: 'SESSION_LOCKED',
        message: 'Oturum güvenlik nedeniyle kilitlendi',
        statusCode: 403,
      );
    }
    return session;
  }

  /// İstemcinin eşleştirme talebini kaydeder ve açık anahtarı oturuma kilitler (Binding Immutability).
  void registerRequest({
    required String sessionId,
    required String pairingSecret,
    required String deviceId,
    required String name,
    required String platform,
    required List<int> clientPublicKeyBytes,
    required String keyAlgorithm,
  }) {
    final session = getSession(sessionId);

    // Secret doğrulaması (Brute-force engeli: 3 hata)
    if (session.pairingSecret != pairingSecret) {
      session.failedSecretAttempts++;
      if (session.failedSecretAttempts >= 3) {
        session.status = PairingSessionStatus.locked;
      }
      throw PairingException(
        code: 'INVALID_PAIRING_SECRET',
        message: 'Geçersiz eşleştirme parolası',
        statusCode: 401,
      );
    }

    if (session.status != PairingSessionStatus.created) {
      throw PairingException(
        code: 'SESSION_ALREADY_BOUND',
        message: 'Bu oturum zaten bir cihaza bağlanmış veya işleniyor',
        statusCode: 409,
      );
    }

    // Açık anahtarı ayrıştır ve doğrula
    try {
      EcdsaSignatureValidator.parsePublicKey(clientPublicKeyBytes);
    } catch (e) {
      throw PairingException(
        code: 'INVALID_PUBLIC_KEY',
        message: 'Geçersiz ECDSA P-256 açık anahtarı: $e',
        statusCode: 400,
      );
    }

    session.deviceId = deviceId;
    session.deviceName = name;
    session.platform = platform;
    session.clientPublicKeyBytes = Uint8List.fromList(clientPublicKeyBytes);
    session.clientPublicKeyFingerprint = EcdsaSignatureValidator.computePublicKeyFingerprint(clientPublicKeyBytes);
    session.status = PairingSessionStatus.pendingApproval;
  }

  /// Onay bekleyen talepleri Hub arayüzü için listeler.
  List<Map<String, dynamic>> getPendingRequests() {
    final list = <Map<String, dynamic>>[];
    for (final session in _sessions.values) {
      if (!session.isExpired && session.status == PairingSessionStatus.pendingApproval) {
        list.add({
          'session_id': session.sessionId,
          'device_id': session.deviceId,
          'name': session.deviceName,
          'platform': session.platform,
          'fingerprint': session.clientPublicKeyFingerprint,
          'created_at': session.createdAt.toIso8601String(),
        });
      }
    }
    return list;
  }

  /// İşletme sahibi eşleştirmeyi onaylar: Raw token üretilir, RAM tamponuna alınır ve DB'ye unconfirmed yazılır.
  Future<void> approveSession({
    required String sessionId,
    required SpikeDatabase db,
    required WriteQueue writeQueue,
    required String pepper,
  }) async {
    final session = getSession(sessionId);

    if (session.status != PairingSessionStatus.pendingApproval) {
      throw PairingException(
        code: 'INVALID_SESSION_STATE',
        message: 'Yalnızca onay bekleyen oturumlar onaylanabilir',
        statusCode: 400,
      );
    }

    final deviceId = session.deviceId!;
    final name = session.deviceName!;
    final platform = session.platform!;
    final keyFingerprint = session.clientPublicKeyFingerprint!;

    final rawToken = TokenManager.generateToken();
    final salt = TokenManager.generateSalt();
    final tokenHash = TokenManager.hashToken(
      rawToken: rawToken,
      salt: salt,
      pepper: pepper,
    );

    // SQLite tekil yazıcı kuyruğunda atomik cihaz kaydı
    await writeQueue.enqueue(() async {
      await db.transaction(() async {
        final existing = await (db.select(db.devices)..where((d) => d.deviceId.equals(deviceId))).getSingleOrNull();
        if (existing != null) {
          if (!existing.isActive) {
            throw StateError('DEVICE_ALREADY_REVOKED');
          }
          throw StateError('DEVICE_ALREADY_EXISTS');
        }

        await db.into(db.devices).insert(
          DevicesCompanion(
            deviceId: Value(deviceId),
            name: Value(name),
            tokenHash: Value(tokenHash),
            salt: Value(salt),
            isActive: const Value(true),
            isConfirmed: const Value(false),
          ),
        );

        await db.into(db.deviceAuditLogs).insert(
          DeviceAuditLogsCompanion(
            deviceId: Value(deviceId),
            action: const Value('PAIRING_APPROVED'),
            details: Value('Platform: $platform, PubKeyFingerprint: $keyFingerprint'),
          ),
        );
      });
    });

    // Ham token'ı 120 sn RAM tamponuna al (Asla diske yazılmaz)
    deliveryBuffer.store(
      sessionId: sessionId,
      deviceId: deviceId,
      rawToken: rawToken,
    );

    session.status = PairingSessionStatus.approved;
  }

  /// İşletme sahibi talebi reddeder.
  Future<void> rejectSession({
    required String sessionId,
    required SpikeDatabase db,
    required WriteQueue writeQueue,
  }) async {
    final session = getSession(sessionId);

    if (session.status != PairingSessionStatus.pendingApproval) {
      throw PairingException(
        code: 'INVALID_SESSION_STATE',
        message: 'Yalnızca onay bekleyen oturumlar reddedilebilir',
        statusCode: 400,
      );
    }

    session.status = PairingSessionStatus.rejected;

    if (session.deviceId != null) {
      await writeQueue.enqueue(() async {
        await db.into(db.deviceAuditLogs).insert(
          DeviceAuditLogsCompanion(
            deviceId: Value(session.deviceId!),
            action: const Value('PAIRING_REJECTED'),
            details: Value('Platform: ${session.platform}, Rejected by owner.'),
          ),
        );
      });
    }
  }

  // --- Ayrık Challenge ve Hız Sınırlandırması (Rate Limiting) ---

  /// Poll için tek kullanımlık challenge üretir (Kota ve Cooldown denetimiyle).
  PairingChallenge issuePollChallenge({
    required String sessionId,
    required String pairingSecret,
  }) {
    final session = getSession(sessionId);

    // FINDING-3: pairing_secret doğrulaması (Kota ve cooldown'dan ÖNCE!)
    if (session.pairingSecret != pairingSecret) {
      session.failedSecretAttempts++;
      if (session.failedSecretAttempts >= 3) {
        session.status = PairingSessionStatus.locked;
      }
      throw PairingException(
        code: 'INVALID_PAIRING_SECRET',
        message: 'Eşleştirme parolası uyuşmuyor',
        statusCode: 401,
      );
    }

    if (session.status != PairingSessionStatus.approved) {
      throw PairingException(
        code: 'SESSION_NOT_APPROVED',
        message: 'Oturum henüz işletme sahibi tarafından onaylanmadı',
        statusCode: 403,
      );
    }

    _applyRateLimitAndQuota(session);

    final now = DateTime.now();
    final nonceBytes = List<int>.generate(32, (_) => _secureRandom.nextInt(256));
    final challengeId = 'ch_poll_${Random().nextInt(1000000).toString().padLeft(6, '0')}';

    final challenge = PairingChallenge(
      challengeId: challengeId,
      challengeNonce: Uint8List.fromList(nonceBytes),
      operationType: 'POLL',
      createdAt: now,
      expiresAt: now.add(challengeTtl),
    );

    session.activePollChallenge = challenge;
    return challenge;
  }

  /// Poll imzasını doğrular ve ham token'ı RAM tamponundan döner.
  String verifyAndPollToken({
    required String sessionId,
    required String pairingSecret,
    required String pollChallengeId,
    required List<int> signatureBytes,
  }) {
    final session = getSession(sessionId);

    if (session.pairingSecret != pairingSecret) {
      throw PairingException(
        code: 'INVALID_PAIRING_SECRET',
        message: 'Eşleştirme parolası uyuşmuyor',
        statusCode: 401,
      );
    }

    final challenge = session.activePollChallenge;
    if (challenge == null || challenge.challengeId != pollChallengeId) {
      throw PairingException(
        code: 'CHALLENGE_NOT_FOUND',
        message: 'Meydan okuma bulunamadı veya süresi doldu',
        statusCode: 404,
      );
    }

    if (challenge.isConsumed) {
      throw PairingException(
        code: 'CHALLENGE_ALREADY_CONSUMED',
        message: 'Bu challenge daha önce tüketildi (Replay tespit edildi)',
        statusCode: 409,
      );
    }

    if (challenge.isLocked || challenge.failedAttempts >= 3) {
      throw PairingException(
        code: 'CHALLENGE_LOCKED',
        message: 'Bu meydan okuma 3 hatalı deneme nedeniyle kilitlendi. Lütfen yeni challenge talep edin.',
        statusCode: 403,
      );
    }

    if (challenge.isExpired) {
      throw PairingException(
        code: 'CHALLENGE_EXPIRED',
        message: 'Meydan okumanın 60 saniyelik süresi doldu. Lütfen yeni challenge talep edin.',
        statusCode: 410,
      );
    }

    // 6 alanlı kanonik Poll çerçevesini kur
    final canonicalPayload = EcdsaSignatureValidator.buildCanonicalPollPayload(
      protocolVersion: '1',
      pairingSessionId: sessionId,
      publicKeyFingerprintBytes: sha256.convert(session.clientPublicKeyBytes!).bytes,
      challengeId: pollChallengeId,
      challengeNonce: challenge.challengeNonce,
    );

    // Kriptografik İmza Doğrulama (Tekil SHA-256 + Low-S + Strict DER)
    final isValid = EcdsaSignatureValidator.verifySignature(
      publicKeyBytes: session.clientPublicKeyBytes!,
      canonicalPayload: canonicalPayload,
      signatureBytes: signatureBytes,
    );

    if (!isValid) {
      challenge.failedAttempts++;
      if (challenge.failedAttempts >= 3) {
        challenge.isLocked = true;
      }
      throw PairingException(
        code: 'INVALID_DEVICE_SIGNATURE',
        message: 'Cihaz imzası doğrulanamadı (Hatalı deneme: ${challenge.failedAttempts}/3)',
        statusCode: 403,
      );
    }

    // İmza GEÇERLİ: Challenge anında ve geri dönüşsüz CONSUMED yapılır
    challenge.isConsumed = true;

    final rawToken = deliveryBuffer.getRawToken(sessionId);
    if (rawToken == null) {
      throw PairingException(
        code: 'TOKEN_BUFFER_EXPIRED',
        message: 'Teslimat tampon süresi (120 sn) doldu veya token onaylandı',
        statusCode: 410,
      );
    }

    return rawToken;
  }

  /// ACK için tek kullanımlık challenge üretir.
  PairingChallenge issueAckChallenge({
    required String sessionId,
    required String pairingSecret,
  }) {
    final session = getSession(sessionId);

    // FINDING-3: pairing_secret doğrulaması (Kota ve cooldown'dan ÖNCE!)
    if (session.pairingSecret != pairingSecret) {
      session.failedSecretAttempts++;
      if (session.failedSecretAttempts >= 3) {
        session.status = PairingSessionStatus.locked;
      }
      throw PairingException(
        code: 'INVALID_PAIRING_SECRET',
        message: 'Eşleştirme parolası uyuşmuyor',
        statusCode: 401,
      );
    }

    if (session.status != PairingSessionStatus.approved) {
      throw PairingException(
        code: 'SESSION_NOT_APPROVED',
        message: 'Oturum onaylanmamış',
        statusCode: 403,
      );
    }

    _applyRateLimitAndQuota(session);

    final now = DateTime.now();
    final nonceBytes = List<int>.generate(32, (_) => _secureRandom.nextInt(256));
    final challengeId = 'ch_ack_${Random().nextInt(1000000).toString().padLeft(6, '0')}';

    final challenge = PairingChallenge(
      challengeId: challengeId,
      challengeNonce: Uint8List.fromList(nonceBytes),
      operationType: 'ACK',
      createdAt: now,
      expiresAt: now.add(challengeTtl),
    );

    session.activeAckChallenge = challenge;
    return challenge;
  }

  /// Token-Bound ACK imzasını doğrular, cihazı onaylar ve RAM'i temizler.
  Future<void> verifyAndAcknowledge({
    required String sessionId,
    required String ackChallengeId,
    required List<int> signatureBytes,
    required SpikeDatabase db,
    required WriteQueue writeQueue,
  }) async {
    final session = getSession(sessionId);

    final challenge = session.activeAckChallenge;
    if (challenge == null || challenge.challengeId != ackChallengeId) {
      throw PairingException(
        code: 'CHALLENGE_NOT_FOUND',
        message: 'ACK meydan okuması bulunamadı veya süresi doldu',
        statusCode: 404,
      );
    }

    if (challenge.isConsumed) {
      throw PairingException(
        code: 'CHALLENGE_ALREADY_CONSUMED',
        message: 'Bu ACK challenge zaten tüketildi',
        statusCode: 409,
      );
    }

    if (challenge.isLocked || challenge.failedAttempts >= 3) {
      throw PairingException(
        code: 'CHALLENGE_LOCKED',
        message: 'ACK meydan okuması kilitlendi',
        statusCode: 403,
      );
    }

    if (challenge.isExpired) {
      throw PairingException(
        code: 'CHALLENGE_EXPIRED',
        message: 'ACK meydan okumasının 60 saniyelik süresi doldu',
        statusCode: 410,
      );
    }

    // Tampondaki ham token'ın SHA-256 özetini al
    final expectedTokenHash = deliveryBuffer.getTokenSha256(sessionId);
    if (expectedTokenHash == null) {
      throw PairingException(
        code: 'TOKEN_BUFFER_EXPIRED',
        message: 'Tampon süresi dolmuş veya token zaten onaylanmış',
        statusCode: 410,
      );
    }

    // 7 alanlı Token-Bound Kanonik ACK çerçevesini inşa et
    final canonicalAckPayload = EcdsaSignatureValidator.buildCanonicalAckPayload(
      protocolVersion: '1',
      pairingSessionId: sessionId,
      publicKeyFingerprintBytes: sha256.convert(session.clientPublicKeyBytes!).bytes,
      challengeId: ackChallengeId,
      challengeNonce: challenge.challengeNonce,
      tokenHashBytes: expectedTokenHash,
    );

    // Kriptografik İmza Doğrulama
    final isValid = EcdsaSignatureValidator.verifySignature(
      publicKeyBytes: session.clientPublicKeyBytes!,
      canonicalPayload: canonicalAckPayload,
      signatureBytes: signatureBytes,
    );

    if (!isValid) {
      challenge.failedAttempts++;
      if (challenge.failedAttempts >= 3) {
        challenge.isLocked = true;
      }
      throw PairingException(
        code: 'INVALID_ACK_TOKEN_HASH_SIGNATURE',
        message: 'ACK imzası veya token hash doğrulaması başarısız',
        statusCode: 403,
      );
    }

    challenge.isConsumed = true;

    // Tamponu teyit et ve DB'de confirmed yap
    final ok = await deliveryBuffer.acknowledge(
      sessionId: sessionId,
      db: db,
      writeQueue: writeQueue,
    );

    if (!ok) {
      throw PairingException(
        code: 'DELIVERY_CONFIRM_FAILED',
        message: 'Teslimat teyidi tamamlanamadı',
        statusCode: 500,
      );
    }

    session.status = PairingSessionStatus.completed;
  }

  // --- Rate Limiting ve Kota Kontrolü ---

  void _applyRateLimitAndQuota(PairingSession session) {
    final now = DateTime.now();

    // 1. Oturum Başına Toplam Kota (Max 5)
    if (session.challengeCount >= maxChallengesPerSession) {
      session.status = PairingSessionStatus.locked;
      throw PairingException(
        code: 'SESSION_CHALLENGE_QUOTA_EXHAUSTED',
        message: 'Bu oturum için tanınan en fazla 5 meydan okuma kotası aşıldı. Oturum kilitlendi.',
        statusCode: 429,
      );
    }

    // 2. Cooldown Kontrolü (Minimum 5 saniye)
    if (session.lastChallengeIssuedAt != null) {
      final elapsed = now.difference(session.lastChallengeIssuedAt!);
      if (elapsed < challengeCooldown) {
        final remainingSeconds = challengeCooldown.inSeconds - elapsed.inSeconds;
        throw PairingException(
          code: 'CHALLENGE_COOLDOWN_ACTIVE',
          message: 'Lütfen ardışık meydan okuma talepleri arasında 5 saniye bekleyin.',
          statusCode: 429,
          retryAfterSeconds: remainingSeconds > 0 ? remainingSeconds : 1,
        );
      }
    }

    session.challengeCount++;
    session.lastChallengeIssuedAt = now;
  }

  /// Test amaçlı oturumları temizler
  void clear() {
    _sessions.clear();
    deliveryBuffer.clear();
  }
}
