import 'dart:convert';
import 'dart:io';

import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:spike_01_backend/backup/hub_snapshot_service.dart';
import 'package:spike_01_backend/db/database.dart';
import 'package:spike_01_backend/db/write_queue.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File dbFile;
  late Directory backupDir;
  late SpikeDatabase db;
  late WriteQueue writeQueue;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('mms_test_only_b1_hub_');
    dbFile = File(p.join(tempDir.path, 'data', 'market_master.db'));
    await dbFile.parent.create(recursive: true);
    backupDir = Directory(p.join(tempDir.path, 'backups'));
    db = SpikeDatabase(dbFile);
    writeQueue = WriteQueue();
    await db.customStatement('SELECT 1;');
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Faz B-1: Hub Snapshot (VACUUM INTO) & WriteQueue Ayrımı', () {
    test('BK-004: Aşama 1 VACUUM INTO WriteQueue içindeyken Aşama 2 şifreleme WriteQueue’yu bloklamaz', () async {
      await db.into(db.products).insert(
            ProductsCompanion.insert(
              id: 'prod_b1_1',
              barcode: '8690001001111',
              name: 'Pilot Şeker 1kg',
              price: 4500,
              stock: 50000,
            ),
          );

      var stage2Started = false;
      var writeRanDuringStage2 = false;

      final service = HubSnapshotService(
        readDb: () => db,
        writeQueue: writeQueue,
        liveDbFile: dbFile,
        backupDir: backupDir,
        hubId: 'HUB-PILOT-01',
        tenantId: 'tenant_pilot',
        storeId: 'store_01',
        appVersion: '1.0.0',
        kdfIterations: 1000,
        diskSpaceChecker: DiskSpaceChecker(
          freeBytesProbe: (_) async => 1024 * 1024 * 1024,
        ),
        encryptHook: ({
          required File inputFile,
          required File outputFile,
          required String password,
          required BackupManifest manifest,
          int kdfIterations = 1000,
        }) async {
          stage2Started = true;
          // Aşama 2 sürerken eşzamanlı WriteQueue yazması beklemeden çalışabilmelidir
          await writeQueue.enqueue(() async {
            await db.into(db.products).insert(
                  ProductsCompanion.insert(
                    id: 'prod_b1_concurrent',
                    barcode: '8690001002222',
                    name: 'Eşzamanlı Satış Ürünü',
                    price: 2500,
                    stock: 20000,
                  ),
                );
            writeRanDuringStage2 = true;
          });
          return MmsbakV2Crypto.encryptFile(
            inputFile: inputFile,
            outputFile: outputFile,
            password: password,
            manifest: manifest,
            kdfIterations: kdfIterations,
          );
        },
      );

      final result = await service.createEncryptedBackup(
        backupId: 'hub_bak_004',
        recoveryPassword: 'PilotHubParolasi-2026!',
        schemaVersion: db.schemaVersion,
      );

      expect(stage2Started, isTrue);
      expect(writeRanDuringStage2, isTrue);
      expect(result.backupFile.existsSync(), isTrue);

      // Snapshot ve .owner.json Aşama 2 sonrasında temizlenmiş olmalı
      expect(service.snapshotFileForBackup('hub_bak_004').existsSync(), isFalse);
      expect(
        service.ownerSidecarForSnapshot(service.snapshotFileForBackup('hub_bak_004')).existsSync(),
        isFalse,
      );

      // Çözülen SQLite dosyasında Aşama 1 ürünü var ama Aşama 2 sırasındaki yazma snapshot tutarlılığını bozmamış olmalı
      final decryptedDb = File(p.join(tempDir.path, 'decrypted_b1.db'));
      await MmsbakV2Crypto.decryptFile(
        inputFile: result.backupFile,
        outputFile: decryptedDb,
        password: 'PilotHubParolasi-2026!',
      );
      HubSnapshotService.verifySnapshotIntegrityOrThrow(decryptedDb);
    });

    test('BK-005: Yetersiz disk alanında fail-fast ve .tmp_snapshots sahiplik koruması', () async {
      await Directory(p.join(backupDir.path, '.tmp_snapshots')).create(recursive: true);
      final strangerFile = File(p.join(backupDir.path, '.tmp_snapshots', 'unrelated_file.db'));
      await strangerFile.writeAsString('do-not-delete', flush: true);

      final foreignSnap = File(p.join(backupDir.path, '.tmp_snapshots', 'snap_foreign.db'));
      final foreignOwner = File('${foreignSnap.path}.owner.json');
      await foreignSnap.writeAsString('foreign', flush: true);
      await foreignOwner.writeAsString(jsonEncode({'backup_id': 'other_job'}), flush: true);

      final service = HubSnapshotService(
        readDb: () => db,
        writeQueue: writeQueue,
        liveDbFile: dbFile,
        backupDir: backupDir,
        hubId: 'HUB-PILOT-01',
        tenantId: 'tenant_pilot',
        storeId: 'store_01',
        appVersion: '1.0.0',
        kdfIterations: 1000,
        diskSpaceChecker: DiskSpaceChecker(
          freeBytesProbe: (_) async => 1024, // Yetersiz alan (1 KB)
        ),
      );

      await expectLater(
        () => service.createEncryptedBackup(
          backupId: 'hub_bak_low_disk',
          recoveryPassword: 'PilotHubParolasi-2026!',
          schemaVersion: db.schemaVersion,
        ),
        throwsA(isA<BackupException>().having((e) => e.code, 'code', 'ERR_INSUFFICIENT_DISK_SPACE')),
      );

      // Sahipliği eşleşmeyen dosyalar kesinlikle silinmemeli
      expect(await service.deleteOwnedSnapshot(backupId: 'wrong_id', snapshotFile: foreignSnap), isFalse);
      expect(strangerFile.existsSync(), isTrue);
      expect(foreignSnap.existsSync(), isTrue);
    });
  });
}
