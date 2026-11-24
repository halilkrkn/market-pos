@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:http/http.dart' as http;
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/backup/hub_recovery_key_store.dart';
import '../lib/config/hub_config.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/pepper_manager.dart';

/// Faz 3 / 7C — Windows Hub zamanlanmış şifreli yedekleme (TDD).
///
/// Gerçek FFI SQLite + gerçek şifreli yedek motoru + gerçek HTTP sunucusu.
void main() {
  late Directory tempDir;
  late SpikeDatabase db;
  late SpikeServer server;
  late PepperManager pepper;
  const adminSecret = 'hub_sched_admin_secret_2026';
  // ADR-023 B1.7: Hub S5A-4 yedekleri makineye bağlı pepper ile DEĞİL, taşınabilir
  // Portable Recovery Password ile şifrelenir.
  const recoveryPassword = 'Hub-Zamanlanmis-Kurtarma-2026!';
  var port = 9310;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    configureSqliteNative();
  });

  Future<void> startServer({
    required String backupDir,
    BackupSchedulePolicy? policy,
    Duration checkInterval = const Duration(milliseconds: 100),
    String storeId = SpikeServer.defaultStoreId,
  }) async {
    final dbFile = File(p.join(tempDir.path, 'market_master.db'));
    db = SpikeDatabase(dbFile);
    pepper = PepperManager(File(p.join(tempDir.path, 'pepper.dpapi')))..initialize();
    final recoveryKeyStore = HubRecoveryKeyStore(
      File(p.join(tempDir.path, HubRecoveryKeyStore.defaultFileName)),
    );
    await recoveryKeyStore.saveRecoveryPassword(recoveryPassword);
    await db.into(db.products).insert(ProductsCompanion(
          id: const Value('prod_1'),
          barcode: const Value('8690000000011'),
          name: const Value('Ürün'),
          price: const Value(1000),
          stock: const Value(5000),
        ));
    server = SpikeServer(
      db: db,
      dbFile: dbFile,
      writeQueue: WriteQueue(),
      backupDirectory: backupDir,
      adminSecret: adminSecret,
      pepperManager: pepper,
      hubRecoveryKeyStore: recoveryKeyStore,
      storeId: storeId,
      backupSchedule: policy,
      backupCheckInterval: checkInterval,
    );
    port++;
    await server.start(address: InternetAddress.loopbackIPv4, port: port, enableDiscovery: false);
  }

  Future<void> waitFor(bool Function() condition, {Duration timeout = const Duration(seconds: 60)}) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) fail('Koşul $timeout içinde sağlanmadı.');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mms_hub_sched_');
  });

  tearDown(() async {
    try {
      await server.stop();
    } catch (_) {
      // Bazı testler sunucuyu kendisi durdurur.
    }
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {
        // Windows dosya kilidi; geçici dizin.
      }
    }
  });

  group('HubConfig backup_schedule (REL-01 tek kaynak)', () {
    test('1. Varsayılan: 24 saatte bir, 30 gün günlük / 12 ay aylık saklama', () {
      final cfg = HubConfig.fromJson({'environment': 'development'}, baseDir: tempDir.path);
      expect(cfg.backupSchedule.interval, const Duration(hours: 24));
      expect(cfg.backupSchedule.retention.dailyRetentionDays, 30);
      expect(cfg.backupSchedule.retention.monthlyRetentionMonths, 12);
    });

    test('2. Yapılandırılabilir sıklık; 0 zamanlamayı kapatır; geçersiz değer reddedilir', () {
      final cfg = HubConfig.fromJson({
        'environment': 'development',
        'backup_schedule': {'interval_hours': 6, 'daily_retention_days': 14, 'monthly_retention_months': 6},
      }, baseDir: tempDir.path);
      expect(cfg.backupSchedule.interval, const Duration(hours: 6));
      expect(cfg.backupSchedule.retention.dailyRetentionDays, 14);

      final off = HubConfig.fromJson({
        'environment': 'development',
        'backup_schedule': {'interval_hours': 0},
      }, baseDir: tempDir.path);
      expect(off.backupSchedule.enabled, isFalse);

      expect(
        () => HubConfig.fromJson({
          'environment': 'development',
          'backup_schedule': {'interval_hours': -1},
        }, baseDir: tempDir.path),
        throwsA(isA<HubConfigException>()),
      );
      expect(
        () => HubConfig.fromJson({
          'environment': 'development',
          'backup_schedule': {'interval_hourz': 6},
        }, baseDir: tempDir.path),
        throwsA(isA<HubConfigException>()),
      );
    });
  });

  group('Hub zamanlanmış yedekleme', () {
    test('3. Zamanı gelen şifreli yedek otomatik alınır, durum kalıcı yazılır, ikinci kontrolde tekrar alınmaz', () async {
      final backupDir = p.join(tempDir.path, 'backups');
      await startServer(backupDir: backupDir, policy: const BackupSchedulePolicy(interval: Duration(hours: 24)));

      await waitFor(() => server.backupScheduleState?.lastSuccessAt != null);
      final stateFile = server.backupScheduleStateFile;
      await Future<void>.delayed(const Duration(milliseconds: 600)); // birkaç kontrol turu daha

      final backups = await LocalStorageProvider(Directory(backupDir)).listBackups();
      expect(backups, hasLength(1), reason: 'Aralık dolmadan ikinci yedek alınmamalı');
      expect(backups.single.databaseType, DatabaseType.centralMaster);
      expect(backups.single.manifest.storeId, SpikeServer.defaultStoreId);

      final state = await BackupScheduleStateStore(stateFile).load();
      expect(state.lastSuccessAt, isNotNull);
      expect(state.history.single.success, isTrue);
      expect(state.history.single.backupId, backups.single.backupId);

      // Şifreli paket taşınabilir kurtarma parolasıyla çözülür; makineye bağlı
      // pepper ile AÇILAMAZ (yeni PC'de kurtarılabilirlik — ADR-023 B1.7).
      final bytes = await backups.single.file.readAsBytes();
      final decrypted =
          BackupCryptoService.verifyAndDecryptPackage(packageBytes: bytes, password: recoveryPassword);
      expect(decrypted.databaseBytes, isNotEmpty);
      expect(
        () => BackupCryptoService.verifyAndDecryptPackage(packageBytes: bytes, password: pepper.pepper),
        throwsA(isA<BackupCryptoException>()),
      );
    });

    test('4. Yedek hedefi yazılamazsa hata kaydedilir, servis çalışmaya devam eder ve /health gecikmeyi raporlar', () async {
      final blocker = File(p.join(tempDir.path, 'not_a_dir'))..writeAsStringSync('x');
      await startServer(
        backupDir: p.join(blocker.path, 'backups'),
        policy: const BackupSchedulePolicy(interval: Duration(hours: 24)),
      );

      await waitFor(() => server.backupScheduleState?.consecutiveFailures == 1);
      final health = await http.get(Uri.parse('http://127.0.0.1:$port/health'));
      expect(health.statusCode, 200, reason: 'Yedek hatası servisi durdurmamalı');
      final body = jsonDecode(health.body) as Map<String, dynamic>;
      final backup = body['backup'] as Map<String, dynamic>;
      expect(backup['schedule_enabled'], isTrue);
      expect(backup['overdue'], isTrue);
      expect(backup['consecutive_failures'], 1);
      expect(body.toString(), isNot(contains(blocker.path)), reason: '/health dosya yolu sızdırmamalı');
    });

    test('5. Durum ucu yalnızca loopback + admin secret ile erişilir ve geçmişi döner', () async {
      final backupDir = p.join(tempDir.path, 'backups');
      await startServer(backupDir: backupDir, policy: const BackupSchedulePolicy(interval: Duration(hours: 24)));
      await waitFor(() => server.backupScheduleState?.lastSuccessAt != null);

      final noSecret = await http.get(Uri.parse('http://127.0.0.1:$port/api/v1/admin/backup/status'));
      expect(noSecret.statusCode, 401);

      final ok = await http.get(
        Uri.parse('http://127.0.0.1:$port/api/v1/admin/backup/status'),
        headers: {'x-mms-admin-secret': adminSecret},
      );
      expect(ok.statusCode, 200);
      final json = jsonDecode(ok.body) as Map<String, dynamic>;
      expect(json['policy']['interval_minutes'], 24 * 60);
      expect((json['state']['history'] as List), hasLength(1));
      expect(json['next_due_at'], isNotNull);
    });

    test('6. Saklama politikası zamanlanmış yedekten sonra süresi dolan yedekleri temizler', () async {
      final backupDir = p.join(tempDir.path, 'backups');
      // Önce 40 gün önceki tarihli eski bir yedek üret (sunucu kapalıyken).
      final seedFile = File(p.join(tempDir.path, 'seed.db'));
      final seedDb = SpikeDatabase(seedFile);
      await seedDb.customSelect('SELECT 1').get();
      final old = await DatabaseBackupEngine.createBackup(
        liveDbFile: seedFile,
        executeVacuumInto: (snap) async => seedDb.customStatement("VACUUM INTO '${snap.replaceAll("'", "''")}';"),
        deviceId: 'SERVER_HUB',
        tenantId: SpikeServer.defaultTenantId,
        storeId: SpikeServer.defaultStoreId,
        databaseType: DatabaseType.centralMaster,
        schemaVersion: seedDb.schemaVersion,
        appVersion: 'seed',
        backupPassword: 'seed_password_123',
        storageProvider: LocalStorageProvider(Directory(backupDir)),
        kdfIterations: 1000,
        timestamp: DateTime.now().toUtc().subtract(const Duration(days: 400)), // 12 aylık arşiv süresinin de dışında
      );
      await seedDb.close();

      await startServer(backupDir: backupDir, policy: const BackupSchedulePolicy(interval: Duration(hours: 24)));
      await waitFor(() => server.backupScheduleState?.lastSuccessAt != null);

      final remaining = await LocalStorageProvider(Directory(backupDir)).listBackups();
      expect(remaining.map((b) => b.backupId), isNot(contains(old.backupId)));
      expect(remaining, hasLength(1));
      expect(server.backupScheduleState!.history.first.prunedCount, 1);
    });

    test('7. Zamanlama kapalıysa otomatik yedek alınmaz', () async {
      final backupDir = p.join(tempDir.path, 'backups');
      await startServer(backupDir: backupDir, policy: BackupSchedulePolicy.disabled);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(await LocalStorageProvider(Directory(backupDir)).listBackups(), isEmpty);
    });

    test('8. Farklı şubenin yedeği Hub restore ucunda ERR_STORE_ID_MISMATCH ile reddedilir', () async {
      final backupDir = p.join(tempDir.path, 'backups');
      await startServer(backupDir: backupDir, policy: BackupSchedulePolicy.disabled, storeId: 'store-A');
      final other = await DatabaseBackupEngine.createBackup(
        liveDbFile: File(p.join(tempDir.path, 'market_master.db')),
        executeVacuumInto: (snap) async => db.customStatement("VACUUM INTO '${snap.replaceAll("'", "''")}';"),
        deviceId: 'SERVER_HUB',
        tenantId: SpikeServer.defaultTenantId,
        storeId: 'store-B',
        databaseType: DatabaseType.centralMaster,
        schemaVersion: db.schemaVersion,
        appVersion: 'test',
        backupPassword: recoveryPassword,
        storageProvider: LocalStorageProvider(Directory(backupDir)),
        kdfIterations: 1000,
      );

      final resp = await http.post(
        Uri.parse('http://127.0.0.1:$port/api/v1/admin/restore'),
        headers: {'x-mms-admin-secret': adminSecret, 'content-type': 'application/json'},
        body: jsonEncode({'backup_id': other.backupId}),
      );
      expect(resp.statusCode, 400);
      expect((jsonDecode(resp.body) as Map)['code'], 'ERR_STORE_ID_MISMATCH');
    });

    test('9. Hub admin/backup ve admin/restore ortak BackupOperationLock ile çakışmayı 409 ERR_BACKUP_OPERATION_BUSY olarak engeller', () async {
      final backupDir = p.join(tempDir.path, 'backups');
      await startServer(backupDir: backupDir, policy: BackupSchedulePolicy.disabled);
      final foreign = await BackupOperationLock(server.backupOperationLockFile)
          .acquire(BackupOperationKind.restore);
      try {
        final backupResp = await http.post(
          Uri.parse('http://127.0.0.1:$port/api/v1/admin/backup'),
          headers: {'x-mms-admin-secret': adminSecret, 'content-type': 'application/json'},
          body: jsonEncode({}),
        );
        expect(backupResp.statusCode, 409);
        expect((jsonDecode(backupResp.body) as Map)['code'], BackupOperationLock.busyErrorCode);

        final restoreResp = await http.post(
          Uri.parse('http://127.0.0.1:$port/api/v1/admin/restore'),
          headers: {'x-mms-admin-secret': adminSecret, 'content-type': 'application/json'},
          body: jsonEncode({'backup_id': 'any_id'}),
        );
        expect(restoreResp.statusCode, 409);
        expect((jsonDecode(restoreResp.body) as Map)['code'], BackupOperationLock.busyErrorCode);

        final pruneResp = await http.post(
          Uri.parse('http://127.0.0.1:$port/api/v1/admin/backup/prune'),
          headers: {'x-mms-admin-secret': adminSecret},
        );
        expect(pruneResp.statusCode, 409);
        expect((jsonDecode(pruneResp.body) as Map)['code'], BackupOperationLock.busyErrorCode);
      } finally {
        await foreign.release();
      }
    });

    test('10. Hub admin/restore bozuk JSON gövdesinde 500 yerine 400 BAD_REQUEST döner', () async {
      await startServer(
        backupDir: p.join(tempDir.path, 'backups'),
        policy: BackupSchedulePolicy.disabled,
      );
      final resp = await http.post(
        Uri.parse('http://127.0.0.1:$port/api/v1/admin/restore'),
        headers: {'x-mms-admin-secret': adminSecret, 'content-type': 'application/json'},
        body: '{bozuk_json',
      );
      expect(resp.statusCode, 400);
      expect((jsonDecode(resp.body) as Map)['code'], 'ERR_INVALID_JSON');
    });
  });
}
