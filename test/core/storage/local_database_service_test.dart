import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:path/path.dart' as p;

/// DB close timeout testinde kullanılmak üzere close operasyonunu geciktiren test executor'ı
class _HangingCloseExecutor extends QueryExecutor {
  final QueryExecutor _inner;
  final Duration _closeDelay;

  _HangingCloseExecutor(this._inner, {this._closeDelay = const Duration(milliseconds: 500)});

  @override
  SqlDialect get dialect => _inner.dialect;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) => _inner.ensureOpen(user);

  @override
  Future<void> runBatched(BatchedStatements statements) => _inner.runBatched(statements);

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) =>
      _inner.runCustom(statement, args);

  @override
  Future<int> runDelete(String statement, List<Object?> args) =>
      _inner.runDelete(statement, args);

  @override
  Future<int> runInsert(String statement, List<Object?> args) =>
      _inner.runInsert(statement, args);

  @override
  Future<List<Map<String, Object?>>> runSelect(String statement, List<Object?> args) =>
      _inner.runSelect(statement, args);

  @override
  Future<int> runUpdate(String statement, List<Object?> args) =>
      _inner.runUpdate(statement, args);

  @override
  TransactionExecutor beginTransaction() => _inner.beginTransaction();

  @override
  QueryExecutor beginExclusive() => _inner.beginExclusive();

  @override
  Future<void> close() async {
    await Future.delayed(_closeDelay);
    await _inner.close();
  }
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  group('LocalDatabaseService - İstemci Yerel Drift SQLite Testleri', () {
    late LocalDatabaseService localDbService;
    Directory? tempDir;

    setUp(() async {
      localDbService = LocalDatabaseService.forTesting(
        NativeDatabase.memory(),
        path: ':memory:',
      );
    });

    tearDown(() async {
      await localDbService.close();
      await LocalDatabaseService.closeActive();
      LocalDatabaseService.resetForTesting();
      if (tempDir != null && tempDir!.existsSync()) {
        try {
          tempDir!.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('1. Başlangıç Durumu: Doğru path ile başlatılır ve sayaçlar 0 döner', () async {
      expect(localDbService.databasePath, ':memory:');

      final pendingOutbox = await localDbService.getPendingOutboxCount();
      final localSales = await localDbService.getLocalSalesCount();
      final localProducts = await localDbService.getLocalProductsCount();

      expect(pendingOutbox, 0);
      expect(localSales, 0);
      expect(localProducts, 0);
    });

    test('2. Cihaz Kimliği Başlatma: Repository üzerinden istemci durumu oluşturulur', () async {
      final syncState = await localDbService.repository.initializeDevice(
        'POS-WIN-01',
      );

      expect(syncState.deviceId, 'POS-WIN-01');
      expect(syncState.currentClientSeq, 0);
      expect(syncState.lastSyncedSeq, 0);

      final existingState = await localDbService.repository.initializeDevice(
        'POS-WIN-01',
      );
      expect(existingState.deviceId, 'POS-WIN-01');
    });

    test('3. Master Veritabanı İzolasyonu: Sadece client_local şeması çalışır', () async {
      final tables = localDbService.database.allTables
          .map((t) => t.actualTableName)
          .toList();

      expect(tables, contains('local_products'));
      expect(tables, contains('local_sales'));
      expect(tables, contains('outbox_operations'));
      expect(tables, contains('client_sync_states'));

      expect(tables.contains('users'), isFalse);
      expect(tables.contains('stores'), isFalse);
      expect(tables.contains('processed_operations'), isFalse);
    });

    // =========================================================================
    // TEMEL YAŞAM DÖNGÜSÜ (LIFECYCLE) & KORUMA TESTLERİ
    // =========================================================================

    test('4. Sıralı (Sequential) initialize Çağrılarında Aynı Örnek Dönülür', () async {
      tempDir = Directory.systemTemp.createTempSync('mms_seq_test_');
      final dbPath = p.join(tempDir!.path, 'client_local.db');

      final instance1 = await LocalDatabaseService.initialize(customPath: dbPath);
      final instance2 = await LocalDatabaseService.initialize(customPath: dbPath);

      expect(identical(instance1, instance2), isTrue);
      expect(instance1.databasePath, dbPath);
      expect(instance1.isClosed, isFalse);

      await instance1.close();
    });

    test('5. Close Sonrası Eski Referansın Kullanımı Kontrollü Olarak DatabaseClosedException Üretir', () async {
      tempDir = Directory.systemTemp.createTempSync('mms_closed_ref_');
      final dbPath = p.join(tempDir!.path, 'client_local.db');

      final service = await LocalDatabaseService.initialize(customPath: dbPath);
      await service.close();

      expect(service.isClosed, isTrue);
      expect(service.lifecycleState, LocalDatabaseLifecycleState.closed);

      expect(() => service.getPendingOutboxCount(), throwsA(isA<DatabaseClosedException>()));
      expect(() => service.getLocalSalesCount(), throwsA(isA<DatabaseClosedException>()));
      expect(() => service.getLocalProductsCount(), throwsA(isA<DatabaseClosedException>()));
      expect(() => service.database, throwsA(isA<DatabaseClosedException>()));
      expect(() => service.repository, throwsA(isA<DatabaseClosedException>()));
      expect(() => service.runOperation(() async => 42), throwsA(isA<DatabaseClosedException>()));
    });

    // =========================================================================
    // B-6 TALİMATINDAKİ 12 ZORUNLU SENARYO DOĞRULAMASI
    // =========================================================================

    test('6. Senaryo 1: Initialize sırasında Close — deterministik kapatılır, beklenmedik re-open yapılmaz', () async {
      tempDir = Directory.systemTemp.createTempSync('mms_s1_');
      final dbPath = p.join(tempDir!.path, 'client_local.db');

      final initFuture = LocalDatabaseService.initialize(customPath: dbPath);
      final closeFuture = LocalDatabaseService.closeActive();

      final service = await initFuture;
      await closeFuture;

      expect(service.isClosed, isTrue);
      expect(LocalDatabaseService.currentInstance, isNull);
      expect(LocalDatabaseService.currentLifecycleState, LocalDatabaseLifecycleState.uninitialized);
    });

    test('7. Senaryo 2: Close sırasında Initialize — eski bağlantının kapanması beklenir ve yeni açık instance döner', () async {
      tempDir = Directory.systemTemp.createTempSync('mms_s2_');
      final dbPath = p.join(tempDir!.path, 'client_local.db');

      final service1 = await LocalDatabaseService.initialize(customPath: dbPath);
      expect(service1.isClosed, isFalse);

      final closeFuture = service1.close();
      final initFuture = LocalDatabaseService.initialize(customPath: dbPath);

      await closeFuture;
      final service2 = await initFuture;

      expect(service1.isClosed, isTrue);
      expect(service2.isClosed, isFalse);
      expect(identical(service1, service2), isFalse);
      expect(service2.databasePath, dbPath);
      expect(LocalDatabaseService.currentInstance, service2);

      await service2.close();
    });

    test('8. Senaryo 3: Aynı path ile eşzamanlı Initialize — 5 eşzamanlı çağrı tek instance paylaşır', () async {
      tempDir = Directory.systemTemp.createTempSync('mms_s3_');
      final dbPath = p.join(tempDir!.path, 'shared.db');

      final futures = List.generate(
        5,
        (_) => LocalDatabaseService.initialize(customPath: dbPath),
      );

      final results = await Future.wait(futures);

      expect(results.length, 5);
      final first = results.first;
      for (final instance in results) {
        expect(identical(first, instance), isTrue);
      }

      expect(first.isClosed, isFalse);
      expect(first.lifecycleState, LocalDatabaseLifecycleState.ready);

      await first.close();
    });

    test('9. Senaryo 4: Farklı path ile eşzamanlı Initialize — deterministik geçiş yapılır, her çağrı doğru path alır', () async {
      tempDir = Directory.systemTemp.createTempSync('mms_s4_');
      final pathA = p.join(tempDir!.path, 'dbA.db');
      final pathB = p.join(tempDir!.path, 'dbB.db');

      final futureA = LocalDatabaseService.initialize(customPath: pathA);
      final futureB = LocalDatabaseService.initialize(customPath: pathB);

      final serviceA = await futureA;
      final serviceB = await futureB;

      expect(serviceA.databasePath, pathA);
      expect(serviceB.databasePath, pathB);

      final current = LocalDatabaseService.currentInstance;
      expect(current, isNotNull);
      expect(current!.isClosed, isFalse);

      if (!serviceA.isClosed) await serviceA.close();
      if (!serviceB.isClosed) await serviceB.close();
    });

    test('10. Senaryo 5: Aktif DB işlemi sırasında Close — repository üzerinden çalışan işlem drain ile tamamlanır', () async {
      tempDir = Directory.systemTemp.createTempSync('mms_s5_');
      final dbPath = p.join(tempDir!.path, 'client_local.db');

      final service = await LocalDatabaseService.initialize(customPath: dbPath);

      // Repository üzerinden doğrudan çağrılan işlem otomatik olarak drain mekanizmasına dahil edilir
      final opFuture = service.repository.initializeDevice('POS-ACTIVE-TX');
      final closeFuture = service.close();

      final syncState = await opFuture;
      await closeFuture;

      expect(syncState.deviceId, 'POS-ACTIVE-TX');
      expect(service.isClosed, isTrue);
      expect(service.activeQueryCount, 0);
    });

    test('11. Senaryo 6: Aktif Outbox işlemi sırasında Close — repository outbox sorgusu drain ile tamamlanır', () async {
      tempDir = Directory.systemTemp.createTempSync('mms_s6_');
      final dbPath = p.join(tempDir!.path, 'client_local.db');

      final service = await LocalDatabaseService.initialize(customPath: dbPath);

      await service.repository.initializeDevice('POS-OUTBOX-DRAIN');
      final opFuture = service.repository.getUnsyncedOutboxOperations('POS-OUTBOX-DRAIN');
      final closeFuture = service.close();

      final ops = await opFuture;
      await closeFuture;

      expect(ops, isEmpty);
      expect(service.isClosed, isTrue);
    });

    test('12. Senaryo 7: Drain timeout — operasyon drain süresini aşarsa uyarı loglanır ve zorla kapatmaya geçilir', () async {
      tempDir = Directory.systemTemp.createTempSync('mms_s7_');
      final dbPath = p.join(tempDir!.path, 'client_local.db');

      LocalDatabaseService.drainTimeout = const Duration(milliseconds: 100);

      final service = await LocalDatabaseService.initialize(customPath: dbPath);

      // Drain timeout'u aşacak kadar uzun süren bir operasyon başlat
      final longOp = service.runOperation(() async {
        await Future.delayed(const Duration(milliseconds: 400));
        return 'completed';
      });

      await Future.delayed(const Duration(milliseconds: 10));
      final closeFuture = service.close();

      await closeFuture;
      expect(service.isClosed, isTrue);

      try {
        await longOp;
      } catch (_) {}
    });

    test('13. Senaryo 8: DB close timeout — timeout oluşursa state failed olur ve yeni initialize engellenir', () async {
      tempDir = Directory.systemTemp.createTempSync('mms_s8_');
      final dbPath = p.join(tempDir!.path, 'client_local.db');

      LocalDatabaseService.dbCloseTimeout = const Duration(milliseconds: 20);

      // Kapanış operasyonunu 300ms geciktiren test executor'ı ile timeout tetikle
      final hangingExecutor = _HangingCloseExecutor(
        NativeDatabase.memory(),
        closeDelay: const Duration(milliseconds: 300),
      );
      final service = LocalDatabaseService.forTesting(hangingExecutor);

      await service.close();

      expect(LocalDatabaseService.hasCloseTimedOut, isTrue);
      expect(LocalDatabaseService.currentLifecycleState, LocalDatabaseLifecycleState.failed);

      // Veri bütünlüğünü korumak adına yeni initialize çağrısı engellenmelidir
      expect(
        () => LocalDatabaseService.initialize(customPath: dbPath),
        throwsA(isA<StateError>()),
      );
    });

    test('14. Senaryo 9: Close sonrasında Initialize — kapatılan DB temizce yeniden başlatılabilir', () async {
      tempDir = Directory.systemTemp.createTempSync('mms_s9_');
      final dbPath = p.join(tempDir!.path, 'client_local.db');

      final s1 = await LocalDatabaseService.initialize(customPath: dbPath);
      await s1.repository.initializeDevice('POS-REINIT');
      await s1.close();

      expect(s1.isClosed, isTrue);
      expect(LocalDatabaseService.currentInstance, isNull);

      final s2 = await LocalDatabaseService.initialize(customPath: dbPath);
      expect(s2.isClosed, isFalse);
      expect(identical(s1, s2), isFalse);

      final state = await s2.repository.getSyncState('POS-REINIT');
      expect(state, isNotNull);
      expect(state!.deviceId, 'POS-REINIT');

      await s2.close();
    });

    test('15. Senaryo 10: Failed initialize sonrası retry — geçersiz path hata fırlatır, sonraki geçerli çağrı başarılı olur', () async {
      tempDir = Directory.systemTemp.createTempSync('mms_s10_');
      final validPath = p.join(tempDir!.path, 'valid.db');
      final invalidPath = 'Z:\\non_existent_drive_999\\invalid??path\\db.db';

      await expectLater(
        LocalDatabaseService.initialize(customPath: invalidPath),
        throwsA(isA<FileSystemException>()),
      );

      expect(LocalDatabaseService.currentInstance, isNull);
      expect(LocalDatabaseService.currentLifecycleState, LocalDatabaseLifecycleState.uninitialized);

      final service = await LocalDatabaseService.initialize(customPath: validPath);
      expect(service.isClosed, isFalse);
      expect(service.databasePath, validPath);

      await service.close();
    });

    test('16. Senaryo 11: Eşzamanlı Close — birden fazla close çağrısı tek Future paylaşır ve idempotenttir', () async {
      tempDir = Directory.systemTemp.createTempSync('mms_s11_');
      final dbPath = p.join(tempDir!.path, 'client_local.db');

      final service = await LocalDatabaseService.initialize(customPath: dbPath);

      final c1 = service.close();
      final c2 = service.close();
      final c3 = service.close();

      await expectLater(Future.wait([c1, c2, c3]), completes);
      expect(service.isClosed, isTrue);
      expect(LocalDatabaseService.currentInstance, isNull);

      await expectLater(service.close(), completes);
    });

    test('17. Senaryo 12: Test timeout ayarlarının resetlenmesi — resetForTesting tüm timeout ve bayrakları varsayılana döndürür', () async {
      LocalDatabaseService.drainTimeout = const Duration(milliseconds: 42);
      LocalDatabaseService.dbCloseTimeout = const Duration(milliseconds: 99);

      LocalDatabaseService.resetForTesting();

      expect(LocalDatabaseService.drainTimeout, LocalDatabaseService.defaultDrainTimeout);
      expect(LocalDatabaseService.dbCloseTimeout, LocalDatabaseService.defaultDbCloseTimeout);
      expect(LocalDatabaseService.hasCloseTimedOut, isFalse);
      expect(LocalDatabaseService.currentInstance, isNull);
      expect(LocalDatabaseService.currentLifecycleState, LocalDatabaseLifecycleState.uninitialized);
    });
  });
}
