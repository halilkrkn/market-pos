import 'package:meta/meta.dart';

import 'hub_url_validator.dart';

/// Faz 1.1 Hub UDP Discovery Responder JSON sözleşmesinin saf Dart adayı.
///
/// İstemci tarafında ağ soketi açmadan keşif yanıtını doğrulamak ve çoklu ağ
/// arayüzü durumunda yanıt veren IP'yi önceliklendirmek için kullanılır.
@immutable
class DiscoveredHubCandidate {
  static const String expectedService = 'market_mms_hub';

  final String service;
  final String protocolVersion;
  final String hubId;
  final int httpPort;
  final List<String> serverIps;
  final String? responderIp;
  final String scheme;

  const DiscoveredHubCandidate({
    required this.service,
    required this.protocolVersion,
    required this.hubId,
    required this.httpPort,
    required this.serverIps,
    this.responderIp,
    this.scheme = 'http',
  });

  /// UDP Discovery JSON paketinden aday oluşturur; beklenen sözleşmeye uymazsa `null` döner.
  static DiscoveredHubCandidate? tryFromUdpPayload(
    Map<String, dynamic> json, {
    String? responderIp,
    String scheme = 'http',
  }) {
    final service = json['service'];
    final protocolVersion = json['protocol_version'];
    final hubId = json['hub_id'];
    final rawPort = json['http_port'];
    final rawIps = json['server_ips'];

    if (service is! String || service.trim() != expectedService) return null;
    if (protocolVersion is! String || protocolVersion.trim().isEmpty) {
      return null;
    }
    if (hubId is! String || hubId.trim().isEmpty) return null;

    final httpPort = rawPort is int
        ? rawPort
        : (rawPort is String ? int.tryParse(rawPort.trim()) : null);
    if (httpPort == null || httpPort < 1 || httpPort > 65535) return null;

    final parsedIps = <String>[];
    if (rawIps is List) {
      for (final item in rawIps) {
        if (item is String && item.trim().isNotEmpty) {
          parsedIps.add(item.trim());
        }
      }
    }

    final normalizedResponderIp =
        responderIp != null && responderIp.trim().isNotEmpty
            ? responderIp.trim()
            : null;
    if (normalizedResponderIp == null && parsedIps.isEmpty) {
      return null;
    }

    return DiscoveredHubCandidate(
      service: service.trim(),
      protocolVersion: protocolVersion.trim(),
      hubId: hubId.trim(),
      httpPort: httpPort,
      serverIps: List<String>.unmodifiable(parsedIps),
      responderIp: normalizedResponderIp,
      scheme: scheme.trim().toLowerCase() == 'https' ? 'https' : 'http',
    );
  }

  /// Çoklu arayüz ortamında UDP yanıtını gönderen arayüz IP'sini öne koyarak
  /// denenebilir ve platform politikasına uygun temel URL listesi üretir.
  List<String> candidateBaseUrls({required bool allowLoopback}) {
    final orderedHosts = <String>[
      if (responderIp != null) responderIp!,
      ...serverIps,
    ];
    final urls = <String>[];
    final seen = <String>{};

    for (final host in orderedHosts) {
      final candidateRaw = _formatOrigin(scheme, host, httpPort);
      final normalized = HubUrlValidator.tryNormalize(
        candidateRaw,
        allowLoopback: allowLoopback,
      );
      if (normalized != null && seen.add(normalized)) {
        urls.add(normalized);
      }
    }

    return List<String>.unmodifiable(urls);
  }

  static String _formatOrigin(String scheme, String host, int port) {
    final trimmedHost = host.trim();
    final isBareIpv6 = trimmedHost.contains(':') &&
        !trimmedHost.startsWith('[') &&
        !trimmedHost.endsWith(']');
    final formattedHost = isBareIpv6 ? '[$trimmedHost]' : trimmedHost;
    return '$scheme://$formattedHost:$port';
  }
}
