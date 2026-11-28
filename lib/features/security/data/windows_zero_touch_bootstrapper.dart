import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mms_client_storage/mms_client_storage.dart'
    show TlsCertificateValidationException, TlsPinMismatchException;

import '../../../core/logging/redacting_logger.dart';
import '../../../core/security/security_providers.dart';
import '../../../core/security/secure_token_store.dart';
import '../../../core/security/tls_pinned_client_factory.dart';
import '../../diagnostics/application/system_status_notifier.dart';
import '../../diagnostics/domain/system_status.dart';
import '../../setup/domain/app_setup_config.dart';
import '../../setup/setup_providers.dart';
import '../../sync/application/hub_connection_notifier.dart';
import '../../sync/domain/sync_coordinator_state.dart';
import '../../sync/sync_providers.dart';
import 'device_pairing_client.dart';

enum WindowsZeroTouchStatus {
  skippedNotEligible,
  alreadyConfigured,
  bootstrapped,
  caPinnedOwnerAlreadyExists,
  hubUnreachable,
  failed,
}

class WindowsZeroTouchResult {
  final WindowsZeroTouchStatus status;
  final bool caPinnedNow;
  final String? deviceId;
  final String? message;

  const WindowsZeroTouchResult({
    required this.status,
    this.caPinnedNow = false,
    this.deviceId,
    this.message,
  });

  bool get isReady =>
      status == WindowsZeroTouchStatus.alreadyConfigured ||
      status == WindowsZeroTouchStatus.bootstrapped;
}

/// Windows Ana Bilgisayar Zero-Touch Otomatik Kurulum ve Bağlantı Servisi.
///
/// YALNIZCA `Platform.isWindows` iken ve hedef Hub adresi `https://127.0.0.1:<port>`
/// veya `https://localhost:<port>` iken çalışır. Android veya uzak LAN IP
/// adreslerinde ASLA çalışmaz (fail-closed).
class WindowsZeroTouchBootstrapper {
  final DevicePairingClient pairingClient;
  final SecureTokenStore tokenStore;
  final RedactingLogger logger;
  final http.Client Function(PinnedTlsConfig config) pinnedClientFactory;
  final bool Function() isWindowsPlatform;
  final Duration requestTimeout;

  Future<WindowsZeroTouchResult>? _inFlight;

  WindowsZeroTouchBootstrapper({
    required this.pairingClient,
    required this.tokenStore,
    required this.logger,
    http.Client Function(PinnedTlsConfig config)? pinnedClientFactory,
    bool Function()? isWindowsPlatform,
    this.requestTimeout = const Duration(seconds: 5),
  })  : pinnedClientFactory =
            pinnedClientFactory ?? MmsPinnedTlsClientFactory.createClient,
        isWindowsPlatform = isWindowsPlatform ?? (() => Platform.isWindows);

  /// Yalnızca Windows + `https://127.0.0.1` / `https://localhost` hedeflerinde `true` döner.
  static bool isEligibleLoopbackHubUrl(
    String? rawUrl, {
    bool? isWindowsOverride,
  }) {
    final isWin = isWindowsOverride ?? Platform.isWindows;
    if (!isWin || rawUrl == null || rawUrl.trim().isEmpty) return false;
    final parsed = Uri.tryParse(rawUrl.trim());
    if (parsed == null) return false;
    if (parsed.scheme.toLowerCase() != 'https') return false;
    final host = parsed.host.toLowerCase();
    return host == '127.0.0.1' || host == 'localhost';
  }

