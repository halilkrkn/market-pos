import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/core/security/secure_token_store.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/core/theme/app_theme.dart';
import 'package:market_pos/features/backup/application/client_backup_service.dart';
import 'package:market_pos/features/backup/application/google_drive_connect_service.dart';
import 'package:market_pos/features/backup/backup_providers.dart';
import 'package:market_pos/features/backup/presentation/widgets/external_backup_section.dart';
import 'package:market_pos/features/setup/domain/app_setup_config.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

class _FakeDriveServer {
  final Map<String, Uint8List> files = <String, Uint8List>{};
  final Map<String, Map<String, dynamic>> meta = <String, Map<String, dynamic>>{};
  final Map<String, String> uploadSessions = <String, String>{};
  int _seq = 0;

  http.Client createClient() => MockClient((req) async {
        if (req.method == 'GET' && req.url.path == '/drive/v3/files') {
          final q = req.url.queryParameters['q'] ?? '';
          if (q.contains('application/vnd.google-apps.folder')) {
            return http.Response(
              jsonEncode({
                'files': [
                  {'id': 'mms-folder-id'},
                ],
              }),
              200,
            );
          }
          if (q.contains('mms_backup_id')) {
            final match = RegExp(r"value\s*=\s*'([^']+)'").firstMatch(q);
            final targetBackupId = match?.group(1);
            final filtered = meta.values
                .where((m) =>
                    (m['appProperties'] as Map?)?['mms_backup_id'] == targetBackupId)
                .toList();
            return http.Response(jsonEncode({'files': filtered}), 200);
          }
          return http.Response(
            jsonEncode({'files': meta.values.toList()}),
            200,
          );
        }

        if (req.method == 'DELETE' && req.url.path.startsWith('/drive/v3/files/')) {
          final fileId = req.url.pathSegments.last;
          files.remove(fileId);
          meta.remove(fileId);
          return http.Response('', 204);
        }

        if (req.method == 'POST' && req.url.path == '/upload/drive/v3/files') {
          final initMeta = jsonDecode(req.body) as Map<String, dynamic>;
          final sessionId = 'sess_${++_seq}';
          uploadSessions[sessionId] = jsonEncode(initMeta);
          return http.Response(
            '',
            200,
            headers: {
              'location': 'https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&session=$sessionId',
            },
          );
        }

        if (req.method == 'PUT' && req.url.path == '/upload/drive/v3/files') {
          final sessionId = req.url.queryParameters['session']!;
          final initMeta = jsonDecode(uploadSessions[sessionId]!) as Map<String, dynamic>;
          final fileId = 'drive_file_${++_seq}';
          final bytes = Uint8List.fromList(req.bodyBytes);
          final checksumMd5 = md5.convert(bytes).toString();
          files[fileId] = bytes;
          meta[fileId] = {
            'id': fileId,
            'name': initMeta['name'],
            'size': bytes.length.toString(),
            'md5Checksum': checksumMd5,
            'createdTime': DateTime.now().toUtc().toIso8601String(),
            'appProperties': initMeta['appProperties'],
          };
          return http.Response(
            jsonEncode({
              'id': fileId,
              'name': initMeta['name'],
              'size': bytes.length.toString(),
              'md5Checksum': checksumMd5,
            }),
            200,
          );
        }

        if (req.method == 'GET' &&
            req.url.path.startsWith('/drive/v3/files/') &&
            req.url.queryParameters['alt'] == 'media') {
          final fileId = req.url.pathSegments.last;
          final bytes = files[fileId];
          if (bytes == null) return http.Response('Not Found', 404);
          return http.Response.bytes(bytes, 200);
        }

        return http.Response('Not Found', 404);
      });
}

class _FixedDriveToken implements DriveAccessTokenProvider {
  @override
  Future<String> accessToken({bool forceRefresh = false}) async => 'ya29.fake';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const setup = AppSetupConfig(
    isSetupCompleted: true,
    tenantId: 'tenant-drive-1',
    storeId: 'store-drive-1',
    storeName: 'Drive Şube',
    deviceId: 'dev-drive-01',
    deviceName: 'Kasa 1',
  );

