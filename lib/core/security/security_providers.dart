import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../features/setup/setup_providers.dart';
import '../../features/sync/application/hub_connection_notifier.dart';
import '../constants/app_constants.dart';
import '../logging/redacting_logger.dart';
import 'device_role_resolver.dart';
import 'secure_token_store.dart';
import 'tls_pinned_client_factory.dart';

/// B-3 Güvenli token saklama sağlayıcısı.
///
/// Üretim başlatıcısında Windows için [WindowsDpapiTokenStore], Android için
/// [AndroidKeystoreTokenStore] ile override edilir.
final secureTokenStoreProvider = Provider<SecureTokenStore>((ref) {
  return InMemorySecureTokenStore();
});

/// Başlangıçta OS güvenli deposundan okunan cihaz token'ı (varsa).
final initialStoredDeviceTokenProvider = Provider<String?>((ref) => null);

/// Maskeli çalışma zamanı loglayıcısı.
final redactingLoggerProvider = Provider<RedactingLogger>((ref) {
  return RedactingLogger();
});

class DeviceAuthState {
  final String deviceId;
  final String? storedToken;
  final String backendLabel;
  final bool isLoaded;

  /// Güvenli depo okunamadıysa kullanıcıya gösterilecek maskeli hata (fail-closed).
  final String? storageError;

  const DeviceAuthState({
    required this.deviceId,
    this.storedToken,
    required this.backendLabel,
    this.isLoaded = false,
    this.storageError,
  });

  bool get hasStoredToken => storedToken != null && storedToken!.isNotEmpty;

  String? get effectiveToken {
    if (hasStoredToken) return storedToken;
    return AppConstants.defaultDeviceToken.isNotEmpty
        ? AppConstants.defaultDeviceToken
        : null;
  }

  DeviceAuthState copyWith({
    String? deviceId,
    String? storedToken,
    bool clearStoredToken = false,
    String? backendLabel,
    bool? isLoaded,
    String? storageError,
    bool clearStorageError = false,
  }) {
    return DeviceAuthState(
      deviceId: deviceId ?? this.deviceId,
      storedToken: clearStoredToken ? null : (storedToken ?? this.storedToken),
      backendLabel: backendLabel ?? this.backendLabel,
      isLoaded: isLoaded ?? this.isLoaded,
      storageError: clearStorageError ? null : (storageError ?? this.storageError),
    );
  }
}

class DeviceAuthNotifier extends StateNotifier<DeviceAuthState> {
  final SecureTokenStore store;
  final RedactingLogger logger;

  DeviceAuthNotifier({
    required this.store,
    required this.logger,
    required String deviceId,
    String? initialStoredToken,
  }) : super(
          DeviceAuthState(
            deviceId: deviceId,
            storedToken: initialStoredToken,
            backendLabel: store.backendLabel,
            isLoaded: initialStoredToken != null,
          ),
        ) {
    if (initialStoredToken != null && initialStoredToken.isNotEmpty) {
      logger.registerSensitiveValue(initialStoredToken);
    }
    Future<void>.microtask(() => loadForDevice(deviceId));
  }

  Future<void> loadForDevice(String deviceId) async {
    final String? token;
    try {
      token = await store.readDeviceToken(deviceId);
    } catch (e) {
      // Fail-closed: depo okunamazsa hiçbir token (varsayılan dahil) kullanılmaz;
      // senkronizasyon durur, kayıtlar Outbox'ta korunur, kullanıcı yeniden eşleştirme yapar.
      logger.error('secure_storage', 'Cihaz token deposu okunamadı: $e');
      if (!mounted) return;
      state = state.copyWith(
        deviceId: deviceId,
        clearStoredToken: true,
        backendLabel: store.backendLabel,
        isLoaded: true,
        storageError:
            'Güvenli cihaz anahtarı okunamadı. Senkronizasyon durduruldu; cihazı yeniden eşleştirin.',
      );
      return;
    }
    if (token != null && token.isNotEmpty) {
      logger.registerSensitiveValue(token);
    }
    if (!mounted) return;
    state = state.copyWith(
      deviceId: deviceId,
      storedToken: token,
      clearStoredToken: token == null || token.isEmpty,
      backendLabel: store.backendLabel,
      isLoaded: true,
      clearStorageError: true,
    );
  }

