import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/app_setup_config.dart';

/// İstemci kurulum ve çoklu şube/tenant yapılandırması kalıcılık sözleşmesi.
abstract class SetupConfigStore {
  Future<AppSetupConfig> load();
  Future<void> save(AppSetupConfig config);
  Future<void> clear();
}

/// Widget testleri ve geçici oturumlar için bellek içi kurulum deposu.
class InMemorySetupConfigStore implements SetupConfigStore {
  AppSetupConfig _config;

  InMemorySetupConfigStore([AppSetupConfig? initialConfig])
      : _config = initialConfig ?? AppSetupConfig.initial();

  @override
  Future<AppSetupConfig> load() async => _config;

  @override
  Future<void> save(AppSetupConfig config) async {
    _config = config;
  }

  @override
  Future<void> clear() async {
    _config = AppSetupConfig.initial();
  }
}

/// Üretim ortamı için `client_config.json` tabanlı atomik kurulum deposu.
///
/// Yazma işlemleri `.tmp` geçici dosya + rename ile yarıda kalma riskine karşı korunur.
class FileSetupConfigStore implements SetupConfigStore {
  static const String defaultConfigFileName = 'client_config.json';

  final File configFile;

  FileSetupConfigStore({required this.configFile});

  factory FileSetupConfigStore.inDirectory(Directory dataDir) {
    return FileSetupConfigStore(
      configFile: File(p.join(dataDir.path, defaultConfigFileName)),
    );
  }

  @override
  Future<AppSetupConfig> load() async {
    try {
      if (!await configFile.exists()) {
        return AppSetupConfig.initial();
      }
      final raw = await configFile.readAsString();
      if (raw.trim().isEmpty) {
        return AppSetupConfig.initial();
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return AppSetupConfig.initial();
      }
      return AppSetupConfig.fromJson(decoded);
    } catch (_) {
      return AppSetupConfig.initial();
    }
  }

  @override
  Future<void> save(AppSetupConfig config) async {
    if (!configFile.parent.existsSync()) {
      configFile.parent.createSync(recursive: true);
    }
    final tmpFile = File('${configFile.path}.tmp');
    final encoded = const JsonEncoder.withIndent('  ').convert(config.toJson());
    await tmpFile.writeAsString(encoded, flush: true);
    if (await configFile.exists()) {
      await configFile.delete();
    }
    await tmpFile.rename(configFile.path);
  }

  @override
  Future<void> clear() async {
    if (await configFile.exists()) {
      await configFile.delete();
    }
    final tmpFile = File('${configFile.path}.tmp');
    if (await tmpFile.exists()) {
      await tmpFile.delete();
    }
  }
}