  group('Faz C — Google Drive Upload / List / Controlled Download & Restore', () {
    test('Drive upload -> list -> DB değişimi -> wrong password rejection -> controlled restore (Outbox + pauseSync + safety)',
        () async {
      final tempDir = Directory.systemTemp.createTempSync('mms_drive_int_');
      final dbPath = p.join(tempDir.path, 'client_local.db');
      final dbService = await LocalDatabaseService.initialize(customPath: dbPath);

      var syncPausedCount = 0;
      var syncResumedCount = 0;
      final backupRootDir = Directory(p.join(tempDir.path, 'backups'));
      final backupService = ClientBackupService(
        dbService: dbService,
        backupRootDir: backupRootDir,
        readSetupConfig: () => setup,
        kdfIterations: 1000,
        databaseTypeOverride: DatabaseType.clientLocal,
        pauseSync: () async => syncPausedCount++,
        resumeSync: () => syncResumedCount++,
      );

      final fakeDrive = _FakeDriveServer();
      final httpClient = fakeDrive.createClient();
      final uploader = GoogleDriveBackupUploader(
        tokenProvider: _FixedDriveToken(),
        httpClient: httpClient,
        ledger: DriveUploadLedger(File(p.join(tempDir.path, 'drive_ledger.json'))),
        baseDelay: Duration.zero,
      );

      addTearDown(() async {
        httpClient.close();
        await LocalDatabaseService.closeActive();
        LocalDatabaseService.resetForTesting();
        if (tempDir.existsSync()) {
          try {
            tempDir.deleteSync(recursive: true);
          } catch (_) {}
        }
      });

      // 1. Ürün oluştur ve şifreli yedek alıp Drive'a yükle
      await dbService.repository.upsertProducts([
        LocalProductsCompanion(
          id: const Value('p-1'),
          barcode: const Value('8691111111111'),
          name: const Value('Eski Süt'),
          price: const Value(2500),
          stock: const Value(10000),
          updatedAt: Value(DateTime.utc(2026, 11, 21, 10, 0)),
        ),
      ]);
      const password = 'DriveBackupPassword2026!';
      final created = await backupService.createEncryptedBackup(password: password);
      final localInfo = (await backupService.listBackups()).single;
      await uploader.upload(backupFile: localInfo.file, manifest: localInfo.manifest);

      // 2. Yerel veritabanına yedek sonrası bir satış (bekleyen Outbox) ve ürün değişimi ekle
      await dbService.repository.upsertProducts([
        LocalProductsCompanion(
          id: const Value('p-new'),
          barcode: const Value('8692222222222'),
          name: const Value('Yedek Sonrası Eklenen Ürün'),
          price: const Value(5000),
          stock: const Value(5000),
          updatedAt: Value(DateTime.utc(2026, 11, 21, 11, 0)),
        ),
      ]);
      await dbService.repository.createOfflineSale(
        deviceId: setup.deviceId,
        paymentMethod: 'CASH',
        items: [
          CartItemInput.units('p-1', 1),
        ],
      );
      final preRestoreOutbox = await dbService.repository.getUnsyncedOutboxOperations(setup.deviceId);
      expect(preRestoreOutbox, hasLength(1));

      // Yerel yedek dosyasını sil ki gerçekten Drive'dan indirilip geri yüklendiği kanıtlansın
      await backupService.deleteBackup(created.backupId);
      expect(await backupService.listBackups(), isEmpty);

      // 3. Uzaktan yedek listeleme
      final remotes = await backupService.listGoogleDriveBackups(uploader: uploader);
      expect(remotes, hasLength(1));
      expect(remotes.first.backupId, created.backupId);

      // 4. Yanlış parola ile geri yükleme kilide veya canlı DB durdurmaya GEÇMEDEN reddedilir
      await expectLater(
        () => backupService.downloadAndRestoreFromGoogleDrive(
          uploader: uploader,
          remote: remotes.first,
          password: 'WrongPassword!',
        ),
        throwsA(isA<BackupException>().having((e) => e.code, 'code', 'ERR_DECRYPTION_FAILED')),
      );
      expect(syncPausedCount, 0);
      expect(await dbService.repository.getProductById('p-new'), isNotNull);

      // 5. Doğru parola ile geri yükleme: safety snapshot + pause/resume + Outbox korunması
      final restored = await backupService.downloadAndRestoreFromGoogleDrive(
        uploader: uploader,
        remote: remotes.first,
        password: password,
      );
      expect(restored.backupId, created.backupId);
      expect(syncPausedCount, 1);
      expect(syncResumedCount, 1);
      expect(File(restored.safetyBackupPath).existsSync(), isTrue);

      // Ürünler yedek anına döner ama Hub'a gitmemiş Outbox işlemi korunur!
      expect(await dbService.repository.getProductById('p-1'), isNotNull);
      expect(await dbService.repository.getProductById('p-new'), isNull);
      final postRestoreOutbox = await dbService.repository.getUnsyncedOutboxOperations(setup.deviceId);
      expect(postRestoreOutbox, hasLength(1));
      expect(postRestoreOutbox.first.operationId, preRestoreOutbox.first.operationId);
    });

    test('tampered Drive indirilen dosyasında canlı DB durdurulmaz ve sahte/bozuk dosya reddedilir', () async {
      final tempDir = Directory.systemTemp.createTempSync('mms_drive_tamper_');
      final dbPath = p.join(tempDir.path, 'client_local.db');
      final dbService = await LocalDatabaseService.initialize(customPath: dbPath);

      var paused = 0;
      final backupService = ClientBackupService(
        dbService: dbService,
        backupRootDir: Directory(p.join(tempDir.path, 'backups')),
        readSetupConfig: () => setup,
        kdfIterations: 1000,
        databaseTypeOverride: DatabaseType.clientLocal,
        pauseSync: () async => paused++,
        resumeSync: () {},
      );

      final fakeDrive = _FakeDriveServer();
      final httpClient = fakeDrive.createClient();
      final uploader = GoogleDriveBackupUploader(
        tokenProvider: _FixedDriveToken(),
        httpClient: httpClient,
        ledger: DriveUploadLedger(File(p.join(tempDir.path, 'ledger.json'))),
        baseDelay: Duration.zero,
      );

      addTearDown(() async {
        httpClient.close();
        await LocalDatabaseService.closeActive();
        LocalDatabaseService.resetForTesting();
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      await backupService.createEncryptedBackup(password: 'SecretPass123!');
      final localInfo = (await backupService.listBackups()).single;
      final uploaded = await uploader.upload(backupFile: localInfo.file, manifest: localInfo.manifest);
      await backupService.deleteBackup(localInfo.backupId);

      // Drive sunucusundaki baytları boz -> SHA-256 yakalamalı
      final original = fakeDrive.files[uploaded.driveFileId]!;
      final tampered = Uint8List.fromList(original);
      tampered[tampered.length - 1] ^= 0x01;
      fakeDrive.files[uploaded.driveFileId] = tampered;

      final remotes = await backupService.listGoogleDriveBackups(uploader: uploader);
      await expectLater(
        () => backupService.downloadAndRestoreFromGoogleDrive(
          uploader: uploader,
          remote: remotes.single,
          password: 'SecretPass123!',
        ),
        throwsA(isA<DriveBackupException>()
            .having((e) => e.code, 'code', 'ERR_DRIVE_CHECKSUM_MISMATCH')),
      );
      expect(paused, 0);
    });

    test('GoogleDriveConnectService.disconnect token\'ı iptal edip güvenli depodan siler', () async {
      final store = InMemorySecureTokenStore();
      var revokedCalled = false;
      final httpClient = MockClient((req) async {
        if (req.url.toString() == 'https://oauth2.googleapis.com/revoke') {
          revokedCalled = true;
          return http.Response('', 200);
        }
        return http.Response(jsonEncode({'access_token': 'ya29.x', 'expires_in': 3600}), 200);
      });
      final connect = GoogleDriveConnectService(
        clientId: 'cid',
        secureStore: store,
        httpClient: httpClient,
      );
      final tokenProv = GoogleOAuthRefreshTokenProvider(
        clientId: 'cid',
        readRefreshToken: () => store.readSecret(GoogleDriveConnectService.refreshTokenSecretKey),
        httpClient: httpClient,
      );

      await connect.saveRefreshToken('1//refresh-test');
      expect(await connect.isConnected(), isTrue);

      await connect.disconnect(tokenProvider: tokenProv);
      expect(revokedCalled, isTrue);
      expect(await connect.isConnected(), isFalse);
      expect(
        await store.readSecret(GoogleDriveConnectService.refreshTokenSecretKey),
        isNull,
      );
    });

    testWidgets('ExternalBackupSection bağlı durumda Drive geri yükleme butonunu gösterir', (tester) async {
      await tester.runAsync(() async {
        final tempDir = Directory.systemTemp.createTempSync('mms_drive_widget_');
        final store = InMemorySecureTokenStore();
        await store.saveSecret(GoogleDriveConnectService.refreshTokenSecretKey, '1//refresh-ui');

        final fakeDrive = _FakeDriveServer();
        final httpClient = fakeDrive.createClient();

        final connectService = GoogleDriveConnectService(
          clientId: 'cid-ui',
          secureStore: store,
          httpClient: httpClient,
        );
        final uploader = GoogleDriveBackupUploader(
          tokenProvider: _FixedDriveToken(),
          httpClient: httpClient,
          ledger: DriveUploadLedger(File(p.join(tempDir.path, 'ledger.json'))),
        );
        final dummyDb = LocalDatabaseService.forTesting(
          NativeDatabase.memory(),
          path: p.join(tempDir.path, 'ui.db'),
        );
        final backupService = ClientBackupService(
          dbService: dummyDb,
          backupRootDir: Directory(p.join(tempDir.path, 'backups')),
          readSetupConfig: () => setup,
          databaseTypeOverride: DatabaseType.clientLocal,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              googleDriveConnectServiceProvider.overrideWithValue(connectService),
              googleDriveUploaderProvider.overrideWithValue(uploader),
              clientBackupServiceProvider.overrideWithValue(backupService),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const Scaffold(
                body: SingleChildScrollView(child: ExternalBackupSection()),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.byKey(const Key('gdrive_connect_button')), findsOneWidget);
        expect(find.byKey(const Key('gdrive_list_backups_button')), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await dummyDb.close();
        httpClient.close();
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
    });
  });
}
