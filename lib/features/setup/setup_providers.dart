import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/tls_pinned_client_factory.dart';
import '../diagnostics/application/system_status_notifier.dart';
import 'application/setup_config_notifier.dart';
import 'data/local_setup_config_store.dart';
import 'domain/app_setup_config.dart';

/// Varsayılan kurulum deposu (testlerde bellek içi; `main.dart`'ta [FileSetupConfigStore] override edilir).
final setupConfigStoreProvider = Provider<SetupConfigStore>((ref) {
  return InMemorySetupConfigStore();
});

/// Başlangıçta senkron yüklenen kurulum durumu (opsiyonel override).
final initialSetupConfigProvider = Provider<AppSetupConfig?>((ref) => null);

/// Ana kabukta tamamlanmamış kurulum uyarısının gösterilip gösterilmeyeceği.
///
/// Üretim başlatıcısında (`main.dart`) `true` olarak açılır; mevcut kabuk ve
/// ekran widget testlerinde görsel düzeni bozmamak için varsayılan `false` kalır.
final setupWizardBannerEnabledProvider = Provider<bool>((ref) => false);

final setupConfigProvider =
    StateNotifierProvider<SetupConfigNotifier, AppSetupConfig>((ref) {
  final store = ref.watch(setupConfigStoreProvider);
  final initial = ref.watch(initialSetupConfigProvider);
  return SetupConfigNotifier(
    store: store,
    initialState: initial,
    // Faz 7A: Bekleyen Outbox varken cihaz/tenant/şube kimliği değiştirilemez.
    countUnsyncedOutbox: (deviceId) async {
      final summary = await ref
          .read(localDatabaseServiceProvider)
          .repository
          .getOutboxSummary(deviceId: deviceId);
      return summary.totalUnsynced;
    },
  );
});

/// B-2 aktif edildiğinde [PinnedTlsConfig] döner; pasifse `null` döner.
final pinnedTlsConfigProvider = Provider<PinnedTlsConfig?>((ref) {
  final setup = ref.watch(setupConfigProvider);
  if (!setup.hasPinnedCertificate) {
    return null;
  }
  return PinnedTlsConfig(
    caCertPem: setup.pinnedCaPem,
    expectedSha256Hex: setup.normalizedPinSha256!,
  );
});
