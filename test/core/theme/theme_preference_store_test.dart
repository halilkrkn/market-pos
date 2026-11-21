import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/core/theme/theme_preference_store.dart';
import 'package:market_pos/core/theme/theme_provider.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ThemePreferenceStore & ThemeModeNotifier Kalıcılık Testleri', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('mms_theme_store_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('FileThemePreferenceStore: dosya yokken system döner, light/dark/system değerlerini korur', () async {
      final store = FileThemePreferenceStore.inDirectory(tempDir);
      expect(await store.load(), ThemeMode.system);

      await store.save(ThemeMode.dark);
      expect(await store.load(), ThemeMode.dark);

      await store.save(ThemeMode.light);
      expect(await store.load(), ThemeMode.light);

      await store.save(ThemeMode.system);
      expect(await store.load(), ThemeMode.system);
    });

    test('FileThemePreferenceStore: bozuk JSON dosyasında çökmez ve ThemeMode.system döner', () async {
      final file = File(p.join(tempDir.path, FileThemePreferenceStore.defaultFileName));
      await file.writeAsString('{bozuk_json', flush: true);

      final store = FileThemePreferenceStore(file: file);
      expect(await store.load(), ThemeMode.system);
    });

    test('ThemeModeNotifier: setThemeMode ve toggleLightDark değişikliklerini kalıcı kaydeder', () async {
      final store = FileThemePreferenceStore.inDirectory(tempDir);
      final notifier = ThemeModeNotifier(ThemeMode.system, store);
      addTearDown(notifier.dispose);

      notifier.setThemeMode(ThemeMode.dark);
      expect(notifier.state, ThemeMode.dark);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await store.load(), ThemeMode.dark);

      notifier.toggleLightDark(Brightness.dark);
      expect(notifier.state, ThemeMode.light);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await store.load(), ThemeMode.light);
    });
  });
}
