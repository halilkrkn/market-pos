import 'package:mms_client_storage/mms_client_storage.dart';

/// Yerel ağdaki Windows Master Hub sunucularını keşfetmek için saf Dart arayüzü.
abstract class HubDiscoveryClient {
  Future<List<DiscoveredHubCandidate>> discover({
    required String deviceId,
    Duration timeout = const Duration(milliseconds: 2500),
    int probeCount = 3,
    Duration probeInterval = const Duration(milliseconds: 600),
  });
}
