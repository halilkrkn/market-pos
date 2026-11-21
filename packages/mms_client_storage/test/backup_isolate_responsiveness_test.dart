import 'dart:async';
import 'dart:io';

import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Faz 7A §8.1: PBKDF2 (600.000 iterasyon) ve AES işlemleri çağıran isolate'i
/// (Flutter UI isolate) bloklamamalıdır. Çağıran isolate'teki zamanlayıcı,
/// yedekleme/geri yükleme sürerken çalışmaya devam etmelidir.
void main() {
  late Directory tempDir;
  late File dbFile;
  late ClientDatabase db;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mms_backup_isolate_');
    dbFile = File(p.join(tempDir.path, 'client.db'));
    db = ClientDatabase(dbFile);
    final repo = ClientStorageRepository(db);
    await repo.initializeDevice('POS-ISO');
    await repo.createProduct(name: 'Su', price: 1000, barcode: '8690000000011');
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  /// İş sürerken çağıran isolate'in event loop'unun en uzun "donma" süresini (ms) ölçer.
  Future<int> maxStallMsDuring(Future<void> Function() work) async {
    final sw = Stopwatch()..start();
    var last = 0;
    var maxGap = 0;
    final timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      final now = sw.elapsedMilliseconds;
      if (now - last > maxGap) maxGap = now - last;
      last = now;
    });
    await work();
    final end = sw.elapsedMilliseconds;
    if (end - last > maxGap) maxGap = end - last;
    timer.cancel();
    return maxGap;
  }

  test('Yedekleme ve geri yükleme sırasında çağıran isolate yanıt vermeye devam eder', () async {
    final storage = LocalStorageProvider(Directory(p.join(tempDir.path, 'backups')));
    late BackupResult backup;

    final backupStall = await maxStallMsDuring(() async {
      backup = await DatabaseBackupEngine.createBackup(
        liveDbFile: dbFile,
        executeVacuumInto: (snapPath) async {
          await db.customStatement("VACUUM INTO '${snapPath.replaceAll("'", "''")}';");
        },
        deviceId: 'POS-ISO',
        tenantId: 'tenant-1',
        storeId: 'store-1',
        databaseType: DatabaseType.clientLocal,
        schemaVersion: db.schemaVersion,
        appVersion: '1.0.0',
        backupPassword: 'Guclu-Parola-2026',
        storageProvider: storage,
        kdfIterations: 600000,
      );
    });
    expect(backupStall, lessThan(750), reason: 'PBKDF2/AES UI isolate’ini bloklamamalı (en uzun donma: ${backupStall}ms)');

    final restoreStall = await maxStallMsDuring(() async {
      await DatabaseBackupEngine.restoreBackup(
        backupId: backup.backupId,
        liveDbFile: dbFile,
        backupPassword: 'Guclu-Parola-2026',
        storageProvider: storage,
        expectedDeviceId: 'POS-ISO',
        expectedTenantId: 'tenant-1',
        expectedDatabaseType: DatabaseType.clientLocal,
        currentSchemaVersion: db.schemaVersion,
        pauseLiveDb: () async => db.close(),
        resumeLiveDb: () async => db = ClientDatabase(dbFile),
        safetyBackupDir: Directory(p.join(tempDir.path, 'safety')),
      );
    });
    expect(restoreStall, lessThan(750), reason: 'Restore şifre çözme UI isolate’ini bloklamamalı (en uzun donma: ${restoreStall}ms)');
  },
      // Üretim gücünde (600.000 iterasyon) üç PBKDF2 türetmesi: yedek şifreleme, restore
      // çözme ve SEC-SAFETY koruyucu kopya şifrelemesi (21.11.2026). Süit dosyaları paralel
      // koştuğunda varsayılan 30 sn yetmez; doğrulanan şey hız değil UI isolate'inin donmamasıdır.
      timeout: const Timeout(Duration(minutes: 3)));
}
