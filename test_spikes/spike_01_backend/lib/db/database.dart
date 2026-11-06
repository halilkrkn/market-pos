import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

part 'database.g.dart';

class Products extends Table {
  TextColumn get id => text()();
  TextColumn get barcode => text()();
  TextColumn get name => text()();
  IntColumn get price => integer()(); // kuruş bazlı tamsayı (1000 = 10.00 TL)
  TextColumn get priceVersionId => text().withDefault(const Constant('pv_init'))(); // S5A-3: Fiyat sürüm kimliği
  IntColumn get stock => integer()(); // stock_unit bazlı tamsayı (scale=1000)
  TextColumn get stockUnit => text().withDefault(const Constant('adet'))(); // 'adet', 'kg', 'g', 'l', 'ml'
  TextColumn get pricingUnit => text().withDefault(const Constant('adet'))(); // 'adet', 'kg', 'l', 'koli'
  IntColumn get conversionFactorNumerator => integer().withDefault(const Constant(1))(); // 1 pricing_unit = (num / den) stock_unit
  IntColumn get conversionFactorDenominator => integer().withDefault(const Constant(1))(); // Payda (> 0)
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Sales extends Table {
  TextColumn get id => text()();
  TextColumn get deviceId => text()();
  IntColumn get clientSeq => integer()();
  IntColumn get totalAmount => integer()();
  TextColumn get paymentMethod => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class SaleItems extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text().references(Sales, #id)();
  TextColumn get productId => text().references(Products, #id)();
  IntColumn get quantity => integer()();
  IntColumn get unitPrice => integer()();
  IntColumn get totalPrice => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class StockMovements extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text().references(Products, #id)();
  IntColumn get quantity => integer()(); // negatif (satış) veya pozitif (giriş) - stock_unit bazlı
  TextColumn get unit => text().withDefault(const Constant('adet'))(); // Hareket birimi ('adet', 'kg', 'g', 'l')
  TextColumn get movementType => text()(); // 'SATIS', 'GIRIS', 'DUZELTME'
  TextColumn get referenceId => text()(); // sale_id vb.
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class ProductPriceHistories extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text().references(Products, #id)();
  IntColumn get price => integer()(); // kuruş
  DateTimeColumn get validFrom => dateTime()();
  DateTimeColumn get validUntil => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// S5A-3: Ürün senkronizasyon oturumları ve iki aşamalı ACK kayıtları
class ProductSyncSessions extends Table {
  TextColumn get id => text()(); // sync_session_id
  TextColumn get deviceId => text()();
  IntColumn get productCount => integer()();
  DateTimeColumn get syncedAt => dateTime()();
  BoolColumn get isAcknowledged => boolean().withDefault(const Constant(false))();
  DateTimeColumn get acknowledgedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class ProcessedOperations extends Table {
  TextColumn get operationId => text()();
  TextColumn get deviceId => text()();
  TextColumn get idempotencyKey => text().unique()();
  TextColumn get resultPayload => text()();
  DateTimeColumn get processedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {operationId};
}

class Devices extends Table {
  TextColumn get deviceId => text()();
  TextColumn get name => text()();
  // S-2: Açık metin token kaldırıldı; yerine SHA-256 hash ve tuz (salt) eklendi
  TextColumn get tokenHash => text()();
  TextColumn get salt => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isConfirmed => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastUsedAt => dateTime().nullable()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  DateTimeColumn get lastProductSyncAt => dateTime().nullable()(); // S5A-3: Cihazın en son başarılı ürün/fiyat senkronizasyon zamanı
  TextColumn get role => text().withDefault(const Constant('CASHIER'))();

  @override
  Set<Column> get primaryKey => {deviceId};
}

/// S-2: Token yenileme ve iptal hareketlerinin audit kaydını tutan defter tablosu
class DeviceAuditLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get deviceId => text()();
  TextColumn get action => text()(); // 'REGISTER', 'RENEW', 'REVOKE'
  TextColumn get details => text().nullable()(); // Asla açık token içermez
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// S5A-2: SQLite PRAGMA wal_checkpoint sonucunu temsil eden model
class CheckpointResult {
  final int busy;
  final int log;
  final int checkpointed;
  final bool isSuccess;

  const CheckpointResult({
    required this.busy,
    required this.log,
    required this.checkpointed,
  }) : isSuccess = (busy == 0);

  @override
  String toString() => 'CheckpointResult(busy: $busy, log: $log, checkpointed: $checkpointed, isSuccess: $isSuccess)';
}

@DriftDatabase(tables: [Products, Sales, SaleItems, StockMovements, ProcessedOperations, Devices, DeviceAuditLogs, ProductPriceHistories, ProductSyncSessions])
class SpikeDatabase extends _$SpikeDatabase {
  SpikeDatabase(File file) : super(_openConnection(file));

  SpikeDatabase.forTesting(QueryExecutor e) : super(e);

  static QueryExecutor _openConnection(File file) {
    // S5A-4: Çökme / elektrik kesintisi sonrası yarım kalan bir restore işlemi varsa kurtar
    DatabaseBackupEngine.recoverPendingRestoreSync(file);

    return NativeDatabase.createInBackground(
      file,
      setup: (rawDb) {
        rawDb.execute('PRAGMA journal_mode = WAL;');
        rawDb.execute('PRAGMA synchronous = FULL;');
        rawDb.execute('PRAGMA busy_timeout = 5000;');
        rawDb.execute('PRAGMA foreign_keys = ON;');
      },
    );
  }

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON;');
          await customStatement('PRAGMA synchronous = FULL;');
        },
      );

  /// S5A-2: PRAGMA synchronous değerini döner (0 = OFF, 1 = NORMAL, 2 = FULL, 3 = EXTRA)
  Future<int> getSynchronousPragma() async {
    final result = await customSelect('PRAGMA synchronous;').getSingle();
    final val = result.data.values.first;
    if (val is int) return val;
    return int.parse(val.toString());
  }

  /// S5A-2: PRAGMA journal_mode değerini döner (beklenen: 'wal')
  Future<String> getJournalModePragma() async {
    final result = await customSelect('PRAGMA journal_mode;').getSingle();
    final val = result.data.values.first;
    return val.toString().toLowerCase();
  }

  /// S5A-2: PRAGMA wal_checkpoint çalıştırır ve busy, log, checkpointed çıktılarını inceler.
  Future<CheckpointResult> checkpointWal({String mode = 'TRUNCATE'}) async {
    final rows = await customSelect('PRAGMA wal_checkpoint($mode);').get();
    if (rows.isEmpty) {
      return const CheckpointResult(busy: 1, log: -1, checkpointed: -1);
    }
    final row = rows.first.data;
    final busyVal = row['busy'] ?? row.values.elementAt(0);
    final logVal = row['log'] ?? row.values.elementAt(1);
    final cpVal = row['checkpointed'] ?? row.values.elementAt(2);

    final busy = busyVal is int ? busyVal : int.tryParse(busyVal.toString()) ?? 1;
    final log = logVal is int ? logVal : int.tryParse(logVal.toString()) ?? 0;
    final checkpointed = cpVal is int ? cpVal : int.tryParse(cpVal.toString()) ?? 0;

    return CheckpointResult(busy: busy, log: log, checkpointed: checkpointed);
  }
}
