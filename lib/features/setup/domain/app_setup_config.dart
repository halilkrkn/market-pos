import '../../../core/constants/app_constants.dart';

/// MARKET MMS — İşletme / Şube / Cihaz ve TLS Sabitleme Kurulum Yapılandırması.
///
/// Saf Dart alan nesnesidir (`package:flutter` bağımlılığı yoktur).
/// Yerel veritabanı şema sürümünü (`ClientDatabase.schemaVersion == 3`)
/// değiştirmeksizin `client_config.json` dosyasında kalıcı olarak saklanır.
class AppSetupConfig {
  static const String defaultTenantId = 'default-tenant';
  static const String defaultStoreId = 'default-store';
  static const String defaultStoreName = 'Ana Şube';
  static const String defaultDeviceName = 'MARKET MMS Kasa';

  final bool isSetupCompleted;
  final String tenantId;
  final String storeId;
  final String storeName;
  final String deviceId;
  final String deviceName;
  final bool tlsPinningEnabled;
  final String? pinnedCaSha256;
  final String? pinnedCaPem;
  final String? updateManifestUrl;
  final DateTime? updatedAt;

  const AppSetupConfig({
    this.isSetupCompleted = false,
    this.tenantId = defaultTenantId,
    this.storeId = defaultStoreId,
    this.storeName = defaultStoreName,
    this.deviceId = AppConstants.defaultDeviceId,
    this.deviceName = defaultDeviceName,
    this.tlsPinningEnabled = false,
    this.pinnedCaSha256,
    this.pinnedCaPem,
    this.updateManifestUrl,
    this.updatedAt,
  });

  factory AppSetupConfig.initial({String? deviceId}) => AppSetupConfig(
        isSetupCompleted: false,
        tenantId: defaultTenantId,
        storeId: defaultStoreId,
        storeName: defaultStoreName,
        deviceId: (deviceId != null && deviceId.trim().isNotEmpty)
            ? deviceId.trim()
            : AppConstants.defaultDeviceId,
        deviceName: defaultDeviceName,
      );

  bool get hasPinnedCertificate =>
      tlsPinningEnabled &&
      pinnedCaSha256 != null &&
      normalizeSha256Hex(pinnedCaSha256!).isNotEmpty;

  String? get normalizedPinSha256 =>
      pinnedCaSha256 == null ? null : normalizeSha256Hex(pinnedCaSha256!);

  static String normalizeSha256Hex(String raw) {
    return raw.replaceAll(':', '').replaceAll(' ', '').trim().toUpperCase();
  }

  AppSetupConfig copyWith({
    bool? isSetupCompleted,
    String? tenantId,
    String? storeId,
    String? storeName,
    String? deviceId,
    String? deviceName,
    bool? tlsPinningEnabled,
    String? pinnedCaSha256,
    bool clearPinnedCaSha256 = false,
    String? pinnedCaPem,
    bool clearPinnedCaPem = false,
    String? updateManifestUrl,
    bool clearUpdateManifestUrl = false,
    DateTime? updatedAt,
  }) {
    return AppSetupConfig(
      isSetupCompleted: isSetupCompleted ?? this.isSetupCompleted,
      tenantId: tenantId ?? this.tenantId,
      storeId: storeId ?? this.storeId,
      storeName: storeName ?? this.storeName,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      tlsPinningEnabled: tlsPinningEnabled ?? this.tlsPinningEnabled,
      pinnedCaSha256: clearPinnedCaSha256
          ? null
          : (pinnedCaSha256 ?? this.pinnedCaSha256),
      pinnedCaPem: clearPinnedCaPem ? null : (pinnedCaPem ?? this.pinnedCaPem),
      updateManifestUrl: clearUpdateManifestUrl
          ? null
          : (updateManifestUrl ?? this.updateManifestUrl),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': 1,
        'is_setup_completed': isSetupCompleted,
        'tenant_id': tenantId,
        'store_id': storeId,
        'store_name': storeName,
        'device_id': deviceId,
        'device_name': deviceName,
        'tls_pinning_enabled': tlsPinningEnabled,
        if (pinnedCaSha256 != null) 'pinned_ca_sha256': pinnedCaSha256,
        if (pinnedCaPem != null) 'pinned_ca_pem': pinnedCaPem,
        if (updateManifestUrl != null) 'update_manifest_url': updateManifestUrl,
        if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
      };

  factory AppSetupConfig.fromJson(Map<String, dynamic> json) {
    final tenant = (json['tenant_id'] as String?)?.trim();
    final store = (json['store_id'] as String?)?.trim();
    final storeName = (json['store_name'] as String?)?.trim();
    final device = (json['device_id'] as String?)?.trim();
    final deviceName = (json['device_name'] as String?)?.trim();
    final rawSha = (json['pinned_ca_sha256'] as String?)?.trim();
    final rawPem = (json['pinned_ca_pem'] as String?)?.trim();
    final rawManifestUrl = (json['update_manifest_url'] as String?)?.trim();
    final rawUpdatedAt = json['updated_at'] as String?;

    return AppSetupConfig(
      isSetupCompleted: json['is_setup_completed'] as bool? ?? false,
      tenantId: (tenant != null && tenant.isNotEmpty) ? tenant : defaultTenantId,
      storeId: (store != null && store.isNotEmpty) ? store : defaultStoreId,
      storeName:
          (storeName != null && storeName.isNotEmpty) ? storeName : defaultStoreName,
      deviceId: (device != null && device.isNotEmpty)
          ? device
          : AppConstants.defaultDeviceId,
      deviceName: (deviceName != null && deviceName.isNotEmpty)
          ? deviceName
          : defaultDeviceName,
      tlsPinningEnabled: json['tls_pinning_enabled'] as bool? ?? false,
      pinnedCaSha256: (rawSha != null && rawSha.isNotEmpty) ? rawSha : null,
      pinnedCaPem: (rawPem != null && rawPem.isNotEmpty) ? rawPem : null,
      updateManifestUrl:
          (rawManifestUrl != null && rawManifestUrl.isNotEmpty)
              ? rawManifestUrl
              : null,
      updatedAt: rawUpdatedAt != null ? DateTime.tryParse(rawUpdatedAt) : null,
    );
  }
}
