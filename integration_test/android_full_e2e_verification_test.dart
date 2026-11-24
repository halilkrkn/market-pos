import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/features/sync/infrastructure/udp_hub_discovery_client.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import 'support/e2e_hub_target_guard.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late LocalDatabaseService dbService;
  late ClientStorageRepository repo;
  late ClientSyncService syncService;
  late File dbFile;
  // GAP-A03 veri güvenliği: E2E testi ASLA uygulamanın gerçek `client_local.db`
  // dosyasını kullanmaz; her koşumda izole geçici bir SQLite dosyası açılır.
  late Directory isolatedDir;
  late String isolatedDbPath;

  const testDeviceId = 'POS-ANDROID-01';
  const configuredToken = String.fromEnvironment('MMS_E2E_DEVICE_TOKEN');
  const configuredHubUrl = String.fromEnvironment('MMS_E2E_HUB_URL');
  // Yerel ağ keşfi üretim Hub'ını bulup ona test satışı gönderebileceğinden
  // yalnızca açık onayla (`MMS_E2E_ALLOW_DISCOVERY=true`) kullanılır.
  const allowDiscovery = bool.fromEnvironment('MMS_E2E_ALLOW_DISCOVERY');
  // S6: Üretim Hub'ına yazmayı teknik olarak engelleyen zorunlu hedef kısıtları.
  const configuredAllowlist = String.fromEnvironment('MMS_E2E_HUB_ALLOWLIST');
  const configuredExpectedHubId = String.fromEnvironment('MMS_E2E_EXPECTED_HUB_ID');
  late final String rawToken;
  late final String hubUrl;

  setUpAll(() async {
    final envToken = Platform.environment['MMS_E2E_DEVICE_TOKEN'] ?? '';
    rawToken = configuredToken.trim().isNotEmpty
        ? configuredToken.trim()
        : envToken.trim();
    if (rawToken.isEmpty) {
      throw StateError(
        'MMS_E2E_DEVICE_TOKEN tanımlı değil. E2E testi çalıştırmadan önce '
        '--dart-define=MMS_E2E_DEVICE_TOKEN=... ile geçici test cihaz tokenı verin.',
      );
    }
    final allowLoopback = !Platform.isAndroid;
    if (configuredHubUrl.trim().isNotEmpty) {
      hubUrl = HubUrlValidator.normalizeAndValidate(
        configuredHubUrl,
        allowLoopback: allowLoopback,
      );
    } else {
      if (!allowDiscovery) {
        throw StateError(
          'MMS_E2E_HUB_URL tanımlı değil. E2E testi yalnızca izole TEST Hub '
          'adresiyle çalışır (--dart-define=MMS_E2E_HUB_URL=https://...). '
          'Yerel ağ keşfi için ayrıca --dart-define=MMS_E2E_ALLOW_DISCOVERY=true verin.',
        );
      }
      final candidates = await const UdpHubDiscoveryClient().discover(
        deviceId: testDeviceId,
      );
      String? discoveredUrl;
      for (final candidate in candidates) {
        final urls = candidate.candidateBaseUrls(allowLoopback: allowLoopback);
        if (urls.isNotEmpty) {
          discoveredUrl = urls.first;
          break;
        }
      }
      if (discoveredUrl == null) {
        throw StateError(
          'MMS_E2E_HUB_URL tanımlı değil ve yerel ağda Hub keşfedilemedi.',
        );
      }
      hubUrl = discoveredUrl;
    }

    // S6: Ağ isteğinden önce adres allowlist + test Hub kimliği kuralı (fail-closed).
    final allowlist = configuredAllowlist.trim().isNotEmpty
        ? configuredAllowlist
        : (Platform.environment['MMS_E2E_HUB_ALLOWLIST'] ?? '');
    final expectedHubId = configuredExpectedHubId.trim().isNotEmpty
        ? configuredExpectedHubId.trim()
        : (Platform.environment['MMS_E2E_EXPECTED_HUB_ID'] ?? '').trim();
    E2eHubTargetGuard.validateTarget(
      hubUrl: hubUrl,
      allowlistCsv: allowlist,
      expectedHubId: expectedHubId,
    );
    // S6: Hiçbir yazma işleminden önce salt-okunur kimlik doğrulaması.
    final transport = HttpSyncTransport();
    await E2eHubTargetGuard.verifyHubIdentity(
      transport: transport,
      hubUrl: hubUrl,
      deviceToken: rawToken,
      expectedHubId: expectedHubId,
    );

    isolatedDir = Directory.systemTemp.createTempSync('mms_e2e_isolated_');
    isolatedDbPath = p.join(isolatedDir.path, 'client_local_e2e.db');
    // S6: Gerçek uygulama veritabanı yolu açılmadan önce reddedilir.
    if (p.equals(isolatedDbPath, LocalDatabaseService.resolveDefaultDatabasePath())) {
      throw StateError('E2E testi gerçek uygulama veritabanını açmaya çalıştı; durduruldu.');
    }
    dbService = await LocalDatabaseService.initialize(customPath: isolatedDbPath);
    repo = dbService.repository;
    dbFile = File(dbService.databasePath);
    expect(
      p.equals(dbFile.path, LocalDatabaseService.resolveDefaultDatabasePath()),
      isFalse,
      reason: 'E2E testi gerçek uygulama veritabanına dokunmamalıdır.',
    );

    // Test cihazı için temiz başlangıç durumu sağla
    await (dbService.database.delete(dbService.database.outboxOperations)..where((o) => o.deviceId.equals(testDeviceId))).go();
    await (dbService.database.delete(dbService.database.clientSyncStates)..where((s) => s.deviceId.equals(testDeviceId))).go();
    await (dbService.database.delete(dbService.database.localSales)..where((s) => s.deviceId.equals(testDeviceId))).go();

    await repo.initializeDevice(testDeviceId);

    syncService = ClientSyncService(
      repository: repo,
      transport: transport,
      deviceId: testDeviceId,
      deviceToken: rawToken,
      hubUrl: hubUrl,
    );
  });

  tearDownAll(() async {
    try {
      await dbService.close();
    } catch (_) {}
    try {
      if (isolatedDir.existsSync()) isolatedDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('MARKET MMS — Uçtan Uca Son Ürün Doğrulama Testi (Android)', () {
    // ------------------------------------------------------------------------
    // 1. Ürün ve kategori oluşturma, düzenleme ve silme (CRUD)
    // ------------------------------------------------------------------------
    late LocalCategory catFood;
    late LocalProduct prodLocal;

    testWidgets('1. Ürün ve Kategori Oluşturma, Düzenleme ve Silme', (tester) async {
      // Kategori oluştur
      catFood = await repo.createCategory(name: 'Temel Gıda E2E');
      expect(catFood.id, isNotEmpty);
      expect(catFood.name, 'Temel Gıda E2E');

      // Ürün oluştur (350.00 TL = 35000 kuruş, 20 adet = 20000 milli)
      prodLocal = await repo.createProduct(
        name: 'Sızma Zeytinyağı 1L E2E',
        price: 35000,
        barcode: '8690001009999',
        categoryId: catFood.id,
        initialStock: 20000,
      );

      expect(prodLocal.id, isNotEmpty);
      expect(prodLocal.price, 35000);
      expect(prodLocal.stock, 20000);

      // Ürün güncelleme (Fiyat 375.00 TL = 37500 kuruş)
      await repo.updateProduct(
        id: prodLocal.id,
        name: 'Sızma Zeytinyağı 1L E2E (Yeni Etiket)',
        price: 37500,
        priceChangeReason: 'Üretici Zammı (E2E Test)',
      );

      final updated = await repo.getProductById(prodLocal.id);
      expect(updated, isNotNull);
      expect(updated!.price, 37500);
      expect(updated.name, 'Sızma Zeytinyağı 1L E2E (Yeni Etiket)');

      // Fiyat geçmişi kontrolü
      final priceHistories = await repo.getPriceHistory(prodLocal.id);
      expect(priceHistories, isNotEmpty);
      expect(priceHistories.any((ph) => ph.newPrice == 37500), isTrue);

      // Ürünü pasife alma (Soft delete)
      await repo.deactivateProduct(prodLocal.id);
      final deactivated = await repo.getProductById(prodLocal.id);
      expect(deactivated!.isActive, isFalse);

      // Tekrar aktifleştirme
      await repo.updateProduct(id: prodLocal.id, isActive: true);
      final reactivated = await repo.getProductById(prodLocal.id);
      expect(reactivated!.isActive, isTrue);
    });

    // ------------------------------------------------------------------------
    // 2. Barkodla ürün bulma ve sepete ekleme
    // ------------------------------------------------------------------------
    late LocalProduct syncProduct;

    testWidgets('2. Barkodla Ürün Bulma ve Sepete Ekleme', (tester) async {
      // Master Hub'dan resmi katalog ürünlerini çek (prod_cola_330, prod_bread_stone, prod_milk_1l)
      final pullCount = await syncService.syncProducts();
      expect(pullCount, greaterThanOrEqualTo(3), reason: 'Master Hub ürünleri çekilmelidir');

      // Çekilen Kola ürününü bul
      final foundCola = await repo.getProductById('prod_cola');
      expect(foundCola, isNotNull);
      expect(foundCola!.name, 'Kutu Kola 330ml');
      expect(foundCola.price, 2500); // 25.00 TL
      syncProduct = foundCola;

      // Birincil barkod ile arama (869000000001)
      var foundByBarcode = await repo.getProductByBarcode('869000000001');
      expect(foundByBarcode, isNotNull);
      expect(foundByBarcode!.id, 'prod_cola');

      // İkinci alternatif barkod ekleme
      await repo.addProductBarcode(
        productId: 'prod_cola',
        barcode: '869000000099',
        isPrimary: false,
      );

      // Alternatif barkod ile arama
      foundByBarcode = await repo.getProductByBarcode('869000000099');
      expect(foundByBarcode, isNotNull);
      expect(foundByBarcode!.id, 'prod_cola');

      // Sepet öğesi oluşturma (2 adet)
      final cartItem = CartItemInput.units(syncProduct.id, 2);
      expect(cartItem.quantity, 2000);
    });

    // ------------------------------------------------------------------------
    // 3 & 4. Nakit ve kartlı satış & Satış sonrası stok güncelleme
    // ------------------------------------------------------------------------
    late String saleCashId;
    late String saleCardId;

    testWidgets('3 & 4. Nakit ve Kartlı Satış & Stok Güncelleme', (tester) async {
      final initialProduct = await repo.getProductById(syncProduct.id);
      final initialStock = initialProduct!.stock; // 100000 milli (100 adet)

      // Satış 1: NAKİT Satış (2 adet Kola)
      final resCash = await repo.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CASH',
        items: [
          CartItemInput.units(syncProduct.id, 2),
        ],
      );
      saleCashId = resCash.saleId;
      expect(resCash.totalAmount, 5000); // 2 * 2500 kuruş

      // Satış 2: KARTLI Satış (3 adet Kola)
      final resCard = await repo.createOfflineSale(
        deviceId: testDeviceId,
        paymentMethod: 'CARD',
        items: [
          CartItemInput.units(syncProduct.id, 3),
        ],
      );
      saleCardId = resCard.saleId;
      expect(resCard.totalAmount, 7500); // 3 * 2500 kuruş

      // Satış sonrası stok kontrolü (100000 - 2000 - 3000 = 95000)
      final postSaleProduct = await repo.getProductById(syncProduct.id);
      expect(postSaleProduct!.stock, initialStock - 5000);
      expect(postSaleProduct.stock, 95000);

      // Stok hareketleri kontrolü
      final movements = await repo.getStockMovements(productId: syncProduct.id);
      expect(movements.length, greaterThanOrEqualTo(2));
      expect(movements.any((m) => m.referenceId == saleCashId && m.movementType == 'SATIS'), isTrue);
      expect(movements.any((m) => m.referenceId == saleCardId && m.movementType == 'SATIS'), isTrue);
    });

    // ------------------------------------------------------------------------
    // 5. Satış geçmişi ve fiş detayları
    // ------------------------------------------------------------------------
    testWidgets('5. Satış Geçmişi ve Fiş Detayları', (tester) async {
      final sales = await repo.getSalesHistory();
      expect(sales.length, greaterThanOrEqualTo(2));

      // Nakit fiş detayı
      final cashDetail = await repo.getSaleDetail(saleCashId);
      expect(cashDetail, isNotNull);
      expect(cashDetail!.sale.paymentMethod, 'CASH');
      expect(cashDetail.sale.totalAmount, 5000);
      expect(cashDetail.items.first.quantity, 2000);
      expect(cashDetail.items.first.unitPrice, 2500);

      // Kartlı fiş detayı
      final cardDetail = await repo.getSaleDetail(saleCardId);
      expect(cardDetail, isNotNull);
      expect(cardDetail!.sale.paymentMethod, 'CARD');
      expect(cardDetail.sale.totalAmount, 7500);
      expect(cardDetail.items.first.quantity, 3000);
    });

    // ------------------------------------------------------------------------
    // 6. Tam satış iptali ve kısmi iade
    // ------------------------------------------------------------------------
    testWidgets('6. Tam Satış İptali ve Kısmi İade', (tester) async {
      // Nakit satışı TAM İPTAL et (2 adet stoğa geri döner)
      await repo.cancelSale(
        saleId: saleCashId,
        reason: 'Müşteri vazgeçti (E2E Test)',
        deviceId: testDeviceId,
      );

      final cancelledDetail = await repo.getSaleDetail(saleCashId);
      expect(cancelledDetail!.sale.status, 'CANCELLED');

      var product = await repo.getProductById(syncProduct.id);
      expect(product!.stock, 97000); // 95000 + 2000

      // Kartlı satıştan 1 adet KISMİ İADE yap (1 adet satılabilir stoğa geri döner)
      final cardDetail = await repo.getSaleDetail(saleCardId);
      final saleItemId = cardDetail!.items.first.id;

      final refundId = await repo.refundSale(
        saleId: saleCardId,
        deviceId: testDeviceId,
        reason: 'Fazla ürün (E2E Test)',
        items: [
          RefundItemInput(
            saleItemId: saleItemId,
            quantity: 1000,
            productCondition: 'SELLABLE',
          ),
        ],
      );

      expect(refundId, isNotEmpty);
      final refundedDetail = await repo.getSaleDetail(saleCardId);
      expect(refundedDetail!.sale.status, 'PARTIALLY_REFUNDED'); // Kısmi iade sonrası gerçek sözleşme durumu
      expect(refundedDetail.totalRefundedAmount, 2500);
      expect(refundedDetail.refunds, isNotEmpty);

      product = await repo.getProductById(syncProduct.id);
      expect(product!.stock, 98000); // 97000 + 1000
    });

    // ------------------------------------------------------------------------
    // 7. Outbox FIFO ve idempotency (Yerel Kuyruk Kontrolü)
    // ------------------------------------------------------------------------
    testWidgets('7. Outbox FIFO ve Idempotency Kontrolleri', (tester) async {
      final outboxEntries = await (dbService.database.select(dbService.database.outboxOperations)
            ..where((o) => o.deviceId.equals(testDeviceId))
            ..orderBy([(o) => OrderingTerm.asc(o.clientSeq)]))
          .get();

      // En az 4 operasyon olmalı: SALE_CREATE (Nakit), SALE_CREATE (Kart), SALE_CANCEL, SALE_REFUND
      expect(outboxEntries.length, greaterThanOrEqualTo(4));

      // Monotonik clientSeq doğrulaması (1, 2, 3, 4)
      for (var i = 0; i < outboxEntries.length; i++) {
        expect(outboxEntries[i].clientSeq, i + 1);
        expect(outboxEntries[i].status, 'PENDING');
        expect(outboxEntries[i].payloadHash, isNotEmpty);
      }

      expect(outboxEntries[0].operationType, 'SALE_CREATE');
      expect(outboxEntries[1].operationType, 'SALE_CREATE');
      expect(outboxEntries[2].operationType, 'SALE_CANCEL');
      expect(outboxEntries[3].operationType, 'SALE_REFUND');
    });

    // ------------------------------------------------------------------------
    // 8. Windows Local Master Hub ile Android Gerçek Senkronizasyonu (CANLI AĞ)
    // ------------------------------------------------------------------------
    testWidgets('8. Windows Local Master Hub ile Android Gerçek Senkronizasyonu (CANLI AĞ)', (tester) async {
      // Outbox bekleyen işlemleri (2 Satış, 1 İptal, 1 İade) canlı Master Hub'a aktar
      final syncResult = await syncService.syncPendingOutbox();
      expect(syncResult.syncedCount, greaterThanOrEqualTo(4), reason: 'En az 4 operasyon senkronize olmalı');
      expect(syncResult.retriedCount, 0);
      expect(syncResult.permanentFailedCount, 0);

      // Yerel Outbox'ta tüm işlemlerin SYNCED olduğunu doğrula
      final outboxAfter = await (dbService.database.select(dbService.database.outboxOperations)
            ..where((o) => o.deviceId.equals(testDeviceId)))
          .get();
      expect(outboxAfter.every((o) => o.status == 'SYNCED'), isTrue);

      // Idempotency Doğrulaması - Tekrar sync çalıştırıldığında mükerrer kayıt oluşmaz
      final repeatSync = await syncService.syncPendingOutbox();
      expect(repeatSync.syncedCount, 0);
      expect(repeatSync.hasMore, isFalse);
    });

    // ------------------------------------------------------------------------
    // 9. Uygulama yeniden başlatıldığında yerel verilerin korunması
    // ------------------------------------------------------------------------
    testWidgets('9. Uygulama Yeniden Başlatıldığında Yerel Verilerin Korunması', (tester) async {
      // 1. Veritabanını kapat (Uygulamanın sonlanması simülasyonu)
      await dbService.close();

      // 2. Yeniden başlat (aynı izole test DB yolu)
      dbService = await LocalDatabaseService.initialize(customPath: isolatedDbPath);
      repo = dbService.repository;

      // Ürünler korunmuş mu?
      final product = await repo.getProductById(syncProduct.id);
      expect(product, isNotNull);
      expect(product!.price, 2500);
      expect(product.stock, 98000);

      // Satışlar korunmuş mu?
      final sales = await repo.getSalesHistory();
      expect(sales.length, greaterThanOrEqualTo(2));

      // Outbox SYNCED durumları ve sayaç korunmuş mu?
      final syncState = await (dbService.database.select(dbService.database.clientSyncStates)
            ..where((s) => s.deviceId.equals(testDeviceId)))
          .getSingle();
      expect(syncState.currentClientSeq, greaterThanOrEqualTo(4));

      final outbox = await (dbService.database.select(dbService.database.outboxOperations)
            ..where((o) => o.deviceId.equals(testDeviceId)))
          .get();
      expect(outbox.every((o) => o.status == 'SYNCED'), isTrue);
    });

    // ------------------------------------------------------------------------
    // 10. Veritabanı yedekleme ve geri yükleme (S5A-4 Standardı)
    // ------------------------------------------------------------------------
    testWidgets('10. Veritabanı Yedekleme ve Geri Yükleme (S5A-4)', (tester) async {
      final appDocDir = File(dbService.databasePath).parent;
      final backupDir = Directory(p.join(appDocDir.path, 'backups_e2e_test'));
      if (backupDir.existsSync()) {
        try {
          backupDir.deleteSync(recursive: true);
        } catch (_) {}
      }
      backupDir.createSync(recursive: true);

      final storageProvider = LocalStorageProvider(backupDir);
      const backupPassword = 'MmsStrongBackupPassword!2026';

      // 1. S5A-4 Yedek Oluştur (Gerçek VACUUM INTO + PBKDF2 + AES-256-CBC + HMAC-SHA256)
      final backupRes = await DatabaseBackupEngine.createBackup(
        liveDbFile: dbFile,
        executeVacuumInto: (path) async {
          final snapshotFile = File(path);
          if (snapshotFile.existsSync()) snapshotFile.deleteSync();
          final escaped = path.replaceAll("'", "''");
          await dbService.database.customStatement("VACUUM INTO '$escaped';");
        },
        deviceId: testDeviceId,
        tenantId: 'TENANT_DEFAULT',
        storeId: 'STORE_DEFAULT',
        databaseType: DatabaseType.mobileLocal,
        schemaVersion: dbService.database.schemaVersion,
        appVersion: '1.0.0',
        backupPassword: backupPassword,
        storageProvider: storageProvider,
        kdfIterations: 5000, // Hızlı test için 5000 iterasyon
      );

      expect(backupRes.backupId, isNotEmpty);
      final backupFile = await storageProvider.getBackupFile(backupRes.backupId);
      expect(backupFile, isNotNull);
      expect(await backupFile.exists(), isTrue);

      // Sihirli Başlık Kontrolü (MMSBAK01)
      final bytes = await backupFile.readAsBytes();
      final header = ascii.decode(bytes.sublist(0, 8));
      expect(header, 'MMSBAK01');

      // 2. Manipülasyon ve HMAC Koruma Testi: 1 bayt değiştir
      final corruptedBytes = Uint8List.fromList(bytes);
      corruptedBytes[corruptedBytes.length - 1] ^= 0xFF; // Son baytı manipüle et

      expect(
        () => BackupCryptoService.verifyAndDecryptPackage(
          packageBytes: corruptedBytes,
          password: backupPassword,
        ),
        throwsA(isA<BackupCryptoException>()),
        reason: 'Manipüle edilmiş yedek HMAC doğrulamasıyla reddedilmelidir',
      );

      // 3. Sağlam yedekten şifre çözme doğrulaması
      final decrypted = BackupCryptoService.verifyAndDecryptPackage(
        packageBytes: bytes,
        password: backupPassword,
      );
      expect(decrypted.manifest.backupId, backupRes.backupId);
      expect(decrypted.databaseBytes, isNotEmpty);

      // Çözülen veritabanının SQLite bütünlük kontrolü
      final tempRestoredDbFile = File(p.join(appDocDir.path, 'temp_restored_verify.db'));
      await tempRestoredDbFile.writeAsBytes(decrypted.databaseBytes);
      final testSqlite = sqlite.sqlite3.open(tempRestoredDbFile.path);
      final integrityRes = testSqlite.select('PRAGMA integrity_check;');
      expect(integrityRes.first.columnAt(0).toString().toLowerCase(), 'ok');
      testSqlite.close();
      tempRestoredDbFile.deleteSync();
    });
  });
}
