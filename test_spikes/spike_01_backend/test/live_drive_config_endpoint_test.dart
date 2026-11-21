import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/certificate_manager.dart';
import '../lib/security/live_drive_secret_manager.dart';
import '../lib/security/pepper_manager.dart';
import '../lib/security/tls_client_factory.dart';
import '../lib/security/token_manager.dart';

void main() {
  group('K-05: GET /api/v1/sync/live-drive-config & Admin Secret Rotation', () {
    const tenantId = 'tenant-k05';
    const storeId = 'store-k05';
    const hubId = 'HUB-K05';
    const adminSecret = 'super_admin_secret_k05_2026';

    late Directory tempDir;
    late SpikeDatabase db;
    late WriteQueue writeQueue;
    late PepperManager pepperManager;
    late LiveDriveSecretManager secretManager;
    late SpikeServer server;
    late HttpServer httpServer;

    const activeDeviceId = 'DEV-ACTIVE-01';
    const activeToken = 'tok_active_device_k05_123456';
    const revokedDeviceId = 'DEV-REVOKED-02';
    const revokedToken = 'tok_revoked_device_k05_123456';
    const unconfirmedDeviceId = 'DEV-UNCONFIRMED-03';
    const unconfirmedToken = 'tok_unconfirmed_device_k05_123456';

    Future<void> insertDevice({
      required String deviceId,
      required String rawToken,
      required bool isActive,
      required bool isConfirmed,
    }) async {
      final salt = TokenManager.generateSalt();
      final hash = TokenManager.hashToken(
        rawToken: rawToken,
        salt: salt,
        pepper: pepperManager.pepper,
      );
      await db.into(db.devices).insert(
            DevicesCompanion(
              deviceId: Value(deviceId),
              name: Value('Cihaz $deviceId'),
              tokenHash: Value(hash),
              salt: Value(salt),
              isActive: Value(isActive),
              isConfirmed: Value(isConfirmed),
            ),
          );
    }

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mms_k05_hub_test_');
      db = SpikeDatabase.forTesting(NativeDatabase.memory());
      writeQueue = WriteQueue();
      pepperManager = PepperManager(File(p.join(tempDir.path, 'pepper.dpapi')))
        ..initialize(overrideForTesting: 'test_pepper_32_chars_minimum_entropy_k05');
      secretManager = LiveDriveSecretManager(
        File(p.join(tempDir.path, 'live_drive_sync_secret.dpapi')),
      )..initialize();

      await insertDevice(
        deviceId: activeDeviceId,
        rawToken: activeToken,
        isActive: true,
        isConfirmed: true,
      );
      await insertDevice(
        deviceId: revokedDeviceId,
        rawToken: revokedToken,
        isActive: false,
        isConfirmed: true,
      );
      await insertDevice(
        deviceId: unconfirmedDeviceId,
        rawToken: unconfirmedToken,
        isActive: true,
        isConfirmed: false,
      );

      server = SpikeServer(
        db: db,
        writeQueue: writeQueue,
        adminSecret: adminSecret,
        pepperManager: pepperManager,
        liveDriveSecretManager: secretManager,
        tenantId: tenantId,
        storeId: storeId,
        hubId: hubId,
        requireTls: false,
        requireTenantStoreHeaders: true,
        allowAdminEnvFallback: false,
      );
      httpServer = await shelf_io.serve(server.handler, InternetAddress.loopbackIPv4, 0);
    });

    tearDown(() async {
      await httpServer.close(force: true);
      await db.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    Uri url(String path) => Uri.parse('http://127.0.0.1:${httpServer.port}$path');

    test('Yetkili & onaylı cihaz 200 OK, no-store, >=32-char secret ve ACTIVE/REVOKED cihaz listesi alır', () async {
      final resp = await http.get(
        url('/api/v1/sync/live-drive-config'),
        headers: {
          'Authorization': 'Bearer $activeToken',
          'X-MMS-Tenant-Id': tenantId,
          'X-MMS-Store-Id': storeId,
        },
      );

      expect(resp.statusCode, 200);
      expect(resp.headers['cache-control'], 'no-store');

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      expect(body['version'], 1);
      expect(body['tenant_id'], tenantId);
      expect(body['store_id'], storeId);
      expect(body['hub_id'], hubId);
      final secret = body['live_sync_secret'] as String;
      expect(secret.length, greaterThanOrEqualTo(32));
      expect(secret, secretManager.secret);

      final devices = (body['authorized_devices'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final byId = {for (final d in devices) d['device_id']: d};
      expect(byId[activeDeviceId]?['status'], 'ACTIVE');
      expect(byId[revokedDeviceId]?['status'], 'REVOKED');
      expect(byId[unconfirmedDeviceId]?['status'], 'REVOKED');
    });

    test('Kimliksiz (401), iptal edilmiş (403), onaysız (403) ve eksik/yanlış tenant-store (403) reddedilir', () async {
      final noAuth = await http.get(
        url('/api/v1/sync/live-drive-config'),
        headers: {'X-MMS-Tenant-Id': tenantId, 'X-MMS-Store-Id': storeId},
      );
      expect(noAuth.statusCode, 401);

      final revoked = await http.get(
        url('/api/v1/sync/live-drive-config'),
        headers: {
          'Authorization': 'Bearer $revokedToken',
          'X-MMS-Tenant-Id': tenantId,
          'X-MMS-Store-Id': storeId,
        },
      );
      expect(revoked.statusCode, 403);
      expect(jsonDecode(revoked.body)['error'], 'DEVICE_REVOKED');

      final unconfirmed = await http.get(
        url('/api/v1/sync/live-drive-config'),
        headers: {
          'Authorization': 'Bearer $unconfirmedToken',
          'X-MMS-Tenant-Id': tenantId,
          'X-MMS-Store-Id': storeId,
        },
      );
      expect(unconfirmed.statusCode, 403);
      expect(jsonDecode(unconfirmed.body)['error'], 'DEVICE_NOT_CONFIRMED');

      final missingHeaders = await http.get(
        url('/api/v1/sync/live-drive-config'),
        headers: {'Authorization': 'Bearer $activeToken'},
      );
      expect(missingHeaders.statusCode, 403);

      final wrongStore = await http.get(
        url('/api/v1/sync/live-drive-config'),
        headers: {
          'Authorization': 'Bearer $activeToken',
          'X-MMS-Tenant-Id': tenantId,
          'X-MMS-Store-Id': 'wrong-store',
        },
      );
      expect(wrongStore.statusCode, 403);
    });

    test('requireTls=true iken HTTP (426) reddedilir, HTTPS (TLS) üzerinden 200 döner', () async {
      final caKey = p.join(tempDir.path, 'ca.key');
      final caCrt = p.join(tempDir.path, 'ca.crt');
      final srvKey = p.join(tempDir.path, 'srv.key');
      final srvCrt = p.join(tempDir.path, 'srv.crt');
      CertificateManager.generateRootCa(caKeyPath: caKey, caCertPath: caCrt);
      CertificateManager.generateServerCertificate(
        caKeyPath: caKey,
        caCertPath: caCrt,
        serverKeyPath: srvKey,
        serverCertPath: srvCrt,
        sanList: const ['127.0.0.1'],
      );

      final tlsServer = SpikeServer(
        db: db,
        writeQueue: writeQueue,
        adminSecret: adminSecret,
        pepperManager: pepperManager,
        liveDriveSecretManager: secretManager,
        securityContext: CertificateManager.createServerSecurityContext(
          certChainPath: srvCrt,
          privateKeyPath: srvKey,
        ),
        requireTls: true,
        caCertPath: caCrt,
        serverCertPath: srvCrt,
        tenantId: tenantId,
        storeId: storeId,
        hubId: hubId,
        requireTenantStoreHeaders: true,
      );

      // 1. Düz HTTP sunucu arkasında requireTls: true -> 426 UPGRADE_REQUIRED
      final plainSrv = await shelf_io.serve(tlsServer.handler, InternetAddress.loopbackIPv4, 0);
      addTearDown(() => plainSrv.close(force: true));

      final plainResp = await http.get(
        Uri.parse('http://127.0.0.1:${plainSrv.port}/api/v1/sync/live-drive-config'),
        headers: {
          'Authorization': 'Bearer $activeToken',
          'X-MMS-Tenant-Id': tenantId,
          'X-MMS-Store-Id': storeId,
        },
      );
      expect(plainResp.statusCode, 426);

      // 2. Gerçek TLS (HTTPS) üzerinden -> 200 OK
      final httpsSrv = await shelf_io.serve(
        tlsServer.handler,
        InternetAddress.loopbackIPv4,
        0,
        securityContext: tlsServer.securityContext,
      );
      addTearDown(() => httpsSrv.close(force: true));

      final pinnedIo = TlsClientFactory.createPinnedClient(
        trustedRootCaBytes: File(caCrt).readAsBytesSync(),
      );
      final pinnedHttp = IOClient(pinnedIo);
      addTearDown(pinnedHttp.close);

      final tlsResp = await pinnedHttp.get(
        Uri.parse('https://127.0.0.1:${httpsSrv.port}/api/v1/sync/live-drive-config'),
        headers: {
          'Authorization': 'Bearer $activeToken',
          'X-MMS-Tenant-Id': tenantId,
          'X-MMS-Store-Id': storeId,
        },
      );
      expect(tlsResp.statusCode, 200);
      expect(jsonDecode(tlsResp.body)['live_sync_secret'], secretManager.secret);
    });

    test('POST /api/v1/admin/live-drive-secret/rotate admin sırrı doğrular, gizliyi döndürür ve audit loga düz metin yazmaz', () async {
      final beforeSecret = secretManager.secret;

      final badAdmin = await http.post(
        url('/api/v1/admin/live-drive-secret/rotate'),
        headers: {'X-MMS-Admin-Secret': 'wrong_admin_secret'},
      );
      expect(badAdmin.statusCode, 403);
      expect(secretManager.secret, beforeSecret);

      final okRotate = await http.post(
        url('/api/v1/admin/live-drive-secret/rotate'),
        headers: {'X-MMS-Admin-Secret': adminSecret},
      );
      expect(okRotate.statusCode, 200);
      expect(okRotate.body, isNot(contains(secretManager.secret)));
      expect(jsonDecode(okRotate.body)['status'], 'ROTATED');

      final afterSecret = secretManager.secret;
      expect(afterSecret, isNot(equals(beforeSecret)));
      expect(afterSecret.length, greaterThanOrEqualTo(32));

      // Disk kalıcılığı doğrulaması
      final reloaded = LiveDriveSecretManager(
        File(p.join(tempDir.path, 'live_drive_sync_secret.dpapi')),
      )..initialize();
      expect(reloaded.secret, afterSecret);

      // Cihaz ucu artık yeni gizliyi döndürmeli
      final cfgResp = await http.get(
        url('/api/v1/sync/live-drive-config'),
        headers: {
          'Authorization': 'Bearer $activeToken',
          'X-MMS-Tenant-Id': tenantId,
          'X-MMS-Store-Id': storeId,
        },
      );
      expect(cfgResp.statusCode, 200);
      expect(jsonDecode(cfgResp.body)['live_sync_secret'], afterSecret);

      // Audit log açık sır içermemeli
      final logs = await (db.select(db.deviceAuditLogs)
            ..where((l) => l.action.equals('LIVE_DRIVE_SECRET_ROTATE')))
          .get();
      expect(logs, hasLength(1));
      expect(logs.single.details, isNot(contains(beforeSecret)));
      expect(logs.single.details, isNot(contains(afterSecret)));
    });
  });
}
