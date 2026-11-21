import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// MARKET MMS — Uygulama Tema Modu Yöneticisi (Light / Dark / System)
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier([super.initial = ThemeMode.system]);

  void setThemeMode(ThemeMode mode) {
    state = mode;
  }

  void toggleLightDark(Brightness currentPlatformBrightness) {
    if (state == ThemeMode.dark ||
        (state == ThemeMode.system && currentPlatformBrightness == Brightness.dark)) {
      state = ThemeMode.light;
    } else {
      state = ThemeMode.dark;
    }
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier(ThemeMode.system);
});
