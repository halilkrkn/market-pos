import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Faz 7D — Google Drive şifreli yedek yükleme (TDD; sahte Drive/OAuth uçlarıyla).
/// Gerçek Google hesabı/OAuth istemci kimliği gerektiren doğrulama BLOCKED'dır.
class _FakeTokens implements DriveAccessTokenProvider {
  int calls = 0;
  int forcedRefreshes = 0;
  String token = 'ya29.fake-1';

  @override
  Future<String> accessToken({bool forceRefresh = false}) async {
    calls++;
    if (forceRefresh) {
      forcedRefreshes++;
      token = 'ya29.fake-${forcedRefreshes + 1}';
    }
    return token;
  }
}

class _FakeDrive {
  final List<http.Request> requests = [];
  final Map<String, List<int>> stored = {};
  final List<Map<String, dynamic>> files = [];
  int failUploadsWith = 0; // ardışık 503 sayısı
  bool unauthorizedOnce = false;
  bool corruptMd5 = false;
  bool networkDown = false;

  http.Client client() => MockClient((req) async {
        requests.add(req);
        if (networkDown) throw http.ClientException('Network is unreachable');
        final auth = req.headers['authorization'] ?? '';
        if (!auth.startsWith('Bearer ya29.')) return http.Response('{"error":"unauthenticated"}', 401);
        if (unauthorizedOnce) {
          unauthorizedOnce = false;
          return http.Response('{"error":{"code":401}}', 401);
        }
        final path = req.url.path;
        if (req.method == 'GET' && path == '/drive/v3/files') {
          final q = req.url.queryParameters['q'] ?? '';
          final match = files.where((f) {
            if (q.contains("mimeType = 'application/vnd.google-apps.folder'")) {
              return f['mimeType'] == 'application/vnd.google-apps.folder';
            }
            final id = RegExp(r"value = '([^']+)'").firstMatch(q)?.group(1);
            return (f['appProperties'] as Map?)?['mms_backup_id'] == id;
          }).toList();
          return http.Response(jsonEncode({'files': match}), 200);
        }
        if (req.method == 'POST' && path == '/drive/v3/files') {
          final meta = jsonDecode(req.body) as Map<String, dynamic>;
          final f = {'id': 'folder_${files.length}', ...meta};
          files.add(f);
          return http.Response(jsonEncode(f), 200);
        }
        if (req.method == 'POST' && path == '/upload/drive/v3/files') {
          expect(req.url.queryParameters['uploadType'], 'resumable');
          final meta = jsonDecode(req.body) as Map<String, dynamic>;
          final sessionId = 'sess_${requests.length}';
          files.add({'id': 'pending_$sessionId', ...meta, '_session': sessionId});
          return http.Response('', 200, headers: {'location': 'https://www.googleapis.com/upload/drive/v3/files?upload_id=$sessionId'});
        }
        if (req.method == 'PUT' && path == '/upload/drive/v3/files') {
          if (failUploadsWith > 0) {
            failUploadsWith--;
            return http.Response('{"error":"backendError"}', 503);
          }
          final sessionId = req.url.queryParameters['upload_id'];
          final f = files.firstWhere((x) => x['_session'] == sessionId);
          final id = 'file_${sessionId!}';
          f['id'] = id;
          stored[id] = req.bodyBytes;
          return http.Response(
            jsonEncode({
              'id': id,
              'name': f['name'],
              'size': '${req.bodyBytes.length}',
              'md5Checksum': corruptMd5 ? '0' * 32 : md5.convert(req.bodyBytes).toString(),
            }),
            200,
          );
        }
        if (req.method == 'DELETE' && path.startsWith('/drive/v3/files/')) {
          final id = path.split('/').last;
          files.removeWhere((f) => f['id'] == id);
          stored.remove(id);
          return http.Response('', 204);
        }
        return http.Response('not found ${req.method} $path', 404);
      });
}

