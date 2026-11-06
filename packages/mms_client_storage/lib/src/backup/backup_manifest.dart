import 'dart:convert';

/// Yedeklenen veritabanının türünü belirten enum.
/// Bir cihazın yedeği asla merkezi sunucuya veya başka bir cihaz türüne yüklenemez.
enum DatabaseType {
  centralMaster('CENTRAL_MASTER'),
  clientLocal('CLIENT_LOCAL'),
  mobileLocal('MOBILE_LOCAL');

  final String value;
  const DatabaseType(this.value);

  static DatabaseType fromString(String raw) {
    for (final type in DatabaseType.values) {
      if (type.value == raw) return type;
    }
    throw ArgumentError('Bilinmeyen DatabaseType: $raw');
  }
}

/// S5A-4: Yedek paketi için şifrelenmemiş ve doğrulanabilir üstveri bildirgesi (Manifest)
class BackupManifest {
  final String backupId;
  final String deviceId;
  final String tenantId;
  final String storeId;
  final DatabaseType databaseType;
  final int schemaVersion;
  final String appVersion;
  final DateTime timestamp; // UTC
  final String checksum; // Ham (şifresiz) veritabanı dosyasının SHA-256 hash'i
  final int unencryptedSizeBytes;
  final int encryptedSizeBytes;
  final String encryptionAlgorithm; // 'AES-256-CBC-HMAC-SHA256'
  final int kdfIterations; // PBKDF2 iterasyon sayısı (varsayılan: 600.000)
  final bool isMonthlyArchive;

  const BackupManifest({
    required this.backupId,
    required this.deviceId,
    required this.tenantId,
    required this.storeId,
    required this.databaseType,
    required this.schemaVersion,
    required this.appVersion,
    required this.timestamp,
    required this.checksum,
    required this.unencryptedSizeBytes,
    required this.encryptedSizeBytes,
    this.encryptionAlgorithm = 'AES-256-CBC-HMAC-SHA256',
    this.kdfIterations = 600000,
    this.isMonthlyArchive = false,
  });

  Map<String, dynamic> toJson() => {
        'backup_id': backupId,
        'device_id': deviceId,
        'tenant_id': tenantId,
        'store_id': storeId,
        'database_type': databaseType.value,
        'schema_version': schemaVersion,
        'app_version': appVersion,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'checksum': checksum,
        'unencrypted_size_bytes': unencryptedSizeBytes,
        'encrypted_size_bytes': encryptedSizeBytes,
        'encryption_algorithm': encryptionAlgorithm,
        'kdf_iterations': kdfIterations,
        'is_monthly_archive': isMonthlyArchive,
      };

  factory BackupManifest.fromJson(Map<String, dynamic> json) {
    final rawBackupId = json['backup_id'] as String?;
    final rawDeviceId = json['device_id'] as String?;
    final rawTenantId = json['tenant_id'] as String?;
    final rawStoreId = json['store_id'] as String?;
    final rawDbType = json['database_type'] as String?;
    final rawSchemaVer = json['schema_version'] as int?;
    final rawAppVer = json['app_version'] as String?;
    final rawTimestamp = json['timestamp'] as String?;
    final rawChecksum = json['checksum'] as String?;
    final rawUnencSize = json['unencrypted_size_bytes'] as int?;
    final rawEncSize = json['encrypted_size_bytes'] as int?;
    final rawAlgorithm = json['encryption_algorithm'] as String? ?? 'AES-256-CBC-HMAC-SHA256';
    final rawKdfIterations = json['kdf_iterations'] as int? ?? 600000;
    final rawIsMonthly = json['is_monthly_archive'] as bool? ?? false;

    if (rawBackupId == null || rawBackupId.isEmpty) {
      throw const FormatException('Manifest "backup_id" eksik veya geçersiz.');
    }
    if (rawDeviceId == null || rawDeviceId.isEmpty) {
      throw const FormatException('Manifest "device_id" eksik veya geçersiz.');
    }
    if (rawTenantId == null || rawTenantId.isEmpty) {
      throw const FormatException('Manifest "tenant_id" eksik veya geçersiz.');
    }
    if (rawStoreId == null || rawStoreId.isEmpty) {
      throw const FormatException('Manifest "store_id" eksik veya geçersiz.');
    }
    if (rawDbType == null || rawDbType.isEmpty) {
      throw const FormatException('Manifest "database_type" eksik veya geçersiz.');
    }
    if (rawSchemaVer == null || rawSchemaVer <= 0) {
      throw const FormatException('Manifest "schema_version" pozitif bir tamsayı olmalıdır.');
    }
    if (rawAppVer == null || rawAppVer.isEmpty) {
      throw const FormatException('Manifest "app_version" eksik veya geçersiz.');
    }
    if (rawTimestamp == null || rawTimestamp.isEmpty) {
      throw const FormatException('Manifest "timestamp" eksik veya geçersiz.');
    }
    if (rawChecksum == null || rawChecksum.length != 64) {
      throw const FormatException('Manifest "checksum" geçerli bir SHA-256 hex dizesi (64 karakter) olmalıdır.');
    }
    if (rawUnencSize == null || rawUnencSize < 0) {
      throw const FormatException('Manifest "unencrypted_size_bytes" negatif olamaz.');
    }
    if (rawEncSize == null || rawEncSize < 0) {
      throw const FormatException('Manifest "encrypted_size_bytes" negatif olamaz.');
    }

    return BackupManifest(
      backupId: rawBackupId,
      deviceId: rawDeviceId,
      tenantId: rawTenantId,
      storeId: rawStoreId,
      databaseType: DatabaseType.fromString(rawDbType),
      schemaVersion: rawSchemaVer,
      appVersion: rawAppVer,
      timestamp: DateTime.parse(rawTimestamp).toUtc(),
      checksum: rawChecksum.toLowerCase(),
      unencryptedSizeBytes: rawUnencSize,
      encryptedSizeBytes: rawEncSize,
      encryptionAlgorithm: rawAlgorithm,
      kdfIterations: rawKdfIterations,
      isMonthlyArchive: rawIsMonthly,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory BackupManifest.fromJsonString(String jsonStr) =>
      BackupManifest.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);

  BackupManifest copyWith({
    String? backupId,
    String? deviceId,
    String? tenantId,
    String? storeId,
    DatabaseType? databaseType,
    int? schemaVersion,
    String? appVersion,
    DateTime? timestamp,
    String? checksum,
    int? unencryptedSizeBytes,
    int? encryptedSizeBytes,
    String? encryptionAlgorithm,
    int? kdfIterations,
    bool? isMonthlyArchive,
  }) {
    return BackupManifest(
      backupId: backupId ?? this.backupId,
      deviceId: deviceId ?? this.deviceId,
      tenantId: tenantId ?? this.tenantId,
      storeId: storeId ?? this.storeId,
      databaseType: databaseType ?? this.databaseType,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      appVersion: appVersion ?? this.appVersion,
      timestamp: timestamp ?? this.timestamp,
      checksum: checksum ?? this.checksum,
      unencryptedSizeBytes: unencryptedSizeBytes ?? this.unencryptedSizeBytes,
      encryptedSizeBytes: encryptedSizeBytes ?? this.encryptedSizeBytes,
      encryptionAlgorithm: encryptionAlgorithm ?? this.encryptionAlgorithm,
      kdfIterations: kdfIterations ?? this.kdfIterations,
      isMonthlyArchive: isMonthlyArchive ?? this.isMonthlyArchive,
    );
  }
}

