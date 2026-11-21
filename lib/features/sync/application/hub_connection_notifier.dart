import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_response.dart';
import '../../diagnostics/application/system_status_notifier.dart';
import '../../setup/setup_providers.dart';
import '../domain/hub_connection_state.dart';
import '../domain/hub_discovery_client.dart';
import '../infrastructure/udp_hub_discovery_client.dart';

/// Uygulama başlangıcında SQLite (`local_client_settings`) ve platform politikasına göre
/// kalıcı Hub bağlantı durumunu çözen başlatıcı (bootstrapper).
class HubConnectionBootstrapper {
  const HubConnectionBootstrapper._();

  /// Platform güvenlik politikası: Android'de loopback (`127.0.0.1` / `localhost`) yasaktır;
  /// Windows ve masaüstü platformlarda izin verilir.
  static bool defaultAllowLoopbackForPlatform({bool? allowLoopback}) {
    if (allowLoopback != null) return allowLoopback;
    return !Platform.isAndroid;
  }

  /// Uygulama başlangıcında ağ I/O beklemeksizin yerel kalıcı ayardan ve platform
  /// varsayılanlarından ilk [HubConnectionState] nesnesini hazırlar.
  static Future<HubConnectionState> loadInitialState({
    required ClientStorageRepository repository,
    bool? allowLoopback,
    String? configuredHubUrl,
    String? desktopFallbackUrl,
  }) async {
    final effectiveAllowLoopback =
        defaultAllowLoopbackForPlatform(allowLoopback: allowLoopback);

    final stored = await repository.getStoredHubConnection(
      allowLoopback: effectiveAllowLoopback,
    );
    if (stored != null) {
      return HubConnectionState(
        phase: HubConnectionPhase.verifying,
        activeHubUrl: stored.hubUrl,
        hubId: stored.hubId,
        source: stored.source,
        lastVerifiedAt: stored.lastVerifiedAt,
        isInitialized: true,
      );
    }

    final normalizedConfigured = HubUrlValidator.tryNormalize(
      configuredHubUrl ?? AppConstants.configuredBackendBaseUrl,
      allowLoopback: effectiveAllowLoopback,
    );
    if (normalizedConfigured != null) {
      return HubConnectionState(
        phase: HubConnectionPhase.verifying,
        activeHubUrl: normalizedConfigured,
        source: HubUrlSource.configured,
        isInitialized: true,
      );
    }

    if (effectiveAllowLoopback) {
      final normalizedFallback = HubUrlValidator.tryNormalize(
        desktopFallbackUrl ?? AppConstants.windowsLocalhostFallbackUrl,
        allowLoopback: true,
      );
      if (normalizedFallback != null) {
        return HubConnectionState(
          phase: HubConnectionPhase.verifying,
          activeHubUrl: normalizedFallback,
          source: HubUrlSource.localhostFallback,
          isInitialized: true,
        );
      }
    }

    // Android'de kayıtlı veya açıkça yapılandırılmış geçerli LAN adresi yoksa
    // 127.0.0.1 fallback'i ASLA üretilmez.
    return const HubConnectionState(
      phase: HubConnectionPhase.unconfigured,
      activeHubUrl: null,
      isInitialized: true,
    );
  }
}

/// Uygulama genelinde platformun loopback Hub adresine (`127.0.0.1`) izin verip vermediğini bildirir.
final Provider<bool> hubAllowLoopbackPolicyProvider = Provider<bool>((ref) {
  return HubConnectionBootstrapper.defaultAllowLoopbackForPlatform();
});

/// Uygulama başlangıcında (`main.dart`) önceden çözümlenmiş Hub durumunu sağlayan override noktası.
final initialHubConnectionStateProvider = Provider<HubConnectionState?>((ref) {
  return null;
});

