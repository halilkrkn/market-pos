import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../logging/redacting_logger.dart';

/// Hub `/api/v1/devices/me` üzerinden doğrulanan cihaz rolü durumu.
enum DeviceRoleVerificationStatus {
  unauthenticated,
  verifying,
  verified,
  unauthorized,
  unreachable,
}

/// İstemci cihazın Hub tarafından doğrulanmış rol ve oturum geçerlilik durumu.
///
/// Varsayılan ve her türlü hata/eksik durumda fail-closed olarak `'CASHIER'` döner.
class DeviceRoleState {
  static const String roleOwner = 'OWNER';
  static const String roleCashier = 'CASHIER';
  static const Duration defaultCacheTtl = Duration(minutes: 5);

  final String verifiedRole;
  final DeviceRoleVerificationStatus status;
  final String boundDeviceId;
  final String? boundHubUrl;
  final String? boundToken;
  final DateTime? verifiedAtUtc;
  final DateTime? expiresAtUtc;
  final bool? ownerBootstrapCompleted;
  final String? errorCode;

  const DeviceRoleState({
    required this.verifiedRole,
    required this.status,
    required this.boundDeviceId,
    this.boundHubUrl,
    this.boundToken,
    this.verifiedAtUtc,
    this.expiresAtUtc,
    this.ownerBootstrapCompleted,
    this.errorCode,
  });

  factory DeviceRoleState.unauthenticated({
    required String deviceId,
    String? hubUrl,
    String? errorCode,
  }) =>
      DeviceRoleState(
        verifiedRole: roleCashier,
        status: DeviceRoleVerificationStatus.unauthenticated,
        boundDeviceId: deviceId,
        boundHubUrl: hubUrl,
        errorCode: errorCode,
      );

  /// Belirtilen UTC zamanında geçerli efektif rolü döner (`OWNER` veya `CASHIER`).
  ///
  /// Süre aşımı, token uyuşmazlığı, yetkilendirme hatası veya önbellek TTL
  /// dolumunda daima fail-closed `'CASHIER'` döndürür.
  String effectiveRoleAt(
    DateTime nowUtc, {
    Duration ttl = defaultCacheTtl,
  }) {
    if (status != DeviceRoleVerificationStatus.verified) {
      return roleCashier;
    }
    if (verifiedRole.toUpperCase() != roleOwner) {
      return roleCashier;
    }
    if (boundToken == null || boundToken!.isEmpty) {
      return roleCashier;
    }
    if (verifiedAtUtc == null ||
        nowUtc.isBefore(verifiedAtUtc!) ||
        nowUtc.difference(verifiedAtUtc!) > ttl) {
      return roleCashier;
    }
    if (expiresAtUtc != null && !nowUtc.isBefore(expiresAtUtc!)) {
      return roleCashier;
    }
    return roleOwner;
  }

  DeviceRoleState copyWith({
    String? verifiedRole,
    DeviceRoleVerificationStatus? status,
    String? boundDeviceId,
    String? boundHubUrl,
    String? boundToken,
    bool clearBoundToken = false,
    DateTime? verifiedAtUtc,
    bool clearVerifiedAt = false,
    DateTime? expiresAtUtc,
    bool clearExpiresAt = false,
    bool? ownerBootstrapCompleted,
    String? errorCode,
    bool clearErrorCode = false,
  }) {
    return DeviceRoleState(
      verifiedRole: verifiedRole ?? this.verifiedRole,
      status: status ?? this.status,
      boundDeviceId: boundDeviceId ?? this.boundDeviceId,
      boundHubUrl: boundHubUrl ?? this.boundHubUrl,
      boundToken: clearBoundToken ? null : (boundToken ?? this.boundToken),
      verifiedAtUtc:
          clearVerifiedAt ? null : (verifiedAtUtc ?? this.verifiedAtUtc),
      expiresAtUtc: clearExpiresAt ? null : (expiresAtUtc ?? this.expiresAtUtc),
      ownerBootstrapCompleted:
          ownerBootstrapCompleted ?? this.ownerBootstrapCompleted,
      errorCode: clearErrorCode ? null : (errorCode ?? this.errorCode),
    );
  }
}

