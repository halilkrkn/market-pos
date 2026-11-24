import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/backup/hub_backup_oauth_service.dart';
import '../lib/backup/hub_backup_oauth_store.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/security/dpapi.dart';
import '../lib/security/live_drive_secret_manager.dart';
import '../lib/security/pepper_manager.dart';
import '../lib/security/token_manager.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mms_test_only_b2_oauth_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Faz B-2: WindowsDpapi Entropy, OAuth İzolasyonu & PKCE Hub Devri', () {
    test('BK-020: WindowsDpapi pOptionalEntropy, yanlış entropy reddi ve LiveDriveSecret izole kasası', () async {
      if (Platform.isWindows) {
        final entropyA = utf8.encode('MarketMMS:HubBackupDriveOAuth:v1');
        final entropyB = utf8.encode('MarketMMS:WrongEntropy:v1');
        final cipher = WindowsDpapi.protectString('super-secret-refresh-token', entropy: entropyA);
        expect(WindowsDpapi.unprotectString(cipher, entropy: entropyA), equals('super-secret-refresh-token'));
        expect(() => WindowsDpapi.unprotectString(cipher, entropy: entropyB), throwsA(isA<StateError>()));
        expect(() => WindowsDpapi.unprotectString(cipher), throwsA(isA<StateError>()));
      }

      // LiveDriveSecretManager ile HubBackupOAuthStore tamamen ayrı dosya ve bağlama sahiptir
      final securityDir = Directory(p.join(tempDir.path, 'security'));
      await securityDir.create(recursive: true);
      final liveDriveMgr = LiveDriveSecretManager(
        File(p.join(securityDir.path, 'live_drive_sync_secret.dpapi')),
      )..initialize();

      final store = HubBackupOAuthStore(
        File(p.join(securityDir.path, HubBackupOAuthStore.defaultFileName)),
      );
      await store.save(HubBackupOAuthCredentials(
        accessToken: 'acc_token_value_1',
        refreshToken: 'ref_token_value_1',
        expiresAtUtc: DateTime.utc(2026, 11, 22, 13, 0),
        accountEmail: 'pilot@example.com',
        scope: 'https://www.googleapis.com/auth/drive.file',
        connectedAtUtc: DateTime.utc(2026, 11, 22, 12, 0),
      ));

      final loaded = await store.load();
      expect(loaded, isNotNull);
      expect(loaded!.refreshToken, equals('ref_token_value_1'));
      expect(loaded.accountEmail, equals('pilot@example.com'));
      // Canlı sync sırrı ve dosyası bozulmamış olmalı
      expect(liveDriveMgr.secret.length, greaterThanOrEqualTo(32));
      expect(File(p.join(securityDir.path, 'live_drive_sync_secret.dpapi')).existsSync(), isTrue);
      expect(File(p.join(securityDir.path, HubBackupOAuthStore.defaultFileName)).existsSync(), isTrue);
    });

    test('BK-021: PKCE devri (/api/v1/backup/oauth/connect, status, refresh, disconnect) ham token sızdırmaz', () async {
      final dbFile = File(p.join(tempDir.path, 'data', 'market_master.db'));
      await dbFile.parent.create(recursive: true);
      final db = SpikeDatabase(dbFile);
      final wq = WriteQueue();
      final pepper = PepperManager(
        File(p.join(tempDir.path, 'security', 'pepper.dpapi')),
      )..initialize(overrideForTesting: 'pepper_b2_test_secret_32bytes_min');

      await db.into(db.devices).insert(
            DevicesCompanion.insert(
              deviceId: 'POS-OWNER-WIN-01',
              name: 'Owner Kasa',
              tokenHash: TokenManager.hashToken(
                rawToken: 'owner_token_1',
                salt: 'salt_owner_1',
                pepper: pepper.pepper,
              ),
              salt: 'salt_owner_1',
              role: const Value('OWNER'),
            ),
          );

      var refreshCount = 0;
      var currentTime = DateTime.utc(2026, 11, 22, 12, 0);
      final oauthMockHttp = MockClient((req) async {
        final body = req.bodyFields;
        if (req.url.toString().contains('/token')) {
          if (body['grant_type'] == 'authorization_code') {
            return http.Response(
              jsonEncode({
                'access_token': 'acc_secret_xyz_1',
                'refresh_token': 'ref_secret_xyz_1',
                'expires_in': 3600,
                'scope': 'https://www.googleapis.com/auth/drive.file',
              }),
              200,
            );
          }
          if (body['grant_type'] == 'refresh_token') {
            refreshCount++;
            return http.Response(
              jsonEncode({
                'access_token': 'acc_secret_refreshed_2',
                'expires_in': 3600,
              }),
              200,
            );
          }
        }
        if (req.url.toString().contains('/revoke')) {
          return http.Response('', 200);
        }
        return http.Response('Unexpected', 400);
      });

      final oauthStore = HubBackupOAuthStore(
        File(p.join(tempDir.path, 'security', HubBackupOAuthStore.defaultFileName)),
      );
      final oauthService = HubBackupOAuthService(
        store: oauthStore,
        httpClient: oauthMockHttp,
        clock: () => currentTime,
      );

      final server = SpikeServer(
        db: db,
        writeQueue: wq,
        dbFile: dbFile,
        backupDirectory: p.join(tempDir.path, 'backups'),
        pepperManager: pepper,
        adminSecret: 'admin_secret_b2_test',
        hubBackupOAuthService: oauthService,
      );

      final handler = server.handler;

      // 1. OWNER device token ile PKCE handoff (+ replay headers)
      final connectResp = await handler(Request(
        'POST',
        Uri.parse('https://127.0.0.1:8945/api/v1/backup/oauth/connect'),
        headers: {
          'authorization': 'Bearer owner_token_1',
          'content-type': 'application/json',
          'x-mms-timestamp': DateTime.now().toUtc().toIso8601String(),
          'x-mms-nonce': 'nonce_b2_connect_001',
        },
        body: jsonEncode({
          'auth_code': 'pkce_auth_code_123',
          'code_verifier': 'pkce_verifier_456_long_enough_value',
          'redirect_uri': 'http://127.0.0.1:43210/',
          'client_id': 'client_id_test',
          'account_email': 'kasa-sahibi@example.com',
        }),
      ));
      expect(connectResp.statusCode, equals(200));
      final connectJson = await connectResp.readAsString();
      expect(connectJson.contains('acc_secret_xyz_1'), isFalse);
      expect(connectJson.contains('ref_secret_xyz_1'), isFalse);
      final connectMap = jsonDecode(connectJson) as Map<String, dynamic>;
      expect(connectMap['connected'], isTrue);
      expect(connectMap['account_email'], equals('kasa-sahibi@example.com'));

      // 2. Status ham token içermez
      final statusResp = await handler(Request(
        'GET',
        Uri.parse('https://127.0.0.1:8945/api/v1/backup/oauth/status'),
        headers: {'authorization': 'Bearer owner_token_1'},
      ));
      expect(statusResp.statusCode, equals(200));
      final statusBody = await statusResp.readAsString();
      expect(statusBody.contains('acc_secret'), isFalse);
      expect(statusBody.contains('ref_secret'), isFalse);

      // 3. Süre dolmak üzereyken otomatik refresh
      currentTime = currentTime.add(const Duration(minutes: 59));
      final refreshedToken = await oauthService.getValidAccessToken(clientId: 'client_id_test');
      expect(refreshedToken, equals('acc_secret_refreshed_2'));
      expect(refreshCount, equals(1));

      // 4. Disconnect kasayı ve durumu temizler
      final discResp = await handler(Request(
        'POST',
        Uri.parse('https://127.0.0.1:8945/api/v1/backup/oauth/disconnect'),
        headers: {
          'authorization': 'Bearer owner_token_1',
          'x-mms-timestamp': DateTime.now().toUtc().toIso8601String(),
          'x-mms-nonce': 'nonce_b2_disconnect_001',
        },
      ));
      expect(discResp.statusCode, equals(200));
      expect(await oauthStore.file.exists(), isFalse);
      expect((await oauthService.getStatus()).connected, isFalse);

      await db.close();
    });
  });
}
