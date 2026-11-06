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
  const testPort = 8991;
  const testToken = 'token_crash_test';
  const testDeviceId = 'DEV_CRASH_TEST';

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    tempDir = await Directory.systemTemp.createTemp('mms_process_crash_');
    dbPath = p.join(tempDir.path, 'crash_master.db');
    pepperPath = p.join(tempDir.path, 'pepper.dpapi');

    pepperManager = PepperManager(File(pepperPath));
    pepperManager.initialize();

    exePath = p.normalize(p.join(Directory.current.path, 'build', 'spike_service_s2.exe'));
    if (!File(exePath).existsSync()) {
      exePath = p.normalize(p.join(Directory.current.path, 'build', 'spike_service.exe'));
    }
    if (!File(exePath).existsSync()) {
      throw StateError('spike_service executable bulunamadı: $exePath. Önce dart compile exe çalıştırılmalı.');
    }

    // 1. İlk şema kurulumu ve tohumlama (Seed data)
    final setupDb = SpikeDatabase(File(dbPath));
    await setupDb.customStatement('PRAGMA journal_mode = WAL;');
    await setupDb.customStatement('PRAGMA foreign_keys = ON;');

    await setupDb.into(setupDb.products).insertOnConflictUpdate(
          ProductsCompanion(
            id: const Value('prod_cola'),
            barcode: const Value('869000000001'),
            name: const Value('Kutu Kola 330ml'),
            price: const Value(2500),
            stock: const Value(100000),
          ),
        );

    final salt = TokenManager.generateSalt();
    final hash = TokenManager.hashToken(
      rawToken: testToken,
      salt: salt,
      pepper: pepperManager.pepper,
    );

    await setupDb.into(setupDb.devices).insertOnConflictUpdate(
          DevicesCompanion(
            deviceId: const Value(testDeviceId),
            name: const Value('Crash Test Cihazı'),
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

  Future<Process> startBackendProcess() async {
    final process = await Process.start(
      exePath,
      ['--port=$testPort', '--db-path=$dbPath', '--pepper-file=$pepperPath'],
      mode: ProcessStartMode.normal,
    );

    // Sağlık kontrolü ile ayağa kalktığını doğrula (max 5 saniye bekle)
    final stopwatch = Stopwatch()..start();
    var isUp = false;
    while (stopwatch.elapsedMilliseconds < 5000) {
      try {
        final res = await http.get(Uri.parse('http://127.0.0.1:$testPort/health'));
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
      throw StateError('Backend süreci başlatılamadı veya health kontrolüne yanıt vermedi.');
    }

    return process;
  }

  void forceKillProcess(Process process) {
    final pid = process.pid;
    // 1. Önce Process.killPid (SIGKILL)
    try {
      Process.killPid(pid, ProcessSignal.sigkill);
    } catch (_) {}

    // 2. Windows üzerinde garantili taskkill /F /T
    if (Platform.isWindows) {
      try {
        Process.runSync('taskkill', ['/F', '/T', '/PID', '$pid']);
      } catch (_) {}
    }
  }

  bool isProcessAlive(int pid) {
    if (Platform.isWindows) {
      final res = Process.runSync('tasklist', ['/FI', 'PID eq $pid']);
      return res.stdout.toString().contains('$pid');
    }
    return false;
  }

  test('Gerçek OS Process Crash & WAL Recovery Döngüsü (Tam Doğrulama)', () async {
    print('\n======================================================================');
    print('BAŞLADI: Gerçek İşletim Sistemi Seviyesinde Process Crash & Recovery Testi');
    print('======================================================================\n');

    // ADIM 1: İlk Backend Sürecini Başlat
    var backendProcess = await startBackendProcess();
    final childPid = backendProcess.pid;
    print('[ADIM 1] Child Backend Süreci Başlatıldı. PID: $childPid');
    expect(isProcessAlive(childPid), isTrue);

    // ADIM 2: Commit Edilen İşlemleri Gönder (Tx 1, 2, 3)
    print('[ADIM 2] Commit edilecek 3 geçerli satış işlemi gönderiliyor...');
    for (int seq = 1; seq <= 3; seq++) {
      final payload = {
        'operation_id': 'op_committed_$seq',
        'client_seq': seq,
        'total_amount': 2500,
        'payment_method': 'CASH',
        'items': [
          {'product_id': 'prod_cola', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500}
        ],
      };

      final res = await http.post(
        Uri.parse('http://127.0.0.1:$testPort/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $testToken',
        },
        body: jsonEncode(payload),
      );

      expect(res.statusCode, equals(201));
      final resData = jsonDecode(res.body);
      expect(resData['status'], equals('COMMITTED'));
      expect(resData['updated_stocks']['prod_cola'], equals(100000 - (seq * 1000)));
    }
    print('[ADIM 2] 3 Satış başarıyla commit edildi. Beklenen stok: 97000.');

    // ADIM 3: Aktif Yazma İşlemi Sırasında Süreci Zorla Sonlandır (CRASH)
    print('[ADIM 3] 2000 ms gecikmeli satış işlemi (Tx 4) gönderiliyor ve işlem ortasında zorla öldürülüyor...');
    final crashPayload = {
      'operation_id': 'op_interrupted_4',
      'client_seq': 4,
      'total_amount': 2500,
      'payment_method': 'CASH',
      'simulated_delay_ms': 2000, // 2 saniye beklet
      'items': [
        {'product_id': 'prod_cola', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500}
      ],
    };

    // İstek arka planda gönderilir
    final inFlightRequest = http.post(
      Uri.parse('http://127.0.0.1:$testPort/api/v1/sales'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $testToken',
      },
      body: jsonEncode(crashPayload),
    );

    // Satış başlığının yazılması ve transaction ortasına ulaşılması için 200ms bekle
    await Future.delayed(const Duration(milliseconds: 200));

    // ZORLA ÖLDÜR (OS PROCESS CRASH)
    print('[ADIM 3] !!! OS KILL TETİKLENİYOR !!! Hedef PID: $childPid');
    forceKillProcess(backendProcess);

    // İsteğin soket hatasıyla kesildiğini doğrula (SocketException veya ClientException)
    try {
      await inFlightRequest.timeout(const Duration(seconds: 1));
      fail('İstek kesilmedi, beklenmedik şekilde tamamlandı.');
    } catch (e) {
      print('[ADIM 3] Beklendiği gibi istek yarıda kesildi: ${e.runtimeType}');
    }

    // ADIM 4: Sürecin Gerçekten Öldüğünü Doğrula
    await Future.delayed(const Duration(milliseconds: 300));
    final isAliveAfterKill = isProcessAlive(childPid);
    print('[ADIM 4] Süreç canlılık kontrolü (PID $childPid): Canlı mı = $isAliveAfterKill');
    expect(isAliveAfterKill, isFalse, reason: 'Süreç işletim sistemi seviyesinde sonlandırılamadı!');

    // WAL dosyasının diskte varlığını kontrol et
    final walFile = File('$dbPath-wal');
    print('[ADIM 4] SQLite WAL Dosyası Mevcut mu: ${walFile.existsSync()}');

    // ADIM 5: Yeni Bir Backend Process Başlat (SQLite WAL Recovery)
    print('[ADIM 5] Veritabanı yeni bir bağımsız Dart backend süreciyle ayağa kaldırılıyor (Recovery)...');
    backendProcess = await startBackendProcess();
    final newPid = backendProcess.pid;
    print('[ADIM 5] Yeni Backend Süreci Başlatıldı. Yeni PID: $newPid');
    expect(newPid, isNot(equals(childPid)));

    // ADIM 6: Veri Bütünlüğü ve Recovery Doğrulaması (PRAGMA Kontrolleri)
    print('[ADIM 6] SQLite Bütünlük ve Veri Tutarlılığı Denetimi Yapılıyor...');
    final rawDb = sqlite3.open(dbPath);

    // 6.1 PRAGMA integrity_check
    final integrityResult = rawDb.select('PRAGMA integrity_check;');
    final integrityStatus = integrityResult.first['integrity_check'];
    print('[ADIM 6.1] PRAGMA integrity_check sonucu: $integrityStatus');
    expect(integrityStatus, equals('ok'));

    // 6.2 PRAGMA foreign_key_check
    final fkResult = rawDb.select('PRAGMA foreign_key_check;');
    print('[ADIM 6.2] PRAGMA foreign_key_check ihlal sayısı: ${fkResult.length}');
    expect(fkResult.isEmpty, isTrue);

    // 6.3 Commit Edilen İşlemlerin Varlığı (Tx 1, 2, 3)
    final salesCount = rawDb.select('SELECT COUNT(*) as cnt FROM sales;').first['cnt'] as int;
    print('[ADIM 6.3] sales tablosundaki toplam kayıt: $salesCount (Beklenen: 3)');
    expect(salesCount, equals(3));

    final saleItemsCount = rawDb.select('SELECT COUNT(*) as cnt FROM sale_items;').first['cnt'] as int;
    print('[ADIM 6.3] sale_items tablosundaki toplam kayıt: $saleItemsCount (Beklenen: 3)');
    expect(saleItemsCount, equals(3));

    final stockMovementsCount = rawDb.select('SELECT COUNT(*) as cnt FROM stock_movements;').first['cnt'] as int;
    print('[ADIM 6.3] stock_movements tablosundaki toplam kayıt: $stockMovementsCount (Beklenen: 3)');
    expect(stockMovementsCount, equals(3));

    final processedOpsCount = rawDb.select('SELECT COUNT(*) as cnt FROM processed_operations;').first['cnt'] as int;
    print('[ADIM 6.3] processed_operations defterindeki kayıt: $processedOpsCount (Beklenen: 3)');
    expect(processedOpsCount, equals(3));

    // 6.4 Yarım Kalan İşlemin (Tx 4) Durumu
    final interruptedSale = rawDb.select("SELECT * FROM sales WHERE client_seq = 4;");
    print('[ADIM 6.4] Yarım kalan Tx 4 sales tablosunda var mı: ${interruptedSale.isNotEmpty} (Beklenen: False)');
    expect(interruptedSale.isEmpty, isTrue);

    final interruptedOps = rawDb.select("SELECT * FROM processed_operations WHERE operation_id = 'op_interrupted_4';");
    print('[ADIM 6.4] Yarım kalan Tx 4 processed_operations tablosunda var mı: ${interruptedOps.isNotEmpty} (Beklenen: False)');
    expect(interruptedOps.isEmpty, isTrue);

    // 6.5 Stok Bütünlüğü Kontrolü
    final currentStock = rawDb.select("SELECT stock FROM products WHERE id = 'prod_cola';").first['stock'] as int;
    print('[ADIM 6.5] prod_cola güncel stok: $currentStock (Beklenen: 97000)');
    expect(currentStock, equals(97000));

    final movementSum = rawDb.select("SELECT SUM(quantity) as total_qty FROM stock_movements WHERE product_id = 'prod_cola';").first['total_qty'] as int;
    print('[ADIM 6.5] stock_movements toplam değişim: $movementSum (Beklenen: -3000)');
    expect(movementSum, equals(-3000));

    rawDb.dispose();

    // ADIM 7: Kurtarma Sonrası Tekrar Gönderim (Idempotency & Re-execution)
    print('[ADIM 7] Kurtarma sonrası yarıda kalan Tx 4 yeniden gönderiliyor...');
    // Yarım kalan işlem temiz bir şekilde rollback olduğu için şimdi normal gönderilebilir
    final retryPayload = {
      'operation_id': 'op_interrupted_4',
      'client_seq': 4,
      'total_amount': 2500,
      'payment_method': 'CASH',
      'items': [
        {'product_id': 'prod_cola', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500}
      ],
    };

    final retryRes = await http.post(
      Uri.parse('http://127.0.0.1:$testPort/api/v1/sales'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $testToken',
      },
      body: jsonEncode(retryPayload),
    );

    expect(retryRes.statusCode, equals(201));
    final retryData = jsonDecode(retryRes.body);
    expect(retryData['status'], equals('COMMITTED'));
    expect(retryData['updated_stocks']['prod_cola'], equals(96000));
    print('[ADIM 7] Tx 4 başarıyla commit edildi. Yeni stok: 96000.');

    // Aynı Tx 4 tekrar gönderilirse mükerrer satış olmamalı (ACK Replay)
    print('[ADIM 7] Tx 4 tekrar gönderiliyor (Mükerrerlik / Idempotency Testi)...');
    final replayRes = await http.post(
      Uri.parse('http://127.0.0.1:$testPort/api/v1/sales'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $testToken',
      },
      body: jsonEncode(retryPayload),
    );

    expect(replayRes.statusCode, equals(200));
    expect(replayRes.headers['x-mms-idempotent-replay'], equals('true'));
    print('[ADIM 7] Mükerrer satış engellendi, önceki ACK yanıtı başarıyla döndü.');

    // Yeni süreci temiz kapat
    forceKillProcess(backendProcess);
    print('\n======================================================================');
    print('BAŞARILI: Gerçek OS Process Crash & WAL Recovery Testi Tamamlandı!');
    print('======================================================================\n');
  });

  test('Çoklu Döngü: 3 ardışık Process Crash ve Recovery döngüsünde kümülatif tutarlılık', () async {
    print('\n======================================================================');
    print('BAŞLADI: 3 Ardışık Process Crash & Recovery Döngü Testi');
    print('======================================================================\n');

    for (int cycle = 1; cycle <= 3; cycle++) {
      print('\n--- [DÖNGÜ $cycle / 3] Başlatılıyor ---');
      var proc = await startBackendProcess();
      final pid = proc.pid;
      print('[Döngü $cycle] Süreç PID: $pid');

      // 1 geçerli satış yap
      final normalPayload = {
        'operation_id': 'op_cycle_${cycle}_committed',
        'client_seq': 100 + cycle,
        'total_amount': 2500,
        'payment_method': 'CASH',
        'items': [
          {'product_id': 'prod_cola', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500}
        ],
      };
      final normalRes = await http.post(
        Uri.parse('http://127.0.0.1:$testPort/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $testToken',
        },
        body: jsonEncode(normalPayload),
      );
      expect(normalRes.statusCode, equals(201));

      // Yarım kalacak satış gönder ve öldür
      final crashPayload = {
        'operation_id': 'op_cycle_${cycle}_interrupted',
        'client_seq': 200 + cycle,
        'total_amount': 2500,
        'payment_method': 'CASH',
        'simulated_delay_ms': 2000,
        'items': [
          {'product_id': 'prod_cola', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500}
        ],
      };

      final inFlight = http.post(
        Uri.parse('http://127.0.0.1:$testPort/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $testToken',
        },
        body: jsonEncode(crashPayload),
      );

      await Future.delayed(const Duration(milliseconds: 200));
      forceKillProcess(proc);

      try {
        await inFlight.timeout(const Duration(seconds: 1));
      } catch (_) {}

      expect(isProcessAlive(pid), isFalse);
      print('[Döngü $cycle] Süreç $pid başarıyla öldürüldü.');

      // Bütünlük kontrolü
      final rawDb = sqlite3.open(dbPath);
      expect(rawDb.select('PRAGMA integrity_check;').first['integrity_check'], equals('ok'));
      expect(rawDb.select('PRAGMA foreign_key_check;').isEmpty, isTrue);

      // Yarıda kesilen işlemin yazılmadığını doğrula
      final interrupted = rawDb.select("SELECT * FROM sales WHERE client_seq = ${200 + cycle};");
      expect(interrupted.isEmpty, isTrue);

      rawDb.dispose();
      print('[Döngü $cycle] SQLite WAL Recovery doğrulandı.');
    }

    print('\n======================================================================');
    print('BAŞARILI: 3 Ardışık Crash & Recovery Döngüsü %100 Başarı ile Tamamlandı!');
    print('======================================================================\n');
  });
}