/// UDP 8946 yerel ağ Hub keşif istemcisi sağlayıcısı.
///
/// TLS-DISC (istemci tarafı, keşif protokolü DEĞİŞMEDEN): Keşif yanıtı şema
/// taşımaz. Cihaz eşleştirilmişse (CA pin'i var) Hub yalnızca TLS konuşur; adaylar
/// `https://` olarak denenir ve sağlık kontrolü sabitlenmiş istemciyle yapılır.
/// Pin yoksa (geliştirme Hub'ı) `http://` korunur. HTTP'ye geri düşüş yoktur.
final Provider<HubDiscoveryClient> hubDiscoveryClientProvider =
    Provider<HubDiscoveryClient>((ref) {
  // `watch` DEĞİL: pin değişince (eşleştirme) bağlantı yöneticisi yeniden kurulup
  // durumunu kaybetmesin; şema her keşif turunda güncel pin'e göre okunur.
  return UdpHubDiscoveryClient(
    schemeResolver: () => ref.read(pinnedTlsConfigProvider) != null ? 'https' : 'http',
  );
});

/// Otomatik başlangıç keşfi / periyodik / ön-plana dönüş reconnect yaşam döngüsü bayrağı.
///
/// Varsayılan olarak `false` tutulur (test izolasyonu için); [main.dart] içinde
/// Android üretim ortamında `true` olacak şekilde override edilir.
final Provider<bool> hubAutoDiscoveryLifecycleEnabledProvider =
    Provider<bool>((ref) => false);

/// Dinamik Hub URL çözümleme, doğrulama ve kalıcılık yöneticisi.
class HubConnectionNotifier extends StateNotifier<HubConnectionState> {
  final ClientStorageRepository repository;
  final Future<CentralHealthResponse> Function(String url) checkUrlHealth;
  final HubDiscoveryClient? discoveryClient;
  final String deviceId;
  final bool allowLoopback;
  final String? configuredHubUrl;
  final String? desktopFallbackUrl;
  final bool enableAutoLifecycle;
  final Duration reconnectInterval;
  final Duration reconnectCooldown;
  final DateTime Function() now;

  bool _isDisposed = false;
  int _operationEpoch = 0;
  Future<bool>? _activeDiscoveryFuture;
  Future<bool>? _activeReconnectFuture;
  DateTime? _lastAutoAttemptAt;
  Timer? _reconnectTimer;
  AppLifecycleListener? _lifecycleListener;

  HubConnectionNotifier({
    required this.repository,
    required this.checkUrlHealth,
    this.discoveryClient,
    this.deviceId = AppConstants.defaultDeviceId,
    HubConnectionState initialState = const HubConnectionState.initial(),
    bool? allowLoopback,
    this.configuredHubUrl,
    this.desktopFallbackUrl,
    this.enableAutoLifecycle = false,
    this.reconnectInterval = const Duration(seconds: 25),
    this.reconnectCooldown = const Duration(seconds: 10),
    DateTime Function()? now,
  })  : allowLoopback = HubConnectionBootstrapper.defaultAllowLoopbackForPlatform(
          allowLoopback: allowLoopback,
        ),
        now = now ?? DateTime.now,
        super(initialState) {
    _initAutoLifecycle();
  }

  void _initAutoLifecycle() {
    if (!enableAutoLifecycle || _isDisposed) return;

    if (state.isInitialized) {
      unawaited(ensureConnectedOrDiscover(force: true));
    }

    if (reconnectInterval > Duration.zero) {
      _reconnectTimer = Timer.periodic(reconnectInterval, (_) {
        if (_isDisposed || !state.isInitialized) return;
        if (state.phase == HubConnectionPhase.offline ||
            state.phase == HubConnectionPhase.needsDiscovery ||
            state.phase == HubConnectionPhase.unconfigured) {
          unawaited(ensureConnectedOrDiscover());
        }
      });
    }

    try {
      _lifecycleListener = AppLifecycleListener(
        onResume: () {
          if (_isDisposed || !state.isInitialized) return;
          unawaited(ensureConnectedOrDiscover());
        },
      );
    } catch (_) {
      // Headless test ortamlarında binding yoksa sessizce atlanır
    }
  }

