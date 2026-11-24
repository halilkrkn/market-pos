// Commit öncesi bağımsız inceleme bulguları S1 / S2 / S3 / S5 (Hub tarafı) regresyon testleri.
//
// Tüm testler geçici dizinlerde (`mms_test_only_s1s6_*`) sentetik veriyle çalışır; gerçek
// Hub veritabanına, gerçek Google Drive'a veya gerçek OAuth tokenlarına erişmez.
// Drive çağrıları `MockClient` ile taklit edilir.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

const _storedPassword = 'HubKayitliParola-S2-2026!';

/// Belirli bir anda `load()` çağrısını hata ile sonuçlandırabilen test durum deposu
/// (gerçek disk/durum dosyası hatası simülasyonu).
class _FlakyStateStore extends HubBackupStateStore {
  bool failLoads = false;
  int loadCalls = 0;

  _FlakyStateStore(super.file);

  @override
  Future<HubBackupJobsSnapshot> load() {
    loadCalls++;
    if (failLoads) {
      throw const FileSystemException('Simüle edilmiş durum dosyası okuma hatası');
    }
    return super.load();
  }
}

void main() {
  late Directory tempDir;
  late File dbFile;
  late Directory backupDir;
  late Directory securityDir;
  late SpikeDatabase db;
  late WriteQueue writeQueue;
  late File stateFile;
  late HubRecoveryKeyStore recoveryKeyStore;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    tempDir = Directory.systemTemp.createTempSync('mms_test_only_s1s6_');
    dbFile = File(p.join(tempDir.path, 'data', 'market_master.db'));
    await dbFile.parent.create(recursive: true);
    backupDir = Directory(p.join(tempDir.path, 'backups'));
    securityDir = Directory(p.join(tempDir.path, 'security'));
    await securityDir.create(recursive: true);
    db = SpikeDatabase(dbFile);
    writeQueue = WriteQueue();
    await db.customStatement('SELECT 1;');
    stateFile = File(p.join(backupDir.path, HubBackupStateStore.defaultFileName));
    recoveryKeyStore = HubRecoveryKeyStore(
      File(p.join(securityDir.path, HubRecoveryKeyStore.defaultFileName)),
    );
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

  Future<HubBackupOAuthService> connectedOAuth(
    DateTime Function() clock, {
    String? folderId = 'folder_hub_cached',
    String? folderLayout = HubBackupOAuthCredentials.hubSubfolderLayout,
  }) async {
    final store = HubBackupOAuthStore(
      File(p.join(securityDir.path, HubBackupOAuthStore.defaultFileName)),
    );
    await store.save(HubBackupOAuthCredentials(
      accessToken: 'acc_s1s6_valid',
      refreshToken: 'ref_s1s6_valid',
      expiresAtUtc: clock().toUtc().add(const Duration(hours: 1)),
      accountEmail: 'owner@market.test',
      scope: 'https://www.googleapis.com/auth/drive.file',
      folderId: folderId,
      folderLayout: folderLayout,
      connectedAtUtc: clock().toUtc(),
    ));
    return HubBackupOAuthService(
      store: store,
      httpClient: MockClient((req) async => http.Response('{}', 200)),
      clock: clock,
    );
  }

  /// Sağlıklı Drive taklidi. [onDelete] verilirse DELETE çağrısı onu bekler.
  MockClient driveMock({
    String fileId = 'drv_s1s6_ok',
    Future<void> Function(String fileId)? onDelete,
    List<http.Request>? recorder,
    Map<String, List<Map<String, dynamic>>> folderSearchResults = const {},
  }) {
    final uploadedSizes = <String, int>{};
    final appPropsMap = <String, Map<String, dynamic>>{};
    final md5Map = <String, String>{};
    return MockClient((req) async {
      recorder?.add(req);
      final uri = req.url.toString();
      if (req.method == 'GET' &&
          req.url.path == '/drive/v3/files' &&
          (req.url.queryParameters['q'] ?? '').contains('google-apps.folder')) {
        final q = req.url.queryParameters['q']!;
        for (final entry in folderSearchResults.entries) {
          if (q.contains(entry.key)) {
            return http.Response(jsonEncode({'files': entry.value}), 200);
          }
        }
        return http.Response(jsonEncode({'files': []}), 200);
      }
      if (req.method == 'POST' &&
          req.url.path == '/drive/v3/files' &&
          !uri.contains('uploadType')) {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final name = body['name'] as String;
        return http.Response(jsonEncode({'id': 'created_${name.replaceAll(' ', '_')}'}), 200);
      }
      if (req.method == 'POST' && uri.contains('uploadType=resumable')) {
        final decoded = jsonDecode(req.body) as Map<String, dynamic>;
        appPropsMap[fileId] = Map<String, dynamic>.from(
          decoded['appProperties'] as Map? ?? const {},
        );
        return http.Response('', 200, headers: {'location': 'https://upload.test/sess/$fileId'});
      }
      if (req.method == 'PUT' && uri.contains('/sess/')) {
        final range = req.headers['content-range'] ?? '';
        if (range.startsWith('bytes */')) return http.Response('', 308);
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
        await onDelete?.call(req.url.pathSegments.last);
        return http.Response('', 204);
      }
      return http.Response('Unexpected ${req.method} $uri', 400);
    });
  }

  HubBackupOrchestrator buildOrchestrator({
    required HubBackupStateStore stateStore,
    required HubBackupOAuthService oauth,
    required http.Client drive,
    required DateTime Function() clock,
    BackupOperationLock? lock,
    List<String>? logs,
    Duration checkInterval = const Duration(minutes: 1),
    String? subfolderName,
    Map<String, String> extraAppProperties = const {},
  }) {
    return HubBackupOrchestrator(
      snapshotService: HubSnapshotService(
        readDb: () => db,
        writeQueue: writeQueue,
        liveDbFile: dbFile,
        backupDir: backupDir,
        hubId: 'HUB-S1S6',
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
        httpClient: drive,
        subfolderName: subfolderName,
        extraAppProperties: extraAppProperties,
      ),
      operationLock: lock ?? BackupOperationLock(File(p.join(backupDir.path, '.lock'))),
      readSchemaVersion: () => db.schemaVersion,
      oauthClientId: 'cid',
      localClock: clock,
      checkInterval: checkInterval,
      log: logs == null ? null : logs.add,
    );
  }

  // ---------------------------------------------------------------------------
  // S1 — Dakikalık zamanlayıcı Hub sürecini çökertmez
  // ---------------------------------------------------------------------------
  group('S1: Hub yedekleme zamanlayıcısı hata dayanıklılığı', () {
    for (final kind in BackupOperationKind.values) {
      test('Kilit başka bir ${kind.name} işleminde (eski 24s yerel yedek / restore / temizlik) '
          'iken tur hatasız ertelenir, kilit boşalınca sonraki tur çalışır', () async {
        await recoveryKeyStore.saveRecoveryPassword(_storedPassword);
        final clock = DateTime(2026, 11, 22, 0, 5); // 00:00 + 5 dk → SCHEDULED_DAILY
        final stateStore = HubBackupStateStore(stateFile);
        await stateStore.updateSchedule(const HubBackupScheduleConfig(enabled: true));
        final lockFile = File(p.join(backupDir.path, '.lock'));
        final logs = <String>[];
        final orch = buildOrchestrator(
          stateStore: stateStore,
          oauth: await connectedOAuth(() => clock),
          drive: driveMock(),
          clock: () => clock,
          lock: BackupOperationLock(lockFile),
          logs: logs,
        );

        // Başka bir işlem (ör. eski ScheduledBackupRunner veya HubRestoreService) aynı
        // dosya kilidini tutuyor.
        final held = await BackupOperationLock(lockFile).acquire(kind);
        final deferred = await orch.runGuardedTick();
        expect(deferred, isNull);
        expect(orch.lastSchedulerError, isNull,
            reason: 'Kilit çakışması hata olarak kaydedilmemeli.');
        expect(logs.any((l) => l.contains('kilidi başka bir işlemde')), isTrue);
        expect((await stateStore.load()).jobs, isEmpty,
            reason: 'Kilit alınamadığında yarım iş kaydı oluşturulmamalı.');

        await held.release();
        final ran = await orch.runGuardedTick();
        expect(ran, isNotNull);
        expect(ran!.state, equals(HubBackupJobState.completedUploaded));
        expect(ran.trigger, equals(HubBackupTrigger.scheduledDaily));
      });
    }

    test('Manuel yedek sürerken gelen zamanlayıcı turu yarışmaz ve hata fırlatmaz', () async {
      await recoveryKeyStore.saveRecoveryPassword(_storedPassword);
      final clock = DateTime(2026, 11, 22, 1, 0);
      final stateStore = HubBackupStateStore(stateFile);
      await stateStore.updateSchedule(const HubBackupScheduleConfig(enabled: true));
      final uploadStarted = Completer<void>();
      final releaseUpload = Completer<void>();
      var putCalls = 0;
      final slow = MockClient((req) async {
        if (req.method == 'POST' && req.url.toString().contains('uploadType=resumable')) {
          return http.Response('', 200, headers: {'location': 'https://upload.test/sess/slow'});
        }
        if (req.method == 'PUT') {
          putCalls++;
          if (!uploadStarted.isCompleted) uploadStarted.complete();
          await releaseUpload.future;
          return http.Response('', 503);
        }
        return http.Response('{}', 200);
      });
      final orch = buildOrchestrator(
        stateStore: stateStore,
        oauth: await connectedOAuth(() => clock),
        drive: slow,
        clock: () => clock,
        logs: <String>[],
      );

      final manual = orch.triggerBackup(trigger: HubBackupTrigger.manual);
      await uploadStarted.future;
      final tick = await orch.runGuardedTick();
      expect(tick, isNull);
      expect(orch.lastSchedulerError, isNull);
      expect(putCalls, equals(1), reason: 'Zamanlayıcı ikinci bir yükleme başlatmamalı.');

      releaseUpload.complete();
      final manualResult = await manual;
      expect(manualResult.trigger, equals(HubBackupTrigger.manual));
      expect((await stateStore.load()).jobs.length, equals(1));
    });

    test('Kurtarma parolası dosyası okunamıyor: tur süreci çökertmez, hata bir kez '
        'loglanır, parola düzeltilince sonraki tur çalışır', () async {
      final clock = DateTime(2026, 11, 22, 1, 0);
      final stateStore = HubBackupStateStore(stateFile);
      await stateStore.updateSchedule(const HubBackupScheduleConfig(enabled: true));
      // Bozuk DPAPI kasası (çözülemeyen bayt dizisi)
      await recoveryKeyStore.file.writeAsBytes([1, 2, 3, 4, 5, 6, 7, 8]);
      final logs = <String>[];
      final orch = buildOrchestrator(
        stateStore: stateStore,
        oauth: await connectedOAuth(() => clock),
        drive: driveMock(),
        clock: () => clock,
        logs: logs,
      );

      expect(await orch.runGuardedTick(), isNull);
      expect(await orch.runGuardedTick(), isNull);
      expect(orch.lastSchedulerError?.code, equals('ERR_DPAPI_RECOVERY_KEY'));
      expect(
        logs.where((l) => l.contains('ERR_DPAPI_RECOVERY_KEY')).length,
        equals(1),
        reason: 'Aynı hata her dakika tekrar loglanmamalı (ama ilk seferde mutlaka loglanmalı).',
      );
      expect(logs.join('\n').contains(_storedPassword), isFalse);

      await recoveryKeyStore.saveRecoveryPassword(_storedPassword);
      final ran = await orch.runGuardedTick();
      expect(ran?.state, equals(HubBackupJobState.completedUploaded));
      expect(orch.lastSchedulerError, isNull);
    });

    test('Gerçek durum dosyası hatası tura sızmaz; sonraki turda zamanlayıcı devam eder', () async {
      await recoveryKeyStore.saveRecoveryPassword(_storedPassword);
      final clock = DateTime(2026, 11, 22, 1, 0);
      final stateStore = _FlakyStateStore(stateFile);
      await stateStore.updateSchedule(const HubBackupScheduleConfig(enabled: true));
      final logs = <String>[];
      final orch = buildOrchestrator(
        stateStore: stateStore,
        oauth: await connectedOAuth(() => clock),
        drive: driveMock(),
        clock: () => clock,
        logs: logs,
      );

      stateStore.failLoads = true;
      expect(await orch.runGuardedTick(), isNull);
      expect(orch.lastSchedulerError?.code, equals('ERR_HUB_BACKUP_SCHEDULER'));
      expect(logs.any((l) => l.contains('ERR_HUB_BACKUP_SCHEDULER')), isTrue);

      stateStore.failLoads = false;
      final ran = await orch.runGuardedTick();
      expect(ran?.state, equals(HubBackupJobState.completedUploaded));
      expect(orch.lastSchedulerError, isNull);
    });

    test('Gerçek yedekleme hatası (Drive 5xx) işi RETRY_PENDING yapar, tur hatası sayılmaz', () async {
      await recoveryKeyStore.saveRecoveryPassword(_storedPassword);
      final clock = DateTime(2026, 11, 22, 1, 0);
      final stateStore = HubBackupStateStore(stateFile);
      await stateStore.updateSchedule(const HubBackupScheduleConfig(enabled: true));
      final orch = buildOrchestrator(
        stateStore: stateStore,
        oauth: await connectedOAuth(() => clock),
        drive: MockClient((req) async => http.Response('down', 503)),
        clock: () => clock,
        logs: <String>[],
      );
      final job = await orch.runGuardedTick();
      expect(job?.state, equals(HubBackupJobState.retryPending));
      expect(orch.lastSchedulerError, isNull);
    });

    test('Timer.periodic ile gerçek zamanlayıcı: hatalı turlar yakalanmamış asenkron hata '
        'üretmez ve turlar devam eder', () async {
      final clock = DateTime(2026, 11, 22, 1, 0);
      final stateStore = _FlakyStateStore(stateFile);
      await stateStore.updateSchedule(const HubBackupScheduleConfig(enabled: true));
      await recoveryKeyStore.file.writeAsBytes([9, 9, 9, 9]);
      final uncaught = <Object>[];
      late HubBackupOrchestrator orch;
      final oauth = await connectedOAuth(() => clock);

      await runZonedGuarded(() async {
        orch = buildOrchestrator(
          stateStore: stateStore,
          oauth: oauth,
          drive: driveMock(),
          clock: () => clock,
          logs: <String>[],
          checkInterval: const Duration(milliseconds: 40),
        );
        orch.start();
        await Future<void>.delayed(const Duration(milliseconds: 160));
        stateStore.failLoads = true; // farklı bir hata türüne geç
        await Future<void>.delayed(const Duration(milliseconds: 160));
        await orch.shutdown();
      }, (e, _) => uncaught.add(e));

      expect(uncaught, isEmpty,
          reason: 'Zamanlayıcı hatası Timer geri çağrısından sızıp süreci sonlandırmamalı.');
      expect(stateStore.loadCalls, greaterThan(3), reason: 'Turlar hata sonrasında da sürmeli.');
      expect(orch.lastSchedulerError, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // S2 — Yedek yalnızca kayıtlı kurtarma parolasıyla şifrelenir
  // ---------------------------------------------------------------------------
  group('S2: Manuel yedek kayıtlı Portable Recovery Password kullanır', () {
    test('Kayıtlı parola yokken manuel yedek ERR_RECOVERY_KEY_REQUIRED ile reddedilir', () async {
      final clock = DateTime(2026, 11, 22, 10, 0);
      final stateStore = HubBackupStateStore(stateFile);
      final orch = buildOrchestrator(
        stateStore: stateStore,
        oauth: await connectedOAuth(() => clock),
        drive: driveMock(),
        clock: () => clock,
      );
      await expectLater(
        orch.triggerBackup(trigger: HubBackupTrigger.manual),
        throwsA(isA<HubRecoveryKeyException>()
            .having((e) => e.code, 'code', 'ERR_RECOVERY_KEY_REQUIRED')),
      );
      expect((await stateStore.load()).jobs, isEmpty);
    });

    test('Kayıtlı parola ile manuel yedek: paket kayıtlı parolayla çözülür, başka parolayla çözülemez', () async {
      await recoveryKeyStore.saveRecoveryPassword(_storedPassword);
      final clock = DateTime(2026, 11, 22, 10, 0);
      final stateStore = HubBackupStateStore(stateFile);
      final orch = buildOrchestrator(
        stateStore: stateStore,
        oauth: await connectedOAuth(() => clock),
        drive: driveMock(),
        clock: () => clock,
      );
      final job = await orch.triggerBackup(trigger: HubBackupTrigger.manual);
      expect(job.state, equals(HubBackupJobState.completedUploaded));
      final pkg = File(job.encryptedPath!);
      expect(await pkg.exists(), isTrue);

      final out = File(p.join(tempDir.path, 'verify_restore.db'));
      final manifest = await MmsbakV2Crypto.decryptFile(
        inputFile: pkg,
        outputFile: out,
        password: _storedPassword,
      );
      expect(manifest.backupId, equals(job.backupId));
      await expectLater(
        MmsbakV2Crypto.decryptFile(
          inputFile: pkg,
          outputFile: File(p.join(tempDir.path, 'wrong.db')),
          password: 'BaskaBirParola-Kaydedilmemis-1',
        ),
        throwsA(isA<BackupCryptoException>()),
      );
    });

    group('HTTP /api/v1/backup/run', () {
      late SpikeServer server;
      late HttpServer ioServer;
      late String baseUrl;
      late String ownerToken;
      late String cashierToken;
      late HubRecoveryKeyStore serverKeyStore;
      late http.Client client;
      var nonce = 0;

      setUp(() async {
        configureSqliteNative();
        final pepper = PepperManager(File(p.join(securityDir.path, 'pepper.dpapi')))
          ..initialize(overrideForTesting: 'pepper_s2_backup_run_secret_32bytes');
        serverKeyStore = HubRecoveryKeyStore(
          File(p.join(securityDir.path, 'server_${HubRecoveryKeyStore.defaultFileName}')),
        );
        server = SpikeServer(
          db: db,
          writeQueue: writeQueue,
          dbFile: dbFile,
          backupDirectory: backupDir.path,
          pepperManager: pepper,
          adminSecret: 'admin_secret_s2_test',
          hubRecoveryKeyStore: serverKeyStore,
          hubRestoreSafetyKdfIterations: 1000,
        );
        ioServer = await shelf_io.serve(server.handler, InternetAddress.loopbackIPv4, 0);
        baseUrl = 'http://127.0.0.1:${ioServer.port}';
        client = http.Client();

        Future<String> device(String id, String role) async {
          final raw = 'tok_${id}_secret';
          final salt = TokenManager.generateSalt();
          await db.into(db.devices).insert(DevicesCompanion.insert(
                deviceId: id,
                name: 'Cihaz $id',
                tokenHash: TokenManager.hashToken(rawToken: raw, salt: salt, pepper: pepper.pepper),
                salt: salt,
                isActive: const Value(true),
                isConfirmed: const Value(true),
                role: Value(role),
              ));
          return raw;
        }

        ownerToken = await device('POS-OWNER-S2', 'OWNER');
        cashierToken = await device('POS-CASHIER-S2', 'CASHIER');
      });

      tearDown(() async {
        client.close();
        await ioServer.close(force: true);
      });

      Map<String, String> headers({String? bearer, bool admin = false}) => {
            'content-type': 'application/json',
            if (bearer != null) 'authorization': 'Bearer $bearer',
            if (admin) 'x-mms-admin-secret': 'admin_secret_s2_test',
            'x-mms-timestamp': DateTime.now().toUtc().toIso8601String(),
            'x-mms-nonce': 'nonce_s2_${nonce++}_${DateTime.now().microsecondsSinceEpoch}',
          };

      Future<http.Response> run(Map<String, dynamic> body, {String? bearer, bool admin = false}) =>
          client.post(
            Uri.parse('$baseUrl/api/v1/backup/run'),
            headers: headers(bearer: bearer, admin: admin),
            body: jsonEncode(body),
          );

      test('Uzak OWNER istekte farklı parola gönderirse reddedilir; kayıtlı parola değişmez, iş oluşmaz', () async {
        await serverKeyStore.saveRecoveryPassword(_storedPassword);
        final resp = await run({'recovery_password': 'UzaktanGelenFarkliParola-99'}, bearer: ownerToken);
        expect(resp.statusCode, equals(400));
        expect(jsonDecode(resp.body)['code'], equals('ERR_RECOVERY_PASSWORD_NOT_ACCEPTED'));
        expect(await serverKeyStore.loadRecoveryPassword(), equals(_storedPassword));
        expect((await server.hubBackupStateStore.load()).jobs, isEmpty);
      });

      test('Windows (loopback admin) kaydedilmemiş parola ile yedek başlatamaz', () async {
        final resp = await run({'recovery_password': 'KaydedilmemisEkranParolasi-1'}, admin: true);
        expect(resp.statusCode, equals(400));
        expect(jsonDecode(resp.body)['code'], equals('ERR_RECOVERY_PASSWORD_NOT_ACCEPTED'));
        expect(await serverKeyStore.hasRecoveryPassword(), isFalse,
            reason: '/backup/run parolayı asla kaydetmez; kaydetme ayrı uçtur.');
      });

      test('Kayıtlı parola yokken parolasız manuel yedek ERR_RECOVERY_KEY_REQUIRED (fail-closed)', () async {
        final resp = await run(const {}, bearer: ownerToken);
        expect(resp.statusCode, equals(400));
        expect(jsonDecode(resp.body)['code'], equals('ERR_RECOVERY_KEY_REQUIRED'));
        expect((await server.hubBackupStateStore.load()).jobs, isEmpty);
      });

      test('CASHIER yetkisi parola gövdesinden bağımsız olarak 403 alır', () async {
        final resp = await run({'recovery_password': 'Cashier-Denemesi-1234'}, bearer: cashierToken);
        expect(resp.statusCode, equals(403));
        expect(jsonDecode(resp.body)['code'], equals('ERR_OWNER_ROLE_REQUIRED'));
      });
    });
  });

  // ---------------------------------------------------------------------------
  // S3 — Durum deposu eşzamanlılığı
  // ---------------------------------------------------------------------------
  group('S3: backup_jobs_state.json eşzamanlı güncellemeler', () {
    HubBackupJobRecord job(String id, {String? driveFileId, DateTime? created}) {
      final c = created ?? DateTime.utc(2026, 11, 22);
      return HubBackupJobRecord(
        backupId: id,
        trigger: HubBackupTrigger.scheduledDaily,
        state: HubBackupJobState.completedUploaded,
        scheduledDateLocal:
            '${c.year}-${c.month.toString().padLeft(2, '0')}-${c.day.toString().padLeft(2, '0')}',
        createdAtUtc: c,
        updatedAtUtc: c,
        driveFileId: driveFileId,
      );
    }

    test('Drive retention silmesi beklerken yapılan zamanlama değişikliği ve iş güncellemesi kaybolmaz', () async {
      await recoveryKeyStore.saveRecoveryPassword(_storedPassword);
      final clock = DateTime(2026, 11, 22, 14, 0);
      final stateStore = HubBackupStateStore(stateFile);
      await stateStore.upsertJob(job('old_a', driveFileId: 'drv_old_a', created: DateTime.utc(2026, 9, 5)),
          schedule: const HubBackupScheduleConfig(enabled: true));
      await stateStore.upsertJob(job('old_b', driveFileId: 'drv_old_b', created: DateTime.utc(2026, 9, 6)));
      await stateStore.upsertJob(job('old_c', driveFileId: 'drv_old_c', created: DateTime.utc(2026, 9, 7)));

      final deleteStarted = Completer<void>();
      final releaseDelete = Completer<void>();
      final deleted = <String>[];
      final orch = buildOrchestrator(
        stateStore: stateStore,
        oauth: await connectedOAuth(() => clock),
        drive: driveMock(
          fileId: 'drv_new',
          onDelete: (fid) async {
            deleted.add(fid);
            if (!deleteStarted.isCompleted) deleteStarted.complete();
            await releaseDelete.future;
          },
        ),
        clock: () => clock,
      );

      final backup = orch.triggerBackup(trigger: HubBackupTrigger.manual);
      await deleteStarted.future;

      // Retention Drive silmesini beklerken: (1) zamanlama 03:30'a alınır,
      // (2) budanacak bir işin Drive kopyası başka bir işlemce yenilenmiş olur.
      await orch.configureSchedule(
        enabled: true,
        dailyHourLocal: 3,
        dailyMinuteLocal: 30,
        triggerInitialIfDue: false,
      );
      await stateStore.patchJobs({'old_a'}, (j) => job('old_a', driveFileId: 'drv_old_a_REUPLOADED', created: j.createdAtUtc));

      releaseDelete.complete();
      final done = await backup;
      expect(done.state, equals(HubBackupJobState.completedUploaded));
      expect(deleted, isNotEmpty);

      final after = await HubBackupStateStore(stateFile).load(); // yeniden başlatma simülasyonu
      expect(after.schedule.enabled, isTrue);
      expect(after.schedule.dailyHourLocal, equals(3),
          reason: 'Retention eski durum nesnesini geri yazıp yeni zamanlamayı ezmemeli.');
      expect(after.schedule.dailyMinuteLocal, equals(30));
      final byId = {for (final j in after.jobs) j.backupId: j};
      expect(byId['old_a']!.driveFileId, equals('drv_old_a_REUPLOADED'),
          reason: 'Yalnızca silinen dosyayı gösteren alan temizlenmeli.');
      expect(byId[done.backupId]!.driveFileId, equals('drv_new'));
      for (final id in deleted.where((f) => f != 'drv_old_a').map((f) => f.replaceFirst('drv_', ''))) {
        expect(byId[id]!.driveFileId, isNull, reason: '$id Drive\'dan silindi; alan temizlenmeli.');
      }
    });

    test('Aynı anda çok sayıda iş ve zamanlama güncellemesi kayıpsız uygulanır', () async {
      final stateStore = HubBackupStateStore(stateFile);
      final secondInstance = HubBackupStateStore(stateFile); // aynı dosya, farklı örnek
      await Future.wait([
        for (var i = 0; i < 25; i++)
          (i.isEven ? stateStore : secondInstance).upsertJob(job('job_$i')),
        stateStore.updateSchedule(const HubBackupScheduleConfig(enabled: true, dailyHourLocal: 5)),
      ]);
      final after = await stateStore.load();
      expect(after.jobs.map((j) => j.backupId).toSet().length, equals(25));
      expect(after.schedule.enabled, isTrue);
      expect(after.schedule.dailyHourLocal, equals(5));
    });

    test('Dönüştürücü ortasında hata: disk durumu değişmez, sonraki güncelleme çalışır', () async {
      final stateStore = HubBackupStateStore(stateFile);
      await stateStore.upsertJob(job('keep_me'));
      final before = await stateFile.readAsString();
      await expectLater(
        stateStore.update((_) => throw StateError('işlem ortasında hata')),
        throwsA(isA<StateError>()),
      );
      expect(await stateFile.readAsString(), equals(before));
      await stateStore.updateSchedule(const HubBackupScheduleConfig(enabled: true));
      final after = await HubBackupStateStore(stateFile).load();
      expect(after.jobs.single.backupId, equals('keep_me'));
      expect(after.schedule.enabled, isTrue);
      expect(await File('${stateFile.path}.tmp').exists(), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // S5 — Hub yedekleri `MARKET MMS Yedekleri/Hub` alt klasörüne gider
  // ---------------------------------------------------------------------------
  group('S5: Hub Drive klasör ayrımı ve eski önbellek geçişi', () {
    test('Eski kök klasör önbelleği yok sayılır; Hub alt klasörü kök altında bulunur/oluşturulur, '
        'kasa yeni düzenle güncellenir', () async {
      await recoveryKeyStore.saveRecoveryPassword(_storedPassword);
      final clock = DateTime(2026, 11, 22, 10, 0);
      // Geçiş öncesi kurulum: kasada kök klasör kimliği, düzen işareti yok.
      final oauth = await connectedOAuth(() => clock, folderId: 'legacy_root_id', folderLayout: null);
      final requests = <http.Request>[];
      final orch = buildOrchestrator(
        stateStore: HubBackupStateStore(stateFile),
        oauth: oauth,
        drive: driveMock(
          recorder: requests,
          folderSearchResults: {
            "name = 'MARKET MMS Yedekleri'": [
              {'id': 'legacy_root_id', 'name': 'MARKET MMS Yedekleri'},
            ],
          },
        ),
        clock: () => clock,
        subfolderName: MmsDriveBackupFolders.hubSubfolderName,
        extraAppProperties: const {
          MmsDriveBackupFolders.backupSourceProperty: MmsDriveBackupFolders.hubBackupSource,
        },
      );

      final job = await orch.triggerBackup(trigger: HubBackupTrigger.manual);
      expect(job.state, equals(HubBackupJobState.completedUploaded));

      final subSearch = requests.firstWhere((r) =>
          r.method == 'GET' && (r.url.queryParameters['q'] ?? '').contains("name = 'Hub'"));
      expect(subSearch.url.queryParameters['q'], contains("'legacy_root_id' in parents"));
      final createSub = requests.firstWhere((r) =>
          r.method == 'POST' && r.url.path == '/drive/v3/files' && !r.url.toString().contains('uploadType'));
      final createBody = jsonDecode(createSub.body) as Map<String, dynamic>;
      expect(createBody['name'], equals('Hub'));
      expect(createBody['parents'], equals(['legacy_root_id']));

      final init = requests.firstWhere((r) => r.url.toString().contains('uploadType=resumable'));
      final initBody = jsonDecode(init.body) as Map<String, dynamic>;
      expect(initBody['parents'], equals(['created_Hub']),
          reason: 'Hub yedeği eski istemci kök klasörüne değil Hub alt klasörüne yüklenmeli.');
      expect((initBody['appProperties'] as Map)['mms_backup_source'], equals('HUB_CENTRAL'));

      expect(await oauth.getCachedHubFolderId(), equals('created_Hub'));

      // İkinci yedek: önbellek artık Hub düzeninde; klasör araması tekrarlanmaz.
      requests.clear();
      final second = await orch.triggerBackup(trigger: HubBackupTrigger.manual);
      expect(second.state, equals(HubBackupJobState.completedUploaded));
      expect(
        requests.where((r) => (r.url.queryParameters['q'] ?? '').contains('google-apps.folder')),
        isEmpty,
      );
    });
  });

  group('Bölüm 3.3 & 3.4: İki Zamanlayıcı Birlikte Çalışması, Kapanış ve scheduler_last_error Temizliği', () {
    test('Başarılı triggerBackup sonrası önceki scheduler_last_error temizlenir ve yol bilgisi sızmaz', () async {
      await recoveryKeyStore.saveRecoveryPassword(_storedPassword);
      final clock = DateTime(2026, 11, 22, 0, 5);
      final flakyStore = _FlakyStateStore(stateFile)..failLoads = true;
      final orch = buildOrchestrator(
        stateStore: flakyStore,
        oauth: await connectedOAuth(() => clock),
        drive: driveMock(),
        clock: () => clock,
      );

      await orch.runGuardedTick();
      expect(orch.lastSchedulerError, isNotNull);
      expect(orch.lastSchedulerError!.message, isNot(contains(tempDir.path)));

      flakyStore.failLoads = false;
      final completed = await orch.triggerBackup(trigger: HubBackupTrigger.manual);
      expect(completed.state, equals(HubBackupJobState.completedUploaded));
      expect(orch.lastSchedulerError, isNull,
          reason: 'Manuel yedekleme başarılı olduktan sonra eski scheduler_last_error temizlenmelidir.');
    });

    test('Eski 24s zamanlayıcı ile merkezi Drive zamanlayıcısı paralel başlar, aynı kilidi güvenli paylaşır ve kontrollü kapanır', () async {
      final serverDbFile = File(p.join(tempDir.path, 'data', 'dual_sched.db'));
      final serverDb = SpikeDatabase(serverDbFile);
      final pepper = PepperManager(File(p.join(securityDir.path, 'pepper_dual.dpapi')))
        ..initialize(overrideForTesting: 'pepper_dual_sched_32bytes_min_1234');
      await serverDb.into(serverDb.products).insert(
            ProductsCompanion.insert(
              id: 'prod_dual_1',
              barcode: '8690009990001',
              name: 'Dual Scheduler Ürün',
              price: 1500,
              stock: 3000,
            ),
          );
      await recoveryKeyStore.saveRecoveryPassword(_storedPassword);
      final serverWq = WriteQueue();
      final serverOauth = await connectedOAuth(() => DateTime.now());
      final customOrch = HubBackupOrchestrator(
        snapshotService: HubSnapshotService(
          readDb: () => serverDb,
          writeQueue: serverWq,
          liveDbFile: serverDbFile,
          backupDir: backupDir,
          hubId: SpikeServer.defaultHubId,
          tenantId: SpikeServer.defaultTenantId,
          storeId: SpikeServer.defaultStoreId,
          appVersion: '1.0.0',
          kdfIterations: 1000,
          diskSpaceChecker: DiskSpaceChecker(freeBytesProbe: (_) async => 1 << 30),
        ),
        stateStore: HubBackupStateStore(stateFile),
        recoveryKeyStore: recoveryKeyStore,
        oauthService: serverOauth,
        uploader: ResumableDriveUploader(
          accessTokenProvider: ({bool forceRefresh = false}) =>
              serverOauth.getValidAccessToken(
                clientId: 'cid',
                forceRefresh: forceRefresh,
              ),
          httpClient: driveMock(),
        ),
        operationLock: BackupOperationLock(File(p.join(backupDir.path, '.lock'))),
        readSchemaVersion: () => serverDb.schemaVersion,
        oauthClientId: 'cid',
      );

      final srv = SpikeServer(
        db: serverDb,
        dbFile: serverDbFile,
        writeQueue: serverWq,
        backupDirectory: backupDir.path,
        adminSecret: 'dual_sched_admin_2026',
        pepperManager: pepper,
        hubRecoveryKeyStore: recoveryKeyStore,
        hubBackupOAuthService: serverOauth,
        hubBackupOrchestrator: customOrch,
        backupSchedule: const BackupSchedulePolicy(interval: Duration(hours: 24)),
        backupCheckInterval: const Duration(milliseconds: 80),
      );

      await srv.start(address: InternetAddress.loopbackIPv4, port: 0, enableDiscovery: false);
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (srv.backupScheduleState?.lastSuccessAt == null) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Eski 24s zamanlayıcı beklenen sürede ilk yedeği tamamlayamadı.');
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      // Hub durdurulduğunda her iki zamanlayıcı da hata fırlatmadan temiz kapanır
      await srv.stop();
    });
  });
}
