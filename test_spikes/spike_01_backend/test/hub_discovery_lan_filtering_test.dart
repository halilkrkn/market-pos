import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../lib/discovery/discovery_responder.dart';
import '../lib/network/hub_lan_address_resolver.dart';

class _StubInspector implements NetworkAdapterInspector {
  final List<LanInterfaceCandidate> adapters;
  const _StubInspector(this.adapters);

  @override
  Future<List<LanInterfaceCandidate>> inspectAdapters() async => adapters;
}

void main() {
  group('AŞAMA 4 — Hub LAN Discovery Adaptör Filtreleme & Protokol Testleri', () {
    test('VirtualBox Host-Only (Ethernet 3 / 192.168.84.2) ve Hyper-V Default Switch elenir, aktif Wi-Fi seçilir', () async {
      const candidates = <LanInterfaceCandidate>[
        LanInterfaceCandidate(
          adapterName: '{VBOX-2}',
          friendlyName: 'Ethernet 3',
          description: 'VirtualBox Host-Only Ethernet Adapter #2',
          ifIndex: 12,
          luid: 1012,
          ifType: 6,
          operStatus: 1,
          tunnelType: 0,
          hardwareInterface: true, // Bazı VirtualBox sürücüleri true bildirebilir
          hasGateway: false,
          ipv4Addresses: <UnicastIpv4Entry>[UnicastIpv4Entry(ip: '192.168.84.2')],
        ),
        LanInterfaceCandidate(
          adapterName: '{VBOX-1}',
          friendlyName: 'Ethernet 2',
          description: 'VirtualBox Host-Only Ethernet Adapter',
          ifIndex: 13,
          luid: 1013,
          ifType: 6,
          operStatus: 1,
          tunnelType: 0,
          hardwareInterface: true,
          hasGateway: false,
          ipv4Addresses: <UnicastIpv4Entry>[UnicastIpv4Entry(ip: '192.168.56.1')],
        ),
        LanInterfaceCandidate(
          adapterName: '{HYPERV}',
          friendlyName: 'vEthernet (Default Switch)',
          description: 'Hyper-V Virtual Ethernet Adapter',
          ifIndex: 14,
          luid: 1014,
          ifType: 6,
          operStatus: 1,
          tunnelType: 0,
          hardwareInterface: false,
          hasGateway: false,
          ipv4Addresses: <UnicastIpv4Entry>[UnicastIpv4Entry(ip: '172.26.112.1')],
        ),
        LanInterfaceCandidate(
          adapterName: '{WIFI-1}',
          friendlyName: 'Wi-Fi',
          description: 'Intel(R) Dual Band Wireless-AC 3168',
          ifIndex: 7,
          luid: 1007,
          ifType: 71,
          operStatus: 1,
          tunnelType: 0,
          hardwareInterface: true,
          hasGateway: true,
          ipv4Addresses: <UnicastIpv4Entry>[UnicastIpv4Entry(ip: '192.168.1.158')],
        ),
      ];

      final resolver = HubLanAddressResolver(inspector: const _StubInspector(candidates));
      final ips = await resolver.resolveDiscoveryLanIps();
      expect(ips, equals(const <String>['192.168.1.158']));
      expect(ips, isNot(contains('192.168.84.2')));
      expect(ips, isNot(contains('192.168.56.1')));
      expect(ips, isNot(contains('172.26.112.1')));
    });

    test('Çoklu aktif LAN adaptöründe gateway sahibi ve SAN uyumlu IP önceliklenir, tüm fiziksel LAN IP adresleri korunur', () async {
      const candidates = <LanInterfaceCandidate>[
        LanInterfaceCandidate(
          adapterName: '{ETH-NO-GW}',
          friendlyName: 'Ethernet 4',
          description: 'Realtek PCIe GbE Family Controller',
          ifIndex: 9,
          luid: 1009,
          ifType: 6,
          operStatus: 1,
          tunnelType: 0,
          hardwareInterface: true,
          hasGateway: false,
          ipv4Addresses: <UnicastIpv4Entry>[UnicastIpv4Entry(ip: '10.10.20.5')],
        ),
        LanInterfaceCandidate(
          adapterName: '{WIFI-GW}',
          friendlyName: 'Wi-Fi',
          description: 'Intel(R) Wi-Fi Adapter',
          ifIndex: 7,
          luid: 1007,
          ifType: 71,
          operStatus: 1,
          tunnelType: 0,
          hardwareInterface: true,
          hasGateway: true,
          ipv4Addresses: <UnicastIpv4Entry>[UnicastIpv4Entry(ip: '192.168.1.158')],
        ),
      ];

      final resolver = HubLanAddressResolver(inspector: const _StubInspector(candidates));
      final ips = await resolver.resolveDiscoveryLanIps(
        serverCertSanIpv4s: const <String>{'127.0.0.1', '192.168.1.158'},
      );
      expect(ips.first, equals('192.168.1.158'));
      expect(ips, contains('10.10.20.5'));
    });

    test('Adı belirsiz olsa bile açıklaması Host-Only olan sanal adaptör elenir', () {
      const candidates = <LanInterfaceCandidate>[
        LanInterfaceCandidate(
          adapterName: '{GENERIC-HOST-ONLY}',
          friendlyName: 'LAN99',
          description: 'Custom Host-Only Private Network Adapter',
          ifIndex: 20,
          luid: 1020,
          ifType: 6,
          operStatus: 1,
          tunnelType: 0,
          hardwareInterface: true,
          hasGateway: false,
          ipv4Addresses: <UnicastIpv4Entry>[UnicastIpv4Entry(ip: '192.168.99.1')],
        ),
        LanInterfaceCandidate(
          adapterName: '{LAN-REAL}',
          friendlyName: 'Ethernet',
          description: 'Killer E2500 Gigabit Ethernet Controller',
          ifIndex: 21,
          luid: 1021,
          ifType: 6,
          operStatus: 1,
          tunnelType: 0,
          hardwareInterface: true,
          hasGateway: true,
          ipv4Addresses: <UnicastIpv4Entry>[UnicastIpv4Entry(ip: '192.168.1.20')],
        ),
      ];

      final ips = HubLanAddressResolver.selectDiscoveryLanIpsFromCandidates(candidates);
      expect(ips, equals(const <String>['192.168.1.20']));
    });

    test('HubDiscoveryResponder tlsEnabled=true iken yanıtında scheme=https ve filtrelenmiş server_ips döner', () async {
      final responder = HubDiscoveryResponder(
        httpPort: 8945,
        discoveryPort: 18949,
        hubId: 'TEST-HTTPS-HUB',
        bindAddress: InternetAddress.loopbackIPv4,
        tlsEnabled: true,
        lanIpsProvider: () async => const <String>['192.168.1.158'],
      );
      await responder.start();
      addTearDown(responder.stop);

      final client = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(client.close);

      client.send(
        utf8.encode(jsonEncode(<String, dynamic>{'cmd': 'DISCOVER_MMS_HUB', 'version': '1.0'})),
        InternetAddress.loopbackIPv4,
        18949,
      );

      final completer = Completer<Map<String, dynamic>>();
      client.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = client.receive();
          if (dg != null && !completer.isCompleted) {
            completer.complete(jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>);
          }
        }
      });

      final resp = await completer.future.timeout(const Duration(seconds: 3));
      expect(resp['scheme'], equals('https'));
      expect(resp['server_ips'], equals(const <String>['192.168.1.158']));
      expect(resp.containsKey('tls'), isFalse);
    });

    test('Canlı Windows host üzerinde HubDiscoveryResponder.getLocalLanIps() 192.168.84.2 sızdırmaz', () async {
      final ips = await HubDiscoveryResponder.getLocalLanIps();
      expect(ips, isNot(contains('192.168.84.2')));
      expect(ips, isNot(contains('192.168.56.1')));
    });
  });
}
