import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

class HubLanResolutionException implements Exception {
  final String code;
  final String message;

  const HubLanResolutionException(this.code, this.message);

  @override
  String toString() => 'HubLanResolutionException($code): $message';
}

class UnicastIpv4Entry {
  final String ip;
  final int dadState; // Windows IpDadStatePreferred == 4

  const UnicastIpv4Entry({
    required this.ip,
    this.dadState = 4,
  });
}

/// Bir ağ adaptörünün `GetAdaptersAddresses` + `GetIfEntry2` (`MIB_IF_ROW2`)
/// birleşiminden elde edilen donanım ve IP yaşam döngüsü özeti.
class LanInterfaceCandidate {
  final String adapterName;
  final String friendlyName;
  final String description;
  final int ifIndex;
  final int luid;
  final int ifType; // 6: Ethernet, 71: Wi-Fi, 24: Loopback, 131: Tunnel, 23: PPP
  final int operStatus; // 1: IfOperStatusUp
  final int tunnelType; // 0: TUNNEL_TYPE_NONE
  final bool hardwareInterface; // MIB_IF_ROW2.InterfaceAndOperStatusFlags.HardwareInterface
  final bool filterInterface;
  final bool connectorPresent;
  final bool hasGateway;
  final List<UnicastIpv4Entry> ipv4Addresses;

  const LanInterfaceCandidate({
    required this.adapterName,
    required this.friendlyName,
    required this.description,
    required this.ifIndex,
    required this.luid,
    required this.ifType,
    required this.operStatus,
    this.tunnelType = 0,
    required this.hardwareInterface,
    this.filterInterface = false,
    this.connectorPresent = true,
    this.hasGateway = false,
    required this.ipv4Addresses,
  });
}

class ResolvedHubLanAddress {
  final String ipAddress;
  final String selectionSource; // ADVERTISE_HOST | AUTO_SAN_INTERSECTION_TIER1 | AUTO_SAN_INTERSECTION_TIER2_VIRTUAL_SWITCH
  final String? adapterName;

  const ResolvedHubLanAddress({
    required this.ipAddress,
    required this.selectionSource,
    this.adapterName,
  });
}

abstract class NetworkAdapterInspector {
  Future<List<LanInterfaceCandidate>> inspectAdapters();
}

// --- Native Windows iphlpapi.dll FFI Bildirimleri (Windows x64 WinSDK 10.0.26100.0) ---

typedef _GetAdaptersAddressesNative = Uint32 Function(
  Uint32 family,
  Uint32 flags,
  Pointer<Void> reserved,
  Pointer<Uint8> adapterAddresses,
  Pointer<Uint32> sizePointer,
);
typedef _GetAdaptersAddressesDart = int Function(
  int family,
  int flags,
  Pointer<Void> reserved,
  Pointer<Uint8> adapterAddresses,
  Pointer<Uint32> sizePointer,
);

typedef _GetIfEntry2Native = Uint32 Function(Pointer<Uint8> row);
typedef _GetIfEntry2Dart = int Function(Pointer<Uint8> row);

// Microsoft CRT (ucrtbase / msvcrt) malloc/free için yerel bellek yönetimi
final class _WinAlloc {
  static final DynamicLibrary _crt = DynamicLibrary.open('ucrtbase.dll');

  static final void Function(Pointer<Void> ptr) free = _crt
      .lookup<NativeFunction<Void Function(Pointer<Void>)>>('free')
      .asFunction<void Function(Pointer<Void>)>();

  static final Pointer<Uint8> Function(int count, int size) _rawCalloc =
      _crt
          .lookup<NativeFunction<Pointer<Uint8> Function(IntPtr, IntPtr)>>('calloc')
          .asFunction<Pointer<Uint8> Function(int, int)>();

  static Pointer<Uint8> callocZero(int bytes) {
    final ptr = _rawCalloc(bytes, 1);
    if (ptr == nullptr) {
      throw const HubLanResolutionException(
        'ERR_HUB_LAN_IP_UNAVAILABLE',
        'Windows ağ adaptörü sorgusu için bellek ayrılamadı.',
      );
    }
    return ptr;
  }
}

