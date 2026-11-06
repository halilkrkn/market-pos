import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/open.dart';

import 'package:crypto/crypto.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/auth_middleware.dart';
import '../lib/security/body_limit_middleware.dart';
import '../lib/security/certificate_manager.dart';
import '../lib/security/pairing_delivery_buffer.dart';
import '../lib/security/pairing_manager.dart';
import '../lib/security/pepper_manager.dart';
import '../lib/security/secure_cors_middleware.dart';
import '../lib/security/token_manager.dart';
import '../lib/service/admission_gate.dart';
import '../lib/service/lifecycle_manager.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

void configureSqliteNative() {
  if (Platform.isWindows) {
    open.overrideFor(OperatingSystem.windows, () {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      final dllPath = p.join(exeDir, 'sqlite3.dll');
      if (File(dllPath).existsSync()) {
        return DynamicLibrary.open(dllPath);
      }
      try {
        return DynamicLibrary.open('sqlite3.dll');
      } catch (_) {
        return DynamicLibrary.process();
      }
    });
  }
}

class _IdempotencyConflictException implements Exception {
  final String idempotencyKey;
  _IdempotencyConflictException(this.idempotencyKey);
}

class _ValidationException implements Exception {
  final int statusCode;
  final String code;
  final String message;
  _ValidationException(this.statusCode, this.code, this.message);
}

class SpikeServer {
  SpikeDatabase db;
  final File? dbFile;
  final WriteQueue writeQueue;
  final LifecycleManager lifecycle;
  final String? backupDirectory;
  final String? adminSecret;
  final PepperManager pepperManager;
  final SecurityContext? securityContext;
  final bool requireTls;
  final PairingManager pairingManager;
  final String? caCertPath;
  late final Router _router;
  HttpServer? _httpServer;
  Timer? _pairingCleanupTimer;

  static final Random _secureRandom = Random.secure();

  SpikeServer({
    required this.db,
    required this.writeQueue,
    this.dbFile,
    this.backupDirectory,
    this.adminSecret,
    PepperManager? pepperManager,
    this.securityContext,
    this.requireTls = false,
    PairingManager? pairingManager,
    this.caCertPath,
    LifecycleManager? lifecycle,
  })  : pepperManager = _resolvePepperManager(pepperManager),
        pairingManager = pairingManager ?? PairingManager(),
        lifecycle = lifecycle ?? LifecycleManager(db: db, writeQueue: writeQueue) {
    _setupRoutes();
  }

  static PepperManager _resolvePepperManager(PepperManager? provided) {
    if (provided != null) {
      try {
        final _ = provided.pepper;
      } catch (_) {
        provided.initialize();
      }
      return provided;
    }
    final pepperPath = Platform.environment['PEPPER_FILE'] ?? 'pepper.dpapi';
    final pm = PepperManager(File(pepperPath));
    pm.initialize();
    return pm;
  }

  /// Zamanlama saldırılarını (timing attack) önleyen sabit zamanlı byte karşılaştırması
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  /// S5A-2: Satış işlem yükünün (payload) kanonik SHA-256 hash özetini üretir
  static String computeSaleRequestHash(Map<String, dynamic> body) {
    final canonical = {
      'client_seq': body['client_seq'],
      'total_amount': body['total_amount'],
      'payment_method': body['payment_method'],
      'items': body['items'],
    };
    return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
  }

