import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../sync/canonical_payload_hasher.dart';
import '../sync/device_sequence_inspector.dart';

part 'database.g.dart';

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get parentId => text().nullable().references(Categories, #id)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Products extends Table {
  TextColumn get id => text()();
  TextColumn get barcode => text()();
  TextColumn get name => text()();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  IntColumn get price => integer()(); // kuruş bazlı tamsayı (1000 = 10.00 TL)
  TextColumn get priceVersionId => text().withDefault(const Constant('pv_init'))(); // S5A-3: Fiyat sürüm kimliği
  IntColumn get stock => integer()(); // stock_unit bazlı tamsayı (scale=1000)
  TextColumn get stockUnit => text().withDefault(const Constant('adet'))(); // 'adet', 'kg', 'g', 'l', 'ml'
  TextColumn get pricingUnit => text().withDefault(const Constant('adet'))(); // 'adet', 'kg', 'l', 'koli'
  IntColumn get conversionFactorNumerator => integer().withDefault(const Constant(1))(); // 1 pricing_unit = (num / den) stock_unit
  IntColumn get conversionFactorDenominator => integer().withDefault(const Constant(1))(); // Payda (> 0)
  IntColumn get vatRate => integer().withDefault(const Constant(20))(); // KDV oranı (%)
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [{barcode}];
}

