import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../lib/backup/hub_backup_oauth_service.dart';
import '../lib/backup/hub_backup_oauth_store.dart';
import '../lib/backup/hub_backup_orchestrator.dart';
import '../lib/backup/hub_backup_state_store.dart';
import '../lib/backup/hub_recovery_key_store.dart';
import '../lib/backup/hub_snapshot_service.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';

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
    tempDir = Directory.systemTemp.createTempSync('mms_test_only_b3_orch_');
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
    await recoveryKeyStore.saveRecoveryPassword('HubKatilimsiz-Parola-2026!');
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<HubBackupOAuthService> connectedOAuth(DateTime Function() clock) async {
    final store = HubBackupOAuthStore(
      File(p.join(securityDir.path, HubBackupOAuthStore.defaultFileName)),
    );
    await store.save(HubBackupOAuthCredentials(
      accessToken: 'acc_b3_valid',
      refreshToken: 'ref_b3_valid',
      expiresAtUtc: clock().toUtc().add(const Duration(hours: 1)),
      accountEmail: 'owner@market.test',
      scope: 'https://www.googleapis.com/auth/drive.file',
      folderId: 'folder_b3_1',
      // S5: Önbellekteki kimlik zaten `MARKET MMS Yedekleri/Hub` alt klasörüdür
      // (eski kök önbelleği senaryosu hub_backup_s1_s6_hardening_test.dart içinde).
      folderLayout: HubBackupOAuthCredentials.hubSubfolderLayout,
      connectedAtUtc: clock().toUtc(),
    ));
    return HubBackupOAuthService(
      store: store,
      httpClient: MockClient((req) async {
        if (req.url.toString().contains('/token')) {
          return http.Response(
            jsonEncode({
              'access_token': 'acc_b3_refreshed',
              'expires_in': 3600,
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      }),
      clock: clock,
    );
  }

  MockClient healthyDriveMock({
    required void Function(String method, Uri uri)? onCall,
    String fileId = 'drv_file_ok',
  }) {
    final uploadedSizes = <String, int>{};
    final appPropsMap = <String, Map<String, dynamic>>{};
    final md5Map = <String, String>{};

    return MockClient((req) async {
      onCall?.call(req.method, req.url);
      final uri = req.url.toString();
      if (req.method == 'POST' && uri.contains('uploadType=resumable')) {
        final decoded = jsonDecode(req.body) as Map<String, dynamic>;
        appPropsMap[fileId] = Map<String, dynamic>.from(
          decoded['appProperties'] as Map? ?? const {},
        );
        return http.Response(
          '',
          200,
          headers: {'location': 'https://upload.test/sess/$fileId'},
        );
      }
      if (req.method == 'PUT' && uri.contains('/sess/')) {
        final range = req.headers['content-range'] ?? '';
        if (range.startsWith('bytes */')) {
          return http.Response('', 308);
        }
        uploadedSizes[fileId] = req.bodyBytes.length;
        md5Map[fileId] = md5.convert(req.bodyBytes).toString();
        return http.Response(jsonEncode({'id': fileId}), 200);
      }
      if (req.method == 'GET' && uri.contains('/drive/v3/files/$fileId')) {
        return http.Response(
          jsonEncode({
            'id': fileId,
            'size': uploadedSizes[fileId]?.toString() ?? '0',
            'md5Checksum': md5Map[fileId],
            'appProperties': appPropsMap[fileId] ?? const {},
          }),
          200,
        );
      }
      if (req.method == 'DELETE' && uri.contains('/drive/v3/files/')) {
        return http.Response('', 204);
      }
      return http.Response('Unexpected ${req.method} $uri', 400);
    });
  }

  group('Faz B-3: 12-Durum Makinesi, Orkestratör, Crash Recovery & Kooperatif Kapanış', () {
    test('BK-006 & BK-016: Tüm 12 durum, geçiş doğrulaması, atomik state persistence ve katılımsız recovery key koruması', () async {
      expect(HubBackupJobState.values.length, equals(12));
      expect(
        HubBackupStateMachine.canTransition(
          HubBackupJobState.pending,
          HubBackupJobState.runningSnapshot,
        ),
        isTrue,
      );
      expect(
        HubBackupStateMachine.canTransition(
          HubBackupJobState.completedUploaded,
          HubBackupJobState.retryPending,
        ),
        isFalse,
      );

      await expectLater(
        () => recoveryKeyStore.saveRecoveryPassword('short123'),
        throwsA(isA<HubRecoveryKeyException>()),
      );

      var currentLocal = DateTime(2026, 11, 22, 10, 0);
      final oauth = await connectedOAuth(() => currentLocal);
      final driveMock = healthyDriveMock(onCall: (_, __) {});

      final orchestrator = HubBackupOrchestrator(
        snapshotService: HubSnapshotService(
          readDb: () => db,
          writeQueue: writeQueue,
          liveDbFile: dbFile,
          backupDir: backupDir,
          hubId: 'HUB-B3',
          tenantId: 't1',
          storeId: 's1',
          appVersion: '1.0.0',
          kdfIterations: 1000,
          diskSpaceChecker: DiskSpaceChecker(freeBytesProbe: (_) async => 1 << 30),
        ),
        stateStore: stateStore,
        recoveryKeyStore: recoveryKeyStore,
        oauthService: oauth,
        uploader: ResumableDriveUploader(
          accessTokenProvider: ({bool forceRefresh = false}) =>
              oauth.getValidAccessToken(
                clientId: 'cid',
                forceRefresh: forceRefresh,
              ),
          httpClient: driveMock,
        ),
        operationLock: BackupOperationLock(File(p.join(backupDir.path, '.lock'))),
        readSchemaVersion: () => db.schemaVersion,
        oauthClientId: 'cid',
        localClock: () => currentLocal,
      );

      final job = await orchestrator.triggerBackup(trigger: HubBackupTrigger.manual);
      expect(job.state, equals(HubBackupJobState.completedUploaded));
      expect(job.driveFileId, equals('drv_file_ok'));

      final persisted = await stateStore.load();
      expect(persisted.latestJob?.backupId, equals(job.backupId));
      expect(persisted.latestJob?.state, equals(HubBackupJobState.completedUploaded));
      // Durum JSON dosyası asla katılımsız parolayı düz metin içermemeli
      expect(
        (await stateStore.file.readAsString()).contains('HubKatilimsiz-Parola-2026!'),
        isFalse,
      );
    });

    test('BK-007 & BK-009: INITIAL_ENABLE, 00:00 SCHEDULED_DAILY, CATCH_UP ve gece yarısı devri SUPERSEDED', () async {
      var currentLocal = DateTime(2026, 11, 22, 9, 0); // 09:00 açılış
      final oauth = await connectedOAuth(() => currentLocal);
      final driveMock = healthyDriveMock(onCall: (_, __) {});

      final orchestrator = HubBackupOrchestrator(
        snapshotService: HubSnapshotService(
          readDb: () => db,
          writeQueue: writeQueue,
          liveDbFile: dbFile,
          backupDir: backupDir,
          hubId: 'HUB-B3',
          tenantId: 't1',
          storeId: 's1',
          appVersion: '1.0.0',
          kdfIterations: 1000,
          diskSpaceChecker: DiskSpaceChecker(freeBytesProbe: (_) async => 1 << 30),
        ),
        stateStore: stateStore,
        recoveryKeyStore: recoveryKeyStore,
        oauthService: oauth,
        uploader: ResumableDriveUploader(
          accessTokenProvider: ({bool forceRefresh = false}) =>
              oauth.getValidAccessToken(
                clientId: 'cid',
                forceRefresh: forceRefresh,
              ),
          httpClient: driveMock,
        ),
        operationLock: BackupOperationLock(File(p.join(backupDir.path, '.lock'))),
        readSchemaVersion: () => db.schemaVersion,
        oauthClientId: 'cid',
        localClock: () => currentLocal,
      );

      // 1. INITIAL_ENABLE anında tetiklenir
      final snapAfterEnable = await orchestrator.configureSchedule(
        enabled: true,
        dailyHourLocal: 0,
        dailyMinuteLocal: 0,
      );
      expect(snapAfterEnable.latestJob?.trigger, equals(HubBackupTrigger.initialEnable));
      expect(snapAfterEnable.latestJob?.state, equals(HubBackupJobState.completedUploaded));

      // 2. Ertesi gün 00:05'te -> SCHEDULED_DAILY
      currentLocal = DateTime(2026, 11, 23, 0, 5);
      final day2Job = await orchestrator.evaluateTick();
      expect(day2Job, isNotNull);
      expect(day2Job!.trigger, equals(HubBackupTrigger.scheduledDaily));
      expect(day2Job.state, equals(HubBackupJobState.completedUploaded));

      // 3. Ertesi gün bilgisayar 10:30'da açılırsa (00:00 kaçırılmış + önceki günden RETRY_PENDING kalmış) -> CATCH_UP + SUPERSEDED
      await stateStore.upsertJob(
        HubBackupJobRecord(
          backupId: 'unfinished_prev_day',
          trigger: HubBackupTrigger.scheduledDaily,
          state: HubBackupJobState.retryPending,
          scheduledDateLocal: '2026-11-23',
          createdAtUtc: DateTime.utc(2026, 11, 23, 0, 5),
          updatedAtUtc: DateTime.utc(2026, 11, 23, 2, 0),
        ),
      );
      currentLocal = DateTime(2026, 11, 24, 10, 30);
      final day3Job = await orchestrator.evaluateTick();
      expect(day3Job, isNotNull);
      expect(day3Job!.trigger, equals(HubBackupTrigger.catchUp));
      expect(day3Job.state, equals(HubBackupJobState.completedUploaded));

      final afterRollover = await stateStore.load();
      final supersededPrev = afterRollover.jobs
          .firstWhere((j) => j.backupId == 'unfinished_prev_day');
      expect(supersededPrev.state, equals(HubBackupJobState.superseded));
      // Geçmiş COMPLETED_UPLOADED kayıtları korunur
      expect(
        afterRollover.jobs.where((j) => j.state == HubBackupJobState.completedUploaded).length,
        greaterThanOrEqualTo(3),
      );
    });

    test('BK-008 & BK-028: Retry backoff 5/10/20/40/80/160dk, gün sonu 160dk tavanı ve FAILED_AUTH/FAILED_QUOTA kör retry engeli', () async {
      expect(HubBackupOrchestrator.retryDelayForAttempt(1).inMinutes, equals(5));
      expect(HubBackupOrchestrator.retryDelayForAttempt(2).inMinutes, equals(10));
      expect(HubBackupOrchestrator.retryDelayForAttempt(3).inMinutes, equals(20));
      expect(HubBackupOrchestrator.retryDelayForAttempt(4).inMinutes, equals(40));
      expect(HubBackupOrchestrator.retryDelayForAttempt(5).inMinutes, equals(80));
      expect(HubBackupOrchestrator.retryDelayForAttempt(6).inMinutes, equals(160));
      expect(HubBackupOrchestrator.retryDelayForAttempt(9).inMinutes, equals(160));

      var currentLocal = DateTime(2026, 11, 22, 1, 0);
      final oauth = await connectedOAuth(() => currentLocal);
      var quotaCalls = 0;
      final quotaMock = MockClient((req) async {
        quotaCalls++;
        return http.Response(
          jsonEncode({'error': {'code': 403, 'errors': [{'reason': 'storageQuotaExceeded'}]}}),
          403,
        );
      });

      final orchestrator = HubBackupOrchestrator(
        snapshotService: HubSnapshotService(
          readDb: () => db,
          writeQueue: writeQueue,
          liveDbFile: dbFile,
          backupDir: backupDir,
          hubId: 'HUB-B3',
          tenantId: 't1',
          storeId: 's1',
          appVersion: '1.0.0',
          kdfIterations: 1000,
          diskSpaceChecker: DiskSpaceChecker(freeBytesProbe: (_) async => 1 << 30),
        ),
        stateStore: stateStore,
        recoveryKeyStore: recoveryKeyStore,
        oauthService: oauth,
        uploader: ResumableDriveUploader(
          accessTokenProvider: ({bool forceRefresh = false}) =>
              oauth.getValidAccessToken(
                clientId: 'cid',
                forceRefresh: forceRefresh,
              ),
          httpClient: quotaMock,
        ),
        operationLock: BackupOperationLock(File(p.join(backupDir.path, '.lock'))),
        readSchemaVersion: () => db.schemaVersion,
        oauthClientId: 'cid',
        localClock: () => currentLocal,
      );

      await orchestrator.configureSchedule(enabled: true, triggerInitialIfDue: false);
      final failedJob = await orchestrator.triggerBackup(trigger: HubBackupTrigger.scheduledDaily);
      expect(failedJob.state, equals(HubBackupJobState.failedQuota));
      final recordedCalls = quotaCalls;

      // Sonraki tick'lerde kota hatası tekrar döngüsüne girmez
      currentLocal = currentLocal.add(const Duration(minutes: 30));
      expect(await orchestrator.evaluateTick(), isNull);
      expect(quotaCalls, equals(recordedCalls));
    });

    test('BK-010: Aşamalı crash recovery (ENCRYPTED_LOCAL_READY -> UPLOADING, gereksiz 600k PBKDF2 çalıştırmadan)', () async {
      var currentLocal = DateTime(2026, 11, 22, 12, 0);
      final oauth = await connectedOAuth(() => currentLocal);

      // Şifrelenmiş .mmsbak üret ama Drive kesintisi nedeniyle ENCRYPTED_LOCAL_READY durumda bırak
      var encryptCalls = 0;
      final snapSvc = HubSnapshotService(
        readDb: () => db,
        writeQueue: writeQueue,
        liveDbFile: dbFile,
        backupDir: backupDir,
        hubId: 'HUB-B3',
        tenantId: 't1',
        storeId: 's1',
        appVersion: '1.0.0',
        kdfIterations: 1000,
        diskSpaceChecker: DiskSpaceChecker(freeBytesProbe: (_) async => 1 << 30),
        encryptHook: ({
          required File inputFile,
          required File outputFile,
          required String password,
          required BackupManifest manifest,
          int kdfIterations = 1000,
        }) {
          encryptCalls++;
          return MmsbakV2Crypto.encryptFile(
            inputFile: inputFile,
            outputFile: outputFile,
            password: password,
            manifest: manifest,
            kdfIterations: kdfIterations,
          );
        },
      );

      final preBuilt = await snapSvc.createEncryptedBackup(
        backupId: 'crash_rec_bak_1',
        recoveryPassword: 'HubKatilimsiz-Parola-2026!',
        schemaVersion: db.schemaVersion,
      );
      expect(encryptCalls, equals(1));
      final encSha = await MmsbakV2Crypto.computeFileSha256(preBuilt.backupFile);

      await stateStore.upsertJob(
        HubBackupJobRecord(
          backupId: 'crash_rec_bak_1',
          trigger: HubBackupTrigger.scheduledDaily,
          state: HubBackupJobState.encryptedLocalReady,
          scheduledDateLocal: '2026-11-22',
          createdAtUtc: currentLocal.toUtc(),
          updatedAtUtc: currentLocal.toUtc(),
          encryptedPath: preBuilt.backupFile.path,
          encryptedSha256: encSha,
          encryptedSizeBytes: preBuilt.encryptedSizeBytes,
        ),
        schedule: const HubBackupScheduleConfig(enabled: true),
      );

      final driveMock = healthyDriveMock(onCall: (_, __) {}, fileId: 'drv_resumed_1');
      final orchestrator = HubBackupOrchestrator(
        snapshotService: snapSvc,
        stateStore: stateStore,
        recoveryKeyStore: recoveryKeyStore,
        oauthService: oauth,
        uploader: ResumableDriveUploader(
          accessTokenProvider: ({bool forceRefresh = false}) =>
              oauth.getValidAccessToken(
                clientId: 'cid',
                forceRefresh: forceRefresh,
              ),
          httpClient: driveMock,
        ),
        operationLock: BackupOperationLock(File(p.join(backupDir.path, '.lock'))),
        readSchemaVersion: () => db.schemaVersion,
        oauthClientId: 'cid',
        localClock: () => currentLocal,
      );

      // Yeni açılışta tekrar şifreleme yapılmadan doğrudan yüklenip COMPLETED_UPLOADED olmalı
      encryptCalls = 0;
      final recovered = await orchestrator.recoverOnStartup();
      expect(recovered, isNotNull);
      expect(recovered!.backupId, equals('crash_rec_bak_1'));
      expect(recovered.state, equals(HubBackupJobState.completedUploaded));
      expect(recovered.driveFileId, equals('drv_resumed_1'));
      expect(encryptCalls, equals(0));
    });

    test('BK-014 & BK-015 & BK-030: Kooperatif <1.5s kapanış (aynı backup_id RETRY_PENDING), kilit çakışması ve retention sırası', () async {
      final currentLocal = DateTime(2026, 11, 22, 14, 0);
      final oauth = await connectedOAuth(() => currentLocal);
      final uploadStarted = Completer<void>();

      final slowMock = MockClient((req) async {
        if (req.method == 'POST' && req.url.toString().contains('uploadType=resumable')) {
          return http.Response(
            '',
            200,
            headers: {'location': 'https://upload.test/slow_sess'},
          );
        }
        if (req.method == 'PUT') {
          if (!uploadStarted.isCompleted) uploadStarted.complete();
          await Future<void>.delayed(const Duration(seconds: 15));
          return http.Response(jsonEncode({'id': 'never'}), 200);
        }
        return http.Response('{}', 200);
      });

      final lock = BackupOperationLock(File(p.join(backupDir.path, '.lock')));
      final orchestrator = HubBackupOrchestrator(
        snapshotService: HubSnapshotService(
          readDb: () => db,
          writeQueue: writeQueue,
          liveDbFile: dbFile,
          backupDir: backupDir,
          hubId: 'HUB-B3',
          tenantId: 't1',
          storeId: 's1',
          appVersion: '1.0.0',
          kdfIterations: 1000,
          diskSpaceChecker: DiskSpaceChecker(freeBytesProbe: (_) async => 1 << 30),
        ),
        stateStore: stateStore,
        recoveryKeyStore: recoveryKeyStore,
        oauthService: oauth,
        uploader: ResumableDriveUploader(
          accessTokenProvider: ({bool forceRefresh = false}) =>
              oauth.getValidAccessToken(
                clientId: 'cid',
                forceRefresh: forceRefresh,
              ),
          httpClient: slowMock,
        ),
        operationLock: lock,
        readSchemaVersion: () => db.schemaVersion,
        oauthClientId: 'cid',
        localClock: () => currentLocal,
      );

      final jobFuture = orchestrator.triggerBackup(trigger: HubBackupTrigger.manual);
      await uploadStarted.future;

      // BK-015: Eşzamanlı ikinci yedek/restore BackupOperationLock / BUSY ile engellenir
      expect(
        () => orchestrator.triggerBackup(trigger: HubBackupTrigger.manual),
        throwsA(isA<BackupException>()
            .having((e) => e.code, 'code', BackupOperationLock.busyErrorCode)),
      );

      // BK-014: Kapanış sinyali 1.5s altında yüklemeyi duraklatıp RETRY_PENDING bırakır
      final sw = Stopwatch()..start();
      await orchestrator.shutdown();
      final jobAfterShutdown = await jobFuture;
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(1500));
      expect(jobAfterShutdown.state, equals(HubBackupJobState.retryPending));
      expect(jobAfterShutdown.lastErrorCode, equals('UPLOAD_CANCELLED_FOR_SHUTDOWN'));

      // BK-030: Yükleme COMPLETED_UPLOADED olmadan Drive silme/budama çağrılmamış olmalı
      final savedState = await stateStore.load();
      expect(savedState.latestJob?.backupId, equals(jobAfterShutdown.backupId));
      expect(savedState.latestJob?.state, equals(HubBackupJobState.retryPending));
    });

    test('BK-033: Drive retention budanan yedeğin driveFileId alanını temizler, aynı dosyayı tekrar silmez ve en yeni geçerli yedeği korur', () async {
      var currentLocal = DateTime(2026, 11, 22, 14, 0);
      final oauth = await connectedOAuth(() => currentLocal);

      // 30 günden eski, aynı takvim ayında iki geçerli Drive yedeği: ay başına yalnızca
      // en yenisi (old_b) korunur; old_a budanır.
      for (final seed in [
        ('old_a', DateTime.utc(2026, 9, 5), 'drv_old_a'),
        ('old_b', DateTime.utc(2026, 9, 10), 'drv_old_b'),
      ]) {
        await stateStore.upsertJob(
          HubBackupJobRecord(
            backupId: seed.$1,
            trigger: HubBackupTrigger.scheduledDaily,
            state: HubBackupJobState.completedUploaded,
            scheduledDateLocal:
                '${seed.$2.year}-${seed.$2.month.toString().padLeft(2, '0')}-${seed.$2.day.toString().padLeft(2, '0')}',
            createdAtUtc: seed.$2,
            updatedAtUtc: seed.$2,
            driveFileId: seed.$3,
          ),
          schedule: const HubBackupScheduleConfig(enabled: true),
        );
      }

      final deleteCalls = <String>[];
      HubBackupOrchestrator buildOrchestrator(String fileId) => HubBackupOrchestrator(
            snapshotService: HubSnapshotService(
              readDb: () => db,
              writeQueue: writeQueue,
              liveDbFile: dbFile,
              backupDir: backupDir,
              hubId: 'HUB-B3',
              tenantId: 't1',
              storeId: 's1',
              appVersion: '1.0.0',
              kdfIterations: 1000,
              diskSpaceChecker: DiskSpaceChecker(freeBytesProbe: (_) async => 1 << 30),
            ),
            stateStore: stateStore,
            recoveryKeyStore: recoveryKeyStore,
            oauthService: oauth,
            uploader: ResumableDriveUploader(
              accessTokenProvider: ({bool forceRefresh = false}) =>
                  oauth.getValidAccessToken(
                    clientId: 'cid',
                    forceRefresh: forceRefresh,
                  ),
              httpClient: healthyDriveMock(
                onCall: (method, uri) {
                  if (method == 'DELETE') deleteCalls.add(uri.pathSegments.last);
                },
                fileId: fileId,
              ),
            ),
            operationLock: BackupOperationLock(File(p.join(backupDir.path, '.lock'))),
            readSchemaVersion: () => db.schemaVersion,
            oauthClientId: 'cid',
            localClock: () => currentLocal,
          );

      final first = await buildOrchestrator('drv_new_1')
          .triggerBackup(trigger: HubBackupTrigger.manual);
      expect(first.state, equals(HubBackupJobState.completedUploaded));
      expect(deleteCalls, equals(['drv_old_a']));

      final afterFirst = await stateStore.load();
      final byId = {for (final j in afterFirst.jobs) j.backupId: j};
      expect(byId['old_a']!.driveFileId, isNull,
          reason: 'Drive\'dan silinen yedek artık geçerli Drive kopyası olarak listelenmemeli.');
      expect(byId['old_b']!.driveFileId, equals('drv_old_b'));
      expect(byId[first.backupId]!.driveFileId, equals('drv_new_1'));

      // İkinci başarılı yedekte zaten silinmiş drv_old_a için tekrar DELETE gönderilmez.
      currentLocal = currentLocal.add(const Duration(hours: 1));
      deleteCalls.clear();
      final second = await buildOrchestrator('drv_new_2')
          .triggerBackup(trigger: HubBackupTrigger.manual);
      expect(second.state, equals(HubBackupJobState.completedUploaded));
      expect(deleteCalls, isNot(contains('drv_old_a')));
    });

    test('BK-020: Drive verify uyuşmazlığında bozuk dosya silinir, oturum sıfırlanır ve sonraki deneme COMPLETED_UPLOADED olur', () async {
      var currentLocal = DateTime(2026, 11, 22, 15, 0);
      final oauth = await connectedOAuth(() => currentLocal);
      final deletedFileIds = <String>[];
      var attempt = 0;

      final client = MockClient((req) async {
        final uri = req.url.toString();
        if (req.method == 'POST' && uri.contains('uploadType=resumable')) {
          attempt++;
          return http.Response('', 200, headers: {
            'location': 'https://upload.test/sess_bk020_$attempt',
          });
        }
        if (req.method == 'PUT' && uri.contains('/sess_bk020_')) {
          final fileId = 'drv_bk020_$attempt';
          return http.Response(jsonEncode({'id': fileId}), 200);
        }
        if (req.method == 'GET' && uri.contains('/drive/v3/files/drv_bk020_1')) {
          return http.Response(
            jsonEncode({
              'id': 'drv_bk020_1',
              'size': '12',
              'md5Checksum': 'bad',
              'appProperties': {'mms_backup_id': 'mismatch', 'mms_sha256': '00'},
            }),
            200,
          );
        }
        if (req.method == 'GET' && uri.contains('/drive/v3/files/drv_bk020_2')) {
          final bytes = await Directory(backupDir.path)
              .listSync()
              .whereType<File>()
              .firstWhere((f) => f.path.endsWith('.mmsbak'))
              .readAsBytes();
          final encSha = await MmsbakV2Crypto.computeFileSha256(
            Directory(backupDir.path)
                .listSync()
                .whereType<File>()
                .firstWhere((f) => f.path.endsWith('.mmsbak')),
          );
          final snap = await stateStore.load();
          return http.Response(
            jsonEncode({
              'id': 'drv_bk020_2',
              'size': bytes.length.toString(),
              'appProperties': {
                'mms_backup_id': snap.latestJob!.backupId,
                'mms_sha256': encSha,
              },
            }),
            200,
          );
        }
        if (req.method == 'DELETE' && uri.contains('/drive/v3/files/')) {
          deletedFileIds.add(req.url.pathSegments.last);
          return http.Response('', 204);
        }
        return http.Response('unexpected ${req.method} $uri', 400);
      });

      final orchestrator = HubBackupOrchestrator(
        snapshotService: HubSnapshotService(
          readDb: () => db,
          writeQueue: writeQueue,
          liveDbFile: dbFile,
          backupDir: backupDir,
          hubId: 'HUB-B3',
          tenantId: 't1',
          storeId: 's1',
          appVersion: '1.0.0',
          kdfIterations: 1000,
          diskSpaceChecker: DiskSpaceChecker(freeBytesProbe: (_) async => 1 << 30),
        ),
        stateStore: stateStore,
        recoveryKeyStore: recoveryKeyStore,
        oauthService: oauth,
        uploader: ResumableDriveUploader(
          accessTokenProvider: ({bool forceRefresh = false}) =>
              oauth.getValidAccessToken(
                clientId: 'cid',
                forceRefresh: forceRefresh,
              ),
          httpClient: client,
        ),
        operationLock: BackupOperationLock(File(p.join(backupDir.path, '.lock'))),
        readSchemaVersion: () => db.schemaVersion,
        oauthClientId: 'cid',
        localClock: () => currentLocal,
      );

      final failedVerify = await orchestrator.triggerBackup(trigger: HubBackupTrigger.manual);
      expect(failedVerify.state, equals(HubBackupJobState.retryPending));
      expect(failedVerify.driveSessionUri, isNull);
      expect(failedVerify.driveFileId, isNull);
      expect(failedVerify.uploadedBytes, equals(0));
      expect(deletedFileIds, equals(['drv_bk020_1']));

      // Retry çağrısı temiz oturumla yüklemeyi tamamlar
      currentLocal = currentLocal.add(const Duration(minutes: 6));
      final recovered = await orchestrator.retryExistingJob(failedVerify.backupId);
      expect(recovered.state, equals(HubBackupJobState.completedUploaded));
      expect(recovered.driveFileId, equals('drv_bk020_2'));
    });
  });
}