  /// Dış taşıma katmanı (ör. [BackgroundSyncCoordinator]) mevcut aktif URL'de
  /// ağ/zaman aşımı hatası gözlediğinde, cihaz hâlâ `connected` görünüyorsa
  /// fazı `offline`a çeker ve yaşam döngüsü aktifse otomatik yeniden keşfi tetikler.
  ///
  /// Eski bir URL'den gelen bayat hatalar yok sayılır.
  void reportTransportUnreachable({
    required String failedUrl,
    String? errorMessage,
  }) {
    if (_isDisposed || !state.isInitialized) return;
    final currentUrl = HubUrlValidator.tryNormalize(
      state.activeHubUrl,
      allowLoopback: allowLoopback,
    );
    final observedUrl = HubUrlValidator.tryNormalize(
      failedUrl,
      allowLoopback: allowLoopback,
    );
    if (currentUrl == null || observedUrl == null || currentUrl != observedUrl) {
      return;
    }
    if (state.phase != HubConnectionPhase.connected) {
      return;
    }

    state = state.copyWith(
      phase: HubConnectionPhase.offline,
      lastCheckedAt: now(),
      isBusy: false,
      errorMessage: errorMessage ?? 'Hub ağ bağlantısı kesildi.',
    );

    if (enableAutoLifecycle) {
      unawaited(ensureConnectedOrDiscover());
    }
  }

  /// Yerel SQLite ayarlarından başlangıç Hub durumunu asenkron yükler.
  Future<void> initializeFromStorage() async {
    if (_isDisposed) return;
    final epoch = ++_operationEpoch;
    final loaded = await HubConnectionBootstrapper.loadInitialState(
      repository: repository,
      allowLoopback: allowLoopback,
      configuredHubUrl: configuredHubUrl,
      desktopFallbackUrl: desktopFallbackUrl,
    );
    if (_isDisposed || epoch != _operationEpoch) return;
    state = loaded;
  }

  /// Aktif Hub adresi için `/health` doğrulaması çalıştırır; başarılı olursa
  /// kalıcı `lastVerifiedAt` bilgisini günceller.
  Future<CentralHealthResponse?> verifyActiveHub() async {
    if (_isDisposed || !state.isInitialized) return null;

    final rawUrl = state.activeHubUrl;
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      final targetPhase = state.phase == HubConnectionPhase.needsDiscovery
          ? HubConnectionPhase.needsDiscovery
          : HubConnectionPhase.unconfigured;
      state = state.copyWith(
        phase: targetPhase,
        clearActiveHubUrl: true,
        isBusy: false,
      );
      return null;
    }

    final normalizedUrl = HubUrlValidator.tryNormalize(
      rawUrl,
      allowLoopback: allowLoopback,
    );
    if (normalizedUrl == null) {
      await repository.clearStoredHubConnection();
      if (_isDisposed) return null;
      state = state.copyWith(
        phase: HubConnectionPhase.needsDiscovery,
        clearActiveHubUrl: true,
        clearHubId: true,
        clearSource: true,
        isBusy: false,
        errorMessage: 'Geçersiz veya platform tarafından engellenmiş Hub adresi.',
      );
      return null;
    }

    final epoch = ++_operationEpoch;
    state = state.copyWith(
      phase: HubConnectionPhase.verifying,
      activeHubUrl: normalizedUrl,
      isBusy: true,
      clearErrorMessage: true,
    );

    final CentralHealthResponse health;
    try {
      health = await checkUrlHealth(normalizedUrl);
    } catch (e) {
      if (_isDisposed || epoch != _operationEpoch) return null;
      state = state.copyWith(
        phase: HubConnectionPhase.offline,
        lastCheckedAt: now(),
        isBusy: false,
        errorMessage: e.toString(),
      );
      return CentralHealthResponse.unreachable(errorMessage: e.toString());
    }

    if (_isDisposed || epoch != _operationEpoch) return health;