  /// Hub yönetimi için Loopback ve Admin Secret yetkilendirmesi denetler (Fail-Closed)
  Response? _verifyLoopbackAndAdmin(Request req, {String actionName = 'Bu işlem'}) {
    final connectionInfo = req.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    if (connectionInfo == null) {
      return Response.forbidden(
        jsonEncode({
          'error': 'FORBIDDEN',
          'code': 'ERR_LOOPBACK_REQUIRED',
          'message': '$actionName için bağlantı bilgisi doğrulanamadı. Yalnızca yerel makineden (loopback) erişilebilir.',
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final remoteAddr = connectionInfo.remoteAddress;
    final isLoopback = remoteAddr.isLoopback ||
        remoteAddr.address == '127.0.0.1' ||
        remoteAddr.address == '::1' ||
        remoteAddr.address == '0:0:0:0:0:0:0:1' ||
        remoteAddr.address == '::ffff:127.0.0.1';

    if (!isLoopback) {
      return Response.forbidden(
        jsonEncode({
          'error': 'FORBIDDEN',
          'code': 'ERR_LOOPBACK_REQUIRED',
          'message': '$actionName için yalnızca yerel makineden (loopback) erişilebilir.',
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final effectiveAdminSecret = adminSecret ?? Platform.environment['ADMIN_SECRET'];
    if (effectiveAdminSecret == null || effectiveAdminSecret.isEmpty) {
      return Response(
        503,
        body: jsonEncode({
          'error': 'ADMIN_DISABLED',
          'code': 'ERR_ADMIN_NOT_CONFIGURED',
          'message': 'Admin secret yapılandırılmamış ve güvenlik nedeniyle devre dışıdır.',
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final providedAdminSecret = req.headers['x-admin-secret'] ??
        (req.headers['authorization']?.startsWith('Bearer ') == true
            ? req.headers['authorization']!.substring(7).trim()
            : null);

    if (providedAdminSecret == null || providedAdminSecret.isEmpty) {
      return Response(
        401,
        body: jsonEncode({
          'error': 'UNAUTHORIZED',
          'code': 'ERR_ADMIN_SECRET_REQUIRED',
          'message': '$actionName için admin secret gereklidir.',
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    if (!_constantTimeEquals(utf8.encode(providedAdminSecret), utf8.encode(effectiveAdminSecret))) {
      return Response.forbidden(
        jsonEncode({
          'error': 'FORBIDDEN',
          'code': 'ERR_INVALID_ADMIN_SECRET',
          'message': 'Geçersiz admin secret.',
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    return null;
  }

  /// Çakışma ve üzerine yazmayı önleyen, mikrosaniye ve kriptografik nonce içeren benzersiz dosya adı üretici
  String _generateUniqueBackupPath(Directory targetDir) {
    while (true) {
      final now = DateTime.now().toUtc();
      final ts = now.toIso8601String().replaceAll(RegExp(r'[^0-9]'), '');
      final nonceBytes = List<int>.generate(4, (_) => _secureRandom.nextInt(256));
      final nonceHex = nonceBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final safeFileName = 'mms_backup_${ts}_$nonceHex.db';
      final safeBackupPath = p.normalize(p.join(targetDir.path, safeFileName));
      if (!File(safeBackupPath).existsSync()) {
        return safeBackupPath;
      }
    }
  }

  void _setupRoutes() {
    _router = Router();

    // 1. Health check (Sistem ve SQLite sürümü maskelenmiştir)
    _router.get('/health', (Request req) async {
      return Response.ok(
        jsonEncode({
          'status': 'UP',
          'timestamp': DateTime.now().toIso8601String(),
          'sqlite_version': 'masked', // Sistem sürümü sızıntısını önlemek için maskelendi
          'queue_metrics': writeQueue.metrics.toJson(),
        }),
        headers: {'content-type': 'application/json'},
      );
    });


    // 2. Eski Cihaz Kaydı (S-4 ile tasfiye edildi - 404 Not Found)
    _router.post('/api/v1/devices/register', (Request req) async {
      return Response.notFound(
        jsonEncode({
          'error': 'NOT_FOUND',
          'code': 'ERR_ENDPOINT_RETIRED',
          'message': 'Eski cihaz kayıt endpoint’i kaldırılmıştır. Lütfen güvenli eşleştirme (/api/v1/pairing/*) protokolünü kullanın.',
        }),
        headers: {'content-type': 'application/json'},
      );
    });


    // -------------------------------------------------------------
    // S-4: GÜVENLİ CİHAZ EŞLEŞTİRME (PAIRING) PROTOKOLÜ (v1.6)
    // -------------------------------------------------------------

    // 1. Yeni Eşleştirme Oturumu Başlat (Hub Admin / Loopback)
    _router.post('/api/v1/pairing/session', (Request req) async {
      final authError = _verifyLoopbackAndAdmin(req, actionName: 'Eşleştirme oturumu oluşturma');
      if (authError != null) return authError;

      final scheme = requireTls ? 'https' : (req.requestedUri.scheme);
      final host = req.requestedUri.host;
      final port = req.requestedUri.port;
      final hubUrl = '$scheme://$host:$port';

      var caFingerprint = 'UNKNOWN';
      if (caCertPath != null && File(caCertPath!).existsSync()) {
        caFingerprint = CertificateManager.computeSha256Fingerprint(File(caCertPath!).readAsBytesSync());
      } else {
        final envCert = Platform.environment['ROOT_CA_CERT_FILE'];
        if (envCert != null && File(envCert).existsSync()) {
          caFingerprint = CertificateManager.computeSha256Fingerprint(File(envCert).readAsBytesSync());
        }
      }

      final sessionData = pairingManager.createSession(
        hubUrl: hubUrl,
        caFingerprint: caFingerprint,
      );

      return Response(
        201,
        body: jsonEncode(sessionData),
        headers: {'content-type': 'application/json'},
      );
    });


    // 2. Kök CA Sertifikasını İndir (Public)
    _router.get('/api/v1/pairing/ca-cert', (Request req) async {
      String? certContent;
      if (caCertPath != null && File(caCertPath!).existsSync()) {
        certContent = File(caCertPath!).readAsStringSync();
      } else {
        final envCert = Platform.environment['ROOT_CA_CERT_FILE'];
        if (envCert != null && File(envCert).existsSync()) {
          certContent = File(envCert).readAsStringSync();
        }
      }

      if (certContent == null) {
        return Response.notFound(
          jsonEncode({
            'error': 'NOT_FOUND',
            'code': 'ERR_CA_CERT_NOT_FOUND',
            'message': 'Kök CA sertifikası bulunamadı.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      return Response.ok(
        certContent,
        headers: {'content-type': 'application/x-x509-ca-cert'},
      );
    });

    // 3. Eşleştirme Talebi Gönder (Public - HTTPS)
    _router.post('/api/v1/pairing/request', (Request req) async {
      try {
        final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
        final sessionId = body['session_id'] as String;
        final pairingSecret = body['pairing_secret'] as String;
        final deviceId = body['device_id'] as String;
        final name = body['name'] as String;
        final platform = body['platform'] as String? ?? 'UNKNOWN';
        final keyAlg = body['key_algorithm'] as String? ?? 'ECDSA_P256';

        final rawKey = body['client_public_key'];
        List<int> pubKeyBytes;
        if (rawKey is String) {
          pubKeyBytes = base64Decode(rawKey);
        } else if (rawKey is List) {
          pubKeyBytes = List<int>.from(rawKey);
        } else {
          return Response(400, body: jsonEncode({'error': 'INVALID_PUBLIC_KEY', 'message': 'Açık anahtar belirtilmedi.'}), headers: {'content-type': 'application/json'});
        }

        pairingManager.registerRequest(
          sessionId: sessionId,
          pairingSecret: pairingSecret,
          deviceId: deviceId,
          name: name,
          platform: platform,
          clientPublicKeyBytes: pubKeyBytes,
          keyAlgorithm: keyAlg,
        );

        return Response(
          202,
          body: jsonEncode({
            'status': 'PENDING_APPROVAL',
            'session_id': sessionId,
            'message': 'Eşleştirme talebi alındı. İşletme sahibi onayı bekleniyor.',
          }),
          headers: {'content-type': 'application/json'},
        );
      } on PairingException catch (e) {
        return Response(
          e.statusCode,
          body: jsonEncode({'error': e.code, 'message': e.message}),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        return Response(400, body: jsonEncode({'error': 'BAD_REQUEST', 'message': e.toString()}), headers: {'content-type': 'application/json'});
      }
    });

    // 4. Onay Bekleyen Talepleri Listele (Hub Admin / Loopback)
    _router.get('/api/v1/pairing/requests', (Request req) async {
      final authError = _verifyLoopbackAndAdmin(req, actionName: 'Eşleştirme taleplerini listeleme');
      if (authError != null) return authError;

      final requests = pairingManager.getPendingRequests();
      return Response.ok(
        jsonEncode({'requests': requests}),
        headers: {'content-type': 'application/json'},
      );
    });


    // 5. Talebi Onayla (Hub Admin / Loopback)
    _router.post('/api/v1/pairing/approve', (Request req) async {
      final authError = _verifyLoopbackAndAdmin(req, actionName: 'Eşleştirme onaylama');
      if (authError != null) return authError;

      try {
        final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
        final sessionId = body['session_id'] as String;

        await pairingManager.approveSession(
          sessionId: sessionId,
          db: db,
          writeQueue: writeQueue,
          pepper: pepperManager.pepper,
        );

        return Response.ok(
          jsonEncode({
            'status': 'APPROVED',
            'session_id': sessionId,
            'message': 'Cihaz onaylandı. Token teslimat tamponuna alındı.',
          }),
          headers: {'content-type': 'application/json'},
        );
      } on PairingException catch (e) {
        return Response(
          e.statusCode,
          body: jsonEncode({'error': e.code, 'message': e.message}),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        if (e.toString().contains('DEVICE_ALREADY_EXISTS')) {
          return Response(409, body: jsonEncode({'error': 'DEVICE_ALREADY_EXISTS', 'message': 'Bu ID ile aktif bir cihaz zaten mevcut.'}), headers: {'content-type': 'application/json'});
        }
        if (e.toString().contains('DEVICE_ALREADY_REVOKED')) {
          return Response(409, body: jsonEncode({'error': 'DEVICE_ALREADY_REVOKED', 'message': 'İptal edilmiş bir cihaz yeniden eşleştirilemez.'}), headers: {'content-type': 'application/json'});
        }
        return Response(400, body: jsonEncode({'error': 'BAD_REQUEST', 'message': e.toString()}), headers: {'content-type': 'application/json'});
      }
    });

    // 6. Talebi Reddet (Hub Admin / Loopback)
    _router.post('/api/v1/pairing/reject', (Request req) async {
      final authError = _verifyLoopbackAndAdmin(req, actionName: 'Eşleştirme reddetme');
      if (authError != null) return authError;

      try {
        final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
        final sessionId = body['session_id'] as String;

        await pairingManager.rejectSession(
          sessionId: sessionId,
          db: db,
          writeQueue: writeQueue,
        );

        return Response.ok(
          jsonEncode({
            'status': 'REJECTED',
            'session_id': sessionId,
            'message': 'Eşleştirme talebi reddedildi.',
          }),
          headers: {'content-type': 'application/json'},
        );
      } on PairingException catch (e) {
        return Response(
          e.statusCode,
          body: jsonEncode({'error': e.code, 'message': e.message}),
          headers: {'content-type': 'application/json'},
        );
      }
    });

    // 7. Poll Challenge İste (Public + pairing_secret)
    _router.post('/api/v1/pairing/poll-challenge', (Request req) async {
      try {
        final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
        final sessionId = body['session_id'] as String?;
        final pairingSecret = body['pairing_secret'] as String?;

        if (sessionId == null || sessionId.isEmpty) {
          return Response(400, body: jsonEncode({'error': 'INVALID_REQUEST', 'message': 'session_id gereklidir'}), headers: {'content-type': 'application/json'});
        }
        if (pairingSecret == null || pairingSecret.isEmpty) {
          return Response(401, body: jsonEncode({'error': 'INVALID_PAIRING_SECRET', 'message': 'pairing_secret gereklidir'}), headers: {'content-type': 'application/json'});
        }

        final challenge = pairingManager.issuePollChallenge(
          sessionId: sessionId,
          pairingSecret: pairingSecret,
        );

        return Response.ok(
          jsonEncode({
            'poll_challenge_id': challenge.challengeId,
            'poll_challenge_nonce': base64Encode(challenge.challengeNonce),
            'expires_in': 60,
          }),
          headers: {'content-type': 'application/json'},
        );
      } on PairingException catch (e) {
        final headers = <String, String>{'content-type': 'application/json'};
        if (e.statusCode == 429 && e.retryAfterSeconds != null) {
          headers['retry-after'] = e.retryAfterSeconds.toString();
        }
        return Response(
          e.statusCode,
          body: jsonEncode({
            'error': e.code,
            'message': e.message,
            if (e.retryAfterSeconds != null) 'retry_after_seconds': e.retryAfterSeconds,
          }),
          headers: headers,
        );
      } catch (e) {
        return Response(400, body: jsonEncode({'error': 'BAD_REQUEST', 'message': e.toString()}), headers: {'content-type': 'application/json'});
      }
    });

    // 8. Poll Token (Public - İmzalı Kanonik Çerçeve)
    _router.post('/api/v1/pairing/poll', (Request req) async {
      try {
        final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
        final sessionId = body['session_id'] as String;
        final pairingSecret = body['pairing_secret'] as String;
        final pollChallengeId = body['poll_challenge_id'] as String;

        final rawSig = body['signature'];
        List<int> sigBytes;
        if (rawSig is String) {
          sigBytes = base64Decode(rawSig);
        } else if (rawSig is List) {
          sigBytes = List<int>.from(rawSig);
        } else {
          return Response(400, body: jsonEncode({'error': 'INVALID_SIGNATURE', 'message': 'İmza belirtilmedi'}), headers: {'content-type': 'application/json'});
        }

        final rawToken = pairingManager.verifyAndPollToken(
          sessionId: sessionId,
          pairingSecret: pairingSecret,
          pollChallengeId: pollChallengeId,
          signatureBytes: sigBytes,
        );

        final session = pairingManager.getSession(sessionId);

        return Response.ok(
          jsonEncode({
            'status': 'PAIRED',
            'device_id': session.deviceId,
            'token': rawToken,
          }),
          headers: {'content-type': 'application/json'},
        );
      } on PairingException catch (e) {
        return Response(
          e.statusCode,
          body: jsonEncode({'error': e.code, 'message': e.message}),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        return Response(400, body: jsonEncode({'error': 'BAD_REQUEST', 'message': e.toString()}), headers: {'content-type': 'application/json'});
      }
    });

    // 9. ACK Challenge İste (Public + pairing_secret)
    _router.post('/api/v1/pairing/ack-challenge', (Request req) async {
      try {
        final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
        final sessionId = body['session_id'] as String?;
        final pairingSecret = body['pairing_secret'] as String?;

        if (sessionId == null || sessionId.isEmpty) {
          return Response(400, body: jsonEncode({'error': 'INVALID_REQUEST', 'message': 'session_id gereklidir'}), headers: {'content-type': 'application/json'});
        }
        if (pairingSecret == null || pairingSecret.isEmpty) {
          return Response(401, body: jsonEncode({'error': 'INVALID_PAIRING_SECRET', 'message': 'pairing_secret gereklidir'}), headers: {'content-type': 'application/json'});
        }

        final challenge = pairingManager.issueAckChallenge(
          sessionId: sessionId,
          pairingSecret: pairingSecret,
        );

        return Response.ok(
          jsonEncode({
            'ack_challenge_id': challenge.challengeId,
            'ack_challenge_nonce': base64Encode(challenge.challengeNonce),
            'expires_in': 60,
          }),
          headers: {'content-type': 'application/json'},
        );
      } on PairingException catch (e) {
        final headers = <String, String>{'content-type': 'application/json'};
        if (e.statusCode == 429 && e.retryAfterSeconds != null) {
          headers['retry-after'] = e.retryAfterSeconds.toString();
        }
        return Response(
          e.statusCode,
          body: jsonEncode({
            'error': e.code,
            'message': e.message,
            if (e.retryAfterSeconds != null) 'retry_after_seconds': e.retryAfterSeconds,
          }),
          headers: headers,
        );
      } catch (e) {
        return Response(400, body: jsonEncode({'error': 'BAD_REQUEST', 'message': e.toString()}), headers: {'content-type': 'application/json'});
      }
    });

    // 10. ACK Onayı (Public - Token-Bound İmzalı Çerçeve)
    _router.post('/api/v1/pairing/ack', (Request req) async {
      try {
        final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
        final sessionId = body['session_id'] as String;
        final ackChallengeId = body['ack_challenge_id'] as String;

        final rawSig = body['signature'];
        List<int> sigBytes;
        if (rawSig is String) {
          sigBytes = base64Decode(rawSig);
        } else if (rawSig is List) {
          sigBytes = List<int>.from(rawSig);
        } else {
          return Response(400, body: jsonEncode({'error': 'INVALID_SIGNATURE', 'message': 'İmza belirtilmedi'}), headers: {'content-type': 'application/json'});
        }

        await pairingManager.verifyAndAcknowledge(
          sessionId: sessionId,
          ackChallengeId: ackChallengeId,
          signatureBytes: sigBytes,
          db: db,
          writeQueue: writeQueue,
        );

        return Response.ok(
          jsonEncode({
            'status': 'CONFIRMED',
            'session_id': sessionId,
            'message': 'Teslimat teyidi tamamlandı. Cihaz başarıyla aktifleştirildi.',
          }),
          headers: {'content-type': 'application/json'},
        );
      } on PairingException catch (e) {
        return Response(
          e.statusCode,
          body: jsonEncode({'error': e.code, 'message': e.message}),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        return Response(400, body: jsonEncode({'error': 'BAD_REQUEST', 'message': e.toString()}), headers: {'content-type': 'application/json'});
      }
    });

    // 3. Token Yenileme (Renew Token - S-2)
    _router.post('/api/v1/devices/renew-token', (Request req) async {
      final deviceId = req.context['authenticated_device_id'] as String?;
      if (deviceId == null) {
        return Response(
          401,
          body: jsonEncode({
            'error': 'UNAUTHORIZED',
            'message': 'Token yenileme için yetkili bir cihaz oturumu gereklidir.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final newToken = TokenManager.generateToken();
      final newSalt = TokenManager.generateSalt();
      final newHash = TokenManager.hashToken(
        rawToken: newToken,
        salt: newSalt,
        pepper: pepperManager.pepper,
      );

      await writeQueue.enqueue(() async {
        await (db.update(db.devices)..where((d) => d.deviceId.equals(deviceId))).write(
              DevicesCompanion(
                tokenHash: Value(newHash),
                salt: Value(newSalt),
                lastUsedAt: Value(DateTime.now()),
              ),
            );
        await db.into(db.deviceAuditLogs).insert(
              DeviceAuditLogsCompanion(
                deviceId: Value(deviceId),
                action: const Value('RENEW'),
                details: const Value('Token başarıyla yenilendi.'),
              ),
            );
      });

      return Response.ok(
        jsonEncode({
          'status': 'RENEWED',
          'device_id': deviceId,
          'token': newToken,
        }),
        headers: {'content-type': 'application/json'},
      );
    });


    // 4. Token İptali (Revoke Device - S-2)
    _router.post('/api/v1/devices/revoke', (Request req) async {
      final effectiveAdminSecret = adminSecret ?? Platform.environment['ADMIN_SECRET'];
      final providedAdminSecret = req.headers['x-admin-secret'] ??
          (req.headers['authorization']?.startsWith('Bearer ') == true
              ? req.headers['authorization']!.substring(7).trim()
              : null);

      if (effectiveAdminSecret == null || effectiveAdminSecret.isEmpty) {
        return Response(
          503,
          body: jsonEncode({
            'error': 'REVOCATION_DISABLED',
            'code': 'ERR_ADMIN_SECRET_NOT_CONFIGURED',
            'message': 'Admin secret yapılandırılmadığı için cihaz iptal işlemi yapılamaz.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      if (providedAdminSecret == null || providedAdminSecret.isEmpty) {
        return Response(
          401,
          body: jsonEncode({
            'error': 'UNAUTHORIZED',
            'code': 'ERR_ADMIN_SECRET_REQUIRED',
            'message': 'Cihaz iptal işlemi için admin secret gereklidir.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      if (!_constantTimeEquals(utf8.encode(providedAdminSecret), utf8.encode(effectiveAdminSecret))) {
        return Response.forbidden(
          jsonEncode({
            'error': 'FORBIDDEN',
            'code': 'ERR_INVALID_ADMIN_SECRET',
            'message': 'Geçersiz admin secret.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final bodyStr = await req.readAsString();
      Map<String, dynamic> body = {};
      if (bodyStr.isNotEmpty) {
        try {
          body = jsonDecode(bodyStr) as Map<String, dynamic>;
        } catch (_) {}
      }

      final targetDeviceId = body['device_id'] as String?;
      if (targetDeviceId == null || targetDeviceId.isEmpty) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'INVALID_REQUEST',
            'message': 'device_id parametresi zorunludur.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final reason = body['reason'] as String? ?? 'Admin tarafından iptal edildi';

      final device = await (db.select(db.devices)..where((d) => d.deviceId.equals(targetDeviceId))).getSingleOrNull();
      if (device == null) {
        return Response(
          404,
          body: jsonEncode({
            'error': 'DEVICE_NOT_FOUND',
            'message': 'İptal edilecek cihaz bulunamadı.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      if (!device.isActive) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'ALREADY_REVOKED',
            'message': 'Cihaz zaten daha önce iptal edilmiştir.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      await writeQueue.enqueue(() async {
        await (db.update(db.devices)..where((d) => d.deviceId.equals(targetDeviceId))).write(
              const DevicesCompanion(isActive: Value(false)),
            );
        await db.into(db.deviceAuditLogs).insert(
              DeviceAuditLogsCompanion(
                deviceId: Value(targetDeviceId),
                action: const Value('REVOKE'),
                details: Value('İptal nedeni: $reason'),
              ),
            );
      });

      return Response.ok(
        jsonEncode({
          'status': 'REVOKED',
          'device_id': targetDeviceId,
        }),
        headers: {'content-type': 'application/json'},
      );
    });


    // 4.5. Ürün Listesi ve Fiyat Senkronizasyonu (S5A-3 İki Aşamalı İstemci Senkronizasyonu - Snapshot)
    _router.get('/api/v1/products', (Request req) async {
      final deviceId = req.context['authenticated_device_id'] as String?;
      final now = DateTime.now();

      final products = await db.select(db.products).get();
      final items = products.map((p) => {
        'id': p.id,
        'barcode': p.barcode,
        'name': p.name,
        'price': p.price,
        'price_version_id': p.priceVersionId,
        'stock': p.stock,
        'stock_unit': p.stockUnit,
        'pricing_unit': p.pricingUnit,
        'conversion_factor_numerator': p.conversionFactorNumerator,
        'conversion_factor_denominator': p.conversionFactorDenominator,
        'is_active': p.isActive,
        'barcodes': [p.barcode],
        'updated_at': p.updatedAt.toIso8601String(),
      }).toList();

      String? syncSessionId;
      if (deviceId != null) {
        syncSessionId = 'sync_${deviceId}_${now.microsecondsSinceEpoch}';
        await writeQueue.enqueue(() async {
          await db.into(db.productSyncSessions).insert(
                ProductSyncSessionsCompanion(
                  id: Value(syncSessionId!),
                  deviceId: Value(deviceId),
                  productCount: Value(items.length),
                  syncedAt: Value(now),
                  isAcknowledged: const Value(false),
                  createdAt: Value(now),
                ),
              );
        });
      }

      return Response.ok(
        jsonEncode({
          'status': 'OK',
          'products': items,
          'count': items.length,
          'synced_at': now.toIso8601String(),
          if (syncSessionId != null) 'sync_session_id': syncSessionId,
        }),
        headers: {'content-type': 'application/json'},
      );
    });


    // 4.6. Ürün Senkronizasyon Onayı (S5A-3 Product Sync ACK - Idempotent)
    _router.post('/api/v1/products/sync-ack', (Request req) async {
      final deviceId = req.context['authenticated_device_id'] as String?;
      if (deviceId == null) {
        return Response(
          401,
          body: jsonEncode({
            'error': 'UNAUTHORIZED',
            'code': 'ERR_AUTH_REQUIRED',
            'message': 'Ürün senkronizasyon onayı için yetkili bir cihaz oturumu gereklidir.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final bodyStr = await req.readAsString();
      Map<String, dynamic> body = {};
      if (bodyStr.isNotEmpty) {
        try {
          body = jsonDecode(bodyStr) as Map<String, dynamic>;
        } catch (_) {}
      }

      final syncSessionId = body['sync_session_id'] as String?;
      if (syncSessionId == null || syncSessionId.trim().isEmpty) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'BAD_REQUEST',
            'code': 'ERR_INVALID_REQUEST',
            'message': 'sync_session_id parametresi zorunludur.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final session = await (db.select(db.productSyncSessions)
            ..where((s) => s.id.equals(syncSessionId) & s.deviceId.equals(deviceId)))
          .getSingleOrNull();

      if (session == null) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'BAD_REQUEST',
            'code': 'ERR_INVALID_SYNC_SESSION',
            'message': 'Geçersiz veya bu cihaza ait olmayan senkronizasyon oturumu: $syncSessionId',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Idempotency: Eğer bu sync_session_id daha önce onaylanmışsa güvenle 200 OK dön
      if (session.isAcknowledged) {
        return Response.ok(
          jsonEncode({
            'status': 'ALREADY_ACKNOWLEDGED',
            'sync_session_id': syncSessionId,
            'synced_at': session.syncedAt.toIso8601String(),
            'acknowledged_at': session.acknowledgedAt?.toIso8601String(),
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final ackTime = DateTime.now();
      await writeQueue.enqueue(() async {
        await (db.update(db.productSyncSessions)..where((s) => s.id.equals(syncSessionId))).write(
              ProductSyncSessionsCompanion(
                isAcknowledged: const Value(true),
                acknowledgedAt: Value(ackTime),
              ),
            );

        final currentDev = await (db.select(db.devices)..where((d) => d.deviceId.equals(deviceId))).getSingleOrNull();
        final currentLastSync = currentDev?.lastProductSyncAt;
        if (currentLastSync == null || session.syncedAt.isAfter(currentLastSync)) {
          await (db.update(db.devices)..where((d) => d.deviceId.equals(deviceId))).write(
                DevicesCompanion(
                  lastProductSyncAt: Value(session.syncedAt),
                ),
              );
        }
      });

      return Response.ok(
        jsonEncode({
          'status': 'ACKNOWLEDGED',
          'sync_session_id': syncSessionId,
          'synced_at': session.syncedAt.toIso8601String(),
          'acknowledged_at': ackTime.toIso8601String(),
        }),
        headers: {'content-type': 'application/json'},
      );
    });


    // 5. Atomik Satış ve Stok Düşümü (Idempotent)
    _router.post('/api/v1/sales', (Request req) async {
      // device_id ASLA istemci payload'ından alınmaz; kimliği doğrulanmış request context'ten alınır
      final deviceId = req.context['authenticated_device_id'] as String;
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;

      final rawClientSeq = body['client_seq'];
      if (rawClientSeq is! int || rawClientSeq <= 0) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'BAD_REQUEST',
            'code': 'ERR_INVALID_CLIENT_SEQ',
            'message': 'client_seq pozitif bir tamsayı (> 0) olmalıdır.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }
      final clientSeq = rawClientSeq;

      final rawTotalAmount = body['total_amount'];
      if (rawTotalAmount is! int || rawTotalAmount <= 0 || rawTotalAmount > 100000000000) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'BAD_REQUEST',
            'code': 'ERR_INVALID_TOTAL_AMOUNT',
            'message': 'total_amount pozitif ve geçerli bir tamsayı olmalıdır.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }
      final totalAmount = rawTotalAmount;

      final rawItems = body['items'];
      if (rawItems is! List || rawItems.isEmpty) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'BAD_REQUEST',
            'code': 'ERR_INVALID_ITEMS',
            'message': 'Satış en az bir kalem içermelidir.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }
      final items = rawItems;

      final operationId = body['operation_id'] as String;
      final idempotencyKey = '$deviceId:$clientSeq';
      final paymentMethod = body['payment_method'] as String? ?? 'CASH';
      final incomingHash = computeSaleRequestHash(body);

      // A. Önce Idempotency kontrolü (Inbox defteri)
      final existingOp = await (db.select(db.processedOperations)
            ..where((o) => o.idempotencyKey.equals(idempotencyKey)))
          .getSingleOrNull();

      if (existingOp != null) {
        final cachedJson = jsonDecode(existingOp.resultPayload) as Map<String, dynamic>;
        final cachedHash = cachedJson['__request_hash'] as String?;
        final isMismatch = (cachedHash != null && cachedHash != incomingHash) ||
            (cachedHash == null && cachedJson['total_amount'] != totalAmount);

        if (isMismatch) {
          return Response(
            409,
            body: jsonEncode({
              'error': 'CONFLICT',
              'code': 'ERR_IDEMPOTENCY_PAYLOAD_MISMATCH',
              'message': 'Aynı idempotency key ($idempotencyKey) farklı bir işlem yükü ile tekrar gönderilemez.',
              'idempotency_key': idempotencyKey,
            }),
            headers: {'content-type': 'application/json'},
          );
        }

        return Response.ok(
          existingOp.resultPayload,
          headers: {
            'content-type': 'application/json',
            'x-mms-idempotent-replay': 'true',
          },
        );
      }

      // B. Yeni işlem: Tekil yazıcı kuyruğunda atomik transaction işlet
      try {
        final result = await writeQueue.enqueue(() async {
          return await db.transaction(() async {
            final checkAgain = await (db.select(db.processedOperations)
                  ..where((o) => o.idempotencyKey.equals(idempotencyKey)))
                .getSingleOrNull();
            if (checkAgain != null) {
              final checkJson = jsonDecode(checkAgain.resultPayload) as Map<String, dynamic>;
              final checkHash = checkJson['__request_hash'] as String?;
              final isMismatch = (checkHash != null && checkHash != incomingHash) ||
                  (checkHash == null && checkJson['total_amount'] != totalAmount);
              if (isMismatch) {
                throw _IdempotencyConflictException(idempotencyKey);
              }
              return checkJson;
            }

            int calculatedTotalAmount = 0;
            final itemValidations = <Map<String, dynamic>>[];

            for (final item in items) {
              if (item is! Map<String, dynamic>) {
                throw _ValidationException(400, 'ERR_INVALID_ITEM_FORMAT', 'Kalem formatı geçersiz.');
              }
              final pId = item['product_id'] as String?;
              final qty = item['quantity'] as int?;
              final uPrice = item['unit_price'] as int?;
              final tPrice = item['total_price'] as int?;
              final priceVersionId = item['price_version_id'] as String?;

              if (pId == null || pId.isEmpty) {
                throw _ValidationException(400, 'ERR_INVALID_PRODUCT_ID', 'Geçersiz ürün kimliği.');
              }
              if (qty == null || qty <= 0 || qty > 1000000000) {
                throw _ValidationException(400, 'ERR_INVALID_QUANTITY', 'Miktar pozitif ve geçerli bir tamsayı olmalıdır (> 0): $qty');
              }
              if (uPrice == null || uPrice < 0 || uPrice > 100000000000) {
                throw _ValidationException(400, 'ERR_INVALID_PRICE', 'Birim fiyat negatif veya aşırı büyük olamaz: $uPrice');
              }
              if (tPrice == null || tPrice < 0 || tPrice > 9223372036854775807) {
                throw _ValidationException(400, 'ERR_INVALID_TOTAL_PRICE', 'Satır tutarı negatif olamaz: $tPrice');
              }

              // S5A-3: Çarpım öncesi Integer Overflow kontrolü (Dart 64-bit int)
              const int maxSafeInt = 9223372036854775807;
              if (uPrice > 0 && qty > (maxSafeInt - 500) ~/ uPrice) {
                throw _ValidationException(400, 'ERR_INTEGER_OVERFLOW', 'Birim fiyat ve miktar çarpımı güvenli tamsayı sınırını aşıyor.');
              }

              final product = await (db.select(db.products)..where((p) => p.id.equals(pId))).getSingleOrNull();
              if (product == null) {
                throw StateError('Ürün bulunamadı: $pId. Satış transactionı iptal edildi.');
              }

              // S5A-3 (Topic 1): Fiyat Snapshot ve Fiyat Sürümü Doğrulaması
              if (priceVersionId == null || priceVersionId == product.priceVersionId) {
                // İstemci güncel fiyat sürümünü veya varsayılanı kullanıyorsa güncel fiyatla birebir eşleşmeli
                if (uPrice != product.price) {
                  throw _ValidationException(
                    400,
                    'ERR_UNRECOGNIZED_PRICE',
                    'Ürün ($pId) fiyatı ($uPrice) geçerli fiyat sürümü (${product.price}) ile uyuşmuyor.',
                  );
                }
              } else {
                // Belirtilen fiyat sürümü için geçmiş fiyat defteri doğrulaması
                final historyMatch = await (db.select(db.productPriceHistories)
                      ..where((h) => h.id.equals(priceVersionId) & h.productId.equals(pId)))
                    .getSingleOrNull();

                if (historyMatch == null) {
                  throw _ValidationException(
                    400,
                    'ERR_UNRECOGNIZED_PRICE_VERSION',
                    'Bilinmeyen veya ürünle eşleşmeyen fiyat sürümü: $priceVersionId (Ürün: $pId)',
                  );
                }

                if (uPrice != historyMatch.price) {
                  throw _ValidationException(
                    400,
                    'ERR_PRICE_MISMATCH',
                    'Ürün ($pId) fiyatı ($uPrice) belirtilen fiyat sürümü (${historyMatch.price}) ile uyuşmuyor.',
                  );
                }

                // Cihazın bu fiyat sürümünü kullanabilirliğini doğrula:
                // Cihazın son ürün senkronizasyon zamanı, fiyatın geçerlilik bitişinden (validUntil) sonra ise bu sürümü kullanamaz!
                final device = await (db.select(db.devices)..where((d) => d.deviceId.equals(deviceId))).getSingleOrNull();
                if (historyMatch.validUntil != null && device != null && device.lastProductSyncAt != null) {
                  if (!device.lastProductSyncAt!.isBefore(historyMatch.validUntil!)) {
                    throw _ValidationException(
                      400,
                      'ERR_PRICE_VERSION_EXPIRED_FOR_DEVICE',
                      'Fiyat sürümü ($priceVersionId) bu cihaz için geçerli değildir; cihaz daha yeni bir ürün senkronizasyonu almıştır.',
                    );
                  }
                }
              }

              // S5A-3 (Topic 3): Tek Miktar Sözleşmesi — Miktar her zaman scale=1000'dir.
              // Geriye uyumluluk veya tahmin mantığı olmaksızın katı standart sözleşme formülü:
              final expectedTotalPrice = ((uPrice * qty) + 500) ~/ 1000;
              if (tPrice != expectedTotalPrice) {
                throw _ValidationException(
                  400,
                  'ERR_ITEM_TOTAL_MISMATCH',
                  'Satır tutarı hatalı. Gönderilen: $tPrice, beklenen (scale=1000): $expectedTotalPrice',
                );
              }

              // Toplam sepet tutarı ekleme öncesi overflow kontrolü
              if (calculatedTotalAmount > maxSafeInt - tPrice) {
                throw _ValidationException(400, 'ERR_INTEGER_OVERFLOW', 'Toplam sepet tutarı güvenli tamsayı sınırını aşıyor.');
              }
              calculatedTotalAmount += tPrice;

              // Birim ve Stok Dönüşümü (scale=1000 milli-birim)
              final num = product.conversionFactorNumerator;
              final den = product.conversionFactorDenominator;
              if (num <= 0 || den <= 0) {
                throw StateError('Geçersiz dönüşüm katsayısı ($num / $den): ${product.name}');
              }

              // Çarpım öncesi overflow kontrolü
              if (num > 0 && qty > maxSafeInt ~/ num) {
                throw _ValidationException(400, 'ERR_INTEGER_OVERFLOW', 'Miktar ve birim katsayısı çarpımı güvenli tamsayı sınırını aşıyor.');
              }

              final prodMilli = qty * num;
              if (prodMilli % den != 0) {
                throw _ValidationException(
                  400,
                  'ERR_UNIT_CONVERSION_PRECISION_LOSS',
                  'Miktar ($qty) ürün stok birimine (${product.stockUnit}) kayıpsız dönüştürülemiyor.',
                );
              }
              final stockDelta = prodMilli ~/ den;

              itemValidations.add({
                'product': product,
                'pId': pId,
                'qty': qty,
                'uPrice': uPrice,
                'tPrice': tPrice,
                'stockDelta': stockDelta,
              });
            }

            // Toplam sepet tutarı kontrolü
            if (calculatedTotalAmount != totalAmount) {
              throw _ValidationException(
                400,
                'ERR_TOTAL_AMOUNT_MISMATCH',
                'Sepet toplam tutarı hatalı. Gönderilen: $totalAmount, satır toplamları: $calculatedTotalAmount',
              );
            }

            final saleId = 'sale_${DateTime.now().microsecondsSinceEpoch}';

            await db.into(db.sales).insert(
                  SalesCompanion(
                    id: Value(saleId),
                    deviceId: Value(deviceId),
                    clientSeq: Value(clientSeq),
                    totalAmount: Value(totalAmount),
                    paymentMethod: Value(paymentMethod),
                  ),
                );

            final simulatedDelayMs = body['simulated_delay_ms'] as int? ?? 0;
            if (simulatedDelayMs > 0) {
              await Future.delayed(Duration(milliseconds: simulatedDelayMs));
            }

            final updatedStocks = <String, int>{};
            for (final item in itemValidations) {
              final product = item['product'] as Product;
              final pId = item['pId'] as String;
              final qty = item['qty'] as int;
              final uPrice = item['uPrice'] as int;
              final tPrice = item['tPrice'] as int;
              final stockDelta = item['stockDelta'] as int;

              await db.into(db.saleItems).insert(
                    SaleItemsCompanion(
                      id: Value('item_${DateTime.now().microsecondsSinceEpoch}_$pId'),
                      saleId: Value(saleId),
                      productId: Value(pId),
                      quantity: Value(qty),
                      unitPrice: Value(uPrice),
                      totalPrice: Value(tPrice),
                    ),
                  );

              await db.into(db.stockMovements).insert(
                    StockMovementsCompanion(
                      id: Value('sm_${DateTime.now().microsecondsSinceEpoch}_$pId'),
                      productId: Value(pId),
                      quantity: Value(-stockDelta),
                      unit: Value(product.stockUnit),
                      movementType: const Value('SATIS'),
                      referenceId: Value(saleId),
                    ),
                  );

              // S5A-2: Fiziksel satış stok yetersizliği nedeniyle ASLA reddedilmez;
              // eksiye düşebilir ve stok hareketi negatif olarak kaydedilir.
              final currentStock = product.stock;
              final newStock = currentStock - stockDelta;

              await (db.update(db.products)..where((p) => p.id.equals(pId)))
                  .write(ProductsCompanion(stock: Value(newStock)));
              updatedStocks[pId] = newStock;
            }

            final responsePayload = {
              'status': 'COMMITTED',
              'sale_id': saleId,
              'device_id': deviceId,
              'client_seq': clientSeq,
              'total_amount': totalAmount,
              'updated_stocks': updatedStocks,
              'committed_at': DateTime.now().toIso8601String(),
              '__request_hash': incomingHash,
            };

            await db.into(db.processedOperations).insert(
                  ProcessedOperationsCompanion(
                    operationId: Value(operationId),
                    deviceId: Value(deviceId),
                    idempotencyKey: Value(idempotencyKey),
                    resultPayload: Value(jsonEncode(responsePayload)),
                  ),
                );

            return responsePayload;
          });
        });

        // S5A-2: Commit-before-ACK (Drift SQLite transaction tamamlandıktan sonra 201 Created döner)
        return Response(
          201,
          body: jsonEncode(result),
          headers: {'content-type': 'application/json'},
        );
      } on _IdempotencyConflictException catch (e) {
        return Response(
          409,
          body: jsonEncode({
            'error': 'CONFLICT',
            'code': 'ERR_IDEMPOTENCY_PAYLOAD_MISMATCH',
            'message': 'Aynı idempotency key (${e.idempotencyKey}) farklı bir işlem yükü ile tekrar gönderilemez.',
            'idempotency_key': e.idempotencyKey,
          }),
          headers: {'content-type': 'application/json'},
        );
      } on _ValidationException catch (e) {
        return Response(
          e.statusCode,
          body: jsonEncode({
            'error': 'BAD_REQUEST',
            'code': e.code,
            'message': e.message,
          }),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        stderr.writeln('[ERROR] Satış transaction hatası: ${e.runtimeType} -> $e');
        return Response.internalServerError(
          body: jsonEncode({
            'error': 'TRANSACTION_FAILED',
            'code': 'ERR_TRANSACTION_FAILED',
            'message': 'İşlem sunucu hatası nedeniyle tamamlanamadı.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }
    });

    // 6. Canlı Snapshot / Yedekleme Uç Noktası (VACUUM INTO - Hardened & Çakışma Korumalı)
    _router.post('/api/v1/backup/snapshot', (Request req) async {
      final bodyStr = await req.readAsString();
      Map<String, dynamic> body = {};
      if (bodyStr.isNotEmpty) {
        try {
          body = jsonDecode(bodyStr) as Map<String, dynamic>;
        } catch (_) {}
      }

      // SQL Injection karakter kontrolü (Şüpheli karakterler anında 400 ile reddedilir)
      if (body.containsKey('target_path')) {
        final clientPath = body['target_path']?.toString() ?? '';
        if (clientPath.contains("'") ||
            clientPath.contains(';') ||
            clientPath.contains('--') ||
            clientPath.contains('\x00')) {
          return Response(
            400,
            body: jsonEncode({
              'error': 'INVALID_REQUEST',
              'code': 'ERR_MALICIOUS_INPUT',
              'message': 'Geçersiz yedekleme parametresi.',
            }),
            headers: {'content-type': 'application/json'},
          );
        }
      }

      // Güvenlik Kuralı: İstemcinin verdiği keyfi dosya yolu KESİNLİKLE kabul edilmez.
      // Dosya yolu sunucu tarafında sabit ve korumalı dizinde üretilir.
      final targetDir = Directory(backupDirectory ?? p.join(Directory.current.path, 'backups'));
      if (!targetDir.existsSync()) {
        targetDir.createSync(recursive: true);
      }

      // Eşzamanlı isteklerde çakışmayı ve üzerine yazmayı önleyen benzersiz dosya yolu
      final safeBackupPath = _generateUniqueBackupPath(targetDir);

      await writeQueue.enqueue(() async {
        final escapedPath = safeBackupPath.replaceAll("'", "''");
        await db.customStatement("VACUUM INTO '$escapedPath';");
      });

      return Response.ok(
        jsonEncode({
          'status': 'SUCCESS',
          'backup_path': safeBackupPath,
          'timestamp': DateTime.now().toIso8601String(),
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    // 6.1. S5A-4: Merkezi Veritabanı Şifreli Yedekleme (Encrypted Backup with Manifest)
    _router.post('/api/v1/admin/backup', (Request req) async {
      final providedAdminSecret = req.headers['x-mms-admin-secret'] ?? '';
      final effectiveAdminSecret = adminSecret ?? Platform.environment['ADMIN_SECRET'] ?? 'adm_sec';

      if (providedAdminSecret.isEmpty ||
          !_constantTimeEquals(utf8.encode(providedAdminSecret), utf8.encode(effectiveAdminSecret))) {
        return Response.forbidden(
          jsonEncode({
            'error': 'FORBIDDEN',
            'code': 'ERR_INVALID_ADMIN_SECRET',
            'message': 'Yedekleme işlemi için geçerli bir admin secret gereklidir.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final bodyStr = await req.readAsString();
      Map<String, dynamic> body = {};
      if (bodyStr.isNotEmpty) {
        try {
          body = jsonDecode(bodyStr) as Map<String, dynamic>;
        } catch (_) {}
      }

      final targetDir = Directory(backupDirectory ?? p.join(Directory.current.path, 'backups'));
      final storage = LocalStorageProvider(targetDir);
      final backupPassword = body['backup_password'] as String? ?? pepperManager.pepper;
      final isMonthly = body['is_monthly_archive'] as bool? ?? false;

      final targetLiveDb = dbFile ?? File(p.join(Directory.current.path, 'market_master.db'));

      try {
        final result = await DatabaseBackupEngine.createBackup(
          liveDbFile: targetLiveDb,
          executeVacuumInto: (snapPath) async {
            await writeQueue.enqueue(() async {
              final escaped = snapPath.replaceAll("'", "''");
              await db.customStatement("VACUUM INTO '$escaped';");
            });
          },
          deviceId: 'SERVER_HUB',
          tenantId: 'tenant_default',
          storeId: 'store_main',
          databaseType: DatabaseType.centralMaster,
          schemaVersion: 1,
          appVersion: '1.0.0',
          backupPassword: backupPassword,
          storageProvider: storage,
          isMonthlyArchive: isMonthly,
        );

        return Response.ok(
          jsonEncode({
            'status': 'SUCCESS',
            'backup_id': result.backupId,
            'manifest': result.manifest.toJson(),
            'created_at': result.createdAt.toIso8601String(),
          }),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({
            'error': 'BACKUP_FAILED',
            'message': e.toString(),
          }),
          headers: {'content-type': 'application/json'},
        );
      }
    });

    // 6.2. S5A-4: Yedekleri Listeleme
    _router.get('/api/v1/admin/backups', (Request req) async {
      final providedAdminSecret = req.headers['x-mms-admin-secret'] ?? '';
      final effectiveAdminSecret = adminSecret ?? Platform.environment['ADMIN_SECRET'] ?? 'adm_sec';

      if (providedAdminSecret.isEmpty ||
          !_constantTimeEquals(utf8.encode(providedAdminSecret), utf8.encode(effectiveAdminSecret))) {
        return Response.forbidden(
          jsonEncode({
            'error': 'FORBIDDEN',
            'code': 'ERR_INVALID_ADMIN_SECRET',
            'message': 'Admin secret gereklidir.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final targetDir = Directory(backupDirectory ?? p.join(Directory.current.path, 'backups'));
      final storage = LocalStorageProvider(targetDir);
      final backups = await storage.listBackups();

      return Response.ok(
        jsonEncode({
          'status': 'SUCCESS',
          'count': backups.length,
          'backups': backups.map((b) => b.manifest.toJson()).toList(),
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    // 6.3. S5A-4: Kontrollü ve Koruyucu Yedekli Geri Yükleme (Restore)
    _router.post('/api/v1/admin/restore', (Request req) async {
      final providedAdminSecret = req.headers['x-mms-admin-secret'] ?? '';
      final effectiveAdminSecret = adminSecret ?? Platform.environment['ADMIN_SECRET'] ?? 'adm_sec';

      if (providedAdminSecret.isEmpty ||
          !_constantTimeEquals(utf8.encode(providedAdminSecret), utf8.encode(effectiveAdminSecret))) {
        return Response.forbidden(
          jsonEncode({
            'error': 'FORBIDDEN',
            'code': 'ERR_INVALID_ADMIN_SECRET',
            'message': 'Geri yükleme işlemi için geçerli bir admin secret gereklidir.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final backupId = body['backup_id'] as String?;
      final backupPassword = body['backup_password'] as String? ?? pepperManager.pepper;

      if (backupId == null || backupId.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'BAD_REQUEST', 'message': 'backup_id parametresi zorunludur.'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final targetDir = Directory(backupDirectory ?? p.join(Directory.current.path, 'backups'));
      final storage = LocalStorageProvider(targetDir);
      final safetyDir = Directory(p.join(targetDir.path, 'safety_snapshots'));
      final targetLiveDb = dbFile ?? File(p.join(Directory.current.path, 'market_master.db'));

      try {
        final result = await DatabaseBackupEngine.restoreBackup(
          backupId: backupId,
          liveDbFile: targetLiveDb,
          backupPassword: backupPassword,
          storageProvider: storage,
          expectedDeviceId: 'SERVER_HUB',
          expectedTenantId: 'tenant_default',
          expectedDatabaseType: DatabaseType.centralMaster,
          currentSchemaVersion: 1,
          minSupportedSchemaVersion: 1,
          pauseLiveDb: () async {
            // 1. Yeni API işlemlerini geçici olarak durdur ve devam edenlerin tamamlanmasını bekle
            await lifecycle.admissionGate.pauseForMaintenance(allowedRemaining: 1);
            // 2. Devam eden yazma kuyruğu işlerinin bitmesini bekle
            await writeQueue.pauseForMaintenance();
            // 3. SQLite WAL checkpoint yap ve bağlantıyı güvenle kapat
            try {
              await db.checkpointWal(mode: 'TRUNCATE');
            } catch (_) {}
            await db.close();
          },
          resumeLiveDb: () async {
            // 4. Veritabanı bağlantısını yeniden aç
            this.db = SpikeDatabase(targetLiveDb);
            lifecycle.db = this.db;
            // 5. Yazma kuyruğunu ve API kabul kapısını yeniden aç
            writeQueue.resumeAfterMaintenance();
            lifecycle.admissionGate.resumeAfterMaintenance();
          },
          safetyBackupDir: safetyDir,
        );

        return Response.ok(
          jsonEncode({
            'status': 'RESTORED',
            'backup_id': result.backupId,
            'safety_backup_path': result.safetyBackupPath,
            'restored_at': result.restoredAt.toIso8601String(),
          }),
          headers: {'content-type': 'application/json'},
        );
      } on BackupException catch (e) {
        return Response(
          400,
          body: jsonEncode({
            'error': 'RESTORE_FAILED',
            'code': e.code,
            'message': e.message,
          }),
          headers: {'content-type': 'application/json'},
        );
      } catch (e) {
        return Response.internalServerError(
          body: jsonEncode({
            'error': 'INTERNAL_ERROR',
            'message': e.toString(),
          }),
          headers: {'content-type': 'application/json'},
        );
      }
    });

    // 6.4. S5A-4: Saklama Süresi Temizliği (Retention Prune)
    _router.post('/api/v1/admin/backup/prune', (Request req) async {
      final providedAdminSecret = req.headers['x-mms-admin-secret'] ?? '';
      final effectiveAdminSecret = adminSecret ?? Platform.environment['ADMIN_SECRET'] ?? 'adm_sec';

      if (providedAdminSecret.isEmpty ||
          !_constantTimeEquals(utf8.encode(providedAdminSecret), utf8.encode(effectiveAdminSecret))) {
        return Response.forbidden(
          jsonEncode({
            'error': 'FORBIDDEN',
            'code': 'ERR_INVALID_ADMIN_SECRET',
            'message': 'Admin secret gereklidir.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final targetDir = Directory(backupDirectory ?? p.join(Directory.current.path, 'backups'));
      final storage = LocalStorageProvider(targetDir);
      final pruned = await const RetentionPolicyManager().executePruning(storage);

      return Response.ok(
        jsonEncode({
          'status': 'PRUNED',
          'count': pruned.length,
          'pruned_backup_ids': pruned,
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    // 7. Kuyruk Metrikleri
    _router.get('/api/v1/metrics', (Request req) async {
      return Response.ok(
        jsonEncode({
          'queue_metrics': writeQueue.metrics.toJson(),
          'timestamp': DateTime.now().toIso8601String(),
        }),
        headers: {'content-type': 'application/json'},
      );
    });


    // 8. Kontrollü Kapanma Uç Noktası (Graceful Shutdown - Loopback ve Ayrı Admin Secret Korumalı)
    _router.post('/api/v1/admin/shutdown', (Request req) async {
      // A. Loopback Kontrolü (IPv4 ve IPv6)
      final connectionInfo = req.context['shelf.io.connection_info'] as HttpConnectionInfo?;
      if (connectionInfo != null) {
        final remoteAddr = connectionInfo.remoteAddress;
        final isLoopback = remoteAddr.isLoopback ||
            remoteAddr.address == '127.0.0.1' ||
            remoteAddr.address == '::1' ||
            remoteAddr.address == '0:0:0:0:0:0:0:1' ||
            remoteAddr.address == '::ffff:127.0.0.1';

        if (!isLoopback) {
          return Response.forbidden(
            jsonEncode({
              'error': 'FORBIDDEN',
              'code': 'ERR_LOOPBACK_REQUIRED',
              'message': 'Shutdown uç noktasına yalnızca yerel makineden (loopback) erişilebilir.',
            }),
            headers: {'content-type': 'application/json'},
          );
        }
      }

      // B. Güvenli Admin Secret Yapılandırma Kontrolü
      final effectiveAdminSecret = adminSecret ?? Platform.environment['ADMIN_SECRET'];
      if (effectiveAdminSecret == null || effectiveAdminSecret.isEmpty) {
        return Response(
          503,
          body: jsonEncode({
            'error': 'SHUTDOWN_DISABLED',
            'code': 'ERR_SHUTDOWN_NOT_CONFIGURED',
            'message': 'Admin shutdown özelliği yapılandırılmamış ve güvenlik nedeniyle devre dışıdır.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // C. Admin Secret Yetkilendirmesi (Normal cihaz token'ları yetkisizdir)
      final providedAdminSecret = req.headers['x-admin-secret'] ??
          (req.headers['authorization']?.startsWith('Bearer ') == true
              ? req.headers['authorization']!.substring(7).trim()
              : null);

      if (providedAdminSecret == null || providedAdminSecret.isEmpty) {
        return Response(
          401,
          body: jsonEncode({
            'error': 'UNAUTHORIZED',
            'code': 'ERR_ADMIN_SECRET_REQUIRED',
            'message': 'Shutdown işlemi için admin secret gereklidir.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Sabit zamanlı karşılaştırma ile sırrın doğrulanması
      if (!_constantTimeEquals(utf8.encode(providedAdminSecret), utf8.encode(effectiveAdminSecret))) {
        return Response.forbidden(
          jsonEncode({
            'error': 'FORBIDDEN',
            'code': 'ERR_INVALID_ADMIN_SECRET',
            'message': 'Geçersiz admin secret. Normal cihaz tokenları ile shutdown yapılamaz.',
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Yanıtın sokete yazılması için 50 ms sonra shutdown tetikle
      Timer(const Duration(milliseconds: 50), () => lifecycle.shutdown(reason: 'Admin HTTP shutdown'));
      return Response.ok(
        jsonEncode({
          'status': 'SHUTTING_DOWN',
          'timestamp': DateTime.now().toIso8601String(),
        }),
        headers: {'content-type': 'application/json'},
      );
    });

  }

  Handler get handler {
    final pipeline = Pipeline()
        .addMiddleware(createAdmissionMiddleware(lifecycle.admissionGate))
        .addMiddleware(createSecureCorsMiddleware())
        .addMiddleware(createBodyLimitMiddleware(maxBytes: 2 * 1024 * 1024))
        .addMiddleware(createAuthMiddleware(
          db: db,
          isDraining: () => writeQueue.isDraining || !lifecycle.admissionGate.isOpen,
          pepperManager: pepperManager,
          writeQueue: writeQueue,
          requireTls: requireTls,
          publicPaths: [
            '/health',
            '/api/v1/admin/shutdown',
            '/api/v1/admin/backup',
            '/api/v1/admin/backups',
            '/api/v1/admin/restore',
            '/api/v1/admin/backup/prune',
            '/api/v1/devices/revoke',
            '/api/v1/pairing/session',
            '/api/v1/pairing/requests',
            '/api/v1/pairing/approve',
            '/api/v1/pairing/reject',
            '/api/v1/pairing/ca-cert',
            '/api/v1/pairing/request',
            '/api/v1/pairing/poll-challenge',
            '/api/v1/pairing/poll',
            '/api/v1/pairing/ack-challenge',
            '/api/v1/pairing/ack',
          ],
        ))
        .addHandler(_router.call);
    return pipeline;
  }

  Future<void> start({
    InternetAddress? address,
    int port = 8080,
    Duration cleanupInterval = const Duration(seconds: 15),
  }) async {
    // S-4: Startup reconcile - sunucu açılışında onaylanmamış yarım kalan cihazları temizle
    await PairingDeliveryBuffer.startupReconcile(db: db, writeQueue: writeQueue);

    final host = address ?? InternetAddress.anyIPv4;
    _httpServer = await shelf_io.serve(
      handler,
      host,
      port,
      securityContext: securityContext,
    );
    lifecycle.attachServer(_httpServer!);

    // FINDING-2: Periyodik teslimat zaman aşımı temizleyicisi (15-30 sn)
    _pairingCleanupTimer?.cancel();
    _pairingCleanupTimer = Timer.periodic(cleanupInterval, (_) async {
      try {
        if (!writeQueue.isDraining) {
          await pairingManager.deliveryBuffer.cleanUpExpired(
            db: db,
            writeQueue: writeQueue,
          );
        }
      } catch (e) {
        print('[WARN] Pairing delivery cleanup error: $e');
      }
    });
  }

  Future<void> stop() async {
    _pairingCleanupTimer?.cancel();
    _pairingCleanupTimer = null;
    await lifecycle.shutdown();
  }
}

void main(List<String> args) async {
  configureSqliteNative();

  int port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
  String dbPath = Platform.environment['DB_PATH'] ?? 'spike_master.db';
  String? backupDir = Platform.environment['BACKUP_DIR'];
  String? adminSecret = Platform.environment['ADMIN_SECRET'];
  String? pepperPath = Platform.environment['PEPPER_FILE'];
  String? certPath = Platform.environment['TLS_CERT'];
  String? keyPath = Platform.environment['TLS_KEY'];
  bool enableTls = Platform.environment['ENABLE_TLS'] == 'true';

  for (final arg in args) {
    if (arg.startsWith('--port=')) {
      port = int.tryParse(arg.substring(7)) ?? port;
    } else if (arg.startsWith('--db-path=')) {
      dbPath = arg.substring(10);
    } else if (arg.startsWith('--backup-dir=')) {
      backupDir = arg.substring(13);
    } else if (arg.startsWith('--admin-secret=')) {
      adminSecret = arg.substring(15);
    } else if (arg.startsWith('--pepper-file=')) {
      pepperPath = arg.substring(14);
    } else if (arg.startsWith('--cert=')) {
      certPath = arg.substring(7);
      enableTls = true;
    } else if (arg.startsWith('--key=')) {
      keyPath = arg.substring(6);
      enableTls = true;
    } else if (arg == '--tls') {
      enableTls = true;
    }
  }

  final db = SpikeDatabase(File(dbPath));
  final queue = WriteQueue();

  // PepperManager başlat
  final pepperManager = PepperManager(File(pepperPath ?? 'pepper.dpapi'));
  pepperManager.initialize();

  SecurityContext? securityContext;
  if (enableTls) {
    if (certPath == null || keyPath == null) {
      throw TlsConfigurationException('TLS etkinleştirildi ancak --cert veya --key dosyaları belirtilmedi.');
    }
    securityContext = CertificateManager.createServerSecurityContext(
      certChainPath: certPath,
      privateKeyPath: keyPath,
    );
  }

  final existingCola = await (db.select(db.products)..where((p) => p.id.equals('prod_cola'))).getSingleOrNull();
  if (existingCola == null) {
    await db.into(db.products).insert(
          ProductsCompanion(
            id: const Value('prod_cola'),
            barcode: const Value('869000000001'),
            name: const Value('Kutu Kola 330ml'),
            price: const Value(2500),
            stock: const Value(100),
          ),
        );
  }

  final server = SpikeServer(
    db: db,
    dbFile: File(dbPath),
    writeQueue: queue,
    backupDirectory: backupDir,
    adminSecret: adminSecret,
    pepperManager: pepperManager,
    securityContext: securityContext,
    requireTls: enableTls,
  );
  await server.start(port: port);

  stdout.writeln('MARKET MMS SPIKE-01 Backend çalışıyor: http://0.0.0.0:$port');
  stdout.writeln('Veritabanı: $dbPath');

  await server.lifecycle.onShutdown;
  server.stop();
  stdout.writeln('MARKET MMS SPIKE-01 Backend güvenle kapatıldı.');
  exit(server.lifecycle.exitCode);
}
