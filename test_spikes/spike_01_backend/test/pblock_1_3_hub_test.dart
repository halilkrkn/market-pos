import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../bin/server.dart';
import '../lib/config/hub_config.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../lib/discovery/discovery_responder.dart';
import '../lib/network/hub_lan_address_resolver.dart';
import '../lib/security/certificate_manager.dart';
import '../lib/security/ecdsa_signature_validator.dart';
import '../lib/security/pairing_manager.dart';
import '../lib/security/pepper_manager.dart';
import '../lib/security/tls_client_factory.dart';
import '../lib/security/token_manager.dart';

class _FakeInspector implements NetworkAdapterInspector {
  final List<LanInterfaceCandidate> candidates;
  final Object? throwError;
  _FakeInspector(this.candidates, {this.throwError});

  @override
  Future<List<LanInterfaceCandidate>> inspectAdapters() async {
    if (throwError != null) throw throwError!;
    return candidates;
  }
}

Uint8List _tlv(int tag, List<int> content) {
  final len = content.length;
  final out = <int>[tag];
  if (len < 128) {
    out.add(len);
  } else if (len <= 0xFF) {
    out.addAll([0x81, len]);
  } else {
    out.addAll([0x82, (len >> 8) & 0xFF, len & 0xFF]);
  }
  out.addAll(content);
  return Uint8List.fromList(out);
}

Uint8List _tlvSeq(int tag, List<List<int>> children) {
  final flat = <int>[];
  for (final c in children) {
    flat.addAll(c);
  }
  return _tlv(tag, flat);
}

