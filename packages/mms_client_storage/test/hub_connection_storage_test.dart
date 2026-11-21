import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:test/test.dart';

void main() {
  group('HubUrlValidator ve DiscoveredHubCandidate Kontrat Testleri', () {
    test('geçerli HTTP/HTTPS adreslerini doğrular ve sondaki eğik çizgiyi temizler', () {
      expect(
        HubUrlValidator.normalizeAndValidate(
          '  HTTP://192.168.1.50:8945///  ',
          allowLoopback: false,
        ),
        'http://192.168.1.50:8945',
      );
      expect(
        HubUrlValidator.normalizeAndValidate(
          'https://Hub.Local:8443/',
          allowLoopback: false,
        ),
        'https://hub.local:8443',
      );
      expect(
        HubUrlValidator.normalizeAndValidate(
          'http://127.0.0.1:8945/',
          allowLoopback: true,
        ),
        'http://127.0.0.1:8945',
      );
    });

    test('geçersiz veya eksik biçimli Hub URL değerlerini reddeder', () {
      const invalidUrls = <String>[
        '',
        '   ',
        '192.168.1.50:8945',
        'ftp://192.168.1.50:8945',
        'http://192.168.1.50:8945/health',
        'http://192.168.1.50:8945?token=abc',
        'http://user:pass@192.168.1.50:8945',
        'http://192.168.1.50:0',
      ];

      for (final raw in invalidUrls) {
        expect(
          () => HubUrlValidator.normalizeAndValidate(raw, allowLoopback: true),
          throwsA(isA<HubUrlValidationException>()),
          reason: 'Geçersiz URL kabul edilmemeli: $raw',
        );
        expect(HubUrlValidator.tryNormalize(raw, allowLoopback: true), isNull);
      }
    });

    test('allowLoopback=false (Android) iken loopback ve 0.0.0.0 adreslerini reddeder', () {
      const blockedUrls = <String>[
        'http://127.0.0.1:8945',
        'http://127.0.1.1:8945',
        'http://localhost:8945',
        'http://dev.localhost:8945',
        'http://localhost.localdomain:8945',
        'http://[::1]:8945',
        'http://[::ffff:127.0.0.1]:8945',
        'http://0.0.0.0:8945',
        'http://[::]:8945',
      ];

      for (final raw in blockedUrls) {
        expect(
          () => HubUrlValidator.normalizeAndValidate(raw, allowLoopback: false),
          throwsA(isA<HubUrlValidationException>()),
          reason: 'Android politikası loopback adresi engellemeli: $raw',
        );
        expect(
          HubUrlValidator.tryNormalize(raw, allowLoopback: false),
          isNull,
        );
      }
    });

    test('DiscoveredHubCandidate çoklu NIC yanıtında responderIp adresini ilk sıraya koyar', () {
      final candidate = DiscoveredHubCandidate.tryFromUdpPayload(
        const <String, dynamic>{
          'service': 'market_mms_hub',
          'protocol_version': '1.0',
          'hub_id': 'hub-store-01',
          'http_port': 8945,
          'server_ips': <String>['10.0.0.15', '192.168.1.50', '127.0.0.1'],
        },
        responderIp: '192.168.1.50',
      );

      expect(candidate, isNotNull);
      expect(candidate!.hubId, 'hub-store-01');
      expect(
        candidate.candidateBaseUrls(allowLoopback: false),
        const <String>[
          'http://192.168.1.50:8945',
          'http://10.0.0.15:8945',
        ],
      );
    });

    test('normalizeUserInput yalın IP, host:port ve URL girdilerini normalize eder ve Android politikasını korur', () {
      expect(
        HubUrlValidator.normalizeUserInput(
          ' 192.168.1.50 ',
          allowLoopback: false,
        ),
        'http://192.168.1.50:8945',
      );
      expect(
        HubUrlValidator.normalizeUserInput(
          '192.168.1.50:8950',
          allowLoopback: false,
        ),
        'http://192.168.1.50:8950',
      );
      expect(
        HubUrlValidator.normalizeUserInput(
          'HTTPS://hub.local:8443/',
          allowLoopback: false,
        ),
        'https://hub.local:8443',
      );
      expect(
        HubUrlValidator.normalizeUserInput(
          '127.0.0.1',
          allowLoopback: true,
        ),
        'http://127.0.0.1:8945',
      );

      for (final blocked in const <String>[
        '127.0.0.1',
        '127.0.0.1:8945',
        'localhost',
        '::1',
        '0.0.0.0:8945',
        '',
        '192.168.1.50:abc',
        '192.168.1.50/health',
      ]) {
        expect(
          () => HubUrlValidator.normalizeUserInput(
            blocked,
            allowLoopback: false,
          ),
          throwsA(isA<HubUrlValidationException>()),
          reason: 'Girdi reddedilmeli: $blocked',
        );
      }
    });
  });

  group('ClientStorageRepository - LocalClientSettings ve Hub URL Kalıcılığı', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mms_hub_cfg_test_');
      dbFile = File(p.join(tempDir.path, 'client_local.db'));
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('taze kurulumda schemaVersion=4 olur ve başlangıçta Hub ayarı null döner', () async {
      final db = ClientDatabase(dbFile);
      addTearDown(db.close);
      final repo = ClientStorageRepository(db);

      expect(db.schemaVersion, 4);
      expect(await repo.getStoredHubConnection(allowLoopback: false), isNull);

      final versionRows = await db.customSelect('PRAGMA user_version;').get();
      expect(versionRows.single.data['user_version'], 4);
    });

    test('kaydedilen Hub bağlantısı veritabanı kapatılıp açıldıktan sonra korunur', () async {
      final initialNow = DateTime.utc(2026, 11, 20, 10, 0, 0);
      final verifiedAt = DateTime.utc(2026, 11, 20, 10, 5, 0);

      final db1 = ClientDatabase(dbFile);
      final repo1 = ClientStorageRepository(db1);
      final saved = await repo1.saveStoredHubConnection(
        hubUrl: 'http://192.168.1.40:8945/',
        hubId: 'hub-main-01',
        source: HubUrlSource.discovered,
        allowLoopback: false,
        now: initialNow,
      );
      expect(saved.hubUrl, 'http://192.168.1.40:8945');
      expect(saved.lastVerifiedAt, isNull);

      await repo1.markHubConnectionVerified(
        hubUrl: 'http://192.168.1.40:8945',
        hubId: 'hub-main-01',
        allowLoopback: false,
        verifiedAt: verifiedAt,
      );
      await db1.close();

      // Yeni açılışta tüm alanlar eksiksiz geri okunmalı
      final db2 = ClientDatabase(dbFile);
      addTearDown(db2.close);
      final repo2 = ClientStorageRepository(db2);
      final loaded = await repo2.getStoredHubConnection(allowLoopback: false);

      expect(loaded, isNotNull);
      expect(loaded!.hubUrl, 'http://192.168.1.40:8945');
      expect(loaded.hubId, 'hub-main-01');
      expect(loaded.source, HubUrlSource.discovered);
      expect(
        loaded.lastVerifiedAt?.millisecondsSinceEpoch,
        verifiedAt.millisecondsSinceEpoch,
      );
      expect(loaded.updatedAt.millisecondsSinceEpoch, verifiedAt.millisecondsSinceEpoch);

      // Yeni URL yazıldığında eski lastVerifiedAt sıfırlanır ve tek satır korunur
      final updatedNow = DateTime.utc(2026, 11, 20, 11, 0, 0);
      await repo2.saveStoredHubConnection(
        hubUrl: 'http://192.168.1.55:8945',
        hubId: 'hub-main-02',
        source: HubUrlSource.manual,
        allowLoopback: false,
        now: updatedNow,
      );
      final rows = await db2.select(db2.localClientSettings).get();
      expect(rows, hasLength(1));
      expect(rows.single.hubUrl, 'http://192.168.1.55:8945');
      expect(rows.single.lastVerifiedAt, isNull);
    });

    test('Android (allowLoopback=false) yazma ve okuma katmanında loopback adresi reddeder', () async {
      final db = ClientDatabase(dbFile);
      addTearDown(db.close);
      final repo = ClientStorageRepository(db);

      await expectLater(
        () => repo.saveStoredHubConnection(
          hubUrl: 'http://127.0.0.1:8945',
          source: HubUrlSource.manual,
          allowLoopback: false,
        ),
        throwsA(isA<HubUrlValidationException>()),
      );
      expect(await db.select(db.localClientSettings).get(), isEmpty);

      // Bir önceki profilde/testte loopback yazılmış olsa bile allowLoopback=false ile null dönmeli
      await repo.saveStoredHubConnection(
        hubUrl: 'http://127.0.0.1:8945',
        source: HubUrlSource.localhostFallback,
        allowLoopback: true,
      );
      expect(await repo.getStoredHubConnection(allowLoopback: true), isNotNull);
      expect(await repo.getStoredHubConnection(allowLoopback: false), isNull);

      await repo.clearStoredHubConnection();
      expect(await repo.getStoredHubConnection(allowLoopback: true), isNull);
    });
  });

  group('Gerçek FFI SQLite v2 -> v3 Migration Bütünlük Testi', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mms_v2_v3_mig_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('v2 veritabanı v3e yükselirken satış, ürün, iade, outbox ve client_sync_states verilerini eksiksiz korur', () async {
      // 1. Mevcut şemadan v2 tablo ve indeks DDL tanımlarını (local_client_settings HARİÇ) al
      final schemaTemplateFile = File(p.join(tempDir.path, 'template_v3.db'));
      final templateDb = ClientDatabase(schemaTemplateFile);
      final ddlRows = await templateDb.customSelect(
        "SELECT type, name, sql FROM sqlite_master "
        "WHERE sql IS NOT NULL "
        "AND name NOT LIKE 'sqlite_%' "
        "AND name != 'local_client_settings' "
        "ORDER BY CASE type WHEN 'table' THEN 0 ELSE 1 END, name;",
      ).get();
      final v2DdlStatements =
          ddlRows.map((row) => row.data['sql'] as String).toList();
      await templateDb.close();

      // 2. Ham sqlite3 ile gerçek bir v2 veritabanı oluştur (local_client_settings YOK, user_version=2)
      final legacyV2File = File(p.join(tempDir.path, 'legacy_v2_client.db'));
      final rawDb = sqlite3.sqlite3.open(legacyV2File.path);
      try {
        for (final ddl in v2DdlStatements) {
          rawDb.execute('$ddl;');
        }
        // v4 (stok girişi) sütunları v2 şemasında yoktu: şablondan kaldırarak gerçek v2'yi üret.
        rawDb.execute('ALTER TABLE local_stock_movements DROP COLUMN purchase_price;');
        rawDb.execute('ALTER TABLE local_stock_movements DROP COLUMN note;');
        rawDb.execute('PRAGMA user_version = 2;');

        final nowSec = DateTime.utc(2026, 11, 19, 12, 0).millisecondsSinceEpoch ~/ 1000;
        rawDb.execute(
          "INSERT INTO local_categories (id, name, is_active, created_at, updated_at) "
          "VALUES ('cat-1', 'İçecekler', 1, $nowSec, $nowSec);",
        );
        rawDb.execute(
          "INSERT INTO local_products (id, barcode, name, category_id, price, price_version_id, stock, stock_unit, pricing_unit, conversion_factor_numerator, conversion_factor_denominator, vat_rate, is_active, updated_at) "
          "VALUES ('prod-1', '869000100001', 'Çay 1L', 'cat-1', 2500, 'pv-1', 49000, 'adet', 'adet', 1, 1, 10, 1, $nowSec);",
        );
        rawDb.execute(
          "INSERT INTO local_product_barcodes (id, product_id, barcode, is_primary, is_active, created_at) "
          "VALUES ('bc-1', 'prod-1', '869000100001', 1, 1, $nowSec);",
        );
        rawDb.execute(
          "INSERT INTO local_sales (id, device_id, client_seq, total_amount, payment_method, status, created_at) "
          "VALUES ('sale-v2-1', 'POS-AND-01', 1, 2500, 'CASH', 'COMPLETED', $nowSec);",
        );
        rawDb.execute(
          "INSERT INTO local_sale_items (id, sale_id, product_id, product_name_snapshot, unit_snapshot, price_version_id, unit_price, quantity, total_price) "
          "VALUES ('si-1', 'sale-v2-1', 'prod-1', 'Çay 1L', 'adet', 'pv-1', 2500, 1000, 2500);",
        );
        rawDb.execute(
          "INSERT INTO local_stock_movements (id, product_id, quantity, unit, movement_type, reference_id, created_at) "
          "VALUES ('sm-1', 'prod-1', -1000, 'adet', 'SALE', 'sale-v2-1', $nowSec);",
        );
        rawDb.execute(
          "INSERT INTO local_refunds (id, sale_id, device_id, client_seq, total_refund_amount, payment_method, reason, created_at) "
          "VALUES ('ref-v2-1', 'sale-v2-1', 'POS-AND-01', 2, 2500, 'CASH', 'İade test', $nowSec);",
        );
        rawDb.execute(
          "INSERT INTO local_refund_items (id, refund_id, sale_item_id, product_id, quantity, unit_price, refund_amount, product_condition, created_at) "
          "VALUES ('ri-1', 'ref-v2-1', 'si-1', 'prod-1', 1000, 2500, 2500, 'INTACT', $nowSec);",
        );
        rawDb.execute(
          "INSERT INTO local_price_history (id, product_id, old_price, new_price, price_version_id, source, reason, changed_at) "
          "VALUES ('ph-1', 'prod-1', 2200, 2500, 'pv-1', 'MANUAL', 'Test', $nowSec);",
        );
        rawDb.execute(
          "INSERT INTO outbox_operations (operation_id, device_id, client_seq, operation_type, payload, payload_hash, occurred_at, status, attempt_count, created_at) "
          "VALUES ('ob-1', 'POS-AND-01', 1, 'SALE', '{}', 'hash-1', $nowSec, 'PENDING', 0, $nowSec), "
          "('ob-2', 'POS-AND-01', 2, 'REFUND', '{}', 'hash-2', $nowSec, 'PENDING', 0, $nowSec);",
        );
        rawDb.execute(
          "INSERT INTO client_sync_states (device_id, current_client_seq, last_synced_seq, last_server_sale_seq, updated_at) "
          "VALUES ('POS-AND-01', 2, 0, 42, $nowSec);",
        );
      } finally {
        rawDb.close();
      }

      // 3. v2 dosyasını Drift ClientDatabase (güncel schemaVersion=4) ile aç; 2 -> 3 -> 4 zinciri çalışır
      final upgradedDb = ClientDatabase(legacyV2File);
      addTearDown(upgradedDb.close);
      final repo = ClientStorageRepository(upgradedDb);

      // İlk erişimde gerçek onUpgrade(2 -> 3) tetiklenmeli ve DROP olmadan yeni tablo oluşturulmalı
      expect(await repo.getStoredHubConnection(allowLoopback: false), isNull);

      final userVersionRows =
          await upgradedDb.customSelect('PRAGMA user_version;').get();
      expect(userVersionRows.single.data['user_version'], 4);
      final movementCols = (await upgradedDb
              .customSelect("PRAGMA table_info('local_stock_movements');")
              .get())
          .map((r) => r.data['name'])
          .toSet();
      expect(movementCols, containsAll(['purchase_price', 'note']));

      // Yeni tabloya yazma & okuma doğrula
      await repo.saveStoredHubConnection(
        hubUrl: 'http://192.168.1.77:8945',
        hubId: 'hub-mig-01',
        source: HubUrlSource.discovered,
        allowLoopback: false,
      );
      final savedCfg = await repo.getStoredHubConnection(allowLoopback: false);
      expect(savedCfg?.hubUrl, 'http://192.168.1.77:8945');

      // Tüm v2 verilerinin eksiksiz korunduğunu doğrula
      expect((await upgradedDb.select(upgradedDb.localCategories).get()).single.name, 'İçecekler');
      expect((await upgradedDb.select(upgradedDb.localProducts).get()).single.stock, 49000);
      expect((await upgradedDb.select(upgradedDb.localProductBarcodes).get()).single.barcode, '869000100001');
      expect((await upgradedDb.select(upgradedDb.localSales).get()).single.totalAmount, 2500);
      expect((await upgradedDb.select(upgradedDb.localSaleItems).get()).single.totalPrice, 2500);
      expect((await upgradedDb.select(upgradedDb.localStockMovements).get()).single.quantity, -1000);
      expect((await upgradedDb.select(upgradedDb.localRefunds).get()).single.totalRefundAmount, 2500);
      expect((await upgradedDb.select(upgradedDb.localRefundItems).get()).single.refundAmount, 2500);
      expect((await upgradedDb.select(upgradedDb.localPriceHistory).get()).single.newPrice, 2500);

      final pendingOutbox = await (upgradedDb.select(upgradedDb.outboxOperations)
            ..orderBy([(o) => OrderingTerm.asc(o.clientSeq)]))
          .get();
      expect(pendingOutbox.map((o) => o.clientSeq).toList(), <int>[1, 2]);
      expect(pendingOutbox.map((o) => o.status).toList(), <String>['PENDING', 'PENDING']);

      final syncState =
          await (upgradedDb.select(upgradedDb.clientSyncStates)).getSingle();
      expect(syncState.deviceId, 'POS-AND-01');
      expect(syncState.currentClientSeq, 2);
      expect(syncState.lastSyncedSeq, 0);
      expect(syncState.lastServerSaleSeq, 42);
    });
  });
}
