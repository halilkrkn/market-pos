import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _InMemoryDriveRelayTransport implements DriveLiveEnvelopeTransport {
  final Map<String, ({String fileName, Uint8List bytes, Map<String, String> appProperties})>
      stored = {};
  int uploadCallCount = 0;
  int listCallCount = 0;
  int _seq = 0;
  Object? errorOnUpload;

  @override
  Future<String> ensureSyncFolder() async => 'livesync-folder-1';

  @override
  Future<String> uploadEnvelope({
    required String folderId,
    required String fileName,
    required Uint8List bytes,
    required Map<String, String> appProperties,
  }) async {
    uploadCallCount++;
    if (errorOnUpload != null) throw errorOnUpload!;
    final id = 'env_file_${++_seq}';
    stored[id] = (
      fileName: fileName,
      bytes: Uint8List.fromList(bytes),
      appProperties: Map<String, String>.from(appProperties),
    );
    return id;
  }

  @override
  Future<List<DriveRemoteEnvelopeEntry>> listEnvelopes({
    required String folderId,
    required String tenantId,
    required String storeId,
  }) async {
    listCallCount++;
    final out = <DriveRemoteEnvelopeEntry>[];
    for (final e in stored.entries) {
      final parsed = DriveRemoteEnvelopeEntry.tryParse({
        'id': e.key,
        'name': e.value.fileName,
        'appProperties': e.value.appProperties,
      });
      if (parsed != null && parsed.tenantId == tenantId && parsed.storeId == storeId) {
        out.add(parsed);
      }
    }
    return out;
  }

  @override
  Future<Uint8List> downloadEnvelope({required String fileId}) async {
    final rec = stored[fileId];
    if (rec == null) throw StateError('Not found $fileId');
    return rec.bytes;
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  const tenantId = 'tenant-1';
  const storeId = 'store-1';
  const liveSecret = 'LiveSyncSecret_2026!Strong';

  Future<
      ({
        Directory dir,
        ClientDatabase db,
        ClientStorageRepository repo,
        DriveLiveSyncLedger ledger,
        DriveAuthorizedDeviceRegistry registry,
        _InMemoryDriveRelayTransport transport,
      })> createNode({
    required String deviceId,
    _InMemoryDriveRelayTransport? sharedTransport,
    DriveAuthorizedDeviceRegistry? sharedRegistry,
  }) async {
    final dir = Directory.systemTemp.createTempSync('mms_hybrid_sync_');
    final db = ClientDatabase.forTesting(NativeDatabase.memory());
    final repo = ClientStorageRepository(db);
    final ledger = DriveLiveSyncLedger(File(p.join(dir.path, 'drive_live_ledger.json')));
    final registry = sharedRegistry ??
        (DriveAuthorizedDeviceRegistry()
          ..authorizeDevice(
            deviceId: deviceId,
            tenantId: tenantId,
            storeId: storeId,
            deviceSecretOrPublicKey: 'dev-key-$deviceId',
          ));
    final transport = sharedTransport ?? _InMemoryDriveRelayTransport();

    await repo.upsertProducts([
      LocalProductsCompanion(
        id: const Value('prod_milk'),
        barcode: const Value('8690001'),
        name: const Value('Tam Yağlı Süt 1L'),
        price: const Value(3500),
        priceVersionId: const Value('pv_init'),
        stock: const Value(20000),
        updatedAt: Value(DateTime.utc(2026, 11, 21, 9, 0)),
      ),
    ]);

    addTearDown(() async {
      await db.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    return (
      dir: dir,
      db: db,
      repo: repo,
      ledger: ledger,
      registry: registry,
      transport: transport,
    );
  }

  group('ADR-021 — Hibrit Hub + Google Drive Canlı Senkronizasyon (Senaryolar 1–23)', () {
    test('S1–S3: Hub önceliği korunur; 1. hata fallback açmaz; 2. hata Drive fallback aktif eder', () async {
      final node = await createNode(deviceId: 'dev-a');
      final engine = MmsDriveLiveSyncEngine(
        repository: node.repo,
        transport: node.transport,
        ledger: node.ledger,
        deviceRegistry: node.registry,
        tenantId: tenantId,
        storeId: storeId,
        localDeviceId: 'dev-a',
        readLiveSyncSecret: () async => liveSecret,
        kdfIterations: 100,
      );

      // S1: Hub normal çalışıyorsa Drive sıfır trafik
      final healthy = await engine.recordHubHealthy();
      expect(healthy.driveFallbackActive, isFalse);
      expect(node.transport.uploadCallCount, 0);
      expect(node.transport.listCallCount, 0);

      // S2: 1. ağ hatası fallback başlatmaz
      final fail1 = await engine.recordHubFailure(isSecurityHold: false, isAuthFailure: false);
      expect(fail1.consecutiveHubFailures, 1);
      expect(fail1.driveFallbackActive, isFalse);

      // S3: 2. ardışık ağ hatası doğrulanmış Hub kesintisi sayılır
      final fail2 = await engine.recordHubFailure(isSecurityHold: false, isAuthFailure: false);
      expect(fail2.consecutiveHubFailures, 2);
      expect(fail2.driveFallbackActive, isTrue);
    });

    test('S4–S6: TLS pin, TLS sertifika ve 401/403 auth hatalarında Drive fallback KESİNLİKLE açılmaz', () async {
      final node = await createNode(deviceId: 'dev-a');
      final engine = MmsDriveLiveSyncEngine(
        repository: node.repo,
        transport: node.transport,
        ledger: node.ledger,
        deviceRegistry: node.registry,
        tenantId: tenantId,
        storeId: storeId,
        localDeviceId: 'dev-a',
        readLiveSyncSecret: () async => liveSecret,
        kdfIterations: 100,
      );

      for (var i = 0; i < 4; i++) {
        final sPin = await engine.recordHubFailure(isSecurityHold: true, isAuthFailure: false);
        expect(sPin.driveFallbackActive, isFalse);
        final sAuth = await engine.recordHubFailure(isSecurityHold: false, isAuthFailure: true);
        expect(sAuth.driveFallbackActive, isFalse);
      }
      expect(node.transport.uploadCallCount, 0);
    });

    test('S7–S12: Kripto ayrımı, yanlış secret, 1-bit tamper, farklı tenant/store ve REVOKED/kayıtsız cihaz reddi', () async {
      final sharedRegistry = DriveAuthorizedDeviceRegistry()
        ..authorizeDevice(
          deviceId: 'dev-a',
          tenantId: tenantId,
          storeId: storeId,
          deviceSecretOrPublicKey: 'dev-key-a',
        );

      final meta = DriveSyncEnvelopeMetadata(
        envelopeId: 'env-sec-1',
        schemaVersion: 4,
        tenantId: tenantId,
        storeId: storeId,
        originDeviceId: 'dev-a',
        clientSeq: 1,
        operationId: 'op-sec-1',
        operationType: 'STOCK_RECEIPT',
        payloadHash: '', // aşağıda doldurulur
        createdAtUtc: DateTime.fromMillisecondsSinceEpoch(1763712000000, isUtc: true),
        kdfIterations: 100,
      );
      final payloadJson = jsonEncode({
        'operation_id': 'op-sec-1',
        'operation_type': 'STOCK_RECEIPT',
        'client_seq': 1,
        'receipt_id': 'rcpt-1',
        'product_id': 'prod_milk',
        'quantity': 5000,
      });
      final payloadHash = sha256.convert(utf8.encode(payloadJson)).toString();
      final validMeta = DriveSyncEnvelopeMetadata(
        envelopeId: meta.envelopeId,
        schemaVersion: meta.schemaVersion,
        tenantId: meta.tenantId,
        storeId: meta.storeId,
        originDeviceId: meta.originDeviceId,
        clientSeq: meta.clientSeq,
        operationId: meta.operationId,
        operationType: meta.operationType,
        payloadHash: payloadHash,
        createdAtUtc: meta.createdAtUtc,
        kdfIterations: 100,
      );

      final bytes = EncryptedSyncEnvelopeCodec.encryptEnvelope(
        metadata: validMeta,
        payloadJson: payloadJson,
        liveSyncSecret: liveSecret,
        deviceKey: 'dev-key-a',
      );

      // S7: Yedek anahtarı türetimiyle LiveSync anahtarı farklıdır
      final salt = Uint8List.fromList(List.filled(16, 7));
      final backupKeys = BackupCryptoService.deriveKeys(
        password: liveSecret,
        salt: salt,
        iterations: 100,
      );
      final liveKeys = EncryptedSyncEnvelopeCodec.deriveEnvelopeKeys(
        liveSyncSecret: liveSecret,
        tenantId: tenantId,
        storeId: storeId,
        salt: salt,
        iterations: 100,
      );
      expect(backupKeys.encryptionKey, isNot(equals(liveKeys.encryptionKey)));
      expect(backupKeys.hmacKey, isNot(equals(liveKeys.hmacKey)));

      // S8: Yanlış secret
      expect(
        () => EncryptedSyncEnvelopeCodec.verifyAndDecryptEnvelope(
          envelopeBytes: bytes,
          liveSyncSecret: 'WrongSecret!',
          expectedTenantId: tenantId,
          expectedStoreId: storeId,
          deviceRegistry: sharedRegistry,
        ),
        throwsA(isA<DriveSyncSecurityException>()
            .having((e) => e.code, 'code', 'ERR_ENVELOPE_HMAC_FAILED')),
      );

      // S9: 1-bit tamper
      final tampered = Uint8List.fromList(bytes);
      tampered[tampered.length - 10] ^= 0x01;
      expect(
        () => EncryptedSyncEnvelopeCodec.verifyAndDecryptEnvelope(
          envelopeBytes: tampered,
          liveSyncSecret: liveSecret,
          expectedTenantId: tenantId,
          expectedStoreId: storeId,
          deviceRegistry: sharedRegistry,
        ),
        throwsA(isA<DriveSyncSecurityException>()
            .having((e) => e.code, 'code', 'ERR_ENVELOPE_HMAC_FAILED')),
      );

      // S10: Tenant / Store uyuşmazlığı
      expect(
        () => EncryptedSyncEnvelopeCodec.verifyAndDecryptEnvelope(
          envelopeBytes: bytes,
          liveSyncSecret: liveSecret,
          expectedTenantId: 'other-tenant',
          expectedStoreId: storeId,
          deviceRegistry: sharedRegistry,
        ),
        throwsA(isA<DriveSyncSecurityException>()
            .having((e) => e.code, 'code', 'ERR_TENANT_STORE_MISMATCH')),
      );

      // S12: Bozuk cihaz auth etiketi (imza)
      final forgedKeyBytes = EncryptedSyncEnvelopeCodec.encryptEnvelope(
        metadata: validMeta,
        payloadJson: payloadJson,
        liveSyncSecret: liveSecret,
        deviceKey: 'forged-device-key',
      );
      expect(
        () => EncryptedSyncEnvelopeCodec.verifyAndDecryptEnvelope(
          envelopeBytes: forgedKeyBytes,
          liveSyncSecret: liveSecret,
          expectedTenantId: tenantId,
          expectedStoreId: storeId,
          deviceRegistry: sharedRegistry,
        ),
        throwsA(isA<DriveSyncSecurityException>()
            .having((e) => e.code, 'code', 'ERR_DEVICE_SIGNATURE_INVALID')),
      );

      // S11: REVOKED cihaz
      sharedRegistry.revokeDevice('dev-a');
      expect(
        () => EncryptedSyncEnvelopeCodec.verifyAndDecryptEnvelope(
          envelopeBytes: bytes,
          liveSyncSecret: liveSecret,
          expectedTenantId: tenantId,
          expectedStoreId: storeId,
          deviceRegistry: sharedRegistry,
        ),
        throwsA(isA<DriveSyncSecurityException>()
            .having((e) => e.code, 'code', 'ERR_DEVICE_REVOKED')),
      );
    });

    test('S13–S17: Çoklu cihaz satış + iptal + iade + stok girişi, echo-loop engeli ve Outbox status korunumu', () async {
      final sharedTransport = _InMemoryDriveRelayTransport();
      final sharedRegistry = DriveAuthorizedDeviceRegistry()
        ..authorizeDevice(deviceId: 'dev-a', tenantId: tenantId, storeId: storeId)
        ..authorizeDevice(deviceId: 'dev-b', tenantId: tenantId, storeId: storeId);

      final nodeA = await createNode(
        deviceId: 'dev-a',
        sharedTransport: sharedTransport,
        sharedRegistry: sharedRegistry,
      );
      final nodeB = await createNode(
        deviceId: 'dev-b',
        sharedTransport: sharedTransport,
        sharedRegistry: sharedRegistry,
      );

      final engineA = MmsDriveLiveSyncEngine(
        repository: nodeA.repo,
        transport: sharedTransport,
        ledger: nodeA.ledger,
        deviceRegistry: sharedRegistry,
        tenantId: tenantId,
        storeId: storeId,
        localDeviceId: 'dev-a',
        readLiveSyncSecret: () async => liveSecret,
        kdfIterations: 100,
      );
      final engineB = MmsDriveLiveSyncEngine(
        repository: nodeB.repo,
        transport: sharedTransport,
        ledger: nodeB.ledger,
        deviceRegistry: sharedRegistry,
        tenantId: tenantId,
        storeId: storeId,
        localDeviceId: 'dev-b',
        readLiveSyncSecret: () async => liveSecret,
        kdfIterations: 100,
      );

      // Cihaz A offline iken stok girişi (+5), satış (-2), kısmi iade (+1 SELLABLE) yapar
      await nodeA.repo.receiveStock(
        receiptId: 'rcpt-milk-1',
        productId: 'prod_milk',
        quantityMilli: 5000,
        deviceId: 'dev-a',
      );
      final saleRes = await nodeA.repo.createOfflineSale(
        deviceId: 'dev-a',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_milk', 2)],
      );
      final detail = await nodeA.repo.getSaleDetail(saleRes.saleId);
      await nodeA.repo.refundSale(
        saleId: saleRes.saleId,
        deviceId: 'dev-a',
        reason: 'Müşteri iadesi',
        items: [
          RefundItemInput(
            saleItemId: detail!.items.single.id,
            quantity: 1000,
            productCondition: 'SELLABLE',
          ),
        ],
      );

      // A Drive'a yükler
      final cycleA1 = await engineA.runDriveFallbackCycle();
      expect(cycleA1.uploadedCount, 3);
      expect(cycleA1.appliedCount, 0);

      // S14: A'nın Outbox satırları Drive'a gidince ASLA SYNCED yapılmaz!
      final outboxA = await nodeA.repo.getUnsyncedOutboxOperations('dev-a');
      expect(outboxA, hasLength(3));
      expect(outboxA.every((o) => o.status == 'PENDING'), isTrue);

      // S13: İkinci turda aynı Outbox satırları tekrar yüklenmez (immutable & idempotent)
      final cycleA2 = await engineA.runDriveFallbackCycle();
      expect(cycleA2.uploadedCount, 0);

      // S15–S17: B Drive'dan indirir -> stok = 20 + 5 - 2 + 1 = 24.000 (24000 milli); B'nin outbox'ı boş kalır!
      final cycleB1 = await engineB.runDriveFallbackCycle();
      expect(cycleB1.appliedCount, 3);
      expect(cycleB1.rejectedSecurityCount, 0);
      final prodB = await nodeB.repo.getProductById('prod_milk');
      expect(prodB!.stock, 24000);

      final salesOnB = await nodeB.repo.getSalesHistory();
      expect(salesOnB, hasLength(1));
      expect(salesOnB.single.status, 'PARTIALLY_REFUNDED');

      // S15: Echo-loop yok -> B'nin Outbox'ı tamamen boş!
      expect(await nodeB.repo.getUnsyncedOutboxOperations('dev-b'), isEmpty);

      // S20: B aynı zarfları tekrar görse çift işlem yapmaz
      final cycleB2 = await engineB.runDriveFallbackCycle();
      expect(cycleB2.appliedCount, 0);
      expect((await nodeB.repo.getProductById('prod_milk'))!.stock, 24000);
    });

    test('S18–S19: Saat sapması bağımsızlığı ve out-of-order gap koruması (1 yokken 2 bekletilir)', () async {
      final sharedTransport = _InMemoryDriveRelayTransport();
      final sharedRegistry = DriveAuthorizedDeviceRegistry()
        ..authorizeDevice(deviceId: 'dev-a', tenantId: tenantId, storeId: storeId)
        ..authorizeDevice(deviceId: 'dev-b', tenantId: tenantId, storeId: storeId);

      // S18: A saati 2020'de, B saati 2032'de
      final nodeA = await createNode(
        deviceId: 'dev-a',
        sharedTransport: sharedTransport,
        sharedRegistry: sharedRegistry,
      );
      final nodeB = await createNode(
        deviceId: 'dev-b',
        sharedTransport: sharedTransport,
        sharedRegistry: sharedRegistry,
      );

      final engineA = MmsDriveLiveSyncEngine(
        repository: nodeA.repo,
        transport: sharedTransport,
        ledger: nodeA.ledger,
        deviceRegistry: sharedRegistry,
        tenantId: tenantId,
        storeId: storeId,
        localDeviceId: 'dev-a',
        readLiveSyncSecret: () async => liveSecret,
        kdfIterations: 100,
        clock: () => DateTime.utc(2020, 1, 1),
      );
      final engineB = MmsDriveLiveSyncEngine(
        repository: nodeB.repo,
        transport: sharedTransport,
        ledger: nodeB.ledger,
        deviceRegistry: sharedRegistry,
        tenantId: tenantId,
        storeId: storeId,
        localDeviceId: 'dev-b',
        readLiveSyncSecret: () async => liveSecret,
        kdfIterations: 100,
        clock: () => DateTime.utc(2032, 6, 15),
      );

      await nodeA.repo.createOfflineSale(
        deviceId: 'dev-a',
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_milk', 1)],
      );
      await nodeA.repo.createOfflineSale(
        deviceId: 'dev-a',
        paymentMethod: 'CARD',
        items: [CartItemInput.units('prod_milk', 3)],
      );
      await engineA.runDriveFallbackCycle();

      // S19: client_seq 1'i Drive'dan geçici olarak kaldır (sadece seq=2 görünür -> gap!)
      final seq1Entry = sharedTransport.stored.entries
          .firstWhere((e) => e.value.appProperties['mms_client_seq'] == '1');
      sharedTransport.stored.remove(seq1Entry.key);

      final gappedRes = await engineB.runDriveFallbackCycle();
      expect(gappedRes.appliedCount, 0);
      expect(gappedRes.deferredGapCount, 1);
      expect((await nodeB.repo.getProductById('prod_milk'))!.stock, 20000);

      // Şimdi seq=1 Drive'a düşer -> B hem 1'i hem 2'yi (toplam 4 adet düşüş -> 16000) sırayla uygular!
      sharedTransport.stored[seq1Entry.key] = seq1Entry.value;
      final filledRes = await engineB.runDriveFallbackCycle();
      expect(filledRes.appliedCount, 2);
      expect((await nodeB.repo.getProductById('prod_milk'))!.stock, 16000);
    });

    test('S21–S23: Non-LWW PRODUCT_UPSERT çakışması, Hub reconciliation ve BackupOperationLock koordinasyonu', () async {
      final sharedTransport = _InMemoryDriveRelayTransport();
      final sharedRegistry = DriveAuthorizedDeviceRegistry()
        ..authorizeDevice(deviceId: 'dev-a', tenantId: tenantId, storeId: storeId)
        ..authorizeDevice(deviceId: 'dev-b', tenantId: tenantId, storeId: storeId);

      final nodeA = await createNode(
        deviceId: 'dev-a',
        sharedTransport: sharedTransport,
        sharedRegistry: sharedRegistry,
      );
      final nodeB = await createNode(
        deviceId: 'dev-b',
        sharedTransport: sharedTransport,
        sharedRegistry: sharedRegistry,
      );

      final lockFileB = File(p.join(nodeB.dir.path, BackupOperationLock.defaultFileName));
      final engineA = MmsDriveLiveSyncEngine(
        repository: nodeA.repo,
        transport: sharedTransport,
        ledger: nodeA.ledger,
        deviceRegistry: sharedRegistry,
        tenantId: tenantId,
        storeId: storeId,
        localDeviceId: 'dev-a',
        readLiveSyncSecret: () async => liveSecret,
        kdfIterations: 100,
      );
      final engineB = MmsDriveLiveSyncEngine(
        repository: nodeB.repo,
        transport: sharedTransport,
        ledger: nodeB.ledger,
        deviceRegistry: sharedRegistry,
        tenantId: tenantId,
        storeId: storeId,
        localDeviceId: 'dev-b',
        readLiveSyncSecret: () async => liveSecret,
        operationLockFile: lockFileB,
        kdfIterations: 100,
      );

      // A ve B aynı üründe Hub kapalıyken farklı fiyat güncellemesi yapar
      await nodeA.repo.updateProduct(id: 'prod_milk', price: 4200, deviceId: 'dev-a');
      await nodeB.repo.updateProduct(id: 'prod_milk', price: 4500, deviceId: 'dev-b');

      await engineA.runDriveFallbackCycle();

      // S23: BackupOperationLock tutuluyorken Drive canlı senkronizasyonu atlanır
      final heldLock = await BackupOperationLock(lockFileB).acquire(BackupOperationKind.restore);
      final busyCycle = await engineB.runDriveFallbackCycle();
      expect(busyCycle.skippedLockBusy, isTrue);
      await heldLock.release();

      // S21: Kilit serbestken B zarfı alır ama 4500'ü 4200 ile SESSİZCE EZMEZ; çakışma kaydeder!
      final conflictCycle = await engineB.runDriveFallbackCycle();
      expect(conflictCycle.hasConflicts, isTrue);
      expect(conflictCycle.newConflicts.single.entityId, 'prod_milk');
      expect((await nodeB.repo.getProductById('prod_milk'))!.price, 4500);
      expect((await engineB.getLedgerState()).unresolvedConflicts, hasLength(1));

      // S22: Master Hub döndüğünde Outbox ACK tamamlanmadan reconcile kapanmaz
      var outboxAcked = false;
      final partialReconcile = await engineB.reconcileWithMasterHub(
        pushOutboxToHub: () async => 0,
        pullProductsFromHub: () async => 1,
        pullSalesFromHub: () async => 0,
        isOutboxEmptyOrAllSynced: () => outboxAcked,
      );
      expect(partialReconcile.reconciled, isFalse);
      expect((await engineB.getLedgerState()).pendingHubReconciliation, isTrue);

      outboxAcked = true;
      final fullReconcile = await engineB.reconcileWithMasterHub(
        pushOutboxToHub: () async => 1,
        pullProductsFromHub: () async => 1,
        pullSalesFromHub: () async => 1,
        isOutboxEmptyOrAllSynced: () => outboxAcked,
      );
      expect(fullReconcile.reconciled, isTrue);
      expect(fullReconcile.clearedConflictCount, 1);
      final finalState = await engineB.getLedgerState();
      expect(finalState.driveFallbackActive, isFalse);
      expect(finalState.pendingHubReconciliation, isFalse);
      expect(finalState.unresolvedConflicts, isEmpty);
    });
  });
}
