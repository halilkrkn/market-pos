import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/features/updates/data/app_update_checker.dart';
import 'package:market_pos/features/updates/data/app_update_installer.dart';
import 'package:market_pos/features/updates/domain/app_update_info.dart';

void main() {
  group('GitHub Releases Uzaktan Güncelleme Denetleyicisi', () {
    const windowsPayload = 'dummy-windows-msi-bytes-1.0.4';
    const androidPayload = 'dummy-android-apk-bytes-1.0.4';
    final windowsSha = sha256.convert(utf8.encode(windowsPayload)).toString();
    final androidSha = sha256.convert(utf8.encode(androidPayload)).toString();

    String buildReleasesJson({
      String tagName = 'v1.0.4-b5',
      bool prerelease = true,
      bool draft = false,
      bool includeShaAsset = true,
      String? releaseBody = 'Hata düzeltmeleri ve otomatik güncelleme desteği.',
    }) {
      return jsonEncode([
        {
          'tag_name': tagName,
          'draft': draft,
          'prerelease': prerelease,
          'body': releaseBody,
          'assets': [
            {
              'name': 'MarketMMS-Setup-1.0.4-x64.msi',
              'browser_download_url':
                  'https://github.com/halilkrkn/market-pos/releases/download/$tagName/MarketMMS-Setup-1.0.4-x64.msi',
            },
            {
              'name': 'MarketMMS-1.0.4-b5-android-TEST_ONLY.apk',
              'browser_download_url':
                  'https://github.com/halilkrkn/market-pos/releases/download/$tagName/MarketMMS-1.0.4-b5-android-TEST_ONLY.apk',
            },
            if (includeShaAsset)
              {
                'name': 'SHA256SUMS.txt',
                'browser_download_url':
                    'https://github.com/halilkrkn/market-pos/releases/download/$tagName/SHA256SUMS.txt',
              },
          ],
        },
      ]);
    }

    const utf8JsonHeaders = {'content-type': 'application/json; charset=utf-8'};

    final validShaSums = '''
$windowsSha  MarketMMS-Setup-1.0.4-x64.msi
$androidSha  MarketMMS-1.0.4-b5-android-TEST_ONLY.apk
''';

    test('Windows için MarketMMS-Setup-*.msi ve SHA256SUMS.txt eşleşmesini doğrular', () async {
      final checker = AppUpdateChecker(
        currentVersion: '1.0.3',
        currentBuildNumber: 4,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/releases')) {
            return http.Response(
              buildReleasesJson(),
              200,
              headers: utf8JsonHeaders,
            );
          }
          if (request.url.path.endsWith('/SHA256SUMS.txt')) {
            return http.Response(validShaSums, 200);
          }
          return http.Response('not found', 404);
        }),
      );

      final res = await checker.checkGitHubRelease(platform: TargetPlatform.windows);
      expect(res.availability, AppUpdateAvailability.updateAvailable);
      expect(res.manifest, isNotNull);
      expect(res.manifest!.latestVersion, '1.0.4-b5');
      expect(res.manifest!.assetFileName, 'MarketMMS-Setup-1.0.4-x64.msi');
      expect(
        res.manifest!.downloadUrl,
        'https://github.com/halilkrkn/market-pos/releases/download/v1.0.4-b5/MarketMMS-Setup-1.0.4-x64.msi',
      );
      expect(res.manifest!.sha256Checksum, windowsSha);
      expect(res.manifest!.releaseNotes, contains('otomatik güncelleme'));
    });

    test('Android için MarketMMS-*-android*.apk ve SHA256SUMS.txt eşleşmesini doğrular', () async {
      final checker = AppUpdateChecker(
        currentVersion: '1.0.3',
        currentBuildNumber: 4,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/releases')) {
            return http.Response(
              buildReleasesJson(),
              200,
              headers: utf8JsonHeaders,
            );
          }
          if (request.url.path.endsWith('/SHA256SUMS.txt')) {
            return http.Response(validShaSums, 200);
          }
          return http.Response('not found', 404);
        }),
      );

      final res = await checker.checkGitHubRelease(platform: TargetPlatform.android);
      expect(res.availability, AppUpdateAvailability.updateAvailable);
      expect(res.manifest!.assetFileName, 'MarketMMS-1.0.4-b5-android-TEST_ONLY.apk');
      expect(res.manifest!.sha256Checksum, androidSha);
    });

    test('aynı sürüm (v1.0.3-b4 vs 1.0.3+4) upToDate, daha yeni build (v1.0.3-b5) updateAvailable döner', () async {
      final sameChecker = AppUpdateChecker(
        currentVersion: '1.0.3',
        currentBuildNumber: 4,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/releases')) {
            return http.Response(
              buildReleasesJson(tagName: 'v1.0.3-b4'),
              200,
              headers: utf8JsonHeaders,
            );
          }
          return http.Response(validShaSums, 200);
        }),
      );
      expect(
        (await sameChecker.checkGitHubRelease(platform: TargetPlatform.windows))
            .availability,
        AppUpdateAvailability.upToDate,
      );

      final newerBuildChecker = AppUpdateChecker(
        currentVersion: '1.0.3',
        currentBuildNumber: 4,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/releases')) {
            return http.Response(
              buildReleasesJson(tagName: 'v1.0.3-b5'),
              200,
              headers: utf8JsonHeaders,
            );
          }
          return http.Response(validShaSums, 200);
        }),
      );
      expect(
        (await newerBuildChecker.checkGitHubRelease(platform: TargetPlatform.windows))
            .availability,
        AppUpdateAvailability.updateAvailable,
      );
    });

    test('includePrereleases=false iken prerelease ve daima draft sürümler atlanır', () async {
      final checker = AppUpdateChecker(
        currentVersion: '1.0.3',
        currentBuildNumber: 4,
        client: MockClient((request) async {
          return http.Response(
            jsonEncode([
              jsonDecode(buildReleasesJson(tagName: 'v1.0.9-b9', prerelease: true)).first,
              jsonDecode(buildReleasesJson(tagName: 'v1.0.8', draft: true, prerelease: false)).first,
            ]),
            200,
            headers: utf8JsonHeaders,
          );
        }),
      );

      final res = await checker.checkGitHubRelease(
        platform: TargetPlatform.windows,
        includePrereleases: false,
      );
      expect(res.availability, AppUpdateAvailability.upToDate);
    });

    test('SHA256SUMS.txt eksik veya hedef dosya özeti bulunmuyorsa fail-closed unavailable döner', () async {
      final missingAssetChecker = AppUpdateChecker(
        currentVersion: '1.0.3',
        currentBuildNumber: 4,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/releases')) {
            return http.Response(
              buildReleasesJson(includeShaAsset: false),
              200,
              headers: utf8JsonHeaders,
            );
          }
          return http.Response('', 404);
        }),
      );
      expect(
        (await missingAssetChecker.checkGitHubRelease(platform: TargetPlatform.windows))
            .availability,
        AppUpdateAvailability.unavailable,
      );

      final malformedShaChecker = AppUpdateChecker(
        currentVersion: '1.0.3',
        currentBuildNumber: 4,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/releases')) {
            return http.Response(
              buildReleasesJson(),
              200,
              headers: utf8JsonHeaders,
            );
          }
          return http.Response('deadbeef  MarketMMS-Setup-1.0.4-x64.msi\n', 200);
        }),
      );
      expect(
        (await malformedShaChecker.checkGitHubRelease(platform: TargetPlatform.windows))
            .availability,
        AppUpdateAvailability.unavailable,
      );
    });

    test('çevrimdışı / ağ hatasında sessizce unavailable döner ve istisna fırlatmaz', () async {
      final offlineChecker = AppUpdateChecker(
        currentVersion: '1.0.3',
        currentBuildNumber: 4,
        client: MockClient((_) async => throw const SocketException('offline')),
      );

      final res = await offlineChecker.checkGitHubRelease(
        platform: TargetPlatform.android,
      );
      expect(res.availability, AppUpdateAvailability.unavailable);
    });
  });

  group('AppUpdateInstaller SHA-256 Doğrulama ve Fail-Closed İndirme', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('mms_update_dl_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('geçerli SHA-256 ile indirme tamamlanır ve dosya diske kaydedilir', () async {
      final bytes = utf8.encode('verified-msi-installer-binary-content');
      final expectedSha = sha256.convert(bytes).toString();
      final progressEvents = <double>[];

      final installer = AppUpdateInstaller(
        downloadDirectory: tempDir,
        platformOverride: TargetPlatform.windows,
        client: MockClient((request) async {
          return http.Response.bytes(
            bytes,
            200,
            headers: {'content-length': '${bytes.length}'},
          );
        }),
      );

      final manifest = AppUpdateManifest(
        latestVersion: '1.0.4',
        minSupportedVersion: '1.0.0',
        downloadUrl: 'https://github.com/halilkrkn/market-pos/releases/download/v1.0.4/MarketMMS-Setup-1.0.4-x64.msi',
        sha256Checksum: expectedSha,
        assetFileName: 'MarketMMS-Setup-1.0.4-x64.msi',
      );

      final file = await installer.downloadAndVerify(
        manifest,
        onProgress: progressEvents.add,
      );

      expect(await file.exists(), isTrue);
      expect(await file.readAsBytes(), bytes);
      expect(progressEvents.last, 1.0);
    });

    test('SHA-256 uyuşmazlığında dosyayı DERHAL siler ve AppUpdateInstallException fırlatır', () async {
      final bytes = utf8.encode('tampered-installer-binary');
      final wrongSha = '0' * 64;

      final installer = AppUpdateInstaller(
        downloadDirectory: tempDir,
        platformOverride: TargetPlatform.windows,
        client: MockClient((request) async {
          return http.Response.bytes(
            bytes,
            200,
            headers: {'content-length': '${bytes.length}'},
          );
        }),
      );

      final manifest = AppUpdateManifest(
        latestVersion: '1.0.4',
        minSupportedVersion: '1.0.0',
        downloadUrl: 'https://github.com/halilkrkn/market-pos/releases/download/v1.0.4/MarketMMS-Setup-1.0.4-x64.msi',
        sha256Checksum: wrongSha,
        assetFileName: 'MarketMMS-Setup-1.0.4-x64.msi',
      );

      await expectLater(
        () => installer.downloadAndVerify(manifest),
        throwsA(
          isA<AppUpdateInstallException>().having(
            (e) => e.code,
            'code',
            'SHA256_MISMATCH',
          ),
        ),
      );

      expect(tempDir.listSync(), isEmpty);
    });

    test('HTTPS olmayan indirme adresi fail-closed reddedilir', () async {
      final installer = AppUpdateInstaller(
        downloadDirectory: tempDir,
        platformOverride: TargetPlatform.android,
      );
      final insecureManifest = AppUpdateManifest(
        latestVersion: '1.0.4',
        minSupportedVersion: '1.0.0',
        downloadUrl: 'http://example.com/update.apk',
        sha256Checksum: 'a' * 64,
        assetFileName: 'update.apk',
      );

      await expectLater(
        () => installer.downloadAndVerify(insecureManifest),
        throwsA(
          isA<AppUpdateInstallException>().having(
            (e) => e.code,
            'code',
            'INVALID_MANIFEST',
          ),
        ),
      );
    });
  });
}
