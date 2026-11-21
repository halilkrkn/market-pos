import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_setup_config_store.dart';
import '../domain/app_setup_config.dart';

/// Bekleyen (Hub'a gönderilmemiş) Outbox kayıtları varken cihaz/tenant/şube
/// kimliği değiştirilmeye çalışıldığında fırlatılır.
class PendingOutboxIdentityChangeException implements Exception {
  final int unsyncedCount;
  const PendingOutboxIdentityChangeException(this.unsyncedCount);

  String get message =>
      'Hub’a henüz gönderilmemiş $unsyncedCount işlem var. Cihaz, işletme veya şube kimliği '
      'değiştirilirse bu kayıtlar gönderilemez. Önce senkronizasyonun tamamlanmasını bekleyin.';

  @override
  String toString() => message;
}

/// Çoklu şube / tenant / cihaz ve TLS sabitleme kurulum durumunu yönetir.
class SetupConfigNotifier extends StateNotifier<AppSetupConfig> {
  final SetupConfigStore store;

  /// Verilen cihaz kimliğinin SYNCED olmayan Outbox kayıt sayısı (Faz 7A koruması).
  final Future<int> Function(String deviceId)? countUnsyncedOutbox;

  SetupConfigNotifier({
    required this.store,
    AppSetupConfig? initialState,
    this.countUnsyncedOutbox,
  }) : super(initialState ?? AppSetupConfig.initial());

  Future<void> reload() async {
    state = await store.load();
  }

  Future<AppSetupConfig> completeInitialSetup({
    required String tenantId,
    required String storeId,
    required String storeName,
    required String deviceId,
    required String deviceName,
  }) async {
    return updateStoreProfile(
      tenantId: tenantId,
      storeId: storeId,
      storeName: storeName,
      deviceId: deviceId,
      deviceName: deviceName,
      markCompleted: true,
    );
  }

  Future<AppSetupConfig> updateStoreProfile({
    required String tenantId,
    required String storeId,
    required String storeName,
    required String deviceId,
    required String deviceName,
    bool markCompleted = true,
  }) async {
    final cleanTenant = tenantId.trim();
    final cleanStore = storeId.trim();
    final cleanStoreName = storeName.trim();
    final cleanDevice = deviceId.trim();
    final cleanDeviceName = deviceName.trim();

    if (cleanTenant.isEmpty ||
        cleanStore.isEmpty ||
        cleanStoreName.isEmpty ||
        cleanDevice.isEmpty ||
        cleanDeviceName.isEmpty) {
      throw const FormatException(
        'İşletme (Tenant), Şube (Store) ve Cihaz alanları boş bırakılamaz.',
      );
    }

    final identityChanged = state.isSetupCompleted &&
        (cleanDevice != state.deviceId ||
            cleanTenant != state.tenantId ||
            cleanStore != state.storeId);
    final counter = countUnsyncedOutbox;
    if (identityChanged && counter != null) {
      final unsynced = await counter(state.deviceId);
      if (unsynced > 0) {
        throw PendingOutboxIdentityChangeException(unsynced);
      }
    }

    final next = state.copyWith(
      isSetupCompleted: markCompleted ? true : state.isSetupCompleted,
      tenantId: cleanTenant,
      storeId: cleanStore,
      storeName: cleanStoreName,
      deviceId: cleanDevice,
      deviceName: cleanDeviceName,
      updatedAt: DateTime.now().toUtc(),
    );
    await store.save(next);
    state = next;
    return next;
  }

  Future<AppSetupConfig> updateTlsPinning({
    required bool enabled,
    String? sha256Hex,
    String? caCertPem,
  }) async {
    final normalized =
        sha256Hex == null ? '' : AppSetupConfig.normalizeSha256Hex(sha256Hex);
    if (enabled &&
        (normalized.length != 64 ||
            !RegExp(r'^[0-9A-F]{64}$').hasMatch(normalized))) {
      throw const FormatException(
        'Sertifika sabitleme için geçerli 64 karakterli SHA-256 parmak izi girilmelidir.',
      );
    }

    final cleanPem = caCertPem?.trim();
    final next = state.copyWith(
      tlsPinningEnabled: enabled,
      pinnedCaSha256: normalized.isEmpty ? null : normalized,
      clearPinnedCaSha256: normalized.isEmpty,
      pinnedCaPem: (cleanPem == null || cleanPem.isEmpty) ? null : cleanPem,
      clearPinnedCaPem: cleanPem == null || cleanPem.isEmpty,
      updatedAt: DateTime.now().toUtc(),
    );
    await store.save(next);
    state = next;
    return next;
  }

  Future<AppSetupConfig> clearTlsPinning() async {
    final next = state.copyWith(
      tlsPinningEnabled: false,
      clearPinnedCaSha256: true,
      clearPinnedCaPem: true,
      updatedAt: DateTime.now().toUtc(),
    );
    await store.save(next);
    state = next;
    return next;
  }

  Future<AppSetupConfig> updateManifestUrl(String? url) async {
    final trimmed = url?.trim() ?? '';
    final next = state.copyWith(
      updateManifestUrl: trimmed.isEmpty ? null : trimmed,
      clearUpdateManifestUrl: trimmed.isEmpty,
      updatedAt: DateTime.now().toUtc(),
    );
    await store.save(next);
    state = next;
    return next;
  }

  Future<void> resetSetup() async {
    await store.clear();
    state = AppSetupConfig.initial();
  }
}
