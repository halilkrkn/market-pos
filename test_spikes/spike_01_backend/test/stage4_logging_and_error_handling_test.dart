import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/backup/hub_backup_state_store.dart';
import '../lib/backup/hub_recovery_key_store.dart';
import '../lib/backup/hub_restore_service.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/pepper_manager.dart';
import '../lib/security/token_manager.dart';

class _CapturedStderr implements Stdout {
  final List<String> lines = <String>[];
  final StringBuffer _buf = StringBuffer();

  @override
  void write(Object? object) => _buf.write(object ?? '');

  @override
  void writeln([Object? object = '']) {
    _buf.write(object ?? '');
    lines.add(_buf.toString());
    _buf.clear();
  }

  @override
  void writeAll(Iterable objects, [String separator = '']) =>
      _buf.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _buf.writeCharCode(charCode);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _ThrowingHubScheduleStore extends BackupScheduleStateStore {
  final Object error;

  _ThrowingHubScheduleStore(super.file, this.error);

  @override
  Future<BackupScheduleState> load() => Future<BackupScheduleState>.error(error);
}

void main() {
  group('AUD-LOW-01 Backend: Dosya Yolu Maskeleme & Sessiz Catch Giderimi', () {
    late Directory tempDir;

    setUp(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      tempDir = Directory.systemTemp.createTempSync('mms_test_only_low01_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      '1. Uzak OWNER /api/v1/backup/restore yanıtında safety_backup_path tam Hub dizin yapısını sızdırmaz',
      () async {
        configureSqliteNative();
        final dbFile = File(p.join(tempDir.path, 'hub_data', 'market_master.db'));
        await dbFile.parent.create(recursive: true);
        final backupDir = Directory(p.join(tempDir.path, 'hub_backups'));
        final secDir = Directory(p.join(tempDir.path, 'hub_sec'));
        await secDir.create(recursive: true);
        final db = SpikeDatabase(dbFile);
        await db.customStatement('SELECT 1;');
        final wq = WriteQueue();
        final pepper = PepperManager(File(p.join(secDir.path, 'pepper.dpapi')))
          ..initialize(overrideForTesting: 'pepper_low01_secret_32bytes_min!');

        const rawTok = 'mms_dt_owner_low01_tok';
        final salt = TokenManager.generateSalt();
        await db.into(db.devices).insert(
              DevicesCompanion.insert(
                deviceId: 'OWNER-REMOTE-01',
                name: 'Remote Owner',
                tokenHash: TokenManager.hashToken(
                  rawToken: rawTok,
                  salt: salt,
                  pepper: pepper.pepper,
                ),
                salt: salt,
                isActive: const Value(true),
                isConfirmed: const Value(true),
                role: const Value('OWNER'),
              ),
            );
        await db.into(db.products).insert(
              ProductsCompanion.insert(
                id: 'p1',
                barcode: '8690001119991',
                name: 'Test',
                price: 500,
                stock: 1000,
              ),
            );

        final tempSnap = File(p.join(tempDir.path, 'snap.db'));
        await db.customStatement(
          "VACUUM INTO '${tempSnap.path.replaceAll("'", "''")}';",
        );
        const pass = 'RemoteRestorePass-2026!';
        final pkg = File(p.join(backupDir.path, 'hub_backup_bak_low01.mmsbak'));
        final man = BackupManifest(
          backupId: 'bak_low01',
          deviceId: SpikeServer.defaultHubId,
          tenantId: SpikeServer.defaultTenantId,
          storeId: SpikeServer.defaultStoreId,
          databaseType: DatabaseType.centralMaster,
          schemaVersion: db.schemaVersion,
          appVersion: '1.0.0',
          timestamp: DateTime.now().toUtc(),
          checksum: await MmsbakV2Crypto.computeFileSha256(tempSnap),
          unencryptedSizeBytes: await tempSnap.length(),
          encryptedSizeBytes: 0,
        );
        await MmsbakV2Crypto.encryptFile(
          inputFile: tempSnap,
          outputFile: pkg,
          password: pass,
          manifest: man,
          kdfIterations: 1000,
        );

        final server = SpikeServer(
          db: db,
          dbFile: dbFile,
          writeQueue: wq,
          backupDirectory: backupDir.path,
          pepperManager: pepper,
          adminSecret: 'admin_low01_sec',
          hubRestoreSafetyKdfIterations: 1000,
        );
        final ioServer = await shelf_io.serve(
          server.handler,
          InternetAddress.loopbackIPv4,
          0,
        );
        final client = http.Client();
        try {
          final resp = await client.post(
            Uri.parse('http://127.0.0.1:${ioServer.port}/api/v1/backup/restore'),
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $rawTok',
              'x-mms-timestamp': DateTime.now().toUtc().toIso8601String(),
              'x-mms-nonce': 'nonce_low01_remote_1',
            },
            body: jsonEncode({
              'backup_id': 'bak_low01',
              'recovery_password': pass,
            }),
          );
          expect(resp.statusCode, equals(200));
          final body = jsonDecode(resp.body) as Map<String, dynamic>;
          final safetyPath = body['safety_backup_path'] as String;
          expect(safetyPath, isNotEmpty);
          expect(safetyPath, isNot(contains(tempDir.path)));
          expect(safetyPath, equals(p.basename(safetyPath)));
        } finally {
          client.close();
          await ioServer.close(force: true);
          await server.db.close();
        }
      },
    );

    test(
      '2. ResumableDriveUploader, HubBackupStateStore ve HubRestoreService uyarılarda tam dizin yolunu veya tokenı sızdırmaz',
      () async {
        // 2a. HubBackupStateStore karantina kaydı sadece basename içerir
        final secretDir = Directory(p.join(tempDir.path, 'secret_dir_name'));
        await secretDir.create(recursive: true);
        final storeFile = File(p.join(secretDir.path, 'backup_jobs_state.json'));
        await storeFile.writeAsString('{broken_json');
        final stateLogs = <String>[];
        final store = HubBackupStateStore(storeFile, log: stateLogs.add);
        final snap = await store.load();
        expect(snap.jobs, isEmpty);
        expect(stateLogs.single, contains('backup_jobs_state.json.corrupt_'));
        expect(stateLogs.single, isNot(contains('secret_dir_name')));
        expect(stateLogs.single, isNot(contains(tempDir.path)));

        // 2b. HubRestoreService hata/temizlik logları recoveryPassword veya tempDir sızdırmaz
        final restoreLogs = <String>[];
        final badPkg = File(p.join(tempDir.path, 'corrupt_pkg.mmsbak'));
        await badPkg.writeAsString('INVALID');
        final liveDb = File(p.join(tempDir.path, 'data', 'market_master.db'));
        final bDir = Directory(p.join(tempDir.path, 'bak_dir'));
        await bDir.create(recursive: true);
        final lock = BackupOperationLock(
          File(p.join(bDir.path, BackupOperationLock.defaultFileName)),
        );
        await expectLater(
          HubRestoreService.restoreFromEncryptedPackage(
            packageFile: badPkg,
            recoveryPassword: 'SuperSecretRecoveryPassword-2026!',
            liveDbFile: liveDb,
            backupDir: bDir,
            lock: lock,
            pauseAndCloseLiveDb: () async {},
            reopenLiveDb: (f) async => SpikeDatabase(f),
            expectedTenantId: 'tenant-1',
            expectedStoreId: 'store-1',
            log: restoreLogs.add,
          ),
          throwsA(anything),
        );
        final joinedRestoreLogs = restoreLogs.join('\n');
        expect(joinedRestoreLogs, isNot(contains(tempDir.path)));
        expect(
          joinedRestoreLogs,
          isNot(contains('SuperSecretRecoveryPassword-2026!')),
        );

        // 2c. ResumableDriveUploader hata ve JSON decode uyarılarında token sızdırmaz
        final driveLogs = <String>[];
        const secretAccessToken = 'ya29.super_secret_uploader_tok_99';
        final uploader = ResumableDriveUploader(
          accessTokenProvider: ({bool forceRefresh = false}) async =>
              secretAccessToken,
          httpClient: MockClient((req) async {
            return http.Response('{not-valid-json', 502);
          }),
          log: driveLogs.add,
        );

        await expectLater(
          uploader.listHubBackups(),
          throwsA(
            isA<DriveResumableUploadException>().having(
              (e) => e.message,
              'message',
              isNot(contains(secretAccessToken)),
            ),
          ),
        );
        expect(driveLogs.join('\n'), isNot(contains(secretAccessToken)));
      },
    );

    test(
      '3. Backend ve client storage kritik yedekleme/restore/API dosyalarında boş sessiz catch (_) {} blokları ve tam yol karantina logları kalmamalıdır',
      () {
        var dir = Directory.current;
        while (!File(p.join(dir.path, 'AGENTS.md')).existsSync()) {
          final parent = dir.parent;
          if (parent.path == dir.path) {
            fail('Depo kökü (AGENTS.md) bulunamadı');
          }
          dir = parent;
        }
        final repoRoot = dir.path;

        final targets = <File>[
          File(p.join(repoRoot, 'test_spikes', 'spike_01_backend', 'bin', 'server.dart')),
          File(p.join(repoRoot, 'test_spikes', 'spike_01_backend', 'lib', 'backup', 'hub_restore_service.dart')),
          File(p.join(repoRoot, 'test_spikes', 'spike_01_backend', 'lib', 'backup', 'hub_backup_state_store.dart')),
          File(p.join(repoRoot, 'packages', 'mms_client_storage', 'lib', 'src', 'backup', 'resumable_drive_uploader.dart')),
        ];

        final silentCatchRegex = RegExp(
          r'catch\s*\([^)]*\)\s*\{\s*(?://[^\r\n]*\s*)*\}',
        );
        final findings = <String>[];
        for (final file in targets) {
          final src = file.readAsStringSync();
          for (final m in silentCatchRegex.allMatches(src)) {
            final line = src.substring(0, m.start).split('\n').length;
            findings.add('${p.basename(file.path)}:$line: ${m.group(0)}');
          }
        }
        expect(
          findings,
          isEmpty,
          reason: 'Sessiz exception yutan catch blokları bulundu: $findings',
        );

        final stateStoreSrc = targets[2].readAsStringSync();
        expect(stateStoreSrc, contains('p.basename(quarantine)'));
      },
    );

    test(
      '4. Zamanlanmış yedekleme hatası ve genel loglarda tam yerel dizin yolu veya gizli parametreler sızdırılmaz',
      () async {
        configureSqliteNative();
        final secretTemp = Directory.systemTemp.createTempSync(
          'mms_test_only_sched_path_leak_',
        );
        addTearDown(() {
          if (secretTemp.existsSync()) {
            try {
              secretTemp.deleteSync(recursive: true);
            } catch (_) {}
          }
        });

        final dbFile = File(p.join(secretTemp.path, 'market_master.db'));
        final db = SpikeDatabase(dbFile);
        final pepper = PepperManager(File(p.join(secretTemp.path, 'pepper.dpapi')))
          ..initialize();
        final keyStore = HubRecoveryKeyStore(
          File(p.join(secretTemp.path, HubRecoveryKeyStore.defaultFileName)),
        );
        await keyStore.saveRecoveryPassword('AuditSecretPass-2026!');

        // Dosya ile yedek klasörünü bloklayıp zamanlanmış yedek hatası üret
        final blockedTarget = File(p.join(secretTemp.path, 'blocked_backup_dir'))
          ..writeAsStringSync('not_a_dir');

        final server = SpikeServer(
          db: db,
          dbFile: dbFile,
          writeQueue: WriteQueue(),
          backupDirectory: blockedTarget.path,
          adminSecret: 'adm_sched_redaction_2026',
          pepperManager: pepper,
          hubRecoveryKeyStore: keyStore,
          backupSchedule: const BackupSchedulePolicy(interval: Duration(hours: 24)),
          backupCheckInterval: const Duration(milliseconds: 50),
        );

        final printedLines = <String>[];
        await runZoned(
          () async {
            await server.start(
              address: InternetAddress.loopbackIPv4,
              port: 0,
              enableDiscovery: false,
            );
            final deadline = DateTime.now().add(const Duration(seconds: 10));
            while (server.backupScheduleState?.lastErrorCode == null) {
              if (DateTime.now().isAfter(deadline)) {
                fail('Zamanlanmış yedek hatası zamanında kaydedilmedi.');
              }
              await Future<void>.delayed(const Duration(milliseconds: 50));
            }
            await Future<void>.delayed(const Duration(milliseconds: 80));
            await server.stop();
          },
          zoneSpecification: ZoneSpecification(
            print: (_, __, ___, line) => printedLines.add(line),
          ),
        );

        final combined = printedLines.join('\n');
        expect(combined, contains('[BACKUP] Zamanlanmış Hub yedeği: BAŞARISIZ'));
        expect(combined, isNot(contains(secretTemp.path)));
        expect(combined, isNot(contains('mms_test_only_sched_path_leak_')));
        expect(combined, contains('blocked_backup_dir'));
      },
    );

    test(
      '5. Hub zamanlayıcı ve BackupEngine kurtarma loglarında SpikeServer.redactLogText ile uyumlu biçimde tam yol/sır maskelenir',
      () async {
        final sink = _CapturedStderr();
        final stateFile = File(p.join(tempDir.path, 'hub_sched_state.json'));
        final secretErrText =
            'Authorization: Bearer HubJwt1 ya29.HubTok99 recovery_password=HubRecPass! '
            'https://hub.local/cb?code=4/0AXHubCode&upload_id=HubUpId&state=ok '
            '${tempDir.path}\\market_master.db '
            'file:///C:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/backup/scheduled_backup.dart:445:7';

        await IOOverrides.runZoned(() async {
          final sched = BackupScheduler(
            runner: ScheduledBackupRunner(
              readPolicy: () => const BackupSchedulePolicy(interval: Duration(hours: 12)),
              stateStore: _ThrowingHubScheduleStore(stateFile, Exception(secretErrText)),
              createBackup: () async => throw UnimplementedError(),
            ),
            checkInterval: const Duration(hours: 1),
          );
          sched.start(runImmediately: true);
          await Future<void>.delayed(const Duration(milliseconds: 30));
          await sched.stop();
        }, stderr: () => sink);

        final combined = sink.lines.join('\n');
        expect(combined, contains('[BackupScheduler] Zamanlanmış yedek kontrolü başarısız:'));
        expect(combined, isNot(contains(tempDir.path)));
        expect(combined, isNot(contains('HubJwt1')));
        expect(combined, isNot(contains('ya29.HubTok99')));
        expect(combined, isNot(contains('HubRecPass!')));
        expect(combined, isNot(contains('4/0AXHubCode')));
        expect(combined, isNot(contains('HubUpId')));
        expect(combined, isNot(contains('C:/Users/halil')));
        expect(combined, contains('market_master.db'));
        expect(combined, contains('&state=ok'));
      },
    );
  });
}
