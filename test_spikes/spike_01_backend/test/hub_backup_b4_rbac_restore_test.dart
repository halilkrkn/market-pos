import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:http/http.dart' as http;
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/backup/hub_restore_service.dart';
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
    tempDir = Directory.systemTemp.createTempSync('mms_test_only_b4_rbac_');
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
        File dbFile,
        Directory backupDir,
      })> bootLiveLoopbackServer({
    ReplayProtectionService? replayService,
  }) async {
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
      ..initialize(overrideForTesting: 'pepper_b4_rbac_secret_32bytes_min');

    final server = SpikeServer(
      db: db,
      writeQueue: wq,
      dbFile: dbFile,
      backupDirectory: backupDir.path,
      pepperManager: pepper,
      adminSecret: 'admin_secret_b4_test',
      replayProtectionService: replayService,
      // Safety snapshot PBKDF2 turu yalnızca sunucu yapılandırmasından gelir (testte hızlı).
      hubRestoreSafetyKdfIterations: 1000,
    );
    final ioServer = await shelf_io.serve(
      server.handler,
      InternetAddress.loopbackIPv4,
      0,
    );
    final baseUrl = 'http://127.0.0.1:${ioServer.port}';
    return (
      db: db,
      wq: wq,
      pepper: pepper,
      server: server,
      ioServer: ioServer,
      baseUrl: baseUrl,
      dbFile: dbFile,
      backupDir: backupDir,
    );
  }

  Future<String> insertDevice(
    SpikeDatabase db,
    PepperManager pepper, {
    required String deviceId,
    required String role,
    bool isActive = true,
    bool isConfirmed = true,
  }) async {
    final rawTok = 'tok_${deviceId}_secret';
    final salt = TokenManager.generateSalt();
    final hash = TokenManager.hashToken(
      rawToken: rawTok,
      salt: salt,
      pepper: pepper.pepper,
    );
    await db.into(db.devices).insert(
          DevicesCompanion.insert(
            deviceId: deviceId,
            name: 'Cihaz $deviceId',
            tokenHash: hash,
            salt: salt,
            isActive: Value(isActive),
            isConfirmed: Value(isConfirmed),
            role: Value(role),
          ),
        );
    return rawTok;
  }

  Map<String, String> replayHeaders(DateTime nowUtc, String nonce) => {
        'x-mms-timestamp': nowUtc.toUtc().toIso8601String(),
        'x-mms-nonce': nonce,
      };

  group('Faz B-4: RBAC (OV-04), Replay Koruması & Yeni PC Restore', () {
    test('BK-022: Tek seferlik OWNER bootstrap (OV-04), ilk Android CASHIER varsayılanı ve son OWNER koruması', () async {
      final ctx = await bootLiveLoopbackServer();
      final client = http.Client();
      try {
        // 1. İlk eşleştirilen Android cihaz ASLA otomatik OWNER yapılmaz -> CASHIER olur
        final sessionMap = ctx.server.pairingManager.createSession(
          hubUrl: ctx.baseUrl,
          caFingerprint: 'AA:BB',
        );
        final privKey = BigInt.parse(
          'A1B2C3D4E5F60102030405060708090A1B2C3D4E5F60102030405060708090A1',
          radix: 16,
        );
        final pubBytes = EcdsaSignatureValidator.getPublicKeyBytes(privKey);
        ctx.server.pairingManager.registerRequest(
          sessionId: sessionMap['session_id'] as String,
          pairingSecret: sessionMap['pairing_secret'] as String,
          deviceId: 'ANDROID-FIRST-01',
          name: 'İlk Kasa Telefon',
          platform: 'android',
          clientPublicKeyBytes: pubBytes,
          keyAlgorithm: 'ECDSA_P256',
        );
        await ctx.server.pairingManager.approveSession(
          sessionId: sessionMap['session_id'] as String,
          db: ctx.db,
          writeQueue: ctx.wq,
          pepper: ctx.pepper.pepper,
        );

        final firstDevice = await (ctx.db.select(ctx.db.devices)
              ..where((d) => d.deviceId.equals('ANDROID-FIRST-01')))
            .getSingle();
        expect(firstDevice.role, equals('CASHIER'));

        // 2. Tek seferlik Hub OWNER bootstrap (`WIN-HUB-OWNER`)
        final bootResp1 = await client.post(
          Uri.parse('${ctx.baseUrl}/api/v1/admin/owner/bootstrap'),
          headers: {
            'content-type': 'application/json',
            'x-mms-admin-secret': 'admin_secret_b4_test',
          },
          body: jsonEncode({
            'device_id': 'WIN-HUB-OWNER',
            'name': 'Ana Kasa Windows',
            'register_if_missing': true,
          }),
        );
        expect(bootResp1.statusCode, equals(200));
        final bootJson = jsonDecode(bootResp1.body) as Map<String, dynamic>;
        expect(bootJson['role'], equals('OWNER'));
        final ownerToken = bootJson['token'] as String;

        // 3. İkinci bootstrap girişimi tekrar kullanılamaz -> 409 ERR_OWNER_ALREADY_BOOTSTRAPPED
        final bootResp2 = await client.post(
          Uri.parse('${ctx.baseUrl}/api/v1/admin/owner/bootstrap'),
          headers: {
            'content-type': 'application/json',
            'x-mms-admin-secret': 'admin_secret_b4_test',
          },
          body: jsonEncode({'device_id': 'ANDROID-FIRST-01'}),
        );
        expect(bootResp2.statusCode, equals(409));
        expect(jsonDecode(bootResp2.body)['code'], equals('ERR_OWNER_ALREADY_BOOTSTRAPPED'));

        // 4. Son aktif OWNER cihazı CASHIER'a düşürülemez veya iptal edilemez -> 409 ERR_LAST_OWNER_PROTECTED
        final demoteResp = await client.post(
          Uri.parse('${ctx.baseUrl}/api/v1/devices/role'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $ownerToken',
            ...replayHeaders(DateTime.now().toUtc(), 'nonce_demote_last_owner'),
          },
          body: jsonEncode({'device_id': 'WIN-HUB-OWNER', 'role': 'CASHIER'}),
        );
        expect(demoteResp.statusCode, equals(409));
        expect(jsonDecode(demoteResp.body)['code'], equals('ERR_LAST_OWNER_PROTECTED'));

        final revokeLastResp = await client.post(
          Uri.parse('${ctx.baseUrl}/api/v1/devices/revoke'),
          headers: {
            'content-type': 'application/json',
            'x-mms-admin-secret': 'admin_secret_b4_test',
          },
          body: jsonEncode({'device_id': 'WIN-HUB-OWNER'}),
        );
        expect(revokeLastResp.statusCode, equals(409));
        expect(jsonDecode(revokeLastResp.body)['code'], equals('ERR_LAST_OWNER_PROTECTED'));

        // 5. OWNER başka cihazı OWNER'a yükseltebilir, ardından birini CASHIER yapabilir
        final promoteResp = await client.post(
          Uri.parse('${ctx.baseUrl}/api/v1/devices/role'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $ownerToken',
            ...replayHeaders(DateTime.now().toUtc(), 'nonce_promote_and_01'),
          },
          body: jsonEncode({'device_id': 'ANDROID-FIRST-01', 'role': 'OWNER'}),
        );
        expect(promoteResp.statusCode, equals(200));
        final promoted = await (ctx.db.select(ctx.db.devices)
              ..where((d) => d.deviceId.equals('ANDROID-FIRST-01')))
            .getSingle();
        expect(promoted.role, equals('OWNER'));
      } finally {
        client.close();
        await ctx.ioServer.close(force: true);
        await ctx.db.close();
      }
    });

    test('BK-023: CASHIER rolü tüm Hub backup/restore/OAuth/schedule uçlarında 403 ERR_OWNER_ROLE_REQUIRED alır ve mutasyon yapamaz', () async {
      final ctx = await bootLiveLoopbackServer();
      final client = http.Client();
      try {
        final cashierToken = await insertDevice(
          ctx.db,
          ctx.pepper,
          deviceId: 'POS-CASHIER-01',
          role: 'CASHIER',
        );
        final ownerToken = await insertDevice(
          ctx.db,
          ctx.pepper,
          deviceId: 'POS-OWNER-01',
          role: 'OWNER',
        );

        final getPaths = [
          '/api/v1/backup/status',
          '/api/v1/backup/list',
          '/api/v1/backup/oauth/status',
        ];
        for (final path in getPaths) {
          final resp = await client.get(
            Uri.parse('${ctx.baseUrl}$path'),
            headers: {'authorization': 'Bearer $cashierToken'},
          );
          expect(resp.statusCode, equals(403), reason: 'GET $path');
          expect(jsonDecode(resp.body)['code'], equals('ERR_OWNER_ROLE_REQUIRED'));
        }

        final postEndpoints = [
          ('/api/v1/backup/recovery-key', {'recovery_password': 'CashierAttemptPass123!'}),
          ('/api/v1/backup/schedule', {'enabled': true}),
          ('/api/v1/backup/run', <String, dynamic>{}),
          ('/api/v1/backup/restore', {'backup_id': 'any', 'recovery_password': 'AnyPassword-2026!'}),
          ('/api/v1/backup/oauth/disconnect', <String, dynamic>{}),
          ('/api/v1/devices/role', {'device_id': 'POS-OWNER-01', 'role': 'CASHIER'}),
        ];
        var n = 0;
        for (final entry in postEndpoints) {
          n++;
          final resp = await client.post(
            Uri.parse('${ctx.baseUrl}${entry.$1}'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $cashierToken',
              ...replayHeaders(DateTime.now().toUtc(), 'nonce_cashier_$n'),
            },
            body: jsonEncode(entry.$2),
          );
          expect(resp.statusCode, equals(403), reason: 'POST ${entry.$1}');
          expect(jsonDecode(resp.body)['code'], equals('ERR_OWNER_ROLE_REQUIRED'));
        }

        // CASHIER hiçbir kurtarma anahtarı yazamamış olmalı
        expect(await ctx.server.hubRecoveryKeyStore.hasRecoveryPassword(), isFalse);

        // OWNER erişebilir
        final ownerStatus = await client.get(
          Uri.parse('${ctx.baseUrl}/api/v1/backup/status'),
          headers: {'authorization': 'Bearer $ownerToken'},
        );
        expect(ownerStatus.statusCode, equals(200));
      } finally {
        client.close();
        await ctx.ioServer.close(force: true);
        await ctx.db.close();
      }
    });

    test('BK-024: Replay koruması eksik/bayat timestamp ve yinelenen nonce isteklerini 403 ERR_REPLAY_DETECTED ile reddeder, audit yazar ve mutasyon yapmaz', () async {
      var clockUtc = DateTime.utc(2026, 11, 22, 15, 0);
      final replayService = ReplayProtectionService(clock: () => clockUtc);
      final ctx = await bootLiveLoopbackServer(replayService: replayService);
      final client = http.Client();
      try {
        final ownerToken = await insertDevice(
          ctx.db,
          ctx.pepper,
          deviceId: 'POS-OWNER-REPLAY',
          role: 'OWNER',
        );

        // 1. Bayat timestamp (> 300s) reddedilir ve key kaydedilmez
        final staleResp = await client.post(
          Uri.parse('${ctx.baseUrl}/api/v1/backup/recovery-key'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $ownerToken',
            ...replayHeaders(
              clockUtc.subtract(const Duration(seconds: 305)),
              'nonce_stale_0001',
            ),
          },
          body: jsonEncode({'recovery_password': 'StaleAttemptPass123!'}),
        );
        expect(staleResp.statusCode, equals(403));
        expect(jsonDecode(staleResp.body)['code'], equals('ERR_REPLAY_DETECTED'));
        expect(await ctx.server.hubRecoveryKeyStore.hasRecoveryPassword(), isFalse);

        // 2. Geçerli timestamp + benzersiz nonce -> kabul
        final okResp = await client.post(
          Uri.parse('${ctx.baseUrl}/api/v1/backup/recovery-key'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $ownerToken',
            ...replayHeaders(clockUtc, 'nonce_unique_0001'),
          },
          body: jsonEncode({'recovery_password': 'ValidInitialPass123!'}),
        );
        expect(okResp.statusCode, equals(200));

        // 3. Aynı nonce ikinci kez -> 403 ERR_REPLAY_DETECTED ve parola değişmez
        final replayResp = await client.post(
          Uri.parse('${ctx.baseUrl}/api/v1/backup/recovery-key'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $ownerToken',
            ...replayHeaders(clockUtc, 'nonce_unique_0001'),
          },
          body: jsonEncode({'recovery_password': 'HijackedPassword999!'}),
        );
        expect(replayResp.statusCode, equals(403));
        expect(jsonDecode(replayResp.body)['code'], equals('ERR_REPLAY_DETECTED'));
        expect(
          await ctx.server.hubRecoveryKeyStore.loadRecoveryPassword(),
          equals('ValidInitialPass123!'),
        );

        final auditRows = await (ctx.db.select(ctx.db.deviceAuditLogs)
              ..where((a) => a.action.equals('REPLAY_REJECTED')))
            .get();
        expect(auditRows.length, greaterThanOrEqualTo(2));
      } finally {
        client.close();
        await ctx.ioServer.close(force: true);
        await ctx.db.close();
      }
    });

    test('BK-025: Yeni PC Hub Restore (MMSBAK02), şifreli pre-restore safety snapshot, restore_epoch artışı ve kontrollü token geçersizleştirme', () async {
      final ctx = await bootLiveLoopbackServer();
      final client = http.Client();
      try {
        final ownerToken = await insertDevice(
          ctx.db,
          ctx.pepper,
          deviceId: 'POS-OWNER-RES',
          role: 'OWNER',
        );
        final cashierActiveToken = await insertDevice(
          ctx.db,
          ctx.pepper,
          deviceId: 'POS-CASHIER-ACTIVE',
          role: 'CASHIER',
          isActive: true,
        );
        await insertDevice(
          ctx.db,
          ctx.pepper,
          deviceId: 'POS-CASHIER-REVOKED',
          role: 'CASHIER',
          isActive: false,
          isConfirmed: false,
        );

        await ctx.db.into(ctx.db.products).insert(
              ProductsCompanion.insert(
                id: 'prod_before_snap',
                barcode: '8690001110001',
                name: 'Yedekteki Ürün',
                price: 5000,
                stock: 10000,
              ),
            );

        // Taşınabilir MMSBAK02 paketi oluştur (snapshot aşaması -> encrypt aşaması)
        const recoveryPass = 'NewPcRestorePass-2026!';
        // Yeni PC senaryosu: paket Owner tarafından Hub yedek dizinine kopyalanmıştır;
        // uzak OWNER cihazı yalnızca backup_id ile seçer (keyfi dosya yolu yasak).
        final pkgFile =
            File(p.join(ctx.backupDir.path, 'hub_backup_portable_bak_025.mmsbak'));
        final tempSnap = File(p.join(tempDir.path, 'src_snap.db'));
        await ctx.db.customStatement(
          "VACUUM INTO '${tempSnap.path.replaceAll("'", "''")}';",
        );
        final baseMan = BackupManifest(
          backupId: 'portable_bak_025',
          deviceId: ctx.server.hubId,
          tenantId: ctx.server.tenantId,
          storeId: ctx.server.storeId,
          databaseType: DatabaseType.centralMaster,
          schemaVersion: ctx.db.schemaVersion,
          appVersion: '1.0.0',
          timestamp: DateTime.now().toUtc(),
          checksum: await MmsbakV2Crypto.computeFileSha256(tempSnap),
          unencryptedSizeBytes: await tempSnap.length(),
          encryptedSizeBytes: 0,
        );
        await MmsbakV2Crypto.encryptFile(
          inputFile: tempSnap,
          outputFile: pkgFile,
          password: recoveryPass,
          manifest: baseMan,
          kdfIterations: 1000,
        );

        // Restore sonrası yedekte OLMAYACAK yeni bir ürün ekleyerek geri dönüşü kanıtla
        await ctx.db.into(ctx.db.products).insert(
              ProductsCompanion.insert(
                id: 'prod_after_snap_lost',
                barcode: '8690001110002',
                name: 'Restore Sonrası Silinecek Ürün',
                price: 9000,
                stock: 5000,
              ),
            );

        final healthBefore = jsonDecode(
          (await client.get(Uri.parse('${ctx.baseUrl}/health'))).body,
        ) as Map<String, dynamic>;
        expect(healthBefore['restore_epoch'], equals('epoch_0'));

        // GÜVENLİK: Uzak OWNER cihazı keyfi dosya yolu veremez (403), backup_id dizin
        // geçişi içeremez (400); loopback admin bile UNC/ağ yolu veremez (400).
        final remotePathResp = await client.post(
          Uri.parse('${ctx.baseUrl}/api/v1/backup/restore'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $ownerToken',
            ...replayHeaders(DateTime.now().toUtc(), 'nonce_restore_path_remote'),
          },
          body: jsonEncode({'package_path': pkgFile.path, 'recovery_password': recoveryPass}),
        );
        expect(remotePathResp.statusCode, equals(403));
        expect(jsonDecode(remotePathResp.body)['code'], equals('ERR_PACKAGE_PATH_LOOPBACK_ONLY'));

        final traversalResp = await client.post(
          Uri.parse('${ctx.baseUrl}/api/v1/backup/restore'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $ownerToken',
            ...replayHeaders(DateTime.now().toUtc(), 'nonce_restore_traversal'),
          },
          body: jsonEncode({'backup_id': r'..\..\x', 'recovery_password': recoveryPass}),
        );
        expect(traversalResp.statusCode, equals(400));
        expect(jsonDecode(traversalResp.body)['code'], equals('ERR_INVALID_BACKUP_ID'));

        final uncResp = await client.post(
          Uri.parse('${ctx.baseUrl}/api/v1/backup/restore'),
          headers: {
            'content-type': 'application/json',
            'x-mms-admin-secret': 'admin_secret_b4_test',
            ...replayHeaders(DateTime.now().toUtc(), 'nonce_restore_unc'),
          },
          body: jsonEncode({
            'package_path': r'\\attacker.invalid\share\evil.mmsbak',
            'recovery_password': recoveryPass,
          }),
        );
        expect(uncResp.statusCode, equals(400));
        expect(jsonDecode(uncResp.body)['code'], equals('ERR_INVALID_PACKAGE_PATH'));

        final restoreResp = await client.post(
          Uri.parse('${ctx.baseUrl}/api/v1/backup/restore'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $ownerToken',
            ...replayHeaders(DateTime.now().toUtc(), 'nonce_restore_025'),
          },
          body: jsonEncode({
            'backup_id': 'portable_bak_025',
            'recovery_password': recoveryPass,
          }),
        );
        expect(restoreResp.statusCode, equals(200), reason: restoreResp.body);
        final restoreBody = jsonDecode(restoreResp.body) as Map<String, dynamic>;
        expect(restoreBody['status'], equals('RESTORED'));
        expect(restoreBody['safety_backup_encrypted'], isTrue);
        final newEpoch = restoreBody['restore_epoch'] as String;
        expect(newEpoch, isNot(equals('epoch_0')));
        expect(restoreBody['invalidated_active_device_count'], equals(2));
        expect(restoreBody['preserved_revoked_device_count'], equals(1));

        // 1. Pre-restore safety snapshot şifreli .mmsbak olarak alınmış ve geri çözülebilir olmalı
        // (AUD-LOW-01: uzak OWNER yanıtında safety_backup_path yalnızca dosya adı döner)
        final safetyBackupName = restoreBody['safety_backup_path'] as String;
        expect(p.basename(safetyBackupName), equals(safetyBackupName));
        final safetyFile = File(p.join(ctx.backupDir.path, 'safety_snapshots', safetyBackupName));
        expect(safetyFile.existsSync(), isTrue);
        expect((await MmsbakV2Crypto.inspectFile(safetyFile)).formatVersion, equals(2));

        // 2. Restore sonrası DB eski ürün setine dönmüş ve /health yeni restore_epoch göstermeli
        final healthAfter = jsonDecode(
          (await client.get(Uri.parse('${ctx.baseUrl}/health'))).body,
        ) as Map<String, dynamic>;
        expect(healthAfter['restore_epoch'], equals(newEpoch));

        final prodsAfter = await ctx.server.db.select(ctx.server.db.products).get();
        expect(prodsAfter.map((e) => e.id).toList(), equals(['prod_before_snap']));

        // 3. Kontrollü token geçersizleştirme: Eski cihaz tokenları reddedilir,
        // isActive=true olan POS-CASHIER-ACTIVE allowRePair ile yeniden eşleşebilir,
        // kalıcı revoke edilen POS-CASHIER-REVOKED hâlâ DEVICE_ALREADY_REVOKED ile reddedilir!
        final oldTokenCall = await client.get(
          Uri.parse('${ctx.baseUrl}/api/v1/products'),
          headers: {'authorization': 'Bearer $cashierActiveToken'},
        );
        expect(oldTokenCall.statusCode, equals(401));

        final activeRow = await (ctx.server.db.select(ctx.server.db.devices)
              ..where((d) => d.deviceId.equals('POS-CASHIER-ACTIVE')))
            .getSingle();
        expect(activeRow.isActive, isTrue);
        expect(activeRow.isConfirmed, isFalse);

        final revokedRow = await (ctx.server.db.select(ctx.server.db.devices)
              ..where((d) => d.deviceId.equals('POS-CASHIER-REVOKED')))
            .getSingle();
        expect(revokedRow.isActive, isFalse);
      } finally {
        client.close();
        await ctx.ioServer.close(force: true);
        await ctx.server.db.close();
      }
    });

    test('BK-005: Yanlış tenant_id, store_id, database_type veya yanlış parola restore sırasında reddedilir; canlı DB korunur', () async {
      final ctx = await bootLiveLoopbackServer();
      final client = http.Client();
      try {
        final ownerToken = await insertDevice(
          ctx.db,
          ctx.pepper,
          deviceId: 'POS-OWNER-BK005',
          role: 'OWNER',
        );
        await ctx.db.into(ctx.db.products).insert(
              ProductsCompanion.insert(
                id: 'prod_live_bk005',
                barcode: '8690005000011',
                name: 'Canlı Korunan Ürün',
                price: 4200,
                stock: 9000,
              ),
            );

        final tempSnap = File(p.join(tempDir.path, 'src_bk005.db'));
        await ctx.db.customStatement(
          "VACUUM INTO '${tempSnap.path.replaceAll("'", "''")}';",
        );
        const recoveryPass = 'Bk005MismatchPass-2026!';

        Future<void> writeVariant({
          required String backupId,
          required String tenantId,
          required String storeId,
          required DatabaseType dbType,
        }) async {
          final man = BackupManifest(
            backupId: backupId,
            deviceId: ctx.server.hubId,
            tenantId: tenantId,
            storeId: storeId,
            databaseType: dbType,
            schemaVersion: ctx.db.schemaVersion,
            appVersion: '1.0.0',
            timestamp: DateTime.now().toUtc(),
            checksum: await MmsbakV2Crypto.computeFileSha256(tempSnap),
            unencryptedSizeBytes: await tempSnap.length(),
            encryptedSizeBytes: 0,
          );
          await MmsbakV2Crypto.encryptFile(
            inputFile: tempSnap,
            outputFile: File(p.join(ctx.backupDir.path, 'hub_backup_$backupId.mmsbak')),
            password: recoveryPass,
            manifest: man,
            kdfIterations: 1000,
          );
        }

        await writeVariant(
          backupId: 'bk005_wrong_tenant',
          tenantId: 'other-tenant',
          storeId: ctx.server.storeId,
          dbType: DatabaseType.centralMaster,
        );
        await writeVariant(
          backupId: 'bk005_wrong_store',
          tenantId: ctx.server.tenantId,
          storeId: 'other-store',
          dbType: DatabaseType.centralMaster,
        );
        await writeVariant(
          backupId: 'bk005_wrong_dbtype',
          tenantId: ctx.server.tenantId,
          storeId: ctx.server.storeId,
          dbType: DatabaseType.mobileLocal,
        );
        await writeVariant(
          backupId: 'bk005_valid_meta',
          tenantId: ctx.server.tenantId,
          storeId: ctx.server.storeId,
          dbType: DatabaseType.centralMaster,
        );

        Future<http.Response> attemptRestore(String backupId, String pass, String nonce) {
          return client.post(
            Uri.parse('${ctx.baseUrl}/api/v1/backup/restore'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $ownerToken',
              ...replayHeaders(DateTime.now().toUtc(), nonce),
            },
            body: jsonEncode({'backup_id': backupId, 'recovery_password': pass}),
          );
        }

        final rTenant = await attemptRestore('bk005_wrong_tenant', recoveryPass, 'n_bk005_1');
        expect(rTenant.statusCode, anyOf([400, 409]));
        expect(jsonDecode(rTenant.body)['code'], equals('ERR_TENANT_ID_MISMATCH'));

        final rStore = await attemptRestore('bk005_wrong_store', recoveryPass, 'n_bk005_2');
        expect(rStore.statusCode, anyOf([400, 409]));
        expect(jsonDecode(rStore.body)['code'], equals('ERR_STORE_ID_MISMATCH'));

        final rType = await attemptRestore('bk005_wrong_dbtype', recoveryPass, 'n_bk005_3');
        expect(rType.statusCode, anyOf([400, 409]));
        expect(jsonDecode(rType.body)['code'], equals('ERR_DATABASE_TYPE_MISMATCH'));

        final rBadPass = await attemptRestore('bk005_valid_meta', 'WrongPass-123456!', 'n_bk005_4');
        expect(rBadPass.statusCode, anyOf([400, 403, 500]));
        expect(rBadPass.statusCode, isNot(equals(200)));

        // Canlı veritabanı değişmeden kalmalıdır
        final prods = await ctx.server.db.select(ctx.server.db.products).get();
        expect(prods.map((e) => e.id).toList(), equals(['prod_live_bk005']));
      } finally {
        client.close();
        await ctx.ioServer.close(force: true);
        await ctx.server.db.close();
      }
    });

    test('BK-023: Swap sonrası reopenLiveDb başarısız olursa orijinal canlı DB geri alınır ve şifreli safety snapshot korunur', () async {
      configureSqliteNative();
      final dbFile = File(p.join(tempDir.path, 'data_bk023', 'market_master.db'));
      await dbFile.parent.create(recursive: true);
      final backupDir = Directory(p.join(tempDir.path, 'backups_bk023'));
      await backupDir.create(recursive: true);

      var liveDb = SpikeDatabase(dbFile);
      await liveDb.into(liveDb.products).insert(
            ProductsCompanion.insert(
              id: 'prod_snap_state',
              barcode: '8690023000011',
              name: 'Yedekteki Ürün',
              price: 1000,
              stock: 2000,
            ),
          );

      const recoveryPass = 'Bk023RollbackPass-2026!';
      final pkgFile = File(p.join(backupDir.path, 'hub_backup_bk023.mmsbak'));
      final tempSnap = File(p.join(tempDir.path, 'snap_bk023.db'));
      await liveDb.customStatement("VACUUM INTO '${tempSnap.path.replaceAll("'", "''")}';");
      final man = BackupManifest(
        backupId: 'bak_bk023',
        deviceId: 'HUB-BK023',
        tenantId: 't1',
        storeId: 's1',
        databaseType: DatabaseType.centralMaster,
        schemaVersion: liveDb.schemaVersion,
        appVersion: '1.0.0',
        timestamp: DateTime.now().toUtc(),
        checksum: await MmsbakV2Crypto.computeFileSha256(tempSnap),
        unencryptedSizeBytes: await tempSnap.length(),
        encryptedSizeBytes: 0,
      );
      await MmsbakV2Crypto.encryptFile(
        inputFile: tempSnap,
        outputFile: pkgFile,
        password: recoveryPass,
        manifest: man,
        kdfIterations: 1000,
      );

      // Canlı veritabanını yedeğin sonrasında değiştir (rollback bu veriyi geri getirmeli!)
      await liveDb.into(liveDb.products).insert(
            ProductsCompanion.insert(
              id: 'prod_live_must_survive_rollback',
              barcode: '8690023000028',
              name: 'Rollback İle Korunan Canlı Ürün',
              price: 7500,
              stock: 5000,
            ),
          );

      var reopenAttempts = 0;
      final lock = BackupOperationLock(File(p.join(backupDir.path, '.lock')));

      await expectLater(
        () => HubRestoreService.restoreFromEncryptedPackage(
          packageFile: pkgFile,
          recoveryPassword: recoveryPass,
          liveDbFile: dbFile,
          backupDir: backupDir,
          lock: lock,
          expectedTenantId: 't1',
          expectedStoreId: 's1',
          kdfIterations: 1000,
          pauseAndCloseLiveDb: () async {
            await liveDb.checkpointWal(mode: 'TRUNCATE');
            await liveDb.close();
          },
          reopenLiveDb: (file) async {
            reopenAttempts++;
            if (reopenAttempts == 1) {
              throw const FileSystemException('Simüle edilmiş post-swap DB açılış hatası');
            }
            liveDb = SpikeDatabase(file);
            return liveDb;
          },
        ),
        throwsA(isA<FileSystemException>()),
      );

      // Orijinal canlı ürün seti eksiksiz geri dönmüş olmalıdır
      final survivedIds = (await liveDb.select(liveDb.products).get()).map((e) => e.id).toSet();
      expect(survivedIds, containsAll(['prod_snap_state', 'prod_live_must_survive_rollback']));

      // Şifreli safety snapshot korunmuş ve geçici .pre_swap dosyası geri taşındığı için kalmamış olmalıdır
      final safetyDir = Directory(p.join(backupDir.path, 'safety_snapshots'));
      final safetyFiles = safetyDir.listSync().whereType<File>().where((f) => f.path.endsWith('.mmsbak')).toList();
      expect(safetyFiles, isNotEmpty);
      expect((await MmsbakV2Crypto.inspectFile(safetyFiles.single)).formatVersion, equals(2));
      expect(File('${dbFile.path}.pre_swap').existsSync(), isFalse);

      await liveDb.close();
    });
  });
}
