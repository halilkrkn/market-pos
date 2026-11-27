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
    'Stage J — İzole Canlı Hub (TCP 8947 / UDP 8948) üzerinde §13.1-§13.5 çoklu cihaz ve kesinti/kurtarma E2E doğrulaması',
    timeout: const Timeout(Duration(minutes: 2)),
    skip: runLive
        ? false
        : 'Canlı izole Test Hub gerektirir (MMS_ISOLATED_LIVE_E2E=true).',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      LocalDatabaseService.resetForTesting();

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
      expect(caCertFile.existsSync(), isTrue);
      expect(adminSecretFile.existsSync(), isTrue);

      final caPem = caCertFile.readAsStringSync();
      final canonicalCa =
          MmsPinnedTlsClientFactory.validateAndComputeCaPin(caCertFile.readAsBytesSync());
      final caSha256Hex = canonicalCa.sha256Hex;
      final adminSecret = adminSecretFile.readAsStringSync().trim();

      final pinnedConfig = PinnedTlsConfig(
        caCertPem: caPem,
        expectedSha256Hex: caSha256Hex,
      );
      final adminHttp = MmsPinnedTlsClientFactory.createClient(pinnedConfig);
      addTearDown(adminHttp.close);

      // Hub /health + UDP 8948 keşif doğrulaması
      final healthResp = await adminHttp.get(Uri.parse('$hubUrl/health'));
      expect(healthResp.statusCode, equals(200));
      expect((jsonDecode(healthResp.body) as Map)['status'], equals('UP'));

      final discovery = UdpHubDiscoveryClient(
        discoveryPort: discoveryPort,
        defaultScheme: 'https',
        overrideTargets: [InternetAddress('127.0.0.1')],
      );
      final foundHubs = await discovery.discover(
        deviceId: 'WIN-J-DISCOVERY',
        timeout: const Duration(milliseconds: 2000),
      );
      expect(foundHubs, isNotEmpty);
      expect(foundHubs.first.httpPort, equals(parsedHub.port));

      // İzole istemci DB'leri (Windows + Android simülasyonları)
      final e2eClientsDir = Directory(p.join(testRoot, 'e2e_clients'))
        ..createSync(recursive: true);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final winDeviceId = 'WIN-J-OWN-$stamp';
      final winCashierDeviceId = 'WIN-J-CAS-$stamp';
      final andDeviceId = 'AND-J-CAS-$stamp';

      final winDbFile = File(p.join(e2eClientsDir.path, 'stage_j_win_$stamp.db'));
      final andDbFile = File(p.join(e2eClientsDir.path, 'stage_j_and_$stamp.db'));

      LocalDatabaseService? activeWinDb =
          await LocalDatabaseService.initialize(customPath: winDbFile.path);
      ClientDatabase? activeAndDb = ClientDatabase(andDbFile);
      var andRepo = ClientStorageRepository(activeAndDb);

      addTearDown(() async {
        if (activeWinDb != null) {
          await activeWinDb!.close();
          activeWinDb = null;
        }
        LocalDatabaseService.resetForTesting();
        if (activeAndDb != null) {
          await activeAndDb!.close();
          activeAndDb = null;
        }
      });

      await activeWinDb!.repository.initializeDevice(winDeviceId);
      await andRepo.initializeDevice(andDeviceId);

      final adminClient = HubPairingAdminClient(
        hubBaseUrl: hubUrl,
        httpClient: adminHttp,
      );
      final logger = RedactingLogger();

      Future<String> pairDevice({
        required String deviceId,
        required String name,
        required String platform,
      }) async {
        final store = InMemorySecureTokenStore();
        final session = await adminClient.createSession(adminSecret: adminSecret);
        final qr = PairingQrPayload.parse(session.qrPayload);
        final pairingClient = DevicePairingClient(tokenStore: store, logger: logger);
        final future = pairingClient.pairDevice(
          hubBaseUrl: hubUrl,
          sessionId: qr.sessionId,
          pairingSecret: qr.pairingSecret,
          deviceId: deviceId,
          deviceName: name,
          platformName: platform,
          expectedCaSha256: caSha256Hex,
          payloadCaSha256: qr.caSha256,
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await adminClient.approve(sessionId: session.sessionId, adminSecret: adminSecret);
        final res = await future;
        expect(res.confirmed, isTrue);
        final token = await store.readDeviceToken(deviceId);
        expect(token, isNotNull);
        return token!;
      }

      final winOwnerToken = await pairDevice(
        deviceId: winDeviceId,
        name: 'Windows Owner POS',
        platform: 'windows',
      );
      final winCashierToken = await pairDevice(
        deviceId: winCashierDeviceId,
        name: 'Windows Cashier 2',
        platform: 'windows',
      );
      final andToken = await pairDevice(
        deviceId: andDeviceId,
        name: 'Android Cashier POS',
        platform: 'android',
      );

      const tenantId = 'tenant-isolated-test';
      const storeId = 'store-isolated-test-01';

      var replayCounter = 0;
      Map<String, String> replayHeaders() => {
            'x-mms-timestamp': DateTime.now().toUtc().toIso8601String(),
            'x-mms-nonce': 'stagej_${stamp}_${++replayCounter}_nonce',
          };

      // Hub OWNER bootstrap veya role promotion
      final bootResp = await adminHttp.post(
        Uri.parse('$hubUrl/api/v1/admin/owner/bootstrap'),
        headers: {
          'content-type': 'application/json',
          'x-mms-admin-secret': adminSecret,
        },
        body: jsonEncode({'device_id': winDeviceId, 'register_if_missing': false}),
      );
      expect(bootResp.statusCode, anyOf(equals(200), equals(409)));
      if (bootResp.statusCode == 200) {
        final secondBoot = await adminHttp.post(
          Uri.parse('$hubUrl/api/v1/admin/owner/bootstrap'),
          headers: {
            'content-type': 'application/json',
            'x-mms-admin-secret': adminSecret,
          },
          body: jsonEncode({'device_id': andDeviceId, 'register_if_missing': false}),
        );
        expect(secondBoot.statusCode, equals(409));
      } else {
        final promoResp = await adminHttp.post(
          Uri.parse('$hubUrl/api/v1/devices/role'),
          headers: {
            'content-type': 'application/json',
            'x-mms-admin-secret': adminSecret,
            ...replayHeaders(),
          },
          body: jsonEncode({'device_id': winDeviceId, 'role': 'OWNER'}),
        );
        expect(promoResp.statusCode, equals(200));
      }

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
        repository: activeWinDb!.repository,
        transport: winTransport,
        deviceId: winDeviceId,
        deviceToken: winOwnerToken,
        hubUrl: hubUrl,
      );
      final andSync = ClientSyncService(
        repository: andRepo,
        transport: andTransport,
        deviceId: andDeviceId,
        deviceToken: andToken,
        hubUrl: hubUrl,
      );

      // =========================================================================
      // §13.1 SATIŞ, KURUŞ + HALF-UP, İADE (SELLABLE vs DAMAGED) VE SNAPSHOT
      // =========================================================================
      expect(
        () => PaymentMethod.parse('SPLIT'),
        throwsArgumentError,
      );
      expect(
        () => activeWinDb!.repository.createOfflineSale(
          deviceId: winDeviceId,
          paymentMethod: 'NAKIT',
          items: [CartItemInput.units('nonexistent', 1)],
        ),
        throwsArgumentError,
      );

      final bcPrimaryKg = '8691${stamp % 100000000}'.padRight(13, '3');
      final bcUnit = '8692${stamp % 100000000}'.padRight(13, '4');
      final bcSecondary = '8693${stamp % 100000000}'.padRight(13, '5');

      // Half-Up boundary testi: 301 kuruş/kg * 0.500 kg -> 150.5 -> Half-Up 151 kuruş!
      final kgProduct = await activeWinDb!.repository.createProduct(
        name: 'StageJ Peynir 1KG',
        price: 301,
        barcode: bcPrimaryKg,
        initialStock: 10000,
        stockUnit: 'kg',
        pricingUnit: 'kg',
        deviceId: winDeviceId,
      );
      final unitProduct = await activeWinDb!.repository.createProduct(
        name: 'StageJ Süt 1L',
        price: 4500, // 45.00 TL
        barcode: bcUnit,
        initialStock: 10000, // 10 adet
        deviceId: winDeviceId,
      );
      expect((await winSync.syncPendingOutbox()).isCleanSuccess, isTrue);
      // İlk ürün senkronu ile local_hub_synced_products tablosunu kaydet
      await winSync.syncProducts();

      final halfUpSale = await activeWinDb!.repository.createOfflineSale(
        deviceId: winDeviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.fractional(kgProduct.id, 500)],
      );
      expect(halfUpSale.totalAmount, equals(151));

      final cardSale = await activeWinDb!.repository.createOfflineSale(
        deviceId: winDeviceId,
        paymentMethod: 'CARD',
        items: [CartItemInput.units(unitProduct.id, 4)],
      );
      expect(cardSale.totalAmount, equals(18000)); // 4 * 4500
      expect((await winSync.syncPendingOutbox()).isCleanSuccess, isTrue);

      // Fiyat güncelle -> geçmiş satış snapshot fiyatı değişmez; eski fiyatlı sepet PriceChangedException fırlatır
      await activeWinDb!.repository.updateProduct(
        id: unitProduct.id,
        price: 5500,
        priceChangeReason: 'StageJ zam',
        deviceId: winDeviceId,
      );
      expect((await winSync.syncPendingOutbox()).isCleanSuccess, isTrue);

      final oldDetail = await activeWinDb!.repository.getSaleDetail(cardSale.saleId);
      expect(oldDetail, isNotNull);
      expect(oldDetail!.items.single.unitPrice, equals(4500));
      expect(
        () => activeWinDb!.repository.createOfflineSale(
          deviceId: winDeviceId,
          paymentMethod: 'CASH',
          items: [
            CartItemInput.units(
              unitProduct.id,
              1,
              expectedUnitPrice: 4500,
            ),
          ],
        ),
        throwsA(isA<PriceChangedException>()),
      );

      // Kısmi iade #1: SELLABLE 1 adet -> stok 6000 -> 7000
      final cardSaleItemId = oldDetail.items.single.id;
      await activeWinDb!.repository.refundSale(
        saleId: cardSale.saleId,
        items: [
          RefundItemInput(
            saleItemId: cardSaleItemId,
            quantity: 1000,
            productCondition: 'SELLABLE',
          ),
        ],
        reason: 'Müşteri iadesi sağlam ürün',
        deviceId: winDeviceId,
      );
      expect(
        (await activeWinDb!.repository.getProductById(unitProduct.id))!.stock,
        equals(7000),
      );

      // Kısmi iade #2: DAMAGED 1 adet -> stok artmaz, 7000 kalır
      await activeWinDb!.repository.refundSale(
        saleId: cardSale.saleId,
        items: [
          RefundItemInput(
            saleItemId: cardSaleItemId,
            quantity: 1000,
            productCondition: 'DAMAGED',
          ),
        ],
        reason: 'Ambalaj hasarlı',
        deviceId: winDeviceId,
      );
      expect(
        (await activeWinDb!.repository.getProductById(unitProduct.id))!.stock,
        equals(7000),
      );

      // Kalan 2 adet yerine 3 adet iade denemesi fail-closed reddedilir
      await expectLater(
        () => activeWinDb!.repository.refundSale(
          saleId: cardSale.saleId,
          items: [
            RefundItemInput(
              saleItemId: cardSaleItemId,
              quantity: 3000,
              productCondition: 'SELLABLE',
            ),
          ],
          reason: 'Aşırı iade testi',
          deviceId: winDeviceId,
        ),
        throwsArgumentError,
      );

      final updatedDetail = await activeWinDb!.repository.getSaleDetail(cardSale.saleId);
      expect(updatedDetail!.totalRefundedAmount, equals(9000));
      expect(updatedDetail.netAmount, equals(9000));
      expect(updatedDetail.displayStatus, equals(SaleDisplayStatus.partiallyRefunded));

      expect((await winSync.syncPendingOutbox()).isCleanSuccess, isTrue);
      await andSync.syncProducts();
      await andSync.syncSales();

      final andUnitAfterRefund = await andRepo.getProductById(unitProduct.id);
      expect(andUnitAfterRefund!.stock, equals(7000));
      expect(andUnitAfterRefund.price, equals(5500));

      // =========================================================================
      // §13.2 ÜRÜN, STOK GİRİŞİ, İKİNCİL BARKOD, EKSİ STOK VE PASİF ÜRÜN
      // =========================================================================
      await activeWinDb!.repository.addProductBarcode(
        productId: unitProduct.id,
        barcode: bcSecondary,
        deviceId: winDeviceId,
      );
      // Aynı ikincil barkodu başka ürüne ekleme reddedilir
      await expectLater(
        () => activeWinDb!.repository.addProductBarcode(
          productId: kgProduct.id,
          barcode: bcSecondary,
          deviceId: winDeviceId,
        ),
        throwsArgumentError,
      );

      // Stok girişi (+5000 = +5 adet, stok 7000 -> 12000)
      await activeWinDb!.repository.receiveStock(
        receiptId: 'rcpt_stagej_$stamp',
        productId: unitProduct.id,
        quantityMilli: 5000,
        unitPurchasePrice: 3200,
        note: 'StageJ mal kabul',
        deviceId: winDeviceId,
      );
      expect((await winSync.syncPendingOutbox()).isCleanSuccess, isTrue);
      await andSync.syncProducts();
      final andBySecBarcode = await andRepo.getProductByBarcode(bcSecondary);
      expect(andBySecBarcode, isNotNull);
      expect(andBySecBarcode!.id, equals(unitProduct.id));
      expect(andBySecBarcode.stock, equals(12000));

      // Eksi stok politikası allow + pasif ürün satışı engeli
      final lowStockProd = await activeWinDb!.repository.createProduct(
        name: 'StageJ Eksi Stok Testi',
        price: 1000,
        barcode: '8694${stamp % 100000000}'.padRight(13, '6'),
        initialStock: 1000, // 1 adet
        deviceId: winDeviceId,
      );
      final negSale = await activeWinDb!.repository.createOfflineSale(
        deviceId: winDeviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units(lowStockProd.id, 3)],
      );
      expect(negSale.totalAmount, equals(3000));
      expect(
        (await activeWinDb!.repository.getProductById(lowStockProd.id))!.stock,
        equals(-2000),
      );
      expect((await winSync.syncPendingOutbox()).isCleanSuccess, isTrue);
      await andSync.syncProducts();
      expect((await andRepo.getProductById(lowStockProd.id))!.stock, equals(-2000));

      await activeWinDb!.repository.deactivateProduct(lowStockProd.id, deviceId: winDeviceId);
      expect((await winSync.syncPendingOutbox()).isCleanSuccess, isTrue);
      await expectLater(
        () => activeWinDb!.repository.createOfflineSale(
          deviceId: winDeviceId,
          paymentMethod: 'CASH',
          items: [CartItemInput.units(lowStockProd.id, 1)],
        ),
        throwsStateError,
      );
      expect(await activeWinDb!.repository.getSaleDetail(negSale.saleId), isNotNull);

      // =========================================================================
      // §13.3 EŞZAMANLI ÇOKLU CİHAZ SENKRONU, IDEMPOTENCY REPLAY & 409 & NONCE
      // =========================================================================
      final concWin = await activeWinDb!.repository.createOfflineSale(
        deviceId: winDeviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units(unitProduct.id, 2)],
      );
      final concAnd = await andRepo.createOfflineSale(
        deviceId: andDeviceId,
        paymentMethod: 'CARD',
        items: [CartItemInput.units(unitProduct.id, 3)],
      );
      final pushResults = await Future.wait([
        winSync.syncPendingOutbox(),
        andSync.syncPendingOutbox(),
      ]);
      expect(pushResults[0].isCleanSuccess, isTrue);
      expect(pushResults[1].isCleanSuccess, isTrue);

      await winSync.syncProducts();
      await andSync.syncProducts();
      // Stok 12000 - 2000 - 3000 = 7000
      expect(
        (await activeWinDb!.repository.getProductById(unitProduct.id))!.stock,
        equals(7000),
      );
      expect((await andRepo.getProductById(unitProduct.id))!.stock, equals(7000));

      // Duplicate idempotent replay (200 + x-mms-idempotent-replay) & 409 tampered
      final lastSyncedOp = (await (activeWinDb!.database
                .select(activeWinDb!.database.outboxOperations)
              ..where((o) => o.operationId.equals(concWin.operationId)))
            .get())
          .single;
      final replaySaleResp = await winTransport.postSale(
        hubUrl: hubUrl,
        token: winOwnerToken,
        payload: lastSyncedOp.payload,
      );
      expect(replaySaleResp.statusCode, equals(200));
      expect(replaySaleResp.headers['x-mms-idempotent-replay'], equals('true'));

      final tampered = Map<String, dynamic>.from(jsonDecode(lastSyncedOp.payload) as Map);
      tampered['total_amount'] = (tampered['total_amount'] as int) + 100;
      final conflictSaleResp = await winTransport.postSale(
        hubUrl: hubUrl,
        token: winOwnerToken,
        payload: jsonEncode(tampered),
      );
      expect(conflictSaleResp.statusCode, equals(409));

      // Nonce tekrar kullanımı -> 403 ERR_REPLAY_DETECTED
      final fixedHeaders = replayHeaders();
      final r1 = await adminHttp.post(
        Uri.parse('$hubUrl/api/v1/devices/role'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $winOwnerToken',
          'x-mms-tenant-id': tenantId,
          'x-mms-store-id': storeId,
          ...fixedHeaders,
        },
        body: jsonEncode({'device_id': winCashierDeviceId, 'role': 'CASHIER'}),
      );
      expect(r1.statusCode, equals(200));
      final r2 = await adminHttp.post(
        Uri.parse('$hubUrl/api/v1/devices/role'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $winOwnerToken',
          'x-mms-tenant-id': tenantId,
          'x-mms-store-id': storeId,
          ...fixedHeaders,
        },
        body: jsonEncode({'device_id': winCashierDeviceId, 'role': 'CASHIER'}),
      );
      expect(r2.statusCode, equals(403));
      expect((jsonDecode(r2.body) as Map)['code'], equals('ERR_REPLAY_DETECTED'));
      expect(concAnd.totalAmount, equals(16500)); // 3 * 5500

      // =========================================================================
      // §13.4 CANLI HUB DURDURMA -> ÇEVRİMDIŞI DB REOPEN -> HUB BAŞLATMA -> SYNC
      // =========================================================================
      final repoRoot = Directory.current.path;
      final stopRes = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          p.join(repoRoot, 'scripts', 'dev_test', 'stop_isolated_test_hub.ps1'),
          '-TestRoot',
          testRoot,
        ],
      );
      expect(stopRes.exitCode, equals(0), reason: '${stopRes.stdout}\n${stopRes.stderr}');

      await expectLater(
        () => adminHttp.get(Uri.parse('$hubUrl/health')).timeout(const Duration(seconds: 2)),
        throwsA(anything),
      );

      // Hub kapalıyken her iki istemcide çevrimdışı satış
      final offWin = await activeWinDb!.repository.createOfflineSale(
        deviceId: winDeviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units(unitProduct.id, 1)],
      );
      final offAnd = await andRepo.createOfflineSale(
        deviceId: andDeviceId,
        paymentMethod: 'CARD',
        items: [CartItemInput.units(unitProduct.id, 2)],
      );
      expect(await activeWinDb!.getPendingOutboxCount(), equals(1));
      expect((await andRepo.getOutboxSummary(deviceId: andDeviceId)).pending, equals(1));

      // İki yerel DB'yi kapat ve diskten yeniden aç (uygulama yeniden başlatma)
      await activeWinDb!.close();
      activeWinDb = null;
      LocalDatabaseService.resetForTesting();
      await activeAndDb!.close();
      activeAndDb = null;

      activeWinDb = await LocalDatabaseService.initialize(customPath: winDbFile.path);
      activeAndDb = ClientDatabase(andDbFile);
      andRepo = ClientStorageRepository(activeAndDb!);

      expect(await activeWinDb!.getPendingOutboxCount(), equals(1));
      expect((await andRepo.getOutboxSummary(deviceId: andDeviceId)).pending, equals(1));

      // Canlı Hub'ı doğrudan --config ile yeniden başlat (detached mms_backend.exe)
      final hubDir = p.join(testRoot, 'hub');
      final hubBinDir = p.join(hubDir, 'bin');
      final hubExe = File(p.join(hubBinDir, 'mms_backend.exe'));
      final hubCfg = File(p.join(hubDir, 'config', 'hub_config.json'));
      final hubPidFile = File(p.join(hubDir, 'hub.pid'));
      expect(hubExe.existsSync(), isTrue);
      expect(hubCfg.existsSync(), isTrue);

      final restartedHubProc = await Process.start(
        hubExe.path,
        ['--config=${hubCfg.path}'],
        workingDirectory: hubBinDir,
        mode: ProcessStartMode.detached,
      );
      hubPidFile.writeAsStringSync('${restartedHubProc.pid}', flush: true);

      var hubBackUp = false;
      final restartDeadline = DateTime.now().add(const Duration(seconds: 20));
      while (DateTime.now().isBefore(restartDeadline)) {
        try {
          final resp = await adminHttp
              .get(Uri.parse('$hubUrl/health'))
              .timeout(const Duration(seconds: 2));
          if (resp.statusCode == 200) {
            hubBackUp = true;
            break;
          }
        } catch (_) {
          // Hub ayağa kalkana kadar kısa bekleme
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      expect(hubBackUp, isTrue, reason: 'Yeniden başlatılan İzole Hub /health 200 dönmedi');

      final winSyncAfter = ClientSyncService(
        repository: activeWinDb!.repository,
        transport: winTransport,
        deviceId: winDeviceId,
        deviceToken: winOwnerToken,
        hubUrl: hubUrl,
      );
      final andSyncAfter = ClientSyncService(
        repository: andRepo,
        transport: andTransport,
        deviceId: andDeviceId,
        deviceToken: andToken,
        hubUrl: hubUrl,
      );

      expect((await winSyncAfter.syncPendingOutbox()).isCleanSuccess, isTrue);
      expect((await andSyncAfter.syncPendingOutbox()).isCleanSuccess, isTrue);
      expect(await activeWinDb!.getPendingOutboxCount(), equals(0));
      expect((await andRepo.getOutboxSummary(deviceId: andDeviceId)).pending, equals(0));

      await winSyncAfter.syncProducts();
      await winSyncAfter.syncSales();
      await andSyncAfter.syncProducts();
      await andSyncAfter.syncSales();

      // Stok 7000 - 1000 - 2000 = 4000
      expect(
        (await activeWinDb!.repository.getProductById(unitProduct.id))!.stock,
        equals(4000),
      );
      expect((await andRepo.getProductById(unitProduct.id))!.stock, equals(4000));
      final winHist = await activeWinDb!.repository.getSalesHistory(limit: 50);
      final andHist = await andRepo.getSalesHistory(limit: 50);
      expect(
        winHist.any((s) => s.deviceId == andDeviceId && s.clientSeq == offAnd.clientSeq),
        isTrue,
      );
      expect(
        andHist.any((s) => s.deviceId == winDeviceId && s.clientSeq == offWin.clientSeq),
        isTrue,
      );

      // =========================================================================
      // §13.5 RBAC (OWNER vs CASHIER), YETKİSİZ ERİŞİM VE CİHAZ İPTALİ
      // =========================================================================
      final cashierRoleDeny = await adminHttp.post(
        Uri.parse('$hubUrl/api/v1/devices/role'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $winCashierToken',
          'x-mms-tenant-id': tenantId,
          'x-mms-store-id': storeId,
          ...replayHeaders(),
        },
        body: jsonEncode({'device_id': andDeviceId, 'role': 'OWNER'}),
      );
      expect(cashierRoleDeny.statusCode, equals(403));
      expect((jsonDecode(cashierRoleDeny.body) as Map)['code'], equals('ERR_OWNER_ROLE_REQUIRED'));

      final unauthResp = await adminHttp.get(Uri.parse('$hubUrl/api/v1/products'));
      expect(unauthResp.statusCode, equals(401));

      // Geçici CASHIER cihazını iptal et ve token'ın anında reddedildiğini doğrula
      final revokeResp = await adminHttp.post(
        Uri.parse('$hubUrl/api/v1/devices/revoke'),
        headers: {
          'content-type': 'application/json',
          'x-mms-admin-secret': adminSecret,
        },
        body: jsonEncode({
          'device_id': winCashierDeviceId,
          'reason': 'StageJ RBAC revoke verification',
        }),
      );
      expect(revokeResp.statusCode, equals(200));

      final revokedProductsResp = await adminHttp.get(
        Uri.parse('$hubUrl/api/v1/products'),
        headers: {
          'authorization': 'Bearer $winCashierToken',
          'x-mms-tenant-id': tenantId,
          'x-mms-store-id': storeId,
        },
      );
      expect(revokedProductsResp.statusCode, anyOf(equals(401), equals(403)));
    },
  );
}
