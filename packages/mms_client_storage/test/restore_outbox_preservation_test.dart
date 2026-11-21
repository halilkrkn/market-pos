import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Faz 7A — Restore veri bütünlüğü (ADR-BAK-03 / DEC-BAK-02) TDD testleri.
///
/// Kural: Geri yükleme, yedekten SONRA oluşmuş ve Hub'a henüz ulaşmamış Outbox
/// işlemlerini silemez; `client_seq` sayacı geriye alınamaz (aksi halde aynı sıra
/// numarası farklı içerikle yeniden üretilir ve Hub `409` ile kuyruğu kilitler).
/// Gerçek FFI SQLite (WAL) dosyaları üzerinde çalışır.
void main() {
  late Directory tempDir;
  late File dbFile;
  late ClientDatabase db;
  late ClientStorageRepository repo;
  late Directory backupDir;
  late Directory safetyDir;
  late LocalStorageProvider storage;

  const password = 'Restore_Outbox_Test_Password_2026!';
  const deviceId = 'DEV_RESTORE_01';
  const tenantId = 'tenant_restore';
  const storeId = 'store_restore';
  const kdf = 1000;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mms_restore_outbox_');
    dbFile = File(p.join(tempDir.path, 'client_local.db'));
    backupDir = Directory(p.join(tempDir.path, 'backups'))..createSync();
    safetyDir = Directory(p.join(tempDir.path, 'safety'))..createSync();
    storage = LocalStorageProvider(backupDir);
    db = ClientDatabase(dbFile);
    repo = ClientStorageRepository(db);
    await repo.upsertProducts([
      LocalProductsCompanion(
        id: const Value('prod_1'),
        barcode: const Value('869000111'),
        name: const Value('Su 0.5L'),
        price: const Value(1000),
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

  Future<BackupResult> takeBackup({String store = storeId}) {
    return DatabaseBackupEngine.createBackup(
      liveDbFile: dbFile,
      executeVacuumInto: (snap) async {
        await db.customStatement("VACUUM INTO '${snap.replaceAll("'", "''")}';");
      },
      deviceId: deviceId,
      tenantId: tenantId,
      storeId: store,
      databaseType: DatabaseType.clientLocal,
      schemaVersion: db.schemaVersion,
      appVersion: 'test',
      backupPassword: password,
      storageProvider: storage,
      kdfIterations: kdf,
    );
  }

  var resumeCount = 0;

  Future<RestoreResult> restore(
    String backupId, {
    String? expectedStoreId,
    Future<void> Function(String safetyPath)? safetyExecutor,
  }) {
    resumeCount = 0;
    return DatabaseBackupEngine.restoreBackup(
      backupId: backupId,
      liveDbFile: dbFile,
      backupPassword: password,
      storageProvider: storage,
      expectedDeviceId: deviceId,
      expectedTenantId: tenantId,
      expectedStoreId: expectedStoreId,
      expectedDatabaseType: DatabaseType.clientLocal,
      currentSchemaVersion: db.schemaVersion,
      pauseLiveDb: () async => db.close(),
      resumeLiveDb: () async {
        resumeCount++;
        db = ClientDatabase(dbFile);
        repo = ClientStorageRepository(db);
      },
      safetyBackupDir: safetyDir,
      customSafetySnapshotExecutor: safetyExecutor,
    );
  }

  Future<OutboxOperation> saleOp(int seq) async {
    return (db.select(db.outboxOperations)
          ..where((o) => o.deviceId.equals(deviceId) & o.clientSeq.equals(seq)))
        .getSingle();
  }

  group('Restore Outbox ve client_seq korunması (ADR-BAK-03)', () {
    test('1. Yedekten sonra oluşan bekleyen Outbox işlemi restore sonrası korunur', () async {
      await repo.createOfflineSale(
        deviceId: deviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_1', 1)],
      ); // seq 1
      final backup = await takeBackup();

      await repo.createOfflineSale(
        deviceId: deviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_1', 2)],
      ); // seq 2 (yedekte yok, Hub'a gönderilmedi)
      final pendingAfterBackup = await saleOp(2);

      await restore(backup.backupId);

      final restoredOutbox = await (db.select(db.outboxOperations)
            ..where((o) => o.deviceId.equals(deviceId)))
          .get();
      final seq2 = restoredOutbox.where((o) => o.clientSeq == 2).toList();
      expect(seq2, hasLength(1), reason: 'Yedekten sonraki bekleyen satış Outbox\'tan silinmemeli');
      expect(seq2.single.operationId, pendingAfterBackup.operationId);
      expect(seq2.single.payloadHash, pendingAfterBackup.payloadHash);
      expect(seq2.single.status, 'PENDING');
    });

    test('2. client_seq sayacı restore sonrası geriye alınmaz; yeni işlem eski sırayı tekrar kullanmaz', () async {
      final backup = await takeBackup(); // seq 0
      for (var i = 0; i < 3; i++) {
        await repo.createOfflineSale(
          deviceId: deviceId,
          paymentMethod: 'CASH',
          items: [CartItemInput.units('prod_1', 1)],
        );
      } // seq 1..3
      final op1 = await saleOp(1);
      final op2 = await saleOp(2);
      await repo.markOutboxSynced(op1.operationId, clientSeq: 1, deviceId: deviceId);
      await repo.markOutboxSynced(op2.operationId, clientSeq: 2, deviceId: deviceId);

      await restore(backup.backupId);

      final state = await repo.getSyncState(deviceId);
      expect(state!.currentClientSeq, greaterThanOrEqualTo(3));
      expect(state.lastSyncedSeq, 2, reason: 'Hub onayı alınmış sıra geri alınmamalı');

      final next = await repo.createOfflineSale(
        deviceId: deviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_1', 1)],
      );
      expect(next.clientSeq, 4, reason: 'Hub\'da kullanılmış 1..3 sıraları yeniden üretilmemeli');

      // Hub'a ulaşmış işlemler tekrar gönderilmek üzere PENDING'e dönmemeli
      expect((await saleOp(1)).status, 'SYNCED');
      expect((await saleOp(2)).status, 'SYNCED');
      expect((await saleOp(3)).status, 'PENDING');
    });

    test('3. Satış downlink cursor\'ı yedekteki değerde kalır (yedekten sonraki satışlar Hub\'dan yeniden indirilir)', () async {
      final backup = await takeBackup();
      await (db.update(db.clientSyncStates)..where((s) => s.deviceId.equals(deviceId)))
          .write(const ClientSyncStatesCompanion(lastServerSaleSeq: Value(42)));

      await restore(backup.backupId);

      final state = await repo.getSyncState(deviceId);
      expect(state!.lastServerSaleSeq, 0);
    });

    test('4. Farklı şubeye (store) ait yedek reddedilir ve canlı veri değişmez', () async {
      final backup = await takeBackup(store: 'store_OTHER');
      await repo.createOfflineSale(
        deviceId: deviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_1', 1)],
      );

      await expectLater(
        restore(backup.backupId, expectedStoreId: storeId),
        throwsA(isA<BackupException>().having((e) => e.code, 'code', 'ERR_STORE_ID_MISMATCH')),
      );
      expect(await db.select(db.localSales).get(), hasLength(1));
    });

    test('5. Güvenlik yedeği yazılamazsa (disk dolu) canlı DB yeniden açılır, veri korunur, staging temizlenir', () async {
      final backup = await takeBackup();
      await repo.createOfflineSale(
        deviceId: deviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_1', 1)],
      );

      await expectLater(
        restore(
          backup.backupId,
          safetyExecutor: (_) async =>
              throw const FileSystemException('There is not enough space on the disk.', '', OSError('disk full', 112)),
        ),
        throwsA(anything),
      );

      expect(resumeCount, 1, reason: 'Duraklatılan canlı veritabanı açık bırakılmamalı (kilitli kalmamalı)');
      expect(await db.select(db.localSales).get(), hasLength(1));
      final leftovers = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('restore_staging') || f.path.endsWith('.restore_journal'));
      expect(leftovers, isEmpty);
    });
  });
}
