import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Faz 3 / 7D — Zamanlanmış yerel yedekleme iş kuralları (TDD, altyapıdan bağımsız).
void main() {
  late Directory tempDir;
  late File stateFile;
  late DateTime now;

  BackupResult fakeResult(String id, {int size = 2048}) {
    final manifest = BackupManifest(
      backupId: id,
      deviceId: 'SERVER_HUB',
      tenantId: 't',
      storeId: 's',
      databaseType: DatabaseType.centralMaster,
      schemaVersion: 3,
      appVersion: 'test',
      timestamp: now,
      checksum: 'x' * 64,
      unencryptedSizeBytes: size,
      encryptedSizeBytes: size,
      kdfIterations: 1000,
    );
    return BackupResult(
      backupId: id,
      manifest: manifest,
      encryptedSizeBytes: size,
      unencryptedSizeBytes: size,
      createdAt: now,
    );
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mms_sched_backup_');
    stateFile = File(p.join(tempDir.path, 'backup_schedule_state.json'));
    now = DateTime.utc(2026, 11, 21, 3, 0);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('BackupSchedulePolicy.isDue', () {
    const policy = BackupSchedulePolicy(interval: Duration(hours: 24));

    test('1. Hiç başarılı yedek yoksa yedek zamanı gelmiştir', () {
      expect(policy.isDue(state: BackupScheduleState.empty, now: now), isTrue);
    });

    test('2. Aralık dolmadan tekrar yedek alınmaz; dolunca alınır', () {
      final state = BackupScheduleState.empty.copyWith(lastSuccessAt: now.subtract(const Duration(hours: 23)));
      expect(policy.isDue(state: state, now: now), isFalse);
      expect(policy.isDue(state: state, now: now.add(const Duration(hours: 1))), isTrue);
    });

    test('3. Son deneme başarısızsa (ör. disk dolu) yeniden deneme gecikmesi beklenir; sonra tekrar denenir', () {
      final state = BackupScheduleState.empty.copyWith(
        lastFailureAt: now.subtract(const Duration(minutes: 5)),
        consecutiveFailures: 1,
      );
      expect(policy.isDue(state: state, now: now), isFalse);
      expect(policy.isDue(state: state, now: now.add(policy.failureRetryDelay)), isTrue);
    });

    test('4. Devre dışı politika (interval=0) hiçbir zaman yedek tetiklemez', () {
      const disabled = BackupSchedulePolicy(interval: Duration.zero);
      expect(disabled.enabled, isFalse);
      expect(disabled.isDue(state: BackupScheduleState.empty, now: now), isFalse);
    });

    test('5. Son başarı + aralık "gecikmiş" (overdue) olarak raporlanır', () {
      final state = BackupScheduleState.empty.copyWith(lastSuccessAt: now.subtract(const Duration(hours: 30)));
      expect(policy.isOverdue(state: state, now: now), isTrue);
      final fresh = BackupScheduleState.empty.copyWith(lastSuccessAt: now.subtract(const Duration(hours: 2)));
      expect(policy.isOverdue(state: fresh, now: now), isFalse);
    });
  });

  group('ScheduledBackupRunner', () {
    ScheduledBackupRunner runner({
      required Future<BackupResult> Function() create,
      Future<List<String>> Function()? prune,
      Future<void> Function(BackupResult)? afterSuccess,
      BackupSchedulePolicy policy = const BackupSchedulePolicy(interval: Duration(hours: 24)),
    }) {
      return ScheduledBackupRunner(
        readPolicy: () => policy,
        stateStore: BackupScheduleStateStore(stateFile),
        createBackup: create,
        pruneExpired: prune,
        afterSuccess: afterSuccess,
        clock: () => now,
      );
    }

    test('6. Başarılı çalıştırma son başarı zamanını, boyutu ve geçmişi kalıcı yazar; saklama politikası uygulanır', () async {
      var pruneCalls = 0;
      final r = runner(
        create: () async => fakeResult('b1'),
        prune: () async {
          pruneCalls++;
          return ['old1', 'old2'];
        },
      );

      final record = await r.runIfDue();

      expect(record, isNotNull);
      expect(record!.success, isTrue);
      expect(record.backupId, 'b1');
      expect(record.prunedCount, 2);
      expect(pruneCalls, 1);

      final reloaded = await BackupScheduleStateStore(stateFile).load();
      expect(reloaded.lastSuccessAt, now);
      expect(reloaded.consecutiveFailures, 0);
      expect(reloaded.history.single.backupId, 'b1');
      expect(reloaded.history.single.sizeBytes, 2048);
    });

    test('7. Yedek zamanı gelmemişse hiçbir şey yapılmaz', () async {
      var calls = 0;
      await BackupScheduleStateStore(stateFile).save(
        BackupScheduleState.empty.copyWith(lastSuccessAt: now.subtract(const Duration(hours: 1))),
      );
      final r = runner(create: () async {
        calls++;
        return fakeResult('b2');
      });
      expect(await r.runIfDue(), isNull);
      expect(calls, 0);
    });

    test('8. Eşzamanlı tetiklemeler tek yedek üretir (single-flight)', () async {
      var calls = 0;
      final gate = Completer<void>();
      final r = runner(create: () async {
        calls++;
        await gate.future;
        return fakeResult('b3');
      });
      final f1 = r.runNow(trigger: BackupTrigger.scheduled);
      final f2 = r.runNow(trigger: BackupTrigger.manual);
      gate.complete();
      final results = await Future.wait([f1, f2]);
      expect(calls, 1);
      expect(identical(results[0], results[1]), isTrue);
    });

    test('9. Disk dolu hatası anlaşılır kodla kaydedilir, ardışık hata sayılır, başarıda sıfırlanır', () async {
      var fail = true;
      final r = runner(create: () async {
        if (fail) {
          throw const FileSystemException('There is not enough space on the disk.', r'E:\backups', OSError('disk full', 112));
        }
        return fakeResult('b4');
      });

      final failed = await r.runNow(trigger: BackupTrigger.scheduled);
      expect(failed.success, isFalse);
      expect(failed.errorCode, 'ERR_DISK_FULL');
      var state = await BackupScheduleStateStore(stateFile).load();
      expect(state.consecutiveFailures, 1);
      expect(state.lastErrorCode, 'ERR_DISK_FULL');
      expect(state.lastSuccessAt, isNull);

      fail = false;
      now = now.add(const Duration(hours: 1));
      final ok = await r.runNow(trigger: BackupTrigger.manual);
      expect(ok.success, isTrue);
      state = await BackupScheduleStateStore(stateFile).load();
      expect(state.consecutiveFailures, 0);
      expect(state.lastErrorCode, isNull);
      expect(state.history, hasLength(2));
    });

    test('10. Hedef aygıt çıkarılmışsa (USB) ERR_TARGET_UNAVAILABLE olarak sınıflanır', () async {
      final r = runner(create: () async {
        throw const FileSystemException('The device is not ready.', r'F:\mms', OSError('not ready', 21));
      });
      final rec = await r.runNow(trigger: BackupTrigger.scheduled);
      expect(rec.errorCode, 'ERR_TARGET_UNAVAILABLE');
    });

    test('11. Uzak yükleme (Drive) hatası yerel yedeği başarısız yapmaz; ayrı kaydedilir', () async {
      final r = runner(
        create: () async => fakeResult('b5'),
        afterSuccess: (_) async => throw StateError('Drive erişilemiyor'),
      );
      final rec = await r.runNow(trigger: BackupTrigger.scheduled);
      expect(rec.success, isTrue);
      expect(rec.postProcessError, contains('Drive erişilemiyor'));
      final state = await BackupScheduleStateStore(stateFile).load();
      expect(state.lastSuccessAt, now);
    });

    test('12. Geçmiş en fazla 30 kayıt tutar (en yeni başta)', () async {
      var i = 0;
      final r = runner(create: () async => fakeResult('b${i++}'));
      for (var k = 0; k < 35; k++) {
        now = now.add(const Duration(minutes: 1));
        await r.runNow(trigger: BackupTrigger.manual);
      }
      final state = await BackupScheduleStateStore(stateFile).load();
      expect(state.history, hasLength(BackupScheduleState.maxHistory));
      expect(state.history.first.backupId, 'b34');
    });

    test('13. Bozuk durum dosyası çökme yaratmaz; karantinaya alınır ve boş durumla devam edilir', () async {
      stateFile.writeAsStringSync('{bozuk json');
      final state = await BackupScheduleStateStore(stateFile).load();
      expect(state.lastSuccessAt, isNull);
      final quarantined = tempDir.listSync().where((f) => f.path.contains('.corrupt_'));
      expect(quarantined, isNotEmpty, reason: 'Bozuk dosya sessizce silinmemeli');
    });

    test('14. Durum dosyası atomik yazılır (geçici dosya kalmaz) ve geçerli JSON içerir', () async {
      await BackupScheduleStateStore(stateFile).save(BackupScheduleState.empty.copyWith(lastSuccessAt: now));
      expect(tempDir.listSync().where((f) => f.path.endsWith('.tmp')), isEmpty);
      expect(() => jsonDecode(stateFile.readAsStringSync()), returnsNormally);
    });
  });
}