    final checkedAt = health.checkedAt;
    if (health.isHealthy) {
      var effectiveSource = state.source ?? HubUrlSource.lastVerified;
      var effectiveHubId = state.hubId;
      DateTime effectiveVerifiedAt = checkedAt;

      final shouldPersistVerification =
          effectiveSource != HubUrlSource.configured &&
              effectiveSource != HubUrlSource.localhostFallback;
      if (shouldPersistVerification) {
        final stored = await repository.markHubConnectionVerified(
          hubUrl: normalizedUrl,
          hubId: effectiveHubId,
          source: effectiveSource,
          allowLoopback: allowLoopback,
          verifiedAt: checkedAt,
        );
        if (_isDisposed || epoch != _operationEpoch) return health;
        effectiveSource = stored.source;
        effectiveHubId = stored.hubId;
        effectiveVerifiedAt = stored.lastVerifiedAt ?? checkedAt;
      }

      state = state.copyWith(
        phase: HubConnectionPhase.connected,
        activeHubUrl: normalizedUrl,
        hubId: effectiveHubId,
        source: effectiveSource,
        lastVerifiedAt: effectiveVerifiedAt,
        lastCheckedAt: checkedAt,
        isInitialized: true,
        isBusy: false,
        clearErrorMessage: true,
      );
      return health;
    }

