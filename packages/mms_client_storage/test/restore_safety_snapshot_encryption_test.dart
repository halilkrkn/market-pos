import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:test/test.dart';

class _CapturingStderr implements Stdout {
  final List<String> lines = <String>[];
  final StringBuffer _buffer = StringBuffer();

  @override
  void write(Object? object) => _buffer.write(object ?? '');

  @override
  void writeln([Object? object = '']) {
    _buffer.write(object ?? '');
    lines.add(_buffer.toString());
    _buffer.clear();
  }

  @override
  void writeAll(Iterable objects, [String separator = '']) =>
      _buffer.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _buffer.writeCharCode(charCode);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// SEC-SAFETY — Restore öncesi alınan güvenlik kopyası (safety snapshot) diskte
/// şifresiz kalmamalıdır.
///
/// Güvenlik kopyası yalnızca restore SÜRESİNCE geri alma (rollback / journal
/// kurtarma) için şifresiz gereklidir. Restore başarıyla tamamlandığında, geri
/// yüklenen yedeğin parolası ve KDF gücüyle şifreli `.mmsbak` paketine dönüştürülür
/// ve şifresiz kopya silinir. Şifreleme başarısız olursa restore BAŞARISIZ SAYILMAZ;
/// şifresiz kopya korunur ve sonuçta işaretlenir (veri kaybı yerine görünür risk).
void main() {
  late Directory tempDir;
  late File dbFile;
  late ClientDatabase db;
  late ClientStorageRepository repo;
  late Directory backupDir;
  late Directory safetyDir;
  late LocalStorageProvider storage;

  const password = 'Safety_Snapshot_Test_Password_2026!';
  const deviceId = 'DEV_SAFETY_01';
  const tenantId = 'tenant_safety';
  const storeId = 'store_safety';
  const kdf = 1000;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mms_safety_enc_');
    dbFile = File(p.join(tempDir.path, 'client_local.db'));
    backupDir = Directory(p.join(tempDir.path, 'backups'))..createSync();
    safetyDir = Directory(p.join(tempDir.path, 'backups', 'safety'));
    storage = LocalStorageProvider(backupDir);
    db = ClientDatabase(dbFile);
    repo = ClientStorageRepository(db);
    await repo.upsertProducts([
      LocalProductsCompanion(
        id: const Value('prod_1'),
        barcode: const Value('869000222'),
        name: const Value('Ekmek'),
        price: const Value(1500),
        stock: const Value(100000),
        updatedAt: Value(DateTime.now()),
      ),
    ]);
    await repo.initializeDevice(deviceId);
  });

  tearDown(() async {
    try {
      await db.close();
    } catch (_) {
      // Test kendi içinde kapatmış olabilir.
    }
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {
        // Windows dosya kilidi: geçici dizin işletim sistemi tarafından temizlenir.
      }
    }
  });

  Future<BackupResult> takeBackup() {
    return DatabaseBackupEngine.createBackup(
      liveDbFile: dbFile,
      executeVacuumInto: (snap) async {
        await db.customStatement("VACUUM INTO '${snap.replaceAll("'", "''")}';");
      },
      deviceId: deviceId,
      tenantId: tenantId,
      storeId: storeId,
      databaseType: DatabaseType.clientLocal,
      schemaVersion: db.schemaVersion,
      appVersion: 'test',
      backupPassword: password,
      storageProvider: storage,
      kdfIterations: kdf,
    );
  }

  Future<RestoreResult> restore(
    String backupId, {
    bool encryptSafetyBackup = true,
    Directory? safetyOverride,
  }) {
    return DatabaseBackupEngine.restoreBackup(
      backupId: backupId,
      liveDbFile: dbFile,
      backupPassword: password,
      storageProvider: storage,
      expectedDeviceId: deviceId,
      expectedTenantId: tenantId,
      expectedStoreId: storeId,
      expectedDatabaseType: DatabaseType.clientLocal,
      currentSchemaVersion: db.schemaVersion,
      pauseLiveDb: () async => db.close(),
      resumeLiveDb: () async {
        db = ClientDatabase(dbFile);
        repo = ClientStorageRepository(db);
      },
      safetyBackupDir: safetyOverride ?? safetyDir,
      encryptSafetyBackup: encryptSafetyBackup,
    );
  }

  Future<void> sell(int qty) => repo.createOfflineSale(
        deviceId: deviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_1', qty)],
      );

  List<File> filesIn(Directory dir, String suffix) => dir.existsSync()
      ? dir.listSync().whereType<File>().where((f) => f.path.endsWith(suffix)).toList()
      : <File>[];

  group('SEC-SAFETY: restore güvenlik kopyası şifreli saklanır', () {
    test('1. Başarılı restore sonrası şifresiz .db kalmaz; tek bir şifreli .mmsbak oluşur', () async {
      await sell(1);
      final backup = await takeBackup();
      await sell(2); // Restore öncesi canlı durum: 2 satış

      final result = await restore(backup.backupId);

      expect(filesIn(safetyDir, '.db'), isEmpty, reason: 'şifresiz güvenlik kopyası diskte kalmamalı');
      expect(filesIn(safetyDir, '.tmp'), isEmpty);
      final sealed = filesIn(safetyDir, '.mmsbak');
      expect(sealed, hasLength(1));
      expect(result.safetyBackupEncrypted, isTrue);
      expect(result.safetyBackupPath, sealed.single.path);

      // Dosyanın başında SQLite imzası olmamalı (gerçekten şifreli).
      final head = sealed.single.readAsBytesSync().sublist(0, 16);
      expect(String.fromCharCodes(head), isNot(startsWith('SQLite format 3')));
    });

    test('2. Şifreli güvenlik kopyası aynı cihaz/kiracı/şube kimliğini taşır ve aynı parolayla açılır', () async {
      await sell(1);
      final backup = await takeBackup();
      await sell(2);
      await sell(3); // canlı: 3 satış

      final result = await restore(backup.backupId);
      final bytes = File(result.safetyBackupPath).readAsBytesSync();

      final manifest = BackupCryptoService.extractManifestWithoutDecryption(bytes);
      expect(manifest.deviceId, deviceId);
      expect(manifest.tenantId, tenantId);
      expect(manifest.storeId, storeId);
      expect(manifest.databaseType, DatabaseType.clientLocal);
      expect(manifest.kdfIterations, kdf, reason: 'geri yüklenen yedeğin KDF gücü korunur');
      expect(manifest.backupId, isNot(backup.backupId));

      final decrypted = BackupCryptoService.verifyAndDecryptPackage(packageBytes: bytes, password: password);
      final probe = File(p.join(tempDir.path, 'probe.db'))..writeAsBytesSync(decrypted.databaseBytes);
      final raw = sql.sqlite3.open(probe.path);
      try {
        final count = raw.select('SELECT COUNT(*) AS c FROM local_sales').first['c'] as int;
        expect(count, 3, reason: 'güvenlik kopyası restore ÖNCESİ canlı durumu içerir');
      } finally {
        raw.close();
      }
    });

    test('3. Şifreli güvenlik kopyası standart restore akışıyla geri yüklenebilir (kurtarma prosedürü)', () async {
      await sell(1);
      final backup = await takeBackup();
      await sell(2);
      await sell(3);

      final first = await restore(backup.backupId);
      expect((await db.select(db.localSales).get()).length, 1);

      // Owner kurtarma prosedürü: güvenlik kopyası dizinini depolama olarak kullan.
      final safetyStorage = LocalStorageProvider(safetyDir);
      final safetyId = BackupCryptoService.extractManifestWithoutDecryption(
        File(first.safetyBackupPath).readAsBytesSync(),
      ).backupId;
      await DatabaseBackupEngine.restoreBackup(
        backupId: safetyId,
        liveDbFile: dbFile,
        backupPassword: password,
        storageProvider: safetyStorage,
        expectedDeviceId: deviceId,
        expectedTenantId: tenantId,
        expectedStoreId: storeId,
        expectedDatabaseType: DatabaseType.clientLocal,
        currentSchemaVersion: db.schemaVersion,
        pauseLiveDb: () async => db.close(),
        resumeLiveDb: () async {
          db = ClientDatabase(dbFile);
          repo = ClientStorageRepository(db);
        },
        safetyBackupDir: Directory(p.join(tempDir.path, 'safety2')),
      );
      expect((await db.select(db.localSales).get()).length, 3);
    });

    test('4. encryptSafetyBackup=false: eski davranış (şifresiz kopya) açıkça seçilebilir', () async {
      await sell(1);
      final backup = await takeBackup();

      final result = await restore(backup.backupId, encryptSafetyBackup: false);

      expect(result.safetyBackupEncrypted, isFalse);
      expect(result.safetyBackupPath, endsWith('.db'));
      expect(File(result.safetyBackupPath).existsSync(), isTrue);
      expect(filesIn(safetyDir, '.mmsbak'), isEmpty);
    });

    test('5. Şifreleme hedefi yazılamazsa restore yine başarılıdır; şifresiz kopya korunur ve işaretlenir', () async {
      await sell(1);
      final backup = await takeBackup();
      await sell(2);

      // Şifreli paket yazımı başarısız (ör. disk doldu) → mühürleme adımı hata verir.
      final blocked = Directory(p.join(tempDir.path, 'blocked_safety'))..createSync();
      final result = await DatabaseBackupEngine.restoreBackup(
        backupId: backup.backupId,
        liveDbFile: dbFile,
        backupPassword: password,
        storageProvider: storage,
        expectedDeviceId: deviceId,
        expectedTenantId: tenantId,
        expectedStoreId: storeId,
        expectedDatabaseType: DatabaseType.clientLocal,
        currentSchemaVersion: db.schemaVersion,
        pauseLiveDb: () async => db.close(),
        resumeLiveDb: () async {
          db = ClientDatabase(dbFile);
          repo = ClientStorageRepository(db);
        },
        safetyBackupDir: blocked,
        customSafetyBackupSealer: (_) async => throw const FileSystemException('simüle: disk dolu'),
      );

      expect((await db.select(db.localSales).get()).length, 1, reason: 'restore tamamlandı');
      expect(result.safetyBackupEncrypted, isFalse);
      expect(File(result.safetyBackupPath).existsSync(), isTrue, reason: 'şifresiz kopya silinmedi');
      expect(result.safetyBackupPath, endsWith('.db'));
      expect(filesIn(blocked, '.mmsbak'), isEmpty);
      expect(filesIn(blocked, '.tmp'), isEmpty);
    });

    test('6. Başarısız restore (bozuk parola) güvenlik dizinine dosya bırakmaz ve canlı DB değişmez', () async {
      await sell(1);
      final backup = await takeBackup();
      await sell(2);

      await expectLater(
        DatabaseBackupEngine.restoreBackup(
          backupId: backup.backupId,
          liveDbFile: dbFile,
          backupPassword: 'yanlis-parola-123',
          storageProvider: storage,
          expectedDeviceId: deviceId,
          expectedTenantId: tenantId,
          expectedStoreId: storeId,
          expectedDatabaseType: DatabaseType.clientLocal,
          currentSchemaVersion: db.schemaVersion,
          pauseLiveDb: () async => db.close(),
          resumeLiveDb: () async {
            db = ClientDatabase(dbFile);
            repo = ClientStorageRepository(db);
          },
          safetyBackupDir: safetyDir,
        ),
        throwsA(isA<BackupException>().having((e) => e.code, 'code', 'ERR_DECRYPTION_FAILED')),
      );
      expect(filesIn(safetyDir, '.db'), isEmpty);
      expect(filesIn(safetyDir, '.mmsbak'), isEmpty);
      expect((await db.select(db.localSales).get()).length, 2);
    });

    test('7. AUD-LOW-01: Rollback ikincil hatasında tam yerel yol ve sırlar maskelenir ve ilk hata rethrow edilir', () async {
      await sell(1);
      final backup = await takeBackup();
      await sell(2);

      final sink = _CapturingStderr();
      const injectedErr =
          'Rollback ikincil hata: Bearer JwtRb9 ya29.RbTok99 recovery_password=RbPass-2026! '
          'https://hub.local/cb?code=4/0AXRbCode&upload_id=RbUpId '
          'file:///C:/Users/halil/Github/market-pos/packages/mms_client_storage/lib/src/backup/database_backup_engine.dart:715:9';

      await IOOverrides.runZoned(() async {
        var resumeCalls = 0;
        await expectLater(
          DatabaseBackupEngine.restoreBackup(
            backupId: backup.backupId,
            liveDbFile: dbFile,
            backupPassword: password,
            storageProvider: storage,
            expectedDeviceId: deviceId,
            expectedTenantId: tenantId,
            expectedStoreId: storeId,
            expectedDatabaseType: DatabaseType.clientLocal,
            currentSchemaVersion: db.schemaVersion,
            pauseLiveDb: () async => db.close(),
            resumeLiveDb: () async {
              resumeCalls++;
              if (resumeCalls == 1) {
                throw StateError('Birincil resume hatası (rethrow edilmeli)');
              }
              throw FileSystemException(injectedErr, dbFile.path);
            },
            safetyBackupDir: safetyDir,
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'Birincil resume hatası (rethrow edilmeli)',
            ),
          ),
        );
      }, stderr: () => sink);

      final joined = sink.lines.join('\n');
      expect(
        joined,
        contains('[CRITICAL] Koruyucu yedekten geri alma sırasında ikincil hata:'),
      );
      for (final secret in [
        tempDir.path,
        'JwtRb9',
        'ya29.RbTok99',
        'RbPass-2026!',
        '4/0AXRbCode',
        'RbUpId',
        'C:/Users/halil',
      ]) {
        expect(joined, isNot(contains(secret)));
      }
      expect(joined, contains('client_local.db'));
      expect(joined, contains('database_backup_engine.dart:715:9'));

      // tearDown için DB'yi temiz aç
      db = ClientDatabase(dbFile);
      repo = ClientStorageRepository(db);
    });
  });
}