/// Gerçek Windows x64 `iphlpapi.dll` (`GetAdaptersAddresses` + `GetIfEntry2`) denetleyicisi.
///
/// Windows 10 SDK (`IPTypes.h` + `netioapi.h`) 64-bit ABI offset'lerini kullanır ve
/// çalışma zamanında Dart'ın yerleşik `NetworkInterface.list` çıktısıyla çapraz doğrulama yapar.
/// Herhangi bir FFI hatası veya çapraz kontrol uyuşmazlığında fail-closed hata fırlatır.
class WindowsNetworkAdapterInspector implements NetworkAdapterInspector {
  static const int _afInet = 2;
  static const int _gaaFlagIncludeGateways = 0x0080;
  static const int _errorSuccess = 0;
  static const int _errorBufferOverflow = 111;

  // IP_ADAPTER_ADDRESSES_LH x64 byte offset'leri (IPTypes.h)
  static const int _aaIfIndex = 4;
  static const int _aaNext = 8;
  static const int _aaAdapterNamePtr = 16;
  static const int _aaFirstUnicastPtr = 24;
  static const int _aaDescriptionPtr = 64;
  static const int _aaFriendlyNamePtr = 72;
  static const int _aaIfType = 100;
  static const int _aaOperStatus = 104;
  static const int _aaFirstGatewayPtr = 208;
  static const int _aaLuid = 224;
  static const int _aaTunnelType = 272;

  // IP_ADAPTER_UNICAST_ADDRESS_LH x64 byte offset'leri (IPTypes.h)
  static const int _uaNext = 8;
  static const int _uaSockaddrPtr = 16;
  static const int _uaSockaddrLen = 24;
  static const int _uaDadState = 40;

  // MIB_IF_ROW2 x64 byte offset'leri (netioapi.h; sizeof == 1352)
  static const int _mibRowSize = 1408; // Hizalamalı güvenli buffer boyutu
  static const int _mibInterfaceLuid = 0;
  static const int _mibInterfaceIndex = 8;
  static const int _mibTunnelType = 1132;
  static const int _mibFlagsByte = 1152;
  static const int _mibOperStatus = 1156;

  static DynamicLibrary? _iphlpapi;
  static _GetAdaptersAddressesDart? _getAdaptersAddresses;
  static _GetIfEntry2Dart? _getIfEntry2;

  static void _ensureLoaded() {
    if (!Platform.isWindows) {
      throw const HubLanResolutionException(
        'ERR_HUB_LAN_IP_UNAVAILABLE',
        'WindowsNetworkAdapterInspector yalnızca Windows üzerinde çalıştırılabilir.',
      );
    }
    _iphlpapi ??= DynamicLibrary.open('iphlpapi.dll');
    _getAdaptersAddresses ??= _iphlpapi!
        .lookup<NativeFunction<_GetAdaptersAddressesNative>>('GetAdaptersAddresses')
        .asFunction<_GetAdaptersAddressesDart>();
    _getIfEntry2 ??= _iphlpapi!
        .lookup<NativeFunction<_GetIfEntry2Native>>('GetIfEntry2')
        .asFunction<_GetIfEntry2Dart>();
  }

  static String _readUtf16String(int ptrAddr, {int maxChars = 512}) {
    if (ptrAddr == 0) return '';
    final ptr = Pointer<Uint16>.fromAddress(ptrAddr);
    final codeUnits = <int>[];
    for (var i = 0; i < maxChars; i++) {
      final ch = ptr[i];
      if (ch == 0) break;
      codeUnits.add(ch);
    }
    return String.fromCharCodes(codeUnits);
  }

