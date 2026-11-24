import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/ecdsa_signature_validator.dart';
import '../lib/security/pepper_manager.dart';
import '../lib/security/replay_protection_service.dart';
import '../lib/security/token_manager.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    tempDir = Directory.systemTemp.createTempSync('mms_test_only_s4_rbac_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<
      ({
        SpikeDatabase db,
        WriteQueue wq,
        PepperManager pepper,
        SpikeServer server,
        HttpServer ioServer,
        String baseUrl,
      })> bootServer() async {
    configureSqliteNative();
    final dbFile = File(p.join(tempDir.path, 'data', 'market_master.db'));
    await dbFile.parent.create(recursive: true);
    final backupDir = Directory(p.join(tempDir.path, 'backups'));
    final secDir = Directory(p.join(tempDir.path, 'security'));
    await secDir.create(recursive: true);

    final db = SpikeDatabase(dbFile);
    await db.customStatement('SELECT 1;');
    final wq = WriteQueue();
    final pepper = PepperManager(File(p.join(secDir.path, 'pepper.dpapi')))
      ..initialize(overrideForTesting: 'pepper_s4_rbac_secret_32bytes_min!!');

    final server = SpikeServer(
      db: db,
      writeQueue: wq,
      dbFile: dbFile,
      backupDirectory: backupDir.path,
      pepperManager: pepper,
      adminSecret: 'admin_s4_rbac_secret',
      replayProtectionService: ReplayProtectionService(),
      hubRestoreSafetyKdfIterations: 1000,
    );
    final ioServer = await shelf_io.serve(
      server.handler,
      InternetAddress.loopbackIPv4,
      0,
    );
    return (
      db: db,
      wq: wq,
      pepper: pepper,
      server: server,
      ioServer: ioServer,
      baseUrl: 'http://127.0.0.1:${ioServer.port}',
    );
  }

  Future<String> insertDevice(
    SpikeDatabase db,
    PepperManager pepper, {
    required String deviceId,
    required String role,
    bool isActive = true,
    bool isConfirmed = true,
    DateTime? expiresAt,
  }) async {
    final rawTok = 'mms_dt_s4_${deviceId}_tok';
    final salt = TokenManager.generateSalt();
    final hash = TokenManager.hashToken(
      rawToken: rawTok,
      salt: salt,
      pepper: pepper.pepper,
    );
    await db.into(db.devices).insert(
          DevicesCompanion.insert(
            deviceId: deviceId,
            name: 'Device $deviceId',
            tokenHash: hash,
            salt: salt,
            isActive: Value(isActive),
            isConfirmed: Value(isConfirmed),
            expiresAt: Value(expiresAt),
            role: Value(role),
          ),
        );
    return rawTok;
  }

  Map<String, String> authHeaders(
    String token, {
    String tenantId = SpikeServer.defaultTenantId,
    String storeId = SpikeServer.defaultStoreId,
  }) =>
      {
        'authorization': 'Bearer $token',
        'x-mms-tenant-id': tenantId,
        'x-mms-store-id': storeId,
      };

  group('AUD-MED-04 Backend: GET /api/v1/devices/me & RBAC Tek Doğruluk Kaynağı', () {
    test(
      '1. Bootstrapped OWNER, ilk eşleşen Android CASHIER, rol değişikliği ve CASHIER satış korunumu',
      () async {
        final ctx = await bootServer();
        final client = http.Client();
        try {
          // A) İlk eşleşen Android cihazı ASLA otomatik OWNER olmaz -> CASHIER
          final sess = ctx.server.pairingManager.createSession(
            hubUrl: ctx.baseUrl,
            caFingerprint: 'AA:BB',
          );
          final privKey = BigInt.parse(
            'A1B2C3D4E5F60102030405060708090A1B2C3D4E5F60102030405060708090A1',
            radix: 16,
          );
          final pubBytes = EcdsaSignatureValidator.getPublicKeyBytes(privKey);
          ctx.server.pairingManager.registerRequest(
            sessionId: sess['session_id'] as String,
            pairingSecret: sess['pairing_secret'] as String,
            deviceId: 'AND-FIRST-01',
            name: 'İlk Android',
            platform: 'android',
            clientPublicKeyBytes: pubBytes,
            keyAlgorithm: 'ECDSA_P256',
          );
          await ctx.server.pairingManager.approveSession(
            sessionId: sess['session_id'] as String,
            db: ctx.db,
            writeQueue: ctx.wq,
            pepper: ctx.pepper.pepper,
          );
          final pollCh = ctx.server.pairingManager.issuePollChallenge(
            sessionId: sess['session_id'] as String,
            pairingSecret: sess['pairing_secret'] as String,
          );
          final pollPayload = EcdsaSignatureValidator.buildCanonicalPollPayload(
            protocolVersion: '1',
            pairingSessionId: sess['session_id'] as String,
            publicKeyFingerprintBytes: sha256.convert(pubBytes).bytes,
            challengeId: pollCh.challengeId,
            challengeNonce: pollCh.challengeNonce,
          );
          final pollSig = EcdsaSignatureValidator.signPayload(
            privateKey: privKey,
            canonicalPayload: pollPayload,
          );
          final androidTok = ctx.server.pairingManager.verifyAndPollToken(
            sessionId: sess['session_id'] as String,
            pairingSecret: sess['pairing_secret'] as String,
            pollChallengeId: pollCh.challengeId,
            signatureBytes: pollSig,
          );
          // İlk Android cihazının onaylı CASHIER olarak DB'de aktif edildiğini doğrula
          await (ctx.db.update(ctx.db.devices)
                ..where((d) => d.deviceId.equals('AND-FIRST-01')))
              .write(const DevicesCompanion(isConfirmed: Value(true)));

          // Bootstrap tamamlanmadan önceki durum + CASHIER rolü sorgusu
          final andMeBeforeBoot = await client.get(
            Uri.parse('${ctx.baseUrl}/api/v1/devices/me'),
            headers: authHeaders(androidTok),
          );
          expect(andMeBeforeBoot.statusCode, equals(200));
          final andJson1 = jsonDecode(andMeBeforeBoot.body) as Map<String, dynamic>;
          expect(andJson1['device_id'], equals('AND-FIRST-01'));
          expect(andJson1['role'], equals('CASHIER'));
          expect(andJson1['owner_bootstrap_completed'], isFalse);

          // B) Windows tek seferlik OWNER bootstrap
          final bootResp = await client.post(
            Uri.parse('${ctx.baseUrl}/api/v1/admin/owner/bootstrap'),
            headers: {
              'content-type': 'application/json',
              'x-mms-admin-secret': 'admin_s4_rbac_secret',
            },
            body: jsonEncode({
              'device_id': 'WIN-HOST-01',
              'name': 'Ana Kasa Windows',
              'register_if_missing': true,
            }),
          );
          expect(bootResp.statusCode, equals(200));
          final ownerTok =
              (jsonDecode(bootResp.body) as Map<String, dynamic>)['token'] as String;

          final ownerMe = await client.get(
            Uri.parse('${ctx.baseUrl}/api/v1/devices/me'),
            headers: authHeaders(ownerTok),
          );
          expect(ownerMe.statusCode, equals(200));
          final ownerJson = jsonDecode(ownerMe.body) as Map<String, dynamic>;
          expect(ownerJson['device_id'], equals('WIN-HOST-01'));
          expect(ownerJson['role'], equals('OWNER'));
          expect(ownerJson['owner_bootstrap_completed'], isTrue);
          expect(ownerJson['restore_epoch'], equals('epoch_0'));

          // C) CASHIER doğrudan backup uçlarına erişemez (403 ERR_OWNER_ROLE_REQUIRED),
          // ancak normal satış + ürün işlemlerini sürdürebilir.
          final cashierStatusResp = await client.get(
            Uri.parse('${ctx.baseUrl}/api/v1/backup/status'),
            headers: authHeaders(androidTok),
          );
          expect(cashierStatusResp.statusCode, equals(403));
          expect(
            jsonDecode(cashierStatusResp.body)['code'],
            equals('ERR_OWNER_ROLE_REQUIRED'),
          );

          await ctx.db.into(ctx.db.products).insert(
                ProductsCompanion.insert(
                  id: 'prod_rbac_1',
                  barcode: '8690009990001',
                  name: 'Ekmek',
                  price: 1200,
                  stock: 50000,
                ),
              );
          final saleResp = await client.post(
            Uri.parse('${ctx.baseUrl}/api/v1/sales'),
            headers: {
              'content-type': 'application/json',
              ...authHeaders(androidTok),
            },
            body: jsonEncode({
              'idempotency_key': 'idem_cashier_sale_1',
              'client_seq': 1,
              'payment_method': 'CASH',
              'total_amount': 1200,
              'items': [
                {
                  'product_id': 'prod_rbac_1',
                  'product_name': 'Ekmek',
                  'quantity': 1000,
                  'unit_price': 1200,
                  'total_price': 1200,
                },
              ],
            }),
          );
          expect(saleResp.statusCode, equals(201));

          // D) Rol değişikliği: AND-FIRST-01 OWNER yapılır -> /devices/me ve /sync/device-state güncellenir
          final promoteResp = await client.post(
            Uri.parse('${ctx.baseUrl}/api/v1/devices/role'),
            headers: {
              'content-type': 'application/json',
              ...authHeaders(ownerTok),
              'x-mms-timestamp': DateTime.now().toUtc().toIso8601String(),
              'x-mms-nonce': 'nonce_s4_promote_1',
            },
            body: jsonEncode({'device_id': 'AND-FIRST-01', 'role': 'OWNER'}),
          );
          expect(promoteResp.statusCode, equals(200));

          final andMePromoted = await client.get(
            Uri.parse('${ctx.baseUrl}/api/v1/devices/me'),
            headers: authHeaders(androidTok),
          );
          expect(andMePromoted.statusCode, equals(200));
          expect(jsonDecode(andMePromoted.body)['role'], equals('OWNER'));

          final devStateResp = await client.get(
            Uri.parse('${ctx.baseUrl}/api/v1/sync/device-state'),
            headers: authHeaders(androidTok),
          );
          expect(devStateResp.statusCode, equals(200));
          expect(jsonDecode(devStateResp.body)['role'], equals('OWNER'));

          // Geri CASHIER'a düşürme -> hemen /devices/me içinde CASHIER olmalı
          final demoteResp = await client.post(
            Uri.parse('${ctx.baseUrl}/api/v1/devices/role'),
            headers: {
              'content-type': 'application/json',
              ...authHeaders(ownerTok),
              'x-mms-timestamp': DateTime.now().toUtc().toIso8601String(),
              'x-mms-nonce': 'nonce_s4_demote_1',
            },
            body: jsonEncode({'device_id': 'AND-FIRST-01', 'role': 'CASHIER'}),
          );
          expect(demoteResp.statusCode, equals(200));

          final andMeDemoted = await client.get(
            Uri.parse('${ctx.baseUrl}/api/v1/devices/me'),
            headers: authHeaders(androidTok),
          );
          expect(andMeDemoted.statusCode, equals(200));
          expect(jsonDecode(andMeDemoted.body)['role'], equals('CASHIER'));
        } finally {
          client.close();
          await ctx.ioServer.close(force: true);
          await ctx.db.close();
        }
      },
    );

    test(
      '2. Geçersiz, süresi dolmuş, iptal edilmiş token ve tenant uyuşmazlığında GET /api/v1/devices/me fail-closed reddeder',
      () async {
        final ctx = await bootServer();
        final client = http.Client();
        try {
          final expiredTok = await insertDevice(
            ctx.db,
            ctx.pepper,
            deviceId: 'WIN-EXPIRED-OWNER',
            role: 'OWNER',
            expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
          );
          final revokedTok = await insertDevice(
            ctx.db,
            ctx.pepper,
            deviceId: 'WIN-REVOKED-OWNER',
            role: 'OWNER',
            isActive: false,
          );
          final unconfirmedTok = await insertDevice(
            ctx.db,
            ctx.pepper,
            deviceId: 'WIN-UNCONF-OWNER',
            role: 'OWNER',
            isConfirmed: false,
          );
          final validTok = await insertDevice(
            ctx.db,
            ctx.pepper,
            deviceId: 'WIN-VALID-OWNER',
            role: 'OWNER',
          );

          final unauthResp = await client.get(
            Uri.parse('${ctx.baseUrl}/api/v1/devices/me'),
          );
          expect(unauthResp.statusCode, equals(401));

          final bogusResp = await client.get(
            Uri.parse('${ctx.baseUrl}/api/v1/devices/me'),
            headers: authHeaders('bogus_invalid_token'),
          );
          expect(bogusResp.statusCode, equals(401));

          final expiredResp = await client.get(
            Uri.parse('${ctx.baseUrl}/api/v1/devices/me'),
            headers: authHeaders(expiredTok),
          );
          expect(expiredResp.statusCode, equals(401));

          final revokedResp = await client.get(
            Uri.parse('${ctx.baseUrl}/api/v1/devices/me'),
            headers: authHeaders(revokedTok),
          );
          expect(revokedResp.statusCode, equals(403));

          final unconfResp = await client.get(
            Uri.parse('${ctx.baseUrl}/api/v1/devices/me'),
            headers: authHeaders(unconfirmedTok),
          );
          expect(unconfResp.statusCode, equals(403));

          final wrongTenantResp = await client.get(
            Uri.parse('${ctx.baseUrl}/api/v1/devices/me'),
            headers: authHeaders(validTok, tenantId: 'other-tenant'),
          );
          expect(wrongTenantResp.statusCode, equals(403));
          expect(
            jsonDecode(wrongTenantResp.body)['code'],
            equals('ERR_TENANT_STORE_MISMATCH'),
          );

          final missingTenantHeadersResp = await client.get(
            Uri.parse('${ctx.baseUrl}/api/v1/devices/me'),
            headers: {'authorization': 'Bearer $validTok'},
          );
          expect(missingTenantHeadersResp.statusCode, equals(403));
          expect(
            jsonDecode(missingTenantHeadersResp.body)['code'],
            equals('ERR_TENANT_STORE_REQUIRED'),
          );
        } finally {
          client.close();
          await ctx.ioServer.close(force: true);
          await ctx.db.close();
        }
      },
    );

    test(
      '3. Tüm 11 OWNER endpointi OWNER -> CASHIER düşürümünün hemen ardından CASHIER isteğini 403 ERR_OWNER_ROLE_REQUIRED ile reddeder',
      () async {
        final ctx = await bootServer();
        final client = http.Client();
        try {
          final targetTok = await insertDevice(
            ctx.db,
            ctx.pepper,
            deviceId: 'POS-TARGET-DEMOTE',
            role: 'OWNER',
          );
          final secondOwnerTok = await insertDevice(
            ctx.db,
            ctx.pepper,
            deviceId: 'POS-SECOND-OWNER',
            role: 'OWNER',
          );

          // İlk aşamada POS-TARGET-DEMOTE OWNER olarak /api/v1/backup/status okuyabilir (200)
          final okBefore = await client.get(
            Uri.parse('${ctx.baseUrl}/api/v1/backup/status'),
            headers: authHeaders(targetTok),
          );
          expect(okBefore.statusCode, equals(200));

          // İkinci OWNER tarafından anında CASHIER'a düşürülür (istemci 5 dk önbellek tutsa dahi!)
          final demoteResp = await client.post(
            Uri.parse('${ctx.baseUrl}/api/v1/devices/role'),
            headers: {
              'content-type': 'application/json',
              ...authHeaders(secondOwnerTok),
              'x-mms-timestamp': DateTime.now().toUtc().toIso8601String(),
              'x-mms-nonce': 'nonce_s4_all11_demote',
            },
            body: jsonEncode({
              'device_id': 'POS-TARGET-DEMOTE',
              'role': 'CASHIER',
            }),
          );
          expect(demoteResp.statusCode, equals(200));

          final ownerEndpoints = <(String, String)>[
            ('POST', '/api/v1/devices/role'),
            ('POST', '/api/v1/backup/oauth/connect'),
            ('GET', '/api/v1/backup/oauth/status'),
            ('POST', '/api/v1/backup/oauth/disconnect'),
            ('GET', '/api/v1/backup/status'),
            ('GET', '/api/v1/backup/list'),
            ('GET', '/api/v1/backup/drive/list'),
            ('POST', '/api/v1/backup/recovery-key'),
            ('POST', '/api/v1/backup/schedule'),
            ('POST', '/api/v1/backup/run'),
            ('POST', '/api/v1/backup/restore'),
          ];

          for (final (method, path) in ownerEndpoints) {
            final uri = Uri.parse('${ctx.baseUrl}$path');
            final hdrs = {
              'content-type': 'application/json',
              ...authHeaders(targetTok),
            };
            final resp = method == 'GET'
                ? await client.get(uri, headers: hdrs)
                : await client.post(uri, headers: hdrs, body: '{}');
            expect(
              resp.statusCode,
              equals(403),
              reason: '$method $path CASHIER için 403 dönmeliydi; ${resp.statusCode}',
            );
            final body = jsonDecode(resp.body) as Map<String, dynamic>;
            expect(
              body['code'],
              equals('ERR_OWNER_ROLE_REQUIRED'),
              reason: '$method $path ERR_OWNER_ROLE_REQUIRED dönmeliydi',
            );
          }
        } finally {
          client.close();
          await ctx.ioServer.close(force: true);
          await ctx.db.close();
        }
      },
    );
  });
}
