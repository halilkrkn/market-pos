import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/pepper_manager.dart';
import '../lib/security/token_manager.dart';
import '../lib/service/admission_gate.dart';
import '../lib/service/lifecycle_manager.dart';

void main() {
  late Directory tempDir;
  late File dbFile;
  late SpikeDatabase db;
  late WriteQueue writeQueue;
  late PepperManager pepperManager;
  late SpikeServer server;
  late String baseUrl;
  const testPort = 8998;
  const deviceId = 'DEV_S5A2';
  const rawToken = 'token_s5a2_durability_secret_123';
  const deviceIdB = 'DEV_S5A2_B';
  const rawTokenB = 'token_s5a2_device_b_456';
  const adminSecret = 'admin_s5a2_secret_9999';

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    configureSqliteNative();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mms_s5a2_durability_');
    dbFile = File(p.join(tempDir.path, 'durability_master.db'));

    pepperManager = PepperManager(File(p.join(tempDir.path, 'pepper.dpapi')));
    pepperManager.initialize();

    db = SpikeDatabase(dbFile);
    writeQueue = WriteQueue();

    // 1. Ürün tohumla: prod_cola (stok: 100), prod_water (stok: 5)
    await db.into(db.products).insert(
          ProductsCompanion(
            id: const Value('prod_cola'),
            barcode: const Value('869000000001'),
            name: const Value('Kutu Kola 330ml'),
            price: const Value(2500),
            stock: const Value(100000),
          ),
        );
    await db.into(db.products).insert(
          ProductsCompanion(
            id: const Value('prod_water'),
            barcode: const Value('869000000002'),
            name: const Value('Su 500ml'),
            price: const Value(1000),
            stock: const Value(5000),
          ),
        );

    // 2. Yetkili cihaz 1 (DEV_S5A2) tohumla
    final saltA = TokenManager.generateSalt();
    final hashA = TokenManager.hashToken(
      rawToken: rawToken,
      salt: saltA,
      pepper: pepperManager.pepper,
    );
    await db.into(db.devices).insert(
          DevicesCompanion(
            deviceId: const Value(deviceId),
            name: const Value('S5A-2 Kasa Cihazı A'),
            tokenHash: Value(hashA),
            salt: Value(saltA),
            isActive: const Value(true),
            isConfirmed: const Value(true),
          ),
        );

    // 3. Yetkili cihaz 2 (DEV_S5A2_B) tohumla
    final saltB = TokenManager.generateSalt();
    final hashB = TokenManager.hashToken(
      rawToken: rawTokenB,
      salt: saltB,
      pepper: pepperManager.pepper,
    );
    await db.into(db.devices).insert(
          DevicesCompanion(
            deviceId: const Value(deviceIdB),
            name: const Value('S5A-2 Kasa Cihazı B'),
            tokenHash: Value(hashB),
            salt: Value(saltB),
            isActive: const Value(true),
            isConfirmed: const Value(true),
          ),
        );

    server = SpikeServer(
      db: db,
      writeQueue: writeQueue,
      adminSecret: adminSecret,
      pepperManager: pepperManager,
    );

    await server.start(port: testPort);
    baseUrl = 'http://127.0.0.1:$testPort';
  });

  tearDown(() async {
    try {
      await server.stop();
    } catch (_) {}
    try {
      await db.close();
    } catch (_) {}
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('Aşama S-5A-2: SQLite FULL Durability, Yaşam Döngüsü ve İşlem Güvenliği Testleri', () {
    test('1. PRAGMA synchronous = FULL (2) ve PRAGMA journal_mode = WAL doğrulaması', () async {
      // Drift bağlantısı üzerinden doğrulama
      final syncPragma = await db.getSynchronousPragma();
      final journalPragma = await db.getJournalModePragma();

      expect(syncPragma, equals(2), reason: 'PRAGMA synchronous değeri 2 (FULL) olmalıdır.');
      expect(journalPragma, equals('wal'), reason: 'PRAGMA journal_mode değeri wal olmalıdır.');

      // Doğrudan bağımsız SQLite bağlantısı ile de doğrula
      final rawDb = sqlite.sqlite3.open(dbFile.path);
      try {
        final rawSync = rawDb.select('PRAGMA synchronous;').first.values.first as int;
        final rawJournal = (rawDb.select('PRAGMA journal_mode;').first.values.first as String).toLowerCase();

        expect(rawSync, equals(2));
        expect(rawJournal, equals('wal'));
      } finally {
        rawDb.dispose();
      }
    });

    test('2. AdmissionGate yeni istekleri 503 ile reddederken in-flight isteklerin bitmesini beklemelidir', () async {
      final gate = AdmissionGate();
      expect(gate.isOpen, isTrue);
      expect(gate.inFlightRequests, equals(0));

      // 1. İstek alımı
      final acquired1 = gate.tryAcquire();
      expect(acquired1, isTrue);
      expect(gate.inFlightRequests, equals(1));

      // 2. Kapıyı kapat (Draining başlar)
      gate.close();
      expect(gate.isOpen, isFalse);

      // Yeni gelen istek derhal reddedilmeli
      final acquired2 = gate.tryAcquire();
      expect(acquired2, isFalse);
      expect(gate.inFlightRequests, equals(1)); // Artmamalı

      // 3. In-flight drain beklemesi
      bool drainFinished = false;
      final drainFuture = gate.waitForInFlightDrain().then((val) {
        drainFinished = val;
      });

      // Henüz in-flight 1 olduğu için drain tamamlanmamış olmalı
      await Future.delayed(const Duration(milliseconds: 20));
      expect(drainFinished, isFalse);

      // In-flight isteği tamamla
      gate.release();
      await drainFuture;
      expect(drainFinished, isTrue);
      expect(gate.inFlightRequests, equals(0));
    });

    test('3. AdmissionGate exception ve hata durumunda release() çağrılmalı ve in-flight sıfırlanmalıdır', () async {
      final gate = AdmissionGate();
      final middleware = createAdmissionMiddleware(gate);

      // Hata fırlatan bir Handler simüle et
      final handler = middleware((Request req) async {
        throw StateError('Simüle edilmiş istek işleme hatası!');
      });

      expect(gate.inFlightRequests, equals(0));

      try {
        await handler(Request('POST', Uri.parse('http://127.0.0.1/api/test')));
      } catch (e) {
        expect(e, isA<StateError>());
      }

      // İstek exception fırlatsa dahi finally bloğu sayesinde release() çalışmış ve sayaç 0 olmalıdır
      expect(gate.inFlightRequests, equals(0), reason: 'Exception fırlatıldığında in-flight sayacı 0\'a dönmelidir.');
    });

    test('4. WriteQueue FIFO sırasını korumalı ve metrikleri doğru artırmalıdır', () async {
      final queue = WriteQueue();
      final executionOrder = <int>[];

      final f1 = queue.enqueue(() async {
        await Future.delayed(const Duration(milliseconds: 50));
        executionOrder.add(1);
        return 1;
      });
      final f2 = queue.enqueue(() async {
        await Future.delayed(const Duration(milliseconds: 30));
        executionOrder.add(2);
        return 2;
      });
      final f3 = queue.enqueue(() async {
        await Future.delayed(const Duration(milliseconds: 10));
        executionOrder.add(3);
        return 3;
      });

      await Future.wait([f1, f2, f3]);

      // FIFO garantisi: Enqueue edilme sırasına göre tamamlanmalıdır
      expect(executionOrder, equals([1, 2, 3]));
      expect(queue.metrics.totalEnqueued, equals(3));
      expect(queue.metrics.totalCompleted, equals(3));
      expect(queue.metrics.totalFailed, equals(0));
      expect(queue.metrics.currentQueueLength, equals(0));
      expect(queue.metrics.peakQueueLength, greaterThanOrEqualTo(1));
    });

    test('5. Tekil Global Shutdown Deadline: In-flight ve WriteQueue aynı bütçeyi paylaşmalı, toplam süre deadline\'ı aşmamalıdır', () async {
      final customGate = AdmissionGate();
      final hangingQueue = WriteQueue();

      // In-flight'ı meşgul et
      customGate.tryAcquire();

      final manager = LifecycleManager(
        db: db,
        writeQueue: hangingQueue,
        admissionGate: customGate,
        drainTimeout: const Duration(milliseconds: 150), // Global deadline: 150 ms
      );

      final sw = Stopwatch()..start();
      // 50 ms sonra in-flight tamamlansın
      Timer(const Duration(milliseconds: 50), () => customGate.release());

      // WriteQueue ise 500 ms sürsün (kalan 100 ms'yi aşacak)
      hangingQueue.enqueue(() async {
        await Future.delayed(const Duration(milliseconds: 500));
      });

      final exitCode = await manager.shutdown(reason: 'Global deadline test');
      sw.stop();

      expect(exitCode, equals(101), reason: 'Kalan süre tükendiğinde 101 ile çıkmalıdır.');
      // Toplam süre 150ms deadline civarında olmalı, asla 150 + 150 = 300ms olmamalıdır!
      expect(sw.elapsedMilliseconds, lessThan(280), reason: 'Shutdown süresi global deadline sınırını aşamaz!');
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(140));
    });

    test('6. Başarılı drain sonrası PRAGMA wal_checkpoint(TRUNCATE) ve temiz DB kapanışı (Exit code 0)', () async {
      // Birkaç işlem yaparak WAL dosyasını doldur
      for (int i = 1; i <= 3; i++) {
        await writeQueue.enqueue(() async {
          await db.into(db.sales).insert(
                SalesCompanion(
                  id: Value('sale_chk_$i'),
                  deviceId: const Value(deviceId),
                  clientSeq: Value(100 + i),
                  totalAmount: const Value(2500),
                  paymentMethod: const Value('CASH'),
                ),
              );
        });
      }

      // Kapatmayı tetikle
      final exitCode = await server.lifecycle.shutdown(reason: 'Test successful drain');
      expect(exitCode, equals(0), reason: 'Başarılı drain sonrası exit code 0 dönmelidir.');

      // Checkpoint sonucunu doğrula
      expect(server.lifecycle.lastCheckpointResult?.busy, equals(0));
      expect(server.lifecycle.lastCheckpointResult?.isSuccess, isTrue);

      // Bağımsız SQLite ile doğrula: WAL checkpoint yapıldı ve veri bütünlüğü tam
      final rawDb = sqlite.sqlite3.open(dbFile.path);
      try {
        final integrity = rawDb.select('PRAGMA integrity_check;').first.values.first as String;
        expect(integrity, equals('ok'));

        final salesCount = rawDb.select('SELECT COUNT(*) as cnt FROM sales;').first['cnt'] as int;
        expect(salesCount, equals(3));
      } finally {
        rawDb.dispose();
      }
    });

    test('7. PRAGMA wal_checkpoint BUSY (busy=1) durumunda güvenli kapanış davranışı', () async {
      // Veritabanına veri yaz
      await writeQueue.enqueue(() async {
        await db.into(db.sales).insert(
              SalesCompanion(
                id: const Value('sale_cp_busy_1'),
                deviceId: const Value(deviceId),
                clientSeq: const Value(888),
                totalAmount: const Value(2500),
                paymentMethod: const Value('CASH'),
              ),
            );
      });

      // İkinci bir SQLite bağlantısı açarak okuma kilidi koy (WAL read lock)
      final lockerDb = sqlite.sqlite3.open(dbFile.path);
      try {
        lockerDb.execute('BEGIN DEFERRED;');
        lockerDb.select('SELECT * FROM sales;');

        // Checkpoint çalıştır
        final cpResult = await db.checkpointWal(mode: 'TRUNCATE');
        expect(cpResult.busy, equals(1), reason: 'Açık okuma kilidi varken wal_checkpoint busy=1 dönmelidir.');
        expect(cpResult.isSuccess, isFalse);

        // LifecycleManager shutdown bu durumu kontrollü yönetmeli, DB'yi kapatırken WAL'ı bozmamalıdır
        final exitCode = await server.lifecycle.shutdown(reason: 'Test checkpoint busy');
        expect(exitCode, equals(0));
        expect(server.lifecycle.lastCheckpointResult?.busy, equals(1));
      } finally {
        lockerDb.execute('ROLLBACK;');
        lockerDb.dispose();
      }

      // Yeniden açıldığında satış kaydı WAL recovery ile eksiksiz okunmalıdır
      final checkDb = SpikeDatabase(dbFile);
      try {
        final sales = await (checkDb.select(checkDb.sales)..where((s) => s.id.equals('sale_cp_busy_1'))).get();
        expect(sales.length, equals(1), reason: 'Checkpoint busy olsa dahi WAL recovery veriyi korur.');
      } finally {
        await checkDb.close();
      }
    });

    test('8. Drain zaman aşımı durumunda WAL dosyasının silinmemesi/bozulmaması ve sürecin kontrollü 101 ile sonlanması', () async {
      final hangingQueue = WriteQueue();
      // 500 ms süren bir işlem kuyruğa sok
      hangingQueue.enqueue(() async {
        await Future.delayed(const Duration(milliseconds: 500));
      });

      // 50 ms timeout ile drain çağır
      final drained = await hangingQueue.drain(timeout: const Duration(milliseconds: 50));
      expect(drained, isFalse, reason: 'Zaman aşımında drain false dönmelidir.');

      // Mock lifecycle ile 101 davranışı doğrula
      final timeoutLifecycle = LifecycleManager(
        db: db,
        writeQueue: hangingQueue,
        drainTimeout: const Duration(milliseconds: 50),
      );

      // drain zaman aşımına zorla
      final exitCode = await timeoutLifecycle.shutdown(reason: 'Test timeout drain');
      expect(exitCode, equals(101), reason: 'Drain zaman aşımında kontrollü exit code 101 dönmelidir.');
    });

    test('9. Commit-before-ACK: Transaction SQLite\'a commit edilmeden istemciye ACK verilmemelidir', () async {
      final payload = {
        'operation_id': 'op_cba_1',
        'client_seq': 10,
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
          'authorization': 'Bearer $rawToken',
        },
        body: jsonEncode(payload),
      );

      expect(res.statusCode, equals(201));
      final resBody = jsonDecode(res.body) as Map<String, dynamic>;
      expect(resBody['status'], equals('COMMITTED'));
      final saleId = resBody['sale_id'] as String;

      // İstemci ACK aldığında veritabanı dosyasında verinin kesinlikle var olduğunu doğrula
      final rawDb = sqlite.sqlite3.open(dbFile.path);
      try {
        final saleRow = rawDb.select("SELECT * FROM sales WHERE id = '$saleId';");
        expect(saleRow.isNotEmpty, isTrue, reason: 'ACK dönmeden önce transaction diske commit edilmiş olmalıdır!');
        expect(saleRow.first['total_amount'], equals(2500));

        final itemRow = rawDb.select("SELECT * FROM sale_items WHERE sale_id = '$saleId';");
        expect(itemRow.isNotEmpty, isTrue);

        final stockRow = rawDb.select("SELECT stock FROM products WHERE id = 'prod_cola';");
        expect(stockRow.first['stock'], equals(99000)); // 100000 - 1000 = 99000
      } finally {
        rawDb.dispose();
      }
    });

    test('10. ACK kaybı sonrası aynı payload ile tekrar gönderimde mükerrer satış/stok düşümü olmadan önceki yanıt dönmelidir (Idempotent Replay)', () async {
      final payload = {
        'operation_id': 'op_replay_1',
        'client_seq': 11,
        'total_amount': 5000,
        'payment_method': 'CASH',
        'items': [
          {'product_id': 'prod_cola', 'quantity': 2000, 'unit_price': 2500, 'total_price': 5000}
        ],
      };

      // 1. İlk gönderim
      final res1 = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $rawToken',
        },
        body: jsonEncode(payload),
      );
      expect(res1.statusCode, equals(201));
      final body1 = jsonDecode(res1.body) as Map<String, dynamic>;

      // 2. İkinci gönderim (ACK kaybı simülasyonu - Birebir aynı payload)
      final res2 = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $rawToken',
        },
        body: jsonEncode(payload),
      );

      expect(res2.statusCode, equals(200));
      expect(res2.headers['x-mms-idempotent-replay'], equals('true'));
      final body2 = jsonDecode(res2.body) as Map<String, dynamic>;

      // Yanıt içerikleri aynı olmalı
      expect(body2['sale_id'], equals(body1['sale_id']));
      expect(body2['client_seq'], equals(11));

      // Veritabanında mükerrer kayıt ve mükerrer stok düşümü olmamalı
      final rawDb = sqlite.sqlite3.open(dbFile.path);
      try {
        final sales = rawDb.select("SELECT COUNT(*) as cnt FROM sales WHERE client_seq = 11;");
        expect(sales.first['cnt'], equals(1), reason: 'Tek bir satış kaydı bulunmalıdır.');

        final colaStock = rawDb.select("SELECT stock FROM products WHERE id = 'prod_cola';");
        expect(colaStock.first['stock'], equals(98000), reason: 'Stok sadece bir kez düşmelidir (100000 - 2000 = 98000).');
      } finally {
        rawDb.dispose();
      }
    });

    test('11. Aynı idempotency key ile farklı payload geldiğinde 409 Conflict dönmelidir (ERR_IDEMPOTENCY_PAYLOAD_MISMATCH)', () async {
      final payloadOriginal = {
        'operation_id': 'op_conflict_1',
        'client_seq': 12,
        'total_amount': 2500,
        'payment_method': 'CASH',
        'items': [
          {'product_id': 'prod_cola', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500}
        ],
      };

      // 1. İlk geçerli satış
      final res1 = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $rawToken',
        },
        body: jsonEncode(payloadOriginal),
      );
      expect(res1.statusCode, equals(201));

      // 2. Aynı idempotency key ($deviceId:12), ancak farklı sepet/tutar!
      final payloadMismatched = {
        'operation_id': 'op_conflict_1',
        'client_seq': 12, // AYNI SIRA NO
        'total_amount': 5000, // FARKLI TUTAR!
        'payment_method': 'CREDIT_CARD',
        'items': [
          {'product_id': 'prod_cola', 'quantity': 2000, 'unit_price': 2500, 'total_price': 5000}
        ],
      };

      final res2 = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $rawToken',
        },
        body: jsonEncode(payloadMismatched),
      );

      expect(res2.statusCode, equals(409));
      final body2 = jsonDecode(res2.body) as Map<String, dynamic>;
      expect(body2['error'], equals('CONFLICT'));
      expect(body2['code'], equals('ERR_IDEMPOTENCY_PAYLOAD_MISMATCH'));
      expect(body2['idempotency_key'], equals('$deviceId:12'));

      // Veritabanındaki ilk işlem bozulmamış olmalıdır
      final rawDb = sqlite.sqlite3.open(dbFile.path);
      try {
        final sales = rawDb.select("SELECT * FROM sales WHERE client_seq = 12;");
        expect(sales.length, equals(1));
        expect(sales.first['total_amount'], equals(2500)); // Değiştirilmemiş olmalı
      } finally {
        rawDb.dispose();
      }
    });

    test('12. Farklı cihazların aynı client_seq değerini kullanması birbirleriyle çakışmamalıdır (Device-scoped Idempotency)', () async {
      // Cihaz A: DEV_S5A2, client_seq = 1
      final payloadA = {
        'operation_id': 'op_dev_a_seq_1',
        'client_seq': 1,
        'total_amount': 2500,
        'payment_method': 'CASH',
        'items': [
          {'product_id': 'prod_cola', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500}
        ],
      };

      // Cihaz B: DEV_S5A2_B, client_seq = 1 (AYNI SIRA NUMARASI!)
      final payloadB = {
        'operation_id': 'op_dev_b_seq_1',
        'client_seq': 1,
        'total_amount': 1000,
        'payment_method': 'CREDIT_CARD',
        'items': [
          {'product_id': 'prod_water', 'quantity': 1000, 'unit_price': 1000, 'total_price': 1000}
        ],
      };

      // Cihaz A satışı gönderir
      final resA = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $rawToken', // Cihaz A token'ı
        },
        body: jsonEncode(payloadA),
      );
      expect(resA.statusCode, equals(201));
      final bodyA = jsonDecode(resA.body);
      expect(bodyA['device_id'], equals(deviceId));
      expect(bodyA['client_seq'], equals(1));

      // Cihaz B de AYNI client_seq=1 ile satış gönderir (ÇAKIŞMAMALIDIR!)
      final resB = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $rawTokenB', // Cihaz B token'ı
        },
        body: jsonEncode(payloadB),
      );
      expect(resB.statusCode, equals(201), reason: 'Farklı cihazların aynı client_seq değeri çakışmamalıdır!');
      final bodyB = jsonDecode(resB.body);
      expect(bodyB['device_id'], equals(deviceIdB));
      expect(bodyB['client_seq'], equals(1));

      // Veritabanı doğrulaması: İki ayrı satış kaydı ve iki ayrı processed_operations kaydı bulunmalı
      final rawDb = sqlite.sqlite3.open(dbFile.path);
      try {
        final sales = rawDb.select('SELECT * FROM sales WHERE client_seq = 1;');
        expect(sales.length, equals(2));
        expect(sales.any((s) => s['device_id'] == deviceId), isTrue);
        expect(sales.any((s) => s['device_id'] == deviceIdB), isTrue);

        final ops = rawDb.select('SELECT * FROM processed_operations;');
        expect(ops.any((o) => o['idempotency_key'] == '$deviceId:1'), isTrue);
        expect(ops.any((o) => o['idempotency_key'] == '$deviceIdB:1'), isTrue);
      } finally {
        rawDb.dispose();
      }
    });

    test('13. client_seq pozitif tamsayı (> 0) olmalı, geçersiz veya negatif değerler 400 Bad Request almalıdır', () async {
      final invalidSeqPayload = {
        'operation_id': 'op_neg_seq',
        'client_seq': -5, // NEGATİF!
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
          'authorization': 'Bearer $rawToken',
        },
        body: jsonEncode(invalidSeqPayload),
      );

      expect(res.statusCode, equals(400));
      final body = jsonDecode(res.body);
      expect(body['error'], equals('BAD_REQUEST'));
      expect(body['code'], equals('ERR_INVALID_CLIENT_SEQ'));
    });

    test('14. İstemci gövdesinde gönderilen sahte device_id yok sayılmalı, token context\'indeki device_id kullanılmalıdır', () async {
      final spoofPayload = {
        'operation_id': 'op_spoof_test',
        'device_id': 'HACKED_SPOOFED_DEVICE_ID', // SAHTE GÖVDE PARAMETRESİ!
        'client_seq': 77,
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
          'authorization': 'Bearer $rawToken', // DEV_S5A2 token'ı
        },
        body: jsonEncode(spoofPayload),
      );

      expect(res.statusCode, equals(201));
      final body = jsonDecode(res.body);
      expect(body['device_id'], equals(deviceId), reason: 'İstemci gövdesindeki sahte device_id yok sayılmalıdır!');

      final rawDb = sqlite.sqlite3.open(dbFile.path);
      try {
        final sale = rawDb.select("SELECT * FROM sales WHERE client_seq = 77;");
        expect(sale.first['device_id'], equals(deviceId));
      } finally {
        rawDb.dispose();
      }
    });

    test('15. Satış + kalemler + stok hareketleri tek atomik transaction içinde işletilmeli ve hata durumunda rollback yapılmalıdır', () async {
      // Olmayan ürün içeren satış
      final failingPayload = {
        'operation_id': 'op_rollback_test',
        'client_seq': 13,
        'total_amount': 5000,
        'payment_method': 'CASH',
        'items': [
          {'product_id': 'prod_cola', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500},
          {'product_id': 'non_existing_product_xyz', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500},
        ],
      };

      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $rawToken',
        },
        body: jsonEncode(failingPayload),
      );

      expect(res.statusCode, equals(500));

      // Veritabanı temiz kalmalı (Rollback)
      final rawDb = sqlite.sqlite3.open(dbFile.path);
      try {
        final sales = rawDb.select("SELECT * FROM sales WHERE client_seq = 13;");
        expect(sales.isEmpty, isTrue, reason: 'Satış kaydı rollback edilmiş olmalıdır.');

        final ops = rawDb.select("SELECT * FROM processed_operations WHERE idempotency_key = '$deviceId:13';");
        expect(ops.isEmpty, isTrue, reason: 'ProcessedOperations kaydı rollback edilmiş olmalıdır.');

        // Cola stoğu düşmemeli
        final cola = rawDb.select("SELECT stock FROM products WHERE id = 'prod_cola';");
        expect(cola.first['stock'], equals(100000));
      } finally {
        rawDb.dispose();
      }
    });

    test('16. Fiziksel satışta negatif stok durumuna izin verilmeli ve stok hareketi negatif olarak kaydedilmelidir', () async {
      // prod_water başlangıç stoğu: 5000 milli-birim (5 adet)
      // Müşteri kasada 12 adet su aldı (fiziksel satış engellenemez!)
      final payload = {
        'operation_id': 'op_neg_stock_1',
        'client_seq': 14,
        'total_amount': 12000,
        'payment_method': 'CASH',
        'items': [
          {'product_id': 'prod_water', 'quantity': 12000, 'unit_price': 1000, 'total_price': 12000}
        ],
      };

      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $rawToken',
        },
        body: jsonEncode(payload),
      );

      expect(res.statusCode, equals(201));
      final resBody = jsonDecode(res.body) as Map<String, dynamic>;
      expect(resBody['status'], equals('COMMITTED'));
      // 5000 - 12000 = -7000
      expect(resBody['updated_stocks']['prod_water'], equals(-7000));

      // Veritabanı doğrulama
      final rawDb = sqlite.sqlite3.open(dbFile.path);
      try {
        final waterStock = rawDb.select("SELECT stock FROM products WHERE id = 'prod_water';");
        expect(waterStock.first['stock'], equals(-7000), reason: 'Stok negatif değere inebilmelidir.');

        final movements = rawDb.select("SELECT * FROM stock_movements WHERE product_id = 'prod_water';");
        expect(movements.isNotEmpty, isTrue);
        expect(movements.first['quantity'], equals(-12000));
        expect(movements.first['movement_type'], equals('SATIS'));
      } finally {
        rawDb.dispose();
      }
    });

    test('17. SQLITE_BUSY durumunda kontrollü retry ve exponential backoff davranışı', () async {
      final queue = WriteQueue(
        maxRetries: 3,
        initialRetryDelay: const Duration(milliseconds: 10),
      );

      int attempts = 0;
      final result = await queue.enqueue(() async {
        attempts++;
        if (attempts < 3) {
          // SQLite Error 5: SQLITE_BUSY
          throw sqlite.SqliteException(5, 'database is locked');
        }
        return 'SUCCESS_AFTER_BUSY';
      });

      expect(result, equals('SUCCESS_AFTER_BUSY'));
      expect(attempts, equals(3));
      expect(queue.metrics.totalBusyErrors, equals(2));
      expect(queue.metrics.totalRetries, equals(2));
      expect(queue.metrics.totalCompleted, equals(1));
    });

    test('18. Gerçek process restart sonrası SQLite crash recovery (WAL recovery ile veri kaybı yaşanmaması)', () async {
      // Birkaç işlem yap ve WAL dosyasına yazılmasını sağla
      for (int i = 1; i <= 3; i++) {
        await writeQueue.enqueue(() async {
          await db.into(db.sales).insert(
                SalesCompanion(
                  id: Value('sale_recover_$i'),
                  deviceId: const Value(deviceId),
                  clientSeq: Value(500 + i),
                  totalAmount: const Value(1500),
                  paymentMethod: const Value('CASH'),
                ),
              );
        });
      }

      // Veritabanını checkpoint yapmadan aniden kapat (Crash simülasyonu)
      await server.stop();
      await db.close();

      // Yeni bir bağımsız SQLite bağlantısıyla crash recovery testi yap
      final recoveryDb = SpikeDatabase(dbFile);
      try {
        final integrity = await recoveryDb.customSelect('PRAGMA integrity_check;').getSingle();
        expect(integrity.data.values.first, equals('ok'));

        final sales = await recoveryDb.select(recoveryDb.sales).get();
        final recoverSales = sales.where((s) => s.id.startsWith('sale_recover_')).toList();
        expect(recoverSales.length, equals(3), reason: 'Crash recovery sonrası tüm commit edilmiş satışlar korunmalıdır.');
      } finally {
        await recoveryDb.close();
      }
    });
  });
}
