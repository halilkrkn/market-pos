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

void main() {
  late Directory tempDir;
  late File dbFile;
  late SpikeDatabase db;
  late WriteQueue writeQueue;
  late SpikeServer server;
  late PepperManager pepperManager;
  final testPort = 8966;
  final baseUrl = 'http://127.0.0.1:$testPort';
  final validToken = 'mms_pat_validation_test_token_123';
  final deviceId = 'DEV_VAL_TEST';

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    tempDir = await Directory.systemTemp.createTemp('mms_sales_val_test_');
    dbFile = File(p.join(tempDir.path, 'market_val.db'));
    final pepperFile = File(p.join(tempDir.path, 'pepper.dpapi'));
    pepperManager = PepperManager(pepperFile);
    pepperManager.initialize();

    db = SpikeDatabase(dbFile);
    writeQueue = WriteQueue();

    // Test cihazı ve ürünleri ekle
    final salt = TokenManager.generateSalt();
    final hash = TokenManager.hashToken(
      rawToken: validToken,
      salt: salt,
      pepper: pepperManager.pepper,
    );

    await db.into(db.devices).insert(
          DevicesCompanion(
            deviceId: Value(deviceId),
            name: const Value('Validation Test Device'),
            tokenHash: Value(hash),
            salt: Value(salt),
            isActive: const Value(true),
            isConfirmed: const Value(true),
          ),
        );

    // prod_et: pricing_unit = kg, stock_unit = g, factor = 1000/1, price = 20000 (200 TL/kg), stock = 10,000,000 milli-g (10 kg)
    await db.into(db.products).insert(
          ProductsCompanion(
            id: const Value('prod_et'),
            barcode: const Value('869001'),
            name: const Value('Kuşbaşı Et'),
            price: const Value(20000),
            stock: const Value(10000000),
            stockUnit: const Value('g'),
            pricingUnit: const Value('kg'),
            conversionFactorNumerator: const Value(1000),
            conversionFactorDenominator: const Value(1),
          ),
        );

    // prod_zamli: Fiyatı 300 TL'ye çıktı, ancak eski fiyatı 200 TL geçmişte kayıtlı
    await db.into(db.products).insert(
          ProductsCompanion(
            id: const Value('prod_zamli'),
            barcode: const Value('869002'),
            name: const Value('Zamlı Ürün'),
            price: const Value(30000), // Güncel: 300 TL
            stock: const Value(100000),
            stockUnit: const Value('adet'),
            pricingUnit: const Value('adet'),
            conversionFactorNumerator: const Value(1),
            conversionFactorDenominator: const Value(1),
          ),
        );

    await db.into(db.productPriceHistories).insert(
          ProductPriceHistoriesCompanion(
            id: const Value('ph_1'),
            productId: const Value('prod_zamli'),
            price: const Value(20000), // Eski geçerli fiyat: 200 TL
            validFrom: Value(DateTime.now().subtract(const Duration(days: 30))),
            validUntil: Value(DateTime.now().subtract(const Duration(days: 1))),
          ),
        );

    // prod_lossy: 1/3 dönüşümlü
    await db.into(db.products).insert(
          ProductsCompanion(
            id: const Value('prod_lossy'),
            barcode: const Value('869003'),
            name: const Value('Lossy Ürün'),
            price: const Value(1000),
            stock: const Value(10000),
            stockUnit: const Value('adet'),
            pricingUnit: const Value('paket'),
            conversionFactorNumerator: const Value(1),
            conversionFactorDenominator: const Value(3),
          ),
        );

    server = SpikeServer(
      db: db,
      writeQueue: writeQueue,
      backupDirectory: tempDir.path,
      adminSecret: 'adm_sec',
      pepperManager: pepperManager,
    );
    await server.start(port: testPort);
  });

  tearDownAll(() async {
    server.stop();
    await db.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  Map<String, String> authHeaders() => {
        'content-type': 'application/json',
        'authorization': 'Bearer $validToken',
      };

  group('Aşama S-5A-3: Merkezi Satış Endpoint Güvenliği ve Doğrulamaları', () {
    test('1. Negatif veya sıfır miktar (quantity <= 0) 400 ERR_INVALID_QUANTITY ile reddedilir', () async {
      final resNeg = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: authHeaders(),
        body: jsonEncode({
          'operation_id': 'op_neg_qty',
          'client_seq': 1,
          'total_amount': 10000,
          'payment_method': 'CASH',
          'items': [
            {'product_id': 'prod_et', 'quantity': -500, 'unit_price': 20000, 'total_price': 10000}
          ],
        }),
      );
      expect(resNeg.statusCode, equals(400));
      final dataNeg = jsonDecode(resNeg.body);
      expect(dataNeg['code'], equals('ERR_INVALID_QUANTITY'));

      final resZero = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: authHeaders(),
        body: jsonEncode({
          'operation_id': 'op_zero_qty',
          'client_seq': 2,
          'total_amount': 10000,
          'payment_method': 'CASH',
          'items': [
            {'product_id': 'prod_et', 'quantity': 0, 'unit_price': 20000, 'total_price': 10000}
          ],
        }),
      );
      expect(resZero.statusCode, equals(400));
      final dataZero = jsonDecode(resZero.body);
      expect(dataZero['code'], equals('ERR_INVALID_QUANTITY'));
    });

    test('2. Hileli satır tutarı 400 ERR_ITEM_TOTAL_MISMATCH ile reddedilir', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: authHeaders(),
        body: jsonEncode({
          'operation_id': 'op_bad_item_total',
          'client_seq': 3,
          'total_amount': 1,
          'payment_method': 'CASH',
          'items': [
            {'product_id': 'prod_et', 'quantity': 500, 'unit_price': 20000, 'total_price': 1}
          ],
        }),
      );
      expect(res.statusCode, equals(400));
      final data = jsonDecode(res.body);
      expect(data['code'], equals('ERR_ITEM_TOTAL_MISMATCH'));
    });

    test('3. Sepet toplam tutarı (total_amount) satır toplamlarıyla eşleşmezse 400 ERR_TOTAL_AMOUNT_MISMATCH döner', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: authHeaders(),
        body: jsonEncode({
          'operation_id': 'op_bad_sum',
          'client_seq': 4,
          'total_amount': 9999,
          'payment_method': 'CASH',
          'items': [
            {'product_id': 'prod_et', 'quantity': 500, 'unit_price': 20000, 'total_price': 10000}
          ],
        }),
      );
      expect(res.statusCode, equals(400));
      final data = jsonDecode(res.body);
      expect(data['code'], equals('ERR_TOTAL_AMOUNT_MISMATCH'));
    });

    test('4. Tanınmayan / uydurma birim fiyat 400 ERR_UNRECOGNIZED_PRICE ile reddedilir', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: authHeaders(),
        body: jsonEncode({
          'operation_id': 'op_fake_price',
          'client_seq': 5,
          'total_amount': 500,
          'payment_method': 'CASH',
          'items': [
            {'product_id': 'prod_et', 'quantity': 500, 'unit_price': 1000, 'total_price': 500}
          ],
        }),
      );
      expect(res.statusCode, equals(400));
      final data = jsonDecode(res.body);
      expect(data['code'], equals('ERR_UNRECOGNIZED_PRICE'));
    });

    test('5. Fiyat Snapshot Doğrulaması: Henüz yeni senkronizasyon almamışken geçerli fiyat geçmişindeki fiyat kabul edilir', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: authHeaders(),
        body: jsonEncode({
          'operation_id': 'op_valid_history_price',
          'client_seq': 6,
          'total_amount': 20000,
          'payment_method': 'CASH',
          'items': [
            {
              'product_id': 'prod_zamli',
              'price_version_id': 'ph_1',
              'quantity': 1000,
              'unit_price': 20000,
              'total_price': 20000,
            }
          ],
        }),
      );
      expect(res.statusCode, equals(201));
      final data = jsonDecode(res.body);
      expect(data['status'], equals('COMMITTED'));
    });

    test('6. Kayıpsız temsil edilemeyen birim dönüşümü 400 ERR_UNIT_CONVERSION_PRECISION_LOSS ile reddedilir', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: authHeaders(),
        body: jsonEncode({
          'operation_id': 'op_lossy_conv',
          'client_seq': 7,
          'total_amount': 1000,
          'payment_method': 'CASH',
          'items': [
            {'product_id': 'prod_lossy', 'quantity': 1000, 'unit_price': 1000, 'total_price': 1000}
          ],
        }),
      );
      expect(res.statusCode, equals(400));
      final data = jsonDecode(res.body);
      expect(data['code'], equals('ERR_UNIT_CONVERSION_PRECISION_LOSS'));
    });

    test('7. Başarılı satış sonrası stok stock_unit cinsinden doğru düşer', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: authHeaders(),
        body: jsonEncode({
          'operation_id': 'op_stock_conv_success',
          'client_seq': 8,
          'total_amount': 10000,
          'payment_method': 'CASH',
          'items': [
            {'product_id': 'prod_et', 'quantity': 500, 'unit_price': 20000, 'total_price': 10000}
          ],
        }),
      );
      expect(res.statusCode, equals(201));
      final data = jsonDecode(res.body);
      expect(data['updated_stocks']['prod_et'], equals(9500000));

      final sm = await (db.select(db.stockMovements)..where((s) => s.referenceId.equals(data['sale_id']))).getSingle();
      expect(sm.quantity, equals(-500000));
      expect(sm.unit, equals('g'));
    });

    test('8. İki Aşamalı Product Sync ACK ve Fiyat Snapshot Güvenliği', () async {
      // 1. Cihaz GET /api/v1/products çağırarak güncel fiyatları (300 TL) çeker
      final syncRes = await http.get(Uri.parse('$baseUrl/api/v1/products'), headers: authHeaders());
      expect(syncRes.statusCode, equals(200));
      final syncData = jsonDecode(syncRes.body) as Map<String, dynamic>;
      final syncSessionId = syncData['sync_session_id'] as String;
      expect(syncSessionId, isNotEmpty);

      // KONTROL 1: GET çağrısı yapılmış olsa dahi, henüz ACK gönderilmediği için sunucuda lastProductSyncAt GÜNCELLENMEMİŞTİR
      final devBeforeAck = await (db.select(db.devices)..where((d) => d.deviceId.equals(deviceId))).getSingle();
      expect(devBeforeAck.lastProductSyncAt, isNull);

      // KONTROL 2: ACK öncesinde eski fiyatla yapılan meşru offline satış (200 TL, ph_1) sunucu tarafından 201 ile KABUL EDİLİR!
      final preAckSaleRes = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: authHeaders(),
        body: jsonEncode({
          'operation_id': 'op_legit_pre_ack_sale',
          'client_seq': 9,
          'total_amount': 20000,
          'payment_method': 'CASH',
          'items': [
            {
              'product_id': 'prod_zamli',
              'price_version_id': 'ph_1',
              'quantity': 1000,
              'unit_price': 20000,
              'total_price': 20000,
            }
          ],
        }),
      );
      expect(preAckSaleRes.statusCode, equals(201));
      final preAckSaleJson = jsonDecode(preAckSaleRes.body);
      expect(preAckSaleJson['status'], equals('COMMITTED'));

      // KONTROL 3: İstemci yerel veritabanına başarıyla yazdıktan sonra POST /api/v1/products/sync-ack çağırır
      final ackRes = await http.post(
        Uri.parse('$baseUrl/api/v1/products/sync-ack'),
        headers: authHeaders(),
        body: jsonEncode({'sync_session_id': syncSessionId}),
      );
      expect(ackRes.statusCode, equals(200));
      final ackData = jsonDecode(ackRes.body);
      expect(ackData['status'], equals('ACKNOWLEDGED'));

      // Sunucudaki lastProductSyncAt güncellendi
      final devAfterAck = await (db.select(db.devices)..where((d) => d.deviceId.equals(deviceId))).getSingle();
      expect(devAfterAck.lastProductSyncAt, isNotNull);

      // KONTROL 4: Aynı ACK'nın tekrar gönderilmesi (Idempotent replay) 200 OK döner, yan etki yaratmaz
      final duplicateAckRes = await http.post(
        Uri.parse('$baseUrl/api/v1/products/sync-ack'),
        headers: authHeaders(),
        body: jsonEncode({'sync_session_id': syncSessionId}),
      );
      expect(duplicateAckRes.statusCode, equals(200));
      final duplicateAckData = jsonDecode(duplicateAckRes.body);
      expect(duplicateAckData['status'], equals('ALREADY_ACKNOWLEDGED'));

      // KONTROL 5: ACK sonrasında cihaz artık yeni fiyatı onaylamış olduğundan, eski 200 TL fiyatı (ph_1) ile gelen satış 400 ile REDDEDİLİR!
      final postAckSaleRes = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: authHeaders(),
        body: jsonEncode({
          'operation_id': 'op_expired_price_attempt',
          'client_seq': 13,
          'total_amount': 20000,
          'payment_method': 'CASH',
          'items': [
            {
              'product_id': 'prod_zamli',
              'price_version_id': 'ph_1',
              'quantity': 1000,
              'unit_price': 20000,
              'total_price': 20000,
            }
          ],
        }),
      );
      expect(postAckSaleRes.statusCode, equals(400));
      final err = jsonDecode(postAckSaleRes.body);
      expect(err['code'], equals('ERR_PRICE_VERSION_EXPIRED_FOR_DEVICE'));
    });

    test('9. Integer Overflow: Birim fiyat * miktar çarpımı 64-bit sınırını aşarsa çarpım öncesi 400 ERR_INTEGER_OVERFLOW ile reddedilir', () async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: authHeaders(),
        body: jsonEncode({
          'operation_id': 'op_overflow_price_qty',
          'client_seq': 10,
          'total_amount': 5000,
          'payment_method': 'CASH',
          'items': [
            {
              'product_id': 'prod_zamli',
              'quantity': 1000000000, // 1 milyar
              'unit_price': 10000000000, // 100 milyon TL (çarpım: 10^19 > 9.22 * 10^18)
              'total_price': 5000,
            }
          ],
        }),
      );
      expect(res.statusCode, equals(400));
      final err = jsonDecode(res.body);
      expect(err['code'], equals('ERR_INTEGER_OVERFLOW'));
    });

    test('10. Integer Overflow: Miktar * conversionFactorNumerator taşması çarpım öncesi 400 ERR_INTEGER_OVERFLOW ile reddedilir', () async {
      // prod_big_num: conversionFactorNumerator = 10^12
      await db.into(db.products).insert(
            const ProductsCompanion(
              id: Value('prod_big_num'),
              barcode: Value('869009'),
              name: Value('Big Num Product'),
              price: Value(1000),
              stock: Value(100000),
              conversionFactorNumerator: Value(1000000000000), // 10^12
              conversionFactorDenominator: Value(1),
            ),
          );

      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: authHeaders(),
        body: jsonEncode({
          'operation_id': 'op_overflow_conv',
          'client_seq': 11,
          'total_amount': 10000000,
          'payment_method': 'CASH',
          'items': [
            {
              'product_id': 'prod_big_num',
              'quantity': 10000000, // 10^7 * 10^12 = 10^19 > 9.22 * 10^18 (taşma!)
              'unit_price': 1000,
              'total_price': 10000000,
            }
          ],
        }),
      );
      expect(res.statusCode, equals(400));
      final err = jsonDecode(res.body);
      expect(err['code'], equals('ERR_INTEGER_OVERFLOW'));
    });

    test('11. Tek Miktar Sözleşmesi: Eski unscaled miktar (scale!=1000) geriye uyumluluk olmaksızın 400 ile reddedilir', () async {
      // qty: 1 (unscaled) gönderip total_price: 30000 (300 TL) bekleyen istek reddedilmeli
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/sales'),
        headers: authHeaders(),
        body: jsonEncode({
          'operation_id': 'op_unscaled_rejected',
          'client_seq': 12,
          'total_amount': 30000,
          'payment_method': 'CASH',
          'items': [
            {
              'product_id': 'prod_zamli',
              'quantity': 1, // scale=1000'de bu 0.001 adettir!
              'unit_price': 30000,
              'total_price': 30000, // 30000 * 1 / 1000 = 30 kuruş olmalıydı!
            }
          ],
        }),
      );
      expect(res.statusCode, equals(400));
      final err = jsonDecode(res.body);
      expect(err['code'], equals('ERR_ITEM_TOTAL_MISMATCH'));
    });
  });
}
