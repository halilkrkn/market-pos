import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/core/security/secure_token_store.dart';
import 'package:market_pos/core/security/security_providers.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/features/backup/backup_providers.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';

void main() {
  test('BK-032: backupScheduleControllerProvider Drive upload hatalarını afterSuccess içinde yutmaz; yalnızca yerel cihaz yedeği yönetir', () {
    final localDb = LocalDatabaseService.forTesting(
      NativeDatabase.memory(),
      path: ':memory:',
    );
    addTearDown(() async {
      await localDb.close();
      await LocalDatabaseService.closeActive();
      LocalDatabaseService.resetForTesting();
    });

    final container = ProviderContainer(
      overrides: [
        localDatabaseServiceProvider.overrideWithValue(localDb),
        secureTokenStoreProvider.overrideWithValue(InMemorySecureTokenStore()),
        googleDriveUploaderProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(backupScheduleControllerProvider.notifier);
    expect(controller.afterSuccess, isNull);
  });
}
