import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import 'package:path/path.dart' as p;

/// ADR-021 / K-05: Mağaza içi yetkili ve iptal edilmiş cihaz kayıt defteri
/// kalıcılık sözleşmesi.
abstract class DriveAuthorizedRegistryStore {
  Future<DriveAuthorizedDeviceRegistry> load();
  Future<void> save(DriveAuthorizedDeviceRegistry registry);
}

/// Testler için bellek içi cihaz kayıt defteri deposu.
class InMemoryDriveAuthorizedRegistryStore
    implements DriveAuthorizedRegistryStore {
  DriveAuthorizedDeviceRegistry _registry;

  InMemoryDriveAuthorizedRegistryStore([
    DriveAuthorizedDeviceRegistry? initialRegistry,
  ]) : _registry = initialRegistry ?? DriveAuthorizedDeviceRegistry();

  @override
  Future<DriveAuthorizedDeviceRegistry> load() async => _registry;

  @override
  Future<void> save(DriveAuthorizedDeviceRegistry registry) async {
    _registry = DriveAuthorizedDeviceRegistry(registry.all);
  }
}

/// Yerel `drive_authorized_devices.json` dosyasında atomik `.tmp` + rename ile
/// yetkili cihaz kayıt defterini kalıcı saklayan depo (DB şemasını değiştirmez).
class FileDriveAuthorizedRegistryStore
    implements DriveAuthorizedRegistryStore {
  static const String defaultFileName = 'drive_authorized_devices.json';

  final File file;

  FileDriveAuthorizedRegistryStore({required this.file});

  factory FileDriveAuthorizedRegistryStore.inDirectory(Directory dataDir) {
    return FileDriveAuthorizedRegistryStore(
      file: File(p.join(dataDir.path, defaultFileName)),
    );
  }

  @override
  Future<DriveAuthorizedDeviceRegistry> load() async {
    try {
      if (!await file.exists()) {
        return DriveAuthorizedDeviceRegistry();
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return DriveAuthorizedDeviceRegistry();
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return DriveAuthorizedDeviceRegistry();
      }
      return DriveAuthorizedDeviceRegistry.fromJson(decoded);
    } catch (e) {
      debugPrint(
        '[FileDriveAuthorizedRegistryStore] Kayıt defteri okunamadı, boş başlanıyor: $e',
      );
      return DriveAuthorizedDeviceRegistry();
    }
  }

  @override
  Future<void> save(DriveAuthorizedDeviceRegistry registry) async {
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    final tmpFile = File('${file.path}.tmp');
    final encoded = const JsonEncoder.withIndent('  ').convert(registry.toJson());
    await tmpFile.writeAsString(encoded, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tmpFile.rename(file.path);
  }
}