  static String _readAsciiString(int ptrAddr, {int maxChars = 256}) {
    if (ptrAddr == 0) return '';
    final ptr = Pointer<Uint8>.fromAddress(ptrAddr);
    final bytes = <int>[];
    for (var i = 0; i < maxChars; i++) {
      final b = ptr[i];
      if (b == 0) break;
      bytes.add(b);
    }
    return String.fromCharCodes(bytes);
  }

  static Uint8List _viewBytes(int ptrAddr, int length) {
    final ptr = Pointer<Uint8>.fromAddress(ptrAddr);
    return ptr.asTypedList(length);
  }

  @override
  Future<List<LanInterfaceCandidate>> inspectAdapters() async {
    _ensureLoaded();

    final sizePtr = _WinAlloc.callocZero(4).cast<Uint32>();
    Pointer<Uint8> buffer = nullptr;
    try {
      var bufSize = 16384;
      buffer = _WinAlloc.callocZero(bufSize);
      sizePtr.value = bufSize;

      var status = _getAdaptersAddresses!(
        _afInet,
        _gaaFlagIncludeGateways,
        nullptr,
        buffer,
        sizePtr,
      );
      var attempts = 0;
      while (status == _errorBufferOverflow && attempts < 4) {
        attempts++;
        _WinAlloc.free(buffer.cast<Void>());
        buffer = nullptr;
        bufSize = sizePtr.value + 4096;
        buffer = _WinAlloc.callocZero(bufSize);
        sizePtr.value = bufSize;
        status = _getAdaptersAddresses!(
          _afInet,
          _gaaFlagIncludeGateways,
          nullptr,
          buffer,
          sizePtr,
        );
      }

      if (status != _errorSuccess) {
        throw HubLanResolutionException(
          'ERR_HUB_LAN_IP_UNAVAILABLE',
          'GetAdaptersAddresses başarısız oldu (hata kodu=$status).',
        );
      }

      final candidates = <LanInterfaceCandidate>[];
      final mibRow = _WinAlloc.callocZero(_mibRowSize);
      try {
        var curAddr = buffer.address;
        while (curAddr != 0) {
          final node = _viewBytes(curAddr, 280);
          final bd = ByteData.sublistView(node);

          final ifIndex = bd.getUint32(_aaIfIndex, Endian.little);
          final nextAddr = bd.getUint64(_aaNext, Endian.little);
          final adapterNamePtr = bd.getUint64(_aaAdapterNamePtr, Endian.little);
          final firstUnicastPtr = bd.getUint64(_aaFirstUnicastPtr, Endian.little);
          final descriptionPtr = bd.getUint64(_aaDescriptionPtr, Endian.little);
          final friendlyNamePtr = bd.getUint64(_aaFriendlyNamePtr, Endian.little);
          final ifType = bd.getUint32(_aaIfType, Endian.little);
          final operStatus = bd.getInt32(_aaOperStatus, Endian.little);
          final firstGatewayPtr = bd.getUint64(_aaFirstGatewayPtr, Endian.little);
          final luid = bd.getUint64(_aaLuid, Endian.little);
          var tunnelType = bd.getInt32(_aaTunnelType, Endian.little);

          // MIB_IF_ROW2 üzerinden GetIfEntry2 donanım doğrulaması
          mibRow.asTypedList(_mibRowSize).fillRange(0, _mibRowSize, 0);
          final mibBd = ByteData.sublistView(mibRow.asTypedList(_mibRowSize));
          mibBd.setUint64(_mibInterfaceLuid, luid, Endian.little);
          mibBd.setUint32(_mibInterfaceIndex, ifIndex, Endian.little);

          var hardwareInterface = false;
          var filterInterface = false;
          var connectorPresent = false;
          var effectiveOperStatus = operStatus;

          final ifEntryRes = _getIfEntry2!(mibRow);
          if (ifEntryRes != _errorSuccess) {
            throw HubLanResolutionException(
              'ERR_HUB_LAN_IP_UNAVAILABLE',
              'GetIfEntry2 donanım doğrulaması başarısız (ifIndex=$ifIndex, err=$ifEntryRes).',
            );
          }

          final returnedIndex = mibBd.getUint32(_mibInterfaceIndex, Endian.little);
          if (returnedIndex != ifIndex) {
            throw HubLanResolutionException(
              'ERR_HUB_LAN_IP_UNAVAILABLE',
              'FFI MIB_IF_ROW2 IfIndex çapraz kontrol uyuşmazlığı ($returnedIndex != $ifIndex).',
            );
          }
          final flagsByte = mibBd.getUint8(_mibFlagsByte);
          hardwareInterface = (flagsByte & 0x01) != 0;
          filterInterface = (flagsByte & 0x02) != 0;
          connectorPresent = (flagsByte & 0x04) != 0;
          tunnelType = mibBd.getUint32(_mibTunnelType, Endian.little);
          effectiveOperStatus = mibBd.getInt32(_mibOperStatus, Endian.little);

          // Unicast IPv4 adreslerini topla
          final unicasts = <UnicastIpv4Entry>[];
          var uaPtr = firstUnicastPtr;
          while (uaPtr != 0) {
            final ua = _viewBytes(uaPtr, 64);
            final uaBd = ByteData.sublistView(ua);
            final uaNext = uaBd.getUint64(_uaNext, Endian.little);
            final sockAddrPtr = uaBd.getUint64(_uaSockaddrPtr, Endian.little);
            final sockAddrLen = uaBd.getInt32(_uaSockaddrLen, Endian.little);
            final dadState = uaBd.getInt32(_uaDadState, Endian.little);

            if (sockAddrPtr != 0 && sockAddrLen >= 8) {
              final sa = _viewBytes(sockAddrPtr, 16);
              final saBd = ByteData.sublistView(sa);
              final family = saBd.getUint16(0, Endian.little);
              if (family == _afInet) {
                final ip = '${sa[4]}.${sa[5]}.${sa[6]}.${sa[7]}';
                unicasts.add(UnicastIpv4Entry(ip: ip, dadState: dadState));
              }
            }
            uaPtr = uaNext;
          }

          candidates.add(LanInterfaceCandidate(
            adapterName: _readAsciiString(adapterNamePtr),
            friendlyName: _readUtf16String(friendlyNamePtr),
            description: _readUtf16String(descriptionPtr),
            ifIndex: ifIndex,
            luid: luid,
            ifType: ifType,
            operStatus: effectiveOperStatus,
            tunnelType: tunnelType,
            hardwareInterface: hardwareInterface,
            filterInterface: filterInterface,
            connectorPresent: connectorPresent,
            hasGateway: firstGatewayPtr != 0,
            ipv4Addresses: unicasts,
          ));

          curAddr = nextAddr;
        }
      } finally {
        _WinAlloc.free(mibRow.cast<Void>());
      }

      // Çalışma zamanı çapraz doğrulaması: Dart NetworkInterface.list(IPv4)
      final stdInterfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
        includeLoopback: false,
      );
      final stdIpsByIndex = <int, Set<String>>{};
      for (final ni in stdInterfaces) {
        stdIpsByIndex[ni.index] = ni.addresses.map((a) => a.address).toSet();
      }
      for (final c in candidates) {
        if (c.operStatus != 1 || c.ifType == 24) continue;
        final stdSet = stdIpsByIndex[c.ifIndex];
        if (stdSet == null) continue;
        for (final entry in c.ipv4Addresses) {
          if (entry.dadState == 4 &&
              !entry.ip.startsWith('127.') &&
              !entry.ip.startsWith('169.254.') &&
              !stdSet.contains(entry.ip)) {
            throw HubLanResolutionException(
              'ERR_HUB_LAN_IP_UNAVAILABLE',
              'FFI IPv4 (${entry.ip}, ifIndex=${c.ifIndex}) ile NetworkInterface.list uyuşmadı.',
            );
          }
        }
      }

      return candidates;
    } finally {
      if (buffer != nullptr) _WinAlloc.free(buffer.cast<Void>());
      _WinAlloc.free(sizePtr.cast<Void>());
    }
  }
}