  /// Adım A (Loopback TOFU CA sabitleme) + Adım B (`/api/v1/local/auto-bootstrap`).
  ///
  /// Hub kapalıysa/erişilemiyorsa uygulamayı bloklamadan sessizce döner.
  /// `409 ERR_OWNER_ALREADY_BOOTSTRAPPED` durumunda hata patlatmadan sessizce geçer.
  Future<WindowsZeroTouchResult> run({
    required String? hubBaseUrl,
    required AppSetupConfig setupConfig,
    required Future<AppSetupConfig> Function(String sha256Hex, String caCertPem)
        onSavePinnedCa,
    required Future<void> Function(String deviceId, String token)
        onSaveDeviceToken,
    Future<void> Function()? onRefreshAfterBootstrap,
  }) {
    if (_inFlight != null) {
      return _inFlight!;
    }
    final future = _execute(
      hubBaseUrl: hubBaseUrl,
      setupConfig: setupConfig,
      onSavePinnedCa: onSavePinnedCa,
      onSaveDeviceToken: onSaveDeviceToken,
      onRefreshAfterBootstrap: onRefreshAfterBootstrap,
    );
    _inFlight = future;
    future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    });
    return future;
  }

  Future<WindowsZeroTouchResult> _execute({
    required String? hubBaseUrl,
    required AppSetupConfig setupConfig,
    required Future<AppSetupConfig> Function(String sha256Hex, String caCertPem)
        onSavePinnedCa,
    required Future<void> Function(String deviceId, String token)
        onSaveDeviceToken,
    Future<void> Function()? onRefreshAfterBootstrap,
  }) async {
    final isWin = isWindowsPlatform();
    if (!isEligibleLoopbackHubUrl(hubBaseUrl, isWindowsOverride: isWin)) {
      return const WindowsZeroTouchResult(
        status: WindowsZeroTouchStatus.skippedNotEligible,
      );
    }

    final cleanBaseUrl = hubBaseUrl!.trim().replaceAll(RegExp(r'/+$'), '');
    var currentConfig = setupConfig;
    var caPinnedNow = false;

    // Adım A: Henüz pinnedCaPem / tlsPinSha256 yoksa loopback TOFU ile Kök CA'yı sabitle
    final hasPinnedCa = currentConfig.hasPinnedCertificate &&
        (currentConfig.pinnedCaPem?.trim().isNotEmpty ?? false);
    if (!hasPinnedCa) {
      try {
        final canonical = await pairingClient.fetchLoopbackRootCaTofu(
          hubBaseUrl: cleanBaseUrl,
          requestTimeout: requestTimeout,
          isWindowsOverride: isWin,
        );
        currentConfig = await onSavePinnedCa(
          canonical.sha256Hex,
          canonical.toPem(),
        );
        caPinnedNow = true;
        logger.info(
          'zero_touch',
          'Windows yerel Hub Kök CA sertifikası otomatik sabitlendi.',
        );
      } on DevicePairingException catch (e) {
        if (e.code == 'BOOTSTRAP_TIMEOUT' ||
            e.code == 'BOOTSTRAP_FETCH_FAILED' ||
            e.code == 'TLS_VERIFICATION_FAILED' ||
            e.code == 'HUB_HEALTH_FAILED') {
          logger.warning(
            'zero_touch',
            'Yerel Hub henüz erişilemiyor; otomatik CA sabitlemesi ertelendi (${e.code}).',
          );
          return WindowsZeroTouchResult(
            status: WindowsZeroTouchStatus.hubUnreachable,
            message: 'Yerel Master Hub erişilebilir değil.',
          );
        }
        logger.warning(
          'zero_touch',
          'Otomatik CA sabitlemesi reddedildi (${e.code}).',
        );
        return WindowsZeroTouchResult(
          status: WindowsZeroTouchStatus.failed,
          message: e.message,
        );
      } on SocketException {
        return const WindowsZeroTouchResult(
          status: WindowsZeroTouchStatus.hubUnreachable,
          message: 'Yerel Master Hub erişilebilir değil.',
        );
      } on TimeoutException {
        return const WindowsZeroTouchResult(
          status: WindowsZeroTouchStatus.hubUnreachable,
          message: 'Yerel Master Hub yanıt vermedi.',
        );
      } on http.ClientException {
        return const WindowsZeroTouchResult(
          status: WindowsZeroTouchStatus.hubUnreachable,
          message: 'Yerel Master Hub bağlantısı kurulamadı.',
        );
      } catch (e) {
        logger.warning(
          'zero_touch',
          'Otomatik CA sabitlemesi sırasında beklenmeyen hata: ${e.runtimeType}',
        );
        return const WindowsZeroTouchResult(
          status: WindowsZeroTouchStatus.failed,
          message: 'Yerel Hub sertifika sabitlemesi tamamlanamadı.',
        );
      }
    }

    final normalizedPin = currentConfig.normalizedPinSha256;
    final caPem = currentConfig.pinnedCaPem;
    if (normalizedPin == null ||
        normalizedPin.isEmpty ||
        caPem == null ||
        caPem.trim().isEmpty) {
      return const WindowsZeroTouchResult(
        status: WindowsZeroTouchStatus.failed,
        message: 'Sabitlenmiş Kök CA yapılandırması eksik.',
      );
    }

    // Adım B: SecureTokenStore (Windows DPAPI) içinde cihaz token'ı yoksa auto-bootstrap çağır
    String? existingToken;
    try {
      existingToken = await tokenStore.readDeviceToken(currentConfig.deviceId);
    } catch (e) {
      logger.warning(
        'zero_touch',
        'Güvenli token deposu okunamadı: ${e.runtimeType}',
      );
      return const WindowsZeroTouchResult(
        status: WindowsZeroTouchStatus.failed,
        message: 'Güvenli cihaz anahtarı deposu okunamadı.',
      );
    }

    if (existingToken != null && existingToken.trim().isNotEmpty) {
      logger.registerSensitiveValue(existingToken);
      if (caPinnedNow && onRefreshAfterBootstrap != null) {
        await onRefreshAfterBootstrap();
      }
      return WindowsZeroTouchResult(
        status: WindowsZeroTouchStatus.alreadyConfigured,
        caPinnedNow: caPinnedNow,
        deviceId: currentConfig.deviceId,
      );
    }

    final pinnedConfig = PinnedTlsConfig(
      caCertPem: caPem,
      expectedSha256Hex: normalizedPin,
    );
    final client = pinnedClientFactory(pinnedConfig);
    try {
      final deviceName = currentConfig.deviceName.trim().isNotEmpty
          ? currentConfig.deviceName.trim()
          : 'Windows Ana Bilgisayar';
      final resp = await client
          .post(
            Uri.parse('$cleanBaseUrl/api/v1/local/auto-bootstrap'),
            headers: const <String, String>{
              'content-type': 'application/json',
              'accept': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'device_id': currentConfig.deviceId,
              'name': deviceName,
            }),
          )
          .timeout(requestTimeout);

      Map<String, dynamic> decoded = const {};
      if (resp.body.trim().isNotEmpty) {
        try {
          final parsed = jsonDecode(resp.body);
          if (parsed is Map) {
            decoded = Map<String, dynamic>.from(parsed);
          }
        } catch (_) {
          decoded = const {};
        }
      }

      if (resp.statusCode == 200) {
        final issuedToken = (decoded['device_token'] as String?)?.trim() ?? '';
        final resolvedId =
            ((decoded['device_id'] as String?)?.trim().isNotEmpty ?? false)
                ? (decoded['device_id'] as String).trim()
                : currentConfig.deviceId;
        if (issuedToken.isEmpty) {
          return WindowsZeroTouchResult(
            status: WindowsZeroTouchStatus.failed,
            caPinnedNow: caPinnedNow,
            message: 'Hub otomatik kurulum yanıtında cihaz token bulunamadı.',
          );
        }
        logger.registerSensitiveValue(issuedToken);
        await onSaveDeviceToken(resolvedId, issuedToken);
        logger.info(
          'zero_touch',
          'Windows ana bilgisayar otomatik OWNER bağlantısı tamamlandı.',
        );
        if (onRefreshAfterBootstrap != null) {
          await onRefreshAfterBootstrap();
        }
        return WindowsZeroTouchResult(
          status: WindowsZeroTouchStatus.bootstrapped,
          caPinnedNow: caPinnedNow,
          deviceId: resolvedId,
          message: 'Ana bilgisayar bağlantısı otomatik olarak tamamlandı.',
        );
      }

      final errCode = (decoded['code'] as String?) ??
          (decoded['error'] as String?) ??
          'HTTP_${resp.statusCode}';
      if (resp.statusCode == 409 &&
          errCode == 'ERR_OWNER_ALREADY_BOOTSTRAPPED') {
        logger.info(
          'zero_touch',
          'Hub daha önce mühürlenmiş; otomatik kurulum sessizce atlandı.',
        );
        if (caPinnedNow && onRefreshAfterBootstrap != null) {
          await onRefreshAfterBootstrap();
        }
        return WindowsZeroTouchResult(
          status: WindowsZeroTouchStatus.caPinnedOwnerAlreadyExists,
          caPinnedNow: caPinnedNow,
          deviceId: currentConfig.deviceId,
          message:
              'Hub ilk kurulumu daha önce başka bir yönetici tarafından mühürlenmiş.',
        );
      }

      logger.warning(
        'zero_touch',
        'Otomatik OWNER kurulumu reddedildi (HTTP ${resp.statusCode}, $errCode).',
      );
      return WindowsZeroTouchResult(
        status: WindowsZeroTouchStatus.failed,
        caPinnedNow: caPinnedNow,
        message: (decoded['message'] as String?) ??
            'Otomatik ana bilgisayar bağlantısı başarısız (HTTP ${resp.statusCode}).',
      );
    } on SocketException {
      return WindowsZeroTouchResult(
        status: WindowsZeroTouchStatus.hubUnreachable,
        caPinnedNow: caPinnedNow,
        message: 'Yerel Master Hub erişilebilir değil.',
      );
    } on TimeoutException {
      return WindowsZeroTouchResult(
        status: WindowsZeroTouchStatus.hubUnreachable,
        caPinnedNow: caPinnedNow,
        message: 'Yerel Master Hub yanıt vermedi.',
      );
    } on http.ClientException {
      return WindowsZeroTouchResult(
        status: WindowsZeroTouchStatus.hubUnreachable,
        caPinnedNow: caPinnedNow,
        message: 'Yerel Master Hub bağlantısı kurulamadı.',
      );
    } on TlsPinMismatchException catch (e) {
      return WindowsZeroTouchResult(
        status: WindowsZeroTouchStatus.failed,
        caPinnedNow: caPinnedNow,
        message: e.message,
      );
    } on TlsCertificateValidationException catch (e) {
      return WindowsZeroTouchResult(
        status: WindowsZeroTouchStatus.failed,
        caPinnedNow: caPinnedNow,
        message: e.message,
      );
    } finally {
      client.close();
    }
  }
}

