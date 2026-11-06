import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
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
  const testPort = 8993;
  const validToken = 'token_lifecycle_test';

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    configureSqliteNative();
    tempDir = await Directory.systemTemp.createTemp('mms_lifecycle_test_');
    dbFile = File(p.join(tempDir.path, 'lifecycle.db'));

    pepperManager = PepperManager(File(p.join(tempDir.path, 'pepper.dpapi')));
    pepperManager.initialize();

    db = SpikeDatabase(dbFile);
    writeQueue = WriteQueue();

    // Cihaz ve ürün tohumla
    await db.into(db.products).insert(
          ProductsCompanion(
            id: const Value('prod_cola'),
            barcode: const Value('869000000001'),
            name: const Value('Kutu Kola 330ml'),
            price: const Value(2500),
            stock: const Value(100),
          ),
        );

    final salt = TokenManager.generateSalt();
    final hash = TokenManager.hashToken(
      rawToken: validToken,
      salt: salt,
      pepper: pepperManager.pepper,
    );

    await db.into(db.devices).insert(
          DevicesCompanion(
            deviceId: const Value('DEV_DRAIN_01'),
            name: const Value('Drain Test Kasa'),
            tokenHash: Value(hash),
            salt: Value(salt),
            isActive: const Value(true),
          ),
        );

    server = SpikeServer(db: db, writeQueue: writeQueue, pepperManager: pepperManager);
    await server.start(port: testPort);
    baseUrl = 'http://127.0.0.1:$testPort';
  });

  tearDown(() async {
    try {
      await server.stop();
    } catch (_) {}
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  test('Graceful Shutdown: WriteQueue drain ve HTTP 503 SERVICE_DRAINING doğrulaması', () async {
    print('\n======================================================================');
    print('BAŞLADI: Graceful Shutdown ve WriteQueue Drain Testi');
    print('======================================================================\n');

    // 1. Sıraya 3 yavaş yazma işlemi sok (her biri 100ms)
    final completedTasks = <int>[];
    for (int i = 1; i <= 3; i++) {
      writeQueue.enqueue(() async {
        await Future.delayed(const Duration(milliseconds: 100));
        completedTasks.add(i);
        return i;
      });
    }

    expect(writeQueue.metrics.currentQueueLength, equals(3));
    print('[ADIM 1] 3 işlem kuyruğa alındı. Kuyruk boyutu: ${writeQueue.metrics.currentQueueLength}');

    // 2. AdmissionGate kapat (Servis kapanmaya hazırlanıyor)
    server.lifecycle.admissionGate.close();
    expect(server.lifecycle.admissionGate.isOpen, isFalse);
    print('[ADIM 2] AdmissionGate kapatıldı. Yeni HTTP istekleri 503 almalı.');

    // 3. AdmissionGate kapalıyken gelen yeni HTTP isteği 503 SERVICE_DRAINING dönmeli
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/sales'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $validToken',
      },
      body: jsonEncode({
        'operation_id': 'op_rejected_drain',
        'client_seq': 99,
        'total_amount': 2500,
        'payment_method': 'CASH',
        'items': [
          {'product_id': 'prod_cola', 'quantity': 1000, 'unit_price': 2500, 'total_price': 2500}
        ],
      }),
    );

    expect(res.statusCode, equals(503));
    final resBody = jsonDecode(res.body);
    expect(resBody['error'], equals('SERVICE_DRAINING'));
    print('[ADIM 3] Draining sırasında HTTP isteği 503 SERVICE_DRAINING ile reddedildi.');

    // 4. Shutdown (Draining) tetikle
    final shutdownFuture = server.lifecycle.shutdown(reason: 'Test Shutdown');
    expect(writeQueue.isDraining, isTrue);
    print('[ADIM 4] LifecycleManager.shutdown tetiklendi. isDraining = ${writeQueue.isDraining}');

    // 5. Draining sırasında gelen yeni yazma isteği doğrudan ServiceDrainingException fırlatmalı
    expect(
      () => writeQueue.enqueue(() async => 999),
      throwsA(isA<ServiceDrainingException>()),
      reason: 'Draining modundaki kuyruk yeni iş kabul etmemeli!',
    );
    print('[ADIM 5] Draining sırasında kuyruğa ekleme engellendi (ServiceDrainingException fırlatıldı).');

    // 6. Shutdown tamamlanmasını bekle
    await shutdownFuture;
    print('[ADIM 6] Sunucu ve veritabanı güvenle kapandı.');

    // 7. Draining öncesinde kuyruğa alınmış 3 işlemin eksiksiz tamamlandığını doğrula
    expect(completedTasks.length, equals(3));
    expect(completedTasks, equals([1, 2, 3]));
    print('[ADIM 6] Bekleyen tüm 3 işlem kapanmadan önce eksiksiz işlendi: $completedTasks');

    print('\n======================================================================');
    print('BAŞARILI: Graceful Shutdown ve WriteQueue Drain Testi Tamamlandı!');
    print('======================================================================\n');
  });
}

