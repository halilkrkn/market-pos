// S5: Merkezi Hub (ADR-023) ve eski istemci (ADR-016/021) Google Drive yedeklerinin ayrımı.
// Gerçek Google Drive'a erişmez; tüm Drive yanıtları MockClient ile taklit edilir.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _FakeTokens implements DriveAccessTokenProvider {
  int calls = 0;
  int forcedRefreshes = 0;
  String _currentToken = 'ya29.test-only-1';

  @override
  Future<String> accessToken({bool forceRefresh = false}) async {
    calls++;
    if (forceRefresh) {
      forcedRefreshes++;
      _currentToken = 'ya29.test-only-${forcedRefreshes + 1}';
    }
    return _currentToken;
  }
}

void main() {
  test(
      'Klasör adları: Hub alt klasörü kök altında; eski istemci kökü değişmedi; LiveSync ayrı',
      () {
    expect(
        MmsDriveBackupFolders.rootFolderName, equals('MARKET MMS Yedekleri'));
    expect(GoogleDriveBackupUploader.folderName,
        equals(MmsDriveBackupFolders.rootFolderName));
    expect(ResumableDriveUploader.defaultFolderName,
        equals(MmsDriveBackupFolders.rootFolderName));
    expect(MmsDriveBackupFolders.hubSubfolderName, equals('Hub'));
    expect(GoogleDriveLiveEnvelopeTransport.folderName,
        isNot(equals(MmsDriveBackupFolders.rootFolderName)));
  });

  test(
      'DriveRemoteBackupInfo: kaynak işareti veya hub_backup_ öneki Hub yedeğini tanımlar',
      () {
    final hubBySource = DriveRemoteBackupInfo.tryParse({
      'id': 'h1',
      'name': 'anything.mmsbak',
      'appProperties': {
        'mms_backup_source': 'HUB_CENTRAL',
        'mms_backup_id': 'b1'
      },
    })!;
    final hubByLegacyName = DriveRemoteBackupInfo.tryParse({
      'id': 'h2',
      'name': 'hub_backup_20261122_abc.mmsbak',
      'appProperties': {'mms_backup_id': 'b2'},
    })!;
    final client = DriveRemoteBackupInfo.tryParse({
      'id': 'c1',
      'name': 'backup_MOBILE_LOCAL_dev1_x.mmsbak',
      'appProperties': {
        'mms_backup_id': 'c1',
        'mms_database_type': 'MOBILE_LOCAL'
      },
    })!;
    expect(hubBySource.isHubCentralBackup, isTrue);
    expect(hubByLegacyName.isHubCentralBackup, isTrue);
    expect(client.isHubCentralBackup, isFalse);
  });

  test(
      'Eski istemci geri yükleme listesi kök klasörde kalmış Hub yedeklerini göstermez',
      () async {
    final tmp = Directory.systemTemp.createTempSync('mms_test_only_s5_list_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final uploader = GoogleDriveBackupUploader(
      tokenProvider: _FakeTokens(),
      ledger: DriveUploadLedger(File(p.join(tmp.path, 'ledger.json'))),
      baseDelay: Duration.zero,
      httpClient: MockClient((req) async {
        final q = req.url.queryParameters['q'] ?? '';
        if (q.contains('application/vnd.google-apps.folder')) {
          return http.Response(
              jsonEncode({
                'files': [
                  {'id': 'root-folder'}
                ]
              }),
              200);
        }
        expect(q, contains("'root-folder' in parents"));
        return http.Response(
          jsonEncode({
            'files': [
              {
                'id': 'client-1',
                'name': 'backup_MOBILE_LOCAL_dev1_c1.mmsbak',
                'size': '100',
                'createdTime': '2026-11-20T10:00:00Z',
                'appProperties': {
                  'mms_backup_id': 'c1',
                  'mms_device_id': 'dev1'
                },
              },
              {
                // Geçiş öncesi kök klasöre yüklenmiş Hub yedeği (kaynak işareti yok)
                'id': 'hub-legacy',
                'name': 'hub_backup_hb1.mmsbak',
                'size': '200',
                'createdTime': '2026-11-21T10:00:00Z',
                'appProperties': {
                  'mms_backup_id': 'hb1',
                  'mms_device_id': 'MMS-HUB-MASTER'
                },
              },
              {
                'id': 'hub-marked',
                'name': 'other_name.mmsbak',
                'size': '300',
                'createdTime': '2026-11-22T10:00:00Z',
                'appProperties': {
                  'mms_backup_id': 'hb2',
                  'mms_backup_source': 'HUB_CENTRAL'
                },
              },
              // Hub alt klasörü (klasör, .mmsbak değil) listelenmez
              {'id': 'hub-subfolder', 'name': 'Hub'},
            ],
          }),
          200,
        );
      }),
    );

    final listed = await uploader.listRemoteBackups();
    expect(listed.map((e) => e.fileId), equals(['client-1']));
  });

  test(
      'ResumableDriveUploader alt klasörsüz (varsayılan) davranışı değişmedi: kök klasöre yükler',
      () async {
    final tmp = Directory.systemTemp.createTempSync('mms_test_only_s5_upl_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final plain = File(p.join(tmp.path, 'snap.db'))
      ..writeAsBytesSync(List<int>.filled(4096, 7));
    final enc = File(p.join(tmp.path, 'pkg.mmsbak'));
    final manifest = await MmsbakV2Crypto.encryptFile(
      inputFile: plain,
      outputFile: enc,
      password: 'S5-TestParolasi-2026!',
      kdfIterations: 1000,
      manifest: BackupManifest(
        backupId: 's5_default',
        deviceId: 'dev',
        tenantId: 't',
        storeId: 's',
        databaseType: DatabaseType.mobileLocal,
        schemaVersion: 1,
        appVersion: '1.0.0',
        timestamp: DateTime.utc(2026, 11, 22),
        checksum: '0' * 64,
        unencryptedSizeBytes: 4096,
        encryptedSizeBytes: 0,
        encryptionAlgorithm: MmsbakV2Crypto.algorithmId,
        kdfIterations: 1000,
      ),
    );
    final requests = <http.Request>[];
    final inlineTokens = _FakeTokens();
    final uploader = ResumableDriveUploader(
      accessTokenProvider: inlineTokens.accessToken,
      httpClient: MockClient((req) async {
        requests.add(req);
        final q = req.url.queryParameters['q'] ?? '';
        if (q.contains('google-apps.folder')) {
          return http.Response(
              jsonEncode({
                'files': [
                  {'id': 'root-x'}
                ]
              }),
              200);
        }
        // Yükleme başlatma aşamasında testi durdur (klasör seçimini doğrulamak yeterli).
        return http.Response('stop', 400);
      }),
    );
    await expectLater(
      uploader.uploadFile(encryptedFile: enc, manifest: manifest),
      throwsA(isA<DriveResumableUploadException>()),
    );
    final folderQueries = requests
        .where((r) =>
            (r.url.queryParameters['q'] ?? '').contains('google-apps.folder'))
        .toList();
    expect(folderQueries.length, equals(1));
    expect(folderQueries.single.url.queryParameters['q'],
        isNot(contains('in parents')));
    final init = requests
        .firstWhere((r) => r.url.toString().contains('uploadType=resumable'));
    expect((jsonDecode(init.body) as Map)['parents'], equals(['root-x']));
    expect(
        ((jsonDecode(init.body) as Map)['appProperties'] as Map)
            .containsKey('mms_backup_source'),
        isFalse);
  });

  test(
      'AUD-LOW-02: Test wrapper _FakeTokens forceRefresh=false/true ayrımını doğru uygular',
      () async {
    final tokens = _FakeTokens();
    final first = await tokens.accessToken(forceRefresh: false);
    final cached = await tokens.accessToken(forceRefresh: false);
    expect(cached, equals(first));

    final refreshed = await tokens.accessToken(forceRefresh: true);
    expect(refreshed, isNot(equals(first)));
  });
}
