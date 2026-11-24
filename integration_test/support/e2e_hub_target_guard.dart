import 'dart:convert';

import 'package:mms_client_storage/mms_client_storage.dart';

/// S6: E2E testinin hedef Hub'ı güvenlik nedeniyle reddedildi.
class E2eHubTargetRejected implements Exception {
  final String reason;

  const E2eHubTargetRejected(this.reason);

  @override
  String toString() => 'E2eHubTargetRejected: $reason';
}

/// S6: Uçtan uca (E2E) testlerin üretim Master Hub'ına yazmasını TEKNİK olarak
/// engelleyen hedef doğrulayıcı. Varsayılan davranış kapalıdır (fail-closed).
///
/// Bir Hub'a herhangi bir istek (okuma dahil) gönderilmeden ÖNCE:
/// 1. [validateTarget] — çevrimdışı kontroller:
///    - `MMS_E2E_EXPECTED_HUB_ID` zorunludur ve [testHubIdPattern] ile eşleşmelidir
///      (`E2E-` veya `TEST-` öneki). Üretim/varsayılan Hub kimlikleri
///      (ör. `MMS-HUB-MASTER`, `HUB-PILOT-01`) bu kurala uymadığı için reddedilir.
///    - `MMS_E2E_HUB_ALLOWLIST` zorunludur (`host:port` virgüllü liste) ve Hub URL'sinin
///      (keşifle bulunan dahil) `host:port` değeri listede birebir bulunmalıdır.
/// Yazma işlemlerinden ÖNCE:
/// 2. [verifyHubIdentity] — salt-okunur `GET /api/v1/sync/device-state` ile Hub'ın
///    bildirdiği `hub_id` beklenen test kimliğine birebir eşit olmalıdır. Aynı adreste
///    yanlışlıkla üretim Hub'ı çalışıyorsa kimlik uyuşmaz ve test hiçbir şey yazmadan durur.
abstract final class E2eHubTargetGuard {
  static final RegExp testHubIdPattern =
      RegExp(r'^(E2E|TEST)-[A-Za-z0-9][A-Za-z0-9_-]{1,62}$');

  /// `host:port` listesini ayrıştırır; port zorunludur (örtük port kabul edilmez).
  static Set<String> parseAllowlist(String csv) {
    final result = <String>{};
    for (final raw in csv.split(',')) {
      final entry = raw.trim().toLowerCase();
      if (entry.isEmpty) continue;
      final idx = entry.lastIndexOf(':');
      if (idx <= 0 || idx == entry.length - 1) {
        throw E2eHubTargetRejected(
          'MMS_E2E_HUB_ALLOWLIST girdisi "host:port" biçiminde olmalıdır: "$raw"',
        );
      }
      final port = int.tryParse(entry.substring(idx + 1));
      if (port == null || port <= 0 || port > 65535) {
        throw E2eHubTargetRejected('MMS_E2E_HUB_ALLOWLIST geçersiz port: "$raw"');
      }
      result.add(entry);
    }
    return result;
  }

  static String hostPortOf(Uri uri) {
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    return '${uri.host.toLowerCase()}:$port';
  }

  /// Ağ isteği yapmadan hedef adres ve beklenen Hub kimliğini doğrular.
  static void validateTarget({
    required String hubUrl,
    required String allowlistCsv,
    required String expectedHubId,
  }) {
    final expected = expectedHubId.trim();
    if (expected.isEmpty) {
      throw const E2eHubTargetRejected(
        'MMS_E2E_EXPECTED_HUB_ID tanımlı değil. E2E testi yalnızca kimliği bilinen izole '
        'TEST Hub üzerinde çalışır (ör. HUB_ID=E2E-HUB-01 ile başlatılmış Hub).',
      );
    }
    if (!testHubIdPattern.hasMatch(expected)) {
      throw E2eHubTargetRejected(
        'Beklenen Hub kimliği "$expected" test öneki (E2E- / TEST-) taşımıyor. '
        'Üretim Hub kimlikleriyle E2E testi çalıştırılamaz.',
      );
    }
    final allow = parseAllowlist(allowlistCsv);
    if (allow.isEmpty) {
      throw const E2eHubTargetRejected(
        'MMS_E2E_HUB_ALLOWLIST tanımlı değil. İzinli test Hub adreslerini '
        '"host:port" listesi olarak verin (ör. 192.168.50.10:9443).',
      );
    }
    final uri = Uri.tryParse(hubUrl.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw E2eHubTargetRejected('Geçersiz Hub adresi: "$hubUrl"');
    }
    final target = hostPortOf(uri);
    if (!allow.contains(target)) {
      throw E2eHubTargetRejected(
        'Hub adresi $target izinli test Hub listesinde değil (MMS_E2E_HUB_ALLOWLIST).',
      );
    }
  }

  /// Yazma işlemlerinden önce Hub kimliğini salt-okunur uçla doğrular.
  static Future<void> verifyHubIdentity({
    required PostRestoreSyncTransport transport,
    required String hubUrl,
    required String deviceToken,
    required String expectedHubId,
  }) async {
    final resp = await transport.getDeviceState(hubUrl: hubUrl, token: deviceToken);
    if (resp.statusCode != 200) {
      throw E2eHubTargetRejected(
        'Hub kimliği doğrulanamadı (GET /api/v1/sync/device-state → '
        '${resp.isNetworkError ? 'ağ hatası' : 'HTTP ${resp.statusCode}'}). Test yazma yapmadan durduruldu.',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(resp.body);
    } on FormatException {
      decoded = null;
    }
    final hubId = decoded is Map ? decoded['hub_id'] : null;
    if (hubId is! String || hubId != expectedHubId.trim()) {
      throw E2eHubTargetRejected(
        'Hub kimliği uyuşmuyor (beklenen: ${expectedHubId.trim()}, gelen: $hubId). '
        'Hedef bir üretim Hub\'ı olabilir; test yazma yapmadan durduruldu.',
      );
    }
  }
}
