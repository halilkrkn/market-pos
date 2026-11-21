import 'dart:io';
import 'dart:typed_data';

import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// Faz 7D — USB / harici klasöre yedek aktarımı (TDD).
/// Fiziksel USB yerine, hata enjeksiyonlu yazıcı ile disk dolu / aygıt çıkarıldı
/// senaryoları ve gerçek dosya sistemi ile bütünlük doğrulaması test edilir.
void main() {
  late Directory tempDir;
  late Directory localBackups;
  late Directory usb;
  late BackupResult backup;

  const deviceId = 'DEV_USB_01';
  const tenantId = 'tenant_usb';
  const storeId = 'store_usb';

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('mms_usb_transfer_');
    localBackups = Directory(p.join(tempDir.path, 'backups'))..createSync();
    usb = Directory(p.join(tempDir.path, 'USB_E'))..createSync();
    final liveDb = File(p.join(tempDir.path, 'client_local.db'));
    final raw = sqlite3.open(liveDb.path)
      ..execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT);')
      ..execute("INSERT INTO t (v) VALUES ('kayıt');");
    backup = await DatabaseBackupEngine.createBackup(
      liveDbFile: liveDb,
      executeVacuumInto: (snap) async => raw.execute("VACUUM INTO '${snap.replaceAll("'", "''")}';"),
      deviceId: deviceId,
      tenantId: tenantId,
      storeId: storeId,
      databaseType: DatabaseType.clientLocal,
      schemaVersion: 4,
      appVersion: 'test',
      backupPassword: 'Usb_Transfer_Pass_2026',
      storageProvider: LocalStorageProvider(localBackups),
      kdfIterations: 1000,
    );
    raw.close();
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<File> sourceFile() => LocalStorageProvider(localBackups).getBackupFile(backup.backupId);

  group('Dışa aktarım (USB / ağ klasörü)', () {
    test('1. Başarılı aktarım: içerik bayt bayt aynı, geçici dosya kalmaz', () async {
      final src = await sourceFile();
      final out = await BackupFileTransfer.exportToDirectory(source: src, targetDir: usb);

      expect(out.existsSync(), isTrue);
      expect(out.readAsBytesSync(), src.readAsBytesSync());
      expect(usb.listSync().where((f) => f.path.endsWith('.tmp')), isEmpty);
    });

    test('2. Disk dolu: anlaşılır hata (ERR_DISK_FULL), yarım dosya bırakılmaz, kaynak korunur', () async {
      final src = await sourceFile();
      await expectLater(
        BackupFileTransfer.exportToDirectory(
          source: src,
          targetDir: usb,
          writer: (target, bytes) async {
            await target.writeAsBytes(bytes.sublist(0, bytes.length ~/ 2));
            throw FileSystemException('There is not enough space on the disk.', target.path, const OSError('disk full', 112));
          },
        ),
        throwsA(isA<BackupException>().having((e) => e.code, 'code', 'ERR_DISK_FULL')),
      );
      expect(usb.listSync(), isEmpty, reason: 'Yarım yazılmış .tmp dosyası geçerli yedek gibi kalmamalı');
      expect(src.existsSync(), isTrue);
    });

    test('3. USB yazım sırasında çıkarıldı: ERR_TARGET_UNAVAILABLE', () async {
      final src = await sourceFile();
      await expectLater(
        BackupFileTransfer.exportToDirectory(
          source: src,
          targetDir: usb,
          writer: (target, bytes) async =>
              throw FileSystemException('The device is not ready.', target.path, const OSError('not ready', 21)),
        ),
        throwsA(isA<BackupException>().having((e) => e.code, 'code', 'ERR_TARGET_UNAVAILABLE')),
      );
    });

    test('4. Sessiz bozulma (yazılan ≠ kaynak) geri okuma doğrulamasıyla yakalanır', () async {
      final src = await sourceFile();
      await expectLater(
        BackupFileTransfer.exportToDirectory(
          source: src,
          targetDir: usb,
          writer: (target, bytes) async {
            final corrupted = Uint8List.fromList(bytes);
            corrupted[corrupted.length - 1] ^= 0xFF;
            await target.writeAsBytes(corrupted, flush: true);
          },
        ),
        throwsA(isA<BackupException>().having((e) => e.code, 'code', 'ERR_EXPORT_VERIFY_FAILED')),
      );
      expect(usb.listSync(), isEmpty);
    });

    test('5. Hedefte aynı yedek varsa üzerine yazılmaz', () async {
      final src = await sourceFile();
      await BackupFileTransfer.exportToDirectory(source: src, targetDir: usb);
      await expectLater(
        BackupFileTransfer.exportToDirectory(source: src, targetDir: usb),
        throwsA(isA<BackupException>().having((e) => e.code, 'code', 'ERR_TARGET_EXISTS')),
      );
    });

    test('6. Hedef klasör yoksa (USB takılı değil) ERR_TARGET_UNAVAILABLE', () async {
      final src = await sourceFile();
      await expectLater(
        BackupFileTransfer.exportToDirectory(source: src, targetDir: Directory(p.join(tempDir.path, 'YOK'))),
        throwsA(isA<BackupException>().having((e) => e.code, 'code', 'ERR_TARGET_UNAVAILABLE')),
      );
    });
  });

  group('İçe aktarım (USB → yerel yedek klasörü)', () {
    Future<File> exported() async => BackupFileTransfer.exportToDirectory(source: await sourceFile(), targetDir: usb);

    Future<BackupPackageInfo> import(File f, {String device = deviceId, String store = storeId}) =>
        BackupFileTransfer.importFromFile(
          external: f,
          backupRoot: Directory(p.join(tempDir.path, 'restore_area')),
          expectedType: DatabaseType.clientLocal,
          expectedDeviceId: device,
          expectedTenantId: tenantId,
          expectedStoreId: store,
        );

    test('7. Geçerli yedek içe aktarılır ve restore için listelenir', () async {
      final info = await import(await exported());
      expect(info.backupId, backup.backupId);
      final listed = await LocalStorageProvider(Directory(p.join(tempDir.path, 'restore_area'))).listBackups();
      expect(listed.single.backupId, backup.backupId);
    });

    test('8. Yarım (kesik) dosya reddedilir: ERR_INCOMPLETE_BACKUP', () async {
      final f = await exported();
      final bytes = f.readAsBytesSync();
      final truncated = File(p.join(usb.path, 'kesik.mmsbak'))..writeAsBytesSync(bytes.sublist(0, bytes.length - 100));
      await expectLater(
        import(truncated),
        throwsA(isA<BackupException>().having((e) => e.code, 'code', 'ERR_INCOMPLETE_BACKUP')),
      );
    });

    test('9. Yedek olmayan / bozuk dosya reddedilir: ERR_CORRUPT_BACKUP', () async {
      final junk = File(p.join(usb.path, 'foto.mmsbak'))..writeAsBytesSync(List<int>.generate(500, (i) => i % 256));
      await expectLater(
        import(junk),
        throwsA(isA<BackupException>().having((e) => e.code, 'code', 'ERR_CORRUPT_BACKUP')),
      );
    });

    test('10. Başka cihaz veya başka şubenin yedeği içe aktarılmaz', () async {
      final f = await exported();
      await expectLater(
        import(f, device: 'DEV_BASKA'),
        throwsA(isA<BackupException>().having((e) => e.code, 'code', 'ERR_DEVICE_ID_MISMATCH')),
      );
      await expectLater(
        import(f, store: 'store_BASKA'),
        throwsA(isA<BackupException>().having((e) => e.code, 'code', 'ERR_STORE_ID_MISMATCH')),
      );
    });
  });
}
