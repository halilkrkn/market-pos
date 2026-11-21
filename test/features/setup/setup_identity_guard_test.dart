import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/features/setup/application/setup_config_notifier.dart';
import 'package:market_pos/features/setup/data/local_setup_config_store.dart';

/// Faz 7A §8.2: Bekleyen Outbox varken cihaz/tenant/şube kimliği değiştirilemez;
/// aksi halde eski cihaz kimliğiyle yazılmış kayıtlar bir daha gönderilmez.
void main() {
  late Map<String, int> unsynced;
  late SetupConfigNotifier notifier;

  setUp(() async {
    unsynced = {};
    notifier = SetupConfigNotifier(
      store: InMemorySetupConfigStore(),
      countUnsyncedOutbox: (deviceId) async => unsynced[deviceId] ?? 0,
    );
    await notifier.completeInitialSetup(
      tenantId: 'tenant-1',
      storeId: 'store-1',
      storeName: 'Merkez',
      deviceId: 'POS-1',
      deviceName: 'Kasa 1',
    );
  });

  tearDown(() => notifier.dispose());

  test('Bekleyen kayıt varken Device ID değişimi reddedilir ve durum korunur', () async {
    unsynced['POS-1'] = 3;
    await expectLater(
      notifier.updateStoreProfile(
        tenantId: 'tenant-1',
        storeId: 'store-1',
        storeName: 'Merkez',
        deviceId: 'POS-2',
        deviceName: 'Kasa 1',
      ),
      throwsA(isA<PendingOutboxIdentityChangeException>()),
    );
    expect(notifier.state.deviceId, 'POS-1');
  });

  test('Bekleyen kayıt varken tenant/şube değişimi de reddedilir', () async {
    unsynced['POS-1'] = 1;
    await expectLater(
      notifier.updateStoreProfile(
        tenantId: 'tenant-1',
        storeId: 'store-2',
        storeName: 'Merkez',
        deviceId: 'POS-1',
        deviceName: 'Kasa 1',
      ),
      throwsA(isA<PendingOutboxIdentityChangeException>()),
    );
  });

  test('Bekleyen kayıt varken yalnızca görünen ad değişebilir', () async {
    unsynced['POS-1'] = 1;
    final next = await notifier.updateStoreProfile(
      tenantId: 'tenant-1',
      storeId: 'store-1',
      storeName: 'Merkez Şube',
      deviceId: 'POS-1',
      deviceName: 'Ön Kasa',
    );
    expect(next.storeName, 'Merkez Şube');
    expect(next.deviceName, 'Ön Kasa');
  });

  test('Kuyruk boşsa Device ID değiştirilebilir', () async {
    final next = await notifier.updateStoreProfile(
      tenantId: 'tenant-1',
      storeId: 'store-1',
      storeName: 'Merkez',
      deviceId: 'POS-2',
      deviceName: 'Kasa 1',
    );
    expect(next.deviceId, 'POS-2');
  });
}
