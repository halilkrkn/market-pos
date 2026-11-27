import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/user_friendly_error_mapper.dart';
import '../../domain/app_destination.dart';
import 'windows_desktop_shell_gateway.dart';
import 'windows_tray_models.dart';

/// MARKET MMS Windows Sistem Tepsisi, Otomatik Başlatma ve Kontrollü Çıkış Denetleyicisi.
///
/// Presentation katmanında yer alır; domain/data katmanlarına UI bağımlılığı eklemez.
/// "Uygulamadan Çık" akışında aktif senkronizasyon ve yedek turları duraklatılır,
/// yerel SQLite bağlantısı (Outbox dahil) kontrollü şekilde kapatılır ve ardından
/// native pencere kapatma onayı verilir.
class WindowsTrayController extends StateNotifier<WindowsTrayState> {
  final WindowsDesktopShellGateway gateway;
  final void Function(AppDestination destination) onNavigate;
  final Future<void> Function() onPauseSyncForExit;
  final Future<void> Function() onWaitBackupIdleForExit;
  final Future<void> Function() onCloseDatabaseForExit;

  bool _initialized = false;
  bool _isDisposed = false;
  WindowsTrayStatusSnapshot? _lastPushedSnapshot;

  WindowsTrayController({
    required this.gateway,
    required this.onNavigate,
    required this.onPauseSyncForExit,
    required this.onWaitBackupIdleForExit,
    required this.onCloseDatabaseForExit,
  }) : super(WindowsTrayState.initial(isSupported: gateway.isSupported));

  Future<void> initialize() async {
    if (_initialized || _isDisposed || !gateway.isSupported) return;
    _initialized = true;
    gateway.setActionHandler(handleMenuAction);

    try {
      final trayOk = await gateway.initializeTray();
      final autoStart = await gateway.getAutoStartEnabled();
      if (_isDisposed) return;
      state = state.copyWith(
        isTrayActive: trayOk,
        autoStartEnabled: autoStart,
        lastError: trayOk
            ? null
            : 'Sistem tepsisi simgesi oluşturulamadı.',
      );
    } catch (e) {
      if (_isDisposed) return;
      state = state.copyWith(
        isTrayActive: false,
        lastError: UserFriendlyErrorMapper.map(
          e,
          fallback: 'Sistem tepsisi başlatılamadı.',
        ),
      );
    }
  }

  Future<void> pushStatus(WindowsTrayStatusSnapshot snapshot) async {
    if (_isDisposed || !gateway.isSupported || !state.isTrayActive) return;
    if (_lastPushedSnapshot == snapshot) return;
    _lastPushedSnapshot = snapshot;
    try {
      await gateway.updateTrayStatus(snapshot);
    } catch (e) {
      debugPrint(
        '[WindowsTrayController] Tepsi durumu güncellenemedi: ${UserFriendlyErrorMapper.redactSecrets(e.toString())}',
      );
    }
  }

  Future<void> showWindow() async {
    if (_isDisposed || !gateway.isSupported) return;
    await gateway.showWindow();
  }

  Future<void> hideToTray() async {
    if (_isDisposed || !gateway.isSupported) return;
    await gateway.hideToTray();
  }

  Future<void> setAutoStartEnabled(bool enabled) async {
    if (_isDisposed || !gateway.isSupported || state.isAutoStartBusy) return;
    state = state.copyWith(isAutoStartBusy: true, lastError: null);
    try {
      final wrote = await gateway.setAutoStartEnabled(enabled);
      final actual = await gateway.getAutoStartEnabled();
      if (_isDisposed) return;
      state = state.copyWith(
        autoStartEnabled: actual,
        isAutoStartBusy: false,
        lastError: wrote
            ? null
            : 'Windows otomatik başlatma ayarı güncellenemedi.',
      );
    } catch (e) {
      if (_isDisposed) return;
      state = state.copyWith(
        isAutoStartBusy: false,
        lastError: UserFriendlyErrorMapper.map(
          e,
          fallback: 'Windows otomatik başlatma ayarı güncellenemedi.',
        ),
      );
    }
  }

  Future<void> handleMenuAction(WindowsTrayMenuAction action) async {
    if (_isDisposed) return;
    switch (action) {
      case WindowsTrayMenuAction.openApp:
        await showWindow();
      case WindowsTrayMenuAction.openHubStatus:
      case WindowsTrayMenuAction.openSyncStatus:
      case WindowsTrayMenuAction.openBackupStatus:
      case WindowsTrayMenuAction.openSettings:
        onNavigate(AppDestination.diagnostics);
        await showWindow();
      case WindowsTrayMenuAction.requestExit:
        await performControlledExit();
    }
  }

  /// Kontrollü çıkış:
  /// 1. Yeni ve devam eden senkronizasyon turunu güvenle duraklatır.
  /// 2. Aktif yedekleme turunun bitmesini sınırlı süreyle bekler.
  /// 3. Yerel Drift SQLite bağlantısını (Outbox bütünlüğü korunarak) kapatır.
  /// 4. Native Win32 tepsisini kaldırıp pencereyi sonlandırır.
  Future<void> performControlledExit() async {
    if (_isDisposed || state.isExiting) return;
    state = state.copyWith(isExiting: true, lastError: null);

    try {
      await onPauseSyncForExit();
    } catch (e) {
      debugPrint(
        '[WindowsTrayController] Çıkış öncesi senkronizasyon duraklatma uyarısı: ${UserFriendlyErrorMapper.redactSecrets(e.toString())}',
      );
    }

    try {
      await onWaitBackupIdleForExit();
    } catch (e) {
      debugPrint(
        '[WindowsTrayController] Çıkış öncesi yedekleme bekleme uyarısı: ${UserFriendlyErrorMapper.redactSecrets(e.toString())}',
      );
    }

    try {
      await onCloseDatabaseForExit();
    } catch (e) {
      debugPrint(
        '[WindowsTrayController] Çıkış öncesi veritabanı kapatma uyarısı: ${UserFriendlyErrorMapper.redactSecrets(e.toString())}',
      );
    }

    if (gateway.isSupported) {
      try {
        await gateway.confirmExit();
      } catch (e) {
        if (!_isDisposed) {
          state = state.copyWith(
            isExiting: false,
            lastError: UserFriendlyErrorMapper.map(
              e,
              fallback: 'Uygulama kapatılırken hata oluştu.',
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    gateway.setActionHandler(null);
    super.dispose();
  }
}
