import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../lib/backup/hub_backup_oauth_service.dart';
import '../lib/backup/hub_backup_oauth_store.dart';
import 'helpers/test_backup_sandbox.dart';

String _maskCommentsAndStrings(String src) {
  final out = StringBuffer();
  var i = 0;
  var blockCommentDepth = 0;

  void writePreservingNewlines(String text) {
    for (var k = 0; k < text.length; k++) {
      final ch = text.codeUnitAt(k);
      if (ch == 10 || ch == 13) {
        out.writeCharCode(ch);
      } else {
        out.write(' ');
      }
    }
  }

  while (i < src.length) {
    if (blockCommentDepth > 0) {
      if (i + 1 < src.length && src[i] == '/' && src[i + 1] == '*') {
        blockCommentDepth++;
        out.write('  ');
        i += 2;
        continue;
      }
      if (i + 1 < src.length && src[i] == '*' && src[i + 1] == '/') {
        blockCommentDepth--;
        out.write('  ');
        i += 2;
        continue;
      }
      writePreservingNewlines(src[i]);
      i++;
      continue;
    }

    if (i + 1 < src.length && src[i] == '/' && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        writePreservingNewlines(src[i]);
        i++;
      }
      continue;
    }
    if (i + 1 < src.length && src[i] == '/' && src[i + 1] == '*') {
      blockCommentDepth = 1;
      out.write('  ');
      i += 2;
      continue;
    }

    // Raw strings: r'...' / r"..." / r'''...''' / r"""..."""
    final isRaw = (src[i] == 'r') &&
        i + 1 < src.length &&
        (src[i + 1] == '\'' || src[i + 1] == '"');
    final quoteStart = isRaw ? i + 1 : i;
    if (src[quoteStart] == '\'' || src[quoteStart] == '"') {
      final qChar = src[quoteStart];
      final isTriple = quoteStart + 2 < src.length &&
          src[quoteStart + 1] == qChar &&
          src[quoteStart + 2] == qChar;
      final delimLen = isTriple ? 3 : 1;
      writePreservingNewlines(src.substring(i, quoteStart + delimLen));
      i = quoteStart + delimLen;
      while (i < src.length) {
        if (!isRaw && src[i] == r'\' && i + 1 < src.length) {
          writePreservingNewlines(src.substring(i, i + 2));
          i += 2;
          continue;
        }
        if (isTriple) {
          if (i + 2 < src.length &&
              src[i] == qChar &&
              src[i + 1] == qChar &&
              src[i + 2] == qChar) {
            out.write('   ');
            i += 3;
            break;
          }
        } else if (src[i] == qChar) {
          out.write(' ');
          i++;
          break;
        }
        writePreservingNewlines(src[i]);
        i++;
      }
      continue;
    }

    out.write(src[i]);
    i++;
  }
  return out.toString();
}

Directory _findRepoRoot() {
  var cur = Directory.current.absolute;
  while (true) {
    if (File(p.join(cur.path, 'AGENTS.md')).existsSync()) {
      return cur;
    }
    final parent = cur.parent;
    if (parent.path == cur.path) {
      return Directory.current;
    }
    cur = parent;
  }
}