    state = state.copyWith(
      phase: HubConnectionPhase.offline,
      activeHubUrl: normalizedUrl,
      lastCheckedAt: checkedAt,
      isInitialized: true,
      isBusy: false,
      errorMessage: health.errorMessage ?? 'Hub şu anda erişilebilir değil.',
    );
    return health;
  }

  /// Yeni bir Hub adresini doğrular, kalıcı SQLite ayarına yazar ve aktif hale getirir.
  ///
  /// Geçersiz veya Android'de loopback adres verildiğinde `HubUrlValidationException`
  /// fırlatır; mevcut durum ve kalıcı veritabanı kaydı değiştirilmez.
  Future<bool> setHubUrl(
    String rawUrl, {
    String? hubId,
    HubUrlSource source = HubUrlSource.manual,
    bool verifyHealth = true,
  }) async {
    final normalizedUrl = HubUrlValidator.normalizeAndValidate(
      rawUrl,
      allowLoopback: allowLoopback,
    );

    final epoch = ++_operationEpoch;
    final saved = await repository.saveStoredHubConnection(
      hubUrl: normalizedUrl,
      hubId: hubId,
      source: source,
      allowLoopback: allowLoopback,
      now: now(),
    );
    if (_isDisposed || epoch != _operationEpoch) return false;

    state = state.copyWith(
      phase: verifyHealth
          ? HubConnectionPhase.verifying
          : HubConnectionPhase.offline,
      activeHubUrl: saved.hubUrl,
      hubId: saved.hubId,
      clearHubId: saved.hubId == null,
      source: saved.source,
      lastVerifiedAt: saved.lastVerifiedAt,
      clearLastVerifiedAt: saved.lastVerifiedAt == null,
      isInitialized: true,
      isBusy: verifyHealth,
      clearErrorMessage: true,
    );

    if (!verifyHealth) {
      return true;
    }

    final health = await verifyActiveHub();
    return health?.isHealthy ?? false;
  }

  /// Dış sağlık sonucu (ör. [SystemStatusNotifier.refreshStatus]) üzerinden
  /// aktif URL'nin bağlantı fazını ve doğrulama zamanını senkronize eder.
  Future<void> syncHealthObservation({
    required String url,
    required CentralHealthResponse health,
  }) async {
    if (_isDisposed || !state.isInitialized) return;
    final currentUrl = HubUrlValidator.tryNormalize(
      state.activeHubUrl,
      allowLoopback: allowLoopback,
    );
    final observedUrl = HubUrlValidator.tryNormalize(
      url,
      allowLoopback: allowLoopback,
    );
    if (currentUrl == null || observedUrl == null || currentUrl != observedUrl) {
      return;
    }

    if (health.isHealthy) {
      final shouldPersist = state.source != null &&
          state.source != HubUrlSource.configured &&
          state.source != HubUrlSource.localhostFallback;
      if (shouldPersist) {
        await repository.markHubConnectionVerified(
          hubUrl: currentUrl,
          hubId: state.hubId,
          source: state.source,
          allowLoopback: allowLoopback,
          verifiedAt: health.checkedAt,
        );
        if (_isDisposed) return;
      }
      state = state.copyWith(
        phase: HubConnectionPhase.connected,
        lastVerifiedAt: health.checkedAt,
        lastCheckedAt: health.checkedAt,
        isBusy: false,
        clearErrorMessage: true,
      );
      return;
    }

    state = state.copyWith(
      phase: HubConnectionPhase.offline,
      lastCheckedAt: health.checkedAt,
      isBusy: false,
      errorMessage: health.errorMessage,
    );
  }

  /// Kalıcı Hub yapılandırmasını temizler ve durumu [nextPhase] aşamasına çeker.
  Future<void> clearHubConnection({
    HubConnectionPhase nextPhase = HubConnectionPhase.unconfigured,
  }) async {
    final epoch = ++_operationEpoch;
    await repository.clearStoredHubConnection();
    if (_isDisposed || epoch != _operationEpoch) return;

    state = HubConnectionState(
      phase: nextPhase,
      activeHubUrl: null,
      hubId: null,
      source: null,
      lastVerifiedAt: null,
      lastCheckedAt: null,
      isInitialized: true,
      isBusy: false,
      errorMessage: null,
    );
  }

  /// Yerel ağda UDP 8946 yayınıyla Master Hub keşfeder, aday IP'leri sırayla
  /// `/health` ile doğrular ve ilk sağlıklı Hub'ı kalıcı ayara kaydedip bağlanır.
  Future<bool> discoverAndConnect({
    Duration timeout = const Duration(milliseconds: 2500),
  }) {
    if (_isDisposed || discoveryClient == null) {
      return Future.value(false);
    }
    if (_activeDiscoveryFuture != null) {
      return _activeDiscoveryFuture!;
    }

    final future = _runDiscoverAndConnect(timeout: timeout);
    _activeDiscoveryFuture = future;
    future.whenComplete(() {
      if (identical(_activeDiscoveryFuture, future)) {
        _activeDiscoveryFuture = null;
      }
    });
    return future;
  }

  Future<bool> _runDiscoverAndConnect({required Duration timeout}) async {
    final epoch = ++_operationEpoch;
    state = state.copyWith(
      phase: HubConnectionPhase.discovering,
      isBusy: true,
      isInitialized: true,
      clearErrorMessage: true,
    );

    List<DiscoveredHubCandidate> candidates = const <DiscoveredHubCandidate>[];
    try {
      candidates = await discoveryClient!.discover(
        deviceId: deviceId,
        timeout: timeout,
      );
    } catch (e) {
      debugPrint('[HubConnectionNotifier] UDP keşif hatası: $e');
    }

    if (_isDisposed || epoch != _operationEpoch) return false;

    String? lastFailureMessage;
    for (final candidate in candidates) {
      final candidateUrls = candidate.candidateBaseUrls(
        allowLoopback: allowLoopback,
      );
      for (final candidateUrl in candidateUrls) {
        if (_isDisposed || epoch != _operationEpoch) return false;

        final CentralHealthResponse health;
        try {
          health = await checkUrlHealth(candidateUrl);
        } catch (e) {
          lastFailureMessage = e.toString();
          continue;
        }

        if (_isDisposed || epoch != _operationEpoch) return false;
        if (health.isHealthy) {
          final stored = await repository.markHubConnectionVerified(
            hubUrl: candidateUrl,
            hubId: candidate.hubId,
            source: HubUrlSource.discovered,
            allowLoopback: allowLoopback,
            verifiedAt: health.checkedAt,
          );
          if (_isDisposed || epoch != _operationEpoch) return false;

          state = state.copyWith(
            phase: HubConnectionPhase.connected,
            activeHubUrl: stored.hubUrl,
            hubId: stored.hubId,
            source: stored.source,
            lastVerifiedAt: stored.lastVerifiedAt ?? health.checkedAt,
            lastCheckedAt: health.checkedAt,
            isInitialized: true,
            isBusy: false,
            clearErrorMessage: true,
          );
          return true;
        } else {
          lastFailureMessage = health.errorMessage;
        }
      }
    }

    if (_isDisposed || epoch != _operationEpoch) return false;

    final checkedAt = now();
    if (state.hasActiveHubUrl) {
      state = state.copyWith(
        phase: HubConnectionPhase.offline,
        lastCheckedAt: checkedAt,
        isInitialized: true,
        isBusy: false,
        errorMessage: candidates.isEmpty
            ? 'Yerel ağda Hub bulunamadı; kayıtlı son adres çevrimdışı modda korunuyor.'
            : (lastFailureMessage ??
                'Bulunan Hub adayı sağlık kontrolünden geçemedi.'),
      );
    } else {
      state = state.copyWith(
        phase: HubConnectionPhase.needsDiscovery,
        clearActiveHubUrl: true,
        lastCheckedAt: checkedAt,
        isInitialized: true,
        isBusy: false,
        errorMessage: candidates.isEmpty
            ? 'Yerel ağda Master Hub bulunamadı. Aynı Wi-Fi ağında olduğunuzdan emin olun veya manuel IP girin.'
            : (lastFailureMessage ??
                'Bulunan Hub adayı sağlık kontrolünden geçemedi.'),
      );
    }
    return false;
  }

  /// Önce kayıtlı/aktif son Hub adresini doğrular; erişilemezse veya adres yoksa
  /// tekil (single-flight) olarak UDP keşfine düşerek bağlantıyı yeniden kurar.
  Future<bool> ensureConnectedOrDiscover({
    bool allowDiscoveryFallback = true,
    bool force = false,
    Duration discoveryTimeout = const Duration(milliseconds: 2500),
  }) {
    if (_isDisposed || !state.isInitialized) {
      return Future.value(false);
    }
    if (_activeReconnectFuture != null) {
      return _activeReconnectFuture!;
    }
    if (_activeDiscoveryFuture != null) {
      return _activeDiscoveryFuture!;
    }

    if (!force && _lastAutoAttemptAt != null) {
      final elapsed = now().difference(_lastAutoAttemptAt!);
      if (elapsed < reconnectCooldown) {
        return Future.value(state.phase == HubConnectionPhase.connected);
      }
    }

    _lastAutoAttemptAt = now();
    final future = _runEnsureConnectedOrDiscover(
      allowDiscoveryFallback: allowDiscoveryFallback,
      discoveryTimeout: discoveryTimeout,
    );
    _activeReconnectFuture = future;
    future.whenComplete(() {
      if (identical(_activeReconnectFuture, future)) {
        _activeReconnectFuture = null;
      }
    });
    return future;
  }

  Future<bool> _runEnsureConnectedOrDiscover({
    required bool allowDiscoveryFallback,
    required Duration discoveryTimeout,
  }) async {
    if (state.hasActiveHubUrl) {
      final health = await verifyActiveHub();
      if (_isDisposed) return false;
      if (health != null && health.isHealthy) {
        return true;
      }
    }

    if (allowDiscoveryFallback && discoveryClient != null) {
      return discoverAndConnect(timeout: discoveryTimeout);
    }
    return false;
  }

  /// Kullanıcının Diagnostics ekranından girdiği IP/host/URL'yi doğrular,
  /// sağlık kontrolü başarılıysa kalıcı SQLite ayarına yazar ve aktif eder.
  ///
  /// Geçersiz veya erişilemeyen bir adres girildiğinde önceden kayıtlı çalışan
  /// Hub adresini ASLA silmez veya üzerine yazmaz.
  Future<HubManualConnectResult> connectToManualAddress(String rawInput) async {
    if (_isDisposed) {
      return const HubManualConnectResult(
        isSuccess: false,
        message: 'Bağlantı yöneticisi aktif değil.',
      );
    }

    final String normalizedUrl;
    try {
      normalizedUrl = HubUrlValidator.normalizeUserInput(
        rawInput,
        defaultPort: AppConstants.defaultBackendPort,
        allowLoopback: allowLoopback,
      );
    } on HubUrlValidationException catch (e) {
      state = state.copyWith(errorMessage: e.message);
      return HubManualConnectResult(isSuccess: false, message: e.message);
    }

    final epoch = ++_operationEpoch;
    state = state.copyWith(isBusy: true, clearErrorMessage: true);

    final CentralHealthResponse health;
    try {
      health = await checkUrlHealth(normalizedUrl);
    } catch (e) {
      if (_isDisposed || epoch != _operationEpoch) {
        return const HubManualConnectResult(
          isSuccess: false,
          message: 'Bağlantı denemesi iptal edildi.',
        );
      }
      final msg = 'Hub adresine ulaşılamadı ($normalizedUrl): $e';
      state = state.copyWith(isBusy: false, errorMessage: msg);
      return HubManualConnectResult(
        isSuccess: false,
        normalizedUrl: normalizedUrl,
        message: msg,
      );
    }

    if (_isDisposed || epoch != _operationEpoch) {
      return const HubManualConnectResult(
        isSuccess: false,
        message: 'Bağlantı denemesi daha yeni bir işlem nedeniyle iptal edildi.',
      );
    }

    if (!health.isHealthy) {
      final reason = health.errorMessage ?? 'Sağlık yanıtı alınamadı';
      final msg = 'Hub doğrulanamadı ($normalizedUrl): $reason';
      state = state.copyWith(
        phase: state.hasActiveHubUrl ? state.phase : HubConnectionPhase.offline,
        lastCheckedAt: health.checkedAt,
        isBusy: false,
        errorMessage: msg,
      );
      return HubManualConnectResult(
        isSuccess: false,
        normalizedUrl: normalizedUrl,
        message: msg,
      );
    }

    final stored = await repository.markHubConnectionVerified(
      hubUrl: normalizedUrl,
      source: HubUrlSource.manual,
      allowLoopback: allowLoopback,
      verifiedAt: health.checkedAt,
    );
    if (_isDisposed || epoch != _operationEpoch) {
      return const HubManualConnectResult(
        isSuccess: false,
        message: 'Bağlantı denemesi iptal edildi.',
      );
    }

    state = state.copyWith(
      phase: HubConnectionPhase.connected,
      activeHubUrl: stored.hubUrl,
      hubId: stored.hubId,
      clearHubId: stored.hubId == null,
      source: stored.source,
      lastVerifiedAt: stored.lastVerifiedAt ?? health.checkedAt,
      lastCheckedAt: health.checkedAt,
      isInitialized: true,
      isBusy: false,
      clearErrorMessage: true,
    );

    return HubManualConnectResult(
      isSuccess: true,
      normalizedUrl: stored.hubUrl,
      message: 'Hub bağlantısı doğrulandı ve kaydedildi (${stored.hubUrl}).',
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
    super.dispose();
  }
}

