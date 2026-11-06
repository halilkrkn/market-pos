import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:spike_01_backend/security/pepper_manager.dart';
import 'package:spike_01_backend/security/token_manager.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

void main() {
  late Directory tempDir;
  late String masterDbPath;
  late String pepperPath;
  late String clientDbPath;
  late String exePath;
  late ClientDatabase clientDb;
  late ClientStorageRepository clientRepo;
  late ClientSyncService syncService;

  const testPort = 8945;
  const hubUrl = 'http://127.0.0.1:$testPort';
  const testDeviceId = 'DEV_WIN_LIVE';
  const rawToken = 'test_token_live_secret_9988';

  Process? backendProcess;

  Future<Process> startBackend() async {
    final proc = await Process.start(
      exePath,
      ['--port=$testPort', '--db-path=$masterDbPath', '--pepper-file=$pepperPath'],
      mode: ProcessStartMode.normal,
    );

    proc.stderr.transform(utf8.decoder).listen((e) => stderr.writeln('[BACKEND ERR] $e'));
    proc.stdout.transform(utf8.decoder).listen((o) => stdout.writeln('[BACKEND OUT] $o'));

    // Sağlık kontrolü ile açılmasını bekle (max 5 sn)
    final sw = Stopwatch()..start();
    var isUp = false;
    while (sw.elapsedMilliseconds < 5000) {
      try {
        final res = await http.get(Uri.parse('$hubUrl/health')).timeout(const Duration(milliseconds: 300));
        if (res.statusCode == 200) {
          isUp = true;
          break;
        }
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    if (!isUp) {
      proc.kill(ProcessSignal.sigkill);
      throw StateError('Canlı backend $testPort portunda 5 saniye içinde açılamadı!');
    }

    return proc;
  }

  Future<void> stopBackend(Process? proc) async {
    if (proc == null) return;
    proc.kill(ProcessSignal.sigkill);
    await proc.exitCode.timeout(const Duration(seconds: 3), onTimeout: () => -1);
  }

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('mms_live_hub_test_');
    masterDbPath = p.normalize(p.join(tempDir.path, 'market_master.db'));
    pepperPath = p.normalize(p.join(tempDir.path, 'pepper.key'));
    clientDbPath = p.normalize(p.join(tempDir.path, 'client_local.db'));

    final pepperManager = PepperManager(File(pepperPath));
    pepperManager.initialize();
    final pepper = pepperManager.pepper;

    final salt = TokenManager.generateSalt();
    final tokenHash = TokenManager.hashToken(
      rawToken: rawToken,
      salt: salt,
      pepper: pepper,
    );

    // Backend EXE yolunu bul (test_spikes/spike_01_backend/build/mms_backend.exe)
    final rootDir = Directory.current.path;
    exePath = p.normalize(p.join(rootDir, '..', '..', 'test_spikes', 'spike_01_backend', 'build', 'mms_backend.exe'));
    if (!File(exePath).existsSync()) {
      exePath = p.normalize(p.join(rootDir, 'test_spikes', 'spike_01_backend', 'build', 'mms_backend.exe'));
    }

    expect(File(exePath).existsSync(), isTrue, reason: 'mms_backend.exe derlenmiş olmalı');

    // Master SQLite veritabanını oluştur ve başlangıç tablolarını/cihazını hazırla
    final rawMaster = sqlite3.open(masterDbPath);
    rawMaster.execute('''
      PRAGMA journal_mode = WAL;
      PRAGMA synchronous = FULL;
      
      CREATE TABLE IF NOT EXISTS products (
        id TEXT NOT NULL PRIMARY KEY,
        barcode TEXT NOT NULL,
        name TEXT NOT NULL,
        price INTEGER NOT NULL,
        price_version_id TEXT NOT NULL DEFAULT 'pv_init',
        stock INTEGER NOT NULL,
        stock_unit TEXT NOT NULL DEFAULT 'adet',
        pricing_unit TEXT NOT NULL DEFAULT 'adet',
        conversion_factor_numerator INTEGER NOT NULL DEFAULT 1,
        conversion_factor_denominator INTEGER NOT NULL DEFAULT 1,
        is_active INTEGER NOT NULL DEFAULT 1,
        updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      );

      CREATE TABLE IF NOT EXISTS sales (
        id TEXT NOT NULL PRIMARY KEY,
        device_id TEXT NOT NULL,
        client_seq INTEGER NOT NULL,
        total_amount INTEGER NOT NULL,
        payment_method TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      );

      CREATE TABLE IF NOT EXISTS sale_items (
        id TEXT NOT NULL PRIMARY KEY,
        sale_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price INTEGER NOT NULL,
        total_price INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS stock_movements (
        id TEXT NOT NULL PRIMARY KEY,
        product_id TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit TEXT NOT NULL DEFAULT 'adet',
        movement_type TEXT NOT NULL,
        reference_id TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      );

      CREATE TABLE IF NOT EXISTS product_price_histories (
        id TEXT NOT NULL PRIMARY KEY,
        product_id TEXT NOT NULL,
        price INTEGER NOT NULL,
        valid_from INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        valid_until INTEGER,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      );

      CREATE TABLE IF NOT EXISTS processed_operations (
        operation_id TEXT NOT NULL PRIMARY KEY,
        device_id TEXT NOT NULL,
        idempotency_key TEXT NOT NULL UNIQUE,
        result_payload TEXT NOT NULL,
        processed_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      );

      CREATE TABLE IF NOT EXISTS devices (
        device_id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        token_hash TEXT NOT NULL,
        salt TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        is_confirmed INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
        last_used_at INTEGER,
        expires_at INTEGER,
        last_product_sync_at INTEGER,
        role TEXT NOT NULL DEFAULT 'CASHIER'
      );

      CREATE TABLE IF NOT EXISTS device_audit_logs (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        action TEXT NOT NULL,
        details TEXT,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      );

      CREATE TABLE IF NOT EXISTS product_sync_sessions (
        id TEXT NOT NULL PRIMARY KEY,
        device_id TEXT NOT NULL,
        product_count INTEGER NOT NULL,
        synced_at INTEGER NOT NULL,
        is_acknowledged INTEGER NOT NULL DEFAULT 0,
        acknowledged_at INTEGER,
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
      );
    ''');

    // Master DB'ye tartılı/kesirli ürünleri ekle
    // Dana Kıyma: 200 TL/kg (20000 kuruş), Stok: 100 kg (100000 milli-birim)
    // Çiftlik Sütü: 40 TL/L (4000 kuruş), Stok: 50 L (50000 milli-birim)
    rawMaster.execute('''
      INSERT INTO products (id, barcode, name, price, stock, stock_unit, pricing_unit, conversion_factor_numerator, conversion_factor_denominator, is_active) VALUES
        ('prod_live_meat', '8690011', 'Canlı Hub Dana Kıyma', 20000, 100000, 'kg', 'kg', 1, 1, 1),
        ('prod_live_milk', '8690022', 'Canlı Hub Çiftlik Sütü', 4000, 50000, 'l', 'l', 1, 1, 1);
    ''');

    // Cihazı doğrulanmış ve aktif olarak ekle
    rawMaster.execute('''
      INSERT INTO devices (device_id, name, token_hash, salt, is_active, is_confirmed) VALUES
        ('$testDeviceId', 'Canlı Windows Test Cihazı', '$tokenHash', '$salt', 1, 1);
    ''');

    rawMaster.dispose();

    // İstemci yerel veritabanını hazırla
    clientDb = ClientDatabase(File(clientDbPath));
    clientRepo = ClientStorageRepository(clientDb);
    syncService = ClientSyncService(
      repository: clientRepo,
      transport: HttpSyncTransport(),
      deviceId: testDeviceId,
      deviceToken: rawToken,
      hubUrl: hubUrl,
      baseBackoff: const Duration(milliseconds: 100),
      maxBackoff: const Duration(seconds: 1),
    );
  });

  tearDownAll(() async {
    await stopBackend(backendProcess);
    await clientDb.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('Tam Entegrasyon: Kesirli Miktar Ürün Senkronizasyonu -> Servis Kapanması -> 0.5 kg ve 1.25 L Çevrimdışı Satış -> Servis Açılması -> Canlı API Aktarımı -> Idempotent Replay', () async {
    // -------------------------------------------------------------------------
    // ADIM 1: Canlı Backend Başlat ve Ürünleri İstemciye Senkronize Et
    // -------------------------------------------------------------------------
    backendProcess = await startBackend();

    final syncCount = await syncService.syncProducts();
    expect(syncCount, greaterThanOrEqualTo(2));

    // İstemci yerel cache'inde ürünlerin olduğunu doğrula
    final localMeat = await (clientDb.select(clientDb.localProducts)..where((p) => p.id.equals('prod_live_meat'))).getSingle();
    final localMilk = await (clientDb.select(clientDb.localProducts)..where((p) => p.id.equals('prod_live_milk'))).getSingle();

    expect(localMeat.price, equals(20000));
    expect(localMeat.stock, equals(100000)); // 100.000 kg
    expect(localMilk.price, equals(4000));
    expect(localMilk.stock, equals(50000)); // 50.000 L

    // -------------------------------------------------------------------------
    // ADIM 2: Servisi Durdur (Windows Service Kapandı / Offline Mod)
    // -------------------------------------------------------------------------
    await stopBackend(backendProcess);
    backendProcess = null;

    // Satış 1: 0.5 kg Dana Kıyma (200 TL/kg = 20000 kuruş) -> 10000 kuruş (100 TL)
    final sale1 = await clientRepo.createOfflineSale(
      deviceId: testDeviceId,
      paymentMethod: 'CASH',
      items: [
        CartItemInput.fractional('prod_live_meat', 500), // 0.500 kg
      ],
    );
    expect(sale1.clientSeq, equals(1));
    expect(sale1.totalAmount, equals(10000)); // 100.00 TL

    // Satış 2: 1.25 L Çiftlik Sütü (40 TL/L = 4000 kuruş) -> 5000 kuruş (50 TL)
    final sale2 = await clientRepo.createOfflineSale(
      deviceId: testDeviceId,
      paymentMethod: 'CREDIT_CARD',
      items: [
        CartItemInput.fractional('prod_live_milk', 1250), // 1.250 L
      ],
    );
    expect(sale2.clientSeq, equals(2));
    expect(sale2.totalAmount, equals(5000)); // 50.00 TL

    // İstemci yerel stokları anında güncellenmiştir (Milli-birim)
    final updatedLocalMeat = await (clientDb.select(clientDb.localProducts)..where((p) => p.id.equals('prod_live_meat'))).getSingle();
    final updatedLocalMilk = await (clientDb.select(clientDb.localProducts)..where((p) => p.id.equals('prod_live_milk'))).getSingle();
    expect(updatedLocalMeat.stock, equals(99500)); // 100000 - 500 = 99.500 kg
    expect(updatedLocalMilk.stock, equals(48750)); // 50000 - 1250 = 48.750 L

    // İstemci Outbox'ında 2 adet PENDING işlem vardır
    final pendingOps = await clientRepo.getUnsyncedOutboxOperations(testDeviceId);
    expect(pendingOps.length, equals(2));

    // Servis kapalıyken senkronizasyon denenirse: Ağ hatası alır, RETRY olur, satışlar korunur
    final offlineSyncResult = await syncService.syncPendingOutbox();
    expect(offlineSyncResult.syncedCount, equals(0));
    expect(offlineSyncResult.retriedCount, equals(1)); // seq 1 retry'a geçti

    // -------------------------------------------------------------------------
    // ADIM 3: Servis Yeniden Başlatıldı (Online Mod)
    // -------------------------------------------------------------------------
    backendProcess = await startBackend();

    // Bekleme süresi sonrasında (simüle zaman) senkronizasyon motorunu çalıştır
    final futureTime = DateTime.now().add(const Duration(seconds: 3));
    final onlineSyncResult = await syncService.syncPendingOutbox(now: futureTime);

    expect(onlineSyncResult.syncedCount, equals(2)); // seq 1 ve seq 2 başarıyla aktarıldı
    expect(onlineSyncResult.retriedCount, equals(0));
    expect(onlineSyncResult.permanentFailedCount, equals(0));
    expect(onlineSyncResult.hasMore, isFalse);

    // İstemci tarafında her iki işlemin SYNCED olduğunu doğrula
    final syncedOps = await clientDb.select(clientDb.outboxOperations).get();
    for (final op in syncedOps) {
      expect(op.status, equals('SYNCED'));
      expect(op.acknowledgedAt, isNotNull);
    }

    final clientState = await clientRepo.getSyncState(testDeviceId);
    expect(clientState!.lastSyncedSeq, equals(2));

    // -------------------------------------------------------------------------
    // ADIM 4: Master DB'de Verilerin Doğrulanması (Kesirli Satış, Kalemler ve Stoklar)
    // -------------------------------------------------------------------------
    final rawMaster = sqlite3.open(masterDbPath);

    final masterSales = rawMaster.select("SELECT * FROM sales WHERE device_id = '$testDeviceId' ORDER BY client_seq ASC;");
    expect(masterSales.length, equals(2));
    expect(masterSales[0]['client_seq'], equals(1));
    expect(masterSales[0]['total_amount'], equals(10000)); // 100 TL
    expect(masterSales[1]['client_seq'], equals(2));
    expect(masterSales[1]['total_amount'], equals(5000)); // 50 TL

    // Master DB'deki satır kalemleri ve kesirli miktarları doğrula
    final masterItems = rawMaster.select("SELECT * FROM sale_items ORDER BY id ASC;");
    expect(masterItems.length, equals(2));
    final meatItem = masterItems.firstWhere((i) => i['product_id'] == 'prod_live_meat');
    expect(meatItem['quantity'], equals(500)); // 0.5 kg = 500 milli-birim
    expect(meatItem['unit_price'], equals(20000)); // 200 TL/kg
    expect(meatItem['total_price'], equals(10000)); // 100 TL

    final milkItem = masterItems.firstWhere((i) => i['product_id'] == 'prod_live_milk');
    expect(milkItem['quantity'], equals(1250)); // 1.25 L = 1250 milli-birim
    expect(milkItem['unit_price'], equals(4000)); // 40 TL/L
    expect(milkItem['total_price'], equals(5000)); // 50 TL

    // Master DB'deki stok hareketleri ve güncel stokları doğrula
    final masterMeatStock = rawMaster.select("SELECT stock FROM products WHERE id = 'prod_live_meat';").first['stock'] as int;
    final masterMilkStock = rawMaster.select("SELECT stock FROM products WHERE id = 'prod_live_milk';").first['stock'] as int;
    expect(masterMeatStock, equals(99500)); // 100000 - 500 = 99.5 kg
    expect(masterMilkStock, equals(48750)); // 50000 - 1250 = 48.75 L

    final masterOps = rawMaster.select("SELECT * FROM processed_operations WHERE device_id = '$testDeviceId';");
    expect(masterOps.length, equals(2));
    final idempotencyKeys = masterOps.map((r) => r['idempotency_key']).toSet();
    expect(idempotencyKeys, contains('$testDeviceId:1'));
    expect(idempotencyKeys, contains('$testDeviceId:2'));

    // -------------------------------------------------------------------------
    // ADIM 5: ACK Kaybı ve Tekrar Gönderim (Idempotent Replay Doğrulaması)
    // -------------------------------------------------------------------------
    // seq 2 işlemini istemcide yapay olarak PENDING durumuna geri al (ACK kaybı simülasyonu)
    await (clientDb.update(clientDb.outboxOperations)..where((o) => o.operationId.equals(sale2.operationId))).write(
          const OutboxOperationsCompanion(
            status: Value('PENDING'),
            acknowledgedAt: Value(null),
          ),
        );

    // İstemci seq 2'yi tekrar gönderir
    final replayResult = await syncService.syncPendingOutbox();
    expect(replayResult.syncedCount, equals(1)); // Tekrar gönderilen işlem başarılı ACK aldı

    // Master DB'de üçüncü bir satış veya stok düşümü OLMADIĞINI doğrula
    final masterSalesAfterReplay = rawMaster.select("SELECT * FROM sales WHERE device_id = '$testDeviceId';");
    expect(masterSalesAfterReplay.length, equals(2)); // Satış sayısı halen 2!

    final masterMeatStockAfter = rawMaster.select("SELECT stock FROM products WHERE id = 'prod_live_meat';").first['stock'] as int;
    final masterMilkStockAfter = rawMaster.select("SELECT stock FROM products WHERE id = 'prod_live_milk';").first['stock'] as int;
    expect(masterMeatStockAfter, equals(99500)); // Stok değişmedi
    expect(masterMilkStockAfter, equals(48750)); // Stok değişmedi

    rawMaster.dispose();
  });
}
