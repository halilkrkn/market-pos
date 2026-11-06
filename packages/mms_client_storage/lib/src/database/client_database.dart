import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../backup/database_backup_engine.dart';

part 'client_database.g.dart';

/// 1. Yerel Ürünler Tablosu (Cache)
class LocalProducts extends Table {
  TextColumn get id => text()();
  TextColumn get barcode => text().nullable()(); // Birincil barkod önbelleği (Tek doğruluk kaynağı: LocalProductBarcodes)
  TextColumn get name => text()();
  IntColumn get price => integer()(); // Kuruş bazlı birim satış fiyatı (Ör: 200 TL/kg = 20000 kuruş) - Floating point YASAK
  TextColumn get priceVersionId => text().withDefault(const Constant('pv_init'))(); // S5A-3: Fiyat sürüm kimliği
  IntColumn get stock => integer()(); // Milli-birim bazlı stok miktarı (1000 = 1 adet/kg/L, 500 = 0.5 kg)
  TextColumn get stockUnit => text().withDefault(const Constant('adet'))(); // 'adet', 'kg', 'g', 'l', 'ml', 'paket', 'kutu'
  TextColumn get pricingUnit => text().withDefault(const Constant('adet'))(); // Fiyatlandırma birimi
  IntColumn get conversionFactorNumerator => integer().withDefault(const Constant(1))(); // 1 pricing_unit = (num / den) stock_unit
  IntColumn get conversionFactorDenominator => integer().withDefault(const Constant(1))(); // Payda (> 0)
  IntColumn get vatRate => integer().withDefault(const Constant(20))(); // KDV oranı (%)
  BoolColumn get isActive => boolean().withDefault(const Constant(true))(); // Pasif ürün satışa sunulamaz
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 2. Yerel Ürün Barkodları Tablosu (Barkod Tek Doğruluk Kaynağı - SSOT)
///
/// Kural: Bir barkod yalnızca BİR ürüne atanabilir. Tenant genelinde mutlak benzersizlik!
/// 0, 1 veya birden fazla barkod bir ürüne bağlanabilir.
class LocalProductBarcodes extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text().references(LocalProducts, #id)();
  TextColumn get barcode => text()();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(true))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {barcode} // Barkod tekilliği güvencesi: 1 barkod -> yalnızca 1 ürün
      ];
}

/// 3. Yerel Satışlar Tablosu
class LocalSales extends Table {
  TextColumn get id => text()();
  TextColumn get deviceId => text()();
  IntColumn get clientSeq => integer()();
  IntColumn get totalAmount => integer()(); // Kuruş bazlı tamsayı
  TextColumn get paymentMethod => text()(); // 'CASH', 'CREDIT_CARD', etc.
  TextColumn get status => text().withDefault(const Constant('COMPLETED'))(); // 'COMPLETED', 'CANCELLED'
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {deviceId, clientSeq}
      ];
}

/// 4. Yerel Satış Kalemleri Tablosu
class LocalSaleItems extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text().references(LocalSales, #id)();
  TextColumn get productId => text().references(LocalProducts, #id)();
  TextColumn get productNameSnapshot => text()(); // Satış anındaki ürün adı snapshot'ı
  TextColumn get unitSnapshot => text().withDefault(const Constant('adet'))(); // Satış anındaki birim snapshot'ı ('kg', 'adet', vb.)
  TextColumn get priceVersionId => text().withDefault(const Constant('pv_init'))(); // S5A-3: Satış anındaki fiyat sürüm kimliği snapshot'ı
  IntColumn get unitPrice => integer()(); // Satış anındaki birim fiyat snapshot'ı (kuruş)
  IntColumn get quantity => integer()(); // Milli-birim bazlı miktar (500 = 0.5 kg, 1250 = 1.25 L, 1000 = 1 adet)
  IntColumn get totalPrice => integer()(); // ((unitPrice * quantity) + 500) ~/ 1000 (kuruş)

  @override
  Set<Column> get primaryKey => {id};
}

/// 5. Yerel Stok Hareketleri Tablosu
class LocalStockMovements extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text().references(LocalProducts, #id)();
  IntColumn get quantity => integer()(); // Milli-birim bazlı miktar: Negatif (satış) veya Pozitif (giriş)
  TextColumn get unit => text().withDefault(const Constant('adet'))(); // Hareket birimi ('adet', 'kg', 'l', vb.)
  TextColumn get movementType => text()(); // 'SATIS', 'GIRIS', 'DUZELTME'
  TextColumn get referenceId => text()(); // sale_id vb.
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 6. Outbox Senkronizasyon Kuyruğu Tablosu
class OutboxOperations extends Table {
  TextColumn get operationId => text()();
  TextColumn get deviceId => text()();
  IntColumn get clientSeq => integer()();
  TextColumn get operationType => text()(); // 'SALE_CREATE'
  TextColumn get payload => text()(); // Değiştirilemez JSON dizesi
  TextColumn get payloadHash => text()(); // SHA-256 hash
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get status => text().withDefault(const Constant('PENDING'))(); // 'PENDING', 'IN_PROGRESS', 'SYNCED', 'RETRY', 'FAILED_PERMANENT'
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextRetryAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get acknowledgedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {operationId};

  @override
  List<Set<Column>> get uniqueKeys => [
        {deviceId, clientSeq}
      ];
}

/// 7. İstemci Senkronizasyon Durumu Tablosu (Cihaz kimliği ve monotonic sayaç)
class ClientSyncStates extends Table {
  TextColumn get deviceId => text()();
  IntColumn get currentClientSeq => integer().withDefault(const Constant(0))();
  IntColumn get lastSyncedSeq => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastProductSyncAt => dateTime().nullable()();
  TextColumn get pendingSyncSessionId => text().nullable()(); // S5A-3: Henüz Hub tarafından ACK onayı alınmamış sync_session_id
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {deviceId};
}

@DriftDatabase(tables: [
  LocalProducts,
  LocalProductBarcodes,
  LocalSales,
  LocalSaleItems,
  LocalStockMovements,
  OutboxOperations,
  ClientSyncStates,
])
class ClientDatabase extends _$ClientDatabase {
  ClientDatabase(File file) : super(_openConnection(file));

  ClientDatabase.forTesting(QueryExecutor e) : super(e);

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
        onCreate: (m) async {
          await m.createAll();
          // Hızlı FIFO sorgulaması için outbox indeksleri
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_outbox_status_seq ON outbox_operations (status, client_seq);',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_sales_device_seq ON local_sales (device_id, client_seq);',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_barcodes_product ON local_product_barcodes (product_id, is_active);',
          );
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // Şema yükseltme adımları
          }
        },
      );
}
