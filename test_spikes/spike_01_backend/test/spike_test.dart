import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/pepper_manager.dart';
import '../lib/security/token_manager.dart';

void main() {
  late Directory tempDir;
  late File dbFile;
  late SpikeDatabase db;
  late WriteQueue writeQueue;
  late PepperManager pepperManager;
  late SpikeServer server;
  late String baseUrl;
  const testPort = 8888;
  const validToken = 'valid_token_device_1';
  const revokedToken = 'revoked_token_device_2';

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    configureSqliteNative();
    tempDir = await Directory.systemTemp.createTemp('mms_spike_');
    dbFile = File(p.join(tempDir.path, 'spike_test.db'));

    pepperManager = PepperManager(File(p.join(tempDir.path, 'pepper.dpapi')));
    pepperManager.initialize();

    db = SpikeDatabase(dbFile);
    writeQueue = WriteQueue();

    // 1. Ürün ekle (Başlangıç stoğu: 100 adet = 100000 milli-birim)
    await db.into(db.products).insert(
          ProductsCompanion(
            id: const Value('prod_cola'),
            barcode: const Value('869000000001'),
            name: const Value('Kutu Kola 330ml'),
            price: const Value(2500),
            stock: const Value(100000),
          ),
        );

    // 2. Yetkili Cihaz ekle
    final validSalt = TokenManager.generateSalt();
    final validHash = TokenManager.hashToken(
      rawToken: validToken,
      salt: validSalt,
      pepper: pepperManager.pepper,
    );
    await db.into(db.devices).insert(
          DevicesCompanion(
            deviceId: const Value('DEV_WIN_01'),
            name: const Value('Windows Kasa 1'),
            tokenHash: Value(validHash),
            salt: Value(validSalt),
            isActive: const Value(true),
          ),
        );

    // 3. Yetkisi İptal Edilmiş Cihaz ekle
    final revokedSalt = TokenManager.generateSalt();
    final revokedHash = TokenManager.hashToken(
      rawToken: revokedToken,
      salt: revokedSalt,
      pepper: pepperManager.pepper,
    );
    await db.into(db.devices).insert(
          DevicesCompanion(
            deviceId: const Value('DEV_MOB_REVOKED'),
            name: const Value('Çalınan Android Telefon'),
            tokenHash: Value(revokedHash),
            salt: Value(revokedSalt),
            isActive: const Value(false),
          ),
        );

    server = SpikeServer(db: db, writeQueue: writeQueue, pepperManager: pepperManager);
    await server.start(address: InternetAddress.loopbackIPv4, port: testPort);
    baseUrl = 'http://127.0.0.1:$testPort';
  });

  tearDownAll(() async {
    await server.stop();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('1. HTTP API ve Health Check Testleri', () {
    test('GET /health - Servis ve SQLite sürümünü dönmelidir', () async {
      final res = await http.get(Uri.parse('$baseUrl/health'));
      expect(res.statusCode, equals(200));

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      expect(data['status'], equals('UP'));
      expect(data['sqlite_version'], isNotEmpty);
      expect(data['queue_metrics'], isNotNull);
    });
  });

  group('2. Güvenlik ve Cihaz Yetkilendirme Testleri', () {
    test('Yetkisiz istek (Token yok) -> 401 Unauthorized dönmelidir', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'operation_id': 'op_test'}),
      );
      expect(res.statusCode, equals(401));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['error'], equals('UNAUTHORIZED'));
    });

    test('Bilinmeyen token -> 401 Unauthorized dönmelidir', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer unknown_token_xyz',
        },
        body: jsonEncode({'operation_id': 'op_test'}),
      );
      expect(res.statusCode, equals(401));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['error'], equals('DEVICE_NOT_FOUND'));
    });

    test('Yetkisi iptal edilmiş cihaz (revoked) -> 403 Forbidden dönmelidir', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $revokedToken',
        },
        body: jsonEncode({'operation_id': 'op_test'}),
      );
      expect(res.statusCode, equals(403));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['error'], equals('DEVICE_REVOKED'));
      expect(body['device_id'], equals('DEV_MOB_REVOKED'));
    });
  });

  group('3. Atomik Satış, Stok Düşümü ve İdempotency Testleri', () {
    test('Geçerli satış transactionı başarıyla atomik işlenmeli ve stok düşmelidir', () async {
      final payload = {
        'operation_id': 'op_sale_1',
        'client_seq': 1,
        'total_amount': 5000,
        'payment_method': 'CASH',
        'items': [
          {'product_id': 'prod_cola', 'quantity': 2000, 'unit_price': 2500, 'total_price': 5000}
        ],
      };

      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $validToken',
        },
        body: jsonEncode(payload),
      );

      expect(res.statusCode, equals(201));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      expect(data['status'], equals('COMMITTED'));
      expect(data['client_seq'], equals(1));
      expect(data['updated_stocks']['prod_cola'], equals(98000)); // 100000 - 2000 = 98000

      // Veritabanı doğrulama
      final product = await (db.select(db.products)..where((p) => p.id.equals('prod_cola'))).getSingle();
      expect(product.stock, equals(98000));

      final movements = await db.select(db.stockMovements).get();
      expect(movements.any((m) => m.referenceId == data['sale_id'] && m.quantity == -2000), isTrue);
    });

    test('ACK Kaybı Sonrası Tekrar Gönderim (Idempotency) -> Mükerrer satış ve mükerrer stok düşüşü olmamalıdır', () async {
      final payload = {
        'operation_id': 'op_sale_1', // Aynı işlem kimliği ve seq
        'client_seq': 1,
        'total_amount': 5000,
        'payment_method': 'CASH',
        'items': [
          {'product_id': 'prod_cola', 'quantity': 2000, 'unit_price': 2500, 'total_price': 5000}
        ],
      };

      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $validToken',
        },
        body: jsonEncode(payload),
      );

      expect(res.statusCode, equals(200)); // İdempotent replay
      expect(res.headers['x-mms-idempotent-replay'], equals('true'));

      // Stok hala 98000 olmalıdır (ikinci kez 2000 düşmemelidir!)
      final product = await (db.select(db.products)..where((p) => p.id.equals('prod_cola'))).getSingle();
      expect(product.stock, equals(98000));

      // Satışlar tablosunda sadece 1 kayıt olmalıdır
      final sales = await (db.select(db.sales)..where((s) => s.clientSeq.equals(1))).get();
      expect(sales.length, equals(1));
    });
  });

  group('4. Transaction Hata ve Rollback Bütünlüğü', () {
    test('Hatalı transaction ortasında hata fırlatılırsa veritabanı temiz kalmalı (Rollback)', () async {
      // Olmayan ürün satmaya çalışıldığında foreign key hatası simülasyonu
      final payload = {
        'operation_id': 'op_sale_failing',
        'client_seq': 999,
        'total_amount': 2500,
        'payment_method': 'CASH',
        'items': [
          {'product_id': 'non_existing_product_xyz', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500}
        ],
      };

      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $validToken',
        },
        body: jsonEncode(payload),
      );

      expect(res.statusCode, equals(500));

      // Satış tablosuna yazılmadığını doğrula
      final sales = await (db.select(db.sales)..where((s) => s.clientSeq.equals(999))).get();
      expect(sales.isEmpty, isTrue);

      // Processed operations defterine yazılmadığını doğrula
      final ops = await (db.select(db.processedOperations)..where((o) => o.operationId.equals('op_sale_failing'))).get();
      expect(ops.isEmpty, isTrue);
    });
  });

  group('5. Canlı Yedekleme (VACUUM INTO) ve Bütünlük Doğrulaması', () {
    String? snapshotPath;

    test('Canlı SQLite yedeği (VACUUM INTO) alınabilmeli ve snapshot sağlam olmalıdır', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/backup/snapshot'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $validToken',
        },
        body: jsonEncode({}),
      );

      expect(res.statusCode, equals(200));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      snapshotPath = data['backup_path'] as String;
      expect(File(snapshotPath!).existsSync(), isTrue);

      // Snapshot dosyasını doğrudan SQLite ile aç ve PRAGMA integrity_check yap
      final snapshotRawDb = sqlite3.open(snapshotPath!);
      final checkResult = snapshotRawDb.select('PRAGMA integrity_check;');
      expect(checkResult.first['integrity_check'], equals('ok'));

      // Orijinal veritabanı ile kayıt sayılarını doğrula
      final originalProductsCount = (await db.select(db.products).get()).length;
      final snapshotProductsCount = snapshotRawDb.select('SELECT COUNT(*) as cnt FROM products;').first['cnt'];
      expect(snapshotProductsCount, equals(originalProductsCount));

      snapshotRawDb.dispose();
    });

    test('Kontrollü Restore: Snapshot yedeğinden veritabanı geri yüklenebilmeli ve tutarlı çalışmalıdır', () async {
      expect(snapshotPath, isNotNull);
      expect(File(snapshotPath!).existsSync(), isTrue);

      final restoredPath = p.join(tempDir.path, 'restored_test.db');
      await File(snapshotPath!).copy(restoredPath);

      final restoredDb = SpikeDatabase(File(restoredPath));

      // Drift ve SQLite bütünlük kontrolü
      final check = await restoredDb.customSelect('PRAGMA integrity_check;').getSingle();
      expect(check.data['integrity_check'], equals('ok'));

      // Restore edilmiş DB'deki verileri sorgula
      final products = await restoredDb.select(restoredDb.products).get();
      expect(products.isNotEmpty, isTrue);

      final sales = await restoredDb.select(restoredDb.sales).get();
      expect(sales.isNotEmpty, isTrue);

      final devices = await restoredDb.select(restoredDb.devices).get();
      expect(devices.isNotEmpty, isTrue);

      await restoredDb.close();
    });
  });

  group('6. Eşzamanlı Yük ve Performans Ölçümü (4 İstemci Normal Yük vs 10 İstemci Stres)', () {
    test('Normal Yük: 4 eşzamanlı istemci toplam 40 satış işlemi (P50, P95, P99 ölçümü)', () async {
      // 4 Cihaz kaydet
      for (int i = 1; i <= 4; i++) {
        final salt = TokenManager.generateSalt();
        final hash = TokenManager.hashToken(
          rawToken: 'token_client_$i',
          salt: salt,
          pepper: pepperManager.pepper,
        );
        await db.into(db.devices).insertOnConflictUpdate(
              DevicesCompanion(
                deviceId: Value('DEV_CLIENT_$i'),
                name: Value('Cihaz $i'),
                tokenHash: Value(hash),
                salt: Value(salt),
                isActive: const Value(true),
              ),
            );
      }

      final failedBefore = writeQueue.metrics.totalFailed;
      final latencies = <int>[];
      final futures = <Future<void>>[];

      for (int client = 1; client <= 4; client++) {
        futures.add(Future(() async {
          for (int seq = 10; seq < 20; seq++) {
            final sw = Stopwatch()..start();
            final payload = {
              'operation_id': 'op_${client}_$seq',
              'client_seq': seq,
              'total_amount': 2500,
              'payment_method': 'CASH',
              'items': [
                {'product_id': 'prod_cola', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500}
              ],
            };

            final res = await http.post(
              Uri.parse('$baseUrl/api/v1/sales'),
              headers: {
                'content-type': 'application/json',
                'authorization': 'Bearer token_client_$client',
              },
              body: jsonEncode(payload),
            );

            sw.stop();
            expect(res.statusCode, equals(201));
            latencies.add(sw.elapsedMilliseconds);
          }
        }));
      }

      await Future.wait(futures);

      latencies.sort();
      final p50 = latencies[(latencies.length * 0.50).floor()];
      final p95 = latencies[(latencies.length * 0.95).floor()];
      final p99 = latencies[(latencies.length * 0.99).floor()];

      print('\n================ NORMAL YÜK ÖLÇÜM SONUÇLARI (4 İstemci / 40 İşlem) ================');
      print('Toplam İşlem: ${latencies.length}');
      print('P50 (Medyan) Gecikme: $p50 ms');
      print('P95 Gecikme: $p95 ms');
      print('P99 Gecikme: $p99 ms');
      print('En Hızlı: ${latencies.first} ms | En Yavaş: ${latencies.last} ms');
      print('Kuyruk Metrikleri: ${writeQueue.metrics.toJson()}');
      print('====================================================================================\n');

      expect(writeQueue.metrics.totalFailed - failedBefore, equals(0));
      expect(writeQueue.metrics.totalBusyErrors, equals(0));
    });

    test('Stres Yükü: 10 eşzamanlı istemci toplam 100 eşzamanlı satış (Burst Stres Testi)', () async {
      // 10 Cihaz kaydet
      for (int i = 1; i <= 10; i++) {
        final salt = TokenManager.generateSalt();
        final hash = TokenManager.hashToken(
          rawToken: 'token_burst_$i',
          salt: salt,
          pepper: pepperManager.pepper,
        );
        await db.into(db.devices).insertOnConflictUpdate(
              DevicesCompanion(
                deviceId: Value('DEV_BURST_$i'),
                name: Value('Burst Kasa $i'),
                tokenHash: Value(hash),
                salt: Value(salt),
                isActive: const Value(true),
              ),
            );
      }

      final failedBefore = writeQueue.metrics.totalFailed;
      final latencies = <int>[];
      final futures = <Future<void>>[];

      for (int client = 1; client <= 10; client++) {
        futures.add(Future(() async {
          for (int seq = 100; seq < 110; seq++) {
            final sw = Stopwatch()..start();
            final payload = {
              'operation_id': 'burst_op_${client}_$seq',
              'client_seq': seq,
              'total_amount': 2500,
              'payment_method': 'CASH',
              'items': [
                {'product_id': 'prod_cola', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500}
              ],
            };

            final res = await http.post(
              Uri.parse('$baseUrl/api/v1/sales'),
              headers: {
                'content-type': 'application/json',
                'authorization': 'Bearer token_burst_$client',
              },
              body: jsonEncode(payload),
            );

            sw.stop();
            expect(res.statusCode, equals(201));
            latencies.add(sw.elapsedMilliseconds);
          }
        }));
      }

      await Future.wait(futures);

      latencies.sort();
      final p50 = latencies[(latencies.length * 0.50).floor()];
      final p95 = latencies[(latencies.length * 0.95).floor()];
      final p99 = latencies[(latencies.length * 0.99).floor()];

      print('\n================ STRES TESTİ ÖLÇÜM SONUÇLARI (10 İstemci / 100 İşlem) ================');
      print('Toplam İşlem: ${latencies.length}');
      print('P50 (Medyan) Gecikme: $p50 ms');
      print('P95 Gecikme: $p95 ms');
      print('P99 Gecikme: $p99 ms');
      print('En Hızlı: ${latencies.first} ms | En Yavaş: ${latencies.last} ms');
      print('Kuyruk Metrikleri (Stres): ${writeQueue.metrics.toJson()}');
      print('======================================================================================\n');

      expect(writeQueue.metrics.totalFailed - failedBefore, equals(0));
    });
  });
}
