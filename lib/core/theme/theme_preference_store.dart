import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Uygulama tema tercihi kalıcılık sözleşmesi.
abstract class ThemePreferenceStore {
  Future<ThemeMode> load();
  Future<void> save(ThemeMode mode);
}

/// Testler için bellek içi tema tercihi deposu.
class InMemoryThemePreferenceStore implements ThemePreferenceStore {
  ThemeMode _mode;

  InMemoryThemePreferenceStore([this._mode = ThemeMode.system]);

  @override
  Future<ThemeMode> load() async => _mode;

  @override
  Future<void> save(ThemeMode mode) async {
    _mode = mode;
  }
}

/// Yerel `client_theme.json` dosyasında atomik `.tmp` + rename ile tema modu
/// saklayan kalıcı depo (DB şema sürümünü değiştirmeden çalışır).
class FileThemePreferenceStore implements ThemePreferenceStore {
  static const String defaultFileName = 'client_theme.json';

  final File file;

  FileThemePreferenceStore({required this.file});

  factory FileThemePreferenceStore.inDirectory(Directory dataDir) {
    return FileThemePreferenceStore(
      file: File(p.join(dataDir.path, defaultFileName)),
    );
  }

  static String encodeMode(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  static ThemeMode decodeMode(Object? raw) => switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  @override
  Future<ThemeMode> load() async {
    try {
      if (!await file.exists()) {
        return ThemeMode.system;
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return ThemeMode.system;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return ThemeMode.system;
      }
      return decodeMode(decoded['theme_mode']);
    } catch (e) {
      debugPrint('[FileThemePreferenceStore] Tema okunamadı, system kullanılıyor: $e');
      return ThemeMode.system;
    }
  }

  @override
  Future<void> save(ThemeMode mode) async {
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    final tmpFile = File('${file.path}.tmp');
    final encoded = jsonEncode(<String, dynamic>{
      'version': 1,
      'theme_mode': encodeMode(mode),
    });
    await tmpFile.writeAsString(encoded, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tmpFile.rename(file.path);
  }
}