/// `P-BLOCK-3` (`DEC-REV-4`) Hub LAN IP Çözümleyici.
///
/// İki kademeli fiziksel + host LAN sanal anahtar (Hyper-V External vEthernet) seçimi,
/// loopback/APIPA/VPN dışlama ve `advertise_host` çift doğrulaması (SAN + canlı yerel IP)
/// uygular. Loopback (`127.x`) hiçbir koşulda LAN adresi olarak döndürülmez.
class HubLanAddressResolver {
  static const int operStatusUp = 1;
  static const int dadStatePreferred = 4;
  static const Set<int> allowedLanIfTypes = <int>{6, 71}; // Ethernet (6), Wi-Fi (71)

  static const List<String> _excludedKeywords = <String>[
    'wireguard',
    'wintun',
    'tap-windows',
    'openvpn',
    'zerotier',
    'tailscale',
    'nordlynx',
    'wsl',
    'default switch',
    'docker',
    'virtualbox',
    'vbox',
    'vmware',
    'vmnet',
    'pseudo',
    'teredo',
    '6to4',
    'ip-https',
    'loopback',
    'vethernet (internal)',
    'vethernet (private)',
    'host-only',
  ];

  final NetworkAdapterInspector inspector;

  const HubLanAddressResolver({required this.inspector});

