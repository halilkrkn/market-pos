import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/features/updates/data/app_update_checker.dart';
import 'package:market_pos/features/updates/domain/app_update_info.dart';

/// UPD-SEC — Güncelleme manifestinin bütünlük ön koşulları.
///
/// Uygulama paketi kendisi indirip kurmaz; Owner'a "yeni sürüm" bilgisini ve
/// doğrulanacak SHA-256 özetini gösterir. Bu yüzden manifest, indirme adresi TLS
/// olmadan veya geçerli bir SHA-256 olmadan "güncelleme hazır" olarak sunulmamalıdır
/// (LAN'daki sahte manifest kullanıcıyı doğrulanamayan pakete yönlendiremez).
void main() {
  AppUpdateChecker checker(Map<String, dynamic> manifest, {int status = 200}) => AppUpdateChecker(
        currentVersion: '1.0.0',
        client: MockClient((_) async => http.Response(jsonEncode(manifest), status)),
      );

  const validSha = 'a3f1c2d4e5b60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

  test('1. HTTPS indirme adresi + geçerli SHA-256 → güncelleme hazır', () async {
    final r = await checker({
      'latest_version': '1.1.0',
      'min_supported_version': '1.0.0',
      'download_url': 'https://hub.local:8945/dl/market_mms_1.1.0.apk',
      'sha256': validSha.toUpperCase(),
    }).checkManifestUrl('https://hub.local/manifest.json');
    expect(r.availability, AppUpdateAvailability.updateAvailable);
    expect(r.manifest!.sha256Checksum, validSha, reason: 'özet küçük harfe normalize edilir');
  });

  test('2. Şifresiz HTTP indirme adresi reddedilir (sahte manifest / MITM)', () async {
    final r = await checker({
      'latest_version': '1.1.0',
      'download_url': 'http://192.168.1.50/market_mms.apk',
      'sha256': validSha,
    }).checkManifestUrl('https://hub.local/manifest.json');
    expect(r.availability, AppUpdateAvailability.unavailable);
    expect(r.message, contains('HTTPS'));
  });

  test('3. İndirme adresi varken SHA-256 eksik veya bozuksa reddedilir', () async {
    for (final sha in [null, '', 'abc123', 'z' * 64]) {
      final r = await checker({
        'latest_version': '1.1.0',
        'download_url': 'https://hub.local/market_mms.apk',
        'sha256': ?sha,
      }).checkManifestUrl('https://hub.local/manifest.json');
      expect(r.availability, AppUpdateAvailability.unavailable, reason: 'sha=$sha');
      expect(r.message, contains('SHA-256'));
    }
  });

  test('4. Bozuk manifest "çevrimdışı" değil "geçersiz manifest" olarak raporlanır', () async {
    final r = await checker({'min_supported_version': '1.0.0'}).checkManifestUrl('https://hub.local/m.json');
    expect(r.availability, AppUpdateAvailability.unavailable);
    expect(r.message, contains('geçersiz'));
    expect(r.message, isNot(contains('çevrimdışı')));
  });

  test('5. İndirme adresi olmayan bilgi amaçlı manifest (yalnızca sürüm) kabul edilir', () async {
    final r = await checker({'latest_version': '1.0.0', 'min_supported_version': '1.0.0'})
        .checkManifestUrl('https://hub.local/m.json');
    expect(r.availability, AppUpdateAvailability.upToDate);
  });

  test('6. Zorunlu sürüm (min_supported) güvenli olmayan manifestte de güvenli tarafta kalır: reddedilir', () async {
    final r = await checker({
      'latest_version': '2.0.0',
      'min_supported_version': '2.0.0',
      'download_url': 'http://evil.local/x.apk',
      'sha256': validSha,
    }).checkManifestUrl('https://hub.local/m.json');
    expect(r.availability, AppUpdateAvailability.unavailable);
  });

  test('7. Ağ hatası hâlâ çevrimdışı olarak raporlanır ve istisna fırlatmaz', () async {
    final r = await AppUpdateChecker(
      currentVersion: '1.0.0',
      client: MockClient((_) async => throw http.ClientException('bağlantı yok')),
    ).checkManifestUrl('https://hub.local/m.json');
    expect(r.availability, AppUpdateAvailability.unavailable);
    expect(r.message, contains('çevrimdışı'));
  });
}