/// Master Hub `GET /api/v1/devices/me` üzerinden Windows ve Android cihaz rolünü
/// fail-closed doğrulayan Riverpod `StateNotifier`.
class DeviceRoleNotifier extends StateNotifier<DeviceRoleState> {
  final http.Client httpClient;
  final RedactingLogger logger;
  final String? Function() readHubUrl;
  final String? Function() readDeviceToken;
  final String deviceId;
  final String tenantId;
  final String storeId;
  final bool hasStorageError;
  final DateTime Function() clock;
  final Duration cacheTtl;
  final Duration requestTimeout;

  Future<String>? _inFlightRefresh;

  DeviceRoleNotifier({
    required this.httpClient,
    required this.logger,
    required this.readHubUrl,
    required this.readDeviceToken,
    required this.deviceId,
    required this.tenantId,
    required this.storeId,
    this.hasStorageError = false,
    DateTime Function()? clock,
    this.cacheTtl = DeviceRoleState.defaultCacheTtl,
    this.requestTimeout = const Duration(seconds: 6),
  })  : clock = clock ?? (() => DateTime.now().toUtc()),
        super(
          DeviceRoleState.unauthenticated(
            deviceId: deviceId,
            hubUrl: readHubUrl(),
            errorCode: hasStorageError ? 'ERR_SECURE_STORAGE' : null,
          ),
        ) {
    final initialToken = (readDeviceToken() ?? '').trim();
    final initialHub = (readHubUrl() ?? '').trim();
    if (!hasStorageError &&
        initialToken.isNotEmpty &&
        initialHub.isNotEmpty &&
        deviceId.trim().isNotEmpty) {
      Future<void>.microtask(() {
        if (mounted) {
          unawaited(refreshRole(force: false));
        }
      });
    }
  }

  /// Hub oturumu 401/403 döndürdüğünde veya token iptal edildiğinde eski `OWNER`
  /// yetkisini anında temizler (fail-closed).
  void invalidateFromAuthError({String? code}) {
    if (!mounted) return;
    state = DeviceRoleState(
      verifiedRole: DeviceRoleState.roleCashier,
      status: DeviceRoleVerificationStatus.unauthorized,
      boundDeviceId: deviceId,
      boundHubUrl: readHubUrl(),
      errorCode: code ?? 'ERR_AUTH_INVALIDATED',
    );
  }

