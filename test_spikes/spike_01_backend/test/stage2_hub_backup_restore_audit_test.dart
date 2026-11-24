@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/backup/hub_backup_oauth_service.dart';
import '../lib/backup/hub_backup_oauth_store.dart';
import '../lib/backup/hub_backup_orchestrator.dart';
import '../lib/backup/hub_backup_state_store.dart';
import '../lib/backup/hub_recovery_key_store.dart';
import '../lib/backup/hub_snapshot_service.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/pepper_manager.dart';
import '../lib/security/token_manager.dart';

void main() {
  late Directory tempDir;
  late File dbFile;
  late Directory backupDir;
  late Directory securityDir;
  late SpikeDatabase db;
  late WriteQueue writeQueue;
  late HubBackupStateStore stateStore;
  late HubRecoveryKeyStore recoveryKeyStore;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    tempDir = Directory.systemTemp.createTempSync('mms_test_only_stage2_');
    dbFile = File(p.join(tempDir.path, 'data', 'market_master.db'));
    await dbFile.parent.create(recursive: true);
    backupDir = Directory(p.join(tempDir.path, 'backups'));
    securityDir = Directory(p.join(tempDir.path, 'security'));
    await securityDir.create(recursive: true);
    db = SpikeDatabase(dbFile);
    writeQueue = WriteQueue();
    await db.customStatement('SELECT 1;');

    stateStore = HubBackupStateStore(
      File(p.join(backupDir.path, HubBackupStateStore.defaultFileName)),
    );
    recoveryKeyStore = HubRecoveryKeyStore(
      File(p.join(securityDir.path, HubRecoveryKeyStore.defaultFileName)),
    );
    await recoveryKeyStore.saveRecoveryPassword('Stage2-Hub-Recovery-2026!');
  });

  tearDown(() async {
    await db.close();
    for (var attempt = 0; attempt < 5; attempt++) {
      if (!tempDir.existsSync()) break;
      try {
        tempDir.deleteSync(recursive: true);
        break;
      } on FileSystemException {
        if (attempt == 4) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    }
  });

  group('AUD-MED-03 & AUD-HIGH-02: HubBackupOrchestrator Alt Aşama A', () {
    test('uploadToDrive: false ayarında Drive OAuth olmadan yedek ENCRYPTED_LOCAL_READY olarak tamamlanır ve 12-durum makinesi korunur', () async {
      // Mevcut 12 durumlu makineye yeni durum eklenmemelidir
      expect(HubBackupJobState.values.length, equals(12));

      var currentLocal = DateTime(2026, 11, 24, 9, 0);
      final oauthStore = HubBackupOAuthStore(
        File(p.join(securityDir.path, HubBackupOAuthStore.defaultFileName)),
      );
      // Drive OAuth bağlantısı HİÇ YOK
      final oauthService = HubBackupOAuthService(
        store: oauthStore,
        httpClient: MockClient((_) async => http.Response('unexpected', 500)),
        clock: () => currentLocal,
      );

      var driveHttpCalls = 0;
      final orch = HubBackupOrchestrator(
        snapshotService: HubSnapshotService(
          readDb: () => db,
          writeQueue: writeQueue,
          liveDbFile: dbFile,
          backupDir: backupDir,
          hubId: 'HUB-LOCAL-ONLY',
          tenantId: 't1',
          storeId: 's1',
          appVersion: '1.0.0',
          kdfIterations: 1000,
          diskSpaceChecker: DiskSpaceChecker(freeBytesProbe: (_) async => 1 << 30),
        ),
        stateStore: stateStore,
        recoveryKeyStore: recoveryKeyStore,
        oauthService: oauthService,
        uploader: ResumableDriveUploader(
          accessTokenProvider: ({bool forceRefresh = false}) =>
              oauthService.getValidAccessToken(
                clientId: 'cid',
                forceRefresh: forceRefresh,
              ),
          httpClient: MockClient((_) async {
            driveHttpCalls++;
            return http.Response('unexpected', 500);
          }),
        ),
        operationLock: BackupOperationLock(File(p.join(backupDir.path, '.lock'))),
        readSchemaVersion: () => db.schemaVersion,
        oauthClientId: 'cid',
        localClock: () => currentLocal,
      );

      final afterConfig = await orch.configureSchedule(
        enabled: true,
        dailyHourLocal: 0,
        dailyMinuteLocal: 0,
        uploadToDrive: false,
      );

      expect(driveHttpCalls, equals(0));
      expect(afterConfig.schedule.uploadToDrive, isFalse);
      expect(afterConfig.latestJob, isNotNull);
      expect(afterConfig.latestJob!.state, equals(HubBackupJobState.encryptedLocalReady));
      expect(afterConfig.latestJob!.lastErrorCode, isNull);
      expect(afterConfig.latestJob!.encryptedPath, isNotNull);
      expect(File(afterConfig.latestJob!.encryptedPath!).existsSync(), isTrue);
      expect(afterConfig.lastCompletedDateLocal, equals('2026-11-24'));
      expect(afterConfig.lastCompletedAtUtc, isNotNull);

      // Sonraki zamanlayıcı turu aynı gün için ikinci yedeği başlatmaz
      currentLocal = DateTime(2026, 11, 24, 9, 5);
      expect(await orch.evaluateTick(), isNull);
      expect(driveHttpCalls, equals(0));

      // Ertesi gün geldiğinde dünkü tamamlanmış yerel yedek SUPERSEDED hatasına çevrilmez;
      // bugünün yerel yedeği alınır
      currentLocal = DateTime(2026, 11, 25, 0, 5);
      final day2 = await orch.evaluateTick();
      expect(day2, isNotNull);
      expect(day2!.state, equals(HubBackupJobState.encryptedLocalReady));
      final snapDay2 = await stateStore.load();
      final day1After = snapDay2.jobs.firstWhere(
        (j) => j.backupId == afterConfig.latestJob!.backupId,
      );
      expect(day1After.state, equals(HubBackupJobState.encryptedLocalReady));
      expect(day1After.lastErrorCode, isNull);
    });

    test('VERIFYING aşamasında driveFileId varken çökme sonrası recoverOnStartup transition exception atmaz ve Drive doğrulamasını tamamlar', () async {
      var currentLocal = DateTime(2026, 11, 24, 12, 0);
      final oauthStore = HubBackupOAuthStore(
        File(p.join(securityDir.path, HubBackupOAuthStore.defaultFileName)),
      );
      await oauthStore.save(HubBackupOAuthCredentials(
        accessToken: 'acc_verify_rec',
        refreshToken: 'ref_verify_rec',
        expiresAtUtc: currentLocal.toUtc().add(const Duration(hours: 1)),
        scope: 'https://www.googleapis.com/auth/drive.file',
        folderId: 'folder_hub_s2',
        folderLayout: HubBackupOAuthCredentials.hubSubfolderLayout,
        connectedAtUtc: currentLocal.toUtc(),
      ));
      final oauthService = HubBackupOAuthService(
        store: oauthStore,
        httpClient: MockClient((_) async => http.Response('{}', 200)),
        clock: () => currentLocal,
      );

      final snapSvc = HubSnapshotService(
        readDb: () => db,
        writeQueue: writeQueue,
        liveDbFile: dbFile,
        backupDir: backupDir,
        hubId: 'HUB-VERIFY-REC',
        tenantId: 't1',
        storeId: 's1',
        appVersion: '1.0.0',
        kdfIterations: 1000,
        diskSpaceChecker: DiskSpaceChecker(freeBytesProbe: (_) async => 1 << 30),
      );
      final built = await snapSvc.createEncryptedBackup(
        backupId: 'bak_verifying_crash_1',
        recoveryPassword: 'Stage2-Hub-Recovery-2026!',
        schemaVersion: db.schemaVersion,
      );
      final encBytes = await built.backupFile.readAsBytes();
      final encSha = sha256.convert(encBytes).toString();
      final encMd5 = md5.convert(encBytes).toString();

      await stateStore.upsertJob(
        HubBackupJobRecord(
          backupId: 'bak_verifying_crash_1',
          trigger: HubBackupTrigger.scheduledDaily,
          state: HubBackupJobState.verifying,
          scheduledDateLocal: '2026-11-24',
          createdAtUtc: currentLocal.toUtc(),
          updatedAtUtc: currentLocal.toUtc(),
          encryptedPath: built.backupFile.path,
          encryptedSha256: encSha,
          encryptedSizeBytes: encBytes.length,
          driveSessionUri: 'https://upload.example.com/sess_done',
          uploadedBytes: encBytes.length,
          driveFileId: 'drv_verifying_crash_1',
        ),
        schedule: const HubBackupScheduleConfig(enabled: true),
      );

      var uploadPutCalls = 0;
      final orch = HubBackupOrchestrator(
        snapshotService: snapSvc,
        stateStore: stateStore,
        recoveryKeyStore: recoveryKeyStore,
        oauthService: oauthService,
        uploader: ResumableDriveUploader(
          accessTokenProvider: ({bool forceRefresh = false}) =>
              oauthService.getValidAccessToken(
                clientId: 'cid',
                forceRefresh: forceRefresh,
              ),
          httpClient: MockClient((req) async {
            if (req.method == 'GET' &&
                req.url.path == '/drive/v3/files/drv_verifying_crash_1') {
              return http.Response(
                jsonEncode({
                  'id': 'drv_verifying_crash_1',
                  'size': encBytes.length.toString(),
                  'md5Checksum': encMd5,
                  'appProperties': {
                    'mms_backup_id': 'bak_verifying_crash_1',
                    'mms_sha256': encSha,
                  },
                }),
                200,
              );
            }
            if (req.method == 'PUT' || req.method == 'POST') {
              uploadPutCalls++;
            }
            return http.Response('Unexpected ${req.method} ${req.url}', 400);
          }),
        ),
        operationLock: BackupOperationLock(File(p.join(backupDir.path, '.lock'))),
        readSchemaVersion: () => db.schemaVersion,
        oauthClientId: 'cid',
        localClock: () => currentLocal,
      );

      final recovered = await orch.recoverOnStartup();
      expect(recovered, isNotNull);
      expect(recovered!.state, equals(HubBackupJobState.completedUploaded));
      expect(recovered.driveFileId, equals('drv_verifying_crash_1'));
      expect(
        uploadPutCalls,
        equals(0),
        reason: 'VERIFYING sonrası kurtarma dosyayı yeniden yüklememeli.',
      );
    });

    test('OAuth yenilemede geçici HTTP 503 hatası FAILED_AUTH değil RETRY_PENDING durumuna geçirir', () async {
      var currentLocal = DateTime(2026, 11, 24, 13, 0);
      final oauthStore = HubBackupOAuthStore(
        File(p.join(securityDir.path, HubBackupOAuthStore.defaultFileName)),
      );
      await oauthStore.save(HubBackupOAuthCredentials(
        accessToken: 'soon_expiring_acc',
        refreshToken: 'valid_refresh_tok',
        // 120s güvenlik payı içinde → yenileme tetiklenecek
        expiresAtUtc: currentLocal.toUtc().add(const Duration(seconds: 30)),
        scope: 'https://www.googleapis.com/auth/drive.file',
        connectedAtUtc: currentLocal.toUtc(),
      ));
      final oauthService = HubBackupOAuthService(
        store: oauthStore,
        httpClient: MockClient((req) async {
          if (req.url.toString().contains('/token')) {
            return http.Response('Service Unavailable', 503);
          }
          return http.Response('{}', 200);
        }),
        clock: () => currentLocal,
      );

      final orch = HubBackupOrchestrator(
        snapshotService: HubSnapshotService(
          readDb: () => db,
          writeQueue: writeQueue,
          liveDbFile: dbFile,
          backupDir: backupDir,
          hubId: 'HUB-OAUTH-503',
          tenantId: 't1',
          storeId: 's1',
          appVersion: '1.0.0',
          kdfIterations: 1000,
          diskSpaceChecker: DiskSpaceChecker(freeBytesProbe: (_) async => 1 << 30),
        ),
        stateStore: stateStore,
        recoveryKeyStore: recoveryKeyStore,
        oauthService: oauthService,
        uploader: ResumableDriveUploader(
          accessTokenProvider: ({bool forceRefresh = false}) =>
              oauthService.getValidAccessToken(
                clientId: 'cid',
                forceRefresh: forceRefresh,
              ),
          httpClient: MockClient((_) async => http.Response('{}', 200)),
        ),
        operationLock: BackupOperationLock(File(p.join(backupDir.path, '.lock'))),
        readSchemaVersion: () => db.schemaVersion,
        oauthClientId: 'cid',
        localClock: () => currentLocal,
      );

      final job = await orch.triggerBackup(trigger: HubBackupTrigger.manual);
      expect(job.state, equals(HubBackupJobState.retryPending));
      expect((await oauthService.getStatus()).needsReauth, isFalse);
    });
  });

  group('AUD-MED-01: Legacy /api/v1/admin/restore + restore_epoch + Token İptali + OV-03', () {
    test('POST /api/v1/admin/restore restore_epoch artırır, aktif cihaz tokenını geçersizleştirir (401), revoked cihazı korur, OV-03 uzlaştırır ve legacy_machine_key destekler', () async {
      final serverDir = Directory(p.join(tempDir.path, 'admin_restore_hub'));
      final mDbFile = File(p.join(serverDir.path, 'data', 'market_master.db'));
      await mDbFile.parent.create(recursive: true);
      final mBackupDir = Directory(p.join(serverDir.path, 'backups'));
      final mSecDir = Directory(p.join(serverDir.path, 'security'));
      await mSecDir.create(recursive: true);

      final mDb = SpikeDatabase(mDbFile);
      final mWq = WriteQueue();
      final mPepper = PepperManager(File(p.join(mSecDir.path, 'pepper.dpapi')))
        ..initialize(overrideForTesting: 'pepper_stage2_med01_32bytes_secret');
      final mKeyStore = HubRecoveryKeyStore(
        File(p.join(mSecDir.path, HubRecoveryKeyStore.defaultFileName)),
      );
      await mKeyStore.saveRecoveryPassword('Stage2-Med01-Pass-2026!');

      Future<void> seedDev(String devId, String rawTok, {bool active = true}) async {
        final salt = TokenManager.generateSalt();
        await mDb.into(mDb.devices).insert(
              DevicesCompanion.insert(
                deviceId: devId,
                name: 'Cihaz $devId',
                tokenHash: TokenManager.hashToken(
                  rawToken: rawTok,
                  salt: salt,
                  pepper: mPepper.pepper,
                ),
                salt: salt,
                isActive: Value(active),
                isConfirmed: Value(active),
                role: const Value('CASHIER'),
              ),
            );
      }

      const activeTok = 'tok_med01_active';
      await seedDev('POS-MED01-ACT', activeTok, active: true);
      await seedDev('POS-MED01-REV', 'tok_med01_rev', active: false);
      await mDb.into(mDb.products).insert(
            ProductsCompanion.insert(
              id: 'prod_med01',
              barcode: '8690011000011',
              name: 'Med01 Ürün',
              price: 1500,
              stock: 20000,
            ),
          );

      // İstemci FFI SQLite ve OV-03 hazırlığı
      final cDb = ClientDatabase(File(p.join(tempDir.path, 'client_med01.db')));
      final cRepo = ClientStorageRepository(cDb);
      await cRepo.initializeDevice('POS-MED01-ACT');
      await cRepo.upsertProducts([
        LocalProductsCompanion.insert(
          id: 'prod_med01',
          name: 'Med01 Ürün',
          barcode: const Value('8690011000011'),
          price: 1500,
          stock: 20000,
        ),
      ]);

      final srv = SpikeServer(
        db: mDb,
        dbFile: mDbFile,
        writeQueue: mWq,
        backupDirectory: mBackupDir.path,
        adminSecret: 'admin_med01_secret',
        pepperManager: mPepper,
        hubRecoveryKeyStore: mKeyStore,
        hubRestoreSafetyKdfIterations: 1000,
      );
      final ioSrv = await shelf_io.serve(srv.handler, InternetAddress.loopbackIPv4, 0);
      final baseUrl = 'http://127.0.0.1:${ioSrv.port}';
      final client = http.Client();
      try {
        // 1. Yedek al (satış öncesi)
        final backupResp = await client.post(
          Uri.parse('$baseUrl/api/v1/admin/backup'),
          headers: {
            'content-type': 'application/json',
            'x-mms-admin-secret': 'admin_med01_secret',
          },
          body: '{}',
        );
        expect(backupResp.statusCode, equals(200), reason: backupResp.body);
        final backupId = (jsonDecode(backupResp.body) as Map)['backup_id'] as String;

        // 2. Yedek sonrasında istemci 1 adet satış yapıp Hub'a senkronize etsin (SYNCED + epoch_0)
        await cRepo.createOfflineSale(
          deviceId: 'POS-MED01-ACT',
          paymentMethod: 'CASH',
          items: [CartItemInput.units('prod_med01', 1)],
        );
        final cSync1 = ClientSyncService(
          repository: cRepo,
          transport: HttpSyncTransport.forStore(
            client: client,
            tenantId: SpikeServer.defaultTenantId,
            storeId: SpikeServer.defaultStoreId,
          ),
          deviceId: 'POS-MED01-ACT',
          deviceToken: activeTok,
          hubUrl: baseUrl,
        );
        final preRestoreSync = await cSync1.syncPendingOutbox();
        expect(preRestoreSync.isCleanSuccess, isTrue);
        expect((await srv.db.select(srv.db.sales).get()), hasLength(1));

        // Yedek sonrasında geçici bir ürün daha ekle
        await srv.db.into(srv.db.products).insert(
              ProductsCompanion.insert(
                id: 'prod_med01_extra',
                barcode: '8690011000099',
                name: 'Silinecek Ürün',
                price: 5000,
                stock: 1000,
              ),
            );

        final healthBefore = jsonDecode(
          (await client.get(Uri.parse('$baseUrl/health'))).body,
        ) as Map<String, dynamic>;
        expect(healthBefore['restore_epoch'], equals('epoch_0'));

        final restoreResp = await client.post(
          Uri.parse('$baseUrl/api/v1/admin/restore'),
          headers: {
            'content-type': 'application/json',
            'x-mms-admin-secret': 'admin_med01_secret',
          },
          body: jsonEncode({'backup_id': backupId}),
        );
        expect(restoreResp.statusCode, equals(200), reason: restoreResp.body);
        final restoreBody = jsonDecode(restoreResp.body) as Map<String, dynamic>;
        expect(restoreBody['status'], equals('RESTORED'));
        expect(restoreBody['safety_backup_encrypted'], isTrue);
        final newEpoch = restoreBody['restore_epoch'] as String?;
        expect(newEpoch, isNotNull);
        expect(newEpoch, isNot(equals('epoch_0')));
        expect(restoreBody['invalidated_active_device_count'], equals(1));
        expect(restoreBody['preserved_revoked_device_count'], equals(1));

        final healthAfter = jsonDecode(
          (await client.get(Uri.parse('$baseUrl/health'))).body,
        ) as Map<String, dynamic>;
        expect(healthAfter['restore_epoch'], equals(newEpoch));

        // Eski aktif cihaz token'ı restore sonrası reddedilmelidir (401)
        final staleTokenCall = await client.get(
          Uri.parse('$baseUrl/api/v1/products'),
          headers: {
            'authorization': 'Bearer $activeTok',
            'x-mms-tenant-id': SpikeServer.defaultTenantId,
            'x-mms-store-id': SpikeServer.defaultStoreId,
          },
        );
        expect(staleTokenCall.statusCode, equals(401));

        // Revoked cihaz kalıcı olarak isActive = false kalmalıdır
        final revokedRow = await (srv.db.select(srv.db.devices)
              ..where((d) => d.deviceId.equals('POS-MED01-REV')))
            .getSingle();
        expect(revokedRow.isActive, isFalse);

        final productsAfter = await srv.db.select(srv.db.products).get();
        expect(productsAfter.map((p) => p.id).toList(), equals(['prod_med01']));
        expect(await srv.db.select(srv.db.sales).get(), isEmpty);

        // 3. Re-pairing sonrası OV-03 reconciliation kayıp SYNCED satışı yeni restore_epoch üzerinde kurtarır
        const renewedTok = 'tok_med01_renewed';
        final newSalt = TokenManager.generateSalt();
        await srv.writeQueue.enqueue(() async {
          await (srv.db.update(srv.db.devices)
                ..where((d) => d.deviceId.equals('POS-MED01-ACT')))
              .write(
            DevicesCompanion(
              tokenHash: Value(TokenManager.hashToken(
                rawToken: renewedTok,
                salt: newSalt,
                pepper: mPepper.pepper,
              )),
              salt: Value(newSalt),
              isConfirmed: const Value(true),
              isActive: const Value(true),
            ),
          );
        });

        final cSync2 = ClientSyncService(
          repository: cRepo,
          transport: HttpSyncTransport.forStore(
            client: client,
            tenantId: SpikeServer.defaultTenantId,
            storeId: SpikeServer.defaultStoreId,
          ),
          deviceId: 'POS-MED01-ACT',
          deviceToken: renewedTok,
          hubUrl: baseUrl,
        );
        final postRestoreSync = await cSync2.syncPendingOutbox();
        expect(postRestoreSync.isCleanSuccess, isTrue);
        expect(postRestoreSync.postRestoreRequeuedCount, equals(1));
        expect(await srv.db.select(srv.db.sales).get(), hasLength(1));
        expect(await cRepo.getStoredRestoreEpoch('POS-MED01-ACT'), equals(newEpoch));

        // 4. legacy_machine_key: true ile pepper-şifreli eski yedek restore'u da restore_epoch artırır
        final legacyPepperBak = await DatabaseBackupEngine.createBackup(
          liveDbFile: mDbFile,
          executeVacuumInto: (snap) async =>
              srv.db.customStatement("VACUUM INTO '${snap.replaceAll("'", "''")}';"),
          deviceId: 'SERVER_HUB',
          tenantId: SpikeServer.defaultTenantId,
          storeId: SpikeServer.defaultStoreId,
          databaseType: DatabaseType.centralMaster,
          schemaVersion: srv.db.schemaVersion,
          appVersion: 'legacy-pepper',
          backupPassword: mPepper.pepper,
          storageProvider: LocalStorageProvider(mBackupDir),
          kdfIterations: 1000,
        );
        final legacyResp = await client.post(
          Uri.parse('$baseUrl/api/v1/admin/restore'),
          headers: {
            'content-type': 'application/json',
            'x-mms-admin-secret': 'admin_med01_secret',
          },
          body: jsonEncode({
            'backup_id': legacyPepperBak.backupId,
            'legacy_machine_key': true,
          }),
        );
        expect(legacyResp.statusCode, equals(200), reason: legacyResp.body);
        final legacyBody = jsonDecode(legacyResp.body) as Map<String, dynamic>;
        expect(legacyBody['restore_epoch'], isNotNull);
        expect(legacyBody['restore_epoch'], isNot(equals(newEpoch)));
      } finally {
        await cDb.close();
        client.close();
        await ioSrv.close(force: true);
        await srv.db.close();
      }
    });
  });

  group('AUD-CRIT-03: Google Drive Hub Yedek Listeleme, Doğrulamalı İndirme ve Yeni PC Restore', () {
    test('7 günden eski önbelleği silinmiş Hub yedeği Drive üzerinden indirilip doğrulanarak geri yüklenir', () async {
      final drive = _FakeGoogleDriveBackend();
      final hubDir = Directory(p.join(tempDir.path, 'hub_pruned_cache'));
      final mDbFile = File(p.join(hubDir.path, 'data', 'market_master.db'));
      await mDbFile.parent.create(recursive: true);
      final mBackupDir = Directory(p.join(hubDir.path, 'backups'));
      final mSecDir = Directory(p.join(hubDir.path, 'security'));
      await mSecDir.create(recursive: true);

      final mDb = SpikeDatabase(mDbFile);
      final mWq = WriteQueue();
      final mPepper = PepperManager(File(p.join(mSecDir.path, 'pepper.dpapi')))
        ..initialize(overrideForTesting: 'pepper_stage2_crit03_32bytes_min');
      final mKeyStore = HubRecoveryKeyStore(
        File(p.join(mSecDir.path, HubRecoveryKeyStore.defaultFileName)),
      );
      const recoveryPass = 'Crit03-PrunedCache-Pass-2026!';
      await mKeyStore.saveRecoveryPassword(recoveryPass);

      final oauthStore = HubBackupOAuthStore(
        File(p.join(mSecDir.path, HubBackupOAuthStore.defaultFileName)),
      );
      await oauthStore.save(HubBackupOAuthCredentials(
        accessToken: 'acc_drive_crit03',
        refreshToken: 'ref_drive_crit03',
        expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 2)),
        accountEmail: 'owner@market.test',
        scope: 'https://www.googleapis.com/auth/drive.file',
        connectedAtUtc: DateTime.now().toUtc(),
      ));
      final oauthSvc = HubBackupOAuthService(
        store: oauthStore,
        httpClient: drive.client,
      );

      final ownerSalt = TokenManager.generateSalt();
      const ownerTok = 'tok_crit03_owner';
      await mDb.into(mDb.devices).insert(
            DevicesCompanion.insert(
              deviceId: 'POS-OWNER-CRIT03',
              name: 'Owner Kasa',
              tokenHash: TokenManager.hashToken(
                rawToken: ownerTok,
                salt: ownerSalt,
                pepper: mPepper.pepper,
              ),
              salt: ownerSalt,
              isActive: const Value(true),
              isConfirmed: const Value(true),
              role: const Value('OWNER'),
            ),
          );

      await mDb.into(mDb.products).insert(
            ProductsCompanion.insert(
              id: 'prod_before_prune',
              barcode: '8690003330011',
              name: 'Buluttan Dönecek Ürün',
              price: 4250,
              stock: 12000,
            ),
          );

      final orch = HubBackupOrchestrator(
        snapshotService: HubSnapshotService(
          readDb: () => mDb,
          writeQueue: mWq,
          liveDbFile: mDbFile,
          backupDir: mBackupDir,
          hubId: SpikeServer.defaultHubId,
          tenantId: SpikeServer.defaultTenantId,
          storeId: SpikeServer.defaultStoreId,
          appVersion: '1.0.0',
          kdfIterations: 1000,
          diskSpaceChecker: DiskSpaceChecker(freeBytesProbe: (_) async => 1 << 30),
        ),
        stateStore: HubBackupStateStore(
          File(p.join(mBackupDir.path, HubBackupStateStore.defaultFileName)),
        ),
        recoveryKeyStore: mKeyStore,
        oauthService: oauthSvc,
        uploader: ResumableDriveUploader(
          accessTokenProvider: ({bool forceRefresh = false}) =>
              oauthSvc.getValidAccessToken(
                clientId: 'cid',
                forceRefresh: forceRefresh,
              ),
          httpClient: drive.client,
          folderName: MmsDriveBackupFolders.rootFolderName,
          subfolderName: MmsDriveBackupFolders.hubSubfolderName,
          extraAppProperties: const {
            MmsDriveBackupFolders.backupSourceProperty:
                MmsDriveBackupFolders.hubBackupSource,
          },
        ),
        operationLock: BackupOperationLock(
          File(p.join(mBackupDir.path, BackupOperationLock.defaultFileName)),
        ),
        readSchemaVersion: () => mDb.schemaVersion,
        oauthClientId: 'cid',
      );

      final srv = SpikeServer(
        db: mDb,
        dbFile: mDbFile,
        writeQueue: mWq,
        backupDirectory: mBackupDir.path,
        adminSecret: 'admin_crit03_secret',
        pepperManager: mPepper,
        hubRecoveryKeyStore: mKeyStore,
        hubBackupOAuthService: oauthSvc,
        hubBackupOrchestrator: orch,
        hubRestoreSafetyKdfIterations: 1000,
      );
      final ioSrv = await shelf_io.serve(srv.handler, InternetAddress.loopbackIPv4, 0);
      final baseUrl = 'http://127.0.0.1:${ioSrv.port}';
      final client = http.Client();
      try {
        // 1. Manuel yedekle -> Drive'a yüklenir
        final uploaded = await orch.triggerBackup(trigger: HubBackupTrigger.manual);
        expect(uploaded.state, equals(HubBackupJobState.completedUploaded));
        expect(uploaded.driveFileId, isNotNull);

        // 2. 7 günlük yerel önbellek temizliği simülasyonu: diskteki .mmsbak silinir ve
        // backup_jobs_state.json'da encryptedPath = null kalır (driveFileId korunur).
        final localFile = File(uploaded.encryptedPath!);
        if (await localFile.exists()) {
          await localFile.delete();
        }
        await srv.hubBackupStateStore.patchJobs(
          {uploaded.backupId},
          (j) => HubBackupJobRecord(
            backupId: j.backupId,
            trigger: j.trigger,
            state: j.state,
            scheduledDateLocal: j.scheduledDateLocal,
            createdAtUtc: j.createdAtUtc,
            updatedAtUtc: j.updatedAtUtc,
            encryptedPath: null,
            encryptedSha256: j.encryptedSha256,
            encryptedSizeBytes: j.encryptedSizeBytes,
            driveFileId: j.driveFileId,
            uploadedBytes: j.uploadedBytes,
          ),
        );

        // 3. Yedek sonrasında eklenen ürün restore ile silinmeli
        await mDb.into(mDb.products).insert(
              ProductsCompanion.insert(
                id: 'prod_post_backup_temp',
                barcode: '8690003330028',
                name: 'Restore İle Gidecek Ürün',
                price: 9900,
                stock: 1000,
              ),
            );

        // 4. Bozuk Drive baytlarında restore CANLI DB'ye DOKUNMADAN reddedilmelidir
        drive.tamperNextDownload = true;
        final badRestore = await client.post(
          Uri.parse('$baseUrl/api/v1/backup/restore'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $ownerTok',
            'x-mms-timestamp': DateTime.now().toUtc().toIso8601String(),
            'x-mms-nonce': 'nonce_crit03_tamper',
          },
          body: jsonEncode({
            'backup_id': uploaded.backupId,
            'recovery_password': recoveryPass,
          }),
        );
        expect(badRestore.statusCode, isNot(equals(200)));
        expect(
          (await srv.db.select(srv.db.products).get()).map((e) => e.id),
          contains('prod_post_backup_temp'),
          reason: 'Bozuk Drive indirmesi doğrulanmadan restore başlatılmamalıdır.',
        );

        // 5. Sağlam Drive indirmesi + doğrulama + geri yükleme başarılı olmalıdır
        drive.tamperNextDownload = false;
        final okRestore = await client.post(
          Uri.parse('$baseUrl/api/v1/backup/restore'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $ownerTok',
            'x-mms-timestamp': DateTime.now().toUtc().toIso8601String(),
            'x-mms-nonce': 'nonce_crit03_ok',
          },
          body: jsonEncode({
            'backup_id': uploaded.backupId,
            'recovery_password': recoveryPass,
          }),
        );
        expect(okRestore.statusCode, equals(200), reason: okRestore.body);
        final okJson = jsonDecode(okRestore.body) as Map<String, dynamic>;
        expect(okJson['status'], equals('RESTORED'));
        expect(okJson['backup_id'], equals(uploaded.backupId));
        final restoredIds = (await srv.db.select(srv.db.products).get())
            .map((e) => e.id)
            .toList();
        expect(restoredIds, equals(['prod_before_prune']));
      } finally {
        client.close();
        await ioSrv.close(force: true);
        await srv.db.close();
      }
    });

    test('Yeni PC Felaket Kurtarma: Boş yerel backups/ ve boş state ile Drive listeleme, indirme ve restore tam veriyi geri getirir', () async {
      final drive = _FakeGoogleDriveBackend();
      const recoveryPass = 'NewPc-Disaster-Pass-2026!';

      // Drive içine LiveSync (.mmsenv) ve istemci yedeği gürültüsü koy: Hub listesinde görünmemeli!
      drive.seedNonHubFiles();

      // --- HUB-A (Kaynak Makine): Ürün + Satış üret ve Google Drive'a yükle ---
      final hubADir = Directory(p.join(tempDir.path, 'hub_a_source'));
      final dbAFile = File(p.join(hubADir.path, 'data', 'market_master.db'));
      await dbAFile.parent.create(recursive: true);
      final backupADir = Directory(p.join(hubADir.path, 'backups'));
      final secADir = Directory(p.join(hubADir.path, 'security'));
      await secADir.create(recursive: true);

      final dbA = SpikeDatabase(dbAFile);
      final wqA = WriteQueue();
      final keyStoreA = HubRecoveryKeyStore(
        File(p.join(secADir.path, HubRecoveryKeyStore.defaultFileName)),
      );
      await keyStoreA.saveRecoveryPassword(recoveryPass);

      final oauthStoreA = HubBackupOAuthStore(
        File(p.join(secADir.path, HubBackupOAuthStore.defaultFileName)),
      );
      await oauthStoreA.save(HubBackupOAuthCredentials(
        accessToken: 'acc_hub_a',
        refreshToken: 'ref_shared_google_account',
        expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 2)),
        accountEmail: 'store-owner@example.com',
        scope: 'https://www.googleapis.com/auth/drive.file',
        connectedAtUtc: DateTime.now().toUtc(),
      ));
      final oauthSvcA = HubBackupOAuthService(
        store: oauthStoreA,
        httpClient: drive.client,
      );

      await dbA.into(dbA.products).insert(
            ProductsCompanion.insert(
              id: 'prod_dr_1',
              barcode: '8690007770011',
              name: 'Kurtarma Test Ürünü',
              price: 7500,
              stock: 33000,
            ),
          );
      await dbA.into(dbA.sales).insert(
            SalesCompanion.insert(
              id: 'sale_dr_1',
              deviceId: 'POS-A-01',
              clientSeq: 1,
              totalAmount: 7500,
              paymentMethod: 'CASH',
            ),
          );

      final orchA = HubBackupOrchestrator(
        snapshotService: HubSnapshotService(
          readDb: () => dbA,
          writeQueue: wqA,
          liveDbFile: dbAFile,
          backupDir: backupADir,
          hubId: 'HUB-OLD-PC',
          tenantId: SpikeServer.defaultTenantId,
          storeId: SpikeServer.defaultStoreId,
          appVersion: '1.0.0',
          kdfIterations: 1000,
          diskSpaceChecker: DiskSpaceChecker(freeBytesProbe: (_) async => 1 << 30),
        ),
        stateStore: HubBackupStateStore(
          File(p.join(backupADir.path, HubBackupStateStore.defaultFileName)),
        ),
        recoveryKeyStore: keyStoreA,
        oauthService: oauthSvcA,
        uploader: ResumableDriveUploader(
          accessTokenProvider: ({bool forceRefresh = false}) =>
              oauthSvcA.getValidAccessToken(
                clientId: 'cid',
                forceRefresh: forceRefresh,
              ),
          httpClient: drive.client,
          folderName: MmsDriveBackupFolders.rootFolderName,
          subfolderName: MmsDriveBackupFolders.hubSubfolderName,
          extraAppProperties: const {
            MmsDriveBackupFolders.backupSourceProperty:
                MmsDriveBackupFolders.hubBackupSource,
          },
        ),
        operationLock: BackupOperationLock(
          File(p.join(backupADir.path, BackupOperationLock.defaultFileName)),
        ),
        readSchemaVersion: () => dbA.schemaVersion,
        oauthClientId: 'cid',
      );
      final uploadedFromA = await orchA.triggerBackup(trigger: HubBackupTrigger.manual);
      expect(uploadedFromA.state, equals(HubBackupJobState.completedUploaded));
      await dbA.close();

      // --- HUB-B (Yepyeni Bilgisayar): Tamamen boş DB, boş backups/, state JSON yok, yeni pepper ---
      final hubBDir = Directory(p.join(tempDir.path, 'hub_b_new_pc'));
      final dbBFile = File(p.join(hubBDir.path, 'data', 'market_master.db'));
      await dbBFile.parent.create(recursive: true);
      final backupBDir = Directory(p.join(hubBDir.path, 'backups'));
      final secBDir = Directory(p.join(hubBDir.path, 'security'));
      await secBDir.create(recursive: true);

      final dbB = SpikeDatabase(dbBFile);
      final wqB = WriteQueue();
      final pepperB = PepperManager(File(p.join(secBDir.path, 'pepper.dpapi')))
        ..initialize(overrideForTesting: 'new_pc_brand_new_pepper_32bytes');

      final cashierSaltB = TokenManager.generateSalt();
      const cashierTokB = 'tok_new_pc_cashier';
      await dbB.into(dbB.devices).insert(
            DevicesCompanion.insert(
              deviceId: 'POS-B-CASHIER',
              name: 'Yeni PC Kasiyer',
              tokenHash: TokenManager.hashToken(
                rawToken: cashierTokB,
                salt: cashierSaltB,
                pepper: pepperB.pepper,
              ),
              salt: cashierSaltB,
              role: const Value('CASHIER'),
            ),
          );

      // Yeni PC'de Drive OAuth bağlı, ancak cached folderId = null ve backups/ dizini BOMBOŞ!
      final oauthStoreB = HubBackupOAuthStore(
        File(p.join(secBDir.path, HubBackupOAuthStore.defaultFileName)),
      );
      await oauthStoreB.save(HubBackupOAuthCredentials(
        accessToken: 'acc_hub_b',
        refreshToken: 'ref_shared_google_account',
        expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 2)),
        accountEmail: 'store-owner@example.com',
        scope: 'https://www.googleapis.com/auth/drive.file',
        connectedAtUtc: DateTime.now().toUtc(),
      ));
      final oauthSvcB = HubBackupOAuthService(
        store: oauthStoreB,
        httpClient: drive.client,
      );
      final keyStoreB = HubRecoveryKeyStore(
        File(p.join(secBDir.path, HubRecoveryKeyStore.defaultFileName)),
      );

      final orchB = HubBackupOrchestrator(
        snapshotService: HubSnapshotService(
          readDb: () => dbB,
          writeQueue: wqB,
          liveDbFile: dbBFile,
          backupDir: backupBDir,
          hubId: 'HUB-NEW-PC',
          tenantId: SpikeServer.defaultTenantId,
          storeId: SpikeServer.defaultStoreId,
          appVersion: '1.0.0',
          kdfIterations: 1000,
          diskSpaceChecker: DiskSpaceChecker(freeBytesProbe: (_) async => 1 << 30),
        ),
        stateStore: HubBackupStateStore(
          File(p.join(backupBDir.path, HubBackupStateStore.defaultFileName)),
        ),
        recoveryKeyStore: keyStoreB,
        oauthService: oauthSvcB,
        uploader: ResumableDriveUploader(
          accessTokenProvider: ({bool forceRefresh = false}) =>
              oauthSvcB.getValidAccessToken(
                clientId: 'cid',
                forceRefresh: forceRefresh,
              ),
          httpClient: drive.client,
          folderName: MmsDriveBackupFolders.rootFolderName,
          subfolderName: MmsDriveBackupFolders.hubSubfolderName,
          extraAppProperties: const {
            MmsDriveBackupFolders.backupSourceProperty:
                MmsDriveBackupFolders.hubBackupSource,
          },
        ),
        operationLock: BackupOperationLock(
          File(p.join(backupBDir.path, BackupOperationLock.defaultFileName)),
        ),
        readSchemaVersion: () => dbB.schemaVersion,
        oauthClientId: 'cid',
      );

      final srvB = SpikeServer(
        db: dbB,
        dbFile: dbBFile,
        writeQueue: wqB,
        backupDirectory: backupBDir.path,
        adminSecret: 'new_pc_admin_secret_2026',
        pepperManager: pepperB,
        hubRecoveryKeyStore: keyStoreB,
        hubBackupOAuthService: oauthSvcB,
        hubBackupOrchestrator: orchB,
        hubRestoreSafetyKdfIterations: 1000,
      );
      final ioSrvB = await shelf_io.serve(srvB.handler, InternetAddress.loopbackIPv4, 0);
      final baseUrlB = 'http://127.0.0.1:${ioSrvB.port}';
      final client = http.Client();
      try {
        expect(
          backupBDir.existsSync()
              ? backupBDir.listSync().where((e) => e.path.endsWith('.mmsbak'))
              : const [],
          isEmpty,
        );

        // 1. CASHIER Drive yedek listesini göremez -> 403
        final cashierListResp = await client.get(
          Uri.parse('$baseUrlB/api/v1/backup/drive/list'),
          headers: {'authorization': 'Bearer $cashierTokB'},
        );
        expect(cashierListResp.statusCode, equals(403));

        // 2. Yeni PC admin/OWNER Drive'daki HUB_CENTRAL yedeklerini listeler
        final listResp = await client.get(
          Uri.parse('$baseUrlB/api/v1/backup/drive/list'),
          headers: {'x-mms-admin-secret': 'new_pc_admin_secret_2026'},
        );
        expect(listResp.statusCode, equals(200), reason: listResp.body);
        final listed = ((jsonDecode(listResp.body) as Map)['backups'] as List)
            .cast<Map<String, dynamic>>();
        expect(listed, hasLength(1),
            reason: 'Yalnızca HUB_CENTRAL .mmsbak listelenmeli; .mmsenv ve mobil yedekler hariç kalmalı.');
        expect(listed.single['backup_id'], equals(uploadedFromA.backupId));
        expect(listed.single['drive_file_id'], equals(uploadedFromA.driveFileId));
        expect(listed.single['cached_locally'], isFalse);

        // 3. Yeni PC'de Drive'dan indir + doğrula + restore et (yerel cache boşken!)
        final restoreResp = await client.post(
          Uri.parse('$baseUrlB/api/v1/backup/restore'),
          headers: {
            'content-type': 'application/json',
            'x-mms-admin-secret': 'new_pc_admin_secret_2026',
            'x-mms-timestamp': DateTime.now().toUtc().toIso8601String(),
            'x-mms-nonce': 'nonce_new_pc_dr_1',
          },
          body: jsonEncode({
            'backup_id': listed.single['backup_id'],
            'drive_file_id': listed.single['drive_file_id'],
            'recovery_password': recoveryPass,
          }),
        );
        expect(restoreResp.statusCode, equals(200), reason: restoreResp.body);
        final restoreJson = jsonDecode(restoreResp.body) as Map<String, dynamic>;
        expect(restoreJson['status'], equals('RESTORED'));
        expect(restoreJson['backup_id'], equals(uploadedFromA.backupId));
        expect(restoreJson['restore_epoch'], isNot(equals('epoch_0')));

        final restoredProducts = await srvB.db.select(srvB.db.products).get();
        expect(restoredProducts.map((p) => p.id).toList(), equals(['prod_dr_1']));
        expect(restoredProducts.single.stock, equals(33000));

        final restoredSales = await srvB.db.select(srvB.db.sales).get();
        expect(restoredSales.map((s) => s.id).toList(), equals(['sale_dr_1']));
      } finally {
        client.close();
        await ioSrvB.close(force: true);
        await srvB.db.close();
      }
    });
  });
}

