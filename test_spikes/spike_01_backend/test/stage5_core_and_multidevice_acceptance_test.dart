@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/backup/hub_backup_oauth_service.dart';
import '../lib/backup/hub_backup_oauth_store.dart';
import '../lib/backup/hub_backup_orchestrator.dart';
import '../lib/backup/hub_backup_state_store.dart';
import '../lib/backup/hub_restore_service.dart';
import '../lib/backup/hub_snapshot_service.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/pepper_manager.dart';
import '../lib/security/replay_protection_service.dart';
import '../lib/security/token_manager.dart';

class _MemoryDriveRelay implements DriveLiveEnvelopeTransport {
  final Map<String, ({String fileName, Uint8List bytes, Map<String, String> appProperties})>
      files = {};
  int _seq = 0;

  @override
  Future<String> ensureSyncFolder() async => 'stage5_livesync_folder';

  @override
  Future<String> uploadEnvelope({
    required String folderId,
    required String fileName,
    required Uint8List bytes,
    required Map<String, String> appProperties,
  }) async {
    final id = 'env_${++_seq}';
    files[id] = (
      fileName: fileName,
      bytes: Uint8List.fromList(bytes),
      appProperties: Map<String, String>.from(appProperties),
    );
    return id;
  }

  @override
  Future<List<DriveRemoteEnvelopeEntry>> listEnvelopes({
    required String folderId,
    required String tenantId,
    required String storeId,
  }) async {
    final res = <DriveRemoteEnvelopeEntry>[];
    for (final e in files.entries) {
      final parsed = DriveRemoteEnvelopeEntry.tryParse({
        'id': e.key,
        'name': e.value.fileName,
        'appProperties': e.value.appProperties,
      });
      if (parsed != null &&
          parsed.tenantId == tenantId &&
          parsed.storeId == storeId) {
        res.add(parsed);
      }
    }
    return res;
  }

