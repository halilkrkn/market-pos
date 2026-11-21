import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme_preference_store.dart';

final themePreferenceStoreProvider = Provider<ThemePreferenceStore>((ref) {
  return InMemoryThemePreferenceStore();
});

final initialThemeModeProvider = Provider<ThemeMode>((ref) {
  return ThemeMode.system;
});

/// MARKET MMS — Uygulama Tema Modu Yöneticisi (Light / Dark / System)
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final ThemePreferenceStore? _store;

  ThemeModeNotifier([
    super.initial = ThemeMode.system,
    ThemePreferenceStore? store,
  ]) : _store = store;

  void setThemeMode(ThemeMode mode) {
    if (state == mode) return;
    state = mode;
    unawaited(_persist(mode));
  }

  void toggleLightDark(Brightness currentPlatformBrightness) {
    final next = (state == ThemeMode.dark ||
            (state == ThemeMode.system &&
                currentPlatformBrightness == Brightness.dark))
        ? ThemeMode.light
        : ThemeMode.dark;
    state = next;
    unawaited(_persist(next));
  }

  Future<void> _persist(ThemeMode mode) async {
    final store = _store;
    if (store == null) return;
    try {
      await store.save(mode);
    } catch (e) {
      debugPrint('[ThemeModeNotifier] Tema tercihi kaydedilemedi: $e');
    }
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  final initial = ref.watch(initialThemeModeProvider);
  final store = ref.watch(themePreferenceStoreProvider);
  return ThemeModeNotifier(initial, store);
});