class _StoredDriveEntry {
  final String id;
  final String name;
  final String parentId;
  final List<int> bytes;
  final Map<String, dynamic> appProperties;
  final DateTime createdTimeUtc;

  _StoredDriveEntry({
    required this.id,
    required this.name,
    required this.parentId,
    required this.bytes,
    required this.appProperties,
    required this.createdTimeUtc,
  });
}

/// Test içi durumlu Google Drive v3 API simülatörü (sınıf kapsamı yalnız sentetik test verisidir).
class _FakeGoogleDriveBackend {
  final Map<String, ({String id, String name, String? parentId})> _folders = {};
  final Map<String, _StoredDriveEntry> _files = {};
  final Map<String, ({String name, String parentId, Map<String, dynamic> appProps, BytesBuilder buf})>
      _sessions = {};
  var _seq = 0;
  bool tamperNextDownload = false;

  late final http.Client client = _FakeDriveHttpClient(this);

  void seedNonHubFiles() {
    _folders.putIfAbsent(
      'root_livesync',
      () => (id: 'drv_folder_livesync', name: 'MARKET MMS LiveSync', parentId: null),
    );
    _files['drv_env_1'] = _StoredDriveEntry(
      id: 'drv_env_1',
      name: 'live_sync_envelope_1.mmsenv',
      parentId: 'drv_folder_livesync',
      bytes: utf8.encode('not-a-backup'),
      appProperties: {'mms_live_sync': 'true'},
      createdTimeUtc: DateTime.utc(2026, 11, 24, 8, 0),
    );
    final rootMms = _ensureFolder(MmsDriveBackupFolders.rootFolderName, null);
    _files['drv_client_1'] = _StoredDriveEntry(
      id: 'drv_client_1',
      name: 'backup_MOBILE_LOCAL_dev1_abc.mmsbak',
      parentId: rootMms,
      bytes: [1, 2, 3],
      appProperties: {
        'mms_backup_id': 'client_bak_1',
        'mms_database_type': 'MOBILE_LOCAL',
      },
      createdTimeUtc: DateTime.utc(2026, 11, 24, 9, 0),
    );
  }

