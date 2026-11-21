import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;

import '../backup/backup_crypto.dart';
import '../backup/backup_operation_lock.dart';
import '../backup/database_backup_engine.dart';
import '../backup/google_drive_backup.dart';
import '../database/client_database.dart';
import '../database/client_storage_repository.dart';

/// ADR-021: Hibrit canlı senkronizasyon güvenlik ve bütünlük istisnası.
class DriveSyncSecurityException implements Exception {
  final String code;
  final String message;

  const DriveSyncSecurityException(this.code, this.message);

  @override
  String toString() => 'DriveSyncSecurityException [$code]: $message';
}

enum DriveSyncDeviceStatus {
  active('ACTIVE'),
  revoked('REVOKED');

  final String value;
  const DriveSyncDeviceStatus(this.value);

  static DriveSyncDeviceStatus fromString(String? raw) {
    for (final s in values) {
      if (s.value == raw) return s;
    }
    return DriveSyncDeviceStatus.revoked;
  }
}

class DriveAuthorizedDevice {
  final String deviceId;
  final String tenantId;
  final String storeId;
  final DriveSyncDeviceStatus status;
  final String? deviceSecretOrPublicKey;
  final DateTime updatedAtUtc;

  const DriveAuthorizedDevice({
    required this.deviceId,
    required this.tenantId,
    required this.storeId,
    required this.status,
    this.deviceSecretOrPublicKey,
    required this.updatedAtUtc,
  });

  bool get isActive => status == DriveSyncDeviceStatus.active;

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'tenant_id': tenantId,
        'store_id': storeId,
        'status': status.value,
        if (deviceSecretOrPublicKey != null) 'device_key': deviceSecretOrPublicKey,
        'updated_at': updatedAtUtc.toUtc().toIso8601String(),
      };

  factory DriveAuthorizedDevice.fromJson(Map<String, dynamic> json) =>
      DriveAuthorizedDevice(
        deviceId: json['device_id'] as String,
        tenantId: json['tenant_id'] as String,
        storeId: json['store_id'] as String,
        status: DriveSyncDeviceStatus.fromString(json['status'] as String?),
        deviceSecretOrPublicKey: json['device_key'] as String?,
        updatedAtUtc: DateTime.parse(json['updated_at'] as String).toUtc(),
      );
}

/// Mağaza içindeki yetkili ve iptal edilmiş (`REVOKED`) cihaz kayıt defteri.
class DriveAuthorizedDeviceRegistry {
  final Map<String, DriveAuthorizedDevice> _devices;

  DriveAuthorizedDeviceRegistry([Iterable<DriveAuthorizedDevice> initial = const []])
      : _devices = {for (final d in initial) d.deviceId: d};

  List<DriveAuthorizedDevice> get all => List.unmodifiable(_devices.values);

  void authorizeDevice({
    required String deviceId,
    required String tenantId,
    required String storeId,
    String? deviceSecretOrPublicKey,
    DateTime? updatedAtUtc,
  }) {
    _devices[deviceId] = DriveAuthorizedDevice(
      deviceId: deviceId,
      tenantId: tenantId,
      storeId: storeId,
      status: DriveSyncDeviceStatus.active,
      deviceSecretOrPublicKey: deviceSecretOrPublicKey,
      updatedAtUtc: (updatedAtUtc ?? DateTime.now()).toUtc(),
    );
  }

  void revokeDevice(String deviceId, {DateTime? updatedAtUtc}) {
    final existing = _devices[deviceId];
    if (existing == null) return;
    _devices[deviceId] = DriveAuthorizedDevice(
      deviceId: existing.deviceId,
      tenantId: existing.tenantId,
      storeId: existing.storeId,
      status: DriveSyncDeviceStatus.revoked,
      deviceSecretOrPublicKey: existing.deviceSecretOrPublicKey,
      updatedAtUtc: (updatedAtUtc ?? DateTime.now()).toUtc(),
    );
  }

  DriveAuthorizedDevice? find(String deviceId) => _devices[deviceId];

  DriveAuthorizedDevice requireAuthorized({
    required String deviceId,
    required String tenantId,
    required String storeId,
  }) {
    final record = _devices[deviceId];
    if (record == null) {
      throw DriveSyncSecurityException(
        'ERR_DEVICE_UNAUTHORIZED',
        'Drive senkronizasyon zarfı kayıtsız cihazdan ($deviceId) geldiği için reddedildi.',
      );
    }
    if (!record.isActive) {
      throw DriveSyncSecurityException(
        'ERR_DEVICE_REVOKED',
        'Yetkisi iptal edilmiş ($deviceId) cihazdan gelen Drive zarfı reddedildi.',
      );
    }
    if (record.tenantId != tenantId || record.storeId != storeId) {
      throw DriveSyncSecurityException(
        'ERR_TENANT_STORE_MISMATCH',
        'Zarf tenant/store uyuşmazlığı ($tenantId/$storeId != ${record.tenantId}/${record.storeId}).',
      );
    }
    return record;
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'devices': _devices.values.map((d) => d.toJson()).toList(),
      };

