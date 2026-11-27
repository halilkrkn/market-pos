import 'package:flutter/services.dart';

import 'windows_tray_models.dart';

/// Windows yerel Win32 Sistem Tepsisi ve HKCU Run otomatik başlatma soyutlaması.
abstract class WindowsDesktopShellGateway {
  bool get isSupported;

  void setActionHandler(
    Future<void> Function(WindowsTrayMenuAction action)? handler,
  );

  Future<bool> initializeTray();
  Future<void> updateTrayStatus(WindowsTrayStatusSnapshot snapshot);
  Future<void> showWindow();
  Future<void> hideToTray();
  Future<void> confirmExit();
  Future<bool> getAutoStartEnabled();
  Future<bool> setAutoStartEnabled(bool enabled);
}

/// Gerçek Win32 runner ile `com.marketmms.market_pos/windows_shell` MethodChannel köprüsü.
class MethodChannelWindowsDesktopShellGateway
    implements WindowsDesktopShellGateway {
  static const MethodChannel _channel = MethodChannel(
    'com.marketmms.market_pos/windows_shell',
  );

  Future<void> Function(WindowsTrayMenuAction action)? _actionHandler;

  MethodChannelWindowsDesktopShellGateway() {
    _channel.setMethodCallHandler(_handleIncomingCall);
  }

  @override
  bool get isSupported => true;

  @override
  void setActionHandler(
    Future<void> Function(WindowsTrayMenuAction action)? handler,
  ) {
    _actionHandler = handler;
  }

  Future<dynamic> _handleIncomingCall(MethodCall call) async {
    if (call.method == 'onTrayAction') {
      final rawAction = call.arguments as String?;
      final parsed = WindowsTrayMenuAction.fromWireName(rawAction);
      final handler = _actionHandler;
      if (parsed != null && handler != null) {
        await handler(parsed);
      }
    }
    return null;
  }

  @override
  Future<bool> initializeTray() async {
    final result = await _channel.invokeMethod<bool>('initializeTray');
    return result ?? false;
  }

  @override
  Future<void> updateTrayStatus(WindowsTrayStatusSnapshot snapshot) async {
    await _channel.invokeMethod<bool>(
      'updateTrayStatus',
      snapshot.toChannelMap(),
    );
  }

  @override
  Future<void> showWindow() async {
    await _channel.invokeMethod<bool>('showWindow');
  }

  @override
  Future<void> hideToTray() async {
    await _channel.invokeMethod<bool>('hideToTray');
  }

  @override
  Future<void> confirmExit() async {
    await _channel.invokeMethod<bool>('confirmExit');
  }

  @override
  Future<bool> getAutoStartEnabled() async {
    final result = await _channel.invokeMethod<bool>('getAutoStartEnabled');
    return result ?? false;
  }

  @override
  Future<bool> setAutoStartEnabled(bool enabled) async {
    final result = await _channel.invokeMethod<bool>(
      'setAutoStartEnabled',
      enabled,
    );
    return result ?? false;
  }
}

/// Windows dışı platformlar ve izole widget/unit testleri için güvenli no-op ağ geçidi.
class NoopWindowsDesktopShellGateway implements WindowsDesktopShellGateway {
  const NoopWindowsDesktopShellGateway();

  @override
  bool get isSupported => false;

  @override
  void setActionHandler(
    Future<void> Function(WindowsTrayMenuAction action)? handler,
  ) {}

  @override
  Future<bool> initializeTray() async => false;

  @override
  Future<void> updateTrayStatus(WindowsTrayStatusSnapshot snapshot) async {}

  @override
  Future<void> showWindow() async {}

  @override
  Future<void> hideToTray() async {}

  @override
  Future<void> confirmExit() async {}

  @override
  Future<bool> getAutoStartEnabled() async => false;

  @override
  Future<bool> setAutoStartEnabled(bool enabled) async => false;
}
