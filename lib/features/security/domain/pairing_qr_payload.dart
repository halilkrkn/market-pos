import 'dart:convert';

import '../../../core/security/tls_pinned_client_factory.dart';

/// Hub eşleştirme QR kodu veya derin bağlantı içeriği.
class PairingQrPayload {
  final String sessionId;
  final String pairingSecret;
  final String? hubUrl;
  final String? caSha256;
  final String? caPem;

  const PairingQrPayload({
    required this.sessionId,
    required this.pairingSecret,
    this.hubUrl,
    this.caSha256,
    this.caPem,
  });

  String? get normalizedCaSha256 =>
      caSha256 == null ? null : PinnedTlsConfig.normalizeHex(caSha256!);

  static PairingQrPayload parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Eşleştirme QR/kodu boş olamaz.');
    }

    if (trimmed.startsWith('{')) {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Geçersiz JSON eşleştirme verisi.');
      }
      return _fromMap(decoded);
    }

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.queryParameters.isNotEmpty) {
      final qp = uri.queryParameters;
      final fallbackHubUrl = (uri.scheme == 'http' || uri.scheme == 'https')
          ? Uri(
              scheme: uri.scheme,
              host: uri.host,
              port: uri.hasPort ? uri.port : null,
            ).toString()
          : null;
      return _fromMap(<String, dynamic>{
        ...qp,
        if ((qp['hub_url'] == null && qp['hubUrl'] == null) &&
            fallbackHubUrl != null)
          'hub_url': fallbackHubUrl,
      });
    }

    throw const FormatException(
      'Eşleştirme verisi JSON veya marketmms://pair URL formatında olmalıdır.',
    );
  }

  static PairingQrPayload _fromMap(Map<String, dynamic> map) {
    String? pick(List<String> keys) {
      for (final key in keys) {
        final v = map[key]?.toString().trim();
        if (v != null && v.isNotEmpty) return v;
      }
      return null;
    }

    final sessionId = pick(const ['session_id', 'sessionId', 'sid']);
    final secret = pick(const ['pairing_secret', 'pairingSecret', 'secret']);
    if (sessionId == null || secret == null) {
      throw const FormatException(
        'Eşleştirme yükünde "session_id" ve "pairing_secret" alanları zorunludur.',
      );
    }

    final hubUrl = pick(const ['hub_url', 'hubUrl', 'url']);
    final rawCaSha = pick(
      const [
        'ca_sha256',
        'caSha256',
        'cert_sha256',
        'fingerprint',
        'ca_fingerprint',
        'caFingerprint',
      ],
    );
    final normalizedCaSha = (rawCaSha == null ||
            rawCaSha.trim().isEmpty ||
            rawCaSha.trim().toUpperCase() == 'UNKNOWN')
        ? null
        : PinnedTlsConfig.normalizeHex(rawCaSha);
    final caSha =
        (normalizedCaSha == null || normalizedCaSha.isEmpty) ? null : normalizedCaSha;
    final caPem = pick(const ['ca_pem', 'caPem', 'ca_cert']);

    return PairingQrPayload(
      sessionId: sessionId,
      pairingSecret: secret,
      hubUrl: hubUrl,
      caSha256: caSha,
      caPem: caPem,
    );
  }
}