Uint8List _package(BackupManifest manifest, int size) => BackupCryptoService.encryptPackage(
      databaseBytes: Uint8List.fromList(List<int>.generate(size, (i) => (i * 7) % 256)),
      password: 'Drive_Test_Password_2026!',
      manifest: manifest,
    );

void main() {
  late Directory tempDir;
  late File backupFile;
  late BackupManifest manifest;
  late _FakeDrive drive;
  late _FakeTokens tokens;
  late List<Duration> delays;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mms_gdrive_');
    manifest = BackupManifest(
      backupId: 'b1',
      deviceId: 'DEV1',
      tenantId: 't',
      storeId: 's',
      databaseType: DatabaseType.clientLocal,
      schemaVersion: 4,
      appVersion: 'test',
      timestamp: DateTime.utc(2026, 11, 21),
      checksum: 'c' * 64,
      unencryptedSizeBytes: 1,
      encryptedSizeBytes: 1,
      kdfIterations: 1000,
    );
    // Gerçek şifreli .mmsbak paketi (uploader yalnızca şifreli paket kabul eder).
    backupFile = File(p.join(tempDir.path, 'backup_CLIENT_LOCAL_DEV1_x_b1.mmsbak'))
      ..writeAsBytesSync(_package(manifest, 4096));
    drive = _FakeDrive();
    tokens = _FakeTokens();
    delays = [];
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  GoogleDriveBackupUploader uploader({int maxAttempts = 4}) => GoogleDriveBackupUploader(
        tokenProvider: tokens,
        httpClient: drive.client(),
        ledger: DriveUploadLedger(File(p.join(tempDir.path, 'drive_upload_ledger.json'))),
        maxAttempts: maxAttempts,
        delay: (d) async => delays.add(d),
      );

  group('GoogleDriveBackupUploader', () {
    test('1. Şifreli paket yüklenir; yalnızca uygulama klasörüne, kimlik etiketleriyle; boyut+MD5 doğrulanır; kayıt tutulur', () async {
      final rec = await uploader().upload(backupFile: backupFile, manifest: manifest);

      expect(rec.skipped, isFalse);
      expect(drive.stored[rec.driveFileId], backupFile.readAsBytesSync());
      final uploaded = drive.files.firstWhere((f) => f['id'] == rec.driveFileId);
      expect((uploaded['appProperties'] as Map)['mms_backup_id'], 'b1');
      expect((uploaded['appProperties'] as Map)['mms_sha256'], sha256.convert(backupFile.readAsBytesSync()).toString());
      expect(uploaded['parents'], isNotEmpty, reason: 'MMS yedek klasörüne yüklenmeli');

      final ledger = await DriveUploadLedger(File(p.join(tempDir.path, 'drive_upload_ledger.json'))).load();
      expect(ledger.entries['b1']!.driveFileId, rec.driveFileId);
      expect(ledger.lastSuccessAt, isNotNull);
    });

    test('2. Aynı yedek ikinci kez yüklenmez (yerel kayıt)', () async {
      final u = uploader();
      await u.upload(backupFile: backupFile, manifest: manifest);
      final before = drive.requests.where((r) => r.method == 'PUT').length;
      final again = await u.upload(backupFile: backupFile, manifest: manifest);
      expect(again.skipped, isTrue);
      expect(drive.requests.where((r) => r.method == 'PUT').length, before);
    });

    test('3. Yerel kayıt kaybolsa da Drive\'daki etiket sayesinde tekrar yüklenmez', () async {
      drive.files.add({
        'id': 'existing_1',
        'name': 'x.mmsbak',
        'appProperties': {'mms_backup_id': 'b1'},
      });
      final rec = await uploader().upload(backupFile: backupFile, manifest: manifest);
      expect(rec.skipped, isTrue);
      expect(rec.driveFileId, 'existing_1');
      expect(drive.requests.where((r) => r.method == 'PUT'), isEmpty);
    });

    test('4. 401 alınca token bir kez yenilenir ve işlem tamamlanır', () async {
      drive.unauthorizedOnce = true;
      final rec = await uploader().upload(backupFile: backupFile, manifest: manifest);
      expect(rec.skipped, isFalse);
      expect(tokens.forcedRefreshes, 1);
    });

    test('5. Geçici Drive hatası (503) üstel bekleme ile yeniden denenir', () async {
      drive.failUploadsWith = 2;
      final rec = await uploader().upload(backupFile: backupFile, manifest: manifest);
      expect(rec.skipped, isFalse);
      expect(delays, hasLength(2));
      expect(delays[1], greaterThan(delays[0]));
    });

    test('6. Bağlantı yoksa ERR_DRIVE_UNAVAILABLE; yerel yedek dosyasına dokunulmaz; hata kaydedilir', () async {
      drive.networkDown = true;
      final bytesBefore = backupFile.readAsBytesSync();
      await expectLater(
        uploader(maxAttempts: 3).upload(backupFile: backupFile, manifest: manifest),
        throwsA(isA<DriveBackupException>().having((e) => e.code, 'code', 'ERR_DRIVE_UNAVAILABLE')),
      );
      expect(backupFile.readAsBytesSync(), bytesBefore);
      final ledger = await DriveUploadLedger(File(p.join(tempDir.path, 'drive_upload_ledger.json'))).load();
      expect(ledger.entries, isEmpty);
      expect(ledger.lastErrorCode, 'ERR_DRIVE_UNAVAILABLE');
    });

    test('7. Yükleme sonrası MD5 uyuşmazsa uzak dosya silinir ve ERR_DRIVE_VERIFY_FAILED', () async {
      drive.corruptMd5 = true;
      await expectLater(
        uploader().upload(backupFile: backupFile, manifest: manifest),
        throwsA(isA<DriveBackupException>().having((e) => e.code, 'code', 'ERR_DRIVE_VERIFY_FAILED')),
      );
      expect(drive.requests.where((r) => r.method == 'DELETE'), hasLength(1));
      expect(drive.stored, isEmpty);
    });

    test('8. uploadPending yalnızca Drive\'a henüz gitmemiş yerel yedekleri yükler (gecikmiş yükleme kuyruğu)', () async {
      final m2 = BackupManifest.fromJson({...manifest.toJson(), 'backup_id': 'b2'});
      final second = File(p.join(tempDir.path, 'backup_CLIENT_LOCAL_DEV1_y_b2.mmsbak'))..writeAsBytesSync(_package(m2, 64));
      final u = uploader();
      await u.upload(backupFile: backupFile, manifest: manifest);

      final results = await u.uploadPending([
        (file: backupFile, manifest: manifest),
        (file: second, manifest: m2),
      ]);
      expect(results.where((r) => !r.skipped).map((r) => r.backupId), ['b2']);
    });

    test('8b. Şifresiz dosya (ör. SQLite güvenlik kopyası) Drive\'a ASLA gönderilmez; ağ isteği yapılmaz', () async {
      final plain = File(p.join(tempDir.path, 'safety_snapshot_CLIENT_LOCAL.db'))
        ..writeAsBytesSync([...utf8.encode('SQLite format 3'), 0, ...List<int>.filled(4080, 1)]);
      await expectLater(
        uploader().upload(backupFile: plain, manifest: manifest),
        throwsA(isA<DriveBackupException>().having((e) => e.code, 'code', 'ERR_DRIVE_NOT_ENCRYPTED_PACKAGE')),
      );
      expect(drive.requests, isEmpty);
    });

    test('8c. Dosyadaki manifest verilen yedekle eşleşmezse (yanlış dosya) yükleme reddedilir', () async {
      final other = BackupManifest.fromJson({...manifest.toJson(), 'backup_id': 'baska'});
      final wrong = File(p.join(tempDir.path, 'backup_wrong.mmsbak'))..writeAsBytesSync(_package(other, 128));
      await expectLater(
        uploader().upload(backupFile: wrong, manifest: manifest),
        throwsA(isA<DriveBackupException>().having((e) => e.code, 'code', 'ERR_DRIVE_NOT_ENCRYPTED_PACKAGE')),
      );
      expect(drive.requests, isEmpty);
    });
  });

  group('Google OAuth', () {
    test('9. Yetkilendirme adresi yalnızca drive.file izni ister, PKCE (S256) ve offline erişim kullanır', () {
      final flow = GoogleOAuthDesktopFlow(clientId: 'cid.apps.googleusercontent.com', httpClient: MockClient((_) async => http.Response('', 500)));
      final session = flow.begin(redirectUri: 'http://127.0.0.1:53682/');
      final uri = session.authorizationUri;
      expect(uri.host, 'accounts.google.com');
      expect(uri.queryParameters['scope'], 'https://www.googleapis.com/auth/drive.file');
      expect(uri.queryParameters['code_challenge_method'], 'S256');
      expect(uri.queryParameters['code_challenge'], isNot(session.codeVerifier));
      expect(uri.queryParameters['access_type'], 'offline');
      expect(uri.queryParameters['state'], session.state);
      expect(session.codeVerifier.length, greaterThanOrEqualTo(43));
    });

    test('10. Geri dönüşte state uyuşmazsa (CSRF) kod kabul edilmez; doğru state ile kod değiştirilir', () async {
      late Map<String, String> posted;
      final flow = GoogleOAuthDesktopFlow(
        clientId: 'cid',
        httpClient: MockClient((req) async {
          posted = req.bodyFields;
          return http.Response(jsonEncode({'access_token': 'ya29.a', 'expires_in': 3600, 'refresh_token': '1//r'}), 200);
        }),
      );
      final session = flow.begin(redirectUri: 'http://127.0.0.1:53682/');
      await expectLater(
        flow.complete(session, Uri.parse('http://127.0.0.1:53682/?code=abc&state=sahte')),
        throwsA(isA<DriveBackupException>().having((e) => e.code, 'code', 'ERR_OAUTH_STATE_MISMATCH')),
      );
      final tokensOut = await flow.complete(session, Uri.parse('http://127.0.0.1:53682/?code=abc&state=${session.state}'));
      expect(tokensOut.refreshToken, '1//r');
      expect(posted['code_verifier'], session.codeVerifier);
      expect(posted['grant_type'], 'authorization_code');
    });

    test('11. Refresh token: erişim token\'ı süresi dolana kadar önbellekten verilir; iptal edilmişse yeniden yetki istenir', () async {
      var tokenCalls = 0;
      var revoked = false;
      final provider = GoogleOAuthRefreshTokenProvider(
        clientId: 'cid',
        readRefreshToken: () async => '1//r',
        httpClient: MockClient((req) async {
          tokenCalls++;
          if (revoked) return http.Response(jsonEncode({'error': 'invalid_grant'}), 400);
          return http.Response(jsonEncode({'access_token': 'ya29.t$tokenCalls', 'expires_in': 3600}), 200);
        }),
      );
      expect(await provider.accessToken(), 'ya29.t1');
      expect(await provider.accessToken(), 'ya29.t1');
      expect(tokenCalls, 1);

      revoked = true;
      await expectLater(
        provider.accessToken(forceRefresh: true),
        throwsA(isA<DriveBackupException>().having((e) => e.code, 'code', 'ERR_DRIVE_REAUTH_REQUIRED')),
      );
    });

    test('12. listRemoteBackups sayfalama (nextPageToken), filtreleme ve tarih azalan sıralama yapar', () async {
      final tmp = Directory.systemTemp.createTempSync('mms_drive_list_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final uploader = GoogleDriveBackupUploader(
        tokenProvider: _FakeTokens(),
        ledger: DriveUploadLedger(File(p.join(tmp.path, 'ledger.json'))),
        baseDelay: Duration.zero,
        httpClient: MockClient((req) async {
          if (req.url.path == '/drive/v3/files' &&
              (req.url.queryParameters['q'] ?? '').contains('application/vnd.google-apps.folder')) {
            return http.Response(
              jsonEncode({
                'files': [
                  {'id': 'folder-1'},
                ],
              }),
              200,
            );
          }
          final page = req.url.queryParameters['pageToken'];
          if (page == null) {
            return http.Response(
              jsonEncode({
                'nextPageToken': 'page-2',
                'files': [
                  {
                    'id': 'f-old',
                    'name': 'backup_CLIENT_LOCAL_dev1_old.mmsbak',
                    'size': '1024',
                    'createdTime': '2026-11-20T08:00:00Z',
                    'appProperties': {
                      'mms_backup_id': 'b-old',
                      'mms_device_id': 'dev-1',
                      'mms_tenant_id': 't-1',
                      'mms_store_id': 's-1',
                      'mms_database_type': 'CLIENT_LOCAL',
                    },
                  },
                  {
                    'id': 'f-ignored',
                    'name': 'notes.txt',
                    'size': '12',
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'files': [
                {
                  'id': 'f-new',
                  'name': 'backup_CLIENT_LOCAL_dev1_new.mmsbak',
                  'size': '2048',
                  'createdTime': '2026-11-21T09:00:00Z',
                  'appProperties': {
                    'mms_backup_id': 'b-new',
                    'mms_device_id': 'dev-1',
                    'mms_tenant_id': 't-1',
                    'mms_store_id': 's-1',
                    'mms_database_type': 'CLIENT_LOCAL',
                  },
                },
                {
                  'id': 'f-other-tenant',
                  'name': 'backup_CLIENT_LOCAL_dev9_other.mmsbak',
                  'size': '512',
                  'createdTime': '2026-11-21T10:00:00Z',
                  'appProperties': {
                    'mms_backup_id': 'b-other',
                    'mms_device_id': 'dev-9',
                    'mms_tenant_id': 't-2',
                    'mms_store_id': 's-1',
                    'mms_database_type': 'CLIENT_LOCAL',
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final listed = await uploader.listRemoteBackups(
        tenantId: 't-1',
        storeId: 's-1',
        deviceId: 'dev-1',
      );
      expect(listed.map((e) => e.backupId).toList(), ['b-new', 'b-old']);
      expect(listed.first.sizeBytes, 2048);
    });

    test('13. downloadEncryptedBackup yarım .part dosyasını Range ile sürdürür ve SHA-256 + yapıyı doğrular', () async {
      final tmp = Directory.systemTemp.createTempSync('mms_drive_dl_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final pkgBytes = BackupCryptoService.encryptPackage(
        databaseBytes: Uint8List.fromList(utf8.encode('SQLite format 3\x00test_db_payload')),
        password: 'StrongPassword123!',
        manifest: BackupManifest(
          backupId: 'bkp-range-1',
          deviceId: 'dev-1',
          tenantId: 't-1',
          storeId: 's-1',
          databaseType: DatabaseType.clientLocal,
          schemaVersion: 4,
          appVersion: '1.0.0',
          timestamp: DateTime.utc(2026, 11, 21, 10, 0),
          checksum: sha256.convert(utf8.encode('SQLite format 3\x00test_db_payload')).toString(),
          unencryptedSizeBytes: 31,
          encryptedSizeBytes: 0,
          kdfIterations: 1000,
        ),
      );
      final expectedSha = sha256.convert(pkgBytes).toString();
      const splitOffset = 24;
      final outDir = Directory(p.join(tmp.path, 'dl'))..createSync();
      const fileName = 'backup_CLIENT_LOCAL_dev1_bkp-range-1.mmsbak';
      await File(p.join(outDir.path, '$fileName.part'))
          .writeAsBytes(pkgBytes.sublist(0, splitOffset), flush: true);

      String? capturedRange;
      final uploader = GoogleDriveBackupUploader(
        tokenProvider: _FakeTokens(),
        ledger: DriveUploadLedger(File(p.join(tmp.path, 'ledger.json'))),
        baseDelay: Duration.zero,
        httpClient: MockClient((req) async {
          capturedRange = req.headers['Range'];
          expect(capturedRange, 'bytes=$splitOffset-');
          return http.Response.bytes(pkgBytes.sublist(splitOffset), 206);
        }),
      );

      final downloaded = await uploader.downloadEncryptedBackup(
        remote: DriveRemoteBackupInfo(
          fileId: 'drive-id-1',
          fileName: fileName,
          sizeBytes: pkgBytes.length,
          backupId: 'bkp-range-1',
          sha256Checksum: expectedSha,
        ),
        targetDir: outDir,
      );

      expect(await downloaded.exists(), isTrue);
      expect(await File('${downloaded.path}.part').exists(), isFalse);
      expect(await downloaded.readAsBytes(), pkgBytes);
    });

    test('14. downloadEncryptedBackup bozuk/checksum uyuşmayan indirmede .part dosyasını siler', () async {
      final tmp = Directory.systemTemp.createTempSync('mms_drive_bad_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final pkgBytes = BackupCryptoService.encryptPackage(
        databaseBytes: Uint8List.fromList(utf8.encode('SQLite format 3\x00payload')),
        password: 'StrongPassword123!',
        manifest: BackupManifest(
          backupId: 'bkp-bad-1',
          deviceId: 'dev-1',
          tenantId: 't-1',
          storeId: 's-1',
          databaseType: DatabaseType.clientLocal,
          schemaVersion: 4,
          appVersion: '1.0.0',
          timestamp: DateTime.utc(2026, 11, 21, 10, 0),
          checksum: sha256.convert(utf8.encode('SQLite format 3\x00payload')).toString(),
          unencryptedSizeBytes: 23,
          encryptedSizeBytes: 0,
          kdfIterations: 1000,
        ),
      );
      final tampered = Uint8List.fromList(pkgBytes);
      tampered[tampered.length - 5] ^= 0xff;
      final expectedSha = sha256.convert(pkgBytes).toString();
      final outDir = Directory(p.join(tmp.path, 'dl'))..createSync();
      const fileName = 'backup_CLIENT_LOCAL_dev1_bkp-bad-1.mmsbak';

      final uploader = GoogleDriveBackupUploader(
        tokenProvider: _FakeTokens(),
        ledger: DriveUploadLedger(File(p.join(tmp.path, 'ledger.json'))),
        baseDelay: Duration.zero,
        httpClient: MockClient((_) async => http.Response.bytes(tampered, 200)),
      );

      await expectLater(
        () => uploader.downloadEncryptedBackup(
          remote: DriveRemoteBackupInfo(
            fileId: 'drive-bad-1',
            fileName: fileName,
            sizeBytes: pkgBytes.length,
            backupId: 'bkp-bad-1',
            sha256Checksum: expectedSha,
          ),
          targetDir: outDir,
        ),
        throwsA(isA<DriveBackupException>()
            .having((e) => e.code, 'code', 'ERR_DRIVE_CHECKSUM_MISMATCH')),
      );
      expect(outDir.listSync(), isEmpty);
    });

    test('15. revokeToken önbelleği sıfırlar ve Google revoke endpoint çağrısı yapar', () async {
      Uri? revokedUri;
      String? revokedBody;
      final client = MockClient((req) async {
        if (req.url.path == '/revoke') {
          revokedUri = req.url;
          revokedBody = req.body;
          return http.Response('', 200);
        }
        return http.Response(jsonEncode({'access_token': 'ya29.live', 'expires_in': 3600}), 200);
      });
      final provider = GoogleOAuthRefreshTokenProvider(
        clientId: 'cid',
        readRefreshToken: () async => '1//refresh-secret',
        httpClient: client,
      );

      expect(await provider.accessToken(), 'ya29.live');
      final ok = await provider.revokeToken();
      expect(ok, isTrue);
      expect(revokedUri.toString(), 'https://oauth2.googleapis.com/revoke');
      expect(revokedBody, contains('token='));
    });
  });
}