  /// Cihazın gerçek rolünü Master Hub üzerinden doğrular (`GET /api/v1/devices/me`).
  ///
  /// Bağlantı yok, token geçersiz, süresi dolmuş veya Hub reddetmişse fail-closed
  /// `'CASHIER'` döner ve eski `'OWNER'` önbelleğini temizler.
  Future<String> refreshRole({bool force = false}) async {
    if (!mounted) return DeviceRoleState.roleCashier;

    if (_inFlightRefresh != null) {
      final first = await _inFlightRefresh!;
      if (!force || !mounted) return first;
    }

    final future = _doRefreshRole(force: force);
    _inFlightRefresh = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightRefresh, future)) {
        _inFlightRefresh = null;
      }
    }
  }

  Future<String> _doRefreshRole({required bool force}) async {
    final hubBase = (readHubUrl() ?? '').trim().replaceAll(RegExp(r'/+$'), '');
    final token = (readDeviceToken() ?? '').trim();
    final cleanDeviceId = deviceId.trim();

    if (hasStorageError ||
        cleanDeviceId.isEmpty ||
        hubBase.isEmpty ||
        token.isEmpty) {
      if (mounted) {
        state = DeviceRoleState.unauthenticated(
          deviceId: deviceId,
          hubUrl: hubBase.isEmpty ? null : hubBase,
          errorCode: hasStorageError
              ? 'ERR_SECURE_STORAGE'
              : (token.isEmpty ? 'ERR_TOKEN_MISSING' : 'ERR_HUB_UNCONFIGURED'),
        );
      }
      return DeviceRoleState.roleCashier;
    }

    final now = clock().toUtc();
    if (!force &&
        state.status == DeviceRoleVerificationStatus.verified &&
        state.boundDeviceId == cleanDeviceId &&
        state.boundHubUrl == hubBase &&
        state.boundToken == token &&
        state.effectiveRoleAt(now, ttl: cacheTtl) == state.verifiedRole) {
      return state.effectiveRoleAt(now, ttl: cacheTtl);
    }

    if (mounted) {
      state = state.copyWith(
        status: DeviceRoleVerificationStatus.verifying,
        clearErrorCode: true,
      );
    }

    try {
      final resp = await httpClient
          .get(
            Uri.parse('$hubBase/api/v1/devices/me'),
            headers: {
              'authorization': 'Bearer $token',
              if (tenantId.trim().isNotEmpty) 'x-mms-tenant-id': tenantId.trim(),
              if (storeId.trim().isNotEmpty) 'x-mms-store-id': storeId.trim(),
            },
          )
          .timeout(requestTimeout);

      if (!mounted) return DeviceRoleState.roleCashier;

      Map<String, dynamic> decoded = const {};
      if (resp.body.trim().isNotEmpty) {
        try {
          final parsed = jsonDecode(resp.body);
          if (parsed is Map) {
            decoded = Map<String, dynamic>.from(parsed);
          } else {
            logger.warning(
              'rbac',
              'Hub rol yanıtı JSON nesnesi değil (${parsed.runtimeType}).',
            );
          }
        } catch (e) {
          logger.warning(
            'rbac',
            'Hub rol yanıtı JSON ayrıştırılamadı: ${e.runtimeType}',
          );
        }
      }

      if (resp.statusCode == 200) {
        final returnedId = (decoded['device_id'] as String?)?.trim();
        if (returnedId != null &&
            returnedId.isNotEmpty &&
            returnedId != cleanDeviceId) {
          logger.warning(
            'rbac',
            'Hub rol yanıtındaki device_id uyuşmuyor ($returnedId != $cleanDeviceId).',
          );
          invalidateFromAuthError(code: 'ERR_DEVICE_ID_MISMATCH');
          return DeviceRoleState.roleCashier;
        }

        final isActive = (decoded['is_active'] as bool?) ?? true;
        final isConfirmed = (decoded['is_confirmed'] as bool?) ?? true;
        if (!isActive || !isConfirmed) {
          invalidateFromAuthError(
            code: !isActive ? 'DEVICE_REVOKED' : 'ERR_DEVICE_NOT_CONFIRMED',
          );
          return DeviceRoleState.roleCashier;
        }

        final expiresRaw = decoded['expires_at'];
        final expiresAtUtc = expiresRaw is String
            ? DateTime.tryParse(expiresRaw)?.toUtc()
            : null;
        final checkedAt = clock().toUtc();
        if (expiresAtUtc != null && !checkedAt.isBefore(expiresAtUtc)) {
          invalidateFromAuthError(code: 'TOKEN_EXPIRED');
          return DeviceRoleState.roleCashier;
        }

        final rawRole = (decoded['role'] as String?)?.trim().toUpperCase();
        final resolvedRole = rawRole == DeviceRoleState.roleOwner
            ? DeviceRoleState.roleOwner
            : DeviceRoleState.roleCashier;

        state = DeviceRoleState(
          verifiedRole: resolvedRole,
          status: DeviceRoleVerificationStatus.verified,
          boundDeviceId: cleanDeviceId,
          boundHubUrl: hubBase,
          boundToken: token,
          verifiedAtUtc: checkedAt,
          expiresAtUtc: expiresAtUtc,
          ownerBootstrapCompleted:
              decoded['owner_bootstrap_completed'] as bool?,
        );
        return resolvedRole;
      }

      final errorCode = (decoded['code'] as String?) ??
          (decoded['error'] as String?) ??
          'HTTP_${resp.statusCode}';

      if (resp.statusCode == 401 || resp.statusCode == 403) {
        invalidateFromAuthError(code: errorCode);
        return DeviceRoleState.roleCashier;
      }

      logger.warning(
        'rbac',
        'Hub rol doğrulaması başarısız oldu (HTTP ${resp.statusCode}, $errorCode); fail-closed CASHIER uygulandı.',
      );
      state = DeviceRoleState(
        verifiedRole: DeviceRoleState.roleCashier,
        status: DeviceRoleVerificationStatus.unreachable,
        boundDeviceId: cleanDeviceId,
        boundHubUrl: hubBase,
        errorCode: errorCode,
      );
      return DeviceRoleState.roleCashier;
    } catch (e) {
      if (!mounted) return DeviceRoleState.roleCashier;
      logger.warning(
        'rbac',
        'Hub rol doğrulaması erişilemedi (${e.runtimeType}); fail-closed CASHIER uygulandı.',
      );
      state = DeviceRoleState(
        verifiedRole: DeviceRoleState.roleCashier,
        status: DeviceRoleVerificationStatus.unreachable,
        boundDeviceId: cleanDeviceId,
        boundHubUrl: hubBase,
        errorCode: e.runtimeType.toString(),
      );
      return DeviceRoleState.roleCashier;
    }
  }
}