  factory DriveAuthorizedDeviceRegistry.fromJson(Map<String, dynamic> json) {
    final list = (json['devices'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((m) => DriveAuthorizedDevice.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    return DriveAuthorizedDeviceRegistry(list);
  }
}

/// Non-LWW çakışma kaydı (eşzamanlı PRODUCT_UPSERT vb. sessizce ezilmez).
class DriveSyncConflictRecord {
  final String conflictId;
  final String entityType;
  final String entityId;
  final String originDeviceId;
  final int originClientSeq;
  final String? localPriceVersionId;
  final String? remotePriceVersionId;
  final int? localPrice;
  final int? remotePrice;
  final String reason;
  final DateTime detectedAtUtc;
  final bool resolved;

  const DriveSyncConflictRecord({
    required this.conflictId,
    required this.entityType,
    required this.entityId,
    required this.originDeviceId,
    required this.originClientSeq,
    this.localPriceVersionId,
    this.remotePriceVersionId,
    this.localPrice,
    this.remotePrice,
    required this.reason,
    required this.detectedAtUtc,
    this.resolved = false,
  });

  DriveSyncConflictRecord copyWith({bool? resolved}) => DriveSyncConflictRecord(
        conflictId: conflictId,
        entityType: entityType,
        entityId: entityId,
        originDeviceId: originDeviceId,
        originClientSeq: originClientSeq,
        localPriceVersionId: localPriceVersionId,
        remotePriceVersionId: remotePriceVersionId,
        localPrice: localPrice,
        remotePrice: remotePrice,
        reason: reason,
        detectedAtUtc: detectedAtUtc,
        resolved: resolved ?? this.resolved,
      );

  Map<String, dynamic> toJson() => {
        'conflict_id': conflictId,
        'entity_type': entityType,
        'entity_id': entityId,
        'origin_device_id': originDeviceId,
        'origin_client_seq': originClientSeq,
        'local_price_version_id': localPriceVersionId,
        'remote_price_version_id': remotePriceVersionId,
        'local_price': localPrice,
        'remote_price': remotePrice,
        'reason': reason,
        'detected_at': detectedAtUtc.toUtc().toIso8601String(),
        'resolved': resolved,
      };

  factory DriveSyncConflictRecord.fromJson(Map<String, dynamic> json) =>
      DriveSyncConflictRecord(
        conflictId: json['conflict_id'] as String,
        entityType: json['entity_type'] as String,
        entityId: json['entity_id'] as String,
        originDeviceId: json['origin_device_id'] as String,
        originClientSeq: json['origin_client_seq'] as int,
        localPriceVersionId: json['local_price_version_id'] as String?,
        remotePriceVersionId: json['remote_price_version_id'] as String?,
        localPrice: json['local_price'] as int?,
        remotePrice: json['remote_price'] as int?,
        reason: json['reason'] as String,
        detectedAtUtc: DateTime.parse(json['detected_at'] as String).toUtc(),
        resolved: json['resolved'] == true,
      );
}

class DriveLiveSyncLedgerState {
  final String? folderId;
  final Map<String, int> lastUploadedSeqByDevice;
  final Map<String, int> lastAppliedSeqByDevice;
  final Map<String, String> uploadedEnvelopeFileIds;
  final List<DriveSyncConflictRecord> conflicts;
  final int consecutiveHubFailures;
  final bool driveFallbackActive;
  final bool pendingHubReconciliation;
  final DateTime? lastDriveSyncAtUtc;
  final DateTime? lastHubReconciledAtUtc;
  final String? lastError;

  const DriveLiveSyncLedgerState({
    this.folderId,
    this.lastUploadedSeqByDevice = const {},
    this.lastAppliedSeqByDevice = const {},
    this.uploadedEnvelopeFileIds = const {},
    this.conflicts = const [],
    this.consecutiveHubFailures = 0,
    this.driveFallbackActive = false,
    this.pendingHubReconciliation = false,
    this.lastDriveSyncAtUtc,
    this.lastHubReconciledAtUtc,
    this.lastError,
  });

  static const empty = DriveLiveSyncLedgerState();

  List<DriveSyncConflictRecord> get unresolvedConflicts =>
      conflicts.where((c) => !c.resolved).toList();

  DriveLiveSyncLedgerState copyWith({
    String? folderId,
    Map<String, int>? lastUploadedSeqByDevice,
    Map<String, int>? lastAppliedSeqByDevice,
    Map<String, String>? uploadedEnvelopeFileIds,
    List<DriveSyncConflictRecord>? conflicts,
    int? consecutiveHubFailures,
    bool? driveFallbackActive,
    bool? pendingHubReconciliation,
    DateTime? lastDriveSyncAtUtc,
    DateTime? lastHubReconciledAtUtc,
    String? lastError,
    bool clearLastError = false,
  }) =>
      DriveLiveSyncLedgerState(
        folderId: folderId ?? this.folderId,
        lastUploadedSeqByDevice:
            lastUploadedSeqByDevice ?? this.lastUploadedSeqByDevice,
        lastAppliedSeqByDevice:
            lastAppliedSeqByDevice ?? this.lastAppliedSeqByDevice,
        uploadedEnvelopeFileIds:
            uploadedEnvelopeFileIds ?? this.uploadedEnvelopeFileIds,
        conflicts: conflicts ?? this.conflicts,
        consecutiveHubFailures:
            consecutiveHubFailures ?? this.consecutiveHubFailures,
        driveFallbackActive: driveFallbackActive ?? this.driveFallbackActive,
        pendingHubReconciliation:
            pendingHubReconciliation ?? this.pendingHubReconciliation,
        lastDriveSyncAtUtc: lastDriveSyncAtUtc ?? this.lastDriveSyncAtUtc,
        lastHubReconciledAtUtc:
            lastHubReconciledAtUtc ?? this.lastHubReconciledAtUtc,
        lastError: clearLastError ? null : (lastError ?? this.lastError),
      );

  Map<String, dynamic> toJson() => {
        'version': 1,
        'folder_id': folderId,
        'last_uploaded_seq': lastUploadedSeqByDevice,
        'last_applied_seq': lastAppliedSeqByDevice,
        'uploaded_file_ids': uploadedEnvelopeFileIds,
        'conflicts': conflicts.map((c) => c.toJson()).toList(),
        'consecutive_hub_failures': consecutiveHubFailures,
        'drive_fallback_active': driveFallbackActive,
        'pending_hub_reconciliation': pendingHubReconciliation,
        'last_drive_sync_at': lastDriveSyncAtUtc?.toUtc().toIso8601String(),
        'last_hub_reconciled_at':
            lastHubReconciledAtUtc?.toUtc().toIso8601String(),
        'last_error': lastError,
      };

  factory DriveLiveSyncLedgerState.fromJson(Map<String, dynamic> json) {
    Map<String, int> parseIntMap(Object? raw) {
      if (raw is! Map) return const {};
      return {
        for (final entry in raw.entries)
          if (entry.key is String && entry.value is int)
            entry.key as String: entry.value as int,
      };
    }

    Map<String, String> parseStrMap(Object? raw) {
      if (raw is! Map) return const {};
      return {
        for (final entry in raw.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    }

    DateTime? parseTs(Object? raw) =>
        raw is String ? DateTime.tryParse(raw)?.toUtc() : null;

    return DriveLiveSyncLedgerState(
      folderId: json['folder_id'] as String?,
      lastUploadedSeqByDevice: parseIntMap(json['last_uploaded_seq']),
      lastAppliedSeqByDevice: parseIntMap(json['last_applied_seq']),
      uploadedEnvelopeFileIds: parseStrMap(json['uploaded_file_ids']),
      conflicts: ((json['conflicts'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map((m) => DriveSyncConflictRecord.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
      consecutiveHubFailures: (json['consecutive_hub_failures'] as int?) ?? 0,
      driveFallbackActive: json['drive_fallback_active'] == true,
      pendingHubReconciliation: json['pending_hub_reconciliation'] == true,
      lastDriveSyncAtUtc: parseTs(json['last_drive_sync_at']),
      lastHubReconciledAtUtc: parseTs(json['last_hub_reconciled_at']),
      lastError: json['last_error'] as String?,
    );
  }
}

class DriveLiveSyncLedger {
  final File file;
  DriveLiveSyncLedger(this.file);

  Future<DriveLiveSyncLedgerState> load() async {
    if (!await file.exists()) return DriveLiveSyncLedgerState.empty;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        return DriveLiveSyncLedgerState.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    } on FormatException catch (e) {
      stderr.writeln('[DriveLiveSyncLedger] Durum okunamadı: ${e.message}');
    }
    return DriveLiveSyncLedgerState.empty;
  }

  Future<void> save(DriveLiveSyncLedgerState state) async {
    if (!await file.parent.exists()) await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(state.toJson()), flush: true);
    await tmp.rename(file.path);
  }
}

/// Zarf üstverisi (şifresiz başlıkta yalnızca yönlendirme ve kimlik; ticari içerik yok).
class DriveSyncEnvelopeMetadata {
  final String envelopeId;
  final int schemaVersion;
  final String tenantId;
  final String storeId;
  final String originDeviceId;
  final int clientSeq;
  final String operationId;
  final String operationType;
  final String payloadHash;
  final DateTime createdAtUtc;
  final int kdfIterations;
  final String? deviceAuthTag;

  const DriveSyncEnvelopeMetadata({
    required this.envelopeId,
    required this.schemaVersion,
    required this.tenantId,
    required this.storeId,
    required this.originDeviceId,
    required this.clientSeq,
    required this.operationId,
    required this.operationType,
    required this.payloadHash,
    required this.createdAtUtc,
    required this.kdfIterations,
    this.deviceAuthTag,
  });

  Map<String, dynamic> toJson() => {
        'v': 1,
        'envelope_id': envelopeId,
        'schema_version': schemaVersion,
        'tenant_id': tenantId,
        'store_id': storeId,
        'origin_device_id': originDeviceId,
        'client_seq': clientSeq,
        'operation_id': operationId,
        'operation_type': operationType,
        'payload_hash': payloadHash,
        'created_at': createdAtUtc.toUtc().toIso8601String(),
        'kdf_iterations': kdfIterations,
        if (deviceAuthTag != null) 'device_auth_tag': deviceAuthTag,
      };

  factory DriveSyncEnvelopeMetadata.fromJson(Map<String, dynamic> json) =>
      DriveSyncEnvelopeMetadata(
        envelopeId: json['envelope_id'] as String,
        schemaVersion: json['schema_version'] as int,
        tenantId: json['tenant_id'] as String,
        storeId: json['store_id'] as String,
        originDeviceId: json['origin_device_id'] as String,
        clientSeq: json['client_seq'] as int,
        operationId: json['operation_id'] as String,
        operationType: json['operation_type'] as String,
        payloadHash: json['payload_hash'] as String,
        createdAtUtc: DateTime.parse(json['created_at'] as String).toUtc(),
        kdfIterations: (json['kdf_iterations'] as int?) ?? 10000,
        deviceAuthTag: json['device_auth_tag'] as String?,
      );
}

class DecryptedSyncEnvelope {
  final DriveSyncEnvelopeMetadata metadata;
  final String payloadJson;

  const DecryptedSyncEnvelope({
    required this.metadata,
    required this.payloadJson,
  });
}

/// `MMSENV01` şifreli ve Encrypt-then-MAC doğrulamalı zarf kodeği.
///
/// Yedek parolasından (`backup_schedule_password_v1`) TAMAMEN AYRI canlı
/// senkronizasyon gizlisi (`drive_live_sync_secret_v1`) ve domain ayırıcısı
/// (`MMS-LIVESYNC-ENV-V1`) ile PBKDF2-HMAC-SHA256 anahtarları türetir.
class EncryptedSyncEnvelopeCodec {
  EncryptedSyncEnvelopeCodec._();

  static final List<int> magicHeader = utf8.encode('MMSENV01');
  static const String domainSeparator = 'MMS-LIVESYNC-ENV-V1';
  static const int defaultKdfIterations = 10000;
  static const int maxEnvelopeBytes = 512 * 1024;
  static final Random _random = Random.secure();

  static DerivedKeys deriveEnvelopeKeys({
    required String liveSyncSecret,
    required String tenantId,
    required String storeId,
    required Uint8List salt,
    int iterations = defaultKdfIterations,
  }) {
    final scopedSecret = '$domainSeparator|$tenantId|$storeId|$liveSyncSecret';
    return BackupCryptoService.deriveKeys(
      password: scopedSecret,
      salt: salt,
      iterations: iterations,
    );
  }

  static String computeDeviceAuthTag({
    required String deviceKey,
    required String tenantId,
    required String storeId,
    required String originDeviceId,
    required int clientSeq,
    required String operationId,
    required String payloadHash,
  }) {
    final mac = Hmac(sha256, utf8.encode(deviceKey));
    return mac
        .convert(
          utf8.encode(
            '$domainSeparator|$tenantId|$storeId|$originDeviceId|$clientSeq|$operationId|$payloadHash',
          ),
        )
        .toString();
  }

  static Uint8List encryptEnvelope({
    required DriveSyncEnvelopeMetadata metadata,
    required String payloadJson,
    required String liveSyncSecret,
    String? deviceKey,
  }) {
    if (liveSyncSecret.isEmpty) {
      throw const DriveSyncSecurityException(
        'ERR_LIVESYNC_SECRET_MISSING',
        'Canlı senkronizasyon şifreleme sırrı yapılandırılmamış.',
      );
    }

    final salt = Uint8List.fromList(List<int>.generate(16, (_) => _random.nextInt(256)));
    final iv = Uint8List.fromList(List<int>.generate(16, (_) => _random.nextInt(256)));
    final keys = deriveEnvelopeKeys(
      liveSyncSecret: liveSyncSecret,
      tenantId: metadata.tenantId,
      storeId: metadata.storeId,
      salt: salt,
      iterations: metadata.kdfIterations,
    );

    final inner = jsonEncode(<String, dynamic>{
      'operation_id': metadata.operationId,
      'operation_type': metadata.operationType,
      'origin_device_id': metadata.originDeviceId,
      'client_seq': metadata.clientSeq,
      'payload_hash': metadata.payloadHash,
      'payload_json': payloadJson,
    });
    final ciphertext = Aes256Cbc.encrypt(
      plaintext: Uint8List.fromList(utf8.encode(inner)),
      key: keys.encryptionKey,
      iv: iv,
    );

    final finalMeta = DriveSyncEnvelopeMetadata(
      envelopeId: metadata.envelopeId,
      schemaVersion: metadata.schemaVersion,
      tenantId: metadata.tenantId,
      storeId: metadata.storeId,
      originDeviceId: metadata.originDeviceId,
      clientSeq: metadata.clientSeq,
      operationId: metadata.operationId,
      operationType: metadata.operationType,
      payloadHash: metadata.payloadHash,
      createdAtUtc: metadata.createdAtUtc,
      kdfIterations: metadata.kdfIterations,
      deviceAuthTag: deviceKey != null
          ? computeDeviceAuthTag(
              deviceKey: deviceKey,
              tenantId: metadata.tenantId,
              storeId: metadata.storeId,
              originDeviceId: metadata.originDeviceId,
              clientSeq: metadata.clientSeq,
              operationId: metadata.operationId,
              payloadHash: metadata.payloadHash,
            )
          : metadata.deviceAuthTag,
    );

    final metaBytes = utf8.encode(jsonEncode(finalMeta.toJson()));
    final metaLen = metaBytes.length;

    final builder = BytesBuilder(copy: false)
      ..add(magicHeader)
      ..add([
        (metaLen >> 24) & 0xff,
        (metaLen >> 16) & 0xff,
        (metaLen >> 8) & 0xff,
        metaLen & 0xff,
      ])
      ..add(metaBytes)
      ..add(salt)
      ..add(iv)
      ..add(ciphertext);

    final unsigned = builder.toBytes();
    final tag = Hmac(sha256, keys.hmacKey).convert(unsigned).bytes;

    final out = BytesBuilder(copy: false)
      ..add(unsigned)
      ..add(tag);
    final result = out.toBytes();
    if (result.length > maxEnvelopeBytes) {
      throw const DriveSyncSecurityException(
        'ERR_ENVELOPE_TOO_LARGE',
        'Canlı senkronizasyon zarfı izin verilen 512 KB sınırını aşıyor.',
      );
    }
    return result;
  }

  static DriveSyncEnvelopeMetadata inspectMetadataWithoutDecryption(
    Uint8List envelopeBytes,
  ) {
    if (envelopeBytes.length < 112 || envelopeBytes.length > maxEnvelopeBytes) {
      throw const DriveSyncSecurityException(
        'ERR_ENVELOPE_CORRUPT',
        'Senkronizasyon zarf boyutu geçersiz.',
      );
    }
    for (var i = 0; i < 8; i++) {
      if (envelopeBytes[i] != magicHeader[i]) {
        throw const DriveSyncSecurityException(
          'ERR_ENVELOPE_MAGIC',
          'Geçersiz MMSENV01 zarf başlığı.',
        );
      }
    }
    final metaLen = (envelopeBytes[8] << 24) |
        (envelopeBytes[9] << 16) |
        (envelopeBytes[10] << 8) |
        envelopeBytes[11];
    if (metaLen <= 0 || 12 + metaLen + 16 + 16 + 16 + 32 > envelopeBytes.length) {
      throw const DriveSyncSecurityException(
        'ERR_ENVELOPE_CORRUPT',
        'Zarf üstveri uzunluğu bozuk.',
      );
    }
    final metaJson = utf8.decode(envelopeBytes.sublist(12, 12 + metaLen));
    final raw = jsonDecode(metaJson);
    if (raw is! Map) {
      throw const DriveSyncSecurityException(
        'ERR_ENVELOPE_CORRUPT',
        'Zarf üstveri JSON biçimi geçersiz.',
      );
    }
    return DriveSyncEnvelopeMetadata.fromJson(Map<String, dynamic>.from(raw));
  }

  static DecryptedSyncEnvelope verifyAndDecryptEnvelope({
    required Uint8List envelopeBytes,
    required String liveSyncSecret,
    required String expectedTenantId,
    required String expectedStoreId,
    DriveAuthorizedDeviceRegistry? deviceRegistry,
    int maxSupportedSchemaVersion = 4,
  }) {
    if (liveSyncSecret.isEmpty) {
      throw const DriveSyncSecurityException(
        'ERR_LIVESYNC_SECRET_MISSING',
        'Canlı senkronizasyon sırrı yok.',
      );
    }

    final meta = inspectMetadataWithoutDecryption(envelopeBytes);
    if (meta.tenantId != expectedTenantId || meta.storeId != expectedStoreId) {
      throw DriveSyncSecurityException(
        'ERR_TENANT_STORE_MISMATCH',
        'Zarf farklı tenant/store ($expectedTenantId/$expectedStoreId != ${meta.tenantId}/${meta.storeId}) içeriyor.',
      );
    }
    if (meta.schemaVersion > maxSupportedSchemaVersion) {
      throw DriveSyncSecurityException(
        'ERR_SCHEMA_TOO_NEW',
        'Zarf şema sürümü (${meta.schemaVersion}) desteklenmiyor.',
      );
    }

    if (deviceRegistry != null) {
      final dev = deviceRegistry.requireAuthorized(
        deviceId: meta.originDeviceId,
        tenantId: expectedTenantId,
        storeId: expectedStoreId,
      );
      if (dev.deviceSecretOrPublicKey != null &&
          dev.deviceSecretOrPublicKey!.isNotEmpty) {
        final expectedTag = computeDeviceAuthTag(
          deviceKey: dev.deviceSecretOrPublicKey!,
          tenantId: meta.tenantId,
          storeId: meta.storeId,
          originDeviceId: meta.originDeviceId,
          clientSeq: meta.clientSeq,
          operationId: meta.operationId,
          payloadHash: meta.payloadHash,
        );
        if (meta.deviceAuthTag == null ||
            !BackupCryptoService.constantTimeEquals(
              utf8.encode(meta.deviceAuthTag!),
              utf8.encode(expectedTag),
            )) {
          throw DriveSyncSecurityException(
            'ERR_DEVICE_SIGNATURE_INVALID',
            'Cihaz imza/kimlik doğrulaması geçersiz (${meta.originDeviceId}).',
          );
        }
      }
    }

    final metaLen = (envelopeBytes[8] << 24) |
        (envelopeBytes[9] << 16) |
        (envelopeBytes[10] << 8) |
        envelopeBytes[11];
    final saltOffset = 12 + metaLen;
    final ivOffset = saltOffset + 16;
    final cipherOffset = ivOffset + 16;
    final tagOffset = envelopeBytes.length - 32;

    final salt = Uint8List.sublistView(envelopeBytes, saltOffset, ivOffset);
    final iv = Uint8List.sublistView(envelopeBytes, ivOffset, cipherOffset);
    final ciphertext = Uint8List.sublistView(envelopeBytes, cipherOffset, tagOffset);
    final expectedTag = Uint8List.sublistView(envelopeBytes, tagOffset);

    final keys = deriveEnvelopeKeys(
      liveSyncSecret: liveSyncSecret,
      tenantId: meta.tenantId,
      storeId: meta.storeId,
      salt: salt,
      iterations: meta.kdfIterations,
    );

    final actualTag = Hmac(sha256, keys.hmacKey)
        .convert(Uint8List.sublistView(envelopeBytes, 0, tagOffset))
        .bytes;
    if (!BackupCryptoService.constantTimeEquals(actualTag, expectedTag)) {
      throw const DriveSyncSecurityException(
        'ERR_ENVELOPE_HMAC_FAILED',
        'Canlı senkronizasyon zarfı HMAC doğrulaması başarısız (yanlış anahtar veya bozulma).',
      );
    }

    final Uint8List plaintextBytes;
    try {
      plaintextBytes = Aes256Cbc.decrypt(
        ciphertext: ciphertext,
        key: keys.encryptionKey,
        iv: iv,
      );
    } catch (e) {
      throw DriveSyncSecurityException(
        'ERR_ENVELOPE_DECRYPT_FAILED',
        'Zarf çözülemedi: $e',
      );
    }

    final inner = jsonDecode(utf8.decode(plaintextBytes)) as Map<String, dynamic>;
    final payloadJson = inner['payload_json'] as String;
    if (inner['operation_id'] != meta.operationId ||
        inner['origin_device_id'] != meta.originDeviceId ||
        inner['client_seq'] != meta.clientSeq ||
        inner['operation_type'] != meta.operationType) {
      throw const DriveSyncSecurityException(
        'ERR_ENVELOPE_METADATA_MISMATCH',
        'Zarf iç kimlik bilgileri başlıkla uyuşmuyor.',
      );
    }

    final computedPayloadHash = sha256.convert(utf8.encode(payloadJson)).toString();
    if (meta.operationType == 'PRODUCT_UPSERT' || meta.operationType == 'STOCK_RECEIPT') {
      if (!BackupCryptoService.constantTimeEquals(
        utf8.encode(computedPayloadHash),
        utf8.encode(meta.payloadHash),
      )) {
        throw const DriveSyncSecurityException(
          'ERR_ENVELOPE_PAYLOAD_HASH_MISMATCH',
          'Zarf payload SHA-256 özeti uyuşmuyor.',
        );
      }
    } else {
      final canonicalHash = ClientStorageRepository.computeSaleRequestHash(
        Map<String, dynamic>.from(jsonDecode(payloadJson) as Map),
      );
      if (!BackupCryptoService.constantTimeEquals(
            utf8.encode(canonicalHash),
            utf8.encode(meta.payloadHash),
          ) &&
          !BackupCryptoService.constantTimeEquals(
            utf8.encode(computedPayloadHash),
            utf8.encode(meta.payloadHash),
          )) {
        throw const DriveSyncSecurityException(
          'ERR_ENVELOPE_PAYLOAD_HASH_MISMATCH',
          'Satış zarfı payload hash doğrulaması geçemedi.',
        );
      }
    }

    return DecryptedSyncEnvelope(
      metadata: meta,
      payloadJson: payloadJson,
    );
  }
}

class DriveRemoteEnvelopeEntry {
  final String fileId;
  final String fileName;
  final String originDeviceId;
  final int clientSeq;
  final String operationId;
  final String operationType;
  final String tenantId;
  final String storeId;
  final String? sha256Hex;

  const DriveRemoteEnvelopeEntry({
    required this.fileId,
    required this.fileName,
    required this.originDeviceId,
    required this.clientSeq,
    required this.operationId,
    required this.operationType,
    required this.tenantId,
    required this.storeId,
    this.sha256Hex,
  });

  static DriveRemoteEnvelopeEntry? tryParse(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final name = json['name'] as String?;
    if (id == null || name == null || !name.endsWith('.mmsenv')) return null;
    final propsRaw = json['appProperties'];
    if (propsRaw is! Map) return null;
    final props = Map<String, dynamic>.from(propsRaw);
    final devId = props['mms_device_id'] as String?;
    final seqStr = props['mms_client_seq']?.toString();
    final opId = props['mms_op_id'] as String?;
    final opType = props['mms_op_type'] as String?;
    final tenant = props['mms_tenant_id'] as String?;
    final store = props['mms_store_id'] as String?;
    final seq = int.tryParse(seqStr ?? '');
    if (devId == null ||
        seq == null ||
        opId == null ||
        opType == null ||
        tenant == null ||
        store == null) {
      return null;
    }
    return DriveRemoteEnvelopeEntry(
      fileId: id,
      fileName: name,
      originDeviceId: devId,
      clientSeq: seq,
      operationId: opId,
      operationType: opType,
      tenantId: tenant,
      storeId: store,
      sha256Hex: props['mms_sha256'] as String?,
    );
  }
}

/// Google Drive LiveSync transport sözleşmesi (`drive.file`).
abstract class DriveLiveEnvelopeTransport {
  Future<String> ensureSyncFolder();

  Future<String> uploadEnvelope({
    required String folderId,
    required String fileName,
    required Uint8List bytes,
    required Map<String, String> appProperties,
  });

  Future<List<DriveRemoteEnvelopeEntry>> listEnvelopes({
    required String folderId,
    required String tenantId,
    required String storeId,
  });

  Future<Uint8List> downloadEnvelope({required String fileId});
}

class GoogleDriveLiveEnvelopeTransport implements DriveLiveEnvelopeTransport {
  static const String folderName = 'MARKET MMS LiveSync';
  static const String _folderMime = 'application/vnd.google-apps.folder';

  final DriveAccessTokenProvider tokenProvider;
  final http.Client httpClient;
  final int maxAttempts;
  final Duration baseDelay;
  final Future<void> Function(Duration) delay;
  final Duration requestTimeout;

  String? _cachedFolderId;

  GoogleDriveLiveEnvelopeTransport({
    required this.tokenProvider,
    required this.httpClient,
    this.maxAttempts = 4,
    this.baseDelay = const Duration(seconds: 1),
    Future<void> Function(Duration)? delay,
    this.requestTimeout = const Duration(seconds: 30),
  }) : delay = delay ?? Future.delayed;

  @override
  Future<String> ensureSyncFolder() async {
    if (_cachedFolderId != null) return _cachedFolderId!;
    final q = "mimeType = '$_folderMime' and name = '${_esc(folderName)}' and trashed = false";
    final listResp = await _send(
      (token) => httpClient.get(
        Uri.https('www.googleapis.com', '/drive/v3/files', {
          'q': q,
          'fields': 'files(id)',
          'spaces': 'drive',
        }),
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
    final files = (_dec(listResp.body)['files'] as List<dynamic>?) ?? const [];
    if (files.isNotEmpty) {
      final id = (files.first as Map)['id'] as String?;
      if (id != null && id.isNotEmpty) {
        _cachedFolderId = id;
        return id;
      }
    }
    final createResp = await _send(
      (token) => httpClient.post(
        Uri.https('www.googleapis.com', '/drive/v3/files', {'fields': 'id'}),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'name': folderName, 'mimeType': _folderMime}),
      ),
    );
    final id = _dec(createResp.body)['id'] as String?;
    if (id == null || id.isEmpty) {
      throw const DriveBackupException(
        'ERR_DRIVE_UNAVAILABLE',
        'Google Drive LiveSync klasörü oluşturulamadı.',
      );
    }
    _cachedFolderId = id;
    return id;
  }

  @override
  Future<String> uploadEnvelope({
    required String folderId,
    required String fileName,
    required Uint8List bytes,
    required Map<String, String> appProperties,
  }) async {
    final initResp = await _send(
      (token) => httpClient.post(
        Uri.https('www.googleapis.com', '/upload/drive/v3/files', {
          'uploadType': 'resumable',
        }),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=utf-8',
          'X-Upload-Content-Type': 'application/octet-stream',
          'X-Upload-Content-Length': bytes.length.toString(),
        },
        body: jsonEncode({
          'name': fileName,
          'parents': [folderId],
          'appProperties': appProperties,
        }),
      ),
    );
    final location = initResp.headers['location'];
    if (location == null || location.isEmpty) {
      throw const DriveBackupException(
        'ERR_DRIVE_UNAVAILABLE',
        'Drive resumable envelope upload location alınamadı.',
      );
    }
    final putResp = await _send(
      (token) => httpClient.put(
        Uri.parse(location),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/octet-stream',
        },
        body: bytes,
      ),
    );
    final id = _dec(putResp.body)['id'] as String?;
    if (id == null || id.isEmpty) {
      throw const DriveBackupException(
        'ERR_DRIVE_VERIFY_FAILED',
        'Drive yüklenen zarf kimliği döndürmedi.',
      );
    }
    return id;
  }

  @override
  Future<List<DriveRemoteEnvelopeEntry>> listEnvelopes({
    required String folderId,
    required String tenantId,
    required String storeId,
  }) async {
    final entries = <DriveRemoteEnvelopeEntry>[];
    String? pageToken;
    do {
      final resp = await _send(
        (token) => httpClient.get(
          Uri.https('www.googleapis.com', '/drive/v3/files', {
            'q': "'${_esc(folderId)}' in parents and trashed = false",
            'fields': 'nextPageToken,files(id,name,appProperties)',
            'spaces': 'drive',
            'pageSize': '200',
            if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
          }),
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      final body = _dec(resp.body);
      final files = body['files'] as List<dynamic>? ?? const [];
      for (final f in files) {
        if (f is! Map) continue;
        final parsed = DriveRemoteEnvelopeEntry.tryParse(Map<String, dynamic>.from(f));
        if (parsed != null &&
            parsed.tenantId == tenantId &&
            parsed.storeId == storeId) {
          entries.add(parsed);
        }
      }
      final next = body['nextPageToken'];
      pageToken = next is String && next.isNotEmpty ? next : null;
    } while (pageToken != null);
    return entries;
  }

  @override
  Future<Uint8List> downloadEnvelope({required String fileId}) async {
    final resp = await _send(
      (token) => httpClient.get(
        Uri.https('www.googleapis.com', '/drive/v3/files/${Uri.encodeComponent(fileId)}', {
          'alt': 'media',
        }),
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
    return resp.bodyBytes;
  }

  Future<http.Response> _send(Future<http.Response> Function(String token) fn) async {
    var refreshedOnce = false;
    for (var attempt = 1;; attempt++) {
      final token = await tokenProvider.accessToken(forceRefresh: refreshedOnce);
      try {
        final resp = await fn(token).timeout(requestTimeout);
        if (resp.statusCode >= 200 && resp.statusCode < 300) return resp;
        if (resp.statusCode == 401 && !refreshedOnce) {
          refreshedOnce = true;
          continue;
        }
        final retryable = resp.statusCode == 429 || resp.statusCode >= 500;
        if (!retryable) {
          throw DriveBackupException(
            resp.statusCode == 401 || resp.statusCode == 403
                ? 'ERR_DRIVE_REAUTH_REQUIRED'
                : 'ERR_DRIVE_REJECTED',
            'Drive LiveSync reddedildi (HTTP ${resp.statusCode}).',
          );
        }
        if (attempt >= maxAttempts) {
          throw DriveBackupException(
            'ERR_DRIVE_UNAVAILABLE',
            'Drive LiveSync kullanılamıyor (HTTP ${resp.statusCode}).',
          );
        }
      } on DriveBackupException {
        rethrow;
      } on Exception catch (e) {
        if (attempt >= maxAttempts) {
          throw DriveBackupException(
            'ERR_DRIVE_UNAVAILABLE',
            'Drive LiveSync bağlantı hatası: ${e.runtimeType}',
          );
        }
      }
      await delay(baseDelay * (1 << (attempt - 1)));
    }
  }

  static String _esc(String v) => v.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  static Map<String, dynamic> _dec(String body) {
    if (body.isEmpty) return const {};
    try {
      final d = jsonDecode(body);
      return d is Map ? Map<String, dynamic>.from(d) : const {};
    } on FormatException {
      return const {};
    }
  }
}

class DriveFallbackCycleResult {
  final int uploadedCount;
  final int appliedCount;
  final int skippedDuplicateCount;
  final int deferredGapCount;
  final int rejectedSecurityCount;
  final List<DriveSyncConflictRecord> newConflicts;
  final bool skippedLockBusy;
  final String? errorMessage;

  const DriveFallbackCycleResult({
    this.uploadedCount = 0,
    this.appliedCount = 0,
    this.skippedDuplicateCount = 0,
    this.deferredGapCount = 0,
    this.rejectedSecurityCount = 0,
    this.newConflicts = const [],
    this.skippedLockBusy = false,
    this.errorMessage,
  });

  bool get hasErrors => errorMessage != null;
  bool get hasConflicts => newConflicts.isNotEmpty;
}

class HubReconciliationResult {
  final bool reconciled;
  final int pushedOutboxCount;
  final int pulledProductsCount;
  final int pulledSalesCount;
  final int clearedConflictCount;
  final String? errorMessage;

  const HubReconciliationResult({
    required this.reconciled,
    this.pushedOutboxCount = 0,
    this.pulledProductsCount = 0,
    this.pulledSalesCount = 0,
    this.clearedConflictCount = 0,
    this.errorMessage,
  });
}

/// ADR-021: Hub Öncelikli Hibrit + Google Drive Canlı Senkronizasyon Motoru.
class MmsDriveLiveSyncEngine {
  final ClientStorageRepository repository;
  final DriveLiveEnvelopeTransport transport;
  final DriveLiveSyncLedger ledger;
  final DriveAuthorizedDeviceRegistry deviceRegistry;
  final String tenantId;
  final String storeId;
  final String localDeviceId;
  final Future<String?> Function() readLiveSyncSecret;
  final File? operationLockFile;
  final int fallbackFailureThreshold;
  final int kdfIterations;
  final DateTime Function() clock;

  MmsDriveLiveSyncEngine({
    required this.repository,
    required this.transport,
    required this.ledger,
    required this.deviceRegistry,
    required this.tenantId,
    required this.storeId,
    required this.localDeviceId,
    required this.readLiveSyncSecret,
    this.operationLockFile,
    this.fallbackFailureThreshold = 2,
    this.kdfIterations = EncryptedSyncEnvelopeCodec.defaultKdfIterations,
    DateTime Function()? clock,
  }) : clock = clock ?? (() => DateTime.now().toUtc());

  Future<DriveLiveSyncLedgerState> getLedgerState() => ledger.load();

  /// Hub normal yanıt verdiğinde fallback sayacı sıfırlanır (Hub önceliği).
  Future<DriveLiveSyncLedgerState> recordHubHealthy() async {
    final current = await ledger.load();
    final updated = current.copyWith(
      consecutiveHubFailures: 0,
      driveFallbackActive: false,
      clearLastError: true,
    );
    await ledger.save(updated);
    return updated;
  }

  /// Hub hatası kaydeder; güvenlik (TLS pin/cert) veya yetki hatalarında ASLA fallback açmaz.
  Future<DriveLiveSyncLedgerState> recordHubFailure({
    required bool isSecurityHold,
    required bool isAuthFailure,
    bool isPaused = false,
  }) async {
    final current = await ledger.load();
    if (isSecurityHold || isAuthFailure || isPaused) {
      final blocked = current.copyWith(
        driveFallbackActive: false,
      );
      await ledger.save(blocked);
      return blocked;
    }
    final nextFailures = current.consecutiveHubFailures + 1;
    final activateFallback = nextFailures >= fallbackFailureThreshold;
    final updated = current.copyWith(
      consecutiveHubFailures: nextFailures,
      driveFallbackActive: activateFallback || current.driveFallbackActive,
    );
    await ledger.save(updated);
    return updated;
  }

  /// Hub doğrulanmış şekilde çevrimdışı iken Drive üzerinden şifreli zarf alışverişi yapar.
  /// - Cihazın kendi `outbox_operations` satırları Drive'a yazılsa da ASLA `SYNCED` yapılmaz.
  /// - Uzaktan gelen zarflar `(origin_device_id, client_seq)` sırasıyla bitişik uygulanır.
  /// - Başka cihazın işlemleri yerel `outbox_operations`'a eklenmez (echo loop engeli).
  /// - `PRODUCT_UPSERT` çakışmalarında sessiz LWW yapılmaz; çakışma kaydı üretilir.
  Future<DriveFallbackCycleResult> runDriveFallbackCycle() async {
    Future<DriveFallbackCycleResult> execute() async {
      final secret = await readLiveSyncSecret();
      if (secret == null || secret.isEmpty) {
        return const DriveFallbackCycleResult(
          errorMessage: 'Canlı senkronizasyon sırrı (drive_live_sync_secret_v1) yapılandırılmadı.',
        );
      }

      late final DriveAuthorizedDevice localAuth;
      try {
        localAuth = deviceRegistry.requireAuthorized(
          deviceId: localDeviceId,
          tenantId: tenantId,
          storeId: storeId,
        );
      } on DriveSyncSecurityException catch (e) {
        return DriveFallbackCycleResult(
          rejectedSecurityCount: 1,
          errorMessage: e.message,
        );
      }

      var state = await ledger.load();
      final folderId = state.folderId ?? await transport.ensureSyncFolder();
      if (state.folderId != folderId) {
        state = state.copyWith(folderId: folderId);
        await ledger.save(state);
      }

      final uploadedMap = Map<String, int>.from(state.lastUploadedSeqByDevice);
      final uploadedFileIds = Map<String, String>.from(state.uploadedEnvelopeFileIds);
      final appliedMap = Map<String, int>.from(state.lastAppliedSeqByDevice);
      final conflicts = List<DriveSyncConflictRecord>.from(state.conflicts);
      final newConflicts = <DriveSyncConflictRecord>[];

      var uploadedCount = 0;
      var appliedCount = 0;
      var skippedDup = 0;
      var deferredGap = 0;
      var rejectedSec = 0;

      // 1. UPLINK TO DRIVE: Yerel bekleyen Outbox satırlarını yükle (Outbox status'u ASLA değiştirme!)
      final pendingOutbox = await repository.getUnsyncedOutboxOperations(localDeviceId);
      final lastUploaded = uploadedMap[localDeviceId] ?? 0;

      for (final op in pendingOutbox) {
        if (op.clientSeq <= lastUploaded &&
            uploadedFileIds.containsKey('$localDeviceId:${op.clientSeq}')) {
          continue;
        }
        final envelopeKey = '$localDeviceId:${op.clientSeq}';
        if (uploadedFileIds.containsKey(envelopeKey)) continue;

        final nowUtc = clock();
        final meta = DriveSyncEnvelopeMetadata(
          envelopeId: 'env_${localDeviceId}_${op.clientSeq}',
          schemaVersion: repository.db.schemaVersion,
          tenantId: tenantId,
          storeId: storeId,
          originDeviceId: localDeviceId,
          clientSeq: op.clientSeq,
          operationId: op.operationId,
          operationType: op.operationType,
          payloadHash: op.payloadHash,
          createdAtUtc: nowUtc,
          kdfIterations: kdfIterations,
        );

        final encryptedBytes = EncryptedSyncEnvelopeCodec.encryptEnvelope(
          metadata: meta,
          payloadJson: op.payload,
          liveSyncSecret: secret,
          deviceKey: localAuth.deviceSecretOrPublicKey,
        );
        final fileName =
            'env_${_safePart(tenantId)}_${_safePart(storeId)}_${_safePart(localDeviceId)}_'
            '${op.clientSeq.toString().padLeft(12, '0')}_${_safePart(op.operationId)}.mmsenv';
        final fileId = await transport.uploadEnvelope(
          folderId: folderId,
          fileName: fileName,
          bytes: encryptedBytes,
          appProperties: {
            'mms_env_v': '1',
            'mms_tenant_id': tenantId,
            'mms_store_id': storeId,
            'mms_device_id': localDeviceId,
            'mms_client_seq': op.clientSeq.toString(),
            'mms_op_id': op.operationId,
            'mms_op_type': op.operationType,
            'mms_sha256': sha256.convert(encryptedBytes).toString(),
          },
        );

        uploadedFileIds[envelopeKey] = fileId;
        if (op.clientSeq > (uploadedMap[localDeviceId] ?? 0)) {
          uploadedMap[localDeviceId] = op.clientSeq;
        }
        uploadedCount++;
      }

      // 2. DOWNLINK FROM DRIVE: Diğer cihaz zarflarını indir & (origin_device_id, client_seq) bitişik uygula
      final remoteEntries = await transport.listEnvelopes(
        folderId: folderId,
        tenantId: tenantId,
        storeId: storeId,
      );

      final byOrigin = <String, List<DriveRemoteEnvelopeEntry>>{};
      for (final e in remoteEntries) {
        if (e.originDeviceId == localDeviceId) continue; // Kendi zarflarımızı geri uygulamayız (echo guard).
        byOrigin.putIfAbsent(e.originDeviceId, () => []).add(e);
      }

      for (final entry in byOrigin.entries) {
        final originId = entry.key;
        final ops = entry.value..sort((a, b) => a.clientSeq.compareTo(b.clientSeq));

        // Cihaz yetkisi kontrolü (REVOKED / yetkisiz cihaz doğrudan engellenir)
        try {
          deviceRegistry.requireAuthorized(
            deviceId: originId,
            tenantId: tenantId,
            storeId: storeId,
          );
        } on DriveSyncSecurityException {
          rejectedSec += ops.length;
          continue;
        }

        var expectedSeq = (appliedMap[originId] ?? 0) + 1;
        for (final remote in ops) {
          if (remote.clientSeq < expectedSeq) {
            skippedDup++;
            continue;
          }
          if (remote.clientSeq > expectedSeq) {
            // Aradaki işlem gelmeden sonraki client_seq işlenmez!
            deferredGap += ops.where((o) => o.clientSeq > expectedSeq).length;
            break;
          }

          final bytes = await transport.downloadEnvelope(fileId: remote.fileId);
          if (remote.sha256Hex != null && remote.sha256Hex!.isNotEmpty) {
            final actualSha = sha256.convert(bytes).toString().toLowerCase();
            if (!BackupCryptoService.constantTimeEquals(
              utf8.encode(actualSha),
              utf8.encode(remote.sha256Hex!.toLowerCase()),
            )) {
              rejectedSec++;
              break;
            }
          }

          final DecryptedSyncEnvelope decrypted;
          try {
            decrypted = EncryptedSyncEnvelopeCodec.verifyAndDecryptEnvelope(
              envelopeBytes: bytes,
              liveSyncSecret: secret,
              expectedTenantId: tenantId,
              expectedStoreId: storeId,
              deviceRegistry: deviceRegistry,
              maxSupportedSchemaVersion: repository.db.schemaVersion,
            );
          } on DriveSyncSecurityException {
            rejectedSec++;
            break;
          }

          final conflict = await _applyRemoteOperation(decrypted);
          if (conflict != null) {
            final alreadyRecorded = conflicts.any((c) => c.conflictId == conflict.conflictId);
            if (!alreadyRecorded) {
              conflicts.add(conflict);
              newConflicts.add(conflict);
            }
          }
          appliedMap[originId] = remote.clientSeq;
          expectedSeq = remote.clientSeq + 1;
          appliedCount++;
        }
      }

      final nextState = state.copyWith(
        folderId: folderId,
        lastUploadedSeqByDevice: uploadedMap,
        lastAppliedSeqByDevice: appliedMap,
        uploadedEnvelopeFileIds: uploadedFileIds,
        conflicts: conflicts,
        driveFallbackActive: true,
        pendingHubReconciliation:
            state.pendingHubReconciliation || uploadedCount > 0 || appliedCount > 0,
        lastDriveSyncAtUtc: clock(),
        clearLastError: true,
      );
      await ledger.save(nextState);

      return DriveFallbackCycleResult(
        uploadedCount: uploadedCount,
        appliedCount: appliedCount,
        skippedDuplicateCount: skippedDup,
        deferredGapCount: deferredGap,
        rejectedSecurityCount: rejectedSec,
        newConflicts: newConflicts,
      );
    }

    final lockFile = operationLockFile;
    if (lockFile != null) {
      try {
        return await BackupOperationLock(lockFile)
            .synchronized(BackupOperationKind.backup, execute);
      } on BackupException catch (e) {
        if (e.code == BackupOperationLock.busyErrorCode) {
          return const DriveFallbackCycleResult(skippedLockBusy: true);
        }
        rethrow;
      }
    }
    return execute();
  }

  /// Master Hub geri geldiğinde kontrollü birleştirme (Reconciliation):
  /// 1) Yerel bekleyen Outbox'ı FIFO ile Hub'a iter (ancak Hub ACK verirse SYNCED olur).
  /// 2) Authoritative ürün ve satışları Hub'dan indirir.
  /// 3) Her ikisi temiz biterse fallback + pendingHubReconciliation temizlenir.
  Future<HubReconciliationResult> reconcileWithMasterHub({
    required Future<int> Function() pushOutboxToHub,
    required Future<int> Function() pullProductsFromHub,
    required Future<int> Function() pullSalesFromHub,
    required bool Function() isOutboxEmptyOrAllSynced,
  }) async {
    final pushed = await pushOutboxToHub();
    if (!isOutboxEmptyOrAllSynced()) {
      return HubReconciliationResult(
        reconciled: false,
        pushedOutboxCount: pushed,
        errorMessage: 'Bekleyen Outbox işlemleri Master Hub tarafından henüz tamamen onaylanmadı.',
      );
    }
    final products = await pullProductsFromHub();
    final sales = await pullSalesFromHub();

    final current = await ledger.load();
    final resolvedConflicts = current.conflicts
        .map((c) => c.resolved ? c : c.copyWith(resolved: true))
        .toList();
    final clearedCount = current.unresolvedConflicts.length;

    await ledger.save(
      current.copyWith(
        conflicts: resolvedConflicts,
        consecutiveHubFailures: 0,
        driveFallbackActive: false,
        pendingHubReconciliation: false,
        lastHubReconciledAtUtc: clock(),
        clearLastError: true,
      ),
    );

    return HubReconciliationResult(
      reconciled: true,
      pushedOutboxCount: pushed,
      pulledProductsCount: products,
      pulledSalesCount: sales,
      clearedConflictCount: clearedCount,
    );
  }

  Future<DriveSyncConflictRecord?> _applyRemoteOperation(
    DecryptedSyncEnvelope env,
  ) async {
    final meta = env.metadata;
    final payload = Map<String, dynamic>.from(jsonDecode(env.payloadJson) as Map);
    final db = repository.db;

    return db.transaction<DriveSyncConflictRecord?>(() async {
      switch (meta.operationType) {
        case 'PRODUCT_UPSERT':
          final prodMap = Map<String, dynamic>.from(payload['product'] as Map);
          final prodId = prodMap['id'] as String;
          final incomingPrice = prodMap['price'] as int;
          final incomingPriceVer =
              prodMap['price_version_id'] as String? ?? 'pv_remote';

          // Non-LWW çakışma kontrolü: Yerelde bu ürün için bekleyen (Hub'a gitmemiş) PRODUCT_UPSERT
          // veya farklı sürümlü mevcut kayıt varsa sessiz LWW overwrite YAPILMAZ.
          final pendingLocalProductOps = await (db.select(db.outboxOperations)
                ..where((o) =>
                    o.operationType.equals('PRODUCT_UPSERT') &
                    o.status.equals('SYNCED').not()))
              .get();
          final hasPendingLocalEdit = pendingLocalProductOps.any((o) {
            try {
              final m = jsonDecode(o.payload) as Map<String, dynamic>;
              return (m['product'] as Map?)?['id'] == prodId;
            } catch (_) {
              return false;
            }
          });

          final existing = await (db.select(db.localProducts)
                ..where((p) => p.id.equals(prodId)))
              .getSingleOrNull();

          if (hasPendingLocalEdit ||
              (existing != null &&
                  existing.priceVersionId != incomingPriceVer &&
                  existing.price != incomingPrice)) {
            return DriveSyncConflictRecord(
              conflictId: 'cfl_${prodId}_${meta.originDeviceId}_${meta.clientSeq}',
              entityType: 'PRODUCT_UPSERT',
              entityId: prodId,
              originDeviceId: meta.originDeviceId,
              originClientSeq: meta.clientSeq,
              localPriceVersionId: existing?.priceVersionId,
              remotePriceVersionId: incomingPriceVer,
              localPrice: existing?.price,
              remotePrice: incomingPrice,
              reason: hasPendingLocalEdit
                  ? 'Aynı ürün üzerinde bekleyen yerel değişiklik ile uzak cihaz güncellemesi çakıştı (LWW yasak).'
                  : 'İki cihaz arasında ürün fiyat sürümü (${existing?.priceVersionId} vs $incomingPriceVer) çakıştı.',
              detectedAtUtc: clock(),
            );
          }

          if (existing == null) {
            await db.into(db.localProducts).insert(
                  LocalProductsCompanion(
                    id: Value(prodId),
                    barcode: Value(prodMap['barcode'] as String?),
                    name: Value(prodMap['name'] as String),
                    price: Value(incomingPrice),
                    priceVersionId: Value(incomingPriceVer),
                    stock: Value(prodMap['stock'] as int? ?? 0),
                    stockUnit: Value(prodMap['stock_unit'] as String? ?? 'adet'),
                    pricingUnit: Value(prodMap['pricing_unit'] as String? ?? 'adet'),
                    conversionFactorNumerator:
                        Value(prodMap['conversion_factor_numerator'] as int? ?? 1),
                    conversionFactorDenominator:
                        Value(prodMap['conversion_factor_denominator'] as int? ?? 1),
                    vatRate: Value(prodMap['vat_rate'] as int? ?? 20),
                    isActive: Value(prodMap['is_active'] as bool? ?? true),
                    updatedAt: Value(meta.createdAtUtc),
                  ),
                );
            final primaryBc = prodMap['barcode'] as String?;
            if (primaryBc != null && primaryBc.isNotEmpty) {
              final existingBc = await (db.select(db.localProductBarcodes)
                    ..where((b) => b.barcode.equals(primaryBc)))
                  .getSingleOrNull();
              if (existingBc == null) {
                await db.into(db.localProductBarcodes).insert(
                      LocalProductBarcodesCompanion(
                        id: Value('bc_${prodId}_drive_primary'),
                        productId: Value(prodId),
                        barcode: Value(primaryBc),
                        isPrimary: const Value(true),
                        isActive: const Value(true),
                        createdAt: Value(meta.createdAtUtc),
                      ),
                    );
              }
            }
          }
          return null;

        case 'STOCK_RECEIPT':
          final receiptId = payload['receipt_id'] as String;
          final productId = payload['product_id'] as String;
          final qtyMilli = payload['quantity'] as int;
          final existingMove = await (db.select(db.localStockMovements)
                ..where((m) => m.id.equals(receiptId)))
              .getSingleOrNull();
          if (existingMove != null) return null;

          final prod = await (db.select(db.localProducts)
                ..where((p) => p.id.equals(productId)))
              .getSingleOrNull();
          if (prod == null) return null;

          await db.customUpdate(
            'UPDATE local_products SET stock = stock + ?, updated_at = ? WHERE id = ?;',
            variables: [
              Variable.withInt(qtyMilli),
              Variable.withDateTime(meta.createdAtUtc),
              Variable.withString(productId),
            ],
            updates: {db.localProducts},
          );
          await db.into(db.localStockMovements).insert(
                LocalStockMovementsCompanion(
                  id: Value(receiptId),
                  productId: Value(productId),
                  quantity: Value(qtyMilli),
                  unit: Value(payload['unit'] as String? ?? prod.stockUnit),
                  movementType: const Value('GIRIS'),
                  referenceId: Value(receiptId),
                  purchasePrice: Value(payload['unit_purchase_price'] as int?),
                  note: Value(payload['note'] as String?),
                  createdAt: Value(meta.createdAtUtc),
                ),
              );
          return null;

        case 'SALE_CANCEL':
          final saleId = payload['sale_id'] as String?;
          final targetSeq = payload['target_client_seq'] as int?;
          final sale = saleId != null
              ? await (db.select(db.localSales)..where((s) => s.id.equals(saleId)))
                  .getSingleOrNull()
              : (targetSeq != null
                  ? await (db.select(db.localSales)
                        ..where((s) =>
                            s.deviceId.equals(meta.originDeviceId) &
                            s.clientSeq.equals(targetSeq)))
                      .getSingleOrNull()
                  : null);
          if (sale == null || sale.status == 'CANCELLED') return null;

          final items = await (db.select(db.localSaleItems)
                ..where((i) => i.saleId.equals(sale.id)))
              .get();
          for (final item in items) {
            final prod = await (db.select(db.localProducts)
                  ..where((p) => p.id.equals(item.productId)))
                .getSingleOrNull();
            if (prod == null) continue;
            final stockDelta = (item.quantity * prod.conversionFactorNumerator) ~/
                prod.conversionFactorDenominator;
            await db.customUpdate(
              'UPDATE local_products SET stock = stock + ?, updated_at = ? WHERE id = ?;',
              variables: [
                Variable.withInt(stockDelta),
                Variable.withDateTime(meta.createdAtUtc),
                Variable.withString(prod.id),
              ],
              updates: {db.localProducts},
            );
            await db.into(db.localStockMovements).insertOnConflictUpdate(
                  LocalStockMovementsCompanion(
                    id: Value('dsm_cancel_${meta.originDeviceId}_${meta.clientSeq}_${prod.id}'),
                    productId: Value(prod.id),
                    quantity: Value(stockDelta),
                    unit: Value(prod.stockUnit),
                    movementType: const Value('SATIS_IPTALI'),
                    referenceId: Value(sale.id),
                    createdAt: Value(meta.createdAtUtc),
                  ),
                );
          }
          await (db.update(db.localSales)..where((s) => s.id.equals(sale.id))).write(
            LocalSalesCompanion(
              status: const Value('CANCELLED'),
              cancelReason: Value(payload['reason'] as String? ?? 'Drive sync iptal'),
              cancelledAt: Value(meta.createdAtUtc),
            ),
          );
          return null;

        case 'SALE_REFUND':
          final refundId = payload['refund_id'] as String? ??
              'dref_${meta.originDeviceId}_${meta.clientSeq}';
          final existingRef = await (db.select(db.localRefunds)
                ..where((r) =>
                    r.id.equals(refundId) |
                    (r.deviceId.equals(meta.originDeviceId) &
                        r.clientSeq.equals(meta.clientSeq))))
              .getSingleOrNull();
          if (existingRef != null) return null;

          final saleId = payload['sale_id'] as String?;
          final targetSeq = payload['target_client_seq'] as int?;
          var sale = saleId != null
              ? await (db.select(db.localSales)..where((s) => s.id.equals(saleId)))
                  .getSingleOrNull()
              : null;
          sale ??= targetSeq != null
              ? await (db.select(db.localSales)
                    ..where((s) =>
                        s.deviceId.equals(meta.originDeviceId) &
                        s.clientSeq.equals(targetSeq)))
                  .getSingleOrNull()
              : null;
          if (sale == null) return null;
          final resolvedSale = sale;

          await db.into(db.localRefunds).insert(
                LocalRefundsCompanion(
                  id: Value(refundId),
                  saleId: Value(resolvedSale.id),
                  deviceId: Value(meta.originDeviceId),
                  clientSeq: Value(meta.clientSeq),
                  totalRefundAmount: Value(payload['total_refund_amount'] as int),
                  paymentMethod: Value(
                    payload['payment_method'] as String? ?? resolvedSale.paymentMethod,
                  ),
                  reason: Value(payload['reason'] as String? ?? 'Drive sync iade'),
                  createdAt: Value(meta.createdAtUtc),
                ),
              );
          final items = payload['items'] as List<dynamic>? ?? const [];
          for (final rawItem in items) {
            final item = Map<String, dynamic>.from(rawItem as Map);
            final prodId = item['product_id'] as String;
            final qty = item['quantity'] as int;
            final condition = item['product_condition'] as String? ?? 'SELLABLE';
            final saleItem = await (db.select(db.localSaleItems)
                  ..where((si) =>
                      si.saleId.equals(resolvedSale.id) &
                      si.productId.equals(prodId)))
                .getSingleOrNull();
            if (saleItem != null) {
              await db.into(db.localRefundItems).insertOnConflictUpdate(
                    LocalRefundItemsCompanion(
                      id: Value('drefitem_${refundId}_$prodId'),
                      refundId: Value(refundId),
                      saleItemId: Value(saleItem.id),
                      productId: Value(prodId),
                      quantity: Value(qty),
                      unitPrice: Value(item['unit_price'] as int? ?? saleItem.unitPrice),
                      refundAmount: Value(
                        item['refund_amount'] as int? ??
                            (((saleItem.unitPrice * qty) + 500) ~/ 1000),
                      ),
                      productCondition: Value(condition),
                      createdAt: Value(meta.createdAtUtc),
                    ),
                  );
            }
            final prod = await (db.select(db.localProducts)
                  ..where((p) => p.id.equals(prodId)))
                .getSingleOrNull();
            if (prod != null) {
              final delta = (qty * prod.conversionFactorNumerator) ~/
                  prod.conversionFactorDenominator;
              if (condition == 'SELLABLE') {
                await db.customUpdate(
                  'UPDATE local_products SET stock = stock + ?, updated_at = ? WHERE id = ?;',
                  variables: [
                    Variable.withInt(delta),
                    Variable.withDateTime(meta.createdAtUtc),
                    Variable.withString(prod.id),
                  ],
                  updates: {db.localProducts},
                );
              }
              await db.into(db.localStockMovements).insertOnConflictUpdate(
                    LocalStockMovementsCompanion(
                      id: Value('dsm_ref_${refundId}_$prodId'),
                      productId: Value(prodId),
                      quantity: Value(delta),
                      unit: Value(prod.stockUnit),
                      movementType: Value(
                        condition == 'SELLABLE' ? 'MUSTERI_IADESI' : 'FIRE_KAYIP',
                      ),
                      referenceId: Value(refundId),
                      createdAt: Value(meta.createdAtUtc),
                    ),
                  );
            }
          }
          await (db.update(db.localSales)
                ..where((s) => s.id.equals(resolvedSale.id)))
              .write(
            const LocalSalesCompanion(status: Value('PARTIALLY_REFUNDED')),
          );
          return null;

        case 'SALE_CREATE':
        default:
          // Idempotent kontrol: Aynı (device_id, client_seq) zaten yerelde varsa geç.
          final existingSale = await (db.select(db.localSales)
                ..where((s) =>
                    s.deviceId.equals(meta.originDeviceId) &
                    s.clientSeq.equals(meta.clientSeq)))
              .getSingleOrNull();
          if (existingSale != null) return null;

          final saleId = payload['sale_id'] as String? ??
              'dsale_${meta.originDeviceId}_${meta.clientSeq}';
          final items = (payload['items'] as List<dynamic>? ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();

          for (final item in items) {
            final prodId = item['product_id'] as String;
            final existingProd = await (db.select(db.localProducts)
                  ..where((p) => p.id.equals(prodId)))
                .getSingleOrNull();
            if (existingProd == null) {
              await db.into(db.localProducts).insert(
                    LocalProductsCompanion(
                      id: Value(prodId),
                      name: Value(item['product_name'] as String? ?? prodId),
                      price: Value(item['unit_price'] as int? ?? 0),
                      priceVersionId:
                          Value(item['price_version_id'] as String? ?? 'pv_remote'),
                      stock: const Value(0),
                      stockUnit: Value(item['unit'] as String? ?? 'adet'),
                      pricingUnit: Value(item['unit'] as String? ?? 'adet'),
                      updatedAt: Value(meta.createdAtUtc),
                    ),
                  );
            }
          }

          await db.into(db.localSales).insert(
                LocalSalesCompanion(
                  id: Value(saleId),
                  deviceId: Value(meta.originDeviceId),
                  clientSeq: Value(meta.clientSeq),
                  totalAmount: Value(payload['total_amount'] as int),
                  paymentMethod: Value(payload['payment_method'] as String),
                  status: const Value('COMPLETED'),
                  createdAt: Value(meta.createdAtUtc),
                ),
              );

          for (final item in items) {
            final prodId = item['product_id'] as String;
            final qty = item['quantity'] as int;
            final unitPrice = item['unit_price'] as int? ?? 0;
            final totalPrice =
                item['total_price'] as int? ?? (((unitPrice * qty) + 500) ~/ 1000);
            final prod = await (db.select(db.localProducts)
                  ..where((p) => p.id.equals(prodId)))
                .getSingle();

            await db.into(db.localSaleItems).insertOnConflictUpdate(
                  LocalSaleItemsCompanion(
                    id: Value('ditem_${saleId}_$prodId'),
                    saleId: Value(saleId),
                    productId: Value(prodId),
                    productNameSnapshot: Value(prod.name),
                    unitSnapshot: Value(item['unit'] as String? ?? prod.pricingUnit),
                    priceVersionId: Value(
                      item['price_version_id'] as String? ?? prod.priceVersionId,
                    ),
                    unitPrice: Value(unitPrice),
                    quantity: Value(qty),
                    totalPrice: Value(totalPrice),
                  ),
                );

            final stockDelta = (qty * prod.conversionFactorNumerator) ~/
                prod.conversionFactorDenominator;
            await db.customUpdate(
              'UPDATE local_products SET stock = stock - ?, updated_at = ? WHERE id = ?;',
              variables: [
                Variable.withInt(stockDelta),
                Variable.withDateTime(meta.createdAtUtc),
                Variable.withString(prodId),
              ],
              updates: {db.localProducts},
            );
            await db.into(db.localStockMovements).insertOnConflictUpdate(
                  LocalStockMovementsCompanion(
                    id: Value('dsm_${saleId}_$prodId'),
                    productId: Value(prodId),
                    quantity: Value(-stockDelta),
                    unit: Value(prod.stockUnit),
                    movementType: const Value('SATIS'),
                    referenceId: Value(saleId),
                    createdAt: Value(meta.createdAtUtc),
                  ),
                );
          }
          return null;
      }
    });
  }

  static String _safePart(String raw) =>
      raw.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
}