  @override
  Future<Uint8List> downloadEnvelope({required String fileId}) async {
    final rec = files[fileId];
    if (rec == null) throw StateError('Envelope yok: $fileId');
    return rec.bytes;
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  configureSqliteNative();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mms_test_only_stage5_acc_');
  });

  tearDown(() async {
    for (var attempt = 0; attempt < 6; attempt++) {
      if (!tempDir.existsSync()) break;
      try {
        tempDir.deleteSync(recursive: true);
        break;
      } on FileSystemException {
        if (attempt == 5) break;
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    }
  });

  Future<
      ({
        File hubDbFile,
        Directory backupDir,
        Directory secDir,
        SpikeDatabase hubDb,
        WriteQueue writeQueue,
        PepperManager pepper,
        SpikeServer server,
        HttpServer ioServer,
        String baseUrl,
      })> startHub(
    String subDir, {
    String adminSecret = 'stage5_admin_secret_1',
    String? pepperOverride,
  }) async {
    final root = Directory(p.join(tempDir.path, subDir))..createSync(recursive: true);
    final hubDbFile = File(p.join(root.path, 'data', 'market_master.db'));
    hubDbFile.parent.createSync(recursive: true);
    final backupDir = Directory(p.join(root.path, 'backups'))..createSync();
    final secDir = Directory(p.join(root.path, 'security'))..createSync();
    final db = SpikeDatabase(hubDbFile);
    await db.customStatement('SELECT 1;');
    final wq = WriteQueue();
    final pepper = PepperManager(File(p.join(secDir.path, 'pepper.dpapi')))
      ..initialize(
        overrideForTesting:
            pepperOverride ?? 'stage5_pepper_secret_32_bytes_min!!',
      );
    final server = SpikeServer(
      db: db,
      dbFile: hubDbFile,
      writeQueue: wq,
      backupDirectory: backupDir.path,
      pepperManager: pepper,
      adminSecret: adminSecret,
      replayProtectionService: ReplayProtectionService(),
      hubRestoreSafetyKdfIterations: 1000,
    );
    final ioServer = await shelf_io.serve(
      server.handler,
      InternetAddress.loopbackIPv4,
      0,
    );
    return (
      hubDbFile: hubDbFile,
      backupDir: backupDir,
      secDir: secDir,
      hubDb: db,
      writeQueue: wq,
      pepper: pepper,
      server: server,
      ioServer: ioServer,
      baseUrl: 'http://127.0.0.1:${ioServer.port}',
    );
  }

  Future<String> registerDevice(
    SpikeDatabase db,
    PepperManager pepper, {
    required String deviceId,
    required String role,
    bool isActive = true,
    bool isConfirmed = true,
  }) async {
    final tok = 'mms_dt_s5_${deviceId}_tok';
    final salt = TokenManager.generateSalt();
    await db.into(db.devices).insert(
          DevicesCompanion.insert(
            deviceId: deviceId,
            name: 'Device $deviceId',
            tokenHash: TokenManager.hashToken(
              rawToken: tok,
              salt: salt,
              pepper: pepper.pepper,
            ),
            salt: salt,
            isActive: Value(isActive),
            isConfirmed: Value(isConfirmed),
            role: Value(role),
          ),
        );
    return tok;
  }

  group('Aşama 5.2 — Temel Market Operasyonları (17 Akış + Atomik/Finansal Kesinlik)', () {
    test('1. Kategori, ürün, birincil/ikincil barkod, duplicate ret, kesirli Half-Up, satış, iade, iptal, fiyat geçmişi, RBAC ve Dashboard', () async {
      final ctx = await startHub('hub_52');
      final httpClient = http.Client();
      final ownerTok = await registerDevice(
        ctx.hubDb,
        ctx.pepper,
        deviceId: 'WIN-52-OWNER',
        role: 'OWNER',
      );
      final cashierTok = await registerDevice(
        ctx.hubDb,
        ctx.pepper,
        deviceId: 'AND-52-CASHIER',
        role: 'CASHIER',
      );

      final clientDbFile = File(p.join(tempDir.path, 'client_52.db'));
      final cdb = ClientDatabase(clientDbFile);
      final repo = ClientStorageRepository(cdb);
      await repo.initializeDevice('WIN-52-OWNER');
      final transport = HttpSyncTransport();
      final sync = ClientSyncService(
        repository: repo,
        transport: transport,
        deviceId: 'WIN-52-OWNER',
        deviceToken: ownerTok,
        hubUrl: ctx.baseUrl,
      );

      try {
        // Akış 3: Kategori oluşturma, güncelleme ve pasife alma
        final parentCat = await repo.createCategory(name: 'Gıda');
        final childCat = await repo.createCategory(name: 'Şarküteri', parentId: parentCat.id);
        await repo.updateCategory(id: childCat.id, name: 'Et & Şarküteri', parentId: parentCat.id);
        final tempCat = await repo.createCategory(name: 'Geçici Kategori');
        await repo.deactivateCategory(tempCat.id);
        final activeCats = await repo.getCategories();
        expect(activeCats.map((c) => c.id), containsAll([parentCat.id, childCat.id]));
        expect(activeCats.map((c) => c.id), isNot(contains(tempCat.id)));

        // Akış 1 & 4: Ürün oluşturma + birincil barkod
        final cheese = await repo.createProduct(
          name: 'Tam Yağlı Kaşar Peyniri 1kg',
          price: 1999, // 19.99 TL/kg (Half-Up testi için)
          barcode: '8690500100001',
          categoryId: childCat.id,
          initialStock: 20000, // 20 kg (milli-birim: 20000)
          stockUnit: 'kg',
          pricingUnit: 'kg',
          initialPurchasePrice: 1200,
          deviceId: 'WIN-52-OWNER',
        );
        final milk = await repo.createProduct(
          name: 'Süt 1L',
          price: 3000,
          barcode: '8690500100002',
          categoryId: parentCat.id,
          initialStock: 10000, // 10 adet
          deviceId: 'WIN-52-OWNER',
        );

        // Akış 5 & 6: İkincil barkod ekleme/silme + duplicate engeli
        await repo.addProductBarcode(
          productId: cheese.id,
          barcode: '8690500999001',
          isPrimary: false,
          deviceId: 'WIN-52-OWNER',
        );
        await expectLater(
          () => repo.addProductBarcode(
            productId: milk.id,
            barcode: '8690500999001',
            deviceId: 'WIN-52-OWNER',
          ),
          throwsA(anything),
        );

        // Akış 7: Birincil & ikincil barkod ile ürün bulma; bilinmeyen barkod null
        expect((await repo.getProductByBarcode('8690500100001'))?.id, equals(cheese.id));
        expect((await repo.getProductByBarcode('8690500999001'))?.id, equals(cheese.id));
        expect(await repo.getProductByBarcode('8699999999999'), isNull);

        // İkincil barkod silme
        final cheeseBarcodes = await repo.getBarcodesForProduct(cheese.id);
        final altBc = cheeseBarcodes.firstWhere((b) => !b.isPrimary);
        await repo.removeProductBarcode(altBc.id, deviceId: 'WIN-52-OWNER');
        expect((await repo.getBarcodesForProduct(cheese.id)).length, equals(1));

        // Akış 2, 14, 15: Ürün güncelleme + fiyat geçmişi + priceVersionId
        final updatedMilk = await repo.updateProduct(
          id: milk.id,
          name: 'Organik Süt 1L',
          price: 3500,
          priceChangeReason: 'Tedarikçi zammı',
          deviceId: 'WIN-52-OWNER',
        );
        expect(updatedMilk.priceVersionId, isNot(equals(milk.priceVersionId)));
        final priceHistory = await (cdb.select(cdb.localPriceHistory)
              ..where((h) => h.productId.equals(milk.id)))
            .get();
        expect(priceHistory.length, equals(2));
        expect(priceHistory.any((h) => h.oldPrice == 0 && h.newPrice == 3000), isTrue);
        expect(priceHistory.any((h) => h.oldPrice == 3000 && h.newPrice == 3500), isTrue);

        // Akış 8, 9, 10, 11 & Half-Up yuvarlama:
        // 0.333 kg * 1999 kuruş = 665.667 -> Half-Up ((1999 * 333) + 500) ~/ 1000 = 666 kuruş
        final halfUpSale = await repo.createOfflineSale(
          deviceId: 'WIN-52-OWNER',
          paymentMethod: 'CASH',
          items: [
            CartItemInput.fractional(
              cheese.id,
              333,
              expectedUnitPrice: 1999,
              expectedPriceVersionId: cheese.priceVersionId,
            ),
          ],
        );
        expect(halfUpSale.totalAmount, equals(666));
        expect(halfUpSale.totalAmount, isA<int>());
        expect((await repo.getProductById(cheese.id))!.stock, equals(19667));

        // PriceChangedException tutarlılığı: eski fiyat sürümü sepette tespit edilir
        await expectLater(
          () => repo.createOfflineSale(
            deviceId: 'WIN-52-OWNER',
            paymentMethod: 'CASH',
            items: [
              CartItemInput.units(
                milk.id,
                1,
                expectedUnitPrice: 3000,
                expectedPriceVersionId: milk.priceVersionId,
              ),
            ],
          ),
          throwsA(isA<PriceChangedException>()),
        );

        // Akış 13: Kısmi iade (SELLABLE stok artar vs DAMAGED artmaz; Half-Up)
        final saleForRefund = await repo.createOfflineSale(
          deviceId: 'WIN-52-OWNER',
          paymentMethod: 'CARD',
          items: [CartItemInput.units(milk.id, 4)], // 4 * 3500 = 14000; stok 10 -> 6
        );
        final detail = await repo.getSaleDetail(saleForRefund.saleId);
        await repo.refundSale(
          saleId: saleForRefund.saleId,
          items: [
            RefundItemInput(
              saleItemId: detail!.items.single.id,
              quantity: 1000,
              productCondition: 'SELLABLE',
            ),
            RefundItemInput(
              saleItemId: detail.items.single.id,
              quantity: 1000,
              productCondition: 'DAMAGED',
            ),
          ],
          reason: '1 sağlam + 1 hasarlı iade',
          deviceId: 'WIN-52-OWNER',
        );
        // Sadece SELLABLE (+1) stoğa döndü: 6 + 1 = 7 adet (7000)
        expect((await repo.getProductById(milk.id))!.stock, equals(7000));

        // Akış 12: Tam satış iptali (net kalan adet = 2 -> stok 7 + 2 = 9)
        await repo.cancelSale(
          saleId: saleForRefund.saleId,
          reason: 'Kalan kalem iptali',
          deviceId: 'WIN-52-OWNER',
        );
        expect((await repo.getProductById(milk.id))!.stock, equals(9000));

        // 17. Dashboard net toplam doğrulama: sadece halfUpSale (666 kuruş CASH) net kalmalı
        final prodSum = await repo.getDashboardProductSummary();
        expect(prodSum.activeProductCount, equals(2));
        final salesSum = await repo.getDashboardSalesSummary(
          todayStart: DateTime(
            DateTime.now().year,
            DateTime.now().month,
            DateTime.now().day,
          ),
        );
        expect(salesSum.todaySalesTotalCents, equals(666));
        expect(salesSum.todayCashTotalCents, equals(666));
        expect(salesSum.todayCardTotalCents, equals(0));
        expect(salesSum.todaySalesCount, equals(1));

        // Tüm Outbox'ı Hub'a senkronize et ve Hub'da da 666 kuruş + duplicate barcode reddini doğrula
        final batch = await sync.syncPendingOutbox(maxBatch: 50);
        expect(batch.permanentFailedCount, equals(0));
        expect(await repo.getUnsyncedOutboxOperations('WIN-52-OWNER'), isEmpty);

        final hubCheese = await (ctx.hubDb.select(ctx.hubDb.products)
              ..where((p) => p.id.equals(cheese.id)))
            .getSingle();
        expect(hubCheese.stock, equals(19667));
        final hubSale = await (ctx.hubDb.select(ctx.hubDb.sales)
              ..where((s) =>
                  s.deviceId.equals('WIN-52-OWNER') &
                  s.clientSeq.equals(halfUpSale.clientSeq)))
            .getSingle();
        expect(hubSale.totalAmount, equals(666));

        // Hub duplicate barcode 409 engeli
        final nextOwnerSeq =
            ((await repo.getSyncState('WIN-52-OWNER'))?.lastSyncedSeq ?? 0) + 1;
        final dupUpsertResp = await httpClient.post(
          Uri.parse('${ctx.baseUrl}/api/v1/products/upsert'),
          headers: {
            'authorization': 'Bearer $ownerTok',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'operation_id': 'op_dup_bc_test_1',
            'device_id': 'WIN-52-OWNER',
            'client_seq': nextOwnerSeq,
            'product': {
              'id': 'prod_dup_test',
              'name': 'Çakışan Ürün',
              'barcode': '8690500100001',
              'price': 1000,
              'stock': 1000,
              'barcodes': ['8690500100001'],
            },
          }),
        );
        expect(dupUpsertResp.statusCode, equals(409));

        // Aynı satışın idempotency replay koruması
        final replaySale = (await repo.getSyncedOutboxOperations('WIN-52-OWNER'))
            .firstWhere((o) => o.operationType == 'SALE_CREATE');
        final replayResp = await httpClient.post(
          Uri.parse('${ctx.baseUrl}/api/v1/sales'),
          headers: {
            'authorization': 'Bearer $ownerTok',
            'content-type': 'application/json',
          },
          body: replaySale.payload,
        );
        expect(replayResp.statusCode, equals(200));
        expect(
          (await (ctx.hubDb.select(ctx.hubDb.products)
                ..where((p) => p.id.equals(cheese.id)))
              .getSingle())
              .stock,
          equals(19667),
        );

        // Akış 16: CASHIER / OWNER RBAC doğrulaması
        final cashierBackupTry = await httpClient.get(
          Uri.parse('${ctx.baseUrl}/api/v1/backup/status'),
          headers: {'authorization': 'Bearer $cashierTok'},
        );
        expect(cashierBackupTry.statusCode, equals(403));
        final ownerStatusTry = await httpClient.get(
          Uri.parse('${ctx.baseUrl}/api/v1/backup/status'),
          headers: {'authorization': 'Bearer $ownerTok'},
        );
        expect(ownerStatusTry.statusCode, equals(200));
      } finally {
        httpClient.close();
        transport.close();
        await cdb.close();
        await ctx.ioServer.close(force: true);
        await ctx.hubDb.close();
      }
    });
  });

  group('Aşama 5.3 — Offline-First ve Çoklu Cihaz (17 Senaryo)', () {
    test('2. 2-cihazlı offline/online FIFO, seq gap, eşzamanlı stok/fiyat çatışması, MMSENV01 fallback + Hub uzlaşma ve OV-03 fail-closed', () async {
      var ctx = await startHub('hub_53');
      final httpClient = http.Client();
      final tokA = await registerDevice(ctx.hubDb, ctx.pepper, deviceId: 'DEV-53-A', role: 'OWNER');
      final tokB = await registerDevice(ctx.hubDb, ctx.pepper, deviceId: 'DEV-53-B', role: 'CASHIER');

      // Ortak başlangıç ürünü: 10 adet, 50.00 TL
      await ctx.hubDb.into(ctx.hubDb.products).insert(
            ProductsCompanion.insert(
              id: 'prod_53_oil',
              barcode: '8690530000011',
              name: 'Zeytinyağı 1L',
              price: 5000,
              priceVersionId: const Value('pv_53_1'),
              stock: 10000,
            ),
          );

      final dbA = ClientDatabase(File(p.join(tempDir.path, 'dev53_a.db')));
      final dbB = ClientDatabase(File(p.join(tempDir.path, 'dev53_b.db')));
      final repoA = ClientStorageRepository(dbA);
      final repoB = ClientStorageRepository(dbB);
      await repoA.initializeDevice('DEV-53-A');
      await repoB.initializeDevice('DEV-53-B');
      final transportA = HttpSyncTransport.forStore(
        client: httpClient,
        tenantId: SpikeServer.defaultTenantId,
        storeId: SpikeServer.defaultStoreId,
      );
      final transportB = HttpSyncTransport.forStore(
        client: httpClient,
        tenantId: SpikeServer.defaultTenantId,
        storeId: SpikeServer.defaultStoreId,
      );
      final syncA = ClientSyncService(
        repository: repoA,
        transport: transportA,
        deviceId: 'DEV-53-A',
        deviceToken: tokA,
        hubUrl: ctx.baseUrl,
      );
      final syncB = ClientSyncService(
        repository: repoB,
        transport: transportB,
        deviceId: 'DEV-53-B',
        deviceToken: tokB,
        hubUrl: ctx.baseUrl,
      );

      try {
        // Senaryo 1: Hub açıkken normal ürün sync
        expect(await syncA.syncProducts(), equals(1));
        expect(await syncB.syncProducts(), equals(1));

        // Senaryo 2, 8, 9, 10: Hub kapatılır (offline); A 7 adet satıp fiyatı 60 TL yapar; B eski pv_53_1 fiyatla 6 adet satar (toplam 13 > 10 stok)
        await ctx.ioServer.close(force: true);
        await ctx.hubDb.close();

        final saleA1 = await repoA.createOfflineSale(
          deviceId: 'DEV-53-A',
          paymentMethod: 'CASH',
          items: [CartItemInput.units('prod_53_oil', 7)],
        );
        final priceUpA = await repoA.updateProduct(
          id: 'prod_53_oil',
          price: 6000,
          deviceId: 'DEV-53-A',
        );
        final saleB1 = await repoB.createOfflineSale(
          deviceId: 'DEV-53-B',
          paymentMethod: 'CARD',
          items: [
            CartItemInput.units(
              'prod_53_oil',
              6,
              expectedUnitPrice: 5000,
              expectedPriceVersionId: 'pv_53_1',
            ),
          ],
        );
        expect(saleB1.totalAmount, equals(30000));

        // Senaryo 11: Hub kapalıyken Google Drive (MMSENV01) hibrit fallback + Non-LWW çatışma kaydı
        final sharedDrive = _MemoryDriveRelay();
        final registry = DriveAuthorizedDeviceRegistry()
          ..authorizeDevice(deviceId: 'DEV-53-A', tenantId: SpikeServer.defaultTenantId, storeId: SpikeServer.defaultStoreId, deviceSecretOrPublicKey: 'key_a')
          ..authorizeDevice(deviceId: 'DEV-53-B', tenantId: SpikeServer.defaultTenantId, storeId: SpikeServer.defaultStoreId, deviceSecretOrPublicKey: 'key_b');
        final driveA = MmsDriveLiveSyncEngine(
          repository: repoA,
          transport: sharedDrive,
          ledger: DriveLiveSyncLedger(File(p.join(tempDir.path, 'ledger_a.json'))),
          deviceRegistry: registry,
          tenantId: SpikeServer.defaultTenantId,
          storeId: SpikeServer.defaultStoreId,
          localDeviceId: 'DEV-53-A',
          readLiveSyncSecret: () async => 'Stage5LiveSyncSecret-2026!',
          kdfIterations: 100,
        );
        final driveB = MmsDriveLiveSyncEngine(
          repository: repoB,
          transport: sharedDrive,
          ledger: DriveLiveSyncLedger(File(p.join(tempDir.path, 'ledger_b.json'))),
          deviceRegistry: registry,
          tenantId: SpikeServer.defaultTenantId,
          storeId: SpikeServer.defaultStoreId,
          localDeviceId: 'DEV-53-B',
          readLiveSyncSecret: () async => 'Stage5LiveSyncSecret-2026!',
          kdfIterations: 100,
        );
        await driveA.recordHubFailure(isSecurityHold: false, isAuthFailure: false);
        await driveA.recordHubFailure(isSecurityHold: false, isAuthFailure: false);
        await driveB.recordHubFailure(isSecurityHold: false, isAuthFailure: false);
        await driveB.recordHubFailure(isSecurityHold: false, isAuthFailure: false);

        final fbA = await driveA.runDriveFallbackCycle();
        expect(fbA.uploadedCount, equals(2));
        final fbB = await driveB.runDriveFallbackCycle();
        expect(fbB.uploadedCount, equals(1));
        expect(fbB.appliedCount, equals(2));
        // A kendi Outbox'ını Drive'dan dönse de ASLA SYNCED yapmaz
        expect((await repoA.getUnsyncedOutboxOperations('DEV-53-A')).length, equals(2));
        // B'nin Outbox'ına A'nın işlemleri echo olmaz
        expect((await repoB.getUnsyncedOutboxOperations('DEV-53-B')).length, equals(1));

        // B'ye aynı ürün üzerinde bekleyen yerel PRODUCT_UPSERT varken A'nın fiyat değişimi gelirse sessiz LWW olmaz!
        await repoA.updateProduct(id: 'prod_53_oil', price: 6500, deviceId: 'DEV-53-A');
        await repoB.updateProduct(id: 'prod_53_oil', price: 5800, deviceId: 'DEV-53-B');
        await driveA.runDriveFallbackCycle();
        final fbConflictB = await driveB.runDriveFallbackCycle();
        expect(fbConflictB.newConflicts.length, equals(1));

        // Senaryo 3, 4, 12, 13, 14: Hub aynı DB + pepper ile yeniden açılır; reconciliation + FIFO + stok -3 kg
        final reopenedDb = SpikeDatabase(ctx.hubDbFile);
        final server2 = SpikeServer(
          db: reopenedDb,
          dbFile: ctx.hubDbFile,
          writeQueue: WriteQueue(),
          backupDirectory: ctx.backupDir.path,
          pepperManager: ctx.pepper,
          adminSecret: 'stage5_admin_secret_1',
          hubRestoreSafetyKdfIterations: 1000,
        );
        final io2 = await shelf_io.serve(server2.handler, InternetAddress.loopbackIPv4, 0);
        final url2 = 'http://127.0.0.1:${io2.port}';
        final syncA2 = ClientSyncService(
          repository: repoA,
          transport: transportA,
          deviceId: 'DEV-53-A',
          deviceToken: tokA,
          hubUrl: url2,
        );
        final syncB2 = ClientSyncService(
          repository: repoB,
          transport: transportB,
          deviceId: 'DEV-53-B',
          deviceToken: tokB,
          hubUrl: url2,
        );

        try {
          final recA = await driveA.reconcileWithMasterHub(
            pushOutboxToHub: () async => (await syncA2.syncPendingOutbox()).syncedCount,
            pullProductsFromHub: () => syncA2.syncProducts(),
            pullSalesFromHub: () => syncA2.syncSales(),
            isOutboxEmptyOrAllSynced: () => true,
          );
          final recB = await driveB.reconcileWithMasterHub(
            pushOutboxToHub: () async => (await syncB2.syncPendingOutbox()).syncedCount,
            pullProductsFromHub: () => syncB2.syncProducts(),
            pullSalesFromHub: () => syncB2.syncSales(),
            isOutboxEmptyOrAllSynced: () => true,
          );
          expect(recA.reconciled, isTrue);
          expect(recB.reconciled, isTrue);

          final finalHubProd = await (reopenedDb.select(reopenedDb.products)
                ..where((p) => p.id.equals('prod_53_oil')))
              .getSingle();
          // Başlangıç 10 - A(7) - B(6) = -3 kg (-3000 milli); iki fiziksel satış da korundu!
          expect(finalHubProd.stock, equals(-3000));
          expect((await reopenedDb.select(reopenedDb.sales).get()).length, equals(2));

          // Senaryo 5 & 6: Idempotent replay
          final opA = (await repoA.getSyncedOutboxOperations('DEV-53-A')).first;
          final rep = await httpClient.post(
            Uri.parse('$url2/api/v1/sales'),
            headers: {
              'authorization': 'Bearer $tokA',
              'content-type': 'application/json',
            },
            body: opA.payload,
          );
          expect(rep.statusCode, equals(200));

          // Senaryo 7: Client sequence gap tespiti (seq 99 atlamalı gönderim -> 409 ERR_CLIENT_SEQ_GAP)
          final gapPayload = jsonEncode({
            'operation_id': 'op_gap_99',
            'sale_id': 'sale_gap_99',
            'device_id': 'DEV-53-B',
            'client_seq': 99,
            'items': [
              {
                'product_id': 'prod_53_oil',
                'quantity': 1000,
                'unit_price': 5000,
                'total_price': 5000,
                'price_version_id': priceUpA.priceVersionId,
              }
            ],
            'total_amount': 5000,
            'payment_method': 'CASH',
          });
          final gapResp = await httpClient.post(
            Uri.parse('$url2/api/v1/sales'),
            headers: {
              'authorization': 'Bearer $tokB',
              'content-type': 'application/json',
            },
            body: gapPayload,
          );
          expect(gapResp.statusCode, equals(409));
          expect(jsonDecode(gapResp.body)['code'], equals('ERR_CLIENT_SEQ_GAP'));

          // Senaryo 14: Device identity sabitliği
          expect((await repoA.getSyncState('DEV-53-A'))?.deviceId, equals('DEV-53-A'));
          expect(saleA1.operationId, isNotEmpty);

          // Senaryo 15, 16, 17: OV-03 restore_epoch uzlaştırması & eksik payload durumunda fail-closed
          // Hub DB'deki son satışı (Hub ID = sale_<micros>), kalemlerini, stok hareketini ve
          // işlem kaydını temizleyip restore_epoch değiştirerek saleA1 öncesi yedeğe dönüşü simüle et.
          final hubSaleA1 = await (reopenedDb.select(reopenedDb.sales)
                ..where((s) =>
                    s.deviceId.equals('DEV-53-A') &
                    s.clientSeq.equals(saleA1.clientSeq)))
              .getSingle();
          await (reopenedDb.delete(reopenedDb.saleItems)
                ..where((i) => i.saleId.equals(hubSaleA1.id)))
              .go();
          await (reopenedDb.delete(reopenedDb.stockMovements)
                ..where((m) => m.referenceId.equals(hubSaleA1.id)))
              .go();
          await (reopenedDb.delete(reopenedDb.sales)
                ..where((s) => s.id.equals(hubSaleA1.id)))
              .go();
          await (reopenedDb.delete(reopenedDb.processedOperations)
                ..where((o) =>
                    o.deviceId.equals('DEV-53-A') &
                    o.clientSeq.equals(saleA1.clientSeq)))
              .go();
          await (reopenedDb.update(reopenedDb.products)
                ..where((p) => p.id.equals('prod_53_oil')))
              .write(ProductsCompanion(stock: Value(finalHubProd.stock + 7000)));
          await (reopenedDb.update(reopenedDb.devices)
                ..where((d) => d.deviceId.equals('DEV-53-A')))
              .write(const DevicesCompanion(lastCommittedClientSeq: Value(0)));
          await reopenedDb.into(reopenedDb.hubMetadata).insertOnConflictUpdate(
                HubMetadataCompanion(
                  key: const Value('restore_epoch'),
                  value: const Value('epoch_restored_53'),
                  updatedAt: Value(DateTime.now().toUtc()),
                ),
              );
          final ov03 = await syncA2.syncPendingOutbox();
          expect(ov03.postRestoreRequeuedCount, greaterThanOrEqualTo(1));
          expect(ov03.postRestoreHistoryMissing, isFalse);
          expect(ov03.isCleanSuccess, isTrue, reason: 'OV-03 sync error: ${ov03.lastError}');
          expect(
            (await (reopenedDb.select(reopenedDb.sales)
                  ..where((s) =>
                      s.deviceId.equals('DEV-53-A') &
                      s.clientSeq.equals(saleA1.clientSeq)))
                .getSingleOrNull()),
            isNotNull,
          );
          expect(
            (await (reopenedDb.select(reopenedDb.products)
                      ..where((p) => p.id.equals('prod_53_oil')))
                    .getSingle())
                .stock,
            equals(-3000),
          );

          // Senaryo 17: Eksik yerel SYNCED payload -> fail-closed
          await (dbB.update(dbB.clientSyncStates)
                ..where((s) => s.deviceId.equals('DEV-53-B')))
              .write(const ClientSyncStatesCompanion(lastSyncedSeq: Value(50)));
          await reopenedDb.into(reopenedDb.hubMetadata).insertOnConflictUpdate(
                HubMetadataCompanion(
                  key: const Value('restore_epoch'),
                  value: const Value('epoch_restored_failclosed'),
                  updatedAt: Value(DateTime.now().toUtc()),
                ),
              );
          final failClosedRes = await syncB2.syncPendingOutbox();
          expect(failClosedRes.postRestoreHistoryMissing, isTrue);
        } finally {
          await io2.close(force: true);
          await reopenedDb.close();
        }
      } finally {
        httpClient.close();
        transportA.close();
        transportB.close();
        await dbA.close();
        await dbB.close();
      }
    });
  });

  group('Aşama 5.4 — Backup ve Disaster Recovery (15 Senaryo + Yeni PC Simülasyonu)', () {
    test('3. Merkezi MMSBAK02 oluşturma, şifreleme, indirme/doğrulama, 1-bit tamper reddi, yeni PC restore, epoch, token invalidation, crash recovery ve retention', () async {
      final ctx1 = await startHub('hub_54_old', pepperOverride: 'old_machine_pepper_secret_32bytes!!');
      final httpClient = http.Client();
      const recoveryPass = 'Portable-Master-Recovery-2026!';
      final oldOwnerTok = await registerDevice(ctx1.hubDb, ctx1.pepper, deviceId: 'DEV-ACT-1', role: 'OWNER', isActive: true);
      final oldCashierTok = await registerDevice(ctx1.hubDb, ctx1.pepper, deviceId: 'DEV-ACT-2', role: 'CASHIER', isActive: true);
      await registerDevice(ctx1.hubDb, ctx1.pepper, deviceId: 'DEV-REV-1', role: 'CASHIER', isActive: false);

      await ctx1.hubDb.into(ctx1.hubDb.products).insert(
            ProductsCompanion.insert(
              id: 'prod_dr_1',
              barcode: '8690540000011',
              name: 'Felaket Kurtarma Çayı 500g',
              price: 14500,
              stock: 30000,
            ),
          );

      // OAuth & sahte Drive deposu
      final fakeDriveFiles = <String, ({Uint8List bytes, Map<String, String> meta})>{};
      var sessionSeq = 0;
      final mockDriveHttp = MockClient((req) async {
        if (req.url.toString().contains('/oauth2.googleapis.com/token')) {
          return http.Response(jsonEncode({'access_token': 'acc_dr_1', 'expires_in': 3600}), 200);
        }
        if (req.method == 'GET' && req.url.path == '/drive/v3/files') {
          final q = req.url.queryParameters['q'] ?? '';
          if (q.contains("mimeType = 'application/vnd.google-apps.folder'")) {
            return http.Response(
              jsonEncode({'files': [{'id': 'drv_folder_hub', 'name': 'Hub'}]}),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'files': [
                for (final e in fakeDriveFiles.entries)
                  {
                    'id': e.key,
                    'name': 'hub_backup_${e.value.meta['mms_backup_id']}.mmsbak',
                    'size': e.value.bytes.length.toString(),
                    'appProperties': e.value.meta,
                  }
              ],
            }),
            200,
          );
        }
        if (req.method == 'POST' && req.url.path.startsWith('/upload/drive/v3/files')) {
          final uploadUrl = 'https://upload.example.test/sess_${++sessionSeq}';
          return http.Response('', 200, headers: {'location': uploadUrl});
        }
        if (req.method == 'PUT' && req.url.host == 'upload.example.test') {
          final id = 'drv_file_${fakeDriveFiles.length + 1}';
          final bytes = Uint8List.fromList(req.bodyBytes);
          fakeDriveFiles[id] = (
            bytes: bytes,
            meta: {
              'mms_backup_source': 'HUB_CENTRAL',
              'mms_database_type': DatabaseType.centralMaster.value,
              'mms_sha256': sha256.convert(bytes).toString(),
            },
          );
          return http.Response(
            jsonEncode({
              'id': id,
              'size': bytes.length.toString(),
              'md5Checksum': md5.convert(bytes).toString(),
            }),
            200,
          );
        }
        if (req.method == 'GET' && req.url.path.startsWith('/drive/v3/files/')) {
          final id = req.url.pathSegments.last;
          final f = fakeDriveFiles[id];
          if (f == null) return http.Response('Not Found', 404);
          if (req.url.queryParameters['alt'] == 'media') {
            return http.Response.bytes(f.bytes, 200);
          }
          return http.Response(
            jsonEncode({
              'id': id,
              'name': 'hub_backup_bak_dr_uploaded.mmsbak',
              'size': f.bytes.length.toString(),
              'md5Checksum': md5.convert(f.bytes).toString(),
              'appProperties': f.meta,
            }),
            200,
          );
        }
        return http.Response('Unhandled ${req.method} ${req.url}', 404);
      });

      final oauthStore = HubBackupOAuthStore(
        File(p.join(ctx1.secDir.path, HubBackupOAuthStore.defaultFileName)),
      );
      await oauthStore.save(HubBackupOAuthCredentials(
        accessToken: 'acc_dr_1',
        refreshToken: 'ref_dr_1',
        expiresAtUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
        scope: 'https://www.googleapis.com/auth/drive.file',
        folderId: 'drv_folder_hub',
        folderLayout: HubBackupOAuthCredentials.hubSubfolderLayout,
        connectedAtUtc: DateTime.now().toUtc(),
      ));
      final oauthSvc = HubBackupOAuthService(store: oauthStore, httpClient: mockDriveHttp);
      final snapSvc = HubSnapshotService(
        readDb: () => ctx1.hubDb,
        writeQueue: ctx1.writeQueue,
        liveDbFile: ctx1.hubDbFile,
        backupDir: ctx1.backupDir,
        hubId: SpikeServer.defaultHubId,
        tenantId: SpikeServer.defaultTenantId,
        storeId: SpikeServer.defaultStoreId,
        appVersion: '1.0.0',
        kdfIterations: 1000,
        diskSpaceChecker: DiskSpaceChecker(freeBytesProbe: (_) async => 1 << 30),
      );
      final uploader = ResumableDriveUploader(
        accessTokenProvider: ({bool forceRefresh = false}) =>
            oauthSvc.getValidAccessToken(clientId: 'cid', forceRefresh: forceRefresh),
        httpClient: mockDriveHttp,
      );
      final orch = HubBackupOrchestrator(
        snapshotService: snapSvc,
        stateStore: HubBackupStateStore(File(p.join(ctx1.backupDir.path, HubBackupStateStore.defaultFileName))),
        recoveryKeyStore: ctx1.server.hubRecoveryKeyStore,
        oauthService: oauthSvc,
        uploader: uploader,
        operationLock: BackupOperationLock(File(p.join(ctx1.backupDir.path, '.lock'))),
        readSchemaVersion: () => ctx1.hubDb.schemaVersion,
        oauthClientId: 'cid',
      );
      await ctx1.server.hubRecoveryKeyStore.saveRecoveryPassword(recoveryPass);

      final job = await orch.triggerBackup();
      expect(job.state, equals(HubBackupJobState.completedUploaded));
      expect(job.driveFileId, isNotNull);
      final rawEnc = await File(job.encryptedPath!).readAsBytes();
      // Şifreli paket düz SQLite başlığı içermez, MMSBAK02 başlığı içerir
      expect(rawEnc.sublist(0, 8), equals(MmsbakV2Crypto.magicHeader));
      expect(utf8.decode(rawEnc, allowMalformed: true), isNot(contains('SQLite format 3')));

      // Eski Hub kapatılır
      await ctx1.ioServer.close(force: true);
      await ctx1.hubDb.close();

      final dlDir = Directory(p.join(tempDir.path, 'dl_from_drive'))..createSync();
      // Yeni bilgisayar (TAMAMEN FARKLI PEPPER + BOŞ DB) üzerinde indirme & doğrulama & restore
      final newCtx = await startHub('hub_54_new_pc', pepperOverride: 'BRAND_NEW_PC_PEPPER_32_BYTES_MIN!!');
      try {
        final dlRes = await uploader.downloadAndVerifyBackup(
          driveFileId: job.driveFileId!,
          targetDir: dlDir,
          expectedBackupId: job.backupId,
          expectedSha256Hex: job.encryptedSha256,
        );
        final dlFile = dlRes.file;
        expect(dlRes.sha256Hex, equals(job.encryptedSha256));

        // Bozuk backup (1-bit tamper) ve yanlış parola reddedilir
        final tampered = File(p.join(tempDir.path, 'tampered.mmsbak'))
          ..writeAsBytesSync(Uint8List.fromList(rawEnc)..[rawEnc.length - 12] ^= 0x01);
        final decOut = File(p.join(tempDir.path, 'unused.db'));
        await expectLater(
          () => MmsbakV2Crypto.decryptFile(
            inputFile: tampered,
            outputFile: decOut,
            password: recoveryPass,
          ),
          throwsA(isA<BackupCryptoException>()),
        );
        await expectLater(
          () => MmsbakV2Crypto.decryptFile(
            inputFile: dlFile,
            outputFile: decOut,
            password: 'Wrong-Password-2026!',
          ),
          throwsA(isA<BackupCryptoException>()),
        );

        // Yeni PC'ye kontrollü restore (HubRestoreService)
        SpikeDatabase activeNewDb = newCtx.hubDb;
        final restoreRes = await HubRestoreService.restoreFromEncryptedPackage(
          packageFile: dlFile,
          recoveryPassword: recoveryPass,
          liveDbFile: newCtx.hubDbFile,
          backupDir: newCtx.backupDir,
          lock: BackupOperationLock(File(p.join(newCtx.backupDir.path, '.lock'))),
          pauseAndCloseLiveDb: () async => activeNewDb.close(),
          reopenLiveDb: (f) async {
            activeNewDb = SpikeDatabase(f);
            return activeNewDb;
          },
          expectedTenantId: SpikeServer.defaultTenantId,
          expectedStoreId: SpikeServer.defaultStoreId,
          kdfIterations: 1000,
        );
        expect(restoreRes.restoreEpoch, isNot(equals('epoch_0')));
        expect(restoreRes.invalidatedActiveDeviceCount, equals(2)); // DEV-ACT-1, DEV-ACT-2
        expect(restoreRes.preservedRevokedDeviceCount, equals(1)); // DEV-REV-1 kalıcı iptalli

        // Restore edilmiş DB içeriği & epoch kontrolü
        final restoredProd = await (activeNewDb.select(activeNewDb.products)
              ..where((p) => p.id.equals('prod_dr_1')))
            .getSingle();
        expect(restoredProd.name, equals('Felaket Kurtarma Çayı 500g'));
        expect(restoredProd.stock, equals(30000));
        final revDev = await (activeNewDb.select(activeNewDb.devices)
              ..where((d) => d.deviceId.equals('DEV-REV-1')))
            .getSingle();
        expect(revDev.isActive, isFalse);
        await activeNewDb.close();

        // Eski cihaz token'ları restore sonrası yeni PC'de geçersiz (401) kalır
        final reopenedNewDb = SpikeDatabase(newCtx.hubDbFile);
        final serverAfter = SpikeServer(
          db: reopenedNewDb,
          dbFile: newCtx.hubDbFile,
          writeQueue: WriteQueue(),
          backupDirectory: newCtx.backupDir.path,
          pepperManager: newCtx.pepper,
          adminSecret: 'stage5_admin_secret_1',
        );
        final ioAfter = await shelf_io.serve(serverAfter.handler, InternetAddress.loopbackIPv4, 0);
        try {
          for (final staleTok in [oldOwnerTok, oldCashierTok]) {
            final staleResp = await httpClient.get(
              Uri.parse('http://127.0.0.1:${ioAfter.port}/api/v1/products'),
              headers: {'authorization': 'Bearer $staleTok'},
            );
            expect(staleResp.statusCode, equals(401));
          }
        } finally {
          await ioAfter.close(force: true);
          await reopenedNewDb.close();
        }

        // TEST_ONLY Retention Politikası: 7g yerel + 30g günlük / 12 ay + min 1 geçerli kuralı
        final policy = const HubBackupRetentionPolicy();
        final nowUtc = DateTime.utc(2026, 11, 24, 12, 0);
        final candidates = <HubBackupRetentionCandidate>[
          HubBackupRetentionCandidate(
            backupId: 'b_today',
            createdAtUtc: nowUtc.subtract(const Duration(days: 1)),
            isCompletedUploaded: true,
            driveFileId: 'd1',
            localFilePath: '/tmp/b1.mmsbak',
          ),
          HubBackupRetentionCandidate(
            backupId: 'b_10d_local_old',
            createdAtUtc: nowUtc.subtract(const Duration(days: 10)),
            isCompletedUploaded: true,
            driveFileId: 'd2',
            localFilePath: '/tmp/b2.mmsbak',
          ),
          for (var m = 2; m <= 15; m++)
            HubBackupRetentionCandidate(
              backupId: 'b_month_$m',
              createdAtUtc: DateTime.utc(2026, 11 - m, 15),
              isCompletedUploaded: true,
              driveFileId: 'd_month_$m',
            ),
        ];
        final localPlan = policy.evaluateLocalCacheRetention(candidates, nowUtc: nowUtc);
        expect(localPlan.pruneIds, contains('b_10d_local_old'));
        expect(localPlan.retainIds, contains('b_today'));
        final drivePlan = policy.evaluateDriveRetention(candidates, nowUtc: nowUtc);
        expect(drivePlan.retainIds, containsAll(['b_today', 'b_10d_local_old', 'b_month_2']));
        expect(drivePlan.pruneIds, containsAll(['b_month_14', 'b_month_15']));
      } finally {
        httpClient.close();
        await newCtx.ioServer.close(force: true);
      }
    });
  });
}
