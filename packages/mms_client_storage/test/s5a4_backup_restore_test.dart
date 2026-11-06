import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

void main() {
  late Directory tempDir;
  late File clientDbFile;
  late ClientDatabase clientDb;
  late ClientStorageRepository repo;
  late Directory backupStorageDir;
  late Directory safetyBackupDir;
  late LocalStorageProvider storageProvider;

  const validPassword = 'MMS_Super_Secure_Backup_Password_2026!';
  const deviceId = 'DEV_WIN_CASHIER_01';
  const tenantId = 'tenant_market_001';
  const storeId = 'store_branch_main';
  const testKdfIterations = 10000;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mms_backup_test_');
    clientDbFile = File(p.join(tempDir.path, 'client_local.db'));
    backupStorageDir = Directory(p.join(tempDir.path, 'backups'));
    safetyBackupDir = Directory(p.join(tempDir.path, 'safety_snapshots'));

    backupStorageDir.createSync(recursive: true);
    safetyBackupDir.createSync(recursive: true);

    storageProvider = LocalStorageProvider(backupStorageDir);

    clientDb = ClientDatabase(clientDbFile);
    repo = ClientStorageRepository(clientDb);

    // Başlangıç test ürünlerini ekle
    await repo.upsertProducts([
      LocalProductsCompanion(
        id: const Value('prod_1'),
        barcode: const Value('8690001'),
        name: const Value('Süt 1L'),
        price: const Value(3000), // 30.00 TL
        stock: const Value(50000), // 50 adet
        stockUnit: const Value('adet'),
        pricingUnit: const Value('adet'),
        updatedAt: Value(DateTime.now()),
      ),
      LocalProductsCompanion(
        id: const Value('prod_2'),
        barcode: const Value('8690002'),
        name: const Value('Peynir 1kg'),
        price: const Value(15000), // 150.00 TL
        stock: const Value(20000), // 20 kg
        stockUnit: const Value('kg'),
        pricingUnit: const Value('kg'),
        updatedAt: Value(DateTime.now()),
      ),
    ]);
  });

  tearDown(() async {
    await clientDb.close();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('Aşama S-5A-4: Yedekleme ve Geri Yükleme Altyapısı (Backup & Restore Infrastructure)', () {
    test('1. Normal Backup: Şifreli yedekleme ve doğrulanabilir manifest üretimi', () async {
      // 1 satış oluştur
      await repo.createOfflineSale(
        deviceId: deviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_1', 1)],
      );

      final result = await DatabaseBackupEngine.createBackup(
        liveDbFile: clientDbFile,
        executeVacuumInto: (snapPath) async {
          final escaped = snapPath.replaceAll("'", "''");
          await clientDb.customStatement("VACUUM INTO '$escaped';");
        },
        deviceId: deviceId,
        tenantId: tenantId,
        storeId: storeId,
        databaseType: DatabaseType.clientLocal,
        schemaVersion: 1,
        appVersion: '1.0.0',
        backupPassword: validPassword,
        storageProvider: storageProvider,
        kdfIterations: testKdfIterations,
      );

      expect(result.backupId, isNotEmpty);
      expect(result.manifest.backupId, equals(result.backupId));
      expect(result.manifest.deviceId, equals(deviceId));
      expect(result.manifest.tenantId, equals(tenantId));
      expect(result.manifest.databaseType, equals(DatabaseType.clientLocal));
      expect(result.manifest.schemaVersion, equals(1));
      expect(result.manifest.checksum.length, equals(64));
      expect(result.encryptedSizeBytes, greaterThan(0));
      expect(result.unencryptedSizeBytes, greaterThan(0));

      // Depolama alanında .mmsbak dosyasının oluştuğunu ve .tmp dosyasının kalmadığını doğrula
      final backups = await storageProvider.listBackups();
      expect(backups.length, equals(1));
      expect(backups.first.backupId, equals(result.backupId));
      expect(backups.first.file.path.endsWith('.mmsbak'), isTrue);

      final tmpFiles = backupStorageDir.listSync().where((f) => f.path.endsWith('.tmp')).toList();
      expect(tmpFiles, isEmpty);
    });

    test('2. WAL Aktifken Backup: WAL modundaki SQLite veritabanı tutarlı yedeklenir (VACUUM INTO)', () async {
      // SQLite WAL modunda olduğunu doğrula
      final raw = sqlite3.open(clientDbFile.path);
      final journalMode = raw.select('PRAGMA journal_mode;').first.columnAt(0).toString().toLowerCase();
      raw.dispose();
      expect(journalMode, equals('wal'));

      // Satış ekle (WAL dosyasına yazılır)
      await repo.createOfflineSale(
        deviceId: deviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_1', 2)],
      );

      // WAL dosyasının oluştuğunu veya var olduğunu doğrula
      final walFile = File('${clientDbFile.path}-wal');
      expect(walFile.existsSync(), isTrue);

      // Yedek al
      final backup = await DatabaseBackupEngine.createBackup(
        liveDbFile: clientDbFile,
        executeVacuumInto: (snapPath) async {
          final escaped = snapPath.replaceAll("'", "''");
          await clientDb.customStatement("VACUUM INTO '$escaped';");
        },
        deviceId: deviceId,
        tenantId: tenantId,
        storeId: storeId,
        databaseType: DatabaseType.clientLocal,
        schemaVersion: 1,
        appVersion: '1.0.0',
        backupPassword: validPassword,
        storageProvider: storageProvider,
        kdfIterations: testKdfIterations,
      );

      // Şifreyi çöz ve yedeğin içinde WAL'a yazılan satışın eksiksiz var olduğunu doğrula
      final packageFile = await storageProvider.getBackupFile(backup.backupId);
      final decrypted = BackupCryptoService.verifyAndDecryptPackage(
        packageBytes: await packageFile.readAsBytes(),
        password: validPassword,
      );

      final tempRestoreFile = File(p.join(tempDir.path, 'verify_wal_snap.db'));
      await tempRestoreFile.writeAsBytes(decrypted.databaseBytes);

      final snapDb = sqlite3.open(tempRestoreFile.path);
      final salesCount = snapDb.select('SELECT COUNT(*) FROM local_sales;').first.columnAt(0) as int;
      final checkRes = snapDb.select('PRAGMA integrity_check;').first.columnAt(0).toString().toLowerCase();
      snapDb.dispose();

      expect(salesCount, equals(1));
      expect(checkRes, equals('ok'));
    });

    test('3. Backup Sırasında Eşzamanlı Yazma: Satış transactionları yedekleme esnasında kilitlenmez', () async {
      // Paralel yazma simülasyonu
      final writeCompleter = Completer<void>();
      var writeCompleted = false;

      // Arka planda peş peşe 3 satış yazma işlemi başlat
      final backgroundWrites = Future(() async {
        for (var i = 1; i <= 3; i++) {
          await repo.createOfflineSale(
            deviceId: deviceId,
            paymentMethod: 'CASH',
            items: [CartItemInput.units('prod_1', 1)],
          );
          await Future.delayed(const Duration(milliseconds: 10));
        }
        writeCompleted = true;
        writeCompleter.complete();
      });

      // Eşzamanlı olarak yedek al
      final backupResult = await DatabaseBackupEngine.createBackup(
        liveDbFile: clientDbFile,
        executeVacuumInto: (snapPath) async {
          final escaped = snapPath.replaceAll("'", "''");
          await clientDb.customStatement("VACUUM INTO '$escaped';");
        },
        deviceId: deviceId,
        tenantId: tenantId,
        storeId: storeId,
        databaseType: DatabaseType.clientLocal,
        schemaVersion: 1,
        appVersion: '1.0.0',
        backupPassword: validPassword,
        storageProvider: storageProvider,
        kdfIterations: testKdfIterations,
      );

      await backgroundWrites;
      expect(writeCompleted, isTrue);
      expect(backupResult.backupId, isNotEmpty);

      // Canlı veritabanında toplam 3 satışın tamamının yazılmış olduğunu doğrula
      final sales = await clientDb.select(clientDb.localSales).get();
      expect(sales.length, equals(3));
    });

    test('4. Yarım Kalan / Hatalı Backup: .tmp dosyaları temizlenir ve geçersiz yedek kaydedilmez', () async {
      expect(
        () async => await DatabaseBackupEngine.createBackup(
          liveDbFile: clientDbFile,
          executeVacuumInto: (snapPath) async {
            // Hata simülasyonu: Snapshot alınırken beklenmeyen bir exception fırlat
            throw StateError('Disk I/O hatası simülasyonu');
          },
          deviceId: deviceId,
          tenantId: tenantId,
          storeId: storeId,
          databaseType: DatabaseType.clientLocal,
          schemaVersion: 1,
          appVersion: '1.0.0',
          backupPassword: validPassword,
          storageProvider: storageProvider,
        ),
        throwsA(isA<StateError>()),
      );

      // Hiçbir geçerli yedek kaydedilmemiş olmalı
      final backups = await storageProvider.listBackups();
      expect(backups, isEmpty);

      // Artık .tmp dosyası kalmamış olmalı
      final tmpFiles = backupStorageDir.listSync().where((f) => f.path.endsWith('.tmp')).toList();
      expect(tmpFiles, isEmpty);
    });

    test('5. Şifreli Yedekten Güvenli Restore: Canlı veritabanı yedeğe döner ve bütünlük korunur', () async {
      // 1. Durum A: 1 satış oluştur ve yedek al
      await repo.createOfflineSale(
        deviceId: deviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_1', 1)], // clientSeq = 1
      );

      final backupA = await DatabaseBackupEngine.createBackup(
        liveDbFile: clientDbFile,
        executeVacuumInto: (snapPath) async {
          final escaped = snapPath.replaceAll("'", "''");
          await clientDb.customStatement("VACUUM INTO '$escaped';");
        },
        deviceId: deviceId,
        tenantId: tenantId,
        storeId: storeId,
        databaseType: DatabaseType.clientLocal,
        schemaVersion: 1,
        appVersion: '1.0.0',
        backupPassword: validPassword,
        storageProvider: storageProvider,
        kdfIterations: testKdfIterations,
      );

      // 2. Durum B: 2 yeni satış daha yap (Canlı DB'de 3 satış var)
      await repo.createOfflineSale(
        deviceId: deviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_1', 1)], // clientSeq = 2
      );
      await repo.createOfflineSale(
        deviceId: deviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_2', 1)], // clientSeq = 3
      );
      var currentSales = await clientDb.select(clientDb.localSales).get();
      expect(currentSales.length, equals(3));

      // 3. Durum A yedeğini geri yükle (Restore)
      final restoreRes = await DatabaseBackupEngine.restoreBackup(
        backupId: backupA.backupId,
        liveDbFile: clientDbFile,
        backupPassword: validPassword,
        storageProvider: storageProvider,
        expectedDeviceId: deviceId,
        expectedTenantId: tenantId,
        expectedDatabaseType: DatabaseType.clientLocal,
        currentSchemaVersion: 1,
        pauseLiveDb: () async => await clientDb.close(),
        resumeLiveDb: () async {
          clientDb = ClientDatabase(clientDbFile);
          repo = ClientStorageRepository(clientDb);
        },
        safetyBackupDir: safetyBackupDir,
      );

      expect(restoreRes.backupId, equals(backupA.backupId));

      // 4. Canlı veritabanının Durum A'ya (1 satış) döndüğünü doğrula
      final restoredSales = await clientDb.select(clientDb.localSales).get();
      expect(restoredSales.length, equals(1));
      expect(restoredSales.first.clientSeq, equals(1));

      // 5. Pre-restore koruyucu yedeğin oluşturulduğunu teyit et
      final safetyFiles = safetyBackupDir.listSync().where((f) => f.path.endsWith('.db')).toList();
      expect(safetyFiles, isNotEmpty);
    });

    test('6. Hatalı Şifre: Yanlış parola ile restore reddedilir ve canlı DB korunur', () async {
      final backup = await DatabaseBackupEngine.createBackup(
        liveDbFile: clientDbFile,
        executeVacuumInto: (snapPath) async {
          final escaped = snapPath.replaceAll("'", "''");
          await clientDb.customStatement("VACUUM INTO '$escaped';");
        },
        deviceId: deviceId,
        tenantId: tenantId,
        storeId: storeId,
        databaseType: DatabaseType.clientLocal,
        schemaVersion: 1,
        appVersion: '1.0.0',
        backupPassword: validPassword,
        storageProvider: storageProvider,
        kdfIterations: testKdfIterations,
      );

      expect(
        () async => await DatabaseBackupEngine.restoreBackup(
          backupId: backup.backupId,
          liveDbFile: clientDbFile,
          backupPassword: 'WRONG_INCORRECT_PASSWORD',
          storageProvider: storageProvider,
          expectedDeviceId: deviceId,
          expectedTenantId: tenantId,
          expectedDatabaseType: DatabaseType.clientLocal,
          currentSchemaVersion: 1,
          pauseLiveDb: () async {},
          resumeLiveDb: () async {},
          safetyBackupDir: safetyBackupDir,
        ),
        throwsA(isA<BackupException>().having((e) => e.code, 'code', anyOf(['ERR_DECRYPTION_FAILED', 'ERR_CORRUPT_MANIFEST']))),
      );

      // Canlı DB sağlam kalır
      final prods = await clientDb.select(clientDb.localProducts).get();
      expect(prods.length, equals(2));
    });

    test('7. Bozuk veya Değiştirilmiş Manifest: Paket manipülasyonu HMAC ile anında tespit edilir ve reddedilir', () async {
      final backup = await DatabaseBackupEngine.createBackup(
        liveDbFile: clientDbFile,
        executeVacuumInto: (snapPath) async {
          final escaped = snapPath.replaceAll("'", "''");
          await clientDb.customStatement("VACUUM INTO '$escaped';");
        },
        deviceId: deviceId,
        tenantId: tenantId,
        storeId: storeId,
        databaseType: DatabaseType.clientLocal,
        schemaVersion: 1,
        appVersion: '1.0.0',
        backupPassword: validPassword,
        storageProvider: storageProvider,
        kdfIterations: testKdfIterations,
      );

      // Dosya içeriğinde manifest bölgesinden bir baytı değiştir
      final packageFile = await storageProvider.getBackupFile(backup.backupId);
      final bytes = Uint8List.fromList(await packageFile.readAsBytes());
      bytes[15] = bytes[15] ^ 0xFF; // Bayt manipülasyonu
      await packageFile.writeAsBytes(bytes);

      expect(
        () async => await DatabaseBackupEngine.restoreBackup(
          backupId: backup.backupId,
          liveDbFile: clientDbFile,
          backupPassword: validPassword,
          storageProvider: storageProvider,
          expectedDeviceId: deviceId,
          expectedTenantId: tenantId,
          expectedDatabaseType: DatabaseType.clientLocal,
          currentSchemaVersion: 1,
          pauseLiveDb: () async {},
          resumeLiveDb: () async {},
          safetyBackupDir: safetyBackupDir,
        ),
        throwsA(isA<BackupException>().having((e) => e.code, 'code', anyOf(['ERR_DECRYPTION_FAILED', 'ERR_CORRUPT_MANIFEST']))),
      );
    });

    test('8. Yanlış Şema Sürümü: Yedeğin şema sürümü geleceğe aitse (schemaVersion=99) restore reddedilir', () async {
      // Şema sürümü 99 olan bir yedek paketi hazırla
      final rawSnapshotBytes = await clientDbFile.readAsBytes();
      final checksum = sha256.convert(rawSnapshotBytes).toString().toLowerCase();

      final futureManifest = BackupManifest(
        backupId: 'future_backup_99',
        deviceId: deviceId,
        tenantId: tenantId,
        storeId: storeId,
        databaseType: DatabaseType.clientLocal,
        schemaVersion: 99, // Gelecek şema
        appVersion: '9.9.0',
        timestamp: DateTime.now().toUtc(),
        checksum: checksum,
        unencryptedSizeBytes: rawSnapshotBytes.length,
        encryptedSizeBytes: 0,
        kdfIterations: testKdfIterations,
      );

      final packageBytes = BackupCryptoService.encryptPackage(
        databaseBytes: rawSnapshotBytes,
        password: validPassword,
        manifest: futureManifest,
      );

      await storageProvider.saveBackup(packageBytes: packageBytes, manifest: futureManifest);

      expect(
        () async => await DatabaseBackupEngine.restoreBackup(
          backupId: 'future_backup_99',
          liveDbFile: clientDbFile,
          backupPassword: validPassword,
          storageProvider: storageProvider,
          expectedDeviceId: deviceId,
          expectedTenantId: tenantId,
          expectedDatabaseType: DatabaseType.clientLocal,
          currentSchemaVersion: 1, // Uygulama yalnızca v1 destekliyor
          pauseLiveDb: () async {},
          resumeLiveDb: () async {},
          safetyBackupDir: safetyBackupDir,
        ),
        throwsA(isA<BackupException>().having((e) => e.code, 'code', 'ERR_INCOMPATIBLE_SCHEMA_VERSION')),
      );
    });

    test('9. Veritabanı Türü ve Cihaz Ayrımı: Merkezi DB yedeği Client DB üzerine yüklenemez', () async {
      // CENTRAL_MASTER türünde bir yedek oluştur
      final rawBytes = await clientDbFile.readAsBytes();
      final checksum = sha256.convert(rawBytes).toString().toLowerCase();

      final serverManifest = BackupManifest(
        backupId: 'server_backup_001',
        deviceId: 'SERVER_HUB',
        tenantId: tenantId,
        storeId: storeId,
        databaseType: DatabaseType.centralMaster, // Merkezi sunucu yedeği!
        schemaVersion: 1,
        appVersion: '1.0.0',
        timestamp: DateTime.now().toUtc(),
        checksum: checksum,
        unencryptedSizeBytes: rawBytes.length,
        encryptedSizeBytes: 0,
        kdfIterations: testKdfIterations,
      );

      final packageBytes = BackupCryptoService.encryptPackage(
        databaseBytes: rawBytes,
        password: validPassword,
        manifest: serverManifest,
      );

      await storageProvider.saveBackup(packageBytes: packageBytes, manifest: serverManifest);

      // Kasa istemcisine (CLIENT_LOCAL) yüklemeye çalış -> Reddedilmeli!
      expect(
        () async => await DatabaseBackupEngine.restoreBackup(
          backupId: 'server_backup_001',
          liveDbFile: clientDbFile,
          backupPassword: validPassword,
          storageProvider: storageProvider,
          expectedDeviceId: deviceId,
          expectedTenantId: tenantId,
          expectedDatabaseType: DatabaseType.clientLocal,
          currentSchemaVersion: 1,
          pauseLiveDb: () async {},
          resumeLiveDb: () async {},
          safetyBackupDir: safetyBackupDir,
        ),
        throwsA(isA<BackupException>().having((e) => e.code, 'code', 'ERR_DATABASE_TYPE_MISMATCH')),
      );

      // Başka bir cihazın (DEV_OTHER) yedeğini bu cihaza yüklemeye çalış -> Reddedilmeli!
      final otherDevManifest = serverManifest.copyWith(
        backupId: 'other_dev_002',
        databaseType: DatabaseType.clientLocal,
        deviceId: 'DEV_OTHER_CASHIER',
      );
      final otherDevBytes = BackupCryptoService.encryptPackage(
        databaseBytes: rawBytes,
        password: validPassword,
        manifest: otherDevManifest,
      );
      await storageProvider.saveBackup(packageBytes: otherDevBytes, manifest: otherDevManifest);

      expect(
        () async => await DatabaseBackupEngine.restoreBackup(
          backupId: 'other_dev_002',
          liveDbFile: clientDbFile,
          backupPassword: validPassword,
          storageProvider: storageProvider,
          expectedDeviceId: deviceId, // Bu cihaz: DEV_WIN_CASHIER_01
          expectedTenantId: tenantId,
          expectedDatabaseType: DatabaseType.clientLocal,
          currentSchemaVersion: 1,
          pauseLiveDb: () async {},
          resumeLiveDb: () async {},
          safetyBackupDir: safetyBackupDir,
        ),
        throwsA(isA<BackupException>().having((e) => e.code, 'code', 'ERR_DEVICE_ID_MISMATCH')),
      );
    });

    test('10. Restore Sırasında Hata ve Koruyucu Yedekten Otomatik Kurtarma (Safety Rollback)', () async {
      // 1. Canlı DB'de önemli veriler var (1 satış)
      await repo.createOfflineSale(
        deviceId: deviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_1', 1)],
      );

      // Yedek oluştur
      final backup = await DatabaseBackupEngine.createBackup(
        liveDbFile: clientDbFile,
        executeVacuumInto: (snapPath) async {
          final escaped = snapPath.replaceAll("'", "''");
          await clientDb.customStatement("VACUUM INTO '$escaped';");
        },
        deviceId: deviceId,
        tenantId: tenantId,
        storeId: storeId,
        databaseType: DatabaseType.clientLocal,
        schemaVersion: 1,
        appVersion: '1.0.0',
        backupPassword: validPassword,
        storageProvider: storageProvider,
        kdfIterations: testKdfIterations,
      );

      // 2. Canlı veritabanına yeni bir satış daha yap (Örn: kurtarılması gereken canlı durum)
      await repo.createOfflineSale(
        deviceId: deviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_2', 1)],
      );
      expect((await clientDb.select(clientDb.localSales).get()).length, equals(2));

      // 3. Restore sırasında resumeLiveDb adımında kasıtlı bir çökme simüle et
      await expectLater(
        DatabaseBackupEngine.restoreBackup(
          backupId: backup.backupId,
          liveDbFile: clientDbFile,
          backupPassword: validPassword,
          storageProvider: storageProvider,
          expectedDeviceId: deviceId,
          expectedTenantId: tenantId,
          expectedDatabaseType: DatabaseType.clientLocal,
          currentSchemaVersion: 1,
          pauseLiveDb: () async {
            await clientDb.close();
          },
          resumeLiveDb: () async {
            // Hata simülasyonu: DB açılışında beklenmeyen çökme
            throw StateError('Simüle Edilmiş Kritik Restore Çökmesi');
          },
          safetyBackupDir: safetyBackupDir,
        ),
        throwsA(isA<StateError>()),
      );

      // 4. Rollback mekanizması canlı DB'yi koruyucu yedekten geri yüklemiş olmalı
      clientDb = ClientDatabase(clientDbFile);
      repo = ClientStorageRepository(clientDb);

      // Veritabanının çökmeden önceki 2 satışını eksiksiz koruduğunu doğrula
      final preservedSales = await clientDb.select(clientDb.localSales).get();
      expect(preservedSales.length, equals(2));
    });

    test('11. Mevcut Yedeğin Üzerine Yazılmaması (Immutability)', () async {
      final rawBytes = await clientDbFile.readAsBytes();
      final checksum = sha256.convert(rawBytes).toString().toLowerCase();

      final fixedTs = DateTime.utc(2026, 11, 6, 12, 0, 0);
      final manifest = BackupManifest(
        backupId: 'immutable_backup_001',
        deviceId: deviceId,
        tenantId: tenantId,
        storeId: storeId,
        databaseType: DatabaseType.clientLocal,
        schemaVersion: 1,
        appVersion: '1.0.0',
        timestamp: fixedTs,
        checksum: checksum,
        unencryptedSizeBytes: rawBytes.length,
        encryptedSizeBytes: 0,
        kdfIterations: testKdfIterations,
      );

      final packageBytes = BackupCryptoService.encryptPackage(
        databaseBytes: rawBytes,
        password: validPassword,
        manifest: manifest,
      );

      // 1. İlk kayıt başarılı
      await storageProvider.saveBackup(packageBytes: packageBytes, manifest: manifest);

      // 2. Aynı manifest ve dosya adı ile ikinci kayıt StateError fırlatmalı
      expect(
        () async => await storageProvider.saveBackup(packageBytes: packageBytes, manifest: manifest),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('üzerine yazılamaz'))),
      );
    });

    test('12. Saklama Süresi Temizliği (Retention Policy: 30 Gün Günlük, 12 Ay Aylık Arşiv)', () async {
      final now = DateTime.utc(2026, 11, 6, 12, 0, 0);
      final rawBytes = await clientDbFile.readAsBytes();
      final checksum = sha256.convert(rawBytes).toString().toLowerCase();

      // Test için farklı tarihlerde 5 yedek paketi oluştur
      // B1: 5 gün önce (Son 30 gün içinde -> KORUNMALI)
      // B2: 25 gün önce (Son 30 gün içinde -> KORUNMALI)
      // B3: 45 gün önce, ayın ilk günü değil (30 günden eski ve aylık değil -> SİLİNMELİ)
      // B4: 60 gün önce (2 ay önce), ayın 1. günü (Aylık arşiv -> KORUNMALI)
      // B5: 400 gün önce (13 ay önce) (12 aydan eski -> SİLİNMELİ)
      final testManifests = [
        BackupManifest(
          backupId: 'b1_recent_5d',
          deviceId: deviceId,
          tenantId: tenantId,
          storeId: storeId,
          databaseType: DatabaseType.clientLocal,
          schemaVersion: 1,
          appVersion: '1.0.0',
          timestamp: now.subtract(const Duration(days: 5)),
          checksum: checksum,
          unencryptedSizeBytes: rawBytes.length,
          encryptedSizeBytes: 0,
          kdfIterations: testKdfIterations,
        ),
        BackupManifest(
          backupId: 'b2_recent_25d',
          deviceId: deviceId,
          tenantId: tenantId,
          storeId: storeId,
          databaseType: DatabaseType.clientLocal,
          schemaVersion: 1,
          appVersion: '1.0.0',
          timestamp: now.subtract(const Duration(days: 25)),
          checksum: checksum,
          unencryptedSizeBytes: rawBytes.length,
          encryptedSizeBytes: 0,
          kdfIterations: testKdfIterations,
        ),
        BackupManifest(
          backupId: 'b3_expired_daily_45d',
          deviceId: deviceId,
          tenantId: tenantId,
          storeId: storeId,
          databaseType: DatabaseType.clientLocal,
          schemaVersion: 1,
          appVersion: '1.0.0',
          timestamp: now.subtract(const Duration(days: 45)),
          checksum: checksum,
          unencryptedSizeBytes: rawBytes.length,
          encryptedSizeBytes: 0,
          kdfIterations: testKdfIterations,
          isMonthlyArchive: false,
        ),
        BackupManifest(
          backupId: 'b4_monthly_archive_60d',
          deviceId: deviceId,
          tenantId: tenantId,
          storeId: storeId,
          databaseType: DatabaseType.clientLocal,
          schemaVersion: 1,
          appVersion: '1.0.0',
          timestamp: now.subtract(const Duration(days: 60)),
          checksum: checksum,
          unencryptedSizeBytes: rawBytes.length,
          encryptedSizeBytes: 0,
          kdfIterations: testKdfIterations,
          isMonthlyArchive: true, // Aylık arşiv
        ),
        BackupManifest(
          backupId: 'b5_expired_archive_400d',
          deviceId: deviceId,
          tenantId: tenantId,
          storeId: storeId,
          databaseType: DatabaseType.clientLocal,
          schemaVersion: 1,
          appVersion: '1.0.0',
          timestamp: now.subtract(const Duration(days: 400)),
          checksum: checksum,
          unencryptedSizeBytes: rawBytes.length,
          encryptedSizeBytes: 0,
          kdfIterations: testKdfIterations,
          isMonthlyArchive: true, // 12 ayı aşmış
        ),
      ];

      for (final m in testManifests) {
        final pkg = BackupCryptoService.encryptPackage(
          databaseBytes: rawBytes,
          password: validPassword,
          manifest: m,
        );
        await storageProvider.saveBackup(packageBytes: pkg, manifest: m);
      }

      final initialBackups = await storageProvider.listBackups();
      expect(initialBackups.length, equals(5));

      // Temizlik politikasını çalıştır
      const retentionMgr = RetentionPolicyManager();
      final prunedIds = await retentionMgr.executePruning(storageProvider, now: now);

      // b3 (45 günlük eski) ve b5 (400 günlük eski arşiv) silinmeli
      expect(prunedIds, containsAll(['b3_expired_daily_45d', 'b5_expired_archive_400d']));

      final remainingBackups = await storageProvider.listBackups();
      final remainingIds = remainingBackups.map((b) => b.backupId).toList();

      expect(remainingIds, containsAll(['b1_recent_5d', 'b2_recent_25d', 'b4_monthly_archive_60d']));
      expect(remainingIds, isNot(contains('b3_expired_daily_45d')));
      expect(remainingIds, isNot(contains('b5_expired_archive_400d')));
    });

    test('13. Merkezi DB (market_master.db) ve Client DB Bağımsız Yedekleme ve Doğrulaması', () async {
      // 1. Merkezi Master DB simülasyonu
      final masterDbFile = File(p.join(tempDir.path, 'master_sim.db'));
      final masterRaw = sqlite3.open(masterDbFile.path);
      masterRaw.execute('''
        PRAGMA journal_mode = WAL;
        CREATE TABLE central_sales (id TEXT PRIMARY KEY, amount INTEGER);
        INSERT INTO central_sales VALUES ('cs_1', 99000);
      ''');
      masterRaw.dispose();

      // Merkezi DB yedeği al
      final centralBackup = await DatabaseBackupEngine.createBackup(
        liveDbFile: masterDbFile,
        executeVacuumInto: (snapPath) async {
          final raw = sqlite3.open(masterDbFile.path);
          raw.execute("VACUUM INTO '${snapPath.replaceAll("'", "''")}';");
          raw.dispose();
        },
        deviceId: 'SERVER_HUB',
        tenantId: tenantId,
        storeId: 'store_central',
        databaseType: DatabaseType.centralMaster,
        schemaVersion: 1,
        appVersion: '1.0.0',
        backupPassword: validPassword,
        storageProvider: storageProvider,
        kdfIterations: testKdfIterations,
      );

      expect(centralBackup.manifest.databaseType, equals(DatabaseType.centralMaster));
      expect(centralBackup.manifest.deviceId, equals('SERVER_HUB'));

      // 2. Client DB yedeği al
      final clientBackup = await DatabaseBackupEngine.createBackup(
        liveDbFile: clientDbFile,
        executeVacuumInto: (snapPath) async {
          final escaped = snapPath.replaceAll("'", "''");
          await clientDb.customStatement("VACUUM INTO '$escaped';");
        },
        deviceId: deviceId,
        tenantId: tenantId,
        storeId: storeId,
        databaseType: DatabaseType.clientLocal,
        schemaVersion: 1,
        appVersion: '1.0.0',
        backupPassword: validPassword,
        storageProvider: storageProvider,
        kdfIterations: testKdfIterations,
      );

      expect(clientBackup.manifest.databaseType, equals(DatabaseType.clientLocal));
      expect(clientBackup.manifest.deviceId, equals(deviceId));

      // 3. Depolamada her iki türün bağımsız listelendiğini ve filtrelenebildiğini doğrula
      final centralList = await storageProvider.listBackups(databaseType: DatabaseType.centralMaster);
      final clientList = await storageProvider.listBackups(databaseType: DatabaseType.clientLocal);

      expect(centralList.map((b) => b.backupId), contains(centralBackup.backupId));
      expect(centralList.map((b) => b.backupId), isNot(contains(clientBackup.backupId)));

      expect(clientList.map((b) => b.backupId), contains(clientBackup.backupId));
      expect(clientList.map((b) => b.backupId), isNot(contains(centralBackup.backupId)));
    });

    test('14. Restore Sırasında SQLite Bağlantı Güvenliği (Lifecycle Pause/Resume & Integrity Checks)', () async {
      // 1. Canlı veritabanında 1 satış oluştur ve yedek al
      await repo.createOfflineSale(
        deviceId: deviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_1', 1)],
      );

      final backup = await DatabaseBackupEngine.createBackup(
        liveDbFile: clientDbFile,
        executeVacuumInto: (snapPath) async {
          final escaped = snapPath.replaceAll("'", "''");
          await clientDb.customStatement("VACUUM INTO '$escaped';");
        },
        deviceId: deviceId,
        tenantId: tenantId,
        storeId: storeId,
        databaseType: DatabaseType.clientLocal,
        schemaVersion: 1,
        appVersion: '1.0.0',
        backupPassword: validPassword,
        storageProvider: storageProvider,
        kdfIterations: testKdfIterations,
      );

      // 2. Canlı veritabanına 1 satış daha ekle
      await repo.createOfflineSale(
        deviceId: deviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_2', 1)],
      );
      expect((await clientDb.select(clientDb.localSales).get()).length, equals(2));

      // Sıralı çağrıları izleme
      final lifecycleEvents = <String>[];

      // 3. Kontrollü restore akışı: pauseLiveDb çağrısı canlı bağlantıyı kapatmalı, resumeLiveDb yeniden açmalı
      final restoreRes = await DatabaseBackupEngine.restoreBackup(
        backupId: backup.backupId,
        liveDbFile: clientDbFile,
        backupPassword: validPassword,
        storageProvider: storageProvider,
        expectedDeviceId: deviceId,
        expectedTenantId: tenantId,
        expectedDatabaseType: DatabaseType.clientLocal,
        currentSchemaVersion: 1,
        pauseLiveDb: () async {
          lifecycleEvents.add('PAUSE_CALLED');
          await clientDb.close();
          lifecycleEvents.add('DB_CLOSED');
        },
        resumeLiveDb: () async {
          lifecycleEvents.add('RESUME_CALLED');
          clientDb = ClientDatabase(clientDbFile);
          repo = ClientStorageRepository(clientDb);
          lifecycleEvents.add('DB_REOPENED');
        },
        safetyBackupDir: safetyBackupDir,
      );

      expect(restoreRes.backupId, equals(backup.backupId));
      expect(lifecycleEvents, equals(['PAUSE_CALLED', 'DB_CLOSED', 'RESUME_CALLED', 'DB_REOPENED']));

      // 4. Yeniden açılan canlı bağlantının sağlıklı çalıştığını doğrula (1 satışa dönmeli)
      final restoredSales = await clientDb.select(clientDb.localSales).get();
      expect(restoredSales.length, equals(1));
      expect(restoredSales.first.clientSeq, equals(1));
    });

    test('15. PBKDF2-HMAC-SHA256 600.000 İterasyon Üretim Güvenliği, Süre Ölçümü ve Bütünlük Doğrulaması', () async {
      // 1. Canlı DB'den 600.000 iterasyonlu şifreli yedek al
      final backupStopwatch = Stopwatch()..start();
      final backup = await DatabaseBackupEngine.createBackup(
        liveDbFile: clientDbFile,
        executeVacuumInto: (snapPath) async {
          final escaped = snapPath.replaceAll("'", "''");
          await clientDb.customStatement("VACUUM INTO '$escaped';");
        },
        deviceId: deviceId,
        tenantId: tenantId,
        storeId: storeId,
        databaseType: DatabaseType.clientLocal,
        schemaVersion: 1,
        appVersion: '1.0.0',
        backupPassword: validPassword,
        storageProvider: storageProvider,
        kdfIterations: 600000, // ZORUNLU: Tam üretim seviyesi 600.000 iterasyon
      );
      backupStopwatch.stop();

      expect(backup.manifest.kdfIterations, equals(600000));
      print('[BENCHMARK] PBKDF2 600.000 İterasyon Backup Şifreleme Süresi: ${backupStopwatch.elapsedMilliseconds} ms (${(backupStopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)} sn)');

      // 2. Canlı DB'yi değiştir
      await repo.createOfflineSale(
        deviceId: deviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_2', 1)],
      );

      // 3. 600.000 iterasyonlu yedeği geri yükle (Restore süresini ölç)
      final restoreStopwatch = Stopwatch()..start();
      final restoreResult = await DatabaseBackupEngine.restoreBackup(
        backupId: backup.backupId,
        liveDbFile: clientDbFile,
        backupPassword: validPassword,
        storageProvider: storageProvider,
        expectedDeviceId: deviceId,
        expectedTenantId: tenantId,
        expectedDatabaseType: DatabaseType.clientLocal,
        currentSchemaVersion: 1,
        pauseLiveDb: () async => await clientDb.close(),
        resumeLiveDb: () async {
          clientDb = ClientDatabase(clientDbFile);
          repo = ClientStorageRepository(clientDb);
        },
        safetyBackupDir: safetyBackupDir,
      );
      restoreStopwatch.stop();

      print('[BENCHMARK] PBKDF2 600.000 İterasyon Restore Doğrulama & Çözme Süresi: ${restoreStopwatch.elapsedMilliseconds} ms (${(restoreStopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)} sn)');
      expect(restoreResult.manifest.kdfIterations, equals(600000));

      // 4. Çözülen veritabanı bütünlüğünün ve verilerin tam olduğunu teyit et
      final sales = await clientDb.select(clientDb.localSales).get();
      expect(sales.isEmpty, isTrue); // Başlangıç durumunda henüz satış yoktu
      final prods = await clientDb.select(clientDb.localProducts).get();
      expect(prods.length, equals(2));
    });

    test('16. Eski Şema Sürümünden Restore ve Başarılı Migration Doğrulaması (v1 -> v2)', () async {
      // 1. Şema sürümü 1 olan bir yedek oluştur
      final backup = await DatabaseBackupEngine.createBackup(
        liveDbFile: clientDbFile,
        executeVacuumInto: (snapPath) async {
          final escaped = snapPath.replaceAll("'", "''");
          await clientDb.customStatement("VACUUM INTO '$escaped';");
        },
        deviceId: deviceId,
        tenantId: tenantId,
        storeId: storeId,
        databaseType: DatabaseType.clientLocal,
        schemaVersion: 1,
        appVersion: '1.0.0',
        backupPassword: validPassword,
        storageProvider: storageProvider,
        kdfIterations: testKdfIterations,
      );

      // 2. Uygulama şema sürümü 2'ye geçtiğinde (currentSchemaVersion = 2) restore et
      bool migrationExecuted = false;

      final restoreRes = await DatabaseBackupEngine.restoreBackup(
        backupId: backup.backupId,
        liveDbFile: clientDbFile,
        backupPassword: validPassword,
        storageProvider: storageProvider,
        expectedDeviceId: deviceId,
        expectedTenantId: tenantId,
        expectedDatabaseType: DatabaseType.clientLocal,
        currentSchemaVersion: 2, // Yeni şema sürümü
        minSupportedSchemaVersion: 1, // Minimum desteklenen
        pauseLiveDb: () async => await clientDb.close(),
        applySchemaMigration: (dynamic targetOrFrom, [dynamic fromOrTo, dynamic toVer]) async {
          migrationExecuted = true;
          final File targetFile = targetOrFrom is File ? targetOrFrom : clientDbFile;
          final int fromVersion = targetOrFrom is File ? fromOrTo as int : targetOrFrom as int;
          final int toVersion = targetOrFrom is File ? toVer as int : fromOrTo as int;

          expect(fromVersion, equals(1));
          expect(toVersion, equals(2));

          // Yeni sürüm tablosunu hedef (staging) veritabanına ekle
          final raw = sqlite3.open(targetFile.path);
          try {
            raw.execute('CREATE TABLE customer_loyalty (id TEXT PRIMARY KEY, points INTEGER);');
            raw.execute('INSERT INTO customer_loyalty VALUES (\'cust_1\', 500);');
            raw.execute('PRAGMA user_version = 2;');
          } finally {
            raw.dispose();
          }
        },
        resumeLiveDb: () async {
          clientDb = ClientDatabase(clientDbFile);
          repo = ClientStorageRepository(clientDb);
        },
        safetyBackupDir: safetyBackupDir,
      );

      expect(restoreRes.backupId, equals(backup.backupId));
      expect(migrationExecuted, isTrue);

      // 3. Migrasyon sonucu eklenen yeni tablonun okunabildiğini doğrula
      final checkRaw = sqlite3.open(clientDbFile.path);
      try {
        final rows = checkRaw.select('SELECT points FROM customer_loyalty WHERE id = ?;', ['cust_1']);
        expect(rows.first['points'], equals(500));
      } finally {
        checkRaw.dispose();
      }
    });

    test('17. Eski Şema Sürümünden Restore Sırasında Migration Hatası ve Koruyucu Rollback', () async {
      // 1. Canlı DB'de değerli bir satış var
      await repo.createOfflineSale(
        deviceId: deviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_1', 1)],
      );
      expect((await clientDb.select(clientDb.localSales).get()).length, equals(1));

      // 2. Eski şema (v1) yedeği al
      final backup = await DatabaseBackupEngine.createBackup(
        liveDbFile: clientDbFile,
        executeVacuumInto: (snapPath) async {
          final escaped = snapPath.replaceAll("'", "''");
          await clientDb.customStatement("VACUUM INTO '$escaped';");
        },
        deviceId: deviceId,
        tenantId: tenantId,
        storeId: storeId,
        databaseType: DatabaseType.clientLocal,
        schemaVersion: 1,
        appVersion: '1.0.0',
        backupPassword: validPassword,
        storageProvider: storageProvider,
        kdfIterations: testKdfIterations,
      );

      // 3. Canlı veritabanına yeni bir satış daha yap (korunması gereken güncel durum)
      await repo.createOfflineSale(
        deviceId: deviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_2', 1)],
      );
      expect((await clientDb.select(clientDb.localSales).get()).length, equals(2));

      // 4. Restore sırasında applySchemaMigration adımında hata fırlat
      expect(
        () async => await DatabaseBackupEngine.restoreBackup(
          backupId: backup.backupId,
          liveDbFile: clientDbFile,
          backupPassword: validPassword,
          storageProvider: storageProvider,
          expectedDeviceId: deviceId,
          expectedTenantId: tenantId,
          expectedDatabaseType: DatabaseType.clientLocal,
          currentSchemaVersion: 2,
          minSupportedSchemaVersion: 1,
          pauseLiveDb: () async {
            print('[TEST 10 PAUSE CALLED]');
            await clientDb.close();
            print('[TEST 10 DB CLOSED]');
          },
          applySchemaMigration: (fromVersion, toVersion) async {
            throw const FormatException('Simüle Edilmiş Şema Migrasyon Hatası (Bozuk DDL veya kısıtlama ihlali)');
          },
          resumeLiveDb: () async {
            clientDb = ClientDatabase(clientDbFile);
            repo = ClientStorageRepository(clientDb);
          },
          safetyBackupDir: safetyBackupDir,
        ),
        throwsA(isA<FormatException>()),
      );

      // 5. Canlı veritabanının koruyucu güvenlik yedeğinden (safety_snapshot) eksiksiz kurtarıldığını teyit et
      clientDb = ClientDatabase(clientDbFile);
      repo = ClientStorageRepository(clientDb);

      final preservedSales = await clientDb.select(clientDb.localSales).get();
      expect(preservedSales.length, equals(2)); // Canlı DB 2 satışı korumuş olmalıdır
    });

    test('18. Desteklenmeyen Eski Şema Sürümünün Reddedilmesi (minSupportedSchemaVersion)', () async {
      // 1. Şema sürümü 1 olan bir yedek oluştur
      final rawBytes = await clientDbFile.readAsBytes();
      final checksum = sha256.convert(rawBytes).toString().toLowerCase();

      final manifestV1 = BackupManifest(
        backupId: 'backup_unsupported_v1',
        deviceId: deviceId,
        tenantId: tenantId,
        storeId: storeId,
        databaseType: DatabaseType.clientLocal,
        schemaVersion: 1, // Uygulama minimum v2 desteklerken bu sürüm eski kalır
        appVersion: '1.0.0',
        timestamp: DateTime.now().toUtc(),
        checksum: checksum,
        unencryptedSizeBytes: rawBytes.length,
        encryptedSizeBytes: 0,
        kdfIterations: testKdfIterations,
      );

      final pkgBytes = BackupCryptoService.encryptPackage(
        databaseBytes: rawBytes,
        password: validPassword,
        manifest: manifestV1,
      );
      await storageProvider.saveBackup(packageBytes: pkgBytes, manifest: manifestV1);

      // 2. minSupportedSchemaVersion = 2 iken v1 yedeğini restore etme girişiminin reddedildiğini doğrula
      expect(
        () async => await DatabaseBackupEngine.restoreBackup(
          backupId: 'backup_unsupported_v1',
          liveDbFile: clientDbFile,
          backupPassword: validPassword,
          storageProvider: storageProvider,
          expectedDeviceId: deviceId,
          expectedTenantId: tenantId,
          expectedDatabaseType: DatabaseType.clientLocal,
          currentSchemaVersion: 3, // Mevcut sürüm v3
          minSupportedSchemaVersion: 2, // Minimum kabul edilen v2
          pauseLiveDb: () async {},
          resumeLiveDb: () async {},
          safetyBackupDir: safetyBackupDir,
        ),
        throwsA(isA<BackupException>().having((e) => e.code, 'code', equals('ERR_UNSUPPORTED_OLD_SCHEMA'))),
      );

      // Canlı DB'nin sağlam kaldığını doğrula
      final prods = await clientDb.select(clientDb.localProducts).get();
      expect(prods.length, equals(2));
    });

    test('19. Salt Benzersizliği ve Kriptografik Rastgelelik Doğrulaması (CSPRNG Uniqueness)', () async {
      // Aynı veritabanı içeriği ve aynı parola ile ardışık iki yedek al
      final b1 = await DatabaseBackupEngine.createBackup(
        liveDbFile: clientDbFile,
        executeVacuumInto: (snapPath) async {
          final escaped = snapPath.replaceAll("'", "''");
          await clientDb.customStatement("VACUUM INTO '$escaped';");
        },
        deviceId: deviceId,
        tenantId: tenantId,
        storeId: storeId,
        databaseType: DatabaseType.clientLocal,
        schemaVersion: 1,
        appVersion: '1.0.0',
        backupPassword: validPassword,
        storageProvider: storageProvider,
        kdfIterations: testKdfIterations,
      );

      final b2 = await DatabaseBackupEngine.createBackup(
        liveDbFile: clientDbFile,
        executeVacuumInto: (snapPath) async {
          final escaped = snapPath.replaceAll("'", "''");
          await clientDb.customStatement("VACUUM INTO '$escaped';");
        },
        deviceId: deviceId,
        tenantId: tenantId,
        storeId: storeId,
        databaseType: DatabaseType.clientLocal,
        schemaVersion: 1,
        appVersion: '1.0.0',
        backupPassword: validPassword,
        storageProvider: storageProvider,
        kdfIterations: testKdfIterations,
      );

      final pkg1 = await (await storageProvider.getBackupFile(b1.backupId)).readAsBytes();
      final pkg2 = await (await storageProvider.getBackupFile(b2.backupId)).readAsBytes();

      // Salt ve IV bölgelerini çıkar
      final mLen1 = (pkg1[8] << 24) | (pkg1[9] << 16) | (pkg1[10] << 8) | pkg1[11];
      final mLen2 = (pkg2[8] << 24) | (pkg2[9] << 16) | (pkg2[10] << 8) | pkg2[11];

      final salt1 = pkg1.sublist(12 + mLen1, 12 + mLen1 + 16);
      final salt2 = pkg2.sublist(12 + mLen2, 12 + mLen2 + 16);

      final iv1 = pkg1.sublist(12 + mLen1 + 16, 12 + mLen1 + 32);
      final iv2 = pkg2.sublist(12 + mLen2 + 16, 12 + mLen2 + 32);

      // 1. Salt ve IV'ler kesinlikle birbirinden farklı olmalıdır (CSPRNG)
      expect(salt1, isNot(equals(salt2)));
      expect(iv1, isNot(equals(iv2)));

      // 2. Paketlerin tamamı farklı olmalıdır (Non-deterministic ciphertext)
      expect(pkg1, isNot(equals(pkg2)));
    });

    test('20. Restore Sırasında Crash / Elektrik Kesintisi Simülasyonu ve İleriye Doğru Otomatik Kurtarma', () async {
      // 1. Canlı veritabanında 1 satış oluştur
      await repo.createOfflineSale(
        deviceId: deviceId,
        paymentMethod: 'CASH',
        items: [CartItemInput.units('prod_1', 1)],
      );

      // 2. Staging dosyasını aynı dizinde hazırla
      final liveDir = clientDbFile.parent;
      final stagingFile = File(p.join(liveDir.path, '${p.basename(clientDbFile.path)}.restore_staging.tmp'));
      final swapBakFile = File(p.join(liveDir.path, '${p.basename(clientDbFile.path)}.swap_bak'));
      final journalFile = File(p.join(liveDir.path, '${p.basename(clientDbFile.path)}.restore_journal'));

      // Staging veritabanı: içinde 2 satış olan geçerli bir SQLite DB oluştur
      final rawStaging = sqlite3.open(stagingFile.path);
      rawStaging.execute('''
        PRAGMA journal_mode = WAL;
        CREATE TABLE local_sales (id TEXT PRIMARY KEY, client_seq INTEGER, total_amount INTEGER);
        INSERT INTO local_sales VALUES ('sale_recovered_1', 1, 5000);
        INSERT INTO local_sales VALUES ('sale_recovered_2', 2, 7500);
      ''');
      rawStaging.dispose();

      // 3. Simülasyon: Canlı veritabanını kapat, canlı dosyayı swap_bak'a taşı ve journal yaz (Elektrik tam burada kesildi!)
      await clientDb.close();
      await clientDbFile.rename(swapBakFile.path);

      final journalData = {
        'version': 1,
        'staging_file': stagingFile.path,
        'safety_file': p.join(safetyBackupDir.path, 'dummy_safety.db'),
        'live_file': clientDbFile.path,
        'swap_file': swapBakFile.path,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };
      await journalFile.writeAsString(jsonEncode(journalData), flush: true);

      // Bu anda: clientDbFile diskte yok! swap_bak, staging ve journal var.
      expect(clientDbFile.existsSync(), isFalse);
      expect(stagingFile.existsSync(), isTrue);
      expect(swapBakFile.existsSync(), isTrue);
      expect(journalFile.existsSync(), isTrue);

      // 4. Uygulama yeniden başlatılıyor: recoverPendingRestoreSync otomatik tetiklenir
      final recovered = DatabaseBackupEngine.recoverPendingRestoreSync(clientDbFile);
      expect(recovered, isTrue);

      // 5. Kurtarma doğrulaması:
      // Canlı dosya geri geldi, staging ve swap_bak temizlendi, journal silindi
      expect(clientDbFile.existsSync(), isTrue);
      expect(stagingFile.existsSync(), isFalse);
      expect(swapBakFile.existsSync(), isFalse);
      expect(journalFile.existsSync(), isFalse);

      // Canlı veritabanını aç ve kurtarılan 2 satışın okunduğunu doğrula
      final checkDb = sqlite3.open(clientDbFile.path);
      final rows = checkDb.select('SELECT id, total_amount FROM local_sales ORDER BY client_seq;');
      checkDb.dispose();

      expect(rows.length, equals(2));
      expect(rows[0]['id'], equals('sale_recovered_1'));
      expect(rows[1]['id'], equals('sale_recovered_2'));
    });

    test('21. Restore Sırasında Crash ve Hasarlı Staging Durumunda Swap/Safety Rollback Kurtarma', () async {
      // 1. Canlı dosyayı hazırla (1 satış)
      final liveDir = clientDbFile.parent;
      final stagingFile = File(p.join(liveDir.path, '${p.basename(clientDbFile.path)}.restore_staging.tmp'));
      final swapBakFile = File(p.join(liveDir.path, '${p.basename(clientDbFile.path)}.swap_bak'));
      final journalFile = File(p.join(liveDir.path, '${p.basename(clientDbFile.path)}.restore_journal'));

      await clientDb.close();

      // swapBakFile: çökmeden önceki orijinal sağlam canlı DB (1 satış)
      final rawSwap = sqlite3.open(swapBakFile.path);
      rawSwap.execute('''
        PRAGMA journal_mode = WAL;
        CREATE TABLE local_sales (id TEXT PRIMARY KEY, client_seq INTEGER, total_amount INTEGER);
        INSERT INTO local_sales VALUES ('sale_original_live', 1, 9900);
      ''');
      rawSwap.dispose();

      // stagingFile: yarım yazılmış / hasarlı dosya simülasyonu
      await stagingFile.writeAsBytes([0x00, 0x01, 0x02, 0x03], flush: true);

      // Journal yaz (Elektrik tam staging bozulduğunda kesildi)
      final journalData = {
        'version': 1,
        'staging_file': stagingFile.path,
        'safety_file': p.join(safetyBackupDir.path, 'dummy_safety.db'),
        'live_file': clientDbFile.path,
        'swap_file': swapBakFile.path,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };
      await journalFile.writeAsString(jsonEncode(journalData), flush: true);

      if (clientDbFile.existsSync()) {
        clientDbFile.deleteSync();
      }

      // 2. Uygulama açılışı: Hasarlı staging reddedilir ve swap_bak orijinal durumuna geri dönülür
      final recovered = DatabaseBackupEngine.recoverPendingRestoreSync(clientDbFile);
      expect(recovered, isTrue);

      expect(clientDbFile.existsSync(), isTrue);
      expect(stagingFile.existsSync(), isFalse);
      expect(journalFile.existsSync(), isFalse);

      // Orijinal verinin korunduğunu doğrula
      final checkDb = sqlite3.open(clientDbFile.path);
      final rows = checkDb.select('SELECT id, total_amount FROM local_sales;');
      checkDb.dispose();

      expect(rows.length, equals(1));
      expect(rows.first['id'], equals('sale_original_live'));
    });

    test('22. Mobil İstemci DB Yaşam Döngüsü ve İzolasyonu (DatabaseType.mobileLocal)', () async {
      // 1. Mobil cihaz veritabanı simülasyonu
      final mobileDbFile = File(p.join(tempDir.path, 'client_mobile.db'));
      final rawMobile = sqlite3.open(mobileDbFile.path);
      rawMobile.execute('''
        PRAGMA journal_mode = WAL;
        CREATE TABLE mobile_sales (id TEXT PRIMARY KEY, client_seq INTEGER, total_amount INTEGER);
        INSERT INTO mobile_sales VALUES ('mob_sale_1', 1, 3500);
      ''');
      rawMobile.dispose();

      // Mobil cihaz yedeği al
      final mobileBackup = await DatabaseBackupEngine.createBackup(
        liveDbFile: mobileDbFile,
        executeVacuumInto: (snapPath) async {
          final raw = sqlite3.open(mobileDbFile.path);
          raw.execute("VACUUM INTO '${snapPath.replaceAll("'", "''")}';");
          raw.dispose();
        },
        deviceId: 'DEV_MOBILE_ANDROID_01',
        tenantId: tenantId,
        storeId: 'store_mobile',
        databaseType: DatabaseType.mobileLocal,
        schemaVersion: 1,
        appVersion: '1.0.0',
        backupPassword: validPassword,
        storageProvider: storageProvider,
        kdfIterations: testKdfIterations,
      );

      expect(mobileBackup.manifest.databaseType, equals(DatabaseType.mobileLocal));
      expect(mobileBackup.manifest.deviceId, equals('DEV_MOBILE_ANDROID_01'));

      // 2. Çapraz Yükleme Koruması: Mobil yedeğin Client Local veya Central Master üzerine yüklenmesi KESİNLİKLE engellenmeli
      expect(
        () async => await DatabaseBackupEngine.restoreBackup(
          backupId: mobileBackup.backupId,
          liveDbFile: clientDbFile,
          backupPassword: validPassword,
          storageProvider: storageProvider,
          expectedDeviceId: deviceId, // DEV_WIN_CASHIER_01
          expectedTenantId: tenantId,
          expectedDatabaseType: DatabaseType.clientLocal,
          currentSchemaVersion: 1,
          pauseLiveDb: () async {},
          resumeLiveDb: () async {},
          safetyBackupDir: safetyBackupDir,
        ),
        throwsA(isA<BackupException>().having((e) => e.code, 'code', equals('ERR_DATABASE_TYPE_MISMATCH'))),
      );

      // 3. Mobil DB'nin kendi üzerinde kontrollü ve atomik geri yüklenmesi
      // Canlı mobil DB'ye yeni satış ekle
      final rawMobileUpdate = sqlite3.open(mobileDbFile.path);
      rawMobileUpdate.execute("INSERT INTO mobile_sales VALUES ('mob_sale_2', 2, 8000);");
      rawMobileUpdate.dispose();

      final mobileRestoreRes = await DatabaseBackupEngine.restoreBackup(
        backupId: mobileBackup.backupId,
        liveDbFile: mobileDbFile,
        backupPassword: validPassword,
        storageProvider: storageProvider,
        expectedDeviceId: 'DEV_MOBILE_ANDROID_01',
        expectedTenantId: tenantId,
        expectedDatabaseType: DatabaseType.mobileLocal,
        currentSchemaVersion: 1,
        pauseLiveDb: () async {},
        resumeLiveDb: () async {},
        safetyBackupDir: safetyBackupDir,
      );

      expect(mobileRestoreRes.backupId, equals(mobileBackup.backupId));

      // 4. Mobil DB'nin durum 1'e (1 satış) döndüğünü ve bütünlüğün korunduğunu doğrula
      final checkMobile = sqlite3.open(mobileDbFile.path);
      final mRows = checkMobile.select('SELECT id FROM mobile_sales;');
      checkMobile.dispose();

      expect(mRows.length, equals(1));
      expect(mRows.first['id'], equals('mob_sale_1'));
    });
  });
}

