import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mms_test_only_stage2_up_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<({File file, BackupManifest manifest, String shaHex, String md5Hex})>
      createSampleEncryptedFile({
    required String backupId,
    int rawSizeBytes = 16384,
  }) async {
    final plain = File(p.join(tempDir.path, 'src_$backupId.db'));
    await plain.writeAsBytes(
      Uint8List.fromList(List<int>.generate(rawSizeBytes, (i) => (i * 17) & 0xff)),
      flush: true,
    );
    final enc = File(p.join(tempDir.path, 'hub_backup_$backupId.mmsbak'));
    final baseManifest = BackupManifest(
      backupId: backupId,
      deviceId: 'HUB-WIN-STAGE2',
      tenantId: 'tenant_pilot',
      storeId: 'store_01',
      databaseType: DatabaseType.centralMaster,
      schemaVersion: 4,
      appVersion: '1.0.0',
      timestamp: DateTime.utc(2026, 11, 24, 10, 0),
      checksum: sha256.convert(const [0]).toString(),
      unencryptedSizeBytes: rawSizeBytes,
      encryptedSizeBytes: 0,
    );
    final man = await MmsbakV2Crypto.encryptFile(
      inputFile: plain,
      outputFile: enc,
      password: 'Stage2-Recovery-Pass-2026!',
      manifest: baseManifest,
      kdfIterations: 1000,
    );
    final bytes = await enc.readAsBytes();
    return (
      file: enc,
      manifest: man,
      shaHex: sha256.convert(bytes).toString(),
      md5Hex: md5.convert(bytes).toString(),
    );
  }

  group('AUD-HIGH-02: ResumableDriveUploader OAuth Access Token Yenileme', () {
    test('Yükleme sırasında süresi dolan token VERIFYING aşamasında HTTP 401 alınca forceRefresh=true ile yenilenir ve başarılı olur', () async {
      final pkg = await createSampleEncryptedFile(backupId: 'bak_auth_verify_401');
      final totalLen = await pkg.file.length();

      var activeToken = 'expiring_tok_1';
      final forceRefreshCalls = <bool>[];
      var verifyCalls = 0;

      final client = MockClient((req) async {
        final uri = req.url.toString();
        if (req.method == 'GET' && req.url.path == '/drive/v3/files') {
          expect(req.headers['authorization'], equals('Bearer $activeToken'));
          return http.Response(jsonEncode({'files': [{'id': 'folder_s2'}]}), 200);
        }
        if (req.method == 'POST' && uri.contains('uploadType=resumable')) {
          expect(req.headers['authorization'], equals('Bearer $activeToken'));
          return http.Response(
            '',
            200,
            headers: {'location': 'https://upload.example.com/sess_exp_verify'},
          );
        }
        if (req.method == 'PUT' && uri.contains('sess_exp_verify')) {
          // Uzun süren parça yüklemesi sırasında token'ın süresi dolmuş simülasyonu
          activeToken = 'expired_now';
          return http.Response(jsonEncode({'id': 'drv_exp_verify_1'}), 200);
        }
        if (req.method == 'GET' && req.url.path == '/drive/v3/files/drv_exp_verify_1') {
          verifyCalls++;
          if (req.headers['authorization'] != 'Bearer fresh_tok_2') {
            return http.Response(
              jsonEncode({'error': {'code': 401, 'message': 'Invalid Credentials'}}),
              401,
            );
          }
          return http.Response(
            jsonEncode({
              'id': 'drv_exp_verify_1',
              'size': totalLen.toString(),
              'md5Checksum': pkg.md5Hex,
              'appProperties': {
                'mms_backup_id': 'bak_auth_verify_401',
                'mms_sha256': pkg.shaHex,
              },
            }),
            200,
          );
        }
        return http.Response('Unexpected ${req.method} $uri', 400);
      });

      final uploader = ResumableDriveUploader(
        accessTokenProvider: ({bool forceRefresh = false}) async {
          forceRefreshCalls.add(forceRefresh);
          if (forceRefresh) {
            activeToken = 'fresh_tok_2';
            return activeToken;
          }
          return activeToken;
        },
        httpClient: client,
      );

      final result = await uploader.uploadFile(
        encryptedFile: pkg.file,
        manifest: pkg.manifest,
      );
      expect(result.driveFileId, equals('drv_exp_verify_1'));
      expect(forceRefreshCalls, contains(true));
      expect(verifyCalls, greaterThanOrEqualTo(1));
    });

    test('Session init, HTTP 308 probe ve deleteRemoteFile adımlarında HTTP 401 alınırsa forceRefresh=true ile kurtarılır', () async {
      final pkg = await createSampleEncryptedFile(backupId: 'bak_auth_probe_401');
      final totalLen = await pkg.file.length();

      var forceRefreshCount = 0;
      var currentValidToken = 'fresh_after_401';

      final client = MockClient((req) async {
        final auth = req.headers['authorization'];
        final uri = req.url.toString();

        // Resumable chunk PUT Bearer beklemez; tüm Drive API v3 uçları stale token'a 401 döner.
        if (req.method == 'PUT' && uri.contains('sess_resume_401')) {
          final contentRange = req.headers['content-range'] ?? '';
          if (contentRange.startsWith('bytes */')) {
            if (auth != 'Bearer $currentValidToken') {
              return http.Response('Unauthorized', 401);
            }
            return http.Response('', 308);
          }
          return http.Response(jsonEncode({'id': 'drv_probe_401'}), 200);
        }

        if (auth != 'Bearer $currentValidToken') {
          return http.Response('Unauthorized', 401);
        }

        if (req.method == 'GET' && req.url.path == '/drive/v3/files') {
          return http.Response(jsonEncode({'files': [{'id': 'folder_s2'}]}), 200);
        }
        if (req.method == 'GET' && req.url.path == '/drive/v3/files/drv_probe_401') {
          return http.Response(
            jsonEncode({
              'id': 'drv_probe_401',
              'size': totalLen.toString(),
              'md5Checksum': pkg.md5Hex,
              'appProperties': {
                'mms_backup_id': 'bak_auth_probe_401',
                'mms_sha256': pkg.shaHex,
              },
            }),
            200,
          );
        }
        if (req.method == 'DELETE' && req.url.path == '/drive/v3/files/drv_probe_401') {
          return http.Response('', 204);
        }
        return http.Response('Unexpected ${req.method} $uri', 400);
      });

      var provideStale = true;
      final uploader = ResumableDriveUploader(
        accessTokenProvider: ({bool forceRefresh = false}) async {
          if (forceRefresh) {
            forceRefreshCount++;
            provideStale = false;
            return currentValidToken;
          }
          return provideStale ? 'stale_tok' : currentValidToken;
        },
        httpClient: client,
      );

      final result = await uploader.uploadFile(
        encryptedFile: pkg.file,
        manifest: pkg.manifest,
        existingSessionUri: 'https://upload.example.com/sess_resume_401',
      );
      expect(result.driveFileId, equals('drv_probe_401'));
      expect(forceRefreshCount, greaterThanOrEqualTo(1));

      // deleteRemoteFile sırasında yeniden stale dönse bile 401 -> forceRefresh kurtarır
      provideStale = true;
      final beforeDeleteRefresh = forceRefreshCount;
      await uploader.deleteRemoteFile('drv_probe_401');
      expect(forceRefreshCount, greaterThan(beforeDeleteRefresh));
    });

    test('Geçici OAuth token yenileme hatası (SocketException) FAILED_AUTH değil transient (RETRY_PENDING) döner', () async {
      final pkg = await createSampleEncryptedFile(backupId: 'bak_transient_oauth');

      final uploader = ResumableDriveUploader(
        accessTokenProvider: ({bool forceRefresh = false}) async {
          throw const SocketException('Temporary DNS timeout on oauth2.googleapis.com');
        },
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );

      await expectLater(
        () => uploader.uploadFile(encryptedFile: pkg.file, manifest: pkg.manifest),
        throwsA(
          isA<DriveResumableUploadException>()
              .having((e) => e.kind, 'kind', DriveUploadFailureKind.transient)
              .having((e) => e.code, 'code', 'RETRY_PENDING'),
        ),
      );
    });
  });

  group('AUD-MED-03: Probe Eksik ID Koruması ve 404/410 Drive Dosyası Kurtarma', () {
    test('_probeSessionOffset HTTP 200 yanıtında id eksikse TypeError yerine DriveResumableUploadException fırlatır', () async {
      final pkg = await createSampleEncryptedFile(backupId: 'bak_probe_missing_id');

      final client = MockClient((req) async {
        final uri = req.url.toString();
        if (req.method == 'GET' && req.url.path == '/drive/v3/files') {
          // 1. klasör araması, 2. mms_backup_id kurtarma araması
          if ((req.url.queryParameters['q'] ?? '').contains('google-apps.folder')) {
            return http.Response(jsonEncode({'files': [{'id': 'folder_s2'}]}), 200);
          }
          return http.Response(jsonEncode({'files': []}), 200);
        }
        if (req.method == 'PUT' && uri.contains('sess_missing_id')) {
          return http.Response(jsonEncode({'status': 'done_without_id'}), 200);
        }
        return http.Response('Unexpected ${req.method} $uri', 400);
      });

      final uploader = ResumableDriveUploader(
        accessTokenProvider: ({bool forceRefresh = false}) async => 'tok_ok',
        httpClient: client,
      );

      await expectLater(
        () => uploader.uploadFile(
          encryptedFile: pkg.file,
          manifest: pkg.manifest,
          knownFolderId: 'folder_s2',
          existingSessionUri: 'https://upload.example.com/sess_missing_id',
        ),
        throwsA(
          isA<DriveResumableUploadException>()
              .having((e) => e.code, 'code', 'ERR_DRIVE_MISSING_FILE_ID'),
        ),
      );
    });

    test('Oturum süresi dolduğunda (410) Drive üzerinde aynı backup_id ile tamamlanmış geçerli dosya varsa yeni dosya açmaz', () async {
      final pkg = await createSampleEncryptedFile(backupId: 'bak_410_dedup');
      final totalLen = await pkg.file.length();
      var newSessionPostCalls = 0;

      final client = MockClient((req) async {
        final uri = req.url.toString();
        if (req.method == 'PUT' && uri.contains('expired_410_sess')) {
          return http.Response('Gone', 410);
        }
        if (req.method == 'GET' && req.url.path == '/drive/v3/files') {
          final q = req.url.queryParameters['q'] ?? '';
          if (q.contains("mms_backup_id") && q.contains('bak_410_dedup')) {
            return http.Response(
              jsonEncode({
                'files': [
                  {
                    'id': 'drv_already_uploaded_1',
                    'name': p.basename(pkg.file.path),
                    'size': totalLen.toString(),
                    'md5Checksum': pkg.md5Hex,
                    'appProperties': {
                      'mms_backup_id': 'bak_410_dedup',
                      'mms_sha256': pkg.shaHex,
                    },
                  }
                ],
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'files': [{'id': 'folder_s2'}]}), 200);
        }
        if (req.method == 'GET' && req.url.path == '/drive/v3/files/drv_already_uploaded_1') {
          return http.Response(
            jsonEncode({
              'id': 'drv_already_uploaded_1',
              'size': totalLen.toString(),
              'md5Checksum': pkg.md5Hex,
              'appProperties': {
                'mms_backup_id': 'bak_410_dedup',
                'mms_sha256': pkg.shaHex,
              },
            }),
            200,
          );
        }
        if (req.method == 'POST' && uri.contains('uploadType=resumable')) {
          newSessionPostCalls++;
          return http.Response('', 200, headers: {'location': 'https://upload.example.com/dup_sess'});
        }
        return http.Response('Unexpected ${req.method} $uri', 400);
      });

      final uploader = ResumableDriveUploader(
        accessTokenProvider: ({bool forceRefresh = false}) async => 'tok_ok',
        httpClient: client,
      );

      final result = await uploader.uploadFile(
        encryptedFile: pkg.file,
        manifest: pkg.manifest,
        knownFolderId: 'folder_s2',
        existingSessionUri: 'https://upload.example.com/expired_410_sess',
        existingUploadedBytes: totalLen ~/ 2,
      );
      expect(result.driveFileId, equals('drv_already_uploaded_1'));
      expect(
        newSessionPostCalls,
        equals(0),
        reason: 'Drive dosyayı zaten tamamladıysa mükerrer dosya yüklenmemeli.',
      );
    });
  });

  group('AUD-CRIT-03: ResumableDriveUploader Hub Yedek Listeleme ve Doğrulamalı İndirme', () {
    test('listHubBackups yalnızca HUB_CENTRAL .mmsbak dosyalarını listeler; .mmsenv ve mobil yedekleri dışlar, 401de token yeniler', () async {
      var authToken = 'expired_list_tok';
      var refreshed = false;

      final client = MockClient((req) async {
        if (req.headers['authorization'] != 'Bearer valid_list_tok') {
          return http.Response('Unauthorized', 401);
        }
        final q = req.url.queryParameters['q'] ?? '';
        if (q.contains("name = 'MARKET MMS Yedekleri'")) {
          return http.Response(jsonEncode({'files': [{'id': 'root_dir_1'}]}), 200);
        }
        if (q.contains("name = 'Hub'") && q.contains("'root_dir_1' in parents")) {
          return http.Response(jsonEncode({'files': [{'id': 'hub_dir_1'}]}), 200);
        }
        if (q.contains("'hub_dir_1' in parents")) {
          return http.Response(
            jsonEncode({
              'files': [
                {
                  'id': 'drv_hub_1',
                  'name': 'hub_backup_bak_hub_1.mmsbak',
                  'size': '1024',
                  'md5Checksum': 'abc',
                  'createdTime': '2026-11-24T05:00:00Z',
                  'appProperties': {
                    'mms_backup_source': 'HUB_CENTRAL',
                    'mms_backup_id': 'bak_hub_1',
                    'mms_sha256': '1' * 64,
                    'mms_database_type': 'CENTRAL_MASTER',
                    'mms_schema_version': '4',
                    'mms_device_id': 'MMS-HUB-MASTER',
                  },
                },
                {
                  'id': 'drv_env_noise',
                  'name': 'sync_envelope.mmsenv',
                  'size': '256',
                  'appProperties': {'mms_live_sync': 'true'},
                },
                {
                  'id': 'drv_mobile_noise',
                  'name': 'backup_MOBILE_LOCAL_dev1.mmsbak',
                  'size': '512',
                  'appProperties': {'mms_database_type': 'MOBILE_LOCAL'},
                },
              ],
            }),
            200,
          );
        }
        if (q.contains("'root_dir_1' in parents")) {
          return http.Response(
            jsonEncode({
              'files': [
                {
                  'id': 'drv_hub_legacy_root',
                  'name': 'hub_backup_bak_legacy_1.mmsbak',
                  'size': '2048',
                  'createdTime': '2026-11-20T05:00:00Z',
                  'appProperties': {'mms_backup_id': 'bak_legacy_1'},
                },
                {
                  'id': 'drv_client_root',
                  'name': 'backup_CLIENT_LOCAL_win1.mmsbak',
                  'size': '900',
                  'appProperties': {'mms_database_type': 'CLIENT_LOCAL'},
                },
              ],
            }),
            200,
          );
        }
        return http.Response('Unexpected $q', 400);
      });

      final uploader = ResumableDriveUploader(
        accessTokenProvider: ({bool forceRefresh = false}) async {
          if (forceRefresh) {
            refreshed = true;
            authToken = 'valid_list_tok';
          }
          return authToken;
        },
        httpClient: client,
        folderName: MmsDriveBackupFolders.rootFolderName,
        subfolderName: MmsDriveBackupFolders.hubSubfolderName,
      );

      final items = await uploader.listHubBackups();
      expect(refreshed, isTrue);
      expect(items.map((e) => e.driveFileId).toList(),
          equals(['drv_hub_1', 'drv_hub_legacy_root']));
      expect(items.first.backupId, equals('bak_hub_1'));
      expect(items.first.schemaVersion, equals(4));
    });

    test('downloadAndVerifyBackup bozuk boyut, SHA-256 veya geçersiz paket yapısını .part temizleyerek reddeder ve geçerli paketi atomik indirir', () async {
      final pkg = await createSampleEncryptedFile(backupId: 'bak_dl_verify_1');
      final rawBytes = await pkg.file.readAsBytes();
      final downloadDir = Directory(p.join(tempDir.path, 'dl_target'))..createSync();

      var mode = 'bad_size';
      final client = _CallbackStreamClient((req) async {
        if (req.url.path == '/drive/v3/files/drv_dl_1' &&
            req.url.queryParameters['alt'] != 'media') {
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({
              'id': 'drv_dl_1',
              'name': 'hub_backup_bak_dl_verify_1.mmsbak',
              'size': rawBytes.length.toString(),
              'md5Checksum': pkg.md5Hex,
              'createdTime': '2026-11-24T10:00:00Z',
              'appProperties': {
                'mms_backup_source': 'HUB_CENTRAL',
                'mms_backup_id': 'bak_dl_verify_1',
                'mms_sha256': pkg.shaHex,
              },
            }))),
            200,
          );
        }
        if (req.url.path == '/drive/v3/files/drv_dl_1' &&
            req.url.queryParameters['alt'] == 'media') {
          if (mode == 'bad_size') {
            return http.StreamedResponse(
              Stream.value(rawBytes.sublist(0, rawBytes.length - 10)),
              200,
            );
          }
          if (mode == 'bad_sha') {
            final mutated = Uint8List.fromList(rawBytes);
            mutated[mutated.length - 1] ^= 0xff;
            return http.StreamedResponse(Stream.value(mutated), 200);
          }
          if (mode == 'not_mmsbak') {
            return http.StreamedResponse(
              Stream.value(Uint8List.fromList(utf8.encode('plain invalid'))),
              200,
            );
          }
          return http.StreamedResponse(Stream.value(rawBytes), 200);
        }
        return http.StreamedResponse(const Stream.empty(), 404);
      });

      final uploader = ResumableDriveUploader(
        accessTokenProvider: ({bool forceRefresh = false}) async => 'dl_tok_ok',
        httpClient: client,
        folderName: MmsDriveBackupFolders.rootFolderName,
        subfolderName: MmsDriveBackupFolders.hubSubfolderName,
      );

      // 1. Boyut uyuşmazlığı
      await expectLater(
        () => uploader.downloadAndVerifyBackup(
          driveFileId: 'drv_dl_1',
          targetDir: downloadDir,
          expectedBackupId: 'bak_dl_verify_1',
        ),
        throwsA(isA<DriveResumableUploadException>()
            .having((e) => e.kind, 'kind', DriveUploadFailureKind.integrityVerificationFailed)),
      );
      expect(downloadDir.listSync(), isEmpty);

      // 2. SHA-256 uyuşmazlığı
      mode = 'bad_sha';
      await expectLater(
        () => uploader.downloadAndVerifyBackup(
          driveFileId: 'drv_dl_1',
          targetDir: downloadDir,
          expectedBackupId: 'bak_dl_verify_1',
        ),
        throwsA(isA<DriveResumableUploadException>()
            .having((e) => e.kind, 'kind', DriveUploadFailureKind.integrityVerificationFailed)),
      );
      expect(downloadDir.listSync(), isEmpty);

      // 3. Geçersiz driveFileId enjeksiyonu HTTP çağrısı bile yapmadan reddedilir
      await expectLater(
        () => uploader.downloadAndVerifyBackup(
          driveFileId: '../secret',
          targetDir: downloadDir,
        ),
        throwsA(isA<DriveResumableUploadException>()
            .having((e) => e.code, 'code', 'ERR_INVALID_DRIVE_FILE_ID')),
      );

      // 4. Geçerli paket eksiksiz indirilip doğrulanır
      mode = 'valid';
      final downloaded = await uploader.downloadAndVerifyBackup(
        driveFileId: 'drv_dl_1',
        targetDir: downloadDir,
        expectedBackupId: 'bak_dl_verify_1',
        expectedSha256Hex: pkg.shaHex,
        expectedSizeBytes: rawBytes.length,
      );
      expect(await downloaded.file.exists(), isTrue);
      expect(downloaded.sha256Hex, equals(pkg.shaHex));
      expect(downloaded.manifest.backupId, equals('bak_dl_verify_1'));
      expect(File('${downloaded.file.path}.part').existsSync(), isFalse);
    });
  });
}

class _CallbackStreamClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest req) handler;

  _CallbackStreamClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}