/// MARKET MMS - Dinamik Hub Bağlantı Durumu Sağlayıcısı
final StateNotifierProvider<HubConnectionNotifier, HubConnectionState>
    hubConnectionProvider =
    StateNotifierProvider<HubConnectionNotifier, HubConnectionState>((ref) {
  final localDb = ref.watch(localDatabaseServiceProvider);
  final initialOverride = ref.watch(initialHubConnectionStateProvider);
  final allowLoopback = ref.watch(hubAllowLoopbackPolicyProvider);
  final discoveryClient = ref.watch(hubDiscoveryClientProvider);
  final enableAutoLifecycle =
      ref.watch(hubAutoDiscoveryLifecycleEnabledProvider);
  final apiClient = ref.read(apiClientProvider);

  Future<CentralHealthResponse> checkUrlHealth(String url) {
    final currentClient = ref.read(apiClientProvider);
    try {
      return currentClient.checkHealthForUrl(url);
    } on UnimplementedError {
      return currentClient.checkHealth();
    } catch (e) {
      return Future.value(
        CentralHealthResponse.unreachable(errorMessage: e.toString()),
      );
    }
  }

  final notifier = HubConnectionNotifier(
    repository: localDb.repository,
    checkUrlHealth: checkUrlHealth,
    discoveryClient: discoveryClient,
    deviceId: apiClient.deviceId,
    allowLoopback: allowLoopback,
    enableAutoLifecycle: enableAutoLifecycle,
    initialState: initialOverride ?? const HubConnectionState.initial(),
  );

  if (initialOverride == null) {
    unawaited(
      notifier.initializeFromStorage().then((_) {
        if (enableAutoLifecycle) {
          return notifier.ensureConnectedOrDiscover(force: true);
        }
        return false;
      }).catchError((Object error, StackTrace _) {
        debugPrint('[HubConnectionNotifier] Başlangıç yükleme hatası: $error');
        return false;
      }),
    );
  }

  return notifier;
});
