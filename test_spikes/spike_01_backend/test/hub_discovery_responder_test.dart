import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../lib/discovery/discovery_responder.dart';
import '../lib/db/database.dart';
import '../lib/db/write_queue.dart';
import '../bin/server.dart';

void main() {
  group('MARKET MMS — Hub UDP Discovery Responder Testleri (Faz 1.1)', () {
    const testDiscoveryPort = 18946; // Test ortamında çakışmayı önlemek için özel port
    const testHttpPort = 8945;
    late HubDiscoveryResponder responder;

    setUp(() async {
      responder = HubDiscoveryResponder(
        httpPort: testHttpPort,
        discoveryPort: testDiscoveryPort,
        hubId: 'TEST-MMS-HUB',
        bindAddress: InternetAddress.loopbackIPv4,
      );
      await responder.start();
    });

    tearDown(() async {
      await responder.stop();
    });

    test('Senaryo 1: Geçerli DISCOVER_MMS_HUB isteğine doğru unicast yanıt', () async {
      expect(responder.isRunning, isTrue);

      // İstemci soketi oluştur
      final clientSocket = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );

      final requestPayload = jsonEncode({
        'cmd': 'DISCOVER_MMS_HUB',
        'version': '1.0',
        'client_device_id': 'POS-ANDROID-TEST',
      });

      // İsteği gönder
      clientSocket.send(
        utf8.encode(requestPayload),
        InternetAddress.loopbackIPv4,
        testDiscoveryPort,
      );

      // Yanıtı bekle
      final completer = Completer<Map<String, dynamic>>();
      clientSocket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = clientSocket.receive();
          if (dg != null) {
            final json = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
            if (!completer.isCompleted) {
              completer.complete(json);
            }
          }
        }
      });

      final response = await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw TimeoutException('Discovery yanıtı zaman aşımına uğradı'),
      );

      clientSocket.close();

      // Yanıt alanlarını doğrula
      expect(response['service'], equals('market_mms_hub'));
      expect(response['protocol_version'], equals('1.0'));
      expect(response['hub_id'], equals('TEST-MMS-HUB'));
      expect(response['http_port'], equals(testHttpPort));
      expect(response['server_time'], isNotNull);
      expect(response['server_ips'], isA<List>());
    });

    test('Senaryo 2: Geçersiz veya alakasız komutlar sessizce reddedilir (yanıt verilmez)', () async {
      final clientSocket = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );

      // Yanlış komut gönder
      final invalidPayload = jsonEncode({
        'cmd': 'UNKNOWN_PROBE',
        'data': 'test',
      });

      clientSocket.send(
        utf8.encode(invalidPayload),
        InternetAddress.loopbackIPv4,
        testDiscoveryPort,
      );

      bool receivedResponse = false;
      clientSocket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = clientSocket.receive();
          if (dg != null) {
            receivedResponse = true;
          }
        }
      });

      // 600 ms bekle — yanıt gelmemeli
      await Future.delayed(const Duration(milliseconds: 600));
      clientSocket.close();

      expect(receivedResponse, isFalse);
      expect(responder.isRunning, isTrue); // Sunucu çökmeksizin çalışmaya devam etmeli
    });

    test('Senaryo 3: Bozuk veya aşırı büyük JSON paketleri soketi çökertmez', () async {
      final clientSocket = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );

      // 1. Bozuk veri
      clientSocket.send(
        utf8.encode('Bu geçerli bir JSON değildir! {[[}'),
        InternetAddress.loopbackIPv4,
        testDiscoveryPort,
      );

      // 2. 1024 baytı aşan aşırı büyük paket (Buffer flood)
      final largeBytes = List<int>.filled(2048, 65); // 'A' karakterleri
      clientSocket.send(
        largeBytes,
        InternetAddress.loopbackIPv4,
        testDiscoveryPort,
      );

      await Future.delayed(const Duration(milliseconds: 200));

      // Ardından meşru istek gönderildiğinde sunucu hala çalışıyor olmalı
      final validPayload = jsonEncode({'cmd': 'DISCOVER_MMS_HUB'});
      clientSocket.send(
        utf8.encode(validPayload),
        InternetAddress.loopbackIPv4,
        testDiscoveryPort,
      );

      final completer = Completer<bool>();
      clientSocket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = clientSocket.receive();
          if (dg != null) {
            final json = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
            if (json['service'] == 'market_mms_hub' && !completer.isCompleted) {
              completer.complete(true);
            }
          }
        }
      });

      final success = await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => false,
      );

      clientSocket.close();
      expect(success, isTrue);
    });

    test('Senaryo 4: Birden fazla istek ardışık ve eşzamanlı olarak başarıyla yanıtlanır', () async {
      final clientSocket = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );

      final validPayload = jsonEncode({'cmd': 'DISCOVER_MMS_HUB'});
      final validBytes = utf8.encode(validPayload);

      int responseCount = 0;
      final completer = Completer<int>();

      clientSocket.listen((event) {
        if (event == RawSocketEvent.read) {
          while (true) {
            final dg = clientSocket.receive();
            if (dg == null) break;
            responseCount++;
            if (responseCount >= 3 && !completer.isCompleted) {
              completer.complete(responseCount);
            }
          }
        }
      });

      // 3 adet ardışık istek fırlat
      clientSocket.send(validBytes, InternetAddress.loopbackIPv4, testDiscoveryPort);
      await Future.delayed(const Duration(milliseconds: 30));
      clientSocket.send(validBytes, InternetAddress.loopbackIPv4, testDiscoveryPort);
      await Future.delayed(const Duration(milliseconds: 30));
      clientSocket.send(validBytes, InternetAddress.loopbackIPv4, testDiscoveryPort);

      final totalReceived = await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => responseCount,
      );

      clientSocket.close();
      expect(totalReceived, greaterThanOrEqualTo(3));
    });

    test('Senaryo 5: Hub durdurulup yeniden başlatıldığında port kilitlenmez (Lifecycle & Port Reuse)', () async {
      expect(responder.isRunning, isTrue);

      // 1. Durdur
      await responder.stop();
      expect(responder.isRunning, isFalse);

      // 2. Hemen aynı portta tekrar başlat
      final restartResponder = HubDiscoveryResponder(
        httpPort: testHttpPort,
        discoveryPort: testDiscoveryPort,
        bindAddress: InternetAddress.loopbackIPv4,
      );

      await restartResponder.start();
      expect(restartResponder.isRunning, isTrue);

      // İletişimi sına
      final clientSocket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      clientSocket.send(
        utf8.encode(jsonEncode({'cmd': 'DISCOVER_MMS_HUB'})),
        InternetAddress.loopbackIPv4,
        testDiscoveryPort,
      );

      final completer = Completer<bool>();
      clientSocket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = clientSocket.receive();
          if (dg != null && !completer.isCompleted) {
            completer.complete(true);
          }
        }
      });

      final received = await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => false,
      );

      clientSocket.close();
      await restartResponder.stop();

      expect(received, isTrue);
    });

    test('Senaryo 6: getLocalLanIps sanal ağları ve loopback adreslerini eler', () async {
      final ips = await HubDiscoveryResponder.getLocalLanIps();
      // Tüm bulunan IP'ler IPv4 formatında olmalı ve loopback/APIPA olmamalı
      for (final ip in ips) {
        expect(ip.startsWith('127.'), isFalse);
        expect(ip.startsWith('169.254.'), isFalse);
        expect(ip.startsWith('192.168.56.'), isFalse);
      }
    });

    test('Senaryo 7: SpikeServer lifecycle entegrasyonu (start ile başlar, stop ile kapanır)', () async {
      final tempDir = await Directory.systemTemp.createTemp('spike_server_discovery_test_');
      final dbFile = File('${tempDir.path}/temp_master.db');
      final db = SpikeDatabase(dbFile);
      final queue = WriteQueue();

      final server = SpikeServer(
        db: db,
        dbFile: dbFile,
        writeQueue: queue,
        backupDirectory: '${tempDir.path}/backups',
      );

      const serverHttpPort = 18099;
      const serverDiscoveryPort = 18948;

      try {
        await server.start(
          port: serverHttpPort,
          discoveryPort: serverDiscoveryPort,
          address: InternetAddress.loopbackIPv4,
        );

        expect(server.discoveryResponder, isNotNull);
        expect(server.discoveryResponder!.isRunning, isTrue);

        // UDP üzerinden SpikeServer'ı keşfet
        final clientSocket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
        clientSocket.send(
          utf8.encode(jsonEncode({'cmd': 'DISCOVER_MMS_HUB'})),
          InternetAddress.loopbackIPv4,
          serverDiscoveryPort,
        );

        final completer = Completer<Map<String, dynamic>>();
        clientSocket.listen((event) {
          if (event == RawSocketEvent.read) {
            final dg = clientSocket.receive();
            if (dg != null && !completer.isCompleted) {
              completer.complete(jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>);
            }
          }
        });

        final response = await completer.future.timeout(
          const Duration(seconds: 3),
          onTimeout: () => throw TimeoutException('SpikeServer discovery yanıtı gelmedi'),
        );

        clientSocket.close();

        expect(response['service'], equals('market_mms_hub'));
        expect(response['protocol_version'], equals('1.0'));
        expect(response['http_port'], equals(serverHttpPort));
        expect(response.containsKey('tls'), isFalse);
        expect(response.containsKey('ca_sha256'), isFalse);
        expect(response.containsKey('ca_pem'), isFalse);
        expect(response.containsKey('ca_fingerprint'), isFalse);

        // Sunucuyu durdur
        await server.stop();
        expect(server.discoveryResponder, isNull);
      } finally {
        await db.close();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });
}