void main() {
  group('AUD-LOW-02: Test Altyapısı İzolasyonu, Cleanup & forceRefresh', () {
    test('1. Tüm test dosyalarındaki her SpikeServer kurulumu açıkça backupDirectory belirtir', () {
      final repoRoot = _findRepoRoot();
      final testDir = Directory(
        p.join(repoRoot.path, 'test_spikes', 'spike_01_backend', 'test'),
      );
      final dartFiles = testDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('_test.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      expect(dartFiles, isNotEmpty);

      final ctorRegex = RegExp(r'\bSpikeServer\s*\(');
      final violations = <String>[];

      for (final file in dartFiles) {
        final raw = file.readAsStringSync();
        final masked = _maskCommentsAndStrings(raw);
        for (final match in ctorRegex.allMatches(masked)) {
          final openParenIdx = masked.indexOf('(', match.start);
          if (openParenIdx < 0) continue;
          var depth = 0;
          var closeParenIdx = -1;
          for (var idx = openParenIdx; idx < masked.length; idx++) {
            final ch = masked[idx];
            if (ch == '(') {
              depth++;
            } else if (ch == ')') {
              depth--;
              if (depth == 0) {
                closeParenIdx = idx;
                break;
              }
            }
          }
          final endIdx = closeParenIdx > openParenIdx ? closeParenIdx : masked.length;
          final argsSlice = masked.substring(openParenIdx + 1, endIdx);
          if (!RegExp(r'\bbackupDirectory\s*:').hasMatch(argsSlice)) {
            final lineNumber = '\n'.allMatches(raw.substring(0, match.start)).length + 1;
            final rel = p.relative(file.path, from: testDir.path);
            violations.add('$rel:$lineNumber');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'backupDirectory olmayan SpikeServer() çağrıları workspace backups/ klasörünü kirletir:\n${violations.join('\n')}',
      );
    });

    test('2. TestBackupSandbox gerçek proje, ProgramData, LocalAppData ve işaretsiz dizinleri reddeder', () {
      final repoRoot = _findRepoRoot();
      final workspaceBackups = Directory(
        p.join(repoRoot.path, 'test_spikes', 'spike_01_backend', 'backups'),
      );
      expect(
        () => TestBackupSandbox.assertSafeTestBackupDirectory(workspaceBackups),
        throwsStateError,
      );
      expect(
        () => TestBackupSandbox.assertSafeTestBackupDirectory(repoRoot),
        throwsStateError,
      );
      expect(
        () => TestBackupSandbox.assertSafeTestBackupDirectory(
          Directory(r'C:\ProgramData\MarketMMS\backups'),
        ),
        throwsStateError,
      );
      expect(
        () => TestBackupSandbox.assertSafeTestBackupDirectory(
          Directory(r'C:\Users\sample\AppData\Local\MarketMMS\backups'),
        ),
        throwsStateError,
      );
      expect(
        () => TestBackupSandbox.assertSafeTestBackupDirectory(Directory.systemTemp),
        throwsStateError,
      );

      final unmarked = Directory.systemTemp.createTempSync('mms_unmarked_probe_');
      try {
        expect(
          () => TestBackupSandbox.assertSafeTestBackupDirectory(unmarked),
          throwsStateError,
        );
      } finally {
        if (unmarked.existsSync()) {
          unmarked.deleteSync(recursive: true);
        }
      }
    });

    test('3. TestBackupSandbox başarı ve exception durumlarında yalnızca kendi dizinini temizler', () {
      final sibling = TestBackupSandbox.createManual(prefix: 'mms_sibling_keep_');
      addTearDown(sibling.dispose);
      final siblingMarkerData = File(p.join(sibling.path, 'keep.txt'))
        ..writeAsStringSync('keep');

      // A) Normal başarı senaryosu cleanup
      final successBox = TestBackupSandbox.createManual(prefix: 'mms_success_clean_');
      final successDirPath = successBox.path;
      File(p.join(successDirPath, 'sample.mmsbak')).writeAsStringSync('pkg');
      expect(Directory(successDirPath).existsSync(), isTrue);
      successBox.dispose();
      expect(Directory(successDirPath).existsSync(), isFalse);
      expect(siblingMarkerData.existsSync(), isTrue);

      // B) Test başarısızlığı / exception fırlatma senaryosu cleanup
      final failureBox = TestBackupSandbox.createManual(prefix: 'mms_fail_clean_');
      final failureDirPath = failureBox.path;
      File(p.join(failureDirPath, 'partial.db')).writeAsStringSync('partial');
      expect(() {
        try {
          throw StateError('Simule edilmis test hatasi');
        } finally {
          failureBox.dispose();
        }
      }, throwsStateError);
      expect(Directory(failureDirPath).existsSync(), isFalse);
      expect(siblingMarkerData.existsSync(), isTrue);
    });

    test('4. Paralel test sandboxları izoledir ve test tekrarlanabilirliği tamdır', () async {
      for (var round = 0; round < 2; round++) {
        final createdPaths = <String>[];
        await Future.wait(
          List.generate(5, (idx) async {
            final box = TestBackupSandbox.createManual(
              prefix: 'mms_parallel_${round}_$idx\_',
            );
            createdPaths.add(box.path);
            try {
              final artifact = File(p.join(box.path, 'hub_backup_same_name.mmsbak'));
              await artifact.writeAsString('round=$round;worker=$idx', flush: true);
              await Future<void>.delayed(Duration(milliseconds: 10 * (5 - idx)));
              expect(
                await artifact.readAsString(),
                equals('round=$round;worker=$idx'),
              );
            } finally {
              box.dispose();
            }
          }),
        );
        expect(createdPaths.toSet().length, equals(5));
        for (final path in createdPaths) {
          expect(Directory(path).existsSync(), isFalse);
        }
      }
    });

    test('5. Backend HubBackupOAuthService ve ResumableDriveUploader forceRefresh=false/true aktarımını doğrular', () async {
      final sandbox = TestBackupSandbox.create(prefix: 'mms_oauth_refresh_');
      final oauthStore = HubBackupOAuthStore(
        File(p.join(sandbox.path, HubBackupOAuthStore.defaultFileName)),
      );

      var refreshEndpointCalls = 0;
      final tokenHistory = <String>[];
      var currentToken = 'ya29.backend-initial-1';
      var rejectPutOnce = true;

      final oauthClient = MockClient((req) async {
        final params = Uri.splitQueryString(req.body);
        if (params['grant_type'] == 'authorization_code') {
          return http.Response(
            jsonEncode({
              'access_token': currentToken,
              'refresh_token': '1//backend-refresh-low02',
              'expires_in': 3600,
              'scope': googleDriveFileScope,
            }),
            200,
          );
        }
        if (params['grant_type'] == 'refresh_token') {
          refreshEndpointCalls++;
          currentToken = 'ya29.backend-refreshed-$refreshEndpointCalls';
          return http.Response(
            jsonEncode({
              'access_token': currentToken,
              'expires_in': 3600,
              'scope': googleDriveFileScope,
            }),
            200,
          );
        }
        return http.Response('unexpected', 400);
      });

      final nowUtc = DateTime.utc(2026, 11, 24, 10, 0);
      final oauthService = HubBackupOAuthService(
        store: oauthStore,
        httpClient: oauthClient,
        clock: () => nowUtc,
      );

      await oauthService.connectWithPkce(
        authCode: 'auth-low02',
        codeVerifier: 'verifier-low02',
        redirectUri: 'http://127.0.0.1:51001/callback',
        clientId: 'cid-low02',
      );

      // forceRefresh=false: geçerli önbellek token'ı döner, HTTP refresh gitmez.
      final tokCached1 = await oauthService.getValidAccessToken(
        clientId: 'cid-low02',
        forceRefresh: false,
      );
      final tokCached2 = await oauthService.getValidAccessToken(
        clientId: 'cid-low02',
        forceRefresh: false,
      );
      expect(tokCached1, equals('ya29.backend-initial-1'));
      expect(tokCached2, equals(tokCached1));
      expect(refreshEndpointCalls, equals(0));

      // Şifreli sentetik paket + HTTP 401 sonrası ResumableDriveUploader -> forceRefresh: true
      final plainFile = File(p.join(sandbox.path, 'snap.db'))
        ..writeAsBytesSync(List<int>.filled(4096, 5));
      final pkgFile = File(p.join(sandbox.path, 'snap.mmsbak'));
      final manifest = await MmsbakV2Crypto.encryptFile(
        inputFile: plainFile,
        outputFile: pkgFile,
        password: 'Low02-Backend-Password-2026!',
        kdfIterations: 1000,
        manifest: BackupManifest(
          backupId: 'bak_low02_backend',
          deviceId: 'hub-1',
          tenantId: 't-1',
          storeId: 's-1',
          databaseType: DatabaseType.centralMaster,
          schemaVersion: 4,
          appVersion: '1.0.0',
          timestamp: nowUtc,
          checksum: '0' * 64,
          unencryptedSizeBytes: 4096,
          encryptedSizeBytes: 0,
          encryptionAlgorithm: MmsbakV2Crypto.algorithmId,
          kdfIterations: 1000,
        ),
      );
      final encBytes = await pkgFile.readAsBytes();
      final encMd5 = md5.convert(encBytes).toString();
      final encSha = sha256.convert(encBytes).toString();

      final uploader = ResumableDriveUploader(
        accessTokenProvider: ({bool forceRefresh = false}) =>
            oauthService.getValidAccessToken(
              clientId: 'cid-low02',
              forceRefresh: forceRefresh,
            ),
        httpClient: MockClient((req) async {
          if (req.method == 'GET' && req.url.path == '/drive/v3/files') {
            final q = req.url.queryParameters['q'] ?? '';
            if (q.contains('application/vnd.google-apps.folder')) {
              return http.Response(
                jsonEncode({
                  'files': [
                    {'id': 'hub-folder-1'},
                  ],
                }),
                200,
              );
            }
            return http.Response(jsonEncode({'files': []}), 200);
          }
          if (req.method == 'POST' && req.url.path == '/upload/drive/v3/files') {
            tokenHistory.add(req.headers['authorization'] ?? '');
            if (rejectPutOnce) {
              rejectPutOnce = false;
              return http.Response('{"error":"expired"}', 401);
            }
            return http.Response(
              '',
              200,
              headers: {
                'location': 'https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&session=s1',
              },
            );
          }
          if (req.method == 'PUT' && req.url.path == '/upload/drive/v3/files') {
            return http.Response(
              jsonEncode({
                'id': 'drv_file_low02',
                'name': 'snap.mmsbak',
                'size': encBytes.length.toString(),
                'md5Checksum': encMd5,
              }),
              200,
            );
          }
          if (req.method == 'GET' && req.url.path == '/drive/v3/files/drv_file_low02') {
            tokenHistory.add(req.headers['authorization'] ?? '');
            return http.Response(
              jsonEncode({
                'id': 'drv_file_low02',
                'size': encBytes.length.toString(),
                'md5Checksum': encMd5,
                'appProperties': {
                  'mms_backup_id': 'bak_low02_backend',
                  'mms_sha256': encSha,
                },
              }),
              200,
            );
          }
          return http.Response('unexpected', 400);
        }),
      );

      final result = await uploader.uploadFile(
        encryptedFile: pkgFile,
        manifest: manifest,
      );
      expect(result.driveFileId, equals('drv_file_low02'));
      expect(refreshEndpointCalls, equals(1));
      expect(tokenHistory.length, equals(3));
      expect(tokenHistory.first, equals('Bearer ya29.backend-initial-1'));
      expect(tokenHistory.last, equals('Bearer ya29.backend-refreshed-1'));
    });
  });
}
