import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// BK-LOCK — Yedek / geri yükleme işlemlerinin karşılıklı dışlanması.
///
/// Aynı yedek dizininde aynı anda yalnızca BİR yedek veya restore çalışır. Kilit
/// dosya tabanlıdır (özel oluşturma), bu yüzden ön plan zamanlayıcısı ile ileride
/// eklenecek arka plan işçisi (ayrı isolate / süreç) arasında da geçerlidir. Çöken
/// süreçten kalan kilit, [BackupOperationLock.staleAfter] sonrasında devralınır.
void main() {
  late Directory tempDir;
  late File lockFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mms_backup_lock_');
    lockFile = File(p.join(tempDir.path, BackupOperationLock.defaultFileName));
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {
      // Windows dosya kilidi; geçici dizin.
    }
  });

  group('BackupOperationLock', () {
    test('1. Kilit alınınca ikinci alıcı ERR_BACKUP_OPERATION_BUSY alır; bırakılınca tekrar alınır', () async {
      final a = BackupOperationLock(lockFile);
      final b = BackupOperationLock(lockFile);

      final held = await a.acquire(BackupOperationKind.restore);
      await expectLater(
        b.acquire(BackupOperationKind.backup),
        throwsA(isA<BackupException>()
            .having((e) => e.code, 'code', BackupOperationLock.busyErrorCode)
            .having((e) => e.message, 'message', contains('geri yükleme'))),
      );

      await held.release();
      expect(lockFile.existsSync(), isFalse);
      final again = await b.acquire(BackupOperationKind.backup);
      await again.release();
    });

    test('2. synchronized: işlem hata verse bile kilit bırakılır', () async {
      final lock = BackupOperationLock(lockFile);
      await expectLater(
        lock.synchronized(BackupOperationKind.backup, () async => throw StateError('disk dolu')),
        throwsStateError,
      );
      expect(lockFile.existsSync(), isFalse);
      expect(await lock.synchronized(BackupOperationKind.backup, () async => 42), 42);
    });

    test('3. Çöken süreçten kalan eski kilit staleAfter sonrasında devralınır; tazesi devralınmaz', () async {
      final now = DateTime.utc(2026, 11, 21, 12);
      lockFile.writeAsStringSync(jsonEncode({
        'operation': 'BACKUP',
        'pid': -1,
        'acquired_at': now.subtract(const Duration(hours: 2)).toIso8601String(),
      }));
      final lock = BackupOperationLock(lockFile, staleAfter: const Duration(hours: 1), clock: () => now);
      final held = await lock.acquire(BackupOperationKind.restore);
      final content = jsonDecode(lockFile.readAsStringSync()) as Map<String, dynamic>;
      expect(content['operation'], 'RESTORE');
      await held.release();

      lockFile.writeAsStringSync(jsonEncode({
        'operation': 'BACKUP',
        'pid': -1,
        'acquired_at': now.subtract(const Duration(minutes: 10)).toIso8601String(),
      }));
      await expectLater(lock.acquire(BackupOperationKind.restore), throwsA(isA<BackupException>()));
    });

    test('4. Okunamayan (bozuk) kilit dosyası taze ise meşgul sayılır; eskiyse devralınır', () async {
      lockFile.writeAsStringSync('{bozuk');
      final fresh = BackupOperationLock(lockFile, staleAfter: const Duration(hours: 1));
      await expectLater(fresh.acquire(BackupOperationKind.backup), throwsA(isA<BackupException>()));

      final later = BackupOperationLock(
        lockFile,
        staleAfter: const Duration(hours: 1),
        clock: () => DateTime.now().toUtc().add(const Duration(hours: 3)),
      );
      final held = await later.acquire(BackupOperationKind.backup);
      await held.release();
    });

    test('5. Kilit isolate sınırını aşar (arka plan işçisi senaryosu)', () async {
      final held = await BackupOperationLock(lockFile).acquire(BackupOperationKind.restore);
      final path = lockFile.path;
      final otherIsolateCode = await Isolate.run(() async {
        try {
          await BackupOperationLock(File(path)).acquire(BackupOperationKind.backup);
          return 'ACQUIRED';
        } on BackupException catch (e) {
          return e.code;
        }
      });
      expect(otherIsolateCode, BackupOperationLock.busyErrorCode);
      await held.release();
    });

    test('6. Başkasının kilidi bırakılmaz (release yalnızca kendi belirtecini siler)', () async {
      final now = DateTime.utc(2026, 11, 21, 12);
      final a = BackupOperationLock(lockFile, staleAfter: const Duration(minutes: 1), clock: () => now);
      final heldA = await a.acquire(BackupOperationKind.backup);
      // A takıldı; kilit eskidi ve B devraldı.
      final b = BackupOperationLock(
        lockFile,
        staleAfter: const Duration(minutes: 1),
        clock: () => now.add(const Duration(minutes: 5)),
      );
      final heldB = await b.acquire(BackupOperationKind.restore);
      await heldA.release(); // A geç uyanır: B'nin kilidini SİLMEMELİ.
      expect(lockFile.existsSync(), isTrue);
      expect((jsonDecode(lockFile.readAsStringSync()) as Map)['operation'], 'RESTORE');
      await heldB.release();
      expect(lockFile.existsSync(), isFalse);
    });

    test('8. Varsayılan ~60 sn staleAfter + heartbeat: aktif işlem staleAfter süresini aşsa bile devralınmaz', () async {
      final defaultLock = BackupOperationLock(lockFile);
      expect(defaultLock.staleAfter, const Duration(seconds: 60));
      expect(defaultLock.heartbeatInterval, const Duration(seconds: 10));

      final a = BackupOperationLock(
        lockFile,
        staleAfter: const Duration(milliseconds: 240),
        heartbeatInterval: const Duration(milliseconds: 50),
      );
      final b = BackupOperationLock(
        lockFile,
        staleAfter: const Duration(milliseconds: 240),
        heartbeatInterval: Duration.zero,
      );

      final held = await a.acquire(BackupOperationKind.restore);
      try {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await expectLater(
          b.acquire(BackupOperationKind.backup),
          throwsA(isA<BackupException>().having((e) => e.code, 'code', BackupOperationLock.busyErrorCode)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await expectLater(
          b.acquire(BackupOperationKind.backup),
          throwsA(isA<BackupException>().having((e) => e.code, 'code', BackupOperationLock.busyErrorCode)),
        );
        expect(held.lostOwnership, isFalse);
      } finally {
        await held.release();
      }
      expect(lockFile.existsSync(), isFalse);
    });

    test('9. Gerçek süreç çökmesi (SIGKILL): kilit önce meşgul kalır, heartbeat durunca staleAfter sonrası kurtarılır', () async {
      String resolveDartExecutable() {
        final currentExe = Platform.resolvedExecutable;
        final exeBase = p.basenameWithoutExtension(currentExe).toLowerCase();
        final dartName = Platform.isWindows ? 'dart.exe' : 'dart';
        if (exeBase == 'dart') {
          return currentExe;
        }
        var dir = Directory(currentExe).parent;
        for (var i = 0; i < 8; i++) {
          final cachedDart = File(p.join(dir.path, 'dart-sdk', 'bin', dartName));
          if (cachedDart.existsSync()) {
            return cachedDart.path;
          }
          final nestedCachedDart = File(
            p.join(dir.path, 'bin', 'cache', 'dart-sdk', 'bin', dartName),
          );
          if (nestedCachedDart.existsSync()) {
            return nestedCachedDart.path;
          }
          final parent = dir.parent;
          if (parent.path == dir.path) break;
          dir = parent;
        }
        final whichCmd = Platform.isWindows ? 'where.exe' : 'which';
        final res = Process.runSync(whichCmd, const ['dart']);
        if (res.exitCode == 0) {
          for (final line in LineSplitter.split(res.stdout.toString())) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) continue;
            final candidate = File(
              p.join(p.dirname(trimmed), 'cache', 'dart-sdk', 'bin', dartName),
            );
            if (candidate.existsSync()) return candidate.path;
            if (!Platform.isWindows || trimmed.toLowerCase().endsWith('.exe')) {
              return trimmed;
            }
          }
        }
        return currentExe;
      }

      final scriptFile = File(p.join(tempDir.path, 'lock_holder_child.dart'));
      final pkgCfg = File(p.join(Directory.current.path, '.dart_tool', 'package_config.json'));
      scriptFile.writeAsStringSync('''
import 'dart:async';
import 'dart:io';
import 'package:mms_client_storage/mms_client_storage.dart';

Future<void> main(List<String> args) async {
  final lock = BackupOperationLock(
    File(args[0]),
    staleAfter: const Duration(milliseconds: 500),
    heartbeatInterval: const Duration(milliseconds: 80),
  );
  await lock.acquire(BackupOperationKind.backup);
  stdout.writeln('ACQUIRED');
  await stdout.flush();
  await Future<void>.delayed(const Duration(seconds: 30));
}
''');

      final proc = await Process.start(
        resolveDartExecutable(),
        ['--packages=${pkgCfg.path}', scriptFile.path, lockFile.path],
      );
      addTearDown(() => proc.kill(ProcessSignal.sigkill));

      final stderrBuffer = StringBuffer();
      proc.stderr.transform(utf8.decoder).listen(stderrBuffer.write);

      final ready = await proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .firstWhere((line) => line.trim() == 'ACQUIRED')
          .timeout(
            const Duration(seconds: 45),
            onTimeout: () => throw TimeoutException(
              'Çocuk süreç ACQUIRED bildirmedi. stderr: $stderrBuffer',
              const Duration(seconds: 45),
            ),
          );
      expect(ready, 'ACQUIRED');

      final parentLock = BackupOperationLock(
        lockFile,
        staleAfter: const Duration(milliseconds: 500),
        heartbeatInterval: Duration.zero,
      );
      await expectLater(
        parentLock.acquire(BackupOperationKind.restore),
        throwsA(isA<BackupException>().having((e) => e.code, 'code', BackupOperationLock.busyErrorCode)),
      );

      // Ani süreç çökmesi simülasyonu: release çalışmaz, heartbeat durur.
      proc.kill(ProcessSignal.sigkill);
      await proc.exitCode;

      await Future<void>.delayed(const Duration(milliseconds: 650));
      final recovered = await parentLock.acquire(BackupOperationKind.restore);
      try {
        final json = jsonDecode(lockFile.readAsStringSync()) as Map<String, dynamic>;
        expect(json['operation'], 'RESTORE');
        expect(json['pid'], pid);
      } finally {
        await recovered.release();
      }
      expect(lockFile.existsSync(), isFalse);
    });

    test('10. TOCTOU koruması: stale kilit üzerinde 6 eşzamanlı isolate yarışında yalnızca 1 sahip kazanır ve kilidi silinmez', () async {
      final staleTs = DateTime.now().toUtc().subtract(const Duration(minutes: 5)).toIso8601String();
      lockFile.writeAsStringSync(jsonEncode({
        'version': 2,
        'operation': 'BACKUP',
        'pid': -1,
        'owner_id': 'dead_owner_token',
        'token': 'dead_owner_token',
        'acquired_at': staleTs,
        'heartbeat_at': staleTs,
      }));

      final lockPath = lockFile.path;
      final results = await Future.wait(
        List.generate(6, (_) {
          return Isolate.run(() async {
            final lock = BackupOperationLock(
              File(lockPath),
              staleAfter: const Duration(seconds: 30),
              heartbeatInterval: Duration.zero,
            );
            try {
              final held = await lock.acquire(BackupOperationKind.restore);
              await Future<void>.delayed(const Duration(milliseconds: 180));
              final raw = File(lockPath).existsSync() ? File(lockPath).readAsStringSync() : null;
              final stillMine = raw != null &&
                  (jsonDecode(raw) as Map<String, dynamic>)['token'] == held.ownerToken;
              await held.release();
              return stillMine ? 'WIN_INTACT' : 'WIN_CORRUPTED';
            } on BackupException catch (e) {
              return e.code;
            }
          });
        }),
      );

      expect(results.where((r) => r == 'WIN_INTACT'), hasLength(1), reason: 'Sonuçlar: $results');
      expect(results.where((r) => r == BackupOperationLock.busyErrorCode), hasLength(5));
      expect(lockFile.existsSync(), isFalse);
    });

    test('11. Sahipliği kaybeden eski sahip heartbeatNow() ve release() ile yeni kilidi ezmez', () async {
      var currentNow = DateTime.utc(2026, 11, 21, 12, 0, 0);
      final a = BackupOperationLock(
        lockFile,
        staleAfter: const Duration(seconds: 60),
        heartbeatInterval: Duration.zero,
        clock: () => currentNow,
      );
      final b = BackupOperationLock(
        lockFile,
        staleAfter: const Duration(seconds: 60),
        heartbeatInterval: Duration.zero,
        clock: () => currentNow,
      );

      final heldA = await a.acquire(BackupOperationKind.backup);
      currentNow = currentNow.add(const Duration(seconds: 90));
      final heldB = await b.acquire(BackupOperationKind.restore);

      expect(await heldA.heartbeatNow(), isFalse);
      expect(heldA.lostOwnership, isTrue);
      await heldA.release();

      expect(lockFile.existsSync(), isTrue);
      final diskJson = jsonDecode(lockFile.readAsStringSync()) as Map<String, dynamic>;
      expect(diskJson['token'], heldB.ownerToken);
      expect(diskJson['operation'], 'RESTORE');

      await heldB.release();
      expect(lockFile.existsSync(), isFalse);
    });

    test('12. Eski v1 kilit biçimiyle (heartbeat_at olmadan) geriye dönük uyumludur', () async {
      final now = DateTime.utc(2026, 11, 21, 12, 0, 0);
      lockFile.writeAsStringSync(jsonEncode({
        'operation': 'BACKUP',
        'pid': -1,
        'token': 'legacy_v1_tok',
        'acquired_at': now.subtract(const Duration(seconds: 10)).toIso8601String(),
      }));

      final freshCheck = BackupOperationLock(
        lockFile,
        staleAfter: const Duration(seconds: 60),
        heartbeatInterval: Duration.zero,
        clock: () => now,
      );
      await expectLater(
        freshCheck.acquire(BackupOperationKind.restore),
        throwsA(isA<BackupException>().having((e) => e.code, 'code', BackupOperationLock.busyErrorCode)),
      );

      final staleCheck = BackupOperationLock(
        lockFile,
        staleAfter: const Duration(seconds: 60),
        heartbeatInterval: Duration.zero,
        clock: () => now.add(const Duration(minutes: 2)),
      );
      final held = await staleCheck.acquire(BackupOperationKind.restore);
      await held.release();
    });

    test('13. 0 baytlık yarıda kalmış kilit dosyası kısa sürede kurtarılır (60 sn beklemez); tazesi engeller', () async {
      var currentNow = DateTime.utc(2026, 11, 21, 12, 0, 0);
      lockFile.writeAsStringSync('');

      final freshEmpty = BackupOperationLock(
        lockFile,
        staleAfter: const Duration(seconds: 60),
        emptyLockStaleAfter: const Duration(seconds: 5),
        heartbeatInterval: Duration.zero,
        clock: () => currentNow,
      );
      await expectLater(
        freshEmpty.acquire(BackupOperationKind.backup),
        throwsA(isA<BackupException>().having((e) => e.code, 'code', BackupOperationLock.busyErrorCode)),
      );

      // 6 saniye sonra (staleAfter 60s dolmadan!) 0-bayt çökme artığı kurtarılır.
      final agedLock = BackupOperationLock(
        lockFile,
        staleAfter: const Duration(seconds: 60),
        emptyLockStaleAfter: const Duration(seconds: 5),
        heartbeatInterval: Duration.zero,
        clock: () => lockFile.lastModifiedSync().toUtc().add(const Duration(seconds: 6)),
      );
      final recovered = await agedLock.acquire(BackupOperationKind.restore);
      try {
        expect(lockFile.existsSync(), isTrue);
      } finally {
        await recovered.release();
      }
      expect(lockFile.existsSync(), isFalse);
    });

    test('14. Sahip doğrulamalı .recovering mutex eski .recovering üzerinde eşzamanlı kurtarmayı tek kazananla sınırlar', () async {
      final staleTs = DateTime.now().toUtc().subtract(const Duration(minutes: 5)).toIso8601String();
      lockFile.writeAsStringSync(jsonEncode({
        'version': 2,
        'operation': 'BACKUP',
        'pid': -1,
        'owner_id': 'crashed_owner',
        'token': 'crashed_owner',
        'acquired_at': staleTs,
        'heartbeat_at': staleTs,
      }));
      final recoveryFile = File('${lockFile.path}.recovering');
      recoveryFile.writeAsStringSync(jsonEncode({
        'token': 'dead_recoverer',
        'created_at': staleTs,
      }));

      final lockPath = lockFile.path;
      final outcomes = await Future.wait(
        List.generate(6, (_) {
          return Isolate.run(() async {
            final lock = BackupOperationLock(
              File(lockPath),
              staleAfter: const Duration(seconds: 30),
              recoveryLockStaleAfter: const Duration(seconds: 10),
              heartbeatInterval: Duration.zero,
            );
            try {
              final held = await lock.acquire(BackupOperationKind.backup);
              await Future<void>.delayed(const Duration(milliseconds: 120));
              await held.release();
              return 'WON';
            } on BackupException catch (e) {
              return e.code;
            }
          });
        }),
      );

      expect(outcomes.where((r) => r == 'WON'), hasLength(1), reason: 'Sonuçlar: $outcomes');
      expect(outcomes.where((r) => r == BackupOperationLock.busyErrorCode), hasLength(5));
      expect(lockFile.existsSync(), isFalse);
      expect(recoveryFile.existsSync(), isFalse);
    });
  });

  group('ScheduledBackupRunner + meşgul kilit', () {
    test('7. Zamanlanmış tur, başka işlem sürerken hata KAYDETMEDEN atlanır; manuel tur hatayı kaydeder', () async {
      final store = BackupScheduleStateStore(File(p.join(tempDir.path, 'state.json')));
      final runner = ScheduledBackupRunner(
        readPolicy: () => const BackupSchedulePolicy(interval: Duration(hours: 24)),
        stateStore: store,
        createBackup: () async => throw const BackupException(
          BackupOperationLock.busyErrorCode,
          'Şu anda geri yükleme sürüyor.',
        ),
      );

      expect(await runner.runIfDue(), isNull);
      final afterScheduled = await store.load();
      expect(afterScheduled.history, isEmpty);
      expect(afterScheduled.consecutiveFailures, 0);
      expect(afterScheduled.lastFailureAt, isNull, reason: '30 dk yeniden deneme gecikmesi tetiklenmemeli');

      final manual = await runner.runNow(trigger: BackupTrigger.manual);
      expect(manual.success, isFalse);
      expect(manual.errorCode, BackupOperationLock.busyErrorCode);
    });
  });
}
