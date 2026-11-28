import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/user_friendly_error_mapper.dart';
import 'data/app_update_checker.dart';
import 'data/app_update_installer.dart';
import 'domain/app_update_info.dart';

/// Widget ve entegrasyon testlerinde açılışta gerçek GitHub API isteğini
/// izole etmek için varsayılan `false` tutulur; `main.dart` içinde `true` yapılır.
final appUpdateAutoCheckEnabledProvider = Provider<bool>((ref) => false);

final appUpdateCheckerProvider = Provider<AppUpdateChecker>(
  (ref) => const AppUpdateChecker(),
);

final appUpdateInstallerProvider = Provider<AppUpdateInstaller>(
  (ref) => const AppUpdateInstaller(),
);

class AppUpdateState {
  final bool isChecking;
  final bool isDownloading;
  final double? downloadProgress;
  final AppUpdateCheckResult? lastResult;
  final String? errorMessage;
  final bool bannerDismissed;

  const AppUpdateState({
    this.isChecking = false,
    this.isDownloading = false,
    this.downloadProgress,
    this.lastResult,
    this.errorMessage,
    this.bannerDismissed = false,
  });

  AppUpdateManifest? get availableManifest {
    final res = lastResult;
    if (res == null) return null;
    if (res.availability != AppUpdateAvailability.updateAvailable &&
        res.availability != AppUpdateAvailability.updateRequired) {
      return null;
    }
    return res.manifest;
  }

  bool get hasAvailableUpdate => availableManifest != null;

  static const _sentinel = Object();

  AppUpdateState copyWith({
    bool? isChecking,
    bool? isDownloading,
    Object? downloadProgress = _sentinel,
    Object? lastResult = _sentinel,
    Object? errorMessage = _sentinel,
    bool? bannerDismissed,
  }) {
    return AppUpdateState(
      isChecking: isChecking ?? this.isChecking,
      isDownloading: isDownloading ?? this.isDownloading,
      downloadProgress: identical(downloadProgress, _sentinel)
          ? this.downloadProgress
          : downloadProgress as double?,
      lastResult: identical(lastResult, _sentinel)
          ? this.lastResult
          : lastResult as AppUpdateCheckResult?,
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
      bannerDismissed: bannerDismissed ?? this.bannerDismissed,
    );
  }
}

class AppUpdateController extends StateNotifier<AppUpdateState> {
  final AppUpdateChecker checker;
  final AppUpdateInstaller installer;
  final TargetPlatform? platformOverride;

  AppUpdateController({
    required this.checker,
    required this.installer,
    this.platformOverride,
  }) : super(const AppUpdateState());

  Future<void> checkForUpdates({bool silent = false}) async {
    if (state.isChecking || state.isDownloading) return;
    state = state.copyWith(
      isChecking: true,
      errorMessage: silent ? state.errorMessage : null,
    );

    final result = await checker.checkGitHubRelease(
      platform: platformOverride ?? defaultTargetPlatform,
    );
    if (!mounted) return;

    if (silent && result.availability == AppUpdateAvailability.unavailable) {
      state = state.copyWith(isChecking: false);
      return;
    }

    final hasNew = result.availability == AppUpdateAvailability.updateAvailable ||
        result.availability == AppUpdateAvailability.updateRequired;
    state = state.copyWith(
      isChecking: false,
      lastResult: result,
      errorMessage: null,
      bannerDismissed: hasNew ? false : state.bannerDismissed,
    );
  }

  Future<void> downloadAndInstall() async {
    final manifest = state.availableManifest;
    if (manifest == null || state.isDownloading) return;

    state = state.copyWith(
      isDownloading: true,
      downloadProgress: 0.0,
      errorMessage: null,
    );

    try {
      await installer.downloadVerifyAndInstall(
        manifest,
        onProgress: (progress) {
          if (!mounted) return;
          state = state.copyWith(downloadProgress: progress);
        },
      );
      if (!mounted) return;
      state = state.copyWith(
        isDownloading: false,
        downloadProgress: 1.0,
      );
    } on AppUpdateInstallException catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isDownloading: false,
        downloadProgress: null,
        errorMessage: e.message,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isDownloading: false,
        downloadProgress: null,
        errorMessage: UserFriendlyErrorMapper.map(
          e,
          fallback: 'Güncelleme indirilemedi veya kurulum başlatılamadı.',
        ),
      );
    }
  }

  void dismissBanner() {
    state = state.copyWith(bannerDismissed: true);
  }
}

final appUpdateControllerProvider =
    StateNotifierProvider<AppUpdateController, AppUpdateState>((ref) {
  return AppUpdateController(
    checker: ref.watch(appUpdateCheckerProvider),
    installer: ref.watch(appUpdateInstallerProvider),
  );
});

/// Uygulama kabuğu açıldığında arka planda tek seferlik sessiz güncelleme
/// denetimini tetikler (offline durumda UI açılışını asla bloklamaz).
final appUpdateStartupTriggerProvider = Provider<void>((ref) {
  if (!ref.watch(appUpdateAutoCheckEnabledProvider)) return;
  var disposed = false;
  ref.onDispose(() => disposed = true);
  Future<void>.microtask(() {
    if (disposed) return;
    ref.read(appUpdateControllerProvider.notifier).checkForUpdates(silent: true);
  });
});
