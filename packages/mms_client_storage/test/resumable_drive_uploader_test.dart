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
    tempDir = Directory.systemTemp.createTempSync('mms_test_only_b2_up_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<({File file, BackupManifest manifest, String shaHex, String md5Hex})>
      createSampleEncryptedFile({
    required String backupId,
    required int rawSizeBytes,
  }) async {
    final plain = File(p.join(tempDir.path, 'src_$backupId.db'));
    await plain.writeAsBytes(
      Uint8List.fromList(List<int>.generate(rawSizeBytes, (i) => (i * 13) & 0xff)),
      flush: true,
    );
    final enc = File(p.join(tempDir.path, 'hub_backup_$backupId.mmsbak'));
    final baseManifest = BackupManifest(
      backupId: backupId,
      deviceId: 'HUB-WIN-01',
      tenantId: 'tenant_pilot',
      storeId: 'store_01',
      databaseType: DatabaseType.centralMaster,
      schemaVersion: 4,
      appVersion: '1.0.0',
      timestamp: DateTime.utc(2026, 11, 22, 12, 0),
      checksum: sha256.convert(const [0]).toString(),
      unencryptedSizeBytes: rawSizeBytes,
      encryptedSizeBytes: 0,
    );
    final man = await MmsbakV2Crypto.encryptFile(
      inputFile: plain,
      outputFile: enc,
      password: 'ResumableUpload-Pass-2026!',
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

  group('Faz B-2: ResumableDriveUploader (HTTP 308, 404/410, 403 Quota vs Auth, VERIFYING)', () {
    test('BK-011: 256KiB-hizalı çok parçalı akış, yarıda kesinti sonrası HTTP 308 devam etme ve VERIFYING doğrulaması', () async {
      const chunk = 256 * 1024;
      final pkg = await createSampleEncryptedFile(
        backupId: 'bak_308_011',
        rawSizeBytes: (256 * 1024) + 12000,
      );
      final totalLen = await pkg.file.length();
      var receivedBytes = 0;
      var sessionCount = 0;
      var dropFirstSecondChunk = true;

      final mockClient = MockClient((req) async {
        final uri = req.url.toString();
        if (req.method == 'GET' && uri.contains('files?')) {
          return http.Response(jsonEncode({'files': [{'id': 'folder_mms_1'}]}), 200);
        }
        if (req.method == 'POST' && uri.contains('uploadType=resumable')) {
          sessionCount++;
          return http.Response(
            '',
            200,
            headers: {'location': 'https://upload.example.com/session_$sessionCount'},
          );
        }
        if (req.method == 'PUT' && uri.startsWith('https://upload.example.com/session_')) {
          final contentRange = req.headers['content-range'] ?? '';
          if (contentRange.startsWith('bytes */')) {
            if (receivedBytes == 0) {
              return http.Response('', 308);
            }
            return http.Response(
              '',
              308,
              headers: {'range': 'bytes=0-${receivedBytes - 1}'},
            );
          }

          final m = RegExp(r'bytes (\d+)-(\d+)/(\d+)').firstMatch(contentRange)!;
          final start = int.parse(m.group(1)!);
          final end = int.parse(m.group(2)!);
          expect(start, equals(receivedBytes));
          if (start > 0 && dropFirstSecondChunk) {
            dropFirstSecondChunk = false;
            return http.Response('Service Unavailable', 503);
          }
          receivedBytes = end + 1;
          if (receivedBytes < totalLen) {
            return http.Response(
              '',
              308,
              headers: {'range': 'bytes=0-$end'},
            );
          }
          return http.Response(jsonEncode({'id': 'drive_file_011'}), 200);
        }
        if (req.method == 'GET' && uri.contains('/drive/v3/files/drive_file_011')) {
          return http.Response(
            jsonEncode({
              'id': 'drive_file_011',
              'size': totalLen.toString(),
              'md5Checksum': pkg.md5Hex,
              'appProperties': {
                'mms_backup_id': 'bak_308_011',
                'mms_sha256': pkg.shaHex,
              },
            }),
            200,
          );
        }
        return http.Response('Unexpected: ${req.method} $uri', 400);
      });

      final uploader = ResumableDriveUploader(
        accessTokenProvider: ({bool forceRefresh = false}) async => 'access_tok_1',
        httpClient: mockClient,
        chunkSizeBytes: chunk,
      );

      String? persistedSession;
      int persistedOffset = 0;

      // İlk deneme ikinci parçada geçici 503 alıp progress kaydetmeli
      await expectLater(
        () => uploader.uploadFile(
          encryptedFile: pkg.file,
          manifest: pkg.manifest,
          onSessionProgress: (s, b) {
            persistedSession = s;
            persistedOffset = b;
          },
        ),
        throwsA(
          isA<DriveResumableUploadException>()
              .having((e) => e.kind, 'kind', DriveUploadFailureKind.transient),
        ),
      );
      expect(persistedSession, equals('https://upload.example.com/session_1'));
      expect(persistedOffset, equals(chunk));

      // İkinci deneme HTTP 308 ofsetinden devam edip VERIFYING ile bitirmeli
      var verifyingEntered = false;
      final result = await uploader.uploadFile(
        encryptedFile: pkg.file,
        manifest: pkg.manifest,
        existingSessionUri: persistedSession,
        existingUploadedBytes: persistedOffset,
        onBeforeVerify: (fid) {
          verifyingEntered = fid == 'drive_file_011';
        },
      );
      expect(verifyingEntered, isTrue);
      expect(result.driveFileId, equals('drive_file_011'));
      expect(result.uploadedBytes, equals(totalLen));
      expect(sessionCount, equals(1)); // Aynı oturumdan devam edildi
    });

    test('BK-012: Süresi dolan oturum (HTTP 404/410) aynı backup_id ile yeni session açarak kurtarılır', () async {
      final pkg = await createSampleEncryptedFile(
        backupId: 'bak_410_012',
        rawSizeBytes: 32768,
      );
      final totalLen = await pkg.file.length();
      var newSessionCreated = false;

      final mockClient = MockClient((req) async {
        final uri = req.url.toString();
        if (req.method == 'GET' && uri.contains('files?')) {
          return http.Response(jsonEncode({'files': [{'id': 'folder_mms_1'}]}), 200);
        }
        if (req.method == 'PUT' && uri.contains('old_expired_session')) {
          return http.Response('Gone', 410);
        }
        if (req.method == 'POST' && uri.contains('uploadType=resumable')) {
          newSessionCreated = true;
          return http.Response(
            '',
            200,
            headers: {'location': 'https://upload.example.com/fresh_session'},
          );
        }
        if (req.method == 'PUT' && uri.contains('fresh_session')) {
          return http.Response(jsonEncode({'id': 'drive_file_012'}), 200);
        }
        if (req.method == 'GET' && uri.contains('/drive/v3/files/drive_file_012')) {
          return http.Response(
            jsonEncode({
              'id': 'drive_file_012',
              'size': totalLen.toString(),
              'md5Checksum': pkg.md5Hex,
              'appProperties': {
                'mms_backup_id': 'bak_410_012',
                'mms_sha256': pkg.shaHex,
              },
            }),
            200,
          );
        }
        return http.Response('Bad req', 400);
      });

      final uploader = ResumableDriveUploader(
        accessTokenProvider: ({bool forceRefresh = false}) async => 'access_tok_2',
        httpClient: mockClient,
      );

      final result = await uploader.uploadFile(
        encryptedFile: pkg.file,
        manifest: pkg.manifest,
        existingSessionUri: 'https://upload.example.com/old_expired_session',
        existingUploadedBytes: 16384,
      );
      expect(newSessionCreated, isTrue);
      expect(result.driveFileId, equals('drive_file_012'));
    });

    test('BK-013: HTTP 403 storageQuotaExceeded (FAILED_QUOTA) vs 401/403 auth (FAILED_AUTH) ve hızlı iptal (<1.5s)', () async {
      final pkg = await createSampleEncryptedFile(
        backupId: 'bak_cls_013',
        rawSizeBytes: 8192,
      );

      final quotaClient = MockClient((req) async {
        if (req.method == 'GET' && req.url.toString().contains('files?')) {
          return http.Response(jsonEncode({'files': [{'id': 'f1'}]}), 200);
        }
        return http.Response(
          jsonEncode({
            'error': {
              'code': 403,
              'errors': [{'reason': 'storageQuotaExceeded'}],
            }
          }),
          403,
        );
      });
      final quotaUploader = ResumableDriveUploader(
        accessTokenProvider: ({bool forceRefresh = false}) async => 'tok',
        httpClient: quotaClient,
      );
      await expectLater(
        () => quotaUploader.uploadFile(encryptedFile: pkg.file, manifest: pkg.manifest),
        throwsA(isA<DriveResumableUploadException>()
            .having((e) => e.kind, 'kind', DriveUploadFailureKind.quotaExceeded)
            .having((e) => e.code, 'code', 'FAILED_QUOTA')),
      );

      final authClient = MockClient((req) async {
        return http.Response(
          jsonEncode({'error': {'code': 403, 'errors': [{'reason': 'insufficientPermissions'}]}}),
          403,
        );
      });
      final authUploader = ResumableDriveUploader(
        accessTokenProvider: ({bool forceRefresh = false}) async => 'tok',
        httpClient: authClient,
      );
      await expectLater(
        () => authUploader.uploadFile(encryptedFile: pkg.file, manifest: pkg.manifest),
        throwsA(isA<DriveResumableUploadException>()
            .having((e) => e.kind, 'kind', DriveUploadFailureKind.authFailure)
            .having((e) => e.code, 'code', 'FAILED_AUTH')),
      );

      // Kooperatif iptal (<1.5s)
      final slowClient = MockClient((req) async {
        await Future<void>.delayed(const Duration(seconds: 10));
        return http.Response('{}', 200);
      });
      final cancelToken = BackupCancellationToken();
      final cancelUploader = ResumableDriveUploader(
        accessTokenProvider: ({bool forceRefresh = false}) async => 'tok',
        httpClient: slowClient,
      );
      Future<void>.delayed(const Duration(milliseconds: 80), cancelToken.cancel);
      final sw = Stopwatch()..start();
      await expectLater(
        () => cancelUploader.uploadFile(
          encryptedFile: pkg.file,
          manifest: pkg.manifest,
          cancellationToken: cancelToken,
        ),
        throwsA(isA<DriveResumableUploadException>()
            .having((e) => e.kind, 'kind', DriveUploadFailureKind.cancelled)),
      );
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(1500));
    });

    test('BK-020: Drive verify aşamasında boyut/hash/backup_id uyuşmazlığında bozuk uzak dosya silinir ve hata döner', () async {
      final pkg = await createSampleEncryptedFile(
        backupId: 'bak_verify_fail_020',
        rawSizeBytes: 8192,
      );
      final deletedFileIds = <String>[];

      final mismatchClient = MockClient((req) async {
        final uri = req.url.toString();
        if (req.method == 'GET' && req.url.path == '/drive/v3/files') {
          return http.Response(jsonEncode({'files': [{'id': 'folder_bk020'}]}), 200);
        }
        if (req.method == 'POST' && uri.contains('uploadType=resumable')) {
          return http.Response('', 200, headers: {
            'location': 'https://upload.example.com/sess_bk020',
          });
        }
        if (req.method == 'PUT' && uri.contains('sess_bk020')) {
          return http.Response(jsonEncode({'id': 'corrupt_file_020'}), 200);
        }
        if (req.method == 'GET' && req.url.path == '/drive/v3/files/corrupt_file_020') {
          return http.Response(
            jsonEncode({
              'id': 'corrupt_file_020',
              'size': '1',
              'md5Checksum': '0000',
              'appProperties': {'mms_backup_id': 'wrong_id', 'mms_sha256': 'deadbeef'},
            }),
            200,
          );
        }
        if (req.method == 'DELETE' && req.url.path == '/drive/v3/files/corrupt_file_020') {
          deletedFileIds.add('corrupt_file_020');
          return http.Response('', 204);
        }
        return http.Response('unexpected ${req.method} $uri', 400);
      });

      final uploader = ResumableDriveUploader(
        accessTokenProvider: ({bool forceRefresh = false}) async => 'tok_bk020',
        httpClient: mismatchClient,
      );

      await expectLater(
        () => uploader.uploadFile(encryptedFile: pkg.file, manifest: pkg.manifest),
        throwsA(isA<DriveResumableUploadException>()
            .having((e) => e.kind, 'kind', DriveUploadFailureKind.integrityVerificationFailed)),
      );
      expect(deletedFileIds, equals(['corrupt_file_020']));
    });
  });
}
