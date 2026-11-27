import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/core/logging/redacting_logger.dart';
import 'package:market_pos/core/security/secure_token_store.dart';
import 'package:market_pos/core/security/tls_pinned_client_factory.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/features/security/data/device_pairing_client.dart';
import 'package:market_pos/features/security/data/hub_pairing_admin_client.dart';
import 'package:market_pos/features/security/domain/pairing_qr_payload.dart';
import 'package:market_pos/features/sync/infrastructure/udp_hub_discovery_client.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  final runLive = Platform.environment['MMS_ISOLATED_LIVE_E2E'] == 'true';

  test(
    'İzole Test Hub (TCP 8947 / UDP 8948) üzerinde gerçek 2-istemcili uçtan uca senkronizasyon',
    skip: runLive
        ? false
        : 'Canlı izole Test Hub gerektirir (MMS_ISOLATED_LIVE_E2E=true).',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
      final testRoot = Platform.environment['MMS_ISOLATED_TEST_ROOT'] ??
          p.join(localAppData, 'MarketMMS_Isolated_Test');
      final hubUrl =
          Platform.environment['MMS_ISOLATED_HUB_URL'] ?? 'https://127.0.0.1:8947';
      final discoveryPort = int.tryParse(
            Platform.environment['MMS_ISOLATED_DISCOVERY_PORT'] ?? '8948',
          ) ??
          8948;

      final parsedHub = Uri.parse(hubUrl);
      expect(parsedHub.scheme, equals('https'));
      expect(parsedHub.port, isNot(8085));
      expect(parsedHub.port, isNot(8945));
      expect(discoveryPort, isNot(8946));

      final caCertFile = File(p.join(testRoot, 'hub', 'certs', 'ca.crt'));
      final adminSecretFile =
          File(p.join(testRoot, 'hub', 'security', 'admin_secret.txt'));
      expect(caCertFile.existsSync(), isTrue, reason: 'ca.crt bulunamadı');
      expect(adminSecretFile.existsSync(), isTrue, reason: 'admin_secret.txt yok');

      final caPem = caCertFile.readAsStringSync();
      final caBytes = caCertFile.readAsBytesSync();
      final canonicalCa = MmsPinnedTlsClientFactory.validateAndComputeCaPin(
        caBytes,
      );
      final caSha256Hex = canonicalCa.sha256Hex;
      final adminSecret = adminSecretFile.readAsStringSync().trim();

      final pinnedConfig = PinnedTlsConfig(
        caCertPem: caPem,
        expectedSha256Hex: caSha256Hex,
      );
      final adminHttp = MmsPinnedTlsClientFactory.createClient(pinnedConfig);
      addTearDown(adminHttp.close);

      // 1. Pinned TLS /health kontrolü
      final healthResp = await adminHttp.get(Uri.parse('$hubUrl/health'));
      expect(healthResp.statusCode, equals(200));
      final healthJson = jsonDecode(healthResp.body) as Map<String, dynamic>;
      expect(healthJson['status'], equals('UP'));
      expect(healthJson['restore_epoch'], isNotNull);

      // 2. UDP 8948 Discovery kontrolü
      final discoveryClient = UdpHubDiscoveryClient(
        discoveryPort: discoveryPort,
        defaultScheme: 'https',
        overrideTargets: [InternetAddress('127.0.0.1')],
      );
      final discovered = await discoveryClient.discover(
        deviceId: 'WIN-TEST-01',
        timeout: const Duration(milliseconds: 2000),
      );
      expect(discovered, isNotEmpty);
      expect(discovered.first.hubId, equals('MMS-HUB-ISOLATED-TEST'));
      expect(discovered.first.httpPort, equals(parsedHub.port));

      // 3. İki ayrı izole FFI SQLite istemci DB'si (WIN-TEST-* & AND-SIM-*)
      final e2eClientsDir = Directory(p.join(testRoot, 'e2e_clients'))
        ..createSync(recursive: true);
      final runStamp = DateTime.now().millisecondsSinceEpoch;
      final winDeviceId = 'WIN-TEST-$runStamp';
      final andDeviceId = 'AND-SIM-$runStamp';
      final winDbFile = File(p.join(e2eClientsDir.path, 'win_test_$runStamp.db'));
      final andDbFile = File(p.join(e2eClientsDir.path, 'and_sim_$runStamp.db'));

      final winDb = await LocalDatabaseService.initialize(customPath: winDbFile.path);
      addTearDown(() async {
        await winDb.close();
      });
      await winDb.repository.initializeDevice(winDeviceId);

      // Ayrı ClientDatabase örneği (ikinci istemci izolasyonu)
      final andRawDb = ClientDatabase(andDbFile);
      final andRepo = ClientStorageRepository(andRawDb);
      addTearDown(() async {
        await andRawDb.close();
      });
      await andRepo.initializeDevice(andDeviceId);

      final adminClient = HubPairingAdminClient(
        hubBaseUrl: hubUrl,
        httpClient: adminHttp,
      );

      final winTokenStore = InMemorySecureTokenStore();
      final andTokenStore = InMemorySecureTokenStore();
      final logger = RedactingLogger();

      Future<String> pairTestDevice({
        required String deviceId,
        required String deviceName,
        required String platformName,
        required SecureTokenStore tokenStore,
      }) async {
        final session = await adminClient.createSession(adminSecret: adminSecret);
        final qr = PairingQrPayload.parse(session.qrPayload);
        expect(qr.caSha256, isNotNull);
        expect(qr.caSha256, equals(caSha256Hex));

        final pairingClient = DevicePairingClient(
          tokenStore: tokenStore,
          logger: logger,
        );

        final pairingFuture = pairingClient.pairDevice(
          hubBaseUrl: hubUrl,
          sessionId: qr.sessionId,
          pairingSecret: qr.pairingSecret,
          deviceId: deviceId,
          deviceName: deviceName,
          platformName: platformName,
          expectedCaSha256: caSha256Hex,
          payloadCaSha256: qr.caSha256,
        );

        await Future<void>.delayed(const Duration(milliseconds: 250));
        await adminClient.approve(
          sessionId: session.sessionId,
          adminSecret: adminSecret,
        );

        final res = await pairingFuture;
        expect(res.confirmed, isTrue);
        final token = await tokenStore.readDeviceToken(deviceId);
        expect(token, isNotNull);
        expect(token!.isNotEmpty, isTrue);
        return token;
      }

      final winToken = await pairTestDevice(
        deviceId: winDeviceId,
        deviceName: 'Windows Isolated Cashier',
        platformName: 'windows',
        tokenStore: winTokenStore,
      );
      final andToken = await pairTestDevice(
        deviceId: andDeviceId,
        deviceName: 'Android Simulated Cashier',
        platformName: 'android',
        tokenStore: andTokenStore,
      );

      const tenantId = 'tenant-isolated-test';
      const storeId = 'store-isolated-test-01';

      final winTransport = HttpSyncTransport.forStore(
        client: MmsPinnedTlsClientFactory.createClient(pinnedConfig),
        tenantId: tenantId,
        storeId: storeId,
      );
      final andTransport = HttpSyncTransport.forStore(
        client: MmsPinnedTlsClientFactory.createClient(pinnedConfig),
        tenantId: tenantId,
        storeId: storeId,
      );
      addTearDown(() {
        winTransport.close();
        andTransport.close();
      });

      final winSync = ClientSyncService(
        repository: winDb.repository,
        transport: winTransport,
        deviceId: winDeviceId,
        deviceToken: winToken,
        hubUrl: hubUrl,
      );
      final andSync = ClientSyncService(
        repository: andRepo,
        transport: andTransport,
        deviceId: andDeviceId,
        deviceToken: andToken,
        hubUrl: hubUrl,
      );

      // 4. Windows'tan kategori + ürün oluştur ve Hub'a senkronize et -> Android çeksin
      final cat = await winDb.repository.createCategory(name: 'Test İçecek');
      final winProdBarcode = '8699${runStamp % 1000000000}'.padRight(13, '1');
      final winProduct = await winDb.repository.createProduct(
        name: 'İzole Test Meyve Suyu 1L',
        price: 2550, // 25.50 TL
        barcode: winProdBarcode,
        categoryId: cat.id,
        initialStock: 10000, // 10 adet
        deviceId: winDeviceId,
      );

      final winPush1 = await winSync.syncPendingOutbox();
      expect(winPush1.isCleanSuccess, isTrue);
      expect(winPush1.syncedCount, equals(1));

      await andSync.syncProducts();
      final andLookedUp = await andRepo.getProductByBarcode(winProdBarcode);
      expect(andLookedUp, isNotNull);
      expect(andLookedUp!.id, equals(winProduct.id));
      expect(andLookedUp.price, equals(2550));
      expect(andLookedUp.stock, equals(10000));

      // 5. Android simülasyonundan ürün oluştur ve Hub'a gönder -> Windows çeksin
      final andProdBarcode = '8698${runStamp % 1000000000}'.padRight(13, '2');
      final andProduct = await andRepo.createProduct(
        name: 'İzole Android Sim Ürün',
        price: 1275, // 12.75 TL
        barcode: andProdBarcode,
        initialStock: 20000, // 20 adet
        deviceId: andDeviceId,
      );

      final andPush1 = await andSync.syncPendingOutbox();
      expect(andPush1.isCleanSuccess, isTrue);
      expect(andPush1.syncedCount, equals(1));

      await winSync.syncProducts();
      final winLookedUpFromAnd =
          await winDb.repository.getProductByBarcode(andProdBarcode);
      expect(winLookedUpFromAnd, isNotNull);
      expect(winLookedUpFromAnd!.id, equals(andProduct.id));
      expect(winLookedUpFromAnd.price, equals(1275));

      // 6. Barkodla satış + stok değişimi (WIN-TEST -> 2 adet = 51.00 TL, stok 10 -> 8)
      final sale1 = await winDb.repository.createOfflineSale(
        deviceId: winDeviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units(winProduct.id, 2)],
      );
      expect(sale1.totalAmount, equals(5100));
      expect(await winDb.getPendingOutboxCount(), equals(1));

      final winPush2 = await winSync.syncPendingOutbox();
      expect(winPush2.isCleanSuccess, isTrue);
      expect(winPush2.syncedCount, equals(1));

      await andSync.syncProducts();
      await andSync.syncSales();
      final andAfterSale1 = await andRepo.getProductByBarcode(winProdBarcode);
      expect(andAfterSale1!.stock, equals(8000));
      final andSalesAfter1 = await andRepo.getSalesHistory(limit: 50);
      expect(
        andSalesAfter1.any(
          (s) =>
              s.deviceId == winDeviceId &&
              s.clientSeq == sale1.clientSeq &&
              s.totalAmount == 5100,
        ),
        isTrue,
      );

      // 7. Offline satış (WIN-TEST senkronize etmeden 3 adet daha satar -> stok 8 -> 5)
      final offlineSale = await winDb.repository.createOfflineSale(
        deviceId: winDeviceId,
        paymentMethod: 'CARD',
        items: [CartItemInput.units(winProduct.id, 3)],
      );
      expect(offlineSale.totalAmount, equals(7650));
      expect(await winDb.getPendingOutboxCount(), equals(1));
      final winLocalDuringOffline =
          await winDb.repository.getProductByBarcode(winProdBarcode);
      expect(winLocalDuringOffline!.stock, equals(5000));

      // 8. Bağlantı geri gelir -> Outbox gönderimi + Hub uzlaştırma + Android tutarlılık
      final winPush3 = await winSync.syncPendingOutbox();
      expect(winPush3.isCleanSuccess, isTrue);
      expect(winPush3.syncedCount, equals(1));
      expect(await winDb.getPendingOutboxCount(), equals(0));

      await andSync.syncProducts();
      await andSync.syncSales();
      final andAfterOfflineSync =
          await andRepo.getProductByBarcode(winProdBarcode);
      expect(andAfterOfflineSync!.stock, equals(5000));
      final andSalesAfter2 = await andRepo.getSalesHistory(limit: 50);
      expect(
        andSalesAfter2.any(
          (s) =>
              s.deviceId == winDeviceId &&
              s.clientSeq == offlineSale.clientSeq &&
              s.totalAmount == 7650,
        ),
        isTrue,
      );

      // 9. Idempotency & Duplicate Operation kontrolü
      final syncedOp = (await (winDb.database.select(winDb.database.outboxOperations)
                ..where((o) => o.operationId.equals(offlineSale.operationId)))
              .get())
          .single;
      final replayResp = await winTransport.postSale(
        hubUrl: hubUrl,
        token: winToken,
        payload: syncedOp.payload,
      );
      expect(replayResp.statusCode, equals(200));
      expect(replayResp.headers['x-mms-idempotent-replay'], equals('true'));

      // Aynı idempotency_key + farklı tutar -> 409 CONFLICT
      final decodedPayload =
          Map<String, dynamic>.from(jsonDecode(syncedOp.payload) as Map);
      decodedPayload['total_amount'] = 9999;
      final conflictResp = await winTransport.postSale(
        hubUrl: hubUrl,
        token: winToken,
        payload: jsonEncode(decodedPayload),
      );
      expect(conflictResp.statusCode, equals(409));

      // Hub stoğu hala 5000 (mükerrer düşüş olmadı)
      await andSync.syncProducts();
      final andFinalProd = await andRepo.getProductByBarcode(winProdBarcode);
      expect(andFinalProd!.stock, equals(5000));
    },
  );
}