/// Üretim başlatıcısında (`main.dart`) `Platform.isWindows` ile açılır;
/// izole widget testlerinde varsayılan `false` kalır.
final windowsZeroTouchAutoBootstrapEnabledProvider =
    Provider<bool>((ref) => false);

final windowsZeroTouchBootstrapperProvider =
    Provider<WindowsZeroTouchBootstrapper>((ref) {
  final tokenStore = ref.watch(secureTokenStoreProvider);
  final logger = ref.watch(redactingLoggerProvider);
  final pairingClient = DevicePairingClient(
    tokenStore: tokenStore,
    logger: logger,
  );
  return WindowsZeroTouchBootstrapper(
    pairingClient: pairingClient,
    tokenStore: tokenStore,
    logger: logger,
  );
});

final windowsZeroTouchRunnerProvider =
    Provider<Future<WindowsZeroTouchResult> Function()>((ref) {
  return () async {
    final bootstrapper = ref.read(windowsZeroTouchBootstrapperProvider);
    final hubUrl = ref.read(hubConnectionProvider).activeHubUrl;
    final setup = ref.read(setupConfigProvider);
    return bootstrapper.run(
      hubBaseUrl: hubUrl,
      setupConfig: setup,
      onSavePinnedCa: (sha256Hex, caCertPem) {
        return ref.read(setupConfigProvider.notifier).updateTlsPinning(
              enabled: true,
              sha256Hex: sha256Hex,
              caCertPem: caCertPem,
            );
      },
      onSaveDeviceToken: (deviceId, token) {
        return ref
            .read(deviceAuthProvider.notifier)
            .setStoredToken(deviceId, token);
      },
      onRefreshAfterBootstrap: () async {
        await ref.read(deviceRoleProvider.notifier).refreshRole(force: true);
        unawaited(ref.read(systemStatusProvider.notifier).refreshStatus());
        unawaited(
          ref
              .read(backgroundSyncCoordinatorProvider.notifier)
              .triggerSync(reason: SyncTriggerReason.connectivityRestored),
        );
      },
    );
  };
});

final windowsZeroTouchStartupProvider = Provider<void>((ref) {
  final enabled = ref.watch(windowsZeroTouchAutoBootstrapEnabledProvider);
  if (!enabled) return;

  ref.listen<SystemStatus>(systemStatusProvider, (previous, next) {
    final wasOnline = previous?.backendState == BackendConnectionState.online;
    final isNowOnline = next.backendState == BackendConnectionState.online;
    if (!wasOnline && isNowOnline) {
      final setup = ref.read(setupConfigProvider);
      final auth = ref.read(deviceAuthProvider);
      if (!setup.hasPinnedCertificate || !auth.hasStoredToken) {
        unawaited(ref.read(windowsZeroTouchRunnerProvider)());
      }
    }
  });

  unawaited(Future<void>.microtask(() async {
    await ref.read(windowsZeroTouchRunnerProvider)();
  }));
});
