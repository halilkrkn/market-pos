@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:http/http.dart' as http;
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/backup/hub_recovery_key_store.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/dpapi.dart';
import '../lib/security/pepper_manager.dart';

/// B-4 (ADR-023 B1.7 / OV-05): Eski S5A-4 manuel Hub yedek/restore uçları ve
/// eski aralıklı zamanlayıcı, parola verilmediğinde makineye bağlı
/// `pepper.dpapi` yerine taşınabilir Portable Recovery Password kullanır.
///
/// Gerçek FFI SQLite + gerçek şifreli yedek motoru + gerçek HTTP sunucusu +
/// gerçek LocalMachine DPAPI (yalnızca geçici test dizinlerinde).
void main() {
  late Directory tempDir;
  late SpikeDatabase db;
  late SpikeServer server;
  late PepperManager pepper;
  late HubRecoveryKeyStore recoveryKeyStore;
  const adminSecret = 'legacy_portable_admin_secret_2026';
  const recoveryPassword = 'Tasinabilir-Kurtarma-2026!';
  var port = 9460;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    configureSqliteNative();
  });

  Future<void> startServer({
    bool withRecoveryKey = true,
    BackupSchedulePolicy? policy,
  }) async {
    final dbFile = File(p.join(tempDir.path, 'market_master.db'));
    db = SpikeDatabase(dbFile);
    pepper = PepperManager(File(p.join(tempDir.path, 'pepper.dpapi')))..initialize();
    recoveryKeyStore = HubRecoveryKeyStore(
      File(p.join(tempDir.path, HubRecoveryKeyStore.defaultFileName)),
    );
    if (withRecoveryKey) {
      await recoveryKeyStore.saveRecoveryPassword(recoveryPassword);
    }
    await db.into(db.products).insert(ProductsCompanion(
          id: const Value('prod_portable_1'),
          barcode: const Value('8690000077001'),
          name: const Value('Taşınabilir Yedek Ürünü'),
          price: const Value(1250),
          stock: const Value(3000),
        ));
    server = SpikeServer(
      db: db,
      dbFile: dbFile,
      writeQueue: WriteQueue(),
      backupDirectory: p.join(tempDir.path, 'backups'),
      adminSecret: adminSecret,
      pepperManager: pepper,
      hubRecoveryKeyStore: recoveryKeyStore,
      backupSchedule: policy ?? BackupSchedulePolicy.disabled,
      backupCheckInterval: const Duration(milliseconds: 100),
    );
    port++;
    await server.start(address: InternetAddress.loopbackIPv4, port: port, enableDiscovery: false);
  }

  Future<http.Response> post(String path, Map<String, dynamic> body) => http.post(
        Uri.parse('http://127.0.0.1:$port$path'),
        headers: {'x-mms-admin-secret': adminSecret, 'content-type': 'application/json'},
        body: jsonEncode(body),
      );

  Future<void> waitFor(bool Function() condition,
      {Duration timeout = const Duration(seconds: 60)}) async {
    final deadline = DateTime.now().add(timeout);
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) fail('Koşul $timeout içinde sağlanmadı.');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mms_legacy_portable_');
  });

  tearDown(() async {
    try {
      await server.stop();
    } catch (_) {}
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {
        // Windows dosya kilidi; geçici dizin.
      }
    }
  });

  test('LP-01 Parolasız /admin/backup Portable Recovery Password ile şifrelenir; pepper ile AÇILAMAZ', () async {
    await startServer();
    final resp = await post('/api/v1/admin/backup', {});
    expect(resp.statusCode, 200, reason: resp.body);
    final backupId = (jsonDecode(resp.body) as Map)['backup_id'] as String;

    final file = await LocalStorageProvider(Directory(p.join(tempDir.path, 'backups')))
        .getBackupFile(backupId);
    final bytes = await file.readAsBytes();

    final decrypted = BackupCryptoService.verifyAndDecryptPackage(
      packageBytes: bytes,
      password: recoveryPassword,
    );
    expect(decrypted.databaseBytes, isNotEmpty);
    expect(
      () => BackupCryptoService.verifyAndDecryptPackage(packageBytes: bytes, password: pepper.pepper),
      throwsA(isA<BackupCryptoException>()),
      reason: 'Makineye bağlı pepper artık yedek anahtarı olmamalıdır (ADR-023 B1.7).',
    );
  });

  test('LP-02 Kurtarma anahtarı yoksa parolasız /admin/backup fail-closed 412 döner ve dosya üretmez', () async {
    await startServer(withRecoveryKey: false);
    final resp = await post('/api/v1/admin/backup', {});
    expect(resp.statusCode, 412, reason: resp.body);
    expect((jsonDecode(resp.body) as Map)['code'], 'ERR_RECOVERY_KEY_NOT_CONFIGURED');
    final backups =
        await LocalStorageProvider(Directory(p.join(tempDir.path, 'backups'))).listBackups();
    expect(backups, isEmpty);
  });

  test('LP-03 Eski istemcinin backup_password / recovery_password göndermesi 400 ERR_BACKUP_PASSWORD_NOT_ACCEPTED ile reddedilir (S2)', () async {
    await startServer();
    final resp = await post('/api/v1/admin/backup', {'backup_password': 'kisa-parola'});
    expect(resp.statusCode, 400, reason: resp.body);
    expect((jsonDecode(resp.body) as Map)['code'], 'ERR_BACKUP_PASSWORD_NOT_ACCEPTED');
    final backups =
        await LocalStorageProvider(Directory(p.join(tempDir.path, 'backups'))).listBackups();
    expect(backups, isEmpty, reason: 'Reddedilen istek yedek dosyası oluşturmamalı.');

    final respRec = await post('/api/v1/admin/backup', {'recovery_password': 'UzunGecerliParola-2026!'});
    expect(respRec.statusCode, 400, reason: respRec.body);
    expect((jsonDecode(respRec.body) as Map)['code'], 'ERR_BACKUP_PASSWORD_NOT_ACCEPTED');
  });

  test('LP-08 Eski /admin/backup güvenlik matrisi: yetkisiz istek, uzak istemci, zayıf/kayıtlı parola, loopback erişimi', () async {
    await startServer(withRecoveryKey: true);

    // 1. Admin secret olmadan -> 401
    final noAuth = await http.post(
      Uri.parse('http://127.0.0.1:$port/api/v1/admin/backup'),
      headers: {'content-type': 'application/json'},
      body: '{}',
    );
    expect(noAuth.statusCode, 401);

    // 2. Yanlış admin secret -> 403
    final badAuth = await http.post(
      Uri.parse('http://127.0.0.1:$port/api/v1/admin/backup'),
      headers: {
        'x-mms-admin-secret': 'yanlis_admin_secret',
        'content-type': 'application/json',
      },
      body: '{}',
    );
    expect(badAuth.statusCode, 403);

    // 3. Uzak istemciden erişim (Request context remote address simülasyonu / router doğrudan çağrı) -> 403 ERR_LOOPBACK_REQUIRED
    final remoteReq = Request(
      'POST',
      Uri.parse('http://192.168.1.10:$port/api/v1/admin/backup'),
      headers: {
        'x-mms-admin-secret': adminSecret,
        'content-type': 'application/json',
      },
      body: '{}',
      context: {
        'shelf.io.connection_info': _FakeHttpConnectionInfo(InternetAddress('192.168.1.50')),
      },
    );
    final remoteResp = await server.handler(remoteReq);
    expect(remoteResp.statusCode, 403);
    expect((jsonDecode(await remoteResp.readAsString()) as Map)['code'], 'ERR_LOOPBACK_REQUIRED');

    // 4. Loopback + geçerli admin secret + kayıtlı Recovery Password -> 200 & HUB_STORED_DPAPI
    final ok = await post('/api/v1/admin/backup', {});
    expect(ok.statusCode, 200, reason: ok.body);
    final okBody = jsonDecode(ok.body) as Map<String, dynamic>;
    expect(okBody['recovery_key_source'], equals('HUB_STORED_DPAPI'));

    // 5. Zayıf (< 12 karakter) kayıtlı parola dosyada bozulmuşsa fail-closed 412 döner
    await recoveryKeyStore.file.writeAsBytes(
      WindowsDpapi.protect(
        utf8.encode('zayif'),
        entropy: HubRecoveryKeyStore.recoveryKeyEntropy,
      ),
      flush: true,
    );
    final weakStored = await post('/api/v1/admin/backup', {});
    expect(weakStored.statusCode, 412, reason: weakStored.body);
    expect((jsonDecode(weakStored.body) as Map)['code'], 'ERR_CORRUPT_RECOVERY_KEY');
  });

  test('LP-04 Parolasız /admin/restore Portable Recovery Password ile geri yükler', () async {
    await startServer();
    final backupResp = await post('/api/v1/admin/backup', {});
    expect(backupResp.statusCode, 200, reason: backupResp.body);
    final backupId = (jsonDecode(backupResp.body) as Map)['backup_id'] as String;

    final restoreResp = await post('/api/v1/admin/restore', {'backup_id': backupId});
    expect(restoreResp.statusCode, 200, reason: restoreResp.body);
    final json = jsonDecode(restoreResp.body) as Map<String, dynamic>;
    expect(json['status'], 'RESTORED');
    expect(json['safety_backup_encrypted'], isTrue);

    final restored = await (server.db.select(server.db.products)
          ..where((t) => t.id.equals('prod_portable_1')))
        .getSingleOrNull();
    expect(restored, isNotNull);
  });

  test('LP-05 Eski pepper şifreli yedek varsayılan olarak AÇILMAZ; yalnızca açık legacy_machine_key onayıyla aynı makinede açılır', () async {
    await startServer();
    final legacy = await DatabaseBackupEngine.createBackup(
      liveDbFile: File(p.join(tempDir.path, 'market_master.db')),
      executeVacuumInto: (snap) async =>
          db.customStatement("VACUUM INTO '${snap.replaceAll("'", "''")}';"),
      deviceId: 'SERVER_HUB',
      tenantId: SpikeServer.defaultTenantId,
      storeId: SpikeServer.defaultStoreId,
      databaseType: DatabaseType.centralMaster,
      schemaVersion: db.schemaVersion,
      appVersion: 'legacy-pepper',
      backupPassword: pepper.pepper,
      storageProvider: LocalStorageProvider(Directory(p.join(tempDir.path, 'backups'))),
      kdfIterations: 1000,
    );

    final denied = await post('/api/v1/admin/restore', {'backup_id': legacy.backupId});
    expect(denied.statusCode, 400, reason: denied.body);
    expect((jsonDecode(denied.body) as Map)['code'], isNot('RESTORED'));

    final allowed = await post('/api/v1/admin/restore', {
      'backup_id': legacy.backupId,
      'legacy_machine_key': true,
    });
    expect(allowed.statusCode, 200, reason: allowed.body);
    final allowedBody = jsonDecode(allowed.body) as Map;
    expect(allowedBody['status'], 'RESTORED');

    // S4: legacy_machine_key restore'unda restore ÖNCESİ güvenlik kopyası da aynı
    // makineye bağlı pepper ile şifrelenir → yalnızca bu Hub bilgisayarında açılır;
    // Portable Recovery Password ile AÇILMAZ (yeni bilgisayara taşınamaz).
    expect(allowedBody['safety_backup_encrypted'], isTrue);
    final safetyFile = File(allowedBody['safety_backup_path'] as String);
    expect(await safetyFile.exists(), isTrue);
    final opened = await MmsbakV2Crypto.decryptFile(
      inputFile: safetyFile,
      outputFile: File(p.join(tempDir.path, 'safety_open_pepper.db')),
      password: pepper.pepper,
    );
    expect(opened.databaseType, DatabaseType.centralMaster);
    await expectLater(
      MmsbakV2Crypto.decryptFile(
        inputFile: safetyFile,
        outputFile: File(p.join(tempDir.path, 'safety_open_portable.db')),
        password: recoveryPassword,
      ),
      throwsA(isA<BackupCryptoException>()),
    );
  });

  test('LP-06 Eski aralıklı zamanlayıcı kurtarma anahtarı yokken pepper ile yedek ALMAZ; hatayı kaydeder', () async {
    await startServer(
      withRecoveryKey: false,
      policy: const BackupSchedulePolicy(interval: Duration(hours: 24)),
    );
    await waitFor(() => (server.backupScheduleState?.consecutiveFailures ?? 0) >= 1);
    final backups =
        await LocalStorageProvider(Directory(p.join(tempDir.path, 'backups'))).listBackups();
    expect(backups, isEmpty);
    expect(server.backupScheduleState!.lastSuccessAt, isNull);
  });

  test('LP-07 Eski aralıklı zamanlayıcı kurtarma anahtarı varken taşınabilir parola ile yedek alır', () async {
    await startServer(policy: const BackupSchedulePolicy(interval: Duration(hours: 24)));
    await waitFor(() => server.backupScheduleState?.lastSuccessAt != null);
    final backups =
        await LocalStorageProvider(Directory(p.join(tempDir.path, 'backups'))).listBackups();
    expect(backups, hasLength(1));
    final bytes = await backups.single.file.readAsBytes();
    expect(
      BackupCryptoService.verifyAndDecryptPackage(packageBytes: bytes, password: recoveryPassword)
          .databaseBytes,
      isNotEmpty,
    );
  });
}

class _FakeHttpConnectionInfo implements HttpConnectionInfo {
  @override
  final InternetAddress remoteAddress;

  @override
  final int localPort = 8945;

  @override
  final int remotePort = 54321;

  _FakeHttpConnectionInfo(this.remoteAddress);
}
