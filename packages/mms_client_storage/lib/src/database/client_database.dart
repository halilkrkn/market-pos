import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../backup/database_backup_engine.dart';

part 'client_database.g.dart';

/// 0. Yerel Kategoriler Tablosu (Hiyerarşik: Ana Kategori -> Alt Kategori)
class LocalCategories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get parentId => text().nullable().references(LocalCategories, #id)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 1. Yerel Ürünler Tablosu (Cache)
class LocalProducts extends Table {
  TextColumn get id => text()();
  TextColumn get barcode => text().nullable()(); // Birincil barkod önbelleği (Tek doğruluk kaynağı: LocalProductBarcodes)
  TextColumn get name => text()();
  TextColumn get categoryId => text().nullable().references(LocalCategories, #id)(); // Kategori ilişkisi
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
  TextColumn get paymentMethod => text()(); // Kanonik sözleşme: 'CASH', 'CARD'
  TextColumn get status => text().withDefault(const Constant('COMPLETED'))(); // 'COMPLETED', 'CANCELLED', 'REFUNDED'
  TextColumn get cancelReason => text().nullable()(); // İptal gerekçesi (BR-POS-08)
  DateTimeColumn get cancelledAt => dateTime().nullable()(); // İptal zamanı
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
  TextColumn get movementType => text()(); // 'SATIS', 'SATIS_IPTALI', 'MUSTERI_IADESI', 'FIRE_KAYIP', 'GIRIS', 'BASLANGIC_STOK', 'DUZELTME'
  TextColumn get referenceId => text()(); // sale_id vb.
  IntColumn get purchasePrice => integer().nullable()(); // v4: Stok birimi başına alış fiyatı (kuruş), yalnızca giriş hareketlerinde
  TextColumn get note => text().nullable()(); // v4: Stok girişi açıklaması (irsaliye no vb.)
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 6. Yerel İadeler Tablosu (Kısmi İade Kayıtları — BR-POS-09, BR-POS-10)
class LocalRefunds extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text().references(LocalSales, #id)();
  TextColumn get deviceId => text()();
  IntColumn get clientSeq => integer()();
  IntColumn get totalRefundAmount => integer()(); // Kuruş bazlı tamsayı
  TextColumn get paymentMethod => text()(); // Kanonik sözleşme: 'CASH', 'CARD'
  TextColumn get reason => text()(); // Zorunlu iade gerekçesi
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {deviceId, clientSeq}
      ];
}

/// 7. Yerel İade Kalemleri Tablosu
class LocalRefundItems extends Table {
  TextColumn get id => text()();
  TextColumn get refundId => text().references(LocalRefunds, #id)();
  TextColumn get saleItemId => text().references(LocalSaleItems, #id)();
  TextColumn get productId => text().references(LocalProducts, #id)();
  IntColumn get quantity => integer()(); // Milli-birim bazlı miktar (örn: 1000 = 1 adet/kg)
  IntColumn get unitPrice => integer()(); // Satış anındaki birim fiyat snapshot'ı (kuruş)
  IntColumn get refundAmount => integer()(); // ((unitPrice * quantity) + 500) ~/ 1000 (kuruş)
  TextColumn get productCondition => text().withDefault(const Constant('SELLABLE'))(); // 'SELLABLE', 'DAMAGED'
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 8. Yerel Fiyat Değişiklik Geçmişi Tablosu (BR-PROD-13)
class LocalPriceHistory extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text().references(LocalProducts, #id)();
  IntColumn get oldPrice => integer()(); // Kuruş
  IntColumn get newPrice => integer()(); // Kuruş
  TextColumn get priceVersionId => text()(); // S5A-3: Fiyat sürüm kimliği (örn: pv_...)
  TextColumn get source => text().withDefault(const Constant('MANUAL_UI'))(); // 'MANUAL_UI', 'EXCEL_IMPORT', 'SYNC'
  TextColumn get reason => text().nullable()();
  DateTimeColumn get changedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 9. Outbox Senkronizasyon Kuyruğu Tablosu
class OutboxOperations extends Table {
  TextColumn get operationId => text()();
  TextColumn get deviceId => text()();
  IntColumn get clientSeq => integer()();
  TextColumn get operationType => text()(); // 'SALE_CREATE', 'SALE_CANCEL', 'SALE_REFUND', 'PRODUCT_UPSERT', 'CATEGORY_UPSERT'
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

/// 10. İstemci Senkronizasyon Durumu Tablosu (Cihaz kimliği ve monotonic sayaç)
class ClientSyncStates extends Table {
  TextColumn get deviceId => text()();
  IntColumn get currentClientSeq => integer().withDefault(const Constant(0))();
  IntColumn get lastSyncedSeq => integer().withDefault(const Constant(0))();
  IntColumn get lastServerSaleSeq => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastProductSyncAt => dateTime().nullable()();
  DateTimeColumn get lastSalesSyncAt => dateTime().nullable()();
  TextColumn get pendingSyncSessionId => text().nullable()(); // S5A-3: Henüz Hub tarafından ACK onayı alınmamış sync_session_id
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {deviceId};
}

/// İstemciye özel kalıcı ayarlar (örn. son doğrulanan/keşfedilen Hub bağlantısı)
class LocalClientSettings extends Table {
  TextColumn get settingKey => text()();
  TextColumn get hubUrl => text().nullable()();
  TextColumn get hubId => text().nullable()();
  TextColumn get source => text().nullable()();
  DateTimeColumn get lastVerifiedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {settingKey};
}

@DriftDatabase(tables: [
  LocalCategories,
  LocalProducts,
  LocalProductBarcodes,
  LocalSales,
  LocalSaleItems,
  LocalStockMovements,
  LocalRefunds,
  LocalRefundItems,
  LocalPriceHistory,
  OutboxOperations,
  ClientSyncStates,
  LocalClientSettings,
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
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON;');
          await customStatement('PRAGMA synchronous = FULL;');
          await customStatement(
            'CREATE TABLE IF NOT EXISTS local_hub_synced_products ('
            '  product_id TEXT PRIMARY KEY,'
            '  synced_at TEXT NOT NULL'
            ');',
          );
          final syncStateColumns = await customSelect(
            "PRAGMA table_info('client_sync_states');",
          ).get();
          final syncColNames = syncStateColumns.map((row) => row.data['name'] as String).toSet();
          if (!syncColNames.contains('last_server_sale_seq')) {
            await customStatement(
              'ALTER TABLE client_sync_states ADD COLUMN last_server_sale_seq INTEGER NOT NULL DEFAULT 0;',
            );
          }
          if (!syncColNames.contains('last_sales_sync_at')) {
            await customStatement(
              'ALTER TABLE client_sync_states ADD COLUMN last_sales_sync_at INTEGER;',
            );
          }
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
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_sales_created_at ON local_sales (created_at DESC);',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_refunds_sale_id ON local_refunds (sale_id);',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_price_history_product ON local_price_history (product_id, changed_at DESC);',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_stock_movements_product ON local_stock_movements (product_id, created_at DESC);',
          );
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(localCategories);
            await m.addColumn(localProducts, localProducts.categoryId);
            await m.addColumn(localSales, localSales.cancelReason);
            await m.addColumn(localSales, localSales.cancelledAt);
            await m.createTable(localRefunds);
            await m.createTable(localRefundItems);
            await m.createTable(localPriceHistory);
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_sales_created_at ON local_sales (created_at DESC);',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_refunds_sale_id ON local_refunds (sale_id);',
            );
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_price_history_product ON local_price_history (product_id, changed_at DESC);',
            );
          }
          if (from < 3) {
            await m.createTable(localClientSettings);
          }
          if (from < 4) {
            // Owner onaylı (21 Kasım 2026) additive migration: veri silmez, yalnızca nullable sütun ekler.
            // Savunmacı: kısmen onarılmış/yeniden oluşturulmuş DB'lerde sütun zaten varsa tekrar eklenmez.
            final movementCols = (await customSelect(
              "PRAGMA table_info('local_stock_movements');",
            ).get())
                .map((row) => row.data['name'] as String)
                .toSet();
            if (!movementCols.contains('purchase_price')) {
              await m.addColumn(localStockMovements, localStockMovements.purchasePrice);
            }
            if (!movementCols.contains('note')) {
              await m.addColumn(localStockMovements, localStockMovements.note);
            }
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_stock_movements_product ON local_stock_movements (product_id, created_at DESC);',
            );
          }
        },
      );
}