  static bool isDisqualifiedIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return true;
    final octets = <int>[];
    for (final p in parts) {
      final v = int.tryParse(p);
      if (v == null || v < 0 || v > 255) return true;
      octets.add(v);
    }
    final o0 = octets[0];
    final o1 = octets[1];
    if (o0 == 127) return true; // 127.0.0.0/8 loopback
    if (o0 == 0) return true; // 0.0.0.0/8
    if (o0 == 169 && o1 == 254) return true; // 169.254.0.0/16 APIPA
    if (o0 >= 224) return true; // Multicast + broadcast
    if (o0 == 100 && o1 >= 64 && o1 <= 127) return true; // 100.64.0.0/10 CGNAT / Tailscale
    if (o0 == 192 && o1 == 168 && octets[2] == 56) return true; // VirtualBox Host-Only
    return false;
  }

  static bool isRfc1918PrivateLan(String ip) {
    if (isDisqualifiedIpv4(ip)) return false;
    final octets = ip.split('.').map(int.parse).toList();
    if (octets[0] == 10) return true;
    if (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) return true;
    if (octets[0] == 192 && octets[1] == 168) return true;
    return false;
  }

  static bool _hasExcludedKeyword(LanInterfaceCandidate c) {
    final hay = '${c.friendlyName} ${c.description} ${c.adapterName}'.toLowerCase();
    return _excludedKeywords.any(hay.contains);
  }

  Future<ResolvedHubLanAddress> resolve({
    required Set<String> serverCertSanIpv4s,
    String? advertiseHost,
  }) async {
    // SAN kesişimi öncesinde loopback/APIPA adreslerini temizle.
    final lanSanIps = serverCertSanIpv4s
        .where((ip) => !isDisqualifiedIpv4(ip))
        .toSet();

    final adapters = await inspector.inspectAdapters();

    // 1. Açık advertise_host yapılandırması varsa çift doğrulama (SAN + Yerel Canlı IP)
    if (advertiseHost != null && advertiseHost.trim().isNotEmpty) {
      final hostIp = advertiseHost.trim();
      if (isDisqualifiedIpv4(hostIp)) {
        throw HubLanResolutionException(
          'ERR_ADVERTISE_HOST_NOT_LOCAL',
          'advertise_host ($hostIp) geçerli bir LAN IPv4 adresi olamaz.',
        );
      }
      if (!lanSanIps.contains(hostIp)) {
        throw HubLanResolutionException(
          'ERR_ADVERTISE_HOST_SAN_MISMATCH',
          'Yapılandırılan advertise_host ($hostIp) server.crt SAN IPv4 listesinde bulunmuyor.',
        );
      }
      LanInterfaceCandidate? localOwner;
      for (final c in adapters) {
        if (c.operStatus != operStatusUp || c.ifType == 24) continue;
        final hasActiveIp = c.ipv4Addresses.any(
          (u) => u.dadState == dadStatePreferred && u.ip == hostIp,
        );
        if (hasActiveIp) {
          localOwner = c;
          break;
        }
      }
      if (localOwner == null) {
        throw HubLanResolutionException(
          'ERR_ADVERTISE_HOST_NOT_LOCAL',
          'Yapılandırılan advertise_host ($hostIp) bu makinede aktif bir ağ arayüzüne atanmış değil.',
        );
      }
      return ResolvedHubLanAddress(
        ipAddress: hostIp,
        selectionSource: 'ADVERTISE_HOST',
        adapterName: localOwner.friendlyName,
      );
    }

    if (lanSanIps.isEmpty) {
      throw const HubLanResolutionException(
        'ERR_HUB_LAN_IP_UNAVAILABLE',
        'Sunucu sertifikası (server.crt) loopback dışında geçerli bir LAN IPv4 SAN kaydı içermiyor.',
      );
    }

    final tier1Matches = <({String ip, LanInterfaceCandidate adapter})>[];
    final tier2Matches = <({String ip, LanInterfaceCandidate adapter})>[];

    for (final c in adapters) {
      if (c.operStatus != operStatusUp) continue;
      if (!allowedLanIfTypes.contains(c.ifType)) continue;
      if (c.tunnelType != 0) continue;
      if (_hasExcludedKeyword(c)) continue;

      for (final u in c.ipv4Addresses) {
        if (u.dadState != dadStatePreferred) continue;
        if (isDisqualifiedIpv4(u.ip)) continue;
        if (!lanSanIps.contains(u.ip)) continue;

        if (c.hardwareInterface) {
          tier1Matches.add((ip: u.ip, adapter: c));
        } else if (c.ifType == 6 && isRfc1918PrivateLan(u.ip)) {
          // Hyper-V External Virtual Switch (vEthernet) gibi gerçek host LAN köprüsü
          tier2Matches.add((ip: u.ip, adapter: c));
        }
      }
    }

    if (tier1Matches.isNotEmpty) {
      return _pickUniqueOrGateway(
        tier1Matches,
        source: 'AUTO_SAN_INTERSECTION_TIER1',
      );
    }
    if (tier2Matches.isNotEmpty) {
      return _pickUniqueOrGateway(
        tier2Matches,
        source: 'AUTO_SAN_INTERSECTION_TIER2_VIRTUAL_SWITCH',
      );
    }

    throw const HubLanResolutionException(
      'ERR_HUB_LAN_IP_UNAVAILABLE',
      'server.crt SAN listesiyle eşleşen aktif yerel ağ (LAN) adaptörü bulunamadı.',
    );
  }

  static ResolvedHubLanAddress _pickUniqueOrGateway(
    List<({String ip, LanInterfaceCandidate adapter})> matches, {
    required String source,
  }) {
    final distinctIps = matches.map((m) => m.ip).toSet();
    if (distinctIps.length == 1) {
      return ResolvedHubLanAddress(
        ipAddress: matches.first.ip,
        selectionSource: source,
        adapterName: matches.first.adapter.friendlyName,
      );
    }

    // Tek aktif default gateway sahibi olan IP'ye bak (ancak iki farklı ağda birden
    // gateway varsa asla keyfi seçme -> ERR_HUB_LAN_IP_AMBIGUOUS).
    final withGateway = matches.where((m) => m.adapter.hasGateway).toList();
    final gatewayIps = withGateway.map((m) => m.ip).toSet();
    if (gatewayIps.length == 1) {
      return ResolvedHubLanAddress(
        ipAddress: withGateway.first.ip,
        selectionSource: source,
        adapterName: withGateway.first.adapter.friendlyName,
      );
    }

    throw HubLanResolutionException(
      'ERR_HUB_LAN_IP_AMBIGUOUS',
      'Birden fazla aktif LAN IP adresi server.crt SAN listesiyle eşleşiyor: '
      '${distinctIps.join(', ')}. hub_config.json içinde advertise_host belirtin.',
    );
  }

  /// UDP Discovery yanıtı için aktif, doğrulanmış fiziksel/yerel LAN IPv4
  /// adreslerini öncelik sırasıyla çözer; VirtualBox Host-Only, Hyper-V
  /// Default Switch, VPN, tunnel, loopback ve APIPA arayüzlerini dışlar.
  Future<List<String>> resolveDiscoveryLanIps({
    String? advertiseHost,
    Set<String>? serverCertSanIpv4s,
  }) async {
    final adapters = await inspector.inspectAdapters();
    return selectDiscoveryLanIpsFromCandidates(
      adapters,
      advertiseHost: advertiseHost,
      serverCertSanIpv4s: serverCertSanIpv4s,
    );
  }

  /// Saf deterministik keşif IPv4 seçimi (birim testleri ve Windows denetleyicisi paylaşır).
  static List<String> selectDiscoveryLanIpsFromCandidates(
    List<LanInterfaceCandidate> adapters, {
    String? advertiseHost,
    Set<String>? serverCertSanIpv4s,
  }) {
    final lanSanIps = serverCertSanIpv4s
            ?.where((ip) => !isDisqualifiedIpv4(ip))
            .toSet() ??
        const <String>{};
    final result = <String>[];
    void addUnique(String ip) {
      if (!result.contains(ip)) {
        result.add(ip);
      }
    }

    if (advertiseHost != null && advertiseHost.trim().isNotEmpty) {
      final hostIp = advertiseHost.trim();
      final isValidSan = lanSanIps.isEmpty || lanSanIps.contains(hostIp);
      if (!isDisqualifiedIpv4(hostIp) && isValidSan) {
        final ownedLocally = adapters.any(
          (c) =>
              c.operStatus == operStatusUp &&
              c.ifType != 24 &&
              c.tunnelType == 0 &&
              !_hasExcludedKeyword(c) &&
              c.ipv4Addresses.any(
                (u) => u.dadState == dadStatePreferred && u.ip == hostIp,
              ),
        );
        if (ownedLocally) {
          addUnique(hostIp);
        }
      }
    }

    final tier1Gateway = <String>[];
    final tier1NoGateway = <String>[];
    final tier2Bridged = <String>[];

    for (final c in adapters) {
      if (c.operStatus != operStatusUp) continue;
      if (!allowedLanIfTypes.contains(c.ifType)) continue;
      if (c.tunnelType != 0) continue;
      if (_hasExcludedKeyword(c)) continue;

      for (final u in c.ipv4Addresses) {
        if (u.dadState != dadStatePreferred) continue;
        if (isDisqualifiedIpv4(u.ip)) continue;
        if (c.hardwareInterface) {
          if (c.hasGateway) {
            tier1Gateway.add(u.ip);
          } else {
            tier1NoGateway.add(u.ip);
          }
        } else if (c.ifType == 6 &&
            c.hasGateway &&
            isRfc1918PrivateLan(u.ip)) {
          tier2Bridged.add(u.ip);
        }
      }
    }

    List<String> orderBySan(List<String> ips) {
      if (lanSanIps.isEmpty) return ips;
      final inSan = ips.where(lanSanIps.contains);
      final notInSan = ips.where((ip) => !lanSanIps.contains(ip));
      return <String>[...inSan, ...notInSan];
    }

    for (final bucket in <List<String>>[
      orderBySan(tier1Gateway),
      orderBySan(tier1NoGateway),
      orderBySan(tier2Bridged),
    ]) {
      for (final ip in bucket) {
        addUnique(ip);
      }
    }

    return List<String>.unmodifiable(result);
  }
}
