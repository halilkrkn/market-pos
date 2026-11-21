import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mms_client_storage/mms_client_storage.dart';

/// K-05: Hub tarafından TLS-pinned kanal üzerinden teslim edilen canlı Drive
/// senkronizasyon yapılandırması.
class HubLiveDriveConfig {
  final String tenantId;
  final String storeId;
  final String hubId;
  final String liveSyncSecret;
  final List<DriveAuthorizedDevice> authorizedDevices;

  const HubLiveDriveConfig({
    required this.tenantId,
    required this.storeId,
    required this.hubId,
    required this.liveSyncSecret,
    required this.authorizedDevices,
  });
}

/// K-05: Hub `GET /api/v1/sync/live-drive-config` istemcisi.
///
/// Sır veya token hiçbir zaman loglanmaz; `404` durumunda eski Hub'larla geriye
/// dönük uyumluluk için `null` döner.
class HubLiveDriveConfigClient {
  final http.Client _httpClient;
  final Duration timeout;

  HubLiveDriveConfigClient({
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 10),
  }) : _httpClient = httpClient ?? http.Client();

  Future<HubLiveDriveConfig?> fetchConfig({
    required String hubUrl,
    required String deviceToken,
    required String tenantId,
    required String storeId,
  }) async {
    final cleanUrl = hubUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final cleanToken = deviceToken.trim();
    if (cleanUrl.isEmpty || cleanToken.isEmpty) {
      return null;
    }

    final uri = Uri.parse('$cleanUrl/api/v1/sync/live-drive-config');
    final response = await _httpClient.get(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $cleanToken',
        'X-MMS-Tenant-Id': tenantId,
        'X-MMS-Store-Id': storeId,
      },
    ).timeout(timeout);

    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      throw StateError(
        'Live Drive yapılandırması alınamadı [HTTP ${response.statusCode}].',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Live Drive yapılandırma yanıtı geçersiz.');
    }

    final respTenant = (decoded['tenant_id'] as String?)?.trim();
    final respStore = (decoded['store_id'] as String?)?.trim();
    if (respTenant != tenantId || respStore != storeId) {
      throw StateError(
        'Live Drive yapılandırma tenant/store uyuşmazlığı ($respTenant/$respStore).',
      );
    }

    final rawSecret = (decoded['live_sync_secret'] as String?)?.trim() ?? '';
    if (rawSecret.length < 32) {
      throw StateError(
        'Live Drive senkronizasyon gizlisi eksik veya yetersiz entropiye sahip.',
      );
    }

    final rawDevices = decoded['authorized_devices'];
    if (rawDevices is! List) {
      throw const FormatException(
        'Live Drive yetkili cihaz listesi geçersiz biçimde.',
      );
    }

    final devices = <DriveAuthorizedDevice>[];
    for (final entry in rawDevices) {
      if (entry is! Map) {
        throw const FormatException('Yetkili cihaz kaydı JSON nesnesi değil.');
      }
      devices.add(
        DriveAuthorizedDevice.fromJson(Map<String, dynamic>.from(entry)),
      );
    }

    return HubLiveDriveConfig(
      tenantId: respTenant!,
      storeId: respStore!,
      hubId: (decoded['hub_id'] as String?)?.trim() ?? '',
      liveSyncSecret: rawSecret,
      authorizedDevices: List<DriveAuthorizedDevice>.unmodifiable(devices),
    );
  }

  void close() => _httpClient.close();
}
