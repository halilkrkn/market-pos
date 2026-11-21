import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// MARKET MMS — Hub UDP Discovery Responder (Faz 1.1)
///
/// Yerel ağdaki istemcilerin (Android / Windows) Master Hub sunucusunu
/// sıfır konfigürasyonla (Zero-Config) otomatik keşfetmesini sağlar.
///
/// Protokol:
/// 1. İstemci UDP [discoveryPort] (varsayılan: 8946) portuna broadcast gönderir:
///    {"cmd": "DISCOVER_MMS_HUB", "version": "1.0", "client_device_id": "..."}
/// 2. Hub, gelen datagram'ın kaynak IP ve portuna Unicast JSON yanıt döner:
///    {
///      "service": "market_mms_hub",
///      "protocol_version": "1.0",
///      "hub_id": "MMS-HUB-MASTER",
///      "http_port": 8945,
///      "server_time": "2026-11-20T...Z",
///      "server_ips": ["192.168.1.158"]
///    }
/// 3. İstemci hem UDP yanıtının geldiği socket kaynak IP adresini (source address)
///    hem de [server_ips] listesini kullanarak doğru ağ arayüzünü doğrular.
class HubDiscoveryResponder {
  static const String defaultServiceName = 'market_mms_hub';
  static const String protocolVersion = '1.0';
  static const String discoveryCommand = 'DISCOVER_MMS_HUB';
  static const int defaultDiscoveryPort = 8946;
  static const int maxDatagramLength = 1024;

  final int httpPort;
  final int discoveryPort;
  final String hubId;
  final InternetAddress? bindAddress;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  bool _isRunning = false;
  List<String> _cachedLanIps = const [];
  DateTime? _lastLanIpsRefresh;

  HubDiscoveryResponder({
    required this.httpPort,
    this.discoveryPort = defaultDiscoveryPort,
    this.hubId = 'MMS-HUB-MASTER',
    this.bindAddress,
  });

  /// Discovery servisinin aktif çalışıp çalışmadığı
  bool get isRunning => _isRunning;

  /// UDP Discovery dinleyicisini başlatır
  Future<void> start() async {
    if (_isRunning) return;

    // Başlangıçta IP önbelleğini ısıt
    await _refreshLanIps();

    final targetAddress = bindAddress ?? InternetAddress.anyIPv4;
    _socket = await RawDatagramSocket.bind(
      targetAddress,
      discoveryPort,
      reuseAddress: true,
      reusePort: false,
    );
    _socket!.broadcastEnabled = true;

    _subscription = _socket!.listen(
      _handleSocketEvent,
      onError: _handleError,
      onDone: _handleDone,
      cancelOnError: false,
    );

    _isRunning = true;
  }

  Future<void> _refreshLanIps() async {
    try {
      _cachedLanIps = await getLocalLanIps();
      _lastLanIpsRefresh = DateTime.now();
    } catch (_) {}
  }

  Future<List<String>> _getEffectiveLanIps() async {
    if (_lastLanIpsRefresh == null ||
        DateTime.now().difference(_lastLanIpsRefresh!) > const Duration(seconds: 30)) {
      await _refreshLanIps();
    }
    return _cachedLanIps;
  }

  /// Soket olaylarını işler
  void _handleSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read || _socket == null) return;

    try {
      final datagram = _socket?.receive();
      if (datagram == null) return;

      // Aşırı büyük paketleri filtrele (DoS ve buffer koruması)
      if (datagram.data.length > maxDatagramLength) {
        return;
      }

      final rawString = utf8.decode(datagram.data, allowMalformed: false);
      final dynamic decoded = jsonDecode(rawString);

      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final cmd = decoded['cmd'] as String?;
      if (cmd != discoveryCommand) {
        // Geçersiz veya alakasız komut: Güvenli biçimde göz ardı et
        return;
      }

      // Geçerli istek: Eşzamanlı/asenkron olarak yanıt hazırla ve gönder
      _sendDiscoveryResponse(datagram.address, datagram.port);
    } catch (_) {
      // Bozuk UTF-8 veya geçersiz JSON paketlerinde sessizce devam et
    }
  }

  /// İstemciye unicast discovery yanıtı gönderir
  Future<void> _sendDiscoveryResponse(
    InternetAddress clientAddress,
    int clientPort,
  ) async {
    if (_socket == null || !_isRunning) return;

    try {
      final lanIps = await _getEffectiveLanIps();
      final responseMap = <String, dynamic>{
        'service': defaultServiceName,
        'protocol_version': protocolVersion,
        'hub_id': hubId,
        'http_port': httpPort,
        'server_time': DateTime.now().toUtc().toIso8601String(),
        'server_ips': lanIps,
      };

      final responseBytes = utf8.encode(jsonEncode(responseMap));
      _socket?.send(responseBytes, clientAddress, clientPort);
    } catch (e) {
      // Ağ hatasında sunucuyu çökertme
    }
  }

  /// Windows makinesindeki geçerli fiziksel/yerel ağ IPv4 adreslerini listeler.
  /// Sanal adaptörleri (VirtualBox, APIPA 169.254, loopback) filtreler.
  static Future<List<String>> getLocalLanIps() async {
    final results = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
        includeLoopback: false,
      );

      for (final iface in interfaces) {
        final lowerName = iface.name.toLowerCase();
        // Bilinen sanal arayüzleri eler
        if (lowerName.contains('virtual') ||
            lowerName.contains('vbox') ||
            lowerName.contains('vmware') ||
            lowerName.contains('pseudo') ||
            lowerName.contains('vethernet')) {
          continue;
        }

        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('127.') || ip.startsWith('169.254.')) {
            continue;
          }
          // VirtualBox varsayılan host-only ağı
          if (ip.startsWith('192.168.56.')) {
            continue;
          }
          if (!results.contains(ip)) {
            results.add(ip);
          }
        }
      }
    } catch (_) {}
    return results;
  }

  void _handleError(Object error, StackTrace stack) {
    // Soket seviyesindeki hatalar yakalanır; sunucu ayakta kalır
  }

  void _handleDone() {
    _isRunning = false;
  }

  /// UDP dinleyicisini zarif biçimde durdurur ve kaynakları serbest bırakır
  Future<void> stop() async {
    _isRunning = false;
    await _subscription?.cancel();
    _subscription = null;
    _socket?.close();
    _socket = null;
  }
}
