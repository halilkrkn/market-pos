import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../lib/db/database.dart';
import '../lib/security/pepper_manager.dart';
import '../lib/security/token_manager.dart';

void main() {
  late Directory tempDir;
  late String dbPath;
  late String exePath;
  late String pepperPath;
  late PepperManager pepperManager;
  const port = 8997;
  const adminToken = 'token_admin_test_lifecycle';
  const adminSecret = 'sec_shutdown_test_secret_1234';

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    tempDir = await Directory.systemTemp.createTemp('mms_graceful_shutdown_suite_');
    dbPath = p.join(tempDir.path, 'suite_test.db');
    pepperPath = p.join(tempDir.path, 'pepper.dpapi');

    pepperManager = PepperManager(File(pepperPath));
    pepperManager.initialize();

    exePath = p.normalize(p.join(Directory.current.path, 'build', 'spike_service_s2.exe'));
    if (!File(exePath).existsSync()) {
      exePath = p.normalize(p.join(Directory.current.path, 'build', 'spike_service.exe'));
    }

    if (!File(exePath).existsSync()) {
      throw StateError('spike_service executable bulunamadı: $exePath');
    }

    // İlk tohumlama
    final setupDb = SpikeDatabase(File(dbPath));
    await setupDb.customStatement('PRAGMA journal_mode = WAL;');
    await setupDb.customStatement('PRAGMA foreign_keys = ON;');
    await setupDb.into(setupDb.products).insert(
          ProductsCompanion(
            id: const Value('prod_cola'),
            barcode: const Value('869000000001'),
            name: const Value('Kutu Kola 330ml'),
            price: const Value(2500),
            stock: const Value(500000),
          ),
        );

    final salt = TokenManager.generateSalt();
    final hash = TokenManager.hashToken(
      rawToken: adminToken,
      salt: salt,
      pepper: pepperManager.pepper,
    );

    await setupDb.into(setupDb.devices).insert(
          DevicesCompanion(
            deviceId: const Value('DEV_ADMIN'),
            name: const Value('Admin Cihazı'),
            tokenHash: Value(hash),
            salt: Value(salt),
            isActive: const Value(true),
          ),
        );
    await setupDb.close();
  });

  tearDownAll(() async {
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Future<Process> spawnBackend() async {
    final process = await Process.start(
      exePath,
      ['--port=$port', '--db-path=$dbPath', '--pepper-file=$pepperPath', '--admin-secret=$adminSecret'],
      mode: ProcessStartMode.normal,
    );

    // /health kontrolü (Maks 5 sn)
    var isUp = false;
    for (int i = 0; i < 30; i++) {
      try {
        final res = await http.get(Uri.parse('http://127.0.0.1:$port/health'));
        if (res.statusCode == 200) {
          isUp = true;
          break;
        }
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
    if (!isUp) {
      process.kill();
      throw StateError('Sunucu ayağa kalkamadı.');
    }
    return process;
  }

  test('1. Graceful Shutdown: Süreç kaynakları temizleyip 15 sn yerine < 1.5 sn içinde kendiliğinden sonlanmalıdır', () async {
    print('\n[TEST 1] Graceful Shutdown Başlatılıyor...');
    final process = await spawnBackend();

    final sw = Stopwatch()..start();
    final res = await http.post(
      Uri.parse('http://127.0.0.1:$port/api/v1/admin/shutdown'),
      headers: {
        'content-type': 'application/json',
        'x-admin-secret': adminSecret,
      },
    );
    expect(res.statusCode, equals(200));

    final exitCode = await process.exitCode.timeout(const Duration(seconds: 4));
    sw.stop();

    print('[TEST 1] Kapanış tamamlandı: ${sw.elapsedMilliseconds} ms | Exit code: $exitCode');
    expect(exitCode, equals(0));
    expect(sw.elapsedMilliseconds, lessThan(1500), reason: 'Kapanma süresi 1.5 saniyenin altında olmalıdır!');
  });

  test('2. Tekrarlı Stop/Start Döngüsü: 3 ardışık döngüde hızlı başlama, hızlı durma ve veri tutarlılığı', () async {
    print('\n[TEST 2] 3 Ardışık Stop/Start Döngü Testi Başlatılıyor...');

    for (int cycle = 1; cycle <= 3; cycle++) {
      print('\n--- [Döngü $cycle / 3] Başlatılıyor ---');
      final proc = await spawnBackend();
      print('[Döngü $cycle] Süreç ayağa kalktı (PID: ${proc.pid}). /health kontrol ediliyor...');

      final healthRes = await http.get(Uri.parse('http://127.0.0.1:$port/health'));
      expect(healthRes.statusCode, equals(200));

      // 1 satış işlemi yap
      final saleRes = await http.post(
        Uri.parse('http://127.0.0.1:$port/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $adminToken',
        },
        body: jsonEncode({
          'operation_id': 'op_cycle_$cycle',
          'client_seq': cycle,
          'total_amount': 2500,
          'payment_method': 'CASH',
          'items': [
            {'product_id': 'prod_cola', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500}
          ],
        }),
      );
      expect(saleRes.statusCode, equals(201));
      print('[Döngü $cycle] Satış tamamlandı (Tx $cycle).');

      // Shutdown gönder ve süreyi ölç
      final sw = Stopwatch()..start();
      final shutRes = await http.post(
        Uri.parse('http://127.0.0.1:$port/api/v1/admin/shutdown'),
        headers: {
          'content-type': 'application/json',
          'x-admin-secret': adminSecret,
        },
      );
      expect(shutRes.statusCode, equals(200));

      final exitCode = await proc.exitCode.timeout(const Duration(seconds: 4));
      sw.stop();

      print('[Döngü $cycle] Süreç sonlandı: ${sw.elapsedMilliseconds} ms | Exit code: $exitCode');
      expect(exitCode, equals(0));
      expect(sw.elapsedMilliseconds, lessThan(1500));
    }
    print('\n[TEST 2] 3 Döngü başarıyla tamamlandı.');
  });

  test('3. Kapanış Sonrası SQLite Integrity ve Foreign Key Kontrolü', () async {
    print('\n[TEST 3] SQLite Veri Bütünlüğü Doğrulanıyor...');
    final rawDb = sqlite3.open(dbPath);

    // 1. Integrity check
    final integrity = rawDb.select('PRAGMA integrity_check;');
    expect(integrity.first['integrity_check'], equals('ok'));
    print('[TEST 3] PRAGMA integrity_check: ok');

    // 2. Foreign key check
    final fkCheck = rawDb.select('PRAGMA foreign_key_check;');
    expect(fkCheck.isEmpty, isTrue);
    print('[TEST 3] PRAGMA foreign_key_check: 0 ihlal');

    // 3. 3 satışın da eksiksiz yazıldığını doğrula
    final salesCount = rawDb.select('SELECT COUNT(*) as cnt FROM sales;').first['cnt'] as int;
    expect(salesCount, equals(3));
    print('[TEST 3] Satış kayıt sayısı: $salesCount (Beklenen: 3)');

    // 4. Güncel stok: 500000 - 3000 = 497000
    final stock = rawDb.select("SELECT stock FROM products WHERE id = 'prod_cola';").first['stock'] as int;
    expect(stock, equals(497000));
    print('[TEST 3] Güncel stok: $stock (Beklenen: 497000)');

    rawDb.dispose();
    print('\n======================================================================');
    print('BAŞARILI: Windows Service Graceful Shutdown Düzeltmesi %100 Doğrulandı!');
    print('======================================================================\n');
  });
}