  Future<void> setStoredToken(String deviceId, String token) async {
    logger.registerSensitiveValue(token);
    await store.saveDeviceToken(deviceId, token);
    if (!mounted) return;
    state = state.copyWith(
      deviceId: deviceId,
      storedToken: token,
      backendLabel: store.backendLabel,
      isLoaded: true,
    );
  }

  Future<void> clearStoredToken() async {
    await store.deleteDeviceToken(state.deviceId);
    if (!mounted) return;
    state = state.copyWith(
      clearStoredToken: true,
      isLoaded: true,
    );
  }
}

final deviceAuthProvider =
    StateNotifierProvider<DeviceAuthNotifier, DeviceAuthState>((ref) {
  final store = ref.watch(secureTokenStoreProvider);
  final logger = ref.watch(redactingLoggerProvider);
  final setup = ref.watch(setupConfigProvider);
  final initialSetup = ref.watch(initialSetupConfigProvider);
  final initialToken = ref.watch(initialStoredDeviceTokenProvider);
  final canUseInitialToken = initialSetup == null
      ? setup.deviceId == AppConstants.defaultDeviceId
      : setup.deviceId == initialSetup.deviceId;
  return DeviceAuthNotifier(
    store: store,
    logger: logger,
    deviceId: setup.deviceId,
    initialStoredToken: canUseInitialToken ? initialToken : null,
  );
});

/// API istemcisi ve SyncCoordinator için aktif cihaz token'ını döner.
final effectiveDeviceTokenProvider = Provider<String?>((ref) {
  return ref.watch(deviceAuthProvider).effectiveToken;
});

/// Rol ve yedekleme yönetimi için TLS sertifika sabitlemeli Hub HTTP istemcisi.
final deviceRoleHttpClientProvider = Provider<http.Client>((ref) {
  final pinnedTls = ref.watch(pinnedTlsConfigProvider);
  final client = pinnedTls != null
      ? MmsPinnedTlsClientFactory.createClient(pinnedTls)
      : http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Rol önbellek süresi ve token son kullanma denetimi için UTC saat sağlayıcısı.
final deviceRoleClockProvider = Provider<DateTime Function()>((ref) {
  return () => DateTime.now().toUtc();
});

/// Hub `/api/v1/devices/me` üzerinden fail-closed cihaz rolü doğrulama sağlayıcısı.
final deviceRoleProvider =
    StateNotifierProvider<DeviceRoleNotifier, DeviceRoleState>((ref) {
  final auth = ref.watch(deviceAuthProvider);
  final setup = ref.watch(setupConfigProvider);
  final activeHubUrl =
      ref.watch(hubConnectionProvider.select((s) => s.activeHubUrl));
  final httpClient = ref.watch(deviceRoleHttpClientProvider);
  final logger = ref.watch(redactingLoggerProvider);
  final clock = ref.watch(deviceRoleClockProvider);

  return DeviceRoleNotifier(
    httpClient: httpClient,
    logger: logger,
    readHubUrl: () => activeHubUrl,
    readDeviceToken: () => auth.effectiveToken,
    deviceId: setup.deviceId,
    tenantId: setup.tenantId,
    storeId: setup.storeId,
    hasStorageError: auth.storageError != null,
    clock: clock,
  );
});

/// Doğrulanmış efektif cihaz rolü (`OWNER` veya fail-closed `CASHIER`).
final effectiveDeviceRoleProvider = Provider<String>((ref) {
  final roleState = ref.watch(deviceRoleProvider);
  final clock = ref.watch(deviceRoleClockProvider);
  return roleState.effectiveRoleAt(clock());
});
