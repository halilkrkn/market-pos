import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mms_test_only_b1_pkg_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  BackupManifest sampleManifest({String backupId = 'bak_v2_001'}) => BackupManifest(
        backupId: backupId,
        deviceId: 'HUB-WIN-01',
        tenantId: 'tenant_pilot',
        storeId: 'store_01',
        databaseType: DatabaseType.centralMaster,
        schemaVersion: 4,
        appVersion: '1.0.0',
        timestamp: DateTime.utc(2026, 11, 22, 0, 0),
        checksum: sha256.convert(const [1, 2, 3]).toString(),
        unencryptedSizeBytes: 3,
        encryptedSizeBytes: 0,
      );

  group('Faz B-1: MMSBAK02 Streaming AEAD Crypto & Retention', () {
    test('BK-001: 12+ karakter parola politikası, MMSBAK02 encrypt/decrypt ve MMSBAK01 geriye dönük uyumluluk', () async {
      final plainFile = File(p.join(tempDir.path, 'sample.db'));
      final plainBytes = Uint8List.fromList(List<int>.generate(65536, (i) => (i * 31) & 0xff));
      await plainFile.writeAsBytes(plainBytes, flush: true);

      final outV2 = File(p.join(tempDir.path, 'pkg_v2.mmsbak'));
      expect(
        () => MmsbakV2Crypto.encryptFile(
          inputFile: plainFile,
          outputFile: outV2,
          password: 'kisa_11_kar',
          manifest: sampleManifest(),
          kdfIterations: 1000,
        ),
        throwsA(isA<BackupCryptoException>()),
      );

      const pass = 'PilotMarket-Kurtarma-2026!';
      final v2Manifest = await MmsbakV2Crypto.encryptFile(
        inputFile: plainFile,
        outputFile: outV2,
        password: pass,
        manifest: sampleManifest(),
        kdfIterations: 1000,
      );
      expect(v2Manifest.encryptionAlgorithm, equals(MmsbakV2Crypto.algorithmId));

      final inspectedV2 = await MmsbakV2Crypto.inspectFile(outV2);
      expect(inspectedV2.formatVersion, equals(2));
      expect(inspectedV2.manifest.backupId, equals('bak_v2_001'));
      expect(
        BackupFileTransfer.verifyPackageStructure(await outV2.readAsBytes()).backupId,
        equals('bak_v2_001'),
      );

      final restoredV2 = File(p.join(tempDir.path, 'restored_v2.db'));
      await MmsbakV2Crypto.decryptFile(
        inputFile: outV2,
        outputFile: restoredV2,
        password: pass,
      );
      expect(await restoredV2.readAsBytes(), equals(plainBytes));

      // MMSBAK01 geriye dönük çözme/inceleme uyumluluğu
      final v1Bytes = BackupCryptoService.encryptPackage(
        databaseBytes: plainBytes,
        password: pass,
        manifest: sampleManifest(backupId: 'bak_v1_compat').copyWith(
          kdfIterations: 1000,
          checksum: sha256.convert(plainBytes).toString(),
          unencryptedSizeBytes: plainBytes.length,
        ),
      );
      final outV1 = File(p.join(tempDir.path, 'pkg_v1.mmsbak'));
      await outV1.writeAsBytes(v1Bytes, flush: true);
      final inspectedV1 = await MmsbakV2Crypto.inspectFile(outV1);
      expect(inspectedV1.formatVersion, equals(1));
      final restoredV1 = File(p.join(tempDir.path, 'restored_v1.db'));
      final decV1Manifest = await MmsbakV2Crypto.decryptFile(
        inputFile: outV1,
        outputFile: restoredV1,
        password: pass,
      );
      expect(decV1Manifest.backupId, equals('bak_v1_compat'));
      expect(await restoredV1.readAsBytes(), equals(plainBytes));
    });

    test('BK-002: Yanlış parola ve 1-bit bozulma (header/DEK/chunk/MAC/truncation/trailing) fail-closed reddedilir', () async {
      final plainFile = File(p.join(tempDir.path, 'tamper_src.db'));
      await plainFile.writeAsBytes(
        Uint8List.fromList(List<int>.generate(12000, (i) => i & 0xff)),
        flush: true,
      );
      final encFile = File(p.join(tempDir.path, 'tamper.mmsbak'));
      await MmsbakV2Crypto.encryptFile(
        inputFile: plainFile,
        outputFile: encFile,
        password: 'DogruParola-EnAz12!',
        manifest: sampleManifest(backupId: 'bak_tamper'),
        kdfIterations: 1000,
        chunkSize: 4096,
      );

      final restored = File(p.join(tempDir.path, 'should_not_exist.db'));
      await expectLater(
        () => MmsbakV2Crypto.decryptFile(
          inputFile: encFile,
          outputFile: restored,
          password: 'YanlisParola-EnAz12!',
        ),
        throwsA(isA<BackupCryptoException>()),
      );
      expect(restored.existsSync(), isFalse);

      final originalBytes = await encFile.readAsBytes();
      // 1) Son baytta (chunk ciphertext/MAC) 1 bit bozulma
      final tailTampered = Uint8List.fromList(originalBytes);
      tailTampered[tailTampered.length - 1] ^= 0x01;
      final tailFile = File(p.join(tempDir.path, 'tail_bad.mmsbak'));
      await tailFile.writeAsBytes(tailTampered, flush: true);
      await expectLater(
        () => MmsbakV2Crypto.decryptFile(
          inputFile: tailFile,
          outputFile: restored,
          password: 'DogruParola-EnAz12!',
        ),
        throwsA(isA<BackupCryptoException>()),
      );

      // 2) Truncation (eksik kesilmiş dosya)
      final truncated = File(p.join(tempDir.path, 'trunc.mmsbak'));
      await truncated.writeAsBytes(originalBytes.sublist(0, originalBytes.length - 5), flush: true);
      await expectLater(
        () => MmsbakV2Crypto.decryptFile(
          inputFile: truncated,
          outputFile: restored,
          password: 'DogruParola-EnAz12!',
        ),
        throwsA(isA<BackupException>()),
      );
      expect(restored.existsSync(), isFalse);
    });

    test('BK-003: Çok parçalı (> 3 MiB, 1 MiB chunk) akışlı şifreleme/çözme tam SHA-256 doğrulaması', () async {
      final largeFile = File(p.join(tempDir.path, 'large_3_2mb.db'));
      final sizeBytes = (3 * 1024 * 1024) + (200 * 1024);
      final data = Uint8List(sizeBytes);
      for (var i = 0; i < sizeBytes; i++) {
        data[i] = (i * 17 + (i >> 8)) & 0xff;
      }
      await largeFile.writeAsBytes(data, flush: true);
      final expectedSha = sha256.convert(data).toString();

      final encFile = File(p.join(tempDir.path, 'large.mmsbak'));
      const pass = 'BuyukAkisliYedekParolasi2026!';
      final man = await MmsbakV2Crypto.encryptFile(
        inputFile: largeFile,
        outputFile: encFile,
        password: pass,
        manifest: sampleManifest(backupId: 'bak_large_3mb'),
        kdfIterations: 1000,
      );
      expect(man.checksum, equals(expectedSha));
      expect(man.unencryptedSizeBytes, equals(sizeBytes));

      final outDb = File(p.join(tempDir.path, 'large_restored.db'));
      final decManifest = await MmsbakV2Crypto.decryptFile(
        inputFile: encFile,
        outputFile: outDb,
        password: pass,
      );
      expect(decManifest.checksum, equals(expectedSha));
      expect(await outDb.length(), equals(sizeBytes));
      expect(await MmsbakV2Crypto.computeFileSha256(outDb), equals(expectedSha));
    });

    test('BK-017: DiskSpaceChecker 2.5 * (db + wal) + 64 MiB formülü ve sınır kontrolleri', () async {
      final dbFile = File(p.join(tempDir.path, 'master.db'));
      final walFile = File('${dbFile.path}-wal');
      await dbFile.writeAsBytes(Uint8List(4 * 1024 * 1024), flush: true); // 4 MiB
      await walFile.writeAsBytes(Uint8List(2 * 1024 * 1024), flush: true); // 2 MiB
      final required = DiskSpaceChecker.computeRequiredBytes(
        dbBytes: 4 * 1024 * 1024,
        walBytes: 2 * 1024 * 1024,
      );
      // 2.5 * 6 MiB + 64 MiB = 79 MiB
      expect(required, equals(79 * 1024 * 1024));

      final failChecker = DiskSpaceChecker(
        freeBytesProbe: (_) async => required - 1,
      );
      final failRes = await failChecker.checkForDatabase(
        databaseFile: dbFile,
        targetDir: tempDir,
      );
      expect(failRes.ok, isFalse);
      expect(failRes.requiredBytes, equals(required));

      final passChecker = DiskSpaceChecker(
        freeBytesProbe: (_) async => required,
      );
      final passRes = await passChecker.checkForDatabase(
        databaseFile: dbFile,
        targetDir: tempDir,
      );
      expect(passRes.ok, isTrue);
    });

    test('BK-018 & BK-019: Drive saklama (30g günlük + 12 takvim ayı + min 1 sert değişmez) vs 7 günlük yerel önbellek ayrımı', () {
      const policy = HubBackupRetentionPolicy();
      final nowUtc = DateTime.utc(2026, 11, 22, 12, 0);

      // BK-018a: Tüm yedekler 24 aydan eski olsa bile son geçerli COMPLETED_UPLOADED korunur
      final onlyOld = [
        HubBackupRetentionCandidate(
          backupId: 'old_1',
          createdAtUtc: DateTime.utc(2024, 1, 10),
          isCompletedUploaded: true,
          driveFileId: 'drive_old_1',
        ),
        HubBackupRetentionCandidate(
          backupId: 'old_2',
          createdAtUtc: DateTime.utc(2024, 5, 10),
          isCompletedUploaded: true,
          driveFileId: 'drive_old_2',
        ),
      ];
      final oldPlan = policy.evaluateDriveRetention(onlyOld, nowUtc: nowUtc);
      expect(oldPlan.retainIds, contains('old_2'));
      expect(oldPlan.retainIds.length, greaterThanOrEqualTo(1));

      // BK-018b: 14 farklı geçmiş takvim ayı + son 30g içi günlük -> en yeni 12 takvim ayı + son 30g korunur
      final multi = <HubBackupRetentionCandidate>[
        HubBackupRetentionCandidate(
          backupId: 'recent_5d',
          createdAtUtc: nowUtc.subtract(const Duration(days: 5)),
          isCompletedUploaded: true,
          driveFileId: 'drv_recent_5d',
          localFilePath: '/backups/recent_5d.mmsbak',
        ),
        HubBackupRetentionCandidate(
          backupId: 'recent_12d',
          createdAtUtc: nowUtc.subtract(const Duration(days: 12)),
          isCompletedUploaded: true,
          driveFileId: 'drv_recent_12d',
          localFilePath: '/backups/recent_12d.mmsbak',
        ),
        HubBackupRetentionCandidate(
          backupId: 'unuploaded_15d',
          createdAtUtc: nowUtc.subtract(const Duration(days: 15)),
          isCompletedUploaded: false,
          localFilePath: '/backups/unuploaded_15d.mmsbak',
        ),
      ];
      for (var m = 2; m <= 15; m++) {
        final dt = DateTime.utc(2026, 11 - m, 15); // Dart DateTime ay taşırmasını otomatik normalize eder
        multi.add(HubBackupRetentionCandidate(
          backupId: 'month_$m',
          createdAtUtc: dt,
          isCompletedUploaded: true,
          driveFileId: 'drv_month_$m',
          localFilePath: '/backups/month_$m.mmsbak',
        ));
      }

      final drvPlan = policy.evaluateDriveRetention(multi, nowUtc: nowUtc);
      expect(drvPlan.retainIds, containsAll(['recent_5d', 'recent_12d']));
      // 14 eski aydan en yeni 12'si korunur, en eski 2'si temizlenir
      expect(drvPlan.pruneIds.length, equals(2));
      expect(drvPlan.retainIds, isNot(contains('unuploaded_15d')));

      // BK-019: Yerel önbellek 7 gün tutar, yüklenmemiş yedeği (unuploaded_15d) korur
      final localPlan = policy.evaluateLocalCacheRetention(multi, nowUtc: nowUtc);
      expect(localPlan.retainIds, contains('recent_5d'));
      expect(localPlan.retainIds, contains('unuploaded_15d'));
      expect(localPlan.pruneIds, contains('recent_12d'));
      expect(localPlan.pruneIds, contains('month_2'));
    });
  });
}
