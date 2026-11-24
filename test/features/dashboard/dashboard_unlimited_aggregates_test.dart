import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:market_pos/core/network/api_client.dart';
import 'package:market_pos/core/storage/local_database_service.dart';
import 'package:market_pos/features/dashboard/dashboard_providers.dart';
import 'package:market_pos/features/diagnostics/application/system_status_notifier.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

void main() {
  test('dashboardSnapshotProvider 500 ürün limitini aşan katalogta tüm ürünleri ve son kritik stokları doğru sayar', () async {
    final localDb = LocalDatabaseService.forTesting(
      NativeDatabase.memory(),
      path: ':memory:',
    );
    final apiClient = MmsApiClient(
      client: MockClient((_) async => http.Response('{"status":"UP"}', 200)),
      baseUrl: 'http://127.0.0.1:8945',
      deviceId: 'WIN-DASH-TEST',
    );
    addTearDown(() async {
      await localDb.close();
      await LocalDatabaseService.closeActive();
      LocalDatabaseService.resetForTesting();
    });

    final now = DateTime.now();
    await localDb.database.transaction(() async {
      for (var i = 0; i < 560; i++) {
        final isCriticalLate = i >= 550;
        await localDb.database.into(localDb.database.localProducts).insert(
              LocalProductsCompanion.insert(
                id: 'prod_dash_prov_$i',
                name: isCriticalLate
                    ? 'ZZZ Kritik ${i.toString().padLeft(4, '0')}'
                    : 'AAA Normal ${i.toString().padLeft(4, '0')}',
                barcode: Value('8699000${i.toString().padLeft(6, '0')}'),
                price: 1500,
                stock: isCriticalLate ? 0 : 25000,
                updatedAt: Value(now),
              ),
            );
      }
    });

    final container = ProviderContainer(
      overrides: [
        localDatabaseServiceProvider.overrideWithValue(localDb),
        apiClientProvider.overrideWithValue(apiClient),
      ],
    );
    addTearDown(container.dispose);

    // Başlangıç arka plan durum yenilemesinin tamamlanmasını bekle (provider dispose yarışı olmadan)
    container.read(systemStatusProvider);
    await container.read(systemStatusProvider.notifier).refreshStatus();

    final snapshot = await container.read(dashboardSnapshotProvider.future);
    expect(snapshot.activeProductCount, equals(560));
    expect(snapshot.criticalStockCount, equals(10));
    expect(snapshot.criticalProducts.length, equals(8));
    expect(snapshot.criticalProducts.every((p) => p.stock == 0), isTrue);
  });
}
