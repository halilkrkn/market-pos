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
import '../lib/sync/canonical_payload_hasher.dart';

class _IntegrityTestEnv {
  final Directory tempDir;
  final SpikeDatabase db;
  final SpikeServer server;
  final PepperManager pepperManager;
  final String baseUrl;
  final String deviceId;
  final String token;

  _IntegrityTestEnv._({
    required this.tempDir,
    required this.db,
    required this.server,
    required this.pepperManager,
    required this.baseUrl,
    required this.deviceId,
    required this.token,
  });

  static int _nextPort = 8970;
  static int _opSeq = 0;

  static Future<_IntegrityTestEnv> create({
    String deviceId = 'POS-BK0211-01',
    String token = 'tok_bk0211_primary',
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('mms_bk02_1_1_');
    final dbFile = File(p.join(tempDir.path, 'market_master.db'));
    final pepperFile = File(p.join(tempDir.path, 'pepper.dpapi'));
    final pepper = PepperManager(pepperFile)..initialize();
    final db = SpikeDatabase(dbFile);

    await seedDevice(
      db: db,
      pepper: pepper,
      deviceId: deviceId,
      token: token,
    );

    await db.into(db.products).insertOnConflictUpdate(
          ProductsCompanion(
            id: const Value('prod_sut'),
            barcode: const Value('86900011001'),
            name: const Value('Tam Yağlı Süt 1L'),
            price: const Value(3000), // 30.00 TL
            stock: const Value(50000), // 50 adet (scale=1000)
            stockUnit: const Value('adet'),
            pricingUnit: const Value('adet'),
            conversionFactorNumerator: const Value(1),
            conversionFactorDenominator: const Value(1),
          ),
        );

    await db.into(db.products).insertOnConflictUpdate(
          ProductsCompanion(
            id: const Value('prod_peynir'),
            barcode: const Value('86900011002'),
            name: const Value('Beyaz Peynir Kg'),
            price: const Value(15), // 0.15 TL (Half-Up kuruş testi için de uygun)
            stock: const Value(10000), // 10 kg = 10000 g
            stockUnit: const Value('g'),
            pricingUnit: const Value('kg'),
            conversionFactorNumerator: const Value(1),
            conversionFactorDenominator: const Value(1),
          ),
        );

    final port = _nextPort++;
    final server = SpikeServer(
      db: db,
      dbFile: dbFile,
      writeQueue: WriteQueue(),
      backupDirectory: p.join(tempDir.path, 'backups'),
      pepperManager: pepper,
    );
    await server.start(
      address: InternetAddress.loopbackIPv4,
      port: port,
      enableDiscovery: false,
    );

    return _IntegrityTestEnv._(
      tempDir: tempDir,
      db: db,
      server: server,
      pepperManager: pepper,
      baseUrl: 'http://127.0.0.1:$port',
      deviceId: deviceId,
      token: token,
    );
  }

  static Future<void> seedDevice({
    required SpikeDatabase db,
    required PepperManager pepper,
    required String deviceId,
    required String token,
  }) async {
    final salt = TokenManager.generateSalt();
    final hash = TokenManager.hashToken(
      rawToken: token,
      salt: salt,
      pepper: pepper.pepper,
    );
    await db.into(db.devices).insertOnConflictUpdate(
          DevicesCompanion(
            deviceId: Value(deviceId),
            name: Value('Terminal $deviceId'),
            tokenHash: Value(hash),
            salt: Value(salt),
            isActive: const Value(true),
            isConfirmed: const Value(true),
          ),
        );
  }

  Map<String, String> headers({String? customToken}) => {
        'content-type': 'application/json',
        'authorization': 'Bearer ${customToken ?? token}',
        'x-mms-tenant-id': SpikeServer.defaultTenantId,
        'x-mms-store-id': SpikeServer.defaultStoreId,
      };

  Future<http.Response> postSales(
    Map<String, dynamic> body, {
    String? customToken,
  }) =>
      http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: headers(customToken: customToken),
        body: jsonEncode(body),
      );

  Future<String> createSale({
    required int clientSeq,
    String productId = 'prod_sut',
    int quantity = 2000,
    int unitPrice = 3000,
    int? totalAmount,
    String paymentMethod = 'CASH',
    List<Map<String, dynamic>>? customItems,
    String? customToken,
  }) async {
    final items = customItems ??
        [
          {
            'product_id': productId,
            'quantity': quantity,
            'unit_price': unitPrice,
            'total_price': ((unitPrice * quantity) + 500) ~/ 1000,
          }
        ];
    final computedTotal = totalAmount ??
        items.fold<int>(0, (sum, item) => sum + (item['total_price'] as int));

    final res = await postSales(
      {
        'operation_id': 'op_sale_${clientSeq}_${++_opSeq}',
        'operation_type': 'SALE_CREATE',
        'client_seq': clientSeq,
        'total_amount': computedTotal,
        'payment_method': paymentMethod,
        'items': items,
      },
      customToken: customToken,
    );
    expect(res.statusCode, equals(201), reason: res.body);
    return (jsonDecode(res.body) as Map<String, dynamic>)['sale_id'] as String;
  }

