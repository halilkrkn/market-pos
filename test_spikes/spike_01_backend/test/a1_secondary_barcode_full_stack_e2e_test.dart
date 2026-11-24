@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/pepper_manager.dart';
import '../lib/security/token_manager.dart';

/// Hat A — A-3 / A-6 / A-7 (GAP-A01) tam yığın doğrulaması:
/// Gerçek `ClientStorageRepository` (FFI SQLite) + gerçek `ClientSyncService` /
/// `HttpSyncTransport` + gerçek `SpikeServer` (FFI SQLite Hub). Mock yoktur.
///
/// Akış: Cihaz A ürün + ikincil barkod oluşturur → Outbox FIFO ile Hub'a gider →
/// Cihaz B ürün indirmesiyle ikincil barkodu alır → Hub kapalıyken ikincil barkodla
/// çevrimdışı satış yapar (iki kez okutma = 2 adet) → Hub'a gönderir → Hub stoğu
/// tek sefer düşer, tekrar gönderim mükerrer oluşturmaz → Cihaz A barkodu siler →
/// Cihaz B'de barkod artık çözülmez.
void main() {
  late Directory tempDir;
  late File hubDbFile;
  late SpikeDatabase hubDb;
  late PepperManager pepper;
  late SpikeServer server;
  const port = 18994;
  const hubUrl = 'http://127.0.0.1:$port';
  const devA = 'POS-A1-E2E-WIN';
  const devB = 'POS-A1-E2E-AND';
  final tokens = <String, String>{};
  final clientDbs = <String, ClientDatabase>{};
  final repos = <String, ClientStorageRepository>{};
  final syncs = <String, ClientSyncService>{};

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    configureSqliteNative();
  });

  Future<void> startHub() async {
    hubDb = SpikeDatabase(hubDbFile);
    server = SpikeServer(
      db: hubDb,
      dbFile: hubDbFile,
      writeQueue: WriteQueue(),
      backupDirectory: p.join(tempDir.path, 'backups'),
      pepperManager: pepper,
    );
    await server.start(port: port, enableDiscovery: false);
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mms_test_only_a1_full_stack_');
    hubDbFile = File(p.join(tempDir.path, 'hub_master.db'));
    pepper = PepperManager(File(p.join(tempDir.path, 'pepper.dpapi')))..initialize();
    final seedDb = SpikeDatabase(hubDbFile);
    for (final devId in [devA, devB]) {
      final raw = 'test_only_token_$devId';
      tokens[devId] = raw;
      final salt = TokenManager.generateSalt();
      await seedDb.into(seedDb.devices).insert(DevicesCompanion(
            deviceId: Value(devId),
            name: Value('E2E $devId'),
            tokenHash: Value(TokenManager.hashToken(rawToken: raw, salt: salt, pepper: pepper.pepper)),
            salt: Value(salt),
            isActive: const Value(true),
            isConfirmed: const Value(true),
          ));
      final cdb = ClientDatabase(File(p.join(tempDir.path, '$devId.db')));
      final repo = ClientStorageRepository(cdb);
      await repo.initializeDevice(devId);
      clientDbs[devId] = cdb;
      repos[devId] = repo;
      syncs[devId] = ClientSyncService(
        repository: repo,
        transport: HttpSyncTransport(),
        deviceId: devId,
        deviceToken: raw,
        hubUrl: hubUrl,
      );
    }
    await seedDb.close();
    await startHub();
  });

  tearDown(() async {
    for (final db in clientDbs.values) {
      try {
        await db.close();
      } catch (_) {}
    }
    clientDbs.clear();
    repos.clear();
    syncs.clear();
    try {
      await server.stop();
    } catch (_) {}
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  test('İkincil barkod: Cihaz A oluştur → Hub → Cihaz B indir → çevrimdışı satış (2x okutma) → stok → silme yayılımı', () async {
    const primary = '8690007770001';
    const secondary = '8690007770002';

    // 1. Cihaz A: ürün (10 adet) + ikincil barkod; ikisi de Outbox FIFO'ya girer.
    final product = await repos[devA]!.createProduct(
      name: 'E2E İkincil Barkodlu Çay',
      price: 4250, // 42,50 TL (kuruş)
      barcode: primary,
      initialStock: 10000,
      deviceId: devA,
    );
    await repos[devA]!.addProductBarcode(
      productId: product.id,
      barcode: secondary,
      deviceId: devA,
    );
    final pushA = await syncs[devA]!.syncPendingOutbox();
    expect(pushA.syncedCount, greaterThanOrEqualTo(2), reason: 'Ürün + barkod upsert gönderilmeli');

    final hubBarcodes = await (hubDb.select(hubDb.productBarcodes)
          ..where((b) => b.productId.equals(product.id) & b.isActive.equals(true)))
        .get();
    expect(hubBarcodes.map((b) => b.barcode), containsAll([primary, secondary]));

    // 2. Cihaz B: ürün indirmesi ikincil barkodu getirir.
    await syncs[devB]!.syncProducts();
    final resolvedOnB = await repos[devB]!.getProductByBarcode(secondary);
    expect(resolvedOnB?.id, equals(product.id));
    expect(resolvedOnB?.price, equals(4250));

    // 3. Hub kapalı: Cihaz B ikincil barkodu iki kez okutur (2 adet) ve çevrimdışı satar.
    await server.stop();
    final scanned = await repos[devB]!.getProductByBarcode(secondary);
    final sale = await repos[devB]!.createOfflineSale(
      deviceId: devB,
      paymentMethod: 'CASH',
      items: [CartItemInput.units(scanned!.id, 2)],
    );
    expect(sale.totalAmount, equals(8500));
    final localAfterSale = await repos[devB]!.getProductById(product.id);
    expect(localAfterSale!.stock, equals(8000), reason: 'Yerel stok çevrimdışı düşmeli');

    // 4. Hub geri gelir: satış gönderilir, Hub stoğu tek sefer düşer.
    await startHub();
    final pushB = await syncs[devB]!.syncPendingOutbox();
    expect(pushB.syncedCount, equals(1));
    final hubProduct = await (hubDb.select(hubDb.products)..where((t) => t.id.equals(product.id)))
        .getSingle();
    expect(hubProduct.stock, equals(8000));
    expect(await hubDb.select(hubDb.sales).get(), hasLength(1));

    // Tekrar gönderim (idempotency): yeni satış / stok düşümü yok.
    final repeat = await syncs[devB]!.syncPendingOutbox();
    expect(repeat.syncedCount, equals(0));
    final hubProductAfterRepeat = await (hubDb.select(hubDb.products)
          ..where((t) => t.id.equals(product.id)))
        .getSingle();
    expect(hubProductAfterRepeat.stock, equals(8000));

    // 5. Cihaz A ikincil barkodu siler → Hub → Cihaz B'de barkod artık çözülmez.
    final rows = await repos[devA]!.getBarcodesForProduct(product.id);
    final secondaryRow = rows.firstWhere((r) => r.barcode == secondary);
    await repos[devA]!.removeProductBarcode(secondaryRow.id, deviceId: devA);
    // Uygulama döngüsüyle aynı sıra (BackgroundSyncCoordinator): önce Outbox gönder, sonra çek.
    final pushRemove = await syncs[devA]!.syncPendingOutbox();
    expect(pushRemove.syncedCount, equals(1));
    await syncs[devA]!.syncProducts();
    expect(await repos[devA]!.getProductByBarcode(secondary), isNull);

    await syncs[devB]!.syncProducts();
    expect(await repos[devB]!.getProductByBarcode(secondary), isNull,
        reason: 'Silinen ikincil barkod diğer cihazda çözülmemeli');
    expect((await repos[devB]!.getProductByBarcode(primary))?.id, equals(product.id));

    // Hub stoğu barkod upsert'i ile EZİLMEMELİ (Faz 7A: stok yalnızca hareketlerle değişir).
    final hubFinal = await (hubDb.select(hubDb.products)..where((t) => t.id.equals(product.id)))
        .getSingle();
    expect(hubFinal.stock, equals(8000));
  });
}
