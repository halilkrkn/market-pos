import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mms_client_storage/mms_client_storage.dart';

import '../domain/hub_discovery_client.dart';

/// Faz 1.1 `HubDiscoveryResponder` (UDP 8946) sözleşmesiyle tam uyumlu
/// UDP broadcast / unicast Master Hub keşif istemcisi (Faz 1.3).
class UdpHubDiscoveryClient implements HubDiscoveryClient {
  static const int defaultDiscoveryPort = 8946;
  static const String discoveryCommand = 'DISCOVER_MMS_HUB';
  static const String protocolVersion = '1.0';
  static const int maxResponseBytes = 2048;

  final int discoveryPort;
  final InternetAddress? bindAddress;
  final List<InternetAddress>? overrideTargets;
  final Duration settleAfterFirstMatch;
  final String defaultScheme;

  /// TLS-DISC: Her keşif anında şemayı çözer (ör. cihaz eşleştirildikten sonra
  /// `https`). Verilmezse [defaultScheme] kullanılır.
  final String Function()? schemeResolver;

  const UdpHubDiscoveryClient({
    this.discoveryPort = defaultDiscoveryPort,
    this.bindAddress,
    this.overrideTargets,
    this.settleAfterFirstMatch = const Duration(milliseconds: 200),
    this.defaultScheme = 'https',
    this.schemeResolver,
  });

  /// Bu keşif turunda adaylara uygulanacak şema.
  String get effectiveScheme => schemeResolver?.call() ?? defaultScheme;

  /// Yerel IPv4 ağ arayüzlerinden directed `/24` broadcast hedeflerini ve
  /// `255.255.255.255` genel broadcast adresini üretir.
  Future<List<InternetAddress>> resolveBroadcastTargets() async {
    if (overrideTargets != null && overrideTargets!.isNotEmpty) {
      return overrideTargets!;
    }

    final targets = <InternetAddress>[];
    final seenIps = <String>{};

    void addTarget(InternetAddress address) {
      if (seenIps.add(address.address)) {
        targets.add(address);
      }
    }

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
        includeLoopback: false,
      );

      for (final iface in interfaces) {
        final lowerName = iface.name.toLowerCase();
        if (_isIgnoredInterfaceName(lowerName)) {
          continue;
        }

        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('127.') ||
              ip.startsWith('169.254.') ||
              ip.startsWith('192.168.56.')) {
            continue;
          }

          final octets = ip.split('.');
          if (octets.length == 4) {
            final subnetBroadcast = InternetAddress.tryParse(
              '${octets[0]}.${octets[1]}.${octets[2]}.255',
            );
            if (subnetBroadcast != null) {
              addTarget(subnetBroadcast);
            }
          }
        }
      }
    } catch (e) {
      stderr.writeln(
        '[UdpHubDiscovery] Ağ arayüzleri listelenemedi: ${e.runtimeType}',
      );
    }

    addTarget(InternetAddress('255.255.255.255'));
    return targets;
  }

  static bool _isIgnoredInterfaceName(String lowerName) {
    return lowerName.contains('virtual') ||
        lowerName.contains('vbox') ||
        lowerName.contains('host-only') ||
        lowerName.contains('vmware') ||
        lowerName.contains('pseudo') ||
        lowerName.contains('vethernet') ||
        lowerName.contains('docker') ||
        lowerName.contains('utun') ||
        lowerName.contains('tun') ||
        lowerName.contains('rmnet') ||
        lowerName.contains('ccmni') ||
        lowerName.contains('pdp');
  }

  @override
  Future<List<DiscoveredHubCandidate>> discover({
    required String deviceId,
    Duration timeout = const Duration(milliseconds: 2500),
    int probeCount = 3,
    Duration probeInterval = const Duration(milliseconds: 600),
  }) async {
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    Timer? overallTimer;
    Timer? probeTimer;
    Timer? settleTimer;

    final candidates = <DiscoveredHubCandidate>[];
    final scheme = effectiveScheme;
    final seenKeys = <String>{};
    final completer = Completer<List<DiscoveredHubCandidate>>();

    void finishDiscovery() {
      if (!completer.isCompleted) {
        completer.complete(
          List<DiscoveredHubCandidate>.unmodifiable(candidates),
        );
      }
    }

    try {
      final targets = await resolveBroadcastTargets();
      if (targets.isEmpty) {
        return const <DiscoveredHubCandidate>[];
      }

      socket = await RawDatagramSocket.bind(
        bindAddress ?? InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;

      final payloadBytes = utf8.encode(
        jsonEncode(<String, dynamic>{
          'cmd': discoveryCommand,
          'version': protocolVersion,
          'client_device_id': deviceId,
        }),
      );

      void sendProbe() {
        final activeSocket = socket;
        if (activeSocket == null || completer.isCompleted) return;
        for (final target in targets) {
          try {
            activeSocket.send(payloadBytes, target, discoveryPort);
          } catch (_) {
            // Tekil arayüz/adres gönderim hatası diğer hedefleri kesmemelidir
          }
        }
      }

      subscription = socket.listen(
        (event) {
          final activeSocket = socket;
          if (event != RawSocketEvent.read || activeSocket == null) return;
          while (true) {
            final datagram = activeSocket.receive();
            if (datagram == null) break;
            if (datagram.data.length > maxResponseBytes) continue;

            try {
              final rawJson = utf8.decode(datagram.data, allowMalformed: false);
              final decoded = jsonDecode(rawJson);
              if (decoded is! Map<String, dynamic>) continue;

              final candidate = DiscoveredHubCandidate.tryFromUdpPayload(
                decoded,
                responderIp: datagram.address.address,
                scheme: scheme,
              );
              if (candidate == null) continue;

              final dedupKey =
                  '${candidate.hubId}|${candidate.responderIp ?? ''}|${candidate.httpPort}';
              if (seenKeys.add(dedupKey)) {
                candidates.add(candidate);
              }

              settleTimer ??= Timer(settleAfterFirstMatch, finishDiscovery);
            } catch (_) {
              // Bozuk UTF-8 veya geçersiz JSON paketleri yok sayılır
            }
          }
        },
        onError: (_) {},
        onDone: finishDiscovery,
        cancelOnError: false,
      );

      overallTimer = Timer(timeout, finishDiscovery);

      sendProbe();
      var sentCount = 1;
      if (probeCount > 1 && probeInterval > Duration.zero) {
        probeTimer = Timer.periodic(probeInterval, (timer) {
          if (completer.isCompleted || sentCount >= probeCount) {
            timer.cancel();
            return;
          }
          sentCount++;
          sendProbe();
        });
      }

      return await completer.future;
    } catch (_) {
      return List<DiscoveredHubCandidate>.unmodifiable(candidates);
    } finally {
      overallTimer?.cancel();
      probeTimer?.cancel();
      settleTimer?.cancel();
      await subscription?.cancel();
      socket?.close();
    }
  }
}