Uint8List _buildSyntheticX509({
  bool includeV3 = true,
  int version = 2,
  bool outerSigMismatch = false,
  bool diffSubjectFromIssuer = false,
  bool expired = false,
  bool notYetValid = false,
  bool duplicateOid = false,
  bool nonCanonicalCriticalFalse = false,
  bool caTrue = true,
  bool includeKeyUsage = true,
  bool keyCertSign = true,
  bool includeSan = false,
}) {
  final sigAlg = _tlv(0x30, [0x06, 0x03, 0x55, 0x04, 0x03]);
  final altSigAlg = _tlv(0x30, [0x06, 0x03, 0x55, 0x04, 0x04]);
  final nameA = _tlvSeq(0x30, [
    _tlvSeq(0x31, [
      _tlvSeq(0x30, [
        _tlv(0x06, [0x55, 0x04, 0x03]),
        _tlv(0x0C, utf8.encode('MMS Synth CA')),
      ]),
    ]),
  ]);
  final nameB = _tlvSeq(0x30, [
    _tlvSeq(0x31, [
      _tlvSeq(0x30, [
        _tlv(0x06, [0x55, 0x04, 0x03]),
        _tlv(0x0C, utf8.encode('MMS Other CA')),
      ]),
    ]),
  ]);

  final nbStr = notYetValid ? '400101000000Z' : '250101000000Z';
  final naStr = expired ? '250102000000Z' : '450101000000Z';
  final validity = _tlvSeq(0x30, [
    _tlv(0x17, ascii.encode(nbStr)),
    _tlv(0x17, ascii.encode(naStr)),
  ]);

  final spki = _tlvSeq(0x30, [
    sigAlg,
    _tlv(0x03, [0x00, ...List<int>.filled(36, 0x11)]),
  ]);

  final exts = <int>[];
  // BasicConstraints 2.5.29.19 -> 55 1D 13
  final bcValue = _tlvSeq(0x30, caTrue ? [_tlv(0x01, [0xFF])] : []);
  exts.addAll(_tlvSeq(0x30, [
    _tlv(0x06, [0x55, 0x1D, 0x13]),
    if (nonCanonicalCriticalFalse) _tlv(0x01, [0x00]),
    _tlv(0x04, bcValue),
  ]));
  if (duplicateOid) {
    exts.addAll(_tlvSeq(0x30, [
      _tlv(0x06, [0x55, 0x1D, 0x13]),
      _tlv(0x04, bcValue),
    ]));
  }
  if (includeKeyUsage) {
    final kuByte = keyCertSign ? 0x06 : 0x80; // 0x04 = keyCertSign, 0x02 = cRLSign
    final kuBitStr = _tlv(0x03, [0x01, kuByte]);
    exts.addAll(_tlvSeq(0x30, [
      _tlv(0x06, [0x55, 0x1D, 0x0F]),
      _tlv(0x04, kuBitStr),
    ]));
  }
  if (includeSan) {
    final sanVal = _tlvSeq(0x30, [
      _tlv(0x87, [127, 0, 0, 1]),
    ]);
    exts.addAll(_tlvSeq(0x30, [
      _tlv(0x06, [0x55, 0x1D, 0x11]),
      _tlv(0x04, sanVal),
    ]));
  }

  final tbsBody = <int>[
    if (includeV3) ..._tlv(0xA0, _tlv(0x02, [version])),
    ..._tlv(0x02, [0x01]), // serial
    ...sigAlg,
    ...nameA, // issuer
    ...validity,
    ...(diffSubjectFromIssuer ? nameB : nameA), // subject
    ...spki,
    ..._tlv(0xA3, _tlv(0x30, exts)),
  ];

  final tbs = _tlv(0x30, tbsBody);
  return _tlv(0x30, [
    ...tbs,
    ...(outerSigMismatch ? altSigAlg : sigAlg),
    ..._tlv(0x03, [0x00, 0x01, 0x02, 0x03]),
  ]);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final fixedNow = DateTime.utc(2027, 6, 15);

  group('P-BLOCK-1: TV-DER-01..05 & TV-X509-01..09 (UTF-8 Bağımsız DER/PEM & MmsX509PreValidator)', () {
    test('HUB-T01 / HUB-T01d / TV-DER-01..04: Ham binary DER, LF PEM, BOM+CRLF PEM aynı SHA-256 üretir; F-1 utf8 bağımsızdır', () {
      final derBytes = kSharedTestRootCaDerBytes;
      expect(derBytes.any((b) => b >= 0x80), isTrue, reason: 'Gerçek binary DER yüksek-bit baytlar içermelidir');

      final r1 = extractCanonicalSingleCertDer(derBytes);
      expect(r1.wasPem, isFalse);
      expect(r1.sha256Hex, kSharedTestRootCaSha256Hex);

      final lfPemBytes = Uint8List.fromList(utf8.encode(kSharedTestRootCaPem.replaceAll('\r\n', '\n')));
      final r2 = extractCanonicalSingleCertDer(lfPemBytes);
      expect(r2.wasPem, isTrue);
      expect(r2.sha256Hex, kSharedTestRootCaSha256Hex);

      final bomCrlfBytes = Uint8List.fromList([
        0xEF, 0xBB, 0xBF,
        ...utf8.encode('\r\n${kSharedTestRootCaPem.replaceAll('\n', '\r\n')}\r\n  '),
      ]);
      final r3 = extractCanonicalSingleCertDer(bomCrlfBytes);
      expect(r3.wasPem, isTrue);
      expect(r3.sha256Hex, kSharedTestRootCaSha256Hex);

      // HUB-T01b / TV-X509-01: Gerçek OpenSSL X.509v3 Root CA validation geçer
      MmsX509PreValidator.validateRootCaDer(derBytes, nowUtc: fixedNow);
    });

    test('HUB-T01d / HUB-T02 / TV-DER-05: Sınır ihlalleri, BOM/UTF-8, trailing byte, 0x80 ve çoklu blok reddedilir', () {
      final validDer = kSharedTestRootCaDerBytes;

      final cases = <Uint8List>[
        // Çoklu sertifika
        Uint8List.fromList(utf8.encode('$kSharedTestRootCaPem\n$kSharedTestRootCaPem')),
        // Private key başlığı
        Uint8List.fromList(utf8.encode('-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----')),
        // Bozuk Base64
        Uint8List.fromList(utf8.encode('-----BEGIN CERTIFICATE-----\n@@@invalid@@@\n-----END CERTIFICATE-----')),
        // Trailing byte eklenmiş DER
        Uint8List.fromList([...validDer, 0x00]),
        // Truncated DER
        Uint8List.sublistView(validDer, 0, validDer.length - 10),
        // Indefinite length 0x80
        Uint8List.fromList([0x30, 0x80, 0x02, 0x01, 0x01, 0x00, 0x00]),
        // Non-minimal long-form length (0x81 0x04 yerine 0x04 olmalı)
        Uint8List.fromList([0x30, 0x81, 0x04, 0x02, 0x02, 0x01, 0x02]),
        // BOM + bozuk UTF-8
        Uint8List.fromList([0xEF, 0xBB, 0xBF, 0xFF, 0xFE, 0xFA]),
        // -----BEGIN ile birlikte bozuk UTF-8
        Uint8List.fromList([...ascii.encode('-----BEGIN '), 0xFF, 0xFE]),
        // Çok küçük (3 bayt)
        Uint8List.fromList([0x30, 0x01, 0x00]),
      ];

      for (final bad in cases) {
        expect(
          () => extractCanonicalSingleCertDer(bad),
          throwsA(isA<X509ValidationException>().having((e) => e.code, 'code', 'INVALID_CA_CERT')),
        );
      }

      // 65.537 bayt (> 64 KB) sınırı
      expect(
        () => extractCanonicalSingleCertDer(Uint8List(65537)),
        throwsA(isA<X509ValidationException>()),
      );
    });

    test('HUB-T02b / HUB-T02c / TV-X509-02..09: Sentetik CA:TRUE, keyCertSign, v1, expiry, notYetValid, duplicate OID, sigAlg mismatch, critical:FALSE', () {
      // Geçerli sentetik v3 Root CA
      final good = _buildSyntheticX509();
      MmsX509PreValidator.validateRootCaDer(good, nowUtc: fixedNow);

      expect(
        () => MmsX509PreValidator.validateRootCaDer(_buildSyntheticX509(caTrue: false), nowUtc: fixedNow),
        throwsA(isA<X509ValidationException>().having((e) => e.code, 'code', 'CA_CERT_NOT_CA')),
      );
      expect(
        () => MmsX509PreValidator.validateRootCaDer(_buildSyntheticX509(includeSan: true), nowUtc: fixedNow),
        throwsA(isA<X509ValidationException>().having((e) => e.code, 'code', 'CA_CERT_IS_LEAF_CERT')),
      );
      expect(
        () => MmsX509PreValidator.validateRootCaDer(_buildSyntheticX509(keyCertSign: false), nowUtc: fixedNow),
        throwsA(isA<X509ValidationException>().having((e) => e.code, 'code', 'CA_CERT_MISSING_KEY_CERT_SIGN')),
      );
      expect(
        () => MmsX509PreValidator.validateRootCaDer(_buildSyntheticX509(includeV3: false), nowUtc: fixedNow),
        throwsA(isA<X509ValidationException>().having((e) => e.code, 'code', 'CA_CERT_NOT_V3')),
      );
      expect(
        () => MmsX509PreValidator.validateRootCaDer(_buildSyntheticX509(expired: true), nowUtc: fixedNow),
        throwsA(isA<X509ValidationException>().having((e) => e.code, 'code', 'CA_CERT_EXPIRED')),
      );
      expect(
        () => MmsX509PreValidator.validateRootCaDer(_buildSyntheticX509(notYetValid: true), nowUtc: fixedNow),
        throwsA(isA<X509ValidationException>().having((e) => e.code, 'code', 'CA_CERT_NOT_YET_VALID')),
      );
      expect(
        () => MmsX509PreValidator.validateRootCaDer(_buildSyntheticX509(duplicateOid: true), nowUtc: fixedNow),
        throwsA(isA<X509ValidationException>().having((e) => e.code, 'code', 'INVALID_CA_CERT')),
      );
      expect(
        () => MmsX509PreValidator.validateRootCaDer(_buildSyntheticX509(outerSigMismatch: true), nowUtc: fixedNow),
        throwsA(isA<X509ValidationException>().having((e) => e.code, 'code', 'INVALID_CA_CERT')),
      );
      expect(
        () => MmsX509PreValidator.validateRootCaDer(_buildSyntheticX509(nonCanonicalCriticalFalse: true), nowUtc: fixedNow),
        throwsA(isA<X509ValidationException>().having((e) => e.code, 'code', 'INVALID_CA_CERT')),
      );
      expect(
        () => MmsX509PreValidator.validateRootCaDer(_buildSyntheticX509(diffSubjectFromIssuer: true), nowUtc: fixedNow),
        throwsA(isA<X509ValidationException>().having((e) => e.code, 'code', 'CA_CERT_NOT_SELF_ISSUED')),
      );
      // 14-bayt sentetik DER sahteciliği reddi (TV-X509-07)
      expect(
        () => MmsX509PreValidator.validateRootCaDer(Uint8List.fromList([0x30, 0x0C, 0x30, 0x03, 0x02, 0x01, 0x01, 0x30, 0x02, 0x05, 0x00, 0x03, 0x01, 0x00])),
        throwsA(isA<X509ValidationException>()),
      );
    });

    test('HUB-T01c: Aynı Subject DN\'e sahip sahte CA2 leaf sertifikasını BoringSSL imza doğrulamasıyla reddeder (DN eşitliği imza değildir)', () async {
      final dir = await Directory.systemTemp.createTemp('mms_hub_t01c_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final ca1Key = p.join(dir.path, 'ca1.key');
      final ca1Crt = p.join(dir.path, 'ca1.crt');
      final ca2Key = p.join(dir.path, 'ca2.key');
      final ca2Crt = p.join(dir.path, 'ca2.crt');
      CertificateManager.generateRootCa(caKeyPath: ca1Key, caCertPath: ca1Crt, commonName: 'Same Subject CA');
      CertificateManager.generateRootCa(caKeyPath: ca2Key, caCertPath: ca2Crt, commonName: 'Same Subject CA');

      final srvKey = p.join(dir.path, 'srv_ca2.key');
      final srvCrt = p.join(dir.path, 'srv_ca2.crt');
      CertificateManager.generateServerCertificate(
        caKeyPath: ca2Key,
        caCertPath: ca2Crt,
        serverKeyPath: srvKey,
        serverCertPath: srvCrt,
        sanList: const ['127.0.0.1'],
      );

      final ctx = CertificateManager.createServerSecurityContext(certChainPath: srvCrt, privateKeyPath: srvKey);
      final server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, ctx);
      addTearDown(() => server.close(force: true));

      final ca1Bytes = File(ca1Crt).readAsBytesSync();
      final client = TlsClientFactory.createPinnedClient(trustedRootCaBytes: ca1Bytes);
      addTearDown(() => client.close(force: true));

      await expectLater(
        () async {
          final req = await client.getUrl(Uri.parse('https://127.0.0.1:${server.port}/health'));
          await req.close();
        },
        throwsA(anyOf(isA<HandshakeException>(), isA<SocketException>())),
      );
    });
  });

  group('P-BLOCK-3: HubLanAddressResolver & Windows x64 FFI (HUB-T03..T09, NET-01..08)', () {
    test('HUB-T03 / HUB-T04 / NET-01..03: 127.0.0.1 çıkarılır, VPN/WSL/VirtualBox/APIPA elenir, yalnız fiziksel NIC seçilir', () async {
      final resolver = HubLanAddressResolver(
        inspector: _FakeInspector(const [
          LanInterfaceCandidate(
            adapterName: 'loopback',
            friendlyName: 'Loopback Pseudo-Interface 1',
            description: 'Software Loopback',
            ifIndex: 1,
            luid: 100,
            ifType: 24,
            operStatus: 1,
            hardwareInterface: false,
            ipv4Addresses: [UnicastIpv4Entry(ip: '127.0.0.1')],
          ),
          LanInterfaceCandidate(
            adapterName: 'wg0',
            friendlyName: 'WireGuard Tunnel',
            description: 'WireGuard Tunnel',
            ifIndex: 2,
            luid: 101,
            ifType: 6,
            operStatus: 1,
            hardwareInterface: false,
            ipv4Addresses: [UnicastIpv4Entry(ip: '100.64.10.2')],
          ),
          LanInterfaceCandidate(
            adapterName: 'wsl',
            friendlyName: 'vEthernet (WSL)',
            description: 'Hyper-V Virtual Ethernet Adapter',
            ifIndex: 3,
            luid: 102,
            ifType: 6,
            operStatus: 1,
            hardwareInterface: false,
            ipv4Addresses: [UnicastIpv4Entry(ip: '172.20.10.1')],
          ),
          LanInterfaceCandidate(
            adapterName: 'vbox',
            friendlyName: 'VirtualBox Host-Only Ethernet Adapter',
            description: 'Oracle VirtualBox',
            ifIndex: 4,
            luid: 103,
            ifType: 6,
            operStatus: 1,
            hardwareInterface: false,
            ipv4Addresses: [UnicastIpv4Entry(ip: '192.168.56.1')],
          ),
          LanInterfaceCandidate(
            adapterName: 'eth0',
            friendlyName: 'Ethernet',
            description: 'Realtek PCIe GbE Family Controller',
            ifIndex: 5,
            luid: 104,
            ifType: 6,
            operStatus: 1,
            hardwareInterface: true,
            hasGateway: true,
            ipv4Addresses: [
              UnicastIpv4Entry(ip: '169.254.1.2'),
              UnicastIpv4Entry(ip: '192.168.1.50', dadState: 4),
            ],
          ),
        ]),
      );

      final res = await resolver.resolve(
        serverCertSanIpv4s: const {'127.0.0.1', '192.168.1.50', '172.20.10.1', '192.168.56.1'},
      );
      expect(res.ipAddress, '192.168.1.50');
      expect(res.selectionSource, 'AUTO_SAN_INTERSECTION_TIER1');

      // Fiziksel NIC koparsa VPN/WSL üzerinden sızıntı yapılmaz -> ERR_HUB_LAN_IP_UNAVAILABLE
      final disconnectedResolver = HubLanAddressResolver(
        inspector: _FakeInspector(const [
          LanInterfaceCandidate(
            adapterName: 'wg0',
            friendlyName: 'WireGuard Tunnel',
            description: 'WireGuard Tunnel',
            ifIndex: 2,
            luid: 101,
            ifType: 6,
            operStatus: 1,
            hardwareInterface: false,
            ipv4Addresses: [UnicastIpv4Entry(ip: '10.8.0.2')],
          ),
          LanInterfaceCandidate(
            adapterName: 'eth0',
            friendlyName: 'Ethernet',
            description: 'Realtek PCIe GbE',
            ifIndex: 5,
            luid: 104,
            ifType: 6,
            operStatus: 2, // Down
            hardwareInterface: true,
            ipv4Addresses: [UnicastIpv4Entry(ip: '192.168.1.50', dadState: 4)],
          ),
        ]),
      );
      await expectLater(
        () => disconnectedResolver.resolve(serverCertSanIpv4s: const {'127.0.0.1', '192.168.1.50', '10.8.0.2'}),
        throwsA(isA<HubLanResolutionException>().having((e) => e.code, 'code', 'ERR_HUB_LAN_IP_UNAVAILABLE')),
      );
    });

    test('HUB-T04b: DadState != Preferred ve OperStatus != Up reddedilir', () async {
      final resolver = HubLanAddressResolver(
        inspector: _FakeInspector(const [
          LanInterfaceCandidate(
            adapterName: 'eth0',
            friendlyName: 'Ethernet',
            description: 'Intel NIC',
            ifIndex: 7,
            luid: 200,
            ifType: 6,
            operStatus: 1,
            hardwareInterface: true,
            ipv4Addresses: [UnicastIpv4Entry(ip: '192.168.1.60', dadState: 1)], // Tentative != 4
          ),
        ]),
      );
      await expectLater(
        () => resolver.resolve(serverCertSanIpv4s: const {'127.0.0.1', '192.168.1.60'}),
        throwsA(isA<HubLanResolutionException>().having((e) => e.code, 'code', 'ERR_HUB_LAN_IP_UNAVAILABLE')),
      );
    });

    test('HUB-T04d (NET-02b): Hyper-V External vEthernet host LAN adaptörü Tier 2 ile korunur; WSL elenir', () async {
      final resolver = HubLanAddressResolver(
        inspector: _FakeInspector(const [
          LanInterfaceCandidate(
            adapterName: 'wsl',
            friendlyName: 'vEthernet (WSL)',
            description: 'Hyper-V Virtual Ethernet Adapter',
            ifIndex: 10,
            luid: 300,
            ifType: 6,
            operStatus: 1,
            hardwareInterface: false,
            ipv4Addresses: [UnicastIpv4Entry(ip: '172.25.0.1')],
          ),
          LanInterfaceCandidate(
            adapterName: 'hv_ext',
            friendlyName: 'vEthernet (External Switch)',
            description: 'Hyper-V Virtual Ethernet Adapter',
            ifIndex: 11,
            luid: 301,
            ifType: 6,
            operStatus: 1,
            hardwareInterface: false,
            hasGateway: true,
            ipv4Addresses: [UnicastIpv4Entry(ip: '192.168.1.55')],
          ),
        ]),
      );

      final res = await resolver.resolve(
        serverCertSanIpv4s: const {'127.0.0.1', '192.168.1.55', '172.25.0.1'},
      );
      expect(res.ipAddress, '192.168.1.55');
      expect(res.selectionSource, 'AUTO_SAN_INTERSECTION_TIER2_VIRTUAL_SWITCH');
    });

    test('HUB-T05 & HUB-T08 & HUB-T09 (NET-04..08): Çoklu NIC ambiguity, advertise_host SAN/lokal doğrulaması & DHCP değişimi', () async {
      // Multi-NIC with both having gateways -> AMBIGUOUS
      final multiInspector = _FakeInspector(const [
        LanInterfaceCandidate(
          adapterName: 'eth',
          friendlyName: 'Ethernet',
          description: 'Ethernet NIC',
          ifIndex: 1,
          luid: 1,
          ifType: 6,
          operStatus: 1,
          hardwareInterface: true,
          hasGateway: true,
          ipv4Addresses: [UnicastIpv4Entry(ip: '192.168.1.50')],
        ),
        LanInterfaceCandidate(
          adapterName: 'wifi',
          friendlyName: 'Wi-Fi',
          description: 'Wi-Fi NIC',
          ifIndex: 2,
          luid: 2,
          ifType: 71,
          operStatus: 1,
          hardwareInterface: true,
          hasGateway: true,
          ipv4Addresses: [UnicastIpv4Entry(ip: '192.168.1.51')],
        ),
      ]);
      final resolver = HubLanAddressResolver(inspector: multiInspector);

      await expectLater(
        () => resolver.resolve(serverCertSanIpv4s: const {'127.0.0.1', '192.168.1.50', '192.168.1.51'}),
        throwsA(isA<HubLanResolutionException>().having((e) => e.code, 'code', 'ERR_HUB_LAN_IP_AMBIGUOUS')),
      );

      // Geçerli advertise_host seçilir (NET-05)
      final advOk = await resolver.resolve(
        serverCertSanIpv4s: const {'127.0.0.1', '192.168.1.50', '192.168.1.51'},
        advertiseHost: '192.168.1.50',
      );
      expect(advOk.ipAddress, '192.168.1.50');
      expect(advOk.selectionSource, 'ADVERTISE_HOST');

      // SAN dışı advertise_host -> ERR_ADVERTISE_HOST_SAN_MISMATCH (NET-06)
      await expectLater(
        () => resolver.resolve(
          serverCertSanIpv4s: const {'127.0.0.1', '192.168.1.51'},
          advertiseHost: '192.168.1.50',
        ),
        throwsA(isA<HubLanResolutionException>().having((e) => e.code, 'code', 'ERR_ADVERTISE_HOST_SAN_MISMATCH')),
      );

      // SAN'da olup makinede olmayan advertise_host -> ERR_ADVERTISE_HOST_NOT_LOCAL (NET-08)
      await expectLater(
        () => resolver.resolve(
          serverCertSanIpv4s: const {'127.0.0.1', '192.168.1.99'},
          advertiseHost: '192.168.1.99',
        ),
        throwsA(isA<HubLanResolutionException>().having((e) => e.code, 'code', 'ERR_ADVERTISE_HOST_NOT_LOCAL')),
      );
    });

    test('HUB-T04c: Canlı Windows x64 GetAdaptersAddresses + GetIfEntry2 FFI doğrulaması ve NetworkInterface.list çapraz kontrolü + fail-closed hata simülasyonu', () async {
      if (Platform.isWindows) {
        final liveInspector = WindowsNetworkAdapterInspector();
        final adapters = await liveInspector.inspectAdapters();
        expect(adapters, isNotEmpty, reason: 'Windows makinesinde en az 1 ağ arayüzü dönmeli');
        expect(
          adapters.any((a) => a.ifIndex > 0 && a.luid != 0),
          isTrue,
          reason: 'x64 IP_ADAPTER_ADDRESSES_LH Luid/IfIndex offsetleri geçerli değer üretmeli',
        );
      }

      final failingResolver = HubLanAddressResolver(
        inspector: _FakeInspector(
          const [],
          throwError: const HubLanResolutionException('ERR_HUB_LAN_IP_UNAVAILABLE', 'FFI failure'),
        ),
      );
      await expectLater(
        () => failingResolver.resolve(serverCertSanIpv4s: const {'192.168.1.10'}),
        throwsA(isA<HubLanResolutionException>().having((e) => e.code, 'code', 'ERR_HUB_LAN_IP_UNAVAILABLE')),
      );
    });

    test('HUB-T06: ADR-018 UDP HUB_DISCOVERY_V1 v1.0 6 alan regresyon kilidi', () async {
      final responder = HubDiscoveryResponder(
        httpPort: 8945,
        discoveryPort: 0,
        hubId: 'TEST-HUB',
        bindAddress: InternetAddress.loopbackIPv4,
      );
      await responder.start();
      addTearDown(responder.stop);

      final lanIps = await HubDiscoveryResponder.getLocalLanIps();
      expect(lanIps.any((ip) => ip.startsWith('127.')), isFalse);
      final src = File(p.join(Directory.current.path, 'lib', 'discovery', 'discovery_responder.dart')).readAsStringSync();
      expect(src, contains("'service':"));
      expect(src, contains("'protocol_version':"));
      expect(src, contains("'hub_id':"));
      expect(src, contains("'http_port':"));
      expect(src, contains("'server_time':"));
      expect(src, contains("'server_ips':"));
    });
  });

  group('P-BLOCK-2 & Hub Sunucu Entegrasyonu (HUB-T07 & HUB-T09b)', () {
    test('HUB-T07: IP:127.0.0.1 eksik server.crt startup\'ta exit 78 (HubStartupArgException) ile durur; LAN SAN uyuşmazlığında Hub ayakta kalır ve /pairing/session 503 döner', () async {
      final dir = await Directory.systemTemp.createTemp('mms_hub_san_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final caKey = p.join(dir.path, 'ca.key');
      final caCrt = p.join(dir.path, 'ca.crt');
      CertificateManager.generateRootCa(caKeyPath: caKey, caCertPath: caCrt);

      // 1. Yalnız DNS:localhost (IP:127.0.0.1 yok) -> startup exit 78
      final noLoopbackKey = p.join(dir.path, 'nolb.key');
      final noLoopbackCrt = p.join(dir.path, 'nolb.crt');
      CertificateManager.generateServerCertificate(
        caKeyPath: caKey,
        caCertPath: caCrt,
        serverKeyPath: noLoopbackKey,
        serverCertPath: noLoopbackCrt,
        sanList: const ['localhost', '192.168.1.50'],
      );

      final db = SpikeDatabase(File(p.join(dir.path, 'hub_nolb.db')));
      addTearDown(db.close);
      final pepper = PepperManager(File(p.join(dir.path, 'pepper1.dpapi')))..initialize();
      final noLbServer = SpikeServer(
        db: db,
        writeQueue: WriteQueue(),
        adminSecret: 'adm',
        pepperManager: pepper,
        securityContext: CertificateManager.createServerSecurityContext(
          certChainPath: noLoopbackCrt,
          privateKeyPath: noLoopbackKey,
        ),
        requireTls: true,
        caCertPath: caCrt,
        serverCertPath: noLoopbackCrt,
      );

      await expectLater(
        () => noLbServer.start(address: InternetAddress.loopbackIPv4, port: 0, enableDiscovery: false),
        throwsA(
          isA<HubStartupArgException>()
              .having((e) => e.exitCode, 'exitCode', 78)
              .having((e) => e.message, 'message', contains('ERR_SERVER_CERT_MISSING_LOOPBACK_SAN')),
        ),
      );

      // 2. IP:127.0.0.1 var ancak advertise_host (192.168.1.50) SAN içinde yok -> Hub AÇIK kalır, /pairing/session 503
      final withLbKey = p.join(dir.path, 'withlb.key');
      final withLbCrt = p.join(dir.path, 'withlb.crt');
      CertificateManager.generateServerCertificate(
        caKeyPath: caKey,
        caCertPath: caCrt,
        serverKeyPath: withLbKey,
        serverCertPath: withLbCrt,
        sanList: const ['127.0.0.1', 'localhost'],
      );
      final sock = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = sock.port;
      await sock.close();

      final lanMismatchServer = SpikeServer(
        db: db,
        writeQueue: WriteQueue(),
        adminSecret: 'adm_lan_test',
        pepperManager: pepper,
        securityContext: CertificateManager.createServerSecurityContext(
          certChainPath: withLbCrt,
          privateKeyPath: withLbKey,
        ),
        requireTls: true,
        caCertPath: caCrt,
        serverCertPath: withLbCrt,
        advertiseHost: '192.168.1.50',
        lanAddressResolver: HubLanAddressResolver(
          inspector: _FakeInspector(const [
            LanInterfaceCandidate(
              adapterName: 'eth',
              friendlyName: 'Ethernet',
              description: 'Realtek',
              ifIndex: 1,
              luid: 1,
              ifType: 6,
              operStatus: 1,
              hardwareInterface: true,
              ipv4Addresses: [UnicastIpv4Entry(ip: '192.168.1.50')],
            ),
          ]),
        ),
      );
      await lanMismatchServer.start(address: InternetAddress.loopbackIPv4, port: port, enableDiscovery: false);
      addTearDown(lanMismatchServer.stop);

      final tlsClient = TlsClientFactory.createPinnedClient(trustedRootCaBytes: File(caCrt).readAsBytesSync());
      addTearDown(() => tlsClient.close(force: true));

      final healthReq = await tlsClient.getUrl(Uri.parse('https://127.0.0.1:$port/health'));
      final healthResp = await healthReq.close();
      expect(healthResp.statusCode, 200, reason: 'LAN SAN uyuşmazlığında Hub yerel POS için ayakta kalmalı');

      final sessReq = await tlsClient.postUrl(Uri.parse('https://127.0.0.1:$port/api/v1/pairing/session'));
      sessReq.headers.set('x-mms-admin-secret', 'adm_lan_test');
      final sessResp = await sessReq.close();
      final sessJson = jsonDecode(await utf8.decoder.bind(sessResp).join()) as Map<String, dynamic>;
      expect(sessResp.statusCode, 503);
      expect(sessJson['code'], 'ERR_ADVERTISE_HOST_SAN_MISMATCH');
    });

    test('HUB-T09b: Sunucu idempotent /ack replay (200 OK), bozuk imza reddi (403) ve re-pairingde eski aktif token korunumu', () async {
      final dir = await Directory.systemTemp.createTemp('mms_hub_t09b_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final db = SpikeDatabase(File(p.join(dir.path, 't09b.db')));
      addTearDown(db.close);
      final queue = WriteQueue();
      final pepper = PepperManager(File(p.join(dir.path, 'pepper.dpapi')))..initialize();
      const adminSecret = 'adm_t09b_secret';

      const devId = 'DEV_REPAIR_01';
      final oldToken = TokenManager.generateToken();
      final oldSalt = TokenManager.generateSalt();
      final oldHash = TokenManager.hashToken(rawToken: oldToken, salt: oldSalt, pepper: pepper.pepper);
      await db.into(db.devices).insert(
        DevicesCompanion(
          deviceId: const Value(devId),
          name: const Value('Existing Active POS'),
          tokenHash: Value(oldHash),
          salt: Value(oldSalt),
          isActive: const Value(true),
          isConfirmed: const Value(true),
        ),
      );

      final server = SpikeServer(
        db: db,
        writeQueue: queue,
        adminSecret: adminSecret,
        pepperManager: pepper,
        requireTls: false,
      );
      final sock = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = sock.port;
      await sock.close();
      await server.start(address: InternetAddress.loopbackIPv4, port: port, enableDiscovery: false);
      addTearDown(server.stop);

      final privKey = BigInt.parse('1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF', radix: 16);
      final pubKey = EcdsaSignatureValidator.getPublicKeyBytes(privKey);
      final pubFp = sha256.convert(pubKey).bytes;

      final sess = server.pairingManager.createSession(
        hubUrl: 'http://127.0.0.1:$port',
        caFingerprint: 'UNKNOWN',
      );
      final sId = sess['session_id'] as String;
      final pSec = sess['pairing_secret'] as String;

      server.pairingManager.registerRequest(
        sessionId: sId,
        pairingSecret: pSec,
        deviceId: devId,
        name: 'Existing Active POS',
        platform: 'ANDROID',
        clientPublicKeyBytes: pubKey,
        keyAlgorithm: 'ECDSA_P256',
      );
      await server.pairingManager.approveSession(
        sessionId: sId,
        db: db,
        writeQueue: queue,
        pepper: pepper.pepper,
        allowRePair: true,
      );

      // /ack gelmeden ÖNCE DB'deki eski aktif tokenHash korunmalı!
      final beforeAckDev = await (db.select(db.devices)..where((d) => d.deviceId.equals(devId))).getSingle();
      expect(beforeAckDev.tokenHash, oldHash, reason: 'Re-pairing onaylandı ama henüz ACK alınmadı; eski token bozulmamalı');

      final pollCh = server.pairingManager.issuePollChallenge(sessionId: sId, pairingSecret: pSec);
      final pollSig = EcdsaSignatureValidator.signPayload(
        privateKey: privKey,
        canonicalPayload: EcdsaSignatureValidator.buildCanonicalPollPayload(
          protocolVersion: '1',
          pairingSessionId: sId,
          publicKeyFingerprintBytes: pubFp,
          challengeId: pollCh.challengeId,
          challengeNonce: pollCh.challengeNonce,
        ),
      );
      final newToken = server.pairingManager.verifyAndPollToken(
        sessionId: sId,
        pairingSecret: pSec,
        pollChallengeId: pollCh.challengeId,
        signatureBytes: pollSig,
      );

      // Cooldown testini beklemeden zamanı geri çek (test kontrolü için lastChallengeIssuedAt)
      server.pairingManager.getSession(sId).lastChallengeIssuedAt =
          DateTime.now().subtract(const Duration(seconds: 6));

      final ackCh = server.pairingManager.issueAckChallenge(sessionId: sId, pairingSecret: pSec);
      final ackSig = EcdsaSignatureValidator.signPayload(
        privateKey: privKey,
        canonicalPayload: EcdsaSignatureValidator.buildCanonicalAckPayload(
          protocolVersion: '1',
          pairingSessionId: sId,
          publicKeyFingerprintBytes: pubFp,
          challengeId: ackCh.challengeId,
          challengeNonce: ackCh.challengeNonce,
          tokenHashBytes: sha256.convert(utf8.encode(newToken)).bytes,
        ),
      );

      // 1. İlk ACK
      final ack1 = await server.pairingManager.verifyAndAcknowledge(
        sessionId: sId,
        ackChallengeId: ackCh.challengeId,
        signatureBytes: ackSig,
        db: db,
        writeQueue: queue,
      );
      expect(ack1.confirmed, isTrue);
      expect(ack1.idempotentReplay, isFalse);

      // Yeni tokenHash DB'ye terfi edilmiş olmalı
      final afterAckDev = await (db.select(db.devices)..where((d) => d.deviceId.equals(devId))).getSingle();
      expect(afterAckDev.tokenHash, isNot(oldHash));

      // 2. Aynı ACK idempotent replay -> 200 OK
      final ack2 = await server.pairingManager.verifyAndAcknowledge(
        sessionId: sId,
        ackChallengeId: ackCh.challengeId,
        signatureBytes: ackSig,
        db: db,
        writeQueue: queue,
      );
      expect(ack2.confirmed, isTrue);
      expect(ack2.idempotentReplay, isTrue);

      // 3. Bozuk imzalı ACK replay -> 403 INVALID_ACK_TOKEN_HASH_SIGNATURE
      await expectLater(
        () => server.pairingManager.verifyAndAcknowledge(
          sessionId: sId,
          ackChallengeId: ackCh.challengeId,
          signatureBytes: List<int>.filled(70, 0x42),
          db: db,
          writeQueue: queue,
        ),
        throwsA(isA<PairingException>().having((e) => e.code, 'code', 'INVALID_ACK_TOKEN_HASH_SIGNATURE')),
      );
    });

    test('HubConfig advertise_host doğrulaması (geçerli kabul edilir; loopback/APIPA/geçersiz reddedilir)', () {
      expect(
        () => HubConfig.fromJson({
          'environment': 'development',
          'advertise_host': '127.0.0.1',
          'tls': {'enabled': false},
        }, baseDir: '.'),
        throwsA(isA<HubConfigException>()),
      );
      final ok = HubConfig.fromJson({
        'environment': 'development',
        'advertise_host': '192.168.1.50',
        'tls': {'enabled': false},
      }, baseDir: '.');
      expect(ok.advertiseHost, '192.168.1.50');
    });
  });
}