  Future<void> dispose() async {
    await server.stop();
    await db.close();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  }
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    configureSqliteNative();
  });

  group('BK-02.1.1 Grup 1 — SALE_CANCEL Bütünlüğü ve Stok Koruması', () {
    test('TC-C01: Bulunamayan satışın iptali 404 döner; stok, hareket veya receipt oluşmaz, HWM ilerlemez', () async {
      final env = await _IntegrityTestEnv.create();
      addTearDown(env.dispose);

      final res1 = await env.postSales({
        'operation_id': 'op_cancel_missing_1',
        'operation_type': 'SALE_CANCEL',
        'client_seq': 1,
        'sale_id': 'sale_olmayan_id',
        'reason': 'Olmayan satış',
      });
      expect(res1.statusCode, equals(404), reason: res1.body);
      expect((jsonDecode(res1.body) as Map)['code'], equals('ERR_SALE_NOT_FOUND'));

      final res2 = await env.postSales({
        'operation_id': 'op_cancel_missing_2',
        'operation_type': 'SALE_CANCEL',
        'client_seq': 1,
        'sale_id': 'csale_olmayan_yerel',
        'target_client_seq': 999,
        'reason': 'Olmayan seq',
      });
      expect(res2.statusCode, equals(404), reason: res2.body);

      expect(await env.db.select(env.db.processedOperations).get(), isEmpty);
      expect(await env.db.select(env.db.stockMovements).get(), isEmpty);
      final dev = await (env.db.select(env.db.devices)
            ..where((d) => d.deviceId.equals(env.deviceId)))
          .getSingle();
      expect(dev.lastCommittedClientSeq, equals(0));
      expect(dev.maxSeenClientSeq, equals(0));
    });

    test('TC-C02: Başka cihazın yerel csale_+target_client_seq referansıyla iptal 404 reddedilir; gerçek Hub ID ile farklı cihaz çakışmaz', () async {
      final env = await _IntegrityTestEnv.create();
      addTearDown(env.dispose);

      const secondDevId = 'POS-BK0211-02';
      const secondToken = 'tok_bk0211_secondary';
      await _IntegrityTestEnv.seedDevice(
        db: env.db,
        pepper: env.pepperManager,
        deviceId: secondDevId,
        token: secondToken,
      );

      // Cihaz 1 satış yapar (seq=1)
      final dev1SaleId = await env.createSale(clientSeq: 1, quantity: 2000);
      // Cihaz 2 kendi satışını yapar (seq=1) — aynı client_seq=1 fakat farklı ürün/miktar
      final dev2SaleId = await env.createSale(
        clientSeq: 1,
        productId: 'prod_peynir',
        quantity: 1000,
        unitPrice: 15,
        customToken: secondToken,
      );

      // Cihaz 2 yerel csale_+target_client_seq=99 ile Cihaz 1'i taklit edemez -> 404
      final spoofRes = await env.postSales(
        {
          'operation_id': 'op_spoof_cancel',
          'operation_type': 'SALE_CANCEL',
          'client_seq': 2,
          'sale_id': 'csale_forged_1',
          'target_client_seq': 99,
          'reason': 'Geçersiz referans',
        },
        customToken: secondToken,
      );
      expect(spoofRes.statusCode, equals(404), reason: spoofRes.body);

      // Cihaz 2 doğrudan Hub'dan indirdiği dev1SaleId ile Cihaz 1'in satışını iptal ettiğinde,
      // payload'da target_client_seq=1 olsa bile Cihaz 2'nin kendi dev2SaleId satışı YANLIŞLIKLA iptal edilmemelidir!
      final crossCancelRes = await env.postSales(
        {
          'operation_id': 'op_cross_cancel',
          'operation_type': 'SALE_CANCEL',
          'client_seq': 2,
          'sale_id': dev1SaleId,
          'target_client_seq': 1,
          'reason': 'Merkezi terminalden iptal',
        },
        customToken: secondToken,
      );
      expect(crossCancelRes.statusCode, equals(201), reason: crossCancelRes.body);

      final sale1After = await (env.db.select(env.db.sales)
            ..where((s) => s.id.equals(dev1SaleId)))
          .getSingle();
      final sale2After = await (env.db.select(env.db.sales)
            ..where((s) => s.id.equals(dev2SaleId)))
          .getSingle();
      expect(sale1After.status, equals('CANCELLED'));
      expect(sale2After.status, equals('COMPLETED'));
    });

    test('TC-C03: Aynı satışın farklı client_seq ile iki kez iptali 409 ile engellenir; stok ikinci kez artmaz', () async {
      final env = await _IntegrityTestEnv.create();
      addTearDown(env.dispose);

      final saleId = await env.createSale(clientSeq: 1, quantity: 3000);
      final stockAfterSale = (await (env.db.select(env.db.products)
                ..where((p) => p.id.equals('prod_sut')))
              .getSingle())
          .stock;
      expect(stockAfterSale, equals(47000));

      // 1. İptal (seq=2) -> Başarılı, stok 47000 -> 50000
      final cancel1 = await env.postSales({
        'operation_id': 'op_cancel_1',
        'operation_type': 'SALE_CANCEL',
        'client_seq': 2,
        'sale_id': saleId,
        'target_client_seq': 1,
        'reason': 'İlk iptal',
      });
      expect(cancel1.statusCode, equals(201), reason: cancel1.body);

      // 2. İptal girişimi (seq=3, farklı client_seq) -> 409 ERR_SALE_ALREADY_CANCELLED
      final cancel2 = await env.postSales({
        'operation_id': 'op_cancel_2',
        'operation_type': 'SALE_CANCEL',
        'client_seq': 3,
        'sale_id': saleId,
        'target_client_seq': 1,
        'reason': 'İkinci iptal denemesi',
      });
      expect(cancel2.statusCode, equals(409), reason: cancel2.body);
      expect(
        (jsonDecode(cancel2.body) as Map)['code'],
        equals('ERR_SALE_ALREADY_CANCELLED'),
      );

      final prod = await (env.db.select(env.db.products)
            ..where((p) => p.id.equals('prod_sut')))
          .getSingle();
      expect(prod.stock, equals(50000)); // Asla 53000 olmaz!

      final cancelMovements = await (env.db.select(env.db.stockMovements)
            ..where((m) =>
                m.referenceId.equals(saleId) &
                m.movementType.equals('SATIS_IPTALI')))
          .get();
      expect(cancelMovements.length, equals(1));

      final ops = await (env.db.select(env.db.processedOperations)
            ..where((o) => o.deviceId.equals(env.deviceId)))
          .get();
      expect(ops.map((o) => o.clientSeq).toList()..sort(), equals([1, 2]));

      final dev = await (env.db.select(env.db.devices)
            ..where((d) => d.deviceId.equals(env.deviceId)))
          .getSingle();
      expect(dev.lastCommittedClientSeq, equals(2));
      expect(dev.maxSeenClientSeq, equals(2));
    });

    test('TC-C04: Tam iade edilmiş (REFUNDED) satışa iptal denemesi 409 döner', () async {
      final env = await _IntegrityTestEnv.create();
      addTearDown(env.dispose);

      final saleId = await env.createSale(clientSeq: 1, quantity: 2000);

      final refundRes = await env.postSales({
        'operation_id': 'op_full_ref_before_cancel',
        'operation_type': 'SALE_REFUND',
        'client_seq': 2,
        'refund_id': 'ref_full_before_cancel',
        'sale_id': saleId,
        'target_client_seq': 1,
        'total_refund_amount': 6000,
        'reason': 'Tam iade',
        'items': [
          {
            'product_id': 'prod_sut',
            'quantity': 2000,
            'unit_price': 3000,
            'refund_amount': 6000,
            'product_condition': 'SELLABLE',
          }
        ],
      });
      expect(refundRes.statusCode, equals(201), reason: refundRes.body);

      final cancelAfterFullRefund = await env.postSales({
        'operation_id': 'op_cancel_after_full_refund',
        'operation_type': 'SALE_CANCEL',
        'client_seq': 3,
        'sale_id': saleId,
        'target_client_seq': 1,
        'reason': 'Tam iade sonrası iptal',
      });
      expect(cancelAfterFullRefund.statusCode, equals(409));
      expect(
        (jsonDecode(cancelAfterFullRefund.body) as Map)['code'],
        equals('ERR_SALE_ALREADY_REFUNDED'),
      );

      final sale = await (env.db.select(env.db.sales)
            ..where((s) => s.id.equals(saleId)))
          .getSingle();
      expect(sale.status, equals('REFUNDED'));
      final prod = await (env.db.select(env.db.products)
            ..where((p) => p.id.equals('prod_sut')))
          .getSingle();
      expect(prod.stock, equals(50000));
    });

    test('TC-C05 & TC-C06: Kısmi SELLABLE ve DAMAGED iade sonrası SALE_CANCEL yalnızca kalan miktarı stoğa ekler', () async {
      final env = await _IntegrityTestEnv.create();
      addTearDown(env.dispose);

      // 5 adet Süt (5000) ve 3 kg Peynir (3000) içeren tek satış -> seq=1
      final saleId = await env.createSale(
        clientSeq: 1,
        customItems: [
          {
            'product_id': 'prod_sut',
            'quantity': 5000,
            'unit_price': 3000,
            'total_price': 15000,
          },
          {
            'product_id': 'prod_peynir',
            'quantity': 3000,
            'unit_price': 15,
            'total_price': 45,
          },
        ],
      );
      // Başlangıç stokları: sut=50000->45000, peynir=10000->7000

      // seq=2: Süt'ten 2 adet SELLABLE (+2000 stok), Peynir'den 1 kg DAMAGED (stok artmaz, FIRE_KAYIP) kısmi iade
      final partialRefund = await env.postSales({
        'operation_id': 'op_part_ref_cond',
        'operation_type': 'SALE_REFUND',
        'client_seq': 2,
        'refund_id': 'ref_part_cond',
        'sale_id': saleId,
        'target_client_seq': 1,
        'total_refund_amount': 6015,
        'reason': 'Kısmi iade (SELLABLE + DAMAGED)',
        'items': [
          {
            'product_id': 'prod_sut',
            'quantity': 2000,
            'unit_price': 3000,
            'refund_amount': 6000,
            'product_condition': 'SELLABLE',
          },
          {
            'product_id': 'prod_peynir',
            'quantity': 1000,
            'unit_price': 15,
            'refund_amount': 15,
            'product_condition': 'DAMAGED',
          },
        ],
      });
      expect(partialRefund.statusCode, equals(201), reason: partialRefund.body);

      final sutMid = (await (env.db.select(env.db.products)
                ..where((p) => p.id.equals('prod_sut')))
              .getSingle())
          .stock;
      final peynirMid = (await (env.db.select(env.db.products)
                ..where((p) => p.id.equals('prod_peynir')))
              .getSingle())
          .stock;
      expect(sutMid, equals(47000)); // 45000 + 2000
      expect(peynirMid, equals(7000)); // DAMAGED artırmadı

      // seq=3: Kalan satışın iptali
      // Beklenen: Süt için yalnızca kalan 3000 stoğa eklenir -> 47000 + 3000 = 50000
      // Beklenen: Peynir için DAMAGED olan 1000 stoğa eklenmez, yalnızca kalan 2000 eklenir -> 7000 + 2000 = 9000
      final cancelRes = await env.postSales({
        'operation_id': 'op_cancel_after_partial',
        'operation_type': 'SALE_CANCEL',
        'client_seq': 3,
        'sale_id': saleId,
        'target_client_seq': 1,
        'reason': 'Kalan satışı iptal',
      });
      expect(cancelRes.statusCode, equals(201), reason: cancelRes.body);

      final sutFinal = (await (env.db.select(env.db.products)
                ..where((p) => p.id.equals('prod_sut')))
              .getSingle())
          .stock;
      final peynirFinal = (await (env.db.select(env.db.products)
                ..where((p) => p.id.equals('prod_peynir')))
              .getSingle())
          .stock;
      expect(sutFinal, equals(50000));
      expect(peynirFinal, equals(9000)); // 10000 - 1000 DAMAGED/FIRE_KAYIP
    });

    test('TC-C07: SALE_CANCEL boş reason (400), Idempotent Replay (200) ve Payload Mismatch (409)', () async {
      final env = await _IntegrityTestEnv.create();
      addTearDown(env.dispose);

      final saleId = await env.createSale(clientSeq: 1, quantity: 1000);

      final emptyReasonRes = await env.postSales({
        'operation_id': 'op_cancel_empty_reason',
        'operation_type': 'SALE_CANCEL',
        'client_seq': 2,
        'sale_id': saleId,
        'reason': '   ',
      });
      expect(emptyReasonRes.statusCode, equals(400));

      final cancelBody = {
        'operation_id': 'op_cancel_replay_2',
        'operation_type': 'SALE_CANCEL',
        'client_seq': 2,
        'sale_id': saleId,
        'target_client_seq': 1,
        'reason': 'Müşteri vazgeçti',
      };
      final firstRes = await env.postSales(cancelBody);
      expect(firstRes.statusCode, equals(201), reason: firstRes.body);

      // Aynı seq=2 + aynı payload -> Idempotent Replay (200 OK, ikinci kez stok artmaz)
      final replayRes = await env.postSales(cancelBody);
      expect(replayRes.statusCode, equals(200), reason: replayRes.body);
      expect(replayRes.headers['x-mms-idempotent-replay'], equals('true'));

      // Aynı seq=2 + farklı reason -> 409 ERR_IDEMPOTENCY_PAYLOAD_MISMATCH
      final mismatchRes = await env.postSales({
        ...cancelBody,
        'reason': 'Farklı gerekçe',
      });
      expect(mismatchRes.statusCode, equals(409));
      expect(
        (jsonDecode(mismatchRes.body) as Map)['code'],
        equals('ERR_IDEMPOTENCY_PAYLOAD_MISMATCH'),
      );

      final prod = await (env.db.select(env.db.products)
            ..where((p) => p.id.equals('prod_sut')))
          .getSingle();
      expect(prod.stock, equals(50000));
    });

    test('TC-C08: Eşzamanlı (Future.wait) çift SALE_CANCEL talebinde yalnızca biri commit olur, stok 1 kez döner', () async {
      final env = await _IntegrityTestEnv.create();
      addTearDown(env.dispose);

      final saleId = await env.createSale(clientSeq: 1, quantity: 2000);

      final req1 = env.postSales({
        'operation_id': 'op_conc_cancel_2',
        'operation_type': 'SALE_CANCEL',
        'client_seq': 2,
        'sale_id': saleId,
        'target_client_seq': 1,
        'reason': 'Eşzamanlı iptal 1',
      });
      final req2 = env.postSales({
        'operation_id': 'op_conc_cancel_3',
        'operation_type': 'SALE_CANCEL',
        'client_seq': 3,
        'sale_id': saleId,
        'target_client_seq': 1,
        'reason': 'Eşzamanlı iptal 2',
      });

      final responses = await Future.wait([req1, req2]);
      final codes = responses.map((r) => r.statusCode).toList()..sort();
      // İkisi aynı anda gelirse sıra gereği: (2 = 201, 3 = 409 ERR_SALE_ALREADY_CANCELLED)
      // veya eğer req2 kuyruğa erken girdiyse (3 = 409 ERR_CLIENT_SEQ_GAP, 2 = 201).
      expect(codes, equals([201, 409]));

      final prod = await (env.db.select(env.db.products)
            ..where((p) => p.id.equals('prod_sut')))
          .getSingle();
      expect(prod.stock, equals(50000));
    });
  });

  group('BK-02.1.1 Grup 2 — SALE_REFUND Bütünlüğü, Over-Refund ve Finansal Kesinlik', () {
    test('TC-R01: Bulunamayan satışa iade (target_client_seq mevcut geçersiz ve target_client_seq=null) 404 döner, yetim stok/receipt yazılmaz', () async {
      final env = await _IntegrityTestEnv.create();
      addTearDown(env.dispose);

      // Durum A: target_client_seq = 999 geçersiz
      final resWithSeq = await env.postSales({
        'operation_id': 'op_ref_missing_seq',
        'operation_type': 'SALE_REFUND',
        'client_seq': 1,
        'refund_id': 'ref_missing_seq',
        'sale_id': 'csale_yok_999',
        'target_client_seq': 999,
        'total_refund_amount': 3000,
        'reason': 'Olmayan satış iadesi',
        'items': [
          {
            'product_id': 'prod_sut',
            'quantity': 1000,
            'unit_price': 3000,
            'refund_amount': 3000,
            'product_condition': 'SELLABLE',
          }
        ],
      });
      expect(resWithSeq.statusCode, equals(404), reason: resWithSeq.body);
      expect((jsonDecode(resWithSeq.body) as Map)['code'], equals('ERR_SALE_NOT_FOUND'));

      // Durum B: target_client_seq = null + geçersiz sale_id (eski BUG senaryosu!)
      final resWithoutSeq = await env.postSales({
        'operation_id': 'op_ref_missing_no_seq',
        'operation_type': 'SALE_REFUND',
        'client_seq': 1,
        'refund_id': 'ref_missing_no_seq',
        'sale_id': 'sale_olmayan_direct',
        'total_refund_amount': 3000,
        'reason': 'Olmayan satış iadesi target seq yok',
        'items': [
          {
            'product_id': 'prod_sut',
            'quantity': 1000,
            'unit_price': 3000,
            'refund_amount': 3000,
            'product_condition': 'SELLABLE',
          }
        ],
      });
      expect(resWithoutSeq.statusCode, equals(404), reason: resWithoutSeq.body);
      expect((jsonDecode(resWithoutSeq.body) as Map)['code'], equals('ERR_SALE_NOT_FOUND'));

      expect(await env.db.select(env.db.refunds).get(), isEmpty);
      expect(await env.db.select(env.db.refundItems).get(), isEmpty);
      expect(await env.db.select(env.db.stockMovements).get(), isEmpty);
      expect(await env.db.select(env.db.processedOperations).get(), isEmpty);
      final prod = await (env.db.select(env.db.products)
            ..where((p) => p.id.equals('prod_sut')))
          .getSingle();
      expect(prod.stock, equals(50000));
    });

    test('TC-R02: CANCELLED satışa iade girişimi 409 ERR_SALE_ALREADY_CANCELLED ile reddedilir', () async {
      final env = await _IntegrityTestEnv.create();
      addTearDown(env.dispose);

      final saleId = await env.createSale(clientSeq: 1, quantity: 2000);
      final cancelRes = await env.postSales({
        'operation_id': 'op_c_1',
        'operation_type': 'SALE_CANCEL',
        'client_seq': 2,
        'sale_id': saleId,
        'target_client_seq': 1,
        'reason': 'İptal',
      });
      expect(cancelRes.statusCode, equals(201));

      final refundOnCancelled = await env.postSales({
        'operation_id': 'op_ref_on_cancelled',
        'operation_type': 'SALE_REFUND',
        'client_seq': 3,
        'refund_id': 'ref_on_cancelled',
        'sale_id': saleId,
        'target_client_seq': 1,
        'total_refund_amount': 3000,
        'reason': 'İptal edilmiş satışa iade',
        'items': [
          {
            'product_id': 'prod_sut',
            'quantity': 1000,
            'unit_price': 3000,
            'refund_amount': 3000,
            'product_condition': 'SELLABLE',
          }
        ],
      });
      expect(refundOnCancelled.statusCode, equals(409));
      expect(
        (jsonDecode(refundOnCancelled.body) as Map)['code'],
        equals('ERR_SALE_ALREADY_CANCELLED'),
      );

      expect(await env.db.select(env.db.refunds).get(), isEmpty);
      final dev = await (env.db.select(env.db.devices)
            ..where((d) => d.deviceId.equals(env.deviceId)))
          .getSingle();
      expect(dev.lastCommittedClientSeq, equals(2));
    });

    test('TC-R03 & TC-R04: Çoklu kısmi iade -> tam iade (REFUNDED), ödeme yöntemi mirası (CARD) ve tam iade sonrası 409 reddi', () async {
      final env = await _IntegrityTestEnv.create();
      addTearDown(env.dispose);

      final saleId = await env.createSale(
        clientSeq: 1,
        quantity: 3000,
        paymentMethod: 'CARD',
      );

      // 1. Kısmi iade (1000) -> PARTIALLY_REFUNDED
      final ref1 = await env.postSales({
        'operation_id': 'op_ref_p1',
        'operation_type': 'SALE_REFUND',
        'client_seq': 2,
        'refund_id': 'ref_p1',
        'sale_id': saleId,
        'target_client_seq': 1,
        'total_refund_amount': 3000,
        'reason': '1. kısmi iade',
        'items': [
          {
            'product_id': 'prod_sut',
            'quantity': 1000,
            'unit_price': 3000,
            'refund_amount': 3000,
            'product_condition': 'SELLABLE',
          }
        ],
      });
      expect(ref1.statusCode, equals(201), reason: ref1.body);
      expect(
        (await (env.db.select(env.db.sales)..where((s) => s.id.equals(saleId))).getSingle()).status,
        equals('PARTIALLY_REFUNDED'),
      );

      // 2. Kısmi iade (2000) -> kümülatif 3000/3000 -> REFUNDED
      final ref2 = await env.postSales({
        'operation_id': 'op_ref_p2',
        'operation_type': 'SALE_REFUND',
        'client_seq': 3,
        'refund_id': 'ref_p2',
        'sale_id': saleId,
        'target_client_seq': 1,
        'total_refund_amount': 6000,
        'reason': '2. kısmi iade tamamlama',
        'items': [
          {
            'product_id': 'prod_sut',
            'quantity': 2000,
            'unit_price': 3000,
            'refund_amount': 6000,
            'product_condition': 'SELLABLE',
          }
        ],
      });
      expect(ref2.statusCode, equals(201), reason: ref2.body);

      final saleAfterFull = await (env.db.select(env.db.sales)
            ..where((s) => s.id.equals(saleId)))
          .getSingle();
      expect(saleAfterFull.status, equals('REFUNDED'));

      // İade payment_method değerleri orijinal satışın ('CARD') değerini miras almalı
      final allRefunds = await (env.db.select(env.db.refunds)
            ..where((r) => r.saleId.equals(saleId)))
          .get();
      expect(allRefunds.length, equals(2));
      for (final r in allRefunds) {
        expect(r.paymentMethod, equals('CARD'));
      }

      // 3. Tam iade sonrası yeni iade girişimi (seq=4) -> 409 ERR_SALE_ALREADY_REFUNDED
      final overAfterFull = await env.postSales({
        'operation_id': 'op_ref_after_full',
        'operation_type': 'SALE_REFUND',
        'client_seq': 4,
        'refund_id': 'ref_after_full',
        'sale_id': saleId,
        'target_client_seq': 1,
        'total_refund_amount': 3000,
        'reason': 'Tam iade sonrası yeni iade',
        'items': [
          {
            'product_id': 'prod_sut',
            'quantity': 1000,
            'unit_price': 3000,
            'refund_amount': 3000,
            'product_condition': 'SELLABLE',
          }
        ],
      });
      expect(overAfterFull.statusCode, equals(409));
      expect(
        (jsonDecode(overAfterFull.body) as Map)['code'],
        equals('ERR_SALE_ALREADY_REFUNDED'),
      );

      final dev = await (env.db.select(env.db.devices)
            ..where((d) => d.deviceId.equals(env.deviceId)))
          .getSingle();
      expect(dev.lastCommittedClientSeq, equals(3));

      // seq=2 idempotent replay hâlâ 200 OK dönmeli (replay kontrolü durum kontrolünden önce)
      final replayRef1 = await env.postSales({
        'operation_id': 'op_ref_p1',
        'operation_type': 'SALE_REFUND',
        'client_seq': 2,
        'refund_id': 'ref_p1',
        'sale_id': saleId,
        'target_client_seq': 1,
        'total_refund_amount': 3000,
        'reason': '1. kısmi iade',
        'items': [
          {
            'product_id': 'prod_sut',
            'quantity': 1000,
            'unit_price': 3000,
            'refund_amount': 3000,
            'product_condition': 'SELLABLE',
          }
        ],
      });
      expect(replayRef1.statusCode, equals(200));
      expect(replayRef1.headers['x-mms-idempotent-replay'], equals('true'));
    });

    test('TC-R05: Tek seferde, kümülatif ve aynı istek içi mükerrer satırla fazla miktar iadesi 409 reddedilir', () async {
      final env = await _IntegrityTestEnv.create();
      addTearDown(env.dispose);

      final saleId = await env.createSale(clientSeq: 1, quantity: 2000);

      // A. Tek seferde 3000 > 2000 -> 409 ERR_REFUND_EXCEEDS_SALE
      final singleOver = await env.postSales({
        'operation_id': 'op_over_single',
        'operation_type': 'SALE_REFUND',
        'client_seq': 2,
        'refund_id': 'ref_over_single',
        'sale_id': saleId,
        'target_client_seq': 1,
        'total_refund_amount': 9000,
        'reason': 'Tek seferde aşım',
        'items': [
          {
            'product_id': 'prod_sut',
            'quantity': 3000,
            'unit_price': 3000,
            'refund_amount': 9000,
            'product_condition': 'SELLABLE',
          }
        ],
      });
      expect(singleOver.statusCode, equals(409), reason: singleOver.body);
      expect((jsonDecode(singleOver.body) as Map)['code'], equals('ERR_REFUND_EXCEEDS_SALE'));

      // B. Aynı istek içinde aynı ürünü iki satıra bölüp (1200 + 1200 = 2400 > 2000) aşma denemesi -> 409
      final splitOver = await env.postSales({
        'operation_id': 'op_over_split',
        'operation_type': 'SALE_REFUND',
        'client_seq': 2,
        'refund_id': 'ref_over_split',
        'sale_id': saleId,
        'target_client_seq': 1,
        'total_refund_amount': 7200,
        'reason': 'Çift satır bypass denemesi',
        'items': [
          {
            'product_id': 'prod_sut',
            'quantity': 1200,
            'unit_price': 3000,
            'refund_amount': 3600,
            'product_condition': 'SELLABLE',
          },
          {
            'product_id': 'prod_sut',
            'quantity': 1200,
            'unit_price': 3000,
            'refund_amount': 3600,
            'product_condition': 'SELLABLE',
          },
        ],
      });
      expect(splitOver.statusCode, equals(409), reason: splitOver.body);
      expect((jsonDecode(splitOver.body) as Map)['code'], equals('ERR_REFUND_EXCEEDS_SALE'));

      // C. Geçerli 1200 iade (seq=2) -> 201
      final validFirst = await env.postSales({
        'operation_id': 'op_ref_ok_1200',
        'operation_type': 'SALE_REFUND',
        'client_seq': 2,
        'refund_id': 'ref_ok_1200',
        'sale_id': saleId,
        'target_client_seq': 1,
        'total_refund_amount': 3600,
        'reason': '1.2 adet kısmi iade',
        'items': [
          {
            'product_id': 'prod_sut',
            'quantity': 1200,
            'unit_price': 3000,
            'refund_amount': 3600,
            'product_condition': 'SELLABLE',
          }
        ],
      });
      expect(validFirst.statusCode, equals(201));

      // D. Kalan 800 varken 1000 isteme (seq=3) -> 409
      final cumOver = await env.postSales({
        'operation_id': 'op_over_cum',
        'operation_type': 'SALE_REFUND',
        'client_seq': 3,
        'refund_id': 'ref_over_cum',
        'sale_id': saleId,
        'target_client_seq': 1,
        'total_refund_amount': 3000,
        'reason': 'Kümülatif aşım',
        'items': [
          {
            'product_id': 'prod_sut',
            'quantity': 1000,
            'unit_price': 3000,
            'refund_amount': 3000,
            'product_condition': 'SELLABLE',
          }
        ],
      });
      expect(cumOver.statusCode, equals(409), reason: cumOver.body);
      expect((jsonDecode(cumOver.body) as Map)['code'], equals('ERR_REFUND_EXCEEDS_SALE'));

      // HWM hâlâ 2 olmalı ve aynı seq=3 ile geçerli 800 gönderildiğinde FIFO devam etmeli!
      final devBeforeFix = await (env.db.select(env.db.devices)
            ..where((d) => d.deviceId.equals(env.deviceId)))
          .getSingle();
      expect(devBeforeFix.lastCommittedClientSeq, equals(2));

      final validSecond = await env.postSales({
        'operation_id': 'op_ref_ok_800',
        'operation_type': 'SALE_REFUND',
        'client_seq': 3,
        'refund_id': 'ref_ok_800',
        'sale_id': saleId,
        'target_client_seq': 1,
        'total_refund_amount': 2400,
        'reason': 'Kalan 0.8 adet iade',
        'items': [
          {
            'product_id': 'prod_sut',
            'quantity': 800,
            'unit_price': 3000,
            'refund_amount': 2400,
            'product_condition': 'SELLABLE',
          }
        ],
      });
      expect(validSecond.statusCode, equals(201), reason: validSecond.body);
      expect(
        (await (env.db.select(env.db.sales)..where((s) => s.id.equals(saleId))).getSingle()).status,
        equals('REFUNDED'),
      );
    });

    test('TC-R06: Satışta olmayan ürün, snapshot unit_price uyumsuzluğu, Half-Up tutar sapması ve total_refund_amount aşımı reddedilir', () async {
      final env = await _IntegrityTestEnv.create();
      addTearDown(env.dispose);

      // 1 kg peynir @ 15 kuruş (seq=1) + Half-Up yuvarlama testi için 333g -> ((15*333)+500)~/1000 = 5495~/1000 = 5 kuruş; 500g -> ((15*500)+500)~/1000 = 8000~/1000 = 8 kuruş
      final saleId = await env.createSale(
        clientSeq: 1,
        productId: 'prod_peynir',
        quantity: 1000,
        unitPrice: 15,
      );

      // A. Satışta olmayan ürün (prod_sut bu satışta yok!) -> 400 ERR_REFUND_ITEM_NOT_IN_SALE
      final wrongProd = await env.postSales({
        'operation_id': 'op_wrong_prod',
        'operation_type': 'SALE_REFUND',
        'client_seq': 2,
        'refund_id': 'ref_wrong_prod',
        'sale_id': saleId,
        'total_refund_amount': 3000,
        'reason': 'Yanlış ürün',
        'items': [
          {
            'product_id': 'prod_sut',
            'quantity': 1000,
            'unit_price': 3000,
            'refund_amount': 3000,
          }
        ],
      });
      expect(wrongProd.statusCode, equals(400));
      expect((jsonDecode(wrongProd.body) as Map)['code'], equals('ERR_REFUND_ITEM_NOT_IN_SALE'));

      // B. Snapshot unit_price manipülasyonu (15 yerine 20) -> 400 ERR_REFUND_UNIT_PRICE_MISMATCH
      final wrongPrice = await env.postSales({
        'operation_id': 'op_wrong_price',
        'operation_type': 'SALE_REFUND',
        'client_seq': 2,
        'refund_id': 'ref_wrong_price',
        'sale_id': saleId,
        'total_refund_amount': 10,
        'reason': 'Fiyat uyumsuzluğu',
        'items': [
          {
            'product_id': 'prod_peynir',
            'quantity': 500,
            'unit_price': 20,
            'refund_amount': 10,
          }
        ],
      });
      expect(wrongPrice.statusCode, equals(400));
      expect((jsonDecode(wrongPrice.body) as Map)['code'], equals('ERR_REFUND_UNIT_PRICE_MISMATCH'));

      // C. Half-Up beklenen tutardan sapma: ((15 * 500) + 500) ~/ 1000 = 8 iken 7 gönderildi -> 400 ERR_REFUND_AMOUNT_MISMATCH
      final wrongHalfUp = await env.postSales({
        'operation_id': 'op_wrong_halfup',
        'operation_type': 'SALE_REFUND',
        'client_seq': 2,
        'refund_id': 'ref_wrong_halfup',
        'sale_id': saleId,
        'total_refund_amount': 7,
        'reason': 'Half-Up sapması',
        'items': [
          {
            'product_id': 'prod_peynir',
            'quantity': 500,
            'unit_price': 15,
            'refund_amount': 7,
          }
        ],
      });
      expect(wrongHalfUp.statusCode, equals(400));
      expect((jsonDecode(wrongHalfUp.body) as Map)['code'], equals('ERR_REFUND_AMOUNT_MISMATCH'));

      // D. total_refund_amount kalem toplamından farklı (8 yerine 100) -> 400 ERR_REFUND_TOTAL_MISMATCH
      final wrongTotal = await env.postSales({
        'operation_id': 'op_wrong_total',
        'operation_type': 'SALE_REFUND',
        'client_seq': 2,
        'refund_id': 'ref_wrong_total',
        'sale_id': saleId,
        'total_refund_amount': 100,
        'reason': 'Toplam iade sapması',
        'items': [
          {
            'product_id': 'prod_peynir',
            'quantity': 500,
            'unit_price': 15,
            'refund_amount': 8,
          }
        ],
      });
      expect(wrongTotal.statusCode, equals(400));
      expect((jsonDecode(wrongTotal.body) as Map)['code'], equals('ERR_REFUND_TOTAL_MISMATCH'));

      // E. Geçerli Half-Up 500g iade -> 8 kuruş -> 201 Created!
      final validHalfUp = await env.postSales({
        'operation_id': 'op_valid_halfup',
        'operation_type': 'SALE_REFUND',
        'client_seq': 2,
        'refund_id': 'ref_valid_halfup',
        'sale_id': saleId,
        'total_refund_amount': 8,
        'reason': 'Half-Up geçerli iade',
        'items': [
          {
            'product_id': 'prod_peynir',
            'quantity': 500,
            'unit_price': 15,
            'refund_amount': 8,
            'product_condition': 'SELLABLE',
          }
        ],
      });
      expect(validHalfUp.statusCode, equals(201), reason: validHalfUp.body);

      // Tüm reddedilenlerden sonra seq=2 düzgün işlenebildi -> HWM=2
      final dev = await (env.db.select(env.db.devices)
            ..where((d) => d.deviceId.equals(env.deviceId)))
          .getSingle();
      expect(dev.lastCommittedClientSeq, equals(2));
    });

    test('TC-R07: SELLABLE vs DAMAGED stok ve hareket ayrımı, kanonik sale_item_id kaydı ve downlink görünürlüğü', () async {
      final env = await _IntegrityTestEnv.create();
      addTearDown(env.dispose);

      final saleId = await env.createSale(
        clientSeq: 1,
        customItems: [
          {'product_id': 'prod_sut', 'quantity': 2000, 'unit_price': 3000, 'total_price': 6000},
          {'product_id': 'prod_peynir', 'quantity': 1000, 'unit_price': 15, 'total_price': 15},
        ],
      );

      final refundRes = await env.postSales({
        'operation_id': 'op_cond_mixed',
        'operation_type': 'SALE_REFUND',
        'client_seq': 2,
        'refund_id': 'ref_cond_mixed',
        'sale_id': saleId,
        'target_client_seq': 1,
        'total_refund_amount': 6015,
        'reason': 'Karışık kondisyon tam iade',
        'items': [
          {
            'sale_item_id': 'citem_yerel_id_sut',
            'product_id': 'prod_sut',
            'quantity': 2000,
            'unit_price': 3000,
            'refund_amount': 6000,
            'product_condition': 'SELLABLE',
          },
          {
            'sale_item_id': 'citem_yerel_id_peynir',
            'product_id': 'prod_peynir',
            'quantity': 1000,
            'unit_price': 15,
            'refund_amount': 15,
            'product_condition': 'DAMAGED',
          },
        ],
      });
      expect(refundRes.statusCode, equals(201), reason: refundRes.body);

      final sut = await (env.db.select(env.db.products)..where((p) => p.id.equals('prod_sut'))).getSingle();
      final peynir = await (env.db.select(env.db.products)..where((p) => p.id.equals('prod_peynir'))).getSingle();
      expect(sut.stock, equals(50000)); // SELLABLE -> satılabilir stok döndü
      expect(peynir.stock, equals(9000)); // DAMAGED -> satılabilir stok ARTMAZ

      final fireMovements = await (env.db.select(env.db.stockMovements)
            ..where((m) => m.referenceId.equals('ref_cond_mixed') & m.movementType.equals('FIRE_KAYIP')))
          .get();
      expect(fireMovements.length, equals(1));
      expect(fireMovements.first.quantity, equals(1000));

      // refund_items.sale_item_id yerel citem_ değil Hub sale_items.id (item_...) olarak mühürlenmeli
      final saleItems = await (env.db.select(env.db.saleItems)..where((si) => si.saleId.equals(saleId))).get();
      final hubItemIds = saleItems.map((e) => e.id).toSet();
      final refItems = await (env.db.select(env.db.refundItems)..where((ri) => ri.refundId.equals('ref_cond_mixed'))).get();
      for (final ri in refItems) {
        expect(hubItemIds.contains(ri.saleItemId), isTrue);
      }

      // Downlink GET /api/v1/sales doğrulaması
      final dl = await http.get(Uri.parse('${env.baseUrl}/api/v1/sales?cursor=0'), headers: env.headers());
      expect(dl.statusCode, equals(200));
      final dlSale = ((jsonDecode(dl.body) as Map)['sales'] as List).first as Map<String, dynamic>;
      expect(dlSale['status'], equals('REFUNDED'));
      expect((dlSale['refunds'] as List).length, equals(1));
    });

    test('TC-R08: Aynı satışa eşzamanlı (Future.wait) iade taleplerinde fazla iade engellenir, receipt/HWM atomiktir', () async {
      final env = await _IntegrityTestEnv.create();
      addTearDown(env.dispose);

      // 1 adet süt satışı (seq=1)
      final saleId = await env.createSale(clientSeq: 1, quantity: 1000);

      final r1 = env.postSales({
        'operation_id': 'op_conc_ref_2',
        'operation_type': 'SALE_REFUND',
        'client_seq': 2,
        'refund_id': 'ref_conc_2',
        'sale_id': saleId,
        'target_client_seq': 1,
        'total_refund_amount': 3000,
        'reason': 'Eşzamanlı iade 1',
        'items': [
          {
            'product_id': 'prod_sut',
            'quantity': 1000,
            'unit_price': 3000,
            'refund_amount': 3000,
            'product_condition': 'SELLABLE',
          }
        ],
      });
      final r2 = env.postSales({
        'operation_id': 'op_conc_ref_3',
        'operation_type': 'SALE_REFUND',
        'client_seq': 3,
        'refund_id': 'ref_conc_3',
        'sale_id': saleId,
        'target_client_seq': 1,
        'total_refund_amount': 3000,
        'reason': 'Eşzamanlı iade 2',
        'items': [
          {
            'product_id': 'prod_sut',
            'quantity': 1000,
            'unit_price': 3000,
            'refund_amount': 3000,
            'product_condition': 'SELLABLE',
          }
        ],
      });

      final responses = await Future.wait([r1, r2]);
      final codes = responses.map((r) => r.statusCode).toList()..sort();
      expect(codes, equals([201, 409]));

      final refunds = await (env.db.select(env.db.refunds)..where((r) => r.saleId.equals(saleId))).get();
      expect(refunds.length, equals(1));

      final prod = await (env.db.select(env.db.products)..where((p) => p.id.equals('prod_sut'))).getSingle();
      expect(prod.stock, equals(50000));

      final stateRes = await http.get(
        Uri.parse('${env.baseUrl}/api/v1/sync/device-state'),
        headers: env.headers(),
      );
      expect(stateRes.statusCode, equals(200));
      final stateJson = jsonDecode(stateRes.body) as Map<String, dynamic>;
      expect(stateJson['high_water_mark_seq'], equals(2));
      expect(stateJson['committed_operation_count'], equals(2));

      final ops = await (env.db.select(env.db.processedOperations)
            ..where((o) => o.deviceId.equals(env.deviceId)))
          .get();
      for (final op in ops) {
        expect(CanonicalPayloadHasher.isValidSha256Hex(op.requestHash), isTrue);
      }
    });
  });
}
