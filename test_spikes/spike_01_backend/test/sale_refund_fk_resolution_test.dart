// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import '../bin/server.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/pepper_manager.dart';
import '../lib/security/token_manager.dart';

/// MARKET MMS — SALE_REFUND FK Çözümleme Testleri
///
/// Bu test grubu, Windows istemcisinin yerel csale_... ID ile gönderdiği
/// SALE_REFUND isteğinin Hub tarafında device_id + target_client_seq ile
/// doğru Hub sale_...  ID'sine çözümlenmesini doğrular.
void main() {
  late Directory tempDir;
  late File dbFile;
  late SpikeDatabase db;
  late WriteQueue writeQueue;
  late SpikeServer server;
  late PepperManager pepperManager;
  final testPort = 8982; // sales_downlink_api_test.dart'tan farklı port
  final baseUrl = 'http://127.0.0.1:$testPort';
  final validToken = 'mms_pat_refund_fk_token_999';
  final deviceId = 'POS-WIN-TEST-01';

  // Hub tarafındaki gerçek sale ID'si (test kurulumunda oluşturulacak)
  late String hubSaleId;
  // Satışın client_seq'i (target_client_seq olarak kullanılacak)
  final saleClientSeq = 1;

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    tempDir = await Directory.systemTemp.createTemp('mms_refund_fk_test_');
    dbFile = File(p.join(tempDir.path, 'market_master.db'));
    final pepperFile = File(p.join(tempDir.path, 'pepper.dpapi'));
    pepperManager = PepperManager(pepperFile);
    pepperManager.initialize();

    db = SpikeDatabase(dbFile);
    writeQueue = WriteQueue();

    final salt = TokenManager.generateSalt();
    final hash = TokenManager.hashToken(
      rawToken: validToken,
      salt: salt,
      pepper: pepperManager.pepper,
    );

    // Test cihazını kaydet
    await db.into(db.devices).insert(
      DevicesCompanion(
        deviceId: Value(deviceId),
        name: const Value('Windows POS FK Test'),
        tokenHash: Value(hash),
        salt: Value(salt),
        isActive: const Value(true),
        isConfirmed: const Value(true),
      ),
    );

    // Test ürününü ekle
    await db.into(db.products).insert(
      ProductsCompanion(
        id: const Value('prod_fk_test_001'),
        name: const Value('FK Test Ürünü'),
        barcode: const Value('88810001'),
        price: const Value(8500),
        stock: const Value(100000),
        pricingUnit: const Value('adet'),
        stockUnit: const Value('adet'),
        isActive: const Value(true),
      ),
    );

    server = SpikeServer(
      db: db,
      writeQueue: writeQueue,
      dbFile: dbFile,
      backupDirectory: p.join(tempDir.path, 'backups'),
      pepperManager: pepperManager,
      requireTls: false,
    );

    await server.start(port: testPort);

    // Satışı Hub'a kaydet (Windows cihazından SALE_CREATE simülasyonu — 2 adet = 2000 milli-birim)
    final saleBody = {
      'operation_id': 'op_win_fk_sale_$saleClientSeq',
      'client_seq': saleClientSeq,
      'idempotency_key': '$deviceId:$saleClientSeq',
      'total_amount': 17000,
      'payment_method': 'CASH',
      'items': [
        {
          'product_id': 'prod_fk_test_001',
          'quantity': 2000,
          'unit_price': 8500,
          'total_price': 17000,
        }
      ],
    };

    final postRes = await http.post(
      Uri.parse('$baseUrl/api/v1/sales'),
      headers: {
        'Authorization': 'Bearer $validToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(saleBody),
    );
    expect(postRes.statusCode, equals(201), reason: 'Kurulum satışı başarısız');

    // Hub'ın atadığı sale_...  ID'sini al
    final getRes = await http.get(
      Uri.parse('$baseUrl/api/v1/sales?cursor=0'),
      headers: {'Authorization': 'Bearer $validToken'},
    );
    final getBody = jsonDecode(getRes.body) as Map<String, dynamic>;
    final sales = getBody['sales'] as List<dynamic>;
    expect(sales.length, equals(1), reason: 'Kurulum satışı Hub\'da görünmüyor');
    hubSaleId = sales.first['id'] as String;
    print('Kurulum tamamlandı. Hub Sale ID: $hubSaleId, client_seq: $saleClientSeq');
  });

  tearDownAll(() async {
    await server.stop();
    await db.close();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('MARKET MMS — SALE_REFUND FK Çözümleme Testleri', () {
    // -------------------------------------------------------------------------
    // Senaryo 1: Doğrudan Hub sale_... ID ile iade — mevcut davranış korunmalı
    // -------------------------------------------------------------------------
    test(
        'Senaryo 1 — Doğrudan Hub sale_... ID ile iade: 201 ve iade kaydı oluşturulmalı',
        () async {
      final refundClientSeq = 2;
      final refundId = 'ref_fk_direct_$refundClientSeq';
      final refundBody = {
        'operation_id': 'op_win_fk_refund_direct_$refundClientSeq',
        'operation_type': 'SALE_REFUND',
        'client_seq': refundClientSeq,
        'idempotency_key': '$deviceId:$refundClientSeq',
        'refund_id': refundId,
        'sale_id': hubSaleId, // Doğrudan Hub sale_... ID
        'target_client_seq': saleClientSeq,
        'total_refund_amount': 8500,
        'reason': 'Test iadesi — doğrudan Hub ID',
        'items': [
          {
            'sale_id': hubSaleId,
            'product_id': 'prod_fk_test_001',
            'product_name': 'FK Test Ürünü',
            'quantity': 1000,
            'unit_price': 8500,
            'refund_amount': 8500,
          }
        ],
      };

      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'Authorization': 'Bearer $validToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(refundBody),
      );
      expect(res.statusCode, anyOf(200, 201),
          reason: 'Doğrudan Hub ID ile iade başarısız: ${res.body}');

      // Refund kaydını doğrula
      final refunds = await db.select(db.refunds).get();
      expect(refunds.any((r) => r.saleId == hubSaleId), isTrue,
          reason: 'Refund kaydında Hub sale_id görünmüyor');
    });

    // -------------------------------------------------------------------------
    // Senaryo 2: Yerel csale_... ID ile iade + target_client_seq — FK çözümleme
    // -------------------------------------------------------------------------
    test(
        'Senaryo 2 — Yerel csale_... ID + target_client_seq: Hub sale_...  ID\'ye çözümlenmeli ve 201 döner',
        () async {
      final refundClientSeq = 3;
      // Windows istemcisinin gönderdiği yerel csale_... ID simülasyonu
      final localSaleId = 'csale_1795047790128585_${saleClientSeq}_2_abcdef';

      final refundBody = {
        'operation_id': 'op_win_fk_refund_local_$refundClientSeq',
        'operation_type': 'SALE_REFUND',
        'client_seq': refundClientSeq,
        'idempotency_key': '$deviceId:$refundClientSeq',
        'refund_id': 'ref_fk_local_$refundClientSeq',
        'sale_id': localSaleId, // Yerel csale_... ID
        'target_client_seq': saleClientSeq, // device_id + bu seq ile çözümle
        'total_refund_amount': 8500,
        'reason': 'Test iadesi — yerel csale ID çözümleme',
        'items': [
          {
            'sale_id': localSaleId,
            'product_id': 'prod_fk_test_001',
            'product_name': 'FK Test Ürünü',
            'quantity': 1000,
            'unit_price': 8500,
            'refund_amount': 8500,
          }
        ],
      };

      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'Authorization': 'Bearer $validToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(refundBody),
      );
      expect(res.statusCode, anyOf(200, 201),
          reason:
              'csale_ ID\'den Hub ID\'ye çözümleme başarısız: ${res.body}');

      // Refund tablosunda Hub sale_id ile yazılmış olmalı (csale_ ID değil)
      final refunds = await db.select(db.refunds).get();
      final refund = refunds.firstWhere(
        (r) => r.clientSeq == refundClientSeq && r.deviceId == deviceId,
        orElse: () => throw TestFailure(
            'client_seq=$refundClientSeq için refund kaydı bulunamadı'),
      );
      expect(refund.saleId, equals(hubSaleId),
          reason:
              'Refund kaydında csale_ ID yazıldı, Hub sale_...  ID bekleniyor');
      expect(refund.saleId, startsWith('sale_'),
          reason: 'Refund saleId Hub formatında (sale_...) olmalı');
    });

    // -------------------------------------------------------------------------
    // Senaryo 3: Yanlış device_id — 0 eşleşme — 404 fail-closed reddet
    // -------------------------------------------------------------------------
    test(
        'Senaryo 3 — Yanlış device_id ile csale_... ID: 0 eşleşme, HTTP 404 döner',
        () async {
      final refundClientSeq = 1;
      final wrongDeviceToken = 'mms_pat_wrong_device_token_777';
      // Yanlış cihaz için token ekle
      final salt2 = TokenManager.generateSalt();
      final hash2 = TokenManager.hashToken(
        rawToken: wrongDeviceToken,
        salt: salt2,
        pepper: pepperManager.pepper,
      );
      await db.into(db.devices).insert(
        DevicesCompanion(
          deviceId: const Value('POS-WRONG-DEVICE'),
          name: const Value('Yanlış Cihaz'),
          tokenHash: Value(hash2),
          salt: Value(salt2),
          isActive: const Value(true),
          isConfirmed: const Value(true),
        ),
      );

      // POS-WRONG-DEVICE cihazından, POS-WIN-TEST-01'in satışına iade dene
      // device_id=POS-WRONG-DEVICE, target_client_seq=$saleClientSeq → 0 eşleşme
      final refundBody = {
        'operation_id': 'op_wrong_dev_refund_$refundClientSeq',
        'operation_type': 'SALE_REFUND',
        'client_seq': refundClientSeq,
        'idempotency_key': 'POS-WRONG-DEVICE:$refundClientSeq',
        'refund_id': 'ref_wrong_dev_$refundClientSeq',
        'sale_id': 'csale_1795047790128585_${saleClientSeq}_2_wrongdev',
        'target_client_seq': saleClientSeq,
        'total_refund_amount': 8500,
        'reason': 'Test — yanlış cihaz',
        'items': [
          {
            'sale_id': 'csale_wrong',
            'product_id': 'prod_fk_test_001',
            'product_name': 'FK Test Ürünü',
            'quantity': 1000,
            'unit_price': 8500,
            'refund_amount': 8500,
          }
        ],
      };

      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'Authorization': 'Bearer $wrongDeviceToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(refundBody),
      );
      // 0 eşleşme → HTTP 404 ERR_SALE_NOT_FOUND
      expect(res.statusCode, equals(404),
          reason: 'Yanlış device_id\'de 404 bekleniyor: ${res.body}');

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['code'], equals('ERR_SALE_NOT_FOUND'));
      // Hata mesajında "bulunamadı" veya çözümleme başarısız ibaresi olmalı
      final errorText = body.toString().toLowerCase();
      expect(
        errorText.contains('bulunamad') || errorText.contains('çözümleme'),
        isTrue,
        reason: 'Hata mesajında çözümleme hatası açıklaması yok',
      );
    });

    // -------------------------------------------------------------------------
    // Senaryo 4: Var olmayan target_client_seq — 0 eşleşme — 404 fail-closed reddet
    // -------------------------------------------------------------------------
    test(
        'Senaryo 4 — Var olmayan target_client_seq=9999: 0 eşleşme, HTTP 404 döner',
        () async {
      final refundClientSeq = 4;
      final refundBody = {
        'operation_id': 'op_win_fk_refund_notexist_$refundClientSeq',
        'operation_type': 'SALE_REFUND',
        'client_seq': refundClientSeq,
        'idempotency_key': '$deviceId:$refundClientSeq',
        'refund_id': 'ref_notexist_$refundClientSeq',
        'sale_id': 'csale_1795047790128585_9999_2_notexist',
        'target_client_seq': 9999, // Bu client_seq Hub'da yok
        'total_refund_amount': 8500,
        'reason': 'Test — var olmayan seq',
        'items': [
          {
            'sale_id': 'csale_9999',
            'product_id': 'prod_fk_test_001',
            'product_name': 'FK Test Ürünü',
            'quantity': 1000,
            'unit_price': 8500,
            'refund_amount': 8500,
          }
        ],
      };

      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'Authorization': 'Bearer $validToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(refundBody),
      );
      expect(res.statusCode, equals(404),
          reason: 'Var olmayan seq\'de 404 bekleniyor: ${res.body}');

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['code'], equals('ERR_SALE_NOT_FOUND'));
      final errorText = body.toString().toLowerCase();
      expect(
        errorText.contains('bulunamad') || errorText.contains('çözümleme'),
        isTrue,
        reason: 'Hata mesajında çözümleme hatası açıklaması yok',
      );
    });

    // -------------------------------------------------------------------------
    // Senaryo 5: İdempotency — aynı refund isteği iki kez gönderildiğinde
    //            ikinci istek de 200/201 döner, ikinci refund kaydı açılmaz
    // -------------------------------------------------------------------------
    test(
        'Senaryo 5 — İdempotency: aynı SALE_REFUND isteği iki kez gönderildiğinde '
        '200/201 döner ve sadece 1 refund kaydı oluşur',
        () async {
      // Senaryo 2'de client_seq=3 ile refund başarıyla oluşturuldu.
      // Aynı isteği tekrar gönder → idempotency yanıtı bekleniyor.
      final refundClientSeq = 3;
      final localSaleId = 'csale_1795047790128585_${saleClientSeq}_2_abcdef';

      final refundBody = {
        'operation_id': 'op_win_fk_refund_local_$refundClientSeq',
        'operation_type': 'SALE_REFUND',
        'client_seq': refundClientSeq,
        'idempotency_key': '$deviceId:$refundClientSeq',
        'refund_id': 'ref_fk_local_$refundClientSeq',
        'sale_id': localSaleId,
        'target_client_seq': saleClientSeq,
        'total_refund_amount': 8500,
        'reason': 'Test iadesi — yerel csale ID çözümleme',
        'items': [
          {
            'sale_id': localSaleId,
            'product_id': 'prod_fk_test_001',
            'product_name': 'FK Test Ürünü',
            'quantity': 1000,
            'unit_price': 8500,
            'refund_amount': 8500,
          }
        ],
      };

      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: {
          'Authorization': 'Bearer $validToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(refundBody),
      );
      expect(res.statusCode, anyOf(200, 201),
          reason: 'İdempotency tekrar isteği başarısız: ${res.body}');

      // Sadece 1 refund kaydı olmalı (client_seq=3 için)
      final refunds = await db.select(db.refunds).get();
      final matchingRefunds = refunds
          .where((r) => r.clientSeq == refundClientSeq && r.deviceId == deviceId)
          .toList();
      expect(matchingRefunds.length, equals(1),
          reason:
              'İdempotency ihlali: client_seq=$refundClientSeq için ${matchingRefunds.length} refund kaydı var');
    });
  });
}
