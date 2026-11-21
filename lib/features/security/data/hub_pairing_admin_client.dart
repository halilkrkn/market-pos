import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class HubPairingAdminException implements Exception {
  final String code;
  final String message;
  const HubPairingAdminException(this.code, this.message);

  @override
  String toString() => 'HubPairingAdminException($code): $message';
}

class PendingPairingRequest {
  final String sessionId;
  final String deviceId;
  final String deviceName;
  final String platform;
  final String publicKeyFingerprint;
  final DateTime? requestedAt;

  const PendingPairingRequest({
    required this.sessionId,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.publicKeyFingerprint,
    this.requestedAt,
  });

  factory PendingPairingRequest.fromJson(Map<String, dynamic> j) => PendingPairingRequest(
        sessionId: j['session_id'] as String,
        deviceId: j['device_id'] as String? ?? '?',
        deviceName: j['name'] as String? ?? '?',
        platform: j['platform'] as String? ?? 'UNKNOWN',
        publicKeyFingerprint: j['fingerprint'] as String? ?? '',
        requestedAt: DateTime.tryParse(j['created_at'] as String? ?? ''),
      );
}

class PairingSessionInfo {
  final String sessionId;
  final DateTime? expiresAt;

  /// Android cihazın tarayacağı/yapıştıracağı ham JSON (pairing secret içerir; loglanmaz).
  final String qrPayload;

  const PairingSessionInfo({required this.sessionId, required this.qrPayload, this.expiresAt});

  @override
  String toString() => 'PairingSessionInfo(sessionId: $sessionId, expiresAt: $expiresAt)';
}

/// Faz 7B — Windows Owner için Hub eşleştirme yönetimi (oturum aç, bekleyenleri listele,
/// onayla, reddet). Hub bu uçları yalnızca loopback + admin secret ile kabul eder;
/// admin secret çağrı başına verilir ve kalıcı olarak saklanmaz.
class HubPairingAdminClient {
  final String hubBaseUrl;
  final http.Client httpClient;
  final Duration timeout;

  HubPairingAdminClient({
    required this.hubBaseUrl,
    required this.httpClient,
    this.timeout = const Duration(seconds: 8),
  });

  Map<String, String> _headers(String adminSecret) {
    final clean = adminSecret.trim();
    if (clean.isEmpty) {
      throw const HubPairingAdminException('ERR_ADMIN_SECRET_REQUIRED', 'Hub yönetici anahtarını (admin secret) girin.');
    }
    return {'content-type': 'application/json', 'x-mms-admin-secret': clean};
  }

  Uri _uri(String path) => Uri.parse('${hubBaseUrl.replaceAll(RegExp(r'/+$'), '')}$path');

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() call) async {
    final http.Response resp;
    try {
      resp = await call().timeout(timeout);
    } on TimeoutException {
      throw const HubPairingAdminException('ERR_HUB_UNREACHABLE', 'Hub yanıt vermedi. Hub servisinin çalıştığını kontrol edin.');
    } on Exception catch (e) {
      throw HubPairingAdminException('ERR_HUB_UNREACHABLE', 'Hub\'a bağlanılamadı: ${e.runtimeType}');
    }
    Map<String, dynamic> body = const {};
    try {
      final d = jsonDecode(resp.body);
      if (d is Map) body = Map<String, dynamic>.from(d);
    } on FormatException {
      body = const {};
    }
    if (resp.statusCode >= 200 && resp.statusCode < 300) return body;
    final code = body['code'] as String? ?? body['error'] as String? ?? 'HTTP_${resp.statusCode}';
    final message = switch (resp.statusCode) {
      401 => 'Yönetici anahtarı gerekli.',
      403 when code == 'ERR_LOOPBACK_REQUIRED' => 'Bu işlem yalnızca Hub bilgisayarından yapılabilir.',
      403 => 'Yönetici anahtarı hatalı.',
      503 => 'Hub yönetici işlemleri yapılandırılmamış (admin secret dosyası yok).',
      _ => body['message'] as String? ?? 'Hub isteği başarısız (HTTP ${resp.statusCode}).',
    };
    throw HubPairingAdminException(code, message);
  }

  Future<List<PendingPairingRequest>> listPendingRequests({required String adminSecret}) async {
    final headers = _headers(adminSecret);
    final body = await _send(() => httpClient.get(_uri('/api/v1/pairing/requests'), headers: headers));
    return ((body['requests'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => PendingPairingRequest.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<void> approve({
    required String sessionId,
    required String adminSecret,
    bool allowRePair = false,
  }) async {
    final headers = _headers(adminSecret);
    await _send(() => httpClient.post(
          _uri('/api/v1/pairing/approve'),
          headers: headers,
          body: jsonEncode({
            'session_id': sessionId,
            if (allowRePair) 'allow_re_pair': true,
          }),
        ));
  }

  Future<void> reject({required String sessionId, required String adminSecret}) async {
    final headers = _headers(adminSecret);
    await _send(() => httpClient.post(_uri('/api/v1/pairing/reject'),
        headers: headers, body: jsonEncode({'session_id': sessionId})));
  }

  Future<PairingSessionInfo> createSession({required String adminSecret}) async {
    final headers = _headers(adminSecret);
    final body = await _send(() => httpClient.post(_uri('/api/v1/pairing/session'), headers: headers, body: '{}'));
    final sessionId = body['session_id'] as String?;
    if (sessionId == null) {
      throw const HubPairingAdminException('ERR_INVALID_RESPONSE', 'Hub eşleştirme oturumu döndürmedi.');
    }
    final expires = body['expires_at'];
    return PairingSessionInfo(
      sessionId: sessionId,
      qrPayload: jsonEncode(body),
      expiresAt: expires is int ? DateTime.fromMillisecondsSinceEpoch(expires * 1000) : null,
    );
  }
}