/// v4 (GAP-A01): Ürün başına çoklu/ikincil barkod yaşam döngüsü tablosu.
/// Bir barkod Hub genelinde yalnızca tek bir ürüne ait olabilir (`unique`).
class ProductBarcodes extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get barcode => text().unique()();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Sales extends Table {
  TextColumn get id => text()();
  TextColumn get deviceId => text()();
  IntColumn get clientSeq => integer()();
  IntColumn get totalAmount => integer()();
  TextColumn get paymentMethod => text()();
  IntColumn get serverSeq => integer().nullable()(); // Monotonik artan Hub satış sıra numarası (Downlink Cursor)
  TextColumn get status => text().withDefault(const Constant('COMPLETED'))(); // 'COMPLETED', 'CANCELLED', 'REFUNDED'
  TextColumn get cancelReason => text().nullable()(); // İptal gerekçesi
  DateTimeColumn get cancelledAt => dateTime().nullable()(); // İptal zamanı
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

class Refunds extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text().references(Sales, #id)();
  TextColumn get deviceId => text()();
  IntColumn get clientSeq => integer()();
  IntColumn get totalRefundAmount => integer()();
  TextColumn get paymentMethod => text()();
  TextColumn get reason => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class RefundItems extends Table {
  TextColumn get id => text()();
  TextColumn get refundId => text().references(Refunds, #id)();
  TextColumn get saleItemId => text().nullable()();
  TextColumn get productId => text().references(Products, #id)();
  IntColumn get quantity => integer()();
  IntColumn get unitPrice => integer()();
  IntColumn get refundAmount => integer()();
  TextColumn get productCondition => text().withDefault(const Constant('SELLABLE'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

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
  IntColumn get purchasePrice => integer().nullable()(); // v3: STOCK_RECEIPT alış fiyatı (kuruş / stok birimi)
  TextColumn get note => text().nullable()(); // v3: Stok girişi açıklaması
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
  IntColumn get clientSeq => integer().nullable()();
  TextColumn get operationType => text().nullable()();
  TextColumn get requestHash => text().nullable()();
  TextColumn get hashVersion => text().nullable()();
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
  IntColumn get lastCommittedClientSeq => integer().withDefault(const Constant(0))(); // BK-02.1: Kesintisiz cihaz HWM
  IntColumn get maxSeenClientSeq => integer().withDefault(const Constant(0))(); // BK-02.1: Görülen en yüksek seq (boşluk olsa bile)
  DateTimeColumn get lastCommittedAt => dateTime().nullable()(); // BK-02.1: Son başarılı seq commit zamanı
  TextColumn get role => text().withDefault(const Constant('CASHIER'))();

  @override
  Set<Column> get primaryKey => {deviceId};
}

/// BK-02.1: Pilot tek-tenant / tek-store Hub kimlik sabitlerini saklayan metadata tablosu
class HubMetadata extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {key};
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

@DriftDatabase(tables: [Categories, Products, ProductBarcodes, Sales, SaleItems, StockMovements, ProcessedOperations, Devices, DeviceAuditLogs, ProductPriceHistories, ProductSyncSessions, Refunds, RefundItems, HubMetadata])
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
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _ensureLegacySalesAndRefundTables();
          await _upgradeV1ToV2();
          await _ensureV4ProductBarcodesTable();
          await _ensureV5CategoriesAndVatColumns();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await _ensureLegacySalesAndRefundTables();
            await _upgradeV1ToV2();
          }
          if (from < 3) {
            await _ensureV3StockMovementColumns();
          }
          if (from < 4) {
            await _ensureV4ProductBarcodesTable();
          }
          if (from < 5) {
            await m.createTable(categories);
            await m.addColumn(products, products.categoryId);
            await m.addColumn(products, products.vatRate);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON;');
          await customStatement('PRAGMA synchronous = FULL;');

          // Güvenli Barkod Benzersizliği İndeksi:
          // Migration öncesinde mükerrer barkod kontrolü yap
          final dups = await customSelect(
            'SELECT barcode, count(*) as cnt FROM products GROUP BY barcode HAVING cnt > 1;',
          ).get();
          if (dups.isNotEmpty) {
            final barcodes = dups.map((d) => '${d.data["barcode"]} (${d.data["cnt"]})').join(', ');
            throw StateError(
              'Hub Veritabanı Migration Hatası: Mükerrer barkod(lar) tespit edildi: $barcodes. '
              'Benzersizlik indeksi oluşturulamaz, veritabanı açılışı durduruldu.',
            );
          }
          await customStatement('CREATE UNIQUE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode);');

          await _ensureLegacySalesAndRefundTables();
          await _ensureV2SchemaAndIndexes();
          await _ensureV3StockMovementColumns();
          await _ensureV4ProductBarcodesTable();
          await _ensureV5CategoriesAndVatColumns();
        },
      );

  /// Hub v4 -> v5 (MMS-001): Kategoriler ve ürün KDV/kategori sütunları için
  /// idempotent güvence (restore edilen eski yedeklerde de güvenli çalışır).
  Future<void> _ensureV5CategoriesAndVatColumns() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS categories (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        parent_id TEXT REFERENCES categories(id),
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      );
    ''');
    final prodCols = await customSelect("PRAGMA table_info('products');").get();
    final prodColNames = prodCols.map((c) => c.data['name'].toString()).toSet();
    if (!prodColNames.contains('category_id')) {
      await customStatement(
        'ALTER TABLE products ADD COLUMN category_id TEXT REFERENCES categories(id);',
      );
    }
    if (!prodColNames.contains('vat_rate')) {
      await customStatement(
        'ALTER TABLE products ADD COLUMN vat_rate INTEGER NOT NULL DEFAULT 20;',
      );
    }
  }

  /// Hub v3 -> v4 (GAP-A01): Çoklu/ikincil barkodlar için additive, veri koruyucu
  /// migration. Mevcut `products.barcode` değerlerini kaybetmeden `product_barcodes`
  /// tablosuna backfill eder.
  Future<void> _ensureV4ProductBarcodesTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS product_barcodes (
        id TEXT NOT NULL PRIMARY KEY,
        product_id TEXT NOT NULL REFERENCES products(id),
        barcode TEXT NOT NULL UNIQUE,
        is_primary INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      );
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_product_barcodes_product ON product_barcodes(product_id, is_active);',
    );
    await customStatement(
      'INSERT OR IGNORE INTO product_barcodes (id, product_id, barcode, is_primary, is_active, created_at) '
      "SELECT 'bc_' || id || '_primary', id, TRIM(barcode), 1, 1, COALESCE(updated_at, strftime('%s', 'now')) "
      "FROM products WHERE barcode IS NOT NULL AND TRIM(barcode) != '';",
    );
  }

  /// Hub v2 -> v3 (Owner onayı 21 Kasım 2026): STOCK_RECEIPT için additive, veri koruyucu
  /// sütunlar. DROP/RECREATE yapmaz; restore edilen eski yedeklerde de idempotent çalışır.
  Future<void> _ensureV3StockMovementColumns() async {
    final cols = await customSelect("PRAGMA table_info('stock_movements');").get();
    final names = cols.map((c) => c.data['name'].toString()).toSet();
    if (!names.contains('purchase_price')) {
      await customStatement('ALTER TABLE stock_movements ADD COLUMN purchase_price INTEGER;');
    }
    if (!names.contains('note')) {
      await customStatement('ALTER TABLE stock_movements ADD COLUMN note TEXT;');
    }
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_stock_movements_product ON stock_movements(product_id, created_at);',
    );
  }

  Future<void> _ensureLegacySalesAndRefundTables() async {
    // Sales Downlink şema sütunları ve indeksleri
    final salesCols = await customSelect("PRAGMA table_info('sales');").get();
    final salesColNames = salesCols.map((c) => c.data['name'].toString()).toSet();
    if (!salesColNames.contains('server_seq')) {
      await customStatement('ALTER TABLE sales ADD COLUMN server_seq INTEGER;');
    }
    if (!salesColNames.contains('status')) {
      await customStatement("ALTER TABLE sales ADD COLUMN status TEXT NOT NULL DEFAULT 'COMPLETED';");
    }
    if (!salesColNames.contains('cancel_reason')) {
      await customStatement('ALTER TABLE sales ADD COLUMN cancel_reason TEXT;');
    }
    if (!salesColNames.contains('cancelled_at')) {
      await customStatement('ALTER TABLE sales ADD COLUMN cancelled_at INTEGER;');
    }
    await customStatement('UPDATE sales SET server_seq = rowid WHERE server_seq IS NULL OR server_seq = 0;');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_sales_server_seq ON sales(server_seq);');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_sales_device_client_seq ON sales(device_id, client_seq);');

    // Refunds ve RefundItems tabloları
    await customStatement('''
      CREATE TABLE IF NOT EXISTS refunds (
        id TEXT PRIMARY KEY,
        sale_id TEXT NOT NULL REFERENCES sales(id),
        device_id TEXT NOT NULL,
        client_seq INTEGER NOT NULL,
        total_refund_amount INTEGER NOT NULL,
        payment_method TEXT NOT NULL,
        reason TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS refund_items (
        id TEXT PRIMARY KEY,
        refund_id TEXT NOT NULL REFERENCES refunds(id),
        sale_item_id TEXT,
        product_id TEXT NOT NULL REFERENCES products(id),
        quantity INTEGER NOT NULL,
        unit_price INTEGER NOT NULL,
        refund_amount INTEGER NOT NULL,
        product_condition TEXT NOT NULL DEFAULT 'SELLABLE',
        created_at INTEGER NOT NULL
      );
    ''');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_refunds_sale_id ON refunds(sale_id);');
  }

  Future<void> _ensureV2SchemaAndIndexes() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS hub_metadata (
        key TEXT NOT NULL PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      );
    ''');

    final procCols = await customSelect("PRAGMA table_info('processed_operations');").get();
    final procColNames = procCols.map((c) => c.data['name'].toString()).toSet();
    if (!procColNames.contains('client_seq')) {
      await customStatement('ALTER TABLE processed_operations ADD COLUMN client_seq INTEGER;');
    }
    if (!procColNames.contains('operation_type')) {
      await customStatement('ALTER TABLE processed_operations ADD COLUMN operation_type TEXT;');
    }
    if (!procColNames.contains('request_hash')) {
      await customStatement('ALTER TABLE processed_operations ADD COLUMN request_hash TEXT;');
    }
    if (!procColNames.contains('hash_version')) {
      await customStatement('ALTER TABLE processed_operations ADD COLUMN hash_version TEXT;');
    }

    final devCols = await customSelect("PRAGMA table_info('devices');").get();
    final devColNames = devCols.map((c) => c.data['name'].toString()).toSet();
    if (!devColNames.contains('last_committed_client_seq')) {
      await customStatement('ALTER TABLE devices ADD COLUMN last_committed_client_seq INTEGER NOT NULL DEFAULT 0;');
    }
    if (!devColNames.contains('max_seen_client_seq')) {
      await customStatement('ALTER TABLE devices ADD COLUMN max_seen_client_seq INTEGER NOT NULL DEFAULT 0;');
    }
    if (!devColNames.contains('last_committed_at')) {
      await customStatement('ALTER TABLE devices ADD COLUMN last_committed_at INTEGER;');
    }

    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_processed_ops_device_seq '
      'ON processed_operations(device_id, client_seq) '
      'WHERE client_seq IS NOT NULL;',
    );
  }

  /// BK-02.1: Hub DB v1 -> v2 Additive ve Veri Koruyucu Migration.
  ///
  /// - DROP / RECREATE yapmaz, mevcut kayıtları silmez.
  /// - Eksik hash bilgisi için tahmin üretmez (`request_hash` ve `hash_version` NULL kalır).
  /// - Hata durumunda gizlemez, exception fırlatarak migration transaction'ını geri alır.
  Future<void> _upgradeV1ToV2() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS hub_metadata (
        key TEXT NOT NULL PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      );
    ''');

    final procCols = await customSelect("PRAGMA table_info('processed_operations');").get();
    final procColNames = procCols.map((c) => c.data['name'].toString()).toSet();
    if (!procColNames.contains('client_seq')) {
      await customStatement('ALTER TABLE processed_operations ADD COLUMN client_seq INTEGER;');
    }
    if (!procColNames.contains('operation_type')) {
      await customStatement('ALTER TABLE processed_operations ADD COLUMN operation_type TEXT;');
    }
    if (!procColNames.contains('request_hash')) {
      await customStatement('ALTER TABLE processed_operations ADD COLUMN request_hash TEXT;');
    }
    if (!procColNames.contains('hash_version')) {
      await customStatement('ALTER TABLE processed_operations ADD COLUMN hash_version TEXT;');
    }

    final devCols = await customSelect("PRAGMA table_info('devices');").get();
    final devColNames = devCols.map((c) => c.data['name'].toString()).toSet();
    if (!devColNames.contains('last_committed_client_seq')) {
      await customStatement('ALTER TABLE devices ADD COLUMN last_committed_client_seq INTEGER NOT NULL DEFAULT 0;');
    }
    if (!devColNames.contains('max_seen_client_seq')) {
      await customStatement('ALTER TABLE devices ADD COLUMN max_seen_client_seq INTEGER NOT NULL DEFAULT 0;');
    }
    if (!devColNames.contains('last_committed_at')) {
      await customStatement('ALTER TABLE devices ADD COLUMN last_committed_at INTEGER;');
    }

    // 1. Legacy processed_operations satırlarını deterministik ve tahminsiz olarak backfill et
    final unmigratedOps = await customSelect(
      'SELECT operation_id, device_id, idempotency_key, result_payload '
      'FROM processed_operations WHERE client_seq IS NULL;',
    ).get();

    for (final row in unmigratedOps) {
      final opId = row.data['operation_id']?.toString() ?? '';
      final deviceId = row.data['device_id']?.toString() ?? '';
      final idemKey = row.data['idempotency_key']?.toString() ?? '';
      final rawPayload = row.data['result_payload']?.toString() ?? '';

      final sepIdx = idemKey.lastIndexOf(':');
      if (sepIdx <= 0 || sepIdx >= idemKey.length - 1) {
        throw StateError(
          'Hub v1 -> v2 Migration Hatası: Geçersiz idempotency_key formatı ($idemKey) [operation_id=$opId].',
        );
      }
      final keyDevice = idemKey.substring(0, sepIdx);
      final parsedSeq = int.tryParse(idemKey.substring(sepIdx + 1));
      if (keyDevice != deviceId || parsedSeq == null || parsedSeq <= 0) {
        throw StateError(
          'Hub v1 -> v2 Migration Hatası: idempotency_key ($idemKey) device_id ($deviceId) ile tutarsız [operation_id=$opId].',
        );
      }

      String? opType;
      String? reqHash;
      String? hashVersion;

      if (rawPayload.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawPayload);
          if (decoded is Map<String, dynamic>) {
            final rawHash = decoded['__request_hash'];
            if (rawHash is String && CanonicalPayloadHasher.isValidSha256Hex(rawHash)) {
              reqHash = rawHash.trim().toLowerCase();
              final rawVer = decoded['__hash_version'];
              hashVersion = (rawVer is String && rawVer.trim().isNotEmpty)
                  ? rawVer.trim()
                  : CanonicalPayloadHasher.hashVersionV1Legacy;
            }
            // __request_hash yoksa reqHash ve hashVersion kesinlikle NULL kalır (tahmini hash üretilmez).

            final rawOpType = decoded['operation_type'];
            if (rawOpType is String &&
                CanonicalPayloadHasher.supportedOperationTypes.contains(rawOpType)) {
              opType = rawOpType;
            } else if (decoded['sale_id'] is String &&
                decoded['total_amount'] is int &&
                !decoded.containsKey('refund_id') &&
                !decoded.containsKey('product_id') &&
                !decoded.containsKey('reason')) {
              final saleRows = await customSelect(
                'SELECT 1 AS ok FROM sales WHERE device_id = ? AND client_seq = ? LIMIT 1;',
                variables: [Variable.withString(deviceId), Variable.withInt(parsedSeq)],
              ).get();
              if (saleRows.isNotEmpty) {
                opType = 'SALE_CREATE';
              }
            }
          }
        } catch (_) {
          // Bozuk JSON için tahminde bulunma; NULL bırak.
        }
      }

      await customStatement(
        'UPDATE processed_operations '
        'SET client_seq = ?, operation_type = ?, request_hash = ?, hash_version = ? '
        'WHERE operation_id = ?;',
        [parsedSeq, opType, reqHash, hashVersion, opId],
      );
    }

    // 2. Cihaz bazlı kesintisiz HWM ve max_seen_client_seq değerlerini hesapla ve kaydet
    final deviceRows = await customSelect('SELECT device_id FROM devices;').get();
    for (final devRow in deviceRows) {
      final devId = devRow.data['device_id']?.toString();
      if (devId == null || devId.isEmpty) continue;

      final seqRows = await customSelect(
        'SELECT client_seq, processed_at FROM processed_operations '
        'WHERE device_id = ? AND client_seq IS NOT NULL ORDER BY client_seq ASC;',
        variables: [Variable.withString(devId)],
      ).get();

      final seqs = <int>[];
      Object? maxProcessedAt;
      int? maxProcessedAtInt;
      for (final sr in seqRows) {
        final seqVal = sr.data['client_seq'];
        if (seqVal is int && seqVal > 0) {
          seqs.add(seqVal);
        }
        final pa = sr.data['processed_at'];
        if (pa is int && (maxProcessedAtInt == null || pa > maxProcessedAtInt)) {
          maxProcessedAtInt = pa;
          maxProcessedAt = pa;
        }
      }

      final summary = DeviceSequenceInspector.computeFromSeqs(seqs);
      await customStatement(
        'UPDATE devices '
        'SET last_committed_client_seq = ?, max_seen_client_seq = ?, '
        'last_committed_at = COALESCE(last_committed_at, ?) '
        'WHERE device_id = ?;',
        [summary.contiguousHwm, summary.maxSeenClientSeq, maxProcessedAt, devId],
      );
    }

    // 3. Partial unique index oluştur (mükerrer (device_id, client_seq) varsa fail-closed hata verir)
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_processed_ops_device_seq '
      'ON processed_operations(device_id, client_seq) '
      'WHERE client_seq IS NOT NULL;',
    );
  }

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