  String _ensureFolder(String name, String? parentId) {
    final key = '${parentId ?? ''}::$name';
    final existing = _folders[key];
    if (existing != null) return existing.id;
    final id = 'drv_folder_${++_seq}';
    _folders[key] = (id: id, name: name, parentId: parentId);
    return id;
  }

  Future<http.StreamedResponse> handle(http.BaseRequest req) async {
    final bytes = await req.finalize().toBytes();
    final url = req.url;

    // Resumable session upload chunks / completion
    if (req.method == 'PUT' && url.path.startsWith('/upload_sess/')) {
      final sessId = url.pathSegments.last;
      final sess = _sessions[sessId];
      if (sess == null) {
        return _streamResp(404, 'Not Found');
      }
      final contentRange = req.headers['content-range'] ?? '';
      if (contentRange.startsWith('bytes */')) {
        return _streamResp(308, '');
      }
      sess.buf.add(bytes);
      final m = RegExp(r'bytes (\d+)-(\d+)/(\d+)').firstMatch(contentRange);
      final isFinal = m == null ||
          int.parse(m.group(2)!) + 1 >= int.parse(m.group(3)!);
      if (!isFinal) {
        return _streamResp(
          308,
          '',
          headers: {'range': 'bytes=0-${sess.buf.length - 1}'},
        );
      }
      final fileId = 'drv_file_${++_seq}';
      final fullBytes = sess.buf.takeBytes();
      _files[fileId] = _StoredDriveEntry(
        id: fileId,
        name: sess.name,
        parentId: sess.parentId,
        bytes: fullBytes,
        appProperties: sess.appProps,
        createdTimeUtc: DateTime.now().toUtc(),
      );
      _sessions.remove(sessId);
      return _streamResp(200, jsonEncode({'id': fileId}));
    }

    // Start resumable session
    if (req.method == 'POST' &&
        url.path == '/upload/drive/v3/files' &&
        url.queryParameters['uploadType'] == 'resumable') {
      final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final sessId = 'sess_${++_seq}';
      _sessions[sessId] = (
        name: decoded['name'] as String,
        parentId: ((decoded['parents'] as List?)?.first as String?) ?? '',
        appProps: Map<String, dynamic>.from(
          decoded['appProperties'] as Map? ?? const {},
        ),
        buf: BytesBuilder(copy: false),
      );
      return _streamResp(
        200,
        '',
        headers: {'location': 'https://www.googleapis.com/upload_sess/$sessId'},
      );
    }

    // Files list / search
    if (req.method == 'GET' && url.path == '/drive/v3/files') {
      final q = url.queryParameters['q'] ?? '';
      if (q.contains("mimeType = 'application/vnd.google-apps.folder'")) {
        final nameMatch = RegExp(r"name = '([^']+)'").firstMatch(q);
        final parentMatch = RegExp(r"'([^']+)' in parents").firstMatch(q);
        final wantedName = nameMatch?.group(1);
        final wantedParent = parentMatch?.group(1);
        final matches = _folders.values
            .where((f) =>
                f.name == wantedName &&
                (wantedParent == null ? f.parentId == null : f.parentId == wantedParent))
            .map((f) => {'id': f.id, 'name': f.name})
            .toList();
        return _streamResp(200, jsonEncode({'files': matches}));
      }

      final parentMatch = RegExp(r"'([^']+)' in parents").firstMatch(q);
      final wantedParent = parentMatch?.group(1);
      final backupIdMatch =
          RegExp(r"key='mms_backup_id' and value = '([^']+)'").firstMatch(q);
      final wantedBackupId = backupIdMatch?.group(1);

      final matches = _files.values.where((f) {
        if (wantedParent != null && f.parentId != wantedParent) return false;
        if (wantedBackupId != null &&
            f.appProperties['mms_backup_id'] != wantedBackupId) {
          return false;
        }
        return true;
      }).map((f) {
        return {
          'id': f.id,
          'name': f.name,
          'size': f.bytes.length.toString(),
          'md5Checksum': md5.convert(f.bytes).toString(),
          'createdTime': f.createdTimeUtc.toIso8601String(),
          'appProperties': f.appProperties,
        };
      }).toList();
      return _streamResp(200, jsonEncode({'files': matches}));
    }

    // Create folder
    if (req.method == 'POST' && url.path == '/drive/v3/files') {
      final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final name = decoded['name'] as String;
      final parentId = (decoded['parents'] as List?)?.first as String?;
      final id = _ensureFolder(name, parentId);
      return _streamResp(200, jsonEncode({'id': id, 'name': name}));
    }

    // Get metadata or alt=media download for /drive/v3/files/<id>
    if (req.method == 'GET' && url.path.startsWith('/drive/v3/files/')) {
      final fileId = url.pathSegments.last;
      final entry = _files[fileId];
      if (entry == null) {
        return _streamResp(404, jsonEncode({'error': {'code': 404}}));
      }
      if (url.queryParameters['alt'] == 'media') {
        final payload = List<int>.from(entry.bytes);
        if (tamperNextDownload && payload.length > 20) {
          payload[payload.length - 5] ^= 0xff;
        }
        return http.StreamedResponse(
          Stream<List<int>>.value(payload),
          200,
          contentLength: payload.length,
        );
      }
      return _streamResp(
        200,
        jsonEncode({
          'id': entry.id,
          'name': entry.name,
          'size': entry.bytes.length.toString(),
          'md5Checksum': md5.convert(entry.bytes).toString(),
          'createdTime': entry.createdTimeUtc.toIso8601String(),
          'appProperties': entry.appProperties,
        }),
      );
    }

    if (req.method == 'DELETE' && url.path.startsWith('/drive/v3/files/')) {
      final fileId = url.pathSegments.last;
      _files.remove(fileId);
      return _streamResp(204, '');
    }

    return _streamResp(400, 'Unexpected ${req.method} $url');
  }

  static http.StreamedResponse _streamResp(
    int status,
    String body, {
    Map<String, String> headers = const {},
  }) {
    final encoded = utf8.encode(body);
    return http.StreamedResponse(
      Stream<List<int>>.value(encoded),
      status,
      headers: headers,
      contentLength: encoded.length,
    );
  }
}

class _FakeDriveHttpClient extends http.BaseClient {
  final _FakeGoogleDriveBackend backend;

  _FakeDriveHttpClient(this.backend);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      backend.handle(request);
}
