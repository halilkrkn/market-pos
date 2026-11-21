import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../data/drive_authorized_registry_store.dart';

/// K-05 / ADR-021: Mağaza içi yetkili ve iptal edilmiş cihaz kayıt defteri yöneticisi.
class DriveAuthorizedRegistryNotifier
    extends StateNotifier<DriveAuthorizedDeviceRegistry> {
  final DriveAuthorizedRegistryStore store;

  DriveAuthorizedRegistryNotifier({
    required this.store,
    DriveAuthorizedDeviceRegistry? initialRegistry,
    required String localDeviceId,
    required String tenantId,
    required String storeId,
  }) : super(
          _buildEffectiveRegistry(
            initialRegistry?.all ?? const <DriveAuthorizedDevice>[],
            localDeviceId: localDeviceId,
            tenantId: tenantId,
            storeId: storeId,
          ),
        );

  static DriveAuthorizedDeviceRegistry _buildEffectiveRegistry(
    List<DriveAuthorizedDevice> devices, {
    required String localDeviceId,
    required String tenantId,
    required String storeId,
  }) {
    final scoped = devices
        .where((d) => d.tenantId == tenantId && d.storeId == storeId)
        .toList();
    final registry = DriveAuthorizedDeviceRegistry(scoped);

    final trimmedLocal = localDeviceId.trim();
    if (trimmedLocal.isNotEmpty && registry.find(trimmedLocal) == null) {
      // Yerel cihaz listede henüz yoksa başlangıç yerel çalışma için ACTIVE eklenir.
      // Hub tarafından açıkça REVOKED işaretlenmişse fail-closed REVOKED korunur.
      registry.authorizeDevice(
        deviceId: trimmedLocal,
        tenantId: tenantId,
        storeId: storeId,
      );
    }
    return registry;
  }

  static bool _isEquivalent(
    DriveAuthorizedDeviceRegistry a,
    DriveAuthorizedDeviceRegistry b,
  ) {
    final aDevices = a.all;
    final bDevices = b.all;
    if (aDevices.length != bDevices.length) return false;
    for (final devA in aDevices) {
      final devB = b.find(devA.deviceId);
      if (devB == null ||
          devB.tenantId != devA.tenantId ||
          devB.storeId != devA.storeId ||
          devB.status != devA.status) {
        return false;
      }
    }
    return true;
  }

  /// Hub'dan gelen yetkili/iptal edilmiş cihaz anlık görüntüsünü uygular ve kalıcı kaydeder.
  Future<void> applyHubSnapshot({
    required List<DriveAuthorizedDevice> devices,
    required String localDeviceId,
    required String tenantId,
    required String storeId,
  }) async {
    final next = _buildEffectiveRegistry(
      devices,
      localDeviceId: localDeviceId,
      tenantId: tenantId,
      storeId: storeId,
    );
    if (_isEquivalent(state, next)) {
      return;
    }
    if (!mounted) return;
    state = next;
    try {
      await store.save(next);
    } catch (e) {
      debugPrint(
        '[DriveAuthorizedRegistryNotifier] Cihaz kayıt defteri kaydedilemedi: $e',
      );
    }
  }
}
